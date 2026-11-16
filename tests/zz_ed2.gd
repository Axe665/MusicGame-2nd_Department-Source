extends SceneTree

func _dump(node: Node, depth := 0) -> void:
	if node is Control and depth <= 4:
		var c := node as Control
		print("[t] %s%s min=%s size=%s" % ["  ".repeat(depth), c.name, str(c.get_combined_minimum_size()), str(c.size)])
	for child in node.get_children():
		_dump(child, depth + 1)

func _init() -> void:
	await process_frame
	var main: Node = load("res://charter/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	var app: Node = get_root().get_node_or_null("App")
	app.open_set_file("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/sets/ReDIVE NEURON [导入].set.json")
	await create_timer(0.8).timeout
	main._open_storyboard_editor()
	await create_timer(1.0).timeout
	_dump(main._sb_editor)
	quit()
