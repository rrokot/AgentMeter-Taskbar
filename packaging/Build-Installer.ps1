param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$InnoCompiler,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$buildDirectory = Join-Path $OutputDirectory "build-$Version"
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
$toolbarDll = Join-Path $buildDirectory "AgentMeterBand-$Version.dll"
$toolbarSource = Join-Path $projectRoot 'src\AgentMeterBand.cs'

& $compiler /nologo /target:library /platform:x64 /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "/out:$toolbarDll" $toolbarSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build the toolbar DLL.' }

$installerSource = Join-Path $PSScriptRoot 'AgentMeter.iss'
& $InnoCompiler "/DAppVersion=$Version" "/DBuildDirectory=$buildDirectory" "/DOutputDirectory=$OutputDirectory" $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build AgentMeter Setup.' }
