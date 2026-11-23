param([Parameter(Mandatory)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$layout = Import-PowerShellDataFile -LiteralPath (Join-Path $projectRoot 'packaging\InstallationLayout.psd1')
$runtimeFields = 'DirectoryName', 'RegistrySubKey', 'RegistryVersionValueName', 'UpdaterFileName'
$declarations = foreach ($field in $runtimeFields) {
    '    internal const string {0} = @"{1}";' -f $field, $layout[$field].Replace('"', '""')
}
$source = @(
    '// Generated from packaging/InstallationLayout.psd1.'
    'internal static partial class InstallationLayout {'
    $declarations
    '}'
)
[IO.File]::WriteAllLines($OutputPath, [string[]]$source, [Text.UTF8Encoding]::new($false))
