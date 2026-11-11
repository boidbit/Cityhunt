## The Roof Run on its own (scripts/roof_run.gd, scripts/roof_track.gd), headless:
##   godot --headless --path godot --fixed-fps 30 -s res://tests/roof_run_test.gd -- --seed=3
## 1. it plays itself (--auto) for 3 km: it must still be running, have been through streets and back up onto
##    roofs, leapt, rolled, changed lanes and picked up coins; every row of things in his way had a way through;
## 2. nobody playing: the run must end soon, with a reason;
## 3. the swipes: one up leaps, one down rolls (low enough for a pipe), left and right change lane;
## 4. from the game's menu to a run and back, twice: the city scene makes way, and comes back, and the sound buses
##    are not made again each time (they used to pile up);
## and how long a frame of the run's own scripts takes (without drawing).
## Prints "ok"/"FAIL" per check and ends with "DONE fails=N" (exit code 1 if anything failed).
extends SceneTree

var fails := 0
var seed_n := 3
var stage := ""
var run: RoofRun
var frames := 0
var swipes := {}
var only_auto := false      # --only-auto: just the run that plays itself (to try many seeds)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_n = int(a.substr(7))
		elif a == "--only-auto":
			only_auto = true
	_start("auto")

func check(ok: bool, what: String) -> void:
	print("   %s   %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

func _start(st: String) -> void:
	stage = st
	frames = 0
	run = RoofRun.new(seed_n, st == "auto")
	root.add_child(run)
	print("== %s (seed %d)" % [st, seed_n])

func _next(st: String) -> void:
	run.started = false
	run.queue_free()
	run = null
	if st == "":
		print("DONE fails=%d" % fails)
		quit(1 if fails > 0 else 0)
		return
	_start(st)

func _process(_d: float) -> bool:
	if stage == "menu":
		_menu_checks()
		return false
	if run == null or not run.started:
		return false
	frames += 1
	match stage:
		"auto":
			if run.mode == "dead" or run.dist >= 3000.0 or run.t > 500.0:
				var st: Dictionary = run.track.stats
				var c: Dictionary = run.counts
				check(run.mode != "dead", "plays itself for 3 km without a crash (%.0f m, %.0f s%s)" % [run.dist, run.t, (", " + run.cause) if run.mode == "dead" else ""])
				check(c.drops >= 2 and c.launches >= 2, "down into the street and back up onto the roofs, more than once (%d drops, %d launches)" % [c.drops, c.launches])
				check(st.corners >= 2, "the way turns on the roofs (%d corners, %d gaps, %d roofs)" % [st.corners, st.gaps, st.roofs])
				check(c.jumps >= 20, "leaps (%d)" % c.jumps)
				check(c.rolls >= 2, "dives and rolls (%d)" % c.rolls)
				check(c.dodges >= 6, "changes lane (%d)" % c.dodges)
				check(run.coins >= 40, "picks up coins (%d)" % run.coins)
				check(st.cars >= 15, "cars in the streets (%d), %d passed close, %d leapt over" % [st.cars, c.close, c.over])
				check(c.landings_hard >= 4, "hard landings roll (%d)" % c.landings_hard)
				check(run.v > 9.0, "runs faster the further he gets (%.1f m/s)" % run.v)
				check(run.track.solids.size() < 400 and run.track.get_child_count() < 900, "clears what is behind him (%d solids, %d nodes)" % [run.track.solids.size(), run.track.get_child_count()])
				var parts := []
				var tot := 0.0
				for k in run.prof:
					var ms := float(run.prof[k]) / 1000.0 / maxf(frames, 1)
					parts.append("%s %.2f" % [k, ms])
					if k != "body only":
						tot += ms
				check(tot < 2.0, "the run's own scripts are light: %.2f ms a frame (%s)" % [tot, ", ".join(parts)])
				_next("" if only_auto else "idle")
		"idle":
			if run.mode == "dead":
				check(run.dist < 400.0 and run.cause != "", "nobody playing: the run ends soon (%.0f m: %s)" % [run.dist, run.cause])
				_next("swipes")
			elif run.t > 120.0:
				check(false, "nobody playing: the run ends soon (still going at %.0f m)" % run.dist)
				_next("swipes")
		"swipes":
			_swipe_checks()
	return false

## Scripted: a swipe left, up, down and right on the first roof (it is clear for 40 m).
func _swipe_checks() -> void:
	var r := run
	if frames == 10:
		_send(Vector2(-60, 0))
	elif frames == 22:
		check(r.lane == 0 and absf(r.x - RoofTrack.LANES[0]) < 0.05, "swipe left: one lane left (x %.2f)" % r.x)
		_send(Vector2(0, -60))
	elif frames == 26:
		check(not r.grounded and r.vy > 0.0 and r.mode == "air", "swipe up: a leap (up at %.1f m/s)" % r.vy)
		swipes.top = r.y
	elif frames > 26 and frames < 60:
		swipes.top = maxf(float(swipes.top), r.y)
	elif frames == 60:
		check(r.grounded and float(swipes.top) - 14.0 > 1.6, "and down again (%.2f m up at the top)" % (float(swipes.top) - 14.0))
		_send(Vector2(0, 60))
	elif frames == 68:
		check(r.mode == "roll" and r._height() < 1.0, "swipe down: dive and roll, low (%.2f m)" % r._height())
	elif frames == 100:
		check(r.mode == "run", "and back to running")
		_send(Vector2(60, 0), false)
	elif frames == 101:
		check(r.lane == 1, "a swipe counts as the finger moves, before it lifts (lane %d)" % r.lane)
	elif frames == 103:
		_send(Vector2(60, 0))
	elif frames == 112:
		check(r.lane == 2 and absf(r.x - RoofTrack.LANES[2]) < 0.05 and r.mode != "dead", "two quick swipes right: two lanes over (lane %d, x %.2f)" % [r.lane, r.x])
		run.started = false
		run.queue_free()
		run = null
		stage = "menu"
		frames = 0
		print("== menu")

var menu_scene: Node
var buses := 0
func _menu_checks() -> void:
	frames += 1
	var f := frames % 100
	var round := frames / 100
	if frames == 1:
		menu_scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(menu_scene)
		current_scene = menu_scene
	elif f == 30:
		if round == 0:
			buses = AudioServer.bus_count
		RoofRun.start(self)
	elif f == 50:
		check(current_scene is RoofRun and not is_instance_valid(menu_scene), "ROOF RUN from the menu: the city goes, the run takes its place")
		(current_scene as RoofRun)._to_menu()
	elif f == 80:
		var back := current_scene != null and current_scene.name == "Main" and current_scene.get_child_count() > 0 and current_scene.get_child(0) is Game
		check(back, "MENU: back to the game")
		check(AudioServer.bus_count == buses, "and its sound buses are the ones it had (%d, at first %d)" % [AudioServer.bus_count, buses])
		menu_scene = current_scene
		if round >= 1:
			stage = ""
			print("DONE fails=%d" % fails)
			quit(1 if fails > 0 else 0)

## A swipe of the finger by v (a mouse drag, as a touch screen sends it): down, moved and (unless told not to) lifted.
func _send(v: Vector2, lift := true) -> void:
	var at := Vector2(400, 200)
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = at
	run._unhandled_input(d)
	var m := InputEventMouseMotion.new()
	m.position = at + v
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	run._unhandled_input(m)
	if lift:
		var u := InputEventMouseButton.new()
		u.button_index = MOUSE_BUTTON_LEFT
		u.pressed = false
		u.position = at + v
		run._unhandled_input(u)
