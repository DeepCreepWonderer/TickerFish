extends RefCounted
const UITheme := preload("res://scripts/ui_theme.gd")
## 横幅模式渲染器:顶部全宽一排卡片(符号+价+涨跌+sparkline)。

const FLAT_THRESHOLD := 0.05

const MAX_CARD_W := 240.0
const OUTER_PAD := 6.0
const CARD_GAP := 6.0
const CARD_PAD := 12.0
const CORNER := 7.0

const COLS_PER_ROW := 8
const ROW_H := 84.0
const MAX_ROWS := 7

const FONT_SYMBOL := 16
const FONT_PRICE := 19
const FONT_CHANGE := 13
const FONT_GROUP := 12
const GROUP_PAD := 6.0

const SPARK_FRAC := 0.42
const SPARK_MIN_W := 40.0
const SPARK_MAX_PTS := 80

const COLOR_SYMBOL := Color(0.85, 0.89, 0.88, 0.98)
const COLOR_PRICE := Color(0.914, 0.929, 0.922, 1.0)
const COLOR_UP := Color(0.275, 0.788, 0.541, 1.0)
const COLOR_DOWN := Color(0.941, 0.439, 0.431, 1.0)
const COLOR_FLAT := Color(0.60, 0.66, 0.65, 0.85)
const COLOR_EMPTY_HINT := Color(0.541, 0.604, 0.596, 0.7)

var _mono: Font = null

func _get_mono() -> Font:
	if _mono == null:
		_mono = UITheme.mono()
	return _mono

var _last_rect: Rect2 = Rect2()
var _cols: int = 1
var _rows: int = 1
var _cell_w: float = 0.0
var _cell_h: float = 0.0
var _grid_x: float = 0.0
var _grid_y: float = 0.0
var _n: int = 0

var _drag_src: int = -1
var _drag_pos: Vector2 = Vector2.ZERO
var _drag_slot: int = 0
var _drag_group: String = ""
var _label_w: float = 0.0
var _p_pos: Array = []
var _pos_init: bool = false
var _settling: bool = false
var _last_ms: int = 0

# ---- grouping ----

static func group_of(item) -> String:
	return str(item.get("group", "")) if item is Dictionary else ""

static func rows_for(list: Array) -> int:
	var rows := 0
	var i := 0
	while i < list.size():
		var g: String = group_of(list[i])
		var j := i
		while j < list.size() and group_of(list[j]) == g:
			j += 1
		rows += int(ceil(float(j - i) / float(COLS_PER_ROW)))
		i = j
	return maxi(rows, 1)

func _group_at(list: Array, i: int) -> String:
	if i == _drag_src and _drag_src >= 0:
		return _drag_group
	return group_of(list[i])

func _rows_from(order: Array, list: Array) -> Array:
	var rows: Array = []
	var i := 0
	while i < order.size():
		var g: String = _group_at(list, int(order[i]))
		var seg: Array = []
		while i < order.size() and _group_at(list, int(order[i])) == g:
			seg.append(int(order[i]))
			i += 1
		var k := 0
		while k < seg.size():
			rows.append({
				"items": seg.slice(k, mini(k + COLS_PER_ROW, seg.size())),
				"group": g,
				"first": k == 0,
			})
			k += COLS_PER_ROW
	return rows

# ---- drag ----

func set_drag(src: int, pos: Vector2) -> void:
	_drag_src = src
	_drag_pos = pos

func clear_drag() -> void:
	_drag_src = -1
	_drag_group = ""

func drag_slot() -> int:
	return _drag_slot

func drag_group() -> String:
	return _drag_group

func tick(_delta: float) -> bool:
	return _drag_src >= 0 or _settling

func _base_order(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		if i != _drag_src:
			out.append(i)
	return out

func drop_target(list: Array, pos: Vector2) -> Dictionary:
	var held: Dictionary = {"slot": 0, "group": ""}
	if _drag_src >= 0 and _drag_src < list.size():
		held["group"] = group_of(list[_drag_src])
	var base := _base_order(list.size())
	if base.is_empty() or _cell_w <= 0.0 or _cell_h <= 0.0:
		return held
	var keep := _drag_src
	_drag_src = -1
	var rows := _rows_from(base, list)
	_drag_src = keep
	if rows.is_empty():
		return held
	var r := clampi(int((pos.y - _grid_y) / _cell_h), 0, rows.size() - 1)
	var row: Array = (rows[r] as Dictionary)["items"]
	var c := clampi(int((pos.x - _grid_x - _label_w) / _cell_w), 0, row.size())
	var idx := 0
	for k in range(r):
		idx += ((rows[k] as Dictionary)["items"] as Array).size()
	return {
		"slot": clampi(idx + c, 0, base.size()),
		"group": str((rows[r] as Dictionary)["group"]),
	}

func _compute_label_w(list: Array, font: Font) -> float:
	var label_font: Font = _get_mono()
	if label_font == null:
		label_font = font
	var w := 0.0
	for it in list:
		var g: String = group_of(it)
		if g == "":
			continue
		w = maxf(w, label_font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_GROUP).x)
	if w <= 0.0:
		return 0.0
	return clampf(w + GROUP_PAD * 2.0, 34.0, 110.0)

func _layout_metrics(rows: Array, rect: Rect2) -> void:
	var max_len := 1
	for r in rows:
		max_len = maxi(max_len, ((r as Dictionary)["items"] as Array).size())
	_cols = clampi(max_len, 1, COLS_PER_ROW)
	_rows = maxi(rows.size(), 1)
	_grid_x = rect.position.x + OUTER_PAD
	_grid_y = rect.position.y + OUTER_PAD
	_cell_w = minf((rect.size.x - OUTER_PAD * 2.0 - _label_w) / float(_cols), MAX_CARD_W)
	_cell_h = (rect.size.y - OUTER_PAD * 2.0) / float(_rows)

func render(canvas: CanvasItem, font: Font, rect: Rect2) -> void:
	_last_rect = rect
	if font == null:
		return
	canvas.draw_rect(rect, UITheme.GROUP_BG, true)

	var list: Array = IdleSystem.get_numeric_list() if IdleSystem != null else []
	_n = list.size()
	if _n == 0:
		_pos_init = false
		var hint: String = Lang.t("numeric.empty") if Lang != null else "No stocks yet"
		var ts: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		canvas.draw_string(font,
			Vector2(rect.position.x + (rect.size.x - ts.x) * 0.5, rect.position.y + rect.size.y * 0.5 + 5.0),
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_EMPTY_HINT)
		return

	if _drag_src >= _n:
		_drag_src = -1
	_label_w = _compute_label_w(list, font)
	if _drag_src >= 0:
		var drop: Dictionary = drop_target(list, _drag_pos)
		_drag_slot = int(drop["slot"])
		_drag_group = str(drop["group"])

	var order := _base_order(_n)
	if _drag_src >= 0:
		order.insert(clampi(_drag_slot, 0, order.size()), _drag_src)

	var rows := _rows_from(order, list)
	_layout_metrics(rows, rect)

	var targets: Array = []
	targets.resize(_n)
	for r in range(rows.size()):
		var row: Array = (rows[r] as Dictionary)["items"]
		for c in range(row.size()):
			targets[int(row[c])] = Vector2(
				_grid_x + _label_w + float(c) * _cell_w, _grid_y + float(r) * _cell_h)
	_draw_group_labels(canvas, font, rows)

	var now: int = Time.get_ticks_msec()
	var dt: float = clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1) if _last_ms > 0 else 0.0
	_last_ms = now
	if _p_pos.size() != _n:
		_p_pos.resize(_n)
		_pos_init = false
	var k: float = clampf(dt * 16.0, 0.0, 1.0)
	_settling = false
	for i in range(_n):
		if not _pos_init:
			_p_pos[i] = targets[i]
		else:
			_p_pos[i] = (_p_pos[i] as Vector2).lerp(targets[i], k)
			if ((_p_pos[i] as Vector2) - (targets[i] as Vector2)).length() > 0.5:
				_settling = true
	_pos_init = true

	for i in range(_n):
		if i == _drag_src:
			continue
		_draw_card(canvas, font, Rect2(_p_pos[i], Vector2(_cell_w, _cell_h)), list[i])

	if _drag_src >= 0 and _drag_src < _n:
		var inner_off := Vector2(CARD_GAP * 0.5, CARD_GAP * 0.5)
		var inner_size := Vector2(_cell_w - CARD_GAP, _cell_h - CARD_GAP)
		_draw_round_rect(canvas, Rect2((targets[_drag_src] as Vector2) + inner_off, inner_size),
			CORNER, Color(1.0, 1.0, 1.0, 0.05))
		var fx: float = clampf(_drag_pos.x - _cell_w * 0.5,
			_grid_x - 10.0, _grid_x + float(_cols) * _cell_w - _cell_w + 10.0)
		var fy: float = clampf(_drag_pos.y - _cell_h * 0.5,
			_grid_y - 8.0, _grid_y + float(_rows) * _cell_h - _cell_h + 8.0)
		var fcell := Rect2(Vector2(fx, fy), Vector2(_cell_w, _cell_h))
		_draw_round_rect(canvas, Rect2(fcell.position + inner_off + Vector2(3.0, 7.0), inner_size),
			CORNER, Color(0.0, 0.0, 0.0, 0.4))
		_draw_card(canvas, font, fcell, list[_drag_src])

func _draw_card(canvas: CanvasItem, font: Font, cell: Rect2, item: Dictionary) -> void:
	var inner := Rect2(cell.position + Vector2(CARD_GAP * 0.5, CARD_GAP * 0.5),
		cell.size - Vector2(CARD_GAP, CARD_GAP))
	if inner.size.x <= 6.0 or inner.size.y <= 6.0:
		return
	_draw_round_rect(canvas, inner, CORNER, UITheme.PANEL_CARD)

	var symbol: String = item.get("symbol", "")
	var market: String = item.get("market", "stocks")
	var key: String = "%s:%s" % [market, symbol]

	var price_text := "—"
	var change_text := ""
	var change_pct := 0.0
	var have_pct := false
	var prev_close := 0.0
	if DataReader != null:
		var data: Dictionary = DataReader.get_ticker(key)
		if not data.is_empty():
			var price = data.get("price", null)
			var cp = data.get("change_pct", null)
			var pc = data.get("previous_close", null)
			if price != null:
				price_text = _format_price(float(price))
			if cp != null:
				change_pct = float(cp)
				have_pct = true
				change_text = _format_change_pct(change_pct)
			if pc != null:
				prev_close = float(pc)
	var accent: Color = _color_for_change(change_pct) if have_pct else COLOR_FLAT
	canvas.draw_rect(Rect2(inner.position.x + 3.0, inner.position.y + 6.0,
		3.0, inner.size.y - 12.0), Color(accent.r, accent.g, accent.b, 0.85), true)

	var spark_w: float = clampf(inner.size.x * SPARK_FRAC, 0.0, inner.size.x - 60.0)
	if spark_w < SPARK_MIN_W:
		spark_w = 0.0
	var text_w: float = inner.size.x - spark_w - CARD_PAD * 2.0
	var tx := inner.position.x + CARD_PAD
	var cy0 := inner.position.y
	var mid := inner.position.y + inner.size.y * 0.5

	var num_font: Font = _get_mono()
	if num_font == null:
		num_font = font
	canvas.draw_string(num_font, Vector2(tx, mid - 6.0),
		symbol, HORIZONTAL_ALIGNMENT_LEFT, text_w, FONT_SYMBOL, COLOR_PRICE)
	if change_text != "":
		var cs: Vector2 = num_font.get_string_size(change_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE)
		var chx: float = tx + text_w - 6.0 - cs.x
		if chx > tx + 4.0:
			canvas.draw_rect(Rect2(chx - 6.0, cy0 + 6.0, cs.x + 12.0, 15.0),
				Color(accent.r, accent.g, accent.b, 0.14), true)
			canvas.draw_string(num_font, Vector2(chx, cy0 + 18.0),
				change_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE, accent)
	var price_color: Color = COLOR_PRICE if price_text != "—" else COLOR_FLAT
	canvas.draw_string(num_font, Vector2(tx, mid + FONT_PRICE),
		price_text, HORIZONTAL_ALIGNMENT_LEFT, text_w, FONT_PRICE, price_color)

	if spark_w > 0.0 and DataReader != null:
		var sx := inner.position.x + inner.size.x - spark_w - CARD_PAD * 0.5
		var sy := inner.position.y + CARD_PAD * 0.5
		var sh := inner.size.y - CARD_PAD
		if sh > 6.0:
			_draw_spark(canvas, sx, sy, spark_w, sh, DataReader.get_bars(key), accent, prev_close)


func _draw_group_labels(canvas: CanvasItem, font: Font, rows: Array) -> void:
	if _label_w <= 0.0:
		return
	var label_font: Font = _get_mono()
	if label_font == null:
		label_font = font
	for r in range(rows.size()):
		var row: Dictionary = rows[r]
		var g: String = str(row["group"])
		if g == "":
			continue
		var y := _grid_y + float(r) * _cell_h
		canvas.draw_rect(Rect2(_grid_x + _label_w - 3.0, y + CARD_GAP * 0.5,
			2.0, _cell_h - CARD_GAP), Color(COLOR_SYMBOL, 0.25), true)
		if not bool(row["first"]):
			continue
		var ts: Vector2 = label_font.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_GROUP)
		canvas.draw_string(label_font, Vector2(_grid_x + GROUP_PAD, y + _cell_h * 0.5 + ts.y * 0.28),
			g, HORIZONTAL_ALIGNMENT_LEFT, _label_w - GROUP_PAD * 2.0, FONT_GROUP, COLOR_PRICE)

func index_at(pos: Vector2) -> int:
	return _index_at(pos)

func _index_at(pos: Vector2) -> int:
	if _n == 0 or _cell_w <= 0.0 or _cell_h <= 0.0 or IdleSystem == null:
		return -1
	if pos.x < _grid_x or pos.y < _grid_y:
		return -1
	var list: Array = IdleSystem.get_numeric_list()
	if list.size() != _n:
		return -1
	var order: Array = []
	for i in range(_n):
		order.append(i)
	var rows := _rows_from(order, list)
	var r := int((pos.y - _grid_y) / _cell_h)
	if r < 0 or r >= rows.size():
		return -1
	var row: Array = (rows[r] as Dictionary)["items"]
	var c := int((pos.x - _grid_x - _label_w) / _cell_w)
	if c < 0 or c >= row.size():
		return -1
	return int(row[c])

func item_id_at(pos: Vector2) -> String:
	var i := _index_at(pos)
	if i < 0 or IdleSystem == null:
		return ""
	return IdleSystem.get_numeric_list()[i].get("id", "")

func item_label_at(pos: Vector2) -> String:
	var i := _index_at(pos)
	if i < 0 or IdleSystem == null:
		return ""
	var it: Dictionary = IdleSystem.get_numeric_list()[i]
	var nick: String = it.get("nickname", "")
	return nick if nick != "" else it.get("symbol", "")


func _draw_round_rect(canvas: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	canvas.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col, true)
	canvas.draw_rect(Rect2(r.position.x, r.position.y + rad, r.size.x, r.size.y - rad * 2.0), col, true)
	canvas.draw_circle(Vector2(r.position.x + rad, r.position.y + rad), rad, col)
	canvas.draw_circle(Vector2(r.position.x + r.size.x - rad, r.position.y + rad), rad, col)
	canvas.draw_circle(Vector2(r.position.x + rad, r.position.y + r.size.y - rad), rad, col)
	canvas.draw_circle(Vector2(r.position.x + r.size.x - rad, r.position.y + r.size.y - rad), rad, col)

func _draw_spark(canvas: CanvasItem, x: float, y: float, w: float, h: float,
		bars: Array, col: Color, prev_close: float) -> void:
	if w <= 2.0 or h <= 2.0:
		return
	var closes: Array[float] = []
	for b in bars:
		closes.append(float(b.get("c", 0.0)))
	if closes.size() < 2:
		var ym := y + h * 0.5
		canvas.draw_line(Vector2(x, ym), Vector2(x + w, ym), Color(col, 0.5), 1.0, true)
		return
	if closes.size() > SPARK_MAX_PTS:
		var ds: Array[float] = []
		var step: float = float(closes.size() - 1) / float(SPARK_MAX_PTS - 1)
		for i in range(SPARK_MAX_PTS):
			ds.append(closes[int(round(float(i) * step))])
		closes = ds
	var lo := INF
	var hi := -INF
	for c in closes:
		lo = minf(lo, c)
		hi = maxf(hi, c)
	if prev_close > 0.0:
		lo = minf(lo, prev_close)
		hi = maxf(hi, prev_close)
	var span: float = maxf(hi - lo, 0.0001)
	var n := closes.size()
	var pts := PackedVector2Array()
	for i in range(n):
		var px := x + float(i) / float(n - 1) * w
		var py := y + h - (closes[i] - lo) / span * h
		pts.append(Vector2(px, py))
	if prev_close > 0.0:
		var y_base := y + h - (prev_close - lo) / span * h
		var segs := _split_segments(pts, closes, prev_close, y_base)
		for s in segs:
			var a: Vector2 = s["a"]
			var b: Vector2 = s["b"]
			var sc: Color = s["col"]
			if absf(b.x - a.x) >= 0.5 and (absf(a.y - y_base) >= 0.5 or absf(b.y - y_base) >= 0.5):
				var fill := PackedVector2Array([a, b, Vector2(b.x, y_base), Vector2(a.x, y_base)])
				canvas.draw_colored_polygon(fill, Color(sc, 0.15))
		_draw_dashed_hline(canvas, x, x + w, y_base, Color(0.6, 0.65, 0.72, 0.5))
		for s in segs:
			var la: Vector2 = s["a"]
			var lb: Vector2 = s["b"]
			var lc: Color = s["col"]
			canvas.draw_line(la, lb, lc, 1.6, true)
	else:
		var area := PackedVector2Array(pts)
		area.append(Vector2(x + w, y + h))
		area.append(Vector2(x, y + h))
		canvas.draw_colored_polygon(area, Color(col, 0.15))
		canvas.draw_polyline(pts, col, 1.6, true)

func _draw_dashed_hline(canvas: CanvasItem, x0: float, x1: float, y: float, col: Color) -> void:
	var dash := 4.0
	var gap := 3.0
	var cx := x0
	while cx < x1:
		var seg_end := minf(cx + dash, x1)
		canvas.draw_line(Vector2(cx, y), Vector2(seg_end, y), col, 1.0, true)
		cx = seg_end + gap

func _split_segments(pts: PackedVector2Array, closes: Array[float], base_val: float, y_base: float) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var above0: bool = closes[i] >= base_val
		var above1: bool = closes[i + 1] >= base_val
		if above0 == above1:
			out.append({"a": p0, "b": p1, "col": COLOR_UP if above0 else COLOR_DOWN})
		else:
			var denom: float = closes[i + 1] - closes[i]
			var t: float = 0.5 if absf(denom) < 0.000001 else (base_val - closes[i]) / denom
			t = clampf(t, 0.0, 1.0)
			var mid := Vector2(lerpf(p0.x, p1.x, t), y_base)
			out.append({"a": p0, "b": mid, "col": COLOR_UP if above0 else COLOR_DOWN})
			out.append({"a": mid, "b": p1, "col": COLOR_UP if above1 else COLOR_DOWN})
	return out


func _format_price(p: float) -> String:
	if absf(p) < 1.0:
		return "%.4f" % p
	return _add_thousands_sep("%.2f" % p)

func _format_change_pct(pct: float) -> String:
	if absf(pct) < FLAT_THRESHOLD:
		return "0.00%"
	if pct > 0:
		return "+%.2f%%" % pct
	return "%.2f%%" % pct

func _color_for_change(pct: float) -> Color:
	if absf(pct) < FLAT_THRESHOLD:
		return COLOR_FLAT
	if pct > 0:
		return COLOR_UP
	return COLOR_DOWN

func _add_thousands_sep(s: String) -> String:
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var dot := s.find(".")
	var int_part := s if dot < 0 else s.substr(0, dot)
	var frac := "" if dot < 0 else s.substr(dot)
	var out := ""
	var cnt := 0
	for i in range(int_part.length() - 1, -1, -1):
		out = int_part[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if neg else "") + out + frac
