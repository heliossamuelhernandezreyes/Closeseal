extends SceneTree
func _initialize() -> void:
	var candidate_path:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate="):candidate_path=argument.trim_prefix("--candidate=")
	var candidate: AnimationLibrary=load(candidate_path)
	var delivered: AnimationLibrary=load("res://assets/shooter/serious/combat_motion.res")
	var keys:=0
	var same:=candidate!=null and candidate.get_animation_list()==delivered.get_animation_list()
	if same:
		for clip in delivered.get_animation_list():
			var a: Animation=delivered.get_animation(clip)
			var b: Animation=candidate.get_animation(clip)
			same=same and a.length==b.length and a.loop_mode==b.loop_mode and a.get_track_count()==b.get_track_count()
			for track in a.get_track_count():
				same=same and a.track_get_path(track)==b.track_get_path(track) and a.track_get_key_count(track)==b.track_get_key_count(track)
				for key in a.track_get_key_count(track):
					keys+=1
					same=same and a.track_get_key_time(track,key)==b.track_get_key_time(track,key) and a.track_get_key_value(track,key)==b.track_get_key_value(track,key)
	var report: Dictionary={"ok":same,"clips":delivered.get_animation_list().size(),"keys":keys,"candidate":candidate_path,"scope":"Exact native key equality after ARCONT writer rebuild and reopen"}
	DirAccess.make_dir_recursive_absolute("res://.arcont/production-evidence")
	var file:=FileAccess.open("res://.arcont/production-evidence/motion-rebuild.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("MOTION_REPRO ",JSON.stringify(report));quit(0 if same else 1)
