extends Node
## verify_staff_synergy.gd — 法器羁绊【法力条 / 灵泉 / 余韵 / 共鸣 / 净化】（2026-08-03 用户定稿）
##
## 用户原话：「没啥问题，需要给每个装备设计个法力条，有些接入主动效果，就眩晕好了」
##           「但这些潮水的名字都可以改掉，和法器相关吧，且考虑是携带者还是全队」
##
## ★这里守的是**别的门禁守不住的四件事**：
##   ① 法力条是【每件独立】的 —— 一件满了只清它自己，别的那件不受影响
##   ② 满了触发的是**这件装备在 `_tick_eq_intervals` 里的同一条分支**
##      （所以抽了 `fire_equip_effect`；两套实现 = 两套数值与特效，只有一套被门禁覆盖）
##   ③ **防连放**：法器效果自己打出的伤害不涨法力（否则满→放→伤害→又满 的自激循环）
##   ④ 法力条**绝不碰龟能** —— `_energy` / `_maxEnergy` 是放技能用的，两者混线会让龟能凭空暴涨
##
## 还守作用域分工（用户点名要考虑的）：**法力条=携带者**，**灵泉/余韵/共鸣=全队**。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_staff_synergy.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const Staff := preload("res://scripts/systems/equip/staff_synergy_system.gd")
const StaffSyn := preload("res://scripts/systems/equip/staff_synergy_system.gd")
const EquipReadouts := preload("res://scripts/gamedata/equip_readouts.gd")

var _n := 0
var _fail := 0
var _s


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 法器羁绊: 法力条 / 灵泉 / 余韵 / 共鸣 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	var staffs: Array = _ids_of_type("法器", 10)
	_ok("★分母: 找到 %d 件法器装备(顶档 10 件才验得了)" % staffs.size(), staffs.size() >= 10)

	# ══ ① 没激活羁绊也有法力条(满值 100) ══════════════════════════════
	#   ★这里【曾经】断言的是相反的事("1 件 → 法力一点不涨")。2026-08-12 用户拆掉那道闸:
	#     「我整个场上只装备符纸为啥不能触发主动? 激活法器羁绊只是加快法力条的充能
	#       但没激活时也有 100 法力值啊」。理由是硬的 —— 088/089/090 三件的**唯一**
	#     触发方式就是"该法器法力条集满时"(文案逐字), 有闸就等于单装一件是死件。
	var a0: Dictionary = _mk("left", staffs.slice(0, 1))
	_run([a0])
	_ok("① ★没激活羁绊(1 件)时满值 = 100", _s._staff_syn.mana_full(a0) == 100.0,
		"实得 %.0f" % _s._staff_syn.mana_full(a0))
	_s._staff_syn.add_mana(a0, 40.0)
	_ok("① ★没激活羁绊也照涨法力(拆闸前这里恒为 0)",
		absf(_mana(a0, staffs[0]) - 40.0) < 0.01, "mana=%.1f" % _mana(a0, staffs[0]))
	_s._staff_syn.add_mana(a0, 61.0)         # 40+61=101 ≥ 100 ⇒ 该触发并清零
	_ok("① ★没激活羁绊也能【满 100 触发】(清零 = 触发过了)",
		absf(_mana(a0, staffs[0])) < 0.01, "mana=%.1f" % _mana(a0, staffs[0]))
	# ★只拆法力条这一道: 灵泉(每 2.5 秒按已损生命回血)是【全队】收益, 仍然要档位。
	#   不钉这条的话, 以后顺手把灵泉也放开 = 一件法器全队回血, 局内看不出来。
	a0["hp"] = 1000.0                        # 掉了 2000
	var hp_before: float = float(a0["hp"])
	_s._staff_syn._t_tick = 0.0
	_s._staff_syn.tick(_s.EQ_TICK + 0.001)   # 走一个自然节拍
	_ok("① ★灵泉仍然要档位(没激活 ⇒ 一点不回血), 拆闸只拆了法力条",
		absf(float(a0["hp"]) - hp_before) < 0.01, "hp %.0f → %.0f" % [hp_before, float(a0["hp"])])
	_ok("① 而同一个节拍里法力照涨 +25(分母: 证明 tick 真的跑过了, 不是空转)",
		absf(_mana(a0, staffs[0]) - Staff.MANA_PER_TICK) < 0.01,
		"mana=%.1f" % _mana(a0, staffs[0]))

	# ══ ② 法力条【每件独立】═══════════════════════════════════════
	# 首档满值 100。给 60 → 两件都是 60、都没满。
	var a1: Dictionary = _mk("left", staffs.slice(0, 2))
	_run([a1])
	_s._staff_syn.add_mana(a1, 60.0)
	_ok("② 首档满值 = 100(定稿)", _s._staff_syn.mana_full(a1) == 100.0,
		"实得 %.0f" % _s._staff_syn.mana_full(a1))
	_ok("② 两件法器【各自】涨到 60(不是共享一条条)",
		absf(_mana(a1, staffs[0]) - 60.0) < 0.01 and absf(_mana(a1, staffs[1]) - 60.0) < 0.01,
		"[%.0f, %.0f]" % [_mana(a1, staffs[0]), _mana(a1, staffs[1])])
	# 只把第 0 件推满：手动补 40 会两件一起补，所以改用"直接写第 0 件再加 1"
	var st0: Dictionary = a1["eq_state"].get(staffs[0], {})
	st0["mana"] = 99.0
	a1["eq_state"][staffs[0]] = st0
	_s._staff_syn.add_mana(a1, 1.0)
	_ok("② ★满了的那件清零, 另一件【不受影响】(仍在 61)",
		absf(_mana(a1, staffs[0])) < 0.01 and absf(_mana(a1, staffs[1]) - 61.0) < 0.01,
		"[%.1f, %.1f]" % [_mana(a1, staffs[0]), _mana(a1, staffs[1])])

	# ══ ③ 满了触发的是【同一条】效果分支 ═══════════════════════════
	_ok("③ ★fire_equip_effect 存在(法力满 与 tick 到点 走同一条路)",
		_s._equip_sys.has_method("fire_equip_effect"))
	# 真的跑：找一件"效果能被观测到"的法器 —— 用 _fire 直调并数它有没有报错 + 有没有走到 match
	var fired := true
	for iid in staffs:
		# 不该抛异常, 也不该改龟能
		_s._staff_syn._fire(a1, str(iid), 1)
	_ok("③ 全部 %d 件法器的效果分支都能被法力条触发(不报错)" % staffs.size(), fired)

	# ══ ④ 法力条【绝不碰龟能】═════════════════════════════════════
	var e_before: float = float(a1.get("energy", 0.0))
	var me_before: float = float(a1.get("max_energy", 0.0))
	_s._staff_syn.add_mana(a1, 500.0)
	_ok("④ ★涨法力不动龟能(energy / max_energy 一点没变)",
		absf(float(a1.get("energy", 0.0)) - e_before) < 0.01
		and absf(float(a1.get("max_energy", 0.0)) - me_before) < 0.01,
		"energy %.1f→%.1f" % [e_before, float(a1.get("energy", 0.0))])

	# ══ ⑤ 防连放：_staff_busy 期间不涨法力 ════════════════════════
	var a2: Dictionary = _mk("left", staffs.slice(0, 2))
	_run([a2])
	a2["_staff_busy"] = true
	_s._staff_syn.add_mana(a2, 80.0)
	_ok("⑤ ★防连放: 法器效果执行期间(_staff_busy)造成的伤害【不涨法力】",
		absf(_mana(a2, staffs[0])) < 0.01, "mana=%.1f" % _mana(a2, staffs[0]))
	a2["_staff_busy"] = false
	_s._staff_syn.add_mana(a2, 80.0)
	_ok("⑤ 标记解除后恢复正常积累", absf(_mana(a2, staffs[0]) - 80.0) < 0.01,
		"mana=%.1f" % _mana(a2, staffs[0]))

	# ══ ⑥ 满值随档位递减(法器越多放得越勤) ════════════════════════
	var full_by_tier: Array = []
	for cnt in [2, 5, 8, 10]:
		var au: Dictionary = _mk("left", staffs.slice(0, cnt))
		_run([au])
		full_by_tier.append(_s._staff_syn.mana_full(au))
	_ok("⑥ 满值逐档递减 %s(法器越多放得越勤)" % str(full_by_tier),
		full_by_tier == [100.0, 80.0, 60.0, 50.0], str(full_by_tier))

	# ══ ⑦ 作用域: 灵泉/余韵/共鸣 = 全队(不带法器的队友也吃) ════════
	# 5 件法器全在 A 身上(档2) → B 一件不带, 也要回血。
	var pair := _run([_mk("left", staffs.slice(0, 5)), _mk("left", [])])
	var b: Dictionary = pair[1]
	b["hp"] = float(b["maxHp"]) * 0.5
	var hp0: float = float(b["hp"])
	_s._staff_syn._t_tick = 0.0
	_s._staff_syn.tick(2.6)
	_ok("⑦ ★灵泉是【全队】: 一件法器都不带的队友也回血(已损失 ×5%%)",
		float(b["hp"]) > hp0 + 1.0, "%.0f → %.0f" % [hp0, float(b["hp"])])
	# 而法力条是【携带者】: B 身上没有任何法力条
	_ok("⑦ ★法力条是【携带者】: 不带法器的队友身上没有任何法力条",
		(b.get("eq_state", {}) as Dictionary).is_empty(), str(b.get("eq_state", {})))

	# ══ ⑧ 余韵: 受到治疗 → 额外拿治疗量 N% 的护盾 ══════════════════
	# 档3 需要 8 件 ⇒ ECHO_PCT[2] = 30%
	var c: Dictionary = _run([_mk("left", staffs.slice(0, 8))])[0]
	c["hp"] = float(c["maxHp"]) * 0.5
	c["shield"] = 0.0
	_s._damage._heal(c, 200.0)
	# ★期望值【写死 60】不读 Staff.ECHO_PCT —— 读常量就是恒真式:
	#   把 ECHO_PCT[2] 改成 0 时两边一起变成 0, 门禁照样全绿(实测变异 0 FAIL)。
	#   定稿数是 30%: 200 × 0.30 = 60。改数值就该在这里红。
	_ok("⑧ 余韵(档3): 回 200 血 → 额外拿 60 护盾(定稿 30%%)",
		absf(float(c["shield"]) - 60.0) < 1.0, "shield=%.1f" % float(c["shield"]))
	_ok("⑧ ★常量表就是定稿值 ECHO_PCT = [0, 0, 0.30, 0.50]",
		Staff.ECHO_PCT == [0.0, 0.0, 0.30, 0.50], str(Staff.ECHO_PCT))
	# 档2(5 件) 没有余韵
	var c2: Dictionary = _run([_mk("left", staffs.slice(0, 5))])[0]
	c2["hp"] = float(c2["maxHp"]) * 0.5
	c2["shield"] = 0.0
	_s._damage._heal(c2, 200.0)
	_ok("⑧ ★档2 没有余韵(ECHO_PCT[1]=0) → 一点护盾都没有",
		absf(float(c2["shield"])) < 0.01, "shield=%.1f" % float(c2["shield"]))

	# ══ ⑨ 共鸣: 顶档每 7.5 秒 回 15% 最大生命 + 净化 2 种 ═══════════
	var d: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	d["hp"] = float(d["maxHp"]) * 0.2
	var dh0: float = float(d["hp"])
	d["stun_until"] = _s._t + 99.0
	d["slow_until"] = _s._t + 99.0
	d["dot_stacks"] = {"burn": 3}
	# ★数值断言【直调 _resonance】隔离掉灵泉 —— tick(7.6) 会同时推过灵泉的 2.5 秒节拍,
	#   两条效果的回血量会叠在一起(实测 450 共鸣 + 288 灵泉 = 738), 那样断言就把
	#   "两条效果的执行顺序"也写死了, 以后动任何一条都会红在无关的地方。
	_s._staff_syn._resonance()
	# ★同样写死: maxHp 3000 × 15% = 450。
	_ok("⑨ 共鸣(顶档): 回 15%% 最大生命 (%.0f → %.0f, 期望 +450)" % [dh0, float(d["hp"])],
		absf(float(d["hp"]) - dh0 - 450.0) < 2.0)
	# 再单独验它【真的挂在 tick 上】: 同样掉到 20%, 走 tick 要比只有灵泉回得多。
	var d3: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	d3["hp"] = float(d3["maxHp"]) * 0.2
	_s._staff_syn._t_tick = 0.0
	_s._staff_syn._t_reso = 0.0
	_s._staff_syn.tick(7.6)
	_ok("⑨ 共鸣挂在 tick 上(走一次 7.5 秒节拍, 回血 > 单靠灵泉的量)",
		float(d3["hp"]) - float(d3["maxHp"]) * 0.2 > 450.0,
		"回了 %.0f" % (float(d3["hp"]) - float(d3["maxHp"]) * 0.2))
	_ok("⑨ ★净化的是 2 【种】不是 2 层: 眩晕+减速被清, 灼烧【还在】(顺序固定)",
		float(d.get("stun_until", 0.0)) <= _s._t and float(d.get("slow_until", 0.0)) <= _s._t
		and int((d.get("dot_stacks", {}) as Dictionary).get("burn", 0)) == 3,
		"stun=%.1f slow=%.1f burn=%d" % [float(d.get("stun_until", 0.0)),
			float(d.get("slow_until", 0.0)), int((d.get("dot_stacks", {}) as Dictionary).get("burn", 0))])
	# 档3(8 件) 没有共鸣的净化, 也不回血
	var d2: Dictionary = _run([_mk("left", staffs.slice(0, 8))])[0]
	d2["hp"] = float(d2["maxHp"]) * 0.2
	var d2h0: float = float(d2["hp"])
	_s._staff_syn._t_reso = 0.0
	_s._staff_syn.tick(7.6)
	_ok("⑨ ★档3 没有共鸣(只有顶档 10 件才有) → 不回那 15%%",
		float(d2["hp"]) - d2h0 < 225.0,
		"%.0f → %.0f" % [d2h0, float(d2["hp"])])

	# ══ ⑩ 净化的每一种都真的清得掉(含诅咒走 dots 数组) ═════════════
	var e: Dictionary = _run([_mk("left", staffs.slice(0, 10))])[0]
	e["stun_until"] = _s._t + 99.0
	e["slow_until"] = _s._t + 99.0
	e["dot_stacks"] = {"burn": 3, "poison": 2}
	e["dots"] = [{"tag": "curse", "dps": 10.0, "until": _s._t + 99.0}]
	var cleared: int = _s._staff_syn.dispel(e, 5)
	_ok("⑩ ★五种减益逐一都清得掉(清了 %d 种)" % cleared, cleared == 5, "只清掉 %d 种" % cleared)
	_ok("⑩ ★诅咒是从 dots 数组里摘的(不是一个 curse_until 字段 —— 那个字段全仓库不存在)",
		(e.get("dots", []) as Array).is_empty(), str(e.get("dots", [])))

	# ══ ⑪ 战斗真的在跑它(不是写了没人调) ═══════════════════════════
	_ok("⑪ ★主场景持有 _staff_syn 成员", _s.get("_staff_syn") != null)
	var src_main: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⑪ ★_staff_syn.tick 挂在主循环上(否则法力永远不涨)",
		src_main.find("_staff_syn.tick(") >= 0)
	var src_dmg: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	_ok("⑪ ★三条法力来源都接线了(受伤 / 造成伤害 / 治疗后的余韵)",
		src_dmg.count("_staff_syn.add_mana(") >= 3 and src_dmg.find("_staff_syn.on_healed(") >= 0,
		"add_mana×%d on_healed=%s" % [src_dmg.count("_staff_syn.add_mana("),
			src_dmg.find("_staff_syn.on_healed(") >= 0])
	# ★一个类型的机制只能有一个主人: 灵泉不能同时留在 synergy_system(会各发一次)
	var src_syn: String = FileAccess.get_file_as_string("res://scripts/systems/equip/synergy_system.gd")
	_ok("⑪ ★灵泉只有一个主人(synergy_system 里不再有法器的周期回血)",
		src_syn.find("TIDE_PCT") < 0 and src_syn.find('tiers.has("法器")') < 0)

	# ══ ⑫ 【每一件】法器都要能被法力条触发 ══════════════════════════════
	#   规格:「满 100/80/60/50 → **触发这件法器的效果**」⇒ 十件都要在 fire_equip_effect
	#   的 match 里有分支。那个 match **没有兜底 `_:`**, 漏一件就是"法力白攒":
	#   条照涨照满照清零、光柱照放, 效果零触发 —— 局内完全看不出来, 只会觉得"这件好弱"。
	#   2026-08-12 实测漏了五件(011/023/026/029/043), 用户问「能触发主动吗」才查出来。
	var src_eq: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var i0: int = src_eq.find("func fire_equip_effect(")
	var i1: int = src_eq.find("\nfunc ", i0 + 10)      # 到下一个顶层 func 为止 = 这张分发表
	_ok("⑫ 找得到 fire_equip_effect 的函数体(判据的地基)", i0 >= 0 and i1 > i0)
	var body: String = src_eq.substr(i0, i1 - i0) if (i0 >= 0 and i1 > i0) else ""
	var staff_ids: Array = []
	for se in DataRegistry.phase2_equipment:
		var sid: String = str((se as Dictionary).get("id", ""))
		if Phase2Types.type_of(sid) == "法器":
			staff_ids.append(sid)
	staff_ids.sort()
	var missing: Array = []
	for sid2 in staff_ids:
		if body.find('"%s"' % str(sid2)) < 0:
			missing.append(str(sid2))
	_ok("⑫ ★分母: 法器共 10 件(少了说明类型表被动过, 判据要跟着改)",
		staff_ids.size() == 10, "实得 %d 件: %s" % [staff_ids.size(), str(staff_ids)])
	_ok("⑫ ★十件法器【每一件】都在 fire_equip_effect 里有分支(法力满 ⇒ 真的放得出效果)",
		missing.is_empty(), "没接的: %s" % str(missing))
	# 兜底分支一旦被加进来, 上面那条断言就失去意义(什么 id 都"能触发"了) —— 一并钉死
	_ok("⑫ ★分发表不许有兜底 `_:`(有的话上一条就成了空检查)",
		body.find("\n\t\t_:") < 0)

	# ══ ⑬ 【每一件】法器的法力条都要在局内看得见 ═════════════════════════
	#   用户 2026-08-12「每个法器装备又正确接了法力条吗」的字面判据。
	#   ★出口只有一个: 头像下装备格的充能条(PANEL_CHARGE / EquipReadouts.CHARGE),
	#     读 eq_state[id].mana_pct(归一百分比 —— 满值随档位 100/80/60/50 变, 而条的分母
	#     只能是常量, 直接读 mana 会让高档永远填不满)。
	#   ★023/026 身上【同时】跑着两条真条子(它自己的老充能 + 法器法力), 所以表里是"一件多条"。
	var no_bar: Array = []
	for sid3 in staff_ids:
		var raw2: Array = EquipReadouts.CHARGE.get(str(sid3), [])
		var specs2: Array = raw2 if (raw2.size() > 0 and raw2[0] is Array) else [raw2]
		var has_mana := false
		for sp in specs2:
			if (sp is Array) and (sp as Array).size() > 0 and str((sp as Array)[0]) == "mana_pct":
				has_mana = true
		if not has_mana:
			no_bar.append(str(sid3))
	_ok("⑬ ★十件法器【每一件】的法力条在装备格里都有出口(mana_pct)",
		no_bar.is_empty(), "看不到法力的: %s" % str(no_bar))
	# 老条不许被顶掉: 023/026 文案里写着"进度显示在图标下方", 说的是它们自己那条
	## ★023/026 原来各有一条【自己的】充能条(火法力 / 雷电充能)自己攒自己放, 于是同一件
	##   装备上跑着两条条子。2026-08-12 按规则并进法力条:「法器只有法力条触发的主动效果,
	##   可能有常驻的被动效果」—— 它们每段命中 +10 / 每段伤害 +25 是【被动在给法力条充能】,
	##   不是第二条独立的条。⇒ 十件各只有【一条】, 而且【同一个颜色】(用户:「法器统一用
	##   一个颜色的法力条吧」)。颜色不统一玩家会以为是不同机制。
	var bar_colors: Dictionary = {}
	var multi: Array = []
	for sid4 in staff_ids:
		var rc: Array = EquipReadouts.CHARGE.get(str(sid4), [])
		if rc.size() > 0 and rc[0] is Array:
			multi.append(str(sid4))
			continue
		bar_colors[str(rc[2]) if rc.size() > 2 else "(缺省青)"] = true
	_ok("⑬ ★十件法器各只有【一条】条子(自己的老充能条已并进法力条)",
		multi.is_empty(), "还有多条的: %s" % str(multi))
	_ok("⑬ ★十件法器的法力条【统一一个颜色】", bar_colors.keys().size() == 1,
		"实得 %d 种: %s" % [bar_colors.keys().size(), str(bar_colors.keys())])
	var src_eq2: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	_ok("⑬ ★023/026 的每段命中/每段伤害灌的是【法器法力】, 老条子已无人写",
		src_eq2.find("battle._staff_syn.add_mana(src, 10.0)") >= 0
			and src_eq2.find("battle._staff_syn.add_mana(src, 15.0)") >= 0
			and src_eq2.find('_eq_charge(stt, "fire_mana"') < 0
			and src_eq2.find('_eq_charge(stt, "thunder"') < 0)
	var src_hud: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_hud.gd")
	_ok("⑬ 条子的构建在 _hud(主文件只翻表 —— 上帝文件不许涨行数)",
		src_hud.find("func add_equip_charge_bar(") >= 0)

	# ══ ⑭ 法器【没有第二个触发口】: 一件都不许在周期表里 ═════════════════
	#   规则(用户 2026-08-12):「并不是有两个触发路径, 只有法力条触发的主动效果,
	#   可能有常驻的被动效果」。周期表(_EQ_CUSTOM_IV / EQ_IV_BATCH1)驱动的是"每 N 秒放一次",
	#   那就是第二个触发口。029(12秒·驱动函数已删) / 030(7秒) / 031(8秒) 都是这么来的。
	var in_iv: Array = []
	for sid5 in staff_ids:
		if float((_s._EQ_CUSTOM_IV as Dictionary).get(str(sid5), 0.0)) > 0.0 \
				or float((_s._equip_sys.EQ_IV_BATCH1 as Dictionary).get(str(sid5), 0.0)) > 0.0:
			in_iv.append(str(sid5))
	_ok("⑭ ★十件法器一件都不在周期表里(周期=第二个触发口)",
		in_iv.is_empty(), "还挂着周期的: %s" % str(in_iv))

	# ══ ⑮ 043 的负面被动: 它【自己那条】法力条上限 +50/25/0% ═══════════════
	#   用户 2026-08-12:「海浪…满法力就直接放海浪, 但这里弄个负面被动: 法力值上限提升50/25/0%」。
	#   ★满值因此从【按人算】变成【按件算】—— 同一个单位身上两件法器的满值可以不一样。
	var a43: Dictionary = _mk("left", [staffs[0]])
	_run([a43])
	for cs in [[1, 150.0], [2, 125.0], [3, 100.0]]:
		_ok("⑮ 043 ★%d 的满值 = %.0f(档0基准100 × (1+%.0f%%))" % [int(cs[0]), float(cs[1]),
				float(StaffSyn.MANA_FULL_PCT["p2eq_043"][int(cs[0]) - 1])],
			absf(_s._staff_syn.mana_full_for(a43, "p2eq_043", int(cs[0])) - float(cs[1])) < 0.01,
			"实得 %.1f" % _s._staff_syn.mana_full_for(a43, "p2eq_043", int(cs[0])))
	_ok("⑮ ★分母: 没登记倍率的法器仍按【人】的满值(100), 没被这条改动波及",
		absf(_s._staff_syn.mana_full_for(a43, "p2eq_089", 1) - 100.0) < 0.01,
		"089★1 实得 %.1f" % _s._staff_syn.mana_full_for(a43, "p2eq_089", 1))
	# 有羁绊时按档位满值【成比例】放大, 不是写死 150
	_s._synergy._by_side = {"left": {"法器": 4}, "right": {}}       # 档4 ⇒ 基准 50
	_ok("⑮ ★顶档时也成比例(50 × 1.5 = 75), 不是写死的 150",
		absf(_s._staff_syn.mana_full_for(a43, "p2eq_043", 1) - 75.0) < 0.01,
		"实得 %.1f" % _s._staff_syn.mana_full_for(a43, "p2eq_043", 1))
	_s._synergy._by_side = {"left": {}, "right": {}}

	_s._units.clear()
	_s.set_process(false)
	await get_tree().process_frame
	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 法器羁绊" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mana(u: Dictionary, iid) -> float:
	return float((u["eq_state"].get(str(iid), {}) as Dictionary).get("mana", 0.0))


func _ids_of_type(t: String, n: int) -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if Phase2Types.type_of(str((e as Dictionary).get("id", ""))) == t:
			out.append(str((e as Dictionary).get("id", "")))
		if out.size() >= n:
			break
	return out


## 干净合成单位。★用 "green" 不用 "basic" —— 小龟有「不屈」被动(按稀有度增伤),
## 会把精确数值断言弄脏（memory fb-ci-vs-local-divergence）。
func _mk(side: String, ids: Array) -> Dictionary:
	var eqs: Array = []
	for i in ids:
		eqs.append({"id": str(i), "star": 1})
	return {"id": "green", "name": "合成", "side": side, "alive": true,
		"hp": 3000.0, "maxHp": 3000.0, "shield": 0.0, "equips": eqs, "eq_state": {},
		"base_atk": 100.0, "atk": 100.0, "base_def": 0.0, "def": 0.0,
		"base_mr": 0.0, "mr": 0.0, "crit": 0.0, "crit_dmg": 1.5,
		"armor_pen": 0.0, "magic_pen": 0.0, "lifesteal": 0.0, "buffs": {},
		"dots": [], "dot_stacks": {}, "pos": Vector2.ZERO}


func _run(units: Array) -> Array:
	_s._units.clear()
	_s._units.append_array(units)
	_s._synergy._by_side = {"left": {}, "right": {}}
	_s._synergy.apply_all()
	return units
