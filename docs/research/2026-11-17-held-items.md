# How Dreadmoor attaches held tools (verified 2026-11-17)

Read from the game's own Blueprint bytecode and asset data (Steam build 26670657) with
`tools/re/bpdump.py`. Dumps are in `docs/research/bp-dumps/`. Item data dumps were written to
`build/itemdump/`; rerun `bpdump.py build/itemdump "IDA_HookGun$" "IDA_Harpoon$" "IDA_Knife$" "IDA_Sickle$" "SK_DreadMoreSkeleton$"`.

## The chain

1. **The item data says where.** Each tool's `IT_Equipment_C_0` holds its equip information.
   - `EquipAttachToComponentWithTag` is the tag of the character component to attach to.
   - `EquipSocket` is the socket on that component.

   | Item | Equipment actor | Tag | Socket |
   |---|---|---|---|
   | `IDA_HookGun` | `BP_HookGunEquipment` | `PlayerMesh` | `HookSimple` |
   | `IDA_Harpoon` | `BP_HarpoonEquipment` | `PlayerMesh` | `Harpoon_Socket` |
   | `IDA_Knife` | static mesh | `PlayerMesh` | `KnifeSocket` |
   | `IDA_Sickle` | `BP_Sickle_Equipment` | `PlayerMesh` | `KnifeSocket` |

   There is no axe item. The melee tools are the knife and the sickle.

2. **`PlayerMesh` is the character mesh.** `BP_PlayerCharacter`'s `CharacterMesh0` (the
   pawn's `Mesh`, mesh `dm_demo_NewProtagonist`) carries the `PlayerMesh` tag.
   The `Camera` and the flashlight `SpotLight` are attached to it at `head`.

3. **The sockets are on the right hand.** They are defined on the skeleton
   `SK_DreadMoreSkeleton`.
   - `HookSimple`, `Harpoon_Socket` and `KnifeSocket` all sit on `hand_r`.
   - So do `FishingRod`, `Nozzle`, `RepairGun`, `PolypusGun` and the `Repair_*` sockets.
   - `Forceps_LHand`, `Reel_l_Socket` and `Fueling_LSocket` sit on `hand_l`.
   - `Camera` sits on `head`.

4. **The attach call.** In `SO_ExecuteEquipmentData`:
   - `DrdGetComponentToAttach(owner, EquipAttachToComponentWithTag)` finds the tagged component (L1735).
   - `BP_AC_EquipmentManager.Equip Item(component, ..., EquipSocket, ...)` is called (L188A).
   - Blueprint equipment is spawned and the whole actor is attached with
     `K2_AttachToComponent(Attach To, SocketName, 0, 0, 0, true)`, which is KeepRelative
     (`BP_AC_EquipmentManager` L0621).
   - Static and skeletal equipment attach a new component the same way (L0318, L0317).

5. **The game re-attaches.** `MC_ReattachItem(tag, EquipAttachToComponentWithTag, EquipSocket,
   EquipTransform)` (`SO_ExecuteEquipmentData` L1CD1) runs another
   `K2_AttachToComponent(<tagged component>, EquipSocket, 0, 0, 0, true)` after
   `DoesSocketExist`, so the game can take a tool back after we move it.

6. **Unequip still finds moved tools.** Unequip uses `FL_InventoryFramework.GetComponentByTag`
   and `GetAttachedActors(..., true, true)` from the player. Both search recursively, and
   `BP_VRArms` is attached to the player's mesh, so a tool on our Body is still found and
   destroyed.

7. **Aim comes from the view.** `GA_HookGun` and `GA_Harpoon` aim from
   `PlayerController.GetPlayerViewPoint`. UEVR's aim method drives the control rotation, so with
   `aim_method = 2` the direction follows the right hand while the origin stays at the camera.
   That last point is inferred, not observed; check it in the headset.

## What this means for `items_follow_hands`

- The scan looks at `pawn.Mesh.AttachChildren`. That matches step 2: tools attach to
  `CharacterMesh0`.
- It moves a child whose socket's bone is `hand_l` / `hand_r` or below. That matches step 3.
  The camera and flashlight on `head` are skipped, as are leader-pose clothing pieces with
  socket `None`.
- It re-attaches with KeepRelative, the same rule the game uses, so `EquipTransform` is kept.
- Our Body uses the same skeleton, so the sockets exist on it. The bridge still checks
  `DoesSocketExist` and logs a failure instead of guessing.
- Step 5 is why the bridge stops after 3 quick take-backs (within 2 s).

## Still unverified

- Whether `MC_ReattachItem` fires during normal play or only on network and equip-notify paths.
  The first in-game run's `held item` log lines will show it.
- The projectile origin when aiming with the hand (step 7).

## Correction from the first in-game run (16:50)

At runtime `GetSocketBoneName` returns **`Hand_R`** and **`Head`**, capitalised. The
skeleton dump's name table shows lowercase `hand_r`. Unreal names compare case-insensitively
but Lua strings don't, so name checks in Lua must ignore case (`lib/itemfollow.lua` does now).
The run also logged `BP_FirstAid_Equipment` attached at `Syringe_Socket` on `Hand_R`. The
hook gun's attached component is its `SkeletalMesh`, not the actor root.
