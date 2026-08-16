extends AcceptDialog
const UITheme := preload("res://scripts/ui_theme.gd")
const TideToggle := preload("res://scripts/tide_toggle.gd")
## 编辑大卡对话框:命名组合 + 勾选该市场标的(≤5)。

signal saved(index: int, syms: Array, title: String, interval: int)

const CAP := 5
const INTERVAL_MIN := 2
const INTERVAL_MAX := 3600

var _index: int = -1
var _market: String = "stocks"
var _preset_syms: Array = []
var _preset_title: String = ""
var _preset_interval: int = 60

var _title_edit: LineEdit
var _interval_spin: SpinBox
var _search: LineEdit
var _list: VBoxContainer
var _checks: Array = []
var _hint: Label

func setup(index: int, market: String, syms: Array, card_title: String, interval: int) -> void:
	_index = index
	_market = market
	_preset_syms = syms.duplicate()
	_preset_title = card_title
	_preset_interval = interval

func _ready() -> void:
	title = Lang.t("hero_edit.title")
	get_ok_button().text = Lang.t("hero_edit.save")
	var cancel_btn := add_cancel_button(Lang.t("dialog.cancel"))
	_build_ui()
	UITheme.style_primary_button(get_ok_button())
	UITheme.style_flat_button(cancel_btn)
	confirmed.connect(_on_confirm)
	about_to_popup.connect(_on_about_to_popup)
	_on_toggle(false)

func _on_about_to_popup() -> void:
	var parent_ctrl := get_parent() as Control
	var w: int = 360
	if parent_ctrl != null:
		w = maxi(300, int(parent_ctrl.size.x) - 24)
	size = Vector2i(w, 0)

func _build_ui() -> void:
	var FONT_SIZE := UITheme.BODY
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	add_child(root)

	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	root.add_child(trow)
	var tlabel := Label.new()
	tlabel.text = Lang.t("hero_edit.name")
	tlabel.custom_minimum_size = Vector2(72, 0)
	tlabel.add_theme_font_size_override("font_size", FONT_SIZE)
	trow.add_child(tlabel)
	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = Lang.t("hero_edit.name_placeholder")
	_title_edit.text = _preset_title
	_title_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(_title_edit)
	trow.add_child(_title_edit)

	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 6)
	root.add_child(irow)
	var ilabel := Label.new()
	ilabel.text = Lang.t("hero_edit.interval")
	ilabel.custom_minimum_size = Vector2(72, 0)
	ilabel.add_theme_font_size_override("font_size", FONT_SIZE)
	irow.add_child(ilabel)
	_interval_spin = SpinBox.new()
	_interval_spin.min_value = INTERVAL_MIN
	_interval_spin.max_value = INTERVAL_MAX
	_interval_spin.step = 1
	_interval_spin.suffix = Lang.t("hero_edit.sec")
	_interval_spin.value = clampi(_preset_interval, INTERVAL_MIN, INTERVAL_MAX)
	_interval_spin.add_theme_font_size_override("font_size", FONT_SIZE)
	_interval_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_spinbox(_interval_spin)
	irow.add_child(_interval_spin)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", UITheme.HINT)
	_hint.modulate = UITheme.TEXT_DIM
	_hint.text = Lang.t("hero_edit.pick", {"max": CAP})
	root.add_child(_hint)

	var entries: Array = []
	if IdleSystem != null:
		for it in IdleSystem.get_numeric_list():
			if str(it.get("market", "stocks")) == _market:
				entries.append(it)

	if not entries.is_empty():
		_search = LineEdit.new()
		_search.placeholder_text = Lang.t("hero_edit.search")
		_search.add_theme_font_size_override("font_size", FONT_SIZE)
		_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search.clear_button_enabled = true
		UITheme.style_input(_search)
		_search.text_changed.connect(_on_search_changed)
		root.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_list = list

	if entries.is_empty():
		var empty := Label.new()
		empty.text = Lang.t("hero_edit.empty")
		empty.add_theme_font_size_override("font_size", FONT_SIZE)
		empty.modulate = UITheme.TEXT_DIM
		list.add_child(empty)
	list.add_theme_constant_override("separation", 7)
	for it in entries:
		var sym := str(it.get("symbol", ""))
		var nick := str(it.get("nickname", ""))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _row_card_style())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var namebox := VBoxContainer.new()
		namebox.add_theme_constant_override("separation", 1)
		namebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		namebox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(namebox)
		var sym_lbl := Label.new()
		sym_lbl.text = sym
		sym_lbl.add_theme_font_size_override("font_size", UITheme.BODY)
		sym_lbl.add_theme_font_override("font", UITheme.sans_bold())
		sym_lbl.add_theme_color_override("font_color", UITheme.TEXT)
		namebox.add_child(sym_lbl)
		if nick != "" and nick != sym:
			var nm := Label.new()
			nm.text = nick
			nm.add_theme_font_size_override("font_size", UITheme.HINT)
			nm.modulate = UITheme.TEXT_DIM
			namebox.add_child(nm)
		var tog := TideToggle.new()
		tog.button_pressed = sym in _preset_syms
		tog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tog.toggled.connect(_on_toggle)
		row.add_child(tog)
		_checks.append({"sym": sym, "nick": nick, "tog": tog, "card": card})

	var ordered: Array = []
	for s in _preset_syms:
		for c in _checks:
			if c["sym"] == str(s) and not (c in ordered):
				ordered.append(c)
	for c in _checks:
		if not (c in ordered):
			ordered.append(c)
	_checks = ordered
	_apply_order()

func _apply_order() -> void:
	if _list == null:
		return
	for i in range(_checks.size()):
		_list.move_child(_checks[i]["card"], i)

func _resort_checked_first() -> void:
	var checked: Array = []
	var unchecked: Array = []
	for c in _checks:
		if c["tog"].button_pressed:
			checked.append(c)
		else:
			unchecked.append(c)
	_checks = checked + unchecked
	_apply_order()

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

func _on_search_changed(q: String) -> void:
	var query := q.strip_edges().to_lower()
	for c in _checks:
		var hay: String = (str(c["sym"]) + " " + str(c["nick"])).to_lower()
		c["card"].visible = query == "" or c["tog"].button_pressed or hay.contains(query)

func _on_toggle(_pressed: bool) -> void:
	var n := 0
	for c in _checks:
		if c["tog"].button_pressed:
			n += 1
	if n > CAP:
		_hint.text = Lang.t("hero_edit.too_many", {"max": CAP})
		_hint.modulate = UITheme.WARN
	else:
		_hint.text = Lang.t("hero_edit.pick", {"max": CAP})
		_hint.modulate = UITheme.TEXT_DIM
	get_ok_button().disabled = n > CAP
	_resort_checked_first()

func _on_confirm() -> void:
	var syms: Array = []
	for c in _checks:
		if c["tog"].button_pressed:
			syms.append(c["sym"])
	if syms.size() > CAP:
		return
	var iv: int = int(_interval_spin.value) if _interval_spin != null else 60
	saved.emit(_index, syms, _title_edit.text.strip_edges(), iv)
