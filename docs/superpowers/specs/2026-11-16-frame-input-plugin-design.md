# DreadmoorVR Steam Frame input plugin: design

Approved by Bob on 2026-11-16 ("Architecture Decision Approved: proceed with Option 2"). The
project's hardware spec is "Dreadmoor VR: Steam Frame Native Specification v1.0", recorded
below under Requirements.

## Intent

The Steam Frame is the primary target hardware, not a compatibility layer pretending to be
Oculus Touch. Input has to be native and verified during normal play. The working renderer
(UEVR nightly 01143) must not be destabilized.

## Requirements (spec v1.0)

**Immediate**

1. Use Valve's `frame_controller` input definition and a native SteamVR binding.
2. Nightly 01143 stays the rendering baseline.
3. Right ABXY are mapped independently and correctly: X interacts, it doesn't jump.
4. The left D-pad works without shifting or duplicate actions.
5. Separate Menu (Pause) and View (Inventory) inputs, as the final goal.
6. Both 6DoF controller poses are preserved.
7. Read-only instrumentation verifies input during normal play, with no scripted button
   sequences.

**Future**

8. Tracked hands and arms with IK.
9. Right-hand aiming independent of the head.
10. Context-aware gripping.
11. Investigate SteamVR skeletal input at the fidelity the device actually provides.
12. Keep analogue and touch values instead of reducing everything to digital Xbox buttons.

## Constraints

- Don't modify SteamVR driver files.
- Don't port the fork's renderer.
- Use the gamepad layer only for the game functions that need it.
- Keep these layers separate and testable on their own: capture, mapping, tracking,
  interaction.
- Nothing counts as working until it's verified in the running game.
- No claims of full hand tracking from capacitive sensors.
- No repetitive manual button sequences.
- Keep a reversible known-good baseline before every substantial change.
- Don't register a competing action manifest or replace UEVR's action sets. If a required
  action is missing, report it as a limitation.
- **Stop condition:** if the plugin can't reach the needed OpenVR actions through the
  nightly's manifest, document why and propose a narrow workaround or SDK extension.

## Approaches considered

1. **Native binding + Lua only.** Cheapest, but it can't read analogue or touch values (the
   nightly's Lua is digital-only), and the separate Menu/View requirement is unproven.
2. **Native binding + Lua + a small C++ plugin. Chosen.** It meets the whole spec, and the
   plugin SDK is public.
3. **A custom UEVR build with the fork's Frame commits.** Blocked: UESDK is private.

## Layers

- **C++ plugin (`DreadmoorVR.dll`):** hardware and runtime input, analogue values, skeletal
  data, diagnostics. It's an input adapter, not a renderer or gamepad replacement.
- **Lua bridge:** Dreadmoor gameplay logic and Unreal object work.
- **Pak:** assets.
- **UEVR nightly:** rendering, tracking, game compatibility.

## Verified facts (nightly commit 4ee5c6b, public repo)

- Plugin SDK 2.39 (`include/uevr/API.h`). Entry points are `uevr_plugin_required_version`
  and `uevr_plugin_initialize`.
- `functions->dispatch_lua_event(name, data)` reaches Lua through
  `uevr.sdk.callbacks.on_lua_event(fn(name, data))` (`ScriptContext.cpp:181, 1479`).
- The `vr` interface has `is_openvr`, `is_openxr`, `get_action_handle`, `is_action_active`,
  `is_action_active_any_joystick` and `get_joystick_axis`. There's no analogue or skeletal
  call, so the plugin reads those through OpenVR (`vr::VRInput()`, headers at
  `dependencies/openvr/headers`) using UEVR's action handles, and never calls
  `UpdateActionState` itself.
- The nightly's `actions.json` declares `Squeeze` (vector1), `SkeletonLeftHand` and
  `SkeletonRightHand` (skeleton), `Trigger` and `Grip` (boolean), `Touchpad` (vector2),
  `TouchpadClick` and `Teleport` (boolean), plus the face buttons, the D-pad and
  `SystemButton`.
- `VR.cpp` never turns `TouchpadClick` or `Teleport` into gamepad buttons, so they're spare
  candidates for Menu and View.
- UEVR gates every controller input except Start on `is_hmd_active()`. Frame passthrough
  makes the headset read as inactive, which kills input.

## Phase 1 deliverable (this plan only)

A minimal plugin that:
1. confirms it loaded
2. lists the exact available action handles and their types
3. shows at least one verified live controller state change, captured passively
4. delivers a C++ → Lua event successfully
5. leaves Dreadmoor's 3D rendering working

Phases 2 (telemetry) and 3 (game integration) wait for Bob's go-ahead after Phase 1.
