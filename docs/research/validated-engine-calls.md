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
| `AActor::K2_TeleportTo` | Actor.h:3327 | BlueprintCallable | `bool K2_TeleportTo(FVector DestLocation, FRotator DestRotation)` |
| `AController::GetControlRotation` | GameFramework/Controller.h:159 | BlueprintCallable | `virtual FRotator GetControlRotation() const` |
| `UGameplayStatics::BeginDeferredActorSpawnFromClass` | Kismet/GameplayStatics.h:67 | BlueprintCallable, BlueprintInternalUseOnly | `(WorldContextObject, ActorClass, const FTransform& SpawnTransform, ESpawnActorCollisionHandlingMethod CollisionHandlingOverride, AActor* Owner = nullptr, ESpawnActorScaleMethod TransformScaleMethod = MultiplyWithRoot)` |
| `UGameplayStatics::FinishSpawningActor` | GameplayStatics.h:71 | BlueprintCallable, BlueprintInternalUseOnly | `(AActor* Actor, const FTransform& SpawnTransform, ESpawnActorScaleMethod TransformScaleMethod = MultiplyWithRoot)` |
| `UKismetSystemLibrary::MakeSoftObjectPath` | Kismet/KismetSystemLibrary.h:336 | yes | `FSoftObjectPath MakeSoftObjectPath(const FString& PathString)` |
| `UKismetSystemLibrary::Conv_SoftObjPathToSoftObjRef` | KismetSystemLibrary.h:344 | yes | `TSoftObjectPtr<UObject> Conv_SoftObjPathToSoftObjRef(const FSoftObjectPath&)` |
| `UKismetSystemLibrary::LoadAsset_Blocking` | KismetSystemLibrary.h:395 | yes | `UObject* LoadAsset_Blocking(TSoftObjectPtr<UObject> Asset)` |
| `USceneComponent::K2_AttachToComponent` | Components/SceneComponent.h:747 | BlueprintCallable | `(Parent, FName SocketName, EAttachmentRule Location, Rotation, Scale, bool bWeldSimulatedBodies)`; `EAttachmentRule` KeepRelative=0, KeepWorld=1, **SnapToTarget=2** |
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
