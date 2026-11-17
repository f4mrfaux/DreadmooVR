<#
.SYNOPSIS
  Capture the Dreadmoor game window (what UEVR mirrors from the headset) to JPEGs.

.DESCRIPTION
  Uses ffmpeg's gfxcapture filter (Windows Graphics Capture). It reads the window's own frames,
  so it works with DX12, with other windows on top, and without changing focus. Focus changes
  froze UEVR hand tracking on 2026-11-17, so nothing here touches the window.
  Needs an ffmpeg build with gfxcapture (FFmpeg 8+; the WinGet yt-dlp.FFmpeg build has it).

.PARAMETER Count     Number of frames (default 1).
.PARAMETER Interval  Seconds between frames (default 1).
.PARAMETER Out       Output folder (default build/snaps). Files are named HHmmss_N.jpg.
.PARAMETER Width     Scale to this width (default 1280; 0 = full size).

.EXAMPLE
  pwsh tools/snap.ps1                      # one frame
  pwsh tools/snap.ps1 -Count 6 -Interval 1 # six frames, a second apart
#>
param(
    [int]$Count = 1,
    [double]$Interval = 1,
    [string]$Out = (Join-Path $PSScriptRoot '..\build\snaps'),
    [int]$Width = 1280
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Process -Name 'Dreadmoor-Win64-Shipping' -ErrorAction SilentlyContinue)) { throw 'Dreadmoor is not running.' }
New-Item -ItemType Directory -Force $Out | Out-Null
$src = 'gfxcapture=window_exe=(?i)Dreadmoor-Win64-Shipping\.exe:capture_cursor=0,hwdownload,format=bgra'
if ($Width -gt 0) { $src += ",scale=${Width}:-1" }
$stamp = Get-Date -Format 'HHmmss'
for ($i = 1; $i -le $Count; $i++) {
    $file = Join-Path $Out ("{0}_{1}.jpg" -f $stamp, $i)
    & ffmpeg -hide_banner -loglevel error -y -filter_complex $src -frames:v 1 -q:v 4 $file
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file)) { throw "capture $i failed" }
    (Resolve-Path $file).Path
    if ($i -lt $Count) { Start-Sleep -Milliseconds ([int]($Interval * 1000)) }
}
