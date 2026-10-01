@tool
extends RefCounted

# Only provider data is synchronized. Native meshes remain the portable renderer.
static func synchronize(state: Dictionary, pull := false) -> Dictionary:
    var data_map: Dictionary = state["map"]
    var fields: Array = data_map.get("authoring", {}).get("heightfields", [])
    if fields.is_empty() or not ClassDB.class_exists(&"Terrain3D"):
        return {"ok": false, "error": "Terrain3D and authored heightfields are required"}
    var materials: Array = data_map["authoring"].get("materials", [])
    if materials.size() > 32:
        return {"ok": false, "error": "Terrain3D supports at most 32 material ids per synchronization"}
    var palette: Array[String] = []
    var colors: Dictionary = {}
    for m in materials:
        palette.append(String(m["id"]))
        colors[m["id"]] = Color(String(m.get("albedo", "808080")))
    var spacing := float(fields[0].get("spacing", [1, 1])[0])
    for f in fields:
        var step: Array = f.get("spacing", [1, 1])
        var p: Array = f.get("position", [0, 0, 0])
        if float(step[0]) != spacing or float(step[1]) != spacing or absf(float(p[0]) / spacing - roundf(float(p[0]) / spacing)) > 0.0001 or absf(float(p[2]) / spacing - roundf(float(p[2]) / spacing)) > 0.0001:
            return {"ok": false, "error": "Terrain3D fields require one square world-aligned spacing"}
    var directory := "res://maps/generated/terrain/" + String(data_map["id"])
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
    var terrain = ClassDB.instantiate(&"Terrain3D")
    terrain.set("vertex_spacing", spacing)
    terrain.set("region_size", 64)
    terrain.set("data_directory", directory)
    terrain.visible = false
    var loop: SceneTree = Engine.get_main_loop()
    loop.root.add_child(terrain)
    await loop.process_frame
    var provider = terrain.get("data")
    if provider == null:
        terrain.free()
        return {"ok": false, "error": "Terrain3D data did not initialize"}
    var util = ClassDB.instantiate(&"Terrain3DUtil")
    if not pull:
        for f in fields:
            var columns := int(f["columns"])
            var rows := int(f["rows"])
            var heights: Array = f["heights"]
            var paint: Array = f.get("paint", [])
            var holes: Array = f.get("holes", [])
            var origin := Vector3(float(f.get("position", [0, 0, 0])[0]), 0, float(f.get("position", [0, 0, 0])[2]))
            var height := Image.create(columns, rows, false, Image.FORMAT_RF)
            var control := Image.create(columns, rows, false, Image.FORMAT_RF)
            var color := Image.create(columns, rows, false, Image.FORMAT_RGBA8)
            for z in range(rows):
                for x in range(columns):
                    var cell := mini(z, rows - 2) * (columns - 1) + mini(x, columns - 2)
                    var material := String(paint[cell]) if not paint.is_empty() else String(f["material"])
                    var bits: int = util.call("enc_base", palette.find(material)) | util.call("enc_nav", true)
                    if not holes.is_empty() and holes[cell]:
                        bits |= int(util.call("enc_hole", true))
                    height.set_pixel(x, z, Color(float(heights[z * columns + x]) + float(f.get("position", [0, 0, 0])[1]), 0, 0, 1))
                    control.set_pixel(x, z, Color(float(util.call("as_float", bits)), 0, 0, 1))
                    color.set_pixel(x, z, colors[material])
            var images: Array[Image] = [height, control, color]
            provider.call("import_images", images, origin)
        provider.call("save_directory", directory)
    else:
        provider.call("load_directory", directory)
    var result := state.duplicate(true)
    var maximum_error := 0.0
    var paint_matches := true
    for f in result["map"]["authoring"]["heightfields"]:
        var columns := int(f["columns"])
        var rows := int(f["rows"])
        var position: Array = f.get("position", [0, 0, 0])
        for z in range(rows):
            for x in range(columns):
                var index := z * columns + x
                var point := Vector3(float(position[0]) + x * spacing, 0, float(position[2]) + z * spacing)
                var sampled: float = provider.call("get_height", point)
                # Holes intentionally have no surface height. Their stored RF value
                # remains accessible through get_pixel rather than interpolation.
                if not is_finite(sampled):
                    var pixel: Color = provider.call("get_pixel", 0, point)
                    sampled = pixel.r
                sampled -= float(position[1])
                maximum_error = maxf(maximum_error, absf(sampled - float(f["heights"][index])))
                if pull:
                    f["heights"][index] = sampled
        var paint: Array = []
        var holes: Array = []
        for z in range(rows - 1):
            for x in range(columns - 1):
                var point := Vector3(float(position[0]) + x * spacing, 0, float(position[2]) + z * spacing)
                var bits: int = provider.call("get_control", point)
                var base: int = util.call("get_base", bits)
                paint.append(palette[base] if base >= 0 and base < palette.size() else String(f["material"]))
                holes.append(bool(util.call("is_hole", bits)))
        var expected: Array = f.get("paint", [])
        if not expected.is_empty() and expected != paint:
            paint_matches = false
        if pull:
            f["paint"] = paint
            f["holes"] = holes
    util.free()
    terrain.free()
    var files := DirAccess.get_files_at(directory)
    if files.is_empty():
        return {"ok": false, "error": "Terrain3D did not persist region files"}
    if pull:
        return {"ok": true, "state": result, "provider_directory": directory}
    # Reload disk data in a separate provider instance before declaring success.
    var reloaded := await synchronize(state, true)
    if not reloaded.get("ok", false):
        return reloaded
    return {"ok": maximum_error < 0.001 and paint_matches, "provider_directory": directory, "region_files": Array(files), "maximum_height_error": maximum_error, "paint_preserved": paint_matches, "reloaded_state": reloaded["state"]}
