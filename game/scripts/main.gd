extends Node3D

const Rules = preload("res://scripts/match.gd")
const Arena = preload("res://scripts/arena.gd")
const Fighter = preload("res://scripts/fighter.gd")
const Hud = preload("res://scripts/hud.gd")
const PORT := 8910
const SLOT_ORDER := [0, 3, 1, 4, 2, 5]

var simulation := Rules.new()
var state: Dictionary = {}
var controls: Dictionary = {}
var input_times: Dictionary = {}
var peer_slots: Dictionary = {}
var local_slot := -1
var mode := "Practice"
var playing := false
var authority := true
var dedicated := false
var headless := false
var camera: Camera3D
var hud: Control
var fighters: Array[Node3D] = []
var projectile_nodes: Dictionary = {}
var effects: Array[Dictionary] = []
var snapshot_clock := 0.0
var input_clock := 0.0
var last_event := 0
var snapshots_received := 0
var test_client := false
var test_clock := 0.0
var capture_path := ""
var camera_focus := Vector3.ZERO
var camera_zoom := 21.0
var round_end_clock := 0.0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	var args := OS.get_cmdline_user_args()
	dedicated = "--server" in args
	test_client = "--test-client" in args
	multiplayer.server_relay = false
	setup_input()
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): print("Connected; waiting for slot"))
	multiplayer.connection_failed.connect(func(): connection_error("Could not connect. Check the address and that the host is running."))
	multiplayer.server_disconnected.connect(func(): connection_error("The host disconnected. You can start practice or join another match."))
	state = simulation.snapshot()
	if not headless and not dedicated:
		add_child(Arena.new())
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = camera_zoom
		camera.position = Vector3(3.0, 25.0, 21.5)
		add_child(camera)
		camera.look_at(Vector3(0, 0, 0))
		camera.current = true
		for slot in range(6):
			var fighter := Fighter.new()
			add_child(fighter)
			fighter.setup(slot)
			fighters.append(fighter)
		var layer := CanvasLayer.new()
		add_child(layer)
		hud = Hud.new()
		layer.add_child(hud)
		hud.setup(self)
	if dedicated:
		host_match(true)
	else:
		for arg in args:
			if arg.begins_with("--join="):
				join_match(arg.trim_prefix("--join="))
			if arg.begins_with("--capture="):
				capture_path = arg.trim_prefix("--capture=")
		if "--host" in args:
			host_match()
		elif "--play" in args:
			practice()
	if not capture_path.is_empty():
		capture.call_deferred()


func setup_input() -> void:
	var bindings := {"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
		"up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"grenade": [KEY_Q], "dodge": [KEY_SPACE]}
	for action in bindings:
		InputMap.add_action(action)
		for key in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func practice() -> void:
	close_network()
	simulation = Rules.new()
	simulation.actors[0].peer = 1
	local_slot = 0
	mode = "Practice"
	playing = true
	state = simulation.snapshot()
	if hud:
		hud.show_menu(false)


func host_match(server_only: bool = false) -> void:
	close_network()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(PORT)
	if error != OK:
		connection_error("Port %d is unavailable. Close the other host and try again." % PORT)
		return
	multiplayer.multiplayer_peer = peer
	simulation = Rules.new()
	authority = true
	playing = true
	mode = "Hosting"
	local_slot = -1 if server_only else 0
	if not server_only:
		peer_slots[1] = 0
		simulation.actors[0].peer = 1
	state = simulation.snapshot()
	print("SERVER_READY port=%d" % PORT)
	if hud:
		hud.show_menu(false)


func join_match(address: String) -> void:
	address = address.strip_edges()
	if not (address.begins_with("ws://") or address.begins_with("wss://")):
		if hud:
			hud.set_status("Enter a ws:// or wss:// server address.")
		return
	close_network()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(address)
	if error != OK:
		connection_error("Invalid server address.")
		return
	multiplayer.multiplayer_peer = peer
	authority = false
	playing = false
	mode = "Connecting"
	local_slot = -1
	if hud:
		hud.set_status("Connecting to the arena…")


func close_network() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer_slots.clear()
	controls.clear()
	input_times.clear()
	authority = true
	playing = false
	local_slot = -1
	last_event = 0
	round_end_clock = 0.0
	for projectile in projectile_nodes.values():
		projectile.queue_free()
	projectile_nodes.clear()
	for effect in effects:
		effect.node.queue_free()
	effects.clear()


func connection_error(message: String) -> void:
	close_network()
	simulation = Rules.new()
	state = simulation.snapshot()
	mode = "Practice"
	push_warning(message)
	if hud:
		hud.show_menu(true)
		hud.set_status(message)


func on_peer_connected(id: int) -> void:
	if not authority:
		return
	for slot in SLOT_ORDER:
		if not peer_slots.values().has(slot):
			peer_slots[id] = slot
			simulation.actors[slot].peer = id
			assign_slot.rpc_id(id, slot)
			print("PLAYER_JOINED peer=%d slot=%d" % [id, slot])
			return
	multiplayer.multiplayer_peer.disconnect_peer(id, true)


func on_peer_disconnected(id: int) -> void:
	if authority and peer_slots.has(id):
		var slot: int = peer_slots[id]
		simulation.actors[slot].peer = 0
		controls.erase(slot)
		input_times.erase(slot)
		peer_slots.erase(id)
		print("PLAYER_LEFT slot=%d; bot took over" % slot)


@rpc("authority", "call_remote", "reliable")
func assign_slot(slot: int) -> void:
	local_slot = slot
	playing = true
	mode = "Online"
	print("PLAYER_ASSIGNED slot=%d" % slot)
	if hud:
		hud.show_menu(false)


@rpc("any_peer", "call_remote", "reliable")
func submit_input(move: Vector2, aim: Vector2, fire: bool, grenade: bool, dash: bool) -> void:
	if not authority:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not peer_slots.has(sender):
		return
	var slot: int = peer_slots[sender]
	var now := Time.get_ticks_msec() / 1000.0
	if now - input_times.get(slot, -100.0) < 0.015:
		return
	controls[slot] = simulation.sanitize(move, aim, fire, grenade, dash)
	input_times[slot] = now


@rpc("authority", "call_remote", "reliable")
func receive_state(snapshot: Dictionary) -> void:
	if authority:
		return
	state = snapshot
	snapshots_received += 1


func _physics_process(delta: float) -> void:
	if authority and playing:
		if dedicated and peer_slots.is_empty():
			round_end_clock = 0.0
			if simulation.elapsed > 0:
				simulation.reset()
				state = simulation.snapshot()
			return
		if dedicated and simulation.winner != -2:
			round_end_clock += delta
			if round_end_clock > 10.0:
				simulation.reset()
				round_end_clock = 0.0
		var now := Time.get_ticks_msec() / 1000.0
		for slot in input_times:
			if now - input_times[slot] > 0.3:
				controls.erase(slot)
		if local_slot >= 0:
			controls[local_slot] = read_controls()
		simulation.step(delta, controls)
		state = simulation.snapshot()
		snapshot_clock += delta
		if snapshot_clock >= 0.05:
			snapshot_clock = 0.0
			var sockets := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
			if sockets:
				for id in peer_slots:
					if id != 1 and sockets.get_peer(id).get_ready_state() == WebSocketPeer.STATE_OPEN:
						receive_state.rpc_id(id, state)
	elif not authority and playing and local_slot >= 0:
		input_clock += delta
		if input_clock >= 0.033:
			input_clock = 0.0
			var input := read_controls()
			submit_input.rpc_id(1, input.get("move", Vector2.ZERO), input.get("aim", Vector2.ZERO),
				input.get("fire", false), input.get("grenade", false), input.get("dash", false))
	if test_client:
		test_clock += delta
		if test_clock > 4.0:
			if local_slot >= 0 and snapshots_received > 20:
				print("TEST_CLIENT_OK slot=%d snapshots=%d" % [local_slot, snapshots_received])
				get_tree().quit(0)
			else:
				push_error("TEST_CLIENT_FAILED assignment or state missing")
				get_tree().quit(1)


func read_controls() -> Dictionary:
	if local_slot < 0 or state.is_empty():
		return {}
	var actor: Dictionary = state.actors[local_slot]
	if test_client:
		return simulation.bot_input(actor)
	if not camera or (hud and hud.menu_visible):
		return {}
	var keys := Input.get_vector("left", "right", "up", "down")
	var right := Vector2(camera.global_basis.x.x, camera.global_basis.x.z).normalized()
	var down := Vector2(camera.global_basis.z.x, camera.global_basis.z.z).normalized()
	var movement := right * keys.x + down * keys.y
	var mouse := get_viewport().get_mouse_position()
	var plane := Plane(Vector3.UP, 0.65)
	var hit = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	var aim: Vector2 = actor.p + actor.aim
	if hit != null:
		aim = Vector2(hit.x, hit.z)
	return simulation.sanitize(movement, aim, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		Input.is_action_pressed("grenade"), Input.is_action_pressed("dodge"))


func restart_match() -> void:
	if authority:
		simulation.reset()
		state = simulation.snapshot()
		if hud:
			hud.show_menu(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and hud:
		hud.show_menu(not hud.menu_visible)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom = maxf(16.0, camera_zoom - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom = minf(30.0, camera_zoom + 1.0)


func _process(delta: float) -> void:
	if headless or dedicated or state.is_empty():
		return
	for index in range(fighters.size()):
		fighters[index].update_state(state.actors[index], delta, index == local_slot)
	var focus_target := Vector3.ZERO
	if local_slot >= 0:
		focus_target = fighters[local_slot].position
		focus_target.x = clampf(focus_target.x, -21, 21)
		focus_target.z = clampf(focus_target.z, -12.5, 12.5)
	camera_focus = camera_focus.lerp(focus_target, 1.0 - exp(-7.0 * delta))
	camera.position = camera_focus + Vector3(3.0, 25.0, 21.5)
	camera.look_at(camera_focus)
	camera.size = lerpf(camera.size, camera_zoom, 1.0 - exp(-8.0 * delta))
	update_projectiles(delta)
	for event in state.events:
		if event.id > last_event:
			last_event = event.id
			if event.kind == "blast":
				add_blast(event.p, event.team)
	for index in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		effect.time -= delta
		if effect.time <= 0:
			effect.node.queue_free()
			effects.remove_at(index)
		else:
			effect.node.scale = Vector3.ONE * (1.0 + (1.0 - effect.time / 0.45) * 5.0)
	if hud:
		hud.queue_redraw()


func update_projectiles(delta: float) -> void:
	var live: Dictionary = {}
	for bullet in state.bullets:
		live[bullet.id] = true
		if not projectile_nodes.has(bullet.id):
			var node := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.16 if bullet.grenade else 0.07
			mesh.height = mesh.radius * 2
			mesh.radial_segments = 8
			mesh.rings = 4
			node.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color("ffbe64") if bullet.grenade else (Arena.BLUE if bullet.team == 0 else Arena.RED)
			node.material_override = mat
			node.scale = Vector3.ONE if bullet.grenade else Vector3(1, 1, 4.0)
			add_child(node)
			node.position = Vector3(bullet.p.x, 0.75, bullet.p.y)
			projectile_nodes[bullet.id] = node
		var projectile: MeshInstance3D = projectile_nodes[bullet.id]
		var height: float = 0.75 + (sin(minf(1.0, bullet.life / maxf(0.01, bullet.life + bullet.ttl)) * PI) * 2.0 if bullet.grenade else 0.0)
		projectile.position = projectile.position.lerp(Vector3(bullet.p.x, height, bullet.p.y), 1 - exp(-35 * delta))
		projectile.rotation.y = atan2(bullet.dir.x, bullet.dir.y)
	for id in projectile_nodes.keys():
		if not live.has(id):
			projectile_nodes[id].queue_free()
			projectile_nodes.erase(id)


func add_blast(point: Vector2, team: int) -> void:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.35
	mesh.outer_radius = 0.48
	mesh.rings = 32
	mesh.ring_segments = 6
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Arena.BLUE if team == 0 else Arena.RED
	node.material_override = mat
	node.position = Vector3(point.x, 0.14, point.y)
	add_child(node)
	effects.append({"node": node, "time": 0.45})


func capture() -> void:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE_SAVED ", error, " ", capture_path)
	get_tree().quit(0 if error == OK else 1)
