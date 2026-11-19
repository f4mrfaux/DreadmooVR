# M3 gesture headset check

Run this after injecting the current DreadmoorVR profile. Gesture thresholds live in
`src/data/dreadmoorvr_arms_tuning.lua`; the bridge reloads that file while the game runs.
Gesture smoke checks passed in the local fake UEVR/game harness, but physical tracking,
Steam Frame input, and game feel still require a headset run.

## 2026-11-18 candidate deployment

The UE 5.6 cook completed after the editor MCP reported `/Temp/Untitled_1`, no open asset editors,
no selected actors or warnings, and `save_all` reported zero dirty packages. The editor was then
closed cleanly with no packages discarded. The pak audit found 3 entries, all under
`Dreadmoor/Content/DreadmoorVR/`; the cooked pak and current M3 Lua/tuning files are deployed.
Commits: `ce53196` (helm anchors, pose checks, placement calibration, and throttle debounce) and
`a2d1c9c` (steering deadzone, response curve and smoothing; deliberate neutral pass to reverse).
These latest helm changes have not yet had a headset playtest.

## Morning run: fishing and helm first

Before the run, record the Dreadmoor build, UEVR version/commit, SteamVR version, Frame firmware,
and Windows build. Turn Steam Frame passthrough off before injecting UEVR; a previous runtime
report showed only 4.98% HMD-active ticks, which can suppress controller input. V1 support will
be limited to a combination that passes this checklist.

1. **Fishing fight:** enter the fish fight, leave the left stick untouched, then lean the right
   hand left and right. Confirm the fight indicator responds in the intended direction. The pose
   calibrates when the fish becomes active; return to center between trials.
2. **Fishing reel:** crank with the left hand around the right-hand reel point. Confirm the reel
   stays held only while turning and stops on release.
3. **Fishing QTE:** during DirectionalDrag, hold Frame A as the possible `IA_QTE_LMB` input and
   move the right hand horizontally and vertically. Record whether A is accepted and whether both
   directions move the QTE indicator. Other QTEs should keep their physical inputs.
4. **First-person small boat:** enter the `BP_SmallBoat_V2` helm while on foot. Check the VR arms
   remain visible even though the game hides the diver actor. The left hand should sit on the
   wheel's authored `LHand_Socket`; the right should sit on the throttle's `RHand` socket. Move the
   left hand through a left/right arc to steer. The first 2 cm around center is ignored, then input
   builds gently and reaches full steering at about 22 cm by default; light smoothing should keep
   tracking jitter from flicking the helm. HMD movement should look around; first-person right-stick camera look is
   suppressed because it rotates the game control frame underneath the tracked hands. Third-person
   camera look remains native.
   Also watch the selected wheel cosmetic overlay while steering fully left and right: it should
   remain aligned with and rotate together with the base `Small_Boat_Steerwheel`, without lag or
   snapping back. This sync is implemented in M3 but has no live validation yet.
5. **Throttle:** on entering first-person helm, hold the right hand in a comfortable hip-fire pose
   for neutral, and keep both hands still through the brief calibration poll (at least 1.4 s,
   including 0.4 s of stable pose). No axes should be sent during calibration. Move the right hand
   low beside the hip for reverse; return to the hip-fire pose for neutral; then extend the right
   arm diagonally forward with a straight elbow for forward. The gesture projects hand motion onto
   an up-and-forward axis, so the diagonal reach counts even when the hand does not rise much. Each
   detent must remain requested for 120 ms before it is accepted and produces one right-controller
   haptic click. Invalid/out-of-range pose reads must zero the axes and restart calibration. A
   false `is_using_controllers` hint alone must not suppress valid tracked poses; confirm steering
   still responds during that runtime state. Other boat types intentionally retain their native
   stick. First-person mode must keep gamepad LX/LY neutral during initial calibration, so a
   physical stick cannot leak through.

After the run, send the visible behavior plus log lines containing `fishing`, `native SteamVR pose`,
`boat mesh anchors`, `boat throttle detent`, `boat arms visibility`, or `FAILED`. The boat anchor log
gives the live world positions of the wheel mesh and throttle lever for alignment review.

## 2026-11-18 first-person helm recording

OBS captured `C:\Users\Bob\Videos\Mod Showcase\Mod Showcase 2026-11-18 14-02-13.mkv`
(4m 50s). The player reported that steering no longer felt reversed on this pass. Frames around
160s, 230s, and 270s show the tracked hands near the helm controls, but their alignment changes as
the view/control frame turns; the right hand only appears near the throttle in some frames. The
game Blueprint routes `IA_BoatLook` to controller yaw and pitch, so first-person right-stick look
was identified as a source of that frame movement. The source now suppresses that look input in
first person and uses the static mesh's authored grip sockets for the two rendered hands. These
changes are not live validated until the updated Lua scripts are reloaded.

The same recording's runtime log showed `boat controls FAILED: caught (...) exception` on helm
entry. The profile currently contains `VR_MovementOrientation=1` and `VR_RoomscaleMovement=true`;
we need a fresh run with per-setting failure logs to confirm whether the boat override disables
room-scale movement. Do not attribute the reported forward camera push to room-scale until that
check passes.

## Melee guard

- [ ] Equip the sickle (the knife has no block ability).
- [ ] Put the right hand low, in front of the torso, near the centerline; point the controller
  down like a thumbs-down. Hold for about 0.1 seconds.
- [ ] Confirm the game's block action stays held from Secondary Use (left trigger), without
  triggering an attack. UEVR log should show `guard held` once.
- [ ] Raise or move the hand behind the body. Confirm block releases and the log shows
  `guard released` once.
- [ ] Swing normally after releasing guard; confirm an attack still triggers.
- [ ] If guard activates at rest or is hard to enter, adjust `guard_enter_z` / `guard_exit_z`.
  Keep `guard_exit_z` closer to zero than `guard_enter_z` to preserve hysteresis.
- [ ] Set `guard_enabled = false` once and verify the physical trigger passes through; restore it
  to `true` afterward.

## Hook gun

- [ ] With hook home, rotate the left hand around the crank point near the right hand. Confirm it
  does not fire the gun.
- [ ] Fire the hook, then crank with the left hand. Confirm one distinct reel press per roughly
  90 degrees and that motion in either direction reels.
- [ ] Stop rotating and confirm presses stop. Return the hook and confirm queued crank turns do
  not fire it.
- [ ] Confirm the glowing reticle sits on the point the hook will reach and the game's center dot
  returns when the reticle hides.

## Fishing

**Capture follow-up (2026-11-18):** the UEVR log from the latest OBS run rendered `CurrentQTE` as a
temporary `FGameplayTag` wrapper address, rather than its tag name. The bridge now reads the
reflected `TagName` FName, so `None` no longer looks like a continuously changing QTE and blocks
the reel path. The Lua smoke fixture now supplies the same struct shape. Restart/reload the Lua
bridge before validating; check that `fishing crank: reel held` appears only while cranking and
that normal fishing resumes after a QTE.

- **Cast:** before a fish is hooked, hold the right hand beside the right ear briefly to charge,
  then extend the arm forward to release `IA_Fishing_Cast`. The gesture only overrides the cast
  trigger; it leaves both camera-look axes untouched. Check that the landing power widget charges,
  the float launches on extension, and the view does not flip. The left-hand crank remains the
  separate reel gesture during a fish fight.
- **Hook set:** when `QTE.Type.FishingBite` appears, give the right hand one quick upward twitch.
  The gesture sends a single short `IA_Fishing_Cast` press for that bite QTE; ordinary upward
  movement outside the bite window does nothing.

- [ ] During the fish fight, lean the right hand left/right from a neutral position; confirm the
  fight indicator reacts in the direction expected by the game's UI. Adjust
  `fishing_fight_deadzone_m` if neutral tracking noise moves it; `fishing_fight_range_m` controls
  how far the lean takes to reach full stick input.
- [ ] Crank with the left hand while fighting; confirm the game's reel trigger is held only while
  cranking.
- [ ] Trigger a DirectionalDrag QTE; confirm right-hand horizontal/vertical movement controls
  the QTE and the crank is suppressed.
- [ ] Reach FishLand and record the prompt shown, the button pressed, whether the QTE reports
  success, and whether the game enters the landing animation. That reported base-game issue is
  separate from the mod gestures; do not infer its cause from gesture behavior alone.
- [ ] If controller tracking briefly drops during a fish fight, confirm the crank releases and
  gesture axes stop. When tracking returns, confirm the right-hand lean recalibrates for that fish
  and the next DirectionalDrag QTE captures a fresh neutral pose.

Fishing uses finite, in-range UEVR pose reads and per-hand SteamVR Pose-action validity when that
native stream is available. Cast and hook-set require the right-hand pose; fish-fight, reel, and
DirectionalDrag require both hands. The UEVR `is_using_controllers` hint alone does not suppress
valid poses. Native validity is refreshed on state changes and a 100 ms heartbeat; an invalid hand
or a heartbeat older than 500 ms clears the fish/QTE reference, resets the crank detector, zeros
gesture axes, releases synthetic reel/cast/hook-set input, and logs a rate-limited fail-safe line.
If no native validity events arrive, the bridge falls back to validated UEVR poses. Physical inputs
continue to pass through while gesture state is cleared.

## What to send back

Note the title of the check, whether it worked, and any UEVR log lines containing `guard`,
`fishing`, `crank`, or `swing`. For FishLand, include the visible prompt/button and whether it
timed out or accepted input.

## Finger tracking and first-person helm view

- **Finger tracking:** move each Steam Frame controller finger independently. Confirm the matching
  avatar digit bends, then opens when released. The Lua bridge logs the actual arm AnimInstance
  class and whether `FingerCurlLThumb` can be written and read back. A `property probe FAILED` line
  means the Unreal AnimBP property path/name is the remaining blocker; include that line and the
  next `finger animation update FAILED` line if present.
- **First-person boat camera:** the helm now uses a separate `boat_camera_forward` offset of -30 cm;
  walking retains -12 cm. Check that the torso no longer fills the helm view and that walking view
  returns after leaving the boat. This offset is an initial headset trial, not an asserted final fit.
# Crafting and boat interactions

- **Craft bench cursor:** in BP_CraftController_C, move the left controller around a 40 cm
  head-relative workspace. The bridge moves the desktop cursor; the game's own TraceForPile,
  HoveredPile, and IA_Crafting_Click still handle hover and pile selection. Use the bottom face
  button to select a pile and the left face button to start/cancel crafting; those avoid the top
  face button's overlapping recipe action. The top face button opens recipes.
- **Small boat:** confirm the third-person view keeps the game's native stick steering/throttle.
  Switch to the BP_SmallBoat_V2 first-person helm view: left-hand horizontal travel
  steers through IA_BoatMove.X; after calibrating with the right hand in a hip-fire neutral pose,
  lower the right hand to the hip for reverse or extend it diagonally forward for forward.
  Switching back to third-person must immediately restore the native stick axes. Other boat types
  always keep their native controls.
  Each detent transition requests a short click on the right controller. The transition logs the
  live world positions of BP_ShipSteeringWheel.Small_Boat_Steerwheel and Throttle_lever.
  Their cooked meshes are Dreadmoor/Content/Dreadmoor/Art/StaticMesh/Characters/Small_Boat/
  Small_Boat_Steerwheel.uasset and Throttle_lever.uasset. The wheel is owned by the boat's
  BP_ShipSteeringWheel child actor.
  The game hides its diver actor at the helm, so M2 clears the arms mesh's inherited hidden state
  while keeping it attached to the diver skeletal-mesh pose source; shoulder solving uses boat pawn
  yaw and hand targets stay tied to the tracked controllers.
  Expected logs: `native SteamVR pose-validity stream connected`, `native SteamVR pose L=valid` or
  `native SteamVR pose R=valid`,
  `boat mesh anchors`, `boat pose`, and `boat throttle detent: forward|neutral|reverse`.
  `boat pose` samples SteamVR head/hand positions and the resulting rudder/throttle values once a
  second; use its timestamps alongside a screen recording when checking hand alignment or drift.
  UEVR boat-setting failures now identify the specific setting key and operation (read, set, or
  restore). Anchor discovery retries while the child actor is spawning and reports the failing
  component lookup rather than silently falling back. Helm poses are checked for finite position,
  plausible tracking-space bounds, a near-unit quaternion, and implausible per-frame hand jumps;
  failed or invalid pose reads fail to neutral and require recalibration. Native per-hand SteamVR
  Pose-action validity is sent on state changes and a 100 ms heartbeat; either invalid hand or a
  heartbeat older than 500 ms fails to neutral, while a false `is_using_controllers` hint alone
  does not block valid poses. The throttle uses a stable-hand polling delay on entry
  and a 120 ms detent debounce to reduce accidental movement while the right hand is settling.
  Tune live in the gestures table: boat_steer_range_m controls horizontal travel to full rudder,
  boat_steer_deadzone_m ignores center noise, boat_steer_curve shapes the center response, and
  boat_steer_smoothing_s controls low-pass filtering. The throttle uses boat_throttle_enter_m for
  forward/reverse, boat_throttle_release_m for neutral, and a 120 ms stable detent before changes.

  **Live throttle pass (2026-11-18):** five-second pose holds showed reverse at negative projected
  travel (about -0.18 to -0.45 m), neutral near center (about -0.06 to +0.05 m), and forward at
  positive up-and-forward travel (about +0.09 to +0.13 m). Forward samples just under the +0.10 m
  entry threshold are consistent with the 120 ms debounce and sparse telemetry sampling. Leave
  thresholds unchanged pending a labeled, denser recording: the current `boat pose` log interval
  did not mark the exact start/end of each repeated hold, so it cannot establish repeatability.

  On the craft bench, craft_cursor_span_m changes how much hand movement spans the viewport.

These are smoke-tested against the bridge and fake UE objects. Check cursor reach, wheel alignment,
and detent feel in-headset; screen viewport scale and the player's natural hand reach need live
confirmation.

## Automated boat harness

Run `lua tests/run.lua boat` from the repository root. The targeted harness exercises third-person
native-axis pass-through, camera-mode switching, first-person hand calibration, valid poses with a
false runtime controller hint, invalid-pose neutral fallback, both rudder directions and center
deadzone, forward/neutral/reverse detents and haptics, and the post-game-tick cosmetic wheel copy
for left and right turns. Its fixture gives the wheel mesh a relative rotation offset to catch
component-versus-actor rotation mismatches. The expected source is
`BP_ShipSteeringWheel.ReceiveTick`, which copies the steering-wheel actor's world rotation to the
`CurrentActiveWheelCosmetic.Actor`. It uses fake UEVR/game objects, so it verifies bridge logic only; the headset
checklist above is still needed for the live wheel model, tracking reach, and haptic feel.

The visible hand targets are rebased every frame to the boat meshes' authored grip sockets in
`m2_arms.lua`: left to `Small_Boat_Steerwheel.LHand_Socket`, right to `Throttle_lever.RHand`.
Gesture input still reads the raw tracked controller poses, so hand anchoring does not move the
steering or throttle neutral reference. The controller-to-socket alignment and cosmetic actor
sync both still need confirmation with the selected in-game wheel cosmetic.

The socket solver replaces UEVR's absolute controller-local location offset. UEVR reapplies that
offset through the current controller rotation each frame, so the solver must remove it using the
current basis before calculating the next offset. Non-finite values and corrections over 150 cm
fail closed and restore the normal grip offset. `test_boat_socket_anchors_converge_without_compounding_and_restore`
checks socket convergence through a 90-degree controller-basis turn and return to the walking
grip offset. On headset, confirm both visible hands stay on their grips while rotating the wrists
and turning the wheel; check logs for `boat grip offsets` and absence of `boat hand grip socket
FAILED` or NaN values.

## Finger tracking probe

The native plugin reads OpenVR `FromDevice` finger-curl summaries for the two bound skeleton
actions and streams five channels per hand to M2: thumb, index, middle, ring, and pinky (0=open,
1=curled). The M2 listener eases these values into `ABP_VRArms`, whose AnimGraph bends all three
joints of each digit. In a safe area, move each finger through open/closed positions separately.
Check the corresponding avatar finger moves smoothly, opens fully, and does not pull neighboring
digits along. Check thumb opposition and both hands from a relaxed open pose through a fist. The
initial bend angles are a starting fit; report any finger bending backwards or clipping into the
palm so we can correct its axis/sign and per-joint angles. If tracking stops, the hand should ease
open within about 0.5 seconds. The log/report curls remain available to distinguish sensor input
from mesh articulation.
