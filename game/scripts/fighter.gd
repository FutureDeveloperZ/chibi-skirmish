extends Node3D

const Rules = preload("res://scripts/match.gd")
const BLUE := Color("28b8e6")
const RED := Color("f87978")
var slot := 0
var model: Node3D
var animation: AnimationPlayer
var marker: MeshInstance3D
var selection: MeshInstance3D
var current_clip := ""
var target_position := Vector3.ZERO
var health := 100.0
var initialized := false
var standing_height := 0.0
var death_lift := Curve.new()
var skin_surfaces: Array[Dictionary] = []


func setup(index: int) -> void:
	slot = index
	var scene = load("res://assets/characters/%s.glb" % Rules.MODELS[slot])
	model = scene.instantiate()
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0]
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in animation.get_animation_list():
			if clip in ["idle", "run", "walk"]:
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	# Bind-pose mesh AABBs do not describe the animated characters' actual feet.
	for child in model.find_children("*", "MeshInstance3D", true, false):
		if not child.skin:
			continue
		var skeleton: Skeleton3D = child.get_node(child.skeleton)
		var bones: Array[int] = []
		for bind in range(child.skin.get_bind_count()):
			bones.append(skeleton.find_bone(child.skin.get_bind_name(bind)))
		for surface in range(child.mesh.get_surface_count()):
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			skin_surfaces.append({"skeleton": skeleton, "skin": child.skin, "bones": bones,
				"vertices": arrays[Mesh.ARRAY_VERTEX], "joints": arrays[Mesh.ARRAY_BONES],
				"weights": arrays[Mesh.ARRAY_WEIGHTS]})
	animation.play("idle")
	animation.seek(0.0, true)
	var bounds := visual_bounds()
	var factor := 1.8 / maxf(bounds.size.y, 0.1)
	standing_height = 0.08 - bounds.position.y * factor
	# Sample once at spawn, then use the curve instead of skinning vertices every frame.
	var death := animation.get_animation("death")
	death_lift.max_domain = death.length
	death_lift.max_value = 10.0
	animation.play("death")
	for frame in range(ceili(death.length * 60.0) + 1):
		var time := minf(frame / 60.0, death.length)
		animation.seek(time, true)
		death_lift.add_point(Vector2(time, maxf(0.0, bounds.position.y - visual_bounds().position.y) * factor))
	animation.play("idle")
	animation.seek(0.0, true)
	model.scale = Vector3.ONE * factor
	model.position.y = standing_height
	marker = make_ring(0.45, 0.055, BLUE if slot < 3 else RED)
	selection = make_ring(0.61, 0.035, Color("fffef2"))
	selection.visible = false
	play("idle")
	skin_surfaces.clear()


func visual_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for surface in skin_surfaces:
		var skeleton: Skeleton3D = surface.skeleton
		var skin: Skin = surface.skin
		var poses: Array[Transform3D] = []
		var relative := model.global_transform.affine_inverse() * skeleton.global_transform
		for bind in range(skin.get_bind_count()):
			poses.append(relative * skeleton.get_bone_global_pose(surface.bones[bind]) * skin.get_bind_pose(bind))
		for vertex in range(surface.vertices.size()):
			var point := Vector3.ZERO
			for joint in range(4):
				var index: int = vertex * 4 + joint
				if surface.weights[index] > 0:
					point += (poses[surface.joints[index]] * surface.vertices[vertex]) * surface.weights[index]
			bounds = AABB(point, Vector3.ZERO) if first else bounds.expand(point)
			first = false
	return bounds


func make_ring(radius: float, width: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.mesh = mesh
	node.material_override = material
	node.position.y = 0.10
	add_child(node)
	return node


func update_state(actor: Dictionary, delta: float, local: bool) -> void:
	target_position = Vector3(actor.p.x, 0, actor.p.y)
	if not initialized or position.distance_to(target_position) > 4:
		position = target_position
		initialized = true
	else:
		position = position.lerp(target_position, 1.0 - exp(-22.0 * delta))
	health = actor.hp
	selection.visible = local and health > 0
	marker.visible = health > 0
	model.visible = true
	var facing: Vector2 = actor.aim
	if health > 0:
		# Imported characters look along -Z; gameplay directions use X/Z coordinates.
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-facing.x, -facing.y), 1.0 - exp(-16.0 * delta))
	if health <= 0:
		play("death")
	elif Vector2(actor.move).length() > 0.1:
		play("run")
	elif actor.fired > 0:
		play("shot")
	else:
		play("idle")
	animation.advance(delta)
	model.position.y = standing_height + (death_lift.sample(animation.current_animation_position) if health <= 0 else 0.0)
	if actor.protection > 0:
		marker.scale = Vector3.ONE * (1.15 + sin(Time.get_ticks_msec() * 0.008) * 0.1)
	else:
		marker.scale = Vector3.ONE


func play(clip: String) -> void:
	if animation and current_clip != clip and animation.has_animation(clip):
		animation.play(clip, 0.12)
		current_clip = clip
