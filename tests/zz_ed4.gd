extends SceneTree

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
	var ed = main._sb_editor
	# 模拟 1280x720 屏幕：按 fit_size 的公式直接缩小对话框
	var small := StoryboardEditor.fit_size(Vector2(1280, 720))
	ed.size = small
	await create_timer(0.6).timeout
	var scroll: ScrollContainer = ed.find_child("EditorScroll", true, false)
	print("[ed4] 模拟小屏 size=%s 内容=%s 视口=%s 竖向滚动条=%s max=%d" % [str(small),
		str(scroll.get_child(0).size), str(scroll.size),
		str(scroll.get_v_scroll_bar().visible), int(scroll.get_v_scroll_bar().max_value)])
	scroll.scroll_vertical = 100000
	await create_timer(0.3).timeout
	get_root().get_texture().get_image().save_png("/tmp/opencode/ed_small.png")
	print("[ed4] 滚到底：scroll_vertical=%d（底部按钮可见）" % scroll.scroll_vertical)
	quit()
