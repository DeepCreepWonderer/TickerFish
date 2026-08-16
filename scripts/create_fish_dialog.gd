extends AcceptDialog
const UITheme := preload("res://scripts/ui_theme.gd")
## 批量添加股票/加密货币对话框:选市场,逐个搜索/输入加入列表,一次性提交。

signal tickers_committed(market: String, symbols: Array, design: int, species: String)

const SearchDialogScript := preload("res://scripts/search_ticker_dialog.gd")
const DIALOG_W := 380

var _current_market: String = "stocks"
var _hide_species: bool = false
var _pending: Array = []

var _symbol_edit: LineEdit
var _search_btn: Button
var _add_btn: Button
var _list: HFlowContainer
var _tab_stocks: Button
var _tab_crypto: Button
var _show_design: bool = false
var _selected_design: int = -1
var _design_tabs: Array = []
var _show_species: bool = false
var _selected_species: String = ""
var _active_search_dialog: AcceptDialog = null
var _limit_label: Label = null

func set_hide_species(hide_species: bool) -> void:
	_hide_species = hide_species

func set_show_design(v: bool) -> void:
	_show_design = v

func set_show_species(v: bool) -> void:
	_show_species = v

func _ready() -> void:
	if _hide_species:
		title = Lang.t("create_stock.title")
		get_ok_button().text = Lang.t("create_stock.create")
	else:
		title = Lang.t("create_fish.title")
		get_ok_button().text = Lang.t("create_fish.create")
	var cancel_btn := add_cancel_button(Lang.t("dialog.cancel"))
	UITheme.style_dialog(self)
	_build_ui()
	UITheme.style_primary_button(get_ok_button())
	UITheme.style_flat_button(cancel_btn)
	confirmed.connect(_on_confirm)
	wrap_controls = true
	var sh := DisplayServer.screen_get_size(get_tree().root.current_screen)
	min_size = Vector2i(DIALOG_W, 0)
	max_size = Vector2i(DIALOG_W, int(sh.y * 0.85))

func popup_centered_on_parent() -> void:
	var full: bool = IdleSystem != null and IdleSystem.is_global_limit_reached()
	if _limit_label != null:
		_limit_label.visible = full
		if full:
			_limit_label.text = Lang.t("create_fish.global_limit", {"max": IdleSystem.MAX_TOTAL_SYMBOLS})
	reset_size()
	popup_centered()

func _build_ui() -> void:
	var FONT_SIZE := UITheme.BODY
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP + 3)
	add_child(root)

	var head := Label.new()
	head.text = Lang.t("create_stock.title") if _hide_species else Lang.t("create_fish.title")
	head.add_theme_font_size_override("font_size", UITheme.TITLE)
	head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(head)

	var sub := Label.new()
	sub.text = Lang.t("create_fish.subtitle")
	sub.add_theme_font_size_override("font_size", UITheme.HINT)
	sub.modulate = UITheme.TEXT_DIM
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(DIALOG_W - 40, 0)
	root.add_child(sub)

	_limit_label = Label.new()
	_limit_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_limit_label.add_theme_constant_override("line_spacing", UITheme.LINE)
	_limit_label.modulate = UITheme.WARN
	_limit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_limit_label.custom_minimum_size = Vector2(DIALOG_W - 40, 0)
	_limit_label.visible = false
	root.add_child(_limit_label)

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
	_current_market = IdleSystem.get_context_market() if IdleSystem != null else "stocks"
	_update_market_tabs()

	if _show_design:
		var design_sec := _section(root, Lang.t("create_fish.design"))
		var dtabs := HBoxContainer.new()
		dtabs.add_theme_constant_override("separation", 18)
		design_sec.add_child(dtabs)
		_design_tabs.clear()
		var opts: Array = [[-1, Lang.t("design.random")]]
		for i in range(LottieFish.DESIGN_COUNT):
			opts.append([i, LottieFish.design_name(i)])
		for opt in opts:
			var val: int = opt[0]
			var b := _make_tab(str(opt[1]))
			b.pressed.connect(_select_design.bind(val))
			dtabs.add_child(b)
			_design_tabs.append([val, b])
		_update_design_tabs()

	if _show_species:
		var species_sec := _section(root, Lang.t("create_fish.species"))
		var sp_pick := OptionButton.new()
		sp_pick.add_theme_font_size_override("font_size", FONT_SIZE)
		sp_pick.get_popup().add_theme_font_size_override("font_size", FONT_SIZE)
		sp_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_option_button(sp_pick)
		var all_species: Array = FishSpecies.get_all()
		for i in range(all_species.size()):
			sp_pick.add_item(FishSpecies.get_display_name(all_species[i].id), i)
		sp_pick.select(0)
		_selected_species = str(all_species[0].id)
		sp_pick.item_selected.connect(func(idx): _selected_species = str(FishSpecies.SPECIES_LIST[idx].id))
		species_sec.add_child(sp_pick)

	var code_sec := _section(root, Lang.t("create_fish.symbol"))
	var sym_row := HBoxContainer.new()
	sym_row.add_theme_constant_override("separation", 8)
	code_sec.add_child(sym_row)
	_symbol_edit = LineEdit.new()
	_symbol_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	_symbol_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(_symbol_edit)
	_symbol_edit.text_submitted.connect(func(_t): _on_add_pressed())
	_symbol_edit.text_changed.connect(func(_t): _update_ok_state())
	sym_row.add_child(_symbol_edit)
	_search_btn = Button.new()
	_search_btn.text = "🔍"
	_search_btn.tooltip_text = Lang.t("create_fish.search_tip")
	_search_btn.custom_minimum_size = Vector2(40, 0)
	UITheme.style_icon_button(_search_btn)
	_search_btn.pressed.connect(_on_search_pressed)
	sym_row.add_child(_search_btn)
	_add_btn = Button.new()
	_add_btn.text = "＋"
	_add_btn.tooltip_text = Lang.t("create_stock.add_to_list")
	_add_btn.custom_minimum_size = Vector2(40, 0)
	UITheme.style_icon_button(_add_btn)
	_add_btn.pressed.connect(_on_add_pressed)
	sym_row.add_child(_add_btn)

	_list = HFlowContainer.new()
	_list.add_theme_constant_override("h_separation", 7)
	_list.add_theme_constant_override("v_separation", 7)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_list)

	_apply_market_ui()
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
	_pending.clear()
	_update_market_tabs()
	_apply_market_ui()
	_rebuild_list()

func _select_design(val: int) -> void:
	_selected_design = val
	_update_design_tabs()

func _update_design_tabs() -> void:
	for pair in _design_tabs:
		var val: int = pair[0]
		var b: Button = pair[1]
		var on: bool = val == _selected_design
		b.add_theme_stylebox_override("normal", _tab_style(on))
		b.add_theme_stylebox_override("hover", _tab_style(on))
		b.add_theme_stylebox_override("pressed", _tab_style(on))
		b.add_theme_color_override("font_color", UITheme.TEXT if on else UITheme.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", UITheme.TEXT)

func _apply_market_ui() -> void:
	if _symbol_edit != null:
		var ph := "create_fish.symbol_placeholder_crypto" if _current_market == "crypto" else "create_fish.symbol_placeholder"
		_symbol_edit.placeholder_text = Lang.t(ph)

func _add_pending(symbol: String) -> void:
	var sym := symbol.strip_edges().to_upper()
	if sym == "" or sym in _pending:
		return
	_pending.append(sym)
	_symbol_edit.text = ""
	_rebuild_list()

func _on_add_pressed() -> void:
	_add_pending(_symbol_edit.text)

func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var FONT_SIZE := UITheme.BODY
	if _pending.is_empty():
		var hint := Label.new()
		hint.text = Lang.t("create_stock.empty")
		hint.add_theme_font_size_override("font_size", FONT_SIZE)
		hint.modulate = UITheme.TEXT_DIM
		_list.add_child(hint)
	for sym in _pending:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.chip_style())
		_list.add_child(chip)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		chip.add_child(row)
		var lbl := Label.new()
		lbl.text = str(sym)
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.add_theme_color_override("font_color", UITheme.TEXT)
		row.add_child(lbl)
		var x := Button.new()
		x.text = "✕"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.add_theme_font_size_override("font_size", UITheme.HINT)
		x.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		x.add_theme_color_override("font_hover_color", UITheme.DOWN)
		x.pressed.connect(_remove_pending.bind(str(sym)))
		row.add_child(x)
	_update_ok_state()

func _update_ok_state() -> void:
	var typed: bool = _symbol_edit != null and _symbol_edit.text.strip_edges() != ""
	get_ok_button().disabled = _pending.is_empty() and not typed

func _remove_pending(sym: String) -> void:
	_pending.erase(sym)
	_rebuild_list()

func _on_search_pressed() -> void:
	if _active_search_dialog != null and is_instance_valid(_active_search_dialog):
		_active_search_dialog.queue_free()
		_active_search_dialog = null

	var dialog := AcceptDialog.new()
	dialog.set_script(SearchDialogScript)
	dialog.exclusive = false
	var top := get_parent()
	if top != null:
		top.add_child(dialog)
		if top is Control and dialog.has_method("set_tank_size"):
			dialog.set_tank_size(Vector2i(top.size))
	else:
		add_child(dialog)
	_active_search_dialog = dialog
	dialog.setup(_current_market)
	dialog.ticker_picked.connect(_on_ticker_picked)
	dialog.canceled.connect(func(): _active_search_dialog = null)
	dialog.popup_centered()

func _on_ticker_picked(symbol: String) -> void:
	_add_pending(symbol)
	_active_search_dialog = null

func _on_confirm() -> void:
	if _symbol_edit != null and _symbol_edit.text.strip_edges() != "":
		_add_pending(_symbol_edit.text)
	if _pending.is_empty():
		return
	tickers_committed.emit(_current_market, _pending.duplicate(), _selected_design, _selected_species)
	queue_free()
