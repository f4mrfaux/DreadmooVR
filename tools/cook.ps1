<#
.SYNOPSIS
  Cooks the mod pak with UE 5.6 and checks its contents.

.DESCRIPTION
  BuildCookRun cooks the whole project; chunk 1 (everything under /Game/DreadmoorVR, see
  Config/DefaultGame.ini) lands in pakchunk1-Windows.{utoc,ucas,pak}. Those are copied to
  build/pak/ as DreadmoorVR_P.* and listed with tools/re/list_container.py, which fails the
  cook if any asset outside /Game/DreadmoorVR got in (a stand-in would overwrite the game's
  own asset).
  Never uses UE 5.8.
#>
[CmdletBinding()]
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$UE = 'C:\Program Files\Epic Games\UE_5.6'
$Project = Join-Path $Repo 'unreal\Dreadmoor\Dreadmoor.uproject'
$Stage = Join-Path $Repo 'build\stage'
$Out = Join-Path $Repo 'build\pak'
$Log = Join-Path $Repo 'build\cook.log'

if (-not (Test-Path "$UE\Engine\Build\BatchFiles\RunUAT.bat")) { throw "UE 5.6 not found at $UE" }

$open = Get-CimInstance Win32_Process -Filter "Name like 'UnrealEditor%'" |
    Where-Object { $_.CommandLine -like '*Dreadmoor.uproject*' }
if ($open) { throw "Close the Unreal editor (pid $($open.ProcessId -join ',')) before cooking; it locks the project's assets." }

New-Item -ItemType Directory -Force (Split-Path $Log), $Out | Out-Null
Remove-Item "$Out\DreadmoorVR_P.*" -ErrorAction SilentlyContinue

$uatArgs = @('BuildCookRun', "-project=$Project", '-platform=Win64', '-clientconfig=Shipping',
    '-cook', '-stage', '-pak', '-iostore', '-package', '-noP4', '-utf8output', '-unattended',
    '-archive', "-archivedirectory=$Stage")
if ($SkipBuild) { $uatArgs += '-skipbuild' } else { $uatArgs += '-build' }

Write-Host "Cooking (log: $Log) ..."
& "$UE\Engine\Build\BatchFiles\RunUAT.bat" @uatArgs *> $Log
if ($LASTEXITCODE -ne 0) { throw "BuildCookRun failed (exit $LASTEXITCODE). See $Log" }

$chunk = Get-ChildItem $Stage -Recurse -Filter 'pakchunk1-Windows.utoc' | Select-Object -First 1
if (-not $chunk) { throw "No pakchunk1-Windows.utoc under ${Stage}: chunk 1 was not generated. Check the AssetManagerSettings rule." }
foreach ($ext in 'utoc', 'ucas', 'pak') {
    Copy-Item (Join-Path $chunk.DirectoryName "pakchunk1-Windows.$ext") (Join-Path $Out "DreadmoorVR_P.$ext")
}

python -I (Join-Path $Repo 'tools\re\list_container.py') (Join-Path $Out 'DreadmoorVR_P.utoc') --allow 'Dreadmoor/Content/DreadmoorVR/'
if ($LASTEXITCODE -ne 0) {
    Remove-Item "$Out\DreadmoorVR_P.*"
    throw 'The pak holds assets outside /Game/DreadmoorVR. Removed it; fix the stand-in exclusions and cook again.'
}
Write-Host "OK: $Out\DreadmoorVR_P.{utoc,ucas,pak}"
