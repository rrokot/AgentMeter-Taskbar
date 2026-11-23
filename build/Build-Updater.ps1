param([Parameter(Mandatory)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The 64-bit .NET Framework compiler is unavailable.'
}

$sourceDirectory = Join-Path $projectRoot 'src\Updater'
$sources = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.cs' -File | Select-Object -ExpandProperty FullName)
$sharedLayoutSource = Join-Path $projectRoot 'src\Windows\InstallationLayout.cs'
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$layoutSource = Join-Path ([IO.Path]::GetTempPath()) ('AgentMeterLayout-' + [guid]::NewGuid().ToString('N') + '.cs')
try {
    & (Join-Path $PSScriptRoot 'Write-InstallationLayoutSource.ps1') -OutputPath $layoutSource
    & $compiler /nologo /target:winexe /platform:x64 /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll "/out:$OutputPath" @sources $sharedLayoutSource $layoutSource
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the updater.' }
} finally { [IO.File]::Delete($layoutSource) }
