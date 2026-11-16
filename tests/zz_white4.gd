extends SceneTree

func _init() -> void:
	await process_frame
	var text := FileAccess.get_file_as_string("/home/axe665/.local/share/godot/app_userdata/Tamaki₃ 制谱器/imports/DJ Raisei - ReDIVE NEURON (Wispy) [BEGINNER]_5dfb822b/sb/storyboard.osb")
	var board := Storyboard.parse(text, "storyboard.osb")
	for ms in [0.0, 500.0, 1000.0, 2000.0]:
		var items := board.sample(ms)
		print("[w4] ms=%.0f items=%d" % [ms, items.size()])
		for item in items:
			var c: Color = item["colour"]
			if c.r > 0.9 and c.g > 0.9 and c.b > 0.9:
				print("[w4]   白 path=%s pos=%s scale=%s alpha=%.2f add=%s layer=%s" % [
					String(item["path"]), str(item["pos"]), str(item["scale"]),
					float(item["alpha"]), str(item["additive"]), String(item["layer"])])
	quit()
