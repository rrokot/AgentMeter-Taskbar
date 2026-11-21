function Set-AgentMeterClaudeConnection($SettingsPath, $StatusLinePath, [switch]$Remove) {
    $statusLineCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
        $StatusLinePath.Replace('\', '/') + '"'
    $previousJson = $null
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $SettingsPath) {
        $previousJson = [IO.File]::ReadAllText($SettingsPath)
        $settings = ConvertFrom-Json -InputObject $previousJson
        if ($settings -isnot [pscustomobject]) { return $false }
    }

    $existing = $settings.PSObject.Properties['statusLine']
    $isAgentMeter = $existing -and $existing.Value.type -eq 'command' -and
        $existing.Value.command -ceq $statusLineCommand
    if ($Remove) {
        if (!$isAgentMeter) { return $false }
        $settings.PSObject.Properties.Remove('statusLine')
    } else {
        if ($existing) { return [bool]$isAgentMeter }
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
