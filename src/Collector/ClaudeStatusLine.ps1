param(
    [string]$DataDirectory = $PSScriptRoot,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuotaData.ps1')

$inputReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
try { $payload = $inputReader.ReadToEnd() }
finally { $inputReader.Dispose() }
if ([string]::IsNullOrWhiteSpace($payload)) { return }
try { $status = ConvertFrom-Json -InputObject $payload }
catch { return }

$observedAt = [DateTimeOffset]::UtcNow
$snapshot = @{ observed_at = $observedAt.ToString('o', $invariantCulture) }
$summary = foreach ($period in $QuotaPeriods) {
    $statusWindow = $status.rate_limits.($period.StatusLineField)
    $resetAt = ConvertFrom-UnixSeconds $statusWindow.resets_at
    $quota = ConvertTo-QuotaWindow $statusWindow.used_percentage $resetAt
    if ($quota) {
        $quota.observed_at = $snapshot.observed_at
        $snapshot[$period.StatusLineField] = $quota
        '{0}: {1}%' -f $period.DisplayLabel, $quota.percent
    }
}
if (!$summary) { return }
if (!$Quiet) { $summary -join ' | ' }

try {
    $DataDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDirectory)
    [IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
    $writerLock = Open-QuotaWriterLock (Join-Path $DataDirectory 'claude-usage.lock')
    if (!$writerLock) { return }
    try {
        $snapshotPath = Join-Path $DataDirectory 'claude-usage.json'
        $previous = $null
        try { $previous = Read-QuotaJson $snapshotPath }
        catch { }
        $previousSnapshotTime = ConvertTo-QuotaTimestamp $previous.observed_at
        if ($previousSnapshotTime -gt $observedAt) {
            $snapshot.observed_at = $previousSnapshotTime.ToString('o', $invariantCulture)
        }
        foreach ($period in $QuotaPeriods) {
            $field = $period.StatusLineField
            $previousWindow = $previous.$field
            $previousWindowTime = ConvertTo-QuotaTimestamp $previousWindow.observed_at
            if (!$previousWindowTime) { $previousWindowTime = $previousSnapshotTime }
            if (!$previousWindow -or !$previousWindowTime -or
                ($snapshot[$field] -and $previousWindowTime -le $observedAt)) { continue }

            $savedWindow = ConvertTo-QuotaWindow $previousWindow.percent $previousWindow.reset
            if ($savedWindow) {
                $savedWindow.observed_at = $previousWindowTime.ToString('o', $invariantCulture)
                $snapshot[$field] = $savedWindow
            }
        }
        Write-QuotaJson $snapshotPath $snapshot
    }
    finally { $writerLock.Dispose() }
} catch [IO.IOException] { Write-Warning 'AgentMeter could not save the Claude Code quota snapshot.' }
catch [UnauthorizedAccessException] { Write-Warning 'AgentMeter could not save the Claude Code quota snapshot.' }
