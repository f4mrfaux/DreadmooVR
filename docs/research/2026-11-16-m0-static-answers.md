# M0 questions answered from the game's code (2026-11-16)

Bob asked whether the M0 headset run was needed for these, or whether the code could answer
them. Most of them come straight from the Blueprint dumps in `docs/research/bp-dumps/` and the
mapping contexts read with `tools/re/imc.py`. **Read** means seen in the code. **Inferred** means
deduced from it.

## Fishing states

**Read.** The fishing controller's `State` is a gameplay tag, not an enum:

| Tag | Meaning |
|---|---|
| `Fishing.State.Idle` | rig up, nothing happening |
| `Fishing.State.Start` | entering fishing |
| `Fishing.State.Aiming` | cast held, power meter up |
| `Fishing.State.Casting` | float in flight or waiting for a bite |
| `Fishing.State.Fighting` | fish hooked |
| `Fishing.State.Finish.Success` / `.Failed` | landed or lost |

The fish has its own state: `Fishing.Fish.State.Idle`, `.Fighting`, `.Exhausted`, `.Escaped`.
Events on the controller are `Fishing.Event.QTE`, `.Attack` and `.GAS`. This list is what the
code compares against. The state tree could hold more tags that no Blueprint names.

## Prompt buttons

| Prompt | Action | Gamepad | Source |
|---|---|---|---|
| Bite | `IA_Fishing_Cast` | right trigger | **Read**: `WBP_QTE_FishingBite` listens for it; `IMC_Fishing` |
| Land (`WBP_QTE_FishLand`) | `IA_QTE_Interact` | A (keyboard F) | **Inferred**: `IMC_QTE` holds only F, A, left stick, right trigger and left mouse, and Interact pairs with F/A |
| Reel timing (`WBP_QTE_Reel`) | `IA_QTE_Interact` | A | same |
| Directional drag | `IA_QTE_LMB` held + `IA_QTE_Look` | A held + left stick | **Read**: `IMC_QTE_Drag` holds only A, left stick and left mouse |
| Reeling | `IA_Fishing_Cast` held | right trigger held | **Read** |

## Fight direction

**Read**, end to end:

- `IA_Fishing_Fight` is stick X with no negate modifier, so stick left is negative.
- `GetPlayerDirection`: `StruggleX < 0` gives 1, `> 0` gives 2, and 0 gives 0.
- For the fish, `FishDirection == 2` puts the fish mesh at +Y beside the rod in
  `GetFishMeshTargetOffset`, and it turns the camera +17.5° of yaw in `RotateControl`. Both of
  those are to the right.
- So 1 means left and 2 means right, for both the player and the fish.
- `IsSameDirection` succeeds when the player pushes **toward the side the fish is swimming**.
  The HUD (`WBP_FishingStruggle.UpdateDirection`) shows an arrow on the fish's side, and it
  turns green when you match.

**For VR:** lean the rod **toward** the fish to match. That follows the fish, the opposite of
real-world pulling against it. The bridge maps a rod lean of more than the threshold to stick X
±1, with the sign equal to the lean side. Haptics should confirm a match.

## Hook gun

**Read**:

- Each primary-use press adds `Config.PressPercent` to `DragForceMul`, clamped to
  `Config.MaxMultiplier`.
- Every tick it subtracts the literal **0.008**, floored at 0.
- The pull is `Config.DragForce × (DragForceMul + 1)`.
- Aim comes from the player's view point.
- `Config` comes from the native `DrdConfigsSubsystem.GetConfigHookGun()`, which means the
  numbers live in native config data, not in any Blueprint.

**Not readable statically without a mappings file.** Those numbers don't change the bridge's
design: one crank click is one press, and the game's clamp caps the pull. The M0 probe logs
the numbers the first time the hook gun is fired in a live session. It's useful but not
blocking.

## Still needs the headset

- **Bench layout in VR.** Where the fixed bench camera puts the piles relative to the head is
  a viewing question, not a code question.
- **Whether UEVR's emulated pad reaches the QTE widgets.** The widgets bind through Enhanced
  Input like the rest, so it is expected to work.
- **Comfort with the game steering the view** during a fight (`RotateControl`).
