param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$InnoCompiler,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$buildDirectory = Join-Path $OutputDirectory "build-$Version"
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
$toolbarDll = Join-Path $buildDirectory "AgentMeterBand-$Version.dll"
& (Join-Path $PSScriptRoot 'Build-Toolbar.ps1') -Version $Version -OutputPath $toolbarDll

$collectorExe = Join-Path $buildDirectory "AgentMeter Collector-$Version.exe"
& (Join-Path $PSScriptRoot 'Build-Collector.ps1') -OutputPath $collectorExe
$updaterExe = Join-Path $buildDirectory "AgentMeterUpdater-$Version.exe"
& (Join-Path $PSScriptRoot 'Build-Updater.ps1') -OutputPath $updaterExe

$installerSource = Join-Path $projectRoot 'packaging\AgentMeter.iss'
& $InnoCompiler "/DAppVersion=$Version" "/DBuildDirectory=$buildDirectory" "/DOutputDirectory=$OutputDirectory" $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build AgentMeter Setup.' }
