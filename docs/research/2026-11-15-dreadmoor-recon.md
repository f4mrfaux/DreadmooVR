# Dreadmoor VR mod — reconnaissance findings

Date: 2026-11-15
Status: research notes feeding the design spec. Nothing here is a decision.

> Superseded in part. The "Inferred" and "Unknown" sections below were written from names
> alone. [2026-11-15-game-code-answers.md](2026-11-15-game-code-answers.md) answers most of
> them from the Blueprint bytecode, and corrects the guess about the player's body rig.

## Target

| | |
|---|---|
| Game | DREADMOOR, Steam app 3629430, build 26670657 |
| Install | `D:\SteamLibrary\steamapps\common\DREADMOOR` |
| Main binary | `Dreadmoor\Binaries\Win64\Dreadmoor-Win64-Shipping.exe`, 191,527,936 bytes |
| SHA-256 | `246e7ba61b7b1e00451f32cc94b3f3b66c8128697ef4b400d9e836e3fe696c36` |

## Method and its limits

Static inspection only. The game was never launched, attached to, or modified.

- REA target-free PE parsers: imports (`ev_304db7bc…1eabe5`), resources (`ev_7221ffe0…398515`).
- Direct string sweep of the executable (595,710 ASCII and 106,053 UTF-16 strings, minimum length 5).
- IoStore `.utoc` and `.pak` header reads, plus the unencrypted directory index.
- No disassembly or decompilation. A Ghidra pass on a 191 MB monolithic binary was judged
  not worth hours when reflection strings answer the questions at hand.

Consequence: every claim about *behaviour* below is an inference from names. Function
addresses, call order, and what the Blueprints actually do are unobserved.

## Observed

### Engine and platform

- **Unreal Engine 5.6.1** — PE version resource `FileVersion 5.6.1.0`.
- Monolithic shipping build (one exe, no engine DLLs). PDB name is embedded, PDB is not shipped.
- Renderer: D3D12 and D3D11 delay-loaded. Lumen hardware ray tracing, Nanite, TSR, DLSS,
  FSR3 (with frame interpolation), XeSS (with frame generation) all compiled in.
- Input: `XINPUT1_4.dll` delay-loaded, `HID.DLL` imported, Steam API, plus a studio plugin
  `DrdSonyInput` (`DrdSonyInputDevice.cpp`, `DrdSteamInputBridge.cpp`).
- No anti-cheat or protector markers: zero hits for EasyAntiCheat, BattlEye, Denuvo,
  VMProtect, Themida, XignCode.
- Crash reporting through Sentry, telemetry through GameAnalytics.

### VR support in the shipped build

- **No VR runtime plugin is compiled in.** Zero hits for `openxr_loader`, `OpenXRHMD`,
  `xrCreateInstance`, `XR_KHR_`, `SteamVR`, `openvr_api`, `OculusHMD`, `OculusXR`, `LibOVR`.
- The engine's generic XR layer *is* present: `/Script/HeadMountedDisplay`,
  `UMotionControllerComponent`, `XRMotionControllerData`, `vr.InstancedStereo`,
  `vr.MobileMultiView`, `vr.HiddenAreaMask`, `xr.VRS.*` foveation cvars, `emulatestereo`,
  `bStartInVR`, and the fake-stereo device settings.

### Content containers

- `Dreadmoor-Windows.utoc`: IoStore version 8, flags `Compressed | Indexed`.
  **Not encrypted, not signed.** Encryption key GUID is all zeros.
- `Dreadmoor-Windows.pak`: version 11, index not encrypted.
- 17,665 `.uasset` and 3,479 `.umap` names readable from the directory index.

### Game code layout

Native module `/Script/Dreadmoor` is thin: 37 source files, classes prefixed `Drd`.
Embedded source paths root at `G:\Work\UnrealProjects\DREADMOOR\`.

Third-party gameplay frameworks compiled in:

| Plugin | Role |
|---|---|
| ALS / IWALS (`IWALS_AbilitySystem`, `HelpfulFunctions`, `ClimbingNavigation`, `JakubCableComponent`) | Character locomotion and interaction framework, full-body animation |
| InventoryFrameworkPlugin (`IFP_ItemQuery`, `IFP_GAS`, `IFP_Crafting`) | Inventory and items |
| GameplayAbilities | Every tool use and interaction is an ability |
| EnhancedInput, CommonUI, CommonInput, CommonGame | Input and UI stack |
| DWP2 (`ShipController`, `ShipEngineComponent`, `WaterObjectComponent`) | Boat physics and buoyancy |
| Narrative, NarrativeNavigator | Quests, dialogue, markers |

Key native classes:

- Player: `ADrdPlayerCharacter`, `ADrdBaseCharacter`, `ADrdDiverCharacter`,
  `ADrdPlayerController`, `UDrdCharacterMovementComponent`.
- Interaction: `UDrdPlayerInteractionComponent` (`SearchRange`, `TraceInterval`,
  `TraceSphereRadius`, `SearchSphere`, `InteractablesInRange`, `CurrentInteractableTarget`,
  `GetCurrentInteractable`, `GetIsAnyInteractionActive`), `UDrdInteractableComponent`
  (`InteractHoldTime`, `OnTryToStartInteraction`, `OnTryToStopInteraction`,
  `OnInteractionAbilityChanged`, `LoadedAbility`), `UDrdProxyInteractionComponent`,
  `UDrdPickable`, `UDrdHookInterface` (`TryInteractWithHook`, `TryDragWithHook`).
- Fishing: `ADrdFishingControllerBase`, `ADrdFishingAimTarget`, `ADrdStrugglingFish`,
  `UDrdFishingSubsystem`, `UDrdAttributeSetFishingRod`,
  `EDrdStruggleDirection {Center, Left, Right}`.
- Quick-time events: `UDrdQteSubsystem`, `UDrdQteController` (`StartQTE`, `ForceFinishQTE`,
  `QteTypeTag`, `OnQteFinished`, `OnQteEventTriggered`, `OnQteValueChanged`).
- Ship: `ADrdShipBase` is its own possessable pawn (`OnPossessChanged`,
  `FirstPersonCameraSpringArm`, `SpringArmComponent`, `SwitchCameraAction`, `DockerAction`,
  `AfterburnerAction`), `UDrdShipFloatingMovementComponent`, `UDrdShipDockingComponent`.
- Haptics: `UDrdControllerFeedbackSubsystem` (`PlayControllerFeedback`,
  `PlayControllerFeedbackFromMagnitude`, `UpdateControllerContinuousFeedback`,
  `StopControllerFeedback`) driven by
  `EDrdControllerFeedbackEvent {AxeImpact, PlayerDamage, ShipCollision, CharacterCollision,
  FishingCatch, WeaponFire, FishingCast, FishingBite, FishingTension, ShipDamage, ShipBoost,
  GeneratorPull}`.
- Ability input: `EDrdAbilityInputID {None, Confirm, Cancel, Sprint, FireAbility,
  FireAbilityCommit, ShipAfterburner, ShipDocker, ShipInteract}`.
- `UDrdHeadTrackingComponent` is a character look-at behaviour (angles, turn strength, look
  cooldowns). It is not hardware head tracking.

### Input surface (asset names)

31 mapping contexts, which read as the game's list of modes:

`IMC_CharacterMapping`, `IMC_Boat`, `IMC_Fishing`, `IMC_FishingReview`, `IMC_Diving`,
`IMC_Towing`, `IMC_Bilge`, `IMC_Radio`, `IMC_SafeInputMapping`, `IMC_RemoteController`,
`IMC_ShipLoader`, `IMC_ShipUpdgradesTable`, `IMC_CharacterCrafting`, `IMC_Inventory`,
`IMC_Journal`, `IMC_Mastery`, `IMC_Trade`, `IMC_QTE`, `IMC_QTE_Drag`, `IMC_QTE_Drag_UI`,
`IMC_QTE_Gererator`, `IMC_QTE_Lockpicking`, `IMC_QTE_WaterPump`, and UI contexts.

143 input actions. The physically suggestive ones:

- Fishing: `IA_Fishing_Cast`, `IA_Fishing_Ability_Reel`, `IA_Fishing_Fight`, `IA_Fishing_Drag`,
  `IA_Fishing_Recast`, `IA_Fishing_ReleaseFish`, `IA_Fishing_MoveFishToHold`, `IA_Fishing_Gear`.
- Tools: `IA_PrimaryUse`, `IA_SecondaryUse`, `IA_Aiming`, `IA_Reload`, `IA_Hook`, `IA_HookGun`,
  `IA_Heal`, `IA_RemoveBarnacles`, `IA_CharLight`, `IA_Slot_1..4`.
- QTE: `IA_QTE_Axis`, `IA_QTE_GamepadPull`, `IA_QTE_Interact`, `IA_QTE_PrimaryUse`, `IA_QTE_Look`.
- Boat: `IA_BoatMove`, `IA_BoatAfterrburner`, `IA_Klaxon`, `IA_BoatLights`, `IA_Bilge`,
  `IA_Docker`, `IA_BoatFishing`, `IA_BoatSwitchCamera`.
- Dials: `IA_RadioFrequencyAdjustment`, `IA_RadioPowerAdjustment`, `IA_SafeDrag`.
- Body: `IA_LeanLeft`, `IA_LeanRight`, `IA_Crouch`, `IA_SwimUp`.
- Developer: `IA_Dev_CheatPanel`, `IA_Dev_TeleportToShip`, `IA_Dev_TimeDilation`.

121 gameplay abilities, including `GA_Knife`, `GA_Sickle_Attack`, `GA_Sickle_Block`,
`GA_Harpoon`, `GA_HarpoonAim`, `GA_HookGun`, `GA_GrapplingHookGun`, `GA_GrapplingHookGunDrag`,
`GA_RepairTool`, `GA_HandTool_Carry`, `GA_HandTool_Pickup`, `GA_UseFirstAid`, `GA_Reload`,
`GA_BarnacleWasher`, `GA_Fishing_ForcePulling`, `GA_Fishing_TensionRestoring`,
`GA_ShipTakeControl`, `GA_ShipReleaseControl`, `GA_DoorInteract`, `GA_DrawerInteraction`.

Relevant Blueprints: `BP_PlayerCharacter`, `BP_DrdPlayerController`, `BP_PlayerCameraManager`,
`BP_DiverCharacter`, `BP_SmallBoat_V2`, `BP_PaddleBoat`, `BP_ShipSteeringWheel`,
`BP_HandToolActor_Base`, `BP_HandObjectsVisibilityComponent`, `BP_FishingRodWithReel`,
`BP_FishingController`, `BP_HarpoonEquipment`, `BP_HookGunEquipment`, `BP_Sickle_Equipment`,
`BP_RepairTool`, `BP_Radio`, and QTEs `BP_QTE_Reel`, `BP_QTE_RunGenerator`,
`BP_QTE_WaterPump`, `BP_QTE_Lockpicking`, `BP_QTE_DirectionalDrag`, `BP_QTE_QuickTap`,
`BP_QTE_FishingBite`, `BP_QTE_FishLand`.

Animation: `ABP_Main_Hero_Fishing`, `ABP_SimpleRod_Fishing`, `ABP_Character_GeneratorQTE`,
`ABP_SK_DreadMore_Steering`, and linked layers `ABP_LayerHarpoon`, `ABP_LayerHookGun`,
`ABP_LayerKnife`, `ABP_LayerMedicKit`, `ABP_RepairToolLayer`, `ABP_HandlingModuleLayer`.
ALS assets present: `ALS_Mannequin_Skeleton`, `ALS_OverlayState`, `ALS_ViewMode`.
Skeleton bone names `hand_l`, `hand_r` present.

### Engine functions available by name

Reflected and therefore callable through `ProcessEvent`: `InjectInputVectorForAction`,
`InjectInputForPlayerMapping`, `InjectInputVectorForPlayerMapping`, `AddMappingContext`,
`RemoveMappingContext`, `HasMappingContext`, `PlayDynamicForceFeedback`, `PlayHapticEffect`,
`SetHapticsByValue`, `K2_AttachToComponent`, `K2_SetWorldTransform`, `GetSocketTransform`,
`TryActivateAbilityByClass`, `AbilityLocalInputPressed`, `SendGameplayEventToActor`,
`SetViewTargetWithBlend`, `EnableCheats`.

## Inferred

- Gameplay logic lives mostly in Blueprint. Basis: 994 `BP_` assets against 37 native files.
- The player is a full-body ALS-style character whose hands are animation-driven and whose
  tools attach to hand bones through linked anim layers. Basis: asset names only. Which mesh
  the first-person view actually shows is not confirmed.
- UEVR can attach, because the stereo and motion-controller interfaces it hooks are present
  and nothing blocks injection. Not tested.
- Gestures can drive Enhanced Input actions directly instead of spoofing gamepad buttons.
  Basis: the inject functions are reflected. Not tested.
- Game haptic events can be redirected per hand by hooking `PlayControllerFeedback`.
  Basis: it is a reflected function on a subsystem. Not tested.

## Unknown

1. **Whether UEVR works on this build at all.** Official docs say UE 4.8–5.4. Third-party
   guides and uevr.io say nightly builds carry 5.5 and 5.6 fixes. Nobody appears to have
   published a Dreadmoor profile.
2. How the first-person body is rigged: full body, separate arms, or camera-attached.
3. Tool attachment sockets and whether aim comes from the camera or the tool.
4. Whether `DrdSteamInputBridge` interferes with UEVR's emulated XInput pad.
5. Stereo performance with Lumen at headset refresh rates.
6. How the camera behaves during ship possession, cutscenes (`LevelSequence`), and QTEs.
7. Whether the game is strictly single-player. Networking modules are compiled in, which
   proves nothing either way.

## Tooling facts

### UEVR

Source: [UEVR documentation](https://docs.uevr.io/print.html),
[UEVR nightly releases](https://github.com/praydog/UEVR-nightly/releases),
[vr.org guide](https://vr.org/uevr), [uevr.io](https://uevr.io/).

- Stable 1.05 dates from November 2024. Documented range UE 4.8–5.4, D3D11 and D3D12.
- Rendering modes: Native Stereo (preferred), Synchronized Sequential (fallback, TAA
  ghosting), AFR (last resort).
- Frame generation must be off.
- Controllers are presented to the game as an XInput gamepad.
- Plugin callbacks include `on_pre_engine_tick`, `on_post_engine_tick`,
  `on_xinput_get_state`, `on_xinput_set_state`, `on_pre_calculate_stereo_view_offset`,
  `on_post_calculate_stereo_view_offset`, `on_pre_viewport_client_draw`. Lua mirrors these
  under `uevr.sdk.callbacks`.
- VR API: `get_pose`, `get_grip_pose`, `get_aim_pose`, `get_action_handle`,
  `is_action_active`, `get_joystick_axis`, `trigger_haptic_vibration`, `set_aim_method`,
  `set_snap_turn_enabled`, `recenter_view`, `set_mod_value`.
- UObjectHook attaches any scene component to a hand or the HMD with a location and
  rotation offset, optionally permanent. Every `UMotionControllerComponent` follows the real
  controllers once UObjectHook is active.
- UFunctions can be called (`obj:FuncName(...)`) and hooked (`fn:hook_ptr(pre, post)`, where
  `pre` returning false skips the original).
- Files: `%APPDATA%\UnrealVRMod\<exe name>\` holding `config.txt`, `plugins\*.dll`,
  `scripts\*.lua`.

### Steam Frame

Source: [Steam Frame Input, Steamworks](https://partner.steamgames.com/doc/steamhardware/steamframe/input),
[UploadVR announcement coverage](https://www.uploadvr.com/valve-steam-frame-official-announcement-features-details/),
[vr.org spec sheet](https://vr.org/steam-frame-specs).

- Controllers carry a full gamepad split across two hands. Left: d-pad, view, bumper,
  trigger, grip, thumbstick. Right: A B X Y, menu, bumper, trigger, grip, thumbstick.
- Touch states on every input, capacitive finger tracking exposed through the SteamVR
  Skeletal Input API, 6-DOF tracking, haptic output per hand.
- OpenXR: extension `XR_VALVE_frame_controller_interaction`, profile
  `/interaction_profiles/valve/frame_controller_valve`.
- OpenVR controller type `frame_controller`. SteamVR falls back to a generic OpenXR binding,
  then an Oculus Touch binding, remapped onto the Frame layout.
- No controller-free hand tracking.
- Eye tracking through `XR_EXT_eye_gaze_interaction`.

## Working files

String dumps and helper scripts are in the session scratchpad, which is temporary. To
regenerate: dump printable strings of length 5 or more from the executable and from
`Dreadmoor-Windows.utoc`, then search for the names above.
