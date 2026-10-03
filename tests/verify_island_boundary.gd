extends Node
## verify_island_boundary.gd — 「中间是陆地, 外边为海, 以此为边界」(A 刀)
##
## ★需求原文(用户 2026-10-03): 「要么中间就是可活动的陆地，外边为海，以此为边界」
##   ⇒ 一个东西只表达一件事: 看见陆地就是能走, 看见海就是不能走。
##
## ★为什么这条判据有必要: 改之前实测 `data/maps/arena.json` 跟需求**正好是反的** ——
##   ARENA 内 30.8% 是水(240/779 格)、ARENA 外 40.7% 是草地(485/1193 格)。
##   玩家读不出边界的真因不是"画得糊", 是**边界两边是同一种东西**。
##
## ★判据只问两件事, 两条都配分母(N=0 是空检查不是通过):
##     ① ARENA 覆盖区内 water 格 == 0
##     ② ARENA 外的陆地格(grass/stone/sand) == 0
##   再加一条「岛轮廓还在」(void > 0), 否则把整张图铺成水也能过 ①②。
##
## ★★**可活动区 = ARENA 矩形** 这一点是被代码逼出来的, 不是美术选择:
##   移动钳位是 `clampf(pos.x, ARENA.position.x, ARENA.end.x)`(x/y 各自独立),
##   在 `RealtimeBattle3DScene.gd` 里有 4 处同样的副本(:2500 :4524 :5314 :5348)。
##   ⇒ 海岸线只能正好落在这个矩形上; 想要有机形状的岸线必须先把钳位改成形状感知的,
##   那是**玩法改动**(角上活动空间会少), 不在本刀范围内。
##
## ★不读产品常量以外的任何数: ARENA 直接取 `RTScene.ARENA`, 格子类型取 json 自己的 `types`
##   ⇒ 哪天 ARENA 改了或者 types 换序, 这条判据跟着走, 不会变成对着旧数字算。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MAP_PATH := "res://data/maps/arena.json"

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 岛与海: 中间陆地 / 外边海 / 边界=海岸线 ===")

	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	_ok("★分母: arena.json 打得开", f != null, MAP_PATH)
	if f == null:
		_done()
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_ok("★分母: arena.json 解析出字典", parsed is Dictionary)
	if not (parsed is Dictionary):
		_done()
		return
	var d: Dictionary = parsed

	var types: Array = d.get("types", [])
	var i_grass: int = types.find("grass")
	var i_water: int = types.find("water")
	var i_stone: int = types.find("stone")
	var i_sand: int = types.find("sand")
	var i_void: int = types.find("void")
	_ok("★分母: types 里五种地块下标都查得到(换序也不会算错)",
		i_grass >= 0 and i_water >= 0 and i_stone >= 0 and i_sand >= 0 and i_void >= 0,
		"grass=%d water=%d stone=%d sand=%d void=%d" % [i_grass, i_water, i_stone, i_sand, i_void])
	if i_water < 0 or i_void < 0:
		_done()
		return

	var tile: float = float(d.get("tile", 0.0))
	var ox: float = float(d.get("origin_x", 0.0))
	var oy: float = float(d.get("origin_y", 0.0))
	var w: int = int(d.get("w", 0))
	var h: int = int(d.get("h", 0))
	var grid: Array = d.get("grid", [])
	_ok("★分母: grid 尺寸与 w/h 一致", grid.size() == h and tile > 0.0 and w > 0,
		"grid %d 行 · w=%d h=%d tile=%.2f" % [grid.size(), w, h, tile])
	if grid.size() != h or tile <= 0.0:
		_done()
		return

	## ★★用**产品自己的** `ArenaShape.in_rect_shape()` 判"可活动", 不在这里重写一份形状公式 ——
	##   重写一份就等于手抄, 哪天 `ARENA_SHAPE_N` 改了这条判据会悄悄量错(memory
	##   `fb-hand-rolled-copies-drift` / `fb-猜字段名会静默数成0` 同族)。
	## ★离散化容差: 格子按**中心点**判, 而形状是连续的 ⇒ 边界上一圈格子天生两边都沾。
	##   ⇒ 只对**明确在内**(内缩一格还在里面)和**明确在外**(外扩一格仍在外面)的格子下断言,
	##   夹在中间那一圈单独记成"边界格"并打印分母, 不许静默吞掉。
	var land := [i_grass, i_stone, i_sand]
	var strict_in := 0
	var strict_in_notland := 0
	var strict_out := 0
	var strict_out_land := 0
	var edge_cells := 0
	var voids := 0
	for r in range(h):
		var row: Array = grid[r]
		for c in range(mini(w, row.size())):
			var v: int = int(row[c])
			if v == i_void:
				voids += 1
			var px: float = ox + (float(c) + 0.5) * tile
			var py: float = oy + (float(r) + 0.5) * tile
			var p := Vector2(px, py)
			var inner: bool = ArenaShape.in_rect_shape(p, RTScene.ARENA, tile)        # 内缩一格还在里面 = 明确在内
			var outer: bool = ArenaShape.in_rect_shape(p, RTScene.ARENA, -tile)       # 外扩一格仍在外面 = 明确在外
			if inner:
				strict_in += 1
				if not (v in land):
					strict_in_notland += 1
			elif not outer:
				strict_out += 1
				if v in land:
					strict_out_land += 1
			else:
				edge_cells += 1

	_ok("★分母: 明确在可活动区内的格子 > 0(0 的话 ① 恒真)", strict_in > 0, "%d 格" % strict_in)
	_ok("★分母: 明确在可活动区外的格子 > 0(0 的话 ② 恒真)", strict_out > 0, "%d 格" % strict_out)
	_ok("★分母: 边界那一圈格子数(它们两边都沾, 本判据不对它们下断言)",
		edge_cells > 0 and edge_cells < strict_in, "边界格 %d · 内 %d · 外 %d" % [edge_cells, strict_in, strict_out])

	# ── ① 中间是可活动的陆地 ⇒ 区内零水 ──
	_ok("①★★可活动区内每一格都是陆（龟站的地方不许是水/虚空）",
		strict_in_notland == 0, "非陆 %d / %d 格" % [strict_in_notland, strict_in])

	# ── ② 外边为海 ⇒ 区外零陆 ──
	_ok("②★★可活动区外没有一格是陆（走不到的地方不许画成陆地）",
		strict_out_land == 0, "区外陆格 %d / %d" % [strict_out_land, strict_out])

	# ── ③ 岛轮廓还在: 否则把整张图铺成水也能过 ①② ──
	_ok("③★岛的 void 轮廓仍在（全铺满就没有剪影了, 而 ①② 对铺满无感）",
		voids > 0, "void %d 格" % voids)

	_done()


func _done() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 岛与海" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
