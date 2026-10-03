## Checks the new pieces one at a time: getting into a car and driving it, crashing into a wall,
## getting out, the T-Rex throwing the car you are in, the T-Rex ploughing through a parked car,
## escaping with her by car, flares, ringing her phone, day and night, and the T-Rex not seeing
## someone who stands still. Prints "ok"/"FAIL" per check and ends with "DONE fails=N".
##   godot --headless --path godot --fixed-fps 30 -s res://tests/drive_test.gd
extends SceneTree

var g: Game
var f := 0
var fails := 0
var stage := 0
var t := 0.0
var car: Dictionary
var mark := Vector2()
var mark2 := 0.0
var other: Dictionary
var walk_t := 0.0

func _initialize() -> void:
	# the same run every time (where she hides, the weather, how cars tumble)
	seed(20261003)
	root.add_child(load("res://scenes/main.tscn").instantiate())

func check(ok: bool, what: String) -> void:
	if ok:
		print("   ok   ", what)
	else:
		fails += 1
		print("   FAIL ", what)

func finish() -> void:
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)

## Keeps the T-Rex far away and calm, so a check isn't spoilt by it.
func park_rex() -> void:
	g.mon.pos = Vector3(110, 0, 110) if g.pl.pos.x < 0.0 else Vector3(-110, 0, -110)
	g.mon.set_state("PATROL")
	g.mon.pause_t = 999.0
	g.mon.awareness = 0.0
	g.mon.speed = 0.0
	g.dir.next_cross = 1e9
	g.dir.next_phantom = 1e9

func next(s := -1) -> void:
	stage = stage + 1 if s < 0 else s
	t = 0.0

## A parked car with open road ahead of it (so driving off it doesn't hit a wall at once).
func open_car() -> Dictionary:
	var best := {}
	var bd := -1.0
	for c in g.veh.cars:
		if c.state != "parked":
			continue
		var fw: Vector2 = g.veh.forward(c)
		var clear := 0.0
		while clear < 40.0:
			var p: Vector2 = c.pos + fw * (c.size.x * 0.5 + 1.5 + clear)
			if not g.col.walkable(p.x, p.y, 1.2):
				break
			clear += 1.0
		if clear > bd:
			bd = clear
			best = c
	return best

## Open road: a point with 16 m clear in some direction (and room around it).
func _open_spot() -> Dictionary:
	for n in g.nodes:
		for k in 8:
			var dir := Vector2.from_angle(TAU * k / 8.0)
			var p := Vector2(n.x, n.z) + Vector2(dir.y, -dir.x) * 3.0
			var ok := true
			for s in range(-2, 17):
				var q := p + dir * s
				if not g.col.walkable(q.x, q.y, 2.5) or not g.col.los_clear(p.x, p.y, q.x, q.y, 1.3):
					ok = false
					break
			if ok:
				return {p = p, dir = dir}
	return {p = Vector2(g.pl.pos.x, g.pl.pos.z), dir = Vector2(0, 1)}

## A point on open road 14 m from a building wall, facing it, with nothing in between.
func _facing_wall() -> Dictionary:
	for i in g.col.x0.size():
		if g.col.y1[i] < 8.0 or (g.col.x1[i] - g.col.x0[i]) < 10.0:
			continue
		for side in [-1.0, 1.0]:
			var z: float = (g.col.z0[i] - 15.0) if side < 0.0 else (g.col.z1[i] + 15.0)
			var x: float = (g.col.x0[i] + g.col.x1[i]) * 0.5
			var p := Vector2(x, z)
			var dir := Vector2(0, -side)
			var ok := true
			for k in range(0, 13):
				var q := p + dir * k
				if not g.col.walkable(q.x, q.y, 1.4):
					ok = false
					break
			if ok:
				return {p = p, dir = dir}
	return {}

func _process(dt: float) -> bool:
	f += 1
	t += dt
	if g == null:
		var m := root.get_child(root.get_child_count() - 1)
		if m.get_child_count():
			g = m.get_child(0) as Game
		return false
	if (stage > 0 and stage < 9) or stage >= 19:
		park_rex()
	var inp: Dictionary = g.hud.input
	match stage:
		0:
			if f < 10:
				return false
			g.start_game()
			car = open_car()
			check(car.size() > 0, "found a parked car with road ahead")
			var p: Vector2 = g.veh.exit_point(car)
			g.pl.pos = Vector3(p.x, 0.0, p.y)
			next()
		1:
			if t < 0.2:
				return false
			var act := g.find_interact()
			check(act.get("label", "") == "DRIVE", "DRIVE offered beside a car (got '%s')" % act.get("label", ""))
			g.do_interact()
			check(g.pl.driving and car.state == "driven", "USE gets in and drives")
			check(not g.col.box_on(car.box), "the car's box is out of the way while it is driven")
			mark = car.pos
			mark2 = car.yaw
			inp.jy = 1.0
			next()
		2:
			if t < 2.0:
				return false
			check(car.speed > 6.0, "the throttle gets it moving (%.1f m/s)" % car.speed)
			check((car.pos as Vector2).distance_to(mark) > 6.0, "it covered ground (%.1f m)" % (car.pos as Vector2).distance_to(mark))
			check(g.pl.pos.distance_to(Vector3(car.pos.x, g.pl.pos.y, car.pos.y)) < 0.1, "the player rides with it")
			mark2 = car.yaw
			inp.jx = 1.0
			next()
		3:
			if t < 0.8:
				return false
			check(U.ang_diff(mark2, car.yaw) < -0.1, "steering right turns it right (%.2f rad)" % U.ang_diff(mark2, car.yaw))
			inp.jx = 0.0
			# put it in front of a building wall with clear road between, and floor it
			var spot := _facing_wall()
			check(spot.size() > 0, "found a building wall to drive at")
			if spot.size():
				car.pos = spot.p
				car.yaw = atan2(-spot.dir.y, spot.dir.x)
			car.speed = 0.0
			inp.jy = 1.0
			next()
		4:
			# never inside a wall on the way
			if not g.col.walkable(car.pos.x, car.pos.y, 0.2):
				check(false, "the car stays out of the walls (at %s)" % car.pos)
				inp.jy = 0.0
				next()
				return false
			if t < 5.0:
				return false
			check(absf(car.speed) < 4.0, "a wall stops it (%.1f m/s)" % car.speed)
			check(true, "the car stays out of the walls")
			inp.jy = 0.0
			next()
		5:
			if t < 0.5:
				return false
			var act := g.find_interact()
			check(act.get("label", "") == "EXIT", "EXIT offered while driving (got '%s')" % act.get("label", ""))
			g.do_interact()
			check(not g.pl.driving and car.state == "parked", "USE gets out")
			check(g.col.walkable(g.pl.pos.x, g.pl.pos.z, 0.3), "out onto open ground")
			check(g.col.box_on(car.box), "the car is solid again where it was left")
			next()
		6:
			# the T-Rex bites the car you are in: a shove, then over it goes and you are thrown out
			g.enter_car(car)
			var fw: Vector2 = g.veh.forward(car)
			g.car_bitten(Vector2(-fw.y, fw.x))
			check(car.state == "driven" and car.hp == Vehicles.HP - 1, "the first bite only shoves it")
			g.car_bitten(Vector2(-fw.y, fw.x))
			check(car.state == "tumble", "the second bite throws it")
			next()
		7:
			if car.state == "tumble" and t < 4.0:
				return false
			check(car.state in ["wreck", "parked"], "it comes to rest (%s, roll %.2f)" % [car.state, car.roll])
			check(not g.pl.driving and g.pl.stun_t > 0.0, "the player is thrown out, dazed")
			check(g.col.box_on(car.box), "the wreck is solid where it landed")
			check(g.col.walkable(g.pl.pos.x, g.pl.pos.z, 0.25), "thrown out onto open ground")
			next()
		8:
			# escaping with her by car: she gets in, and driving up to the barricade wins
			g.phase = "escape"
			g.exit = g.data.exits[0]
			var c2 := open_car()
			var p: Vector2 = g.veh.exit_point(c2)
			g.pl.pos = Vector3(p.x, 0.0, p.y)
			g.child.pos = g.pl.pos + Vector3(1.0, 0, 0)
			g.child.state = "follow"
			g.enter_car(c2)
			check(g.child.state == "car", "she gets in when she is with you")
			c2.pos = Vector2(g.exit.x, g.exit.z) + Vector2(0, 4.0 if g.exit.z < 0 else -4.0)
			c2.speed = 0.0
			next()
		9:
			if g.phase == "escape" and t < 2.0:
				return false
			check(g.phase in ["won", "wonEnd"], "reaching the barricade with her in the car wins (phase %s)" % g.phase)
			next()
		10:
			if g.phase != "wonEnd" and t < 5.0:
				return false
			# a fresh run for the rest
			g.start_game()
			check(not g.pl.driving and g.veh.driven == null, "a new run starts on foot")
			check(car.state == "parked" and (car.pos as Vector2).distance_to(car.home) < 0.01, "the cars are back where they were")
			# the T-Rex charging through a parked car throws it aside
			other = open_car()
			var fw: Vector2 = g.veh.forward(other)
			var side := Vector2(-fw.y, fw.x)
			var from: Vector2 = other.pos + side * 9.0
			g.pl.pos = Vector3(other.pos.x - side.x * 14.0, 0, other.pos.y - side.y * 14.0)
			g.mon.pos = Vector3(from.x, 0, from.y)
			g.mon.yaw = atan2(-side.x, -side.y)
			g.mon.set_state("CHASE")
			g.mon.last_seen_t = g.time
			g.mon.speed = 6.0
			mark = other.pos
			next()
		11:
			g.mon.last_seen_t = g.time
			g.mon.last_known = g.pl.pos
			if other.state == "parked" and (other.pos as Vector2).distance_to(mark) < 0.5 and t < 4.0:
				return false
			check(other.state != "parked" or (other.pos as Vector2).distance_to(mark) > 0.5, "charging, it throws a parked car out of its way (%s)" % other.state)
			next()
		12:
			if other.state == "tumble" and t < 4.0:
				return false
			park_rex()
			if g.phase != "explore":
				g.start_game()
			park_rex()
			# flares: a throw lands, burns, and pulls the T-Rex over
			var before := g.flares
			var open := _open_spot()
			g.pl.pos = Vector3(open.p.x, 0.0, open.p.y)
			g.pl.cam_yaw = atan2(open.dir.x, open.dir.y)
			g.throw_flare()
			check(g.flares == before - 1 and g.flare_list.size() == 1, "a flare is thrown")
			next()
		13:
			park_rex()
			if t < 1.6:
				return false
			var fl: Dictionary = g.flare_list[0] if g.flare_list.size() else {}
			check(fl.get("landed", false), "it lands")
			check(fl.size() and Vector2(fl.x, fl.z).distance_to(Vector2(g.pl.pos.x, g.pl.pos.z)) > 4.0, "some way off")
			g.mon.pos = Vector3(fl.x + 30.0, 0, fl.z) if fl.size() else g.mon.pos
			g.mon.set_state("PATROL")
			g.mon.pause_t = 0.0
			g.mon.lure(fl.x, fl.z)
			check(g.mon.state == "INVESTIGATE" and g.mon.inv.distance_to(Vector2(fl.x, fl.z)) < 0.1, "the T-Rex goes to the light")
			park_rex()
			next()
		14:
			# her phone: it rings, the search area narrows, then it has to wait
			park_rex()
			check(g.phase == "explore", "still playing (phase %s)" % g.phase)
			g.call_t = 0.0
			mark2 = g.search.r
			g.call_phone()
			check(g.call_t > 0.0, "calling starts the wait before the next call")
			next()
		15:
			park_rex()
			if t < 2.2:
				return false
			check(g.search.r < mark2, "the ring narrows the search area (%.0f -> %.0f m)" % [mark2, g.search.r])
			var spot := Vector2(g.loc.spot[0], g.loc.spot[1])
			check(spot.distance_to(g.search.c) <= g.search.r + 0.01, "and she is still inside it")
			# day and night
			g.set_daylight(true)
			check(g.world.day == 1.0 and g.daylight, "daylight on")
			g.set_daylight(false)
			check(g.world.day == 0.0 and not g.daylight, "and back to night")
			next()
		16:
			# it sees movement: standing still 14 m in front of it, in the dark, with the torch off
			g.pl.flash = false
			var open := _open_spot()
			g.pl.pos = Vector3(open.p.x, 0.0, open.p.y)
			var rp: Vector2 = open.p + open.dir * 14.0
			g.mon.pos = Vector3(rp.x, 0, rp.y)
			g.mon.yaw = atan2(-open.dir.x, -open.dir.y)
			g.mon.set_state("PATROL")
			g.mon.pause_t = 999.0
			g.mon.awareness = 0.0
			g.mon.speed = 0.0
			mark = rp
			next()
		17:
			g.mon.pos = Vector3(mark.x, 0, mark.y)
			g.mon.pause_t = 999.0
			if t < 2.0:
				return false
			check(g.mon.awareness < 0.3, "it doesn't notice someone standing still (awareness %.2f)" % g.mon.awareness)
			next()
		18:
			# now walk about in front of it
			g.mon.pos = Vector3(mark.x, 0, mark.y)
			g.mon.pause_t = 999.0
			g.pl.cam_yaw = g.mon.yaw + PI * 0.5
			inp.jy = 0.6
			# (he speeds up gradually, so give it a few seconds)
			if g.mon.awareness <= 0.3 and g.mon.state == "PATROL" and t < 4.0:
				return false
			inp.jy = 0.0
			check(g.mon.awareness > 0.3 or g.mon.state != "PATROL", "it notices the same person moving (awareness %.2f, %s)" % [g.mon.awareness, g.mon.state])
			next()
		19:
			# the phone buttons: GAS, the arrows, BRAKE
			if g.phase != "explore":
				g.start_game()
			car = open_car()
			var p: Vector2 = g.veh.exit_point(car)
			g.pl.pos = Vector3(p.x, 0.0, p.y)
			g.enter_car(car)
			inp.gas = true
			next()
		20:
			if t < 1.5:
				return false
			check(car.speed > 4.0, "GAS drives it (%.1f m/s)" % car.speed)
			inp.gas = false
			mark2 = car.yaw
			inp.right = true
			next()
		21:
			if t < 0.6:
				return false
			check(U.ang_diff(mark2, car.yaw) < -0.05, "the right arrow turns it right (%.2f rad)" % U.ang_diff(mark2, car.yaw))
			inp.right = false
			mark2 = car.yaw
			inp.left = true
			next()
		22:
			if t < 0.6:
				return false
			check(U.ang_diff(mark2, car.yaw) > 0.05, "the left arrow turns it left (%.2f rad)" % U.ang_diff(mark2, car.yaw))
			inp.left = false
			inp.sprint = true
			next()
		23:
			if t < 2.5:
				return false
			check(car.speed < -0.5, "BRAKE stops it, then backs it up (%.1f m/s)" % car.speed)
			inp.sprint = false
			# drive it into the side of a parked car
			other = {}
			for o in g.veh.cars:
				if o.state == "parked" and o != car:
					var fw: Vector2 = g.veh.forward(o)
					var side := Vector2(-fw.y, fw.x)
					var from: Vector2 = o.pos + side * 7.5
					var ok := true
					for k in range(0, 5):
						var q := from - side * k
						if not g.col.walkable(q.x, q.y, 1.2):
							ok = false
					if ok:
						other = o
						car.pos = from
						car.yaw = atan2(side.y, -side.x)
						break
			check(other.size() > 0, "found a parked car to drive into")
			mark = other.pos
			car.speed = 13.0
			inp.gas = true
			next()
		24:
			if other.state == "parked" and t < 3.0:
				return false
			inp.gas = false
			check(other.state == "slide" or (other.pos as Vector2).distance_to(mark) > 0.3, "the car it hits is shoved (%s, moved %.1f m)" % [other.state, (other.pos as Vector2).distance_to(mark)])
			check(car.damage > 0.05, "the crash damages the car (%.2f)" % car.damage)
			var dented := false
			for role in car.meshes:
				for m in car.meshes[role]:
					if (m as Node).has_meta("orig_mesh"):
						dented = true
			check(dented, "and dents it")
			next()
		25:
			if other.state == "slide" and t < 6.0:
				return false
			check(other.state == "parked" and (other.pos as Vector2).distance_to(mark) > 0.5, "it slides to a stop somewhere else (%.1f m)" % (other.pos as Vector2).distance_to(mark))
			check(g.col.box_on(other.box), "solid where it stopped")
			# one more knock finishes the engine
			var spot := _facing_wall()
			car.pos = spot.p
			car.yaw = atan2(-spot.dir.y, spot.dir.x)
			car.damage = 0.95
			car.speed = 14.0
			inp.gas = true
			next()
		26:
			if t < 2.5:
				return false
			check(car.damage >= 1.0, "the crash finishes the engine (damage %.2f)" % car.damage)
			car.pos = _facing_wall().p
			car.speed = 0.0
			next()
		27:
			if t < 1.5:
				return false
			check(absf(car.speed) < 0.5, "a dead engine won't go (%.1f m/s)" % car.speed)
			inp.gas = false
			g.do_interact()
			check(not g.pl.driving and car.state == "wreck", "getting out leaves a wreck (%s)" % car.state)
			var near = g.veh.near_car(g.pl.pos.x, g.pl.pos.z)
			check(near == null or not is_same(near, car), "which can no longer be driven")
			g.start_game()
			var clean: bool = car.damage == 0.0
			for role in car.meshes:
				for m in car.meshes[role]:
					if (m as Node).has_meta("orig_mesh"):
						clean = false
			check(clean and car.state == "parked", "a new run mends it")
			finish()
	return false
