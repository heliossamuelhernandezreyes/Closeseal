# Closeseal

Closeseal is the production game repository. ARCONT is its external technical knowledge bank and experimental laboratory.

## Repository role

This repository contains the game itself: gameplay code, scenes, assets, builds, tests and release automation.

ARCONT remains separate and is used for evidence-backed technical decisions, benchmarks, profiling and reusable engine knowledge.

## Status

Bootstrap phase. Product decisions are intentionally explicit and unresolved until documented in `docs/PRODUCT_CONTRACT.md`.

## Engine

Godot 4.7.2-stable is the initial canonical engine target, aligned with the current ARCONT Godot pin. Engine upgrades must be deliberate and documented.


## Urban environment

[Distrito Nexo](docs/map_forge/URBAN_NEXO.md) is the first explorable urban map:
512 × 512 metres, four districts and 32 blocks, authored with Arcont Map Forge
and committed Kenney assets. Run `src/urban/urban_nexo.tscn` in Godot (F6).
The documentation includes controls, source checksums and eight real captures.

## General engine authoring

[Map Forge 1.3](docs/map_forge/GODOT_AUTHORING.md) exposes native Godot and installed
provider APIs through ARCONT's CLI and optional MCP stdio server. Explicit scene
recipes can create/edit nodes and resources, run provider methods, save/reopen,
capture, query collision/navigation, author spatial sound and collect measurements.
Canonical map editing remains available through the existing map contract control.
