# Unreal editor + MCP setup (2026-11-15)

How the mod's authoring editor is set up so Claude Code can drive it.

## Pieces

| Piece | Where | Notes |
|---|---|---|
| Unreal Engine 5.6 | `C:\Program Files\Epic Games\UE_5.6` | Matches the game's 5.6.1. Assets cooked in any other minor version won't load in the game. UE_5.8 is also installed; don't use it for this mod. |
| Mod project | `unreal/Dreadmoor/Dreadmoor.uproject` | C++ project, `EngineAssociation` 5.6. Named **Dreadmoor** to match the game's project, so cooked content mounts at the same `/Game/...` paths (`Dreadmoor/Content/...` in the pak). |
| EngineWire 0.6.0 | `unreal/Dreadmoor/Plugins/EngineWire` | MCP plugin from [ChiR24/Unreal_mcp](https://github.com/ChiR24/Unreal_mcp), MIT. Source release from `Downloads\EngineWire-0.6.0`. Editor-only modules, so it is not cooked into the mod. |
| MCP client config | `.mcp.json` (repo root) | Runs `npx unreal-engine-mcp-server@0.6.0` (stdio proxy, Node 20.19+). `UE_PROJECT_PATH` lets it read the token itself, so no token is stored in config. |

Why EngineWire: it supports UE 5.0–5.8, is active and MIT-licensed, and edits Blueprint event
graphs, Animation Blueprints, skeletons, Control Rig/IK, and runs PIE with screenshots. Epic's
own MCP plugin is 5.8-only. The backup is db-lyon/ue-mcp, which has no 5.6 prebuilt binaries.

## Build

```powershell
& "C:\Program Files\Epic Games\UE_5.6\Engine\Build\BatchFiles\Build.bat" DreadmoorEditor Win64 Development "-Project=C:\Users\Bob\source\dreadmooreVR\unreal\Dreadmoor\Dreadmoor.uproject" -WaitMutex
```

First build took about 4 minutes with VS 2022 and finished with 0 errors. The log is in `unreal/build.log`.
Call `Build.bat` from PowerShell. Calling it through `cmd //c` from Git Bash breaks the quoting.

## Run

1. Launch `UnrealEditor.exe` from UE_5.6 with the `.uproject`.
2. Within about 15 s the plugin listens on `127.0.0.1:3000/mcp` and writes
   `unreal/Dreadmoor/Saved/MCP/capability-token`. Treat the token as a password. Clients send it
   in the `X-MCP-Capability-Token` header. Delete the file and restart the editor to rotate it.
3. Claude Code loads `.mcp.json` at startup and asks you to approve the `unreal-engine` server.
   The editor must already be running.

The server exposes one tool, `unreal`, with four operations: search, describe, execute and configure.

## Status

- Verified: the UE 5.6 editor loads EngineWire; hand-sent MCP `initialize`, `search`, `describe`, and read-only `execute` calls work over HTTP.
- Not yet verified: Claude Code's stdio proxy attachment and EngineWire Blueprint graph writes in UE 5.6.
- The mod's cooking and pak packaging workflow is in `tools/cook.ps1`; this MCP setup note does not validate a fresh cook.

### Editor input crash observed 2026-11-18

Stock EngineWire 0.6.0 crashed after a `control_editor.simulate_input` key tap in the AnimBP
preview viewport. The delayed `ScheduleKeyReleaseForMcp` lambda dereferenced a null PIE world at
`Plugins/EngineWire/Source/EngineWire/Private/Domains/ControlEditor/McpEditorInput.cpp:63` and
raised an access violation at `0x60`. The local ignored EngineWire source now null-checks the world
settings pointer; UE 5.6 rebuilt the plugin successfully, and the same editor-viewport key tap
survived its delayed release. This workaround is local to the ignored plugin copy and is not part
of the mod or an upstream fix. Reapplying or replacing EngineWire with stock 0.6.0 restores the
crash risk.

The AnimBP preview screenshot showed `SKM_Quinn_Simple`, not the protagonist mesh referenced by
`BP_VRArms.Body`. Do not use that preview as visual validation of finger or arm shapes. Source and
Lua harness checks remain useful, but actual pose-shape validation needs the game mesh in a working
preview or a pose-labeled in-game capture.

### Game Blueprints versus mod assets

EngineWire reads editor assets registered in the `unreal/Dreadmoor` project. It does not mount
the installed game's cooked IoStore containers as editable Blueprint assets. The game Blueprints
are cooked; the editor graph source is not present in those packages, so copying the cooked files
into this project's `Content` folder will not make their graphs inspectable through MCP. In this
session the editor was correctly running this project, but its world was `/Temp/Untitled_1` and
the asset registry confirmed that the two boat Blueprint paths were absent. Use the read-only
`tools/re` IoStore/Kismet pipeline for shipped game Blueprint bytecode; use EngineWire for the
mod project's editable assets. Record which source was used in research notes so cooked-code
findings are not described as live editor-graph reads.
