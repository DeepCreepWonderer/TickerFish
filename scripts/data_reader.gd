extends Node
## 轮询 prices.json,缓存行情,变化时发 prices_updated;Autoload。

signal prices_updated

const POLL_SECONDS := 5.0
const BAR_INTERVAL_SECONDS := 30.0
const MAX_BARS := 400
const SAVE_BARS_SECONDS := 60.0
const BARS_CACHE_PATH := "user://bars_cache.json"

var _bars: Dictionary = {}
var _current_bars: Dictionary = {}
var _hist_bars: Dictionary = {}

var _data: Dictionary = {}
var _last_updated_at: String = ""
var _has_ever_read: bool = false
var _parse_warning_shown: bool = false


func _ready() -> void:
	_load_bars()
	_read_file()
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.timeout.connect(_read_file)
	add_child(timer)
	timer.start()
	var save_timer := Timer.new()
	save_timer.wait_time = SAVE_BARS_SECONDS
	save_timer.timeout.connect(_save_bars)
	add_child(save_timer)
	save_timer.start()


func _get_prices_path() -> String:
	return BackendManager.get_data_dir() + "prices.json"


func _read_file() -> void:
	var abs_path := _get_prices_path()

	if not FileAccess.file_exists(abs_path):
		if not _has_ever_read:
			print("[DataReader] Waiting for prices.json... path=", abs_path)
		return

	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		if not _parse_warning_shown:
			print("[DataReader] prices.json not yet parseable (line ", json.get_error_line(), "): ", json.get_error_message(), " — will retry")
			_parse_warning_shown = true
		return
	_parse_warning_shown = false

	var parsed = json.data
	if not parsed is Dictionary:
		return

	var new_updated_at: String = parsed.get("updated_at", "")
	if new_updated_at == _last_updated_at:
		return

	_data = parsed
	_last_updated_at = new_updated_at

	var sb = parsed.get("bars", {})
	if sb is Dictionary:
		for k in sb.keys():
			if sb[k] is Array and (sb[k] as Array).size() >= 2:
				_hist_bars[k] = sb[k]

	_accumulate_bars()

	if not _has_ever_read:
		_has_ever_read = true
	BackendManager.mark_running()

	prices_updated.emit()

	var tickers_count = _data.get("tickers", {}).size()
	print("[DataReader] New data updated_at=", new_updated_at, " tickers=", tickers_count)


func get_ticker(key: String) -> Dictionary:
	var tickers: Dictionary = _data.get("tickers", {})
	return tickers.get(key, {})


func get_bars(key: String) -> Array:
	if _hist_bars.has(key):
		return (_hist_bars[key] as Array).duplicate()
	var arr: Array = (_bars.get(key, []) as Array).duplicate()
	if _current_bars.has(key):
		var cur: Dictionary = _current_bars[key]
		arr.append({"o": cur["o"], "h": cur["h"], "l": cur["l"], "c": cur["c"]})
	return arr


func _accumulate_bars() -> void:
	var tickers: Dictionary = _data.get("tickers", {})
	var now: float = Time.get_unix_time_from_system()
	for key in tickers:
		var t = tickers[key]
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var p = t.get("price", null)
		if p == null:
			continue
		var price: float = float(p)
		if price <= 0.0:
			continue

		if not _current_bars.has(key):
			_current_bars[key] = {"start": now, "o": price, "h": price, "l": price, "c": price}
			continue

		var cur: Dictionary = _current_bars[key]
		if now - float(cur["start"]) >= BAR_INTERVAL_SECONDS:
			var arr: Array = _bars.get(key, [])
			arr.append({"o": cur["o"], "h": cur["h"], "l": cur["l"], "c": cur["c"]})
			while arr.size() > MAX_BARS:
				arr.pop_front()
			_bars[key] = arr
			_current_bars[key] = {"start": now, "o": price, "h": price, "l": price, "c": price}
		else:
			cur["c"] = price
			cur["h"] = maxf(float(cur["h"]), price)
			cur["l"] = minf(float(cur["l"]), price)


func get_status() -> String:
	return _data.get("status", "")


func needs_config() -> bool:
	return get_status() == "needs_config"


func get_error_code() -> String:
	return str(_data.get("error", ""))


func get_providers_not_ready() -> Dictionary:
	var d = _data.get("providers_not_ready", {})
	if d is Dictionary:
		return d
	return {}


func _et_date_str() -> String:
	var d: Dictionary = MarketClock.et_now()
	return "%04d-%02d-%02d" % [int(d.get("year", 1970)), int(d.get("month", 1)), int(d.get("day", 1))]

func _save_bars() -> void:
	var stock_bars: Dictionary = {}
	for k in _bars.keys():
		if not str(k).begins_with("crypto:"):
			stock_bars[k] = _bars[k]
	var stock_cur: Dictionary = {}
	for k in _current_bars.keys():
		if not str(k).begins_with("crypto:"):
			stock_cur[k] = _current_bars[k]
	if stock_bars.is_empty() and stock_cur.is_empty():
		return
	var f := FileAccess.open(BARS_CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"date": _et_date_str(), "bars": stock_bars, "current": stock_cur}))
	f.close()

func _load_bars() -> void:
	if not FileAccess.file_exists(BARS_CACHE_PATH):
		return
	var f := FileAccess.open(BARS_CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	if str(parsed.get("date", "")) != _et_date_str():
		return
	var b = parsed.get("bars", {})
	if b is Dictionary:
		_bars = b
	var c = parsed.get("current", {})
	if c is Dictionary:
		_current_bars = c

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_save_bars()
