extends Node
## 触发提醒的原生置顶 toast 弹窗管理器(自有堆叠与屏幕定位);Autoload。


const AlertPopupWindowScript := preload("res://scripts/alert_popup_window.gd")

const MAX_VISIBLE_POPUPS := 5
const POPUP_GAP := 8
const SCREEN_MARGIN := 16

var _stack: Array = []

func _ready() -> void:
	if AlertSystem != null:
		AlertSystem.alert_fired.connect(_on_alert_fired)
	if IdleSystem != null:
		IdleSystem.alerts_enabled_changed.connect(_on_alerts_enabled_changed)

func _on_alerts_enabled_changed(enabled: bool) -> void:
	if enabled:
		return
	for popup in _stack:
		if popup != null and is_instance_valid(popup):
			popup.queue_free()
	_stack.clear()

func _on_alert_fired(record: Dictionary) -> void:
	if _stack.size() >= MAX_VISIBLE_POPUPS:
		return
	var popup = AlertPopupWindowScript.new()
	get_tree().root.add_child(popup)
	popup.setup(record)
	popup.dismissed.connect(_on_popup_dismissed.bind(popup))
	_stack.append(popup)
	_reflow()

func _on_popup_dismissed(popup) -> void:
	_stack.erase(popup)
	_reflow()

func _reflow() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var n := _stack.size()
	for idx in n:
		var popup = _stack[idx]
		if popup == null or not is_instance_valid(popup):
			continue
		var stack_pos: int = n - 1 - idx
		var w: int = popup.size.x
		var h: int = popup.size.y
		var x := usable.position.x + usable.size.x - w - SCREEN_MARGIN
		var y := usable.position.y + usable.size.y - SCREEN_MARGIN - h - stack_pos * (h + POPUP_GAP)
		popup.position = Vector2i(x, y)
