extends RefCounted
## The authority runs this simulation; clients only send controls and display snapshots.

const LIMIT := Vector2(34, 22)
const RADIUS := 0.48
const SPEED := 5.6
const MAX_HP := 100.0
const WIN_SCORE := 20
const MATCH_SECONDS := 300.0
const NAMES := ["Rapi", "Neon", "Anis", "Marian", "Delta", "Signal"]
const MODELS := ["c010_00", "c011_00", "c012_00", "c013_00", "c020_00", "c022_00"]
const COVERS := [
	Rect2(-19, -8, 6, 2.6), Rect2(13, 5.4, 6, 2.6),
	Rect2(-19, 5.4, 6, 2.6), Rect2(13, -8, 6, 2.6),
	Rect2(-10, -1.8, 2, 3.6), Rect2(8, -1.8, 2, 3.6),
	Rect2(-4, -2, 3, 1.2), Rect2(1, 0.8, 3, 1.2),
	Rect2(-6, -14, 4, 2.8), Rect2(2, 11.2, 4, 2.8),
	Rect2(-25, -16, 4, 2), Rect2(21, 14, 4, 2),
	Rect2(-25, 14, 4, 2), Rect2(21, -16, 4, 2),
	Rect2(-3, -20, 6, 2), Rect2(-3, 18, 6, 2),
	Rect2(-15, -19, 2, 2), Rect2(13, 17, 2, 2),
]

var actors: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var scores: Array[int] = [0, 0]
var remaining := MATCH_SECONDS
var elapsed := 0.0
var winner := -2 # -2 playing, -1 draw, 0/1 winning team
var next_bullet := 0
var event_id := 0
var events: Array[Dictionary] = []
var navigation := AStarGrid2D.new()


func _init() -> void:
	navigation.region = Rect2i(-34, -22, 69, 45)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-34, 35):
		for y in range(-22, 23):
			navigation.set_point_solid(Vector2i(x, y), not walkable(Vector2(x, y), 0.65))
	reset()


func reset() -> void:
	var peers: Array[int] = []
	for actor in actors:
		peers.append(actor.peer)
	actors.clear()
	bullets.clear()
	events.clear()
	scores = [0, 0]
	remaining = MATCH_SECONDS
	elapsed = 0.0
	winner = -2
	for slot in range(6):
		actors.append({"slot": slot, "peer": peers[slot] if peers.size() == 6 else 0,
			"team": slot / 3, "p": spawn(slot), "move": Vector2.ZERO,
			"aim": Vector2.RIGHT if slot < 3 else Vector2.LEFT,
			"hp": MAX_HP, "respawn": 0.0, "protection": 1.5,
			"fire_cd": 0.0, "grenade_cd": 0.0, "dash_cd": 0.0,
			"dash_time": 0.0, "dash_dir": Vector2.ZERO, "fired": 0.0,
			"kills": 0, "deaths": 0, "waypoint": spawn(slot), "repath": 0.0})


func spawn(slot: int) -> Vector2:
	return Vector2(-27 if slot < 3 else 27, (slot % 3 - 1) * 7.0)


func walkable(point: Vector2, radius: float = RADIUS) -> bool:
	if absf(point.x) > LIMIT.x - radius or absf(point.y) > LIMIT.y - radius:
		return false
	for cover in COVERS:
		if cover.grow(radius).has_point(point):
			return false
	return true


func line_clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
	for step in range(steps + 1):
		if not walkable(a.lerp(b, float(step) / steps), 0.02):
			return false
	return true


func sanitize(move: Vector2, aim: Vector2, fire: bool, grenade: bool, dash: bool) -> Dictionary:
	if not move.is_finite() or not aim.is_finite():
		return {}
	return {"move": move.limit_length(1.0), "aim": aim.clamp(-LIMIT, LIMIT),
		"fire": fire, "grenade": grenade, "dash": dash}


func step(delta: float, controls: Dictionary) -> void:
	if winner != -2:
		return
	elapsed += delta
	remaining = maxf(0.0, remaining - delta)
	for actor in actors:
		for key in ["fire_cd", "grenade_cd", "dash_cd", "dash_time", "fired", "protection", "repath"]:
			actor[key] = maxf(0.0, actor[key] - delta)
		if actor.hp <= 0:
			actor.respawn -= delta
			if actor.respawn <= 0:
				actor.hp = MAX_HP
				actor.p = spawn(actor.slot)
				actor.protection = 1.5
			continue
		var input: Dictionary = controls.get(actor.slot, {}) if actor.peer != 0 else bot_input(actor)
		var movement: Vector2 = input.get("move", Vector2.ZERO)
		var aim_at: Vector2 = input.get("aim", actor.p + actor.aim)
		if aim_at.distance_to(actor.p) > 0.05:
			actor.aim = (aim_at - actor.p).normalized()
		if input.get("dash", false) and actor.dash_cd <= 0:
			actor.dash_time = 0.16
			actor.dash_cd = 3.0
			actor.dash_dir = movement.normalized() if movement.length() > 0.01 else actor.aim
		if actor.dash_time > 0:
			movement = actor.dash_dir * 3.0
		actor.move = movement
		move_actor(actor, movement * SPEED * delta)
		if input.get("fire", false) and actor.fire_cd <= 0:
			actor.fire_cd = 0.19
			actor.fired = 0.16
			actor.protection = 0.0
			launch(actor, actor.aim, false)
		if input.get("grenade", false) and actor.grenade_cd <= 0:
			actor.grenade_cd = 8.0
			actor.protection = 0.0
			launch(actor, actor.aim, true, clampf(actor.p.distance_to(aim_at), 2.0, 9.0))
	separate_actors()
	step_bullets(delta)
	if scores[0] >= WIN_SCORE or scores[1] >= WIN_SCORE or remaining <= 0:
		winner = -1 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1)
	while events.size() > 16:
		events.pop_front()


func move_actor(actor: Dictionary, offset: Vector2) -> void:
	var steps := maxi(1, ceili(offset.length() / 0.15))
	offset /= steps
	for step in range(steps):
		var point: Vector2 = actor.p
		if walkable(point + Vector2(offset.x, 0)):
			point.x += offset.x
		if walkable(point + Vector2(0, offset.y)):
			point.y += offset.y
		actor.p = point


func separate_actors() -> void:
	for i in range(actors.size()):
		for j in range(i + 1, actors.size()):
			var a: Dictionary = actors[i]
			var b: Dictionary = actors[j]
			if a.hp <= 0 or b.hp <= 0:
				continue
			var offset: Vector2 = b.p - a.p
			var distance := offset.length()
			if distance < RADIUS * 2:
				var push := (offset / distance if distance > 0.001 else Vector2.RIGHT) * (RADIUS * 2 - distance) * 0.5
				move_actor(a, -push)
				move_actor(b, push)


func launch(actor: Dictionary, direction: Vector2, grenade: bool, distance: float = 0.0) -> void:
	next_bullet += 1
	bullets.append({"id": next_bullet, "p": actor.p + direction * 0.55,
		"dir": direction, "team": actor.team, "owner": actor.slot,
		"grenade": grenade, "ttl": distance / 10.0 if grenade else 0.9,
		"life": 0.0})


func step_bullets(delta: float) -> void:
	for index in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[index]
		bullet.ttl -= delta
		bullet.life += delta
		var speed := 10.0 if bullet.grenade else 24.0
		var steps := maxi(1, ceili(speed * delta / 0.18))
		var remove: bool = bullet.ttl <= 0
		for substep in range(steps):
			if remove:
				break
			bullet.p += bullet.dir * speed * delta / steps
			if not bullet.grenade:
				if not walkable(bullet.p, 0.01):
					remove = true
					break
				for actor in actors:
					if actor.team != bullet.team and actor.hp > 0 and actor.p.distance_to(bullet.p) < 0.48:
						damage(actor, 12.0, bullet.owner)
						remove = true
						break
		if remove:
			if bullet.grenade:
				emit_event("blast", bullet.p, bullet.team)
				for actor in actors:
					if actor.team != bullet.team and actor.hp > 0 and actor.p.distance_to(bullet.p) < 2.6:
						if line_clear(bullet.p, actor.p):
							damage(actor, 52.0, bullet.owner)
			bullets.remove_at(index)


func damage(actor: Dictionary, amount: float, source: int) -> void:
	if actor.hp <= 0 or actor.protection > 0:
		return
	actor.hp = maxf(0.0, actor.hp - amount)
	emit_event("hit", actor.p, actor.team)
	if actor.hp == 0:
		actor.respawn = 4.0
		actor.deaths += 1
		actors[source].kills += 1
		scores[actors[source].team] += 1
		emit_event("elimination", actor.p, actors[source].team, source, actor.slot)


func emit_event(kind: String, point: Vector2, team: int, source: int = -1, target: int = -1) -> void:
	event_id += 1
	events.append({"id": event_id, "kind": kind, "p": point, "team": team,
		"source": source, "target": target, "time": elapsed})


func bot_input(actor: Dictionary) -> Dictionary:
	var enemy: Dictionary = {}
	var best := INF
	for target in actors:
		if target.team == actor.team or target.hp <= 0:
			continue
		var distance: float = actor.p.distance_to(target.p)
		if distance < best:
			best = distance
			enemy = target
	if enemy.is_empty():
		return {}
	var clear := line_clear(actor.p, enemy.p)
	var movement := Vector2.ZERO
	if clear and best < 8.5:
		var toward: Vector2 = (enemy.p - actor.p).normalized()
		movement = toward * (0.5 if best > 6 else -0.4 if best < 3.5 else 0.0)
		movement += toward.orthogonal() * sin(elapsed * 1.3 + actor.slot * 2) * 0.65
	else:
		if actor.repath <= 0 or actor.p.distance_to(actor.waypoint) < 0.3:
			actor.repath = 0.5
			var origin := Vector2i(Vector2(actor.p).round())
			var destination := Vector2i(Vector2(enemy.p).round())
			if navigation.is_in_boundsv(origin) and navigation.is_in_boundsv(destination):
				if not navigation.is_point_solid(origin) and not navigation.is_point_solid(destination):
					var path := navigation.get_point_path(origin, destination)
					if path.size() > 1:
						actor.waypoint = path[1]
		movement = (actor.waypoint - actor.p).limit_length(1.0)
	var wobble := Vector2(sin(elapsed * 2.1 + actor.slot), cos(elapsed * 1.8 + actor.slot)) * 0.3
	return {"move": movement.limit_length(1.0), "aim": enemy.p + wobble,
		"fire": clear and best < 13, "grenade": clear and best < 8.0,
		"dash": actor.hp < 35 and best < 4}


func snapshot() -> Dictionary:
	# Six actors and a small projectile pool; keep this explicit until profiling calls for packing.
	return {"actors": actors.duplicate(true), "bullets": bullets.duplicate(true),
		"scores": scores.duplicate(), "remaining": remaining, "elapsed": elapsed,
		"winner": winner, "events": events.duplicate(true)}
