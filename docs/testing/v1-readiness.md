# DreadmoorVR v1 readiness

Status snapshot: 2026-11-18. This records implementation and verification separately so a passing
desk harness is not mistaken for headset acceptance.

## Current state

| Area | State | Evidence / remaining check |
|---|---|---|
| UEVR runtime and pak loading | Passed | M0/M1 headset evidence in `docs/research/2026-11-16-m1-passed.md`. |
| Native input plugin | Built and smoke-tested | `build/plugin/Release/DreadmoorVR.dll`; 9 native core tests pass. All 16 Frame binding outputs resolve to installed UEVR actions across 20 physical sources. The latest captured report showed 25.4% HMD-active ticks, 59.8% valid Frame Pose-action ticks, and 15.5% UEVR `using_controllers` ticks. The bridge now consumes a native per-hand validity heartbeat; retest end-to-end with passthrough off on the release setup. |
| Arms and shoulder fit | Implemented; on-foot headset tuning recorded | EngineWire confirmed matching per-digit curl channels and the existing parent-bone Pitch axis against the game's fist animation. `ABP_VRArms` now uses a deeper, joint-specific curl range for fists while preserving independent index and middle extension. Retest helm hand placement and three finger poses in headset. |
| Fishing gestures | Implemented and smoke-tested | Harness covers right-hand cast/hook-set and both-hand fight/reel/DQTE validity, active-input release on tracking loss, recovery, signed lean/deadzone, and one hook-set pulse per bite. Headset acceptance remains required; confirm A for DQTE and record the separate base-game FishLand failure. |
| Boat steering and throttle | Updated after live test; headset retest required | 14 boat harness checks cover native third-person pass-through, pose validity, heartbeat expiry/recovery, wheel-top neutral and signed lower-arc steering, steering/throttle haptics, proportional forward reach, large moving-socket offsets, and cosmetic rotation. The 2026-11-18 live run showed the old 150 cm hand-anchor cap releasing both hands every frame; the solver now accepts finite boat-scale world offsets and holds the last valid pair on invalid samples. Retest hand placement, throttle behavior, and cosmetic alignment. |
| Craft bench cursor | Implemented and smoke-tested | Headset check required for viewport reach and mapped face-button actions. |
| Cooked pak | Re-cooked and allowlist checked | The updated `ABP_VRArms` pak contains only the three `/Game/DreadmoorVR` assets. UE emitted four warnings for the referenced base-game skeleton, which the mod resolves from the installed game at runtime. |
| Install / release package | Deployed for local testing | `tools/deploy.ps1` installed the new pak and bridge files to the UEVR profile and game `~mods`. Rebuild the versioned tester archive after headset acceptance. |

The production bridge no longer spawns the historical M1 debug cube. The cooked probe asset stays
available for explicit diagnostics through `src/probes/m1_probe.lua`.

Latest local verification on 2026-11-18: 147 Lua tests and 9 native tests pass; the Release plugin
build succeeds; the fresh pak allowlist contains only the three `/Game/DreadmoorVR` assets. The
pak and current bridge scripts are deployed to the local game and UEVR profile. Unreal's four cook
warnings identify the base-game skeleton as NeverCook; this mod references the installed game
asset and does not package or overwrite it. The previous `1.0.0-beta.1` archive predates this cook
and needs rebuilding before distribution. The optional legacy `main.lua` settings bridge remains
excluded by default. The Frame binding has 20 controller sources and 16 outputs, all found in the
installed UEVR action manifest. These checks do not replace a real headset run.

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
