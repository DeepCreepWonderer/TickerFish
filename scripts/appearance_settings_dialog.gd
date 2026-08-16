extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## 外观与语言设置:语言、配色两个下拉框,选中即生效。

signal confirmed


const LANGS := [["en", "menu.language.en"], ["zh", "menu.language.zh"]]
const TONES := [["deep_water", "menu.tone.deep_water"],
	["warm_charcoal", "menu.tone.warm_charcoal"],
	["indigo", "menu.tone.indigo"]]

var _lang_label: Label
var _tone_label: Label
var _lang_pick: OptionButton
var _tone_pick: OptionButton
var _close_btn: Button

func _ready() -> void:
	title = Lang.t("appearance.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()
	_build_ui()
	if Lang != null:
		Lang.language_changed.connect(_on_language_changed)
	if IdleSystem != null:
		IdleSystem.color_tone_changed.connect(_on_tone_changed)


func _on_tone_changed(_new_tone: String) -> void:
	for c in get_children():
		c.hide()
		c.queue_free()
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
	outer.add_child(root)

	_lang_label = _section_label(Lang.t("appearance.language"))
	root.add_child(_lang_label)
	_lang_pick = _make_picker(root)
	for i in range(LANGS.size()):
		_lang_pick.add_item(Lang.t(str(LANGS[i][1])), i)
	_lang_pick.select(_index_of(LANGS, IdleSystem.get_language() if IdleSystem != null else "en"))
	_lang_pick.item_selected.connect(_on_lang_selected)

	_tone_label = _section_label(Lang.t("appearance.color_tone"))
	root.add_child(_tone_label)
	_tone_pick = _make_picker(root)
	for i in range(TONES.size()):
		_tone_pick.add_item(Lang.t(str(TONES[i][1])), i)
	_tone_pick.select(_index_of(TONES, IdleSystem.get_color_tone() if IdleSystem != null else "deep_water"))
	_tone_pick.item_selected.connect(_on_tone_selected)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(foot)
	_close_btn = Button.new()
	_close_btn.text = Lang.t("dialog.close")
	UITheme.style_primary_button(_close_btn)
	_close_btn.pressed.connect(_on_close_requested)
	foot.add_child(_close_btn)

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.HINT)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

func _make_picker(root: VBoxContainer) -> OptionButton:
	var pick := OptionButton.new()
	pick.add_theme_font_size_override("font_size", UITheme.BODY)
	pick.get_popup().add_theme_font_size_override("font_size", UITheme.BODY)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_option_button(pick)
	root.add_child(pick)
	return pick

func _index_of(table: Array, value: String) -> int:
	for i in range(table.size()):
		if str(table[i][0]) == value:
			return i
	return 0

func _on_lang_selected(index: int) -> void:
	if IdleSystem == null or index < 0 or index >= LANGS.size():
		return
	IdleSystem.save_language(str(LANGS[index][0]))

func _on_tone_selected(index: int) -> void:
	if IdleSystem == null or index < 0 or index >= TONES.size():
		return
	IdleSystem.save_color_tone(str(TONES[index][0]))

func _on_language_changed(_new_lang: String) -> void:
	title = Lang.t("appearance.title")
	_lang_label.text = Lang.t("appearance.language")
	_tone_label.text = Lang.t("appearance.color_tone")
	_close_btn.text = Lang.t("dialog.close")
	for i in range(LANGS.size()):
		_lang_pick.set_item_text(i, Lang.t(str(LANGS[i][1])))
	for i in range(TONES.size()):
		_tone_pick.set_item_text(i, Lang.t(str(TONES[i][1])))

func _on_close_requested() -> void:
	confirmed.emit()
	hide()
