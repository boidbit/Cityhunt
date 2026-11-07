## superrun, for the Shorts director (tests/short.gd): he crosses the city over its roofs the way a superhero
## would, and drops off the last one to the street.
## The city's roofs differ by 5-60 m from one building to the next: for a man running across them that is a
## wall every few metres, for him it is the course. From roof to roof (up to 22 m apart, any way round):
## - hop: a near roof about as high: the captured running leap, real gravity, out of his sprint;
## - mega: a roof 1.5-25 m higher, or one across a street: he pulls up, sinks into a crouch and blasts off (the
##   roof cracks), front-flips at the top of the arc and lands on it;
## - drop: a roof 4 m or more lower, or at the end the street: he dives off at full tilt, flips on the way down
##   and comes down in a superhero landing (one knee, one fist), cracking whatever he lands on, then is up and off.
## Gravity on the super moves is twice the real one, so a 20 m leap is a blast, not a float. Slow motion is kept
## for two moments only: the flip at the top of the biggest leap, and the last landing, in the street.
## The route (picked by the seed): a search of the roofs for 3-5 moves, every kind of move in it if it can be,
## going on the same way more or less, a run-up on every roof, ending on a roof high enough to drop to the street.
## superchase (chase = true): the same over 2-3 moves without the flips, the camera behind him; then the street,
## where every car comes for him (see _street_begin), and an outcome: pass, fall or car.
extends RefCounted

const GS := 19.62            # gravity of the super moves (m/s2)
const SPRINT := 5.9
const HOP_GAP := 3.6         # a hop: at most this far ...
const HOP_UP := 1.2          # ... this much higher ...
const HOP_DOWN := 4.0        # ... or this much lower
const REACH := 22.0          # the furthest leap (m, edge to edge)
const RISE := 25.0           # the highest leap up
const CLEAR := 3.0           # how far above the higher roof the top of a mega leap is
const APEX_CT := 0.79        # the leap clip's tightest tuck (s)
const MAN_LAYER := 1 << 9    # the render layer he is drawn on (the cracks are not painted on him)

var d                        # the director
var g: Game
var man: Man
var fx
var route: Array = []        # moves: kind, a, b (roof boxes; b null for the street), h_from, h_to, take, land, u, gap
var start := Vector2()
var mi := 0                  # the move he is on
var mode := ""               # run, crouch, air, land, hero, end
var tmr := 0.0               # game seconds in this mode
var seg := {}                # the stretch of roof he is running: a, dir, len, h
var s := 0.0
var off := Vector3()
var fl := {}                 # the flight
var toe := [0.0, 0.0]
var steps := 0
var shake := 0.0
var hero_w := 0.0            # how far into the superhero landing pose he is (0..1)
var hero_fade := 0.0         # per second, going out of it
var cam_move := -1
var slow_n := 0
var slowed := false
var crack: ImageTexture
var done := false
# superchase: the same roofs (no flips, the camera behind him), then the street with the cars after him
var chase := false
var outcome := "pass"        # pass; fall (comes up short of a roof and falls); car (a car gets him in the street)
var fail_mi := -1            # the leap he comes up short on (outcome fall)
var st := {}                 # the street: where he lands, which way it runs, how far it is clear
var st_t := 0.0              # game seconds into the street
var st_s := 0.0              # how far along it he is
var st_off := 0.0            # how far to the side of its line
var cars_on: Array = []      # the cars after him (see _street_begin)
var kick_cam := {}
var want_len := 0.0          # seconds of video wanted (0: as long as it takes): how many roofs, how many cars
var all_stunts := false     # every street stunt in the one video (in the seed's order), not just a few
var relax := false
# the game's Superhero Run (play): every stunt waits for the player's swipe or tap; too late and it goes wrong
var play := false
var lives := 3
var score := 0
var rage := 0.0              # 0..1: filled by stunts done in time; full, he may crush the last car
var ask := {}                # the prompt: g (up, down, side, tap), ok, t0, t1 (video seconds)
var flash := ""
var flash_until := 0.0
var perfect_until := -1.0
const GESTURE := {"step": "side", "crash2": "side", "dive": "down", "hide": "down", "vault": "up", "roofstep": "up", "kick": "tap"}           # no route with all the street it wants: take one with less

func _init(p_d) -> void:
	d = p_d
	g = d.g
	fx = d.fx

# ---------------------------------------------------------------- the route
func setup() -> bool:
	man = Man.new()
	g.add_child(man)
	d.man = man
	for mi_ in man.model.find_children("*", "MeshInstance3D", true, false):
		(mi_ as MeshInstance3D).layers = MAN_LAYER
	var roofs: Array = []
	for c in g.world.col:
		if float(c[2]) == 0.0 and float(c[3]) >= 12.0 and int(c[6]) == 3:
			roofs.append(c)
	if not _plan(roofs):
		relax = true
		if not chase or not _plan(roofs):
			return false
	# the roofs on the route cleared (they are run over), every roof dressed
	var edits := []
	for m in route:
		for r in [m.a, m.b]:
			if r != null:
				edits.append([r, float(r[3]), float(r[3])])
	d._set_roofs(edits)
	d.dress_roofs(d.roof_tris(), roofs)
	crack = _crack_texture()
	_toe_offs()
	var m0: Dictionary = route[0]
	_segment(start, m0.take, float(m0.h_from))
	man.reset(atan2(seg.dir.x, seg.dir.y))
	man.state = Man.MOVE
	man.speed = SPRINT
	man.real_speed = SPRINT
	man.position = Vector3(start.x, float(m0.h_from), start.y)
	man.rotation.y = man.yaw
	mode = "run"
	# the two moments in slow motion: the biggest leap up's flip, the last landing
	var big := -1
	for i in route.size():
		var m: Dictionary = route[i]
		m.slow = false
		if m.kind == "mega" and (big < 0 or float(m.h_to) - float(m.h_from) > float(route[big].h_to) - float(route[big].h_from)):
			big = i
	if big >= 0:
		route[big].slow = true
	route[-1].slow = true
	if chase:
		for i in route.size():
			route[i].slow = false
			if route[i].kind == "mega":
				fail_mi = i
	var desc := []
	for m in route:
		desc.append("%s %+.0f m%s" % [m.kind, float(m.h_to) - float(m.h_from), " over %.0f m" % m.gap if float(m.gap) > 6.0 else ""])
	print("superrun: %d moves: %s" % [route.size(), ", ".join(desc)])
	return true

## Where he leaves one roof for another: the nearest points of the two (they are boxes), the takeoff a little in
## from the edge, the landing a few metres into the next; and what kind of move it is. {} if out of reach.
func _move(a: Array, b: Array) -> Dictionary:
	var pa := Vector2()
	var pb := Vector2()
	for k in 2:
		var lo := 0 if k == 0 else 4
		var a0 := float(a[lo])
		var a1 := float(a[lo + 1])
		var b0 := float(b[lo])
		var b1 := float(b[lo + 1])
		var va: float
		var vb: float
		if a1 <= b0:
			va = a1
			vb = b0
		elif b1 <= a0:
			va = a0
			vb = b1
		else:
			va = (maxf(a0, b0) + minf(a1, b1)) * 0.5
			vb = va
		pa[k] = va
		pb[k] = vb
	var gap := pa.distance_to(pb)
	var dh := float(b[3]) - float(a[3])
	if gap > REACH or dh > RISE:
		return {}
	var ca := _centre(a)
	var cb := _centre(b)
	var u: Vector2
	if gap > 0.05:
		u = (pb - pa) / gap
	else:
		# side by side: straight across the wall they share
		var ox := minf(float(a[1]), float(b[1])) - maxf(float(a[0]), float(b[0]))
		var oz := minf(float(a[5]), float(b[5])) - maxf(float(a[4]), float(b[4]))
		if ox > 0.05 and oz > 0.05:
			return {}
		u = Vector2(signf(cb.x - ca.x), 0.0) if ox <= 0.05 else Vector2(0.0, signf(cb.y - ca.y))
	var kind := "mega"
	if gap <= HOP_GAP and dh <= HOP_UP and dh >= -HOP_DOWN:
		kind = "hop"
	elif dh < -HOP_DOWN:
		kind = "drop"
	var land_in := 2.5 if kind == "hop" else 3.5
	var land := _inside(b, pb + u * land_in, 1.2)
	var take := _inside(a, pa - u * 0.6, 0.5)
	if kind == "mega" and dh > 0.0:
		# up to a higher roof: far enough back that he is clear of its wall before he is above its edge
		var ok := false
		for k in 20:
			var back := 0.6 + k * 0.4
			take = _inside(a, pa - u * back, 0.5)
			var D := (pa - take).dot(u)
			var y0 := float(a[3]) + 0.55
			var top := maxf(float(a[3]), float(b[3])) + CLEAR + 1.0
			var vy := sqrt(2.0 * GS * (top - y0))
			var T := vy / GS + sqrt(2.0 * maxf(top - (float(b[3]) + 0.9), 0.05) / GS)
			var yb := float(b[3]) + 1.0 - y0
			var t1 := (vy - sqrt(maxf(vy * vy - 2.0 * GS * yb, 0.0))) / GS
			var vh := (land - take).dot(u) / T
			if vh * t1 < D + gap - 0.6:
				ok = true
				break
		if not ok:
			return {}
	return {"kind": kind, "a": a, "b": b, "h_from": float(a[3]), "h_to": float(b[3]), "take": take, "land": land,
		"u": u.normalized(), "gap": gap, "edge": pa, "far": pb}

## The last move: off a roof to the street beside it, on the side most along the way he is going, clear of other
## buildings and parked cars.
func _to_street(a: Array, u_prev: Vector2) -> Dictionary:
	var best := {}
	var bd := -INF
	var c := _centre(a)
	for n in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		for f in [0.3, 0.5, 0.7]:
			var e := Vector2()
			if n.x != 0.0:
				e = Vector2(float(a[1]) if n.x > 0.0 else float(a[0]), lerpf(float(a[4]), float(a[5]), f))
			else:
				e = Vector2(lerpf(float(a[0]), float(a[1]), f), float(a[5]) if n.y > 0.0 else float(a[4]))
			var land: Vector2 = e + n * 6.0
			if not _open_ground(land) or not _open_ground(e + n * 3.0):
				continue
			if chase and maxf(_street_room(land, Vector2(-n.y, n.x)), _street_room(land, Vector2(n.y, -n.x))) < (0.6 if relax else 1.0):
				# the chase needs a long straight of street to run, and some behind him for the cars
				continue
			var score: float = n.dot(u_prev) - absf(f - 0.5)
			if score > bd:
				bd = score
				best = {"kind": "drop", "a": a, "b": null, "h_from": float(a[3]), "h_to": g.world.ground_at(land.x, land.y, 0.0),
					"take": _inside(a, e - n * 0.6, 0.5), "land": land, "u": n, "gap": 0.0, "edge": e, "far": e, "street": true}
	return best

## Nothing built there and no car within 3.5 m.
func _open_ground(p: Vector2) -> bool:
	for c in g.world.col:
		if float(c[3]) > 0.5 and p.x > float(c[0]) - 1.0 and p.x < float(c[1]) + 1.0 and p.y > float(c[4]) - 1.0 and p.y < float(c[5]) + 1.0:
			return false
	for car in g.veh.cars:
		if car.state != "gone" and (car.pos as Vector2).distance_to(p) < 3.5:
			return false
	return absf(p.x) < g.bound - 3.0 and absf(p.y) < g.bound - 3.0

func _centre(r: Array) -> Vector2:
	return Vector2((float(r[0]) + float(r[1])) * 0.5, (float(r[4]) + float(r[5])) * 0.5)

func _inside(r: Array, p: Vector2, inset: float) -> Vector2:
	var x0 := float(r[0]) + inset
	var x1 := float(r[1]) - inset
	var z0 := float(r[4]) + inset
	var z1 := float(r[5]) - inset
	return Vector2(clampf(p.x, minf(x0, x1), maxf(x0, x1)), clampf(p.y, minf(z0, z1), maxf(z0, z1)))

## The search: from roofs 18-45 m high, every route of 3-5 moves (the drop to the street the last) where each roof
## gives a run-up of 4-40 m between
## where he lands and where he leaves, he never turns back by more than 100 degrees, and the last roof (25 m up or
## more) has a street to drop to. The best by variety and size; the seed shuffles the search.
func _plan(roofs: Array) -> bool:
	var moves := {}
	for i in roofs.size():
		var out := []
		for j in roofs.size():
			if i != j:
				var m := _move(roofs[i], roofs[j])
				if not m.is_empty():
					m.j = j
					out.append(m)
		out.shuffle()
		moves[i] = out
	var order := range(roofs.size())
	order.shuffle()
	# (a lambda keeps its own copies of plain locals: what it finds goes in here)
	var res := {"found": [], "budget": 250000}
	var walk := func(walk_ref: Callable, i: int, path: Array, seen: Dictionary) -> void:
		res.budget -= 1
		if res.budget <= 0:
			return
		if path.size() >= (1 if chase else 2) and float(roofs[i][3]) >= 25.0:
			var last: Dictionary = path[-1]
			var fin := _to_street(roofs[i], last.u)
			if not fin.is_empty() and _runway(last.land, fin.take, last.u, fin.u):
				res.found.append([_score(path, fin), path + [fin], path.size() >= 2 and path[-1].kind == "mega"])
		if path.size() >= (_max_moves() if chase else 4):
			return
		for m in moves[i]:
			if seen.has(m.j):
				continue
			if not path.is_empty():
				var last: Dictionary = path[-1]
				if not _runway(last.land, m.take, last.u, m.u):
					continue
			seen[m.j] = true
			path.append(m)
			walk_ref.call(walk_ref, int(m.j), path, seen)
			path.pop_back()
			seen.erase(m.j)
	for i in order:
		var h := float(roofs[i][3])
		if h < 18.0 or h > 45.0:
			continue
		walk.call(walk, i, [], {i: true})
		if int(res.budget) <= 0:
			break
	var found: Array = res.found
	if found.is_empty():
		return false
	if chase and outcome == "fall":
		var late := found.filter(func(x): return x[2])
		if not late.is_empty():
			found = late
	# one of the best few, by the seed: not the same run every time
	found.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	var pick := randi() % mini(15, found.size())
	route = found[pick][1]
	# he comes running from 9 m back (or as far as the roof allows)
	var m0: Dictionary = route[0]
	start = _inside(m0.a, m0.take - m0.u * 9.0, 0.6)
	if start.distance_to(m0.take) < 4.0:
		start = _inside(m0.a, m0.take - m0.u * 9.0, 0.3)
	print("superrun: %d routes, took number %d (score %.1f, the best %.1f)" % [found.size(), pick + 1, float(found[pick][0]), float(found[0][0])])
	return true

## A run between where he lands and where he leaves next: 4-40 m, never turning back by more than 100 degrees.
func _runway(land: Vector2, take: Vector2, u_in: Vector2, u_out: Vector2) -> bool:
	var run := take - land
	var l := run.length()
	if l < 4.0 or l > 40.0:
		return false
	return u_in.dot(run / l) > -0.17 and (run / l).dot(u_out) > -0.17

func _score(path: Array, fin: Dictionary) -> float:
	var kinds := {}
	var sc := 0.0
	for m in path:
		kinds[m.kind] = true
		var dh: float = float(m.h_to) - float(m.h_from)
		if m.kind == "mega":
			sc += minf(dh, 25.0) / 6.0 + (2.0 if float(m.gap) > 7.0 else 0.0)
		elif m.kind == "drop":
			sc += minf(-dh, 40.0) / 10.0
		else:
			sc += 0.8
	sc += kinds.size() * 4.0 + float(fin.h_from) / 12.0
	# 3-4 moves and the drop make a Short; more is a long one
	if chase:
		return sc - absf(path.size() - _max_moves()) * 4.5
	return sc - maxf(0.0, path.size() - 2) * 4.5

## Roof to roof moves before the street, by the length of video wanted.
func _max_moves() -> int:
	if want_len <= 0.0:
		return 2
	return 1 if want_len <= 20.0 else (2 if want_len <= 50.0 else 3)

# ---------------------------------------------------------------- him
## When each foot leaves the ground in his sprint (a fraction of the stride: left, right).
func _toe_offs() -> void:
	var sk := man.skel
	var pts := []
	for side in ["L", "R"]:
		pts.append(sk.find_bone("Bip01 %s Foot" % side))
		pts.append(sk.find_bone("Bip01 %s Toe0" % side))
	var lows := [[], []]
	for i in 96:
		man._apply([["sprint", i / 96.0, 1.0]])
		for f in 2:
			lows[f].append(minf(sk.get_bone_global_pose(pts[f * 2]).origin.y - Man.ANKLE_REST, sk.get_bone_global_pose(pts[f * 2 + 1]).origin.y - Man.BALL_REST))
	for f in 2:
		var lo: Array = lows[f]
		var floor_y: float = lo.min()
		for i in 96:
			if lo[i] - floor_y < 0.03 and lo[(i + 1) % 96] - floor_y >= 0.03:
				toe[f] = (i + 1) / 96.0

func _segment(a: Vector2, b: Vector2, h: float) -> void:
	var v := b - a
	seg = {"a": a, "dir": v.normalized() if v.length() > 0.01 else Vector2(sin(man.yaw), cos(man.yaw)), "len": v.length(), "h": h}
	s = 0.0

## One frame of him, after the game's own update.
func drive(dt: float) -> void:
	if done or route.is_empty():
		return
	var t: float = d.now()
	tmr += dt
	shake = maxf(0.0, shake - dt * 1.6)
	man.body.position = Vector3.ZERO
	var m: Dictionary = route[mini(mi, route.size() - 1)]
	match mode:
		"run":
			_run(dt, t, m)
		"crouch":
			# planted, sinking into it; then off
			man.move(dt, Vector2(), 0.0, false)
			man.position = Vector3(seg.a.x + seg.dir.x * s, float(m.h_from), seg.a.y + seg.dir.y * s)
			man.rotation.y = man.yaw
			man.animate(dt)
			var k := clampf(tmr / 0.22, 0.0, 1.0)
			d._absorb(0.32 * k * k * (3.0 - 2.0 * k))
			if tmr >= 0.3:
				_launch(t, m)
		"air":
			_air(dt, t, m)
		"land":
			man.move(dt, Vector2(), 0.0, false)
			man.position.y = float(m.h_to)
			man.rotation.y = man.yaw
			man.animate(dt)
			var k := tmr / 0.08 if tmr < 0.08 else maxf(0.0, 1.0 - (tmr - 0.08) / 0.35)
			d._absorb(float(fl.deep) * k * k * (3.0 - 2.0 * k))
			if man.ct >= float(man.meta[fl.clip].land) + 0.3 and man.run_on():
				_next(t)
		"hero":
			man.position.y = float(m.h_to)
			man.rotation.y = man.yaw
			man.animate(dt)
			hero_w = clampf(tmr / 0.07, 0.0, 1.0)
			_hero_pose(hero_w)
			if tmr >= 0.75:
				if m.has("street") and chase:
					man.ct = float(man.meta[fl.clip].land) + 0.31
					man.run_on()
					man.speed = 0.5
					hero_fade = 1.0 / 0.6
					_street_begin(t)
				elif m.has("street"):
					# up on his feet, looking at the lens
					man._to(Man.IDLE, 0.7)
					man.idle_t = 0.0
					hero_fade = 1.0 / 0.9
					mode = "end"
					tmr = 0.0
				else:
					man.ct = float(man.meta[fl.clip].land) + 0.31
					man.run_on()
					man.speed = 0.5
					hero_fade = 1.0 / 0.55
					_next(t)
		"thrown", "getup":
			if not st.is_empty():
				st_t += dt
				_street_cars(dt, t)
			_thrown_step(dt, t)
		"street", "dodge", "vault", "vault_land", "kick", "after", "hide", "anger", "crouch2", "stomp_air", "stomp", "top":
			_street(dt, t)
		"end":
			man.move(dt, Vector2(), 0.0, false)
			man.position.y = float(m.h_to)
			man.animate(dt)
			hero_w = maxf(0.0, hero_w - hero_fade * dt)
			_hero_pose(hero_w)
			if tmr > 1.6:
				d.end_after(t, 0.6)
	if man.step != steps:
		steps = man.step
		d.mark("step_%d" % steps, t)

## Sprinting along the roof to the next take-off (turning onto it if he landed facing elsewhere); off at the edge.
func _run(dt: float, t: float, m: Dictionary) -> void:
	var want := SPRINT
	var left: float = float(seg.len) - s
	if play and int(ask.get("mi", -1)) != mi and left < 9.0:
		_ask("up", left / SPRINT, true)
		ask.mi = mi
	if m.kind == "mega" and left < 3.2:
		want = 3.2
	var before := fposmod(man.phase, 1.0)
	var yaw0 := man.yaw
	var step := man.move(dt, seg.dir, want, false)
	man.real_speed = man.speed
	s = minf(s + step.length(), float(seg.len) + 1.0)
	off = off.lerp(Vector3.ZERO, 1.0 - exp(-dt / 0.3))
	var p: Vector2 = seg.a + seg.dir * s
	man.position = Vector3(p.x, float(seg.h), p.y) + off
	man.yaw = rotate_toward(yaw0, atan2(seg.dir.x, seg.dir.y), 7.0 * dt)
	man.turn_rate = angle_difference(yaw0, man.yaw) / maxf(dt, 1e-4)
	man.rotation.y = man.yaw
	man.animate(dt)
	if hero_w > 0.0:
		hero_w = maxf(0.0, hero_w - hero_fade * dt)
		_hero_pose(hero_w)
	left = float(seg.len) - s
	if m.kind == "mega":
		if left < 0.35 and play and not ask.get("ok", false):
			_miss_edge(t, m)
		elif left < 0.35:
			# pull up and sink into a crouch: the leap clip's own landing crouch, deeper
			man.jump("gap_jump", float(man.meta.gap_jump.land) + 0.06, 0.16)
			man.jump_rate = 0.0
			mode = "crouch"
			tmr = 0.0
			d.mark("crouch_%d" % (mi + 1), t)
		return
	# hop or drop: off whichever foot last leaves the ground before the edge (as the roofrun does)
	var after := fposmod(man.phase, 1.0)
	var edge: float = float(seg.len) + 0.6
	for f in 2:
		var ph: float = toe[f]
		var crossed: bool = (before < ph and after >= ph) or (before > after and (before < ph or after >= ph))
		if crossed and edge - s - man._stride(man.speed) * 0.5 < 0.2 and mode == "run" and (not play or ask.get("ok", false)):
			_takeoff(t, m, f)
	if mode == "run" and s >= edge - 0.1:
		if play and not ask.get("ok", false):
			_miss_edge(t, m)
		else:
			_takeoff(t, m, 0 if fposmod(man.phase - toe[0], 1.0) < 0.5 else 1)

func _hips() -> Vector3:
	return man.position + Basis(Vector3.UP, man.yaw) * man.skel.get_bone_pose_position(0)

## Off the edge out of his stride: a hop (the captured leap's own arc, real gravity) or a drop (a dive off it,
## super gravity, a flip on the way down).
func _takeoff(t: float, m: Dictionary, foot: int) -> void:
	var c := "gap_jump" if foot == 0 else "gap_jump_r"
	var cm: Dictionary = man.meta[c]
	var hips0 := _hips()
	man.yaw = atan2(m.u.x, m.u.y)
	var u3 := Vector3(m.u.x, 0.0, m.u.y)
	var y1: float = float(m.h_to) + man.clip_hips(c, float(cm.land)).y
	var to_land := (Vector2(m.land.x, m.land.y) - Vector2(hips0.x, hips0.z)).dot(m.u)
	var gr := 9.81 if m.kind == "hop" else GS
	var vy := sqrt(2.0 * 9.81 * float(cm.rise)) if m.kind == "hop" else 4.0
	var T := 0.0
	var vh := man.speed
	for i in 60:
		var disc := vy * vy + 2.0 * gr * (hips0.y - y1)
		if disc < 0.0:
			vy += 0.25
			continue
		T = (vy + sqrt(disc)) / gr
		if m.kind == "hop":
			# far enough to be well onto the next roof
			var past: float = (Vector2(m.far.x, m.far.y) - Vector2(hips0.x, hips0.z)).dot(m.u) + 0.8
			if vh * T < past:
				vy += 0.2
				continue
		elif to_land / T > 11.0:
			# a drop to a roof far off: more air to get there
			vy += 0.5
			continue
		break
	if m.kind != "hop":
		vh = clampf(to_land / T, 2.5, 12.0)
	man.jump(c, float(cm.takeoff), 0.12)
	fl = {"clip": c, "hips0": hips0, "vh": u3 * vh, "vy": vy, "T": T, "g": gr, "super": m.kind != "hop",
		"flip": TAU if (m.kind != "hop" and T > 0.9 and not chase) else 0.0, "deep": 0.15}
	mode = "air"
	tmr = 0.0
	d.mark("takeoff_%d" % (mi + 1), t)
	print("superrun: move %d (%s %+.1f m) off the %s foot at %.1f m/s: %.2f s in the air" % [mi + 1, m.kind, float(m.h_to) - float(m.h_from), "left" if foot == 0 else "right", vh, T])

## Out of the crouch: up, clear of the higher roof by CLEAR, down onto the far one.
func _launch(t: float, m: Dictionary) -> void:
	var c := "gap_jump"
	var cm: Dictionary = man.meta[c]
	man.yaw = atan2(m.u.x, m.u.y)
	var hips0 := _hips()
	var y1: float = float(m.h_to) + man.clip_hips(c, float(cm.land)).y
	var top := maxf(float(m.h_from), float(m.h_to)) + CLEAR + 1.0
	var vy := sqrt(2.0 * GS * maxf(top - hips0.y, 0.5))
	var T := vy / GS + sqrt(2.0 * maxf(top - y1, 0.05) / GS)
	var to_land := (Vector2(m.land.x, m.land.y) - Vector2(hips0.x, hips0.z)).dot(m.u)
	var vh := maxf(to_land, 0.5) / T
	var short := chase and outcome == "fall" and mi == fail_mi
	if short:
		# not enough: the top of the arc just under the far roof, into its wall on the way down
		var wall: float = (Vector2(m.far.x, m.far.y) - Vector2(hips0.x, hips0.z)).dot(m.u) - 0.35
		vy = sqrt(2.0 * GS * maxf(float(m.h_to) - 0.5 - hips0.y, 0.5))
		vh = maxf(wall, 0.5) / (vy / GS + 0.3)
		T = 99.0
	man.jump(c, float(cm.takeoff) - 0.04, 0.08)
	man.jump_rate = 1.0
	fl = {"clip": c, "hips0": hips0, "vh": Vector3(m.u.x, 0.0, m.u.y) * vh, "vy": vy, "T": T, "g": GS, "super": true,
		"flip": 0.0 if chase else TAU, "deep": 0.22, "short": short}
	mode = "air"
	tmr = 0.0
	impact(Vector3(hips0.x, float(m.h_from), hips0.z), 0.7, float(m.h_from))
	d.mark("launch_%d" % (mi + 1), t)
	print("superrun: move %d (mega %+.1f m over %.1f m): up at %.1f m/s, %.2f s in the air" % [mi + 1, float(m.h_to) - float(m.h_from), float(m.gap), vy, T])

## In the air: his hips fly the arc; the leap clip goes from the push-off to its tightest tuck, holds it while he
## turns over (the flip, about his hips), and opens out to land.
func _air(dt: float, t: float, m: Dictionary) -> void:
	var c: String = fl.clip
	var cm: Dictionary = man.meta[c]
	var T: float = fl.T
	var tau := minf(tmr, T)
	var hips: Vector3 = fl.hips0 + (fl.vh as Vector3) * tau + Vector3(0.0, float(fl.vy) * tau - 0.5 * float(fl.g) * tau * tau, 0.0)
	var x := tau / T
	var tk := float(cm.takeoff)
	var ld := float(cm.land)
	if fl.get("short", false):
		x = clampf(tmr / 1.4, 0.0, 0.7)
		var wall: float = (Vector2(m.far.x, m.far.y) - Vector2(fl.hips0.x, fl.hips0.z)).dot(m.u) - 0.35
		if (Vector2(hips.x, hips.z) - Vector2(fl.hips0.x, fl.hips0.z)).dot(m.u) >= wall:
			# into the wall, short of the top: knocked back off it, falling
			var vyn: float = float(fl.vy) - float(fl.g) * tau
			fx.burst("impact", hips + Vector3(m.u.x, 0.4, m.u.y) * 0.4, Vector3(-m.u.x, 0.3, -m.u.y))
			shake = maxf(shake, 0.3)
			d.mark("wallhit", t)
			man.body.transform = Transform3D()
			_thrown(Vector3(-m.u.x * 1.6, minf(vyn, 0.0), -m.u.y * 1.6), GS, -1.0,
				g.world.ground_at(hips.x - m.u.x * 2.0, hips.z - m.u.y * 2.0, 0.0), hips)
			return
	var ct: float
	if not fl.super:
		ct = tk + (ld - tk) * d._warp(x, clampf(T / (ld - tk), 0.5, 2.6))
	elif x < 0.22:
		ct = lerpf(tk, APEX_CT, _ease(x / 0.22))
	elif x < 0.72:
		ct = APEX_CT
	else:
		ct = lerpf(APEX_CT, ld, _ease((x - 0.72) / 0.28))
	man.ct = ct
	var R := Basis(Vector3.UP, man.yaw)
	man.position = hips - R * man.clip_hips(c, ct)
	man.rotation.y = man.yaw
	man.animate(dt)
	if chase and fl.super:
		# flying, not falling: a fist out, one knee drawn up, leaning into the way down
		var vy_now: float = float(fl.vy) - float(fl.g) * tau
		var w := _ease((x - 0.06) / 0.14) * (1.0 - _ease((x - 0.8) / 0.12))
		_fly_pose(w, clampf(vy_now / 10.0, -1.0, 1.0))
		var pitch := clampf(-vy_now * 0.035, 0.0, 0.5) * w
		if pitch > 0.001:
			var hl0 := man.skel.get_bone_pose_position(0)
			var B0 := Basis(Vector3.RIGHT, pitch)
			man.body.transform = Transform3D(B0, hl0 - B0 * hl0)
	var turn := float(fl.flip) * _ease(clampf((x - 0.2) / 0.52, 0.0, 1.0))
	if turn > 0.0 and turn < TAU - 0.001:
		var hl := man.skel.get_bone_pose_position(0)
		var B := Basis(Vector3.RIGHT, turn)
		man.body.transform = Transform3D(B, hl - B * hl)
		if not d.events.has("flip_%d" % (mi + 1)):
			d.mark("flip_%d" % (mi + 1), t)
	if tmr < T:
		return
	# down
	man.body.transform = Transform3D()
	man.position.y = float(m.h_to)
	var at := Vector3(man.position.x, float(m.h_to), man.position.z)
	var fall: float = float(fl.vy) * float(fl.vy) / (2.0 * float(fl.g)) + float(fl.hips0.y) - hips.y
	if m.kind == "drop":
		man.ct = ld + 0.06
		man.jump_rate = 0.0
		mode = "hero"
		tmr = 0.0
		impact(at, 1.6 if m.has("street") else 1.25, float(m.h_to))
		d.mark("slam_%d" % (mi + 1), t)
		if chase and m.has("street"):
			_shockwave(at, m.u, t)
	else:
		man.jump_rate = 1.5
		fl.deep = clampf(0.03 * fall + 0.05, 0.08, 0.26)
		mode = "land"
		tmr = 0.0
		if m.kind == "mega":
			impact(at, 0.8, float(m.h_to))
			d.mark("impact_%d" % (mi + 1), t)
		else:
			d.mark("touchdown_%d" % (mi + 1), t)

## On to the next move: the run from where he is to its take-off.
func _next(t: float) -> void:
	mi += 1
	if mi >= route.size():
		mode = "end"
		return
	var m: Dictionary = route[mi]
	var q := Vector2(man.position.x, man.position.z)
	_segment(q, m.take, float(m.h_from))
	off = Vector3.ZERO
	mode = "run"
	tmr = 0.0

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

# ---------------------------------------------------------------- the superhero landing
## Laid over whatever pose he has, by w (0..1): down on his right knee, the left foot planted ahead, the right
## fist on the ground, the left arm out behind, head down. Bones are bent in his own space (he faces +z, his left
## is +x) and reached with two-bone IK; then each is blended from where it was by w.
func _hero_pose(w: float) -> void:
	if w <= 0.001:
		return
	var sk := man.skel
	var ids := {}
	for n in ["Bip01", "Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head", "Bip01 L Thigh", "Bip01 L Calf",
			"Bip01 L Foot", "Bip01 R Thigh", "Bip01 R Calf", "Bip01 R Foot", "Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand",
			"Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand"]:
		ids[n] = sk.find_bone(n)
	var base := {}
	for n in ids:
		base[n] = [sk.get_bone_pose_position(ids[n]), sk.get_bone_pose_rotation(ids[n])]
	var b0: int = ids["Bip01"]
	# the hips down and forward, tipped forward
	sk.set_bone_pose_position(b0, Vector3(0.0, 0.46, 0.05))
	_turn(b0, deg_to_rad(24.0))
	for n in [["Bip01 Spine", 14.0], ["Bip01 Spine1", 12.0], ["Bip01 Spine2", 10.0], ["Bip01 Neck", 6.0], ["Bip01 Head", 14.0]]:
		_turn(ids[n[0]], deg_to_rad(n[1]))
	var flat: Basis = sk.get_bone_global_rest(ids["Bip01 L Foot"]).basis
	var pointed: Basis = Basis(Vector3.RIGHT, deg_to_rad(62.0)) * sk.get_bone_global_rest(ids["Bip01 R Foot"]).basis
	_ik(ids["Bip01 L Thigh"], ids["Bip01 L Calf"], ids["Bip01 L Foot"], Vector3(0.15, Man.ANKLE_REST, 0.38), Vector3(0.1, 0.6, 1.0), flat)
	_ik(ids["Bip01 R Thigh"], ids["Bip01 R Calf"], ids["Bip01 R Foot"], Vector3(-0.12, 0.13, -0.44), Vector3(0.0, -1.0, 0.25), pointed)
	_ik(ids["Bip01 R UpperArm"], ids["Bip01 R Forearm"], ids["Bip01 R Hand"], Vector3(-0.27, 0.09, 0.47), Vector3(-1.0, 0.4, -0.4), null)
	_ik(ids["Bip01 L UpperArm"], ids["Bip01 L Forearm"], ids["Bip01 L Hand"], Vector3(0.62, 0.62, -0.32), Vector3(0.2, -1.0, -0.2), null)
	# the fist on the ground: the hand pointing down
	var hg := sk.get_bone_global_pose(ids["Bip01 R Hand"])
	hg.basis = Basis(Quaternion(hg.basis.x.normalized(), Vector3(0.0, -1.0, 0.15).normalized())) * hg.basis
	sk.set_bone_global_pose(ids["Bip01 R Hand"], hg)
	if w >= 0.999:
		return
	for n in ids:
		var i: int = ids[n]
		sk.set_bone_pose_position(i, (base[n][0] as Vector3).lerp(sk.get_bone_pose_position(i), w))
		sk.set_bone_pose_rotation(i, (base[n][1] as Quaternion).slerp(sk.get_bone_pose_rotation(i), w))

## Flying, laid over the leap clip by w: back straight and chin up, the left leg long with the toes pointed, the
## right knee drawn up, the right fist out (overhead going up, ahead coming down: up from -1 to 1), the left arm back.
func _fly_pose(w: float, up: float) -> void:
	if w <= 0.001:
		return
	var sk := man.skel
	var ids := {}
	for n in ["Bip01", "Bip01 Spine", "Bip01 Spine1", "Bip01 Neck", "Bip01 Head", "Bip01 L Thigh", "Bip01 L Calf", "Bip01 L Foot",
			"Bip01 R Thigh", "Bip01 R Calf", "Bip01 R Foot", "Bip01 L UpperArm", "Bip01 L Forearm", "Bip01 L Hand",
			"Bip01 R UpperArm", "Bip01 R Forearm", "Bip01 R Hand"]:
		ids[n] = sk.find_bone(n)
	var base := {}
	for n in ids:
		base[n] = [sk.get_bone_pose_position(ids[n]), sk.get_bone_pose_rotation(ids[n])]
	for n in [["Bip01 Spine", -10.0], ["Bip01 Spine1", -8.0], ["Bip01 Neck", -6.0], ["Bip01 Head", -12.0]]:
		_turn(ids[n[0]], deg_to_rad(n[1]))
	var hp: Vector3 = sk.get_bone_global_pose(ids["Bip01"]).origin
	var pl: Basis = Basis(Vector3.RIGHT, deg_to_rad(55.0)) * sk.get_bone_global_rest(ids["Bip01 L Foot"]).basis
	var pr: Basis = Basis(Vector3.RIGHT, deg_to_rad(45.0)) * sk.get_bone_global_rest(ids["Bip01 R Foot"]).basis
	_ik(ids["Bip01 L Thigh"], ids["Bip01 L Calf"], ids["Bip01 L Foot"], hp + Vector3(0.1, -0.93, -0.14), Vector3(0.0, 0.0, 1.0), pl)
	_ik(ids["Bip01 R Thigh"], ids["Bip01 R Calf"], ids["Bip01 R Foot"], hp + Vector3(-0.12, -0.52, 0.08), Vector3(0.0, 0.25, 1.0), pr)
	var shr: Vector3 = sk.get_bone_global_pose(ids["Bip01 R UpperArm"]).origin
	var shl: Vector3 = sk.get_bone_global_pose(ids["Bip01 L UpperArm"]).origin
	var k := (up + 1.0) * 0.5
	_ik(ids["Bip01 R UpperArm"], ids["Bip01 R Forearm"], ids["Bip01 R Hand"], shr + Vector3(-0.06, 0.12, 0.56).lerp(Vector3(-0.05, 0.56, 0.2), k),
		Vector3(-0.4, -1.0, 0.0), null)
	_ik(ids["Bip01 L UpperArm"], ids["Bip01 L Forearm"], ids["Bip01 L Hand"], shl + Vector3(0.2, -0.46, -0.3), Vector3(0.3, 0.0, -1.0), null)
	if w >= 0.999:
		return
	for n in ids:
		var i: int = ids[n]
		sk.set_bone_pose_position(i, (base[n][0] as Vector3).lerp(sk.get_bone_pose_position(i), w))
		sk.set_bone_pose_rotation(i, (base[n][1] as Quaternion).slerp(sk.get_bone_pose_rotation(i), w))

## Tips a bone forward (about his own x) by a, about its own joint.
func _turn(b: int, a: float) -> void:
	var gp := man.skel.get_bone_global_pose(b)
	gp.basis = Basis(Vector3.RIGHT, a) * gp.basis
	man.skel.set_bone_global_pose(b, gp)

## Two-bone IK in his own space: the joint at the end of bones a, b reaches target, the middle joint bending
## towards pole; the end bone c given its own turn if end_basis is a Basis.
func _ik(a: int, b: int, c: int, target: Vector3, pole: Vector3, end_basis) -> void:
	var sk := man.skel
	var ga := sk.get_bone_global_pose(a)
	var gb := sk.get_bone_global_pose(b)
	var gc := sk.get_bone_global_pose(c)
	var l1 := ga.origin.distance_to(gb.origin)
	var l2 := gb.origin.distance_to(gc.origin)
	var h := ga.origin
	var dd := clampf(h.distance_to(target), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
	var u := (target - h).normalized()
	var p := pole - u * pole.dot(u)
	if p.length() < 1e-4:
		return
	p = p.normalized()
	var along := (l1 * l1 - l2 * l2 + dd * dd) / (2.0 * dd)
	var mid := h + u * along + p * sqrt(maxf(l1 * l1 - along * along, 0.0))
	ga.basis = Basis(Quaternion((gb.origin - h).normalized(), (mid - h).normalized())) * ga.basis
	sk.set_bone_global_pose(a, ga)
	gb = sk.get_bone_global_pose(b)
	var end := sk.get_bone_global_pose(c).origin
	gb.basis = Basis(Quaternion((end - gb.origin).normalized(), (target - gb.origin).normalized())) * gb.basis
	sk.set_bone_global_pose(b, gb)
	if end_basis is Basis:
		var gf := sk.get_bone_global_pose(c)
		gf.basis = end_basis
		sk.set_bone_global_pose(c, gf)

# ---------------------------------------------------------------- impacts
## Where he hits hard: the surface cracks (a decal of cracks), dust rings out along it, grit flies, the lens
## shakes. power ~1: a superhero landing.
func impact(at: Vector3, power: float, floor_y: float) -> void:
	var dc := Decal.new()
	dc.texture_albedo = crack
	dc.size = Vector3(4.2, 2.0, 4.2) * clampf(power, 0.5, 1.8)
	dc.position = at + Vector3(0, 0.3, 0)
	dc.rotation.y = randf() * TAU
	dc.albedo_mix = 1.0
	dc.upper_fade = 0.2
	dc.lower_fade = 0.2
	dc.cull_mask = 0xFFFFF & ~MAN_LAYER
	g.add_child(dc)
	fx.burst("shock" if power >= 0.75 else "puff", Vector3(at.x, floor_y, at.z), Vector3.UP)
	shake = maxf(shake, 0.22 * power)

## Cracks running out from a crushed middle, drawn once (512 px, transparent between them).
func _crack_texture() -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n * 0.5, n * 0.5)
	for y in range(n / 2 - 70, n / 2 + 70):
		for x in range(n / 2 - 70, n / 2 + 70):
			var r := Vector2(x, y).distance_to(c) / 70.0
			if r < 1.0:
				var a := 0.75 * pow(1.0 - r, 0.6) * (0.75 + 0.25 * randf())
				img.set_pixel(x, y, Color(0.06, 0.055, 0.05, a))
	var arms := 13
	for i in arms:
		var ang := TAU * i / arms + randf_range(-0.2, 0.2)
		_crack_line(img, c, ang, randf_range(150.0, 245.0), 4.0, 2)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _crack_line(img: Image, from: Vector2, ang: float, length: float, width: float, depth: int) -> void:
	var p := from
	var steps_n := int(length / 6.0)
	for k in steps_n:
		ang += randf_range(-0.35, 0.35)
		var q := p + Vector2(cos(ang), sin(ang)) * 6.0
		var w := width * (1.0 - float(k) / steps_n) + 0.8
		for j in 7:
			var m := p.lerp(q, j / 6.0)
			for oy in range(-int(ceil(w)), int(ceil(w)) + 1):
				for ox in range(-int(ceil(w)), int(ceil(w)) + 1):
					var px := int(m.x) + ox
					var py := int(m.y) + oy
					if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
						continue
					var dist := Vector2(ox, oy).length()
					if dist <= w:
						var a := 0.85 * (1.0 - dist / (w + 0.5))
						var old := img.get_pixel(px, py)
						if a > old.a:
							img.set_pixel(px, py, Color(0.05, 0.045, 0.04, a))
		p = q
		if depth > 0 and randf() < 0.07:
			_crack_line(img, p, ang + randf_range(-1.0, 1.0), length * 0.4, w * 0.7, depth - 1)

# ---------------------------------------------------------------- superchase: the street
## How far a straight line from p runs clear of buildings and street furniture (not cars), up to most.
func _open_run(p: Vector2, dir: Vector2, most: float) -> float:
	var k := 0.0
	while k < most:
		var q := p + dir * (k + 2.0)
		for c in g.world.col:
			if float(c[3]) > 0.5 and q.x > float(c[0]) - 0.8 and q.x < float(c[1]) + 0.8 and q.y > float(c[4]) - 0.8 and q.y < float(c[5]) + 0.8:
				return k
		if absf(q.x) > g.bound - 2.0 or absf(q.y) > g.bound - 2.0:
			return k
		k += 2.0
	return k

## Down in the street every car in sight comes for him, nobody at the wheel, each one driving straight at him: from
## where they wait (behind him, and up ahead) they pull off as late as they can and are flat out when they get to him.
## What he does about them (the seed picks which, and in what order): a side step or a dive and roll at the last
## moment (it goes through where he was); a leap over one coming head on; a foot on the roof of one and off it; two at
## once from both ends that hit each other when he steps out from between them; one that follows him past a lamp
## post into it; one that rams the car he ducks behind and goes over him. Then one head on he kicks away end over end,
## the one behind him stops short, and he has had enough: he leaps onto it, crushes it flat and stands on the wreck.
## (Outcome "car": the second one gets him: he is thrown, comes down hard, rolls and gets up.)
func _street_begin(t: float) -> void:
	var m: Dictionary = route[-1]
	var p0 := Vector2(man.position.x, man.position.z)
	var u: Vector2 = m.u
	var best := {}
	for sgn in [1.0, -1.0]:
		var dir: Vector2 = Vector2(-u.y, u.x) * sgn
		var room := _street_room(p0, dir)
		if best.is_empty() or room > float(best.room):
			best = {"dir": dir, "room": room}
	st = best
	var dir: Vector2 = st.dir
	st.ahead = _open_run(p0, dir, 130.0)
	st.behind = _open_run(p0, -dir, 60.0)
	st.p0 = p0
	st.n = u
	st.y = float(m.h_to)
	# what is parked along it goes, every door is shut; the cars that come for him are taken from the rest
	var picked := []
	for c in g.veh.cars:
		if c.get("hinge"):
			(c.hinge as Node3D).rotation.y = 0.0
		if c.state == "gone" or c.state == "tumble" or c.node == null:
			continue
		var q: Vector2 = (c.pos as Vector2) - p0
		var along := q.dot(dir)
		if along > -float(st.behind) - 8.0 and along < float(st.ahead) + 8.0 and absf(q.dot(u)) < 4.5:
			_park_away(c)
		elif c.state == "parked" and picked.size() < 16:
			picked.append(c)
	# the cars, in the order they get to him: [when, +1 from behind / -1 head on, what for (, the lamp post)]
	var plan := []
	for b in _beats():
		var what: String = b[2]
		if what == "pole":
			var pole := _find_pole(SPRINT * 0.82 * (float(b[0]) - 0.3))
			if pole != Vector2.INF:
				plan.append([b[0], 1, "pole", pole])
				continue
			# (no lamp post where it would be: two cars head on instead, or a side step if that is coming anyway)
			what = "crash2"
			for b2 in _beats():
				if b2[2] == "crash2":
					what = "step"
		if what == "crash2":
			plan.append([b[0], 1, "crash2"])
			plan.append([b[0], -1, "crash2_h"])
		elif what == "hide":
			plan.append([float(b[0]) - 2.2, -1, "shield"])
			plan.append([b[0], -1, "hide"])
		else:
			plan.append([b[0], b[1], what])
	var nb := 0
	for b in plan:
		if int(b[1]) > 0:
			nb += 1
	var gap_b := clampf((float(st.behind) - 9.0) / maxf(nb - 1, 1), 5.5, 7.0)
	var kb := 0
	cars_on = []
	for i in mini(plan.size(), picked.size()):
		var c: Dictionary = picked[i]
		var b: Array = plan[i]
		var from := int(b[1])
		var start: float
		if from > 0:
			# queued behind where he lands, the first to go at the front
			start = -6.0 - gap_b * kb
			kb += 1
		else:
			# up ahead, a fair way past where it will get to him
			start = clampf(SPRINT * 0.82 * float(b[0]) + 28.0, 12.0, float(st.ahead) - 4.0)
		var lane0 := 1.7 if i % 2 == 0 else -1.7
		if c.box >= 0:
			g.col.disable_box(c.box)
		c.state = "driven"
		c.roll = 0.0
		c.lift = 0.0
		c.y = st.y
		c.pos = _street_at(start, lane0)
		var hd := dir * float(from)
		c.yaw = atan2(-hd.y, hd.x)
		(c.node as Node3D).visible = true
		g.veh._apply(c)
		g.world.move_car_halos(c.i, g.veh.xform(c), true)
		var e := {"c": c, "t": float(b[0]), "from": from, "what": b[2], "v": 13.5 if from > 0 else 12.0,
			"s_meet": start, "start": start, "lane0": lane0, "lane": lane0, "fixed": false, "done": false, "past": false, "i": i + 1}
		if b[2] == "pole":
			var pl: Vector2 = b[3]
			e.pole = pl
			e.s_meet = pl.x - float(c.size.x) * 0.5
			e.lane = pl.y
			e.fixed = true
		if b[2] in ["crash2_h", "shield", "brake"]:
			e.done = true
		cars_on.append(e)
	for k in range(1, cars_on.size()):
		if cars_on[k].what == "crash2_h" and cars_on[k - 1].what == "crash2":
			cars_on[k - 1].pair = cars_on[k]
		if cars_on[k].what == "hide" and cars_on[k - 1].what == "shield":
			cars_on[k].shield = cars_on[k - 1]
	for e in cars_on:
		if e.what == "hide" and not e.has("shield"):
			e.what = "vault"
	mode = "street"
	tmr = 0.0
	st_t = 0.0
	st_s = 0.0
	st_off = 0.0
	d.mark("engines", t)
	var whats := []
	for e in cars_on:
		whats.append(e.what)
	print("superchase: the street runs %.0f m on (%.0f m behind), %d cars after him: %s" % [float(st.ahead), float(st.behind), cars_on.size(), ", ".join(whats)])

const LEADS := {"step": 0.72, "dive": 0.78, "vault": 0.36, "roofstep": 0.42, "crash2": 0.72}

## [seconds into the street when it gets to him, +1 from behind / -1 head on, what he does]: a few of the moves, in
## an order picked by the seed (as many as the length wanted allows), then the kick and the one he crushes.
func _beats() -> Array:
	if outcome == "car":
		return [[2.8, 1, "step"], [4.9, 1, "hit"]]
	var pool := ["step", "dive", "vault", "crash2", "pole", "hide", "roofstep"]
	var dur := {"step": 2.2, "dive": 2.4, "vault": 2.4, "crash2": 2.6, "pole": 2.8, "hide": 3.4, "roofstep": 2.4}
	var from := {"step": 1, "dive": 1, "vault": -1, "crash2": 1, "pole": 1, "hide": -1, "roofstep": -1}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed_n) * 7919 + 11
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var k := 1 if (want_len > 0.0 and want_len <= 20.0) else (5 if want_len > 32.0 else 3)
	if all_stunts:
		k = pool.size()
	var out := []
	var at := 4.6 if pool[0] == "hide" else 2.8
	for i in k:
		out.append([at, from[pool[i]], pool[i]])
		at += float(dur[pool[i]])
	out.append([at, -1, "kick"])
	out.append([at + 0.5, 1, "brake"])
	return out

## How much clear street he needs ahead of where he lands (he runs most of it; the last cars wait beyond).
func _need_ahead() -> float:
	return SPRINT * float(_beats()[-1][0]) * 0.85 + 22.0

const NEED_BEHIND := 22.0

## 1 or more: a street with all the room the chase needs, either way along it from p.
func _street_room(p: Vector2, dir: Vector2) -> float:
	return minf(_open_run(p, dir, _need_ahead() + 10.0) / _need_ahead(), _open_run(p, -dir, NEED_BEHIND + 8.0) / NEED_BEHIND)

## A lamp post (or any thin post) beside the street near where he will be: [along, to the side], or INF.
func _find_pole(est: float) -> Vector2:
	var best := Vector2.INF
	for c in g.world.col:
		if float(c[1]) - float(c[0]) > 0.7 or float(c[5]) - float(c[4]) > 0.7 or float(c[3]) < 2.5 or float(c[2]) > 0.5:
			continue
		var q := Vector2((float(c[0]) + float(c[1])) * 0.5, (float(c[4]) + float(c[5])) * 0.5) - (st.p0 as Vector2)
		var a := q.dot(st.dir)
		var l := q.dot(st.n)
		if absf(a - est) < 6.0 and absf(l) > 1.8 and absf(l) < 7.5 and (best == Vector2.INF or absf(a - est) < absf(best.x - est)):
			best = Vector2(a, l)
	return best

## Which way (along the street's side) a dodge clip takes him: +1 / -1 (side if it hardly moves him).
func _dodge_side(c: String, yaw_add: float, side: float) -> float:
	var r := man._root(c, man._len(c))
	var lat := (Basis(Vector3.UP, atan2(st.dir.x, st.dir.y) + yaw_add) * Vector3(r.x, 0.0, r.y)).dot(Vector3(st.n.x, 0.0, st.n.y))
	return signf(lat) if absf(lat) > 0.3 else side

## Where he crouches behind the car he hides behind.
func _spot(sh: Dictionary) -> float:
	return float(sh.s_meet) - float(sh.c.size.x) * 0.5 - 0.75

func _park_away(c: Dictionary) -> void:
	if c.box >= 0:
		g.col.disable_box(c.box)
	c.pos = Vector2(g.bound + 60.0, g.bound + 60.0)
	c.state = "gone"
	(c.node as Node3D).visible = false
	g.veh._apply(c)
	g.world.move_car_halos(c.i, g.veh.xform(c), true)
	if c.get("smoke"):
		(c.smoke as Node3D).visible = false

func _street_at(along: float, side: float) -> Vector2:
	return (st.p0 as Vector2) + (st.dir as Vector2) * along + (st.n as Vector2) * side

## The landing in the street knocks the parked cars round him over, flying away from him (the ones in the street
## off to its side, out of the way of the chase).
func _shockwave(at: Vector3, u: Vector2, t: float) -> void:
	var n := 0
	for c in g.veh.cars:
		if c.state != "parked" or c.node == null:
			continue
		var q: Vector2 = (c.pos as Vector2) - Vector2(at.x, at.z)
		var dd := q.length()
		if dd > 16.0 or dd < 0.5:
			continue
		var across := q.dot(u)
		if absf(across) > 4.5:
			if absf(across) / dd > 0.5:
				g.veh.knock(c, q / dd, clampf(1.2 - dd / 16.0, 0.3, 1.0))
				n += 1
		else:
			g.veh.knock(c, (u * (1.0 if across >= 0.0 else -1.0) + q / dd * 0.3).normalized(), clampf(1.2 - dd / 16.0, 0.65, 1.0))
			n += 1
	if n > 0:
		d.mark("shockwave", t)

## One frame in the street: the cars, then him.
func _street(dt: float, t: float) -> void:
	st_t += dt
	_street_cars(dt, t)
	var dir: Vector2 = st.dir
	var yaw_dir := atan2(dir.x, dir.y)
	match mode:
		"street":
			# flat out; over towards a lamp post, or to the car he will hide behind, on time
			var want := SPRINT
			st.want_off = st_off
			for e in cars_on:
				if e.done:
					continue
				if e.what == "pole":
					var pl: Vector2 = e.pole
					var lf: float = float(e.t) - 0.3 - st_t
					if lf < 4.0:
						st.want_off = pl.y - signf(pl.y) * 0.6
						if lf > 0.3:
							want = clampf((pl.x - st_s) / lf, 4.2, 7.2)
				elif e.what == "hide":
					var sh: Dictionary = e.shield
					var lf: float = float(e.t) - 1.2 - st_t
					if lf < 4.0:
						st.want_off = float(sh.lane)
						if lf > 0.3:
							want = clampf((_spot(sh) - st_s) / lf, 4.0, 7.2)
				break
			var off0 := st_off
			st_off = move_toward(st_off, float(st.want_off), 1.4 * dt)
			var lat := (st_off - off0) / maxf(dt, 1e-4)
			var face := (dir * maxf(man.speed, 1.0) + (st.n as Vector2) * lat).normalized()
			var yaw0 := man.yaw
			var step := man.move(dt, face, want, false)
			man.real_speed = man.speed
			st_s += step.length() * dir.dot(face)
			var p := _street_at(st_s, st_off)
			man.position = Vector3(p.x, float(st.y), p.y)
			man.yaw = rotate_toward(yaw0, atan2(face.x, face.y), 6.0 * dt)
			man.turn_rate = angle_difference(yaw0, man.yaw) / maxf(dt, 1e-4)
			man.rotation.y = man.yaw
			man.animate(dt)
			if hero_w > 0.0:
				hero_w = maxf(0.0, hero_w - hero_fade * dt)
				_hero_pose(hero_w)
			for e in cars_on:
				if e.done:
					continue
				if e.what == "pole":
					if st_s > float(e.pole.x) + 0.5:
						e.done = true
						continue
				elif e.what == "hide":
					if play and ask.is_empty() and st_s >= _spot(e.shield) - 6.0:
						_ask(GESTURE.hide, 1.0)
					if st_s >= _spot(e.shield) - 0.25:
						_answer(e, t)
				elif e.what != "hit":
					var lead: float = LEADS.get(e.what, float(man.meta.kick.hit) + 0.05)
					if play and ask.is_empty() and st_t >= float(e.t) - lead - 1.1:
						_ask(GESTURE.get(e.what, "tap"), 1.1)
					if st_t >= float(e.t) - lead:
						_answer(e, t)
				break
			if play and mode == "street" and st_t > float(cars_on[-1].t) + 2.5 if not cars_on.is_empty() else false:
				d.end_after(t, 1.0)
		"dodge":
			# the clip carries him aside, and the push gets him out of its way; then he runs on from there
			var step := man.move(dt, Vector2(), 0.0, false)
			var k0 := _ease((tmr - dt) / 0.42)
			var k1 := _ease(tmr / 0.42)
			man.position += step + (st.push as Vector3) * (k1 - k0)
			man.position.y = float(st.y)
			man.rotation.y = man.yaw
			man.animate(dt)
			_street_resync()
			if man.state == Man.MOVE:
				mode = "street"
		"vault":
			var c: String = fl.clip
			var cm: Dictionary = man.meta[c]
			var T: float = fl.T
			var tau := minf(tmr, T)
			var hips: Vector3 = fl.hips0 + (fl.vh as Vector3) * tau + Vector3(0.0, float(fl.vy) * tau - 0.5 * 9.81 * tau * tau, 0.0)
			var tk := float(cm.takeoff)
			var ld := float(cm.land)
			man.ct = tk + (ld - tk) * d._warp(tau / T, clampf(T / (ld - tk), 0.5, 2.6))
			man.position = hips - Basis(Vector3.UP, man.yaw) * man.clip_hips(c, man.ct)
			man.rotation.y = man.yaw
			man.animate(dt)
			_street_resync()
			if tmr >= T and fl.get("step2", false):
				# a foot on its roof as it goes under him, and off it again
				var vy2 := 4.2
				var yl := float(st.y) + man.clip_hips(c, ld).y
				fl.T = (vy2 + sqrt(vy2 * vy2 + 2.0 * 9.81 * maxf(hips.y - yl, 0.0))) / 9.81
				fl.hips0 = hips
				fl.vy = vy2
				fl.step2 = false
				man.jump(c, tk, 0.06)
				tmr = 0.0
				shake = maxf(shake, 0.15)
				d.mark("roofstep", t)
			elif tmr >= T:
				man.position.y = float(st.y)
				man.jump_rate = 1.5
				mode = "vault_land"
				tmr = 0.0
				d.mark("touchdown_v", t)
		"vault_land":
			var step := man.move(dt, Vector2(), 0.0, false)
			man.position += step
			man.position.y = float(st.y)
			man.rotation.y = man.yaw
			man.animate(dt)
			_street_resync()
			if man.ct >= float(man.meta[fl.clip].land) + 0.3 and man.run_on():
				mode = "street"
		"hide":
			# down behind it until it has been hit, then up and on
			var up: bool = st.has("hide_hit") and st_t - float(st.hide_hit) > 0.55
			man.move(dt, Vector2(), 0.0, not up)
			var p := _street_at(st_s, st_off)
			man.position = Vector3(p.x, float(st.y), p.y)
			man.yaw = rotate_toward(man.yaw, yaw_dir, 6.0 * dt)
			man.rotation.y = man.yaw
			man.animate(dt)
			if (up and st_t - float(st.hide_hit) > 1.1) or tmr > 4.5:
				st.erase("hide_hit")
				mode = "street"
		"kick", "after":
			var step := man.move(dt, Vector2(), 0.0, false)
			man.position += step
			man.position.y = float(st.y)
			man.rotation.y = man.yaw
			man.animate(dt)
			_street_resync()
			if mode == "kick" and (man.state != Man.JUMP or man.ct >= float(man.meta.kick.len) - 0.3 or tmr > 3.0):
				man._to(Man.IDLE, 0.5)
				man.idle_t = 0.0
				mode = "after"
			if mode == "after":
				var vic := {}
				for e in cars_on:
					if e.what == "brake" and e.c.state == "driven":
						vic = e
				if not vic.is_empty() and tmr > 1.6 and not play:
					_stomp_begin(vic, t)
				elif not vic.is_empty() and tmr > 1.6:
					# his call: crush it (rage full, a swipe up) or not
					if rage < 0.75:
						d.end_after(t, 1.0)
					elif not st.has("stomp_asked"):
						st.stomp_asked = true
						_ask("up", 2.5, true)
						_say("RAGE FULL! SWIPE UP")
					elif ask.get("ok", false):
						ask = {}
						_stomp_begin(vic, t)
					elif ask.is_empty() or d.now() > float(ask.t1):
						ask = {}
						d.end_after(t, 0.5)
				elif vic.is_empty() and tmr > 2.2:
					d.end_after(t, 0.3)
		"anger":
			# he has had enough: round to face the one behind him
			man.move(dt, Vector2(), 0.0, false)
			man.position.y = float(st.y)
			var cp: Vector2 = st.victim.pos
			man.yaw = rotate_toward(man.yaw, atan2(cp.x - man.position.x, cp.y - man.position.z), 4.5 * dt)
			man.turn_rate = 0.0
			man.rotation.y = man.yaw
			man.animate(dt)
			if tmr > 1.1:
				man.jump("gap_jump", float(man.meta.gap_jump.land) + 0.06, 0.16)
				man.jump_rate = 0.0
				mode = "crouch2"
				tmr = 0.0
		"crouch2":
			man.move(dt, Vector2(), 0.0, false)
			man.position.y = float(st.y)
			man.rotation.y = man.yaw
			man.animate(dt)
			var k := clampf(tmr / 0.22, 0.0, 1.0)
			d._absorb(0.32 * k * k * (3.0 - 2.0 * k))
			if tmr >= 0.3:
				_stomp_launch(t)
		"stomp_air":
			var T: float = fl.T
			var tau := minf(tmr, T)
			var hips: Vector3 = fl.hips0 + (fl.vh as Vector3) * tau + Vector3(0.0, float(fl.vy) * tau - 0.5 * GS * tau * tau, 0.0)
			var x := tau / T
			var cm: Dictionary = man.meta.gap_jump
			var ct: float
			if x < 0.22:
				ct = lerpf(float(cm.takeoff), APEX_CT, _ease(x / 0.22))
			elif x < 0.72:
				ct = APEX_CT
			else:
				ct = lerpf(APEX_CT, float(cm.land), _ease((x - 0.72) / 0.28))
			man.ct = ct
			man.position = hips - Basis(Vector3.UP, man.yaw) * man.clip_hips("gap_jump", ct)
			man.rotation.y = man.yaw
			man.animate(dt)
			_fly_pose(_ease((x - 0.06) / 0.14) * (1.0 - _ease((x - 0.8) / 0.12)), clampf((float(fl.vy) - GS * tau) / 10.0, -1.0, 1.0))
			if tmr >= T:
				# onto its roof: the roof caves in, the glass goes, it is done for
				man.ct = float(cm.land) + 0.06
				man.jump_rate = 0.0
				mode = "stomp"
				tmr = 0.0
				var c: Dictionary = st.victim
				var at := Vector3(man.position.x, float(st.y) + float(c.size.y), man.position.z)
				fx.burst("shock", at, Vector3.UP)
				fx.burst("impact", at + Vector3(0, 0.3, 0), Vector3.UP)
				shake = 0.7
				score += 300
				_say("CRUSHED!")
				g.veh._smoke(c)
				g.world.move_car_halos(c.i, g.veh.xform(c), true)
				d.mark("stomp", t)
		"stomp", "top":
			var c: Dictionary = st.victim
			st.crush = minf(float(st.get("crush", 0.0)) + dt / 0.12, 1.0)
			var k := lerpf(1.0, 0.58, _ease(float(st.crush)))
			var tr: Transform3D = g.veh.xform(c)
			tr.basis = tr.basis * Basis.from_scale(Vector3(1.0, k, 1.0))
			(c.node as Node3D).transform = tr
			man.move(dt, Vector2(), 0.0, false)
			man.position.y = float(st.y) + float(c.size.y) * k
			man.rotation.y = man.yaw
			man.animate(dt)
			if mode == "stomp":
				hero_w = clampf(tmr / 0.07, 0.0, 1.0)
				_hero_pose(hero_w)
				if tmr >= 0.9:
					man._to(Man.IDLE, 0.7)
					man.idle_t = 0.0
					hero_fade = 1.0 / 0.9
					mode = "top"
					tmr = 0.0
			else:
				hero_w = maxf(0.0, hero_w - hero_fade * dt)
				_hero_pose(hero_w)
				if tmr > 2.6:
					d.end_after(t, 0.5)

func _stomp_begin(e: Dictionary, t: float) -> void:
	st.victim = e.c
	mode = "anger"
	tmr = 0.0
	d.mark("anger", t)

## Up off the street and down onto the roof of the one behind him.
func _stomp_launch(t: float) -> void:
	var c: Dictionary = st.victim
	var cm: Dictionary = man.meta.gap_jump
	var hips0 := _hips()
	var roof := float(st.y) + float(c.size.y) * 0.95
	var y1 := roof + man.clip_hips("gap_jump", float(cm.land)).y
	var top := roof + 2.4
	var vy := sqrt(2.0 * GS * maxf(top - hips0.y, 0.5))
	var T := vy / GS + sqrt(2.0 * maxf(top - y1, 0.05) / GS)
	var to := Vector3(c.pos.x - hips0.x, 0.0, c.pos.y - hips0.z)
	man.yaw = atan2(to.x, to.z)
	man.jump("gap_jump", float(cm.takeoff) - 0.04, 0.08)
	man.jump_rate = 1.0
	fl = {"hips0": hips0, "vh": to / T, "vy": vy, "T": T}
	mode = "stomp_air"
	tmr = 0.0
	fx.burst("puff", Vector3(hips0.x, float(st.y), hips0.z), Vector3.UP)
	d.mark("launch_s", t)

## Where along the street and how far to its side he now is.
func _street_resync() -> void:
	var q := Vector2(man.position.x, man.position.z) - (st.p0 as Vector2)
	st_s = q.dot(st.dir)
	st_off = q.dot(st.n)

## He answers a car: a side step or a dive and roll (each with a push out of its way), a leap over it, a foot on
## its roof, a kick, ducking behind a car.
func _street_move(e: Dictionary, t: float) -> void:
	e.done = true
	tmr = 0.0
	var side := 1.0 if (int(e.i) % 2) == 1 else -1.0
	var n3 := Vector3(st.n.x, 0.0, st.n.y)
	match e.what:
		"step", "crash2":
			var c := "dodge_l" if side > 0.0 else "dodge_r"
			man.jump(c, -1.0, 0.15)
			var s := _dodge_side(c, 0.0, side)
			st.push = n3 * s * 2.3
			st.push_s = s
			mode = "dodge"
			d.mark("dodge_%d" % e.i, t)
		"dive":
			man.jump("dive_roll", -1.0, 0.15)
			man.yaw += side * 0.5
			var s := _dodge_side("dive_roll", side * 0.5, side)
			st.push = n3 * s * 1.6
			st.push_s = s
			mode = "dodge"
			d.mark("dive_%d" % e.i, t)
		"vault", "roofstep":
			var foot := 0 if fposmod(man.phase - toe[0], 1.0) < 0.5 else 1
			var c := "gap_jump" if foot == 0 else "gap_jump_r"
			var hips0 := _hips()
			var dir: Vector2 = st.dir
			var vy := 6.0
			var T := 2.0 * vy / 9.81
			if e.what == "roofstep":
				# up to its roof just as it gets to him
				var tau := maxf(float(e.t) - st_t, 0.2)
				vy = (float(st.y) + float(e.c.size.y) + 1.05 - hips0.y + 4.905 * tau * tau) / tau
				T = tau
			man.jump(c, float(man.meta[c].takeoff), 0.12)
			fl = {"clip": c, "hips0": hips0, "vh": Vector3(dir.x, 0.0, dir.y) * maxf(man.speed, 5.0), "vy": vy, "T": T,
				"step2": e.what == "roofstep"}
			mode = "vault"
			d.mark("vault_%d" % e.i, t)
		"kick":
			# planted, facing it: the kick lands as it arrives
			man.jump("kick", 0.0, 0.18)
			man.yaw = atan2(st.dir.x, st.dir.y)
			_street_resync()
			e.s_meet = st_s + 0.9 + float(e.c.size.x) * 0.5
			e.fixed = true
			st.stop = st_s
			mode = "kick"
			var cp := _street_at(st_s + 0.9, st_off)
			kick_cam = {"at": Vector3(cp.x, float(st.y), cp.y)}
			d.mark("plant", t)
		"hide":
			man._play(Man.CROUCH_IN, "crouch_in", 0.0, 0.25)
			man.speed = 0.0
			mode = "hide"
			d.mark("duck", t)

## The first car the camera should be watching for: the next one to get to him (or the one just done, a moment more).
func _cam_entry() -> Dictionary:
	for e in cars_on:
		if e.what in ["brake", "crash2_h", "shield"] or e.past:
			continue
		if e.has("past_at") and st_t > float(e.past_at) + 1.0:
			continue
		return e
	return {}

## The cars: each from where it waited, timed to reach him at its moment (off as late as it can, flat out as it gets
## there; the last one, and the one he hides behind, braking to a stop); then whatever it runs into.
func _street_cars(dt: float, t: float) -> void:
	var dir: Vector2 = st.dir
	var nv: Vector2 = st.n
	var kick_at := 99.0
	for e in cars_on:
		if e.what == "kick":
			kick_at = float(e.t) - float(man.meta.kick.hit) - 0.05
	var stop_pred: float = float(st.get("stop", st_s + SPRINT * maxf(kick_at - st_t, 0.0)))
	for e in cars_on:
		var c: Dictionary = e.c
		if c.state != "driven":
			continue
		var tm: float = e.t
		var left := tm - st_t
		if e.what == "hide" and e.has("shield"):
			# at the car he is hiding behind, nose to nose
			var sh: Dictionary = e.shield
			e.s_meet = float(sh.s_meet) + float(sh.c.size.x) * 0.5 + float(c.size.x) * 0.5
			e.lane = sh.lane
		elif not e.fixed and (left > 0.8 or e.what == "kick" or e.what == "brake"):
			# aimed at where he will be when it gets there (the kick and the one behind: where he stops)
			var aim := st_s + SPRINT * left
			if e.what == "kick":
				aim = stop_pred + 0.9 + float(c.size.x) * 0.5
			elif e.what == "brake":
				aim = stop_pred - 5.5
			elif e.what == "shield":
				aim = st_s + SPRINT * maxf(left + 1.0, 0.0) + float(c.size.x) * 0.5 + 0.75
			e.s_meet = aim if not e.get("aimed", false) else lerpf(float(e.s_meet), aim, 1.0 - exp(-dt / 0.35))
			e.aimed = true
			e.lane = st_off
		elif not e.fixed:
			e.fixed = true
		var v: float = e.v
		var D: float = float(e.s_meet) - float(e.start)
		var L := maxf(absf(D), 0.01)
		var along: float
		var x := 1.0
		if e.has("skid"):
			var tau := minf(st_t - float(e.skid[1]), v / 9.0)
			along = float(e.skid[0]) + float(e.from) * (v * tau - 4.5 * tau * tau)
		elif e.what == "brake" or e.what == "shield":
			var T := maxf(minf(1.5 * L / v, tm), 0.05)
			x = (st_t - (tm - T)) / T
			var xc := clampf(x, 0.0, 1.0)
			along = float(e.start) + D * xc * xc * (3.0 - 2.0 * xc)
		else:
			var T := maxf(minf(2.0 * L / v, tm), 0.05)
			var a := clampf(2.0 - v * T / L, 0.0, 1.0)
			x = (st_t - (tm - T)) / T
			var f: float
			if x <= 1.0:
				var xc := maxf(x, 0.0)
				f = a * xc + (1.0 - a) * xc * xc
			else:
				f = 1.0 + (2.0 - a) * (x - 1.0)
			along = float(e.start) + D * f
		var heading := dir * float(e.from)
		var p := _street_at(along, lerpf(float(e.lane0), float(e.lane), _ease(x * 1.6)))
		c.pos = p
		c.yaw = atan2(-heading.y, heading.x)
		c.y = float(st.y)
		g.veh._apply(c)
		if absf(along - st_s) < 4.0 and not e.has("passed_mark") and e.what != "brake" and e.what != "shield":
			e.passed_mark = true
			d.mark("pass_%d" % e.i, t)
		match e.what:
			"kick":
				if left <= 0.0 and mode == "kick":
					var hit := Vector3(p.x, float(st.y) + 0.9, p.y) - Vector3(dir.x, 0.0, dir.y) * float(c.size.x) * 0.5
					g.veh.knock(c, dir, 1.7)
					fx.burst("impact", hit, Vector3(dir.x, 0.6, dir.y))
					shake = maxf(shake, 0.45)
					kick_cam.car = c
					kick_cam.k_tmr = tmr
					d.mark("kick", t)
					score += 200
			"hit":
				if left <= float(c.size.x) * 0.5 / v and mode == "street" and not e.has("skid"):
					# it gets him (its nose, not its middle): thrown along its way and up
					fx.burst("impact", _hips(), Vector3(heading.x, 0.5, heading.y))
					shake = maxf(shake, 0.5)
					kick_cam = {"at": Vector3(p.x, float(st.y), p.y) + Vector3(heading.x, 0.0, heading.y) * 3.0, "hit": true}
					var sgh := 1.0 if randf() < 0.5 else -1.0
					c.state = "parked"
					g.veh.shove(c, heading * v * 0.5 + nv * sgh * 7.0, 2.0 * sgh)
					d.mark("hit", t)
					man.yaw = atan2(heading.x, heading.y)
					_thrown(Vector3(heading.x, 0.0, heading.y) * v * 0.7 + Vector3(0, 5.5, 0), 9.81, 1.0, float(st.y), _hips())
			"crash2":
				var pr = e.get("pair")
				if pr != null and not e.has("bang") and left <= (float(c.size.x) + float(pr.c.size.x)) * 0.5 / (v + float(pr.v)):
					# the two of them, head on, where he was
					e.bang = true
					e.past_at = st_t
					var away := -float(st.get("push_s", 1.0))
					var mid := Vector3(p.x, float(st.y) + 0.8, p.y) + Vector3(dir.x, 0.0, dir.y) * float(c.size.x) * 0.5
					g.veh.knock(c, (dir + nv * away * 0.6).normalized(), 1.0)
					g.veh.knock(pr.c, (-dir + nv * away * 0.6).normalized(), 1.0)
					fx.burst("impact", mid, Vector3(nv.x * away, 0.6, nv.y * away))
					shake = maxf(shake, 0.5)
					d.mark("crash2", t)
					score += 150
					if e.has("missed"):
						_thrown(Vector3(nv.x, 0.0, nv.y) * away * -6.0 + Vector3(0, 5.0, 0), 9.81, 1.0, float(st.y), _hips())
			"pole":
				if left <= 0.0 and not e.has("bang"):
					e.bang = true
					e.past_at = st_t
					var pl: Vector2 = e.pole
					var pp := _street_at(pl.x, pl.y)
					g.veh.knock(c, (dir + nv * signf(pl.y) * 0.5).normalized(), 0.9)
					fx.burst("impact", Vector3(pp.x, float(st.y) + 0.9, pp.y), Vector3(-dir.x, 0.5, -dir.y))
					shake = maxf(shake, 0.35)
					d.mark("polehit", t)
					score += 100
			"hide":
				if left <= 0.0 and e.has("shield") and not e.has("bang"):
					# it rams the car he is behind, which goes skidding off, and goes over him
					e.bang = true
					e.past_at = st_t
					st.hide_hit = st_t
					var sc: Dictionary = e.shield.c
					var sg := 1.0 if randf() < 0.5 else -1.0
					sc.state = "parked"
					g.veh.shove(sc, nv * sg * 7.5 - dir * 1.0, 2.2 * sg)
					g.veh.knock(c, -dir, 1.3)
					fx.burst("impact", Vector3(p.x, float(st.y) + 0.8, p.y) - Vector3(dir.x, 0.0, dir.y) * float(c.size.x) * 0.5, Vector3(-dir.x, 0.6, -dir.y))
					shake = maxf(shake, 0.5)
					d.mark("smash", t)
					score += 150
					if st.get("hide_missed", false):
						_thrown(Vector3(-dir.x, 0.0, -dir.y) * 5.0 + Vector3(0, 4.5, 0), 9.81, -1.0, float(st.y), _hips())
			"step", "dive", "vault", "roofstep":
				if left < -0.7 and not e.past:
					# past him: it spins out
					e.past = true
					c.state = "parked"
					var away := signf(float(e.lane) - st_off)
					if away == 0.0:
						away = 1.0 if randf() < 0.5 else -1.0
					g.veh.shove(c, heading * v * 0.6 + nv * away * randf_range(6.0, 7.5), randf_range(1.6, 2.8) * away)
					d.mark("spin_%d" % e.i, t)

# ---------------------------------------------------------------- thrown: hit by a car, or off a wall
## Thrown: turning over (whole turns, so he comes down the right way up), down hard, rolls with it and gets up.
func _thrown(vel: Vector3, gr: float, sgn: float, floor_y: float, hips: Vector3) -> void:
	if play:
		lives -= 1
		ask = {}
		_say("OUCH!  -1 ♥" if lives > 0 else "WIPED OUT")
	man.jump("gap_jump", 0.86, 0.06)
	man.jump_rate = 0.0
	var T := (vel.y + sqrt(maxf(vel.y * vel.y + 2.0 * gr * maxf(hips.y - floor_y - 0.45, 0.0), 0.0))) / gr
	fl = {"clip": "gap_jump", "fall_p": hips, "fall_v": vel, "g": gr, "floor": floor_y, "sgn": sgn,
		"spin": TAU * maxf(1.0, roundf(T * 6.0 / TAU)) / maxf(T, 0.1)}
	mode = "thrown"
	tmr = 0.0

func _thrown_step(dt: float, t: float) -> void:
	if mode == "thrown":
		var v: Vector3 = fl.fall_v
		v.y -= float(fl.g) * dt
		fl.fall_v = v
		fl.fall_p = (fl.fall_p as Vector3) + v * dt
		man.position = (fl.fall_p as Vector3) - Basis(Vector3.UP, man.yaw) * man.clip_hips(fl.clip, man.ct)
		man.rotation.y = man.yaw
		man.animate(dt)
		var hl := man.skel.get_bone_pose_position(0)
		var B := Basis(Vector3.RIGHT, tmr * float(fl.spin) * float(fl.sgn))
		man.body.transform = Transform3D(B, hl - B * hl)
		if (fl.fall_p as Vector3).y <= float(fl.floor) + 0.45 and v.y < 0.0:
			# down: it cracks the ground; he rolls with it, the way he was going, and comes up on his feet
			man.body.transform = Transform3D()
			var at := Vector3(man.position.x, float(fl.floor), man.position.z)
			impact(at, 0.9, float(fl.floor))
			shake = 0.5
			d.mark("crash", t)
			if Vector2(v.x, v.z).length() > 0.3:
				man.yaw = atan2(v.x, v.z)
			man.jump("dive_roll", float(man.meta.dive_roll.get("land", 0.9)) + 0.05, 0.1)
			mode = "getup"
			tmr = 0.0
			kick_cam.getup = at
		return
	var step := man.move(dt, Vector2(), 0.0, false)
	man.position += step
	man.position.y = float(fl.floor)
	man.rotation.y = man.yaw
	man.animate(dt)
	if man.state == Man.JUMP and man.ct >= man._len("dive_roll") - 0.45:
		man._to(Man.IDLE, 0.45)
		man.speed = 0.0
		man.idle_t = 0.0
	if play and lives > 0 and not st.is_empty():
		if tmr > 2.2:
			_street_resync()
			mode = "street"
			tmr = 0.0
		return
	if tmr > 0.9 and not d.events.has("fail"):
		d.mark("fail", t)
	if tmr > 3.4:
		d.end_after(t, 0.2)

# ---------------------------------------------------------------- slow motion and the camera
## The time scale wanted now: slow in the crouch, the flip and the impact, full speed in between, eased.
func step(t: float) -> void:
	if route.is_empty():
		return
	var want := 1.0
	var m: Dictionary = route[mini(mi, route.size() - 1)]
	if chase:
		match mode:
			"kick":
				var k := man.ct - float(man.meta.kick.hit)
				if k > -0.16 and k < 0.45:
					want = 0.35
			"thrown":
				want = 0.4 if tmr < 0.3 else 1.0
			"stomp":
				want = 0.4 if tmr < 0.35 else 1.0
	if play and d.now() < perfect_until:
		want = minf(want, 0.5)
	elif m.slow and not chase:
		match mode:
			"air":
				if fl.super:
					var x: float = tmr / float(fl.T)
					if m.kind == "mega" and x > 0.3 and x < 0.6:
						want = 0.4
					elif m.kind == "drop" and x > 0.9:
						want = 0.3
			"hero":
				want = 0.35 if tmr < 0.35 else 1.0
	var cur := Engine.time_scale
	Engine.time_scale = move_toward(cur, want, 3.5 / float(d.fps))
	if Engine.time_scale < 0.6 and not slowed:
		slowed = true
		slow_n += 1
		d.mark("slow_on_%d" % slow_n, t)
		AudioServer.set_bus_volume_db(0, -16.0)
	elif Engine.time_scale >= 0.6 and slowed:
		slowed = false
		d.mark("slow_off_%d" % slow_n, t)
		AudioServer.set_bus_volume_db(0, 0.0)

## Which camera: behind him running; low beside him as he crouches and blasts off; round him through the flip;
## on the far roof as he comes down; from above the edge as he dives off; at the foot of it as he lands.
func cut(_t: float) -> String:
	if route.is_empty():
		return "game"
	var m: Dictionary = route[mini(mi, route.size() - 1)]
	var shot := "sr_chase"
	if chase:
		shot = _chase_cut(m)
	else:
		shot = _run_cut(m)
	var key := mi * 20 + SHOTS.find(shot)
	if key != cam_move:
		cam_move = key
		d.last_mode = ""
	return shot

const SHOTS := ["sr_chase", "sr_launch", "sr_after", "sr_hop", "sr_orbit", "sr_land", "sr_dive", "sr_ground",
	"sc_air", "sc_front", "sc_back", "sc_kick", "sc_fall", "sc_getup", "sc_side", "sc_face", "sc_stomp", "sc_top"]

## The chase: behind him on the roofs and through the air; the street drop seen from below; in the street ahead
## of him looking back while a car comes up behind, behind him while one comes at him; beside the kick (or the hit).
func _chase_cut(m: Dictionary) -> String:
	match mode:
		"run", "crouch":
			return "sr_chase"
		"air":
			if m.has("street") and tmr / float(fl.T) > 0.6:
				return "sr_ground"
			return "sc_air"
		"land":
			return "sc_air"
		"thrown":
			return "sc_kick" if not st.is_empty() else "sc_fall"
		"getup":
			return "sc_getup"
		"hero", "end":
			return "sr_ground"
		"kick", "after":
			return "sc_kick"
		"hide":
			return "sc_back"
		"anger":
			return "sc_face"
		"crouch2", "stomp_air":
			return "sc_stomp"
		"stomp":
			return "sc_stomp" if tmr < 0.5 else "sc_top"
		"top":
			return "sc_top"
	var e := _cam_entry()
	if e.is_empty():
		return "sc_back"
	if e.what == "crash2" and float(e.t) - st_t < 2.0:
		return "sc_side"
	return "sc_front" if int(e.from) > 0 else "sc_back"

func _run_cut(m: Dictionary) -> String:
	var shot := "sr_chase"
	match mode:
		"run":
			if m.kind == "mega" and float(seg.len) - s < 3.5:
				shot = "sr_launch"
			elif tmr < 0.7 and mi > 0:
				shot = "sr_after"
		"crouch":
			shot = "sr_launch"
		"air":
			var x: float = tmr / float(fl.T)
			if not fl.super:
				shot = "sr_hop"
			elif m.kind == "mega":
				shot = "sr_launch" if x < 0.18 else ("sr_orbit" if x < 0.72 else "sr_land")
			else:
				shot = "sr_dive" if x < 0.22 else ("sr_orbit" if x < 0.66 else "sr_ground")
		"land":
			shot = "sr_hop" if m.kind == "hop" else "sr_land"
		"hero", "end":
			shot = "sr_ground"
	return shot

## [where the camera is, what it looks at, its field of view] for a shot.
func camera(mode_name: String, t: float) -> Array:
	var m: Dictionary = route[mini(mi, route.size() - 1)]
	var hips := man.skel.global_transform * man.skel.get_bone_global_pose(0).origin
	var u := Vector3(m.u.x, 0.0, m.u.y)
	var n := Vector3(-u.z, 0.0, u.x)
	var take := Vector3(m.take.x, float(m.h_from), m.take.y)
	var land := Vector3(m.land.x, float(m.h_to), m.land.y)
	var pos := Vector3()
	var look := Vector3()
	var fov := 66.0
	match mode_name:
		"sr_chase", "sr_after":
			var h := Vector3(sin(man.yaw), 0.0, cos(man.yaw))
			pos = hips - h * 3.4 + Vector3(-h.z, 0.0, h.x) * 0.7 + Vector3(0, 1.0, 0)
			pos.y = maxf(pos.y, float(seg.get("h", 0.0)) + 1.1)
			look = hips + h * 6.0 + Vector3(0, 0.1, 0)
			fov = 72.0
		"sr_launch":
			# low on the roof, ahead of him and to the side: he sinks down and blasts up out of frame-top
			pos = take + u * 3.2 + n * 2.6 + Vector3(0, 0.45, 0)
			look = hips.lerp(take + Vector3(0, 1.0, 0), 0.25)
			fov = 70.0
		"sr_orbit":
			# round him as he turns over, slowly, the city far below
			# (off a building, round the open side of him only: the half facing the way he leapt)
			var a0 := atan2(u.z, u.x)
			var a := a0 + clampf(-1.3 + tmr * 2.2, -1.4, 1.4)
			pos = hips + Vector3(cos(a), 0.0, sin(a)) * 5.5 + Vector3(0, 0.9, 0)
			look = hips
			fov = 62.0
		"sr_land":
			# on the roof ahead of where he lands, low, looking back up at him coming down
			pos = land + u * 4.6 + n * 1.8 + Vector3(0, 0.55, 0)
			look = hips.lerp(land + Vector3(0, 1.0, 0), 0.3)
			fov = 68.0
		"sr_dive":
			# out past the edge and above it, looking down past him at where he is going
			pos = take + u * 2.4 + n * 1.6 + Vector3(0, 3.2, 0)
			look = hips.lerp(land, 0.55)
			fov = 72.0
		"sr_ground":
			# at the foot of it, low, out ahead and to the side of where he lands, a wide lens: he falls into it
			pos = land + u * 5.5 + n * 4.5 + Vector3(0, 0.5, 0)
			look = hips.lerp(land + Vector3(0, 0.9, 0), 0.3)
			fov = 76.0
		"sc_air":
			# behind him and a little above, looking the way he is going
			var vy: float = float(fl.vy) - float(fl.g) * minf(tmr, float(fl.T)) if mode == "air" else 0.0
			pos = hips - u * 4.0 + n * 0.6 + Vector3(0, 1.5, 0)
			pos.y = maxf(pos.y, (float(m.h_to) if mode == "land" else float(m.h_from)) + 1.2)
			look = hips + u * 5.0 + Vector3(0, clampf(vy * 0.2, -3.0, 3.0) - 0.3, 0)
			fov = 72.0
		"sc_fall":
			# where the camera was as he hit the wall: he falls away below it
			if not kick_cam.has("fall"):
				kick_cam.fall = d.cam_p
			pos = kick_cam.fall
			look = hips
			fov = 70.0
		"sc_front", "sc_back":
			var sd := Vector3(st.dir.x, 0.0, st.dir.y)
			var sn := Vector3(st.n.x, 0.0, st.n.y)
			var at := Vector3(hips.x, float(st.y), hips.z)
			if mode_name == "sc_front":
				# ahead of him, low, looking back past him at what is coming up behind
				pos = at + sd * 5.5 + sn * 2.4 + Vector3(0, 1.0, 0)
				look = at - sd * 4.0 + Vector3(0, 0.9, 0)
			else:
				# behind him, low, a wide lens: what is coming at him over his shoulder
				pos = at - sd * 4.6 + sn * 2.4 + Vector3(0, 1.5, 0)
				look = at + sd * 7.0 + Vector3(0, 0.8, 0)
			fov = 74.0
		"sc_kick":
			var sd := Vector3(st.dir.x, 0.0, st.dir.y)
			var sn := Vector3(st.n.x, 0.0, st.n.y)
			var at: Vector3 = kick_cam.get("at", hips)
			var from := at + Vector3(0, 1.0, 0)
			if kick_cam.has("hit"):
				# fixed beside where the car gets him
				if not kick_cam.has("pos"):
					kick_cam.pos = d.pulled(from, at + sn * 5.2 - sd * 1.2 + Vector3(0, 1.1, 0))
				pos = kick_cam.pos
				look = hips
				fov = 64.0
			else:
				# low over his shoulder, swinging round to his side and pushing in as the car comes (in slow
				# motion), then after the car as it goes end over end
				if not kick_cam.has("side"):
					var room := 0.0
					kick_cam.side = 0.0
					for sg in [1.0, -1.0]:
						var q: Vector3 = d.pulled(from, at + sn * sg * 4.8 + Vector3(0, 1.0, 0))
						if q.distance_to(from) > maxf(room + 0.3, 3.5):
							room = q.distance_to(from)
							kick_cam.side = sg
				var sg: float = kick_cam.side
				var k := _ease(tmr / 1.3)
				var a0 := Vector2(-3.6, 1.3)
				var a1 := Vector2(-0.4, 4.6) if sg != 0.0 else Vector2(-4.4, 0.9)
				var ang := lerp_angle(a0.angle(), a1.angle(), k)
				var o := Vector2(cos(ang), sin(ang)) * lerpf(a0.length(), a1.length(), k)
				pos = d.pulled(from, at + sd * o.x + sn * o.y * (sg if sg != 0.0 else 1.0) + Vector3(0, lerpf(0.55, 0.85, k), 0))
				look = at + Vector3(0, 0.9, 0) + sd * 1.2
				fov = lerpf(62.0, 50.0, k)
				if kick_cam.has("car"):
					var cp: Vector3 = g.veh.xform(kick_cam.car).origin + Vector3(0, 0.6, 0)
					var kk := _ease((tmr - float(kick_cam.k_tmr)) / 0.7)
					look = look.lerp(cp, kk * 0.45)
					look.y = minf(look.y, hips.y + 2.0)
					fov = lerpf(fov, 66.0, kk)
		"sc_side":
			# beside the street, square on to where the two of them will meet
			var e := _cam_entry()
			var key := "side_%d" % int(e.get("i", 0))
			if not kick_cam.has(key):
				var a2 := _street_at(float(e.get("s_meet", st_s)), float(e.get("lane", st_off)))
				var at := Vector3(a2.x, float(st.y), a2.y)
				var sn := Vector3(st.n.x, 0.0, st.n.y)
				var sd := Vector3(st.dir.x, 0.0, st.dir.y)
				var bp := at + Vector3(0, 5.0, 0) - sd * 6.0
				var room := 0.0
				for sg in [1.0, -1.0]:
					var q: Vector3 = d.pulled(at + Vector3(0, 1.2, 0), at + sn * sg * 8.0 - sd * 1.5 + Vector3(0, 1.4, 0))
					if q.distance_to(at) > room:
						room = q.distance_to(at)
						bp = q
				kick_cam[key] = [bp, at]
			pos = kick_cam[key][0]
			look = (kick_cam[key][1] as Vector3) + Vector3(0, 0.8, 0)
			fov = 64.0
		"sc_face":
			# close on his face, from between him and the car he is about to crush
			var cp: Vector2 = st.victim.pos
			var head := hips + Vector3(0, 0.62, 0)
			var f := Vector3(cp.x - head.x, 0.0, cp.y - head.z).normalized()
			pos = head + f * 1.3 + Vector3(-f.z, 0.0, f.x) * 0.3
			look = head
			fov = 40.0
		"sc_stomp":
			# off to the side, low: up off the street and down onto it
			var c: Dictionary = st.victim
			var cp := Vector3(c.pos.x, float(st.y), c.pos.y)
			if not kick_cam.has("stomp"):
				var mid := (Vector3(man.position.x, float(st.y), man.position.z) + cp) * 0.5
				var sn := Vector3(st.n.x, 0.0, st.n.y)
				var bp := mid + Vector3(0, 6.0, 0)
				var room := 0.0
				for sg in [1.0, -1.0]:
					var q: Vector3 = d.pulled(mid + Vector3(0, 1.2, 0), mid + sn * sg * 7.0 + Vector3(0, 1.8, 0))
					if q.distance_to(mid) > room:
						room = q.distance_to(mid)
						bp = q
				kick_cam.stomp = bp
			pos = kick_cam.stomp
			look = hips.lerp(cp + Vector3(0, 1.2, 0), 0.35)
			fov = 60.0
		"sc_top":
			# round him, standing on the wreck
			var a: float = float(kick_cam.get("top_a", 0.0)) + (d.now() - float(kick_cam.get("top_t0", d.now()))) * 0.5
			if not kick_cam.has("top_a"):
				kick_cam.top_a = atan2(d.cam_p.z - hips.z, d.cam_p.x - hips.x)
				kick_cam.top_t0 = d.now()
			pos = d.pulled(hips + Vector3(0, 0.5, 0), hips + Vector3(cos(a), 0.0, sin(a)) * 5.0 + Vector3(0, 0.9, 0))
			look = hips + Vector3(0, 0.15, 0)
			fov = 60.0
		"sc_getup":
			# low, a few metres off, where he came down: he rolls and gets up
			var at: Vector3 = kick_cam.get("getup", hips)
			if not kick_cam.has("gpos"):
				var f := Vector3(sin(man.yaw), 0.0, cos(man.yaw))
				var sdv := Vector3(-f.z, 0.0, f.x)
				kick_cam.gpos = d.pulled(at + Vector3(0, 1.0, 0), at + f * 3.2 + sdv * 3.0 + Vector3(0, 1.1, 0))
			pos = kick_cam.gpos
			look = hips + Vector3(0, 0.1, 0)
			fov = 58.0
		"sr_hop":
			# beside the edge, low on the lower roof
			var lo := minf(float(m.h_from), float(m.h_to))
			var e := Vector3(m.edge.x, lo, m.edge.y)
			pos = e + n * 4.0 + u * 2.4 + Vector3(0, 0.8, 0)
			look = hips.lerp(e + Vector3(0, 1.2, 0), 0.3)
			fov = 64.0
	# never inside a building: pulled in short of the first wall between him and the camera
	if mode_name in ["sc_front", "sc_back"]:
		pos = d.pulled(Vector3(hips.x, float(st.y) + 1.0, hips.z), pos)
	elif (mode_name.begins_with("sr_") and mode_name != "sr_chase" and mode_name != "sr_after") or mode_name == "sc_air":
		pos = d.pulled(hips, pos)
	# the shake of a hard landing
	if shake > 0.0:
		var tt: float = d.now()
		pos += Vector3(sin(tt * 61.0), sin(tt * 53.0 + 1.3), sin(tt * 47.0 + 2.1)) * shake * 0.35
	return [pos, look, fov]

# ---------------------------------------------------------------- the Superhero Run: prompts and answers
func _ask(gst: String, window: float, roof := false) -> void:
	ask = {"g": gst, "ok": false, "t0": d.now(), "t1": d.now() + maxf(window, 0.3)}
	# (testing: every edge, and three cars in four, answered)
	if d.autoplay and (roof or randf() < 0.75):
		gesture(gst, d.now() + maxf(window, 0.3) * 0.7)

## A swipe or tap from the player: the right one, while asked, does it (late in the window: perfect).
func gesture(gst: String, at: float) -> void:
	if ask.is_empty() or ask.ok or gst != ask.g:
		return
	ask.ok = true
	rage = minf(rage + 0.25, 1.0)
	var k := (at - float(ask.t0)) / maxf(float(ask.t1) - float(ask.t0), 0.01)
	if k > 0.6:
		score += 200
		perfect_until = at + 0.6
		_say("PERFECT!")
	else:
		score += 100
		_say("NICE")

func _say(text: String) -> void:
	flash = text
	flash_until = d.now() + 1.0

## The moment of a street move: done if he was told in time, gone wrong if not.
func _answer(e: Dictionary, t: float) -> void:
	if not play or ask.get("ok", false):
		ask = {}
		_street_move(e, t)
		return
	ask = {}
	e.done = true
	_say("TOO LATE!")
	match e.what:
		"crash2":
			e.missed = true
		"hide":
			st.hide_missed = true
			man.speed = 0.0
			mode = "hide"
			tmr = 0.0
		_:
			e.what = "hit"

## Too late at the edge: he runs off it and falls.
func _miss_edge(t: float, m: Dictionary) -> void:
	ask = {}
	lives = 1
	var h := _hips()
	var floor_y: float = minf(float(m.h_to), float(m.h_from)) if float(m.gap) < 1.5 else g.world.ground_at(h.x + m.u.x * 3.0, h.z + m.u.y * 3.0, 0.0)
	_thrown(Vector3(m.u.x, 0.0, m.u.y) * 3.5 + Vector3(0, 1.5, 0), 9.81, 1.0, floor_y, h)
	d.mark("wallhit", t)
