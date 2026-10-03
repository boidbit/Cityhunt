## The evacuated city: cars left on their roofs and sides (a few burnt out and still smoking), a
## couple still burning, rubble fallen from the buildings, and the T-Rex's huge three-toed tracks
## pressed into the wet streets. Placed with its own fixed random sequence, so the city looks the
## same every run and the game's own random numbers (and so its tests) are untouched.
class_name Dressing
extends RefCounted

const WRECKS := 11
const FIRES := 2

var g: Game
var rng := RandomNumberGenerator.new()
var fires: Array = []       # {pos: Vector3, light: OmniLight3D, voice, halo}
var heaps: Array[Vector2] = []     # where the rubble lies
var tracks: Array[Vector2] = []    # where each line of its prints starts

static func build(game: Game) -> Dressing:
	var d := Dressing.new()
	d.g = game
	d.rng.seed = 20261003
	d._wrecks()
	d._rubble()
	d._tracks()
	return d

# ---------------------------------------------------------------- wrecks and fires
func _wrecks() -> void:
	var list: Array = g.veh.cars.filter(func(c): return c.alarm < 0 and c.type != "police" and c.box >= 0)
	# spread them out: no two wrecks closer than 18 m
	var chosen := []
	var tries := 0
	while chosen.size() < WRECKS and tries < 400 and list.size():
		tries += 1
		var c: Dictionary = list[rng.randi() % list.size()]
		var ok := true
		for o in chosen:
			if (o.pos as Vector2).distance_to(c.pos) < 18.0:
				ok = false
				break
		# keep them off the player's starting points
		for s in g.data.starts:
			if Vector2(s.x, s.z).distance_to(c.pos) < 10.0:
				ok = false
		if ok:
			chosen.append(c)
			list.erase(c)
	for k in chosen.size():
		var c: Dictionary = chosen[k]
		var r := rng.randf()
		var roll := PI if r < 0.45 else PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
		var burnt := k < 5
		g.veh.make_wreck(c, roll, rng.randf_range(-0.5, 0.5), burnt, k < 3)
		if k >= 3 and k < 3 + FIRES:
			_fire(c)

## A wreck still burning: flickering orange light, a glow, and its crackle when you are near.
func _fire(c: Dictionary) -> void:
	var p := Vector3(c.pos.x, 0.9, c.pos.y)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.omni_range = 14.0
	l.omni_attenuation = World.RANGE_FIT.y
	l.shadow_enabled = false
	l.position = p + Vector3(0, 0.6, 0)
	g.add_child(l)
	var flames := GPUParticles3D.new()
	flames.amount = 22
	flames.lifetime = 0.9
	flames.local_coords = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(1.2, 0.2, 0.6)
	m.direction = Vector3(0, 1, 0)
	m.spread = 10.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 2.2
	m.gravity = Vector3(0, 1.2, 0)
	m.scale_min = 0.6
	m.scale_max = 1.3
	var grad := GradientTexture1D.new()
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1.0, 0.75, 0.3, 0.0), Color(1.0, 0.55, 0.15, 0.9), Color(0.6, 0.15, 0.05, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.gradient = gr
	m.color_ramp = grad
	flames.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.vertex_color_use_as_albedo = true
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = g.world.tex("glow")
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = sm
	flames.draw_pass_1 = q
	flames.position = p
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
	g.add_child(flames)
	if c.smoke == null:
		g.veh._smoke(c)
		c.home_smoke = true
	fires.append({pos = p, light = l, voice = -1, halo = 4 + fires.size()})

func update(dt: float, t: float) -> void:
	var cp := g.cam.global_position
	for i in fires.size():
		var f: Dictionary = fires[i]
		var k := 0.75 + 0.25 * sin(t * 17.0 + i * 3.0) * sin(t * 6.3 + i)
		(f.light as OmniLight3D).light_energy = 2.4 * k
		g.world.set_dyn_halo(f.halo, f.pos + Vector3(0, 0.4, 0), Color(1.4 * k, 0.6 * k, 0.2 * k), 4.5)
		var d := U.hyp(cp.x - f.pos.x, cp.z - f.pos.z)
		# the Mobile renderer lights each mesh with only 8 omni lights: the fire's is on only nearby
		(f.light as OmniLight3D).visible = d < 40.0
		var near := d < 32.0 and g.phase != "menu"
		if near and f.voice < 0:
			f.voice = g.sfx.hold("fire_loop")
		elif not near and f.voice >= 0:
			g.sfx.release(f.voice)
			f.voice = -1
		if f.voice >= 0:
			var pp := g.pos_params(f.pos.x, 0.5, f.pos.z, 10.0)
			g.sfx.hold_update(f.voice, "fire_loop", pp.vol * 0.3, pp.pan, pp.lp)

func release_sounds() -> void:
	for f in fires:
		if f.voice >= 0:
			g.sfx.release(f.voice)
			f.voice = -1

# ---------------------------------------------------------------- rubble
## Broken concrete fallen against the buildings: heaps of chunks on the sidewalks, waist high, away
## from doors, hiding spots and clues (there is always the street to go round by).
func _rubble() -> void:
	var chunk := _chunk_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = g.world.tex("concrete")
	mat.albedo_color = Color(0.9, 0.87, 0.82)
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	var xs: Array = []
	# building walls: tall boxes that block sight
	var walls := []
	for i in g.col.x0.size():
		if g.col.y1[i] > 8.0 and (g.col.flags[i] & Col.F_LOS) and (g.col.x1[i] - g.col.x0[i]) * (g.col.z1[i] - g.col.z0[i]) > 30.0:
			walls.append(i)
	var made := 0
	var tries := 0
	while made < 26 and tries < 600 and walls.size():
		tries += 1
		var i: int = walls[rng.randi() % walls.size()]
		# a point just outside one face of the wall
		var side := rng.randi() % 4
		var x := rng.randf_range(g.col.x0[i], g.col.x1[i])
		var z := rng.randf_range(g.col.z0[i], g.col.z1[i])
		match side:
			0: x = g.col.x0[i] - 0.9
			1: x = g.col.x1[i] + 0.9
			2: z = g.col.z0[i] - 0.9
			3: z = g.col.z1[i] + 0.9
		if not g.world.on_slab(x, z) or not g.col.walkable(x, z, 0.5) or not _clear_of_play(x, z, 7.0):
			continue
		made += 1
		heaps.append(Vector2(x, z))
		var n := rng.randi_range(12, 20)
		var big := rng.randf_range(0.9, 1.5)
		# solid, and low enough to crouch behind out of its sight
		var hb := 0.95 * big
		g.col.add_box(x - hb, x + hb, 0.0, 0.85, z - hb, z + hb, Col.F_LOS)
		for j in n:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 1.9) * big
			var s := rng.randf_range(0.3, 0.85) * big * (1.0 - r / (2.4 * big + 0.01))
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(s * rng.randf_range(0.8, 1.6), s, s * rng.randf_range(0.8, 1.4)))
			xs.append(Transform3D(b, Vector3(x + cos(a) * r, 0.14 + s * 0.35, z + sin(a) * r)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = chunk
	mm.instance_count = xs.size()
	for k in xs.size():
		mm.set_instance_transform(k, xs[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.name = "Rubble"
	g.world.add_child(mi)

## Not where the game needs room: her hiding places and the way in, the hiding spots, the exits,
## the starting points and the clues' spots.
func _clear_of_play(x: float, z: float, r: float) -> bool:
	for l in g.data.locs:
		if U.hyp(l.ent[0] - x, l.ent[1] - z) < r or U.hyp(l.trail[0][0] - x, l.trail[0][1] - z) < r or U.hyp(l.trail[1][0] - x, l.trail[1][1] - z) < r:
			return false
	for h in g.data.hides:
		if U.hyp(h[0] - x, h[1] - z) < r:
			return false
	for s in g.data.starts:
		if U.hyp(s.x - x, s.z - z) < r:
			return false
	for e in g.data.exits:
		if U.hyp(e.x - x, e.z - z) < r * 2.0:
			return false
	for c in g.data.cluespots:
		if U.hyp(c.x - x, c.z - z) < 2.5:
			return false
	return true

## A rough lump of concrete: a box with its corners pulled about.
func _chunk_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var v := []
	for cx in [-0.5, 0.5]:
		for cy in [-0.5, 0.5]:
			for cz in [-0.5, 0.5]:
				v.append(Vector3(cx, cy, cz) + Vector3(r.randf_range(-0.18, 0.18), r.randf_range(-0.18, 0.18), r.randf_range(-0.18, 0.18)))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var d: Vector3 = v[f[3]]
		# (a b c d run anticlockwise seen from outside; Godot's front faces are clockwise)
		for tri in [[a, c, b], [a, d, c]]:
			var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
			for p in tri:
				st.set_normal(n)
				st.add_vertex(p)
	return st.commit()

# ---------------------------------------------------------------- its tracks
## Lines of three-toed prints a metre long across the streets, where it has walked.
func _tracks() -> void:
	var tex := _print_texture()
	var xs: Array = []
	var nodes: Array = g.nodes
	var used := {}
	var trails := 0
	var tries := 0
	while trails < 9 and tries < 200:
		tries += 1
		var a := rng.randi() % nodes.size()
		var nb: Array = nodes[a].n
		var b: int = int(nb[rng.randi() % nb.size()])
		var key := "%d-%d" % [mini(a, b), maxi(a, b)]
		if used.has(key):
			continue
		used[key] = true
		trails += 1
		tracks.append(Vector2(nodes[a].x, nodes[a].z))
		var A := Vector2(nodes[a].x, nodes[a].z)
		var B := Vector2(nodes[b].x, nodes[b].z)
		var dir := (B - A).normalized()
		var side := Vector2(-dir.y, dir.x)
		var len := A.distance_to(B)
		var off := rng.randf_range(-2.5, 2.5)
		var yaw := atan2(dir.x, dir.y)
		var k := 0
		var s := rng.randf_range(0.0, 3.0)
		while s < len:
			var p := A + dir * s + side * (off + (0.85 if k % 2 == 0 else -0.85))
			if g.col.walkable(p.x, p.y, 0.6) and not g.world.on_slab(p.x, p.y):
				var bs := Basis(Vector3.UP, yaw + rng.randf_range(-0.12, 0.12)).scaled(Vector3(1.0, 1.0, 1.0) * rng.randf_range(0.95, 1.1))
				xs.append(Transform3D(bs, Vector3(p.x, 0.014, p.y)))
			s += 3.1
			k += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 1.15)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.roughness = 0.12
	mat.render_priority = 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	mi.name = "Tracks"
	g.world.add_child(mi)

## A muddy, water-filled three-toed print, drawn here (heel pad and three long toes with claws).
func _print_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var heel := Vector2(64, 92)
	var toes := [Vector2(64, 14), Vector2(26, 34), Vector2(102, 34)]
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var dmin := p.distance_to(heel) / 26.0
			for t in toes:
				# distance to the segment heel -> toe, the toe narrowing to a claw
				var ab: Vector2 = t - heel
				var u := clampf((p - heel).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var w := lerpf(15.0, 6.0, u)
				dmin = minf(dmin, p.distance_to(heel + ab * u) / w)
			if dmin < 1.0:
				var depth := 1.0 - dmin
				var a := clampf(depth * 3.0, 0.0, 0.85)
				img.set_pixel(x, y, Color(0.05, 0.045, 0.04, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
