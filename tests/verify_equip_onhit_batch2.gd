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
	_t060_jelly_parasol()
	_t061_wraith_bell()
	_t067_hunter_flask()
	_t068_elixir()
	_t073_vine_bow()
	_t074_bone_quiver()
	_t075_eagle_lens()
	_t076_corroder()
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
		"func _eq_on_hit": ["p2eq_067", "p2eq_073", "p2eq_074", "p2eq_075", "p2eq_076", "p2eq_083"],
		"func _eq_on_basic_attack": ["p2eq_078"],
		"func _eq_on_dodge": ["p2eq_060", "p2eq_061"],
		"func _eq_on_kill": ["p2eq_068"],
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
	_ok("⓪ ★分母: 本批一共查了 %d 件(应为 10)" % total, total == 10, "total=%d" % total)
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
		code.count("_eq_bonus_hit(") == 6,
		"出现 %d 次(期望 6 = 1 定义 + 5 调用: 067/073/074/075/083)" % code.count("_eq_bonus_hit("))
	# 六件 on-hit 的效果体都外迁成具名函数, 且分派写成 `"id": _fn(` —— 少一条,
	# tooltip_number_audit 就拿不到函数锚点, 数值会被判"远处命中"
	var hit_body: String = _fn_body(code, "func _eq_on_hit")
	var fns := {"p2eq_067": "_eq_hunter_flask", "p2eq_073": "_eq_vine_bow", "p2eq_074": "_eq_bone_quiver",
		"p2eq_075": "_eq_eagle_lens", "p2eq_076": "_eq_corroder", "p2eq_083": "_eq_tide_rapier"}
	var nowire: Array = []
	for k in fns:
		if not hit_body.contains("\"%s\": %s(" % [k, fns[k]]):
			nowire.append("%s→%s" % [k, fns[k]])
		if not code.contains("func %s(" % fns[k]):
			nowire.append("缺 func %s" % fns[k])
	_ok("⓪ 六件 on-hit 的分派写成 \"id\": _fn( 且函数真的存在(tooltip 审计靠这个锚点)",
		nowire.is_empty(), str(nowire))


# ─────────────────────────────────────────────────────────────
# 060 磷光水母伞: 闪避成功 → 对最近的敌人 20/35/60 魔法伤害
# ─────────────────────────────────────────────────────────────
func _t060_jelly_parasol() -> void:
	print("── 060 磷光水母伞 · 闪避反击 ──")
	for si in range(3):
		var want: float = [20.0, 35.0, 60.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -260.0), 3000.0), "p2eq_060", si + 1)
		var near: Dictionary = _mk("basic", "right", Vector2(-120.0, -260.0), 9000.0)
		var far: Dictionary = _mk("basic", "right", Vector2(360.0, -260.0), 9000.0)
		var h0: float = float(near["hp"])
		var f0: float = float(far["hp"])
		_s._equip_sys._eq_on_dodge(u)
		_ok("060 si=%d 最近敌吃 %.0f 魔法(需求 20/35/60, 魔抗 0)" % [si, want],
			absf(h0 - float(near["hp"]) - want) < 0.51, "实掉 %.1f" % (h0 - float(near["hp"])))
		_ok("060 si=%d ★分母: 远处那个没吃到(证明是单体最近敌)" % si,
			absf(f0 - float(far["hp"])) < 0.01, "远处掉 %.1f" % (f0 - float(far["hp"])))
	# ★★真入口: 走【中央伤害管线的闪避分支】—— 不是直接调钩子
	_s._units.clear()
	var d: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -300.0), 3000.0), "p2eq_060", 3)
	d["dodge_bonus"] = 1.0                       # randf() ∈ [0,1) 恒 < 1.0 ⇒ 必闪
	var atkr: Dictionary = _mk("basic", "right", Vector2(-120.0, -300.0), 9000.0)
	var a0: float = float(atkr["hp"])
	var d0: float = float(d["hp"])
	_s._damage._apply_damage_from(atkr, d, 500, Color("#ffffff"))
	_ok("060 ★★真入口: 被打时真的闪避了(自己一点血没掉)",
		absf(d0 - float(d["hp"])) < 0.01, "携带者掉 %.1f" % (d0 - float(d["hp"])))
	_ok("060 ★★真入口: 闪避成功 → 攻击者吃到 60 魔法(3★)",
		absf(a0 - float(atkr["hp"]) - 60.0) < 0.51, "攻击者掉 %.1f 期望 60" % (a0 - float(atkr["hp"])))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 061 游魂贝铃: 闪避成功 → 本体 +12/20/32% 移速, 持续 2 秒(可刷新)
# ─────────────────────────────────────────────────────────────
func _t061_wraith_bell() -> void:
	print("── 061 游魂贝铃 · 闪避加移速 ──")
	for si in range(3):
		var want: float = 1.0 + [0.12, 0.20, 0.32][si]
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0 + 20.0 * float(si), -200.0)), "p2eq_061", si + 1)
		u["move_buff_mult"] = 1.0
		u["move_buff_until"] = 0.0
		_ok("061 si=%d ★分母: 起手没有移速 buff(倍率 1.0)" % si,
			absf(float(u.get("move_buff_mult", 1.0)) - 1.0) < 0.0001,
			"mult=%.3f" % float(u.get("move_buff_mult", 1.0)))
		_s._equip_sys._eq_on_dodge(u)
		_ok("061 si=%d 闪避后移速倍率 = %.2f(需求 +12/20/32%%)" % [si, want],
			absf(float(u["move_buff_mult"]) - want) < 0.0005,
			"实测 %.3f 期望 %.3f" % [float(u["move_buff_mult"]), want])
		_ok("061 si=%d 持续 2 秒(到期时刻 = 现在 +2)" % si,
			absf(float(u["move_buff_until"]) - (_s._t + 2.0)) < 0.02,
			"until-_t=%.3f" % (float(u["move_buff_until"]) - _s._t))
	# ★可刷新: 时钟往前推 1.5 秒后再闪一次, 到期时刻要跟着往后走
	var r: Dictionary = _equip(_mk("fortune", "left", Vector2(-200.0, -160.0)), "p2eq_061", 3)
	r["move_buff_mult"] = 1.0
	r["move_buff_until"] = 0.0
	var tsave: float = _s._t
	_s._equip_sys._eq_on_dodge(r)
	var u1: float = float(r["move_buff_until"])
	_s._t = tsave + 1.5
	_s._equip_sys._eq_on_dodge(r)
	_ok("061 ★可刷新: 1.5 秒后再闪 → 到期时刻从 %.2f 推到 %.2f" % [u1, float(r["move_buff_until"])],
		float(r["move_buff_until"]) > u1 + 1.4, "Δ=%.2f" % (float(r["move_buff_until"]) - u1))
	# ★不吞掉更强的 buff: move_buff_mult 是【单槽】通道(训龟大师怒吼也写它)
	r["move_buff_mult"] = 1.50
	r["move_buff_until"] = _s._t + 8.0
	_equip(r, "p2eq_061", 1)                     # 1★ 只想给 1.12
	_s._equip_sys._eq_on_dodge(r)
	_ok("061 ★不把别人给的 1.50 移速盖成 1.12(单槽通道取更强的那个)",
		absf(float(r["move_buff_mult"]) - 1.50) < 0.0005, "mult=%.3f" % float(r["move_buff_mult"]))
	_s._t = tsave
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 067 猎人的酒囊: 攻击【猎物】时额外造成 10/16/25% 真实伤害
# ─────────────────────────────────────────────────────────────
func _t067_hunter_flask() -> void:
	print("── 067 猎人的酒囊 · 打猎物额外真伤 ──")
	for si in range(3):
		var want: float = [20.0, 32.0, 50.0][si]   # 200 × 10/16/25%
		_s._units.clear()
		_s._potion_syn.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -120.0), 3000.0), "p2eq_067", si + 1)
		var prey: Dictionary = _mk("basic", "right", Vector2(-100.0, -120.0), 9000.0)
		var other: Dictionary = _mk("basic", "right", Vector2(100.0, -120.0), 9000.0)
		_s._potion_syn._prey["left"] = prey        # 药水羁绊打的标记(这里直接置, 不依赖档位)
		var p0: float = float(prey["hp"])
		var o0: float = float(other["hp"])
		_s._equip_sys._eq_on_hit(u, prey, 200)
		_s._equip_sys._eq_on_hit(u, other, 200)
		_ok("067 si=%d 打猎物额外 %.0f 真伤(200 的 10/16/25%%)" % [si, want],
			absf(p0 - float(prey["hp"]) - want) < 0.51, "实掉 %.1f" % (p0 - float(prey["hp"])))
		_ok("067 si=%d ★分母: 打【非猎物】一点额外伤害都没有" % si,
			absf(o0 - float(other["hp"])) < 0.01, "非猎物掉 %.1f" % (o0 - float(other["hp"])))
	_s._potion_syn.clear()
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 068 万灵龟血: 击杀任意敌 → 永久 +4/7/12 攻击(上限 +60/110/180); 杀猎物则双倍
# ─────────────────────────────────────────────────────────────
func _t068_elixir() -> void:
	print("── 068 万灵龟血 · 击杀涨攻 ──")
	for si in range(3):
		var per: float = [4.0, 7.0, 12.0][si]
		var cap: float = [60.0, 110.0, 180.0][si]
		_s._units.clear()
		_s._potion_syn.clear()
		var k: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -60.0), 3000.0), "p2eq_068", si + 1)
		var v: Dictionary = _mk("basic", "right", Vector2(-100.0, -60.0), 9000.0)
		var a0: float = float(k["base_atk"])
		var atk0: float = float(k["atk"])
		_s._equip_sys._eq_on_kill(k, v)
		_ok("068 si=%d 一次击杀 +%.0f 攻击力(需求 4/7/12)" % [si, per],
			absf(float(k["base_atk"]) - a0 - per) < 0.01,
			"base_atk %.1f→%.1f" % [a0, float(k["base_atk"])])
		_ok("068 si=%d ★写的是 base_atk 且 atk 真的跟着涨(写 atk 会被 _recalc_stats 冲掉)" % si,
			float(k["atk"]) > atk0 + per - 0.51, "atk %.1f→%.1f" % [atk0, float(k["atk"])])
		for _j in range(200):
			_s._equip_sys._eq_on_kill(k, v)
		_ok("068 si=%d ★封顶 +%.0f(需求 60/110/180; 灌 200 次击杀也不超)" % [si, cap],
			absf(float(k["base_atk"]) - a0 - cap) < 0.01,
			"base_atk +%.1f 期望 +%.0f" % [float(k["base_atk"]) - a0, cap])
	# ★猎物双倍
	_s._units.clear()
	_s._potion_syn.clear()
	var k3: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, -20.0), 3000.0), "p2eq_068", 3)
	var prey: Dictionary = _mk("basic", "right", Vector2(-100.0, -20.0), 9000.0)
	_s._potion_syn._prey["left"] = prey
	var b0: float = float(k3["base_atk"])
	_s._equip_sys._eq_on_kill(k3, prey)
	_ok("068 ★杀的是【猎物】→ 双倍(3★ 12 → 24)",
		absf(float(k3["base_atk"]) - b0 - 24.0) < 0.01,
		"base_atk +%.1f 期望 +24" % (float(k3["base_atk"]) - b0))
	# ★分母: 同一只 3★ 杀非猎物只 +12(证明双倍不是恒定给的)
	var k4: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0, -20.0), 3000.0), "p2eq_068", 3)
	var norm: Dictionary = _mk("basic", "right", Vector2(-60.0, -20.0), 9000.0)
	var c0: float = float(k4["base_atk"])
	_s._equip_sys._eq_on_kill(k4, norm)
	_ok("068 ★分母: 杀非猎物只 +12(不是每次都双倍)",
		absf(float(k4["base_atk"]) - c0 - 12.0) < 0.01,
		"base_atk +%.1f 期望 +12" % (float(k4["base_atk"]) - c0))
	# ★★真入口: 走 _kill —— 而且 _eq_on_kill 必须排在 _potion_syn.on_death(清空猎物槽)【之前】
	_s._units.clear()
	_s._potion_syn.clear()
	var k5: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 20.0), 3000.0), "p2eq_068", 3)
	var dying: Dictionary = _mk("basic", "right", Vector2(-100.0, 20.0), 9000.0)
	_s._potion_syn._prey["left"] = dying
	var e0: float = float(k5["base_atk"])
	dying["hp"] = 0.0
	_s._kill(dying, k5)
	_ok("068 ★★真入口: 经 _kill 触发, 且此时猎物槽还没被清 → 拿到双倍 24",
		absf(float(k5["base_atk"]) - e0 - 24.0) < 0.01,
		"base_atk +%.1f 期望 +24" % (float(k5["base_atk"]) - e0))
	_s._potion_syn.clear()
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 073 藤蔓短弓: 命中生命 >70% 的目标 → 本次伤害 +8/14/22%
# ─────────────────────────────────────────────────────────────
func _t073_vine_bow() -> void:
	print("── 073 藤蔓短弓 · 打健康目标加伤 ──")
	for si in range(3):
		var want: float = [8.0, 14.0, 22.0][si]   # 100 × 8/14/22%
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 60.0), 3000.0), "p2eq_073", si + 1)
		var full: Dictionary = _mk("basic", "right", Vector2(-100.0, 60.0), 1000.0)
		var hurt: Dictionary = _mk("basic", "right", Vector2(100.0, 60.0), 1000.0)
		hurt["hp"] = 600.0                          # 60% < 70% → 不该加伤
		var f0: float = float(full["hp"])
		var h0: float = float(hurt["hp"])
		_s._equip_sys._eq_on_hit(u, full, 100)
		_s._equip_sys._eq_on_hit(u, hurt, 100)
		_ok("073 si=%d 满血目标额外 %.0f(本次 100 的 8/14/22%%)" % [si, want],
			absf(f0 - float(full["hp"]) - want) < 0.51, "实掉 %.1f" % (f0 - float(full["hp"])))
		_ok("073 si=%d ★分母: 60%% 血的目标一点加伤都没有(阈值是 70%%)" % si,
			absf(h0 - float(hurt["hp"])) < 0.01, "残血目标掉 %.1f" % (h0 - float(hurt["hp"])))
	# ★★端到端: 经【中央伤害管线】打一发 100, 目标总共该掉 122(100 本体 + 22 加成)
	_s._units.clear()
	var e2e: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 100.0), 3000.0), "p2eq_073", 3)
	var tgt: Dictionary = _mk("basic", "right", Vector2(-100.0, 100.0), 9000.0)
	var t0: float = float(tgt["hp"])
	_s._damage._apply_damage_from(e2e, tgt, 100, Color("#ffffff"))
	_ok("073 ★★端到端: 经 _apply_damage_from 打 100 → 实掉 122(on-hit 真的在管线上)",
		absf(t0 - float(tgt["hp"]) - 122.0) < 0.51, "实掉 %.1f 期望 122" % (t0 - float(tgt["hp"])))
	# ★分母: 同一发, 换成不带 073 的攻击者 → 就是 100
	var bare: Dictionary = _mk("fortune", "left", Vector2(-260.0, 100.0), 3000.0)
	bare["equips"] = [{"id": "p2eq_073", "star": 3}]
	bare["equips"] = []
	var t1: float = float(tgt["hp"])
	_s._damage._apply_damage_from(bare, tgt, 100, Color("#ffffff"))
	_ok("073 ★分母: 不带装备的同一发只掉 100(证明上面那 22 是 073 加的)",
		absf(t1 - float(tgt["hp"]) - 100.0) < 0.51, "实掉 %.1f" % (t1 - float(tgt["hp"])))
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 074 骨簇箭袋: 暴击时额外造成 10/18/30 真实伤害
# ─────────────────────────────────────────────────────────────
func _t074_bone_quiver() -> void:
	print("── 074 骨簇箭袋 · 暴击追真伤 ──")
	for si in range(3):
		var want: float = [10.0, 18.0, 30.0][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 140.0), 3000.0), "p2eq_074", si + 1)
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 140.0), 9000.0)
		_s._last_atk_crit = false
		var n0: float = float(t["hp"])
		_s._equip_sys._eq_on_hit(u, t, 100)
		_ok("074 si=%d ★分母: 没暴击 → 一点额外伤害都没有" % si,
			absf(n0 - float(t["hp"])) < 0.01, "非暴击掉 %.1f" % (n0 - float(t["hp"])))
		_s._last_atk_crit = true
		var c0: float = float(t["hp"])
		_s._equip_sys._eq_on_hit(u, t, 100)
		_ok("074 si=%d 暴击 → 额外 %.0f 真伤(需求 10/18/30)" % [si, want],
			absf(c0 - float(t["hp"]) - want) < 0.51, "实掉 %.1f" % (c0 - float(t["hp"])))
	# ★★真暴击: 让攻击者暴击率 100% 走 _atk_dmg → _apply_damage_from, 不手工置标志
	_s._units.clear()
	var u2: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 180.0), 3000.0), "p2eq_074", 3)
	u2["atk"] = 100.0
	u2["base_atk"] = 100.0
	u2["crit"] = 1.0
	u2["crit_dmg"] = 1.5
	var t2: Dictionary = _mk("basic", "right", Vector2(-100.0, 180.0), 9000.0)
	var b0: float = float(t2["hp"])
	var d2: int = _s._atk_dmg(u2, 1.0, t2)        # 暴击率 100% ⇒ 必暴, 且它会置 _last_atk_crit
	_s._damage._apply_damage_from(u2, t2, d2, Color("#ffffff"))
	_ok("074 ★★真暴击(不手工置标志): 150 暴击伤 + 30 真伤 = 180",
		absf(b0 - float(t2["hp"]) - 180.0) < 0.51,
		"本体段 %d · 实掉 %.1f 期望 180" % [d2, b0 - float(t2["hp"])])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 075 鹰眼镜片: 每满 100 码 +2/3.5/5% 伤害, 最多 +10/18/28%
# ─────────────────────────────────────────────────────────────
func _t075_eagle_lens() -> void:
	print("── 075 鹰眼镜片 · 越远越疼 ──")
	for si in range(3):
		var per: float = [0.02, 0.035, 0.05][si]
		var cap: float = [0.10, 0.18, 0.28][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-400.0, 220.0), 3000.0), "p2eq_075", si + 1)
		# 300 码 → 3 档
		var t3: Dictionary = _mk("basic", "right", Vector2(-100.0, 220.0), 9000.0)
		var a0: float = float(t3["hp"])
		_s._equip_sys._eq_on_hit(u, t3, 1000)
		var want3: float = round(1000.0 * minf(3.0 * per, cap))
		_ok("075 si=%d 300 码 → 额外 %.0f(每满 100 码 +2/3.5/5%%)" % [si, want3],
			absf(a0 - float(t3["hp"]) - want3) < 0.51, "实掉 %.1f 期望 %.0f" % [a0 - float(t3["hp"]), want3])
		# 0 码(贴脸) → 一点都不加
		var t0d: Dictionary = _mk("basic", "right", Vector2(-400.0, 220.0), 9000.0)
		var z0: float = float(t0d["hp"])
		_s._equip_sys._eq_on_hit(u, t0d, 1000)
		_ok("075 si=%d ★分母: 贴脸(0 码) → 一点加伤都没有" % si,
			absf(z0 - float(t0d["hp"])) < 0.01, "贴脸掉 %.1f" % (z0 - float(t0d["hp"])))
		# 2000 码 → 封顶
		var tf: Dictionary = _mk("basic", "right", Vector2(-400.0, 2220.0), 9000.0)
		tf["pos"] = u["pos"] + Vector2(2000.0, 0.0)      # 直接摆坐标, 不受 ARENA 钳制影响
		var c0: float = float(tf["hp"])
		_s._equip_sys._eq_on_hit(u, tf, 1000)
		_ok("075 si=%d ★封顶 +%.0f%%(2000 码远也不超)" % [si, cap * 100.0],
			absf(c0 - float(tf["hp"]) - round(1000.0 * cap)) < 0.51,
			"实掉 %.1f 期望 %.0f" % [c0 - float(tf["hp"]), round(1000.0 * cap)])
	_s._units.clear()


# ─────────────────────────────────────────────────────────────
# 076 腐蚀重弩: 暴击时为目标额外叠 1/1/2 层【腐蚀】(共用 corrode_stacks, 上限 5)
# ─────────────────────────────────────────────────────────────
func _t076_corroder() -> void:
	print("── 076 腐蚀重弩 · 暴击喂腐蚀 ──")
	for si in range(3):
		var per: int = [1, 1, 2][si]
		_s._units.clear()
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 260.0), 3000.0), "p2eq_076", si + 1)
		var t: Dictionary = _mk("basic", "right", Vector2(-100.0, 260.0), 9000.0)
		_s._last_atk_crit = false
		_s._equip_sys._eq_on_hit(u, t, 100)
		_ok("076 si=%d ★分母: 没暴击 → 一层都不叠" % si,
			int(t.get("corrode_stacks", 0)) == 0, "stacks=%d" % int(t.get("corrode_stacks", 0)))
		_s._last_atk_crit = true
		_s._equip_sys._eq_on_hit(u, t, 100)
		_ok("076 si=%d 一次暴击叠 %d 层(需求 1/1/2)" % [si, per],
			int(t["corrode_stacks"]) == per, "stacks=%d" % int(t["corrode_stacks"]))
		_ok("076 si=%d ★U2-B 用户拍板: 无弓箭羁绊时 corrode_tier = 装备星级 %d" % [si, si + 1],
			int(t["corrode_tier"]) == si + 1, "tier=%d" % int(t["corrode_tier"]))
		for _j in range(20):
			_s._equip_sys._eq_on_hit(u, t, 100)
		_ok("076 si=%d ★仍受 5 层上限(灌 20 次暴击也是 5)" % si,
			int(t["corrode_stacks"]) == 5, "stacks=%d" % int(t["corrode_stacks"]))
	# ★带弓箭羁绊时用【羁绊档位】, 且不把已有的高档位降下去
	_s._units.clear()
	var saved = _s._synergy._by_side
	_s._synergy._by_side = {"left": {"弓箭": 3}, "right": {}}
	var w: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, 300.0), 3000.0), "p2eq_076", 1)
	var wt: Dictionary = _mk("basic", "right", Vector2(-100.0, 300.0), 9000.0)
	_s._last_atk_crit = true
	_s._equip_sys._eq_on_hit(w, wt, 100)
	_ok("076 ★1★ 装备 + 弓箭 3 档 → tier 取【羁绊的 3】不是星级的 1",
		int(wt["corrode_tier"]) == 3, "tier=%d" % int(wt["corrode_tier"]))
	wt["corrode_tier"] = 3
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._equip_sys._eq_on_hit(w, wt, 100)
	_ok("076 ★不把目标身上已有的 3 档腐蚀降成 1 档(取 max, 否则等于自己削自己队伍)",
		int(wt["corrode_tier"]) == 3, "tier=%d" % int(wt["corrode_tier"]))
	# ★★真的接上羁绊的消费侧: 满 5 层的目标受伤会被放大(vuln_mult) —— 不是写了没人读
	var vic: Dictionary = _mk("basic", "right", Vector2(0.0, 300.0), 9000.0)
	vic["corrode_stacks"] = 5
	vic["corrode_tier"] = 1                      # 每层 +2% ⇒ ×1.10
	var v0: float = float(vic["hp"])
	var plain: Dictionary = _mk("fortune", "left", Vector2(-200.0, 300.0), 3000.0)
	_s._damage._apply_damage_from(plain, vic, 100, Color("#ffffff"))
	_ok("076 ★★共用的是羁绊那套 corrode_stacks(满 5 层·1 档 → 100 打成 110, 再 +10% 转真伤 = 121)",
		absf(v0 - float(vic["hp"]) - 121.0) < 0.51, "实掉 %.1f 期望 121" % (v0 - float(vic["hp"])))
	_s._synergy._by_side = saved
	_s._last_atk_crit = false
	_s._units.clear()


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
