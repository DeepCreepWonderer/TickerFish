extends AcceptDialog
const UITheme := preload("res://scripts/ui_theme.gd")
## 标的搜索对话框:本地表(打包基础表 + user 学习表)即时匹配;股票联网查 Finnhub /search,加密拉 Binance exchangeInfo 全量币种(去 USD 稳定币后缀取 base);选中即写入学习表。

signal ticker_picked(symbol: String)

const CATALOG_PATH := "res://tickers_catalog.json"
const LEARNED_PATH := "user://tickers_learned.json"
const CRYPTO_CACHE_PATH := "user://binance_symbols.json"
const MAX_RESULTS := 100
const DIALOG_TANK_MARGIN := 24
const ONLINE_MIN_LEN := 2
const ONLINE_DEBOUNCE := 0.35
const FINNHUB_SEARCH_URL := "https://finnhub.io/api/v1/search?q="
const BINANCE_HOSTS := ["https://data-api.binance.vision", "https://data.binance.com"]
const USD_QUOTES := ["USDT", "USDC", "FDUSD", "TUSD", "BUSD"]

var _market: String = "stocks"
var _items: Array = []
var _online_items: Array = []
var _selected_symbol: String = ""
var _selected_name: String = ""
var _tank_size: Vector2i = Vector2i.ZERO
var _ex_host_idx: int = 0

var _search_edit: LineEdit
var _result_list: ItemList
var _http: HTTPRequest
var _ex_http: HTTPRequest
var _debounce: Timer

func _ready() -> void:
	min_size = Vector2i(220, 240)
	size = Vector2i(260, 320)
	get_ok_button().text = Lang.t("search.select")
	var cancel_btn := add_cancel_button(Lang.t("dialog.cancel"))
	get_ok_button().disabled = true
	UITheme.style_primary_button(get_ok_button())
	UITheme.style_flat_button(cancel_btn)

	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.max_redirects = 0
	add_child(_http)
	_http.request_completed.connect(_on_search_response)

	_ex_http = HTTPRequest.new()
	_ex_http.timeout = 15.0
	add_child(_ex_http)
	_ex_http.request_completed.connect(_on_exchangeinfo_response)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = ONLINE_DEBOUNCE
	_debounce.timeout.connect(_on_debounce_timeout)
	add_child(_debounce)

	_build_ui()
	confirmed.connect(_on_confirm)
	about_to_popup.connect(_on_about_to_popup)

func _on_about_to_popup() -> void:
	var target_w: int = 260
	var target_h: int = 320
	if _tank_size.x > 0:
		target_w = mini(target_w, _tank_size.x - DIALOG_TANK_MARGIN)
	if _tank_size.y > 0:
		target_h = mini(target_h, _tank_size.y - DIALOG_TANK_MARGIN)
	target_w = maxi(target_w, min_size.x)
	target_h = maxi(target_h, min_size.y)
	size = Vector2i(target_w, target_h)

func set_tank_size(tank_size: Vector2i) -> void:
	_tank_size = tank_size

func setup(market: String) -> void:
	_market = market
	title = Lang.t("search.title_crypto") if market == "crypto" else Lang.t("search.title")
	_load_catalog()
	if _market == "crypto":
		_load_crypto_cache()
		_fetch_binance_symbols()
	_refresh_results("")

func _load_catalog() -> void:
	_items = []
	var base: Variant = _read_catalog_file(CATALOG_PATH)
	if base is Dictionary:
		for it in base.get(_market, []):
			_items.append(it)
	var learned: Variant = _read_catalog_file(LEARNED_PATH)
	if learned is Dictionary:
		var seen := {}
		for it in _items:
			seen[str(it.get("symbol", "")).to_upper()] = true
		for it in learned.get(_market, []):
			var sym: String = str(it.get("symbol", "")).to_upper()
			if sym != "" and not seen.has(sym):
				seen[sym] = true
				_items.append(it)

func _read_catalog_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP)
	add_child(root)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = Lang.t("search.placeholder")
	_search_edit.add_theme_font_size_override("font_size", UITheme.BODY)
	_search_edit.text_changed.connect(_on_search_changed)
	UITheme.style_input(_search_edit)
	root.add_child(_search_edit)

	_result_list = ItemList.new()
	_result_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_list.add_theme_font_size_override("font_size", UITheme.BODY)
	_result_list.item_selected.connect(_on_result_selected)
	_result_list.item_activated.connect(_on_result_activated)
	root.add_child(_result_list)

	var hint := Label.new()
	hint.text = Lang.t("search.online_hint_crypto") if _market == "crypto" else Lang.t("search.online_hint")
	hint.add_theme_font_size_override("font_size", UITheme.HINT)
	hint.modulate = UITheme.TEXT_DIM
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200, 0)
	root.add_child(hint)

func _on_search_changed(text: String) -> void:
	_refresh_results(text)
	if _market != "stocks":
		return
	var q := text.strip_edges()
	if q.length() >= ONLINE_MIN_LEN:
		_debounce.start()
	else:
		_debounce.stop()

func _on_debounce_timeout() -> void:
	_do_online_search(_search_edit.text.strip_edges())

func _do_online_search(query: String) -> void:
	if query.length() < ONLINE_MIN_LEN or _market != "stocks":
		return
	var key: String = _finnhub_key()
	if key == "":
		return
	_http.cancel_request()
	var url: String = FINNHUB_SEARCH_URL + query.uri_encode()
	var headers := PackedStringArray(["X-Finnhub-Token: " + key])
	_http.request(url, headers, HTTPClient.METHOD_GET)

func _on_search_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var out: Array = []
	for r in parsed.get("result", []):
		if not (r is Dictionary):
			continue
		var sym: String = str(r.get("symbol", "")).strip_edges().to_upper()
		if sym == "" or sym.contains(":") or sym.contains(" "):
			continue
		out.append({"symbol": sym, "name": str(r.get("description", sym))})
	_online_items = out
	_refresh_results(_search_edit.text)

func _load_crypto_cache() -> void:
	var d: Variant = _read_catalog_file(CRYPTO_CACHE_PATH)
	if d is Array:
		_online_items = []
		for b in d:
			_online_items.append({"symbol": str(b), "name": ""})

func _fetch_binance_symbols() -> void:
	_ex_http.cancel_request()
	_ex_http.request(BINANCE_HOSTS[_ex_host_idx] + "/api/v3/exchangeInfo")

func _on_exchangeinfo_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if _ex_host_idx + 1 < BINANCE_HOSTS.size():
			_ex_host_idx += 1
			_fetch_binance_symbols()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var seen := {}
	var bases: Array = []
	for s in parsed.get("symbols", []):
		if not (s is Dictionary):
			continue
		if str(s.get("status", "")) != "TRADING":
			continue
		if not (str(s.get("quoteAsset", "")) in USD_QUOTES):
			continue
		var base: String = str(s.get("baseAsset", "")).to_upper()
		if base == "" or seen.has(base) or base in StockFetcher.STABLECOINS:
			continue
		seen[base] = true
		bases.append(base)
	bases.sort()
	_online_items = []
	for b in bases:
		_online_items.append({"symbol": str(b), "name": ""})
	var f := FileAccess.open(CRYPTO_CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(bases))
		f.close()
	_refresh_results(_search_edit.text)

func _refresh_results(query: String) -> void:
	_result_list.clear()
	var q := query.strip_edges().to_lower()
	var shown := {}
	var count := 0
	for it in _items:
		if count >= MAX_RESULTS:
			break
		var sym: String = str(it.get("symbol", ""))
		var display_name: String = str(it.get("name", ""))
		if _market == "crypto" and sym.to_upper() in StockFetcher.STABLECOINS:
			continue
		if q == "" or sym.to_lower().begins_with(q) or display_name.to_lower().find(q) >= 0:
			if not shown.has(sym.to_upper()):
				shown[sym.to_upper()] = true
				_add_row(sym, display_name)
				count += 1
	for it in _online_items:
		if q == "" or count >= MAX_RESULTS:
			break
		var sym: String = str(it.get("symbol", ""))
		if _market == "crypto" and sym.to_upper() in StockFetcher.STABLECOINS:
			continue
		if not (sym.to_lower().begins_with(q) or str(it.get("name", "")).to_lower().find(q) >= 0):
			continue
		if shown.has(sym.to_upper()):
			continue
		shown[sym.to_upper()] = true
		_add_row(sym, str(it.get("name", "")))
		count += 1
	_selected_symbol = ""
	_selected_name = ""
	get_ok_button().disabled = true

func _add_row(sym: String, display_name: String) -> void:
	var text: String = sym if (display_name == "" or display_name.to_upper() == sym.to_upper()) else "%s  ·  %s" % [sym, display_name]
	_result_list.add_item(text)
	_result_list.set_item_metadata(_result_list.item_count - 1, {"symbol": sym, "name": display_name})

func _on_result_selected(idx: int) -> void:
	var m: Dictionary = _result_list.get_item_metadata(idx)
	_selected_symbol = str(m.get("symbol", ""))
	_selected_name = str(m.get("name", ""))
	get_ok_button().disabled = _selected_symbol == ""

func _on_result_activated(idx: int) -> void:
	var m: Dictionary = _result_list.get_item_metadata(idx)
	_selected_symbol = str(m.get("symbol", ""))
	_selected_name = str(m.get("name", ""))
	_emit_and_close()

func _on_confirm() -> void:
	if _selected_symbol == "":
		return
	_emit_and_close()

func _emit_and_close() -> void:
	_learn(_selected_symbol, _selected_name)
	ticker_picked.emit(_selected_symbol)
	queue_free()

func _learn(symbol: String, display_name: String) -> void:
	var sym: String = symbol.strip_edges().to_upper()
	if sym == "":
		return
	for it in _items:
		if str(it.get("symbol", "")).to_upper() == sym:
			return
	var learned: Variant = _read_catalog_file(LEARNED_PATH)
	var data: Dictionary = learned if learned is Dictionary else {}
	var list: Array = data.get(_market, []) if data.get(_market, []) is Array else []
	list.append({"symbol": sym, "name": display_name if display_name != "" else sym})
	data[_market] = list
	var f := FileAccess.open(LEARNED_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _finnhub_key() -> String:
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
