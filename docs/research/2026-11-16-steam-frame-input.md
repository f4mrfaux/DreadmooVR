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
It's an unofficial fork, and it would replace nightly 01143 as the foundation.

**Downloaded with Bob's approval (2026-11-16):**
- Location: `Downloads\UEVR-joeyhodge-111426\x\`.
- `uevr.zip` SHA-256 `9d4159b5…0242b4` matches GitHub's digest.
- Its backend embeds a `frame_controller` binding, written at start as
  `bindings_frame_controller.json`.
- It adds the actions `StartButton`, `BackButton`, `Bumper` and `TriggerAxis`, plus touch
  states.
- **Route 1 removed for the fork test (Bob: "we want steam frame native").** The personal
  binding was deleted with `POST /input/deleteconfig.action {"url":
  "vr-input-workshop://3840998860"}`, and vrserver logged "Marking published file ID
  3840998860 as deleted". So SteamVR falls back to the app's default, which under the fork
  is its native `bindings_frame_controller.json`. Our binding's source stays in
  `profile/steamvr/` and can be saved again in one call.
- The fork's own doc (`docs/steam-frame-input.md` in the fork) confirms the same face-button
  routing Route 1 used:
  - Frame A → `AButtonRight`
  - Frame B → `AButtonLeft`
  - Frame X → `BButtonRight`
  - Frame Y → `BButtonLeft`
  - Right menu → `StartButton`; left view → `BackButton`
  - Bumpers → `Bumper`; grips → `Grip` and `Squeeze`
- It also states: "The native defaults send standard A/B/X/Y gamepad bits."
- It adds Lua calls the bridge can use for grab gestures:
  `vr.get_controller_type(source)` (returns "frame"), `vr.get_controller_profile(source)`,
  `vr.get_action_axis(handle, source)` for the analogue squeeze and trigger, and
  `vr.get_action_state(handle, source)`.
- It never overwrites a customised `bindings_frame_controller.json`; it only upgrades stock
  copies.

## Next

1. Runtime test of Route 1: restart SteamVR and the game, then check:
   - vrserver.txt loads `vr-input-workshop://3840998860` for `frame_controller`
   - each Frame button gives the expected Xbox button (probe `pad=` lines)
   - no doubled presses
2. If Route 1 fails or loses Inventory and Pause, evaluate Route 2.

## Runtime log, 2026-11-16

- **12:28:** the fork was injected into Rainmeter by mistake. Rainmeter's UEVR log shows
  commit 76e67fc.
- **12:30:** the fork was injected into Dreadmoor. Its log shows commit 76e67fc, and it wrote
  `bindings_frame_controller.json`. The bridge loaded and applied its settings.
- Controls were dead. vrserver still loaded the deleted personal binding from Steam's local
  cache (`steamapps\workshop\content\250820\3840998860\…_legacy.bin`), because a deleted
  workshop binding stays "current" until something else is selected.
- **Fix (12:32:08):** `POST /input/selectconfig.action {app_key: steam.app.3629430,
  controller_type: frame_controller, url: file:///…/bindings_frame_controller.json}`. The
  vrserver log shows the fork's Frame binding loaded live, with no restart.
- **Lesson:** after deleting a personal binding, select its replacement explicitly.

## Back to nightly 01143 with a native Frame binding (12:35)

The fork rendered only the HUD in Dreadmoor. Its log reads "Failing closed for FSceneViewport
render target … native-resource discovery failed", and the probe saw no pad changes under
it. Bob chose nightly 01143 plus a native Frame binding:

- Route 1's binding was saved again: `vr-input-workshop://3841006354`.
- It was selected explicitly with `selectconfig.action`, and vrserver loaded it at 12:35:16.

## Porting the fork's Frame input into the nightly: assessment

- The fork is exactly nightly 01143 (praydog 4ee5c6b) plus 456 commits. GitHub compare
  reports it "ahead 456, behind 0", with merge base 4ee5c6b. So the nightly is its base.
- The Frame work is three commits, about +2,200 lines with a third of that in tests:
  - 1be3ffe: capability-gated Frame input
  - 01aa042: controller identity, grip axes and touch input in the Lua API
  - 0a4dd9d: Touch default repairs
- Those commits sit on top of other fork changes (`VR.cpp` is about 10k lines in the fork
  against 3.3k in mainline), so a cherry-pick onto 4ee5c6b will conflict.
- The OpenVR-only core is small: the Frame binding (`SteamFrameBindings.hpp`), the new
  actions (`StartButton`, `BackButton`, `Bumper`, `TriggerAxis`), and their gamepad mapping
  in `VR.cpp`.
- Build tools are present (VS 2022 Community and its CMake).
- Over our binding, a port would add dedicated Start and Back buttons, bumpers separate from
  the grips, and the Lua grip-axis API.

## Building UEVR ourselves: blocked

- UEVR's repo is public, but `dependencies/submodules/UESDK` points to `praydog/UESDK`,
  which is private. `git ls-remote` says "Repository not found" and the web page returns
  404, while `CMakeLists.txt:62` does `add_subdirectory(dependencies/submodules/UESDK)`.
  Official and fork binaries come from CI that has access to it.
- No newer official nightly exists: 01143 (2026-08-30) is the latest, and upstream has no
  Frame commits.
- **Alternative: an earlier fork release with the Frame input and older rendering:**
  - `100926TownFallp2` (2026-10-09, commit a5d0e2a) contains 1be3ffe and 01aa042 (Frame
    input and the Lua controller API). It lacks 0a4dd9d, which only repairs the Touch
    defaults. Its notes say "rendering remains unchanged".
  - `100826steamframep2` (2026-10-07) is commit 01aa042 itself, with the notes
    "Input-only: rendering, UObject/UESDK, and game compatibility fixes are intact".
  - The fork's UE 5.6 Slate/Native Fix render reworks are dated 23 Oct onward.
  - The fork still carried other render changes before October, so it's a better bet but not
    a sure one.
- **Downloaded 100926TownFallp2 (12:40):** `Downloads\UEVR-joeyhodge-100926\x\`. Its SHA-256 `520bd3d9…` matches GitHub's, and it contains `XR_VALVE_frame_controller_interaction` and `bindings_frame_controller.json`. The profile's Frame binding file was selected in SteamVR.

## Fork 100926TownFallp2 runtime (12:45)

- The log shows commit a5d0e2a (tag 100826steamframep2), and it loaded over OpenVR.
- It logged "Keeping customized Steam Frame binding file", because the file was the 13 Nov
  build's copy. That file is compatible: every action it uses exists in this build's
  `actions.json`. vrserver loaded it at 12:45:12.
- **No input:** there's no "Successfully spoofed gamepad connection" line, and the probe saw
  zero pad events. Bob reported that the Frame controller doesn't navigate the menu. The
  nightly logs "spoofed gamepad connection @ 0" right away (build/m0/0733).
- It also logged the same D3D12 back-buffer and Slate errors as the nightly; rendering was not
  reported.
- **Result:** neither fork build works with Dreadmoor. 111426 renders only the HUD, and
  100926 delivers no gamepad input.
- **Fallback in place:** our native Frame binding `vr-input-workshop://3841006354` was
  selected again for nightly 01143.
- **Better source:** a build of nightly 01143 plus only the fork's Frame input commits
  (1be3ffe, 01aa042), from joeyhodge or anyone with UESDK access.

## Nightly 01143 with our Frame binding (12:48 to 12:54)

- The workshop personal save (`vr-input-workshop://3841006354`) loads as `…_legacy.bin`.
  After it loaded at 12:49:53, **no input** reached UEVR: no buttons and no sticks.
- The same binding was then selected as a plain file,
  `file:///…/UnrealVRMod/Dreadmoor-Win64-Shipping/dreadmoorvr_bindings_frame_controller.json`.
  It loaded at 12:52:42 with no errors, every output action exists in nightly's
  `actions.json`, and the format matches Valve's own Frame bindings (for example Half-Life:
  Alyx). Still **no input** came through when Bob pressed every button live.
- **Not yet known:** whether a binding switched while the game is running ever takes effect.
  No live switch today was confirmed by input. Next test: restart the game, re-inject the
  nightly, and check that vrserver loads the file binding as current. That also tests
  persistence across restarts.

## Baseline restore test (13:22): input still dead

The profile was restored to the morning's working state:
- nightly 01143
- UEVR's own Touch binding, loaded 13:23:02
- only the read-only probe running
- `DPadShifting=true`, game aim, HUD not following the view
- fork leftovers and `main.lua` moved to `_hold_1317`

Bob pressed every button and got no input. The probe saw only the Start spoof (`0x0010`).

**So the cause is outside the UEVR profile, the bindings and our scripts.**

UEVR's gate (`VR.hpp:306`, commit 4ee5c6b) is:
`is_using_controllers = controllers_allowed && is_hmd_active() && controllers found &&
now - m_last_controller_update <= inactivity timer`. `m_last_controller_update` is set only
when `is_any_action_down()` sees VR action data.

The Start spoof runs before this gate, and everything else after it. So either SteamVR is
delivering no action data to the app, or `is_hmd_active()` is false.

Both are SteamVR or headset state. The session made many Binding-API calls (save, delete,
select) against a live vrserver, so the next step is a full SteamVR restart, then one test.
