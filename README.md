# DreadmoorVR

<img src="docs/assets/dreadmoovr-kraken-storm.png" alt="DreadmoorVR logo" width="420">

A VR mod for **Dreadmoor** (Unreal Engine 5.6) using UEVR and Steam Frame. It adds tracked arms and gesture controls for grappling, melee guard, fishing, crafting, and small-boat steering.

**Status:** private beta `1.0.0-beta.2`. Boat, fishing, and tracked-arm headset acceptance is still pending. See [v1 readiness](docs/testing/v1-readiness.md).

## Features

- Tracked VR arms and held-item alignment
- Gesture-based grappling and melee guard
- Fishing gestures for fish fights, reeling, and directional QTEs
- Crafting-bench cursor control
- First-person boat steering and throttle gestures with haptic detents
- Native third-person boat controls remain available

## Implementation

The mod is made of three parts:

- **Unreal content pak** cooked from `unreal/Dreadmoor` with UE 5.6
- **UEVR Lua bridge** in `src/scripts` for pose tracking, gestures, and game integration
- **Native C++ / OpenVR plugin** in `plugin` for Steam Frame input support

The repository also includes local Python tools for inspecting Unreal IoStore containers, Blueprint bytecode, and input mappings. See [`tools/re`](tools/re) and the [research notes](docs/research).

## Build and install

- [Install, update, and rollback](docs/release/INSTALL.md)
- Cook and deploy scripts: [`tools/cook.ps1`](tools/cook.ps1), [`tools/deploy.ps1`](tools/deploy.ps1)
- [Gesture smoke-test checklist](docs/testing/m3-gesture-checklist.md)
- [v1 readiness and remaining headset checks](docs/testing/v1-readiness.md)
- [Changelog](CHANGELOG.md)

## About the reverse engineering

This is authorized game-mod work. I built the local parsers and used them to trace shipped Blueprint and input behavior, then checked the findings against the Unreal project and runtime. The notes distinguish verified behavior from hypotheses and headset-only checks. The workflow and toolchain are documented in [`docs/research`](docs/research) and the [Unreal MCP setup notes](docs/setup/unreal-editor-mcp.md).

**Toolchain:** C++, Lua, Python, Unreal Engine 5.6, UEVR, OpenVR, SteamVR, EngineWire Unreal MCP.

## Developer note

AI helped trace and cross-check shipped-game calls and Unreal APIs. I verified the findings against the project and runtime, then did the headset tuning. I can read C++; I just can’t read a whole game’s worth of Blueprint bytecode by hand before breakfast.
