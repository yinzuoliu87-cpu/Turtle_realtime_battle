class_name EquipStatsApply
extends RefCounted
## 装备【被动属性/flag 应用】系统(2026-07-26 从 equip_system.gd 抽出)。
## 与主动效果分开: 本系统只在 spawn/升星 把 EquipStats.STATS 的纯数值+永久flag 写进单位字段;
## 主动技能效果(剑气/枪械/召唤…)仍在 EquipSystem。类内名不变, 外部引用用 battle.。

var battle

func _init(b) -> void:
	battle = b

func _eq_apply_all_stats() -> void:
	for u in battle._units:
		for e in u.get("equips", []):
			_eq_apply_one_stats(u, str(e["id"]), int(e.get("star", 1)))
	_b4_on_spawn_all()


## ★这里原来是 `_apply_feast_hp()` ——「072 百年龟苓宴: 开战给全队 +60/110/180 最大生命」。
##   2026-08-05 用户把 072 整条重做成【铁皮蛋糕盒】(终极护盾 + 变身礼盒 + 阵亡分裂),
##   新设计里【没有"开战送血"这一半】⇒ 整段删掉, 不是搬走。
##   效果本体见 scripts/systems/equip/eq_food_batch.gd 的 §072 段。


## ★这里原来是 `_apply_altar_egg_hp()` ——「093 祭坛残石: 本方龟蛋 +200/400/700 最大生命」。
##   2026-08-06 用户把 093 整条重做成【香火石】(跨对局养成的刻痕 + 独特羁绊 + 强化普攻),
##   新设计里**完全没有龟蛋这一半** ⇒ 整段删掉, 不是搬走。别加回来。
##   (旧效果本身也站不住: 遗物羁绊【龟蛋加固】给的是 +1200/2200/3600, 700 连它一档都不到。)


## 批④(2026-08-06) 后 17 件的【登场钩】: 在全队属性都施加完之后统一跑一遍。
##
## ★为什么放在 `_eq_apply_all_stats` 末尾而不是 `_eq_apply_flags` 里:
##   `_eq_apply_flags` 是**逐单位**跑的 —— 077/079/080 要在登场时生成召唤物并读携带者的
##   最终属性(079 的炮台攻速要跟随携带者、080 的机炮吃携带者攻击力), 轮到第一只龟时
##   它自己的属性才刚写完、别的龟还没写。放末尾能保证读到的都是最终值。
## ★换路会整体重建单位字典 ⇒ 本函数在每一路的开战管线里重跑 ⇒ 召唤物每路重新生成。
func _b4_on_spawn_all() -> void:
	var owner: Dictionary = battle._equip_sys.B4_OWNER
	for u in battle._units:
		if not (u is Dictionary) or not (u.get("eq_state", null) is Dictionary):
			continue
		for e in u.get("equips", []):
			if not (e is Dictionary):
				continue
			var eid: String = str((e as Dictionary).get("id", ""))
			if not owner.has(eid):
				continue
			u["_b4_eq"] = true   # 每帧 tick_unit 的常驻守卫(不遍历 equips, 见 EquipSystem._eq_tick)
			var sys = battle._equip_sys._b4(eid)
			if sys != null:
				sys.on_spawn(u, eid, clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1)


# 单件逐星属性 → 实时单位字段 (复用 battle.EquipStats.STATS; 字段口径换到实时引擎).
# 单件逐星属性 → 实时单位字段 (复用 battle.EquipStats.STATS; 字段口径换到实时引擎).
func _eq_apply_one_stats(u: Dictionary, item_id: String, star: int) -> void:
	var arr: Array = battle.EquipStats.STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		_eq_apply_flags(u, item_id, star)
		return
	apply_stat_dict(u, arr[i], item_id)
	_eq_apply_flags(u, item_id, star)


## ★2026-08-03 抽出的纯函数: 把一份属性 dict 施加到单位上。
## 抽它的理由同 EquipStats.lines_of —— 让【还没有装备在用的新字段】也能被门禁验到,
## 而不是等某件装备用上了才发现"展示写了、施加没写"(dodgePct 的教训)。
## item_id 仍要传: 有一处按 id 排除(p2eq_015 反伤走专属分支, 见下面那段血泪注释)。
func apply_stat_dict(u: Dictionary, st: Dictionary, item_id: String) -> void:
	if st.has("atk"):
		u["base_atk"] += float(st["atk"])
	if st.has("hp"):
		var add: float = float(st["hp"])  # 装备hp已是最终值
		u["maxHp"] += add; u["hp"] += add
	if st.has("crit"):
		u["crit"] += float(st["crit"])
	if st.has("armorPen"):
		u["armor_pen"] += float(st["armorPen"])
	if st.has("magicPen"):
		u["magic_pen"] += float(st["magicPen"])
	if st.has("_lifestealPct"):
		u["lifesteal"] += float(st["_lifestealPct"]) / 100.0
	if st.has("def"):
		u["base_def"] += float(st["def"])
	if st.has("mr"):
		u["base_mr"] += float(st["mr"])
	if st.has("critDmg"):
		u["crit_dmg"] += float(st["critDmg"])
	if st.has("_maxEnergy"):   # 初始龟能: 开局减该技冷却(init_energy_bonus懒初始化时折算, 多件叠加)
		u["init_energy_bonus"] = float(u.get("init_energy_bonus", 0.0)) + float(st["_maxEnergy"])
	if st.has("_echargePct"):   # 龟能充能速率% → echarge_perm 永久倍率(多件叠加)
		u["echarge_perm"] = float(u.get("echarge_perm", 1.0)) + float(st["_echargePct"]) / 100.0
	# ★2026-08-03 批2 三个新字段(方案书 D7)。★★多件叠加一律【加】(D16「u4加吧」):
	#   单件时加法与乘法同值(1.0×(1+x) == 1.0+x), 差异只在同一只龟叠多件时出现。
	#   加法的好处是【可预测、不指数爆炸】—— 乘算是本项目翻车过的形状
	#   (memory fb-verify-magnitude-not-just-correctness: 彩虹五条探针全绿仍把胜率从 14% 推到 97%)。
	if st.has("_aspdPct"):      # 攻速% → aspd_perm(战斗侧 atk_cd 除以它)
		u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + float(st["_aspdPct"]) / 100.0
	if st.has("_mspdPct"):      # 移速% → move_perm(★新通道: 既有的 move_buff_mult 是【限时】的, 装备要永久)
		u["move_perm"] = float(u.get("move_perm", 1.0)) + float(st["_mspdPct"]) / 100.0
	if st.has("_rangePct"):     # 射程% → range_perm(★新通道; atk_range 被 34 处直接读, 不能就地乘)
		u["range_perm"] = float(u.get("range_perm", 1.0)) + float(st["_rangePct"]) / 100.0
	if st.has("_rangeAdd"):     # 射程 flat(码) → range_add(2026-08-05·065 鲨肝油)。同理不能就地写 atk_range
		u["range_add"] = float(u.get("range_add", 0.0)) + float(st["_rangeAdd"])
	# ↓ 以下4类原先漏接: 数值表里写了、单位字段也确实被消费, 但从没往里写 → 属性栏骗人(用户2026-07-19发现)
	# ★★2026-08-02 修【反伤发两次】: p2eq_015 荆棘海胆必须【跳过】这个通用钩。
	#   它在 equip_system.gd:1104 有【专属分支】自己发反伤(而且要把伤害累计进 thorn_accum
	#   才能触发"满阈值 → 护盾 + 强化下一次普攻")。两条路都在 battle_damage.gd 的同一个
	#   `if not from_equip` 块里触发, 无互斥 ⇒ 实际反伤是名义值的【两倍】,
	#   而累计器只统计其中一半 ⇒ 阈值触发速率也只有名义的一半。
	#   探针实测(1★ 名义 12%): 打 1000 → 反伤 240(应 120), thorn_accum 只记 120。倍率 2.00×。
	#   ★别改成"删掉专属分支": 累计/护盾/流血那套只有专属分支有。
	#   ★也别改成"删掉通用钩": p2eq_013(海胆壳 8/11/15%)与灵龟觉醒(shell_system.gd:307)
	#     都靠它, 它们【没有】专属反伤分支, 删了会让那两处反伤直接归零。
	const REFLECT_OWNED_BY_BRANCH := ["p2eq_015"]
	if st.has("reflectPct") and not (item_id in REFLECT_OWNED_BY_BRANCH):
		u["reflect"] = float(u.get("reflect", 0.0)) + float(st["reflectPct"]) / 100.0
	# ★★2026-08-02 补: dodgePct 一直【只在图鉴显示、从不施加】——
	#   equip_stats.gd:38 有展示分支, 而本文件从来没有对应的施加分支,
	#   全靠 p2eq_046 的专属分支兜着(现已删, 见下)。图鉴写着"闪避 +15%"是假的。
	#   ★生效值被 DODGE_CAP(75%) 钳在 _recalc_stats 里, 这里只管加。
	if st.has("dodgePct"):
		battle._damage._buff(u, "dodge", float(st["dodgePct"]) / 100.0, false, 99999.0)
	if st.has("healAmp"):       # 治疗增幅% → battle._damage._heal 读 u.heal_amp (amt *= 1+heal_amp)
		u["heal_amp"] = float(u.get("heal_amp", 0.0)) + float(st["healAmp"]) / 100.0
	if st.has("shieldAmp"):     # 护盾增幅% → battle._damage._grant_shield 读 u.shield_amp (amt *= 1+shield_amp)
		u["shield_amp"] = float(u.get("shield_amp", 0.0)) + float(st["shieldAmp"]) / 100.0
	if st.has("shieldHealPct"): # 「治疗&盾增」% → 同时加治疗增幅与护盾增幅
		u["heal_amp"] = float(u.get("heal_amp", 0.0)) + float(st["shieldHealPct"]) / 100.0
		u["shield_amp"] = float(u.get("shield_amp", 0.0)) + float(st["shieldHealPct"]) / 100.0
	battle._recalc_stats(u)

# 财神招财临时装备升星: STATS[item]每星是绝对值→只加(新星-旧星)数值差量(不重跑_eq_apply_flags,避免dodge/harden/on-hit等flag类重复叠加·flag类逐星缩放留F5)
# 财神招财临时装备升星: STATS[item]每星是绝对值→只加(新星-旧星)数值差量(不重跑_eq_apply_flags,避免dodge/harden/on-hit等flag类重复叠加·flag类逐星缩放留F5)
func _eq_star_delta_stats(u: Dictionary, item_id: String, from_star: int, to_star: int) -> void:
	var arr: Array = battle.EquipStats.STATS.get(item_id, [])
	var fi: int = clampi(from_star, 1, 3) - 1
	var ti: int = clampi(to_star, 1, 3) - 1
	if fi < 0 or ti < 0 or fi >= arr.size() or ti >= arr.size():
		return
	var a: Dictionary = arr[fi]
	var b: Dictionary = arr[ti]
	u["base_atk"] += float(b.get("atk", 0.0)) - float(a.get("atk", 0.0))
	var hp_d: float = float(b.get("hp", 0.0)) - float(a.get("hp", 0.0))   # 装备hp已是最终值
	u["maxHp"] += hp_d; u["hp"] += hp_d
	u["crit"] += float(b.get("crit", 0.0)) - float(a.get("crit", 0.0))
	u["armor_pen"] += float(b.get("armorPen", 0.0)) - float(a.get("armorPen", 0.0))
	u["magic_pen"] += float(b.get("magicPen", 0.0)) - float(a.get("magicPen", 0.0))
	u["lifesteal"] += (float(b.get("_lifestealPct", 0.0)) - float(a.get("_lifestealPct", 0.0))) / 100.0
	u["base_def"] += float(b.get("def", 0.0)) - float(a.get("def", 0.0))
	u["base_mr"] += float(b.get("mr", 0.0)) - float(a.get("mr", 0.0))
	u["crit_dmg"] += float(b.get("critDmg", 0.0)) - float(a.get("critDmg", 0.0))
	u["init_energy_bonus"] = float(u.get("init_energy_bonus", 0.0)) + float(b.get("_maxEnergy", 0.0)) - float(a.get("_maxEnergy", 0.0))
	u["echarge_perm"] = float(u.get("echarge_perm", 1.0)) + (float(b.get("_echargePct", 0.0)) - float(a.get("_echargePct", 0.0))) / 100.0
	battle._recalc_stats(u)

# 永久 flag / 初始充能 (受击/闪避/必中类被动开关 + 充能计数器初值).
# 永久 flag / 初始充能 (受击/闪避/必中类被动开关 + 充能计数器初值).
func _eq_apply_flags(u: Dictionary, item_id: String, star: int) -> void:
	var si: int = clampi(star, 1, 3) - 1
	var stt: Dictionary = u["eq_state"].get(item_id, {})
	match item_id:
		"p2eq_046":   # 幽灵墨鱼: 永久闪避 buff (复用 dodge 系统)
			# 闪避率改从 battle.EquipStats.STATS 取 —— 它此前是这里的内联字面量, 而图鉴/背包读 STATS,
			# 于是闪避在两处 UI 里都不显示(用户2026-07-19「必须写完整」的漏网)。现在同源。
			# ★★2026-08-02: 闪避改走【通用 dodgePct 分支】(见本文件上方), 这里不再自己 _buff ——
			#   否则同一件装备的闪避会【发两次】, 与 p2eq_015 荆棘海胆"反伤发两次"是同一个形状
			#   (那次实测 2.00× 名义)。专属分支只留它独有的东西: 闪避触发的永久护盾。
			stt["ghost_shield"] = [30.0, 50.0, 120.0][si]
		"p2eq_054":   # 瞄准镜: 必中 (无视目标闪避)
			u["eq_cannot_be_dodged"] = true
		"p2eq_013", "p2eq_014":   # 炙烤海胆(cap20·+1/1.5/2) / 深海堡垒甲(cap25·+2/4/6·用户2026-07-19)
			stt["harden_inc"] = ([2.0, 4.0, 6.0][si] if item_id == "p2eq_014" else [1.0, 1.5, 2.0][si])
			stt["harden_cap"] = (EquipTickSystem.FORTRESS_CAP if item_id == "p2eq_014" else EquipSystem.URCHIN_CAP)
			stt["harden_stacks"] = 0
			stt["harden_given"] = false
		"p2eq_015":   # 荆棘海胆: 反伤转真伤+施流血
			# ★用户 2026-07-30 效果重做: 反伤比例提到 12/25/40%;
			#   流血【不再每次反伤都给】, 改成"累计反伤到阈值 → 护盾 + 强化下一次普攻"。
			#   (reflect_bleed 这个每击流血字段已废除 —— 留着会是死字段。)
			stt["reflect_pct"] = EquipSystem.THORN_REFLECT[si]
			stt["thorn_accum"] = 0.0
			stt["thorn_pct"] = 0.0        # 归一化镜像(0~100), 给装备格充能条; 阈值随星级变所以不能直接挂 accum
			stt["thorn_empower"] = 0      # 攒着的"强化下一次普攻"次数, 给装备格层数徽章
		"p2eq_038":   # 信号放大器(用户2026-07-30 重做): 固定 30% 攻速(不分星) + 放大层数从 0 起
			# ★2026-08-03 D16: 乘 → 加(统一口径)。单件时两者同值, 多件/叠层时加法更弱。
			#   ⚠ 这是一次【静默的削弱】, 而 tooltip_number_audit 抓不到(它只比三元组字面量,
			#   D16 只改运算符不改字面量; 038 的"30%""每层5%"还是单值, 根本不在它视野内)。
			#   ⇒ verify_aspd_stack_add 专门守这个组合, 反向验证过改回乘法会红。
			#   ★意外收获: 现有文案在乘法口径下【本来就是错的】(038 文案读作 +130%、实发 +160%),
			#   改成加法后文案变对了, 不需要改文案。
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + SignalWaveSystem.ASPD_FLAT
			stt["sig_stacks"] = 0
			stt["sig_arc_deg"] = 0.0      # 张角从 0 起, 第一次释放变 90°
			stt["sig_amp_given"] = 0.0
			stt["sig_aspd_given"] = 0.0
		"p2eq_056":   # 飞镖(用户2026-07-30 加新效果): 提供 40/80/150% 攻击速度
			# ★aspd_perm 是本项目的"永久攻速乘子"字段(贝母021 等也用它),
			#   在主循环算 atk_cd 时除进去 —— 见 RealtimeBattle3DScene 的 atk_cd 那一行。
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + [0.40, 0.80, 1.50][si]   # ★D16: 乘→加(同上)
			stt["dart_hits"] = 0        # 普攻计数(每 5 下强化一次)
		"p2eq_016":   # 铁壁盾: 每段非真实伤害固定减 3/6/10 (flat_dr, 叠加多件取和·用户2026-07-19)
			u["flat_dr"] = float(u.get("flat_dr", 0.0)) + [3.0, 6.0, 10.0][si]
		"p2eq_024":   # 龙蛋: 装备即3层吐息
			stt["dragon_stacks"] = 3
		"p2eq_039":   # 竹制弓箭: 生长充能数 (6/10/15 次·用户2026-07-19 从 1/1/3 提上来)
			stt["bamboo_charges"] = [6, 10, 15][si]   # 用户2026-07-19: 1/1/3 → 6/10/15 (一局重置: eq_state每场重建)
		"p2eq_052":   # 左轮: 6发子弹
			stt["revolver_bullets"] = EquipSystem.REVOLVER_AMMO
		"p2eq_027":   # 电棍: 3/4/5 层电击(逐星)
			stt["baton_charges"] = [3, 4, 5][si]
		"p2eq_058":   # 穿甲遗弹(重做·用户2026-07-19): 登场召唤炮台 (延到首帧spawn, 同032)
			u["_turret_pending"] = true
			u["_turret_si"] = si
		"p2eq_032":   # 唤灵骨符: 登场召唤亡灵骷髅 (延到首帧spawn, 避免开战setup中append battle._units)
			u["_skele_pending"] = true
			u["_skele_si"] = si
		"p2eq_047":   # 重击锤: ATK += maxHp×pct (一次性按当前maxHp折算)
			u["hammer_pct"] = float(u.get("hammer_pct", 0.0)) + [0.04, 0.06, 0.15][si]   # 重击锤: 随maxHp动态(在_recalc_stats累加), 多件叠加
			battle._recalc_stats(u)
		"p2eq_041":   # 退潮浊液: 登场5秒后涨潮(临时+maxHp/+攻击/+体积/+射程), 到期退潮还原(用户2026-07-19)
			var hp41: float = [250.0, 400.0, 650.0][si]   # 装备hp是最终值, 不乘HP_MULT
			var atk41: float = [10.0, 16.0, 25.0][si]
			var dur41: float = [8.0, 11.0, 15.0][si]
			battle._pending_shots.append({"delay": EquipSystem.TIDE_DELAY, "fn": func(): battle._equip_sys._eq_ebb_surge(u, hp41, atk41, dur41), "src": u})
		"p2eq_035":   # 黄铜齿轮: 本局累计产币数(显示用)
			stt["coins_made"] = 0
		"p2eq_034":   # 玩偶小熊: 大熊层 + 已销毁标记 + 每4s派小熊计时 + 蓄力标记
			stt["bear_layers"] = 0
			stt["bear_done"] = false
			stt["doll_si"] = si
			stt["doll_t"] = 0.0
			stt["bear_charging"] = false
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag) + 受伤治疗最低血%友军累积充能
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
			stt["anchor_accum"] = 0.0    # 累积治疗, 满 ANCHOR_ACC_PER_CHARGE(250)→+1充能
			stt["anchor_charges"] = 0    # 沉锚充能 (施法时消耗)
		"p2eq_011":   # 饮血护符坠: 溢出治疗转血护盾 (累积上限200/350/500, 多件取最大上限)
			u["overheal2shield_cap"] = maxf(float(u.get("overheal2shield_cap", 0.0)), [200.0, 350.0, 500.0][si])
		# ══ 批③(2026-08-05) 常驻字段类 —— 值写在这里, 消费点在 EquipSystem / battle_damage ══
		#    ★为什么走"常驻字段 + 中央管线守卫"而不是每次伤害遍历 equips:
		#      伤害管线每帧跑成百上千次, 遍历 equips 是【所有 95 件装备的公共开销】;
		#      写成字段后, 不带这几件的单位在管线上只多一次 `dict.get` 且拿到默认值。
		#    ★换路会整体重建单位字典 → 本函数在每一路的开战管线里重跑 → 字段自动重写(方案书 R5)。
		# ══ 灵物 5 件(2026-08-05 用户逐件重做·§0.5 定稿) ══════════════════════
		#    ★p2eq_063 原来在这里写 `_ink_sac`(幽影墨囊·致命伤留 1 血)。063 已整条重做成
		#      【白鲸气环】, 那两行随之删掉 ⇒ `_ink_sac` 通道进入休眠(函数留着, 见
		#      EquipSystem._eq_ink_sac 的头注: 调用点在 battle_damage 两条路上, 删不得)。
		#    ★下面两件只写【常驻字段】: 消费点是 EqSpiritBatch.tick_unit(每帧, 在
		#      EquipSystem._eq_tick 的 EQ_TICK 闸之前)。不带这两件的单位每帧只多两次 dict.get。
		#    ★多件同带取【星级更高的那一件】: 两件 060 各跑一套 7 秒计时会让减伤几乎常驻,
		#      那是另一个量级 —— 取 max 与 082/084/071 的口径一致。
		"p2eq_060":   # 磷光水母伞: 每 7 秒开伞 2.5 秒(减伤 + 闪避 + 结束回血), 自管两相计时
			u["_parasol_si"] = maxi(int(u.get("_parasol_si", -1)), si)
			stt["pa_t"] = 0.0
			stt["pa_open"] = false
			stt["pa_units"] = []
			stt["pa_dr"] = 0.0
		"p2eq_062":   # 螳螂虾钳: 闪避蓄一发强化普攻(2 秒 CD 卡触发) —— 效果本体 EqSpiritBatch
			# ★★这里【必须】把 eq_state 的槽先建出来, 哪怕两个值都是默认值:
			#   `_eq_on_hit` 的循环是 `var stt = src["eq_state"].get(iid, {})` … 末尾
			#   `src["eq_state"][iid] = stt`。槽不存在时外层拿到的是一个**新的空字典**,
			#   而效果函数里写进去的是**另一个**字典 ⇒ 循环末尾那一行会把效果写的东西整个盖掉。
			#   槽存在时两边拿到的是同一个对象(Godot 的 Dictionary 是引用), 才不会互相覆盖。
			stt["emp_ready"] = false
			stt["emp_cd_until"] = 0.0
		"p2eq_064":   # 溺者的浮囊: 首次跌破 35% 血 → 幽灵护盾(每路一次, eq_state 换路重建)
			u["_bladder_si"] = maxi(int(u.get("_bladder_si", -1)), si)
			stt["ghost_fired"] = false
			stt["ghost_res"] = 0.0
			stt["ghost_vfx"] = null
		# ★★这里原来有 082「砗磲护心甲·护盾存在时额外减伤 8/14/22%」(`_clam_dr`)
		#   与 084「血牙巨剑·半血 +攻击力 +吸血」(`_fang_pct`/`_fang_ls`/`_fang_on`)。
		#   2026-08-06 用户把这两件整条重做 —— 082 变成【护心反伤】(每受一段攻击反伤魔法,
		#   每 15 次攒一层, 普攻消耗一层回血 + 附带 100% 魔抗魔伤), 084 变成【手半剑】
		#   (近战/远程两套完全不同的行为) ⇒ 两组常驻字段整批作废, 消费点也一并撤掉。
		# ══ 食物 4 件(2026-08-05 用户逐件重做·§0.5 定稿) ══════════════════════
		#    效果本体全在 scripts/systems/equip/eq_food_batch.gd。这里只立【一个常驻守卫字段】,
		#    让每帧的 `EquipSystem._eq_tick` 认得出"这只龟身上有食物件"而不必遍历 equips
		#    (伤害/tick 是全 95 件装备的公共热路径, 不带这四件的单位只多一次 dict.get)。
		#    ★换路会整体重建单位 ⇒ 本函数在每一路的开战管线里重跑 ⇒ 字段自动重写(每路重置)。
		#    ★★071 这里原来是「暖流海带汤: 受到治疗时把 25/40/60% 分给血量最低的友军」——
		#      用户已把它整条重做成【炼乳罐】(全队奶油护盾 + 破盾 AOE + 整路 buff), 旧效果作废。
		#      ⚠ 诚实记录: `battle_damage.gd:465` 那个 `_kelp_share > 0` 的调用点仍在
		#      (那个文件归主会话), 但 `_kelp_share` 从此【零写入】⇒ 那条守卫恒不成立、永不进入。
		"p2eq_069", "p2eq_070", "p2eq_071", "p2eq_072":
			u["_food_eq"] = true
		# ★这里原来有 085/086 的 `_b3_gadget`(受法术伤害时掷骰充能 / 减速+反弹)
		#   与 094「觉醒之核」的 `awk_t0`/`awk_done`(本路开打时刻)。三件都已整条重做
		#   (085 → 压电陶瓷片: 受【所有】伤害按比例转龟能; 086 → 六分仪浮游炮; 094 → 祖龟碑:
		#   阵亡才立碑) ⇒ 旧字段作废。批④ 统一的登场标记 `_b4_eq` 在 `_b4_on_spawn_all` 里写。
		"p2eq_036":   # 温泉蛋: 孵化进度 → 临时等级(上限随星级) → 满级全队均摊护盾(一次) + 携带者每秒回血
			stt["incub"] = 0.0
			stt["incub_given"] = false
			stt["egg_levels"] = 0
			stt["incub_shield"] = [300.0, 400.0, 600.0][si]
			# ★等级上限 3 → 3/4/5 随星级(用户 2026-08-01)。原来写死 3 → 1★和3★的成长天花板一模一样,
			#   升星只多给护盾数字, 玩家感受不到"这颗蛋更强"。上限存进 eq_state 而不是每次现算,
			#   因为 _egg_add_progress(u, amt) 拿不到 si(它只有单位和增量)。
			stt["egg_cap"] = [3, 4, 5][si]
			stt["heal_ps"] = [5.0, 7.0, 10.0][si]   # 携带者每秒回血(用户 2026-08-01 新效果)
			u["has_egg"] = true
		# ══ 药水四件(2026-08-05 用户逐件重做·§0.5 定稿) ═══════════════════
		#    效果本体在 scripts/systems/equip/eq_potion_batch.gd。这里只做两件事:
		#    ① 点亮每帧守卫 `_potion_tick`(EquipSystem._eq_tick 靠它决定要不要调 tick_unit,
		#       不带这四件的单位只多一次 dict.get);
		#    ② 预置【本路】的起算时刻 —— 066「第 11 秒」/ 068「第 12 秒」都是
		#       CLAUDE.md §3.4 那颗地雷: battle._t 跨上路/下路/决胜累加、永不重置,
		#       直接判 `_t >= 11` 会让**下路一开场就触发**。本函数跑在【每一路的开战管线】里,
		#       所以它记的正好是"本路开打"(同 094 觉醒之核)。
		"p2eq_065":   # 鲨肝油: 每次普攻叠攻速(不设上限·换路重置=单位重建天然带来的)
			u["_potion_tick"] = true
			stt["oil_stacks"] = 0
		"p2eq_066":   # 鲸涎浓浆: 本路第 11 秒喝药 → 免疫控制 + 十项属性 + 体型 +40%
			u["_potion_tick"] = true
			stt["brew_t0"] = battle._t
			stt["brew_done"] = false
		"p2eq_067":   # 毒药瓶: 每 6 秒投瓶(周期表) + 中毒者治疗/护盾减半(每帧)
			u["_potion_tick"] = true
			stt["vial_thrown"] = 0
		"p2eq_068":   # 深海气压罐: 受伤充能, 本路第 12 秒起每 12 秒释放法力护盾 + 法力激光
			u["_potion_tick"] = true
			stt["can_t0"] = battle._t
			stt["can_charge"] = 0.0
			stt["can_fired"] = 0
	u["eq_state"][item_id] = stt
