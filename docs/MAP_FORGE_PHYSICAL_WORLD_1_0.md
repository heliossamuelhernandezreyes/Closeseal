# Map Forge 1.0 — Citadel Physical World

Status: implementation gate

## Goal

Turn the canonical map contract into gameplay-aware physical geography without coupling Close Seal to one terrain authoring provider.

## Required layers

1. Canonical semantics — routes, formation widths, objectives, regions and landforms remain game-owned.
2. Physical terrain — ridges, peaks, cliffs, passes, rivers and bridges must state whether they alter traversal.
3. Navigation — route corridors remain the canonical walkable baseline; tactical landforms may constrain them only through explicit contract data and validation.
4. Formation capacity — every route must preserve its declared formation width and report geometric column capacity.
5. World dressing — biome/scatter and structures are derivative provider projections and must not silently alter traversal.
6. Mobile budget — every production candidate map declares an explicit target FPS, active-unit budget and visible-scatter budget.
7. Evidence — editor materialization, navigation, runtime behavior, visual capture and Android performance are separate claims.

## Citadel acceptance gates

- Contract validation passes.
- Physical-world semantic analysis reports no errors.
- At least one tactical or navigation-blocking landform is represented before claiming tactical mountain terrain.
- Every canonical route remains at least as wide as its declared formation width.
- Navigation bake produces non-empty polygons and vertices.
- Provider-generated geometry cannot silently become canonical source of truth.
- Android performance must be measured before claiming the 60 FPS product target.

## Claim boundary

Passing this gate means the map is structurally ready for physical-world materialization. It does not prove balance, agent avoidance quality, multiplayer correctness, visual quality, or Android frame rate.
