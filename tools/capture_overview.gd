extends SceneTree


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hud.show_menu(false)
	game.camera_zoom = 49.0
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../previews/relay-yard-overview.png")
	root.get_texture().get_image().save_png(output)
	print("OVERVIEW_SAVED ", output)
	quit()
