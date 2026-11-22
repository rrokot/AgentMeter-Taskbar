. (Join-Path $PSScriptRoot '..\packaging\UpdateManifest.ps1')

Describe 'Signed update feed' {
    BeforeEach {
        $signer = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $signer.PersistKeyInCsp = $false
        $publicKey = $signer.ToXmlString($false)
        $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
    }
    AfterEach { $signer.Dispose() }

    function New-TestUpdateFeed($Version, $Hash) {
        $manifest = @{ schema = 1; version = $Version; sha256 = $Hash } | ConvertTo-Json -Compress
        $payload = [Text.Encoding]::UTF8.GetBytes($manifest)
        return ConvertTo-Json -InputObject @{
            payload = [Convert]::ToBase64String($payload)
            signature = [Convert]::ToBase64String($signer.SignData($payload, $sha256Oid))
        }
    }

    It 'accepts a higher signed version and ignores installed or older releases' {
        $feed = New-TestUpdateFeed '0.2.0' ('a' * 64)
        (Read-VerifiedUpdate $feed $publicKey ([version]'0.1.0')).version | Should Be '0.2.0'
        Read-VerifiedUpdate $feed $publicKey ([version]'0.2.0') | Should BeNullOrEmpty
        Read-VerifiedUpdate $feed $publicKey ([version]'0.3.0') | Should BeNullOrEmpty
    }

    It 'rejects a signed manifest after the payload is changed' {
        $feed = New-TestUpdateFeed '0.2.0' ('a' * 64) | ConvertFrom-Json
        $feed.payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"version":"999.0.0"}'))
        { Read-VerifiedUpdate (ConvertTo-Json $feed) $publicKey ([version]'0.1.0') } | Should Throw
    }

    It 'rejects version text that cannot be used in a release asset name' {
        $feed = New-TestUpdateFeed '../0.2.0' ('a' * 64)
        { Read-VerifiedUpdate $feed $publicKey ([version]'0.1.0') } | Should Throw
    }

    It 'rejects a downloaded installer whose SHA-256 differs from the manifest' {
        $installer = Join-Path $TestDrive 'installer.exe'
        [IO.File]::WriteAllText($installer, 'first package')
        $hash = (Get-FileHash -LiteralPath $installer).Hash
        { Assert-UpdateInstallerHash $installer $hash } | Should Not Throw
        [IO.File]::WriteAllText($installer, 'changed package')
        { Assert-UpdateInstallerHash $installer $hash } | Should Throw
    }
}
