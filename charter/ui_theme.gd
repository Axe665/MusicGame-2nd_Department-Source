class_name UITheme
extends RefCounted

const BG := Color("#0B0C10")
const PANEL := Color("#12141A")
const RAISED := Color("#191C24")
const RAISED_HOVER := Color("#232834")
const BORDER := Color("#2A2F3A")
const BORDER_BRIGHT := Color("#3D4453")
const INK := Color("#F2F0EA")
const MUTED := Color("#9AA0AC")
const FAINT := Color("#6B7280")
const CORAL := Color("#F2583E")
const CORAL_DARK := Color("#A83828")
const PINK := Color("#FF6FAE")
const CYAN := Color("#5FD8CF")
const GOLD := Color("#F0C36A")
## 金键（Bell）：亮黄 + 乳白高光 + 深褐描边。刻意和 Hold 的琥珀 #F2A65A 拉开。
const KEY_YELLOW := Color("#FFD84D")
const KEY_HILITE := Color("#FFF6D2")
const KEY_EDGE := Color("#2A1E05")
## 金键内侧斜面（比主色深一档）。
const KEY_DEEP := Color("#B8860B")
const ACCENT := Color("#FFDE00")
const ACCENT_DARK := Color("#C9A800")
const CARD := Color("#DCDAD2")
const CARD_INK := Color("#111315")
const FONT_REGULAR := preload("res://assets/fonts/NotoSansSC-Regular.ttf")
const FONT_BOLD := preload("res://assets/fonts/NotoSansSC-Bold.ttf")
const FONT_MONO := preload("res://assets/fonts/NotoSansMono-Regular.ttf")
const AMBER := Color("#F2A65A")
const MINT := Color("#6FE3A8")
const SEEK_IN := Color("#79E0FF")
const SEEK_OUT := Color("#FFB86B")
const VIOLET := Color("#9C8CFF")
const RED := Color("#D94B3D")
const GREEN := Color("#86C97A")
const WHITE := Color("#FFFFFF")


static func build() -> Theme:
	var theme := Theme.new()
	var regular: Font = FONT_REGULAR
	var bold: Font = load("res://assets/fonts/NotoSansSC-Bold.ttf")
	var mono: Font = load("res://assets/fonts/NotoSansMono-Regular.ttf")
	theme.default_font = regular
	theme.default_font_size = 14

	theme.set_font("font", "Label", regular)
	theme.set_font_size("font_size", "Label", 14)
	theme.set_color("font_color", "Label", INK)

	theme.set_font("font", "Button", regular)
	theme.set_font_size("font_size", "Button", 13)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", BG)
	theme.set_color("font_disabled_color", "Button", FAINT)
	theme.set_stylebox("normal", "Button", _box(RAISED, BORDER, 6, 8, 4))
	theme.set_stylebox("hover", "Button", _box(RAISED_HOVER, BORDER_BRIGHT, 6, 8, 4))
	theme.set_stylebox("pressed", "Button", _box(ACCENT, ACCENT, 6, 8, 4))
	theme.set_stylebox("disabled", "Button", _box(PANEL, Color("#222630"), 6, 8, 4))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), ACCENT, 6, 8, 4, 1))

	for type_name in ["OptionButton", "MenuButton", "CheckButton"]:
		theme.set_font("font", type_name, regular)
		theme.set_font_size("font_size", type_name, 13)
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_hover_color", type_name, WHITE)
		theme.set_color("font_pressed_color", type_name, BG)
		theme.set_color("font_disabled_color", type_name, FAINT)
		theme.set_stylebox("normal", type_name, _box(RAISED, BORDER, 6, 8, 4))
		theme.set_stylebox("hover", type_name, _box(RAISED_HOVER, BORDER_BRIGHT, 6, 8, 4))
		theme.set_stylebox("pressed", type_name, _box(ACCENT, ACCENT, 6, 8, 4))
		theme.set_stylebox("disabled", type_name, _box(PANEL, Color("#222630"), 6, 8, 4))
		theme.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), ACCENT, 6, 8, 4, 1))

	theme.set_font("font", "LineEdit", regular)
	theme.set_font_size("font_size", "LineEdit", 13)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", FAINT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(CYAN.r, CYAN.g, CYAN.b, 0.25))
	theme.set_stylebox("normal", "LineEdit", _box(RAISED, BORDER, 5, 7, 3))
	theme.set_stylebox("focus", "LineEdit", _box(RAISED, ACCENT, 5, 7, 3, 1))
	theme.set_stylebox("read_only", "LineEdit", _box(PANEL, BORDER, 5, 7, 3))

	theme.set_font("font", "SpinBox", regular)
	theme.set_font_size("font_size", "SpinBox", 13)
	theme.set_color("font_color", "SpinBox", INK)
	theme.set_color("font_placeholder_color", "SpinBox", FAINT)

	theme.set_font("font", "CheckBox", regular)
	theme.set_font_size("font_size", "CheckBox", 13)
	theme.set_color("font_color", "CheckBox", INK)
	theme.set_color("font_hover_color", "CheckBox", WHITE)
	theme.set_color("font_pressed_color", "CheckBox", WHITE)
	theme.set_color("font_disabled_color", "CheckBox", FAINT)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER, 8, 10, 8))
	theme.set_stylebox("panel", "Panel", _box(PANEL, BORDER, 8, 10, 8))

	theme.set_stylebox("panel", "TabContainer", _box(PANEL, BORDER, 8, 8, 8))
	theme.set_stylebox("tab_selected", "TabContainer", _box(ACCENT, ACCENT, 6, 12, 6))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(PANEL, BORDER, 6, 12, 6))
	theme.set_stylebox("tab_hovered", "TabContainer", _box(RAISED_HOVER, BORDER_BRIGHT, 6, 12, 6))
	theme.set_stylebox("tab_disabled", "TabContainer", _box(PANEL, BORDER, 6, 12, 6))
	theme.set_color("font_selected_color", "TabContainer", BG)
	theme.set_color("font_unselected_color", "TabContainer", MUTED)
	theme.set_color("font_hovered_color", "TabContainer", INK)
	theme.set_font("font", "TabContainer", regular)
	theme.set_font_size("font_size", "TabContainer", 13)

	theme.set_font("font", "ItemList", regular)
	theme.set_font_size("font_size", "ItemList", 13)
	theme.set_color("font_color", "ItemList", INK)
	theme.set_color("font_selected_color", "ItemList", WHITE)
	theme.set_color("guide_color", "ItemList", BORDER)
	theme.set_stylebox("panel", "ItemList", _box(PANEL, BORDER, 6, 6, 4))
	theme.set_stylebox("selected", "ItemList", _box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), ACCENT, 4, 6, 3))
	theme.set_stylebox("selected_focus", "ItemList", _box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.24), ACCENT, 4, 6, 3))
	theme.set_stylebox("cursor", "ItemList", _box(Color(0, 0, 0, 0), CYAN, 4, 6, 3, 1))
	theme.set_stylebox("cursor_unfocused", "ItemList", _box(Color(0, 0, 0, 0), BORDER_BRIGHT, 4, 6, 3, 1))

	theme.set_font("font", "PopupMenu", regular)
	theme.set_font_size("font_size", "PopupMenu", 13)
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", WHITE)
	theme.set_stylebox("panel", "PopupMenu", _box(RAISED, BORDER_BRIGHT, 6, 8, 6))
	theme.set_stylebox("hover", "PopupMenu", _box(Color(CYAN.r, CYAN.g, CYAN.b, 0.18), Color(0, 0, 0, 0), 4, 6, 3))

	theme.set_stylebox("background", "ProgressBar", _box(RAISED, BORDER, 4, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(ACCENT, Color(0, 0, 0, 0), 4, 0, 0))
	theme.set_font("font", "ProgressBar", regular)
	theme.set_font_size("font_size", "ProgressBar", 11)
	theme.set_color("font_color", "ProgressBar", INK)

	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_stylebox("separator", "VSeparator", line)

	theme.set_stylebox("panel", "TooltipPanel", _box(RAISED, BORDER_BRIGHT, 5, 8, 5))
	theme.set_font("font", "TooltipLabel", regular)
	theme.set_font_size("font_size", "TooltipLabel", 12)
	theme.set_color("font_color", "TooltipLabel", INK)

	theme.set_font("font", "Window", regular)
	theme.set_font_size("font_size", "Window", 14)
	theme.set_stylebox("panel", "Window", _box(PANEL, BORDER_BRIGHT, 8, 12, 10))

	# Keep the mono face for timing readouts; apply per-node via helper.
	return theme


static func _box(
	bg: Color,
	border: Color,
	radius: int,
	margin_x: int,
	margin_y: int,
	border_width: int = 1
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


static func mono_font() -> Font:
	return FONT_MONO


static func bold_font() -> Font:
	return FONT_BOLD


static func style_label(label: Label, size: int = 14, color: Color = INK) -> Label:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func style_mono(label: Label, size: int = 13, color: Color = INK) -> Label:
	label.add_theme_font_override("font", mono_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


static func style_section(label: Label) -> Label:
	label.add_theme_font_override("font", bold_font())
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", INK)
	return label
