"""Failure recovery matters: plugin setup must preserve authored configuration."""
import contextlib
import hashlib
import importlib.util
import io
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


class ProviderSetupTests(unittest.TestCase):
    def test_failed_bootstrap_restores_exact_source_bytes(self):
        importer = module("project_import_failure", "import_authoring_project.py")
        original = b'[application]\nconfig/name="X"\n[editor_plugins]\nenabled=PackedStringArray("res://plugin.cfg")\n[rendering]\n'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "project.godot").write_bytes(original)
            result = subprocess.CompletedProcess([], 0, "ERROR: invalid resource", "")
            with patch.object(importer, "ROOT", root), patch.object(importer.subprocess, "run", return_value=result), patch("sys.argv", ["import", "--godot", "godot"]), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(RuntimeError): importer.main()
            self.assertEqual((root / "project.godot").read_bytes(), original)

    def test_enabled_pass_sees_restored_configuration(self):
        importer = module("project_import_success", "import_authoring_project.py")
        original = b'[editor_plugins]\nenabled=PackedStringArray("res://plugin.cfg")\n'
        observed = []
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "project.godot").write_bytes(original)
            def run(*args, **kwargs):
                observed.append((root / "project.godot").read_bytes())
                return subprocess.CompletedProcess([], 0, "", "")
            with patch.object(importer, "ROOT", root), patch.object(importer.subprocess, "run", side_effect=run), patch("sys.argv", ["import"]), contextlib.redirect_stdout(io.StringIO()):
                importer.main()
            self.assertIn(b"PackedStringArray()", observed[0])
            self.assertEqual(observed[1], original)

    def test_patches_reject_wrong_source_and_verify_exact_result(self):
        installer = module("provider_patch", "install_map_authoring_providers.py")
        before, after = b"before\n", b"after\n"
        body = b"--- a/plugin.gd\n+++ b/plugin.gd\n@@ -1 +1 @@\n-before\n+after\n"
        digest = lambda value: hashlib.sha256(value).hexdigest()
        provider = {"id": "fixture", "patches": [{"file": "plugin.gd", "patch": "fix.patch", "patch_sha256": digest(body), "source_sha256": digest(before), "result_sha256": digest(after)}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "addon"
            target.mkdir()
            (root / "fix.patch").write_bytes(body)
            source = target / "plugin.gd"
            source.write_bytes(b"unexpected\n")
            with patch.object(installer, "ROOT", root):
                with self.assertRaises(RuntimeError): installer.apply_source_patches(provider, target)
                self.assertEqual(source.read_bytes(), b"unexpected\n")
                source.write_bytes(before)
                installer.apply_source_patches(provider, target)
            self.assertEqual(source.read_bytes(), after)
