extends BaseButton
const UITheme := preload("res://scripts/ui_theme.gd")
## Tide 方形复选框:选中=金底金勾,未选=灰边空框。

const BOX := 20.0

func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(BOX, BOX)

func _toggled(_on: bool) -> void:
	queue_redraw()

func _draw() -> void:
	var on: bool = button_pressed
	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.ACCENT_SOFT if on else Color(1, 1, 1, 0.04)
	box.border_color = UITheme.ACCENT if on else UITheme.TEXT_DIM
	box.set_border_width_all(2 if on else 1)
	box.set_corner_radius_all(5)
	draw_style_box(box, Rect2(0, 0, BOX, BOX))
	if on:
		draw_line(Vector2(BOX * 0.24, BOX * 0.52), Vector2(BOX * 0.42, BOX * 0.70), UITheme.ACCENT, 2.0, true)
		draw_line(Vector2(BOX * 0.42, BOX * 0.70), Vector2(BOX * 0.76, BOX * 0.30), UITheme.ACCENT, 2.0, true)
