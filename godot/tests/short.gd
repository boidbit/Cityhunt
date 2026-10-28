## Shorts director: plays one scripted action shot for a vertical video, in daylight, with cinematic cuts and no HUD.
## Meant to be recorded with Godot's movie maker (see tools/shorts and .github/workflows/shorts-video.yml):
##   godot --path godot --resolution 1080x1920 --fixed-fps 30 --write-movie out/clip.avi -s res://tests/short.gd -- --shot=carchase --seed=3 --len=26
## --shot=carchase  you drive, the T-Rex right behind; it bites the car, then throws it over (close-up chase)
## --shot=chase     on foot, it charges from behind and you sprint away along the streets
## --shot=freeze    on foot, it walks up to where you stand still; the beat breaks and it charges
## --bite=SECONDS   carchase: when it is let catch up and bite (-1: never)
## --flare=4.5      chase: throw the flare at that second (the creature is drawn to it)
## --len=SECONDS    how long the shot lasts, then the program quits
## Every half second a line of trace is printed, and at the end all of it as one ::notice for the Actions page.
extends SceneTree

const FPS := 30.0
const CUTS := ["front_low", "dash_back", "side_low", "dash_back", "rex_pov"]

var g: Game
var shot := "carchase"
var seed_n := 1
var length := 26.0
var flare_at := -1.0
var beat := 7.0
var bite_at := 12.0
var f := 0
var started := -1
var wp: Array = []
var last_p := Vector2()
var still_t := 0.0
var rev_t := 0.0
var flared := false
var broke := false
var car: Variant = null
var bite_t := -99.0      # when the first bite landed
var unpaused := 0        # how many times the game paused itself and was set going again
var trace: Array = []
var trace_at := 0.0
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
		elif a.begins_with("--bite="):
			bite_at = float(a.substr(7))
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
	# the game pauses itself when its window loses focus (as on a phone); on the virtual screen that happens
	# a few seconds in and would freeze the rest of the video
	if g.paused:
		g.paused = false
		g.sfx.pause_all(false)
		unpaused += 1
	match shot:
		"freeze":
			freeze(t, dt)
		"chase":
			chase(t, dt)
		_:
			carchase(t, dt)
	if car != null and bite_t < 0.0 and car.hp < Vehicles.HP:
		bite_t = t
	if flare_at >= 0.0 and not flared and t >= flare_at:
		flared = true
		g.flares = 1
		g.throw_flare()
	if t >= trace_at:
		trace_at += 0.5
		log_trace(t)
	if t >= length:
		print("shot %s done: phase %s, creature %s" % [shot, g.phase, g.mon.state])
		print("::notice title=trace %s seed %d::%s" % [shot, seed_n, "%0A".join(trace)])
		quit(0)
	return false

func log_trace(t: float) -> void:
	var d := Vector2(g.mon.pos.x - g.pl.pos.x, g.mon.pos.z - g.pl.pos.z).length()
	var sp: float = absf(car.speed) if car != null and g.pl.driving else g.pl.real_sp
	var line := "t=%4.1f phase=%s rex=%s dist=%.0fm speed=%.1f cam=%s unpaused=%d%s" % [t, g.phase, g.mon.state, d, sp, cut(t), unpaused,
		(" car=%s hp=%d" % [car.state, car.hp]) if car != null else ""]
	trace.append(line)
	print(line)

# ---------------------------------------------------------------- setup
func setup() -> void:
	seed(seed_n)
	g.set_daylight(true)
	g.start_game()
	g.settings.gfx = "high"
	g.apply_gfx()
	g.hud.visible = false
	# light rain by day: wet streets, no lightning
	g.wx_i = 0.55
	g.wx_to = 0.55
	g.wx_t = 9999.0
	g.dir.next_lightning = 9999.0
	g.dir.next_cross = 9999.0
	g.dir.next_phantom = 9999.0
	g.dir.next_siren = 9999.0
	g.time = 0.0
	g.call_t = 9999.0
	g.hud.input.sprint = false
	var p := Vector2(g.pl.pos.x, g.pl.pos.z)
	match shot:
		"freeze":
			place_freeze(p)
		"chase":
			place_chase(p)
		_:
			place_carchase(p)
	print("shot %s, seed %d, player at %s, creature at %s" % [shot, seed_n, p.round(), Vector2(g.mon.pos.x, g.mon.pos.z).round()])

## A street spot between lo and hi metres from p with a clear line to it, the nearest such one.
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

## Puts the creature on a clear spot k metres behind (from, heading dir), facing along dir.
func rex_behind(from: Vector2, dir: Vector2, k: float) -> void:
	var at := from - dir * k
	for kk in [k, k * 0.8, k * 1.25, k * 0.65, k * 1.5]:
		var c: Vector2 = from - dir * kk
		if g.col.walkable(c.x, c.y, 2.2) and g.col.path_clear(c.x, c.y, from.x, from.y, 1.2):
			at = c
			break
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.yaw = atan2(dir.x, dir.y)
	g.mon.cur = g.nearest_node(at.x, at.y, true)

## Streets to follow: a seeded random node 70 to 150 m from here, reached along the street graph.
func plan_route(from: Vector2) -> void:
	var a := g.nearest_node(from.x, from.y, false)
	var best := -1
	var bs := -INF
	for i in g.nodes.size():
		var q := Vector2(g.nodes[i].x, g.nodes[i].z)
		var d := q.distance_to(from)
		if d < 70.0 or d > 150.0:
			continue
		var s := randf()
		if s > bs:
			bs = s
			best = i
	wp = []
	if best >= 0:
		for i in g.bfs(a, best):
			wp.append(Vector2(g.nodes[i].x, g.nodes[i].z))
	if wp.is_empty():
		wp.append(from + Vector2(50, 0))

func place_carchase(p: Vector2) -> void:
	# the fastest parked car near the start
	var best: Variant = null
	var bs := INF
	for c in g.veh.cars:
		if c.state != "parked":
			continue
		var d: float = (c.pos as Vector2).distance_to(p)
		var s := d - (25.0 if c.vm == "agera" else 0.0)
		if d < 90.0 and s < bs:
			bs = s
			best = c
	if best == null:
		for c in g.veh.cars:
			if c.state == "parked":
				best = c
				break
	car = best
	var cp: Vector2 = car.pos
	plan_route(cp)
	var dir := Vector2.from_angle(-car.yaw)
	if wp.size() > 1:
		dir = (wp[1] - cp).normalized() if cp.distance_to(wp[0]) < 6.0 else (wp[0] - cp).normalized()
	car.yaw = -dir.angle()
	g.pl.pos = Vector3(cp.x, g.world.ground_at(cp.x, cp.y, 0.0), cp.y)
	g.enter_car(car)
	rex_behind(cp, dir, 16.0)
	g.mon.start_chase()
	g.mon.last_seen_t = g.time

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
	var q := far_spot(p, 26.0, 38.0)
	if q.x == INF:
		q = p + Vector2(-30, 0)
	g.mon.pos = Vector3(q.x, 0.0, q.y)
	g.mon.yaw = atan2(p.x - q.x, p.y - q.y)
	g.mon.cur = g.nearest_node(q.x, q.y, true)
	g.mon.start_chase()
	route_away()

## Streets to run along on foot: the farthest node (60 to 110 m) from the creature that is reachable from here.
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
## Drives the streets with the creature right behind: the gap it keeps is the drama. At first it stays about
## 14 m back (close in every shot), from bite_at it is let catch up, bites (a shove), bites again (over she goes).
func carchase(t: float, dt: float) -> void:
	var inp: Dictionary = g.hud.input
	inp.jx = 0.0
	inp.jy = 0.0
	var c: Variant = car
	if c == null or not g.pl.driving or c.state != "driven":
		return
	g.mon.last_seen_t = g.time
	g.mon.last_known = g.pl.pos
	var cp: Vector2 = c.pos
	while wp.size() > 1 and cp.distance_to(wp[0]) < 8.0:
		wp.pop_front()
	if wp.size() <= 1 and (wp.is_empty() or cp.distance_to(wp[0]) < 8.0):
		plan_route(cp)
	var fv: Vector2 = g.veh.forward(c)
	var want := atan2(wp[0].y - cp.y, wp[0].x - cp.x)
	var err := U.ang_diff(atan2(fv.y, fv.x), want)
	var steer := clampf(err * 2.2, -1.0, 1.0)
	var gap := cp.distance_to(Vector2(g.mon.pos.x, g.mon.pos.z))
	var goal := 5.0 if bite_at >= 0.0 and t >= bite_at else 14.0
	var des := clampf(11.0 + (gap - goal) * 0.9, 5.0, 24.0) * (1.0 - 0.55 * minf(1.0, absf(err) / 1.2))
	var thr := clampf((des - c.speed) * 0.5, -0.5, 1.0)
	# wedged against something: back out
	if absf(c.speed) < 1.0 and t > 2.0:
		still_t += dt
	else:
		still_t = 0.0
	if still_t > 1.2:
		rev_t = 0.9
		still_t = 0.0
	if rev_t > 0.0:
		rev_t -= dt
		thr = -1.0
		steer = -steer
	inp.jy = thr
	inp.jx = steer

func freeze(t: float, dt: float) -> void:
	var inp: Dictionary = g.hud.input
	if t < beat:
		# it must not notice him before the beat; the ground shakes and the tension builds
		g.mon.awareness = minf(g.mon.awareness, 0.3)
		inp.jx = 0.0
		inp.jy = 0.0
		face_creature(dt)
	elif not broke:
		broke = true
		g.mon.start_chase()
		g.pl.crouch = false
		g.hud.set_toggle("crouch", false)
		route_away()
	else:
		steer_foot(dt)

func chase(_t: float, dt: float) -> void:
	steer_foot(dt)

## Sprints along the waypoints.
func steer_foot(dt: float) -> void:
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
	if shot == "carchase":
		if car == null or car.state == "tumble" or not g.pl.driving:
			return "game"
		if bite_t >= 0.0 and t - bite_t < 1.3:
			return "side_low"
		return CUTS[int(t / 1.7) % CUTS.size()]
	if shot == "freeze":
		if t < 2.0:
			return "face"
		if t < beat - 1.5:
			return "game"
		if t < beat + 0.8:
			return "face"
		if t < beat + 3.5:
			return "side"
		return "game"
	if t < 2.0:
		return "side"
	if t < 5.5:
		return "game"
	if t < 7.5:
		return "side"
	return "game"

## A camera position pulled in short of a wall between from and want.
func pulled(from: Vector3, want: Vector3) -> Vector3:
	var k: float = g.col.ray3(from, want, 0.25)
	return from.lerp(want, clampf(k * 0.92, 0.12, 1.0))

func camera() -> void:
	if g == null or started < 0:
		return
	var t := (f - started) / FPS
	var mode := cut(t)
	if mode == "game":
		return   # the game's own camera over the player's shoulder or behind the car
	var m: Monster = g.mon
	var fwd := Vector3(sin(m.yaw), 0.0, cos(m.yaw))
	var right := Vector3(-cos(m.yaw), 0.0, sin(m.yaw))
	var c: Camera3D = g.cam
	var shake := minf(1.0, g.tremor + 0.3)
	var jit := Vector3(sin(t * 23.0), sin(t * 31.0 + 1.0), 0.0) * 0.03 * shake
	var rhead := m.pos + fwd * 3.4 + Vector3(0, 3.0, 0)
	if car != null and shot == "carchase":
		var fv: Vector2 = g.veh.forward(car)
		var cf := Vector3(fv.x, 0.0, fv.y)
		var cr := Vector3(-fv.y, 0.0, fv.x)
		var cpos := Vector3(car.pos.x, car.y, car.pos.y)
		var wobble := jit * (1.0 + absf(car.speed) * 0.25)
		match mode:
			"front_low":
				# ahead of the car, low, looking back along it: the creature fills the gap behind it
				c.position = pulled(cpos + Vector3(0, 1.0, 0), cpos + cf * 6.5 + cr * 1.4 * sin(t * 0.8) + Vector3(0, 0.9, 0)) + wobble
				c.fov = 70.0
				c.look_at(cpos.lerp(rhead, 0.4) + Vector3(0, 0.6, 0))
			"dash_back":
				# on the boot looking back at it
				c.position = cpos - cf * 1.5 + Vector3(0, 1.5, 0) + wobble
				c.fov = 76.0
				c.look_at(rhead)
			"side_low":
				c.position = pulled(cpos + Vector3(0, 0.8, 0), cpos + cr * 5.5 - cf * 2.0 + Vector3(0, 0.7, 0)) + wobble
				c.fov = 64.0
				c.look_at(cpos.lerp(rhead, 0.4) + Vector3(0, 1.0, 0))
			_:
				# over the creature's back at the car
				c.position = m.pos - fwd * 2.5 + right * 2.0 + Vector3(0, 4.6, 0) + wobble
				c.fov = 60.0
				c.look_at(cpos + Vector3(0, 1.0, 0))
		return
	match mode:
		"face":
			var head := m.pos + fwd * 3.6 + Vector3(0, 2.8, 0)
			c.position = head + fwd * 9.0 + Vector3(0.0, -1.7, 0.0) + right * 1.5 * sin(t * 0.5) + jit
			c.fov = 58.0
			c.look_at(head + Vector3(0, 0.1, 0))
		"side":
			c.position = m.pos + fwd * 2.5 + right * (7.5 + 1.0 * sin(t * 0.7)) + Vector3(0, 0.9, 0) + jit
			c.fov = 66.0
			c.look_at(m.pos + fwd * 1.5 + Vector3(0, 2.0, 0))
