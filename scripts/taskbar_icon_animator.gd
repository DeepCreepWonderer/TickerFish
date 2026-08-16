extends Node
## 任务栏图标动画:跟踪自选表第一条,涨绿跌红的像素鱼,每帧刷 OS 图标;Autoload。

const ICON_PX := 64
const ANIM_JSON_PATH := "res://tickerfish-anim.json"
const DRAW_CHART_BG := true

const EMBEDDED := {
	"grid": {
		"cols": 16,
		"rows": 11
	},
	"fps": 12.5,
	"palettes": {
		"up": {
			"1": "#16c784",
			"2": "#3ee08f",
			"3": "#ffffff",
			"4": "#0c8f57",
			"5": "#0a1729"
		},
		"down": {
			"1": "#ea3943",
			"2": "#ff6b78",
			"3": "#ffffff",
			"4": "#c01f2e",
			"5": "#0a1729"
		}
	},
	"masks": [
		[[0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,0],[0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0],[0,2,2,0,0,1,1,1,1,1,1,1,1,1,0,0],[0,0,2,2,1,1,1,1,1,1,1,1,1,1,1,0],[0,0,0,2,1,1,1,1,1,1,1,1,3,5,1,0],[0,0,0,2,1,1,1,1,1,1,1,1,1,1,1,0],[0,0,0,2,1,1,1,1,1,1,1,1,1,1,1,0],[0,0,2,2,0,1,1,1,4,4,1,1,1,1,0,0],[0,2,2,0,0,0,0,1,1,1,1,1,1,0,0,0],[0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]],
		[[0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,0],[0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0],[0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,0],[0,2,2,0,1,1,1,1,1,1,1,1,1,1,1,0],[0,0,2,2,1,1,1,1,1,1,1,1,3,5,1,0],[0,0,0,2,1,1,1,1,1,1,1,1,1,1,1,0],[0,0,2,2,1,1,1,1,1,1,1,1,1,1,1,0],[0,2,2,0,0,1,1,1,4,4,1,1,1,1,0,0],[0,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0],[0,0,0,0,0,0,0,0,2,2,2,0,0,0,0,0],[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]]
	],
	"frames": [
		{
			"mask": 0,
			"dy": 0
		},
		{
			"mask": 0,
			"dy": 0.23
		},
		{
			"mask": 0,
			"dy": 0.424
		},
		{
			"mask": 0,
			"dy": 0.554
		},
		{
			"mask": 1,
			"dy": 0.6
		},
		{
			"mask": 1,
			"dy": 0.554
		},
		{
			"mask": 1,
			"dy": 0.424
		},
		{
			"mask": 1,
			"dy": 0.23
		},
		{
			"mask": 0,
			"dy": 0
		},
		{
			"mask": 0,
			"dy": -0.23
		},
		{
			"mask": 0,
			"dy": -0.424
		},
		{
			"mask": 0,
			"dy": -0.554
		},
		{
			"mask": 1,
			"dy": -0.6
		},
		{
			"mask": 1,
			"dy": -0.554
		},
		{
			"mask": 1,
			"dy": -0.424
		},
		{
			"mask": 1,
			"dy": -0.23
		}
	],
	"background": {
		"tile": {
			"cornerRadiusRatio": 0.2237,
			"up": {
				"fill": [
					"#16314f",
					"#0a1729"
				],
				"radial": true
			},
			"down": {
				"fill": [
					"#3a1622",
					"#120810"
				],
				"radial": true
			}
		},
		"grid": {
			"divisions": 12,
			"color": "#78c8ff",
			"opacity": 0.06
		},
		"chart": {
			"viewBox": [332,300],
			"strokeWidth": 3.5,
			"up": {
				"color": "#22e08d",
				"areaOpacity": 0.3,
				"points": [[0,236],[40,216],[72,226],[110,182],[150,196],[190,152],[230,166],[272,120],[332,94]]
			},
			"down": {
				"color": "#ff4d5e",
				"areaOpacity": 0.3,
				"points": [[0,64],[40,84],[72,74],[110,118],[150,104],[190,148],[230,134],[272,180],[332,206]]
			}
		},
		"note": "Draw tile (rounded), then faint grid, then chart area+line (points in viewBox coords, scale to tile), then the fish frames on top. Use up/down to match rising/falling."
	}
}

var _fps: float = 12.5
var _cols: int = 16
var _rows: int = 11
var _frames_up: Array = []
var _frames_down: Array = []
var _n: int = 0
var _idx: int = 0
var _accum: float = 0.0
var _is_up: bool = true
var _active: bool = false

func _ready() -> void:
	set_process(false)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_ICON):
		push_warning("[TaskbarIcon] platform has no window-icon support; disabled")
		return
	var spec: Dictionary = _load_spec()
	if spec.is_empty():
		push_warning("[TaskbarIcon] no animation spec; disabled")
		return
	_prerender(spec)
	if _n == 0:
		push_warning("[TaskbarIcon] zero frames rendered; disabled")
		return
	_active = true

	if IdleSystem != null:
		IdleSystem.fish_list_changed.connect(_refresh_tracked)
		IdleSystem.numeric_list_changed.connect(_refresh_tracked)
	if DataReader != null and DataReader.has_signal("prices_updated"):
		DataReader.prices_updated.connect(_recompute_direction)

	_refresh_tracked()
	_idx = 0
	_apply_current()
	print("[TaskbarIcon] active. frames=", _n, " fps=", _fps, " key=", _resolve_key())


func _load_spec() -> Dictionary:
	if FileAccess.file_exists(ANIM_JSON_PATH):
		var f := FileAccess.open(ANIM_JSON_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("masks") and parsed.has("frames"):
				return parsed
	return EMBEDDED.duplicate(true)

func _prerender(spec: Dictionary) -> void:
	var grid: Dictionary = spec.get("grid", {})
	_cols = int(grid.get("cols", 16))
	_rows = int(grid.get("rows", 11))
	_fps = float(spec.get("fps", 12.5))
	if _fps <= 0.0:
		_fps = 12.5
	var masks: Array = spec.get("masks", [])
	var frames: Array = spec.get("frames", [])
	var pals: Dictionary = spec.get("palettes", {})
	var pal_up: Dictionary = pals.get("up", {})
	var pal_down: Dictionary = pals.get("down", {})
	var bgspec: Dictionary = spec.get("background", {}) if DRAW_CHART_BG else {}
	var bg_up: Image = _make_bg(bgspec, true)
	var bg_down: Image = _make_bg(bgspec, false)
	for fr in frames:
		var mi: int = int(fr.get("mask", 0))
		if mi < 0 or mi >= masks.size():
			mi = 0
		var dy: float = float(fr.get("dy", 0.0))
		_frames_up.append(_compose(bg_up, _render(masks[mi], pal_up, dy)))
		_frames_down.append(_compose(bg_down, _render(masks[mi], pal_down, dy)))
	_n = _frames_up.size()

func _compose(bg: Image, fish: Image) -> Image:
	if bg.get_width() != ICON_PX:
		return fish
	var out := bg.duplicate() as Image
	out.blend_rect(fish, Rect2i(0, 0, ICON_PX, ICON_PX), Vector2i.ZERO)
	return out


func _render(mask_grid: Array, palette: Dictionary, dy: float) -> Image:
	var img := Image.create_empty(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cell: int = int(float(ICON_PX) / float(_cols))
	if cell < 1:
		cell = 1
	var grid_h: int = _rows * cell
	var y_base: int = int(float(ICON_PX - grid_h) / 2.0) + int(round(dy * cell))
	var x_base: int = int(float(ICON_PX - _cols * cell) / 2.0)
	for r in _rows:
		if r >= mask_grid.size():
			break
		var row: Array = mask_grid[r]
		for c in _cols:
			if c >= row.size():
				break
			var code: int = int(row[c])
			if code == 0:
				continue
			var col := Color(str(palette.get(str(code), "#ffffff")))
			var px: int = x_base + c * cell
			var py: int = y_base + r * cell
			if px < 0 or py < 0 or px + cell > ICON_PX or py + cell > ICON_PX:
				continue
			img.fill_rect(Rect2i(px, py, cell, cell), col)
	return img


func _make_bg(bgspec: Dictionary, is_up: bool) -> Image:
	if bgspec.is_empty():
		return Image.new()
	var img := Image.create_empty(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	var tile: Dictionary = bgspec.get("tile", {})
	var td: Dictionary = tile.get("up" if is_up else "down", {})
	var fills: Array = td.get("fill", ["#16314f", "#0a1729"])
	var c0 := Color(str(fills[0]))
	var c1 := Color(str(fills[fills.size() - 1]))
	_fill_gradient(img, c0, c1, bool(td.get("radial", true)))
	var grid: Dictionary = bgspec.get("grid", {})
	if not grid.is_empty():
		_draw_grid(img, grid)
	var chart: Dictionary = bgspec.get("chart", {})
	if not chart.is_empty():
		_draw_chart(img, chart, is_up)
	var ratio: float = float(tile.get("cornerRadiusRatio", 0.2237))
	_round_corners(img, int(round(ratio * float(ICON_PX))))
	return img

func _fill_gradient(img: Image, c0: Color, c1: Color, radial: bool) -> void:
	var cx := float(ICON_PX) * 0.5
	var cy := float(ICON_PX) * 0.5
	var maxd := sqrt(cx * cx + cy * cy)
	for y in ICON_PX:
		for x in ICON_PX:
			var t: float
			if radial:
				var dx := float(x) + 0.5 - cx
				var dy := float(y) + 0.5 - cy
				t = clampf(sqrt(dx * dx + dy * dy) / maxd, 0.0, 1.0)
			else:
				t = float(y) / float(ICON_PX - 1)
			img.set_pixel(x, y, c0.lerp(c1, t))

func _draw_grid(img: Image, grid: Dictionary) -> void:
	var div: int = int(grid.get("divisions", 12))
	if div <= 0:
		return
	var gc := Color(str(grid.get("color", "#78c8ff")))
	var op := float(grid.get("opacity", 0.06))
	var step := float(ICON_PX) / float(div)
	for i in range(1, div):
		var p := int(round(float(i) * step))
		for a in ICON_PX:
			_blend_px(img, p, a, gc, op)
			_blend_px(img, a, p, gc, op)

func _draw_chart(img: Image, chart: Dictionary, is_up: bool) -> void:
	var vb: Array = chart.get("viewBox", [332, 300])
	var sx := float(ICON_PX) / float(vb[0])
	var sy := float(ICON_PX) / float(vb[1])
	var d: Dictionary = chart.get("up" if is_up else "down", {})
	var raw: Array = d.get("points", [])
	if raw.size() < 2:
		return
	var col := Color(str(d.get("color", "#22e08d")))
	var area_op := float(d.get("areaOpacity", 0.3))
	var pts: Array = []
	for p in raw:
		pts.append(Vector2(float(p[0]) * sx, float(p[1]) * sy))
	var x_start: int = maxi(0, int(floor(pts[0].x)))
	var x_end: int = mini(ICON_PX, int(ceil(pts[pts.size() - 1].x)))
	for x in range(x_start, x_end):
		var ly := _line_y_at(pts, float(x))
		for y in range(int(round(ly)), ICON_PX):
			_blend_px(img, x, y, col, area_op)
	var th: int = maxi(2, int(round(float(chart.get("strokeWidth", 3.5)) * sy)))
	for i in range(pts.size() - 1):
		_draw_seg(img,
			Vector2i(int(round(pts[i].x)), int(round(pts[i].y))),
			Vector2i(int(round(pts[i + 1].x)), int(round(pts[i + 1].y))), col, th)

func _line_y_at(pts: Array, x: float) -> float:
	if x <= pts[0].x:
		return pts[0].y
	for i in range(pts.size() - 1):
		if x >= pts[i].x and x <= pts[i + 1].x:
			var span: float = maxf(0.0001, pts[i + 1].x - pts[i].x)
			return lerpf(pts[i].y, pts[i + 1].y, (x - pts[i].x) / span)
	return pts[pts.size() - 1].y

func _draw_seg(img: Image, a: Vector2i, b: Vector2i, col: Color, th: int) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0:
		steps = 1
	for i in range(steps + 1):
		var tt := float(i) / float(steps)
		var x := int(round(lerpf(float(a.x), float(b.x), tt)))
		var y := int(round(lerpf(float(a.y), float(b.y), tt)))
		_dot(img, x, y, col, th)

func _dot(img: Image, x: int, y: int, col: Color, th: int) -> void:
	var h: int = int(th / 2.0)
	for dy in range(-h, th - h):
		for dx in range(-h, th - h):
			var px := x + dx
			var py := y + dy
			if px >= 0 and px < ICON_PX and py >= 0 and py < ICON_PX:
				img.set_pixel(px, py, col)

func _blend_px(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or x >= ICON_PX or y < 0 or y >= ICON_PX:
		return
	img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, a))

func _round_corners(img: Image, r: int) -> void:
	if r <= 0:
		return
	var corners := [
		Vector4i(r, r, 0, 0),
		Vector4i(ICON_PX - 1 - r, r, ICON_PX - r, 0),
		Vector4i(r, ICON_PX - 1 - r, 0, ICON_PX - r),
		Vector4i(ICON_PX - 1 - r, ICON_PX - 1 - r, ICON_PX - r, ICON_PX - r),
	]
	for cn in corners:
		for y in range(cn.w, cn.w + r):
			for x in range(cn.z, cn.z + r):
				var dx := float(x - cn.x)
				var dy := float(y - cn.y)
				if dx * dx + dy * dy > float(r * r):
					img.set_pixel(x, y, Color(0, 0, 0, 0))


func _process(delta: float) -> void:
	if not _active or _n == 0:
		return
	_accum += delta
	var spf := 1.0 / _fps
	var advanced := false
	while _accum >= spf:
		_accum -= spf
		_idx = (_idx + 1) % _n
		advanced = true
	if advanced:
		_apply_current()

func _apply_current() -> void:
	var arr: Array = _frames_up if _is_up else _frames_down
	if arr.is_empty():
		return
	if _idx < 0 or _idx >= arr.size():
		_idx = 0
	DisplayServer.set_icon(arr[_idx])


func _resolve_key() -> String:
	if IdleSystem == null:
		return ""
	var entries: Array = IdleSystem.get_all_watchlist_entries()
	if entries.is_empty():
		return ""
	var e: Dictionary = entries[0]
	return str(e.get("market", "")) + ":" + str(e.get("symbol", ""))

func _recompute_direction() -> void:
	var up := true
	var key := _resolve_key()
	if key != "" and DataReader != null:
		var t: Dictionary = DataReader.get_ticker(key)
		if not t.is_empty():
			up = float(t.get("change_pct", 0.0)) >= 0.0
	_is_up = up

func _refresh_tracked() -> void:
	_recompute_direction()
	if not _active:
		return
	set_process(true)
	_accum = 0.0
