class_name Preview3D
extends Control

signal cursor_changed(u: float, valid: bool)
signal notice(message: String, level: String)

const RING_WIDTH := 4.0
const GLOW_WIDTH := 18.0
const PREVIEW_MARGIN := 1.24
const MOUSE_TILT_DEGREES := 11.0

var chart_override: Chart = null
var follow_app: bool = true
var time_beat: float = 0.0
var playing: bool = false
var interactive: bool = true
var playtest_mode: bool = false
var show_hud: bool = true
var show_debug: bool = false
var flow_scale: float = 1.0
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
var _overlay: Control
var _ring_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _stage_material: StandardMaterial3D
var _bezel_material: StandardMaterial3D
var _shadow_material: StandardMaterial3D
var _disc_material: StandardMaterial3D
var _beams_material: StandardMaterial3D
var _frame_material: StandardMaterial3D

var _last_mesh_beat: float = -9999.0
var _mesh_dirty: bool = true
var _last_chart_ref: Chart = null
var _last_video_path: String = ""
var _video_load_failed: bool = false
var _last_cursor_emit: Vector2 = Vector2(-999, -999)
var _last_view_key: String = ""
var _last_fit_key: String = ""
var _last_mesh_key: String = ""
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
	_frame_material.albedo_color = Color(0.82, 0.68, 0.42, 0.62)
	_frame_material.render_priority = 3

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
	_stage_mesh = MeshInstance3D.new()
	_ring_root.add_child(_stage_mesh)
	_build_stage()
	_bezel_mesh = MeshInstance3D.new()
	_ring_root.add_child(_bezel_mesh)
	_build_bezel_gpu()
	_frame_mesh = MeshInstance3D.new()
	_ring_root.add_child(_frame_mesh)
	_build_frame()
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
	var t := get_time_beat()
	var time_changed := absf(t - _last_process_time) > 0.0005
	var mesh_key := _mesh_key(chart, t)
	var view_changed := _update_transform(t)
	var flat_dirty := _mesh_dirty and not use_3d_ring
	if use_3d_ring and (_mesh_dirty or mesh_key != _last_mesh_key):
		_update_ring_mesh(chart, t)
		_last_mesh_key = mesh_key
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
			parts.append("%s:m:%d" % [event.id, roundi(beat * 20.0)])
		elif event.end_behavior == "hold":
			parts.append("%s:h" % event.id)
		elif beat <= event.end_beat + event.restore_duration:
			parts.append("%s:r:%d" % [event.id, roundi(beat * 20.0)])
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
		var amount := 5.0 if playtest_mode else MOUSE_TILT_DEGREES
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
	var key := "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [rotation, tilt_x, tilt_y, zoom, ellipse, _tilt.x, _tilt.y]
	if key == _last_view_key:
		return false
	_last_view_key = key
	var basis := Basis(Vector3(0, 0, 1), deg_to_rad(rotation))
	basis = basis * Basis(Vector3(1, 0, 0), deg_to_rad(tilt_x + _tilt.x))
	basis = basis * Basis(Vector3(0, 1, 0), deg_to_rad(tilt_y + _tilt.y))
	_ring_root.transform = Transform3D(basis.scaled(Vector3(zoom * ellipse, zoom, zoom)), Vector3(-_tilt.y * 2.8, -_tilt.x * 2.8, 0.0))
	var fit_key := "%.3f|%.3f|%.0f|%.0f" % [zoom, ellipse, size.x, size.y]
	if fit_key != _last_fit_key:
		_last_fit_key = fit_key
		_update_camera_fit(chart, zoom, ellipse)
	return true


func _update_camera_fit(chart: Chart, zoom: float, ellipse: float) -> void:
	var max_radius := 520.0
	for shape in chart.sorted_shapes():
		for i in 32:
			var u := float(i) / 32.0
			var data := shape.point_at(u)
			var point: Vector2 = data.point
			max_radius = maxf(max_radius, point.length())
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	var wanted := max_radius * maxf(0.5, zoom) * maxf(0.5, ellipse) * PREVIEW_MARGIN
	var distance := wanted / tan(deg_to_rad(_camera.fov * 0.5)) / minf(1.0, aspect)
	distance = clampf(distance, 500.0, 6000.0)
	_camera.position = Vector3(0, 0, distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _update_ring_mesh(chart: Chart, beat: float) -> void:
	var points := BoundaryRuntime.eval_shape(chart, beat, 256)
	_ring_mesh.mesh = _build_ribbon(points, RING_WIDTH, _ring_material)
	_glow_mesh.mesh = _build_ribbon(points, GLOW_WIDTH, _glow_material)
	_shadow_mesh.mesh = _build_ribbon(points, 30.0, _shadow_material)
	_last_mesh_beat = beat
	_mesh_dirty = false


func _build_beams() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _beams_material)
	for i in 8:
		var angle := TAU * float(i) / 8.0 + TAU / 16.0
		var direction := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-direction.y, direction.x)
		var near := direction * 170.0
		var far := direction * 620.0
		var near_half := normal * 12.0
		var far_half := normal * 34.0
		mesh.surface_add_vertex(Vector3(near.x + near_half.x, near.y + near_half.y, -32.0))
		mesh.surface_add_vertex(Vector3(near.x - near_half.x, near.y - near_half.y, -32.0))
		mesh.surface_add_vertex(Vector3(far.x - far_half.x, far.y - far_half.y, -32.0))
		mesh.surface_add_vertex(Vector3(near.x + near_half.x, near.y + near_half.y, -32.0))
		mesh.surface_add_vertex(Vector3(far.x - far_half.x, far.y - far_half.y, -32.0))
		mesh.surface_add_vertex(Vector3(far.x + far_half.x, far.y + far_half.y, -32.0))
	mesh.surface_end()
	_beams_mesh.mesh = mesh


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
	for radius in [385.0, 425.0, 455.0, 600.0]:
		var steps := 96
		for i in steps:
			var a0 := TAU * float(i) / float(steps)
			var a1 := TAU * float(i + 1) / float(steps)
			mesh.surface_add_vertex(Vector3(cos(a0) * radius, sin(a0) * radius, -30.0))
			mesh.surface_add_vertex(Vector3(cos(a1) * radius, sin(a1) * radius, -30.0))
	for i in 8:
		var a := TAU * float(i) / 8.0 + TAU / 16.0
		mesh.surface_add_vertex(Vector3(cos(a) * 170.0, sin(a) * 170.0, -30.0))
		mesh.surface_add_vertex(Vector3(cos(a) * 620.0, sin(a) * 620.0, -30.0))
	mesh.surface_end()
	_stage_mesh.mesh = mesh


func _build_frame() -> void:
	var points: Array[Dictionary] = []
	for i in 8:
		var angle := TAU * float(i) / 8.0 + TAU / 16.0
		points.append({"point": Vector2(cos(angle), sin(angle)) * 505.0, "gap": false})
	_frame_mesh.mesh = _build_ribbon(points, 2.2, _frame_material)


func _build_bezel_gpu() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _bezel_material)
	for i in 24:
		var a := TAU * float(i) / 24.0
		var r0 := 466.0
		var r1 := 484.0 if i % 6 == 0 else 474.0
		mesh.surface_add_vertex(Vector3(cos(a) * r0, sin(a) * r0, 0.0))
		mesh.surface_add_vertex(Vector3(cos(a) * r1, sin(a) * r1, 0.0))
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var p := Vector2(cos(a), sin(a)) * 510.0
		mesh.surface_add_vertex(Vector3(p.x - 6.0, p.y, 0.0))
		mesh.surface_add_vertex(Vector3(p.x + 6.0, p.y, 0.0))
		mesh.surface_add_vertex(Vector3(p.x, p.y - 6.0, 0.0))
		mesh.surface_add_vertex(Vector3(p.x, p.y + 6.0, 0.0))
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
	_mesh_dirty = true
	_last_video_path = ""
	_last_background_path = ""
	_last_fit_key = ""
	_last_mesh_key = ""
	_force_3d_frame = true
	queue_redraw()


func _on_chart_live_changed() -> void:
	_mesh_dirty = true
	_last_fit_key = ""
	_last_mesh_key = ""
	_force_3d_frame = true
	queue_redraw()


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
			var point: Dictionary = _drag_visual_note.visual_pts[visual]
			_drag_visual_db = float(point.get("db", 0.0))
			_drag_visual_da = float(point.get("da", 0.0))
			_app.begin_edit()
			return
	if _app.tool in ["tap", "hold", "path", "anchor", "bell"]:
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
	if _drag_visual_note == null or _drag_visual < 0 or _drag_visual >= _drag_visual_note.visual_pts.size():
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	var point: Dictionary = _drag_visual_note.visual_pts[_drag_visual]
	var duration := _drag_visual_note.duration()
	point["db"] = clampf(_drag_visual_db + (screen_position.y - _drag_visual_start.y) / 36.0, 0.001, maxf(0.001, duration - 0.001))
	var angle := rad_to_deg(atan2(design.y, design.x))
	point["da"] = JudgeMath.angle_delta(_drag_visual_note.angle, angle)
	_app.touch_chart()


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


func _create_note(type: String) -> void:
	if _app == null or not cursor_valid:
		return
	var chart := get_chart()
	if chart == null:
		return
	var beat: float = _app.snap_beat(get_time_beat())
	var angle := fposmod(cursor_u * 360.0, 360.0)
	var note := Note.new(type, beat, angle, 60.0)
	note.id = chart.next_note_id()
	match type:
		"hold":
			note.end_beat = beat + 1.0
			note.hold = true
		"path":
			note.end_beat = beat + 1.0
			note.tail_angle = fposmod(angle + 90.0, 360.0)
			note.tail_width = 45.0
			note.tolerance = 0.24
			note.samples_per_beat = 4.0
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
	var result := BoundaryRuntime.nearest_u(chart, t, mouse_screen, func(point: Vector2) -> Vector2: return project_design(point), 96)
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
	if not mouse_inside and not playtest_mode:
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


func project_u(u: float, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	var data := BoundaryRuntime.eval_point(chart, u, beat)
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


func trace_screen_points(note: Note, beat: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var chart := get_chart()
	for point in note.trace_pts:
		var x := float(point.get("x", 0.0))
		var y := float(point.get("y", 0.0))
		if note.trace_style == "slider" and chart != null:
			var radius := minf(1.0, sqrt(x * x + y * y))
			var angle := fposmod(rad_to_deg(atan2(y, x)), 360.0)
			var data := BoundaryRuntime.eval_point(chart, angle / 360.0, beat)
			if bool(data.get("gap", false)):
				continue
			points.append(project_design((data.point as Vector2) * radius))
		else:
			points.append(Vector2(x * size.x, y * size.y))
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
	_draw_paths(canvas, chart, t, pre)
	_draw_holds(canvas, chart, t, pre)
	_draw_notes(canvas, chart, t, pre)
	_draw_traces(canvas, chart, t)
	_draw_boundary_controls(canvas, chart)
	_draw_cursor(canvas, chart, t)
	if show_hud:
		_draw_hud(canvas, chart, t)
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
	for radius in [385.0, 600.0]:
		var points := PackedVector2Array()
		for i in 49:
			var a := TAU * float(i) / 48.0
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(0.56, 0.62, 0.72, 0.08), 1.0, true)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var p0 := _affine_point(Vector2(cos(a), sin(a)) * 150.0, affine)
		var p1 := _affine_point(Vector2(cos(a), sin(a)) * 620.0, affine)
		canvas.draw_line(p0, p1, Color(0.56, 0.62, 0.72, 0.045), 1.0, true)


func _draw_flat_ring(canvas: Control, chart: Chart, t: float) -> void:
	var points := BoundaryRuntime.eval_shape(chart, t, 192)
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
	for radius in [425.0, 455.0]:
		var points := PackedVector2Array()
		for i in 65:
			var angle := TAU * float(i) / 64.0
			points.append(_affine_point(Vector2(cos(angle), sin(angle)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(1, 1, 1, 0.13), 1.0, true)
	var arc := PackedVector2Array()
	for i in 33:
		var angle := deg_to_rad(lerpf(-160.0, -20.0, float(i) / 32.0))
		arc.append(_affine_point(Vector2(cos(angle), sin(angle)) * 478.0, affine))
	if arc.size() > 1:
		canvas.draw_polyline(arc, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.72), 2.0, true)
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var a := _affine_point(Vector2(cos(angle), sin(angle)) * 466.0, affine)
		var b := _affine_point(Vector2(cos(angle), sin(angle)) * (482.0 if i % 6 == 0 else 474.0), affine)
		canvas.draw_line(a, b, Color(1, 1, 1, 0.26 if i % 6 == 0 else 0.12), 1.0, true)
	for i in 4:
		var angle := TAU * (float(i) + 0.5) / 4.0
		var p := _affine_point(Vector2(cos(angle), sin(angle)) * 505.0, affine)
		canvas.draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(1, 1, 1, 0.20), 1.0, true)
		canvas.draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(1, 1, 1, 0.20), 1.0, true)
	var marker := _affine_point(Vector2(0, 505), affine)
	var d := PackedVector2Array([marker + Vector2(0, -5), marker + Vector2(5, 0), marker + Vector2(0, 5), marker + Vector2(-5, 0), marker + Vector2(0, -5)])
	canvas.draw_polyline(d, Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.8), 1.5, true)


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
	var data := BoundaryRuntime.eval_point(get_chart(), fposmod(angle, 360.0) / 360.0, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * scale)


func _pick_visual_node(screen_position: Vector2) -> int:
	if _app == null:
		return -1
	var note: Note = _app.get_selected_note()
	if note == null or not note.type in ["path", "hold"]:
		return -1
	if note.type == "path" and note.path_style == "star":
		return -1
	var chart := get_chart()
	if chart == null:
		return -1
	var t := get_time_beat()
	for i in note.visual_pts.size():
		var point: Dictionary = note.visual_pts[i]
		var p: Vector2
		if note.type == "hold":
			p = _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
		else:
			p = _path_screen_point(chart, note, float(point.get("db", 0.0)), t)
		if _valid_point(p) and p.distance_to(screen_position) <= 12.0:
			return i
	return -1


func _draw_paths(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var visible: Array = []
	for note in chart.notes:
		if note.type == "path" and t >= note.beat - pre and t <= note.end_beat + 0.5:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	for i in visible.size():
		_draw_one_path(canvas, chart, visible[i], t, pre, i == visible.size() - 1)


func _draw_one_path(canvas: Control, chart: Chart, note: Note, t: float, pre: float, top: bool) -> void:
	var total := note.duration()
	if total <= 0.001:
		return
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	var count := 80
	var last_valid := Vector2(INF, INF)
	for i in count + 1:
		var rel := total * float(i) / float(count)
		var erased := note.erased_at(rel)
		var p := _path_screen_point(chart, note, rel, t)
		if erased or not _valid_point(p):
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			last_valid = Vector2(INF, INF)
			continue
		# 跳区不连线：断开处直接起新的一段，避免画出跨过擦除区的假轨迹。
		if last_valid.x < 1.0e9 and p.distance_to(last_valid) > 64.0:
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
		run.append(p)
		last_valid = p
	if run.size() > 1:
		runs.append(run)
	var body := Color(0.78, 0.80, 0.79, 0.62 if top else 0.22)
	var dash := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.92 if top else 0.34)
	var arrow := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.95 if top else 0.34)
	for piece in runs:
		if piece.size() < 2:
			continue
		if top:
			var shadow := PackedVector2Array()
			for p in piece:
				shadow.append(p + Vector2(6, 8))
			canvas.draw_polyline(shadow, Color(0, 0, 0, 0.45), 26.0, true)
		canvas.draw_polyline(piece, Color(0, 0, 0, 0.55), 24.0, true)
		canvas.draw_polyline(piece, Color(1, 1, 1, 0.20 if top else 0.07), 20.0, true)
		canvas.draw_polyline(piece, body, 17.0, true)
		canvas.draw_polyline(piece, Color(1, 1, 1, 0.12 if top else 0.04), 11.0, true)
		_draw_dashed_polyline(canvas, piece, dash, 2.0, 6.0)
		var arrow_count := clampi(int(total * 1.5), 2, 5)
		for k in arrow_count:
			var fraction := (float(k) + 1.0) / float(arrow_count + 1)
			var sample: Dictionary = _polyline_sample(piece, fraction)
			_draw_arrowhead(canvas, sample["point"], sample["direction"], arrow)
			var direction: Vector2 = (sample["direction"] as Vector2).normalized()
			var normal := Vector2(-direction.y, direction.x)
			var tick_point: Vector2 = sample["point"]
			canvas.draw_line(tick_point - normal * 12.0, tick_point + normal * 12.0, Color(1, 1, 1, 0.22 if top else 0.08), 1.0, true)
	var star := note.path_style == "star"
	for sample_beat in note.path_sample_beats():
		var rel := clampf(sample_beat - note.beat, 0.0, total)
		var p := _path_ring_point(chart, note, rel, t) if star else _path_screen_point(chart, note, rel, t)
		if _valid_point(p):
			canvas.draw_circle(p, 3.2, Color(0, 0, 0, 0.45))
			canvas.draw_circle(p, 2.2, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.92 if top else 0.30))
	_draw_target_arc(canvas, note.angle, note.width, t, UITheme.CORAL, 10.0)
	_draw_target_arc(canvas, note.tail_angle, note.tail_width, t, UITheme.GOLD, 8.0)
	if _app != null and note.path_style != "star":
		var selected_note: Note = _app.get_selected_note()
		if selected_note != null and selected_note.id == note.id:
			for point in note.visual_pts:
				var node := _path_screen_point(chart, note, float(point.get("db", 0.0)), t)
				if _valid_point(node):
					_draw_diamond(canvas, node, 5.0, UITheme.CYAN)
					canvas.draw_circle(node, 1.8, UITheme.INK)
	var head := _flying_position(chart, note.angle, note.beat, t, pre)
	var tail := _flying_position(chart, note.tail_angle, note.end_beat, t, pre)
	if note.path_style == "star" and _valid_point(head) and _valid_point(tail):
		canvas.draw_dashed_line(head, tail, Color(1, 1, 1, 0.16 if top else 0.07), 1.0, 5.0)
	_draw_path_head(canvas, head, top)
	_draw_path_tail(canvas, tail, top)
	if t >= note.beat and t <= note.end_beat:
		var p := _path_screen_point(chart, note, t - note.beat, t)
		if _valid_point(p):
			canvas.draw_circle(p, 7.0, UITheme.CYAN if top else Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.5))
			canvas.draw_circle(p, 2.5, UITheme.INK)


func path_distance(note: Note, relative_beat: float, beat: float, screen_point: Vector2) -> float:
	var chart := get_chart()
	if chart == null:
		return INF
	var best := INF
	for offset in [-0.06, 0.0, 0.06]:
		var rel := clampf(relative_beat + offset, 0.0, note.duration())
		var p := _path_ring_point(chart, note, rel, beat)
		if _valid_point(p):
			best = minf(best, p.distance_to(screen_point))
	return best


func _path_ring_point(chart: Chart, note: Note, relative_beat: float, t: float) -> Vector2:
	var degrees := note.path_angle_at(relative_beat)
	var data := BoundaryRuntime.eval_point(chart, fposmod(degrees, 360.0) / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design(data.point)


func _path_screen_point(chart: Chart, note: Note, relative_beat: float, t: float) -> Vector2:
	var local := note.path_local_at(relative_beat)
	var radius := local.length()
	if radius <= 0.0001:
		return project_design(Vector2.ZERO)
	var degrees := fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
	var data := BoundaryRuntime.eval_point(chart, degrees / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * radius)


func _draw_path_head(canvas: Control, point: Vector2, top: bool) -> void:
	if not _valid_point(point):
		return
	var alpha := 1.0 if top else 0.45
	canvas.draw_circle(point, 22.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.16 * alpha))
	_draw_star_filled(canvas, point, 12.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, alpha))


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


func _draw_path_tail(canvas: Control, point: Vector2, top: bool) -> void:
	if not _valid_point(point):
		return
	var alpha := 1.0 if top else 0.45
	canvas.draw_circle(point, 18.0, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.14 * alpha))
	canvas.draw_circle(point, 15.0, Color(0, 0, 0, 0.64 * alpha))
	canvas.draw_circle(point, 12.5, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, alpha))
	canvas.draw_circle(point, 6.2, Color(0, 0, 0, 0.82 * alpha))
	canvas.draw_arc(point, 9.0, 0.0, TAU, 28, Color(1, 1, 1, 0.88 * alpha), 1.6, true)
	canvas.draw_circle(point, 2.0, Color(1, 1, 1, 0.9 * alpha))


func _hold_node_screen(chart: Chart, note: Note, relative_beat: float, relative_angle: float, t: float) -> Vector2:
	var duration := maxf(0.001, note.duration())
	var q := clampf(relative_beat / duration, 0.0, 1.0)
	var angle := fposmod(note.angle + relative_angle, 360.0)
	var data := BoundaryRuntime.eval_point(chart, angle / 360.0, t)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	var center := project_design(Vector2.ZERO)
	var boundary := project_design(data.point)
	return center.lerp(boundary, 0.25).lerp(boundary, q)


func _draw_holds(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	for note in chart.notes:
		if note.type != "hold":
			continue
		if t < note.beat - pre or t > note.end_beat + 0.3:
			continue
		var u := fposmod(note.angle, 360.0) / 360.0
		var boundary := project_u(u, t)
		if not _valid_point(boundary):
			continue
		var center := project_design(Vector2.ZERO)
		var body := PackedVector2Array([center.lerp(boundary, 0.25)])
		var visuals := note.visual_pts.duplicate()
		visuals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("db", 0.0)) < float(b.get("db", 0.0)))
		for point in visuals:
			var node := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
			if _valid_point(node):
				body.append(node)
		body.append(boundary)
		var shadow := PackedVector2Array()
		for p in body:
			shadow.append(p + Vector2(5, 7))
		canvas.draw_polyline(shadow, Color(0, 0, 0, 0.44), 24.0, true)
		canvas.draw_polyline(body, Color(0, 0, 0, 0.62), 20.0, true)
		canvas.draw_polyline(body, Color(1, 1, 1, 0.92), 15.0, true)
		canvas.draw_polyline(body, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.88), 10.0, true)
		canvas.draw_polyline(body, Color(1, 1, 0.9, 0.34), 2.6, true)
		_draw_target_arc(canvas, note.angle, note.width, t, UITheme.AMBER, 12.0)
		var head := _flying_position(chart, note.angle, note.beat, t, pre)
		_draw_hexagon(canvas, head, 11.0, UITheme.AMBER)
		if _app != null:
			var selected_note: Note = _app.get_selected_note()
			if selected_note != null and selected_note.id == note.id:
				for point in visuals:
					var node := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
					if _valid_point(node):
						_draw_diamond(canvas, node, 5.0, UITheme.CYAN)
						canvas.draw_circle(node, 1.8, UITheme.INK)
		if t >= note.beat and t <= note.end_beat:
			var glow := 0.5 + 0.5 * sin(t * PI)
			canvas.draw_arc(boundary, 18.0, 0.0, TAU, 32, Color(UITheme.AMBER.r, UITheme.AMBER.g, UITheme.AMBER.b, 0.28 * glow), 2.0, true)


func _draw_notes(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	for note in chart.notes:
		if note.type in ["path", "hold", "trace"]:
			continue
		if t < note.beat - pre or t > note.beat + 0.3:
			continue
		match note.type:
			"tap":
				_draw_tap_note(canvas, chart, note, t, pre)
			"anchor":
				var p := _flying_position(chart, note.angle, note.beat, t, pre)
				if _valid_point(p):
					canvas.draw_circle(p, 18.0, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.14))
				_draw_diamond(canvas, p, 11.0, UITheme.VIOLET)
			"bell":
				var bell := bell_screen(note, t)
				if not bell.is_empty():
					_draw_bell(canvas, bell["center"], bell["radius"], t, note.beat, pre)


func _draw_tap_note(canvas: Control, chart: Chart, note: Note, t: float, pre: float) -> void:
	var width := maxf(note.width, 6.0)
	var steps := clampi(int(width / 5.0), 8, 96)
	var q := clampf((t - (note.beat - pre)) / maxf(0.001, pre), 0.0, 1.0)
	var center := project_design(Vector2.ZERO)
	var points := PackedVector2Array()
	for i in steps + 1:
		var angle := note.angle - width * 0.5 + width * float(i) / float(steps)
		var data := BoundaryRuntime.eval_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var p := project_design(data.point * q)
		if _valid_point(p):
			points.append(p)
	var target_points := PackedVector2Array()
	for i in steps + 1:
		var angle := note.angle - width * 0.5 + width * float(i) / float(steps)
		var p := project_u(fposmod(angle, 360.0) / 360.0, t)
		if _valid_point(p):
			target_points.append(p)
	if target_points.size() > 1:
		canvas.draw_polyline(target_points, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.16), 9.0, true)
	if points.size() < 2:
		return
	var shadow := PackedVector2Array()
	for p in points:
		shadow.append(p + Vector2(5, 7))
	canvas.draw_polyline(shadow, Color(0, 0, 0, 0.42), 26.0, true)
	canvas.draw_polyline(points, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.10), 26.0, true)
	canvas.draw_polyline(points, Color(0, 0, 0, 0.68), 19.0, true)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.94), 14.0, true)
	canvas.draw_polyline(points, UITheme.CORAL, 9.5, true)
	canvas.draw_polyline(points, Color(1, 1, 0.94, 0.38), 2.6, true)
	for cap in [points[0], points[-1]]:
		canvas.draw_circle(cap, 7.0, Color(0, 0, 0, 0.65))
		canvas.draw_circle(cap, 5.4, Color(1, 1, 1, 0.95))
		canvas.draw_circle(cap, 3.6, UITheme.CORAL)
	var center_data := BoundaryRuntime.eval_point(chart, fposmod(note.angle, 360.0) / 360.0, t)
	if not bool(center_data.get("gap", false)):
		var c := project_design(center_data.point * q)
		canvas.draw_line(c, center.lerp(c, 0.84), UITheme.INK, 2.0, true)
		canvas.draw_circle(c, 2.0, UITheme.INK)


func _draw_traces(canvas: Control, chart: Chart, t: float) -> void:
	var pre := _pre_read_beats(chart, t)
	for note in chart.notes:
		if note.type != "trace":
			continue
		var lead := pre if note.trace_style == "slider" else 0.5
		if t < note.beat - lead or t > note.end_beat + 0.5:
			continue
		var points := trace_screen_points(note, t)
		if points.size() > 1 and note.trace_style == "slider":
			_draw_slider_trace(canvas, note, points, t)
			continue
		if points.size() > 1:
			var duration := maxf(0.001, note.duration())
			var progress := clampf((t - note.beat) / duration, 0.0, 1.0)
			var outline := PackedVector2Array()
			for p in points:
				outline.append(p + Vector2(4, 6))
			canvas.draw_polyline(outline, Color(0, 0, 0, 0.52), 42.0, true)
			canvas.draw_polyline(points, Color(1, 1, 1, 0.14), 38.0, true)
			canvas.draw_polyline(points, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.14), 36.0, true)
			canvas.draw_polyline(points, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.30), 28.0, true)
			canvas.draw_polyline(_offset_polyline(points, 16.0), Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.62), 1.5, true)
			canvas.draw_polyline(_offset_polyline(points, -16.0), Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.62), 1.5, true)
			_draw_dashed_polyline(canvas, points, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.92), 2.0, 6.0)
			var arrow_count := 5
			for k in arrow_count:
				var fraction := (float(k) + 0.5) / float(arrow_count)
				var sample := _polyline_sample(points, fraction)
				_draw_arrowhead(canvas, sample["point"], sample["direction"], Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.95))
			var prefix := _polyline_prefix(points, progress)
			if prefix.size() > 1:
				canvas.draw_polyline(prefix, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.26), 30.0, true)
			for i in range(0, note.trace_pts.size(), maxi(1, note.trace_pts.size() / 8)):
				_draw_diamond(canvas, points[i], 3.2, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.85))
			_draw_trace_cap(canvas, points[0], true)
			_draw_trace_cap(canvas, points[-1], false)
			_draw_label(canvas, "TRACE", points[0] + Vector2(14, -14), UITheme.MINT)
		var position := _trace_position(note, t)
		if _valid_point(position):
			canvas.draw_circle(position, 16.0, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.14))
			canvas.draw_circle(position, 10.0, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.92))
			canvas.draw_circle(position, 4.0, UITheme.INK)
			canvas.draw_arc(position, 13.0, 0.0, TAU, 28, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.75), 1.5, true)
	if _drawing_trace and _trace_points.size() > 1:
		var temp := PackedVector2Array()
		for p in _trace_points:
			temp.append(p)
		canvas.draw_polyline(temp, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.7), 3.0, true)


func _draw_slider_trace(canvas: Control, note: Note, points: PackedVector2Array, t: float) -> void:
	var duration := maxf(0.001, note.duration())
	var progress := clampf((t - note.beat) / duration, 0.0, 1.0)
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(5, 7))
	canvas.draw_polyline(shadow, Color(0, 0, 0, 0.44), 24.0, true)
	canvas.draw_polyline(points, Color(0, 0, 0, 0.55), 22.0, true)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.92), 16.0, true)
	canvas.draw_polyline(points, Color(0.78, 0.80, 0.79, 0.88), 12.0, true)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.14), 6.0, true)
	_draw_dashed_polyline(canvas, points, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.90), 2.0, 6.0)
	for k in 3:
		var sample: Dictionary = _polyline_sample(points, (float(k) + 1.0) / 4.0)
		_draw_arrowhead(canvas, sample["point"], sample["direction"], UITheme.CYAN)
	var prefix := _polyline_prefix(points, progress)
	if prefix.size() > 1:
		canvas.draw_polyline(prefix, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.30), 14.0, true)
	# 星头和圆环尾都是轨迹的一部分：固定画在轨迹两端，尾部不单独飞入。
	_draw_path_head(canvas, points[0], true)
	_draw_path_tail(canvas, points[-1], true)
	var position := _trace_position(note, t)
	if _valid_point(position):
		canvas.draw_circle(position, 9.0, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.88))
		canvas.draw_circle(position, 3.2, UITheme.INK)
	if not playtest_mode:
		_draw_label(canvas, "SLIDE", points[0] + Vector2(16, -14), UITheme.CYAN)


func _draw_trace_cap(canvas: Control, point: Vector2, start: bool) -> void:
	if not _valid_point(point):
		return
	var color := Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.95)
	canvas.draw_circle(point, 8.0, Color(UITheme.MINT.r, UITheme.MINT.g, UITheme.MINT.b, 0.16))
	canvas.draw_arc(point, 7.0, 0.0, TAU, 20, color, 1.5, true)
	if start:
		canvas.draw_circle(point, 3.0, color)
	else:
		_draw_diamond(canvas, point, 4.0, color)


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


func add_hit_pulse(point: Vector2, color: Color, label: String = "HIT") -> void:
	if not _valid_point(point):
		return
	_pulses.append({"pos": point, "age": 0.0, "color": color, "label": label})
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_pulses(canvas: Control) -> void:
	for pulse in _pulses:
		var age := float(pulse.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.5, 0.0, 1.0)
		var point: Vector2 = pulse["pos"]
		var color: Color = pulse["color"]
		var radius := 12.0 + age * 70.0
		canvas.draw_arc(point, radius, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.55 * alpha), 2.0 + 2.0 * alpha, true)
		canvas.draw_circle(point, 3.0 * alpha, Color(color.r, color.g, color.b, alpha))
		canvas.draw_string(UITheme.bold_font(), point + Vector2(12, -14 - age * 26), String(pulse.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color.r, color.g, color.b, alpha))


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
	var r := maxf(6.0, radius) * lerpf(0.65, 1.0, q)
	canvas.draw_circle(point, r + 2.5, Color(0, 0, 0, 0.55))
	canvas.draw_circle(point, r, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.20))
	canvas.draw_arc(point, r, 0.0, TAU, 32, Color(1, 1, 1, 0.92), 2.4, true)
	canvas.draw_arc(point, r * 0.82, 0.0, TAU, 28, UITheme.GOLD, 1.6, true)
	canvas.draw_circle(point, r * 0.55, UITheme.GOLD)
	canvas.draw_circle(point, r * 0.20, UITheme.INK)
	canvas.draw_arc(point, r * 0.55, -PI * 0.85, -PI * 0.25, 16, Color(1, 1, 1, 0.55), 1.3, true)


func bell_screen(note: Note, beat: float) -> Dictionary:
	var chart := get_chart()
	if chart == null:
		return {}
	var data := BoundaryRuntime.eval_point(chart, note.center_u, beat)
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
	var target := clampf(t - note.beat, 0.0, total)
	for i in range(1, points.size()):
		var db := float(note.trace_pts[i].get("db", 0.0))
		if target <= db:
			var previous_db := float(note.trace_pts[i - 1].get("db", 0.0))
			var p := clampf((target - previous_db) / maxf(0.001, db - previous_db), 0.0, 1.0)
			return points[i - 1].lerp(points[i], p)
	return points[-1]


func _valid_point(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x < 1.0e9 and point.y < 1.0e9
