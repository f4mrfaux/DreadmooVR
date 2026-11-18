# Validated engine calls

**Rule (Bob, 2026-11-16):** use only canonical, validated function calls. Every engine function
the plugin or the Lua scripts call is checked against the **UE 5.6 engine headers**
(`C:\Program Files\Epic Games\UE_5.6\Engine\Source\Runtime\Engine\Classes\`), the same
engine version the game ships (5.6.1). Each check confirms:
- the reflected name, which is the C++ function name and **not** the Blueprint display name
  or ScriptName
- `UFUNCTION` exposure, since only reflected functions can be reached through Lua or
  `process_event`
- parameter order
- enum values

Add a row here before using a new call.

| Call | Header:line | UFUNCTION | Signature / values used |
|---|---|---|---|
| `AActor::GetTransform` | GameFramework/Actor.h:1545 | BlueprintCallable (display "Get Actor Transform") | `const FTransform& GetTransform() const`. **Not** `K2_GetActorTransform`, which doesn't exist; that bug was found in game on 2026-11-16 |
| `AActor::K2_GetActorLocation` | Actor.h:1558 | BlueprintCallable | `FVector K2_GetActorLocation() const` |
| `AActor::K2_GetActorRotation` | Actor.h:1579 | BlueprintCallable | `FRotator K2_GetActorRotation() const` |
| `AActor::K2_GetComponentsByClass` | Actor.h:3762 | BlueprintCallable (`ScriptName=GetComponentsByClass`) | `TArray<UActorComponent*> K2_GetComponentsByClass(TSubclassOf<UActorComponent>) const`; used as a fallback to find the hook gun's generated `Hook` mesh component |
| `AActor::K2_TeleportTo` | Actor.h:3327 | BlueprintCallable | `bool K2_TeleportTo(FVector DestLocation, FRotator DestRotation)` |
| `AController::GetControlRotation` | GameFramework/Controller.h:159 | BlueprintCallable | `virtual FRotator GetControlRotation() const` |
| `UGameplayStatics::BeginDeferredActorSpawnFromClass` | Kismet/GameplayStatics.h:67 | BlueprintCallable, BlueprintInternalUseOnly | `(WorldContextObject, ActorClass, const FTransform& SpawnTransform, ESpawnActorCollisionHandlingMethod CollisionHandlingOverride, AActor* Owner = nullptr, ESpawnActorScaleMethod TransformScaleMethod = MultiplyWithRoot)` |
| `UGameplayStatics::FinishSpawningActor` | GameplayStatics.h:71 | BlueprintCallable, BlueprintInternalUseOnly | `(AActor* Actor, const FTransform& SpawnTransform, ESpawnActorScaleMethod TransformScaleMethod = MultiplyWithRoot)` |
| `UKismetSystemLibrary::MakeSoftObjectPath` | Kismet/KismetSystemLibrary.h:336 | yes | `FSoftObjectPath MakeSoftObjectPath(const FString& PathString)` |
| `UKismetSystemLibrary::Conv_SoftObjPathToSoftObjRef` | KismetSystemLibrary.h:344 | yes | `TSoftObjectPtr<UObject> Conv_SoftObjPathToSoftObjRef(const FSoftObjectPath&)` |
| `UKismetSystemLibrary::LoadAsset_Blocking` | KismetSystemLibrary.h:395 | yes | `UObject* LoadAsset_Blocking(TSoftObjectPtr<UObject> Asset)` |
| `USceneComponent::K2_AttachToComponent` | Components/SceneComponent.h:747 | BlueprintCallable | `(Parent, FName SocketName, EAttachmentRule Location, Rotation, Scale, bool bWeldSimulatedBodies)`; `EAttachmentRule` KeepRelative=0, KeepWorld=1, **SnapToTarget=2** |
| `USceneComponent::SetHiddenInGame` | Components/SceneComponent.h:915 | BlueprintCallable | `(bool NewHidden, bool bPropagateToChildren=false)`; clear hidden state on the VR arms body after the game hides the diver at the first-person helm |
| `USceneComponent::K2_GetComponentLocation` / `K2_GetComponentRotation` | SceneComponent.h:644 / 648 | BlueprintCallable | used in `ABP_VRArms` |
| `USkinnedMeshComponent::HideBoneByName` | Components/SkinnedMeshComponent.h:2034 | BlueprintCallable | `(FName BoneName, EPhysBodyOp)`; **PBO_None=0** (:85) |
| `USkinnedMeshComponent::UnHideBoneByName` | SkinnedMeshComponent.h:2043 | BlueprintCallable | `(FName BoneName)` |
| `AActor::SetActorHiddenInGame` | Actor.h:1912 | BlueprintCallable | `(bool bNewHidden)` |
| `AActor::K2_DestroyActor` | Actor.h:1924 | BlueprintCallable | `()` |
| `AActor::GetActorRightVector` | Actor.h:1591 | BlueprintCallable | used in `ABP_VRArms` |
| `UAnimInstance::GetOwningActor` / `BlueprintUpdateAnimation` | Animation/AnimInstance.h:533 / 551 | BlueprintCallable / event | used in `ABP_VRArms` |
| `UKismetMathLibrary::Add_VectorVector` / `Multiply_VectorFloat` | Kismet/KismetMathLibrary.h:1378 / 1406 | BlueprintPure | elbow hints |
| `FAnimNode_TwoBoneIK` fields | AnimGraphRuntime/.../AnimNode_TwoBoneIK.h:26/80/84 | node props | `IKBone`, `EffectorLocationSpace`, `JointTargetLocationSpace` = **BCS_WorldSpace** (AnimTypes.h:62) |
| `FAnimNode_ModifyBone` fields | AnimNode_ModifyBone.h:37/57/69 | node props | `BoneToModify`, `RotationMode`=**BMM_Replace**, `RotationSpace`=BCS_WorldSpace |
| `FAnimNode_CopyPoseFromMesh::bUseAttachedParent` | AnimNode_CopyPoseFromMesh.h:28 | node prop | true, so `Body` must be attached to the game mesh |
| `USkeletalMeshComponent::AnimClass` | Components/SkeletalMeshComponent.h:368 | property | `ABP_VRArms_C` |
| UEVR global usertype `UEVR_UObjectHook.activate()`, `UEVR_UObjectHook.get_or_add_motion_controller_state(obj)`, `:set_hand(0 left, 1 right)`, `:set_permanent(bool)` (NOT `uevr.uobject_hook`, which is nil in game) | lua-api ScriptContext.cpp:990, 991, 1028, 984, 985 (UEVR 4ee5c6b) | Lua API | hand index from UObjectHook.cpp |
| Cook setting `[CookSettings] CookContentMissingSeverity=Warning` | Editor/UnrealEd/Private/Cooker/CookImportsChecker.cpp:683 | DefaultEditor.ini | stand-in references are external on purpose |

**Enum values** (Engine/EngineTypes.h):
- `ESpawnActorCollisionHandlingMethod`: Undefined=0, **AlwaysSpawn=1** (we pass 1),
  AdjustIfPossibleButAlwaysSpawn=2, …
- `ESpawnActorScaleMethod` (uint8): OverrideRootScale=0, **MultiplyWithRoot=1** (we pass 1),
  SelectDefaultAtRuntime=2

**Runtime cross-check:** the plugin resolves functions and parameters by name through UEVR's
reflection (`find_function`, `find_property`) and logs their offsets. The M1 run on
2026-11-16 logged `Make(PathString=0, Ret=16 size=48) Conv(In=0, Ret=32 size=72)
Load(Asset=0, Ret=40 size=48)`, and `LoadAsset_Blocking` returned the class.

**UEVR SDK calls** (plugin SDK 2.39, `plugin/third_party/uevr/API.h` at 4ee5c6b) are checked
against that vendored header, and OpenVR calls against `plugin/third_party/openvr/openvr.h`
(`IVRInput_010`, `IVRSystem_022`).
| `USceneComponent::AttachChildren` | Components/SceneComponent.h:116 | property (Transient) | read from Lua as a 1-based table, nil when empty (UEVR ScriptUtility.cpp:206) |
| `USceneComponent::GetAttachParent` / `GetAttachSocketName` | Components/SceneComponent.h:683 / :687 | BlueprintCallable | held-item scan; FName returns use `:to_string()` |
| `USkinnedMeshComponent::GetSocketBoneName` / `GetParentBone` | Components/SkinnedMeshComponent.h:1094 / :1181 | BlueprintCallable | `GetParentBone` returns `None` at the root |
| `USceneComponent::DoesSocketExist` | Components/SceneComponent.h:814 | BlueprintCallable | checked on `Body` before re-attaching |
| UEVR `MotionControllerState:set_location_offset(Vector3f)` | UEVR ScriptContext.cpp:967; applied in UObjectHook.cpp:925 | Lua API | controller OpenVR frame, cm; +Z = back toward the wrist |
| UEVR `uevr.params.vr.set_mod_value(key, string)` | uevr/API.h; Lua ScriptContext.cpp:481 | Lua API | `VR_CameraForwardOffset`, `VR_CameraUpOffset`, `VR_AimMethod` (VR.hpp:45: 1 head, 2 right controller), `VR_MovementOrientation` |
| UEVR `uevr.params.vr.get_pose(index, UEVR_Vector3f, UEVR_Quaternionf)` | ScriptContext.cpp:456; PluginLoader get_pose = `VR::get_transform` | Lua API | raw SteamVR tracking space, metres |
| UEVR `on_post_calculate_stereo_view_offset(device, view_index, world_to_meters, position, rotation, is_double)` | ScriptContext.cpp:157 / :1367 | Lua callback | UE5 passes Vector3d; eye world position, but disagreed with hand-derived numbers, so treat as approximate |
| `USceneComponent::IsVisible` | Components/SceneComponent.h:834 | BlueprintCallable | hook gun `Hook` mesh: hidden = hook out (GA_HookGun L0488 / L0D51) |
| `UActorComponent::GetOwner` | Components/ActorComponent.h:490 | BlueprintCallable | from the attached tool component to `BP_HookGunEquipment` |
| UEVR `on_xinput_get_state(retval, user_index, state)`, `state.Gamepad.bRightTrigger` | ScriptContext.cpp:125 / :1219; lua-api datatypes/XInput.cpp:11 | Lua callback, writable member | virtual primary-use taps (right trigger = `IA_PrimaryUse`) |
| UEVR `UFunction:hook_ptr(pre, post)`; post receives `(fn, obj, locals, result)` | ScriptContext.cpp:805 / :1209 | Lua API | post-hook `ABP_V03_C:BlueprintUpdateAnimation` to zero `ControlRotaton` pitch |
| UE5 rotator property read from Lua | ScriptUtility.cpp:156-170 | Lua API | returns a live `Vector3d` (x = Pitch, y = Yaw, z = Roll); writing `x` changes the object |
| `APawn::Controller`, `AController::GetControlRotation` | GameFramework/Pawn.h:198, Controller.h:159 | property, BlueprintCallable | harness torso check |
| `USceneComponent::GetSocketRotation` | Components/SceneComponent.h:799 | BlueprintCallable | `spine_05` pitch in the harness |
| `UWidgetBlueprintLibrary::GetAllWidgetsOfClass` | UMG/Public/Blueprint/WidgetBlueprintLibrary.h:302 | BlueprintCallable | finds the live `WBP_Cross_C`; array out-param through an empty Lua table |
| `UWidget::SetRenderOpacity` | UMG/Public/Components/Widget.h | BlueprintCallable | fades the game's 2D dot while the 3D dot is shown |
| `USceneComponent::SetVisibility` / `UStaticMeshComponent::SetStaticMesh` / `UPrimitiveComponent::SetMaterial`, `SetCollisionEnabled`, `SetCastShadow` / `SetWorldScale3D` / `AActor::K2_SetActorLocation` / `UKismetSystemLibrary::LineTraceSingle` / `APlayerCameraManager::GetCameraLocation`, `GetCameraRotation` | SceneComponent.h:899, StaticMeshComponent.h:426, PrimitiveComponent.h:1516/1942/1881, SceneComponent.h:565, Actor.h:1575, KismetSystemLibrary.h:1243, PlayerCameraManager.h:706/702 | BlueprintCallable | hook gun reticle |
| `UKismetMathLibrary::MakeTransform` | Kismet/KismetMathLibrary.h:3929-3930 | BlueprintPure | `item_rot` offset for held tools |
