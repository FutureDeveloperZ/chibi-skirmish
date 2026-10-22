extends Node3D

const Rules = preload("res://scripts/match.gd")
const BLUE := Color("28b8e6")
const RED := Color("f87978")
static var pose_cache: Dictionary = {}
var slot := 0
var character := -1
var model: Node3D
var animation: AnimationPlayer
var marker: MeshInstance3D
var selection: MeshInstance3D
var aim_skeleton: Skeleton3D
var weapon_bone := -1
var head_bone := -1
var eye_bones: Array[int] = []
var aim_heading := 0.0
var current_clip := ""
var target_position := Vector3.ZERO
var health := 100.0
var initialized := false
var standing_height := 0.0
var death_lift := Curve.new()
var skin_surfaces: Array[Dictionary] = []


func setup(index: int, character_index: int = -1) -> void:
	slot = index
	set_character(index if character_index < 0 else character_index)
	marker = make_ring(0.45, 0.055, BLUE if slot < 3 else RED)
	selection = make_ring(0.61, 0.035, Color("fffef2"))
	selection.visible = false


func set_character(index: int) -> void:
	if character == index and model:
		return
	if model:
		remove_child(model)
		model.queue_free()
	character = clampi(index, 0, Rules.MODELS.size() - 1)
	current_clip = ""
	death_lift = Curve.new()
	var scene = load("res://assets/characters/%s.glb" % Rules.MODELS[character])
	model = scene.instantiate()
	add_child(model)
	aim_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	weapon_bone = aim_skeleton.find_bone("Bip001 Prop1")
	head_bone = aim_skeleton.find_bone("Bip001 Head")
	eye_bones = [aim_skeleton.find_bone("eyeL_bone01"), aim_skeleton.find_bone("eyeR_bone01")]
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animation = players[0]
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in animation.get_animation_list():
			if clip in ["idle", "run", "walk"]:
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	build_running_shot()
	if pose_cache.has(character):
		var cached: Dictionary = pose_cache[character]
		standing_height = cached.height
		death_lift = cached.lift
		model.scale = Vector3.ONE * cached.factor
		model.position.y = standing_height
		play("idle")
		return
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
	pose_cache[character] = {"height": standing_height, "factor": factor, "lift": death_lift}
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
	if actor.get("character", slot) != character:
		set_character(actor.get("character", slot))
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
		aim_heading = lerp_angle(aim_heading, atan2(-facing.x, -facing.y), 1.0 - exp(-16.0 * delta))
	if health <= 0:
		play("death")
	elif actor.fired > 0 or actor.fire_cd > 0:
		play("run_shot" if Vector2(actor.move).length() > 0.1 else "shot")
	elif Vector2(actor.move).length() > 0.1:
		play("run")
	else:
		play("idle")
	animation.advance(delta)
	if health > 0:
		# Viewer-facing offsets differ per clip. Align the animated weapon's barrel
		# axis, including animation blends, rather than assuming a model forward axis.
		var weapon_basis := aim_skeleton.global_basis * aim_skeleton.get_bone_global_pose(weapon_bone).basis
		var pose_forward := weapon_basis.y
		if current_clip == "run":
			# Running clips carry the gun across the body; face along the head instead.
			var eyes := (aim_skeleton.get_bone_global_pose(eye_bones[0]).origin + aim_skeleton.get_bone_global_pose(eye_bones[1]).origin) * 0.5
			pose_forward = aim_skeleton.global_basis * (eyes - aim_skeleton.get_bone_global_pose(head_bone).origin)
		var local_barrel := model.global_basis.inverse() * pose_forward
		var pose_heading := atan2(-local_barrel.x, -local_barrel.z)
		model.rotation.y = aim_heading - pose_heading
	model.position.y = standing_height + (death_lift.sample(animation.current_animation_position) if health <= 0 else 0.0)
	if actor.protection > 0:
		marker.scale = Vector3.ONE * (1.15 + sin(Time.get_ticks_msec() * 0.008) * 0.1)
	else:
		marker.scale = Vector3.ONE


func play(clip: String) -> void:
	if animation and current_clip != clip and animation.has_animation(clip):
		animation.play(clip, 0.12)
		current_clip = clip


func build_running_shot() -> void:
	if animation.has_animation("run_shot"):
		return
	# Keep the running pelvis and legs, with the shooting torso, arms, and weapon.
	# A native clip keeps playback and crossfades on the existing AnimationPlayer.
	var running: Animation = animation.get_animation("run")
	var shooting: Animation = animation.get_animation("shot")
	var combined: Animation = running.duplicate()
	for track in range(combined.get_track_count() - 1, -1, -1):
		if not lower_body_track(combined.track_get_path(track)):
			combined.remove_track(track)
	var time_scale := running.length / shooting.length
	for track in range(shooting.get_track_count()):
		if lower_body_track(shooting.track_get_path(track)):
			continue
		shooting.copy_track(track, combined)
		var copied := combined.get_track_count() - 1
		var keys := combined.track_get_key_count(copied)
		# Scale from the outer end so moving a key cannot reorder the next index.
		for step in range(keys):
			var key := keys - 1 - step if time_scale > 1.0 else step
			combined.track_set_key_time(copied, key, combined.track_get_key_time(copied, key) * time_scale)
	combined.loop_mode = Animation.LOOP_LINEAR
	animation.get_animation_library("").add_animation("run_shot", combined)


func lower_body_track(path: NodePath) -> bool:
	var bone_path := str(path)
	for part in ["Pelvis", "Thigh", "Calf", "Foot", "Toe"]:
		if part in bone_path:
			return true
	return false
