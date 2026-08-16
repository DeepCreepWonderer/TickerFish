extends Node2D
## 休市/夜间的月亮图标绘制,并飘出 Zzz 粒子。

const MOON_SIZE_RATIO := 0.40
const MOON_COLOR := Color(0.70, 0.62, 0.45, 1.0)
const MOON_OUTLINE_COLOR := Color(0.55, 0.48, 0.32, 0.65)
const MOON_INTRINSIC_ALPHA := 0.75

const INNER_RATIO := 0.83
const OFFSET_ABS := 0.4
const ARC_SEGS := 32
const TILT_DEGREES := 30.0

const ZZZ_SPAWN_INTERVAL := 1.8
const ZzzScript := preload("res://scripts/zzz_particle.gd")

var _alpha: float = 0.0
var _radius: float = 30.0
var _tank_size: Vector2 = Vector2.ZERO
var _zzz_spawn_timer: float = 0.0

func _ready() -> void:
	_zzz_spawn_timer = ZZZ_SPAWN_INTERVAL

func _process(delta: float) -> void:
	if _alpha > 0.1:
		_zzz_spawn_timer += delta
		if _zzz_spawn_timer >= ZZZ_SPAWN_INTERVAL:
			_zzz_spawn_timer = 0.0
			_spawn_zzz()

func set_visibility(target_alpha: float, tank_size: Vector2) -> void:
	_alpha = target_alpha
	_tank_size = tank_size
	position = tank_size * 0.5
	var diameter: float = min(tank_size.x, tank_size.y) * MOON_SIZE_RATIO
	_radius = diameter * 0.5
	queue_redraw()

func _spawn_zzz() -> void:
	var zzz := Node2D.new()
	zzz.set_script(ZzzScript)
	var top := Vector2(_radius * 0.3, -_radius * 1.1)
	zzz.position = top.rotated(deg_to_rad(TILT_DEGREES))
	add_child(zzz)

func _draw() -> void:
	if _alpha < 0.01:
		return
	draw_set_transform(Vector2.ZERO, deg_to_rad(TILT_DEGREES), Vector2.ONE)
	_draw_crescent()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_crescent() -> void:
	var R: float = _radius
	var r: float = R * INNER_RATIO
	var dx: float = R * OFFSET_ABS

	if dx <= 0.001:
		return
	var x_int: float = -(R * R - r * r + dx * dx) / (2.0 * dx)
	var y_sq: float = R * R - x_int * x_int
	if y_sq <= 0:
		return
	var y_int: float = sqrt(y_sq)

	var theta_outer: float = atan2(y_int, x_int)
	var theta_inner: float = atan2(y_int, x_int + dx)

	var pts := PackedVector2Array()

	for i in range(ARC_SEGS + 1):
		var t: float = float(i) / float(ARC_SEGS)
		var angle: float = lerp(theta_outer, -theta_outer, t)
		pts.append(Vector2(cos(angle) * R, sin(angle) * R))

	for i in range(ARC_SEGS + 1):
		var t: float = float(i) / float(ARC_SEGS)
		var angle: float = lerp(-theta_inner, theta_inner, t)
		pts.append(Vector2(-dx + cos(angle) * r, sin(angle) * r))

	var color := MOON_COLOR
	color.a *= _alpha * MOON_INTRINSIC_ALPHA
	draw_colored_polygon(pts, color)

	var outline := MOON_OUTLINE_COLOR
	outline.a *= _alpha * 0.4
	var closed_pts := pts.duplicate()
	closed_pts.append(pts[0])
	draw_polyline(closed_pts, outline, 1.2, true)
