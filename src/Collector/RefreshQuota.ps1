param([string]$DataDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuotaData.ps1')

$maximumClaudeQuotaAgeWithoutReset = [TimeSpan]::FromMinutes(15)

function Read-CodexSessionQuotaWindows {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $recentSessionLogCount = 10
    $sessionLogs = Get-ChildItem -LiteralPath (Join-Path $codexHome 'sessions') -Filter 'rollout-*.jsonl' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First $recentSessionLogCount
    $latestLimitTimestamp = [DateTimeOffset]::MinValue
    $latestQuotaWindows = @{}
    foreach ($sessionLog in $sessionLogs) {
        try {
            $stream = [IO.File]::Open($sessionLog.FullName, 'Open', 'Read', 'ReadWrite, Delete')
            $reader = [IO.StreamReader]::new($stream)
            try {
                while ($null -ne ($logLine = $reader.ReadLine())) {
                    if (!$logLine.Contains('"rate_limits"')) { continue }
                    try { $record = ConvertFrom-Json -InputObject $logLine }
                    catch { continue }
                    $rateLimits = $record.payload.rate_limits
                    if (!$rateLimits -or ($rateLimits.limit_id -and $rateLimits.limit_id -ne 'codex') -or
                        ($record.payload.type -and $record.payload.type -ne 'token_count')) { continue }

                    $recordTimestamp = ConvertTo-QuotaTimestamp $record.timestamp
                    if (!$recordTimestamp) { $recordTimestamp = [DateTimeOffset]$sessionLog.LastWriteTimeUtc }
                    if ($recordTimestamp -lt $latestLimitTimestamp) { continue }

                    $quotaWindows = @{}
                    foreach ($windowSlot in 'primary', 'secondary') {
                        $rawWindow = $rateLimits.$windowSlot
                        $periodName = switch ([string]$rawWindow.window_minutes) {
                            '300' { 'FiveHour' }
                            '10080' { 'Weekly' }
                            '' { if ($windowSlot -eq 'primary') { 'FiveHour' } else { 'Weekly' } }
                        }
                        if ($periodName) {
                            $resetAt = ConvertFrom-UnixSeconds $rawWindow.resets_at
                            $quotaWindow = ConvertTo-QuotaWindow $rawWindow.used_percent $resetAt
                            if ($quotaWindow) { $quotaWindows[$periodName] = $quotaWindow }
                        }
                    }
                    if ($quotaWindows.Count) {
                        $latestQuotaWindows = $quotaWindows
                        $latestLimitTimestamp = $recordTimestamp
                    }
                }
            } finally { $reader.Dispose() }
        } catch [IO.IOException] {
            # A session can disappear or become unreadable while Codex is writing its logs.
        } catch [UnauthorizedAccessException] {
            # Other session files may still contain valid data.
        }
    }
    return $latestQuotaWindows
}

function ConvertTo-ClaudeQuotaObservation($Percent, $Reset, [DateTimeOffset]$ObservedAt) {
    $quota = ConvertTo-QuotaWindow $Percent $Reset
    if (!$quota) { return }
    $quota.observedAt = $ObservedAt
    $quota.freshUntil = if ($quota.reset) { ConvertTo-QuotaTimestamp $quota.reset } else { $ObservedAt + $maximumClaudeQuotaAgeWithoutReset }
    return $quota
}

function Read-ClaudeStatusLineQuotaWindows($SnapshotPath, [DateTimeOffset]$Now) {
    $result = @{
        windowsByPeriod = @{}
        message = 'Open Usage in Claude Desktop or enable the AgentMeter status line in Claude Code.'
    }
    if (!(Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { return $result }

    $snapshot = Read-QuotaJson $SnapshotPath
    $snapshotTime = ConvertTo-QuotaTimestamp $snapshot.observed_at
    $result.message = 'Waiting for current Claude usage. Open Usage in Claude Desktop or run a turn in Claude Code.'
    foreach ($period in $QuotaPeriods) {
        $rawWindow = $snapshot.($period.StatusLineField)
        $observedAt = ConvertTo-QuotaTimestamp $rawWindow.observed_at
        if (!$observedAt) { $observedAt = $snapshotTime }
        if (!$observedAt -or $observedAt -gt $Now) { continue }
        $quotaWindow = ConvertTo-ClaudeQuotaObservation $rawWindow.percent $rawWindow.reset $observedAt
        if ($quotaWindow) { $result.windowsByPeriod[$period.Name] = $quotaWindow }
    }
    if ($result.windowsByPeriod.Count) { $result.message = '' }
    return $result
}

function Read-ClaudeDesktopQuotaWindows($HistoryPath, [DateTimeOffset]$Now) {
    if (!(Test-Path -LiteralPath $HistoryPath -PathType Leaf)) { return }
    $history = Read-QuotaJson $HistoryPath
    if ($history.version -ne 2 -or $history.samples -isnot [array]) { return }

    $nowUnixMilliseconds = $Now.ToUnixTimeMilliseconds()
    $newestSampleUnixMilliseconds = 1L
    $newestSample = $null
    foreach ($sample in $history.samples) {
        $sampleUnixMilliseconds = 0L
        if (![long]::TryParse([string]$sample.t, [ref]$sampleUnixMilliseconds) -or
            $sampleUnixMilliseconds -lt $newestSampleUnixMilliseconds -or $sampleUnixMilliseconds -gt $nowUnixMilliseconds) { continue }
        $newestSampleUnixMilliseconds = $sampleUnixMilliseconds
        $newestSample = $sample
    }
    if (!$newestSample) { return }

    # Desktop history stores percentages with no reset timestamps.
    $observedAt = [DateTimeOffset]::FromUnixTimeMilliseconds($newestSampleUnixMilliseconds)
    $fiveHour = ConvertTo-ClaudeQuotaObservation $newestSample.u.fh $null $observedAt
    $weekly = ConvertTo-ClaudeQuotaObservation $newestSample.u.sd $null $observedAt
    $windowsByPeriod = @{}
    if ($fiveHour) { $windowsByPeriod.FiveHour = $fiveHour }
    if ($weekly) { $windowsByPeriod.Weekly = $weekly }
    if ($windowsByPeriod.Count) { return $windowsByPeriod }
}

function Resolve-ClaudeQuotaWindows($StatusLinePath, $DesktopHistoryPath, [DateTimeOffset]$Now, $PreviousSnapshot) {
    try { $statusLine = Read-ClaudeStatusLineQuotaWindows $StatusLinePath $Now }
    catch { $statusLine = @{ windowsByPeriod = @{}; message = 'Claude Code status-line data could not be read.' } }
    try { $desktopWindows = Read-ClaudeDesktopQuotaWindows $DesktopHistoryPath $Now }
    catch { $desktopWindows = $null }

    $windowsByPeriod = @{}
    foreach ($period in $QuotaPeriods) {
        $periodKey = "claude_$($period.SnapshotSlot)"
        $savedObservation = ConvertTo-QuotaTimestamp $PreviousSnapshot.("${periodKey}_observed_at")
        $saved = if ($savedObservation -and $savedObservation -le $Now) {
            ConvertTo-ClaudeQuotaObservation $PreviousSnapshot.("${periodKey}_last_pct") $PreviousSnapshot.("${periodKey}_reset_at") $savedObservation
        }
        $desktopWindow = if ($desktopWindows) { $desktopWindows[$period.Name] }
        $observations = @($statusLine.windowsByPeriod[$period.Name], $desktopWindow, $saved) | Where-Object { $_ }
        $currentWindow = $observations | Where-Object { $_.freshUntil -gt $Now } | Select-Object -First 1
        $selectedWindow = if ($currentWindow) { $currentWindow } else {
            $observations | Sort-Object -Property @{ Expression = { $_.observedAt }; Descending = $true } | Select-Object -First 1
        }
        if ($selectedWindow) { $windowsByPeriod[$period.Name] = $selectedWindow }
    }
    return @{ windowsByPeriod = $windowsByPeriod; message = $statusLine.message }
}

function Add-ProviderQuotaFields($Snapshot, $ProviderKey, $WindowsByPeriod, $ProviderMessage, [DateTimeOffset]$Now) {
    $hasAnyLimits = $WindowsByPeriod.Count -gt 0
    $Snapshot["${ProviderKey}_status"] = if ($hasAnyLimits) { 'ok' } else { 'error' }
    $Snapshot["${ProviderKey}_msg"] = if ($hasAnyLimits) { '' } else { $ProviderMessage }
    foreach ($period in $QuotaPeriods) {
        $periodKey = "${ProviderKey}_$($period.SnapshotSlot)"
        $Snapshot["${periodKey}_label"] = $period.DisplayLabel
        $Snapshot["${periodKey}_pct"] = ''
        $quotaWindow = $WindowsByPeriod[$period.Name]
        $resetAt = if ($quotaWindow) { ConvertTo-QuotaTimestamp $quotaWindow.reset }
        $Snapshot["${periodKey}_reset_at"] = if ($resetAt) { $resetAt.ToString('o', $invariantCulture) } else { '' }
        $freshUntil = if ($quotaWindow) { $quotaWindow.freshUntil }
        if ($quotaWindow.observedAt) {
            $Snapshot["${periodKey}_last_pct"] = [string]$quotaWindow.percent
            $Snapshot["${periodKey}_observed_at"] = $quotaWindow.observedAt.ToString('o', $invariantCulture)
            $Snapshot["${periodKey}_fresh_until"] = $freshUntil.ToString('o', $invariantCulture)
        }
        if ($quotaWindow -and (!$resetAt -or $resetAt -gt $Now) -and (!$freshUntil -or $freshUntil -gt $Now)) {
            $Snapshot["${periodKey}_pct"] = [string]$quotaWindow.percent
        }
    }
}

# Dot-sourcing loads the functions only, so the tests can call them.
if ($MyInvocation.InvocationName -eq '.') { return }

$DataDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDirectory)
[IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
$collectorLock = Open-QuotaWriterLock (Join-Path $DataDirectory 'collector.lock')
if (!$collectorLock) { return }

try {
    $codexLimitsByPeriod = @{}
    $codexMessage = 'Start a Codex CLI session with a ChatGPT subscription to refresh usage.'
    try { $codexLimitsByPeriod = Read-CodexSessionQuotaWindows }
    catch { $codexMessage = 'Codex session logs could not be read.' }
    $now = [DateTimeOffset]::UtcNow
    $snapshotPath = Join-Path $DataDirectory 'data.json'
    $previousSnapshot = $null
    try { $previousSnapshot = Read-QuotaJson $snapshotPath }
    catch { }
    $desktopHistoryPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Claude\plan-usage-history.json'
    $claudeResult = Resolve-ClaudeQuotaWindows (Join-Path $DataDirectory 'claude-usage.json') $desktopHistoryPath $now $previousSnapshot

    $snapshot = @{ updated_at = $now.ToString('o', $invariantCulture) }
    Add-ProviderQuotaFields $snapshot 'codex' $codexLimitsByPeriod $codexMessage $now
    Add-ProviderQuotaFields $snapshot 'claude' $claudeResult.windowsByPeriod $claudeResult.message $now
    Write-QuotaJson $snapshotPath $snapshot
} finally {
    $collectorLock.Dispose()
}
