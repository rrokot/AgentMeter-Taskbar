[CmdletBinding(DefaultParameterSetName='Automatic')]
param(
    [Parameter(ParameterSetName='Interactive')][switch]$Interactive,
    [Parameter(ParameterSetName='Popup', Mandatory)][ValidateSet('Check','Install')][string]$Mode,
    [Parameter(ParameterSetName='Popup')][ValidatePattern('^\d+\.\d+\.\d+$')][string]$TargetVersion
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'QuotaData.ps1')
. (Join-Path $PSScriptRoot 'UpdateManifest.ps1')

function Show-UpdateMessage([string]$Message) {
    if ($Interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($Message, 'AgentMeter Taskbar')
    }
}

function Write-UpdateResult([string]$Status, [string]$Version) {
    if ($Mode) { ConvertTo-Json -Compress @{ status = $Status; version = $Version } }
}

$updateLock = Open-QuotaWriterLock (Join-Path $PSScriptRoot 'updates.lock')
if (!$updateLock) {
    Show-UpdateMessage 'An AgentMeter update check is already running.'
    Write-UpdateResult 'busy'
    return
}
$downloadDirectory = Join-Path $env:TEMP ('AgentMeterUpdate-' + [guid]::NewGuid().ToString('N'))
$feedPath = Join-Path $downloadDirectory 'agentmeter-update.json'
$installerPath = Join-Path $downloadDirectory 'AgentMeter-Setup.exe'
$logPath = Join-Path $PSScriptRoot 'updates.log'

try {
    $registryPath = 'HKCU:\Software\AgentMeterTaskbar'
    $installedVersion = [version](Get-ItemProperty -LiteralPath $registryPath -Name Version).Version
    $publicKey = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'update-public.xml') -Raw
    [IO.Directory]::CreateDirectory($downloadDirectory) | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $releaseBase = 'https://github.com/rrokot/AgentMeter-Taskbar/releases'
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri "$releaseBase/latest/download/agentmeter-update.json" -OutFile $feedPath
    if ((Get-Item -LiteralPath $feedPath).Length -gt 16384) { throw 'Update manifest is too large.' }
    $release = Read-VerifiedUpdate (Get-Content -LiteralPath $feedPath -Raw) $publicKey $installedVersion
    if (!$release) {
        Show-UpdateMessage "AgentMeter Taskbar is up to date ($installedVersion)."
        Write-UpdateResult 'current' $installedVersion
        return
    }

    $version = $release.version
    if ($Mode -eq 'Check' -or ($Mode -eq 'Install' -and $version -cne $TargetVersion)) {
        Write-UpdateResult 'available' $version
        return
    }
    $installerUri = "$releaseBase/download/v$version/AgentMeter-Taskbar-Setup-v$version.exe"
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 90 -Uri $installerUri -OutFile $installerPath
    Assert-UpdateInstallerHash $installerPath $release.sha256
    $currentVersion = [version](Get-ItemProperty -LiteralPath $registryPath -Name Version).Version
    if ([version]$version -le $currentVersion) {
        Write-UpdateResult 'current' $currentVersion
        return
    }

    $setupArguments = @('/NORESTART', '/SP-')
    if ($Interactive) {
        $setup = Start-Process -FilePath $installerPath -ArgumentList $setupArguments -Wait -PassThru
        if ($setup.ExitCode -eq 2) { return }
    } else {
        $setupArguments += '/VERYSILENT', '/SUPPRESSMSGBOXES'
        $setup = Start-Process -FilePath $installerPath -ArgumentList $setupArguments -WindowStyle Hidden -Wait -PassThru
    }
    if ($setup.ExitCode -ne 0) { throw "AgentMeter Setup returned exit code $($setup.ExitCode)." }
    $currentVersion = [version](Get-ItemProperty -LiteralPath $registryPath -Name Version).Version
    if ($currentVersion -ne [version]$version) { throw 'Setup did not register the expected version.' }

    Write-UpdateResult 'installed' $version
    Add-Content -LiteralPath $logPath -Value "$([DateTimeOffset]::Now.ToString('o')) Installed $version" -ErrorAction SilentlyContinue
} catch {
    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 65536) {
            Clear-Content -LiteralPath $logPath
        }
        Add-Content -LiteralPath $logPath -Value "$([DateTimeOffset]::Now.ToString('o')) $($_.Exception.Message)"
    } catch { }
    Show-UpdateMessage "Could not check or install the update. Details are in $logPath."
    exit 1
} finally {
    $updateLock.Dispose()
    foreach ($download in $feedPath, $installerPath) {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -ErrorAction SilentlyContinue }
    }
    try {
        if (Test-Path -LiteralPath $downloadDirectory) { [IO.Directory]::Delete($downloadDirectory) }
    } catch [IO.IOException] { }
    catch [UnauthorizedAccessException] { }
}
