. (Join-Path $PSScriptRoot '..\packaging\ClaudeConnection.ps1')

Describe 'Optional Claude Code setup' {
    It 'adds and removes the AgentMeter status line while preserving other settings' {
        $path = Join-Path $TestDrive 'settings.json'
        [IO.File]::WriteAllText($path, '{"permissions":{"allow":["Read"]}}')
        $publisher = '0.2.7'
        Set-AgentMeterClaudeConnection $path $publisher | Should Be $true
        $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        $settings.statusLine.command | Should Match '"%LOCALAPPDATA%/AgentMeterTaskbar/AgentMeter Collector-0\.2\.7\.exe" claude-status$'
        Set-AgentMeterClaudeConnection $path $publisher -Remove | Should Be $true
        $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        $settings.statusLine | Should BeNullOrEmpty
        $settings.permissions.allow[0] | Should Be 'Read'
    }

    It 'keeps an existing custom status line intact during install and uninstall' {
        $path = Join-Path $TestDrive 'settings.json'
        $original = '{"statusLine":{"type":"command","command":"my-status"}}'
        [IO.File]::WriteAllText($path, $original)
        $publisher = '0.2.7'
        Set-AgentMeterClaudeConnection $path $publisher | Should Be $false
        Set-AgentMeterClaudeConnection $path $publisher -Remove | Should Be $false
        [IO.File]::ReadAllText($path) | Should Be $original
    }

    It 'updates a status line installed by AgentMeter to the new collector' {
        $path = Join-Path $TestDrive 'upgrade-settings.json'
        $previous = '0.2.7'
        $current = '0.2.8'
        Set-AgentMeterClaudeConnection $path $previous | Should Be $true
        Set-AgentMeterClaudeConnection $path $current -PreviousPublisherVersion $previous | Should Be $true
        $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        $settings.statusLine.command | Should Match '"%LOCALAPPDATA%/AgentMeterTaskbar/AgentMeter Collector-0\.2\.8\.exe" claude-status$'
    }

    It 'passes Claude input through the Windows shells with a quoted profile path' {
        $localAppData = Join-Path $TestDrive 'Profile %USERPROFILE% & $user'
        $appDirectory = Join-Path $localAppData 'AgentMeterTaskbar'
        [IO.Directory]::CreateDirectory($appDirectory) | Out-Null
        $publisher = Join-Path $appDirectory 'AgentMeter Collector-0.2.7.exe'
        & (Join-Path $PSScriptRoot '..\build\Build-Collector.ps1') -OutputPath $publisher

        $command = Get-AgentMeterStatusLineCommand '0.2.7'
        $powerShellScript = Join-Path $TestDrive 'status-line.ps1'
        [IO.File]::WriteAllText($powerShellScript, $command)
        $shells = @(
            [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'powershell.exe'),
                ('-NoProfile -ExecutionPolicy Bypass -File "' + $powerShellScript + '"'))
        )
        $gitBash = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
        if (Test-Path -LiteralPath $gitBash) {
            $bashScript = Join-Path $TestDrive 'status-line.sh'
            [IO.File]::WriteAllText($bashScript, $command + "`n")
            $shells += [Diagnostics.ProcessStartInfo]::new($gitBash, ('--noprofile --norc "' + $bashScript + '"'))
        }
        foreach ($shell in $shells) {
            $shell.UseShellExecute = $false
            $shell.CreateNoWindow = $true
            $shell.RedirectStandardInput = $true
            $shell.RedirectStandardOutput = $true
            $shell.EnvironmentVariables['LOCALAPPDATA'] = $localAppData
            $process = [Diagnostics.Process]::Start($shell)
            try {
                $output = $process.StandardOutput.ReadToEndAsync()
                $process.StandardInput.WriteLine('{"rate_limits":{"five_hour":{"used_percentage":14}}}')
                $process.StandardInput.Close()
                if (!$process.WaitForExit(10000)) {
                    $process.Kill()
                    throw "The status-line command timed out in $($shell.FileName)."
                }
                $process.ExitCode | Should Be 0
                $output.GetAwaiter().GetResult().Trim() | Should Be '5h: 14%'
            } finally { $process.Dispose() }
        }
    }
}
