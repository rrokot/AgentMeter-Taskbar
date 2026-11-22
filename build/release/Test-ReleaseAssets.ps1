param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Feed
)

$ErrorActionPreference = 'Stop'
$buildDirectory = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $buildDirectory
$installerPath = (Resolve-Path -LiteralPath $Installer).Path
$feedPath = (Resolve-Path -LiteralPath $Feed).Path
$verificationDirectory = Join-Path ([IO.Path]::GetTempPath()) ('AgentMeterVerify-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($verificationDirectory) | Out-Null
$verifier = Join-Path $verificationDirectory 'AgentMeterUpdater.exe'
$verificationKey = Join-Path $verificationDirectory 'update-public.xml'
try {
    & (Join-Path $buildDirectory 'Build-Updater.ps1') -OutputPath $verifier
    Copy-Item -LiteralPath (Join-Path $projectRoot 'src\Updater\update-public.xml') -Destination $verificationKey
    $arguments = 'verify-release', ('"' + $feedPath + '"'), ('"' + $installerPath + '"'), $Version
    $process = Start-Process -FilePath $verifier -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        $log = Join-Path $verificationDirectory 'updates.log'
        if (Test-Path -LiteralPath $log) { throw (Get-Content -LiteralPath $log -Raw) }
        throw 'The compiled updater rejected the signed release.'
    }
    (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
} finally {
    [IO.File]::Delete($verifier)
    [IO.File]::Delete($verificationKey)
    [IO.File]::Delete((Join-Path $verificationDirectory 'updates.log'))
    [IO.Directory]::Delete($verificationDirectory)
}
