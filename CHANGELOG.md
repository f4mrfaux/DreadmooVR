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
- Removed the automatic M1 debug-cube spawn from the production bridge.
- Local Lua and native test suites pass. Headset acceptance for fishing, boat steering/throttle,
  arms/shoulders, crafting, and the target Steam Frame input setup is still pending. The reported
  fish landing animation restart is tracked as a base-game issue; this mod does not claim to fix it.
