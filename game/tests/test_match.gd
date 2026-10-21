extends SceneTree

const Rules = preload("res://scripts/match.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	var match_state := Rules.new()
	check(match_state.actors.size() == 6, "Six fighters must spawn")
	check(match_state.actors[2].team == 0 and match_state.actors[3].team == 1, "Teams must contain three fighters")
	for actor in match_state.actors:
		check(match_state.walkable(actor.p), "Spawns must be walkable")
		actor.peer = actor.slot + 1
		actor.protection = 0.0
	check(match_state.sanitize(Vector2(INF, 0), Vector2.ZERO, false, false, false).is_empty(), "Reject non-finite network input")
	var sanitized := match_state.sanitize(Vector2(99, 99), Vector2(999, -999), true, false, false)
	check(sanitized.move.length() <= 1.001, "Movement must be normalized")
	check(sanitized.aim == Vector2(34, -22), "Aim must be bounded")
	check(not match_state.line_clear(Vector2(-11, 0), Vector2(-7, 0)), "Cover must block shots")
	var actor: Dictionary = match_state.actors[0]
	actor.p = Vector2(-10.6, 0)
	match_state.move_actor(actor, Vector2(10, 0))
	check(actor.p.x < -10.4, "Fast movement must not tunnel through cover")
	actor.p = Vector2(-2, 0)
	match_state.actors[3].p = Vector2(2, 0)
	match_state.launch(actor, Vector2.RIGHT, false)
	for tick in range(30):
		match_state.step(1.0 / 60.0, {})
	check(match_state.actors[3].hp == 88, "A bullet must deal damage exactly once")
	match_state.actors[3].protection = 1.0
	match_state.damage(match_state.actors[3], 100, 0)
	check(match_state.actors[3].hp == 88, "Respawn protection must prevent damage")
	match_state.actors[3].protection = 0.0
	match_state.damage(match_state.actors[3], 100, 0)
	check(match_state.scores[0] == 1 and match_state.actors[3].respawn == 4, "An elimination scores and starts respawn")
	for tick in range(241):
		match_state.step(1.0 / 60.0, {})
	check(match_state.actors[3].hp == 100 and match_state.actors[3].protection > 0, "Dead fighters must respawn protected")
	match_state.scores[0] = Rules.WIN_SCORE
	match_state.step(1.0 / 60.0, {})
	check(match_state.winner == 0, "Reaching the score limit must end the match")
	var time_before: float = match_state.remaining
	match_state.step(1.0, {})
	check(match_state.remaining == time_before, "Completed matches must stop simulating")
	match_state.reset()
	check(match_state.actors[3].peer == 4 and match_state.scores == [0, 0], "Restart must preserve connections and clear scores")
	match_state.remaining = 0.001
	match_state.step(1.0 / 60.0, {})
	check(match_state.winner == -1, "An equal score at timeout must be a draw")
	var bots := Rules.new()
	for tick in range(60 * 90):
		bots.step(1.0 / 60.0, {})
	check(bots.scores[0] + bots.scores[1] > 0, "Bots must navigate and fight rather than remain stuck")
	print("MATCH_TESTS ", "PASS" if failures == 0 else "FAIL", " failures=", failures, " bot_scores=", bots.scores)
	quit(0 if failures == 0 else 1)
