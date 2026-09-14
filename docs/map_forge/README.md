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

- EditorPlugin scaffold: implemented.
- Provider discovery: implemented.
- Canonical contract loader/validator: implemented.
- First competitive laboratory map contract: implemented.
- Native fallback: declared architecture path.
- Terrain3D/Cyclops/ProtonScatter/FuncGodot binaries/source: not vendored yet.
- Runtime performance/mobile compatibility: not yet validated; no performance claim is made.

The next milestone is adapter-by-adapter installation/pinning and reproducible editor/import tests before any provider is marked production-ready.
