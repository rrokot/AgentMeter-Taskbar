function Get-AgentMeterStatusLineCommand([ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$PublisherVersion, [hashtable]$Layout) {
    # Claude Code uses Git Bash or PowerShell on Windows. The space in the executable name
    # keeps the path quoted when either shell forwards it to cmd for LOCALAPPDATA expansion.
    $publisher = '"%LOCALAPPDATA%/{0}/{1}"' -f $Layout.DirectoryName, ($Layout.CollectorFileName -f $PublisherVersion)
    'cmd.exe /d/v:off/c if exist ' + $publisher + ' ' + $publisher + ' claude-status'
}

function Set-AgentMeterClaudeConnection($SettingsPath, $PublisherVersion, [hashtable]$Layout, [switch]$Remove, $PreviousPublisherVersion) {
    $statusLineCommand = Get-AgentMeterStatusLineCommand $PublisherVersion $Layout
    $previousJson = $null
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $SettingsPath) {
        $previousJson = [IO.File]::ReadAllText($SettingsPath)
        $settings = ConvertFrom-Json -InputObject $previousJson
        if ($settings -isnot [pscustomobject]) { return $false }
    }

    $existing = $settings.PSObject.Properties['statusLine']
    $previousCommand = if ($PreviousPublisherVersion) { Get-AgentMeterStatusLineCommand $PreviousPublisherVersion $Layout }
    $existingCommand = if ($existing -and $existing.Value.type -eq 'command') { $existing.Value.command }
    if ($Remove) {
        if ($existingCommand -cne $statusLineCommand) { return $false }
        $settings.PSObject.Properties.Remove('statusLine')
    } elseif ($existing) {
        if ($existingCommand -ceq $statusLineCommand) { return $true }
        if (!$previousCommand -or $existingCommand -cne $previousCommand) { return $false }
        $existing.Value.command = $statusLineCommand
    } else {
        $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue @{
            type = 'command'
            command = $statusLineCommand
        }
    }

    $directory = Split-Path -Parent $SettingsPath
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $stagedPath = Join-Path $directory ('agentmeter-settings-' + [guid]::NewGuid().ToString('N') + '.pending')
    try {
        $json = ConvertTo-Json -InputObject $settings -Depth 100
        [IO.File]::WriteAllText($stagedPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if ($null -eq $previousJson) {
            [IO.File]::Move($stagedPath, $SettingsPath)
        } else {
            if ([IO.File]::ReadAllText($SettingsPath) -cne $previousJson) { return $false }
            [IO.File]::Replace($stagedPath, $SettingsPath, [NullString]::Value)
        }
        return $true
    } finally { [IO.File]::Delete($stagedPath) }
}
