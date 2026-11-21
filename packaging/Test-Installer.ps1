param(
    [Parameter(Mandatory)][string]$PreviousInstaller,
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Run this installation test on a disposable GitHub-hosted runner.'
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'AgentMeterTaskbar'
$startAllBack = 'HKCU:\Software\StartIsBack'
$productKey = 'HKCU:\Software\AgentMeterTaskbar'
$toolbarKey = 'HKCU:\Software\Classes\CLSID\{EA143E8E-217B-4B86-925B-37EA04848915}'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B8D2F322-40F2-4265-8551-1E9417B52FDD}_is1'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$collectorTask = "AgentMeter Taskbar Collector ($sid)"
$updateTask = "AgentMeter Taskbar Updates ($sid)"
foreach ($path in $installDirectory, $startAllBack, $productKey, $toolbarKey, $uninstallKey) {
    if (Test-Path -LiteralPath $path) { throw 'The installation-test runner is not clean.' }
}

function Start-TestSetup($Path, [string[]]$Options) {
    $process = Start-Process -FilePath $Path -ArgumentList $Options -WindowStyle Hidden -PassThru -Wait
    return $process.ExitCode
}

function Assert-InstalledVersion($ExpectedVersion) {
    $actualVersion = (Get-ItemProperty -LiteralPath $productKey -Name Version).Version
    if ($actualVersion -ne $ExpectedVersion) { throw "Expected version $ExpectedVersion, installed $actualVersion." }
    $server = Get-ItemProperty -LiteralPath (Join-Path $toolbarKey 'InprocServer32')
    $expectedDll = Join-Path $installDirectory "AgentMeterBand-$ExpectedVersion.dll"
    if (([uri]$server.CodeBase).LocalPath -ne $expectedDll -or !(Test-Path -LiteralPath $expectedDll -PathType Leaf)) {
        throw 'Explorer registration does not reference the packaged toolbar.'
    }
}

$options = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'
$logDirectory = Join-Path $env:RUNNER_TEMP 'agentmeter-setup-logs'
[IO.Directory]::CreateDirectory($logDirectory) | Out-Null
if ((Start-TestSetup $Installer ($options + "/LOG=$logDirectory\prerequisite.log")) -eq 0) {
    throw 'Setup should refuse to install without the classic taskbar.'
}

try {
    New-Item -Path $startAllBack | Out-Null
    New-ItemProperty -LiteralPath $startAllBack -Name LegacyTaskbar -PropertyType DWord -Value 1 | Out-Null
    if ((Start-TestSetup $PreviousInstaller ($options + "/LOG=$logDirectory\install.log")) -ne 0) {
        throw 'Fresh setup failed.'
    }
    Assert-InstalledVersion '0.1.99'
    if (!(Get-ScheduledTask -TaskName $collectorTask) -or !(Get-ScheduledTask -TaskName $updateTask)) {
        throw 'Setup did not create both per-user tasks.'
    }
    $initialUninstall = (Get-ItemProperty -LiteralPath $uninstallKey).UninstallString
    if ((Start-TestSetup $Installer ($options + "/LOG=$logDirectory\upgrade.log")) -ne 0) {
        throw 'Upgrade setup failed.'
    }
    Assert-InstalledVersion $Version
    if ((Get-ItemProperty -LiteralPath $uninstallKey).UninstallString -ne $initialUninstall) {
        throw 'Upgrade should reuse the Installed apps entry.'
    }

    $optOut = $options + '/MERGETASKS=!autoupdate' + "/LOG=$logDirectory\opt-out.log"
    if ((Start-TestSetup $Installer $optOut) -ne 0) { throw 'Reconfiguring Setup failed.' }
    if (Get-ScheduledTask -TaskName $updateTask -ErrorAction SilentlyContinue) {
        throw 'Disabling automatic updates did not remove its scheduled task.'
    }
    if ((Start-TestSetup $Installer ($options + "/LOG=$logDirectory\reinstall.log")) -ne 0) {
        throw 'Reinstalling with the prior task selection failed.'
    }
    if (Get-ScheduledTask -TaskName $updateTask -ErrorAction SilentlyContinue) {
        throw 'Setup did not preserve the automatic-update preference.'
    }

    $uninstaller = $initialUninstall.Trim('"')
    if ((Start-TestSetup $uninstaller ($options + "/LOG=$logDirectory\uninstall.log")) -ne 0) {
        throw 'Uninstall failed.'
    }
    foreach ($path in $productKey, $toolbarKey, $uninstallKey, $installDirectory) {
        if (Test-Path -LiteralPath $path) { throw 'Uninstall left an installation entry or files.' }
    }
    foreach ($taskName in $collectorTask, $updateTask) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            throw "Uninstall left task $taskName."
        }
    }
} catch {
    foreach ($file in Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File) {
        Write-Host $file.Name
        Get-Content -LiteralPath $file.FullName -Tail 35
    }
    throw
} finally {
    if (Test-Path -LiteralPath $startAllBack) { Remove-Item -LiteralPath $startAllBack -Recurse }
}
Write-Host 'Verified prerequisite check, per-user install, upgrade, update preference, and uninstall.'
