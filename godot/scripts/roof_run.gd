## Roof Run: an endless run over the roofs and down the streets of a city in the sun (the menu's ROOF RUN).
## He runs by himself and the way turns by itself (the corners are on the roofs); the player only acts:
##   swipe up    leap (an alley, a step up, an air unit, a fence, a barrier; onto a car)
##   swipe down  dive and roll (under a pipe or a gantry); in the air: straight down and roll
##   swipe left / right  change lane (three of them), in the air too
## A swipe counts the moment the finger has moved (scripts/swipe.gd) and is remembered for a moment, so one made
## just before he lands still happens. Keys: arrows or WASD, space to leap.
## Off the end of the roofs he drops into a street; cars come at him in one lane, parked cars, barriers and
## gantries stand in the others; a pad near its end throws him back up onto the roofs, and round it goes, faster
## each time. Falling into an alley, running into a wall, a car or anything he did not clear ends the run; a lane
## change into something only bounces him back.
## The world is scripts/roof_track.gd. --auto (tests, videos): it plays itself. --record: also prints what
## happens for the Shorts sound mix (see tests/short.gd --mode=endless).
class_name RoofRun
extends Node3D

const SAVE := "user://roofrun.json"
const LAT := 15.0            # m/s sideways changing lane
const BUFFER := 0.16         # s a swipe is remembered
const COYOTE := 0.12         # s after running off an edge he can still leap
const ROLL_LOW := Vector2(0.72, 1.85)   # the dive and roll is low (under 1 m) between these clip times
const H_STAND := 1.75
const H_LOW := 0.95

var track: RoofTrack
var man: Man
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var ground: MeshInstance3D
var swipe := Swipe.new()
var settings := {vol = 80, gfx = "auto", vib = true}
var save := {best = 0, coins = 0, runs = 0}

# him, in path space
var s := 2.0
var x := 0.0
var y := 14.0
var vy := 0.0
var v := 8.0
var lane := 1
var lane_from := 1
var grounded := true
var coyote := 0.0
var last_floor := 14.0
var mode := "run"            # run, air, land, roll, dead
var air := {}                # the leap or fall he is in: kind, t, T, clip, flip, from
var roll_land := false       # land in a roll (a big drop, or a swipe down in the air)
var buffered := {}           # gesture -> seconds it is still good for
var stumble_t := 0.0
var t := 0.0
var dist := 0.0
var coins := 0
var bonus := 0
var best_before := 0
var cause := ""
var beat_i := 0              # the next beat (drop, launch) on the track
var launched_at := -1.0
var passed := {}             # the cars already counted as passed or leapt, by number
var counts := {jumps = 0, rolls = 0, dodges = 0, bounces = 0, launches = 0, drops = 0, close = 0, over = 0, landings_hard = 0}

# camera
var cam_yaw := 0.0
var cam_y := 14.0
var shake := 0.0
var fov_base := 62.0
var dead_t := 0.0

# run settings
var auto := false
var record := false
var seed_n := 0
var max_t := 0.0             # (record/tests) stop after this many seconds
var outcome := "pass"        # (record) pass: it keeps going; car / fall: near the end it stops playing and comes to grief
var give_up := INF           # (record, car / fall) when it stops playing (in the street for a car, on the roofs for a fall)
var portrait := false        # the screen is taller than wide (a Shorts recording): a closer camera, a bigger HUD
var paused := false
var started := false

# hud
var hud: CanvasLayer
var lbl := {}
var popup_t := 0.0
var hint_t := 6.0
var over_panel: Control
var pause_panel: Control

# sound
var voices: Array[AudioStreamPlayer] = []
var streams := {}
var wind: AudioStreamPlayer
var steps_seen := 0
var trail: Array = []        # (playing itself) the last frames, printed if it crashes
var prof := {}               # where a frame's time goes (microseconds, summed): see the test

func _init(p_seed := 0, p_auto := false) -> void:
	seed_n = p_seed if p_seed != 0 else randi_range(1, 99999)
	auto = p_auto
	name = "RoofRun"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--auto":
			auto = true
		elif a == "--record":
			record = true
			auto = true
		elif a.begins_with("--seed="):
			seed_n = int(a.substr(7))
		elif a.begins_with("--length=") and float(a.substr(9)) > 0.0:
			max_t = float(a.substr(9))
		elif a.begins_with("--outcome="):
			outcome = a.substr(10)
	if record:
		auto = true
		if max_t <= 0.0:
			max_t = 45.0
		if outcome == "random":
			outcome = ["pass", "pass", "car"][seed_n % 3]
		if outcome != "pass":
			# it gives up playing a few seconds before the end (once it is somewhere it can come to grief the way
			# asked for), and has a little longer to come to grief in
			give_up = maxf(max_t - 6.0, max_t * 0.6)
			max_t += 18.0
	Engine.time_scale = 1.0
	settings.merge(U.load_json("user://settings.json"), true)
	save.merge(U.load_json(SAVE), true)
	best_before = int(save.best)
	RenderingServer.global_shader_parameter_set("rain_amount", 0.0)
	RenderingServer.global_shader_parameter_set("refl_on", 0.0)
	RenderingServer.global_shader_parameter_set("daylight", 1.0)
	RenderingServer.global_shader_parameter_set("tremor", 0.0)
	_world()
	track = RoofTrack.new(seed_n)
	track.speed_at = func(at: float) -> float: return _speed_for(at)
	add_child(track)
	track.update(0.0, 0.0)
	man = Man.new()
	add_child(man)
	y = 14.0
	last_floor = y
	man.reset(track.yaw_at(s))
	man.state = Man.MOVE
	man.speed = v
	man.real_speed = v
	cam_yaw = track.yaw_at(s)
	cam_y = y
	_sounds()
	_hud()
	_gfx()
	get_viewport().size_changed.connect(_gfx)
	print("ROOFRUN seed %d%s" % [seed_n, " (auto)" if auto else ""])
	if record:
		print("PREROLL 0.0000")
	started = true

# ---------------------------------------------------------------- the world around the track
func _world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.25, 0.5, 0.86)
	sm.sky_horizon_color = Color(0.76, 0.84, 0.92)
	sm.ground_horizon_color = Color(0.76, 0.84, 0.92)
	sm.ground_bottom_color = Color(0.3, 0.32, 0.35)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	# (a warm, neutral fill: the sky's own blue made every wall look cold)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.72)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.76, 0.84, 0.92)
	env.fog_density = 0.0
	env.fog_depth_curve = 1.4
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 230.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.shadow_bias = 0.05
	add_child(sun)
	# the ground (alleys and streets), kept under him
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(700, 700)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.2, 0.21)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	cam = Camera3D.new()
	cam.near = 0.15
	cam.far = 260.0
	add_child(cam)
	cam.current = true

## Graphics from the game's setting (scripts/game.gd): render scale, shadows, anti-aliasing; the field of view
## for the screen's shape (a portrait recording keeps its width).
func _gfx() -> void:
	var mobile := OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	if mobile:
		Engine.max_fps = 60
	var lv := {"low": 0, "medium": 1, "high": 2}.get(String(settings.gfx), 1 if mobile else 2) as int
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [0.6, 0.75, 0.9][lv] if mobile else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if lv == 0 else Viewport.MSAA_2X
	sun.shadow_enabled = lv > 0
	var sz := vp.get_visible_rect().size
	portrait = sz.y > sz.x
	if portrait:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		fov_base = 70.0
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		fov_base = 64.0

## His speed at a distance: 8 m/s to start with, rising towards 12.5 (a recording starts as if 1.5 km in).
func _speed_for(at: float) -> float:
	return 8.0 + 4.5 * (1.0 - exp(-(at + (1500.0 if record else 0.0)) / 2600.0))

# ---------------------------------------------------------------- each frame
func _process(delta: float) -> void:
	if not started:
		return
	var dt := minf(delta, 1.0 / 20.0)
	if paused:
		return
	t += dt
	if mode == "dead":
		dead_t += dt
		_animate_dead(dt)
		_camera(dt)
		_update_hud(dt)
		if (auto or record) and dead_t > 1.6:
			_finish()
		return
	var u0 := Time.get_ticks_usec()
	if auto and not _given_up():
		_autopilot()
		trail.append("t %.2f s %.2f x %.2f y %.2f vy %.1f %s %s lane %d buf %s" % [t, s, x, y, vy, mode, "g" if grounded else "a", lane, str(buffered.keys())])
		if trail.size() > 14:
			trail.pop_front()
	var u1 := Time.get_ticks_usec()
	_step(dt)
	var u2 := Time.get_ticks_usec()
	track.move_cars(dt, s, v)
	track.update(s, s)
	var u3 := Time.get_ticks_usec()
	_coins_and_cars()
	_camera(dt)
	_update_hud(dt)
	var u4 := Time.get_ticks_usec()
	for k in [["auto", u1 - u0], ["step+body", u2 - u1], ["track", u3 - u2], ["coins+cam+hud", u4 - u3]]:
		prof[k[0]] = int(prof.get(k[0], 0)) + int(k[1])
	ground.global_position = Vector3(snappedf(cam.global_position.x, 10.0), 0.0, snappedf(cam.global_position.z, 10.0))
	if man.step != steps_seen:
		steps_seen = man.step
		if grounded and mode != "roll":
			_play("step_dry_%d" % (steps_seen % 4 + 1), -15.0 + randf() * 2.0, 1.0 + randf() * 0.1)
			_event("step")
	wind.volume_db = lerpf(-30.0, -14.0, clampf((y - 2.0) / 14.0, 0.0, 1.0))
	if max_t > 0.0 and t >= max_t:
		_event("end")
		_finish()

func _step(dt: float) -> void:
	v = _speed_for(s)
	if stumble_t > 0.0:
		stumble_t -= dt
		v *= 0.82
	for k in buffered.keys():
		buffered[k] = float(buffered[k]) - dt
		if float(buffered[k]) <= 0.0:
			buffered.erase(k)
	coyote = maxf(0.0, coyote - dt)
	# what he was asked to do
	if buffered.has("left") or buffered.has("right"):
		var d := -1 if buffered.has("left") else 1
		buffered.erase("left")
		buffered.erase("right")
		var to := clampi(lane + d, 0, 2)
		if to != lane:
			lane_from = lane
			lane = to
			counts.dodges += 1
			_play("step_dry_2", -10.0, 1.2)
			_event("dodge")
	if buffered.has("up") and (grounded or coyote > 0.0) and mode != "air":
		buffered.erase("up")
		_leap()
	if buffered.has("down"):
		if grounded and mode in ["run", "land"]:
			buffered.erase("down")
			_roll(0.55)
		elif not grounded:
			buffered.erase("down")
			vy = minf(vy, -15.0)
			roll_land = true
	# the beats: the launch pad in the street
	while beat_i < track.beats.size() and s > float(track.beats[beat_i].s) + 0.5:
		var b: Dictionary = track.beats[beat_i]
		beat_i += 1
		if b.kind == "drop":
			counts.drops += 1
			_event("drop")
	for b in track.beats:
		if b.kind == "launch" and s >= float(b.s) and s < float(b.s) + 3.0 and launched_at < float(b.s):
			launched_at = float(b.s)
			_launch(b)
	# sideways
	var x_was := x
	var tx: float = RoofTrack.LANES[lane]
	var nx := move_toward(x, tx, LAT * dt)
	var h := _height()
	var foot := y + (RoofTrack.STEP if grounded else 0.05)
	var side := track.hit(s - 0.28, s + 0.28, nx - 0.3, nx + 0.3, foot, y + h)
	if not side.is_empty() and float(side.y1) > foot:
		# bounced back into the lane he came from
		lane = lane_from
		stumble_t = 0.6
		counts.bounces += 1
		shake = maxf(shake, 0.25)
		_play("thud_1", -6.0, 1.1)
		_popup("WATCH OUT!", Color(1.0, 0.5, 0.3))
		_vibrate(40)
		_event("bump")
	else:
		x = nx
	var vx := (x - x_was) / dt
	# forwards
	var fwd: float = air.get("vh", v) if mode == "air" else v
	var ns := s + fwd * dt
	foot = y + (RoofTrack.STEP if grounded else 0.05)
	var o := track.hit(ns - 0.3, ns + 0.3, x - 0.3, x + 0.3, foot, y + h)
	if not o.is_empty():
		if not grounded and vy <= 0.5 and float(o.y1) - y < 0.4:
			# coming down onto it: stand on it
			y = float(o.y1)
		else:
			_die(o)
			return
	s = ns
	dist = maxf(dist, s)
	# up and down
	if grounded:
		var fl := track.floor_at(s, x, y)
		if fl < y - 0.03:
			grounded = false
			vy = 0.0
			coyote = COYOTE
			_start_air("fall")
		else:
			y = fl
	if not grounded:
		air.t = float(air.get("t", 0.0)) + dt
		vy -= RoofTrack.GRAV * dt
		var ny := y + vy * dt
		var fl := track.floor_at(s, x, y + 0.05, 0.3)
		if vy <= 0.0 and ny <= fl:
			y = fl
			_land()
		else:
			y = ny
		if track.zone_at(s) == "roof" and y < last_floor - 4.5:
			_die({kind = "fall"})
			return
	_animate(dt, vx)

func _height() -> float:
	if man.state == Man.JUMP and man.clip == "dive_roll" and man.ct > ROLL_LOW.x and man.ct < ROLL_LOW.y:
		return H_LOW
	return H_STAND

# ---------------------------------------------------------------- moves
func _leap() -> void:
	grounded = false
	vy = RoofTrack.JUMP_V
	coyote = 0.0
	counts.jumps += 1
	_start_air("jump")
	_play("step_dry_3", -6.0, 0.9)
	_play("card_1", -14.0, 0.7)
	_event("takeoff")
	# a leap off the last roof into the street: a flip on the way down
	for b in track.beats:
		if b.kind == "drop" and float(b.s) - s < 12.0 and float(b.s) - s > -0.5:
			air.flip = true
			bonus += 150
			_popup("+150  STYLE!", Color(1.0, 0.85, 0.3))

## In the air, by a leap or off an edge: the captured leap played over the time he will be up there (worked out
## now, from what is ahead), off whichever foot is nearer.
func _start_air(kind: String) -> void:
	var ph := fposmod(man.phase, 1.0)
	var c := "gap_jump" if ph < 0.5 else "gap_jump_r"
	var T := _predict_air()
	air = {kind = kind, t = 0.0, T = T, clip = c, flip = false, from_y = y}
	mode = "air"
	if kind == "fall" and T < 0.22:
		# a step down: he just keeps running
		air.clip = ""
		return
	var m: Dictionary = man.meta[c]
	man.jump(c, float(m.takeoff) - (0.05 if kind == "fall" else 0.0), 0.1)
	roll_land = roll_land or T > 1.0

func _predict_air() -> float:
	var ps := s
	var py := y
	var pv := vy
	var step := 1.0 / 60.0
	var tt := 0.0
	while tt < 3.0:
		tt += step
		pv -= RoofTrack.GRAV * step
		var ny := py + pv * step
		ps += float(air.get("vh", v)) * step if air.get("kind", "") == "launch" else v * step
		var fl := track.floor_at(ps, x, py + 0.05, 0.3)
		if pv <= 0.0 and ny <= fl:
			return tt
		py = ny
	return tt

func _land() -> void:
	var hard: bool = float(air.get("T", 0.0)) > 1.0 or air.get("kind", "") == "launch"
	grounded = true
	last_floor = y
	vy = 0.0
	if roll_land or hard:
		roll_land = false
		counts.landings_hard += 1
		shake = maxf(shake, 0.5 if hard else 0.2)
		_play("thud_2", -2.0, 0.85)
		if hard:
			_play("boom_1", -12.0, 1.2)
		_vibrate(60 if hard else 25)
		_event("slam" if hard else "touchdown")
		_roll(1.15)
	else:
		_play("thud_2", -9.0, 1.1)
		_play("step_dry_1", -8.0, 0.9)
		_event("touchdown")
		if air.get("clip", "") != "":
			man.jump_rate = 1.6
			mode = "land"
		else:
			mode = "run"
	man.body.rotation = Vector3()
	man.body.position = Vector3()
	air = {}

## The dive and roll, from clip time `at` (0.55: from the run, straight into the dive; 1.15: landing into it).
func _roll(at: float) -> void:
	man.jump("dive_roll", at, 0.08)
	man.jump_rate = 1.75
	mode = "roll"
	if at < 1.0:
		counts.rolls += 1
		_play("thud_1", -10.0, 1.3)
		_event("dive")

## Thrown up from the pad onto the roof at the end of the street, turning over at the top.
func _launch(b: Dictionary) -> void:
	var h := float(b.h)
	var apex := h + 2.8
	var vy0 := sqrt(2.0 * RoofTrack.GRAV * (apex - y))
	var T := vy0 / RoofTrack.GRAV + sqrt(2.0 * (apex - h) / RoofTrack.GRAV)
	grounded = false
	vy = vy0
	air = {}
	_start_air("launch")
	air.vh = (float(b.s_land) - s) / T
	air.T = T
	air.flip = true
	counts.launches += 1
	bonus += 100
	_popup("+100  UP YOU GO!", Color(0.5, 0.85, 1.0))
	_play("boom_2", -6.0, 0.8)
	_play("card_2", -10.0, 0.6)
	_vibrate(50)
	_event("launch")

func _die(o: Dictionary) -> void:
	mode = "dead"
	var k := String(o.get("kind", ""))
	# frozen tucked, thrown over (see _animate_dead)
	man.jump("gap_jump", 0.8, 0.15)
	man.jump_rate = 0.0
	man.body.position = Vector3()
	cause = {"car": "HIT BY A CAR", "roof": "RAN INTO A WALL", "fall": "FELL", "tank": "RAN INTO A WATER TANK",
		"pipe": "HIT THE PIPE", "box": "TRIPPED", "fence": "TRIPPED", "barrier": "TRIPPED"}.get(k, "CRASHED")
	dead_t = 0.0
	shake = 0.7
	if k == "fall":
		_play("card_2", -8.0, 0.5)
	else:
		_play("boom_1", -2.0, 0.9)
		_play("clang_2", -4.0, 1.0)
		_play("thud_3", -3.0, 0.8)
		if k == "car":
			_play("shatter_1", -4.0, 1.0)
	_vibrate(180)
	_event("crash")
	if record:
		print("EVENT fail %.2f" % t)
	print("ROOFRUN over at %.0f m (%s), %d coins, score %d, %.1f s" % [dist, cause, coins, score(), t])
	if o.has("s0"):
		print("   ran into %s s %.1f-%.1f x %.1f-%.1f y %.2f-%.2f v %.1f; he was at s %.2f x %.2f y %.2f (vy %.1f, %s, lane %d, %s %.2f)" % [k,
			float(o.s0), float(o.s1), float(o.x0), float(o.x1), float(o.y0), float(o.y1), float(o.get("v", 0.0)), s, x, y, vy, mode,
			lane, man.clip, man.ct])
	for l in trail:
		print("   | ", l)
	_end_run()

func score() -> int:
	return int(dist) + coins * 10 + bonus

# ---------------------------------------------------------------- his body
func _animate(dt: float, vx: float) -> void:
	var d := track.dir_at(s)
	var path_yaw := atan2(d.x, d.y)
	var yaw0 := man.yaw
	match mode:
		"air":
			if air.get("clip", "") != "":
				var m: Dictionary = man.meta[air.clip]
				var k := clampf(float(air.t) / maxf(float(air.T), 0.05), 0.0, 1.0)
				man.ct = float(m.takeoff) + (float(m.land) - float(m.takeoff)) * k
			else:
				man.speed = v
				man.real_speed = v
				man.move(dt, d, v, false)
		"land", "roll":
			man.move(dt, d, v, false)
			var done := false
			if mode == "land":
				done = man.ct >= float(man.meta[man.clip].land) + 0.22 and man.run_on()
			else:
				done = man.ct >= ROLL_LOW.y and man.run_on()
			if done or man.state != Man.JUMP:
				mode = "run"
				man.speed = v
		_:
			if man.state != Man.MOVE and man.state != Man.JUMP:
				man.state = Man.MOVE
			man.speed = v
			man.real_speed = v
			man.move(dt, d, v, false)
	# facing: along the path, turned the way he is moving sideways
	man.yaw = path_yaw - atan2(vx, maxf(v, 1.0)) * 0.6
	man.turn_rate = U.ang_diff(yaw0, man.yaw) / maxf(dt, 1e-4)
	man.position = track.world(s, x, y)
	man.rotation.y = man.yaw
	var ua := Time.get_ticks_usec()
	man.animate(dt)
	prof["body only"] = int(prof.get("body only", 0)) + Time.get_ticks_usec() - ua
	# a flip: the whole body turned over about his hips, through the middle of the flight
	if mode == "air" and air.get("flip", false):
		var k := clampf(float(air.t) / maxf(float(air.T), 0.05), 0.0, 1.0)
		var u := clampf((k - 0.18) / 0.62, 0.0, 1.0)  # (the flip)
		var a := TAU * u * u * (3.0 - 2.0 * u)
		var piv := Vector3(0, 0.95, 0)
		var b := Basis(Vector3.RIGHT, a)
		man.body.basis = b * man.body.basis
		man.body.position = piv - b * piv

func _animate_dead(dt: float) -> void:
	# thrown back and down: he goes over and lies still
	var k := clampf(dead_t / 0.5, 0.0, 1.0)
	if cause == "FELL":
		vy -= RoofTrack.GRAV * dt
		y = maxf(y + vy * dt, 0.0)
		s += v * 0.3 * dt * (1.0 - k)
	else:
		s -= 2.5 * dt * (1.0 - k)
	man.position = track.world(s, x, y)
	man.animate(dt)
	var b := Basis(Vector3.RIGHT, -PI * 0.5 * k)
	var piv := Vector3(0, 0.9, 0)
	man.body.basis = b
	man.body.position = piv - b * piv + Vector3(0, -0.6 * k, 0)

# ---------------------------------------------------------------- coins, cars he passes
func _coins_and_cars() -> void:
	for c in track.coins:
		if c.get("taken", false):
			continue
		var n: MeshInstance3D = c.node
		if not is_instance_valid(n):
			continue
		if absf(float(c.s) - s) < 18.0:
			n.rotate(Vector3.UP, 3.0 * get_process_delta_time())
		if absf(float(c.s) - s) < 0.8 and absf(float(c.x) - x) < 0.95 and float(c.y) > y - 0.3 and float(c.y) < y + _height() + 0.3:
			c.taken = true
			n.visible = false
			coins += 1
			_play("chime", -16.0, 1.6 + randf() * 0.3)
			_event("coin")
	for o in track.near:
		# (by its number: a dictionary as a key goes by what is in it, and a car's place changes)
		if o.kind != "car" or passed.has(o.id):
			continue
		if float(o.s1) < s - 0.4:
			passed[o.id] = true
			var dx := absf((float(o.x0) + float(o.x1)) * 0.5 - x)
			if not grounded and y >= float(o.y1) - 0.2 and dx < 1.2:
				counts.over += 1
				bonus += 50
				_popup("+50  OVER IT!", Color(1.0, 0.85, 0.3))
				_event("vault")
			elif float(o.v) < 0.0 and dx < 3.0:
				counts.close += 1
				bonus += 25
				_popup("+25  CLOSE ONE!", Color(1.0, 0.7, 0.3))
				_play("card_1", -12.0, 0.5)
				_event("pass")

# ---------------------------------------------------------------- the camera
func _camera(dt: float) -> void:
	var yaw := track.yaw_at(s + 3.0)
	cam_yaw = lerp_angle(cam_yaw, yaw, 1.0 - exp(-dt / 0.28))
	var up_tau := 0.08 if y > cam_y else 0.22
	cam_y = lerpf(cam_y, y, 1.0 - exp(-dt / up_tau))
	var fwd := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var high: bool = mode == "air" and air.get("kind", "") == "launch"
	var back := 6.6 if high else (4.4 if portrait else 5.4)
	var up := 3.4 if high else (2.6 if portrait else 2.5)
	var him := track.world(s, x * 0.6, cam_y)
	var p := him - fwd * back + Vector3.UP * up
	var look := him + fwd * (4.5 if portrait else 6.0) + Vector3.UP * (0.7 if portrait else 1.0)
	if mode == "dead":
		p = cam.global_position
		look = man.global_position + Vector3.UP * 0.6
	shake = maxf(0.0, shake - dt * 1.6)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * shake * 0.25
	cam.global_position = p + right * sh.x + Vector3.UP * sh.y
	if cam.global_position.distance_to(look) > 0.1:
		cam.look_at(look, Vector3.UP)
	cam.fov = lerpf(cam.fov if cam.fov > 1.0 else fov_base, fov_base + clampf((v - 8.0) * 1.4, 0.0, 7.0), 1.0 - exp(-dt / 0.5))

# ---------------------------------------------------------------- the player
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_ESCAPE or e.keycode == KEY_P):
		_set_pause(not paused)
		return
	if paused or mode == "dead" or auto:
		return
	var g := swipe.feed(e)
	if g == "tap":
		g = "up"
	if g != "":
		buffered[g] = BUFFER
		hint_t = minf(hint_t, 0.6)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if started and mode != "dead" and not auto:
			_set_pause(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if paused or mode == "dead":
			_to_menu()
		else:
			_set_pause(true)

func _set_pause(on: bool) -> void:
	if mode == "dead":
		return
	paused = on
	pause_panel.visible = on
	for p in voices:
		p.stream_paused = on
	wind.stream_paused = on
	get_tree().paused = false

# ---------------------------------------------------------------- it plays itself (tests, videos)
## Looks down each lane for what he cannot leap or roll under (a water tank, a tall car, a car coming at him)
## and moves to the lane where that is furthest off; in his lane it leaps or rolls what is there, and leaps alleys
## and steps up at the right moment.
func _autopilot() -> void:
	_auto_lane()
	if not grounded and mode == "air":
		return
	var look := v * 1.2 + 4.0
	# things in his lane (where he will be once the lane change is done)
	for e in track.ahead_in_lane(s, lane, look):
		var d: float = e[0]
		var o: Dictionary = e[1]
		var top := float(o.y1)
		var bottom := float(o.y0)
		if top <= y + RoofTrack.STEP or float(o.s1) < s or bottom > y + H_STAND:
			continue
		var closing := v - float(o.v)
		var dt_hit := (d - 0.3) / maxf(closing, 0.5)
		if bottom > y + 1.0:
			# above his waist: roll under it
			if dt_hit < 0.22 + 2.0 / v and mode in ["run", "land"]:
				buffered["down"] = BUFFER
			break
		if top - y < 1.25:
			# low enough to leap
			if dt_hit < 0.27:
				buffered["up"] = BUFFER
			break
	if grounded and track.zone_at(s) == "roof":
		# an alley (not a step down onto the next roof: that he just runs off), and walls to leap up
		var ahead := 0.45 + v * 0.03
		if track.floor_at(s + ahead, x, y) < y - 3.3 and track.floor_at(s + ahead + 1.2, x, y) < y - 3.3:
			buffered["up"] = BUFFER
		var wall := track.hit(s + 0.3, s + v * 0.2 + 0.6, x - 0.3, x + 0.3, y + RoofTrack.STEP, y + 1.6)
		if not wall.is_empty() and wall.kind == "roof":
			buffered["up"] = BUFFER

## Moves to the lane that stays clear longest of what he could not get past (see _lane_clear_for).
func _auto_lane() -> void:
	var horizon := 2.6
	var times: Array[float] = []
	for l in 3:
		times.append(_lane_clear_for(l, horizon, absi(l - lane) * 0.17))
	if times[lane] >= horizon:
		# nothing in the way: go for the coins in the next lane if that is clear too
		for c in track.coins:
			if c.get("taken", false) or float(c.s) < s + 3.0 or float(c.s) > s + v * 1.4 or float(c.y) > y + 1.6:
				continue
			var cl := RoofTrack.LANES.find(float(c.x))
			if cl >= 0 and absi(cl - lane) == 1 and times[cl] >= horizon:
				buffered["right" if cl > lane else "left"] = BUFFER
				break
		return
	var best := lane
	var bt: float = times[lane]
	for l in 3:
		if l == lane:
			continue
		# going two lanes over crosses the middle one
		if absi(l - lane) == 2 and times[1] < 0.45:
			continue
		if times[l] > bt + 0.15 or (times[l] > bt and absi(l - lane) < absi(best - lane)):
			bt = times[l]
			best = l
	if best != lane:
		buffered["right" if best > lane else "left"] = BUFFER

## How long lane l stays free of things he cannot get past: too tall to leap, too low to roll under, coming at
## him, or something he could leap or roll but that is already too near to (after `extra` seconds getting there).
func _lane_clear_for(l: int, horizon: float, extra: float) -> float:
	var first := horizon
	for e in track.ahead_in_lane(s, l, v * horizon + 25.0):
		var o: Dictionary = e[1]
		if float(o.s1) < s - 0.3:
			continue
		var top := float(o.y1)
		var bottom := float(o.y0)
		if top <= y + RoofTrack.STEP or bottom > y + H_STAND:
			continue
		var closing := v - float(o.v)
		if closing <= 0.1:
			continue
		var tt := (float(o.s0) - s - 0.4) / closing
		var moving: bool = float(o.v) != 0.0 and o.kind == "car"
		var need := INF
		if bottom > y + 1.0:
			need = 0.32 + extra
		elif top - y < 1.25 and not moving:
			need = 0.2 + extra
		if tt >= need and need < INF:
			continue
		first = minf(first, maxf(tt, 0.0))
	return first

func _given_up() -> bool:
	if t < give_up:
		return false
	var z := track.zone_at(s)
	return t > give_up + 12.0 or (outcome == "car" and z == "street") or (outcome != "car" and z == "roof")

# ---------------------------------------------------------------- what is shown
func _hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 20
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	var big := _big_font()
	var cond: Font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	# (a portrait recording is 1080 wide: everything bigger)
	var sz := get_viewport().get_visible_rect().size
	var k := maxf(1.0, sz.x / 430.0) if sz.y > sz.x else 1.0
	var mk := func(f: Font, size: int, col := Color.WHITE) -> Label:
		size = int(size * k)
		var l := Label.new()
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", col)
		l.add_theme_constant_override("outline_size", maxi(4, size / 7))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l
	var dist_l: Label = mk.call(big, 46)
	dist_l.position = Vector2(22, 8) * k + (Vector2(0, 90) if k > 1.0 else Vector2())
	hud.add_child(dist_l)
	var coin_l: Label = mk.call(cond, 24, Color(1.0, 0.85, 0.3))
	coin_l.position = Vector2(24, 62) * k + (Vector2(0, 90) if k > 1.0 else Vector2())
	hud.add_child(coin_l)
	var best_l: Label = mk.call(cond, 18, Color(1, 1, 1, 0.8))
	best_l.position = Vector2(24, 92) * k + (Vector2(0, 90) if k > 1.0 else Vector2())
	hud.add_child(best_l)
	var pop: Label = mk.call(big, 40, Color(1.0, 0.85, 0.3))
	pop.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pop.position.y = 70 * k + (300.0 if k > 1.0 else 0.0)
	hud.add_child(pop)
	var hint: Label = mk.call(cond, 26)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y = -60
	hint.text = "SWIPE UP: LEAP  ·  DOWN: ROLL  ·  LEFT / RIGHT: CHANGE LANE" if DisplayServer.is_touchscreen_available() else "UP / SPACE: LEAP  ·  DOWN: ROLL  ·  LEFT / RIGHT: CHANGE LANE  ·  P: PAUSE"
	hud.add_child(hint)
	lbl = {dist = dist_l, coins = coin_l, best = best_l, pop = pop, hint = hint}
	if not record:
		var pb := Button.new()
		pb.text = "II"
		pb.add_theme_font_override("font", big)
		pb.add_theme_font_size_override("font_size", 30)
		pb.custom_minimum_size = Vector2(64, 56)
		pb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		pb.position = Vector2(-84, 14)
		pb.focus_mode = Control.FOCUS_NONE
		_button_style(pb, false)
		pb.pressed.connect(func(): _set_pause(true))
		hud.add_child(pb)
		lbl.pause = pb
	pause_panel = _panel("PAUSED", "", [["RESUME", func(): _set_pause(false)], ["MENU", _to_menu]], big, cond)
	pause_panel.visible = false
	over_panel = null

## The game's display face, heavy (as on its own screens, scripts/hud.gd).
func _big_font() -> Font:
	var f := FontVariation.new()
	f.base_font = load("res://assets/fonts/BigShouldersDisplay.ttf")
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return f

func _button_style(b: Button, primary: bool) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.93, 0.66, 0.24) if primary else Color(0.05, 0.06, 0.08, 0.75)
		if st.begins_with("pressed") or st == "hover_pressed":
			sb.bg_color = sb.bg_color.darkened(0.25)
		sb.border_color = Color(1, 1, 1, 0.25)
		sb.set_border_width_all(0 if primary else 1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		b.add_theme_stylebox_override(st, sb)
	var fc := Color(0.08, 0.06, 0.03) if primary else Color(0.92, 0.93, 0.95)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fc)

func _panel(title: String, body: String, buttons: Array, big: Font, cond: Font) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(bg)
	var v_box := VBoxContainer.new()
	v_box.set_anchors_preset(Control.PRESET_CENTER)
	v_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	v_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v_box.add_theme_constant_override("separation", 10)
	bg.add_child(v_box)
	var tl := Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_override("font", big)
	tl.add_theme_font_size_override("font_size", 60)
	v_box.add_child(tl)
	if body != "":
		var bl := Label.new()
		bl.text = body
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.add_theme_font_override("font", cond)
		bl.add_theme_font_size_override("font_size", 24)
		v_box.add_child(bl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v_box.add_child(row)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(190, 64)
		btn.add_theme_font_override("font", big)
		btn.add_theme_font_size_override("font_size", 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		_button_style(btn, row.get_child_count() == 0)
		row.add_child(btn)
	return bg

func _update_hud(dt: float) -> void:
	(lbl.dist as Label).text = "%d m" % int(dist)
	(lbl.coins as Label).text = "COINS %d    SCORE %d" % [coins, score()]
	(lbl.best as Label).text = ("BEST %d" % best_before) if best_before > 0 and not record else ""
	popup_t = maxf(0.0, popup_t - dt)
	(lbl.pop as Label).modulate.a = clampf(popup_t / 0.3, 0.0, 1.0)
	hint_t = maxf(0.0, hint_t - dt)
	(lbl.hint as Label).modulate.a = clampf(hint_t / 0.5, 0.0, 1.0) if not record else 0.0

func _popup(text: String, col: Color) -> void:
	var l: Label = lbl.get("pop")
	if l == null:
		return
	l.text = text
	l.add_theme_color_override("font_color", col)
	popup_t = 1.1

# ---------------------------------------------------------------- the end
func _end_run() -> void:
	save.runs = int(save.runs) + 1
	save.coins = int(save.coins) + coins
	var new_best := score() > int(save.best)
	if new_best:
		save.best = score()
	if not auto:
		U.save_json(SAVE, save)
	if record:
		return
	var big := _big_font()
	var cond: Font = load("res://assets/fonts/BarlowCondensed-Bold.ttf")
	var body := "%d m   ·   %d coins   ·   score %d\n%s" % [int(dist), coins, score(), "NEW BEST!" if new_best else "best %d" % int(save.best)]
	over_panel = _panel(cause, body, [["AGAIN", _again], ["MENU", _to_menu]], big, cond)
	over_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(over_panel, "modulate:a", 1.0, 0.35)
	if lbl.has("pause"):
		(lbl.pause as Button).visible = false

func _finish() -> void:
	if not started:
		return
	started = false
	print("ROOFRUN end: %.0f m, %d coins, score %d, %.1f s, %s, roofs %d gaps %d corners %d streets %d cars %d, counts %s" % [dist, coins, score(), t,
		"alive" if mode != "dead" else cause, track.stats.roofs, track.stats.gaps, track.stats.corners, track.stats.streets, track.stats.cars, str(counts)])
	if auto or record:
		get_tree().quit(0)

func _again() -> void:
	var tree := get_tree()
	var n := RoofRun.new()
	tree.root.add_child(n)
	tree.current_scene = n
	queue_free()

func _to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

## Starts a Roof Run from the game's menu: the city scene goes (it is heavy) and the run takes its place.
static func start(tree: SceneTree) -> void:
	var n := RoofRun.new()
	var old := tree.current_scene
	tree.root.add_child(n)
	tree.current_scene = n
	if old != null:
		old.queue_free()

# ---------------------------------------------------------------- sound
func _sounds() -> void:
	for n in ["step_dry_1", "step_dry_2", "step_dry_3", "step_dry_4", "thud_1", "thud_2", "thud_3", "boom_1", "boom_2",
			"clang_2", "shatter_1", "chime", "card_1", "card_2"]:
		streams[n] = load("res://assets/sounds/%s.wav" % n)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
	var vol := float(settings.vol) / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, 0.95 * vol)))
	wind = AudioStreamPlayer.new()
	wind.stream = RoofTrack.looped("wind_loop")
	wind.volume_db = -20.0
	add_child(wind)
	wind.play()

func _play(n: String, db: float, pitch := 1.0) -> void:
	# (a recording gets its effects laid on afterwards, from the events: tools/shorts/compose.py)
	if not streams.has(n) or record:
		return
	for p in voices:
		if not p.playing:
			p.stream = streams[n]
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return

func _vibrate(ms: int) -> void:
	if bool(settings.get("vib", true)) and not auto:
		Input.vibrate_handheld(ms)

## What happened when, for the Shorts sound mix (tools/shorts/compose.py), as "EVENT name seconds".
var _ev_n := {}
func _event(what: String) -> void:
	if not record:
		return
	_ev_n[what] = int(_ev_n.get(what, 0)) + 1
	print("EVENT %s_%d %.2f" % [what, _ev_n[what], t])
