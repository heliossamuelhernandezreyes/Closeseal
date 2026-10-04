# Sector 07 presentation authoring

Use the exact engine and Arcont revision in `arcont-production.lock.json`.
Create an independent managed stage with `tools/prepare_shooter.py`. Submit
`authoring/recipes/sector07_presentation.json` through Arcont's general
`godot_authoring_control.py`: discover, inspect, then create or replace with
`if_revision`. The recipe never edits the canonical map.

The game adapter creates portable UV2 mesh resources and saves a runtime world
plus an isolated bake scene. Imported resource ownership stays intact. Explicit
SHA-256 entries for the candidate's scene, meshes and materials are passed to
`production_toolchain.py bundle --project STAGE record.json`; `--replace` only
replaces an Arcont-managed destination. Keep its pre-bake receipt unchanged.

Run `python tools/shooter_lightmap_bake.py --project STAGE --engine ENGINE` inside
an X11 RenderingDevice session. Godot 4.7.2 does not expose `LightmapGI.bake` to
GDScript: the game-owned temporary editor plugin invokes the native bake toolbar.
The helper completes texture imports first and restores the stage's editor-plugin
configuration afterwards. The bake scene has the runtime lightmap node paths.
Its saved light data is also assigned to `sector_world.tscn`.

The accepted bake retains two Godot editor teardown diagnostics (`List::erase`
and an absolute-node lookup after scene removal). The native atlas, bindings and
probes were produced before shutdown. Keep this limitation visible in the output
record; require a separate clean runtime import and acceptance instead of calling
the editor adapter error-free.

Preserve the native bake log and receipt, then hash the final saved resources
separately. Reopen the final scene in a freshly imported Compatibility stage,
bake canonical navigation, and run all shooter acceptance jobs including
`shooter_presentation_acceptance.gd`. That job checks resolved visible mesh
bindings, textures, actor probes, unchanged canonical hash, camera obstruction,
shoulder clearance and action continuity. Inspect actual courtyard/workshop views.
Do not infer Android performance from these Linux captures or software timings.

After review, commit the derived assets and final hashes to Closeseal. The bake
scene and editor adapter are authoring tools; the APK excludes the bake scene,
tools and authoring inputs. The runtime needs only the saved world, mesh/material
resources, light textures and probe data. Arcont is not a runtime dependency.

`tools/verify_shooter_sector.py` verifies the post-bake hashes and the essential
`.exr.import` layered-texture metadata. Preserve that metadata when preparing a
fresh project: the default EXR importer creates a 2D texture and loses the array
layers required by LightmapGI. `prepare_shooter.py` retains the native atlas import
configuration while regenerating ordinary developer texture imports.
