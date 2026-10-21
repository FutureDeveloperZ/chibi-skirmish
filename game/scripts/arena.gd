extends Node3D
## A surface logistics yard: three routes, container cover, concrete, steel, and warning paint.

const Rules = preload("res://scripts/match.gd")
const BLUE := Color("72c9e7")
const RED := Color("e57c73")
const YELLOW := Color("dcae59")
var materials: Dictionary = {}


func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("202b37")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9cadc7")
	settings.ambient_light_energy = 0.48
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53, -34, 0)
	sun.light_color = Color("c9d8e6")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	sun.shadow_blur = 1.8
	add_child(sun)
	build_ground()
	for index in range(Rules.COVERS.size()):
		var rect: Rect2 = Rules.COVERS[index]
		if index < 4:
			container(rect, Color("5c686e") if index % 2 == 0 else Color("7e5d4a"), index)
		elif index in [8, 9, 14, 15]:
			cargo_stack(rect, index)
		else:
			barricade(rect)
	build_perimeter()
	merge_static_boxes()


func merge_static_boxes() -> void:
	# One surface per shared material keeps the expanded yard inexpensive to render.
	var groups: Dictionary = {}
	for child in get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.material_override is StandardMaterial3D:
			var mat: Material = child.material_override
			if not groups.has(mat):
				groups[mat] = []
			groups[mat].append(child)
	for mat in groups:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for child in groups[mat]:
			surface.append_from(child.mesh, 0, child.transform)
			child.queue_free()
		var merged := MeshInstance3D.new()
		merged.mesh = surface.commit()
		merged.material_override = mat
		add_child(merged)


func build_ground() -> void:
	box(Vector3(0, -0.65, 0), Vector3(90, 1, 66), Color("1c252e"))
	var ground := box(Vector3(0, -0.11, 0), Vector3(69, 0.2, 45), Color("394149"))
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_burley;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float grain = hash(floor(wp.xz * 100.0));
	float patch = hash(floor(wp.xz * 1.2));
	vec3 asphalt = vec3(0.095, 0.113, 0.128);
	ALBEDO = asphalt * (0.88 + grain * 0.16 + patch * 0.10);
	ROUGHNESS = 0.96;
}
"""
	var ground_material := ShaderMaterial.new()
	ground_material.shader = shader
	ground.material_override = ground_material
	# Utility trenches and expansion joints break up the surface at a human scale.
	for x in range(-32, 35, 4):
		box(Vector3(x, 0.002, 0), Vector3(0.025, 0.01, 44), Color("252d33"))
	for z in range(-20, 23, 4):
		box(Vector3(0, 0.003, z), Vector3(68, 0.01, 0.025), Color("252d33"))
	for z in [-11.0, 11.0]:
		for x in range(-31, 33, 5):
			box(Vector3(x, 0.012, z), Vector3(2.2, 0.012, 0.065), YELLOW.darkened(0.25))
	for x in [-22, 22]:
		box(Vector3(x, 0.014, 0), Vector3(0.1, 0.015, 40), Color("78858a"))
		for z in range(-20, 21, 5):
			box(Vector3(x, 0.02, z), Vector3(0.8, 0.018, 0.09), Color("929a96"))
	for x in [-6, 6]:
		box(Vector3(x, 0.01, 0), Vector3(0.45, 0.018, 42), Color("202a30"))
		for z in range(-20, 22, 2):
			box(Vector3(x, 0.025, z), Vector3(0.5, 0.02, 0.05), Color("617078"))
	for side in [-1, 1]:
		var color := BLUE if side < 0 else RED
		box(Vector3(side * 27, 0.015, 0), Vector3(8, 0.018, 20), Color("414c55"))
		for edge in [-10, 10]:
			box(Vector3(side * 27, 0.035, edge), Vector3(8, 0.02, 0.10), color.darkened(0.2))
		box(Vector3(side * 23, 0.035, 0), Vector3(0.10, 0.02, 20), color)
		for z in [-7, 0, 7]:
			ring(Vector3(side * 27, 0.04, z), 1.0, 0.04, color)
		floor_text(Vector3(side * 28, 0.045, 0), "01" if side < 0 else "02", 0.025, Color("b3b9b4"))
	floor_text(Vector3(0, 0.045, -5), "RELAY 07", 0.02, Color("889393"))
	floor_text(Vector3(-14, 0.045, -18), "NORTH ACCESS", 0.009, Color("86928d"))
	floor_text(Vector3(14, 0.045, 18), "SOUTH ACCESS", 0.009, Color("86928d"))
	for point in [Vector3(-22, 0, -5), Vector3(22, 0, 5), Vector3(-11, 0, 14), Vector3(11, 0, -14)]:
		for index in range(7):
			var mark := box(point + Vector3(index * 0.45, 0.027, 0), Vector3(0.24, 0.018, 1.1), YELLOW.darkened(0.12))
			mark.rotation.y = -0.55
	# Damaged slabs, tire traces, and small scattered debris are ground decoration only.
	for index in range(24):
		var x := float(posmod(index * 17, 61) - 30)
		var z := float(posmod(index * 13, 39) - 19)
		var blocked := false
		for cover in Rules.COVERS:
			blocked = blocked or cover.grow(0.2).has_point(Vector2(x, z))
		if not blocked:
			var crack := box(Vector3(x, 0.022, z), Vector3(0.035, 0.01, 0.8 + (index % 3) * 0.5), Color("283136"))
			crack.rotation.y = index * 1.13


func container(rect: Rect2, color: Color, index: int) -> void:
	var center := rect.get_center()
	var point := Vector3(center.x, 1.12, center.y)
	box(point, Vector3(rect.size.x, 2.2, rect.size.y), color)
	box(point + Vector3(0, 1.14, 0), Vector3(rect.size.x + 0.08, 0.10, rect.size.y + 0.08), color.lightened(0.10))
	for rib in range(14):
		var x: float = -rect.size.x / 2 + 0.15 + rib * (rect.size.x - 0.3) / 13
		for side in [-1, 1]:
			box(point + Vector3(x, 0, side * (rect.size.y / 2 + 0.015)), Vector3(0.07, 2.06, 0.055), color.lightened(0.08))
		box(point + Vector3(x, 1.21, 0), Vector3(0.06, 0.025, rect.size.y - 0.12), color.darkened(0.1))
	for side in [-1, 1]:
		box(point + Vector3(side * (rect.size.x / 2 - 0.1), 0, 0), Vector3(0.14, 2.3, rect.size.y + 0.12), Color("3b444c"))
		for z in [-0.7, 0.7]:
			box(point + Vector3(side * (rect.size.x / 2 + 0.04), 0, z), Vector3(0.06, 1.85, 0.055), Color("9ba19a"))
	var label := Label3D.new()
	label.text = "ELYSION  /  %03d" % (index + 41)
	label.position = point + Vector3(0, 0.2, rect.size.y / 2 + 0.055)
	label.pixel_size = 0.008
	label.font_size = 48
	label.modulate = Color("d5d5be")
	label.outline_size = 0
	add_child(label)
	box(point + Vector3(-1.6, -0.5, rect.size.y / 2 + 0.06), Vector3(0.5, 0.35, 0.025), YELLOW)


func barricade(rect: Rect2) -> void:
	var c := rect.get_center()
	var point := Vector3(c.x, 0.57, c.y)
	box(point, Vector3(rect.size.x, 1.1, rect.size.y), Color("697477"))
	box(point + Vector3(0, 0.62, 0), Vector3(rect.size.x + 0.1, 0.14, rect.size.y + 0.1), Color("9a9b8f"))
	box(point - Vector3(0, 0.4, 0), Vector3(rect.size.x + 0.2, 0.22, rect.size.y + 0.2), Color("434e54"))
	for side in [-1, 1]:
		box(point + Vector3(0, 0.28, side * (rect.size.y / 2 + 0.02)), Vector3(rect.size.x - 0.16, 0.23, 0.04), Color("333d43"))
		for x in range(maxi(1, int(rect.size.x / 0.55))):
			box(point + Vector3(-rect.size.x / 2 + 0.3 + x * 0.55, 0.28, side * (rect.size.y / 2 + 0.05)), Vector3(0.24, 0.19, 0.02), YELLOW.darkened(0.1))
	for x in [-0.32, 0.32]:
		box(point + Vector3(x * rect.size.x, -0.1, rect.size.y / 2 + 0.03), Vector3(0.08, 0.28, 0.02), Color("343d43"))


func cargo_stack(rect: Rect2, index: int) -> void:
	var c := rect.get_center()
	box(Vector3(c.x, 0.14, c.y), Vector3(rect.size.x + 0.1, 0.28, rect.size.y + 0.1), Color("564a3c"))
	for x in [-0.24, 0.24]:
		var point := Vector3(c.x + x * rect.size.x, 0.94, c.y)
		var size := Vector3(rect.size.x * 0.45, 1.55, rect.size.y - 0.12)
		var color := Color("676c62") if index % 2 == 0 else Color("6c6253")
		box(point, size, color)
		for edge in [-0.35, 0.35]:
			box(point + Vector3(edge * size.x, 0, 0), Vector3(0.09, size.y + 0.06, size.z + 0.06), Color("363f43"))
		box(point + Vector3(0, 0.25, size.z / 2 + 0.02), Vector3(0.5, 0.32, 0.03), YELLOW.darkened(0.2))


func build_perimeter() -> void:
	for side in [-1, 1]:
		box(Vector3(0, 0.5, side * 22.7), Vector3(70, 1, 0.6), Color("59676f"))
		box(Vector3(side * 34.7, 0.5, 0), Vector3(0.6, 1, 46), Color("59676f"))
		for x in range(-32, 35, 4):
			box(Vector3(x, 1.7, side * 22.7), Vector3(0.12, 2.5, 0.12), Color("637682"))
		for y in [1.15, 2.2, 2.9]:
			box(Vector3(0, y, side * 22.7), Vector3(70, 0.045, 0.045), Color("6d7d82"))
		for x in [-26, -8, 8, 26]:
			lamp(Vector3(x, 0, side * 21.4), side)
		for z in [-16, -6, 6, 16]:
			barrel(Vector3(side * 32.5, 0, z))
		# Warehouses and ventilation equipment stay outside collision boundaries.
		box(Vector3(side * 39.5, 3.2, 0), Vector3(7, 6.4, 45), Color("414e5b"))
		for z in range(-20, 22, 5):
			box(Vector3(side * 35.95, 2.1, z), Vector3(0.12, 3.6, 3.1), Color("293640"))
			box(Vector3(side * 35.84, 4.5, z), Vector3(0.07, 0.3, 2.7), Color("8cb7c9"))
	for x in [-26, -14, 0, 14, 26]:
		box(Vector3(x, 3.2, -28), Vector3(11, 6.4, 7), Color("414c58"))
		box(Vector3(x, 6.5, -28), Vector3(11.4, 0.3, 7.3), Color("677580"))
		for vent in [-2, 2]:
			box(Vector3(x + vent, 7.0, -28), Vector3(2.4, 0.8, 2.4), Color("4b5d67"))
	for side in [-1, 1]:
		var color := BLUE if side < 0 else RED
		box(Vector3(side * 33, 2.4, 0), Vector3(0.35, 4.5, 8), Color("3d4c5a"))
		box(Vector3(side * 32.8, 3.3, 0), Vector3(0.08, 0.13, 6), color)
		for z in [-3.5, 3.5]:
			box(Vector3(side * 32.7, 1.9, z), Vector3(0.12, 3.6, 0.15), YELLOW)


func barrel(point: Vector3) -> void:
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.36
	mesh.bottom_radius = 0.36
	mesh.height = 1.05
	mesh.radial_segments = 12
	body.mesh = mesh
	body.material_override = material(Color("6c5d47"))
	body.position = point + Vector3(0, 0.55, 0)
	add_child(body)
	for height in [0.22, 0.83]:
		ring(point + Vector3(0, height, 0), 0.38, 0.045, Color("343e45"))


func lamp(point: Vector3, side: int) -> void:
	box(point + Vector3(0, 3.2, 0), Vector3(0.15, 6.4, 0.15), Color("526473"))
	box(point + Vector3(0, 6.4, -side * 0.65), Vector3(0.18, 0.12, 1.4), Color("526473"))
	var light_surface := box(point + Vector3(0, 6.35, -side * 1.2), Vector3(0.8, 0.08, 0.5), Color("dbe7e1"))
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("d1e3e9")
	light_surface.material_override = glow


func floor_text(point: Vector3, text: String, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = preload("res://assets/fonts/Display.ttf")
	label.font_size = 96
	label.pixel_size = pixel_size
	label.position = point
	label.rotation_degrees.x = -90
	label.outline_size = 0
	label.modulate = color
	add_child(label)


func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var result := StandardMaterial3D.new()
		result.albedo_color = color
		result.roughness = 0.88
		materials[color] = result
	return materials[color]


func box(point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = point
	add_child(node)
	return node


func ring(point: Vector3, radius: float, width: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = material(color)
	node.position = point
	add_child(node)
	return node
