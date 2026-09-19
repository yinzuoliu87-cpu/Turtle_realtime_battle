extends Node
## verify_edge_wall — 场地边界必须被**一条连续的竖直带**盖住（整圈一段不漏）。
##
## ★★2026-09-20 改账（不是加白名单）：实现从【逐格 billboard 墙卡】换成
##   【沿整圈边界的一个连续 ArrayMesh】，原来那套判据（卡片数 / 卡片高 / billboard 开没开 /
##   段总宽）测的全是旧实现的形状，一条都不再适用。
##
## ★为什么换实现（证据在 `scratchpad/shapecal/edge/` 的 15 张参考边界裁图）：
##   2026-09-18 第一版四向全画被实拍当场否掉 ——「一层层错开互相重叠的砖带」，只好退到只画朝北一圈。
##   ★根因**不是**「岛的轮廓是阶梯」，是**卡片各自独立**：斜边上相邻 run 分属不同行，
##     每张卡各自发卡、各自朝相机，于是读成一堆错开的砖。
##   ★参考里 15 张边界裁图**没有一张是逐格卡**：Arknights_4 / BrawlStars_3 是台地挤出侧面；
##     BrawlStars_2/4 绿篱；ClashOfClans_2 城墙件排成一条；CultOfTheLamb_1 白石 curb；
##     HadesII_1 / Hades_1 栏杆女儿墙；Hades_0 骨柱环；TFT_1 植被带；TFT_2/4 石挡墙。
##   ★★跨 A/B/C 三类共 26 张，共同点是**「边界上有一条连续构件」**，不是「轮廓必须是直边」——
##     C 类（格子化阶梯，本项目就是这类）在参考里有 8 张，**格子阶梯本身不是病，裸着的阶梯边才是**。
##     ⇒ 方案书原定目标「轮廓角点 52 → ≤8」据此作废，换成本文件这条。
##
## ★旧实现只画朝北 = **整圈 174 段里只盖了 58 段**，三分之二裸着。本门禁的主判据就是这个。

const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")

## ★标定字面值，**不读产品常量** —— 读产品常量就成了恒真式：
##   2026-09-18 第一版写的是 `size.y == BWB.WALL_H_M`，测试与产品读同一个数，
##   反向验证把常量改成 0.55 时**一条都没红**。
const WALL_H_EXPECT := 1.75          # 真实竖直几何口径（billboard 口径是 1.11，差 1.58 倍，别混用）
const WS_EXPECT := 0.024             # 像素 → 米

var _pass := 0
var _fail := 0


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [name, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, extra])


func _ready() -> void:
	await get_tree().process_frame

	# ── ① 独立重算：从 arena.json 自己数一遍整圈边界 ──────────────────
	var f := FileAccess.open(BWB.MAP_PATH, FileAccess.READ)
	_chk("① ★分母: arena.json 打得开", f != null, BWB.MAP_PATH)
	if f == null:
		_done()
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	_chk("① ★分母: arena.json 解析出字典", data is Dictionary)
	if not (data is Dictionary):
		_done()
		return
	var grid: Array = (data as Dictionary).get("grid", [])
	var w: int = int((data as Dictionary).get("w", 0))
	var h: int = int((data as Dictionary).get("h", 0))
	var tile: float = float((data as Dictionary).get("tile", 0.0))
	var types: Array = (data as Dictionary).get("types", [])
	var void_i: int = types.find("void")
	_chk("① ★分母: grid/w/h/tile 都有值 且 types 里有 void",
		grid.size() > 0 and w > 0 and h > 0 and tile > 0.0 and void_i >= 0,
		"%d×%d tile=%.1f void=%d" % [w, h, tile, void_i])
	if void_i < 0:
		_done()
		return

	var at := func(r: int, c: int) -> int:
		if r < 0 or r >= h or c < 0 or c >= w:
			return void_i
		var row: Array = grid[r]
		if c >= row.size():
			return void_i
		return int(row[c])

	var want_segs := 0
	var want_north := 0
	for r in range(h):
		for c in range(w):
			if at.call(r, c) == void_i:
				continue
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				if at.call(r + int(d[0]), c + int(d[1])) == void_i:
					want_segs += 1
			if at.call(r - 1, c) == void_i:
				want_north += 1
	_chk("① ★分母: 整圈边界段 > 0(否则这条门禁什么都没测)", want_segs > 0,
		"整圈 %d 段 · 其中朝北 %d 段" % [want_segs, want_north])
	var want_perim_m: float = float(want_segs) * tile * WS_EXPECT

	# ── ② 真的建出来了（不是写了函数没人调）──────────────────────────
	var scn: PackedScene = load("res://scenes/RealtimeBattle3D.tscn")
	var inst = scn.instantiate()
	add_child(inst)
	for _i in range(6):
		await get_tree().process_frame
	_chk("② ★分母: 战场 _world 建出来了", inst._world != null)
	var root: Node = inst._world.get_node_or_null("EdgeWall") if inst._world != null else null
	_chk("② ★EdgeWall 节点真的进了场景树", root != null)
	var band: MeshInstance3D = null
	if root != null:
		band = root.get_node_or_null("EdgeBand") as MeshInstance3D
	_chk("② ★EdgeBand 是**一个** mesh(不是一堆逐格卡)", band != null and band.mesh != null,
		"子节点 %d 个" % (root.get_child_count() if root != null else -1))
	if band == null or band.mesh == null:
		inst.queue_free()
		_done()
		return

	# ── ③ ★主判据：整圈一段不漏 ──────────────────────────────────────
	var arrays: Array = band.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var quads: int = verts.size() / 6
	_chk("③ ★★四边形数 == 独立重算的整圈边界段数(旧实现只画朝北 %d 段, 会在这里红)" % want_north,
		quads == want_segs, "mesh %d 个 / 期望 %d 个" % [quads, want_segs])

	# ── ④ 高度：底贴地、顶到标定高度 ────────────────────────────────
	var y_lo := 0.0
	var y_hi := 0.0
	for v in verts:
		y_lo = minf(y_lo, v.y)
		y_hi = maxf(y_hi, v.y)
	_chk("④ ★带底贴在 y=0(不是浮空/陷地)", absf(y_lo) < 0.01, "最低 y = %.4f" % y_lo)
	_chk("④ ★带顶 = %.2f 米(标定字面值·不读产品常量)" % WALL_H_EXPECT,
		absf(y_hi - WALL_H_EXPECT) < 0.01, "最高 y = %.4f" % y_hi)
	_chk("④ ★分母: 产品常量与标定值一致(改了要重新标定, 不许偷偷改)",
		absf(BWB.WALL_H_M_GEO - WALL_H_EXPECT) < 0.001,
		"产品 %.3f · 标定 %.3f" % [BWB.WALL_H_M_GEO, WALL_H_EXPECT])

	# ── ⑤ 总长对账：横向总长 == 整圈周长 ────────────────────────────
	var total_m := 0.0
	for q in range(quads):
		var a: Vector3 = verts[q * 6 + 0]
		var b: Vector3 = verts[q * 6 + 1]
		total_m += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	_chk("⑤ ★带的总长 == 整圈周长 %.2f 米(漏一段或叠一段都会红)" % want_perim_m,
		absf(total_m - want_perim_m) < 0.05, "实测 %.2f 米" % total_m)

	# ── ⑥ 材质：像素画不糊 / 双面 / 吃光 ────────────────────────────
	var m := band.material_override as StandardMaterial3D
	_chk("⑥ ★分母: 材质是 StandardMaterial3D", m != null)
	if m != null:
		_chk("⑥ 用的是 wall-edge.png(不是退回默认白材质)",
			m.albedo_texture != null and str(m.albedo_texture.resource_path).ends_with("wall-edge.png"),
			str(m.albedo_texture.resource_path) if m.albedo_texture != null else "null")
		_chk("⑥ NEAREST 过滤(像素画不许插值成糊)",
			m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		## ★双面：远端(北)那一圈的外表面**背对相机**，不关剔除就看不见 ——
		##   而实测 49 个可见边界格里 42 个恰恰都在那一圈。
		_chk("⑥ ★双面不剔除(远端那圈背对相机, 剔了就白画)",
			m.cull_mode == BaseMaterial3D.CULL_DISABLED)
		## ★吃光（W8 关闭）：原来是 UNSHADED + 手工标定的 `WALL_GAIN`，那个数被地面亮度牵着走，
		##   2026-09-18 一天内重标定三次（1.55→1.70→2.05）。真几何吃光后不再需要它。
		_chk("⑥ ★吃光而不是 UNSHADED(W8: 干掉手工标定的 WALL_GAIN)",
			m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,
			"shading_mode=%d" % int(m.shading_mode))

	inst.queue_free()
	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 边界连续带 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 边界连续带 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
