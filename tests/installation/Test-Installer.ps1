param(
    [Parameter(Mandatory)][string]$ProductionInstaller,
    [Parameter(Mandatory)][string]$FixtureInstaller,
    [Parameter(Mandatory)][string]$Version
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Run this installation test on a disposable GitHub-hosted runner.'
}

$layout = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '..\..\packaging\InstallationLayout.psd1')
$installDirectory = Join-Path $env:LOCALAPPDATA $layout.DirectoryName
$productKey = Join-Path 'HKCU:\' $layout.RegistrySubKey
$versionValueName = $layout.RegistryVersionValueName
$toolbarKey = 'HKCU:\Software\Classes\CLSID\{EA143E8E-217B-4B86-925B-37EA04848915}'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B8D2F322-40F2-4265-8551-1E9417B52FDD}_is1'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$collectorTask = "AgentMeter Taskbar Collector ($sid)"
$updateTask = "AgentMeter Taskbar Updates ($sid)"
foreach ($path in $installDirectory, $productKey, $toolbarKey, $uninstallKey) {
    if (Test-Path -LiteralPath $path) { throw 'The installation-test runner is not clean.' }
}

function Start-TestSetup($Path, [string[]]$Options) {
    $process = Start-Process -FilePath $Path -ArgumentList $Options -WindowStyle Hidden -PassThru -Wait
    return $process.ExitCode
}

function Assert-InstalledVersion($ExpectedVersion) {
    $actualVersion = Get-ItemPropertyValue -LiteralPath $productKey -Name $versionValueName
    if ($actualVersion -ne $ExpectedVersion) { throw "Expected version $ExpectedVersion, installed $actualVersion." }
    $server = Get-ItemProperty -LiteralPath (Join-Path $toolbarKey 'InprocServer32')
    $expectedDll = Join-Path $installDirectory ($layout.ToolbarFileName -f $ExpectedVersion)
    if (([uri]$server.CodeBase).LocalPath -ne $expectedDll -or !(Test-Path -LiteralPath $expectedDll -PathType Leaf)) {
        throw 'Explorer registration does not reference the packaged toolbar.'
    }
    if ((Get-Item -LiteralPath $expectedDll).VersionInfo.ProductVersion -ne $ExpectedVersion) {
        throw 'The toolbar version shown in the popup does not match the installed package.'
    }
}

function Invoke-TestSignedUpdate([switch]$CheckOnly) {
    $feed = Join-Path $logDirectory 'test-update-feed.json'
    $publicKeyPath = Join-Path $installDirectory 'update-public.xml'
    $installedPublicKey = [IO.File]::ReadAllBytes($publicKeyPath)
    $feedVersion = if ($CheckOnly) { $newerVersion } else { $Version }
    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(2048)
    $rsa.PersistKeyInCsp = $false
    try {
        $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $payload = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ schema = 1; version = $feedVersion; sha256 = $hash }))
        $sha256Oid = [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
        $manifest = @{
            payload = [Convert]::ToBase64String($payload)
            signature = [Convert]::ToBase64String($rsa.SignData($payload, $sha256Oid))
        }
        ConvertTo-Json -InputObject $manifest | Set-Content -LiteralPath $feed -Encoding UTF8
        [IO.File]::WriteAllText($publicKeyPath, $rsa.ToXmlString($false))
    } finally { $rsa.Dispose() }

    $download = [Action[Uri, string, int]] {
        param($Uri, $DestinationPath, $TimeoutSeconds)
        if ($Uri.AbsolutePath.EndsWith('/agentmeter-update.json')) {
            [IO.File]::Copy($feed, $DestinationPath)
        } elseif (!$CheckOnly -and $Uri.AbsolutePath.EndsWith("/AgentMeter-Taskbar-Setup-v$feedVersion.exe")) {
            [IO.File]::Copy($installerPath, $DestinationPath)
        } else {
            throw "Unexpected update URL: $Uri"
        }
    }
    try {
        $registryVersion = Get-ItemPropertyValue -LiteralPath $productKey -Name $versionValueName
        $updateDirectory = $installDirectory.PSObject.BaseObject
        if ($CheckOnly) {
            $check = $runUpdate.Invoke($null, @($updateDirectory, [Enum]::Parse($updateMode, 'Check'), $null, $download))
            if ($check.Outcome.ToString() -ne 'Available' -or $check.Version.ToString() -ne $feedVersion) {
                throw 'Popup check did not return the signed release version.'
            }
            $changed = $runUpdate.Invoke($null, @($updateDirectory, [Enum]::Parse($updateMode, 'Install'), [version]'0.0.1', $download))
            if ($changed.Outcome.ToString() -ne 'Available' -or $changed.Version -ne $check.Version) {
                throw 'Popup install did not stop when the selected version differed from the signed release.'
            }
        } else {
            $expectedOutcome = if ([version]$registryVersion -lt [version]$Version) { 'Installed' } else { 'Current' }
            $automatic = $runUpdate.Invoke($null, @($updateDirectory, [Enum]::Parse($updateMode, 'Automatic'), $null, $download))
            if ($automatic.Outcome.ToString() -ne $expectedOutcome -or $automatic.Version.ToString() -ne $Version) {
                throw "The automatic update did not report $expectedOutcome for $Version."
            }
        }
    } finally {
        [IO.File]::WriteAllBytes($publicKeyPath, $installedPublicKey)
    }
}

$installerPath = (Resolve-Path -LiteralPath $FixtureInstaller).Path
$current = [version]$Version
$newerVersion = "$($current.Major).$($current.Minor).$($current.Build + 1)"
$options = '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'
$logDirectory = Join-Path $env:RUNNER_TEMP 'agentmeter-setup-logs'
[IO.Directory]::CreateDirectory($logDirectory) | Out-Null
try {
    Add-Type -Path (Join-Path $PSScriptRoot 'SetupTestDesktop.cs')
    $productionPath = (Resolve-Path -LiteralPath $ProductionInstaller).Path
    $prerequisiteLog = Join-Path $logDirectory 'prerequisite.log'
    $prerequisiteOptions = ($options + ('/LOG="' + $prerequisiteLog + '"')) -join ' '
    $prerequisiteExitCode = [SetupTestDesktop]::Run($productionPath, $prerequisiteOptions)
    if ($prerequisiteExitCode -eq 0 -or
        !(Select-String -LiteralPath $prerequisiteLog -SimpleMatch 'No DeskBand-compatible taskbar was detected.' -Quiet)) {
        throw "Production Setup should reject a desktop without a detected DeskBand host (exit code $prerequisiteExitCode)."
    }

    $env:CLAUDE_CONFIG_DIR = Join-Path $logDirectory 'claude'
    [IO.Directory]::CreateDirectory($env:CLAUDE_CONFIG_DIR) | Out-Null
    $claudeSettings = Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json'
    [IO.File]::WriteAllText($claudeSettings, '{"permissions":{"allow":["Read"]}}')

    $env:CODEX_HOME = Join-Path $logDirectory 'codex'
    $codexSessions = Join-Path $env:CODEX_HOME 'sessions'
    [IO.Directory]::CreateDirectory($codexSessions) | Out-Null
    $codexLog = @{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        payload = @{
            type = 'token_count'
            rate_limits = @{ primary = @{ used_percent = 21; window_minutes = 300 } }
        }
    } | ConvertTo-Json -Compress -Depth 6
    [IO.File]::WriteAllText((Join-Path $codexSessions 'rollout-first-install.jsonl'), $codexLog)
    if ((Start-TestSetup $installerPath ($options + "/LOG=$logDirectory\install.log")) -ne 0) {
        throw 'Fresh setup failed.'
    }
    $snapshotPath = Join-Path $installDirectory 'data.json'
    if (!(Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        throw 'The first installation completed without a quota snapshot.'
    }
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    if ($snapshot.codex_five_hour_pct -ne '21' -or !$snapshot.PSObject.Properties['claude_five_hour_pct']) {
        throw 'The first quota snapshot did not include the existing Codex quota and the Claude fields.'
    }
    Assert-InstalledVersion $Version
    $initialUninstall = (Get-ItemProperty -LiteralPath $uninstallKey).UninstallString
    if (!(Get-Content -LiteralPath $claudeSettings -Raw | ConvertFrom-Json).statusLine.command) {
        throw 'Setup did not connect the existing Claude Code profile.'
    }
    $updaterTriggers = (Get-ScheduledTask -TaskName $updateTask).Triggers
    if (!($updaterTriggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $_.Enabled })) {
        throw 'Automatic updates must check at Windows sign-in.'
    }
    $updaterExe = Join-Path $installDirectory ($layout.UpdaterFileName -f $Version)
    $updaterAction = (Get-ScheduledTask -TaskName $updateTask).Actions
    if ($updaterAction.Execute -ne $updaterExe -or $updaterAction.Arguments -ne 'automatic') {
        throw 'The scheduled task does not run the packaged updater executable.'
    }
    $toolbarDll = Join-Path $installDirectory ($layout.ToolbarFileName -f $Version)
    $toolbar = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($toolbarDll))
    $runToolbarUpdater = $toolbar.GetType('ToolbarUpdater', $true).GetMethod('RunUpdater', [Reflection.BindingFlags]'Static, NonPublic')
    # Hold the lock so the toolbar can launch the registered updater without downloading a release.
    $updateLock = [IO.File]::Open((Join-Path $installDirectory 'updates.lock'), 'OpenOrCreate', 'Write', 'None')
    try {
        $reply = $runToolbarUpdater.Invoke($null, @($installDirectory.PSObject.BaseObject, 'check', 30000)) | ConvertFrom-Json
        if ($reply.status -ne 'busy') { throw 'The toolbar could not launch the installed updater.' }
    } finally { $updateLock.Dispose() }
    $updaterAssembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($updaterExe))
    $updateService = $updaterAssembly.GetType('UpdateService', $true)
    $updateMode = $updateService.GetNestedType('Mode', [Reflection.BindingFlags]'NonPublic')
    $runUpdate = $updateService.GetMethod('Run', [Reflection.BindingFlags]'Static, NonPublic')
    $collectorExe = Join-Path $installDirectory ($layout.CollectorFileName -f $Version)
    $collectorAction = (Get-ScheduledTask -TaskName $collectorTask).Actions
    if ($collectorAction.Execute -ne $collectorExe) {
        throw 'The scheduled task does not run the packaged collector executable.'
    }

    # Exercise an available signed update with the current package and an older registered version.
    Set-ItemProperty -LiteralPath $productKey -Name $versionValueName -Value '0.0.0'
    Invoke-TestSignedUpdate
    Assert-InstalledVersion $Version
    Invoke-TestSignedUpdate
    Invoke-TestSignedUpdate -CheckOnly
    if ((Get-ItemProperty -LiteralPath $uninstallKey).UninstallString -ne $initialUninstall) {
        throw 'Upgrade should reuse the Installed apps entry.'
    }
    Set-ItemProperty -LiteralPath $productKey -Name $versionValueName -Value $newerVersion
    try {
        if ((Start-TestSetup $installerPath ($options + "/LOG=$logDirectory\downgrade.log")) -eq 0) {
            throw 'Setup allowed an older version over a newer one.'
        }
    } finally { Set-ItemProperty -LiteralPath $productKey -Name $versionValueName -Value $Version }
    Assert-InstalledVersion $Version

    if ((Start-TestSetup $installerPath ($options + "/LOG=$logDirectory\reinstall.log")) -ne 0) {
        throw 'Reinstalling failed.'
    }
    if (!(Get-ScheduledTask -TaskName $updateTask -ErrorAction SilentlyContinue)) {
        throw 'Reinstalling did not preserve the automatic-update task.'
    }

    $uninstaller = $initialUninstall.Trim('"')
    if ((Start-TestSetup $uninstaller ($options + "/LOG=$logDirectory\uninstall.log")) -ne 0) {
        throw 'Uninstall failed.'
    }
    foreach ($path in $productKey, $toolbarKey, $uninstallKey, $installDirectory) {
        if (Test-Path -LiteralPath $path) { throw 'Uninstall left an installation entry or files.' }
    }
    foreach ($taskName in $collectorTask, $updateTask) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            throw "Uninstall left task $taskName."
        }
    }
    $settings = Get-Content -LiteralPath $claudeSettings -Raw | ConvertFrom-Json
    if ($settings.statusLine -or $settings.permissions.allow[0] -ne 'Read') {
        throw 'Uninstall did not remove only its own Claude Code setting.'
    }
} catch {
    foreach ($file in Get-ChildItem -LiteralPath $logDirectory -Filter '*.log' -File) {
        Write-Host $file.Name
        Get-Content -LiteralPath $file.FullName -Tail 35
    }
    throw
}
Write-Host 'Verified prerequisite check, per-user install, signed background update, sign-in trigger, and uninstall.'
