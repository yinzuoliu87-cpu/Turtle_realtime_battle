extends Node
## verify_decor_grounded.gd — 四版主题的装饰物必须站在平台边沿以内, 不许摆到岛外黑海面/半空
##
## ★由来(用户 2026-10-03, 看着深礁截图):「装饰物乱飞到上面，人家是这么做的吗」
##   查出三层在岛外摆东西: 边框密植(岛外 200px 网格) / 默认中景(沉船/紫海葵) / 远景发光群。
##   岛外是近黑的海面, 物件脚下没有看得见的地, 透视一抬就飘到画面上方。
##   参考(咩咩真实游玩截帧)外围的东西都有落脚点: 插地火把、从边沿长出来的草和树。
## ★量的是**产品真的摆出来的节点**(建真战斗场捞 TileDecor 下的精灵), 不是重算坐标。
## ★阈值 1.22: 收进边沿的那圈最远约 1.15(半径 1.06 + 簇内散布 55px 压扁后);
##   边框密植那层到约 1.55 ⇒ 卡在两者之间。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const R_MAX := 1.22

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
	print("=== 主题装饰物不许悬空(站在平台边沿以内) ===")
	var keep: String = AT.active
	RB.DEBUG_EDIT = true
	for th in AT.ALL:
		AT.active = th
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		var decor: Node = _find_named(s._world, "TileDecor")
		_ok("[%s] ★分母: 找得到装饰容器 TileDecor" % th, decor != null)
		if decor != null:
			var A: Rect2 = RB.ARENA
			var c3: Vector3 = s._world_pos(A.position + A.size * 0.5, 0.0)
			var e3: Vector3 = s._world_pos(A.end, 0.0)
			var hx: float = absf(e3.x - c3.x)
			var hz: float = absf(e3.z - c3.z)
			var sprites: Array = _all_sprites(decor)
			var worst := 0.0
			var worst_tex := ""
			for sp in sprites:
				var p: Vector3 = (sp as Node3D).global_position
				var r: float = Vector2((p.x - c3.x) / hx, (p.z - c3.z) / hz).length()
				if r > worst:
					worst = r
					worst_tex = str((sp as Sprite3D).texture.resource_path) if (sp as Sprite3D).texture != null else "?"
			_ok("[%s] ★分母: 装饰精灵数 ≥ 12" % th, sprites.size() >= 12, "%d 个" % sprites.size())
			_ok("[%s] ★★最远的装饰离中心 ≤ %.2f 倍战场半径(超出 = 摆到岛外黑海面上, 读作悬空)" % [th, R_MAX],
				worst <= R_MAX, "最远 %.2f  (%s)" % [worst, worst_tex.get_file()])
		## ★远景只许有地形网格: 水面光柱 / 鱼群 / 气泡柱 / 海带剪影带 / 发光群 都是默认(水下)画面的,
		##   第一版这里只查了发光群 ⇒ 顶上 4 道光柱照样漏进四版, 用户又指了一次(2026-10-03)。
		var far: Node = _find_named(s._world, "FarBackdrop")
		_ok("[%s] ★分母: 找得到远景容器 FarBackdrop" % th, far != null)
		var far_sp: Array = _all_sprites(far)
		var names := {}
		for sp in far_sp:
			var tx: Texture2D = (sp as Sprite3D).texture
			var k: String = (tx.resource_path.get_file() if tx != null and tx.resource_path != "" else "(程序生成)")
			names[k] = int(names.get(k, 0)) + 1
		_ok("[%s] ★★远景里没有任何精灵(光柱/鱼群/气泡/海带带/发光群)" % th, far_sp.size() == 0, str(names))
		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 主题装饰物不悬空" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _find_named(root: Node, nm: String) -> Node:
	if root == null:
		return null
	for c in root.get_children():
		if c.name == nm:
			return c
		var r: Node = _find_named(c, nm)
		if r != null:
			return r
	return null


func _all_sprites(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is Sprite3D:
			out.append(c)
		out.append_array(_all_sprites(c))
	return out
