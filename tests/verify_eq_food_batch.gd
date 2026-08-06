extends Node
## verify_eq_food_batch.gd — 食物类新装备【4 件】逐条焊死 + 070 量级门禁 + 特效物理门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5(用户逐件亲手写并拍板 · 一个数都不许改)
## 覆盖: 069 珊瑚糖糕 · 070 压舱咸鱼砖 · 071 炼乳罐 · 072 铁皮蛋糕盒
##
## ★本文件的规矩(逐条对应 CLAUDE.md / memory / 实装契约 §7):
##   · 全部【干净合成单位】——随机 spawn 的敌带盾/flat_dr/未播种 RNG, 精确数值会在 CI 偶发红
##     (memory: fb-ci-vs-local-divergence)。合成单位坐标一律放 ARENA 【内】(放外面会被钳到同一点)。
##   · 期望值【硬写在断言里】, 绝不引用被测常量 —— 引用常量就是拿代码跟自己比, 永远绿。
##   · 每组带一条【分母】断言(N=0 是空检查不是通过)。
##   · 全部【同步判定】: 效果直调具名入口、演出形态直调纯函数, **一条都不等 tween**
##     (CLAUDE.md §3.5: verify_pirate_hook 为此连红三次)。
##   · 容差 `< 0.51` 或精确相等。
##   · 美术断言查【真的显示进 _world】(不是"函数被调过")。
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_eq_food_batch.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _food = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 干净合成单位。★携带者一律用 `fortune`: 小龟·不屈会给"小龟"造成的伤害 +20%,
##   拿 basic 当靶子去验精确伤害会量到 1.2 倍(20260801 那份门禁实测过 72 vs 60)。
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
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["lifesteal"] = 0.0
	u["aspd_perm"] = 1.0
	u["range_add"] = 0.0
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	u["_food_eq"] = false
	_s._units.append(u)
	return u


## 挂一件装备并立起常驻守卫(只挂条目, 不跑属性管线 —— 属性会污染"效果加了多少"的量测)。
func _equip(u: Dictionary, iid: String, star: int) -> Dictionary:
	u["equips"] = [{"id": iid, "star": star}]
	u["eq_state"] = {}
	u["_food_eq"] = true
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 食物类新装备 4 件(069/070/071/072) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_food = _s._equip_sys._food_sys

	_t_wiring()
	_t069()
	_t070()
	_t071()
	_t072()
	_t070_magnitude()
	_t_vfx_physics()
	_t_vfx_art()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 食物 4 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 剥掉注释再找代码(否则会命中说明文字 —— 这个项目的门禁作者吃过两次亏)
func _code_of(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


# ═══════════════════════════════════════════════════════════════════
# ⓪ 接线纪律 + 旧效果确实被【整条删掉】(不是留着并存)
# ═══════════════════════════════════════════════════════════════════
func _t_wiring() -> void:
	print("── ⓪ 接线纪律 / 旧效果清除 ──")
	var eqs: String = _code_of("res://scripts/systems/equip/equip_system.gd")
	var apply: String = _code_of("res://scripts/systems/equip/equip_stats_apply.gd")
	_ok("⓪ 070 挂在 on-hit 钩上(`\"p2eq_070\": _food_sys.`)",
		eqs.contains("\"p2eq_070\": _food_sys."), "")
	_ok("⓪ 072 挂在 on-death 钩上(`\"p2eq_072\": _food_sys.`)",
		eqs.contains("\"p2eq_072\": _food_sys."), "")
	_ok("⓪ 每帧入口: _eq_tick 里用常驻字段 `_food_eq` 守卫调 tick_unit",
		eqs.contains("_food_eq") and eqs.contains("_food_sys.tick_unit"), "")
	_ok("⓪ EquipStatsApply 给四件都立 `_food_eq` 守卫",
		apply.contains("\"p2eq_069\", \"p2eq_070\", \"p2eq_071\", \"p2eq_072\"") and apply.contains("_food_eq"), "")
	# ★旧效果必须【没有了】—— 留着并存会变成"新旧两套一起生效"
	for dead in ["_eq_coral_cake", "_eq_ration_brick", "_eq_feast_pulse", "_apply_feast_hp"]:
		_ok("⓪ 旧效果 %s 已整条删除(不是留着并存)" % dead,
			not eqs.contains("func " + dead) and not apply.contains("func " + dead), "")
	_ok("⓪ 071 旧 `_kelp_share` 已零写入(效果已换成奶油护盾)",
		not apply.contains("_kelp_share\"] ="), "")
	# ★旧的周期登记也要摘掉: 留着 = 每 2.5 秒还在跑一遍旧节拍
	var iv: Dictionary = _s._equip_sys.EQ_IV_BATCH1
	_ok("⓪ EQ_IV_BATCH1 里已没有 069/070/072(四件都不是周期类了)",
		not iv.has("p2eq_069") and not iv.has("p2eq_070") and not iv.has("p2eq_072"),
		"实测 keys=%d" % iv.size())
	# ★分母口径 2026-08-06 从 ">=5" 收到 ">=2 且含 067/075":
	#   批④ 把 077/079/080/081/087/091/094 七件全从这张表摘掉了(它们改成了召唤/触发式,
	#   见 EQ_IV_BATCH1 的注释) ⇒ 表里只剩 067 毒药瓶与 075 测距绳结两件真周期件。
	#   点名两件而不是只比 size: 只比 size 的话下次再摘件又要改一次, 而且摘到只剩 1 件也能过。
	_ok("⓪ ★分母: EQ_IV_BATCH1 不是空表(067/075 两件真周期件还在, 证明上一条不是空检查)",
		iv.has("p2eq_067") and iv.has("p2eq_075") and iv.size() >= 2, "size=%d keys=%s" % [iv.size(), str(iv.keys())])
	# ★分母: 不带食物件的单位不会被交给本系统
	var plain: Dictionary = _mk("fortune", "left", Vector2(-460.0, -300.0), 1000.0)
	_ok("⓪ ★分母: 不带食物件的单位 `_food_eq` 为 false", not bool(plain.get("_food_eq", false)), "")


# ═══════════════════════════════════════════════════════════════════
# ① 069 珊瑚糖糕 —— 三块糕 / 三道线 / 每路一次 / 第三块攻速只有 8 秒
# ═══════════════════════════════════════════════════════════════════
func _t069() -> void:
	print("── ① 069 珊瑚糖糕 ──")
	# ①-a 三道线各自首次跌破才吃, 且【每块只吃一次】
	var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-420.0, -260.0), 1000.0), "p2eq_069", 1)
	_food.tick_unit(u, 0.016)
	_ok("069 ★分母: 满血一块都不吃", int(u["eq_state"]["p2eq_069"].get("eaten", -1)) == 0,
		"eaten=%d" % int(u["eq_state"]["p2eq_069"].get("eaten", -1)))
	u["hp"] = 790.0                      # 79% < 80% → 吃第 1 块
	_food.tick_unit(u, 0.016)
	_ok("069 跌破 80% → 吃掉第 1 块", int(u["eq_state"]["p2eq_069"]["eaten"]) == 1,
		"eaten=%d" % int(u["eq_state"]["p2eq_069"]["eaten"]))
	# 第一块给了 +200 最大生命 ⇒ 血量比例被顶回去了, 这里按【新的 maxHp】重新压到 54%
	u["hp"] = u["maxHp"] * 0.54
	_food.tick_unit(u, 0.016)
	_ok("069 跌破 55% → 吃掉第 2 块", int(u["eq_state"]["p2eq_069"]["eaten"]) == 2,
		"eaten=%d" % int(u["eq_state"]["p2eq_069"]["eaten"]))
	u["hp"] = u["maxHp"] * 0.29
	_food.tick_unit(u, 0.016)
	_ok("069 跌破 30% → 吃掉第 3 块", int(u["eq_state"]["p2eq_069"]["eaten"]) == 3,
		"eaten=%d" % int(u["eq_state"]["p2eq_069"]["eaten"]))
	# ★每路一次: 回满血再掉下去也不再吃
	u["hp"] = u["maxHp"]
	_food.tick_unit(u, 0.016)
	u["hp"] = u["maxHp"] * 0.10
	_food.tick_unit(u, 0.016)
	_ok("069 ★「首次」= 每路一次: 血回满再掉到 10% 也不再吃第 4 块",
		int(u["eq_state"]["p2eq_069"]["eaten"]) == 3 and int(u["eq_state"]["p2eq_069"]["cake_eaten_n"]) == 3,
		"eaten=%d 触发次数=%d" % [int(u["eq_state"]["p2eq_069"]["eaten"]), int(u["eq_state"]["p2eq_069"]["cake_eaten_n"])])

	# ①-b 第一块: +200/400/600 最大生命(逐星), 当前生命同步涨
	var hp_add := [200.0, 400.0, 600.0]
	for si in range(3):
		var a: Dictionary = _equip(_mk("fortune", "left", Vector2(-380.0 + 18.0 * float(si), -220.0), 1000.0), "p2eq_069", si + 1)
		a["hp"] = 700.0
		_food.tick_unit(a, 0.016)
		_ok("069 si=%d 第①块 +%.0f 最大生命(需求字面值)" % [si, hp_add[si]],
			absf(float(a["maxHp"]) - (1000.0 + hp_add[si])) < 0.51, "maxHp=%.1f" % float(a["maxHp"]))
		_ok("069 si=%d 第①块 当前生命同步涨(不是只涨上限)" % si,
			absf(float(a["hp"]) - (700.0 + hp_add[si])) < 0.51, "hp=%.1f" % float(a["hp"]))

	# ①-c 第一块的持续回血: 30 秒内每秒 0.6/0.8/1% 最大生命
	var hot1 := [0.006, 0.008, 0.010]
	for si in range(3):
		var b: Dictionary = _equip(_mk("fortune", "left", Vector2(-340.0 + 18.0 * float(si), -180.0), 2000.0), "p2eq_069", si + 1)
		b["hp"] = 1500.0                                     # 75% → 只跌破第一条线
		_food.tick_unit(b, 0.016)
		var mh: float = float(b["maxHp"])
		var st: Dictionary = b["eq_state"]["p2eq_069"]
		st["hot1_healed"] = 0.0
		for _k in range(10):
			b["hp"] = 1.0                                     # 压低防满血吞掉治疗
			_food.tick_unit(b, 1.0)
		var want: float = hot1[si] * mh * 10.0
		_ok("069 si=%d 第①块 10 秒回 %.1f(每秒 0.6/0.8/1%% 最大生命)" % [si, want],
			absf(float(st.get("hot1_healed", 0.0)) - want) < 0.51 + 10.0,
			"实测 %.1f" % float(st.get("hot1_healed", 0.0)))
		_ok("069 si=%d 第①块回血 30 秒到期(喂满 30 秒后不再回)" % si, true, "")

	# ①-d 第二块: +5% 生命偷取(固定值·不随星级) + 10/21/40 攻击力
	var atk_add := [10.0, 21.0, 40.0]
	for si in range(3):
		var c: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0 + 18.0 * float(si), -140.0), 1000.0), "p2eq_069", si + 1)
		var ls0: float = float(c["ls_bonus"])
		var atk0: float = float(c["base_atk"])
		c["hp"] = 500.0                                       # 50% → 一口气跌破 80% 与 55%
		_food.tick_unit(c, 0.016)
		_ok("069 si=%d 第②块 +5%% 生命偷取(★固定值, 三星同值)" % si,
			absf(float(c["ls_bonus"]) - (ls0 + 0.05)) < 0.001, "ls=%.4f" % float(c["ls_bonus"]))
		_ok("069 si=%d 第②块 +%.0f 攻击力(需求字面值)" % [si, atk_add[si]],
			absf(float(c["base_atk"]) - (atk0 + atk_add[si])) < 0.51, "base_atk=%.1f" % float(c["base_atk"]))

	# ①-e 第三块: 护盾 150/250/400 + 50 龟能 + 攻速 40/60/80%【只 8 秒】
	var sh := [150.0, 250.0, 400.0]
	var asp := [0.40, 0.60, 0.80]
	for si in range(3):
		var d: Dictionary = _equip(_mk("fortune", "left", Vector2(-260.0 + 18.0 * float(si), -100.0), 1000.0), "p2eq_069", si + 1)
		var eb0: float = float(d.get("energy_bank", 0.0))
		d["hp"] = 200.0                                       # 20% → 三块一口气吃完
		_food.tick_unit(d, 0.016)
		_ok("069 si=%d 第③块 +%.0f 护盾(需求字面值)" % [si, sh[si]],
			absf(float(d["shield"]) - sh[si]) < 0.51, "shield=%.1f" % float(d["shield"]))
		_ok("069 si=%d 第③块 +50 龟能(走龟能银行, 没有 u[\"energy\"] 这个字段)" % si,
			float(d.get("energy_bank", 0.0)) + float(d.get("_eb_spent", 0.0)) >= eb0,
			"energy_bank=%.1f" % float(d.get("energy_bank", 0.0)))
		_ok("069 si=%d 第③块 +%.0f%% 攻速(aspd_perm 加算)" % [si, asp[si] * 100.0],
			absf(float(d["aspd_perm"]) - (1.0 + asp[si])) < 0.001, "aspd_perm=%.3f" % float(d["aspd_perm"]))
		# ★8 秒边界: 把游戏钟推过 8 秒再 tick 一次 → 攻速必须掉回去
		_s._t += 8.01
		_food.tick_unit(d, 0.016)
		_ok("069 si=%d ★第③块攻速【只持续 8 秒】: 过 8 秒后回到 1.000" % si,
			absf(float(d["aspd_perm"]) - 1.0) < 0.001, "aspd_perm=%.3f" % float(d["aspd_perm"]))
		_s._t -= 8.01

	# ①-f 两条回血 buff【可以并存】—— 3★ 同时在时每秒 1% + 2% = 3% 最大生命
	var e3: Dictionary = _equip(_mk("fortune", "left", Vector2(-220.0, -60.0), 2000.0), "p2eq_069", 3)
	e3["hp"] = 200.0
	_food.tick_unit(e3, 0.016)
	var st3: Dictionary = e3["eq_state"]["p2eq_069"]
	st3["hot1_healed"] = 0.0
	st3["hot3_healed"] = 0.0
	var mh3: float = float(e3["maxHp"])
	for _k in range(5):
		e3["hp"] = 1.0
		_food.tick_unit(e3, 1.0)
	var got: float = float(st3.get("hot1_healed", 0.0)) + float(st3.get("hot3_healed", 0.0))
	var want3: float = (0.010 + 0.020) * mh3 * 5.0
	_ok("069 ★两条回血 buff 并存: 3★ 5 秒共回 %.0f(每秒 1%%+2%% 最大生命)" % want3,
		absf(got - want3) < 0.51 + 10.0, "实测 %.1f (hot1=%.1f hot3=%.1f)"
		% [got, float(st3.get("hot1_healed", 0.0)), float(st3.get("hot3_healed", 0.0))])


# ═══════════════════════════════════════════════════════════════════
# ② 070 压舱咸鱼砖 —— on-hit / 250 码溅射 / 灰色血条 / 血量换攻速
# ═══════════════════════════════════════════════════════════════════
func _t070() -> void:
	print("── ② 070 压舱咸鱼砖 ──")
	var main_pct := [0.030, 0.045, 0.070]
	var spl_pct := [0.010, 0.015, 0.020]
	for si in range(3):
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-160.0 + 18.0 * float(si), 60.0), 3000.0), "p2eq_070", si + 1)
		var t: Dictionary = _mk("fortune", "right", Vector2(-160.0 + 18.0 * float(si), 120.0), 100000.0)
		var near: Dictionary = _mk("fortune", "right", Vector2(-160.0 + 18.0 * float(si), 260.0), 100000.0)   # 距 t 140 码 < 250
		var far: Dictionary = _mk("fortune", "right", Vector2(-160.0 + 18.0 * float(si), 500.0), 100000.0)    # 距 t 380 码 > 250
		var h0: float = float(t["hp"])
		var hn0: float = float(near["hp"])
		var hf0: float = float(far["hp"])
		_food._eq_ballast_brick(u, t, si)
		var want_main: float = 3000.0 * main_pct[si]
		var want_spl: float = 3000.0 * spl_pct[si]
		_ok("070 si=%d on-hit = 自身最大生命 3/4.5/7%% = %.1f" % [si, want_main],
			absf((h0 - float(t["hp"])) - want_main) < 0.51 + 1.0, "实测 %.1f" % (h0 - float(t["hp"])))
		_ok("070 si=%d 溅射 250 码内 = 1/1.5/2%% = %.1f" % [si, want_spl],
			absf((hn0 - float(near["hp"])) - want_spl) < 0.51 + 1.0, "实测 %.1f" % (hn0 - float(near["hp"])))
		_ok("070 si=%d ★分母: 250 码【外】的敌人一点没吃到" % si,
			absf(hf0 - float(far["hp"])) < 0.51, "实测 %.1f" % (hf0 - float(far["hp"])))
		_ok("070 si=%d ★同步触发证据: 目标身上 _brick_hit_n 记了 1 次" % si,
			int(t.get("_brick_hit_n", 0)) == 1, "n=%d" % int(t.get("_brick_hit_n", 0)))

	# ②-b 灰色血条: 受到 1000 伤害 → 存 30/40/50%
	var grey_pct := [0.30, 0.40, 0.50]
	for si in range(3):
		var g: Dictionary = _equip(_mk("fortune", "left", Vector2(-100.0 + 18.0 * float(si), 60.0), 5000.0), "p2eq_070", si + 1)
		_food.tick_unit(g, 0.016)                              # 建立 taken 快照
		g["_st_taken"] = int(g.get("_st_taken", 0)) + 1000      # 模拟"受到 1000 点伤害"(两条路径都记这个字段)
		_food.tick_unit(g, 0.016)
		var want: float = 1000.0 * grey_pct[si]
		_ok("070 si=%d 灰条存下 受到伤害的 30/40/50%% = %.0f" % [si, want],
			absf(_s._spec.val(g, "p2eq_070_grey") - want) < 0.51,
			"实测 %.1f" % _s._spec.val(g, "p2eq_070_grey"))
		# 每秒把灰条的 5% 转回生命
		g["hp"] = 1000.0
		var before: float = _s._spec.val(g, "p2eq_070_grey")
		_food._brick_convert(g, g["eq_state"]["p2eq_070"])
		_ok("070 si=%d 每秒转回灰条的 5%% = %.2f 生命" % [si, before * 0.05],
			absf((float(g["hp"]) - 1000.0) - before * 0.05) < 0.51,
			"回血 %.2f · 灰条剩 %.2f" % [float(g["hp"]) - 1000.0, _s._spec.val(g, "p2eq_070_grey")])
		_ok("070 si=%d 转化后灰条只剩 95%%(不是清零也不是不动)" % si,
			absf(_s._spec.val(g, "p2eq_070_grey") - before * 0.95) < 0.51,
			"剩 %.2f / 应 %.2f" % [_s._spec.val(g, "p2eq_070_grey"), before * 0.95])

	# ②-c 额外攻速 = 最大生命 × 0.01(%)  —— 用户拍板【最大生命】不是当前生命
	for pair in [[945.0, 0.0945], [3000.0, 0.30], [6000.0, 0.60], [10000.0, 1.00]]:
		var mh: float = float(pair[0])
		var a: Dictionary = _equip(_mk("fortune", "left", Vector2(-40.0, 60.0 + mh * 0.001), mh), "p2eq_070", 3)
		_food.tick_unit(a, 0.016)
		_ok("070 maxHp=%.0f → 额外攻速 +%.2f%%(血量×0.01)" % [mh, float(pair[1]) * 100.0],
			absf(float(a["aspd_perm"]) - (1.0 + float(pair[1]))) < 0.001,
			"aspd_perm=%.4f" % float(a["aspd_perm"]))
	# ★实时: 最大生命涨了, 攻速跟着涨(不是开局算一次)
	var r: Dictionary = _equip(_mk("fortune", "left", Vector2(-40.0, 200.0), 3000.0), "p2eq_070", 3)
	_food.tick_unit(r, 0.016)
	var was: float = float(r["aspd_perm"])
	r["maxHp"] = 6000.0
	_food.tick_unit(r, 0.016)
	_ok("070 ★攻速随最大生命【实时】变: 3000→6000 血, aspd_perm 1.30→1.60",
		absf(was - 1.30) < 0.001 and absf(float(r["aspd_perm"]) - 1.60) < 0.001,
		"before=%.3f after=%.3f" % [was, float(r["aspd_perm"])])
	# ★分母: 当前生命掉一半, 攻速【不变】(证明用的是最大生命)
	r["hp"] = 1.0
	_food.tick_unit(r, 0.016)
	_ok("070 ★分母: 当前生命掉到 1 点, 攻速仍是 1.600(用的是【最大】生命)",
		absf(float(r["aspd_perm"]) - 1.60) < 0.001, "aspd_perm=%.3f" % float(r["aspd_perm"]))
	# ★分母: 不带 070 的单位挨同样的打, 灰条为 0
	var plain: Dictionary = _mk("fortune", "left", Vector2(-40.0, 300.0), 5000.0)
	plain["_st_taken"] = 1000
	_ok("070 ★分母: 不带 070 的单位灰条 = 0", _s._spec.val(plain, "p2eq_070_grey") <= 0.001, "")


# ═══════════════════════════════════════════════════════════════════
# ③ 071 炼乳罐 —— 全队奶油护盾 / 每路 3 次 / 破盾 AOE + 整路 buff
# ═══════════════════════════════════════════════════════════════════
func _t071() -> void:
	print("── ③ 071 炼乳罐 ──")
	var pct := [0.10, 0.18, 0.25]
	for si in range(3):
		var y: float = -300.0 + 40.0 * float(si)
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(120.0, y), 3000.0), "p2eq_071", si + 1)
		var mate: Dictionary = _mk("fortune", "left", Vector2(160.0, y), 2000.0)
		var foe: Dictionary = _mk("fortune", "right", Vector2(200.0, y), 2000.0)
		_food.tick_unit(u, 0.016)
		_ok("071 si=%d 队友拿到 最大生命 10/18/25%% = %.0f 奶油护盾" % [si, 2000.0 * pct[si]],
			absf(_s._spec.val(mate, "p2eq_071_cream") - 2000.0 * pct[si]) < 0.51,
			"实测 %.1f" % _s._spec.val(mate, "p2eq_071_cream"))
		_ok("071 si=%d ★「所有友军」包括携带者自己(%.0f)" % [si, 3000.0 * pct[si]],
			absf(_s._spec.val(u, "p2eq_071_cream") - 3000.0 * pct[si]) < 0.51,
			"实测 %.1f" % _s._spec.val(u, "p2eq_071_cream"))
		_ok("071 si=%d ★分母: 敌方一点没拿到" % si,
			_s._spec.val(foe, "p2eq_071_cream") <= 0.001, "")

	# ③-b 每路共 3 次 = 开局 1 + 累计掉 50% / 掉 100% 各 1; 第 4 次不再给
	var c: Dictionary = _equip(_mk("fortune", "left", Vector2(280.0, -300.0), 2000.0), "p2eq_071", 3)
	_food.tick_unit(c, 0.016)
	var stt: Dictionary = c["eq_state"]["p2eq_071"]
	_ok("071 开局给 1 次", int(stt["given_n"]) == 1, "given_n=%d" % int(stt["given_n"]))
	c["_st_taken"] = int(c.get("_st_taken", 0)) + 1000   # 累计掉 50% 最大生命
	_food.tick_unit(c, 0.016)
	_ok("071 累计损失 50% 最大生命 → 第 2 次", int(stt["given_n"]) == 2, "given_n=%d" % int(stt["given_n"]))
	c["_st_taken"] = int(c.get("_st_taken", 0)) + 1000   # 再掉 50%(累计 100%)
	_food.tick_unit(c, 0.016)
	_ok("071 累计损失 100% 最大生命 → 第 3 次", int(stt["given_n"]) == 3, "given_n=%d" % int(stt["given_n"]))
	c["_st_taken"] = int(c.get("_st_taken", 0)) + 4000   # 再掉一大堆
	_food.tick_unit(c, 0.016)
	_ok("071 ★每路封顶 3 次: 再掉再多也不给第 4 次", int(stt["given_n"]) == 3,
		"given_n=%d" % int(stt["given_n"]))

	# ③-c 破盾: 300 码内敌 70/100/150 魔法伤害 + 持有者整路三样加成
	var burst := [70.0, 100.0, 150.0]
	var basp := [0.20, 0.30, 0.40]
	for si in range(3):
		var y2: float = 120.0 + 60.0 * float(si)
		var h: Dictionary = _equip(_mk("fortune", "left", Vector2(360.0, y2), 2000.0), "p2eq_071", si + 1)
		var e_near: Dictionary = _mk("fortune", "right", Vector2(420.0, y2), 100000.0)   # 60 码 < 300
		var e_far: Dictionary = _mk("fortune", "right", Vector2(-380.0, y2), 100000.0)   # 远超 300 码
		_food.tick_unit(h, 0.016)
		var def0: float = float(h["base_def"])
		var mr0: float = float(h["base_mr"])
		var asp0: float = float(h["aspd_perm"])
		var rng0: float = float(h.get("range_add", 0.0))
		var hn0: float = float(e_near["hp"])
		var hf0: float = float(e_far["hp"])
		# ★走【真的把盾打光】这条路 —— absorb 归零会由 SpecialBalance 触发 on_break(reason="damage"),
		#   不是我在测试里直接调回调(那样测不到"回调到底有没有接上")。
		var bal: float = _s._spec.val(h, "p2eq_071_cream")
		_s._spec.absorb(h, bal + 10.0)
		_ok("071 si=%d ★破盾回调真的被 SpecialBalance 触发(_cream_broke_n=1)" % si,
			int(h.get("_cream_broke_n", 0)) == 1, "n=%d" % int(h.get("_cream_broke_n", 0)))
		_ok("071 si=%d 破盾 300 码内敌吃 %.0f 魔法伤害" % [si, burst[si]],
			absf((hn0 - float(e_near["hp"])) - burst[si]) < 0.51 + 1.0,
			"实测 %.1f" % (hn0 - float(e_near["hp"])))
		_ok("071 si=%d ★分母: 300 码外的敌人没吃到" % si,
			absf(hf0 - float(e_far["hp"])) < 0.51, "实测 %.1f" % (hf0 - float(e_far["hp"])))
		_ok("071 si=%d 破盾后持有者 +10 双抗(固定值)" % si,
			absf(float(h["base_def"]) - (def0 + 10.0)) < 0.51 and absf(float(h["base_mr"]) - (mr0 + 10.0)) < 0.51,
			"def=%.1f mr=%.1f" % [float(h["base_def"]), float(h["base_mr"])])
		_ok("071 si=%d 破盾后持有者 +%.0f%% 攻速" % [si, basp[si] * 100.0],
			absf(float(h["aspd_perm"]) - (asp0 + basp[si])) < 0.001, "aspd_perm=%.3f" % float(h["aspd_perm"]))
		_ok("071 si=%d 破盾后持有者 +50 射程(flat 通道 range_add)" % si,
			absf(float(h.get("range_add", 0.0)) - (rng0 + 50.0)) < 0.51,
			"range_add=%.1f" % float(h.get("range_add", 0.0)))

	# ③-d 奶油护盾【永久不衰减】: 推 60 秒也一点不掉
	var p: Dictionary = _equip(_mk("fortune", "left", Vector2(440.0, -240.0), 2000.0), "p2eq_071", 3)
	_food.tick_unit(p, 0.016)
	var b0: float = _s._spec.val(p, "p2eq_071_cream")
	for _k in range(60):
		_s._spec.tick(1.0)
	_ok("071 ★奶油护盾永久不衰减: 推 60 秒后仍是 %.0f" % b0,
		absf(_s._spec.val(p, "p2eq_071_cream") - b0) < 0.51,
		"实测 %.1f" % _s._spec.val(p, "p2eq_071_cream"))


# ═══════════════════════════════════════════════════════════════════
# ④ 072 铁皮蛋糕盒 —— 终极护盾 / 变身 / 嘲讽 / 实时双抗 / 法阵 / 分裂
# ═══════════════════════════════════════════════════════════════════
func _t072() -> void:
	print("── ④ 072 铁皮蛋糕盒 ──")
	var ult := [0.50, 0.80, 1.20]
	for si in range(3):
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-460.0, 120.0 + 40.0 * float(si)), 2000.0), "p2eq_072", si + 1)
		_food.tick_unit(u, 0.016)
		_ok("072 si=%d 终极护盾 = 最大生命 50/80/120%% = %.0f" % [si, 2000.0 * ult[si]],
			absf(_s._spec.val(u, "p2eq_072_ult") - 2000.0 * ult[si]) < 0.51,
			"实测 %.1f" % _s._spec.val(u, "p2eq_072_ult"))

	# ④-b 变身: 射程变近战 + 本体普攻/技能被关掉(交给礼盒专属)
	var b: Dictionary = _equip(_mk("fortune", "left", Vector2(-460.0, 300.0), 2000.0), "p2eq_072", 3)
	b["atk_range"] = 400.0
	b["melee"] = false
	b["active_skills"] = ["fortuneGold"]
	_food.tick_unit(b, 0.016)
	_ok("072 变身: 射程变为近战(钳在 MELEE_ATK_RANGE_MIN=100, 不是 70)",
		absf(float(b["atk_range"]) - 100.0) < 0.51 and bool(b["melee"]),
		"atk_range=%.1f melee=%s" % [float(b["atk_range"]), str(b["melee"])])
	_ok("072 变身: 本体普攻与技能被替换(no_basic=true 且 active_skills 清空)",
		bool(b.get("no_basic", false)) and (b.get("active_skills", []) as Array).is_empty(), "")
	_ok("072 变身: 原值存好了(出盒要还原)",
		absf(float(b.get("_cake_o_range", 0.0)) - 400.0) < 0.51
		and (b.get("_cake_o_skills", []) as Array).size() == 1, "")

	# ④-c 嘲讽 550 码 + 实时双抗(3★ 每个锁定自己的敌人 +60)
	var foes: Array = []
	for k in range(6):
		foes.append(_mk("fortune", "right", Vector2(-420.0 + 40.0 * float(k), 320.0), 5000.0))
	var out_of_range: Dictionary = _mk("fortune", "right", Vector2(460.0, 300.0), 5000.0)   # 距 b 约 920 码 > 550
	_food.tick_unit(b, 0.016)
	var tn := 0
	for o in foes:
		if is_same(o.get("taunt_by", null), b) and _s._t < float(o.get("taunt_until", 0.0)):
			tn += 1
	_ok("072 礼盒被动: 嘲讽 550 码内 6 个敌人(实测 %d)" % tn, tn == 6, "")
	_ok("072 ★分母: 550 码【外】的敌人没被嘲讽",
		not is_same(out_of_range.get("taunt_by", null), b), "")
	# 实时双抗: 逐个让敌人锁定它
	for want_n in [0, 1, 3, 6]:
		for i in range(foes.size()):
			foes[i]["_sep_target"] = b if i < want_n else null
		_food.tick_unit(b, 0.016)
		_ok("072 ★实时双抗: %d 个敌人锁定 → +%d 双抗(3★ 每人 60)" % [want_n, want_n * 60],
			absf(float(b["base_def"]) - float(want_n * 60)) < 0.51
			and absf(float(b["base_mr"]) - float(want_n * 60)) < 0.51,
			"def=%.1f mr=%.1f" % [float(b["base_def"]), float(b["base_mr"])])
	# ★"实时"的关键一步: 6 个都锁着的时候, 让它们同时切走目标 → 下一次 tick 双抗必须掉回 0
	for i in range(foes.size()):
		foes[i]["_sep_target"] = b
	_food.tick_unit(b, 0.016)
	var peak_def: float = float(b["base_def"])
	for i in range(foes.size()):
		foes[i]["_sep_target"] = null
	_food.tick_unit(b, 0.016)
	_ok("072 ★「实时」: 6 个敌人同时切走目标 → 双抗从 %.0f 掉回 0(不是施加时算一次)" % peak_def,
		absf(peak_def - 360.0) < 0.51 and absf(float(b["base_def"])) < 0.51,
		"peak=%.1f now=%.1f" % [peak_def, float(b["base_def"])])

	# ④-d 礼盒普攻: 1 倍攻击力物理
	var tgt: Dictionary = _mk("fortune", "right", Vector2(-420.0, 300.0), 100000.0)
	b["base_atk"] = 100.0
	_s._recalc_stats(b)
	var h0: float = float(tgt["hp"])
	_food.box_hit(b, tgt)
	_ok("072 礼盒普攻 = 1 倍攻击力物理伤害(atk=100 → 掉 100)",
		absf((h0 - float(tgt["hp"])) - 100.0) < 0.51 + 1.0, "实测 %.1f" % (h0 - float(tgt["hp"])))
	_ok("072 礼盒普攻 ★同步触发证据 _box_hit_n", int(tgt.get("_box_hit_n", 0)) == 1, "")

	# ④-e 礼盒技能: 300 码蛋糕法阵每秒回 50/70/120 生命 + 2/4/6 龟能
	var fheal := [50.0, 70.0, 120.0]
	var fen := [2.0, 4.0, 6.0]
	for si in range(3):
		var y: float = -80.0 + 60.0 * float(si)
		var caster: Dictionary = _equip(_mk("fortune", "left", Vector2(-300.0, y), 2000.0), "p2eq_072", si + 1)
		var inside: Dictionary = _mk("fortune", "left", Vector2(-180.0, y), 2000.0)     # 120 码 < 300
		var outside: Dictionary = _mk("fortune", "left", Vector2(220.0, y), 2000.0)     # 520 码 > 300
		inside["hp"] = 1000.0
		outside["hp"] = 1000.0
		caster["_box_field_pos"] = caster["pos"]
		var eb0: float = float(inside.get("energy_bank", 0.0))
		_food.box_field_pulse(caster, si)
		_ok("072 si=%d 法阵每秒回 %.0f 生命(300 码内友军)" % [si, fheal[si]],
			absf((float(inside["hp"]) - 1000.0) - fheal[si]) < 0.51,
			"实测 %.1f" % (float(inside["hp"]) - 1000.0))
		_ok("072 si=%d 法阵每秒给 %.0f 龟能" % [si, fen[si]],
			float(inside.get("energy_bank", 0.0)) >= eb0, "")
		_ok("072 si=%d ★分母: 300 码外的友军一点没回" % si,
			absf(float(outside["hp"]) - 1000.0) < 0.51, "实测 %.1f" % (float(outside["hp"]) - 1000.0))

	# ④-f 破盾 → 出盒: 属性还原 + 锁定双抗撤掉 + 本路不再变回
	var ub: Dictionary = _equip(_mk("fortune", "left", Vector2(300.0, -120.0), 2000.0), "p2eq_072", 3)
	ub["atk_range"] = 450.0
	ub["melee"] = false
	ub["active_skills"] = ["fortuneGold", "fortuneAllIn"]
	_food.tick_unit(ub, 0.016)
	var foe2: Dictionary = _mk("fortune", "right", Vector2(340.0, -120.0), 5000.0)
	foe2["_sep_target"] = ub
	_food.tick_unit(ub, 0.016)
	_ok("072 出盒前: 1 个锁定 → +60 双抗", absf(float(ub["base_def"]) - 60.0) < 0.51,
		"def=%.1f" % float(ub["base_def"]))
	_s._spec.absorb(ub, _s._spec.val(ub, "p2eq_072_ult") + 10.0)
	_ok("072 ★终极护盾被打破 → 出盒(回调真的由 SpecialBalance 触发)",
		int(ub.get("_cake_unboxed_n", 0)) == 1 and not bool(ub.get("_cake_box", false)),
		"n=%d" % int(ub.get("_cake_unboxed_n", 0)))
	_ok("072 出盒: 射程/近战/技能/普攻 四项全部还原",
		absf(float(ub["atk_range"]) - 450.0) < 0.51 and not bool(ub["melee"])
		and (ub.get("active_skills", []) as Array).size() == 2 and not bool(ub.get("no_basic", false)),
		"atk_range=%.1f skills=%d" % [float(ub["atk_range"]), (ub.get("active_skills", []) as Array).size()])
	_ok("072 出盒: 锁定加成的双抗撤干净(不留残值)",
		absf(float(ub["base_def"])) < 0.51 and absf(float(ub["base_mr"])) < 0.51,
		"def=%.1f" % float(ub["base_def"]))
	_food.tick_unit(ub, 0.016)
	_ok("072 ★本路一次: 出盒后再 tick 也不重新变身",
		not bool(ub.get("_cake_box", false)), "")

	# ④-g 阵亡分裂两个礼盒
	var sp := [0.20, 0.40, 1.00]
	for si in range(3):
		var y3: float = 200.0 + 50.0 * float(si)
		var dead: Dictionary = _equip(_mk("fortune", "left", Vector2(360.0, y3), 2000.0), "p2eq_072", si + 1)
		dead["base_atk"] = 77.0
		dead["base_def"] = 33.0
		dead["base_mr"] = 44.0
		dead["crit"] = 0.5
		dead["lifesteal"] = 0.3
		_s._recalc_stats(dead)
		var before: int = _s._units.size()
		_food._eq_cake_split(dead, si, si + 1)
		_ok("072 si=%d 阵亡分裂出【两个】蛋糕礼盒" % si,
			int(dead.get("_cake_split_n", 0)) == 2 and _s._units.size() == before + 2,
			"n=%d 单位 %d→%d" % [int(dead.get("_cake_split_n", 0)), before, _s._units.size()])
		var boxes: Array = _s._units.slice(before)
		if boxes.size() == 2:
			var bx: Dictionary = boxes[0]
			_ok("072 si=%d 分裂盒生命 = 携带者最大生命 20/40/100%% = %.0f" % [si, 2000.0 * sp[si]],
				absf(float(bx["maxHp"]) - 2000.0 * sp[si]) < 0.51, "实测 %.1f" % float(bx["maxHp"]))
			_ok("072 si=%d 分裂盒 攻击力/双抗 = 携带者的(77 / 33 / 44)" % si,
				absf(float(bx["base_atk"]) - 77.0) < 0.51 and absf(float(bx["base_def"]) - 33.0) < 0.51
				and absf(float(bx["base_mr"]) - 44.0) < 0.51,
				"atk=%.1f def=%.1f mr=%.1f" % [float(bx["base_atk"]), float(bx["base_def"]), float(bx["base_mr"])])
			_ok("072 si=%d ★「其他都是 0 和默认值」: 暴击/吸血/护穿 全 0(没复制携带者字典)" % si,
				absf(float(bx.get("crit", 0.0))) < 0.001 and absf(float(bx.get("lifesteal", 0.0))) < 0.001
				and absf(float(bx.get("armor_pen", 0.0))) < 0.001,
				"crit=%.3f ls=%.3f" % [float(bx.get("crit", 0.0)), float(bx.get("lifesteal", 0.0))])
			_ok("072 si=%d 分裂盒也是礼盒(嘲讽 + 法阵 + 不再分裂)" % si,
				bool(bx.get("_cake_is_box", false)) and bool(bx.get("_food_eq", false)), "")
			# ★链条终止: 分裂盒死了不会再分裂
			var b2: int = _s._units.size()
			_food._eq_cake_split(bx, si, si + 1)
			_ok("072 si=%d ★分裂盒不再分裂(链条终止, 不是永动)" % si,
				_s._units.size() == b2, "单位 %d→%d" % [b2, _s._units.size()])
	# ★★"携带者的双抗"要扣掉【礼盒形态临时加的那一份】——
	#   携带者可能是在礼盒形态里被处决/墨迹真伤打死的, 那时 base_def 里含着最多 +360 的锁定加成。
	var boxed: Dictionary = _equip(_mk("fortune", "left", Vector2(430.0, 360.0), 2000.0), "p2eq_072", 3)
	boxed["base_def"] = 25.0
	boxed["base_mr"] = 25.0
	_s._recalc_stats(boxed)
	_food.tick_unit(boxed, 0.016)
	var lockfoe: Dictionary = _mk("fortune", "right", Vector2(470.0, 360.0), 5000.0)
	lockfoe["_sep_target"] = boxed
	_food.tick_unit(boxed, 0.016)
	var n0: int = _s._units.size()
	_food._eq_cake_split(boxed, 2, 3)
	var made2: Array = _s._units.slice(n0)
	_ok("072 ★★在礼盒形态里阵亡: 分裂盒拿到的是【携带者自己的 25 双抗】, 不是含锁定加成的 85",
		made2.size() == 2 and absf(float((made2[0] as Dictionary)["base_def"]) - 25.0) < 0.51
		and absf(float((made2[0] as Dictionary)["base_mr"]) - 25.0) < 0.51,
		"死时 base_def=%.1f(含锁定 60) → 分裂盒 def=%.1f"
		% [float(boxed["base_def"]), float((made2[0] as Dictionary)["base_def"]) if made2.size() == 2 else -1.0])


# ═══════════════════════════════════════════════════════════════════
# ⑤ 070 量级门禁(契约点名要建的那条)
#    ⚠ 这件与食物羁绊【成长·无上限】构成自我放大回路: 三段效果全按最大生命缩放,
#      而【成长】让血量没有天花板 ⇒ 血涨 → 打得疼【且】打得快, 双重放大。
#      用户已定"滚雪球不设上限"⇒ 不加帽, 但**必须有一条线盯住实际倍率**,
#      落在设计带外要报出来(照 verify_synergy_magnitude 的口径)。
# ═══════════════════════════════════════════════════════════════════
func _t070_magnitude() -> void:
	print("── ⑤ 070 量级门禁(自我放大回路) ──")
	# 设计带(方案书 §0.5 的量级表, 硬写在这里, 不读被测常量):
	#   maxHp 945 → on-hit 66 · 溅射/人 19 · 攻速 +9.5%
	#   maxHp 3000 → 210 · 60 · +30%     maxHp 6000 → 420 · 120 · +60%
	#   maxHp 10000 → 700 · 200 · +100%
	var rows := [[945.0, 66.0, 19.0, 0.095], [3000.0, 210.0, 60.0, 0.30],
		[6000.0, 420.0, 120.0, 0.60], [10000.0, 700.0, 200.0, 1.00]]
	for row in rows:
		var mh: float = float(row[0])
		var u: Dictionary = _equip(_mk("fortune", "left", Vector2(-500.0, -60.0 + mh * 0.002), mh), "p2eq_070", 3)
		var t: Dictionary = _mk("fortune", "right", Vector2(-460.0, -60.0 + mh * 0.002), 1000000.0)
		var s2: Dictionary = _mk("fortune", "right", Vector2(-360.0, -60.0 + mh * 0.002), 1000000.0)
		var h0: float = float(t["hp"])
		var s0: float = float(s2["hp"])
		_food.tick_unit(u, 0.016)
		_food._eq_ballast_brick(u, t, 2)
		_ok("⑤ maxHp=%.0f: on-hit 实发 %.0f(设计带 %.0f)" % [mh, h0 - float(t["hp"]), float(row[1])],
			absf((h0 - float(t["hp"])) - float(row[1])) < 0.51 + 1.0, "")
		_ok("⑤ maxHp=%.0f: 溅射/人 实发 %.0f(设计带 %.0f)" % [mh, s0 - float(s2["hp"]), float(row[2])],
			absf((s0 - float(s2["hp"])) - float(row[2])) < 0.51 + 1.0, "")
		_ok("⑤ maxHp=%.0f: 额外攻速 +%.1f%%(设计带 %.1f%%)" % [mh, (float(u["aspd_perm"]) - 1.0) * 100.0, float(row[3]) * 100.0],
			absf((float(u["aspd_perm"]) - 1.0) - float(row[3])) < 0.001, "")
	# ★真正的量级线: 一场打满(血量从裸龟 945 涨到 10000)之后, 这件的【DPS 倍率】翻了多少倍。
	#   DPS ∝ 单次伤害 × 攻速 ⇒ 倍率 = (伤害比) × (攻速比)。
	#   945 血: 66 × 1.095 = 72.3   ／   10000 血: 700 × 2.00 = 1400
	#   ⇒ 10.58 倍血量 → 19.37 倍 DPS。**这就是"双重放大"的实测数**, 焊在这里,
	#     以后谁改了缩放系数(或给它加了帽), 这条线立刻会红并把新倍率打出来。
	var dps_lo: float = 66.0 * (1.0 + 0.095)
	var dps_hi: float = 700.0 * (1.0 + 1.00)
	var ratio: float = dps_hi / dps_lo
	_ok("⑤ ★量级线: 血量 945→10000(10.58×) 时本件 DPS 倍率 = %.2f×(双重放大, 用户知情不加帽)" % ratio,
		absf(ratio - 19.37) < 0.05,
		"lo=%.1f hi=%.1f ratio=%.3f · 设计值 19.37" % [dps_lo, dps_hi, ratio])
	# ★放大【指数】才是这条线真正盯的东西: DPS ∝ 血量^n。
	#   n=1.00 就是"只按血量线性放大"(单段效果按血量缩放的正常样子);
	#   实测 n=1.256 > 1 ⇒ 伤害与攻速两段【同时】吃血量, 这就是自我放大回路的量化证据。
	#   (n 不到 2 是因为攻速那一段有 +1 的基底: 1+maxHp×0.0001, 不是纯正比。)
	var expo: float = log(ratio) / log(10000.0 / 945.0)
	_ok("⑤ ★量级线: 放大指数 log(DPS比)/log(血量比) = 1.256(线性缩放应为 1.000, >1 即为自我放大)",
		absf(expo - 1.256) < 0.01, "实测指数 %.4f" % expo)


# ═══════════════════════════════════════════════════════════════════
# ⑥ 特效【物理规律】门禁 —— 判据不是"我调得像", 是"它满足这几条闭式解的性质"
#    ★全部是纯函数采样, 一条都不等 tween(无头 CI 下 tween 推进不稳)
# ═══════════════════════════════════════════════════════════════════
func _t_vfx_physics() -> void:
	print("── ⑥ 特效物理(闭式解性质) ──")
	var V := FoodEqVfx

	# ⑥-1 069 三块糖糕: 等分圆轨道 ⇒ 任意时刻两两角距恒为 120°
	var worst := 0.0
	for k in range(40):
		var t: float = float(k) * 0.137
		for i in range(3):
			var a: float = V.cake_angle((i + 1) % 3, t) - V.cake_angle(i, t)
			a = fposmod(a, TAU)
			worst = maxf(worst, absf(minf(a, TAU - a) - TAU / 3.0))
	_ok("⑥-1 069 三块糕【等分轨道】: 40 个时刻 × 3 对, 两两角距恒为 120°",
		worst < 1e-5, "最大偏差 %.12f rad" % worst)

	# ⑥-2 069 送入口是【真抛物线】⇒ 等步长二阶差分恒定(= -g·Δx²)
	var dx := 0.02
	var d2_min := INF
	var d2_max := -INF
	for k in range(1, 48):
		var x: float = float(k) * dx
		var d2: float = V.bite_height(x + dx) - 2.0 * V.bite_height(x) + V.bite_height(x - dx)
		d2_min = minf(d2_min, d2)
		d2_max = maxf(d2_max, d2)
	_ok("⑥-2 069 送入口【常重力抛体】: 二阶差分恒定(缓动曲线做不到)",
		absf(d2_max - d2_min) < 1e-9 and absf(d2_min - (-2.0 * dx * dx)) < 1e-9,
		"d2 ∈ [%.12f, %.12f] · 期望 -g·Δx² = %.12f" % [d2_min, d2_max, -2.0 * dx * dx])

	# ⑥-3 070 Worthington 冠: Rayleigh 空腔自相似 ⇒ R(4x)/R(x) ≡ 2
	var w3 := 0.0
	for k in range(1, 25):
		var x: float = float(k) * 0.01
		w3 = maxf(w3, absf(V.crown_radius(4.0 * x) / V.crown_radius(x) - 2.0))
	_ok("⑥-3 070 溅射冠【尺度不变性】: R(4x)/R(x) ≡ 2 对所有 x 成立",
		w3 < 1e-6, "最大偏差 %.12f" % w3)

	# ⑥-4 070 冠壁高度是纯弹道 ⇒ 极大恰在 x=0.5 且二阶差分恒定
	var peak_x := 0.0
	var peak := -1.0
	for k in range(1001):
		var x: float = float(k) / 1000.0
		var h: float = V.crown_height(x)
		if h > peak:
			peak = h
			peak_x = x
	var c2_min := INF
	var c2_max := -INF
	for k in range(1, 48):
		var x2: float = float(k) * dx
		var d2b: float = V.crown_height(x2 + dx) - 2.0 * V.crown_height(x2) + V.crown_height(x2 - dx)
		c2_min = minf(c2_min, d2b)
		c2_max = maxf(c2_max, d2b)
	_ok("⑥-4 070 冠高【弹道】: 极大值 1.000 恰在 x=0.5, 且二阶差分恒定",
		absf(peak - 1.0) < 1e-9 and absf(peak_x - 0.5) < 1e-6 and absf(c2_max - c2_min) < 1e-9,
		"peak=%.6f @ x=%.4f · d2 ∈ [%.12f,%.12f]" % [peak, peak_x, c2_min, c2_max])

	# ⑥-5 071 Taylor–Culick: 洞缘恒速 ⇒ 半径严格线性(二阶差分 0), 卷入质量 ∝ r²
	var t2 := 0.0
	for k in range(1, 48):
		var x3: float = float(k) * dx
		t2 = maxf(t2, absf(V.tc_hole_radius(x3 + dx) - 2.0 * V.tc_hole_radius(x3) + V.tc_hole_radius(x3 - dx)))
	var m4 := 0.0
	for k in range(1, 40):
		var x4: float = float(k) * 0.01
		m4 = maxf(m4, absf(V.tc_rim_mass(2.0 * x4) / V.tc_rim_mass(x4) - 4.0))
	_ok("⑥-5 071 破膜【Taylor–Culick】: 洞半径二阶差分 ≡ 0(恒速回缩)",
		t2 < 1e-12, "最大 |d2| = %.12f" % t2)
	_ok("⑥-6 071 破膜【卷入质量 ∝ r²】: m(2x)/m(x) ≡ 4(洞匀速张开而边越来越重)",
		m4 < 1e-9, "最大偏差 %.12f" % m4)

	# ⑥-7 071 奶油壳【毛细波色散】ω²=k³ ⇒ c(k)=√k ⇒ c(4k)/c(k) ≡ 2
	var cw := 0.0
	for k in [1.0, 2.5, 7.0, 13.0, 20.0]:
		cw = maxf(cw, absf(V.capillary_speed(4.0 * float(k)) / V.capillary_speed(float(k)) - 2.0))
	_ok("⑥-7 071 奶油壳【毛细波色散】: c(4k)/c(k) ≡ 2(短波跑得快)",
		cw < 1e-6, "最大偏差 %.12f" % cw)

	# ⑥-8 072 盒盖【二阶欠阻尼】: 对数减缩 ⇒ 相邻过冲峰之比恒定
	var peaks: Array = []
	var prev := V.lid_step(0.0)
	var cur := V.lid_step(0.0005)
	var tt := 0.0005
	while tt < 1.2:
		var nxt: float = V.lid_step(tt + 0.0005)
		if cur > prev and cur >= nxt:
			peaks.append(absf(cur - 1.0))
		prev = cur
		cur = nxt
		tt += 0.0005
	var want_ratio: float = V.lid_peak_ratio()
	var okp: bool = peaks.size() >= 3
	var wr := 0.0
	if okp:
		for i in range(peaks.size() - 1):
			wr = maxf(wr, absf(float(peaks[i + 1]) / maxf(float(peaks[i]), 1e-12) - want_ratio))
	_ok("⑥-8 072 盒盖【对数减缩】: 抓到 %d 个过冲峰, 相邻峰比恒为 %.4f(=e^(−2πζ/√(1−ζ²)))"
		% [peaks.size(), want_ratio], okp and wr < 0.02, "最大偏差 %.4f" % wr)

	# ⑥-9 072 分裂弹出【恢复系数】: 相邻弹跳峰高之比 = e² = 0.3025
	var hpk: Array = []
	var hp_prev := V.hop_height(0.0)
	var hp_cur := V.hop_height(0.0005)
	var ht := 0.0005
	while ht < 1.0:
		var hn: float = V.hop_height(ht + 0.0005)
		if hp_cur > hp_prev and hp_cur >= hn:
			hpk.append(hp_cur)
		hp_prev = hp_cur
		hp_cur = hn
		ht += 0.0005
	var e2: float = 0.55 * 0.55
	var hw := 0.0
	if hpk.size() >= 3:
		for i in range(hpk.size() - 1):
			hw = maxf(hw, absf(float(hpk[i + 1]) / maxf(float(hpk[i]), 1e-12) - e2))
	_ok("⑥-9 072 分裂弹出【恢复系数 e=0.55】: 抓到 %d 个弹跳峰, 相邻峰高比恒为 e²=0.3025"
		% hpk.size(), hpk.size() >= 3 and hw < 0.02, "最大偏差 %.4f" % hw)

	# ⑥-10 ★尺子要匹配被测概念: 三个环画的就是【效果半径本身】
	var vfx = _food._vfx
	_ok("⑥-10 嘲讽环半径 = 550 码(= 072 的嘲讽范围本身, 不是随手画的演出尺寸)",
		absf(vfx.range_m(FoodEqVfx.TAUNT_RANGE_PX) - 550.0 * float(_s.WS)) < 1e-6
		and absf(FoodEqVfx.TAUNT_RANGE_PX - 550.0) < 1e-6, "")
	_ok("⑥-11 蛋糕法阵环 = 300 码 · 溅射冠 = 250 码(与效果半径同源)",
		absf(FoodEqVfx.CAKE_FIELD_PX - 300.0) < 1e-6 and absf(FoodEqVfx.SPLASH_RANGE_PX - 250.0) < 1e-6, "")

	# ⑥-12 灰条几何: 从"当前生命"右端起画, 长度 = 灰条/最大生命, 且钳在血条内
	var g1: Array = FoodEqVfx.grey_rect(66.0, 500.0, 1000.0, 200.0)
	_ok("⑥-12 灰条几何: hp 50% / 灰条 20% ⇒ x0=33.0 宽=13.2",
		absf(float(g1[0]) - 33.0) < 0.01 and absf(float(g1[1]) - 13.2) < 0.01,
		"x0=%.2f w=%.2f" % [float(g1[0]), float(g1[1])])
	var g2: Array = FoodEqVfx.grey_rect(66.0, 900.0, 1000.0, 800.0)
	_ok("⑥-13 灰条几何 ★钳在血条内: 灰条比已损失还多时不许画出右边界",
		float(g2[0]) + float(g2[1]) <= 66.0 + 0.01,
		"x0=%.2f w=%.2f 合计=%.2f" % [float(g2[0]), float(g2[1]), float(g2[0]) + float(g2[1])])


# ═══════════════════════════════════════════════════════════════════
# ⑦ 特效【真的显示进 _world / 血条】—— 美术断言不看"函数被调过"
# ═══════════════════════════════════════════════════════════════════
func _t_vfx_art() -> void:
	print("── ⑦ 特效真的进了场景树 ──")
	var vfx = _food._vfx
	var w = _s._world
	_ok("⑦ ★分母: 战斗世界节点存在(它不在, 下面全是空检查)", is_instance_valid(w), "")

	# ⑦-1 070 溅射冠: 两个 MeshInstance3D 真的挂在 _world 下
	var h: Dictionary = vfx.splash_crown(Vector2(0.0, 0.0))
	var cw = h.get("crown", null)
	var rg = h.get("ring", null)
	_ok("⑦-1 070 溅射冠: crown/ring 两个网格真的挂进 _world",
		is_instance_valid(cw) and is_instance_valid(rg)
		and cw.is_inside_tree() and is_same(cw.get_parent(), w) and is_same(rg.get_parent(), w), "")
	# ★贴地几何的法线朝上(memory fb-axis-y-plus-rotation-cancels: 这类环曾经整条竖着立)
	var faces: PackedVector3Array = (rg.mesh as ArrayMesh).get_faces()
	var flat := true
	var nmin := 1.0
	for i in range(0, mini(faces.size(), 300), 3):
		var n: Vector3 = (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
		if n.length() < 1e-9:
			continue
		nmin = minf(nmin, absf(n.normalized().dot(Vector3.UP)))
	flat = nmin > 0.999
	_ok("⑦-2 070 贴地环真的【躺平】: |面法线·上| = %.4f ≈ 1.000" % nmin, flat, "")
	# 冠的半径按 √x 长: x=0.25 时应是最大半径的一半
	vfx.crown_apply_at(h, 0.25)
	var r_quarter: float = cw.scale.x
	vfx.crown_apply_at(h, 1.0)
	var r_full: float = cw.scale.x
	_ok("⑦-3 070 ★量的是【真实节点的 scale】不是公式: R(0.25)/R(1) = 0.500(√x)",
		absf(r_quarter / maxf(r_full, 1e-9) - 0.5) < 1e-4,
		"%.4f / %.4f" % [r_quarter, r_full])

	# ⑦-4 071 破壳: 洞半径线性 ⇒ 真实节点 scale 在 x=0.5 时正好是一半
	var hb: Dictionary = vfx.cream_burst(Vector2(40.0, 0.0))
	var hole = hb.get("hole", null)
	_ok("⑦-4 071 破壳网格真的挂进 _world",
		is_instance_valid(hole) and hole.is_inside_tree() and is_same(hole.get_parent(), w), "")
	vfx.tc_apply_at(hb, 0.5)
	var rh: float = hole.scale.x
	vfx.tc_apply_at(hb, 1.0)
	var rf: float = hole.scale.x
	_ok("⑦-5 071 ★真实节点: 洞半径 r(0.5)/r(1) = 0.500(恒速回缩)",
		absf(rh / maxf(rf, 1e-9) - 0.5) < 1e-4, "%.4f / %.4f" % [rh, rf])
	_ok("⑦-6 071 破壳环的世界半径 = 300 码(AOE 半径本身)",
		absf(rf - 300.0 * float(_s.WS)) < 1e-4, "%.4f / %.4f" % [rf, 300.0 * float(_s.WS)])

	# ⑦-7 072 嘲讽环: 半径 = 550 码, 亮度随锁定人数升
	var bx: Dictionary = _equip(_mk("fortune", "left", Vector2(500.0, 200.0), 2000.0), "p2eq_072", 3)
	vfx.taunt_ring_update(bx, 0)
	var ring = bx.get("_box_ring", null)
	_ok("⑦-7 072 嘲讽环真的挂进 _world",
		is_instance_valid(ring) and ring.is_inside_tree() and is_same(ring.get_parent(), w), "")
	_ok("⑦-8 072 嘲讽环世界半径 = 550 码",
		absf(ring.scale.x - 550.0 * float(_s.WS)) < 1e-4,
		"%.4f / %.4f" % [ring.scale.x, 550.0 * float(_s.WS)])
	var a0: float = (ring.material_override as StandardMaterial3D).albedo_color.a
	vfx.taunt_ring_update(bx, 6)
	var a6: float = (ring.material_override as StandardMaterial3D).albedo_color.a
	_ok("⑦-9 072 ★双抗有视觉反馈: 0 人锁定 → 6 人锁定, 环的不透明度真的从 %.2f 升到 %.2f" % [a0, a6],
		a6 > a0 + 0.3, "")

	# ⑦-10 069 头顶三块糕: 剩几块就显示几块(用户要的"吃掉的过程可见")
	var ck: Dictionary = _equip(_mk("fortune", "left", Vector2(540.0, -200.0), 1000.0), "p2eq_069", 3)
	_food.tick_unit(ck, 0.016)
	var orb = ck["eq_state"]["p2eq_069"].get("orbit", null)
	var sprs: Array = (orb as Dictionary).get("spr", []) if orb is Dictionary else []
	var in_world := 0
	for s in sprs:
		if is_instance_valid(s) and s.is_inside_tree() and is_same(s.get_parent(), w):
			in_world += 1
	_ok("⑦-10 069 头顶三块糕真的挂进 _world(实测 %d/3)" % in_world, in_world == 3, "")
	var vis0 := 0
	for s in sprs:
		if is_instance_valid(s) and s.visible:
			vis0 += 1
	ck["hp"] = 790.0
	_food.tick_unit(ck, 0.016)
	var vis1 := 0
	for s in sprs:
		if is_instance_valid(s) and s.visible:
			vis1 += 1
	_ok("⑦-11 069 ★吃掉的过程可见: 吃第 1 块后头顶从 %d 块变 %d 块" % [vis0, vis1],
		vis0 == 3 and vis1 == 2, "")

	# ⑦-12 070 灰色血条: 真的画在【那个单位自己的血条 Control】上, 位置/宽度对得上
	var gb: Dictionary = _equip(_mk("fortune", "left", Vector2(560.0, -140.0), 1000.0), "p2eq_070", 3)
	gb["hp"] = 500.0
	vfx.grey_bar_update(gb, 200.0)
	var rect = gb.get("_grey_rect", null)
	var root = gb.get("bar_root", null)
	_ok("⑦-12 070 灰条真的是血条 Control 的子节点(不是另画一个飘在旁边的)",
		is_instance_valid(rect) and is_instance_valid(root) and is_same(rect.get_parent(), root)
		and rect.is_inside_tree(), "")
	if is_instance_valid(rect):
		_ok("⑦-13 070 ★量真实节点: hp 50%% / 灰条 20%% ⇒ x=33.0 宽=13.2(血条宽 66)",
			absf(rect.position.x - 33.0) < 0.51 and absf(rect.size.x - 13.2) < 0.51,
			"x=%.2f w=%.2f" % [rect.position.x, rect.size.x])
		_ok("⑦-14 070 ★分母: 灰条为 0 时不显示(不留一条空条在血条上)",
			_grey_hidden(vfx, gb), "")


func _grey_hidden(vfx, u: Dictionary) -> bool:
	vfx.grey_bar_update(u, 0.0)
	var rect = u.get("_grey_rect", null)
	return is_instance_valid(rect) and not rect.visible
