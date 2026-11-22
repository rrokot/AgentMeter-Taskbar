function Read-VerifiedUpdate($Envelope, [string]$PublicKey, [version]$InstalledVersion) {
    $feed = ConvertFrom-Json -InputObject $Envelope
    $payload = [Convert]::FromBase64String($feed.payload)
    $signature = [Convert]::FromBase64String($feed.signature)
    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
    $rsa.PersistKeyInCsp = $false
    try {
        $rsa.FromXmlString($PublicKey)
        $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
        if (!$rsa.VerifyData($payload, $sha256Oid, $signature)) { throw 'Update signature verification failed.' }
    } finally { $rsa.Dispose() }

    $release = ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($payload))
    if ($release.schema -ne 1 -or $release.version -notmatch '^\d+\.\d+\.\d+$' -or
        $release.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Unsupported update manifest.' }
    if ([version]$release.version -gt $InstalledVersion) { return $release }
}

function Assert-UpdateInstallerHash($Path, $ExpectedHash) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'Downloaded installer checksum verification failed.'
    }
}
