# Steam Frame input with UEVR (2026-11-16)

The engineering directive's Task A (P0) is native Steam Frame input. This page records what is
known, from logs, source and Valve's documentation, and what still needs a runtime test.
**Status: not yet runtime-tested.**

## What is in use

- **Runtime:** OpenVR through SteamVR, streamed over vrlink. UEVR's log reports
  `Requested runtime: openxr_loader.dll`, but it writes OpenVR binding files and sets up the
  OpenVR overlay, so the injector's OpenVR choice wins.
- **Devices:** `frame_controller` (both hands) and `frame_hmd` (vrserver.txt).
- **UEVR:** nightly 01143, mainline commit 4ee5c6b.

## The Frame's layout

From the Frame driver's `frame_controller_profile.json` and Valve's
[Frame input page](https://partner.steamgames.com/doc/steamhardware/steamframe/input):

- **Right controller:** A, B, X, Y, menu, system, bumper, trigger, grip, thumbstick, thumbrest.
- **Left controller:** D-pad (up, right, down, left), view, system, bumper, trigger, grip,
  thumbstick, thumbrest.

The left D-pad sits where a Touch controller has X/Y. The profile's `mirror_mappings` pair
left `dpad_up/right/down/left` with right `y/b/a/x`.

## Why the controls were wrong

1. **UEVR ships no Frame binding.** It writes `actions.json` and bindings for knuckles, Touch,
   Vive and Rift (`VR.cpp` `initialize_openvr_input`), and it **rewrites them at every start**.
   So a file added to the profile folder is thrown away.
2. **SteamVR falls back** in this order: Frame binding, then OpenXR generic, then Oculus
   Touch remapped to the Frame (Valve's page). Dreadmoor was using UEVR's
   `bindings_oculus_touch.json`, auto-remapped (`getactions.json`:
   `current_binding_url` = that file).
3. **The remap merges buttons.** Valve's page says the Touch top button (B/Y) lands on all
   three upper Frame buttons: left D-pad left/up/right and right X/Y/B. That is the
   "X was D-pad" and doubled presses Bob saw.
4. **UEVR's own gamepad mapping** (mainline `VR.cpp` `on_xinput_get_state`):
   - right A action → Xbox A
   - right B action → Xbox X
   - left A action (the Touch X button) → Xbox B
   - left B action (the Touch Y button) → Xbox Y
   - grip → LB/RB; trigger → LT/RT; stick click → L3/R3
   - system action: a tap is Start; a hold over 0.5 s is Back
5. **UEVR rebuilds the pad after the Lua callbacks.** It zeroes `wButtons` and sets them
   again, so a Lua face-button rewrite cannot work. It was tried and removed (commit 0f14f6e).
6. **D-pad shifting** (`VR_DPadShifting`) was on. The bridge now sets it to `false` at load.
7. **A second XInput slot.** A UEVR plugin author found the Frame makes games poll XInput
   index 1 as well, probably Steam Input's emulated pad
   ([SystemReShock PR #14](https://github.com/gwizdek/SystemReShock-UEVR-Plugin/pull/14)).
   UEVR serves only the lowest slot. Bob disabled Steam Input for Dreadmoor at 10:51. Whether
   the game still reads slot 1 is not yet checked.

## Two routes to native Frame input

### Route 1: a personal SteamVR binding (in place, untested)

A Frame binding for UEVR's actions was saved through SteamVR's own Binding UI API
(vrserver, `localhost:27062`). The UI's requests are gated only by a `Referer` header. The
save went through `POST /input/savebinding.action` with `save_type: "personal"`.

- Source: `profile/steamvr/dreadmoorvr_bindings_frame_controller.json`.
- SteamVR stored it as `vr-input-workshop://3840998860` (vrserver log: "Save with task.
  Type: 2"). `getactions.json` now reports it as Dreadmoor's `current_binding_url` for
  `frame_controller`.
- SteamVR's install files are not touched. UEVR's per-start rewrite doesn't affect it,
  because it lives in Steam's binding storage.
- **Persistence across UEVR and SteamVR restarts is not yet tested.**

Planned mapping, to be confirmed by a runtime test:

| Frame button | SteamVR action | UEVR → Xbox | Dreadmoor on foot |
|---|---|---|---|
| Right A | `abuttonright` | A | Jump |
| Right B | `abuttonleft` | B | (unknown) |
| Right X | `bbuttonright` | X | Interact |
| Right Y | `bbuttonleft` | Y | Reload |
| Left D-pad | `dpad_up/right/down/left` | D-pad | Item slots (likely) |
| Bumpers | `grip` | LB / RB | Map / Pin |
| Triggers | `trigger` | LT / RT | Secondary / Primary use |
| Grips | `squeeze` | (none) | free for the bridge's grab gestures |
| Sticks | `joystick` + `joystickclick` | LS / RS, L3 / R3 | Move, look; sprint, flashlight |
| Right menu, left view | `systembutton` | tap Start, hold Back | Pause; Inventory |

Two compromises in this table:
- View and menu share UEVR's one system action, so Inventory is a long press.
- UEVR's right-hand buttons pass through its B/X swap, so the Frame's B is routed to the
  left-A action to come out as Xbox B.

### Route 2: joeyhodge's UEVR fork (not tried)

[joeyhodge/UEVR](https://github.com/joeyhodge/UEVR), branch `ue57performance`, has native
Frame support in both the OpenVR and OpenXR paths:

- `get_frame_controller_mask`, `frame_controller_profiles`, and a `uevr::steam_frame` module
  in `VR.cpp` and `OpenXR.cpp`
- separate start, back, bumper and trigger-axis actions

Its releases (for example `111426XRAsyncXRWaitFrameOptions`, 2026-11-13) ship `uevr.zip`.
It's an unofficial fork, so it needs Bob's approval to download, and it would replace
nightly 01143 as the foundation.

## Next

1. Runtime test of Route 1: restart SteamVR and the game, then check:
   - vrserver.txt loads `vr-input-workshop://3840998860` for `frame_controller`
   - each Frame button gives the expected Xbox button (probe `pad=` lines)
   - no doubled presses
2. If Route 1 fails or loses Inventory and Pause, evaluate Route 2.
