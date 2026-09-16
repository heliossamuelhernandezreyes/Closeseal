@tool
class_name CloseSealMapPhysicalWorld
extends RefCounted
const MAP_CONTRACT = preload("res://src/map/map_contract.gd")
static func profile_path(map_id: String) -> String: return "res://maps/physical/%s.json" % map_id
static func load_profile(map_id: String) -> Dictionary:
    var path:=profile_path(map_id)
    if not FileAccess.file_exists(path): return {}
    var file:=FileAccess.open(path,FileAccess.READ)
    if file==null:return {}
    var parsed=JSON.parse_string(file.get_as_text())
    return parsed if typeof(parsed)==TYPE_DICTIONARY else {}
static func analyze(map_data:Dictionary,profile:Dictionary={}) -> Dictionary:
    var errors:Array[String]=[];var warnings:Array[String]=[];var map_id:=String(map_data.get("id",""))
    if profile.is_empty():profile=load_profile(map_id)
    if profile.is_empty():return {"ok":false,"errors":["physical profile missing for '%s'"%map_id],"warnings":[]}
    if String(profile.get("map_id",""))!=map_id:errors.append("physical profile map_id does not match canonical map")
    var blockers:Array=profile.get("terrain_blockers",[]);var tactical:=0
    for value in blockers:
        if typeof(value)!=TYPE_DICTIONARY:errors.append("terrain blocker must be a dictionary");continue
        var b:Dictionary=value;var id:=String(b.get("id","")).strip_edges()
        if id.is_empty():errors.append("terrain blocker requires id")
        if not _finite_vec3_array(b.get("center",null)):errors.append("blocker '%s' requires finite center"%id)
        if not _positive_vec3_array(b.get("size",null)):errors.append("blocker '%s' requires positive size"%id)
        if String(b.get("navigation_role","")) in ["tactical_boundary","blocking_cliff","pass_wall"]:tactical+=1
    if tactical==0:errors.append("physical profile has no tactical blocking terrain")
    var route_ids:Dictionary={};var formation:Dictionary=profile.get("formation",{});var footprint:=maxf(float(formation.get("unit_diameter",0.9))+float(formation.get("spacing",0.25)),0.1);var minimum_columns:=maxi(1,int(formation.get("minimum_columns",3)));var route_capacity:Dictionary={}
    for value in map_data.get("routes",[]):
        if typeof(value)!=TYPE_DICTIONARY:continue
        var route:Dictionary=value;var rid:=String(route.get("id","route"));route_ids[rid]=true;var width:=float(route.get("width",0.0));var required:=float(route.get("formation_width",width));var columns:=maxi(1,int(floor(width/footprint)));route_capacity[rid]={"width":width,"formation_width":required,"columns":columns}
        if width+0.001<required:errors.append("route '%s' is narrower than declared formation width"%rid)
        if columns<minimum_columns:errors.append("route '%s' cannot satisfy minimum formation columns"%rid)
    var passes:Array=profile.get("passes",[])
    for value in passes:
        if typeof(value)!=TYPE_DICTIONARY:continue
        var p:Dictionary=value;var pid:=String(p.get("id","pass"));var rid:=String(p.get("connects_route",""))
        if not route_ids.has(rid):errors.append("pass '%s' references unknown route '%s'"%[pid,rid])
        if float(p.get("width",0.0))<=0.0:errors.append("pass '%s' requires positive width"%pid)
        if float(p.get("max_slope_degrees",91.0))>45.0:warnings.append("pass '%s' exceeds recommended tactical slope"%pid)
    var budgets:Dictionary=profile.get("performance_budget",{})
    for key in ["target_fps","max_active_units","max_visible_scatter_instances"]:
        if float(budgets.get(key,0))<=0.0:errors.append("performance_budget.%s must be positive"%key)
    if not bool(budgets.get("require_measured_device_evidence",false)):warnings.append("device evidence is not required by profile")
    return {"ok":errors.is_empty(),"errors":errors,"warnings":warnings,"blockers":blockers.size(),"tactical_blockers":tactical,"passes":passes.size(),"water_crossings":profile.get("water_crossings",[]).size(),"biomes":profile.get("biomes",[]).size(),"route_capacity":route_capacity,"performance_budget":budgets,"model":"canonical map + provider-neutral physical profile; target-device benchmark remains a separate claim"}
static func augment_scene(scene_path:String,map_data:Dictionary,profile:Dictionary={}) -> Dictionary:
    if profile.is_empty():profile=load_profile(String(map_data.get("id","")))
    var audit:=analyze(map_data,profile)
    if not bool(audit.get("ok",false)):return audit
    if scene_path.is_empty() or not ResourceLoader.exists(scene_path):return {"ok":false,"error":"authoring scene missing"}
    var packed=load(scene_path)
    if packed==null or not packed is PackedScene:return {"ok":false,"error":"authoring scene is not PackedScene"}
    var root=packed.instantiate()
    if root==null or not root is Node3D:return {"ok":false,"error":"authoring scene cannot instantiate"}
    var root3d:Node3D=root;var old:=root3d.get_node_or_null("PhysicalWorld")
    if old!=null:root3d.remove_child(old);old.free()
    var layer:=Node3D.new();layer.name="PhysicalWorld";layer.set_meta("map_forge_role","canonical_physical_constraints");root3d.add_child(layer);layer.owner=root3d
    for value in profile.get("terrain_blockers",[]):
        if typeof(value)!=TYPE_DICTIONARY:continue
        var b:Dictionary=value;var body:=StaticBody3D.new();body.name=String(b.get("id","blocker"));body.position=MAP_CONTRACT.vec3_from(b.get("center",[]));body.set_meta("navigation_role",String(b.get("navigation_role","tactical_boundary")));var shape_node:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=MAP_CONTRACT.vec3_from(b.get("size",[]),Vector3.ONE);shape_node.shape=shape;body.add_child(shape_node);layer.add_child(body);body.owner=root3d;shape_node.owner=root3d
    for value in profile.get("passes",[]):
        if typeof(value)!=TYPE_DICTIONARY:continue
        var p:Dictionary=value;var marker:=Marker3D.new();marker.name=String(p.get("id","pass"));marker.position=MAP_CONTRACT.vec3_from(p.get("center",[]));marker.set_meta("map_forge_role","tactical_pass");marker.set_meta("width",float(p.get("width",0.0)));marker.set_meta("connects_route",String(p.get("connects_route","")));layer.add_child(marker);marker.owner=root3d
    var repacked:=PackedScene.new()
    if repacked.pack(root3d)!=OK:root3d.free();return {"ok":false,"error":"physical world repack failed"}
    var save_error:=ResourceSaver.save(repacked,scene_path);root3d.free()
    if save_error!=OK:return {"ok":false,"error":"physical world save failed"}
    audit["scene_path"]=scene_path;audit["materialized_collision_bodies"]=profile.get("terrain_blockers",[]).size();return audit
static func format_report(result:Dictionary)->String:
    var lines:Array[String]=["[b]Map Forge 1.0 — Physical World[/b]"];lines.append("[color=green]READY[/color]" if bool(result.get("ok",false)) else "[color=red]BLOCKED[/color]");lines.append("%d tactical blockers • %d passes • %d water crossings • %d biomes"%[int(result.get("tactical_blockers",0)),int(result.get("passes",0)),int(result.get("water_crossings",0)),int(result.get("biomes",0))]);for error in result.get("errors",[]):lines.append("[color=red]ERROR[/color] %s"%error);for warning in result.get("warnings",[]):lines.append("[color=yellow]WARN[/color] %s"%warning);lines.append("Android FPS remains unproven until measured on target hardware.");return "\n".join(lines)
static func _finite_vec3_array(value)->bool:return typeof(value)==TYPE_ARRAY and value.size()>=3 and is_finite(float(value[0])) and is_finite(float(value[1])) and is_finite(float(value[2]))
static func _positive_vec3_array(value)->bool:return _finite_vec3_array(value) and float(value[0])>0.0 and float(value[1])>0.0 and float(value[2])>0.0
