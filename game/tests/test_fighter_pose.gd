extends SceneTree

const Rules = preload("res://scripts/match.gd")
const Fighter = preload("res://scripts/fighter.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


# Evaluate the actual deformed vertices, independently of the model's static AABB.
func floor_height(fighter: Node3D) -> float:
	var lowest := INF
	for mesh in fighter.model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.skin:
			continue
		var skeleton: Skeleton3D = mesh.get_node(mesh.skeleton)
		var poses: Array[Transform3D] = []
		for bind in range(mesh.skin.get_bind_count()):
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			poses.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			for vertex in range(arrays[Mesh.ARRAY_VERTEX].size()):
				var point := Vector3.ZERO
				for joint in range(4):
					var index: int = vertex * 4 + joint
					point += (poses[arrays[Mesh.ARRAY_BONES][index]] * arrays[Mesh.ARRAY_VERTEX][vertex]) * arrays[Mesh.ARRAY_WEIGHTS][index]
				lowest = minf(lowest, point.y)
	return lowest


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var simulation := Rules.new()
	var fighters: Array[Node3D] = []
	for slot in range(6):
		var fighter := Fighter.new()
		world.add_child(fighter)
		fighter.setup(slot)
		fighters.append(fighter)
		var actor: Dictionary = simulation.actors[slot]
		actor.p = Vector2((slot - 2.5) * 3.3, -5)
		actor.move = Vector2.ZERO
		for direction in [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]:
			actor.aim = direction
			fighter.update_state(actor, 1.0, true)
			var forward := -fighter.model.global_basis.z.normalized()
			check(forward.dot(Vector3(direction.x, 0, direction.y)) > 0.999, "%s must face its aim" % Rules.NAMES[slot])
		fighter.animation.seek(0.0, true)
		check(floor_height(fighter) > 0.02, "%s idle pose must stand above the floor" % Rules.NAMES[slot])
		var heading: float = fighter.model.rotation.y
		actor.hp = 0
		actor.aim = -actor.aim
		actor.respawn = 4.0
		fighter.update_state(actor, 0.0, true)
		check(not fighter.selection.visible, "Dead fighters must not retain the selection ring")
		# Cover the complete death clip, including the previously hidden final fall.
		for frame in range(180):
			actor.respawn = 4.0 - frame / 60.0
			fighter.update_state(actor, 1.0 / 60.0, true)
			if frame % 3 == 0:
				var low := floor_height(fighter)
				check(low >= 0.015, "%s death frame %d clips below the floor: %.3f" % [Rules.NAMES[slot], frame, low])
		check(is_equal_approx(fighter.model.rotation.y, heading), "Dead fighters must keep their death heading")
		check(fighter.model.visible, "The full death animation and corpse must remain visible")
		actor.hp = 100
		actor.respawn = 0
		fighter.update_state(actor, 1.0, true)
		check(is_equal_approx(fighter.model.position.y, fighter.standing_height), "Respawning must clear the death lift")
		# Leave a grounded fallen pose for the optional visual check.
		actor.hp = 0
		actor.respawn = 2.2
		for frame in range(108):
			fighter.update_state(actor, 1.0 / 60.0, false)
	if DisplayServer.get_name() != "headless":
		world.add_child(load("res://scripts/arena.gd").new())
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 17
		camera.position = Vector3(0, 15, 10)
		camera.look_at(Vector3(0, 0, -5))
		camera.current = true
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/chibi-grounded-deaths.png")
	print("FIGHTER_POSE_TESTS ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
