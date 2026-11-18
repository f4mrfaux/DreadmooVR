# Hook gun alignment calibration

## Locked value

Keep `item_rot = { p = 0, y = 15, r = 0 }` in `src/data/dreadmoorvr_arms_tuning.lua`.
Bob confirmed the live yaw 15 result with **“you got it!”** on 2026-11-18. The active UEVR
profile also logged `held item local rotation offset p=0 y=15 r=0` after the value was restored.

## Evidence and why this is easy to regress

- Claude's final live sweep on 2026-11-17 left the hook gun at yaw 15. That was an uncommitted
  tuning change when Claude hit its usage limit.
- The 2026-11-18 local-space `ComposeTransforms` correction made the earlier yaw 90 value invalid;
  a visual-only sweep at yaw 0 then looked forward, but it did not compare the barrel with a live
  fired shot. Do not substitute the old yaw 90 or the yaw 0 intermediate result for the accepted
  calibration.
- The firing ability traces from `PlayerController.GetPlayerViewPoint` and launches from the
  equipment's `Hook` component. `item_rot` aligns the visible held gun to the observed shot line;
  it does not change the game's trace or projectile code.
- An eight-frame burst (`build/snaps/102524_1.jpg` through `_8.jpg`) showed the tether line to the
  right of the held barrel at yaw 0. After restoring yaw 15, M2 applied the new item offset live.
  Bob confirmed the resulting alignment, so this is the accepted player calibration.

## Regression guard

`tests/test_tuning.lua::test_project_hook_gun_alignment_calibration_stays_at_yaw_15` asserts the
accepted p/y/r triple directly from the shipped tuning file. Run `lua tests/run.lua` before changing
held-item transform composition or tuning; if a future calibration intentionally changes, update
this note and test from a live shot comparison.
