# Frame input plugin, Phase 1 evidence (2026-11-16)

Plan: `docs/superpowers/plans/2026-11-16-frame-input-plugin-phase1.md`. Run: nightly 01143
(4ee5c6b), injected 14:15:59, Bob played normally with passthrough off.

Evidence files in `build/phase1/` (not committed):
- `uevr_log.txt`: the full UEVR log
- `dreadmoorvr_lines.txt`: the 567 plugin and probe lines
- `render_1418.jpg`: the game window at 14:18

## Deliverables

| # | Deliverable | Result | Evidence |
|---|---|---|---|
| 1 | Load confirmation | **Pass** | `[PluginLoader] Loaded …\plugins\DreadmoorVR.dll`, `requires version 2.39.0`, `[DreadmoorVR.dll] loaded; SDK 2.39.0; runtime openvr=1 openxr=0` |
| 2 | Action handles and types | **Pass** | 29 of 29 manifest actions, all with `err=0` and `binding_err=0` (table below) |
| 3 | A live controller state change | **Pass, with a limitation** | Plugin: `Joystick@L` (50 changes), `Squeeze@L/R` inactive → 0.0, `ThumbRestTouch*`, skeleton tracking level. Probe: `act=BButtonRight@R pad=0x4000`, ×2 |
| 4 | C++ → Lua delivery, received | **Pass** | Probe: `plugin=dreadmoorvr_ping:1`. Plugin: `Lua -> C++ ack received: 'ping 1' (round trip verified after 1 ping(s))`. Probe: `plugin=dreadmoorvr_input:SkeletonLeftHand@L=tracking_level=1` |
| 5 | 3D rendering preserved | **Pass on the desktop mirror; headset confirmation pending** | `render_1418.jpg` shows the full 3D scene. The only UEVR errors are the same startup retries as the morning's working runs, plus one compositor submit error at startup |

## Hand identity

| Hand | Source handle | Device | Controller type |
|---|---|---|---|
| L | 0x20008ca000000009 | 1 | frame_controller |
| R | 0x20008ca00000000a | 2 | frame_controller |

## Action inventory (bindings from our native Frame binding)

| Action | Type | Bound to (Frame) |
|---|---|---|
| AButtonRight | boolean | right `a` |
| AButtonLeft | boolean | right `b` |
| BButtonRight | boolean | right `x` |
| BButtonLeft | boolean | right `y` |
| DPad_Up / Right / Down / Left | boolean | left `dpad_up` / `dpad_right` / `dpad_down` / `dpad_left` |
| Trigger | boolean | left and right `trigger` (click) |
| Grip | boolean | left and right `bumper` (click) |
| Squeeze | vector1 | left and right `grip` (pull) |
| Joystick / JoystickClick | vector2 / boolean | left and right `thumbstick` |
| ThumbRestTouchLeft / Right | boolean | left / right `thumbrest` (touch) |
| SystemButton | boolean | right `menu` **and** left `view` |
| SkeletonLeftHand / Right | skeleton | left / right `skeleton` |
| Pose, GripPose | pose | `tip`, `handgrip` |
| Haptic | vibration | both hands |
| HeadsetOnHead, Touchpad, TouchpadClick, Teleport, A/B ButtonTouch L/R | — | **unbound** |

## Acceptance requirements

- **Polling order and currency:**
  - UEVR runs `VR` → `PluginLoader` → `LuaLoader` (`Mods.cpp:14–18`).
  - `VR::on_pre_engine_tick` calls `UpdateActionState` at its end (`VR.cpp:1386`). On frames
    where UEVR skips its viewport draw, it skips the update.
  - So the plugin's pre-tick reads data refreshed in the same tick, or at most one frame old.
  - On the gamepad path it's VR first, then Lua.
  - **Correction to an earlier claim:** Lua's gamepad callback runs *after* UEVR's mapping.
- **Round trip:** proven by the ack (deliverable 4).
- **Read-only listener only:**
  - `main.lua` (the gameplay bridge) isn't deployed, and `deploy.ps1` now needs `-Bridge`
    to ship it.
  - The probe's only write is the ack event.
- **Error codes:** every action logs `err` (GetActionHandle) and `binding_err`
  (GetActionBindingInfo), and every value read logs `err<N>` on failure. All 29 handles came
  back `err=0`.
- **Dropped telemetry:** logged ("telemetry cap reached (200 lines); 436 changes dropped").
- **Renderer and config untouched:**
  - The nightly was used as-is.
  - `config.txt`'s SHA-256 was identical before and after the deploy.
  - The config merge is now opt-in (`-Config`).
- **Rollback:** `powershell -File tools/deploy.ps1 -RemovePlugin` deletes only
  `plugins\DreadmoorVR.dll`.

## Validation items 1–6

1. **Are the required actions declared?**
   - Declared: `Squeeze` (analogue grip), the skeletons, and two spare unmapped booleans
     (`TouchpadClick`, `Teleport`).
   - **Missing: there's no analogue trigger action.** `Trigger` is boolean only. That's a
     limitation of the manifest.
   - There's no separate Start or Back action.
2. **Bound for `frame_controller`?** Yes for everything in the table above. `Touchpad`,
   `TouchpadClick`, `Teleport`, `HeadsetOnHead` and the face-button touch actions are
   unbound in our binding.
3. **Observed without disrupting UEVR?** Yes, as far as tested. The plugin never calls
   `UpdateActionState`. After the plugin loaded, UEVR's mapping still delivered Frame X → Xbox
   X (`pad=0x4000`) to the game.
4. **Analogue values meaningful?**
   - **Unknown.** `Squeeze` reads 0.0 when idle, but no pull was captured before the cap.
   - The trigger has no analogue action at all (item 1).
5. **Skeletal data?** Accessible. `GetSkeletalTrackingLevel` returns 1, which is
   `VRSkeletalTracking_Partial`, on both skeleton actions. Only the level was checked; no
   bone data was read.
6. **Separate Menu/View without duplicate Start/Back?**
   - **Not yet.** Both are bound to `SystemButton`, so a tap is Start and a hold is Back.
   - `TouchpadClick` and `Teleport` are spare and never mapped by UEVR, so they could carry
     Menu and View separately. That's Phase 3 and untested.

## Bonus finding: X no longer jumps

Probe line: `act=BButtonRight@R pad=0x4000`. The Frame X button reached the game as Xbox X
alone, not `0x5000` (A+X). This held with our native Frame binding and passthrough off.
Only X was observed; the other buttons weren't pressed in this session.

## Limitations to address in Phase 2

- **The plugin's telemetry budget went to stick noise:** 50 of its 200 lines were
  `Joystick@L` steps of 0.1, and 436 changes were dropped, including any button edges after
  the cap. Phase 2 should log analogue axes separately from digital edges, with their own
  rate or threshold, so digital edges are never starved.
- The skeleton is read once per action, but its log key says `@L` even for
  `SkeletonRightHand`. That's cosmetic.
- 3D rendering in the headset still needs Bob's confirmation; the desktop mirror is confirmed.
