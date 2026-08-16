extends Node2D
const UITheme := preload("res://scripts/ui_theme.gd")
## 鱼上方的文字气泡(涨跌数字/提醒),淡入淡出。

const LIFETIME := 10.0
const FADE_IN_DURATION := 0.25
const FADE_OUT_DURATION := 0.5
const FONT_SIZE := 13
const PAD := Vector2(10, 7)
const CORNER := 8.0
const SEP := " · "
const Y_OFFSET := -24.0
const Y_OFFSET_BELOW := 24.0
const TAIL_W := 6.0
const TAIL_H := 6.0

const BG_ALPHA := 0.96
const BORDER := Color(1, 1, 1, 0.14)
const ALERT_BORDER := Color(0.96, 0.58, 0.32, 0.95)
const SHADOW := Color(0, 0, 0, 0.40)

const C_NAME := Color(0.914, 0.929, 0.922, 1.0)
const C_PRICE := Color(0.914, 0.929, 0.922, 1.0)
const C_SEP := Color(1, 1, 1, 0.36)
const C_UP := Color(0.34, 0.86, 0.48)
const C_DOWN := Color(0.96, 0.42, 0.42)
const C_FLAT := Color(1, 1, 1, 0.60)

var text: String = ""
var is_alert: bool = false
var _elapsed := 0.0
var _alpha := 0.0
var _font: Font

func _ready() -> void:
    _font = UITheme.mono()

func setup(t: String, alert: bool = false) -> void:
    text = t
    is_alert = alert
    _elapsed = 0.0
    _alpha = 0.0
    queue_redraw()

func _process(delta: float) -> void:
    _elapsed += delta

    if _elapsed < FADE_IN_DURATION:
        _alpha = _elapsed / FADE_IN_DURATION
    elif _elapsed > LIFETIME - FADE_OUT_DURATION:
        var t := (LIFETIME - _elapsed) / FADE_OUT_DURATION
        _alpha = max(0.0, t)
    else:
        _alpha = 1.0

    if _elapsed >= LIFETIME:
        queue_free()
        return

    queue_redraw()

func close_immediately() -> void:
    if _elapsed < LIFETIME - FADE_OUT_DURATION:
        _elapsed = LIFETIME - FADE_OUT_DURATION

func _fade(c: Color) -> Color:
    return Color(c.r, c.g, c.b, c.a * _alpha)

func _bg() -> Color:
    var c: Color = UITheme.PANEL_CARD
    return Color(c.r, c.g, c.b, BG_ALPHA)

func _segments() -> Array:
    var raw := text.split(SEP, false)
    if raw.size() == 3:
        var chg: String = raw[2]
        var col: Color = C_FLAT
        if chg.contains("-"):
            col = C_DOWN
        elif chg.contains("+"):
            col = C_UP
        return [
            {"t": raw[0], "c": C_NAME},
            {"t": SEP, "c": C_SEP},
            {"t": raw[1], "c": C_PRICE},
            {"t": SEP, "c": C_SEP},
            {"t": chg, "c": col},
        ]
    return [{"t": text, "c": C_PRICE}]

func _draw() -> void:
    if _alpha < 0.01 or text == "":
        return

    var segs := _segments()
    var line_h := _font.get_height(FONT_SIZE)
    var ascent := _font.get_ascent(FONT_SIZE)
    var content_w := 0.0
    for s in segs:
        content_w += _font.get_string_size(s["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
    var bubble_size := Vector2(content_w + PAD.x * 2.0, line_h + PAD.y * 2.0)

    var fish := get_parent() as Node2D
    var tank := fish.get_parent() as Control if fish else null

    var show_below := false
    var x_shift := 0.0

    if tank != null and fish != null:
        var fish_pos := fish.position
        var top_pos_in_tank_y := fish_pos.y + Y_OFFSET - bubble_size.y
        if top_pos_in_tank_y < 4:
            show_below = true

        var bubble_left_in_tank := fish_pos.x - bubble_size.x * 0.5
        var bubble_right_in_tank := fish_pos.x + bubble_size.x * 0.5
        if bubble_left_in_tank < 4:
            x_shift = 4 - bubble_left_in_tank
        elif bubble_right_in_tank > tank.size.x - 4:
            x_shift = (tank.size.x - 4) - bubble_right_in_tank

    var bubble_pos: Vector2
    if show_below:
        bubble_pos = Vector2(-bubble_size.x * 0.5 + x_shift, Y_OFFSET_BELOW)
    else:
        bubble_pos = Vector2(-bubble_size.x * 0.5 + x_shift, Y_OFFSET - bubble_size.y)

    var bubble_rect := Rect2(bubble_pos, bubble_size)

    var sb := StyleBoxFlat.new()
    sb.bg_color = _fade(_bg())
    sb.set_corner_radius_all(int(CORNER))
    sb.border_color = _fade(ALERT_BORDER if is_alert else BORDER)
    sb.set_border_width_all(2 if is_alert else 1)
    sb.shadow_color = Color(SHADOW.r, SHADOW.g, SHADOW.b, SHADOW.a * _alpha)
    sb.shadow_size = 4
    sb.shadow_offset = Vector2(0, 2)
    draw_style_box(sb, bubble_rect)

    var tail_pts: PackedVector2Array
    if show_below:
        var top := Vector2(-x_shift, Y_OFFSET_BELOW + 1)
        tail_pts = PackedVector2Array([
            Vector2(-x_shift, Y_OFFSET_BELOW - TAIL_H),
            Vector2(-x_shift - TAIL_W, top.y),
            Vector2(-x_shift + TAIL_W, top.y),
        ])
    else:
        var bot := Vector2(-x_shift, Y_OFFSET - 1)
        tail_pts = PackedVector2Array([
            Vector2(-x_shift, Y_OFFSET + TAIL_H),
            Vector2(-x_shift - TAIL_W, bot.y),
            Vector2(-x_shift + TAIL_W, bot.y),
        ])
    draw_colored_polygon(tail_pts, _fade(_bg()))

    var x := bubble_pos.x + PAD.x
    var by := bubble_pos.y + PAD.y + ascent
    for s in segs:
        draw_string(_font, Vector2(x, by), s["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _fade(s["c"]))
        x += _font.get_string_size(s["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
