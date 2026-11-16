extends SceneTree

func _shot(tag: String, pv) -> void:
	var img: Image = get_root().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var out: Array[String] = []
	for x in [2, 40, 120, w / 2, w - 121, w - 41, w - 3]:
		out.append("%d:%s" % [x, img.get_pixel(x, h / 2).to_html(false)])
	print("[w3] %s ms=%.0f %s" % [tag, pv.get_chart_ms() if pv.has_method("get_chart_ms") else -1.0, " ".join(out)])
	img.save_png("/tmp/opencode/w3_%s.png" % tag)

func _init() -> void:
	await process_frame
	var main: Node = load("res://charter/main.tscn").instantiate()
	get_root().add_child(main)
	await process_frame
	var app: Node = get_root().get_node_or_null("App")
	app.show_storyboard = true
	app.show_storyboard_background = true
	app.open_set_file("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/sets/ReDIVE NEURON [导入].set.json")
	await create_timer(0.8).timeout
	main._start_playtest(false)
	var pt = main._playtest
	# 等倒计时结束
	for i in 60:
		await create_timer(0.1).timeout
		if pt._ready_layer == null or not pt._ready_layer.visible:
			break
	print("[w3] ready 结束")
	for i in 6:
		_shot("b%d" % i, pt._preview)
		await create_timer(0.25).timeout
	quit()
