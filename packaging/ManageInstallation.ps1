param(
    [Parameter(Mandatory)][ValidateSet('Install', 'Uninstall')][string]$Operation,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$ProductVersion
)

$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar'
if ($PSScriptRoot -ne $installDirectory -or
    (Get-Item -LiteralPath $installDirectory -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
    throw 'Unexpected AgentMeter Taskbar installation directory.'
}

$user = [Security.Principal.WindowsIdentity]::GetCurrent()
$collectorTaskName = "AgentMeter Taskbar Collector ($($user.User.Value))"
$updateTaskName = "AgentMeter Taskbar Updates ($($user.User.Value))"
$taskPath = '\'
$productRegistryPath = 'HKCU:\Software\AgentMeterTaskbar'
$toolbarRegistryPath = 'HKCU:\Software\Classes\CLSID\{EA143E8E-217B-4B86-925B-37EA04848915}'
$serverRegistryPath = Join-Path $toolbarRegistryPath 'InprocServer32'
$deskBandCategoryId = '{00021492-0000-0000-C000-000000000046}'
$collectorLauncher = Join-Path $installDirectory "AgentMeterCollector-$ProductVersion.exe"
$statusLine = Join-Path $installDirectory 'ClaudeStatusLine.ps1'
$managedClaudeSettings = (Get-ItemProperty -LiteralPath $productRegistryPath -Name ClaudeSettingsPath -ErrorAction SilentlyContinue).ClaudeSettingsPath
. (Join-Path $installDirectory 'ClaudeConnection.ps1')

function Remove-AgentMeterTask($TaskName) {
    if (Get-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -ErrorAction SilentlyContinue) {
        Disable-ScheduledTask -TaskName $TaskName -TaskPath $taskPath | Out-Null
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $taskPath -Confirm:$false
    }
}

if ($Operation -eq 'Uninstall') {
    Remove-AgentMeterTask $updateTaskName
    Remove-AgentMeterTask $collectorTaskName
    if ($managedClaudeSettings) {
        try { [void](Set-AgentMeterClaudeConnection $managedClaudeSettings $statusLine -Remove) }
        catch { Write-Warning 'Could not remove the AgentMeter status-line entry from Claude Code settings.' }
    }
    foreach ($registryPath in $toolbarRegistryPath, $productRegistryPath) {
        if (Test-Path -LiteralPath $registryPath) { Remove-Item -LiteralPath $registryPath -Recurse }
    }
    return
}

$toolbarDll = Join-Path $installDirectory "AgentMeterBand-$ProductVersion.dll"
$assemblyName = [Reflection.AssemblyName]::GetAssemblyName($toolbarDll).FullName
$previousServer = Get-ItemProperty -LiteralPath $serverRegistryPath -ErrorAction SilentlyContinue
$previousCollector = Get-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
$previousUpdater = Get-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
$principal = New-ScheduledTaskPrincipal -UserId $user.Name -LogonType Interactive -RunLevel Limited
$collectorChanged = $false
$previousCollectorXml = $null
$updaterAdded = $false

try {
    if (!$previousCollector -or $previousCollector.Actions.Execute -ne $collectorLauncher) {
        if ($previousCollector) {
            $previousCollectorXml = Export-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath
        }
        $action = New-ScheduledTaskAction -Execute $collectorLauncher -WorkingDirectory $installDirectory
        $interval = New-TimeSpan -Minutes 1
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Add($interval) -RepetitionInterval $interval
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 55)
        Register-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -Principal $principal -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        $collectorChanged = $true
    }

    if (!$previousUpdater) {
        $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $updater = Join-Path $installDirectory 'UpdateAgentMeter.ps1'
        $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $updater + '"'
        $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $installDirectory
        $triggers = @(
            New-ScheduledTaskTrigger -Daily -At '03:00'
            New-ScheduledTaskTrigger -AtLogOn -User $user.Name -RandomDelay (New-TimeSpan -Minutes 3)
        )
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -Principal $principal -Action $action -Trigger $triggers -Settings $settings | Out-Null
        $updaterAdded = $true
    }

    New-Item -Path $serverRegistryPath -Force | Out-Null
    Set-Item -LiteralPath $toolbarRegistryPath -Value 'AgentMeter Quotas'
    Set-Item -LiteralPath $serverRegistryPath -Value 'mscoree.dll'
    $comProperties = @{
        ThreadingModel = 'Apartment'
        Class = 'AgentMeterBand'
        Assembly = $assemblyName
        RuntimeVersion = 'v4.0.30319'
        CodeBase = ([uri]$toolbarDll).AbsoluteUri
    }
    foreach ($name in $comProperties.Keys) {
        Set-ItemProperty -LiteralPath $serverRegistryPath -Name $name -Value $comProperties[$name]
    }
    New-Item -Path "$toolbarRegistryPath\Implemented Categories\$deskBandCategoryId" -Force | Out-Null

    New-Item -Path $productRegistryPath -Force | Out-Null
    Set-ItemProperty -LiteralPath $productRegistryPath -Name Version -Value $ProductVersion
} catch {
    if ($previousServer.Assembly -and $previousServer.CodeBase) {
        Set-ItemProperty -LiteralPath $serverRegistryPath -Name Assembly -Value $previousServer.Assembly -ErrorAction SilentlyContinue
        Set-ItemProperty -LiteralPath $serverRegistryPath -Name CodeBase -Value $previousServer.CodeBase -ErrorAction SilentlyContinue
    } elseif (!$previousServer -and (Test-Path -LiteralPath $toolbarRegistryPath)) {
        Remove-Item -LiteralPath $toolbarRegistryPath -Recurse -ErrorAction SilentlyContinue
    }
    if ($updaterAdded) { Remove-AgentMeterTask $updateTaskName }
    if ($collectorChanged) {
        if ($previousCollectorXml) {
            Register-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -Xml $previousCollectorXml -Force | Out-Null
        } else { Remove-AgentMeterTask $collectorTaskName }
    }
    throw
}

try {
    $claudeDirectory = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    $settingsPath = if ($managedClaudeSettings -and (Test-Path -LiteralPath $managedClaudeSettings -PathType Leaf)) {
        $managedClaudeSettings
    } elseif (Test-Path -LiteralPath $claudeDirectory -PathType Container) {
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $claudeDirectory 'settings.json'))
    }
    if ($settingsPath -and (Set-AgentMeterClaudeConnection $settingsPath $statusLine)) {
        Set-ItemProperty -LiteralPath $productRegistryPath -Name ClaudeSettingsPath -Value $settingsPath
    }
} catch { Write-Warning 'Could not configure the Claude Code status line.' }

# A pre-release build used a shared task name. Migrate it only when it belongs to this user and installation.
$legacyTaskName = 'AgentMeter Taskbar Collector'
$legacyTask = Get-ScheduledTask -TaskName $legacyTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($legacyTask -and $legacyTask.Principal.UserId -in $user.Name, $user.User.Value -and
    $legacyTask.Actions.WorkingDirectory -eq $installDirectory) {
    try { Remove-AgentMeterTask $legacyTaskName }
    catch { Write-Warning 'Could not remove the previous AgentMeter collector task.' }
}
Remove-Item -LiteralPath (Join-Path $installDirectory 'RefreshQuota.vbs') -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $installDirectory 'claude-cache.json') -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $installDirectory -Filter 'AgentMeterBand-*.dll' -File |
    Where-Object { $_.FullName -ne $toolbarDll } |
    Remove-Item -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $installDirectory -Filter 'AgentMeterCollector-*.exe' -File |
    Where-Object { $_.FullName -ne $collectorLauncher } |
    Remove-Item -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
