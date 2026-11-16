# Frame Input Plugin, Phase 2 (Passive Telemetry) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Read-only input telemetry that produces a diagnostic report during normal play.
It covers per-hand identity, action edges, analogue values, tracking validity, the gamepad
the game receives and the physical → Xbox mapping, with no manual button runs.

**Architecture:**
- The pure logic goes in `plugin/src/core.hpp` and is desk-tested:
  - config parsing
  - an analogue filter
  - digital and analogue budgets that are kept separate
  - a mapping aggregator
- `Plugin.cpp` wires it to OpenVR reads, `on_xinput_get_state` (which runs after UEVR's VR
  mapping, so it sees the game's pad) and a report file.

**Spec:** `docs/superpowers/specs/2026-11-16-frame-input-plugin-design.md` (Phase 2), plus
Bob's directive "Phase 2: Passive input telemetry".

## Global Constraints

- Read only:
  - no `UpdateActionState`
  - no binding, manifest or config changes
  - never modify the gamepad state (observe only)
- Edge-triggered logging, configurable sampling, no per-frame dumps.
- Digital edges must never be starved by analogue noise (the Phase 1 flaw).
- Rollback stays `deploy.ps1 -RemovePlugin`, and the renderer and `config.txt` stay
  untouched.
- No Phase 3: no Menu/View conversion, no mapping changes, no skeletal interaction.

## Review Focus

1. **Stick jitter around zero:** must not flood the log. Covered by the `analog_step` test.
2. **Missing or garbage config file:** fall back to defaults. Covered by the `config_defaults`
   test.
3. **Two buttons at once:** must not be recorded as a single-button mapping. Covered by the
   `mapping_multi` test.
4. **A cap is reached:** drops are counted per budget and appear in the report. Covered by the
   `budgets_separate` test.
5. **A report write fails** (folder locked): log it once and keep running. Handled in
   `write_report`.

---

### Task 1: Core additions and tests

**Interfaces (`core.hpp`, namespace `dvr`):**
- `struct TelemetryConfig { float analog_step=0.25f; int analog_min_ms=250; size_t digital_cap=3000; size_t analog_cap=600; int report_s=30; };`
- `TelemetryConfig parse_config(std::string_view text)`: `key=value` lines; unknown keys and
  bad values are ignored.
- `class AnalogFilter { public: AnalogFilter(float step, int min_ms); std::optional<float> feed(const std::string& key, float v, int64_t now_ms); };`
  Quantises to `step`. It emits when the quantised value changes and at least `min_ms` has
  passed since the key's last emit, except that a change to or from 0 always emits.
- `class MapAggregator { public: void observe(const std::vector<std::string>& down, uint16_t pad); std::string summary() const; };`
  When exactly one action is down and the pad is non-zero, it counts `action->0xPAD`.
- Two `EdgeLog` instances: digital (`digital_cap`) and analogue (`analog_cap`).

- [ ] Tests in `plugin/tests/test_core.cpp`:
  - `config_defaults`: `parse_config("")` gives defaults, and `parse_config("analog_step=x\nfoo=1")` gives defaults.
  - `config_values`: `"analog_step=0.5\nanalog_min_ms=100\nreport_s=10"` gives 0.5, 100 and 10.
  - `analog_step`: with step 0.25 and min 250, feeding 0.01 then 0.02 gives nothing, then
    0.30 gives 0.25, then 0.32 within 100 ms gives nothing, then 0.0 at once gives 0.0
    (to-zero always emits).
  - `mapping_multi`: `{"X@R"}` with 0x4000, twice, plus `{"A@R","X@R"}` with 0x5000, gives
    the summary `X@R->0x4000 x2`.
  - `budgets_separate`: filling the analogue `EdgeLog(2)` doesn't stop the digital
    `EdgeLog(2)` logging.
- [ ] Watch them fail, implement, watch them pass, then commit.

### Task 2: Plugin telemetry and report

- [ ] Read `<profile>\dreadmoorvr_telemetry.txt` at load (it's optional) and log the
  effective config.
- [ ] Each tick:
  - digital actions → digital `EdgeLog`
  - vector1 and vector2 → `AnalogFilter`, then the analogue `EdgeLog`
  - skeleton level edges
  - tracking validity: `GetPoseActionDataRelativeToNow(Pose, TrackingUniverseStanding, 0, …, source)`,
    logging `bPoseIsValid` and `eTrackingResult` edges per hand
- [ ] Every log line carries a millisecond timestamp, the hand (L/R) and the device index.
- [ ] `on_xinput_get_state`: log pad-button edges (`pad=0xNNNN`) and feed `MapAggregator`
  with the digital actions currently down.
- [ ] Every `report_s` seconds, and on unload, write
  `<profile>\dreadmoorvr_input_report.txt`:
  - config
  - hand identities
  - per-action edge counts
  - the mapping summary
  - pose-valid percentage per hand
  - drops per budget
  - UEVR's `is_hmd_active` and `is_using_controllers` time percentages

  Write it to a temporary file, then rename it into place.
- [ ] Build, desk test, deploy (`-Probe`), confirm `config.txt` is unchanged by hash, commit.

### Task 3: Runtime verification

- [ ] Bob plays normally for a few minutes.
- [ ] Collect the report and log lines into `docs/research/2026-11-16-frame-plugin-phase2.md`.
  State plainly which mappings were observed and which weren't exercised. Commit, then stop
  before Phase 3.
