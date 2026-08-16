extends Node
## 价格提醒引擎:当日涨跌幅每上一个阈值档提醒一次,涨跌分别计档,档位只升不降、按交易日清零;Autoload。


signal alert_fired(record: Dictionary)

const STEP_EPSILON := 0.000000001
const CSV_HEADER := "symbol,name,data_time,previous_close,price,change_pct,threshold_set,currency"
const CSV_FORMULA_LEAD := ["=", "+", "-", "@", "\t", "\r"]

var _steps: Dictionary = {}
var _steps_date: String = ""

func _ready() -> void:
	if DataReader != null:
		DataReader.prices_updated.connect(_on_prices_updated)
	if IdleSystem != null:
		IdleSystem.alerts_enabled_changed.connect(_on_alerts_enabled_changed)
		IdleSystem.alert_threshold_changed.connect(_on_alert_threshold_changed)
	print("[AlertSystem] Ready.")

func _on_alert_threshold_changed(key: String) -> void:
	if _steps.erase(key):
		print("[AlertSystem] Ladder reset for ", key, " (threshold changed)")

func _on_alerts_enabled_changed(enabled: bool) -> void:
	_steps.clear()
	_steps_date = ""
	if IdleSystem != null:
		IdleSystem.clear_alert_steps()
	print("[AlertSystem] Ladder state reset (master switch → ", enabled, ")")

func _today() -> String:
	var et: Dictionary = MarketClock.et_now()
	return "%04d-%02d-%02d" % [int(et.get("year", 1970)), int(et.get("month", 1)), int(et.get("day", 1))]

func _step_of(change: float, threshold: float) -> int:
	if change <= 0.0 or threshold <= 0.0:
		return 0
	return int(change / threshold + STEP_EPSILON)

func _on_prices_updated() -> void:
	if IdleSystem == null or DataReader == null:
		return
	if not IdleSystem.get_alerts_enabled():
		return

	var today: String = _today()
	if today != _steps_date:
		_steps_date = today
		_steps = IdleSystem.get_alert_steps(today)

	var dirty := false
	for e in IdleSystem.get_all_watchlist_entries():
		var market: String = str(e.get("market", ""))
		var symbol: String = str(e.get("symbol", ""))
		var key: String = market + ":" + symbol
		var cfg: Dictionary = IdleSystem.get_alert_config(key)
		if not cfg.get("enabled", false):
			continue
		var threshold: float = float(cfg.get("threshold", 3.0))
		if threshold <= 0.0:
			continue

		var data: Dictionary = DataReader.get_ticker(key)
		if data.is_empty():
			continue
		var price_v = data.get("price", null)
		if price_v == null or float(price_v) <= 0.0:
			continue
		if data.get("market_open", true) == false:
			continue

		var change_signed: float = float(data.get("change_pct", 0.0))
		var up_now: int = _step_of(change_signed, threshold)
		var down_now: int = _step_of(-change_signed, threshold)

		var rec = _steps.get(key, null)
		if not (rec is Dictionary):
			_steps[key] = {"up": up_now, "down": down_now}
			dirty = true
			continue

		var up_prev: int = int(rec.get("up", 0))
		var down_prev: int = int(rec.get("down", 0))
		if up_now <= up_prev and down_now <= down_prev:
			continue

		_steps[key] = {"up": maxi(up_prev, up_now), "down": maxi(down_prev, down_now)}
		dirty = true
		_fire(e, data, threshold, change_signed)

	if dirty:
		IdleSystem.save_alert_steps(today, _steps)

func _fire(entry: Dictionary, data: Dictionary, threshold: float, change_signed: float) -> void:
	var symbol: String = str(entry.get("symbol", ""))
	var display_name: String = str(entry.get("name", ""))
	if display_name == "":
		display_name = str(data.get("display_name", symbol))

	var record := {
		"market": str(entry.get("market", "")),
		"symbol": symbol,
		"name": display_name,
		"data_time": str(data.get("last_trade_at", "")),
		"previous_close": data.get("previous_close", null),
		"price": data.get("price", null),
		"change_pct": snappedf(change_signed, 0.01),
		"threshold": snappedf(threshold, 0.01),
		"currency": str(data.get("currency", "")),
	}

	IdleSystem.add_alert_record(record)
	_append_csv(record)
	alert_fired.emit(record)
	print("[AlertSystem] FIRED ", symbol, " ", record["change_pct"], "% (step of ", threshold, "%)")

func _append_csv(record: Dictionary) -> void:
	var et: Dictionary = MarketClock.et_now()
	var year: int = int(et.get("year", 1970))
	var path: String = BackendManager.get_data_dir() + "price_alerts_%d.csv" % year
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	var existed: bool = FileAccess.file_exists(path)
	var f: FileAccess
	if existed:
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[AlertSystem] could not open %s (in use?); skipping CSV row" % path)
		return
	if not existed:
		f.store_string("\uFEFF" + CSV_HEADER + "\r\n")

	var line: String = ",".join([
		_csv(str(record.get("symbol", ""))),
		_csv(str(record.get("name", ""))),
		_csv(str(record.get("data_time", ""))),
		_num(record.get("previous_close", null)),
		_num(record.get("price", null)),
		_num2(record.get("change_pct", null)),
		_num2(record.get("threshold", null)),
		_csv(str(record.get("currency", ""))),
	])
	f.store_string(line + "\r\n")
	f.close()

func _csv(s: String) -> String:
	if s != "" and s.substr(0, 1) in CSV_FORMULA_LEAD:
		s = "'" + s
	if s.find(",") >= 0 or s.find("\"") >= 0 or s.find("\n") >= 0:
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s

func _num(v) -> String:
	if v == null:
		return ""
	return "%.4f" % float(v)

func _num2(v) -> String:
	if v == null:
		return ""
	return "%.2f" % float(v)
