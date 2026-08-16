extends Node2D
## 鱼嘴升起的环形泡泡:颜色表涨/跌,形状按幅度分 5 级。


const LIFETIME := 2.0
const FADE_IN_T := 0.25
const FADE_OUT_T := 0.5

const BASE_TOTAL_RISE := 10.0
const REFERENCE_FISH_H := 20.0
const RISE_SCALE_MIN := 0.6
const RISE_SCALE_MAX := 1.8

const WOBBLE_AMPLITUDE := 2.4
const WOBBLE_FREQ := 1.8

const TIER1_MAX := 5.0
const TIER2_MAX := 10.0
const TIER3_MAX := 20.0
const TIER4_MAX := 50.0

const COLOR_UP := Color(0.30, 0.85, 0.40, 1.0)
const COLOR_DOWN := Color(0.95, 0.35, 0.35, 1.0)
const COLOR_UP_EXTREME := Color(1.00, 0.82, 0.10, 1.0)
const COLOR_DOWN_EXTREME := Color(0.40, 0.05, 0.05, 1.0)

var direction: int = 1

var _elapsed: float = 0.0
var _spawn_x: float = 0.0
var _phase: float = 0.0
var _rise_speed: float = BASE_TOTAL_RISE / LIFETIME

var _outer_radius: float = 3.2
var _outer_thickness: float = 1.1
var _inner_radius: float = 0.0
var _inner_thickness: float = 0.0
var _fill_alpha: float = 0.0
var _ring_color: Color = COLOR_UP

func setup(change_pct: float, fish_size: Vector2) -> void:
	direction = -1 if change_pct < 0 else 1
	_phase = randf() * TAU
	_spawn_x = position.x

	var rise_scale: float = clamp(fish_size.y / REFERENCE_FISH_H, RISE_SCALE_MIN, RISE_SCALE_MAX)
	_rise_speed = (BASE_TOTAL_RISE / LIFETIME) * rise_scale

	_resolve_tier(absf(change_pct))

func _resolve_tier(abs_pct: float) -> void:
	var is_up: bool = direction > 0
	var base_color: Color = COLOR_UP if is_up else COLOR_DOWN

	if abs_pct < TIER1_MAX:
		_outer_radius = 3.0
		_outer_thickness = 0.9
		_inner_radius = 0.0
		_fill_alpha = 0.0
		_ring_color = base_color
	elif abs_pct < TIER2_MAX:
		_outer_radius = 4.2
		_outer_thickness = 0.9
		_inner_radius = 0.0
		_fill_alpha = 0.0
		_ring_color = base_color
	elif abs_pct < TIER3_MAX:
		_outer_radius = 4.8
		_outer_thickness = 0.9
		_inner_radius = 2.4
		_inner_thickness = 0.8
		_fill_alpha = 0.0
		_ring_color = base_color
	elif abs_pct < TIER4_MAX:
		_outer_radius = 5.4
		_outer_thickness = 1.0
		_inner_radius = 0.0
		_fill_alpha = 0.55
		_ring_color = base_color
	else:
		_outer_radius = 6.2
		_outer_thickness = 0.0
		_inner_radius = 0.0
		_fill_alpha = 1.0
		_ring_color = COLOR_UP_EXTREME if is_up else COLOR_DOWN_EXTREME

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return

	var age_t: float = _elapsed / LIFETIME
	var wobble: float = sin(_elapsed * WOBBLE_FREQ * TAU + _phase) * WOBBLE_AMPLITUDE * (1.0 - age_t)
	position.x = _spawn_x + wobble
	position.y -= _rise_speed * delta

	queue_redraw()

func _draw() -> void:
	var alpha: float
	if _elapsed < FADE_IN_T:
		alpha = _elapsed / FADE_IN_T
	elif _elapsed > LIFETIME - FADE_OUT_T:
		alpha = (LIFETIME - _elapsed) / FADE_OUT_T
	else:
		alpha = 1.0
	alpha = clamp(alpha, 0.0, 1.0)

	if _fill_alpha > 0.001:
		var fc: Color = _ring_color
		fc.a = _ring_color.a * alpha * _fill_alpha
		var fill_r: float = _outer_radius if _outer_thickness <= 0.001 else _outer_radius - _outer_thickness * 0.5
		draw_circle(Vector2.ZERO, fill_r, fc)

	if _outer_thickness > 0.001:
		var rc: Color = _ring_color
		rc.a *= alpha
		draw_arc(Vector2.ZERO, _outer_radius, 0.0, TAU, 24, rc, _outer_thickness, true)

	if _inner_radius > 0.001:
		var rc2: Color = _ring_color
		rc2.a *= alpha
		draw_arc(Vector2.ZERO, _inner_radius, 0.0, TAU, 16, rc2, _inner_thickness, true)
