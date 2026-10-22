extends Button

var accent := Color("ff183c")
var caption := ""
var subtitle := ""
var badge := ""
var display_font: Font
var rest_position := Vector2.ZERO
var rest_angle := 0.0
var motion_time := 0.0
var hover_amount := 0.0

func _ready() -> void:
	rest_position = position
	rest_angle = rotation
	motion_time = float(badge.to_int()) * 1.7
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	motion_time += delta
	var active := is_hovered() or has_focus()
	hover_amount = lerpf(hover_amount, 1.0 if active else 0.0, 1.0 - exp(-12.0 * delta))
	position = rest_position + Vector2(sin(motion_time * 0.7) * 2.0, sin(motion_time * 1.25) * 4.0 - hover_amount * 9.0)
	rotation = rest_angle + deg_to_rad(sin(motion_time * 0.85) * 0.6 - hover_amount * 1.0)
	scale = Vector2.ONE * (1.0 + hover_amount * 0.035)


func _draw() -> void:
	var active := is_hovered() or has_focus()
	var w := size.x
	var h := size.y
	var points := PackedVector2Array([Vector2(8, 0), Vector2(w, 7), Vector2(w - 24, h - 8), Vector2(0, h)])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(10, 12))
	draw_colored_polygon(shadow, accent)
	draw_colored_polygon(points, Color("faf4e8") if active else Color("09090d"))
	var ink := Color("09090d") if active else Color("faf4e8")
	draw_string(display_font, Vector2(24, h * 0.62), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, ink)
	draw_string(display_font, Vector2(28, h - 10), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, accent.darkened(0.35) if active else Color("ded8cd"))
	draw_circle(Vector2(w - 38, h * 0.48), 20, ink)
	draw_string(display_font, Vector2(w - 46, h * 0.48 + 8), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("09090d") if not active else Color("faf4e8"))
