## Entry point: starts the game, the test bed when run with --testbed (or the older --chars / --bare test flags), or
## a Roof Run with --roofrun.
extends Node3D

func _ready() -> void:
	var test := false
	for a in OS.get_cmdline_user_args():
		if a == "--testbed" or a.begins_with("--chars") or a == "--bare" or a.begins_with("--bare="):
			test = true
		elif a == "--roofrun":
			# straight into a Roof Run (--auto: it plays itself)
			RoofRun.start.call_deferred(get_tree())
			return
	var n: Node = load("res://scripts/testbed.gd").new() if test else Game.new()
	add_child(n)
