# DreadmoorVR v1 readiness

Status snapshot: 2026-11-18. This records implementation and verification separately so a passing
desk harness is not mistaken for headset acceptance.

## Current state

| Area | State | Evidence / remaining check |
|---|---|---|
| UEVR runtime and pak loading | Passed | M0/M1 headset evidence in `docs/research/2026-11-16-m1-passed.md`. |
| Native input plugin | Built and smoke-tested | `build/plugin/Release/DreadmoorVR.dll`; 9 native core tests pass. All 16 Frame binding outputs resolve to installed UEVR actions across 20 physical sources. The latest runtime report still shows only 4.98% HMD-active ticks and 36% valid hand-pose ticks; retest with passthrough off on the release setup. |
| Arms and shoulder fit | Implemented; on-foot headset tuning recorded | Retest first-person helm visibility after the latest hidden-state handling. |
| Fishing gestures | Implemented and smoke-tested | This morning's lean/reel/DQTE headset run is still required. Confirm A for DQTE and record the separate base-game FishLand failure. |
| Boat steering and throttle | Implemented and smoke-tested | Harness covers native third-person stick pass-through, first-person gesture takeover/release, rudder, throttle detents and cosmetic actor rotation. A helm playtest is still needed for steering sign/range, haptics, arms visibility, and cosmetic alignment in both directions. |
| Craft bench cursor | Implemented and smoke-tested | Headset check required for viewport reach and mapped face-button actions. |
| Cooked pak | Present and content-allowlist checked | `list_container.py` reports only the three `/Game/DreadmoorVR` assets. Recook if any Unreal assets change. |
| Install / release package | Beta tester candidate assembled | `dist/DreadmoorVR-1.0.0-beta.1.zip` contains 28 payload files, including the M0 and M3 checklists. The clean archive manifest records its source commit; every payload SHA-256 was verified. Headset acceptance is pending. |

The production bridge no longer spawns the historical M1 debug cube. The cooked probe asset stays
available for explicit diagnostics through `src/probes/m1_probe.lua`.

Latest local verification on 2026-11-18: 132 Lua tests and 9 native tests pass; the Release plugin
build succeeds; the pak allowlist contains only the three `/Game/DreadmoorVR` assets. The current
pak was cooked after the latest `ABP_VRArms.uasset` edit. The clean `1.0.0-beta.1` tester archive
contains 28 payload files; all manifest hashes match and both referenced smoke checklists are
included. The optional legacy `main.lua` settings bridge is excluded by default, matching the
development deploy. The Frame binding has 20 controller sources and 16 outputs, all found in the
installed UEVR action manifest. The deployed gesture scripts, rebuilt plugin, and tuning are in
the local UEVR profile. These checks do not replace a real headset run.

## Remaining v1 gates

1. Complete the fishing and small-boat run in `m3-gesture-checklist.md`; fix any sign, reach,
   input ownership, visibility, or haptic problems found there.
2. Run crafting plus the core M0 checklist on the same pinned game, UEVR nightly, SteamVR, and
   Steam Frame versions that v1 will support.
3. Record and pin the tested Dreadmoor build, UEVR version, SteamVR version, Frame firmware, and
   Windows/runtime setup. Current evidence pins UEVR nightly 01143 / commit 4ee5c6b, but that
   input setup has not passed the current end-to-end Frame runtime check.
4. Do one clean release build and pak audit; verify the packaged DLL, Lua scripts, tuning file,
   binding file, and cooked assets match the tested tree.
5. Commit the accepted release state, create a clean versioned archive/tag, then install it on a
   clean profile and smoke-test update and rollback.

Beta status: local code and packaging checks are green, but the beta still needs a headset
acceptance pass on the intended Steam Frame setup before it is sent to testers. The install,
update, rollback, changelog, and archive assembly path are documented. The stable v1 release still
requires a committed tree, a clean tagged archive, and install/update/rollback checks.
