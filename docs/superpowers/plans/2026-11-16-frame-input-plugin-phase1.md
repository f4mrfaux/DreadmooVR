# Frame Input Plugin, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A minimal `DreadmoorVR.dll` UEVR plugin that loads in nightly 01143. It lists
every action in UEVR's manifest with its type, handle and Frame binding origin. It captures a
live controller state change passively and delivers a C++ → Lua event, all without
disturbing rendering.

**Architecture:**
- The plugin uses UEVR's public plugin SDK 2.39 for loading, logging, ticks and Lua events.
- It uses OpenVR's `IVRInput` read-only for action data, resolving `VR_GetGenericInterface`
  from the `openvr_api.dll` UEVR already loaded.
- It never calls `UpdateActionState` or `SetActionManifestPath`, and never touches bindings.
- Pure logic (manifest parsing, edge detection) lives in a header-only unit with a desk test.

**Tech Stack:** C++20, CMake, VS 2022 x64; UEVR plugin headers (MIT) and OpenVR headers (BSD)
vendored in `plugin/third_party/`.

**Spec:** `docs/superpowers/specs/2026-11-16-frame-input-plugin-design.md`

## Global Constraints

- Don't modify SteamVR driver files, patch the nightly or replace its renderer.
- Don't register a competing action manifest or replace UEVR's action sets.
- Read only: no `UpdateActionState`, no binding changes, no writes to game objects.
- Edge-triggered logging only, never per-frame dumps.
- Nothing counts as working until it's verified in the running game, and the evidence is
  collected passively with no scripted button sequences.
- Keep a reversible baseline: the plugin is one file in `<profile>\plugins\`, and removing it
  restores today's state.

## Review Focus

1. **Plugin loaded under OpenXR, or before OpenVR is ready:** it must log "not OpenVR" or
   "waiting" and do nothing else, never crash. Covered by Task 2's `runtime_gate` test.
2. **An action declared in the manifest but unbound for `frame_controller`:** list it as
   "unbound", never treat it as an error. Task 2's origins log.
3. **`actions.json` missing or malformed:** log the reason and still run the SDK-level
   checks. Task 1's `parse_manifest_bad_input` test.
4. **A chattering button:** the edge detector logs each change once, and the log is capped.
   Task 1's `edge_cap` test.
5. **Script reset or plugin unload while ticking:** no dangling Lua callback or handle use.
   Task 3 clears its state in `on_script_reset` and on shutdown.

---

### Task 1: Pure core and desk test

**Files:**
- Create: `plugin/CMakeLists.txt`, `plugin/src/core.hpp`, `plugin/tests/test_core.cpp`
- Create: `plugin/third_party/uevr/{API.h,API.hpp,Plugin.hpp,LICENSE}`, copied from
  `C:\Users\Bob\source\UEVR-frame` at commit 4ee5c6b
- Create: `plugin/third_party/openvr/{openvr.h,LICENSE}`, from
  `UEVR-frame/dependencies/openvr/headers`

**Interfaces:**
- Produces, in `core.hpp`, namespace `dvr`:
  - `struct ActionDecl { std::string name; std::string type; };`
  - `std::vector<ActionDecl> parse_manifest(std::string_view json)`: returns an empty
    vector on malformed input.
  - `class EdgeLog { public: explicit EdgeLog(size_t cap); std::optional<std::string>
    change(const std::string& key, const std::string& value); size_t count() const; };`
  - `bool runtime_gate(bool is_openvr, bool runtime_ready)`

- [ ] **Step 1: Write `plugin/tests/test_core.cpp`** (plain `assert`, `main` returns 0):
  - `parse_manifest_finds_actions`: a two-action sample with
    `{"name":"/actions/default/in/Squeeze","type":"vector1"}` gives 2 entries, and
    entry 0 is Squeeze, vector1.
  - `parse_manifest_bad_input`: `"{"` and `""` each give an empty vector.
  - `edge_cap`: with `EdgeLog(3)`, `change("A@R","1")` returns `"A@R=1"`; the same value
    again returns `nullopt`; after three distinct changes the fourth returns `nullopt`.
  - `runtime_gate`: `(true,true)` is true; `(false,true)` and `(true,false)` are false.
- [ ] **Step 2: Build and run the test. Expected:** it fails to compile because `core.hpp`
  doesn't exist yet.
  `cmake -S plugin -B build/plugin -G "Visual Studio 17 2022" -A x64 && cmake --build build/plugin --config Release && build/plugin/Release/test_core.exe`
- [ ] **Step 3: Implement `core.hpp`.** `parse_manifest` scans the `"actions"` array for
  `"name"` and `"type"` string pairs, with no JSON library. `EdgeLog` keeps the last value
  per key and a count that stops at the cap.
- [ ] **Step 4: Run it again. Expected:** `test_core.exe` exits with 0.
- [ ] **Step 5: Commit**: `feat(plugin): pure core, manifest parse and edge log`.

### Task 2: Plugin load, runtime gate and action inventory

**Files:**
- Create: `plugin/src/Plugin.cpp`, and add a `DreadmoorVR` SHARED target to
  `plugin/CMakeLists.txt`
- Modify: `plugin/tests/test_core.cpp`, only if the gate changes

**Interfaces:**
- Consumes: `parse_manifest`, `runtime_gate`.
- Produces:
  - Exports `uevr_plugin_required_version` (2.39.0) and `uevr_plugin_initialize`.
  - A log line prefix `[DreadmoorVR.dll]`.
  - The Lua event `dreadmoorvr_plugin` with data `loaded`.

- [ ] **Step 1: Implement initialize.**
  - Store `param`.
  - Log the version, the runtime (`vr->is_openvr()` / `is_openxr()`) and the persistent dir.
  - Register `on_pre_engine_tick`.
  - Call `dispatch_lua_event("dreadmoorvr_plugin", "loaded")`.
- [ ] **Step 2: On the first tick where `runtime_gate(is_openvr, vr->is_runtime_ready())`
  holds:**
  - Get `IVRInput` through `GetProcAddress(GetModuleHandleA("openvr_api.dll"), "VR_GetGenericInterface")`
    with `vr::IVRInput_Version`.
  - Read `<persistent>\actions.json` and run `parse_manifest` on it.
  - For each action, log `name`, `type`, the handle from `vr->get_action_handle`, and for
    `/user/hand/left` and `/user/hand/right`, `GetActionOrigins` → `GetOriginLocalizedName`,
    or `unbound`.
  - Log whether `VR_GetGenericInterface` succeeded.
- [ ] **Step 3: Build. Expected:** `build/plugin/Release/DreadmoorVR.dll` exists and its
  export table has both `uevr_plugin_*` symbols (`dumpbin /exports`).
- [ ] **Step 4: Commit**: `feat(plugin): load, runtime gate, action inventory`.

### Task 3: Passive state capture and the Lua side

**Files:**
- Modify: `plugin/src/Plugin.cpp`, `src/scripts/m0_probe.lua`, `tools/deploy.ps1`

**Interfaces:**
- Consumes: `EdgeLog`, and the inventory from Task 2.
- Produces:
  - The Lua event `dreadmoorvr_input` with data `<Action>@<L|R>=<value>`, sent on the first
    change only.
  - Probe log lines `plugin=<event>:<data>`.

- [ ] **Step 1: Each tick after inventory, read the actions on both sources without calling
  `UpdateActionState`:**
  - boolean actions through `GetDigitalActionData` (`bState`, `bActive`)
  - vector1 and vector2 through `GetAnalogActionData` (x rounded to 0.1)
  - skeleton through `GetSkeletalTrackingLevel`
  - Feed `EdgeLog(200)` and log each returned line. On the first change, dispatch
    `dreadmoorvr_input`.
- [ ] **Step 2: Lua side.** `m0_probe.lua` registers
  `uevr.sdk.callbacks.on_lua_event(function(name, data) ... end)` and logs
  `plugin=name:data`.
- [ ] **Step 3: Deploy.** `deploy.ps1` copies `build/plugin/Release/DreadmoorVR.dll` to
  `<profile>\plugins\DreadmoorVR.dll` when it exists.
- [ ] **Step 4: Build, desk test and deploy. Expected:** `test_core.exe` exits 0, and the
  DLL is in `plugins\`.
- [ ] **Step 5: Commit**: `feat(plugin): passive action capture, Lua event, deploy`.

### Task 4: Runtime verification (Phase 1 gate)

- [ ] **Step 1:** Bob launches and injects the nightly as usual, then plays normally with
  passthrough off. No button sequence.
- [ ] **Step 2:** Collect the evidence from UEVR's `log.txt` and record it in
  `docs/research/2026-11-16-frame-plugin-phase1.md`:
  1. `[DreadmoorVR.dll]` load and runtime lines
  2. the full action inventory with types, handles and Frame origins
  3. at least one live `Action@side=value` change
  4. the probe's `plugin=dreadmoorvr_plugin:loaded` and `plugin=dreadmoorvr_input:...`
  5. Bob's one-word confirmation that the 3D scene renders
- [ ] **Step 3:** Answer validation items 1–6 from the evidence, writing "unknown" where the
  evidence doesn't settle one. Commit, then stop for Bob's authorisation of Phase 2.
