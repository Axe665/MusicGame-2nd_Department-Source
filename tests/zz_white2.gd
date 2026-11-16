extends SceneTree

func _edges(tag: String, pv) -> void:
	var img: Image = get_root().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var samples := {
		"左": Vector2i(2, h / 2), "右": Vector2i(w - 3, h / 2),
		"上": Vector2i(w / 2, 2), "下": Vector2i(w / 2, h - 3),
		"左上": Vector2i(2, 2), "右上": Vector2i(w - 3, 2),
	}
	var out: Array[String] = []
	for key in samples.keys():
		out.append("%s=%s" % [key, img.get_pixel(samples[key].x, samples[key].y).to_html(false)])
	print("[w2] %s pv=%s svp=%s %s" % [tag, str(pv.size), str(pv._subviewport.size), " ".join(out)])
	img.save_png("/tmp/opencode/white2_%s.png" % tag)

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
	for i in 8:
		await create_timer(0.15).timeout
		_edges("p%02d" % i, main._playtest._preview)
	quit()
