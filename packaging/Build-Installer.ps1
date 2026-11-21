param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$InnoCompiler,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$buildDirectory = Join-Path $OutputDirectory "build-$Version"
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
$toolbarDll = Join-Path $buildDirectory "AgentMeterBand-$Version.dll"
& (Join-Path $PSScriptRoot 'Build-Toolbar.ps1') -Version $Version -OutputPath $toolbarDll

$installerSource = Join-Path $PSScriptRoot 'AgentMeter.iss'
& $InnoCompiler "/DAppVersion=$Version" "/DBuildDirectory=$buildDirectory" "/DOutputDirectory=$OutputDirectory" $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build AgentMeter Setup.' }
