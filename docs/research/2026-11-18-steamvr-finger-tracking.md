# SteamVR finger-tracking probe

## What was missing

The Frame binding already maps `SkeletonLeftHand` and `SkeletonRightHand` to the controller
skeleton paths. The native plugin only queried `GetSkeletalTrackingLevel`, which confirmed a
tracking level but did not read any finger values.

## Current probe

The plugin now queries `GetSkeletalActionData` and `GetSkeletalSummaryData` with
`VRSummaryType_FromDevice`. It logs quantized curl changes, includes the latest per-hand values
in `%APPDATA%/UnrealVRMod/Dreadmoor-Win64-Shipping/dreadmoorvr_input_report.txt`, and streams
the five channels to the M2 Lua listener at up to 30 Hz:

- `0` means straight/open; `1` means curled.
- Values are reported for thumb, index, middle, ring, and pinky.
- Skeleton loss marks the sample unavailable.

This is sensor streaming, not a pose recognizer. M2 now sends each sample to the corresponding
`ABP_VRArms` AnimInstance float and eases toward the latest value with a 45 ms time constant. The
AnimGraph drives all 30 finger joints with additive `Modify Bone` nodes in parent-bone space: three
segments per thumb, index, middle, ring, and pinky on both hands. Each finger channel controls its
three joints together; proximal/middle/distal flex angles start at 25/35/25 degrees for the thumb
and 35/55/35 degrees for the other digits. Those are initial articulation settings, not headset
calibration. UE 5.6 compiled the AnimBlueprint after both graph batches, and graph inspection
confirmed all 30 targets, curl Alpha links, and pose links. The Frame's live values, rotation axis
direction, and visual fit still need an in-game finger-by-finger check.

An explicit inactive sample eases that hand back open. Lua also treats a channel with no fresh
sample for 0.5 seconds as open, covering a plugin shutdown that cannot send an inactive event. The
M2 smoke harness exercises side/channel mapping, smoothing, inactive recovery, and stale-sample
recovery.

## Fallout 4 VR Body / FRIK comparison

The existing body solver in this project is a Lua port of **UBIKSolver**, which calculates arm,
elbow, and clavicle placement from hand targets. FRIK is a separate Fallout 4 VR body mod; it is a
useful reference for separating body IK from hand articulation, not a drop-in Unreal dependency.
Its changelog says its finger tracking curls fingers dynamically from controller touch plus
trigger/grip axes. Its public API is an output interface: tagged hand overrides accept per-finger
values where `0` is bent and `1` is straight. That convention is the inverse of the OpenVR summary
curls above, so an adapter to that API would use `1 - curl`. We should preserve continuous sensor
values and let the hand rig render them; no gesture classifier is needed.

## Attribution and licensing

No FRIK source code has been copied or adapted in this project. We used its published feature
description and API docs as design references. If we later lift or adapt FRIK implementation code,
we must preserve its attribution and comply with the repository's GPL-3.0 license, including the
source and distribution terms that apply to derivative code. Keep such code isolated and review
license compatibility before shipping it. Our existing UBIK arm solver is separately attributed in
`src/scripts/lib/ubik.lua` to UBIKSolver (MIT, Jonas Mølgaard, 2023); it is not FRIK code.

The arm asset has no skeletal finger controls baked into its original AnimGraph, so the mod now
adds its own per-digit layer after wrist IK. The game skeleton was inspected through EngineWire;
the real finger bone names are `thumb_01..03`, `index_01..03`, `middle_01..03`, `ring_01..03`, and
`pinky_01..03`, each with `_l` and `_r` suffixes. This keeps the existing UBIK arm solve untouched.
`UPoseableMeshComponent` remains a fallback only; it is not used by the current implementation.

References:

- [FRIK public API: tagged hand poses and per-finger values](https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/docs/frik-api.md)
- [FRIK changelog: dynamic finger tracking from controller touch, trigger, and grip](https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/docs/changelog.md)
- [FRIK repository license (GPL-3.0)](https://github.com/rollingrock/Fallout-4-VR-Body/blob/main/LICENSE)
- [Valve SteamVR Skeletal Input](https://github.com/ValveSoftware/openvr/wiki/SteamVR-Skeletal-Input)
- [Valve OpenVR hand skeleton](https://github.com/ValveSoftware/openvr/wiki/Hand-Skeleton)

## Boat hand and cosmetic audit

In first-person `BP_SmallBoat_V2`, `m2_arms.lua` rebases the visible hand targets every frame to
the authored grip sockets:

- Left: `BP_ShipSteeringWheel.Small_Boat_Steerwheel.LHand_Socket`
- Right: `BP_SmallBoat_V2.Throttle_lever.RHand`

M3 continues to read raw SteamVR poses for rudder and throttle, independently of these visual
offsets. The cosmetic wheel Blueprint accesses
`CurrentActiveWheelCosmetic.Actor.K2_SetActorRotation`; M3 now resolves that nested `Actor` before
copying the wheel actor's rotation. The Lua harness covers both wheel directions and the wrapper
shape. Both hand fit and cosmetic follow still need live in-game confirmation.

## Live axis and fist-range follow-up — 2026-11-18

The running UE 5.6 project was inspected through EngineWire. `ABP_VRArms` has 30 finger
`ModifyBone` nodes. Each node uses additive rotation in parent-bone space and receives the matching
digit's curl channel as Alpha. The configured rotation is Pitch (local Y flexion); the game's own
`MM_Attack_01` hand pose also flexes the finger chains around that axis. The earlier report that the
fingers looked off-axis was not enough to justify switching axes, so the graph axis stayed intact.

The old full-curl range (35/55/35 degrees for index through pinky, with a similar shallow thumb
range) did not close the fingers far enough for a clear fist. The AnimGraph now uses these full-curl
joint rotations, in degrees, from base to tip:

| Digit | Base | Middle | Tip |
|---|---:|---:|---:|
| Index | 65 | 85 | 65 |
| Middle | 65 | 80 | 60 |
| Ring | 65 | 80 | 60 |
| Pinky | 60 | 75 | 60 |
| Thumb | 25 | 40 | 35 |

The sensor channels remain independent and continuous: index at zero with the other channels
curled produces a point, middle at zero with the other channels curled produces a raised middle
finger, and all channels curled produces a fist. No gesture classifier or button-triggered poses
were added. UE compiled and saved the AnimBlueprint after the 30-node edit. This needs headset
validation for curl depth and the two single-finger gestures before calling the hand result final.

EngineWire also read the game's reference skeleton and `MM_Attack_01` animation track data. The
rotation-axis comparison supports Pitch as the bend axis; the edit changes the bend range, not the
sensor ordering or rotation space. The exported game animation is a reference for the hand shape,
not copied code or a redistributed asset.
