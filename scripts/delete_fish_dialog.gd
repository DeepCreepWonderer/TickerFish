extends AcceptDialog
const UITheme := preload("res://scripts/ui_theme.gd")
const TideCheck := preload("res://scripts/tide_check.gd")
## 批量删除股票/加密货币对话框:选市场,勾选已有代码,一次性删除。

signal tickers_deleted(ids: Array)

const DIALOG_W := 380

var _current_market: String = "stocks"
var _entries: Array = []
var _checks: Array = []

var _search: LineEdit
var _list: VBoxContainer
var _tab_stocks: Button
var _tab_crypto: Button

func setup(market: String, entries: Array) -> void:
	_current_market = "crypto" if market == "crypto" else "stocks"
	_entries = entries

func _ready() -> void:
	title = Lang.t("delete_stock.title")
	get_ok_button().text = Lang.t("delete_stock.delete")
	var cancel_btn := add_cancel_button(Lang.t("dialog.cancel"))
	UITheme.style_dialog(self)
	_build_ui()
	UITheme.style_danger_button(get_ok_button())
	UITheme.style_flat_button(cancel_btn)
	confirmed.connect(_on_confirm)
	wrap_controls = true
	var sh := DisplayServer.screen_get_size(get_tree().root.current_screen)
	min_size = Vector2i(DIALOG_W, 0)
	max_size = Vector2i(DIALOG_W, int(sh.y * 0.85))

func popup_centered_on_parent() -> void:
	reset_size()
	popup_centered()

func _build_ui() -> void:
	var FONT_SIZE := UITheme.BODY
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP + 3)
	add_child(root)

	var head := Label.new()
	head.text = Lang.t("delete_stock.title")
	head.add_theme_font_size_override("font_size", UITheme.TITLE)
	head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(head)

	var sub := Label.new()
	sub.text = Lang.t("delete_stock.subtitle")
	sub.add_theme_font_size_override("font_size", UITheme.HINT)
	sub.modulate = UITheme.TEXT_DIM
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(DIALOG_W - 40, 0)
	root.add_child(sub)

	var market_sec := _section(root, Lang.t("create_fish.market"))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 18)
	market_sec.add_child(tabs)
	_tab_stocks = _make_tab(Lang.t("about.market.stocks"))
	_tab_crypto = _make_tab(Lang.t("about.market.crypto"))
	_tab_stocks.pressed.connect(_select_market.bind("stocks"))
	_tab_crypto.pressed.connect(_select_market.bind("crypto"))
	tabs.add_child(_tab_stocks)
	tabs.add_child(_tab_crypto)
	_update_market_tabs()

	var code_sec := _section(root, Lang.t("create_fish.symbol"))
	_search = LineEdit.new()
	_search.placeholder_text = Lang.t("hero_edit.search")
	_search.add_theme_font_size_override("font_size", FONT_SIZE)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	UITheme.style_input(_search)
	_search.text_changed.connect(_on_search_changed)
	code_sec.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 168)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_sec.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_rebuild_list()

func _section(parent: Control, section_title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var lbl := Label.new()
	lbl.text = section_title.replace(":", "").replace("：", "")
	lbl.add_theme_font_size_override("font_size", UITheme.HINT)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(lbl)
	return box

func _make_tab(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UITheme.BODY)
	b.focus_mode = Control.FOCUS_NONE
	return b

func _tab_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = UITheme.ACCENT if active else Color(0, 0, 0, 0)
	s.border_width_bottom = 2
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _update_market_tabs() -> void:
	var pairs := [[_tab_stocks, _current_market == "stocks"], [_tab_crypto, _current_market == "crypto"]]
	for pair in pairs:
		var b: Button = pair[0]
		var on: bool = pair[1]
		b.add_theme_stylebox_override("normal", _tab_style(on))
		b.add_theme_stylebox_override("hover", _tab_style(on))
		b.add_theme_stylebox_override("pressed", _tab_style(on))
		b.add_theme_color_override("font_color", UITheme.TEXT if on else UITheme.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", UITheme.TEXT)

func _select_market(market: String) -> void:
	if market == _current_market:
		return
	_current_market = market
	if IdleSystem != null:
		IdleSystem.set_selected_market(market)
	if _search != null:
		_search.text = ""
	_update_market_tabs()
	_rebuild_list()

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.add_theme_constant_override("separation", 7)
	_checks.clear()
	var any := false
	for it in _entries:
		if str(it.get("market", "stocks")) != _current_market:
			continue
		any = true
		var sym := str(it.get("symbol", ""))
		var nick := str(it.get("nickname", ""))
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _row_card_style())
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var chk := TideCheck.new()
		chk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chk)
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
		_checks.append({"id": str(it.get("id", "")), "sym": sym, "nick": nick, "tog": chk, "card": card})
	if not any:
		var empty := Label.new()
		empty.text = Lang.t("hero_edit.empty")
		empty.add_theme_font_size_override("font_size", UITheme.BODY)
		empty.modulate = UITheme.TEXT_DIM
		_list.add_child(empty)

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

func _on_confirm() -> void:
	var ids: Array = []
	for c in _checks:
		if c["tog"].button_pressed:
			ids.append(c["id"])
	if not ids.is_empty():
		tickers_deleted.emit(ids)
	queue_free()
