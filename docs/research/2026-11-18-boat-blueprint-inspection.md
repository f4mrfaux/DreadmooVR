# Boat Blueprint inspection: cooked game assets

Date: 2026-11-18

## Source and method

The installed game is Steam build `26709786`; its `Dreadmoor-Windows.utoc` was last written
2026-11-16. EngineWire was connected to Unreal Editor PID `27940`, launched with the mod project
`unreal/Dreadmoor/Dreadmoor.uproject`. MCP reported the active editor world as
`/Temp/Untitled_1`. The asset registry search returned no matches, and `asset.query_asset`
`lookup=exists` returned false for both:

- `/Game/Dreadmoor/Core/Features/Ship/BP_SmallBoat_V2`
- `/Game/Dreadmoor/Core/Features/Ship/Riding/BP_ShipSteeringWheel`

These are game assets, not part of the mod project's registered content. EngineWire cannot load
their editor Blueprint graphs from the game's cooked IoStore packages. We therefore used the
project's read-only parser against the installed game container, not MCP, to inspect current
bytecode:

```powershell
python -I tools/re/bpdump.py <output-folder> BP_SmallBoat_V2$ BP_ShipSteeringWheel$
```

The fresh output was compared with `docs/research/bp-dumps/`. The steering wheel dump matched
exactly. The boat dump matched in bytecode; four lines differed only in the parser's heuristic
`NiagaraDataInterfaceWater_0`/`_1` reference labels and an SCS reference omitted by one version of
the heuristic. No boat graph behavior changed in the installed build relative to the checked-in
dump. The tool reads the game containers and writes only its requested output folder.

## Findings confirmed from current cooked bytecode

- `BP_SmallBoat_V2.ExecuteUbergraph_BP_SmallBoat_V2`, called from its tick path, polls
  `IA_BoatMove` with `GetBoundActionValue` and converts it to a 2D axis. The X axis selects
  steering roll `+65` or `-65` degrees (zero returns to the hull's calm-roll offset); the Y axis
  selects throttle lever roll `+25`, `-22`, or `0` degrees. Both are interpolated with `FInterpTo`
  at speed `2`.
- The cooked `Small_Boat_Steerwheel` static mesh exports an `LHand_Socket`, and `Throttle_lever`
  exports an `RHand` socket. These are the authored grip transforms for the two visible controls;
  use them to position the rendered VR hands instead of estimating grip offsets from screenshots.
- `IA_BoatLook` feeds its X/Y values directly to `AddControllerYawInput` and
  `AddControllerPitchInput`. In the first-person tracked helm, that gamepad look rotates the
  control frame under the tracked hands; the mod now suppresses right-stick look only in that
  view, leaving head tracking active and third-person gamepad look unchanged.
- `BP_ShipSteeringWheel` listens for the `CosmeticModulars.Ship.Wheel` slot change. With a
  cosmetic wheel installed, it hides the base `Small_Boat_Steerwheel`, enables actor ticking,
  resolves the active cosmetic module, and on each tick copies the steering-wheel actor's world
  rotation to the cosmetic actor. Removing the cosmetic restores the base mesh and disables the
  tick.

This confirms the intended native third-person axes and the game's cosmetic-wheel sync logic.
It does not prove that a particular live cosmetic instance follows correctly at runtime, because
the cooked code is disassembled rather than exercised in PIE. The mod's gesture steering and the
cosmetic mesh should still be smoke-tested in game.

## Mod comparison and correction

The mod's post-tick cosmetic sync had been copying the base mesh component's world rotation. The
game Blueprint copies the steering-wheel actor's world rotation to
`CurrentActiveWheelCosmetic.Actor`. Since the mesh component can carry its own relative rotation,
using the component can inject an unwanted offset into the cosmetic mesh. The mod now reads
`K2_GetActorRotation()` from the wheel actor and writes it to the nested cosmetic actor, matching
the shipped Blueprint. The smoke fixture uses the same wrapper/Actor shape and gives the mesh a
deliberately different rotation. This verifies the source and destination in the harness; a live
in-game cosmetic-wheel check is still required.

The current boat dump also confirms `bFirstPersonCameraEnabled` is updated by the boat's camera
switch event. The gesture bridge now gates its XInput axis override on that flag: third-person
keeps native stick steering and throttle, while first-person captures a fresh hand-neutral pose
and drives the same `IA_BoatMove` axes. Switching back immediately releases the override. The
targeted harness covers both camera transitions and verifies the physical stick values pass
through unchanged in third-person.

## Verification

- `lua tests/run.lua boat`: 8 passed, 0 failed.
- `lua tests/run.lua`: 132 passed, 0 failed.
- The updated Lua scripts were deployed to the UEVR profile with `tools/deploy.ps1 -NoPak`; the
  game pak was left untouched. Live headset validation of the camera switch and cosmetic wheel
  remains outstanding.

## 2026-11-19 build 26786104 throttle follow-up

Re-dumped `BP_SmallBoat_V2` from the newly installed `Dreadmoor-Windows.utoc` into
`docs/research/bp-dumps/BP_SmallBoat_V2-build-26786104.txt`. The throttle graph is unchanged: positive
`IA_BoatMove.Y` selects the `+25` lever target, negative selects `-22`. The 11:30 runtime trace
also agrees: positive input (`+0.24` to `+0.64`) accompanies forward travel, while negative input
(`-1.00`) accompanies reverse travel. The gamepad axis sign was therefore retained.

M3 previously projected head-relative hand Z against the HMD yaw captured at helm entry. In the
user's run, HMD orientation changed substantially after calibration, and a forward throttle
attempt crossed the old frame's reverse threshold. M3 now stores the right-hand neutral point in
tracking space and projects hand displacement onto the current HMD forward axis while neutral. It
freezes that axis when a detent is being engaged or held, so head movement cannot flip an active
throttle. This is a source correction; neutral/forward/reverse and head-turn hardware validation
remain outstanding.
