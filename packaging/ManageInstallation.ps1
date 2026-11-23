param(
    [Parameter(Mandatory)][ValidateSet('Install', 'Uninstall')][string]$Operation,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$ProductVersion
)

$ErrorActionPreference = 'Stop'
$layout = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'InstallationLayout.psd1')
$installDirectory = Join-Path $env:LOCALAPPDATA $layout.DirectoryName
if ($PSScriptRoot -ne $installDirectory -or
    (Get-Item -LiteralPath $installDirectory -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
    throw 'Unexpected AgentMeter Taskbar installation directory.'
}

$user = [Security.Principal.WindowsIdentity]::GetCurrent()
$collectorTaskName = "AgentMeter Taskbar Collector ($($user.User.Value))"
$updateTaskName = "AgentMeter Taskbar Updates ($($user.User.Value))"
$taskPath = '\'
$productRegistryPath = Join-Path 'HKCU:\' $layout.RegistrySubKey
$versionValueName = $layout.RegistryVersionValueName
$toolbarRegistryPath = 'HKCU:\Software\Classes\CLSID\{EA143E8E-217B-4B86-925B-37EA04848915}'
$serverRegistryPath = Join-Path $toolbarRegistryPath 'InprocServer32'
$deskBandCategoryId = '{00021492-0000-0000-C000-000000000046}'
$collectorExe = Join-Path $installDirectory ($layout.CollectorFileName -f $ProductVersion)
$updaterExe = Join-Path $installDirectory ($layout.UpdaterFileName -f $ProductVersion)
$productRegistration = Get-ItemProperty -LiteralPath $productRegistryPath -ErrorAction SilentlyContinue
$managedClaudeSettings = $productRegistration.ClaudeSettingsPath
$managedClaudeVersion = $productRegistration.ClaudePublisherVersion
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
    if ($managedClaudeSettings -and $managedClaudeVersion) {
        try { [void](Set-AgentMeterClaudeConnection $managedClaudeSettings $managedClaudeVersion -Layout $layout -Remove) }
        catch { Write-Warning 'Could not remove the AgentMeter status-line entry from Claude Code settings.' }
    }
    foreach ($registryPath in $toolbarRegistryPath, $productRegistryPath) {
        if (Test-Path -LiteralPath $registryPath) { Remove-Item -LiteralPath $registryPath -Recurse }
    }
    return
}

$toolbarDll = Join-Path $installDirectory ($layout.ToolbarFileName -f $ProductVersion)
$assemblyName = [Reflection.AssemblyName]::GetAssemblyName($toolbarDll).FullName
$previousServer = Get-ItemProperty -LiteralPath $serverRegistryPath -ErrorAction SilentlyContinue
$previousCollector = Get-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
$previousUpdater = Get-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
$principal = New-ScheduledTaskPrincipal -UserId $user.Name -LogonType Interactive -RunLevel Limited
$collectorChanged = $false
$previousCollectorXml = $null
$updaterChanged = $false
$previousUpdaterXml = $null

try {
    if (!$previousCollector -or $previousCollector.Actions.Execute -ne $collectorExe) {
        if ($previousCollector) {
            $previousCollectorXml = Export-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath
        }
        $action = New-ScheduledTaskAction -Execute $collectorExe -WorkingDirectory $installDirectory
        $interval = New-TimeSpan -Minutes 1
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Add($interval) -RepetitionInterval $interval
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds 55)
        Register-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -Principal $principal -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
        $collectorChanged = $true
    }

    if (!$previousUpdater -or $previousUpdater.Actions.Execute -ne $updaterExe) {
        if ($previousUpdater) {
            $previousUpdaterXml = Export-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath
        }
        $action = New-ScheduledTaskAction -Execute $updaterExe -Argument 'automatic' -WorkingDirectory $installDirectory
        $triggers = @(
            New-ScheduledTaskTrigger -Daily -At '03:00'
            New-ScheduledTaskTrigger -AtLogOn -User $user.Name -RandomDelay (New-TimeSpan -Minutes 3)
        )
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -Principal $principal -Action $action -Trigger $triggers -Settings $settings -Force | Out-Null
        $updaterChanged = $true
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
    Set-ItemProperty -LiteralPath $productRegistryPath -Name $versionValueName -Value $ProductVersion
} catch {
    if ($previousServer.Assembly -and $previousServer.CodeBase) {
        Set-ItemProperty -LiteralPath $serverRegistryPath -Name Assembly -Value $previousServer.Assembly -ErrorAction SilentlyContinue
        Set-ItemProperty -LiteralPath $serverRegistryPath -Name CodeBase -Value $previousServer.CodeBase -ErrorAction SilentlyContinue
    } elseif (!$previousServer -and (Test-Path -LiteralPath $toolbarRegistryPath)) {
        Remove-Item -LiteralPath $toolbarRegistryPath -Recurse -ErrorAction SilentlyContinue
    }
    if ($updaterChanged) {
        if ($previousUpdaterXml) {
            Register-ScheduledTask -TaskName $updateTaskName -TaskPath $taskPath -Xml $previousUpdaterXml -Force | Out-Null
        } else { Remove-AgentMeterTask $updateTaskName }
    }
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
    if ($settingsPath -and (Set-AgentMeterClaudeConnection $settingsPath $ProductVersion -Layout $layout -PreviousPublisherVersion $managedClaudeVersion)) {
        Set-ItemProperty -LiteralPath $productRegistryPath -Name ClaudeSettingsPath -Value $settingsPath
        Set-ItemProperty -LiteralPath $productRegistryPath -Name ClaudePublisherVersion -Value $ProductVersion
        $managedClaudeVersion = $ProductVersion
    }
} catch { Write-Warning 'Could not configure the Claude Code status line.' }

Get-ChildItem -LiteralPath $installDirectory -Filter ($layout.ToolbarFileName -f '*') -File |
    Where-Object { $_.FullName -ne $toolbarDll } |
    Remove-Item -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $installDirectory -Filter ($layout.CollectorFileName -f '*') -File |
    Where-Object { $_.FullName -ne $collectorExe -and $_.Name -ne ($layout.CollectorFileName -f $managedClaudeVersion) } |
    Remove-Item -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $installDirectory -Filter ($layout.UpdaterFileName -f '*') -File |
    Where-Object { $_.FullName -ne $updaterExe } |
    Remove-Item -ErrorAction SilentlyContinue

if ($productRegistration.$versionValueName) {
    Start-ScheduledTask -TaskName $collectorTaskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    return
}

# Give Explorer a quota snapshot when it loads the toolbar after first-time setup.
try {
    $initialCollector = Start-Process -FilePath $collectorExe -WindowStyle Hidden -PassThru
    try {
        $initialCollectionTimeoutMilliseconds = 10000
        if (!$initialCollector.WaitForExit($initialCollectionTimeoutMilliseconds)) {
            if (!$initialCollector.HasExited) { $initialCollector.Kill() }
            Write-Warning 'Initial quota collection timed out. The scheduled collector will try again.'
        } elseif ($initialCollector.ExitCode -ne 0) {
            Write-Warning "Initial quota collection returned exit code $($initialCollector.ExitCode)."
        }
    } finally { $initialCollector.Dispose() }
} catch { Write-Warning 'Could not start the initial quota collection. The scheduled collector will try again.' }
