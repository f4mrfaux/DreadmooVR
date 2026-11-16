"""Overnight map of Dreadmoor's Blueprints: dump each one, then have the local model summarise it.

    python -I -X utf8 tools/re/map_game.py [--out build/map] [--limit N] [--no-ai]

Resumable: a Blueprint whose dump and summary already exist is skipped, so the job can be
stopped and restarted at any time. The most VR-relevant folders go first.

Outputs (all under --out, git-ignored):
  dumps/<container path>.txt     bpdump text for each Blueprint
  summaries/<container path>.json  the model's structured summary
  index.jsonl                    one line per Blueprint, appended as each finishes
  progress.log                   timestamps, failures, rate

The summaries come from game content and a weaker local model: they are leads to check
against the dumps, not facts.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpdump  # noqa: E402
import cfg  # noqa: E402
import zen  # noqa: E402

OLLAMA = os.environ.get("DELEGATE_BASE_URL", "http://127.0.0.1:11434")
MODEL = "qwen3:30b-a3b-instruct-2507-q4_K_M"
MAX_CHARS = 40000          # per model call; bigger dumps are split and merged
NAME_RE = re.compile(r"/(BP|GA|ABP|WBP|STT|STE|GE|AC|BPI|BTT|BTS|BTD|GAS|CR|AM|BFL|BPC)_[^/]*\.uasset$")

# Only Blueprints that matter to the VR mod: hands and held tools, fishing, the bench, hook
# gun, harpoon/knife, pawns and their cameras, input, prompts, haptics, carry/attach. Matched
# case-insensitively against the whole container path.
RELEVANT = re.compile(
    r"fish|hook|handtool|hand_|craft|player|character|interact|qte|ship|boat|steer|diver|diving|"
    r"harpoon|knife|sickle|equipment|camera|input|feedback|haptic|crosshair|aim|carry|grab|"
    r"pickup|lure|reel|rod|float|bench|tool|weapon|mesh_?visib|prompt|hud", re.I)
NOT_RELEVANT = re.compile(r"/(Audio|Sound|SFX|Environment|Weather|AI|NPC|Quest|Dialog|Narrative|"
                          r"Map|Level|Landscape|Foliage|Water/Ocean|Localization|Achievement|Save|"
                          r"Art|QuestFeatures|UpgradeDock|WaterBoss|Tutorial|FishGrinder|"
                          r"CraftingMaterials|Modules|Recipes|Descriptions|Liligator|Fishtrader[^/]*)/"
                          r"|/Animations/(?!Characters/)", re.I)

# Folders matched in this order first; everything else after.
PRIORITY = [
    "Core/Features/Fishing", "Core/Features/Hook", "Core/Features/HandTool", "Core/Features/Craft",
    "Core/Player", "Core/Character", "Core/Features/Interaction", "Core/Features/QTE",
    "Core/Features/Ship", "Core/Features/Boat", "Core/Features/Diving", "Core/Features/Harpoon",
    "Core/Features", "Core/GAS", "Core/Input", "Core/UI", "UI", "Animations", "Core",
]

PROMPT = """You are mapping a shipped Unreal Engine 5.6 game (Dreadmoor) for a VR mod. Below is a
disassembled Blueprint: exports, functions as pseudo-code (one line per bytecode statement), and
heuristic object references. Summarise it as JSON only, no prose, with these keys:
  "purpose": one or two sentences, what this Blueprint is for in the game.
  "parent": parent class if visible, else null.
  "components": component names and classes it owns.
  "functions": list of {"name", "does"} for its important functions/events (max 15).
  "inputs": input actions (IA_*), input mapping contexts, ability input tasks (WaitInputPress etc.).
  "tags": gameplay tags referenced.
  "calls_out": notable functions it calls on other classes (Class.Function).
  "spawns": classes it spawns or adds.
  "state": key variables that hold game state (name and what it means).
  "vr_notes": anything a VR mod would care about: camera or view control, control rotation,
              aim traces, hand/socket attachment, montages, haptics/controller feedback, UI prompts,
              mouse-cursor logic. Empty list if none.
Only state what the text shows. Cite line labels like L0A61 where useful. Unknown = null.

Blueprint: {path}
---
{text}
"""

MERGE_PROMPT = """Merge these partial JSON summaries of one Blueprint ({path}) into one JSON object
with the same keys (purpose, parent, components, functions, inputs, tags, calls_out, spawns,
state, vr_notes). Deduplicate; keep at most 15 functions. JSON only.
---
{parts}
"""


def ollama(prompt, timeout=2700):
    body = json.dumps({
        "model": MODEL, "prompt": prompt, "stream": False, "format": "json",
        "options": {"temperature": 0, "num_ctx": 32768},
    }).encode()
    req = urllib.request.Request(OLLAMA + "/api/generate", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())["response"]


def summarise(path, text):
    chunks = [text[i:i + MAX_CHARS] for i in range(0, len(text), MAX_CHARS)] or [""]
    parts = []
    for c in chunks:
        raw = ollama(PROMPT.replace("{path}", path).replace("{text}", c))
        parts.append(json.loads(raw))
    if len(parts) == 1:
        return parts[0]
    raw = ollama(MERGE_PROMPT.replace("{path}", path).replace("{parts}", json.dumps(parts)[:MAX_CHARS]))
    return json.loads(raw)


def priority(path):
    for i, p in enumerate(PRIORITY):
        if "/" + p + "/" in path:
            return i
    return len(PRIORITY)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join("build", "map"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--no-ai", action="store_true")
    a = ap.parse_args()
    dumps = os.path.join(a.out, "dumps")
    sums = os.path.join(a.out, "summaries")
    os.makedirs(dumps, exist_ok=True)
    os.makedirs(sums, exist_ok=True)
    plog = open(os.path.join(a.out, "progress.log"), "a", encoding="utf-8")
    index = open(os.path.join(a.out, "index.jsonl"), "a", encoding="utf-8")

    def log(msg):
        line = time.strftime("%H:%M:%S ") + msg
        print(line, flush=True)
        plog.write(line + "\n")
        plog.flush()

    store, glob, _ = cfg.open_stores()
    ctx = zen.Context(store, glob)
    todo = sorted((p for p in store.files if p.startswith("Dreadmoor/Content/Dreadmoor/") and NAME_RE.search(p)
                   and RELEVANT.search(p) and not NOT_RELEVANT.search(p)),
                  key=lambda p: (priority(p), p))
    if a.limit:
        todo = todo[:a.limit]
    log(f"start: {len(todo)} blueprints, ai={'off' if a.no_ai else MODEL}")

    done = 0
    t_start = time.time()
    for path in todo:
        rel = path[len("Dreadmoor/Content/"):-len(".uasset")]
        sub = os.path.dirname(rel)
        dump_dir = os.path.join(dumps, sub)
        sum_path = os.path.join(sums, rel + ".json")
        dump_path = os.path.join(dump_dir, os.path.basename(rel) + ".txt")
        if os.path.exists(sum_path) or (a.no_ai and os.path.exists(dump_path)):
            continue
        try:
            os.makedirs(dump_dir, exist_ok=True)
            if not os.path.exists(dump_path):
                bpdump.dump_package(ctx, path, dump_dir)
            if a.no_ai:
                done += 1
                continue
            text = open(dump_path, encoding="utf-8").read()
            s = summarise(path, text)
            os.makedirs(os.path.dirname(sum_path), exist_ok=True)
            with open(sum_path, "w", encoding="utf-8") as f:
                json.dump(s, f, indent=1)
            index.write(json.dumps({"path": path, "lines": text.count("\n"),
                                    "purpose": s.get("purpose") if isinstance(s, dict) else None}) + "\n")
            index.flush()
            done += 1
            rate = (time.time() - t_start) / done
            log(f"ok {done}/{len(todo)} {rel} ({rate:.0f}s each)")
        except Exception as ex:  # keep going; failures are listed in the log
            log(f"FAIL {rel}: {type(ex).__name__}: {ex}")
            time.sleep(5)
    log(f"finished: {done} done this run")


if __name__ == "__main__":
    main()
