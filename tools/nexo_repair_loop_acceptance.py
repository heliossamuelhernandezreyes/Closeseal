#!/usr/bin/env python3
"""Controlled Nexo fault -> ARCONT diagnosis -> repair -> replay acceptance.

The checkout is never intentionally left broken. A disposable staged Nexo copy
is used for every mutation. Nexo supplies raw structured evidence plus a
declarative diagnosis policy; ARCONT selects the hypothesis/candidate and
compiles the revision-checked repair plan.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


FAULT_OBJECT_ID = "hero_cover_body_0"
FAULT_HEIGHT = 1.70
FAULT_CENTER_Y = 0.85
CANONICAL_HEIGHT = 1.14
CANONICAL_CENTER_Y = 0.57
MAX_VAULT_HEIGHT = 1.35


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], *, cwd: Path | None = None, log: Path | None = None, timeout: int = 600) -> subprocess.CompletedProcess:
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout, check=False)
    if log is not None:
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    if completed.returncode:
        raise RuntimeError({
            "command": command,
            "returncode": completed.returncode,
            "stdout_tail": completed.stdout[-3000:],
            "stderr_tail": completed.stderr[-3000:],
        })
    return completed


def run_agent(arcont: Path, project: Path, plan: dict, evidence: Path, name: str) -> dict:
    command = [
        sys.executable,
        str(arcont / "tools/arcont_agent.py"),
        "run-plan",
        "--project",
        str(project),
        "--plan",
        "-",
        "--allow-project-write",
    ]
    completed = subprocess.run(
        command,
        input=json.dumps(plan),
        text=True,
        capture_output=True,
        timeout=900,
        check=False,
    )
    (evidence / f"{name}.stdout.json").write_text(completed.stdout, encoding="utf-8")
    (evidence / f"{name}.stderr.log").write_text(completed.stderr, encoding="utf-8")
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError({"invalid_agent_json": name, "stderr": completed.stderr[-3000:]}) from exc
    if completed.returncode or not report.get("ok"):
        raise RuntimeError({"agent_plan_failed": name, "report": report})
    return report


def run_diagnosis(arcont: Path, policy: Path, raw_evidence: dict, evidence_dir: Path) -> dict:
    evidence_path = evidence_dir / "03-diagnosis-evidence.json"
    evidence_path.write_text(json.dumps(raw_evidence, indent=2), encoding="utf-8")
    command = [
        sys.executable,
        str(arcont / "tools/arcont_agent.py"),
        "diagnose",
        "--policy",
        str(policy),
        "--evidence",
        str(evidence_path),
        "--require-match",
    ]
    completed = subprocess.run(command, text=True, capture_output=True, timeout=120, check=False)
    (evidence_dir / "03-diagnosis.stdout.json").write_text(completed.stdout, encoding="utf-8")
    (evidence_dir / "03-diagnosis.stderr.log").write_text(completed.stderr, encoding="utf-8")
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError({"invalid_diagnosis_json": completed.stderr[-3000:]}) from exc
    if completed.returncode or not report.get("ok") or not report.get("matched"):
        raise RuntimeError({"diagnosis_failed": report, "stderr": completed.stderr[-3000:]})
    return report


def step_output(report: dict, step_id: str) -> dict:
    for step in report.get("steps", []):
        if step.get("id") == step_id:
            return step["output"]
    raise KeyError(step_id)


def checkpoint_states(playtest_output: dict) -> dict[str, dict]:
    report = playtest_output["result"]["report"]
    return {item["id"]: item for item in report["checkpoints"]}


def find_object(data: dict, identity: str) -> dict:
    for item in data.get("authoring", {}).get("objects", []):
        if item.get("id") == identity:
            return item
    raise KeyError(identity)


def runtime_recipe(project: Path) -> dict:
    recipe = json.loads((project / "authoring/recipes/shooter_third_person.json").read_text(encoding="utf-8"))
    dependencies = {}
    for relative in recipe.get("dependencies", {}):
        path = project / relative
        if path.is_file():
            dependencies[relative] = sha256(path)
    recipe["dependencies"] = dependencies
    return recipe


def map_fault_plan(original: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_inject_low_cover_fault",
        "goal": "Inject a bounded physical low-cover height fault by stable map object ID.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["map-forge.editor.control"],
        "steps": [
            {
                "id": "inspect_map",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {"protocol_version": 1, "operation": "inspect", "map_id": "nexo_combat_01"},
            },
            {
                "id": "fault_cover",
                "kind": "invoke",
                "capability": "map-forge.editor.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "patch",
                    "map_id": "nexo_combat_01",
                    "if_revision": {"$from": "inspect_map", "pointer": "/result/revision"},
                    "dry_run": False,
                    "patch": [
                        {"op": "test", "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/size/1", "value": original["size"][1]},
                        {"op": "test", "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/position/1", "value": original["position"][1]},
                        {"op": "replace", "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/size/1", "value": FAULT_HEIGHT},
                        {"op": "replace", "path": f"/map/authoring/objects/@{FAULT_OBJECT_ID}/position/1", "value": FAULT_CENTER_Y},
                    ],
                },
                "expect": [
                    {"pointer": "/result/committed", "op": "equals", "value": True},
                    {"pointer": "/result/revision", "op": "exists"},
                ],
            },
        ],
    }


def first_playtest_plan(recipe: dict, session: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_observe_fault",
        "goal": "Build the faulted Nexo slice and observe the real third-person cover/vault route.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inventory",
                "kind": "inspect-project",
                "max_files": 50000,
                "expect": [{"pointer": "/project/engine", "op": "equals", "value": "godot"}],
            },
            {
                "id": "author",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "create",
                    "document_id": recipe["id"],
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [{"pointer": "/result/revision", "op": "exists"}],
            },
            {
                "id": "inspect_authored",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {"protocol_version": 1, "operation": "inspect", "document_id": recipe["id"]},
            },
            {
                "id": "playtest",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "playtest",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_authored", "pointer": "/result/revision"},
                    "if_bundle": {"$from": "inspect_authored", "pointer": "/result/last_build/directory"},
                    "scene": "scenes/nexo_third_person.tscn",
                    "session": session,
                    "options": {"audio_driver": "Dummy"},
                },
            },
        ],
    }


def raw_diagnosis_evidence(project: Path, playtest_output: dict) -> dict:
    states = checkpoint_states(playtest_output)
    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]
    data = json.loads((project / "maps/nexo_combat_01.json").read_text(encoding="utf-8"))
    route_completed = (
        isinstance(land.get("position"), list)
        and len(land["position"]) >= 3
        and land["position"][2] <= 99.8
        and land.get("vault_aborted") is False
    )
    return {
        "signals": {
            "cover_low": bool(cover.get("cover_low")),
            "cover_crouched": bool(cover.get("crouched")),
            "vault_state": vault.get("movement_state"),
            "vault_route_completed": route_completed,
        },
        "observations": {
            "cover_position": cover.get("position"),
            "vault_position": vault.get("position"),
            "land_position": land.get("position"),
        },
        "context": {"map_id": "nexo_combat_01"},
        "limits": {"max_vault_height": MAX_VAULT_HEIGHT},
        "baseline": {"height": CANONICAL_HEIGHT, "center_y": CANONICAL_CENTER_Y},
        "world": {"objects": data.get("authoring", {}).get("objects", [])},
    }


def recovery_playtest_plan(recipe: dict, session: dict) -> dict:
    return {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_verify_repair",
        "goal": "Rebuild from the repaired revision and prove the exact cover/vault route recovers.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inspect_old_authoring",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {"protocol_version": 1, "operation": "inspect", "document_id": recipe["id"]},
            },
            {
                "id": "rebuild",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "replace",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_old_authoring", "pointer": "/result/revision"},
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [{"pointer": "/result/revision", "op": "exists"}],
            },
            {
                "id": "inspect_repaired_authoring",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {"protocol_version": 1, "operation": "inspect", "document_id": recipe["id"]},
            },
            {
                "id": "playtest",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "timeout_seconds": 300,
                "request": {
                    "protocol_version": 1,
                    "operation": "playtest",
                    "document_id": recipe["id"],
                    "if_revision": {"$from": "inspect_repaired_authoring", "pointer": "/result/revision"},
                    "if_bundle": {"$from": "inspect_repaired_authoring", "pointer": "/result/last_build/directory"},
                    "scene": "scenes/nexo_third_person.tscn",
                    "session": session,
                    "options": {"audio_driver": "Dummy"},
                },
                "expect": [
                    {"pointer": "/result/passed", "op": "equals", "value": True},
                    {"pointer": "/result/report/input_released", "op": "equals", "value": True},
                ],
            },
        ],
    }


def prepare_stage(source: Path, stage: Path, godot: str, evidence: Path) -> None:
    run([sys.executable, str(source / "tools/prepare_shooter.py"), "--stage", str(stage)], cwd=source, log=evidence / "prepare-stage.log")

    # The staged slice normally consumes a pre-baked sector. This experiment
    # deliberately edits the canonical map, so force the dynamic MapVisualKit
    # path instead of allowing stale derived geometry.
    (stage / "assets/shooter/sector07/sector_world.tscn").unlink(missing_ok=True)

    shutil.copy(source / "map-forge.authoring.json", stage / "map-forge.authoring.json")
    for name in ("map_forge_adapter.py", "validate_maps.py", "validate_environment.py"):
        shutil.copy(source / "tools" / name, stage / "tools" / name)

    run([godot, "--headless", "--path", str(stage), "--editor", "--import"], log=evidence / "import-1.log")
    run([sys.executable, str(source / "tools/configure_shooter_imports.py"), "--stage", str(stage)], cwd=source, log=evidence / "configure-imports.log")
    run([godot, "--headless", "--path", str(stage), "--editor", "--import"], log=evidence / "import-2.log")
    run([godot, "--headless", "--path", str(stage), "--script", "res://tools/shooter_bake.gd"], log=evidence / "bake.log")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", type=Path, required=True)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    source = Path(__file__).resolve().parents[1]
    arcont = args.arcont.resolve()
    stage = args.stage.resolve()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    godot = os.environ.get("GODOT_BIN", "godot")
    policy_path = source / "authoring/diagnosis/nexo_low_cover_vault.policy.json"

    prepare_stage(source, stage, godot, evidence)

    map_path = stage / "maps/nexo_combat_01.json"
    canonical_sha = sha256(map_path)
    canonical_data = json.loads(map_path.read_text(encoding="utf-8"))
    original = find_object(canonical_data, FAULT_OBJECT_ID)
    if original["size"][1] != CANONICAL_HEIGHT or original["position"][1] != CANONICAL_CENTER_Y:
        raise RuntimeError({"unexpected_canonical_cover": original})

    session = json.loads((stage / "authoring/scenarios/shooter_third_person.json").read_text(encoding="utf-8"))

    fault_edit = run_agent(arcont, stage, map_fault_plan(original), evidence, "01-fault-map")
    fault_data = json.loads(map_path.read_text(encoding="utf-8"))
    fault_object = find_object(fault_data, FAULT_OBJECT_ID)
    if fault_object["size"][1] != FAULT_HEIGHT or fault_object["position"][1] != FAULT_CENTER_Y:
        raise RuntimeError({"fault_not_committed": fault_object})

    fault_recipe = runtime_recipe(stage)
    fault_observation = run_agent(arcont, stage, first_playtest_plan(fault_recipe, session), evidence, "02-observe-fault")
    fault_playtest = step_output(fault_observation, "playtest")

    raw_evidence = raw_diagnosis_evidence(stage, fault_playtest)
    diagnosis = run_diagnosis(arcont, policy_path, raw_evidence, evidence)
    hypothesis = diagnosis["hypothesis"]
    if hypothesis["code"] != "low_cover_height_out_of_vault_range":
        raise RuntimeError({"unexpected_hypothesis": hypothesis["code"]})
    if hypothesis["candidate"].get("id") != FAULT_OBJECT_ID:
        raise RuntimeError({"unexpected_candidate": hypothesis["candidate"].get("id"), "expected": FAULT_OBJECT_ID})

    repair_plan = hypothesis.get("repair_plan")
    if not isinstance(repair_plan, dict):
        raise RuntimeError("ARCONT diagnosis did not compile a repair plan")
    repair_edit = run_agent(arcont, stage, repair_plan, evidence, "04-repair-map")
    if sha256(map_path) != canonical_sha:
        raise RuntimeError({
            "repair_did_not_restore_canonical_map_bytes": {
                "expected": canonical_sha,
                "actual": sha256(map_path),
            }
        })

    repaired_recipe = runtime_recipe(stage)
    recovery = run_agent(arcont, stage, recovery_playtest_plan(repaired_recipe, session), evidence, "05-verify-repair")
    repaired_playtest = step_output(recovery, "playtest")
    states = checkpoint_states(repaired_playtest)
    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]

    assertions = {
        "arcont_selected_hypothesis": diagnosis.get("matched") is True,
        "arcont_selected_fault_object": hypothesis["candidate"].get("id") == FAULT_OBJECT_ID,
        "canonical_map_restored_byte_for_byte": sha256(map_path) == canonical_sha,
        "cover_low_recovered": cover.get("movement_state") == "cover" and cover.get("cover_low") is True and cover.get("crouched") is True,
        "vault_recovered": vault.get("movement_state") == "vault",
        "landing_recovered": land.get("movement_state") == "free" and land.get("vault_aborted") is False,
        "playtest_passed": repaired_playtest["result"].get("passed") is True,
        "input_released": repaired_playtest["result"]["report"].get("input_released") is True,
    }
    if not all(assertions.values()):
        raise RuntimeError({"recovery_assertions": assertions, "states": states})

    summary = {
        "ok": True,
        "arcont_head": subprocess.check_output(["git", "-C", str(arcont), "rev-parse", "HEAD"], text=True).strip(),
        "fault": {
            "object_id": FAULT_OBJECT_ID,
            "canonical_height": CANONICAL_HEIGHT,
            "fault_height": FAULT_HEIGHT,
            "map_plan_sha256": fault_edit["plan_sha256"],
            "observation_plan_sha256": fault_observation["plan_sha256"],
            "playtest_passed": fault_playtest["result"].get("passed"),
        },
        "diagnosis": {
            "policy_id": diagnosis["policy_id"],
            "policy_sha256": diagnosis["policy_sha256"],
            "evidence_sha256": diagnosis["evidence_sha256"],
            "hypothesis": {
                "id": hypothesis["id"],
                "code": hypothesis["code"],
                "summary": hypothesis["summary"],
                "candidate": hypothesis["candidate"],
                "candidate_distance_xz": hypothesis["candidate_distance_xz"],
                "details": hypothesis["details"],
            },
            "compiled_repair_plan_sha256": repair_edit["plan_sha256"],
        },
        "repair": {
            "verification_plan_sha256": recovery["plan_sha256"],
            "canonical_map_sha256": canonical_sha,
            "assertions": assertions,
            "physics_frames": repaired_playtest["result"]["report"]["physics_frames"],
            "final_state": repaired_playtest["result"]["report"]["final_state"],
        },
        "limits": [
            "Controlled disposable-stage repair experiment; production repository content is not committed by the loop.",
            "Game-specific diagnosis knowledge is declarative policy data; ARCONT owns hypothesis/candidate selection and repair-plan compilation.",
            "This is deterministic policy reasoning, not yet free-form LLM hypothesis generation.",
            "Linux/Xvfb evidence does not establish Android handset FPS, thermals, or subjective animation quality.",
        ],
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
