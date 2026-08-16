extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
const TideToggle := preload("res://scripts/tide_toggle.gd")
## 价格提醒设置:搜索选一只标的,设当日涨跌幅 ±% 阈值 + 开关,直写 IdleSystem。

signal confirmed


var _entries: Array = []
var _ticker_btns: Array = []
var _selected_key: String = ""
var _selected_label: String = ""
var _loaded_threshold: float = 3.0
var _loaded_enabled: bool = false
var _pending: Dictionary = {}
var _picking: bool = false
var _search: LineEdit
var _list_panel: PanelContainer
var _spin: SpinBox
var _toggle: TideToggle
var _config_box: VBoxContainer
var _master_toggle: TideToggle
var _off_hint: Label
var _none_enabled_hint: Label
var _scroll_main: ScrollContainer
var _foot: HBoxContainer
var _sub_label: Label

func _ready() -> void:
	title = Lang.t("alert.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()
	if IdleSystem != null:
		IdleSystem.prune_orphan_alert_configs()
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
	root.add_theme_constant_override("separation", UITheme.GAP + 2)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(root)

	var head := Label.new()
	head.text = Lang.t("alert.title")
	head.add_theme_font_size_override("font_size", UITheme.TITLE)
	head.add_theme_font_override("font", UITheme.sans_bold())
	head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(head)

	_sub_label = Label.new()
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_font_size_override("font_size", UITheme.HINT)
	_sub_label.modulate = UITheme.TEXT_DIM
	root.add_child(_sub_label)

	var master_card := PanelContainer.new()
	master_card.add_theme_stylebox_override("panel", _row_card_style())
	root.add_child(master_card)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	master_card.add_child(mrow)
	var mlbl := Label.new()
	mlbl.text = Lang.t("alert.master_enable")
	mlbl.add_theme_font_size_override("font_size", UITheme.BODY)
	mlbl.add_theme_color_override("font_color", UITheme.TEXT)
	mlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mlbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(mlbl)
	_master_toggle = TideToggle.new()
	_master_toggle.button_pressed = IdleSystem.get_alerts_enabled() if IdleSystem != null else false
	_master_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_master_toggle.toggled.connect(_on_master_toggled)
	mrow.add_child(_master_toggle)

	_off_hint = Label.new()
	_off_hint.text = Lang.t("alert.master_off_hint")
	_off_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_off_hint.custom_minimum_size = Vector2(240, 0)
	_off_hint.add_theme_font_size_override("font_size", UITheme.HINT)
	_off_hint.modulate = UITheme.TEXT_MUTE
	root.add_child(_off_hint)

	_none_enabled_hint = Label.new()
	_none_enabled_hint.text = Lang.t("alert.none_enabled_hint")
	_none_enabled_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_none_enabled_hint.custom_minimum_size = Vector2(240, 0)
	_none_enabled_hint.add_theme_font_size_override("font_size", UITheme.HINT)
	_none_enabled_hint.modulate = UITheme.WARN
	root.add_child(_none_enabled_hint)

	_entries = IdleSystem.get_all_watchlist_entries() if IdleSystem != null else []
	if _entries.is_empty():
		_refresh_hints()
		_none_enabled_hint.visible = false
		var empty := Label.new()
		empty.text = Lang.t("alert.no_tickers")
		empty.add_theme_font_size_override("font_size", UITheme.BODY)
		empty.modulate = UITheme.TEXT_MUTE
		root.add_child(empty)
		return

	var scroll_main := ScrollContainer.new()
	scroll_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_main.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll_main)
	_scroll_main = scroll_main
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP + 2)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_main.add_child(body)

	# ---- 标的:搜索 + 可选列表 ----
	body.add_child(_section_label(Lang.t("alert.ticker")))
	_search = LineEdit.new()
	_search.placeholder_text = Lang.t("common.search_ticker")
	_search.add_theme_font_size_override("font_size", UITheme.BODY)
	UITheme.style_input(_search)
	_search.text_changed.connect(_on_search_changed)
	_search.focus_entered.connect(_on_search_focus)
	_search.focus_exited.connect(func(): call_deferred("_maybe_close_list"))
	body.add_child(_search)

	_list_panel = PanelContainer.new()
	_list_panel.add_theme_stylebox_override("panel", _dropdown_style())
	_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_panel.visible = false
	body.add_child(_list_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_panel.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)
	for e in _entries:
		_build_ticker_btn(list_box, e)

	# ---- 选中标的的配置 ----
	_config_box = VBoxContainer.new()
	_config_box.add_theme_constant_override("separation", UITheme.GAP)
	body.add_child(_config_box)

	_config_box.add_child(_section_label(Lang.t("alert.threshold")))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	_config_box.add_child(trow)
	var pm := Label.new()
	pm.text = "±"
	pm.add_theme_font_size_override("font_size", UITheme.TITLE)
	pm.modulate = UITheme.TEXT_DIM
	pm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(pm)
	_spin = SpinBox.new()
	_spin.min_value = 0.5
	_spin.max_value = 50.0
	_spin.step = 0.5
	_spin.value = 3.0
	_spin.suffix = "%"
	_spin.add_theme_font_size_override("font_size", UITheme.BODY)
	_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_spinbox(_spin)
	trow.add_child(_spin)

	var enable_card := PanelContainer.new()
	enable_card.add_theme_stylebox_override("panel", _row_card_style())
	_config_box.add_child(enable_card)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 8)
	enable_card.add_child(erow)
	var elbl := Label.new()
	elbl.text = Lang.t("alert.enable_this")
	elbl.add_theme_font_size_override("font_size", UITheme.BODY)
	elbl.add_theme_color_override("font_color", UITheme.TEXT)
	elbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	erow.add_child(elbl)
	_toggle = TideToggle.new()
	_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toggle.toggled.connect(func(_on): _refresh_hints())
	erow.add_child(_toggle)

	# ---- 底部按钮 ----
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(foot)
	_foot = foot
	var cancel_btn := Button.new()
	cancel_btn.text = Lang.t("dialog.cancel")
	UITheme.style_flat_button(cancel_btn)
	cancel_btn.pressed.connect(_on_cancel)
	foot.add_child(cancel_btn)
	var save_btn := Button.new()
	save_btn.text = Lang.t("settings.save")
	UITheme.style_primary_button(save_btn)
	save_btn.pressed.connect(_on_save)
	foot.add_child(save_btn)

	_select_entry(_entries[0])
	_apply_master_state()

func _on_master_toggled(on: bool) -> void:
	if IdleSystem != null:
		IdleSystem.save_alerts_enabled(on)
	_apply_master_state()

func _apply_master_state() -> void:
	var on: bool = _master_toggle != null and _master_toggle.button_pressed
	if _scroll_main != null:
		_scroll_main.visible = on
	if _foot != null:
		_foot.visible = on
	_refresh_hints()

func _refresh_hints() -> void:
	var on: bool = _master_toggle != null and _master_toggle.button_pressed
	if _sub_label != null:
		_sub_label.text = Lang.t("alert.subtitle") if on else Lang.t("alert.subtitle_off")
	if _off_hint != null:
		_off_hint.visible = not on
	if _none_enabled_hint != null:
		_none_enabled_hint.visible = on and not _any_ticker_enabled()

func _any_ticker_enabled() -> bool:
	if _toggle != null and _toggle.button_pressed:
		return true
	if IdleSystem == null:
		return false
	for e in _entries:
		var key: String = str(e.get("market", "")) + ":" + str(e.get("symbol", ""))
		if key == _selected_key:
			continue
		if _pending.has(key):
			if bool((_pending[key] as Dictionary).get("enabled", false)):
				return true
			continue
		if IdleSystem.get_alert_config(key).get("enabled", false):
			return true
	return false

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.HINT)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

func _build_ticker_btn(list_box: VBoxContainer, entry: Dictionary) -> void:
	var market: String = str(entry.get("market", ""))
	var symbol: String = str(entry.get("symbol", ""))
	var disp_name: String = str(entry.get("name", symbol))
	var key: String = market + ":" + symbol
	var b := Button.new()
	b.text = symbol if (disp_name == "" or disp_name == symbol) else (symbol + "   " + disp_name)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", UITheme.BODY)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_ticker_btn(b, false)
	b.button_down.connect(func(): _picking = true)
	b.pressed.connect(_select_entry.bind(entry))
	list_box.add_child(b)
	_ticker_btns.append({"btn": b, "key": key, "text": (symbol + " " + disp_name).to_lower()})

func _style_ticker_btn(b: Button, on: bool) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.ACCENT_SOFT if on else Color(0, 0, 0, 0)
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	var h := s.duplicate()
	h.bg_color = UITheme.ACCENT_SOFT if on else Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("focus", s)
	var col: Color = UITheme.ACCENT if on else UITheme.TEXT
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)

func _select_entry(entry: Dictionary) -> void:
	var market: String = str(entry.get("market", ""))
	var symbol: String = str(entry.get("symbol", ""))
	var disp_name: String = str(entry.get("name", symbol))
	var key: String = market + ":" + symbol
	if _selected_key != "" and _selected_key != key:
		_stash(_selected_key)
	_selected_key = key
	_selected_label = symbol if (disp_name == "" or disp_name == symbol) else (symbol + "  ·  " + disp_name)
	for r in _ticker_btns:
		_style_ticker_btn(r["btn"], r["key"] == key)
	var cfg: Dictionary = IdleSystem.get_alert_config(key) if IdleSystem != null else {}
	if _pending.has(key):
		cfg = _pending[key]
	_loaded_threshold = float(cfg.get("threshold", 3.0))
	_loaded_enabled = bool(cfg.get("enabled", false))
	_spin.value = _loaded_threshold
	_toggle.button_pressed = _loaded_enabled
	_search.text = _selected_label
	_picking = false
	_close_list()
	_search.release_focus()

func _stash(key: String) -> void:
	if key == "" or _spin == null or _toggle == null:
		return
	if is_equal_approx(_spin.value, _loaded_threshold) and _toggle.button_pressed == _loaded_enabled:
		return
	_pending[key] = {"threshold": _spin.value, "enabled": _toggle.button_pressed}

func _flush() -> void:
	if IdleSystem == null:
		_pending.clear()
		return
	for key in _pending:
		var c: Dictionary = _pending[key]
		IdleSystem.set_alert_config(str(key), float(c.get("threshold", 3.0)), bool(c.get("enabled", false)))
	_pending.clear()

func _input(event: InputEvent) -> void:
	if _list_panel == null or not _list_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var p: Vector2 = event.position
		if not _search.get_global_rect().has_point(p) and not _list_panel.get_global_rect().has_point(p):
			_close_list()
			_search.text = _selected_label
			_search.release_focus()

func _on_search_focus() -> void:
	_search.text = ""
	_filter_list("")
	_list_panel.visible = true

func _on_search_changed(q: String) -> void:
	_filter_list(q)
	_list_panel.visible = true

func _filter_list(q: String) -> void:
	var query := q.strip_edges().to_lower()
	for r in _ticker_btns:
		r["btn"].visible = query == "" or str(r["text"]).contains(query)

func _close_list() -> void:
	if _list_panel != null:
		_list_panel.visible = false

func _maybe_close_list() -> void:
	if _picking:
		return
	_close_list()
	_search.text = _selected_label

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

func _on_save() -> void:
	_stash(_selected_key)
	_flush()
	confirmed.emit()
	hide()

func _on_cancel() -> void:
	_pending.clear()
	confirmed.emit()
	hide()

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

func _on_close_requested() -> void:
	_stash(_selected_key)
	_flush()
	confirmed.emit()
	hide()
