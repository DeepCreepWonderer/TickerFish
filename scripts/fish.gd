extends Node2D
const UITheme := preload("res://scripts/ui_theme.gd")
## 鱼精灵:游动动画、按涨跌上色、吐泡泡与标签。

@export var ticker_key: String = "stocks:AAPL"
@export var market: String = "stocks"
@export var fish_id: String = ""
@export var nickname: String = ""
@export var fish_width_ratio: float = 0.12
@export var fish_aspect_ratio: float = 0.5
@export var fish_size_scale_ratio: float = 3.0
const FISH_BASE_TANK_WIDTH := 384.0

const BASE_SPEED := 40.0
const SPEED_MULT_BOOM := 1.6
const SPEED_MULT_BIG_UP := 1.35
const SPEED_MULT_SMALL_UP := 1.15
const SPEED_MULT_FLAT := 1.0
const SPEED_MULT_SMALL_DOWN := 0.85
const SPEED_MULT_BIG_DOWN := 0.65
const SPEED_MULT_CRASH := 0.4

const COLOR_BOOM := Color(1.0, 0.85, 0.2)
const COLOR_BIG_UP := Color(0.2, 0.85, 0.3)
const COLOR_SMALL_UP := Color(0.55, 0.9, 0.55)
const COLOR_FLAT := Color(0.7, 0.7, 0.7)
const COLOR_SMALL_DOWN := Color(0.95, 0.6, 0.6)
const COLOR_BIG_DOWN := Color(0.9, 0.3, 0.3)
const COLOR_CRASH := Color(0.55, 0.2, 0.55)

const TURN_SMOOTHNESS := 3.0
const RANDOM_TURN_INTERVAL := 2.5

const VERTICAL_PADDING_RATIO := 0.10

const AVOID_RADIUS_MULT := 1.5
const AVOID_STRENGTH := 2.5

const SLEEP_CHECK_INTERVAL := 1.0
const SLEEP_SPEED_MULT := 0.35
const SLEEP_DESAT_AMOUNT := 0.55
const SLEEP_DARKEN := 0.15
const ZZZ_SPAWN_INTERVAL := 1.8
const SLEEP_TRANSITION_DURATION := 1.5

const BubbleScript := preload("res://scripts/bubble.gd")
const ZzzScript := preload("res://scripts/zzz_particle.gd")
const AmbientBubbleScript := preload("res://scripts/ambient_bubble.gd")

const AMBIENT_BUBBLE_INTERVAL_MIN := 8.0
const AMBIENT_BUBBLE_INTERVAL_MAX := 12.0
const AMBIENT_BUBBLE_FLAT_THRESHOLD := 0.05

var _velocity: Vector2 = Vector2.ZERO
var _target_direction: Vector2 = Vector2.RIGHT
var _current_color: Color = COLOR_FLAT
var _speed: float = BASE_SPEED
var _fish_size: Vector2 = Vector2(40, 20)
var _random_turn_timer: float = 0.0

var _tank_size: Vector2 = Vector2.ZERO

var _active_bubble: Node2D = null

var _is_sleeping: bool = false
var _sleep_transition: float = 0.0
var _sleep_check_timer: float = 0.0
var _zzz_spawn_timer: float = 0.0

var _last_direction: int = 0
var _last_change_pct: float = 0.0
var _ambient_bubble_timer: float = 0.0
var _ambient_bubble_next: float = 0.0

func _ready() -> void:
	randomize()
	var angle := randf() * TAU
	_target_direction = Vector2(cos(angle), sin(angle)).normalized()
	_velocity = _target_direction * BASE_SPEED

	_refresh_sleep_state()
	_sleep_transition = 1.0 if _is_sleeping else 0.0

	_ambient_bubble_next = randf_range(AMBIENT_BUBBLE_INTERVAL_MIN, AMBIENT_BUBBLE_INTERVAL_MAX)
	_ambient_bubble_timer = randf() * _ambient_bubble_next

	if DataReader != null:
		DataReader.prices_updated.connect(_on_prices_updated)
		_on_prices_updated()

func _process(delta: float) -> void:
	var parent := get_parent() as Control
	if parent != null:
		_tank_size = parent.size
		var base_fish_w: float = FISH_BASE_TANK_WIDTH * fish_width_ratio
		var scale_factor: float = 1.0 + (_tank_size.x / FISH_BASE_TANK_WIDTH - 1.0) / fish_size_scale_ratio
		scale_factor = max(0.3, scale_factor)
		var fish_w: float = base_fish_w * scale_factor
		_fish_size = Vector2(fish_w, fish_w * fish_aspect_ratio)

	_sleep_check_timer += delta
	if _sleep_check_timer >= SLEEP_CHECK_INTERVAL:
		_sleep_check_timer = 0.0
		_refresh_sleep_state()

	var target_t: float = 1.0 if _is_sleeping else 0.0
	if SLEEP_TRANSITION_DURATION > 0.0:
		var step: float = delta / SLEEP_TRANSITION_DURATION
		if target_t > _sleep_transition:
			_sleep_transition = min(_sleep_transition + step, target_t)
		else:
			_sleep_transition = max(_sleep_transition - step, target_t)
	else:
		_sleep_transition = target_t

	if _sleep_transition > 0.5:
		_zzz_spawn_timer += delta
		if _zzz_spawn_timer >= ZZZ_SPAWN_INTERVAL:
			_zzz_spawn_timer = 0.0
			_spawn_zzz()

	if _sleep_transition <= 0.5:
		_ambient_bubble_timer += delta
		if _ambient_bubble_timer >= _ambient_bubble_next:
			_ambient_bubble_timer = 0.0
			_ambient_bubble_next = randf_range(AMBIENT_BUBBLE_INTERVAL_MIN, AMBIENT_BUBBLE_INTERVAL_MAX)
			_try_spawn_ambient_bubble()

	_random_turn_timer += delta
	if _random_turn_timer > RANDOM_TURN_INTERVAL:
		_random_turn_timer = 0.0
		var jitter := (randf() - 0.5) * PI * 0.5
		_target_direction = _target_direction.rotated(jitter)

	var avoid := _compute_avoidance()
	if avoid.length() > 0.01:
		_target_direction = (_target_direction + avoid * AVOID_STRENGTH * delta).normalized()

	var speed_mult: float = lerp(1.0, SLEEP_SPEED_MULT, _sleep_transition)
	var effective_speed: float = _speed * speed_mult

	_velocity = _velocity.lerp(_target_direction * effective_speed, delta * TURN_SMOOTHNESS)
	position += _velocity * delta

	var margin_x := _visual_half_width()
	var margin_y := _fish_size.y * 0.35
	var v_pad := _tank_size.y * VERTICAL_PADDING_RATIO

	if position.x < margin_x:
		position.x = margin_x
		_target_direction.x = abs(_target_direction.x)
	elif position.x > _tank_size.x - margin_x:
		position.x = _tank_size.x - margin_x
		_target_direction.x = -abs(_target_direction.x)

	var top_limit := v_pad + margin_y
	var bottom_limit := _tank_size.y - v_pad - margin_y
	if position.y < top_limit:
		position.y = top_limit
		_target_direction.y = abs(_target_direction.y)
	elif position.y > bottom_limit:
		position.y = bottom_limit
		_target_direction.y = -abs(_target_direction.y)

	_anim_time += delta

	queue_redraw()

func _compute_avoidance() -> Vector2:
	var parent := get_parent()
	if parent == null:
		return Vector2.ZERO

	var avoid_radius := _fish_size.x * AVOID_RADIUS_MULT
	var push := Vector2.ZERO
	for sibling in parent.get_children():
		if sibling == self:
			continue
		if not sibling.has_method("is_point_inside"):
			continue
		var sib2d := sibling as Node2D
		if sib2d == null:
			continue
		var diff := position - sib2d.position
		var dist := diff.length()
		if dist > 0 and dist < avoid_radius:
			var strength := 1.6 - (dist / avoid_radius)
			push += diff.normalized() * strength
	return push

func _refresh_sleep_state() -> void:
	var should_sleep: bool = not MarketClock.is_market_awake(market)
	if should_sleep != _is_sleeping:
		_is_sleeping = should_sleep
		if _is_sleeping:
			_zzz_spawn_timer = ZZZ_SPAWN_INTERVAL
		print("[Fish] ", ticker_key, " ", "sleeping" if _is_sleeping else "awake",
			" (", MarketClock.debug_et_now_str(), ")")

func _spawn_zzz() -> void:
	var zzz := Node2D.new()
	zzz.set_script(ZzzScript)
	var facing_right := _velocity.x >= 0
	var head_x: float = _fish_size.x * 0.25 if facing_right else -_fish_size.x * 0.25
	zzz.position = Vector2(head_x, -_fish_size.y * 0.55)
	add_child(zzz)
	zzz.setup(_fish_size)

func _try_spawn_ambient_bubble() -> void:
	if _last_direction == 0:
		return
	if DataReader == null:
		return
	var data: Dictionary = DataReader.get_ticker(ticker_key)
	if data.is_empty():
		return

	var bubble := Node2D.new()
	bubble.set_script(AmbientBubbleScript)
	var facing_right := _velocity.x >= 0
	var head_x: float = _fish_size.x * 0.30 if facing_right else -_fish_size.x * 0.30
	bubble.position = Vector2(head_x, -_fish_size.y * 0.55)
	add_child(bubble)
	bubble.setup(_last_change_pct, _fish_size)

func _to_sleep_color(c: Color, amount: float) -> Color:
	if amount <= 0.0:
		return c
	var desat: float = SLEEP_DESAT_AMOUNT * amount
	var darken: float = SLEEP_DARKEN * amount
	var gray: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	var r: float = lerp(c.r, gray, desat)
	var g: float = lerp(c.g, gray, desat)
	var b: float = lerp(c.b, gray, desat)
	r = max(0.0, r - darken)
	g = max(0.0, g - darken)
	b = max(0.0, b - darken)
	return Color(r, g, b, c.a)

const SKIN_MINIMAL := "minimal"
const SKIN_ARTISTIC := "artistic"

func _draw() -> void:
	var skin: String = IdleSystem.get_fish_skin() if IdleSystem != null else SKIN_MINIMAL
	match skin:
		SKIN_MINIMAL:
			_draw_minimal()
		SKIN_ARTISTIC:
			_draw_artistic()
		_:
			_draw_minimal()

	if IdleSystem != null and IdleSystem.get_show_ticker_labels():
		_draw_ticker_label()

const LABEL_FONT_SIZE := 11
const LABEL_COLOR := Color(0.914, 0.929, 0.922, 1.0)
const LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.5)
const LABEL_SHADOW_OFFSET := Vector2(1.0, 1.0)
const LABEL_GAP_PX := 3.0

func _draw_ticker_label() -> void:
	var text: String = _get_label_text()
	if text == "":
		return
	var font: Font = UITheme.mono()
	if font == null:
		return
	var visual_half_h: float = _fish_size.y * 0.5
	var skin: String = IdleSystem.get_fish_skin() if IdleSystem != null else SKIN_MINIMAL
	if skin == SKIN_ARTISTIC:
		visual_half_h *= ARTISTIC_SIZE_MULT
	elif LottieFish.available():
		visual_half_h = LottieFish.label_offset(_get_design_index(), _fish_size.x * LottieFish.RENDER_SCALE)

	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var ascent: float = font.get_ascent(LABEL_FONT_SIZE)
	var draw_pos := Vector2(
		-text_size.x * 0.5,
		visual_half_h + LABEL_GAP_PX + ascent
	)
	var fade: float = lerp(1.0, 0.55, _sleep_transition)
	var sh: Color = LABEL_SHADOW
	sh.a *= fade
	draw_string(font, draw_pos + LABEL_SHADOW_OFFSET, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, sh)
	var c: Color = LABEL_COLOR
	c.a *= fade
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, c)

func _get_label_text() -> String:
	if nickname != "":
		return nickname
	var parts := ticker_key.split(":", true, 1)
	return parts[1] if parts.size() > 1 else ticker_key

var _design_idx: int = -1

func _get_design_index() -> int:
	if _design_idx < 0:
		var stored := -1
		if IdleSystem != null and fish_id != "":
			for f in IdleSystem.get_fish_list():
				if f.get("id", "") == fish_id:
					stored = int(f.get("design", -1))
					break
		if stored >= 0 and stored < LottieFish.DESIGN_COUNT:
			_design_idx = stored
		else:
			var key: String = fish_id if fish_id != "" else ticker_key
			_design_idx = abs(int(key.hash())) % LottieFish.DESIGN_COUNT
	return _design_idx

func _draw_minimal() -> void:
	if not LottieFish.available():
		_draw_minimal_legacy()
		return

	var facing_right := _velocity.x >= 0
	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2(-1, 1))

	var tint := _to_sleep_color(_current_color, _sleep_transition)
	var t := _sleep_transition
	var idx := _get_design_index()
	var render_w := _fish_size.x * LottieFish.RENDER_SCALE
	var rate := clampf(_speed / BASE_SPEED, 0.5, 1.7)
	if t < 0.999:
		LottieFish.draw_fish(self, idx, false, _anim_time, rate, render_w, tint, 1.0 - t)
	if t > 0.001:
		LottieFish.draw_fish(self, idx, true, _anim_time, 1.0, render_w, tint, t)

	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_minimal_legacy() -> void:
	var facing_right := _velocity.x >= 0
	var w := _fish_size.x
	var h := _fish_size.y

	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2(-1, 1))

	var body_color := _to_sleep_color(_current_color, _sleep_transition)

	var ellipse_pts := PackedVector2Array()
	var segments := 24
	for i in range(segments):
		var t := i / float(segments) * TAU
		ellipse_pts.append(Vector2(cos(t) * w * 0.4, sin(t) * h * 0.5))
	draw_colored_polygon(ellipse_pts, body_color)

	var tail_pts := PackedVector2Array([
		Vector2(-w * 0.4, 0),
		Vector2(-w * 0.5, -h * 0.5),
		Vector2(-w * 0.5, h * 0.5),
	])
	draw_colored_polygon(tail_pts, body_color)

	var eye_pos := Vector2(w * 0.18, -h * 0.18)
	var awake_a: float = 1.0 - _sleep_transition
	var asleep_a: float = _sleep_transition
	if awake_a > 0.01:
		var eye_radius: float = h * 0.13
		draw_circle(eye_pos, eye_radius, Color(1, 1, 1, awake_a))
		draw_circle(eye_pos + Vector2(eye_radius * 0.3, 0), eye_radius * 0.55, Color(0, 0, 0, awake_a))
	if asleep_a > 0.01:
		var eye_w: float = h * 0.22
		var eye_color := Color(0.15, 0.15, 0.2, 0.85 * asleep_a)
		draw_line(eye_pos + Vector2(-eye_w * 0.5, 0),
				  eye_pos + Vector2(eye_w * 0.5, 0),
				  eye_color, 1.6, true)

	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

const SPRITE_FRAME_W := 64
const SPRITE_FRAME_H := 32
const SPRITE_FRAMES_PER_ANIM := 8

const ARTISTIC_SIZE_MULT := 2.5

const ANIM_FPS_BOOM := 12.0
const ANIM_FPS_BIG_UP := 10.0
const ANIM_FPS_SMALL_UP := 9.0
const ANIM_FPS_FLAT := 8.0
const ANIM_FPS_SMALL_DOWN := 6.0
const ANIM_FPS_BIG_DOWN := 5.0
const ANIM_FPS_CRASH := 3.0

var _anim_time: float = 0.0

func _draw_artistic() -> void:
	var sheet: Texture2D = FishArt.sheet()
	if sheet == null:
		if IdleSystem != null and IdleSystem.get_fish_skin() == SKIN_ARTISTIC:
			IdleSystem.save_fish_skin(SKIN_MINIMAL)
		_draw_minimal()
		return

	var species: String = FishSpecies.DEFAULT_SPECIES
	if IdleSystem != null:
		for f in IdleSystem.get_fish_list():
			if f.get("id", "") == fish_id:
				species = f.get("species", FishSpecies.DEFAULT_SPECIES)
				break
	if not FishSpecies.is_valid(species):
		species = FishSpecies.DEFAULT_SPECIES

	var src_y: int = FishSpecies.get_movement_y(species)

	var awake_fps: float = _emotion_to_anim_fps()
	var sleep_fps: float = awake_fps * SLEEP_SPEED_MULT
	var actual_fps: float = lerp(awake_fps, sleep_fps, _sleep_transition)
	var frame_idx: int = int(_anim_time * actual_fps) % SPRITE_FRAMES_PER_ANIM

	var src_x: int = frame_idx * SPRITE_FRAME_W
	var src_rect := Rect2(src_x, src_y, SPRITE_FRAME_W, SPRITE_FRAME_H)

	var dst_w: float = _fish_size.x * ARTISTIC_SIZE_MULT
	var dst_h: float = dst_w * (float(SPRITE_FRAME_H) / float(SPRITE_FRAME_W))
	var dst_rect := Rect2(-dst_w * 0.5, -dst_h * 0.5, dst_w, dst_h)

	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if material != null:
		material = null

	var facing_right := _velocity.x >= 0
	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2(-1, 1))

	var base_color := Color.WHITE
	var final_color := _to_sleep_color(base_color, _sleep_transition)
	final_color.a = lerp(1.0, 0.75, _sleep_transition)

	draw_texture_rect_region(sheet, dst_rect, src_rect, final_color)

	if not facing_right:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _emotion_to_anim_fps() -> float:
	var ratio := _speed / BASE_SPEED
	if ratio >= 1.55:
		return ANIM_FPS_BOOM
	elif ratio >= 1.30:
		return ANIM_FPS_BIG_UP
	elif ratio >= 1.10:
		return ANIM_FPS_SMALL_UP
	elif ratio >= 0.95:
		return ANIM_FPS_FLAT
	elif ratio >= 0.75:
		return ANIM_FPS_SMALL_DOWN
	elif ratio >= 0.50:
		return ANIM_FPS_BIG_DOWN
	else:
		return ANIM_FPS_CRASH


func _on_prices_updated() -> void:
	var data: Dictionary = DataReader.get_ticker(ticker_key)
	if data.is_empty():
		return
	var change_pct: float = float(data.get("change_pct", 0.0))
	var data_market: String = data.get("market", "stocks")
	_update_emotion(change_pct, data_market)

func _update_emotion(change_pct: float, _mkt: String) -> void:
	_last_change_pct = change_pct

	if change_pct > AMBIENT_BUBBLE_FLAT_THRESHOLD:
		_last_direction = 1
	elif change_pct < -AMBIENT_BUBBLE_FLAT_THRESHOLD:
		_last_direction = -1
	else:
		_last_direction = 0

	var t_boom: float = 10.0
	var t_big_up: float = 3.0
	var t_small_up: float = 0.5
	var t_small_down: float = -0.5
	var t_big_down: float = -3.0
	var t_crash: float = -10.0

	if change_pct >= t_boom:
		_current_color = COLOR_BOOM
		_speed = BASE_SPEED * SPEED_MULT_BOOM
	elif change_pct >= t_big_up:
		_current_color = COLOR_BIG_UP
		_speed = BASE_SPEED * SPEED_MULT_BIG_UP
	elif change_pct >= t_small_up:
		_current_color = COLOR_SMALL_UP
		_speed = BASE_SPEED * SPEED_MULT_SMALL_UP
	elif change_pct >= t_small_down:
		_current_color = COLOR_FLAT
		_speed = BASE_SPEED * SPEED_MULT_FLAT
	elif change_pct >= t_big_down:
		_current_color = COLOR_SMALL_DOWN
		_speed = BASE_SPEED * SPEED_MULT_SMALL_DOWN
	elif change_pct >= t_crash:
		_current_color = COLOR_BIG_DOWN
		_speed = BASE_SPEED * SPEED_MULT_BIG_DOWN
	else:
		_current_color = COLOR_CRASH
		_speed = BASE_SPEED * SPEED_MULT_CRASH

func _visual_half_width() -> float:
	var skin: String = IdleSystem.get_fish_skin() if IdleSystem != null else SKIN_MINIMAL
	if skin == SKIN_ARTISTIC and FishArt.sheet() != null:
		return _fish_size.x * ARTISTIC_SIZE_MULT * 0.5
	if LottieFish.available():
		return LottieFish.half_extent(_get_design_index(), _fish_size.x * LottieFish.RENDER_SCALE)
	return _fish_size.x * 0.5

func is_point_inside(local_pos: Vector2) -> bool:
	var p := local_pos - position
	var rx := _fish_size.x * 0.5
	var ry := _fish_size.y * 0.5
	if rx <= 0 or ry <= 0:
		return false
	return (p.x * p.x) / (rx * rx) + (p.y * p.y) / (ry * ry) <= 1.0

func spawn_bubble() -> void:
	if _active_bubble != null and is_instance_valid(_active_bubble):
		_active_bubble.queue_free()
		_active_bubble = null

	var data: Dictionary = DataReader.get_ticker(ticker_key)
	if data.is_empty():
		return

	var symbol: String = data.get("symbol", ticker_key)
	var display_name: String = nickname if nickname != "" else symbol
	var price: float = float(data.get("price", 0))
	var change_pct: float = float(data.get("change_pct", 0))
	var currency: String = data.get("currency", "USD")

	var sign_str := "+" if change_pct >= 0 else ""
	var text := "%s · %s%.2f · %s%.2f%%" % [display_name, _currency_symbol(currency), price, sign_str, change_pct]

	var bubble := Node2D.new()
	bubble.set_script(BubbleScript)
	add_child(bubble)
	bubble.setup(text)
	_active_bubble = bubble

func close_bubble() -> void:
	if _active_bubble != null and is_instance_valid(_active_bubble):
		_active_bubble.close_immediately()

func spawn_alert_bubble(record: Dictionary) -> void:
	if _active_bubble != null and is_instance_valid(_active_bubble):
		_active_bubble.queue_free()
		_active_bubble = null

	var symbol: String = str(record.get("symbol", ticker_key))
	var display_name: String = nickname if nickname != "" else symbol
	var price_v = record.get("price", null)
	var change_pct: float = float(record.get("change_pct", 0.0))
	var currency: String = str(record.get("currency", "USD"))

	var sign_str := "+" if change_pct >= 0 else ""
	var price_str := ("%.2f" % float(price_v)) if price_v != null else "—"
	var text := "%s · %s%s · %s%.2f%%" % [display_name, _currency_symbol(currency), price_str, sign_str, change_pct]

	var bubble := Node2D.new()
	bubble.set_script(BubbleScript)
	add_child(bubble)
	bubble.setup(text, true)
	_active_bubble = bubble

func fade_in(duration: float) -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, duration)

func fade_out_and_remove(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, duration)
	tw.tween_callback(queue_free)

func _currency_symbol(c: String) -> String:
	match c:
		"USD": return "$"
		"HKD": return "HK$"
		"JPY": return "¥"
		"CNY": return "¥"
		"KRW": return "₩"
		"EURO": return "€"
		"GBP": return "₤"
		_: return ""
