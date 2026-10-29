## Shorts director: plays one scripted, satisfying action moment for a vertical Short (1080x1920), on a bright,
## dry day, with a steady hero camera that cuts on the beats, slow motion and no HUD. Recorded with Godot's movie
## maker on a GitHub server (see tools/shorts and .github/workflows/shorts-video.yml):
##   godot --path godot --resolution 1080x1920 --fixed-fps 120 --write-movie out/clip.avi -s res://tests/short.gd -- --mode=flip --seed=3 --fps=120
## --mode=flip      the T-Rex runs the car down, bites the boot, then lifts it in its jaws and throws it over
## --mode=nearmiss  its jaws snap shut just short of the boot three times; the car pulls away and it roars
## --mode=ram       the T-Rex charges down the street; he floors it straight into it, then backs off fast
## --mode=hunter    he goes after the T-Rex: rams it, backs off, rams it again, and it goes down
## --mode=domino    the T-Rex charges down a street of parked cars, throwing them aside one after another
## --mode=freeze    he hides beside a car while it walks up, sniffs about a few metres off and walks on
## --seed=N         where in the city it happens (and the small random choices)
## --fps=N          frames recorded a second (the same as Godot's --fixed-fps); compose.py blends them into motion blur
## Do not call a flag --shot, --frames, --day, --play, --loc or --stats: the game itself reads those (--shot=x quits it after 60 frames).
## It prints "PREROLL s" (video before the shot starts, cut off later), a trace line every half second, and
## "EVENT name seconds" for what happened when: tools/shorts/compose.py lays the sound and captions on those.
## Event times are seconds of video from the start of the shot; they run on while the game is slowed down.
##
## The car he drives does not steer itself through traffic: it follows a smoothed line along the streets, cleared
## of parked cars, at a speed each bend allows, so it never clips anything. Contact with the T-Rex is staged too:
## its jaws close on the boot before the car moves, and nobody is ever killed on screen.
extends SceneTree

const FX := preload("res://tests/short_fx.gd")
const MAX_LEN := 34.0
const LUNGES := [3.4, 7.0, 10.6]   # nearmiss: when its jaws snap shut, short of the boot
const BITES := [10.5, 13.6]        # flip: when its jaws close on the boot (the second lifts the car)
const SNAP := 5.5                  # flip: a first snap, short
const A_LAT := 6.5                 # how hard the car may corner (m/s2)
const JAW_REACH := 4.2             # the creature's jaws, ahead of its centre (Monster.head)

var g: Game
var fx: FX
var recipe := "flip"
var seed_n := 1
var fps := 30.0
var f := 0
var started := -1
var done_at := -1.0
var events := {}         # name -> second it first happened
var trace: Array = []
var trace_at := 0.0
var rig: Node
var unpaused := 0
var bites := 0
var anims := {}          # attack clips already started, by name

# the car he drives, on its lane
var car: Variant = null
var last_hp := 0
var wp: Array = []
var away := Vector2(INF, INF)
var lane: Array = []     # Vector2 every metre along the smoothed route
var lane_v: Array = []   # the fastest each metre can be taken (bends, braking for them)
var ls := 0.0            # how far along the lane the car is
var lv := 0.0            # its speed along it (negative: backing up)
var want_v := 13.0       # the speed the shot asks for
var lane_off := 0.0      # sideways off the line (a shove), springing back
var off_v := 0.0
var yaw_off := 0.0
var car_free := true     # false while it is in the creature's jaws, or thrown
var carry_t := -1.0
var track: Array[Vector2] = []   # where the car has been, oldest first
var follow := false              # the creature runs `gap` behind the car along its track
var gap := 13.0

# the creature on a path of its own
var walk := false
var rpath: Array = []
var rs := 0.0
var rdir := 1.0
var rspeed := 0.0
var face_to := Vector2(INF, INF)
# ... or on the car's lane, facing it (ram, hunter)
var rex_lane := false
var rex_s := 0.0
var rex_v := 0.0
var hits := 0
var hunt := "approach"
var hunt_t := 0.0
var downed := false

# domino and freeze
var lined: Array = []
var tossed := 0
var hide := Vector2()
var stop_s := 0.0
var pause_until := -1.0

# slow motion and the camera
var slow_n := 0
var slow_until := -1.0
var lock := {}
var cam_p := Vector3()
var cam_l := Vector3()
var last_mode := ""
var hero_until := -1.0

## Runs after the game's own _process (higher priority number = later): puts the car and the creature where the
## shot wants them and takes the camera over.
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
	g.hud.visible = false
	if started < 0:
		if g.phase == "menu" and f > 10:
			# everything recorded before this frame (the start screen) is cut off by compose.py
			print("PREROLL %.4f" % ((f - 1) / fps))
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
		if recipe == "flip":
			bites += 1
			mark("bite_%d" % bites, t)
	match recipe:
		"ram":
			step_hunt(t, dt, 1)
		"hunter":
			step_hunt(t, dt, 2)
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
	if g.phase == "caught" or g.phase == "lost":
		# never shown: compose.py cuts to black on it
		mark("caught", t)
		end_after(t, 0.4)
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
	place_car(dt)
	place_rex()
	if recipe == "domino" or (recipe == "flip" and not car_free):
		g.pl.actor.visible = false
	if downed:
		# it stays down: the death clip held on its last frame
		var a: Rex = g.mon.actor
		a.once = "death"
		if a.anim.current_animation != a.clip_names.get("death", ""):
			a.anim.play(a.clip_names.death)
			a.anim.seek(a.anim.current_animation_length, true)
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
		fx.burst("impact", cpos + Vector3(0, 0.6, 0), Vector3.UP)
	elif what == "land":
		fx.burst("land", Vector3(cpos.x, 0.0, cpos.z), Vector3.UP)
	elif what.begins_with("ram"):
		var hit := (cpos + cf * hl).lerp(g.mon.pos, 0.3) + Vector3(0, 1.0, 0)
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

## Starts a one-shot clip on the creature once per name (an attack whose jaws close `lead` seconds later).
func strike(name: String, clip: String, speed: float) -> void:
	if anims.has(name):
		return
	anims[name] = true
	g.mon.actor.play_once(clip, speed)

func log_trace(t: float) -> void:
	var d := Vector2(g.mon.pos.x - g.pl.pos.x, g.mon.pos.z - g.pl.pos.z).length()
	var sp: float = absf(car.speed) if car != null and g.pl.driving else g.pl.real_sp
	var line := "t=%4.1f phase=%s rex=%s dist=%.0fm speed=%.1f cam=%s scale=%.2f%s" % [t, g.phase, g.mon.state, d, sp, last_mode,
		Engine.time_scale, (" car=%s hp=%d lane=%.0f/%d" % [car.state, car.hp, ls, lane.size()]) if car != null else ""]
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
		"ram", "hunter":
			setup_hunt(p)
		"domino":
			setup_domino()
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

## Streets to drive: a seeded random node 70 to 150 m off, along the street graph, preferring ones well away
## from `away` (so the next leg does not turn back).
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

# ---------------------------------------------------------------- the lane
## The line the car drives: legs of the street graph chained to 650 m, corners rounded, parked cars moved off it,
## nudged round whatever else stands in it, smoothed, and a speed for every metre that the bends allow.
func build_lane(from: Vector2, dir: Vector2) -> void:
	var pts: Array = [from]
	away = from - dir * 40.0
	for leg in 8:
		plan_route(pts[-1])
		for q in wp:
			if (q as Vector2).distance_to(pts[-1]) > 2.0:
				pts.append(q)
		if leg == 0:
			# the street node nearest the car may be behind it: start forwards
			while pts.size() > 2 and ((pts[1] as Vector2) - from).dot(dir) < 0.0:
				pts.remove_at(1)
		if poly_len(pts) > 650.0:
			break
		away = poly_at(pts, poly_len(pts) - 40.0)
	away = Vector2(INF, INF)
	var raw := _resample(_round_corners(pts), 1.0)
	clear_lane(raw)
	# round anything still in the way (a bus, rubble): the nearest clear spot across the street, then smoothed
	var off := []
	for i in raw.size():
		var p: Vector2 = raw[i]
		var n := _normal(raw, i)
		var o := 0.0
		if not g.col.walkable(p.x, p.y, 1.3):
			for k in [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0]:
				if g.col.walkable(p.x + n.x * k, p.y + n.y * k, 1.3):
					o = k
					break
		off.append(o)
	lane = []
	for i in raw.size():
		var s := 0.0
		var w := 0.0
		for j in range(maxi(i - 8, 0), mini(i + 9, raw.size())):
			var k := 1.0 - absf(j - i) / 9.0
			s += float(off[j]) * k
			w += k
		lane.append((raw[i] as Vector2) + _normal(raw, i) * (s / w))
	# speeds: what each bend allows, then braking for the bends ahead
	lane_v = []
	for i in lane.size():
		var a := _heading(i - 3)
		var b := _heading(i + 3)
		var bend := absf(U.ang_diff(a, b)) / 6.0
		lane_v.append(minf(26.0, sqrt(A_LAT / maxf(bend, 0.0001))))
	for i in range(lane.size() - 2, -1, -1):
		lane_v[i] = minf(lane_v[i], sqrt(lane_v[i + 1] * lane_v[i + 1] + 2.0 * 7.0))
	ls = 0.0

func _heading(i: int) -> float:
	var a: Vector2 = lane[clampi(i, 0, lane.size() - 2)]
	var b: Vector2 = lane[clampi(i, 0, lane.size() - 2) + 1]
	return (b - a).angle()

func _normal(pts: Array, i: int) -> Vector2:
	var a: Vector2 = pts[maxi(i - 1, 0)]
	var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)

## Each corner turned into a curve (a quadratic through the corner, up to 9 m either side of it).
func _round_corners(pts: Array) -> Array:
	if pts.size() < 3:
		return pts.duplicate()
	var out: Array = [pts[0]]
	for i in range(1, pts.size() - 1):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var d := minf(9.0, minf(a.distance_to(b), b.distance_to(c)) * 0.5)
		var p0 := b + (a - b).normalized() * d
		var p1 := b + (c - b).normalized() * d
		for k in 9:
			var u := k / 8.0
			out.append(p0.lerp(b, u).lerp(b.lerp(p1, u), u))
	out.append(pts[-1])
	return out

func _resample(pts: Array, step: float) -> Array:
	var out: Array = []
	var L := poly_len(pts)
	var s := 0.0
	var i := 1
	var acc := 0.0
	while s <= L and pts.size() > 1:
		while i < pts.size() - 1 and acc + (pts[i] as Vector2).distance_to(pts[i - 1]) < s:
			acc += (pts[i] as Vector2).distance_to(pts[i - 1])
			i += 1
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		out.append(a.lerp(b, clampf((s - acc) / seg, 0.0, 1.0)) if seg > 0.0 else a)
		s += step
	return out

## Parked cars and wrecks within reach of the line: moved to the kerb side, or if there is no room, out of
## the city (an evacuated street).
func clear_lane(pts: Array) -> void:
	for c in g.veh.cars:
		if c.i == car.i or (c.state != "parked" and c.state != "wreck"):
			continue
		var q: Vector2 = c.pos
		var bi := -1
		var bd := INF
		for i in range(0, pts.size(), 2):
			var d := q.distance_to(pts[i])
			if d < bd:
				bd = d
				bi = i
		if bd > 3.8:
			continue
		var n := _normal(pts, bi)
		var side := 1.0 if (q - (pts[bi] as Vector2)).dot(n) >= 0.0 else -1.0
		var to: Vector2 = (pts[bi] as Vector2) + n * side * 4.6
		if c.box >= 0:
			g.col.disable_box(c.box)
		if g.col.walkable(to.x, to.y, 1.1):
			c.pos = to
			g.veh._apply(c)
			g.veh._place_box(c)
			g.world.move_car_halos(c.i, g.veh.xform(c), c.state == "wreck")
		else:
			c.pos = Vector2(g.bound + 60.0, g.bound + 60.0)
			c.state = "gone"
			(c.node as Node3D).visible = false
			g.veh._apply(c)
			g.world.move_car_halos(c.i, g.veh.xform(c), true)
			if c.smoke:
				(c.smoke as Node3D).visible = false

func lane_at(s: float) -> Vector2:
	var i := clampi(int(floor(s)), 0, lane.size() - 2)
	return (lane[i] as Vector2).lerp(lane[i + 1], clampf(s - i, 0.0, 1.0))

func lane_dir(s: float) -> Vector2:
	var d := lane_at(s + 1.5) - lane_at(s - 1.5)
	return d.normalized() if d.length() > 0.001 else Vector2(1, 0)

## One frame of driving, before the game's update: the speed along the lane, eased to `want_v` and held under
## what the bends ahead allow. The game drives nothing itself (no input); place_car() puts the car on the line.
func drive(dt: float) -> void:
	var inp: Dictionary = g.hud.input
	inp.jx = 0.0
	inp.jy = 0.0
	inp.sprint = false
	if car == null or not car_free or lane.size() < 3:
		return
	var top := want_v
	if want_v > 0.0:
		top = minf(want_v, float(lane_v[clampi(int(ls) + 1, 0, lane_v.size() - 1)]))
	if ls >= lane.size() - 3.0:
		top = 0.0
	lv = move_toward(lv, top, (5.0 if absf(top) > absf(lv) else 8.0) * dt)
	ls = clampf(ls + lv * dt, 0.0, lane.size() - 2.0)
	car.speed = lv

## After the game's update: the car on its line (or in the creature's jaws).
func place_car(dt: float) -> void:
	if car == null or car.state != "driven" or lane.size() < 3:
		return
	if not car_free:
		if carry_t >= 0.0:
			carry(dt)
		return
	# a shove off the line springs back
	off_v += (-lane_off * 7.0 - off_v * 3.5) * dt
	lane_off += off_v * dt
	yaw_off = lerpf(yaw_off, 0.0, 1.0 - exp(-dt * 3.0))
	var d := lane_dir(ls)
	var n := Vector2(-d.y, d.x)
	var p := lane_at(ls) + n * lane_off
	car.pos = p
	car.yaw = -d.angle() + yaw_off
	car.y = g.world.ground_at(p.x, p.y, 0.0)
	car.speed = lv
	# the front wheels turn into the bend ahead
	car.steer = clampf(U.ang_diff(d.angle(), lane_dir(ls + 4.0).angle()) * 2.5, -1.0, 1.0)
	g.veh._apply(car)

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

## Puts him in the car and lays its lane from where it stands, with the game's chase camera already pulled back
## behind it (left to itself it starts close, inside the car).
func get_in() -> Vector2:
	var cp: Vector2 = car.pos
	g.pl.pos = Vector3(cp.x, g.world.ground_at(cp.x, cp.y, 0.0), cp.y)
	g.enter_car(car)
	var dir := Vector2.from_angle(-car.yaw)
	plan_route(cp)
	if wp.size() > 1:
		dir = ((wp[1] if cp.distance_to(wp[0]) < 6.0 else wp[0]) - cp).normalized()
	build_lane(cp, dir)
	dir = lane_dir(2.0)
	car.yaw = -dir.angle()
	g.pl.cam_cur = 8.0
	g.pl.cam_yaw = atan2(dir.x, dir.y)
	for k in range(100, -1, -1):
		track.append(cp - dir * (k * 0.4))
	fx.rig_wheels(car)
	return dir

## Keeps the creature on his trail while he drives (it never bites by itself: the shot stages that).
func keep_chasing() -> void:
	var m := g.mon
	m.bite_cd = 99.0
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
## Where the shot wants the creature this frame, after the game has moved it.
func place_rex() -> void:
	var m := g.mon
	var p := Vector2()
	var h := Vector2()
	if rex_lane and lane.size() > 2:
		p = lane_at(rex_s)
		h = -lane_dir(rex_s)   # facing back along the lane, at the car
	elif follow and car != null and g.pl.driving and car.state == "driven" and car_free:
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

## How far behind the car (centre to centre) the creature's jaws close on the boot.
func jaw_gap() -> float:
	return float(car.size.x) * 0.5 + JAW_REACH - 0.6

# ---------------------------------------------------------------- flip and nearmiss: chased by car
func setup_chase(p: Vector2) -> void:
	pick_car(p)
	var dir := get_in()
	var cp: Vector2 = car.pos
	var at := cp - dir * gap
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	g.mon.yaw = atan2(dir.x, dir.y)
	g.mon.start_chase()
	follow = true
	want_v = 13.0

## Ten seconds of close chase (its jaws snap once, short of the boot). Then it closes in and its jaws close on
## the boot: the car is shoved off its line. It closes in again, takes the boot in its jaws, lifts the car and
## throws it over (slow motion in the air). It lands on its roof; the creature walks up, sniffs the wreck, roars.
## He stays inside, unseen: nobody climbs out of that.
func step_flip(t: float, dt: float) -> void:
	var m := g.mon
	if car_free:
		drive(dt)
		keep_chasing()
		var g0 := 13.0
		var dip := 1.0 - clampf(absf(t - SNAP) / 1.1, 0.0, 1.0)
		gap = g0 - (g0 - jaw_gap() - 1.4) * smoothstep(0.0, 1.0, dip)
		for b in BITES:
			var k := 0.0
			if t > b - 1.3 and t <= b + 0.2:
				k = smoothstep(b - 1.3, b - 0.1, t)
			elif t > b + 0.2:
				k = 1.0 - smoothstep(b + 0.2, b + 1.4, t)
			gap = minf(gap, lerpf(g0, jaw_gap(), k))
		# the jaws close about 0.35 s into the attack clip
		if t >= SNAP - 0.35:
			strike("snap", "attack", 1.3)
		if t >= SNAP:
			mark("snap_1", t)
		if t >= BITES[0] - 0.35:
			strike("bite1", "attack", 1.3)
		if t >= BITES[0] and bites == 0 and not anims.has("bit1"):
			anims["bit1"] = true
			var fv: Vector2 = g.veh.forward(car)
			g.car_bitten((fv + Vector2(-fv.y, fv.x) * 0.4).normalized())
			var side := 1.0 if randf() < 0.5 else -1.0
			off_v = side * 3.2
			yaw_off = side * 0.22
			lv *= 0.5
		if t >= BITES[1] - 0.35:
			strike("bite2", "attack", 1.3)
		if t >= BITES[1] and not anims.has("lift"):
			anims["lift"] = true
			# its jaws have the boot: from here the car goes where its head goes
			mark("lift", t)
			car_free = false
			carry_t = 0.0
			car.speed = 0.0
			follow = false
			var mp := Vector2(m.pos.x, m.pos.z)
			var fw := Vector2(sin(m.yaw), cos(m.yaw))
			rpath = [mp, mp + fw * 30.0]
			rs = 0.0
			rdir = 1.0
			rspeed = maxf(absf(lv) * 0.6, 3.0)
			walk = true
	if carry_t >= 0.0:
		rspeed = move_toward(rspeed, 1.5, 6.0 * dt)
	if car.state == "tumble" and not events.has("flip"):
		mark("flip", t)
		slow(t, 3.0, 0.3)
		lock_orbit()
		walk = false
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
		end_after(t, 0.5)   # something went wrong: cut it short rather than drag on

## The car held in the creature's jaws for a moment, lifted by the boot, then thrown (the game's own throw).
func carry(dt: float) -> void:
	var m := g.mon
	carry_t += dt
	var fw := Vector2(sin(m.yaw), cos(m.yaw))
	var head := Vector2(m.pos.x, m.pos.z) + fw * JAW_REACH
	var cf: Vector2 = g.veh.forward(car)
	var u := clampf(carry_t / 0.45, 0.0, 1.0)
	car.pos = head + cf * (float(car.size.x) * 0.5 - 0.6)
	car.y = g.world.ground_at(car.pos.x, car.pos.y, 0.0) + 1.5 * smoothstep(0.0, 1.0, u)
	car.roll = 0.15 * u
	car.speed = 0.0
	g.veh._apply(car)
	if u >= 1.0:
		carry_t = -1.0
		var side := Vector2(-fw.y, fw.x) * (1.0 if randf() < 0.5 else -1.0)
		g.car_bitten((fw * 0.6 + side).normalized())   # the second bite throws it over (Game.car_bitten)

## Its jaws snap shut just short of the boot three times; the last in slow motion. Then he floors it, it falls
## back and roars.
func step_nearmiss(t: float, dt: float) -> void:
	drive(dt)
	keep_chasing()
	var base := 13.0
	if t > 12.2:
		want_v = 22.0
		base = 13.0 + (t - 12.2) * 6.0
		if not events.has("roar") and t > 13.0:
			g.mon.roar_t = 1.6
			mark("roar", t)
		end_after(t, 4.4)
	var short := jaw_gap() + 0.9
	var dip := 0.0
	for i in LUNGES.size():
		var L: float = LUNGES[i]
		dip = maxf(dip, 1.0 - clampf(absf(t - L) / 1.1, 0.0, 1.0))
		if t >= L - 0.35:
			strike("snap_%d" % (i + 1), "attack", 1.3)
		if t >= L:
			mark("snap_%d" % (i + 1), t)
		if i == LUNGES.size() - 1 and t >= L - 0.5 and slow_n == 0:
			slow(t, 1.8, 0.35)
	gap = base - (base - short) * smoothstep(0.0, 1.0, dip)

# ---------------------------------------------------------------- ram and hunter
## The creature stands at the far end of the street, on the car's lane, facing it; it roars and charges.
func setup_hunt(p: Vector2) -> void:
	pick_car(p)
	get_in()
	want_v = 0.0
	var L := float(lane.size())
	rex_s = clampf(L - 10.0, 60.0, 140.0)
	rex_v = 0.0
	rex_lane = true
	var at := lane_at(rex_s)
	g.mon.pos = Vector3(at.x, 0.0, at.y)
	# standing, head scanning, until it charges
	g.mon.set_state("INVESTIGATE")
	g.mon.phase2 = 1
	g.mon.pause_t = 99.0
	g.mon.bite_cd = 99.0

## ram: one hit, then he backs off fast while it staggers and roars. hunter: he backs off and goes again, and
## the second hit puts it down.
func step_hunt(t: float, dt: float, need: int) -> void:
	var m := g.mon
	m.bite_cd = 99.0
	m.awareness = 0.0
	var hl: float = car.size.x * 0.5
	var contact := hl + 2.4
	var gc := rex_s - ls   # centre to centre along the street
	if t > 0.6 and not events.has("roar"):
		m.roar_t = 1.4
		mark("roar", t)
	match hunt:
		"approach":
			want_v = 0.0 if t < 1.0 else (24.0 if recipe == "hunter" else 21.0)
			if m.state == "STUN" or downed:
				rex_v = move_toward(rex_v, 0.0, 10.0 * dt)
			elif t > 1.8 and gc < 80.0:
				if m.state != "CHASE":
					m.set_state("CHASE")
				m.last_seen_t = g.time
				rex_v = move_toward(rex_v, -8.5, 6.0 * dt)
			if slow_n == hits and gc < contact + (lv - rex_v) * 0.45:
				slow(t, 2.4 if hits == 0 else 3.0, 0.25 if hits == 0 else 0.2)
				lock_impact()
			if gc <= contact:
				hit(t, need)
		"back":
			want_v = -6.0
			rex_v = move_toward(rex_v, 0.0, 10.0 * dt)
			if t > hunt_t + 2.0:
				hunt = "wait"
				hunt_t = t
		"wait":
			want_v = 0.0
			rex_v = move_toward(rex_v, 0.0, 10.0 * dt)
			if t > hunt_t + 0.6 and m.state != "STUN":
				hunt = "approach"
				m.roar_t = 1.2
				mark("roar_2", t)
		"flee":
			want_v = -9.0
			rex_v = move_toward(rex_v, 0.0, 10.0 * dt)
			if t > hunt_t + 2.2 and not events.has("roar_end"):
				m.roar_t = 1.6
				mark("roar_end", t)
		"done":
			want_v = 0.0
			rex_v = move_toward(rex_v, 0.0, 5.0 * dt)
	drive(dt)
	rex_s = clampf(rex_s + rex_v * dt, ls + contact - 0.2, lane.size() - 2.0)
	m.speed = absf(rex_v)
	if t > 30.0:
		end_after(t, 0.5)

func hit(t: float, need: int) -> void:
	var m := g.mon
	hits += 1
	mark("ram" if hits == 1 else "ram_%d" % hits, t)
	lv = -3.0
	rex_v = 7.0
	hunt_t = t
	if hits >= need and need >= 2:
		# down it goes
		hunt = "done"
		downed = true
		m.set_state("STUN")
		m.stun_t = 999.0
		m.actor.play_once("death", 0.9)
		mark("fall", t)
		end_after(t, 7.5)
	else:
		m.rammed(14.0)
		hunt = "flee" if need == 1 else "back"
		if need == 1:
			end_after(t, 5.5)

# ---------------------------------------------------------------- domino
## A straight street with nothing much in it: four to seven parked cars are set out along it, staggered either
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
## Which camera at time t. Each recipe has a hero shot that carries most of it (the car and the creature both in
## frame); it cuts away only on the beats, for two to three seconds.
func cut(t: float) -> String:
	var slowing := slow_until >= 0.0
	match recipe:
		"ram", "hunter":
			if events.has("fall"):
				if slowing and not lock.is_empty():
					return "locked"
				return "fall_side" if t < events.fall + 5.0 else "drone_up"
			if slowing and not lock.is_empty():
				return "locked"
			if hits > 0 and t - hunt_t < 2.2:
				return "rex_face"
			if hits > 0 and hunt == "flee":
				return "dash_back"
			if t < 1.8:
				return "rex_face"
			if recipe == "hunter" and t < 4.2 and hits == 0:
				return "drone"
			if rex_s - ls < 32.0 and hunt == "approach":
				return "hood"
			return "hero_back"
		"domino":
			if slowing:
				return "dom_side"
			if events.has("roar_end") or not events.has("toss_1"):
				return "dom_front"
			var since: float = t - events.toss_1
			return "dom_side" if since < 3.5 else ("dom_high" if since < 6.5 else "dom_front")
		"freeze":
			if t < 2.5:
				return "feet"
			if pause_until >= 0.0 and t < pause_until:
				var into := t - (pause_until - 5.5)
				return "rex_close" if into > 2.2 and into < 4.0 else "hide_pov"
			if pause_until >= 0.0 and t < pause_until + 3.0:
				return "wide"
			return "hide_pov"
		"nearmiss":
			if not g.pl.driving:
				return "game"
			if slowing:
				return "side_low"
			if t > 12.2:
				return "dash_back"
			if absf(t - LUNGES[0]) < 0.9:
				return "dash_back"
			if absf(t - LUNGES[1]) < 0.9 or absf(t - LUNGES[2]) < 0.9:
				return "side_low"
			return "hero"
		_:
			if events.has("roar"):
				return "rex_face"
			if events.has("land"):
				return "wreck"
			if events.has("flip"):
				return "locked" if slowing and not lock.is_empty() else "game"
			if not car_free:
				return "side_low"
			for b in BITES:
				if t > b - 1.0 and t < b + 1.4:
					return "side_low"
			if t >= 4.6 and t < 6.6:
				return "dash_back"
			if t >= 7.5 and t < 9.0:
				return "front_low"
			return "hero"
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
	var fv: Vector2 = g.veh.forward(car)
	var mid := cp + Vector3(fv.x, 0.0, fv.y) * (float(car.size.x) * 0.5 + 1.2)
	var perp := Vector3(-fv.y, 0.0, fv.x)
	var p := pulled(mid + Vector3(0, 1.0, 0), mid + perp * 9.0 + Vector3(0, 1.1, 0))
	lock = {p = p, look = mid.lerp(m.pos, 0.3) + Vector3(0, 1.6, 0), t0 = now()}

func camera(t: float, dt: float) -> void:
	var mode := cut(t)
	var hero := "hero_back" if recipe in ["ram", "hunter"] else "hero"
	if t < hero_until and mode in ["front_low", "dash_back", "side_low", "rex_pov", "hood"]:
		mode = hero
	if mode == "game":
		last_mode = mode
		return   # the game's own chase camera behind the car
	var m: Monster = g.mon
	var fwd := Vector3(sin(m.yaw), 0.0, cos(m.yaw))
	var right := Vector3(-cos(m.yaw), 0.0, sin(m.yaw))
	var rhead := m.pos + fwd * 3.4 + Vector3(0, 3.0, 0)
	var shake := minf(1.0, g.tremor * 0.8 + 0.15)
	var jit := Vector3(sin(t * 23.0), sin(t * 31.0 + 1.0), sin(t * 17.0)) * 0.03 * shake
	var pos := Vector3()
	var look := Vector3()
	var fov := 64.0
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
	match mode:
		"hero":
			# ahead and to one side, looking back along the car: it and the creature behind it both in frame
			pos = pulled(cpos + Vector3(0, 1.2, 0), cpos + cf * 7.0 + cr * 4.0 + Vector3(0, 1.8, 0))
			look = cpos.lerp(rhead, 0.35) + Vector3(0, 0.2, 0)
			fov = 62.0
		"hero_back":
			# behind and to one side: the car, and the creature ahead of it down the street
			pos = pulled(cpos + Vector3(0, 1.4, 0), cpos - cf * 7.5 + cr * 2.6 + Vector3(0, 2.2, 0))
			look = cpos.lerp(m.pos + Vector3(0, 1.5, 0), 0.45) + Vector3(0, 0.8, 0)
			fov = 60.0
		"drone":
			pos = cpos - cf * 14.0 + Vector3(0, 16.0, 0)
			look = cpos + cf * 22.0
			fov = 55.0
		"drone_up":
			var mid := cpos.lerp(m.pos, 0.5)
			var rise: float = t - events.fall - 5.0
			pos = mid - cf * 10.0 + cr * 6.0 + Vector3(0, 6.0 + rise * 2.5, 0)
			look = mid
			fov = 58.0
		"fall_side":
			var mid2 := cpos.lerp(m.pos, 0.5)
			pos = pulled(mid2 + Vector3(0, 1.2, 0), mid2 + cr * 11.0 + Vector3(0, 1.5, 0))
			look = mid2 + Vector3(0, 1.2, 0)
			fov = 60.0
		"front_low":
			# ahead of the bonnet, low, looking back along the car
			pos = pulled(cpos + cf * (hl + 0.4) + Vector3(0, 1.0, 0), cpos + cf * (hl + 6.0) + cr * 1.3 + Vector3(0, 0.9, 0))
			look = cpos.lerp(rhead, 0.45) + Vector3(0, 0.5, 0)
			fov = 64.0
		"dash_back":
			# just behind and above the boot, outside the car, looking back at it
			pos = cpos - cf * (hl + 1.3) + cr * 0.6 + Vector3(0, 1.9, 0)
			look = rhead
			fov = 70.0
		"side_low":
			pos = pulled(cpos + cr * (hw + 0.4) + Vector3(0, 0.8, 0), cpos + cr * (hw + 6.0) - cf * 2.0 + Vector3(0, 0.8, 0))
			look = cpos.lerp(rhead, 0.4) + Vector3(0, 0.8, 0)
			fov = 62.0
		"hood":
			# on the bonnet looking ahead: it charges at the lens
			pos = cpos + cf * (hl + 0.2) + Vector3(0, 1.3, 0)
			look = rhead - Vector3(0, 0.6, 0)
			fov = 60.0
		"rex_face":
			pos = pulled(rhead, rhead + fwd * 9.0 + right * 1.5 + Vector3(0, -1.9, 0))
			look = rhead + Vector3(0, 0.2, 0)
			fov = 56.0
		"wreck":
			# side on to the creature and the wreck it is walking up to
			var dd := Vector3(m.pos.x - cpos.x, 0.0, m.pos.z - cpos.z).normalized()
			var mid4 := cpos.lerp(Vector3(m.pos.x, cpos.y, m.pos.z), 0.45)
			pos = pulled(mid4 + Vector3(0, 1.2, 0), mid4 + Vector3(-dd.z, 0.0, dd.x) * 10.0 + Vector3(0, 1.3, 0))
			look = mid4 + Vector3(0, 1.4, 0)
			fov = 62.0
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
		"dom_front":
			var ahead := poly_at(rpath, rs + 20.0)
			var fw2 := poly_dir(rpath, rs)
			var n2 := Vector3(-fw2.y, 0.0, fw2.x)
			var base := Vector3(ahead.x, 0.0, ahead.y)
			pos = pulled(base + Vector3(0, 1.0, 0), base + n2 * 4.0 + Vector3(0, 0.8, 0))
			look = m.pos + Vector3(0, 2.4, 0)
			fov = 60.0
		"dom_side":
			var fw3 := poly_dir(rpath, rs)
			var n3 := Vector3(-fw3.y, 0.0, fw3.x)
			var p3 := poly_at(rpath, rs + 3.0)
			var base3 := Vector3(p3.x, 0.0, p3.y)
			pos = pulled(base3 + Vector3(0, 1.4, 0), base3 - n3 * 12.0 + Vector3(0, 1.4, 0))
			look = base3 + Vector3(0, 1.8, 0)
			fov = 64.0
		"dom_high":
			pos = m.pos - fwd * 6.0 + right * 2.0 + Vector3(0, 6.5, 0)
			look = m.pos + fwd * 14.0 + Vector3(0, 1.0, 0)
			fov = 62.0
		"feet":
			pos = pulled(m.pos + Vector3(0, 0.4, 0), m.pos + right * 4.5 + fwd * 3.0 + Vector3(0, 0.35, 0))
			look = m.pos + Vector3(0, 1.2, 0)
			fov = 60.0
		"hide_pov":
			var hp := Vector3(hide.x, g.pl.pos.y, hide.y)
			var to := (Vector3(m.pos.x, hp.y, m.pos.z) - hp).normalized()
			var side := Vector3(-to.z, 0.0, to.x)
			pos = pulled(hp + Vector3(0, 0.9, 0), hp - to * 1.6 + side * 0.5 + Vector3(0, 1.05, 0))
			look = rhead.lerp(hp + Vector3(0, 0.8, 0), 0.15)
			fov = 60.0
		"rex_close":
			pos = pulled(rhead, rhead + right * 3.8 + fwd * 1.6 + Vector3(0, -0.4, 0))
			look = rhead
			fov = 56.0
		"wide":
			var hp2 := Vector3(hide.x, 0.0, hide.y)
			var mid3 := hp2.lerp(m.pos, 0.5)
			var dd2 := (m.pos - hp2).normalized()
			var side2 := Vector3(-dd2.z, 0.0, dd2.x)
			pos = pulled(mid3 + Vector3(0, 2.0, 0), mid3 + side2 * 13.0 + Vector3(0, 2.4, 0))
			look = mid3 + Vector3(0, 1.6, 0)
			fov = 62.0
		_:
			return
	# never inside the creature, never under the street
	pos = g.pl._out_of_rex(pos, (look - pos).normalized())
	pos.y = maxf(pos.y, g.world.ground_at(pos.x, pos.z, 0.0) + 0.25)
	# a cameraman, not a rig bolted to the car: it eases after its mark within a shot, and cuts clean between
	if mode != last_mode or mode == "locked":
		cam_p = pos
		cam_l = look
	else:
		var k := 1.0 - exp(-maxf(dt, 0.0) / 0.2)
		cam_p = cam_p.lerp(pos, k)
		cam_l = cam_l.lerp(look, k)
	last_mode = mode
	if cam_p.distance_to(cam_l) < 0.5:
		return
	var c: Camera3D = g.cam
	c.position = cam_p + jit
	c.fov = fov
	c.look_at(cam_l)
	# the car must stay in frame in a car shot: if it slips out, back to the hero shot for a moment
	if car != null and g.pl.driving and mode in ["front_low", "dash_back", "side_low", "hood"] and mode != "dash_back":
		var probe := Vector3(car.pos.x, car.y + 0.8, car.pos.y)
		var sz := c.get_viewport().get_visible_rect().size
		var sp := c.unproject_position(probe)
		if c.is_position_behind(probe) or sp.x < sz.x * 0.06 or sp.x > sz.x * 0.94 or sp.y < sz.y * 0.06 or sp.y > sz.y * 0.94:
			hero_until = t + 1.5
