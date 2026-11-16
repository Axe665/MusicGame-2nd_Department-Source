extends SceneTree

func _init() -> void:
	await process_frame
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await create_timer(0.4).timeout
	var main: Node = load("res://charter/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	var app: Node = get_root().get_node_or_null("App")
	app.open_set_file("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/sets/ReDIVE NEURON [导入].set.json")
	await create_timer(0.8).timeout
	main._open_storyboard_editor()
	await create_timer(1.2).timeout
	var ed = main._sb_editor
	print("[ed] 窗口=%s 对话框=%s pos=%s" % [str(get_root().size), str(ed.size), str(ed.position)])
	get_root().get_texture().get_image().save_png("/tmp/opencode/ed_1280.png")
	quit()
