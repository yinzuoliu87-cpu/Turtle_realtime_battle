extends Node
## verify_map_field.gd — 地图距离场 + 岸线/水深/湿沙(用户 2026-07-31「你做一板大的吧」)
##
## 守的是: 距离场【算得对】+【真的接到两个 shader 上】+ shader【真的用了它】。
##
## ★为什么值得单独一条门禁: 这套东西的失效方式是【静默的】——
##   距离场烘错/没接上/shader 忘了采样, 画面只会退回"水陆硬切", 不报错、不崩,
##   而"硬切"正是它改之前的样子, 肉眼一眼看不出是坏了还是没做。
##
## ★这里还钉死一条实测教训: 湿沙第一版 wet_tint=(0.55,0.80,0.92)×1.35,
##   亮度加权 0.299*0.74+0.587*1.08+0.114*1.24 ≈ 1.00 —— 只换色相不换明度 = 等于没做。
##   探针实测离水 1/2/3 格亮度 46/44/44 完全没梯度。所以下面直接断言【亮度必须真的变暗】。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_map_field.tscn

const MF := preload("res://scripts/scenes/battle/map_field.gd")
const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")
const MAP := "res://data/maps/arena.json"

const WS := 0.024
const CX := 868.0
const CY := 474.0

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 地图距离场 + 岸线/水深/湿沙 ===")
	MF.invalidate()
	var f: Dictionary = MF.get_field(MAP, WS, CX, CY)
	_ok("① 距离场烘得出来", not f.is_empty() and f.get("tex") != null)
	if f.is_empty() or f.get("tex") == null:
		_done(); return

	var meta = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	var w: int = int(meta["w"])
	var h: int = int(meta["h"])
	var grid: Array = meta["grid"]
	var tex: ImageTexture = f["tex"]
	_ok("① 场的尺寸 = 格子尺寸(逐格一个 texel)",
		tex.get_width() == w and tex.get_height() == h,
		"%dx%d vs 格子 %dx%d" % [tex.get_width(), tex.get_height(), w, h])

	# ── ② 符号对: 水格 d>0 / 陆格 d<0 ──
	var img: Image = tex.get_image()
	var n_w := 0
	var n_l := 0
	var bad_w := 0
	var bad_l := 0
	for r in range(h):
		for c in range(w):
			var d: float = (img.get_pixel(c, r).r - 0.5) * 2.0 * MF.FIELD_R
			if int(grid[r][c]) == 1:
				n_w += 1
				if d <= 0.0: bad_w += 1
			elif int(grid[r][c]) != 4:
				n_l += 1
				if d >= 0.0: bad_l += 1
	_ok("② ★分母: 水格 %d / 陆格 %d(两边都得有, 否则符号断言是空检查)" % [n_w, n_l],
		n_w > 50 and n_l > 50)
	_ok("② 水格的距离全为正(>0 在水里)", bad_w == 0, "%d 个符号反了" % bad_w)
	_ok("② 陆格的距离全为负(<0 在陆上)", bad_l == 0, "%d 个符号反了" % bad_l)

	# ── ③ 数值对: 紧贴水的陆格, |d| 应当 ≈ 1 格(不是 0 也不是 5) ──
	var edge_vals: Array = []
	for r in range(1, h - 1):
		for c in range(1, w - 1):
			if int(grid[r][c]) == 1 or int(grid[r][c]) == 4:
				continue
			var touch := false
			for dr in [-1, 0, 1]:
				for dc in [-1, 0, 1]:
					if absi(dr) + absi(dc) == 1 and int(grid[r + dr][c + dc]) == 1:
						touch = true
			if touch:
				edge_vals.append(absf((img.get_pixel(c, r).r - 0.5) * 2.0 * MF.FIELD_R))
	var avg := 0.0
	for v in edge_vals: avg += v
	avg = avg / maxf(1.0, float(edge_vals.size()))
	_ok("③ ★紧贴水的陆格 |d| ≈ 1 格 (分母 %d 格)" % edge_vals.size(),
		edge_vals.size() > 20 and absf(avg - 1.0) < 0.25, "实测均值 %.3f" % avg)

	# ── ③b G 通道 = 到板子外沿(void)的归一距离, 给岛缘压暗用 ──
	# ★这个通道的失效方式同样是静默的: 全 1 → 边缘不压暗(退回"板子硬生生停在黑色里"),
	#   全 0 → 整块地被压暗成一团。所以两头都要断言。
	var g_edge := 0
	var g_mid := 0
	var g_bad := 0
	for r in range(h):
		for c in range(w):
			if int(grid[r][c]) == 4:
				continue
			var gv: float = img.get_pixel(c, r).g
			if gv < 0.0 or gv > 1.0: g_bad += 1
			# 紧贴 void 或紧贴网格外框的格子, 归一距离应当很小
			var near := (r <= 1 or c <= 1 or r >= h - 2 or c >= w - 2)
			if not near:
				for dr in [-1, 0, 1]:
					for dc in [-1, 0, 1]:
						if int(grid[clampi(r + dr, 0, h - 1)][clampi(c + dc, 0, w - 1)]) == 4:
							near = true
			if near:
				if gv < 0.45: g_edge += 1
			elif gv > 0.45:
				g_mid += 1
	_ok("③b ★贴边的格子 G 小(会被压暗) —— 分母 %d" % g_edge, g_edge > 100)
	_ok("③b ★内部的格子 G 大(不该被压暗) —— 分母 %d" % g_mid, g_mid > 100)
	_ok("③b G 全在 0..1 内", g_bad == 0, "%d 个越界" % g_bad)

	# ── ④ 世界坐标映射对: 把某格的世界坐标喂回去应当落在该格的 texel 上 ──
	var tile: float = float(meta["tile"])
	var org: Vector2 = f["org"]
	var size: Vector2 = f["size"]
	var rc := Vector2i(int(w * 0.5), int(h * 0.5))
	var wp := Vector2((float(meta["origin_x"]) + (float(rc.x) + 0.5) * tile - CX) * WS,
		(float(meta["origin_y"]) + (float(rc.y) + 0.5) * tile - CY) * WS)
	var uv: Vector2 = (wp - org) / size
	_ok("④ ★世界坐标→场 UV 映射对(格心映到该 texel 的中心)",
		absf(uv.x * float(w) - (float(rc.x) + 0.5)) < 0.02
			and absf(uv.y * float(h) - (float(rc.y) + 0.5)) < 0.02,
		"uv=%.4f,%.4f → 格 %.2f,%.2f (期望 %.1f,%.1f)"
			% [uv.x, uv.y, uv.x * float(w), uv.y * float(h), float(rc.x) + 0.5, float(rc.y) + 0.5])

	# ── ⑤ 真的接到材质上(不是烘出来没人用) ──
	print("")
	for ti in [0, 1, 2, 3]:
		var m = BWB.tile_material(ti, WS, CX, CY)
		var got = m.get_shader_parameter("map_field") if m is ShaderMaterial else null
		_ok("⑤ type %d 的材质拿到了距离场" % ti, got != null)
		var sz = m.get_shader_parameter("map_size") if m is ShaderMaterial else null
		_ok("⑤ type %d 拿到了包围盒(不是默认 1×1)" % ti,
			sz != null and (sz as Vector2).length() > 1.0, "size=%s" % str(sz))

	# ── ⑥ shader 真的【用】了它(设了参数不采样 = 白设) ──
	print("")
	var inc := FileAccess.get_file_as_string("res://scripts/scenes/battle/shaders/ground_common.gdshaderinc")
	_ok("⑥ 共用件里有 shore_sdf 且它采样了 map_field",
		inc.contains("float shore_sdf") and inc.contains("texture(map_field"))
	_ok("⑥ ★抖动按【屏幕像素】取(钉在世界上会随透视糊掉, 就不是像素颗粒了)",
		inc.contains("float bayer4") and inc.contains("mod(frag.x, 4.0)"))
	var wsrc := FileAccess.get_file_as_string("res://scripts/scenes/battle/shaders/ground_water.gdshader")
	var lsrc := FileAccess.get_file_as_string("res://scripts/scenes/battle/shaders/ground_land.gdshader")
	_ok("⑥ ★水 shader 用距离场做了【水深】和【岸线泡沫】",
		wsrc.contains("shore_sdf") and wsrc.contains("foam") and wsrc.contains("depth"))
	_ok("⑥ ★陆 shader 用距离场做了【湿沙带】", lsrc.contains("shore_sdf") and lsrc.contains("wet"))
	_ok("⑥ ★两个 shader 都做了【岛缘压暗】(板子不能硬生生停在黑色里)",
		wsrc.contains("edge_fade") and lsrc.contains("edge_fade"))
	_ok("⑥ ★焦散接回真正在用的地面 shader(旧的那份写在跑不到的分支里)",
		inc.contains("float caustics") and wsrc.contains("caustics(") and lsrc.contains("caustics("))
	_ok("⑥ 梯度都过了抖动量化(平滑渐变在低色数下必出条带)",
		wsrc.contains("dither_steps") and lsrc.contains("dither_steps"))
	# ★★必须【先剥掉注释行】再查 —— 我第一版直接 contains("UV.") 当场红, 因为撞上了
	#   我自己写的说明注释「UV 是【每格 0..1】」。这个坑今天已经踩过两次(上次是 season_level)。
	_ok("⑥ 两个 shader 都不读 mesh 的 UV(读了就退回每格一个印章)",
		not _code_of(wsrc).contains("UV.") and not _code_of(lsrc).contains("UV."),
		"水:%s 陆:%s" % [_code_of(wsrc).contains("UV."), _code_of(lsrc).contains("UV.")])

	# ── ⑦ ★★湿沙必须【真的变暗】—— 第一版只换色相不换明度, 等于没做 ──
	# ★不能用 get_shader_parameter 读 —— 它对【没显式 set 过】的参数返回 null,
	#   不会回落到 shader 里写的默认值(我第一版这么写, 拿到 null → 亮度算成 0 → 假红)。
	#   直接从 shader 源码里把默认值解出来, 这也正是运行时真正生效的那个值。
	var wt: Color = _uniform_vec4(lsrc, "wet_tint")
	var lum: float = 0.299 * wt.r + 0.587 * wt.g + 0.114 * wt.b
	_ok("⑦ ★★湿沙色的【亮度加权】明显 < 1(否则只换色相不换明度 = 等于没做)",
		lum > 0.01 and lum < 0.80,
		"wet_tint=(%.2f,%.2f,%.2f) 亮度加权 = %.3f (要 0.01~0.80)" % [wt.r, wt.g, wt.b, lum])

	_done()


## 剥掉 // 注释, 只留真代码 —— 查"源码里有没有某写法"时必须先剥, 否则会撞上说明注释。
func _code_of(src: String) -> String:
	var out := ""
	for ln in src.split("
"):
		var t: String = ln.strip_edges()
		if t.begins_with("//"):
			continue
		var i: int = ln.find("//")
		out += (ln.substr(0, i) if i >= 0 else ln) + "
"
	return out


## 从 shader 源码里解出某个 uniform vec4 的默认值(运行时生效的就是它)。
func _uniform_vec4(src: String, name: String) -> Color:
	for ln in src.split("
"):
		if not ln.contains("uniform vec4 " + name):
			continue
		var i: int = ln.find("vec4(", ln.find("="))
		if i < 0:
			continue
		var body: String = ln.substr(i + 5, ln.find(")", i) - i - 5)
		var parts: PackedStringArray = body.split(",")
		if parts.size() >= 3:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]))
	return Color(0, 0, 0)


func _done() -> void:
	print("")
	print("  (共 %d 条)" % _n)
	print("ALL PASS — 地图距离场·岸线/水深/湿沙" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
