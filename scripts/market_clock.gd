extends Node

class_name MarketClock
## 美股(NYSE)交易时段与节假日判断,及鱼的清醒时段。

const ET_OFFSET_EST := -300
const ET_OFFSET_EDT := -240

const NYSE_OPEN_MIN := 9 * 60 + 30
const NYSE_CLOSE_MIN := 16 * 60
const NYSE_HALF_DAY_CLOSE_MIN := 13 * 60

const AWAKE_LEAD_MIN := 60

# ---- 交易日历兜底表(2026-2035,交易所实时状态优先) ----
const HOLIDAY_TABLE_LAST_YEAR := 2035
const HOLIDAYS := [
	"2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19", "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
	"2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18", "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24",
	"2028-01-17", "2028-02-21", "2028-04-14", "2028-05-29", "2028-06-19", "2028-07-04", "2028-09-04", "2028-11-23", "2028-12-25",
	"2029-01-01", "2029-01-15", "2029-02-19", "2029-03-30", "2029-05-28", "2029-06-19", "2029-07-04", "2029-09-03", "2029-11-22", "2029-12-25",
	"2030-01-01", "2030-01-21", "2030-02-18", "2030-04-19", "2030-05-27", "2030-06-19", "2030-07-04", "2030-09-02", "2030-11-28", "2030-12-25",
	"2031-01-01", "2031-01-20", "2031-02-17", "2031-04-11", "2031-05-26", "2031-06-19", "2031-07-04", "2031-09-01", "2031-11-27", "2031-12-25",
	"2032-01-01", "2032-01-19", "2032-02-16", "2032-03-26", "2032-05-31", "2032-06-18", "2032-07-05", "2032-09-06", "2032-11-25", "2032-12-24",
	"2033-01-17", "2033-02-21", "2033-04-15", "2033-05-30", "2033-06-20", "2033-07-04", "2033-09-05", "2033-11-24", "2033-12-26",
	"2034-01-02", "2034-01-16", "2034-02-20", "2034-04-07", "2034-05-29", "2034-06-19", "2034-07-04", "2034-09-04", "2034-11-23", "2034-12-25",
	"2035-01-01", "2035-01-15", "2035-02-19", "2035-03-23", "2035-05-28", "2035-06-19", "2035-07-04", "2035-09-03", "2035-11-22", "2035-12-25",
]

const HALF_DAYS := [
	"2026-11-27", "2026-12-24",
	"2027-11-26",
	"2028-07-03", "2028-11-24",
	"2029-07-03", "2029-11-23", "2029-12-24",
	"2030-07-03", "2030-11-29", "2030-12-24",
	"2031-07-03", "2031-11-28", "2031-12-24",
	"2032-11-26",
	"2033-11-25",
	"2034-07-03", "2034-11-24",
	"2035-07-03", "2035-11-23", "2035-12-24",
]

# ---- 交易所实时状态 ----
const LIVE_STALE_MS := 15 * 60 * 1000

static var _live_at_ms: int = 0
static var _live_is_open: bool = false
static var _live_holiday: String = ""

static var _holiday_set: Dictionary = {}
static var _half_day_set: Dictionary = {}

static func set_live_status(is_open: bool, holiday: String) -> void:
	_live_is_open = is_open
	_live_holiday = holiday
	_live_at_ms = Time.get_ticks_msec()

static func clear_live_status() -> void:
	_live_at_ms = 0

static func has_live_status() -> bool:
	return _live_at_ms > 0 and (Time.get_ticks_msec() - _live_at_ms) < LIVE_STALE_MS

static func live_holiday_name() -> String:
	return _live_holiday if has_live_status() else ""

static func _ensure_tables() -> void:
	if not _holiday_set.is_empty():
		return
	for d in HOLIDAYS:
		_holiday_set[d] = true
	for d in HALF_DAYS:
		_half_day_set[d] = true

static func et_date_str() -> String:
	var d: Dictionary = et_now()
	return "%04d-%02d-%02d" % [int(d.get("year", 1970)), int(d.get("month", 1)), int(d.get("day", 1))]

static func is_holiday(date_str: String = "") -> bool:
	if date_str == "" and has_live_status():
		return _live_holiday != ""
	_ensure_tables()
	return _holiday_set.has(date_str if date_str != "" else et_date_str())

static func is_half_day(date_str: String = "") -> bool:
	_ensure_tables()
	return _half_day_set.has(date_str if date_str != "" else et_date_str())

static func close_minute(date_str: String = "") -> int:
	return NYSE_HALF_DAY_CLOSE_MIN if is_half_day(date_str) else NYSE_CLOSE_MIN

static func _nth_weekday_of_month(year: int, month: int, weekday: int, n: int) -> int:
	var first := {"year": year, "month": month, "day": 1, "hour": 0, "minute": 0, "second": 0}
	var first_unix := int(Time.get_unix_time_from_datetime_dict(first))
	var first_wd: int = Time.get_datetime_dict_from_unix_time(first_unix).get("weekday", 0)
	var first_match: int = 1 + ((weekday - first_wd + 7) % 7)
	return first_match + (n - 1) * 7

static func _et_offset_minutes(utc_unix: int) -> int:
	var year: int = Time.get_datetime_dict_from_unix_time(utc_unix).get("year", 1970)

	var mar_day: int = _nth_weekday_of_month(year, 3, 0, 2)
	var dst_start: int = int(Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": 3, "day": mar_day, "hour": 7, "minute": 0, "second": 0}))

	var nov_day: int = _nth_weekday_of_month(year, 11, 0, 1)
	var dst_end: int = int(Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": 11, "day": nov_day, "hour": 6, "minute": 0, "second": 0}))

	if utc_unix >= dst_start and utc_unix < dst_end:
		return ET_OFFSET_EDT
	return ET_OFFSET_EST

static func _get_et_now() -> Dictionary:
	var utc_unix: int = int(Time.get_unix_time_from_system())
	var et_unix: int = utc_unix + _et_offset_minutes(utc_unix) * 60
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(et_unix)
	return {
		"weekday": dt.get("weekday", 0),
		"minute_of_day": dt.get("hour", 0) * 60 + dt.get("minute", 0),
		"hour": dt.get("hour", 0),
		"minute": dt.get("minute", 0),
	}

static func is_stock_awake() -> bool:
	if has_live_status() and _live_is_open:
		return true
	var et: Dictionary = _get_et_now()
	var weekday: int = et["weekday"]
	if weekday == 0 or weekday == 6:
		return false
	if is_holiday():
		return false
	var mod: int = et["minute_of_day"]
	return mod >= NYSE_OPEN_MIN - AWAKE_LEAD_MIN and mod < close_minute() + AWAKE_LEAD_MIN

static func is_market_open() -> bool:
	if has_live_status():
		return _live_is_open
	var et: Dictionary = _get_et_now()
	var weekday: int = et["weekday"]
	if weekday == 0 or weekday == 6:
		return false
	if is_holiday():
		return false
	var mod: int = et["minute_of_day"]
	return mod >= NYSE_OPEN_MIN and mod < close_minute()

static func is_market_awake(market: String) -> bool:
	if market == "crypto":
		return true
	return is_stock_awake()

static func debug_et_now_str() -> String:
	var et: Dictionary = _get_et_now()
	var utc_unix: int = int(Time.get_unix_time_from_system())
	var tz: String = "EDT" if _et_offset_minutes(utc_unix) == ET_OFFSET_EDT else "EST"
	return "ET %02d:%02d %s (weekday=%d)" % [et["hour"], et["minute"], tz, et["weekday"]]

static func et_now() -> Dictionary:
	var utc_unix: int = int(Time.get_unix_time_from_system())
	var et_unix: int = utc_unix + _et_offset_minutes(utc_unix) * 60
	return Time.get_datetime_dict_from_unix_time(et_unix)

static func et_now_string() -> String:
	var d: Dictionary = et_now()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(d.get("year", 1970)), int(d.get("month", 1)), int(d.get("day", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0)), int(d.get("second", 0))]
