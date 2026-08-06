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
	# ★078/083 两件已由用户整条重写(2026-08-06 §0.5·批④): 078 双管贝壳枪→电鳗双管铳
	#   (左右管每 2 秒交替 + 电流连锁), 083 潮汐细剑改成 20 层叠加 + 残血攻速。
	#   旧效果函数 _double_barrel_shot / _eq_tide_rapier 均已删除 ⇒ 四段用例
	#   (_t078_double_barrel / _t083_tide_rapier / _t_r4_no_chain / _t_r1_tide_magnitude)
	#   随之删除, 新门禁在 tests/verify_eq_gun_batch.gd 与 tests/verify_eq_blade_batch.gd。
	#   接线结构由 tests/verify_b4_wiring.gd 统一守。

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
		# ★083 与 078 已于 2026-08-06(批④)被用户整条重做 ⇒ 从这两行摘掉。
		#   它们现在走 EquipSystem 的批④统一路由(`_b4(iid).on_hit/on_basic`),
		#   结构由 tests/verify_b4_wiring.gd 守、数值由各路自己的门禁守。
		"func _eq_on_hit": ["p2eq_075"],
		"func _eq_on_basic_attack": ["p2eq_073", "p2eq_074", "p2eq_076"],
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
	_ok("⓪ ★分母: 本批一共查了 %d 件(应为 4 —— 060/061 见 verify_eq_spirit_batch, 067/068 见 verify_eq_potion_batch, 078/083 见批④)" % total, total == 4, "total=%d" % total)
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
	# ★2026-08-06(批④): 083 是 equip_system.gd 里最后一个调这个投递口的件, 它被重做后
	#   这里只剩【1 处定义、0 处调用】。**函数不删** —— 它是"加伤/额外真伤统一投递"的公共口,
	#   eq_bow_batch.gd 等外部文件仍在用(见下面那条分母)。这里守的是"没人在本文件里另写一套扣血"。
	_ok("⓪ _eq_bonus_hit 仍是唯一投递口(equip_system.gd 内 1 处定义, 无就地重写)",
		code.count("_eq_bonus_hit(") == 1,
		"出现 %d 次(期望 1 = 只剩定义; 调用方已全部外迁到各批系统)" % code.count("_eq_bonus_hit("))
	# ★分母: 投递口真的还有人用 —— 否则上面那条会在"函数变成死代码"时照样绿
	var _users := 0
	for _f in ["res://scripts/systems/equip/eq_bow_batch.gd", "res://scripts/systems/equip/eq_potion_batch.gd",
			"res://scripts/systems/equip/eq_spirit_batch.gd", "res://scripts/systems/equip/eq_food_batch.gd"]:
		if _strip(_f).contains("_eq_bonus_hit("):
			_users += 1
	_ok("⓪ ★分母: _eq_bonus_hit 至少还有 1 个外部调用者(不是死代码)", _users >= 1, "调用它的批系统 %d 个" % _users)
	# 六件 on-hit 的效果体都外迁成具名函数, 且分派写成 `"id": _fn(` —— 少一条,
	# tooltip_number_audit 就拿不到函数锚点, 数值会被判"远处命中"
	var hit_body: String = _fn_body(code, "func _eq_on_hit")
	# ★弓箭四件不在这里: 它们的效果本体搬到了 EqBowBatch(分派写成 `"id": _bow_sys.xxx(`),
	#   不再是本文件里的 `_eq_*` 具名函数 ⇒ 改由 tests/verify_eq_bow_batch.gd 守。
	# ★2026-08-06(批④): 这张表原来只剩 083→_eq_tide_rapier 一条, 083 已被整条重做 ⇒ 表空了。
	#   **空表 + for 循环 = 恒真断言**, 那比没有断言更糟(它会一直绿着假装守着东西)。
	#   ⇒ 改成守【本文件仍然负责的那一件】: 075 的分派必须是 `"id": _sys.fn(` 形状,
	#   否则 tooltip_number_audit 拿不到函数锚点, 它的数值会被判"远处命中"。
	_ok("⓪ 075 的 on-hit 分派写成 \"id\": _fn( 形状(tooltip 审计靠这个锚点)",
		hit_body.contains("\"p2eq_075\": _bow_sys.on_hit_075("), "hit_body len=%d" % hit_body.length())
	_ok("⓪ ★分母: on_hit_075 这个函数真的存在于 eq_bow_batch.gd",
		_strip("res://scripts/systems/equip/eq_bow_batch.gd").contains("func on_hit_075("), "")
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

# ★★2026-08-06(批④): 这里原有四段逐件用例 —— _t078_double_barrel / _t083_tide_rapier /
#   _t_r4_no_chain(078 追加那一发不触发 on-hit) / _t_r1_tide_magnitude(083 层数量级)。
#   078 与 083 已由用户整条重做(078 双管贝壳枪→电鳗双管铳: 左右管每 2 秒交替 + 电流连锁;
#   083 潮汐细剑: 20 层叠加 + 残血攻速), 旧效果函数 _double_barrel_shot / _eq_tide_rapier
#   均已从 equip_system.gd 删除 ⇒ 四段整段删除。
#   ★是整段删而不是"把旧断言改成新数字" —— 旧用例量的是旧机制(如"25% 概率追加一发"、
#   "最多 5 层"), 改数字保不住它们。新门禁: tests/verify_eq_gun_batch.gd(078) 与
#   tests/verify_eq_blade_batch.gd(083); 接线结构由 tests/verify_b4_wiring.gd 守。
