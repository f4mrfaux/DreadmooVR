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
digit's curl channel as Alpha. The original curl nodes used Pitch (local Y). A prior note said a
game `MM_Attack_01` hand pose supported that axis, but an exact-name scan of the installed cooked
content finds no such asset; that claimed comparison is unverified and should not be used as
evidence for the rig axis. The latest headset capture is stronger evidence for the protagonist mesh.

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

### Exported-mesh shape check

The game's exported protagonist GLB was loaded in a temporary Godot viewer (outside the project
and package) to check the actual hand geometry against those same curl angles. The export contains
an 89-bone skeleton and the expected left/right digit chains. Rendered open, full-fist, index-point,
and middle-point samples show visibly distinct shapes: both fists close, and each point sample
leaves its selected digit extended while the other channels curl. This catches missing bone-name
matches and gross curl-axis/shape problems on the protagonist mesh. It is a geometry check using
the authored values: the temporary viewer applies approximate local-Y rotations in Godot, so this
does not prove that Godot and Unreal evaluate parent-bone axes identically. It does not execute
Unreal's AnimGraph or prove the headset's sensor-to-mesh result. The live screenshots in
`artifacts/hands-curl-*` are not labeled by gesture, so actual in-game mapping and naturalness still
need labeled runtime evidence.

Local pose renders (kept in `artifacts/`, excluded from this source commit because the capture
folder is 112 MB): `protagonist-pose-open.png`, `protagonist-pose-fist.png`,
`protagonist-pose-index-point.png`, `protagonist-pose-middle-point.png`, and matching
`protagonist-hands-*` close-up crops.

EngineWire read the current `/Game/DreadmoorVR/BP_VRArms` component template: `Body.SkeletalMesh`
resolves to `/Game/Dreadmoor/Animations/Characters/New/dm_demo_NewProtagonist`, its `AnimClass` is
`/Game/DreadmoorVR/ABP_VRArms_C`, `bVisible` is true, and `bHiddenInGame` is false. The Blueprint
is up to date and has no compile errors. This confirms the runtime arms actor is authored with the
protagonist mesh, even though the standalone AnimBP editor preview was showing a generic mannequin.

The isolated render uses a front view with arms relaxed, so it also cannot validate the boat
grip-socket alignment. EngineWire's AnimBlueprint preview showed a generic mannequin rather than
the protagonist, and the editor crashed during an input attempt before a useful protagonist-in-helm
preview could be captured. Do not mark character hand placement on the wheel/throttle as visually
validated from the current evidence.

### Boat target recovery from the latest runtime log

The 21:27 runtime capture repeatedly reported `socket correction outside world safety bound` while
UEVR's active-controller hint was true. The hand targets and authored sockets were individually
finite, but their different world origins made the relative controller offset exceed the safety
bound; the previous recovery only handled a false controller hint. M2 now falls back to direct
socket placement for that valid-socket/invalid-relative-offset case and keeps that placement through
the helm session, following the moving wheel and throttle sockets. It resets controller offsets and
restores walking placement on exit. A Lua regression reproduces the logged class of failure while
the hint remains true. An earlier 21:19 capture also showed `glm::vec` basis vectors causing the
solver's uppercase `X/Y/Z` check to fail; a second regression supplies lowercase `x/y/z` bases and
confirms the socket path recovers without depending on those values. These fixes cover both logged
failure shapes in the bridge logic, but do not visually confirm the protagonist's arms or grip fit
in a new running-game capture.

The exported animation is a reference for the hand shape, not copied code or a redistributed asset.

### 2026-11-19: non-thumb curl plane correction

The first OBS capture showed an index pose that clips while open; reference-pose reset nodes were
added to straighten that starting pose. The latest 06:50 OBS capture confirms the pointer pose is
now acceptable, but closing the index into a fist bends it about 90 degrees sideways across the
knuckles/fingers instead of into the palm. Index input and AnimBP readback change during the capture,
so this is a curl-plane problem, not a missing sensor channel.

EngineWire's reference-skeleton read shows the finger chains run along local X and the rows spread
across local Z. Pitch (rotation about local Y) sweeps the fingers over the knuckle line; Yaw
(rotation about local Z) flexes them into the palm. A first pass used opposite yaw signs per hand;
the headset showed the right hand curled correctly and the left curled in the exact opposite
direction. The left signs are now flipped to match the known-good right signs. All 24 curl nodes for
index, middle, ring, and pinky use negative local-Z Yaw on both hands. Full-curl magnitudes stay as
before: index 65/85/65, middle and ring 65/80/60, pinky 60/75/60 degrees. Thumb nodes remain
untouched because their curl shape looked good. The reference-pose resets, sensor channels, and open
pointer pose are unchanged. `ABP_VRArms` compiled and saved with zero errors/warnings. Verify the
left fist direction on the next headset run; keep the right-hand pose as the known-good reference.

### 2026-11-19: first-person helm hand pin timing

The 05:38 OBS helm run and matching runtime log showed the visible hands drifting off the wheel and
throttle. UObjectHook updates controller targets before M2's pre-engine-tick socket pin, overwriting
the pin for the rendered frame. M2 now reapplies authored left wheel and right throttle socket
locations in the post-stereo callback, after the hook update. Automated Lua checks simulate this
callback order and cover moving sockets and helm exit restoration. This timing fix does not establish
that wrist roll or grip offsets look natural in game; confirm those visually in the next headset run.
