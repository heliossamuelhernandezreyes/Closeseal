# Map Forge 1.2 — editor control and World 3D

The assistant operates the map editor. There is no prompt-to-map generator,
model endpoint or API key. Every map decision remains explicit authored data.

## Setup

Check out ARCONT separately, set `ARCONT_ROOT` to its directory and `GODOT_BIN`
to the pinned Godot executable. The game requires Python 3 for external control.
`map-forge.authoring.json` declares the project adapter and editable layers.
For Windows, configure the appropriate Python executable in `adapter_command`;
the dock currently launches `python3`, so the portable CLI is the supported path
where that executable name is unavailable.

Open the project in Godot to finish importing assets before external control.
For a clean command-line checkout, run `godot --path . --editor --headless --import`
with the pinned engine; `--quit` alone may leave textures unimported.

```bash
python "$ARCONT_ROOT/tools/map_forge_control.py" --project . --request request.json --output response.json
```

Use `capabilities`, `list`, then `inspect`. The inspect response provides the
complete state and revision. Use that revision in a patch/replace/restore
request. All existing and extension fields are editable; the game validates the
result before it is saved. Dry-run is the default. Set `dry_run: false` to commit.

## Visual authoring

- **World 3D:** renders the same contract used by runtime. Right-drag orbits,
  middle-drag pans, the wheel zooms and Frame fits the map.
- Click a marker or select an object in the tree. Edit X/Y/Z or its complete
  JSON, including dimensions, heights, materials and route points.
- Select Complete map contract to add/remove any collection item or edit a
  field not represented by the convenient controls.
- Apply JSON validates first. Edits join the existing Undo/Redo and Save flow.
- **Control:** executes the same ARCONT request protocol without blocking the
  editor. Set the tool path or ARCONT_ROOT. Save pending visual edits before
  external control; committed responses reload the canonical source.

## Geometry and imported resources

`authoring.geometry` accepts authored indexed triangle meshes: id, vertices,
indices, material, optional position/rotation_degrees and collision. Indices
must form triangles and reference valid vertices. Use Godot's clockwise front
face winding; generated normals follow that convention. This can represent custom
terrain, ramps, bridges or arbitrary authored geometry.

`authoring.instances` accepts id, scene (`res://` PackedScene/GLB), position,
rotation_degrees and positive scale. Assets must already exist in the game and
pass their production pipeline. The control interface does not invent assets.

Both are consumed by the runtime visual kit and generated authoring scene.
Custom collision does not automatically redefine the canonical navigation
corridors. Changes to traversal require the physical/navigation acceptance
gates; a rendered obstacle alone is not proof of blocked pathfinding.

## Building and inspecting

`materialize` uses the provider bridge, native visual kit, navigation and optional
physical profile. `capture` renders tactical/north/east/top camera views from
the provided state. `options.cameras` also accepts any authored camera position,
target, perspective/orthogonal projection, field of view and orthogonal size:

```json
{"views": ["top"], "cameras": [{"name": "detail", "position": [18, 14, 24], "target": [0, 2, 6], "projection": "perspective", "fov": 55}]}
```

Set `views` to an empty array to capture only custom cameras. Missing or invalid
scene resources make materialization/capture fail instead of silently omitting
the asset. Captures need a rendering/display environment (Xvfb in CI).
Responses include output paths, counts and logs in `.mapforge/evidence`.

The 1.0 import blocker in the physical report formatter is corrected. This does
not establish device performance. Terrain3D grid synchronization and world collision navigation are documented in
[ENVIRONMENT_AUTHORING.md](ENVIRONMENT_AUTHORING.md). Dynamic avoidance quality
and target Android measurements remain independent gates.

## Verification

```bash
python tools/map_forge_control_smoke.py --arcont "$ARCONT_ROOT"
python tools/map_forge_control_smoke.py --arcont "$ARCONT_ROOT" --engine
```

The smoke test exercises the public CLI: inspect, create, invalid-edit rejection,
stale revision rejection, stable-ID patching, analysis and restoration. The
engine variant adds missing-resource rejection, physical materialization and
five actual rendered views (including an authored detail camera) of an authored
custom ramp and a placed scene resource. Integral numeric indices round-trip
between Python and Godot JSON without a type mismatch.

General environment composition, terrain brushes, custom material resources
and world navigation: [ENVIRONMENT_AUTHORING.md](ENVIRONMENT_AUTHORING.md).
