## The model cars as things that move: the one the player drives, the ones the T-Rex throws and
## flips, and the wrecks they leave. Each car keeps its collision box in Col where the car is (out of
## the way while it is driven or in the air, back where it comes to rest), and its glows, shadow and
## alarm follow it.
class_name Vehicles
extends RefCounted

## Size of each model at scale 1 (length along its +x, width, height), metres.
const SIZE := {gls = Vector3(5.1, 1.78, 2.1), agera = Vector3(4.3, 1.13, 2.0)}
const TOP_SPEED := {gls = 21.0, agera = 26.0}   # m/s (75 and 94 km/h)
const WHEELBASE := 2.9
const HP := 2                                    # T-Rex hits a car takes before it is thrown over

var g: Game
var cars: Array = []        # see _make
var by_box := {}            # Col box index -> car
var driven = null           # the car the player is in
var lights: Array[SpotLight3D] = []
var exhaust: GPUParticles3D

func _init(p_g: Game) -> void:
	g = p_g
	var slots: Array = g.data.vslots
	for i in slots.size():
		if i >= g.world.car_nodes.size() or g.world.car_nodes[i] == null:
			continue
		var c := _make(i, slots[i])
		cars.append(c)
		if c.box >= 0:
			by_box[c.box] = c
	for k in 2:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.93, 0.82)
		s.light_energy = 0.0
		s.spot_range = 38.0
		s.spot_angle = 30.0
		s.spot_attenuation = 0.9
		s.shadow_enabled = false
		g.add_child(s)
		lights.append(s)

func _make(i: int, s: Dictionary) -> Dictionary:
	var vm := String(s.vm)
	var sc := World.car_scale(s)
	var sz: Vector3 = SIZE.get(vm, SIZE.gls) * sc
	# its box in Col: the one centred where it is parked
	var box := -1
	var best := 0.8
	for j in g.col.x0.size():
		var cx := (g.col.x0[j] + g.col.x1[j]) * 0.5
		var cz := (g.col.z0[j] + g.col.z1[j]) * 0.5
		var d := U.hyp(cx - float(s.x), cz - float(s.z))
		if d < best and g.col.y0[j] < 0.1 and g.col.y1[j] < 2.5:
			best = d
			box = j
	var entry: Dictionary = g.world.car_nodes[i]
	return {
		i = i, vm = vm, type = String(s.get("type", "suv")), sc = sc, size = sz,
		node = entry.node, meshes = entry.meshes, roles = entry.roles, hinge = entry.hinge,
		door = int(s.get("door", 0)),
		box = box, box_flags = g.col.flags[box] if box >= 0 else 11,
		shadow = int(g.world.car_shadow.get(Vector2(s.x, s.z), -1)),
		alarm = int(s.get("alarm", -1)),
		pos = Vector2(float(s.x), float(s.z)), yaw = float(s.ry), roll = 0.0, lift = 0.0, y = 0.0,
		state = "parked", hp = HP, speed = 0.0, steer = 0.0, push = Vector2(), spin = 0.0,
		tumble = {}, smoke = null, home = Vector2(float(s.x), float(s.z)),
	}

# ---------------------------------------------------------------- placing a car
func forward(c: Dictionary) -> Vector2:
	return Vector2(cos(c.yaw), -sin(c.yaw))

func _basis(c: Dictionary) -> Basis:
	return Basis(Vector3.UP, c.yaw) * Basis(Vector3.RIGHT, c.roll)

## The car's transform: turned by yaw, rolled about its length around a point half its height up
## (so it can lie on its side or roof), lifted by lift (in the air while thrown).
func xform(c: Dictionary) -> Transform3D:
	var b := _basis(c)
	var hp: float = c.size.y * 0.5
	var origin := Vector3(c.pos.x, c.y + hp + c.lift, c.pos.y) - b * Vector3(0, hp, 0)
	return Transform3D(b.scaled(Vector3.ONE * c.sc), origin)

## How far it must be lifted so its lowest corner just touches the ground, at its current roll.
func rest_lift(c: Dictionary) -> float:
	var b := _basis(c)
	var hp: float = c.size.y * 0.5
	var lo := INF
	for cx in [-0.5, 0.5]:
		for cy in [0.0, 1.0]:
			for cz in [-0.5, 0.5]:
				var p := b * (Vector3(cx * c.size.x, cy * c.size.y, cz * c.size.z) - Vector3(0, hp, 0))
				lo = minf(lo, p.y + hp)
	return -lo

func _apply(c: Dictionary) -> void:
	var t := xform(c)
	(c.node as Node3D).transform = t
	if c.shadow >= 0:
		var flat: bool = absf(c.roll) < 0.05 and c.lift < 0.3
		var ext := Vector2(c.size.x, c.size.z) + Vector2(0.9, 0.9)
		var b := Basis(Vector3.UP, c.yaw).scaled(Vector3(ext.x, 1, ext.y) if flat or c.state == "wreck" else Vector3(0.001, 1, 0.001))
		g.world.shadow_mm.set_instance_transform(c.shadow, Transform3D(b, Vector3(c.pos.x, c.y + 0.012, c.pos.y)))

## Puts its box back in Col around where it now rests (the box of its footprint, turned).
func _place_box(c: Dictionary) -> void:
	if c.box < 0:
		return
	var f := forward(c)
	var r := Vector2(-f.y, f.x)
	var hl: float = c.size.x * 0.5
	var hw: float = maxf(c.size.z, c.size.y if absf(sin(c.roll)) > 0.5 else 0.0) * 0.5
	var ex := absf(f.x) * hl + absf(r.x) * hw
	var ez := absf(f.y) * hl + absf(r.y) * hw
	var top: float = c.size.z if absf(sin(c.roll)) > 0.5 else c.size.y
	g.col.set_box(c.box, c.pos.x - ex, c.pos.x + ex, c.y, c.y + top, c.pos.y - ez, c.pos.y + ez)
	if c.alarm >= 0 and c.alarm < g.alarms.size():
		g.alarms[c.alarm].x = c.pos.x
		g.alarms[c.alarm].z = c.pos.y
		g.alarms[c.alarm].hx = ex
		g.alarms[c.alarm].hz = ez

# ---------------------------------------------------------------- driving
## The car whose driver's door is in reach of (x,z), or null.
func near_car(x: float, z: float) -> Variant:
	var best = null
	var bd := 2.4
	for c in cars:
		if c.state != "parked":
			continue
		var f := forward(c)
		var d := Vector2(x, z) - (c.pos as Vector2)
		# distance from the car's outline
		var along: float = absf(d.dot(f)) - c.size.x * 0.5
		var side: float = absf(d.dot(Vector2(-f.y, f.x))) - c.size.z * 0.5
		var gap := Vector2(maxf(along, 0.0), maxf(side, 0.0)).length()
		if gap < bd:
			bd = gap
			best = c
	return best

func enter(c: Dictionary) -> void:
	driven = c
	c.state = "driven"
	c.speed = 0.0
	c.steer = 0.0
	c.push = Vector2()
	c.spin = 0.0
	if c.box >= 0:
		g.col.disable_box(c.box)
	if c.hinge:
		(c.hinge as Node3D).rotation.y = 0.0
	for m in c.meshes.get("head", []):
		(m as MeshInstance3D).material_override = g.world.head_lit
	for m in c.meshes.get("tail", []):
		(m as MeshInstance3D).material_override = g.world.tail_lit
	g.world.move_car_halos(c.i, xform(c), true)
	if c.alarm >= 0 and c.alarm < g.alarms.size():
		var a: Dictionary = g.alarms[c.alarm]
		if a.cd <= 0.0:
			g.trigger_alarm(a)
	g.sfx.play("clink", 0.3)

## Where the driver steps out: beside the driver's door, else the other side, else behind or in
## front, else the nearest open ground round the car (it may be jammed against a wall).
func exit_point(c: Dictionary) -> Vector2:
	var f := forward(c)
	var r := Vector2(-f.y, f.x)
	var side: float = c.size.z * 0.5 + 0.7
	for p in [c.pos - r * side + f * 0.4, c.pos + r * side + f * 0.4, c.pos - f * (c.size.x * 0.5 + 0.8), c.pos + f * (c.size.x * 0.5 + 0.8)]:
		if g.col.walkable(p.x, p.y, 0.4):
			return p
	var d := side
	while d < 8.0:
		for k in 16:
			var p: Vector2 = c.pos + Vector2.from_angle(TAU * k / 16.0) * d
			if g.col.walkable(p.x, p.y, 0.4):
				return p
		d += 0.5
	return c.pos - r * side

func leave(c: Dictionary) -> void:
	if driven == c:
		driven = null
	for l in lights:
		l.light_energy = 0.0
	g.sfx.loop_to("engine_loop", 0.0, 0.3)
	if c.state == "driven":
		c.state = "parked"
		c.speed = 0.0
		for m in c.meshes.get("head", []):
			(m as MeshInstance3D).material_override = c.roles[m]
		for m in c.meshes.get("tail", []):
			(m as MeshInstance3D).material_override = c.roles[m]
		_place_box(c)
		g.world.move_car_halos(c.i, xform(c), false)

## One frame of driving. throttle and steer -1..1 (stick up/down, left/right), brake: handbrake.
func drive(dt: float, throttle: float, steer: float, brake: bool, lights_on: bool) -> void:
	var c: Dictionary = driven
	if c == null or c.state != "driven":
		return
	var top: float = TOP_SPEED.get(c.vm, 21.0) * (0.7 if c.hp < HP else 1.0)
	var sp: float = c.speed
	if throttle > 0.05:
		sp += (16.0 * throttle if sp < -0.3 else 7.5 * throttle * (1.0 - clampf(sp / top, 0.0, 1.0))) * dt
	elif throttle < -0.05:
		sp -= (16.0 * -throttle if sp > 0.3 else 5.0 * -throttle) * dt
		sp = maxf(sp, -6.0)
	else:
		sp = move_toward(sp, 0.0, 2.2 * dt)
	if brake:
		sp = move_toward(sp, 0.0, 22.0 * dt)
	c.speed = sp
	c.steer = lerpf(c.steer, steer, minf(1.0, dt * 7.0))
	var wheel: float = c.steer * 0.62 * (1.0 - 0.55 * clampf(absf(sp) / top, 0.0, 1.0))
	c.yaw -= sp / WHEELBASE * tan(wheel) * dt * (1.6 if brake and absf(sp) > 6.0 else 1.0)
	c.yaw += c.spin * dt
	c.spin = move_toward(c.spin, 0.0, 3.0 * dt)
	var f := forward(c)
	var vel: Vector2 = f * sp + c.push
	c.push = (c.push as Vector2) * exp(-2.5 * dt)
	var old: Vector2 = c.pos
	c.pos += vel * dt
	_collide_driven(c, vel, dt)
	c.pos.x = clampf(c.pos.x, -g.bound + 1.5, g.bound - 1.5)
	c.pos.y = clampf(c.pos.y, -g.bound + 1.5, g.bound - 1.5)
	c.y = lerpf(c.y, g.world.ground_at(c.pos.x, c.pos.y, 0.0), minf(1.0, dt * 10.0))
	# the stairs down to the subway are no road
	var h: Dictionary = g.world.hole
	if c.pos.x > h.x0 - 1.4 and c.pos.x < h.x1 + 1.4 and c.pos.y > h.z0 - 1.4 and c.pos.y < h.z1 + 1.4:
		c.pos = old
		c.speed *= -0.2
	_apply(c)
	# its headlights
	var t := xform(c)
	var L: Dictionary = World.CAR_LIGHTS.get(c.vm, World.CAR_LIGHTS.gls)
	for k in 2:
		var l := lights[k]
		var p: Vector3 = t * Vector3(L.head.x + 0.1, L.head.y, L.head.z * (k * 2 - 1))
		l.global_position = p
		var ahead: Vector3 = t * Vector3(L.head.x + 12.0, L.head.y - 1.6, L.head.z * (k * 2 - 1))
		if not p.is_equal_approx(ahead):
			l.look_at(ahead)
		l.light_energy = (4.0 if lights_on else 0.0) * (0.0 if g.daylight else 1.0)
	var f01 := clampf(absf(c.speed) / top, 0.0, 1.0)
	g.sfx.loop_to("engine_loop", 0.18 + 0.22 * f01, 0.15)
	g.sfx.loop_pitch("engine_loop", 0.85 + 1.5 * f01 + (0.15 if throttle > 0.3 else 0.0))

## Keeps the driven car out of walls and parked cars: three circles along its length.
func _collide_driven(c: Dictionary, vel: Vector2, dt: float) -> void:
	var f := forward(c)
	var r: float = c.size.z * 0.5
	var off: float = c.size.x * 0.5 - r
	var push := Vector2()
	for k in [-off, 0.0, off]:
		var cc: Vector2 = c.pos + f * k
		var p := g.col.collide(Vector3(cc.x, 0.0, cc.y), r, 0.3, 1.3, false)
		var d := Vector2(p.x - cc.x, p.z - cc.y)
		if d.length() > push.length():
			push = d
	# the T-Rex is solid too
	var m := g.mon
	var md := (c.pos as Vector2) - Vector2(m.pos.x, m.pos.z)
	var reach: float = Monster.BODY_R + r + 0.3
	if md.length() < reach:
		var n := md.normalized() if md.length() > 0.01 else -f
		var hit := -vel.dot(n)
		push += n * (reach - md.length())
		if hit > 7.0 and m.state != "STUN":
			m.rammed(hit)
			g.buzz(160)
			g.sfx.play("boom", 0.6)
			c.hp -= 1
	if push.length() < 0.001:
		return
	c.pos += push
	var n2 := push.normalized()
	var impact := -vel.dot(n2)
	if impact > 2.5:
		c.speed *= 0.3
		if impact > 9.0:
			c.speed = -c.speed * 0.3
		var v := clampf(impact / 18.0, 0.15, 1.0)
		g.sfx.play("clang", 0.5 * v)
		if impact > 8.0:
			g.sfx.play("shatter", 0.5 * v)
		g.pl.shake = maxf(g.pl.shake, v * 0.9)
		g.buzz(int(30 + 120 * v))
	else:
		# scraping along: lose the speed going into the wall only
		c.speed *= 1.0 - 3.0 * dt

# ---------------------------------------------------------------- the T-Rex throws cars
## A parked car the T-Rex runs into while charging, or the car being driven when it bites: it is
## thrown along dir (unit, x/z), harder for k nearer 1, tumbling over and landing somewhere it fits.
func knock(c: Dictionary, dir: Vector2, k: float) -> void:
	if c.state == "tumble":
		return
	var was_driven: bool = c.state == "driven"
	if c.box >= 0:
		g.col.disable_box(c.box)
	c.state = "tumble"
	var dist := 2.5 + 6.0 * k
	var land: Vector2 = c.pos
	var d := dist
	while d > 0.0:
		var q: Vector2 = c.pos + dir * d
		if g.col.walkable(q.x, q.y, 1.3) and absf(q.x) < g.bound - 3.0 and absf(q.y) < g.bound - 3.0:
			land = q
			break
		d -= 0.75
	# over onto its roof, its side, or all the way round back onto its wheels
	var right := Vector2(sin(c.yaw), cos(c.yaw))   # the car's +z side
	var sgn := 1.0 if dir.dot(right) >= 0.0 else -1.0
	var roll := 0.0
	var r := randf()
	if k > 0.6:
		roll = PI if r < 0.5 else (PI * 0.5 if r < 0.8 else TAU)
	elif k > 0.3:
		roll = PI * 0.5 if r < 0.6 else 0.0
	c.tumble = {t = 0.0, dur = 0.8 + 0.5 * k, p0 = c.pos, p1 = land, yaw0 = c.yaw, yaw1 = c.yaw + randf_range(-1.2, 1.2) * k,
		roll0 = c.roll, roll1 = c.roll + roll * sgn, h = 0.6 + 2.6 * k, driven = was_driven, y0 = c.y}
	if c.hinge:
		(c.hinge as Node3D).rotation.y = 0.0
	g.world.move_car_halos(c.i, xform(c), true)
	var pp := g.pos_params(c.pos.x, 1.0, c.pos.y, 30.0)
	g.sfx.play("clang", maxf(0.2, pp.vol), pp.pan, pp.lp)
	g.sfx.play("shatter", maxf(0.15, pp.vol * 0.8), pp.pan, pp.lp)

func update(dt: float) -> void:
	for c in cars:
		if c.state == "tumble":
			_tumble(c, dt)

func _tumble(c: Dictionary, dt: float) -> void:
	var T: Dictionary = c.tumble
	T.t += dt
	var u: float = clampf(T.t / T.dur, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 2.0)
	c.pos = (T.p0 as Vector2).lerp(T.p1, e)
	c.yaw = lerpf(T.yaw0, T.yaw1, e)
	c.roll = lerpf(T.roll0, T.roll1, e)
	c.y = lerpf(T.y0, 0.0, u)
	c.lift = sin(PI * u) * T.h + rest_lift(c) * u
	_apply(c)
	if T.driven:
		g.pl.pos = Vector3(c.pos.x, c.y, c.pos.y)
	if u >= 1.0:
		_land(c)

func _land(c: Dictionary) -> void:
	var T: Dictionary = c.tumble
	c.roll = wrapf(c.roll, -PI, PI)
	var upright: bool = absf(c.roll) < 0.3
	if upright:
		c.roll = 0.0
	c.lift = rest_lift(c)
	c.tumble = {}
	c.state = "parked" if upright and c.hp > 0 else "wreck"
	if c.state == "wreck":
		_smoke(c)
	_apply(c)
	_place_box(c)
	g.world.move_car_halos(c.i, xform(c), c.state == "wreck")
	var pp := g.pos_params(c.pos.x, 0.5, c.pos.y, 34.0)
	g.sfx.play("boom", maxf(0.25, pp.vol), pp.pan, pp.lp)
	g.sfx.play("thud", maxf(0.3, pp.vol), pp.pan, pp.lp)
	var d := U.hyp(g.pl.pos.x - c.pos.x, g.pl.pos.z - c.pos.y)
	if d < 30.0:
		g.pl.shake = maxf(g.pl.shake, (1.0 - d / 30.0) * 1.1)
		g.buzz(int(60 + 100 * (1.0 - d / 30.0)))
	if c.alarm >= 0 and c.alarm < g.alarms.size():
		g.trigger_alarm(g.alarms[c.alarm])
	else:
		g.mon.hear(c.pos.x, c.pos.y)
	if T.get("driven", false):
		g.thrown_out(c)

## Smoke curling up from a wreck.
func _smoke(c: Dictionary) -> void:
	if c.smoke:
		return
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 4.0
	p.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 12.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.2
	m.gravity = Vector3(0.25, 0.35, 0)
	m.scale_min = 1.2
	m.scale_max = 2.6
	var curve := CurveTexture.new()
	var cv := Curve.new()
	cv.add_point(Vector2(0, 0.4))
	cv.add_point(Vector2(1, 1.6))
	curve.curve = cv
	m.scale_curve = curve
	var grad := GradientTexture1D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.12, 0.12, 0.12, 0.0), Color(0.16, 0.16, 0.16, 0.45), Color(0.2, 0.2, 0.2, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.gradient = gr
	m.color_ramp = grad
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = g.world.tex("glow")
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = sm
	p.draw_pass_1 = q
	p.position = Vector3(c.pos.x, c.y + 0.8, c.pos.y)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 14, 8))
	g.add_child(p)
	c.smoke = p

## Cars the T-Rex's body (circle at p, radius r) is running into right now.
func cars_hit(p: Vector2, r: float) -> Array:
	var out := []
	for i in g.col.near(p.x - r, p.y - r, p.x + r, p.y + r):
		if not by_box.has(i):
			continue
		var c: Dictionary = by_box[i]
		if c.state == "tumble" or c.state == "driven":
			continue
		var cx := clampf(p.x, g.col.x0[i], g.col.x1[i])
		var cz := clampf(p.y, g.col.z0[i], g.col.z1[i])
		if U.hyp(p.x - cx, p.y - cz) < r:
			out.append(c)
	return out

## Makes a car one of the wrecks the city was left with (see Dressing): on its side or roof, maybe
## burnt out, smoking. It stays that way from run to run.
func make_wreck(c: Dictionary, roll: float, dyaw: float, burnt: bool, smoking: bool) -> void:
	c.home_roll = roll
	c.home_yaw = c.yaw + dyaw
	c.home_smoke = smoking
	if burnt:
		for role in ["paint", "far"]:
			for m in c.meshes.get(role, []):
				(m as MeshInstance3D).set_instance_shader_parameter("paint", Vector3(0.035, 0.03, 0.028))
	_to_home(c)

## Back to how the city was built (a new run).
func reset() -> void:
	if driven:
		leave(driven)
	for c in cars:
		_to_home(c)

func _to_home(c: Dictionary) -> void:
	c.pos = c.home
	c.yaw = float(c.get("home_yaw", g.data.vslots[c.i].ry))
	c.roll = float(c.get("home_roll", 0.0))
	c.y = 0.0
	c.hp = HP
	c.speed = 0.0
	c.push = Vector2()
	c.spin = 0.0
	c.tumble = {}
	var wreck: bool = absf(c.roll) > 0.01
	c.state = "wreck" if wreck else "parked"
	c.lift = rest_lift(c) if wreck else 0.0
	if c.smoke and not (wreck and c.get("home_smoke", false)):
		(c.smoke as Node).queue_free()
		c.smoke = null
	if wreck and c.get("home_smoke", false):
		_smoke(c)
	if c.hinge:
		(c.hinge as Node3D).rotation.y = 0.0 if wreck else c.door * 1.0
	for role in ["head", "tail"]:
		for m in c.meshes.get(role, []):
			(m as MeshInstance3D).material_override = c.roles[m]
	_apply(c)
	if c.box >= 0:
		if wreck:
			_place_box(c)
		else:
			_place_box_home(c)
	g.world.move_car_halos(c.i, xform(c), wreck)

func _place_box_home(c: Dictionary) -> void:
	var b: Array = g.data.col[c.box]
	g.col.set_box(c.box, float(b[0]), float(b[1]), float(b[2]), float(b[3]), float(b[4]), float(b[5]))
	if c.alarm >= 0 and c.alarm < g.alarms.size():
		var a: Dictionary = g.data.alarms[c.alarm]
		g.alarms[c.alarm].x = float(a.x)
		g.alarms[c.alarm].z = float(a.z)
		g.alarms[c.alarm].hx = float(a.hx)
		g.alarms[c.alarm].hz = float(a.hz)
