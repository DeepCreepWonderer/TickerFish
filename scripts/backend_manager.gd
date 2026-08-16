extends Node
## 后端状态机 + api 配置/密钥/数据目录读取;Autoload。

signal backend_state_changed(state: int)

enum {
	STATE_DEV,
	STATE_STARTING,
	STATE_RUNNING,
}

var _state: int = STATE_DEV

func _ready() -> void:
	_state = STATE_STARTING
	backend_state_changed.emit(_state)
	print("[Backend] Using native StockFetcher (no external fetcher process)")
	_ensure_editor_data_dir()

func mark_running() -> void:
	if _state == STATE_STARTING or _state == STATE_DEV:
		_state = STATE_RUNNING
		backend_state_changed.emit(_state)
		print("[Backend] backend ready")

func get_data_dir() -> String:
	if not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join("DataBridge") + "/"
	return ProjectSettings.globalize_path("res://") + "DataBridge/"

func _ensure_editor_data_dir() -> void:
	if not OS.has_feature("editor"):
		return
	var dir_abs: String = get_data_dir().trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var ignore: String = dir_abs.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var f := FileAccess.open(ignore, FileAccess.WRITE)
		if f != null:
			f.store_string("")
			f.close()

func get_state() -> int:
	return _state

func get_api_config_path() -> String:
	if not OS.has_feature("editor"):
		return OS.get_executable_path().get_base_dir().path_join("api_config.json")

	var root: String = ProjectSettings.globalize_path("res://")
	var candidates := [
		root + "api_config.json",
		root + "../Backend/api_config.json",
		root + "Backend/api_config.json",
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return candidates[0]

func get_api_config() -> Dictionary:
	var path := get_api_config_path()
	if not FileAccess.file_exists(path):
		push_warning("[Backend] api_config.json not found: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("[Backend] failed to parse api_config.json")
		return {}
	return parsed

func get_api_keys() -> Dictionary:
	var cfg := get_api_config()
	var keys = cfg.get("api_keys", {})
	if keys is Dictionary:
		return keys
	return {}

const DEFAULT_API_CONFIG := {
	"stocks": {
		"provider": "finnhub",
		"api_key_ref": "finnhub",
		"min_interval_seconds": 60,
	},
	"api_keys": {
		"finnhub": "",
	},
}

const STOCK_PROVIDER_DEFAULT := "finnhub"
const STOCK_PROVIDER_VALID := ["finnhub"]

func get_stock_provider() -> String:
	var cfg := get_api_config()
	var stocks = cfg.get("stocks", {})
	if stocks is Dictionary:
		var p: String = str(stocks.get("provider", STOCK_PROVIDER_DEFAULT))
		if p in STOCK_PROVIDER_VALID:
			return p
	return STOCK_PROVIDER_DEFAULT

func save_api_keys(new_keys: Dictionary) -> bool:
	var cfg := get_api_config()
	if cfg.is_empty():
		cfg = DEFAULT_API_CONFIG.duplicate(true)
	cfg["api_keys"] = new_keys
	return _write_config_atomic(cfg)


const DEFAULT_MARKET_INTERVAL := 60

func get_market_intervals() -> Dictionary:
	var cfg := get_api_config()
	var out := {}
	for market in cfg.keys():
		if typeof(market) != TYPE_STRING:
			continue
		if market.begins_with("_") or market == "api_keys":
			continue
		var entry = cfg[market]
		if not (entry is Dictionary):
			continue
		var v = entry.get("min_interval_seconds", DEFAULT_MARKET_INTERVAL)
		var seconds: int = DEFAULT_MARKET_INTERVAL
		match typeof(v):
			TYPE_INT:
				seconds = v
			TYPE_FLOAT:
				seconds = int(v)
			TYPE_STRING:
				if v.is_valid_int():
					seconds = v.to_int()
		out[market] = max(seconds, 1)
	return out

func _write_config_atomic(cfg: Dictionary) -> bool:
	var path := get_api_config_path()
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[Backend] cannot write tmp file: " + tmp_path)
		return false
	f.store_string(JSON.stringify(cfg, "  "))
	f.close()

	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_error("[Backend] cannot open directory: " + path.get_base_dir())
		return false
	var err := dir.rename(tmp_path.get_file(), path.get_file())
	if err != OK:
		push_error("[Backend] rename failed err=" + str(err))
		return false

	print("[Backend] api_config.json saved, fetcher will hot-reload within the next poll cycle")
	return true

const PROVIDER_ATTRIBUTION := {
	"finnhub": {"display_name": "Finnhub", "url": "https://finnhub.io"},
}

const CRYPTO_ATTRIBUTION := [
	{"display_name": "Binance", "url": "https://www.binance.com", "role": "primary"},
	{"display_name": "CoinGecko", "url": "https://www.coingecko.com", "role": "fallback"},
]

func get_active_data_sources() -> Array:
	var out: Array = []
	var provider := get_stock_provider()
	var info: Dictionary = PROVIDER_ATTRIBUTION.get(
		provider, {"display_name": provider.capitalize(), "url": ""})
	out.append({
		"market": "stocks",
		"display_name": str(info.get("display_name", "")),
		"url": str(info.get("url", "")),
		"role": "primary",
		"description": "",
	})
	for c in CRYPTO_ATTRIBUTION:
		out.append({
			"market": "crypto",
			"display_name": str(c.get("display_name", "")),
			"url": str(c.get("url", "")),
			"role": str(c.get("role", "primary")),
			"description": "",
		})
	return out
