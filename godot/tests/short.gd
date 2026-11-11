## Shorts director for the movie maker (the recipes, cameras and flags are in scripts/director.gd; --mode=endless
## records the Roof Run, scripts/roof_run.gd, playing itself):
##   godot --path godot --resolution 1080x1920 --fixed-fps 120 --write-movie out/clip.avi -s res://tests/short.gd -- --mode=flip --seed=3 --fps=120
extends SceneTree

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--mode=endless"):
		# the Roof Run playing itself (scripts/roof_run.gd), the events printed for the sound mix
		var run := RoofRun.new()
		run.record = true
		root.add_child(run)
		current_scene = run
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.add_child(load("res://scripts/director.gd").new())
