# Curved urban roads through ARCONT

`authoring/recipes/urban_roads.json` authors a four-lane curved boulevard and
a two-lane flyover with 8m deck height. Nine explicit points define seven
Bezier segments, shoulders, road thickness and 22 lane paths. Sixteen existing
Kenney CC0 game assets frame the scene; no provider demo project is copied.
This is a separate 250m district study; canonical Urban Nexo JSON is preserved.

RoadGenerator is source-pinned in `third_party/map_authoring.lock.json` at
`9d144dc4a28dd6bee870895d2b77d69174356281` (MIT). Its editor plugin is enabled
alongside Map Forge. The general authoring bridge registers every authored
RoadPoint and RoadContainer, exposing native transforms and provider methods
through `set`, `call`, discovery and trusted project-script steps. The recipe
is the revisioned source; manual scene edits must be reflected back into the
recipe to survive a recipe rebuild.

```bash
python tools/install_map_authoring_providers.py
"$GODOT_BIN" --path . --editor --headless --import
python tools/road_network_smoke.py --arcont "$ARCONT_ROOT"
```

The test runs the public ARCONT CLI: provider discovery, commit, stale and
invalid-method rejection, stable-ID position/width patch and restore. It checks
real meshes, lane connections, collision samples on both sides of joints,
navigation across both roads and a capsule moving on a curve and climbing the
ramp. Every successful build saves two bundle scenes:

- `scenes/urban_roads_editable.tscn`: original RoadPoints/connections and provider
  regeneration on reopen, with interactive editor handles.
- `scenes/urban_roads_baked.tscn`: native road meshes/collision, baked navigation,
  Path3D lane curves and scenery. RoadGenerator runtime scripts are excluded.

The generic recursive `save` operation is not used for editable provider output:
RoadSegment requires a constructor argument. The project extension deliberately
packs source nodes while excluding generated segments. Reopening independently
regenerates and compares point/mesh geometry; the baked scene tests bridge and
lower street collision with a separate layer to avoid hitting the original.
Bundles remain immutable when a recipe is patched or restored. Use the existing
Control panel to run requests; the save step returns both paths. Open the editable
path in Godot (or copy the full bundle and referenced assets for distribution).

Scope limits: lane paths are navigation foundations, not traffic simulation;
terrain flattening and intersections are not enabled or accepted here. Mesh
quality and low-poly assets do not establish AAA art. CI render measurements
describe a Linux software renderer, not Android or production hardware.
