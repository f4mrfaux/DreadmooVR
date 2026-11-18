# Dreadmoor VR

A VR mod for Dreadmoor (Unreal Engine 5.6.1) on the Steam Frame. Real arms and hands, and
gesture fishing, crafting, hook gun, melee guard, and small-boat controls. It has two halves: a content pak cooked from
`unreal/Dreadmoor` with UE 5.6, and a UEVR Lua bridge in `src/scripts`. Made with the
developer's blessing, not for sale.

## Where things are deployed

`tools/deploy.ps1` writes only to these two places. Delete both to remove the mod completely.

- Pak: `D:\SteamLibrary\steamapps\common\DREADMOOR\Dreadmoor\Content\Paks\~mods\DreadmoorVR_P.*`
- UEVR profile: `%APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\`

## Release status

This repository is still a pre-release candidate. See [v1 readiness](docs/testing/v1-readiness.md)
for headset gates and supported-version status. Release and rollback instructions are in
[docs/release/INSTALL.md](docs/release/INSTALL.md); user-visible changes are tracked in
[CHANGELOG.md](CHANGELOG.md). After committing a validated tree, create the beta archive with
`tools/package-release.ps1 -Version 1.0.0-beta.1`. `-AllowDirtyCandidate` is for local, clearly
marked builds only. Do not label an archive `1.0.0` until the headset gates pass.

## Documents

- Design: [docs/superpowers/specs/2026-11-15-dreadmoor-vr-gestures-design.md](docs/superpowers/specs/2026-11-15-dreadmoor-vr-gestures-design.md)
- Plan 1: [docs/superpowers/plans/2026-11-15-dreadmoor-vr-foundations.md](docs/superpowers/plans/2026-11-15-dreadmoor-vr-foundations.md)
- Research: [docs/research](docs/research), RE scripts: [tools/re](tools/re)
- Editor MCP setup: [docs/setup/unreal-editor-mcp.md](docs/setup/unreal-editor-mcp.md)
- Headset checks: [M3 gestures](docs/testing/m3-gesture-checklist.md), [v1 readiness](docs/testing/v1-readiness.md)
