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
	get_root().get_texture().get_image().save_png("/tmp/opencode/view_editor.png")
	var pv = main._preview
	print("[v] preview size=%s dir=%s items=%d" % [str(pv.size), pv._storyboard_dir, pv._sb_render_items.size()])
	quit()
