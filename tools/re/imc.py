"""Heuristic dump of Enhanced Input mapping contexts: which key drives which action.

The property layout of cooked assets is not available without a mappings file, so this
walks the serialized bytes of the mapping-context export and pairs each input-action
reference with the key name that follows it. Modifier and trigger objects referenced just
before an action are attributed to that mapping. Treat the output as strong evidence, not
as a parsed structure.

usage: imc.py <IMC name substring> [...]
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cfg  # noqa: E402
import zen  # noqa: E402

KEY = re.compile(
    r"^(Gamepad_\w+|\w*Mouse\w*|[A-Z]|Zero|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|SpaceBar|Tab|Escape|Enter|"
    r"(Left|Right)(Shift|Control|Alt|Command)|F\d+|Up|Down|Left|Right|BackSpace|Delete|Insert|Home|End|PageUp|PageDown|"
    r"CapsLock|Tilde|Comma|Period|Slash|Semicolon|Hyphen|Equals|Apostrophe|LeftBracket|RightBracket|Backslash|"
    r"NumPad\w+|Add|Subtract|Multiply|Divide|PS5_\w+|PS4_\w+|Steam_\w+|AnyKey)$")


def dump(ctx, path):
    pkg = ctx.load(path)
    main = next((e for e in pkg.exports if pkg.class_of(e) == "InputMappingContext"), None)
    if main is None:
        print(f"!! no InputMappingContext export in {path}")
        return
    data = pkg.export_bytes(main)
    n_imp, n_exp, n_names = len(pkg.imports), len(pkg.exports), len(pkg.names)
    action, pending, rows = None, [], []
    i = 0
    while i + 4 <= len(data):
        v = struct.unpack_from("<i", data, i)[0]
        if -n_imp <= v < 0:
            r = pkg.obj(v, short=False)
            if "/IA_" in r or r.rsplit(".", 1)[-1].startswith("IA_"):
                action = r.rsplit(".", 1)[-1]
                i += 4
                continue
        if 0 < v <= n_exp:
            e = pkg.exports[v - 1]
            cls = pkg.class_of(e)
            if cls.startswith(("InputModifier", "InputTrigger", "DrdInputModifier", "DrdInputTrigger")):
                pending.append(cls.replace("InputModifier", "Mod:").replace("InputTrigger", "Trig:"))
                i += 4
                continue
        if i + 8 <= len(data) and 0 < v < n_names and struct.unpack_from("<I", data, i + 4)[0] == 0:
            nm = pkg.names[v]
            # Very low name indices collide with small integers in the data; skip them.
            # A single-letter name at a very low index is usually a small integer, not a key.
            if KEY.match(nm) and action and (v >= 12 or len(nm) > 1):
                rows.append((action, nm, pending))
                pending = []
                i += 8
                continue
        i += 1
    print(f"## {pkg.name.rsplit('/', 1)[-1]}  ({len(rows)} mappings)")
    by_action = {}
    verbose = os.environ.get("IMC_VERBOSE")
    for a, k, mods in rows:
        label = k + (f" [{', '.join(sorted(set(mods)))}]" if mods and verbose else "")
        if label not in by_action.setdefault(a, []):
            by_action[a].append(label)
    for a in sorted(by_action):
        print(f"  {a:34s} <- " + " | ".join(by_action[a]))


def main():
    store, glob, _ = cfg.open_stores()
    ctx = zen.Context(store, glob)
    for needle in sys.argv[1:]:
        exact = needle.endswith("$")
        n = needle.rstrip("$").lower()
        for p in sorted(store.files):
            base = os.path.splitext(os.path.basename(p))[0].lower()
            if p.endswith(".uasset") and (base == n if exact else n in base):
                try:
                    dump(ctx, p)
                except Exception as ex:
                    print(f"!! {p}: {ex}")


if __name__ == "__main__":
    main()
