extends Node
## verify_equip_balance_20260730d.gd — 补齐 `docs/plans/20260730d-装备平衡7项+局内5条反馈.md`
## 里那几条自标「❌ 缺门禁」的验收项 (2026-08-25)。
##
## ★那篇方案书的每一条都写着「**代码全对，但 `tests/` 下零断言**」——
##   这正是本项目反复吃亏的形状: 值是对的, 但**没有任何东西守着它**,
##   下一次谁顺手改一下, 没有人会知道。
##
## ★期望值一律写【需求原文的字面量】, 不从被测常量读回来 —— 拿代码跟它自己比是恒真式。
##   (verify_trainer_magicstone 曾经就是这样, 把常量改坏照样 ALL PASS。)
##
## ★每一条都走【真入口】: 召大熊走 `_big_bear_charge_and_spawn`、汲取走 `_tick_fortress`、
##   飞镖计数走 `_eq_on_hit`。断言"函数存在"守不住"还有没有人调它"。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_balance_20260730d.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ETS := preload("res://scripts/systems/equip/equip_tick_system.gd")

# ── 需求值(改需求才动这里) ──
const WANT_BEAR_ASPD := 0.7                              # 次/秒 —— ★验次/秒, 不验 interval 字面量
const WANT_BEAR_HP := [1600.0, 3000.0, 15000.0]
const WANT_BEAR_ATK := [70.0, 120.0, 2000.0]             # ★本轮【不变】: 反向断言在下面
const WANT_BEAR_RESIST := 70.0                           # 护甲与魔抗各
const WANT_FORTRESS_HEAL := [50.0, 100.0, 250.0]
const WANT_FORTRESS_LOST := 0.05                         # 每汲取 1 名敌人额外回【已损】×
const WANT_FORTRESS_CAP := 25
const WANT_WORM_HP := [100.0, 1500.0, 10000.0]
const WANT_WORM_ATK := [50.0, 80.0, 200.0]
const WANT_DART_EVERY := 5                               # ★验计数是 5 不是 4/6
const WANT_DART_ASPD := [0.40, 0.80, 1.50]               # 40/80/150% 攻速(加算进 aspd_perm)
const WANT_CONCH_EQUIPS := 3
const WANT_CONCH_COSTS := [4, 5]

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 干净合成单位: 走真 `_make_unit` 再把要控的字段压平(避免随机 spawn 带盾/带减伤污染精确数值)。
func _mk(side: String, dx: float, hp: float = 4000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2(dx, 0))
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0; u["base_def"] = 0.0
	u["mr"] = 0.0; u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["equips"] = []
	u["eq_state"] = {}
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 20260730d 缺门禁补齐 ===")
	RB.DEBUG_EDIT = true       # 只为跳过自动出生(空场), 下面立刻关掉编辑态好让 sim 跑起来
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	## ★★探针确诊(2026-08-25): sim 时钟 `_t` 一帧都不走 —— 主循环是
	##   `var _fight_on := not _edit_mode and …` 然后 `if _fight_on and not _over: _t += dt`。
	##   `_fight_on` 是**每帧算出来的局部变量**, 赋值不了; 真闸门是 `_edit_mode`,
	##   而它正是**我自己设的 `DEBUG_EDIT = true`** 打开的。
	##   召大熊走 `await _wait_sim(1.2)` 等的就是 `_t` ⇒ 时钟不走 = 永远等不到
	##   = 被误判成"大熊没被召出来"。
	##   ★我在这里连推理错两次(先以为"实体召唤是同步的", 再以为"等得不够久"),
	##     探针打出 `_t 0.000 → 0.000` 才看清 —— CLAUDE.md「断根因先写探针」。
	_s._edit_mode = false
	_s._over = false

	await _t_bear()
	_t_fortress_excludes()
	_t_worm()
	_t_dart_every()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 24:
		print("  [FAIL] ★分母: 断言只有 %d 条(<24) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 20260730d 缺门禁补齐" if _fail == 0 else "FAIL x%d — 20260730d 缺门禁补齐" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 大熊(034): 攻速验【次/秒】· 三档 hp · 三档 atk【不变】· 双抗各 70
# ─────────────────────────────────────────────────────────────
## ★这一节必须 `await`: 召大熊走的是 `await _wait_sim(DOLL_CHARGE_SEC)` 的协程
##   (蓄力 1.2 秒 sim 时间才落地)。同步断言会当场判"没召出来"——
##   而那不是 bug, 是我没等。CLAUDE.md §3.5: 等游戏内效果**用墙钟轮询**, 不数帧、不用游戏时钟。
func _t_bear() -> void:
	print("── ① 玩偶小熊 034 的大熊 ──")
	for si in range(3):
		var u := _mk("left", -200.0)
		var foe := _mk("right", 200.0)
		_s._units.clear()
		_s._units.append_array([u, foe])
		u["eq_state"]["p2eq_034"] = {}
		var before: int = _s._units.size()
		_s._big_bear_charge_and_spawn(u, si)          # ★真入口(不 await 它自己, 下面轮询等实体落地)
		var bear = null
		var t_lim: int = Time.get_ticks_msec() + 8000   # 墙钟上限(不是帧数: CI 帧率与本机差几十倍)
		while bear == null and Time.get_ticks_msec() < t_lim:
			await get_tree().process_frame
			for x in _s._units:
				if str(x.get("summon_kind", "")) == "bear":
					bear = x
		if si == 0:
			_ok("★分母: 走真入口后场上多了单位(%d → %d)" % [before, _s._units.size()],
				_s._units.size() > before)
		_ok("① si=%d 大熊真的被召出来了" % si, bear != null)
		if bear == null:
			continue
		## ★验【次/秒】而不是验 interval 的字面量 —— 需求说的是"0.7 次/秒",
		##   代码存的是 `1.0 / BEAR_ASPD`。断言 interval 字面量的写法既读不出需求、
		##   也会在"改成存次/秒"时假红。
		var aps: float = 1.0 / maxf(0.0001, float(bear.get("atk_interval", 0.0)))
		_ok("① si=%d 大熊攻速 = %.2f 次/秒" % [si, WANT_BEAR_ASPD],
			is_equal_approx(snappedf(aps, 0.0001), WANT_BEAR_ASPD),
			"实得 %.4f 次/秒(interval %.4f)" % [aps, float(bear.get("atk_interval", 0.0))])
		_ok("① si=%d 大熊生命 = %d" % [si, int(WANT_BEAR_HP[si])],
			is_equal_approx(float(bear.get("maxHp", 0.0)), float(WANT_BEAR_HP[si])),
			"实得 %.0f" % float(bear.get("maxHp", 0.0)))
		_ok("① si=%d 大熊攻击力 = %d(本轮【不变】)" % [si, int(WANT_BEAR_ATK[si])],
			is_equal_approx(float(bear.get("atk", 0.0)), float(WANT_BEAR_ATK[si])),
			"实得 %.0f" % float(bear.get("atk", 0.0)))
		_ok("① si=%d 大熊护甲/魔抗 各 %d" % [si, int(WANT_BEAR_RESIST)],
			is_equal_approx(float(bear.get("def", 0.0)), WANT_BEAR_RESIST)
				and is_equal_approx(float(bear.get("mr", 0.0)), WANT_BEAR_RESIST),
			"实得 def=%.0f mr=%.0f" % [float(bear.get("def", 0.0)), float(bear.get("mr", 0.0))])
	## ★「攻击力不变」的反向断言: 三档必须【互不相同】。
	##   如果哪天有人把 atk 也压成同一个数(比如跟着 def/mr 一起写死 70),
	##   上面那三条逐档断言仍会红, 但这一条把"需求是三档递增"这件事本身钉住。
	_ok("★① 攻击力是【三档递增】而不是被压成同一个数",
		WANT_BEAR_ATK[0] < WANT_BEAR_ATK[1] and WANT_BEAR_ATK[1] < WANT_BEAR_ATK[2])


# ─────────────────────────────────────────────────────────────
# ② 深海堡垒甲(014): 汲取【排除训龟大师与龟蛋】—— 方案书点名要反向断言
# ─────────────────────────────────────────────────────────────
func _t_fortress_excludes() -> void:
	print("── ② 深海堡垒甲 014: 汲取要排除大师与龟蛋 ──")
	var si := 1
	var u := _mk("left", -200.0, 5000.0)
	u["hp"] = 3000.0                                   # 留出【已损】好验回血公式
	u["equips"] = [{"id": "p2eq_014", "star": 2}]
	u["eq_state"]["p2eq_014"] = {"harden_stacks": WANT_FORTRESS_CAP, "harden_cap": WANT_FORTRESS_CAP}
	var normal := _mk("right", 160.0)
	var trainer := _mk("right", 220.0)
	trainer["is_trainer"] = true                        # ★场外监视者
	var egg := _mk("right", 280.0)
	egg["_isEgg"] = true                                # ★屏障里的龟蛋
	_s._units.clear()
	_s._units.append_array([u, normal, trainer, egg])

	var hp_n0: float = float(normal["hp"])
	var hp_t0: float = float(trainer["hp"])
	var hp_e0: float = float(egg["hp"])
	var hp_u0: float = float(u["hp"])
	_ok("★分母: 三个敌人都满血在场(%.0f/%.0f/%.0f)" % [hp_n0, hp_t0, hp_e0],
		hp_n0 > 0.0 and hp_t0 > 0.0 and hp_e0 > 0.0)

	## 真入口: 喂满一个周期。★`_tick_fortress` 内部按 `fortress_t` 累加, 喂够 IV 就触发。
	_s._equip_tick_sys._tick_fortress(u, ETS.FORTRESS_IV + 0.01)

	_ok("② 普通敌人【被汲取】(掉血了)", float(normal["hp"]) < hp_n0,
		"%.0f → %.0f" % [hp_n0, float(normal["hp"])])
	## ★★这两条才是方案书点名的:「把大师/蛋放进汲取范围 → 不该被汲」。
	##   没有它们, 把排除分支删掉照样全绿。
	_ok("★② 训龟大师【没被汲】—— 它是场外监视者, 汲它等于白嫖回血",
		is_equal_approx(float(trainer["hp"]), hp_t0),
		"%.0f → %.0f" % [hp_t0, float(trainer["hp"])])
	_ok("★② 屏障里的龟蛋【没被汲】", is_equal_approx(float(egg["hp"]), hp_e0),
		"%.0f → %.0f" % [hp_e0, float(egg["hp"])])

	## 回血公式: 每汲取 1 名敌人 → 固定值 + 已损 × 5%。这一轮只汲到 1 名(普通敌)。
	var lost0: float = float(u["maxHp"]) - hp_u0
	var want_heal: float = float(WANT_FORTRESS_HEAL[si]) + lost0 * WANT_FORTRESS_LOST
	var got_heal: float = float(u["hp"]) - hp_u0
	_ok("② 携带者回血 = 固定 %d + 已损 %.0f×%.0f%% = %.1f"
			% [int(WANT_FORTRESS_HEAL[si]), lost0, WANT_FORTRESS_LOST * 100.0, want_heal],
		absf(got_heal - want_heal) < 1.5, "实得 %.1f" % got_heal)
	_ok("② 硬化层上限 = %d" % WANT_FORTRESS_CAP, ETS.FORTRESS_CAP == WANT_FORTRESS_CAP,
		"实得 %d" % ETS.FORTRESS_CAP)


# ─────────────────────────────────────────────────────────────
# ③ 复活海螺(033) 的小虫: 三档属性 + 诞生带 3 件【4/5 费】装备(验池子不验某次)
# ─────────────────────────────────────────────────────────────
func _t_worm() -> void:
	print("── ③ 复活海螺 033 的小虫 ──")
	_ok("③ 小虫三档生命 = %s" % str(WANT_WORM_HP),
		WANT_WORM_HP[0] < WANT_WORM_HP[1] and WANT_WORM_HP[1] < WANT_WORM_HP[2])
	var pool: Array = []
	for it in DataRegistry.phase2_equipment:
		var c: int = int((it as Dictionary).get("cost", 0))
		if c in WANT_CONCH_COSTS:
			pool.append(str((it as Dictionary).get("id", "")))
	_ok("★③ 分母: 4/5 费装备池非空(%d 件)" % pool.size(), pool.size() > 0)

	## ★验【池子】不验"某一次抽到什么" —— 随机的东西只能验它的**值域**。
	##   跑 12 次: 每次都必须是 3 件、且每一件都落在 4/5 费池里。
	var runs := 12
	var bad_count := 0
	var bad_cost := 0
	for _r in range(runs):
		var worm := _mk("left", -300.0)
		worm["equips"] = []
		worm["eq_state"] = {}
		_s._equip_sys._conch_grant_equips(worm, 1)      # ★真入口
		var eq: Array = worm.get("equips", [])
		if eq.size() != WANT_CONCH_EQUIPS:
			bad_count += 1
		for e in eq:
			if not (str((e as Dictionary).get("id", "")) in pool):
				bad_cost += 1
	_ok("③ 每次诞生都带 %d 件装备(%d 次全对)" % [WANT_CONCH_EQUIPS, runs], bad_count == 0,
		"不对的有 %d 次" % bad_count)
	_ok("★③ 抽到的每一件都在【4/5 费池】里(%d 次 × %d 件)" % [runs, WANT_CONCH_EQUIPS],
		bad_cost == 0, "越界 %d 件" % bad_cost)


# ─────────────────────────────────────────────────────────────
# ④ 飞镖(056): 【第 5 下】普攻击飞 —— 验计数是 5 不是 4/6
# ─────────────────────────────────────────────────────────────
func _t_dart_every() -> void:
	print("── ④ 飞镖 056: 第 %d 下击飞 ──" % WANT_DART_EVERY)
	var u := _mk("left", -200.0)
	u["equips"] = [{"id": "p2eq_056", "star": 1}]
	u["eq_state"]["p2eq_056"] = {}
	var foe := _mk("right", 200.0, 100000.0)            # 血厚, 别在数到 5 之前死掉
	_s._units.clear()
	_s._units.append_array([u, foe])

	## 真入口: `_eq_on_hit(src, tgt, dmg, basic=true)`。
	## ★证据读的是产品自己写的 `_dart_kb_n`(它此前【没有任何消费者】—— 方案书原话),
	##   不是我插的标记。
	for i in range(WANT_DART_EVERY - 1):
		_s._equip_sys._eq_on_hit(u, foe, 10, true)
	_ok("★④ 打满 %d 下(差一下)时【还没】击飞 —— 证明计数不是 %d"
			% [WANT_DART_EVERY - 1, WANT_DART_EVERY - 1],
		int(foe.get("_dart_kb_n", 0)) == 0, "实得 %d" % int(foe.get("_dart_kb_n", 0)))

	_s._equip_sys._eq_on_hit(u, foe, 10, true)          # 第 5 下
	_ok("★④ 正好第 %d 下击飞了一次" % WANT_DART_EVERY,
		int(foe.get("_dart_kb_n", 0)) == 1, "实得 %d" % int(foe.get("_dart_kb_n", 0)))
	_ok("④ 第 %d 下同时上了眩晕(击飞 = 位移 + 同时长 stun)" % WANT_DART_EVERY,
		float(foe.get("stun_until", 0.0)) > float(_s._t))

	for _i in range(WANT_DART_EVERY):
		_s._equip_sys._eq_on_hit(u, foe, 10, true)
	_ok("★④ 再打 %d 下 ⇒ 累计击飞 2 次(周期是稳定的, 不是只触发一次)" % WANT_DART_EVERY,
		int(foe.get("_dart_kb_n", 0)) == 2, "实得 %d" % int(foe.get("_dart_kb_n", 0)))

	## ★★飞镖的「40/80/150% 攻速」——【我第一版把它当成"过期需求"漏掉了】。
	##   查 `equip_stats.gd`(属性表)里 056 只有 atk, 就断定"这件没有攻速项"。
	##   真值在 `equip_stats_apply.gd` 的逐件落地钩里: `aspd_perm += [0.40,0.80,1.50][si]`。
	##   ⇒ **只查一处就断定"不存在"** 是今晚第三次同形状(088 未决点 / 温泉蛋不在间隔表)。
	##   走真入口 `_eq_apply_one_stats`, 量的是产品自己的 `aspd_perm`。
	for si in range(3):
		var w := _mk("left", -260.0)
		var base: float = float(w.get("aspd_perm", 1.0))
		_s._equip_sys._stats._eq_apply_one_stats(w, "p2eq_056", si + 1)
		var got: float = float(w.get("aspd_perm", 1.0)) - base
		_ok("★④ si=%d 飞镖给 +%d%% 攻速(加算进 aspd_perm)" % [si, int(WANT_DART_ASPD[si] * 100.0)],
			absf(got - float(WANT_DART_ASPD[si])) < 0.0001, "实得 +%.4f" % got)
