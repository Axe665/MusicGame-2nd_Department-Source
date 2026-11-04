class_name Preview3D
extends Control

signal cursor_changed(u: float, valid: bool)
signal notice(message: String, level: String)

const RING_WIDTH := 4.0
const GLOW_WIDTH := 18.0
const PREVIEW_MARGIN := 1.24
const MOUSE_TILT_DEGREES := 11.0
## Path / Trace 的视觉尺寸：相对旧版 ×2。只放大笔画与头尾，不改轨迹几何与判定。
const PATH_SIZE_SCALE := 2.0
const TRACE_SIZE_SCALE := 2.0

var chart_override: Chart = null
var follow_app: bool = true
var time_beat: float = 0.0
var playing: bool = false
var interactive: bool = true
var playtest_mode: bool = false
var show_hud: bool = true
var show_debug: bool = false
var flow_scale: float = 1.0
var star_speed: float = 1.0
var custom_cursor_visible: bool = true
var mouse_tilt: bool = true
var use_3d_ring: bool = true:
	set(value):
		if use_3d_ring == value:
			return
		use_3d_ring = value
		if _viewport_container != null:
			_viewport_container.visible = value
		if _subviewport != null:
			_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
			_render_mode = -1 if value else SubViewport.UPDATE_DISABLED
		_force_3d_frame = value
		_mesh_dirty = true
		if _overlay != null:
			_overlay.queue_redraw()

var _app: Node = null

var hud_accuracy: float = -1.0
var hud_rating: String = "—"
var hud_errors: Array[float] = []

var cursor_u: float = 0.0
var cursor_valid: bool = false
var mouse_screen: Vector2 = Vector2.ZERO
var mouse_inside: bool = false

var _bg: TextureRect
var _background_image: TextureRect
var _last_background_path: String = ""
var _video: VideoStreamPlayer
var _viewport_container: SubViewportContainer
var _subviewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _ring_root: Node3D
var _ring_mesh: MeshInstance3D
var _glow_mesh: MeshInstance3D
var _stage_mesh: MeshInstance3D
var _bezel_mesh: MeshInstance3D
var _shadow_mesh: MeshInstance3D
var _disc_mesh: MeshInstance3D
var _beams_mesh: MeshInstance3D
var _frame_mesh: MeshInstance3D
var _amber_mesh: MeshInstance3D
var _rim_mesh: MeshInstance3D
var _overlay: Control
var _ring_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _stage_material: StandardMaterial3D
var _bezel_material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _disc_material: StandardMaterial3D
var _beams_material: StandardMaterial3D
var _frame_material: StandardMaterial3D
var _amber_material: StandardMaterial3D
var _rim_material: StandardMaterial3D

var _last_mesh_beat: float = -9999.0
var _mesh_dirty: bool = true
var _last_chart_ref: Chart = null
var _last_video_path: String = ""
var _video_load_failed: bool = false
var _last_cursor_emit: Vector2 = Vector2(-999, -999)
var _cursor_cache_key: String = ""
var _sorted_notes_cache: Array[Note] = []
var _trace_cache: Dictionary = {}
var _path_runs_cache: Dictionary = {}
var _trace_cache_mesh: String = ""
var _sorted_notes_chart: Chart = null
var _last_view_key: String = ""
var _last_fit_key: String = ""
var _last_mesh_key: String = ""
var _last_mesh_usec: int = 0
var _last_process_time: float = -9999.0
var _last_mouse_screen: Vector2 = Vector2(-9999, -9999)
var _cursor_trail: Array[Dictionary] = []
var _avg_radius_cache: float = 100.0
var _avg_radius_key: String = ""
var _last_overlay_time: float = -9999.0
var _render_mode: int = -1
var _render_frame: int = 0
var _tilt: Vector2 = Vector2.ZERO
var _tilt_target: Vector2 = Vector2.ZERO
var _force_3d_frame: bool = false
var _boundary_frame_cache: BoundaryFrame = null
var _max_design_radius: float = -1.0
var _path_local_cache: Dictionary = {}

var _drag_segment: int = -1
var _drag_endpoint: int = -1
var _drag_shape_backup: Dictionary = {}
var _drag_visual: int = -1
var _drag_visual_note: Note = null
var _drag_visual_start: Vector2 = Vector2.ZERO
var _drag_visual_db: float = 0.0
var _drag_visual_da: float = 0.0
var _drawing_trace: bool = false
var _drawing_red: bool = false
var _red_region: Region = null
var _red_start_u: float = 0.0
var _red_start_beat: float = 0.0
var _red_start_mouse: Vector2 = Vector2.ZERO
var _pulses: Array[Dictionary] = []
var _arc_flashes: Array[Dictionary] = []
# 音符外观与打击特效方案（网页 Note & Hit Lab 里可对比选择）。
var note_skin: String = "candy"
var hit_fx_style: String = "burst"
var _skin_cache: Dictionary = {}
var _skin_cache_key: String = ""
var trace_cuts: Dictionary = {}
var path_cuts: Dictionary = {}
var path_cut_versions: Dictionary = {}
var _drawing_path: bool = false
var _path_points: Array[Vector2] = []
var _path_head_angle: float = 0.0
var _trace_points: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app = get_node_or_null("/root/App")
	_build_layers()
	_build_3d()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.selection_changed.connect(_on_selection_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.tool_changed.connect(_on_tool_changed)
	set_process(true)


func _exit_tree() -> void:
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func set_suspended(suspended: bool) -> void:
	set_process(not suspended)
	if _subviewport == null:
		return
	if suspended:
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_render_mode = SubViewport.UPDATE_DISABLED
	else:
		_force_3d_frame = use_3d_ring
		_render_mode = -1


func get_chart() -> Chart:
	if chart_override != null:
		return chart_override
	if _app == null:
		return null
	return _app.chart


func get_time_beat() -> float:
	if follow_app and _app != null:
		return _app.playhead_beat
	return time_beat


func current_view() -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return ViewState.default_state()
	return BoundaryRuntime.eval_view(chart, get_time_beat())


func _build_layers() -> void:
	_bg = TextureRect.new()
	_bg.name = "StageBackground"
	var space := GradientTexture2D.new()
	space.width = 512
	space.height = 512
	space.fill = GradientTexture2D.FILL_RADIAL
	space.fill_from = Vector2(0.5, 0.46)
	space.fill_to = Vector2(1.0, 0.95)
	var space_gradient := Gradient.new()
	space_gradient.set_color(0, Color("#151D2B"))
	space_gradient.set_color(1, Color("#05070B"))
	space.gradient = space_gradient
	_bg.texture = space
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_background_image = TextureRect.new()
	_background_image.name = "BackgroundImage"
	_background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_image.modulate = Color(1, 1, 1, 0.32)
	_background_image.visible = false
	add_child(_background_image)
	_background_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_video = VideoStreamPlayer.new()
	_video.name = "Video"
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	_video.expand = true
	_video.volume_db = -80.0
	add_child(_video)
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "ViewportContainer"
	_viewport_container.stretch = false
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_subviewport = SubViewport.new()
	_subviewport.name = "SubViewport"
	_subviewport.transparent_bg = true
	_subviewport.own_world_3d = true
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	_subviewport.scaling_3d_scale = 0.8
	_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_subviewport)

	_overlay = Control.new()
	_overlay.set_script(load("res://charter/preview_overlay.gd"))
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set("preview", self)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.visible = use_3d_ring


func _build_3d() -> void:
	_world = Node3D.new()
	_world.name = "World3D"
	_subviewport.add_child(_world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.20, 0.26, 1.0)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_world.add_child(world_env)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 42.0
	_camera.near = 1.0
	_camera.far = 6000.0
	_camera.position = Vector3(0, 0, 1200)
	_world.add_child(_camera)
	_camera.current = true
	_camera.look_at(Vector3.ZERO, Vector3.UP)

	_ring_root = Node3D.new()
	_ring_root.name = "RingRoot"
	_world.add_child(_ring_root)

	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.albedo_color = Color(0.62, 0.64, 0.68, 0.95)
	_ring_material.render_priority = 3

	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.albedo_color = Color(0.37, 0.85, 0.81, 0.12)
	_glow_material.render_priority = 2

	_stage_material = StandardMaterial3D.new()
	_stage_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stage_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stage_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stage_material.albedo_color = Color(0.62, 0.68, 0.78, 0.16)
	_stage_material.render_priority = -2

	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_disc_material.albedo_color = Color(0.05, 0.07, 0.10, 0.45)
	_disc_material.render_priority = -3

	_beams_material = StandardMaterial3D.new()
	_beams_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beams_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beams_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beams_material.albedo_color = Color(0.50, 0.70, 0.78, 0.032)
	_beams_material.render_priority = -2

	_frame_material = StandardMaterial3D.new()
	_frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame_material.albedo_color = Color(0.96, 0.95, 0.90, 0.92)
	_frame_material.render_priority = 4

	_amber_material = StandardMaterial3D.new()
	_amber_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_amber_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_amber_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_amber_material.albedo_color = Color(0.94, 0.55, 0.21, 0.84)
	_amber_material.render_priority = 3

	_rim_material = StandardMaterial3D.new()
	_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_material.albedo_color = Color(0.02, 0.03, 0.045, 0.72)
	_rim_material.render_priority = -4

	_bezel_material = StandardMaterial3D.new()
	_bezel_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bezel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bezel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bezel_material.albedo_color = Color(0.95, 0.90, 0.78, 0.80)
	_bezel_material.render_priority = 4

	_shadow_material = StandardMaterial3D.new()
	_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_material.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	_shadow_material.render_priority = 1

	_disc_mesh = MeshInstance3D.new()
	_ring_root.add_child(_disc_mesh)
	_build_disc()
	_beams_mesh = MeshInstance3D.new()
	_ring_root.add_child(_beams_mesh)
	_build_beams()
	_rim_mesh = MeshInstance3D.new()
	_rim_mesh.position = Vector3(0, 0, -34)
	_ring_root.add_child(_rim_mesh)
	_build_rim()
	_stage_mesh = MeshInstance3D.new()
	_ring_root.add_child(_stage_mesh)
	_build_stage()
	_bezel_mesh = MeshInstance3D.new()
	_ring_root.add_child(_bezel_mesh)
	_build_bezel_gpu()
	_frame_mesh = MeshInstance3D.new()
	_ring_root.add_child(_frame_mesh)
	_build_frame()
	_amber_mesh = MeshInstance3D.new()
	_ring_root.add_child(_amber_mesh)
	_build_amber()
	_shadow_mesh = MeshInstance3D.new()
	_shadow_mesh.position = Vector3(0, -26, -2)
	_ring_root.add_child(_shadow_mesh)
	_glow_mesh = MeshInstance3D.new()
	_ring_root.add_child(_glow_mesh)
	_ring_mesh = MeshInstance3D.new()
	_ring_root.add_child(_ring_mesh)


func _process(_delta: float) -> void:
	var chart := get_chart()
	if chart == null:
		return
	if follow_app and _app != null and _app.chart != _last_chart_ref:
		_last_chart_ref = _app.chart
		_mesh_dirty = true
		_last_video_path = ""
		_last_background_path = ""
		_video_load_failed = false
		_last_fit_key = ""
		_last_mesh_key = ""
	_update_mouse_tilt(_delta)
	for i in range(_pulses.size() - 1, -1, -1):
		_pulses[i]["age"] = float(_pulses[i].get("age", 0.0)) + _delta
		if float(_pulses[i]["age"]) > 0.5:
			_pulses.remove_at(i)
	for i in range(_arc_flashes.size() - 1, -1, -1):
		_arc_flashes[i]["age"] = float(_arc_flashes[i].get("age", 0.0)) + _delta
		if float(_arc_flashes[i]["age"]) > 0.32:
			_arc_flashes.remove_at(i)
	var t := get_time_beat()
	var time_changed := absf(t - _last_process_time) > 0.0005
	var mesh_key := _mesh_key(chart, t)
	var view_changed := _update_transform(t)
	var flat_dirty := _mesh_dirty and not use_3d_ring
	if use_3d_ring and (_mesh_dirty or mesh_key != _last_mesh_key):
		# 形变动画只需 30Hz；拖动几何时立即重建，避免手感发飘。
		var now_usec := Time.get_ticks_usec()
		if _mesh_dirty or now_usec - _last_mesh_usec >= 33333:
			_update_ring_mesh(chart, t)
			_last_mesh_key = mesh_key
			_last_mesh_usec = now_usec
			view_changed = true
	if not use_3d_ring and _mesh_dirty:
		_mesh_dirty = false
	_update_background(chart)
	_update_video(chart, t)
	var beat_phase := fposmod(t, 1.0)
	_glow_material.albedo_color = Color(0.37, 0.92, 0.86, 0.10 + 0.09 * exp(-beat_phase * 7.0))
	if playtest_mode:
		mouse_screen = get_local_mouse_position()
		mouse_inside = true
	var mouse_moved := mouse_screen.distance_to(_last_mouse_screen) > 0.1
	if mouse_inside and (playtest_mode or (playing and Engine.get_process_frames() % 6 == 0) or mouse_moved):
		_update_cursor()
	_update_cursor_trail(_delta)
	var needs_overlay := time_changed or mouse_moved or view_changed or flat_dirty or not _cursor_trail.is_empty()
	if needs_overlay:
		_overlay.queue_redraw()
	if use_3d_ring:
		_update_3d_mode(playing or playtest_mode or _tilt.distance_to(_tilt_target) > 0.01, view_changed or _mesh_dirty)
	_last_process_time = t
	_last_mouse_screen = mouse_screen


func _mesh_key(chart: Chart, beat: float) -> String:
	var parts: Array[String] = []
	for event in chart.events:
		if beat < event.start_beat:
			continue
		if beat <= event.end_beat:
			parts.append("%s:m:%.6f" % [event.id, beat])
		elif event.end_behavior == "hold":
			parts.append("%s:h" % event.id)
		elif beat <= event.end_beat + event.restore_duration:
			parts.append("%s:r:%.6f" % [event.id, beat])
		else:
			parts.append("%s:p" % event.id)
	if parts.is_empty():
		return "base:" + chart.default_shape_id
	return "|".join(parts)


func _update_3d_mode(animate: bool, changed: bool) -> void:
	if _subviewport == null:
		return
	var desired := SubViewport.UPDATE_ONCE if changed else SubViewport.UPDATE_DISABLED
	if _force_3d_frame:
		desired = SubViewport.UPDATE_ONCE
		_force_3d_frame = false
	if animate:
		desired = SubViewport.UPDATE_ALWAYS
	elif not changed and _render_mode == SubViewport.UPDATE_ALWAYS:
		desired = SubViewport.UPDATE_DISABLED
	if desired != _render_mode:
		_subviewport.render_target_update_mode = desired
		_render_mode = desired


func _update_mouse_tilt(delta: float) -> void:
	if not mouse_tilt or not (mouse_inside or playtest_mode):
		_tilt_target = Vector2.ZERO
	elif size.x > 1.0 and size.y > 1.0:
		var local := get_local_mouse_position()
		var nx := clampf((local.x - size.x * 0.5) / (size.x * 0.5), -1.0, 1.0)
		var ny := clampf((local.y - size.y * 0.5) / (size.y * 0.5), -1.0, 1.0)
		var amount := 7.0 if playtest_mode else MOUSE_TILT_DEGREES
		_tilt_target = Vector2(-ny * amount, nx * amount)
	var weight := 1.0 - exp(-maxf(0.0, delta) * 10.0)
	_tilt = _tilt.lerp(_tilt_target, weight)
	if _tilt_target == Vector2.ZERO and _tilt.length() < 0.01:
		_tilt = Vector2.ZERO


func _update_transform(beat: float) -> bool:
	var chart := get_chart()
	if chart == null:
		return false
	var view := BoundaryRuntime.eval_view(chart, beat)
	var rotation := float(view.get("rotation", 0.0))
	var tilt_x := float(view.get("tilt_x", 0.0))
	var tilt_y := float(view.get("tilt_y", 0.0))
	var zoom := float(view.get("zoom", 1.0))
	var ellipse := float(view.get("ellipse", 1.0))
	if bool(chart.metadata.get("face_camera", true)):
		# 正对镜头只忽略谱面 ViewState 的倾斜；鼠标视差仍然保留。
		tilt_x = 0.0
		tilt_y = 0.0
		ellipse = 1.0
	if playtest_mode:
		# 试玩只保留平面内旋转 + 鼠标视差，不跟随谱面倾斜。
		tilt_x = 0.0
		tilt_y = 0.0
		ellipse = 1.0
	var key := "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [rotation, tilt_x, tilt_y, zoom, ellipse, _tilt.x, _tilt.y]
	if key == _last_view_key:
		return false
	_last_view_key = key
	var basis := Basis(Vector3(0, 0, 1), deg_to_rad(rotation))
	basis = basis * Basis(Vector3(1, 0, 0), deg_to_rad(tilt_x + _tilt.x))
	basis = basis * Basis(Vector3(0, 1, 0), deg_to_rad(tilt_y + _tilt.y))
	_ring_root.transform = Transform3D(basis.scaled(Vector3(zoom * ellipse, zoom, zoom)), Vector3(-_tilt.y * 2.8, -_tilt.x * 2.8, 0.0))
	var fit_key := "%.3f|%.3f|%d|%.0f|%.0f" % [zoom, ellipse, 1 if playtest_mode else 0, size.x, size.y]
	if fit_key != _last_fit_key:
		_last_fit_key = fit_key
		_update_camera_fit(chart, zoom, ellipse)
	return true


func _update_camera_fit(chart: Chart, zoom: float, ellipse: float) -> void:
	if _max_design_radius < 0.0:
		_max_design_radius = 520.0
		for shape in chart.sorted_shapes():
			for data in shape.sample_points(32):
				var point: Vector2 = data.point
				_max_design_radius = maxf(_max_design_radius, point.length())
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	# 试玩时把环放大到接近 Estella 的满屏比例；编辑器保持原来的留白。
	var margin := 1.06 if playtest_mode else PREVIEW_MARGIN
	var wanted := _max_design_radius * maxf(0.5, zoom) * maxf(0.5, ellipse) * margin
	var distance := wanted / tan(deg_to_rad(_camera.fov * 0.5)) / minf(1.0, aspect)
	distance = clampf(distance, 500.0, 6000.0)
	_camera.position = Vector3(0, 0, distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _update_ring_mesh(chart: Chart, beat: float) -> void:
	var points := _frame_for(chart, beat).sample_points(256)
	_ring_mesh.mesh = _build_ribbon(points, RING_WIDTH, _ring_material)
	_glow_mesh.mesh = _build_ribbon(points, GLOW_WIDTH, _glow_material)
	_shadow_mesh.mesh = _build_ribbon(points, 30.0, _shadow_material)
	_last_mesh_beat = beat
	_mesh_dirty = false


func _build_beams() -> void:
	# 终末地式舞台不再使用八束光，保留空节点避免影响旧的渲染开关。
	_beams_mesh.mesh = ImmediateMesh.new()


func _build_rim() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _rim_material)
	var inner := 512.0
	var outer := 600.0
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		var p0 := Vector2(cos(a0), sin(a0))
		var p1 := Vector2(cos(a1), sin(a1))
		mesh.surface_add_vertex(Vector3(p0.x * inner, p0.y * inner, 0.0))
		mesh.surface_add_vertex(Vector3(p0.x * outer, p0.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * outer, p1.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p0.x * inner, p0.y * inner, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * outer, p1.y * outer, 0.0))
		mesh.surface_add_vertex(Vector3(p1.x * inner, p1.y * inner, 0.0))
	mesh.surface_end()
	_rim_mesh.mesh = mesh


func _build_disc() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _disc_material)
	var radius := 640.0
	for i in 96:
		var a0 := TAU * float(i) / 96.0
		var a1 := TAU * float(i + 1) / 96.0
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, -48.0))
		mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, -48.0))
	mesh.surface_end()
	_disc_mesh.mesh = mesh


func _build_stage() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _stage_material)
	for radius in [360.0, 420.0, 620.0]:
		var steps := 96
		for i in steps:
			var a0 := TAU * float(i) / float(steps)
			var a1 := TAU * float(i + 1) / float(steps)
			mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, -30.0))
			mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, -30.0))
	# 稀疏斜向刻线，替代原来的八条径向线。
	for angle in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(angle)
		var direction := Vector2(cos(a), sin(a))
		for offset in [-2.0, 2.0]:
			var normal: Vector2 = Vector2(-direction.y, direction.x) * offset
			mesh.surface_add_vertex(Vector3((direction * 520.0 + normal).x, (direction * 520.0 + normal).y, -30.0))
			mesh.surface_add_vertex(Vector3((direction * 590.0 + normal).x, (direction * 590.0 + normal).y, -30.0))
	mesh.surface_end()
	_stage_mesh.mesh = mesh


func _build_frame() -> void:
	# 白色分段外弧：角度取自终末地菜单的 5 段开口弧。
	var segments := [[-40.5, -10.0], [-4.0, 44.0], [138.0, 168.0], [174.0, 204.0], [210.0, 234.0]]
	_frame_mesh.mesh = _build_arc_mesh(segments, 505.0, 9.8, _frame_material)


func _build_amber() -> void:
	var segments := [[20.0, 44.0], [137.0, 160.0]]
	_amber_mesh.mesh = _build_arc_mesh(segments, 466.0, 1.6, _amber_material)


func _build_arc_mesh(segments: Array, radius: float, width: float, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var half := width * 0.5
	for segment in segments:
		var a0 := deg_to_rad(float(segment[0]))
		var a1 := deg_to_rad(float(segment[1]))
		var steps := maxi(8, int(absf(a1 - a0) * radius / 18.0))
		for i in steps:
			var t0 := a0 + (a1 - a0) * float(i) / float(steps)
			var t1 := a0 + (a1 - a0) * float(i + 1) / float(steps)
			var p0 := Vector2(cos(t0), sin(t0)) * radius
			var p1 := Vector2(cos(t1), sin(t1)) * radius
			var n0 := Vector2(-sin(t0), cos(t0)) * half
			var n1 := Vector2(-sin(t1), cos(t1)) * half
			mesh.surface_add_vertex(Vector3(p0.x + n0.x, p0.y + n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p0.x - n0.x, p0.y - n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x - n1.x, p1.y - n1.y, 0.0))
			mesh.surface_add_vertex(Vector3(p0.x + n0.x, p0.y + n0.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x - n1.x, p1.y - n1.y, 0.0))
			mesh.surface_add_vertex(Vector3(p1.x + n1.x, p1.y + n1.y, 0.0))
	mesh.surface_end()
	return mesh


func _build_bezel_gpu() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _bezel_material)
	# 四条细凹槽
	for radius in [470.0, 474.0, 478.0, 482.0]:
		for i in 96:
			var a0 := TAU * float(i) / 96.0
			var a1 := TAU * float(i + 1) / 96.0
			mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, 0.0))
			mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, 0.0))
	# 稀疏刻度：只保留 5 个方向的小三角，模仿菜单里的黄色旗标。
	for angle in [-101.0, -162.0, -37.0, 29.0, 141.0]:
		var a := deg_to_rad(angle)
		var p := Vector2(cos(a), sin(a)) * 455.0
		var outward := Vector2(cos(a), sin(a))
		var side := Vector2(-outward.y, outward.x) * 7.0
		mesh.surface_add_vertex(Vector3(p.x + side.x, p.y + side.y, 0.0))
		mesh.surface_add_vertex(Vector3((p + outward * 13.0).x, (p + outward * 13.0).y, 0.0))
		mesh.surface_add_vertex(Vector3((p + outward * 13.0).x, (p + outward * 13.0).y, 0.0))
		mesh.surface_add_vertex(Vector3(p.x - side.x, p.y - side.y, 0.0))
	mesh.surface_end()
	_bezel_mesh.mesh = mesh


func _build_ribbon(points: Array[Dictionary], width: float, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var half := width * 0.5
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		if bool(a.get("gap", false)) or bool(b.get("gap", false)):
			continue
		var pa: Vector2 = a.point
		var pb: Vector2 = b.point
		var delta := pb - pa
		if delta.length_squared() < 0.000001:
			continue
		var normal := Vector2(-delta.y, delta.x).normalized() * half
		var v0 := pa + normal
		var v1 := pa - normal
		var v2 := pb + normal
		var v3 := pb - normal
		mesh.surface_add_vertex(Vector3(v0.x, v0.y, 0.0))
		mesh.surface_add_vertex(Vector3(v1.x, v1.y, 0.0))
		mesh.surface_add_vertex(Vector3(v2.x, v2.y, 0.0))
		mesh.surface_add_vertex(Vector3(v1.x, v1.y, 0.0))
		mesh.surface_add_vertex(Vector3(v3.x, v3.y, 0.0))
		mesh.surface_add_vertex(Vector3(v2.x, v2.y, 0.0))
	mesh.surface_end()
	return mesh


func _update_background(chart: Chart) -> void:
	var path := String(chart.metadata.get("background", ""))
	if path == _last_background_path:
		return
	_last_background_path = path
	if path.is_empty():
		_background_image.visible = false
		return
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		if _app != null and not _app.chart_path.is_empty():
			resolved = ChartIO.resolve_path(_app.chart_path, path)
	var texture: Texture2D = null
	if resolved.begins_with("res://"):
		if ResourceLoader.exists(resolved):
			texture = load(resolved) as Texture2D
	else:
		var image := Image.load_from_file(ProjectSettings.globalize_path(resolved) if resolved.begins_with("user://") else resolved)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_background_image.texture = texture
	_background_image.visible = texture != null


func _update_video(chart: Chart, beat: float) -> void:
	var path := chart.video_path
	if path.is_empty():
		_video.visible = false
		return
	if path != _last_video_path:
		_last_video_path = path
		_video_load_failed = false
		var resolved := path
		if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
			if _app != null and not _app.chart_path.is_empty():
				resolved = ChartIO.resolve_path(_app.chart_path, path)
		var prepared := MediaIO.prepare_video(resolved)
		if prepared.is_empty():
			_video_load_failed = true
			_video.visible = false
			notice.emit("视频不可用：%s" % MediaIO.last_error, "warning")
			return
		var stream := ChartIO.video_stream_from_path(prepared)
		if stream == null:
			_video_load_failed = true
			_video.visible = false
			notice.emit("视频无法解码；保留路径，不影响编辑。", "warning")
			return
		_video.stream = stream
		_video.visible = true
		_video.play()
		_video.paused = true
	_video.modulate = Color(1, 1, 1, clampf(chart.video_opacity, 0.0, 1.0))
	var ms := chart.timing.beat_to_chart_ms(beat) - chart.offset_ms + chart.video_offset_ms
	var seconds := maxf(0.0, ms / 1000.0)
	if not playing:
		if not _video.is_playing():
			_video.play()
		_video.paused = true
		if absf(_video.stream_position - seconds) > 0.05:
			_video.stream_position = seconds
	elif _video.paused:
		_video.paused = false
		_video.stream_position = seconds
	elif absf(_video.stream_position - seconds) > 0.20:
		_video.stream_position = seconds


func _on_chart_changed() -> void:
	_sorted_notes_chart = null
	_trace_cache.clear()
	trace_cuts.clear()
	path_cuts.clear()
	path_cut_versions.clear()
	_path_runs_cache.clear()
	_boundary_frame_cache = null
	_path_local_cache.clear()
	_max_design_radius = -1.0
	_mesh_dirty = true
	_last_video_path = ""
	_last_background_path = ""
	_last_fit_key = ""
	_last_mesh_key = ""
	_force_3d_frame = true
	queue_redraw()


func _on_chart_live_changed() -> void:
	_sorted_notes_chart = null
	_trace_cache.clear()
	trace_cuts.clear()
	path_cuts.clear()
	path_cut_versions.clear()
	_path_runs_cache.clear()
	_boundary_frame_cache = null
	_path_local_cache.clear()
	# Note/region drags only change the overlay. Boundary dragging marks the
	# mesh dirty in _update_drag(), where the actual geometry is edited.
	if _mesh_dirty:
		_max_design_radius = -1.0
		_last_fit_key = ""
		_avg_radius_key = ""
		_force_3d_frame = true
	if _overlay != null:
		_overlay.queue_redraw()


func _on_selection_changed() -> void:
	queue_redraw()


func _on_playhead_changed(_beat: float) -> void:
	pass


func _on_tool_changed(_tool: String) -> void:
	queue_redraw()


func _on_resized() -> void:
	_last_fit_key = ""
	_render_mode = -1
	_force_3d_frame = true
	if _subviewport != null:
		_subviewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	var chart := get_chart()
	if chart != null:
		var view := current_view()
		_update_camera_fit(chart, float(view.get("zoom", 1.0)), float(view.get("ellipse", 1.0)))


func _on_mouse_entered() -> void:
	mouse_inside = true
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_update_cursor()
	_overlay.queue_redraw()


func _on_mouse_exited() -> void:
	mouse_inside = false
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_overlay.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_screen = event.position
		if interactive and not playtest_mode:
			if _drag_segment >= 0:
				_update_drag(event.position)
			elif _drag_visual >= 0:
				_update_visual_drag(event.position)
			elif _drawing_red:
				_update_cursor()
				_update_red_drag(event.position)
			elif _drawing_path:
				_append_path_point(event.position)
			elif _drawing_trace:
				_append_trace_point(event.position)
		_update_cursor()
		_overlay.queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_screen = event.position
		if event.pressed:
			_on_left_press(event)
		else:
			_on_left_release(event)
		accept_event()


func _on_left_press(event: InputEventMouseButton) -> void:
	_update_cursor()
	if not interactive or playtest_mode:
		return
	if _app == null:
		return
	if _app.trace_draw_mode:
		_drawing_trace = true
		_trace_points.clear()
		_trace_points.append(event.position)
		return
	if _app.boundary_mode:
		if event.double_click:
			_split_segment()
			return
		var control := _pick_control_point(event.position)
		if not control.is_empty():
			var active_shape := _active_shape()
			_drag_segment = int(control["segment_index"])
			_drag_endpoint = int(control["endpoint"])
			_drag_shape_backup = active_shape.to_dict() if active_shape != null else {}
			_app.begin_edit()
			return
		var segment_index := _nearest_segment_index(event.position)
		if segment_index >= 0:
			_app.select_segment(segment_index)
			return
	if _app.tool == "red":
		if not cursor_valid:
			return
		var chart := get_chart()
		if chart == null:
			return
		var start_beat: float = _app.snap_beat(get_time_beat())
		var region := Region.new(chart.next_region_id(), start_beat, start_beat + 1.0)
		region.angle = cursor_u * 360.0
		region.width = 30.0
		_app.begin_edit()
		chart.regions.append(region)
		_app.select_region(region.id)
		_red_region = region
		_red_start_u = cursor_u
		_red_start_beat = start_beat
		_red_start_mouse = event.position
		_drawing_red = true
		return
	if _app.tool == "select":
		var visual := _pick_visual_node(event.position)
		if visual >= 0:
			_drag_visual = visual
			_drag_visual_note = _app.get_selected_note()
			_drag_visual_start = event.position
			if _drag_visual_note.type == "path":
				var trace_count: int = _drag_visual_note.trace_pts.size()
				if visual < trace_count:
					var point: Dictionary = _drag_visual_note.trace_pts[visual]
					_drag_visual_db = float(point.get("db", 0.0))
				else:
					var design: Dictionary = _drag_visual_note.visual_pts[visual - trace_count]
					_drag_visual_db = float(design.get("db", 0.0))
					_drag_visual_da = float(design.get("da", 0.0))
			else:
				var point: Dictionary = _drag_visual_note.visual_pts[visual]
				_drag_visual_db = float(point.get("db", 0.0))
				_drag_visual_da = float(point.get("da", 0.0))
			_app.begin_edit()
			return
	if _app.tool == "path":
		if cursor_valid:
			_drawing_path = true
			_path_head_angle = fposmod(cursor_u * 360.0, 360.0)
			_path_points.clear()
			_path_points.append(Vector2(cos(deg_to_rad(_path_head_angle)), sin(deg_to_rad(_path_head_angle))))
		return
	if _app.tool in ["tap", "tap_sized", "hold", "path", "anchor", "bell"]:
		if cursor_valid:
			_create_note(_app.tool)
		return
	if _app.tool == "select":
		var note_id := _pick_note(event.position)
		if note_id >= 0:
			_app.select_note(note_id)


func _on_left_release(_event: InputEventMouseButton) -> void:
	if _drag_visual >= 0:
		_drag_visual = -1
		_drag_visual_note = null
		if _app != null:
			_app.finish_edit()
	if _drag_segment >= 0:
		_drag_segment = -1
		_drag_endpoint = -1
		var shape := _active_shape()
		if shape != null and not _drag_shape_backup.is_empty():
			if not shape.validate().is_empty():
				var restored := BoundaryShape.from_dict(_drag_shape_backup)
				shape.segments = restored.segments
				shape.closed = restored.closed
				_mesh_dirty = true
				notice.emit("该轮廓会自交、非凸或变形过激，已回退。", "warning")
		_drag_shape_backup = {}
		if _app != null:
			_app.finish_edit()
	if _drawing_red:
		_drawing_red = false
		_red_region = null
		if _app != null:
			_app.finish_edit()
	if _drawing_trace:
		_drawing_trace = false
		_create_trace()
	if _drawing_path:
		_drawing_path = false
		_create_path()


func _update_drag(screen_position: Vector2) -> void:
	if _app == null or _drag_segment < 0:
		return
	var shape := _active_shape()
	if shape == null:
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	var sorted := shape.sorted_segments()
	if _drag_segment >= sorted.size():
		return
	var segment := sorted[_drag_segment]
	if _drag_endpoint == 0:
		segment.p0 = design
		if _drag_segment > 0:
			sorted[_drag_segment - 1].p1 = design
		elif shape.closed:
			sorted[-1].p1 = design
	else:
		segment.p1 = design
		if _drag_segment < sorted.size() - 1:
			sorted[_drag_segment + 1].p0 = design
		elif shape.closed:
			sorted[0].p0 = design
	_app.touch_chart()
	_mesh_dirty = true


func _update_visual_drag(screen_position: Vector2) -> void:
	if _drag_visual_note == null or _drag_visual < 0:
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	if _drag_visual_note.type == "path":
		var trace_count: int = _drag_visual_note.trace_pts.size()
		if _drag_visual >= trace_count:
			var design_index := _drag_visual - trace_count
			if design_index >= _drag_visual_note.visual_pts.size():
				return
			var marker: Dictionary = _drag_visual_note.visual_pts[design_index]
			var duration := _drag_visual_note.duration()
			marker["db"] = clampf(_drag_visual_db + (screen_position.y - _drag_visual_start.y) / 36.0, 0.001, maxf(0.001, duration - 0.001))
			marker["da"] = JudgeMath.angle_delta(_drag_visual_note.angle, rad_to_deg(atan2(design.y, design.x)))
			_app.touch_chart()
			return
		if _drag_visual >= _drag_visual_note.trace_pts.size():
			return
		var local := _design_to_path_local(design)
		var point: Dictionary = _drag_visual_note.trace_pts[_drag_visual]
		point["x"] = local.x
		point["y"] = local.y
		if _drag_visual == 0:
			_drag_visual_note.angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		elif _drag_visual == _drag_visual_note.trace_pts.size() - 1:
			_drag_visual_note.tail_angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		_app.touch_chart()
		return
	if _drag_visual >= _drag_visual_note.visual_pts.size():
		return
	var point: Dictionary = _drag_visual_note.visual_pts[_drag_visual]
	var duration := _drag_visual_note.duration()
	point["db"] = clampf(_drag_visual_db + (screen_position.y - _drag_visual_start.y) / 36.0, 0.001, maxf(0.001, duration - 0.001))
	var angle := rad_to_deg(atan2(design.y, design.x))
	point["da"] = JudgeMath.angle_delta(_drag_visual_note.angle, angle)
	_app.touch_chart()


func _design_to_path_local(design: Vector2) -> Vector2:
	var chart := get_chart()
	if chart == null or design.length() <= 0.001:
		return Vector2(0.7, 0.0)
	var angle := fposmod(rad_to_deg(atan2(design.y, design.x)), 360.0)
	var data := _boundary_point(chart, angle / 360.0, get_time_beat())
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	var ring_radius := maxf(0.001, (data.point as Vector2).length())
	return design / ring_radius


func _update_red_drag(screen_position: Vector2) -> void:
	if _red_region == null:
		return
	var delta := (cursor_u - _red_start_u) * 360.0
	if absf(delta) < 8.0:
		delta = 30.0 if delta >= 0.0 else -30.0
	_red_region.angle = fposmod(_red_start_u * 360.0 + delta * 0.5, 360.0)
	_red_region.width = clampf(absf(delta), 10.0, 359.0)
	var beat := _red_start_beat + (screen_position.y - _red_start_mouse.y) / 40.0
	_red_region.start_beat = minf(_red_start_beat, beat)
	_red_region.end_beat = maxf(_red_start_beat + 0.25, minf(beat, _red_start_beat + 4.0))
	_app.touch_chart()


func _append_trace_point(point: Vector2) -> void:
	var clamped := plane_clamp_screen(point)
	if _trace_points.is_empty() or _trace_points[-1].distance_to(clamped) > 4.0:
		_trace_points.append(clamped)
		_overlay.queue_redraw()


func _create_trace() -> void:
	if _app == null or _trace_points.size() < 2:
		_trace_points.clear()
		return
	var chart := get_chart()
	if chart == null:
		_trace_points.clear()
		return
	var start: float = _app.snap_beat(get_time_beat())
	var end: float = start + 1.0
	var note := Note.new("trace", start, 0.0, 0.0)
	note.id = chart.next_note_id()
	note.end_beat = end
	note.move_px = 120.0
	for i in _trace_points.size():
		var point := _trace_points[i]
		note.trace_pts.append({
			"x": clampf(point.x / maxf(1.0, size.x), 0.0, 1.0),
			"y": clampf(point.y / maxf(1.0, size.y), 0.0, 1.0),
			"db": 1.0 * float(i) / float(_trace_points.size() - 1),
		})
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)
	_trace_points.clear()


func _append_path_point(screen: Vector2) -> void:
	var design := _screen_to_ring_plane(screen)
	if not design.is_finite():
		return
	var local := _design_to_path_local(design)
	if not local.is_finite():
		return
	var radius := local.length()
	if radius <= 0.001:
		return
	radius = clampf(radius, 0.06, 0.985)
	local = local.normalized() * radius
	if _path_points.is_empty() or _path_points[-1].distance_to(local) > 0.012:
		_path_points.append(local)


func _create_path() -> void:
	if _app == null:
		_path_points.clear()
		return
	var chart := get_chart()
	if chart == null or _path_points.is_empty():
		_path_points.clear()
		return
	if _path_points.size() < 2:
		var angle := deg_to_rad(_path_head_angle + 60.0)
		_path_points.append(Vector2(cos(angle), sin(angle)) * 0.70)
	var start: float = _app.snap_beat(get_time_beat())
	var note := Note.new("path", start, _path_head_angle, 62.0)
	note.id = chart.next_note_id()
	note.end_beat = start + 1.0
	note.tail_width = 45.0
	note.tolerance = 0.24
	note.samples_per_beat = 4.0
	note.space = "plane"
	var last: Vector2 = _path_points[-1]
	note.tail_angle = fposmod(rad_to_deg(atan2(last.y, last.x)), 360.0)
	for i in _path_points.size():
		var point := _path_points[i]
		note.trace_pts.append({
			"x": point.x,
			"y": point.y,
			"db": note.duration() * float(i) / float(_path_points.size() - 1),
		})
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)
	_path_points.clear()


func _create_note(type: String) -> void:
	if _app == null or not cursor_valid:
		return
	var chart := get_chart()
	if chart == null:
		return
	var beat: float = _app.snap_beat(get_time_beat())
	var angle := fposmod(cursor_u * 360.0, 360.0)
	var kind := "tap" if type == "tap_sized" else type
	var note := Note.new(kind, beat, angle, 60.0)
	note.id = chart.next_note_id()
	match type:
		"tap_sized":
			note.set_size_ratio(1.0)
		"hold":
			note.end_beat = beat + 1.0
			note.hold = true
			note.hold_style = "straight"
		"path":
			note.end_beat = beat + 1.0
			note.tail_angle = fposmod(angle + 60.0, 360.0)
			note.tail_width = 45.0
			note.tolerance = 0.24
			note.samples_per_beat = 4.0
			note.trace_pts = [
				{"x": cos(deg_to_rad(angle)), "y": sin(deg_to_rad(angle)), "db": 0.0},
				{"x": cos(deg_to_rad(note.tail_angle)) * 0.70, "y": sin(deg_to_rad(note.tail_angle)) * 0.70, "db": 1.0},
			]
		"anchor":
			note.width = 0.0
			note.anchor_pair = -1
		"bell":
			note.width = 0.0
			note.center_u = cursor_u
			note.radius = 26.0
	_app.begin_edit()
	chart.notes.append(note)
	_app.finish_edit()
	_app.select_note(note.id)


func _pick_control_point(screen: Vector2) -> Dictionary:
	var shape := _active_shape()
	if shape == null:
		return {}
	var sorted := shape.sorted_segments()
	var best := {}
	var best_distance := 14.0
	for index in sorted.size():
		var segment := sorted[index]
		for endpoint in 2:
			var point: Vector2 = segment.p0 if endpoint == 0 else segment.p1
			var projected := project_design(point)
			var distance := projected.distance_to(screen)
			if distance < best_distance:
				best_distance = distance
				best = {"segment_index": index, "endpoint": endpoint}
	return best


func _nearest_segment_index(screen: Vector2) -> int:
	var shape := _active_shape()
	if shape == null:
		return -1
	var chart := get_chart()
	if chart == null:
		return -1
	var result := BoundaryRuntime.nearest_u(chart, get_time_beat(), screen, func(point: Vector2) -> Vector2: return project_design(point), 512)
	if float(result["distance"]) > 28.0:
		return -1
	var u := float(result["u"])
	var segment := shape.segment_at(u)
	if segment == null:
		return -1
	var sorted := shape.sorted_segments()
	return sorted.find(segment)


func _pick_note(screen: Vector2) -> int:
	var chart := get_chart()
	if chart == null:
		return -1
	var t := get_time_beat()
	var pre := _pre_read_beats(chart, t)
	var best := -1
	var best_distance := 20.0
	for note in chart.notes:
		match note.type:
			"trace":
				continue
			"path":
				var head := _flying_position(chart, note.angle, note.beat, t, pre)
				var tail := _flying_position(chart, note.tail_angle, note.end_beat, t, pre)
				if head.distance_to(screen) < best_distance:
					best_distance = head.distance_to(screen)
					best = note.id
				if tail.distance_to(screen) < best_distance:
					best_distance = tail.distance_to(screen)
					best = note.id
			_:
				var u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
				var target := _flying_position(chart, u * 360.0, note.beat, t, pre)
				var boundary := project_u(u, t)
				var distance := minf(target.distance_to(screen), boundary.distance_to(screen))
				if distance < best_distance:
					best_distance = distance
					best = note.id
	return best


func _active_shape() -> BoundaryShape:
	var chart := get_chart()
	if chart == null:
		return null
	if follow_app and _app != null:
		var selected: BoundaryShape = _app.get_selected_shape()
		if selected != null:
			return selected
	return chart.get_default_shape()


func _split_segment() -> void:
	if _app == null:
		return
	var shape := _active_shape()
	if shape == null or not cursor_valid:
		return
	var u := cursor_u
	var segment := shape.segment_at(u)
	if segment == null:
		return
	var t := segment.local_t(u)
	if t <= 0.02 or t >= 0.98:
		return
	var point := segment.point_at(t)
	var first := BoundarySegment.new(segment.u0, u, segment.p0, point, segment.ix, segment.iy, segment.gap)
	var second := BoundarySegment.new(u, segment.u1, point, segment.p1, segment.ix, segment.iy, segment.gap)
	_app.begin_edit()
	var backup := shape.segments.duplicate()
	var index := shape.segments.find(segment)
	shape.segments.remove_at(index)
	shape.segments.append(first)
	shape.segments.append(second)
	shape.segments.sort_custom(func(a: BoundarySegment, b: BoundarySegment) -> bool: return a.u0 < b.u0)
	if not shape.validate().is_empty():
		shape.segments = backup
		_mesh_dirty = true
		notice.emit("拆分会产生自交、非凸或变形过激，已取消。", "warning")
		_app.finish_edit()
		return
	_app.finish_edit()
	var sorted := shape.sorted_segments()
	_app.select_segment(sorted.find(first))
	_mesh_dirty = true


func _pre_read_beats(chart: Chart, beat: float) -> float:
	return chart.pre_read_ms / maxf(0.1, flow_scale) / 60000.0 * chart.timing.bpm_at(beat)


func _flying_position(chart: Chart, angle: float, target_beat: float, current_beat: float, pre: float) -> Vector2:
	var u := fposmod(angle, 360.0) / 360.0
	var boundary := project_u(u, current_beat)
	var center := project_design(Vector2.ZERO)
	var q := clampf((current_beat - (target_beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
	return center.lerp(boundary, q)


func _update_cursor_trail(delta: float) -> void:
	for i in range(_cursor_trail.size() - 1, -1, -1):
		var age := float(_cursor_trail[i].get("age", 0.0)) + delta
		_cursor_trail[i]["age"] = age
		if age > 0.26:
			_cursor_trail.remove_at(i)
	if not mouse_inside:
		_cursor_trail.clear()
		return
	if _last_mouse_screen.distance_to(mouse_screen) <= 1.0:
		return
	_cursor_trail.append({"pos": mouse_screen, "age": 0.0})
	if _cursor_trail.size() > 28:
		_cursor_trail.pop_front()


func _update_cursor() -> void:
	var chart := get_chart()
	if chart == null:
		return
	var t := get_time_beat()
	# 鼠标和边界几何都没变时，直接复用上一帧的 u，避免每帧 96 次反解。
	var cache_key := "%s|%.1f|%.1f|%s" % [_mesh_key(chart, t), mouse_screen.x, mouse_screen.y, _last_view_key]
	if cache_key == _cursor_cache_key:
		return
	_cursor_cache_key = cache_key
	var result := BoundaryRuntime.nearest_u(chart, t, mouse_screen, func(point: Vector2) -> Vector2: return project_design(point), 96, _frame_for(chart, t))
	var u := float(result["u"])
	var distance := float(result["distance"])
	var center := project_design(Vector2.ZERO)
	var average_key := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, t), _last_view_key, size.x, size.y]
	if average_key != _avg_radius_key:
		_avg_radius_key = average_key
		var total := 0.0
		var counted := 0
		var samples := 12
		for i in samples:
			var sample_point := project_u(float(i) / float(samples), t)
			if _valid_point(sample_point):
				total += sample_point.distance_to(center)
				counted += 1
		_avg_radius_cache = total / float(maxi(1, counted)) if counted > 0 else 100.0
	var average := _avg_radius_cache
	var threshold := maxf(20.0, average * 0.20)
	var near_center := mouse_screen.distance_to(center) < average * 0.12
	var valid := distance <= threshold and not near_center
	if playtest_mode:
		# Estella 式外环：内圈外整片有效，鼠标离开环/舞台后仍按最近 u 判定。
		valid = mouse_screen.distance_to(center) >= average * 0.45
	elif not mouse_inside:
		valid = false
	cursor_u = u
	cursor_valid = valid
	if _last_cursor_emit.distance_to(Vector2(u, 1.0 if valid else 0.0)) > 0.0001:
		_last_cursor_emit = Vector2(u, 1.0 if valid else 0.0)
		cursor_changed.emit(u, valid)


func _screen_to_ring_plane(screen: Vector2) -> Vector2:
	if _camera == null or _ring_root == null:
		return Vector2(INF, INF)
	var normal := (_ring_root.transform.basis * Vector3(0, 0, 1)).normalized()
	var plane := Plane(normal, -normal.dot(_ring_root.transform.origin))
	var hit: Variant = plane.intersects_ray(_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))
	if hit == null:
		return Vector2(INF, INF)
	var hit_point: Vector3 = hit
	var local: Vector3 = _ring_root.transform.affine_inverse() * hit_point
	return Vector2(local.x, local.y)


func project_design(point: Vector2) -> Vector2:
	if _camera == null or _ring_root == null:
		return Vector2.ZERO
	var world: Vector3 = _ring_root.transform * Vector3(point.x, point.y, 0.0)
	return _camera.unproject_position(world)


func _frame_for(chart: Chart, beat: float) -> BoundaryFrame:
	if _boundary_frame_cache == null or _boundary_frame_cache.chart != chart or _boundary_frame_cache.beat != beat:
		if _boundary_frame_cache != null and _boundary_frame_cache.chart != chart:
			_max_design_radius = -1.0
			_path_local_cache.clear()
		_boundary_frame_cache = BoundaryFrame.new(chart, beat, _boundary_frame_cache)
	return _boundary_frame_cache


func _boundary_point(chart: Chart, u: float, beat: float) -> Dictionary:
	return _frame_for(chart, beat).point_at(u)


func project_u(u: float, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	var data := _boundary_point(chart, u, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design(data.point)


func plane_stage_radius() -> float:
	var center := project_design(Vector2.ZERO)
	var x_point := project_design(Vector2(505.0, 0.0))
	var y_point := project_design(Vector2(0.0, 505.0))
	if not _valid_point(center) or not _valid_point(x_point) or not _valid_point(y_point):
		return minf(size.x, size.y) * 0.35
	return maxf(40.0, minf(center.distance_to(x_point), center.distance_to(y_point)))


func plane_clamp_screen(point: Vector2) -> Vector2:
	var center := project_design(Vector2.ZERO)
	var radius := plane_stage_radius()
	return Vector2(
		clampf(point.x, center.x - 0.66 * radius, center.x + 0.66 * radius),
		clampf(point.y, center.y - 0.495 * radius, center.y + 0.495 * radius)
	)


func trace_screen_points(note: Note, beat: float = 0.0, scale: float = 1.0) -> PackedVector2Array:
	var chart := get_chart()
	var grow := clampf(scale, 0.0, 1.0)
	var center := project_design(Vector2.ZERO)
	var mesh := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, beat) if chart != null else "", _last_view_key, size.x, size.y]
	if mesh != _trace_cache_mesh:
		_trace_cache_mesh = mesh
		_trace_cache.clear()
		_path_runs_cache.clear()
	_path_runs_cache.clear()
	var cache_key := "%d|%s" % [note.id, mesh]
	if grow >= 0.999 and _trace_cache.has(cache_key):
		return _trace_cache[cache_key]
	var points := PackedVector2Array()
	for point in note.trace_pts:
		var x := float(point.get("x", 0.0))
		var y := float(point.get("y", 0.0))
		if note.trace_style == "slider" and chart != null:
			var radius := minf(1.0, sqrt(x * x + y * y))
			var angle := fposmod(rad_to_deg(atan2(y, x)), 360.0)
			var data := _boundary_point(chart, angle / 360.0, beat)
			if bool(data.get("gap", false)):
				continue
			points.append(project_design((data.point as Vector2) * radius * grow))
		else:
			points.append(center.lerp(Vector2(x * size.x, y * size.y), grow))
	if grow >= 0.999:
		_trace_cache[cache_key] = points
	return points


func draw_overlay(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var t := get_time_beat()
	var pre := _pre_read_beats(chart, t)
	if not use_3d_ring:
		_draw_flat_stage(canvas, chart, t)
		_draw_flat_ring(canvas, chart, t)
	if not use_3d_ring:
		_draw_bezel(canvas, chart, t)
	_draw_red_regions(canvas, chart, t)
	# 图层顺序：滑条底带 → Path → Hold → Tap/Anchor/Bell，命中目标始终在上层。
	_draw_traces(canvas, chart, t)
	_draw_paths(canvas, chart, t, pre)
	_draw_holds(canvas, chart, t, pre)
	_draw_notes(canvas, chart, t, pre)
	_draw_boundary_controls(canvas, chart)
	_draw_cursor(canvas, chart, t)
	if show_hud:
		_draw_hud(canvas, chart, t)
	_draw_arc_flashes(canvas)
	_draw_pulses(canvas)
	if show_debug:
		_draw_debug(canvas, chart, t)


func _screen_affine() -> Array:
	var center := project_design(Vector2.ZERO)
	var x_axis := project_design(Vector2(100, 0)) - center
	var y_axis := project_design(Vector2(0, 100)) - center
	return [center, x_axis / 100.0, y_axis / 100.0]


func _affine_point(point: Vector2, affine: Array) -> Vector2:
	var center: Vector2 = affine[0]
	var x_axis: Vector2 = affine[1]
	var y_axis: Vector2 = affine[2]
	return center + x_axis * point.x + y_axis * point.y


func _draw_flat_stage(canvas: Control, chart: Chart, t: float) -> void:
	var affine := _screen_affine()
	for radius in [360.0, 420.0, 620.0]:
		var points := PackedVector2Array()
		for i in 97:
			var a := TAU * float(i) / 96.0
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(0.56, 0.62, 0.72, 0.08), 1.0, true)
	for angle in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(angle)
		for offset in [-2.0, 2.0]:
			var normal: Vector2 = Vector2(-sin(a), cos(a)) * offset
			var p0 := _affine_point(Vector2(cos(a), sin(a)) * 520.0 + normal, affine)
			var p1 := _affine_point(Vector2(cos(a), sin(a)) * 590.0 + normal, affine)
			canvas.draw_line(p0, p1, Color(0.56, 0.62, 0.72, 0.10), 1.0, true)


func _draw_flat_ring(canvas: Control, chart: Chart, t: float) -> void:
	var points := _frame_for(chart, t).sample_points(192)
	var run := PackedVector2Array()
	for item in points:
		if bool(item.get("gap", false)):
			if run.size() > 1:
				canvas.draw_polyline(run, Color(0.37, 0.85, 0.81, 0.10), 18.0, true)
				canvas.draw_polyline(run, Color(0.55, 0.60, 0.70, 0.95), 4.0, true)
				canvas.draw_polyline(run, Color(1, 1, 1, 0.18), 1.0, true)
			run = PackedVector2Array()
			continue
		var p := project_design(item.point)
		if _valid_point(p):
			run.append(p)
	if run.size() > 1:
		canvas.draw_polyline(run, Color(0.37, 0.85, 0.81, 0.10), 18.0, true)
		canvas.draw_polyline(run, Color(0.55, 0.60, 0.70, 0.95), 4.0, true)
		canvas.draw_polyline(run, Color(1, 1, 1, 0.18), 1.0, true)


func _draw_bezel(canvas: Control, chart: Chart, t: float) -> void:
	var affine := _screen_affine()
	var center: Vector2 = affine[0]
	if not _valid_point(center):
		return
	for radius in [470.0, 474.0, 478.0, 482.0]:
		var points := PackedVector2Array()
		for i in 97:
			var angle := TAU * float(i) / 96.0
			points.append(_affine_point(Vector2(cos(angle), sin(angle)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(1, 1, 1, 0.09), 1.0, true)
	_draw_affine_arcs(canvas, affine, [[20.0, 44.0], [137.0, 160.0]], 466.0, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.82), 1.8)
	_draw_affine_arcs(canvas, affine, [[-40.5, -10.0], [-4.0, 44.0], [138.0, 168.0], [174.0, 204.0], [210.0, 234.0]], 505.0, Color(1, 1, 1, 0.92), 9.8)
	for angle in [-101.0, -162.0, -37.0, 29.0, 141.0]:
		var a := deg_to_rad(angle)
		var p := _affine_point(Vector2(cos(a), sin(a)) * 462.0, affine)
		var outward := (_affine_point(Vector2(cos(a), sin(a)) * 470.0, affine) - p).normalized()
		var side := Vector2(-outward.y, outward.x) * 6.0
		canvas.draw_colored_polygon(PackedVector2Array([p + side, p - side, p + outward * 12.0]), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.8))


func _draw_affine_arcs(canvas: Control, affine: Array, segments: Array, radius: float, color: Color, width: float) -> void:
	for segment in segments:
		var points := PackedVector2Array()
		var a0 := deg_to_rad(float(segment[0]))
		var a1 := deg_to_rad(float(segment[1]))
		var steps := maxi(8, int(absf(a1 - a0) * 18.0))
		for i in steps + 1:
			var a := a0 + (a1 - a0) * float(i) / float(steps)
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, color, width, true)


func _draw_red_regions(canvas: Control, chart: Chart, t: float) -> void:
	var pre := _pre_read_beats(chart, t)
	for region in chart.regions:
		var active := region.active_at(t)
		var incoming := t >= region.start_beat - pre and t < region.start_beat
		if not active and not incoming:
			continue
		var outer := _arc_points_scaled(region.angle, region.width, t, 40, 1.0)
		var inner := _arc_points_scaled(region.angle, region.width, t, 40, 0.68)
		if outer.size() < 2 or inner.size() < 2:
			continue
		var fill_alpha := (0.52 + 0.06 * sin(t * PI * 2.0)) if active else 0.12
		var polygon := PackedVector2Array()
		for point in outer:
			polygon.append(point)
		for i in range(inner.size() - 1, -1, -1):
			polygon.append(inner[i])
		canvas.draw_colored_polygon(polygon, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, fill_alpha))
		canvas.draw_polyline(outer, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.25 if active else 0.06), 18.0, true)
		canvas.draw_polyline(outer, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.98 if active else 0.35), 3.0, true)
		canvas.draw_polyline(inner, Color(UITheme.RED.r, UITheme.RED.g, UITheme.RED.b, 0.75 if active else 0.18), 1.5, true)
		for i in 5:
			var slice := float(i) / 4.0
			var a := region.angle - region.width * 0.5 + region.width * slice
			var p0 := _arc_point_scaled(a, t, 0.78)
			var p1 := _arc_point_scaled(a, t, 0.97)
			if _valid_point(p0) and _valid_point(p1):
				canvas.draw_line(p0, p1, Color(1.0, 0.42, 0.34, 0.26 if active else 0.05), 1.0, true)
		var label_point := _arc_point_scaled(region.angle, t, 0.86)
		if _valid_point(label_point):
			_draw_badge(canvas, "RED" if active else "RED IN", label_point + Vector2(0, -4), UITheme.RED)


func _arc_points_scaled(angle: float, width: float, beat: float, steps: int, scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_width := clampf(width, 0.1, 360.0)
	var count := maxi(steps, 4)
	for i in count + 1:
		var a := angle - safe_width * 0.5 + safe_width * float(i) / float(count)
		var p := _arc_point_scaled(a, beat, scale)
		if _valid_point(p):
			points.append(p)
	return points


func _arc_point_scaled(angle: float, beat: float, scale: float) -> Vector2:
	var data := _boundary_point(get_chart(), fposmod(angle, 360.0) / 360.0, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * scale)


func _pick_visual_node(screen_position: Vector2) -> int:
	if _app == null:
		return -1
	var note: Note = _app.get_selected_note()
	if note == null or note.type not in ["path", "hold"]:
		return -1
	var chart := get_chart()
	if chart == null:
		return -1
	var t := get_time_beat()
	if note.type == "hold":
		for i in note.visual_pts.size():
			var point: Dictionary = note.visual_pts[i]
			var p := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
			if _valid_point(p) and p.distance_to(screen_position) <= 12.0:
				return i
		return -1
	for i in note.trace_pts.size():
		var point: Dictionary = note.trace_pts[i]
		var local := Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0)))
		var p := _path_local_screen(chart, local, t)
		if _valid_point(p) and p.distance_to(screen_position) <= 12.0:
			return i
	# 中间设计判定点用轨迹时间定位，单独编号排在平面点之后。
	for i in note.visual_pts.size():
		var point: Dictionary = note.visual_pts[i]
		var p := _path_screen_point(chart, note, float(point.get("db", 0.0)), t)
		if _valid_point(p) and p.distance_to(screen_position) <= 10.0:
			return note.trace_pts.size() + i
	return -1


func _draw_paths(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var visible: Array = []
	for note in _notes_in_range(chart, t - pre - 128.0, t + pre + 0.5):
		if note.type == "path" and t >= note.beat - pre and t <= note.end_beat + 0.5:
			visible.append(note)
	# 旧 Path 先画、新的最后画：多星星重叠时，新星和它的擦除缺口始终在最上层。
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	for i in visible.size():
		_draw_one_path(canvas, chart, visible[i], t, pre, i == visible.size() - 1, visible.size())
	if _drawing_path and _path_points.size() > 1:
		var preview := PackedVector2Array()
		for local in _path_points:
			var p := _path_local_screen(chart, local, t)
			if _valid_point(p):
				preview.append(p)
		if preview.size() > 1:
			canvas.draw_polyline(preview, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.75), 3.0, true)
			for p in preview:
				canvas.draw_circle(p, 2.5, UITheme.CYAN)


func path_screen_runs(note: Note, t: float, grow: float = 1.0) -> Array[PackedVector2Array]:
	var chart := get_chart()
	if chart == null:
		return []
	var total := note.duration()
	if total <= 0.001:
		return []
	var count := clampi(int(total * 18.0), 40, 96)
	var points := PackedVector2Array()
	var erased_flags: Array[bool] = []
	for i in count + 1:
		var rel := total * float(i) / float(count)
		erased_flags.append(path_erased(note, rel))
		points.append(_path_screen_point(chart, note, rel, t, false, 1.0))
	var runs := split_path_runs(points, erased_flags)
	if grow < 0.999:
		var center := project_design(Vector2.ZERO)
		var scaled_runs: Array[PackedVector2Array] = []
		for piece in runs:
			var scaled := PackedVector2Array()
			for p in piece:
				scaled.append(center.lerp(p, grow))
			scaled_runs.append(scaled)
		runs = scaled_runs
	return runs


static func split_path_runs(points: PackedVector2Array, erased: Array) -> Array[PackedVector2Array]:
	# 只在真正擦除/无效点处分段；不再用像素距离阈值，避免长轨迹被误切。
	var result: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in points.size():
		var point := points[i]
		var hidden := i < erased.size() and bool(erased[i])
		if hidden or not is_finite(point.x) or not is_finite(point.y) or point.x > 1.0e9 or point.y > 1.0e9:
			if run.size() > 1:
				result.append(run)
			run = PackedVector2Array()
			continue
		run.append(point)
	if run.size() > 1:
		result.append(run)
	return result


func _draw_one_path(canvas: Control, chart: Chart, note: Note, t: float, pre: float, top: bool, visible_count: int = 1) -> void:
	var total := note.duration()
	if total <= 0.001:
		return
	var grow := clampf((t - (note.beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
	var ns := _note_scale()
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
	var q := clampf((t - note.beat - wait) / maxf(0.001, total - wait), 0.0, 1.0)
	var progress := 1.0 - pow(1.0 - q, maxf(0.05, note.path_speed))
	var runs: Array[PackedVector2Array] = []
	var mesh := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, t), _last_view_key, size.x, size.y]
	var cache_key := "%d|%d|%s" % [note.id, int(path_cut_versions.get(note.id, 0)), mesh]
	if _path_runs_cache.has(cache_key):
		runs = _path_runs_cache[cache_key]
	else:
		var count := clampi(int(total * 18.0), 40, 96)
		if visible_count >= 4:
			count = clampi(int(total * 12.0), 28, 64)
		var points := PackedVector2Array()
		var erased_flags: Array[bool] = []
		for i in count + 1:
			var rel := total * float(i) / float(count)
			erased_flags.append(path_erased(note, rel))
			points.append(_path_screen_point(chart, note, rel, t, true, 1.0))
		runs = split_path_runs(points, erased_flags)
		if _path_runs_cache.size() > 64:
			_path_runs_cache.clear()
		_path_runs_cache[cache_key] = runs
	if grow < 0.999:
		# 缓存的是完整轨迹；飞入阶段只缩放副本，不能改缓存。
		var center := project_design(Vector2.ZERO)
		var scaled_runs: Array[PackedVector2Array] = []
		for piece in runs:
			var scaled := PackedVector2Array()
			for p in piece:
				scaled.append(center.lerp(p, grow))
			scaled_runs.append(scaled)
		runs = scaled_runs
	var dash := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.92 if top else 0.34)
	var future := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.98 if top else 0.38)
	var passed := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.26 if top else 0.12)
	for piece in runs:
		if piece.size() < 2:
			continue
		var path_band := float(_skin()["band"])
		if not top:
			# 下层 Path 只留一条低亮度线；星头/尾/进度球只画最上层的一条。
			canvas.draw_polyline(piece, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.48), 3.2 * PATH_SIZE_SCALE * ns * path_band, true)
			continue
		# 舞萌式滑动：单条高亮线 + 密集 V 形箭头；把多层描边合并，减少 10k 谱面的 draw call。
		canvas.draw_polyline(piece, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.95), 5.0 * PATH_SIZE_SCALE * ns * path_band, true)
		_draw_dashed_polyline(canvas, piece, dash, 2.4 * PATH_SIZE_SCALE, 10.0 * PATH_SIZE_SCALE)
		# V 形箭头列：按轨迹长度铺满，像舞萌的滑动箭头链。
		var piece_length := 0.0
		for i in piece.size() - 1:
			piece_length += piece[i].distance_to(piece[i + 1])
		var chevron_cap := 24 if visible_count < 4 else (16 if visible_count < 8 else 10)
		var chevron_count := clampi(int(piece_length / maxf(12.0, 20.0 * ns)), 3, chevron_cap)
		for k in chevron_count:
			var fraction := (float(k) + 0.5) / float(chevron_count)
			var sample: Dictionary = _polyline_sample(piece, fraction)
			_draw_chevron(canvas, sample["point"], sample["direction"], passed if fraction < progress else future, 16.0 * ns * PATH_SIZE_SCALE)
	var selected_note: Note = _app.get_selected_note() if _app != null else null
	var selected := selected_note != null and selected_note.id == note.id
	if selected:
		# 中间判定点只在选中时绘制，避免多星星铺满采样点拖慢编辑器。
		for sample_beat in note.path_sample_beats():
			var rel := clampf(sample_beat - note.beat, 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, grow)
			if _valid_point(p):
				canvas.draw_circle(p, 2.6 * ns, Color(0, 0, 0, 0.5))
				canvas.draw_circle(p, 1.8 * ns, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.85 if top else 0.28))
		# 手动放置的中间设计点。
		for point in note.visual_pts:
			var rel := clampf(float(point.get("db", 0.0)), 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, grow)
			if _valid_point(p):
				_draw_diamond(canvas, p, 4.5, UITheme.GOLD)
	if not top:
		return
	_draw_target_arc(canvas, note.angle, note.width, t, UITheme.CORAL, 14.0 * PATH_SIZE_SCALE)
	if selected:
		for point in note.trace_pts:
			var node := _path_local_screen(chart, Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))), t, grow)
			if _valid_point(node):
				_draw_diamond(canvas, node, 5.0, UITheme.CYAN)
				canvas.draw_circle(node, 1.8, UITheme.INK)
	var head := _flying_position(chart, note.angle, note.beat, t, pre)
	# 尾部跟随轨迹一起从圆心长出，只落在平面内，不再回到环上。
	var tail := _path_screen_point(chart, note, total, t, true, grow)
	# 试玩时星星头在滑动开始后交给进度球，不再留在起点造成“断开的星头”。
	var head_visible := not playtest_mode or t < note.beat + wait + 0.02
	if head_visible:
		_draw_path_head(canvas, head, top, grow * ns, UITheme.CYAN)
		if _valid_point(head):
			# 重叠 Path 用不同颜色的外环 + 编号区分星头。
			var accents: Array[Color] = [UITheme.CORAL, UITheme.CYAN, UITheme.VIOLET, UITheme.MINT]
			var accent: Color = accents[note.id % accents.size()]
			canvas.draw_arc(head, 28.0 * ns * PATH_SIZE_SCALE, 0.0, TAU, 30, Color(accent.r, accent.g, accent.b, 0.95 if top else 0.45), 2.8, true)
			canvas.draw_string(UITheme.mono_font(), head + Vector2(20, -18), "#%d" % note.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(accent.r, accent.g, accent.b, 0.9 if top else 0.4))
		if top and _valid_point(head):
			# 头部的白色箭头指向轨迹内侧，进一步区分头和尾。
			var ahead := _path_screen_point(chart, note, minf(total, maxf(0.05, total * 0.08)), t, true, grow)
			if _valid_point(ahead):
				_draw_arrowhead(canvas, head + (ahead - head).normalized() * 29.0 * ns * PATH_SIZE_SCALE, ahead - head, Color(1, 1, 1, 0.95))
		if show_debug and top and _valid_point(head):
			canvas.draw_string(UITheme.bold_font(), head + Vector2(-12, -22), "PATH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.85))
	_draw_path_tail(canvas, tail, top, grow * ns)
	# 大号发光球 + 短拖尾：当前进度点始终比星头更亮，方向一目了然。
	if t >= note.beat and t <= note.end_beat:
		var rel := progress * total
		for trail_index in range(4, 0, -1):
			var trail_rel := rel - float(trail_index) * 0.035 * total
			if trail_rel < 0.0 or path_erased(note, trail_rel):
				continue
			var trail_point := _path_screen_point(chart, note, trail_rel, t, false)
			if _valid_point(trail_point):
				var fade := 0.34 * (1.0 - float(trail_index) / 5.0)
				canvas.draw_circle(trail_point, (18.0 - float(trail_index) * 1.6) * ns * PATH_SIZE_SCALE, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, fade))
		var p := _path_screen_point(chart, note, rel, t, false)
		if _valid_point(p):
			canvas.draw_circle(p, 32.0 * ns * PATH_SIZE_SCALE, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.18 if top else 0.07))
			canvas.draw_circle(p, 19.0 * ns * PATH_SIZE_SCALE, Color(0, 0, 0, 0.58))
			canvas.draw_circle(p, 16.0 * ns * PATH_SIZE_SCALE, UITheme.CYAN if top else Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.5))
			canvas.draw_circle(p, 10.0 * ns * PATH_SIZE_SCALE, Color(1, 1, 1, 0.96))
			canvas.draw_circle(p, 4.5 * ns * PATH_SIZE_SCALE, UITheme.INK)


func path_point(note: Note, relative_beat: float, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	return _path_screen_point(chart, note, relative_beat, beat, false)


static func path_erase_ranges(points: PackedVector2Array, from: Vector2, to: Vector2, radius: float) -> Array[Vector2]:
	# 返回被鼠标（或本帧鼠标扫过的线段）覆盖的时间比例区间。
	var ranges: Array[Vector2] = []
	if points.size() < 2:
		return ranges
	var segments := points.size() - 1
	var point_only := from.distance_to(to) < 0.5
	var start := -1
	for i in segments:
		var a := points[i]
		var b := points[i + 1]
		if not a.is_finite() or not b.is_finite():
			if start >= 0:
				ranges.append(Vector2(float(start) / float(segments), float(i) / float(segments)))
				start = -1
			continue
		var distance := INF
		if point_only:
			distance = from.distance_to(Geometry2D.get_closest_point_to_segment(from, a, b))
		else:
			var pair := Geometry2D.get_closest_points_between_segments(a, b, from, to)
			if pair.size() >= 2:
				distance = pair[0].distance_to(pair[1])
		if distance <= radius:
			if start < 0:
				start = i
		elif start >= 0:
			ranges.append(Vector2(float(start) / float(segments), float(i) / float(segments)))
			start = -1
	if start >= 0:
		ranges.append(Vector2(float(start) / float(segments), 1.0))
	return ranges


func _point_polyline_distance(points: PackedVector2Array, point: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if not a.is_finite() or not b.is_finite():
			continue
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


func erase_path_overlap(note: Note, from: Vector2, to: Vector2, beat: float) -> bool:
	var chart := get_chart()
	if chart == null:
		return false
	var total := note.duration()
	if total <= 0.001:
		return false
	var count := 96
	var points := PackedVector2Array()
	for i in count + 1:
		points.append(_path_screen_point(chart, note, total * float(i) / float(count), beat, false))
	var brush := 26.0 * _note_scale()
	# 多星星保护：只有鼠标当前或上一帧确实贴着这条 Path 时才擦，
	# 避免从 A 星移到 B 星时把路上穿过的 C 星误削。
	var guard := 72.0 * _note_scale()
	if minf(_point_polyline_distance(points, from), _point_polyline_distance(points, to)) > guard:
		return false
	var ranges := path_erase_ranges(points, from, to, brush)
	for span in ranges:
		_add_path_erase_range(note, span.x, span.y)
	return not ranges.is_empty()


static func merge_erase_ranges(ranges: Array, from_fraction: float, to_fraction: float) -> Array:
	var a := clampf(minf(from_fraction, to_fraction), 0.0, 1.0)
	var b := clampf(maxf(from_fraction, to_fraction), 0.0, 1.0)
	if a < 0.08:
		a = 0.0
	if b - a <= 0.002:
		return ranges
	var all: Array = ranges.duplicate(true)
	all.append({"from": a, "to": b})
	all.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.get("from", 0.0)) < float(y.get("from", 0.0)))
	var merged: Array = []
	for item in all:
		if merged.is_empty() or float(item.get("from", 0.0)) > float(merged[-1].get("to", 0.0)) + 0.035:
			merged.append({"from": float(item.get("from", 0.0)), "to": float(item.get("to", 0.0))})
		else:
			merged[-1]["to"] = maxf(float(merged[-1].get("to", 0.0)), float(item.get("to", 0.0)))
	return merged


func set_path_erased_to(note: Note, fraction: float) -> void:
	# 试玩时只保留一个连续缺口：从头部到当前进度，轨迹始终是连续的一段。
	var target := clampf(fraction, 0.0, 1.0)
	if target <= 0.004:
		return
	var current: Array = path_cuts.get(note.id, [])
	if current.size() == 1 and absf(float(current[0].get("to", -1.0)) - target) <= 0.001:
		return
	path_cuts[note.id] = [{"from": 0.0, "to": target}]
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


func path_fraction(note: Note, mouse: Vector2, beat: float) -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return {"fraction": 0.0, "distance": INF}
	var points := PackedVector2Array()
	var count := 48
	for i in count + 1:
		var p := _path_screen_point(chart, note, note.duration() * float(i) / float(count), beat, false)
		if _valid_point(p):
			points.append(p)
	if points.size() < 2:
		return {"fraction": 0.0, "distance": INF}
	var best := INF
	var best_fraction := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var length_squared := ab.length_squared()
		var q := 0.0 if length_squared <= 0.0001 else clampf((mouse - a).dot(ab) / length_squared, 0.0, 1.0)
		var distance := mouse.distance_to(a + ab * q)
		if distance < best:
			best = distance
			best_fraction = (float(i) + q) / float(points.size() - 1)
	return {"fraction": best_fraction, "distance": best}


func _add_path_erase_range(note: Note, from_fraction: float, to_fraction: float) -> void:
	var merged := merge_erase_ranges(path_cuts.get(note.id, []), from_fraction, to_fraction)
	if merged == path_cuts.get(note.id, []):
		return
	path_cuts[note.id] = merged
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


func path_erased(note: Note, relative_beat: float) -> bool:
	if note.erased_at(relative_beat):
		return true
	var total := maxf(0.000001, note.duration())
	var p := clampf(relative_beat / total, 0.0, 1.0)
	for gap in path_cuts.get(note.id, []):
		if p >= float(gap.get("from", 0.0)) and p <= float(gap.get("to", 1.0)):
			return true
	return false


func _path_local_screen(chart: Chart, local: Vector2, t: float, scale: float = 1.0) -> Vector2:
	var radius := local.length()
	if radius <= 0.0001:
		return project_design(Vector2.ZERO)
	var degrees := fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
	var data := _boundary_point(chart, degrees / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * radius * clampf(scale, 0.0, 1.0))


func _path_screen_point(chart: Chart, note: Note, relative_beat: float, t: float, cache_sample: bool = true, scale: float = 1.0) -> Vector2:
	var local: Vector2
	if cache_sample:
		if not _path_local_cache.has(note):
			_path_local_cache[note] = {}
		var samples: Dictionary = _path_local_cache[note]
		if not samples.has(relative_beat):
			samples[relative_beat] = note.path_local_at(relative_beat)
		local = samples[relative_beat]
	else:
		# The moving marker has a new relative time every frame; do not retain it.
		local = note.path_local_at(relative_beat)
	return _path_local_screen(chart, local, t, scale)


static func skin_presets() -> Dictionary:
	return {
		"candy": {"label": "糖霜胶囊", "scale": 1.20, "band": 1.14, "outline": 1.0, "glow": 1.3, "gloss": 0.6, "shadow": 0.8, "fill": 0.95},
		"neon": {"label": "霓虹线框", "scale": 1.10, "band": 1.06, "outline": 0.45, "glow": 2.0, "gloss": 0.15, "shadow": 0.0, "fill": 0.70},
		"glass": {"label": "玻璃棱镜", "scale": 1.16, "band": 1.10, "outline": 0.8, "glow": 0.9, "gloss": 0.9, "shadow": 0.35, "fill": 0.42},
		"sticker": {"label": "街机贴纸", "scale": 1.28, "band": 1.20, "outline": 1.55, "glow": 0.15, "gloss": 0.0, "shadow": 1.0, "fill": 1.0},
	}


static func hit_fx_presets() -> Dictionary:
	return {"burst": "迸裂", "ring": "圆环", "prism": "棱镜", "ink": "墨滴"}


func refresh_style() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _skin() -> Dictionary:
	if _skin_cache_key == note_skin and not _skin_cache.is_empty():
		return _skin_cache
	var presets := skin_presets()
	var chosen: Dictionary = presets.get(note_skin, {})
	if chosen.is_empty():
		chosen = presets["candy"]
	_skin_cache = chosen.duplicate()
	_skin_cache["id"] = note_skin if presets.has(note_skin) else "candy"
	_skin_cache_key = note_skin
	return _skin_cache


func _stroke_band(canvas: Control, points: PackedVector2Array, color: Color, width: float, alpha: float = 1.0, size_scale: float = -1.0) -> void:
	# 所有音符共用同一套描边/高光/发光，换肤只改参数，不改判定。
	if points.size() < 2:
		return
	var skin := _skin()
	var k := float(skin["scale"]) if size_scale < 0.0 else size_scale
	var band := float(skin["band"]) if size_scale < 0.0 else 1.0
	var outline := float(skin["outline"])
	var glow := float(skin["glow"])
	var gloss := float(skin["gloss"])
	var shadow := float(skin["shadow"])
	var w := width * k * band
	if glow > 0.01:
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.10 * glow * alpha), w + 18.0, true)
	if shadow > 0.01:
		var offset := PackedVector2Array()
		for p in points:
			offset.append(p + Vector2(5, 7) * shadow)
		canvas.draw_polyline(offset, Color(0, 0, 0, 0.38 * shadow * alpha), w + 10.0, true)
	canvas.draw_polyline(points, Color(0, 0, 0, 0.62 * outline * alpha), w + 5.0 * outline, true)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.92 * alpha), w, true)
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.94 * alpha), maxf(3.0, w * 0.62), true)
	if gloss > 0.01:
		canvas.draw_polyline(points, Color(1, 1, 0.94, 0.34 * gloss * alpha), maxf(1.5, w * 0.16), true)
	if String(skin["id"]) == "neon":
		canvas.draw_polyline(points, Color(0.04, 0.06, 0.08, 0.85 * alpha), maxf(2.0, w * 0.20), true)


func _draw_path_head(canvas: Control, point: Vector2, top: bool, scale: float = 1.0, color: Color = UITheme.CORAL) -> void:
	if not _valid_point(point):
		return
	var alpha := 1.0 if top else 0.45
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE
	canvas.draw_circle(point, 31.0 * s, Color(color.r, color.g, color.b, 0.18 * alpha))
	canvas.draw_circle(point, 24.0 * s, Color(0, 0, 0, 0.32 * alpha))
	canvas.draw_arc(point, 24.0 * s, 0.0, TAU, 30, Color(1, 1, 1, 0.30 * alpha), 2.0, true)
	_draw_star_filled(canvas, point, 18.0 * s, Color(color.r, color.g, color.b, alpha))


func _draw_star_filled(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for layer in 3:
		points = PackedVector2Array()
		var layer_radius := radius + (3.6 if layer == 0 else (1.2 if layer == 1 else 0.0))
		for i in 10:
			var angle := -PI * 0.5 + TAU * float(i) / 10.0
			var r := layer_radius if i % 2 == 0 else layer_radius * 0.45
			points.append(point + Vector2(cos(angle), sin(angle)) * r)
		canvas.draw_colored_polygon(points, Color(0, 0, 0, 0.68) if layer == 0 else (Color(1, 1, 1, 0.96) if layer == 1 else color))
		points.append(points[0])
		canvas.draw_polyline(points, Color(0, 0, 0, 0.7) if layer == 0 else (Color(1, 1, 1, 0.96) if layer == 1 else UITheme.INK), 1.4, true)
	canvas.draw_circle(point, radius * 0.24, Color(0, 0, 0, 0.82))


func _draw_path_tail(canvas: Control, point: Vector2, top: bool, scale: float = 1.0, color: Color = UITheme.GOLD) -> void:
	if not _valid_point(point):
		return
	var alpha := 1.0 if top else 0.45
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE
	# 舞萌的滑动终点也是一颗星；比头小一圈，并用外环区分。
	canvas.draw_circle(point, 20.0 * s, Color(color.r, color.g, color.b, 0.10 * alpha))
	canvas.draw_arc(point, 17.0 * s, 0.0, TAU, 30, Color(color.r, color.g, color.b, 0.55 * alpha), 1.8, true)
	_draw_star_filled(canvas, point, 12.0 * s, Color(color.r, color.g, color.b, alpha))


func _hold_node_screen(chart: Chart, note: Note, relative_beat: float, relative_angle: float, t: float) -> Vector2:
	var duration := maxf(0.001, note.duration())
	var q := clampf(relative_beat / duration, 0.0, 1.0)
	var angle := fposmod(note.angle + relative_angle, 360.0)
	var data := _boundary_point(chart, angle / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	var center := project_design(Vector2.ZERO)
	var boundary := project_design(data.point)
	return center.lerp(boundary, 0.25).lerp(boundary, q)


func _draw_holds(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var ns := _note_scale()
	var visible: Array[Note] = []
	for note in _notes_in_range(chart, t - pre - 128.0, t + pre + 0.3):
		if note.type == "hold" and t >= note.beat - pre and t <= note.end_beat + 0.3:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	for note in visible:
		# 结束后 0.24 拍内渐隐，而不是瞬间消失。
		var fade := 1.0 if t <= note.end_beat else clampf(1.0 - (t - note.end_beat) / 0.24, 0.0, 1.0)
		if fade <= 0.01:
			continue
		var grow_raw := clampf((t - (note.beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
		# 与 Tap 同一套接近表现：环心处只有 1/6 长，飞近时长大到 1。
		var grow := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, grow_raw)
		var center := project_design(Vector2.ZERO)
		var body := PackedVector2Array()
		var curved := note.hold_style == "curved" and note.visual_pts.is_empty()
		if not note.visual_pts.is_empty():
			# Hold 体节点：和 Path 共用 visual_pts，节点只改画面，不改头部判定。
			var design_points: Array[Dictionary] = [{"db": 0.0, "da": 0.0}]
			design_points.append_array(note.visual_pts)
			design_points.append({"db": note.duration(), "da": 0.0})
			design_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("db", 0.0)) < float(b.get("db", 0.0)))
			for point in design_points:
				var p := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
				if _valid_point(p):
					body.append(center.lerp(p, grow))
		elif curved:
			# 弯 Hold：本体沿环弯曲，尾部有明确端环。
			var span := clampf(16.0 + note.duration() * 12.0, 20.0, 64.0)
			var steps := maxi(10, int(span / 3.0))
			for i in steps + 1:
				var angle := note.angle + span * float(i) / float(steps)
				var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
				if bool(data.get("gap", false)):
					continue
				body.append(center.lerp(project_design(data.point), grow))
		else:
			# 直 Hold：从内圈笔直连到环上，圆头胶囊；导入默认用这种。
			var data := _boundary_point(chart, fposmod(note.angle, 360.0) / 360.0, t)
			if bool(data.get("gap", false)):
				continue
			var outer := project_design(data.point)
			var inner := center.lerp(outer, 0.28)
			for i in 7:
				body.append(center.lerp(inner.lerp(outer, float(i) / 6.0), grow))
		if body.size() < 2:
			continue
		var boundary: Vector2 = body[-1]
		var hs := ns * float(_skin()["scale"])
		# 舞萌式 Hold：金色胶囊 + 粉色圆环头，不再用六边形。
		_stroke_band(canvas, body, UITheme.GOLD, 16.0 * ns, fade)
		canvas.draw_circle(body[0], 10.0 * hs, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.90 * fade))
		canvas.draw_circle(body[0], 5.0 * hs, Color(1, 1, 1, 0.28 * fade))
		_draw_target_arc(canvas, note.angle, note.arc_width(), t, UITheme.GOLD, 12.0)
		# 外端是粉色 Tap 环，方便读松手时机。
		_draw_tap_donut(canvas, boundary, 20.0 * hs, UITheme.GOLD, fade)
		if t >= note.beat and t <= note.end_beat:
			var progress := clampf((t - note.beat) / maxf(0.001, note.duration()), 0.0, 1.0)
			var marker_index := progress * float(body.size() - 1)
			var lower := clampi(int(marker_index), 0, body.size() - 1)
			var upper := mini(lower + 1, body.size() - 1)
			var marker := body[lower].lerp(body[upper], marker_index - float(lower))
			canvas.draw_circle(marker, 12.0 * hs, Color(1, 1, 1, 0.28))
			canvas.draw_circle(marker, 8.0 * hs, Color(1, 1, 1, 0.96))
			canvas.draw_circle(marker, 4.0 * hs, UITheme.GOLD)
		if fade > 0.999 and t < note.beat + 0.02:
			var head := _flying_position(chart, note.angle, note.beat, t, pre)
			_draw_tap_donut(canvas, head, 18.0 * hs * clampf(grow, Note.SPAWN_LENGTH_RATIO, 1.0), UITheme.GOLD, fade)
			if show_debug and _valid_point(head):
				canvas.draw_string(UITheme.bold_font(), head + Vector2(-14, -22), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.85))
		if t >= note.beat and t <= note.end_beat:
			var glow := 0.5 + 0.5 * sin(t * PI)
			canvas.draw_arc(boundary, 28.0 * hs, 0.0, TAU, 32, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.28 * glow), 2.6, true)
		if _app != null and not note.visual_pts.is_empty():
			var selected: Note = _app.get_selected_note()
			if selected != null and selected.id == note.id:
				for point in note.visual_pts:
					var marker := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
					if _valid_point(marker):
						_draw_diamond(canvas, marker, 5.5, UITheme.GOLD)


func _draw_notes(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var visible: Array[Note] = []
	for note in _notes_in_range(chart, t - pre - 0.1, t + pre + 0.1):
		if note.type in ["path", "hold", "trace"]:
			continue
		if t >= note.beat - pre and t <= note.beat + 0.3:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	for note in visible:
		match note.type:
			"tap":
				_draw_tap_note(canvas, chart, note, t, pre)
			"anchor":
				var grow := clampf((t - (note.beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
				var p := _flying_position(chart, note.angle, note.beat, t, pre)
				if _valid_point(p):
					canvas.draw_circle(p, 27.0 * grow, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.14))
				_draw_diamond(canvas, p, 16.0 * clampf(grow, 0.35, 1.0), UITheme.VIOLET)
			"bell":
				var bell := bell_screen(note, t)
				if not bell.is_empty():
					_draw_bell(canvas, bell["center"], bell["radius"], t, note.beat, pre)


func _draw_tap_donut(canvas: Control, point: Vector2, radius: float, color: Color, alpha: float = 1.0) -> void:
	# 舞萌式 Tap：固定大小的粉色圆环，不随判定宽度拉成长条。
	var skin := _skin()
	var outline := float(skin["outline"])
	var glow := float(skin["glow"])
	var gloss := float(skin["gloss"])
	canvas.draw_circle(point, radius + 10.0, Color(color.r, color.g, color.b, 0.10 * glow * alpha))
	canvas.draw_circle(point, radius + 3.5 * outline, Color(0, 0, 0, 0.66 * alpha))
	canvas.draw_circle(point, radius + 1.2, Color(1, 1, 1, 0.94 * alpha))
	canvas.draw_circle(point, radius - 1.0, Color(color.r, color.g, color.b, 0.95 * alpha))
	canvas.draw_circle(point, radius * 0.58, Color(0.04, 0.05, 0.07, 0.92 * alpha))
	canvas.draw_arc(point, radius * 0.58, 0.0, TAU, 28, Color(1, 1, 1, 0.55 * alpha), 1.4, true)
	canvas.draw_circle(point, radius * 0.18, Color(color.r, color.g, color.b, 0.65 * alpha))
	if gloss > 0.01:
		canvas.draw_arc(point, radius * 0.82, -PI * 0.85, -PI * 0.25, 16, Color(1, 1, 1, 0.42 * gloss * alpha), 2.0, true)


func _draw_tap_note(canvas: Control, chart: Chart, note: Note, t: float, pre: float) -> void:
	# 长度系统：普通 Tap = 0.5 l，大小 Tap = size_ratio × l；条带随半径从 1/6 长到 1。
	var ns := _note_scale()
	var width := note.arc_width()
	var progress := clampf((t - (note.beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
	var q := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress)
	if width <= 0.05:
		# 长度为 0 的大小 Tap 仍然占一个位置，留一个点提示它存在。
		var tip := _boundary_point(chart, fposmod(note.angle, 360.0) / 360.0, t)
		if not bool(tip.get("gap", false)):
			var dot := project_design((tip.point as Vector2) * q)
			if _valid_point(dot):
				canvas.draw_circle(dot, 7.0 * ns, Color(UITheme.PINK.r, UITheme.PINK.g, UITheme.PINK.b, 0.90))
		return
	var steps := clampi(int(width / 4.0), 10, 96)
	var points := PackedVector2Array()
	for i in steps + 1:
		var angle := note.angle - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var p := project_design(data.point * q)
		if _valid_point(p):
			points.append(p)
	if points.size() < 2:
		return
	_stroke_band(canvas, points, UITheme.PINK, 18.0 * ns)
	var cap_scale := ns * float(_skin()["scale"])
	# 两端圆头：让长条读成一根胶囊，而不是一段没有边界的弧。
	for cap in [points[0], points[-1]]:
		canvas.draw_circle(cap, 12.0 * cap_scale, Color(0, 0, 0, 0.66))
		canvas.draw_circle(cap, 9.5 * cap_scale, Color(1, 1, 1, 0.94))
		canvas.draw_circle(cap, 6.0 * cap_scale, UITheme.PINK)
	# 中心命中点：宽度变化时仍然知道该按哪里。
	var center_point := points[points.size() / 2]
	canvas.draw_circle(center_point, 8.0 * cap_scale, Color(0, 0, 0, 0.55))
	canvas.draw_circle(center_point, 6.0 * cap_scale, Color(1, 1, 1, 0.96))
	canvas.draw_circle(center_point, 3.0 * cap_scale, UITheme.PINK)
	if show_debug:
		canvas.draw_string(UITheme.bold_font(), center_point + Vector2(-12, -22), "TAP %.0f°%s" % [note.arc_width(), " ×l %.2f" % note.size_ratio if note.sized else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.PINK.r, UITheme.PINK.g, UITheme.PINK.b, 0.85))


func _draw_traces(canvas: Control, chart: Chart, t: float) -> void:
	var pre := _pre_read_beats(chart, t)
	var visible: Array[Note] = []
	for note in _notes_in_range(chart, t - pre - 128.0, t + pre + 0.5):
		if note.type != "trace":
			continue
		var lead := pre if note.trace_style == "slider" else 0.5
		if t >= note.beat - lead and t <= note.end_beat + 0.5:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	for note in visible:
		var lead := pre if note.trace_style == "slider" else 0.5
		var grow := clampf((t - (note.beat - lead)) / maxf(0.001, lead), 0.0, 1.0)
		var points := trace_screen_points(note, t, grow)
		if points.size() > 1 and note.trace_style == "slider":
			_draw_slider_trace(canvas, note, points, t, grow)
			continue
		if points.size() > 1:
			var duration := maxf(0.001, note.duration())
			var progress := clampf((t - note.beat) / duration, 0.0, 1.0)
			var ns_trace := _note_scale() * float(_skin()["scale"])
			_stroke_band(canvas, points, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.85), 16.0 * ns_trace * TRACE_SIZE_SCALE, 0.78)
			canvas.draw_polyline(_offset_polyline(points, 12.0 * TRACE_SIZE_SCALE), Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.62), 1.6 * TRACE_SIZE_SCALE, true)
			canvas.draw_polyline(_offset_polyline(points, -12.0 * TRACE_SIZE_SCALE), Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.62), 1.6 * TRACE_SIZE_SCALE, true)
			_draw_dashed_polyline(canvas, points, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.92), 2.4 * TRACE_SIZE_SCALE, 7.0 * TRACE_SIZE_SCALE)
			var arrow_count := 5
			for k in arrow_count:
				var fraction := (float(k) + 0.5) / float(arrow_count)
				var sample := _polyline_sample(points, fraction)
				_draw_arrowhead(canvas, sample["point"], sample["direction"], Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.95))
			var prefix := _polyline_prefix(points, progress)
			if prefix.size() > 1:
				canvas.draw_polyline(prefix, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.26), 30.0 * TRACE_SIZE_SCALE, true)
			for i in range(0, note.trace_pts.size(), maxi(1, note.trace_pts.size() / 8)):
				_draw_diamond(canvas, points[i], 3.2 * TRACE_SIZE_SCALE, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.85))
			_draw_trace_cap(canvas, points[0], true)
			_draw_trace_cap(canvas, points[-1], false)
			if show_debug:
				_draw_label(canvas, "TRACE", points[0] + Vector2(14, -14), UITheme.MINT)
		var position := _trace_position(note, t)
		if _valid_point(position):
			canvas.draw_circle(position, 24.0 * TRACE_SIZE_SCALE, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.14))
			canvas.draw_circle(position, 15.0 * TRACE_SIZE_SCALE, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.92))
			canvas.draw_circle(position, 6.0 * TRACE_SIZE_SCALE, UITheme.INK)
			canvas.draw_arc(position, 20.0 * TRACE_SIZE_SCALE, 0.0, TAU, 28, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.75), 2.0, true)
	if _drawing_trace and _trace_points.size() > 1:
		var temp := PackedVector2Array()
		for p in _trace_points:
			temp.append(p)
		canvas.draw_polyline(temp, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.7), 3.0, true)


func cut_trace(note: Note, from_fraction: float, to_fraction: float) -> void:
	var a := clampf(minf(from_fraction, to_fraction), 0.0, 1.0)
	var b := clampf(maxf(from_fraction, to_fraction), 0.0, 1.0)
	if b - a <= 0.004:
		return
	if not trace_cuts.has(note.id):
		trace_cuts[note.id] = []
	trace_cuts[note.id].append({"from": a, "to": b})
	if _overlay != null:
		_overlay.queue_redraw()


func trace_fraction(note: Note, mouse: Vector2, beat: float) -> Dictionary:
	var points := trace_screen_points(note, beat)
	if points.size() < 2:
		return {"fraction": 0.0, "distance": INF}
	var best := INF
	var best_fraction := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var length_squared := ab.length_squared()
		var t := 0.0 if length_squared <= 0.0001 else clampf((mouse - a).dot(ab) / length_squared, 0.0, 1.0)
		var distance := mouse.distance_to(a + ab * t)
		if distance < best:
			best = distance
			best_fraction = (float(i) + t) / float(points.size() - 1)
	return {"fraction": best_fraction, "distance": best}


func _draw_slider_trace(canvas: Control, note: Note, points: PackedVector2Array, t: float, grow: float = 1.0) -> void:
	var ns := _note_scale()
	var duration := maxf(0.001, note.duration())
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, duration - 0.001))
	var progress := clampf((t - note.beat - wait) / maxf(0.001, duration - wait) * star_speed, 0.0, 1.0)
	var runs := _trace_visible_runs(note, points)
	for run in runs:
		if run.size() < 2:
			continue
		# 宽笔刷主体：去掉中心虚线和箭头，让星头、带体、尾环读成同一条轨迹。
		_stroke_band(canvas, run, Color(0.78, 0.94, 0.92), 16.0 * ns * TRACE_SIZE_SCALE)
	# 流动高光：跟着引导星走的一小段亮带。
	var from_index := clampi(int((progress - 0.16) * float(points.size())), 0, points.size() - 1)
	var to_index := clampi(int((progress + 0.04) * float(points.size())) + 1, from_index + 1, points.size())
	var highlight := PackedVector2Array()
	for i in range(from_index, to_index):
		if not _trace_index_cut(note, i, points.size()):
			highlight.append(points[i])
	if highlight.size() > 1:
		canvas.draw_polyline(highlight, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.30), 18.0 * TRACE_SIZE_SCALE, true)
		canvas.draw_polyline(highlight, Color(1, 1, 1, 0.82), 8.0 * TRACE_SIZE_SCALE, true)
	# 星头和圆环尾都是轨迹的一部分：固定画在轨迹两端，尾部不单独飞入。
	_draw_path_head(canvas, points[0], true, grow * ns, UITheme.CYAN)
	if points.size() > 1:
		var head_dir := (points[1] - points[0]).normalized()
		_draw_arrowhead(canvas, points[0] + head_dir * 22.0 * ns * TRACE_SIZE_SCALE, head_dir, Color(1, 1, 1, 0.95))
	_draw_path_tail(canvas, points[-1], true, grow * ns, UITheme.CYAN)
	var position := _trace_position(note, t)
	if _valid_point(position):
		canvas.draw_circle(position, 17.0 * TRACE_SIZE_SCALE, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.20))
		canvas.draw_circle(position, 11.5 * TRACE_SIZE_SCALE, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.92))
		canvas.draw_circle(position, 4.5 * TRACE_SIZE_SCALE, UITheme.INK)
	if show_debug:
		_draw_label(canvas, "SLIDE", points[0] + Vector2(18, -16), UITheme.CYAN)


func _trace_visible_runs(note: Note, points: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in points.size():
		if _trace_index_cut(note, i, points.size()):
			if run.size() > 1:
				result.append(run)
			run = PackedVector2Array()
			continue
		run.append(points[i])
	if run.size() > 1:
		result.append(run)
	return result


func _trace_index_cut(note: Note, index: int, count: int) -> bool:
	if not trace_cuts.has(note.id) or count <= 1:
		return false
	var fraction := float(index) / float(count - 1)
	for cut in trace_cuts[note.id]:
		if fraction >= float(cut.get("from", 0.0)) and fraction <= float(cut.get("to", 1.0)):
			return true
	return false


func _draw_trace_cap(canvas: Control, point: Vector2, start: bool) -> void:
	if not _valid_point(point):
		return
	var color := Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.95)
	canvas.draw_circle(point, 14.0 * TRACE_SIZE_SCALE, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.16))
	canvas.draw_arc(point, 12.0 * TRACE_SIZE_SCALE, 0.0, TAU, 20, color, 2.4 * TRACE_SIZE_SCALE, true)
	if start:
		canvas.draw_circle(point, 5.0 * TRACE_SIZE_SCALE, color)
	else:
		_draw_diamond(canvas, point, 7.0 * TRACE_SIZE_SCALE, color)


func _offset_polyline(points: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var previous := points[maxi(0, i - 1)]
		var next := points[mini(points.size() - 1, i + 1)]
		var direction := (next - previous).normalized()
		if direction.length_squared() < 0.1:
			direction = Vector2.RIGHT
		result.append(points[i] + Vector2(-direction.y, direction.x) * offset)
	return result


func _polyline_prefix(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if points.size() < 2:
		return result
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := clampf(fraction, 0.0, 1.0) * total
	var cursor := 0.0
	result.append(points[0])
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if cursor + segment >= target:
			var p := (target - cursor) / maxf(0.001, segment)
			result.append(points[i].lerp(points[i + 1], p))
			return result
		result.append(points[i + 1])
		cursor += segment
	return result


func _draw_boundary_controls(canvas: Control, chart: Chart) -> void:
	if not show_debug and not (_app != null and _app.boundary_mode):
		return
	var shape := _active_shape()
	if shape == null:
		return
	var sorted := shape.sorted_segments()
	var selected: int = -1 if _app == null else int(_app.selected_segment_index)
	for index in sorted.size():
		var segment := sorted[index]
		var color := UITheme.CORAL if index == selected else UITheme.CYAN
		for endpoint in 2:
			var point: Vector2 = segment.p0 if endpoint == 0 else segment.p1
			var p := project_design(point)
			if not _valid_point(p):
				continue
			var rect := Rect2(p - Vector2(4, 4), Vector2(8, 8))
			canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.95))
			canvas.draw_rect(rect, UITheme.BG, false, 1.0)
		if index == selected:
			_draw_segment_highlight(canvas, segment, selected)


func _draw_segment_highlight(canvas: Control, segment: BoundarySegment, _index: int) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var p := project_design(segment.point_at(float(i) / 32.0))
		if _valid_point(p):
			points.append(p)
	if points.size() > 1:
		canvas.draw_polyline(points, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.45), 6.0, true)


func _draw_cursor(canvas: Control, chart: Chart, t: float) -> void:
	if not custom_cursor_visible or (not mouse_inside and not playtest_mode):
		return
	_draw_player_cursor(canvas)
	if playtest_mode:
		return
	var p := project_u(cursor_u, t)
	if cursor_valid and _valid_point(p):
		canvas.draw_circle(p, 7.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.22))
		canvas.draw_arc(p, 6.5, 0.0, TAU, 24, UITheme.CORAL, 1.6, true)
		canvas.draw_circle(p, 1.8, UITheme.CORAL)
		if show_debug:
			canvas.draw_string(UITheme.mono_font(), p + Vector2(12, 22), "u %.1f°" % (cursor_u * 360.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func _draw_player_cursor(canvas: Control) -> void:
	var accent := UITheme.CYAN if cursor_valid or playtest_mode else UITheme.MUTED
	# osu 风格拖尾：连续线段填补采样空隙，越靠近光标越大、越亮，停手后自然消失。
	for i in range(1, _cursor_trail.size()):
		var previous: Dictionary = _cursor_trail[i - 1]
		var current: Dictionary = _cursor_trail[i]
		var life := clampf(1.0 - float(current.get("age", 0.0)) / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i) / float(maxi(1, _cursor_trail.size() - 1))
		canvas.draw_line(previous["pos"], current["pos"], Color(accent.r, accent.g, accent.b, 0.10 * life), lerpf(2.5, 9.0, ratio), true)
	for i in _cursor_trail.size():
		var item: Dictionary = _cursor_trail[i]
		var age := float(item.get("age", 0.0))
		var life := clampf(1.0 - age / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i + 1) / float(maxi(1, _cursor_trail.size()))
		var point: Vector2 = item["pos"]
		var radius := lerpf(3.0, 10.5, ratio)
		canvas.draw_circle(point, radius * 1.9, Color(accent.r, accent.g, accent.b, 0.06 * life))
		canvas.draw_circle(point, radius, Color(accent.r, accent.g, accent.b, 0.26 * life))
		canvas.draw_circle(point, radius * 0.45, Color(1, 1, 1, 0.16 * life))
	var m := mouse_screen
	var spin := Time.get_ticks_msec() / 1000.0 * 2.2
	canvas.draw_circle(m, 27.0, Color(accent.r, accent.g, accent.b, 0.035))
	canvas.draw_circle(m, 20.0, Color(accent.r, accent.g, accent.b, 0.06))
	canvas.draw_arc(m, 19.5, spin, spin + PI * 0.85, 22, Color(accent.r, accent.g, accent.b, 0.72), 1.7, true)
	canvas.draw_arc(m, 19.5, spin + PI, spin + PI * 1.75, 22, Color(accent.r, accent.g, accent.b, 0.34), 1.2, true)
	canvas.draw_arc(m, 14.0, 0.0, TAU, 48, Color(0, 0, 0, 0.62), 5.4, true)
	canvas.draw_arc(m, 14.0, 0.0, TAU, 48, Color(1, 1, 1, 0.96), 2.6, true)
	canvas.draw_arc(m, 9.2, 0.0, TAU, 36, Color(accent.r, accent.g, accent.b, 0.95), 2.0, true)
	canvas.draw_circle(m, 4.4, Color(0, 0, 0, 0.78))
	canvas.draw_circle(m, 2.5, Color(1, 1, 1, 0.98))
	for k in 4:
		var direction := Vector2.from_angle(float(k) * PI * 0.5)
		canvas.draw_line(m + direction * 15.5, m + direction * 19.0, Color(1, 1, 1, 0.42), 1.2, true)
	if not cursor_valid and playtest_mode and show_debug:
		canvas.draw_string(UITheme.mono_font(), m + Vector2(18, -16), "环外", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func request_redraw() -> void:
	_mesh_dirty = true
	if _overlay != null:
		_overlay.queue_redraw()


func add_hit_pulse(point: Vector2, color: Color, label: String = "HIT", kind: String = "tap") -> void:
	if not _valid_point(point):
		return
	var sparks: Array[float] = []
	for i in 16:
		sparks.append(randf_range(0.0, TAU))
	_pulses.append({"pos": point, "age": 0.0, "color": color, "label": label, "kind": kind, "sparks": sparks})
	if _overlay != null:
		_overlay.queue_redraw()


func add_arc_flash(angle_degrees: float, width: float, beat: float, color: Color) -> void:
	if not playtest_mode or _overlay == null:
		return
	_arc_flashes.append({"angle": angle_degrees, "width": width, "beat": beat, "color": color, "age": 0.0})
	_overlay.queue_redraw()


func _draw_arc_flashes(canvas: Control) -> void:
	for flash in _arc_flashes:
		var age := float(flash.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.32, 0.0, 1.0)
		var color: Color = flash["color"]
		var width := float(flash.get("width", 60.0)) * lerpf(1.0, 1.35, age / 0.32)
		var points := _arc_points(float(flash["angle"]), width, float(flash["beat"]), 36)
		if points.size() < 2:
			continue
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.28 * alpha), 34.0, true)
		canvas.draw_polyline(points, Color(1, 1, 1, 0.7 * alpha), 10.0 * alpha + 2.0, true)
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.95 * alpha), 3.0, true)


func _draw_pulses(canvas: Control) -> void:
	for pulse in _pulses:
		var age := float(pulse.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.42, 0.0, 1.0)
		var point: Vector2 = pulse["pos"]
		var color: Color = pulse["color"]
		var sparks: Array = pulse.get("sparks", [])
		match hit_fx_style:
			"ring":
				_draw_fx_ring(canvas, point, color, age, sparks)
			"prism":
				_draw_fx_prism(canvas, point, color, age, sparks)
			"ink":
				_draw_fx_ink(canvas, point, color, age, sparks)
			_:
				_draw_fx_burst(canvas, point, color, age, sparks)
		match String(pulse.get("kind", "tap")):
			"hold":
				canvas.draw_line(point + Vector2(0, -92.0 * (1.0 - alpha)), point - Vector2(0, 20), Color(color.r, color.g, color.b, 0.35 * alpha), 12.0, true)
			"bell":
				canvas.draw_arc(point, 28.0 + age * 20.0, 0.0, TAU, 28, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, alpha), 3.4, true)
				for k in 8:
					var a := float(k) * TAU / 8.0
					var inner := point + Vector2(cos(a), sin(a)) * (12.0 + age * 26.0)
					var outer := point + Vector2(cos(a), sin(a)) * (28.0 + age * 62.0)
					canvas.draw_line(inner, outer, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.75 * alpha), 2.4, true)
			"path":
				for k in 5:
					var a := float(k) * TAU / 5.0
					canvas.draw_circle(point + Vector2(cos(a), sin(a)) * (22.0 + age * 54.0), 3.6 * alpha, Color(1, 1, 1, alpha))
			"trace":
				canvas.draw_line(point - Vector2(52, 0), point + Vector2(52, 0), Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.5 * alpha), 9.0 * alpha + 1.0, true)
		var text_scale := 1.0 + 0.28 * clampf(1.0 - age / 0.12, 0.0, 1.0)
		canvas.draw_string_outline(UITheme.bold_font(), point + Vector2(30, -36 - age * 30), String(pulse.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * text_scale), 4, Color(0, 0, 0, 0.55 * alpha))
		canvas.draw_string(UITheme.bold_font(), point + Vector2(30, -36 - age * 30), String(pulse.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * text_scale), Color(color.r, color.g, color.b, alpha))


func _draw_fx_burst(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 舞萌式：白闪 + 冲击环 + 锥形碎片，落点最明确。
	var t := clampf(age / 0.40, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.16, 0.0, 1.0)
	if flash > 0.0:
		canvas.draw_circle(point, 48.0 * flash + 8.0, Color(color.r, color.g, color.b, 0.18 * flash))
		canvas.draw_circle(point, 26.0 * flash + 5.0, Color(1, 1, 1, 0.30 * flash))
		canvas.draw_circle(point, 13.0 * flash + 3.0, Color(1, 1, 1, 0.92 * flash))
		# 舞萌式四角星：命中瞬间在音符上炸开一颗星。
		var star_points := PackedVector2Array()
		var spin := -PI * 0.5 + age * 0.9
		for i in 8:
			var angle := spin + TAU * float(i) / 8.0
			var radius := (40.0 * flash + 10.0) if i % 2 == 0 else (13.0 * flash + 5.0)
			star_points.append(point + Vector2(cos(angle), sin(angle)) * radius)
		canvas.draw_colored_polygon(star_points, Color(1, 1, 1, 0.26 * flash))
		var star_outline := star_points.duplicate()
		star_outline.append(star_points[0])
		canvas.draw_polyline(star_outline, Color(1, 1, 1, 0.78 * flash), 2.0, true)
	# 实心冲击盘 + 双层环。
	canvas.draw_circle(point, 30.0 + 42.0 * t, Color(color.r, color.g, color.b, 0.12 * fade))
	var ring_radius := 14.0 + 82.0 * (1.0 - pow(1.0 - t, 3.0))
	canvas.draw_arc(point, ring_radius, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.78 * fade), 3.0 + 6.0 * fade, true)
	canvas.draw_arc(point, ring_radius * 1.26, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.24 * fade), 1.2 + 2.0 * fade, true)
	for i in sparks.size():
		var angle := float(sparks[i])
		var length := 0.40 + 0.60 * absf(sin(float(i) * 2.3))
		var direction := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-direction.y, direction.x)
		var inner := point + direction * (9.0 + 16.0 * t)
		var outer := point + direction * (24.0 + 88.0 * t * length)
		var half := 3.6 * (1.0 - t) + 1.0
		canvas.draw_colored_polygon(PackedVector2Array([inner + normal * half, inner - normal * half, outer]), Color(color.r, color.g, color.b, 0.88 * fade))
		canvas.draw_line(inner, outer, Color(1, 1, 1, 0.72 * fade), 1.2, true)
		canvas.draw_circle(outer, 3.4 * fade, Color(1, 1, 1, 0.90 * fade))
	# 四向长星芒，给“打中了”一个明确的中心。
	for k in 4:
		var angle := PI * 0.25 + float(k) * PI * 0.5 + age * 0.6
		var direction := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-direction.y, direction.x)
		var tip := point + direction * (42.0 + 58.0 * t)
		var base := point + direction * (10.0 + 16.0 * t)
		canvas.draw_colored_polygon(PackedVector2Array([base + normal * 2.4, base - normal * 2.4, tip]), Color(1, 1, 1, 0.34 * fade))
	canvas.draw_circle(point, 8.0 * fade, Color(color.r, color.g, color.b, fade))


func _draw_fx_ring(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# osu 式：实心 hit circle + 向外扩散的光环，干净不挡读谱。
	var t := clampf(age / 0.40, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.12, 0.0, 1.0)
	var core := 34.0 * (1.0 - 0.50 * t)
	if flash > 0.0:
		canvas.draw_circle(point, core + 18.0 * flash, Color(1, 1, 1, 0.22 * flash))
	canvas.draw_circle(point, core + 9.0, Color(color.r, color.g, color.b, 0.26 * fade))
	canvas.draw_circle(point, core, Color(1, 1, 1, 0.92 * fade))
	canvas.draw_arc(point, core + 2.5, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.95 * fade), 4.0 * fade + 1.0, true)
	canvas.draw_arc(point, maxf(2.0, core - 6.0), 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.55 * fade), 1.6, true)
	var ring_radius := 20.0 + 74.0 * (1.0 - pow(1.0 - t, 2.0))
	canvas.draw_arc(point, ring_radius, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.80 * fade), 2.6 + 2.0 * fade, true)
	canvas.draw_arc(point, ring_radius + 11.0, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.28 * fade), 1.2, true)
	for k in 4:
		var angle := PI * 0.25 + float(k) * PI * 0.5
		var spark := point + Vector2(cos(angle), sin(angle)) * (30.0 + 48.0 * t)
		_draw_diamond(canvas, spark, 8.5 * fade, color)
	canvas.draw_circle(point, 6.0 * fade, Color(color.r, color.g, color.b, fade))


func _draw_fx_prism(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 棱镜式：三色三角碎片旋出，适合高亮曲目。
	var t := clampf(age / 0.32, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.12, 0.0, 1.0)
	canvas.draw_circle(point, 26.0 * flash + 4.0, Color(1, 1, 1, 0.55 * flash))
	var palette: Array[Color] = [color, UITheme.CYAN, UITheme.GOLD]
	for i in 3:
		var base := float(sparks[i % maxi(1, sparks.size())]) if not sparks.is_empty() else float(i) * TAU / 3.0
		var angle := base + t * 1.6
		var center := point + Vector2(cos(angle), sin(angle)) * (12.0 + 72.0 * t)
		var size := (13.0 + 7.0 * sin(float(i))) * (1.0 - 0.5 * t)
		var spin := angle + PI * 0.5 + t * 2.4 * float(i - 1)
		var triangle := PackedVector2Array()
		for j in 3:
			var a := spin + TAU * float(j) / 3.0
			triangle.append(center + Vector2(cos(a), sin(a)) * size)
		var tint: Color = palette[i % palette.size()]
		canvas.draw_colored_polygon(triangle, Color(tint.r, tint.g, tint.b, 0.44 * fade))
		triangle.append(triangle[0])
		canvas.draw_polyline(triangle, Color(1, 1, 1, 0.80 * fade), 1.8, true)
	canvas.draw_circle(point, 8.0 * fade, Color(1, 1, 1, 0.90 * fade))
	canvas.draw_arc(point, 18.0 + 40.0 * t, 0.0, TAU, 28, Color(color.r, color.g, color.b, 0.45 * fade), 1.2, true)


func _draw_fx_ink(canvas: Control, point: Vector2, color: Color, age: float, sparks: Array) -> void:
	# 墨滴式：低多边形飞溅，安静但有重量。
	var t := clampf(age / 0.45, 0.0, 1.0)
	var fade := 1.0 - t
	canvas.draw_circle(point, 18.0 * (1.0 - 0.6 * t), Color(color.r, color.g, color.b, 0.55 * fade))
	canvas.draw_circle(point, 10.0 * (1.0 - 0.5 * t), Color(color.r, color.g, color.b, 0.78 * fade))
	var count := mini(10, sparks.size())
	for i in count:
		var angle := float(sparks[i])
		var distance := (10.0 + 80.0 * t) * (0.35 + 0.65 * absf(sin(float(i) * 1.7)))
		var radius := (3.0 + 5.0 * absf(cos(float(i) * 2.1))) * (1.0 - t)
		canvas.draw_circle(point + Vector2(cos(angle), sin(angle)) * distance, radius, Color(color.r, color.g, color.b, 0.60 * fade))
	if not sparks.is_empty():
		var angle0 := float(sparks[0])
		canvas.draw_line(point, point + Vector2(cos(angle0), sin(angle0)) * (36.0 + 72.0 * t), Color(color.r, color.g, color.b, 0.50 * fade), 3.5 * (1.0 - t) + 0.5, true)
	canvas.draw_circle(point, 3.0 * fade, Color(1, 1, 1, 0.65 * fade))


func _draw_hud(canvas: Control, chart: Chart, t: float) -> void:
	var width := size.x
	var cx := width * 0.5
	var cy := minf(136.0, size.y * 0.20)
	var radius := minf(width * 0.32, 124.0)
	if playtest_mode:
		cy = maxf(170.0, size.y * 0.20)
		radius = minf(width * 0.18, 148.0)
	if radius < 40.0:
		return
	var start := -PI * 0.5 - PI / 6.0
	var end := -PI * 0.5 + PI / 6.0
	var third := (end - start) / 3.0
	if _video != null and _video.visible:
		canvas.draw_rect(Rect2(cx - radius - 24, cy - radius - 18, radius * 2.0 + 48, radius * 1.25 + 54), Color(0, 0, 0, 0.26))
	canvas.draw_arc(Vector2(cx, cy), radius, start, end, 48, Color(0, 0, 0, 0.55), 30.0, true)
	for i in 3:
		var seg_start := start + third * float(i)
		var seg_end := seg_start + third
		canvas.draw_arc(Vector2(cx, cy), radius, seg_start, seg_end, 24, Color(1, 1, 1, 0.06), 24.0, true)
	var progress := clampf(t / maxf(1.0, chart.duration_beats()), 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, start, start + third * progress, 24, UITheme.INK, 24.0, true)
	if hud_rating != "—" and not hud_rating.is_empty():
		canvas.draw_arc(Vector2(cx, cy), radius, start + third, start + third * 2.0, 24, UITheme.GOLD, 24.0, true)
	var accuracy_ratio := 0.5 if hud_accuracy < 0.0 else clampf(hud_accuracy / 100.0, 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, end - third, end - third + third * accuracy_ratio, 24, UITheme.CYAN, 24.0, true)
	var font := UITheme.bold_font()
	var mono := UITheme.mono_font()
	canvas.draw_string(font, Vector2(cx - radius * 0.68, cy - radius * 0.52), "进度", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.INK)
	canvas.draw_string(font, Vector2(cx - 18, cy - radius * 0.52), hud_rating, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.INK)
	canvas.draw_string(font, Vector2(cx + radius * 0.48, cy - radius * 0.52), "准度", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.CYAN)
	canvas.draw_string(mono, Vector2(cx - radius * 0.68, cy - radius * 0.32), "%d%%" % roundi(progress * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.INK)
	canvas.draw_string(mono, Vector2(cx + radius * 0.48, cy - radius * 0.32), "—" if hud_accuracy < 0.0 else "%.2f%%" % hud_accuracy, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.INK)
	var baseline_y := cy + radius * 0.44
	var tick_left := cx - radius * 0.80
	var tick_right := cx + radius * 0.80
	canvas.draw_line(Vector2(tick_left, baseline_y), Vector2(tick_right, baseline_y), Color(1, 1, 1, 0.16), 1.0, true)
	for i in 20:
		var x := lerpf(tick_left, tick_right, float(i) / 19.0)
		var error := 0.0
		if i < hud_errors.size():
			error = hud_errors[hud_errors.size() - 1 - i]
		var length := 4.0 + minf(12.0, absf(error) / 32.0 * 12.0) if i < hud_errors.size() else 3.0
		var color := Color(1, 1, 1, 0.14)
		if i < hud_errors.size():
			color = UITheme.CYAN if error < 0.0 else UITheme.CORAL
		canvas.draw_line(Vector2(x, baseline_y - 2.0), Vector2(x, baseline_y - 2.0 - length), color, 2.0, true)
	canvas.draw_string(mono, Vector2(cx - 34, baseline_y + 20), "预览 / 非正式", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.MUTED)


func _draw_debug(canvas: Control, chart: Chart, t: float) -> void:
	var rect := Rect2(10, 10, 238, 82)
	canvas.draw_rect(rect, Color(0, 0, 0, 0.58))
	canvas.draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.35), false, 1.0)
	var mono := UITheme.mono_font()
	canvas.draw_string(mono, Vector2(18, 28), "u %.2f°  |  beat %.2f" % [cursor_u * 360.0, t], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.INK)
	canvas.draw_string(mono, Vector2(18, 44), "time %.0f ms  |  %s" % [chart.timing.beat_to_chart_ms(t), "有效" if cursor_valid else "无位置"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 60), "shape %s  |  zoom %.2f" % [chart.default_shape_id, float(current_view().get("zoom", 1.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 76), "branch 0  |  D %.0f ms ×%.2f  |  %d fps" % [chart.pre_read_ms, flow_scale, Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	for i in 12:
		var u := float(i) / 12.0
		var p := project_u(u, t)
		if _valid_point(p):
			canvas.draw_string(mono, p + Vector2(4, -4), "%d°" % (i * 30), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.42))


func _draw_dashed_polyline(canvas: Control, points: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	var segments := PackedVector2Array()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.01:
			continue
		var direction := (b - a) / length
		var cursor := 0.0
		while cursor < length:
			var segment_end := minf(cursor + dash, length)
			segments.append(a + direction * cursor)
			segments.append(a + direction * segment_end)
			cursor += dash * 2.0
	if segments.size() > 1:
		canvas.draw_multiline(segments, color, width)


func _polyline_sample(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := clampf(fraction, 0.0, 1.0) * total
	var cursor := 0.0
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if cursor + segment >= target and segment > 0.01:
			var p := (target - cursor) / segment
			return {"point": points[i].lerp(points[i + 1], p), "direction": points[i + 1] - points[i]}
		cursor += segment
	return {"point": points[-1], "direction": points[-1] - points[-2] if points.size() > 1 else Vector2.ZERO}


func _draw_arrowhead(canvas: Control, point: Vector2, direction: Vector2, color: Color) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		point + dir * 7.0,
		point - dir * 5.0 + normal * 5.0,
		point - dir * 5.0 - normal * 5.0,
	])
	canvas.draw_colored_polygon(points, color)


func _draw_chevron(canvas: Control, point: Vector2, direction: Vector2, color: Color, size: float) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var tip := point + dir * size * 0.12
	var left := point - dir * size + normal * size * 0.80
	var right := point - dir * size - normal * size * 0.80
	# 一条粗 V 形 polyline：比三层描边少 2/3 draw call，也不产生多边形三角化失败。
	canvas.draw_polyline(PackedVector2Array([left, tip, right]), color, maxf(2.0, size * 0.52), true)


func _draw_star(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(point + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	canvas.draw_polyline(points, color, 2.0, true)
	canvas.draw_circle(point, 2.0, color)


func _draw_ring(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	canvas.draw_arc(point, radius, 0.0, TAU, 28, color, 2.0, true)
	canvas.draw_circle(point, 1.8, color)


func _draw_hexagon(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 6:
		var angle := -PI * 0.5 + TAU * float(i) / 6.0
		points.append(point + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_circle(point, radius + 3.0, Color(0, 0, 0, 0.62))
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, Color(1, 1, 1, 0.96), 2.6, true)
	canvas.draw_circle(point, radius * 0.34, UITheme.BG)
	canvas.draw_circle(point, radius * 0.20, Color(1, 1, 1, 0.9))


func _draw_badge(canvas: Control, text: String, position: Vector2, color: Color) -> void:
	var font := UITheme.bold_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var rect := Rect2(position + Vector2(-text_size.x * 0.5 - 5, -12), Vector2(text_size.x + 10, 16))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.72))
	canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.85), false, 1.0)
	canvas.draw_string(font, position + Vector2(-text_size.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_label(canvas: Control, text: String, position: Vector2, color: Color) -> void:
	var font := UITheme.mono_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	var rect := Rect2(position + Vector2(-3, -9), Vector2(text_size.x + 6, 12))
	canvas.draw_rect(rect, Color(0, 0, 0, 0.38))
	canvas.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(color.r, color.g, color.b, 0.95))


func _draw_target_arc(canvas: Control, angle: float, width: float, beat: float, color: Color, thickness: float) -> void:
	thickness *= _note_scale()
	var points := _arc_points(angle, width, beat, 36)
	if points.size() < 2:
		return
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.22), thickness, true)
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.88), 2.0, true)


func _arc_points(angle: float, width: float, beat: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_width := clampf(width, 0.1, 360.0)
	var count := maxi(steps, 4)
	for i in count + 1:
		var a := angle - safe_width * 0.5 + safe_width * float(i) / float(count)
		var p := project_u(fposmod(a, 360.0) / 360.0, beat)
		if _valid_point(p):
			points.append(p)
	return points


func _draw_marker(canvas: Control, point: Vector2, color: Color, radius: float) -> void:
	if not _valid_point(point):
		return
	var center := project_design(Vector2.ZERO)
	canvas.draw_line(center, point, Color(color.r, color.g, color.b, 0.16), 2.0, true)
	canvas.draw_circle(point, radius, color)
	canvas.draw_circle(point, maxf(2.0, radius * 0.35), UITheme.INK)


func _draw_diamond(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	if not _valid_point(point):
		return
	var points := PackedVector2Array([
		point + Vector2(0, -radius),
		point + Vector2(radius, 0),
		point + Vector2(0, radius),
		point + Vector2(-radius, 0),
	])
	points.append(points[0])
	canvas.draw_polyline(points, Color(0, 0, 0, 0.66), 5.0, true)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.94), 3.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], points[3]]), Color(color.r, color.g, color.b, 0.32))
	canvas.draw_polyline(points, color, 1.7, true)
	canvas.draw_circle(point, maxf(2.0, radius * 0.26), Color(0, 0, 0, 0.68))
	canvas.draw_circle(point, maxf(1.2, radius * 0.14), Color(1, 1, 1, 0.92))


func _draw_bell(canvas: Control, point: Vector2, radius: float, t: float, target: float, pre: float) -> void:
	var q := clampf((t - (target - pre)) / maxf(0.001, pre), 0.0, 1.0)
	var r := maxf(10.0, radius * 1.35) * lerpf(0.65, 1.0, q)
	var p := project_design(Vector2.ZERO).lerp(point, q)
	canvas.draw_circle(p, r + 3.0, Color(0, 0, 0, 0.55))
	canvas.draw_circle(p, r + 24.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.10))
	canvas.draw_circle(p, r, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.20))
	canvas.draw_arc(p, r, 0.0, TAU, 32, Color(1, 1, 1, 0.92), 2.4, true)
	canvas.draw_arc(p, r * 0.82, 0.0, TAU, 28, UITheme.GOLD, 1.6, true)
	canvas.draw_circle(p, r * 0.55, UITheme.GOLD)
	canvas.draw_circle(p, r * 0.20, UITheme.INK)
	canvas.draw_arc(p, r * 0.55, -PI * 0.85, -PI * 0.25, 16, Color(1, 1, 1, 0.55), 1.3, true)
	# Bell 吸附：鼠标靠近时显示收缩环 + 四向吸点。
	var snap := maxf(96.0, r)
	if mouse_inside:
		var distance := mouse_screen.distance_to(p)
		if distance <= snap * 1.7:
			var pull := clampf(1.0 - distance / snap, 0.0, 1.0)
			canvas.draw_arc(p, snap, 0.0, TAU, 48, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.08 + 0.20 * pull), 1.2 + 1.4 * pull, true)
			var ring := lerpf(snap, r + 4.0, pull)
			canvas.draw_arc(p, ring, 0.0, TAU, 36, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45 + 0.45 * pull), 2.2, true)
			canvas.draw_arc(p, ring + 5.0, 0.0, TAU, 36, Color(1, 1, 1, 0.18 + 0.30 * pull), 1.0, true)
			for i in 4:
				var a := t * TAU * 1.5 + float(i) * TAU / 4.0
				var spark := p + Vector2(cos(a), sin(a)) * lerpf(snap * 0.95, r * 0.72, pull)
				canvas.draw_circle(spark, 1.6 + 1.4 * pull, Color(1, 1, 1, 0.55 + 0.35 * pull))
				canvas.draw_circle(spark, 3.2 + 2.0 * pull, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.16 + 0.20 * pull))


func bell_screen(note: Note, beat: float) -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return {}
	var data := _boundary_point(chart, note.center_u, beat)
	if bool(data.get("gap", false)):
		return {}
	var design: Vector2 = data.point
	var center := project_design(design)
	if not _valid_point(center):
		return {}
	return {"center": center, "radius": _design_radius_to_screen(design, note.radius)}


func _design_radius_to_screen(point: Vector2, radius: float) -> float:
	var p1 := project_design(point)
	var p2 := project_design(Vector2(point.x + radius, point.y))
	if not _valid_point(p1) or not _valid_point(p2):
		return radius
	return p1.distance_to(p2)


func _trace_position(note: Note, t: float) -> Vector2:
	var points := trace_screen_points(note, t)
	if points.size() < 2:
		return Vector2(INF, INF)
	var total := note.duration()
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
	var move_total := maxf(0.001, total - wait)
	var target := clampf((t - note.beat - wait) * star_speed / move_total * total, 0.0, total)
	for i in range(1, points.size()):
		var db := float(note.trace_pts[i].get("db", 0.0))
		if target <= db:
			var previous_db := float(note.trace_pts[i - 1].get("db", 0.0))
			var p := clampf((target - previous_db) / maxf(0.001, db - previous_db), 0.0, 1.0)
			return points[i - 1].lerp(points[i], p)
	return points[-1]


func _notes_in_range(chart: Chart, from_beat: float, to_beat: float) -> Array[Note]:
	if _sorted_notes_chart != chart or _sorted_notes_cache.size() != chart.notes.size():
		_sorted_notes_chart = chart
		_sorted_notes_cache = chart.notes.duplicate()
		_sorted_notes_cache.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	var low := 0
	var high := _sorted_notes_cache.size()
	while low < high:
		var mid := (low + high) / 2
		if _sorted_notes_cache[mid].beat < from_beat:
			low = mid + 1
		else:
			high = mid
	var result: Array[Note] = []
	for i in range(low, _sorted_notes_cache.size()):
		if _sorted_notes_cache[i].beat > to_beat:
			break
		result.append(_sorted_notes_cache[i])
	return result


func _note_scale() -> float:
	# 以 330px 设计半径为 1.0；编辑器小预览和试玩大环保持相同相对大小。
	var base := _avg_radius_cache
	if base < 40.0:
		base = 300.0
	return clampf(base / 330.0, 0.55, 1.7)


func _valid_point(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x < 1.0e9 and point.y < 1.0e9
