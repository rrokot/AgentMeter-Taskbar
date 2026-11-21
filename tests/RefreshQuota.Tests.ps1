# Written for Pester 3.4, the version bundled with Windows PowerShell 5.1.
. (Join-Path $PSScriptRoot '..\src\RefreshQuota.ps1')

function New-TestDirectory {
    $path = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function Write-TestTextFile($Path, $Text) {
    $parentDirectory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($parentDirectory) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-RelativeIsoTimestamp($HoursFromNow) {
    return [DateTimeOffset]::UtcNow.AddHours($HoursFromNow).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}

Describe 'ConvertTo-QuotaWindow' {
    It 'rounds the percentage down' {
        (ConvertTo-QuotaWindow '42.9' $null).percent | Should Be 42
    }
    It 'caps the percentage at 100' {
        (ConvertTo-QuotaWindow 150 $null).percent | Should Be 100
    }
    It 'rejects negative and non-numeric values' {
        ConvertTo-QuotaWindow -1 $null | Should BeNullOrEmpty
        ConvertTo-QuotaWindow 'abc' $null | Should BeNullOrEmpty
        ConvertTo-QuotaWindow $null $null | Should BeNullOrEmpty
    }
    It 'keeps a valid reset time and drops an invalid one' {
        (ConvertTo-QuotaWindow 5 '2030-01-02T03:04:05Z').reset | Should Be '2030-01-02T03:04:05.0000000+00:00'
        (ConvertTo-QuotaWindow 5 'soon').reset | Should Be ''
    }
}

Describe 'ConvertFrom-UnixTime' {
    It 'converts seconds since the epoch' {
        (ConvertFrom-UnixTime 1700000000).ToUnixTimeSeconds() | Should Be 1700000000
    }
    It 'rejects zero and text' {
        ConvertFrom-UnixTime 0 | Should BeNullOrEmpty
        ConvertFrom-UnixTime 'later' | Should BeNullOrEmpty
    }
}

Describe 'Add-Limits' {
    $now = [DateTimeOffset]::UtcNow

    It 'reports an error with the message when there is no data' {
        $output = @{}
        Add-Limits $output 'codex' @($null, $null) 'Start Codex.' $now
        $output.codex_status | Should Be 'error'
        $output.codex_msg | Should Be 'Start Codex.'
        $output.codex_c1_pct | Should Be ''
        $output.codex_c2_reset_at | Should Be ''
    }
    It 'publishes the reset timestamp for a running period' {
        $reset = $now.AddHours(2).ToOffset([TimeSpan]::FromHours(2))
        $output = @{}
        Add-Limits $output 'claude' @(@{ percent = 37; reset = $reset }, $null) 'ignored' $now
        $output.claude_status | Should Be 'ok'
        $output.claude_msg | Should Be ''
        $output.claude_c1_label | Should Be '5h'
        $output.claude_c1_pct | Should Be '37'
        $output.claude_c1_reset_at | Should Be ($reset.ToString('o'))
        $output.claude_c2_pct | Should Be ''
    }
    It 'keeps the timestamp but hides the percentage at the reset boundary' {
        $output = @{}
        Add-Limits $output 'codex' @($null, @{ percent = 90; reset = $now }) '' $now
        $output.codex_c2_pct | Should Be ''
        $output.codex_c2_reset_at | Should Be ($now.ToString('o'))
    }
    It 'keeps the percentage when the reset time is unknown' {
        $output = @{}
        Add-Limits $output 'codex' @(@{ percent = 12; reset = '' }, $null) '' $now
        $output.codex_c1_pct | Should Be '12'
        $output.codex_c1_reset_at | Should Be ''
    }
}

Describe 'Get-CodexLimits' {
    $previousCodexHome = $env:CODEX_HOME
    AfterEach { $env:CODEX_HOME = $previousCodexHome }

    function New-CodexRateLimitLogLine($Timestamp, $Primary, $Secondary, $LimitId) {
        $limits = @{}
        if ($Primary) { $limits.primary = $Primary }
        if ($Secondary) { $limits.secondary = $Secondary }
        if ($LimitId) { $limits.limit_id = $LimitId }
        return ConvertTo-Json -Compress -Depth 6 @{
            timestamp = $Timestamp
            payload = @{ type = 'token_count'; rate_limits = $limits }
        }
    }
    $reset = [DateTimeOffset]::UtcNow.AddHours(3).ToUnixTimeSeconds()

    It 'returns nothing when there are no session logs' {
        $env:CODEX_HOME = New-TestDirectory
        (Get-CodexLimits).Count | Should Be 0
    }
    It 'takes the record with the latest timestamp across files' {
        $env:CODEX_HOME = New-TestDirectory
        $olderLogLine = New-CodexRateLimitLogLine '2026-01-01T10:00:00Z' @{ used_percent = 10; window_minutes = 300; resets_at = $reset } @{ used_percent = 20; window_minutes = 10080; resets_at = $reset }
        $newerLogLine = New-CodexRateLimitLogLine '2026-01-01T12:00:00Z' @{ used_percent = 55; window_minutes = 300; resets_at = $reset } @{ used_percent = 66; window_minutes = 10080; resets_at = $reset }
        Write-TestTextFile (Join-Path $env:CODEX_HOME 'sessions\2026\rollout-a.jsonl') "$newerLogLine`n"
        Write-TestTextFile (Join-Path $env:CODEX_HOME 'sessions\2026\rollout-b.jsonl') "not json `"rate_limits`"`n$olderLogLine`n"
        $limits = Get-CodexLimits
        $limits['5h'].percent | Should Be 55
        $limits['7d'].percent | Should Be 66
        $limits['5h'].reset | Should Not BeNullOrEmpty
    }
    It 'labels a weekly limit in the primary slot by its window length' {
        $env:CODEX_HOME = New-TestDirectory
        $logLine = New-CodexRateLimitLogLine '2026-01-01T10:00:00Z' @{ used_percent = 30; window_minutes = 10080; resets_at = $reset } $null
        Write-TestTextFile (Join-Path $env:CODEX_HOME 'sessions\rollout-a.jsonl') "$logLine`n"
        $limits = Get-CodexLimits
        $limits.ContainsKey('5h') | Should Be $false
        $limits['7d'].percent | Should Be 30
    }
    It 'ignores limits that belong to another product' {
        $env:CODEX_HOME = New-TestDirectory
        $logLine = New-CodexRateLimitLogLine '2026-01-01T10:00:00Z' @{ used_percent = 30; window_minutes = 300; resets_at = $reset } $null 'other'
        Write-TestTextFile (Join-Path $env:CODEX_HOME 'sessions\rollout-a.jsonl') "$logLine`n"
        (Get-CodexLimits).Count | Should Be 0
    }
}

Describe 'Claude Code status-line quotas' {
    $publisherPath = Join-Path $PSScriptRoot '..\src\ClaudeStatusLine.ps1'

    It 'stores only quota fields and reports them on the next collection' {
        $dataDirectory = Join-Path (New-TestDirectory) 'taskbar data'
        $reset = [DateTimeOffset]::UtcNow.AddHours(4).ToUnixTimeSeconds()
        $payload = @{
            session_id = 'private-session-field'
            model = @{ display_name = 'Private model context' }
            rate_limits = @{
                five_hour = @{ used_percentage = 14.6; resets_at = $reset }
                seven_day = @{ used_percentage = 0 }
                spend_limit = @{ used_percentage = 33 }
            }
        } | ConvertTo-Json -Depth 5
        $line = $payload | & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $publisherPath -DataDirectory $dataDirectory
        $LASTEXITCODE | Should Be 0
        $line | Should Be '5h: 14% | 7d: 0%'

        $snapshotPath = Join-Path $dataDirectory 'claude-usage.json'
        $snapshot = Read-QuotaJson $snapshotPath
        @($snapshot.PSObject.Properties.Name).Count | Should Be 3
        $snapshot.five_hour.reset | Should Not BeNullOrEmpty
        $snapshot.seven_day.reset | Should Be ''
        $result = Get-ClaudeStatusLineLimits $snapshotPath ([DateTimeOffset]::UtcNow)
        $result.limits[0].percent | Should Be 14
        $result.limits[1].percent | Should Be 0
        $result.message | Should Be ''

        $replacement = '{"rate_limits":{"seven_day":{"used_percentage":37}}}'
        $line = $replacement | & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $publisherPath -DataDirectory $dataDirectory -Quiet
        $LASTEXITCODE | Should Be 0
        $line | Should BeNullOrEmpty
        (Read-QuotaJson $snapshotPath).seven_day.percent | Should Be 37
    }

    It 'keeps the last snapshot when a later payload lacks quota fields' {
        $dataDirectory = New-TestDirectory
        $snapshotPath = Join-Path $dataDirectory 'claude-usage.json'
        Write-QuotaJson $snapshotPath @{ five_hour = @{ percent = 10 } }
        '{"rate_limits":{"spend_limit":{"used_percentage":50}}}' |
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $publisherPath -DataDirectory $dataDirectory
        $LASTEXITCODE | Should Be 0
        (Read-QuotaJson $snapshotPath).five_hour.percent | Should Be 10
    }

    It 'waits for setup before a Claude session has supplied any limits' {
        $snapshotPath = Join-Path (New-TestDirectory) 'claude-usage.json'
        $result = Get-ClaudeStatusLineLimits $snapshotPath ([DateTimeOffset]::UtcNow)
        $result.limits[0] | Should BeNullOrEmpty
        $result.message | Should Match 'Enable the AgentMeter status line'
    }

    It 'expires each window at its own reset and drops old values without one' {
        $now = [DateTimeOffset]::Parse('2026-06-01T08:00:00Z')
        $snapshotPath = Join-Path (New-TestDirectory) 'claude-usage.json'
        Write-QuotaJson $snapshotPath @{
            observed_at = $now.AddHours(-3).ToString('o')
            five_hour = @{ percent = 76; reset = $now.ToString('o') }
            seven_day = @{ percent = 25; reset = $now.AddDays(5).ToString('o') }
        }
        $result = Get-ClaudeStatusLineLimits $snapshotPath $now
        $result.limits[0] | Should BeNullOrEmpty
        $result.limits[1].percent | Should Be 25

        Write-QuotaJson $snapshotPath @{
            observed_at = $now.AddMinutes(-16).ToString('o')
            five_hour = @{ percent = 47 }
        }
        $result = Get-ClaudeStatusLineLimits $snapshotPath $now
        $result.limits[0] | Should BeNullOrEmpty
        $result.message | Should Match 'Waiting for current Claude Code quota data'
    }
}
