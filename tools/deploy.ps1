<#
.SYNOPSIS
  Deploys the Dreadmoor VR mod: bridge scripts and profile settings to the UEVR profile folder,
  and the cooked pak to the game's ~mods folder.

.DESCRIPTION
  Writes only to:
    %APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\
    <game>\Dreadmoor\Content\Paks\~mods\
  A manifest (deployed.txt) in the profile folder records every file this script wrote. Files
  it wrote last time and no longer ships are removed; nothing else is ever touched.
  config.txt is merged key by key, so settings changed in the UEVR menu survive.

.PARAMETER Probe   Also deploy src/scripts/m0_probe.lua (M0 only).
.PARAMETER NoPak   Skip the pak half.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Probe,
    [switch]$NoPak
)
$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$UevrDir = Join-Path $env:APPDATA 'UnrealVRMod\Dreadmoor-Win64-Shipping'
$Mods = 'D:\SteamLibrary\steamapps\common\DREADMOOR\Dreadmoor\Content\Paks\~mods'
$Manifest = Join-Path $UevrDir 'deployed.txt'

# What ships: destination -> source
$plan = [ordered]@{}
foreach ($f in Get-ChildItem (Join-Path $Repo 'src\scripts') -Filter *.lua) {
    if ($f.Name -eq 'm0_probe.lua' -and -not $Probe) { continue }
    $plan[(Join-Path $UevrDir "scripts\$($f.Name)")] = $f.FullName
}
# Modules live in scripts\lib so UEVR does not autoload them; main.lua requires them.
foreach ($f in Get-ChildItem (Join-Path $Repo 'src\scripts\lib') -Filter *.lua) {
    $plan[(Join-Path $UevrDir "scripts\lib\$($f.Name)")] = $f.FullName
}
$dataDir = Join-Path $Repo 'src\data'
if (Test-Path $dataDir) {
    foreach ($f in Get-ChildItem $dataDir -File | Where-Object Name -ne '.gitkeep') {
        $plan[(Join-Path $UevrDir $f.Name)] = $f.FullName
    }
}
if (-not $NoPak) {
    $pakDir = Join-Path $Repo 'build\pak'
    $paks = @(Get-ChildItem $pakDir -Filter 'DreadmoorVR_P.*' -ErrorAction SilentlyContinue)
    if ($paks.Count -ne 3) { throw "Expected DreadmoorVR_P.utoc/.ucas/.pak in $pakDir; run tools/cook.ps1 first, or pass -NoPak." }
    foreach ($f in $paks) { $plan[(Join-Path $Mods $f.Name)] = $f.FullName }
}

# Remove files we shipped before but no longer ship.
$previous = @()
if (Test-Path $Manifest) { $previous = Get-Content $Manifest | Where-Object { $_ } }
foreach ($old in $previous) {
    if (-not $plan.Contains($old) -and (Test-Path $old)) {
        if ($PSCmdlet.ShouldProcess($old, 'Remove (no longer shipped)')) { Remove-Item $old }
    }
}

# Copy.
foreach ($dst in $plan.Keys) {
    if ($PSCmdlet.ShouldProcess($dst, "Copy from $($plan[$dst])")) {
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $plan[$dst] $dst -Force
    }
}

# Merge config.txt.
$cfgSrc = Join-Path $Repo 'profile\config.txt'
$cfgDst = Join-Path $UevrDir 'config.txt'
if ($PSCmdlet.ShouldProcess($cfgDst, 'Merge settings')) {
    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $cfgDst) { $lines.AddRange([string[]](Get-Content $cfgDst)) }
    foreach ($kv in Get-Content $cfgSrc | Where-Object { $_ -match '=' }) {
        $key = $kv.Split('=')[0]
        $i = $lines.FindIndex({ param($l) $l.StartsWith("$key=") })
        if ($i -ge 0) { $lines[$i] = $kv } else { $lines.Add($kv) }
    }
    New-Item -ItemType Directory -Force $UevrDir | Out-Null
    Set-Content $cfgDst $lines
}

if ($PSCmdlet.ShouldProcess($Manifest, 'Write manifest')) {
    New-Item -ItemType Directory -Force $UevrDir | Out-Null
    Set-Content $Manifest @($plan.Keys)
}
Write-Host "Deployed $($plan.Count) files."
