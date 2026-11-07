## Shorts director for the movie maker (the recipes, cameras and flags are in scripts/director.gd):
##   godot --path godot --resolution 1080x1920 --fixed-fps 120 --write-movie out/clip.avi -s res://tests/short.gd -- --mode=flip --seed=3 --fps=120
extends SceneTree

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	root.add_child(load("res://scripts/director.gd").new())
