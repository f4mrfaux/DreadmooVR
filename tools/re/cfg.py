"""Shared paths for the Dreadmoor analysis scripts."""
import os

GAME = r"D:\SteamLibrary\steamapps\common\DREADMOOR"
PAKS = os.path.join(GAME, "Dreadmoor", "Content", "Paks")
UTOC = os.path.join(PAKS, "Dreadmoor-Windows.utoc")
GLOBAL_UTOC = os.path.join(PAKS, "global.utoc")
OODLE_CANDIDATES = [
    r"D:\SteamLibrary\steamapps\common\ARMORED CORE VI FIRES OF RUBICON\Game\oo2core_8_win64.dll",
    r"D:\SteamLibrary\steamapps\common\ELDEN RING\Game\oo2core_6_win64.dll",
]


def open_stores():
    from iostore import IoStore, Oodle
    last = None
    for dll in OODLE_CANDIDATES:
        if not os.path.exists(dll):
            continue
        try:
            oodle = Oodle(dll)
            store = IoStore(UTOC, oodle)
            store.read_chunk(store.files[next(iter(store.files))])
            return store, IoStore(GLOBAL_UTOC, oodle), dll
        except Exception as e:  # try the next decoder
            last = e
    raise RuntimeError(f"no working Oodle decoder: {last}")
