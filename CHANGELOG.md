# Changelog

User-visible changes are recorded here. Dates are local development dates; an entry marked
pending has not passed headset acceptance.

## 1.0.0-beta.1 candidate — 2026-11-18

- Added gesture controls for fishing fight lean, reel cranking, DirectionalDrag QTE, small-boat
  steering and throttle, sickle guard, hook-gun reeling, and craft-bench cursor movement.
- Added first-person VR arms visibility handling at the small-boat helm while retaining the
  diver skeletal mesh as the arms pose source.
- Added right-controller haptic feedback when small-boat throttle changes between reverse,
  neutral, and forward.
- Preserved native stick steering in third-person boat view and enabled hand steering only in
  first-person; switching views restores or recalibrates the gesture axes.
- Matched cosmetic steering wheel updates to the game's steering-wheel actor rotation to avoid
  applying the mesh component's local offset twice.
- Corrected the cosmetic wheel sync target to the modular cosmetic's nested `Actor`, matching the
  shipped `BP_ShipSteeringWheel` Blueprint. Live headset confirmation is pending.
- Added SteamVR five-finger curl driven articulation for both hands, with smoothing and three
  additive bone joints per digit. Tracking loss and stale samples ease back to an open hand.
  Finger direction and fit still need headset validation.
- Removed the automatic M1 debug-cube spawn from the production bridge.
- Local Lua and native test suites pass. Headset acceptance for fishing, boat steering/throttle,
  arms/shoulders, crafting, and the target Steam Frame input setup is still pending. The reported
  fish landing animation restart is tracked as a base-game issue; this mod does not claim to fix it.

### Developer's note

I built this with UE 5.6, UEVR's Lua bridge and a small native OpenVR input plugin, SteamVR action
bindings, EngineWire's Unreal MCP for our mod assets, and the local `tools/re` parsers for the
game's cooked IoStore containers and Blueprint bytecode. AI assisted with tracing and cross-checking
the game's calls, input paths, and Unreal APIs; I verified the findings against the project and
runtime and did the headset tuning. Honestly, I couldn't have traced this many shipped-game calls
by hand in 72 hours. I can read C++; I just can't read a whole game's worth of Blueprint bytecode
before breakfast.
