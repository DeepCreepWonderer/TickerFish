extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
const TideToggle := preload("res://scripts/tide_toggle.gd")
## 价格记录设置:总开关、采样间隔、搜索选择记录哪些标的(多选)。

signal confirmed


var _interval_dropdown: OptionButton
var _enable_check: BaseButton
var _rows: Array = []
var _search: LineEdit
var _list_panel: PanelContainer
var _chips_box: HFlowContainer
var _chips_hint: Label
var _picking: bool = false
var _entries: Array = []

func _ready() -> void:
	title = Lang.t("price_rec.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()
	_build_ui()


func _build_ui() -> void:
	add_child(UITheme.bg_panel())
	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", UITheme.PAD)
	outer.add_theme_constant_override("margin_right", UITheme.PAD)
	outer.add_theme_constant_override("margin_top", UITheme.PAD)
	outer.add_theme_constant_override("margin_bottom", UITheme.PAD)
	outer.anchor_right = 1.0
	outer.anchor_bottom = 1.0
	add_child(outer)

	var scroll_main := ScrollContainer.new()
	scroll_main.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_main.anchor_right = 1.0
	scroll_main.anchor_bottom = 1.0
	outer.add_child(scroll_main)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_main.add_child(root)

	var enable_card := PanelContainer.new()
	enable_card.add_theme_stylebox_override("panel", _row_card_style())
	enable_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(enable_card)
	var enable_row := HBoxContainer.new()
	enable_row.add_theme_constant_override("separation", 8)
	enable_card.add_child(enable_row)
	var enable_lbl := Label.new()
	enable_lbl.text = Lang.t("price_rec.enable")
	enable_lbl.add_theme_font_size_override("font_size", UITheme.BODY)
	enable_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	enable_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enable_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enable_row.add_child(enable_lbl)
	_enable_check = TideToggle.new()
	_enable_check.button_pressed = IdleSystem.get_price_stream_enabled()
	_enable_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_enable_check.toggled.connect(_on_enable_toggled)
	enable_row.add_child(_enable_check)

	var interval_row := HBoxContainer.new()
	interval_row.add_theme_constant_override("separation", 6)
	root.add_child(interval_row)
	var interval_label := Label.new()
	interval_label.text = Lang.t("price_rec.interval")
	interval_label.add_theme_font_size_override("font_size", UITheme.BODY)
	interval_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	interval_row.add_child(interval_label)
	_interval_dropdown = OptionButton.new()
	_interval_dropdown.add_theme_font_size_override("font_size", UITheme.BODY)
	_interval_dropdown.get_popup().add_theme_font_size_override("font_size", UITheme.BODY)
	_interval_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_option_button(_interval_dropdown)
	var intervals := [15, 30, 60]
	var current_iv: int = IdleSystem.get_price_stream_interval_min()
	for i in range(intervals.size()):
		var mins: int = intervals[i]
		_interval_dropdown.add_item(Lang.t("price_rec.minutes", {"n": mins}), mins)
		if mins == current_iv:
			_interval_dropdown.select(i)
	_interval_dropdown.item_selected.connect(_on_interval_selected)
	interval_row.add_child(_interval_dropdown)

	root.add_child(HSeparator.new())

	var list_header := Label.new()
	list_header.text = Lang.t("price_rec.tickers_header")
	list_header.add_theme_font_size_override("font_size", UITheme.HINT)
	list_header.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(list_header)

	_entries = IdleSystem.get_all_watchlist_entries()
	if _entries.is_empty():
		var empty := Label.new()
		empty.text = Lang.t("price_rec.no_tickers")
		empty.add_theme_font_size_override("font_size", UITheme.BODY)
		empty.modulate = UITheme.TEXT_MUTE
		root.add_child(empty)
	else:
		_search = LineEdit.new()
		_search.placeholder_text = Lang.t("common.search_ticker")
		_search.add_theme_font_size_override("font_size", UITheme.BODY)
		UITheme.style_input(_search)
		_search.text_changed.connect(_on_search_changed)
		_search.focus_entered.connect(_on_search_focus)
		_search.focus_exited.connect(func(): call_deferred("_maybe_close_list"))
		root.add_child(_search)

		_chips_box = HFlowContainer.new()
		_chips_box.add_theme_constant_override("h_separation", 6)
		_chips_box.add_theme_constant_override("v_separation", 6)
		root.add_child(_chips_box)
		_chips_hint = Label.new()
		_chips_hint.text = Lang.t("price_rec.none_selected")
		_chips_hint.add_theme_font_size_override("font_size", UITheme.HINT)
		_chips_hint.modulate = UITheme.TEXT_MUTE
		_chips_box.add_child(_chips_hint)

		_list_panel = PanelContainer.new()
		_list_panel.add_theme_stylebox_override("panel", _dropdown_style())
		_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_panel.visible = false
		root.add_child(_list_panel)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 160)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_list_panel.add_child(scroll)
		var list_box := VBoxContainer.new()
		list_box.add_theme_constant_override("separation", 5)
		list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list_box)
		for e in _entries:
			var market: String = str(e.get("market", ""))
			var symbol: String = str(e.get("symbol", ""))
			var disp_name: String = str(e.get("name", symbol))
			var key: String = market + ":" + symbol
			_build_ticker_row(list_box, symbol, disp_name, key)
		_refresh_chips()

	root.add_child(HSeparator.new())

	var note := Label.new()
	note.text = Lang.t("price_rec.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", UITheme.HINT)
	note.add_theme_constant_override("line_spacing", UITheme.LINE)
	note.modulate = UITheme.TEXT_MUTE
	root.add_child(note)

func _build_ticker_row(list_box: VBoxContainer, symbol: String, disp_name: String, key: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var namebox := VBoxContainer.new()
	namebox.add_theme_constant_override("separation", 1)
	namebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	namebox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(namebox)
	var sym_lbl := Label.new()
	sym_lbl.text = symbol
	sym_lbl.add_theme_font_size_override("font_size", UITheme.BODY)
	sym_lbl.add_theme_font_override("font", UITheme.sans_bold())
	sym_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	namebox.add_child(sym_lbl)
	if disp_name != "" and disp_name != symbol:
		var nm := Label.new()
		nm.text = disp_name
		nm.add_theme_font_size_override("font_size", UITheme.HINT)
		nm.modulate = UITheme.TEXT_DIM
		namebox.add_child(nm)
	var tog := TideToggle.new()
	tog.button_pressed = IdleSystem.is_symbol_recorded(key)
	tog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tog.button_down.connect(func(): _picking = true)
	tog.toggled.connect(_on_ticker_toggled.bind(key))
	row.add_child(tog)
	_rows.append({"card": card, "tog": tog, "key": key, "symbol": symbol, "text": (symbol + " " + disp_name).to_lower()})

func _refresh_chips() -> void:
	if _chips_box == null:
		return
	for c in _chips_box.get_children():
		if c != _chips_hint:
			c.queue_free()
	var any := false
	for r in _rows:
		if r["tog"].button_pressed:
			any = true
			_chips_box.add_child(_make_chip(r))
	_chips_hint.visible = not any

func _make_chip(r: Dictionary) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.chip_style())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	chip.add_child(h)
	var l := Label.new()
	l.text = str(r["symbol"])
	l.add_theme_font_size_override("font_size", UITheme.HINT)
	l.add_theme_color_override("font_color", UITheme.TEXT)
	h.add_child(l)
	var x := Button.new()
	x.text = "✕"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", UITheme.HINT)
	x.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	x.add_theme_color_override("font_hover_color", UITheme.DOWN)
	x.pressed.connect(func(): r["tog"].button_pressed = false)
	h.add_child(x)
	return chip

func _input(event: InputEvent) -> void:
	if _list_panel == null or not _list_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		if not _search.get_global_rect().has_point(p) and not _list_panel.get_global_rect().has_point(p):
			_close_list()

func _on_search_focus() -> void:
	_filter_list(_search.text)
	_list_panel.visible = true

func _on_search_changed(q: String) -> void:
	_filter_list(q)
	_list_panel.visible = true

func _filter_list(q: String) -> void:
	var query := q.strip_edges().to_lower()
	for r in _rows:
		r["card"].visible = query == "" or str(r["text"]).contains(query)

func _close_list() -> void:
	if _list_panel != null:
		_list_panel.visible = false

func _maybe_close_list() -> void:
	if _picking:
		_picking = false
		return
	_close_list()

func _row_card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.04)
	s.border_color = UITheme.CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 10
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s

func _dropdown_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.WINDOW_BG
	s.border_color = UITheme.CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(UITheme.RADIUS)
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s

func _on_enable_toggled(on: bool) -> void:
	IdleSystem.save_price_stream_enabled(on)

func _on_interval_selected(index: int) -> void:
	var mins: int = _interval_dropdown.get_item_id(index)
	IdleSystem.save_price_stream_interval_min(mins)

func _on_ticker_toggled(recorded: bool, key: String) -> void:
	IdleSystem.set_symbol_recorded(key, recorded)
	_refresh_chips()

func _on_close_requested() -> void:
	confirmed.emit()
	hide()
