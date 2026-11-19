# DreadmoorVR release video shot checklist

Use this as a capture list for a short vertical-slice release montage. Record clean source
footage first, then add labels and music during editing. Keep each demonstration long enough to
read without narration; use the optional caption to make the VR input clear to viewers.

## Capture setup

- [ ] Capture the game at the highest stable resolution and frame rate available.
- [ ] Record a clean gameplay track without debug overlays; capture a separate debug/log track
  only if needed for troubleshooting.
- [ ] Confirm the current mod build, UEVR profile, and Steam Frame input setup before recording.
- [ ] Use a save/location with a clear background and enough room to show hands and body movement.
- [ ] Leave a short pause before and after each action for clean edit points.
- [ ] Capture each feature twice: one natural-speed take and one close, readable take.
- [ ] Keep any release-status wording accurate: call features headset-validated only after the
  recorded take works as shown.

## Suggested vertical-slice sequence

### 1. Establish the mod

- [ ] **Opening gameplay shot:** first-person view in Dreadmoor, with the tracked hands visible.
- [ ] **Title card:** “DreadmoorVR” plus a concise subtitle such as “Tracked hands • gesture
  controls • boat and fishing support”.
- [ ] **Optional setup card:** identify UEVR and Steam Frame; avoid implying support for hardware
  combinations that have not been validated.

### 2. Finger tracking and hand poses

- [ ] **Independent finger tracking:** hold both hands in view and wiggle each finger one at a
  time; pause between fingers so the matching avatar digit is easy to see.
- [ ] **Open and close:** slowly open the hand, make a natural fist, then reopen it. Show both
  hands in separate takes if the camera cannot frame them clearly together.
- [ ] **Index point:** keep the other fingers curled and extend the index finger toward a visible
  object or UI target.
- [ ] **Middle-finger gesture:** keep the other fingers curled and extend the middle finger.
- [ ] **Thumb gesture:** show a clear thumbs-up, then return to a relaxed hand.
- [ ] **Close-up angle:** hold the hands against a contrasting background so finger curl and
  extension are visible. Avoid fingers crossing or clipping through one another in the take.
- [ ] Optional caption: “SteamVR finger curl tracking, smoothed into the in-game hand rig.”

### 3. Tracked arms and body response

- [ ] **Arm reach:** raise and lower each arm, reach forward, then bring the elbows back toward
  the hips; keep the hands in the game camera view.
- [ ] **Wave:** wave both arms naturally, then point in different directions. Show the avatar
  shoulders and elbows following the movement.
- [ ] **Turn and reach:** turn the head while moving one arm, then reach across the body. This
  makes it easy to see whether head motion and arm tracking remain independent.
- [ ] **Held-item alignment:** hold a tool, rotate the wrist, and show that the tool follows the
  hand with its intended grip orientation.
- [ ] Choose footage where elbows bend naturally and shoulders do not visibly twist or snap.

### 4. Grappling and tools

- [ ] **Aim:** bring the grapple gun up and aim using the tracked hand; show the reticle and gun
  direction together in frame.
- [ ] **Fire:** shoot a clear, safe target and let the hook travel far enough to read.
- [ ] **Grapple/reel:** attach the hook, then make the reel/cranking motion with the left hand near
  the right-hand tool. Show the rope or hook responding, then stop the gesture and show reeling
  stop.
- [ ] Optional pickup: show the gun from a side angle before firing so its hand alignment and
  orientation are apparent.

### 5. Melee guard

- [ ] Equip the sickle and show the ready stance.
- [ ] Bring the right hand in front of the torso and angle it down into the guard gesture.
- [ ] Hold briefly while an incoming attack is blocked, then release the gesture and make a
  normal attack so the two actions are distinguishable.
- [ ] Use a take where the avatar torso stays facing forward and the guard reads from the arm.

### 6. Fishing

- [ ] **Cast load:** bring the right hand beside the right ear and hold briefly.
- [ ] **Cast release:** extend the arm forward; keep the view steady and show the float landing.
- [ ] **Set the hook:** during the bite prompt, make one quick upward twitch. Include the prompt
  and the game's reaction in frame.
- [ ] **Fish fight:** move the right hand left and right from a relaxed neutral position; show the
  fight indicator responding in the same shot if possible.
- [ ] **Crank to reel:** while fighting the fish, rotate the left hand around the reel point near
  the right hand. Keep turning for a few beats, then stop and show the reel action stopping.
- [ ] **Directional QTE:** move the right hand horizontally and vertically in response to the
  on-screen QTE; preserve enough screen space to see both the hand and indicator.
- [ ] **Landing:** capture the actual FishLand prompt and outcome. Do not edit around a failed
  landing animation in a way that implies the mod fixed that base-game issue.
- [ ] Fishing crank, cast, hook-set, and QTE behavior need a clean headset-confirmed take before
  being presented as release-ready; the latest code smoke checks alone do not prove the in-game
  result.

### 7. Boat controls

- [ ] **Enter first-person helm:** show the transition and the first-person view with the head
  remaining hidden.
- [ ] **Hands on controls:** frame the left hand at the wheel and the right hand at the throttle.
  Hold still briefly so viewers can see the grip placement before moving.
- [ ] **Steer left and right:** make a gradual left arc, return through center, then make a right
  arc. Show the boat turning in the matching direction.
- [ ] **Throttle neutral:** hold the comfortable hip-fire position and show that the boat holds
  neutral.
- [ ] **Forward:** move the right hand diagonally forward to accelerate; show the boat gaining
  speed.
- [ ] **Reverse:** move the right hand deliberately back toward/behind the hip; show reverse
  engaging.
- [ ] **Detent feedback:** if the capture audio or controller telemetry can make it clear, show
  the haptic clicks at reverse, neutral, and forward transitions. Do not claim viewers can hear
  haptics unless they are actually represented in the footage.
- [ ] **Look around:** turn the head toward a side window while keeping the helm pose. Show that
  first-person head look remains available during steering.
- [ ] **Cosmetic wheel:** include a close shot of the selected wheel cosmetic while turning, to
  show whether it follows the base wheel. Use only if it stays aligned throughout the take.
- [ ] Use a take where the compass and controls remain visible and the torso does not obscure the
  dashboard. Keep the hidden-head first-person presentation.

### 8. Crafting and interaction

- [ ] **Craft-bench cursor:** open the crafting bench and move the hand to navigate the cursor
  across multiple options.
- [ ] Select an item or recipe and show the resulting game response.
- [ ] Include a short physical-controller input pass-through shot if it is useful to explain that
  native controls remain available alongside gestures.

### 9. Closing sequence

- [ ] Finish on a short gameplay beat combining tracked hands with one recognizable action, such
  as aiming the grapple gun or returning to the helm.
- [ ] Add a final card with the project name, repository/release link, supported setup, and beta
  status as applicable.
- [ ] Credit UEVR, OpenVR/SteamVR, Unreal Engine tooling, and any reused code/assets according to
  the project’s attribution notes and their licenses.
- [ ] Review the final cut for accidental debug text, desktop notifications, private paths,
  account details, or footage that contradicts the feature claims.

## Recommended edit order

1. Opening first-person gameplay
2. Finger tracking and fist/point gestures
3. Tracked arms and held-item alignment
4. Grapple fire and reel
5. Melee guard
6. Fishing cast, hook-set, fight, crank, and QTE
7. Boat wheel, throttle, and look-around
8. Craft-bench cursor
9. Closing gameplay and release card

## Claims to keep precise

- “Full finger tracking” is a useful feature heading, but describe it in detail as tracked
  finger-curl inputs driving the in-game digits; do not imply optical tracking of every joint.
- Distinguish gestures that have a clean headset-confirmed take from those covered only by local
  smoke tests.
- The mod adds VR input and presentation behavior around Dreadmoor’s existing systems. Do not
  imply it changes base-game fishing outcomes such as the reported fish-landing animation issue.
- Keep the first-person boat view headless, as designed; do not add a visible head for the video.
