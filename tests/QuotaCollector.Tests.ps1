function New-QuotaFixture {
    $directory = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    @{
        directory = $directory
        snapshot = Join-Path $directory 'data.json'
        statusLine = Join-Path $directory 'claude-usage.json'
        desktopHistory = Join-Path $directory 'plan-usage-history.json'
        codexHome = Join-Path $directory 'codex'
    }
}

function Write-FixtureText($Path, $Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-FixtureJson($Path, $Value) {
    Write-FixtureText $Path (ConvertTo-Json -Compress -Depth 6 $Value)
}

function Invoke-FixtureCollection($Fixture, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow) {
    $collect.Invoke($Fixture.directory, $Fixture.codexHome, $Fixture.desktopHistory, $Now)
    Get-Content -LiteralPath $Fixture.snapshot -Raw | ConvertFrom-Json
}

function New-CodexLogLine($Timestamp, $Primary, $Secondary, $LimitId) {
    $limits = @{}
    if ($Primary) { $limits.primary = $Primary }
    if ($Secondary) { $limits.secondary = $Secondary }
    if ($LimitId) { $limits.limit_id = $LimitId }
    ConvertTo-Json -Compress -Depth 6 @{
        timestamp = $Timestamp
        payload = @{ type = 'token_count'; rate_limits = $limits }
    }
}

function Invoke-FixtureStatusLine($Payload, $DataDirectory) {
    $publisher = Join-Path $DataDirectory 'AgentMeterCollector.exe'
    if (![IO.File]::Exists($publisher)) { [IO.File]::Copy($collectorExe, $publisher) }
    $startInfo = [Diagnostics.ProcessStartInfo]::new($publisher, 'claude-status')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Payload)
        $process.StandardInput.Close()
        if (!$process.WaitForExit(10000)) {
            $process.Kill()
            throw 'The status-line process timed out.'
        }
        if ($process.ExitCode -ne 0) { throw $errors.GetAwaiter().GetResult() }
        $output.GetAwaiter().GetResult().Trim()
    } finally { $process.Dispose() }
}

Describe 'Quota collector snapshots' {
    BeforeAll {
        $collectorExe = Join-Path $TestDrive 'AgentMeterCollector.exe'
        & (Join-Path $PSScriptRoot '..\build\Build-Collector.ps1') -OutputPath $collectorExe
        $collector = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($collectorExe))
        $collectionMethod = $collector.GetType('QuotaSnapshot', $true).GetMethod('Collect', [Reflection.BindingFlags]'Static, NonPublic')
        $collectionActionType = [Action[string, string, string, Nullable[DateTimeOffset]]]
        $collect = [Delegate]::CreateDelegate($collectionActionType, $collectionMethod)
        $now = [DateTimeOffset]::Parse('2026-11-22T11:45:00Z')
    }

    It 'collects quotas when launched as a standalone executable' {
        $fixture = New-QuotaFixture
        $fixtureExe = Join-Path $fixture.directory 'AgentMeterCollector.exe'
        [IO.File]::Copy($collectorExe, $fixtureExe)
        $logLine = New-CodexLogLine ([DateTimeOffset]::UtcNow.ToString('o')) @{ used_percent = 21 }
        Write-FixtureText (Join-Path $fixture.codexHome 'sessions\rollout-a.jsonl') $logLine

        $startInfo = [Diagnostics.ProcessStartInfo]::new($fixtureExe)
        $startInfo.UseShellExecute = $false
        $startInfo.EnvironmentVariables['CODEX_HOME'] = $fixture.codexHome
        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            if (!$process.WaitForExit(10000)) {
                $process.Kill()
                throw 'The quota collector timed out.'
            }
            $process.ExitCode | Should Be 0
        } finally { $process.Dispose() }
        $output = Get-Content -LiteralPath $fixture.snapshot -Raw | ConvertFrom-Json
        $output.codex_five_hour_pct | Should Be '21'
    }

    It 'reports missing sources using the toolbar fields' {
        $output = Invoke-FixtureCollection (New-QuotaFixture) $now
        $output.updated_at | Should Be ($now.ToString('o'))
        $output.codex_status | Should Be 'error'
        $output.codex_msg | Should Match 'Start a Codex'
        $output.codex_five_hour_pct | Should Be ''
        $output.codex_weekly_reset_at | Should Be ''
        $output.claude_status | Should Be 'error'
        $output.claude_msg | Should Match 'Open Usage in Claude Desktop'
    }

    It 'uses the newest Codex event across logs and skips malformed lines' {
        $fixture = New-QuotaFixture
        $resetAt = $now.AddHours(3)
        $older = New-CodexLogLine ($now.AddMinutes(-5).ToString('o')) @{ used_percent = 10; window_minutes = 300 }
        $newer = New-CodexLogLine ($now.ToString('o')) @{ used_percent = '55.9'; window_minutes = 300; resets_at = $resetAt.ToUnixTimeSeconds() } @{ used_percent = 150; window_minutes = 10080 }
        Write-FixtureText (Join-Path $fixture.codexHome 'sessions\2026\rollout-a.jsonl') $newer
        Write-FixtureText (Join-Path $fixture.codexHome 'sessions\2026\rollout-b.jsonl') ('corrupt "rate_limits"' + [Environment]::NewLine + $older)
        $output = Invoke-FixtureCollection $fixture $now
        $output.codex_status | Should Be 'ok'
        $output.codex_five_hour_pct | Should Be '55'
        $output.codex_five_hour_reset_at | Should Be ($resetAt.ToString('o'))
        $output.codex_weekly_pct | Should Be '100'
        $output.codex_weekly_reset_at | Should Be ''
    }

    It 'maps Codex limits by duration, ignores other products, and hides a limit at reset' {
        $fixture = New-QuotaFixture
        $weekly = New-CodexLogLine ($now.AddMinutes(-1).ToString('o')) @{ used_percent = 90; window_minutes = 10080; resets_at = $now.ToUnixTimeSeconds() }
        $otherProduct = New-CodexLogLine ($now.ToString('o')) @{ used_percent = 12; window_minutes = 300 } $null 'other'
        Write-FixtureText (Join-Path $fixture.codexHome 'sessions\rollout-a.jsonl') ($weekly + [Environment]::NewLine + $otherProduct)
        $output = Invoke-FixtureCollection $fixture $now
        $output.codex_status | Should Be 'ok'
        $output.codex_five_hour_pct | Should Be ''
        $output.codex_five_hour_reset_at | Should Be ''
        $output.codex_weekly_pct | Should Be ''
        $output.codex_weekly_reset_at | Should Be ($now.ToString('o'))
        (Invoke-FixtureCollection $fixture $now.AddSeconds(-1)).codex_weekly_pct | Should Be '90'
    }

    It 'rejects invalid usage and treats invalid reset values as unknown' {
        $fixture = New-QuotaFixture
        $logLine = New-CodexLogLine ($now.ToString('o')) @{ used_percent = -1 } @{ used_percent = 12; resets_at = 'later' }
        Write-FixtureText (Join-Path $fixture.codexHome 'sessions\rollout-a.jsonl') $logLine
        $output = Invoke-FixtureCollection $fixture $now
        $output.codex_five_hour_pct | Should Be ''
        $output.codex_weekly_pct | Should Be '12'
        $output.codex_weekly_reset_at | Should Be ''
    }

    It 'publishes only quota data from Claude Code and preserves a missing period on partial updates' {
        $fixture = New-QuotaFixture
        $reset = $now.AddYears(50).ToUnixTimeSeconds()
        $payload = @{
            session_id = 'private-session-field'
            model = @{ display_name = 'Private model context' }
            rate_limits = @{
                five_hour = @{ used_percentage = 14.6; resets_at = $reset }
                seven_day = @{ used_percentage = 0 }
                spend_limit = @{ used_percentage = 33 }
            }
        } | ConvertTo-Json -Depth 5
        Invoke-FixtureStatusLine $payload $fixture.directory | Should Be '5h: 14% | 7d: 0%'
        $statusLine = Get-Content -LiteralPath $fixture.statusLine -Raw | ConvertFrom-Json
        @($statusLine.PSObject.Properties.Name).Count | Should Be 2
        $output = Invoke-FixtureCollection $fixture
        $output.claude_five_hour_pct | Should Be '14'
        $output.claude_five_hour_reset_at | Should Be ([DateTimeOffset]::FromUnixTimeSeconds($reset).ToString('o'))
        $output.claude_weekly_pct | Should Be '0'
        $output.claude_weekly_reset_at | Should Be ''

        Invoke-FixtureStatusLine '{"rate_limits":{"seven_day":{"used_percentage":37}}}' $fixture.directory | Should Be '7d: 37%'
        Invoke-FixtureStatusLine '{"rate_limits":{"spend_limit":{"used_percentage":50}}}' $fixture.directory | Should BeNullOrEmpty
        $output = Invoke-FixtureCollection $fixture
        $output.claude_five_hour_pct | Should Be '14'
        $output.claude_five_hour_observed_at | Should Be $statusLine.five_hour.observed_at
        $output.claude_weekly_pct | Should Be '37'
    }

    It 'accepts a UTF-8 preamble and preserves the untouched Claude Code period' {
        $fixture = New-QuotaFixture
        $previousTime = [DateTimeOffset]::UtcNow.AddMinutes(-20)
        Write-FixtureJson $fixture.statusLine @{
            five_hour = @{ percent = 14; observed_at = $previousTime.ToString('o') }
        }
        $originalInputEncoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = [Text.UTF8Encoding]::new($true)
            Invoke-FixtureStatusLine '{"rate_limits":{"seven_day":{"used_percentage":37}}}' $fixture.directory | Should Be '7d: 37%'
        } finally { [Console]::InputEncoding = $originalInputEncoding }
        $output = Invoke-FixtureCollection $fixture
        $output.claude_five_hour_pct | Should Be ''
        $output.claude_five_hour_last_pct | Should Be '14'
        $output.claude_five_hour_observed_at | Should Be ($previousTime.ToString('o'))
        $output.claude_weekly_pct | Should Be '37'
    }

    It 'uses the latest non-future Desktop sample and keeps zero usage' {
        $fixture = New-QuotaFixture
        Write-FixtureJson $fixture.desktopHistory @{ version = 2; samples = @(
            @{ t = $now.AddMinutes(-1).ToUnixTimeMilliseconds(); u = @{ fh = 2; sd = 0; xu = 25 } }
            @{ t = $now.AddMinutes(-5).ToUnixTimeMilliseconds(); u = @{ fh = 50; sd = 60 } }
            @{ t = $now.AddMinutes(5).ToUnixTimeMilliseconds(); u = @{ fh = 80; sd = 90 } }
        ) }
        $output = Invoke-FixtureCollection $fixture $now
        $output.claude_status | Should Be 'ok'
        $output.claude_five_hour_pct | Should Be '2'
        $output.claude_weekly_pct | Should Be '0'
        $output.claude_five_hour_reset_at | Should Be ''
    }

    It 'marks Desktop samples stale after 15 minutes and ignores unknown history formats' {
        $fixture = New-QuotaFixture
        $oldSample = @{ t = $now.AddMinutes(-16).ToUnixTimeMilliseconds(); u = @{ fh = 10 } }
        Write-FixtureJson $fixture.desktopHistory @{ version = 2; samples = @($oldSample) }
        $output = Invoke-FixtureCollection $fixture $now
        $output.claude_five_hour_pct | Should Be ''
        $output.claude_five_hour_last_pct | Should Be '10'

        $recentSample = @{ t = $now.AddMinutes(-1).ToUnixTimeMilliseconds(); u = @{ fh = 20 } }
        Write-FixtureJson $fixture.desktopHistory @{ version = 3; samples = @($recentSample) }
        (Invoke-FixtureCollection $fixture $now).claude_five_hour_last_pct | Should Be '10'
    }

    It 'prefers current Claude Code periods and falls back to Desktop or the previous snapshot' {
        $fixture = New-QuotaFixture
        $sample = @{ t = $now.AddMinutes(-1).ToUnixTimeMilliseconds(); u = @{ fh = 12; sd = 34 } }
        Write-FixtureJson $fixture.desktopHistory @{ version = 2; samples = @($sample) }
        Write-FixtureJson $fixture.statusLine @{
            five_hour = @{
                percent = 25
                observed_at = $now.AddMinutes(-10).ToString('o')
                reset = $now.AddHours(1).ToString('o')
            }
        }
        $output = Invoke-FixtureCollection $fixture $now
        $output.claude_five_hour_pct | Should Be '25'
        $output.claude_weekly_pct | Should Be '34'

        Write-FixtureText $fixture.statusLine '{'
        $output = Invoke-FixtureCollection $fixture $now
        $output.claude_five_hour_pct | Should Be '12'
        $output.claude_weekly_pct | Should Be '34'

        [IO.File]::Delete($fixture.desktopHistory)
        $output = Invoke-FixtureCollection $fixture $now.AddHours(2)
        $output.claude_five_hour_pct | Should Be ''
        $output.claude_five_hour_last_pct | Should Be '12'
        $output.claude_weekly_pct | Should Be ''
        $output.claude_weekly_last_pct | Should Be '34'
    }

    It 'keeps an expired Claude reset and honors its original time zone offset' {
        $fixture = New-QuotaFixture
        $resetAt = $now.ToOffset([TimeSpan]::FromHours(2))
        $observedAt = $now.AddHours(-3).ToString('o')
        Write-FixtureJson $fixture.statusLine @{
            five_hour = @{ percent = 76; reset = $resetAt.ToString('o'); observed_at = $observedAt }
            seven_day = @{ percent = 25; reset = $now.AddDays(5).ToString('o'); observed_at = $observedAt }
        }
        $output = Invoke-FixtureCollection $fixture $now
        $output.claude_five_hour_pct | Should Be ''
        $output.claude_five_hour_last_pct | Should Be '76'
        $output.claude_five_hour_reset_at | Should Be ($resetAt.ToString('o'))
        $output.claude_weekly_pct | Should Be '25'
    }

    It 'leaves the snapshot intact while another collector holds the writer lock' {
        $fixture = New-QuotaFixture
        Write-FixtureJson $fixture.snapshot @{ updated_at = $now.ToString('o') }
        $lock = [IO.File]::Open((Join-Path $fixture.directory 'collector.lock'), 'OpenOrCreate', 'Write', 'None')
        try {
            $output = Invoke-FixtureCollection $fixture $now.AddMinutes(1)
            $output.updated_at | Should Be ($now.ToString('o'))
        } finally { $lock.Dispose() }
        $output = Invoke-FixtureCollection $fixture $now.AddMinutes(1)
        $output.updated_at | Should Be ($now.AddMinutes(1).ToString('o'))
    }
}
