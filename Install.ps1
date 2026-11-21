$ErrorActionPreference = 'Stop'

$minimumWindows11Build = 22000
if ($PSVersionTable.PSEdition -ne 'Desktop' -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -or
    [Environment]::OSVersion.Version.Build -lt $minimumWindows11Build) {
    throw 'Use 64-bit Windows PowerShell on Windows 11 x64.'
}

$startAllBack = Get-ItemProperty 'HKCU:\Software\StartIsBack' -ErrorAction SilentlyContinue
if ($null -eq $startAllBack -or $startAllBack.LegacyTaskbar -ne 1) {
    throw 'Enable the classic taskbar in StartAllBack before installing.'
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$collectorTaskName = "AgentMeter Taskbar Collector ($($currentUser.User.Value))"
$collectorTaskPath = '\'
$deskBandCategoryId = '{00021492-0000-0000-C000-000000000046}'
$toolbarClassId = '{EA143E8E-217B-4B86-925B-37EA04848915}'
$toolbarClassRegistryPath = "HKCU:\Software\Classes\CLSID\$toolbarClassId"
$inprocServerRegistryPath = Join-Path $toolbarClassRegistryPath 'InprocServer32'
$scriptHostPath = Join-Path $env:WINDIR 'System32\wscript.exe'

if (!(Test-Path -LiteralPath $scriptHostPath)) {
    throw 'Windows Script Host is unavailable.'
}

$isUpdate = Test-Path -LiteralPath $installDirectory
if ($isUpdate) {
    $resolvedInstallDirectory = (Resolve-Path -LiteralPath $installDirectory).Path
    if ($resolvedInstallDirectory -ne $installDirectory -or (Get-Item -LiteralPath $resolvedInstallDirectory -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected installation folder: $resolvedInstallDirectory"
    }
} else {
    New-Item -ItemType Directory -Path $installDirectory | Out-Null
}

# Explorer keeps the loaded toolbar DLL locked, so every build gets its own file and assembly name.
$toolbarDllPath = Join-Path $installDirectory ('AgentMeterBand-{0:yyyyMMddHHmmss}.dll' -f (Get-Date))
$previousServerRegistration = Get-ItemProperty -LiteralPath $inprocServerRegistryPath -ErrorAction SilentlyContinue
$toolbarWasRegistered = Test-Path -LiteralPath $toolbarClassRegistryPath
$collectorTaskAlreadyExists = [bool](Get-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath -ErrorAction SilentlyContinue)
try {
    $version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
    & (Join-Path $PSScriptRoot 'packaging\Build-Toolbar.ps1') -Version $version -OutputPath $toolbarDllPath
    foreach ($collectorFileName in 'QuotaData.ps1', 'ClaudeStatusLine.ps1', 'RefreshQuota.ps1', 'RefreshQuota.vbs') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "src\$collectorFileName") -Destination $installDirectory -Force
    }

    New-Item -Path $inprocServerRegistryPath -Force | Out-Null
    Set-Item -LiteralPath $toolbarClassRegistryPath -Value 'AgentMeter Quotas'
    Set-Item -LiteralPath $inprocServerRegistryPath -Value 'mscoree.dll'
    Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name ThreadingModel -Value Apartment
    Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name Class -Value AgentMeterBand
    Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name Assembly -Value ([Reflection.AssemblyName]::GetAssemblyName($toolbarDllPath).FullName)
    Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name RuntimeVersion -Value 'v4.0.30319'
    Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name CodeBase -Value ([uri]$toolbarDllPath).AbsoluteUri
    New-Item -Path "$toolbarClassRegistryPath\Implemented Categories\$deskBandCategoryId" -Force | Out-Null

    $collectorLauncherPath = Join-Path $installDirectory 'RefreshQuota.vbs'
    $collectorAction = New-ScheduledTaskAction -Execute $scriptHostPath -Argument ('//B //NoLogo "' + $collectorLauncherPath + '"') -WorkingDirectory $installDirectory
    $collectorInterval = New-TimeSpan -Minutes 1
    $firstCollectorRun = (Get-Date).Add($collectorInterval)
    $collectorTrigger = New-ScheduledTaskTrigger -Once -At $firstCollectorRun -RepetitionInterval $collectorInterval
    $collectorPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser.Name -LogonType Interactive -RunLevel Limited
    $collectorSettingsArguments = @{
        MultipleInstances = 'IgnoreNew'
        StartWhenAvailable = $true
        AllowStartIfOnBatteries = $true
        DontStopIfGoingOnBatteries = $true
        ExecutionTimeLimit = New-TimeSpan -Seconds 55
    }
    $collectorSettings = New-ScheduledTaskSettingsSet @collectorSettingsArguments
    $collectorRegistration = @{
        TaskName = $collectorTaskName
        TaskPath = $collectorTaskPath
        Action = $collectorAction
        Trigger = $collectorTrigger
        Principal = $collectorPrincipal
        Settings = $collectorSettings
        Description = 'Refresh AgentMeter Claude Code and Codex quota data.'
    }
    Register-ScheduledTask @collectorRegistration -Force | Out-Null
    Start-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath
} catch {
    # Put the toolbar registration back so Explorer keeps loading the build it already has.
    if ($previousServerRegistration.Assembly -and $previousServerRegistration.CodeBase) {
        Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name Assembly -Value $previousServerRegistration.Assembly -ErrorAction SilentlyContinue
        Set-ItemProperty -LiteralPath $inprocServerRegistryPath -Name CodeBase -Value $previousServerRegistration.CodeBase -ErrorAction SilentlyContinue
    } elseif (!$toolbarWasRegistered -and (Test-Path -LiteralPath $toolbarClassRegistryPath)) {
        Remove-Item -LiteralPath $toolbarClassRegistryPath -Recurse -ErrorAction SilentlyContinue
    }
    if (!$collectorTaskAlreadyExists) {
        Stop-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($isUpdate) {
        Remove-Item -LiteralPath $toolbarDllPath -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $installDirectory -Recurse -ErrorAction SilentlyContinue
    }
    throw
}

# Builds that Explorer still has loaded stay behind until the next update.
Get-ChildItem -LiteralPath $installDirectory -Filter 'AgentMeterBand*.dll' -File |
    Where-Object { $_.FullName -ne $toolbarDllPath } |
    Remove-Item -ErrorAction SilentlyContinue

if ($isUpdate) {
    Write-Host 'Updated. The collector already runs the new scripts.'
    Write-Host 'Sign out of Windows and back in to load the new toolbar build.'
    Write-Host 'If the toolbar is gone afterwards, select Toolbars > AgentMeter Quotas again.'
} else {
    Write-Host 'Installed. Right-click the taskbar and select Toolbars > AgentMeter Quotas once.'
    Write-Host 'If the menu does not show it yet, sign out of Windows and back in.'
}
Write-Host 'For Claude Code quotas, follow the status-line setup in README.md.'
