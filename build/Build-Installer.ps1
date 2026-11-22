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

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$collectorSource = Join-Path $projectRoot 'src\Collector\AgentMeterCollector.cs'
$collectorLauncher = Join-Path $buildDirectory "AgentMeterCollector-$Version.exe"
& $compiler /nologo /target:winexe /platform:x64 "/out:$collectorLauncher" $collectorSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build the collector launcher.' }

$installerSource = Join-Path $projectRoot 'packaging\AgentMeter.iss'
& $InnoCompiler "/DAppVersion=$Version" "/DBuildDirectory=$buildDirectory" "/DOutputDirectory=$OutputDirectory" $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build AgentMeter Setup.' }
