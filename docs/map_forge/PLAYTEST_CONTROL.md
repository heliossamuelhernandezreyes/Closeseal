# Observe and repair an input-driven urban scene

`urban_playtest.json` extends the existing curved-road fixture with a 12x20m
editable workshop, a 3m doorway, twelve physical 0.2m stairs, upper landing,
terminal and three observation cameras. Geometry is explicit native recipe
data; patches address stable step IDs. Roof geometry is a deliberate cutaway
for inspection. The test preserves canonical maps and the game's main scene.

`playtest_explorer.gd` is an instrumented 1.8m capsule fixture. It reads normal
Input actions and uses CharacterBody3D movement. Stair step-up requires swept
capsule clearance and a support collision query; it does not steer by assigning
route positions. The input event also drives a nearby terminal interaction.
It is not a production character, combat system or enemy AI.

The project-owned runner is configured in `godot-authoring.json`. Use Arcont's
same CLI/MCP control with `operation: playtest`, current `if_revision`,
`if_bundle` from `inspect.last_build.directory`, a saved scene artifact and a
version-1 `session`. A rebuild with unchanged source still requires the current
bundle pin. See Arcont's GODOT_PLAYTEST_CONTROL.md
for the request contract. The scene is freshly reopened for every session.

```bash
python tools/import_authoring_project.py --godot "$GODOT_BIN"
xvfb-run -a -s '-screen 0 1280x720x24' python tools/playtest_loop_smoke.py --arcont "$ARCONT_ROOT"
```

The acceptance test explicitly requires:

1. A blocked entrance produces a failed position expectation and contacts with
   the `door_blocker` source ID, while preserving the accepted document/bundle.
2. Revision-checked patches disable the blocker collision and its visible mesh.
3. The same saved session reaches the interior, climbs physical stairs and
   activates the terminal through Input events; actual navigation reaches it.
4. Reopening and repeating gives matching tick counts and positions within 1mm.
5. Restoring source history recreates the blocked route, without editing maps.
6. The actual editor opens the accepted scene and edits/restores a source wall.

Each session records held input, completed physics ticks, position, velocity,
floor status, source-identified contacts, stair-step count and interactions in
`playtest/trace.jsonl`; checkpoint images and JSON remain in immutable run bundles.
Input events are flushed before the next measured tick, including releases while
the tree is paused. Before replay, navigation uses matching map/mesh voxel sizes
and waits for a newer synchronized region iteration, bounded to 120 physics
frames. Preparation frames are separate from the actor's replay tick count.
Navigation is optional: an absent region or a region without a NavigationMesh
reports `available: false` and still permits actor input replay.
`playtest/navigation.tres` preserves the baked mesh; the report records its actual
route points and synchronization iterations. The actor is disabled before the
runner leaves its final tick signal, so cleanup cannot free an emitting actor.
`checkpoint.json` records the last completed command for diagnosis. It is not a
checkpoint that resumes a resident process. `report.json` distinguishes runner
completion (`ok`) from expectation outcome (`passed`). The same distinction is
returned by the CLI, so callers must check `passed` separately from exit status.

Source pins, scene hashes and logs are preserved by Arcont's existing evidence
writer. The accepted scene source is hash-checked before/after replay; dependency
closure extends only to explicitly pinned files. The Linux fixture test does not
establish Android performance, cross-platform physics determinism, general audio
recording or complete production gameplay coverage.

Verified engine/editor results and actual captures are preserved under
[evidence/playtest_loop](evidence/playtest_loop/README.md). The corrected and
reopened sessions each complete 485 actor ticks, twelve step-ups and one terminal
interaction. The blocked/restored sessions stop at the source-identified door
obstacle after 300 ticks. The measured corrected navigation path has 36 points.
