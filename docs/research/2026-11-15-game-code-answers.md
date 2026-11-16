# Dreadmoor — how the game actually works (answers from its code)

Date: 2026-11-15. Game build 26670657, Unreal Engine 5.6.1.
Companion to [2026-11-15-dreadmoor-recon.md](2026-11-15-dreadmoor-recon.md). Where the two
disagree, this file wins: it comes from reading Blueprint bytecode, the recon came from names.

## How these answers were obtained

The Blueprints were extracted from the IoStore container and their bytecode disassembled
into pseudo-code with the scripts in [tools/re](../../tools/re/README.md). The readable
dumps are in [bp-dumps](bp-dumps/). The game was never launched.

Confidence labels used below:

- **Read** — taken directly from disassembled Blueprint logic. The function is named.
- **Layout** — taken from component and construction data by pattern-matching names in
  serialized bytes, because cooked property layouts cannot be parsed without a mappings
  file. Reliable for "what is attached to what", weaker for exact values.
- **Inferred** — a conclusion drawn from the above, not seen directly.
- **Unknown** — not answered. Listed at the end with what would answer it.

Limits that apply throughout: default property values (speeds, distances, socket names
stored as defaults) were mostly not decoded, native C++ functions were not decompiled, and
nothing was observed running.

---

## The finding that shapes everything

**Each activity is a separate pawn that the game possesses.** The player controller leaves
the walking character and takes over a purpose-built actor with its own camera.

| Activity | Pawn | Camera | Player body |
|---|---|---|---|
| Walking | `BP_PlayerCharacter` (`ADrdPlayerCharacter`) | `Camera`, parented to the body mesh at bone `head` | Full body, always present |
| Fishing | `BP_FishingController` (`ADrdFishingControllerBase`), spawned at the fishing spot | `Camera` on `SpringArm` | A second body mesh, `GG_FishermanMix`, with its head bone hidden |
| Crafting | `BP_CraftController` (plain `Pawn`) | Fixed `Camera`, tilts with mouse position | None |
| Boat | `BP_SmallBoat_V2` (`ADrdShipBase`) | `FirstPersonCamera` on `FirstPersonSpringArm`, or a third-person `SpringArmComp` | Character is hidden in first-person boat view |
| Diving | `BP_DiverCharacter` | not read | not read |

Every switch follows the same shape (**Read**: `GA_FishingInteraction`, `GA_ShipTakeControl`):
blend the view to the new pawn over 0.5 s, possess it, wait for an "unpossess" gameplay
event, then possess the character again. The walking character's input is disabled meanwhile.

Consequence: a VR mod cannot treat "the player" as one object. It needs a per-pawn setup,
and the currently possessed pawn class is the reliable signal for which mode is active.

---

## 1. Player body and camera (walking)

**Is it a full body or floating arms?** Full body. **Layout**: `CharacterMesh0` uses skeletal
mesh `dm_demo_NewProtagonist` with animation blueprint `ABP_V03` from a third-party "TFPMovement"
(true first person) kit. There are no separate first-person arms.

**Where is the camera?** **Layout**: the `Camera` component is attached to `CharacterMesh0` at
`head`. The flashlight `SpotLight` is attached the same way. **Read**: `UpdateCameraZLag` and
`UpdateMainMeshZLag` re-derive position from `Mesh.GetSocketTransform('head')` every tick with
vertical smoothing, so camera position is animation-driven. Head bob, landing dips and
montages all move the view.

**What turns the view?** **Read**: `IA_Look` feeds `AddControllerYawInput` /
`AddControllerPitchInput`. The camera uses pawn control rotation, and switches it off during
dialogue and level sequences (`bUsePawnControlRotation = false`), when the game sets control
rotation itself.

**Leaning** exists as state (`LeanValue`, `LeanLeftArm`, `LeanRightArm`), replicated through
template RPCs.

**Equipping an item** (**Read**: `SlotChanged`): the item's `DrdAnimationDataTrait` is pushed
into the animation instance, and abilities are granted from the item's type tag through
`AC_GASHelper.GrantItemAbilities`. So what your hands do with a tool is an animation layer
selected by the item, plus an ability.

## 2. Tools and aiming

**Where does aim come from?** The camera, not the tool.

- **Read** `GA_Harpoon`: line trace from `PlayerController.GetPlayerViewPoint` along the view
  rotation, then spawns `BP_HarpoonProjectile` from a computed launch transform.
- **Read** `GA_Knife`: sphere trace (radius 75) along the controller's control rotation.
- **Read** `GA_HarpoonAim`: just calls `SetAiming(true/false)` on the character.

**Carried objects** (canisters, buckets, quest parts — `BP_HandToolActor_Base`): **Read**
`RootMesh.K2_AttachToComponent(<character mesh>, AttachSocketName, snap, snap, keep-scale)`,
then a take or release montage. The socket name is a default value and was not decoded.

## 3. Fishing

### Starting

**Read** `GA_FishingInteraction`: spawns a fishing controller at the spot, attaches it to the
floor (so it rides the boat), blends the view, possesses it. `IMC_Fishing` is added at
priority 1. On exit it waits for `GAS.Event.Unpossess` and returns to the character.

### The rig

**Layout**: `RotateScene` is the parent of the fisherman body `GG_FishermanMix`, the rod
`SK_FishingRod`, plus `Reel`, `Thread`, `Line`, `Lure`, `Forceps`. Reel and thread follow the
rod's pose (`SetLeaderPoseComponent`). **Read** `SetupCharacterMesh`: the fisherman mesh is
swapped to match the player's mesh, and its `head` bone is hidden.

**The rod points where you look.** **Read** `RotateMesh`: every tick `RotateScene` is set to
the control rotation's yaw, with pitch clamped to −30..0 degrees. There is no independent rod
aim anywhere in the game.

**The game steers your view during a fight.** **Read** `RotateControl`: while a fish is hooked,
control rotation is interpolated (speed 2) toward the fish's `Line_Socket`, offset 17.5 degrees
of yaw to one side depending on fish direction. `UpdateViewClamp` also narrows the camera
manager's yaw and pitch limits around the fishing direction.

### Cast

**Read** fishing controller plus `STT_Fishing_MoveAimTarget`:

1. Press `IA_Fishing_Cast` → state-tree event `StateTree.Event.Started`. A power widget appears.
2. While held, the landing marker sits at
   `pawn location + look direction × lerp(min, max, PowerWidget.GetPower())`.
3. Release → `StateTree.Event.Completed`, and the float is thrown to the marker.

So direction is the look direction and distance is a charge value owned by a UI widget.

### Bite

**Read** `WBP_QTE_FishingBite`: a widget that listens for an `IA_Fishing_Cast` press.

### Fight and reel

**Reeling is holding the cast button.** **Read**: `IA_Fishing_Cast` sets `bMousePressed`, and
`MoveFish` uses that flag as "reeling". `IA_Fishing_Ability_Reel` is something else: it
activates `GA_Fishing_ForcePulling`, a cooldown skill that yanks the fish closer
(`AddBonusMove`).

**The fight input is effectively three positions.** **Read** `UpdateStruggleX`:
`IA_Fishing_Fight` is polled as a 1-D axis every tick. Below 0.5 in magnitude it counts as
centre. Otherwise `StruggleX` eases toward a left or right limit. `GetPlayerDirection` then
reduces it to 0, 1 or 2. Analogue precision past the 0.5 threshold is thrown away.

**The rule is "match the fish's side".** **Read** `IsSameDirection`: true when the player's
direction equals `FishDirection`. From `MoveFish`:

- Matching side **and** reeling drains the fish's stamina, faster the further `StruggleX` is
  from centre.
- Reeling while the fish still has stamina raises line tension. At `Config.MaxTension` the line
  snaps (`TrySnapLine`).
- Not reeling and not matching lets the fish run. At maximum distance that also raises tension.
- At zero stamina the fish is exhausted. Reeling then pulls it in without adding tension. It
  recovers after a while.
- Close enough → state-tree event `Succeeded`, on to landing.
- `IA_Fishing_Drag` toggles a drag mode that halves tension gain and cuts pull speed to a third.
- Rod upgrades scale tension, stamina drain and pull speed through `DrdAttributeSetFishingRod`.

Whether "matching" looks like pulling with the fish or against it on screen is not decided by
this code. See Unknown 4.

### Interrupt events during the fight

**Read** `CheckEvents`, `StartEvent`, `QTEFinished`. Each is a widget pushed to UI layer
`UI.Layer.QTE` that owns its own input and reports `QTE.Result.Success` or `.Failure`:

| QTE | What the player does | Input |
|---|---|---|
| `WBP_QTE_DirectionalDrag` | Hold and drag along a randomly rotated direction until a bar fills | `IA_QTE_LMB` held + `IA_QTE_Look` |
| `WBP_QTE_Reel` | Press when a spinning handle passes a marked sector | `IA_QTE_Interact` |
| `WBP_QTE_FishLand` | Timed press | `IA_QTE_Interact` |
| `WBP_QTE_FishClicker` | not read in detail | — |

A successful directional drag removes a chunk of stamina and can exhaust the fish outright.

### How the rod and arms move

**Read** `ABP_SimpleRod_Fishing`, `ABP_Main_Hero_Fishing`: both animation blueprints pull
`State`, `Left_Right`, `Reel`, `SameDirection` from the fishing controller every frame. The
body adds a left-hand IK effector and a tremor. Rod bend and arm pose are blends driven by
those values. Nothing tracks a free-moving rod.

### Fishing settings

**Read** `WBP_FishingStruggle`: "Immersive Fishing", "Guided Fishing", "Fish Struggle
Indicators" and "Fish Distance" only show or hide HUD panels. **Read** `IsKeyboardSetting`:
"Keyboard Fishing" switches the fight input to two keys.

### Haptics

**Read** `UpdateFishingControllerFeedback`: while a fish is on, every tick calls
`DrdControllerFeedbackLibrary.PlayControllerFeedback(PlayerController, 8, tension %)` and
`UpdateControllerTriggerResistance(PlayerController, 8, tension %)`. Event 8 lines up with
`FishingTension` in the recon's enum order (**Inferred**). These are static library
functions with the strength passed in, so tension is available as a number every frame.

## 4. Crafting bench

**It is a mouse-cursor screen built in 3-D.** `BP_CraftController` is a pawn with a fixed
camera and one child actor per material pile.

- **Read** `TraceForPile`: each tick, `DeprojectMousePositionToWorld` → `SphereTraceMulti` →
  nearest `DrdCraftPile` becomes `HoveredPile`, with `SetIsHovered(true)` and a HUD hint.
- **Read** ubergraph: `IA_Crafting_Click` calls `HoveredPile.ClickPile()`.
- **Read** `PileClicked` → `TryMoveItem(ItemType, bIngredient, 1)`: moves **one unit** between
  two inventories, the player's and the table's. Clicking a shelf pile puts one on the table.
  Clicking the table pile sends one back. There is a cap, `MaxSelectedItems`.
- `IA_Crafting_Start` crafts. **Inferred** from three bound events and a `CancelCraftHold`
  function: it is a hold that cancels on release.
- **Read** `CameraTilt`: the camera leans a little toward the mouse position.

So "pick up and put down" in the game is click-to-transfer of one unit. There is no drag and
no held item. `HoveredPile` is an ordinary Blueprint variable, and `ClickPile` and
`SetIsHovered` are callable functions.

## 5. Boat

**Read** `GA_ShipTakeControl`: the character is moved to a stored transform, attached to the
boat, has input disabled, and is **hidden** when first-person boat view is on. The view blends
to the boat and the controller possesses it. Release is `GAS.Event.RidingShip.End`.

**Layout**: `FirstPersonCamera` sits on `FirstPersonSpringArm`. A separate third-person
`SpringArmComp` exists and `IA_BoatSwitchCamera` toggles them. The wheel is a child actor,
`BP_ShipSteeringWheel`, with its own animation blueprint. A setting "Auto Rotate Camera On
Ship" is read by the boat.

So in first-person boat view there are no player hands on the wheel at all, because the
character is hidden.

## 6. Button mappings

From `tools/re/imc.py`, a byte-pattern pairing of actions and keys. **Partial**: it misses
keys in small assets, so absence of a gamepad key here does not mean there is none.

**On foot** (`IMC_CharacterMapping`)

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / Look | WASD / mouse | left stick / right stick |
| Primary use | left mouse | right trigger |
| Secondary use | right mouse | left trigger |
| Interact | — | face left (X) |
| Jump | space | face bottom (A) |
| Reload | R | face top (Y) |
| Sprint | left shift | left stick click |
| Flashlight | L | right stick click |
| Inventory | I | view / back |
| Map | M | left bumper |
| Pin | V | right bumper |
| Item slots (likely: the action names did not resolve) | 1 2 3 | d-pad |

**Fishing** (`IMC_Fishing`)

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Cast, and reel while held | left mouse | right trigger |
| Recast | right mouse | left trigger |
| Fight axis | mouse X | left stick X or right stick X |
| Look | mouse | either stick |
| Gear | R | — |
| Reel skill | 1 | — |
| Pause | — | menu |

**Fishing review** (`IMC_FishingReview`): auto-sort F, move to hold G, release fish Z, plus
face buttons.

**Boat** (`IMC_Boat`): move W/S, look mouse, afterburner left shift or right trigger, klaxon
left mouse, lights right mouse, docker X, fish scan Y, zoom wheel.

**Crafting** (`IMC_CharacterCrafting`): click is left mouse or a face button, start is a face
button.

**Developer keys present in the shipped build** (`IMC_Globals`): quick scalability presets on
2 and 3, switch UI on U, teleport to ship on T. Whether they are active in retail is not known.

## 7. Single-player

**Inferred**: yes. Game code addresses the player as `GetPlayerController(self, 0)`
everywhere. The server and multicast functions on the character come from the third-party
movement kit, not from Dreadmoor's own design.

---

## What these facts mean for a VR mod

These follow directly from the code. They are consequences, not design decisions.

1. **Mode switching is the backbone.** Four pawns, four cameras. The mod needs per-pawn camera
   and hand handling, keyed on the possessed pawn's class.
2. **Walking will bob.** The camera rides the head bone. The view must be decoupled from head
   animation or it will move without the player moving.
3. **A hand-held rod needs three overrides,** because today the rod follows the look direction:
   detach the rod rig (`RotateScene`) from control rotation and drive it from the right
   controller, stop `RotateControl` steering the view toward the fish, and hide or replace
   the fisherman body's arms since they animate from state rather than from the rod.
4. **Physical reeling maps to one flag.** Reeling is "is the cast action held". A crank
   gesture has to translate into holding `IA_Fishing_Cast`, on or off. Crank speed has no
   meaning to the game today.
5. **Fighting maps to three positions.** Rod lean past a threshold becomes left, right or
   centre. Finer control would be invisible to the game.
6. **Cast direction and power are both overridable but live in different places:** direction
   is control rotation, power is a UI widget's value.
7. **Bite, land and reel-timing prompts are button presses inside widgets.** A gesture can
   stand in for the press. The directional-drag prompt wants a direction, which a physical
   pull naturally supplies.
8. **The crafting bench is close to what was asked for.** Replacing the mouse ray with hand
   proximity to set `HoveredPile`, and calling `ClickPile` on grab or release, reuses the game's
   own logic. Each grab moves exactly one unit.
9. **Boat first-person has no body,** so any hands there are the mod's own.
10. **Tool aim follows the camera,** so aiming a harpoon with the hand means overriding the
    view point or control rotation, which is what UEVR's aim method does.
11. **Tension haptics are free.** The game already emits a 0..1 tension value every frame.
12. **Arms that follow the player can be built at runtime, with no content pak.** The engine's
    `UPoseableMeshComponent` is compiled into the game, with `SetBoneTransformByName`,
    `SetBoneRotationByName`, `GetBoneTransformByName`, `CopyPoseFromSkeletalComponent` and
    `ResetBoneTransformByName` all reflected. So are `AddComponentByClass`,
    `SetSkinnedAssetAndUpdate`, `HideBoneByName` and `SetOverridePostProcessAnimBP`. A script
    or plugin can therefore add a second copy of the game's own character mesh, hide everything
    but the arms, and pose the arm and finger bones each frame from the controllers.
    **Observed** in the binary's reflection names. Not tested in the running game.

## Corrections to earlier notes

- Earlier I mapped the crank gesture to `IA_Fishing_Ability_Reel`. That is wrong. That action
  is a cooldown skill. Reeling is holding `IA_Fishing_Cast`.
- Earlier I described the fight as an analogue axis "from how far you lean the rod". The game
  quantises it to left, centre, right at a 0.5 threshold.
- Earlier I described fighting as hauling opposite to the fish. The code only requires matching
  `FishDirection`. Which way that reads on screen is Unknown 4.
- The recon guessed an "ALS-style" body. It is the TFPMovement kit, full body, camera on the
  head bone. ALS assets exist in the build but the player does not use them.
- "Immersive Fishing" is a HUD toggle, nothing more.

## Still unknown, and what would answer each

1. **Does UEVR run on this 5.6.1 build?** Inject the UEVR nightly already in `Downloads\UEVR`
   and look. Nothing static can answer this.
2. **How the on-foot interaction picks its target.** `UDrdPlayerInteractionComponent` is
   native. It has a `SearchSphere`, `TraceSphereRadius` and `TraceInterval`, which suggests an
   overlap sphere plus a periodic trace, probably from the camera. Decompile it, or watch
   `CurrentInteractableTarget` at runtime while moving the head and hands separately.
3. **Default values:** cast distance range, tension rates, struggle limits, carry socket names,
   the power widget's behaviour. A runtime object dump (UEVR's object explorer, or UE4SS)
   gives these directly, and also yields the mappings file that would let the scripts here
   decode defaults offline.
4. **Fight direction as seen by the player.** Whether `FishDirection` means "fish is going
   left" or "pull left". Play one fight and watch the indicator against the fish.
5. **Exact gamepad mappings** where the table above has gaps. Same runtime dump.
6. **Whether the game's Steam Input bridge (`DrdSteamInputBridge`) and Sony input plugin
   interfere with UEVR's emulated gamepad.** Runtime test.
7. **Diving** (`BP_DiverCharacter`, `IMC_Diving`) was dumped but not read.
8. **The generator, water pump and lockpicking QTEs** were dumped but not read. Their widgets
   follow the same pattern as the fishing ones.
9. **Stereo performance** with Lumen. Runtime only.
