extends Control

const Rules = preload("res://scripts/match.gd")
const BLUE := Color("72c9e7")
const RED := Color("e57c73")
const INK := Color("e8edf0")
const MUTED := Color("98aab7")
const PAPER := Color("1b252e")
const GOLD := Color("dfb565")
const WEAPONS := ["ar", "sg", "rl", "mg", "sr", "smg"]
const WEAPON_NAMES := ["Assault rifle", "Shotgun", "Rocket launcher", "Machine gun", "Sniper rifle", "Submachine gun"]
var portraits: Array[Texture2D] = []
var weapon_icons: Dictionary = {}
var game: Node3D
var menu_visible := true
var menu: Control
var font: Font = preload("res://assets/fonts/Interface.ttf")
var display_font: Font = preload("res://assets/fonts/Display.ttf")


func setup(owner_game: Node3D) -> void:
	game = owner_game
	for model in Rules.MODELS:
		portraits.append(load("res://assets/ui/%s.png" % model))
	for weapon in WEAPONS:
		weapon_icons[weapon] = load("res://assets/ui/weapon_%s_full.png" % weapon)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 17
	self.theme = theme
	menu = load("res://scripts/front_menu.gd").new()
	add_child(menu)
	menu.setup(self, game)


func panel(color: Color, radius: int, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(mini(radius, 2))
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func button(text: String, color: Color, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 46
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_stylebox_override("normal", panel(color, 9, 10))
	result.add_theme_stylebox_override("hover", panel(color.lightened(0.12), 9, 10))
	result.add_theme_stylebox_override("pressed", panel(color.darkened(0.1), 9, 10))
	var focus := panel(color, 9, 10)
	focus.border_color = Color("ffe2a0")
	focus.set_border_width_all(3)
	result.add_theme_stylebox_override("focus", focus)
	var foreground := Color("17222b") if color.get_luminance() > 0.35 else INK
	result.add_theme_color_override("font_color", foreground)
	result.add_theme_color_override("font_hover_color", foreground)
	result.add_theme_color_override("font_pressed_color", foreground)
	result.pressed.connect(action)
	return result


func show_menu(visible_menu: bool) -> void:
	menu_visible = visible_menu
	menu.set_menu_visible(visible_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func set_status(message: String) -> void:
	menu.status.text = message


func text_at(point: Vector2, text: String, size_px: int, color: Color, bold: bool = false) -> void:
	draw_string(display_font if bold else font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func centered(point: Vector2, text: String, size_px: int, color: Color, bold: bool = false) -> void:
	var face := display_font if bold else font
	var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	text_at(point - Vector2(width / 2, 0), text, size_px, color, bold)


func card(rect: Rect2, color: Color = PAPER, radius: int = 12) -> void:
	var p := rect.position
	var s := rect.size
	var cut := minf(10, radius)
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(s.x - cut, 0), p + Vector2(s.x, cut), p + s,
		p + Vector2(cut, s.y), p + Vector2(0, s.y - cut)]), Color(color, 0.95))
	draw_line(p, p + Vector2(s.x - cut, 0), Color("52616d"), 1)


func _draw() -> void:
	if not game or game.state.is_empty() or menu_visible:
		return
	var scale_ui := Vector2(size.x / 1440.0, size.y / 900.0)
	draw_set_transform(Vector2.ZERO, 0, scale_ui)
	var state: Dictionary = game.state
	# The scoreboard and court identity leave the center of the playfield open.
	card(Rect2(26, 24, 232, 62))
	text_at(Vector2(44, 53), "Chibi Skirmish", 23, INK, true)
	text_at(Vector2(44, 73), "Relay yard 07  /  3v3", 13, MUTED)
	card(Rect2(470, 24, 500, 78))
	draw_style_box(panel(Color("294959"), 2), Rect2(481, 35, 135, 56))
	draw_style_box(panel(Color("583c3d"), 2), Rect2(824, 35, 135, 56))
	text_at(Vector2(496, 59), "Alpha", 17, BLUE, true)
	text_at(Vector2(838, 59), "Bravo", 17, RED, true)
	centered(Vector2(586, 76), str(state.scores[0]).pad_zeros(2), 32, Color.WHITE, true)
	centered(Vector2(929, 76), str(state.scores[1]).pad_zeros(2), 32, Color.WHITE, true)
	var seconds := ceili(state.remaining)
	centered(Vector2(720, 65), "%02d:%02d" % [seconds / 60, seconds % 60], 31, INK, true)
	centered(Vector2(720, 86), "First to 20", 13, MUTED)
	card(Rect2(1228, 24, 186, 43))
	draw_circle(Vector2(1247, 46), 4, BLUE if game.playing else MUTED)
	text_at(Vector2(1260, 52), game.mode, 16, INK)
	if game.preferences.values.minimap:
		draw_minimap(state)
	var nameplates: Array[Rect2] = []
	for index in range(game.fighters.size()):
		var actor: Dictionary = state.actors[index]
		if actor.hp <= 0:
			continue
		var point: Vector2 = game.camera.unproject_position(game.fighters[index].position + Vector3(0, 2.05, 0)) / scale_ui
		for occupied in nameplates:
			if occupied.intersects(Rect2(point - Vector2(40, 23), Vector2(80, 30))):
				point.y = occupied.position.y - 10
		nameplates.append(Rect2(point - Vector2(40, 23), Vector2(80, 30)))
		var color := BLUE if actor.team == 0 else RED
		draw_style_box(panel(Color("101820"), 2), Rect2(point + Vector2(-25, 0), Vector2(50, 6)))
		draw_style_box(panel(color, 3), Rect2(point + Vector2(-25, 0), Vector2(maxf(1, 50 * actor.hp / 100), 6)))
		if not game.preferences.values.names:
			continue
		var name_text: String = Rules.NAMES[actor.character] + (" • You" if index == game.local_slot else "")
		var label_width := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12
		draw_style_box(panel(Color(PAPER, 0.94), 4), Rect2(point + Vector2(-label_width / 2, -23), Vector2(label_width, 19)))
		centered(point + Vector2(0, -9), name_text, 13, INK)
	var mine: Dictionary = state.actors[maxi(game.local_slot, 0)]
	card(Rect2(36, 765, 318, 103))
	draw_rect(Rect2(44, 779, 72, 72), Color("374652"))
	draw_texture_rect(portraits[mine.character], Rect2(44, 779, 72, 72), false)
	draw_line(Vector2(44, 851), Vector2(116, 851), GOLD, 3)
	text_at(Vector2(126, 798), Rules.NAMES[mine.character], 22, INK, true)
	text_at(Vector2(126, 820), WEAPON_NAMES[mine.character], 13, MUTED)
	draw_style_box(panel(Color("34434e"), 2), Rect2(126, 833, 202, 9))
	draw_style_box(panel(BLUE if mine.team == 0 else RED, 4), Rect2(126, 833, maxf(1, 202 * mine.hp / 100), 9))
	text_at(Vector2(126, 861), "%d / 100 HP" % mine.hp, 13, INK)
	text_at(Vector2(250, 861), "%d K / %d D" % [mine.kills, mine.deaths], 13, MUTED)
	ability(Vector2(540, 790), "LMB", "Fire", 0.0, 0.0)
	ability(Vector2(666, 790), "Q", "Grenade", mine.grenade_cd, 8.0)
	ability(Vector2(792, 790), "Space", "Dodge", mine.dash_cd, 3.0)
	centered(Vector2(729, 885), "WASD move    Mouse aim    Scroll zoom    Esc menu", 14, INK)
	card(Rect2(1112, 760, 302, 108))
	text_at(Vector2(1128, 785), "Your team", 15, MUTED)
	var team_start: int = mine.team * 3
	for row in range(3):
		var actor: Dictionary = state.actors[team_start + row]
		var y := 807.0 + row * 23
		draw_texture_rect(portraits[actor.character], Rect2(1128, y - 17, 21, 21), false)
		text_at(Vector2(1157, y), Rules.NAMES[actor.character], 14, INK)
		text_at(Vector2(1280, y), "Bot" if actor.peer == 0 else "Player", 12, MUTED)
		text_at(Vector2(1350, y), "%d" % actor.hp, 13, INK)
	var feed_row := 0
	for event in state.events:
		if event.kind == "elimination" and state.elapsed - event.time < 5.0 and feed_row < 4:
			card(Rect2(1070, 268 + feed_row * 32, 344, 27), Color(PAPER, 0.94), 6)
			text_at(Vector2(1082, 287 + feed_row * 32), "%s  eliminated  %s" % [Rules.NAMES[state.actors[event.source].character], Rules.NAMES[state.actors[event.target].character]], 14, INK)
			feed_row += 1
	if mine.hp <= 0 and state.winner == -2:
		card(Rect2(520, 360, 400, 108))
		centered(Vector2(720, 404), "Back in %d" % ceili(mine.respawn), 32, INK, true)
		centered(Vector2(720, 441), "Your team is still in the fight.", 17, MUTED)
	if state.winner != -2:
		card(Rect2(470, 330, 500, 175))
		var result := "Draw" if state.winner == -1 else ("Alpha wins" if state.winner == 0 else "Bravo wins")
		centered(Vector2(720, 394), result, 44, INK, true)
		centered(Vector2(720, 438), "%d  :  %d" % [state.scores[0], state.scores[1]], 28, INK)
		centered(Vector2(720, 476), "Esc to open the match menu", 17, MUTED)
	if not menu_visible:
		var cursor := get_viewport().get_mouse_position() / scale_ui
		draw_arc(cursor, 7, 0, TAU, 24, GOLD, 1.5, true)
		draw_line(cursor - Vector2(12, 0), cursor - Vector2(4, 0), INK, 1.2, true)
		draw_line(cursor + Vector2(4, 0), cursor + Vector2(12, 0), INK, 1.2, true)
		draw_line(cursor - Vector2(0, 12), cursor - Vector2(0, 4), INK, 1.2, true)
		draw_line(cursor + Vector2(0, 4), cursor + Vector2(0, 12), INK, 1.2, true)


func ability(point: Vector2, key: String, label: String, cooldown: float, total: float) -> void:
	card(Rect2(point, Vector2(112, 71)))
	text_at(point + Vector2(12, 27), key, 19, BLUE if cooldown <= 0 else MUTED, true)
	text_at(point + Vector2(12, 52), label if cooldown <= 0 else "%.1fs" % cooldown, 15, INK)
	if key in ["LMB", "Q"]:
		var weapon: String = WEAPONS[game.state.actors[maxi(game.local_slot, 0)].character] if key == "LMB" else "rl"
		var texture: Texture2D = weapon_icons[weapon]
		var icon_size := texture.get_size() * minf(42.0 / texture.get_width(), 30.0 / texture.get_height())
		draw_texture_rect(texture, Rect2(point + Vector2(84, 23) - icon_size / 2, icon_size), false, Color(GOLD if cooldown <= 0 else MUTED))
	else:
		for x in [0, 8]:
			draw_polyline(PackedVector2Array([point + Vector2(76 + x, 16), point + Vector2(83 + x, 23), point + Vector2(76 + x, 30)]), GOLD, 2, true)
	if total > 0:
		draw_style_box(panel(Color("34434e"), 2), Rect2(point + Vector2(12, 60), Vector2(88, 3)))
		draw_style_box(panel(BLUE, 2), Rect2(point + Vector2(12, 60), Vector2(88 * (1 - cooldown / total), 3)))


func draw_minimap(state: Dictionary) -> void:
	card(Rect2(1228, 80, 186, 156), Color(PAPER, 0.97))
	text_at(Vector2(1240, 104), "Relay yard", 14, INK)
	var area := Rect2(1240, 114, 162, 108)
	draw_style_box(panel(Color("303d48"), 2), area)
	var factor := Vector2(area.size.x / (Rules.LIMIT.x * 2), area.size.y / (Rules.LIMIT.y * 2))
	var center := area.get_center()
	for cover in Rules.COVERS:
		draw_rect(Rect2(center + cover.position * factor, cover.size * factor), Color("75828a"))
	for actor in state.actors:
		if actor.hp > 0:
			var p: Vector2 = center + actor.p * factor
			if actor.slot == game.local_slot:
				draw_circle(p, 5.0, INK)
			draw_circle(p, 3, BLUE if actor.team == 0 else RED)
