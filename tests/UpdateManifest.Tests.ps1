Describe 'Compiled update verification' {
    BeforeAll {
        $updater = Join-Path $TestDrive 'AgentMeterUpdater.exe'
        & (Join-Path $PSScriptRoot '..\build\Build-Updater.ps1') -OutputPath $updater
        $publicKey = Join-Path $TestDrive 'update-public.xml'
        $feedPath = Join-Path $TestDrive 'agentmeter-update.json'
        $installer = Join-Path $TestDrive 'installer.exe'
    }

    BeforeEach {
        $signer = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
        $signer.PersistKeyInCsp = $false
        [IO.File]::WriteAllText($publicKey, $signer.ToXmlString($false))
        [IO.File]::WriteAllText($installer, 'test package')
        $hash = (Get-FileHash -LiteralPath $installer).Hash
        $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
    }
    AfterEach { $signer.Dispose() }

    function New-TestUpdateFeed($Version) {
        $manifest = @{ schema = 1; version = $Version; sha256 = $hash } | ConvertTo-Json -Compress
        $payload = [Text.Encoding]::UTF8.GetBytes($manifest)
        @{
            payload = [Convert]::ToBase64String($payload)
            signature = [Convert]::ToBase64String($signer.SignData($payload, $sha256Oid))
        }
    }

    function Invoke-UpdateVerification($Feed, $Version) {
        [IO.File]::WriteAllText($feedPath, (ConvertTo-Json -InputObject $Feed))
        $arguments = 'verify-release', ('"' + $feedPath + '"'), ('"' + $installer + '"'), $Version
        $process = Start-Process -FilePath $updater -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        $process.ExitCode
    }

    It 'accepts a correctly signed manifest for the selected installer and version' {
        Invoke-UpdateVerification (New-TestUpdateFeed '0.2.0') '0.2.0' | Should Be 0
    }

    It 'rejects a signed manifest after the payload is changed' {
        $feed = New-TestUpdateFeed '0.2.0'
        $feed.payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"version":"999.0.0"}'))
        Invoke-UpdateVerification $feed '0.2.0' | Should Be 1
    }

    It 'rejects version text that cannot be used in a release asset name' {
        Invoke-UpdateVerification (New-TestUpdateFeed '../0.2.0') '0.2.0' | Should Be 1
    }

    It 'rejects an installer whose SHA-256 differs from the manifest' {
        $feed = New-TestUpdateFeed '0.2.0'
        [IO.File]::WriteAllText($installer, 'changed package')
        Invoke-UpdateVerification $feed '0.2.0' | Should Be 1
    }

    It 'rejects a signed manifest for another release version' {
        Invoke-UpdateVerification (New-TestUpdateFeed '0.2.0') '0.2.1' | Should Be 1
    }

    It 'reports an update already in progress to the toolbar' {
        $lock = [IO.File]::Open((Join-Path $TestDrive 'updates.lock'), 'OpenOrCreate', 'Write', 'None')
        try {
            $startInfo = [Diagnostics.ProcessStartInfo]::new($updater, 'check')
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $process = [Diagnostics.Process]::Start($startInfo)
            try {
                $output = $process.StandardOutput.ReadToEndAsync()
                if (!$process.WaitForExit(10000)) {
                    $process.Kill()
                    throw 'The updater did not return after detecting the lock.'
                }
                $process.ExitCode | Should Be 0
                $reply = $output.GetAwaiter().GetResult() | ConvertFrom-Json
                $reply.status | Should Be 'busy'
            } finally { $process.Dispose() }
        } finally { $lock.Dispose() }
    }
}
