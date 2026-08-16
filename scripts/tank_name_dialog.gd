extends AcceptDialog
const UITheme := preload("res://scripts/ui_theme.gd")
## 新建/重命名鱼缸对话框:输入鱼缸名称,提交发信号。

signal name_submitted(tank_name: String)

const DIALOG_W := 300

var _mode: String = "create"
var _preset_name: String = ""
var _name_edit: LineEdit

func setup(dlg_mode: String, current_name: String = "") -> void:
	_mode = dlg_mode
	_preset_name = current_name

func _ready() -> void:
	var is_group: bool = _mode == "group"
	var is_rename: bool = _mode == "rename"
	if is_group:
		title = Lang.t("group.title")
	else:
		title = Lang.t("tank.rename_title") if is_rename else Lang.t("tank.create_title")
	get_ok_button().text = Lang.t("tank.save") if (is_rename or is_group) else Lang.t("tank.create")
	var cancel_btn := add_cancel_button(Lang.t("dialog.cancel"))
	UITheme.style_dialog(self)
	_build_ui()
	_on_text_changed("")
	UITheme.style_primary_button(get_ok_button())
	UITheme.style_flat_button(cancel_btn)
	confirmed.connect(_on_confirm)
	wrap_controls = true
	var sh := DisplayServer.screen_get_size(get_tree().root.current_screen)
	min_size = Vector2i(DIALOG_W, 0)
	max_size = Vector2i(DIALOG_W, int(sh.y * 0.85))
	call_deferred("_focus_edit")

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	add_child(root)

	var lbl := Label.new()
	lbl.text = Lang.t("group.name_label") if _mode == "group" else Lang.t("tank.name_label")
	lbl.add_theme_font_size_override("font_size", UITheme.HINT)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	root.add_child(lbl)

	_name_edit = LineEdit.new()
	_name_edit.add_theme_font_size_override("font_size", UITheme.BODY)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text = _preset_name
	_name_edit.placeholder_text = Lang.t("group.name_placeholder") if _mode == "group" else Lang.t("tank.name_placeholder")
	UITheme.style_input(_name_edit)
	_name_edit.text_submitted.connect(func(_t): _on_confirm())
	_name_edit.text_changed.connect(_on_text_changed)
	root.add_child(_name_edit)

	if _mode == "group" and _preset_name.strip_edges() != "":
		var clear_btn := Button.new()
		clear_btn.text = Lang.t("group.clear")
		clear_btn.add_theme_font_size_override("font_size", UITheme.BODY)
		UITheme.style_flat_button(clear_btn)
		clear_btn.pressed.connect(_on_clear_group)
		root.add_child(clear_btn)

func _on_text_changed(_new_text: String) -> void:
	if _mode != "rename" or _name_edit == null:
		return
	get_ok_button().disabled = _name_edit.text.strip_edges() == ""

func _focus_edit() -> void:
	if _name_edit != null:
		_name_edit.grab_focus()
		_name_edit.select_all()

func _on_clear_group() -> void:
	name_submitted.emit("")
	queue_free()

func _on_confirm() -> void:
	if _name_edit == null:
		return
	var tank_name: String = _name_edit.text.strip_edges()
	if _mode == "rename" and tank_name == "":
		return
	name_submitted.emit(tank_name)
	queue_free()
