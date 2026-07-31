class_name MapField
extends RefCounted
## 地图【距离场】—— 让地面/水共用一个"知道整张地图长什么样"的 shader。
##
## 由来(用户 2026-07-31:「想想怎么从外观上做成那种精美像素风吧」「你做一板大的吧」):
##   改前每块地砖只知道自己是什么类型, 于是水陆交界只能是【硬切】——
##   亮青(98)直接怼上暗淤泥(32), 中间零过渡。近景放大一眼看穿, 这是整张图最不"精美"的地方。
##   而岸线泡沫 / 水深渐变 / 湿沙带 这些像素画里最出彩的东西, 本质上都需要同一个信息:
##   【这一点离水陆边界有多远】。与其为每样各打一个补丁, 不如烘一张距离场, 一次给全。
##
## 做法: 把 58×34 的格子烘成一张同尺寸的贴图, R 通道 = 到水陆边界的【有符号距离】(单位: 格)。
##   d > 0 在水里(越大越深) · d < 0 在陆上(越小越内陆) · d ≈ 0 就是岸线。
##   采样时用 filter_linear, 硬件插值天然给出连续的场 —— 不需要更高分辨率。
##
## ★为什么是 chamfer 两遍扫而不是 BFS: 两遍扫是 O(n), 且带对角权重(1.414)后
##   得到的是近似欧氏距离; 4 邻 BFS 会给出菱形(曼哈顿)距离, 岸线会呈现明显的 45° 折角。
##
## ★这张场【与格子无关地】被世界坐标寻址, 所以加密网格/换地图都不用改 shader。

const FIELD_R := 6.0        # 距离场量程(格)。超出就钳到 ±FIELD_R —— 6 格 ≈ 230px, 足够做岸线/浅滩
const WATER := 1

static var _cache_key: String = ""
static var _cache_tex: ImageTexture = null
static var _cache_org := Vector2.ZERO
static var _cache_size := Vector2.ONE


## 取(或烘)当前地图的距离场。返回 {tex, org, size}: org/size 是【世界坐标·米】的包围盒,
## shader 里 uv = (world_xz - org) / size。
## ws/cx/cy 由调用方给(主场景的 WS 与 ARENA 中心) —— 本类不反向依赖主场景。
static func get_field(map_path: String, ws: float, cx: float, cy: float) -> Dictionary:
	if _cache_key == map_path and _cache_tex != null:
		return {"tex": _cache_tex, "org": _cache_org, "size": _cache_size}
	var meta: Dictionary = _load(map_path)
	if meta.is_empty():
		return {}
	var w: int = int(meta["w"])
	var h: int = int(meta["h"])
	var grid: Array = meta["grid"]
	var d: Array = _chamfer(grid, w, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for r in range(h):
		for c in range(w):
			var v: float = clampf(float(d[r][c]), -FIELD_R, FIELD_R)
			img.set_pixel(c, r, Color(0.5 + v / (2.0 * FIELD_R), 0.0, 0.0, 1.0))
	_cache_tex = ImageTexture.create_from_image(img)
	_cache_key = map_path
	var tile: float = float(meta["tile"])
	# 格心在 origin + (i+0.5)*tile。贴图的 texel 中心对应格心, 所以包围盒要按【格心】给,
	# 即从第 0 格心到第 w-1 格心, 再各外扩半格 —— 正好等于 origin .. origin+w*tile。
	_cache_org = Vector2((float(meta["origin_x"]) - cx) * ws, (float(meta["origin_y"]) - cy) * ws)
	_cache_size = Vector2(float(w) * tile * ws, float(h) * tile * ws)
	return {"tex": _cache_tex, "org": _cache_org, "size": _cache_size}


static func invalidate() -> void:      # MAPEDIT 刷完格子要重烘
	_cache_key = ""
	_cache_tex = null


static func _load(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		push_warning("[mapfield] 地图不存在: %s" % p)
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (j is Dictionary) or not j.has("grid"):
		push_warning("[mapfield] 地图解析失败: %s" % p)
		return {}
	return j


## 两遍 chamfer: 先算"到水的距离", 再算"到陆的距离", 相减得有符号场。
## 权重 1 / 1.414 —— 带对角才是近似欧氏, 只走四邻会得到菱形距离(岸线出 45° 折角)。
static func _chamfer(grid: Array, w: int, h: int) -> Array:
	var to_water := _dist_to(grid, w, h, true)
	var to_land := _dist_to(grid, w, h, false)
	var out: Array = []
	for r in range(h):
		var row: Array = []
		for c in range(w):
			# 水格: 到陆的距离为正(越深越大); 陆格: 到水的距离取负
			row.append(float(to_land[r][c]) if int(grid[r][c]) == WATER else -float(to_water[r][c]))
		out.append(row)
	return out


## 到"某类格子"的 chamfer 距离(格)。want_water=true → 到最近水格的距离。
static func _dist_to(grid: Array, w: int, h: int, want_water: bool) -> Array:
	var BIG := 9999.0
	var d: Array = []
	for r in range(h):
		var row: Array = []
		for c in range(w):
			var is_w: bool = int(grid[r][c]) == WATER
			row.append(0.0 if (is_w == want_water) else BIG)
		d.append(row)
	var D1 := 1.0
	var D2 := 1.4142135
	for r in range(h):                                  # 正扫
		for c in range(w):
			var v: float = d[r][c]
			if r > 0:
				v = minf(v, d[r - 1][c] + D1)
				if c > 0: v = minf(v, d[r - 1][c - 1] + D2)
				if c < w - 1: v = minf(v, d[r - 1][c + 1] + D2)
			if c > 0: v = minf(v, d[r][c - 1] + D1)
			d[r][c] = v
	for r in range(h - 1, -1, -1):                      # 反扫
		for c in range(w - 1, -1, -1):
			var v: float = d[r][c]
			if r < h - 1:
				v = minf(v, d[r + 1][c] + D1)
				if c > 0: v = minf(v, d[r + 1][c - 1] + D2)
				if c < w - 1: v = minf(v, d[r + 1][c + 1] + D2)
			if c < w - 1: v = minf(v, d[r][c + 1] + D1)
			d[r][c] = v
	return d
