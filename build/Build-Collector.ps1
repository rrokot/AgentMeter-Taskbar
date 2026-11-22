param([Parameter(Mandatory)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The 64-bit .NET Framework compiler is unavailable.'
}

$sourceDirectory = Join-Path $projectRoot 'src\Collector'
$sources = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.cs' -File | Select-Object -ExpandProperty FullName)
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
& $compiler /nologo /target:winexe /platform:x64 /r:System.Web.Extensions.dll "/out:$OutputPath" @sources
if ($LASTEXITCODE -ne 0) { throw 'Could not build the quota collector.' }
