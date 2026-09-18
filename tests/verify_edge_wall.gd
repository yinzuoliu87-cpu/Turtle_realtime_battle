extends Node
## verify_edge_wall.gd — 场地边界墙(P1-5·v0.19.405)真的建出来了、且建对了
##
## ★为什么需要这条: `docs/plans/.../20260918` 的 P1-5 打勾时被 `plans_lint` 拦下 ——
##   「新打的勾必须写清哪条门禁证明了它」。此前边界墙只有实拍佐证,
##   而 `tools/battle_scene_audit.py` 进不了无头门禁(需要渲染, 见方案书 R10)。
##
## ★判据不许是恒真式。本项目栽过太多次「断言我自己插的标记」——
##   所以这里**独立地从 arena.json 重算一遍**「朝北的连续边界段有几段」,
##   再和产品真建出来的墙卡数对账。两边任一改坏都会红:
##     · 产品侧漏建/多建 ⇒ 数量对不上
##     · 产品侧改了「只画朝北」的规则 ⇒ 数量对不上
##     · 我这份重算写错 ⇒ 数量对不上(不会悄悄放过)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_edge_wall.tscn --quit-after 1200

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BWB := preload("res://scripts/scenes/battle/battle_world_builder.gd")

var _ok_n := 0
var _fail := 0

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok_n += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

func _ready() -> void:
	await get_tree().process_frame
	print("── 场地边界墙(P1-5) ──")

	# ── ① 独立重算: 从 arena.json 数「朝北的连续边界段」有几段 ──
	var f := FileAccess.open(BWB.MAP_PATH, FileAccess.READ)
	_chk("① ★分母: arena.json 打得开", f != null, BWB.MAP_PATH)
	if f == null:
		_done(); return
	var data = JSON.parse_string(f.get_as_text()); f.close()
	var grid: Array = data.get("grid", [])
	var w: int = int(data.get("w", 0))
	var h: int = int(data.get("h", 0))
	_chk("① ★分母: grid 非空且 w/h 有值", grid.size() > 0 and w > 0 and h > 0, "%d×%d, grid %d 行" % [w, h, grid.size()])
	var VOID := 4
	var at := func(r: int, c: int) -> int:
		if r < 0 or r >= h or c < 0 or c >= w: return VOID
		var row: Array = grid[r]
		if c >= row.size(): return VOID
		return int(row[c])
	var want_runs := 0
	var n_edge_north := 0
	for r in range(h):
		var c := 0
		while c < w:
			if at.call(r, c) == VOID or at.call(r - 1, c) != VOID:
				c += 1; continue
			want_runs += 1
			while c < w and at.call(r, c) != VOID and at.call(r - 1, c) == VOID:
				n_edge_north += 1
				c += 1
	_chk("① ★分母: 朝北边界格 > 0(否则这条门禁什么都没测)", n_edge_north > 0, "%d 格 / %d 段" % [n_edge_north, want_runs])

	# ── ② 产品侧: 走真入口建整个战场, 不自己调 build_edge_wall ──
	var inst = RB.new()
	add_child(inst)
	var wcnt := 0
	while wcnt < 900 and inst._world == null:
		await get_tree().process_frame
		wcnt += 1
	for _i in range(20):
		await get_tree().process_frame
	_chk("② ★分母: 战场 _world 建出来了", inst._world != null)
	if inst._world == null:
		_done(); return
	var root: Node = inst._world.get_node_or_null("EdgeWall")
	_chk("② ★边界墙节点 EdgeWall 真的进了场景树(不是只写了函数没人调)", root != null)
	if root == null:
		_done(); return

	var cards: Array = []
	for ch in root.get_children():
		if ch is MeshInstance3D:
			cards.append(ch)
	_chk("② ★墙卡数 == 独立重算的朝北段数", cards.size() == want_runs,
		"实建 %d · 独立算 %d" % [cards.size(), want_runs])

	# ── ③ 每张卡的几何/材质对不对 ──
	## ★★判据必须钉在【标定出来的字面值】上, 不能读产品的 WALL_H_M ——
	##   第一版我写的是 `size.y == BWB.WALL_H_M`, 反向验证时把常量改成 0.55,
	##   **门禁一条都没红**: 等号两边一起变了。这就是「门禁自己喂那个字段再去测它」的恒真式
	##   (memory: fb-gate-must-measure-requirement-not-my-hook / fb-verify-check-can-fail)。
	##   1.11 的来历: 参考实测 竖面÷角色屏幕高 = 0.81, 龟屏幕高中位 38px ⇒ 目标 31px,
	##   billboard 不吃俯角压缩 ⇒ 31 ÷ 27.78 px/米 = 1.11。见 docs/design/20260918-场地边界墙标定.md。
	##   ⇒ 改这个数就是改产品行为, 必须连这行判据一起改, 并重跑实拍复量。
	const WALL_H_EXPECT := 1.11
	_chk("③ ★分母: 产品常量 WALL_H_M 与标定值一致(改了要重新标定, 不许偷偷改)",
		absf(BWB.WALL_H_M - WALL_H_EXPECT) < 0.001, "产品 %.3f · 标定 %.3f" % [BWB.WALL_H_M, WALL_H_EXPECT])
	var bad_h := 0
	var bad_mat := 0
	var bad_filter := 0
	var bad_bb := 0
	var total_w := 0.0
	for mi in cards:
		var q = (mi as MeshInstance3D).mesh
		if not (q is QuadMesh) or absf((q as QuadMesh).size.y - WALL_H_EXPECT) > 0.001:
			bad_h += 1
		else:
			total_w += (q as QuadMesh).size.x
		var m = (mi as MeshInstance3D).material_override
		if not (m is StandardMaterial3D):
			bad_mat += 1; continue
		var sm: StandardMaterial3D = m
		if sm.albedo_texture == null or not str(sm.albedo_texture.resource_path).ends_with("wall-edge.png"):
			bad_mat += 1
		if sm.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			bad_filter += 1
		if sm.billboard_mode != BaseMaterial3D.BILLBOARD_ENABLED:
			bad_bb += 1
	_chk("③ ★每张卡高度 = %.2f 米(标定字面值·不读产品常量)" % WALL_H_EXPECT, bad_h == 0, "不合 %d/%d" % [bad_h, cards.size()])
	_chk("③ ★每张卡都用 wall-edge.png(不是退回默认白材质)", bad_mat == 0, "不合 %d/%d" % [bad_mat, cards.size()])
	_chk("③ ★NEAREST 过滤(像素画不许插值成糊)", bad_filter == 0, "不合 %d/%d" % [bad_filter, cards.size()])
	_chk("③ ★billboard 朝相机(世界高按 1.11 口径, 关掉就会矮一半)", bad_bb == 0, "不合 %d/%d" % [bad_bb, cards.size()])

	# ── ④ 总宽 == 朝北边界格数 × 一格宽: 段没有漏格也没有重复覆盖 ──
	var tile: float = float(data.get("tile", 48.0))
	var want_w: float = float(n_edge_north) * tile * inst.WS
	_chk("④ ★所有段的总宽 == 朝北边界格数 × 格宽(漏一格或叠一格都会红)",
		absf(total_w - want_w) < 0.05, "实测 %.2f 米 · 应为 %.2f 米" % [total_w, want_w])

	# ── ⑤ 墙底贴地: 卡中心 y == 半个墙高(QuadMesh 以中心为原点) ──
	var bad_y := 0
	for mi in cards:
		if absf((mi as MeshInstance3D).position.y - WALL_H_EXPECT * 0.5) > 0.001:
			bad_y += 1
	_chk("⑤ ★墙底贴在 y=0(不是浮在空中/陷进地里)", bad_y == 0, "不合 %d/%d" % [bad_y, cards.size()])

	_done()

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 场地边界墙 (%d/%d)" % [_ok_n, _ok_n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok_n])
	get_tree().quit(1 if _fail > 0 else 0)
