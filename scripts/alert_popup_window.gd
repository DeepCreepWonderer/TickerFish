extends Window
const UITheme := preload("res://scripts/ui_theme.gd")
## 单条提醒的 toast 窗口:无边框置顶、悬停暂停倒计时、点击关闭。


signal dismissed(popup)

const POPUP_LIFETIME := 8.0
const POPUP_SIZE := Vector2i(320, 80)

var _elapsed := 0.0
var _hovering := false

func _ready() -> void:
	borderless = true
	transparent = true
	unresizable = true
	unfocusable = true
	always_on_top = true
	exclusive = false
	size = POPUP_SIZE
	mouse_entered.connect(func(): _hovering = true)
	mouse_exited.connect(func(): _hovering = false)

func setup(record: Dictionary) -> void:
	_build_ui(record)

func _process(delta: float) -> void:
	if _hovering:
		return
	_elapsed += delta
	if _elapsed >= POPUP_LIFETIME:
		_dismiss()

func _dismiss() -> void:
	if not is_inside_tree():
		return
	dismissed.emit(self)
	queue_free()

func _build_ui(record: Dictionary) -> void:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	var bg: Color = UITheme.PANEL_CARD
	style.bg_color = Color(bg.r, bg.g, bg.b, 0.96)
	style.border_color = Color(0.96, 0.72, 0.26, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_input)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	var symbol: String = str(record.get("symbol", ""))
	var display_name: String = str(record.get("name", symbol))
	var title_label := Label.new()
	title_label.text = symbol if (display_name == "" or display_name == symbol) else "%s  %s" % [symbol, display_name]
	title_label.add_theme_font_size_override("font_size", UITheme.BODY)
	title_label.add_theme_color_override("font_color", UITheme.TEXT)
	title_label.clip_text = true
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_label)

	var price_v = record.get("price", null)
	var change_pct: float = float(record.get("change_pct", 0.0))
	var currency: String = str(record.get("currency", "USD"))
	var sign_str := "+" if change_pct >= 0 else ""
	var price_str := ("%.2f" % float(price_v)) if price_v != null else "—"

	var body := Label.new()
	body.text = "%s%s   %s%.2f%%" % [_currency_symbol(currency), price_str, sign_str, change_pct]
	body.add_theme_font_size_override("font_size", UITheme.TITLE)
	body.add_theme_color_override("font_color", UITheme.UP if change_pct >= 0 else UITheme.DOWN)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(body)

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss()

func _currency_symbol(c: String) -> String:
	match c:
		"USD", "USDT", "USDC", "FDUSD", "BUSD", "TUSD": return "$"
		"HKD": return "HK$"
		"JPY": return "¥"
		"CNY": return "¥"
		"KRW": return "₩"
		"EUR": return "€"
		"GBP": return "£"
		_: return ""
