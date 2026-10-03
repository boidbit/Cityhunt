## The T-Rex: what it sees and hears, how it patrols, investigates, searches and chases, how it goes
## after cars and throws the parked ones out of its way. Ported from the browser version's
## monsterPerceive / monsterUpdate, changed for an animal this size:
## - it sees movement: someone standing still is only noticed close up (or in a torch beam)
## - it can't follow anyone into a doorway, an alley or the subway (its body is 4 m wide)
## - the ground shakes under its steps from far away, so you feel it coming before you see it
## - a burning flare draws it, even off a chase
class_name Monster
extends RefCounted

const BODY_R := 2.0         # its body, for walls and cars (the tail and head reach further)
const BITE := 3.1           # how far from its head it catches you
const STILL_SEE := 7.0      # it notices someone standing still only this close

var g: Game
var actor: Rex

var pos := Vector3()
var yaw := 0.0
var state := "PATROL"
var speed := 0.0
var path: Array[Vector2] = []
var awareness := 0.0
var last_known := Vector3()
var last_seen_t := -99.0
var search_t := 0.0
var phase2 := 0
var pause_t := 0.0
var stuck_t := 0.0
var prog := Vector3()
var hear_cd := 0.0
var cur := 0
var prev := -1
var roar_cd := 0.0
var vocal_t := 8.0
var sees := false
var crossing := false
var repath := 0.0
var attack_t := 0.0
var visible := false
var skip_t := 0.0
var inv := Vector2()
var stun_t := 0.0
var bite_cd := 0.0          # after biting a car it backs off a moment
var lure_t := 0.0           # sniffing round a flare
var step_d := 0.0           # ground covered since the last footfall
var roar_t := 0.0           # head up, roaring
var look_t := 0.0

func _init(p_g: Game) -> void:
	g = p_g
	actor = Rex.new()
	actor.name = "TRex"
	g.add_child(actor)

func setup_model() -> void:
	pass

func reset() -> void:
	var cand := []
	for i in g.nodes.size():
		var n: Dictionary = g.nodes[i]
		var d := U.hyp(n.x - g.pl.pos.x, n.z - g.pl.pos.z)
		if d > 95.0 and d < 160.0:
			cand.append(i)
	cur = cand[randi() % cand.size()] if cand.size() else 0
	prev = -1
	pos = Vector3(g.nodes[cur].x, 0.0, g.nodes[cur].z)
	yaw = randf() * TAU
	state = "PATROL"
	path.clear()
	awareness = 0.0
	speed = 0.0
	pause_t = 2.0
	last_seen_t = -99.0
	crossing = false
	roar_cd = 0.0
	vocal_t = 10.0
	attack_t = 0.0
	stun_t = 0.0
	bite_cd = 0.0
	lure_t = 0.0
	roar_t = 0.0
	actor.once = ""

## Where its jaws are (the bite reaches from here).
func head() -> Vector2:
	return Vector2(pos.x + sin(yaw) * 4.2, pos.z + cos(yaw) * 4.2)

func head_dist() -> float:
	var h := head()
	var d1 := Vector2(g.pl.pos.x, g.pl.pos.z).distance_to(h)
	return minf(d1, U.hyp(g.pl.pos.x - pos.x, g.pl.pos.z - pos.z) - 0.6)

# ---------------------------------------------------------------- movement
func goal(x: float, z: float) -> void:
	path.clear()
	repath = 0.6
	if g.col.path_clear(pos.x, pos.z, x, z, BODY_R * 0.6):
		path.append(Vector2(x, z))
		return
	var a := g.nearest_node(pos.x, pos.z, true)
	var b := g.nearest_node(x, z, true)
	for i in g.bfs(a, b):
		path.append(Vector2(g.nodes[i].x, g.nodes[i].z))
	path.append(Vector2(x, z))

## Walk along the path; true when it has run out.
func step_path(dt: float, spd: float, turn: float) -> bool:
	if path.is_empty():
		speed = lerpf(speed, 0.0, minf(1.0, dt * 3.0))
		return true
	if path.size() > 1:
		skip_t -= dt
		if skip_t <= 0.0:
			skip_t = 0.4
			if g.col.path_clear(pos.x, pos.z, path[1].x, path[1].y, BODY_R * 0.6):
				path.remove_at(0)
	var t := path[0]
	var dx := t.x - pos.x
	var dz := t.y - pos.z
	var d := U.hyp(dx, dz)
	if d < (3.0 if path.size() > 1 else 2.0):
		path.remove_at(0)
		if path.is_empty():
			return true
	var ad := U.ang_diff(yaw, atan2(dx, dz))
	yaw += clampf(ad, -turn * dt, turn * dt)
	var align := maxf(0.0, cos(ad))
	speed = lerpf(speed, spd * (0.2 + 0.8 * align), minf(1.0, dt * 1.6))
	pos.x += sin(yaw) * speed * dt
	pos.z += cos(yaw) * speed * dt
	# charging, it ploughs through parked cars instead of going round them
	if speed > 4.0 and g.veh:
		var front := Vector2(pos.x + sin(yaw) * 1.6, pos.z + cos(yaw) * 1.6)
		for c in g.veh.cars_hit(front, BODY_R + 0.4):
			var away: Vector2 = ((c.pos as Vector2) - Vector2(pos.x, pos.z)).normalized()
			var dir := (away + Vector2(sin(yaw), cos(yaw))).normalized()
			g.veh.knock(c, dir, clampf(speed / 9.0, 0.35, 1.0))
			speed *= 0.75
			g.pl.shake = maxf(g.pl.shake, 0.4)
	pos = g.col.collide(pos, BODY_R, 0.2, 5.0, true)
	pos.x = clampf(pos.x, -g.bound + 2.0, g.bound - 2.0)
	pos.z = clampf(pos.z, -g.bound + 2.0, g.bound - 2.0)
	stuck_t += dt
	if stuck_t > 1.4:
		var moved := U.hyp(pos.x - prog.x, pos.z - prog.z)
		prog = pos
		stuck_t = 0.0
		if moved < 0.7 and spd > 0.5:
			# wedged between parked cars in a narrow street: it shoulders them aside
			var front := Vector2(pos.x + sin(yaw) * 1.6, pos.z + cos(yaw) * 1.6)
			var shoved := false
			if g.veh:
				for c in g.veh.cars_hit(front, BODY_R + 0.6):
					var away: Vector2 = ((c.pos as Vector2) - Vector2(pos.x, pos.z)).normalized()
					g.veh.knock(c, away, 0.2)
					shoved = true
			if not shoved:
				path.remove_at(0)
				if path.is_empty():
					return true
	return false

func set_state(s: String) -> void:
	state = s
	path.clear()
	pause_t = 0.0
	phase2 = 0

func patrol_next() -> void:
	var nb: Array = g.nodes[cur].n.filter(func(v): return v != prev)
	var list: Array = nb if nb.size() else g.nodes[cur].n
	var next: int = list[randi() % list.size()]
	var bias := 0.0
	if g.phase == "escape":
		bias = 0.5
	elif g.dir.far_t > 55.0:
		bias = 0.65
	elif g.dir.near_t > 40.0:
		bias = -0.6
	if bias != 0.0 and randf() < absf(bias):
		var best := INF
		for v in list:
			var sc := U.hyp(g.nodes[v].x - g.pl.pos.x, g.nodes[v].z - g.pl.pos.z) * (1.0 if bias > 0.0 else -1.0)
			if sc < best:
				best = sc
				next = v
	prev = cur
	cur = next
	path = [Vector2(g.nodes[next].x + U.rnd(-1.5, 1.5), g.nodes[next].z + U.rnd(-1.5, 1.5))]

## A noise at (x,z) draws it over.
func hear(x: float, z: float) -> void:
	if state == "CHASE" or state == "ATTACK" or state == "STUN":
		return
	if crossing:
		crossing = false
		g.dir.crossing = {}
	inv = Vector2(x, z)
	if state != "INVESTIGATE":
		set_state("INVESTIGATE")
		if randf() < 0.5:
			vocal(0.5)
	goal(x, z)

## A flare landed at (x,z): the light pulls it over, even off a chase if it's close enough.
func lure(x: float, z: float) -> void:
	var d := U.hyp(x - pos.x, z - pos.z)
	if state == "ATTACK" or state == "STUN" or d > 95.0:
		return
	if state == "CHASE":
		if d > 30.0:
			return
		awareness = 0.6
	crossing = false
	g.dir.crossing = {}
	inv = Vector2(x, z)
	set_state("INVESTIGATE")
	lure_t = 9.0
	goal(x, z)

func start_chase() -> void:
	if state == "CHASE" or state == "STUN":
		return
	g.buzz(70)
	set_state("CHASE")
	awareness = 1.0
	crossing = false
	g.dir.crossing = {}
	if roar_cd <= 0.0:
		var pp := g.pos_params(pos.x, 3.0, pos.z, 40.0)
		g.sfx.play("roar", maxf(0.35, pp.vol * 1.3), pp.pan, maxf(pp.lp, 1500.0), 1)
		roar_cd = 14.0
		roar_t = 1.1
	g.sfx.play("stinger", 0.3)

## Hit by a car going fast: it staggers for a moment.
func rammed(hit: float) -> void:
	if state == "ATTACK":
		return
	set_state("STUN")
	stun_t = clampf(hit / 8.0, 1.2, 3.2)
	speed = 0.0
	var pp := g.pos_params(pos.x, 3.0, pos.z, 40.0)
	g.sfx.play("roar", maxf(0.3, pp.vol), pp.pan, pp.lp, 2)
	roar_t = 0.8

func vocal(v: float) -> void:
	var pp := g.pos_params(pos.x, 3.5, pos.z, 30.0)
	if randf() < 0.5:
		g.sfx.play("clicks", pp.vol * v, pp.pan, pp.lp, -1, 0.7)
	else:
		g.sfx.play("growl", pp.vol * v * 0.9, pp.pan, pp.lp, -1, 0.75)

# ---------------------------------------------------------------- senses
func perceive(dt: float) -> void:
	sees = false
	if g.phase != "explore" and g.phase != "escape":
		return
	var P := g.pl
	var dx := P.pos.x - pos.x
	var dz := P.pos.z - pos.z
	var d := U.hyp(dx, dz)
	var esc := g.phase == "escape"
	if P.pos.y < -2.0:
		return
	var facing := absf(U.ang_diff(yaw, atan2(dx, dz)))
	var rng := 24.0
	if P.driving:
		rng = 60.0 if P.car_lights else 34.0
	elif P.flash:
		rng = 46.0
	if P.lit:
		rng *= 1.3
	if g.daylight:
		rng *= 1.45
	if P.crouch and not P.driving:
		rng *= 0.62
	if esc:
		rng *= 1.12
	# it sees what moves: standing still, you are part of the street unless it is right on you
	if P.move == "still" and not P.driving:
		rng = minf(rng, STILL_SEE)
	var mm := 0.55 if P.move == "still" else 0.6 if P.move == "crouch" else 1.0 if P.move == "walk" else 1.45 if P.move == "run" else 1.9
	var h := 0.7 if P.crouch else 1.3
	var s := not P.hidden and d < rng and (facing < 1.25 or d < 9.0) and g.col.los_clear(pos.x, pos.z, P.pos.x, P.pos.z, h)
	if not s and P.flash and not P.driving and not P.hidden and d < 30.0:
		var bx := sin(P.cam_yaw)
		var bz := cos(P.cam_yaw)
		if (bx * -dx + bz * -dz) / d > 0.82 and g.col.los_clear(pos.x, pos.z, P.pos.x, P.pos.z, 1.5):
			s = true
	if P.hidden and P.compromised and d < 18.0:
		s = true
	if P.hidden and not P.compromised and d < 1.6 + BODY_R and state == "SEARCH":
		s = true
	sees = s
	if s:
		var gain := (1.8 * (1.0 - d / maxf(rng, 1.0)) + 0.35) * mm
		if state == "SEARCH" or state == "INVESTIGATE":
			gain *= 1.7
		if crossing and d > 18.0:
			gain *= 0.3
		awareness = minf(1.2, awareness + gain * dt)
		last_known = P.pos
		last_seen_t = g.time
		if awareness >= 1.0:
			start_chase()
		elif awareness > 0.4 and state == "PATROL":
			hear(P.pos.x, P.pos.z)
	elif state != "CHASE":
		awareness = maxf(0.0, awareness - dt * 0.09)
	# hearing
	hear_cd -= dt
	if P.noise > 0.0 and state != "CHASE":
		var r := P.noise * (1.3 if esc else 1.0) * (1.25 - 0.5 * g.wx_i)
		if not g.col.los_clear(pos.x, pos.z, P.pos.x, P.pos.z, 2.0):
			r *= 0.55
		if d < r:
			if d < r * 0.3:
				awareness += 0.7 * dt
			if awareness >= 1.0:
				last_known = P.pos
				last_seen_t = g.time
				start_chase()
			elif hear_cd <= 0.0:
				hear_cd = 1.4
				var e := d * 0.18
				hear(P.pos.x + U.rnd(-e, e), P.pos.z + U.rnd(-e, e))

# ---------------------------------------------------------------- behaviour
func update(dt: float) -> void:
	roar_cd -= dt
	bite_cd -= dt
	roar_t -= dt
	if g.phase == "explore" or g.phase == "escape":
		perceive(dt)
	var P := g.pl
	var esc := g.phase == "escape"
	var dP := U.hyp(P.pos.x - pos.x, P.pos.z - pos.z)
	match state:
		"PATROL":
			var spd := 2.0 if crossing else (2.9 if esc else 2.4)
			if pause_t > 0.0:
				pause_t -= dt
				speed = lerpf(speed, 0.0, dt * 3.0)
			elif path.is_empty() or step_path(dt, spd, 1.6):
				if crossing and path.is_empty():
					crossing = false
					g.dir.crossing = {}
				if path.is_empty():
					if not crossing and randf() < 0.18:
						pause_t = U.rnd(1.5, 4.0)
						if randf() < 0.5:
							vocal(0.4)
					patrol_next()
		"INVESTIGATE":
			var spd := 4.4 if esc else 3.8
			if phase2 == 0:
				if step_path(dt, spd, 2.0):
					phase2 = 1
					pause_t = maxf(U.rnd(2.0, 3.2), lure_t)
			else:
				speed = lerpf(speed, 0.0, dt * 3.0)
				pause_t -= dt
				lure_t -= dt
				if pause_t <= 0.0:
					set_state("SEARCH")
					search_t = 12.0 if esc else 9.0
					last_known = Vector3(inv.x, 0.0, inv.y)
					phase2 = 1
		"SEARCH":
			search_t -= dt
			if phase2 == 0:
				if step_path(dt, 4.4, 2.2):
					phase2 = 1
					pause_t = 1.4
			elif pause_t > 0.0:
				pause_t -= dt
				speed = lerpf(speed, 0.0, dt * 3.0)
				if pause_t <= 0.0:
					for k in 12:
						var x := last_known.x + U.rnd(-18.0, 18.0)
						var z := last_known.z + U.rnd(-18.0, 18.0)
						if g.col.walkable(x, z, BODY_R):
							goal(x, z)
							break
					if path.is_empty():
						goal(last_known.x + U.rnd(-4.0, 4.0), last_known.z + U.rnd(-4.0, 4.0))
			elif step_path(dt, 3.0, 2.0):
				pause_t = U.rnd(1.2, 2.6)
				if randf() < 0.4:
					vocal(0.5)
			if search_t <= 0.0:
				awareness *= 0.3
				set_state("PATROL")
				cur = g.nearest_node(pos.x, pos.z, true)
				prev = -1
				path = [Vector2(g.nodes[cur].x, g.nodes[cur].z)]
		"CHASE":
			var under := P.pos.y < -2.0
			var tracking := not under and (g.time - last_seen_t < 1.8 or sees)
			if tracking:
				last_known = P.pos
				repath -= dt
				if g.col.path_clear(pos.x, pos.z, P.pos.x, P.pos.z, BODY_R * 0.6):
					path = [Vector2(P.pos.x, P.pos.z)]
				elif repath <= 0.0 or path.is_empty():
					goal(P.pos.x, P.pos.z)
				# a car can outrun it on a straight; on foot it is just faster than you can keep up
				var spd := 11.0 if P.driving else (6.6 if esc else 6.3)
				if bite_cd > 0.0 or roar_t > 0.0:
					spd *= 0.25
				step_path(dt, spd, 2.6)
				if dP > 70.0:
					last_seen_t = -99.0
			else:
				if under:
					last_known = Vector3(16.0, 0.0, 12.5)
				set_state("SEARCH")
				search_t = 22.0 if esc else 17.0
				goal(last_known.x, last_known.z)
				phase2 = 0
				vocal(0.7)
		"STUN":
			stun_t -= dt
			speed = lerpf(speed, 0.0, dt * 4.0)
			if stun_t <= 0.0:
				set_state("SEARCH")
				search_t = 10.0
				last_known = P.pos
				goal(P.pos.x, P.pos.z)
				awareness = 0.9
		"ATTACK":
			attack_t += dt
			var want := atan2(P.pos.x - pos.x, P.pos.z - pos.z)
			yaw += U.ang_diff(yaw, want) * minf(1.0, dt * 6.0)
			speed = lerpf(speed, 2.5 if attack_t < 0.4 else 0.0, dt * 5.0)
			if dP > BITE:
				pos.x += sin(yaw) * speed * dt
				pos.z += cos(yaw) * speed * dt
	_finish(dt)

func _finish(dt: float) -> void:
	var P := g.pl
	if (g.phase == "explore" or g.phase == "escape" or g.phase == "dialog") and P.pos.y > -1.5 and state != "STUN":
		var dh := head_dist()
		if P.driving:
			# it bites the car: first a shove, then over it goes
			if dh < BITE + 1.2 and state == "CHASE" and bite_cd <= 0.0 and roar_t <= 0.0:
				bite_cd = 2.4
				actor.play_once("attack", 1.3)
				var dir := Vector2(P.pos.x - pos.x, P.pos.z - pos.z).normalized()
				g.car_bitten(dir)
		elif dh < BITE and (not P.hidden or P.compromised) and (state in ["CHASE", "SEARCH", "INVESTIGATE"] or dh < BITE * 0.7):
			g.lose()
	animate(dt)

# ---------------------------------------------------------------- animation
func animate(dt: float) -> void:
	actor.position = Vector3(pos.x, g.world.ground_at(pos.x, pos.z, 0.0), pos.z)
	actor.rotation.y = yaw
	if state == "ATTACK":
		if actor.once != "attack" and attack_t < 0.2:
			actor.play_once("attack", 1.1)
	elif state == "STUN":
		actor.loco(0.0)
	else:
		actor.loco(speed)
	# head: scanning while it searches or stands, down to sniff at the end of an investigation, up to roar
	var scan := (state == "SEARCH" or state == "INVESTIGATE" or pause_t > 0.0) and speed < 0.8
	look_t += dt
	actor.look = lerpf(actor.look, sin(look_t * 0.9) * 0.6 if scan else (sin(look_t * 9.0) * 0.25 if state == "STUN" else 0.0), minf(1.0, dt * 2.0))
	actor.sniff = lerpf(actor.sniff, 1.0 if scan and (lure_t > 0.0 or state == "INVESTIGATE") else 0.0, minf(1.0, dt * 1.5))
	actor.roar = lerpf(actor.roar, 1.0 if roar_t > 0.0 else 0.0, minf(1.0, dt * 6.0))
	# eyes catching the light: brighter facing the camera, fading with distance, not by day
	var cp := g.cam.global_position
	var ex := cp.x - pos.x
	var ez := cp.z - pos.z
	var face := cos(U.ang_diff(yaw + actor.look, atan2(ex, ez)))
	actor.set_eyes(clampf((face - 0.1) * 1.4, 0.0, 1.0) * clampf(1.0 - (U.hyp(ex, ez) - 12.0) / 80.0, 0.0, 1.0) * (1.0 if state == "CHASE" else 0.75) * (1.0 - g.world.day))
	# footfalls: one every stride
	step_d += speed * dt
	var stride := 3.4 if speed > 5.0 else 2.6
	if speed > 0.4 and step_d > stride:
		step_d = 0.0
		footstep()

func footstep() -> void:
	var wx := pos.x + sin(yaw) * 0.5
	var wz := pos.z + cos(yaw) * 0.5
	var chase := state == "CHASE"
	var pp := g.pos_params(wx, 0.0, wz, 48.0 if chase else 38.0)
	var v: float = pp.vol * (1.5 if chase else 1.15) * (0.6 if g.phase == "menu" else 1.0)
	if v >= 0.004:
		g.sfx.play("thud", minf(v, 1.0), pp.pan, minf(pp.lp, 900.0), -1, 0.7)
	# the ground shakes: felt from far further away than it can see
	if pp.d < 45.0 and g.phase != "menu":
		var k: float = 1.0 - pp.d / 45.0
		g.pl.shake = maxf(g.pl.shake, k * k * 0.55)
		g.tremor = maxf(g.tremor, k)
		if pp.d < 26.0:
			g.buzz(int(18 + 50 * k))
