param([string]$DataDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuotaData.ps1')

function Get-CodexLimits {
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

                    $recordTimestamp = ConvertTo-QuotaDate $record.timestamp
                    if (!$recordTimestamp) { $recordTimestamp = [DateTimeOffset]$sessionLog.LastWriteTimeUtc }
                    if ($recordTimestamp -lt $latestLimitTimestamp) { continue }

                    $quotaWindows = @{}
                    foreach ($windowSlot in 'primary', 'secondary') {
                        $rawWindow = $rateLimits.$windowSlot
                        $periodLabel = switch ([string]$rawWindow.window_minutes) {
                            '300' { '5h' }
                            '10080' { '7d' }
                            '' { if ($windowSlot -eq 'primary') { '5h' } else { '7d' } }
                        }
                        if ($periodLabel) {
                            $resetAt = ConvertFrom-UnixTime $rawWindow.resets_at
                            $quotaWindow = ConvertTo-QuotaWindow $rawWindow.used_percent $resetAt
                            if ($quotaWindow) { $quotaWindows[$periodLabel] = $quotaWindow }
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

function Get-ClaudeStatusLineLimits($SnapshotPath, [DateTimeOffset]$Now) {
    $result = @{
        limits = @($null, $null)
        message = 'Enable the AgentMeter status line in Claude Code and run a turn.'
    }
    if (!(Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { return $result }

    $snapshot = Read-QuotaJson $SnapshotPath
    $observedAt = ConvertTo-QuotaDate $snapshot.observed_at
    $result.message = 'Waiting for current Claude Code quota data. Run a turn to refresh.'
    if (!$observedAt -or $observedAt -gt $Now) { return $result }

    $maximumAgeWithoutReset = [TimeSpan]::FromMinutes(15)
    for ($index = 0; $index -lt $ClaudeQuotaPeriods.Count; $index++) {
        $period = $ClaudeQuotaPeriods[$index]
        $rawWindow = $snapshot.($period.Field)
        $quota = ConvertTo-QuotaWindow $rawWindow.percent $rawWindow.reset
        if (!$quota) { continue }
        $resetAt = ConvertTo-QuotaDate $quota.reset
        if ($resetAt -and $resetAt -le $Now) { continue }
        if (!$resetAt -and ($Now - $observedAt) -gt $maximumAgeWithoutReset) { continue }
        $result.limits[$index] = $quota
    }
    if ($result.limits[0] -or $result.limits[1]) { $result.message = '' }
    return $result
}

function Add-Limits($Output, $Provider, $Limits, $Message, $Now) {
    $periodLabels = @('5h', '7d')
    $hasAnyLimits = $Limits[0] -or $Limits[1]
    $Output["${Provider}_status"] = if ($hasAnyLimits) { 'ok' } else { 'error' }
    $Output["${Provider}_msg"] = if ($hasAnyLimits) { '' } else { $Message }
    for ($periodIndex = 0; $periodIndex -lt $periodLabels.Count; $periodIndex++) {
        $periodKey = "${Provider}_c$($periodIndex + 1)"
        $Output["${periodKey}_label"] = $periodLabels[$periodIndex]
        $Output["${periodKey}_pct"] = ''
        $quotaWindow = $Limits[$periodIndex]
        $resetAt = if ($quotaWindow) { ConvertTo-QuotaDate $quotaWindow.reset }
        $Output["${periodKey}_reset_at"] = if ($resetAt) { $resetAt.ToString('o', $invariantCulture) } else { '' }
        if ($quotaWindow -and (!$resetAt -or $resetAt -gt $Now)) {
            $Output["${periodKey}_pct"] = [string]$quotaWindow.percent
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
    try { $codexLimitsByPeriod = Get-CodexLimits }
    catch { $codexMessage = 'Codex session logs could not be read.' }
    $now = [DateTimeOffset]::UtcNow
    try { $claudeResult = Get-ClaudeStatusLineLimits (Join-Path $DataDirectory 'claude-usage.json') $now }
    catch { $claudeResult = @{ limits = @($null, $null); message = 'Claude Code status-line data could not be read.' } }

    $snapshot = @{ updated_at = $now.ToString('o', $invariantCulture) }
    Add-Limits $snapshot 'codex' @($codexLimitsByPeriod['5h'], $codexLimitsByPeriod['7d']) $codexMessage $now
    Add-Limits $snapshot 'claude' $claudeResult.limits $claudeResult.message $now
    Write-QuotaJson (Join-Path $DataDirectory 'data.json') $snapshot
} finally {
    $collectorLock.Dispose()
}
