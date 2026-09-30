extends Node
## verify_gear_egg_035_036.gd — 035 黄铜齿轮 + 036 温泉蛋的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 【035 黄铜齿轮】「每 `GEAR_IV`(6) 秒获得 **1/2/3** 枚深海币。」
##
## 【036 温泉蛋】「每秒回复 2/5/10 + 0.3/0.8/1.2% 最大生命值;
##   并持续获得孵化进度(每 EQ_TICK 秒 +`EGG_PER_CYCLE`(5)、敌方死亡 +`EGG_ON_FOE_DEATH`(10)、
##   己方死亡 +`EGG_ON_ALLY_DEATH`(15)、造成伤害 ×`EGG_DMG_RATIO`(0.1)、承受伤害 ×同),
##   进度满 `EGG_FULL`(100) 获得 1 点临时等级(**上限 +3/4/5**, 每级 +`EGG_LV_GROWTH`(5)% 基础属性,
##   同一局对局内跨战场保留、开新对局才重置);
##   孵满后为全队均摊 **300/400/600** 点护盾(一次)—— 分摊名单**不含龟蛋与训龟大师**。」
##
## ★两件都**原来没有门禁**。结算层查下来都健康(全在 sim 时钟上)。
## ★本轮顺手修了四处「同一个数存两份」: 035 扣周期写死 `- 6.0`(常量叫 `GEAR_IV`);
##   036 的血量档写死 `0.05`(同一段另外三档都读 `EGG_LV_GROWTH`)、
##   进度回钳写死 `100.0`(常量叫 `EGG_FULL`)、攻速档的 `0.02` **连常量都没有**。
##   数值一个没动, 只是让它们变成同一份。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ET := preload("res://scripts/systems/equip/equip_tick_system.gd")

const GEAR_COINS := [1, 2, 3]
const EGG_CAP := [3, 4, 5]
const EGG_SHIELD := [300.0, 400.0, 600.0]

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
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 035 黄铜齿轮(每 %.0f 秒产币) + 036 温泉蛋(孵满 %.0f 进度 +1 级) ===" % [ET.GEAR_IV, ET.EGG_FULL])
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	var ets = _s._equip_tick_sys

	# ══════════════ 035 黄铜齿轮 ══════════════
	_ok("① ★分母: 产币周期 %.0f 秒" % ET.GEAR_IV, absf(ET.GEAR_IV - 6.0) < 0.01)
	for si in [0, 1, 2]:
		_s._units.clear()
		var c: Dictionary = _mk(500.0, 400.0, "left")
		c["equips"] = [{"id": "p2eq_035", "star": [1, 2, 3][si]}]
		c["eq_state"] = {}
		_s._units.append(c)
		## ★★ 2026-09-29: 齿轮产的币不再直接写 meta, 而是进**本场账本** `gear_minted()`,
		##   结算时随 `_last_reward` 一起进钱包 —— 奇械铸币本来就这么走, 齿轮是唯一绕过去的。
		##   绕过去的后果: **结算屏少算**(真机受控对照 屏显 +30 / 存档 +34)。
		##   ⇒ 这几条改成量**产品自己的账本**。⚠ 这不是放宽:
		##   钱包那一步由 `verify_tick_equips_exact` 与冒烟测试走真结算路径守着。
		ets.reset_match()
		var before: int = int(ets.gear_minted())
		ets._tick_gear(c, ET.GEAR_IV - 0.2)
		_ok("① ★分母(%d 星): 差 0.2 秒时还没到账(+%d)"
			% [si + 1, int(ets.gear_minted()) - before],
			int(ets.gear_minted()) == before,
			"卡住「每 %.0f 秒」那个数" % ET.GEAR_IV)
		ets._tick_gear(c, 0.3)
		var got: int = int(ets.gear_minted()) - before
		_ok("① ★★★%d 星: 满周期进 %d 枚深海币(应 %d)" % [si + 1, got, GEAR_COINS[si]],
			got == GEAR_COINS[si],
			"这条量 `gear_minted()` —— 产品自己的本场账本(钱包由结算路径守)")
	## ★★扣周期必须读 GEAR_IV 而不是写死的 6.0 —— 连喂两个周期, 第二枚必须准时到
	_s._units.clear()
	var c2: Dictionary = _mk(500.0, 400.0, "left")
	c2["equips"] = [{"id": "p2eq_035", "star": 3}]
	c2["eq_state"] = {}
	_s._units.append(c2)
	ets.reset_match()
	var b2: int = int(ets.gear_minted())
	for _k in range(2):
		ets._tick_gear(c2, ET.GEAR_IV + 0.01)
	_ok("① ★★连喂两个周期进两次账(+%d, 应 %d)"
		% [int(ets.gear_minted()) - b2, GEAR_COINS[2] * 2],
		int(ets.gear_minted()) - b2 == GEAR_COINS[2] * 2,
		"扣周期原来写死 `- 6.0`, 与常量 GEAR_IV 是两份")
	## ★右队不产币(文案口径: 深海币是玩家侧 meta 货币)
	_s._units.clear()
	var cr: Dictionary = _mk(500.0, 400.0, "right")
	cr["equips"] = [{"id": "p2eq_035", "star": 3}]
	cr["eq_state"] = {}
	_s._units.append(cr)
	var b3: int = int(gs.meta_deepsea_coins)
	ets._tick_gear(cr, ET.GEAR_IV + 0.01)
	_ok("① ★★右队(敌方)携带者**不**产币(+%d 应 0)" % (int(gs.meta_deepsea_coins) - b3),
		int(gs.meta_deepsea_coins) == b3)

	# ══════════════ 036 温泉蛋 ══════════════
	_ok("② ★分母: 满 %.0f 进度 +1 级 / 每级 +%.0f%% 基础属性 / 周期 +%.0f / 敌死 +%.0f / 己死 +%.0f / 伤害 ×%.2f"
		% [ET.EGG_FULL, ET.EGG_LV_GROWTH * 100.0, ET.EGG_PER_CYCLE,
		   ET.EGG_ON_FOE_DEATH, ET.EGG_ON_ALLY_DEATH, ET.EGG_DMG_RATIO],
		absf(ET.EGG_FULL - 100.0) < 0.01 and absf(ET.EGG_LV_GROWTH - 0.05) < 0.001
			and absf(ET.EGG_PER_CYCLE - 5.0) < 0.01 and absf(ET.EGG_ON_FOE_DEATH - 10.0) < 0.01
			and absf(ET.EGG_ON_ALLY_DEATH - 15.0) < 0.01 and absf(ET.EGG_DMG_RATIO - 0.1) < 0.001)

	# ── ② ★★★等级上限吃星级 3/4/5, 且每级 +5% 基础属性 ────────────────
	for si in [0, 1, 2]:
		_s._units.clear()
		var e: Dictionary = _mk(500.0, 400.0, "left")
		e["has_egg"] = true
		e["equips"] = [{"id": "p2eq_036", "star": [1, 2, 3][si]}]
		e["eq_state"] = {"p2eq_036": {"egg_cap": EGG_CAP[si], "incub_shield": EGG_SHIELD[si]}}
		_s._units.append(e)
		var atk0: float = float(e["base_atk"])
		var hp0: float = float(e["maxHp"])
		## 喂远超上限的进度 —— 等级必须停在 cap 上
		ets._egg_add_progress(e, ET.EGG_FULL * float(EGG_CAP[si] + 3))
		var lv: int = int(e["eq_state"]["p2eq_036"].get("egg_levels", -1))
		_ok("② ★★★%d 星: 喂 %d 级的进度, 等级停在 %d(上限 %d)"
			% [si + 1, EGG_CAP[si] + 3, lv, EGG_CAP[si]],
			lv == EGG_CAP[si],
			"文案: 上限 +3/4/5")
		var want_atk: float = atk0 * (1.0 + ET.EGG_LV_GROWTH * float(EGG_CAP[si]))
		_ok("② ★★%d 星: 基础攻击 %.2f → %.2f(应 %.2f = ×(1+%.2f×%d), 线性非复利)"
			% [si + 1, atk0, float(e["base_atk"]), want_atk, ET.EGG_LV_GROWTH, EGG_CAP[si]],
			absf(float(e["base_atk"]) - want_atk) < 0.01)
		var want_hp: float = hp0 * (1.0 + ET.EGG_LV_GROWTH * float(EGG_CAP[si]))
		_ok("② ★★%d 星: 最大生命 %.0f → %.0f(应 %.0f) —— 血量档原来写死 0.05 而不是读常量"
			% [si + 1, hp0, float(e["maxHp"]), want_hp],
			absf(float(e["maxHp"]) - want_hp) < 1.0)

	# ── ③ ★★★孵满 → 全队均摊护盾一次, 名单不含龟蛋与训龟大师 ──────────
	_s._units.clear()
	var host: Dictionary = _mk(500.0, 400.0, "left")
	host["has_egg"] = true
	host["shield"] = 0.0
	host["equips"] = [{"id": "p2eq_036", "star": 3}]
	host["eq_state"] = {"p2eq_036": {"egg_cap": EGG_CAP[2], "incub_shield": EGG_SHIELD[2]}}
	var mate: Dictionary = _mk(560.0, 400.0, "left")
	mate["shield"] = 0.0
	var egg_base: Dictionary = _mk(200.0, 400.0, "left")
	egg_base["shield"] = 0.0
	egg_base["_isEgg"] = true
	var trainer: Dictionary = _mk(240.0, 400.0, "left")
	trainer["shield"] = 0.0
	trainer["is_trainer"] = true
	var foe: Dictionary = _mk(800.0, 400.0, "right")
	foe["shield"] = 0.0
	for x in [host, mate, egg_base, trainer, foe]:
		_s._units.append(x)
	ets._egg_add_progress(host, ET.EGG_FULL * float(EGG_CAP[2]))
	_ok("③ ★分母: 已孵满 %d 级" % int(host["eq_state"]["p2eq_036"].get("egg_levels", -1)),
		int(host["eq_state"]["p2eq_036"].get("egg_levels", -1)) == EGG_CAP[2])
	var s_host: float = float(host["shield"])
	var s_mate: float = float(mate["shield"])
	_ok("③ ★★★孵满给了护盾(携带者 %.0f / 队友 %.0f)" % [s_host, s_mate],
		s_host > 0.0 and s_mate > 0.0,
		"文案: 孵满后为全队均摊 300/400/600 点护盾(一次)")
	_ok("③ ★★是【均摊】: 携带者与队友拿到的一样多(%.1f vs %.1f)" % [s_host, s_mate],
		absf(s_host - s_mate) < 0.5)
	_ok("③ ★★★分摊名单**不含龟蛋**(蛋身上护盾 %.0f 应 0)" % float(egg_base["shield"]),
		absf(float(egg_base["shield"])) < 0.01)
	_ok("③ ★★★分摊名单**不含训龟大师**(大师身上护盾 %.0f 应 0)" % float(trainer["shield"]),
		absf(float(trainer["shield"])) < 0.01)
	_ok("③ ★★敌方不分(敌人身上护盾 %.0f 应 0)" % float(foe["shield"]),
		absf(float(foe["shield"])) < 0.01)
	## ★★★只给一次。这一条第一版是**恒真式**: 直接再喂进度不会再发, 但那是被
	##   **等级上限**那道闸挡住的(`egg_levels < cap` 为假 ⇒ 循环体根本不进),
	##   跟 `incub_given` 一点关系没有 —— 反向验证把 `incub_given` 改成 false 照样绿。
	##   要真的测到「只给一次」这条闸, 必须**先把上限那道闸让开**(把 cap 抬高),
	##   让循环能再跑进去, 再看护盾发不发。
	var s2: float = float(mate["shield"])
	(host["eq_state"]["p2eq_036"] as Dictionary)["egg_cap"] = EGG_CAP[2] + 3
	ets._egg_add_progress(host, ET.EGG_FULL * 3.0)
	_ok("③ ★分母: 抬高上限后等级确实又涨了(%d 级 > %d)"
		% [int(host["eq_state"]["p2eq_036"].get("egg_levels", -1)), EGG_CAP[2]],
		int(host["eq_state"]["p2eq_036"].get("egg_levels", 0)) > EGG_CAP[2],
		"上限那道闸已让开 ⇒ 下面测到的才是 incub_given 这道闸")
	_ok("③ ★★★护盾**只给一次**(队友护盾 %.0f → %.0f 不变)"
		% [s2, float(mate["shield"])],
		absf(float(mate["shield"]) - s2) < 0.01,
		"文案明写「(一次)」; 这一条守的是 incub_given")

	# ── ④ ★★进度到不了 EGG_FULL 就不该升级(卡住那个 100) ────────────────
	_s._units.clear()
	var e4: Dictionary = _mk(500.0, 400.0, "left")
	e4["has_egg"] = true
	e4["equips"] = [{"id": "p2eq_036", "star": 3}]
	e4["eq_state"] = {"p2eq_036": {"egg_cap": 5, "incub_shield": 600.0}}
	_s._units.append(e4)
	ets._egg_add_progress(e4, ET.EGG_FULL - 1.0)
	_ok("④ ★★差 1 点进度时还是 %d 级(应 0)"
		% int(e4["eq_state"]["p2eq_036"].get("egg_levels", -1)),
		int(e4["eq_state"]["p2eq_036"].get("egg_levels", 0)) == 0,
		"卡住 EGG_FULL = %.0f 这个数" % ET.EGG_FULL)
	ets._egg_add_progress(e4, 2.0)
	_ok("④ ★★再加 2 点就满 %.0f ⇒ 升到 %d 级(应 1)"
		% [ET.EGG_FULL, int(e4["eq_state"]["p2eq_036"].get("egg_levels", -1))],
		int(e4["eq_state"]["p2eq_036"].get("egg_levels", 0)) == 1)
	## ★没有蛋的人喂进度不该有反应
	var nope: Dictionary = _mk(700.0, 400.0, "left")
	nope["eq_state"] = {"p2eq_036": {"egg_cap": 5}}
	_s._units.append(nope)
	ets._egg_add_progress(nope, ET.EGG_FULL * 3.0)
	_ok("④ ★★没有 has_egg 的单位喂进度无反应(%d 级)"
		% int((nope["eq_state"]["p2eq_036"] as Dictionary).get("egg_levels", 0)),
		int((nope["eq_state"]["p2eq_036"] as Dictionary).get("egg_levels", 0)) == 0)

	# ══════════════ ⑤ GEAR_COIN_SPIN —— 头顶那枚金币真的在转、在飘 ══════════════
	#
	# 由来（用户 2026-09-29 14:46）：「1费器械的那个加深海币的装备，这个装备特效怎么变了，
	#   你给我改了？**我之前的弹出金币旋转的动画呢**」。
	# ★查下来链路是通的（贴图在 / `coin_pop` 在调 / `_tick_coin_fx` 在 `_render_step` 里），
	#   但**没有任何判据量过它** —— 所以我答不上那句话，只能说「看着是通的」。
	#   这一节就是把它变成量得到的。
	#
	# ★★为什么必须分成【建出来】和【动起来】两段：
	#   `coin_pop()` 只负责**建**精灵并塞进 `battle._coin_fx`；
	#   转（`spr.frame = int(age*COIN_FPS) % COIN_FRAMES`）与飘（`COIN_RISE * age/life`）
	#   全在 `battle_render._tick_coin_fx()` 里。
	#   ⇒ 只断言「金币出来了」会放过用户描述的那个形状：**弹出来了但不转不飘**。
	#
	# ★这一节不等演出 tween（本仓 §3.5：数值测试不许依赖 tween 跑完），
	#   而是自己推 `battle._t` 再手调 `_tick_coin_fx()` —— 一步喂一步，帧内跃迁抓得住。
	var cvfx = _s._vfx
	var crd = _s._render
	_s._coin_fx.clear()
	var cu: Dictionary = _mk(300.0, 300.0, "left")
	cu["equips"] = [{"id": "p2eq_035", "star": 3}]
	cu["eq_state"] = {}
	_s._units.clear(); _s._units.append(cu)
	var minted0: int = ets.gear_minted()
	## 推过一个完整产币周期（一步一喂，不靠等帧）
	var cn: int = 0
	while cn < 200 and ets.gear_minted() == minted0:
		ets._tick_gear(cu, 0.05)
		cn += 1
	var coins: int = ets.gear_minted() - minted0
	_ok("⑤ ★分母: 产币真的发生了(否则下面全是空检查) —— 3★ 应得 3 枚, 实得 %d 枚(推了 %d 步)"
		% [coins, cn], coins == 3)
	_ok("⑤ ★★GEAR_COIN_SPIN: 头顶金币**建出来了** —— 每枚币一个精灵(实得 %d 个)"
		% _s._coin_fx.size(), _s._coin_fx.size() == coins,
		"coins=%d fx=%d" % [coins, _s._coin_fx.size()])
	var in_tree: int = 0
	for f in _s._coin_fx:
		var sp0 = f.get("spr", null)
		if is_instance_valid(sp0) and sp0.get_parent() == _s._world:
			in_tree += 1
	_ok("⑤ ★★金币真的挂在 `_world` 下(建了没进场景树 = 屏上什么都没有) —— %d/%d"
		% [in_tree, _s._coin_fx.size()], in_tree == _s._coin_fx.size())
	## ── 转：一步一采，收集 frame 的不同取值 ──
	var frames_seen: Dictionary = {}
	var y_lo: float = 1.0e9
	var y_hi: float = -1.0e9
	var t_base: float = _s._t
	var steps: int = 0
	while steps < 60 and _s._coin_fx.size() > 0:
		_s._t = t_base + float(steps) * (cvfx.COIN_LIFE / 40.0)
		## ★★★走**产品自己那条每帧入口** `_render_step()`, 不直接调 `_tick_coin_fx()`。
		##   由来(2026-09-30 反向验证当场拿住): 第一版这里写的是 `crd._tick_coin_fx()`,
		##   于是把 `_render_step` 里那一行调用**整行拿掉**, 门禁竟然 **0 条红** ——
		##   它量的是我自己的调用, 不是产品的接线(memory `fb-gate-must-measure-requirement-not-my-hook`
		##   / `fb-verify-must-run-the-real-path`)。而那正好就是用户描述的形状:
		##   **金币弹出来了但不转** ⇒ 这条洞刚好开在要守的那一点上。
		crd._render_step(0.0, false, false)
		steps += 1
		for f2 in _s._coin_fx:
			var sp2 = f2.get("spr", null)
			if is_instance_valid(sp2) and sp2.visible:
				frames_seen[int(sp2.frame)] = true
				y_lo = minf(y_lo, sp2.position.y)
				y_hi = maxf(y_hi, sp2.position.y)
	_ok("⑤ ★分母: 真的采到样本(采了 %d 步 / 见到 %d 个不同帧号)" % [steps, frames_seen.size()],
		steps >= 10 and frames_seen.size() > 0)
	## ★判据是「转过多少个不同帧」而不是「frame 变了」—— 变一次也叫变, 那放得过
	##   「只在生成那一刻算了一次帧号」这种假转。贴图 12 帧, 一个生命周期该扫过大半。
	_ok("⑤ ★★★GEAR_COIN_SPIN: 金币**在转** —— 一个生命周期里扫过 %d 个不同帧号(贴图共 %d 帧, 要求 ≥4)"
		% [frames_seen.size(), cvfx.COIN_FRAMES], frames_seen.size() >= 4,
		"见到的帧号: %s" % str(frames_seen.keys()))
	_ok("⑤ ★★★GEAR_COIN_SPIN: 金币**在往上飘**(高度差 %.3f m, 要求 > 0.05)"
		% (y_hi - y_lo), (y_hi - y_lo) > 0.05,
		"y %.3f → %.3f · COIN_RISE=%.2f" % [y_lo, y_hi, cvfx.COIN_RISE])
	_ok("⑤ ★寿命到了自己收掉(不许留在场上) —— 剩 %d 个" % _s._coin_fx.size(),
		_s._coin_fx.size() == 0)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 30:
		print("  [FAIL] ★断言只有 %d 条(<30) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 035 黄铜齿轮 + 036 温泉蛋" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
