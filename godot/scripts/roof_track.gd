## The Roof Run's world, built ahead of him as he runs and cleared away behind (scripts/roof_run.gd plays it).
## Everything is placed on a path, in path coordinates: s metres along it, x metres to its right (the lanes are
## x = -2.4, 0, 2.4) and y up. The path is straight lines joined by quarter turns, which only happen on the roof of
## a corner building; it heads north, east or west, never back south, so it never runs into itself.
## It goes round and round for as long as he lasts:
##   roofs: buildings end to end, a gap (an alley) or a step up or down between them, now and then a corner
##          building where the path turns left or right; on the roofs, air units and fences to leap, pipes to roll
##          under, water tanks to step round, and coins;
##   the drop: the last roof ends over a street; he leaps (or just runs) off it and lands in the street;
##   the street: parked cars, cars coming at him, slow ones going his way, barriers and gantries;
##   the launch: a glowing pad near the end of the street throws him up onto the next roofs.
## Every row of things in his way leaves him a way through (a free lane, or a leap or a roll that clears it), with
## room before the next to react; the further he gets the faster he runs and the closer they come.
class_name RoofTrack
extends Node3D

const LANES := [-2.4, 0.0, 2.4]
const AHEAD := 240.0         # built this far ahead of him
const BEHIND := 45.0         # cleared once this far behind
const CORNER := 8.0          # half the size of a corner building (the radius of the turn on its roof)
const JUMP_V := 9.5          # his leap: up at this speed ...
const GRAV := 22.0           # ... against this gravity (a game's, not the real one: snappy)
const STEP := 0.45           # he steps up onto anything this much higher without a leap
const PAD := 16.0            # the launch pad, this far before the end of the street
const MODELS := ["agera", "gls"]

var rng := RandomNumberGenerator.new()
var segs: Array = []         # the path: {line: bool, s0, len, p0: Vector2, dir: Vector2} (+ arcs: c, side, r)
var built := 0.0             # the path so far (m)
var dir := Vector2(0, 1)     # the way the path heads at its end
var solids: Array = []       # {s0, s1, x0, x1, y0, y1, kind, v (m/s along s), node}
var near: Array = []         # the solids from a little behind him to 100 m ahead (what the questions look at)
var coins: Array = []        # {s, x, y, node}
var zones: Array = []        # {s0, s1, kind: roof/street}, in order
var beats: Array = []        # {s, kind: drop/launch, h (the roof it lands on), s_land}
var pieces: Array = []       # {s1, nodes: []} to free once he is past
var decor: Array = []        # the buildings beside the path: {rect: Rect2 (world x/z), s1}
var speed_at := Callable()   # his speed at a distance (how close things may come)
var next := "start"          # what to build next
var roof_h := 14.0           # the height of the last roof built
var rows_since_coin := 0
var sec_end := 0.0           # where the current section ends
var onc := 0                 # the street's lane for the traffic coming at him
var onc_v := -8.0            # and its speed
var street_end := 0.0
var after_corner := false
var stats := {roofs = 0, gaps = 0, corners = 0, streets = 0, cars = 0, rows = 0}

# shared looks
var mat_build: ShaderMaterial
var mat_road: ShaderMaterial
var mats := {}
var box_mesh: BoxMesh
var coin_mesh: CylinderMesh
var car_parts := {}          # model -> [[mesh, transform, role, far]]
var car_dims := {}           # model -> Vector3 (length along +x, height, width)
const WALLS := [Color(0.72, 0.62, 0.5), Color(0.62, 0.36, 0.28), Color(0.78, 0.74, 0.66), Color(0.5, 0.52, 0.56),
	Color(0.66, 0.5, 0.38), Color(0.42, 0.46, 0.52), Color(0.82, 0.7, 0.52), Color(0.56, 0.3, 0.26)]
const PAINT := [Color(0.75, 0.05, 0.04), Color(0.95, 0.95, 0.93), Color(0.05, 0.05, 0.06), Color(0.08, 0.2, 0.55),
	Color(0.9, 0.6, 0.05), Color(0.45, 0.47, 0.5), Color(0.05, 0.35, 0.18), Color(0.95, 0.75, 0.05)]

func _init(seed_n: int) -> void:
	rng.seed = seed_n
	name = "Track"

func _ready() -> void:
	mat_build = ShaderMaterial.new()
	mat_build.shader = load("res://shaders/runner_building.gdshader")
	mat_road = ShaderMaterial.new()
	mat_road.shader = load("res://shaders/runner_road.gdshader")
	box_mesh = BoxMesh.new()
	mats.edge = _std(Color(0.95, 0.75, 0.1), 0.6, 0.0, Color(0.5, 0.35, 0.0))
	mats.parapet = _std(Color(0.45, 0.44, 0.42), 0.9)
	mats.metal = _std(Color(0.55, 0.57, 0.6), 0.45, 0.6)
	mats.dark = _std(Color(0.12, 0.12, 0.13), 0.7, 0.2)
	mats.tank = _std(Color(0.42, 0.3, 0.22), 0.85)
	mats.pipe = _std(Color(0.85, 0.35, 0.08), 0.5, 0.3)
	mats.stripe = _std(Color(0.95, 0.95, 0.92), 0.6)
	mats.red = _std(Color(0.85, 0.1, 0.08), 0.6)
	mats.walk = _std(Color(0.5, 0.49, 0.47), 0.9)
	mats.lamp = _std(Color(0.95, 0.95, 0.9), 0.3, 0.0, Color(0.3, 0.3, 0.25))
	mats.pad = _std(Color(0.2, 0.75, 1.0), 0.3, 0.0, Color(0.1, 0.6, 1.0) * 2.5)
	mats.coin = _std(Color(1.0, 0.78, 0.15), 0.25, 0.9, Color(0.6, 0.4, 0.0))
	coin_mesh = CylinderMesh.new()
	coin_mesh.top_radius = 0.32
	coin_mesh.bottom_radius = 0.32
	coin_mesh.height = 0.07
	coin_mesh.radial_segments = 16
	coin_mesh.rings = 1
	_load_cars()

func _std(c: Color, rough: float, metal := 0.0, emi := Color(0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emi != Color(0, 0, 0):
		m.emission_enabled = true
		m.emission = emi
	return m

## The two car models, near and far (the far one is a light stand-in, scripts/world.gd does the same), and their size.
func _load_cars() -> void:
	var drops: Texture2D = load("res://assets/pbr/drops_n.png")
	var paint := ShaderMaterial.new()
	paint.shader = load("res://shaders/car_paint.gdshader")
	paint.set_shader_parameter("drops_tex", drops)
	var glass := paint.duplicate()
	glass.set_shader_parameter("glass", true)
	var far := paint.duplicate()
	far.set_shader_parameter("far", true)
	mats.car = {"paint": paint, "glass": glass, "far": far,
		"chrome": _std(Color(0.75, 0.77, 0.8), 0.22, 1.0), "trim": _std(Color(0.02, 0.02, 0.02), 0.6, 0.2),
		"carbon": _std(Color(0.03, 0.03, 0.035), 0.35, 0.5), "interior": _std(Color(0.03, 0.03, 0.03), 0.8),
		"tire": _std(Color(0.03, 0.03, 0.035), 0.8), "wheel": _std(Color(0.06, 0.06, 0.065), 0.4, 0.6),
		"lens": _std(Color(0.2, 0.22, 0.25), 0.06, 0.6), "head": _std(Color(0.9, 0.9, 0.85), 0.2, 0.3, Color(0.4, 0.4, 0.35)),
		"tail": _std(Color(0.5, 0.02, 0.02), 0.3, 0.0, Color(0.4, 0.0, 0.0))}
	for vm in MODELS:
		car_parts[vm] = []
		var bb := AABB()
		for f in [false, true]:
			var path := "res://assets/vehicles/%s%s.glb" % [vm, "_far" if f else ""]
			var scn: Node3D = load(path).instantiate()
			var first := true
			for n in scn.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var t := _xform_in(mi, scn)
				car_parts[vm].append([mi.mesh, t, String(mi.name), f])
				if not f:
					var b := t * mi.get_aabb()
					bb = b if first else bb.merge(b)
					first = false
			scn.free()
		car_dims[vm] = Vector3(bb.size.x, bb.end.y, bb.size.z)

func _xform_in(n: Node3D, top: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != top:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

# ---------------------------------------------------------------- the path
func _seg_at(s: float) -> Dictionary:
	var lo := 0
	var hi := segs.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(segs[mid].s0) <= s:
			lo = mid
		else:
			hi = mid - 1
	return segs[lo]

static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)

## The way the path heads at s.
func dir_at(s: float) -> Vector2:
	var g := _seg_at(s)
	if g.line:
		return g.dir
	var a := clampf(s - float(g.s0), 0.0, float(g.len)) / float(g.r) * -float(g.side)
	return (g.dir as Vector2).rotated(-a)

func yaw_at(s: float) -> float:
	var d := dir_at(s)
	return atan2(d.x, d.y)

## The point s along the path, x to its right, y up (world).
func world(s: float, x := 0.0, y := 0.0) -> Vector3:
	var g := _seg_at(s)
	var p: Vector2
	var d: Vector2
	if g.line:
		d = g.dir
		p = (g.p0 as Vector2) + d * (s - float(g.s0))
	else:
		d = dir_at(s)
		p = (g.c as Vector2) - right_of(d) * float(g.r) * float(g.side)
	p += right_of(d) * x
	return Vector3(p.x, y, p.y)

## A transform at s, x, y facing along the path (or back along it).
func frame(s: float, x := 0.0, y := 0.0, back := false) -> Transform3D:
	var yaw := yaw_at(s) + (PI if back else 0.0)
	return Transform3D(Basis(Vector3.UP, yaw), world(s, x, y))

func _line(len: float) -> Dictionary:
	var p0 := Vector2(0, 0) if segs.is_empty() else _end_point()
	var g := {line = true, s0 = built, len = len, p0 = p0, dir = dir}
	segs.append(g)
	built += len
	return g

## A quarter turn on a corner building: side +1 turns right, -1 left.
func _arc(side: float) -> Dictionary:
	var p0 := _end_point()
	var c := p0 + right_of(dir) * CORNER * side
	var g := {line = false, s0 = built, len = PI * 0.5 * CORNER, p0 = p0, dir = dir, c = c, side = side, r = CORNER}
	segs.append(g)
	built += float(g.len)
	dir = right_of(dir) * side
	return g

func _end_point() -> Vector2:
	var w := world(built - 0.0001) if not segs.is_empty() else Vector3()
	return Vector2(w.x, w.z)

# ---------------------------------------------------------------- building it
## Builds on until the path reaches `upto`, and clears what is behind `behind`.
func update(upto: float, behind: float) -> void:
	var guard := 0
	while built < upto + AHEAD and guard < 40:
		guard += 1
		_build_next()
	while not pieces.is_empty() and float(pieces[0].s1) < behind - BEHIND:
		for n in pieces[0].nodes:
			if is_instance_valid(n):
				n.queue_free()
		pieces.pop_front()
	var keep: Array = []
	for o in solids:
		if float(o.s1) >= behind - BEHIND - 10.0:
			keep.append(o)
		elif o.has("node") and is_instance_valid(o.node):
			o.node.queue_free()
	solids = keep
	var kc: Array = []
	for c in coins:
		if float(c.s) >= behind - 5.0:
			kc.append(c)
		elif is_instance_valid(c.node):
			c.node.queue_free()
	coins = kc
	while decor.size() > 80:
		decor.pop_front()
	near_to(behind)

## Picks out the solids near s (from 6 m behind to 100 m ahead): every question below looks only at those.
func near_to(s: float) -> void:
	near = []
	for o in solids:
		if float(o.s1) >= s - 6.0 and float(o.s0) <= s + 100.0:
			near.append(o)

func _speed(s: float) -> float:
	return speed_at.call(s) if speed_at.is_valid() else 8.0

func _build_next() -> void:
	match next:
		"start":
			zones.append({s0 = 0.0, s1 = INF, kind = "roof"})
			_building(46.0, 14.0, 12.0, false)
			# (the first roofs a little shorter: the street comes sooner)
			sec_end = built + rng.randf_range(110.0, 160.0)
			next = "roof"
		"roof":
			_roof_step()
		"street":
			_street()
		"launch":
			_launch()

## One more roof: a gap or a step, maybe a corner, the building, things on it; or, once the section is long
## enough, the drop to the street.
func _roof_step() -> void:
	var v := _speed(built)
	if built >= sec_end:
		_drop()
		return
	var t_air := 2.0 * JUMP_V / GRAV
	var dh := 0.0
	var gap := 0.0
	var r := rng.randf()
	# (off a corner, a short roof, no step up straight away: a leap or a step down)
	if after_corner and r >= 0.8:
		r = rng.randf() * 0.8
	after_corner = false
	if r < 0.5:
		# an alley to leap: never more than he can clear jumping a little before its edge
		gap = rng.randf_range(1.8, clampf(v * t_air * 0.55, 2.2, 5.0))
		dh = rng.randf_range(-2.5, 0.7)
	elif r < 0.8:
		dh = rng.randf_range(-3.0, -1.0)      # a step down: he just drops onto it
	else:
		dh = rng.randf_range(0.5, 1.1)        # a step up: a leap onto it
	var h := clampf(roof_h + dh, 8.0, 24.0)
	# (a step up is a leap: never one so small it looks like a step he could take)
	if h > roof_h and h < roof_h + 0.6:
		h = roof_h
	if gap > 0.0:
		_line(gap)
		stats.gaps += 1
	# a corner now and then (heading north it may turn either way; heading east or west only back north)
	var turn := 0.0
	if rng.randf() < 0.28 and built > 60.0:
		if dir.y > 0.5:
			turn = -1.0 if rng.randf() < 0.5 else 1.0
		else:
			turn = -1.0 if dir.x > 0.5 else 1.0
			# (east: a left turn heads north; west: a right turn does)
	if turn != 0.0:
		_corner(h, turn)
		after_corner = true
	else:
		_building(rng.randf_range(20.0, 40.0), h, rng.randf_range(10.5, 14.0), true)
	stats.roofs += 1

## A building on the path, len long, its roof at h, w wide: the box, low walls along its sides, the yellow edge where
## the roof ends over an alley, the things on its roof, and buildings beside it.
func _building(len: float, h: float, w: float, things: bool) -> void:
	var s0 := built
	_line(len)
	var nodes: Array = []
	var mid := s0 + len * 0.5
	var b := _box(frame(mid, 0.0, h * 0.5), Vector3(w, h, len), mat_build)
	_paint(b)
	nodes.append(b)
	for side: float in [-1.0, 1.0]:
		nodes.append(_box(frame(mid, side * (w * 0.5 - 0.15), h + 0.3), Vector3(0.3, 0.6, len), mats.parapet))
	solids.append({s0 = s0, s1 = s0 + len, x0 = -w * 0.5, x1 = w * 0.5, y0 = 0.0, y1 = h, kind = "roof", v = 0.0})
	# where it ends: a yellow line along the edge (he can see where to leap)
	nodes.append(_box(frame(s0 + len - 0.15, 0.0, h + 0.012), Vector3(w - 0.6, 0.03, 0.3), mats.edge))
	roof_h = h
	_beside(s0, s0 + len, w, h, nodes)
	if things:
		# (not before he is down from the leap onto it and has had a moment to look)
		_roof_rows(s0 + maxf(8.0, _speed(s0) * 1.75), s0 + len - 6.0, h, nodes)
	pieces.append({s1 = s0 + len, nodes = nodes})

func _corner(h: float, side: float) -> void:
	var s0 := built
	var p0 := _end_point()
	var d0 := dir
	_arc(side)
	var c := p0 + d0 * CORNER
	var nodes: Array = []
	var b := _box(Transform3D(Basis(Vector3.UP, atan2(d0.x, d0.y)), Vector3(c.x, h * 0.5, c.y)), Vector3(CORNER * 2.0, h, CORNER * 2.0), mat_build)
	_paint(b)
	nodes.append(b)
	# low walls on the two sides away from the path
	# (a box's own x points left of the way it faces: the side away from the turn is +side)
	var outer := side
	var t := Transform3D(Basis(Vector3.UP, atan2(d0.x, d0.y)), Vector3(c.x, h + 0.3, c.y))
	# (only the outer side: one across the front would fill the camera as it swings round the turn)
	nodes.append(_box(t * Transform3D(Basis(), Vector3(outer * (CORNER - 0.15), 0, 0)), Vector3(0.3, 0.6, CORNER * 2.0), mats.parapet))
	solids.append({s0 = s0, s1 = built, x0 = -6.5, x1 = 6.5, y0 = 0.0, y1 = h, kind = "roof", v = 0.0})
	decor.append({rect = Rect2(c.x - CORNER - 2.0, c.y - CORNER - 2.0, CORNER * 2.0 + 4.0, CORNER * 2.0 + 4.0), s1 = built})
	nodes.append(_box(frame(built - 0.15, 0.0, h + 0.012), Vector3(CORNER * 2.0 - 0.6, 0.03, 0.3), mats.edge))
	roof_h = h
	stats.corners += 1
	pieces.append({s1 = built, nodes = nodes})

## Buildings either side of the path from s0 to s1 (only where nothing stands yet), so it looks like a city.
func _beside(s0: float, s1: float, w: float, h: float, nodes: Array, gap := 3.0) -> void:
	var s := s0 + 0.5
	while s < s1 - 4.0:
		var len := minf(rng.randf_range(10.0, 26.0), s1 - s - 0.5)
		if len < 6.0:
			break
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.12:
				continue
			var dep := rng.randf_range(10.0, 18.0)
			var x := side * (w * 0.5 + gap + dep * 0.5)
			var hh := clampf(h + rng.randf_range(-6.0, 12.0), 6.0, 60.0)
			var cen := world(s + len * 0.5, x)
			var d := dir_at(s + len * 0.5)
			var ext := Vector2(absf(d.x) * len + absf(d.y) * dep, absf(d.y) * len + absf(d.x) * dep)
			var rect := Rect2(cen.x - ext.x * 0.5, cen.z - ext.y * 0.5, ext.x, ext.y)
			if _taken(rect):
				continue
			decor.append({rect = rect, s1 = s + len})
			var b := _box(frame(s + len * 0.5, x, hh * 0.5), Vector3(dep, hh, len), mat_build)
			_paint(b)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodes.append(b)
		s += len + rng.randf_range(0.0, 3.0)

func _taken(r: Rect2) -> bool:
	for o in decor:
		if (o.rect as Rect2).grow(-0.2).intersects(r):
			return true
	# nor across the path ahead or behind (a turn brings it round)
	var path_r := Rect2(r.position, r.size)
	for g in segs.slice(maxi(segs.size() - 12, 0)):
		var a := world(float(g.s0))
		var b := world(float(g.s0) + float(g.len) - 0.001)
		var pr := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z))).grow(6.6)
		if pr.intersects(path_r):
			return true
	return false

## Rows of things on a roof from s0 to s1: each leaves a way through, spaced so there is time to see the next.
func _roof_rows(s0: float, s1: float, h: float, nodes: Array) -> void:
	var s := s0
	while s < s1:
		var v := _speed(s)
		var room := maxf(10.0, v * 1.25)
		var kinds := ["box", "box", "fence", "pipe", "tank", "box2", "coins"]
		var k: String = kinds[rng.randi() % kinds.size()]
		if s > s1 - 2.0:
			break
		_roof_row(k, s, h, nodes)
		stats.rows += 1
		s += room + rng.randf_range(0.0, v * 0.6)

func _roof_row(k: String, s: float, h: float, nodes: Array) -> void:
	var lanes := [0, 1, 2]
	match k:
		"box":
			# an air unit in one lane (leap it, or step round it); coins over it
			var l: int = lanes[rng.randi() % 3]
			_air_unit(s, LANES[l], h, nodes)
			_coin_arc(s - 3.5, LANES[l], h + 0.9, 5, nodes)
		"box2":
			# two of them, one lane free
			var free: int = rng.randi() % 3
			for l: int in lanes:
				if l != free:
					_air_unit(s, LANES[l], h, nodes)
			_coin_line(s - 4.0, LANES[free], h + 0.9, 5, nodes)
		"fence":
			# a low fence right across: leap it
			_solid_box(s, 0.0, 7.6, 0.25, h, h + 0.9, "fence", mats.red, nodes)
			for x: float in [-3.6, 0.0, 3.6]:
				nodes.append(_box(frame(s, x, h + 0.45), Vector3(0.12, 0.9, 0.12), mats.dark))
		"pipe":
			# a pipe right across at chest height: roll under it
			var o := {s0 = s - 0.3, s1 = s + 0.3, x0 = -3.8, x1 = 3.8, y0 = h + 1.15, y1 = h + 1.6, kind = "pipe", v = 0.0}
			solids.append(o)
			var p := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.22
			cm.height = 8.4
			cm.radial_segments = 10
			p.mesh = cm
			p.material_override = mats.pipe
			p.transform = frame(s, 0.0, h + 1.38) * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3())
			add_child(p)
			nodes.append(p)
			for x: float in [-4.0, 4.0]:
				nodes.append(_box(frame(s, x, h + 0.8), Vector3(0.2, 1.6, 0.2), mats.dark))
			_coin_line(s - 3.0, LANES[rng.randi() % 3], h + 0.5, 5, nodes)
		"tank":
			# a water tank on legs in one or two lanes, too tall to leap: step round it
			var free: int = rng.randi() % 3
			var two := rng.randf() < 0.5
			for l: int in lanes:
				if l == free or (not two and l != (free + 1) % 3):
					continue
				_tank(s, LANES[l], h, nodes)
			_coin_line(s - 5.0, LANES[free], h + 0.9, 6, nodes)
		"coins":
			_coin_line(s - 3.0, LANES[rng.randi() % 3], h + 0.9, 8, nodes)

## An air unit: a metal box with a fan in its top and a grille on its front, low enough to leap (or land on).
func _air_unit(s: float, x: float, h: float, nodes: Array) -> void:
	_solid_box(s, x, 1.7, 1.6, h, h + 1.05, "box", mats.metal, nodes)
	var fan := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.04
	cm.radial_segments = 16
	cm.rings = 1
	fan.mesh = cm
	fan.material_override = mats.dark
	fan.transform = frame(s, x, h + 1.06)
	add_child(fan)
	nodes.append(fan)
	nodes.append(_box(frame(s - 0.81, x, h + 0.5), Vector3(1.4, 0.7, 0.04), mats.dark))

## A water tank on legs (wooden staves, a pointed lid): solid from the roof up, too tall to leap.
func _tank(s: float, x: float, h: float, nodes: Array) -> void:
	solids.append({s0 = s - 1.1, s1 = s + 1.1, x0 = x - 1.1, x1 = x + 1.1, y0 = h, y1 = h + 4.4, kind = "tank", v = 0.0})
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.05
	cm.height = 2.3
	cm.radial_segments = 14
	cm.rings = 1
	body.mesh = cm
	body.material_override = mats.tank
	body.transform = frame(s, x, h + 2.75)
	add_child(body)
	nodes.append(body)
	var lid := MeshInstance3D.new()
	var cn := CylinderMesh.new()
	cn.top_radius = 0.05
	cn.bottom_radius = 1.15
	cn.height = 0.65
	cn.radial_segments = 14
	cn.rings = 1
	lid.mesh = cn
	lid.material_override = mats.dark
	lid.transform = frame(s, x, h + 4.22)
	add_child(lid)
	nodes.append(lid)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		nodes.append(_box(frame(s + cos(a) * 0.75, x + sin(a) * 0.75, h + 0.8), Vector3(0.14, 1.6, 0.14), mats.dark))
	# the hoops round it
	for yy: float in [h + 2.0, h + 2.75, h + 3.5]:
		var hoop := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 1.08
		hm.bottom_radius = 1.08
		hm.height = 0.06
		hm.radial_segments = 14
		hm.rings = 1
		hoop.mesh = hm
		hoop.material_override = mats.dark
		hoop.transform = frame(s, x, yy)
		add_child(hoop)
		nodes.append(hoop)

## A box in his way: sx wide, sl long, from y0 to y1 (path space), and solid.
func _solid_box(s: float, x: float, sx: float, sl: float, y0: float, y1: float, kind: String, m: Material, nodes: Array) -> Dictionary:
	var o := {s0 = s - sl * 0.5, s1 = s + sl * 0.5, x0 = x - sx * 0.5, x1 = x + sx * 0.5, y0 = y0, y1 = y1, kind = kind, v = 0.0}
	solids.append(o)
	nodes.append(_box(frame(s, x, (y0 + y1) * 0.5), Vector3(sx, y1 - y0, sl), m))
	return o

## The end of the roofs: a last, long roof (the street is below its far edge), and the beat he leaps off on.
func _drop() -> void:
	# (across an alley: no higher than a leap can take him)
	var h := minf(maxf(roof_h + rng.randf_range(-2.5, 0.4), 8.0), roof_h + 0.4)
	_line(rng.randf_range(2.0, 3.2))
	_building(26.0, h, 12.0, false)
	beats.append({s = built, kind = "drop", h = 0.0})
	zones[-1].s1 = built
	next = "street"

## A street from where he lands: its buildings either side, and what comes at him, then the pad and the next roofs.
func _street() -> void:
	stats.streets += 1
	var s0 := built
	var len := rng.randf_range(230.0, 330.0)
	_line(len)
	zones.append({s0 = s0, s1 = s0 + len, kind = "street"})
	var nodes: Array = []
	# the road, the pavements, buildings both sides
	var rd := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9.0, len)
	rd.mesh = pm
	rd.material_override = mat_road
	rd.set_instance_shader_parameter("len", len)
	rd.transform = frame(s0 + len * 0.5, 0.0, 0.01)
	add_child(rd)
	nodes.append(rd)
	for side: float in [-1.0, 1.0]:
		nodes.append(_box(frame(s0 + len * 0.5, side * 5.75, 0.08), Vector3(2.5, 0.16, len), mats.walk))
		# street lamps
		var s := s0 + 6.0
		while s < s0 + len:
			var pole := _box(frame(s, side * 5.3, 2.8), Vector3(0.12, 5.6, 0.12), mats.dark)
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodes.append(pole)
			var arm := _box(frame(s, side * 4.75, 5.55), Vector3(1.2, 0.08, 0.08), mats.dark)
			arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nodes.append(arm)
			nodes.append(_box(frame(s, side * 4.2, 5.47), Vector3(0.5, 0.12, 0.26), mats.lamp))
			s += 26.0
	_beside(s0, s0 + len - PAD - 8.0, 14.0, 18.0, nodes, 0.0)
	# one lane has the traffic coming at him; parked cars, barriers and gantries stand in the other two
	onc = 0 if rng.randf() < 0.5 else 2
	onc_v = -lerpf(7.0, 11.0, clampf((s0 - 300.0) / 3000.0, 0.0, 1.0))
	street_end = s0 + len
	var rows: Array = []
	var s := s0 + 45.0
	while s < s0 + len - PAD - 30.0:
		var v := _speed(s)
		_street_row(s, nodes)
		rows.append(s)
		stats.rows += 1
		s += maxf(14.0, v * 1.5) + rng.randf_range(0.0, v * 0.8)
	# the traffic: cars meeting him every so often, never where a row leaves him only their lane
	s = s0 + 55.0 + rng.randf_range(0.0, 20.0)
	while s < s0 + len - PAD - 30.0:
		var near_row := false
		for r in rows:
			near_row = near_row or absf(float(r) - s) < 9.0
		if not near_row:
			_car(s, onc, onc_v, MODELS[rng.randi() % 2], nodes)
		s += rng.randf_range(16.0, 34.0)
	pieces.append({s1 = s0 + len, nodes = nodes})
	sec_end = s0 + len
	next = "launch"

func _street_row(s: float, nodes: Array) -> void:
	var mine := [0, 1, 2].filter(func(l): return l != onc)   # his way's two lanes
	var r := rng.randf()
	var free: int = mine[rng.randi() % 2]
	var other: int = mine[0] if free == mine[1] else mine[1]
	if r < 0.32:
		# a parked car; sometimes one in each lane, one of them low enough to leap onto
		_car(s, other, 0.0, "agera" if rng.randf() < 0.5 else "gls", nodes)
		if rng.randf() < 0.35:
			_car(s + rng.randf_range(-1.0, 1.0), free, 0.0, "agera", nodes)
			_coin_arc(s - 4.0, LANES[free], 1.6, 5, nodes)
		else:
			_coin_line(s - 8.0, LANES[free], 0.9, 6, nodes)
	elif r < 0.5:
		# a slow one going his way
		_car(s, other, rng.randf_range(3.0, 4.5), MODELS[rng.randi() % 2], nodes)
		_coin_line(s - 5.0, LANES[free], 0.9, 6, nodes)
	elif r < 0.78:
		# road barriers: in one lane, or both his lanes (leap them, or take the traffic's lane)
		_barrier(s, other, nodes)
		if rng.randf() < 0.5:
			_barrier(s, free, nodes)
			_coin_arc(s - 3.5, LANES[free], 0.9, 5, nodes)
		else:
			_coin_line(s - 6.0, LANES[free], 0.9, 6, nodes)
	else:
		# a gantry across his two lanes at chest height: roll under it
		var x0 := minf(LANES[mine[0]], LANES[mine[1]]) - 1.4
		var x1 := maxf(LANES[mine[0]], LANES[mine[1]]) + 1.4
		solids.append({s0 = s - 0.35, s1 = s + 0.35, x0 = x0, x1 = x1, y0 = 1.15, y1 = 1.7, kind = "pipe", v = 0.0})
		nodes.append(_box(frame(s, (x0 + x1) * 0.5, 1.42), Vector3(x1 - x0, 0.55, 0.5), mats.pipe))
		for xx: float in [x0 - 0.15, x1 + 0.15]:
			nodes.append(_box(frame(s, xx, 0.85), Vector3(0.25, 1.7, 0.25), mats.dark))
		_coin_line(s - 3.0, LANES[mine[rng.randi() % 2]], 0.5, 5, nodes)

func _barrier(s: float, l: int, nodes: Array) -> void:
	_solid_box(s, LANES[l], 2.1, 0.45, 0.0, 0.95, "barrier", mats.stripe, nodes)
	nodes.append(_box(frame(s, LANES[l], 0.62), Vector3(2.12, 0.22, 0.47), mats.red))

## A car in lane l around s: parked (v 0), coming at him (v < 0, placed so it reaches s when he does) or going his
## way (v > 0).
func _car(s: float, l: int, v: float, vm: String, nodes: Array) -> void:
	var dims: Vector3 = car_dims[vm]
	var len := dims.x
	var start := s
	var o := {s0 = start - len * 0.5, s1 = start + len * 0.5, x0 = LANES[l] - dims.z * 0.45, x1 = LANES[l] + dims.z * 0.45,
		y0 = 0.0, y1 = dims.y * 0.97, kind = "car", v = v, meet = s, armed = v == 0.0, vm = vm, lane = l, s_max = street_end - 4.0,
		id = stats.cars}
	var car := Node3D.new()
	car.visible = v >= 0.0
	car.name = "Car"
	add_child(car)
	# the models' front is +x: turned to face along the path (or back along it, coming at him)
	var col: Color = PAINT[rng.randi() % PAINT.size()]
	for p in car_parts[vm]:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3()) * (p[1] as Transform3D)
		var role: String = p[2]
		var m: Material = (mats.car as Dictionary).get(role, mats.car.trim)
		mi.material_override = m
		if role == "paint" or role == "far":
			mi.set_instance_shader_parameter("paint", Vector3(col.r, col.g, col.b))
		if p[3]:
			mi.visibility_range_begin = 32.0
			mi.visibility_range_begin_margin = 3.0
		else:
			mi.visibility_range_end = 32.0
			mi.visibility_range_end_margin = 3.0
			if role != "paint":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(mi)
	o.node = car
	if v < 0.0:
		var snd := AudioStreamPlayer3D.new()
		snd.stream = _engine_stream()
		snd.unit_size = 5.0
		snd.max_distance = 60.0
		snd.volume_db = -6.0
		snd.autoplay = true
		car.add_child(snd)
	solids.append(o)
	nodes.append(car)
	stats.cars += 1
	_place_car(o)

var _engine: AudioStream
func _engine_stream() -> AudioStream:
	if _engine == null:
		_engine = looped("engine_loop")
	return _engine

## A looping sound of the game's (its loop end is in the sounds' manifest: the files are compressed on import).
static func looped(n: String) -> AudioStreamWAV:
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sounds/sounds.json"))
	var w: AudioStreamWAV = load("res://assets/sounds/%s.wav" % n).duplicate()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(info[n].loop_end[0])
	return w

func _place_car(o: Dictionary) -> void:
	var mid := (float(o.s0) + float(o.s1)) * 0.5
	var x := (float(o.x0) + float(o.x1)) * 0.5
	(o.node as Node3D).transform = frame(mid, x, 0.0, float(o.v) < 0.0)

## The cars move on. One coming at him waits, out of sight, until it has just time enough to reach its place in
## the street when he does (from no further than the end of the street), then sets off; one going his way waits
## until he is 40 m off, and stops behind anything in its lane.
func move_cars(dt: float, s_him: float, v_him: float) -> void:
	for o in solids:
		if o.kind != "car" or float(o.v) == 0.0:
			continue
		var len := float(o.s1) - float(o.s0)
		if not o.armed:
			if float(o.v) < 0.0:
				var t_meet := (float(o.meet) - s_him) / maxf(v_him, 1.0)
				var t_max := (float(o.s_max) - float(o.meet)) / -float(o.v)
				if t_meet > minf(14.0, t_max):
					continue
				var mid := float(o.meet) - float(o.v) * t_meet
				o.s0 = mid - len * 0.5
				o.s1 = mid + len * 0.5
				(o.node as Node3D).visible = true
			elif float(o.s0) - s_him > 40.0:
				continue
			o.armed = true
		var ds := float(o.v) * dt
		if ds > 0.0:
			for q in solids:
				if q == o or float(q.x1) <= float(o.x0) or float(q.x0) >= float(o.x1) or float(q.y0) > 1.6:
					continue
				var gap := float(q.s0) - float(o.s1)
				if gap >= 0.0 and gap < 1.5 + ds:
					ds = 0.0
		o.s0 = float(o.s0) + ds
		o.s1 = float(o.s1) + ds
		_place_car(o)

## The pad and the next roofs: the street ends at a building he is thrown up onto.
func _launch() -> void:
	var nodes: Array = []
	var pad_s := built - PAD
	var pad := _box(frame(pad_s, 0.0, 0.05), Vector3(8.0, 0.1, 2.4), mats.pad)
	nodes.append(pad)
	var h := rng.randf_range(11.0, 16.0)
	beats.append({s = pad_s, kind = "launch", h = h, s_land = built + 6.0})
	pieces.append({s1 = built, nodes = nodes})
	zones.append({s0 = built, s1 = INF, kind = "roof"})
	_building(rng.randf_range(30.0, 40.0), h, 12.0, false)
	sec_end = built + rng.randf_range(160.0, 260.0)
	next = "roof"

# ---------------------------------------------------------------- coins
func _coin_line(s: float, x: float, y: float, n: int, nodes: Array) -> void:
	for i in n:
		_coin(s + i * 1.6, x, y, nodes)

## Coins over something to leap: up and down the way he goes.
func _coin_arc(s: float, x: float, y: float, n: int, nodes: Array) -> void:
	for i in n:
		var u := float(i) / float(n - 1)
		_coin(s + i * 1.75, x, y + sin(u * PI) * 1.5, nodes)

func _coin(s: float, x: float, y: float, nodes: Array) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = coin_mesh
	mi.material_override = mats.coin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = frame(s, x, y) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3())
	add_child(mi)
	nodes.append(mi)
	coins.append({s = s, x = x, y = y, node = mi})

# ---------------------------------------------------------------- shapes
func _box(t: Transform3D, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.transform = t
	add_child(mi)
	return mi

func _paint(b: MeshInstance3D) -> void:
	var c: Color = WALLS[rng.randi() % WALLS.size()]
	b.set_instance_shader_parameter("wall", c)
	b.set_instance_shader_parameter("seed", rng.randf() * 10.0)

# ---------------------------------------------------------------- asking about it
## What kind of place s is: "roof" or "street".
func zone_at(s: float) -> String:
	for z in zones:
		if s >= float(z.s0) and s < float(z.s1):
			return z.kind
	return "roof"

## The highest thing he would stand on at s, x (half his width either side): no higher than he can step up to from
## `feet`; the ground (0) if nothing.
func floor_at(s: float, x: float, feet: float, half := 0.3) -> float:
	var best := 0.0
	for o in near:
		if float(o.s1) < s - half or float(o.s0) > s + half or float(o.x1) < x - half or float(o.x0) > x + half:
			continue
		var top := float(o.y1)
		if top <= feet + STEP and top > best and float(o.y0) <= feet + 0.05:
			best = top
	return best

## The first thing his body (s, x from-to, y from-to) runs into, or {}.
func hit(s0: float, s1: float, x0: float, x1: float, y0: float, y1: float) -> Dictionary:
	for o in near:
		if float(o.s1) <= s0 or float(o.s0) >= s1 or float(o.x1) <= x0 or float(o.x0) >= x1:
			continue
		if float(o.y1) <= y0 or float(o.y0) >= y1:
			continue
		return o
	return {}

## The things in lane l from s on (within dist), nearest first: [ahead (m), the solid].
func ahead_in_lane(s: float, l: int, dist: float) -> Array:
	var x: float = LANES[l]
	var out: Array = []
	for o in near:
		if float(o.x1) <= x - 0.3 or float(o.x0) >= x + 0.3 or float(o.s1) < s - 0.5 or float(o.s0) > s + dist:
			continue
		out.append([float(o.s0) - s, o])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out
