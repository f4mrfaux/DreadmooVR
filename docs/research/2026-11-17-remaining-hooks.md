# Remaining game hooks for the VR mod (scraped 2026-11-17)

Static read of the game's Blueprint bytecode and assets (Steam build 26670657) with `tools/re`.
Held tools are in [2026-11-17-held-items.md](2026-11-17-held-items.md). Earlier answers are in
[2026-11-15-game-code-answers.md](2026-11-15-game-code-answers.md) and the
[recon](2026-11-15-dreadmoor-recon.md). Names below are exact, as reflection sees them.

## 1. What bends the torso when you look down

- The character's animation Blueprint is `ABP_V03` (TFPMovement kit, on `CharacterMesh0`).
  - Every update it stores `self.ControlRotaton = OwningController.GetControlRotation()`
    (`ABP_V03` L0356; the misspelling is the game's).
  - It also derives `ControlRotationVelocity` and `YawVelocityPerSec` from that.
- Its anim graph runs two Control Rigs:
  - **`CR_AimingRotation`** has inputs `Pitch` and `Yaw`. It builds a quaternion from Euler
    angles, scales by a constant, and calls `SetRotation` on **`spine_05`**. That is the torso
    bend.
  - **`CR_HandRoationAndSpine_05`** has input `Pitch`. It sets several rotations on the hand and
    spine chain.
- The binding from `ABP_V03` to the rigs' `Pitch` pins is anim-graph constant data that
  `tools/re` does not decode. The likely source is `ControlRotaton.Pitch`. **Unverified.** To
  confirm, read `pawn.Mesh:GetAnimInstance().ControlRotaton` at runtime while pitching the head.
- **What follows:**
  - Control rotation pitch bends `spine_05`, so the clavicles, arms and head-mounted camera move
    with it.
  - With UEVR `aim_method = 2`, control rotation follows the right hand, so the torso will bend
    with hand pitch instead of head pitch.
  - The robust fix is in `ABP_VRArms`: after copying the pose, counter-rotate `spine_05` by the
    same pitch. The arms then hang from an upright chest. Alternatively anchor the shoulders under
    the HMD (FRIK style). Either way the rig is the thing to undo.

## 2. Melee: knife and sickle

- **`GA_Sickle_Attack`:**
  - Starts on the item's primary attack and chains combos with
    `AbilityTask_WaitInputPress` / `WaitInputRelease`.
  - Plays an attack montage on the player mesh.
  - On the montage's notify (`OnNotifyBegin` → `GetHitActors`, L0BDF) it runs
    `SphereTraceMultiForObjects` with **radius 75**.
  - The sphere runs from `AvatarActor.K2_GetActorLocation() + (0,0,50)`, along
    `GetPlayerController(0).GetControlRotation()` forward, between two constant distances.
  - Hits need a `DrdActorTagComponent` with tag `GameEntities.Enemy.CanBeDamaged`.
  - Damage goes through `BPFL_GasFunctions.DrdApplyDamage(... GE_HarpoonDamage ...)`.
- **`GA_Knife`:** the same pattern. A radius-75 sphere along control rotation, damage 10,
  montages `dm_demo_protagonist_Axe_SwingLeft_Montage` / `_SwingRight_Montage`.
- **What follows:** hits come from the body and control rotation, not from the blade. A VR
  swing gesture only needs to press primary use at the swing; with aim on the right hand it hits
  where the hand points. The blade's real path does not matter to the game.

## 3. Which input fires item abilities

- The items `IDA_HookGun` and `IDA_Sickle` carry `IT_PrimaryAttack` → `IC_PrimaryAttack`, which
  calls `IC_ItemAbility.AbilityActivated`.
- `BP_PlayerCharacter` handles `IA_PrimaryUse` in Blueprint only to run
  `TraceDestructibleObjectForNotification()` (L0381). It clears GAS input ID 3 elsewhere
  (`ClearAllAbilitiesWithInputID(3)`, L0005 of the function at line 1481).
- So item abilities are bound to input IDs natively. Pressing primary use (right trigger on the
  virtual pad) is the seam, as the gesture design assumed.

## 4. Already known (recon), still runtime-only

| Need | Name | What a runtime read gives |
|---|---|---|
| Interaction targeting | `UDrdPlayerInteractionComponent`: `SearchRange`, `TraceInterval`, `TraceSphereRadius`, `SearchSphere`, `InteractablesInRange`, `CurrentInteractableTarget` | Whether the trace starts at the camera; watch `CurrentInteractableTarget` while moving the head and hands apart |
| Haptics | `DrdControllerFeedbackLibrary.PlayControllerFeedback(PlayerController, EDrdControllerFeedbackEvent, strength)` (called with event 8 = tension); subsystem `UDrdControllerFeedbackSubsystem` | Hook it to route events per hand |
| Hook gun tuning | `DA_GD_HookGun` (`DragForcePercentPerClick`, `Config.MaxMultiplier`) | Default values, which `tools/re` does not decode |
| Torso bend source | `ABP_V03.ControlRotaton` | Confirms section 1 |

## Not needed

`GA_GrapplingHookGun` and `GA_GrapplingHookGunDrag` are in `Deprecated` and unused. There is no
axe item: the "axe" montages belong to the knife.
