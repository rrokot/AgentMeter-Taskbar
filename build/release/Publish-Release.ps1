param(
    [Parameter(Mandatory)][string]$AssetDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$Commit,
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+/[\w.-]+$')][string]$Repository
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Invoke-GitHubCli {
    $result = & gh @args
    if ($LASTEXITCODE -ne 0) { throw 'A GitHub release command failed.' }
    return $result
}

$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a three-part release version.' }
$tag = "v$version"
$installerName = "AgentMeter-Taskbar-Setup-$tag.exe"
$installer = Join-Path $AssetDirectory $installerName
$checksum = Join-Path $AssetDirectory "AgentMeter-Taskbar-Setup-$tag.sha256"
$feed = Join-Path $AssetDirectory 'agentmeter-update.json'

$hash = & (Join-Path $PSScriptRoot 'Test-ReleaseAssets.ps1') -Version $version -Installer $installer -Feed $feed
if ((Get-Content -LiteralPath $checksum -Raw).Trim() -cne "$hash  $installerName") {
    throw 'The checksum file does not match the signed installer.'
}

$releases = Invoke-GitHubCli api --paginate --slurp "repos/$Repository/releases?per_page=100" | ConvertFrom-Json
$existingRelease = $null
foreach ($release in $releases | ForEach-Object { $_ }) {
    if ($release.tag_name -ceq $tag) { $existingRelease = $release }
    if (!$release.draft -and !$release.prerelease -and $release.tag_name -match '^v(\d+\.\d+\.\d+)$' -and
        [version]$Matches[1] -gt [version]$version) {
        throw "A newer stable release ($($release.tag_name)) is already published."
    }
}

$tagRef = "refs/tags/$tag"
$remoteTag = @(git ls-remote --tags origin $tagRef "$tagRef^{}")
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the release tag.' }
$tagLine = $remoteTag | Where-Object { $_.EndsWith('^{}') } | Select-Object -First 1
if (!$tagLine) { $tagLine = $remoteTag | Select-Object -First 1 }
if ($tagLine -and ($tagLine -split '\s+')[0] -cne $Commit) { throw "Tag $tag already points at another commit." }

if ($existingRelease) {
    if (!$existingRelease.draft) {
        if (!$tagLine -or $existingRelease.prerelease) { throw "Release $tag is not the expected stable release." }
        "Release $tag is already published for $Commit."
        return
    }
    if (!$tagLine -and $existingRelease.target_commitish -cne $Commit) {
        throw "The draft for $tag targets another commit."
    }
} else {
    Invoke-GitHubCli release create $tag --repo $Repository --target $Commit --title "AgentMeter Taskbar $tag" --generate-notes --draft
}

# A draft can be retried after an interrupted upload.
Invoke-GitHubCli release upload $tag $installer $checksum $feed --repo $Repository --clobber
Invoke-GitHubCli release edit $tag --repo $Repository --draft=false --latest
