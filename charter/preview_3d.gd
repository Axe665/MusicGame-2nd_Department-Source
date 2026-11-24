class_name Preview3D
extends Control

signal cursor_changed(u: float, valid: bool)
signal notice(message: String, level: String)
## 环编辑工作区：滚轮缩放、拖空白旋转，由工作区写进镜头关键帧。
signal ring_zoom(delta: float)
signal ring_rotate(degrees: float)
## 环编辑：在预览里点中文本指令时通知工作区同步选择。
signal command_selected(command: AlphaCommand)

const RING_WIDTH := 4.0
const GLOW_WIDTH := 18.0
const PREVIEW_MARGIN := 1.24
## 鼠标视差的最大倾斜角（度）。试玩固定 7°，编辑器预览用这个值。
const MOUSE_TILT_DEGREES := 11.0
## Path / Trace 的视觉尺寸：相对旧版 ×2。只放大笔画与头尾，不改轨迹几何与判定。
const PATH_SIZE_SCALE := 2.0
## 金键（Bell）：环上一段白描边金键（圆头 + 金色核心 + 细金光环）。
const BELL_BAND_HALF := 10.0
## 光标离弧带（含两端）多少像素内算在场。
const BELL_RADIAL_TOLERANCE := 55.0
## 扫键串里的 Bell 放宽到这个半径，并在画面上画出同半径的淡金光圈。
const BELL_CHAIN_TOLERANCE := 75.0
## 星头单独缩小（轨迹宽度不受影响）。
const PATH_HEAD_SCALE := 0.62
## 定型参数：RDP 容差（设计坐标，环半径 1.0）、拐角保护、重采样步长与点数上限。
const PATH_SMOOTH_RDP := 0.018
const PATH_SMOOTH_CORNER_DEG := 40.0
const PATH_SMOOTH_STEP := 0.008
const PATH_SMOOTH_MAX_POINTS := 96
## 接力高亮：等待处理的星在重叠时压到这个亮度。
const PATH_RELAY_DIM := 0.45
const PATH_STYLES: Array[String] = ["tread", "ribbon"]
const CURSOR_MAIN_RADIUS := 14.0
const CURSOR_MAIN_STROKE := 2.6
## 星头球半径 = 光标主环直径 × 这个比例。
const PATH_HEAD_BALL_RATIO := 1.15
## 判定环上的 Seek 弧带厚度：和 Tap 完全一致（18，按音符缩放）。
const SEEK_BAND_WIDTH := 18.0
const SEEK_WARNING_MS := 300.0
## 就位环的显示窗口：和试玩的 Seek 判定窗口（HIT_WINDOW_MS = 200）对齐。
const SEEK_ARM_MS := 200.0
const LIMIT_INNER_SCALE := 0.68
## 命中退场：尾判后尾巴停在判定环上再淡出的真实时长（秒）。
## 用真实时间而不是拍数，慢歌不会拖成半秒、快歌也不会一闪就没。
const END_FADE_SEC := 0.1
## 松手补按窗口内的变暗程度（1 = 不变暗）。
const HOLD_SLIP_DIM := 0.35
## 命中后音符整体放大淡出的时长与最终倍数（osu!std 式击打光）。
## 从音符落在环上的实际大小起步，不再额外放大基座。
const NOTE_POP_SEC := 0.28
const NOTE_POP_SCALE := 1.5
## 命中光环（WACCA 式）：判定环外侧的一段柔光扇 + 向外飞的三角碎屑。
const RING_LIGHT_SEC := 0.25
## 同屏碎屑预算：本体碎屑和环上碎屑共用这么多组，满了只留光扇/本体。
const SHARD_GROUP_BUDGET := 6
const RING_LIGHT_SPAN := 25.0
const RING_LIGHT_INNER := 0.98
const RING_LIGHT_OUTER := 1.18

var chart_override: Chart = null
## 洋葱皮：相邻关键帧的轮廓，由环工作区填。
var onion_shapes: Array = []
var follow_app: bool = true
var time_beat: float = 0.0
var playing: bool = false
var interactive: bool = true
var playtest_mode: bool = false
var show_hud: bool = true
## 仅轨迹导出时关掉：不画音符/轨迹条/判定特效，只留背景与鼠标轨迹。
var show_notes: bool = true
## 拖形状/镜头关键帧时暂时不画音符：10k 音符重绘一次 ≈30ms，会把手感拖没。
## 松手后恢复；环、红区、小节线和洋葱皮仍然画。
var ring_drag_low_detail: bool = false
## 仅轨迹导出时关掉：不显示 3D 判定环。
var show_playfield: bool = true
var show_debug: bool = false
## Dedicated input overlay: geometry and progress come from live playtest states.
var show_path_judgement := false
var path_judgement_states: Dictionary = {}
var flow_scale: float = 1.0
## Trace 门框的主色（默认银白）。
var custom_cursor_visible: bool = true
## 光标大小倍率（1.0 = 默认）。
var cursor_scale: float = 1.0
var mouse_tilt: bool = true
## 倾斜幅度（度）；由设置页写入，0 视为关闭。
## 注入光标（回放/导出）是按哪个尺寸录的。导出视口固定 1280x720，
## 而回放录的是 1600x900 的光标，不换算的话右侧的点会被判成「跑到画面外」。
var auto_cursor_bounds: Vector2 = Vector2.ZERO
var use_3d_ring: bool = true:
	set(value):
		if use_3d_ring == value:
			return
		use_3d_ring = value
		if _viewport_container != null:
			_viewport_container.visible = value and show_playfield
		if _subviewport != null:
			_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_render_mode = SubViewport.UPDATE_DISABLED
		_force_3d_frame = value
		_mesh_dirty = true
		if _overlay != null:
			_overlay.queue_redraw()

var _app: Node = null

var hud_accuracy: float = -1.0
var hud_rating: String = "—"
var hud_errors: Array[float] = []
## 试玩 HUD：四角放数据、中心放连击、环外放进度/准度两条弧。
var hud_combo: int = 0
var hud_max_combo: int = 0
var hud_tiers: Dictionary = {}
var hud_title: String = ""
var hud_difficulty: String = ""
var hud_auto: bool = false
## HUD 选项（来自 App.hud_options()）：缩放 / 连击位置 / 进度仪表 / 判定字位置 / 档位计数 / 透明度 / 左上内容。
var hud_options: Dictionary = {}
var hud_ms: float = 0.0
var hud_total_ms: float = 0.0

var cursor_u: float = 0.0
var path_style: String = PATH_STYLES[0]
var cursor_valid: bool = false
var mouse_screen: Vector2 = Vector2.ZERO
var mouse_inside: bool = false
## AUTO 自动演示时的合成光标：有限值就盖掉真实鼠标，INF 表示用真鼠标。
var auto_cursor: Vector2 = Vector2.INF

var _bg: TextureRect
var _background_image: TextureRect
var _last_background_path: String = ""
## osu! storyboard（.osb）：按谱面缓存一次，贴图按需载入。
var _storyboard: Storyboard = null
var _storyboard_dir := ""
var _storyboard_chart: Chart = null
## 每次试玩都会新建一套 Preview3D，解析结果和贴图放类级缓存里共享：
## 3936 sprite 的 .osb 实测 parse 232ms，135 张图解码更久，重建一次就是一次卡顿。
static var _board_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
const STORYBOARD_BOARD_CACHE_LIMIT: int = 4
const STORYBOARD_TEXTURE_BUDGET: int = 128 * 1024 * 1024
const STORYBOARD_TEXTURE_ENTRY_LIMIT: int = 512
const STORYBOARD_TEXTURE_GRACE_MS: int = 2000
static var _tex_sizes: Dictionary[String, int] = {}
static var _tex_last_used: Dictionary[String, int] = {}
static var _tex_cache_bytes: int = 0
static var _tex_next_trim_ms: int = 0
static var _tex_eviction_generation: int = 0
## 解码放后台线程：135 张 2560x1440 的图同步解码 = 几秒卡死。
## 主线程只做 ImageTexture 上传（必须主线程），其余在 WorkerThreadPool 里跑。
static var _tex_pending: Dictionary = {}
## 超长边压到 1024 后，绘制时要按原尺寸放大回来，否则大背景会缩水成一半。
static var _tex_boost: Dictionary = {}
## .osb 解析也放后台：3936 sprite 的谱实测 parse 232ms，放在首帧 draw 里就是一次卡死。
static var _parse_pending: Dictionary = {}
static var _parse_done: Dictionary = {}
static var _parse_revisions: Dictionary = {}
static var _parse_mutex := Mutex.new()
static var _tex_decoded: Dictionary = {}
static var _tex_mutex := Mutex.new()
static var _tex_upload_frame: int = -1
static var _tex_generation: int = 0
## 预览最大也就屏幕那么高，超长边超过这个数只会白吃显存和解码时间。
const STORYBOARD_TEX_MAX := 1024
var show_storyboard := true
## 只画 Foreground/Overlay 层（关掉 storyboard 的背景层，让谱面背景图露出来）。
var show_storyboard_background := true
## 编辑器的窄预览里把整块 storyboard 等比缩到装得下（试玩保持按高度铺满）。
var storyboard_fit := false
## storyboard 采样按 30Hz 走（60fps 下每帧重算 700+ 对象太贵），中间帧复用同一份结果。
## 故事板每帧都重采样，间隔跟「画质 → 帧率上限」：60/120 跟满，144/240/vsync/不限封顶 120。
var _sb_sample_interval := 1000.0 / 60.0
## 0 = 跟随帧率上限；视频导出设成导出 fps，保证每一帧都重采样。
var storyboard_sample_hz := 0
var _sb_sample_ms := -1.0e9
var _sb_queued_ms := -1.0e9
var _sb_waiting_dir := ""
var _sb_wide_detected := false
var _sb_render_items: Array[Dictionary] = []
## 采样后按图层分桶：每层只遍历自己的对象，不用 7 个层各扫一遍全部 items。
var _sb_layer_items: Dictionary = {}
var _sb_additive_layer_items: Dictionary = {}
## 引用文件的全路径只拼一次（以前每帧每张图都要 get_file() + 拼接）。
var _sb_priority: PackedStringArray = PackedStringArray()
var _sb_priority_index: int = 0
var _sb_priority_ms: float = INF
var _sb_priority_until: float = -INF
var _sb_texture_generation: int = -1
var _sb_paths: Dictionary = {}
var _sb_all_textures_cached: bool = false
var _sb_eviction_generation: int = -1
var _sb_keepalive_ms: int = -500
## storyboard 的 Background 层里有谱面背景图时，静态背景层要关掉（对照 lazer ReplacesBackground）。
var _storyboard_replaces_background := false
## 背景层（Background/Video）单独一层，垫在 3D 判定环下面。
## 每个故事板绘制层外面套一个裁剪容器：只显示 854×480 / 640×480 安全框，
## 超宽背景不再从左右两侧漏出来。绘制节点仍是 _storyboard_bg 等。
var _storyboard_bg_clip: Control = null
var _storyboard_add_bg_clip: Control = null
var _storyboard_fg_clip: Control = null
var _storyboard_top_clip: Control = null
var _storyboard_add_fg_clip: Control = null
var _storyboard_bg: Control = null
## 加色（P,A）元素单独一层：粒子/光晕走 BLEND_MODE_ADD，叠在普通层上面。
var _storyboard_add_bg: Control = null
var _storyboard_add_fg: Control = null
## Foreground 在判定环之上、音符之下；Overlay 在音符之上（osu 的层序）。
var _storyboard_fg: Control = null
var _storyboard_top: Control = null
## 背景调暗层：盖住背景和 storyboard，但压在 3D 判定环下面（osu 的 Background dim）。
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
var _cursor_layer: Control
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
## 静图默认 32% 不透明度；改成全局系数后由设置推动。
## 谱面背景（静图/BGA）的基准不透明度。osu 里背景是实心的，暗度只由「背景明暗」控制，
## 所以这里不再乘一个 0.32 的基准值——那个值会让默认设置下背景几乎看不见。
const BACKGROUND_ALPHA := 1.0
## 背景明暗系数（1.0 = 现在观感）；静图和 BGA 共用。
var background_brightness: float = 1.0
## 暂停时把 BGA 一起停住，恢复后由 _update_video 重新对齐位置。
var video_paused: bool = false
## 播放倍速：BGA 跟着音频一起变速，否则画面会和音乐脱节。
var playback_rate: float = 1.0
## 异步转码的令牌：换谱/换视频后旧结果直接丢掉。
var _video_job_token: int = 0
var _last_cursor_emit: Vector2 = Vector2(-999, -999)
var _cursor_cache_key: String = ""
var _sorted_notes_cache: Array[Note] = []
class VisiblePath:
	var parts: Array[Note] = []
	var first_beat: float = INF
	var last_beat: float = -INF
	var note: Note


class PathStroke:
	var count: int = 0
	var projection_key: String = ""
	var points := PackedVector2Array()
	var distances := PackedFloat64Array()
	var cut_version: int = -1
	var erased: Array[bool] = []
	var runs: Array[PackedVector2Array] = []
	var run_starts: Array[int] = []


class PathChevron:
	var fraction: float
	var point: Vector2
	var direction: Vector2


var _indexed_path_chart: Chart
var _indexed_path_version: int = -1
var _indexed_path_roots: Array[Note] = []
var _path_index: Array[VisiblePath] = []
var _path_prefix_end := PackedFloat64Array()
var _path_strokes: Dictionary[Note, PathStroke] = {}
var _path_overlap_samples: Dictionary[Note, PackedVector2Array] = {}
var _overlap_paths: Array[Note] = []
var _overlap_any: bool = false
var _sorted_notes_chart: Chart = null
var _last_view_key: String = ""
var _last_fit_key: String = ""
var _last_mesh_key: String = ""
var _last_mesh_usec: int = 0
var _last_process_time: float = -9999.0
var _last_mouse_screen: Vector2 = Vector2(-9999, -9999)
var _cursor_trail: Array[Dictionary] = []
## 性能采样：draw_overlay 的平均耗时 + FPS，每 2 秒打印一次（仅试玩）。
var _perf_draw_usec: int = 0
var _perf_frames: int = 0
## [seeks, paths, holds, notes, fx, hud, bar, cursor, audio] 的累计微秒。
var _perf_sections: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var _perf_proc_usec: int = 0
var _perf_mesh_usec: int = 0
var _perf_since_usec: int = 0
## 舞萌星星的默认深蓝色，以及重叠时使用的同色系配色。
const STAR_BLUE := Color(0.22, 0.36, 0.88)
const STAR_BLUE_PALETTE: Array[Color] = [
	Color(0.22, 0.36, 0.88),
	Color(0.16, 0.62, 0.97),
	Color(0.42, 0.52, 1.00),
	Color(0.10, 0.78, 0.90),
	Color(0.30, 0.30, 0.72),
	Color(0.55, 0.72, 1.00),
	Color(0.10, 0.50, 0.62),
]
var _avg_radius_cache: float = 100.0
var _avg_radius_key: String = ""
var _last_overlay_time: float = -9999.0
var _render_mode: int = -1
var _tilt: Vector2 = Vector2.ZERO
var _tilt_target: Vector2 = Vector2.ZERO
var _force_3d_frame: bool = false
var _playhead_redraw_pending: bool = false
var _boundary_frame_cache: BoundaryFrame = null
var _max_design_radius: float = -1.0
var _path_local_cache: Dictionary = {}

var _drag_vertex: int = -1
var _drag_visual: int = -1
var _drag_visual_note: Note = null
var _drag_visual_start: Vector2 = Vector2.ZERO
var _drag_visual_db: float = 0.0
var _drag_visual_da: float = 0.0
var _drag_note: Note = null
var _drag_note_angle: float = 0.0
var _drag_note_tail: float = 0.0
var _drag_note_cursor: float = NAN
## Anchor 是刚体：按下时把整对记下来，拖动与松手回吸都按同一个角度增量走。
var _drag_group: Array[Note] = []
var _drag_group_starts: Array[float] = []
var _drawing_red: bool = false
var _red_region: Region = null
var _red_start_u: float = 0.0
var _red_start_beat: float = 0.0
var _red_start_mouse: Vector2 = Vector2.ZERO
var _pulses: Array[Dictionary] = []
var _ring_lights: Array[Dictionary] = []
var _note_pops: Array[Dictionary] = []
# 音符外观（网页 Note & Hit Lab 里可对比选择）。
var note_skin: String = "candy"
## PERFECT 特效：只有 PERFECT 命中才在判定环外侧亮光扇 + 碎屑。
var show_perfect_fx: bool = true
var _skin_cache: Dictionary = {}
var _skin_cache_key: String = ""
var path_cuts: Dictionary = {}
## 环分区擦除：note.id -> [{from,to}]，和 path_cuts 分开存，避免每帧的
## set_path_erased_to 把分区擦除覆盖掉。
var path_sector_cuts: Dictionary = {}
var path_cut_versions: Dictionary = {}
var _path_sector_cache: Dictionary = {}
## 星头判定结果（试玩时由 Playtest 写入）：{hit: bool, beat: float}。
var _path_head_state: Dictionary = {}
## 试玩判定结果（note.id -> "hit" / "miss" / "holding"）：
## 判定一出来音符就退场；hold 头部命中后只隐藏头部，长条继续画。
var note_states: Dictionary = {}
## 判成 MISS 时的谱面拍：hold 整条按 0.24 拍淡出，不硬切。
var note_state_beats: Dictionary = {}
## 环编辑工作区模式：左键拖空白旋转、滚轮缩放。
var ring_edit_mode: bool = false
## 工作区当前选中的演出指令：文本拖动和滤镜区域描边都靠它。
var selected_command: AlphaCommand = null
var _text_drag: AlphaCommand = null
var _text_drag_offset := Vector2.ZERO
var _ring_line_width := RING_WIDTH
var _ring_glow_width := GLOW_WIDTH
var _jline_active := false
var _jline_color := Color(0.62, 0.64, 0.68)
var _jline_alpha := 1.0
var _last_jline_key := ""
var _ring_rotating: bool = false
var _ring_rot_last: float = 0.0
var _drawing_path: bool = false
## 绘制中的原始鼠标轨迹（屏幕坐标）：先显示原始轨迹，松手再投影/平滑成 Path。
var _path_points: Array[Vector2] = []
var _path_head_angle: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_app = get_node_or_null("/root/App")
	_build_layers()
	_build_3d()
	_build_filter_layer()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.ring_live_changed.connect(_on_ring_live_changed)
		_app.ring_changed.connect(_on_ring_changed)
		_app.selection_changed.connect(_on_selection_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.tool_changed.connect(_on_tool_changed)
	set_process(true)


func _exit_tree() -> void:
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 画质档：0 = 全开，1 = 省电（只降 3D 背景的渲染分辨率，音符永远按全画质画）。
## 试玩里由实测帧时自动降档，只为让弱机也能稳住节奏。
## 全屏滤镜层（屏幕采样 shader）；由 <FLASH>/<HUE>/<ZOOM> 等滤镜指令逐帧驱动。
var _filter_layer: ColorRect = null
## 滤镜层是否常驻。false = 只在有滤镜生效时显示（默认，省掉每帧一次整屏拷贝 +
## 屏幕纹理 mip 链 + 全屏 pass）；true = 旧行为，调试用。
const FILTER_ALWAYS_ON := false
## 启动后先让滤镜层可见这么多帧，把 shader 首次编译的卡顿吃掉——这几帧正好是
## 进入预览/试玩的瞬间，肉眼看不到。
const FILTER_WARMUP_FRAMES := 3
var _filter_warmup_left: int = FILTER_WARMUP_FRAMES
var quality_level: int = 0
## 音符弧带采样精度：true = 1/4°（全画质），false = 1/6°（省电，边缘略方）。
var note_detail_fine: bool = true
## 音符粉色柔光 / 拖尾长度 / 命中特效强度 / 小节线：全部来自视图菜单的画质项。
var note_glow: bool = true
var cursor_trail_mode: String = "long"
var fx_budget: String = "full"
var bar_lines_visible: bool = true
## 3D 背景渲染分辨率与刷新率（2D 与判定永远按游戏帧率）。
var ring_3d_scale: String = "high"
## 0 = 关，1 = 2x，2 = 4x
var msaa_3d_level: int = 1


func set_quality_level(level: int) -> void:
	var next := clampi(level, 0, 1)
	if next == quality_level:
		return
	quality_level = next
	apply_ring_quality()


func apply_playfield_quality(settings: Node) -> void:
	use_3d_ring = bool(settings.use_3d_ring)
	msaa_3d_level = int(settings.msaa_3d_level)
	ring_3d_scale = String(settings.ring_3d_scale)
	apply_ring_quality()


## 3D 背景分辨率：菜单选的高/中/低，再叠加弱机自动降档（降一档，最低 0.4）。
func apply_ring_quality() -> void:
	if _subviewport == null:
		return
	var scale := 1.0
	match ring_3d_scale:
		"high":
			scale = 0.85
		"mid":
			scale = 0.65
		"low":
			scale = 0.5
	if quality_level > 0:
		scale = maxf(0.4, scale - 0.15)
	_subviewport.scaling_3d_scale = scale
	# 抗锯齿按模式组合：MSAA / FXAA / TAA / MSAA+FXAA。
	_subviewport.msaa_3d = Viewport.MSAA_DISABLED
	_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_subviewport.use_taa = false
	match msaa_3d_level:
		1:
			_subviewport.msaa_3d = Viewport.MSAA_2X
		2:
			_subviewport.msaa_3d = Viewport.MSAA_4X
		3:
			_subviewport.msaa_3d = Viewport.MSAA_8X
		4:
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		5:
			_subviewport.use_taa = true
		6:
			_subviewport.msaa_3d = Viewport.MSAA_2X
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		7:
			_subviewport.msaa_3d = Viewport.MSAA_4X
			_subviewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if _overlay != null:
		_overlay.queue_redraw()


## 暂停 / 结算：冻结 3D 子视口（保留最后一帧），但不接管 _process 归属。
## 试玩的帧是 Playtest 主动驱动的，不能在这里 set_process(true)。
func freeze_ring_3d(frozen: bool) -> void:
	if _subviewport == null:
		return
	if frozen:
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_render_mode = SubViewport.UPDATE_DISABLED
	else:
		_force_3d_frame = use_3d_ring
		_render_mode = -1


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


## 建一个故事板绘制节点：外层裁剪容器由调用方建，这里只负责铺满 + 脚本。
func _make_storyboard_draw(clip: Control, node_name: String, flag: String, material: Material) -> Control:
	var draw := Control.new()
	draw.name = node_name
	draw.set_script(load("res://charter/preview_overlay.gd"))
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw.set("preview", self)
	draw.set(flag, true)
	if material != null:
		draw.material = material
	clip.add_child(draw)
	draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return draw


## 安全框（854×480 或 640×480）在预览里的矩形：宽屏场按高度铺满，编辑器预览用 contain。
func _storyboard_field_rect() -> Rect2:
	var field := _storyboard_field_width()
	var scale := size.y / Storyboard.FIELD_HEIGHT
	if storyboard_fit:
		scale = minf(size.x / field, size.y / Storyboard.FIELD_HEIGHT)
	var field_size := Vector2(field, Storyboard.FIELD_HEIGHT) * scale
	return Rect2((size - field_size) * 0.5, field_size)


## 把 5 个裁剪容器摆到安全框上；绘制子节点铺满容器（坐标从安全框左上角算）。
func _update_storyboard_clip_rects() -> void:
	var rect := _storyboard_field_rect()
	for clip in [_storyboard_bg_clip, _storyboard_add_bg_clip, _storyboard_fg_clip,
			_storyboard_top_clip, _storyboard_add_fg_clip]:
		if clip == null:
			continue
		clip.set_anchors_preset(Control.PRESET_TOP_LEFT)
		clip.position = rect.position
		clip.size = rect.size
		for child in clip.get_children():
			(child as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_storyboard_clip_rects()


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
	_subviewport.scaling_3d_scale = 1.0
	_subviewport.msaa_3d = Viewport.MSAA_2X
	_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport_container.add_child(_subviewport)

	_overlay = Control.new()
	_overlay.set_script(load("res://charter/preview_overlay.gd"))
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set("preview", self)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 光标单独一层：鼠标移动只重绘这一层，不再重画整个场景。
	_cursor_layer = Control.new()
	_cursor_layer.set_script(load("res://charter/preview_overlay.gd"))
	_cursor_layer.name = "CursorLayer"
	_cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.set("preview", self)
	_cursor_layer.set("cursor_only", true)
	add_child(_cursor_layer)
	_cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.visible = use_3d_ring and show_playfield
	# storyboard 的 Background 层要垫在 3D 判定环下面，Foreground/Overlay 走 _overlay。
	# 故事板统一裁到安全框：裁剪容器 = 安全框，绘制子节点铺满它。
	# 背景/加色背景在 3D 判定环下面；Foreground 在环上面、音符下面；
	# Overlay 在音符上面、光标下面；加色前景沿用原来的最上层。
	_storyboard_bg_clip = Control.new()
	_storyboard_bg_clip.name = "StoryboardBackgroundClip"
	_storyboard_bg_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storyboard_bg_clip.clip_contents = true
	add_child(_storyboard_bg_clip)
	move_child(_storyboard_bg_clip, _viewport_container.get_index())
	_storyboard_bg = _make_storyboard_draw(_storyboard_bg_clip, "StoryboardBackground", "storyboard_background", null)

	var add_material := CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_storyboard_add_bg_clip = Control.new()
	_storyboard_add_bg_clip.name = "StoryboardAdditiveClip"
	_storyboard_add_bg_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storyboard_add_bg_clip.clip_contents = true
	add_child(_storyboard_add_bg_clip)
	move_child(_storyboard_add_bg_clip, _viewport_container.get_index())
	_storyboard_add_bg = _make_storyboard_draw(_storyboard_add_bg_clip, "StoryboardAdditive", "storyboard_additive", add_material)

	var add_fg_material := CanvasItemMaterial.new()
	add_fg_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_storyboard_add_fg_clip = Control.new()
	_storyboard_add_fg_clip.name = "StoryboardAdditiveFrontClip"
	_storyboard_add_fg_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storyboard_add_fg_clip.clip_contents = true
	add_child(_storyboard_add_fg_clip)
	_storyboard_add_fg = _make_storyboard_draw(_storyboard_add_fg_clip, "StoryboardAdditiveFront", "storyboard_additive", add_fg_material)
	_storyboard_add_fg.set("additive_front", true)

	# Foreground：盖住判定环，但在音符下面。
	_storyboard_fg_clip = Control.new()
	_storyboard_fg_clip.name = "StoryboardForegroundClip"
	_storyboard_fg_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storyboard_fg_clip.clip_contents = true
	add_child(_storyboard_fg_clip)
	move_child(_storyboard_fg_clip, _viewport_container.get_index())
	_storyboard_fg = _make_storyboard_draw(_storyboard_fg_clip, "StoryboardForeground", "storyboard_front", null)

	# Overlay：压在音符上面，光标层下面。
	_storyboard_top_clip = Control.new()
	_storyboard_top_clip.name = "StoryboardOverlayClip"
	_storyboard_top_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storyboard_top_clip.clip_contents = true
	add_child(_storyboard_top_clip)
	move_child(_storyboard_top_clip, _viewport_container.get_index())
	_storyboard_top = _make_storyboard_draw(_storyboard_top_clip, "StoryboardOverlay", "storyboard_overlay", null)

	_update_storyboard_clip_rects()
	# 图层是在 _ready 里建的，构造期间可能已经设过明暗，这里补一次。
	set_background_brightness(background_brightness)


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


## The playtest advances geometry once before judgement, using the same camera
## and beat that the overlay will draw for this frame.
func prepare_playtest_frame(beat: float, delta: float) -> void:
	time_beat = beat
	_process(delta)


func _process(_delta: float) -> void:
	var proc_start := Time.get_ticks_usec()
	# 热身帧计数放在 chart 空检查之前：没有谱面时也要走完预热并隐藏滤镜层。
	if _filter_warmup_left > 0:
		_filter_warmup_left -= 1
		if _filter_warmup_left == 0:
			_set_filter_visible(false)
	var chart := get_chart()
	if chart == null:
		_trim_storyboard_textures(Time.get_ticks_msec())
		_update_filter_visibility(null, 0.0)
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
		if float(_pulses[i]["age"]) > 0.62:
			_pulses.remove_at(i)
	for i in range(_ring_lights.size() - 1, -1, -1):
		_ring_lights[i]["age"] = float(_ring_lights[i].get("age", 0.0)) + _delta
		if float(_ring_lights[i]["age"]) > RING_LIGHT_SEC:
			_ring_lights.remove_at(i)
	for i in range(_note_pops.size() - 1, -1, -1):
		_note_pops[i]["age"] = float(_note_pops[i].get("age", 0.0)) + _delta
		if float(_note_pops[i]["age"]) > NOTE_POP_SEC:
			_note_pops.remove_at(i)
	var t := get_time_beat()
	# 显隐必须在绘制之前定下来（在 _draw 里改 visible 会晚一帧），所以放在 _process。
	_update_filter_visibility(chart, t)
	var time_changed := absf(t - _last_process_time) > 0.0005
	var jline := jline_state(chart, t)
	var jline_key := _jline_key(jline)
	if jline_key != _last_jline_key:
		_last_jline_key = jline_key
		_mesh_dirty = true
	_apply_jline(jline)
	var mesh_key := _mesh_key(chart, t)
	var view_changed := _update_transform(t)
	var flat_dirty := _mesh_dirty and not use_3d_ring
	if use_3d_ring and (_mesh_dirty or mesh_key != _last_mesh_key):
		# 形变时每帧重建：30Hz 的几何更新会让环比音符慢半拍，看起来就是卡顿。
		var mesh_start := Time.get_ticks_usec()
		_update_ring_mesh(chart, t)
		_perf_mesh_usec += Time.get_ticks_usec() - mesh_start
		_last_mesh_key = mesh_key
		_last_mesh_usec = Time.get_ticks_usec()
		view_changed = true
	if not use_3d_ring and _mesh_dirty:
		_mesh_dirty = false
	_update_background(chart)
	_update_video(chart, t)
	_update_storyboard_textures(chart, t)
	var beat_phase := fposmod(t, 1.0)
	var glow_pulse := 0.10 + 0.09 * exp(-beat_phase * 7.0)
	if _jline_active:
		_glow_material.albedo_color = Color(_jline_color.r, _jline_color.g, _jline_color.b, glow_pulse * _jline_alpha)
	else:
		_glow_material.albedo_color = Color(0.37, 0.92, 0.86, glow_pulse)
	if playtest_mode:
		mouse_screen = auto_cursor if auto_cursor.is_finite() else get_local_mouse_position()
		mouse_inside = true
		var perf_now := Time.get_ticks_usec()
		if _perf_since_usec == 0:
			_perf_since_usec = perf_now
		elif perf_now - _perf_since_usec >= 2000000 and _perf_frames > 0:
			var per := float(maxi(1, _perf_frames)) * 1000.0
			if OS.is_debug_build():
				print("[perf] fps=%.0f draw=%.2f proc=%.2f mesh=%.2f | path=%.2f hold=%.2f note=%.2f fx=%.2f hud=%.2f bar=%.2f cursor=%.2f audio=%.2f" % [
					Engine.get_frames_per_second(),
					float(_perf_draw_usec) / float(maxi(1, _perf_frames)) / 1000.0,
					float(_perf_proc_usec) / float(maxi(1, _perf_frames)) / 1000.0,
					float(_perf_mesh_usec) / per,
					float(_perf_sections[1]) / per,
					float(_perf_sections[2]) / per,
					float(_perf_sections[3]) / per,
					float(_perf_sections[4]) / per,
					float(_perf_sections[5]) / per,
					float(_perf_sections[6]) / per,
					float(_perf_sections[7]) / per,
					float(_perf_sections[8]) / per,
				])
			_perf_draw_usec = 0
			_perf_frames = 0
			_perf_sections = [0, 0, 0, 0, 0, 0, 0, 0, 0]
			_perf_proc_usec = 0
			_perf_mesh_usec = 0
			_perf_since_usec = perf_now
	var mouse_moved := mouse_screen.distance_to(_last_mouse_screen) > 0.1
	if mouse_inside and (playtest_mode or (playing and Engine.get_process_frames() % 6 == 0) or mouse_moved):
		# 画 Path 时不做环上吸附：这段完全用不到，省下的就是帧预算。
		if not _drawing_path:
			_update_cursor()
	_update_cursor_trail(_delta)
	# 场景层只在时间/几何/特效变化时重绘；鼠标移动只触发光标层。
	var needs_overlay := _playhead_redraw_pending or time_changed or view_changed or flat_dirty or not _pulses.is_empty() or not _note_pops.is_empty() or not _ring_lights.is_empty()
	_playhead_redraw_pending = false
	if needs_overlay:
		_overlay.queue_redraw()
	if show_storyboard and _storyboard != null and (time_changed or _sb_queued_ms < -1.0e8):
		# 故事板有自己的 2D 坐标，环的形变/镜头变化不会影响它。
		var sb_ms := chart.timing.beat_to_chart_ms(t) - chart.offset_ms
		_sb_sample_interval = _storyboard_sample_interval()
		if absf(sb_ms - _sb_queued_ms) >= maxf(0.0001, _sb_sample_interval):
			_sb_queued_ms = sb_ms
			_queue_storyboard_redraw()
	if mouse_moved or time_changed or view_changed or not _cursor_trail.is_empty():
		_cursor_layer.queue_redraw()
	var render_playfield: bool = use_3d_ring and show_playfield
	if _viewport_container != null:
		_force_3d_frame = _force_3d_frame or (render_playfield and not _viewport_container.visible)
		_viewport_container.visible = render_playfield
	if render_playfield:
		var animate_3d := playing or playtest_mode or _tilt.distance_to(_tilt_target) > 0.01
		# 形变时每帧都要重画：UPDATE_ONCE 渲染完会被引擎改回 DISABLED，
		# 而缓存的 _render_mode 还停在 ONCE，后面的帧就再也不更新（正是卡顿/不动的来源）。
		_update_3d_mode(animate_3d, view_changed or _mesh_dirty or mesh_key != _last_mesh_key)
	elif _subviewport != null and _render_mode != SubViewport.UPDATE_DISABLED:
		freeze_ring_3d(true)
	_last_process_time = t
	_last_mouse_screen = mouse_screen
	_perf_proc_usec += Time.get_ticks_usec() - proc_start


func _mesh_key(chart: Chart, beat: float) -> String:
	# 关键帧模型：缓存键取“当前在哪两个形状之间 + 插值进度”。
	# 少了 p，形变期间键值不变，环网格就永远停在基础形状上。
	var pair := BoundaryRuntime.pair_at(chart, beat)
	if pair.is_empty():
		return "base:" + chart.default_shape_id
	var from_shape: BoundaryShape = pair.get("from")
	var to_shape: BoundaryShape = pair.get("to")
	var from_id := from_shape.id if from_shape != null else "?"
	var to_id := to_shape.id if to_shape != null else "?"
	return "%s>%s:%.4f" % [from_id, to_id, float(pair.get("p", 0.0))]


func _update_3d_mode(animate: bool, changed: bool) -> void:
	if _subviewport == null:
		return
	# 只在“需要连续帧”和“静止”之间切换；UPDATE_ONCE 会被引擎改回 DISABLED，
	# 用它做逐帧更新会卡在第一帧。
	var desired := SubViewport.UPDATE_ALWAYS if (animate or changed or _force_3d_frame) else SubViewport.UPDATE_DISABLED
	_force_3d_frame = false
	if desired != _render_mode:
		_subviewport.render_target_update_mode = desired
		_render_mode = desired


func _update_mouse_tilt(delta: float) -> void:
	var amount := 7.0 if playtest_mode else MOUSE_TILT_DEGREES
	# 导出回放时没有真实鼠标：用注入的回放光标，否则会跟着窗口鼠标乱抖。
	var from_auto := auto_cursor.is_finite()
	var local := auto_cursor if from_auto else get_local_mouse_position()
	var bounds := size
	if from_auto and auto_cursor_bounds.x > 1.0 and auto_cursor_bounds.y > 1.0:
		bounds = auto_cursor_bounds
	var source_ok := (mouse_inside or playtest_mode) and Rect2(Vector2.ZERO, bounds).has_point(local)
	# 无头/基准里 get_local_mouse_position() 恒为 (0,0)，不能把它当成「鼠标在左上角」。
	if DisplayServer.get_name() == "headless" and not from_auto:
		source_ok = false
	if not mouse_tilt or amount <= 0.001 or not source_ok:
		_tilt_target = Vector2.ZERO
	else:
		_tilt_target = tilt_target_for(local, bounds, amount)
	var weight := 1.0 - exp(-maxf(0.0, delta) * 10.0)
	_tilt = _tilt.lerp(_tilt_target, weight)
	if _tilt_target == Vector2.ZERO and _tilt.length() < 0.01:
		_tilt = Vector2.ZERO


## 环的最终变换：绕 X/Y 旋转，并按倾斜量轻微平移环心（每度 2.8 设计单位）。
static func ring_transform(rotation: float, tilt_x: float, tilt_y: float,
		zoom: float, ellipse: float, tilt: Vector2) -> Transform3D:
	var basis := Basis(Vector3(0, 0, 1), deg_to_rad(rotation))
	basis = basis * Basis(Vector3(1, 0, 0), deg_to_rad(tilt_x + tilt.x))
	basis = basis * Basis(Vector3(0, 1, 0), deg_to_rad(tilt_y + tilt.y))
	# 远端那版会随倾斜把环心轻轻推一点（每度 2.8 设计单位），
	# 「只绕环心转」看起来反而平；这里按原样保留。
	return Transform3D(basis.scaled(Vector3(zoom * ellipse, zoom, zoom)),
		Vector3(-tilt.y * 2.8, -tilt.x * 2.8, 0.0))


## 鼠标位置 → 两轴倾斜角。鼠标那一侧的环靠近镜头（近大远小）：
## X 用 -ny 让上边靠近，Y 必须用 -nx 才是同一方向；用 +nx 会左右上下反着歪。
static func tilt_target_for(local: Vector2, bounds: Vector2, degrees: float) -> Vector2:
	if bounds.x <= 1.0 or bounds.y <= 1.0 or degrees <= 0.001:
		return Vector2.ZERO
	var nx := clampf((local.x - bounds.x * 0.5) / (bounds.x * 0.5), -1.0, 1.0)
	var ny := clampf((local.y - bounds.y * 0.5) / (bounds.y * 0.5), -1.0, 1.0)
	return Vector2(-ny * degrees, nx * degrees)


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
	var dolly := float(view.get("dolly", 1.0))
	if bool(chart.metadata.get("face_camera", true)):
		# 正对镜头只忽略谱面 ViewState 的倾斜；鼠标视差仍然保留。
		tilt_x = 0.0
		tilt_y = 0.0
		ellipse = 1.0
	var key := "%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [rotation, tilt_x, tilt_y, zoom, ellipse, dolly, _tilt.x, _tilt.y]
	if key == _last_view_key:
		return false
	_last_view_key = key
	_ring_root.transform = ring_transform(rotation, tilt_x, tilt_y, zoom, ellipse, _tilt)
	var fit_key := "%.3f|%.3f|%.3f|%d|%.0f|%.0f|%.1f" % [zoom, ellipse, dolly, 1 if playtest_mode else 0, size.x, size.y,
		0.0]
	if fit_key != _last_fit_key:
		_last_fit_key = fit_key
		_update_camera_fit(chart, zoom, ellipse, dolly)
	return true


## 谱面里最大的形状半径（舞台读数 / 相机取景共用）。
## 换谱（重试会重建 chart）时会被置 -1；两个使用者都必须能自己补算，
## 否则 HUD 会掉进另一条测量分支、两侧列突然往里缩。
func _ensure_design_radius(chart: Chart) -> float:
	if _max_design_radius > 0.0 or chart == null:
		return _max_design_radius
	_max_design_radius = 520.0
	for shape in chart.sorted_shapes():
		for data in shape.sample_points(32):
			_max_design_radius = maxf(_max_design_radius, (data.point as Vector2).length())
	return _max_design_radius


func _update_camera_fit(chart: Chart, zoom: float, ellipse: float, dolly: float = 1.0) -> void:
	# 环工作区开关会把预览在两个容器间搬动，搬家途中 resized 先到、节点还没入树。
	if not is_inside_tree() or _camera == null or not _camera.is_inside_tree():
		return
	_ensure_design_radius(chart)
	var aspect := maxf(0.2, size.x / maxf(1.0, size.y))
	# 试玩时把环放大到接近满屏比例；编辑器保持原来的留白。
	var margin := 1.06 if playtest_mode else PREVIEW_MARGIN
	# dolly 是真正的镜头推拉：>1 相机靠近（环变大），<1 后退。
	# zoom 仍走原来的取景补偿，所以旧谱默认 dolly=1 时外观不变。
	var wanted := _max_design_radius * maxf(0.5, zoom) * maxf(0.5, ellipse) * margin / maxf(0.2, dolly)
	var distance := wanted / tan(deg_to_rad(_camera.fov * 0.5)) / minf(1.0, aspect)
	distance = clampf(distance, 500.0, 6000.0)
	_camera.position = Vector3(0, 0, distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _update_ring_mesh(chart: Chart, beat: float) -> void:
	var points := _frame_for(chart, beat).sample_points(96)
	_ring_mesh.mesh = _build_ribbon(points, _ring_line_width, _ring_material)
	_glow_mesh.mesh = _build_ribbon(points, _ring_glow_width, _glow_material)
	_shadow_mesh.mesh = _build_ribbon(points, 30.0, _shadow_material)
	_last_mesh_beat = beat
	_mesh_dirty = false


## 当前拍生效的 JLINE：颜色/环宽/透明度/外圈扩张。默认后开始的接管；
## 交叉淡入时按包络权重混合，重叠段的颜色和宽度不会突然跳变。
static func jline_state(chart: Chart, t: float) -> Dictionary:
	if chart == null:
		return {"active": false}
	var active: Array[AlphaCommand] = []
	for command in chart.sorted_commands():
		if not command.enabled or command.category() != AlphaCommand.CATEGORY_JLINE:
			continue
		if t < command.beat - 0.0001 or t > command.end_beat() + 0.0001:
			continue
		if command.envelope_at(t) <= 0.001:
			continue
		active.append(command)
	if active.is_empty():
		return {"active": false}
	var last := active[active.size() - 1]
	var crossfade := last.text_value("blend", "后开始接管") == "交叉淡入" and active.size() > 1
	if not crossfade:
		return _jline_values(last)
	var total := 0.0
	var color := Color(0, 0, 0, 0)
	var width := 0.0
	var alpha := 0.0
	var expand := 0.0
	for command in active:
		var weight := command.envelope_at(t)
		if weight <= 0.0:
			continue
		var value := _jline_values(command)
		var item: Color = value.get("color", Color.WHITE)
		color = Color(color.r + item.r * weight, color.g + item.g * weight,
			color.b + item.b * weight, color.a + item.a * weight)
		width += float(value.get("width", RING_WIDTH)) * weight
		alpha += float(value.get("alpha", 1.0)) * weight
		expand += float(value.get("expand", 0.0)) * weight
		total += weight
	if total <= 0.0001:
		return _jline_values(last)
	return {
		"active": true,
		"color": Color(color.r / total, color.g / total, color.b / total),
		"width": width / total,
		"alpha": alpha / total,
		"expand": expand / total,
	}


static func _jline_values(command: AlphaCommand) -> Dictionary:
	return {
		"active": true,
		"color": command.color_value("color", Color.WHITE),
		"width": clampf(command.number("width", 6.0), 0.5, 24.0),
		"alpha": clampf(command.number("alpha", 1.0), 0.0, 1.0),
		"expand": clampf(command.number("expand", 0.0), 0.0, 1.0),
	}


static func _jline_key(state: Dictionary) -> String:
	if not bool(state.get("active", false)):
		return "off"
	var color: Color = state.get("color", Color.WHITE)
	return "%s|%.3f|%.3f|%.3f" % [color.to_html(), float(state.get("width", RING_WIDTH)),
		float(state.get("alpha", 1.0)), float(state.get("expand", 0.0))]


func _apply_jline(state: Dictionary) -> void:
	_jline_active = bool(state.get("active", false))
	if _jline_active:
		_jline_color = state.get("color", Color.WHITE)
		_jline_alpha = clampf(float(state.get("alpha", 1.0)), 0.0, 1.0)
		_ring_line_width = clampf(float(state.get("width", RING_WIDTH)), 0.5, 24.0)
		_ring_glow_width = maxf(GLOW_WIDTH, _ring_line_width * 3.0 + float(state.get("expand", 0.0)) * 24.0)
		_ring_material.albedo_color = Color(_jline_color.r, _jline_color.g, _jline_color.b, _jline_alpha)
		return
	_ring_line_width = RING_WIDTH
	_ring_glow_width = GLOW_WIDTH
	_ring_material.albedo_color = Color(0.62, 0.64, 0.68, 0.95)


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
	# 每个点取相邻两条边的平均法线（miter）：段与段之间共用顶点，
	# 接缝不会裂开，折角也不会出现锯齿状缺口。
	var normals: Array[Vector2] = []
	normals.resize(count)
	for i in count:
		var prev: Vector2 = points[(i - 1 + count) % count].point
		var next: Vector2 = points[(i + 1) % count].point
		var tangent := next - prev
		if tangent.length_squared() < 0.000001:
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x).normalized() * half
		# 尖角限制：miter 最多 2 倍宽度，避免长刺。
		if normal.length() > half * 2.0:
			normal = normal.normalized() * half * 2.0
		normals[i] = normal
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		if bool(a.get("gap", false)) or bool(b.get("gap", false)):
			continue
		var pa: Vector2 = a.point
		var pb: Vector2 = b.point
		if (pb - pa).length_squared() < 0.000001:
			continue
		var na: Vector2 = normals[i]
		var nb: Vector2 = normals[(i + 1) % count]
		var v0 := pa + na
		var v1 := pa - na
		var v2 := pb + nb
		var v3 := pb - nb
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
	# 新标签页没有背景时必须清掉上一张图；不能因为缓存键也是空串就直接返回。
	if path.is_empty():
		_last_background_path = ""
		if _background_image.texture != null or _background_image.visible:
			_background_image.texture = null
			_background_image.visible = false
		return
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		if _app != null and not _app.chart_path.is_empty():
			resolved = ChartIO.resolve_path(_app.chart_path, path)
	# 用解析后的绝对路径做缓存键：不同标签页可以有相同的相对文件名。
	if resolved == _last_background_path:
		return
	_last_background_path = resolved
	var texture: Texture2D = null
	if resolved.begins_with("res://"):
		if ResourceLoader.exists(resolved):
			texture = load(resolved) as Texture2D
	else:
		var image := Image.load_from_file(ProjectSettings.globalize_path(resolved) if resolved.begins_with("user://") else resolved)
		if image != null and image.get_width() > 0 and image.get_height() > 0:
			texture = ImageTexture.create_from_image(image)
	_background_image.texture = texture
	_background_image.visible = background_image_visible(texture != null, _video != null and _video.stream != null)
	_background_image.modulate = Color(1, 1, 1, background_alpha(background_brightness))


## 静图基准不透明度 32%；明暗系数是全局乘数（1.0 = 默认）。
static func background_alpha(brightness: float) -> float:
	return BACKGROUND_ALPHA * maxf(0.0, brightness)


## 有 BGA 时不叠加谱面背景图：两张背景一起画既脏又浪费。
static func background_image_visible(has_texture: bool, has_video: bool) -> bool:
	return has_texture and not has_video


## BGA 的不透明度：谱面自己的 opacity × 全局明暗系数。
static func video_alpha(chart_opacity: float, brightness: float) -> float:
	return clampf(chart_opacity, 0.0, 1.0) * maxf(0.0, brightness)


## 背景明暗（0–1）：曲绘 / BGA / 整张故事板共用一个系数。
func set_background_brightness(value: float) -> void:
	# 设置项封顶 100%；这里再钳一次，防止别处直接赋值绕过上限。
	background_brightness = clampf(value, 0.0, 1.0)
	if _background_image != null:
		_background_image.modulate = Color(1, 1, 1, background_alpha(background_brightness))
	# 故事板当作一个整体压暗：同一个系数乘到全部图层上。
	# 前景/覆盖层画在判定环上面，不能盖黑遮罩（会把环和音符一起压掉），
	# 所以统一用 self_modulate 乘自身像素，环和 HUD 亮度不变。
	var keep := background_brightness
	var tint := Color(keep, keep, keep, 1.0)
	for layer in [_storyboard_bg, _storyboard_add_bg, _storyboard_fg, _storyboard_top, _storyboard_add_fg]:
		if layer != null:
			(layer as CanvasItem).self_modulate = tint


## 暂停时连 BGA 一起停；恢复后 _update_video 会把播放位置重新对齐。
func set_video_paused(value: bool) -> void:
	video_paused = value
	if _video != null:
		_video.paused = value


func _update_video(chart: Chart, beat: float) -> void:
	var path := chart.video_path
	if path.is_empty():
		_video_job_token += 1
		_video.visible = false
		_video.stream = null
		_refresh_background_layering()
		return
	if path != _last_video_path:
		_last_video_path = path
		_video_load_failed = false
		_video.stream = null
		_video.visible = false
		_video_job_token += 1
		var resolved := path
		if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
			if _app != null and not _app.chart_path.is_empty():
				resolved = ChartIO.resolve_path(_app.chart_path, path)
		_start_video_load(resolved, _video_job_token)
	_refresh_background_layering()
	if _video.stream == null:
		return
	_video.modulate = Color(1, 1, 1, video_alpha(chart.video_opacity, background_brightness))
	if not is_equal_approx(_video.speed_scale, playback_rate):
		_video.speed_scale = maxf(0.1, playback_rate)
	if video_paused:
		_video.paused = true
		return
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


## 有 BGA 时不叠加谱面背景图：两张背景一起画既脏又浪费。
func _refresh_background_layering() -> void:
	# 有 storyboard 时舞台底层（渐变星空）也要关：osu 里故事板背后就是纯黑，
	# 否则开场几秒会看到一块灰亮的渐变底色，像「亮屏」。
	var sb_active := show_storyboard and _storyboard != null
	if _bg != null:
		# 不能直接隐藏：底下的面板是浅色的，会露出白色。改成把渐变底色压成纯黑。
		_bg.visible = true
		_bg.modulate = Color(0.0, 0.0, 0.0, 1.0) if sb_active else Color.WHITE
	# 和 lazer 的 Storyboard.ReplacesBackground 一致：storyboard 的 Background 层里有谱面背景图时，
	# 静态背景层要关掉——否则故事板想做的「黑屏 / 淡入」永远被一张不漏的底图垫住。
	if sb_active and _storyboard_replaces_background and show_storyboard_background:
		_background_image.visible = false
		return
	_background_image.visible = background_image_visible(_background_image.texture != null, _video.stream != null)


## 优先直接解码（gdffmpeg）：mp4 / webm 等不再转码；解码库缺失才退回转码缓存。
func _start_video_load(resolved: String, token: int) -> void:
	var direct := ChartIO.video_stream_from_path(resolved)
	if direct != null:
		_attach_video(direct)
		return
	if MediaIO.is_native_video(resolved):
		_video_load_failed = true
		notice.emit("视频无法解码：%s" % resolved.get_file(), "warning")
		return
	if FileAccess.file_exists(MediaIO.video_cache_path(resolved)):
		_attach_video(ChartIO.video_stream_from_path(MediaIO.video_cache_path(resolved)))
		return
	var tree := get_tree()
	if tree == null:
		return
	notice.emit("没有直接解码库，后台转码中（不阻塞编辑）：%s" % resolved.get_file(), "info")
	var result := await MediaIO.prepare_video_async(resolved, tree)
	if token != _video_job_token or not is_inside_tree():
		return
	if result.is_empty():
		_video_load_failed = true
		notice.emit("视频不可用：%s" % MediaIO.last_error, "warning")
		return
	_attach_video(ChartIO.video_stream_from_path(result))


func _attach_video(stream: VideoStream) -> void:
	if stream == null:
		_video_load_failed = true
		_video.visible = false
		notice.emit("视频无法解码；保留路径，不影响编辑。", "warning")
		return
	_video.stream = stream
	_video.visible = true
	_video.play()
	_video.paused = true
	_refresh_background_layering()


## 每次进试玩都从干净的轨迹开始（上一局的擦除不能留到下局）。
func reset_path_cuts() -> void:
	path_cuts.clear()
	path_sector_cuts.clear()
	path_cut_versions.clear()
	_path_head_state.clear()
	_path_strokes.clear()
	clear_note_states()
	# 上一局的判定文字、命中火花和连击断连动画也会跟着重试活过来：一起清掉。
	_pulses.clear()
	_hud_combo_prev = 0
	_hud_combo_pop_at = -100000
	_hud_combo_break_at = -100000
	_hud_combo_broken = 0


## 星头判定结果：决定圆和下落星星什么时候开始淡出。
func set_path_head_state(note_id: int, hit: bool, beat: float) -> void:
	_path_head_state[note_id] = {"hit": hit, "beat": beat}
	if _overlay != null:
		_overlay.queue_redraw()


## 试玩判定结果："hit" / "miss" 让音符当帧退场；"holding" 让 hold 收起头部。
## beat 只给 hold 的 MISS 用：整条从这一刻起淡出。
func set_note_state(note_id: int, state: String, beat: float = NAN) -> void:
	note_states[note_id] = state
	if not is_nan(beat):
		note_state_beats[note_id] = beat
	if _overlay != null:
		_overlay.queue_redraw()


func note_state(note_id: int) -> String:
	return String(note_states.get(note_id, ""))


static func note_is_retired(state: String) -> bool:
	return state == "hit" or state == "miss"


func clear_note_states() -> void:
	_note_pops.clear()
	if note_states.is_empty():
		if _overlay != null:
			_overlay.queue_redraw()
		return
	note_states.clear()
	note_state_beats.clear()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_chart_changed() -> void:
	_sorted_notes_chart = null
	path_cuts.clear()
	path_sector_cuts.clear()
	_path_sector_cache.clear()
	_path_head_state.clear()
	note_states.clear()
	note_state_beats.clear()
	path_cut_versions.clear()
	_invalidate_path_index()
	_boundary_frame_cache = null
	_path_local_cache.clear()
	_max_design_radius = -1.0
	_mesh_dirty = true
	_last_video_path = ""
	_video_job_token += 1
	video_paused = false
	_last_background_path = ""
	_last_fit_key = ""
	_last_mesh_key = ""
	_force_3d_frame = true
	queue_redraw()


func _on_chart_live_changed() -> void:
	_sorted_notes_chart = null
	path_cuts.clear()
	path_sector_cuts.clear()
	_path_sector_cache.clear()
	_path_head_state.clear()
	path_cut_versions.clear()
	_invalidate_path_index()
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


## 只动形状/镜头：音符缓存（排序、Path 切割）全部保留，只更新环几何。
func _on_ring_live_changed() -> void:
	_boundary_frame_cache = null
	if _mesh_dirty:
		_max_design_radius = -1.0
		_last_fit_key = ""
		_avg_radius_key = ""
		_force_3d_frame = true
	if _overlay != null:
		_overlay.queue_redraw()
	# Note/region drags only change the overlay. Boundary dragging marks the
	# mesh dirty in _update_drag(), where the actual geometry is edited.
	if _mesh_dirty:
		_max_design_radius = -1.0
		_last_fit_key = ""
		_avg_radius_key = ""
		_force_3d_frame = true
	if _overlay != null:
		_overlay.queue_redraw()


## 环编辑一次提交（改形状/镜头/指令）：只重建环几何，音符缓存全部保留。
func _on_ring_changed() -> void:
	_on_ring_live_changed()
	_mesh_dirty = true
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
		_update_camera_fit(chart, float(view.get("zoom", 1.0)), float(view.get("ellipse", 1.0)),
			float(view.get("dolly", 1.0)))


func _on_mouse_entered() -> void:
	mouse_inside = true
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_update_cursor()
	_cursor_layer.queue_redraw()


func _on_mouse_exited() -> void:
	mouse_inside = false
	if not playtest_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_cursor_layer.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if ring_edit_mode and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			ring_zoom.emit(0.02)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ring_zoom.emit(-0.02)
			accept_event()
			return
	if event is InputEventMouseMotion:
		mouse_screen = event.position
		if _text_drag != null:
			_drag_text(event.position)
			accept_event()
			return
		if _ring_rotating:
			ring_rotate.emit((event.position.x - _ring_rot_last) * 0.4)
			_ring_rot_last = event.position.x
			accept_event()
			return
		if playtest_mode:
			_cursor_layer.queue_redraw()
			accept_event()
			return
		if interactive and not playtest_mode:
			if _drag_note != null:
				_update_note_angle_drag(event.position)
			elif _drag_vertex >= 0:
				_update_drag(event.position)
			elif _drag_visual >= 0:
				_update_visual_drag(event.position)
			elif _drawing_red:
				_update_cursor()
				_update_red_drag(event.position)
			elif _drawing_path:
				_append_path_point(event.position)
		if not _drawing_path:
			# 画 Path 时不需要光标吸附；省下来的 3.7ms 直接进帧预算。
			_update_cursor()
		_cursor_layer.queue_redraw()
		if _drag_vertex >= 0 or _drag_visual >= 0 or _drag_note != null or _drawing_red:
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
	if ring_edit_mode:
		var text_hit := _text_command_at(event.position)
		if text_hit != null:
			selected_command = text_hit
			command_selected.emit(text_hit)
			_text_drag = text_hit
			_text_drag_offset = event.position - _text_center(text_hit)
			_app.begin_edit()
			accept_event()
			return
		var vertex_pick := _pick_vertex(event.position)
		if vertex_pick >= 0:
			_drag_vertex = vertex_pick
			_app.select_segment(vertex_pick)
			_app.begin_edit()
			return
		if _pick_note(event.position) < 0:
			_ring_rotating = true
			_ring_rot_last = event.position.x
			_app.begin_edit()
			accept_event()
			return
	if _app.boundary_mode:
		if event.double_click:
			_split_segment()
			return
		var vertex := _pick_vertex(event.position)
		if vertex >= 0:
			_drag_vertex = vertex
			_app.select_segment(vertex)
			_app.begin_edit()
			return
		var segment_index := _nearest_segment_index(event.position)
		if segment_index >= 0:
			_app.select_segment(segment_index)
			return
	if _app.tool == "limit":
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
			_path_points.append(event.position)
		return
	if _app.tool in ["tap", "hold", "path", "anchor", "bell"]:
		if cursor_valid:
			_create_note(_app.tool)
		return
	if _app.tool == "select":
		var note_id := _pick_note(event.position)
		if note_id >= 0:
			_app.select_note(note_id)
			var note: Note = _app.get_selected_note()
			var cursor_deg := screen_angle_deg(event.position)
			if note != null and not note.lock and not is_nan(cursor_deg):
				_drag_note = note
				_drag_note_angle = note.angle
				_drag_note_tail = note.tail_angle
				_drag_note_cursor = cursor_deg
				_drag_group.clear()
				_drag_group_starts.clear()
				if note.type == "anchor":
					for item in _app.with_anchor_partners([note]):
						_drag_group.append(item)
						_drag_group_starts.append(item.angle)
				_app.begin_edit()


func _on_left_release(_event: InputEventMouseButton) -> void:
	if _text_drag != null:
		_text_drag = null
		if _app != null:
			_app.finish_edit()
	if _ring_rotating:
		_ring_rotating = false
		if _app != null:
			_app.finish_edit()
	if _drag_visual >= 0:
		_drag_visual = -1
		_drag_visual_note = null
		if _app != null:
			_app.finish_edit()
	if _drag_note != null:
		_snap_drag_note_group()
		_drag_note = null
		_drag_group.clear()
		_drag_group_starts.clear()
		if _app != null:
			_app.finish_edit()
	if _drag_vertex >= 0:
		_drag_vertex = -1
		if _app != null:
			_app.finish_edit()
		_warn_if_invalid()
	if _drawing_red:
		_drawing_red = false
		_red_region = null
		if _app != null:
			_app.finish_edit()
	if _drawing_path:
		_drawing_path = false
		_create_path()


func _update_drag(screen_position: Vector2) -> void:
	if _drag_vertex < 0:
		return
	var shape := _active_shape()
	if shape == null:
		return
	var design := _screen_to_ring_plane(screen_position)
	if not design.is_finite():
		return
	shape.set_vertex(_drag_vertex, design)
	_app.touch_ring_chart()
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
		var last_index: int = _drag_visual_note.trace_pts.size() - 1
		if not _drag_visual_note.path_controls_set:
			# 手绘 Path：只挪抓住的那一个点，别把整条手绘形状重建成二次曲线。
			var point: Dictionary = _drag_visual_note.trace_pts[_drag_visual]
			point["x"] = local.x
			point["y"] = local.y
			if _drag_visual == 0:
				_drag_visual_note.angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
			elif _drag_visual == last_index:
				_drag_visual_note.tail_angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		elif _drag_visual == last_index:
			# 尾巴手柄：径向拖 = 离心，切向拖 = 尾角。
			_drag_visual_note.tail_angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
			_drag_visual_note.set_path_centrifuge(clampf(local.length(), 0.0, 1.0))
		elif _drag_visual == 0:
			_drag_visual_note.angle = fposmod(rad_to_deg(atan2(local.y, local.x)), 360.0)
		else:
			# 轨迹中点：沿弦法向拖 = 轴长，走 setter 才不会和检查器打架。
			var tail := Vector2(cos(deg_to_rad(_drag_visual_note.tail_angle)),
				sin(deg_to_rad(_drag_visual_note.tail_angle))) * _drag_visual_note.path_centrifuge
			_drag_visual_note.set_path_axis(path_axis_from_drag(
				_drag_visual_note.path_head_point(), tail, local))
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


## 环上拖动音符：按光标绕环心转过的角度整体旋转，跨 0°/360° 也连续。
static func dragged_angle(start_angle: float, start_cursor_deg: float, cursor_deg: float) -> float:
	return fposmod(start_angle + JudgeMath.angle_delta(start_cursor_deg, cursor_deg), 360.0)


## 轨迹中点沿起终弦法向拖多远 → path_axis。与 derive_path_controls() 的
## 反解同一个量纲：1.0 = 弦长，正负决定弯向哪一侧。
static func path_axis_from_drag(head: Vector2, tail: Vector2, local: Vector2) -> float:
	var chord := tail - head
	var length := chord.length()
	if length <= 0.0001:
		return 0.0
	var normal := Vector2(-chord.y, chord.x) / length
	return clampf((local - (head + tail) * 0.5).dot(normal) / length, -2.0, 2.0)


func _update_note_angle_drag(screen: Vector2) -> void:
	if _drag_note == null:
		return
	var cursor_deg := screen_angle_deg(screen)
	if is_nan(cursor_deg):
		return
	var angle := dragged_angle(_drag_note_angle, _drag_note_cursor, cursor_deg)
	if _drag_group.size() > 1:
		# 整对 Anchor 一起转，夹角保持不变。
		var delta := JudgeMath.angle_delta(_drag_note_angle, angle)
		for i in _drag_group.size():
			_drag_group[i].angle = fposmod(_drag_group_starts[i] + delta, 360.0)
	else:
		_drag_note.angle = angle
		if _drag_note.type == "bell":
			_drag_note.center_u = angle / 360.0
		elif _drag_note.type == "path":
			_drag_note.tail_angle = fposmod(_drag_note_tail + JudgeMath.angle_delta(_drag_note_angle, angle), 360.0)
	_app.touch_chart()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## 环预览松手回吸：Anchor 整对旋转（组长吸竖线、伙伴跟转），其他音符不吸。
func _snap_drag_note_group() -> void:
	if _app == null or _drag_group.size() < 2 or _drag_note == null:
		return
	# 只是点了一下没拖动：不动它。
	if absf(JudgeMath.angle_delta(_drag_note_angle, _drag_note.angle)) <= 0.001:
		return
	var leader: Note = _drag_group[0]
	for note in _drag_group:
		if note.lock:
			return
		if note.id < leader.id:
			leader = note
	var delta: float = _app.snap_rail_u(fposmod(leader.angle, 360.0) / 360.0) * 360.0 - leader.angle
	if absf(delta) <= 0.001:
		return
	for note in _drag_group:
		note.angle = fposmod(note.angle + delta, 360.0)
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


## 绘制中只记屏幕点：不做投影、不做平滑，笔迹就是鼠标走过的原始轨迹。
func _append_path_point(screen: Vector2) -> void:
	if _path_points.is_empty() or _path_points[-1].distance_to(screen) > 3.0:
		_path_points.append(screen)


## 把绘制中记下的屏幕轨迹投影到环平面，再交给定型管线。
func _project_path_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for screen in _path_points:
		var design := _screen_to_ring_plane(screen)
		if not design.is_finite():
			continue
		var local := _design_to_path_local(design)
		if not local.is_finite():
			continue
		points.append(local.normalized() * clampf(local.length(), 0.06, 0.985))
	if points.size() >= 2:
		# 头必须与判定角度一致，投影误差不能留在这里。
		points[0] = Vector2(cos(deg_to_rad(_path_head_angle)), sin(deg_to_rad(_path_head_angle)))
	return points


## 松手定型：RDP 去抖动 → 拐角切段 → 段内 Chaikin → 等弧长重采样。
## 头尾点原样保留（它们决定 angle / tail_angle / centrifuge）。
static func finalize_path_points(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() < 3:
		return points.duplicate()
	var kept := _rdp_path(points, PATH_SMOOTH_RDP)
	if kept.size() < 3:
		return kept
	var cuts := _path_corners(kept, PATH_SMOOTH_CORNER_DEG)
	var out: Array[Vector2] = []
	var start := 0
	for cut in cuts:
		var piece: Array[Vector2] = kept.slice(start, cut + 1)
		var smoothed: Array[Vector2] = SentakkiSlide._chaikin(piece, 1)
		if out.is_empty():
			out.append_array(smoothed)
		else:
			out.append_array(smoothed.slice(1))
		start = cut
	var resampled := resample_path_points(out, PATH_SMOOTH_STEP, PATH_SMOOTH_MAX_POINTS)
	# 平滑后再夹半径：反过来 Chaikin 会把贴边的曲线拉进/顶出环面。
	var head := resampled[0]
	var tail := resampled[-1]
	for i in resampled.size():
		var r := clampf(resampled[i].length(), 0.06, 0.985)
		resampled[i] = resampled[i].normalized() * r
	resampled[0] = head
	resampled[-1] = tail
	return resampled


## 保留端点的 RDP。用显式栈，手画很长时也不会把调用栈压爆。
static func _rdp_path(points: Array[Vector2], epsilon: float) -> Array[Vector2]:
	if points.size() < 3:
		return points.duplicate()
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep.fill(0)
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var farthest := -1
		var farthest_distance := epsilon
		var a := points[span.x]
		var b := points[span.y]
		for i in range(span.x + 1, span.y):
			var distance := _point_segment_distance(points[i], a, b)
			if distance > farthest_distance:
				farthest_distance = distance
				farthest = i
		if farthest >= 0:
			keep[farthest] = 1
			stack.append(Vector2i(span.x, farthest))
			stack.append(Vector2i(farthest, span.y))
	var result: Array[Vector2] = []
	for i in points.size():
		if keep[i] == 1:
			result.append(points[i])
	return result


static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## 转折超过这个角度就算拐角：拐角点钉死，不跨角平滑（maimai 的 V 形要留住）。
static func _path_corners(points: Array[Vector2], corner_deg: float) -> Array[int]:
	var result: Array[int] = []
	var limit := cos(deg_to_rad(corner_deg))
	for i in range(1, points.size() - 1):
		var a := (points[i] - points[i - 1]).normalized()
		var b := (points[i + 1] - points[i]).normalized()
		if a.dot(b) < limit:
			result.append(i)
	result.append(points.size() - 1)
	return result


## 等弧长重采样：trace_local_at 是线性扫描，点数必须封顶。
static func resample_path_points(points: Array[Vector2], step: float, max_points: int) -> Array[Vector2]:
	if points.size() < 2:
		return points.duplicate()
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	if total <= 0.0001:
		return points.duplicate()
	var count := clampi(int(ceil(total / maxf(0.0001, step))) + 1, 2, max_points)
	var result: Array[Vector2] = []
	var step_length := total / float(count - 1)
	var walked := 0.0
	var index := 1
	for k in count:
		var target := step_length * float(k)
		while index < points.size() and walked + points[index].distance_to(points[index - 1]) < target:
			walked += points[index].distance_to(points[index - 1])
			index += 1
		if index >= points.size():
			result.append(points[-1])
			continue
		var segment := points[index].distance_to(points[index - 1])
		var q := 0.0 if segment <= 0.000001 else (target - walked) / segment
		result.append(points[index - 1].lerp(points[index], clampf(q, 0.0, 1.0)))
	return result


func _create_path() -> void:
	if _app == null:
		_path_points.clear()
		return
	var chart := get_chart()
	if chart == null or _path_points.is_empty():
		_path_points.clear()
		return
	var projected := _project_path_points()
	if projected.size() < 2:
		var angle := deg_to_rad(_path_head_angle + 60.0)
		projected = [
			Vector2(cos(deg_to_rad(_path_head_angle)), sin(deg_to_rad(_path_head_angle))),
			Vector2(cos(angle), sin(angle)) * 0.70,
		]
	var points := finalize_path_points(projected)
	var start: float = _app.snap_beat(get_time_beat())
	var note := Note.new("path", start, _path_head_angle, 62.0)
	note.id = chart.next_note_id()
	note.end_beat = start + 1.0
	note.tail_width = 45.0
	note.tolerance = 0.24
	note.samples_per_beat = 4.0
	note.space = "plane"
	note.tail_angle = fposmod(rad_to_deg(atan2(points[-1].y, points[-1].x)), 360.0)
	# db 按弧长分配：按索引均分会让画得慢的一段滑得更快，判定手感跟着变。
	var total_length := 0.0
	for i in range(1, points.size()):
		total_length += points[i].distance_to(points[i - 1])
	var walked := 0.0
	for i in points.size():
		var point := points[i]
		note.trace_pts.append({
			"x": point.x,
			"y": point.y,
			"db": note.duration() * walked / maxf(total_length, 0.0001),
		})
		if i < points.size() - 1:
			walked += points[i + 1].distance_to(points[i])
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
	var beat: float = _app.snap_grid_beat(get_time_beat())
	var angle := fposmod(_app.snap_rail_u(cursor_u) * 360.0, 360.0)
	var added: Array[Note] = []
	if type == "anchor":
		# Anchor 是双押配置：一次放两颗同拍反向的锚点。
		added = chart.make_anchor_pair(beat, angle)
	else:
		var note := Note.new(type, beat, angle, 60.0)
		note.id = chart.next_note_id()
		match type:
			"hold":
				note.end_beat = beat + 1.0
				note.hold = true
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
			"bell":
				note.width = Note.BELL_MAX_WIDTH
				note.center_u = cursor_u
				note.radius = 26.0
		added = [note]
	_app.begin_edit()
	for item in added:
		chart.notes.append(item)
	_app.finish_edit()
	_app.select_note(added[0].id)


func _pick_vertex(screen: Vector2) -> int:
	var shape := _active_shape()
	if shape == null:
		return -1
	var best := -1
	var best_distance := 18.0
	var points := shape.vertices()
	for index in points.size():
		var distance := project_design(points[index]).distance_to(screen)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## 松手后只提示，不回退：编辑中允许暂时不合法，保存/试玩时才拦。
func _warn_if_invalid() -> void:
	var shape := _active_shape()
	if shape == null:
		return
	var issues := shape.validate()
	if not issues.is_empty():
		notice.emit("%s（保存前需要修正）" % issues[0], "warning")


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
			"path":
				var head := _flying_position(chart, note.angle, note.beat, t, pre, note.group_id)
				var tail := _flying_position(chart, note.tail_angle, note.end_beat, t, pre, note.group_id)
				if head.distance_to(screen) < best_distance:
					best_distance = head.distance_to(screen)
					best = note.id
				if tail.distance_to(screen) < best_distance:
					best_distance = tail.distance_to(screen)
					best = note.id
			_:
				var u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
				var target := _flying_position(chart, u * 360.0, note.beat, t, pre, note.group_id)
				var boundary := project_u(u, t)
				var distance := minf(target.distance_to(screen), boundary.distance_to(screen))
				if note.type == "anchor":
					var progress: float = _note_progress(chart, note, t)
					var gem: Vector2 = _anchor_gem_position(boundary, lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress))
					distance = minf(distance, gem.distance_to(screen))
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
	if shape == null:
		return
	if shape.vertex_count() >= BoundaryShape.MAX_VERTICES:
		notice.emit("顶点数已达上限 %d" % BoundaryShape.MAX_VERTICES, "warning")
		return
	var index := _nearest_segment_index(mouse_screen)
	if index < 0:
		return
	_app.begin_edit()
	if shape.insert_vertex(index):
		_app.select_segment(mini(index + 1, shape.vertex_count() - 1))
	_app.finish_edit()
	_mesh_dirty = true


func _pre_read_beats(chart: Chart, beat: float) -> float:
	# 飞行时长换算成拍：只用于取窗口/画箭头，判定仍按毫秒。
	return _pre_read_ms(chart, beat) / 60000.0 * chart.timing.bpm_at(beat)


## 音符从出现到该打的时间（毫秒）：固定 1 秒 ÷ 音符速度倍率。
## 不随 BPM 变——高 BPM 只代表谱面更密，不代表要读得更快。
func _pre_read_ms(chart: Chart, _beat: float = 0.0) -> float:
	return maxf(30.0, chart.note_fall_ms() / maxf(0.05, flow_scale))


## 这个音符开始从圆心飞出的拍号（毫秒反推，变 BPM 处连续）。
func _group_base_bpm(chart: Chart, group_id: int = -1, beat: float = 0.0) -> float:
	if chart == null:
		return 120.0
	if group_id >= 0:
		var data := chart.group_data(group_id)
		if not data.is_empty() and float(data.get("bpm", 0.0)) > 0.0:
			return float(data["bpm"])
	return chart.timing.bpm_at(beat)


func _group_current_bpm(chart: Chart, group_id: int, beat: float) -> float:
	return chart.group_bpm_at(group_id, beat) if group_id >= 0 else chart.timing.bpm_at(beat)


## 组 BPM 只给非 0 组做差速：组 0 的 BPM 点就是谱面 timing，
## 让它参与速度会让换 BPM 的段落突然变速，回到之前“固定 1 秒”的行为。
func _group_travel_ms(chart: Chart, target_beat: float, group_id: int, base_ms: float) -> float:
	if group_id <= 0:
		return base_ms
	var base := maxf(1.0, _group_base_bpm(chart, group_id, target_beat))
	var current := maxf(1.0, _group_current_bpm(chart, group_id, target_beat))
	return base_ms * current / base


## 所有组里最慢的下落倍率：取窗口时要按它多回溯一段，否则慢组音符会
## 在预读窗口外生成，直到半路才突然出现。
func _max_group_speed_ratio(chart: Chart) -> float:
	var ratio := 1.0
	for group in chart.groups:
		var gid := int(group.get("id", 0))
		if gid <= 0:
			continue
		var base := maxf(1.0, _group_base_bpm(chart, gid, 0.0))
		for point in chart.group_bpm_points_for(gid):
			ratio = maxf(ratio, maxf(1.0, point.bpm) / base)
	return clampf(ratio, 1.0, 8.0)


func _spawn_beat(chart: Chart, target_beat: float, group_id: int = -1) -> float:
	# Base BPM defines the reference speed; a higher current BPM slows the
	# visual approach by (current / base). Beat conversion still follows the
	# chart timing map, otherwise a 230 BPM chart with a 120 BPM group falls
	# in half a second instead of one.
	var travel_ms := _group_travel_ms(chart, target_beat, group_id, _pre_read_ms(chart, target_beat))
	return chart.timing.spawn_beat(target_beat, travel_ms)


## 0..1 的接近进度（毫秒恒速，不会在变 BPM 时忽然跳到一半）。
func _approach(chart: Chart, target_beat: float, current_beat: float, group_id: int = -1) -> float:
	var travel_ms := _group_travel_ms(chart, target_beat, group_id, _pre_read_ms(chart, target_beat))
	return chart.timing.approach(target_beat, current_beat, travel_ms)


## 星星从圆心落到环上的时长（固定 0.5 秒，换算成拍；不超过预读）。
func _star_fall_beats(chart: Chart, beat: float) -> float:
	var pre := _pre_read_beats(chart, beat)
	var bpm := chart.timing.bpm_at(beat)
	return clampf(0.5 * bpm / 60.0, 0.15, maxf(0.15, pre))


## 星星开始下落（落到环上 0.5 秒前）的拍号。
func _fall_beat(chart: Chart, target_beat: float, group_id: int = -1) -> float:
	var travel_ms := _group_travel_ms(chart, target_beat, group_id,
		minf(_pre_read_ms(chart, target_beat), 500.0))
	return chart.timing.spawn_beat(target_beat, travel_ms)


func _flying_position(chart: Chart, angle: float, target_beat: float, current_beat: float, _pre: float, group_id: int = -1) -> Vector2:
	var u := fposmod(angle, 360.0) / 360.0
	var boundary := project_u(u, current_beat)
	var center := project_design(Vector2.ZERO)
	return center.lerp(boundary, _approach(chart, target_beat, current_beat, group_id))


func _update_cursor_trail(delta: float) -> void:
	for i in range(_cursor_trail.size() - 1, -1, -1):
		var age := float(_cursor_trail[i].get("age", 0.0)) + delta
		_cursor_trail[i]["age"] = age
		if age > 0.26:
			_cursor_trail.remove_at(i)
	if not mouse_inside:
		_cursor_trail.clear()
		return
	var moved := _last_mouse_screen.distance_to(mouse_screen)
	if moved <= 1.0:
		return
	_cursor_trail.append({"pos": mouse_screen, "age": 0.0})
	# 拖尾长度按画质项；快速划动时再缩短，减少绘制量。
	var cap := 28
	match cursor_trail_mode:
		"off":
			_cursor_trail.clear()
			return
		"short":
			cap = 12
	if moved > 60.0:
		cap = mini(cap, 8)
	while _cursor_trail.size() > cap:
		_cursor_trail.pop_front()


func _update_cursor() -> void:
	var chart := get_chart()
	if chart == null:
		return
	if playtest_mode:
		# 试玩完全按鼠标屏幕位置判定（osu 式自由移动），不再反解环上角度。
		# 仍要刷新平均半径缓存：音符缩放和光标尺寸都靠它。
		var center_pt := project_design(Vector2.ZERO)
		var average_key := "%s|%s|%.0f|%.0f" % [_mesh_key(chart, get_time_beat()), _last_view_key, size.x, size.y]
		if average_key != _avg_radius_key:
			_avg_radius_key = average_key
			var total := 0.0
			var counted := 0
			var samples := 12
			for i in samples:
				var sample_point := project_u(float(i) / float(samples), get_time_beat())
				if _valid_point(sample_point):
					total += sample_point.distance_to(center_pt)
					counted += 1
			_avg_radius_cache = total / float(maxi(1, counted)) if counted > 0 else 100.0
		cursor_valid = true
		return
	var t := get_time_beat()
	# 鼠标和边界几何都没变时，直接复用上一帧的 u，避免每帧 96 次反解。
	var cache_key := "%s|%.1f|%.1f|%s" % [_mesh_key(chart, t), mouse_screen.x, mouse_screen.y, _last_view_key]
	if cache_key == _cursor_cache_key:
		return
	_cursor_cache_key = cache_key
	var result := BoundaryRuntime.nearest_u(chart, t, mouse_screen, func(point: Vector2) -> Vector2: return project_design(point), 48, _frame_for(chart, t))
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
	# 判定环吸附范围：环内整片 + 环外再留一大段缓冲，边缘稍偏也不会失效。
	var threshold := maxf(64.0, average * 0.75)
	var inside_circle := mouse_screen.distance_to(center) <= average * 1.15
	var near_center := mouse_screen.distance_to(center) < average * 0.05
	var valid := (inside_circle or distance <= threshold) and not near_center
	if playtest_mode:
		# 外环：内圈外整片有效，鼠标离开环/舞台后仍按最近 u 判定。
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
			_last_fit_key = ""
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


func draw_overlay(canvas: Control) -> void:
	var chart := get_chart()
	var t := get_time_beat()
	# 切换谱面或移出滤镜区间时也要隐藏处理层。
	_apply_filters(chart, t)
	if chart == null:
		return
	var started_usec := Time.get_ticks_usec()
	var pre := _pre_read_beats(chart, t)
	if not use_3d_ring:
		_draw_flat_stage(canvas, chart, t)
		_draw_flat_ring(canvas, chart, t)
	if not use_3d_ring:
		_draw_bezel(canvas, chart, t)
	var t_bar := Time.get_ticks_usec()
	_draw_bar_lines(canvas, chart, t, pre)
	_draw_red_regions(canvas, chart, t)
	_perf_sections[6] += Time.get_ticks_usec() - t_bar
	# 图层顺序：滑条底带 → Path → Hold → Tap/Anchor/Bell，命中目标始终在上层。
	# Combo 单独压在音符层下面，下落音符可以盖住它；左右两列仍在 HUD 层。
	if playtest_mode and show_hud:
		_draw_play_combo_layer(canvas)
	var draw_note_layers := show_notes and not ring_drag_low_detail
	var sec_usec := Time.get_ticks_usec()
	if draw_note_layers:
		_draw_seeks(canvas, chart, t)
	var sec2 := Time.get_ticks_usec()
	_perf_sections[0] += sec2 - sec_usec
	if draw_note_layers:
		_draw_paths(canvas, chart, t, pre)
	sec_usec = Time.get_ticks_usec()
	_perf_sections[1] += sec_usec - sec2
	if draw_note_layers:
		_draw_holds(canvas, chart, t, pre)
	sec2 = Time.get_ticks_usec()
	_perf_sections[2] += sec2 - sec_usec
	if draw_note_layers:
		_draw_notes(canvas, chart, t, pre)
	_draw_alpha_commands(canvas, chart, t)
	if ring_edit_mode:
		_draw_selected_command_guides(canvas, chart, t)
	if show_path_judgement and draw_note_layers:
		_draw_path_judgement(canvas, chart, t, pre)
	_draw_ring_lights(canvas, t)
	if draw_note_layers:
		_draw_note_pops(canvas)
	sec_usec = Time.get_ticks_usec()
	_perf_sections[3] += sec_usec - sec2
	var t_hud := Time.get_ticks_usec()
	_draw_onion(canvas, chart, t)
	_draw_boundary_controls(canvas, chart)
	if show_hud:
		_draw_hud(canvas, chart, t)
	_perf_sections[5] += Time.get_ticks_usec() - t_hud
	sec2 = Time.get_ticks_usec()
	_draw_pulses(canvas)
	_perf_sections[4] += Time.get_ticks_usec() - sec2
	if show_debug:
		_draw_debug(canvas, chart, t)
	_perf_draw_usec += Time.get_ticks_usec() - started_usec
	_perf_frames += 1


## 光标层：鼠标移动时只重绘这里。
func draw_cursor_overlay(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var t_cursor := Time.get_ticks_usec()
	# 绘制中的原始鼠标轨迹：屏幕坐标直接用，不投影、不重绘整层预览。
	if _drawing_path and _path_points.size() > 1:
		var trail := PackedVector2Array(_path_points)
		canvas.draw_polyline(trail, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.28), 7.0, false)
		canvas.draw_polyline(trail, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.85), 2.0, false)
	_draw_cursor(canvas, chart, get_time_beat())
	_perf_sections[7] += Time.get_ticks_usec() - t_cursor


## 试玩把 _chart_ms 的耗时（含每次按键查询）累加进来，便于判断音频是不是瓶颈。
func note_audio_usec(usec: int) -> void:
	_perf_sections[8] += usec


## Match the timeline's bar grid, including local time-signature changes.
static func bar_line_beats(timing: TimingMap, beat: float, pre: float) -> Array[float]:
	var result: Array[float] = []
	if pre <= 0.0:
		return result
	for index in range(maxi(0, ceili(beat)), floori(beat + pre) + 1):
		if index % timing.beats_per_bar_at(float(index)) == 0:
			result.append(float(index))
	return result


func _draw_bar_lines(canvas: Control, chart: Chart, beat: float, pre: float) -> void:
	if not bar_lines_visible:
		return
	var bars := bar_line_beats(chart.timing, beat, pre)
	if bars.is_empty():
		return
	# Reuse the boundary evaluator for every ring; scale before camera projection
	# so the lines follow deformations and tilt exactly like the note bands.
	var frame := _frame_for(chart, beat)
	var boundary: Array[Dictionary] = []
	for i in 72:
		boundary.append(frame.point_at(float(i) / 72.0))
	# Reuse the exact start point: evaluating u=1 can select the first
	# segment but interpolate its far endpoint, leaving a spur at the seam.
	boundary.append(boundary[0])
	for target in bars:
		var progress := clampf(1.0 - (target - beat) / pre, 0.0, 1.0)
		var alpha := 0.58 * smoothstep(0.0, 0.15, progress)
		if alpha <= 0.001:
			continue
		var run := PackedVector2Array()
		for item in boundary:
			var point := project_design((item["point"] as Vector2) * progress)
			if bool(item.get("gap", false)) or not _valid_point(point):
				if run.size() > 1:
					canvas.draw_polyline(run, Color(1, 1, 1, alpha), 1.2, true)
				run = PackedVector2Array()
			else:
				run.append(point)
		if run.size() > 1:
			canvas.draw_polyline(run, Color(1, 1, 1, alpha), 1.2, true)


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


## 统一开关所有故事板图层（画布 + 加色 + 前景 + Overlay）。
func set_storyboard_visible(on: bool) -> void:
	show_storyboard = on
	for layer in [_storyboard_bg, _storyboard_add_bg, _storyboard_fg, _storyboard_top, _storyboard_add_fg]:
		if layer != null:
			layer.visible = on
	refresh_storyboard_layers()


## 编辑 / 换谱后重画所有故事板层（暂停时没有 time_changed，不会自动重绘）。
func refresh_storyboard_layers() -> void:
	# 宽屏/普通场是解析完才确定的，安全框矩形要跟着重算，否则会停在 640×480。
	_update_storyboard_clip_rects()
	# 换谱/解析完成时相机取景半径可能还没算过，这里补一次（和故事板开关无关）。
	var chart := get_chart()
	if chart != null:
		var view := current_view()
		_update_camera_fit(chart, float(view.get("zoom", 1.0)), float(view.get("ellipse", 1.0)),
			float(view.get("dolly", 1.0)))
	_queue_storyboard_redraw()


func _queue_storyboard_redraw() -> void:
	for layer in [_storyboard_bg, _storyboard_add_bg, _storyboard_fg, _storyboard_top, _storyboard_add_fg]:
		if layer != null:
			layer.queue_redraw()


## 谱面切换时重建 storyboard 缓存。
## 换谱/切标签后把故事板缓存清掉并重画（否则会一直显示上一个谱的故事板层）。
func invalidate_storyboard() -> void:
	_storyboard_chart = null
	_storyboard = null
	_storyboard_dir = ""
	_sb_waiting_dir = ""
	_storyboard_replaces_background = false
	_sb_sample_ms = -1.0e9
	_sb_queued_ms = -1.0e9
	_sb_priority_ms = INF
	_sb_all_textures_cached = false
	_sb_paths.clear()
	_sb_render_items = []
	_refresh_background_layering()
	_update_storyboard_clip_rects()
	if _storyboard_bg != null:
		_storyboard_bg.queue_redraw()
	if _storyboard_add_bg != null:
		_storyboard_add_bg.queue_redraw()
	if _storyboard_fg != null:
		_storyboard_fg.queue_redraw()
	if _storyboard_top != null:
		_storyboard_top.queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _ensure_storyboard(chart: Chart) -> void:
	if chart == _storyboard_chart:
		return
	_storyboard_chart = chart
	_storyboard = null
	_storyboard_dir = ""
	_sb_waiting_dir = ""
	_storyboard_replaces_background = false
	_sb_sample_ms = -1.0e9
	_sb_render_items = []
	_sb_queued_ms = -1.0e9
	_sb_priority_ms = INF
	_sb_priority.clear()
	_sb_priority_index = 0
	_sb_all_textures_cached = false
	_sb_paths.clear()
	if chart == null:
		_refresh_background_layering()
		return
	var dir := String(chart.metadata.get("storyboard", ""))
	if dir.is_empty():
		_refresh_background_layering()
		return
	if not _board_cache.has(dir):
		_start_parse(dir)
		_sb_waiting_dir = dir
		_refresh_background_layering()
		return
	var board: Storyboard = _get_cached_storyboard(dir)
	if board == null:
		_refresh_background_layering()
		return
	_storyboard = board
	_storyboard_dir = dir
	_sb_wide_detected = _detect_wide(board)
	_update_storyboard_clip_rects()
	_storyboard_replaces_background = _storyboard.replaces_background(String(chart.metadata.get("background", "")))
	_refresh_background_layering()

## READY 等待开场素材。后续素材跟着时间轴提前请求。
func preload_storyboard_textures(opening_end_ms: float) -> bool:
	var chart: Chart = get_chart()
	if chart == null:
		return true
	return _update_storyboard_textures(chart, get_time_beat(), opening_end_ms)


func _update_storyboard_textures(chart: Chart, beat: float, opening_end_ms: float = -INF) -> bool:
	var now: int = Time.get_ticks_msec()
	if not show_storyboard:
		_trim_storyboard_textures(now)
		return true
	_finish_storyboard_parses()
	_ensure_storyboard(chart)
	_take_parsed_board()
	if _storyboard == null:
		_trim_storyboard_textures(now)
		return _sb_waiting_dir.is_empty()
	if now - _sb_keepalive_ms >= 500:
		_sb_keepalive_ms = now
		# CanvasItem keeps its draw commands while paused, so a visible
		# sprite can remain on screen without touching the texture getter.
		for item in _sb_render_items:
			if show_storyboard_background or String(item["layer"]) not in ["Background", "Video"]:
				keep_storyboard_texture(_storyboard_asset_path(String(item["path"])), now)
		for full in _sb_priority:
			keep_storyboard_texture(full, now)
	pump_storyboard_textures()
	if _sb_texture_generation != _tex_generation:
		_sb_texture_generation = _tex_generation
		_queue_storyboard_redraw()
	if _sb_eviction_generation != _tex_eviction_generation:
		_sb_eviction_generation = _tex_eviction_generation
		_sb_priority_ms = INF
		_sb_all_textures_cached = false
	if _sb_all_textures_cached:
		return true
	var ms: float = chart.timing.beat_to_chart_ms(beat) - chart.offset_ms
	if absf(ms - _sb_priority_ms) >= Storyboard.BUCKET_MS or opening_end_ms > _sb_priority_until:
		_sb_priority_ms = ms
		_sb_priority.clear()
		_sb_priority_index = 0
		var end_ms: float = maxf(ms + 1000.0, opening_end_ms)
		_sb_priority_until = end_ms
		var seen: Dictionary = {}
		var has_missing_texture: bool = false
		for sprite: Storyboard.Sprite in _storyboard.sprites:
			if sprite.commands.is_empty():
				continue
			var full: String = _storyboard_asset_path(sprite.path)
			var cached: bool = _tex_cache.has(full)
			has_missing_texture = has_missing_texture or not cached
			if not show_storyboard_background and sprite.layer in ["Background", "Video"]:
				continue
			if sprite.start_time > end_ms or sprite.end_time < ms:
				continue
			if cached:
				_tex_last_used[full] = now
				continue
			if not seen.has(full):
				seen[full] = true
				_sb_priority.append(full)
		_sb_all_textures_cached = not has_missing_texture
	while _sb_priority_index < _sb_priority.size():
		var full: String = _sb_priority[_sb_priority_index]
		if _tex_cache.has(full):
			_sb_priority_index += 1
			continue
		for i in range(_sb_priority_index, mini(_sb_priority_index + 2, _sb_priority.size())):
			request_storyboard_texture(_sb_priority[i])
		return false
	return true


func _storyboard_asset_path(reference: String) -> String:
	if not _sb_paths.has(reference):
		_sb_paths[reference] = _storyboard_dir.path_join(reference.get_file())
	return _sb_paths[reference]


static func invalidate_storyboard_source(dir: String) -> void:
	_board_cache.erase(dir)
	_parse_revisions[dir] = int(_parse_revisions.get(dir, 0)) + 1


## 后台解析：同一目录只排一次。
func _start_parse(dir: String) -> void:
	if _board_cache.has(dir) or _parse_pending.has(dir):
		return
	_parse_pending[dir] = {
		"task": WorkerThreadPool.add_task(_parse_board.bind(dir), false, "storyboard parse"),
		"revision": int(_parse_revisions.get(dir, 0)),
	}


static func _parse_board(dir: String) -> void:
	var board: Storyboard = Storyboard.load_file(dir.path_join("storyboard.osb"))
	if board != null and board.sprites.is_empty():
		board = null
	_parse_mutex.lock()
	_parse_done[dir] = board
	_parse_mutex.unlock()


static func _finish_storyboard_parses() -> void:
	for dir: String in _parse_pending.keys():
		var job: Dictionary = _parse_pending[dir]
		var task: int = job["task"]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_parse_pending.erase(dir)
		_parse_mutex.lock()
		if int(job["revision"]) == int(_parse_revisions.get(dir, 0)):
			_cache_storyboard(dir, _parse_done.get(dir))
		_parse_done.erase(dir)
		_parse_mutex.unlock()


## 主线程把解析结果换上来（只在同一个谱面/目录还在等的时候）。
func _take_parsed_board() -> void:
	var dir: String = _sb_waiting_dir
	if dir.is_empty():
		return
	if not _board_cache.has(dir):
		_start_parse(dir)
		return
	_sb_waiting_dir = ""
	var board: Storyboard = _get_cached_storyboard(dir)
	if board == null:
		return
	_storyboard = board
	_storyboard_dir = dir
	_sb_wide_detected = _detect_wide(board)
	var chart := get_chart()
	if chart != null:
		_storyboard_replaces_background = _storyboard.replaces_background(String(chart.metadata.get("background", "")))
	_refresh_background_layering()
	_update_storyboard_clip_rects()
	_queue_storyboard_redraw()


static func _cache_storyboard(dir: String, board: Storyboard) -> void:
	_board_cache.erase(dir)
	_board_cache[dir] = board
	if _board_cache.size() > STORYBOARD_BOARD_CACHE_LIMIT:
		_board_cache.erase(_board_cache.keys()[0])


static func _get_cached_storyboard(dir: String) -> Storyboard:
	var board: Storyboard = _board_cache[dir]
	_cache_storyboard(dir, board)
	return board


static func storyboard_texture(full: String) -> Texture2D:
	if not _tex_cache.has(full):
		request_storyboard_texture(full)
		return null
	_tex_last_used[full] = Time.get_ticks_msec()
	return _tex_cache[full]


static func keep_storyboard_texture(full: String, now: int) -> void:
	if _tex_cache.has(full):
		_tex_last_used[full] = now


static func _cache_storyboard_texture(full: String, image: Image, boost: float, now: int) -> void:
	var bytes: int = 0
	var texture: Texture2D = null
	if image != null:
		texture = ImageTexture.create_from_image(image)
		# RGB images may occupy four bytes per pixel after upload.
		bytes = maxi(image.get_data_size(), image.get_width() * image.get_height() * 4)
		_tex_boost[full] = boost
	else:
		_tex_boost.erase(full)
	_tex_cache[full] = texture
	_tex_cache_bytes += bytes - _tex_sizes.get(full, 0)
	_tex_sizes[full] = bytes
	_tex_last_used[full] = now
	_tex_generation += 1


static func _trim_storyboard_textures(now: int, byte_budget: int = STORYBOARD_TEXTURE_BUDGET) -> void:
	if _tex_cache_bytes <= byte_budget and _tex_cache.size() <= STORYBOARD_TEXTURE_ENTRY_LIMIT:
		return
	if now < _tex_next_trim_ms:
		return
	_tex_next_trim_ms = now + 250
	# Allow a temporary overage if the current scene needs more than the budget.
	# Evicting recently drawn or prefetched sprites would force reloads mid-song.
	var paths: Array[String] = _tex_last_used.keys()
	paths.sort_custom(func(a: String, b: String) -> bool: return _tex_last_used[a] < _tex_last_used[b])
	for full in paths:
		if now - _tex_last_used[full] < STORYBOARD_TEXTURE_GRACE_MS:
			break
		_tex_cache_bytes -= _tex_sizes[full]
		_tex_sizes.erase(full)
		_tex_last_used.erase(full)
		_tex_boost.erase(full)
		_tex_cache.erase(full)
		_tex_eviction_generation += 1
		if _tex_cache_bytes <= byte_budget and _tex_cache.size() <= STORYBOARD_TEXTURE_ENTRY_LIMIT:
			break


## 把一张图排进后台解码队列（同一张只排一次）。
static func request_storyboard_texture(full: String) -> void:
	if _tex_cache.has(full) or _tex_pending.has(full):
		return
	if _tex_pending.size() >= 2:
		return
	_tex_pending[full] = WorkerThreadPool.add_task(_decode_texture.bind(full), false, "storyboard texture")


## 限制所有消费者合计每帧只上传一张大图，解码完成的任务也占队列位置。
static func pump_storyboard_textures() -> void:
	var now: int = Time.get_ticks_msec()
	_trim_storyboard_textures(now)
	var frame: int = Engine.get_process_frames()
	if _tex_upload_frame == frame:
		return
	for full: String in _tex_pending.keys():
		var task: int = _tex_pending[full]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		WorkerThreadPool.wait_for_task_completion(task)
		_tex_pending.erase(full)
		_tex_mutex.lock()
		var entry: Array = _tex_decoded.get(full, [])
		_tex_decoded.erase(full)
		_tex_mutex.unlock()
		var image: Image = entry[0] if not entry.is_empty() else null
		var boost: float = float(entry[1]) if image != null else 1.0
		_cache_storyboard_texture(full, image, boost, now)
		if image != null:
			_tex_upload_frame = frame
			return


static func _decode_texture(full: String) -> void:
	var image: Image = null
	var boost := 1.0
	if FileAccess.file_exists(full):
		image = Image.load_from_file(ProjectSettings.globalize_path(full))
		if image != null and not image.is_empty():
			var longest := maxi(image.get_width(), image.get_height())
			if longest > STORYBOARD_TEX_MAX:
				boost = float(longest) / float(STORYBOARD_TEX_MAX)
				var ratio := float(STORYBOARD_TEX_MAX) / float(longest)
				image.resize(maxi(1, roundi(float(image.get_width()) * ratio)),
					maxi(1, roundi(float(image.get_height()) * ratio)), Image.INTERPOLATE_BILINEAR)
		else:
			image = null
	_tex_mutex.lock()
	_tex_decoded[full] = [image, boost]
	_tex_mutex.unlock()


## 把 storyboard 的 640x480 坐标场映射到预览区域：
## osu 是按 **高度** 缩放、场中心对齐屏幕中心（宽屏只是左右多露出来），
## 不是 cover——之前用 max() 会把 1920x540 这种横条撑满整屏，把背景图盖死。
func _storyboard_sample_interval() -> float:
	if storyboard_sample_hz > 0:
		return 1000.0 / float(storyboard_sample_hz)
	var cap := int(Engine.max_fps)
	if cap <= 0:
		cap = 60
	cap = clampi(cap, 30, 120)
	return 1000.0 / float(cap)


func _storyboard_layout(view_size: Vector2) -> Dictionary:
	var field := _storyboard_field_width()
	# 绘制节点就是安全框：按高度缩放，场心 320,240 对齐自己的中心。
	var scale := view_size.y / Storyboard.FIELD_HEIGHT
	var field_center := Vector2(Storyboard.FIELD_WIDTH, Storyboard.FIELD_HEIGHT) * 0.5
	var offset := view_size * 0.5 - field_center * scale
	return {"scale": scale, "offset": offset}


## osu 的宽屏故事板是 854x480，普通的是 640x480；用错会让整张图右移 107 单位。
func _storyboard_field_width() -> float:
	var chart := get_chart()
	if chart != null and bool(chart.metadata.get("widescreen", false)):
		return Storyboard.FIELD_WIDTH_WIDE
	return Storyboard.FIELD_WIDTH_WIDE if _sb_wide_detected else Storyboard.FIELD_WIDTH


## 老谱面导入时没存 WidescreenStoryboard：按内容猜一次。
## 854 场的故事板一定有 x > 640 的元素（4:3 的不会超过 640）。
## 老谱面导入时没存 WidescreenStoryboard：按内容猜一次。
## 注意解析后的命令名是 move/x，不是文件里的 M/MX；只查大写字母会永远判成 4:3，
## 结果试玩按 640×480 裁、把宽屏故事板两侧切掉。
static func _detect_wide(board: Storyboard) -> bool:
	for sprite in board.sprites:
		if sprite.pos.x > 641.0 or sprite.pos.x < -1.0:
			return true
		for command in sprite.commands:
			if command.kind_name in ["move", "x"]:
				for side in [command.from, command.to]:
					if side.size() > 0 and (float(side[0]) > 641.0 or float(side[0]) < -1.0):
						return true
			# shortcut: 没有 WidescreenStoryboard 的旧谱只能猜。
			# 宽屏故事板用 2×2 白点 + V 拉到 427（=854 设计宽）；4:3 的会拉 320。
			if command.kind_name == "vector":
				for side in [command.from, command.to]:
					if side.size() > 0 and float(side[0]) > 400.0:
						return true
	return false


##
## Background/Fail/Pass 在判定环下面，用一层黑色遮罩；
## Foreground/Overlay 在判定环上面，加黑色遮罩会把环也一起压掉，
## 所以这三层改成把自身颜色乘暗（self_modulate），只影响故事板自己的像素。
func draw_storyboard_background(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	_draw_storyboard_layers(canvas, chart, get_time_beat(), ["Video", "Background", "Fail", "Pass"], false)


## 背景层的加色元素（粒子 / 光晕）。
func draw_storyboard_additive_background(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	_draw_storyboard_layers(canvas, chart, get_time_beat(), ["Video", "Background", "Fail", "Pass"], true)


## Foreground 层：判定环之上、音符之下。
func draw_storyboard_front(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	_draw_storyboard_layers(canvas, chart, get_time_beat(), ["Foreground"], false)


## Overlay 层：压在音符上面。
func draw_storyboard_overlay(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	_draw_storyboard_layers(canvas, chart, get_time_beat(), ["Overlay"], false)


## 前景的加色元素。
func draw_storyboard_additive_front(canvas: Control) -> void:
	var chart := get_chart()
	if chart == null:
		return
	_draw_storyboard_layers(canvas, chart, get_time_beat(), ["Foreground", "Overlay"], true)


## osu! storyboard 图层：按图层名过滤后绘制。
func _draw_storyboard_layers(canvas: Control, chart: Chart, t: float, layers: Array, additive_only: bool = false) -> void:
	if not show_storyboard:
		return
	_ensure_storyboard(chart)
	if _storyboard == null:
		return
	var skip_background := not show_storyboard_background
	var ms := chart.timing.beat_to_chart_ms(t) - chart.offset_ms
	if absf(ms - _sb_sample_ms) >= maxf(0.0001, _sb_sample_interval):
		_sb_sample_ms = ms
		_sb_render_items = _storyboard.sample(ms)
		_sb_layer_items.clear()
		_sb_additive_layer_items.clear()
		for entry in _sb_render_items:
			var key := String(entry["layer"])
			var target := _sb_additive_layer_items if bool(entry.get("additive", false)) else _sb_layer_items
			if not target.has(key):
				target[key] = []
			(target[key] as Array).append(entry)
	var view_size := canvas.size
	var layout := _storyboard_layout(view_size)
	var scale: float = layout["scale"]
	var offset: Vector2 = layout["offset"]
	var source: Dictionary = _sb_additive_layer_items if additive_only else _sb_layer_items
	for layer_name in layers:
		var group: Array = source.get(layer_name, [])
		if skip_background and (layer_name == "Background" or layer_name == "Video"):
			continue
		for item in group:
			var full: String = _storyboard_asset_path(String(item["path"]))
			var texture: Texture2D = storyboard_texture(full)
			if texture == null:
				continue
			var sprite_size := Vector2(texture.get_width(), texture.get_height())
			var anchor := _storyboard_anchor(int(item["origin"]), sprite_size)
			var pos: Vector2 = offset + (item["pos"] as Vector2) * scale
			var sprite_scale: Vector2 = item["scale"] * scale * float(_tex_boost.get(full, 1.0))
			var rotation := deg_to_rad(float(item["rotation"]))
			# 屏幕外的 sprite 直接丢掉：storyboard 里数百张图会一直“可见”，
			# 大部分已经被 M 命令挪出画面，不剔除的话每帧白画几百次。
			if not storyboard_sprite_intersects(view_size, pos, sprite_size, anchor, sprite_scale, rotation):
				continue
			var colour := storyboard_item_colour(item, sprite_size, sprite_scale, view_size)
			canvas.draw_set_transform(pos, rotation, sprite_scale)
			canvas.draw_texture(texture, -anchor, colour)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func storyboard_sprite_intersects(view: Vector2, pos: Vector2, sprite_size: Vector2, anchor: Vector2, scale: Vector2, rotation: float) -> bool:
	var center: Vector2 = pos + ((sprite_size * 0.5 - anchor) * scale).rotated(rotation)
	var radius: float = (sprite_size * scale).length() * 0.5 + 4.0
	return Rect2(Vector2.ZERO, view).grow(radius).has_point(center)

## 故事板对象的最终颜色（画布和预览必须共用这一份，否则两边观感对不上）。
## osu 里 P,A 是真正的加色；这里统一压到 35%，否则几百张全屏图叠加会把画面刷白。
## shortcut: 加色统一 0.35 增益，osu 精确混合后再调；等有人反馈“闪光不够亮”再改。
static func storyboard_item_colour(item: Dictionary, sprite_size: Vector2, sprite_scale: Vector2, canvas_size: Vector2) -> Color:
	var colour: Color = item["colour"]
	if colour.r > 0.94 and colour.g > 0.94 and colour.b > 0.94:
		# 2x2 的白点放大铺满屏幕：原本是纯白遮罩，按纯白画会在转场时刺眼。
		if sprite_size.x * sprite_size.y <= 16.0 and sprite_scale.x > canvas_size.x * 0.5:
			colour = Color(0.0, 0.0, 0.0, colour.a)
	colour.a = clampf(float(item["alpha"]), 0.0, 1.0) * colour.a
	if bool(item.get("additive", false)):
		colour.a *= 0.35
	return colour


static func _storyboard_anchor(origin: int, sprite_size: Vector2) -> Vector2:
	match origin:
		0:
			return Vector2.ZERO
		1:
			return Vector2(sprite_size.x * 0.5, 0.0)
		2:
			return Vector2(sprite_size.x, 0.0)
		3:
			return Vector2(0.0, sprite_size.y * 0.5)
		4:
			return sprite_size * 0.5
		5:
			return Vector2(sprite_size.x, sprite_size.y * 0.5)
		6:
			return Vector2(0.0, sprite_size.y)
		7:
			return Vector2(sprite_size.x * 0.5, sprite_size.y)
		8:
			return sprite_size
	return Vector2.ZERO


func _draw_flat_stage(canvas: Control, chart: Chart, t: float) -> void:
	var affine := _screen_affine()
	for radius in [360.0, 420.0, 620.0]:
		var points := PackedVector2Array()
		for i in 97:
			var a := TAU * float(i) / 96.0
			points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
		if points.size() > 1:
			canvas.draw_polyline(points, Color(0.56, 0.62, 0.72, 0.08), 1.0, false)
	for angle in [-135.0, -45.0, 45.0, 135.0]:
		var a := deg_to_rad(angle)
		for offset in [-2.0, 2.0]:
			var normal: Vector2 = Vector2(-sin(a), cos(a)) * offset
			var p0 := _affine_point(Vector2(cos(a), sin(a)) * 520.0 + normal, affine)
			var p1 := _affine_point(Vector2(cos(a), sin(a)) * 590.0 + normal, affine)
			canvas.draw_line(p0, p1, Color(0.56, 0.62, 0.72, 0.10), 1.0, false)


func _draw_flat_ring(canvas: Control, chart: Chart, t: float) -> void:
	var points := _frame_for(chart, t).sample_points(192)
	var jline := jline_state(chart, t)
	var main_color := Color(0.55, 0.60, 0.70, 0.95)
	var glow_color := Color(0.37, 0.85, 0.81, 0.10)
	var highlight := Color(1, 1, 1, 0.18)
	var main_width := RING_WIDTH
	var glow_width := GLOW_WIDTH
	if bool(jline.get("active", false)):
		var color: Color = jline.get("color", Color.WHITE)
		var alpha := clampf(float(jline.get("alpha", 1.0)), 0.0, 1.0)
		main_color = Color(color.r, color.g, color.b, 0.95 * alpha)
		glow_color = Color(color.r, color.g, color.b, 0.16 * alpha)
		highlight = Color(1, 1, 1, 0.18 * alpha)
		main_width = clampf(float(jline.get("width", RING_WIDTH)), 0.5, 24.0)
		glow_width = maxf(GLOW_WIDTH, main_width * 3.0 + float(jline.get("expand", 0.0)) * 24.0)
	var run := PackedVector2Array()
	for item in points:
		if bool(item.get("gap", false)):
			if run.size() > 1:
				canvas.draw_polyline(run, glow_color, glow_width, true)
				canvas.draw_polyline(run, main_color, main_width, true)
				canvas.draw_polyline(run, highlight, 1.0, true)
			run = PackedVector2Array()
			continue
		var p := project_design(item.point)
		if _valid_point(p):
			run.append(p)
	if run.size() > 1:
		canvas.draw_polyline(run, glow_color, glow_width, true)
		canvas.draw_polyline(run, main_color, main_width, true)
		canvas.draw_polyline(run, highlight, 1.0, true)


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
			canvas.draw_polyline(points, Color(1, 1, 1, 0.09), 1.0, false)
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
			canvas.draw_polyline(points, color, width, false)


## Seek 的半径比例：和 Tap/Bell 共用 SPAWN_LENGTH_RATIO → 1 的下落曲线，
## 所以「出生点 / 到环时刻」与其它音符一致，不再是一整段最大半径。
static func seek_grow_scale(progress: float) -> float:
	return lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, clampf(progress, 0.0, 1.0))


## x = 外沿半径，y = 内沿半径，z = 不透明度。Limit 在结束拍瞬间消失，没有退场动画。
static func limit_visual_state(approach: float) -> Vector3:
	var advance: float = smoothstep(0.0, 1.0, approach)
	var outer: float = lerpf(0.38, 1.0, advance)
	var depth: float = lerpf(0.025, 1.0 - LIMIT_INNER_SCALE, smoothstep(0.22, 1.0, approach))
	return Vector3(outer, outer - depth, smoothstep(0.0, 0.46, approach))


func _draw_red_regions(canvas: Control, chart: Chart, t: float) -> void:
	if chart.regions.is_empty():
		return
	var now_ms: float = chart.timing.beat_to_chart_ms(t)
	for region in chart.regions:
		var end_ms: float = chart.timing.beat_to_chart_ms(region.end_beat)
		if now_ms >= end_ms:
			continue
		var progress: float = 1.0 if t >= region.start_beat else _approach(chart, region.start_beat, t)
		var state: Vector3 = limit_visual_state(progress)
		if state.z <= 0.001:
			continue
		_draw_limit_wall(canvas, region, t, state, smoothstep(0.78, 1.0, progress))


func _draw_limit_wall(canvas: Control, region: Region, beat: float, state: Vector3, warning: float) -> void:
	var width: float = clampf(region.width, 0.1, 360.0)
	var steps: int = clampi(ceili(width / 6.0), 4, 60)
	var first_angle: float = region.angle - width * 0.5
	var bevel_scale: float = lerpf(state.x, state.y, 0.17)
	var outer: PackedVector2Array = PackedVector2Array()
	var bevel: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for i in steps + 1:
		var angle: float = first_angle + width * float(i) / float(steps)
		var edge: Vector2 = _arc_point_scaled(angle, beat, state.x)
		var lip: Vector2 = _arc_point_scaled(angle, beat, bevel_scale)
		var back: Vector2 = _arc_point_scaled(angle, beat, state.y)
		if not (_valid_point(edge) and _valid_point(lip) and _valid_point(back)):
			_draw_limit_wall_run(canvas, outer, bevel, inner, state.z, warning)
			outer.clear()
			bevel.clear()
			inner.clear()
			continue
		outer.append(edge)
		bevel.append(lip)
		inner.append(back)
		# Keep polygons open on near-full-circle regions, sharing the cut sample.
		if i == (steps >> 1) and width > 180.0:
			_draw_limit_wall_run(canvas, outer, bevel, inner, state.z, warning)
			outer = PackedVector2Array([edge])
			bevel = PackedVector2Array([lip])
			inner = PackedVector2Array([back])
	_draw_limit_wall_run(canvas, outer, bevel, inner, state.z, warning)


func _draw_limit_wall_run(canvas: Control, outer: PackedVector2Array, bevel: PackedVector2Array, inner: PackedVector2Array, alpha: float, warning: float) -> void:
	if outer.size() < 2:
		return
	var size: float = _note_scale()
	# 配色：外沿是热的警示珊瑚红，墙体向圆心沉成深酒红并变透，
	# 这样红区又不抢音符，又比一整块实心红更立体。
	_draw_gradient_band(canvas, bevel, inner, Color(0.34, 0.020, 0.075, 0.92 * alpha),
		Color(0.13, 0.012, 0.045, 0.62 * alpha))
	_draw_gradient_band(canvas, outer, bevel, Color(0.96, 0.12, 0.22, 0.96 * alpha),
		Color(0.55, 0.045, 0.11, 0.94 * alpha))
	if warning > 0.01:
		var marks: PackedVector2Array = PackedVector2Array()
		for i in range(0, outer.size() - 1, 2):
			marks.append(outer[i].lerp(outer[i + 1], 0.20))
			marks.append(bevel[i].lerp(bevel[i + 1], 0.84))
		canvas.draw_multiline(marks, Color(0.17, 0.024, 0.05, 0.72 * alpha * warning), 3.0 * size, true)
		# The inset rim still identifies the hazard while Seek shares the judgment line.
		canvas.draw_polyline(bevel, Color(1.0, 0.46, 0.54, 0.80 * alpha * warning), 2.4 * size, true)
		canvas.draw_polyline(inner, Color(0.90, 0.18, 0.24, 0.46 * alpha * warning), 1.5 * size, true)
	if note_glow:
		canvas.draw_polyline(outer, Color(0.95, 0.14, 0.24, 0.16 * alpha), 9.0 * size, true)
	canvas.draw_polyline(outer, Color(1.0, 0.68, 0.76, 0.92 * alpha), 2.0 * size, true)
	canvas.draw_polyline(inner, Color(0.92, 0.20, 0.26, 0.32 * alpha), 1.2 * size, true)


func _draw_gradient_band(canvas: Control, a: PackedVector2Array, b: PackedVector2Array, color_a: Color, color_b: Color) -> void:
	var polygon: PackedVector2Array = a.duplicate()
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(a.size() + b.size())
	for i in a.size():
		colors[i] = color_a
	for i in range(b.size() - 1, -1, -1):
		colors[polygon.size()] = color_b
		polygon.append(b[i])
	canvas.draw_polygon(polygon, colors)


## 红区激活期间的判定多边形（外弧 + 内弧）。
func red_region_polygon(region: Region, beat: float) -> PackedVector2Array:
	var outer := _arc_points_scaled(region.angle, region.width, beat, 40, 1.0)
	var inner := _arc_points_scaled(region.angle, region.width, beat, 40, LIMIT_INNER_SCALE)
	if outer.size() < 2 or inner.size() < 2:
		return PackedVector2Array()
	var polygon := PackedVector2Array()
	for point in outer:
		polygon.append(point)
	for i in range(inner.size() - 1, -1, -1):
		polygon.append(inner[i])
	return polygon


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


## 音符最终颜色：单音符覆盖 > 配色组 > 类型默认；预览与试玩共用同一条路径。
func _note_tint(note: Note, fallback: Color) -> Color:
	var chart := get_chart()
	return note.resolved_color(chart, fallback)


func _invalidate_path_index() -> void:
	_indexed_path_chart = null
	_indexed_path_roots = []
	_path_index.clear()
	_path_prefix_end.clear()
	_path_strokes.clear()
	_path_overlap_samples.clear()
	_overlap_paths.clear()
	_overlap_any = false


func _update_path_index(chart: Chart) -> void:
	var roots: Array[Note] = chart.path_roots()
	if chart == _indexed_path_chart and chart.version == _indexed_path_version and is_same(roots, _indexed_path_roots):
		return
	_invalidate_path_index()
	_path_local_cache.clear()
	_indexed_path_chart = chart
	_indexed_path_version = chart.version
	_indexed_path_roots = roots
	var by_id := chart.notes_by_id()
	for root in roots:
		var entry := VisiblePath.new()
		var part: Note = root
		while part != null and entry.parts.size() < 65:
			entry.parts.append(part)
			entry.first_beat = minf(entry.first_beat, part.beat)
			entry.last_beat = maxf(entry.last_beat, part.end_beat + 0.5)
			part = by_id.get(part.path_next_id) if part.path_next_id >= 0 else null
		if entry.parts.size() == 1:
			entry.note = root
		_path_index.append(entry)
	_path_index.sort_custom(func(a: VisiblePath, b: VisiblePath) -> bool: return a.first_beat < b.first_beat)
	var latest_end: float = -INF
	for entry in _path_index:
		latest_end = maxf(latest_end, entry.last_beat)
		_path_prefix_end.append(latest_end)


func _visible_paths(chart: Chart, beat: float) -> Array[Note]:
	_update_path_index(chart)
	var visible: Array[Note] = []
	# Find the first interval that can still be on screen, including chains
	# whose root is far behind the current beat.
	var first: int = _path_prefix_end.bsearch(beat)
	var timing: TimingMap = chart.timing
	var latest_head: float = timing.chart_ms_to_beat(
		timing.beat_to_chart_ms(beat) + _pre_read_ms(chart) * _max_group_speed_ratio(chart)) + 0.000001
	for i in range(first, _path_index.size()):
		var entry: VisiblePath = _path_index[i]
		if entry.first_beat > latest_head:
			break
		if entry.last_beat < beat:
			continue
		for part in entry.parts:
			var spawn_beat := _spawn_beat(chart, part.beat, part.group_id)
			if beat > part.end_beat + 0.5 or beat < spawn_beat:
				continue
			if entry.note == null:
				entry.note = build_path_chain_note(entry.parts[0], entry.parts)
			visible.append(entry.note)
			break
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	return visible


func _draw_paths(canvas: Control, chart: Chart, t: float, _pre: float) -> void:
	var visible: Array[Note] = _visible_paths(chart, t)
	if visible != _overlap_paths:
		_overlap_paths = visible
		_overlap_any = _has_path_overlap(visible)
		for note: Note in _path_strokes.keys():
			if not visible.has(note):
				_path_strokes.erase(note)
	if visible.is_empty():
		return
	# 接力高亮：还没划完的星里，只有尾判定最早的那条（或几条同时到点）保持全亮。
	var active_end := INF
	for note in visible:
		if t <= note.end_beat:
			active_end = minf(active_end, note.end_beat)
	var selected_note: Note = null
	if _app != null and not _app.selected_notes.is_empty():
		selected_note = _app.get_selected_note()
	var projection_key: String = "%s|%s|%s" % [_mesh_key(chart, t), _last_view_key, size]
	# Draw the active paths last while retaining their relative order and colors.
	for active_pass: bool in [false, true]:
		for i in visible.size():
			var note: Note = visible[i]
			var active: bool = t <= note.end_beat and note.end_beat <= active_end + 0.05
			if active != active_pass:
				continue
			var tint: Color = _note_tint(note, Note.DEFAULT_PATH_COLOR)
			if _overlap_any:
				tint = tint.darkened(0.18 * float(i % 4))
			var dim: float = 1.0 if active else PATH_RELAY_DIM
			var selected: bool = selected_note != null and selected_note.id == note.id
			_draw_one_path(canvas, chart, note, t, projection_key, visible.size(), tint, dim, active, selected)


## One synthetic Path for a part chain: one head, one guide ball, one tail.
## Shared by drawing and judgement so the whole chain is judged as drawn.
static func build_path_chain_note(root: Note, chain: Array[Note]) -> Note:
	var result := Note.new("path", root.beat, root.angle, root.width)
	result.id = root.id
	result.end_beat = chain[-1].end_beat
	result.tail_angle = chain[-1].tail_angle
	result.tail_width = chain[-1].tail_width
	result.path_speed = root.path_speed
	result.wait_beat = root.wait_beat
	result.samples_per_beat = root.samples_per_beat
	result.has_custom_color = root.has_custom_color
	result.custom_color = root.custom_color
	result.path_chain = true
	result.path_next_id = root.path_next_id
	result.trace_pts = []
	for part in chain:
		var total := maxf(0.001, part.duration())
		var count := maxi(6, int(total * 18.0))
		for i in count + 1:
			var rel := total * float(i) / float(count)
			var local := part.path_local_at(rel)
			result.trace_pts.append({
				"x": local.x,
				"y": local.y,
				"db": (part.beat - root.beat) + rel,
			})
	return result


func _overlap_samples(note: Note) -> PackedVector2Array:
	if _path_overlap_samples.has(note):
		return _path_overlap_samples[note]
	var duration: float = maxf(0.01, note.duration())
	var samples := PackedVector2Array()
	for i in 13:
		samples.append(note.path_local_at(duration * float(i) / 12.0))
	_path_overlap_samples[note] = samples
	return samples


func _has_path_overlap(visible: Array[Note]) -> bool:
	for i in visible.size():
		var first: Note = visible[i]
		for j in range(i + 1, visible.size()):
			var second: Note = visible[j]
			if first.end_beat < second.beat - 0.25:
				break
			if second.end_beat < first.beat - 0.25:
				continue
			var first_samples: PackedVector2Array = _overlap_samples(first)
			var second_samples: PackedVector2Array = _overlap_samples(second)
			for a in first_samples:
				for b in second_samples:
					if a.distance_squared_to(b) < 0.22 * 0.22:
						return true
	return false


static func split_path_runs(points: PackedVector2Array, erased: Array, starts: Array[int] = []) -> Array[PackedVector2Array]:
	# 只在真正擦除/无效点处分段；不再用像素距离阈值，避免长轨迹被误切。
	starts.clear()
	var result: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in points.size():
		var point := points[i]
		var hidden := i < erased.size() and bool(erased[i])
		if hidden or not is_finite(point.x) or not is_finite(point.y) or point.x > 1.0e9 or point.y > 1.0e9:
			if run.size() > 1:
				result.append(run)
				starts.append(i - run.size())
			run = PackedVector2Array()
			continue
		run.append(point)
	if run.size() > 1:
		result.append(run)
		starts.append(points.size() - run.size())
	return result


func _path_stroke_runs(chart: Chart, note: Note, beat: float, projection_key: String, count: int) -> Array[PackedVector2Array]:
	var stroke: PathStroke = _path_strokes.get(note)
	if stroke == null:
		stroke = PathStroke.new()
		_path_strokes[note] = stroke
	var count_changed: bool = count != stroke.count
	var reproject: bool = count_changed or projection_key != stroke.projection_key
	var cut_version: int = int(path_cut_versions.get(note.id, 0))
	var recut: bool = count_changed or cut_version != stroke.cut_version
	var total: float = note.duration()
	if reproject:
		stroke.points.resize(count + 1)
		stroke.distances.resize(count + 1)
		var distance: float = 0.0
		for i in count + 1:
			var rel: float = total * float(i) / float(count)
			var point: Vector2 = _path_screen_point(chart, note, rel, beat)
			if i > 0 and _valid_point(point) and _valid_point(stroke.points[i - 1]):
				distance += point.distance_to(stroke.points[i - 1])
			stroke.points[i] = point
			stroke.distances[i] = distance
		stroke.projection_key = projection_key
	if recut:
		stroke.erased.resize(count + 1)
		for i in count + 1:
			var rel: float = total * float(i) / float(count)
			stroke.erased[i] = path_erased(note, rel)
		stroke.cut_version = cut_version
	if reproject or recut:
		stroke.runs = split_path_runs(stroke.points, stroke.erased, stroke.run_starts)
		stroke.count = count
	return stroke.runs


func _draw_one_path(canvas: Control, chart: Chart, note: Note, t: float, projection_key: String, visible_count: int, accent: Color, dim: float, active: bool, selected: bool) -> void:
	var total := note.duration()
	if total <= 0.001:
		return
	var group_mul := chart.group_alpha(note.group_id) / 255.0
	var decorative := not chart.note_enabled(note)
	# 尾判后 0.1s 内整条轨迹（轨迹 / 进度球 / 尾环）一起淡出，不再等到 end+0.5 拍硬消失。
	var end_span := end_fade_beats(chart.timing.bpm_at(note.beat))
	var end_fade := clampf(1.0 - (t - note.end_beat) / end_span, 0.0, 1.0)
	# 先铺轨迹，再落星星：轨迹从生成开始淡入，星星落下的那一刻正好铺满。
	var spawn_beat := _spawn_beat(chart, note.beat, note.group_id)
	var fall_beat := _fall_beat(chart, note.beat, note.group_id)
	var trail_fade := smoothstep(0.0, 1.0, chart.timing.ms_fraction(spawn_beat, fall_beat, t)) * group_mul
	if decorative:
		trail_fade = 0.0
	var ns := _note_scale()
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, total - 0.001))
	var q := clampf((t - note.beat - wait) / maxf(0.001, total - wait), 0.0, 1.0)
	var progress := 1.0 - pow(1.0 - q, maxf(0.05, note.path_speed))
	# 轨迹球：所有画法共用同一颗球，大小跟随「光标大小」。
	var ball_width: float = cursor_main_diameter(cursor_scale)
	# 颜色由 _draw_paths 统一分配（自定义优先，重叠时同色系压明度）。
	var trail_dim := dim * trail_fade * end_fade
	var future := Color(accent.r, accent.g, accent.b, 0.98 * trail_dim)
	var passed := Color(accent.r, accent.g, accent.b, 0.14 * trail_dim)
	if trail_fade > 0.001 and end_fade > 0.0:
		var count: int = clampi(int(total * 12.0), 28, 64) if visible_count >= 4 else clampi(int(total * 18.0), 40, 96)
		var runs: Array[PackedVector2Array] = _path_stroke_runs(chart, note, t, projection_key, count)
		for i in runs.size():
			var piece: PackedVector2Array = runs[i]
			if piece.size() < 2:
				continue
			# 所有星都用同一条粗带；还没轮到的那条只压明度（PATH_RELAY_DIM），
			# 不再缩成细线，否则多条星先后出现时后一条完全读不出路径。
			var path_band := float(_skin()["band"])
			var band_width := 5.0 * PATH_SIZE_SCALE * ns * path_band
			# 同押（同屏还有别的 path）时先垫一圈白描边，重叠加起来的带子才数得清。
			if visible_count > 1:
				canvas.draw_polyline(piece, Color(1, 1, 1, 0.34 * trail_dim), band_width * 1.7 + 8.0, false)
			canvas.draw_polyline(piece, Color(0, 0, 0, 0.55 * trail_dim), band_width * 1.7 + 4.0, false)
			if path_style == "ribbon":
				# B 半透明丝带：宽而透的身体 + 一道亮边（Arcaea 式）。
				canvas.draw_polyline(piece, Color(accent.r, accent.g, accent.b, 0.40 * trail_dim), band_width * 1.55, false)
				canvas.draw_polyline(piece, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim), band_width * 0.42, false)
			else:
				# A 粗 chevron 履带：实心带 + 内部箭头纹，方向一眼可读。
				canvas.draw_polyline(piece, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim), band_width * 1.7, false)
				_draw_tread_marks(canvas, piece, band_width * 1.7, Color(0.04, 0.05, 0.08, 0.45 * trail_dim))
			# 方向箭头：丝带靠它读方向；履带本身已经带纹，只在远处留少量箭头。
			var chevron_size := 12.0 * ns * PATH_SIZE_SCALE
			var chevron_spacing := maxf(36.0, chevron_size * 2.3)
			if path_style == "tread":
				chevron_spacing *= 2.2
			for sample in _chevron_samples(piece, chevron_spacing, chevron_size * 1.9):
				# 试玩时轨迹已经被擦到光标处，剩下的每一段都在前方，不该再按“piece 内比例”压暗。
				var chevron_color := future if playtest_mode else (passed if sample.fraction < progress else future)
				_draw_chevron(canvas, sample.point, sample.direction, chevron_color, chevron_size)
	if selected:
		# 中间判定点只在选中时绘制，避免多星星铺满采样点拖慢编辑器。
		for sample_beat in note.path_sample_beats():
			var rel := clampf(sample_beat - note.beat, 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, 1.0)
			if _valid_point(p):
				canvas.draw_circle(p, 2.6 * ns, Color(0, 0, 0, 0.5))
				canvas.draw_circle(p, 1.8 * ns, Color(accent.r, accent.g, accent.b, 0.85))
		# 手动放置的中间设计点。
		for point in note.visual_pts:
			var rel := clampf(float(point.get("db", 0.0)), 0.0, total)
			if path_erased(note, rel):
				continue
			var p := _path_screen_point(chart, note, rel, t, true, 1.0)
			if _valid_point(p):
				_draw_diamond(canvas, p, 4.5, UITheme.GOLD)
	if selected:
		for point in note.trace_pts:
			var node := _path_local_screen(chart, Vector2(float(point.get("x", 0.0)), float(point.get("y", 0.0))), t, 1.0)
			if _valid_point(node):
				_draw_diamond(canvas, node, 5.0, UITheme.CYAN)
				canvas.draw_circle(node, 1.8, UITheme.INK)
	# 星头和 Tap/Bell/Seek 用同一条下落曲线：出生 1/6 半径 → 判定拍落到环上。
	var fall_progress := _note_progress(chart, note, t)
	var fall_ratio: float = lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, fall_progress)
	# 环上固定的落点（圆的中心）和滑动终点。
	var ring_head := _path_screen_point(chart, note, 0.0, t, true, 1.0)
	var tail := _path_screen_point(chart, note, total, t, true, 1.0)
	# 尾点倒计时环：距尾判定 2 拍内从大圈收到尾环，贴合时正是尾判定时刻。
	# 多条星同时在场时，环先缩满的那条就是要先划完的。
	if _valid_point(tail) and trail_fade > 0.01 and end_fade > 0.01:
		# 终点端子：圆头短杠收住轨迹，密集时不会被误读成另一条的起点。
		var dir := (tail - _path_screen_point(chart, note, total - 0.05, t, true, 1.0)).normalized()
		if dir.length_squared() < 0.1:
			dir = Vector2.UP
		var normal := Vector2(-dir.y, dir.x)
		var half := 7.0 * ns * PATH_SIZE_SCALE
		var cap_a := tail + normal * half
		var cap_b := tail - normal * half
		canvas.draw_line(cap_a, cap_b, Color(0, 0, 0, 0.55 * trail_dim), 7.0 * ns)
		canvas.draw_line(cap_a, cap_b, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim), 4.0 * ns)
		canvas.draw_circle(cap_a, 2.4 * ns, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim))
		canvas.draw_circle(cap_b, 2.4 * ns, Color(accent.r, accent.g, accent.b, 0.95 * trail_dim))
		# 多颗星同时在场时，终点再补 3 个反向箭头：一眼看出这条往哪儿结束。
		if visible_count > 1:
			for k in 3:
				var at := tail - dir * float(k + 1) * 11.0 * ns
				_draw_chevron(canvas, at, -dir, Color(1, 1, 1, 0.75 * trail_dim), 9.0 * ns)
	if _valid_point(ring_head) and t >= spawn_beat and fall_progress < 1.0:
		# 发车环：星头落到环上之前，一圈由大到小收进来。
		var landing_radius: float = 13.0 * ns
		var head_ring: float = lerpf(landing_radius + 33.0 * ns, landing_radius, fall_progress)
		canvas.draw_arc(ring_head, head_ring, 0.0, TAU, 32, Color(1, 1, 1, 0.55 * trail_fade * end_fade), 2.2, false)
	if _valid_point(tail) and t >= note.beat - 0.15:
		var remain := note.end_beat - t
		if remain <= 2.0 and remain > -end_span:
			var k := clampf(1.0 - remain / 2.0, 0.0, 1.0)
			var ring_radius := lerpf(52.0, 14.0, k) * ns
			var ring_alpha := lerpf(0.10, 0.95, k * k) * maxf(dim, 0.75) * end_fade * group_mul
			canvas.draw_arc(tail, ring_radius, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, ring_alpha), 2.6, false)
			if active:
				canvas.draw_arc(tail, ring_radius + 3.5, 0.0, TAU, 40, Color(1, 1, 1, 0.30 * ring_alpha), 1.2, false)
	# 星头拆成两部分：
	#   环上的圆 = 落点标记（预读出现，头判后淡出）
	#   下落的星星 = 星形 + 光晕（从圆心飞到圆上；击中后继续落到圆上再淡出，
	#   打空则停在圆上淡出）
	var head_state: Dictionary = _path_head_state.get(note.id, {})
	var state_beat := float(head_state.get("beat", note.beat))
	var head_hit := bool(head_state.get("hit", true))
	var fade_start := maxf(note.beat, state_beat) if head_hit else state_beat
	var fade_beats := 0.3 * chart.timing.bpm_at(note.beat) / 60.0
	var head_alpha := 1.0 - clampf((t - fade_start) / maxf(0.001, fade_beats), 0.0, 1.0)
	# 假 Path：轨迹隐藏，星头直接从落点淡入一拍；真 Path 仍随轨迹淡入。
	var head_fade := 0.0
	if decorative:
		head_fade = clampf(t - note.beat, 0.0, 1.0) * dim * group_mul
	else:
		head_fade = head_alpha * dim * trail_fade * group_mul
	var ring_mul := 0.5 if note.path_chain else 1.0
	var wait_mode := String(_app.path_wait_indicator) if _app != null else "progress"
	var wait_state := path_wait_indicator_state(chart.timing, note, t)
	if wait_mode != "off" and wait_state.y > 0.0:
		# The landing circle becomes the countdown and survives the head-hit fade.
		head_fade = 0.0
	if head_fade > 0.01 and _valid_point(ring_head):
		_draw_path_circle(canvas, ring_head, ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE, accent, head_fade, ring_mul)
		# 重叠 Path 用不同明度的外环区分星头。
		canvas.draw_arc(ring_head, 28.0 * ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE * ring_mul, 0.0, TAU, 30, Color(accent.r, accent.g, accent.b, 0.95 * head_fade), 2.4, false)
		# 音符编号只在编辑器和调试叠层里显示，试玩时不添乱。
		if not playtest_mode or show_debug:
			canvas.draw_string(UITheme.mono_font(), ring_head + Vector2(14, -13), "#%d" % note.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(accent.r, accent.g, accent.b, 0.9 * head_fade))
		# 头部的白色箭头指向轨迹内侧，进一步区分头和尾。
		var ahead := _path_screen_point(chart, note, minf(total, maxf(0.05, total * 0.08)), t, true, 1.0)
		if _valid_point(ahead):
			_draw_arrowhead(canvas, ring_head + (ahead - ring_head).normalized() * 29.0 * ns * PATH_SIZE_SCALE, ahead - ring_head, Color(1, 1, 1, 0.95 * head_fade))
		if show_debug:
			canvas.draw_string(UITheme.bold_font(), ring_head + Vector2(-12, -22), "PATH", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.85))
	# 星头球：判定前从圆心飞到落点，判定后沿轨迹前进。
	# 假 Path 的轨迹不画，判定后只在落点留一颗淡出的球。
	if decorative:
		var false_fade := clampf(t - note.beat, 0.0, 1.0) * group_mul * dim
		if false_fade > 0.01 and _valid_point(ring_head):
			_draw_path_head_ball(canvas, ring_head, Vector2.ZERO, ball_width, accent, false_fade)
	elif t < note.beat:
		var point: Vector2 = _path_screen_point(chart, note, note.path_motion_beat(progress), t, false)
		var alpha: float = dim * end_fade * group_mul * head_alpha
		if alpha > 0.001 and _valid_point(point):
			var center: Vector2 = project_design(Vector2.ZERO)
			_draw_path_head_ball(canvas, center.lerp(point, fall_ratio), (center - point).normalized(),
				ball_width, accent, alpha)
	_draw_path_tail(canvas, tail, true, ns * PATH_SIZE_SCALE, accent, dim * trail_fade * end_fade)
	# 轨迹球：到判定拍后沿轨迹前进。
	if not decorative and t >= note.beat and t <= note.end_beat + end_span:
		var ball_dim := dim * end_fade * group_mul
		var rel := note.path_motion_beat(progress)
		var point := _path_screen_point(chart, note, rel, t, false)
		if ball_dim > 0.001 and _valid_point(point):
			var direction := _path_head_tangent(chart, note, t, rel, point)
			if t < note.beat + wait:
				var inward: Vector2 = (project_design(Vector2.ZERO) - point).normalized()
				if not inward.is_zero_approx():
					var turn: float = 0.0 if direction.is_zero_approx() else inward.angle_to(direction)
					direction = inward.rotated(turn * smoothstep(0.0, 1.0, wait_state.x))
			_draw_path_head_ball(canvas, point, direction, ball_width, accent, ball_dim)
	if wait_mode != "off" and wait_state.y > 0.0 and _valid_point(ring_head):
		# Shrinking mode lands exactly on the original blue head ring; the progress
		# arc retains its larger radius so it remains readable outside the guide ball.
		var head_radius := 28.0 * ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE * ring_mul
		var wait_radius := head_radius if wait_mode == "shrink" else maxf(head_radius, 24.0 * ns * PATH_SIZE_SCALE)
		_draw_path_wait_indicator(canvas, ring_head, wait_radius,
			wait_state.x, wait_state.y * dim * trail_fade, wait_mode)


static func cursor_main_diameter(scale: float) -> float:
	return (2.0 * CURSOR_MAIN_RADIUS + CURSOR_MAIN_STROKE) * clampf(scale, 0.5, 2.0)


func _path_head_tangent(chart: Chart, note: Note, beat: float, relative: float, point: Vector2) -> Vector2:
	var total: float = note.duration()
	# Look ahead locally so an arrow turning around a corner describes the next movement.
	for offset: float in [0.008, 0.02, 0.065, 0.18, 0.5, 1.0]:
		if relative >= total:
			break
		var ahead: Vector2 = _path_screen_point(chart, note, minf(total, relative + total * offset), beat, false)
		if _valid_point(ahead) and ahead.distance_squared_to(point) > 0.16:
			return (ahead - point).normalized()
	for offset: float in [0.008, 0.02, 0.065, 0.18, 0.5, 1.0]:
		if relative <= 0.0:
			break
		var behind: Vector2 = _path_screen_point(chart, note, maxf(0.0, relative - total * offset), beat, false)
		if _valid_point(behind) and behind.distance_squared_to(point) > 0.16:
			return (point - behind).normalized()
	return Vector2.ZERO


func _draw_path_head_ball(canvas: Control, point: Vector2, direction: Vector2, width: float, tint: Color, alpha: float) -> void:
	var radius: float = width * PATH_HEAD_BALL_RATIO * 0.5
	canvas.draw_circle(point, radius, Color(0.04, 0.055, 0.093, 0.98 * alpha), true, -1.0, true)
	canvas.draw_circle(point, radius * 0.77, Color(tint.darkened(0.48), alpha), true, -1.0, true)
	canvas.draw_arc(point, radius * 0.89, 0.0, TAU, 32, Color(tint.lerp(Color.WHITE, 0.52), 0.96 * alpha),
		radius * 0.17, true)
	if direction.is_zero_approx():
		return
	var side: Vector2 = direction.orthogonal() * (radius * 0.33)
	var front: Vector2 = point + direction * (radius * 0.43)
	var back: Vector2 = point - direction * (radius * 0.33)
	canvas.draw_colored_polygon(PackedVector2Array([front, back + side, point - direction * (radius * 0.14), back - side]),
		Color(1.0, 0.99, 0.98, alpha))


## Use elapsed chart milliseconds so BPM changes inside the wait stay in sync.
## x = completion, y = opacity; no countdown for zero wait or before landing.
static func path_wait_indicator_state(timing: TimingMap, note: Note, beat: float) -> Vector2:
	var wait := clampf(note.wait_beat, 0.0, maxf(0.0, note.duration() - 0.001))
	if wait <= 0.0 or beat < note.beat:
		return Vector2.ZERO
	var start_ms := timing.beat_to_chart_ms(note.beat)
	var end_ms := timing.beat_to_chart_ms(note.beat + wait)
	var now_ms := timing.beat_to_chart_ms(beat)
	var completion := clampf((now_ms - start_ms) / maxf(0.001, end_ms - start_ms), 0.0, 1.0)
	var opacity := 1.0 - clampf((now_ms - end_ms) / 160.0, 0.0, 1.0)
	return Vector2(completion, opacity)


func _draw_path_wait_indicator(canvas: Control, center: Vector2, radius: float, completion: float, opacity: float, mode: String) -> void:
	if mode == "shrink":
		var ring_radius := radius * lerpf(2.5, 1.0, completion)
		var alpha := opacity * completion
		canvas.draw_arc(center, ring_radius, 0.0, TAU, 64, Color(0.55, 0.75, 1.0, 0.16 * alpha), 7.0, true)
		canvas.draw_arc(center, ring_radius, 0.0, TAU, 64, Color(0.55, 0.75, 1.0, 0.95 * alpha), 2.4, true)
		return
	var color := Color(0.35, 1.0, 0.62, 0.95 * opacity)
	canvas.draw_arc(center, radius, 0.0, TAU, 64, Color(0.02, 0.03, 0.05, 0.65 * opacity), 6.0, true)
	canvas.draw_arc(center, radius, 0.0, TAU, 64, Color(0.65, 0.75, 0.85, 0.22 * opacity), 2.4, true)
	if completion > 0.001:
		canvas.draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * completion, 64, color, 3.2, true)


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


func path_judgement_points(local_points: PackedVector2Array, beat: float) -> PackedVector2Array:
	var projected := PackedVector2Array()
	var chart := get_chart()
	if chart == null:
		return projected
	for point in local_points:
		projected.append(_path_local_screen(chart, point, beat))
	return projected


func path_judgement_scale() -> float:
	# Input tolerance follows the visible ring size, independently of cursor art.
	return maxf(1.0, _avg_radius_cache)


func path_judgement_debug(note: Note, beat: float) -> Dictionary:
	var state: Dictionary = path_judgement_states.get(note.id, {})
	var tracker: PathProgress = state.get("path_tracker")
	if tracker == null:
		return {}
	return {"points": path_judgement_points(tracker.points, beat),
		"radius": tracker.contact_radius * path_judgement_scale(),
		"next": tracker.next_index, "mandatory": tracker.mandatory,
		"required": tracker.required_index, "coverage": tracker.coverage,
		"progress": tracker.progress, "covered": tracker.covered, "gates": tracker.gates,
		"gate_radii": tracker.gate_radii, "next_gate": tracker.next_gate,
		"cleared": tracker.cleared, "group_count": tracker.group_count,
		"tolerance": tracker.tolerance, "remaining": tracker.remaining_groups(),
		"tail_radius": float(state.get("path_tail_radius", 0.0)),
		"missed": bool(state.get("tail_judged", false)) and not bool(state.get("tail_hit", false))}


func set_path_judgement_visible(value: bool) -> void:
	show_path_judgement = value
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_path_judgement(canvas: Control, chart: Chart, beat: float, pre: float) -> void:
	var font := UITheme.mono_font()
	var confirmed := Color(0.25, 1.0, 0.55)
	var pending := Color(0.25, 0.65, 1.0)
	var current := Color(1.0, 0.65, 0.15)
	var failed := Color(1.0, 0.25, 0.3)
	for note in chart.notes:
		if note.type != "path" or note.beat > beat + pre or beat > note.end_beat + 0.8:
			continue
		var data := path_judgement_debug(note, beat)
		if data.is_empty():
			continue
		var points: PackedVector2Array = data["points"]
		var radius := float(data["radius"])
		var next := int(data["next_gate"])
		var gates: PackedInt32Array = data["gates"]
		var radii: PackedFloat32Array = data["gate_radii"]
		var covered: PackedByteArray = data["covered"]
		var cleared: PackedByteArray = data["cleared"]
		# Draw only valid segments, so boundary gaps never become fake corridors.
		var run := PackedVector2Array()
		var run_covered := false
		for i in points.size() - 1:
			if not _valid_point(points[i]) or not _valid_point(points[i + 1]):
				_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
				run.clear()
				continue
			var is_covered := covered[i] != 0
			if not run.is_empty() and run_covered != is_covered:
				_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
				run.clear()
			if run.is_empty():
				run.append(points[i])
				run_covered = is_covered
			run.append(points[i + 1])
		_draw_path_corridor_run(canvas, run, radius, confirmed if run_covered else pending)
		for i in gates.size():
			var point := points[gates[i]]
			if not _valid_point(point):
				continue
			var gate_radius := float(radii[i]) * path_judgement_scale()
			var color := confirmed if i < cleared.size() and cleared[i] != 0 else pending
			if i == next:
				color = failed if bool(data["missed"]) else current
			canvas.draw_circle(point, gate_radius, Color(color, 0.045))
			canvas.draw_arc(point, gate_radius, 0.0, TAU, 40, Color(color, 0.85), 2.4 if i == next else 1.0, true)
			var label := str(i + 1)
			var offset := Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 4)
			canvas.draw_string_outline(font, point + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
			canvas.draw_string(font, point + offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if not points.is_empty() and _valid_point(points[0]):
			var label := "#%d  组%d/%d  容差%d  剩余%d" % [note.id, mini(next, int(data["group_count"])), int(data["group_count"]), int(data["tolerance"]), int(data["remaining"])]
			var position := points[0] + Vector2(12, -radius - 12)
			canvas.draw_string_outline(UITheme.FONT_REGULAR, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
			canvas.draw_string(UITheme.FONT_REGULAR, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if not points.is_empty() and _valid_point(points[-1]) and float(data["tail_radius"]) > 0.0:
			canvas.draw_arc(points[-1], float(data["tail_radius"]), 0.0, TAU, 48, Color(1, 1, 1, 0.35), 1.0, true)
	var legend := "F10：绿=已消组 / 蓝=未消组 / 橙=下一组 / 白圈=尾区，容差=可跳组数"
	canvas.draw_string_outline(UITheme.FONT_REGULAR, Vector2(24, 72), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(24, 72), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draw_path_corridor_run(canvas: Control, run: PackedVector2Array, radius: float, color: Color) -> void:
	if run.size() < 2:
		return
	# Rounded outlines avoid miter spikes that would falsely imply extra area
	# at sharp corners. Outlines also preserve holes in a closed loop.
	for outline in Geometry2D.offset_polyline(run, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		if outline.size() >= 2:
			outline.append(outline[0])
			canvas.draw_polyline(outline, Color(color, 0.45), 1.4, true)
	canvas.draw_polyline(run, Color(color, 0.65), 1.0, true)


func set_path_erased_to(note: Note, fraction: float) -> void:
	# 试玩时只保留一个连续缺口：从头部到当前进度，轨迹始终是连续的一段。
	# 量化到 1/128：擦除边缘肉眼看不出差别，但采样缓存从「每帧失效」变成「每 1% 失效」。
	var target := clampf(snappedf(fraction, 1.0 / 128.0), 0.0, 1.0)
	if target <= 0.004:
		return
	var current: Array = path_cuts.get(note.id, [])
	if current.size() == 1 and absf(float(current[0].get("to", -1.0)) - target) <= 0.001:
		return
	path_cuts[note.id] = [{"from": 0.0, "to": target}]
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


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
	for gap in path_sector_cuts.get(note.id, []):
		if p >= float(gap.get("from", 0.0)) and p <= float(gap.get("to", 1.0)):
			return true
	return false


## 8 分区（45°，边界在 22.5° + 45°k），和 8 个按键 / 车道对齐。
static func ring_sector(angle_deg: float) -> int:
	return int(floor((fposmod(angle_deg, 360.0) + 22.5) / 45.0)) % 8


## 一条 Path 的轨迹按环分区切出的分数区间：sector -> [{from,to}]。
## 结果缓存到 note 上，轨迹不变就不用重算。
func path_sector_ranges(note: Note) -> Dictionary:
	if _path_sector_cache.has(note):
		return _path_sector_cache[note]
	var result := {}
	var total := maxf(0.000001, note.duration())
	var pts: Array = note.trace_pts
	if pts.size() >= 2:
		var current := -1
		var start := 0.0
		var last_frac := 0.0
		for i in pts.size():
			var point: Dictionary = pts[i]
			var angle := fposmod(rad_to_deg(atan2(float(point.get("y", 0.0)), float(point.get("x", 0.0)))), 360.0)
			var sector := ring_sector(angle)
			var frac := clampf(float(point.get("db", 0.0)) / total, 0.0, 1.0)
			if sector != current:
				if current >= 0:
					if not result.has(current):
						result[current] = []
					(result[current] as Array).append({"from": start, "to": last_frac})
				current = sector
				start = frac
			last_frac = frac
		if current >= 0:
			if not result.has(current):
				result[current] = []
			(result[current] as Array).append({"from": start, "to": last_frac})
	_path_sector_cache[note] = result
	return result


## 星星扫到某个分区时，把该分区里这条 Path 的中段擦掉（头 10% / 尾 15% 保留）。
func cut_path_sector(note: Note, sector: int) -> void:
	var ranges: Array = (path_sector_ranges(note) as Dictionary).get(sector, [])
	if ranges.is_empty():
		return
	var cuts: Array = path_sector_cuts.get(note.id, [])
	var changed := false
	for span in ranges:
		var a := maxf(0.10, float(span.get("from", 0.0)))
		var b := minf(0.85, float(span.get("to", 0.0)))
		if b - a <= 0.01:
			continue
		var duplicate := false
		for old in cuts:
			if absf(float(old.get("from", 0.0)) - a) < 0.005 and absf(float(old.get("to", 0.0)) - b) < 0.005:
				duplicate = true
				break
		if duplicate:
			continue
		cuts.append({"from": a, "to": b})
		changed = true
	if not changed:
		return
	path_sector_cuts[note.id] = cuts
	path_cut_versions[note.id] = int(path_cut_versions.get(note.id, 0)) + 1
	if _overlay != null:
		_overlay.queue_redraw()


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


func _stroke_band(canvas: Control, points: PackedVector2Array, color: Color, width: float, alpha: float = 1.0, size_scale: float = -1.0, glow_mul: float = 1.0) -> void:
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
	if glow > 0.01 and glow_mul > 0.01:
		# 柔光层很宽、对比低，关掉 AA 省下的三角形很可观，观感几乎不变。
		# glow_mul = 0 表示画质项关了柔光：只跳这一层，描边/白边/色带照画。
		canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.10 * glow * glow_mul * alpha), w + 18.0 * glow_mul, false)
	if shadow > 0.01:
		var offset := PackedVector2Array()
		for p in points:
			offset.append(p + Vector2(5, 7) * shadow)
		canvas.draw_polyline(offset, Color(0, 0, 0, 0.38 * shadow * alpha), w + 10.0, false)
	canvas.draw_polyline(points, Color(0, 0, 0, 0.62 * outline * alpha), w + 5.0 * outline, false)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.92 * alpha), w, false)
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.94 * alpha), maxf(3.0, w * 0.62), false)
	if gloss > 0.01:
		canvas.draw_polyline(points, Color(1, 1, 0.94, 0.34 * gloss * alpha), maxf(1.5, w * 0.16), false)
	if String(skin["id"]) == "neon":
		canvas.draw_polyline(points, Color(0.04, 0.06, 0.08, 0.85 * alpha), maxf(2.0, w * 0.20), false)


## 环上的圆：星头的落点标记（不再包含星星本体）。
func _draw_path_circle(canvas: Control, point: Vector2, scale: float, color: Color, alpha: float, ring_mul: float = 1.0) -> void:
	if not _valid_point(point):
		return
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE * PATH_HEAD_SCALE
	canvas.draw_circle(point, 31.0 * s * ring_mul, Color(color.r, color.g, color.b, 0.16 * alpha))
	canvas.draw_circle(point, 24.0 * s * ring_mul, Color(0, 0, 0, 0.30 * alpha))
	canvas.draw_arc(point, 24.0 * s * ring_mul, 0.0, TAU, 30, Color(1, 1, 1, 0.30 * alpha), 2.0, false)


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
		canvas.draw_polyline(points, Color(0, 0, 0, 0.7) if layer == 0 else (Color(1, 1, 1, 0.96) if layer == 1 else UITheme.INK), 1.4, false)
	canvas.draw_circle(point, radius * 0.24, Color(0, 0, 0, 0.82))


func _draw_path_tail(canvas: Control, point: Vector2, top: bool, scale: float = 1.0, color: Color = UITheme.GOLD, dim: float = 1.0) -> void:
	if not _valid_point(point):
		return
	var alpha := (1.0 if top else 0.45) * dim
	var s := clampf(scale, 0.2, 2.0) * float(_skin()["scale"]) * PATH_SIZE_SCALE
	# 尾部不再画星星，只留一个细环标记终点。
	canvas.draw_circle(point, 8.0 * s, Color(color.r, color.g, color.b, 0.08 * alpha))
	canvas.draw_arc(point, 6.5 * s, 0.0, TAU, 30, Color(color.r, color.g, color.b, 0.70 * alpha), 1.6, false)


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


## Hold 头/尾共用的圆角金条贴图。
func _draw_hold_cap_band(canvas: Control, band_a: Vector2, band_b: Vector2, fade: float, tint: Color = UITheme.GOLD) -> void:
	var ns := _note_scale()
	var band_w := 16.0 * ns
	canvas.draw_line(band_a, band_b, Color(0, 0, 0, 0.55 * fade), band_w + 6.0 * ns, false)
	canvas.draw_line(band_a, band_b, Color(1, 1, 1, 0.92 * fade), band_w, false)
	canvas.draw_line(band_a, band_b, Color(tint.r, tint.g, tint.b, 0.95 * fade), band_w * 0.62, false)
	canvas.draw_circle(band_a, band_w * 0.5, Color(tint.r, tint.g, tint.b, 0.95 * fade))
	canvas.draw_circle(band_b, band_w * 0.5, Color(tint.r, tint.g, tint.b, 0.95 * fade))
	canvas.draw_circle(band_a, band_w * 0.5, Color(1, 1, 1, 0.92 * fade), false, 2.0, true)
	canvas.draw_circle(band_b, band_w * 0.5, Color(1, 1, 1, 0.92 * fade), false, 2.0, true)
	canvas.draw_line(band_a + Vector2(0, -band_w * 0.18), band_b + Vector2(0, -band_w * 0.18), Color(1, 1, 0.94, 0.45 * fade), band_w * 0.18, false)


## Hold 尾端：形状同头，但用多层柔光代替锐利描边，一眼就能分清头尾。
func _draw_hold_tail_band(canvas: Control, band_a: Vector2, band_b: Vector2, fade: float, tint: Color = UITheme.GOLD) -> void:
	var ns := _note_scale()
	var band_w := 16.0 * ns
	for layer in 4:
		var k := float(layer) / 3.0
		var w := band_w * lerpf(2.0, 0.9, k)
		var a := lerpf(0.05, 0.28, k) * fade
		var c := Color(tint.r, tint.g, tint.b, a)
		canvas.draw_line(band_a, band_b, c, w, false)
		canvas.draw_circle(band_a, w * 0.5, c)
		canvas.draw_circle(band_b, w * 0.5, c)
	# 中间只留一点白芯，保证尾巴位置读得出来，但不抢头部的注意力。
	canvas.draw_line(band_a, band_b, Color(1, 1, 1, 0.30 * fade), band_w * 0.34, false)
	canvas.draw_circle(band_a, band_w * 0.17, Color(1, 1, 1, 0.30 * fade))
	canvas.draw_circle(band_b, band_w * 0.17, Color(1, 1, 1, 0.30 * fade))


func _draw_hold_sector(canvas: Control, chart: Chart, note: Note, t: float, pre: float, fade: float, hide_head: bool = false, tint: Color = UITheme.GOLD, part: int = 0, highlight: bool = false) -> void:
	# 直长条 = 一个从圆心张开的扇形。整根条按**同一个径向速度**往判定环落：
	# 头部（外缘）在 pre 拍内从圆心走到环上，尾部（内缘）晚 duration 拍跟随，
	# 所以看起来是匀速下落，而不是"先快速长出来再慢慢收"。
	# part 0 = 身体，1 = 头/尾/高亮；分两遍画，同角度的 Hold 头永远压在身体上层。
	var width := maxf(4.0, note.arc_width())
	var half := width * 0.5
	var steps := clampi(int(width / 3.0), 8, 48)
	var duration := maxf(0.001, note.duration())
	var head_start := _spawn_beat(chart, note.beat, note.group_id)
	var read := maxf(0.001, note.beat - head_start)
	var outer_scale := clampf((t - head_start) / read, 0.0, 1.0)
	var inner_scale := clampf((t - note.beat - duration + read) / read, 0.0, 1.0)
	# 尾端压到环上（inner_scale 到 1）后不再返回：退化成零宽的最后一帧要留着，
	# 让尾端光带停在环上淡出，而不是当帧消失。
	if outer_scale <= 0.005:
		return
	var center := project_design(Vector2.ZERO)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var edges := PackedVector2Array()
	for i in steps + 1:
		var angle := note.angle - half + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var edge := project_design(data.point)
		edges.append(edge)
		outer.append(center.lerp(edge, outer_scale))
		inner.append(center.lerp(edge, inner_scale))
	if outer.size() < 2:
		return
	if part == 0:
		var polygon := PackedVector2Array()
		polygon.append_array(outer)
		for i in range(inner.size() - 1, -1, -1):
			polygon.append(inner[i])
		# 头亮尾暗：从内缘到外缘分 10 段渐亮（世界计划式）。
		var slices := 10
		for s in slices:
			var s0 := lerpf(inner_scale, outer_scale, float(s) / float(slices))
			var s1 := lerpf(inner_scale, outer_scale, float(s + 1) / float(slices))
			if s1 - s0 < 0.004 or edges.size() < 2:
				continue
			var quad := PackedVector2Array()
			for k in edges.size():
				quad.append(center.lerp(edges[k], s1))
			for k in range(edges.size() - 1, -1, -1):
				quad.append(center.lerp(edges[k], s0))
			var alpha := lerpf(0.07, 0.42, float(s) / float(maxi(1, slices - 1)))
			canvas.draw_colored_polygon(quad, Color(tint.r, tint.g, tint.b, alpha * fade))
		# 外弧：贴着判定环的高亮边。
		canvas.draw_polyline(outer, Color(1, 1, 1, 0.72 * fade), 2.0, false)
		canvas.draw_polyline(outer, Color(tint.r, tint.g, tint.b, 0.95 * fade), 1.0, false)
		# 内弧：长条尾端，往判定环方向收缩；越窄越亮。
		if inner.size() > 1 and inner_scale > 0.002:
			var tail_alpha := lerpf(0.35, 1.0, clampf(inner_scale, 0.0, 1.0))
			canvas.draw_polyline(inner, Color(tint.r, tint.g, tint.b, tail_alpha * fade), 3.0, false)
			canvas.draw_polyline(inner, Color(1, 1, 1, 0.28 * tail_alpha * fade), 1.2, false)
		# 两侧的径向边，让扇形边界清楚。
		if outer.size() == inner.size() and outer.size() > 1:
			var edge_alpha := 0.30 * fade
			canvas.draw_line(outer[0], inner[0], Color(1, 1, 1, edge_alpha), 1.0, false)
			canvas.draw_line(outer[-1], inner[-1], Color(1, 1, 1, edge_alpha), 1.0, false)
		return
	# 头部：圆角金条 + 白色内高光（世界计划式的圆润端头）；尾部虚化。
	if outer.size() > 1 and not hide_head:
		if highlight:
			# 下一颗要按的 Hold：头带外再垫一层柔光，叠在一起时先看它。
			canvas.draw_line(outer[0], outer[outer.size() - 1], Color(tint.r, tint.g, tint.b, 0.22 * fade), 30.0 * _note_scale(), false)
			canvas.draw_line(outer[0], outer[outer.size() - 1], Color(1, 1, 1, 0.30 * fade), 24.0 * _note_scale(), false)
		_draw_hold_cap_band(canvas, outer[0], outer[outer.size() - 1], fade, tint)
	if inner.size() > 1 and inner_scale > 0.002:
		_draw_hold_tail_band(canvas, inner[0], inner[inner.size() - 1], fade, tint)


## 同角度多颗 Hold 的深度：越晚到越淡，先到的保持实心；下限 0.65 保证还看得见。
static func hold_stack_alpha(lead_beats: float, pre_beats: float) -> float:
	var k := clampf(lead_beats / maxf(0.5, pre_beats * 2.0), 0.0, 1.0)
	return lerpf(1.0, 0.65, k)


func _draw_bent_hold(canvas: Control, chart: Chart, note: Note, t: float, pre: float, fade: float, hide_head: bool, tint: Color, part: int = 0, highlight: bool = false) -> void:
	var ns := _note_scale()
	var center := project_design(Vector2.ZERO)
	var body := PackedVector2Array()
	if not note.visual_pts.is_empty():
		# Hold 体节点：和 Path 共用 visual_pts，节点只改画面，不改头部判定。
		var design_points: Array[Dictionary] = [{"db": 0.0, "da": 0.0}]
		design_points.append_array(note.visual_pts)
		design_points.append({"db": note.duration(), "da": 0.0})
		design_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("db", 0.0)) < float(b.get("db", 0.0)))
		for point in design_points:
			var p := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
			if _valid_point(p):
				body.append(center.lerp(p, _approach(chart, note.beat, t, note.group_id)))
	if body.size() < 2:
		return
	var boundary: Vector2 = body[-1]
	var hs := ns * float(_skin()["scale"])
	var cs := ns
	var direction := (boundary - body[maxi(0, body.size() - 2)]).normalized()
	if direction.length_squared() < 0.5:
		direction = (boundary - center).normalized()
	var normal := Vector2(-direction.y, direction.x)
	if part == 0:
		canvas.draw_polyline(body, Color(0, 0, 0, 0.55 * fade), 11.0 * cs, false)
		canvas.draw_polyline(body, Color(1, 1, 1, 0.90 * fade), 6.0 * cs, false)
		canvas.draw_polyline(body, Color(tint.r, tint.g, tint.b, 0.92 * fade), 3.0 * cs, false)
		# 尾端同为虚化：柔光层代替实心金点。
		canvas.draw_circle(body[0], 9.0 * cs, Color(tint.r, tint.g, tint.b, 0.10 * fade))
		canvas.draw_circle(body[0], 6.0 * cs, Color(tint.r, tint.g, tint.b, 0.20 * fade))
		canvas.draw_circle(body[0], 3.0 * cs, Color(tint.r, tint.g, tint.b, 0.70 * fade))
		canvas.draw_circle(body[0], 1.6 * cs, Color(1, 1, 1, 0.30 * fade))
		return
	# 按住中的白点也放在这一遍：同角度有后续 Hold 时不会被身体盖住。
	if t >= note.beat and t <= note.end_beat:
		var progress := clampf((t - note.beat) / maxf(0.001, note.duration()), 0.0, 1.0)
		var marker_index := progress * float(body.size() - 1)
		var lower := clampi(int(marker_index), 0, body.size() - 1)
		var upper := mini(lower + 1, body.size() - 1)
		var marker := body[lower].lerp(body[upper], marker_index - float(lower))
		canvas.draw_circle(marker, 12.0 * hs, Color(1, 1, 1, 0.28))
		canvas.draw_circle(marker, 8.0 * hs, Color(1, 1, 1, 0.96))
		canvas.draw_circle(marker, 4.0 * hs, tint)
	# 外端：一小段横杆当"头"，宽度随整体一起放大。
	var knob := 9.0 * cs
	if not hide_head:
		if highlight:
			canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(tint.r, tint.g, tint.b, 0.22 * fade), 15.0 * cs, false)
			canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(1, 1, 1, 0.30 * fade), 11.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(0, 0, 0, 0.55 * fade), 7.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(1, 1, 1, 0.95 * fade), 5.0 * cs, false)
		canvas.draw_line(boundary - normal * knob, boundary + normal * knob, Color(tint.r, tint.g, tint.b, 0.95 * fade), 2.6 * cs, false)
	if show_debug and t < note.beat + 0.02:
		var head := _flying_position(chart, note.angle, note.beat, t, pre, note.group_id)
		if _valid_point(head):
			canvas.draw_string(UITheme.bold_font(), head + Vector2(-14, -22), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tint.r, tint.g, tint.b, 0.85))
	if not hide_head and t >= note.beat and t <= note.end_beat:
		var glow := 0.5 + 0.5 * sin(t * PI)
		canvas.draw_arc(boundary, 28.0 * hs, 0.0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.28 * glow), 2.6, false)
	if _app != null and not note.visual_pts.is_empty():
		var selected: Note = _app.get_selected_note()
		if selected != null and selected.id == note.id:
			for point in note.visual_pts:
				var marker := _hold_node_screen(chart, note, float(point.get("db", 0.0)), float(point.get("da", 0.0)), t)
				if _valid_point(marker):
					_draw_diamond(canvas, marker, 5.5, tint)


func _draw_holds(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var ns := _note_scale()
	var visible: Array[Note] = []
	# 回溯窗口按真实最长音符算：写死 128 拍会白扫上千颗短音符。
	var back := pre * _max_group_speed_ratio(chart)
	for note in _notes_in_range(chart, t - back - chart.max_note_length_beats(), t + pre + 0.3):
		if note.type != "hold":
			continue
		var fade_beats := end_fade_beats(chart.timing.bpm_at(note.beat))
		if t >= _spawn_beat(chart, note.beat, note.group_id) and t <= note.end_beat + maxf(0.3, fade_beats):
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	var draw: Dictionary = {}
	var next_id := -1
	var next_lead := INF
	for note in visible:
		var state := note_state(note.id)
		var tint := _note_tint(note, UITheme.HOLD)
		var group_mul := chart.group_alpha(note.group_id) / 255.0
		var fade_beats := end_fade_beats(chart.timing.bpm_at(note.beat))
		var fade := 1.0
		if state == "hit":
			fade = clampf(1.0 - (t - float(note_state_beats.get(note.id, note.end_beat))) / fade_beats, 0.0, 1.0)
		elif state == "miss":
			if not note_state_beats.has(note.id):
				continue
			fade = clampf(1.0 - (t - float(note_state_beats[note.id])) / 0.24, 0.0, 1.0)
		elif t > note.end_beat:
			fade = clampf(1.0 - (t - note.end_beat) / fade_beats, 0.0, 1.0)
		if state == "slip":
			fade *= HOLD_SLIP_DIM
		fade *= group_mul
		if fade <= 0.01:
			continue
		var hide_head := state == "holding" or state == "slip" or t >= note.end_beat
		var straight := true
		for point in note.visual_pts:
			if absf(float(point.get("da", 0.0))) > 0.5:
				straight = false
				break
		var lead := note.beat - t
		var depth := hold_stack_alpha(lead, pre)
		draw[note.id] = {
			"fade": fade, "hide_head": hide_head, "tint": tint, "straight": straight,
			"body_fade": fade * depth,
			"cap_fade": fade * lerpf(1.0, 0.85, clampf(lead / maxf(0.5, pre * 2.0), 0.0, 1.0)),
		}
		if lead >= -0.02 and lead < next_lead:
			next_lead = lead
			next_id = note.id
	# 身体按 beat 降序：先到的最后画，叠在上面；后到的整体更淡。
	for note in visible:
		var d: Dictionary = draw.get(note.id, {})
		if d.is_empty():
			continue
		if bool(d["straight"]):
			_draw_hold_sector(canvas, chart, note, t, pre, float(d["body_fade"]), bool(d["hide_head"]), d["tint"], 0, false)
		else:
			_draw_bent_hold(canvas, chart, note, t, pre, float(d["body_fade"]), bool(d["hide_head"]), d["tint"], 0, false)
	# 头/尾/按住标记统一最后画：同角度叠在一起时，每个 Hold 的头都看得见。
	for note in visible:
		var d: Dictionary = draw.get(note.id, {})
		if d.is_empty():
			continue
		if bool(d["straight"]):
			_draw_hold_sector(canvas, chart, note, t, pre, float(d["cap_fade"]), bool(d["hide_head"]), d["tint"], 1, note.id == next_id)
		else:
			_draw_bent_hold(canvas, chart, note, t, pre, float(d["cap_fade"]), bool(d["hide_head"]), d["tint"], 1, note.id == next_id)


func _draw_notes(canvas: Control, chart: Chart, t: float, pre: float) -> void:
	var visible: Array[Note] = []
	# 试玩里音符留到判定出来为止（MISS 窗口最长 0.3s），编辑器预览仍只多留 0.3 拍。
	var tail_beats := 2.0 if playtest_mode else 0.3
	for note in _notes_around(chart, t, 0.1, 0.1):
		if note.type in ["path", "hold", "seek"]:
			continue
		if t >= _spawn_beat(chart, note.beat, note.group_id) and t <= note.beat + tail_beats:
			visible.append(note)
	visible.sort_custom(func(a: Note, b: Note) -> bool: return a.beat > b.beat)
	for note in visible:
		if note_is_retired(note_state(note.id)):
			continue
		match note.type:
			"tap":
				_draw_tap_note(canvas, chart, note, t, pre)
			"anchor":
				_draw_anchor(canvas, chart, note, t)
			"bell":
				_draw_bell(canvas, chart, note, t)


func _anchor_gem_position(landing: Vector2, fall_ratio: float) -> Vector2:
	if not _valid_point(landing):
		return landing
	# 和 Tap / Bell / Seek 同一条下落曲线：出生 1/6 半径，判定拍落到锚点上。
	return project_design(Vector2.ZERO).lerp(landing, fall_ratio)


func _draw_anchor(canvas: Control, chart: Chart, note: Note, beat: float) -> void:
	var alpha: float = chart.group_alpha(note.group_id) / 255.0
	var landing: Vector2 = project_u(fposmod(note.angle, 360.0) / 360.0, beat)
	if alpha <= 0.001 or not _valid_point(landing):
		return
	var progress: float = _note_progress(chart, note, beat)
	var ns: float = maxf(1.0, _note_scale())
	var tint: Color = UITheme.VIOLET
	# 靶子先浮现在环上：淡入 + 0.8→1 倍微放大，之后一直留到判定。
	var marker: float = smoothstep(0.0, 0.16, progress)
	if marker > 0.001:
		_draw_anchor_cue(canvas, landing, lerpf(15.0, 23.0, marker) * ns, ns, tint, alpha * marker)
	var partner: Note = chart.anchor_partner(note)
	if partner != null and note.id < partner.id and not note_is_retired(note_state(partner.id)):
		var partner_progress: float = _note_progress(chart, partner, beat)
		var partner_marker: float = smoothstep(0.0, 0.16, partner_progress)
		var partner_point: Vector2 = project_u(fposmod(partner.angle, 360.0) / 360.0, beat)
		var offset: Vector2 = partner_point - landing
		if partner_marker > 0.001 and _valid_point(partner_point) and offset.length_squared() > 4.0:
			var inset: Vector2 = offset.limit_length(68.0 * ns) * 0.25
			var start: Vector2 = landing + inset
			var end: Vector2 = partner_point - inset
			# 双押线跟着宝石走：前半段只有四角靶框，宝石走近了才把两颗连起来。
			var line_fade: float = smoothstep(0.50, 0.75, minf(progress, partner_progress))
			var line_alpha: float = minf(marker * alpha, partner_marker * chart.group_alpha(partner.group_id) / 255.0) * line_fade
			var tip: Color = Color(tint, 0.80 * line_alpha)
			var middle: Color = Color(tint, 0.24 * line_alpha)
			canvas.draw_polyline_colors(PackedVector2Array([start, start.lerp(end, 0.20), start.lerp(end, 0.80), end]),
				PackedColorArray([tip, middle, middle, tip]), 2.0 * ns, true)
	# 宝石：从圆心落到靶子上，路上由小变大。
	var gem_point: Vector2 = _anchor_gem_position(landing, lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress))
	_draw_anchor_gem(canvas, gem_point, 29.0 * ns * lerpf(0.4, 1.0, progress), ns, tint,
		alpha * smoothstep(0.0, 0.10, progress))


func _draw_anchor_cue(canvas: Control, point: Vector2, radius: float, size: float, tint: Color, alpha: float) -> void:
	var corners: PackedVector2Array = PackedVector2Array()
	for i in 4:
		var radial: Vector2 = Vector2.UP.rotated(float(i) * PI * 0.5)
		var tip: Vector2 = point + radial * radius
		var foot: Vector2 = tip - radial * (0.34 * radius)
		var across: Vector2 = radial.orthogonal() * (0.34 * radius)
		corners.append_array(PackedVector2Array([foot - across, tip, tip, foot + across]))
	canvas.draw_multiline(corners, Color(0.06, 0.03, 0.16, 0.85 * alpha), 4.5 * size, true)
	canvas.draw_multiline(corners, Color(tint.lerp(Color.WHITE, 0.30), 0.96 * alpha), 2.1 * size, true)


## 锚点的宝石沿用远端 main 的菱形：黑描边 + 白描边 + 半透明紫色填充 + 中心点。
func _draw_anchor_gem(canvas: Control, point: Vector2, radius: float, _size: float, tint: Color, alpha: float) -> void:
	if not _valid_point(point):
		return
	var points := PackedVector2Array([
		point + Vector2(0.0, -radius),
		point + Vector2(radius, 0.0),
		point + Vector2(0.0, radius),
		point + Vector2(-radius, 0.0),
	])
	points.append(points[0])
	canvas.draw_polyline(points, Color(0.0, 0.0, 0.0, 0.66 * alpha), 5.0, true)
	canvas.draw_polyline(points, Color(1.0, 1.0, 1.0, 0.94 * alpha), 3.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], points[3]]),
		Color(tint.r, tint.g, tint.b, 0.32 * alpha))
	canvas.draw_polyline(points, Color(tint.r, tint.g, tint.b, alpha), 1.7, true)
	canvas.draw_circle(point, maxf(2.0, radius * 0.26), Color(0.0, 0.0, 0.0, 0.68 * alpha))
	canvas.draw_circle(point, maxf(1.2, radius * 0.14), Color(1.0, 1.0, 1.0, 0.92 * alpha))


func _draw_tap_note(canvas: Control, chart: Chart, note: Note, t: float, pre: float) -> void:
	# 长度系统：普通 Tap = 0.5 l，大小 Tap = size_ratio × l；条带随半径从 1/6 长到 1。
	# 修饰：HS 改变下落进度；spawn 抬高出生半径；bounce 让落点外凸/内凹；alpha 整体淡出。
	var progress := _note_progress(chart, note, t)
	var q := _note_radius_scale(note, progress)
	var tint := _note_tint(note, UITheme.PINK)
	var center_point := _draw_length_band(canvas, chart, note.angle, note.arc_width(), q, t, tint,
		chart.group_alpha(note.group_id) / 255.0)
	if show_debug and _valid_point(center_point):
		var ns := _note_scale()
		canvas.draw_string(UITheme.bold_font(), center_point + Vector2(-12, -22), "TAP %.0f°%s" % [note.arc_width(), " ×l %.2f" % note.size_ratio if note.sized else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(tint.r, tint.g, tint.b, 0.85))


## Tap 与 Hold 头共用的“长度条”：一段按 radius_scale 缩放的弧带 + 两端圆头 + 中心点。
## 返回中心点屏幕坐标（可能为 INF）。
func _draw_length_band(canvas: Control, chart: Chart, angle: float, width: float, radius_scale: float, t: float, color: Color, alpha: float = 1.0) -> Vector2:
	var ns := _note_scale()
	var radius := maxf(0.0, radius_scale)
	if width <= 0.05:
		# 长度为 0 的大小 Tap 仍然占一个位置，留一个点提示它存在。
		var tip := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, t)
		if bool(tip.get("gap", false)):
			return Vector2(INF, INF)
		var dot := project_design((tip.point as Vector2) * radius)
		if _valid_point(dot):
			canvas.draw_circle(dot, 7.0 * ns, Color(color.r, color.g, color.b, 0.90 * alpha))
		return dot
	# 省电档也只是降采样，不能再低到把长条画成折线。
	var steps := clampi(int(width / (4.0 if note_detail_fine else 6.0)), 16, 96)
	var points := PackedVector2Array()
	for i in steps + 1:
		var sample_angle := angle - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(sample_angle, 360.0) / 360.0, t)
		if bool(data.get("gap", false)):
			continue
		var p := project_design(data.point * radius)
		if _valid_point(p):
			points.append(p)
	if points.size() < 2:
		return Vector2(INF, INF)
	# 胶囊本体（黑描边 + 白边 + 色带 + 高光）永远画；画质项只决定最外层柔光。
	# 之前把整次 _stroke_band 塞进 if note_glow，关光晕时 Tap / Hold 头只剩几个点。
	_stroke_band(canvas, points, color, 18.0 * ns, alpha, -1.0, 0.35 if note_glow else 0.0)
	var cap_scale := ns * float(_skin()["scale"])
	var center_point := points[points.size() / 2]
	# 两端圆头：让长条读成一根胶囊，而不是一段没有边界的弧。
	for cap in [points[0], points[-1]]:
		canvas.draw_circle(cap, 12.0 * cap_scale, Color(0, 0, 0, 0.66 * alpha))
		canvas.draw_circle(cap, 9.5 * cap_scale, Color(1, 1, 1, 0.94 * alpha))
		canvas.draw_circle(cap, 6.0 * cap_scale, Color(color.r, color.g, color.b, alpha))
	# 中心命中点：宽度变化时仍然知道该按哪里。
	canvas.draw_circle(center_point, 8.0 * cap_scale, Color(0, 0, 0, 0.55 * alpha))
	canvas.draw_circle(center_point, 6.0 * cap_scale, Color(1, 1, 1, 0.96 * alpha))
	canvas.draw_circle(center_point, 3.0 * cap_scale, color)
	return center_point


static func ease_out_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _draw_seeks(canvas: Control, chart: Chart, t: float) -> void:
	var now_ms: float = chart.timing.beat_to_chart_ms(t)
	_draw_seek_warnings(canvas, _seek_warnings(chart, t, now_ms))
	var cursor: Vector2 = auto_cursor if auto_cursor.is_finite() else mouse_screen
	for note in _notes_around(chart, t, 2.0, 0.5):
		if note.type != "seek" or t < _spawn_beat(chart, note.beat, note.group_id):
			continue
		var state: String = note_state(note.id)
		var state_beat: float = float(note_state_beats.get(note.id, note.beat))
		var exit_ms: float = now_ms - chart.timing.beat_to_chart_ms(state_beat)
		var inward: bool = note.seek_orien == 1
		var color: Color = UITheme.SEEK_IN if inward else UITheme.SEEK_OUT
		var fade: float = 1.0
		var ring_scale: float = 1.0
		var push: float = 0.0
		if state == "hit" and exit_ms >= 0.0:
			var p: float = clampf(exit_ms / 80.0, 0.0, 1.0)
			fade = 1.0 - p
			ring_scale = 1.0 + 0.06 * p
			push = 10.0 * ease_out_cubic(p)
		elif state == "miss" and exit_ms >= 0.0:
			fade = 1.0 - clampf(exit_ms / 120.0, 0.0, 1.0)
			color = UITheme.RED
		elif t > note.beat:
			fade = clampf((note.beat + 0.5 - t) / 0.5, 0.0, 1.0)
		fade *= chart.group_alpha(note.group_id) / 255.0
		if fade <= 0.001:
			continue
		var grow: float = _note_progress(chart, note, t)
		# 线宽和环半径都用同一条 1/6 → 1 的下落曲线，观感和 Tap 一致。
		var size: float = _note_scale() * seek_grow_scale(grow)
		var emphasis: float = smoothstep(0.38, 1.0, grow)
		var scale: float = seek_grow_scale(grow) * ring_scale
		_draw_seek_ring(canvas, note, t, scale, size, color, fade, push, emphasis)
		# 就位提示：窄 Seek 的光标已经站在弧上、且进入判定窗口时收一圈亮环。
		if note.seek_width() < 359.5 and state.is_empty() \
				and absf(now_ms - chart.timing.beat_to_chart_ms(note.beat)) <= SEEK_ARM_MS \
				and seek_contains(note, t, cursor):
			var armed: PackedVector2Array = seek_arc_points(note, t, scale)
			if armed.size() >= 2:
				canvas.draw_polyline(armed, Color(1, 1, 1, 0.30 * fade), 20.0 * size, true)
				canvas.draw_polyline(armed, Color(color.lightened(0.55), 0.95 * fade), 2.6 * size, true)


## Use chart time so the warning survives BPM changes and follows a scrubbed playhead.
## 只警示最近一档：同一时刻的多颗 Seek（含反向）一起返回。
## 窄 Seek 带自己的中心角和弧宽，警示弧也只画在那一段上。
func _seek_warnings(chart: Chart, beat: float, now_ms: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first_beat: float = chart.timing.chart_ms_to_beat(now_ms - SEEK_WARNING_MS)
	var last_beat: float = chart.timing.chart_ms_to_beat(now_ms + SEEK_WARNING_MS)
	var previous_ms: float = -INF
	var target_ms: float = INF
	var targets: Array[Note] = []
	for note in _notes_in_range(chart, first_beat, last_beat):
		if note.type != "seek" or not chart.note_enabled(note):
			continue
		var alpha: float = chart.group_alpha(note.group_id) / 255.0
		if alpha <= 0.0:
			continue
		var note_ms: float = chart.timing.beat_to_chart_ms(note.beat)
		if note.beat <= beat:
			previous_ms = note_ms
			continue
		if note_is_retired(note_state(note.id)):
			continue
		if note_ms < target_ms - 0.5:
			targets.clear()
			target_ms = note_ms
		if note_ms > target_ms + 0.5:
			break
		targets.append(note)
	if targets.is_empty() or not is_finite(target_ms) or target_ms <= now_ms:
		return result
	var start_ms: float = maxf(target_ms - SEEK_WARNING_MS, previous_ms)
	var phase: float = (now_ms - start_ms) / maxf(1.0, target_ms - start_ms)
	var ramp: float = ease_out_cubic(phase / 0.85)
	for note in targets:
		result.append({
			"angle": fposmod(note.angle, 360.0),
			"width": note.seek_width(),
			"orien": note.seek_orien,
			"strength": chart.group_alpha(note.group_id) / 255.0 * ramp,
		})
	return result


## 整圈 Seek 按方向合并成半圈/整圈；窄 Seek 各画各的弧。
func _draw_seek_warnings(canvas: Control, warnings: Array[Dictionary]) -> void:
	var inward := 0.0
	var outward := 0.0
	for warning in warnings:
		var width: float = float(warning.get("width", 360.0))
		var strength: float = float(warning.get("strength", 0.0))
		if width < 359.5:
			_draw_seek_warning_arc(canvas,
				deg_to_rad(float(warning.get("angle", 0.0)) - width * 0.5), deg_to_rad(width),
				UITheme.SEEK_IN if int(warning.get("orien", 0)) == 1 else UITheme.SEEK_OUT, strength)
		elif int(warning.get("orien", 0)) == 1:
			inward = maxf(inward, strength)
		else:
			outward = maxf(outward, strength)
	if inward > 0.0 and outward > 0.0:
		_draw_seek_warning_arc(canvas, PI * 0.5, PI, UITheme.SEEK_IN, inward)
		_draw_seek_warning_arc(canvas, -PI * 0.5, PI, UITheme.SEEK_OUT, outward)
	elif inward > 0.0 or outward > 0.0:
		_draw_seek_warning_arc(canvas, 0.0, TAU, UITheme.SEEK_IN if inward > 0.0 else UITheme.SEEK_OUT,
			maxf(inward, outward))


## 窄 Seek 的判定弧（屏幕折线）；整圈返回空数组，调用方走原来的整圈分支。
func seek_arc_points(note: Note, beat: float, scale: float = 1.0) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var width: float = note.seek_width()
	if width >= 359.5:
		return points
	var steps: int = clampi(int(width / 4.0), 6, 96)
	var first: float = fposmod(note.angle, 360.0) - width * 0.5
	for i in steps + 1:
		var p: Vector2 = _arc_point_scaled(first + width * float(i) / float(steps), beat, scale)
		if _valid_point(p):
			points.append(p)
	return points


## 光标是否站在这段弧上（±55px，和 Bell 同一套容差）；整圈 Seek 恒为真。
func seek_contains(note: Note, beat: float, point: Vector2) -> bool:
	if note.seek_width() >= 359.5:
		return true
	if not point.is_finite():
		return false
	var arc: PackedVector2Array = seek_arc_points(note, beat)
	return arc.size() >= 2 and _point_polyline_distance(arc, point) <= BELL_RADIAL_TOLERANCE


## 弧的中点（AUTO 光标和判定字都落在这里）。
func seek_screen(note: Note, beat: float) -> Vector2:
	return _arc_point_scaled(fposmod(note.angle, 360.0), beat, 1.0)


func _draw_seek_warning_arc(canvas: Control, angle: float, span: float, tint: Color, alpha: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = roundi(96.0 * span / TAU)
	for i in steps + 1:
		var p: Vector2 = project_design(Vector2.from_angle(angle + span * float(i) / float(steps)) * 478.0)
		if not _valid_point(p):
			return
		points.append(p)
	var size: float = _note_scale()
	if note_glow:
		canvas.draw_polyline(points, Color(tint, 0.19 * alpha), 30.0 * size, true)
		canvas.draw_polyline(points, Color(tint, 0.32 * alpha), 21.0 * size, true)
	canvas.draw_polyline(points, Color(tint.darkened(0.73), 0.91 * alpha), 17.0 * size, true)
	canvas.draw_polyline(points, Color(tint, 0.98 * alpha), 12.0 * size, true)
	canvas.draw_polyline(points, Color(tint.lightened(0.44), 0.94 * alpha), 4.0 * size, true)


func _draw_seek_ring(canvas: Control, note: Note, beat: float, scale: float, size: float, color: Color, alpha: float, push: float, emphasis: float) -> void:
	var center: Vector2 = project_design(Vector2.ZERO)
	var band_alpha: float = alpha * lerpf(0.72, 1.0, emphasis)
	var arrow_alpha: float = alpha * lerpf(0.68, 1.0, emphasis)
	var inward: bool = note.seek_orien == 1
	var width: float = note.seek_width()
	var first: float = fposmod(note.angle, 360.0) - width * 0.5
	var full: bool = width >= 359.5
	# 弧带：整圈是一个闭合的圆（材质和 Tap 一样，只换颜色）；窄弧画成一整段。
	if full:
		var ring: PackedVector2Array = PackedVector2Array()
		var ring_steps: int = 96 if note_detail_fine else 72
		for j in ring_steps + 1:
			var p: Vector2 = _arc_point_scaled(360.0 * float(j) / float(ring_steps), beat, scale)
			if not _valid_point(p):
				_draw_seek_band(canvas, ring, size, color, band_alpha, true)
				ring.clear()
				continue
			ring.append(p)
		_draw_seek_band(canvas, ring, size, color, band_alpha, true)
	else:
		var run: PackedVector2Array = PackedVector2Array()
		var steps: int = clampi(int(width / 3.0), 8, 96)
		for j in steps + 1:
			var p: Vector2 = _arc_point_scaled(first + width * float(j) / float(steps), beat, scale)
			if not _valid_point(p):
				_draw_seek_band(canvas, run, size, color, band_alpha)
				run.clear()
				continue
			run.append(p)
		_draw_seek_band(canvas, run, size, color, band_alpha)
	# 箭头：整圈 12 组；窄弧按 45° 一组，至少给一组。
	var arrows: int = 12 if full else clampi(roundi(width / 45.0), 1, 12)
	var spots: Array[Vector2] = []
	for i in arrows:
		var angle: float = fposmod(note.angle, 360.0) if arrows == 1 \
			else first + width * (float(i) + 0.5) / float(arrows)
		var anchor: Vector2 = _arc_point_scaled(angle, beat, scale)
		if _valid_point(anchor):
			spots.append(anchor)
	# 超过半圈时只在下半侧画箭头，上半侧留白，免得整圈都是箭头；
	# 弧整体在上半侧时至少留最靠下的一组，否则读不出方向。
	if width > 180.0 and not spots.is_empty():
		var lower: Array[Vector2] = []
		for spot in spots:
			if spot.y >= center.y:
				lower.append(spot)
		if lower.is_empty():
			var lowest: Vector2 = spots[0]
			for spot in spots:
				if spot.y > lowest.y:
					lowest = spot
			lower.append(lowest)
		spots = lower
	for spot in spots:
		var radial: Vector2 = (spot - center)
		if radial.is_zero_approx():
			continue
		radial = radial.normalized()
		# Seek Out 箭头朝圆心、Seek In 箭头朝环外。
		var direction: Vector2 = radial if inward else -radial
		var tip: Vector2 = spot + radial * push * size + direction * (35.0 * size)
		_draw_seek_chevron(canvas, tip, direction, 25.0 * size, color, arrow_alpha)


func _draw_seek_chevron(canvas: Control, tip: Vector2, direction: Vector2, depth: float, color: Color, alpha: float) -> void:
	var back: Vector2 = tip - direction * depth
	var wing: Vector2 = direction.orthogonal() * (0.76 * depth)
	var points: PackedVector2Array = PackedVector2Array([
		tip, back + wing, back + wing * 0.39, tip - direction * (0.62 * depth), back - wing * 0.39, back - wing,
	])
	canvas.draw_colored_polygon(points, Color(color, alpha))
	points.append(tip)
	canvas.draw_polyline(points, Color(0.034, 0.047, 0.076, 0.8 * alpha), 1.2, true)


## 判定环上的 Seek 弧带：材质和 Tap 完全相同（同样的 _stroke_band、同样的圆头），
## 只是颜色按朝向区分；整圈是闭合的圆，没有端头。
func _draw_seek_band(canvas: Control, points: PackedVector2Array, size: float, color: Color, alpha: float, closed: bool = false) -> void:
	if points.size() < 2:
		return
	_stroke_band(canvas, points, color, SEEK_BAND_WIDTH * size, alpha, -1.0, 0.35 if note_glow else 0.0)
	if closed:
		return
	var cap_scale: float = size * float(_skin()["scale"])
	for cap in [points[0], points[-1]]:
		canvas.draw_circle(cap, 12.0 * cap_scale, Color(0, 0, 0, 0.66 * alpha))
		canvas.draw_circle(cap, 9.5 * cap_scale, Color(1, 1, 1, 0.94 * alpha))
		canvas.draw_circle(cap, 6.0 * cap_scale, Color(color.r, color.g, color.b, alpha))


func _draw_onion(canvas: Control, chart: Chart, beat: float) -> void:
	if onion_shapes.is_empty():
		return
	for item in onion_shapes:
		if not (item is BoundaryShape):
			continue
		var shape: BoundaryShape = item
		var run := PackedVector2Array()
		for i in 97:
			var data := shape.point_at(float(i) / 96.0)
			if bool(data.get("gap", false)):
				if run.size() > 1:
					canvas.draw_polyline(run, Color(1, 1, 1, 0.16), 1.0, true)
				run = PackedVector2Array()
				continue
			var p := project_design(data.point)
			if _valid_point(p):
				run.append(p)
		if run.size() > 1:
			canvas.draw_polyline(run, Color(1, 1, 1, 0.16), 1.0, true)


func _draw_boundary_controls(canvas: Control, chart: Chart) -> void:
	if not show_debug and not (_app != null and _app.boundary_mode):
		return
	var shape := _active_shape()
	if shape == null:
		return
	var sorted := shape.sorted_segments()
	var points := shape.vertices()
	var selected: int = -1 if _app == null else int(_app.selected_segment_index)
	for index in points.size():
		var color := UITheme.CORAL if index == selected else UITheme.CYAN
		var p := project_design(points[index])
		if _valid_point(p):
			var rect := Rect2(p - Vector2(5, 5), Vector2(10, 10))
			canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.95))
			canvas.draw_rect(rect, UITheme.BG, false, 1.0)
		if index == selected and index < sorted.size():
			_draw_segment_highlight(canvas, sorted[index], selected)


func _draw_segment_highlight(canvas: Control, segment: BoundarySegment, _index: int) -> void:
	var points := PackedVector2Array()
	for i in 33:
		var p := project_design(segment.point_at(float(i) / 32.0))
		if _valid_point(p):
			points.append(p)
	if points.size() > 1:
		canvas.draw_polyline(points, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.45), 6.0, false)


func _draw_cursor(canvas: Control, chart: Chart, t: float) -> void:
	if not custom_cursor_visible or (not mouse_inside and not playtest_mode):
		return
	_draw_player_cursor(canvas)
	if playtest_mode:
		return
	var p := project_u(cursor_u, t)
	if cursor_valid and _valid_point(p):
		canvas.draw_circle(p, 7.0, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.22))
		canvas.draw_arc(p, 6.5, 0.0, TAU, 24, UITheme.CORAL, 1.6, false)
		canvas.draw_circle(p, 1.8, UITheme.CORAL)
		if show_debug:
			canvas.draw_string(UITheme.mono_font(), p + Vector2(12, 22), "u %.1f°" % (cursor_u * 360.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


func _draw_player_cursor(canvas: Control) -> void:
	var accent := UITheme.CYAN if cursor_valid or playtest_mode else UITheme.MUTED
	var cs := clampf(cursor_scale, 0.5, 2.0)
	# osu 风格拖尾：连续线段填补采样空隙，越靠近光标越大、越亮，停手后自然消失。
	for i in range(1, _cursor_trail.size()):
		var previous: Dictionary = _cursor_trail[i - 1]
		var current: Dictionary = _cursor_trail[i]
		var life := clampf(1.0 - float(current.get("age", 0.0)) / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i) / float(maxi(1, _cursor_trail.size() - 1))
		canvas.draw_line(previous["pos"], current["pos"], Color(accent.r, accent.g, accent.b, 0.10 * life), lerpf(2.5, 9.0, ratio) * cs, false)
	for i in _cursor_trail.size():
		var item: Dictionary = _cursor_trail[i]
		var age := float(item.get("age", 0.0))
		var life := clampf(1.0 - age / 0.26, 0.0, 1.0)
		if life <= 0.01:
			continue
		var ratio := float(i + 1) / float(maxi(1, _cursor_trail.size()))
		var point: Vector2 = item["pos"]
		var radius := lerpf(3.0, 10.5, ratio) * cs
		canvas.draw_circle(point, radius, Color(accent.r, accent.g, accent.b, 0.26 * life))
		canvas.draw_circle(point, radius * 0.45, Color(1, 1, 1, 0.16 * life))
	var m := mouse_screen
	var spin := _anim_ms() / 1000.0 * 2.2
	canvas.draw_circle(m, 27.0 * cs, Color(accent.r, accent.g, accent.b, 0.035))
	canvas.draw_circle(m, 20.0 * cs, Color(accent.r, accent.g, accent.b, 0.06))
	canvas.draw_arc(m, 19.5 * cs, spin, spin + PI * 0.85, 22, Color(accent.r, accent.g, accent.b, 0.72), 1.7 * cs, false)
	canvas.draw_arc(m, 19.5 * cs, spin + PI, spin + PI * 1.75, 22, Color(accent.r, accent.g, accent.b, 0.34), 1.2 * cs, false)
	canvas.draw_arc(m, CURSOR_MAIN_RADIUS * cs, 0.0, TAU, 48, Color(0, 0, 0, 0.62), 5.4 * cs, false)
	canvas.draw_arc(m, CURSOR_MAIN_RADIUS * cs, 0.0, TAU, 48, Color(1, 1, 1, 0.96), CURSOR_MAIN_STROKE * cs, false)
	canvas.draw_arc(m, 9.2 * cs, 0.0, TAU, 36, Color(accent.r, accent.g, accent.b, 0.95), 2.0 * cs, false)
	canvas.draw_circle(m, 4.4 * cs, Color(0, 0, 0, 0.78))
	canvas.draw_circle(m, 2.5 * cs, Color(1, 1, 1, 0.98))
	for k in 4:
		var direction := Vector2.from_angle(float(k) * PI * 0.5)
		canvas.draw_line(m + direction * 15.5 * cs, m + direction * 19.0 * cs, Color(1, 1, 1, 0.42), 1.2 * cs, false)
	if not cursor_valid and playtest_mode and show_debug:
		canvas.draw_string(UITheme.mono_font(), m + Vector2(18, -16), "环外", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)


## 装饰动画的时钟：用谱面时间而不是墙钟，否则同一份 replay 两次导出像素不同。
func _anim_ms() -> float:
	var chart := get_chart()
	if chart == null:
		return 0.0
	return chart.timing.beat_to_chart_ms(get_time_beat())


func request_redraw() -> void:
	_mesh_dirty = true
	if _overlay != null:
		_overlay.queue_redraw()


## 播放头移动：只重画覆盖层 + 让 3D 出一帧，不强制重建环网格。
## 拖动时同一拍会收到多次事件，强建等于每帧重传 3 个网格。
## 网格本身由 _process 的 mesh_key 决定，真的跨了拍自然会重建。
func request_playhead_redraw() -> void:
	if is_processing():
		_playhead_redraw_pending = true
	elif _overlay != null:
		_overlay.queue_redraw()
	_force_3d_frame = true


func add_hit_pulse(point: Vector2, color: Color, label: String = "HIT", kind: String = "tap", detail: String = "") -> void:
	if not _valid_point(point):
		return
	# 同一位置连续判定时把文字错开，避免完全叠在一起。
	var stack := 0
	for other in _pulses:
		if (other["pos"] as Vector2).distance_to(point) < 56.0:
			stack += 1
	_pulses.append({
		"pos": point, "age": 0.0, "color": color, "label": label, "kind": kind,
		"detail": detail,
		"scale": tier_fx_scale(label),
		"label_y": float(stack % 3) * 22.0,
	})
	# 特效预算：密集段最多同时保留 20 个脉冲，超出丢最旧的。
	while _pulses.size() > 20:
		_pulses.pop_front()
	if _overlay != null:
		_overlay.queue_redraw()


## 命中退场的淡出时长换算成拍：绘制用的是拍时间，手感按秒算。
static func end_fade_beats(bpm: float) -> float:
	return END_FADE_SEC * maxf(1.0, bpm) / 60.0


## 档位越差，爆点越小：BAD 看起来不该和 PERFECT 一样大。
static func tier_fx_scale(label: String) -> float:
	match label:
		"GREAT": return 0.92
		"GOOD": return 0.82
		"BAD": return 0.68
	return 1.0


## 命中后留在原地的音符本体：整体放大到数倍并淡出（osu!std 击打光）。
func add_note_pop(kind: String, note: Note, beat: float) -> void:
	var chart := get_chart()
	if chart == null or fx_budget == "off":
		return
	var ns := _note_scale()
	var pop := {"kind": kind, "age": 0.0}
	if kind == "anchor":
		var point := note_head_screen(note, beat)
		if not _valid_point(point):
			return
		pop["point"] = point
		pop["color"] = UITheme.VIOLET
		pop["base"] = 24.0 * maxf(1.0, _note_scale())
		pop["shards"] = _take_shard_slot()
	elif kind == "path":
		# 只放大环上的星头标记；下落星星和尾环继续走原来的淡出。
		var point := _path_screen_point(chart, note, 0.0, beat)
		if not _valid_point(point):
			return
		pop["point"] = point
		pop["color"] = note.resolved_color(chart, Note.DEFAULT_PATH_COLOR)
		var base_scale := clampf(ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE, 0.2, 2.0)
		pop["base"] = base_scale * float(_skin()["scale"]) * PATH_SIZE_SCALE * PATH_HEAD_SCALE
		pop["arc_base"] = ns * PATH_SIZE_SCALE * PATH_HEAD_SCALE
	elif kind == "bell":
		# 金键是弧带：命中时沿弧带整体放大，和 Anchor 同一套命中语言。
		var band: PackedVector2Array = PackedVector2Array(bell_live_band(note, beat))
		if band.size() < 2:
			return
		pop["points"] = band
		pop["center"] = band[band.size() / 2]
		pop["color"] = UITheme.KEY_YELLOW
		pop["width"] = BELL_BAND_HALF * 2.0 * float(_skin()["scale"])
		pop["shards"] = _take_shard_slot()
	else:
		var points := note_live_band(note, beat)
		if points.size() < 2:
			return
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= float(points.size())
		var skin := _skin()
		pop["points"] = points
		pop["center"] = center
		pop["color"] = UITheme.GOLD if kind == "hold" else UITheme.PINK
		pop["width"] = 18.0 * ns * float(skin["scale"]) * float(skin["band"])
		pop["cap"] = 6.0 * ns * float(skin["scale"])
	_note_pops.append(pop)
	while _note_pops.size() > 24:
		_note_pops.pop_front()
	if _overlay != null:
		_overlay.queue_redraw()


## 稳定伪随机：同一 index/salt 每帧结果一样，导出才可复现（不能用全局随机源）。
static func _stable_hash(index: int, salt: float) -> float:
	var value: float = sin(float(index) * 12.9898 + (salt + 1.0) * 78.233) * 43758.5453
	return value - floor(value)


## 碎屑预算：本体碎屑（Bell / Anchor）和环上碎屑共用 SHARD_GROUP_BUDGET 组。
func _take_shard_slot() -> bool:
	if fx_budget != "full":
		return false
	var used := 0
	for pop in _note_pops:
		if bool(pop.get("shards", false)):
			used += 1
	for light in _ring_lights:
		if bool(light.get("shards", false)):
			used += 1
	return used < SHARD_GROUP_BUDGET


## 环上回应（WACCA 式）：PERFECT 命中才在判定环外侧亮一段柔光扇 + 向外飞的三角碎屑。
## 只由「PERFECT 特效」和「命中特效」控制，和音符光晕无关。
func add_ring_light(note: Note, perfect: bool) -> void:
	if note == null or not perfect or not show_perfect_fx or fx_budget == "off":
		return
	var chart := get_chart()
	var fallback: Color = UITheme.PINK
	match note.type:
		"hold":
			fallback = UITheme.HOLD
		"bell":
			fallback = UITheme.KEY_YELLOW
		"anchor":
			fallback = UITheme.VIOLET
	var color: Color = note.resolved_color(chart, fallback) if chart != null else fallback
	_ring_lights.append({"angle": fposmod(note.angle, 360.0), "color": color, "age": 0.0,
		"shards": _take_shard_slot()})
	while _ring_lights.size() > SHARD_GROUP_BUDGET:
		_ring_lights.pop_front()
	if _overlay != null:
		_overlay.queue_redraw()


func _draw_ring_lights(canvas: Control, beat: float) -> void:
	if _ring_lights.is_empty():
		return
	var size: float = _note_scale()
	var center: Vector2 = project_design(Vector2.ZERO)
	for light in _ring_lights:
		var age: float = float(light.get("age", 0.0))
		var p: float = clampf(age / RING_LIGHT_SEC, 0.0, 1.0)
		if p >= 1.0:
			continue
		var alpha: float = pow(1.0 - p, 1.6)
		var color: Color = light["color"]
		var base: float = float(light["angle"])
		# 完整：三层按半径叠，贴环最亮、往外越宽越淡；精简：只留贴环那一层。
		var bands := [[RING_LIGHT_INNER * 1.01, 5.5, 0.75, 0.35]]
		if fx_budget == "full":
			bands = [
				[RING_LIGHT_INNER * 1.01, 5.5, 0.75, 0.35],
				[RING_LIGHT_INNER * 1.06, 13.0, 0.32, 0.15],
				[RING_LIGHT_INNER * 1.13, 24.0, 0.13, 0.05],
			]
		for band in bands:
			var line: PackedVector2Array = PackedVector2Array()
			var colors: PackedColorArray = PackedColorArray()
			for i in 17:
				var q: float = float(i) / 16.0 * 2.0 - 1.0
				var at: Vector2 = _arc_point_scaled(base + q * RING_LIGHT_SPAN, beat, float(band[0]))
				if not _valid_point(at):
					continue
				var envelope: float = pow(maxf(0.0, cos(q * PI * 0.5)), 1.4)
				line.append(at)
				colors.append(Color(color.lightened(float(band[3])), float(band[2]) * alpha * envelope))
			if line.size() >= 2:
				canvas.draw_polyline_colors(line, colors, float(band[1]) * size, true)
		# 向外飞的三角碎屑：没有预算就只留光扇。
		if not bool(light.get("shards", false)):
			continue
		var outer_scale: float = RING_LIGHT_OUTER
		for k in 4:
			var h: float = _stable_hash(k, 11.0)
			var at: Vector2 = _arc_point_scaled(base + lerpf(-RING_LIGHT_SPAN, RING_LIGHT_SPAN,
				(float(k) + 0.5) / 4.0), beat, outer_scale)
			if not _valid_point(at):
				continue
			var radial: Vector2 = (at - center).normalized()
			if radial.is_zero_approx():
				continue
			var side: Vector2 = radial.orthogonal() * (5.5 + 3.5 * h) * size * (1.0 - 0.45 * p)
			var tip: Vector2 = at + radial * lerpf(3.0, 15.0, p) * size
			var root: Vector2 = at + radial * 2.0 * size
			canvas.draw_colored_polygon(PackedVector2Array([tip, root + side, root - side]),
				Color(color.lightened(0.25), 0.8 * alpha))


static func note_pop_scale(age: float) -> float:
	var t := clampf(age / NOTE_POP_SEC, 0.0, 1.0)
	return 1.0 + (NOTE_POP_SCALE - 1.0) * (1.0 - pow(1.0 - t, 2.0))


func _draw_note_pops(canvas: Control) -> void:
	for pop in _note_pops:
		var age := float(pop.get("age", 0.0))
		var t := clampf(age / NOTE_POP_SEC, 0.0, 1.0)
		var alpha := 1.0 - t
		if alpha <= 0.01:
			continue
		var pop_scale := note_pop_scale(age)
		var color: Color = pop["color"]
		var flash := clampf(1.0 - age / 0.08, 0.0, 1.0)
		if String(pop.get("kind", "")) == "anchor":
			# 菱形放大淡出 + 四片小菱形向外濺开 + 白色十字光，观感对齐 Tap。
			var point: Vector2 = pop["point"]
			var s := float(pop["base"]) * pop_scale
			var diamond := PackedVector2Array([
				point + Vector2(0.0, -s),
				point + Vector2(s, 0.0),
				point + Vector2(0.0, s),
				point + Vector2(-s, 0.0),
				point + Vector2(0.0, -s),
			])
			canvas.draw_circle(point, s * 2.1, Color(color.r, color.g, color.b, 0.12 * alpha))
			canvas.draw_circle(point, s * 1.4, Color(color.r, color.g, color.b, 0.16 * alpha))
			if bool(pop.get("shards", false)):
				var spread := s * (1.25 + 1.55 * t)
				for i in 3:
					var a := TAU * float(i) / 3.0 + PI * 0.25
					var shard_center := point + Vector2(cos(a), sin(a)) * spread
					var shard_r := s * 0.30 * (1.0 - 0.45 * t)
					canvas.draw_colored_polygon(PackedVector2Array([
						shard_center + Vector2(0.0, -shard_r),
						shard_center + Vector2(shard_r, 0.0),
						shard_center + Vector2(0.0, shard_r),
						shard_center + Vector2(-shard_r, 0.0),
					]), Color(color.r, color.g, color.b, 0.75 * alpha))
			canvas.draw_polyline(diamond, Color(0, 0, 0, 0.60 * alpha), 5.0)
			canvas.draw_polyline(diamond, Color(1, 1, 1, 0.92 * alpha), 3.0)
			canvas.draw_colored_polygon(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3]]),
				Color(color.r, color.g, color.b, 0.32 * alpha))
			if flash > 0.0:
				var arm := s * (1.5 + 0.9 * (1.0 - flash))
				canvas.draw_line(point - Vector2(arm, 0.0), point + Vector2(arm, 0.0),
					Color(1, 1, 1, 0.75 * flash), 2.5, true)
				canvas.draw_line(point - Vector2(0.0, arm), point + Vector2(0.0, arm),
					Color(1, 1, 1, 0.75 * flash), 2.5, true)
				canvas.draw_circle(point, s * 0.9, Color(1, 1, 1, 0.30 * flash))
			continue
		if String(pop.get("kind", "")) == "path":
			# 星头落点标记整体放大：软光 + 黑底 + 白环 + 颜色外弧。
			var point: Vector2 = pop["point"]
			var s := float(pop["base"]) * pop_scale
			canvas.draw_circle(point, 31.0 * s, Color(color.r, color.g, color.b, 0.16 * alpha))
			canvas.draw_circle(point, 24.0 * s, Color(0, 0, 0, 0.30 * alpha))
			canvas.draw_arc(point, 24.0 * s, 0.0, TAU, 30, Color(1, 1, 1, 0.30 * alpha), 2.0, true)
			canvas.draw_arc(point, 28.0 * float(pop["arc_base"]) * pop_scale, 0.0, TAU, 30,
				Color(color.r, color.g, color.b, 0.95 * alpha), 2.4, true)
			if flash > 0.0:
				canvas.draw_circle(point, 16.0 * s, Color(1, 1, 1, 0.35 * flash))
			continue
		if String(pop.get("kind", "")) == "bell":
			# 和锚键同一套命中语言：弧带整体放大，外晕 + 黑底 + 白边 + 金芯。
			var points: PackedVector2Array = pop["points"]
			var middle: Vector2 = pop["center"]
			var ring_center: Vector2 = project_design(Vector2.ZERO)
			var half := float(pop["width"]) * 0.5 * pop_scale
			for layer in [
				[1.85, Color(color.r, color.g, color.b, 0.12 * alpha)],
				[1.02, Color(0, 0, 0, 0.50 * alpha)],
				[0.70, Color(1, 1, 1, 0.92 * alpha)],
				[0.34, Color(color.r, color.g, color.b, 0.96 * alpha)],
			]:
				var band_outer := PackedVector2Array()
				var band_inner := PackedVector2Array()
				var radius: float = half * float(layer[0])
				for p in points:
					var radial: Vector2 = (p - ring_center).normalized()
					var base: Vector2 = ring_center + (p - ring_center) * pop_scale
					band_outer.append(base + radial * radius)
					band_inner.append(base - radial * radius)
				_draw_gradient_band(canvas, band_outer, band_inner, layer[1], layer[1])
				for cap in [band_outer[0].lerp(band_inner[0], 0.5), band_outer[-1].lerp(band_inner[-1], 0.5)]:
					canvas.draw_circle(cap, radius, layer[1])
			if bool(pop.get("shards", false)):
				var shard := BELL_BAND_HALF * 0.32 * pop_scale * (1.0 - 0.5 * t)
				for i in 3:
					var at: Vector2 = points[mini(i * (points.size() - 1) / 2, points.size() - 1)]
					var radial: Vector2 = (at - ring_center).normalized()
					var shard_center := ring_center + (at - ring_center) * pop_scale + radial * (BELL_BAND_HALF * 1.7 * t)
					canvas.draw_colored_polygon(PackedVector2Array([
						shard_center + Vector2(0.0, -shard), shard_center + Vector2(shard, 0.0),
						shard_center + Vector2(0.0, shard), shard_center + Vector2(-shard, 0.0),
					]), Color(color.r, color.g, color.b, 0.78 * alpha))
			if flash > 0.0:
				canvas.draw_circle(middle, BELL_BAND_HALF * 1.6 * pop_scale, Color(1, 1, 1, 0.30 * flash))
			continue
		# Tap / Hold 头：把整条音符（带体 + 两端圆头 + 中心点）一起放大淡出。
		var points: PackedVector2Array = pop["points"]
		var center: Vector2 = pop["center"]
		var scaled := PackedVector2Array()
		for p in points:
			scaled.append(center + (p - center) * pop_scale)
		if scaled.size() < 2:
			continue
		var width := float(pop["width"]) * pop_scale
		var cap := float(pop["cap"]) * pop_scale
		canvas.draw_polyline(scaled, Color(0, 0, 0, 0.55 * alpha), width + 5.0 * pop_scale, true)
		canvas.draw_polyline(scaled, Color(1, 1, 1, 0.92 * alpha), width, true)
		canvas.draw_polyline(scaled, Color(color.r, color.g, color.b, 0.94 * alpha), maxf(3.0, width * 0.62), true)
		for endpoint in [scaled[0], scaled[-1]]:
			canvas.draw_circle(endpoint, cap * 2.0, Color(0, 0, 0, 0.66 * alpha))
			canvas.draw_circle(endpoint, cap * 1.58, Color(1, 1, 1, 0.94 * alpha))
			canvas.draw_circle(endpoint, cap, Color(color.r, color.g, color.b, 0.95 * alpha))
		var middle := scaled[scaled.size() / 2]
		canvas.draw_circle(middle, cap * 1.33, Color(0, 0, 0, 0.55 * alpha))
		canvas.draw_circle(middle, cap, Color(1, 1, 1, 0.96 * alpha))
		canvas.draw_circle(middle, cap * 0.5, color)
		if flash > 0.0:
			canvas.draw_polyline(scaled, Color(1, 1, 1, 0.50 * flash), maxf(2.0, width * 0.30), true)


## 判定字档位：PERFECT/FULL 最高，MISS/LOST 最低。未知标签保持显示。
static func judge_tier_rank(label: String) -> int:
	match label:
		"PERFECT", "FULL": return 0
		"GREAT": return 1
		"GOOD", "FRAY": return 2
		"BAD": return 3
		"MISS", "LOST": return 4
	return -1


static func judge_label_visible(label: String, filter: String) -> bool:
	if label.is_empty():
		return false
	var rank := judge_tier_rank(label)
	if rank < 0:
		return true
	match filter:
		"below_perfect": return rank >= 1
		"below_great": return rank >= 2
		"below_good": return rank >= 3
		"miss_only": return rank >= 4
		_: return true


func _draw_pulses(canvas: Control) -> void:
	# 判定字位置（试玩可切）：跟音符 / 屏幕中心 / 关。
	var judge_mode := "note"
	var judge_filter := "all"
	var judge_anchor := Vector2.ZERO
	var center_label_index := -1
	if playtest_mode:
		judge_mode = String(hud_options.get("judge_position", "ring_out"))
		judge_filter = String(hud_options.get("judge_filter", "all"))
		if judge_mode == "center":
			judge_anchor = _screen_affine()[0] + Vector2(0, -90.0 * clampf(size.y / 900.0, 0.8, 1.8))
			# 居中固定位只画最新一条判定，否则 0.42s 内的脉冲会叠成一团。
			for i in range(_pulses.size() - 1, -1, -1):
				if judge_label_visible(String(_pulses[i].get("label", "")), judge_filter):
					center_label_index = i
					break
	# 脉冲多时只给最新的 6 个画完整特效，其余降级成一个细环。
	# 画质项「精简」把爆点缩小，「关」只留判定字（星头不受影响）。
	var crowded := fx_budget != "full" or _pulses.size() > 6
	for index in _pulses.size():
		var pulse: Dictionary = _pulses[index]
		var age := float(pulse.get("age", 0.0))
		var alpha := clampf(1.0 - age / 0.42, 0.0, 1.0)
		var point: Vector2 = pulse["pos"]
		var color: Color = pulse["color"]
		var kind := String(pulse.get("kind", "tap"))
		# 星头和 Seek 的功能性提示自带一套，不受「命中特效」三档影响；其余按档位缩放爆点。
		var own_fx := kind in ["path", "seek", "lock"]
		if fx_budget != "off" or own_fx:
			if not own_fx and crowded and index < _pulses.size() - 6:
				canvas.draw_arc(point, 16.0 + age * 30.0, 0.0, TAU, 16, Color(color.r, color.g, color.b, 0.5 * alpha), 2.0, false)
				continue
			var fx_scale := float(pulse.get("scale", 1.0))
			if not own_fx and fx_budget == "light":
				fx_scale *= 0.72
			var scaled := absf(fx_scale - 1.0) > 0.001
			if scaled:
				canvas.draw_set_transform(point, 0.0, Vector2(fx_scale, fx_scale))
			var fx_point := Vector2.ZERO if scaled else point
			if kind == "path":
				_draw_fx_path_head(canvas, fx_point, color, age)
			elif kind == "lock":
				_draw_fx_lock(canvas, fx_point, age)
			else:
				_draw_fx_burst(canvas, fx_point, color, age)
			if scaled:
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var label := String(pulse.get("label", ""))
		if not judge_label_visible(label, judge_filter):
			continue
		# 试玩 HUD 只留档位；偏差明细在结算页和暂停页看。
		var detail := "" if playtest_mode else String(pulse.get("detail", ""))
		var label_y := float(pulse.get("label_y", 0.0))
		var pos := point + Vector2(30, -40 - age * 30 + label_y)
		var label_alpha := alpha
		var detail_alpha := 0.72 * alpha
		var outline_alpha := 0.55 * alpha
		# 街机判定字：26px 基准（900 高），随 HUD 缩放；命中 0.1s 内从 1.25 倍缩回原大。
		var hud_scale := clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
		var judge_base := 26.0 * clampf(canvas.size.y / 900.0, 0.8, 1.8) * hud_scale
		var font_size := int(round(judge_base * (1.0 + 0.25 * clampf(1.0 - age / 0.10, 0.0, 1.0))))
		var detail_size := 12
		var outline_size := 6
		if kind == "path":
			# 星星判定字：不跟命中特效一起淡；满亮 0.25s，0.55s 淡完；画到白爆环外面。
			label_alpha = clampf((0.55 - age) / 0.30, 0.0, 1.0)
			detail_alpha = 0.9 * label_alpha
			outline_alpha = 0.85 * label_alpha
			font_size = _path_label_font_size()
			detail_size = 14
			outline_size = maxi(4, int(font_size * 0.24))
			if judge_mode == "note":
				pos = _path_label_point(point, canvas.size, label, detail, font_size, detail_size)
				pos.y += label_y
		if judge_mode == "ring_in" or judge_mode == "ring_out":
			# 所有音符类型统一贴判定环：内侧/外侧由同一个偏移和缩放决定。
			pos = _ring_judge_label_point(point, canvas.size, label, detail, font_size, detail_size, judge_mode == "ring_out", label_y)
		elif judge_mode == "center":
			if index != center_label_index:
				continue
			pos = judge_anchor + Vector2(0, -age * 30.0)
			pos.x -= UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
		elif judge_mode == "off":
			continue
		canvas.draw_string_outline(UITheme.bold_font(), pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, Color(0, 0, 0, outline_alpha))
		canvas.draw_string(UITheme.bold_font(), pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color.r, color.g, color.b, label_alpha))
		# 早/晚提示：判定反馈不清时，把偏差方向直接写在判定字下面。
		if not detail.is_empty():
			# 这里原本用等宽字体，但它没有中文字形，每个不同的“早/晚 X ms”都会触发一次
			# 系统字体回退查找（单次约 18ms），判定密集时会周期性卡顿。改用含中文的正文字体。
			canvas.draw_string(UITheme.FONT_REGULAR, pos + Vector2(0, detail_size + 2), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, Color(1, 1, 1, detail_alpha))


## 星星判定字字号：约环半径 6.5%，随 HUD 缩放，小预览自动缩、大屏封顶。
func _path_label_font_size() -> int:
	var hud_scale := clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	return int(round(clampf(_avg_radius_cache * 0.065, 18.0, 40.0) * hud_scale))


func _path_label_point(point: Vector2, bounds: Vector2, label: String, detail: String, font_size: int, detail_size: int) -> Vector2:
	var width := UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if not detail.is_empty():
		width = maxf(width, UITheme.FONT_REGULAR.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x)
	var block := Vector2(width, float(font_size) + float(detail_size) + 6.0)
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	return path_label_pos(point, center, bounds, block, float(font_size) * 0.82)


## 环内/环外判定字：以音符落点为方向，贴判定环内侧或外侧。
## 偏移随字号和环半径缩放；同角度的多条判定沿半径方向错开。
func _ring_judge_label_point(point: Vector2, bounds: Vector2, label: String, detail: String, font_size: int, detail_size: int, outward: bool, stack: float) -> Vector2:
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	var offset := clampf(maxf(float(font_size) * 1.2, _avg_radius_cache * 0.08), 26.0, 90.0)
	var anchor := judge_label_anchor(point, center, _avg_radius_cache, offset, outward, stack)
	var width := UITheme.bold_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if not detail.is_empty():
		width = maxf(width, UITheme.FONT_REGULAR.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x)
	var block_h := float(font_size) + float(detail_size) + 6.0
	var pos := anchor - Vector2(width * 0.5, float(font_size) * 0.36)
	var margin := 8.0
	pos.x = clampf(pos.x, margin, maxf(margin, bounds.x - width - margin))
	pos.y = clampf(pos.y, float(font_size) * 0.8 + margin, maxf(float(font_size) * 0.8 + margin, bounds.y - block_h - margin))
	return pos


## 判定字锚点：方向取音符落点，半径取落点到环心；落点在圆心时退回环半径。
static func judge_label_anchor(point: Vector2, center: Vector2, fallback_radius: float, offset: float, outward: bool, stack: float = 0.0) -> Vector2:
	var dir := point - center
	var dist := dir.length()
	if dist < 4.0:
		dir = Vector2.UP
		dist = maxf(1.0, fallback_radius)
	else:
		dir /= dist
	var radius := maxf(dist, maxf(1.0, fallback_radius) * 0.55)
	var signed := (offset + stack) if outward else -(offset + stack)
	return center + dir * (radius + signed)


## 星头爆环半径 116px：优先推到外侧，放不下就换内侧，最后夹进画面避免裁切。
static func path_label_pos(point: Vector2, center: Vector2, bounds: Vector2, block: Vector2, ascent: float, dist: float = 132.0) -> Vector2:
	var dir := point - center
	dir = dir.normalized() if dir.length() > 4.0 else Vector2.UP
	var margin := 10.0
	var outward := point + dir * dist
	if _label_fits(outward, bounds, block, ascent, margin):
		return outward
	var inward := point - dir * dist
	if _label_fits(inward, bounds, block, ascent, margin):
		return inward
	return Vector2(
		clampf(outward.x, margin, maxf(margin, bounds.x - block.x - margin)),
		clampf(outward.y, ascent + margin, maxf(ascent + margin, bounds.y - block.y - margin)))


static func _label_fits(pos: Vector2, bounds: Vector2, block: Vector2, ascent: float, margin: float) -> bool:
	return pos.x >= margin and pos.x + block.x <= bounds.x - margin \
		and pos.y - ascent >= margin and pos.y + block.y <= bounds.y - margin


func _draw_fx_path_head(canvas: Control, point: Vector2, color: Color, age: float) -> void:
	# osu!std 式发散：白闪 + 双层扩散圆环 + 12 道放射线，星头命中一眼可见。
	var t := clampf(age / 0.46, 0.0, 1.0)
	var fade := 1.0 - t
	var flash := clampf(1.0 - age / 0.10, 0.0, 1.0)
	if flash > 0.0:
		canvas.draw_circle(point, 14.0 + 26.0 * flash, Color(1, 1, 1, 0.55 * flash))
		canvas.draw_circle(point, 8.0 + 8.0 * flash, Color(1, 1, 1, 0.95 * flash))
	var main_radius := 12.0 + 104.0 * (1.0 - pow(1.0 - t, 2.4))
	canvas.draw_arc(point, main_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.85 * fade), 2.0 + 5.0 * fade, false)
	var delayed := clampf((age - 0.05) / 0.46, 0.0, 1.0)
	if delayed > 0.0:
		var fade2 := 1.0 - delayed
		var second_radius := 8.0 + 74.0 * (1.0 - pow(1.0 - delayed, 2.0))
		canvas.draw_arc(point, second_radius, 0.0, TAU, 36, Color(color.r, color.g, color.b, 0.65 * fade2), 1.6 + 3.0 * fade2, false)
	for k in 12:
		var angle := float(k) * TAU / 12.0 + age * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var inner := point + direction * (10.0 + 18.0 * t)
		var outer := point + direction * (24.0 + 78.0 * t)
		canvas.draw_line(inner, outer, Color(1, 1, 1, 0.80 * fade), 1.6 + 1.6 * fade, false)
	canvas.draw_circle(point, 14.0 * fade, Color(color.r, color.g, color.b, 0.35 * fade))
	canvas.draw_circle(point, 7.0 * fade, Color(1, 1, 1, 0.95 * fade))


func _draw_fx_lock(canvas: Control, point: Vector2, age: float) -> void:
	# 在场锁定：一圈快速收束的金环，不写判定字；告诉玩家“已经算上了”。
	var t := clampf(age / 0.18, 0.0, 1.0)
	var fade := 1.0 - t
	canvas.draw_arc(point, lerpf(30.0, 12.0, t), 0.0, TAU, 32,
		Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.9 * fade), 2.0 + 2.0 * fade, false)
	canvas.draw_circle(point, 3.0 * fade, Color(1, 1, 1, 0.85 * fade))


func _draw_fx_burst(canvas: Control, point: Vector2, color: Color, age: float) -> void:
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
		canvas.draw_polyline(star_outline, Color(1, 1, 1, 0.78 * flash), 2.0, false)
	# 实心冲击盘 + 双层环。
	canvas.draw_circle(point, 30.0 + 42.0 * t, Color(color.r, color.g, color.b, 0.12 * fade))
	var ring_radius := 14.0 + 82.0 * (1.0 - pow(1.0 - t, 3.0))
	canvas.draw_arc(point, ring_radius, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.78 * fade), 3.0 + 6.0 * fade, false)
	canvas.draw_arc(point, ring_radius * 1.26, 0.0, TAU, 20, Color(color.r, color.g, color.b, 0.24 * fade), 1.2 + 2.0 * fade, false)
	canvas.draw_circle(point, 8.0 * fade, Color(color.r, color.g, color.b, fade))


## draw_string 每帧都会重新排版（CJK 尤其贵）：缓存 TextLine，只在文字变化时重建。
var _hud_text: Dictionary = {}
## 连击动画：上一次的连击数 + 放大/断连的时间戳。
var _hud_combo_prev: int = 0
var _hud_combo_pop_at: int = -100000
var _hud_combo_break_at: int = -100000
var _hud_combo_broken: int = 0


func _draw_cached_text(canvas: Control, key: String, font: Font, pos: Vector2, text: String, font_size: int, color: Color) -> void:
	var entry: Dictionary = _hud_text.get(key, {})
	if entry.is_empty() or String(entry["text"]) != text or int(entry["size"]) != font_size:
		var line := TextLine.new()
		line.add_string(text, font, font_size)
		entry = {"text": text, "size": font_size, "line": line}
		_hud_text[key] = entry
	(entry["line"] as TextLine).draw(canvas.get_canvas_item(), pos, color)


func _draw_hud(canvas: Control, chart: Chart, t: float) -> void:
	if playtest_mode:
		_draw_play_hud(canvas, chart, t)
		return
	_draw_editor_hud(canvas, chart, t)


## 编辑器预览的旧仪表：进度 / 评级 / 准度三段弧 + 误差条。
func _draw_editor_hud(canvas: Control, chart: Chart, t: float) -> void:
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
	canvas.draw_arc(Vector2(cx, cy), radius, start, end, 48, Color(0, 0, 0, 0.55), 30.0, false)
	for i in 3:
		var seg_start := start + third * float(i)
		var seg_end := seg_start + third
		canvas.draw_arc(Vector2(cx, cy), radius, seg_start, seg_end, 24, Color(1, 1, 1, 0.06), 24.0, false)
	var progress := clampf(t / maxf(1.0, chart.duration_beats()), 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, start, start + third * progress, 24, UITheme.INK, 24.0, false)
	if hud_rating != "—" and not hud_rating.is_empty():
		canvas.draw_arc(Vector2(cx, cy), radius, start + third, start + third * 2.0, 24, UITheme.GOLD, 24.0, false)
	var accuracy_ratio := 0.5 if hud_accuracy < 0.0 else clampf(hud_accuracy / 100.0, 0.0, 1.0)
	canvas.draw_arc(Vector2(cx, cy), radius, end - third, end - third + third * accuracy_ratio, 24, UITheme.CYAN, 24.0, false)
	var font := UITheme.bold_font()
	var mono := UITheme.mono_font()
	_draw_cached_text(canvas, "hud_progress", font, Vector2(cx - radius * 0.68, cy - radius * 0.52), "进度", 11, UITheme.INK)
	_draw_cached_text(canvas, "hud_rating", font, Vector2(cx - 18, cy - radius * 0.52), hud_rating, 20, UITheme.INK)
	_draw_cached_text(canvas, "hud_accuracy_label", font, Vector2(cx + radius * 0.48, cy - radius * 0.52), "准度", 11, UITheme.CYAN)
	_draw_cached_text(canvas, "hud_progress_value", mono, Vector2(cx - radius * 0.68, cy - radius * 0.32), "%d%%" % roundi(progress * 100.0), 12, UITheme.INK)
	_draw_cached_text(canvas, "hud_accuracy_value", mono, Vector2(cx + radius * 0.48, cy - radius * 0.32), "—" if hud_accuracy < 0.0 else "%.2f%%" % hud_accuracy, 12, UITheme.INK)
	var baseline_y := cy + radius * 0.44
	var tick_left := cx - radius * 0.80
	var tick_right := cx + radius * 0.80
	canvas.draw_line(Vector2(tick_left, baseline_y), Vector2(tick_right, baseline_y), Color(1, 1, 1, 0.16), 1.0, false)
	for i in 20:
		var x := lerpf(tick_left, tick_right, float(i) / 19.0)
		var error := 0.0
		if i < hud_errors.size():
			error = hud_errors[hud_errors.size() - 1 - i]
		var length := 4.0 + minf(12.0, absf(error) / 32.0 * 12.0) if i < hud_errors.size() else 3.0
		var color := Color(1, 1, 1, 0.14)
		if i < hud_errors.size():
			color = UITheme.CYAN if error < 0.0 else UITheme.CORAL
		canvas.draw_line(Vector2(x, baseline_y - 2.0), Vector2(x, baseline_y - 2.0 - length), color, 2.0, false)
	_draw_cached_text(canvas, "hud_preview", mono, Vector2(cx - 34, baseline_y + 20), "预览 / 非正式", 10, UITheme.MUTED)


## Combo 单独走一层：在音符之前绘制，下落 Tap/Hold/Path 会盖住它。
## 左右两列仍在 HUD 层，不受影响。
func _draw_play_combo_layer(canvas: Control) -> void:
	var bounds := size
	if bounds.x < 320.0 or bounds.y < 240.0:
		return
	var op := clampf(float(hud_options.get("opacity", 100)) / 100.0, 0.3, 1.0)
	var hs := clampf(bounds.y / 900.0, 0.8, 1.8)
	var s := hs * clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = bounds * 0.5
	var combo_mode := String(hud_options.get("combo_mode", "center"))
	if combo_mode == "off":
		return
	if combo_mode == "center":
		_draw_combo(canvas, UITheme.bold_font(), center, s, 78.0 * s, 2, op)
		return
	# 右侧：和 _draw_hud_score_column 同一套列起点与纵向排布。
	var margin := 14.0 * s
	var ring_r := _hud_ring_radius(get_time_beat()) * 1.2
	var gap := 20.0 * s
	var right_x := center.x + ring_r + gap
	var acc_size := int(round(38.0 * s))
	var label_row := 24.0 * s
	var height := label_row + float(acc_size) + 8.0 * s + 50.0 * s
	var top_y := center.y - height * 0.5
	var combo_y := top_y + label_row + float(acc_size) + 8.0 * s + 34.0 * s
	_draw_combo(canvas, UITheme.bold_font(), Vector2(right_x, combo_y), s, 34.0 * s, 0, op)


## 试玩 HUD v3：信息贴着环的左右两侧，垂直居中。
## 左：TRACK / 曲名 / 难度 / 可选进度与用时；右：ACCURACY / 大字准度 / 评级章 / 连击。
## 判定字仍在音符处；五档计数只在暂停页和结算页显示。
func _draw_play_hud(canvas: Control, chart: Chart, t: float) -> void:
	var bounds := size
	if bounds.x < 320.0 or bounds.y < 240.0:
		return
	var op := clampf(float(hud_options.get("opacity", 100)) / 100.0, 0.3, 1.0)
	var hs := clampf(bounds.y / 900.0, 0.8, 1.8)
	var s := hs * clampf(float(hud_options.get("scale", 100)) / 100.0, 0.5, 2.0)
	var margin := 14.0 * s
	var bold := UITheme.bold_font()
	var mono := UITheme.mono_font()
	var layout := _hud_layout()
	var center: Vector2 = layout["center"]
	var accuracy := hud_accuracy
	var progress := clampf(t / maxf(1.0, chart.duration_beats()), 0.0, 1.0)
	_draw_ring_gauge(canvas, progress, accuracy, s, op)
	# 舞台外圈刻度大约在判定环的 1.19×；HUD 再退到 1.2×，避免压到装饰环。
	var ring_r: float = float(layout["ring"]) * 1.2
	var gap := 20.0 * s
	var side := minf(center.x, bounds.x - center.x) - ring_r - margin - gap
	var col_w := clampf(side, 90.0 * s, 320.0 * s)
	var left_x := center.x - ring_r - gap - col_w
	var right_x := center.x + ring_r + gap
	_draw_hud_track_column(canvas, left_x + col_w, col_w, center.y, s, op, progress, bold, mono)
	_draw_hud_score_column(canvas, right_x, col_w, center.y, s, op, accuracy, bold, mono)
	# AUTO 必须一直看得见：连击位置改成「角落」时，之前完全没有 AUTO 标记，
	# 玩家手动输入被自动演示吞掉还以为试玩坏了。
	if hud_auto:
		_draw_hud_text(canvas, "p_auto", mono, Vector2(center.x, margin + 12.0 * s), "AUTO",
			_hud_small(s), _hud_tint(UITheme.AMBER, op), 2)
	if bool(hud_options.get("show_watermark", false)):
		_draw_hud_text(canvas, "p_watermark", mono, Vector2(margin, bounds.y - margin), "试玩预览 / 非正式", _hud_small(s), _hud_tint(UITheme.MUTED, op))


## 左列：垂直居中，宽度随窗口收窄；长曲名截断成省略号。
func _draw_hud_track_column(canvas: Control, right_x: float, col_w: float, center_y: float, s: float, op: float, progress: float, bold: Font, mono: Font) -> void:
	var show_title := bool(hud_options.get("show_title", true))
	var show_diff := bool(hud_options.get("show_difficulty", true)) and not hud_difficulty.is_empty()
	var show_pct := bool(hud_options.get("show_percent", false))
	var show_time := bool(hud_options.get("show_time", false))
	var height := 0.0
	if show_title:
		height += 15.0 * s
		if not hud_title.is_empty():
			height += 25.0 * s
	if show_diff:
		height += 27.0 * s
	if show_pct:
		height += 15.0 * s
	if show_time:
		height += 15.0 * s
	var y := center_y - height * 0.5
	if show_title:
		_draw_hud_text(canvas, "p_track", mono, Vector2(right_x, y), "TRACK", _hud_small(s), _hud_tint(UITheme.MUTED, 0.85 * op), 1)
		y += 15.0 * s
		if not hud_title.is_empty():
			var title := _hud_fit_text(hud_title, bold, int(round(19.0 * s)), col_w)
			_draw_hud_text(canvas, "p_title", bold, Vector2(right_x, y), title, int(round(19.0 * s)), _hud_tint(UITheme.INK, op), 1)
			y += 25.0 * s
	if show_diff:
		_draw_chip(canvas, Vector2(right_x, y), hud_difficulty, s, op, UITheme.CYAN, 1)
		y += 27.0 * s
	if show_pct:
		_draw_hud_text(canvas, "p_percent", mono, Vector2(right_x, y), "进度 %d%%" % roundi(progress * 100.0), _hud_small(s), _hud_tint(UITheme.MUTED, op), 1)
		y += 15.0 * s
	if show_time:
		_draw_hud_text(canvas, "p_time", mono, Vector2(right_x, y), "%s / %s" % [_hud_time(hud_ms), _hud_time(hud_total_ms)], _hud_small(s), _hud_tint(UITheme.MUTED, op), 1)


## 右列：准度是主体；评级章与 ACCURACY 同排右对齐，连击在下方。
func _draw_hud_score_column(canvas: Control, x: float, col_w: float, center_y: float, s: float, op: float, accuracy: float, bold: Font, mono: Font) -> void:
	var acc_text := "—" if accuracy < 0.0 else "%.2f%%" % accuracy
	var acc_size := int(round(38.0 * s))
	var combo_mode := String(hud_options.get("combo_mode", "center"))
	var reserve_combo := combo_mode == "corner"
	# 标签行要容得下 22px 的评级章，否则章底会压到准度数字顶部。
	var label_row := 24.0 * s
	var height := label_row + acc_size
	if reserve_combo:
		height += 8.0 * s + 50.0 * s
	var y := center_y - height * 0.5
	var small := _hud_small(s)
	var label_w := mono.get_string_size("ACCURACY", HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	var chip_w := mono.get_string_size(hud_rating, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(11, int(round(13.0 * s)))).x + 14.0 * s
	_draw_hud_text(canvas, "p_acc_label", mono, Vector2(x, y), "ACCURACY", small, _hud_tint(UITheme.MUTED, 0.85 * op))
	# 评级章贴着 ACCURACY 标签，不甩到列的最右边。
	_draw_rank_chip(canvas, x + label_w + 10.0 * s + chip_w, y, hud_rating, s, op)
	y += label_row
	_draw_hud_text(canvas, "p_acc", bold, Vector2(x, y), acc_text, acc_size, _hud_tint(UITheme.INK, op))
	y += acc_size + 8.0 * s
	# Combo 已在音符层下面单独绘制；这里只保留占位高度，避免准度/评级压到连击。


## 环的横向像素半径（取进度带所在的那一圈）；侧栏据此贴住环的切线。
## HUD 左右列要贴着环，但相机带鼠标倾斜/视差，同一帧的投影会有几个 % 的漂移，
## 直接用当帧投影会让「曲名省略成几个字」跟着鼠标来回跳。
## 按「设计半径 + 视口尺寸」缓存一次布局：尺寸不变就不重算。
var _hud_layout_cache: Dictionary = {}


func _hud_layout() -> Dictionary:
	var key := "%d|%dx%d|%s" % [int(_max_design_radius), roundi(size.x), roundi(size.y), _last_view_key]
	if _hud_layout_cache.has(key):
		return _hud_layout_cache[key]
	var center := project_design(Vector2.ZERO)
	if not _valid_point(center):
		center = size * 0.5
	var ring := _hud_ring_radius(0.0)
	if ring <= 1.0:
		ring = minf(size.x, size.y) * 0.44
	var layout := {"center": center, "ring": ring}
	# 只留一份：换谱面 / 改窗口尺寸会生成新 key，旧的直接丢掉。
	_hud_layout_cache = {key: layout}
	return layout


func _hud_ring_radius(t: float) -> float:
	_ensure_design_radius(get_chart())
	if _max_design_radius > 0.0:
		var affine := _screen_affine()
		return _max_design_radius * (affine[1] as Vector2).length()
	var center := project_design(Vector2.ZERO)
	var radius := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, t)
		if _valid_point(edge):
			radius = maxf(radius, center.distance_to(edge))
	return radius


## 曲名太长时截成“前缀…”；按文字/字号/宽度缓存，避免每帧重排。
var _hud_fit_cache: Dictionary = {}

func _hud_fit_text(text: String, font: Font, font_size: int, max_width: float) -> String:
	var key := "%s|%d|%d" % [text, font_size, int(max_width)]
	if _hud_fit_cache.has(key):
		return String(_hud_fit_cache[key])
	var result := text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		var cut := text
		result = "…"
		while cut.length() > 1:
			cut = cut.substr(0, cut.length() - 1)
			if font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
				result = cut + "…"
				break
	_hud_fit_cache[key] = result
	return result


func _hud_small(s: float) -> int:
	return maxi(9, int(round(10.0 * s)))


## 环量表：底轨 + 8px 进度带 + 亮点；准度 2px 在外侧。
func _draw_ring_gauge(canvas: Control, progress: float, accuracy: float, s: float, op: float) -> void:
	if _max_design_radius <= 0.0 or String(hud_options.get("progress_style", "ring")) != "ring":
		return
	var affine := _screen_affine()
	var band_r := _max_design_radius * 1.012
	_hud_arc(canvas, affine, 0.0, 360.0, band_r, _hud_tint(Color(1, 1, 1, 0.10), op), 8.0 * s)
	_hud_arc(canvas, affine, 90.0, 90.0 - 360.0 * progress, band_r, _hud_tint(Color(1, 1, 1, 0.78), op), 8.0 * s)
	var head := 90.0 - 360.0 * progress
	var hp := _affine_point(Vector2(cos(deg_to_rad(head)), sin(deg_to_rad(head))) * band_r, affine)
	canvas.draw_circle(hp, 9.0 * s, _hud_tint(Color(1, 1, 1, 0.16), op))
	canvas.draw_circle(hp, 4.0 * s, _hud_tint(Color(1, 1, 1, 0.95), op))
	if accuracy >= 0.0:
		var acc_ratio := clampf(accuracy / 100.0, 0.0, 1.0)
		_hud_arc(canvas, affine, 90.0, 90.0 + 360.0 * acc_ratio, _max_design_radius * 1.045,
			_hud_tint(Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.55), op), 2.0 * s)


## 难度胶囊：细边框 + 半透明底，比裸文字更像街机标签。
func _draw_chip(canvas: Control, pos: Vector2, text: String, s: float, op: float, color: Color, align: int = 0) -> void:
	var font := UITheme.mono_font()
	var size := maxi(10, int(round(11.0 * s)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0 * s
	var h := 19.0 * s
	var at := pos
	if align == 1:
		at.x -= w
	canvas.draw_rect(Rect2(at.x, at.y, w, h), _hud_tint(color, 0.14 * op))
	canvas.draw_rect(Rect2(at.x, at.y, w, h), _hud_tint(color, 0.55 * op), false, 1.0)
	_draw_hud_text(canvas, "p_chip", font, at + Vector2(7.0 * s, 2.0 * s), text, size, _hud_tint(UITheme.INK, op))


func _draw_rank_chip(canvas: Control, right_x: float, top_y: float, rank: String, s: float, op: float) -> void:
	var color := _rank_color(rank)
	var font := UITheme.mono_font()
	var size := maxi(11, int(round(13.0 * s)))
	var w := font.get_string_size(rank, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0 * s
	var h := 22.0 * s
	canvas.draw_rect(Rect2(right_x - w, top_y, w, h), _hud_tint(color, 0.16 * op))
	canvas.draw_rect(Rect2(right_x - w, top_y, w, h), _hud_tint(color, 0.75 * op), false, 1.0)
	_draw_hud_text(canvas, "p_rank", font, Vector2(right_x - w * 0.5, top_y + 4.0 * s), rank, size, _hud_tint(color, op), 2)


## 连击：≥2 才出现；命中轻微放大，断连变红、下沉、淡出。
func _draw_combo(canvas: Control, font: Font, anchor: Vector2, s: float, base_px: float, align: int, op: float) -> void:
	var now := int(_anim_ms())
	if hud_combo > _hud_combo_prev:
		_hud_combo_pop_at = now
	elif hud_combo < _hud_combo_prev and _hud_combo_prev >= 2:
		_hud_combo_break_at = now
		_hud_combo_broken = _hud_combo_prev
	_hud_combo_prev = hud_combo
	var break_age := float(now - _hud_combo_break_at) / 1000.0
	var flashing := break_age < 0.45
	if hud_combo < 2 and not flashing:
		return
	var pop_age := float(now - _hud_combo_pop_at) / 1000.0
	var pop := 1.0 + 0.08 * maxf(0.0, 1.0 - pop_age / 0.12)
	var color := _hud_tint(UITheme.INK, op)
	var sink := 0.0
	if flashing:
		color = Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, (1.0 - break_age / 0.45) * op)
		pop = 1.04
		sink = 8.0 * s * clampf(break_age / 0.45, 0.0, 1.0)
	var shown := _hud_combo_broken if flashing else hud_combo
	var number_size := int(round(base_px * pop))
	var number_top := anchor.y - number_size * 0.52 + sink
	var label_size := maxi(10, int(round(11.0 * s)))
	var key := "p_combo" if align == 2 else "p_combo_corner"
	_draw_hud_text(canvas, key + "_label", font, Vector2(anchor.x, number_top - label_size - 5.0 * s), "COMBO", label_size, _hud_tint(UITheme.MUTED, 0.9 * op), align)
	_draw_hud_text(canvas, key, font, Vector2(anchor.x, number_top), str(shown), number_size, color, align)


func _hud_tint(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)


func _hud_time(ms: float) -> String:
	var total := int(maxf(0.0, ms) / 1000.0)
	return "%d:%02d" % [total / 60, total % 60]


## HUD 文字：缓存 TextLine（CJK 每帧排版很贵），align 0=左 1=右 2=中。
func _draw_hud_text(canvas: Control, key: String, font: Font, pos: Vector2, text: String, font_size: int, color: Color, align: int = 0) -> void:
	var entry: Dictionary = _hud_text.get(key, {})
	if entry.is_empty() or String(entry["text"]) != text or int(entry["size"]) != font_size:
		var line := TextLine.new()
		line.add_string(text, font, font_size)
		entry = {"text": text, "size": font_size, "line": line, "width": line.get_size().x}
		_hud_text[key] = entry
	var at := pos
	var width := float(entry["width"])
	if align == 1:
		at.x -= width
	elif align == 2:
		at.x -= width * 0.5
	(entry["line"] as TextLine).draw(canvas.get_canvas_item(), at, color)


## 环外仪表弧：按屏幕弧长取点，画满 360° 也不会堆出几千个点。
func _hud_arc(canvas: Control, affine: Array, from_deg: float, to_deg: float, radius: float, color: Color, width: float) -> void:
	var span := deg_to_rad(absf(to_deg - from_deg))
	if span < 0.01:
		return
	var scale := (affine[1] as Vector2).length()
	var steps := clampi(int(span * radius * scale / 3.0), 6, 240)
	var points := PackedVector2Array()
	for i in steps + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
		points.append(_affine_point(Vector2(cos(a), sin(a)) * radius, affine))
	canvas.draw_polyline(points, color, width, true)


func _rank_color(rank: String) -> Color:
	match rank:
		"AAA":
			return UITheme.GOLD
		"AA":
			return UITheme.CYAN
		"A":
			return UITheme.MINT
		"B":
			return UITheme.AMBER
		"C":
			return UITheme.CORAL
	return UITheme.MUTED


func _tier_color(tier: String) -> Color:
	match tier:
		"PERFECT":
			return UITheme.GOLD
		"GREAT":
			return UITheme.CYAN
		"GOOD":
			return UITheme.MINT
		"BAD":
			return UITheme.AMBER
	return UITheme.CORAL


func _draw_debug(canvas: Control, chart: Chart, t: float) -> void:
	var rect := Rect2(10, 10, 238, 82)
	canvas.draw_rect(rect, Color(0, 0, 0, 0.58))
	canvas.draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.35), false, 1.0)
	var mono := UITheme.mono_font()
	canvas.draw_string(mono, Vector2(18, 28), "u %.2f°  |  beat %.2f" % [cursor_u * 360.0, t], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.INK)
	canvas.draw_string(mono, Vector2(18, 44), "time %.0f ms  |  %s" % [chart.timing.beat_to_chart_ms(t), "有效" if cursor_valid else "无位置"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 60), "shape %s  |  zoom %.2f" % [chart.default_shape_id, float(current_view().get("zoom", 1.0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	canvas.draw_string(mono, Vector2(18, 76), "branch 0  |  fall %.0f ms ×%.2f  |  %d fps" % [_pre_read_ms(chart, t), flow_scale, Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.MUTED)
	for i in 12:
		var u := float(i) / 12.0
		var p := project_u(u, t)
		if _valid_point(p):
			canvas.draw_string(mono, p + Vector2(4, -4), "%d°" % (i * 30), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.42))


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


## 方向箭头按「固定弧长间隔」排布：所有 Path 共用同一个间距；
## 折得很厉害的轨迹（锯齿 / 来回折返）弧长很长但占的面积很小，
## 再按屏幕距离去一次重，避免同一片区域堆一堆箭头。
static func chevron_fractions(points: PackedVector2Array, spacing: float, min_gap: float) -> Array[float]:
	var fractions: Array[float] = []
	for sample in _chevron_samples(points, spacing, min_gap):
		fractions.append(sample.fraction)
	return fractions


static func _chevron_samples(points: PackedVector2Array, spacing: float, min_gap: float) -> Array[PathChevron]:
	var samples: Array[PathChevron] = []
	if points.size() < 2 or spacing <= 0.1:
		return samples
	var lengths := PackedFloat64Array()
	var total := 0.0
	for i in points.size() - 1:
		var span := points[i].distance_to(points[i + 1])
		lengths.append(span)
		total += span
	if total < spacing * 0.9:
		return samples
	# 性能上限：箭头上限是 48 只；超出时整体把间距拉开，
	# 而不是只铺满前面一段（否则长轨迹会在中途突然没有箭头）。
	var wanted := maxi(1, int(total / spacing))
	var count := mini(wanted, 48)
	var step := total / float(count)
	var placed := PackedVector2Array()
	var edge: int = 0
	var cursor: float = 0.0
	for k in count:
		var target := (float(k) + 0.5) * step
		# Targets advance in arc-length order, so each edge is visited once.
		while edge < lengths.size() - 1 and cursor + lengths[edge] < target:
			cursor += lengths[edge]
			edge += 1
		var q: float = 0.0 if lengths[edge] <= 0.0001 else (target - cursor) / lengths[edge]
		var spot: Vector2 = points[edge].lerp(points[edge + 1], q)
		var crowded := false
		for previous in placed:
			if previous.distance_to(spot) < min_gap:
				crowded = true
				break
		if crowded:
			continue
		placed.append(spot)
		var sample := PathChevron.new()
		sample.fraction = clampf(target / total, 0.0, 1.0)
		# Ignore tiny edges when choosing a direction, including duplicate points.
		var tangent_edge: int = edge
		var tangent_start: float = cursor
		while tangent_edge < lengths.size() and lengths[tangent_edge] <= 0.01:
			tangent_start += lengths[tangent_edge]
			tangent_edge += 1
		if tangent_edge < lengths.size():
			var weight: float = (target - tangent_start) / lengths[tangent_edge]
			sample.point = points[tangent_edge].lerp(points[tangent_edge + 1], weight)
			sample.direction = points[tangent_edge + 1] - points[tangent_edge]
		else:
			sample.point = points[-1]
			sample.direction = points[-1] - points[-2]
		samples.append(sample)
	return samples


## 履带纹：沿轨迹按固定弧长盖一串暗色 V 纹，读方向、也把实心带区分成“一节一节”。
func _draw_tread_marks(canvas: Control, piece: PackedVector2Array, width: float, color: Color) -> void:
	if piece.size() < 2 or width < 3.0:
		return
	var spacing := maxf(10.0, width * 0.75)
	var size := width * 0.42
	for sample in _chevron_samples(piece, spacing, spacing * 0.8):
		_draw_chevron(canvas, sample.point, sample.direction, color, size)


func _draw_chevron(canvas: Control, point: Vector2, direction: Vector2, color: Color, size: float) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var tip := point + dir * size * 0.12
	var left := point - dir * size + normal * size * 0.80
	var right := point - dir * size - normal * size * 0.80
	# 一条粗 V 形 polyline：比三层描边少 2/3 draw call，也不产生多边形三角化失败。
	canvas.draw_polyline(PackedVector2Array([left, tip, right]), color, maxf(2.0, size * 0.52), false)


func _draw_star(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * float(i) / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(point + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	canvas.draw_polyline(points, color, 2.0, false)
	canvas.draw_circle(point, 2.0, color)


func _draw_ring(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	canvas.draw_arc(point, radius, 0.0, TAU, 28, color, 2.0, false)
	canvas.draw_circle(point, 1.8, color)


func _draw_hexagon(canvas: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 6:
		var angle := -PI * 0.5 + TAU * float(i) / 6.0
		points.append(point + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_circle(point, radius + 3.0, Color(0, 0, 0, 0.62))
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, Color(1, 1, 1, 0.96), 2.6, false)
	canvas.draw_circle(point, radius * 0.34, UITheme.BG)
	canvas.draw_circle(point, radius * 0.20, Color(1, 1, 1, 0.9))


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
	canvas.draw_polyline(points, Color(0, 0, 0, 0.66), 5.0, false)
	canvas.draw_polyline(points, Color(1, 1, 1, 0.94), 3.0, false)
	canvas.draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], points[3]]), Color(color, 0.32))
	canvas.draw_polyline(points, color, 1.7, false)
	canvas.draw_circle(point, maxf(2.0, radius * 0.26), Color(0, 0, 0, 0.68))
	canvas.draw_circle(point, maxf(1.2, radius * 0.14), Color(1, 1, 1, 0.92))


## 金键：环上一段白描边金键（圆头 + 金色核心）。所有 Bell 都在判定环上。
## 长度走 Note.bell_width()，和 Tap 到环时的 31° 同级；不再是一条长 45° 的金板。
func _draw_bell(canvas: Control, chart: Chart, note: Note, t: float) -> void:
	var q := _note_radius_scale(note, _note_progress(chart, note, t))
	var alpha := chart.group_alpha(note.group_id) / 255.0
	var half := BELL_BAND_HALF * _note_scale() * float(_skin()["scale"])
	var group_mul := chart.group_alpha(note.group_id) / 255.0
	var breathe := 0.5 + 0.5 * sin(_anim_ms() / 1000.0 * 2.4)
	# 和 Tap / Hold 同一套语言：白色外壳 + 彩色核心，两端圆头。
	_bell_capsule(canvas, note, t, q, -half - 5.0, half + 5.0,
		Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, (0.07 + 0.05 * breathe) * alpha))
	_bell_capsule(canvas, note, t, q, -half - 2.0, half + 2.0, Color(0, 0, 0, 0.55 * alpha))
	_bell_capsule(canvas, note, t, q, -half, half, Color(1, 1, 1, 0.94 * alpha))
	_bell_capsule(canvas, note, t, q, -half * 0.62, half * 0.62, Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, alpha))
	# 扫键串的铃判定放宽到 75px，就把这个范围画出来：看到多大 = 能打多大。
	if bool(path_judgement_states.get(note.id, {}).get("sweep_chain", false)):
		var halo := _bell_ring_point(chart, note.center_u * 360.0, t, q)
		if halo.is_finite():
			canvas.draw_arc(halo, BELL_CHAIN_TOLERANCE * _note_scale(), 0.0, TAU, 64,
				Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.2 * alpha), 1.6, true)


## 弧带 + 两端圆头：画成一根沿环的胶囊。
func _bell_capsule(canvas: Control, note: Note, beat: float, q: float, lo: float, hi: float, color: Color) -> void:
	var chart := get_chart()
	if chart == null:
		return
	var poly := _bell_shape(note, beat, q, lo, hi)
	if poly.size() >= 3:
		canvas.draw_colored_polygon(poly, color)
	var ring := maxf(_ring_radius_px(beat), 1.0)
	var mid := maxf(0.0, (1.0 + (lo + hi) * 0.5 / ring) * q)
	var width := note.bell_width()
	var cap := absf(hi - lo) * 0.5
	for a in [note.center_u * 360.0 - width * 0.5, note.center_u * 360.0 + width * 0.5]:
		var p := _bell_ring_point(chart, a, beat, mid)
		if p.is_finite():
			canvas.draw_circle(p, cap, color)


## 金键的形状：两条同心弧。lo/hi 是相对判定环的像素偏移，圆头由 _bell_capsule 补。
func _bell_shape(note: Note, beat: float, q: float, lo: float, hi: float) -> PackedVector2Array:
	var chart := get_chart()
	var out := PackedVector2Array()
	if chart == null:
		return out
	var ring := maxf(_ring_radius_px(beat), 1.0)
	var width := note.bell_width()
	var steps := clampi(int(width / 4.0), 10, 96)
	var a0 := note.center_u * 360.0 - width * 0.5
	var a1 := note.center_u * 360.0 + width * 0.5
	var hi_scale := maxf(0.0, (1.0 + hi / ring) * q)
	var lo_scale := maxf(0.0, (1.0 + lo / ring) * q)
	for i in steps + 1:
		var p := _bell_ring_point(chart, a0 + width * float(i) / float(steps), beat, hi_scale)
		if p.is_finite():
			out.append(p)
	for i in steps + 1:
		var p := _bell_ring_point(chart, a1 - width * float(i) / float(steps), beat, lo_scale)
		if p.is_finite():
			out.append(p)
	return out


func _bell_ring_point(chart: Chart, angle_deg: float, beat: float, scale: float) -> Vector2:
	var data := _boundary_point(chart, fposmod(angle_deg, 360.0) / 360.0, beat)
	if bool(data.get("gap", false)):
		return Vector2(INF, INF)
	return project_design((data.point as Vector2) * clampf(scale, 0.0, 4.0))


func _ring_radius_px(beat: float) -> float:
	var center := project_design(Vector2.ZERO)
	var ring := 0.0
	for u in [0.0, 0.25, 0.5, 0.75]:
		var edge := project_u(u, beat)
		if _valid_point(edge):
			ring = maxf(ring, center.distance_to(edge))
	return ring


## 金色弧带的屏幕折线（radius_scale 用于从圆心长出来的接近动画）。
func bell_band_points(note: Note, beat: float, radius_scale: float = 1.0) -> Array[Vector2]:
	var chart := get_chart()
	var points: Array[Vector2] = []
	if chart == null:
		return points
	var width := note.bell_width()
	var steps := clampi(int(width / 4.0), 10, 96)
	var radius := clampf(radius_scale, 0.0, 1.0)
	for i in steps + 1:
		var angle := note.center_u * 360.0 - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(angle, 360.0) / 360.0, beat)
		if bool(data.get("gap", false)):
			continue
		var p := project_design((data.point as Vector2) * radius)
		if _valid_point(p):
			points.append(p)
	return points


## 在场判定：贴住画出来的位置算（Bell 到达前从圆心飞向环）；提前站在判定环上也算。
func bell_contains(note: Note, beat: float, point: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	var live := bell_live_band(note, beat)
	if live.size() >= 2 and JudgeMath.trace_distance(point, live) <= tolerance:
		return true
	var ring := bell_band_points(note, beat)
	return ring.size() >= 2 and JudgeMath.trace_distance(point, ring) <= tolerance


## 扫过判定：这一帧光标走过的线段碰到金键带（或判定环）就算在场。
## 快速扫过时采样点可能整帧跨过金键，只看点会漏判整条路线上的铃。
func bell_swept_contains(note: Note, beat: float, from: Vector2, to: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	if from.distance_to(to) < 0.5:
		return bell_contains(note, beat, to, tolerance)
	if _segment_near_band(bell_live_band(note, beat), from, to, tolerance):
		return true
	return _segment_near_band(bell_band_points(note, beat), from, to, tolerance)


func _segment_near_band(band: Array[Vector2], from: Vector2, to: Vector2, tolerance := BELL_RADIAL_TOLERANCE) -> bool:
	for i in band.size() - 1:
		var a := band[i]
		var b := band[i + 1]
		if not a.is_finite() or not b.is_finite():
			continue
		var pair := Geometry2D.get_closest_points_between_segments(a, b, from, to)
		if pair.size() >= 2 and pair[0].distance_to(pair[1]) <= tolerance:
			return true
	return false


## 金键的屏幕形态：外圈取弧带中点，圆心取圆心金点。
func bell_screen(note: Note, beat: float) -> Dictionary:
	var points := bell_live_band(note, beat)
	if points.size() < 2:
		return {}
	return {"center": points[points.size() / 2], "radius": BELL_BAND_HALF}


## 和 _draw_bell 同一套飞入几何：判定与特效都跟着可见位置走。
func bell_live_band(note: Note, beat: float) -> Array[Vector2]:
	var chart := get_chart()
	var empty: Array[Vector2] = []
	if chart == null:
		return empty
	var grow := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, _approach(chart, note.beat, beat, note.group_id))
	return bell_band_points(note, beat, grow)


## 判定用：判定时刻（beat）环上条带的屏幕折线，宽度为角度 width。
func note_band_points(angle_deg: float, width_deg: float, beat: float, scale: float = 1.0) -> PackedVector2Array:
	var chart := get_chart()
	var points := PackedVector2Array()
	if chart == null:
		return points
	var width := maxf(0.0, width_deg)
	if width <= 0.05:
		var data := _boundary_point(chart, fposmod(angle_deg, 360.0) / 360.0, beat)
		if not bool(data.get("gap", false)):
			var p := project_design((data.point as Vector2) * scale)
			if _valid_point(p):
				points.append(p)
		return points
	var steps := clampi(int(width / 3.0), 6, 48)
	for i in steps + 1:
		var a := angle_deg - width * 0.5 + width * float(i) / float(steps)
		var data := _boundary_point(chart, fposmod(a, 360.0) / 360.0, beat)
		if bool(data.get("gap", false)):
			continue
		var p := project_design((data.point as Vector2) * scale)
		if _valid_point(p):
			points.append(p)
	return points


## 判定用：音符此刻画在屏幕上的条带（含飞入半径），和绘制走同一套几何。
func note_live_band(note: Note, beat: float, pad: float = 0.0) -> PackedVector2Array:
	var chart := get_chart()
	if chart == null:
		return PackedVector2Array()
	var pre := _pre_read_beats(chart, beat)
	var progress := _approach(chart, note.beat, beat, note.group_id)
	var grow := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress)
	return note_band_points(note.angle, note.arc_width() + pad, beat, grow)


## 鼠标在环平面上的角度（度），用于密集流的扇区判定。
func screen_angle_deg(screen: Vector2) -> float:
	var design := _screen_to_ring_plane(screen)
	if not design.is_finite() or design.x > 1.0e9:
		return NAN
	return fposmod(rad_to_deg(atan2(design.y, design.x)), 360.0)


## 音符头部此刻的屏幕位置（和绘制一样从环心飞入）：Anchor 与 Path 头共用。
func note_head_screen(note: Note, beat: float) -> Vector2:
	var chart := get_chart()
	if chart == null:
		return Vector2(INF, INF)
	return _flying_position(chart, note.angle, note.beat, beat, _star_fall_beats(chart, beat), note.group_id)


## Path 头在环上的落点弧（宽度 = note.width 度）。
## 判定按整段弧给点，不能只认弧中点：红弧两端到中点的距离远超容差，
## 玩家点在“看起来就是目标”的弧上却吃 MISS。
func path_head_arc(note: Note, beat: float, pad: float = 0.0) -> PackedVector2Array:
	return note_band_points(note.angle, note.width + pad, beat, 1.0)


## 音符图形自身的屏幕半径（位置判定容差用）。
func note_graphic_radius(kind: String) -> float:
	var ns := _note_scale() * float(_skin()["scale"])
	if kind == "anchor":
		return 16.0 * ns
	return 9.0 * ns


## 以“毫秒预读”为准的取音符窗口。
## 变 BPM 时同一个预读在拍号上会变宽/变窄，按拍号取窗口会让音符提前进/提前出；
## 这里先把 t±pre_ms 换成拍号，窗口在时间上永远是同一个长度。
func _notes_around(chart: Chart, t: float, back: float = 0.0, ahead: float = 0.0) -> Array[Note]:
	var pre_ms := _pre_read_ms(chart, t) * _max_group_speed_ratio(chart)
	var t_ms := chart.timing.beat_to_chart_ms(t)
	var from_beat := chart.timing.chart_ms_to_beat(t_ms - pre_ms) - back
	var to_beat := chart.timing.chart_ms_to_beat(t_ms + pre_ms) + ahead
	return _notes_in_range(chart, from_beat, to_beat)


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


## 演出指令叠加层：判定线 / 文本 / 滤镜。
## 滤镜不做真正的 shader 后处理，只叠加可读的画面提示 + 右上角活动清单，让作者看见"此刻生效了什么"。
func _draw_alpha_commands(canvas: Control, chart: Chart, t: float) -> void:
	if chart == null or chart.commands.is_empty():
		return
	var area := canvas.get_rect()
	var chips: Array[String] = []
	for command in chart.commands:
		if not command.enabled:
			continue
		var env := command.envelope_at(t)
		var in_window := t >= command.beat - 0.0001 and t <= command.end_beat() + 0.0001
		if not in_window:
			continue
		if command.category() == AlphaCommand.CATEGORY_FILTER:
			# 滤镜在起手段包络为 0 也要显示，否则刚好停在起始拍会以为没生效。
			chips.append("%s %.0f%%" % [command.label(), env * 100.0])
			continue
		if env <= 0.01:
			continue
		if command.category() == AlphaCommand.CATEGORY_TEXT:
			_draw_text_command(canvas, area, command, env)
	if chips.is_empty():
		return
	var font := UITheme.bold_font()
	var y := area.position.y + 20.0
	for i in mini(chips.size(), 6):
		canvas.draw_string(font, Vector2(area.end.x - 8.0, y), chips[i], HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 11,
			Color(1, 1, 1, 0.55))
		y += 14.0


func _draw_text_command(canvas: Control, area: Rect2, command: AlphaCommand, env: float) -> void:
	# JUDGETEXT 没有 content：它的 alpha 只该作用在判定文字上，预览层不画。
	var content := command.text_value("content", "")
	if content.is_empty():
		return
	var alpha := clampf(command.number("alpha", 1.0), 0.0, 1.0) * env
	if alpha <= 0.01:
		return
	var font_size := int(clampf(command.number("size", 48.0), 10.0, 200.0))
	var center := _text_center(command)
	var color := command.color_value("color", Color.WHITE)
	canvas.draw_string(UITheme.bold_font(), Vector2(center.x - area.size.x * 0.5, center.y), content,
		HORIZONTAL_ALIGNMENT_CENTER, area.size.x, font_size, Color(color.r, color.g, color.b, alpha))


## 选中滤镜时在预览里画出环平面扇区，改参数能立刻看到边界。
func _draw_selected_command_guides(canvas: Control, chart: Chart, t: float) -> void:
	var command := selected_command
	if command == null or chart == null or not chart.commands.has(command):
		return
	if command.category() != AlphaCommand.CATEGORY_FILTER or not command.flag("region_on", false):
		return
	var radius := _ring_radius_at(chart, t)
	var inner := clampf(command.number("region_inner", 0.0), 0.0, 2.0) * radius
	var outer := clampf(command.number("region_outer", 1.0), 0.0, 2.0) * radius
	if outer <= 0.5:
		return
	var start := deg_to_rad(command.number("region_angle", 0.0))
	var span := deg_to_rad(clampf(command.number("region_span", 360.0), 0.0, 360.0))
	var affine := _screen_affine()
	var center: Vector2 = affine[0]
	if not _valid_point(center):
		return
	var color := Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.95 if command.enabled else 0.4)
	var steps := maxi(8, int(72.0 * maxf(0.04, span / TAU)))
	var outer_points := _region_arc(affine, outer, start, span, steps)
	var inner_points := _region_arc(affine, inner, start, span, steps) if inner > 0.5 else PackedVector2Array()
	if span > TAU - 0.01:
		canvas.draw_polyline(outer_points, color, 2.0, true)
		if inner_points.size() > 1:
			canvas.draw_polyline(inner_points, color, 1.8, true)
		return
	var fill := PackedVector2Array()
	for point in outer_points:
		fill.append(point)
	if inner_points.size() > 1:
		for i in range(inner_points.size() - 1, -1, -1):
			fill.append(inner_points[i])
	else:
		fill.append(center)
	if fill.size() > 2:
		canvas.draw_colored_polygon(fill, Color(color.r, color.g, color.b, 0.09))
	canvas.draw_polyline(outer_points, color, 2.0, true)
	if inner_points.size() > 1:
		canvas.draw_polyline(inner_points, color, 1.8, true)
	var a0 := start
	var a1 := start + span
	var p0_inner := _affine_point(Vector2(cos(a0), sin(a0)) * inner, affine)
	var p0_outer := _affine_point(Vector2(cos(a0), sin(a0)) * outer, affine)
	var p1_inner := _affine_point(Vector2(cos(a1), sin(a1)) * inner, affine)
	var p1_outer := _affine_point(Vector2(cos(a1), sin(a1)) * outer, affine)
	canvas.draw_line(p0_inner, p0_outer, color, 1.8, true)
	canvas.draw_line(p1_inner, p1_outer, color, 1.8, true)


func _region_arc(affine: Array, radius: float, start: float, span: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps + 1:
		var angle := start + span * float(i) / float(steps)
		points.append(_affine_point(Vector2(cos(angle), sin(angle)) * radius, affine))
	return points


func _text_center(command: AlphaCommand) -> Vector2:
	var area := get_rect()
	var offset := Vector2(clampf(command.number("x", 0.0), -1.0, 1.0),
		clampf(command.number("y", 0.0), -1.0, 1.0))
	return area.get_center() + Vector2(offset.x * area.size.x * 0.5, offset.y * area.size.y * 0.5)


func _text_rect(command: AlphaCommand) -> Rect2:
	var content := command.text_value("content", "")
	if content.is_empty():
		return Rect2()
	var center := _text_center(command)
	var font_size := int(clampf(command.number("size", 48.0), 10.0, 200.0))
	var font := UITheme.bold_font()
	var text_size := font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var height := font.get_height(font_size)
	return Rect2(center.x - text_size.x * 0.5, center.y - height * 0.5,
		text_size.x, height).grow(8.0)


func _text_command_at(pos: Vector2) -> AlphaCommand:
	var chart := get_chart()
	if chart == null:
		return null
	var t := get_time_beat()
	var found: AlphaCommand = null
	for command in chart.sorted_commands():
		if not command.enabled or command.category() != AlphaCommand.CATEGORY_TEXT:
			continue
		if command.text_value("content", "").is_empty():
			continue
		if t < command.beat - 0.0001 or t > command.end_beat() + 0.0001:
			continue
		if command.envelope_at(t) <= 0.01:
			continue
		if _text_rect(command).has_point(pos):
			found = command
	return found


func _drag_text(pos: Vector2) -> void:
	var area := get_rect()
	var center := pos - _text_drag_offset
	var nx := clampf((center.x - area.get_center().x) / maxf(1.0, area.size.x * 0.5), -1.0, 1.0)
	var ny := clampf((center.y - area.get_center().y) / maxf(1.0, area.size.y * 0.5), -1.0, 1.0)
	_text_drag.params["x"] = nx
	_text_drag.params["y"] = ny
	if _app != null:
		_app.touch_chart()
	_overlay.queue_redraw()


## 音符下落进度：HS 越大越早冲到判定环，只影响该音符自身。
func _note_progress(chart: Chart, note: Note, t: float) -> float:
	var progress := _approach(chart, note.beat, t, note.group_id)
	var speed := note.speed_scale()
	if absf(speed - 1.0) > 0.001:
		progress = clampf(progress * speed, 0.0, 1.0)
	return progress


## 音符视觉半径倍率：出生半径（spawn）+ 落点弹跳（bounce）。返回可 > 1，表示越过判定环外侧。
func _note_radius_scale(note: Note, progress: float) -> float:
	var q := lerpf(Note.SPAWN_LENGTH_RATIO, 1.0, progress)
	if note.spawn > 0.001:
		q = maxf(q, lerpf(note.spawn, 1.0, progress))
	if note.bounce > 0.001:
		q = maxf(0.0, q * note.bounce_radius(progress))
	return q


## 滤镜后处理：整块预览画面走一次屏幕采样 shader。
## 指令名与默认值照搬 MajdataPlay 的滤镜目录，效果是同一语义的近似实现（不是移植它的 shader）。
const FILTER_SHADER := """shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float brightness = 0.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float hue_shift = 0.0;
uniform float vignette = 0.0;
uniform float zoom = 1.0;
uniform float pixelate = 0.0;
uniform float glitch = 0.0;
uniform float invert = 0.0;
uniform float posterize = 0.0;
uniform float split = 0.0;
uniform float ripple = 0.0;
uniform float radial = 0.0;
uniform float kaleido = 0.0;
uniform float kaleido_segments = 6.0;
uniform float rotate = 0.0;
uniform float bloom = 0.0;
uniform vec2 move = vec2(0.0);
uniform float shake = 0.0;
uniform float shake_freq = 12.0;
uniform vec4 tint = vec4(1.0);
uniform float tint_amount = 0.0;
uniform vec4 flash = vec4(1.0, 1.0, 1.0, 0.0);
uniform vec4 fade = vec4(0.0, 0.0, 0.0, 0.0);
uniform float mask_on = 0.0;
uniform vec2 mask_center = vec2(0.5);
uniform vec2 mask_axis_x = vec2(1.0, 0.0);
uniform vec2 mask_axis_y = vec2(0.0, 1.0);
uniform float mask_angle_start = 0.0;
uniform float mask_angle_span = 6.2831853;
uniform float mask_inner = 0.0;
uniform float mask_outer = 1.0;
uniform float mask_feather = 0.1;
uniform float mask_ring_radius = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 uv = SCREEN_UV - move;
	vec2 center = vec2(0.5);
	vec2 offset = uv - center;
	float tremor = sin(TIME * shake_freq) * 0.006 * shake;
	uv += vec2(tremor, cos(TIME * shake_freq * 1.7) * 0.006 * shake);

	vec2 warped = center + (uv - center) / max(zoom, 0.05);
	float cs = cos(rotate);
	float sn = sin(rotate);
	warped = center + mat2(vec2(cs, -sn), vec2(sn, cs)) * (warped - center);

	if (kaleido > 0.001) {
		vec2 d = warped - center;
		float radius = length(d);
		float angle = atan(d.y, d.x);
		float segment = 6.2831853 / max(kaleido_segments, 2.0);
		angle = abs(mod(angle, segment) - segment * 0.5);
		warped = center + vec2(cos(angle), sin(angle)) * radius;
	}

	float wave = sin(length(warped - center) * 46.0 - TIME * 7.0) * 0.012 * ripple;
	warped += normalize(warped - center + vec2(0.0001)) * wave;

	if (glitch > 0.001) {
		float band = floor(warped.y * 42.0);
		float noise = fract(sin(band * 12.9898 + floor(TIME * 14.0) * 7.233) * 43758.5453);
		warped.x += (noise - 0.5) * 0.12 * glitch * step(0.55, noise);
	}

	if (pixelate > 0.001) {
		float cells = mix(640.0, 36.0, clamp(pixelate, 0.0, 1.0));
		warped = floor(warped * cells) / cells;
	}

	vec3 col;
	if (split > 0.001) {
		float shift = 0.004 * clamp(split, 0.0, 1.0);
		col.r = texture(screen_tex, warped + vec2(shift, 0.0)).r;
		col.g = texture(screen_tex, warped).g;
		col.b = texture(screen_tex, warped - vec2(shift, 0.0)).b;
	} else if (radial > 0.001) {
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float scale = 1.0 - float(i) * 0.032 * clamp(radial, 0.0, 1.0);
			acc += texture(screen_tex, center + (warped - center) * scale).rgb;
		}
		col = acc / 6.0;
	} else if (bloom > 0.001) {
		float amount = clamp(bloom, 0.0, 4.0);
		col = texture(screen_tex, warped).rgb;
		for (int i = 1; i <= 3; i++) {
			float spread = 0.0035 * float(i) * amount;
			float weight = 0.4 / float(i);
			col += texture(screen_tex, warped + vec2(spread, 0.0)).rgb * weight;
			col += texture(screen_tex, warped - vec2(spread, 0.0)).rgb * weight;
			col += texture(screen_tex, warped + vec2(0.0, spread)).rgb * weight;
			col += texture(screen_tex, warped - vec2(0.0, spread)).rgb * weight;
		}
		col /= 1.0 + 1.6 * amount;
	} else {
		col = texture(screen_tex, warped).rgb;
	}

	col = (col - 0.5) * contrast + 0.5;
	col += brightness;

	vec3 hsv = rgb2hsv(clamp(col, 0.0, 1.0));
	hsv.x = fract(hsv.x + hue_shift / 6.2831853);
	hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	col = hsv2rgb(hsv);

	if (posterize > 0.5) {
		float steps = max(posterize, 2.0);
		col = floor(col * steps) / steps;
	}

	col = mix(col, vec3(1.0) - col, clamp(invert, 0.0, 1.0));
	col = mix(col, tint.rgb, clamp(tint_amount * tint.a, 0.0, 1.0));

	float curve = smoothstep(0.95, 0.26, length(offset) * 1.45);
	col *= mix(1.0, curve, clamp(vignette, 0.0, 1.0));

	col = mix(col, flash.rgb, clamp(flash.a, 0.0, 1.0));
	col = mix(col, fade.rgb, clamp(fade.a, 0.0, 1.0));

	float mask = 1.0;
	if (mask_on > 0.5) {
		vec2 local = inverse(mat2(mask_axis_x, mask_axis_y)) * (UV - mask_center);
		float radius = length(local) / max(mask_ring_radius, 0.0001);
		float feather = max(mask_feather, 0.0001);
		float inner = mask_inner <= 0.0001 ? 1.0
			: smoothstep(mask_inner - feather, mask_inner + feather, radius);
		float outer = 1.0 - smoothstep(mask_outer - feather, mask_outer + feather, radius);
		float angle = atan(local.y, local.x);
		float span = clamp(mask_angle_span, 0.0, 6.2831853);
		float delta = mod(angle - mask_angle_start + 12.5663706, 6.2831853);
		float angle_feather = max(mask_feather * 1.5, 0.002);
		float sector = span >= 6.2831852 ? 1.0
			: 1.0 - smoothstep(span - angle_feather, span + angle_feather, delta);
		mask = inner * outer * sector;
	}
	vec3 original = texture(screen_tex, SCREEN_UV).rgb;
	col = mix(original, col, mask);

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
"""


func _build_filter_layer() -> void:
	if _filter_layer != null:
		return
	var shader := Shader.new()
	shader.code = FILTER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_filter_layer = ColorRect.new()
	_filter_layer.name = "FilterLayer"
	_filter_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_layer.color = Color.WHITE
	_filter_layer.material = material
	# 先可见几帧做预热（编译 shader、建好管线），之后由 _update_filter_visibility()
	# 按当前拍点有没有滤镜来决定显隐；没有滤镜时这层整层隐藏。
	_filter_layer.visible = true
	add_child(_filter_layer)
	_filter_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## 只为带滤镜的试玩在准备层底下再预热几帧，把 shader 首次编译的卡顿吃掉。
func warm_up_filters() -> void:
	if _filter_layer == null or not _filter_layer.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless" or not RenderingServer.render_loop_enabled:
		return
	_filter_warmup_left = maxi(_filter_warmup_left, FILTER_WARMUP_FRAMES)
	_set_filter_visible(true)


## 把当前拍点上所有启用中的滤镜指令合成为一组 shader 参数。
func _filter_state(chart: Chart, t: float) -> Dictionary:
	var state := {
		"brightness": 0.0, "contrast": 1.0, "saturation": 1.0, "hue_shift": 0.0,
		"vignette": 0.0, "zoom": 1.0, "pixelate": 0.0, "glitch": 0.0, "invert": 0.0,
		"posterize": 0.0, "split": 0.0, "ripple": 0.0, "radial": 0.0, "kaleido": 0.0,
		"kaleido_segments": 6.0,
		"rotate": 0.0, "bloom": 0.0, "move": Vector2.ZERO, "shake": 0.0, "shake_freq": 12.0,
		"tint": Color(1, 1, 1, 1), "tint_amount": 0.0,
		"flash": Color(1, 1, 1, 0), "fade": Color(0, 0, 0, 0),
	}
	if chart == null:
		return {"uniforms": state, "active": false, "region": {}}
	var active := false
	var last_filter: AlphaCommand = null
	for command in chart.commands:
		if not command.enabled or command.category() != AlphaCommand.CATEGORY_FILTER:
			continue
		var env := command.envelope_at(t)
		var in_window := t >= command.beat - 0.0001 and t <= command.end_beat() + 0.0001
		if env <= 0.001:
			if not in_window:
				continue
			# 停在指令起始拍时包络正好是 0，给一个可见的预览底噪，免得以为指令没生效。
			env = 0.35
		active = true
		if last_filter == null or command.beat > last_filter.beat \
				or (is_equal_approx(command.beat, last_filter.beat) and command.id > last_filter.id):
			last_filter = command
		var strength := clampf(command.number("strength", 0.8), 0.0, 4.0) * env
		match command.name:
			"FLASH":
				state["flash"] = _stronger_color(state["flash"], Color(1, 1, 1, clampf(strength, 0.0, 1.0)))
			"FADE":
				state["fade"] = _stronger_color(state["fade"], Color(0, 0, 0, clampf(strength, 0.0, 1.0)))
			"BRIGHTNESS":
				state["brightness"] = float(state["brightness"]) + command.number("value", 0.5) * env * 0.6
			"SATURATION":
				state["saturation"] = maxf(float(state["saturation"]) * maxf(1.0 + command.number("value", 0.5) * env, 0.0), 0.0)
			"CONTRAST":
				state["contrast"] = maxf(float(state["contrast"]) * maxf(1.0 + (command.number("value", 1.2) - 1.0) * env, 0.1), 0.1)
			"HUE":
				state["hue_shift"] = float(state["hue_shift"]) + deg_to_rad(command.number("value", 45.0)) * env
			"ZOOM":
				state["zoom"] = maxf(float(state["zoom"]) * maxf(lerpf(1.0, command.number("value", 1.5), env), 0.05), 0.05)
			"VIGNETTE":
				state["vignette"] = maxf(float(state["vignette"]), clampf(strength, 0.0, 1.0))
			"ROTATE":
				state["rotate"] = float(state["rotate"]) + deg_to_rad(command.number("value", 10.0)) * env
			"KALEIDOSCOPE":
				# on=false 表示在这段时长里从满强度过渡回关闭，而不是永久保持。
				var fade_out := 1.0 - command.progress_at(t) if not command.flag("on", true) else 1.0
				state["kaleido"] = maxf(float(state["kaleido"]), env * fade_out)
				state["kaleido_segments"] = clampf(command.number("segments", 6.0), 2.0, 16.0)
			"BLOOM":
				state["bloom"] = maxf(float(state["bloom"]), clampf(strength, 0.0, 4.0))
			"INVERT":
				state["invert"] = maxf(float(state["invert"]), clampf(strength, 0.0, 1.0))
			"POSTERIZE":
				state["posterize"] = maxf(float(state["posterize"]), maxf(command.number("levels", 6.0) * env, 2.0))
			"PIXELATE":
				state["pixelate"] = maxf(float(state["pixelate"]), clampf(command.number("size", 8.0) / 32.0, 0.05, 1.0) * env)
			"GLITCH", "SHATTER", "TVNOISE":
				state["glitch"] = maxf(float(state["glitch"]), clampf(strength, 0.0, 1.0))
			"SPLIT":
				state["split"] = maxf(float(state["split"]), clampf(command.number("offset", 0.1) / 0.1, 0.0, 1.0) * env)
			"RIPPLE":
				state["ripple"] = maxf(float(state["ripple"]), clampf(strength, 0.0, 1.0))
			"RADIALBLUR", "GAUSSIAN", "TRAIL", "LENSDISTORT":
				state["radial"] = maxf(float(state["radial"]), clampf(strength, 0.0, 1.0))
			"TINT":
				state["tint"] = command.color_value("color", Color(1, 0.4, 0.8))
				state["tint_amount"] = maxf(float(state["tint_amount"]), clampf(strength, 0.0, 1.0))
			"NEON":
				state["tint"] = command.color_value("color", Color(0.25, 0.9, 1.0))
				state["tint_amount"] = maxf(float(state["tint_amount"]), 0.55 * env)
				state["bloom"] = maxf(float(state["bloom"]), env)
				state["saturation"] = maxf(float(state["saturation"]), 1.25)
			"RAINBOW":
				var spin := fmod(Time.get_ticks_msec() / 1000.0 * 2.0, TAU)
				state["hue_shift"] = float(state["hue_shift"]) + spin * clampf(strength, 0.0, 1.0)
			"SHAKE":
				state["shake"] = maxf(float(state["shake"]), clampf(command.number("strength", 0.5), 0.0, 1.0))
				state["shake_freq"] = command.number("frequency", 12.0)
			"MOVE":
				state["move"] = Vector2(command.number("x", 0.0), command.number("y", 0.0)) * env * 0.25
			_:
				pass
	var region := {}
	if last_filter != null:
		region = {
			"on": last_filter.flag("region_on", false),
			"angle": last_filter.number("region_angle", 0.0),
			"span": last_filter.number("region_span", 360.0),
			"inner": last_filter.number("region_inner", 0.0),
			"outer": last_filter.number("region_outer", 1.0),
			"feather": last_filter.number("region_feather", 0.1),
		}
	return {"uniforms": state, "active": active, "region": region}


func _stronger_color(current: Variant, candidate: Color) -> Color:
	var existing: Color = current
	return candidate if candidate.a > existing.a else existing


## 滤镜层按需显隐：当前拍点没有任何滤镜生效时整层隐藏，省掉每帧一次整屏拷贝、
## 屏幕纹理 mip 链和一次全屏 pass。恒等 pass 只是透传（额外做了 clamp 与一次
## HSV 往返，误差 ≤1/255），隐藏前后肉眼无差别。
func _update_filter_visibility(chart: Chart, t: float) -> void:
	if _filter_warmup_left > 0:
		_set_filter_visible(true)
		return
	if chart == null or chart.commands.is_empty():
		_set_filter_visible(false)
		return
	_set_filter_visible(bool(_filter_state(chart, t).get("active", false)))


func _set_filter_visible(active: bool) -> void:
	if _filter_layer == null:
		return
	var wanted := FILTER_ALWAYS_ON or active
	if _filter_layer.visible != wanted:
		_filter_layer.visible = wanted


func _apply_filters(chart: Chart, t: float) -> void:
	if _filter_layer == null:
		return
	var state: Dictionary = _filter_state(chart, t)
	# 没有滤镜生效时层本身由 _update_filter_visibility() 隐藏，这里不再写恒等 uniform。
	if not bool(state["active"]):
		return
	var material := _filter_layer.material as ShaderMaterial
	if material == null:
		return
	var uniforms: Dictionary = state["uniforms"]
	for key in uniforms:
		material.set_shader_parameter(String(key), uniforms[key])
	var region: Dictionary = state.get("region", {})
	var mask_on := bool(region.get("on", false))
	material.set_shader_parameter("mask_on", 1.0 if mask_on else 0.0)
	if not mask_on or chart == null:
		return
	var layer_size := _filter_layer.size
	if layer_size.x < 1.0 or layer_size.y < 1.0:
		layer_size = size
	if layer_size.x < 1.0 or layer_size.y < 1.0:
		return
	var affine := _screen_affine()
	var center: Vector2 = affine[0]
	var x_axis: Vector2 = affine[1]
	var y_axis: Vector2 = affine[2]
	material.set_shader_parameter("mask_center", Vector2(center.x / layer_size.x, center.y / layer_size.y))
	material.set_shader_parameter("mask_axis_x", Vector2(x_axis.x / layer_size.x, x_axis.y / layer_size.y))
	material.set_shader_parameter("mask_axis_y", Vector2(y_axis.x / layer_size.x, y_axis.y / layer_size.y))
	material.set_shader_parameter("mask_angle_start", deg_to_rad(float(region.get("angle", 0.0))))
	material.set_shader_parameter("mask_angle_span", deg_to_rad(clampf(float(region.get("span", 360.0)), 0.0, 360.0)))
	material.set_shader_parameter("mask_inner", clampf(float(region.get("inner", 0.0)), 0.0, 2.0))
	material.set_shader_parameter("mask_outer", clampf(float(region.get("outer", 1.0)), 0.0, 2.0))
	material.set_shader_parameter("mask_feather", clampf(float(region.get("feather", 0.1)), 0.0, 0.5))
	material.set_shader_parameter("mask_ring_radius", _ring_radius_at(chart, t))


## 环平面遮罩的半径基准：用边界采样点的平均半径，非圆形边界也不会除以 0。
func _ring_radius_at(chart: Chart, beat: float) -> float:
	var points := _frame_for(chart, beat).sample_points(64)
	var total := 0.0
	var count := 0
	for item in points:
		if bool(item.get("gap", false)):
			continue
		var point: Vector2 = item.get("point", Vector2.ZERO)
		if not point.is_finite():
			continue
		total += point.length()
		count += 1
	return maxf(total / maxf(1.0, float(count)), 1.0)
