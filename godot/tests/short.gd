## Shorts director: plays one scripted action shot for a vertical video, with cinematic cuts and no HUD.
## Meant to be recorded with Godot's movie maker (see tools/shorts and .github/workflows/shorts-video.yml):
##   godot --path godot --resolution 1080x1920 --fixed-fps 30 --write-movie out/freeze.avi -s res://tests/short.gd -- --shot=freeze --seed=3 --len=14
## --shot=freeze  it walks up to where you stand still; the beat breaks and it charges (suspense, then action)
## --shot=chase   it charges from behind and you sprint away along the streets
## --flare=4.5    throw the flare at that second (the creature is drawn to it)
## --len=SECONDS  how long the shot lasts, then the program quits
extends SceneTree

const FPS := 30.0

var g: Game
var shot := "chase"
var seed_n := 1
var length := 12.0
var flare_at := -1.0
var beat := 7.0          # freeze: when it charges
var f := 0
var started := -1
var wp: Array = []
var last_p := Vector2()
var still_t := 0.0
var flared := false
var broke := false
var rig: Node

## Runs after the game's own _process (higher priority number = later), so it can take the camera over.
class Rig extends Node:
	var d

	func _init(p_d) -> void:
		d = p_d
		process_priority = 100

	func _process(_dt: float) -> void:
		d.camera()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--seed="):
			seed_n = int(a.substr(7))
		elif a.begins_with("--len="):
			length = float(a.substr(6))
		elif a.begins_with("--flare="):
			flare_at = float(a.substr(8))
		elif a.begins_with("--beat="):
			beat = float(a.substr(7))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	rig = Rig.new(self)
	root.add_child(rig)

func _process(dt: float) -> bool:
	f += 1
	if g == null:
		var m := root.get_child(0)
		if m.get_child_count():
			g = m.get_child(0) as Game
		return false
	if started < 0:
		if g.phase == "menu" and f > 10:
			setup()
			started = f
		return false
	var t := (f - started) / FPS
	match shot:
		"freeze":
			freeze(t, dt)
		_:
			chase(t, dt)
	if flare_at >= 0.0 and not flared and t >= flare_at:
		flared = true
		g.flares = 1
		g.throw_flare()
	if t >= length:
		print("shot %s done: phase %s, creature %s" % [shot, g.phase, g.mon.state])
		quit(0)
	return false

# ---------------------------------------------------------------- setup
func setup() -> void:
	seed(seed_n)
	g.start_game()
	g.settings.gfx = "high"
	g.apply_gfx()
	g.hud.visible = false
	# a storm, as the Shorts want rain and lightning
	g.wx_i = 0.95
	g.wx_to = 0.95
	g.wx_t = 9999.0
	g.dir.next_lightning = 2.0
	g.dir.next_cross = 9999.0
	g.dir.next_phantom = 9999.0
	g.dir.next_siren = 9999.0
	g.time = 0.0
	g.call_t = 9999.0
	g.hud.input.sprint = false
	var p := Vector2(g.pl.pos.x, g.pl.pos.z)
	if shot == "freeze":
		g.pl.flash = false
		g.hud.set_toggle("light", false)
		place_freeze(p)
	else:
		g.pl.flash = true
		place_chase(p)
	print("shot %s, seed %d, player at %s, creature at %s" % [shot, seed_n, p.round(), Vector2(g.mon.pos.x, g.mon.pos.z).round()])

## The creature goes where it can be seen coming: a street spot 30 to 45 m from the player, on a clear line.
func far_spot(p: Vector2, lo: float, hi: float) -> Vector2:
	var best := Vector2(INF, INF)
	var bd := INF
	for n in g.nodes:
		var q := Vector2(n.x, n.z)
		var d := q.distance_to(p)
		if d >= lo and d <= hi and g.col.walkable(q.x, q.y, 2.2) and g.col.path_clear(q.x, q.y, p.x, p.y, 1.0):
			if d < bd:
				bd = d
				best = q
	if best.x == INF:
		for n in g.nodes:
			var q := Vector2(n.x, n.z)
			var d := q.distance_to(p)
			if d >= lo and d <= hi and g.col.walkable(q.x, q.y, 2.2) and d < bd:
				bd = d
				best = q
	return best

func place_freeze(p: Vector2) -> void:
	var q := far_spot(p, 30.0, 48.0)
	if q.x == INF:
		q = p + Vector2(35, 0)
	g.mon.pos = Vector3(q.x, 0.0, q.y)
	g.mon.yaw = atan2(p.x - q.x, p.y - q.y)
	g.mon.cur = g.nearest_node(q.x, q.y, true)
	# it comes to investigate a noise a few metres short of him and stops to sniff and scan
	var dir := (p - q).normalized()
	var spot := p
	for k in [10.0, 12.0, 9.0, 14.0, 8.0]:
		var c: Vector2 = p - dir * k
		if g.col.walkable(c.x, c.y, 2.2) and g.col.path_clear(q.x, q.y, c.x, c.y, 1.6):
			spot = c
			break
	g.mon.hear(spot.x, spot.y)
	g.mon.lure_t = 6.0
	g.pl.crouch = true
	g.hud.set_toggle("crouch", true)

func place_chase(p: Vector2) -> void:
	var q := far_spot(p, 14.0, 22.0)
	if q.x == INF:
		q = p + Vector2(-16, 0)
	g.mon.pos = Vector3(q.x, 0.0, q.y)
	g.mon.yaw = atan2(p.x - q.x, p.y - q.y)
	g.mon.cur = g.nearest_node(q.x, q.y, true)
	g.mon.start_chase()
	route_away()

## Streets to run along: the farthest node (60 to 110 m) from the creature that is reachable from here.
func route_away() -> void:
	var p := Vector2(g.pl.pos.x, g.pl.pos.z)
	var m := Vector2(g.mon.pos.x, g.mon.pos.z)
	var best := -1
	var bs := -INF
	for i in g.nodes.size():
		var q := Vector2(g.nodes[i].x, g.nodes[i].z)
		var d := q.distance_to(p)
		if d < 60.0 or d > 110.0:
			continue
		var s := q.distance_to(m) - 0.5 * d
		if s > bs:
			bs = s
			best = i
	if best < 0:
		best = g.nearest_node(p.x + 60.0, p.y, false)
	wp = []
	for i in g.bfs(g.nearest_node(p.x, p.y, true), best):
		wp.append(Vector2(g.nodes[i].x, g.nodes[i].z))

# ---------------------------------------------------------------- the shots
func freeze(t: float, dt: float) -> void:
	var inp: Dictionary = g.hud.input
	var ahead := t >= beat
	if not ahead:
		# it must not notice him before the beat; the ground shakes and the tension builds
		g.mon.awareness = minf(g.mon.awareness, 0.3)
		inp.jx = 0.0
		inp.jy = 0.0
		face_creature(dt)
	elif not broke:
		broke = true
		g.lightning(1.0)
		g.mon.start_chase()
		g.pl.crouch = false
		g.hud.set_toggle("crouch", false)
		g.pl.flash = true
		g.hud.set_toggle("light", true)
		route_away()
	else:
		steer(dt)

func chase(_t: float, dt: float) -> void:
	steer(dt)

## Sprints along the waypoints.
func steer(dt: float) -> void:
	var inp: Dictionary = g.hud.input
	inp.jx = 0.0
	inp.jy = 0.0
	inp.sprint = true
	if wp.is_empty():
		route_away()
		return
	var p := Vector2(g.pl.pos.x, g.pl.pos.z)
	while wp.size() > 1 and p.distance_to(wp[0]) < 2.0:
		wp.pop_front()
	var d: Vector2 = wp[0] - p
	var want := atan2(d.x, d.y)
	g.pl.cam_yaw += U.ang_diff(g.pl.cam_yaw, want) * minf(1.0, dt * 6.0)
	inp.jy = 1.0
	if p.distance_to(last_p) < 0.02:
		still_t += dt
		if still_t > 1.5:
			route_away()
			still_t = 0.0
	else:
		still_t = 0.0
	last_p = p

func face_creature(dt: float) -> void:
	var want := atan2(g.mon.pos.x - g.pl.pos.x, g.mon.pos.z - g.pl.pos.z)
	g.pl.cam_yaw += U.ang_diff(g.pl.cam_yaw, want) * minf(1.0, dt * 2.0)

# ---------------------------------------------------------------- the camera
## Which shot the camera is on at time t: the cut list for each shot.
func cut(t: float) -> String:
	if shot == "freeze":
		if t < 2.0:
			return "face"
		if t < beat - 1.5:
			return "watch"
		if t < beat + 0.8:
			return "face"
		if t < beat + 3.5:
			return "side"
		return "watch"
	if t < 2.0:
		return "side"
	if t < 5.5:
		return "watch"
	if t < 7.5:
		return "side"
	return "watch"

func camera() -> void:
	if g == null or started < 0:
		return
	var t := (f - started) / FPS
	var m: Monster = g.mon
	var fwd := Vector3(sin(m.yaw), 0.0, cos(m.yaw))
	var right := Vector3(-cos(m.yaw), 0.0, sin(m.yaw))
	var c: Camera3D = g.cam
	var jit := Vector3(sin(t * 23.0), sin(t * 31.0 + 1.0), 0.0) * 0.03 * minf(1.0, g.tremor + 0.3)
	match cut(t):
		"face":
			var head := m.pos + fwd * 3.6 + Vector3(0, 2.8, 0)
			c.position = head + fwd * 9.0 + Vector3(0.0, -1.7, 0.0) + right * 1.5 * sin(t * 0.5) + jit
			c.fov = 58.0
			c.look_at(head + Vector3(0, 0.1, 0))
		"side":
			c.position = m.pos + fwd * 2.5 + right * (7.5 + 1.0 * sin(t * 0.7)) + Vector3(0, 0.9, 0) + jit
			c.fov = 66.0
			c.look_at(m.pos + fwd * 1.5 + Vector3(0, 2.0, 0))
		_:
			pass   # the game's own camera over the player's shoulder, already placed
