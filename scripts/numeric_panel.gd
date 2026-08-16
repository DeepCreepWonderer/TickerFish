extends RefCounted
const UITheme := preload("res://scripts/ui_theme.gd")
## 数字列表模式渲染器:每行 符号+价+涨跌+日内蜡烛。

const CARD_HEIGHT := 58
const CARD_GAP := 3
const CARD_RADIUS := 12
const CARD_PAD_LEFT := 14
const CARD_PAD_RIGHT := 12
const SYM_ZONE := 66

const FONT_SYMBOL := 16
const FONT_PRICE := 17
const FONT_NICK := 11
const FONT_CHANGE := 11
const FONT_NO_DATA := 13

const LIST_TOP := 6
const LIST_BOTTOM_RESERVE := 36

const REC_STRIP_H := 18.0
const COLOR_REC := Color(0.96, 0.72, 0.26, 0.95)

const BAR_BODY_W := 4
const BAR_GAP := 3
const CANDLE_GAP := 10
const CANDLE_TOP_PAD := 13
const CANDLE_BOT_PAD := 13

const COLOR_SEP := Color(1.0, 1.0, 1.0, 0.07)
const COLOR_SYMBOL := Color(0.85, 0.89, 0.88, 0.95)
const COLOR_PRICE := Color(0.914, 0.929, 0.922, 1.0)
const COLOR_NICK := Color(0.541, 0.604, 0.596, 0.85)
const COLOR_UP := Color(0.275, 0.788, 0.541, 1.0)
const COLOR_DOWN := Color(0.941, 0.439, 0.431, 1.0)
const COLOR_FLAT := Color(0.60, 0.66, 0.65, 0.85)
const COLOR_EMPTY_HINT := Color(0.541, 0.604, 0.596, 0.8)
const COLOR_SCROLL_TRACK := Color(1.0, 1.0, 1.0, 0.05)
const COLOR_SCROLL_THUMB := Color(0.906, 0.722, 0.361, 0.4)

const FLAT_THRESHOLD := 0.05

const HEADER_H := 24
const FONT_HEADER := 14
const COLOR_HEADER := Color(1.0, 0.96, 0.86, 1.0)
const COLOR_HEADER_BG := Color(0.906, 0.722, 0.361, 0.26)
const COLOR_HEADER_COUNT := Color(1.0, 0.96, 0.86, 0.8)
const COLOR_HEADER_BAR := Color(0.98, 0.80, 0.42, 1.0)
const MARKET_ORDER := ["stocks", "crypto"]
const SCROLL_LERP := 16.0

var _scroll_offset: float = 0.0
var _scroll_target: float = 0.0
var _mono: Font = null
var _card_sb: StyleBoxFlat = null

func _get_mono() -> Font:
	if _mono == null:
		if ResourceLoader.exists("res://JetBrainsMono.ttf"):
			_mono = load("res://JetBrainsMono.ttf")
	return _mono

func _card_style() -> StyleBoxFlat:
	if _card_sb == null:
		_card_sb = StyleBoxFlat.new()
		_card_sb.set_corner_radius_all(CARD_RADIUS)
	_card_sb.bg_color = UITheme.PANEL_CARD
	return _card_sb

var _rec_strip_h: float = 0.0

var _last_rect: Rect2 = Rect2()
var _layout: Array = []
var _content_height: float = 0.0


func render(canvas: CanvasItem, font: Font, rect: Rect2) -> void:
	_last_rect = rect
	if font == null:
		return

	var origin: Vector2 = rect.position
	var w: float = rect.size.x

	canvas.draw_rect(rect, UITheme.GROUP_BG, true)

	_rec_strip_h = REC_STRIP_H if _recording() else 0.0
	if _rec_strip_h > 0.0:
		_draw_rec_strip(canvas, font, rect)

	var list: Array = IdleSystem.get_numeric_list() if IdleSystem != null else []
	_layout = _build_layout(list)
	_content_height = 0.0
	for e in _layout:
		_content_height = maxf(_content_height, float(e["cy"]) + (HEADER_H if e["type"] == "header" else CARD_HEIGHT))
	_clamp_scroll(rect)

	if list.is_empty():
		var hint: String = Lang.t("numeric.empty") if Lang != null else "No stocks yet"
		var lines: PackedStringArray = hint.split("\n")
		var total_h: float = lines.size() * 18.0
		var start_y: float = origin.y + (rect.size.y - total_h) * 0.5
		for li in range(lines.size()):
			var ln: String = lines[li]
			var ts: Vector2 = font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			canvas.draw_string(font,
				Vector2(origin.x + (w - ts.x) * 0.5, start_y + li * 18 + 12),
				ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_EMPTY_HINT)
		return

	var viewport_bottom: float = origin.y + rect.size.y - LIST_BOTTOM_RESERVE
	var list_top: float = origin.y + LIST_TOP + _rec_strip_h

	for e in _layout:
		var is_header: bool = e["type"] == "header"
		var eh: float = HEADER_H if is_header else CARD_HEIGHT
		var y_top: float = list_top + float(e["cy"]) - _scroll_offset
		if y_top + eh > viewport_bottom + 0.5:
			continue
		if is_header:
			if y_top <= list_top + 0.5:
				continue
			_draw_section_header(canvas, font, str(e["market"]), int(e["count"]), origin.x, w, y_top, false)
		else:
			if y_top < list_top - 0.5:
				continue
			_draw_row(canvas, font, e["item"], y_top, origin, w)

	_draw_sticky(canvas, font, origin.x, w, list_top)

	var max_s: float = _max_scroll(rect)
	if max_s > 0.0:
		var track_top: float = origin.y + LIST_TOP + _rec_strip_h
		var track_h: float = _visible_height(rect)
		var track_x: float = origin.x + rect.size.x - 3.0
		var thumb_h: float = maxf(24.0, track_h * (_visible_height(rect) / _content_height))
		var thumb_y: float = track_top + (track_h - thumb_h) * (_scroll_offset / max_s)
		canvas.draw_rect(Rect2(track_x, track_top, 2.0, track_h), COLOR_SCROLL_TRACK, true)
		canvas.draw_rect(Rect2(track_x, thumb_y, 2.0, thumb_h), COLOR_SCROLL_THUMB, true)


func _build_layout(list: Array) -> Array:
	var groups: Dictionary = {}
	var seen_order: Array = []
	for item in list:
		var m: String = str(item.get("market", "stocks"))
		if not groups.has(m):
			groups[m] = []
			seen_order.append(m)
		groups[m].append(item)
	var ordered: Array = []
	for m in MARKET_ORDER:
		if groups.has(m):
			ordered.append(m)
	for m in seen_order:
		if not ordered.has(m):
			ordered.append(m)
	var out: Array = []
	var cy: float = 0.0
	for m in ordered:
		var items: Array = groups[m]
		out.append({"type": "header", "market": m, "count": items.size(), "cy": cy})
		cy += HEADER_H
		for item in items:
			var sym: String = str(item.get("symbol", ""))
			var nick: String = str(item.get("nickname", ""))
			out.append({"type": "row", "item": item, "cy": cy,
				"id": str(item.get("id", "")), "label": nick if nick != "" else sym})
			cy += CARD_HEIGHT
	return out

func _localize_market(market: String) -> String:
	if Lang == null:
		return market.capitalize()
	var key: String = "about.market." + market
	var t: String = Lang.t(key)
	return t if t != key else market.capitalize()

func _draw_section_header(canvas: CanvasItem, font: Font, market: String, count: int, x: float, w: float, y: float, opaque: bool) -> void:
	if opaque:
		canvas.draw_rect(Rect2(x, y, w, HEADER_H), UITheme.GROUP_BG, true)
	canvas.draw_rect(Rect2(x + CARD_GAP, y, w - CARD_GAP * 2.0, HEADER_H), COLOR_HEADER_BG, true)
	canvas.draw_rect(Rect2(x + CARD_GAP, y, 4.0, HEADER_H), COLOR_HEADER_BAR, true)
	canvas.draw_rect(Rect2(x + CARD_GAP, y + HEADER_H - 1.0, w - CARD_GAP * 2.0, 1.0),
		Color(COLOR_HEADER_BAR.r, COLOR_HEADER_BAR.g, COLOR_HEADER_BAR.b, 0.5), true)
	canvas.draw_string(UITheme.sans_bold(), Vector2(x + CARD_GAP + 12.0, y + 16.0),
		_localize_market(market), HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, FONT_HEADER, COLOR_HEADER)
	var mono: Font = _get_mono()
	if mono == null:
		mono = font
	var cnt: String = str(count)
	var cw: float = mono.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_HEADER).x
	canvas.draw_string(mono, Vector2(x + w - CARD_GAP - CARD_PAD_RIGHT - cw, y + 16.0),
		cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_HEADER, COLOR_HEADER_COUNT)

func _draw_sticky(canvas: CanvasItem, font: Font, x: float, w: float, list_top: float) -> void:
	var cur_market: String = ""
	var cur_count: int = 0
	var next_cy: float = -1.0
	for e in _layout:
		if e["type"] != "header":
			continue
		if float(e["cy"]) - _scroll_offset <= 0.5:
			cur_market = str(e["market"])
			cur_count = int(e["count"])
		elif next_cy < 0.0:
			next_cy = float(e["cy"])
	if cur_market == "":
		return
	var sticky_y: float = list_top
	if next_cy >= 0.0:
		var next_y: float = list_top + next_cy - _scroll_offset
		if next_y < list_top + HEADER_H:
			sticky_y = next_y - HEADER_H
	_draw_section_header(canvas, font, cur_market, cur_count, x, w, sticky_y, true)

func _draw_row(canvas: CanvasItem, font: Font, item: Dictionary, y_top: float, origin: Vector2, w: float) -> void:
	var symbol: String = item.get("symbol", "")
	var nickname: String = item.get("nickname", "")
	var market: String = item.get("market", "stocks")
	var ticker_key: String = "%s:%s" % [market, symbol]

	var price_text := "—"
	var change_text := ""
	var change_color := COLOR_FLAT
	var prev_close := 0.0
	if DataReader != null:
		var data: Dictionary = DataReader.get_ticker(ticker_key)
		if not data.is_empty():
			var price = data.get("price", null)
			var open_price = data.get("open_price", null)
			var change_pct = data.get("change_pct", null)
			var pc = data.get("previous_close", null)
			if pc != null:
				prev_close = float(pc)
			if price != null:
				price_text = _format_price(float(price))
			var abs_part := ""
			var pct_part := ""
			if price != null and open_price != null:
				abs_part = _format_change_abs(float(price) - float(open_price))
			if change_pct != null:
				pct_part = _format_change_pct(float(change_pct))
				change_color = _color_for_change(float(change_pct))
			if abs_part != "" and pct_part != "":
				change_text = "%s  %s" % [abs_part, pct_part]
			elif pct_part != "":
				change_text = pct_part
			else:
				change_text = abs_part

	var card_x: float = origin.x + CARD_GAP
	var card_w: float = w - CARD_GAP * 2.0
	var card_top: float = y_top + CARD_GAP
	var card_h: float = CARD_HEIGHT - CARD_GAP * 2.0
	canvas.draw_style_box(_card_style(), Rect2(card_x, card_top, card_w, card_h))

	var num_font: Font = _get_mono()
	if num_font == null:
		num_font = font

	var pad_l: float = card_x + CARD_PAD_LEFT
	var pad_r: float = card_x + card_w - CARD_PAD_RIGHT

	canvas.draw_string(num_font, Vector2(pad_l, card_top + 22.0),
		symbol, HORIZONTAL_ALIGNMENT_LEFT, SYM_ZONE, FONT_SYMBOL, COLOR_PRICE)
	if nickname != "" and nickname != symbol:
		canvas.draw_string(font, Vector2(pad_l, card_top + 39.0),
			nickname, HORIZONTAL_ALIGNMENT_LEFT, SYM_ZONE + 18.0, FONT_NICK, COLOR_NICK)

	var price_font: int = FONT_PRICE if price_text != "—" else FONT_NO_DATA
	var price_color: Color = COLOR_PRICE if price_text != "—" else COLOR_NICK
	var price_w: float = num_font.get_string_size(price_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, price_font).x
	canvas.draw_string(num_font, Vector2(pad_r - price_w, card_top + 22.0),
		price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, price_font, price_color)

	var right_zone_left: float = pad_r - price_w
	if change_text != "":
		var chg_w: float = num_font.get_string_size(change_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE).x
		var pill_w: float = chg_w + 12.0
		var pill_x: float = pad_r - pill_w
		canvas.draw_rect(Rect2(pill_x, card_top + 30.0, pill_w, 16.0),
			Color(change_color.r, change_color.g, change_color.b, 0.14), true)
		canvas.draw_string(num_font, Vector2(pill_x + 6.0, card_top + 41.0),
			change_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_CHANGE, change_color)
		right_zone_left = minf(right_zone_left, pill_x)

	var chart_left: float = pad_l + SYM_ZONE + 6.0
	var chart_right: float = right_zone_left - CANDLE_GAP
	if DataReader != null and chart_right - chart_left > BAR_BODY_W:
		_draw_bars(canvas, chart_left, chart_right - chart_left, y_top,
			DataReader.get_bars(ticker_key), prev_close)

func _recording() -> bool:
	return PriceRecorder != null and PriceRecorder.is_recording()

func _draw_rec_strip(canvas: CanvasItem, font: Font, rect: Rect2) -> void:
	var origin: Vector2 = rect.position
	var w: float = rect.size.x
	var label: String = Lang.t("rec.recording") if Lang != null else "REC"
	var fs: int = 11
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var dot_r: float = 3.0
	var gap: float = 7.0
	var group_w: float = dot_r * 2.0 + gap + tw
	var start_x: float = origin.x + (w - group_w) * 0.5
	var cy: float = origin.y + REC_STRIP_H * 0.5
	canvas.draw_circle(Vector2(start_x + dot_r, cy), dot_r, COLOR_REC)
	canvas.draw_string(font, Vector2(start_x + dot_r * 2.0 + gap, cy + fs * 0.35),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COLOR_REC)
	canvas.draw_line(Vector2(origin.x, origin.y + REC_STRIP_H - 0.5),
		Vector2(origin.x + w, origin.y + REC_STRIP_H - 0.5), COLOR_SEP, 1.0, false)


func _draw_bars(canvas: CanvasItem, chart_x: float, chart_w: float, y_top: float,
		bars: Array, prev_close: float) -> void:
	if bars.is_empty() or chart_w <= BAR_BODY_W:
		return

	var area_top: float = y_top + CANDLE_TOP_PAD
	var area_bot: float = y_top + CARD_HEIGHT - CANDLE_BOT_PAD
	var area_h: float = area_bot - area_top
	if area_h <= 1.0:
		return

	var slot: float = BAR_BODY_W + BAR_GAP
	var max_fit: int = int(chart_w / slot)
	if max_fit < 1:
		return
	var shown: Array = bars
	if bars.size() > max_fit:
		shown = bars.slice(bars.size() - max_fit)
	var n: int = shown.size()

	var chart_lo: float = INF
	var chart_hi: float = -INF
	for b in shown:
		chart_lo = minf(chart_lo, float(b["l"]))
		chart_hi = maxf(chart_hi, float(b["h"]))
	if prev_close > 0.0:
		chart_lo = minf(chart_lo, prev_close)
		chart_hi = maxf(chart_hi, prev_close)
	var span: float = chart_hi - chart_lo
	var right_edge: float = chart_x + chart_w

	if prev_close > 0.0 and span >= 0.0001:
		var y_base: float = area_bot - (prev_close - chart_lo) / span * area_h
		_draw_dashed_hline(canvas, chart_x, right_edge, y_base, Color(0.6, 0.65, 0.72, 0.5))

	for i in range(n):
		var b: Dictionary = shown[i]
		var bo := float(b["o"])
		var bc := float(b["c"])
		var bh := float(b["h"])
		var bl := float(b["l"])
		var cx: float = right_edge - (n - 1 - i) * slot - BAR_BODY_W * 0.5
		var col := COLOR_UP if bc >= bo else COLOR_DOWN

		if span < 0.0001:
			var ym: float = (area_top + area_bot) * 0.5
			canvas.draw_line(Vector2(cx - BAR_BODY_W * 0.5, ym),
				Vector2(cx + BAR_BODY_W * 0.5, ym), col, 1.0, false)
			continue

		var y_hi: float = area_bot - (bh - chart_lo) / span * area_h
		var y_lo: float = area_bot - (bl - chart_lo) / span * area_h
		var y_o: float = area_bot - (bo - chart_lo) / span * area_h
		var y_c: float = area_bot - (bc - chart_lo) / span * area_h

		canvas.draw_line(Vector2(cx, y_hi), Vector2(cx, y_lo), col, 1.0, false)

		var body_top: float = minf(y_o, y_c)
		var body_bot: float = maxf(y_o, y_c)
		if body_bot - body_top < 1.0:
			body_top -= 0.5
			body_bot += 0.5
		canvas.draw_rect(Rect2(cx - BAR_BODY_W * 0.5, body_top,
			BAR_BODY_W, body_bot - body_top), col, true)


func _draw_dashed_hline(canvas: CanvasItem, x0: float, x1: float, y: float, col: Color) -> void:
	var dash := 4.0
	var gap := 3.0
	var cx := x0
	while cx < x1:
		var seg_end := minf(cx + dash, x1)
		canvas.draw_line(Vector2(cx, y), Vector2(seg_end, y), col, 1.0, true)
		cx = seg_end + gap


func _visible_height(rect: Rect2) -> float:
	return rect.size.y - LIST_BOTTOM_RESERVE - LIST_TOP - _rec_strip_h

func _max_scroll(rect: Rect2) -> float:
	return maxf(0.0, _content_height - _visible_height(rect))

func _clamp_scroll(rect: Rect2) -> void:
	var m: float = _max_scroll(rect)
	_scroll_target = clampf(_scroll_target, 0.0, m)
	_scroll_offset = clampf(_scroll_offset, 0.0, m)

func scroll_by(delta: float) -> bool:
	var prev: float = _scroll_target
	_scroll_target = clampf(_scroll_target + delta, 0.0, _max_scroll(_last_rect))
	return _scroll_target != prev

func tick(delta: float) -> bool:
	if is_equal_approx(_scroll_offset, _scroll_target):
		return false
	if absf(_scroll_target - _scroll_offset) < 0.5:
		_scroll_offset = _scroll_target
		return true
	_scroll_offset = lerpf(_scroll_offset, _scroll_target, clampf(delta * SCROLL_LERP, 0.0, 1.0))
	return true

func _row_at(local_pos: Vector2) -> Dictionary:
	var top: float = _last_rect.position.y + LIST_TOP + _rec_strip_h
	var bottom: float = _last_rect.position.y + _last_rect.size.y - LIST_BOTTOM_RESERVE
	if local_pos.y < top + HEADER_H or local_pos.y > bottom:
		return {}
	var content_y: float = local_pos.y - top + _scroll_offset
	for e in _layout:
		if e["type"] != "row":
			continue
		var cy: float = float(e["cy"])
		if content_y >= cy and content_y < cy + CARD_HEIGHT:
			return e
	return {}

func item_id_at(local_pos: Vector2) -> String:
	var e := _row_at(local_pos)
	return str(e.get("id", "")) if not e.is_empty() else ""

func item_label_at(local_pos: Vector2) -> String:
	var e := _row_at(local_pos)
	return str(e.get("label", "")) if not e.is_empty() else ""


func _format_price(p: float) -> String:
	if absf(p) < 1.0:
		return "%.4f" % p
	return _add_thousands_sep("%.2f" % p)

func _add_thousands_sep(s: String) -> String:
	var dot: int = s.find(".")
	var int_part: String = s.substr(0, dot) if dot >= 0 else s
	var dec_part: String = s.substr(dot) if dot >= 0 else ""
	var neg: bool = int_part.begins_with("-")
	if neg:
		int_part = int_part.substr(1)
	var out: String = ""
	var n: int = int_part.length()
	for i in range(n):
		if i > 0 and (n - i) % 3 == 0:
			out += ","
		out += int_part[i]
	if neg:
		out = "-" + out
	return out + dec_part

func _format_change_abs(c: float) -> String:
	var s: String
	if absf(c) < 1.0:
		s = "%.4f" % c
	else:
		s = _add_thousands_sep("%.2f" % c)
	if c >= 0 and not s.begins_with("-"):
		return "+" + s
	return s

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
