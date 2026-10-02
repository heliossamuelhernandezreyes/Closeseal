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
same CLI/MCP control with `operation: playtest`, current `if_revision`, a saved
scene artifact and a version-1 `session`. See Arcont's GODOT_PLAYTEST_CONTROL.md
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
`checkpoint.json` records the last completed command for diagnosis. It is not a
checkpoint that resumes a resident process. `report.json` distinguishes runner
completion (`ok`) from expectation outcome (`passed`). The same distinction is
returned by the CLI, so callers must check `passed` separately from exit status.

Source pins, scene hashes and logs are preserved by Arcont's existing evidence
writer. The accepted scene source is hash-checked before/after replay; dependency
closure extends only to explicitly pinned files. The Linux fixture test does not
establish Android performance, cross-platform physics determinism, general audio
recording or complete production gameplay coverage.
