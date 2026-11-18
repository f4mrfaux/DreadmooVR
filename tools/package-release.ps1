<#
.SYNOPSIS
  Assemble a portable DreadmoorVR candidate archive from the current built artifacts.
.DESCRIPTION
  Does not build or cook. Requires the plugin DLL and cooked pak trio to already exist.
  Dirty trees are rejected unless -AllowDirtyCandidate is supplied; dirty candidates are
  clearly marked in the manifest and archive name. The optional legacy settings bridge is only
  packaged when -Bridge is supplied, matching tools/deploy.ps1.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$')][string]$Version,
    [switch]$AllowDirtyCandidate,
    [switch]$Bridge
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Git = Get-Command git -ErrorAction Stop
$status = @(& $Git.Source -C $Repo status --porcelain)
if ($LASTEXITCODE -ne 0) { throw 'Could not read git status.' }
$dirty = $status.Count -gt 0
if ($dirty -and -not $AllowDirtyCandidate) {
    throw 'The working tree has uncommitted changes. Commit the release state or pass -AllowDirtyCandidate for a clearly marked local archive.'
}
$commit = (& $Git.Source -C $Repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read the git commit.' }
$plugin = Join-Path $Repo 'build\plugin\Release\DreadmoorVR.dll'
$pakDir = Join-Path $Repo 'build\pak'
$pakFiles = @('DreadmoorVR_P.utoc','DreadmoorVR_P.ucas','DreadmoorVR_P.pak')
$required = @($plugin) + @($pakFiles | ForEach-Object { Join-Path $pakDir $_ }) + @(
    (Join-Path $Repo 'src\scripts\m2_arms.lua'),
    (Join-Path $Repo 'src\scripts\m3_gestures.lua'),
    (Join-Path $Repo 'src\data\dreadmoorvr_arms_tuning.lua'),
    (Join-Path $Repo 'profile\steamvr\dreadmoorvr_bindings_frame_controller.json')
)
foreach ($path in $required) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required release input is missing: $path" } }

$dist = Join-Path $Repo 'dist'
$stageRoot = Join-Path $Repo 'build\release-stage'
$folderName = "DreadmoorVR-$Version" + $(if ($dirty) { '-DIRTY-CANDIDATE' } else { '' })
$stage = Join-Path $stageRoot $folderName
$zip = Join-Path $dist "$folderName.zip"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Force $stage, $dist | Out-Null
$profile = Join-Path $stage 'UEVR\profile'
$scripts = Join-Path $profile 'scripts'
$gameMods = Join-Path $stage 'Game\Dreadmoor\Content\Paks\~mods'
New-Item -ItemType Directory -Force $scripts, (Join-Path $scripts 'lib'), (Join-Path $profile 'plugins'), $gameMods | Out-Null

$excludedScripts = @('m0_probe.lua','m1_probe.lua')
if (-not $Bridge) { $excludedScripts += 'main.lua' }
Get-ChildItem (Join-Path $Repo 'src\scripts') -Filter '*.lua' -File |
    Where-Object { $_.Name -notin $excludedScripts } |
    Copy-Item -Destination $scripts
Copy-Item (Join-Path $Repo 'src\scripts\lib\*.lua') (Join-Path $scripts 'lib')
Copy-Item $plugin (Join-Path $profile 'plugins\DreadmoorVR.dll')
Copy-Item (Join-Path $Repo 'src\data\dreadmoorvr_arms_tuning.lua') $profile
Copy-Item (Join-Path $Repo 'profile\steamvr\dreadmoorvr_bindings_frame_controller.json') (Join-Path $profile 'dreadmoorvr_bindings_frame_controller.json')
foreach ($name in $pakFiles) { Copy-Item (Join-Path $pakDir $name) $gameMods }
Copy-Item (Join-Path $Repo 'docs\release\INSTALL.md') $stage
Copy-Item (Join-Path $Repo 'CHANGELOG.md') $stage
$testDocs = Join-Path $stage 'docs\testing'
New-Item -ItemType Directory -Force $testDocs | Out-Null
Copy-Item (Join-Path $Repo 'docs\testing\m0-checklist.md') $testDocs
Copy-Item (Join-Path $Repo 'docs\testing\m3-gesture-checklist.md') $testDocs

$files = @(Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{
        path = $_.FullName.Substring($stage.Length + 1).Replace('\','/')
        size = $_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$manifest = [ordered]@{
    product = 'DreadmoorVR'
    version = $Version
    channel = $(if ($dirty) { 'dirty-candidate' } else { 'candidate' })
    source_commit = $commit
    working_tree_dirty = $dirty
    packaged_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    files = $files
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'RELEASE-MANIFEST.json') -Encoding utf8
Compress-Archive -LiteralPath $stage -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Created $zip"
Write-Host "Channel: $($manifest.channel); source: $commit; files: $($files.Count)"
