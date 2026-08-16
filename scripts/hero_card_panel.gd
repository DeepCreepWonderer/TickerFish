extends RefCounted
const UITheme := preload("res://scripts/ui_theme.gd")
## 大卡模式渲染器:横向翻页时钟板,每卡装各自的一组标的(≤5),split-flap 轮播,可拖拽重排。

const DEFAULT_INTERVAL := 60.0

const FLAT_THRESHOLD := 0.05

const GRID_PAD := 22.0
const PANEL_GAP := 16.0
const CORNER := 16.0
const PANEL_PAD := 10.0
const ANIM_DUR := 0.5
const SPARK_MIN_W := 40.0
const SPARK_MAX_PTS := 80

const FONT_SYMBOL := 20
const FONT_PRICE := 29
const FONT_CHANGE := 13
const FONT_TITLE := 13
const TITLE_H := 26.0

const COLOR_SEAM := Color(0.0, 0.0, 0.0, 0.3)
const COLOR_TITLE := Color(0.541, 0.604, 0.596, 0.95)
const COLOR_SYMBOL := Color(0.85, 0.89, 0.88, 0.98)
const COLOR_PRICE := Color(0.914, 0.929, 0.922, 1.0)
const COLOR_UP := Color(0.275, 0.788, 0.541, 1.0)
const COLOR_DOWN := Color(0.941, 0.439, 0.431, 1.0)
const COLOR_FLAT := Color(0.60, 0.66, 0.65, 0.85)
const COLOR_EMPTY_HINT := Color(0.541, 0.604, 0.596, 0.7)

var _mono: Font = null

func _get_mono() -> Font:
	if _mono == null:
		if ResourceLoader.exists("res://JetBrainsMono.ttf"):
			_mono = load("res://JetBrainsMono.ttf")
	return _mono

var _pc: int = 1
var _pc_prev: int = 0
var _groups: Array = []
var _p_accum: Array = []
var _p_anim: Array = []
var _p_animating: Array = []
var _p_cycle: Array = []
var _p_x: Array = []
var _pos_init: bool = false
var _settling: bool = false
var _last_ms: int = 0
var _drag_src: int = -1
var _drag_x: float = 0.0
var _grid_x: float = 0.0
var _panel_top: float = 0.0
var _panel_w: float = 0.0
var _panel_h: float = 0.0
var _last_rect: Rect2 = Rect2()


func set_drag(src: int, x: float) -> void:
	_drag_src = src
	_drag_x = x

func clear_drag() -> void:
	_drag_src = -1

func reorder_state(from_idx: int, to_idx: int) -> void:
	if from_idx < 0 or from_idx >= _pc:
		return
	to_idx = clampi(to_idx, 0, _pc - 1)
	if to_idx == from_idx:
		return
	_move_arr(_p_accum, from_idx, to_idx)
	_move_arr(_p_anim, from_idx, to_idx)
	_move_arr(_p_animating, from_idx, to_idx)
	_move_arr(_p_cycle, from_idx, to_idx)
	_move_arr(_p_x, from_idx, to_idx)

func _move_arr(a: Array, from_idx: int, to_idx: int) -> void:
	if from_idx >= a.size():
		return
	var v = a[from_idx]
	a.remove_at(from_idx)
	a.insert(to_idx, v)


func _compute_groups() -> Array:
	if IdleSystem == null:
		return []
	var panels: Array = IdleSystem.get_hero_panels()
	var lookup := {}
	for it in IdleSystem.get_numeric_list():
		lookup[str(it.get("market", "stocks")) + ":" + str(it.get("symbol", ""))] = it
	var groups: Array = []
	for p in panels:
		var market: String = str(p.get("market", "stocks"))
		var items: Array = []
		for s in p.get("syms", []):
			var key: String = market + ":" + str(s)
			if lookup.has(key):
				items.append(lookup[key])
		groups.append({"market": market, "items": items, "title": str(p.get("title", "")), "interval": maxf(float(p.get("interval", DEFAULT_INTERVAL)), 1.0)})
	return groups


func _ensure_panel_state(pc: int) -> void:
	if _pc_prev == pc and _p_accum.size() == pc:
		return
	_p_accum.resize(pc)
	_p_anim.resize(pc)
	_p_animating.resize(pc)
	_p_cycle.resize(pc)
	_p_x.resize(pc)
	for c in range(pc):
		_p_accum[c] = 0.0
		_p_anim[c] = 0.0
		_p_animating[c] = false
		_p_cycle[c] = 0
	_pos_init = false
	_pc_prev = pc


func tick(delta: float) -> bool:
	var groups := _compute_groups()
	_pc = groups.size()
	if _pc == 0:
		return false
	_ensure_panel_state(_pc)
	var need_redraw := false
	for c in range(_pc):
		var gsize: int = (groups[c]["items"] as Array).size()
		if gsize <= 1:
			continue
		if _p_animating[c]:
			_p_anim[c] = float(_p_anim[c]) + delta / ANIM_DUR
			if _p_anim[c] >= 1.0:
				_p_anim[c] = 0.0
				_p_animating[c] = false
				_p_cycle[c] = int(_p_cycle[c]) + 1
			need_redraw = true
		else:
			_p_accum[c] = float(_p_accum[c]) + delta
			if _p_accum[c] >= float(groups[c].get("interval", DEFAULT_INTERVAL)):
				_p_accum[c] = 0.0
				_p_animating[c] = true
				_p_anim[c] = 0.0
				need_redraw = true
	return need_redraw or _drag_src >= 0 or _settling


func render(canvas: CanvasItem, font: Font, rect: Rect2) -> void:
	_last_rect = rect
	if font == null:
		return
	canvas.draw_rect(rect, UITheme.GROUP_BG, true)

	if IdleSystem != null and IdleSystem.get_numeric_list().is_empty():
		var hint: String = Lang.t("numeric.empty") if Lang != null else "No stocks yet"
		var ts: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		canvas.draw_string(font,
			Vector2(rect.position.x + (rect.size.x - ts.x) * 0.5, rect.position.y + rect.size.y * 0.5),
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_EMPTY_HINT)
		return

	var groups := _compute_groups()
	_groups = groups
	_pc = groups.size()
	if _pc == 0:
		return
	_ensure_panel_state(_pc)
	var avail_w: float = rect.size.x - GRID_PAD * 2.0
	var avail_h: float = rect.size.y - GRID_PAD * 2.0
	if avail_w < 20.0 or avail_h < 20.0:
		return
	_panel_w = (avail_w - float(_pc - 1) * PANEL_GAP) / float(_pc)
	_panel_h = avail_h
	_grid_x = rect.position.x + GRID_PAD
	_panel_top = rect.position.y + GRID_PAD

	var targets := _target_positions()
	var now: int = Time.get_ticks_msec()
	var dt: float = clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1) if _last_ms > 0 else 0.0
	_last_ms = now
	if _p_x.size() != _pc:
		_p_x.resize(_pc)
		_pos_init = false
	var k: float = clampf(dt * 16.0, 0.0, 1.0)
	_settling = false
	for c in range(_pc):
		if not _pos_init:
			_p_x[c] = targets[c]
		else:
			_p_x[c] = lerpf(float(_p_x[c]), float(targets[c]), k)
			if absf(float(_p_x[c]) - float(targets[c])) > 0.5:
				_settling = true
	_pos_init = true

	for c in range(_pc):
		if c == _drag_src:
			continue
		_draw_group_card(canvas, font, Rect2(float(_p_x[c]), _panel_top, _panel_w, _panel_h), c)

	if _drag_src >= 0 and _drag_src < _pc:
		var gslot: int = slot_at_x(_drag_x)
		if gslot >= 0:
			var gx: float = _grid_x + float(gslot) * (_panel_w + PANEL_GAP)
			_draw_round_rect(canvas, Rect2(gx, _panel_top, _panel_w, _panel_h), CORNER, Color(1.0, 1.0, 1.0, 0.05))
		var min_x: float = _grid_x - 10.0
		var max_x: float = _grid_x + float(_pc - 1) * (_panel_w + PANEL_GAP) + 10.0
		var fx: float = clampf(_drag_x - _panel_w * 0.5, min_x, max_x)
		var fcell := Rect2(fx, _panel_top - 8.0, _panel_w, _panel_h)
		_draw_round_rect(canvas, Rect2(fcell.position.x + 3.0, fcell.position.y + 7.0, _panel_w, _panel_h), CORNER, Color(0.0, 0.0, 0.0, 0.4))
		_draw_group_card(canvas, font, fcell, _drag_src)


func _target_positions() -> Array:
	var step: float = _panel_w + PANEL_GAP
	var tx: Array = []
	tx.resize(_pc)
	if _drag_src < 0 or _drag_src >= _pc:
		for c in range(_pc):
			tx[c] = _grid_x + float(c) * step
		return tx
	var target_slot: int = slot_at_x(_drag_x)
	var others: Array = []
	for i in range(_pc):
		if i != _drag_src:
			others.append(i)
	var oi: int = 0
	for slot in range(_pc):
		if slot == target_slot:
			continue
		tx[others[oi]] = _grid_x + float(slot) * step
		oi += 1
	tx[_drag_src] = _grid_x + float(target_slot) * step
	return tx


func _draw_group_card(canvas: CanvasItem, font: Font, cell: Rect2, gidx: int) -> void:
	if gidx < 0 or gidx >= _groups.size() or cell.size.x < 8.0 or cell.size.y < 8.0:
		return
	_draw_round_rect(canvas, cell, CORNER, UITheme.PANEL_CARD)
	var g: Dictionary = _groups[gidx]
	_draw_title(canvas, font, cell, str(g.get("title", "")), str(g["market"]))

	var content := Rect2(cell.position.x, cell.position.y + TITLE_H, cell.size.x, cell.size.y - TITLE_H)
	var grp: Array = g["items"]
	if grp.is_empty():
		canvas.draw_string(font,
			Vector2(content.position.x + PANEL_PAD, content.position.y + content.size.y * 0.5 + 6.0),
			"—", HORIZONTAL_ALIGNMENT_CENTER, content.size.x - PANEL_PAD * 2.0, FONT_PRICE, Color(COLOR_EMPTY_HINT, 0.5))
		return
	var gsize: int = grp.size()
	var cyc: int = int(_p_cycle[gidx]) if gidx < _p_cycle.size() else 0
	var cur_i: int = cyc % gsize

	var bar_col: Color = _item_accent(grp[cur_i])
	canvas.draw_rect(Rect2(cell.position.x + 4.0, cell.position.y + 8.0,
		3.0, cell.size.y - 16.0), Color(bar_col.r, bar_col.g, bar_col.b, 0.9), true)
	if gidx < _p_animating.size() and bool(_p_animating[gidx]) and gsize > 1:
		var anim: float = float(_p_anim[gidx])
		var show_i: int = cur_i
		if anim >= 0.5:
			show_i = (cyc + 1) % gsize
		var s: float = absf(1.0 - 2.0 * anim)
		var ccy: float = content.position.y + content.size.y * 0.5
		canvas.draw_set_transform(Vector2(0.0, ccy * (1.0 - s)), 0.0, Vector2(1.0, s))
		_draw_ticker(canvas, font, content, grp[show_i])
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_ticker(canvas, font, content, grp[cur_i])


func _draw_title(canvas: CanvasItem, _font: Font, cell: Rect2, title: String, market: String) -> void:
	var txt: String = title
	if txt == "":
		txt = Lang.t("about.market." + market) if Lang != null else market
	canvas.draw_string(UITheme.sans_bold(), Vector2(cell.position.x + PANEL_PAD + 8.0, cell.position.y + 17.0),
		txt, HORIZONTAL_ALIGNMENT_LEFT, cell.size.x - PANEL_PAD * 2.0 - 8.0, FONT_TITLE, COLOR_PRICE)


func _item_accent(item: Dictionary) -> Color:
	if DataReader != null:
		var d: Dictionary = DataReader.get_ticker("%s:%s" % [item.get("market", "stocks"), item.get("symbol", "")])
		if not d.is_empty():
			var cp = d.get("change_pct", null)
			if cp != null:
				return _color_for_change(float(cp))
	return COLOR_FLAT

func _draw_ticker(canvas: CanvasItem, font: Font, cell: Rect2, item: Dictionary) -> void:
	if cell.size.x < 8.0 or cell.size.y < 8.0:
		return
	var symbol: String = item.get("symbol", "")
	var nickname: String = str(item.get("nickname", ""))
	var market: String = item.get("market", "stocks")
	var key: String = "%s:%s" % [market, symbol]

	var price_text := "—"
	var price_val := 0.0
	var have_price := false
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
				price_val = float(price)
				have_price = true
				price_text = _format_price(price_val)
			if cp != null:
				change_pct = float(cp)
				have_pct = true
				change_text = _format_change_pct(change_pct)
			if pc != null:
				prev_close = float(pc)
	var accent: Color = _color_for_change(change_pct) if have_pct else COLOR_FLAT

	var num_font: Font = _get_mono()
	if num_font == null:
		num_font = font

	var lx: float = cell.position.x + PANEL_PAD + 8.0
	var rx: float = cell.position.x + cell.size.x - PANEL_PAD
	var top: float = cell.position.y

	var pill_left: float = rx
	if change_text != "":
		var cw: float = num_font.get_string_size(change_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE).x
		var pw: float = cw + 12.0
		pill_left = rx - pw
		canvas.draw_rect(Rect2(pill_left, top + 6.0, pw, 17.0),
			Color(accent.r, accent.g, accent.b, 0.14), true)
		canvas.draw_string(num_font, Vector2(pill_left + 6.0, top + 18.5),
			change_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE, accent)

	canvas.draw_string(num_font, Vector2(lx, top + 19.0),
		symbol, HORIZONTAL_ALIGNMENT_LEFT, maxf(pill_left - lx - 8.0, 40.0), FONT_SYMBOL, COLOR_PRICE)
	if nickname != "" and nickname != symbol:
		canvas.draw_string(font, Vector2(lx, top + 37.0),
			nickname, HORIZONTAL_ALIGNMENT_LEFT, rx - lx, 12, Color(COLOR_TITLE, 0.7))

	var price_color: Color = COLOR_PRICE if have_price else COLOR_FLAT
	canvas.draw_string(num_font, Vector2(lx, top + 72.0),
		price_text, HORIZONTAL_ALIGNMENT_LEFT, rx - lx, FONT_PRICE, price_color)

	if have_price and prev_close > 0.0:
		var today: String = Lang.t("hero.today") if Lang != null else "today"
		canvas.draw_string(num_font, Vector2(lx, top + 92.0),
			"%+.2f %s" % [price_val - prev_close, today], HORIZONTAL_ALIGNMENT_LEFT, rx - lx, FONT_CHANGE, accent)

	var sp_top: float = top + 100.0
	var sp_bot: float = cell.position.y + cell.size.y - PANEL_PAD
	if sp_bot - sp_top > 10.0 and (rx - lx) > SPARK_MIN_W and DataReader != null:
		_draw_spark(canvas, lx, sp_top, rx - lx, sp_bot - sp_top, DataReader.get_bars(key), accent, prev_close)


func panel_index_at(pos: Vector2) -> int:
	if _groups.is_empty() or _panel_w <= 0.0:
		return -1
	if pos.y < _panel_top or pos.y > _panel_top + _panel_h:
		return -1
	if pos.x < _grid_x:
		return -1
	var c: int = int((pos.x - _grid_x) / (_panel_w + PANEL_GAP))
	if c < 0 or c >= _groups.size():
		return -1
	if pos.x > _grid_x + float(c) * (_panel_w + PANEL_GAP) + _panel_w:
		return -1
	return c

func slot_at_x(x: float) -> int:
	if _panel_w <= 0.0 or _pc <= 0:
		return -1
	return clampi(int((x - _grid_x) / (_panel_w + PANEL_GAP)), 0, _pc - 1)

func _panel_item_at(pos: Vector2) -> Dictionary:
	if _groups.is_empty() or _panel_w <= 0.0:
		return {}
	if pos.y < _panel_top or pos.y > _panel_top + _panel_h:
		return {}
	var c: int = int((pos.x - _grid_x) / (_panel_w + PANEL_GAP))
	if c < 0 or c >= _groups.size():
		return {}
	var grp: Array = _groups[c]["items"]
	if grp.is_empty():
		return {}
	var cyc: int = int(_p_cycle[c]) if c < _p_cycle.size() else 0
	return grp[cyc % grp.size()]

func item_id_at(pos: Vector2) -> String:
	var it := _panel_item_at(pos)
	return str(it.get("id", "")) if not it.is_empty() else ""

func item_label_at(pos: Vector2) -> String:
	var it := _panel_item_at(pos)
	if it.is_empty():
		return ""
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
	var vtop: float = y + h * 0.30
	var vh: float = h * 0.64
	var pts := PackedVector2Array()
	for i in range(n):
		var px := x + float(i) / float(n - 1) * w
		var py := vtop + vh - (closes[i] - lo) / span * vh
		pts.append(Vector2(px, py))
	if prev_close > 0.0:
		var y_base := vtop + vh - (prev_close - lo) / span * vh
		var segs := _split_segments(pts, closes, prev_close, y_base)
		for s in segs:
			var a: Vector2 = s["a"]
			var b: Vector2 = s["b"]
			var sc: Color = s["col"]
			if absf(b.x - a.x) >= 0.5 and (absf(a.y - y_base) >= 0.5 or absf(b.y - y_base) >= 0.5):
				var fill := PackedVector2Array([a, b])
				if absf(b.y - y_base) >= 0.5:
					fill.append(Vector2(b.x, y_base))
				if absf(a.y - y_base) >= 0.5:
					fill.append(Vector2(a.x, y_base))
				if fill.size() >= 3:
					canvas.draw_colored_polygon(fill, Color(sc, 0.16))
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
		canvas.draw_colored_polygon(area, Color(col, 0.16))
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
