extends Node
## verify_crystal_line_030.gd — 030 迷你水晶球A【贯穿光束】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「该法器法力条集满时朝**最近的敌人方向**发射 **2/2/3 段**贯穿水晶光束
##   (每段间隔 CrystalSystem.LINE_SEG_GAP 秒), 每段对这条直线上
##   (中线两侧各 CrystalSystem.LINE_HALF_W 码)的**每名敌人**造成 **30/35/40 魔法伤害**
##   并施加 **1 层迷你水晶**; 敌人叠满 **3 层**水晶时被引爆,
##   受到 **14/17/20% 其最大生命值**的魔法伤害并**重置层数**。」
##
## ★这一件的结算**2026-08-14 已经从 tween 搬到 `_pending_shots`(sim 时钟)** ——
##   所以它不在 024~029 那条病上。它的缺口是**从来没有一条属于自己的门禁**:
##   `verify_staff_actives_fire` 只验到「法力条走到满并清零」, 量不到段数/贯穿/叠层/引爆。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CS := preload("res://scripts/systems/skills/crystal_system.gd")

const SEGS := [2, 2, 3]
const SEG_DMG := [30, 35, 40]
const BURST_PCT := [0.14, 0.17, 0.20]

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	u["crit"] = 0.0
	u["critDmg"] = 1.0
	u["atk_interval"] = 9999.0
	u["atk_cd"] = 9999.0
	u["mr"] = 0.0
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 030 迷你水晶球A: 2/2/3 段贯穿光束 · 半宽 %.0f 码 · 叠满 %d 层引爆 ==="
		% [CS.LINE_HALF_W, CS.MINI_STACK_MAX])
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	# ── ① ★分母 ─────────────────────────────────────────────────────
	_ok("① ★分母: 段间隔 %.1f 秒 / 半宽 %.0f 码 / 叠满 %d 层引爆"
		% [CS.LINE_SEG_GAP, CS.LINE_HALF_W, CS.MINI_STACK_MAX],
		CS.LINE_SEG_GAP > 0.0 and absf(CS.LINE_HALF_W - 55.0) < 0.01 and CS.MINI_STACK_MAX == 3)

	# ── ② ★★段数吃星级 2/2/3 —— 数它**自己排进队列的段** ────────────
	## 不量世界净血量(025 那轮量净血量把普攻算进去了, ★3 报出 1799 道)
	for si in [0, 1, 2]:
		_s._units.clear()
		_s._pending_shots.clear()
		var c: Dictionary = _mk(500.0, 400.0, "left")
		_s._units.append(c)
		_s._units.append(_mk(700.0, 400.0, "right"))
		_s._equip_sys._eq_crystal_line(c, si)
		_ok("② ★★★%d 星排了 %d 段(应 %d 段)" % [si + 1, _s._pending_shots.size(), SEGS[si]],
			_s._pending_shots.size() == SEGS[si],
			"文案: 发射 2/2/3 段贯穿水晶光束")

	# ── ③ ★★★走真入口: 三段**全部**结算掉 ───────────────────────────
	_s._units.clear()
	_s._pending_shots.clear()
	var c3: Dictionary = _mk(500.0, 400.0, "left")
	## ★目标血量拉到 200 万: 引爆是按【最大生命的百分比】算的, 血少了会被三段打死,
	##   死了就不再挨打 —— 那样量出来的「只结算了 1 段」是**测试自己造的**。
	var o3: Dictionary = _mk(760.0, 400.0, "right")
	o3["hp"] = 2000000.0
	o3["maxHp"] = 2000000.0
	_s._units.append(c3)
	_s._units.append(o3)
	var h3: float = float(o3["hp"])
	_s._equip_sys._eq_crystal_line(c3, 2)         # ★3: 3 段
	_ok("③ ★分母: 刚放完还没结算(掉血 %.0f 应为 0)" % (h3 - float(o3["hp"])),
		absf(h3 - float(o3["hp"])) < 0.01)
	## 推够 3 段 × 0.2 秒 + 余量
	for _k in range(120):
		_s._sim_step(_s.SIM_DT, false, false)
	_ok("③ 队列已排空(没有漏结算的段)", _s._pending_shots.is_empty(),
		"剩 %d 项" % _s._pending_shots.size())
	## 三段各 1 层 ⇒ 第 3 段正好叠满引爆 ⇒ 层数重置为 0
	## ★层数从单位自己的 `stacks` 字典读 —— `_add_stack` / `_consume_stacks` 写的就是这里,
	##   不是门禁自己记的账(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
	var lv3: int = int((o3["stacks"] as Dictionary).get("p2crystal", -1))
	var dealt3: float = h3 - float(o3["hp"])
	_ok("③ ★★三段正好叠满 %d 层并引爆 ⇒ 层数已重置(实测 %d 层)" % [CS.MINI_STACK_MAX, lv3],
		lv3 == 0, "三段各 1 层, 第三段触发引爆并清零")
	## 三段 40 × 1.2(小龟·不屈) = 144, 引爆 20% × 200 万 × 1.2 = 48 万 ⇒ 总量必然 ≫ 单段
	_ok("③ ★★★三段全部结算 + 叠满引爆(总伤 %.0f, 远大于单段)" % dealt3,
		dealt3 > 100000.0,
		"若只有一两百: 引爆那一下没触发(三段只叠到 2 层) —— 段数或叠层断了")

	# ── ④ ★★贯穿: 直线上【每名】敌人都挨打; 带外不挨打 ──────────────
	_s._units.clear()
	_s._pending_shots.clear()
	var c4: Dictionary = _mk(500.0, 400.0, "left")
	var a4: Dictionary = _mk(700.0, 400.0, "right")      # 线上, 近
	var b4: Dictionary = _mk(1000.0, 430.0, "right")     # 线上, 远(偏离 30 < 55)
	var out4: Dictionary = _mk(900.0, 520.0, "right")    # 偏离中线 120 码 > 55
	for x in [a4, b4, out4]:
		x["hp"] = 2000000.0
		x["maxHp"] = 2000000.0
	_s._units.append(c4)
	_s._units.append(a4)
	_s._units.append(b4)
	_s._units.append(out4)
	var ha: float = float(a4["hp"])
	var hb: float = float(b4["hp"])
	var hout: float = float(out4["hp"])
	## 只放一段(直调段函数), 免得引爆把判据搅进来
	_s._crystal_sys._crystal_line_seg(c4, 2, Vector2.RIGHT)
	_ok("④ ★★一段就打到线上【两个】敌人(近 %.0f / 远 %.0f)"
		% [ha - float(a4["hp"]), hb - float(b4["hp"])],
		ha - float(a4["hp"]) > 0.0 and hb - float(b4["hp"]) > 0.0,
		"文案明写「对这条直线上的每名敌人」—— 只打一个就不是贯穿")
	_ok("④ ★★偏离中线 120 码的没挨打(%.0f) —— 挡多了也是错" % (hout - float(out4["hp"])),
		absf(hout - float(out4["hp"])) < 0.01)

	# ── ⑤ ★★★叠层与引爆: 每段 1 层, 满 3 层引爆 14/17/20% 最大生命 ───
	_s._units.clear()
	_s._pending_shots.clear()
	var c5: Dictionary = _mk(500.0, 400.0, "left")
	_s._units.append(c5)
	for si in [0, 1, 2]:
		var o: Dictionary = _mk(700.0 + 70.0 * si, 400.0, "right")
		o["hp"] = 2000000.0
		o["maxHp"] = 2000000.0
		_s._units.append(o)
		## 前两层: 只叠不炸
		var h1: float = float(o["hp"])
		_s._equip_sys._eq_crystal_stack(c5, o, si)
		_s._equip_sys._eq_crystal_stack(c5, o, si)
		var d_two: float = h1 - float(o["hp"])
		## 第三层: 引爆
		var h2: float = float(o["hp"])
		_s._equip_sys._eq_crystal_stack(c5, o, si)
		var d_burst: float = h2 - float(o["hp"])
		if si == 0:
			_ok("⑤ ★★前两层【不】引爆(掉血 %.0f 应为 0)" % d_two, absf(d_two) < 0.01,
				"叠层本身不带伤害, 伤害在光束那一段")
		## ★不断言绝对数值: 携带者 id="basic" 走小龟·不屈(+20%), 那是产品本来的行为。
		##   判据落在**对该被动不敏感**的形状: 引爆量 ÷ 最大生命 的三个星级之比。
		var pct: float = d_burst / float(o["maxHp"])
		_ok("⑤ ★★★%d 星引爆 = 最大生命的 %.1f%%(文案 %.0f%%, ×1.2 不屈 = %.1f%%)"
			% [si + 1, pct * 100.0, BURST_PCT[si] * 100.0, BURST_PCT[si] * 120.0],
			absf(pct - BURST_PCT[si] * 1.2) < 0.005,
			"引爆按【目标最大生命】算 —— 换个血厚的目标它必须跟着变")
		## ★★这一条原来写成 `_ok(..., true, ...)` —— **恒真式, 等于没测**(024 那轮栽过同一个)。
		##   改成真去读单位 `stacks` 字典里那一格。
		var lv_after: int = int((o["stacks"] as Dictionary).get("p2crystal", -1))
		_ok("⑤ %d 星引爆后层数重置为 0(实测 %d 层)" % [si + 1, lv_after], lv_after == 0,
			"重置由 _consume_stacks + _crystal_stack_set(o, 0) 做; -1 = 这个键根本不存在")

	# ── ⑥ 伤害口径: 魔法伤害(吃魔抗) ────────────────────────────────
	_s._units.clear()
	_s._pending_shots.clear()
	var c6: Dictionary = _mk(500.0, 400.0, "left")
	var soft: Dictionary = _mk(700.0, 400.0, "right")
	soft["mr"] = 0.0
	_s._units.append(c6)
	_s._units.append(soft)
	var hs: float = float(soft["hp"])
	_s._crystal_sys._crystal_line_seg(c6, 2, Vector2.RIGHT)
	var ds: float = hs - float(soft["hp"])
	_s._units.clear()
	_s._units.append(c6)
	var hardy: Dictionary = _mk(700.0, 400.0, "right")
	hardy["mr"] = 500.0
	_s._units.append(hardy)
	var hh: float = float(hardy["hp"])
	_s._crystal_sys._crystal_line_seg(c6, 2, Vector2.RIGHT)
	var dh: float = hh - float(hardy["hp"])
	_ok("⑥ ★分母: 两边都掉血了(软 %.0f / 硬 %.0f)" % [ds, dh], ds > 0.0 and dh > 0.0)
	_ok("⑥ ★★魔抗 500 吃得明显少 ⇒ 是【魔法伤害】(软 %.0f vs 硬 %.0f)" % [ds, dh],
		dh < ds * 0.5)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 19:
		print("  [FAIL] ★断言只有 %d 条(<19) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 030 迷你水晶球A" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
