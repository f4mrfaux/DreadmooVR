# Fishing VR bridge

Last checked: 2026-11-17. Static evidence is from Steam build 26670657 and the cooked
Blueprint dumps under `docs/research/bp-dumps/`; live headset behavior still needs confirmation.

## Verified game contract

- Fishing mode is identified by `DrdFishingControllerBase` (`src/scripts/lib/gameapi.lua`).
- `BP_FishingController` receives `IA_Fishing_Cast` on right trigger. Press sets `bMousePressed`
  and release clears it. The same held action drives normal reeling; keep the user's physical
  trigger available for casting and QTEs.
- A valid `StrugglingFish` marks the hooked-fish phase. `CurrentQTE` is a gameplay tag and is
  set to `None` when the QTE ends. Do not run the reel gesture while a QTE is active.
- `IA_Fishing_Fight` reads gamepad left-stick X. `UpdateStruggleX` copies that axis into
  `StruggleX`; `GetPlayerDirection` maps negative to 1 and positive to 2; `IsSameDirection`
  compares that result with `FishDirection`.
- Bob's play note says to pull the rod away from the fish. Preserve the lean-side sign when
  writing left-stick X; the game's direction convention already accounts for the fish's facing.
- `QTE.Type.DirectionalDrag` listens for `IA_QTE_LMB` held plus `IA_QTE_Look` (left stick).
  `imc.py` finds `LeftMouseButton` for `IA_QTE_LMB` in both `IMC_QTE_Drag` and
  `IMC_QTE_Drag_UI`, and `Gamepad_Left2D` for `IA_QTE_Look`. The older M0 note reports A for
  `IA_QTE_LMB`, but that is not confirmed by this heuristic dump. Since the parser is explicitly
  heuristic and Frame A is verified to arrive as XInput A (`0x1000`), treat A as the first
  controller path to test; do not add mouse injection unless the live QTE proves A is ignored.
- `IMC_Fishing`: right trigger = cast, left trigger = recast, left-stick X = fight. The crank
  gesture uses the same left-hand circular path as the hook gun and holds right trigger only
  while a fish is active and no QTE is showing.

## Bridge behavior

- Production input path: `m3_gestures.lua` samples poses in `on_pre_engine_tick`, then writes
  gesture outputs directly to the XInput `state.Gamepad` in its single
  `on_xinput_get_state` callback. Trigger writes are already used for hook/melee gestures;
  fishing extends that same callback with `sThumbLX/Y`. Neutral gesture values leave physical
  Frame input alone. The callback does not synthesize `wButtons`, since UEVR rebuilds those
  button bits after Lua callbacks.
- `src/scripts/lib/pad.lua` is a pure merge helper covered by `tests/test_pad.lua`, but no runtime
  script calls it. Treat it as dormant; it does not describe how live gesture inputs are applied.
- On a new struggling fish, calibrate the right-hand horizontal offset relative to the HMD.
- While fighting and outside a QTE, horizontal right-hand lean past a deadzone writes a signed
  left-stick X value. Physical input passes through while the gesture is neutral.
- During `QTE.Type.DirectionalDrag`, right-hand horizontal/vertical movement writes left-stick
  X/Y. The normal crank stays disabled. Keep Frame A available as the game's possible held
  `IA_QTE_LMB` input; its exact gamepad mapping remains a headset check.
- All other QTEs and non-fishing phases keep their physical inputs. In particular, no inferred
  cast, bite, land, or timed-reel gesture is synthesized.
- Fishing lean thresholds and melee guard posture bounds are exposed in the live
  `gestures` table of `src/data/dreadmoorvr_arms_tuning.lua`; changes are re-read once per second.
  Guard uses a 100 ms pose dwell and separate enter/exit angles to prevent flicker.
- The 2026-11-18 reliability pass shares the boat's pose validator: active controller tracking,
  finite and bounded SteamVR positions, and a normalized near-unit quaternion are required for
  left/right/HMD poses. A tracking or pose failure clears the fish and QTE neutral references,
  resets crank accumulation, zeros gesture axes, and releases synthetic reel input. The next valid
  frame recalibrates against the current fish/QTE. This is code-reviewed but still needs a headset
  check because fishing has not yet had a complete playtest.

## Source map (avoid re-dumping)

- `docs/research/2026-11-16-m0-static-answers.md` — fishing tags, QTE inputs and fish-direction
  correction from play.
- `docs/research/bp-dumps/BP_FishingController.txt` — `InpActEvt_IA_Fishing_Cast_*`,
  `GetPlayerDirection`, `IsSameDirection`, `UpdateStruggleX`, `QTEFinished`, `StartQTE`.
- `docs/research/bp-dumps/WBP_QTE_DirectionalDrag.txt`, `WBP_QTE_Reel.txt`,
  `WBP_QTE_FishLand.txt`, `WBP_QTE_FishingBite.txt` — prompt action bindings.
- `python -I tools/re/imc.py "IMC_Fishing$"` — cooked input mapping summary.
- `docs/research/2026-11-16-frame-plugin-phase2.md` — observed Frame A → XInput A (`0x1000`).
- Implementation: `src/scripts/m3_gestures.lua`; common crank detector:
  `src/scripts/lib/gestures.lua`.

## Smoke coverage

`lua tests/run.lua` exercises the live `m3_gestures.lua` against a fake UEVR/game boundary. The
fishing cases verify that the left-hand crank holds the game's right-trigger reel action and
releases it when rotation stops, right-hand lean writes fishing fight X, and
`QTE.Type.DirectionalDrag` writes X/Y while suppressing the crank. These checks validate Lua
wiring and values; they do not confirm the Frame controller, Enhanced Input, or headset feel.

The M3 integration smoke fixture also tests the right-hand thumb-down guard: it must claim the
left trigger (Secondary Use) after the pose dwell without touching the right-trigger attack,
release after the hand leaves the front guard zone, and leave physical triggers alone when
`guard_enabled = false`.

The M3 smoke fixture must provide UEVR's `get_hmd_index()` because both the guard and fishing
lean reference the HMD pose. This API exists in the vendored UEVR interface (`plugin/third_party/uevr/API.h`);
the earlier fixture omitted it, causing the guard smoke check to fail without indicating a game
runtime defect.

## Open validation

- **Base-game fish landing issue reported 2026-11-17:** landing animation does not
  play and the fight restarts. The bridge does not synthesize FishLand input or
  handle that game's completion transition. Static review found a plausible
  timeout path in the base game: FishLand returns failure if its timer fills,
  and `BP_FishingController.QTEFinished` restores stamina on generic QTE failure.
  Confirm `IA_QTE_Interact` delivery and the successful FishLand StateTree
  transition with a runtime trace. See
  `logs/fish-landing-restarts-fight-2026-11-17.log` for evidence and checks.
- Confirm the right-hand lean neutral offset and sign feel natural while seated/standing.
- Confirm the directional-drag QTE accepts hand X/Y movement in game.
- In the headset, hold Frame A during DirectionalDrag and FishClicker QTEs; determine whether
  those contexts accept XInput A or need a mapping fix.
- Confirm the held right-trigger crank continues reeling for the full drag and releases cleanly
  when movement stops or a QTE begins.
