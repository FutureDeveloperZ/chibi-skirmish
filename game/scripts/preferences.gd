extends RefCounted

const DEFAULTS := {"character": 0, "camera_zoom": 21.0, "fullscreen": false,
	"shadows": true, "minimap": true, "names": true}
var values: Dictionary = DEFAULTS.duplicate()
var path := "user://preferences.cfg"


func read() -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key in DEFAULTS:
		var value = file.get_value("player", key, DEFAULTS[key])
		if typeof(value) == typeof(DEFAULTS[key]):
			values[key] = value
	values.character = clampi(values.character, 0, 5)
	values.camera_zoom = clampf(values.camera_zoom, 16, 30) if is_finite(values.camera_zoom) else 21.0


func save() -> Error:
	var file := ConfigFile.new()
	for key in values:
		file.set_value("player", key, values[key])
	return file.save(path)
