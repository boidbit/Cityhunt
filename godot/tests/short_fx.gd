## Video-only extras for the Shorts director (tests/short.gd), none of them in the game itself: bursts of sparks,
## glass, debris and dust at the impacts, dust kicked up under the T-Rex and behind the car, wheels that turn and
## steer, and a car body that leans into the bends and dips under braking.
extends RefCounted

## The parts of a car model whose triangles inside a wheel are moved onto that wheel's spinner (tyres, rims).
const WHEEL_ROLES := ["wheel", "tire", "chrome", "trim", "carbon"]

var g: Game
var root: Node3D
var car: Variant = null
var wheels: Array = []     # {pivot, spin, r, front}
var roll := 0.0
var pitch := 0.0
var last_speed := 0.0
var last_yaw := 0.0
var rex_dust: GPUParticles3D
var car_dust: GPUParticles3D
var mats := {}

func _init(p_g: Game) -> void:
	g = p_g
	root = Node3D.new()
	root.name = "ShortFX"
	g.add_child(root)
	rex_dust = _dust_emitter(28, 1.8, 0.8, 1.8)
	car_dust = _dust_emitter(36, 1.1, 0.5, 1.2)

# ---------------------------------------------------------------- impacts
## A burst at `at`, thrown out around `dir`. kind: bite (the jaws on the boot), impact (a hard hit), land (a
## car coming down on its roof), toss (a parked car thrown aside).
func burst(kind: String, at: Vector3, dir: Vector3) -> void:
	match kind:
		"bite":
			_sparks(at, dir, 45)
			_glass(at, dir, 45)
			_debris(at, dir, 5)
		"impact":
			_sparks(at, dir, 80)
			_glass(at, dir, 70)
			_debris(at, dir, 12)
			_dust(at - Vector3(0, at.y - 0.3, 0), 18, 1.0)
		"land":
			_dust(at, 36, 1.5)
			_glass(at + Vector3(0, 0.6, 0), Vector3.UP, 60)
			_debris(at + Vector3(0, 0.5, 0), Vector3.UP, 12)
			_sparks(at + Vector3(0, 0.3, 0), Vector3.UP, 50)
		"toss":
			_dust(Vector3(at.x, 0.3, at.z), 24, 1.2)
			_glass(at, dir, 50)
			_debris(at, dir, 9)
			_sparks(at, dir, 30)

func _sparks(at: Vector3, dir: Vector3, n: int) -> void:
	var m := _pm(dir, 60.0, 5.0, 11.0, 9.8)
	m.particle_flag_align_y = true
	m.scale_curve = _curve(1.0, 0.0)
	_collide(m, 0.3)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.2, 0.018)
	mesh.material = _mat("spark")
	_emit(at, n, 0.7, mesh, m, true)

func _glass(at: Vector3, dir: Vector3, n: int) -> void:
	var m := _pm(dir, 70.0, 2.5, 7.0, 9.8)
	m.particle_flag_rotate_y = true
	m.angular_velocity_min = -720.0
	m.angular_velocity_max = 720.0
	m.scale_min = 0.5
	m.scale_max = 1.6
	_collide(m, 0.25)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.008, 0.04)
	mesh.material = _mat("glass")
	_emit(at, n, 2.2, mesh, m, true)

func _debris(at: Vector3, dir: Vector3, n: int) -> void:
	var m := _pm(dir, 55.0, 3.0, 6.5, 9.8)
	m.particle_flag_rotate_y = true
	m.angular_velocity_min = -400.0
	m.angular_velocity_max = 400.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	_collide(m, 0.35)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.05, 0.15)
	mesh.material = _mat("debris")
	_emit(at, n, 2.6, mesh, m, true)

func _dust(at: Vector3, n: int, size: float) -> void:
	var m := _pm(Vector3.UP, 80.0, 1.5, 4.5, -0.4)
	m.damping_min = 2.5
	m.damping_max = 4.0
	m.scale_min = 1.6 * size
	m.scale_max = 3.2 * size
	m.scale_curve = _curve(0.5, 1.6)
	m.color_ramp = _ramp(Color(0.62, 0.58, 0.52), 0.55)
	_emit(at, n, 2.6, _puff(), m, false)

## A dust emitter that stays: moved along under the creature's feet or behind the car each frame.
func _dust_emitter(n: int, life: float, s0: float, s1: float) -> GPUParticles3D:
	var m := _pm(Vector3.UP, 70.0, 0.6, 1.6, -0.3)
	m.damping_min = 1.5
	m.damping_max = 2.5
	m.scale_min = s0
	m.scale_max = s1
	m.scale_curve = _curve(0.5, 1.5)
	m.color_ramp = _ramp(Color(0.6, 0.57, 0.52), 0.35)
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.0
	var p := GPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.process_material = m
	p.draw_pass_1 = _puff()
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 10, 40))
	root.add_child(p)
	return p

func _emit(at: Vector3, n: int, life: float, mesh: Mesh, m: ParticleProcessMaterial, collide: bool) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(n, 1)
	p.lifetime = life
	p.local_coords = false
	p.process_material = m
	p.draw_pass_1 = mesh
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-15, -3, -15), Vector3(30, 16, 30))
	root.add_child(p)
	p.emitting = true
	_free_later(p, life + 1.0)
	if collide:
		# the street, for the bits to bounce and settle on
		var box := GPUParticlesCollisionBox3D.new()
		box.size = Vector3(40, 2, 40)
		box.position = Vector3(at.x, g.world.ground_at(at.x, at.z, 0.0) - 1.0, at.z)
		root.add_child(box)
		_free_later(box, life + 1.0)

func _free_later(n: Node, sec: float) -> void:
	g.get_tree().create_timer(sec).timeout.connect(n.queue_free)

func _pm(dir: Vector3, spread: float, v0: float, v1: float, grav: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	m.spread = spread
	m.initial_velocity_min = v0
	m.initial_velocity_max = v1
	m.gravity = Vector3(0, -grav, 0)
	return m

func _collide(m: ParticleProcessMaterial, bounce: float) -> void:
	m.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	m.collision_friction = 0.6
	m.collision_bounce = bounce
	m.collision_use_scale = true

func _curve(a: float, b: float) -> CurveTexture:
	var cv := Curve.new()
	cv.max_value = maxf(maxf(a, b), 1.0)
	cv.add_point(Vector2(0, a))
	cv.add_point(Vector2(1, b))
	var ct := CurveTexture.new()
	ct.curve = cv
	return ct

func _ramp(c: Color, alpha: float) -> GradientTexture1D:
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(c, 0.0), Color(c, alpha), Color(c, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	return gt

## A soft round puff (the game's glow texture), facing the camera.
func _puff() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _mat("dust")
	return q

func _mat(kind: String) -> StandardMaterial3D:
	if mats.has(kind):
		return mats[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"spark":
			m.albedo_color = Color(1.0, 0.75, 0.4)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.55, 0.18)
			m.emission_energy_multiplier = 8.0
		"glass":
			m.albedo_color = Color(0.78, 0.88, 0.94)
			m.metallic = 0.7
			m.roughness = 0.05
		"debris":
			m.albedo_color = Color(0.07, 0.07, 0.075)
			m.roughness = 0.7
		"dust":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.vertex_color_use_as_albedo = true
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.albedo_texture = g.world.tex("glow")
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mats[kind] = m
	return m

# ---------------------------------------------------------------- wheels
## The car models have all four wheels in one mesh. For the car he drives, the triangles inside each wheel
## (tyre, rim, brake) are moved onto a node of their own at the wheel's hub, so it can roll and, at the front,
## steer. The meshes are this car's own copies; the other cars of the model keep theirs.
func rig_wheels(c: Dictionary) -> void:
	car = c
	last_yaw = c.yaw
	var node: Node3D = c.node
	var tyre: MeshInstance3D = null
	for role in ["wheel", "tire"]:
		for mi in c.meshes.get(role, []):
			if not (mi as Node).has_meta("far") and (mi as Node).get_parent() == node:
				tyre = mi
	if tyre == null or not (tyre.mesh is ArrayMesh):
		return
	# the four hubs: the tyre mesh's vertices split by front/back and left/right
	var pts := PackedVector3Array()
	for s in tyre.mesh.get_surface_count():
		for v in (tyre.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			pts.append(tyre.transform * v)
	if pts.is_empty():
		return
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var midx := (lo.x + hi.x) * 0.5
	var boxes := []
	for k in 4:
		boxes.append([Vector3(INF, INF, INF), Vector3(-INF, -INF, -INF)])
	for p in pts:
		var k := (2 if p.x > midx else 0) + (1 if p.z > 0.0 else 0)
		boxes[k][0] = (boxes[k][0] as Vector3).min(p)
		boxes[k][1] = (boxes[k][1] as Vector3).max(p)
	for k in 4:
		var a: Vector3 = boxes[k][0]
		var b: Vector3 = boxes[k][1]
		if a.x == INF:
			return
		var hub := (a + b) * 0.5
		var pivot := Node3D.new()
		pivot.position = hub
		node.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		wheels.append({pivot = pivot, spin = spin, hub = hub, r = maxf((b.y - a.y) * 0.5, 0.2), w = (b.z - a.z) * 0.5,
			front = hub.x > midx})
	for role in WHEEL_ROLES:
		for mi in c.meshes.get(role, []):
			if not (mi as Node).has_meta("far") and (mi as Node).get_parent() == node:
				_split(mi)

## Which wheel the car-space point is inside (-1: none).
func _wheel_at(p: Vector3) -> int:
	for k in wheels.size():
		var w: Dictionary = wheels[k]
		var h: Vector3 = w.hub
		var r: float = w.r * 1.04
		if (p.x - h.x) * (p.x - h.x) + (p.y - h.y) * (p.y - h.y) <= r * r and absf(p.z - h.z) <= w.w + 0.06:
			return k
	return -1

## Moves the triangles of mi that lie wholly inside a wheel onto that wheel's spinner (same vertices, new
## index lists), leaving the rest on the body.
func _split(mi: MeshInstance3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var body := ArrayMesh.new()
	var parts := [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	var moved := 0
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx = a[Mesh.ARRAY_INDEX]
		var tris := PackedInt32Array()
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			tris = idx
		else:
			tris.resize(v.size())
			for i in v.size():
				tris[i] = i
		# (plain Arrays: they are shared, so appending to one in the list appends in place)
		var keep := []
		var per := [[], [], [], []]
		for t in range(0, tris.size() - 2, 3):
			var k := _wheel_at(mi.transform * v[tris[t]])
			if k >= 0 and (_wheel_at(mi.transform * v[tris[t + 1]]) != k or _wheel_at(mi.transform * v[tris[t + 2]]) != k):
				k = -1
			var dest: Array = keep if k < 0 else per[k]
			dest.append(tris[t])
			dest.append(tris[t + 1])
			dest.append(tris[t + 2])
			if k >= 0:
				moved += 1
		if keep.size():
			var b := a.duplicate()
			b[Mesh.ARRAY_INDEX] = PackedInt32Array(keep)
			body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b)
		for k in 4:
			if (per[k] as Array).size():
				var w := a.duplicate()
				w[Mesh.ARRAY_INDEX] = PackedInt32Array(per[k])
				(parts[k] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, w)
	if moved == 0:
		return
	mi.mesh = body
	for k in 4:
		var pm: ArrayMesh = parts[k]
		if pm.get_surface_count() == 0:
			continue
		var w: Dictionary = wheels[k]
		var wm := MeshInstance3D.new()
		wm.mesh = pm
		# the same vertices, placed so they sit where they were with the spinner at the hub
		wm.transform = Transform3D(mi.transform.basis, mi.transform.origin - (w.hub as Vector3))
		wm.material_override = mi.material_override
		wm.cast_shadow = mi.cast_shadow
		wm.visibility_range_end = mi.visibility_range_end
		wm.visibility_range_end_margin = mi.visibility_range_end_margin
		wm.visibility_range_fade_mode = mi.visibility_range_fade_mode
		(w.spin as Node3D).add_child(wm)

# ---------------------------------------------------------------- every frame
## After the game has placed everything: wheels and body of the driven car, dust under the creature and behind
## the car.
func update(dt: float) -> void:
	var m := g.mon
	rex_dust.global_position = m.pos + Vector3(0, 0.3, 0)
	rex_dust.emitting = m.speed > 3.5 and m.actor.visible
	if car == null or car.state != "driven" or dt <= 0.0:
		car_dust.emitting = false
		return
	var sp: float = car.speed
	var fv: Vector2 = g.veh.forward(car)
	var hl: float = car.size.x * 0.5
	car_dust.global_position = Vector3(car.pos.x, car.y + 0.3, car.pos.y) - Vector3(fv.x, 0.0, fv.y) * (hl - 0.5)
	car_dust.emitting = absf(sp) > 9.0
	# wheels roll, the front ones steer (the same lock the game gives the car)
	var top: float = Vehicles.TOP_SPEED.get(car.vm, 21.0)
	var lock: float = car.steer * lerpf(0.6, 0.13, clampf(absf(sp) / top, 0.0, 1.0))
	for w in wheels:
		(w.spin as Node3D).rotation.z -= sp / float(w.r) * dt
		if w.front:
			(w.pivot as Node3D).rotation.y = -lock
	# the body leans out of a bend and dips its nose under braking (squats under power)
	var yaw_rate := wrapf(float(car.yaw) - last_yaw, -PI, PI) / dt
	var lat := sp * yaw_rate
	var lon := (sp - last_speed) / dt
	last_yaw = car.yaw
	last_speed = sp
	roll = lerpf(roll, clampf(lat * 0.012, -0.09, 0.09), 1.0 - exp(-dt * 6.0))
	pitch = lerpf(pitch, clampf(lon * 0.008, -0.06, 0.06), 1.0 - exp(-dt * 5.0))
	var n: Node3D = car.node
	var piv := Vector3(0, 0.5, 0)
	n.transform = n.transform * Transform3D(Basis(), piv) * Transform3D(Basis(Vector3(0, 0, 1), pitch) * Basis(Vector3(1, 0, 0), roll), Vector3()) * Transform3D(Basis(), -piv)
