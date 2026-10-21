extends SceneTree
## Run on a virtual display: exercises the actual scene, controls, and model imports.

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.fighters.size() == 6, "All six models must instantiate")
	for fighter in game.fighters:
		check(fighter.animation != null, "Every model must have an AnimationPlayer")
		for clip in ["idle", "run", "walk", "shot", "death"]:
			check(fighter.animation.has_animation(clip), "Missing animation: " + clip)
	game.practice()
	var origin: Vector2 = game.simulation.actors[0].p
	Input.action_press("right")
	await create_timer(0.5).timeout
	Input.action_release("right")
	check(game.simulation.actors[0].p.distance_to(origin) > 1.0, "Movement controls must move the local fighter")
	Input.action_press("grenade")
	await create_timer(0.1).timeout
	Input.action_release("grenade")
	check(game.simulation.actors[0].grenade_cd > 7, "The grenade key must activate the ability")
	Input.action_press("dodge")
	await create_timer(0.1).timeout
	Input.action_release("dodge")
	check(game.simulation.actors[0].dash_cd > 2, "The dodge key must activate the ability")
	await create_timer(0.2).timeout # Let the already-started dodge finish before testing menu input.
	game.hud.show_menu(true)
	origin = game.simulation.actors[0].p
	Input.action_press("right")
	await create_timer(0.3).timeout
	Input.action_release("right")
	check(game.simulation.actors[0].p.distance_to(origin) < 0.01, "Menu input must not move the fighter")
	game.hud.show_menu(false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/chibi-tested-gameplay.png")
	print("PLAYABLE_TESTS ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
