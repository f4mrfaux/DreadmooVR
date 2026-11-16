# Dreadmoor VR: gesture fishing and crafting — design

Date: 2026-11-15 (rewritten the same evening for the pak + bridge route)
Status: **approved by Bob 2026-11-15**, with the hook gun added to version 1. Nothing is built.

What changed from the first draft: Bob rejected hidden arms and marker hands. The mod now
shows real arms and hands, authored in the Unreal editor and shipped as a content pak. A thin
UEVR script connects them to the game. The experience goals, game seams and gesture
definitions carry over from the first draft unchanged.

Evidence: [game-code answers](../../research/2026-11-15-game-code-answers.md),
[recon](../../research/2026-11-15-dreadmoor-recon.md),
[editor tooling](../../setup/unreal-editor-mcp.md).

## 1. Intent

Bob wants to play Dreadmoor in VR on a Steam Frame, with his hands doing the fishing and the
crafting instead of buttons. The game is built around handling tools, which is why he thinks
it suits VR.

In his words, the three things that matter:

- reel by cranking the left hand close to the right,
- pull the fishing rod around when fighting a fish,
- pick up and drop things on the crafting bench.

He decided the boat stays on thumbsticks. A grabbable steering wheel is out for now.

His quality bar: "no sense in doing something if it isn't done well." Version 1 is scope A:
real arms and hands that follow him in every mode, the rod in a visible hand, items carried
at the bench, and the game's own rules unchanged.

## 2. Goals, non-goals, anti-goals

### Goals for version 1

1. The whole game is playable in the headset through UEVR, with the Frame controllers acting
   as the gamepad the game already supports.
2. **Real arms and hands in every mode**, on the game's own character model, following the
   controllers with proper elbow bend, and fingers that close with the grip.
3. Fishing is physical: the rod is held in a visible right hand, the left hand cranks to reel,
   leaning the rod fights the fish, a flick casts, a yank sets the hook.
4. The crafting bench is physical: reach to a pile, grab, see the item in the hand, let go
   over the bench.
5. The hook gun is physical: aim it with the hand, pull the trigger to fire, crank its handle
   with the left hand to drag the hooked thing in. Faster cranking pulls harder.
6. The hands feel the game: line tension, bites, and the hook gun's fire and cranking as
   vibration.
7. Every gesture has a button that does the same thing. Gestures add to the controls and never
   replace them.
8. Gesture feel and arm fit can be tuned in seconds without restarting the game. Only new
   poses or new assets need a re-cook.

### Non-goals for version 1

- Boat gestures or a grabbable wheel. Arms still show on the boat.
- Gestures for diving, the generator, the water pump, lockpicking, the radio or the safe.
- Gestures for the harpoon and knife. They aim with the hand (UEVR's aim method) and fire on
  buttons, held in a visible hand, but have no special gestures.
- Hands touching the world physically (pushing objects, collision with walls).
- Left-handed layout.
- Packaging for public release.
- Controller-free hand tracking. The Frame does not offer it.

### Anti-goals: these make it a failure even if it runs

- A gesture that fires when the player did not mean it, for example reeling while scratching
  an arm.
- The game turning the player's view for them while in the headset.
- Needing a button press in the middle of a chain of physical moves.
- Arms that visibly lag, stretch, snap or bend the wrong way.
- Damage to a save file, or a change to any file the game shipped with. The mod adds one
  folder (`Content\Paks\~mods`) and the UEVR profile. Deleting both removes it completely.
- The mod's pak replacing any of the game's own assets.
- A gesture that works only at one exact speed or angle.

## 3. Constraints

- **No source code.** The game is a shipped Unreal Engine 5.6.1 build.
- **UEVR on 5.6.1 is unproven.** Official support stops at 5.4. Nightly builds are reported to
  handle 5.5 and 5.6. No Dreadmoor profile exists. This is tested first (M0).
- **The game ships as IoStore** (`Dreadmoor-Windows.utoc/.ucas/.pak` plus `global.utoc/.ucas`).
  The mod must be cooked the same way. No `.sig` files are present, so the game does not
  appear to check pak signatures. Confirmed only when M1 loads a pak.
- **A pak cannot edit the game's Blueprints and cannot start itself.** Nothing in the game will
  ever spawn the mod's actors. The bridge script must load and spawn them.
- **Cooking a reference to a game asset needs a stand-in at the same path.** The editor project
  is named `Dreadmoor`, so its `/Game/...` paths match the game's. A stand-in is cooked against
  and then left out of the pak, so at runtime the reference resolves to the game's real asset.
- **UE5 assets need a mappings file to be read outside the game.** Exporting the character
  mesh and skeleton for stand-ins needs a `.usmap` from a runtime dump (M0).
- **Each activity is its own pawn** with its own camera: walking, fishing, crafting, boat,
  diving. The bridge sets itself up again on every switch.
- **Reeling is one on/off flag** in the game (the cast action held). Crank speed cannot matter.
- **The fight input has three positions:** left, centre, right, with a 0.5 threshold.
- **The rod follows the look direction** in the game, and the game steers the view toward the
  fish during a fight. Both have to be overridden.
- **The crafting bench is a mouse-cursor screen.** Hover is a ray from the mouse. A click moves
  exactly one unit between shelf and table.
- **Scripts cannot intercept calls the game's Blueprints make to each other.** They can read,
  call, and overwrite results after the game's tick.
- **Game updates** can rename things. Game names the mod depends on live in one module.
- **Use UE 5.6 only** for cooking. UE 5.8 is installed too and must not be used.
- **Bob is cautious about downloads.** Anything new is named and approved first. Known so far:
  FModel (for exporting the mesh and skeleton), and possibly a UEVR nightly.
- **The game never runs standalone on the Frame.** It runs on the PC and streams through
  SteamVR.

## 4. Approach

**Chosen by Bob: pak + bridge.** Each half does what it is good at.

| | Content pak (`DreadmoorVR_P`) | UEVR bridge (Lua) |
|---|---|---|
| Made in | UE 5.6 editor, `unreal/Dreadmoor`, authored through the EngineWire MCP | Text files in the repo |
| Holds | Everything visible: arms actor, animation Blueprint, hand poses, carried-item attach | Everything that touches the game: mode detection, gestures, inputs, game calls, haptics |
| Knows game classes? | No. Only the stand-in mesh and skeleton | Yes, through UEVR reflection, all in `gameapi` |
| Change loop | Re-cook, restart the game | Reload in seconds |
| Talks to the other half | Exposes a small set of variables and functions on `BP_VRArms` | Sets them every frame |

Why this split is the elegant one:

- The art gets the editor's real tools: two-bone IK, pose blending, sockets. Writing those by
  hand in Lua, one bone at a time, is slower to build and looks worse.
- The pak never references game Blueprints, so it needs no stand-in classes for
  `BP_FishingController` and friends. Only a mesh and a skeleton are stubbed.
- When the game updates, the fragile part is the script, where fixes are quick.

Considered and set aside:

- **Arms built entirely from script** with `UPoseableMeshComponent`. Possible (the functions are
  in the game), but IK and finger poses would be hand-written math. Rejected on quality.
- **A C++ UEVR plugin as the bridge.** Kept as the fallback for any single job Lua cannot do,
  most likely loading the pak's class (see risks).
- **UE4SS as the loader.** It can spawn pak actors itself, but adds a second injector next to
  UEVR. Only if UEVR cannot load the class.
- A custom injector or native OpenXR integration. That rebuilds what UEVR already does.

## 5. What the player experiences

### Getting in

Start SteamVR streaming to the Frame, start the game, inject UEVR. The profile loads the
bridge, which spawns the arms. Nothing else to do.

### Arms, everywhere

From the first frame in the headset, the player sees their own arms in the game's character
style, from the shoulders down, following the controllers. Elbows bend naturally. The fingers
curl as the grip is squeezed and the index finger follows the trigger. The game's own body
keeps its legs and shadow, but its arms are hidden so there is never a second pair.

If the player reaches further than the character's arms can, the shoulder follows the hand
instead of the arm stretching. The hand never leaves the controller (D12).

### On foot

Stock UEVR movement: left stick moves, right stick turns, buttons follow the game's gamepad
layout. On top:

- The view stays level while walking. The game's camera rides the head bone and bobs. The mod
  takes the view from the body's position at eye height instead.
- The head mesh is hidden so it does not clip into view.

### Fishing

Walking up to a fishing spot and interacting works as in the flat game. Then:

```
IDLE        CAST               WAIT    BITE          FIGHT                    LAND
rod in  →   raise rod back, →  …   →   buzz in   →   lean rod left/right, →   yank up
hand        flick forward              rod hand,     crank left hand          when prompted
                                       yank up       beside the reel
```

| Moment | What the hands do | What the player feels and sees |
|---|---|---|
| Idle | Right hand holds the rod. It follows the hand exactly | The right hand is closed round the rod's grip. Reel and line as in the game |
| Cast | Raise the rod back past upright, then flick forward | The game's power meter fills while the rod is back. The float lands where the rod points |
| Bite | Yank the rod up | A sharp buzz in the rod hand when the fish bites |
| Reel | Left hand circles beside the reel, either direction | Near the reel, the left hand takes a pinch grip on the handle. A tick per turn. Reeling stops a quarter second after the hand stops |
| Fight | Lean the rod left or right past about 15 degrees | Vibration in the rod hand that grows with line tension |
| Land | Yank up when the landing prompt shows | A buzz on success |

The view is never turned by the game. The head looks where it likes. The game's fisherman
body for this pawn is hidden and replaced by the mod's arms.

Prompts that interrupt a fight (the drag-in-a-direction prompt, the reel-timing prompt) stay on
buttons in version 1. See decision D4.

### Crafting bench

Interacting with the bench works as in the flat game. Then:

- Both arms are there, as everywhere.
- Moving a hand within reach of a pile highlights it, using the game's own highlight and hint.
- Squeezing the grip picks one unit up. The hand closes and holds a copy of that pile's own
  item model.
- Letting go more than about 15 cm from where it was picked moves that one unit to the other
  side: shelf to bench, or bench back to shelf. Letting go close to the pile cancels.
- A pile out of reach can be picked by pointing at it. The index finger points and the nearest
  pile to the pointing ray highlights.
- Crafting itself, recipes and leaving stay on buttons.

Limit carried over from the game: one grab moves one unit. Items cannot be thrown or set down
anywhere else.

### Hook gun

Equip the hook gun as in the flat game. Then:

| Moment | What the hands do | What the player feels and sees |
|---|---|---|
| Hold | Right hand holds the gun | The hand is closed on the grip, the gun points where the hand points |
| Aim | Point the gun | The hook goes where the gun points, not where the head looks |
| Fire | Pull the trigger | A kick in the gun hand. The hook flies along the gun's line |
| Drag | Left hand turns the gun's crank, either direction | Near the crank, the left hand takes a pinch grip on it. A tick per click. The faster the crank turns, the harder the hooked thing is pulled. Stop cranking and the pull fades away, as in the game |
| Arrive | Nothing, once it is close | The item is looted or the hook returns, as the game decides |

Any prompt that appears after a hit (the game has a "twist" prompt animation) stays on buttons
in version 1, like the fishing prompts.

### Boat, diving, menus, everything else

Stock UEVR with the gamepad layout. Arms show and follow the controllers. No gestures.

### Buttons always work

The physical trigger still reels, the stick still fights, the face button still clicks a
pile. A gesture and its button can be mixed freely.

## 6. How it is built

### The pak

Made in `unreal/Dreadmoor` (UE 5.6), cooked to IoStore as `DreadmoorVR_P.utoc/.ucas/.pak`,
installed to `D:\SteamLibrary\steamapps\common\DREADMOOR\Dreadmoor\Content\Paks\~mods\`.
Mod assets live under `/Game/DreadmoorVR/` so they cannot collide with the game's.

| Asset | What it is |
|---|---|
| Stand-in skeleton and mesh | The game's player mesh and skeleton, exported with FModel and imported at their original `/Game/...` paths. **Never cooked into the pak.** Excluded in packaging settings and checked in the pak's file list every build |
| `BP_VRArms` | Actor with one skeletal mesh component using the stand-in mesh. Hides every bone that is not shoulder, arm or hand. Has sockets `Grip_R`, `Grip_L` for held things |
| `ABP_VRArms` | Animation Blueprint on the stand-in skeleton. Two Two-Bone IK nodes driven by hand targets, a wrist rotation per hand, and a per-hand pose blend |
| Hand poses | A pose asset with: open, relaxed, fist, rod grip, reel pinch, item hold, point. Authored in the editor, tuned by eye with Bob |
| `BPI_VRArmsControl` | The interface the bridge calls, so the bridge never needs to know the Blueprint's insides |

`BPI_VRArmsControl`, the entire contract between the halves:

| Call | Meaning |
|---|---|
| `SetHandTargets(LeftXf, RightXf)` | Controller transforms in world space, every frame |
| `SetHandPose(Hand, PoseName, Weight)` | Which authored pose a hand is in |
| `SetFingerCurl(Hand, Grip, Trigger)` | Analogue curl on top of the pose, from the controller |
| `SetFit(ShoulderOffset, ArmScale, Offsets...)` | Tuning values from the bridge's config, so fit is tuned without a re-cook |
| `AttachToHand(Hand, Mesh)` / `ClearHand(Hand)` | Show an item mesh in a hand's grip socket |
| `SetArmsVisible(bool)` | For menus and cutscenes |

Because the skeleton stand-in sits at the game's own path and is not cooked, at runtime
`ABP_VRArms` binds to the game's real skeleton object. No retargeting.

### The bridge

One UEVR profile for `Dreadmoor-Win64-Shipping`, with UEVR settings and Lua units. Each frame:

1. **Know the mode.** Read which pawn is possessed and map its class to walking, fishing,
   crafting, boat, diving or unknown. Match on the base class, since fishing has ground and
   tutorial variants. On a change, undo the old mode's setup and apply the new. Unknown means
   arms on, gestures off.
2. **Read the hands.** Controller poses from UEVR, kept as a short history so speed and
   rotation can be measured.
3. **Drive the arms.** Send hand targets, poses and curl to `BP_VRArms`.
4. **Detect gestures.** Small detectors turn pose history into events and held states.
5. **Tell the game.** Mostly by pressing buttons on the emulated gamepad. Where no button
   exists, by calling the game's own functions.

| Unit | Job | Depends on |
|---|---|---|
| `main` | Wires UEVR callbacks to the units below | all |
| `gameapi` | The only place game names appear. Finds objects, reads values, calls functions, and returns nil safely when something is missing | UEVR |
| `arms` | Loads the pak's `BP_VRArms` class, spawns it, keeps it alive across pawn switches, and is the only caller of `BPI_VRArmsControl`. Hides the game body's arms and head for the current pawn | UEVR, `gameapi` |
| `modes` | Possessed pawn class → mode. Runs enter and exit steps | `gameapi` |
| `poses` | Controller poses in game space, with a history ring and derived velocities | UEVR |
| `gestures/crank`, `flick`, `yank`, `lean`, `reach` | Pure functions: pose history in, events out. No UEVR or game calls | none |
| `pad` | A virtual gamepad. Units ask for buttons and axes. Merged into the real pad state: buttons are OR-ed, an axis is overridden only while a gesture holds it | UEVR |
| `fishing` | Fishing mode: rig setup, rod and reel hand poses, which gestures are live in which game state, outputs | `gameapi`, `arms`, `gestures`, `pad`, `haptics` |
| `crafting` | Bench mode: hover, grab, carried item, release | `gameapi`, `arms`, `gestures`, `haptics` |
| `walking` | Level view | `gameapi` |
| `hookgun` | While the hook gun is equipped on foot: gun in the right hand, hand aim, crank → clicks | `gameapi`, `arms`, `gestures`, `pad`, `haptics` |
| `haptics` | Named effects (tick, buzz, continuous level) per hand | UEVR |
| `config` | Tunable numbers for gestures and arm fit, loaded from a file, reloadable while running | none |
| `debug` | On-screen state readout and a pose recorder | all |

The gesture detectors are free of game and UEVR calls so they can be tested at a desk with
recorded hand motion.

### Where each gesture meets the game

| Gesture | Game seam | Why this seam |
|---|---|---|
| Crank → reel | Hold the cast button on the virtual pad (right trigger) | Reeling in the game is exactly "cast held" |
| Lean → fight | Fight stick X to −1 or +1 on the virtual pad | The game only reads left, centre, right |
| Flick → cast | Press cast at wind-up, release at the flick | The game charges power between press and release |
| Cast direction | Control rotation follows the rod hand (UEVR aim method set to right controller while fishing) | The game aims the cast along control rotation |
| Yank → hook | Tap cast | The bite prompt listens for a cast press |
| Yank → land | Tap the QTE interact button | The landing prompt listens for it |
| Rod in hand | Attach the fishing rig's root (`RotateScene`) to the right controller with UEVR's object hook, marked permanent, offset so the grip sits in `Grip_R` | The game re-aims the rig every tick. A permanent attachment is re-applied after it |
| Game arms hidden | Hide the fishing rig's body mesh (`GG_FishermanMix`). On foot, hide the arm and head bones of the player mesh with `HideBoneByName` | Replaced by `BP_VRArms` |
| No forced view | UEVR drives the view from the headset. The game's steering of control rotation is overwritten each frame by the aim method | The steering call cannot be intercepted from a script |
| Tension, bite | Hook the game's feedback function (`DrdControllerFeedbackLibrary.PlayControllerFeedback`), which is native and receives the event and strength. Fall back to reading tension from the fishing pawn each frame | One hook covers every haptic event the game already defines |
| Is a prompt showing | Read `CurrentQTE` on the fishing pawn, a gameplay tag that is `None` when no prompt is up | Gates the yank so it cannot fire at other times |
| Where the fish is | Read the `StrugglingFish` actor on the fishing pawn. It is null when nothing is hooked | Gives the lean its neutral line, and tells cast gestures from fight gestures |
| Bench hover | After the game's tick, set `HoveredPile` and call `SetIsHovered` from hand position | The game's own hover comes from the mouse and is overwritten |
| Bench grab and release | Call `ClickPile()` on the source pile at release | It is the game's own one-unit transfer |
| Carried item | Read the pile's item mesh and pass it to `AttachToHand` | Shows the real item, not a token |
| Bench camera | Zero the mouse-tilt angles on entering the bench | The game tilts the camera toward the mouse |
| Hook gun in hand | Re-attach the equipped `BP_HookGunEquipment` from the character mesh's socket to `Grip_R` | The game attaches it to its own hidden arms |
| Hook gun aim | UEVR aim method set to the right controller while the gun is equipped | `GA_HookGun.CalculateLaunchTransform` traces from `GetPlayerViewPoint` |
| Fire | The real trigger, unchanged | The ability fires on the primary-use press |
| Crank → drag | Each crank click (about 90 degrees of handle, tunable) is a short press and release of primary use on the virtual pad. While the crank is active the virtual pad owns that button, so a held real trigger cannot swallow the taps. The exact press and release rules are checked in M0, since a release near the item also loots it (`TryLoot`) | Each press adds `DragForcePercentPerClick` to `DragForceMul`, capped at `Config.MaxMultiplier`, and it decays by 0.008 a tick. Crank speed becomes pull strength directly |

### Gesture definitions (starting values, all tunable)

- **Crank.** Take the reel point as a fixed offset from the right controller and the reel axis
  as the controller's sideways axis. Measure the left hand's angle around that axis. Active
  when the hand is 4 to 25 cm from the reel point and has turned faster than 180 degrees per
  second for 150 ms. Stays active for 250 ms after it drops below. Either direction counts.
  The same detector serves the hook gun with its own crank point and axis. For the rod it
  outputs a held state; for the hook gun it outputs a click every 90 degrees turned.
- **Lean.** Angle between the rod's forward direction and a neutral line, measured flat. The
  neutral line is the direction to the hooked fish when known, otherwise the cast direction.
  Enter at 15 degrees, leave at 10. A config switch inverts left and right, because the code
  does not say which way reads correctly on screen.
- **Flick.** Wind-up begins when the rod tilts back past 60 degrees. The flick is a forward
  swing faster than 250 degrees per second that then crosses 30 degrees forward of upright.
- **Yank.** Rod tip moving up faster than 1.5 m/s. Only listened for while a bite or landing
  prompt is showing.
- **Reach.** Nearest pile within 12 cm of a hand. Otherwise nearest pile within 10 cm of a ray
  along the controller's aim direction.

Gestures are only live in the game state they belong to. A crank does nothing unless a fish is
on. The preferred source is the fishing pawn's `State` value. If that cannot be read, a
coarser rule applies and must still hold: with a fish hooked, only crank, lean and yank are
live. With no fish hooked, only flick and yank are live. A wind-up during a fight must never
press cast, because cast is also reel.

### Project layout

```
unreal/Dreadmoor/        UE 5.6 project: stand-ins, /Game/DreadmoorVR/ assets, EngineWire
src/scripts/             Lua bridge units listed above
profile/                 UEVR config.txt and object-hook state for this game
tests/                   desk tests for the gesture detectors, with recorded pose traces
tools/re/                existing analysis scripts
tools/cook.ps1           cooks the pak with UE 5.6, then fails if any stand-in is in its file list
tools/deploy.ps1         copies the pak to ~mods and the scripts and profile to the UEVR folder
docs/                    research and this design
```

Nothing is written outside `Content\Paks\~mods\` and
`%APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\`.

### Testing

- **At the desk:** each gesture detector is run against recorded pose traces: fast, slow,
  sloppy, and ordinary movement that must not trigger it.
- **In the editor:** `ABP_VRArms` is checked in a test level with targets moved through a
  recorded pose trace: no flipped elbows, no stretching, poses blend cleanly.
- **Every cook:** `cook.ps1` lists the pak's files and fails on any path outside
  `/Game/DreadmoorVR/`.
- **In the headset:** a short checklist per milestone, run by Bob. Each line is something he
  does and what he should see.
- **Mode switching:** enter and leave each mode twice in a row. Nothing from one mode may
  remain in the next, and the arms never disappear or double.

## 7. Milestones

Each one ends with something Bob can try. M0 and M1 are go/no-go gates.

**M0. Does UEVR work here?** Before anything is built. Bob runs it in the headset; the builder
prepares the checklist and reads the log. Use the UEVR build in `Downloads\UEVR` (revision
`1a810f69`). If it fails, try the latest nightly, with Bob's approval to download.
Check stereo and head tracking in each pawn, the controllers as a gamepad, and the view in
each mode. Also collect: a `.usmap` mappings dump, the player mesh and skeleton paths and bone
names, the fishing state values, the gamepad buttons for the prompts, which way the fight
indicator reads, how the cast power meter behaves, and whether the line follows a moved rod.
*If UEVR cannot hook or render the game, stop.*

**M1. Does a pak load?** Cook a probe pak with one actor (`BP_PakProbe`, a cube that prints a
message), drop it in `~mods`, and have the bridge load the class and spawn it in front of the
player. Proves IoStore cooking from 5.6, mounting, no signature check, and class loading from
Lua. *If Lua cannot load the class, that one job moves to a small C++ UEVR plugin. If the game
will not mount the pak at all, stop and bring options to Bob.*

**M2. Bridge skeleton.** Mode detection with an on-screen readout, the virtual pad, config
reload, the pose recorder, `cook.ps1` and `deploy.ps1`. *Done when* the readout names the right
mode through walk → fish → walk → bench → walk → boat → walk.

**M3. Arms.** Export and import the stand-ins (FModel download, with approval), build
`BP_VRArms`, `ABP_VRArms` and the hand poses, wire the bridge's `arms` unit. *Done when* Bob
sees his arms on foot, they follow his hands with no lag or flipped elbows, fingers follow the
grip and trigger, the game's own arms and head are gone, and the walking view is level.

**M4. Rod in hand.** The rig follows the right hand with the hand closed on the grip, the
fisherman body hidden, the view never steered. *Done when* Bob can wave the rod around with
the view staying put, and cast with the trigger.

**M5. Fishing gestures.** Flick, yank, crank (with the reel pinch pose), lean, and haptics.
*Done when* Bob lands a fish start to finish without touching a button, outside the interrupt
prompts.

**M6. Crafting bench.** Hover, grab, carried item, release, pointing fallback. *Done when* Bob
loads a recipe's ingredients onto the bench and takes one back, by hand.

**M7. Hook gun.** Gun in hand, hand aim, fire on trigger, crank to drag, haptics. *Done when*
Bob hooks a floating item, cranks it in, and loots it, with the crank speed visibly changing
how fast it comes.

**M8. Tuning and tidy-up.** Arm fit and thresholds from Bob's play sessions, false-trigger
fixes, a short readme. *Done when* Bob plays a full session without a gesture misfiring or an
arm glitch.

## 8. Risks

| Risk | What happens | Response |
|---|---|---|
| UEVR does not run on 5.6.1 | Nothing works | M0 finds out first. Stop there |
| The game will not mount a mod pak | No arms | M1 finds out. Check mount order and IoStore settings; then bring options to Bob |
| UEVR Lua cannot load an unloaded class from the pak | Arms cannot be spawned | M1 finds out. Small C++ UEVR plugin calls the engine's class loader. UE4SS as a last resort |
| A stand-in gets cooked into the pak | The game's own character mesh is overwritten | `cook.ps1` fails the build on any path outside `/Game/DreadmoorVR/` |
| The AnimBP rejects the game's skeleton at runtime | Arms in reference pose or not shown | Stand-in at the same path should resolve to the same object. If not, set the stand-in as a compatible skeleton, or drive bones from the bridge with `UPoseableMeshComponent` |
| FModel cannot read the mesh without mappings | No stand-ins | Mappings dump in M0. UEVR's dumper or UE4SS's can write one |
| Arm proportions do not match the player's real arms | Hands short of the controllers or elbows wrong | Hands always sit on the controllers; shoulders move to fit. Fit values live in the bridge config, tuned live |
| The line or float does not follow a hand-held rig | Line visibly detaches from the rod tip | M0 checks. If so, keep the rig where the game puts it and apply only hand rotation |
| UEVR's aim method does not beat the game's view steering | View or rod jitters during a fight | Overwrite control rotation after the tick in the bridge. If that fails, this piece moves to the C++ plugin |
| The feedback hook does not fire | No game-driven haptics | Read tension from the pawn each frame. Derive bite from the prompt appearing |
| The bench is out of arm's reach from the fixed camera | Cannot touch piles | Move the VR origin toward the bench on entering. The pointing fallback covers the rest |
| The game ignores the emulated gamepad | Buttons and gestures do nothing | Call the game's input functions directly. Larger change, same units |
| Gestures misfire | Anti-goal | State gating, hysteresis, the must-not-trigger traces, and Bob's tuning pass |
| Stereo with Lumen is too slow | Low frame rate | Settings guidance from M0: frame generation off, lighter lighting, upscaling on |
| A game update renames things or changes the mesh | Bridge or arms break | Names live in `gameapi` only. Re-export the stand-ins and re-cook |

## 9. Decisions

### Bob's

- Target is the Steam Frame, through UEVR.
- Version 1 is fishing and the crafting bench. The boat stays on thumbsticks.
- Reel by cranking. Fight by pulling the rod. Grab and drop at the bench.
- Scope A: real arms and hands in every mode, game rules unchanged.
- Route: content pak for everything visible, thin UEVR Lua bridge for everything else.
- The hook gun is in version 1, with its crank worked by hand. Design approved 2026-11-15.

### Mine, for Bob to check

- **D1. Cast by flick and set the hook by yank.** Bob asked for reel and fight. A button between
  physical moves would break the chain.
- **D2. Arms only, from the shoulders down.** The game's legs and shadow stay; its arms and head
  are hidden. A full VR body with leg IK is a lot more work for something rarely looked at.
- **D3. Arms use the game's own character model,** not a new hand model. It matches the game's
  look and needs no new art.
- **D4. Interrupt prompts stay on buttons in version 1.** They need facts M0 collects. The
  drag prompt is the natural next gesture, since it already asks for a pull in a direction.
- **D5. Release distance decides a bench move,** not which surface the hand is over. The game
  does not tell the bridge where "the bench" is, and distance is simple and predictable.
- **D6. Either crank direction reels.** The game cannot tell them apart.
- **D7. Right-handed rod only.**
- **D8. Built for Bob's machine first.** No installer, no settings screen.
- **D9. The project gets version control** (`git init`) before code is written, with the Unreal
  project's `Binaries`, `Intermediate`, `Saved` and `DerivedDataCache` ignored.
- **D10. Standing play, moving with the stick.** Physically walking around the room does not
  move the character. Seated play works by recentring in UEVR.
- **D11. Snap turning on by default,** for comfort. Bob can switch to smooth in the UEVR menu.
- **D12. Hands never leave the controllers.** When the player reaches past the model's arm
  length, the shoulder follows instead of the hand stopping short. A hand that lags behind the
  real one feels worse than a shoulder that drifts a little.

## 10. Left to the builder

- Exact UEVR Lua calls and their timing within the frame.
- How the pak's class is loaded and spawned (settled by M1).
- Rig attachment offsets, the reel point offset and grip socket placement.
- How units are loaded if UEVR's script loader does not support `require`.
- The config file format.
- The desk-test runner. A standalone Lua interpreter is not known to be installed. Ask Bob
  before downloading one.
- All threshold and fit values after first contact with real hand motion.

## 11. What is still unknown

Listed with how to answer each in the
[game-code answers](../../research/2026-11-15-game-code-answers.md#still-unknown-and-what-would-answer-each).
M0 closes items 1 to 6. M1 closes whether a mod pak mounts and whether Lua can load its class.

Added for the hook gun, also checked in M0:

- Which input fires `GA_HookGun`. Primary use (right trigger) is the likely one; the ability
  is granted by item tag, so the binding is not in the Blueprint.
- `DragForcePercentPerClick` and `Config.MaxMultiplier`, which set how many clicks per turn
  feel right.
- What the "twist" prompt after a hit is (`AM_DreadMoreSkeleton_Hookgun_Hit_TwistQTE`) and
  what drives it. It is a natural second crank gesture if it asks for a turn.
- Where the crank sits on the gun model, for the crank point offset.

Evidence: [GA_HookGun dump](../../research/bp-dumps/GA_HookGun.txt), lines 80–84 and 178–184.
`GA_GrapplingHookGun` and `GA_GrapplingHookGunDrag` are in a `Deprecated` folder and are not used.
