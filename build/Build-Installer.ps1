param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$InnoCompiler,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
    [switch]$InstallTestFixture
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packagingDirectory = Join-Path $projectRoot 'packaging'
$layout = Import-PowerShellDataFile -LiteralPath (Join-Path $packagingDirectory 'InstallationLayout.psd1')
$OutputDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$buildDirectory = Join-Path $OutputDirectory "build-$Version"
[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
$toolbarFileName = $layout.ToolbarFileName -f $Version
$collectorFileName = $layout.CollectorFileName -f $Version
$updaterFileName = $layout.UpdaterFileName -f $Version
& (Join-Path $PSScriptRoot 'Build-Toolbar.ps1') -Version $Version -OutputPath (Join-Path $buildDirectory $toolbarFileName)
& (Join-Path $PSScriptRoot 'Build-Collector.ps1') -OutputPath (Join-Path $buildDirectory $collectorFileName)
& (Join-Path $PSScriptRoot 'Build-Updater.ps1') -OutputPath (Join-Path $buildDirectory $updaterFileName)

$installerSource = Join-Path $packagingDirectory 'AgentMeter.iss'
$compilerArguments = @(
    "/DAppVersion=$Version"
    "/DBuildDirectory=$buildDirectory"
    "/DOutputDirectory=$OutputDirectory"
    "/DInstallDirectoryName=$($layout.DirectoryName)"
    "/DProductRegistrySubKey=$($layout.RegistrySubKey)"
    "/DRegistryVersionValueName=$($layout.RegistryVersionValueName)"
    "/DToolbarFileName=$toolbarFileName"
    "/DCollectorFileName=$collectorFileName"
    "/DUpdaterFileName=$updaterFileName"
)
if ($InstallTestFixture) { $compilerArguments += '/DInstallTestFixture' }
& $InnoCompiler @compilerArguments $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Could not build AgentMeter Setup.' }
