#!/usr/bin/env python3
"""Acceptance of ARCONT's bounded agent loop against the real Nexo third-person slice."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def run_agent(arcont: Path, project: Path, plan: dict, allow_write: bool) -> tuple[int, dict]:
    cmd = [
        sys.executable,
        str(arcont / "tools/arcont_agent.py"),
        "run-plan",
        "--project",
        str(project),
        "--plan",
        "-",
    ]
    if allow_write:
        cmd.append("--allow-project-write")
    completed = subprocess.run(
        cmd,
        input=json.dumps(plan),
        text=True,
        capture_output=True,
        timeout=600,
        check=False,
    )
    if not completed.stdout.strip():
        raise RuntimeError({"returncode": completed.returncode, "stderr": completed.stderr[-4000:]})
    return completed.returncode, json.loads(completed.stdout)


def checkpoints(report: dict) -> dict[str, dict]:
    return {item["id"]: item for item in report["result"]["report"]["checkpoints"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arcont", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    arcont = args.arcont.resolve()
    project = args.project.resolve()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)

    recipe = json.loads((project / "authoring/recipes/shooter_third_person.json").read_text(encoding="utf-8"))
    session = json.loads((project / "authoring/scenarios/shooter_third_person.json").read_text(encoding="utf-8"))

    # Negative control: a failed observation must stop before a writer step.
    negative = {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_fail_closed",
        "goal": "Prove that a failed inspection expectation prevents later Nexo authoring.",
        "permissions": {"project_write": True},
        "capability_allowlist": ["godot.authoring.control"],
        "steps": [
            {
                "id": "inventory",
                "kind": "inspect-project",
                "max_files": 50000,
                "expect": [{"pointer": "/project/engine", "op": "equals", "value": "unreal"}],
            },
            {
                "id": "must_not_run",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "create",
                    "document_id": recipe["id"],
                    "recipe": recipe,
                    "dry_run": False,
                    "options": {"audio_driver": "Dummy"},
                },
            },
        ],
    }
    negative_code, negative_report = run_agent(arcont, project, negative, True)
    if negative_code == 0 or negative_report.get("failed_step") != "inventory" or negative_report.get("steps_completed") != 1:
        raise RuntimeError({"negative_control_did_not_fail_closed": negative_report})
    if (project / "authoring/documents/shooter_third_person.json").exists():
        raise RuntimeError("negative control reached the writer unexpectedly")

    positive = {
        "protocol": "arcont-agent-plan",
        "version": 1,
        "id": "nexo_real_acceptance",
        "goal": "Author the real Nexo third-person scene, lock its revision and replay the cover/vault route.",
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
                "id": "discover",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "discover",
                    "document_id": recipe["id"],
                    "options": {"class": "SpringArm3D"},
                },
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
                "expect": [
                    {"pointer": "/result/revision", "op": "exists"},
                    {"pointer": "/result/last_build/directory", "op": "exists"},
                ],
            },
            {
                "id": "inspect_authored",
                "kind": "invoke",
                "capability": "godot.authoring.control",
                "request": {
                    "protocol_version": 1,
                    "operation": "inspect",
                    "document_id": recipe["id"],
                },
                "expect": [
                    {"pointer": "/result/revision", "op": "exists"},
                    {"pointer": "/result/last_build/directory", "op": "exists"},
                ],
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
                "expect": [
                    {"pointer": "/result/passed", "op": "equals", "value": True},
                    {"pointer": "/result/report/input_released", "op": "equals", "value": True},
                ],
            },
        ],
    }

    positive_code, report = run_agent(arcont, project, positive, True)
    if positive_code or not report.get("ok"):
        raise RuntimeError({"agent_loop_failed": report})

    step = next(item for item in report["steps"] if item["id"] == "playtest")
    playtest = step["output"]
    states = checkpoints(playtest)

    cover = states["cover_settle"]["state"]
    vault = states["vault_midpoint"]["state"]
    land = states["land"]["state"]

    assertions = {
        "cover_state_preserved": cover.get("movement_state") == "cover" and cover.get("crouched") is True,
        "vault_state_reached": vault.get("movement_state") == "vault" and vault.get("position", [0, 0, 0])[1] >= 1.0,
        "vault_lands_without_abort": land.get("movement_state") == "free" and land.get("vault_aborted") is False,
        "input_released": playtest["result"]["report"].get("input_released") is True,
        "third_person_visible": all(
            states[name]["state"].get("perspective") == "third_person"
            and states[name]["state"].get("body_visible") is True
            for name in ("cover_settle", "vault_midpoint", "land")
        ),
    }
    if not all(assertions.values()):
        raise RuntimeError({"nexo_state_assertions": assertions, "playtest": playtest})

    summary = {
        "ok": True,
        "arcont_head": subprocess.check_output(
            ["git", "-C", str(arcont), "rev-parse", "HEAD"], text=True
        ).strip(),
        "plan_sha256": report["plan_sha256"],
        "registry_sha256": report["registry_sha256"],
        "steps_completed": report["steps_completed"],
        "write_steps": report["write_steps"],
        "negative_control": {
            "ok": negative_code != 0,
            "failed_step": negative_report.get("failed_step"),
            "steps_completed": negative_report.get("steps_completed"),
        },
        "assertions": assertions,
        "revision": next(item for item in report["steps"] if item["id"] == "inspect_authored")["output"]["result"]["revision"],
        "bundle": next(item for item in report["steps"] if item["id"] == "inspect_authored")["output"]["result"]["last_build"]["directory"],
        "playtest": {
            "passed": playtest["result"]["passed"],
            "physics_frames": playtest["result"]["report"]["physics_frames"],
            "final_state": playtest["result"]["report"]["final_state"],
        },
        "limits": [
            "GitHub Linux/Xvfb acceptance; not Android handset FPS or thermal evidence.",
            "This proves bounded author/build/playtest orchestration, not autonomous artistic judgment.",
        ],
    }

    (evidence / "negative-control.json").write_text(json.dumps(negative_report, indent=2), encoding="utf-8")
    (evidence / "agent-loop-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
