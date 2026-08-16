extends BaseButton
const UITheme := preload("res://scripts/ui_theme.gd")
## Tide 方头金色拨钮:开=金16%底+金方钮,关=灰底灰钮。

const TW := 40.0
const TH := 22.0
const KNOB := 15.0

func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(TW, TH)

func _toggled(_on: bool) -> void:
	queue_redraw()

func _draw() -> void:
	var on: bool = button_pressed
	var track := StyleBoxFlat.new()
	track.bg_color = UITheme.ACCENT_SOFT if on else Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(6)
	draw_style_box(track, Rect2(0, 0, TW, TH))
	var knob := StyleBoxFlat.new()
	knob.bg_color = UITheme.ACCENT if on else UITheme.TEXT_DIM
	knob.set_corner_radius_all(4)
	var kx: float = (TW - 3.0 - KNOB) if on else 3.0
	draw_style_box(knob, Rect2(kx, 3.0, KNOB, TH - 6.0))
