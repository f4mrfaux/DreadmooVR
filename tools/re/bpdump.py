"""Dump cooked Blueprint packages to readable text.

usage: bpdump.py <out_dir> <name-substring> [<name-substring> ...]

Each matching .uasset becomes <out_dir>/<basename>.txt containing the export table, a
heuristic list of names/objects referenced by data-only exports, and disassembled
function bytecode.
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cfg  # noqa: E402
import kismet  # noqa: E402
import zen  # noqa: E402

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_ .:\-]{1,80}$")


def refs_in_export(pkg, data):
    """Heuristic: names and object references that appear in a data-only export, in order."""
    out, seen = [], set()
    n_names, n_imp, n_exp = len(pkg.names), len(pkg.imports), len(pkg.exports)
    i = 0
    while i + 4 <= len(data):
        v = struct.unpack_from("<i", data, i)[0]
        hit = None
        if i + 8 <= len(data) and 0 < v < n_names and struct.unpack_from("<I", data, i + 4)[0] == 0:
            nm = pkg.names[v]
            if not nm.startswith("/") and IDENT.match(nm):
                hit = ("name", nm, 8)
        if hit is None and -n_imp <= v < 0:
            r = pkg.obj(v, short=False)
            if not r.startswith("<") and v < -1 or (v == -1 and False):
                hit = ("obj", r, 4)
        if hit is None and 0 < v <= n_exp and v > 2:
            hit = ("exp", pkg.exports[v - 1].name, 4)
        if hit:
            key = hit[:2]
            if key not in seen:
                seen.add(key)
                out.append(f"{hit[0]}:{hit[1]}")
            i += hit[2]
        else:
            i += 1
    return out


def floats_in_export(data):
    vals = []
    for i in range(0, len(data) - 3):
        f = struct.unpack_from("<f", data, i)[0]
        if f == f and 0.01 <= abs(f) <= 100000 and abs(f * 1000 - round(f * 1000)) < 1e-3:
            vals.append((i, f))
    return vals


def dump_package(ctx, path, out_dir, with_data=True):
    pkg = ctx.load(path)
    lines = [f"# {pkg.name}", f"# file: {path}", ""]
    deps = sorted(p for p in pkg.imported_packages if p.startswith("/Game/") or not p.startswith("/Script"))
    lines.append(f"## imported packages ({len(deps)})")
    lines += [f"  {d}" for d in deps]
    lines.append("")
    lines.append(f"## exports ({len(pkg.exports)})")
    for e in pkg.exports:
        cls = pkg.class_of(e)
        if cls == "Function":
            continue
        sup = pkg.resolve(e.sup, True)
        extra = f" super={sup}" if sup != "None" else ""
        lines.append(f"  [{e.index}] {e.name} : {cls} (outer {pkg.resolve(e.outer, True)}){extra} size={e.size}")
        if with_data and e.size <= 6000 and cls != "BlueprintGeneratedClass":
            refs = refs_in_export(pkg, pkg.export_bytes(e))
            if refs:
                lines.append("        refs: " + ", ".join(refs[:60]))
    lines.append("")
    for e in pkg.exports:
        if pkg.class_of(e) != "Function":
            continue
        try:
            st, flags = kismet.disassemble(pkg, e)
        except Exception as ex:  # keep going; note the failure
            lines.append(f"## function {e.name}  !! disassembly failed: {ex}")
            lines.append("")
            continue
        if st is None:
            lines.append(f"## function {e.name}  (no script)")
            lines.append("")
            continue
        lines.append(f"## function {e.name}  flags=0x{flags:08X}")
        for off, s in st:
            lines.append(f"  L{off:04X}: {s}")
        lines.append("")
    base = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(out_dir, base + ".txt")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return out, len(lines)


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    store, glob, _ = cfg.open_stores()
    ctx = zen.Context(store, glob)
    for needle in sys.argv[2:]:
        exact = needle.endswith("$")
        n = needle.rstrip("$").lower()
        matches = [p for p in store.files if p.endswith(".uasset") and
                   (os.path.splitext(os.path.basename(p))[0].lower() == n if exact
                    else n in os.path.basename(p).lower())]
        if not matches:
            print(f"!! no match: {needle}")
        for m in sorted(matches):
            try:
                out, n_lines = dump_package(ctx, m, out_dir)
                print(f"{n_lines:6d} lines  {os.path.basename(out)}  <- {m}")
            except Exception as ex:
                print(f"!! failed {m}: {ex}")


if __name__ == "__main__":
    main()
