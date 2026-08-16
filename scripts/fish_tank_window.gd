extends Control
## 主窗口:透明无边框置顶,鱼缸/数字/大卡/横幅四模式 + 右键菜单 + 状态栏。

const WINDOW_WIDTH_RATIO := 0.40
const WINDOW_HEIGHT_RATIO := 0.55
const SCREEN_EDGE_MARGIN := 20

const NUMERIC_WIDTH_RATIO := 0.17
const NUMERIC_HEIGHT_RATIO := 0.62
const NUMERIC_MIN_WIDTH := 280
const NUMERIC_MAX_WIDTH := 380
const NUMERIC_MIN_HEIGHT := 360

const STRIP_BAR_HEIGHT := 84
const STRIP_COLS_PER_ROW := 8
const STRIP_MAX_ROWS := 7
const BADGE_GUTTER := 26.0

var _menu_btn: int = MOUSE_BUTTON_LEFT
const HERO_PANEL_W := 220
const HERO_MAX_PANELS := 10
const HERO_MAX_ASPECT := 1.4

const MIN_WINDOW_SIZE := Vector2i(280, 155)
const MAX_WINDOW_SIZE_RATIO := 0.80

const RESIZE_EDGE_THICKNESS := 8

const BORDER_COLOR := Color(0.906, 0.722, 0.361, 0.7)
const BORDER_WIDTH := 2.0
const BORDER_FADE_DURATION := 0.25

const CLOSE_BTN_SIZE := 24
const CLOSE_BTN_MARGIN := 6
const CLOSE_BTN_BG_COLOR := Color(0.941, 0.439, 0.431, 0.9)
const CLOSE_BTN_BG_HOVER_COLOR := Color(1.0, 0.5, 0.49, 1.0)
const CLOSE_BTN_X_COLOR := Color(1, 1, 1, 1)

const ADD_BTN_SIZE := 24
const ADD_BTN_MARGIN := 6
const ADD_BTN_BG_COLOR := Color(0.275, 0.788, 0.541, 0.9)
const ADD_BTN_BG_HOVER_COLOR := Color(0.34, 0.88, 0.62, 1.0)
const ADD_BTN_PLUS_COLOR := Color(0.055, 0.078, 0.086, 1)

const DEL_BTN_SIZE := 24
const DEL_BTN_GAP := 6
const DEL_BTN_BG_COLOR := Color(0.70, 0.42, 0.42, 0.85)
const DEL_BTN_BG_HOVER_COLOR := Color(0.85, 0.5, 0.49, 1.0)
const DEL_BTN_MINUS_COLOR := Color(1, 1, 1, 1)

const TAB_FADE_DURATION := 0.3

const FishScene := preload("res://fish.tscn")
const CreateFishDialogScript := preload("res://scripts/create_fish_dialog.gd")
const DeleteFishDialogScript := preload("res://scripts/delete_fish_dialog.gd")
const TankNameDialogScript := preload("res://scripts/tank_name_dialog.gd")
const MoonIconScript := preload("res://scripts/moon_icon.gd")
const ApiKeySettingsDialogScript := preload("res://scripts/api_key_settings_dialog.gd")
const ApiKeyGuideDialogScript := preload("res://scripts/api_key_guide_dialog.gd")
const OnboardingDialogScript := preload("res://scripts/onboarding_dialog.gd")
const AboutDialogScript := preload("res://scripts/about_dialog.gd")
const PriceRecordSettingsDialogScript := preload("res://scripts/price_record_settings_dialog.gd")
const AlertSettingsDialogScript := preload("res://scripts/alert_settings_dialog.gd")
const AlertHistoryDialogScript := preload("res://scripts/alert_history_dialog.gd")
const AppearanceSettingsDialogScript := preload("res://scripts/appearance_settings_dialog.gd")
const NumericPanelScript := preload("res://scripts/numeric_panel.gd")
const HeroCardPanelScript := preload("res://scripts/hero_card_panel.gd")
const StripPanelScript := preload("res://scripts/strip_panel.gd")
const HeroCardEditDialogScript := preload("res://scripts/hero_card_edit_dialog.gd")
const FishArtDialogScript := preload("res://scripts/fish_art_dialog.gd")
const UITheme := preload("res://scripts/ui_theme.gd")

var _is_dragging := false
var _is_resizing := false
var _resize_edges: Vector2i = Vector2i.ZERO
var _drag_offset := Vector2i.ZERO

var _border_alpha := 0.0
var _border_target_alpha := 0.0

var _close_btn_hovered := false
var _add_btn_hovered := false
var _del_btn_hovered := false
var _active_dialog: Window = null
var _commit_limit_blocked: bool = false
var _commit_tank_full: bool = false
var _commit_duplicates: Array[String] = []

var _font: Font

var _moon_icon: Node2D = null
var _moon_alpha: float = 0.0
const MOON_FADE_DURATION := 0.4

var _after_hours_dialog: AcceptDialog = null

var _press_start_pos: Vector2 = Vector2.ZERO
var _press_moved := false
const CLICK_TOLERANCE := 4.0

var _display_mode: String = "fish_tank"
var _ctx_hero_panel: int = -1
var _card_drag_idx: int = -1
var _card_drag_x: float = 0.0
var _numeric_panel: RefCounted = null
var _hero_panel: RefCounted = null
var _strip_panel: RefCounted = null

const CARD_SCROLL_STEP := 44.0

func _ready() -> void:
	var window := get_window()
	window.borderless = true
	if IdleSystem != null:
		window.always_on_top = IdleSystem.get_always_on_top()
	else:
		window.always_on_top = false
	window.transparent = true
	window.transparent_bg = true

	if Lang != null:
		Lang.language_changed.connect(_on_language_changed)

	if AlertSystem != null:
		AlertSystem.alert_fired.connect(_on_alert_fired)
	if IdleSystem != null:
		IdleSystem.alert_history_changed.connect(_on_alert_history_changed)

	var mouse_pos := DisplayServer.mouse_get_position()
	var screen_id := DisplayServer.get_screen_from_rect(Rect2i(mouse_pos, Vector2i.ONE))
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()

	var screen_pos := DisplayServer.screen_get_position(screen_id)
	var screen_size := DisplayServer.screen_get_size(screen_id)

	print("[FishTank] Mouse detected on screen ", screen_id, " pos=", screen_pos, " size=", screen_size)

	var launch_mode: String = IdleSystem.get_display_mode() if IdleSystem != null else "fish_tank"
	var def_size := _default_window_size(launch_mode, screen_size)
	window.size = def_size
	window.position = _mode_position(launch_mode, screen_pos, screen_size, def_size)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	if IdleSystem != null and launch_mode != "strip" and launch_mode != "hero":
		var saved: Dictionary = IdleSystem.get_window_state(launch_mode)
		if not saved.is_empty():
			var saved_size := Vector2i(int(saved.get("w", def_size.x)), int(saved.get("h", def_size.y)))
			var saved_pos := Vector2i(int(saved.get("x", window.position.x)), int(saved.get("y", window.position.y)))
			var test_screen_id := DisplayServer.get_screen_from_rect(Rect2i(saved_pos, saved_size))
			if test_screen_id >= 0:
				window.size = saved_size
				window.position = saved_pos
				print("[FishTank] Restored ", launch_mode, " window state")

	print("[FishTank] Window init complete. size=", window.size, " pos=", window.position)

	UITheme.apply_default_font()
	if IdleSystem != null:
		UITheme.set_tone(IdleSystem.get_color_tone())
	_font = ThemeDB.fallback_font

	if IdleSystem != null:
		_display_mode = IdleSystem.get_display_mode()
		IdleSystem.display_mode_changed.connect(_on_display_mode_changed)

	if IdleSystem != null:
		IdleSystem.fish_list_changed.connect(_rebuild_fish_nodes)
		IdleSystem.active_tank_changed.connect(func(_id): _rebuild_fish_nodes(true); queue_redraw())
		IdleSystem.global_limit_reached.connect(func(): _commit_limit_blocked = true)
		IdleSystem.tank_full.connect(func(): _commit_tank_full = true)
		IdleSystem.duplicate_skipped.connect(func(sym: String): _commit_duplicates.append(sym))
		IdleSystem.fish_skin_changed.connect(_on_fish_skin_changed)
		IdleSystem.color_tone_changed.connect(_on_color_tone_changed)

	if BackendManager != null:
		BackendManager.backend_state_changed.connect(func(_s): queue_redraw())

	if DataReader != null:
		DataReader.prices_updated.connect(_on_prices_updated_check_config)
		DataReader.prices_updated.connect(_on_numeric_data_changed)
	if IdleSystem != null:
		IdleSystem.numeric_list_changed.connect(_on_numeric_data_changed)
		IdleSystem.price_stream_changed.connect(func(_on): queue_redraw())

	_moon_icon = Node2D.new()
	_moon_icon.set_script(MoonIconScript)
	add_child(_moon_icon)
	move_child(_moon_icon, 0)

	_apply_display_mode()

var _config_dialog_auto_shown: bool = false
var _onboarding_skipped: bool = false

func _on_prices_updated_check_config() -> void:
	if _config_dialog_auto_shown:
		return
	if _onboarding_skipped:
		return
	if not DataReader.needs_config():
		return
	if _active_dialog != null and is_instance_valid(_active_dialog):
		return
	_config_dialog_auto_shown = true
	print("[FishTank] Provider needs API key; showing onboarding")
	_open_onboarding_dialog()

func _rebuild_fish_nodes(fade_in: bool = false) -> void:
	for child in get_children():
		if child.has_method("is_point_inside") and child.has_method("spawn_bubble"):
			child.queue_free()

	if _display_mode != "fish_tank":
		return

	if IdleSystem == null:
		return

	var fish_list: Array = IdleSystem.get_fish_list()
	var tank_w: float = size.x if size.x > 0 else 384.0
	var tank_h: float = size.y if size.y > 0 else 211.0
	var created := 0
	for fish_data in fish_list:
		var fish_market: String = fish_data.get("market", "stocks")
		var symbol: String = fish_data.get("symbol", "AAPL")
		var ticker_key := "%s:%s" % [fish_market, symbol]

		var fish := FishScene.instantiate()
		fish.ticker_key = ticker_key
		fish.market = fish_market
		fish.fish_id = fish_data.get("id", "")
		fish.nickname = fish_data.get("nickname", symbol)
		fish.position = Vector2(
			randf_range(tank_w * 0.2, tank_w * 0.8),
			randf_range(tank_h * 0.2, tank_h * 0.8)
		)
		fish.name = "Fish_" + symbol.replace(".", "_").replace("-", "_")
		add_child(fish)
		if fade_in:
			fish.fade_in(TAB_FADE_DURATION)
		created += 1

	print("[FishTank] Active tank spawned ", created, " fish")

func _process(delta: float) -> void:
	if abs(_border_alpha - _border_target_alpha) > 0.01:
		var dir := 1.0 if _border_target_alpha > _border_alpha else -1.0
		_border_alpha += dir * (delta / BORDER_FADE_DURATION)
		_border_alpha = clamp(_border_alpha, 0.0, 1.0)
		queue_redraw()

	_update_moon(delta)

	if _display_mode == "hero" and _hero_panel != null:
		if _hero_panel.tick(delta):
			queue_redraw()

	if _display_mode == "numeric" and _numeric_panel != null:
		if _numeric_panel.tick(delta):
			queue_redraw()

	if _display_mode == "strip" and _strip_panel != null:
		if _strip_panel.tick(delta):
			queue_redraw()

func _update_moon(delta: float) -> void:
	if _moon_icon == null:
		return

	if _display_mode != "fish_tank":
		if _moon_alpha != 0.0:
			_moon_alpha = 0.0
			_moon_icon.set_visibility(0.0, size)
		return

	var all_sleeping: bool = _is_active_tank_all_sleeping()
	var moon_target_alpha: float = _border_alpha if all_sleeping else 0.0

	var speed: float = delta / MOON_FADE_DURATION
	speed = min(speed, 1.0)
	_moon_alpha = lerp(_moon_alpha, moon_target_alpha, speed * 4.0)
	if abs(_moon_alpha - moon_target_alpha) < 0.005:
		_moon_alpha = moon_target_alpha

	_moon_icon.set_visibility(_moon_alpha, size)

	if all_sleeping and IdleSystem != null and IdleSystem.is_first_after_hours_pending():
		_show_first_after_hours_dialog()

func _is_active_tank_all_sleeping() -> bool:
	var has_fish := false
	for child in get_children():
		if child.has_method("is_point_inside") and child.has_method("spawn_bubble"):
			has_fish = true
			if MarketClock.is_market_awake(str(child.market)):
				return false
	return has_fish

func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	if _display_mode != "fish_tank" and _alert_badge_visible():
		panel_rect = Rect2(Vector2(BADGE_GUTTER, 0.0), size - Vector2(BADGE_GUTTER, 0.0))

	if _display_mode == "numeric" and _numeric_panel != null:
		_numeric_panel.render(self, _font, panel_rect)
	elif _display_mode == "hero" and _hero_panel != null:
		_hero_panel.render(self, _font, panel_rect)
	elif _display_mode == "strip" and _strip_panel != null:
		_strip_panel.render(self, _font, panel_rect)

	var be_state := BackendManager.get_state() if BackendManager != null else BackendManager.STATE_DEV
	var needs_cfg := DataReader != null and DataReader.needs_config()
	var should_show_status := be_state == BackendManager.STATE_STARTING or needs_cfg

	if _border_alpha < 0.01:
		if should_show_status:
			_draw_backend_status()
		_draw_alert_badge()
		return

	var rect := Rect2(Vector2.ZERO, size)
	var border_color := BORDER_COLOR
	border_color.a *= _border_alpha
	draw_rect(rect, border_color, false, BORDER_WIDTH)

	var btn_rect := _get_close_btn_rect()
	var bg_color := CLOSE_BTN_BG_HOVER_COLOR if _close_btn_hovered else CLOSE_BTN_BG_COLOR
	bg_color.a *= _border_alpha
	draw_rect(btn_rect, bg_color, true)

	var x_color := CLOSE_BTN_X_COLOR
	x_color.a *= _border_alpha
	var padding := 7.0
	var p1 := btn_rect.position + Vector2(padding, padding)
	var p2 := btn_rect.position + btn_rect.size - Vector2(padding, padding)
	var p3 := btn_rect.position + Vector2(btn_rect.size.x - padding, padding)
	var p4 := btn_rect.position + Vector2(padding, btn_rect.size.y - padding)
	draw_line(p1, p2, x_color, 2.0, true)
	draw_line(p3, p4, x_color, 2.0, true)

	if _has_empty_slot():
		var add_rect := _get_add_btn_rect()
		var add_bg := ADD_BTN_BG_HOVER_COLOR if _add_btn_hovered else ADD_BTN_BG_COLOR
		add_bg.a *= _border_alpha
		draw_rect(add_rect, add_bg, true)

		var plus_color := ADD_BTN_PLUS_COLOR
		plus_color.a *= _border_alpha
		var ap := 6.0
		var center := add_rect.position + add_rect.size * 0.5
		draw_line(center + Vector2(-add_rect.size.x * 0.5 + ap, 0),
				  center + Vector2(add_rect.size.x * 0.5 - ap, 0),
				  plus_color, 2.0, true)
		draw_line(center + Vector2(0, -add_rect.size.y * 0.5 + ap),
				  center + Vector2(0, add_rect.size.y * 0.5 - ap),
				  plus_color, 2.0, true)

	if _has_deletable():
		var del_rect := _get_del_btn_rect()
		var del_bg := DEL_BTN_BG_HOVER_COLOR if _del_btn_hovered else DEL_BTN_BG_COLOR
		del_bg.a *= _border_alpha
		draw_rect(del_rect, del_bg, true)
		var minus_color := DEL_BTN_MINUS_COLOR
		minus_color.a *= _border_alpha
		var dp := 6.0
		var dc := del_rect.position + del_rect.size * 0.5
		draw_line(dc + Vector2(-del_rect.size.x * 0.5 + dp, 0),
				  dc + Vector2(del_rect.size.x * 0.5 - dp, 0),
				  minus_color, 2.0, true)

	_draw_backend_status()

	if _display_mode == "fish_tank":
		_draw_recording_indicator()
	_draw_alert_badge()

func _alert_badge_visible() -> bool:
	if IdleSystem == null:
		return false
	if not IdleSystem.get_alerts_enabled():
		return false
	return IdleSystem.get_unread_alert_count() > 0

func _draw_alert_badge() -> void:
	if _font == null or not _alert_badge_visible():
		return
	var n: int = IdleSystem.get_unread_alert_count()
	var amber := Color(0.96, 0.72, 0.26, 0.95)
	var cx := 14.0
	var cy: float = _alert_badge_cy()
	draw_circle(Vector2(cx, cy), 7.0, amber)
	var label: String = str(n) if n < 100 else "99+"
	var fs := 10
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, Vector2(cx - text_size.x * 0.5, cy + fs * 0.35), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.15, 0.1, 0.0, 1))

func _draw_recording_indicator() -> void:
	if PriceRecorder == null or not PriceRecorder.is_recording():
		return
	if _font == null:
		return
	var amber := Color(0.96, 0.72, 0.26, 0.95)
	var cx := 14.0
	var cy := 14.0
	draw_circle(Vector2(cx, cy), 3.5, amber)
	var label: String = Lang.t("rec.recording") if Lang != null else "REC"
	draw_string(_font, Vector2(cx + 9.0, cy + 4.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, amber)

func _draw_backend_status() -> void:
	if _font == null:
		return

	var msg := ""
	var color := Color(0.4, 0.4, 0.5, 0.85)
	var error_code := DataReader.get_error_code() if DataReader != null else ""
	if DataReader != null and DataReader.needs_config():
		msg = Lang.t("status.needs_config")
		color = Color(0.85, 0.65, 0.25, 0.95)
	elif error_code != "":
		msg = Lang.t("status.error." + error_code)
		color = Color(0.85, 0.55, 0.25, 0.95) if error_code == "rate_limited" else Color(0.8, 0.35, 0.3, 0.95)
	else:
		if BackendManager.get_state() != BackendManager.STATE_STARTING:
			return
		msg = Lang.t("status.connecting")
		color = Color(0.4, 0.5, 0.7, 0.85)

	if msg == "":
		return

	var fs := 13
	var text_size := _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(
		(size.x - text_size.x) * 0.5,
		size.y * 0.5 + fs * 0.5,
	)
	draw_string(_font, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func _get_close_btn_rect() -> Rect2:
	return Rect2(
		size.x - CLOSE_BTN_SIZE - CLOSE_BTN_MARGIN,
		CLOSE_BTN_MARGIN,
		CLOSE_BTN_SIZE,
		CLOSE_BTN_SIZE
	)

func _is_in_close_btn(local_pos: Vector2) -> bool:
	return _get_close_btn_rect().has_point(local_pos)

func _get_add_btn_rect() -> Rect2:
	return Rect2(
		size.x - ADD_BTN_SIZE - ADD_BTN_MARGIN,
		size.y - ADD_BTN_SIZE - ADD_BTN_MARGIN,
		ADD_BTN_SIZE,
		ADD_BTN_SIZE
	)

func _is_in_add_btn(local_pos: Vector2) -> bool:
	if not _has_empty_slot():
		return false
	return _get_add_btn_rect().has_point(local_pos)

func _get_del_btn_rect() -> Rect2:
	return Rect2(
		size.x - ADD_BTN_SIZE - ADD_BTN_MARGIN - DEL_BTN_GAP - DEL_BTN_SIZE,
		size.y - DEL_BTN_SIZE - ADD_BTN_MARGIN,
		DEL_BTN_SIZE,
		DEL_BTN_SIZE
	)

func _is_in_del_btn(local_pos: Vector2) -> bool:
	if not _has_deletable():
		return false
	return _get_del_btn_rect().has_point(local_pos)

func _has_deletable() -> bool:
	if IdleSystem == null:
		return false
	if _display_mode != "fish_tank":
		return not IdleSystem.get_numeric_list().is_empty()
	return not (IdleSystem.get_active_tank().get("fish", []) as Array).is_empty()

func _alert_badge_cy() -> float:
	var rec_shown: bool = _display_mode == "fish_tank" \
		and PriceRecorder != null and PriceRecorder.is_recording()
	return 30.0 if rec_shown else 14.0

func _get_alert_badge_rect() -> Rect2:
	return Rect2(Vector2(14.0 - 9.0, _alert_badge_cy() - 9.0), Vector2(18.0, 18.0))

func _is_in_alert_badge(local_pos: Vector2) -> bool:
	if not _alert_badge_visible():
		return false
	return _get_alert_badge_rect().has_point(local_pos)

func _has_empty_slot() -> bool:
	if IdleSystem == null:
		return false
	if _display_mode != "fish_tank":
		return not IdleSystem.is_numeric_list_full()
	return not IdleSystem.is_active_tank_full()

func _find_fish_at(local_pos: Vector2) -> Node:
	var children := get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if child.has_method("is_point_inside") and child.has_method("spawn_bubble"):
			if child.is_point_inside(local_pos):
				return child
	return null

func _close_all_bubbles() -> void:
	for child in get_children():
		if child.has_method("close_bubble"):
			child.close_bubble()

func _on_mouse_entered() -> void:
	_border_target_alpha = 1.0

func _on_mouse_exited() -> void:
	_border_target_alpha = 0.0
	_close_btn_hovered = false
	_add_btn_hovered = false
	_del_btn_hovered = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var window := get_window()

	if event is InputEventMouseMotion:
		var hover_close := _is_in_close_btn(event.position)
		var hover_add := _is_in_add_btn(event.position)
		var hover_del := _is_in_del_btn(event.position)
		if hover_close != _close_btn_hovered or hover_add != _add_btn_hovered or hover_del != _del_btn_hovered:
			_close_btn_hovered = hover_close
			_add_btn_hovered = hover_add
			_del_btn_hovered = hover_del
			queue_redraw()

		if not _is_dragging and not _is_resizing and _card_drag_idx < 0:
			if hover_close or hover_add or _is_in_alert_badge(event.position):
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			else:
				var edges := _get_resize_edges(event.position)
				_update_cursor_for_edges(edges)

		if _card_drag_idx >= 0:
			if (event.position - _press_start_pos).length() > CLICK_TOLERANCE:
				_press_moved = true
			_card_drag_x = event.position.x
			if _display_mode == "strip" and _strip_panel != null:
				_strip_panel.set_drag(_card_drag_idx, event.position)
			elif _hero_panel != null:
				_hero_panel.set_drag(_card_drag_idx, _card_drag_x)
			queue_redraw()
			return

		if _is_dragging:
			if (event.position - _press_start_pos).length() > CLICK_TOLERANCE:
				_press_moved = true
			var mouse_global := DisplayServer.mouse_get_position()
			window.position = mouse_global - _drag_offset
			return

		if _is_resizing:
			_do_resize(event.position, event.relative)
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_in_alert_badge(event.position):
					print("[FishTank] Alert badge clicked")
					_open_alert_history_dialog()
					return

				if _is_in_close_btn(event.position):
					print("[FishTank] Close button clicked")
					_quit_and_save()
					return

				if _is_in_add_btn(event.position):
					print("[FishTank] Add-fish button clicked")
					_show_create_fish_dialog()
					return

				if _is_in_del_btn(event.position):
					print("[FishTank] Delete-fish button clicked")
					_show_delete_fish_dialog()
					return

				var edges := _get_resize_edges(event.position)
				var hero_card := -1
				if _display_mode == "hero" and _hero_panel != null:
					hero_card = _hero_panel.panel_index_at(event.position)
				elif _display_mode == "strip" and _strip_panel != null and edges == Vector2i.ZERO:
					hero_card = _strip_panel.index_at(event.position)
				if hero_card >= 0:
					_card_drag_idx = hero_card
					_press_start_pos = event.position
					_card_drag_x = event.position.x
					_press_moved = false
					if _display_mode == "strip":
						_strip_panel.set_drag(hero_card, event.position)
					else:
						_hero_panel.set_drag(hero_card, _card_drag_x)
					mouse_default_cursor_shape = Control.CURSOR_DRAG
				elif edges != Vector2i.ZERO:
					_is_resizing = true
					_resize_edges = edges
				else:
					_is_dragging = true
					_press_start_pos = event.position
					_press_moved = false
					_drag_offset = DisplayServer.mouse_get_position() - window.position
			else:
				if _card_drag_idx >= 0:
					if _display_mode == "strip" and _strip_panel != null:
						if _press_moved and IdleSystem != null:
							var list: Array = IdleSystem.get_numeric_list()
							var item_id: String = ""
							if _card_drag_idx < list.size():
								item_id = str(list[_card_drag_idx].get("id", ""))
							var slot: int = _strip_panel.drag_slot()
							var group: String = _strip_panel.drag_group()
							if slot >= 0 and slot != _card_drag_idx:
								IdleSystem.reorder_numeric_item(_card_drag_idx, slot)
							if item_id != "":
								IdleSystem.set_numeric_item_group(item_id, group)
						_strip_panel.clear_drag()
					elif _press_moved and _hero_panel != null and IdleSystem != null:
						var target: int = _hero_panel.slot_at_x(_card_drag_x)
						if target >= 0 and target != _card_drag_idx:
							IdleSystem.reorder_hero_panel(_card_drag_idx, target)
							_hero_panel.reorder_state(_card_drag_idx, target)
							_resize_hero_to_fit()
					if _hero_panel != null:
						_hero_panel.clear_drag()
					_card_drag_idx = -1
					_press_moved = false
					mouse_default_cursor_shape = Control.CURSOR_ARROW
					queue_redraw()
					return

				if _is_dragging and not _press_moved:
					var fish := _find_fish_at(_press_start_pos)
					if fish != null:
						fish.spawn_bubble()
					else:
						_close_all_bubbles()

				_is_dragging = false
				_is_resizing = false
				_resize_edges = Vector2i.ZERO
				_press_moved = false
				_update_cursor_for_edges(Vector2i.ZERO)

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var list_panel := _active_list_panel()
			if list_panel != null:
				_ctx_hero_panel = -1
				if _display_mode == "hero" and _hero_panel != null:
					_ctx_hero_panel = _hero_panel.panel_index_at(event.position)
				var row_id := ""
				var row_label := ""
				row_id = list_panel.item_id_at(event.position)
				if row_id != "":
					row_label = list_panel.item_label_at(event.position)
				_show_context_menu(event.position, row_id, row_label)
				return
			var fish := _find_fish_at(event.position)
			if fish != null:
				_show_fish_context_menu(event.position, fish)
			else:
				_show_context_menu(event.position)

		if _display_mode == "numeric" and event.pressed and _numeric_panel != null:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _numeric_panel.scroll_by(CARD_SCROLL_STEP):
					queue_redraw()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if _numeric_panel.scroll_by(-CARD_SCROLL_STEP):
					queue_redraw()

func _get_resize_edges(local_pos: Vector2) -> Vector2i:
	var edges := Vector2i.ZERO
	if local_pos.x < RESIZE_EDGE_THICKNESS:
		edges.x = -1
	elif local_pos.x > size.x - RESIZE_EDGE_THICKNESS:
		edges.x = 1
	if local_pos.y < RESIZE_EDGE_THICKNESS:
		edges.y = -1
	elif local_pos.y > size.y - RESIZE_EDGE_THICKNESS:
		edges.y = 1
	return edges

func _update_cursor_for_edges(edges: Vector2i) -> void:
	if edges == Vector2i.ZERO:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif edges.x != 0 and edges.y != 0:
		if edges.x * edges.y > 0:
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		else:
			mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	elif edges.x != 0:
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
	elif edges.y != 0:
		mouse_default_cursor_shape = Control.CURSOR_VSIZE

func _do_resize(_local_pos: Vector2, relative: Vector2) -> void:
	var window := get_window()
	var new_size := Vector2i(window.size)
	var new_pos := Vector2i(window.position)

	var screen_id := DisplayServer.get_screen_from_rect(Rect2i(new_pos, new_size))
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()
	var screen_size := DisplayServer.screen_get_size(screen_id)
	var max_size := Vector2i(
		int(screen_size.x * MAX_WINDOW_SIZE_RATIO),
		int(screen_size.y * MAX_WINDOW_SIZE_RATIO)
	)
	if _display_mode == "hero":
		max_size.y = mini(max_size.y, _hero_max_height(new_size.x))

	if _resize_edges.x == 1:
		new_size.x = clamp(new_size.x + int(relative.x), MIN_WINDOW_SIZE.x, max_size.x)
	elif _resize_edges.x == -1:
		var delta := int(relative.x)
		var proposed := new_size.x - delta
		proposed = clamp(proposed, MIN_WINDOW_SIZE.x, max_size.x)
		new_pos.x += new_size.x - proposed
		new_size.x = proposed

	if _resize_edges.y == 1:
		new_size.y = clamp(new_size.y + int(relative.y), MIN_WINDOW_SIZE.y, max_size.y)
	elif _resize_edges.y == -1:
		var delta := int(relative.y)
		var proposed := new_size.y - delta
		proposed = clamp(proposed, MIN_WINDOW_SIZE.y, max_size.y)
		new_pos.y += new_size.y - proposed
		new_size.y = proposed

	window.size = new_size
	window.position = new_pos

func _show_context_menu(local_pos: Vector2, row_item_id: String = "", _row_label: String = "") -> void:
	var menu := PopupMenu.new()
	UITheme.style_popup_menu(menu)
	_guard_menu(menu)

	var has_top_items := false
	if _display_mode == "hero" and _ctx_hero_panel >= 0:
		menu.add_item(Lang.t("menu.hero_edit_card"), 73)
		menu.add_item(Lang.t("menu.hero_delete_card"), 74)
		has_top_items = true
	if _display_mode != "fish_tank" and row_item_id != "":
		if _display_mode == "strip":
			menu.add_item(Lang.t("menu.set_group"), 71)
		menu.add_item(Lang.t("menu.delete_fish", {"name": _row_label}), 70)
		has_top_items = true
	if has_top_items:
		menu.add_separator()

	var disp_submenu := PopupMenu.new()
	UITheme.style_popup_menu(disp_submenu)
	disp_submenu.window_input.connect(_on_menu_window_input.bind(disp_submenu))
	disp_submenu.name = "DisplayModeSubmenu"
	disp_submenu.add_check_item(Lang.t("menu.display_mode.fish_tank"), 60)
	disp_submenu.add_check_item(Lang.t("menu.display_mode.numeric"), 61)
	disp_submenu.add_check_item(Lang.t("menu.display_mode.hero"), 62)
	disp_submenu.add_check_item(Lang.t("menu.display_mode.strip"), 63)
	disp_submenu.set_item_checked(0, _display_mode == "fish_tank")
	disp_submenu.set_item_checked(1, _display_mode == "numeric")
	disp_submenu.set_item_checked(2, _display_mode == "hero")
	disp_submenu.set_item_checked(3, _display_mode == "strip")
	disp_submenu.id_pressed.connect(_on_display_mode_menu_pressed)
	menu.add_child(disp_submenu)
	menu.add_submenu_item(Lang.t("menu.display_mode"), "DisplayModeSubmenu", 900)

	if _display_mode == "fish_tank":
		var tank_submenu := PopupMenu.new()
		UITheme.style_popup_menu(tank_submenu)
		tank_submenu.window_input.connect(_on_menu_window_input.bind(tank_submenu))
		tank_submenu.name = "TankSubmenu"
		var tanks: Array = IdleSystem.get_tanks() if IdleSystem != null else []
		var active_id: String = IdleSystem.get_active_tank_id() if IdleSystem != null else ""
		for i in range(tanks.size()):
			var tname: String = str(tanks[i].get("name", "")).strip_edges()
			var label: String = tname if tname != "" else (Lang.t("menu.tank") + " " + str(i + 1))
			tank_submenu.add_check_item(label, i)
			tank_submenu.set_item_checked(i, str(tanks[i].get("id", "")) == active_id)
		tank_submenu.add_separator()
		tank_submenu.add_item(Lang.t("menu.tank_new"), 1000)
		if IdleSystem != null and IdleSystem.is_tank_limit_reached():
			tank_submenu.set_item_disabled(tank_submenu.get_item_index(1000), true)
		tank_submenu.add_item(Lang.t("menu.tank_rename"), 1002)
		var active_empty: bool = IdleSystem != null and IdleSystem.get_active_tank().get("fish", []).is_empty()
		if tanks.size() > 1 and active_empty:
			tank_submenu.add_item(Lang.t("menu.tank_delete"), 1001)
		tank_submenu.id_pressed.connect(_on_tank_menu_pressed)
		menu.add_child(tank_submenu)
		menu.add_submenu_item(Lang.t("menu.tank"), "TankSubmenu", 901)

	if _display_mode == "hero":
		var card_submenu := PopupMenu.new()
		UITheme.style_popup_menu(card_submenu)
		card_submenu.window_input.connect(_on_menu_window_input.bind(card_submenu))
		card_submenu.name = "HeroCardSubmenu"
		card_submenu.add_item(Lang.t("menu.hero_cards.add_stocks"), 90)
		card_submenu.add_item(Lang.t("menu.hero_cards.add_crypto"), 91)
		card_submenu.add_separator()
		card_submenu.add_item(Lang.t("menu.hero_cards.reset"), 93)
		card_submenu.id_pressed.connect(_on_hero_card_menu_pressed)
		menu.add_child(card_submenu)
		menu.add_submenu_item(Lang.t("menu.hero_cards"), "HeroCardSubmenu", 902)

	if _display_mode == "fish_tank":
		var skin_submenu := PopupMenu.new()
		UITheme.style_popup_menu(skin_submenu)
		skin_submenu.window_input.connect(_on_menu_window_input.bind(skin_submenu))
		skin_submenu.name = "SkinSubmenu"
		skin_submenu.add_check_item(Lang.t("menu.fish_style.minimal"), 10)
		skin_submenu.add_check_item(Lang.t("menu.fish_style.art"), 11)
		var current_skin: String = "minimal"
		if IdleSystem != null:
			current_skin = IdleSystem.get_fish_skin()
		skin_submenu.set_item_checked(0, current_skin == "minimal")
		skin_submenu.set_item_checked(1, current_skin == "artistic")
		skin_submenu.add_separator()
		skin_submenu.add_item(Lang.t("menu.fish_style.art_setup"), 12)
		skin_submenu.id_pressed.connect(_on_skin_menu_pressed)
		menu.add_child(skin_submenu)
		menu.add_submenu_item(Lang.t("menu.fish_style"), "SkinSubmenu", 903)

		var show_labels: bool = true
		if IdleSystem != null:
			show_labels = IdleSystem.get_show_ticker_labels()
		menu.add_check_item(Lang.t("menu.show_labels"), 50)
		menu.set_item_checked(menu.get_item_index(50), show_labels)

	var on_top: bool = false
	if IdleSystem != null:
		on_top = IdleSystem.get_always_on_top()
	menu.add_check_item(Lang.t("menu.always_on_top"), 1)
	menu.set_item_checked(menu.get_item_index(1), on_top)

	menu.add_separator()
	var settings_submenu := PopupMenu.new()
	UITheme.style_popup_menu(settings_submenu)
	settings_submenu.window_input.connect(_on_menu_window_input.bind(settings_submenu))
	settings_submenu.name = "SettingsSubmenu"

	settings_submenu.add_item(Lang.t("menu.appearance"), 35)
	settings_submenu.add_item(Lang.t("menu.api_settings"), 30)
	settings_submenu.add_item(Lang.t("menu.price_record"), 32)
	settings_submenu.add_item(Lang.t("menu.alert_settings"), 33)
	settings_submenu.add_item(Lang.t("menu.alert_history"), 34)
	settings_submenu.id_pressed.connect(_on_settings_menu_pressed)
	menu.add_child(settings_submenu)
	menu.add_submenu_item(Lang.t("menu.settings"), "SettingsSubmenu", 904)

	menu.add_separator()
	menu.add_item(Lang.t("menu.about"), 31)
	menu.add_item(Lang.t("menu.quit"), 0)
	add_child(menu)
	menu.id_pressed.connect(_on_menu_pressed.bind(row_item_id))
	menu.close_requested.connect(func(): menu.queue_free())
	var menu_pos := Vector2i(local_pos) + Vector2i(get_window().position)
	if _display_mode == "strip":
		menu_pos.y = get_window().position.y + int(size.y) + 2
	_popup_menu_clamped(menu, menu_pos)


func _is_appearance_dialog(dialog: Window) -> bool:
	return dialog != null and dialog.get_script() == AppearanceSettingsDialogScript

func _on_color_tone_changed(new_tone: String) -> void:
	UITheme.set_tone(new_tone)
	if _active_dialog != null and is_instance_valid(_active_dialog) \
			and not _is_appearance_dialog(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null
	queue_redraw()

func _on_language_changed(_new_lang: String) -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog) \
			and not _is_appearance_dialog(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null
	if _after_hours_dialog != null and is_instance_valid(_after_hours_dialog):
		_after_hours_dialog.queue_free()
		_after_hours_dialog = null
	queue_redraw()

func _on_alert_fired(record: Dictionary) -> void:
	queue_redraw()

	if _display_mode != "fish_tank":
		return
	var market: String = str(record.get("market", ""))
	var key: String = market + ":" + str(record.get("symbol", ""))
	for child in get_children():
		if child.has_method("spawn_alert_bubble") and str(child.get("ticker_key")) == key:
			child.spawn_alert_bubble(record)
			break

func _on_alert_history_changed() -> void:
	queue_redraw()

func _on_tank_menu_pressed(id: int) -> void:
	if not _menu_allows():
		return
	if IdleSystem == null:
		return
	if id == 1000:
		_open_tank_name_dialog("create")
		return
	if id == 1002:
		_open_tank_name_dialog("rename")
		return
	if id == 1001:
		IdleSystem.delete_tank(IdleSystem.get_active_tank_id())
		return
	var tanks: Array = IdleSystem.get_tanks()
	if id < 0 or id >= tanks.size():
		return
	IdleSystem.set_active_tank(str(tanks[id].get("id", "")))

func _open_tank_name_dialog(mode: String) -> void:
	if IdleSystem == null:
		return
	if mode == "create" and IdleSystem.is_tank_limit_reached():
		return
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null
	var current_name: String = ""
	if mode == "rename":
		current_name = str(IdleSystem.get_active_tank().get("name", ""))
	var dialog = TankNameDialogScript.new()
	dialog.setup(mode, current_name)
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.name_submitted.connect(_on_tank_name_submitted.bind(mode))
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	dialog.canceled.connect(_on_about_dialog_closed.bind(dialog))
	_popup_clamped(dialog)

func _open_group_dialog(item_id: String) -> void:
	if IdleSystem == null:
		return
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null
	var item: Dictionary = IdleSystem.get_numeric_item(item_id)
	if item.is_empty():
		return
	var dialog = TankNameDialogScript.new()
	dialog.setup("group", str(item.get("group", "")))
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.name_submitted.connect(_on_group_submitted.bind(item_id))
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	dialog.canceled.connect(_on_about_dialog_closed.bind(dialog))
	_popup_clamped(dialog)

func _on_group_submitted(group_name: String, item_id: String) -> void:
	_active_dialog = null
	if IdleSystem != null:
		IdleSystem.set_numeric_item_group(item_id, group_name)
		queue_redraw()

func _on_tank_name_submitted(tank_name: String, mode: String) -> void:
	_active_dialog = null
	if IdleSystem == null:
		return
	if mode == "rename":
		IdleSystem.rename_tank(IdleSystem.get_active_tank_id(), tank_name)
		queue_redraw()
	else:
		var t := IdleSystem.create_tank(tank_name)
		if not t.is_empty():
			IdleSystem.set_active_tank(str(t.get("id", "")))

func _on_skin_menu_pressed(id: int) -> void:
	if not _menu_allows():
		return
	if id == 12:
		_open_fish_art_dialog()
		return
	var skin: String = ""
	if id == 10:
		skin = "minimal"
	elif id == 11:
		skin = "artistic"
	else:
		return
	if IdleSystem == null:
		return
	if IdleSystem.get_fish_skin() == skin:
		return
	if skin == "artistic":
		FishArt.reload()
		if not FishArt.is_available():
			_open_fish_art_dialog()
			return
	_perform_skin_switch(skin)

func _on_display_mode_menu_pressed(id: int) -> void:
	if not _menu_allows():
		return
	var mode: String = ""
	if id == 60:
		mode = "fish_tank"
	elif id == 61:
		mode = "numeric"
	elif id == 62:
		mode = "hero"
	elif id == 63:
		mode = "strip"
	else:
		return
	if IdleSystem == null:
		return
	if IdleSystem.get_display_mode() == mode:
		return
	IdleSystem.save_display_mode(mode)

func _on_display_mode_changed(new_mode: String) -> void:
	if new_mode == _display_mode:
		return
	_save_window_state()
	_display_mode = new_mode
	_apply_window_geometry_for_mode(new_mode)
	_apply_display_mode()

func _active_list_panel() -> RefCounted:
	match _display_mode:
		"numeric":
			return _numeric_panel
		"hero":
			return _hero_panel
		"strip":
			return _strip_panel
	return null

func _on_hero_card_menu_pressed(id: int) -> void:
	if not _menu_allows():
		return
	if IdleSystem == null:
		return
	match id:
		90:
			IdleSystem.add_hero_panel("stocks")
		91:
			IdleSystem.add_hero_panel("crypto")
		93:
			IdleSystem.reset_hero_panels()
		_:
			return
	_resize_hero_to_fit()
	queue_redraw()

func _default_window_size(mode: String, screen_size: Vector2i) -> Vector2i:
	if mode == "strip":
		return Vector2i(screen_size.x, _strip_rows_for(0) * STRIP_BAR_HEIGHT)
	if mode == "hero":
		var hw: int = clampi(_hero_panel_count() * HERO_PANEL_W, HERO_PANEL_W, int(screen_size.x * 0.9))
		var cap: int = mini(_hero_max_height(hw), int(screen_size.y * MAX_WINDOW_SIZE_RATIO))
		var hh: int = clampi(int(_hero_panel_width(hw) * 1.2) + 44, 190, cap)
		return Vector2i(hw, hh)
	if mode == "numeric":
		var nw: int = clampi(int(screen_size.x * NUMERIC_WIDTH_RATIO), NUMERIC_MIN_WIDTH, NUMERIC_MAX_WIDTH)
		var nh: int = maxi(int(screen_size.y * NUMERIC_HEIGHT_RATIO), NUMERIC_MIN_HEIGHT)
		nh = mini(nh, int(screen_size.y * MAX_WINDOW_SIZE_RATIO))
		return Vector2i(nw, nh)
	var lw: int = int(screen_size.x * WINDOW_WIDTH_RATIO)
	return Vector2i(lw, int(lw * WINDOW_HEIGHT_RATIO))

func _corner_position(screen_pos: Vector2i, screen_size: Vector2i, win_size: Vector2i) -> Vector2i:
	return Vector2i(
		screen_pos.x + screen_size.x - win_size.x - SCREEN_EDGE_MARGIN,
		screen_pos.y + screen_size.y - win_size.y - SCREEN_EDGE_MARGIN
	)

func _mode_position(mode: String, screen_pos: Vector2i, screen_size: Vector2i, win_size: Vector2i) -> Vector2i:
	if mode == "strip":
		return screen_pos
	return _corner_position(screen_pos, screen_size, win_size)

func _apply_window_geometry_for_mode(mode: String) -> void:
	var window := get_window()
	if window == null:
		return
	var screen_id := DisplayServer.get_screen_from_rect(Rect2i(window.position, window.size))
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_id)
	var screen_size := DisplayServer.screen_get_size(screen_id)

	var def_size := _default_window_size(mode, screen_size)
	var target_size := def_size
	var target_pos := screen_pos if mode == "strip" else Vector2i(window.position)

	if IdleSystem != null and mode != "strip" and mode != "hero":
		var saved: Dictionary = IdleSystem.get_window_state(mode)
		if not saved.is_empty():
			var s_size := Vector2i(int(saved.get("w", def_size.x)), int(saved.get("h", def_size.y)))
			var s_pos := Vector2i(int(saved.get("x", target_pos.x)), int(saved.get("y", target_pos.y)))
			if DisplayServer.get_screen_from_rect(Rect2i(s_pos, s_size)) >= 0:
				target_size = s_size
				target_pos = s_pos

	if mode != "strip":
		target_pos.x = clampi(target_pos.x, screen_pos.x, screen_pos.x + screen_size.x - target_size.x)
		target_pos.y = clampi(target_pos.y, screen_pos.y, screen_pos.y + screen_size.y - target_size.y)

	window.size = target_size
	window.position = target_pos
	queue_redraw()

func _apply_display_mode() -> void:
	if _display_mode == "fish_tank":
		_numeric_panel = null
		_hero_panel = null
		_strip_panel = null
		_rebuild_fish_nodes()
	else:
		for child in get_children():
			if child.has_method("is_point_inside") and child.has_method("spawn_bubble"):
				child.queue_free()
		_numeric_panel = NumericPanelScript.new() if _display_mode == "numeric" else null
		_hero_panel = HeroCardPanelScript.new() if _display_mode == "hero" else null
		_strip_panel = StripPanelScript.new() if _display_mode == "strip" else null
		if _moon_icon != null:
			_moon_icon.set_visibility(0.0, size)
		_moon_alpha = 0.0
	queue_redraw()

func _strip_rows_for(_n: int) -> int:
	var list: Array = IdleSystem.get_numeric_list() if IdleSystem != null else []
	return clampi(StripPanelScript.rows_for(list), 1, STRIP_MAX_ROWS)

func _resize_strip_to_fit() -> void:
	if _display_mode != "strip":
		return
	var window := get_window()
	if window == null:
		return
	var target_h: int = _strip_rows_for(0) * STRIP_BAR_HEIGHT
	if window.size.y != target_h:
		window.size = Vector2i(window.size.x, target_h)

func _hero_panel_count() -> int:
	if IdleSystem == null:
		return 1
	return clampi(IdleSystem.get_hero_panels().size(), 1, HERO_MAX_PANELS)

func _hero_panel_width(win_w: int) -> float:
	var n: int = _hero_panel_count()
	return float(win_w - 44 - (n - 1) * 16) / float(maxi(n, 1))

func _hero_max_height(win_w: int) -> int:
	return int(_hero_panel_width(win_w) * HERO_MAX_ASPECT) + 44

func _resize_hero_to_fit() -> void:
	if _display_mode != "hero":
		return
	var window := get_window()
	if window == null:
		return
	var screen_id := DisplayServer.get_screen_from_rect(Rect2i(window.position, window.size))
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()
	var screen_w: int = DisplayServer.screen_get_size(screen_id).x
	var target_w: int = clampi(_hero_panel_count() * HERO_PANEL_W, HERO_PANEL_W, int(screen_w * 0.9))
	var target_h: int = clampi(window.size.y, MIN_WINDOW_SIZE.y, _hero_max_height(target_w))
	if window.size != Vector2i(target_w, target_h):
		window.size = Vector2i(target_w, target_h)

func _on_numeric_data_changed() -> void:
	if _display_mode == "strip":
		_resize_strip_to_fit()
	elif _display_mode == "hero":
		_resize_hero_to_fit()
	if _display_mode != "fish_tank":
		queue_redraw()

func _popup_menu_clamped(menu: PopupMenu, want_pos: Vector2i) -> void:
	var msize := Vector2i(menu.get_contents_minimum_size())
	var pos := want_pos
	if msize.x > 0 and msize.y > 0:
		var screen: int = DisplayServer.get_screen_from_rect(Rect2i(want_pos, Vector2i(2, 2)))
		if screen < 0:
			screen = get_window().current_screen
		var usable := DisplayServer.screen_get_usable_rect(screen)
		pos.x = clampi(pos.x, usable.position.x,
			maxi(usable.position.x, usable.position.x + usable.size.x - msize.x))
		pos.y = clampi(pos.y, usable.position.y,
			maxi(usable.position.y, usable.position.y + usable.size.y - msize.y))
	menu.position = pos
	menu.popup()

func _guard_menu(menu: PopupMenu) -> void:
	_menu_btn = MOUSE_BUTTON_LEFT
	menu.window_input.connect(_on_menu_window_input.bind(menu))

func _on_menu_window_input(event: InputEvent, _menu: PopupMenu) -> void:
	if event is InputEventKey and event.pressed:
		_menu_btn = MOUSE_BUTTON_LEFT
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	_menu_btn = event.button_index

func _menu_allows() -> bool:
	if _menu_btn == MOUSE_BUTTON_LEFT:
		return true
	print("[FishTank] Menu activation ignored (button ", _menu_btn, ")")
	return false

func _on_settings_menu_pressed(id: int) -> void:
	if not _menu_allows():
		return
	_on_menu_pressed(id)

func _on_menu_pressed(id: int, row_item_id: String = "") -> void:
	if not _menu_allows():
		return
	if id == 70:
		if row_item_id != "" and IdleSystem != null:
			IdleSystem.remove_numeric_item(row_item_id)
		return
	if id == 71:
		if row_item_id != "":
			_open_group_dialog(row_item_id)
		return
	if id == 73:
		_open_hero_edit_dialog(_ctx_hero_panel)
		return
	if id == 74:
		if IdleSystem != null and _ctx_hero_panel >= 0 and IdleSystem.remove_hero_panel(_ctx_hero_panel):
			_resize_hero_to_fit()
			queue_redraw()
		return
	if id == 0:
		print("[FishTank] User selected Quit")
		_quit_and_save()
	elif id == 1:
		var window := get_window()
		var new_state: bool = not window.always_on_top
		window.always_on_top = new_state
		if IdleSystem != null:
			IdleSystem.save_always_on_top(new_state)
		print("[FishTank] Always on top = ", new_state)
	elif id == 30:
		_open_api_key_dialog()
	elif id == 35:
		_open_appearance_dialog()
	elif id == 32:
		_open_price_record_dialog()
	elif id == 33:
		_open_alert_settings_dialog()
	elif id == 34:
		_open_alert_history_dialog()
	elif id == 31:
		_open_about_dialog()
	elif id == 50:
		if IdleSystem != null:
			IdleSystem.save_show_ticker_labels(not IdleSystem.get_show_ticker_labels())

func _open_alert_settings_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = AlertSettingsDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _open_alert_history_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = AlertHistoryDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _open_price_record_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = PriceRecordSettingsDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _open_appearance_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = AppearanceSettingsDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _open_fish_art_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = FishArtDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	dialog.art_ready.connect(_on_fish_art_ready)
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _on_fish_art_ready() -> void:
	if IdleSystem != null and IdleSystem.get_fish_skin() != "artistic":
		_perform_skin_switch("artistic")

func _open_about_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = AboutDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _open_hero_edit_dialog(index: int) -> void:
	if IdleSystem == null or index < 0:
		return
	var panels: Array = IdleSystem.get_hero_panels()
	if index >= panels.size():
		return
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null
	var dialog = HeroCardEditDialogScript.new()
	dialog.setup(index, str(panels[index]["market"]), panels[index].get("syms", []), str(panels[index].get("title", "")), int(panels[index].get("interval", 60)))
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.saved.connect(_on_hero_card_saved)
	dialog.confirmed.connect(_on_about_dialog_closed.bind(dialog))
	_popup_clamped(dialog)

func _on_hero_card_saved(index: int, syms: Array, title: String, interval: int) -> void:
	if IdleSystem != null:
		IdleSystem.set_hero_panel_content(index, syms, title, interval)
		_resize_hero_to_fit()
		queue_redraw()

func _on_about_dialog_closed(dialog: Window) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()

func _open_api_key_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = ApiKeySettingsDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.confirmed.connect(_on_api_key_dialog_closed.bind(dialog))
	dialog.canceled.connect(_on_api_key_dialog_closed.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _on_api_key_dialog_closed(dialog: Window) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()


func _open_onboarding_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog = OnboardingDialogScript.new()
	get_tree().root.add_child(dialog)
	_active_dialog = dialog
	dialog.request_guide.connect(_on_onboarding_request_guide.bind(dialog))
	dialog.request_settings.connect(_on_onboarding_request_settings.bind(dialog))
	dialog.skipped.connect(_on_onboarding_skipped.bind(dialog))
	if dialog.has_method("set_tank_size"):
		dialog.set_tank_size(Vector2i(size))
	_popup_clamped(dialog)

func _on_onboarding_request_guide(dialog: Window) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()
	_open_guide_then_settings()

func _on_onboarding_request_settings(dialog: Window) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()
	_open_api_key_dialog()

func _on_onboarding_skipped(dialog: Window) -> void:
	if _active_dialog == dialog:
		_active_dialog = null
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()
	_onboarding_skipped = true
	queue_redraw()
	print("[FishTank] Onboarding skipped — status bar shows reminder; settings still in right-click menu")

func _open_guide_then_settings() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var guide = ApiKeyGuideDialogScript.new()
	get_tree().root.add_child(guide)
	_active_dialog = guide
	guide.confirmed.connect(_on_guide_closed.bind(guide))
	guide.request_settings.connect(_on_guide_closed_open_settings.bind(guide))
	if guide.has_method("set_tank_size"):
		guide.set_tank_size(Vector2i(size))
	_popup_clamped(guide)

func _on_guide_closed(guide: Window) -> void:
	if _active_dialog == guide:
		_active_dialog = null
	if guide != null and is_instance_valid(guide):
		guide.queue_free()

func _on_guide_closed_open_settings(guide: Window) -> void:
	_on_guide_closed(guide)
	call_deferred("_open_api_key_dialog")

const SKIN_FADE_DURATION := 0.3

func _perform_skin_switch(new_skin: String) -> void:
	var fishes: Array = []
	for child in get_children():
		if child.has_method("is_point_inside") and child.has_method("spawn_bubble"):
			fishes.append(child)

	if fishes.is_empty():
		IdleSystem.save_fish_skin(new_skin)
		return

	var master := create_tween()
	master.tween_callback(_skin_fade_out_all.bind(fishes))
	master.tween_interval(SKIN_FADE_DURATION)
	master.tween_callback(_apply_skin_change.bind(new_skin))
	master.tween_callback(_skin_fade_in_all.bind(fishes))

func _skin_fade_out_all(fishes: Array) -> void:
	for fish in fishes:
		if not is_instance_valid(fish):
			continue
		var tw := create_tween()
		tw.tween_property(fish, "modulate:a", 0.0, SKIN_FADE_DURATION)

func _apply_skin_change(new_skin: String) -> void:
	IdleSystem.save_fish_skin(new_skin)

func _skin_fade_in_all(fishes: Array) -> void:
	for fish in fishes:
		if not is_instance_valid(fish):
			continue
		var tw := create_tween()
		tw.tween_property(fish, "modulate:a", 1.0, SKIN_FADE_DURATION)

func _on_fish_skin_changed(_new_skin: String) -> void:
	pass

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_window_state()
		get_tree().quit()

func _save_window_state() -> void:
	if IdleSystem == null:
		return
	if not is_inside_tree():
		return
	var window := get_window()
	if window == null:
		return
	IdleSystem.save_window_state(window.position, window.size, _display_mode)
	print("[FishTank] Window state saved (", _display_mode, ")")

func _quit_and_save() -> void:
	_save_window_state()
	get_tree().quit()

func _show_fish_context_menu(local_pos: Vector2, fish: Node) -> void:
	var menu := PopupMenu.new()
	UITheme.style_popup_menu(menu)
	_guard_menu(menu)
	menu.add_item(Lang.t("menu.set_alert"), 1)

	var skin: String = IdleSystem.get_fish_skin() if IdleSystem != null else "minimal"
	if skin == "artistic":
		var species_submenu := PopupMenu.new()
		UITheme.style_popup_menu(species_submenu)
		species_submenu.window_input.connect(_on_menu_window_input.bind(species_submenu))
		species_submenu.name = "FishSpeciesSubmenu"
		var current_species: String = "Anchovy"
		if IdleSystem != null:
			for f in IdleSystem.get_fish_list():
				if f.get("id", "") == fish.fish_id:
					current_species = f.get("species", "Anchovy")
					break
		var species_list: Array = FishSpecies.SPECIES_LIST
		for i in range(species_list.size()):
			var s: Dictionary = species_list[i]
			species_submenu.add_check_item(FishSpecies.get_display_name(s.id), 100 + i)
			species_submenu.set_item_checked(i, s.id == current_species)
		species_submenu.id_pressed.connect(_on_species_menu_pressed.bind(fish))
		menu.add_child(species_submenu)
		menu.add_submenu_item(Lang.t("menu.change_species"), "FishSpeciesSubmenu", 905)
	else:
		var design_submenu := PopupMenu.new()
		UITheme.style_popup_menu(design_submenu)
		design_submenu.window_input.connect(_on_menu_window_input.bind(design_submenu))
		design_submenu.name = "FishDesignSubmenu"
		var current_design := _effective_design(fish.fish_id)
		for i in range(LottieFish.DESIGN_COUNT):
			design_submenu.add_check_item(LottieFish.design_name(i), 200 + i)
			design_submenu.set_item_checked(i, i == current_design)
		design_submenu.id_pressed.connect(_on_design_menu_pressed.bind(fish))
		menu.add_child(design_submenu)
		menu.add_submenu_item(Lang.t("menu.change_design"), "FishDesignSubmenu", 906)

	add_child(menu)
	menu.id_pressed.connect(_on_fish_menu_pressed.bind(fish))
	menu.close_requested.connect(func(): menu.queue_free())
	_popup_menu_clamped(menu, Vector2i(local_pos) + Vector2i(get_window().position))

func _on_fish_menu_pressed(id: int, _fish: Node) -> void:
	if not _menu_allows():
		return
	if id == 1:
		_open_alert_settings_dialog()

func _on_species_menu_pressed(id: int, fish: Node) -> void:
	if not _menu_allows():
		return
	if id < 100 or id >= 100 + FishSpecies.SPECIES_LIST.size():
		return
	if IdleSystem == null:
		return
	var idx: int = id - 100
	var s: Dictionary = FishSpecies.SPECIES_LIST[idx]
	IdleSystem.update_fish_species(fish.fish_id, s.id)

func _effective_design(fish_id: String) -> int:
	if IdleSystem != null:
		for f in IdleSystem.get_fish_list():
			if f.get("id", "") == fish_id:
				var d := int(f.get("design", -1))
				if d >= 0 and d < LottieFish.DESIGN_COUNT:
					return d
				break
	return abs(int(fish_id.hash())) % LottieFish.DESIGN_COUNT

func _on_design_menu_pressed(id: int, fish: Node) -> void:
	if not _menu_allows():
		return
	if id < 200 or id >= 200 + LottieFish.DESIGN_COUNT:
		return
	if IdleSystem != null:
		IdleSystem.update_fish_design(fish.fish_id, id - 200)

func _show_create_fish_dialog() -> void:
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var dialog := AcceptDialog.new()
	dialog.set_script(CreateFishDialogScript)
	var skin: String = IdleSystem.get_fish_skin() if IdleSystem != null else "minimal"
	if dialog.has_method("set_hide_species"):
		dialog.set_hide_species(_display_mode != "fish_tank")
	if dialog.has_method("set_show_design"):
		dialog.set_show_design(_display_mode == "fish_tank" and skin == "minimal")
	if dialog.has_method("set_show_species"):
		dialog.set_show_species(_display_mode == "fish_tank" and skin == "artistic")
	add_child(dialog)
	_active_dialog = dialog
	dialog.tickers_committed.connect(_on_tickers_committed)
	dialog.canceled.connect(func(): _active_dialog = null)
	_popup_clamped(dialog, false)

func _on_tickers_committed(market: String, symbols: Array, design: int = -1, species: String = "") -> void:
	_active_dialog = null
	if IdleSystem == null:
		return
	_commit_limit_blocked = false
	_commit_tank_full = false
	_commit_duplicates.clear()
	var sp: String = species if species != "" else FishSpecies.DEFAULT_SPECIES
	var added := false
	for sym in symbols:
		var s := str(sym)
		var result: Dictionary
		if _display_mode != "fish_tank":
			result = IdleSystem.add_numeric_item(s, market, s)
		else:
			result = IdleSystem.add_fish(s, market, s, sp, design)
		if not result.is_empty():
			added = true
	if added:
		_maybe_prompt_price_stream()
		queue_redraw()
	if _commit_tank_full:
		_show_notice(Lang.t("add.tank_full", {"max": IdleSystem.MAX_FISH_PER_TANK}))
	elif _commit_limit_blocked:
		_show_notice(Lang.t("add.limit_reached", {"max": IdleSystem.MAX_TOTAL_SYMBOLS}))
	elif not _commit_duplicates.is_empty():
		_show_notice(Lang.t("add.duplicate_skipped", {"symbols": ", ".join(_commit_duplicates)}))

func _show_notice(msg: String) -> void:
	var notice := AcceptDialog.new()
	notice.title = Lang.t("dialog.notice")
	notice.dialog_text = msg
	notice.dialog_autowrap = true
	notice.min_size = Vector2i(300, 0)
	UITheme.style_dialog(notice)
	add_child(notice)
	notice.confirmed.connect(func(): notice.queue_free())
	notice.canceled.connect(func(): notice.queue_free())
	_popup_clamped(notice, false)

func _show_delete_fish_dialog() -> void:
	if IdleSystem == null:
		return
	if _active_dialog != null and is_instance_valid(_active_dialog):
		_active_dialog.queue_free()
		_active_dialog = null

	var entries: Array = []
	if _display_mode != "fish_tank":
		for it in IdleSystem.get_numeric_list():
			entries.append({"id": str(it.get("id", "")), "symbol": str(it.get("symbol", "")), "nickname": str(it.get("nickname", "")), "market": str(it.get("market", "stocks"))})
	else:
		for f in IdleSystem.get_active_tank().get("fish", []):
			entries.append({"id": str(f.get("id", "")), "symbol": str(f.get("symbol", "")), "nickname": str(f.get("nickname", "")), "market": str(f.get("market", "stocks"))})

	var dialog := AcceptDialog.new()
	dialog.set_script(DeleteFishDialogScript)
	dialog.setup(IdleSystem.get_context_market(), entries)
	add_child(dialog)
	_active_dialog = dialog
	dialog.tickers_deleted.connect(_on_tickers_deleted)
	dialog.canceled.connect(func(): _active_dialog = null)
	_popup_clamped(dialog, false)

func _on_tickers_deleted(ids: Array) -> void:
	_active_dialog = null
	if IdleSystem == null:
		return
	for id in ids:
		if _display_mode != "fish_tank":
			IdleSystem.remove_numeric_item(str(id))
		else:
			IdleSystem.remove_fish(str(id))
	queue_redraw()

func _popup_clamped(dialog: Window, _on_parent: bool = true) -> void:
	if dialog.has_method("popup_centered_on_parent"):
		dialog.popup_centered_on_parent()
		return
	var main_win := get_window()
	if dialog.get_parent() != main_win:
		var p := dialog.get_parent()
		if p != null:
			p.remove_child(dialog)
		main_win.add_child(dialog)
	dialog.reset_size()
	var dsize := Vector2i(dialog.size)
	if dsize.x <= 0:
		dsize.x = maxi(dialog.min_size.x, 240)
	if dsize.y <= 0:
		dsize.y = maxi(dialog.min_size.y, 120)
	dialog.popup_centered(dsize)

func _maybe_prompt_price_stream() -> void:
	if IdleSystem == null or IdleSystem.is_price_stream_prompted():
		return
	IdleSystem.mark_price_stream_prompted()

	var dialog := ConfirmationDialog.new()
	dialog.title = Lang.t("price_rec.prompt_title")
	dialog.dialog_text = Lang.t("price_rec.prompt_body")
	dialog.dialog_autowrap = true
	dialog.get_ok_button().text = Lang.t("price_rec.prompt_yes")
	dialog.get_cancel_button().text = Lang.t("price_rec.prompt_no")
	var w: int = clampi(int(size.x) - 24, 220, 360)
	dialog.min_size = Vector2i(w, 160)
	add_child(dialog)
	dialog.confirmed.connect(_on_price_prompt_yes.bind(dialog))
	dialog.canceled.connect(_on_price_prompt_dismiss.bind(dialog))
	_popup_clamped(dialog, false)

func _on_price_prompt_yes(dialog: Window) -> void:
	if IdleSystem != null:
		IdleSystem.save_price_stream_enabled(true)
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()

func _on_price_prompt_dismiss(dialog: Window) -> void:
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()

func _show_first_after_hours_dialog() -> void:
	if _after_hours_dialog != null and is_instance_valid(_after_hours_dialog):
		return

	var dialog := AcceptDialog.new()
	dialog.title = Lang.t("after_hours.title")
	dialog.dialog_text = Lang.t("after_hours.body")
	dialog.get_ok_button().text = Lang.t("after_hours.ok")

	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(clampi(int(size.x) - 24, 240, 360), 0)

	add_child(dialog)
	_after_hours_dialog = dialog
	dialog.confirmed.connect(_on_after_hours_dialog_closed)
	dialog.canceled.connect(_on_after_hours_dialog_closed)
	_popup_clamped(dialog, false)

func _on_after_hours_dialog_closed() -> void:
	if IdleSystem != null:
		IdleSystem.mark_first_after_hours_done()
	if _after_hours_dialog != null and is_instance_valid(_after_hours_dialog):
		_after_hours_dialog.queue_free()
	_after_hours_dialog = null
