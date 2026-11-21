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
$summary = foreach ($period in $ClaudeQuotaPeriods) {
    $statusWindow = $status.rate_limits.($period.Field)
    $resetAt = ConvertFrom-UnixTime $statusWindow.resets_at
    $quota = ConvertTo-QuotaWindow $statusWindow.used_percentage $resetAt
    if ($quota) {
        $snapshot[$period.Field] = $quota
        '{0}: {1}%' -f $period.Label, $quota.percent
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
        $previousObservation = $null
        try { $previousObservation = ConvertTo-QuotaDate (Read-QuotaJson $snapshotPath).observed_at }
        catch { }
        if (!$previousObservation -or $observedAt -ge $previousObservation) {
            Write-QuotaJson $snapshotPath $snapshot
        }
    }
    finally { $writerLock.Dispose() }
} catch [IO.IOException] { Write-Warning 'AgentMeter could not save the Claude Code quota snapshot.' }
catch [UnauthorizedAccessException] { Write-Warning 'AgentMeter could not save the Claude Code quota snapshot.' }
