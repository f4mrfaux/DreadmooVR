import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cfg  # noqa: E402
from list_container import foreign_paths, full_path, list_files  # noqa: E402

ALLOW = "Dreadmoor/Content/DreadmoorVR/"


class ListContainerTests(unittest.TestCase):
    def test_list_game_container(self):
        files = list_files(cfg.UTOC)
        self.assertIn(
            "Dreadmoor/Content/3rdParty/TFPMovement/Demo/Character/Mannequins/Meshes/SK_DreadMoreSkeleton.uasset",
            files)
        self.assertEqual(files, sorted(files))

    def test_list_container_flags_foreign_paths(self):
        bad = "Dreadmoor/Content/Dreadmoor/Animations/Characters/new/dm_demo_NewProtagonist.uasset"
        got = foreign_paths(["Dreadmoor/Content/DreadmoorVR/BP_PakProbe.uasset", bad], ALLOW)
        self.assertEqual(got, [bad])

    def test_allowed_only(self):
        self.assertEqual(foreign_paths(["Dreadmoor/Content/DreadmoorVR/PAL_DreadmoorVR.uasset",
                                        "Dreadmoor/Content/DreadmoorVR/BP_PakProbe.uexp"], ALLOW), [])

    def test_full_path_joins_deep_mount(self):
        # A mod container mounts below Content, so its directory entries are relative to that.
        self.assertEqual(full_path("../../../Dreadmoor/Content/DreadmoorVR/", "BP_PakProbe.uasset"),
                         "Dreadmoor/Content/DreadmoorVR/BP_PakProbe.uasset")

    def test_full_path_root_mount_unchanged(self):
        self.assertEqual(full_path("../../../", "Dreadmoor/Content/X.uasset"), "Dreadmoor/Content/X.uasset")

    def test_non_asset_files_ignored(self):
        # Container metadata such as the asset registry or shader libraries are not assets.
        self.assertEqual(foreign_paths(["Dreadmoor/AssetRegistry.bin",
                                        "Dreadmoor/Content/ShaderArchive-Dreadmoor-PCD3D_SM6.ushaderbytecode"], ALLOW), [])


if __name__ == "__main__":
    unittest.main()
