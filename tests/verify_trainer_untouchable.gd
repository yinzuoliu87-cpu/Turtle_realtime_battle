extends Node
## verify_trainer_untouchable.gd — 训龟大师 = 装饰单位 的【运行时哨兵】(2026-10-31)
##
## 用户原话(2026-10-31):「训龟大师不应该受到任何影响，就是个装饰的地位，丢点技能」
## 方案书: docs/plans/20261031e-训龟大师不受影响.md
##
## ★为什么是运行时哨兵而不是静态扫: 能改一个单位的写法有几百种(两条扣血路 / 加盾 / 治疗 / 眩晕 /
##   buff / DoT / 位移 / 直接写字段 / 羁绊按阵营发 …), 静态扫只能找"我想得到的写法"。
##   这里反过来: 让真对局里尽量多的效果发生, **每一个 sim 步**把双方大师的全部字段拍一遍,
##   除了「它自己的机制」那几个字段, 其余任何一个变了就是有东西碰到了它 —— 不需要预先知道是谁。
##
## 判据:
##   ① 全程每一步: 大师除 OWN_KEYS(它自己的出手 / 魔法石 / 动画)外的全部字段 == 开场(摆好那一刻)
##   ② 落地层兜底账本 `battle._untouch_hits` 为空 —— 没有任何东西把它送进扣血 / 加盾 / 控制 / 位移 … 入口
##      (= 它从没被选作目标; 查询层做对了这个账本一次都不该记)
##   ③ 没有弹道锁它、没有单位拿它当分离目标 / 嘲讽来源
##   ④ 分母: 真的放出了多少种技能(28 龟全部已实现技能)、多目标伤害几次、治疗 / 护盾 / 眩晕 / 击飞 / buff /
##      DoT / 减速几次、召唤物几个、时停几步、各羁绊到过几档、大师自己出手几次 —— N=0 是空检查不是通过
##
## ★场面比真对局更狠: 真对局里大师站在场边角落, 这里把它摆在【自己队伍正中间】, 每 90 步再挪回
##   本队质心(挪动由台子做, 挪完重记基线) —— 友方光环 / 范围治疗 / 敌方 AOE 都正好罩着它。
##   两边队伍都是真打(右队不再是不动不打的假人), 每只龟【全部】已实现技能轮转、满龟能。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 它【自己的】机制会动的字段 —— 只有这些允许变。每一条都要说清是谁写的。
## ★不在这里的字段一律受保护(hp / maxHp / shield / pos / height / airborne / stun_until / slow_until /
##   buffs / dots / dot_stacks / atk / def / mr / atk_interval / move_spd / crit / energy / taunt_* / flash_t …)。
const OWN_KEYS := {
	# 演出 / 动画(渲染步写, 不是结算)
	"anim_t": "立绘帧动画计时", "anim_sd": "当前动作帧表(扔石头时切换)", "anim_action": "当前动作名",
	"face_right": "朝向(扔石头前转身)", "_face_x": "朝向参考 x(_face_by_motion)",
	"_prev_pos": "渲染插值上一步位置", "_prev_height": "渲染插值上一步高度",
	# 它自己的出手 —— trainer_system._tick_trainer_attacks / _cast_*
	"_tr_atk_cd": "扔石头冷却", "_tr_throw_vec": "扔石头朝向", "_tr_throw_t0": "扔石头起始时刻",
	"_tr_throw_until": "扔石头动作结束时刻", "_active_cd": "主动技冷却(单槽)",
	"_throw_sd": "扔石头动作帧表(battle_render._update_trainer_anim)",
	# 它自己的被动 —— 魔法石叠层(trainer_system._trainer_magicstone_onhit)与它的阈值特效(_ms_tick_aura)
	"_ms_stacks": "魔法石层数", "_ms_burst_n": "魔法石阈值爆闪次数", "_ms_motes": "魔法石绕转晶石节点",
	"_ms_aura_tier": "魔法石特效档位", "_ms_orbit_t": "魔法石晶石绕转相位",
	# 它自己【打出去】的伤害记账(battle_damage._record_buckets / _apply_damage_from 末尾的来源累积)
	"dmg_dealt": "累计造成伤害", "_st_dealt": "统计面板·造成伤害", "_st_dealt_by_type": "统计面板·按类型",
	"_st_crit": "统计面板·暴击次数",
}

var _fail := 0
var _n := 0

## 跨场景累计的分母
var _cast := {}          # "龟id/技能" → 放出次数(数产品自己写的 skill_cd 抬头)
var _impl := {}          # "龟id/技能" → true(应放的全集)
var _ev := {"dmg": 0, "aoe_steps": 0, "heal": 0, "shield": 0, "stun": 0, "knock": 0, "buff": 0,
	"dot": 0, "slow": 0, "summon": 0, "ts_steps": 0, "tr_cast": 0, "tr_rock": 0, "steps": 0,
	"tamed": 0, "hijacked": 0, "moves": 0, "refl_win": 0}
var _syn_max := {}       # 羁绊类型 → 到过的最高档
var _diff_rows: Array = []        # 大师字段被改的记录(前 40 条)
var _diff_keys := {}              # 被改的字段名 → 次数
var _hits := {}                   # 落地层账本合计
var _trace: Array = []
var _proj_on_tr := 0
var _ref_on_tr := {}              # 别的单位哪个字段拿着大师 → 次数(诊断)
var _guard_pairs := 0             # 分母: 每步比对的「大师 × 字段」次数
var _sched: Array = []            # [单位, 它的全部已实现技能] —— 每 200 步换下一个(与正式对局一样一次只带一个主动技)


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 值的签名。★单位字典只记身份、绝不递归(CLAUDE.md §3.2: 单位字典互相引用成环)。
## 「中性值」(null / false / 0 / "" / 空数组 / 空字典)一律记 "∅" —— 新冒出来一个值为 0 的键不算被改。
static func _fp(v, depth: int = 0) -> String:
	if v == null:
		return "∅"
	match typeof(v):
		TYPE_BOOL:
			return "T" if bool(v) else "∅"
		TYPE_INT:
			return "∅" if int(v) == 0 else "i%d" % int(v)
		TYPE_FLOAT:
			return "∅" if float(v) == 0.0 else ReplayRecorder.exact(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			return "∅" if str(v) == "" else "s:" + str(v)
		TYPE_VECTOR2:
			var w: Vector2 = v
			return "v:%s,%s" % [ReplayRecorder.exact(w.x), ReplayRecorder.exact(w.y)]
		TYPE_VECTOR3:
			var w3: Vector3 = v
			return "v3:%s,%s,%s" % [ReplayRecorder.exact(w3.x), ReplayRecorder.exact(w3.y), ReplayRecorder.exact(w3.z)]
		TYPE_ARRAY:
			var a: Array = v
			if a.is_empty():
				return "∅"
			if depth >= 3:
				return "A%d" % a.size()
			var ps: Array = []
			for e in a:
				ps.append(_fp(e, depth + 1))
			return "[" + ",".join(ps) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.is_empty():
				return "∅"
			if d.has("alive") and d.has("side"):
				return "U:%s/%s" % [str(d.get("id", "?")), str(d.get("side", "?"))]
			if depth >= 3:
				return "D%d" % d.size()
			var ks: Array = d.keys()
			ks.sort()
			var ps2: Array = []
			for k in ks:
				ps2.append("%s=%s" % [str(k), _fp(d[k], depth + 1)])
			return "{" + ",".join(ps2) + "}"
		TYPE_OBJECT:
			return "O"
	return str(v)


static func _snap(u: Dictionary) -> Dictionary:
	var out := {}
	for k in u.keys():
		if OWN_KEYS.has(str(k)):
			continue
		out[str(k)] = _fp(u[k])
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	## 固定战斗随机种子(det 模式: 每帧恰一步) ⇒ 每次跑的是同一局, 分母不随运气上下浮动。
	## NOVERDICT: 不判胜负 —— 一方先倒光的话后面的步数全是空跑。两个开关跑完都还原。
	OS.set_environment("TURTLE_SEED", "424242")
	OS.set_environment("NOVERDICT", "1")

	var pets: Array = DataRegistry.all_pets
	var by_id := {}
	for p in pets:
		if p is Dictionary:
			by_id[str(p.get("id", ""))] = p
	var g0 := ["basic", "stone", "bamboo", "angel", "ice", "ninja", "two_head"]
	var g1 := ["ghost", "diamond", "fortune", "dice", "rainbow", "gambler", "hunter"]
	var g2 := ["pirate", "candy", "bubble", "line", "lightning", "phoenix", "lava"]
	var g3 := ["cyber", "crystal", "chest", "space", "hiding", "headless", "shell"]
	var all_ids: Array = g0 + g1 + g2 + g3
	_ok("★分母: 4 组共 %d 只龟, 与 pets.json 的 %d 只一一对应(漏一只就是这只龟的技能从没被量过)" % [all_ids.size(), by_id.size()],
		all_ids.size() == 28 and by_id.size() == 28 and all_ids.all(func(x): return by_id.has(x)))

	## 装备按类型成组发, 让每一方都能把羁绊叠到高档(触手要灵物 8 / 10 件, 炮台要枪 3 件不同 …)
	var t_sword := ["p2eq_001", "p2eq_003", "p2eq_005", "p2eq_006", "p2eq_007", "p2eq_009", "p2eq_010", "p2eq_083", "p2eq_084"]
	var t_food := ["p2eq_002", "p2eq_012", "p2eq_013", "p2eq_036", "p2eq_037", "p2eq_069", "p2eq_070", "p2eq_071", "p2eq_072"]
	var t_relic := ["p2eq_004", "p2eq_024", "p2eq_044", "p2eq_053", "p2eq_058", "p2eq_059", "p2eq_091", "p2eq_092", "p2eq_094"]
	var t_gadget := ["p2eq_008", "p2eq_020", "p2eq_027", "p2eq_035", "p2eq_038", "p2eq_040", "p2eq_047", "p2eq_085", "p2eq_086", "p2eq_087"]
	var t_staff := ["p2eq_011", "p2eq_023", "p2eq_026", "p2eq_029", "p2eq_030", "p2eq_031", "p2eq_043", "p2eq_088", "p2eq_089", "p2eq_090"]
	var t_shield := ["p2eq_014", "p2eq_015", "p2eq_016", "p2eq_017", "p2eq_018", "p2eq_021", "p2eq_045", "p2eq_081", "p2eq_082"]
	var t_potion := ["p2eq_019", "p2eq_022", "p2eq_028", "p2eq_041", "p2eq_042", "p2eq_065", "p2eq_066", "p2eq_067", "p2eq_068"]
	var t_spirit := ["p2eq_025", "p2eq_032", "p2eq_033", "p2eq_034", "p2eq_046", "p2eq_060", "p2eq_061", "p2eq_062", "p2eq_063", "p2eq_064"]
	var t_bow := ["p2eq_039", "p2eq_049", "p2eq_054", "p2eq_055", "p2eq_056", "p2eq_073", "p2eq_074", "p2eq_075", "p2eq_076"]
	var t_gun := ["p2eq_048", "p2eq_050", "p2eq_051", "p2eq_052", "p2eq_057", "p2eq_077", "p2eq_078", "p2eq_079", "p2eq_080"]
	var t_misc := ["p2eq_093", "p2eq_096"]
	var scen: Array = [
		{"tag": "S1 剑+灵物(触手) vs 法器+奇械", "L": g0, "R": g2, "tr_l": "hook", "tr_r": "tame", "ms_l": false,
			"eqL": t_sword + t_spirit + t_misc, "eqR": t_staff + t_gadget + ["p2eq_004"]},
		{"tag": "S2 食物+盾 vs 药水+弓箭", "L": g1, "R": g3, "tr_l": "glacier", "tr_r": "hunt_order", "ms_l": true,
			"eqL": t_food + t_shield + ["p2eq_024", "p2eq_044", "p2eq_053"], "eqR": t_potion + t_bow + ["p2eq_058", "p2eq_091", "p2eq_092"]},
		{"tag": "S3 枪+遗物(时停) vs 剑+盾", "L": g2, "R": g0, "tr_l": "whistle", "tr_r": "fury_potion", "ms_l": false,
			## 084 手半剑会把【近战】携带者的技能整个换成十字斩 —— S1 里它落在竹叶龟身上, 这里倒过来发, 免得竹叶龟两次都被换掉
			## 059 时停排到第 7 只(凤凰龟, 带涅槃)身上: 第一版落在闪电龟身上, 它活不到第 10 秒 ⇒ 时停一次没放, 那一族整段空跑
			"eqL": t_gun + ["p2eq_004", "p2eq_024", "p2eq_044", "p2eq_053", "p2eq_058", "p2eq_091", "p2eq_059", "p2eq_092", "p2eq_094"]
				+ ["p2eq_025", "p2eq_032", "p2eq_033"], "eqR": _rev(t_sword) + t_shield + t_misc + ["p2eq_002"]},
		{"tag": "S4 法器+药水 vs 灵物(触手)+枪", "L": g3, "R": g1, "tr_l": "tame", "tr_r": "hook", "ms_l": true,
			"eqL": t_staff + t_potion + ["p2eq_046", "p2eq_060"], "eqR": t_spirit + t_gun + ["p2eq_012", "p2eq_013"]},
	]
	var eq_seen := {}
	for sc in scen:
		for e in (sc["eqL"] as Array) + (sc["eqR"] as Array):
			eq_seen[str(e)] = true
	var eq_total := 0
	var all_eq: Dictionary = {}
	var _tj = JSON.parse_string(FileAccess.get_file_as_string("res://data/p2eq-types.json"))
	if _tj is Dictionary:
		all_eq = _tj
	eq_total = all_eq.size()
	var miss_eq: Array = []
	for k in all_eq.keys():
		if not eq_seen.has(str(k)):
			miss_eq.append(str(k))
	_ok("★分母: 4 个场景合计装上 %d 件不同装备 / 全表 %d 件(漏的: %s)" % [eq_seen.size(), eq_total, str(miss_eq)],
		eq_total >= 90 and miss_eq.is_empty())

	for sc in scen:
		await _run(sc, by_id)
	await _run_minions()
	await _run_retaliate()

	## ── 判据 ──
	var miss_cast: Array = []
	for k in _impl.keys():
		if int(_cast.get(k, 0)) <= 0:
			miss_cast.append(str(k))
	miss_cast.sort()
	## ★不要求 100%: 有几个技能要现场条件(财神招财进宝要抽得到装备 / 嘲讽要射程内有人 …), 同一份种子下也会偶尔轮空。
	##   要的是"绝大多数技能真的在大师身边放过", 没放的逐个打印出来。
	var cast_n: int = _impl.size() - miss_cast.size()
	_ok("★分母: 28 龟 + 小将全部已实现技能 %d 个, 真的放出来 %d 个(≥95%%; 没放出来的: %s)" % [_impl.size(), cast_n, str(miss_cast)],
		_impl.size() >= 80 and float(cast_n) >= float(_impl.size()) * 0.95)
	var ck: Array = _cast.keys()
	ck.sort()
	var cs: Array = []
	for k in ck:
		cs.append("%s×%d" % [k, int(_cast[k])])
	print("  [分母] 各技能放出次数: %s" % ", ".join(cs))
	print("  [分母] 事件: %s" % str(_ev))
	print("  [分母] 羁绊到过的最高档: %s" % str(_syn_max))
	_ok("★分母: 多目标伤害(同一步 ≥3 个单位掉血)≥ 200 步 / 治疗 ≥ 100 / 护盾 ≥ 100 / 眩晕 ≥ 30 / 击飞 ≥ 10 / buff ≥ 100 / DoT ≥ 100 / 减速 ≥ 10",
		int(_ev["aoe_steps"]) >= 200 and int(_ev["heal"]) >= 100 and int(_ev["shield"]) >= 100 and int(_ev["stun"]) >= 30
		and int(_ev["knock"]) >= 10 and int(_ev["buff"]) >= 100 and int(_ev["dot"]) >= 100 and int(_ev["slow"]) >= 10, str(_ev))
	_ok("★分母: 反伤窗口(凤凰熔岩盾 / 闪电雷盾在身, 且就站在对面大师脚边)≥ 120 步 —— 打不到它们, 「反伤不回敬大师」就是空检查",
		int(_ev["refl_win"]) >= 120, str(_ev["refl_win"]))
	_ok("★分母: 召唤物 ≥ 10 个 / 时停 ≥ 60 步 / 大师自己出手 ≥ 8 次 / 被驯服或被侵入 ≥ 1 次",
		int(_ev["summon"]) >= 10 and int(_ev["ts_steps"]) >= 60 and int(_ev["tr_cast"]) >= 8
		and int(_ev["tamed"]) + int(_ev["hijacked"]) >= 1, str(_ev))
	var syn_ok: bool = true
	for t in ["剑", "食物", "遗物", "奇械", "法器", "盾", "药水", "灵物", "弓箭", "枪"]:
		if int(_syn_max.get(t, 0)) < 2:
			syn_ok = false
	_ok("★分母: 十类羁绊每一类都到过 ≥2 档(灵物到过顶档 = 触手出场)", syn_ok and int(_syn_max.get("灵物", 0)) >= 4, str(_syn_max))
	_ok("★分母: 每步比对的「大师 × 字段」次数 %d (每步两个大师 × 上百个字段)" % _guard_pairs, _guard_pairs > 100000)

	## ① 字段全程不变
	if not _diff_rows.is_empty():
		print("  —— 大师被改的字段(前 %d 条) ——" % _diff_rows.size())
		for r in _diff_rows:
			print("    " + str(r))
	_ok("★★① 全程每一步: 双方训龟大师除它自己的机制外【没有一个字段变过】", _diff_keys.is_empty(),
		"被改的字段: %s" % str(_diff_keys))
	## ② 落地层账本
	if not _trace.is_empty():
		print("  —— 落地层被送进来的调用栈(前 %d 条) ——" % _trace.size())
		for t2 in _trace:
			print("    " + str(t2))
	_ok("★★② 它从没被任何东西选作目标: 落地层兜底账本为空(扣血 / 加盾 / 治疗 / 控制 / 位移 / buff / DoT …)", _hits.is_empty(),
		"账本: %s" % str(_hits))
	## ③ 弓箭 / 分离 / 嘲讽
	_ok("★★③ 没有弹道锁它", _proj_on_tr == 0, "锁它的弹道 %d 发" % _proj_on_tr)
	print("  [诊断] 别的单位哪些字段拿着大师: %s" % str(_ref_on_tr))
	var bad_ref := 0
	for k in ["_sep_target", "taunt_by", "_target", "target"]:
		bad_ref += int(_ref_on_tr.get(k, 0))
	_ok("★★③ 没有单位拿它当攻击 / 分离目标或嘲讽来源", bad_ref == 0, str(_ref_on_tr))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 训龟大师不受任何影响" if _fail == 0 else "FAIL x%d" % _fail)
	RB.DEBUG_EDIT = false
	OS.unset_environment("TURTLE_SEED")
	OS.unset_environment("NOVERDICT")
	get_tree().quit(1 if _fail > 0 else 0)


## 每只龟【全部】已实现主动技(与 verify_skills_not_dead 同一口径: skillPool 里 `_IMPL_SKILLS` 认得的)
func _impl_skills(s, p: Dictionary) -> Array:
	var out: Array = []
	for sk in p.get("skillPool", []):
		var t := str((sk as Dictionary).get("type", ""))
		if t != "" and s._IMPL_SKILLS.has(t) and not s.PASSIVE_SKILL_TYPES.has(t):
			out.append(t)
	return out


func _arm(s, u: Dictionary, p: Dictionary, side: String) -> void:
	var sks: Array = _impl_skills(s, p)
	## ★一次只带一个、每 200 步轮到下一个: 全塞进去的话 `_pick_ready_skill` 永远挑最贵的那个,
	##   遇到"挑中了却放不出来、也不进冷却"的技能(财神梭哈用过后)就卡死在它身上, 其余技能一次都轮不到(第一版实测 19 个没放)。
	u["active_skills"] = [sks[0]] if not sks.is_empty() else []
	_sched.append([u, sks])
	u["skill_idx"] = 0
	var cds := {}
	for t in sks:
		cds[str(t)] = 0.0
		_impl["%s/%s" % [str(p.get("id", "")), str(t)]] = true
	u["skill_cd"] = cds
	if side == "right":
		u["no_basic"] = false
		u["no_move"] = false
		u.erase("_review_dummy")


func _run(sc: Dictionary, by_id: Dictionary) -> void:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	## 顿帧会把 sim 步吞掉(实测 1200 步只走了 7.8 游戏秒, 时停的第 10 秒根本到不了)。
	## 顿帧是纯演出上的停顿, 不改结算 ⇒ 台子关掉它, 让「步数 ≈ 游戏秒 × 60」。
	s._hitstop_mute = 1000000
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 1500.0   # ★调试场拿它推小将等级(= 血 / 300): 4 万 ⇒ 133 级小将(×660 属性), 1.9 秒互相秒光
	s._edit_full_energy = true
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var L: Array = sc["L"]
	var R: Array = sc["R"]
	var eqL: Array = sc["eqL"]
	var eqR: Array = sc["eqR"]
	for side in ["left", "right"]:
		var ids: Array = L if side == "left" else R
		var eqs: Array = eqL if side == "left" else eqR
		var x: float = c.x - 300.0 if side == "left" else c.x + 300.0
		for i in range(ids.size()):
			var pid: String = str(ids[i])
			var u: Dictionary = s._debug._edit_place_unit(pid, side, Vector2(x, c.y + (float(i) - 3.0) * 85.0))
			var el: Array = []
			for j in range(3):
				var k: int = i * 3 + j
				if k < eqs.size():
					## 059 时停按 1★ 装(定格最短), 其余 3★
					el.append({"id": str(eqs[k]), "star": (1 if str(eqs[k]) == "p2eq_059" else 3)})
			u["_edit_equips"] = el
			_arm(s, u, by_id[pid], side)
	s._edit_trainer_active = str(sc["tr_l"])
	var tl: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "left", Vector2(c.x - 300.0, c.y + 42.0))
	if bool(sc.get("ms_l", false)):
		tl["_tr_passive"] = "magic_stone"
	s._edit_trainer_active = str(sc["tr_r"])
	var trr: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "right", Vector2(c.x + 300.0, c.y + 42.0))
	await _drive(s, [tl, trr], 1200, str(sc["tag"]), true)


## 小将一族(近战浪板 / 远程火箭 / 精英铁锤击飞 / 援军四面合围)+ 两侧大师 —— 它们不在 28 龟里, 技能各走各的系统。
func _run_minions() -> void:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	## 顿帧会把 sim 步吞掉(实测 1200 步只走了 7.8 游戏秒, 时停的第 10 秒根本到不了)。
	## 顿帧是纯演出上的停顿, 不改结算 ⇒ 台子关掉它, 让「步数 ≈ 游戏秒 × 60」。
	s._hitstop_mute = 1000000
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 1500.0   # ★调试场拿它推小将等级(= 血 / 300): 4 万 ⇒ 133 级小将(×660 属性), 1.9 秒互相秒光
	s._edit_full_energy = true
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var roles := ["front", "back", "elite", "reserve"]
	for side in ["left", "right"]:
		var x: float = c.x - 260.0 if side == "left" else c.x + 260.0
		for i in range(roles.size()):
			s._edit_minion_role = str(roles[i])
			var u: Dictionary = s._debug._edit_place_unit("__minion__", side, Vector2(x, c.y + (float(i) - 1.5) * 95.0))
			if side == "right":
				u["no_basic"] = false
				u["no_move"] = false
				u.erase("_review_dummy")
				## 调试场把右队的主动技清空了(假人) —— 按角色还原成 `_make_unit` 给的那一个
				u["active_skills"] = [{"front": "minionBodysurf", "back": "minionRocket", "elite": "eliteHammer", "reserve": ReserveConsts.SKILL}[str(roles[i])]]
			var cds := {}
			for sk in (u.get("active_skills", []) as Array):
				cds[str(sk)] = 0.0
				_impl["__minion__/%s" % str(sk)] = true
			u["skill_cd"] = cds
	s._edit_trainer_active = "glacier"
	var tl: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "left", Vector2(c.x - 260.0, c.y))
	s._edit_trainer_active = "whistle"
	var trr: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "right", Vector2(c.x + 260.0, c.y))
	trr["_tr_passive"] = "magic_stone"
	await _drive(s, [tl, trr], 600, "S5 小将四种 + 大师冰川/口哨/魔法石", false)


## 反伤靶: 凤凰【熔岩盾】/ 闪电【雷盾】(都按「每受一段攻击」回敬攻击者)+ 082 砗磲护心 + 015 荆棘海胆,
##   摆在【对面大师脚边】当它的最近敌人 ⇒ 大师每扔一块石头都打在它们身上。
## ★为什么单开一场: 前五场里这几种回敬一次都没指向过大师(改坏验证 M3 实测: 拆掉反伤闸照样全绿) ——
##   大师的石头只有 1 点伤害, 通用反伤 int(1 × 比例) = 0 天然不触发, 只有「不看伤害大小」的熔岩盾 / 雷盾 / 082 会回敬,
##   而它们得恰好在盾窗口里、恰好是大师的最近敌人。场面不摆出来, 那条闸就没人量。
func _run_retaliate() -> void:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._deterministic = true
	s._hitstop_mute = 1000000
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 1500.0
	s._edit_full_energy = true
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var tl_pos := Vector2(c.x - 300.0, c.y)
	var tr_pos := Vector2(c.x + 300.0, c.y)
	for side in ["left", "right"]:
		var near: Vector2 = tr_pos if side == "left" else tl_pos
		var dx: float = -60.0 if side == "left" else 60.0
		var specs := [["phoenix", "phoenixShield"], ["lightning", "lightningShield"]]
		for i in range(specs.size()):
			var u: Dictionary = s._debug._edit_place_unit(str(specs[i][0]), side, near + Vector2(dx, (float(i) - 0.5) * 70.0))
			u["_edit_equips"] = [{"id": "p2eq_082", "star": 3}, {"id": "p2eq_015", "star": 3}, {"id": "p2eq_014", "star": 3}]
			u["active_skills"] = [str(specs[i][1])]
			u["skill_cd"] = {str(specs[i][1]): 0.0}
			u["no_move"] = true
			if side == "right":
				u["no_basic"] = false
				u.erase("_review_dummy")
	s._edit_trainer_active = "whistle"
	var tl: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "left", tl_pos)
	tl["_tr_passive"] = "magic_stone"
	var trr: Dictionary = s._debug._edit_place_unit(s.TRAINER_ID, "right", tr_pos)
	await _drive(s, [tl, trr], 900, "S6 反伤靶(熔岩盾/雷盾/082/015 站在对面大师脚边)", false)


## 开打并逐步盯着两个大师。
func _drive(s, trainers: Array, steps: int, tag: String, follow: bool) -> void:
	var base: Array = []
	for t in trainers:
		base.append(_snap(t))
	var st := {"step": 0, "prev": [], "refs": [], "slot": 200}
	var cb := func() -> void: _on_step(s, trainers, base, st, follow)
	s.sim_stepped.connect(cb)
	s._debug._edit_start_battle()
	for u in s._units:
		if s._is_untouchable(u):
			continue
		## 开战准备会按底子重算最大生命 ⇒ 在它之后把血统一成 4000(配合下面的「掉到一半就补满」让 20 秒里两边都活着)。
		## ⚠ 不能抬到上万: 盾羁绊冲击波 = 自身最大生命 × 4/6/8%, 一发 ≥ 怒气阈值 400 时对面挨一发就回敬一发,
		##   两边都有盾羁绊 ⇒ 无限互弹到栈溢出(第一版 6 万血实测踩到, 见方案书「新发现的坑」)。4000 × 8% = 320 < 400。
		u["maxHp"] = 4000.0
		u["hp"] = 4000.0
		if str(u.get("side", "")) == "right":
			s._debug._edit_apply_full_energy(u)
	## 开战准备(装备 / 羁绊 / 出场被动)那一下也要量: 这时候还没有 sim 步
	_check(s, trainers, base, -1)
	for tp in s._synergy._by_side.values():
		for ty in (tp as Dictionary).keys():
			_syn_max[str(ty)] = maxi(int(_syn_max.get(str(ty), 0)), int((tp as Dictionary)[ty]))
	var t0: int = int(st["step"])
	var guard := 0
	while int(st["step"]) - t0 < steps and guard < steps * 4:
		await get_tree().process_frame
		guard += 1
		if not is_instance_valid(s):
			break
	print("  [%s] 跑了 %d 步 · 战斗钟 %.1f 秒 · 大师 %d 个 · 场上单位 %d 个 · 结束=%s · 时停已放=%s" % [tag, int(st["step"]) - t0, float(s._t), trainers.size(), s._units.size(), str(s._over), str(s._timestop._ts_fired)])
	_sched.clear()
	if OS.has_environment("VTU_DEBUG"):
		for u in s._units:
			print("    · %s/%s alive=%s hp=%.0f/%.0f summon=%s eff=%s" % [str(u.get("id")), str(u.get("side")), str(u.get("alive")), float(u.get("hp", 0)), float(u.get("maxHp", 0)), str(u.get("is_summon", false)), str(s._eff_side(u))])
	if s.sim_stepped.is_connected(cb):
		s.sim_stepped.disconnect(cb)
	for k in s._untouch_hits.keys():
		_hits[k] = int(_hits.get(k, 0)) + int(s._untouch_hits[k])
	for t in s._untouch_trace:
		if _trace.size() < 40:
			_trace.append("%s | %s" % [tag, str(t)])
	s._pending_shots.clear()
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check(s, trainers: Array, base: Array, step: int) -> void:
	for i in range(trainers.size()):
		var t: Dictionary = trainers[i]
		var b: Dictionary = base[i]
		var keys := {}
		for k in b.keys():
			keys[k] = true
		for k in t.keys():
			if not OWN_KEYS.has(str(k)):
				keys[str(k)] = true
		for k in keys.keys():
			_guard_pairs += 1
			var now: String = _fp(t.get(k, null))
			var was: String = str(b.get(k, "∅"))
			if now != was:
				_diff_keys[k] = int(_diff_keys.get(k, 0)) + 1
				if _diff_rows.size() < 40 and int(_diff_keys[k]) == 1:
					_diff_rows.append("步 %d · %s 方大师 · %s: %s → %s" % [step, str(t.get("side", "?")), k, was.substr(0, 80), now.substr(0, 80)])
				b[k] = now   # 每个字段每次变化只记一笔, 不刷屏


func _on_step(s, trainers: Array, base: Array, st: Dictionary, follow: bool) -> void:
	st["step"] = int(st["step"]) + 1
	_ev["steps"] = int(_ev["steps"]) + 1
	var step: int = int(st["step"])
	_check(s, trainers, base, step)
	## 大师自己出手(分母): 主动技冷却抬头 / 扔石头冷却抬头。
	## ★台子自己的记账不写进大师字典(那会被判成"被改了"): 存在 st 里
	if not st.has("tr_prev"):
		st["tr_prev"] = []
		for t in trainers:
			(st["tr_prev"] as Array).append([0.0, 0.0])
	for i in range(trainers.size()):
		var t: Dictionary = trainers[i]
		var pv: Array = (st["tr_prev"] as Array)[i]
		var acd: float = float(t.get("_active_cd", 0.0))
		var rcd: float = float(t.get("_tr_atk_cd", 0.0))
		if acd > float(pv[0]) + 0.01:
			_ev["tr_cast"] = int(_ev["tr_cast"]) + 1
		if rcd > float(pv[1]) + 0.01:
			_ev["tr_rock"] = int(_ev["tr_rock"]) + 1
		(st["tr_prev"] as Array)[i] = [acd, rcd]
	## 弹道锁大师?
	for pr in s._projectiles:
		if pr is Dictionary:
			var tg = (pr as Dictionary).get("tgt", null)
			for t in trainers:
				if tg is Dictionary and is_same(tg, t):
					_proj_on_tr += 1
	## 别的单位拿着大师(诊断 + ③)
	var refs: Array = st["refs"]
	var prev: Array = st["prev"]
	var dmg_units := 0
	if s._timestop != null and not s._timestop._ts_active.is_empty():
		_ev["ts_steps"] = int(_ev["ts_steps"]) + 1
	for u in s._units:
		if not (u is Dictionary) or s._is_untouchable(u):
			continue
		for k in (u as Dictionary).keys():
			var v = u[k]
			if v is Dictionary:
				for t in trainers:
					if is_same(v, t):
						_ref_on_tr[str(k)] = int(_ref_on_tr.get(str(k), 0)) + 1
		var idx := -1
		for j in range(refs.size()):
			if is_same(refs[j], u):
				idx = j
				break
		var cur := {"hp": float(u.get("hp", 0.0)), "sh": float(u.get("shield", 0.0)),
			"stun": float(u.get("stun_until", 0.0)), "air": bool(u.get("airborne", false)),
			"buffs": (u.get("buffs", []) as Array).size() if u.get("buffs", []) is Array else 0,
			"dots": _dot_total(u), "slow": float(u.get("slow_until", 0.0)),
			"cds": (u.get("skill_cd", {}) as Dictionary).duplicate() if u.get("skill_cd", {}) is Dictionary else {}}
		if idx < 0:
			refs.append(u)
			prev.append(cur)
			if bool(u.get("is_summon", false)):
				_ev["summon"] = int(_ev["summon"]) + 1
			continue
		var p: Dictionary = prev[idx]
		if cur["hp"] < p["hp"] - 0.001 or cur["sh"] < p["sh"] - 0.001:
			_ev["dmg"] = int(_ev["dmg"]) + 1
			dmg_units += 1
		if cur["hp"] > p["hp"] + 0.001:
			_ev["heal"] = int(_ev["heal"]) + 1
		if cur["sh"] > p["sh"] + 0.001:
			_ev["shield"] = int(_ev["shield"]) + 1
		if cur["stun"] > p["stun"] + 0.001:
			_ev["stun"] = int(_ev["stun"]) + 1
		if cur["air"] and not p["air"]:
			_ev["knock"] = int(_ev["knock"]) + 1
		if int(cur["buffs"]) > int(p["buffs"]):
			_ev["buff"] = int(_ev["buff"]) + 1
		if int(cur["dots"]) > int(p["dots"]):
			_ev["dot"] = int(_ev["dot"]) + 1
		if cur["slow"] > p["slow"] + 0.001:
			_ev["slow"] = int(_ev["slow"]) + 1
		if float(u.get("shield", 0.0)) > 0.0 and (float(s._t) < float(u.get("lava_shield_until", 0.0)) or float(s._t) < float(u.get("thunder_shield_until", 0.0))):
			_ev["refl_win"] = int(_ev["refl_win"]) + 1
		## 台子给参战单位续血(掉到一半就补满): 百分比伤害 + 满龟能 + 高档羁绊下 6 万血也撑不过十几秒(实测 S5 小将 1.9 秒全灭),
		##   一方倒光后面全是空跑。补血在【量完这一步的事件之后】做, 并同步改 prev, 不会被记成一次治疗。
		if bool(u.get("alive", false)) and float(u.get("hp", 0.0)) < float(u.get("maxHp", 1.0)) * 0.5:
			u["hp"] = float(u["maxHp"])
			cur["hp"] = float(u["maxHp"])
		var pc: Dictionary = p["cds"]
		var cc: Dictionary = cur["cds"]
		for sk in cc.keys():
			if float(cc[sk]) > float(pc.get(sk, 0.0)) + 0.01:
				var key := "%s/%s" % [str(u.get("id", "")), str(sk)]
				_cast[key] = int(_cast.get(key, 0)) + 1
		if str(u.get("tamed_side", "")) != "" and not bool(p.get("tamed", false)):
			_ev["tamed"] = int(_ev["tamed"]) + 1
		if bool(u.get("hijacked", false)) and not bool(p.get("hij", false)):
			_ev["hijacked"] = int(_ev["hijacked"]) + 1
		cur["tamed"] = str(u.get("tamed_side", "")) != ""
		cur["hij"] = bool(u.get("hijacked", false))
		prev[idx] = cur
	if dmg_units >= 3:
		_ev["aoe_steps"] = int(_ev["aoe_steps"]) + 1
	## 换技能: 每 200 步每只龟换成它的下一个已实现技能, 冷却清零(满龟能)。1200 步 = 6 格 ⇒ 3 个技能的龟每个轮到两次
	if step % int(st["slot"]) == 0:
		var k: int = step / int(st["slot"])
		for pr2 in _sched:
			var su: Dictionary = pr2[0]
			var sks: Array = pr2[1]
			if sks.is_empty() or not su.get("alive", false):
				continue
			var nx: String = str(sks[k % sks.size()])
			su["active_skills"] = [nx]
			var cds2: Dictionary = su.get("skill_cd", {})
			cds2[nx] = 0.0
			su["skill_cd"] = cds2
	## 跟着战场走: 每 90 步把大师挪回本队存活单位的质心(台子做的挪动, 挪完重记 pos 基线)
	if follow and step % 90 == 0:
		for i in range(trainers.size()):
			var t: Dictionary = trainers[i]
			var acc := Vector2.ZERO
			var n := 0
			for u in s._units:
				if u is Dictionary and u.get("alive", false) and not s._is_untouchable(u) \
						and str(s._eff_side(u)) == str(t.get("side", "")) and not bool(u.get("is_summon", false)):
					acc += Vector2(u["pos"])
					n += 1
			if n > 0:
				t["pos"] = acc / float(n) + Vector2(0.0, 30.0)
				base[i]["pos"] = _fp(t["pos"])
				_ev["moves"] = int(_ev["moves"]) + 1


static func _rev(a: Array) -> Array:
	var b: Array = a.duplicate()
	b.reverse()
	return b


static func _dot_total(u: Dictionary) -> int:
	var n := 0
	var ds = u.get("dot_stacks", {})
	if ds is Dictionary:
		for k in (ds as Dictionary).keys():
			n += int((ds as Dictionary)[k]) if typeof((ds as Dictionary)[k]) in [TYPE_INT, TYPE_FLOAT] else 0
	var dl = u.get("dots", [])
	if dl is Array:
		n += (dl as Array).size()
	return n
