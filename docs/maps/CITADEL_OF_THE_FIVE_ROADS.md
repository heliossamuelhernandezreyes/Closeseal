# Citadel of the Five Roads

## Purpose

Large symmetric 3D tactical arena for Close Seal. The canonical contract remains the single source of truth; provider scenes are generated projections.

## Layout

- 96 x 64 metre playable envelope.
- West/east fortified bases with hero spawns.
- Main lane: widest direct assault corridor.
- North/south secondary lanes: objective pressure and tower play.
- North/south jungle flanks: longer, wider alternative routes.
- Central basin: formation space around the central seal.
- North/south relic basins: contestable side objectives.

## Tactical language

- Main lane rewards direct timing and tower pressure.
- Secondary lanes create split pressure without requiring a narrow single-file path.
- Jungle flanks provide alternative approach vectors and concealment zones.
- Ruins and pillars provide readable cover landmarks.
- Watchpoints and wards create reasons to leave the safest lane.
- The layout is mirrored by role and distance, while objective identities remain distinct.

## Authored providers

| Layer | Provider | Contract role |
|---|---|---|
| Terrain | Terrain3D | terrain projection and future sculpt data |
| Structures | Cyclops | fortress, tower, ruin and bridge authoring |
| Scatter | ProtonScatter | pine, deadwood, rocks and rune gardens |
| Import | FuncGodot | optional interchange socket, never canonical format |
| Navigation | Godot Recast | baked physical walkability from route source geometry |

## Materials and asset catalog

The contract defines a reusable palette: fortress/weathered/moss stone, team iron, ancient gold, obsidian, dark wood and blue/violet emissive crystals. Each structure and scatter zone names an asset ID and material ID. The generated manifest exports both catalogs so a future visual asset pass can replace procedural guides without changing gameplay semantics.

## Validation boundary

The map is designed for physical route and crowd validation. The current CI evidence proves provider materialization, Recast bake, A→B queries, avoidance callbacks and load telemetry on Ubuntu/Godot 4.7.2. It does not yet prove Android performance, final art assets, final combat balance or production readiness.

## Next visual pass

Replace procedural guide meshes with authored modular kits, add terrain height variation while preserving route clearance, instantiate the material palette in the runtime renderer, and compare visual readability on a mobile-sized viewport.
