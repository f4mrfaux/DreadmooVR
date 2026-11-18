# Arms, shoulders, and camera review (2026-11-17)

## Evidence from the box breaking capture

Reviewed `Videos/Mod Showcase/Mod Showcase 2026-11-17 18-47-15.mp4` and matched its session to
the M2 samples in the UEVR log. When the player looks down toward the boxes, the avatar's coat/
upper torso fills a large part of the lower view. The arm harness in the same session reports:

- `fit eye_ahead` around `-2 cm`: the rendered eye position is slightly behind the shoulder line.
- `arm_len=50.7 cm`, while hand-to-shoulder distance is commonly `61–72 cm`.
- `out_of_reach` around `93–94%` and mean controller-target to hand-bone error around `20–21 cm`.

The clip's broad occlusion is consistent with the camera being too far back relative to the
shoulders. The reach statistics show the arms are also spending most of the session at or past
the two-bone IK limit, which can make shoulder/elbow pose changes look abrupt.

## Confirmed graph behavior

Inspected `/Game/DreadmoorVR/BP_VRArms` and `/Game/DreadmoorVR/ABP_VRArms` in the running UE 5.6
editor through EngineWire. Both compile cleanly. The AnimGraph copies the character pose, applies
the `LeftShoulderShift` / `RightShoulderShift` translations to the clavicles in component space,
then solves each hand with Two Bone IK. Its update graph computes follow as
`max(distance - ArmLength, 0) * ShoulderFollow`; there is no upper distance cap. The earlier
`ShoulderFollow=1` trial lifted the shoulders dramatically when roomscale targets jumped, so the
legacy path remains disabled.

## Current bounded adjustment

- M2 now applies a small shoulder translation in Lua when the controller target exceeds the arm
  chain length. Influence defaults to `0.5`; translation is hard-capped at `12 cm` per shoulder.
  The legacy AnimBP `ShoulderFollow` input is forced to zero, so the two follow paths cannot add
  together. A tracking jump therefore cannot move a shoulder more than the cap.
- Camera forward offset moved from `-24 cm` to `-12 cm`. Based on the logged `-2 cm` eye-ahead
  measurement, this aims for roughly `+10 cm` ahead of the shoulders, matching the earlier body-fit
  target. This offset still needs headset confirmation.
- No Unreal assets changed, so no pak recook is needed for this Lua/tuning adjustment.

## Validation

- `lua tests/run.lua`: 119 passed. The new pure check verifies shoulder follow scales for small
  overreach, stays zero within reach, and never exceeds its cap for a large tracking spike.
- In-headset follow-up: compare box view occlusion and shoulder smoothness; inspect new `arm` and
  `fit eye_ahead` / `arms summary` log lines. If shoulders still pop, reduce `shoulder_follow` or
  its cap in the live tuning file. If the view moves too far forward, restore `camera_forward`.
