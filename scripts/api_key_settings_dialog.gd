extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
## API key 设置对话框。

const ApiKeyGuideDialogScript := preload("res://scripts/api_key_guide_dialog.gd")

const PROVIDER_INFO := {
	"finnhub": {
		"label": "Finnhub API key",
		"description": "One key and you're set. Refreshes every 1 minute — enough to keep all 50 stocks (the app's maximum) fully up to date.",
		"required": false,
	},
}

signal confirmed
signal canceled


const VERIFY_URL := "https://finnhub.io/api/v1/quote?symbol=AAPL"
const VERIFY_TIMEOUT := 8.0

var _edits: Dictionary = {}
var _save_error: Label = null
var _guide_dialog: Window = null
var _verify_http: HTTPRequest = null
var _save_btn: Button = null
var _verifying: bool = false

func _ready() -> void:
	title = Lang.t("settings.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()

	_build_ui()


	_reload_values()


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
	main_vbox.add_theme_constant_override("separation", 4)
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

	var header := Label.new()
	header.text = Lang.t("settings.header")
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_font_size_override("font_size", UITheme.TITLE)
	root.add_child(header)

	var current_keys: Dictionary = BackendManager.get_api_keys()
	for key in PROVIDER_INFO.keys():
		_build_key_row(root, key, str(current_keys.get(key, "")))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 2)
	root.add_child(spacer)

	var guide_btn := Button.new()
	guide_btn.text = Lang.t("settings.guide_button")
	guide_btn.custom_minimum_size = Vector2(0, 28)
	guide_btn.add_theme_font_size_override("font_size", UITheme.BODY)
	UITheme.style_flat_button(guide_btn)
	guide_btn.pressed.connect(_on_guide_pressed)
	root.add_child(guide_btn)

	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	_save_error = Label.new()
	_save_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_error.custom_minimum_size = Vector2(240, 0)
	_save_error.add_theme_font_size_override("font_size", UITheme.HINT)
	_save_error.add_theme_constant_override("line_spacing", UITheme.LINE)
	_save_error.modulate = UITheme.WARN
	_save_error.visible = false
	main_vbox.add_child(_save_error)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = Lang.t("settings.save")
	save_btn.custom_minimum_size = Vector2(80, 24)
	UITheme.style_primary_button(save_btn)
	save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(save_btn)
	_save_btn = save_btn

func _build_key_row(root: VBoxContainer, key: String, current_value: String) -> void:
	var info: Dictionary = PROVIDER_INFO.get(key, {
		"label": key,
		"description": "",
		"required": false,
	})

	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	root.add_child(group)

	var title_label := Label.new()
	var label_key := "settings.provider." + key + ".label"
	var label_translated := Lang.t(label_key)
	var title_text: String = label_translated if label_translated != label_key else info.get("label", key)
	if info.get("required", false):
		title_text += "  " + Lang.t("settings.required")
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", UITheme.TITLE)
	group.add_child(title_label)

	var desc_key := "settings.provider." + key + ".description"
	var desc_translated := Lang.t(desc_key)
	var desc: String = desc_translated if desc_translated != desc_key else info.get("description", "")
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", UITheme.BODY)
		desc_label.add_theme_constant_override("line_spacing", UITheme.LINE)
		desc_label.modulate = UITheme.TEXT_DIM
		group.add_child(desc_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	group.add_child(row)

	var edit := LineEdit.new()
	edit.text = current_value
	edit.placeholder_text = Lang.t("settings.placeholder")
	edit.secret = true
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(edit)
	row.add_child(edit)
	_edits[key] = edit

	var show_btn := Button.new()
	show_btn.text = "👁"
	show_btn.tooltip_text = Lang.t("settings.toggle_show")
	show_btn.custom_minimum_size = Vector2(26, 0)
	show_btn.toggle_mode = true
	UITheme.style_icon_button(show_btn)
	show_btn.toggled.connect(_on_show_toggled.bind(edit))
	row.add_child(show_btn)

func _on_show_toggled(pressed: bool, edit: LineEdit) -> void:
	if edit != null and is_instance_valid(edit):
		edit.secret = not pressed

func _on_guide_pressed() -> void:
	if _guide_dialog != null and is_instance_valid(_guide_dialog):
		_guide_dialog.queue_free()
		_guide_dialog = null

	_guide_dialog = ApiKeyGuideDialogScript.new()
	get_tree().root.add_child(_guide_dialog)
	_guide_dialog.close_requested.connect(_on_guide_closed)
	if _guide_dialog.has_signal("confirmed"):
		_guide_dialog.confirmed.connect(_on_guide_closed)
	if _guide_dialog.has_signal("request_settings"):
		_guide_dialog.request_settings.connect(_on_guide_closed)
	if _guide_dialog.has_method("set_tank_size"):
		_guide_dialog.set_tank_size(_tank_size)
	_guide_dialog.popup_centered_on_parent()

func _on_guide_closed() -> void:
	if _guide_dialog != null and is_instance_valid(_guide_dialog):
		_guide_dialog.queue_free()
	_guide_dialog = null

func _reload_values() -> void:
	var current_keys: Dictionary = BackendManager.get_api_keys()
	for key in _edits.keys():
		var edit: LineEdit = _edits[key]
		if edit != null and is_instance_valid(edit):
			edit.text = current_keys.get(key, "")

func _on_save_pressed() -> void:
	var new_keys := {}
	for key in _edits.keys():
		var edit: LineEdit = _edits[key]
		if edit != null and is_instance_valid(edit):
			new_keys[key] = edit.text.strip_edges()

	if _verifying:
		return

	var keys_ok: bool = BackendManager.save_api_keys(new_keys)
	if not keys_ok:
		push_error("[ApiKeyDialog] failed to save API keys")
		_show_status(Lang.t("settings.save_failed"), UITheme.WARN)
		return

	print("[ApiKeyDialog] saved keys=", new_keys.keys())
	var key: String = str(new_keys.get("finnhub", "")).strip_edges()
	if key == "":
		_finish_save()
		return
	_start_verify(key)

func _show_status(msg: String, color: Color) -> void:
	if _save_error == null or not is_instance_valid(_save_error):
		return
	_save_error.text = msg
	_save_error.modulate = color
	_save_error.visible = msg != ""

func _finish_save() -> void:
	_show_status("", UITheme.WARN)
	confirmed.emit()
	hide()

func _start_verify(key: String) -> void:
	if _verify_http == null or not is_instance_valid(_verify_http):
		_verify_http = HTTPRequest.new()
		_verify_http.timeout = VERIFY_TIMEOUT
		_verify_http.max_redirects = 0
		add_child(_verify_http)
		_verify_http.request_completed.connect(_on_verify_done)

	var err := _verify_http.request(VERIFY_URL, PackedStringArray(["X-Finnhub-Token: " + key]),
		HTTPClient.METHOD_GET)
	if err != OK:
		_show_status(Lang.t("settings.verify_offline"), UITheme.WARN)
		return
	_verifying = true
	if _save_btn != null and is_instance_valid(_save_btn):
		_save_btn.disabled = true
	_show_status(Lang.t("settings.verifying"), UITheme.TEXT_DIM)

func _on_verify_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_verifying = false
	if _save_btn != null and is_instance_valid(_save_btn):
		_save_btn.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_show_status(Lang.t("settings.verify_offline"), UITheme.WARN)
		return
	if code == 401 or code == 403:
		_show_status(Lang.t("settings.verify_rejected"), UITheme.DOWN)
		return
	if code == 429:
		_show_status(Lang.t("settings.verify_rate_limited"), UITheme.WARN)
		return
	if code != 200:
		_show_status(Lang.t("settings.verify_offline"), UITheme.WARN)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or float(parsed.get("c", 0)) <= 0.0:
		_show_status(Lang.t("settings.verify_rejected"), UITheme.DOWN)
		return

	print("[ApiKeyDialog] key verified OK")
	_finish_save()

func _on_close_requested() -> void:
	canceled.emit()
	hide()
