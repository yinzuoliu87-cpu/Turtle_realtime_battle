extends Node
## verify_equip_onhit_batch2.gd — 新装备【批②·命中/普攻类 10 件】逐件焊死 + R1/R4 门禁
##
## 方案书: docs/plans/20260804-新装备35件效果.md (用户拍板 U1=C 按钩子分 3 批)
## 覆盖: 060 061(on-dodge) · 067 073 074 075 076 083(on-hit) · 078(on-basic-attack) · 068(on-kill)
##
## ★本文件的规矩(照抄批① verify_equip_periodic_batch1 的口径, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】, 不用随机 spawn 的敌 —— 随机敌带盾/flat_dr/未播种 RNG
##     会让精确数值在 CI 上偶发红(memory: fb-ci-vs-local-divergence)。
##   · 合成单位坐标放在 ARENA 【内】—— 放外面会被钳到同一点。
##   · 需求字面值【直接写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 触发一律走【真入口】(_eq_on_hit / _eq_on_dodge / _eq_on_basic_attack / _eq_on_kill),
##     并且至少各有一条【经中央伤害管线 _apply_damage_from 的端到端】断言 ——
##     memory fb-verify-must-run-the-real-path:「断言函数存在」守不住「还有没有人调它」。
##   · 概率类(078)【播种 RNG】测经验频率, 不靠"跑几次看看"(那在 CI 上必然偶发红)。
##   · 不依赖任何演出 tween / 弹道飞完(CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##   · 每条断言都打印实测值与期望值; 每组带一条【分母】断言(N=0 是空检查不是通过)。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_onhit_batch2.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位: 放 ARENA 中心附近, 清掉一切会干扰精确数值的减伤/护盾/暴击。
## ★携带者一律用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%,
##   拿 basic 当携带者去验"22 点加成"会量到 26(批① 与 20260801 那两份门禁都实测过这个坑)。
func _mk(id: String, side: String, off: Vector2, hp: float = 1000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["corrode_stacks"] = 0
	u["corrode_tier"] = 0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


## 装上一件装备(只挂条目, 不跑属性管线 —— 属性会污染"效果加了多少"的量测)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	return u


## 取【已剥注释】源码里某个函数的函数体(到下一个顶格 func 为止)。
func _fn_body(code: String, header: String) -> String:
	var i: int = code.find(header)
	if i < 0:
		return ""
	var e: int = code.find("\nfunc ", i + 1)
	return code.substr(i, (e - i) if e > i else -1)


func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 新装备批②·命中/普攻类 10 件 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_dispatch()
	# ★067/068 两件已由用户整条重写(2026-08-05 §0.5): 067 猎人的酒囊→毒药瓶(周期投瓶 +
	#   普攻叠中毒 + 中毒者治疗/护盾减半)、068 万灵龟血→深海气压罐(受伤充能 → 法力护盾 + 法力激光)。
	#   旧效果函数 _eq_hunter_flask / 旧的 on-kill 分支均已删除 ⇒ 这两段用例搬到
	#   tests/verify_eq_potion_batch.gd(逐件重写, 含分发纪律那一组)。
	# ★073/074/075/076 四件已由用户整条重写(2026-08-05 §0.5),
	#   旧效果与旧效果函数均已删除 ⇒ 这四段用例搬到 tests/verify_eq_bow_batch.gd。
	#   这里不是"删了没人接" —— 新门禁逐件重写了它们, 包括分发纪律那一组。
	_t078_double_barrel()
	_t083_tide_rapier()
	_t_r4_no_chain()
	_t_r1_tide_magnitude()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 新装备批②命中普攻类" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ⓪ 分发纪律: 10 件各自落在【已有的】那个钩子上, 没有新增分发口
#    (方案书 R3: 分发口不要新增)
# ─────────────────────────────────────────────────────────────
func _t_dispatch() -> void:
	print("── ⓪ 分发纪律与接线 ──")
	# ★读源码找 match 分支 —— 但先剥掉注释, 否则会命中我自己写的说明文字
	#   (20260801 / 批① 两份门禁的作者都因此吃过亏)。
	var code: String = _strip("res://scripts/systems/equip/equip_system.gd")
	var groups := {
		# ★073/074/076 的触发时机已从【命中】改成【普攻】(2026-08-05 §0.5 定稿,
		#   用户原文都写"每次普攻") ⇒ 它们在下面那一行。075 的【距离增伤】仍在 on-hit。
		# ★067 也不在这里了: 它被用户重做成【毒药瓶】(周期投瓶 + 普攻叠中毒),
		#   落点是 fire_equip_effect 与 _eq_on_basic_attack, 由 tests/verify_eq_potion_batch.gd 守。
		"func _eq_on_hit": ["p2eq_075", "p2eq_083"],
		"func _eq_on_basic_attack": ["p2eq_073", "p2eq_074", "p2eq_076", "p2eq_078"],
		# ★_eq_on_dodge 这一行整条删掉: 060/061 已被用户重做(060 → 7 秒开伞周期,
		#   061 → on-hit 破损), 都不再挂闪避钩。现在挂闪避钩的是 062 螳螂虾钳,
		#   由 tests/verify_eq_spirit_batch.gd 守。
		# ★_eq_on_kill 这一行也整条删掉: 068 已被用户重做成【深海气压罐】(受伤充能 →
		#   法力护盾 + 法力激光), 不再挂击杀钩。由 tests/verify_eq_potion_batch.gd 守。
	}
	var total := 0
	for hdr in groups:
		var body: String = _fn_body(code, str(hdr))
		_ok("⓪ ★分母: %s 的函数体非空(%d 字符) —— 空串会让下面那条恒真" % [str(hdr), body.length()],
			body.length() > 200, "len=%d" % body.length())
		var miss: Array = []
		var dup: Array = []
		for iid in groups[hdr]:
			total += 1
			var cnt: int = body.count("\"%s\"" % iid)
			if cnt == 0:
				miss.append(iid)
			elif cnt > 1:
				dup.append("%s×%d" % [iid, cnt])
		_ok("⓪ %s 挂着 %s" % [str(hdr), str(groups[hdr])], miss.is_empty(), "缺 %s" % str(miss))
		_ok("⓪ %s 里没有重复 id" % str(hdr), dup.is_empty(), str(dup))
	_ok("⓪ ★分母: 本批一共查了 %d 件(应为 6 —— 060/061 见 verify_eq_spirit_batch, 067/068 见 verify_eq_potion_batch)" % total, total == 6, "total=%d" % total)
	# ★★接线: 这四个钩子【真的被中央管线调】—— 否则上面全绿而游戏里一件都不触发
	var dmg_src: String = _strip("res://scripts/scenes/battle/battle_damage.gd")
	var rb_src: String = _strip("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⓪ ★★接线: battle_damage 的普攻/技能路真的调 _eq_on_hit",
		dmg_src.contains("_eq_on_hit(src, u, dmg)"), "len=%d" % dmg_src.length())
	_ok("⓪ ★★接线: battle_damage 的闪避分支真的调 _eq_on_dodge",
		dmg_src.contains("_eq_on_dodge(u)"))
	_ok("⓪ ★★接线: 主场景的普攻真的调 _eq_on_basic_attack",
		rb_src.contains("_eq_on_basic_attack(u, tgt)"), "len=%d" % rb_src.length())
	_ok("⓪ ★★接线: 主场景的 _kill 真的调 _eq_on_kill",
		rb_src.contains("_eq_on_kill(killer, u)"))
	# 加伤/额外真伤五件共用同一个投递口 —— 不许各写各的扣血(1 处定义 + 5 处调用)
	_ok("⓪ 加伤/额外真伤五件都走同一个 _eq_bonus_hit 投递口(不各写各的)",
		code.count("_eq_bonus_hit(") == 2,
		"出现 %d 次(期望 2 = 1 定义 + 1 调用: 083。067 与弓箭四件已由用户重写, 075 改从 eq_bow_batch.gd 里调这个投递口)" % code.count("_eq_bonus_hit("))
	# 六件 on-hit 的效果体都外迁成具名函数, 且分派写成 `"id": _fn(` —— 少一条,
	# tooltip_number_audit 就拿不到函数锚点, 数值会被判"远处命中"
	var hit_body: String = _fn_body(code, "func _eq_on_hit")
	# ★弓箭四件不在这里: 它们的效果本体搬到了 EqBowBatch(分派写成 `"id": _bow_sys.xxx(`),
	#   不再是本文件里的 `_eq_*` 具名函数 ⇒ 改由 tests/verify_eq_bow_batch.gd 守。
	var fns := {"p2eq_083": "_eq_tide_rapier"}
	var nowire: Array = []
	for k in fns:
		if not hit_body.contains("\"%s\": %s(" % [k, fns[k]]):
			nowire.append("%s→%s" % [k, fns[k]])
		if not code.contains("func %s(" % fns[k]):
			nowire.append("缺 func %s" % fns[k])
	_ok("⓪ 六件 on-hit 的分派写成 \"id\": _fn( 且函数真的存在(tooltip 审计靠这个锚点)",
		nowire.is_empty(), str(nowire))
# ★2026-08-05: 这一段守的是【已被用户整条重做掉】的旧效果, 随效果一并删除。
#   新效果与它的门禁在 tests/verify_eq_spirit_batch.gd(灵物 5 件·§0.5 定稿)。


# ─────────────────────────────
# ★067/068 两件的用例已搬走
#   用户 2026-08-05 逐件亲手重写了这两件(方案书 §0.5 定稿):
#   067 猎人的酒囊(打猎物额外真伤) → 【毒药瓶】每 6 秒投瓶 + 普攻叠中毒 + 中毒者治疗/护盾减半;
#   068 万灵龟血(击杀永久+攻) → 【深海气压罐】受伤充能 → 法力护盾 + 2000 码法力激光。
#   新效果与它们的门禁在 tests/verify_eq_potion_batch.gd。
#   ★是整段删而不是"把旧断言改成新数字" —— 旧用例量的是旧机制
#   (如"只对【猎物】生效"), 改数字保不住它们。


# ─────────────────────────────
# ★弓箭四件(073 074 075 076)的用例已搬走
#   用户 2026-08-05 逐件亲手重写了这四件(方案书 §0.5 定稿), 旧效果
#   (打健康目标加伤 / 暴击追真伤 / 距离分档加伤 / 暴击喂腐蚀)整段作废。
#   新效果与它们的门禁在 tests/verify_eq_bow_batch.gd。
#   ★是整段删而不是"把旧断言改成新数字" —— 旧用例量的是旧机制
#   (如"满血目标才加伤"), 改数字保不住它们, 只会留下测不到东西的空断言。


# ─────────────────────────────────────────────────────────────
# 078 双管贝壳枪: 普攻发出时 25/35/50% 概率追加一发(伤害 40/50/60%)
# ★概率类【播种 RNG】测经验频率 —— 不靠"跑几次看看"(CI 必然偶发红)
# ─────────────────────────────────────────────────────────────
const TRIALS := 1000
const SEED := 20260805


func _t078_double_barrel() -> void:
	print("── 078 双管贝壳枪 · 概率追加一发 ──")
	for si in range(3):
		var want_p: float = [0.25, 0.35, 0.50][si]
		var want_pct: float = [0.40, 0.50, 0.60][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 340.0), 3000.0), "p2eq_078", si + 1)
		u["atk"] = 100.0
		u["base_atk"] = 100.0
		u["crit"] = 0.0
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 340.0), 90000000.0)
		t["hp"] = 90000000.0
		t["_dbarrel_n"] = 0
		_s._battle_rng.seed = SEED
		var h0: float = float(t["hp"])
		for _k in range(TRIALS):
			_s._equip_sys._eq_on_basic_attack(u, t)
		var fired: int = int(t.get("_dbarrel_n", 0))
		var rate: float = float(fired) / float(TRIALS)
		_ok("078 si=%d 追加概率 ≈ %.0f%%(播种 RNG · %d 次实测 %.1f%%)" % [si, want_p * 100.0, TRIALS, rate * 100.0],
			absf(rate - want_p) < 0.03, "实测 %.4f 期望 %.2f" % [rate, want_p])
		_ok("078 si=%d ★分母: 这一轮确实追加过(fired=%d > 0)" % [si, fired], fired > 0)
		var per: float = (h0 - float(t["hp"])) / maxf(1.0, float(fired))
		_ok("078 si=%d 每发伤害 = %.0f%% × 攻击力 100 = %.0f(需求 40/50/60%%)" % [si, want_pct * 100.0, want_pct * 100.0],
			absf(per - want_pct * 100.0) < 0.51, "实测每发 %.2f" % per)
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 083 潮汐细剑: 连续命中同一目标每层 +4/7/11%(最多 5 层, 换目标清空)
# ─────────────────────────────────────────────────────────────
func _t083_tide_rapier() -> void:
	print("── 083 潮汐细剑 · 连击叠层 ──")
	for si in range(3):
		var per: float = [0.04, 0.07, 0.11][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 380.0), 3000.0), "p2eq_083", si + 1)
		var a: Dictionary = _mk("basic", "right", Vector2(-100.0, 380.0), 900000.0)
		var b: Dictionary = _mk("basic", "right", Vector2(100.0, 380.0), 900000.0)
		# 第 1 击: 建立目标, 不吃加成
		var h1: float = float(a["hp"])
		_s._equip_sys._eq_on_hit(u, a, 1000)
		_ok("083 si=%d ★第一击不吃加成(层数在这一击之后才 +1)" % si,
			absf(h1 - float(a["hp"])) < 0.01, "第一击额外 %.1f" % (h1 - float(a["hp"])))
		# 第 2 击: 1 层
		var h2: float = float(a["hp"])
		_s._equip_sys._eq_on_hit(u, a, 1000)
		_ok("083 si=%d 第二击吃 1 层 = +%.0f(需求 4/7/11%%)" % [si, round(1000.0 * per)],
			absf(h2 - float(a["hp"]) - round(1000.0 * per)) < 0.51,
			"实掉 %.1f 期望 %.0f" % [h2 - float(a["hp"]), round(1000.0 * per)])
		# 再打 4 下 → 层数封顶 5
		for _k in range(4):
			_s._equip_sys._eq_on_hit(u, a, 1000)
		var h6: float = float(a["hp"])
		_s._equip_sys._eq_on_hit(u, a, 1000)
		_ok("083 si=%d ★封顶 5 层 = +%.0f(第 7 击也还是 5 层)" % [si, round(1000.0 * per * 5.0)],
			absf(h6 - float(a["hp"]) - round(1000.0 * per * 5.0)) < 0.51,
			"实掉 %.1f 期望 %.0f" % [h6 - float(a["hp"]), round(1000.0 * per * 5.0)])
		_ok("083 si=%d ★分母: eq_state 里真的是 5 层" % si,
			int((u["eq_state"]["p2eq_083"] as Dictionary).get("tide_layers", 0)) == 5,
			"layers=%d" % int((u["eq_state"]["p2eq_083"] as Dictionary).get("tide_layers", 0)))
		# 换目标 → 清空
		var hb: float = float(b["hp"])
		_s._equip_sys._eq_on_hit(u, b, 1000)
		_ok("083 si=%d ★换目标清空(打 b 的第一下没有任何加成)" % si,
			absf(hb - float(b["hp"])) < 0.01, "换靶第一击额外 %.1f" % (hb - float(b["hp"])))
		var ha: float = float(a["hp"])
		_s._equip_sys._eq_on_hit(u, a, 1000)
		_ok("083 si=%d ★换回 a 也是从零开始(不是各存各的)" % si,
			absf(ha - float(a["hp"])) < 0.01, "换回额外 %.1f" % (ha - float(a["hp"])))
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
#  R4 (方案书): 078 追加的那一发【不触发 on-hit】—— 必须焊死
#  不焊的话它会与剑士追打 / 冰封掷骰 / 僵硬叠层形成连锁自激。
# ═════════════════════════════════════════════════════════════
func _t_r4_no_chain() -> void:
	print("── R4 078 追加那发不触发 on-hit / 不喂剑士 ──")
	_s._units.clear()
	var saved = _s._synergy._by_side
	_s._synergy._by_side = {"left": {"剑": 3, "枪": 1}, "right": {}}
	_s._swordsman.clear()
	# 携带者同时带 078(枪) + 083(剑): 083 是本批唯一"每次 on-hit 必叠一层"的件,
	# 拿它当【on-hit 到底有没有被触发】的同步探针 —— 比"数 tween 变多了"那种假断言硬
	# (CLAUDE.md §3.5: _kill 里别的效果也建 tween, 反向验证时不会红)。
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 420.0), 3000.0)
	u["equips"] = [{"id": "p2eq_078", "star": 3}, {"id": "p2eq_083", "star": 3}]
	u["eq_state"] = {}
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	u["crit"] = 0.0
	u["atk_interval"] = 1.25
	var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 420.0), 90000000.0)
	t["hp"] = 90000000.0
	_ok("R4 ★分母: 剑羁绊 3 档已激活(不激活就没有追打, 下面那条会恒真)",
		int(_s._synergy.tier_for(u, "剑")) == 3, "tier=%d" % int(_s._synergy.tier_for(u, "剑")))
	# ★★① 追加那一发【不触发 on-hit】: 直接把那一发打出去, 083 一层都不该叠
	_s._swordsman._pending.clear()
	u["eq_state"] = {}
	_s._equip_sys._double_barrel_shot(u, t, 0.60)
	var lay_after: int = int((u["eq_state"].get("p2eq_083", {}) as Dictionary).get("tide_layers", 0))
	_ok("R4 ★★追加的那一发【不触发 on-hit】(083 一层都没叠)",
		lay_after == 0, "tide_layers=%d" % lay_after)
	# ★★② 追加那一发【不给剑士排追打】(它不经 _basic_attack / _eq_on_basic_attack)
	_ok("R4 ★★追加的那一发不给剑士排追打(pending 仍为空)",
		_s._swordsman._pending.is_empty(), "pending=%d" % _s._swordsman._pending.size())
	# ★★③ 反向证明上面两条不是空检查: 同一对单位走【正常那条路】必须两样都发生
	u["eq_state"] = {}
	_s._damage._apply_damage_from(u, t, 100, Color("#ffffff"))
	var lay_norm: int = int((u["eq_state"].get("p2eq_083", {}) as Dictionary).get("tide_layers", 0))
	_ok("R4 ★★分母: 同一对单位走正常伤害路 → 083 确实叠了 1 层(证明探针有效)",
		lay_norm == 1, "tide_layers=%d" % lay_norm)
	_s._swordsman.on_basic_attack(u, t)
	_ok("R4 ★★分母: 同一只走剑士普攻钩 → 确实排了 2 发追打(证明探针有效)",
		_s._swordsman._pending.size() == 2, "pending=%d" % _s._swordsman._pending.size())
	_s._swordsman.clear()
	_s._synergy._by_side = saved
	_s._units.clear()


# ═════════════════════════════════════════════════════════════
#  R1 量级(方案书 §4 R1 · 用户点名要实测): 剑阵容里 083 的层数涨多快?
#
#  ★口径: 剑士【追打会触发 on-hit】(SwordsmanSystem.tick 里显式调 _eq_on_hit),
#    用户拍板 U3-A「会喂」。⇒ 一次普攻在 3 档下产生 1(普攻) + 2(追打) = 3 次 on-hit。
#    本节【只测量并打印】, 不自己砍数值 —— 数字交给用户拍板。
#  ★用真的 SwordsmanSystem 跑(排队 + tick 推进), 不手工调 3 次 on-hit 假装。
# ═════════════════════════════════════════════════════════════
func _t_r1_tide_magnitude() -> void:
	print("── R1 量级: 剑阵容里 083 层数涨多快 ──")
	_s._units.clear()
	var saved = _s._synergy._by_side
	_s._synergy._by_side = {"left": {"剑": 3}, "right": {}}
	_s._swordsman.clear()
	var u: Dictionary = _mk("fortune", "left", Vector2(-300.0, 460.0), 3000.0)
	u["equips"] = [{"id": "p2eq_083", "star": 3}, {"id": "p2eq_084", "star": 3}]
	u["eq_state"] = {}
	u["atk"] = 100.0
	u["base_atk"] = 100.0
	u["crit"] = 0.0
	u["atk_interval"] = 1.25
	var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 460.0), 90000000.0)
	t["hp"] = 90000000.0
	_ok("R1 ★分母: 剑 3 档已激活 + 身上 2 件剑(追打倍率按件数算)",
		int(_s._synergy.tier_for(u, "剑")) == 3 and u["equips"].size() == 2,
		"tier=%d 件数=%d" % [int(_s._synergy.tier_for(u, "剑")), u["equips"].size()])
	var tsave: float = _s._t
	var atk_n := 0
	var layers := 0
	while atk_n < 8 and layers < 5:
		atk_n += 1
		# 一次普攻: on-hit(本体) + 剑士排 2 发追打, 推时钟让追打落地
		_s._equip_sys._eq_on_hit(u, t, 1000)
		_s._swordsman.on_basic_attack(u, t)
		for _st in range(3):
			_s._t += 0.5
			_s._swordsman.tick(0.5)
		layers = int((u["eq_state"].get("p2eq_083", {}) as Dictionary).get("tide_layers", 0))
		print("    普攻第 %d 下之后 → 083 层数 = %d (加成 +%d%%)" % [atk_n, layers, layers * 11])
	print("  ⇒ 剑 3 档 + 2 件剑: 第 %d 下普攻就满 5 层(+55%% 伤害)" % atk_n)
	# ★★细分记账: 一次普攻里"剑士追打"这一路到底喂了几次 on-hit。
	#   3 档剑士排 2 发追打 ⇒ 应该是 **2 次** on-hit。
	#
	# ★★2026-08-05【这里原来是 4，是个双发 bug，已修】
	#   `SwordsmanSystem.tick` 先调 `_apply_damage_from(...)`(from_equip 默认 false
	#   ⇒ battle_damage.gd:259 内部就会回钩一次 on-hit), 紧接着又【显式】调了一次
	#   `battle._equip_sys._eq_on_hit(...)` ⇒ 每发追打把 on-hit 点了两次,
	#   一次普攻 = 1 + 2x2 = **5 次 on-hit 事件**(应为 3)。
	#   影响的不止 083, 是**所有 on-hit 装备**(流血叠层/005 双刃/各种充能计数)
	#   在剑阵容里全部按双倍速率跑。弓/药水/奇械/法器没这问题(只在内部那段挂了一次)。
	#   ⇒ 删掉 swordsman_system.gd 里那行重复调用。实证: 本行实测值 4 → 2, 正好减半。
	#
	#   ★这条断言把【修好之后】的事实钉住: 谁再把那行加回去, 本条立刻红。
	u["eq_state"] = {}
	_s._swordsman.clear()
	_s._swordsman.on_basic_attack(u, t)
	for _st2 in range(3):
		_s._t += 0.5
		_s._swordsman.tick(0.5)
	var only_chase: int = int((u["eq_state"].get("p2eq_083", {}) as Dictionary).get("tide_layers", 0))
	print("    细分: 只走剑士追打(3 档 = 2 发) → 083 涨了 %d 层" % only_chase)
	_ok("R1 ★★记账: 3 档剑士的 2 发追打【正好】喂 2 次 on-hit(双发 bug 已修)",
		only_chase == 2,
		"实测 %d 层。期望 2 —— 若是 4, 说明 swordsman_system 那行重复的 _eq_on_hit 又回来了" % only_chase)
	_ok("R1 ★★实测: 剑阵容里 083 在 %d 下普攻内满层(不带剑士需要 6 下 on-hit)" % atk_n,
		atk_n >= 1 and atk_n <= 8 and layers == 5,
		"atk_n=%d layers=%d" % [atk_n, layers])
	# ★上限本身是硬的: 无论怎么喂, 加成不超过 5 层 × 11% = 55%
	for _k in range(50):
		_s._equip_sys._eq_on_hit(u, t, 1000)
	var final_l: int = int((u["eq_state"].get("p2eq_083", {}) as Dictionary).get("tide_layers", 0))
	_ok("R1 ★喂爆也不超 5 层(3★ 封顶 = +55% 伤害)", final_l == 5, "layers=%d" % final_l)
	_s._t = tsave
	_s._swordsman.clear()
	_s._synergy._by_side = saved
	_s._units.clear()
