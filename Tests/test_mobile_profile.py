import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('mobile_profile', Path(__file__).resolve().parents[1] / 'Scripts/prepare_mobile_profile.py')
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class MobileProfilePaths(unittest.TestCase):
    def test_keeps_game_overrides_inside_gamedata(self):
        for name in ['gamedata/textures/act/test.dds', 'gamedata/levels/zaton/level_lmap#1.dds',
                     'gamedata/scripts/class_registrator.script', 'gamedata/configs/ui/pda_tasks_16.xml']:
            self.assertEqual(profile.relative_path(name).as_posix(), name)

    def test_rejects_paths_into_saves_archives_and_outside_root(self):
        for name in ['../outside', '/gamedata/scripts/test.script', 'gamedata/scripts/../../user.ltx',
                     'gamedata/scripts//test', 'gamedata/scripts/./test', 'gamedata/scripts/.hidden',
                     'gamedata/scripts/C:save', 'gamedata/scripts/a\\b', 'gamedata/scripts/a\0b',
                     '_appdata_/savedgames/test.scop', 'resources/configs.db', 'fsgame.ltx']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                profile.relative_path(name)
