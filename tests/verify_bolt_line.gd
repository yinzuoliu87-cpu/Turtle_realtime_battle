extends Node
## verify_bolt_line.gd — 连线原语 `_bolt_line` 的门禁 (2026-09-12)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来
## ════════════════════════════════════════════════════════════════════════
## 2026-09-12 做 013~021 的 1:1 复检时, 014 深海堡垒甲的【汲取生命】
## **在实拍里完全找不到** —— 只看得到打在敌人身上的光球, 读不出"汲"这个动作。
##
## 查出来根因不在 014, 在它用的那个原语 `_bolt_line`（**全仓 24 处共用**:
## 闪电链 / 凤凰喷火 / 竹弓 / 水晶 / 忍者 / 火箭 / 星星 / 双头 / 天使 /
## 赛博 / 熔岩 / 触手 / 014 汲取…）, 它有两个毛病:
##   ① **1 像素宽的裸 GPU 线**(`PRIMITIVE_LINES`, 无贴图) —— 像素风里几乎不可见,
##      而且线宽在多数驱动上根本不可调
##   ② `albedo_color:a` **从出生就开始淡** —— memory `fb-vfx-defect-families`
##      的头一条「淡出病」: 短命特效一出生就线性淡出, 实拍读成一抹灰
##
## 改成**沿路径排一串方点 + 先满亮 hold 再淡出**, 实现搬进 `battle_vfx.bolt_line`
## (CLAUDE.md §5: 纯演出不进主文件), 主文件只留一行转发。
##
## ── 判据 ────────────────────────────────────────────────────────────────
## ⚠ 不许断言"我插的标记"或"函数存在" —— 那是插一行数一行必绿
##   (memory `fb-gate-must-measure-requirement-not-my-hook`)。
## ⇒ 这里量**真实产出的网格**: 调完 `_bolt_line` 之后从 `_world` 里把新节点捞出来,
##   读它 `ImmediateMesh` 的**顶点数**与**包围盒**, 再手推它自己的 tween 量 alpha 曲线。
##   ★分母: 距离越长点越多 —— 拿两个不同长度比, 恒定值就说明根本没按路径铺。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## 调一次 `_bolt_line`, 返回它新建的那个 MeshInstance3D(捞不到返回 null)。
func _shoot(a: Vector2, b: Vector2, col: Color) -> MeshInstance3D:
	var before: Array = []
	for c in _s._world.get_children():
		before.append(c)
	_s._bolt_line(a, b, col)
	for c in _s._world.get_children():
		if c is MeshInstance3D and not before.has(c):
			return c
	return null


func _verts(mi: MeshInstance3D) -> int:
	if mi == null or mi.mesh == null:
		return -1
	var m: ImmediateMesh = mi.mesh as ImmediateMesh
	if m == null or m.get_surface_count() < 1:
		return -1
	return int(m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 连线原语 _bolt_line: 一串方点 + 先满亮再淡出 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	var c := Vector2(700.0, 400.0)

	# ── ① 真的建出了网格, 而且是【三角形】不是线 ───────────────────────
	var short_mi: MeshInstance3D = _shoot(c, c + Vector2(120.0, 0.0), Color(1, 1, 1, 0.9))
	_ok("① ★分母: _bolt_line 真的往 _world 里加了一个网格节点", short_mi != null)
	if short_mi == null:
		_done(); return
	var vs: int = _verts(short_mi)
	_ok("① 网格有顶点(实得 %d)" % vs, vs > 0)
	## ★★已知盲区(反向验证抳出来的, 写在这里不装看不见):
	##   我曾写过一条「是 TRIANGLES 不是 LINES」, 拿顶点数能不能被 6 整除去推 ——
	##   把产品退回 `PRIMITIVE_LINES` 后顶点数一模一样, 那条**照样绿** ⇒ 恒真式。
	##   `ImmediateMesh` 没有 `surface_get_primitive_type`, 图元类型**读不回来**;
	##   读不出来就不能装作读得出 ⇒ 删掉那条。
	##   ⇒ 要是有人把 TRIANGLES 改回 LINES, **这条门禁拦不住**;
	##     拦得住的是下面四条(顶点数倍数 / 点数随路径 / 方形 / 满亮段)。
	## 每个方点 = 2 个三角 = 6 顶点
	_ok("① 顶点数是 6 的整数倍(每点两个三角形)", vs % 6 == 0, "实得 %d" % vs)

	# ── ② ★分母: 点数随路径长度走(恒定就说明没按路径铺) ─────────────────
	var long_mi: MeshInstance3D = _shoot(c, c + Vector2(600.0, 0.0), Color(1, 1, 1, 0.9))
	var vl: int = _verts(long_mi)
	_ok("② ★★长路径的点数明显多于短路径(短 %d / 长 %d 顶点)" % [vs, vl], vl > vs * 2,
		"5 倍长度应当约 5 倍点数")

	# ── ③ 方点铺满整条路径(包围盒两端都要够到) ─────────────────────────
	var aabb: AABB = long_mi.get_aabb()
	var want_m: float = 600.0 * _s.WS
	_ok("③ ★包围盒长度 ≈ 路径长度(实得 %.2f m / 应 %.2f m)" % [aabb.size.x, want_m],
		absf(aabb.size.x - want_m) < want_m * 0.25)
	_ok("③ 每个方点是正方形(厚度 ≈ 边长 %.3f m)" % BattleVfx.BOLT_DOT_M,
		absf(aabb.size.z - BattleVfx.BOLT_DOT_M) < 0.02, "实得 %.3f m" % aabb.size.z)

	# ── ④ ★★治淡出病: 满亮段 alpha 不降 ───────────────────────────────
	## 手推它自己的 tween(无头 CI 下 tween 自走不稳, CLAUDE.md §3.5)
	var mat: StandardMaterial3D = long_mi.mesh.surface_get_material(0) as StandardMaterial3D
	_ok("④ ★分母: 拿得到材质", mat != null)
	if mat != null:
		var tws: Array = _s.get_tree().get_processed_tweens()
		var tw: Tween = null
		for t in tws:
			if t is Tween and (t as Tween).is_valid():
				tw = t
		_ok("④ ★分母: 拿到了一条在跑的 tween", tw != null)
		if tw != null:
			tw.pause()
			var a0: float = mat.albedo_color.a
			tw.custom_step(BattleVfx.BOLT_HOLD_T * 0.9)
			var a_hold: float = mat.albedo_color.a
			_ok("④ ★★满亮段 alpha 不降(出生 %.3f → hold 末 %.3f) —— 一出生就淡是被治的那个病"
				% [a0, a_hold], a_hold >= a0 - 0.02)
			tw.custom_step(BattleVfx.BOLT_HOLD_T * 0.2 + BattleVfx.BOLT_FADE_T + 0.05)
			_ok("④ 淡出段跑完后 alpha 归零(实得 %.3f)" % mat.albedo_color.a,
				mat.albedo_color.a <= 0.02)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 10:
		print("  [FAIL] ★断言只有 %d 条(<10) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 连线原语" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
