import importlib.util
import json
import tempfile
import unittest
from pathlib import Path, PureWindowsPath
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


prepare = module("prepare_shooter")
export = module("export_shooter")


class ShooterBuildTests(unittest.TestCase):
    def test_unmanaged_destination_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage"
            target.mkdir()
            valuable = target / "valuable.txt"
            valuable.write_text("keep")
            with self.assertRaises(ValueError):
                prepare.stage(target)
            self.assertEqual(valuable.read_text(), "keep")

    def test_failed_copy_preserves_previous_build(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage"
            target.mkdir()
            (target / prepare.MARKER).write_text(json.dumps(prepare.OWNER))
            (target / "project.godot").write_text("old build")
            with patch.object(prepare, "_populate", side_effect=OSError("copy failed")):
                with self.assertRaises(OSError):
                    prepare.stage(target)
            self.assertEqual((target / "project.godot").read_text(), "old build")
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_successful_restage_removes_stale_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage"
            target.mkdir()
            (target / prepare.MARKER).write_text(json.dumps(prepare.OWNER))
            (target / "stale.fbx").write_text("old asset")
            def populate(path):
                (path / "project.godot").write_text("new build")
                (path / prepare.MARKER).write_text(json.dumps(prepare.OWNER))
            with patch.object(prepare, "_populate", side_effect=populate):
                prepare.stage(target)
            self.assertFalse((target / "stale.fbx").exists())
            self.assertEqual((target / "project.godot").read_text(), "new build")

    def test_project_ancestor_and_symlink_rejected(self):
        for target in [ROOT, ROOT.parent]:
            with self.assertRaises(ValueError):
                prepare.stage(target)
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "link"
            target.symlink_to(ROOT, target_is_directory=True)
            with self.assertRaises(ValueError):
                prepare.stage(target)

    def test_windows_export_paths_are_valid_godot_strings(self):
        text = export.presets(PureWindowsPath(r'C:\Users\Helios\Export Templates'))
        lines = [line.split("=", 1)[1] for line in text.splitlines() if line.startswith("custom_template/")]
        self.assertEqual(len(lines), 8)
        for value in lines:
            self.assertTrue(json.loads(value).startswith("C:/Users/Helios/Export Templates/"))
            self.assertNotIn("\\", json.loads(value))
