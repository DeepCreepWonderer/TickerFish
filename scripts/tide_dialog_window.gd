extends Window
## Tide 对话框基类:窗口尺寸跟随鱼缸与屏幕上限。

const DIALOG_TANK_MARGIN := 24

const DIALOG_W := 420
const DIALOG_H := 520
const DIALOG_MIN := Vector2i(300, 300)
const SCREEN_W_FRAC := 0.6
const SCREEN_H_FRAC := 0.7

var _tank_size: Vector2i = Vector2i.ZERO

func apply_tide_size() -> void:
	min_size = DIALOG_MIN

func set_tank_size(tank_size: Vector2i) -> void:
	_tank_size = tank_size

func _host_screen() -> int:
	if is_inside_tree():
		var root := get_tree().root
		if root != null:
			return root.current_screen
	return DisplayServer.get_primary_screen()

func _resize_to_fit_screen() -> void:
	var screen_size := DisplayServer.screen_get_size(_host_screen())
	var target_w: int = mini(DIALOG_W, int(screen_size.x * SCREEN_W_FRAC))
	var target_h: int = mini(DIALOG_H, int(screen_size.y * SCREEN_H_FRAC))
	if _tank_size.x > 0:
		target_w = mini(target_w, _tank_size.x - DIALOG_TANK_MARGIN)
	if _tank_size.y > 0:
		target_h = mini(target_h, _tank_size.y - DIALOG_TANK_MARGIN)
	size = Vector2i(maxi(target_w, min_size.x), maxi(target_h, min_size.y))

func popup_centered_on_parent() -> void:
	_resize_to_fit_screen()
	popup_centered(size)
