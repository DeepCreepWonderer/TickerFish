extends RefCounted
class_name LottieFish
## 极简鱼:内联渲染 FishDesign 的 Lottie(swim/sleep)矢量动画。

const RENDER_SCALE := 1.1
const DESIGN_COUNT := 3
const DESIGN_IDS := ["koi", "chubby", "angel"]

static func design_name(idx: int) -> String:
	idx = clampi(idx, 0, DESIGN_COUNT - 1)
	var key: String = "design." + str(DESIGN_IDS[idx])
	var t: String = Lang.t(key) if Lang != null else key
	return t if t != key else str(DESIGN_IDS[idx]).capitalize()

const _DESIGNS := [
	{"swim": "res://assets/fish_design/fish1-swim.json", "sleep": "res://assets/fish_design/fish1-sleep.json",
		"center": Vector2(84, 75), "ref_w": 107.0, "bottom_h": 22.0, "face": 1.0},
	{"swim": "res://assets/fish_design/fish2-swim.json", "sleep": "res://assets/fish_design/fish2-sleep.json",
		"center": Vector2(46, 30), "ref_w": 81.0, "bottom_h": 17.0, "face": 1.0},
	{"swim": "res://assets/fish_design/fish3-swim.json", "sleep": "res://assets/fish_design/fish3-sleep.json",
		"center": Vector2(53, 43), "ref_w": 86.0, "bottom_h": 35.0, "face": -1.0},
]

static func label_offset(idx: int, render_w: float) -> float:
	idx = clampi(idx, 0, DESIGN_COUNT - 1)
	var d: Dictionary = _DESIGNS[idx]
	return float(d["bottom_h"]) / float(d["ref_w"]) * render_w

static func half_extent(idx: int, render_w: float) -> float:
	idx = clampi(idx, 0, DESIGN_COUNT - 1)
	var d: Dictionary = _DESIGNS[idx]
	var cx: float = float(d["center"].x)
	var rw: float = float(d["ref_w"])
	return maxf(cx, rw - cx) / rw * render_w

static var _cache := {}
static var _unavailable := false

static func available() -> bool:
	if _unavailable:
		return false
	return _get_anim(0, false) != null

static func _get_anim(idx: int, sleep: bool) -> Dictionary:
	var key := "%d_%s" % [idx, "s" if sleep else "w"]
	if _cache.has(key):
		return _cache[key]
	var path: String = _DESIGNS[idx][("sleep" if sleep else "swim")]
	var parsed = null
	var res = load(path) if ResourceLoader.exists(path) else null
	if res is JSON:
		parsed = res.data
	if not (parsed is Dictionary):
		var txt := FileAccess.get_file_as_string(path)
		if txt != "":
			parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		_unavailable = true
		push_warning("[LottieFish] 加载失败,回退极简程序化鱼:" + path)
		_cache[key] = {}
		return {}
	_cache[key] = parsed
	return parsed

static func draw_fish(ci: CanvasItem, idx: int, sleep: bool, anim_time: float,
		play_rate: float, render_w: float, tint: Color, alpha: float) -> bool:
	if alpha <= 0.001:
		return true
	idx = clampi(idx, 0, DESIGN_COUNT - 1)
	var anim := _get_anim(idx, sleep)
	if anim.is_empty():
		return false
	var design: Dictionary = _DESIGNS[idx]
	var fr: float = float(anim.get("fr", 30.0))
	var op: float = float(anim.get("op", 48.0))
	var frame: float = fmod(anim_time * fr * play_rate, op)
	var scale: float = render_w / float(design["ref_w"])
	var face: float = float(design.get("face", 1.0))

	var layers: Array = anim.get("layers", [])
	for li in range(layers.size() - 1, -1, -1):
		var layer: Dictionary = layers[li]
		if str(layer.get("nm", "")).begins_with("Z"):
			continue
		_draw_layer(ci, layer, frame, design["center"], scale, face, tint, alpha)
	return true

static func _draw_layer(ci: CanvasItem, layer: Dictionary, frame: float,
		center_local: Vector2, scale: float, face: float, tint: Color, alpha: float) -> void:
	var ks: Dictionary = layer.get("ks", {})
	var layer_op: float = _num(_val(ks.get("o", {"a": 0, "k": 100}), frame), 100.0) / 100.0
	var a = ks.get("a", {"a": 0, "k": [0, 0]})
	var t_layer := _xform(ks.get("p"), a, ks.get("s"), ks.get("r"), frame)
	var anchor := _vec(_val(a, 0.0))
	var rest_center := _vec(_val(ks.get("p", {"a": 0, "k": [0, 0]}), 0.0)) + (center_local - anchor)

	var ctx := {
		"ci": ci, "frame": frame, "rest": rest_center, "scale": scale,
		"face": face, "tint": tint, "alpha": alpha * layer_op,
	}
	var shapes: Array = layer.get("shapes", [])
	for si in range(shapes.size() - 1, -1, -1):
		var grp: Dictionary = shapes[si]
		if str(grp.get("ty", "")) == "gr":
			_draw_group(ctx, grp.get("it", []), t_layer)

static func _draw_group(ctx: Dictionary, items: Array, parent: Transform2D) -> void:
	var local := parent
	var fill = null
	var stroke = null
	for it in items:
		match str(it.get("ty", "")):
			"tr":
				local = parent * _xform(it.get("p"), it.get("a"), it.get("s"), it.get("r"), ctx["frame"])
			"fl":
				fill = it
			"st":
				stroke = it
	for i in range(items.size() - 1, -1, -1):
		var it = items[i]
		var ty := str(it.get("ty", ""))
		if ty == "gr":
			_draw_group(ctx, it.get("it", []), local)
		elif ty == "el":
			_paint(ctx, _ellipse_pts(it, ctx["frame"]), true, fill, stroke, local)
		elif ty == "sh":
			var res := _path_pts(it, local, ctx)
			_paint_pts(ctx, res["pts"], res["closed"], fill, stroke)

static func _paint(ctx: Dictionary, local_pts: PackedVector2Array, closed: bool,
		fill, stroke, xform: Transform2D) -> void:
	var pts := PackedVector2Array()
	for p in local_pts:
		pts.append(_map(ctx, xform * p))
	_paint_pts(ctx, pts, closed, fill, stroke)

static func _paint_pts(ctx: Dictionary, pts: PackedVector2Array, closed: bool,
		fill, stroke) -> void:
	if pts.size() < 2:
		return
	var ci: CanvasItem = ctx["ci"]
	if fill != null and pts.size() >= 3:
		var col := _paint_color(fill, ctx["tint"], ctx["alpha"])
		ci.draw_colored_polygon(pts, col)
	if stroke != null:
		var col := _paint_color(stroke, ctx["tint"], ctx["alpha"])
		var w: float = _num(_val(stroke.get("w", {"a": 0, "k": 1.0}), ctx["frame"]), 1.0) * ctx["scale"]
		var line := pts
		if closed:
			line = pts.duplicate()
			line.append(pts[0])
		ci.draw_polyline(line, col, max(1.0, w), true)

# --- 几何 ---

static func _ellipse_pts(el: Dictionary, frame: float) -> PackedVector2Array:
	var c := _vec(_val(el.get("p"), frame))
	var s := _vec(_val(el.get("s"), frame))
	var rx := s.x * 0.5
	var ry := s.y * 0.5
	var pts := PackedVector2Array()
	var seg := 22
	for i in range(seg):
		var a := i / float(seg) * TAU
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

static func _path_pts(sh: Dictionary, xform: Transform2D, ctx: Dictionary) -> Dictionary:
	var ks = sh.get("ks", {})
	var k = ks.get("k", {})
	var closed := bool(k.get("c", false))
	var v: Array = k.get("v", [])
	var it: Array = k.get("i", [])
	var ot: Array = k.get("o", [])
	var pts := PackedVector2Array()
	var n := v.size()
	if n == 0:
		return {"pts": pts, "closed": closed}
	var count := n if closed else n - 1
	for seg in range(count):
		var a := seg
		var b := (seg + 1) % n
		var p0 := Vector2(v[a][0], v[a][1])
		var p3 := Vector2(v[b][0], v[b][1])
		var c1 := p0 + Vector2(ot[a][0], ot[a][1])
		var c2 := p3 + Vector2(it[b][0], it[b][1])
		var steps := 10
		for i in range(steps):
			var tt := i / float(steps)
			pts.append(_map(ctx, xform * _cubic(p0, c1, c2, p3, tt)))
	if not closed:
		pts.append(_map(ctx, xform * Vector2(v[n - 1][0], v[n - 1][1])))
	return {"pts": pts, "closed": closed}

static func _cubic(p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * p3

static func _map(ctx: Dictionary, comp: Vector2) -> Vector2:
	var p: Vector2 = (comp - ctx["rest"]) * ctx["scale"]
	p.x *= ctx["face"]
	return p

# --- 颜色 ---

static func _paint_color(paint: Dictionary, tint: Color, alpha: float) -> Color:
	var raw := _val(paint.get("c"), 0.0)
	var c := Color(float(raw[0]), float(raw[1]), float(raw[2]),
		float(raw[3]) if raw.size() > 3 else 1.0)
	var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	if lum > 0.4:
		c = Color(tint.r, tint.g, tint.b, c.a)
	var o: float = _num(_val(paint.get("o", {"a": 0, "k": 100}), 0.0), 100.0) / 100.0
	c.a *= o * alpha
	return c

# --- 变换与关键帧 ---

static func _xform(p, a, s, r, frame: float) -> Transform2D:
	var pv := _vec(_val(p, frame)) if p != null else Vector2.ZERO
	var av := _vec(_val(a, frame)) if a != null else Vector2.ZERO
	var sv := _vec(_val(s, frame)) if s != null else Vector2(100, 100)
	var rv: float = _num(_val(r, frame), 0.0) if r != null else 0.0
	var t := Transform2D.IDENTITY
	t = t.translated_local(pv)
	t = t.rotated_local(deg_to_rad(rv))
	t = t.scaled_local(Vector2(sv.x / 100.0, sv.y / 100.0))
	t = t.translated_local(-av)
	return t

static func _val(prop, frame: float) -> Array:
	if prop == null:
		return [0.0]
	var k = prop.get("k")
	if int(prop.get("a", 0)) == 0:
		if k is Array:
			return k
		return [float(k)]
	var kfs: Array = k
	if kfs.is_empty():
		return [0.0]
	if frame <= float(kfs[0].get("t", 0)):
		return kfs[0].get("s", [0.0])
	var last: Dictionary = kfs[kfs.size() - 1]
	if frame >= float(last.get("t", 0)):
		return last.get("s", kfs[kfs.size() - 2].get("s", [0.0]))
	for i in range(kfs.size() - 1):
		var ka: Dictionary = kfs[i]
		var kb: Dictionary = kfs[i + 1]
		var ta := float(ka.get("t", 0))
		var tb := float(kb.get("t", 0))
		if frame < ta or frame > tb:
			continue
		var sa: Array = ka.get("s", [0.0])
		var sb: Array = kb.get("s", sa)
		var lt := 0.0 if tb == ta else (frame - ta) / (tb - ta)
		var e := _ease(lt, ka.get("o"), ka.get("i"))
		var out: Array[float] = []
		for j in range(sa.size()):
			out.append(lerp(float(sa[j]), float(sb[j]) if j < sb.size() else float(sa[j]), e))
		return out
	return last.get("s", [0.0])

static func _ease(t: float, o, i) -> float:
	if o == null or i == null:
		return t
	var ox := float(o.get("x", [t])[0])
	var oy := float(o.get("y", [t])[0])
	var ix := float(i.get("x", [t])[0])
	var iy := float(i.get("y", [t])[0])
	var u := t
	for _n in range(8):
		var x := _bez1(u, ox, ix)
		var dx := _bez1d(u, ox, ix)
		if abs(dx) < 0.0001:
			break
		u -= (x - t) / dx
		u = clampf(u, 0.0, 1.0)
	return _bez1(u, oy, iy)

static func _bez1(u: float, c1: float, c2: float) -> float:
	var v := 1.0 - u
	return 3.0 * v * v * u * c1 + 3.0 * v * u * u * c2 + u * u * u

static func _bez1d(u: float, c1: float, c2: float) -> float:
	var v := 1.0 - u
	return 3.0 * v * v * c1 + 6.0 * v * u * (c2 - c1) + 3.0 * u * u * (1.0 - c2)

static func _vec(arr: Array) -> Vector2:
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	if arr.size() == 1:
		return Vector2(float(arr[0]), float(arr[0]))
	return Vector2.ZERO

static func _num(arr: Array, def: float) -> float:
	return float(arr[0]) if arr.size() > 0 else def
