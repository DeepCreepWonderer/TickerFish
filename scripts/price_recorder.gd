extends Node
## 价格定时记录器:按 15/30/60 分分市场写年度 CSV 到 DataBridge 文件夹(美股仅营业时段/加密 24h);Autoload。


const CHECK_SECONDS := 5.0

const CSV_HEADER := "timestamp,symbol,name,price,change_pct,open,high,low,prev_close,currency"
const CSV_FORMULA_LEAD := ["=", "+", "-", "@", "\t", "\r"]

var _last_slot: String = ""

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = CHECK_SECONDS
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()
	print("[PriceRecorder] Ready. enabled=", is_recording())

func is_recording() -> bool:
	return IdleSystem != null and IdleSystem.get_price_stream_enabled()

func _tick() -> void:
	if IdleSystem == null or not IdleSystem.get_price_stream_enabled():
		return

	var et: Dictionary = MarketClock.et_now()
	var minute_of_day: int = int(et.get("hour", 0)) * 60 + int(et.get("minute", 0))
	var interval: int = IdleSystem.get_price_stream_interval_min()
	if interval <= 0:
		return
	if minute_of_day % interval != 0:
		return

	var slot: String = "%04d%02d%02d_%02d%02d" % [
		int(et.get("year", 0)), int(et.get("month", 0)), int(et.get("day", 0)),
		int(et.get("hour", 0)), int(et.get("minute", 0))]
	if slot == _last_slot:
		return
	_last_slot = slot

	_record_sample(int(et.get("year", 1970)))

func _record_sample(year: int) -> void:
	if DataReader == null:
		return
	var entries: Array = IdleSystem.get_all_watchlist_entries()
	if entries.is_empty():
		return
	var excluded: Array = IdleSystem.get_price_stream_excluded()
	var ts: String = MarketClock.et_now_string()

	var us_open: bool = MarketClock.is_market_open()
	var rows_stocks: Array = []
	var rows_crypto: Array = []
	for e in entries:
		var market: String = str(e.get("market", ""))
		var symbol: String = str(e.get("symbol", ""))
		var key: String = market + ":" + symbol
		if key in excluded:
			continue
		var is_crypto: bool = market == "crypto"
		if not is_crypto and not us_open:
			continue

		var data: Dictionary = DataReader.get_ticker(key)
		if data.is_empty():
			continue
		var price_v = data.get("price", null)
		if price_v == null or float(price_v) <= 0.0:
			continue
		if data.get("market_open", true) == false:
			continue

		var disp_name: String = str(e.get("name", ""))
		if disp_name == "":
			disp_name = str(data.get("display_name", symbol))

		var line: String = ",".join([
			ts,
			_csv(symbol),
			_csv(disp_name),
			_num(price_v),
			_num2(data.get("change_pct", null)),
			_num(data.get("open_price", null)),
			_num(data.get("high", null)),
			_num(data.get("low", null)),
			_num(data.get("previous_close", null)),
			_csv(str(data.get("currency", ""))),
		])
		if is_crypto:
			rows_crypto.append(line)
		else:
			rows_stocks.append(line)

	if not rows_stocks.is_empty():
		_append_rows(rows_stocks, year, "stocks")
	if not rows_crypto.is_empty():
		_append_rows(rows_crypto, year, "crypto")

func _append_rows(rows: Array, year: int, market: String) -> void:
	var path: String = BackendManager.get_data_dir() + "price_history_%s_%d.csv" % [market, year]
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
		push_warning("[PriceRecorder] Could not open %s (in use?); skipping sample" % path)
		return

	if not existed:
		f.store_string("\uFEFF" + CSV_HEADER + "\r\n")

	for line in rows:
		f.store_string(line + "\r\n")
	f.close()
	print("[PriceRecorder] Wrote ", rows.size(), " rows -> ", path)


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
