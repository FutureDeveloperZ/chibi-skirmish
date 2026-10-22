extends Control

const Rules = preload("res://scripts/match.gd")
const Fighter = preload("res://scripts/fighter.gd")
const GOLD := Color("ff183c")
const PALETTES := [Color("ff183c"), Color("25c6e8"), Color("f5be38"), Color("8f87ed"), Color("88b968"), Color("ec83ba")]
const WHITE := Color("e8edf0")
const MUTED := Color("c7bfc0")
const WEAPONS := ["Assault rifle", "Shotgun", "Rocket launcher", "Machine gun", "Sniper rifle", "Submachine gun"]
var game: Node3D
var hud: Control
var backdrop: ColorRect
var accent := PALETTES[0]
var accent_labels: Array[Label] = []
var accent_buttons: Array[Button] = []
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
	backdrop = ColorRect.new()
	backdrop.color = Color.WHITE
	var spectator_shader := Shader.new()
	spectator_shader.code = """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D match_view : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 accent_color : source_color = vec4(0.85, 0.05, 0.2, 1.0);
void fragment() {
	vec3 scene = textureLod(match_view, SCREEN_UV, 1.8).rgb;
	float gray = dot(scene, vec3(0.299, 0.587, 0.114));
	scene = mix(vec3(gray), scene, 0.75) * 0.62;
	bool spectator_area = UV.x * 1440.0 < 1030.0 - UV.y * 694.0;
	float diagonal = UV.x * 1.2 + UV.y * 0.6 - TIME * 0.025;
	float streak = pow(max(0.0, sin(diagonal * 22.0)), 30.0);
	float sweep = pow(max(0.0, sin(diagonal * 4.5)), 12.0);
	vec3 animated_accent = accent_color.rgb * (0.94 + streak * 0.08 + sweep * 0.09);
	COLOR = spectator_area ? vec4(scene, 1.0) : vec4(animated_accent, 1.0);
}
"""
	var spectator_material := ShaderMaterial.new()
	spectator_material.shader = spectator_shader
	backdrop.material = spectator_material
	backdrop.size = Vector2(1440, 900)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	design = Control.new()
	design.size = Vector2(1440, 900)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(design)
	design.draw.connect(draw_backdrop)
	label(design, "CHIBI / SKIRMISH", Vector2(58, 35), 42, WHITE, true).rotation_degrees = -4
	label(design, "SIX OPERATORS. TWO TEAMS. ONE WINNER.", Vector2(64, 103), 15, WHITE)
	label(design, "RELAY YARD  /  03 VS 03", Vector2(1080, 73), 17, WHITE, true)
	var start := banner("START", "Enter the fight", "1", Rect2(185, 231, 364, 104), 18, "start")
	var options := banner("OPTIONS", "Make it yours", "2", Rect2(109, 414, 359, 102), -4, "options")
	var credits := banner("CREDITS", "Meet the makers", "3", Rect2(160, 595, 352, 102), -25, "credits")
	var library := banner("LIBRARY", "Choose your operator", "4", Rect2(935, 338, 426, 112), -17, "library")
	navigation_buttons = {"start": start, "options": options, "credits": credits, "library": library}
	label(design, "FIRST TO 20", Vector2(1065, 598), 33, WHITE, true).rotation_degrees = -8
	label(design, "5-MINUTE ROUNDS", Vector2(1070, 655), 14, WHITE)
	selected_name = label(design, "", Vector2(490, 737), 48, WHITE, true)
	selected_name.size.x = 460
	selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_weapon = label(design, "", Vector2(490, 800), 16, WHITE)
	selected_weapon.size.x = 460
	selected_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_hint = label(design, "Ready for deployment", Vector2(490, 829), 14, MUTED)
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
	backdrop.scale = design.scale
	backdrop.position = design.position


func label(parent: Node, text: String, point: Vector2, size_px: int, color: Color, bold := false) -> Label:
	var node := Label.new()
	node.text = text
	node.position = point
	node.add_theme_font_override("font", load("res://assets/fonts/Menu.ttf") if bold else hud.font)
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	if color == GOLD:
		accent_labels.append(node)
	return node


func action(parent: Node, text: String, rect: Rect2, color: Color, callback: Callable) -> Button:
	var node: Button = hud.button(text, color, callback)
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", hud.display_font)
	node.add_theme_constant_override("outline_size", 0)
	if color == GOLD:
		accent_buttons.append(node)
	parent.add_child(node)
	return node


func page(key: String, title: String, rect: Rect2) -> Control:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style: StyleBoxFlat = hud.panel(Color("111014"), 2, 0)
	style.border_color = Color("ff183c")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	design.add_child(panel)
	label(panel, title, Vector2(26, 22), 28, WHITE, true)
	action(panel, "Back", Rect2(rect.size.x - 98, 23, 74, 36), Color("322b32"), func(): open_screen("home"))
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
	preview = Fighter.new()
	world.add_child(preview)
	preview.setup(0, game.preferences.values.character)
	preview.marker.visible = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.55
	camera.position = Vector3(2.4, 2.1, -5)
	camera.look_at(Vector3(0, 0.83, 0))
	camera.current = true
	var image := TextureRect.new()
	image.position = Vector2(412, 102)
	image.size = Vector2(640, 642)
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
	restart = action(panel, "Restart match", Rect2(26, 170, 314, 44), Color("29262d"), game.restart_match)
	action(panel, "Practice with bots", Rect2(26, 232, 314, 50), GOLD, game.practice)
	action(panel, "Host a match", Rect2(26, 298, 314, 50), Color("29262d"), game.host_match)
	server_address = LineEdit.new()
	server_address.position = Vector2(26, 374)
	server_address.size = Vector2(314, 42)
	server_address.text = "ws://127.0.0.1:8910"
	server_address.add_theme_stylebox_override("normal", hud.panel(Color("08080b"), 2, 10))
	server_address.add_theme_stylebox_override("focus", hud.panel(Color("492333"), 2, 10))
	server_address.add_theme_color_override("font_color", WHITE)
	server_address.text_submitted.connect(game.join_match)
	panel.add_child(server_address)
	action(panel, "Join a match", Rect2(26, 432, 314, 50), Color("29262d"), func(): game.join_match(server_address.text))


func build_library() -> void:
	var panel := page("library", "Library", Rect2(1000, 150, 410, 610))
	label(panel, "Choose an operator for your next match.", Vector2(24, 82), 14, MUTED)
	for index in range(Rules.MODELS.size()):
		var x := 24 + (index % 2) * 184
		var y := 126 + (index / 2) * 148
		var choice := action(panel, "", Rect2(x, y, 176, 136), Color("29262d"), func(): choose_character(index))
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
	apply_palette(index)
	preview.set_character(index)
	preview.rotation.y = deg_to_rad(210.0)
	selected_name.text = Rules.NAMES[index]
	selected_weapon.text = WEAPONS[index] + "  /  Drag to rotate"
	selected_hint.text = "Selected for your next match" if game.playing else "Ready for deployment"
	for choice in range(library_buttons.size()):
		library_buttons[choice].set_pressed_no_signal(choice == index)
		library_buttons[choice].add_theme_stylebox_override("pressed", hud.panel(accent.darkened(0.48), 2, 10))


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
	var black := Color("09090d")
	var paper := Color("faf4e8")
	design.draw_colored_polygon(PackedVector2Array([Vector2(617, 83), Vector2(965, 154), Vector2(1070, 650), Vector2(607, 793), Vector2(468, 525)]), paper)
	design.draw_colored_polygon(PackedVector2Array([Vector2(635, 112), Vector2(907, 184), Vector2(1003, 620), Vector2(630, 751), Vector2(510, 510)]), accent.darkened(0.22))
	for x in range(500, 1020, 15):
		for y in range(160, 740, 15):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), PackedVector2Array([Vector2(635, 112), Vector2(907, 184), Vector2(1003, 620), Vector2(630, 751), Vector2(510, 510)])):
				design.draw_circle(Vector2(x, y), 2, accent.darkened(0.65))
	for ray in [PackedVector2Array([Vector2(570, 315), Vector2(365, 152), Vector2(492, 322)]), PackedVector2Array([Vector2(866, 268), Vector2(1173, 115), Vector2(909, 298)]), PackedVector2Array([Vector2(897, 563), Vector2(1302, 800), Vector2(940, 620)]), PackedVector2Array([Vector2(601, 652), Vector2(345, 834), Vector2(638, 685)])]:
		design.draw_colored_polygon(ray, paper)
	design.draw_colored_polygon(PackedVector2Array([Vector2(512, 754), Vector2(936, 726), Vector2(970, 797), Vector2(495, 814)]), black)
	design.draw_colored_polygon(PackedVector2Array([Vector2(0, 839), Vector2(1440, 839), Vector2(1440, 900), Vector2(0, 900)]), black)


func banner(caption: String, subtitle: String, badge: String, rect: Rect2, angle: float, key: String) -> Button:
	var node := preload("res://scripts/menu_banner.gd").new()
	node.caption = caption
	node.subtitle = subtitle
	node.badge = badge
	node.display_font = load("res://assets/fonts/Menu.ttf")
	node.position = rect.position
	node.size = rect.size
	node.pivot_offset = rect.size / 2
	node.rotation_degrees = angle
	for state in ["normal", "hover", "pressed", "focus"]:
		node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	node.pressed.connect(func(): open_screen(key))
	design.add_child(node)
	return node


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or screen != "home" or not event is InputEventKey or not event.pressed or event.echo:
		return
	var destinations := {KEY_1: "start", KEY_2: "options", KEY_3: "credits", KEY_4: "library"}
	if destinations.has(event.keycode):
		open_screen(destinations[event.keycode])
		get_viewport().set_input_as_handled()


func apply_palette(index: int) -> void:
	accent = PALETTES[index]
	backdrop.material.set_shader_parameter("accent_color", accent.darkened(0.15))
	for button in navigation_buttons.values():
		button.accent = accent
		button.queue_redraw()
	for panel in pages.values():
		panel.get_theme_stylebox("panel").border_color = accent
	for node in accent_labels:
		node.add_theme_color_override("font_color", accent.lightened(0.25))
	for button in accent_buttons:
		for state in ["normal", "hover", "pressed", "focus"]:
			var style: StyleBoxFlat = button.get_theme_stylebox(state)
			style.bg_color = accent.darkened(0.48) if state != "hover" else accent.darkened(0.35)
			style.border_color = WHITE
	design.queue_redraw()
