extends SceneTree

func _init() -> void:
	await process_frame
	var main: Node = load("res://charter/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	var app: Node = get_root().get_node_or_null("App")
	app.show_storyboard = true
	app.show_storyboard_background = true
	app.open_set_file("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/sets/ReDIVE NEURON [导入].set.json")
	await create_timer(2.2).timeout
	print("[w5] size=%s beat=%.2f" % [str(main._preview.size), main._preview.get_time_beat()])
	quit()
