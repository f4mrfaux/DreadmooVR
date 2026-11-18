# M3 gesture headset check

Run this after injecting the current DreadmoorVR profile. Gesture thresholds live in
`src/data/dreadmoorvr_arms_tuning.lua`; the bridge reloads that file while the game runs.
Gesture smoke checks passed in the local fake UEVR/game harness, but physical tracking,
Steam Frame input, and game feel still require a headset run.

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
   remain visible even though the game hides the diver actor. Hold the left hand near the wheel at
   entry, then move it horizontally left/right to steer. The neutral hand pose is captured on helm
   entry; about 22 cm reaches full steering by default.
   Also watch the selected wheel cosmetic overlay while steering fully left and right: it should
   remain aligned with and rotate together with the base `Small_Boat_Steerwheel`, without lag or
   snapping back. This sync is implemented in M3 but has no live validation yet.
5. **Throttle:** keep the right hand near its entry height for neutral. Raise it about 14 cm for
   forward, return to neutral, then lower it about 14 cm for reverse. Confirm one right-controller
   haptic click at each state change. Other boat types intentionally retain their native stick.

After the run, send the visible behavior plus log lines containing `fishing`, `boat mesh anchors`,
`boat throttle detent`, `boat arms visibility`, or `FAILED`. The boat anchor log gives the live
world positions of the wheel mesh and throttle lever for alignment review.

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

## What to send back

Note the title of the check, whether it worked, and any UEVR log lines containing `guard`,
`fishing`, `crank`, or `swing`. For FishLand, include the visible prompt/button and whether it
timed out or accepted input.
# Crafting and boat interactions

- **Craft bench cursor:** in BP_CraftController_C, move the left controller around a 40 cm
  head-relative workspace. The bridge moves the desktop cursor; the game's own TraceForPile,
  HoveredPile, and IA_Crafting_Click still handle hover and pile selection. Use the bottom face
  button to select a pile and the left face button to start/cancel crafting; those avoid the top
  face button's overlapping recipe action. The top face button opens recipes.
- **Small boat:** confirm the third-person view keeps the game's native stick steering/throttle.
  Switch to the BP_SmallBoat_V2 first-person helm view: left-hand horizontal travel
  steers through IA_BoatMove.X; right hand vertical travel selects reverse, neutral, or forward.
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
  Expected logs: boat mesh anchors, boat throttle detent: forward|neutral|reverse.
  Tune live in the gestures table: boat_steer_range_m controls the horizontal travel to full
  rudder, boat_throttle_enter_m chooses forward/reverse, boat_throttle_release_m defines neutral,
  and boat_throttle_turnaround_m sets the hysteresis when changing direction.

  On the craft bench, craft_cursor_span_m changes how much hand movement spans the viewport.

These are smoke-tested against the bridge and fake UE objects. Check cursor reach, wheel alignment,
and detent feel in-headset; screen viewport scale and the player's natural hand reach need live
confirmation.

## Automated boat harness

Run `lua tests/run.lua boat` from the repository root. The targeted harness exercises third-person
third-person native-axis pass-through, camera-mode switching, first-person hand calibration, both rudder directions and center
deadzone, forward/neutral/reverse detents and haptics, and the post-game-tick cosmetic wheel copy
for left and right turns. Its fixture gives the wheel mesh a relative rotation offset to catch
component-versus-actor rotation mismatches. The expected source is
`BP_ShipSteeringWheel.ReceiveTick`, which copies the steering-wheel actor's world rotation to the
cosmetic actor. It uses fake UEVR/game objects, so it verifies bridge logic only; the headset
checklist above is still needed for the live wheel model, tracking reach, and haptic feel.
