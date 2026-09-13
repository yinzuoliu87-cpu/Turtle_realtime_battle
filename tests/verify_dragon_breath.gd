extends Node
## verify_dragon_breath.gd — 024 龙蛋【喷火龙】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 「装备时即拥有 3 层吐息, 之后每 EQ_TICK 秒获得 1 层; 满 3 层时清零并召唤喷火龙:
##   龙从携带者位置朝最靠近敌方质心的那名敌人拉出一条直线, 一直飞到最远敌人身后,
##   对这条直线两侧各 DragonSystem.BREATH_HALF_W 码内的单位**按火柱扫到的先后依次结算** ——
##   敌人受到(45/80/120+1×攻击力)魔法伤害并被施加 20/35/50 层灼烧; 友军回复同额生命。」
##
## ⇒ 这套门禁量四件事:
##   ① 几何: 线两侧 ±88 码内算命中, 外面不算(**挡多了也是错**)
##   ② 数值: 伤害与治疗同口径 (45/80/120 + 1×ATK), 灼烧 20/35/50, 且**吃星级**
##   ③ 友军回血那半条(很容易只做敌人那半条)
##   ④ ★★**走真入口**: 让产品自己那条路放一次龙, 看伤害到底落不落地
##
## ★★④ 是关键。伤害是靠 `tween_interval` + `tween_callback` 延时投递的 ——
##   **tween 走未钳制的真实 delta, 无头下推不动**(CLAUDE.md §3.5 / verify_pirate_hook 那次
##   连红三次的根因)。只断言「直调结算函数算得对」守不住「它到底有没有被调到」。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const DS := preload("res://scripts/systems/equip/dragon_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## ★★★用**产品自己的造单位函数** `battle_spawn._make_unit()`, 不手抄字段表。
##   手抄过两版, 两版都漏: 第一版漏 `dot_src` ⇒ `_apply_dot_stacks` 抛错**当场中止**;
##   第二版补齐了 crit/shield 又漏 `airborne` ⇒ 推 sim 时 `_tick_unit` 每步都抛,
##   一轮刷出 **2941 条**致命报错(门禁 rc=0 但致命正则判红)。
##   memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后 —— 调标准函数。
func _mk(px: float, py: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, Vector2(px, py))
	u["hp"] = 90000.0
	u["maxHp"] = 90000.0
	u["atk"] = 100.0
	u["alive"] = true
	return u

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 024 龙蛋: 喷火龙直线贯穿 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	var dr = _s._dragon_sys

	# ── ① ★分母 + 几何: ±88 码那条带 ─────────────────────────────
	_ok("① ★分母: DragonSystem 在场且半宽是 %.0f 码" % DS.BREATH_HALF_W,
		dr != null and absf(DS.BREATH_HALF_W - 88.0) < 0.01)
	var org := Vector2(500.0, 400.0)
	var dir := Vector2.RIGHT
	## ★★取样点用**绝对码数**, 不用 BREATH_HALF_W 自己算 —— 拿被测常量去算阈值是**恒真式**:
	##   把带宽改成 300 码, 用常量算的样本会跟着挪出去, 这两条照样绿(反向验证 M5 当场抓到)。
	##   文案写的是 88 码, 那就拿 44 / 87 / 128 这三个**写死的**点去卡它。
	var inside: Dictionary = _mk(800.0, 400.0 + 44.0, "right")     # 带内
	var edge_in: Dictionary = _mk(800.0, 400.0 + 87.0, "right")    # 刚好在边界内
	var outside: Dictionary = _mk(800.0, 400.0 + 128.0, "right")   # 带外(88 < 128)
	_ok("① 带内算命中", _s._on_line(org, dir, inside["pos"], DS.BREATH_HALF_W))
	_ok("① ★边界含在内(±%.0f 码刚好还算)" % DS.BREATH_HALF_W,
		_s._on_line(org, dir, edge_in["pos"], DS.BREATH_HALF_W))
	_ok("① ★★带外不算(挡多了也是错)",
		not _s._on_line(org, dir, outside["pos"], DS.BREATH_HALF_W))

	# ── ② 数值: 直调结算函数(不等演出, CLAUDE.md §3.5) ────────────
	var carrier: Dictionary = _mk(500.0, 400.0, "left")
	var foe: Dictionary = _mk(800.0, 400.0, "right")
	_s._units.append(carrier)
	_s._units.append(foe)
	var hp0: float = float(foe["hp"])
	dr._dragon_hit_enemy(carrier, foe, 2, null, null)
	var dealt: float = hp0 - float(foe["hp"])
	_ok("② ★分母: 敌人真的掉血了(实得 %.0f)" % dealt, dealt > 0.0)
	_ok("② ★★灼烧 %d 层(★3)" % 50, int(foe["dot_stacks"].get("burn", 0)) == 50,
		"实得 %d 层" % int(foe["dot_stacks"].get("burn", 0)))
	var foe1: Dictionary = _mk(800.0, 400.0, "right")
	_s._units.append(foe1)
	dr._dragon_hit_enemy(carrier, foe1, 0, null, null)
	_ok("② ★1 星是 20 层不是 50 层(层数吃星级)",
		int(foe1["dot_stacks"].get("burn", 0)) == 20,
		"实得 %d 层" % int(foe1["dot_stacks"].get("burn", 0)))

	# ── ③ 友军那半条: 回血, 且与伤害同口径 ───────────────────────
	var ally: Dictionary = _mk(700.0, 400.0, "left")
	ally["hp"] = 1000.0
	_s._units.append(ally)
	var ah0: float = float(ally["hp"])
	dr._dragon_heal_ally(carrier, ally, 2)
	var healed: float = float(ally["hp"]) - ah0
	_ok("③ ★★友军回血(很容易只做敌人那半条) —— 实得 %.0f" % healed, healed > 0.0)
	## 文案: 伤害与治疗**同口径** (45/80/120 + 1×ATK); ★3 = 120 + 100 = 220
	_ok("③ 回血 = 120 + 1×攻击力 = 220(与伤害同口径)", absf(healed - 220.0) < 1.0,
		"实得 %.1f" % healed)

	# ── ④ ★★★走真入口: 产品自己那条路放一次龙, 伤害落不落地 ──────
	## 伤害是 `tween_interval` + `tween_callback` 延时投递的; tween 走**未钳制的真实 delta**,
	## 无头下推不动(CLAUDE.md §3.5)。这一条就是要把「到底有没有被调到」量出来。
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	var e2: Dictionary = _mk(760.0, 400.0, "right")
	var a2: Dictionary = _mk(640.0, 400.0, "left")
	a2["hp"] = 500.0
	_s._units.append(c2)
	_s._units.append(e2)
	_s._units.append(a2)
	var ah2: float = float(a2["hp"])
	var h0: float = float(e2["hp"])
	## ★★这一组必须**让 sim 真的跑起来** —— 前面为了做确定性直调把 process 关了,
	##   关着的话 `_dragon_sys.tick(dt)` 根本不会被调, 测出来的 0 是**我的测试**的 0,
	##   不是产品的 0(第一版就栽在这里, 差点把已经修好的东西再判一次红)。
	_s.process_mode = Node.PROCESS_MODE_ALWAYS
	## ★★还得关掉编辑态: `DEBUG_EDIT=true` ⇒ `battle_spawn` 把 `_edit_mode` 置真 ⇒
	##   `_sim_step` 里的 `_fight_on` 把**整组 tick**(含 _dragon_sys.tick)全门住。
	##   不关的话这一条测的是「编辑态下不结算」, 不是「产品路径通不通」。
	_s._edit_mode = false
	_s._equip_sys._eq_dragon_breath(c2, 2)
	## ★★不靠墙钟, **确定性地推 sim** —— `_dragon_sys.tick` 就在 `_sim_step` 的 `_fight_on` 块里,
	##   直接推它 N 步, 既走真路径又不看帧率脸色(墙钟版实测 4 秒只推进了 0.35 游戏秒)。
	for _k in range(420):        # 420 × 1/60 = 7 游戏秒 > 前摇 0.55 + 飞行 ≤2.6
		_s._sim_step(_s.SIM_DT, false, false)
	var real_dealt: float = h0 - float(e2["hp"])
	_ok("④ ★★★走真入口(_eq_dragon_breath)后, 敌人**确实掉血了**(实得 %.0f)" % real_dealt,
		real_dealt > 0.0,
		"若为 0: 伤害埋在 tween 里而 tween 在无头下推不动 —— 就是 §3.5 那条老病")
	## ★这条原来写成 `_ok(..., true, ...)` —— **恒真式, 等于没测**。换成量真入口上友军的血。
	_ok("④ ★★★同一条路上友军**确实回血了**(实得 %.0f)" % (float(a2["hp"]) - ah2),
		float(a2["hp"]) > ah2,
		"友军那半条最容易漏 —— 它和伤害走同一条队列, 断了就一起断")
	_ok("④ 队列已排空(没有漏结算的项)", _s._dragon_sys._pending.is_empty(),
		"剩 %d 项" % _s._dragon_sys._pending.size())

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 12:
		print("  [FAIL] ★断言只有 %d 条(<12) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 024 喷火龙" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
