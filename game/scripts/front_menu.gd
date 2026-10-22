extends Control

const Rules = preload("res://scripts/match.gd")
const Fighter = preload("res://scripts/fighter.gd")
const GOLD := Color("dfb565")
const WHITE := Color("e8edf0")
const MUTED := Color("9baebb")
const WEAPONS := ["Assault rifle", "Shotgun", "Rocket launcher", "Machine gun", "Sniper rifle", "Submachine gun"]
var game: Node3D
var hud: Control
var design: Control
var screen := "home"
var pages: Dictionary = {}
var status: Label
var server_address: LineEdit
var preview_viewport: SubViewport
var preview: Node3D
var preview_actor: Dictionary
var selected_name: Label
var selected_weapon: Label
var selected_hint: Label
var library_buttons: Array[Button] = []
var resume: Button
var restart: Button
var rotating := false
var option_controls: Dictionary = {}
var navigation_buttons: Dictionary = {}


func setup(owner_hud: Control, owner_game: Node3D) -> void:
	hud = owner_hud
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color("101b24")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	design = Control.new()
	design.size = Vector2(1440, 900)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(design)
	design.draw.connect(draw_backdrop)
	label(design, "Chibi Skirmish", Vector2(66, 53), 32, WHITE, true)
	label(design, "3v3 surface combat", Vector2(68, 96), 16, MUTED)
	label(design, "Relay yard / Surface zone 07", Vector2(1064, 66), 14, MUTED)
	var start := action(design, "Start", Rect2(94, 240, 326, 96), GOLD, func(): open_screen("start"))
	start.add_theme_font_size_override("font_size", 42)
	start.alignment = HORIZONTAL_ALIGNMENT_LEFT
	start.pivot_offset = start.size / 2
	start.rotation_degrees = 18
	var options := action(design, "Options", Rect2(76, 414, 282, 76), Color("273945"), func(): open_screen("options"))
	options.add_theme_font_size_override("font_size", 28)
	options.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var credits := action(design, "Credits", Rect2(94, 588, 282, 76), Color("273945"), func(): open_screen("credits"))
	credits.add_theme_font_size_override("font_size", 28)
	credits.alignment = HORIZONTAL_ALIGNMENT_LEFT
	credits.pivot_offset = credits.size / 2
	credits.rotation_degrees = -25
	label(design, "First to 20 eliminations", Vector2(78, 722), 17, WHITE)
	label(design, "5-minute rounds. Bots fill empty slots.", Vector2(78, 751), 14, MUTED)
	var library := action(design, "Library", Rect2(1064, 332, 302, 108), Color("314957"), func(): open_screen("library"))
	library.add_theme_font_size_override("font_size", 32)
	navigation_buttons = {"start": start, "options": options, "credits": credits, "library": library}
	label(design, "Choose your operator", Vector2(1064, 459), 17, WHITE)
	label(design, "6 playable characters", Vector2(1064, 487), 14, MUTED)
	selected_name = label(design, "", Vector2(490, 737), 37, WHITE, true)
	selected_name.size.x = 460
	selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_weapon = label(design, "", Vector2(490, 787), 16, GOLD)
	selected_weapon.size.x = 460
	selected_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_hint = label(design, "Ready for deployment", Vector2(490, 822), 14, MUTED)
	selected_hint.size.x = 460
	selected_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label(design, "WASD move   /   Mouse aim & fire   /   Q grenade   /   Space dodge", Vector2(76, 840), 14, MUTED)
	status = label(design, "", Vector2(76, 787), 14, GOLD)
	status.size = Vector2(335, 45)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_preview()
	build_start()
	build_library()
	build_options()
	build_credits()
	open_screen("home")
	resized.connect(layout)
	layout()
	refresh_selection()


func layout() -> void:
	if not design:
		return
	var factor := minf(size.x / 1440.0, size.y / 900.0)
	design.scale = Vector2.ONE * factor
	design.position = (size - Vector2(1440, 900) * factor) / 2


func label(parent: Node, text: String, point: Vector2, size_px: int, color: Color, bold := false) -> Label:
	var node := Label.new()
	node.text = text
	node.position = point
	node.add_theme_font_override("font", hud.display_font if bold else hud.font)
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func action(parent: Node, text: String, rect: Rect2, color: Color, callback: Callable) -> Button:
	var node: Button = hud.button(text, color, callback)
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", hud.display_font)
	node.add_theme_constant_override("outline_size", 0)
	parent.add_child(node)
	return node


func page(key: String, title: String, rect: Rect2) -> Control:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = hud.panel(Color("182832"), 2, 0)
	style.border_color = Color("536772")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	design.add_child(panel)
	label(panel, title, Vector2(26, 22), 28, WHITE, true)
	action(panel, "Back", Rect2(rect.size.x - 98, 23, 74, 36), Color("314552"), func(): open_screen("home"))
	pages[key] = panel
	return panel


func build_preview() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(640, 680)
	preview_viewport.transparent_bg = true
	preview_viewport.own_world_3d = true
	preview_viewport.gui_disable_input = true
	preview_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(preview_viewport)
	var world := Node3D.new()
	preview_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b1c4d3")
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 0.8
	world.add_child(light)
	var pedestal := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.12
	mesh.bottom_radius = 1.2
	mesh.height = 0.16
	mesh.radial_segments = 64
	pedestal.mesh = mesh
	pedestal.position.y = -0.06
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("354651")
	metal.metallic = 0.5
	metal.roughness = 0.65
	pedestal.material_override = metal
	world.add_child(pedestal)
	preview = Fighter.new()
	world.add_child(preview)
	preview.setup(0, game.preferences.values.character)
	preview.marker.visible = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.35
	camera.position = Vector3(2.4, 2.1, -5)
	camera.look_at(Vector3(0, 0.83, 0))
	camera.current = true
	var image := TextureRect.new()
	image.position = Vector2(424, 130)
	image.size = Vector2(592, 606)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = preview_viewport.get_texture()
	image.mouse_default_cursor_shape = Control.CURSOR_DRAG
	image.gui_input.connect(rotate_preview)
	design.add_child(image)
	preview_actor = Rules.new().actors[0].duplicate()
	preview_actor.p = Vector2.ZERO
	preview_actor.aim = Vector2(0, 1)
	preview_actor.protection = 0.0


func rotate_preview(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		rotating = event.pressed
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		preview.rotation.y += event.relative.x * 0.012


func build_start() -> void:
	var panel := page("start", "Start", Rect2(62, 185, 366, 545))
	label(panel, "Deploy your selected operator.", Vector2(26, 80), 15, MUTED)
	resume = action(panel, "Resume match", Rect2(26, 116, 314, 44), GOLD, func(): hud.show_menu(false))
	restart = action(panel, "Restart match", Rect2(26, 170, 314, 44), Color("314957"), game.restart_match)
	action(panel, "Practice with bots", Rect2(26, 232, 314, 50), GOLD, game.practice)
	action(panel, "Host a match", Rect2(26, 298, 314, 50), Color("314957"), game.host_match)
	server_address = LineEdit.new()
	server_address.position = Vector2(26, 374)
	server_address.size = Vector2(314, 42)
	server_address.text = "ws://127.0.0.1:8910"
	server_address.add_theme_stylebox_override("normal", hud.panel(Color("0e1c25"), 2, 10))
	server_address.add_theme_stylebox_override("focus", hud.panel(Color("304754"), 2, 10))
	server_address.add_theme_color_override("font_color", WHITE)
	server_address.text_submitted.connect(game.join_match)
	panel.add_child(server_address)
	action(panel, "Join a match", Rect2(26, 432, 314, 50), Color("314957"), func(): game.join_match(server_address.text))


func build_library() -> void:
	var panel := page("library", "Library", Rect2(1000, 150, 410, 610))
	label(panel, "Choose an operator for your next match.", Vector2(24, 82), 14, MUTED)
	for index in range(Rules.MODELS.size()):
		var x := 24 + (index % 2) * 184
		var y := 126 + (index / 2) * 148
		var choice := action(panel, "", Rect2(x, y, 176, 136), Color("253b48"), func(): choose_character(index))
		choice.toggle_mode = true
		var texture: Texture2D = hud.portraits[index]
		choice.draw.connect(func(): choice.draw_texture_rect(texture, Rect2(10, 8, 74, 74), false))
		label(choice, Rules.NAMES[index], Vector2(11, 87), 19, WHITE, true)
		label(choice, WEAPONS[index], Vector2(11, 113), 12, MUTED)
		library_buttons.append(choice)


func choose_character(index: int) -> void:
	game.select_character(index)
	refresh_selection()


func refresh_selection() -> void:
	var index: int = game.preferences.values.character
	preview.set_character(index)
	preview.rotation.y = deg_to_rad(120.0)
	selected_name.text = Rules.NAMES[index]
	selected_weapon.text = WEAPONS[index] + "  /  Drag to rotate"
	selected_hint.text = "Selected for your next match" if game.playing else "Ready for deployment"
	for choice in range(library_buttons.size()):
		library_buttons[choice].set_pressed_no_signal(choice == index)
		library_buttons[choice].add_theme_stylebox_override("pressed", hud.panel(Color("53604e"), 2, 10))


func build_options() -> void:
	var panel := page("options", "Options", Rect2(62, 185, 366, 545))
	label(panel, "Changes are saved automatically.", Vector2(26, 82), 14, MUTED)
	for row in range(4):
		var key: String = ["fullscreen", "shadows", "minimap", "names"][row]
		var check := CheckButton.new()
		check.text = ["Fullscreen", "Environment shadows", "Show minimap", "Show operator names"][row]
		check.position = Vector2(26, 128 + row * 58)
		check.size = Vector2(314, 46)
		check.button_pressed = game.preferences.values[key]
		check.add_theme_color_override("font_color", WHITE)
		check.toggled.connect(func(value): update_option(key, value))
		panel.add_child(check)
		option_controls[key] = check
	label(panel, "Camera zoom", Vector2(26, 384), 17, WHITE)
	var slider := HSlider.new()
	slider.position = Vector2(26, 424)
	slider.size = Vector2(250, 28)
	slider.min_value = 16
	slider.max_value = 30
	slider.step = 1
	slider.value = game.preferences.values.camera_zoom
	var value_label := label(panel, str(int(slider.value)), Vector2(292, 425), 17, GOLD)
	slider.value_changed.connect(func(value):
		value_label.text = str(int(value))
		update_option("camera_zoom", float(value)))
	panel.add_child(slider)
	option_controls.camera_zoom = slider
	label(panel, "Scroll during a match to adjust the view.", Vector2(26, 481), 13, MUTED)


func update_option(key: String, value: Variant) -> void:
	game.preferences.values[key] = value
	game.apply_preferences()
	game.save_preferences()


func build_credits() -> void:
	var panel := page("credits", "Credits", Rect2(62, 185, 366, 545))
	var entries := [
		["Project", "FutureDeveloperZ"],
		["Original characters & artwork", "GODDESS OF VICTORY: NIKKE / SHIFT UP"],
		["Models & animation archive", "NKAS / skuqre"],
		["Portraits & weapon icons", "NKAS / Nikke-db"],
		["Engine", "Godot Engine"],
		["Typeface", "Fira Sans / SIL Open Font License"],
	]
	for row in range(entries.size()):
		label(panel, entries[row][0], Vector2(26, 88 + row * 65), 13, MUTED)
		label(panel, entries[row][1], Vector2(26, 110 + row * 65), 14, WHITE)


func open_screen(key: String) -> void:
	screen = key
	for page_key in pages:
		pages[page_key].visible = page_key == key
	resume.visible = game.playing
	restart.visible = game.playing and game.authority and game.state.winner != -2
	if key == "library":
		refresh_selection()
	if key != "home":
		pages[key].move_to_front()


func set_menu_visible(value: bool) -> void:
	visible = value
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if value:
		open_screen("home")
		refresh_selection()


func _process(delta: float) -> void:
	if not visible or preview_actor.is_empty():
		return
	preview_actor.character = game.preferences.values.character
	preview.update_state(preview_actor, delta, false)
	preview.marker.visible = false


func draw_backdrop() -> void:
	for index in range(3):
		design.draw_texture_rect(hud.portraits[index], Rect2(1064 + index * 68, 528, 58, 58), false)
	for x in range(450, 1030, 60):
		design.draw_line(Vector2(x, 154), Vector2(x, 729), Color("1c2b35"), 1)
	for y in range(154, 730, 60):
		design.draw_line(Vector2(440, y), Vector2(1010, y), Color("1c2b35"), 1)
	design.draw_arc(Vector2(720, 455), 220, 0.2, 2.9, 80, Color("344956"), 2, true)
	design.draw_arc(Vector2(720, 455), 238, 3.4, 5.8, 80, Color("293b48"), 1, true)
	design.draw_line(Vector2(76, 155), Vector2(1366, 155), Color("3d515f"), 1)
	design.draw_line(Vector2(76, 173), Vector2(190, 173), GOLD, 3)
