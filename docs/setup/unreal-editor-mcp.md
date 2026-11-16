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

- Verified: the build succeeds, the editor loads the plugin, and a hand-sent `initialize` request returns HTTP 200 with the expected server info.
- Not yet verified: tool calls from Claude Code, and whether Blueprint node creation and wiring work in 5.6.
- Not yet set up: cooking and pak packaging for the game.
