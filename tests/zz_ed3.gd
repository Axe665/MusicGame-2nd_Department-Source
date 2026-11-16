extends SceneTree

func _init() -> void:
	await process_frame
	print("[f] fit_size 1600x900=%s  1366x768=%s  1280x720=%s  1920x1080=%s" % [
		str(StoryboardEditor.fit_size(Vector2(1600, 900))),
		str(StoryboardEditor.fit_size(Vector2(1366, 768))),
		str(StoryboardEditor.fit_size(Vector2(1280, 720))),
		str(StoryboardEditor.fit_size(Vector2(1920, 1080)))])
	var main: Node = load("res://charter/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	var app: Node = get_root().get_node_or_null("App")
	app.open_set_file("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/sets/ReDIVE NEURON [导入].set.json")
	await create_timer(0.8).timeout
	main._open_storyboard_editor()
	await create_timer(1.2).timeout
	var ed = main._sb_editor
	var vp: Vector2 = get_root().get_visible_rect().size
	print("[f] 窗口=%s 对话框=%s pos=%s 底边=%.0f 右边缘=%.0f" % [str(vp), str(ed.size), str(ed.position),
		float(ed.position.y) + ed.size.y, float(ed.position.x) + ed.size.x])
	var col: Control = ed.find_child("EditorScroll", true, false)
	print("[f] 滚动容器=%s 内容高=%s 需要滚动=%s" % [str(col != null), str(col.get_child(0).size if col != null else Vector2.ZERO), str(col != null and col.get_child(0).size.y > col.size.y + 1.0)])
	get_root().get_texture().get_image().save_png("/tmp/opencode/ed_fit.png")
	quit()
