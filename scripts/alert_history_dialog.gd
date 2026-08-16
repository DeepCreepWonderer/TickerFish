extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## 价格提醒历史面板:按日期分组、可按代码筛选;打开即标记全部已读。


signal confirmed


var _symbol_filter: String = ""
var _list_box: VBoxContainer = null

func _ready() -> void:
	title = Lang.t("alert_history.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()
	if IdleSystem != null:
		IdleSystem.mark_all_alerts_read()
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

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(root)

	var head := Label.new()
	head.text = Lang.t("alert_history.title")
	head.add_theme_font_size_override("font_size", UITheme.TITLE)
	head.add_theme_font_override("font", UITheme.sans_bold())
	head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(head)

	var sub := Label.new()
	sub.text = Lang.t("alert_history.subtitle")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", UITheme.HINT)
	sub.modulate = UITheme.TEXT_DIM
	root.add_child(sub)

	var history: Array = IdleSystem.get_alert_history() if IdleSystem != null else []

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	root.add_child(filter_row)

	var filter_label := Label.new()
	filter_label.text = Lang.t("alert_history.filter")
	filter_label.add_theme_font_size_override("font_size", UITheme.BODY)
	filter_row.add_child(filter_label)

	var filter_btn := OptionButton.new()
	filter_btn.add_theme_font_size_override("font_size", UITheme.BODY)
	filter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_option_button(filter_btn)
	var symbols := _unique_symbols(history)
	filter_btn.add_item(Lang.t("alert_history.filter_all"))
	for s in symbols:
		filter_btn.add_item(s)
	filter_btn.selected = 0
	filter_btn.item_selected.connect(_on_filter_selected)
	filter_row.add_child(filter_btn)

	root.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 5)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	_rebuild_list(history)

func _unique_symbols(history: Array) -> Array:
	var seen := {}
	var out: Array = []
	for r in history:
		var s: String = str(r.get("symbol", ""))
		if s != "" and not seen.has(s):
			seen[s] = true
			out.append(s)
	out.sort()
	return out

func _on_filter_selected(index: int) -> void:
	var full: Array = IdleSystem.get_alert_history() if IdleSystem != null else []
	if index <= 0:
		_symbol_filter = ""
	else:
		var symbols := _unique_symbols(full)
		_symbol_filter = symbols[index - 1] if (index - 1) < symbols.size() else ""
	_rebuild_list(full)

func _rebuild_list(history: Array) -> void:
	for c in _list_box.get_children():
		c.queue_free()

	var filtered: Array = []
	for r in history:
		if _symbol_filter == "" or str(r.get("symbol", "")) == _symbol_filter:
			filtered.append(r)

	if filtered.is_empty():
		var empty := Label.new()
		empty.text = Lang.t("alert_history.empty")
		empty.add_theme_font_size_override("font_size", UITheme.BODY)
		empty.modulate = UITheme.TEXT_MUTE
		_list_box.add_child(empty)
		return

	var last_date := ""
	for r in filtered:
		var date_str := _date_of(r)
		if date_str != last_date:
			last_date = date_str
			var header := Label.new()
			header.text = date_str
			header.add_theme_font_size_override("font_size", UITheme.HINT)
			header.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			var mc := MarginContainer.new()
			mc.add_theme_constant_override("margin_top", 6)
			mc.add_theme_constant_override("margin_left", 2)
			mc.add_child(header)
			_list_box.add_child(mc)
		_build_row(r)

func _date_of(record: Dictionary) -> String:
	var dt: String = str(record.get("data_time", ""))
	if dt.length() >= 10:
		return dt.substr(0, 10)
	return Lang.t("alert_history.unknown_date")

func _build_row(record: Dictionary) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var dt: String = str(record.get("data_time", ""))
	var time_str := dt.substr(11, 5) if dt.length() >= 16 else ""
	var time_label := Label.new()
	time_label.text = time_str
	time_label.add_theme_font_override("font", UITheme.mono())
	time_label.add_theme_font_size_override("font_size", UITheme.HINT)
	time_label.modulate = UITheme.TEXT_MUTE
	time_label.custom_minimum_size = Vector2(42, 0)
	time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(time_label)

	var symbol: String = str(record.get("symbol", ""))
	var display_name: String = str(record.get("name", symbol))
	var namebox := VBoxContainer.new()
	namebox.add_theme_constant_override("separation", 1)
	namebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	namebox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(namebox)
	var sym_label := Label.new()
	sym_label.text = symbol
	sym_label.add_theme_font_override("font", UITheme.sans_bold())
	sym_label.add_theme_font_size_override("font_size", UITheme.BODY)
	sym_label.add_theme_color_override("font_color", UITheme.TEXT)
	sym_label.clip_text = true
	namebox.add_child(sym_label)
	if display_name != "" and display_name != symbol:
		var nm := Label.new()
		nm.text = display_name
		nm.add_theme_font_size_override("font_size", UITheme.HINT)
		nm.modulate = UITheme.TEXT_DIM
		nm.clip_text = true
		namebox.add_child(nm)

	var change_pct: float = float(record.get("change_pct", 0.0))
	var col: Color = UITheme.UP if change_pct >= 0 else UITheme.DOWN
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UITheme.pill_style(col))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	var pct_label := Label.new()
	pct_label.text = "%s%.2f%%" % ["+" if change_pct >= 0 else "", change_pct]
	pct_label.add_theme_font_override("font", UITheme.mono())
	pct_label.add_theme_font_size_override("font_size", UITheme.HINT)
	pct_label.add_theme_color_override("font_color", col)
	pill.add_child(pct_label)

func _row_card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.04)
	s.border_color = UITheme.CARD_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _on_close_requested() -> void:
	confirmed.emit()
	hide()
