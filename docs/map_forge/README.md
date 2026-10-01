# Close Seal Map Forge

Map Forge is the project-owned authoring layer for Close Seal maps. It is intentionally independent from any single third-party editor addon.

## Canonical map contract

`res://maps/*.json` owns gameplay-critical map semantics:

- bounds
- bases and hero spawns
- objectives
- routes
- tactical regions / chokepoints
- provider metadata

Runtime validation lives in `res://src/map/map_contract.gd`.

## Provider model

The editor dock detects optional providers without making them mandatory:

- Terrain3D → terrain authoring
- Cyclops Level Builder → structural blockout
- ProtonScatter → environment scatter
- FuncGodot → optional brush-map interchange/import

When unavailable, Map Forge remains usable with native Godot workflows. Canonical JSON must never require a provider-specific class.

## Planned Map Forge layers

1. Terrain
2. Structures
3. Environment / scatter
4. Gameplay objects
5. Navigation
6. Tactical regions and formation-width annotations
7. Balance overlays
8. Playtest / validation

## Source-control rule

Editor convenience data may be provider-specific, but gameplay-critical semantics must remain serializable and reviewable in the canonical contract.

## Current implementation status

Map Forge 1.1 adds native World 3D authoring and a complete editor-control
interface. Read [EDITOR_CONTROL.md](EDITOR_CONTROL.md) for configuration, public
commands and the distinction between authored data and generated projections.

- EditorPlugin scaffold: implemented.
- Provider discovery: implemented.
- Canonical contract loader/validator: implemented.
- First competitive laboratory map contract: implemented.
- Native fallback: implemented provider guides and runtime visual projection.
- Exact provider acquisition: external installation through the pinned lockfile.
- World 3D selection/JSON/position editing: implemented.
- ARCONT control protocol and game adapter: implemented; no generative service.
- Arbitrary triangle geometry and imported scene placement: implemented.
- Runtime performance/mobile compatibility: not yet validated; no performance claim is made.

Editor import, native editing, materialization and rendered views are tested as
separate gates. Terrain sculpt/paint persistence and device performance remain
independent production milestones.
