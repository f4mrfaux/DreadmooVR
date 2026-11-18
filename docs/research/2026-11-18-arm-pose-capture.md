# Arm pose capture — 2026-11-18

Captured while Bob held a sequence of arm poses in Dreadmoor. The headset cameras do not provide an exterior view of elbows; this capture records SteamVR tracked hands and the M2 virtual hand, elbow, shoulder, and head socket positions.

Raw excerpt: [`logs/arms-pose-capture-2026-11-18.txt`](../../logs/arms-pose-capture-2026-11-18.txt), from 09:11:45 to 09:12:50 local time. Source was the live UEVR `log.txt`.

## Findings

- During the wide-arm hold around 09:11:49–09:11:55, tracked hand span reached 1.60 m. The widest in-game VR hand-target span in the excerpt was about 175 cm at a world scale near 1.10.
- The UBIK span estimate increased from 50.7 cm to 65.8 cm during that hold. The character arm chain measured 50.7 cm. This is evidence the current body/arm fit is short by roughly 15 cm, but the capture does not prove that setting the exposed `ArmLength` property stretches the skeletal chain.
- Narrow-hand samples around 09:12:03–09:12:07 show tracked spans from 0.14–0.36 m. Samples around 09:12:08–09:12:11 show spans around 0.45–0.49 m with hands roughly 0.8 m below eye height. Wider samples recur later in the sequence.
- The capture has no in-game pose labels, so the exact timestamp boundaries for “arms forward” and “elbows at hips” are not certain. The raw socket and tracking data is retained for comparison.
- The live `ABP_VRArms` AnimGraph was inspected through EngineWire: its two Two Bone IK nodes consume `LeftElbowHint` and `RightElbowHint`. The graph is wired and compiled. The bone chain still has fixed 50.7 cm length, and IK straightens when hand targets exceed that reach; there is no arm stretch node.
- User reported right-arm movement twisting the torso and swinging the left shoulder. A temporary live diagnostic changed `aim_method` from right-controller aim to head aim at 09:16:39; the user said this felt much better, but then reported the grapple gun aimed from the head. The live profile tuning file has been restored to `aim_method=2`; the latest runtime log still showed `VR_AimMethod=1`, so a script reload/reinjection is needed to verify the runtime restore. `movement_orientation=1` remains configured for head-led walking.
- A desktop screenshot was captured during the later item-orientation check, but it showed the boat/railing and no grapple gun in hand, so it cannot establish the remaining 90-degree item offset.
- A 90-degree maximum elbow swivel guard was briefly tried as a local candidate, then removed to preserve the elbow bend direction that looked right during hip-fired grapple shots. It did not address arm reach.

## Rig update — 2026-11-18

- Preserved the elbow-hint direction that looked correct during hip-fired grapple shots. The proposed 90-degree swivel guard was removed; neither the UBIK bend calculation nor its hint direction was changed.
- Enabled `bAllowStretching` on both `ABP_VRArms` Two Bone IK nodes and set `MaxStretchScale` to `1.30` with `StartStretchRatio=1`. This allows up to 30% reach extension only after the 50.7 cm chain reaches full extension, in line with the captured 65.8 cm arm estimate. The blueprint compiled with 0 errors and 0 warnings and was saved.
- Cooked and deployed the updated pak. The container check found only `ABP_VRArms`, `BP_PakProbe`, and `BP_VRArms` under `/Game/DreadmoorVR`; no out-of-scope assets were included.
- Claude's held-item yaw tuning is committed in `fbf728c` (`item_rot` yaw 90), but a live sweep showed that was not the correct angle once the transform order was fixed. UE's `ComposeTransforms` contract exposed that the bridge applied the delta in socket space instead of as a local-space delta to grip-to-world. The corrected visual sweep found yaw 0 points forward, yaw 90 right, and yaw 180 toward the player. Yaw 0 was an intermediate visual alignment confirmed in-game (capture: `build/snaps/orientation-confirmation/095116_1.jpg`); the later fired-shot comparison and Bob's confirmation supersede it. The accepted calibration is yaw 15; see [`2026-11-18-hook-shot-alignment.md`](2026-11-18-hook-shot-alignment.md).
- This is a build/deployment result, not a headset validation. On the next run, check elbow bend direction during hip shots and arm reach during the T-pose/forward-arm poses. Also confirm grapple aim follows the right hand after the bridge reloads `aim_method=2`.
- During the next live test, Bob initially thought the elbows were not bending, then confirmed the elbow animation is present once he pulls his elbows farther back. Treat this as a pose/tuning visibility issue, not a broken IK graph. Refine the elbow hint offset with a repeatable elbows-back pose while preserving the hip-shot bend direction.

## Hook shot aim follow-up — 2026-11-18

- Bob reloaded the game and fired several hook shots after confirming the held gun points forward at `item_rot` yaw 0. He reports the hook still travels about 30 degrees to the right.
- Claude's 2026-11-17 live sweep adjusted the held model from yaw 60 to yaw 15 based on screenshots. That was a visual-only calibration; it did not verify projectile direction. The subsequent local-space transform correction established yaw 0 as the forward visual pose.
- The game computes `GA_HookGun.CalculateLaunchTransform` from `PlayerController.GetPlayerViewPoint`, then launches from `BP_HookGunEquipment.GetSpawnTransform` (`Hook` component). So the held model's `item_rot` and the shot's view aim are separate measurements.
- The previous barrel diagnostic failed at runtime because the live Blueprint's `Hook_GEN_VARIABLE` was not discoverable through the attempted root-child scan. Fresh log at 10:08:08 confirms `VR_AimMethod=2` and `tool in hand: hookgun`, followed by that diagnostic failure. Do not treat the failure as evidence of a measured barrel offset.
- Replaced that diagnostic in `m3_gestures.lua` with a direct, read-only comparison of controller control rotation and camera-manager view rotation, which is the rotation used by the firing trace and the M3 reticle. This should distinguish controller/view divergence from held-model orientation on the next Lua reload. It does not yet fix or verify projectile alignment.
- A desktop capture at 10:13 showed the Rigging Bench with no hook shot in flight, so it cannot validate the reported trajectory. Latest evidence is the user's report plus the runtime log; no fresh projectile trajectory capture is available.
- After Bob reset Lua and fired, the replacement diagnostic ran at 10:19 and consistently logged `ctrl=16/20`, `view=16/20`, and `view_minus_ctrl=0/0`. This rules out a control-rotation versus camera-view mismatch at that pose. The shot path still needs its muzzle-to-trace-point offset measured; no blind yaw compensation is justified by this log.
- Extended hook component lookup with `Actor::K2_GetComponentsByClass` as a fallback after the direct property and root-child scan. This matters both for measuring the hook's spawn point and for `hook_is_out`, which controls crank-reel activation. This fallback is deployed locally but still needs a live Lua reset to confirm the component is found.
- Updated the held-item smoke fixture's expected yaw from 180 to 0 to match the corrected composition order and current source tuning.
- The smoke suite now passes (`128 passed, 0 failed`) after updating the existing fixture for the current yaw 0 composition. A three-frame desktop capture after the user's test showed the Rigging Bench, with no hook projectile visible, so the path could not be visually checked from those frames.
- The muzzle-origin diagnostic and component-lookup fallback have now been copied to the active UEVR profile. The 10:19 log predates that second update; another Lua reset is required before checking the new `launch_minus_view` and `muzzle` readings.
- Captured an eight-frame firing burst at 10:25 (`build/snaps/102524_1.jpg`–`102524_8.jpg`). The tether/shot line is visible; the held barrel sits to its left in the firing pose. This is consistent with the reported apparent rightward shot offset, but these frames do not prove a world-space projectile trajectory error.
- Restored Claude's final live-sweep `item_rot` yaw 15 in source and the active profile. M2 applied it live at 10:27:06 (`held item local rotation offset p=0 y=15 r=0`), with no Lua reset. This is a held-model alignment trial; the shot trace itself remains view-based. Smoke suite: 128 passed, 0 failed.

## Next calibration steps

1. Check whether right-arm motion still twists the torso with temporary head aim active.
2. If torso twist stops, separate right-hand weapon aiming from player control yaw before restoring `aim_method=2`.
3. Add yaw and per-side clavicle telemetry before changing shoulder solver geometry. Compare left shoulder motion while only the right controller moves.
4. Validate the 65.8 cm span estimate against a known physical arm measurement before changing `ArmLength` or the game skeleton.
