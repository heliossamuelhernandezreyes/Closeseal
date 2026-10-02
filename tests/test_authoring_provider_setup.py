"""Failure recovery matters: plugin setup must preserve authored configuration."""
import contextlib
import hashlib
import importlib.util
import io
import copy
import json
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
        for newline in [b"\n", b"\r\n"]:
            source = original.replace(b"\n", newline)
            with self.subTest(newline=newline), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "project.godot").write_bytes(source)
                result = subprocess.CompletedProcess([], 0, "ERROR: invalid resource", "")
                with patch.object(importer, "ROOT", root), patch.object(importer.subprocess, "run", return_value=result), patch("sys.argv", ["import", "--godot", "godot"]), contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(RuntimeError): importer.main()
                self.assertEqual((root / "project.godot").read_bytes(), source)

    def test_enabled_pass_sees_restored_configuration(self):
        importer = module("project_import_success", "import_authoring_project.py")
        original = b'[editor_plugins]\nenabled=PackedStringArray("res://plugin.cfg")\n'
        for newline in [b"\n", b"\r\n"]:
            source = original.replace(b"\n", newline)
            observed = []
            with self.subTest(newline=newline), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "project.godot").write_bytes(source)
                def run(*args, **kwargs):
                    observed.append((root / "project.godot").read_bytes())
                    return subprocess.CompletedProcess([], 0, "", "")
                with patch.object(importer, "ROOT", root), patch.object(importer.subprocess, "run", side_effect=run), patch("sys.argv", ["import"]), contextlib.redirect_stdout(io.StringIO()):
                    importer.main()
                self.assertEqual(observed[0], source.replace(b'PackedStringArray("res://plugin.cfg")', b"PackedStringArray()"))
                self.assertEqual(observed[1], source)

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

    def test_failed_install_preserves_previous_addon_and_allows_normal_retry(self):
        installer = module("provider_install_retry", "install_map_authoring_providers.py")
        before, after = b"before\n", b"after\n"
        body = b"--- a/plugin.gd\n+++ b/plugin.gd\n@@ -1 +1 @@\n-before\n+after\n"
        digest = lambda value: hashlib.sha256(value).hexdigest()
        for failure in ["patch_hash", "apply", "result_hash"]:
            for existing in [False, True]:
                with self.subTest(failure=failure, existing=existing), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    checkout = root / "source"
                    addon = checkout / "addons/fixture"
                    addon.mkdir(parents=True)
                    (addon / "plugin.gd").write_bytes(before)
                    (addon / "plugin.cfg").write_text('[plugin]\nname="Fixture"\n')
                    subprocess.run(["git", "init", "-q", str(checkout)], check=True)
                    subprocess.run(["git", "-C", str(checkout), "add", "."], check=True)
                    subprocess.run(["git", "-C", str(checkout), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"], check=True)
                    commit = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
                    (root / "fix.patch").write_bytes(body)
                    provider = {"id": "fixture", "name": "Fixture", "repo": str(checkout), "commit": commit,
                                "source_subdir": "addons/fixture", "target_addon": "addons/fixture",
                                "patches": [{"file": "plugin.gd", "patch": "fix.patch", "patch_sha256": digest(body), "source_sha256": digest(before), "result_sha256": digest(after)}]}
                    target = root / "addons/fixture"
                    if existing:
                        target.mkdir(parents=True)
                        (target / installer.MARKER).write_text('{"previous": true}\n')
                        (target / "plugin.gd").write_bytes(b"previous installation\n")
                    invalid = copy.deepcopy(provider)
                    if failure == "patch_hash": invalid["patches"][0]["patch_sha256"] = "0" * 64
                    if failure == "result_hash": invalid["patches"][0]["result_sha256"] = "0" * 64
                    if failure == "apply":
                        malformed = body.replace(b"-before\n", b"-unmatched\n")
                        (root / "fix.patch").write_bytes(malformed)
                        invalid["patches"][0]["patch_sha256"] = digest(malformed)
                    with patch.object(installer, "ROOT", root), contextlib.redirect_stdout(io.StringIO()):
                        with self.assertRaises((RuntimeError, subprocess.CalledProcessError)):
                            installer.install_git_subdir(invalid, False)
                        if existing:
                            self.assertEqual((target / "plugin.gd").read_bytes(), b"previous installation\n")
                            self.assertEqual(json.loads((target / installer.MARKER).read_text()), {"previous": True})
                        else:
                            self.assertFalse(target.exists())
                        self.assertFalse(list(target.parent.glob(".closeseal-provider-*")))
                        (root / "fix.patch").write_bytes(body)
                        installer.install_git_subdir(provider, False)
                        self.assertTrue(installer.check_provider(provider))
                    self.assertEqual((target / "plugin.gd").read_bytes(), after)

    def test_failed_publication_restores_previous_addon(self):
        installer = module("provider_publish_failure", "install_map_authoring_providers.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            (source / "plugin.cfg").write_text("new")
            target = root / "addons/fixture"
            target.mkdir(parents=True)
            (target / installer.MARKER).write_text("previous marker")
            (target / "plugin.cfg").write_text("previous")
            provider = {"id": "fixture", "name": "Fixture", "target_addon": "addons/fixture"}
            rename = Path.rename
            def fail_publication(path, destination):
                if path.name == "addon": raise OSError("simulated publication failure")
                return rename(path, destination)
            with patch.object(installer, "ROOT", root), patch.object(Path, "rename", fail_publication):
                with self.assertRaises(OSError): installer.publish_provider(provider, source, False)
            self.assertEqual((target / "plugin.cfg").read_text(), "previous")
            self.assertEqual((target / installer.MARKER).read_text(), "previous marker")

    def test_staging_does_not_overwrite_unmanaged_addon(self):
        installer = module("provider_unmanaged", "install_map_authoring_providers.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "addons/fixture"
            target.mkdir(parents=True)
            (target / "plugin.cfg").write_text("authored")
            provider = {"id": "fixture", "name": "Fixture", "target_addon": "addons/fixture"}
            with patch.object(installer, "ROOT", root):
                with self.assertRaises(RuntimeError): installer.publish_provider(provider, root / "missing", False)
            self.assertEqual((target / "plugin.cfg").read_text(), "authored")
