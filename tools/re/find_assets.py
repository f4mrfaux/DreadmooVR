"""List container file paths matching a case-insensitive regular expression.

usage: find_assets.py <regex> [<regex> ...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cfg  # noqa: E402


def main():
    store, _glob, _ = cfg.open_stores()
    for pat in sys.argv[1:]:
        rx = re.compile(pat, re.I)
        hits = sorted(p for p in store.files if rx.search(p) and p.endswith((".uasset", ".umap")))
        print(f"## {pat}  ({len(hits)})")
        for h in hits:
            print("  " + h)


if __name__ == "__main__":
    main()
