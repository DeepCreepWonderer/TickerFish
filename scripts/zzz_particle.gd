extends Node2D
## 睡眠 "Z" 粒子:鱼休眠时飘出。

const LIFETIME := 2.4
const FADE_IN_T := 0.2
const FONT_SIZE_START := 9
const FONT_SIZE_END := 14
const TEXT := "Z"
const TEXT_COLOR := Color(0.6, 0.7, 0.95, 1.0)

const BASE_DRIFT_X := 9.0
const BASE_DRIFT_Y := -10.0
const REFERENCE_FISH_H := 20.0
const DRIFT_SCALE_MIN := 0.6
const DRIFT_SCALE_MAX := 1.8

var _elapsed := 0.0
var _font: Font
var _drift_x: float = BASE_DRIFT_X
var _drift_y: float = BASE_DRIFT_Y

func _ready() -> void:
	_font = ThemeDB.fallback_font
	position.x += randf_range(-3, 3)

func setup(fish_size: Vector2) -> void:
	var drift_scale: float = clamp(fish_size.y / REFERENCE_FISH_H, DRIFT_SCALE_MIN, DRIFT_SCALE_MAX)
	_drift_x = BASE_DRIFT_X * drift_scale
	_drift_y = BASE_DRIFT_Y * drift_scale

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	if _font == null:
		return
	var t: float = _elapsed / LIFETIME

	var alpha: float
	if _elapsed < FADE_IN_T:
		alpha = _elapsed / FADE_IN_T
	else:
		alpha = 1.0 - (_elapsed - FADE_IN_T) / (LIFETIME - FADE_IN_T)
	alpha = clamp(alpha, 0.0, 1.0)

	var drift_t: float = 1.0 - pow(1.0 - t, 2.0)
	var offset := Vector2(_drift_x * drift_t, _drift_y * drift_t)

	var fs: int = int(lerp(float(FONT_SIZE_START), float(FONT_SIZE_END), t))

	var color := TEXT_COLOR
	color.a *= alpha

	var text_size := _font.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var draw_pos := offset + Vector2(-text_size.x * 0.5, text_size.y * 0.3)
	draw_string(_font, draw_pos, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
