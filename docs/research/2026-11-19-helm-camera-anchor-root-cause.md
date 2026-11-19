# First-person helm camera and hand anchoring: evidence review

Date: 2026-11-19
Scope: explain the repeated first-person boat failures and record the source changes made from the evidence. This is not a headset acceptance result.

## Summary

There are three coupled symptoms but at least three distinct systems:

1. The helm view is pushed forward by an unvalidated `-30 cm` camera offset, added on 2026-11-18. The player reports that the view is ahead of the character's neck and makes throttle reach hard to judge. This setting is the first camera variable to isolate; it should not be compensated by further arm/shoulder changes.
2. The visible hands are not proven to be attached to the controls. The current “pinned” log proves that two target components were assigned socket world positions. It does not prove the evaluated skeletal palms/wrists reached those targets. The arm solve and hand-joint telemetry are gated behind a reflected-method `type(...) == "function"` check. The current runtime log has target-pin messages but no arm-joint samples in helm mode. That is a high-priority diagnostic/fix candidate, not yet a proven sole cause.
3. Throttle and steering are computed from hand position relative to the *current HMD translation*, but transformed using the yaw captured at helm entry. This mixes a moving head-relative origin with a frozen orientation. Leaning/reaching/looking can therefore change the measured control reach even when the hand has not moved relative to the boat. The captured sequence shows large right-hand reach variation and persistent reverse; it is consistent with the user's report of unreliable throttle.

The video also shows the player looking forward and toward side windows. Thus the evidence does **not** show that HMD rotation is globally locked. Right-stick `IA_BoatLook` is deliberately suppressed in first-person helm; that is separate from head tracking. Camera position, HMD rotation, game camera yaw, and right-stick look must be tested and logged separately.

## Evidence reviewed

- OBS recording: `C:\Users\Bob\Videos\Mod Showcase\Mod Showcase 2026-11-19 07-40-25.mkv`, 4:31, 1920x1080 at 60 fps. The sampled drive sequence is in `artifacts/helm-captures-2026-11-19/video-drive-sequence/`.
- Runtime excerpt: `artifacts/helm-captures-2026-11-19/helm-log-excerpt.txt`, from `%APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\log.txt`.
- Current source: `src/scripts/m2_arms.lua`, `src/scripts/m3_gestures.lua`, `src/scripts/lib/boatcontrols.lua`, `src/data/dreadmoorvr_arms_tuning.lua`.
- Cooked Blueprint/parser research: `docs/research/2026-11-18-boat-blueprint-inspection.md` and `logs/re-bpdump-2026-11-18/BP_SmallBoat_V2.txt`.
- Relevant history: `2505877` (camera offset), `ce53196` (socket offset anchoring), `71e1a3d` (pose gate), `e5176c2` (control stabilization).

## What has been tried, and what it established

| Attempt | What changed | Evidence/result | What it did not establish |
|---|---|---|---|
| Helm camera advance (`2505877`) | Added `boat_camera_forward = -30 cm`; M2 applies it in boat mode. | Current log reports `VR_CameraForwardOffset=-30`. User reports view is too far forward. The commit itself says headset trial was needed. | No measured eye-to-neck offset or accepted headset comparison. This is not a validated camera fix. |
| Per-frame controller-local socket offsets (`ce53196`) | Recomputed MotionControllerState offsets from the wheel/throttle authored sockets. | Earlier live logs had non-finite controller bases and extreme world corrections (tens/hundreds of thousands of cm). | The UEVR controller-local and game socket world transforms were not reliably in the same frame. A logged computed offset did not mean a valid rendered hand. |
| Direct post-stereo socket target pin fallback (uncommitted current work) | Assigns VR arm target component world location/rotation from `LHand_Socket` / `RHand` after UObjectHook. | This run logged `boat hand post-stereo sockets pinned` at sane world positions. | This only proves target-component assignment. It does not prove AnimGraph/IK evaluation, palm orientation, wrist pose, or correct hand mesh on the grip. |
| Boat arm-solver gate (`5a147024`) | Runs solver in boat only when `type(pawn.K2_GetActorRotation) == "function"`. | Runtime log has no `arm L/R target` or `fit eye_ahead` samples after entering helm, although socket pins continue. The normal smoke fixture supplies ordinary Lua functions. | Whether UEVR exposes this reflected method with a type other than `function` in the live pawn. The harness currently cannot rule that out. |
| Throttle detents/hysteresis (`e5176c2` and current settings) | Added neutral calibration, stable detents, release/turn-around thresholds, and haptics. | M3 has valid L/R/H pose flags; captured values repeatedly hold reverse and `reach` varies from about `-0.09 m` to `-0.59 m`. Inputs are being produced. | Stable classifications do not prove a usable physical mapping. The logged reach is head-relative, not boat- or throttle-relative. |
| First-person right-stick look suppression | Suppresses `IA_BoatLook` while first-person helm is active. | Source logs “use head tracking to look”; the OBS samples include forward and side views. | It cannot be used as evidence that HMD rotation is frozen. It only removes right-stick camera input. |

## Concrete runtime observations

- At `07:42:24.534`, first-person boat gesture mode became active. It calibrated around `07:42:25.545`.
- The current camera offset was logged as `-30 cm`.
- At `07:43:19` to `07:43:50`, `poses_valid=Ltrue,Rtrue,Htrue` and `native_valid=true`; boat axes were emitted. Throttle was `-1` throughout the excerpt while right-hand reach varied substantially. This points to coordinate/calibration usability, not a total tracking outage.
- At `07:43:19.461`, HMD quaternion was `(0.010,0.828,0.055,-0.558)`, while game camera base yaw was `99.9°` and boat yaw `99.3°`. Later camera base yaw and boat yaw remain close. These are base component rotations; they do not expose the final eye orientation after HMD composition.
- The HMD quaternion changes over the captured interval, and OBS frames show forward and side-window views. That is evidence head rotation is reaching the view during this run, though it does not validate comfort, head position, or freedom from game-camera coupling.
- Socket pins report valid-looking world coordinates, but there are no corresponding evaluated hand/elbow/shoulder samples during helm mode. Therefore the strongest claimed success (“hands pinned”) was measured at the wrong layer.
- OBS drive frames show the left arm sometimes reaching toward the wheel. The right hand is low/by the hip in the sampled views, and neither hand is consistently demonstrated gripping its control. This matches the user's report; the mirror view alone cannot measure exact palm-to-socket distance.

## Likely root causes, ranked by evidence

### 1. Target pinning is being mistaken for rendered hand anchoring

`update_boat_hand_anchors` moves `actor.LeftHandTarget` / `RightHandTarget` to sockets. The character's hand mesh is driven through the bridge's arm solver and AnimGraph. The target pin occurs in `on_post_calculate_stereo_view_offset`, while the solver runs from `on_pre_engine_tick`; target changes may only affect a subsequent evaluation. More importantly, `solve_arms`/`sample_arms` run in helm only if `type(pawn.K2_GetActorRotation) == "function"`. UEVR reflected calls can be callable while Lua's `type` does not report a normal function (the same source has a comment about this behavior for another reflected method). If that gate is false, the target pins can succeed while the avatar never solves toward them. No helm joint telemetry currently distinguishes these cases.

**Conclusion:** strongest visual-anchor root-cause candidate. Add explicit gate/result logging and test the reflected call under `pcall`; never call a target-pin log “hands anchored” unless evaluated hand joints confirm it.

### 2. The helm gesture frame is head-relative and internally mixed

`step_boat` computes `hand - current_head` each update, then rotates that vector using `boat_reference_inv`, frozen from HMD yaw at helm entry. This makes the coordinate origin follow current head translation while the orientation does not follow current head rotation. Head lean can look like a hand movement to the throttle detector; turning to inspect windows can rotate the user's hand relative to the frozen frame. Neutral calibration is also taken from the current hand/head relationship after a short fixed interval. A forward camera offset does not directly alter raw SteamVR hand positions, but it changes visual reach and can encourage compensating body movement, which makes this mixed frame more painful.

**Conclusion:** high-confidence source-level flaw and likely contributor to throttle unreliability. The intended physical controls are fixed to the boat; positions should be evaluated in a stable boat/control frame, with an explicitly chosen neutral calibration, not against a moving head translation.

### 3. Camera tuning was changed without a controlled baseline

The `-30 cm` helm offset was added as a view-clearance guess and marked “headset trial needed.” The user now reports that the view is ahead of the neck. Later changes to arms/anchors do not validate or correct that camera origin. Other boat settings (`VR_MovementOrientation`, `VR_AimMethod`, `VR_RoomscaleMovement`) are temporarily changed by `boatcontrols.lua`; those are separate from the direct forward camera offset and HMD orientation.

**Conclusion:** revert/isolate the extra helm camera displacement to a measured baseline before adjusting controls or anatomy. Preserve normal HMD rotation. Measure eye origin against character neck/shoulder and control geometry, rather than tuning from a desktop mirror alone.

## Stop repeating these approaches

- Do not add more arbitrary centimeters to `boat_camera_forward` to hide a body/hand mismatch.
- Do not compute huge controller-local offsets from incompatible UEVR and game world transforms.
- Do not accept `boat hand post-stereo sockets pinned` as proof the visible skeletal hands are anchored.
- Do not change throttle thresholds while the coordinate origin is current-head-relative and the telemetry is already showing valid poses.
- Do not interpret matching base camera and boat yaw as proof the HMD view is locked; log final HMD-composited view or use a controlled head-turn capture.
- Do not change camera rotation to restore right-stick look until separately deciding whether the intended control is HMD rotation, right-stick look, or both.

## Non-circular fix and validation sequence

1. **Instrument before retuning.** In helm, log once per second: reflected-method gate state and `pcall` result; target socket world transform; hand target world transform; evaluated left/right hand and elbow joint world transforms; shoulder-to-hand reach errors; HMD pose; base camera pose; boat pose; active camera offset; and control-frame hand coordinates. Label targets and evaluated joints separately.
2. **Prove or remove the solver gate.** Attempt the reflected actor-rotation call under `pcall` and report its result. Avoid using `type(...) == "function"` as the availability check for a UEVR reflected function. If the solver fails, log the exception and fail safely; if it succeeds, ensure `solve_arms` and samples run in boat mode. Extend the fake-UE fixture to model the runtime reflection behavior only after observing it; a normal Lua method fixture is insufficient evidence.
3. **Fix coordinate definition.** Resolve hand and control positions into a stable boat frame (or use authored socket transforms as the reference). Keep HMD rotation available for looking. Head translation/lean must not shift the boat's neutral throttle point. Calibrate only after a deliberate neutral pose and ensure calibration timeout/failure leaves throttle neutral.
4. **Reset camera to an evidence-based baseline.** Isolate the `-30 cm` boat override and compare with the walking setting/zero offset while holding boat pose and controls constant. Measure eye-to-neck and eye-to-helm distances. Keep HMD yaw/pitch independent of the base camera/boat yaw and explicitly test side-window visibility.
5. **Validate anatomy, not component transforms.** With boat stationary, verify the evaluated palm center and wrist orientation are at the authored wheel/throttle grips. Then rotate the wheel/lever and boat; anchors must follow their control components. Confirm leaving the helm restores controller-driven hand targets. A component/socket log is necessary but not sufficient.
6. **Validate controls only after 1–5.** Repeat identical neutral, reverse, neutral, forward holds with head still, then with head turning/leaning while hands remain on controls. Throttle must remain stable under head motion; left/right steering must be symmetric. Save the runtime excerpt and screenshots/video with each trial.

## Acceptance gate

Do not call first-person helm ready until (a) user can look to both side windows with normal HMD rotation, (b) view origin sits plausibly at the character's head/neck, (c) evaluated left palm stays on the wheel and right palm/wrist stays on the throttle through control and boat movement, (d) head movement does not alter throttle while hands are held still, and (e) helm exit restores ordinary hand tracking. Current state fails or lacks evidence for (b)–(d).

## 2026-11-19 implementation from this review

The review findings have now been applied in source:

- `boat_camera_forward` is `-12 cm`, matching the walking camera baseline and removing the
  unvalidated extra 18 cm helm view advance. HMD rotation and right-stick policy are unchanged.
- The `type(pawn.K2_GetActorRotation) == "function"` helm solver gate is removed. The arm solver
  now runs for an active arms actor in boat mode; `pcall` reports a real reflected-call failure
  instead of silently skipping IK. A successful helm solve logs `boat arm solver active` once.
- M3 first looks for home using each controller relative to the current HMD pose. After home is
  recognized and held stable, it captures that HMD yaw and translation as the fixed control frame.
  Active hand coordinates then subtract that fixed origin instead of the moving head position, so
  head lean no longer redefines throttle reach and head turns do not rotate the control frame.
- Calibration waits for a broad recognized home pose: left hand in the upper-left wheel region
  (approximately 120 o'clock) and right hand in a lower, forward hip-fire neutral region. The player
  gets a log prompt and a right-controller haptic when that pose is recognized; both hands must
  remain stable briefly before neutral is captured. Throttle begins incremental forward input after
  5 cm of forward travel and requires a deliberate 15 cm pullback to engage reverse.

These changes were intended to address the camera displacement, silent solver skip, and moving
head-origin findings. They had not been hardware-validated at the time. The follow-up playback
below confirms that successful solver calls and socket-target logs did not prove that evaluated
palms touch the grips or that the view is at the character's head.

## Follow-up playback: 2026-11-19 08:32

The user's `Mod Showcase 2026-11-19 08-32-30.mkv` and the matching runtime log show the earlier
changes did not finish the helm work. The M2 solver is active, but it still reports grip targets
about 127–165 cm from the shoulders while the arm chain is about 66 cm. Socket pinning therefore
does not make the rendered hands reach the wheel and throttle. No avatar translation should be
guessed from those samples; we need the live boat, body, grip, and camera transforms in one frame.

The persisted UEVR `config.txt` still had `VR_CameraForwardOffset=-30`, while M2 changes the live
value to `-12`. The profile now saves `-12` too, to prevent the old startup value from returning.
The previous `fit eye_ahead` measurement is not enough to position the camera because it does not
compare the boat's actual first-person camera component with the copied body's head socket. M2 now
logs those component/socket world positions and their boat-relative separation once per second.

The throttle sign was not flipped. The cooked boat Blueprint expects positive Y for forward, and
earlier playback samples show the current positive-reach path entering forward and a deliberate
pullback entering reverse. This latest report still describes intermittent forward-to-reverse
behavior, so the reverse detent now requires 22 cm of pullback and a 250 ms stable hold (previously
15 cm and 120 ms). The new debounce reduces brief tracking spikes; it does not prove the user's
forward gesture is now reliable. Hardware validation remains outstanding.

## Transform correction from 08:59 live telemetry

The next runtime log exposed a more specific failure. The authored boat grips were around
`(34287, 52022, 465)`, while the controller targets were around `(10816, 61301, 2376)` and
`(14922, 100550, -7397)`. M2 allowed these tens-of-thousands of centimeters as valid offsets, so
the target bones were never at the controls. Its direct socket fallback also aborted because the
right controller target had no usable rotation snapshot.

The copied body's head socket was `(34374, 52002, 503)` and the live first-person camera component
was around `(34276, 52048, 525)`, about 1 m apart. The shoulder-to-grip midpoint was about 84 cm
forward. This explains why changing `VR_CameraForwardOffset` did not fix the model/view alignment:
the copied character remained displaced from the helm.

M2 now rejects controller-to-socket corrections above 150 cm and switches to the direct authored
socket path. A missing optional controller transform snapshot no longer blocks that fallback. The
arm solver receives the authored wheel/throttle socket positions directly while UObjectHook uses a
different world frame. During first-person helm use, the copied visual body is translated so its
head socket sits 10 cm behind and 5 cm above the live boat camera component; M2 saves and restores
the original relative transform on helm exit/reset. HMD rotation and tracking are left intact.

This transform correction follows measured component/socket positions; it has not been headset
validated. Acceptance still requires hands on the grips, natural body alignment while looking at
side windows, correct throttle direction, and restored controller-driven hands after helm exit.

## 09:23 OBS follow-up

Reviewed `Videos/Mod Showcase/Mod Showcase 2026-11-19 09-23-08.mp4` alongside the 09:27–09:28
M2 telemetry. First-person frames show the copied chest intersecting the dashboard and covering
part of the compass. The head socket and camera component are now close (about 12 cm apart), so
the previous 1 m body/camera gap is corrected. However, that correction moved the entire torso
forward to the game's camera location, and the user's view still feels too far forward.

At 09:28:49 the authored grip targets were still 54 cm (left) and 77 cm (right) from the evaluated
hand bones. This means socket targets and near-camera head alignment do not yet prove the visible
hands reach the controls. The target-to-hand distance and solver's 65 cm arm chain are logged
separately.

The `+30 cm` helm offset was trialed live and rejected: at 09:49 the runtime confirmed `+30`, while
the user reported the view had moved farther forward. Screenshots showed the torso clipping the
lower dash and the compass partly obscured. Source now uses `boat_camera_forward=-30 cm` and maps
the active setting directly into the copied head placement, keeping the head 10 cm behind the
shifted eye; walking remains `-12 cm`. This sign correction follows the live headset report, but
is not an accepted fix. Reload Lua and check compass readability, chest clearance, grip contact,
and side-window head turns before calling the issue fixed.

## 09:57 OBS review and follow-up

Reviewed the complete 09:57:49–10:00:21 OBS recording with its matching M3/M2 logs. The centered
view shows the compass clearly and the camera can look toward the side windows. The copied diver
torso and sleeves still fill the lower cockpit view and cover part of the dashboard, so the body
presentation remains a headset acceptance issue. M2 samples put each evaluated hand within 2 cm
of its authored grip target; that verifies the solver's joint goal, not natural wrist rotation or
visible contact in every frame. Do not move the camera again from those measurements alone.

The strongest throttle/camera failure evidence is at 09:57:23: the HMD pose changes to exactly
`(0,0,0)` and stays there while both hand positions stop changing. The log still labeled those hand
poses and the native heartbeat valid, and the last forward input remained active. M3 now rejects an
HMD pose at the tracking origin and neutralizes both boat axes. This protects against frozen finite
controller samples when HMD tracking has dropped. Throttle detent confirmation is back to 250 ms
to reject brief crossings; the measured 22 cm reverse threshold and calibrated home pose remain.

The 09:57:58 home sample also measured the intended left hand at `y=-0.77 m`, just outside the old
`-0.75 m` gate. The recognition bound now includes that pose and its measured variation. A later
10:00 sample still failed home recognition because both hands were far from the prescribed home;
that is expected and should leave input neutral. The latest OBS is not enough to claim camera/body
alignment or grip contact is fixed; it narrows the next headset check to visible chest clearance,
wheel/throttle hand contact, and side-window head movement after tracking recovers.

## 10:27 OBS follow-up

Reviewed `Videos/Mod Showcase/Mod Showcase 2026-11-19 10-27-28.mp4` against the 10:27–10:32
runtime log. The cockpit view is substantially better: the compass remains readable, both hands
are visible near their controls, and the left steering input reaches both sides (logged values
approach `-1.0` and `+1.0`). The right hand enters forward at roughly 9 cm travel and reverse only
after a clear pullback (logged reach around `-0.29` to `-0.49 m`). Neutral/forward transitions
occur as the hand crosses back through the calibrated neutral band; the 250 ms confirmation is
already in place, so I left the thresholds alone rather than adding more latency.

The headless silhouette appears when the camera pulls back far enough to expose the copied diver's
torso while its head remains hidden. M2 spatial samples show a stable camera-to-head component
offset of roughly 40 cm as the boat turns; this is consistent with the configured helm offset, not
evidence that the Lua camera transform is jumping with throttle. The user explicitly wants to keep
the head hidden and first-person immersion, so no head visibility change was retained. The clip and
logs show hand goals staying within about 1 cm of targets while camera/body visuals change. Do not
hide the full arms body or switch to third person as a workaround; further correction should target
the boat camera/seat transform while preserving the hidden head and tracked arm render.

The 10:27–10:32 clip contains no fishing fight/crank attempt, and its runtime log has no fishing
crank events, so there is no fresh headset evidence for reel sensitivity. The detector previously
required 180 degrees/second and reset immediately if measured radius crossed 4 cm or 25 cm. M3 now
uses a 110 degrees/second gate and 2.5 cm exit hysteresis after acquiring the crank radius. The
shared HMD validator also rejects the tracking-origin pose for fishing actions, releasing held reel
input if the same HMD tracking loss happens during a fish fight. Smoke tests cover slower turns,
radius jitter, and HMD-origin release. Keep the camera in first-person and keep the copied head
hidden; no camera offset or visibility change was made in this pass.

## 2026-11-19 late-session follow-up

The late-session 11:29–11:31 logs refine the throttle diagnosis above. Build `26786104` still maps
positive `IA_BoatMove.Y` to the forward lever target; the runtime trace shows positive input while
the boat travels forward and negative input while it backs up. The sign itself is not reversed.
The remaining error was the gesture projection: M3 used head-relative Z with the HMD yaw frozen at
helm entry. After the HMD turned, the same intended reach could cross the frozen frame's reverse
threshold.

M3 now anchors the neutral right-hand position in tracking space and projects its displacement onto
the current HMD forward axis while the throttle is neutral. Once a detent is requested, the axis
freezes through the transition and hold. This is deployed, but still needs neutral, forward,
reverse, and head-turn validation in the headset.

The same run showed repeated fishing crank releases/reacquisitions on pose discontinuities. Fight
lean was also projected against the live HMD pose each sample while fishing mode set
`VR_AimMethod=1`. M3 now locks a hand-control origin and orientation per struggling-fish instance,
leaving HMD aim for the view. This should stop head turns and fishing-camera motion from rotating
the rod gesture axes. It also needs a headset retest.

OBS samples and the full runtime excerpt referenced above remain in the local `artifacts/` folder;
they are intentionally not part of the source commit. The updated cooked boat Blueprint dump is
tracked at `docs/research/bp-dumps/BP_SmallBoat_V2-build-26786104.txt`.
