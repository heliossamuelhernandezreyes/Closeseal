# Map Forge 1.2 — authored environments

Set `purpose: "environment"` to compose a scene without competitive bases or
injected terraces, rivers, objectives and map borders. Keep the gameplay arrays
present; they may be empty. Competitive mode remains the default for old maps.
Environment mode has no theme preset: shape, layout, resources and lighting are
chosen by the operator. This is an editor operated by a person or assistant.

## Scene composition

All definitions live under `authoring` and support the public control protocol.

| Collection | Authored controls |
| --- | --- |
| `objects` | group, box, sphere, cylinder/cone, capsule, plane, prism, torus; size, transform, material, visibility, collision |
| `geometry` | indexed triangles, vertex UVs, transform, material, collision |
| `instances` | existing Node3D PackedScene/GLB, transform, material override |
| `heightfields` | translated grid chunks, X/Z spacing, row-major heights, per-cell materials and holes, collision |
| `materials` | albedo/normal/roughness/metallic textures, UV scale, emission, opacity, double-sided rendering; or any project Material/ShaderMaterial resource |
| `lights` | directional, omni, spot; color, energy, transform, range, angle, shadows |
| `environment` | background, ambient light and distance fog |

Objects can reference another object's `id` through `parent`. Geometry,
instances and lights can also use an object parent. Transforms are local to that
parent. Missing parents and cycles are rejected. A group gives one editable
transform to an authored building or any compound asset. Scene instances can
contain additional Godot features, including effects or animation; import the
resources before placement. Missing resources make construction fail.

Heightfields are axis-aligned and support 2–2049 vertices per axis per chunk.
Use multiple chunks for larger terrain. This numeric limit is not a performance
budget: choose resolution and assets for the target hardware. Triangle meshes
and imported scenes handle overhangs, tunnels and caves; heightfields alone do
not represent those shapes.

## Brush authoring and history

The World 3D tab has creation controls and a terrain brush. Select a heightfield
in the object tree, enable the brush, choose mode/radius/strength/material, then
click the terrain. Raise, lower, flatten, smooth, paint, hole and fill join the
same Undo/Redo and Save flow as all other visual edits. The tab scrolls to keep
controls accessible in a narrow editor dock.

Arcont operates the same data using the `brush` operation:

```json
{
  "protocol_version": 1,
  "operation": "brush",
  "map_id": "my_environment",
  "if_revision": "<revision returned by inspect>",
  "dry_run": false,
  "options": {
    "heightfield_id": "ground",
    "center": [12, -6],
    "mode": "raise",
    "radius": 8,
    "strength": 3
  }
}
```

Center is world X/Z. Strength is height delta for raise/lower and an interpolation
amount capped at one for flatten/smooth. Flatten also uses `height`; paint uses
a material `id`. A linear radial falloff affects heights; paint and hole/fill
modify cells inside the footprint. Painting uses categorical cell materials,
not GPU splat blending. Invalid edits and stale revisions do not overwrite the
map. Dry-run remains the default. Use `restore` to undo committed external edits.

## Terrain3D persistence

Native meshes render the canonical height and cell material data on the project's
Compatibility renderer. With `authoring.terrain.provider: "terrain3d"`, building
also synchronizes height, base material IDs, color and holes into Terrain3D 1.0.2
region files under `maps/generated/terrain/<map_id>`. Synchronization requires
square, consistent spacing and world-grid-aligned origins, and at most 32
material IDs. Native terrain does not have that material-count restriction.

The provider copy is hidden in the generated scene to avoid drawing duplicate
terrain. The bridge uses documented Terrain3D data APIs rather than an editor
mouse macro. Region files are generated output; canonical JSON is the source
that is versioned and reproduced.

To bring provider height/base-paint/hole edits back to the canonical grid, use
`edit` with `options: {"action": "terrain_pull"}`, the current revision and
`dry_run: false`. Inspect and validate the prepared result before committing.
Pull before rebuilding: materialization reproduces canonical data and will
replace the generated provider copy. Pull samples the existing grid resolution;
provider blend/overlay weights and arbitrary texture-asset configuration are
not imported. Provider file writes are separate from the JSON writer's rollback.

Reference API: https://terrain3d.readthedocs.io/en/stable/api/class_terrain3ddata.html

## Navigation and inspection

`authoring.navigation.mode` supports:

- `none`: a visual environment without navigation.
- `routes`: the existing competitive corridor compiler.
- `world`: Recast baking from actual authored static colliders, including terrain
  and placed resources. The objects that should affect walking need collision.

Agent dimensions and slope/climb settings are explicit. Rebuild after changing
traversal geometry. A rendered obstacle with collision disabled does not block
navigation. Imported dynamic avoidance and gameplay logic need their own tests.

Use `materialize` for a saved Godot scene, `capture` with authored cameras to see
it, `inspect` to read its exact state, and patch/brush/edit to iterate. Evidence
includes requests, responses and engine logs in separate operation directories.

## Acceptance fixtures

The repository contains three independent examples, not theme restrictions:
`environment_alpine_lab`, `environment_interior_lab` and
`environment_orbital_lab`. They exercise sculpted/painted terrain and holes,
a textured interior with a navigation obstacle, and material resources with
custom shaders and scene placement. CI checks provider save/reload, brush parity
between Python and Godot, actual collision/path queries and real camera captures.
The examples use deliberately simple assets; they are not final production art.
Android memory, frame rate and exported platform packages require device tests.
