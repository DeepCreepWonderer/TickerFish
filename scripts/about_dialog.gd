extends "res://scripts/tide_dialog_window.gd"
const UITheme := preload("res://scripts/ui_theme.gd")
const FishBadge := preload("res://scripts/fish_badge.gd")
## 关于对话框:版本号、数据说明、免责声明、数据来源署名与链接。

signal confirmed


func _ready() -> void:
	title = Lang.t("about.title")
	exclusive = false
	borderless = false
	transparent = false
	unresizable = false
	close_requested.connect(_on_close_requested)
	apply_tide_size()

	_build_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close_requested()

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

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	root.add_child(name_row)
	var badge := FishBadge.new()
	var badge_px: int = UITheme.HERO + 16
	badge.custom_minimum_size = Vector2(badge_px, badge_px)
	name_row.add_child(badge)
	var title_label := Label.new()
	title_label.text = Lang.t("app.name")
	title_label.add_theme_font_size_override("font_size", UITheme.HERO)
	title_label.add_theme_font_override("font", UITheme.sans_bold())
	title_label.modulate = UITheme.ACCENT
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(title_label)
	var version_label := Label.new()
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version_label.add_theme_font_size_override("font_size", UITheme.HINT)
	version_label.add_theme_font_override("font", UITheme.mono())
	version_label.modulate = UITheme.TEXT_MUTE
	version_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(version_label)

	var subtitle := Label.new()
	subtitle.text = Lang.t("app.tagline")
	subtitle.add_theme_font_size_override("font_size", UITheme.HINT)
	subtitle.modulate = UITheme.TEXT_MUTE
	root.add_child(subtitle)

	_add_separator(root)

	_add_section_header(root, Lang.t("about.section.data_notes"), UITheme.SECTION)

	var data_info := Label.new()
	data_info.text = _build_data_notes_text()
	data_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data_info.add_theme_font_size_override("font_size", UITheme.BODY)
	data_info.add_theme_constant_override("line_spacing", UITheme.LINE)
	data_info.modulate = UITheme.TEXT_STRONG
	root.add_child(data_info)

	_add_separator(root)

	_add_section_header(root, Lang.t("about.section.disclaimer"), UITheme.SECTION_WARN)

	var disclaimer := Label.new()
	disclaimer.text = Lang.t("about.disclaimer")
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	disclaimer.add_theme_font_size_override("font_size", UITheme.BODY)
	disclaimer.add_theme_constant_override("line_spacing", UITheme.LINE)
	disclaimer.modulate = UITheme.TEXT_STRONG
	root.add_child(disclaimer)

	_add_separator(root)

	_add_section_header(root, Lang.t("about.section.data_sources"), UITheme.SECTION_OK)

	var sources: Array = BackendManager.get_active_data_sources()
	if sources.is_empty():
		var empty_label := Label.new()
		empty_label.text = Lang.t("about.no_sources")
		empty_label.add_theme_font_size_override("font_size", UITheme.BODY)
		empty_label.modulate = UITheme.WARN
		root.add_child(empty_label)
	else:
		for src in sources:
			var market: String = src.get("market", "")
			var market_label: String = _localize_market(market)
			var display_name: String = src.get("display_name", "Unknown")
			var url: String = src.get("url", "")
			var attr_key: String = "about.data_fallback_by" if src.get("role", "") == "fallback" else "about.data_provided_by"
			_add_source(root, market_label, Lang.t(attr_key, {"name": display_name}), url)

	_add_separator(root)

	var privacy := Label.new()
	privacy.text = Lang.t("about.privacy")
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_font_size_override("font_size", UITheme.HINT)
	privacy.add_theme_constant_override("line_spacing", UITheme.LINE)
	privacy.modulate = UITheme.TEXT_MUTE
	root.add_child(privacy)

func _add_section_header(root: VBoxContainer, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UITheme.TITLE)
	label.add_theme_font_override("font", UITheme.sans_bold())
	label.modulate = color
	root.add_child(label)

func _add_source(root: VBoxContainer, market: String, attribution: String, url: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	root.add_child(row)

	var market_label := Label.new()
	market_label.text = market
	market_label.add_theme_font_size_override("font_size", UITheme.HINT)
	market_label.modulate = UITheme.TEXT_MUTE
	row.add_child(market_label)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	row.add_child(line)

	var attr := Label.new()
	attr.text = attribution
	attr.add_theme_font_size_override("font_size", UITheme.BODY)
	attr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(attr)

	if url != "":
		var btn := Button.new()
		btn.text = Lang.t("about.visit")
		btn.custom_minimum_size = Vector2(56, 18)
		btn.add_theme_font_size_override("font_size", UITheme.BODY)
		btn.pressed.connect(_on_link_pressed.bind(url))
		line.add_child(btn)

func _add_separator(root: VBoxContainer) -> void:
	var sep := HSeparator.new()
	root.add_child(sep)

func _on_link_pressed(url: String) -> void:
	OS.shell_open(url)

func _on_close_requested() -> void:
	confirmed.emit()
	hide()


func _localize_market(market: String) -> String:
	var key := "about.market." + market
	var translated := Lang.t(key)
	if translated == key:
		return market.capitalize()
	return translated


func _build_data_notes_text() -> String:
	var lines: Array = []

	var intervals: Dictionary = BackendManager.get_market_intervals()
	if intervals.size() == 1:
		var market: String = intervals.keys()[0]
		var interval_str: String = _format_interval(int(intervals[market]))
		lines.append(Lang.t("about.data_notes.line1", {"interval": interval_str}))
	elif intervals.size() > 1:
		var phrases: Array = []
		for market in intervals.keys():
			var market_name: String = _localize_market(market)
			phrases.append("%s %s" % [market_name, _format_interval(int(intervals[market]))])
		lines.append("• " + ", ".join(phrases))
	else:
		lines.append(Lang.t("about.data_notes.line1", {"interval": "—"}))

	lines.append(Lang.t("about.data_notes.line2"))
	lines.append(Lang.t("about.data_notes.line3"))
	lines.append(Lang.t("about.data_notes.line4"))
	lines.append(Lang.t("about.data_notes.line5"))
	lines.append(Lang.t("about.data_notes.line6"))
	lines.append(Lang.t("about.data_notes.line8"))
	lines.append(Lang.t("about.data_notes.line7"))

	return "\n".join(lines)


func _format_interval(seconds: int) -> String:
	match seconds:
		30: return Lang.t("interval.30s")
		60: return Lang.t("interval.1m")
		120: return Lang.t("interval.2m")
		300: return Lang.t("interval.5m")
	if seconds < 60:
		return Lang.t("interval.seconds", {"n": seconds})
	if seconds % 60 == 0:
		@warning_ignore("integer_division")
		return Lang.t("interval.minutes", {"n": seconds / 60})
	@warning_ignore("integer_division")
	return Lang.t("interval.min_sec", {"m": seconds / 60, "s": seconds % 60})
