param([switch]$Interactive)

$ErrorActionPreference = 'Stop'

function Read-VerifiedUpdate($Envelope, [string]$PublicKey, [version]$InstalledVersion) {
    $feed = ConvertFrom-Json -InputObject $Envelope
    $payload = [Convert]::FromBase64String($feed.payload)
    $signature = [Convert]::FromBase64String($feed.signature)
    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
    $rsa.PersistKeyInCsp = $false
    try {
        $rsa.FromXmlString($PublicKey)
        $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
        if (!$rsa.VerifyData($payload, $sha256Oid, $signature)) { throw 'Update signature verification failed.' }
    } finally { $rsa.Dispose() }

    $release = ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($payload))
    if ($release.schema -ne 1 -or $release.version -notmatch '^\d+\.\d+\.\d+$' -or
        $release.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Unsupported update manifest.' }
    if ([version]$release.version -gt $InstalledVersion) { return $release }
}

function Assert-UpdateInstallerHash($Path, $ExpectedHash) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'Downloaded installer checksum verification failed.'
    }
}

function Show-UpdateMessage([string]$Message) {
    if ($Interactive) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($Message, 'AgentMeter Taskbar')
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
. (Join-Path $PSScriptRoot 'QuotaData.ps1')

$updateLock = Open-QuotaWriterLock (Join-Path $PSScriptRoot 'updates.lock')
if (!$updateLock) {
    Show-UpdateMessage 'An AgentMeter update check is already running.'
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
        return
    }

    $version = $release.version
    $installerUri = "$releaseBase/download/v$version/AgentMeter-Taskbar-Setup-v$version.exe"
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 90 -Uri $installerUri -OutFile $installerPath
    Assert-UpdateInstallerHash $installerPath $release.sha256
    $currentVersion = [version](Get-ItemProperty -LiteralPath $registryPath -Name Version).Version
    if ([version]$version -le $currentVersion) { return }

    $setupArguments = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'
    $setup = Start-Process -FilePath $installerPath -ArgumentList $setupArguments -WindowStyle Hidden -Wait -PassThru
    if ($setup.ExitCode -ne 0) { throw "AgentMeter Setup returned exit code $($setup.ExitCode)." }
    $currentVersion = [version](Get-ItemProperty -LiteralPath $registryPath -Name Version).Version
    if ($currentVersion -ne [version]$version) { throw 'Setup did not register the expected version.' }

    Add-Content -LiteralPath $logPath -Value "$([DateTimeOffset]::Now.ToString('o')) Installed $version"
    Show-UpdateMessage "AgentMeter Taskbar was updated to $version. Explorer will load the new toolbar the next time it starts."
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
    if (Test-Path -LiteralPath $downloadDirectory) {
        [IO.Directory]::Delete($downloadDirectory)
    }
}
