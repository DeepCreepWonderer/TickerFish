extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## 首启欢迎对话框(无 key 时引导注册/填写),只发意图不开下一个窗。


signal request_guide
signal request_settings
signal skipped


var _exit_emitted: bool = false

func _ready() -> void:
	title = Lang.t("onboarding.title")
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

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	outer.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for key in ["onboarding.line1", "onboarding.line2", "onboarding.line5", "onboarding.line3", "onboarding.line4"]:
		var line := Label.new()
		line.text = Lang.t(key)
		line.add_theme_font_size_override("font_size", UITheme.BODY)
		line.add_theme_constant_override("line_spacing", UITheme.LINE)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		vbox.add_child(line)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	root.add_child(spacer)

	var btn_get := Button.new()
	btn_get.text = Lang.t("onboarding.button.get_key")
	UITheme.style_primary_button(btn_get)
	btn_get.pressed.connect(_on_get_key_pressed)
	root.add_child(btn_get)

	var btn_have := Button.new()
	btn_have.text = Lang.t("onboarding.button.have_key")
	UITheme.style_flat_button(btn_have)
	btn_have.pressed.connect(_on_have_key_pressed)
	root.add_child(btn_have)

	var btn_skip := Button.new()
	btn_skip.text = Lang.t("onboarding.button.skip")
	UITheme.style_flat_button(btn_skip)
	btn_skip.pressed.connect(_on_skip_pressed)
	root.add_child(btn_skip)

func _on_get_key_pressed() -> void:
	if _exit_emitted:
		return
	_exit_emitted = true
	request_guide.emit()
	hide()
	queue_free()

func _on_have_key_pressed() -> void:
	if _exit_emitted:
		return
	_exit_emitted = true
	request_settings.emit()
	hide()
	queue_free()

func _on_skip_pressed() -> void:
	if _exit_emitted:
		return
	_exit_emitted = true
	skipped.emit()
	hide()
	queue_free()

func _on_close_requested() -> void:
	if _exit_emitted:
		return
	_exit_emitted = true
	skipped.emit()
	hide()
	queue_free()
