extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## 美术鱼素材引导:说明去哪买、放进哪个文件夹、就地重新检测。

signal confirmed
signal art_ready

var _status: Label = null
var _action: Button = null


func _ready() -> void:
	title = Lang.t("fish_art.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()
	_build_ui()
	if IdleSystem != null:
		IdleSystem.fish_skin_changed.connect(_on_skin_changed)


func _on_skin_changed(_new_skin: String) -> void:
	_refresh_status()


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

	var head := Label.new()
	head.text = Lang.t("fish_art.title")
	head.add_theme_font_size_override("font_size", UITheme.TITLE)
	head.add_theme_font_override("font", UITheme.sans_bold())
	head.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(head)

	var body := Label.new()
	body.text = Lang.t("fish_art.body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(240, 0)
	body.add_theme_font_size_override("font_size", UITheme.BODY)
	body.add_theme_constant_override("line_spacing", UITheme.LINE)
	body.modulate = UITheme.TEXT_STRONG
	root.add_child(body)

	var file_label := Label.new()
	file_label.text = FishArt.SHEET_NAMES[0]
	file_label.add_theme_font_size_override("font_size", UITheme.BODY)
	file_label.add_theme_font_override("font", UITheme.mono())
	file_label.modulate = UITheme.ACCENT
	root.add_child(file_label)

	var path_box := TextEdit.new()
	path_box.text = FishArt.art_dir()
	path_box.editable = false
	path_box.scroll_fit_content_height = true
	path_box.add_theme_font_size_override("font_size", UITheme.HINT)
	path_box.add_theme_font_override("font", UITheme.mono())
	path_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(path_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(240, 0)
	_status.add_theme_font_size_override("font_size", UITheme.HINT)
	root.add_child(_status)
	_refresh_status()

	var note := Label.new()
	note.text = Lang.t("fish_art.license_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(240, 0)
	note.add_theme_font_size_override("font_size", UITheme.HINT)
	note.modulate = UITheme.TEXT_MUTE
	root.add_child(note)

	var buy := Button.new()
	buy.text = Lang.t("fish_art.buy")
	UITheme.style_primary_button(buy)
	buy.pressed.connect(func(): OS.shell_open(FishArt.STORE_URL))
	root.add_child(buy)

	var open_btn := Button.new()
	open_btn.text = Lang.t("fish_art.open_folder")
	UITheme.style_flat_button(open_btn)
	open_btn.pressed.connect(_on_open_folder)
	root.add_child(open_btn)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	root.add_child(foot)

	_action = Button.new()
	UITheme.style_flat_button(_action)
	_action.pressed.connect(_on_action)
	foot.add_child(_action)
	_refresh_status()

	var close_btn := Button.new()
	close_btn.text = Lang.t("dialog.close")
	UITheme.style_primary_button(close_btn)
	close_btn.pressed.connect(_on_close_requested)
	foot.add_child(close_btn)


func _refresh_status() -> void:
	var ok: bool = FishArt.is_available()
	if _status != null:
		_status.text = Lang.t("fish_art.found") if ok else Lang.t("fish_art.not_found")
		_status.modulate = UITheme.SECTION_OK if ok else UITheme.TEXT_MUTE
	if _action == null:
		return
	var in_use: bool = IdleSystem != null and IdleSystem.get_fish_skin() == "artistic"
	if not ok:
		_action.text = Lang.t("fish_art.recheck")
		_action.disabled = false
	elif in_use:
		_action.text = Lang.t("fish_art.in_use")
		_action.disabled = true
	else:
		_action.text = Lang.t("fish_art.enable")
		_action.disabled = false


func _on_open_folder() -> void:
	FishArt.ensure_dir()
	OS.shell_open(FishArt.art_dir())


func _on_action() -> void:
	FishArt.reload()
	_refresh_status()
	if FishArt.is_available():
		art_ready.emit()
		_refresh_status()


func _on_close_requested() -> void:
	confirmed.emit()
	hide()
