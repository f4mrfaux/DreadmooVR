# Install, update, rollback, and remove

This is the pre-release install guide for a local candidate. Follow the archive's own
`RELEASE-MANIFEST.json`; it records the source commit, whether the tree was dirty, and hashes of
every packaged file. Do not install a dirty candidate as a public v1 release.

## Requirements

- Windows and a Steam copy of Dreadmoor.
- UEVR installed and configured for Dreadmoor.
- SteamVR and Steam Frame controllers for the Frame input profile.
- The exact Dreadmoor, UEVR, SteamVR, and Frame software versions are not yet certified. Record
  those versions with headset test results; see `docs/testing/v1-readiness.md`.

## Install from a release archive

1. Close Dreadmoor and UEVR.
2. Keep a copy of the current UEVR profile and any existing Dreadmoor `~mods` files.
3. From the archive, copy `Game/Dreadmoor/Content/Paks/~mods/DreadmoorVR_P.*` to the same
   `~mods` path under the Dreadmoor installation.
4. Copy the contents of `UEVR/profile/` into
   `%APPDATA%/UnrealVRMod/Dreadmoor-Win64-Shipping/`, preserving the `scripts` and `plugins`
   subdirectories. Do not overwrite unrelated profile files.
5. In SteamVR's controller binding UI, select the supplied
   `UEVR/profile/dreadmoorvr_bindings_frame_controller.json` as the Dreadmoor binding source and save it
   as the active personal binding. Confirm the active binding after restarting SteamVR.
6. Start SteamVR, launch Dreadmoor, inject UEVR, and perform the startup checks in
   `docs/testing/m0-checklist.md` followed by the gesture checks in
   `docs/testing/m3-gesture-checklist.md`.

The repo deployment script is for this development machine and targets its configured game
path. Do not run it on another machine without first reviewing the paths near the top of
`tools/deploy.ps1`.

## Update

1. Close Dreadmoor and UEVR.
2. Keep the current archive and profile backup until the updated candidate passes the smoke
   checks.
3. Replace only the mod-owned `DreadmoorVR_P.*` files, `plugins/DreadmoorVR.dll`, shipped Lua
   scripts and libraries, and `dreadmoorvr_arms_tuning.lua` with the new archive copies.
4. Recheck the active SteamVR binding. The personal binding is managed by SteamVR and may not be
   updated by copying the reference JSON into the UEVR profile.
5. Launch and repeat the relevant checklist. Restore the backup if any core input or rendering
   path regresses.

## Roll back

Close the game and UEVR, then restore the prior copies of each mod-owned file from the backup.
If no backup exists, remove the mod-owned pak trio, `plugins/DreadmoorVR.dll`, shipped bridge
scripts and `dreadmoorvr_arms_tuning.lua`; restore the previous SteamVR binding in its binding
UI. Do not remove unrelated files from the profile or `~mods` directory.

## Uninstall

Close the game and UEVR. Remove only:

- `DreadmoorVR_P.utoc`, `DreadmoorVR_P.ucas`, and `DreadmoorVR_P.pak` from Dreadmoor's `~mods`.
- `DreadmoorVR.dll` and the DreadmoorVR Lua files/libraries installed by this archive from the
  Dreadmoor UEVR profile.
- `dreadmoorvr_arms_tuning.lua` and the DreadmoorVR binding file, if present.
- The Dreadmoor personal binding from SteamVR's binding UI; then restore the prior binding.

Do not delete the whole UEVR profile or the whole `~mods` directory. The repository's
`tools/deploy.ps1` manifest only applies to the development machine and should not be copied as
an end-user uninstaller.
