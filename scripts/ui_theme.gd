extends RefCounted
## 全软件 UI 统一配置(Tide 主题):所有窗口的字号 / 间距 / 配色都改这里,一处改动全局生效。

const HERO := 24
const TITLE := 18
const BODY := 16
const HINT := 13

const PAD := 16
const GAP := 12
const LINE := 8
const ROW := 6

const TEXT := Color(0.914, 0.929, 0.922, 0.98)
const TEXT_STRONG := Color(0.914, 0.929, 0.922, 0.88)
const TEXT_DIM := Color(0.541, 0.604, 0.596, 0.95)
const ACCENT := Color(0.906, 0.722, 0.361)

const SECTION := Color(0.906, 0.722, 0.361)
const SECTION_WARN := Color(0.941, 0.663, 0.294)
const SECTION_OK := Color(0.275, 0.788, 0.541)

const UP := Color(0.275, 0.788, 0.541)
const DOWN := Color(0.941, 0.439, 0.431)
const WARN := Color(0.941, 0.663, 0.294)
const SAVE := Color(0.4, 0.85, 0.6)

const CARD_BG := Color(1, 1, 1, 0.045)
const CARD_BORDER := Color(1, 1, 1, 0.09)
const WINDOW_BORDER := Color(0.36, 0.44, 0.44, 0.55)

const RADIUS := 9
const ACCENT_SOFT := Color(0.906, 0.722, 0.361, 0.16)

const TONES := {
	"deep_water": {"win": Color(0.052,0.082,0.074), "group": Color(0.074,0.116,0.104),
		"card": Color(0.100,0.152,0.136), "hi": Color(0.134,0.200,0.180), "mute": Color(0.470,0.545,0.520)},
	"warm_charcoal": {"win": Color(0.075,0.063,0.051), "group": Color(0.102,0.090,0.078),
		"card": Color(0.145,0.129,0.114), "hi": Color(0.192,0.173,0.149), "mute": Color(0.416,0.376,0.341)},
	"indigo": {"win": Color(0.051,0.063,0.094), "group": Color(0.078,0.094,0.149),
		"card": Color(0.118,0.141,0.204), "hi": Color(0.165,0.192,0.271), "mute": Color(0.349,0.376,0.478)},
}

const GROUP_BG_ALPHA := 0.72

static var _tone: String = "deep_water"
static var WINDOW_BG := TONES["deep_water"]["win"] as Color
static var TITLEBAR_BG := TONES["deep_water"]["group"] as Color
static var GROUP_BG := Color(0.074, 0.116, 0.104, GROUP_BG_ALPHA)
static var PANEL_CARD := TONES["deep_water"]["card"] as Color
static var CARD_HI := TONES["deep_water"]["hi"] as Color
static var TEXT_MUTE := Color(0.470, 0.545, 0.520, 0.85)

static func set_tone(name: String) -> void:
	if not TONES.has(name):
		name = "deep_water"
	_tone = name
	var t: Dictionary = TONES[name]
	var g: Color = t["group"]
	WINDOW_BG = t["win"]
	TITLEBAR_BG = g
	GROUP_BG = Color(g.r, g.g, g.b, GROUP_BG_ALPHA)
	PANEL_CARD = t["card"]
	CARD_HI = t["hi"]
	var m: Color = t["mute"]
	TEXT_MUTE = Color(m.r, m.g, m.b, 0.85)

static func get_tone() -> String:
	return _tone

static var _sans: Font = null
static var _sans_bold: Font = null
static var _sans_heavy: Font = null
static var _mono: Font = null
static var _cjk: FontFile = null

static func _cjk_src() -> FontFile:
	if _cjk == null and ResourceLoader.exists("res://NotoSansSC.ttf"):
		_cjk = load("res://NotoSansSC.ttf")
	return _cjk

static func sans() -> Font:
	if _sans == null:
		var src := _cjk_src()
		if src != null:
			var fv := FontVariation.new()
			fv.base_font = src
			fv.variation_opentype = {"wght": 400}
			_sans = fv
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Segoe UI"])
			_sans = f
	return _sans

static func sans_bold() -> Font:
	if _sans_bold == null:
		var src := _cjk_src()
		if src != null:
			var fv := FontVariation.new()
			fv.base_font = src
			fv.variation_opentype = {"wght": 700}
			_sans_bold = fv
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Segoe UI"])
			f.font_weight = 700
			_sans_bold = f
	return _sans_bold

static func sans_heavy() -> Font:
	if _sans_heavy == null:
		var src := _cjk_src()
		if src != null:
			var fv := FontVariation.new()
			fv.base_font = src
			fv.variation_opentype = {"wght": 900}
			fv.variation_embolden = 0.35
			_sans_heavy = fv
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["Segoe UI"])
			f.font_weight = 800
			_sans_heavy = f
	return _sans_heavy

static func mono() -> Font:
	if _mono == null:
		if ResourceLoader.exists("res://JetBrainsMono.ttf"):
			var mf: FontFile = load("res://JetBrainsMono.ttf")
			var fb: Array[Font] = [sans()]
			mf.fallbacks = fb
			_mono = mf
		else:
			var f := SystemFont.new()
			f.font_names = PackedStringArray(["JetBrains Mono", "Consolas"])
			_mono = f
	return _mono

static func apply_default_font() -> void:
	ThemeDB.fallback_font = sans()

static func bg_panel() -> Panel:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = WINDOW_BG
	s.border_color = WINDOW_BORDER
	s.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", s)
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func style_dialog(dlg: AcceptDialog) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = WINDOW_BG
	s.border_color = WINDOW_BORDER
	s.set_border_width_all(1)
	s.content_margin_left = PAD
	s.content_margin_right = PAD
	s.content_margin_top = PAD
	s.content_margin_bottom = PAD
	dlg.add_theme_stylebox_override("panel", s)

static func input_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CARD_BG
	s.border_color = CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

static func input_style_focus() -> StyleBoxFlat:
	var s := input_style()
	s.border_color = ACCENT
	return s

static func style_input(edit: LineEdit) -> void:
	edit.add_theme_stylebox_override("normal", input_style())
	edit.add_theme_stylebox_override("focus", input_style_focus())
	edit.add_theme_stylebox_override("read_only", input_style())
	edit.add_theme_color_override("font_color", TEXT)
	edit.add_theme_color_override("font_placeholder_color", TEXT_MUTE)
	edit.add_theme_color_override("caret_color", ACCENT)

static func style_spinbox(sb: SpinBox) -> void:
	style_input(sb.get_line_edit())
	var bg := StyleBoxFlat.new()
	bg.bg_color = CARD_BG
	bg.set_corner_radius_all(4)
	var hov := StyleBoxFlat.new()
	hov.bg_color = ACCENT_SOFT
	hov.set_corner_radius_all(4)
	for n in ["up_background", "down_background", "up_background_disabled", "down_background_disabled"]:
		sb.add_theme_stylebox_override(n, bg)
	for n in ["up_background_hovered", "up_background_pressed", "down_background_hovered", "down_background_pressed"]:
		sb.add_theme_stylebox_override(n, hov)
	for n in ["up_icon_modulate", "down_icon_modulate", "up_disabled_icon_modulate", "down_disabled_icon_modulate"]:
		sb.add_theme_color_override(n, TEXT_DIM)
	for n in ["up_hover_icon_modulate", "up_pressed_icon_modulate", "down_hover_icon_modulate", "down_pressed_icon_modulate"]:
		sb.add_theme_color_override(n, ACCENT)
	var sep := StyleBoxFlat.new()
	sep.bg_color = CARD_BORDER
	sb.add_theme_stylebox_override("field_and_buttons_separator", sep)
	var nosep := StyleBoxEmpty.new()
	sb.add_theme_stylebox_override("up_down_buttons_separator", nosep)

static func _icon_button_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func style_icon_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _icon_button_style(CARD_BG))
	btn.add_theme_stylebox_override("hover", _icon_button_style(Color(1, 1, 1, 0.10)))
	btn.add_theme_stylebox_override("pressed", _icon_button_style(Color(1, 1, 1, 0.14)))
	btn.add_theme_stylebox_override("focus", input_style_focus())
	btn.add_theme_color_override("font_color", ACCENT)
	btn.add_theme_color_override("font_hover_color", ACCENT)

# ---- Tide 组件辅助 ----

static func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(RADIUS)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s

static func style_primary_button(btn: Button) -> void:
	var base := _btn_style(ACCENT, Color(0, 0, 0, 0))
	var hi := _btn_style(Color(0.949, 0.784, 0.435), Color(0, 0, 0, 0))
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hi)
	btn.add_theme_stylebox_override("pressed", base)
	btn.add_theme_stylebox_override("focus", hi)
	btn.add_theme_color_override("font_color", Color(0.094, 0.071, 0.024))
	btn.add_theme_color_override("font_hover_color", Color(0.094, 0.071, 0.024))

static func style_danger_button(btn: Button) -> void:
	var base := _btn_style(DOWN, Color(0, 0, 0, 0))
	var hi := _btn_style(Color(0.965, 0.5, 0.49), Color(0, 0, 0, 0))
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hi)
	btn.add_theme_stylebox_override("pressed", base)
	btn.add_theme_stylebox_override("focus", hi)
	btn.add_theme_color_override("font_color", Color(0.1, 0.03, 0.03))
	btn.add_theme_color_override("font_hover_color", Color(0.1, 0.03, 0.03))

static func style_flat_button(btn: Button) -> void:
	var base := _btn_style(Color(0, 0, 0, 0), CARD_BORDER)
	var hi := _btn_style(Color(1, 1, 1, 0.06), CARD_BORDER)
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", hi)
	btn.add_theme_stylebox_override("pressed", hi)
	btn.add_theme_stylebox_override("focus", hi)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)

static func chip_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = CARD_BG
	s.border_color = CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

static func style_option_button(ob: OptionButton) -> void:
	ob.add_theme_stylebox_override("normal", input_style())
	ob.add_theme_stylebox_override("hover", input_style())
	ob.add_theme_stylebox_override("pressed", input_style())
	ob.add_theme_stylebox_override("focus", input_style_focus())
	ob.add_theme_color_override("font_color", TEXT)
	ob.add_theme_color_override("font_hover_color", TEXT)
	var pop := ob.get_popup()
	style_popup_menu(pop)

static func style_popup_menu(pm: PopupMenu) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = WINDOW_BG
	panel.border_color = CARD_BORDER
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(RADIUS)
	panel.content_margin_left = 6
	panel.content_margin_right = 6
	panel.content_margin_top = 6
	panel.content_margin_bottom = 6
	pm.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = ACCENT_SOFT
	hover.set_corner_radius_all(6)
	pm.add_theme_stylebox_override("hover", hover)
	pm.add_theme_color_override("font_color", TEXT)
	pm.add_theme_color_override("font_hover_color", TEXT)
	pm.add_theme_color_override("font_separator_color", TEXT_MUTE)
	pm.add_theme_constant_override("v_separation", 3)

static func pill_style(tint: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(tint.r, tint.g, tint.b, 0.14)
	s.set_corner_radius_all(5)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s
