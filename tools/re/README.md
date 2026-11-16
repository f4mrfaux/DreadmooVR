# Dreadmoor reverse-engineering scripts

Read-only tools for looking inside the game's cooked content. They never modify the install
and never run the game. Python 3.13, standard library only.

Run them with `python -I` so Python ignores the current directory and environment.

## What each one does

| Script | Purpose |
|---|---|
| `cfg.py` | Paths to the game install and to an Oodle runtime DLL |
| `iostore.py` | Reads the `.utoc` / `.ucas` container and decompresses chunks |
| `zen.py` | Parses UE 5.6 cooked packages: names, imports, exports, cross-package references |
| `kismet.py` | Disassembles Blueprint bytecode into one pseudo-code line per statement |
| `bpdump.py` | Writes a readable text dump of one or more Blueprints |
| `find_assets.py` | Lists container paths matching a regular expression |
| `imc.py` | Pairs input actions with keys inside mapping contexts (heuristic) |

## Usage

Find assets:

```bash
python -I tools/re/find_assets.py "Features/Fishing/"
```

Dump Blueprints (a trailing `$` means exact name, otherwise substring):

```bash
python -I tools/re/bpdump.py docs/research/bp-dumps "BP_FishingController$" "WBP_QTE_"
```

Show which keys drive which actions:

```bash
python -I tools/re/imc.py "IMC_Fishing$"
```

## Things to know

- **Oodle.** The containers are Oodle-compressed. `cfg.py` loads the Oodle runtime that ships
  with Armored Core VI or Elden Ring from the local Steam library. If neither is installed,
  point `OODLE_CANDIDATES` at any `oo2core_*_win64.dll` version 6 or newer.
- **Reading a dump.** Labels like `L0A61` are in-memory code offsets, so `goto L0A61` lines up.
  An event stub such as `InpActEvt_IA_Fishing_Cast_...` calls `ExecuteUbergraph_X(1303)`: that
  number is decimal, so look for label `L0517` in the ubergraph function.
- **`refs:` lines are a heuristic.** Cooked default values cannot be parsed without a mappings
  file, so `bpdump.py` lists names and object references it recognises in the raw bytes. They
  are good for "what is attached to what" and unreliable for small exports.
- **After a game update,** rerun the dumps. Export offsets and layouts are version-specific:
  these scripts are written for UE 5.6 and were checked against build 26670657.
- **Unsupported:** encrypted containers, versioned packages, default-value decoding.
