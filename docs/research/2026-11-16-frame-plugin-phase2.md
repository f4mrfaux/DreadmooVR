# Frame input plugin, Phase 2 evidence: passive telemetry (2026-11-16)

Plan: `docs/superpowers/plans/2026-11-16-frame-input-plugin-phase2.md`. Plugin commit
1b69671, deployed 15:00:30. Bob played normally for about 4 minutes with passthrough off and
did no button sequence. Bob confirmed Phase 1's headset rendering ("Yes, start Phase 2").

## Report (`<profile>\dreadmoorvr_input_report.txt`, 15:06:11)

```
DreadmoorVR input report (t=240 s since plugin load, 11491 ticks)
config: analog_step=0.25 analog_min_ms=250 digital_cap=3000 analog_cap=600 report_s=30
hand L: device 1 type frame_controller pose valid 47.0107%
hand R: device 2 type frame_controller pose valid 45.9316%
uevr: hmd_active 100% of ticks, using_controllers 43.4079%
presses: AButtonRight@R 3, Grip@L 2, Grip@R 2, ThumbRestTouchLeft@L 1, ThumbRestTouchRight@R 7, Trigger@R 1
mapping: ThumbRestTouchRight@R->0x0010 x1; AButtonRight@R->0x1000 x3; Grip@L->0x0100 x2; Grip@R->0x0200 x1
telemetry: digital 894 lines, 0 dropped; analog 377 lines, 0 dropped
```

## Physical → Xbox mapping observed in normal play

| Frame button | Action | Pad the game received | Observed |
|---|---|---|---|
| Right A | AButtonRight@R | 0x1000 (A) | 3× |
| Right X | BButtonRight@R | 0x4000 (X), no A bit | 2×, Phase 1 run (probe) |
| Left bumper | Grip@L | 0x0100 (LB) | 2× |
| Right bumper | Grip@R | 0x0200 (RB) | 1× |
| Left grip (analogue) | Squeeze@L | (not a pad button) | 0.00 → 0.25 → 0.50 → 0.75 → 1.00 |
| Right B, right Y, D-pad, view | — | — | **not exercised** |
| Right menu | SystemButton | 0x0010 (Start) seen once, but paired with a thumbrest touch | **ambiguous**: UEVR's Start spoof lasts one frame, and the SystemButton press wasn't caught as an edge |
| Triggers | Trigger@R | goes to `bRightTrigger`, not `wButtons` | the press was logged; the pairing doesn't cover triggers yet |

## Findings

- **Separate budgets work:** 0 drops in either budget. Stick noise no longer starves button
  edges (the Phase 1 flaw is fixed).
- **Analogue grip is meaningful (validation item 4):** `Squeeze` swept the full range from
  0.00 to 1.00. There's still no analogue trigger action in the nightly's manifest.
- **Actions and poses go inactive together, in blocks:**
  - Every action reports `bActive=false`, and both poses report invalid with
    `eTrackingResult=0` (Uninitialized), at the same timestamps (t=4669, 8677, 9887 and 25130
    ms).
  - Over the session, poses were valid about 46–47% of the time and UEVR's
    `is_using_controllers` was true 43% of the time, while `is_hmd_active` was 100%.
  - Hypothesis, not verified: the app loses SteamVR input focus (dashboard or system overlay
    open, or focus moving between apps). That's not tracking loss.
  - What would confirm it: logging SteamVR's input-focus state (`IVRSystem::IsInputAvailable`)
    next to these edges. That's a one-line Phase 2 addition.
- **C++ ↔ Lua round trip** verified again: "Lua -> C++ ack received: 'ping 1'".
- **Nothing written outside the profile:**
  - The renderer was untouched.
  - The bridge stayed off.
  - `config.txt`'s baseline keys stayed put: `UI_FollowView=false`, `VR_AimMethod=0`,
    `VR_DPadShifting=true`, `VR_RenderingMethod=0`.

## Not yet covered (honest gaps)

- Right B and Y, the D-pad, and the menu and view buttons weren't pressed during normal play,
  so their mapping is unverified. More play fills these in automatically, with no button run.
- Trigger and stick pairing: `MapAggregator` only pairs `wButtons`. Triggers (`bLeft/RightTrigger`)
  and sticks need their own pairing.
- Positive identification of game actions (for example "Jump happened") isn't implemented.
  Only the pad the game received is observed.
- Input-focus state isn't logged yet (see the hypothesis above).
