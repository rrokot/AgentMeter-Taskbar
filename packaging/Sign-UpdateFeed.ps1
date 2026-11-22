param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$Installer
)

$ErrorActionPreference = 'Stop'
$installerFile = Get-Item -LiteralPath $Installer
if ($installerFile.Name -ne "AgentMeter-Taskbar-Setup-v$Version.exe") {
    throw 'Installer filename does not match the release version.'
}
$publicKey = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'update-public.xml') -Raw).Trim()
$manifest = @{
    schema = 1
    version = $Version
    sha256 = (Get-FileHash -LiteralPath $installerFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$payload = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $manifest -Compress))
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
$rsa.PersistKeyInCsp = $false
$privateKey = $null
try {
    if ([string]::IsNullOrWhiteSpace($env:AGENTMETER_UPDATE_SIGNING_KEY)) {
        throw 'The release-signing environment has no update signing key.'
    }
    $privateKey = [Convert]::FromBase64String($env:AGENTMETER_UPDATE_SIGNING_KEY)
    Remove-Item Env:AGENTMETER_UPDATE_SIGNING_KEY
    $rsa.FromXmlString([Text.Encoding]::UTF8.GetString($privateKey))
    if ($rsa.ToXmlString($false) -ne $publicKey) { throw 'Private key does not match the installed update trust key.' }
    $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
    $signature = $rsa.SignData($payload, $sha256Oid)
    $envelope = @{
        payload = [Convert]::ToBase64String($payload)
        signature = [Convert]::ToBase64String($signature)
    }
    $feedPath = Join-Path $installerFile.DirectoryName 'agentmeter-update.json'
    [IO.File]::WriteAllText($feedPath, (ConvertTo-Json -InputObject $envelope), [Text.UTF8Encoding]::new($false))
    $feedPath
} finally {
    $rsa.Dispose()
    if ($privateKey) { [Array]::Clear($privateKey, 0, $privateKey.Length) }
}
