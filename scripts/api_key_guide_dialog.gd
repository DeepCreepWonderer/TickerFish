extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## API key 注册引导对话框。

signal confirmed
signal request_settings


const STOCK_PROVIDERS := [
	{
		"key": "finnhub",
		"name": "Finnhub",
		"recommended": true,
		"url": "https://finnhub.io/register",
	},
]


func _ready() -> void:
	title = Lang.t("guide.title")
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

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 3)
	outer.add_child(main_vbox)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var intro := Label.new()
	intro.text = Lang.t("guide.intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", UITheme.BODY)
	intro.add_theme_constant_override("line_spacing", UITheme.LINE)
	root.add_child(intro)

	var steps_head := Label.new()
	steps_head.text = Lang.t("guide.steps_title")
	steps_head.add_theme_font_size_override("font_size", UITheme.BODY)
	steps_head.add_theme_font_override("font", UITheme.sans_bold())
	steps_head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(steps_head)

	for i in range(1, 6):
		var step := Label.new()
		step.text = Lang.t("guide.step%d" % i)
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step.add_theme_font_size_override("font_size", UITheme.BODY)
		step.add_theme_constant_override("line_spacing", UITheme.LINE)
		root.add_child(step)

	_add_separator(root)

	for provider in STOCK_PROVIDERS:
		_add_provider_card(root, provider)

	_add_separator(root)

	var crypto_note := Label.new()
	crypto_note.text = Lang.t("guide.crypto_note")
	crypto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crypto_note.add_theme_font_size_override("font_size", UITheme.HINT)
	crypto_note.add_theme_constant_override("line_spacing", UITheme.LINE)
	crypto_note.modulate = UITheme.TEXT_MUTE
	root.add_child(crypto_note)

	var tip := Label.new()
	tip.text = Lang.t("guide.tip")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", UITheme.HINT)
	tip.add_theme_constant_override("line_spacing", UITheme.LINE)
	tip.modulate = UITheme.TEXT_MUTE
	root.add_child(tip)

	var go_btn := Button.new()
	go_btn.text = Lang.t("guide.have_key_button")
	go_btn.custom_minimum_size = Vector2(0, 26)
	UITheme.style_primary_button(go_btn)
	go_btn.pressed.connect(_on_have_key_pressed)
	main_vbox.add_child(go_btn)


func _add_provider_card(root: VBoxContainer, info: Dictionary) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG
	style.border_color = UITheme.CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	box.add_child(title_row)

	var provider_key: String = info.get("key", "")
	var brand: String = info.get("name", "")

	var name_label := Label.new()
	name_label.text = brand
	name_label.add_theme_font_size_override("font_size", UITheme.TITLE)
	title_row.add_child(name_label)

	if info.get("recommended", false):
		var badge := Label.new()
		badge.text = Lang.t("guide.badge.recommended")
		badge.add_theme_font_size_override("font_size", UITheme.HINT)
		badge.modulate = UITheme.SECTION_OK
		title_row.add_child(badge)
	if info.get("warning", false):
		var warn := Label.new()
		warn.text = Lang.t("guide.badge.low_quota")
		warn.add_theme_font_size_override("font_size", UITheme.HINT)
		warn.modulate = UITheme.SECTION_WARN
		title_row.add_child(warn)

	var price_label := Label.new()
	price_label.text = "💰 " + Lang.t("guide." + provider_key + ".price")
	price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price_label.add_theme_font_size_override("font_size", UITheme.BODY)
	price_label.modulate = UITheme.SECTION_OK
	box.add_child(price_label)

	var speed_label := Label.new()
	speed_label.text = "⚡ " + Lang.t("guide." + provider_key + ".speed")
	speed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speed_label.add_theme_font_size_override("font_size", UITheme.BODY)
	speed_label.modulate = UITheme.TEXT_STRONG
	box.add_child(speed_label)

	var notes_key := "guide." + provider_key + ".notes"
	var notes := Lang.t(notes_key)
	if notes != notes_key:
		var notes_label := Label.new()
		notes_label.text = notes
		notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes_label.add_theme_font_size_override("font_size", UITheme.BODY)
		notes_label.add_theme_constant_override("line_spacing", UITheme.LINE)
		notes_label.modulate = UITheme.TEXT_MUTE
		box.add_child(notes_label)

	var url: String = info.get("url", "")
	if url != "":
		var btn := Button.new()
		btn.text = Lang.t("guide.signup_button", {"name": brand})
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override("font_size", UITheme.BODY)
		btn.pressed.connect(_on_link_pressed.bind(url))
		box.add_child(btn)

func _add_separator(root: VBoxContainer) -> void:
	var sep := HSeparator.new()
	root.add_child(sep)

func _on_link_pressed(url: String) -> void:
	OS.shell_open(url)

func _on_have_key_pressed() -> void:
	request_settings.emit()
	hide()

func _on_close_requested() -> void:
	confirmed.emit()
	hide()
