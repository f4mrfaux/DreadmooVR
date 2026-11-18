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

This is sensor streaming, not a pose recognizer, and it does not yet animate the rendered VR hand.
The Lua listener currently validates and retains the samples; it does not feed an animation
property. The plugin build and existing Lua suite pass, but the Frame's live curl values still need
to be confirmed by moving one finger at a time in game.

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

The immediate blocker is the project arm asset: `ABP_VRArms` exposes hand targets/locations and
rotations, but binary string inspection found no thumb or finger controls. The game's reflected
`UPoseableMeshComponent` APIs (`CopyPoseFromSkeletalComponent`, `SetBoneRotationByName`, and
related calls) are a possible runtime route, but the notes explicitly mark it untested. Before
choosing that route, inspect the game's actual hand bone names and the arm mesh skeleton, then prove
one finger can be rotated on a temporary poseable copy. If that works, add a small per-hand
five-curl adapter and drive the corresponding finger chains; keep the UBIK arm solve untouched.

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
