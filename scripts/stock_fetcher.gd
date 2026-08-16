extends Node
## 行情轮询器:美股走 Finnhub、加密货币走 Binance(CoinGecko 兜底),写出 prices.json 给下游。

const FINNHUB_BASE_URL := "https://finnhub.io/api/v1"
const BINANCE_HOSTS := ["https://data-api.binance.vision", "https://data.binance.com"]
const COINGECKO_BASE := "https://api.coingecko.com/api/v3"
const CG_IDS := {
	"BTC": "bitcoin", "ETH": "ethereum", "BNB": "binancecoin", "SOL": "solana",
	"XRP": "ripple", "ADA": "cardano", "DOGE": "dogecoin", "TRX": "tron",
	"TON": "the-open-network", "AVAX": "avalanche-2", "SHIB": "shiba-inu",
	"DOT": "polkadot", "LINK": "chainlink", "MATIC": "matic-network", "LTC": "litecoin",
	"BCH": "bitcoin-cash", "UNI": "uniswap", "XLM": "stellar", "ATOM": "cosmos",
	"ETC": "ethereum-classic", "XMR": "monero", "FIL": "filecoin", "APT": "aptos",
	"ARB": "arbitrum", "OP": "optimism", "NEAR": "near", "INJ": "injective-protocol",
	"SUI": "sui", "PEPE": "pepe",
}

const STABLECOINS := ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USDP", "USDD", "USDS", "USD1",
	"DAI", "PYUSD", "RLUSD", "FRAX", "LUSD", "GUSD", "USDE", "SUSD", "UST", "USTC", "EURT", "EURS"]
const DEFAULT_INTERVAL := 60
const MIN_CYCLE := 5
const REQUEST_TIMEOUT := 10.0

const SYMBOL_REGEX := "^[A-Za-z0-9.\\-:]{1,20}$"

const KLINE_INTERVAL := "15m"
const KLINE_LIMIT := 96
const KLINE_REFRESH_MS := 300000

const STATUS_IDLE_INTERVAL_MS := 15 * 60 * 1000

const CG_MAP_PATH := "user://crypto_cg_map.json"
const ENRICH_PRICE_TOL := 0.02

var _http: HTTPRequest
var _symbol_re: RegEx
var _busy: bool = false
var _next_due_ms: int = 0
var _prev_tickers: Dictionary = {}
var _klines_cache: Dictionary = {}
var _klines_next_ms: int = 0
var _binance_host_idx: int = 0
var _bad_pairs: Dictionary = {}
var _cg_map: Dictionary = {}

var _last_tls_fail: bool = false

var _last_error: String = ""
var _had_fresh: bool = false
var _last_live_open: bool = false
var _last_live_holiday: String = ""
var _status_next_ms: int = 0

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.max_redirects = 0
	add_child(_http)

	_symbol_re = RegEx.new()
	_symbol_re.compile(SYMBOL_REGEX)

	_cg_map = _load_cg_map()
	_prev_tickers = _load_cached_tickers()

	_next_due_ms = Time.get_ticks_msec()

	var t := Timer.new()
	t.wait_time = 1.0
	t.timeout.connect(_on_tick)
	add_child(t)
	t.start()
	print("[StockFetcher] Ready (native GDScript Finnhub fetcher).")

func _on_tick() -> void:
	if _busy:
		return
	if Time.get_ticks_msec() < _next_due_ms:
		return
	_run_cycle()

func _run_cycle() -> void:
	_busy = true
	var interval: int = maxi(_get_interval(), MIN_CYCLE)
	_next_due_ms = Time.get_ticks_msec() + interval * 1000

	var entries: Array = []
	if IdleSystem != null:
		entries = IdleSystem.get_all_watchlist_entries()
	if entries.is_empty():
		entries = [{"market": "stocks", "symbol": "AAPL", "name": "Apple Inc."}]

	var stock_entries: Array = []
	var crypto_entries: Array = []
	for e in entries:
		if str(e.get("market", "stocks")) == "crypto":
			crypto_entries.append(e)
		else:
			stock_entries.append(e)

	_last_error = ""
	_had_fresh = false

	var tickers: Dictionary = {}
	if not crypto_entries.is_empty():
		tickers.merge(await _cycle_binance(crypto_entries), true)
		if Time.get_ticks_msec() >= _klines_next_ms:
			await _refresh_klines(crypto_entries)
			_klines_next_ms = Time.get_ticks_msec() + KLINE_REFRESH_MS

	var stocks_need_key := false
	if not stock_entries.is_empty():
		var key: String = _get_finnhub_key()
		if key == "":
			stocks_need_key = true
			for e in stock_entries:
				var tk: String = _ticker_key(e)
				if _prev_tickers.has(tk):
					tickers[tk] = _cached_entry(tk)
		else:
			await _refresh_market_status(key)
			var to_fetch: Array = stock_entries
			if not MarketClock.is_market_awake("stocks"):
				to_fetch = []
				for e in stock_entries:
					var tk: String = _ticker_key(e)
					if _prev_tickers.has(tk):
						tickers[tk] = _cached_entry(tk)
					else:
						to_fetch.append(e)
			if not to_fetch.is_empty():
				tickers.merge(await _cycle_finnhub(to_fetch, key), true)

	var error_code: String = ""
	if not _had_fresh and _last_error != "":
		error_code = _last_error

	var not_ready: Dictionary = {}
	if stocks_need_key:
		not_ready["stocks"] = "Please enter your Finnhub API key in settings"

	var status: String = "ok"
	if stocks_need_key:
		status = "needs_config"
	elif tickers.is_empty():
		status = "no_data"
	var snapshot := {
		"updated_at": _utc_now_iso(),
		"status": status,
		"error": error_code,
		"tickers": tickers,
		"bars": _klines_cache,
		"providers_not_ready": not_ready,
	}
	_prev_tickers = tickers
	_write_atomic(snapshot)
	if not crypto_entries.is_empty():
		await _enrich_one_crypto(crypto_entries, tickers)
	_busy = false

# ---- 传输层:证书一律验证,握手失败即报错 ----

func _is_tls_fail(res: Array) -> bool:
	return not res.is_empty() and int(res[0]) == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR

func _request(url: String, headers := PackedStringArray()) -> Array:
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_last_tls_fail = false
		return []
	var res: Array = await _http.request_completed
	_last_tls_fail = _is_tls_fail(res)
	if _last_tls_fail:
		push_warning("[StockFetcher] TLS handshake rejected by " + url.get_slice("/", 2)
			+ "; an HTTPS scanner or proxy is intercepting the connection")
	return res

func _transport_error() -> String:
	return "tls_blocked" if _last_tls_fail else "no_connection"

func _load_cached_tickers() -> Dictionary:
	if BackendManager == null:
		return {}
	var path: String = BackendManager.get_data_dir() + "prices.json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var tk = parsed.get("tickers", {})
	if not (tk is Dictionary):
		return {}
	print("[StockFetcher] Seeded cache from prices.json (", tk.size(), " tickers).")
	return tk

func _cached_entry(key: String) -> Dictionary:
	var e: Dictionary = (_prev_tickers[key] as Dictionary).duplicate()
	e["market_open"] = false
	return e

func _ticker_key(e: Dictionary) -> String:
	return str(e.get("market", "stocks")) + ":" + str(e.get("symbol", "")).strip_edges().to_upper()

func _binance_pair(sym: String) -> String:
	for q in ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USD"]:
		if sym.ends_with(q):
			return sym
	return sym + "USDT"

func _cycle_binance(entries: Array) -> Dictionary:
	var query_syms: Array = []
	var info_by_query: Dictionary = {}
	for e in entries:
		var symbol: String = str(e.get("symbol", "")).strip_edges().to_upper()
		if symbol == "" or _symbol_re.search(symbol) == null:
			continue
		var qsym: String = _binance_pair(symbol)
		if not info_by_query.has(qsym):
			query_syms.append(qsym)
			info_by_query[qsym] = {"orig": symbol, "name": str(e.get("name", symbol))}
	if query_syms.is_empty():
		return {}
	var batch_syms: Array = []
	for qsym in query_syms:
		if not _bad_pairs.has(qsym):
			batch_syms.append(qsym)
	var parsed: Dictionary = {}
	if not batch_syms.is_empty():
		parsed = await _fetch_binance_24hr(batch_syms)
	if parsed.is_empty():
		parsed = await _fetch_coingecko(query_syms)
	var tickers: Dictionary = {}
	for qsym in query_syms:
		var info: Dictionary = info_by_query[qsym]
		var orig: String = str(info["orig"])
		var ticker_key: String = "crypto:" + orig
		var q = parsed.get(qsym, {})
		if q is Dictionary and not q.is_empty():
			tickers[ticker_key] = _wrap("crypto", orig, str(info["name"]), q)
		elif _prev_tickers.has(ticker_key):
			tickers[ticker_key] = _cached_entry(ticker_key)
	return tickers

func _refresh_klines(entries: Array) -> void:
	for e in entries:
		var symbol: String = str(e.get("symbol", "")).strip_edges().to_upper()
		if symbol == "" or _symbol_re.search(symbol) == null:
			continue
		var pair: String = _binance_pair(symbol)
		if _bad_pairs.has(pair):
			continue
		var bars: Array = await _fetch_binance_klines(pair)
		if not bars.is_empty():
			_klines_cache["crypto:" + symbol] = bars

func _fetch_binance_klines(qsym: String) -> Array:
	var path: String = "/api/v3/klines?symbol=" + qsym.uri_encode() \
		+ "&interval=" + KLINE_INTERVAL + "&limit=" + str(KLINE_LIMIT)
	var res: Array = await _binance_fetch(path)
	if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return []
	var json := JSON.new()
	if json.parse((res[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return []
	var d = json.data
	var out: Array = []
	if d is Array:
		for k in d:
			if k is Array and k.size() >= 5:
				out.append({
					"o": snappedf(float(k[1]), 0.0001),
					"h": snappedf(float(k[2]), 0.0001),
					"l": snappedf(float(k[3]), 0.0001),
					"c": snappedf(float(k[4]), 0.0001),
				})
	return out

func _fetch_binance_24hr(symbols: Array) -> Dictionary:
	var parts: Array = []
	for s in symbols:
		parts.append("\"" + str(s) + "\"")
	var arr: String = "[" + ",".join(parts) + "]"
	var res: Array = await _binance_fetch("/api/v3/ticker/24hr?symbols=" + arr.uri_encode())
	if res.is_empty():
		_last_error = _transport_error()
		return {}
	var result: int = int(res[0])
	var code: int = int(res[1])
	var body: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		_last_error = _transport_error()
		return {}
	if code == 400:
		return await _probe_binance_symbols(symbols)
	if code != 200:
		_last_error = _classify_http(code)
		push_warning("[StockFetcher] Binance 24hr failed (code=%d): %s" % [code, body.get_string_from_utf8()])
		return {}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	var d = json.data
	var out: Dictionary = {}
	if d is Array:
		for item in d:
			if item is Dictionary:
				var sym: String = str(item.get("symbol", "")).to_upper()
				var q: Dictionary = _parse_binance(item)
				if not q.is_empty():
					out[sym] = q
	if not out.is_empty():
		_had_fresh = true
	return out

func _probe_binance_symbols(symbols: Array) -> Dictionary:
	var out: Dictionary = {}
	for s in symbols:
		var qsym: String = str(s)
		var res: Array = await _binance_fetch("/api/v3/ticker/24hr?symbol=" + qsym.uri_encode())
		if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS:
			_last_error = _transport_error()
			continue
		var code: int = int(res[1])
		if code == 400:
			_bad_pairs[qsym] = true
			push_warning("[StockFetcher] Binance rejects %s; excluded from batch quotes" % qsym)
			continue
		if code != 200:
			_last_error = _classify_http(code)
			continue
		var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if not (d is Dictionary):
			continue
		var q: Dictionary = _parse_binance(d)
		if not q.is_empty():
			out[str(d.get("symbol", qsym)).to_upper()] = q
	if not out.is_empty():
		_had_fresh = true
	return out

func _parse_binance(d: Dictionary) -> Dictionary:
	var price: float = float(d.get("lastPrice", 0))
	if price == 0.0:
		return {}
	var open_price: float = float(d.get("openPrice", 0))
	var day_high: float = float(d.get("highPrice", 0))
	var day_low: float = float(d.get("lowPrice", 0))
	var change_pct: float = float(d.get("priceChangePercent", 0))

	var high_v: Variant = null
	if day_high > 0.0:
		high_v = snappedf(day_high, 0.0001)
	var low_v: Variant = null
	if day_low > 0.0:
		low_v = snappedf(day_low, 0.0001)

	return {
		"price": snappedf(price, 0.0001),
		"open_price": snappedf(open_price, 0.0001),
		"previous_close": snappedf(open_price, 0.0001),
		"high": high_v,
		"low": low_v,
		"change_pct": snappedf(change_pct, 0.01),
		"currency": "USDT",
		"market_open": true,
		"last_trade_at": _utc_now_iso(),
	}

func _binance_fetch(path: String) -> Array:
	var n: int = BINANCE_HOSTS.size()
	for i in n:
		var idx: int = (_binance_host_idx + i) % n
		var res: Array = await _request(str(BINANCE_HOSTS[idx]) + path)
		if res.is_empty():
			continue
		var result: int = int(res[0])
		var code: int = int(res[1])
		if result != HTTPRequest.RESULT_SUCCESS or code == 451 or code == 403 or code >= 500:
			continue
		_binance_host_idx = idx
		return res
	return []

func _base_of(qsym: String) -> String:
	for q in ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USD"]:
		if qsym.length() > q.length() and qsym.ends_with(q):
			return qsym.substr(0, qsym.length() - q.length())
	return qsym

func _load_cg_map() -> Dictionary:
	if not FileAccess.file_exists(CG_MAP_PATH):
		return {}
	var f := FileAccess.open(CG_MAP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var d = JSON.parse_string(text)
	return d if d is Dictionary else {}

func _save_cg_map() -> void:
	var f := FileAccess.open(CG_MAP_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cg_map, "  "))
	f.close()

func _enrich_one_crypto(entries: Array, tickers: Dictionary) -> void:
	for e in entries:
		var base: String = str(e.get("symbol", "")).strip_edges().to_upper()
		if base == "" or _cg_map.has(base) or CG_IDS.has(base):
			continue
		var q = tickers.get("crypto:" + base, {})
		if not (q is Dictionary):
			continue
		var bprice: float = float(q.get("price", 0.0))
		if bprice <= 0.0:
			continue
		await _enrich_coin(base, bprice)
		return

func _enrich_coin(base: String, bprice: float) -> void:
	var cands: Variant = await _cg_search_symbol(base)
	if cands == null:
		return
	var list: Array = cands
	if list.is_empty():
		_cg_map[base] = {"cg_id": "", "name": "", "pair": _binance_pair(base)}
		_save_cg_map()
		return
	var ids: Array = []
	for c in list.slice(0, 3):
		ids.append(str(c["id"]))
	var prices: Dictionary = await _cg_prices(ids)
	var chosen: Dictionary = {}
	for c in list:
		var p: float = float(prices.get(str(c["id"]), 0.0))
		if p > 0.0 and absf(p - bprice) / bprice <= ENRICH_PRICE_TOL:
			chosen = c
			break
	if chosen.is_empty():
		chosen = list[0]
	_cg_map[base] = {"cg_id": str(chosen["id"]), "name": str(chosen["name"]), "pair": _binance_pair(base)}
	_save_cg_map()
	print("[StockFetcher] Enriched ", base, " -> ", chosen["id"], " (", chosen["name"], ")")

func _cg_search_symbol(base: String) -> Variant:
	var res: Array = await _request(COINGECKO_BASE + "/search?query=" + base.uri_encode())
	if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return null
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary):
		return null
	var out: Array = []
	for c in d.get("coins", []):
		if c is Dictionary and str(c.get("symbol", "")).to_upper() == base:
			out.append({"id": str(c.get("id", "")), "name": str(c.get("name", ""))})
	return out

func _cg_prices(ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var url: String = COINGECKO_BASE + "/simple/price?ids=" + (",".join(ids)).uri_encode() + "&vs_currencies=usd"
	var res: Array = await _request(url)
	if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary):
		return {}
	var out: Dictionary = {}
	for id in d:
		var row = d[id]
		if row is Dictionary and row.has("usd"):
			out[str(id)] = float(row["usd"])
	return out

func _fetch_coingecko(query_syms: Array) -> Dictionary:
	var id_to_qsym: Dictionary = {}
	var ids: Array = []
	for qsym in query_syms:
		var base: String = _base_of(str(qsym))
		var id: String = str((_cg_map.get(base, {}) as Dictionary).get("cg_id", ""))
		if id == "":
			id = str(CG_IDS.get(base, ""))
		if id == "" or id_to_qsym.has(id):
			continue
		id_to_qsym[id] = qsym
		ids.append(id)
	if ids.is_empty():
		return {}
	var url: String = COINGECKO_BASE + "/simple/price?ids=" + (",".join(ids)).uri_encode() \
		+ "&vs_currencies=usd&include_24hr_change=true"
	var res: Array = await _request(url)
	if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var json := JSON.new()
	if json.parse((res[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return {}
	var d = json.data
	if not (d is Dictionary):
		return {}
	var out: Dictionary = {}
	for id in id_to_qsym:
		var row = d.get(id, {})
		if not (row is Dictionary) or not row.has("usd"):
			continue
		var price: float = float(row["usd"])
		if price == 0.0:
			continue
		var chg: float = float(row.get("usd_24h_change", 0.0))
		var prev: float = (price / (1.0 + chg / 100.0)) if chg > -100.0 else price
		out[id_to_qsym[id]] = {
			"price": snappedf(price, 0.0001),
			"open_price": snappedf(prev, 0.0001),
			"previous_close": snappedf(prev, 0.0001),
			"high": null,
			"low": null,
			"change_pct": snappedf(chg, 0.01),
			"currency": "USDT",
			"market_open": true,
			"last_trade_at": _utc_now_iso(),
		}
	if not out.is_empty():
		_had_fresh = true
	return out

func _classify_http(code: int) -> String:
	if code == 401 or code == 403:
		return "bad_key"
	if code == 429:
		return "rate_limited"
	return "http_error"

func _refresh_market_status(key: String) -> void:
	var now: int = Time.get_ticks_msec()
	if not MarketClock.is_stock_awake() and now < _status_next_ms:
		return
	_status_next_ms = now + (0 if MarketClock.is_stock_awake() else STATUS_IDLE_INTERVAL_MS)

	var url: String = FINNHUB_BASE_URL + "/stock/market-status?exchange=US"
	var res: Array = await _request(url, PackedStringArray(["X-Finnhub-Token: " + key]))
	if res.is_empty() or int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.has("isOpen"):
		return
	var hol = parsed.get("holiday", null)
	var holiday: String = "" if hol == null else str(hol)
	var is_open: bool = bool(parsed["isOpen"])
	if is_open != _last_live_open or holiday != _last_live_holiday:
		_last_live_open = is_open
		_last_live_holiday = holiday
		print("[StockFetcher] Market status: open=", is_open,
			(" holiday=" + holiday) if holiday != "" else "")
	MarketClock.set_live_status(is_open, holiday)

func _cycle_finnhub(entries: Array, key: String) -> Dictionary:
	var tickers: Dictionary = {}
	for e in entries:
		var market: String = str(e.get("market", "stocks"))
		var symbol: String = str(e.get("symbol", "")).strip_edges().to_upper()
		if symbol == "" or _symbol_re.search(symbol) == null:
			continue
		var disp_name: String = str(e.get("name", symbol))
		var ticker_key: String = market + ":" + symbol

		var data: Dictionary = await _fetch_one(symbol, key)
		if data.is_empty():
			if _prev_tickers.has(ticker_key):
				tickers[ticker_key] = _cached_entry(ticker_key)
			continue
		tickers[ticker_key] = _wrap(market, symbol, disp_name, data)
	return tickers

func _fetch_one(symbol: String, key: String) -> Dictionary:
	var url: String = FINNHUB_BASE_URL + "/quote?symbol=" + symbol.uri_encode()
	var headers := PackedStringArray(["X-Finnhub-Token: " + key])
	var res: Array = await _request(url, headers)
	if res.is_empty():
		_last_error = _transport_error()
		return {}
	var result: int = int(res[0])
	var code: int = int(res[1])
	var body: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		_last_error = _transport_error()
		return {}
	if code != 200:
		_last_error = _classify_http(code)
		return {}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	var d = json.data
	if not (d is Dictionary):
		return {}
	var q: Dictionary = _parse_quote(d)
	if not q.is_empty():
		_had_fresh = true
	return q

func _parse_quote(d: Dictionary) -> Dictionary:
	var current_price: float = float(d.get("c", 0))
	var previous_close: float = float(d.get("pc", 0))
	var open_price: float = float(d.get("o", 0))
	var day_high: float = float(d.get("h", 0))
	var day_low: float = float(d.get("l", 0))

	if current_price == 0.0:
		return {}

	var ref_price: float = previous_close if previous_close > 0.0 else open_price
	var change_pct: float = 0.0
	if ref_price > 0.0:
		change_pct = (current_price - ref_price) / ref_price * 100.0

	var ts: int = int(d.get("t", 0))
	var last_trade: String
	var market_open_now: bool = false
	if ts > 0:
		last_trade = _unix_to_iso(ts)
		market_open_now = (Time.get_unix_time_from_system() - float(ts)) < 30.0 * 60.0
	else:
		last_trade = _utc_now_iso()

	var high_v: Variant = null
	if day_high > 0.0:
		high_v = snappedf(day_high, 0.0001)
	var low_v: Variant = null
	if day_low > 0.0:
		low_v = snappedf(day_low, 0.0001)

	return {
		"price": snappedf(current_price, 0.0001),
		"open_price": snappedf(open_price, 0.0001),
		"previous_close": snappedf(previous_close, 0.0001),
		"high": high_v,
		"low": low_v,
		"change_pct": snappedf(change_pct, 0.01),
		"currency": "USD",
		"market_open": market_open_now,
		"last_trade_at": last_trade,
	}

func _wrap(market: String, symbol: String, display_name: String, data: Dictionary) -> Dictionary:
	return {
		"market": market,
		"symbol": symbol,
		"display_name": display_name,
		"price": data.get("price"),
		"open_price": data.get("open_price"),
		"previous_close": data.get("previous_close"),
		"high": data.get("high"),
		"low": data.get("low"),
		"change_pct": data.get("change_pct"),
		"currency": data.get("currency", "USD"),
		"market_open": data.get("market_open", true),
		"last_trade_at": data.get("last_trade_at", _utc_now_iso()),
	}

func _get_finnhub_key() -> String:
	if BackendManager == null:
		return ""
	var cfg: Dictionary = BackendManager.get_api_config()
	var ref: String = "finnhub"
	var stocks = cfg.get("stocks", {})
	if stocks is Dictionary:
		var r: String = str(stocks.get("api_key_ref", "finnhub"))
		if r != "":
			ref = r
	var keys: Dictionary = BackendManager.get_api_keys()
	return str(keys.get(ref, "")).strip_edges()

func _get_interval() -> int:
	if BackendManager == null:
		return DEFAULT_INTERVAL
	var ivs: Dictionary = BackendManager.get_market_intervals()
	return int(ivs.get("stocks", DEFAULT_INTERVAL))

func _write_atomic(snapshot: Dictionary) -> void:
	var path: String = BackendManager.get_data_dir() + "prices.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp_path: String = path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[StockFetcher] cannot write prices.json tmp: " + tmp_path)
		return
	f.store_string(JSON.stringify(snapshot, "  "))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_error("[StockFetcher] cannot open data dir: " + path.get_base_dir())
		return
	dir.rename(tmp_path.get_file(), path.get_file())

func _utc_now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"

func _unix_to_iso(ts: int) -> String:
	return Time.get_datetime_string_from_unix_time(ts) + "Z"
