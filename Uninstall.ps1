$ErrorActionPreference = 'Stop'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$collectorTaskName = "AgentMeter Taskbar Collector ($($currentUser.User.Value))"
$collectorTaskPath = '\'
$toolbarClassRegistryPath = 'HKCU:\Software\Classes\CLSID\{EA143E8E-217B-4B86-925B-37EA04848915}'
$installDirectory = Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar'

if (![Environment]::Is64BitProcess) {
    throw 'Use 64-bit PowerShell to remove AgentMeter Taskbar.'
}

if (Get-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath -ErrorAction SilentlyContinue) {
    Disable-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath | Out-Null
    Stop-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath
    Unregister-ScheduledTask -TaskName $collectorTaskName -TaskPath $collectorTaskPath -Confirm:$false
}

if (Test-Path -LiteralPath $toolbarClassRegistryPath) {
    Remove-Item -LiteralPath $toolbarClassRegistryPath -Recurse
}
if (Test-Path -LiteralPath $installDirectory) {
    $resolvedInstallDirectory = (Resolve-Path -LiteralPath $installDirectory).Path
    if ($resolvedInstallDirectory -ne $installDirectory -or (Get-Item -LiteralPath $resolvedInstallDirectory).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw "Unexpected installation folder: $resolvedInstallDirectory"
    }
    try {
        Remove-Item -LiteralPath $resolvedInstallDirectory -Recurse
    } catch {
        Write-Warning 'If Explorer has the toolbar DLL open, close AgentMeter Quotas, sign out and back in, then run Uninstall.ps1 again.'
        throw
    }
}
Write-Host 'AgentMeter Quotas removed.'
