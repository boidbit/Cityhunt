## Movement test for the player's body (scripts/man.gd): drives him through walking, running,
## sprinting, stopping, turning round and crouching, and measures what a person would notice:
## - planted feet: how fast a foot on the ground slides while he walks, runs, sprints and sneaks
## - speed builds up and dies down over time instead of jumping
## - stopping from a run takes a few steps, turning while running takes a curve
## Prints "ok"/"FAIL" per check and ends with "DONE fails=N" (exit code 1 if anything failed).
##   godot --headless --path godot --fixed-fps 30 -s res://tests/man_test.gd
extends SceneTree

var man: Man
var pos := Vector3()
var t := 0.0
var fails := 0
var feet := {}            # bone -> [previous point, lowest height seen]
var slip := {}            # label -> [sum of slide speed, frames]
var label := ""
var last := {}
const HZ := 60.0

func _initialize() -> void:
	man = Man.new()
	root.add_child(man)

func check(ok: bool, what: String) -> void:
	print("   %s   %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1

## One frame of input: heading (degrees, world), speed wanted, crouching.
func frame(heading: float, want: float, crouch := false) -> Vector3:
	var dt := 1.0 / HZ
	var a := deg_to_rad(heading)
	var step := man.move(dt, Vector2(sin(a), cos(a)) if want > 0.0 else Vector2(), want, crouch)
	pos += step
	man.real_speed = step.length() / dt
	man.position = pos
	man.rotation.y = man.yaw
	man.animate(dt)
	t += dt
	_feet(dt)
	return step

## A foot flat on the ground (heel and toe both down, this frame and the last) should stay put: this
## measures how fast its ankle moves meanwhile.
func _feet(dt: float) -> void:
	var worst := -1.0
	for side in ["L", "R"]:
		var pts := [man.bone_pos("Bip01 %s Foot" % side), man.bone_pos("Bip01 %s Toe0" % side)]
		var prev: Array = feet.get(side, [])
		feet[side] = pts
		if prev.is_empty() or label == "":
			continue
		var down := true
		var v := 0.0
		for i in 2:
			var p: Vector3 = pts[i]
			var q: Vector3 = prev[i]
			var floor_h := 0.125 if i == 0 else 0.02
			down = down and p.y < floor_h and q.y < floor_h
			if i == 0:
				v = Vector2(p.x - q.x, p.z - q.z).length() / dt
		if down:
			worst = maxf(worst, v)
	if label != "" and worst >= 0.0:
		var s: Array = slip.get(label, [0.0, 0, 0.0])
		s[0] += worst
		s[1] += 1
		s[2] = maxf(s[2], maxf(man.hold_gap[0], man.hold_gap[1]))
		slip[label] = s

## How low his feet are: the lowest of either foot's ankle and ball over their heights standing at rest, and
## per foot [that height, the point that is lowest, [ankle, ball]].
func _feet_low() -> Array:
	var lo := INF
	var per := []
	for side in ["L", "R"]:
		var a := man.bone_pos("Bip01 %s Foot" % side)
		var b := man.bone_pos("Bip01 %s Toe0" % side)
		var ha := a.y - 0.102
		var hb := b.y - 0.002
		per.append([minf(ha, hb), a if ha < hb else b, [a, b]])
		lo = minf(lo, minf(ha, hb))
	return [lo, per]

func run_for(secs: float, heading: float, want: float, crouch := false) -> void:
	var n := int(secs * HZ)
	for i in n:
		frame(heading, want, crouch)

func steady(name: String, secs: float, heading: float, want: float, crouch := false) -> void:
	run_for(1.5, heading, want, crouch)
	label = name
	run_for(secs, heading, want, crouch)
	label = ""

func _process(_d: float) -> bool:
	man.reset(0.0)
	run_for(1.0, 0.0, 0.0)
	check(man.state == Man.IDLE, "stands still with no input")
	# speeding up from standing
	var t0 := t
	var reached := -1.0
	while t - t0 < 4.0:
		frame(0.0, 4.4)
		if reached < 0.0 and man.speed >= 4.2:
			reached = t - t0
	check(reached > 1.0 and reached < 3.2, "takes time to reach running speed (%.2f s to 4.2 m/s)" % reached)
	steady("run", 3.0, 0.0, 4.4)
	t0 = t
	reached = -1.0
	while t - t0 < 4.0:
		frame(0.0, 7.0)
		if reached < 0.0 and man.speed >= 6.8:
			reached = t - t0
	check(reached > 0.6 and reached < 3.0, "run to sprint builds up (%.2f s)" % reached)
	steady("sprint", 3.0, 0.0, 7.0)
	# stopping from a sprint
	var p0 := pos
	t0 = t
	var stop_t := -1.0
	while t - t0 < 5.0:
		frame(0.0, 0.0)
		if stop_t < 0.0 and man.state == Man.IDLE:
			stop_t = t - t0
	var sd := Vector2(pos.x - p0.x, pos.z - p0.z).length()
	check(sd > 3.0 and sd < 9.0, "stopping from a sprint takes a few strides (%.1f m, %.2f s)" % [sd, stop_t])
	check(man.state == Man.IDLE and stop_t > 0.8, "and ends standing")
	# walking
	steady("walk", 3.0, 0.0, 1.5)
	p0 = pos
	run_for(3.0, 0.0, 0.0)
	sd = Vector2(pos.x - p0.x, pos.z - p0.z).length()
	check(sd > 0.4 and sd < 2.5, "stopping from a walk takes a step or two (%.1f m)" % sd)
	# turning round from standing: the turn is stepped, not snapped
	var y0 := man.yaw
	var max_rate := 0.0
	t0 = t
	var faced := -1.0
	while t - t0 < 3.0:
		var y := man.yaw
		frame(180.0, 1.5)
		max_rate = maxf(max_rate, absf(angle_difference(y, man.yaw)) * HZ)
		if faced < 0.0 and absf(angle_difference(man.yaw, PI)) < deg_to_rad(12.0):
			faced = t - t0
	check(faced > 0.5 and faced < 2.5, "turning round from standing steps round (%.2f s)" % faced)
	check(max_rate < 9.0, "never snaps round (fastest %.0f deg/s)" % rad_to_deg(max_rate))
	# a U-turn while running is a curve
	steady("run", 1.0, 180.0, 4.4)
	var start := pos
	max_rate = 0.0
	var far := 0.0
	t0 = t
	faced = -1.0
	while t - t0 < 4.0:
		var y := man.yaw
		frame(0.0, 4.4)
		max_rate = maxf(max_rate, absf(angle_difference(y, man.yaw)) * HZ)
		far = maxf(far, start.z - pos.z)
		if faced < 0.0 and absf(angle_difference(man.yaw, 0.0)) < deg_to_rad(12.0):
			faced = t - t0
	check(faced > 0.4 and faced < 2.5, "a U-turn while running takes a moment (%.2f s)" % faced)
	check(far > 0.4, "and he carries on a little before turning (%.1f m)" % far)
	check(max_rate < 6.0, "turns at most %.0f deg/s while running" % rad_to_deg(max_rate))
	run_for(3.0, 0.0, 0.0)
	# crouching
	run_for(3.0, 0.0, 0.0, true)
	check(man.state == Man.CROUCH, "crouches down")
	steady("crouch walk", 3.0, 0.0, 1.2, true)
	run_for(2.0, 0.0, 0.0, true)
	run_for(3.5, 0.0, 0.0, false)
	check(man.state == Man.IDLE, "stands up again")
	# a leap from a run (the motion-captured gap_jump): off one foot, both feet up, down on both, running on
	run_for(3.0, 0.0, 3.07)
	var run_low := INF
	for i in int(HZ):
		frame(0.0, 3.07)
		run_low = minf(run_low, _feet_low()[0])
	var entry := man.jump()
	check(man.state == Man.JUMP and entry < 0.4, "leaps from a run (joins the clip's run-up at %.2f s)" % entry)
	var jm: Dictionary = man.meta.gap_jump
	var up_t := 0.0
	var clear := 0.0
	var lowest := INF
	var low_at := 0.0
	var slide := [0.0, 0]
	var last_pt := [[], []]
	var leap_t0 := t
	while man.state == Man.JUMP and t - leap_t0 < 3.0:
		frame(0.0, 3.07)
		var fl := _feet_low()
		if fl[0] < lowest:
			lowest = fl[0]
			low_at = man.ct
		clear = maxf(clear, fl[0])
		if fl[0] > 0.05:
			up_t += 1.0 / HZ
		# after landing, a foot on the ground (heel or ball down: he lands on the balls of his feet) should
		# not slide: as it rolls one of the two stays put, so the slower of them
		for i in 2:
			var low: Array = fl[1][i]
			var pts: Array = low[2]
			if man.ct > float(jm.land) and low[0] < 0.012 and not (last_pt[i] as Array).is_empty():
				var va := Vector2(pts[0].x - last_pt[i][0].x, pts[0].z - last_pt[i][0].z).length()
				var vb := Vector2(pts[1].x - last_pt[i][1].x, pts[1].z - last_pt[i][1].z).length()
				slide[0] += minf(va, vb) * HZ
				slide[1] += 1
			last_pt[i] = pts if low[0] < 0.012 else []
	check(up_t > 0.35 and up_t < 0.9, "both feet leave the ground for %.2f s" % up_t)
	check(clear > 0.3, "and clear it by %.2f m at the top" % clear)
	check(lowest > run_low - 0.015, "no foot goes further into the ground than in the run (%.3f m at %.2f s in the clip; the run %.3f m)" % [lowest, low_at, run_low])
	var sv: float = slide[0] / maxf(slide[1], 1)
	check(sv < 0.15 and slide[1] > 15, "he lands on his feet: a foot on the ground slides %.2f m/s on average (%d frames)" % [sv, slide[1]])
	check(man.state == Man.MOVE and man.speed > 2.0, "lands and runs on (%.1f m/s)" % man.speed)
	# flat out: straight into the air off the right foot (the mirrored leap), cut short once down
	run_for(3.5, 0.0, 6.0)
	var rm: Dictionary = man.meta.gap_jump_r
	check(rm.push == "R", "the mirrored leap pushes off the right foot")
	man.jump("gap_jump_r", float(rm.takeoff), 0.12)
	var on := false
	var cut_t := t
	while t - cut_t < 3.0 and not on:
		frame(0.0, 6.0)
		if man.ct >= float(rm.land) + 0.3:
			on = man.run_on()
	check(on and man.state == Man.MOVE, "a leap from a sprint can be cut short once he is down (at %.2f s in the clip)" % man.ct)
	run_for(1.5, 0.0, 6.0)
	check(man.speed > 4.5, "and he is back up to speed (%.1f m/s)" % man.speed)
	run_for(2.0, 0.0, 0.0)
	# the feet
	# held by the leg IK: the slide left is ~0; how far the clip itself drifted shows the gait
	# matches the ground speed (the IK only takes up a few centimetres)
	var limits := {"walk": 0.15, "run": 0.3, "sprint": 0.5, "crouch walk": 0.15}
	var drift := {"walk": 0.04, "run": 0.08, "sprint": 0.12, "crouch walk": 0.05}
	var doing := {"walk": "walking", "run": "running", "sprint": "sprinting", "crouch walk": "sneaking"}
	for k in limits:
		var s: Array = slip.get(k, [0.0, 1, 0.0])
		var v: float = s[0] / maxf(s[1], 1)
		check(v < limits[k] and s[1] > 15, "feet stay planted while %s: a foot on the ground slides %.2f m/s on average (%d frames on the ground)" % [doing[k], v, s[1]])
		check(s[2] < drift[k], "  the leg holds it at most %.1f cm from where the clip would put it" % (s[2] * 100.0))
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
	return false
