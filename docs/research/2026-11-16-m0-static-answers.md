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
| Directional drag | `IA_QTE_LMB` held + `IA_QTE_Look` | A held + left stick (inferred; headset check pending) | Widget bindings read; `imc.py` heuristic finds left mouse + left stick, but may miss an additional gamepad mapping |
| Reeling | `IA_Fishing_Cast` held | right trigger held | **Read** |

## Fight direction

**Corrected by Bob from play (2026-11-16):** you pull **against** the fish, as in real
fishing. My first reading said the opposite and was wrong.

What the code does show (**Read**):

- `IA_Fishing_Fight` is stick X with no negate modifier, so stick left is negative.
- `GetPlayerDirection`: `StruggleX < 0` gives 1 (left), `> 0` gives 2 (right).
- `IsSameDirection` is true when the player's value equals `FishDirection`, and the HUD arrow
  turns green.

Where I went wrong: I took `FishDirection == 2` to mean "fish to the right" because it puts
the fish at +Y in `GetFishMeshTargetOffset`. That offset is in the fish component's own frame,
which evidently faces back toward the player. That flips Y, so `FishDirection` 2 is the fish
going **left**, and the matching input is the opposite side.

**For VR:** lean the rod **away** from the fish to match. The bridge maps a rod lean past the
threshold to stick X ±1, with the sign equal to the lean side. That needs no inversion,
because the game's "match" is already "pull opposite". Haptics should confirm a match.

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
