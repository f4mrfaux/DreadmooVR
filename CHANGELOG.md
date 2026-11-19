# Changelog

User-visible changes are recorded here. Dates are local development dates; an entry marked
pending has not passed headset acceptance.

## 1.0.0-beta.1 candidate — 2026-11-18

- Added gesture controls for fishing fight lean, reel cranking, DirectionalDrag QTE, small-boat
  steering and throttle, sickle guard, hook-gun reeling, and craft-bench cursor movement.
- Added first-person VR arms visibility handling at the small-boat helm while retaining the
  diver skeletal mesh as the arms pose source.
- Stabilized helm hand socket anchoring by removing the exact previous world-space controller
  offset before solving the replacement offset; guards now reject non-finite or implausible
  corrections. Headset confirmation is still needed.
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
  Expanded per-joint curl range to support a readable fist while retaining independent index and
  middle extension for pointing and the middle-finger gesture. Headset validation remains pending.
- Fixed fishing QTE detection to read the reflected FGameplayTag name instead of the wrapper
  address; the address had made a non-QTE state appear continuously active and suppressed reeling.
- Added a separate first-person helm camera offset and runtime finger AnimBP property readback
  diagnostics to guide the next headset check.
- Reworked first-person throttle around the intended hand poses: hip-fire neutral, hand low at
  the hip for reverse, and a straight-elbow diagonal reach for forward. Added projected-travel
  telemetry and a pose-sequence smoke test.
- Fixed a first-person helm lockout where UEVR's `is_using_controllers` hint could be false even
  while all hand and head pose reads validated. The bridge now gates on pose validation and still
  neutralizes controls when a pose read fails; the smoke harness covers both cases.
- Added per-hand SteamVR pose-validity events with a 100 ms heartbeat. Boat and fishing gestures
  now ignore a false UEVR controller-use hint when the required hand poses are valid, and release
  synthetic input when native tracking is invalid or its heartbeat goes stale.
- Fixed first-person helm hands snapping off the wheel and throttle: the socket solver now allows
  finite boat-scale offsets from UEVR's view origin and retains the last valid paired offsets
  through invalid socket samples. Added regression coverage for moving sockets far from view origin.
- Changed helm gestures to require a shallow left-hand wheel arc below wheel-top neutral, with soft
  left-controller steering-step clicks. Throttle now follows right-hand forward reach and clicks
  the right controller on reverse/neutral/forward transitions; positive input magnitude scales with
  reach while headset validation checks the game's fixed throttle detents.
- Added a fishing cast gesture: hold the right hand at the ear to charge `IA_Fishing_Cast`, then
  extend forward to release it; the gesture does not write camera-look axes.
- Added a bite-QTE-only upward twitch that sends one short `IA_Fishing_Cast` press to set the hook.
- Kept the one-hook-set-per-bite latch through brief hand-tracking loss, preventing a second
  hook-set pulse after reacquisition during the same QTE.
- Removed the automatic M1 debug-cube spawn from the production bridge.
- Expanded smoke coverage for boat heartbeat expiry/recovery, wheel-arc steering/haptics, forward
  throttle scaling/mode haptics, large moving-socket offsets and anchor recovery, head-turn-stable
  steering, active fishing input release on tracking loss, bite-pulse duration and one-shot behavior
  after tracking recovery, DirectionalDrag button pass-through, and normal crank-stop release. Local
  Lua and native test suites pass. Headset acceptance for fishing, boat steering/throttle,
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
