$invariantCulture = [Globalization.CultureInfo]::InvariantCulture
$quotaDateStyles = [Globalization.DateTimeStyles]::AssumeUniversal

function Write-QuotaJson($Path, $Value) {
    $pendingPath = "$Path.pending"
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 6
        [IO.File]::WriteAllText($pendingPath, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($pendingPath, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($pendingPath, $Path)
        }
    } finally {
        [IO.File]::Delete($pendingPath)
    }
}

function ConvertTo-QuotaTimestamp($Value) {
    if ($Value -is [DateTimeOffset] -or $Value -is [DateTime]) {
        return [DateTimeOffset]$Value
    }
    $parsedDate = [DateTimeOffset]::MinValue
    if ($Value -and [DateTimeOffset]::TryParse([string]$Value, $invariantCulture, $quotaDateStyles, [ref]$parsedDate)) {
        return $parsedDate
    }
}

function ConvertFrom-UnixSeconds($Value) {
    $unixSeconds = 0L
    if ([long]::TryParse([string]$Value, [ref]$unixSeconds) -and $unixSeconds -gt 0 -and
        $unixSeconds -le [DateTimeOffset]::MaxValue.ToUnixTimeSeconds()) {
        return [DateTimeOffset]::FromUnixTimeSeconds($unixSeconds)
    }
}

function ConvertTo-QuotaWindow($Percent, $Reset) {
    $usagePercent = 0.0
    if ([double]::TryParse([string]$Percent, [Globalization.NumberStyles]::Float, $invariantCulture, [ref]$usagePercent) -and
        $usagePercent -ge 0 -and ![double]::IsInfinity($usagePercent)) {
        $resetAt = ConvertTo-QuotaTimestamp $Reset
        return @{
            percent = [int][Math]::Floor([Math]::Min(100.0, $usagePercent))
            reset = if ($resetAt) { $resetAt.ToString('o', $invariantCulture) } else { '' }
        }
    }
}

# Older toolbar DLLs use these snapshot slots while Explorer still has them loaded.
$QuotaPeriods = @(
    @{ Name = 'FiveHour'; StatusLineField = 'five_hour'; DisplayLabel = '5h'; SnapshotSlot = 'c1' }
    @{ Name = 'Weekly'; StatusLineField = 'seven_day'; DisplayLabel = '7d'; SnapshotSlot = 'c2' }
)

function Open-QuotaWriterLock($Path) {
    try {
        return [IO.FileStream]::new($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
    } catch [IO.IOException] {
        $sharingViolationHResult = 0x80070020
        if ($_.Exception.GetBaseException().HResult -ne $sharingViolationHResult) { throw }
    }
}

function Read-QuotaJson($Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        $maximumQuotaJsonBytes = 65536
        if ($stream.Length -gt $maximumQuotaJsonBytes) { throw 'Quota snapshot exceeds the size limit.' }
        $reader = [IO.StreamReader]::new($stream)
        try { return ConvertFrom-Json -InputObject $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
