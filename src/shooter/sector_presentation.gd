@tool
extends RefCounted
## Authored industrial palette and additive non-colliding maintenance details.
static func lighting(world: Node3D) -> void:
	for node in world.find_children("*","WorldEnvironment",true,false):
		var environment: Environment=node.environment
		var sky:=Sky.new();var panorama:=PanoramaSkyMaterial.new()
		panorama.panorama=load("res://assets/shooter/serious/evening_road_01_puresky.hdr")
		panorama.energy_multiplier=0.85;sky.sky_material=panorama
		environment.sky=sky;environment.background_mode=Environment.BG_SKY
		environment.background_energy_multiplier=0.85;environment.sky_rotation.y=0.55
		environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color=Color("a5b7c2");environment.ambient_light_energy=0.65
		environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode=Environment.TONE_MAPPER_ACES;environment.tonemap_exposure=1.05
		environment.adjustment_enabled=true;environment.adjustment_saturation=0.80;environment.adjustment_contrast=1.04
		environment.fog_enabled=true;environment.fog_light_color=Color("82929b");environment.fog_density=0.0016
		environment.fog_sky_affect=0.08
	for sun in world.find_children("*","DirectionalLight3D",true,false):
		sun.light_color=Color("ffe1bd");sun.light_energy=1.10
		sun.directional_shadow_max_distance=90.0
		sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.shadow_bias=0.035;sun.shadow_normal_bias=1.0
	for light in world.find_children("*","OmniLight3D",true,false):
		# Bake indirect illumination; practical direct light also reaches moving actors.
		light.light_bake_mode=Light3D.BAKE_DYNAMIC
		if str(light.name).begins_with("hero_slice_fill"):
			light.light_color=Color("c1d0d5");light.light_energy=1.50

static func details(world: Node3D) -> Dictionary:
	var detail_root:=Node3D.new();detail_root.name="SectorMaintenanceDetails";world.add_child(detail_root)
	var paint:=ShaderMaterial.new();paint.shader=load("res://assets/shooter/maintenance_paint.gdshader")
	var hazard:=paint.duplicate();hazard.set_shader_parameter("stripes",1.0)
	var rubber:=StandardMaterial3D.new();rubber.albedo_color=Color("242a29");rubber.roughness=0.96
	var steel: Material=load("res://assets/shooter/serious/materials/steel.tres")
	var count:=0
	for x in [-15.0,13.0]:
		for z in [79.5,85.5,91.5]:
			box(detail_root,"PaintedColumn",Vector3(x+(0.24 if x<0 else -0.24),1.55,z),Vector3(0.055,1.50,0.34),hazard)
			count+=1
	for z in [95.0,86.0,74.0]:
		for x in [-12.0,12.0]:
			box(detail_root,"YardSafetyLine",Vector3(x,0.071,z),Vector3(0.08,0.012,7.0),paint)
			count+=1
	for z in [78.0,83.0,89.0]:
		box(detail_root,"WorkshopTaskLamp",Vector3(34.25,2.55,z),Vector3(0.18,0.12,2.2),steel)
		var lamp:=OmniLight3D.new();lamp.name="BenchLamp";lamp.position=Vector3(33.6,2.45,z)
		lamp.light_color=Color("ffd9ad");lamp.light_energy=2.0;lamp.omni_range=6.5;lamp.light_bake_mode=Light3D.BAKE_DYNAMIC
		detail_root.add_child(lamp)
		for i in range(4):
			box(detail_root,"MachineFoot",Vector3(34.2,0.05,z-0.60+i*0.40),Vector3(0.24,0.09,0.25),rubber)
		count+=5
	# Broad, low-height reflected fill keeps silhouettes readable beneath the mezzanine.
	var fill_index:=0
	for point in [Vector3(19,2.0,79),Vector3(28,2.0,86)]:
		var fill:=OmniLight3D.new();fill.name="WorkshopBounceFill%d"%fill_index;fill.position=point;fill_index+=1
		fill.light_color=Color("b6c5cc");fill.light_energy=6.0;fill.omni_range=10.0
		fill.light_bake_mode=Light3D.BAKE_DYNAMIC;detail_root.add_child(fill)
	# Signs are attached to real architecture and respect depth.
	for sign_ in [[Vector3(24,5.4,94.18),0.0,"07   /   MANTENIMIENTO","ACCESO RESTRINGIDO"],
		[Vector3(-21,3.05,100.18),0.0,"04   /   SUMINISTROS","ZONA DE CARGA"],
		[Vector3(0,7.15,61.44),0.0,"NEXO    /    SECTOR 07","PLANTA INDUSTRIAL"]]:
		var panel:=box(detail_root,"SignPanel",sign_[0],Vector3(5.3,0.85,0.045),rubber)
		panel.rotation.y=sign_[1]
		var label:=Label3D.new();label.text=sign_[2]+"\n"+sign_[3];label.font_size=48;label.pixel_size=0.0045
		label.modulate=Color("c3bda9");label.outline_size=0;label.position=sign_[0]+Vector3(0,0,0.035)
		label.rotation.y=sign_[1];detail_root.add_child(label);count+=2
	# Cable drops and conduits cluster beside machinery rather than blocking routes.
	for z in [78.0,83.0,89.0]:
		box(detail_root,"ServiceConduit",Vector3(34.7,3.4,z),Vector3(0.10,3.8,0.10),steel)
		box(detail_root,"ServiceJunction",Vector3(34.67,1.5,z),Vector3(0.28,0.38,0.22),rubber)
		count+=2
	return {"decorative_meshes":count,"additional_colliders":0,"style":"warm practical lights, cool sky fill, restrained maintenance paint"}

static func box(parent: Node3D, name_: String, point: Vector3, size_: Vector3, material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name_;node.position=point
	var mesh:=BoxMesh.new();mesh.size=size_;node.mesh=mesh;node.material_override=material
	parent.add_child(node);return node
