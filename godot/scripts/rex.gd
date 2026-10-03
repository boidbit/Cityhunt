## The T-Rex's body: the low-poly animated T-Rex by Quaternius (CC0, assets/trex), scaled up to a
## real one's size, its clips (idle, walk, run, attack, death, jump) blended by what Monster is doing,
## and a few procedural touches on top: the head scanning and lowering to sniff, the roar.
class_name Rex
extends Node3D

const SRC := "res://assets/trex/Trex.fbx"
const LENGTH := 11.0          # nose to tail tip, metres
const CLIPS := {idle = "TRex_Idle", walk = "TRex_Walk", run = "TRex_Run", attack = "TRex_Attack", death = "TRex_Death", jump = "TRex_Jump"}
## Ground speed (m/s) at which the walk and run clips play at their recorded rate, so the feet
## don't skate: how far a back foot travels while it is on the ground, at this size.
var walk_speed := 4.1
var run_speed := 9.9

var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var clip_names := {}          # short name -> name in the AnimationPlayer
var cur := ""
var once := ""                # a one-shot clip playing (attack), back to the loop when it ends
var head := -1
var neck := -1
var jaw := -1
var look := 0.0               # head turned left/right (rad), eased by Monster
var sniff := 0.0              # 0..1 head down to the ground
var roar := 0.0               # 0..1 head up, jaw open
var scale_k := 1.0
var hook: PoseHook

func _ready() -> void:
	model = load(SRC).instantiate()
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in anim.get_animation_list():
		for k in CLIPS:
			if String(a).ends_with(CLIPS[k]):
				clip_names[k] = a
				var an := anim.get_animation(a)
				an.loop_mode = Animation.LOOP_NONE if k in ["attack", "death", "jump"] else Animation.LOOP_LINEAR
	# size: nose to tail tip from the bones (the skinned mesh's own box is not to scale), to LENGTH
	var nose := _bone_rest_pos("Head_end")
	var tail := _bone_rest_pos("Tail5_end")
	var long := nose.distance_to(tail)
	scale_k = LENGTH / long if long > 0.001 else 1.0
	model.scale = Vector3.ONE * scale_k
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.extra_cull_margin = 4.0
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_skin(m)
	head = _find_bone(["head"])
	neck = _find_bone(["neck"])
	jaw = _find_bone(["jaw", "mouth", "lowerjaw"])
	_eyes()
	hook = PoseHook.new()
	skel.add_child(hook)
	hook.fn = _pose
	anim.animation_finished.connect(func(_n): once = "")
	play("idle", 0.0)

## The flat cartoon colours made darker and wet-looking, closer to a real animal at night in the rain.
func _skin(m: MeshInstance3D) -> void:
	for s in m.mesh.get_surface_count():
		var src := m.mesh.surface_get_material(s) as StandardMaterial3D
		if src == null:
			continue
		var mat := src.duplicate() as StandardMaterial3D
		var n := String(src.resource_name).to_lower()
		var c := mat.albedo_color
		if n == "green":
			c = Color(0.16, 0.17, 0.14)
		elif n == "lightgreen":
			c = Color(0.36, 0.33, 0.26)
		elif n == "black":
			c = Color(0.05, 0.05, 0.05)
		mat.albedo_color = c
		mat.roughness = 0.5 if n in ["green", "lightgreen", "black"] else 0.35
		mat.metallic_specular = 0.6
		m.set_surface_override_material(s, mat)

var eye_mats: Array[StandardMaterial3D] = []

## Two eyes that catch the light, glowing faintly amber in the dark.
func _eyes() -> void:
	if head < 0 or skel.find_bone("Head_end") < 0:
		return
	var a := skel.get_bone_global_rest(head).origin
	var b := skel.get_bone_global_rest(skel.find_bone("Head_end")).origin
	var att := BoneAttachment3D.new()
	att.bone_name = skel.get_bone_name(head)
	skel.add_child(att)
	var to_head := skel.get_bone_global_rest(head).affine_inverse()
	var len := a.distance_to(b)
	for side in [-1.0, 1.0]:
		# in skeleton space: along the head, out to each side, a little up
		var p := a.lerp(b, 0.42) + Vector3(side * len * 0.24, 0.0, len * 0.18)
		var q := QuadMesh.new()
		q.size = Vector2(0.3, 0.3)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = load("res://assets/baked/textures/glow.png")
		mat.albedo_color = Color(1.0, 0.62, 0.2, 0.8)
		mat.disable_fog = true
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var e := MeshInstance3D.new()
		e.mesh = q
		e.material_override = mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.position = to_head * p
		att.add_child(e)
		eye_mats.append(mat)

## Eye glow 0..1 (facing the camera, at night).
func set_eyes(k: float) -> void:
	for m in eye_mats:
		m.albedo_color.a = 0.85 * k

## A bone's rest position in the model's own space (before scale_k).
func _bone_rest_pos(n: String) -> Vector3:
	var i := skel.find_bone(n)
	if i < 0:
		return Vector3()
	var to_model := model.global_transform.affine_inverse() * skel.global_transform
	return to_model * skel.get_bone_global_rest(i).origin

func _find_bone(keys: Array) -> int:
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		for k in keys:
			if n.contains(k) and not n.contains("end"):
				return i
	return -1

func has_clip(k: String) -> bool:
	return clip_names.has(k)

func play(k: String, blend := 0.25, speed := 1.0) -> void:
	if not clip_names.has(k):
		return
	if once != "" and k != once:
		return
	if cur != k:
		anim.play(clip_names[k], blend)
		cur = k
	anim.speed_scale = speed

## A one-shot clip (attack) over whatever loop is playing; returns to the loop when it ends.
func play_once(k: String, speed := 1.0) -> void:
	if not clip_names.has(k):
		return
	once = ""
	cur = ""
	play(k, 0.15, speed)
	once = k

## Walk cycle for a ground speed in m/s.
func loco(speed: float) -> void:
	if once != "":
		return
	if speed < 0.35:
		play("idle", 0.35)
	elif speed < 5.2:
		play("walk", 0.3, clampf(speed / walk_speed, 0.5, 1.5))
	else:
		play("run", 0.3, clampf(speed / run_speed, 0.62, 1.5))

## Head and jaw on top of the clip: turned to look, lowered to sniff, raised to roar.
func _pose(_dt: float) -> void:
	# (skeleton space is the source file's: z up, x across, the head towards -y)
	if neck >= 0:
		_turn(neck, Vector3(0, 0, 1), look * 0.5)
		_turn(neck, Vector3(1, 0, 0), sniff * 0.45 - roar * 0.55)
	if head >= 0:
		_turn(head, Vector3(0, 0, 1), look * 0.5)
		_turn(head, Vector3(1, 0, 0), sniff * 0.35 - roar * 0.4)
	if jaw >= 0:
		_turn(jaw, Vector3(1, 0, 0), roar * 0.7)

## Turn a bone about an axis given in the model's space (character space).
func _turn(i: int, axis: Vector3, a: float) -> void:
	if absf(a) < 0.0005:
		return
	var gp := skel.get_bone_global_pose(i)
	gp.basis = Basis(axis.normalized(), a) * gp.basis
	skel.set_bone_global_pose(i, gp)

## World position of the head (for the bite reach), or a point ahead of the body without a head bone.
func head_pos() -> Vector3:
	if head >= 0:
		return skel.global_transform * skel.get_bone_global_pose(head).origin
	return global_position + global_basis.z * 4.0 + Vector3(0, 3.5, 0)

func foot_pos(left: bool) -> Vector3:
	var i := skel.find_bone("BackFoot.L" if left else "BackFoot.R")
	if i < 0:
		return global_position
	return skel.global_transform * skel.get_bone_global_pose(i).origin
