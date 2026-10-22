extends SceneTree

var failures := 0
const Preferences = preload("res://scripts/preferences.gd")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func click(control: Control) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size / 2)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var menu = game.hud.menu
	check(menu.visible and menu.screen == "home", "The home menu must open on launch")
	check(menu.library_buttons.size() == 6, "The library must expose six playable operators")
	check(menu.navigation_buttons.start.rotation_degrees > 0 and menu.navigation_buttons.credits.rotation_degrees < 0, "Navigation must fan diagonally around the character")
	for page in ["start", "options", "credits", "library"]:
		menu.open_screen("home")
		await click(menu.navigation_buttons[page])
		check(menu.screen == page, "The transformed %s button must accept clicks" % page)
	menu.open_screen("home")
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_4
	shortcut.pressed = true
	root.push_input(shortcut, true)
	await process_frame
	check(menu.screen == "library", "Number badges must open the corresponding menu")
	menu.open_screen("library")
	check(menu.pages.library.visible and not menu.pages.options.visible, "Library navigation must show only its page")
	for character in range(6):
		menu.library_buttons[character].pressed.emit()
		await process_frame
		check(game.preferences.values.character == character, "Library click must update the selected character")
		check(menu.accent == menu.PALETTES[character] and menu.backdrop.color == menu.accent.darkened(0.15), "Character selection must recolor the backdrop")
		check(menu.navigation_buttons.start.accent == menu.accent, "Menu banners must use the selected character palette")
		check(menu.preview.character == character, "Library click must update the 3D preview")
		check(menu.selected_name.text == game.Rules.NAMES[character], "The preview name must match the model")
		check(menu.library_buttons[character].button_pressed, "The chosen card must stay highlighted")
	var loaded := Preferences.new()
	loaded.read()
	check(loaded.values.character == 5, "Character selection must survive loading preferences")
	menu.open_screen("options")
	menu.option_controls.minimap.button_pressed = false
	menu.option_controls.names.button_pressed = false
	menu.option_controls.shadows.button_pressed = false
	menu.option_controls.camera_zoom.value = 25
	check(not game.preferences.values.minimap and not game.preferences.values.names, "Display options must update")
	check(game.camera_zoom == 25, "The zoom slider must change the actual camera setting")
	for light in game.arena.find_children("*", "DirectionalLight3D", true, false):
		check(not light.shadow_enabled, "The shadow setting must affect the world")
	loaded.read()
	check(loaded.values.camera_zoom == 25.0 and not loaded.values.shadows, "Options must persist")
	menu.open_screen("credits")
	check(menu.pages.credits.visible, "Credits must open")
	menu.open_screen("library")
	menu.library_buttons[1].pressed.emit()
	menu.open_screen("start")
	var practice: Button
	for node in menu.pages.start.find_children("*", "Button", true, false):
		if node.text == "Practice with bots":
			practice = node
	check(practice != null, "Start must provide a working practice button")
	practice.pressed.emit()
	await process_frame
	check(game.playing and not game.hud.menu_visible, "Starting must leave the menu and enter the match")
	check(game.simulation.actors[0].character == 1 and game.fighters[0].character == 1, "The selected operator must become the controlled fighter")
	game.restart_match()
	check(game.simulation.actors[0].character == 1, "Restart must retain the chosen operator")
	game.hud.show_menu(true)
	menu.open_screen("library")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/chibi-library.png")
	menu.open_screen("options")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/chibi-options.png")
	game.preferences.values = Preferences.DEFAULTS.duplicate()
	game.save_preferences()
	game.apply_preferences()
	menu.refresh_selection()
	menu.open_screen("home")
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/chibi-home-menu.png")
	print("MENU_TESTS ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
