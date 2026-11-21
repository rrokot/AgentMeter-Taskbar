. (Join-Path $PSScriptRoot '..\packaging\ClaudeConnection.ps1')

Describe 'Optional Claude Code setup' {
    It 'adds and removes the AgentMeter status line while preserving other settings' {
        $path = Join-Path $TestDrive 'settings.json'
        [IO.File]::WriteAllText($path, '{"permissions":{"allow":["Read"]}}')
        $publisher = 'C:\User Profile\AgentMeterTaskbar\ClaudeStatusLine.ps1'
        Set-AgentMeterClaudeConnection $path $publisher | Should Be $true
        $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        $settings.statusLine.command | Should Match '"C:/User Profile/AgentMeterTaskbar/ClaudeStatusLine.ps1"$'
        Set-AgentMeterClaudeConnection $path $publisher -Remove | Should Be $true
        $settings = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        $settings.statusLine | Should BeNullOrEmpty
        $settings.permissions.allow[0] | Should Be 'Read'
    }

    It 'keeps an existing custom status line intact during install and uninstall' {
        $path = Join-Path $TestDrive 'settings.json'
        $original = '{"statusLine":{"type":"command","command":"my-status"}}'
        [IO.File]::WriteAllText($path, $original)
        $publisher = 'C:\AgentMeterTaskbar\ClaudeStatusLine.ps1'
        Set-AgentMeterClaudeConnection $path $publisher | Should Be $false
        Set-AgentMeterClaudeConnection $path $publisher -Remove | Should Be $false
        [IO.File]::ReadAllText($path) | Should Be $original
    }
}
