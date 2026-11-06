## Reads a motion from the CMU Graphics Lab Motion Capture Database (mocap.cs.cmu.edu, "free for all
## uses"): the actor's skeleton (.asf) and his motion (.amc), and poses him frame by frame.
## Space is the capture's own: Y up, metres, and in the rest pose (every rotation zero) the actor
## faces +z with his left side towards +x, which is how the Rocketbox man stands too.
extends RefCounted

const UNIT := 0.0254 / 0.45   # ":units length 0.45": a length unit is 1/0.45 inch

var names: Array[String] = []  # "root" first, then every bone after its parent
var parent := {}               # bone -> parent bone
var dir := {}                  # bone -> its direction in the rest pose (unit vector)
var length := {}               # bone -> metres
var axis := {}                 # bone -> Basis the bone's rotations are given in
var dof := {}                  # bone -> PackedInt32Array, the axes (0 x, 1 y, 2 z) its values turn about
var frames: Array = []         # [frame] -> {bone: PackedFloat32Array}
var fps := 120.0

static func euler(d: Vector3) -> Basis:
	# "XYZ": about x, then y, then z, all about fixed axes
	var r := d * (PI / 180.0)
	return Basis(Vector3(0, 0, 1), r.z) * Basis(Vector3(0, 1, 0), r.y) * Basis(Vector3(1, 0, 0), r.x)

func load_asf(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "can't read " + path)
	var lines := f.get_as_text().split("\n")
	var children := {"root": []}
	var i := 0
	var in_bones := false
	while i < lines.size():
		var l := lines[i].strip_edges()
		if l == ":bonedata":
			in_bones = true
		elif l == ":hierarchy":
			in_bones = false
			i += 2
			while lines[i].strip_edges() != "end":
				var t := lines[i].strip_edges().split(" ", false)
				for c in t.slice(1):
					parent[c] = t[0]
					children[t[0]].append(c)
				i += 1
			break
		elif in_bones and l == "begin":
			var name := ""
			var d := Vector3()
			var len := 0.0
			var ax := Vector3()
			var dofs := PackedInt32Array()
			i += 1
			while lines[i].strip_edges() != "end":
				var t := lines[i].strip_edges().split(" ", false)
				match t[0]:
					"name":
						name = t[1]
					"direction":
						d = Vector3(float(t[1]), float(t[2]), float(t[3]))
					"length":
						len = float(t[1]) * UNIT
					"axis":
						ax = Vector3(float(t[1]), float(t[2]), float(t[3]))
					"dof":
						for a in t.slice(1):
							dofs.append("xyz".find(a[1]))
				i += 1
			dir[name] = d.normalized()
			length[name] = len
			axis[name] = euler(ax)
			dof[name] = dofs
			children[name] = []
		i += 1
	# parents first
	names = ["root"]
	var k := 0
	while k < names.size():
		for c in children[names[k]]:
			names.append(c)
		k += 1

func load_amc(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "can't read " + path)
	var cur := {}
	for line in f.get_as_text().split("\n"):
		var l := line.strip_edges()
		if l.is_empty() or l[0] == "#" or l[0] == ":":
			continue
		var t := l.split(" ", false)
		if t.size() == 1 and t[0].is_valid_int():
			cur = {}
			frames.append(cur)
			continue
		var v := PackedFloat32Array()
		for x in t.slice(1):
			v.append(float(x))
		cur[t[0]] = v

## One frame (k may fall between two frames): every bone's rotation in the capture's space and the
## joint it starts at ("root": the hips).
func pose(k: float) -> Dictionary:
	var k0 := clampi(int(floor(k)), 0, frames.size() - 1)
	var k1 := mini(k0 + 1, frames.size() - 1)
	var w := clampf(k - k0, 0.0, 1.0)
	var a: Dictionary = _fk(frames[k0])
	if w < 1e-4 or k1 == k0:
		return a
	var b: Dictionary = _fk(frames[k1])
	var out := {"rot": {}, "at": {}, "tip": {}}
	for n in names:
		out.rot[n] = Basis((a.rot[n] as Basis).get_rotation_quaternion().slerp((b.rot[n] as Basis).get_rotation_quaternion(), w))
		out.at[n] = (a.at[n] as Vector3).lerp(b.at[n], w)
		out.tip[n] = (a.tip[n] as Vector3).lerp(b.tip[n], w)
	return out

func _fk(fr: Dictionary) -> Dictionary:
	var rot := {}
	var at := {}      # where each bone starts
	var tip := {}     # where it ends
	for n in names:
		if n == "root":
			var v: PackedFloat32Array = fr["root"]
			rot[n] = euler(Vector3(v[3], v[4], v[5]))
			at[n] = Vector3(v[0], v[1], v[2]) * UNIT
			tip[n] = at[n]
			continue
		var e := Vector3()
		var vals: PackedFloat32Array = fr.get(n, PackedFloat32Array())
		var dofs: PackedInt32Array = dof[n]
		for j in dofs.size():
			e[dofs[j]] = vals[j]
		var c: Basis = axis[n]
		rot[n] = rot[parent[n]] * c * euler(e) * c.inverse()
		at[n] = tip[parent[n]]
		tip[n] = at[n] + (rot[n] as Basis) * (dir[n] as Vector3) * (length[n] as float)
	return {"rot": rot, "at": at, "tip": tip}
