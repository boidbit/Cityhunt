## Shorts director: plays one scripted, satisfying action moment for a vertical Short (1080x1920), on a bright,
## dry day, with cinematic cuts, slow motion and no HUD. Recorded with Godot's movie maker on a GitHub server
## (see tools/shorts and .github/workflows/shorts-video.yml):
##   godot --path godot --resolution 1080x1920 --fixed-fps 30 --write-movie out/clip.avi -s res://tests/short.gd -- --mode=flip --seed=3
## --mode=flip      the T-Rex runs the car down, bites it twice and throws it over (slow motion in the air)
## --mode=ram       the car floors it straight at the T-Rex and rams it (slow motion at the hit), then gets away
## --mode=domino    the T-Rex charges down a street of parked cars, throwing them aside one after another
## --mode=nearmiss  its jaws snap shut on the boot three times and miss; the car pulls away and it roars
## --mode=freeze    he hides beside a car while it walks up, sniffs about a few metres off and walks on
## --seed=N         where in the city it happens (and the small random choices)
## Do not call a flag --shot, --frames, --day, --play, --loc or --stats: the game itself reads those (--shot=x quits it after 60 frames).
## Every half second a trace line is printed, and "EVENT name seconds" lines for what happened when (bite, flip, land,
## ram, toss_N, snap_N, roar, slow_on_N/slow_off_N, heart_on/heart_off, end): tools/shorts/compose.py lays the sound
## effects and captions on those. Times are seconds of video, which run on while the game is slowed down.
extends SceneTree

const FX := preload("res://tests/short_fx.gd")
const MAX_LEN := 34.0
const LUNGES := [3.4, 7.0, 10.6]   # nearmiss: when its jaws snap at the boot

var g: Game
var fx: FX
var recipe := "flip"
var seed_n := 1
var fps := 30.0          # frames recorded a second (--fps, the same as Godot's --fixed-fps); more blur into one
var f := 0
var started := -1
var done_at := -1.0
var events := {}         # name -> second it first happened
var trace: Array = []
var trace_at := 0.0
var rig: Node
var unpaused := 0
var bites := 0

# the car he drives
var car: Variant = null
var last_hp := 0
var wp: Array = []
var cruise := 13.0
var still_t := 0.0
var rev_t := 0.0
var hold_until := -1.0
var away := Vector2(INF, INF)    # plan routes away from here (after the ram)
var track: Array[Vector2] = []   # where the car has been, oldest first
var follow := false              # the creature runs `gap` behind the car along its track
var gap := 13.0

# the creature on a path of its own
var walk := false
var rpath: Array = []
var rs := 0.0
var rdir := 1.0
var rspeed := 0.0
var face_to := Vector2(INF, INF) # turn its head this way while it stands

# domino and freeze
var lined: Array = []            # the parked cars set out in its way
var tossed := 0
var hide := Vector2()
var stop_s := 0.0
var pause_until := -1.0

# slow motion and locked cameras
var slow_n := 0
var slow_until := -1.0
var lock := {}

## Runs after the game's own _process (higher priority number = later): puts the creature where the shot
## wants it and takes the camera over.
class Rig extends Node:
	var d

	func _init(p_d) -> void:
		d = p_d
		process_priority = 100

	func _process(dt: float) -> void:
		d.after_game(dt)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			recipe = a.substr(7)
		elif a.begins_with("--seed="):
			seed_n = int(a.substr(7))
		elif a.begins_with("--fps="):
			fps = float(a.substr(6))
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
	var t := now()
	# the game pauses itself when its window loses focus (as on a phone), which a virtual screen can do
	if g.paused:
		g.paused = false
		g.sfx.pause_all(false)
		unpaused += 1
	if car != null and car.hp < last_hp:
		last_hp = car.hp
		if recipe != "ram":
			bites += 1
			mark("bite_%d" % bites, t)
			hold_until = t + 2.5
	match recipe:
		"ram":
			step_ram(t, dt)
		"domino":
			step_domino(t)
		"nearmiss":
			step_nearmiss(t, dt)
		"freeze":
			step_freeze(t)
		_:
			step_flip(t, dt)
	if walk:
		rs = clampf(rs + rspeed * rdir * dt, 0.0, poly_len(rpath))
		g.mon.speed = rspeed
	if slow_until >= 0.0 and t >= slow_until:
		slow_until = -1.0
		Engine.time_scale = 1.0
		AudioServer.set_bus_volume_db(0, 0.0)
		mark("slow_off_%d" % slow_n, t)
	if t >= trace_at:
		trace_at += 0.5
		log_trace(t)
	if (done_at >= 0.0 and t >= done_at) or t >= MAX_LEN:
		Engine.time_scale = 1.0
		mark("end", t)
		print("shot %s done: phase %s, creature %s" % [recipe, g.phase, g.mon.state])
		quit(0)
	return false

func now() -> float:
	return (f - started) / fps

func after_game(dt: float) -> void:
	if g == null or started < 0:
		return
	place_rex()
	if recipe == "domino" or (recipe == "flip" and events.has("flip")):
		g.pl.actor.visible = false
	fx.update(dt)
	camera(now(), dt)

## Notes when something happened, once.
func mark(what: String, t: float) -> void:
	if events.has(what):
		return
	events[what] = t
	var line := "EVENT %s %.2f" % [what, t]
	trace.append(line)
	print(line)
	react(what)

## Sparks, glass, debris and dust where the hits land.
func react(what: String) -> void:
	if car == null:
		return
	var fv: Vector2 = g.veh.forward(car)
	var cf := Vector3(fv.x, 0.0, fv.y)
	var cpos := Vector3(car.pos.x, car.y, car.pos.y)
	var hl: float = car.size.x * 0.5
	if what.begins_with("bite"):
		fx.burst("bite", cpos - cf * hl + Vector3(0, 1.0, 0), Vector3.UP - cf)
	elif what == "flip":
		fx.burst("impact", cpos + Vector3(0, 1.0, 0), Vector3.UP)
	elif what == "land":
		fx.burst("land", cpos, Vector3.UP)
	elif what == "ram":
		var m := g.mon
		var hit := (cpos + cf * hl).lerp(m.pos, 0.3) + Vector3(0, 1.0, 0)
		fx.burst("impact", hit, Vector3.UP * 0.8 - cf)

func end_after(t: float, sec: float) -> void:
	if done_at < 0.0:
		done_at = t + sec

## Slow motion for dur seconds of video; the game's own sound is turned down meanwhile (the effects laid on
## afterwards carry it).
func slow(t: float, dur: float, scale: float) -> void:
	slow_n += 1
	slow_until = t + dur
	Engine.time_scale = scale
	AudioServer.set_bus_volume_db(0, -16.0)
	mark("slow_on_%d" % slow_n, t)

func log_trace(t: float) -> void:
	var d := Vector2(g.mon.pos.x - g.pl.pos.x, g.mon.pos.z - g.pl.pos.z).length()
	var sp: float = absf(car.speed) if car != null and g.pl.driving else g.pl.real_sp
	var line := "t=%4.1f phase=%s rex=%s dist=%.0fm speed=%.1f cam=%s scale=%.2f%s" % [t, g.phase, g.mon.state, d, sp, cut(t),
		Engine.time_scale, (" car=%s hp=%d" % [car.state, car.hp]) if car != null else ""]
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
	# dry: no rain, no lightning, nothing the director of the game would stage
	g.wx_i = 0.0
	g.wx_to = 0.0
	g.wx_t = 9999.0
	g.dir.next_lightning = 9999.0
	g.dir.next_cross = 9999.0
	g.dir.next_phantom = 9999.0
	g.dir.next_siren = 9999.0
	g.time = 0.0
	g.call_t = 9999.0
	g.hud.input.sprint = false
	g.pl.flash = false
	g.cam.keep_aspect = Camera3D.KEEP_HEIGHT
	bright()
	solid_cars()
	fx = FX.new(g)
	var p := Vector2(g.pl.pos.x, g.pl.pos.z)
	match recipe:
		"ram":
			setup_ram(p)
		"domino":
			setup_domino()
		"nearmiss":
			setup_chase(p)
		"freeze":
			setup_freeze()
		_:
			setup_chase(p)
	print("shot %s, seed %d, player at %s, creature at %s" % [recipe, seed_n, Vector2(g.pl.pos.x, g.pl.pos.z).round(), Vector2(g.mon.pos.x, g.mon.pos.z).round()])

## A bright, clear day: a blue haze instead of the grey rain-washed one, lighter shade, a little more exposure.
func bright() -> void:
	var w := g.world
	w.fog_base = Color(0.5, 0.62, 0.8)
	w.fog_end = 900.0
	for e in [w.env, w.refl_env]:
		if e == null:
			continue
		e.background_color = w.fog_base.linear_to_srgb()
		e.ambient_light_color = Color(0.6, 0.63, 0.68).linear_to_srgb()
		e.tonemap_exposure = 1.2
	w.sky_mat.set_shader_parameter("hor", w.fog_base)
	w.skyline_mat.set_shader_parameter("hor", w.fog_base)

## The car models are shells with no floor, their panels drawn from outside only: turned over, you would see
## straight through them to the sky. Drawn from both sides (the paint shader makes the inside dark), a car on
## its roof looks solid.
func solid_cars() -> void:
	var done := {}
	for c in g.veh.cars:
		for role in c.meshes:
			for mi in c.meshes[role]:
				var gi := mi as GeometryInstance3D
				if gi == null or gi.material_override == null:
					continue
				var m: Material = gi.material_override
				if not done.has(m):
					done[m] = g.world._two_sided(m)
				var paint = gi.get_instance_shader_parameter("paint")
				var livery = gi.get_instance_shader_parameter("livery")
				gi.material_override = done[m]
				if paint != null:
					gi.set_instance_shader_parameter("paint", paint)
				if livery != null:
					gi.set_instance_shader_parameter("livery", livery)

# ---------------------------------------------------------------- paths
func poly_len(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += (pts[i] as Vector2).distance_to(pts[i - 1])
	return l

## The point s metres along the polyline (clamped to its ends).
func poly_at(pts: Array, s: float) -> Vector2:
	if pts.is_empty():
		return Vector2()
	var left := maxf(s, 0.0)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		if left <= seg and seg > 0.0:
			return a.lerp(b, left / seg)
		left -= seg
	return pts[-1]

func poly_dir(pts: Array, s: float) -> Vector2:
	var d := poly_at(pts, s + 1.5) - poly_at(pts, s - 1.5)
	return d.normalized() if d.length() > 0.001 else Vector2(0, 1)

## How far along the polyline its nearest point to q is.
func poly_closest(pts: Array, q: Vector2) -> float:
	var best := 0.0
	var bd := INF
	var s := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		var u := 0.0
		if seg > 0.0:
			u = clampf((q - a).dot(b - a) / (seg * seg), 0.0, 1.0)
		var d := a.lerp(b, u).distance_to(q)
		if d < bd:
			bd = d
			best = s + u * seg
		s += seg
	return best

## Streets to drive: a seeded random node 70 to 150 m off, along the street graph; after the ram, one well away
## from where the creature stands.
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
		if away.x != INF:
			s += q.distance_to(away) / 60.0
		if s > bs:
			bs = s
			best = i
	wp = []
	if best >= 0:
		for i in g.bfs(a, best):
			wp.append(Vector2(g.nodes[i].x, g.nodes[i].z))
	if wp.is_empty():
		wp.append(from + Vector2(50, 0))

# ---------------------------------------------------------------- the car
func pick_car(p: Vector2) -> void:
	var best: Variant = null
	var bs := INF
	for c in g.veh.cars:
		if c.state != "parked":
			continue
		var d: float = (c.pos as Vector2).distance_to(p)
		var s := d - (25.0 if c.vm == "agera" else 0.0) + randf() * 10.0
		if d < 90.0 and s < bs:
			bs = s
			best = c
	if best == null:
		for c in g.veh.cars:
			if c.state == "parked":
				best = c
				break
	car = best
	last_hp = car.hp

## Puts him in the car facing along the route, with the game's chase camera already pulled back behind it
## (left to itself it starts close, inside the car).
func get_in() -> Vector2:
	var cp: Vector2 = car.pos
	plan_route(cp)
	var dir := Vector2.from_angle(-car.yaw)
	if wp.size() > 1:
		dir = ((wp[1] if cp.distance_to(wp[0]) < 6.0 else wp[0]) - cp).normalized()
	car.yaw = -dir.angle()
	g.pl.pos = Vector3(cp.x, g.world.ground_at(cp.x, cp.y, 0.0), cp.y)
	g.enter_car(car)
	g.pl.cam_cur = 8.0
	g.pl.cam_yaw = atan2(dir.x, dir.y)
	for k in range(100, -1, -1):
		track.append(cp - dir * (k * 0.4))
	return dir

## One frame of driving along the route at `cruise`, slowing for bends and backing out when wedged.
func drive(t: float, dt: float) -> void:
	var inp: Dictionary = g.hud.input
	inp.jx = 0.0
	inp.jy = 0.0
	inp.sprint = false
	if car == null or not g.pl.driving or car.state != "driven":
		return
	var cp: Vector2 = car.pos
	var reach := 8.0 + absf(car.speed) * 0.6
	while wp.size() > 1 and cp.distance_to(wp[0]) < reach:
		wp.pop_front()
	if wp.is_empty() or (wp.size() == 1 and cp.distance_to(wp[0]) < reach):
		plan_route(cp)
	var fv: Vector2 = g.veh.forward(car)
	var want := atan2(wp[0].y - cp.y, wp[0].x - cp.x)
	var err := U.ang_diff(atan2(fv.y, fv.x), want)
	var steer := clampf(err * 2.2, -1.0, 1.0)
	var des := maxf(cruise * (1.0 - 0.6 * minf(1.0, absf(err) / 0.9)), 4.0)
	var thr := clampf((des - car.speed) * 0.6, -0.5, 1.0)
	if absf(car.speed) < 1.0 and t > 2.0 and t > hold_until:
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

## Keeps the creature on his trail while he drives.
func keep_chasing() -> void:
	var m := g.mon
	if m.state == "STUN" or m.state == "ATTACK":
		return
	if m.state != "CHASE":
		m.set_state("CHASE")
	m.awareness = 1.0
	m.last_seen_t = g.time
	m.last_known = g.pl.pos
	if follow and car != null:
		m.speed = clampf(absf(car.speed) + 3.0, 6.0, 11.0)

# ---------------------------------------------------------------- the creature
## Where the shot wants the creature this frame, after the game has moved it: on the car's track `gap`
## behind it, or `rs` along its own path.
func place_rex() -> void:
	var m := g.mon
	var p := Vector2()
	var h := Vector2()
	if follow and car != null and g.pl.driving and car.state == "driven":
		var cp: Vector2 = car.pos
		if track.is_empty() or track[-1].distance_to(cp) > 0.4:
			track.append(cp)
			if track.size() > 500:
				track.remove_at(0)
		p = point_behind(gap)
		h = p - point_behind(gap + 3.0)
	elif walk:
		p = poly_at(rpath, rs)
		h = poly_dir(rpath, rs) * rdir
	else:
		return
	m.pos = Vector3(p.x, 0.0, p.y)
	if face_to.x != INF:
		m.yaw += U.ang_diff(m.yaw, atan2(face_to.x - p.x, face_to.y - p.y)) * 0.05
	elif h.length() > 0.01:
		m.yaw = atan2(h.x, h.y)
	m.actor.position = Vector3(p.x, g.world.ground_at(p.x, p.y, 0.0), p.y)
	m.actor.rotation.y = m.yaw

## The spot d metres back along the car's track.
func point_behind(d: float) -> Vector2:
	var left := d
	var prev: Vector2 = car.pos
	for i in range(track.size() - 1, -1, -1):
		var seg := prev.distance_to(track[i])
		if seg >= left and seg > 0.0:
			return prev.lerp(track[i], left / seg)
		left -= seg
		prev = track[i]
	return prev

# ---------------------------------------------------------------- flip and nearmiss: chased by car
func setup_chase(p: Vector2) -> void:
	pick_car(p)
	var dir := get_in()
	fx.rig_wheels(car)
	var cp: Vector2 = car.pos
	var at := cp - dir * gap
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.yaw = atan2(dir.x, dir.y)
	g.mon.start_chase()
	follow = true

## Close behind for ten seconds (its jaws snap once, short of the boot), then it closes in: a bite that shoves
## the car, a second that throws it over (slow motion in the air). It lands on its roof; the creature walks up
## to the wreck, sniffs at it and roars. He stays inside: nobody climbs out of that.
func step_flip(t: float, dt: float) -> void:
	var m := g.mon
	if not events.has("flip"):
		drive(t, dt)
		keep_chasing()
		var dip := 1.0 - clampf(absf(t - 5.5) / 1.1, 0.0, 1.0)
		gap = 13.0 - 3.5 * smoothstep(0.0, 1.0, dip) if t < 10.0 else lerpf(13.0, 8.0, clampf((t - 10.0) / 1.5, 0.0, 1.0))
		if t >= 5.3 and not events.has("snap_1"):
			mark("snap_1", t)
			m.actor.play_once("attack", 1.4)
		if t < 10.0:
			m.bite_cd = 99.0
		elif not events.has("hunt"):
			mark("hunt", t)
			m.bite_cd = 0.0
	if car.state == "tumble" and not events.has("flip"):
		mark("flip", t)
		slow(t, 3.0, 0.3)
		lock_orbit()
	if events.has("flip"):
		# he is in there, and stays there
		g.pl.hidden = true
		g.pl.compromised = false
		m.awareness = 0.0
		m.bite_cd = 99.0
	if events.has("flip") and car.state != "tumble" and not events.has("land"):
		mark("land", t)
		# it walks up to the wreck
		var mp := Vector2(m.pos.x, m.pos.z)
		var cp: Vector2 = car.pos
		var to := (cp - mp).normalized() if cp.distance_to(mp) > 0.1 else Vector2(0, 1)
		rpath = [mp, cp - to * 7.0]
		rs = 0.0
		rdir = 1.0
		walk = true
	if events.has("land") and not events.has("roar"):
		var at_wreck := rs >= poly_len(rpath) - 0.3
		rspeed = 0.0 if at_wreck else 3.0
		if not at_wreck:
			m.state = "PATROL"
			m.pause_t = 0.0
		else:
			mark("sniff", t)
			face_to = car.pos
			m.state = "INVESTIGATE"
			m.phase2 = 1
			m.pause_t = 9.0
			m.lure_t = 9.0
			if t > events.sniff + 2.4:
				m.state = "PATROL"
				m.lure_t = 0.0
				m.roar_t = 1.6
				mark("roar", t)
				end_after(t, 2.8)
		if t > events.land + 7.0:
			m.roar_t = 1.6
			mark("roar", t)
			end_after(t, 2.8)
	if t > 26.0 and not events.has("flip"):
		end_after(t, 0.5)   # it never got the second bite in: cut it short rather than drag on

## Its jaws snap shut just short of the boot three times; the last in slow motion. Then he floors it, it
## falls back and roars.
func step_nearmiss(t: float, dt: float) -> void:
	drive(t, dt)
	keep_chasing()
	g.mon.bite_cd = 99.0
	var base := 13.0
	if t > 12.2:
		cruise = 22.0
		base = 13.0 + (t - 12.2) * 6.0
		if not events.has("roar") and t > 13.0:
			g.mon.roar_t = 1.6
			mark("roar", t)
		end_after(t, 4.4)
	var dip := 0.0
	for i in LUNGES.size():
		var L: float = LUNGES[i]
		dip = maxf(dip, 1.0 - clampf(absf(t - L) / 1.1, 0.0, 1.0))
		if t >= L - 0.25 and not events.has("snap_%d" % (i + 1)):
			mark("snap_%d" % (i + 1), t)
			g.mon.actor.play_once("attack", 1.4)
			if i == LUNGES.size() - 1:
				slow(t, 1.8, 0.35)
	gap = base - 5.2 * smoothstep(0.0, 1.0, dip)

# ---------------------------------------------------------------- ram
## The creature stands at the far end of the street, roars and charges; he floors it straight at it.
func setup_ram(p: Vector2) -> void:
	pick_car(p)
	get_in()
	fx.rig_wheels(car)
	cruise = 21.0
	rpath = [car.pos] + wp.duplicate()
	var L := poly_len(rpath)
	if L < 60.0:
		# a longer street: try the route from the far end too
		plan_route(car.pos)
		rpath = [car.pos] + wp.duplicate()
		L = poly_len(rpath)
	rs = clampf(L - 4.0, 30.0, 90.0)
	rdir = -1.0
	rspeed = 0.0
	walk = true
	var at := poly_at(rpath, rs)
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.start_chase()
	g.mon.bite_cd = 99.0

func step_ram(t: float, dt: float) -> void:
	var m := g.mon
	if not events.has("ram"):
		drive(t, dt)
		keep_chasing()
		m.bite_cd = 99.0
		if t > 0.3 and not events.has("roar"):
			m.roar_t = 1.2
			mark("roar", t)
		rspeed = 0.0 if t < 1.4 else minf(8.5, (t - 1.4) * 6.0)
		var d: float = (car.pos as Vector2).distance_to(Vector2(m.pos.x, m.pos.z))
		if slow_n == 0 and d < 3.4 + (absf(car.speed) + rspeed) * 0.4:
			slow(t, 2.6, 0.25)
			lock_impact()
		if m.state == "STUN":
			mark("ram", t)
			walk = false
			away = Vector2(m.pos.x, m.pos.z)
			plan_route(car.pos)
			hold_until = t + 3.0
			rev_t = 1.0
			cruise = 16.0
			end_after(t, 6.5)
		if t > 16.0:
			mark("miss", t)
			end_after(t, 0.5)
	else:
		drive(t, dt)

# ---------------------------------------------------------------- domino
## A straight street with nothing much in it: five or six parked cars are set out along it, staggered either
## side of the line the creature will charge down.
func setup_domino() -> void:
	var cands := []
	for need in [55.0, 45.0, 35.0]:
		for i in g.nodes.size():
			var a := Vector2(g.nodes[i].x, g.nodes[i].z)
			for j in g.nodes[i].n:
				if int(j) < i:
					continue
				var b := Vector2(g.nodes[j].x, g.nodes[j].z)
				var L := a.distance_to(b)
				if L < need:
					continue
				var u := (b - a) / L
				var bad := 0
				for k in range(0, int(L), 4):
					var q := a + u * k
					if not g.col.walkable(q.x, q.y, 2.0):
						bad += 1
				if bad <= 2:
					cands.append([a, b])
		if cands.size():
			break
	var a: Vector2
	var b: Vector2
	if cands.size():
		var pick: Array = cands[randi() % cands.size()]
		a = pick[0]
		b = pick[1]
	else:
		a = Vector2(g.nodes[0].x, g.nodes[0].z)
		b = Vector2(g.nodes[g.nodes[0].n[0]].x, g.nodes[g.nodes[0].n[0]].z)
	if randf() < 0.5:
		var s := a
		a = b
		b = s
	var L := a.distance_to(b)
	var u := (b - a) / L
	var n := Vector2(-u.y, u.x)
	var start := a - u * 10.0 if g.col.walkable((a - u * 10.0).x, (a - u * 10.0).y, 2.0) else a
	rpath = [start, b + u * 4.0]
	# the cars: the nearest parked ones, moved into the street
	var free: Array = g.veh.cars.filter(func(c): return c.state == "parked")
	var mid := a.lerp(b, 0.5)
	free.sort_custom(func(x, y): return (x.pos as Vector2).distance_to(mid) < (y.pos as Vector2).distance_to(mid))
	var count := clampi(int((L - 8.0) / 5.0), 4, 7)
	for k in count:
		if k >= free.size():
			break
		var c: Dictionary = free[k]
		var along := 10.0 + k * (L - 10.0) / maxf(count - 1, 1)
		var side := (1.0 if k % 2 == 0 else -1.0) * randf_range(0.6, 1.4)
		var p := a + u * along + n * side
		c.pos = p
		c.yaw = -u.angle() + randf_range(-0.35, 0.35) + (PI if randf() < 0.5 else 0.0)
		g.veh._apply(c)
		g.veh._place_box(c)
		g.world.move_car_halos(c.i, g.veh.xform(c), false)
		lined.append(c)
	# him: well out of the way
	var far := 0
	var fd := 0.0
	for i in g.nodes.size():
		var d := Vector2(g.nodes[i].x, g.nodes[i].z).distance_to(mid)
		if d > fd:
			fd = d
			far = i
	g.pl.pos = Vector3(g.nodes[far].x, 0.0, g.nodes[far].z)
	g.pl.actor.position = g.pl.pos
	rs = 0.0
	rdir = 1.0
	rspeed = 0.0
	walk = true
	var at := poly_at(rpath, 0.0)
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.yaw = atan2(u.x, u.y)
	g.mon.set_state("CHASE")

func step_domino(t: float) -> void:
	var m := g.mon
	m.awareness = 1.0
	m.last_seen_t = g.time
	m.bite_cd = 99.0
	if m.state != "CHASE":
		m.set_state("CHASE")
	if t > 0.2 and not events.has("roar"):
		m.roar_t = 1.0
		mark("roar", t)
	var L := poly_len(rpath)
	if rs < L - 2.0:
		rspeed = 0.0 if t < 1.2 else minf(9.5, (t - 1.2) * 7.0)
	else:
		rspeed = 0.0
		if not events.has("roar_end"):
			m.roar_t = 1.4
			mark("roar_end", t)
			end_after(t, 2.6)
	# throw whatever is in front of it (the game's own charge does this too, along its own heading)
	var p := poly_at(rpath, rs)
	var fw := poly_dir(rpath, rs)
	if rspeed > 3.0:
		var front := p + fw * 2.0
		for c in g.veh.cars_hit(front, Monster.BODY_R + 1.0):
			var dir: Vector2 = (((c.pos as Vector2) - p).normalized() + fw * 1.2).normalized()
			g.veh.knock(c, dir, randf_range(0.75, 1.0))
	for c in g.veh.cars:
		if c.state == "tumble" and not c.has("_tossed"):
			c["_tossed"] = true
			tossed += 1
			mark("toss_%d" % tossed, t)
			var thrown: Vector2 = ((c.pos as Vector2) - p).normalized()
			fx.burst("toss", Vector3(c.pos.x, 1.0, c.pos.y), Vector3(thrown.x, 1.0, thrown.y))
			if tossed == 1:
				slow(t, 1.3, 0.4)
			elif tossed == lined.size() - 1 and slow_n < 2:
				slow(t, 2.0, 0.3)
	if t > 26.0:
		end_after(t, 0.5)

# ---------------------------------------------------------------- freeze
## He crouches at a hiding place by the street; it comes walking along the street, stops a few metres off to
## sniff and look about, then walks on.
func setup_freeze() -> void:
	var opts := []
	for h in g.hides:
		var a := g.nearest_node(h.x, h.y, true)
		if Vector2(g.nodes[a].x, g.nodes[a].z).distance_to(h) < 14.0:
			opts.append(h)
	hide = opts[randi() % opts.size()] if opts.size() else g.hides[0]
	g.pl.pos = Vector3(hide.x, g.world.ground_at(hide.x, hide.y, 0.0), hide.y)
	g.pl.actor.position = g.pl.pos
	g._hide()
	var a := g.nearest_node(hide.x, hide.y, true)
	# from a street node 28-48 m off on one side to one on the other
	var ring := []
	for i in g.nodes.size():
		var d := Vector2(g.nodes[i].x, g.nodes[i].z).distance_to(hide)
		if d > 28.0 and d < 48.0:
			ring.append(i)
	var p0 := a
	var p1 := a
	var best := 2.0
	for i in ring:
		for j in ring:
			var di := (Vector2(g.nodes[i].x, g.nodes[i].z) - hide).normalized()
			var dj := (Vector2(g.nodes[j].x, g.nodes[j].z) - hide).normalized()
			var c := di.dot(dj) + randf() * 0.2
			if c < best:
				best = c
				p0 = i
				p1 = j
	rpath = []
	for i in g.bfs(p0, a):
		rpath.append(Vector2(g.nodes[i].x, g.nodes[i].z))
	var second := g.bfs(a, p1)
	for k in range(1, second.size()):
		rpath.append(Vector2(g.nodes[second[k]].x, g.nodes[second[k]].z))
	if rpath.size() < 2:
		rpath = [hide + Vector2(30, 6), hide + Vector2(-30, 6)]
	# where it stops: short of the nearest point, at least 5.5 m from him
	stop_s = poly_closest(rpath, hide)
	while stop_s > 0.0 and poly_at(rpath, stop_s).distance_to(hide) < 5.5:
		stop_s -= 0.5
	# it starts close enough to be there in seconds, not a long walk away
	rs = maxf(stop_s - 18.0, 0.0)
	rdir = 1.0
	rspeed = 0.0
	walk = true
	var at := poly_at(rpath, rs)
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.state = "PATROL"

func step_freeze(t: float) -> void:
	var m := g.mon
	m.awareness = 0.0
	var d := Vector2(m.pos.x, m.pos.z).distance_to(hide)
	if pause_until < 0.0:
		m.state = "PATROL"
		m.pause_t = 0.0
		rspeed = 3.0
		face_to = Vector2(INF, INF)
		if d < 16.0:
			mark("heart_on", t)
		if rs >= stop_s:
			pause_until = t + 5.5
			mark("sniff", t)
			slow(t, 1.6, 0.5)
	elif t < pause_until:
		rspeed = 0.0
		m.state = "INVESTIGATE"
		m.phase2 = 1
		m.pause_t = 9.0
		m.lure_t = 9.0
		face_to = hide
	else:
		face_to = Vector2(INF, INF)
		m.state = "PATROL"
		m.pause_t = 0.0
		m.lure_t = 0.0
		rspeed = 3.2
		if d > 18.0:
			mark("heart_off", t)
		if d > 26.0 or rs >= poly_len(rpath) - 0.5:
			end_after(t, 1.5)

# ---------------------------------------------------------------- the camera
## Which camera at time t.
func cut(t: float) -> String:
	match recipe:
		"ram":
			if slow_until >= 0.0 and not lock.is_empty():
				return "locked"
			if events.has("ram"):
				return "rex_face" if t - events.ram < 2.4 else "dash_back"
			if t < 1.6:
				return "rex_face"
			if t < 2.8:
				return "front_low"
			return "hood"
		"domino":
			if slow_until >= 0.0:
				return "dom_side"
			if t < 1.4:
				return "dom_front"
			if events.has("roar_end"):
				return "dom_front"
			return ["dom_side", "dom_front", "dom_high"][int((t - 1.4) / 2.0) % 3]
		"freeze":
			if t < 2.2:
				return "feet"
			if pause_until >= 0.0 and t < pause_until:
				return ["hide_pov", "rex_close", "hide_pov", "wide"][int((t - (pause_until - 5.5)) / 1.5) % 4]
			if pause_until < 0.0:
				return "hide_pov" if t < 7.0 else ["wide", "hide_pov"][int(t / 2.5) % 2]
			return "hide_pov"
		"nearmiss":
			if not g.pl.driving:
				return "game"
			if slow_until >= 0.0:
				return "side_low"
			if t > 12.2:
				return "dash_back"
			for L in LUNGES:
				if absf(t - L) < 0.8:
					return "dash_back" if L == LUNGES[0] else "side_low"
			return ["front_low", "rex_pov", "front_low", "dash_back"][int(t / 1.6) % 4]
		_:
			if events.has("flip") and slow_until >= 0.0 and not lock.is_empty():
				return "locked"
			if events.has("roar"):
				return "rex_face"
			if events.has("land"):
				return "wreck"
			if car != null and (car.state == "tumble" or not g.pl.driving):
				return "game"
			if bites > 0:
				return "side_low"
			return ["dash_back", "front_low", "side_low", "rex_pov"][int(t / 1.7) % 4]
	return "game"

## A camera position pulled in short of a wall between from and want.
func pulled(from: Vector3, want: Vector3) -> Vector3:
	var k: float = g.col.ray3(from, want, 0.25)
	return from.lerp(want, clampf(k * 0.92, 0.1, 1.0))

func lock_orbit() -> void:
	var cp := Vector3(car.pos.x, car.y, car.pos.y)
	var m := g.mon
	var side := atan2(cp.z - m.pos.z, cp.x - m.pos.x) + PI * 0.5
	lock = {c = cp, a = side, t0 = now()}

func lock_impact() -> void:
	var m := g.mon
	var cp := Vector3(car.pos.x, 0.0, car.pos.y)
	var mid := cp.lerp(m.pos, 0.6)
	var fv: Vector2 = g.veh.forward(car)
	var perp := Vector3(-fv.y, 0.0, fv.x)
	var p := pulled(mid + Vector3(0, 1.0, 0), mid + perp * 10.0 + Vector3(0, 1.1, 0))
	lock = {p = p, look = mid + Vector3(0, 1.6, 0), t0 = now()}

func camera(t: float, _dt: float) -> void:
	var mode := cut(t)
	if mode == "game":
		return   # the game's own chase camera behind the car
	var m: Monster = g.mon
	var fwd := Vector3(sin(m.yaw), 0.0, cos(m.yaw))
	var right := Vector3(-cos(m.yaw), 0.0, sin(m.yaw))
	var rhead := m.pos + fwd * 3.4 + Vector3(0, 3.0, 0)
	var shake := minf(1.0, g.tremor * 0.8 + 0.15)
	var jit := Vector3(sin(t * 23.0), sin(t * 31.0 + 1.0), sin(t * 17.0)) * 0.03 * shake
	var pos := Vector3()
	var look := Vector3()
	var fov := 66.0
	var on_car: bool = car != null and g.pl.driving and car.state == "driven"
	var cpos := Vector3()
	var cf := Vector3(0, 0, 1)
	var cr := Vector3(1, 0, 0)
	var hl := 2.3
	var hw := 1.0
	if car != null:
		var fv: Vector2 = g.veh.forward(car)
		cf = Vector3(fv.x, 0.0, fv.y)
		cr = Vector3(-fv.y, 0.0, fv.x)
		cpos = Vector3(car.pos.x, car.y, car.pos.y)
		hl = car.size.x * 0.5
		hw = car.size.z * 0.5
	var wob := jit * (1.0 + (absf(car.speed) * 0.2 if on_car else 0.0))
	match mode:
		"front_low":
			# ahead of the bonnet, low, looking back along the car: the creature fills the street behind it
			pos = pulled(cpos + cf * (hl + 0.4) + Vector3(0, 1.0, 0), cpos + cf * (hl + 6.0) + cr * 1.3 * sin(t * 0.8) + Vector3(0, 0.9, 0)) + wob
			look = cpos.lerp(rhead, 0.45) + Vector3(0, 0.5, 0)
			fov = 64.0
		"dash_back":
			# just behind and above the boot, outside the car, looking back at it
			pos = cpos - cf * (hl + 1.3) + cr * 0.6 + Vector3(0, 1.9, 0) + wob
			look = rhead
			fov = 70.0
		"side_low":
			pos = pulled(cpos + cr * (hw + 0.4) + Vector3(0, 0.8, 0), cpos + cr * (hw + 5.5) - cf * 2.0 + Vector3(0, 0.7, 0)) + wob
			look = cpos.lerp(rhead, 0.4) + Vector3(0, 1.0, 0)
			fov = 62.0
		"rex_pov":
			pos = m.pos - fwd * 2.5 + right * 2.2 + Vector3(0, 4.8, 0) + wob
			look = cpos + Vector3(0, 1.0, 0)
			fov = 58.0
		"hood":
			# on the bonnet looking ahead: it charges at the lens
			pos = cpos + cf * (hl + 0.2) + Vector3(0, 1.3, 0) + wob
			look = rhead - Vector3(0, 0.6, 0)
			fov = 60.0
		"rex_face":
			pos = pulled(rhead, rhead + fwd * 9.0 + right * 1.5 * sin(t * 0.5) + Vector3(0, -1.9, 0)) + jit
			look = rhead + Vector3(0, 0.2, 0)
			fov = 56.0
		"locked":
			if lock.has("p"):
				pos = lock.p
				look = lock.look
			else:
				var a: float = lock.a + (t - lock.t0) * 0.35
				var c: Vector3 = lock.c
				pos = pulled(c + Vector3(0, 1.5, 0), c + Vector3(cos(a), 0.0, sin(a)) * 9.0 + Vector3(0, 2.2, 0))
				look = cpos + Vector3(0, 1.2, 0)
			fov = 62.0
		"wreck":
			# side on to the creature and the wreck it is walking up to
			var dd := Vector3(m.pos.x - cpos.x, 0.0, m.pos.z - cpos.z).normalized()
			var mid4 := cpos.lerp(Vector3(m.pos.x, cpos.y, m.pos.z), 0.45)
			pos = pulled(mid4 + Vector3(0, 1.2, 0), mid4 + Vector3(-dd.z, 0.0, dd.x) * 10.0 + Vector3(0, 1.3, 0)) + jit
			look = mid4 + Vector3(0, 1.4, 0)
			fov = 62.0
		"dom_front":
			var ahead := poly_at(rpath, rs + 20.0)
			var fw2 := poly_dir(rpath, rs)
			var n2 := Vector3(-fw2.y, 0.0, fw2.x)
			var base := Vector3(ahead.x, 0.0, ahead.y)
			pos = pulled(base + Vector3(0, 1.0, 0), base + n2 * 4.0 + Vector3(0, 0.8, 0)) + jit
			look = m.pos + Vector3(0, 2.4, 0)
			fov = 60.0
		"dom_side":
			var fw3 := poly_dir(rpath, rs)
			var n3 := Vector3(-fw3.y, 0.0, fw3.x)
			var p3 := poly_at(rpath, rs + 3.0)
			var base3 := Vector3(p3.x, 0.0, p3.y)
			pos = pulled(base3 + Vector3(0, 1.4, 0), base3 - n3 * 12.0 + Vector3(0, 1.4, 0)) + jit
			look = base3 + Vector3(0, 1.8, 0)
			fov = 64.0
		"dom_high":
			pos = m.pos - fwd * 6.0 + right * 2.0 + Vector3(0, 6.5, 0) + jit
			look = m.pos + fwd * 14.0 + Vector3(0, 1.0, 0)
			fov = 62.0
		"feet":
			pos = pulled(m.pos + Vector3(0, 0.4, 0), m.pos + right * 4.5 + fwd * 3.0 + Vector3(0, 0.35, 0)) + jit
			look = m.pos + Vector3(0, 1.2, 0)
			fov = 60.0
		"hide_pov":
			var hp := Vector3(hide.x, g.pl.pos.y, hide.y)
			var to := (Vector3(m.pos.x, hp.y, m.pos.z) - hp).normalized()
			var side := Vector3(-to.z, 0.0, to.x)
			pos = pulled(hp + Vector3(0, 0.9, 0), hp - to * 1.6 + side * 0.5 + Vector3(0, 1.05, 0)) + jit * 0.5
			look = rhead.lerp(hp + Vector3(0, 0.8, 0), 0.15)
			fov = 60.0
		"rex_close":
			pos = pulled(rhead, rhead + right * 3.8 + fwd * 1.6 + Vector3(0, -0.4, 0)) + jit * 0.5
			look = rhead
			fov = 56.0
		"wide":
			var hp2 := Vector3(hide.x, 0.0, hide.y)
			var mid := hp2.lerp(m.pos, 0.5)
			var dd := (m.pos - hp2).normalized()
			var side2 := Vector3(-dd.z, 0.0, dd.x)
			pos = pulled(mid + Vector3(0, 2.0, 0), mid + side2 * 13.0 + Vector3(0, 2.4, 0)) + jit * 0.5
			look = mid + Vector3(0, 1.6, 0)
			fov = 62.0
		_:
			return
	# never inside the creature, never under the street
	pos = g.pl._out_of_rex(pos, (look - pos).normalized())
	pos.y = maxf(pos.y, g.world.ground_at(pos.x, pos.z, 0.0) + 0.25)
	if pos.distance_to(look) < 0.5:
		return
	var c: Camera3D = g.cam
	c.position = pos
	c.fov = fov
	c.look_at(look)
