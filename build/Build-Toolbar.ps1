param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The 64-bit .NET Framework compiler is unavailable.'
}

$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'src\Toolbar') -Filter '*.cs' -File | Select-Object -ExpandProperty FullName)
$sharedLayoutSource = Join-Path $projectRoot 'src\Windows\InstallationLayout.cs'
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$versionSource = Join-Path ([IO.Path]::GetTempPath()) ('AgentMeterVersion-' + [guid]::NewGuid().ToString('N') + '.cs')
$layoutSource = [IO.Path]::ChangeExtension($versionSource, '.layout.cs')
try {
    $assemblyAttribute = '[assembly: System.Reflection.AssemblyInformationalVersion("{0}")]' -f $Version
    [IO.File]::WriteAllText($versionSource, $assemblyAttribute, [Text.Encoding]::ASCII)
    & (Join-Path $PSScriptRoot 'Write-InstallationLayoutSource.ps1') -OutputPath $layoutSource
    & $compiler /nologo /target:library /platform:x64 /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "/out:$OutputPath" @sources $versionSource $sharedLayoutSource $layoutSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the toolbar DLL.' }
} finally {
    [IO.File]::Delete($versionSource)
    [IO.File]::Delete($layoutSource)
}
