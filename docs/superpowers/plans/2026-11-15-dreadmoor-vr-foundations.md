# Dreadmoor VR — Plan 1: Foundations (M0, M1, M2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove UEVR runs the game (M0), prove a mod pak cooked in UE 5.6 loads and spawns (M1), and stand up the bridge skeleton with mode detection, virtual pad, config reload and readout (M2).

**Architecture:** Two halves per the spec. A content pak cooked from `unreal/Dreadmoor` as chunk 1 under IoStore, renamed `DreadmoorVR_P.*`, dropped in `Content\Paks\~mods`. A UEVR Lua bridge in the game's UEVR profile folder that loads the pak's class and drives it. This plan stops at M2. Arms, fishing, bench and hook gun go in Plan 2, written after the M0 and M1 gates, because their interfaces depend on what those gates find.

**Tech Stack:** UE 5.6 (`C:\Program Files\Epic Games\UE_5.6`), EngineWire MCP for editor authoring, UEVR revision `1a810f69` (`Downloads\UEVR`), Lua 5.4 (UEVR's scripting), PowerShell 7, Python 3.13 (existing `tools/re`).

**Spec:** `docs/superpowers/specs/2026-11-15-dreadmoor-vr-gestures-design.md`

## Global Constraints

- Use UE 5.6 only. Never `UE_5.8`.
- Mod assets live under `/Game/DreadmoorVR/` only. Stand-ins at game paths are never cooked into the pak.
- Write nothing outside `D:\SteamLibrary\steamapps\common\DREADMOOR\Dreadmoor\Content\Paks\~mods\` and `%APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\` (plus this repo). Never modify a file the game shipped with.
- Every game name (class, property, function) appears only in `src/scripts/gameapi.lua`.
- Any new download is named, sized and approved by Bob first. Known in this plan: Lua 5.4 Windows binaries (Task 2), possibly UE4SS for a one-off mappings dump (Task 3).
- Big logs and dumps go to the `local-delegate` MCP, not into context. Spot-check its claims by reading the cited lines.
- Bob works over Remote Control: every question to him goes in message text.
- Headset steps are run by Bob. The builder writes the checklist, then reads the logs.

## Review Focus

1. **Pawn switch mid-frame** (possess changes while a mode's enter step runs): expect the old mode's exit to run exactly once and the readout never to show two modes. Test: `test_modes_switch_runs_exit_once` in Task 8.
2. **Pawn class not in the table** (tutorial or ground variants, diving, menus): expect `unknown`, gestures off, no error. Test: `test_modes_unknown_class` and `test_modes_matches_base_class` in Task 8.
3. **Config file edited to bad Lua or missing a key while running**: expect the last good config kept and an error line on the readout, never a crash. Test: `test_config_bad_reload_keeps_last_good` in Task 8.
4. **Real pad and virtual pad both pressing the same button, or a real stick moved while a gesture holds an axis**: buttons OR-ed, the held axis wins only while held, real input returns the frame it is released. Test: `test_pad_merge_*` in Task 8.
5. **A stand-in or engine file slipping into the pak**: the cook fails. Test: `test_list_container_flags_foreign_paths` in Task 4, exercised again by Task 6's run.

---

## File Structure

```
.gitignore                          ignores Unreal build dirs, Saved, DDC, EngineWire plugin, tools/bin
README.md                           what this repo is, how to deploy, where things go
docs/testing/m0-checklist.md        Bob's M0 headset checklist and what to record
docs/testing/m1-checklist.md        Bob's M1 headset checklist
docs/testing/m2-checklist.md        Bob's M2 headset checklist
profile/config.txt                  UEVR settings for this game (starts as UEVR's defaults)
src/scripts/main.lua                UEVR entry: wires callbacks to units
src/scripts/gameapi.lua             all game names; safe lookups returning nil
src/scripts/modes.lua               pawn class chain → mode; enter/exit bookkeeping
src/scripts/pad.lua                 virtual gamepad and merge into XInput state
src/scripts/config.lua              loads/reloads dreadmoorvr_config.lua with last-good fallback
src/scripts/debug.lua               on-screen readout, log file
src/scripts/armsloader.lua          loads a pak class by path and spawns it (M1 probe now, arms later)
src/scripts/m0_probe.lua            M0-only logger; removed from deploy after M0
src/data/dreadmoorvr_config.lua     tunables, returned as a Lua table
tests/run.lua                       tiny desk test runner (plain asserts)
tests/test_modes.lua, test_pad.lua, test_config.lua
tools/re/list_container.py          lists files in any .utoc, flags paths outside an allowed prefix
tools/re/test_list_container.py     unittest for it
tools/cook.ps1                      BuildCookRun → chunk 1 → rename → list and check
tools/deploy.ps1                    copies pak to ~mods, scripts+profile to UEVR folder
unreal/Dreadmoor/Config/DefaultGame.ini    IoStore + chunking packaging settings
unreal/Dreadmoor/Content/DreadmoorVR/      BP_PakProbe, PAL_DreadmoorVR (PrimaryAssetLabel)
```

The bridge loads units from `scripts/` in the profile folder. If UEVR's loader does not support `require` (spec section 10), `main.lua` uses `dofile` on paths built from the profile directory, and each unit returns its table.

---

### Task 1: Version control and layout

**Files:**
- Create: `.gitignore`, `README.md`, empty dirs via `.gitkeep` in `src/scripts`, `src/data`, `tests`, `profile`, `docs/testing`

- [ ] **Step 1: Ask Bob in message text whether to `git init` (spec D9).** Do not continue this task without a yes.
- [ ] **Step 2: Write `.gitignore`** ignoring: `unreal/Dreadmoor/Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`, `unreal/Dreadmoor/Plugins/EngineWire/` (third-party, re-fetched per `docs/setup/unreal-editor-mcp.md`), `unreal/build.log`, `tools/bin/`, `build/`, `*.pyc`, `.remember/`.
- [ ] **Step 3: Write `README.md`**: one paragraph of purpose, then where the pak and the profile are deployed (the two paths from Global Constraints), and links to the spec and this plan.
- [ ] **Step 4: `git init`, `git add -A`, check** `git status --short | grep -E "Binaries|Intermediate|DerivedDataCache|EngineWire"` prints nothing.
- [ ] **Step 5: Commit** `chore: initial repo with research, design and Unreal project`

### Task 2: Lua desk-test runner

**Files:**
- Create: `tests/run.lua`, `tools/bin/lua54/` (downloaded, git-ignored)

**Interfaces:**
- Produces: `lua tests/run.lua` runs every `tests/test_*.lua`; each test file returns `{ [name] = function() ... end }`; a failing `assert` prints `FAIL <file>::<name>: <message>`; exit code 1 on any failure, 0 otherwise, last line `N passed, M failed`.

- [ ] **Step 1: Ask Bob in message text to approve downloading Lua 5.4 Windows x64 binaries** from LuaBinaries on SourceForge (`lua-5.4.6_Win64_bin.zip`, about 300 KB). Add its SHA-256 to his tool hash manifest if he keeps one in the repo.
- [ ] **Step 2: Unpack into `tools/bin/lua54/`**, per the environment rule (new empty dir). Run `tools/bin/lua54/lua54.exe -v`. Expected: `Lua 5.4.6`.
- [ ] **Step 3: Write `tests/test_smoke.lua`** with one passing test and one deliberately failing test.
- [ ] **Step 4: Write `tests/run.lua`**, which sets `package.path` to include `src/scripts/?.lua` so tests `require` units directly.
- [ ] **Step 5: Run** `tools/bin/lua54/lua54.exe tests/run.lua`. Expected: one FAIL line, `1 passed, 1 failed`, exit 1. Delete the failing test, rerun, expect `1 passed, 0 failed`, exit 0.
- [ ] **Step 6: Commit** `test: add Lua desk test runner`

### Task 3: M0 probe and checklist (GATE)

**Files:**
- Create: `src/scripts/m0_probe.lua`, `docs/testing/m0-checklist.md`, `profile/config.txt`, `tools/deploy.ps1` (scripts and profile part only)

**Interfaces:**
- Produces: `tools/deploy.ps1 [-Probe] [-NoPak]` copies `src/scripts/*.lua` (plus `m0_probe.lua` only with `-Probe`), `src/data/*`, and `profile/*` into `%APPDATA%\UnrealVRMod\Dreadmoor-Win64-Shipping\` (scripts into its `scripts\` subfolder). Never deletes anything it did not write; keeps a `deployed.txt` manifest there to know what it wrote.
- Produces: the probe writes `dreadmoorvr_m0.log` in the profile folder.

- [ ] **Step 1: Write `m0_probe.lua`.** On every pre-engine tick: get the local pawn; when its class changes, log the full class chain (class → super → … → `Pawn`). While the pawn is a fishing controller, log on change: `State`, `CurrentQTE`, whether `StrugglingFish` is valid, `StruggleX`. While the hook gun ability is active, log `DragForceMul`, `DragForcePercentPerClick`, `DragForceMulMax` on change. Log every XInput state change (buttons and triggers) so prompt buttons can be matched to time stamps. Each line: `t=<seconds> <key>=<value>`. Use UEVR's Lua API (`uevr.sdk.callbacks.on_pre_engine_tick`, `uevr.api:get_local_pawn(0)`, `on_xinput_get_state`). Check the exact API names against the example scripts and `include/` that ship in `Downloads\UEVR` before writing.
- [ ] **Step 2: Write `profile/config.txt`.** Copy UEVR's default `config.txt` keys from an existing profile (for example `%APPDATA%\UnrealVRMod\Boltgun-Win64-Shipping\config.txt`). Set only snap turn on (D11). Leave everything else default.
- [ ] **Step 3: Write `tools/deploy.ps1`** (scripts/profile half). Run `tools/deploy.ps1 -Probe -NoPak -WhatIf`. Expected: it lists only paths under the profile folder.
- [ ] **Step 4: Write `docs/testing/m0-checklist.md`.** Two parts. **Before the headset:** start SteamVR streaming, launch the game, inject with `UEVRInjector.exe`, confirm `dreadmoorvr_m0.log` appears. **In the headset**, one line per check with what to look for: stereo and head tracking in walking, fishing, bench, boat, diving; controllers act as a gamepad; what the view does in each mode; cast, hook a fish, reel, fight left and right, land (note which way the fight indicator reads, and what the cast power meter does while the trigger is held); move the rod with the head and see whether the line follows; equip the hook gun, fire at a floating item, mash fire to drag, let go; note any "twist" prompt and what it asks; open the bench and move one item each way. **After:** UEVR menu → dump the SDK; then save the UEVR log and the probe log. **Mappings:** if UEVR cannot write a `.usmap`, ask Bob to approve a one-off UE4SS run to write one (named, sized, approved first, removed afterwards).
- [ ] **Step 5: Deploy, send Bob the checklist with SendUserFile, and stop.** M0 is a gate: wait for his run.
- [ ] **Step 6: After his run,** hand the logs to `local-delegate` with these questions: each pawn class chain seen; the `State` values in order through one catch; the XInput buttons pressed while `CurrentQTE` was set; the hook gun values. Spot-check each answer against the cited lines. Write the findings to `docs/research/2026-11-xx-m0-results.md`, and fill in the spec's unknowns list.
- [ ] **Step 7: Go/no-go.** If UEVR cannot hook or render: stop the plan and bring Bob the options (spec M0). Otherwise commit `docs: M0 results` along with the probe and deploy script.

### Task 4: Container lister

**Files:**
- Create: `tools/re/list_container.py`, `tools/re/test_list_container.py`

**Interfaces:**
- Consumes: `iostore.IoStore(utoc_path, oodle)`, `.files` (dict of path → chunk index), `cfg.OODLE_CANDIDATES`, `cfg.UTOC`.
- Produces: `list_files(utoc_path: str) -> list[str]` (sorted container paths); `foreign_paths(paths: list[str], allowed_prefix: str) -> list[str]`; CLI `python -I tools/re/list_container.py <utoc> [--allow Dreadmoor/Content/DreadmoorVR/]` prints each path and exits 1 if any `.uasset`/`.umap`/`.uexp`/`.ubulk` path falls outside `--allow`. Paths under `Dreadmoor/Content/DreadmoorVR/` plus the container's own metadata files are allowed.

- [ ] **Step 1: Write the failing tests:**
  - `test_list_game_container`: `list_files(cfg.UTOC)` contains `Dreadmoor/Content/3rdParty/TFPMovement/Demo/Character/Mannequins/Meshes/SK_DreadMoreSkeleton.uasset`.
  - `test_list_container_flags_foreign_paths`: `foreign_paths(["Dreadmoor/Content/DreadmoorVR/BP_PakProbe.uasset", "Dreadmoor/Content/Dreadmoor/Animations/Characters/new/dm_demo_NewProtagonist.uasset"], "Dreadmoor/Content/DreadmoorVR/")` returns only the second.
  - `test_allowed_only`: all-allowed input returns `[]`.
- [ ] **Step 2: Run** `python -I -m unittest tools/re/test_list_container.py -v` from `tools/re`. Expected: FAIL, `ModuleNotFoundError: list_container`.
- [ ] **Step 3: Implement it**, trying each Oodle candidate as `cfg.open_stores` does. A mod container may have no compressed blocks, so a directory listing must not need Oodle to work.
- [ ] **Step 4: Rerun.** Expected: 3 tests OK.
- [ ] **Step 5: Commit** `feat(re): list and check IoStore container contents`

### Task 5: Mod content and packaging settings

**Files:**
- Modify: `unreal/Dreadmoor/Config/DefaultGame.ini`
- Create (via the EngineWire MCP, editor running): `/Game/DreadmoorVR/BP_PakProbe`, `/Game/DreadmoorVR/PAL_DreadmoorVR`

**Interfaces:**
- Produces: `/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C`, an Actor with a 50 cm cube (`/Engine/BasicShapes/Cube`) as root and a `BeginPlay` that prints `DreadmoorVR pak loaded` to screen and log for 10 s.
- Produces: `PAL_DreadmoorVR`, a `PrimaryAssetLabel` with `Rules.ChunkId = 1`, `Rules.CookRule = AlwaysCook`, `bLabelAssetsInMyDirectory = true`.

- [ ] **Step 1: In `DefaultGame.ini`, under `[/Script/UnrealEd.ProjectPackagingSettings]`,** set `bUseIoStore=True`, `bGenerateChunks=True`, `UsePakFile=True`, `bShareMaterialShaderCode=False` (so the mod carries its own shaders), `BuildConfiguration=PPBC_Shipping`.
- [ ] **Step 2: Start the editor** (`UnrealEditor.exe` from UE_5.6 with the `.uproject`), wait for port 3000, then call `unreal search`.
- [ ] **Step 3: Create `BP_PakProbe`** with `blueprint.create`, add the cube with the SCS edit capability, write `BeginPlay` with `blueprint.edit_graph` (`Event BeginPlay` → `PrintString` with `InString="DreadmoorVR pak loaded"`, `Duration=10`). Expected: the reply says the Blueprint compiles.
- [ ] **Step 4: Create `PAL_DreadmoorVR`** in `/Game/DreadmoorVR/` with the rules above. Read it back and check `ChunkId` is 1.
- [ ] **Step 5: Delete the MCP smoke test** `/Game/Scratch/BP_McpSmokeTest` (ask Bob first; it's a destructive capability).
- [ ] **Step 6: Commit** `feat(pak): probe actor and chunk 1 label`

### Task 6: Cook script

**Files:**
- Create: `tools/cook.ps1`

**Interfaces:**
- Consumes: `list_container.py` (Task 4).
- Produces: `tools/cook.ps1` writes `build/pak/DreadmoorVR_P.utoc`, `.ucas` and `.pak`, and exits non-zero if the cook fails or any foreign path is in the container.

- [ ] **Step 1: Write it.** Run `RunUAT.bat BuildCookRun` from UE_5.6: `-project=<abs .uproject> -platform=Win64 -clientconfig=Shipping -build -cook -stage -pak -iostore -package -noP4 -utf8output -archive -archivedirectory=<repo>\build\stage`. Find `pakchunk1-Windows.{utoc,ucas,pak}` under the staged `Dreadmoor\Content\Paks`, copy them to `build/pak/` renamed `DreadmoorVR_P.*`, then run `python -I tools/re/list_container.py build/pak/DreadmoorVR_P.utoc --allow Dreadmoor/Content/DreadmoorVR/`. The editor must not have the project open while cooking: close it first, or have the script refuse if `UnrealEditor` is running with this project.
- [ ] **Step 2: Run it.** Expected: exit 0. The listing shows `BP_PakProbe` and `PAL_DreadmoorVR` and nothing else under `Content`. Send the cook log to `local-delegate` if it fails.
- [ ] **Step 3: Commit** `feat: cook script producing DreadmoorVR_P with a content check`

### Task 7: Pak loader and M1 (GATE)

**Files:**
- Create: `src/scripts/armsloader.lua`, `docs/testing/m1-checklist.md`
- Modify: `tools/deploy.ps1` (pak half: copy `build/pak/DreadmoorVR_P.*` to `~mods`, creating it; add those files to the manifest)
- Modify: `src/scripts/gameapi.lua` (create it here with just what the loader needs)

**Interfaces:**
- Produces: `armsloader.load_class(path: string) -> UClass|nil, method: string` tries, in order: (a) `uevr.api:find_uobject("BlueprintGeneratedClass " .. path)`; (b) `KismetSystemLibrary.LoadClassAsset_Blocking` on a soft class reference built with `KismetSystemLibrary.MakeSoftClassPath` and `Conv_SoftClassPathToSoftClassRef`; (c) returns nil. `method` names which one worked, for the log.
- Produces: `armsloader.spawn(class, transform) -> AActor|nil`, using `GameplayStatics.BeginDeferredActorSpawnFromClass` + `FinishSpawningActor` on the current world.
- Produces: `gameapi.local_pawn() -> UObject|nil`, `gameapi.world() -> UObject|nil`, `gameapi.class_chain(obj) -> {string}` (short class names, most-derived first).

- [ ] **Step 1: Write `armsloader.lua`** and the three `gameapi` functions. Only `class_chain` can be desk-tested: write `test_class_chain_walks_supers` in `tests/test_gameapi.lua` with a fake object whose `get_class():get_super()` chain is `BP_FishingController_C → DrdFishingControllerBase → Pawn → Actor → Object`. Expect `{"BP_FishingController_C","DrdFishingControllerBase","Pawn","Actor","Object"}`. Run it failing, implement, run it passing.
- [ ] **Step 2: Add an M1 hook in `main.lua`.** Two seconds after the first walking pawn appears, load `/Game/DreadmoorVR/BP_PakProbe.BP_PakProbe_C`, spawn it 150 cm in front of the pawn, and log the method used or the failure.
- [ ] **Step 3: Write `docs/testing/m1-checklist.md`.** Deploy, inject, walk in. Expected: the cube in front of you and `DreadmoorVR pak loaded` on screen. If neither: the log line says whether the pak mounted (UEVR log `LogPakFile` mount lines) and which load method failed.
- [ ] **Step 4: Deploy with** `tools/deploy.ps1`, **send Bob the checklist, stop.**
- [ ] **Step 5: Read his results.** Cube shows: commit `feat: pak loading proven (M1)`. Mounted but the load failed: write a small C++ UEVR plugin task into Plan 2 (StaticLoadClass from a plugin) and bring it to Bob. Did not mount: stop and bring options to Bob (spec M1).

### Task 8: Bridge skeleton (M2)

**Files:**
- Create: `src/scripts/modes.lua`, `pad.lua`, `config.lua`, `debug.lua`, `src/data/dreadmoorvr_config.lua`, `tests/test_modes.lua`, `test_pad.lua`, `test_config.lua`, `docs/testing/m2-checklist.md`
- Modify: `src/scripts/main.lua`, `src/scripts/gameapi.lua`
- Delete from deploy: `m0_probe.lua` and the M1 spawn hook

**Interfaces:**
- Produces `modes`:
  - `modes.classify(chain: {string}) -> "walking"|"fishing"|"crafting"|"boat"|"diving"|"unknown"`. The first match wins down the chain: `DrdPlayerCharacter` → walking, `DrdFishingControllerBase` → fishing, `BP_CraftController_C` → crafting, `DrdShipBase` → boat, `BP_DiverCharacter_C` → diving. Base-class names come from `gameapi.MODE_CLASSES`, the only place they appear.
  - `modes.new(handlers: {[mode]={enter=fn, exit=fn}}) -> tracker`; `tracker:update(mode)` calls the old mode's `exit` then the new mode's `enter`, only when the mode changes; `tracker.current` is the current mode.
- Produces `pad`:
  - `pad.press(button: string, on: boolean)`, `pad.hold_axis(axis: string, value: number|nil)` (nil releases), `pad.tap(button, frames: integer)`.
  - `pad.merge(real: {buttons=int, lt=int, rt=int, lx=int, ly=int, rx=int, ry=int}) -> merged` (pure, same shape). Button names map to XInput bits (`A`=0x1000, `B`=0x2000, `X`=0x4000, `Y`=0x8000, `LB`=0x0100, `RB`=0x0200, `Start`=0x0010, `Back`=0x0020, `DUp`=0x0001, `DDown`=0x0002, `DLeft`=0x0004, `DRight`=0x0008). `RT`/`LT` pressed means 255. Axes `LX`, `LY`, `RX`, `RY` take −1..1, scaled to ±32767.
  - `pad.end_frame()` advances taps.
  - `main.lua` calls `pad.merge` inside `on_xinput_get_state` and writes the result into the state.
- Produces `config`: `config.load(path) -> table, err|nil`; `config.get() -> table`; `config.reload_if_changed()` (checks the file's modified time once a second). On a parse error or a missing required key, keep the last good table and set `config.last_error`. Required keys for now: `readout = {enabled=boolean}`.
- Produces `debug`: `debug.line(key, value)` puts a line on the on-screen readout (UEVR ImGui overlay via `uevr.sdk.callbacks.on_draw_ui` or the in-world text the API supports; confirm in the API) and in `dreadmoorvr.log`.

- [ ] **Step 1: Write the failing tests**:
  - `test_modes_matches_base_class`: `classify({"BP_FishingController_Tutorial_C","BP_FishingController_C","DrdFishingControllerBase","Pawn"}) == "fishing"`.
  - `test_modes_unknown_class`: `classify({"BP_MenuPawn_C","Pawn","Actor"}) == "unknown"`.
  - `test_modes_switch_runs_exit_once`: in the sequence walking, walking, fishing, fishing, walking, `exit` for walking is called once before fishing's `enter`, and fishing's `exit` is called once.
  - `test_pad_merge_or_buttons`: real `A` plus virtual `A` gives `A` set, real `B` plus virtual nothing gives `B` set.
  - `test_pad_merge_trigger`: `pad.press("RT", true)` with real `rt=0` gives `rt=255`.
  - `test_pad_merge_axis_override_and_release`: `hold_axis("LX", -1)` with real `lx=12000` gives `-32767`; after `hold_axis("LX", nil)` it gives `12000`.
  - `test_pad_tap_lasts_n_frames`: `tap("X", 2)` sets X for exactly two `end_frame` calls.
  - `test_config_bad_reload_keeps_last_good`: load a good file, overwrite it with `return {`, reload; `get().readout.enabled` is unchanged and `last_error` is set.
  - `test_config_missing_key_rejected`: a file returning `{}` keeps the last good table and sets the error.
- [ ] **Step 2: Run** `tools/bin/lua54/lua54.exe tests/run.lua`. Expected: these fail, with module-not-found or assert errors.
- [ ] **Step 3: Implement** `modes.lua`, `pad.lua`, `config.lua` (load with `load(text, name, "t", {})` and an empty environment), and `gameapi.MODE_CLASSES`.
- [ ] **Step 4: Run the tests again.** Expected: all pass, `0 failed`.
- [ ] **Step 5: Wire up `main.lua`**: on every tick, `modes` gets the classified pawn chain; the readout shows the mode, the pawn class and `config.last_error`; `config.reload_if_changed()` runs; there's a pad hook. Write `debug.lua`. Remove the M1 spawn hook, and drop `m0_probe.lua` from the default deploy.
- [ ] **Step 6: Write `docs/testing/m2-checklist.md`.** Walk → fish → walk → bench → walk → boat → walk, and the readout names each mode correctly. Edit `dreadmoorvr_config.lua` to `readout.enabled=false` while playing: it hides within 2 s. Break the file: the readout shows the error and stays. Fix it: the error clears.
- [ ] **Step 7: Deploy, send Bob the checklist, stop.** After a pass, commit `feat: bridge skeleton with modes, pad, config, readout (M2)`.

---

## After this plan

Write Plan 2 (arms, M3–M4) from the M0 results. It needs the mesh and skeleton paths, the bone names, the `.usmap` and the load method M1 found. Plans 3 and 4 cover fishing gestures plus the bench (M5–M6) and the hook gun plus tuning (M7–M8). Each one is written once the plan before it has landed, so every interface comes from tested facts.
