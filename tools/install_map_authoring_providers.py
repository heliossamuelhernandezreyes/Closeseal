#!/usr/bin/env python3
"""Install Close Seal map-authoring providers from the pinned lock file.

Only provider addon directories are copied. Demo projects/assets outside those
addon directories are intentionally excluded. Terrain3D is installed from its
official release archive and verified by SHA-256 because it is a GDExtension
that ships platform binaries.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "third_party" / "map_authoring.lock.json"
MARKER = ".close_seal_provider.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def remove_target(target: Path, force: bool) -> None:
    if not target.exists():
        return
    marker = target / MARKER
    if not force and not marker.exists():
        raise RuntimeError(f"Refusing to overwrite unmanaged directory: {target}")
    shutil.rmtree(target)


def write_marker(target: Path, provider: dict) -> None:
    payload = {
        "id": provider["id"],
        "name": provider["name"],
        "source": provider.get("repo"),
        "commit": provider.get("commit") or provider.get("reviewed_source_commit"),
        "release_tag": provider.get("release_tag"),
        "lock_schema": 1,
    }
    (target / MARKER).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def find_addon_dir(root: Path, expected_name: str) -> Path:
    direct = root / "addons" / expected_name
    if direct.is_dir():
        return direct
    matches = [p for p in root.rglob(expected_name) if p.is_dir() and p.parent.name == "addons"]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one addons/{expected_name}; found {len(matches)}")
    return matches[0]


def install_release(provider: dict, force: bool) -> None:
    target = ROOT / provider["target_addon"]
    remove_target(target, force)
    with tempfile.TemporaryDirectory(prefix="closeseal-provider-") as tmp:
        tmp_path = Path(tmp)
        archive = tmp_path / "provider.zip"
        urllib.request.urlretrieve(provider["archive_url"], archive)
        actual = sha256(archive)
        expected = provider["sha256"].lower()
        if actual.lower() != expected:
            raise RuntimeError(f"SHA-256 mismatch for {provider['name']}: {actual} != {expected}")
        extract = tmp_path / "extract"
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(extract)
        source = find_addon_dir(extract, Path(provider["target_addon"]).name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, target)
    write_marker(target, provider)


def install_git_subdir(provider: dict, force: bool) -> None:
    target = ROOT / provider["target_addon"]
    remove_target(target, force)
    with tempfile.TemporaryDirectory(prefix="closeseal-provider-") as tmp:
        checkout = Path(tmp) / "repo"
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        subprocess.run(["git", "-C", str(checkout), "remote", "add", "origin", provider["repo"]], check=True)
        subprocess.run(["git", "-C", str(checkout), "fetch", "-q", "--depth=1", "origin", provider["commit"]], check=True)
        subprocess.run(["git", "-C", str(checkout), "checkout", "-q", "FETCH_HEAD"], check=True)
        source = checkout / provider["source_subdir"]
        if not source.is_dir():
            raise RuntimeError(f"Pinned source directory missing: {source}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, target, ignore=shutil.ignore_patterns(".godot", "*.import"))
    write_marker(target, provider)


def check_provider(provider: dict) -> bool:
    target = ROOT / provider["target_addon"]
    marker = target / MARKER
    plugin_cfg = target / "plugin.cfg"
    if not target.is_dir() or not plugin_cfg.is_file() or not marker.is_file():
        print(f"MISSING  {provider['id']}: {target.relative_to(ROOT)}")
        return False
    try:
        installed = json.loads(marker.read_text(encoding="utf-8"))
    except Exception:
        print(f"INVALID  {provider['id']}: unreadable marker")
        return False
    wanted = provider.get("commit") or provider.get("reviewed_source_commit")
    if installed.get("commit") != wanted:
        print(f"STALE    {provider['id']}: {installed.get('commit')} != {wanted}")
        return False
    print(f"READY    {provider['id']}: {installed.get('commit')}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("providers", nargs="*", help="provider ids; empty means all")
    parser.add_argument("--check", action="store_true", help="do not install; verify current vendor state")
    parser.add_argument("--force", action="store_true", help="replace an existing unmanaged addon directory")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    providers = lock["providers"]
    requested = set(args.providers)
    selected = [p for p in providers if not requested or p["id"] in requested]
    unknown = requested - {p["id"] for p in providers}
    if unknown:
        raise SystemExit(f"Unknown provider ids: {', '.join(sorted(unknown))}")

    if args.check:
        return 0 if all(check_provider(p) for p in selected) else 1

    for provider in selected:
        print(f"Installing {provider['name']}...")
        if provider["kind"] == "release_archive":
            install_release(provider, args.force)
        elif provider["kind"] == "git_subdir":
            install_git_subdir(provider, args.force)
        else:
            raise RuntimeError(f"Unsupported provider kind: {provider['kind']}")
        if not check_provider(provider):
            raise RuntimeError(f"Post-install verification failed: {provider['id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
