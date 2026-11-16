"""List the files in an IoStore container and flag asset paths outside an allowed prefix.

Used by tools/cook.ps1 to make sure the mod pak carries only /Game/DreadmoorVR/ assets, so a
stand-in for a game asset can never overwrite the real one.

    python -I tools/re/list_container.py <file.utoc> [--allow Dreadmoor/Content/DreadmoorVR/]

Exit code 1 if any asset path falls outside --allow.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from iostore import IoStore  # noqa: E402

ASSET_EXTS = (".uasset", ".umap", ".uexp", ".ubulk", ".uptnl")


def full_path(mount, rel):
    """Container entries are relative to its mount point; make them project-relative."""
    prefix = mount
    while prefix.startswith("../"):
        prefix = prefix[3:]
    return prefix + rel


def list_files(utoc_path):
    # Reading the directory index needs no decompression, so no Oodle decoder is required.
    store = IoStore(utoc_path, None)
    try:
        mount = getattr(store, "mount", "../../../")
        return sorted(full_path(mount, p) for p in store.files)
    finally:
        store._ucas.close()


def foreign_paths(paths, allowed_prefix):
    return [p for p in paths if p.lower().endswith(ASSET_EXTS) and not p.startswith(allowed_prefix)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("utoc")
    ap.add_argument("--allow", default="Dreadmoor/Content/DreadmoorVR/")
    a = ap.parse_args()
    files = list_files(a.utoc)
    for f in files:
        print(f)
    bad = foreign_paths(files, a.allow)
    print(f"## {len(files)} files, {len(bad)} outside {a.allow}")
    for b in bad:
        print(f"FOREIGN {b}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
