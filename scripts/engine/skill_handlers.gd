class_name SkillHandlers extends RefCounted

const Phase2EquipRuntime := preload("res://scripts/engine/phase2_equip_runtime.gd")   # 010 横扫 sweep()

## SkillHandlers — 技能 type 派发器
##
## 输入: caster + target + 所有 fighters + skill 数据
## 输出: ExecutionResult Dictionary, 描述这次技能造成了什么(给 BattleScene 做飘字/日志/视觉)
##
## ExecutionResult 字段:
##   {
##     "type": "damage"/"heal"/"shield"/"none",
##     "effects": [{target_idx, value, kind: "damage"/"heal"/"shield"}, ...],
##     "log_text": "小龟 → 攻击 → 大龟 -42",
##   }
##
## W5a 支持的 type (其他 fallback 到 physical):
##   - physical: 物理伤害, hits × atkScale (W3-W4 已实现, 这里走 Damage.calc_damage)
##   - magic:    魔法伤害 (走 mr 减伤)
##   - heal:     治疗 (selfCast/isAlly 决定目标; healPct/healHpPct/healAmt 决定数值)
##   - shield:   护盾 (selfCast/aoeAlly; shieldFlat + ATK×shieldAtkScale + maxHp×shieldHpPct/100)
##
## 不支持 (W6+):
##   - 100+ 命名 type (basicChiwave/phoenixBurn/iceSpike/...) → fallback 到 physical
##   - DoT (burn/poison/bleed): 等加 buff 系统再做
##   - 嘲讽 / 净化 / 复活 / 抽装备 等控制系
##   - 召唤物 / 装备 proc / 被动


# ─── 主派发函数 ────────────────────────────────────────────────

## 当前回合数 (BattleScene 每 round 设置), 供 starWormhole turnDmgPct 等读
static var current_turn: int = 1


static func execute(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var skill_type: String = skill.get("type", "physical")

	match skill_type:
		"physical":
			if skill.get("eliteRowSplit", false):
				return _minion_elite_split(caster, target, all_fighters, skill)   # 深海小将精英 整排均摊
			return _do_physical(caster, target, all_fighters, skill, "physical")
		"magic":
			if skill.get("prismBonus", false):
				return _rainbow_beam(caster, target, all_fighters, skill)   # A6: 七彩光束 + 棱镜色加成
			return _do_physical(caster, target, all_fighters, skill, "magic")
		"heal":
			return _do_heal(caster, target, all_fighters, skill)
		"shield":
			return _do_shield(caster, all_fighters, skill)
		"p2Sweep":
			# 010 激光长刃 授予的【横扫】主动技 (0龟能): 委托 phase2 runtime sweep() (横扫列/全体+竖斩+回血)
			var sw_fx: Array = Phase2EquipRuntime.sweep(caster, target, int(skill.get("p2Star", 1)), all_fighters)
			return {"type": "damage", "effects": sw_fx, "log_text": "%s ⚡横扫!" % caster.get("name", "?"), "caster_idx": all_fighters.find(caster)}

		# ─── T2 技能 (1:1 PoC, 数据真值已确认) ───
		"phoenixBurn":
			# 单体魔法 atk×0.9 + burn = max(1, round(atk×0.53))
			return _magic_then_dot(caster, target, all_fighters, skill, "burn", 0.53)
		"lavaBolt":
			# 单体魔法 atk×0.9 + hpBonus(target maxHp×8% 不减) + burn(默认0.67)
			return _lava_bolt(caster, target, all_fighters, skill)
		"lavaQuake":
			# 全敌魔法 atk×0.6 + mrDown 20% 4t
			return _magic_then_debuff(caster, target, all_fighters, skill, "mrDown", 20, 4, "magic", "overwrite")
		"lavaSurge":
			# 单体魔法 atk×1.5 + 自盾 atk×80%
			return _magic_then_self_shield(caster, target, all_fighters, skill, 0.80)
		"lavaSplash":
			# 全敌 3 段魔法 atk×0.2 + burn(默认0.67)
			return _magic_then_dot(caster, target, all_fighters, skill, "burn", -1.0)
		"iceFrost":
			# 全敌 10 段魔法 atk×0.18 + mrDown 25% 5t (先 debuff 后伤害, 已 recalc)
			return _ice_frost(caster, target, all_fighters, skill)
		"iceFreeze":
			# 单体魔法 atk×0.6 + 必中 stun 1 回合
			return _ice_freeze(caster, target, all_fighters, skill)
		"bambooSmack":
			# 单体物理 atk×1.0 + chilled 1/2t + knockToFront 击至前排 (1:1 PoC skill-handlers.ts:2597)
			return _bamboo_smack(caster, target, all_fighters, skill)
		"twoHeadFear":
			# 单体物理 atk×0.9 + fear 20% 4t
			return _magic_then_debuff(caster, target, all_fighters, skill, "fear", 20, 4, "physical", "overwrite")
		"hunterMark":
			# 单体物理 atk×1.6 + hunterMark 24% 处决标记 4t
			return _hunter_mark(caster, target, all_fighters, skill)
		"diamondCollide":
			# 物理 atk×0.8+def×0.9+mr×0.9+maxHp×8% + 满 2 次撞击眩晕
			return _diamond_collide(caster, target, all_fighters, skill)
		"diamondSmash":
			# dealRaw def×1+mr×1+atk×0.1 (无减免无暴击) + bleed 9 层
			return _diamond_smash(caster, target, all_fighters, skill)
		"phoenixScald":
			# 单体魔法 atk×0.7 + 破盾50% + atk/def/mrDown15% + burn + healReduce
			return _phoenix_scald(caster, target, all_fighters, skill)
		"piratePlunder":
			# 单体物理 atk×0.8 + 破盾50% + 偷甲/抗各20%
			return _pirate_plunder(caster, target, all_fighters, skill)
		"diamondFortify":
			# 自盾 maxHp×20% + 自 defUp/mrUp = atk×20% 4t
			return _diamond_fortify(caster, all_fighters, skill)
		"crystalBarrier":
			# 自盾 atk×0.9 + 全友 def/mrUp 15% 4t
			return _crystal_barrier(caster, all_fighters, skill)
		"diceFate":
			# 自 buff 随机暴击 40~130% 6t
			return _dice_fate(caster, all_fighters, skill)

		# ─── A 组: 标准伤害技能 (纯 atkScale/hits/aoe + currentHpPct, 无附加或简单 DoT/buff) ───
		# 8 只无专属龟的普攻 + 各龟 AOE — 直接走 _do_physical 用各自 dmgType
		"bambooLeaf", "bambooSpikes", \
		"crystalSpike":
			return _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
		# pirateCannonBarrage: 开炮前对全敌飘"炮击!"紫色警告 (1:1 PoC skill-handlers.ts:5326-5340) + 6波AOE物理
		"pirateCannonBarrage":
			var pc_res: Dictionary = _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
			var pc_warn: Array = []
			for pe in _alive_enemies(caster, all_fighters):
				pc_warn.append({"target_idx": _find_idx(pe, all_fighters), "kind": "passive", "label": "炮击!"})
			pc_warn.append_array(pc_res["effects"])
			pc_res["effects"] = pc_warn
			return pc_res
		# ninjaShuriken: 单发, 暴击时 (40+2×lv)% 伤害转真伤穿甲 + 余物理 (1:1 PoC; 原走_do_physical=暴击全砸物理对甲少伤)
		"ninjaShuriken":
			return _ninja_shuriken(caster, target, all_fighters, skill)
		# ninjaBackstab: 出手前 +5穿甲 buff(1:1 PoC armorPenBuff; 原漏=3段背刺对甲少伤), 再3段物理
		"ninjaBackstab":
			Buffs.add(caster, "armorPen", skill.get("armorPenBuff", 5), int(skill.get("armorPenTurns", 1)) + 1)
			StatsRecalc.recalc(caster)
			return _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
		# headlessSoulStrike: 字段名 targetCurrentHpPct, _do_physical 只认 currentHpPct → remap (A10 修漏读20%当前HP魔法伤害)
		"headlessSoulStrike":
			var hs: Dictionary = skill.duplicate()
			hs["currentHpPct"] = skill.get("targetCurrentHpPct", 0)
			hs["noDodge"] = true   # PoC headlessSoulStrike applyRawDamage直落=必中 (skill-handlers.ts:5382)
			return _do_physical(caster, target, all_fighters, hs, str(skill.get("dmgType", "magic")))
		# A4 diceAttack: totalBase=round(atk×atkScale)+round(crit×critBonusMult), perHit=totalBase/hits (修漏critBonusMult+误当每段)
		"diceAttack":
			return _dice_attack(caster, target, all_fighters, skill)
		# A5 gamblerDraw 万能牌: 2段物理 + 自盾 + 自疗 + 随机8选1减益 (修漏自盾/自疗/减益)
		"gamblerDraw":
			return _gambler_draw(caster, target, all_fighters, skill)
		# A7 candyBarrage: 出手前自身 +护甲穿透 buff (修漏) then 物理
		"candyBarrage":
			var apk: float = float(skill.get("armorPenAtkPct", 0))
			var apg: int = roundi(caster.get("atk", 0) * apk / 100.0) if apk > 0 else 0
			if apg > 0:
				Buffs.add(caster, "armorPen", apg, int(skill.get("armorPenTurns", 3)) + 1)
				StatsRecalc.recalc(caster)
			var cb_res: Dictionary = _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
			if apg > 0:
				(cb_res["effects"] as Array).append({"target_idx": _find_idx(caster, all_fighters), "kind": "passive", "label": "+%d穿甲" % apg})   # 自身穿甲飘字 (1:1 PoC, 原漏)
			return cb_res
		# A8 lineSketch: 物理 + 命中叠 hits 层墨迹 (修漏)
		"lineSketch":
			var rsk: Dictionary = _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
			if target != null and not target.is_empty() and target.get("alive", false):
				_add_ink_stack(target, int(skill.get("hits", 1)), caster)
			return rsk
		# A9 lineInkBomb: 全敌物理 + 每敌叠 hits 层墨迹 (修漏)
		"lineInkBomb":
			var rib: Dictionary = _do_physical(caster, target, all_fighters, skill, str(skill.get("dmgType", "physical")))
			for e in all_fighters:
				if e.get("alive", false) and e.get("side", "") != caster.get("side", ""):
					_add_ink_stack(e, int(skill.get("hits", 1)), caster)
			return rib
		# rainbowStorm: 全敌 hits 波, 每波 magic(atkScale) + true(pierceScale) 双段 + defDown
		#   (旧版路由 _do_physical 只发 magic, 真伤段+defDown 整段丢失 — 真数值 bug)
		"rainbowStorm":
			return _rainbow_storm(caster, target, all_fighters, skill)
		# 宝箱龟: 砸击/风暴 — 完整 6 装备变种 (star/rock/thunder/chain/fire/poison, 1:1 PoC chest.js)
		"chestSmash":
			return _chest_smash(caster, target, all_fighters, skill)
		"chestStorm":
			return _chest_storm(caster, all_fighters, skill)

		# gamblerCards: 3 段每段随机 0.3~0.6×ATK
		"gamblerCards":
			return _gambler_cards(caster, target, all_fighters, skill)
		# iceSpike: 6 段交替物理/魔法 (各 0.7×ATK/3)
		"iceSpike":
			return _ice_spike(caster, target, all_fighters, skill)
		# twoHeadMagicWave: 2 段物理 + 2 段真伤 (各 0.4×ATK)
		"twoHeadMagicWave":
			return _two_head_magic_wave(caster, target, all_fighters, skill)
		# ninjaBomb: 全敌物理 atk×1.1 + armorBreak 25% 3t
		"ninjaBomb":
			return _magic_then_debuff(caster, target, all_fighters, skill, "armorBreak", 25, 4, "physical")
		# hunterPoison: 物理 atk×0.8 + poison + healReduce
		"hunterPoison":
			return _hunter_poison(caster, target, all_fighters, skill)
		# hunterBarrage: 10 发真伤 atk×0.24, 每发【随机敌】(非单体!) — 1:1 PoC alive[random] 团队分摊
		"hunterBarrage":
			return _hunter_barrage(caster, target, all_fighters, skill)
		# headlessStorm: 全敌 hits 段 atk×0.5 固定伤害(无暴击无减甲) + 临时吸血 tempLifesteal% (PoC headless.js:47)
		"headlessStorm":
			return _headless_storm(caster, all_fighters, skill)
		# angelEquality: 2 段物理 + 高稀有度追加真伤
		"angelEquality":
			return _angel_equality(caster, target, all_fighters, skill)
		# twoHeadMindBlast: 魔法 atk×1.0 + 破盾 50% + healReduce 50% 3t
		"twoHeadMindBlast":
			return _two_head_mind_blast(caster, target, all_fighters, skill)
		# 双头龟换形 + 近战形态技能
		"twoHeadSwitch":
			return _two_head_switch(caster, target, all_fighters, skill)
		"twoHeadHammer":
			return _two_head_hammer(caster, target, all_fighters, skill)
		"twoHeadAbsorb":
			return _two_head_absorb(caster, target, all_fighters, skill)
		# 熔岩龟火山形态技能
		"volcanoSmash":
			return _volcano_smash(caster, target, all_fighters, skill)
		"volcanoArmor":
			return _volcano_armor(caster, all_fighters, skill)
		"volcanoErupt":
			return _volcano_erupt(caster, target, all_fighters, skill)
		"volcanoStomp":
			return _volcano_stomp(caster, target, all_fighters, skill)

		# ─── B 组: 选择器技能 ───
		"ghostTouch":
			return _ghost_touch(caster, target, all_fighters, skill)
		"ninjaImpact":
			return _ninja_impact(caster, target, all_fighters, skill)
		"rockShockwave":
			return _rock_shockwave(caster, target, all_fighters, skill)
		"shellStrike":
			return _shell_strike(caster, target, all_fighters, skill)
		"shellErode":
			return _shell_erode(caster, target, all_fighters, skill)
		"cyberBeam":
			return _cyber_beam(caster, target, all_fighters, skill)
		"starWormhole":
			return _star_wormhole(caster, target, all_fighters, skill)
		# 太空龟星能系统
		"starBeam":
			return _star_beam(caster, target, all_fighters, skill)
		"starMeteor":
			return _star_meteor(caster, target, all_fighters, skill)
		"starBlackhole":
			return _star_blackhole(caster, target, all_fighters, skill)
		"starGravityWarp":
			return _star_gravity_warp(caster, target, all_fighters, skill)
		# 闪电龟电击层
		"lightningBarrage":
			return _lightning_barrage(caster, target, all_fighters, skill)
		"lightningSurgeBuff":
			return _lightning_surge_buff(caster, target, all_fighters, skill)
		"lightningSurge":
			return _lightning_surge(caster, target, all_fighters, skill)
		"lightningShield":
			return _lightning_shield(caster, all_fighters, skill)
		# 赛博龟浮游炮/机甲
		"cyberDeploy":
			return _cyber_deploy(caster, all_fighters, skill)
		"cyberSwarmShield", "cyberFirewall":
			return _cyber_swarm_shield(caster, all_fighters, skill)
		# fallback 技能补全
		"turtleShieldBash":
			return _turtle_shield_bash(caster, target, all_fighters, skill)
		# 激光长刃横扫 (e_laser_blade 授予) — 1:1 PoC skill-handlers.ts:616-641
		"laserSweep":
			return _laser_sweep(caster, target, all_fighters, skill)
		"bambooHeal":
			return _bamboo_heal(caster, all_fighters, skill)
		"angelBless":
			return _angel_bless(caster, target, all_fighters, skill)
		"hunterStealth":
			return _hunter_stealth(caster, target, all_fighters, skill)
		"ghostPhantom":
			return _ghost_phantom(caster, target, all_fighters, skill)
		"ghostStorm":
			return _ghost_storm(caster, target, all_fighters, skill)
		"hunterShot":
			return _hunter_shot(caster, target, all_fighters, skill)
		"soulReap":
			return _soul_reap(caster, target, all_fighters, skill)
		"diceAllIn":
			return _dice_all_in(caster, target, all_fighters, skill)
		"crystalBurst":
			return _crystal_burst(caster, target, all_fighters, skill)
		# 招财龟经济
		"fortuneStrike":
			return _fortune_strike(caster, target, all_fighters, skill)
		"fortuneDice":
			return _fortune_dice(caster, all_fighters, skill)
		"fortuneAllIn":
			return _fortune_all_in(caster, target, all_fighters, skill)
		"fortuneGainCoins":
			return _fortune_gain_coins(caster, all_fighters, skill)
		"fortuneBuyEquip":
			return _fortune_buy_equip(caster, all_fighters, skill)
		"gamblerBet":
			return _gambler_bet(caster, target, all_fighters, skill)
		"chestCount":
			return _chest_count(caster, all_fighters, skill)
		# 泡泡/墨迹/凤凰盾/龟壳
		"bubbleShield":
			return _bubble_shield(caster, target, all_fighters, skill)
		"bubbleBind":
			return _bubble_bind(caster, target, all_fighters, skill)
		"phoenixShield":
			return _phoenix_shield(caster, all_fighters, skill)
		"lineLink":
			return _line_link(caster, target, all_fighters, skill)
		"lineFinish":
			return _line_finish(caster, target, all_fighters, skill)
		"shellAbsorb":
			return _shell_absorb(caster, target, all_fighters, skill)
		"shellCopy":
			return _shell_copy(caster, target, all_fighters, skill)
		# 剩余 12 技能
		"basicBarrage":
			return _basic_barrage(caster, target, all_fighters, skill)
		"basicChiWave":
			return _basic_chi_wave(caster, target, all_fighters, skill)
		"basicSlam":
			return _basic_slam(caster, target, all_fighters, skill)
		"stoneTaunt":
			return _stone_taunt(caster, all_fighters, skill)
		"angelSmite":
			return _angel_smite(caster, target, all_fighters, skill)
		"commonTeamShield":
			return _common_team_shield(caster, all_fighters, skill)
		"ghostPhase":
			return _ghost_phase(caster, target, all_fighters, skill)
		"diceFlashStrike":
			return _dice_flash_strike(caster, target, all_fighters, skill)
		"rainbowReflect":
			return _rainbow_reflect(caster, target, all_fighters, skill)
		"bubbleBurst":
			return _bubble_burst(caster, target, all_fighters, skill)
		"bubbleHeal":
			return _bubble_heal(caster, target, all_fighters, skill)
		"phoenixPurify":
			return _phoenix_purify(caster, target, all_fighters, skill)
		# 缩头龟召唤系统
		"hidingDefend":
			return _hiding_defend(caster, all_fighters, skill)
		"hidingCommand":
			return _hiding_command(caster, all_fighters, skill)
		"hidingBuffSummon":
			return _hiding_buff_summon(caster, all_fighters, skill)
		"lightningStrike":
			return _lightning_strike(caster, target, all_fighters, skill)

		_:
			# 未实装 type: fallback 到 physical (跟 PoC AUDIT.md "未知 fallback 单段")
			var fb := _do_physical(caster, target, all_fighters, skill, "physical")
			fb["_fallback"] = true   # 覆盖率测试用标记 (test_coverage 检测未实装技能)
			return fb


# ─── 物理 / 魔法 ───────────────────────────────────────────────

## 通用物理/魔法 — 1:1 PoC skill-handlers.ts:552 physical handler
## base = atk×atkScale + def×defScale + (mr||def)×mrScale + tMaxHp×hpPct% + cMaxHp×selfHpPct%
##   注: defScale/mrScale 用 CASTER 自己的 def/mr (石头龟用防御打人); hpPct 用 TARGET maxHp
## 支持: hits 多段 / aoe 全敌 / atkDown 命中后 debuff / selfDefUpPct 出击后自盾
static func _do_physical(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary, dmg_type: String) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)

	var hits: int = skill.get("hits", 1)
	var atk_scale: float = skill.get("atkScale", 1.0)
	if atk_scale <= 0 and skill.get("defScale", 0) == 0 and skill.get("mrScale", 0) == 0 \
			and skill.get("hpPct", 0) == 0 and skill.get("selfHpPct", 0) == 0:
		atk_scale = 1.0   # 防全空字段 fallback (未知 type)
	var def_scale: float = skill.get("defScale", 0)
	var mr_scale: float = skill.get("mrScale", 0)
	var hp_pct: float = skill.get("hpPct", skill.get("targetHpPct", 0))   # target maxHp % (crystalSpike 字段名是 targetHpPct, 别名读取 — 原漏每段+3%目标maxHp)
	var cur_hp_pct: float = skill.get("currentHpPct", 0)  # target 当前 HP % (starBeam/headlessSoulStrike)
	var self_hp_pct: float = skill.get("selfHpPct", 0)
	var is_aoe: bool = skill.get("aoe", false)
	var crit_chance: float = caster.get("crit", 0.0)

	var caster_atk: float = caster.get("atk", 0)
	var caster_def: float = caster.get("def", 0)
	var caster_mr: float = caster.get("mr", caster.get("def", 0))
	var caster_maxhp: float = caster.get("maxHp", 0)

	# 目标列表: aoe → 全敌; 单体 → [target]
	var targets: Array = []
	if is_aoe:
		targets = _alive_enemies(caster, all_fighters)
	elif target != null and not target.is_empty():
		targets = [target]
	if targets.is_empty():
		return _empty_result(caster_idx)

	var effects: Array = []
	var any_crit_global: bool = false
	for t in targets:
		if not t.get("alive", false):
			continue
		var t_idx := _find_idx(t, all_fighters)
		var t_maxhp: float = t.get("maxHp", 0)
		var t_curhp: float = t.get("hp", 0)
		var base_per_hit: float = caster_atk * atk_scale \
			+ caster_def * def_scale \
			+ caster_mr * mr_scale \
			+ t_maxhp * hp_pct / 100.0 \
			+ t_curhp * cur_hp_pct / 100.0 \
			+ caster_maxhp * self_hp_pct / 100.0

		var total_dmg: int = 0
		var any_crit: bool = false
		# 多段命中逐段记录 (1:1 PoC 每 hit 一个 floatNum + 段间 sleep). hitStaggerMs 默认 500 (PoC physical).
		var seg_delay: float = float(skill.get("hitStaggerMs", 500)) / 1000.0
		var seg_list: Array = []
		for h in range(hits):
			if not t.get("alive", false):
				break
			# 闪避判定 (per-hit): 闪避则该段 0 伤害 + miss/盾/反击 effects. noDodge 技能(PoC applyRawDamage)必中跳过.
			var dodge: Dictionary = ({"dodged": false, "effects": []} if skill.get("noDodge", false) else _roll_dodge(t, caster, all_fighters))
			if dodge["dodged"]:
				for de in dodge["effects"]:
					effects.append(de)
				continue
			var is_crit: bool = Damage.roll_crit(crit_chance)
			var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
			var hit_dmg: int = Damage.calc_damage(caster, t, base_per_hit * crit_mult, dmg_type)
			var r: Dictionary = Damage.apply_raw_damage(t, hit_dmg, dmg_type)
			var shown: int = r["hpLoss"] + r["shieldAbs"]
			total_dmg += shown
			if is_crit:
				any_crit = true
				any_crit_global = true
			if shown > 0:
				seg_list.append({
					"value": shown, "dmg_type": dmg_type, "is_crit": is_crit,
					"delay": seg_list.size() * seg_delay,
					"hp_after": float(t.get("hp", 0)), "shield_after": float(t.get("shield", 0)),
				})

		if total_dmg > 0:
			var eff_d: Dictionary = {
				"target_idx": t_idx,
				"value": total_dmg,
				"kind": "damage",
				"dmg_type": dmg_type,
				"is_crit": any_crit,
			}
			# ≥2 段落地 → 逐段飘字 + 血条逐段下降 (display-only, 不改聚合 value/procs/单测)
			if seg_list.size() >= 2:
				eff_d["segments"] = seg_list
			# 实际落地段数 (shown>0 的段) — on-hit 链计数/概率类 proc 按段触发 (1:1 PoC
			#   skill-handlers.ts: triggerOnHitEffects 在 for i<hits 循环内每段调一次).
			eff_d["hits"] = maxi(1, seg_list.size())
			effects.append(eff_d)

		# atkDown debuff (命中后给 target): {pct, turns}
		var atk_down = skill.get("atkDown", null)
		if atk_down is Dictionary and t.get("alive", false) and atk_down.get("pct", 0) > 0:
			Buffs.add(t, "atkDown", atk_down.get("pct", 0), int(atk_down.get("turns", 2)) + 1)

	# selfDefUpPct (出击后给 caster 自盾): {pct, turns} — 缩头乌龟「攻击」
	var self_def = skill.get("selfDefUpPct", null)
	if self_def is Dictionary and caster.get("alive", false) and self_def.get("pct", 0) > 0:
		var gain: int = roundi(caster.get("baseDef", caster.get("def", 0)) * self_def.get("pct", 0) / 100.0)
		if gain > 0:
			Buffs.add(caster, "defUp", gain, int(self_def.get("turns", 2)) + 1)

	if effects.is_empty():
		return _empty_result(caster_idx)

	var crit_mark := "💥 " if any_crit_global else ""
	var target_label: String = ("全体 %d 敌" % targets.size()) if is_aoe else str(target.get("name", "?"))
	var total_all: int = 0
	for e in effects:
		total_all += e["value"]
	var log_text := "%s%s → %s → %s  -%d" % [
		crit_mark, caster.get("name", "?"), skill.get("name", "?"), target_label, total_all,
	]
	return {"type": "damage", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


# ══════════════════════════════════════════════════════════════
# T2 技能实现 (1:1 PoC skill-handlers.ts, 数据真值确认)
# ══════════════════════════════════════════════════════════════

## 默认灼烧层数 = max(1, round(atk × 0.67))  (PoC dot.ts:34)
static func _default_burn_stacks(caster: Dictionary) -> int:
	return maxi(1, roundi(caster.get("atk", 0) * 0.67))


## 通用: _do_physical(magic) 拿基础伤害 → 对每个被打目标施加 DoT
## dot_scale > 0: stacks = max(1, round(atk × scale)); dot_scale < 0: 用 default_burn_stacks
static func _magic_then_dot(caster: Dictionary, target: Dictionary, all_fighters: Array,
		skill: Dictionary, dot_type: String, dot_scale: float) -> Dictionary:
	var result := _do_physical(caster, target, all_fighters, skill, "magic")
	var stacks: int = _default_burn_stacks(caster) if dot_scale < 0 else maxi(1, roundi(caster.get("atk", 0) * dot_scale))
	for eff in result.get("effects", []):
		if eff.get("kind", "") == "damage":
			var t: Dictionary = all_fighters[eff["target_idx"]]
			if t.get("alive", false):
				Dot.apply_stacks(t, dot_type, stacks)
	return result


## 通用: _do_physical 拿基础伤害 → 对每个被打目标施加 stat debuff (mrDown/fear/chilled 等) + recalc
## bambooSmack: 单体物理 atk×1.0 + chilled 1/2t + knockToFront (1:1 PoC skill-handlers.ts:2597-2607)
##   目标在【后排】且【同列前排为空】→ 移到 front-col + 击至前排飘字 + relayout 视觉平移。
static func _bamboo_smack(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var res: Dictionary = _magic_then_debuff(caster, target, all_fighters, skill, "chilled", 1, 2, "physical")
	if target.get("alive", false) and str(target.get("_position", "")) == "back" and SlotHelpers.front_slot_empty(all_fighters, target):
		var parts := str(target.get("_slotKey", "")).split("-")
		var col: String = parts[parts.size() - 1] if parts.size() > 1 else ""
		target["_position"] = "front"
		if col != "":
			target["_slotKey"] = "front-%s" % col
		res["relayout"] = true
		var eff_list: Array = res.get("effects", [])
		eff_list.append({"target_idx": _find_idx(target, all_fighters), "kind": "passive", "label": "击至前排!"})
		res["effects"] = eff_list
	return res


static func _magic_then_debuff(caster: Dictionary, target: Dictionary, all_fighters: Array,
		skill: Dictionary, debuff_type: String, value: float, duration: int, dmg_type: String = "magic",
		merge_mode: String = "push") -> Dictionary:
	# merge_mode: PoC 同型 debuff 多为 max-merge(overwrite); 个别(armorBreak)是 push 叠加. 默认 push 保留旧行为.
	var result := _do_physical(caster, target, all_fighters, skill, dmg_type)
	for eff in result.get("effects", []):
		if eff.get("kind", "") == "damage":
			var t: Dictionary = all_fighters[eff["target_idx"]]
			if t.get("alive", false):
				Buffs.add(t, debuff_type, value, duration, merge_mode)
				StatsRecalc.recalc(t)   # debuff 本回合即生效
	return result


## 通用: 单体魔法 + 自盾 (atk × shield_pct)
static func _magic_then_self_shield(caster: Dictionary, target: Dictionary, all_fighters: Array,
		skill: Dictionary, shield_pct: float) -> Dictionary:
	var result := _do_physical(caster, target, all_fighters, skill, "magic")
	var shield_amt: int = roundi(caster.get("atk", 0) * shield_pct)
	if shield_amt > 0:
		shield_amt = Buffs.grant_shield(caster, shield_amt)
		var ci := _find_idx(caster, all_fighters)
		result["effects"].append({"target_idx": ci, "value": shield_amt, "kind": "shield"})
	return result


## lavaBolt: 魔法 atk×0.9 (过魔抗) + hpBonus(target maxHp×8% 不减) + burn
static func _lava_bolt(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var t_idx := _find_idx(target, all_fighters)
	var atk_scale: float = skill.get("atkScale", 0.9)
	var hp_pct: float = skill.get("targetHpPct", 8)
	var is_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))
	var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
	# 主段过魔抗
	var main_dmg: int = Damage.calc_damage(caster, target, caster.get("atk", 0) * atk_scale * crit_mult, "magic")
	# hpBonus 不被减, ×critMult
	var hp_bonus: int = roundi(target.get("maxHp", 0) * hp_pct / 100.0 * crit_mult)
	var r: Dictionary = Damage.apply_raw_damage(target, main_dmg + hp_bonus, "magic")
	var total: int = r["hpLoss"] + r["shieldAbs"]
	# burn
	Dot.apply_stacks(target, "burn", _default_burn_stacks(caster))
	var effects: Array = [{"target_idx": t_idx, "value": total, "kind": "damage", "dmg_type": "magic", "is_crit": is_crit}]
	var log_text := "%s%s → 熔岩弹 → %s  -%d" % ["💥 " if is_crit else "", caster.get("name", "?"), target.get("name", "?"), total]
	return {"type": "damage", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


## iceFrost: 先全敌 mrDown 25% 5t + recalc, 再 10 段全敌魔法 atk×0.18
static func _ice_frost(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies := _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var mr_down = skill.get("mrDown", {"pct": 25, "turns": 4})
	# 步骤1: 先 mrDown 全敌 + recalc (本回合后续段吃到)
	for e in enemies:
		Buffs.add(e, "mrDown", mr_down.get("pct", 25), int(mr_down.get("turns", 4)) + 1)
		StatsRecalc.recalc(e)
	# 步骤2: 用 _do_physical aoe + hits 打基础伤害 (现在 mr 已降)
	var aoe_skill := skill.duplicate()
	aoe_skill["aoe"] = true
	aoe_skill["noDodge"] = true   # 1:1 PoC iceFrost 走 applyRawDamage 必中(无闪避判定, skill-handlers.ts:3639); 原经 _do_physical 会 roll dodge = 偏差
	return _do_physical(caster, target, all_fighters, aoe_skill, "magic")


## iceFreeze: 单体魔法 atk×0.6 + 必中 stun 1 回合
static func _ice_freeze(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var result := _do_physical(caster, target, all_fighters, skill, "magic")
	if target != null and not target.is_empty() and target.get("alive", false):
		Buffs.add(target, "stun", 1, 2, "ignore")   # duration 2 = 跳 1 回合
		target["_stunUsed"] = false
		# 冻结施加可见化: 飘"❄️冻结"标 + 冰罩闪 (原静默, 玩家看不出被冻) — flash 走 BattleScene passive 分支
		(result["effects"] as Array).append({"target_idx": _find_idx(target, all_fighters), "kind": "passive", "label": "❄️冻结", "flash": "freeze"})
	return result


## hunterMark: 单体物理 atk×1.6 + 挂处决标记 hunterMark 24% 4t
static func _hunter_mark(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var result := _do_physical(caster, target, all_fighters, skill, "physical")
	if target != null and not target.is_empty() and target.get("alive", false):
		var exec_pct: float = skill.get("markExecPct", 24)
		var mark_turns: int = skill.get("markTurns", 3)
		Buffs.remove_all(target, "hunterMark")
		Buffs.add(target, "hunterMark", exec_pct, mark_turns + 1, "ignore")
	return result


## diamondCollide: 物理 atk×0.8+def×0.9+mr×0.9+maxHp×8% + 撞击计数满2眩晕
static func _diamond_collide(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	# _do_physical 已支持 atkScale/defScale/mrScale/selfHpPct → 直接复用
	var result := _do_physical(caster, target, all_fighters, skill, "physical")
	if target != null and not target.is_empty() and target.get("alive", false):
		var stun_after: int = skill.get("stunAfter", 2)
		var stacks: int = target.get("_diamondCollideStacks", 0) + 1
		if stacks >= stun_after:
			target["_diamondCollideStacks"] = 0
			Buffs.add(target, "stun", 1, 2, "ignore")
			target["_stunUsed"] = false
			# 满层眩晕可见化: 飘"💫眩晕"标 + 冰罩闪 (原叠层+stun全静默, 玩家看不出触发眩晕)
			(result["effects"] as Array).append({"target_idx": _find_idx(target, all_fighters), "kind": "passive", "label": "💫眩晕", "flash": "freeze"})
		else:
			target["_diamondCollideStacks"] = stacks
	return result


## diamondSmash: dealRaw def×1+mr×1+atk×0.1 (无减免无暴击) + bleed
static func _diamond_smash(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var t_idx := _find_idx(target, all_fighters)
	var dmg: int = roundi(caster.get("def", 0) * skill.get("defScale", 1)) \
		+ roundi(caster.get("mr", 0) * skill.get("mrScale", 1)) \
		+ roundi(caster.get("atk", 0) * skill.get("atkScale", 0.1))
	var r: Dictionary = Damage.apply_raw_damage(target, dmg, "physical")
	var total: int = r["hpLoss"] + r["shieldAbs"]
	# bleed = max(1, round(bleedValue × bleedTurns / 4))
	var bleed_stacks: int = maxi(1, roundi(skill.get("bleedValue", 12) * skill.get("bleedTurns", 3) / 4.0))
	Dot.apply_stacks(target, "bleed", bleed_stacks)
	var effects: Array = [{"target_idx": t_idx, "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": false}]
	var log_text := "%s → 钻石冲撞 → %s  -%d" % [caster.get("name", "?"), target.get("name", "?"), total]
	return {"type": "damage", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


## phoenixScald: 魔法 atk×0.7 + 破盾50% + atk/def/mrDown15% + burn + healReduce
static func _phoenix_scald(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	# 步骤1: 破盾 50%
	var break_pct: float = skill.get("shieldBreak", 50) / 100.0
	target["shield"] = roundi(target.get("shield", 0) * (1.0 - break_pct))
	if target.get("bubbleShieldVal", 0) > 0:
		target["bubbleShieldVal"] = roundi(target.get("bubbleShieldVal", 0) * (1.0 - break_pct))
	# 步骤2: 魔法伤害 (复用 _do_physical)
	var result := _do_physical(caster, target, all_fighters, skill, "magic")
	# 步骤3: 三 debuff (各 turns+1) + recalc
	for dt in [["atkDown", "atkDown"], ["defDown", "defDown"], ["mrDown", "mrDown"]]:
		var cfg = skill.get(dt[0], null)
		if cfg is Dictionary:
			Buffs.add(target, dt[1], cfg.get("pct", 15), int(cfg.get("turns", 4)) + 1)
	StatsRecalc.recalc(target)
	# 步骤4: burn
	Dot.apply_stacks(target, "burn", _default_burn_stacks(caster))
	# 步骤5: healReduce
	if skill.get("healReduce", false):
		Buffs.add(target, "healReduce", 50, 5, "refresh")
	return result


## piratePlunder: 物理 atk×0.8 + 破盾50% + 偷甲/抗各20% (纯 buff 模型, 不双扣)
static func _pirate_plunder(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	# 破盾 50% (含泡泡盾, A12 修漏 bubbleShieldVal — 1:1 PoC:3379)
	var break_pct: float = skill.get("shieldBreakPct", 50) / 100.0
	target["shield"] = roundi(target.get("shield", 0) * (1.0 - break_pct))
	if int(target.get("bubbleShieldVal", 0)) > 0:
		target["bubbleShieldVal"] = roundi(target.get("bubbleShieldVal", 0) * (1.0 - break_pct))
	# 主伤害
	var result := _do_physical(caster, target, all_fighters, skill, "physical")
	# 偷甲/抗: target debuff + caster buff (纯 buff, recalc 双方; 不手动改值防双扣)
	var steal_turns: int = skill.get("stealDefTurns", 3)
	var def_gain: int = roundi(target.get("baseDef", 0) * skill.get("stealDefPct", 20) / 100.0)
	var mr_gain: int = roundi(target.get("baseMr", target.get("baseDef", 0)) * skill.get("stealMrPct", 20) / 100.0)
	if def_gain > 0:
		Buffs.add(target, "defDown", skill.get("stealDefPct", 20), steal_turns)
		Buffs.add(caster, "defUp", def_gain, steal_turns)
	if mr_gain > 0:
		Buffs.add(target, "mrDown", skill.get("stealMrPct", 20), steal_turns)
		Buffs.add(caster, "mrUp", mr_gain, steal_turns)
	StatsRecalc.recalc(target)
	StatsRecalc.recalc(caster)
	return result


## diamondFortify: 自盾 maxHp×20% + 自 defUp/mrUp = atk×20% 4t
static func _diamond_fortify(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var effects: Array = []
	var shield_amt: int = roundi(roundi(caster.get("maxHp", 0) * skill.get("shieldHpPct", 20) / 100.0) * Rules.shield_mult())   # 铁壁之日 ×1.3 (原漏)
	if shield_amt > 0:
		shield_amt = Buffs.grant_shield(caster, shield_amt)
		effects.append({"target_idx": caster_idx, "value": shield_amt, "kind": "shield"})
	var turns: int = int(skill.get("defUpTurns", 3)) + 1
	var def_gain: int = roundi(caster.get("atk", 0) * skill.get("defUpAtkPct", 20) / 100.0)
	var mr_gain: int = roundi(caster.get("atk", 0) * skill.get("mrUpAtkPct", 20) / 100.0)
	if def_gain > 0:
		Buffs.add(caster, "defUp", def_gain, turns)
	if mr_gain > 0:
		Buffs.add(caster, "mrUp", mr_gain, turns)
	StatsRecalc.recalc(caster)
	var log_text := "%s → 坚不可摧 → 自盾 +%d 甲/抗强化" % [caster.get("name", "?"), shield_amt]
	return {"type": "shield", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


## crystalBarrier: 自盾 atk×0.9 + 全友 def/mrUp 15% 4t
static func _crystal_barrier(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var effects: Array = []
	# 自盾
	var shield_amt: int = roundi(roundi(caster.get("atk", 0) * skill.get("shieldAtkScale", 0.9)) * Rules.shield_mult())   # 铁壁之日 ×1.3 (原漏)
	if shield_amt > 0:
		shield_amt = Buffs.grant_shield(caster, shield_amt)
		effects.append({"target_idx": caster_idx, "value": shield_amt, "kind": "shield"})
	# 全友 def/mrUp
	var pct: float = skill.get("defMrUpPct", 15)
	var turns: int = int(skill.get("defMrUpTurns", 3)) + 1
	for i in range(all_fighters.size()):
		var ally: Dictionary = all_fighters[i]
		if ally.get("side", "") != caster.get("side", "") or not ally.get("alive", false):
			continue
		var dg: int = roundi(ally.get("baseDef", 0) * pct / 100.0)
		var mg: int = roundi(ally.get("baseMr", ally.get("baseDef", 0)) * pct / 100.0)
		if dg > 0:
			Buffs.add(ally, "defUp", dg, turns)
		if mg > 0:
			Buffs.add(ally, "mrUp", mg, turns)
		StatsRecalc.recalc(ally)
	var log_text := "%s → 水晶壁垒 → 自盾 +%d 全友 +%.0f%% 甲/抗" % [caster.get("name", "?"), shield_amt, pct]
	return {"type": "shield", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


## diceFate: 自 buff 随机暴击 [minCrit..maxCrit]% 6t, 立即生效
static func _dice_fate(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var min_crit: int = skill.get("minCrit", 40)
	var max_crit: int = skill.get("maxCrit", 130)
	var crit_gain: int = min_crit + (randi() % (max_crit - min_crit + 1))
	Buffs.add(caster, "diceFateCrit", crit_gain, int(skill.get("duration", 5)) + 1, "overwrite")
	StatsRecalc.recalc(caster)
	var ci := caster_idx
	var effects: Array = [{"target_idx": ci, "value": crit_gain, "kind": "passive", "label": "🎲 +%d%% 暴击" % crit_gain}]
	var log_text := "%s → 命运骰子 → +%d%% 暴击" % [caster.get("name", "?"), crit_gain]
	return {"type": "shield", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


# ─── 单段命中 helper (闪避 + 暴击 + 落伤) — 多段技能复用 ───
static func _one_hit(caster: Dictionary, target: Dictionary, base: float, dmg_type: String, all_fighters: Array, no_dodge: bool = false) -> Dictionary:
	# no_dodge: PoC 走 applyRawDamage 直接(不过 rollDodge)的技能 = 必中(赌神/猎人/海盗炮/糖果弹幕等)
	if not no_dodge:
		var dodge: Dictionary = _roll_dodge(target, caster, all_fighters)
		if dodge["dodged"]:
			return {"dmg": 0, "raw": 0, "dodged": true, "is_crit": false, "dodge_effects": dodge["effects"]}
	var is_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))
	var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
	var hit_dmg: int = Damage.calc_damage(caster, target, base * crit_mult, dmg_type)
	var r: Dictionary = Damage.apply_raw_damage(target, hit_dmg, dmg_type)
	# raw = 削减前算出的伤害(未被过量击杀 clamp); 龟盾/锤击的"按伤害折盾"要用 raw (1:1 PoC 用 computed 非 shown)
	return {"dmg": r["hpLoss"] + r["shieldAbs"], "raw": hit_dmg, "dodged": false, "is_crit": is_crit, "dodge_effects": []}


## 逐段飘字段 push 助手 — 1:1 PoC 每 hit 一个 floatNum. 在每次 apply_raw_damage 后立即调,
##   snapshot target 当前 hp/shield 供血条逐段下降。dmg<=0 不记 (PoC 0 伤不飘)。
##   delay=该段相对本 effect 起点的秒数; y_off=同型多段垂直错开 (如背刺 (idx-1)*18)。
static func _seg_push(seg_list: Array, dmg: int, dmg_type: String, is_crit: bool, delay: float, target: Dictionary, y_off: float = 0.0) -> void:
	if dmg <= 0:
		return
	seg_list.append({
		"value": dmg, "dmg_type": dmg_type, "is_crit": is_crit, "delay": delay, "y_off": y_off,
		"hp_after": float(target.get("hp", 0)), "shield_after": float(target.get("shield", 0)),
	})


## 组装多段单体技能的通用收尾 (effects + log). segments: ≥2 段则挂到伤害 effect 上逐段飘。
static func _multi_hit_result(caster: Dictionary, target: Dictionary, all_fighters: Array,
		skill_name: String, total_dmg: int, dmg_type: String, any_crit: bool, extra_effects: Array = [], segments: Array = []) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var t_idx := _find_idx(target, all_fighters)
	var effects: Array = []
	if total_dmg > 0:
		var ed: Dictionary = {"target_idx": t_idx, "value": total_dmg, "kind": "damage", "dmg_type": dmg_type, "is_crit": any_crit}
		if segments.size() >= 2:
			ed["segments"] = segments
		# on-hit 计数/概率类 proc 按落地段数触发 (1:1 PoC per-hit)
		ed["hits"] = maxi(1, segments.size())
		effects.append(ed)
	for e in extra_effects:
		effects.append(e)
	if effects.is_empty():
		return _empty_result(caster_idx)
	var log_text := "%s%s → %s → %s  -%d" % ["💥 " if any_crit else "", caster.get("name", "?"), skill_name, target.get("name", "?"), total_dmg]
	return {"type": "damage", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


# ─── 双头龟换形 (twoHead form swap, 1:1 PoC skill-handlers.ts:4085-4206) ───

## twoHeadSwitch: 换形 (ranged↔melee) — 改 base 属性 + 换技能集 + switch-attack
static func _two_head_switch(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var switch_to := str(skill.get("switchTo", "melee"))
	var atk: float = caster.get("atk", 0)
	var effects: Array = []
	if switch_to == "melee":
		var p = caster.get("passive", {})
		if not (p is Dictionary):
			p = {}
		# 从 passive 读 scale (别硬编码; mrGain = defGain, PoC 4100)
		var hp_gain: int = roundi(atk * p.get("hpScale", 1.5))
		var def_gain: int = roundi(atk * p.get("defScale", 0.25))
		var mr_gain: int = def_gain
		var atk_loss: int = roundi(atk * p.get("atkLossScale", 0.3))
		var shield_gain: int = roundi(atk * p.get("shieldScale", 1.1))
		caster["_formHpGain"] = hp_gain
		caster["_formDefGain"] = def_gain
		caster["_formMrGain"] = mr_gain
		caster["_formAtkLoss"] = atk_loss
		var old_max: float = caster.get("maxHp", 0)
		caster["maxHp"] = roundi(old_max) + hp_gain
		caster["hp"] = roundi(float(caster.get("hp", 0)) * caster["maxHp"] / maxf(1.0, old_max))
		caster["baseDef"] = caster.get("baseDef", 0) + def_gain
		caster["def"] = caster["baseDef"]
		caster["baseMr"] = caster.get("baseMr", caster.get("baseDef", 0)) + mr_gain
		caster["mr"] = caster["baseMr"]
		caster["baseAtk"] = caster.get("baseAtk", 0) - atk_loss
		caster["atk"] = caster["baseAtk"]
		shield_gain = Buffs.grant_shield(caster, shield_gain)
		# 换技能集: meleeSkills 按 _equippedIdxs 配对 (滤 passiveSkill); switch 技 cdLeft=cd
		var melee = caster.get("_meleeSkills", [])
		if melee is Array and not (melee as Array).is_empty():
			var eq_idxs: Array = caster.get("_equippedIdxs", [0, 1, 2])
			var paired: Array = []
			for i in eq_idxs:
				if i >= 0 and i < melee.size() and not melee[i].get("passiveSkill", false):
					var sc: Dictionary = melee[i].duplicate(true)
					sc["cdLeft"] = int(skill.get("cd", 4)) if sc.get("type", "") == "twoHeadSwitch" else 0
					paired.append(sc)
			caster["_rangedSkills"] = caster.get("skills", [])
			if paired.is_empty():
				for s in melee:
					if not s.get("passiveSkill", false):
						var sc2: Dictionary = s.duplicate(true)
						sc2["cdLeft"] = 0
						paired.append(sc2)
			caster["skills"] = paired
		caster["_twoHeadForm"] = "melee"
		effects.append({"target_idx": caster_idx, "kind": "passive", "label": "切换近战!", "color": "#c77dff"})   # 1:1 PoC 紫色换形飘字
		# switch-attack 1.2×atk 对 target (无效→最低血敌)
		var t = _switch_attack_target(caster, target, all_fighters)
		if t != null:
			var hit: Dictionary = _one_hit(caster, t, caster.get("atk", 0) * skill.get("switchAtkScale", 1.2), "physical", all_fighters)
			if not hit["dodged"] and hit["dmg"] > 0:
				effects.append({"target_idx": _find_idx(t, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	else:
		# melee → ranged: 用缓存增量还原
		if int(caster.get("_formHpGain", 0)) != 0:
			var old_max2: float = caster.get("maxHp", 0)
			caster["maxHp"] = roundi(old_max2) - int(caster.get("_formHpGain", 0))
			caster["hp"] = mini(int(caster["maxHp"]), roundi(float(caster.get("hp", 0)) * caster["maxHp"] / maxf(1.0, old_max2)))
			caster["baseDef"] = caster.get("baseDef", 0) - int(caster.get("_formDefGain", 0))
			caster["def"] = caster["baseDef"]
			caster["baseMr"] = caster.get("baseMr", caster.get("baseDef", 0)) - int(caster.get("_formMrGain", 0))
			caster["mr"] = caster["baseMr"]
			caster["baseAtk"] = caster.get("baseAtk", 0) + int(caster.get("_formAtkLoss", 0))
			caster["atk"] = caster["baseAtk"]
			caster["_formHpGain"] = 0
			caster["_formDefGain"] = 0
			caster["_formMrGain"] = 0
			caster["_formAtkLoss"] = 0
		if caster.has("_rangedSkills") and caster["_rangedSkills"] is Array:
			caster["skills"] = caster["_rangedSkills"]
			for s in caster["skills"]:
				if s.get("type", "") == "twoHeadSwitch":
					s["cdLeft"] = int(skill.get("cd", 4))
		caster["_twoHeadForm"] = "ranged"
		effects.append({"target_idx": caster_idx, "kind": "passive", "label": "切换远程!", "color": "#fbbf24"})   # 1:1 PoC 金色换形飘字
		if target != null and not target.is_empty() and target.get("alive", false):
			var hit2: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.4), "physical", all_fighters)
			if not hit2["dodged"] and hit2["dmg"] > 0:
				effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit2["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit2["is_crit"]})
			Buffs.add(target, "defDown", skill.get("defReductionPct", 25), int(skill.get("defReductionTurns", 4)) + 1)
			StatsRecalc.recalc(target)
	# 换形羁绊: 换形后 maxHp×pct 护盾 (+tier3 首次换形 ATK)
	var shift := Synergies.apply_shift(caster)
	if shift["shieldAdded"] > 0:
		effects.append({"target_idx": caster_idx, "value": shift["shieldAdded"], "kind": "shield"})
	var form_name := "近战" if caster.get("_twoHeadForm", "") == "melee" else "远程"
	return {"type": "damage", "effects": effects, "log_text": "%s → 换形(%s)" % [caster.get("name", "?"), form_name], "caster_idx": caster_idx}


## switch-attack 目标: 选定 target (敌且活), 否则全敌最低血 (PoC 4130-4133)
static func _switch_attack_target(caster: Dictionary, target: Dictionary, all_fighters: Array):
	if target != null and not target.is_empty() and target.get("alive", false) and target.get("side", "") != caster.get("side", ""):
		return target
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return null
	enemies.sort_custom(func(a, b): return float(a.get("hp", 0)) < float(b.get("hp", 0)))
	return enemies[0]


## twoHeadHammer: atkScale×ATK 物理 + shieldFromDmgPct% 造成伤害转永久护盾
static func _two_head_hammer(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.4), "physical", all_fighters)
	if hit["dodged"]:
		for de in hit["dodge_effects"]:
			effects.append(de)
		return {"type": "damage", "effects": effects, "log_text": "%s → 锤击 → 闪避" % caster.get("name", "?"), "caster_idx": caster_idx} if not effects.is_empty() else _empty_result(caster_idx)
	var dmg: int = hit["dmg"]
	if dmg > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": dmg, "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	var sh: int = roundi(int(hit.get("raw", dmg)) * skill.get("shieldFromDmgPct", 50) / 100.0)   # 用 raw(削减前) 折盾, 1:1 PoC 过量击杀仍按算出值
	if caster.get("alive", false) and sh > 0:
		sh = Buffs.grant_shield(caster, sh)
		effects.append({"target_idx": caster_idx, "value": sh, "kind": "shield"})
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 锤击 → %s  -%d (+%d🛡)" % ["💥 " if hit["is_crit"] else "", caster.get("name", "?"), target.get("name", "?"), dmg, sh], "caster_idx": caster_idx}


## twoHeadAbsorb: (atk×0.6 + tMaxHp×8%) 物理 + heal(atk×40% + 已损HP×18%)
static func _two_head_absorb(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.6)) + roundi(target.get("maxHp", 0) * skill.get("hpPct", 8) / 100.0)
	var hit: Dictionary = _one_hit(caster, target, base, "physical", all_fighters)
	if hit["dodged"]:
		for de in hit["dodge_effects"]:
			effects.append(de)
	var dmg: int = hit["dmg"]
	if dmg > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": dmg, "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	# heal = round(atk×healAtkPct%) + round(已损HP×healLostPct%)
	if caster.get("alive", false):
		var atk_heal: int = roundi(caster.get("atk", 0) * skill.get("healAtkPct", 40) / 100.0)
		var lost: int = int(caster.get("maxHp", 0)) - int(caster.get("hp", 0))
		var lost_heal: int = roundi(lost * skill.get("healLostPct", 18) / 100.0)
		var before: int = caster.get("hp", 0)
		caster["hp"] = mini(int(caster.get("maxHp", 0)), before + Buffs.fatigue_amt(caster, atk_heal + lost_heal))
		var actual: int = int(caster["hp"]) - before
		if actual > 0:
			effects.append({"target_idx": caster_idx, "value": actual, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 吸收 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## twoHeadMindBlast: atk×1.0 magic + shieldBreakPct% 破盾 + healReducePct% 治疗削减
static func _two_head_mind_blast(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var t_idx := _find_idx(target, all_fighters)
	var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.0), "magic", all_fighters)
	if hit["dodged"]:
		for de in hit["dodge_effects"]:
			effects.append(de)
	var dmg: int = hit["dmg"]
	if dmg > 0:
		effects.append({"target_idx": t_idx, "value": dmg, "kind": "damage", "dmg_type": "magic", "is_crit": hit["is_crit"]})
	# 破盾
	if target.get("alive", false) and target.get("shield", 0) > 0:
		var broken: int = roundi(target.get("shield", 0) * skill.get("shieldBreakPct", 50) / 100.0)
		target["shield"] = target.get("shield", 0) - broken
		if broken > 0:
			effects.append({"target_idx": t_idx, "kind": "passive", "label": "-%d🛡破" % broken})
	# 治疗削减
	if target.get("alive", false):
		var hr_pct: int = skill.get("healReducePct", 50)
		Buffs.add(target, "healReduce", hr_pct, int(skill.get("healReduceTurns", 3)) + 1, "refresh")
		effects.append({"target_idx": t_idx, "kind": "passive", "label": "❌治疗-%d%%" % hr_pct})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 精神干扰 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


# ─── 熔岩龟火山形态技能 (volcano, 1:1 PoC skill-handlers.ts:4570-4716) ───
# 注: PoC volcano 技能不 rollDodge (保证命中), smash/erupt 吃暴击, stomp 不吃

## 无闪避命中 (volcano 用): use_crit 控制是否 rollCrit
static func _crit_hit_no_dodge(caster: Dictionary, target: Dictionary, base: float, dmg_type: String, use_crit: bool = true) -> Dictionary:
	var is_crit: bool = use_crit and Damage.roll_crit(caster.get("crit", 0.0))
	var cm: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
	var d: int = Damage.calc_damage(caster, target, base * cm, dmg_type)
	var r: Dictionary = Damage.apply_raw_damage(target, d, dmg_type)
	return {"dmg": r["hpLoss"] + r["shieldAbs"], "is_crit": is_crit}


# ─── fallback 技能补全 (1:1 PoC, agent 提取真值) ───

## turtleShieldBash(basic): 单段物理 atk×0.7 + 已损血×lostHpPct%
static func _turtle_shield_bash(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.7))
	base += roundi((int(target.get("maxHp", 0)) - int(target.get("hp", 0))) * skill.get("lostHpPct", 20) / 100.0)
	var hit: Dictionary = _one_hit(caster, target, base, "physical", all_fighters)
	var effects: Array = []
	if hit["dodged"]:
		for de in hit["dodge_effects"]: effects.append(de)
	elif hit["dmg"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	# 龟盾核心: 获得 80% 伤害值的永久护盾 (1:1 PoC turtleShieldBash:766-768) — 原 handler 漏了护盾!
	var shield_gain := int(roundi(int(hit.get("raw", hit["dmg"])) * float(skill.get("shieldFromDmgPct", 80)) / 100.0))   # raw(削减前)折盾, 1:1 PoC
	if shield_gain > 0 and caster.get("alive", false):
		shield_gain = Buffs.grant_shield(caster, shield_gain)
		effects.append({"target_idx": caster_idx, "value": shield_gain, "kind": "shield"})
	# 击飞 → 标记靶子 (PoC api.knockup 设 _knockedUpThisTurn, e_dart 侧回合末读) — 仅命中存活时
	#   017不沉之锚 _p2AnchorImmune / 龟蛋 _eggImmune 免疫击飞控制 → 不标记 (统一收口 _mark_knockup)
	if not hit["dodged"]:
		_mark_knockup(target)
	if effects.is_empty():
		return _empty_result(caster_idx)
	var sg_txt := " +%d永久盾" % shield_gain if shield_gain > 0 else ""
	return {"type": "damage", "effects": effects, "log_text": "%s → 盾击 → %s%s" % [caster.get("name", "?"), target.get("name", "?"), sg_txt], "caster_idx": caster_idx}


## diceAttack: totalBase=round(atk×atkScale)+round(crit×critBonusMult), perHit=round(totalBase/hits), 每段独立crit+def (1:1 PoC:2638-2651)
static func _dice_attack(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var hits: int = int(skill.get("hits", 3))
	var total_base: int = roundi(caster.get("atk", 0) * float(skill.get("atkScale", 0.9))) + roundi(caster.get("crit", 0.0) * float(skill.get("critBonusMult", 55)))
	var per_hit: int = int(roundi(float(total_base) / float(maxi(1, hits))))
	var effects: Array = []
	var any_crit := false
	for i in range(hits):
		if not target.get("alive", false):
			break
		var hit: Dictionary = _one_hit(caster, target, per_hit, "physical", all_fighters, true)   # PoC diceAttack applyRawDamage直落=必中 (不判闪避)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
			continue
		if hit["dmg"] > 0:
			effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
			if hit["is_crit"]:
				any_crit = true
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 骰子攻击 → %s" % ["💥 " if any_crit else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## gamblerDraw 万能牌: 2段物理 + 自盾(selfShieldAtkPct) + 自疗(selfHealAtkPct) + 随机8选1减益 (1:1 PoC:4805-4865)
static func _gambler_draw(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty():
		return _empty_result(caster_idx)
	var per_hit: int = roundi(caster.get("atk", 0) * float(skill.get("atkScale", 0.5)))
	var effects: Array = []
	for i in range(2):
		if not target.get("alive", false):
			break
		var hit: Dictionary = _one_hit(caster, target, per_hit, "physical", all_fighters, true)   # 万能牌2段必中 (1:1 PoC applyRawDamage)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
			continue
		if hit["dmg"] > 0:
			effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	# 自身永久护盾 + 回血
	var sh: int = roundi(caster.get("atk", 0) * float(skill.get("selfShieldAtkPct", 25)) / 100.0)
	if sh > 0 and caster.get("alive", false):
		sh = Buffs.grant_shield(caster, sh)
		effects.append({"target_idx": caster_idx, "value": sh, "kind": "shield"})
	var hl: int = roundi(caster.get("atk", 0) * float(skill.get("selfHealAtkPct", 25)) / 100.0)
	if hl > 0 and caster.get("alive", false):
		var healed: int = _heal_to(caster, hl)
		if healed > 0:
			effects.append({"target_idx": caster_idx, "value": healed, "kind": "heal"})
	# 随机 8 选 1 减益 (1:1 PoC:4842) — 减益类 duration+1 适配 Godot turn-begin 递减
	if target.get("alive", false):
		var dot_stacks: int = maxi(1, roundi(caster.get("atk", 0) * 0.11))
		match randi() % 8:
			0: Buffs.add(target, "atkDown", 20, 3)   # 1:1 PoC duration 3 (原+1=4 多1回合)
			1: Buffs.add(target, "defDown", 20, 3)   # 1:1 PoC duration 3
			2: Buffs.add(target, "mrDown", 20, 3)   # 1:1 PoC duration 3
			3: Buffs.add(target, "healReduce", 50, 3)   # 1:1 PoC duration 3
			4: Dot.apply_stacks(target, "poison", dot_stacks)
			5: Dot.apply_stacks(target, "bleed", dot_stacks)
			6: Dot.apply_stacks(target, "burn", dot_stacks)
			7: Buffs.add(target, "chilled", 1, 2)   # 1:1 PoC duration 2 (原+1=3)
		StatsRecalc.recalc(target)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 万能牌 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## 七彩光束(magic prismBonus): 2段魔法 + 当前棱镜色加成 (1:1 PoC magic:5748-5776)
##   0红→target吃总伤20%真伤 / 1蓝→自身+20%ATK盾 / 2绿→自身回5%maxHp
static func _rainbow_beam(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	if target == null or target.is_empty():
		return _empty_result(_find_idx(caster, all_fighters))
	var res: Dictionary = _do_physical(caster, target, all_fighters, skill, "magic")
	if not caster.get("alive", false):
		return res
	var effs: Array = res.get("effects", [])
	var total_direct: int = 0
	for e in effs:
		if e is Dictionary and e.get("kind", "") == "damage":
			total_direct += int(e.get("value", 0))
	var color: int = int(caster.get("_prismColor", -1))
	if color == 0 and target.get("alive", false):           # 红: 总伤×20% 真伤
		var bonus: int = roundi(total_direct * 0.2)
		if bonus > 0:
			var r: Dictionary = Damage.apply_raw_damage(target, bonus, "true")
			effs.append({"target_idx": _find_idx(target, all_fighters), "value": int(r["hpLoss"]) + int(r["shieldAbs"]), "kind": "damage", "dmg_type": "true"})
	elif color == 1:                                         # 蓝: 自身 +20%ATK 盾
		var sh: int = roundi(caster.get("atk", 0) * 0.2)
		if sh > 0:
			sh = Buffs.grant_shield(caster, sh)
			effs.append({"target_idx": _find_idx(caster, all_fighters), "value": sh, "kind": "shield"})
	elif color == 2:                                         # 绿: 自身回 5%maxHp
		var hl: int = roundi(caster.get("maxHp", 0) * 0.05)
		if hl > 0:
			var healed: int = _heal_to(caster, hl)
			if healed > 0:
				effs.append({"target_idx": _find_idx(caster, all_fighters), "value": healed, "kind": "heal"})
	res["effects"] = effs
	return res


## 深海小将精英「整排均摊伤害」(设计文档§3): 打【目标所在整排】(前/后)存活敌人,
##   总伤 = ATK×atkScale, 由该排存活敌人【均摊】(每只 = 总伤÷人数; 仅1人→全额) — 1:1 糖果炸弹"均摊"口径.
##   可暴击(每段独立)/可闪避. type 仍 physical → 目标选取走单选敌(front-guard), 此处展开到整排.
static func _minion_elite_split(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty():
		return _empty_result(caster_idx)
	var t_row: String = "back" if str(target.get("_slotKey", "front-0")).begins_with("back") else "front"
	var row_enemies: Array = []
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != caster.get("side", "") \
				and str(f.get("_slotKey", "front-0")).begins_with(t_row):
			row_enemies.append(f)
	var list: Array = row_enemies if not row_enemies.is_empty() else [target]
	var total_raw: float = caster.get("atk", 0) * float(skill.get("atkScale", 1.4))   # 总伤 = ATK×scale
	var per_raw: float = total_raw / float(maxi(1, list.size()))                       # 均摊: 总÷存活人数
	var effects: Array = []
	var any_crit: bool = false
	for t in list:
		if not t.get("alive", false):
			continue
		var hit: Dictionary = _one_hit(caster, t, per_raw, "physical", all_fighters)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
			continue
		var dmg: int = hit["dmg"]
		if dmg > 0:
			effects.append({"target_idx": _find_idx(t, all_fighters), "value": dmg, "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
			if hit["is_crit"]:
				any_crit = true
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 整排均摊 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), list.size()], "caster_idx": caster_idx}


## laserSweep (激光长刃横扫) — 1:1 PoC skill-handlers.ts:616-641
## 目标所在【前排/后排】整排存活敌人各 0.7×ATK 物理 (暴击); 该排仅 1 名 → 1.4×ATK;
## 携带者回血 = 横扫造成总伤害 × 80%。
static func _laser_sweep(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty():
		return _empty_result(caster_idx)
	# target 所在排 (back/front), 取 _slotKey 前缀 (PoC startsWith('back'))
	var t_row: String = "back" if str(target.get("_slotKey", "front-0")).begins_with("back") else "front"
	var row_enemies: Array = []
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != caster.get("side", "") \
				and str(f.get("_slotKey", "front-0")).begins_with(t_row):
			row_enemies.append(f)
	var list: Array = row_enemies if not row_enemies.is_empty() else [target]
	var solo: bool = list.size() == 1
	var atk_scale: float = skill.get("soloScale", 1.4) if solo else skill.get("atkScale", 0.7)
	var heal_pct: float = skill.get("lifestealPct", 80)
	var total_dealt: int = 0
	var effects: Array = []
	var any_crit: bool = false
	for t in list:
		if not t.get("alive", false):
			continue
		var hit: Dictionary = _one_hit(caster, t, caster.get("atk", 0) * atk_scale, "physical", all_fighters)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
			continue
		var dmg: int = hit["dmg"]
		total_dealt += dmg
		if dmg > 0:
			effects.append({"target_idx": _find_idx(t, all_fighters), "value": dmg, "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
			if hit["is_crit"]:
				any_crit = true
	# 携带者回血 = 总伤害 × 80% (走 _heal_to 吃 healReduce)
	if total_dealt > 0 and heal_pct > 0 and caster.get("alive", false):
		var healed: int = _heal_to(caster, roundi(total_dealt * heal_pct / 100.0))
		if healed > 0:
			effects.append({"target_idx": caster_idx, "value": healed, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 横扫 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), list.size()], "caster_idx": caster_idx}


## bambooHeal(bamboo): 有友→自疗10% + 每友盾(maxHp×12%×shieldMult); 无友→自疗15%
static func _bamboo_heal(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var allies: Array = []
	for a in all_fighters:
		if a.get("side", "") == caster.get("side", "") and a.get("alive", false) and a != caster:
			allies.append(a)
	var effects: Array = []
	if allies.is_empty():
		var h: int = roundi(caster.get("maxHp", 0) * skill.get("soloHealPct", 15) / 100.0)
		var hd := _heal_to(caster, h)
		if hd > 0: effects.append({"target_idx": caster_idx, "value": hd, "kind": "heal"})
	else:
		var h2: int = roundi(caster.get("maxHp", 0) * skill.get("healPct", 10) / 100.0)
		var hd2 := _heal_to(caster, h2)
		if hd2 > 0: effects.append({"target_idx": caster_idx, "value": hd2, "kind": "heal"})
		var sh: int = roundi(roundi(caster.get("maxHp", 0) * skill.get("shieldPct", 12) / 100.0) * Rules.shield_mult())
		for a in allies:
			var sh_a := Buffs.grant_shield(a, sh)
			effects.append({"target_idx": _find_idx(a, all_fighters), "value": sh_a, "kind": "shield"})
	return {"type": "heal", "effects": effects, "log_text": "%s → 竹林治愈" % caster.get("name", "?"), "caster_idx": caster_idx}


## angelBless(angel): 自盾 atk×1.2×shieldMult + 自 defUp/mrUp = atk×0.15
## angelBless(angel): 给友军 target 永久盾 + defUp/mrUp(值取 caster.atk); 无 target 退化给自己 (1:1 PoC:1251-1268)
static func _angel_bless(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var tgt: Dictionary = target if (target != null and not target.is_empty()) else caster
	var tgt_idx := _find_idx(tgt, all_fighters)
	var sh: int = roundi(roundi(caster.get("atk", 0) * skill.get("shieldScale", 1.2)) * Rules.shield_mult())
	sh = Buffs.grant_shield(tgt, sh)
	var gain: int = roundi(caster.get("atk", 0) * skill.get("defBoostScale", 0.15))
	var turns: int = int(skill.get("defBoostTurns", 4)) + 1
	if gain > 0:
		Buffs.add(tgt, "defUp", gain, turns)
		Buffs.add(tgt, "mrUp", gain, turns)
		StatsRecalc.recalc(tgt)
	return {"type": "shield", "effects": [{"target_idx": tgt_idx, "value": sh, "kind": "shield"}], "log_text": "%s → 祝福 → %s 盾+%d 甲抗+%d" % [caster.get("name", "?"), tgt.get("name", "?"), sh, gain], "caster_idx": caster_idx}


## hunterStealth(hunter): 物理 atk×0.9 + 自 dodge buff + 自盾 atk×0.7
static func _hunter_stealth(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("dmgScale", 0.9), "physical", all_fighters)
	if hit["dodged"]:
		for de in hit["dodge_effects"]: effects.append(de)
	elif hit["dmg"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	Buffs.add(caster, "dodge", skill.get("dodgePct", 25), int(skill.get("dodgeTurns", 3)) + 1, "refresh")
	var sh: int = roundi(caster.get("atk", 0) * skill.get("shieldScale", 0.7))
	sh = Buffs.grant_shield(caster, sh)
	effects.append({"target_idx": caster_idx, "value": sh, "kind": "shield"})
	return {"type": "damage", "effects": effects, "log_text": "%s → 潜行突袭" % caster.get("name", "?"), "caster_idx": caster_idx}


## ghostPhantom(ghost): magic atk×1.5 + lifesteal% + 自 dodge buff
static func _ghost_phantom(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.5), "magic", all_fighters)
	if hit["dodged"]:
		for de in hit["dodge_effects"]: effects.append(de)
	elif hit["dmg"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "magic", "is_crit": hit["is_crit"]})
		var heal: int = _heal_to(caster, roundi(hit["dmg"] * skill.get("lifestealPct", 80) / 100.0))
		if heal > 0: effects.append({"target_idx": caster_idx, "value": heal, "kind": "heal"})
	Buffs.add(caster, "dodge", skill.get("dodgePct", 25), int(skill.get("dodgeTurns", 2)) + 1, "refresh")
	return {"type": "damage", "effects": effects, "log_text": "%s → 幻影 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## ghostStorm(ghost): 2段; 目标有curse→真伤, 否则魔法+施加curse
static func _ghost_storm(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var has_curse: bool = Buffs.has(target, "curse")
	var hits: int = skill.get("hits", 2)
	var dtype: String = "true" if has_curse else "magic"
	var total: int = 0
	var any_crit: bool = false
	var effects: Array = []   # 移到循环前: 无诅咒魔法段可闪避→闪避飘字要 append
	# 逐段飘字: PoC ghostStorm 段间 sleep(500) (skill-handlers.ts:1489)
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false): break
		var hit: Dictionary
		if has_curse:
			hit = _crit_hit_no_dodge(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.25), dtype)   # 诅咒段→真伤必中 (PoC applyRawDamage :1476)
		else:
			hit = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 1.25), dtype, all_fighters)   # 无诅咒→魔法可闪避 (1:1 PoC dealMagic :1485) — 原必中
			if hit.get("dodged", false):
				for de in hit["dodge_effects"]:
					effects.append(de)
				continue
		_seg_push(seg_list, hit["dmg"], dtype, hit["is_crit"], h * 0.5, target)
		total += hit["dmg"]
		if hit["is_crit"]: any_crit = true
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": dtype, "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	if not has_curse and target.get("alive", false):
		# _src=caster: 诅咒 DoT 致死归功施加者 (1:1 PoC skill-handlers.ts:1493; 旧版漏 _src → 击杀不归功)
		(target["buffs"] as Array).append({"type": "curse", "value": roundi(target.get("maxHp", 0) * 0.05), "duration": int(skill.get("dotTurns", 3)) + 1, "_src": caster})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 怨灵风暴 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## hunterShot(hunter): 残血(<execThresh)临时高暴; 3段物理 atk×0.55
static func _hunter_shot(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var is_exec: bool = target.get("maxHp", 0) > 0 and float(target.get("hp", 0)) / float(target.get("maxHp", 1)) * 100.0 < skill.get("execThresh", 50)
	var saved_crit: float = caster.get("crit", 0.0)
	var saved_ecd: float = caster.get("_extraCritDmg", 0.0)
	if is_exec:
		caster["crit"] = saved_crit + skill.get("execCrit", 40) / 100.0
		caster["_extraCritDmg"] = skill.get("execCritDmg", 20) / 100.0
	var effects: Array = []
	var total: int = 0
	var any_crit: bool = false
	var seg_list: Array = []
	# 逐箭错开 (PoC hunterShot 每箭 fireHunterArrow 240ms 飞行 → 段间~240ms; 之前聚合成1飘字漏了节奏)
	var stagger: float = float(skill.get("hitStaggerMs", 240)) / 1000.0
	for _h in range(skill.get("hits", 3)):
		if not target.get("alive", false): break
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 0.55), "physical", all_fighters, true)   # 射箭必中 (1:1 PoC applyRawDamage)
		if hit["dodged"]:
			for de in hit["dodge_effects"]: effects.append(de)
		else:
			total += hit["dmg"]
			if hit["dmg"] > 0:
				_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], seg_list.size() * stagger, target)
			if hit["is_crit"]: any_crit = true
	if is_exec:
		caster["crit"] = saved_crit
		caster["_extraCritDmg"] = saved_ecd
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit, "hits": maxi(1, seg_list.size())}
		if seg_list.size() >= 2:
			ed["segments"] = seg_list   # 逐箭飘字 + 逐段血条 (1:1 PoC per-arrow floatNum)
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 精准射击 → %s" % ["🎯 " if is_exec else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## soulReap(headless): 全敌物理 (atk×1.1 + 每敌已损血×10%)
static func _soul_reap(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var atk_base: int = roundi(caster.get("atk", 0) * skill.get("atkScale", 1.1))
	var any_crit: bool = false
	var effects: Array = []
	for e in enemies:
		if not e.get("alive", false): continue
		var base: float = atk_base + roundi((int(e.get("maxHp", 0)) - int(e.get("hp", 0))) * skill.get("lostHpPct", 10) / 100.0)
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, base, "physical")
		if hit["dmg"] > 0:
			effects.append({"target_idx": _find_idx(e, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
			if hit["is_crit"]: any_crit = true
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 灵魂收割 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## diceAllIn(dice): 全敌物理 atk×1.2 + 总伤 lifesteal%
static func _dice_all_in(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var base: int = roundi(caster.get("atk", 0) * skill.get("atkScale", 1.2))
	var total_all: int = 0
	var any_crit: bool = false
	var effects: Array = []
	for e in enemies:
		if not e.get("alive", false): continue
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, base, "physical")
		if hit["dmg"] > 0:
			effects.append({"target_idx": _find_idx(e, all_fighters), "value": hit["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
			total_all += hit["dmg"]
			if hit["is_crit"]: any_crit = true
	var heal: int = _heal_to(caster, roundi(total_all * skill.get("lifestealPct", 30) / 100.0))
	if heal > 0:
		effects.append({"target_idx": caster_idx, "value": heal, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 孤注一掷 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## crystalBurst(crystal): 全敌 3段 magic atk×0.233 + true atk×0.033 (结晶引爆走 on-hit 链)
static func _crystal_burst(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var per: Dictionary = {}
	var any_crit: bool = false
	# 逐波飘字: PoC crystalBurst 每波 sleep(500) (skill-handlers.ts:3137); 每敌每波 magic蓝 + true白 双段
	var per_seg: Dictionary = {}
	var wave: int = 0
	for _h in range(skill.get("hits", 3)):
		for e in enemies:
			if not e.get("alive", false): continue
			var ei: int = _find_idx(e, all_fighters)
			if not per_seg.has(ei): per_seg[ei] = []
			# PoC crystalBurst 魔法段走 dealMagic = 可逐敌逐波闪避 (skill-handlers.ts:3116); 真伤穿透段(下)走 applyRawDamage 必中
			var cdodge: Dictionary = _roll_dodge(e, caster, all_fighters)
			if not cdodge["dodged"]:
				var mh: Dictionary = _crit_hit_no_dodge(caster, e, caster.get("atk", 0) * skill.get("atkScale", 0.233), "magic")
				if mh["dmg"] > 0:
					per[ei] = int(per.get(ei, 0)) + int(mh["dmg"])
					_seg_push(per_seg[ei], mh["dmg"], "magic", mh["is_crit"], wave * 0.5, e)
					if mh["is_crit"]: any_crit = true
			if e.get("alive", false):
				var tr: Dictionary = Damage.apply_raw_damage(e, roundi(caster.get("atk", 0) * skill.get("pierceScale", 0.033)), "true")
				var t_shown: int = tr["hpLoss"] + tr["shieldAbs"]
				per[ei] = int(per.get(ei, 0)) + t_shown
				_seg_push(per_seg[ei], t_shown, "true", false, wave * 0.5, e)
		wave += 1
	var effects: Array = []
	for ei2 in per:
		if int(per[ei2]) > 0:
			var ed: Dictionary = {"target_idx": ei2, "value": int(per[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": any_crit}
			if per_seg.has(ei2) and (per_seg[ei2] as Array).size() >= 2: ed["segments"] = per_seg[ei2]
			# hits = 魔法波数 → 结晶印记按波叠 (1:1 PoC 每 dealMagic 叠1层, 真伤段不叠); 原漏设 hits → on-hit 只叠1次=引爆慢3倍
			var mag_hits: int = 0
			for sg in per_seg.get(ei2, []):
				if str((sg as Dictionary).get("dmg_type", "")) == "magic":
					mag_hits += 1
			ed["hits"] = maxi(1, mag_hits)
			effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 水晶爆发 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


# ─── 招财龟经济 (fortune, _goldCoins) ───

## fortuneStrike: 2 段物理 atk×(0.5 + 0.03×coins) (不消耗币)
static func _fortune_strike(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var coins: int = int(caster.get("_goldCoins", 0))
	var scale: float = skill.get("atkScale", 0.5) + skill.get("perCoinAtkScale", 0.03) * coins
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC fortuneStrike 段间 sleep(300) (skill-handlers.ts:3793)
	var seg_list: Array = []
	for h in range(skill.get("hits", 2)):
		if not target.get("alive", false): break
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * scale, "physical", all_fighters)
		if not hit["dodged"]:
			_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], h * 0.3, target)
			total += hit["dmg"]
			if hit["is_crit"]: any_crit = true
	var effects: Array = []
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 财运一击 (%d币)" % ["💥 " if any_crit else "", caster.get("name", "?"), coins], "caster_idx": caster_idx}


## fortuneDice: +3~8 币 + 自疗 healPct% (+若已梭哈 postAllInShieldPct% 盾)
static func _fortune_dice(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var roll: int = 3 + randi() % 6
	caster["_goldCoins"] = int(caster.get("_goldCoins", 0)) + roll
	var effects: Array = []
	var heal: int = _heal_to(caster, roundi(caster.get("maxHp", 0) * skill.get("healPct", 8) / 100.0))
	if heal > 0:
		effects.append({"target_idx": caster_idx, "value": heal, "kind": "heal"})
	# 已用梭哈 (有 fortuneAllIn 在 CD) → 额外盾
	var all_in_used: bool = false
	for s in caster.get("skills", []):
		if s.get("type", "") == "fortuneAllIn" and int(s.get("cdLeft", 0)) > 0:
			all_in_used = true
	if all_in_used and skill.get("postAllInShieldPct", 0) > 0:
		var sh: int = roundi(caster.get("maxHp", 0) * skill.get("postAllInShieldPct", 10) / 100.0)
		sh = Buffs.grant_shield(caster, sh)
		effects.append({"target_idx": caster_idx, "value": sh, "kind": "shield"})
	effects.append({"target_idx": caster_idx, "kind": "passive", "label": "🎲 +%d💰" % roll})
	return {"type": "heal", "effects": effects, "log_text": "%s → 幸运骰子 +%d币" % [caster.get("name", "?"), roll], "caster_idx": caster_idx}


## fortuneAllIn: 消耗全部币, 每币 (atk×0.18物理 + atk×0.18真伤)
static func _fortune_all_in(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var coins: int = int(caster.get("_goldCoins", 0))
	if coins <= 0 or target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	caster["_goldCoins"] = 0
	var normal: int = 0
	var pierce: int = 0
	# 逐枚飘字: PoC fortuneAllIn perDelay = max(80, round(400/sqrt(coins)))ms (skill-handlers.ts:5640,5664)
	#   每枚同帧 物理红 + 真伤白 两段 (5661-5662)
	var per_delay: float = maxf(80.0, roundf(400.0 / sqrt(float(coins)))) / 1000.0
	var seg_phys: Array = []
	var seg_true: Array = []
	var coin_i: int = 0
	for _c in range(coins):
		if not target.get("alive", false): break
		var nh: int = _crit_hit_no_dodge(caster, target, caster.get("atk", 0) * skill.get("perCoinAtkNormal", 0.18), "physical", false)["dmg"]
		_seg_push(seg_phys, nh, "physical", false, coin_i * per_delay, target)
		normal += nh
		if target.get("alive", false):
			var tr: Dictionary = Damage.apply_raw_damage(target, roundi(caster.get("atk", 0) * skill.get("perCoinAtkPierce", 0.18)), "true")
			var t_shown: int = tr["hpLoss"] + tr["shieldAbs"]
			_seg_push(seg_true, t_shown, "true", false, coin_i * per_delay, target)
			pierce += t_shown
		coin_i += 1
	var effects: Array = []
	var t_idx := _find_idx(target, all_fighters)
	if normal > 0:
		var en: Dictionary = {"target_idx": t_idx, "value": normal, "kind": "damage", "dmg_type": "physical", "is_crit": false}
		if seg_phys.size() >= 2: en["segments"] = seg_phys
		effects.append(en)
	if pierce > 0:
		var et: Dictionary = {"target_idx": t_idx, "value": pierce, "kind": "damage", "dmg_type": "true", "is_crit": false}
		if seg_true.size() >= 2: et["segments"] = seg_true
		effects.append(et)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 孤注一掷! 梭哈 %d币" % [caster.get("name", "?"), coins], "caster_idx": caster_idx}


## fortuneGainCoins: +coinGain 币 (selfCast)
static func _fortune_gain_coins(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var g: int = skill.get("coinGain", 10)
	caster["_goldCoins"] = int(caster.get("_goldCoins", 0)) + g
	return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "💰 +%d" % g}], "log_text": "%s → 招财 +%d币" % [caster.get("name", "?"), g], "caster_idx": caster_idx}


## fortuneBuyEquip: 花 coinCost 币随机抽 1 件装备 (selfCast)
static func _fortune_buy_equip(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	# 当前价 = _fortuneBuyCost(每次购买 +25% 累积) 否则基础 coinCost (PoC fortuneBuyEquip:5614)
	var cost: int = int(caster.get("_fortuneBuyCost", skill.get("coinCost", 20)))
	if int(caster.get("_goldCoins", 0)) < cost:
		return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "💰 不足"}], "log_text": "%s → 买装备(币不足)" % caster.get("name", "?"), "caster_idx": caster_idx}
	caster["_goldCoins"] = int(caster.get("_goldCoins", 0)) - cost
	caster["_fortuneBuyCost"] = roundi(cost * 1.25)   # 每次购买后价格 +25%
	var pool: Array = []
	for e in DataRegistry.all_equipment:
		var cat: String = e.get("category", "")
		if cat == "normal" or cat == "unique":
			pool.append(e)
	var bought_eq := ""
	if not pool.is_empty():
		bought_eq = str(pool[randi() % pool.size()].get("id", ""))
	# C1 修: 不再 on_attach 给 caster(=即时强化 bug); 抽中装备进【装备席】由 BattleScene 接
	#   (1:1 PoC fortuneBuyEquip→emit'fortune-buy-equip'→addToBench, 引擎层不碰 GameState/bench)
	var res: Dictionary = {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "🛒 买装备"}], "log_text": "%s → 花 %d币 买装备(进装备席)" % [caster.get("name", "?"), cost], "caster_idx": caster_idx}
	if bought_eq != "":
		res["fortune_buy_eq"] = bought_eq
	return res


## gamblerBet(gambler): 自损40%血换 7段物理 (每段 hpCost/7); +_multiBonus 助连击
static func _gambler_bet(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	if caster.get("maxHp", 0) <= 0 or float(caster.get("hp", 0)) / float(caster.get("maxHp", 1)) <= 0.4:
		return _empty_result(caster_idx)   # 血量不足
	var hp_cost: int = roundi(caster.get("hp", 0) * skill.get("hpCostPct", 40) / 100.0)
	caster["hp"] = maxi(1, int(caster.get("hp", 0)) - hp_cost)
	caster["_multiBonus"] = int(caster.get("_multiBonus", 0)) + skill.get("multiBonus", 20)   # turn-begin 重置
	var hits: int = skill.get("hits", 7)
	var per: float = roundi(hp_cost / float(hits))
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC gamblerBet 先 sleep(400) (skill-handlers.ts:4736), 每段 pulse + sleep(160) 后落伤 + sleep(300)
	#   (4745,4760). 段 h 落点 = 0.4 + 0.16 + h*(0.16+0.3) = 0.56 + h*0.46.
	#   (自损橙字 -hpCost 是 caster 端独立飘字, 非命中段, 不入 seg_list)
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false): break
		var hit: Dictionary = _crit_hit_no_dodge(caster, target, per, "physical")
		_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], 0.56 + h * 0.46, target)
		total += hit["dmg"]
		if hit["is_crit"]: any_crit = true
	var effects: Array = []
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 豪赌! 自损 %d血" % ["💥 " if any_crit else "", caster.get("name", "?"), hp_cost], "caster_idx": caster_idx}


## chestCount(chest): 财宝越多治疗/盾越高. bonus=1+floor(treasure/100)×0.14
static func _chest_count(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var treasure: int = int(caster.get("_chestTreasure", 0))
	var bonus: float = 1.0 + floori(treasure / 100.0) * 0.14
	var effects: Array = []
	var heal: int = _heal_to(caster, roundi(caster.get("maxHp", 0) * skill.get("healHpPct", 5) / 100.0 * bonus))
	if heal > 0:
		effects.append({"target_idx": caster_idx, "value": heal, "kind": "heal"})
	var sh: int = roundi(caster.get("atk", 0) * skill.get("shieldAtkScale", 0.6) * bonus)
	if sh > 0:
		sh = Buffs.grant_shield(caster, sh)
		effects.append({"target_idx": caster_idx, "value": sh, "kind": "shield"})
	return {"type": "heal", "effects": effects, "log_text": "%s → 清点财宝 (%d宝, ×%.2f)" % [caster.get("name", "?"), treasure, bonus], "caster_idx": caster_idx}


## chestSmash(chest): 单体 hits 段 + 6 装备变种 (1:1 PoC chest.js / skill-handlers.ts:3820-3923)
##   star→真伤替代物理; rock→totalBasePower += def+mr; thunder→每段叠 _goldLightning, 满5引爆 1×ATK 真伤;
##   chain→每段对随机其他敌 25% 溅射(同 dmgType + 同样 thunder 叠); fire→结束给全命中加 burn; poison→给全命中加 healReduce 50% 4t
static func _chest_smash(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 4)
	var atk_scale: float = skill.get("atkScale", 0.7)
	var has_star: bool = caster.get("_chestEquipStar", false)
	var has_rock: bool = caster.get("_chestEquipRock", false)
	var has_thunder: bool = caster.get("_chestEquipThunder", false)
	var has_chain: bool = caster.get("_chestEquipChain", false)
	var has_fire: bool = caster.get("_chestEquipFire", false)
	var has_poison: bool = caster.get("_chestEquipPoison", false)
	var dmg_type: String = "true" if has_star else "physical"
	var total_base_power: float = roundi(caster.get("atk", 0) * atk_scale)
	if has_rock:
		total_base_power += caster.get("def", 0) + caster.get("mr", caster.get("def", 0))
	var per_hit_base: int = roundi(total_base_power / hits)
	var effects: Array = []
	var hit_targets: Array = [target]
	var crit_chance: float = caster.get("crit", 0.0)
	var t_idx := _find_idx(target, all_fighters)

	for i in range(hits):
		if not target.get("alive", false):
			break
		var is_crit: bool = Damage.roll_crit(crit_chance)
		var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
		var dmg: int = maxi(1, Damage.calc_damage(caster, target, per_hit_base * crit_mult, dmg_type))   # 1:1 PoC max(1,…) (skill-handlers.ts:3871)
		var r: Dictionary = Damage.apply_raw_damage(target, dmg, dmg_type)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			effects.append({"target_idx": t_idx, "value": shown, "kind": "damage", "dmg_type": dmg_type, "is_crit": is_crit})
		_chest_apply_thunder(caster, target, all_fighters, has_thunder, effects)
		# chain: 25% 溅射另一随机敌 (同 dmgType + 同样 thunder 叠)
		if has_chain:
			var others: Array = []
			for e in _alive_enemies(caster, all_fighters):
				if e != target:
					others.append(e)
			if not others.is_empty():
				var sec: Dictionary = others[randi() % others.size()]
				var chain_dmg: int = maxi(1, roundi(dmg * 0.25))   # 1:1 PoC raw 0.25×已减伤dmg (skill-handlers.ts:3888) — 原再过一遍护甲=双重减免
				var rc: Dictionary = Damage.apply_raw_damage(sec, chain_dmg, dmg_type)
				var s_shown: int = rc["hpLoss"] + rc["shieldAbs"]
				var sec_idx := _find_idx(sec, all_fighters)
				if s_shown > 0:
					effects.append({"target_idx": sec_idx, "value": s_shown, "kind": "damage", "dmg_type": dmg_type, "is_crit": false})
				_chest_apply_thunder(caster, sec, all_fighters, has_thunder, effects)
				if not hit_targets.has(sec):
					hit_targets.append(sec)

	# fire: 全命中目标 burn
	if has_fire:
		for t in hit_targets:
			if t.get("alive", false):
				Dot.apply_stacks(t, "burn", _default_burn_stacks(caster))
	# poison: 全命中目标 healReduce 50% 4t
	if has_poison:
		for t in hit_targets:
			if t.get("alive", false):
				Buffs.add(t, "healReduce", 50, 4, "refresh")

	if effects.is_empty():
		return _empty_result(caster_idx)
	var total_all: int = 0
	for e in effects:
		total_all += e.get("value", 0)
	return {"type": "damage", "effects": effects, "log_text": "%s → %s → %s  -%d" % [caster.get("name", "?"), skill.get("name", "?"), target.get("name", "?"), total_all], "caster_idx": caster_idx}


## chestStorm(chest): 全敌 hits 段物理 + pierceScale 真伤 + star/thunder/fire/poison 变种 (1:1 PoC chest.js:125-220)
static func _chest_storm(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 6)
	var atk_scale: float = skill.get("atkScale", 0.3)
	var pierce_scale: float = skill.get("pierceScale", 0)
	var has_star: bool = caster.get("_chestEquipStar", false)
	var has_thunder: bool = caster.get("_chestEquipThunder", false)
	var has_fire: bool = caster.get("_chestEquipFire", false)
	var has_poison: bool = caster.get("_chestEquipPoison", false)
	var phys_type: String = "true" if has_star else "physical"
	var crit_chance: float = caster.get("crit", 0.0)
	var effects: Array = []

	for i in range(hits):
		for enemy in enemies:
			if not enemy.get("alive", false):
				continue
			var e_idx := _find_idx(enemy, all_fighters)
			var is_crit: bool = Damage.roll_crit(crit_chance)
			var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
			var phys_base: float = roundi(caster.get("atk", 0) * atk_scale)
			var phys_dmg: int = maxi(1, Damage.calc_damage(caster, enemy, phys_base * crit_mult, phys_type))   # 1:1 PoC max(1,…) (skill-handlers.ts:4893)
			var rp: Dictionary = Damage.apply_raw_damage(enemy, phys_dmg, phys_type)
			var phys_shown: int = rp["hpLoss"] + rp["shieldAbs"]
			if phys_shown > 0:
				effects.append({"target_idx": e_idx, "value": phys_shown, "kind": "damage", "dmg_type": phys_type, "is_crit": is_crit})
			# pierceScale 真伤段 (不减甲)
			if pierce_scale > 0 and enemy.get("alive", false):
				var true_dmg: int = roundi(caster.get("atk", 0) * pierce_scale * crit_mult)
				var rt: Dictionary = Damage.apply_raw_damage(enemy, true_dmg, "true")
				var true_shown: int = rt["hpLoss"] + rt["shieldAbs"]
				if true_shown > 0:
					effects.append({"target_idx": e_idx, "value": true_shown, "kind": "damage", "dmg_type": "true", "is_crit": false})
			_chest_apply_thunder(caster, enemy, all_fighters, has_thunder, effects)

	# fire / poison: 全敌
	if has_fire:
		for t in enemies:
			if t.get("alive", false):
				Dot.apply_stacks(t, "burn", _default_burn_stacks(caster))
	if has_poison:
		for t in enemies:
			if t.get("alive", false):
				Buffs.add(t, "healReduce", 50, 4, "refresh")

	if effects.is_empty():
		return _empty_result(caster_idx)
	var total_all: int = 0
	for e in effects:
		total_all += e.get("value", 0)
	return {"type": "damage", "effects": effects, "log_text": "%s → %s → 全体 %d 敌  -%d" % [caster.get("name", "?"), skill.get("name", "?"), enemies.size(), total_all], "caster_idx": caster_idx}


## thunder 装备: 每段命中叠 _goldLightning, 满 5 引爆 1×ATK 真伤 (1:1 PoC chest.js:60 / skill-handlers.ts:3844-3864)
##   引爆的 damage effect 带 "lightning": true 标志 → BattleScene 可据此在该目标脚下播天降闪电 VFX (_play_lightning_strike).
static func _chest_apply_thunder(caster: Dictionary, enemy: Dictionary, all_fighters: Array, has_thunder: bool, effects: Array) -> void:
	if not has_thunder or not enemy.get("alive", false):
		return
	enemy["_goldLightning"] = int(enemy.get("_goldLightning", 0)) + 1
	if int(enemy["_goldLightning"]) >= 5:
		enemy["_goldLightning"] = 0
		var thunder_dmg: int = roundi(caster.get("atk", 0) * 1.0)
		var r: Dictionary = Damage.apply_raw_damage(enemy, thunder_dmg, "true")
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		var e_idx := _find_idx(enemy, all_fighters)
		if shown > 0:
			effects.append({"target_idx": e_idx, "value": shown, "kind": "damage", "dmg_type": "true", "is_crit": false, "lightning": true})


# ─── 泡泡/墨迹/凤凰盾/龟壳 ───

## bubbleShield(bubble): 特殊泡泡盾 round(atk×1.8) (经 apply_raw_damage 吸收, 到期爆裂)
static func _bubble_shield(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var tgt: Dictionary = caster
	if target != null and not target.is_empty() and target.get("side", "") == caster.get("side", "") and target.get("alive", false):
		tgt = target
	var amt: int = roundi(roundi(caster.get("atk", 0) * skill.get("atkScale", 1.8)) * Rules.shield_mult())
	tgt["bubbleShieldVal"] = int(tgt.get("bubbleShieldVal", 0)) + amt
	tgt["_bubbleShieldTurns"] = skill.get("duration", 3)
	tgt["_bubbleBurstScale"] = skill.get("burstScale", 2)
	return {"type": "shield", "effects": [{"target_idx": _find_idx(tgt, all_fighters), "kind": "passive", "label": "+%d🫧 泡泡盾" % amt}], "log_text": "%s → 泡泡护盾 +%d" % [caster.get("name", "?"), amt], "caster_idx": caster_idx}


## bubbleBind(bubble): 给敌挂泡泡束缚 (每受击 -perHitLoss 甲抗, 消费在 on-hit 链)
static func _bubble_bind(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	Buffs.remove_all(target, "bubbleBind")
	var per: int = 2 if int(caster.get("_level", 1)) >= 6 else 1
	(target["buffs"] as Array).append({"type": "bubbleBind", "value": per, "duration": int(skill.get("duration", 8)) + 1, "perHitLoss": per, "lossCap": skill.get("lossCap", 30), "lossUsed": 0})
	return {"type": "shield", "effects": [{"target_idx": _find_idx(target, all_fighters), "kind": "passive", "label": "🫧 束缚 -%d甲抗/击" % per}], "log_text": "%s → 泡泡束缚 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## phoenixShield(phoenix): 自身熔岩盾 round(atk×0.75), 持盾受击反击(on-hit链)
static func _phoenix_shield(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var amt: int = roundi(caster.get("atk", 0) * skill.get("shieldScale", 0.75))
	caster["_lavaShieldVal"] = int(caster.get("_lavaShieldVal", 0)) + Buffs.fatigue_amt(caster, amt)
	caster["_lavaShieldTurns"] = skill.get("duration", 4)
	caster["_lavaShieldCounter"] = skill.get("counterScale", 0.14)
	return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "+%d🔥 熔岩盾" % amt}], "log_text": "%s → 熔岩护盾 +%d" % [caster.get("name", "?"), amt], "caster_idx": caster_idx}


## 墨迹叠层 (cap _inkCapOverride??5, 同步 _inkLink.partner)
static func _add_ink_stack(target: Dictionary, count: int, caster: Dictionary = {}) -> void:
	var cap: int = int(caster.get("_inkCapOverride", target.get("_inkCapOverride", 5)))
	target["_inkStacks"] = mini(cap, int(target.get("_inkStacks", 0)) + count)
	# 速写(lineRapid)后 caster._inkTrueDmg → 墨迹增伤转真伤; 每次叠层写到目标(含墨链伙伴) (1:1 PoC addInkStack:461)
	var rapid: bool = bool(caster.get("_inkTrueDmg", false))
	target["_inkRapidActive"] = rapid
	var link = target.get("_inkLink", null)
	if link is Dictionary and link.get("partner", null) is Dictionary:
		var p: Dictionary = link["partner"]
		p["_inkStacks"] = mini(cap, int(p.get("_inkStacks", 0)) + count)
		p["_inkRapidActive"] = rapid


## lineLink(line): 主+次目标各 atk×0.8 物理 + 叠墨迹 + 建墨链
static func _line_link(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var h1: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("atkScale", 0.8), "physical", all_fighters)
	if not h1["dodged"] and h1["dmg"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": h1["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": h1["is_crit"]})
	_add_ink_stack(target, 1, caster)
	# 第二目标 (任意存活非主)
	var second = null
	for e in _alive_enemies(caster, all_fighters):
		if e != target:
			second = e; break
	if second != null:
		var h2: Dictionary = _one_hit(caster, second, caster.get("atk", 0) * skill.get("atkScale", 0.8), "physical", all_fighters)
		if not h2["dodged"] and h2["dmg"] > 0:
			effects.append({"target_idx": _find_idx(second, all_fighters), "value": h2["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": h2["is_crit"]})
		_add_ink_stack(second, 1, caster)
		var dtype: String = "true" if caster.get("_inkTrueDmg", false) else "magic"
		var link := {"partner": second, "turns": skill.get("duration", 3), "transferPct": skill.get("transferPct", 30), "dmgType": dtype, "owner": caster}
		target["_inkLink"] = link
		second["_inkLink"] = {"partner": target, "turns": skill.get("duration", 3), "transferPct": skill.get("transferPct", 30), "dmgType": dtype, "owner": caster}
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 连结 → 墨链" % caster.get("name", "?"), "caster_idx": caster_idx}


## lineFinish(line): 物理 atk×0.7 + 引爆墨迹 round(atk×0.45×stacks); 清层
static func _line_finish(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var stacks: int = int(target.get("_inkStacks", 0))
	var effects: Array = []
	var t_idx2 := _find_idx(target, all_fighters)
	# 颜色修复: PoC lineFinish 物理段红 + 引爆段(magic蓝/true白) 两独立飘字 (skill-handlers.ts:3465,3473);
	#   Godot 旧版求和成单 magic effect → 物理段错显蓝. 拆成两段, 各自 dmg_type 正确.
	var h1: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * skill.get("baseScale", 0.7), "physical", all_fighters)
	var total: int = 0
	var any_crit: bool = false
	var phys_shown: int = 0
	if not h1["dodged"]:
		phys_shown = h1["dmg"]
		total += phys_shown; any_crit = h1["is_crit"]
	# 引爆
	var burst_shown: int = 0
	var burst_type: String = "true" if caster.get("_inkTrueDmg", false) else "magic"
	if stacks > 0 and target.get("alive", false):
		var bd: int = roundi(caster.get("atk", 0) * skill.get("perStackScale", 0.45) * stacks)
		if burst_type == "magic":
			bd = Damage.calc_damage(caster, target, bd, "magic")
		var br: Dictionary = Damage.apply_raw_damage(target, bd, burst_type)
		burst_shown = br["hpLoss"] + br["shieldAbs"]
		total += burst_shown
	target["_inkStacks"] = 0
	if phys_shown > 0:
		effects.append({"target_idx": t_idx2, "value": phys_shown, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit})
	if burst_shown > 0:
		effects.append({"target_idx": t_idx2, "value": burst_shown, "kind": "damage", "dmg_type": burst_type, "is_crit": any_crit})
	if not target.get("alive", false):
		for s in caster.get("skills", []):
			if s.get("type", "") == "lineFinish":
				s["cdLeft"] = 0
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 终结 → 引爆 %d 墨" % [caster.get("name", "?"), stacks], "caster_idx": caster_idx}


## shellAbsorb(shell): 偷取 target maxHp×10% → 自己 (永久转移)
static func _shell_absorb(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var steal: int = roundi(target.get("maxHp", 0) * skill.get("stealHpPct", 10) / 100.0)
	target["maxHp"] = maxi(1, int(target.get("maxHp", 0)) - steal)
	target["hp"] = mini(int(target.get("maxHp", 0)), maxi(1, int(target.get("hp", 0)) - steal))
	caster["maxHp"] = int(caster.get("maxHp", 0)) + steal
	caster["hp"] = int(caster.get("hp", 0)) + steal
	if caster.has("_initHp"):
		caster["_initHp"] = caster["maxHp"]
	return {"type": "heal", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "🐚 吸取 %dHP" % steal}, {"target_idx": _find_idx(target, all_fighters), "kind": "passive", "label": "-%dHP" % steal}], "log_text": "%s → 吸取 → %s 的 %d 最大生命" % [caster.get("name", "?"), target.get("name", "?"), steal], "caster_idx": caster_idx}


# ─── 剩余 12 技能 (agent 提取规格, 1:1 PoC) ───

## basicBarrage 打击: hits(10) 段, 每发随机一个存活敌, 物理 atk×(总3.1/10).
##   1:1 PoC basic.js: 每发独立飘字+血条逐段降(逐颗segments, delay=发序×280ms+130ms damageAt) +
##   barrage_shots(每发目标序列)给 bolt 动画, 弹与飘字同步. (不再把10段聚合成1飘字.)
static func _basic_barrage(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var hits: int = skill.get("hits", 10)
	var per: float = caster.get("atk", 0) * skill.get("atkScale", 3.1) / float(hits)
	var seg_delay: float = float(skill.get("hitStaggerMs", 280)) / 1000.0
	var shots: Array = []                 # 每发目标 idx (与飘字同序, 给 bolt)
	var per_enemy_segs: Dictionary = {}   # ei → [segments]
	var per_enemy_total: Dictionary = {}  # ei → 总伤
	var any_crit: bool = false
	for h in range(hits):
		var enemies: Array = _alive_enemies(caster, all_fighters)
		if enemies.is_empty(): break
		var e: Dictionary = enemies[randi() % enemies.size()]
		var ei: int = _find_idx(e, all_fighters)
		shots.append(ei)
		var hit: Dictionary = _one_hit(caster, e, per, "physical", all_fighters)
		if hit["dodged"] or int(hit["dmg"]) <= 0:
			continue
		if not per_enemy_segs.has(ei):
			per_enemy_segs[ei] = []
			per_enemy_total[ei] = 0
		per_enemy_total[ei] = int(per_enemy_total[ei]) + int(hit["dmg"])
		(per_enemy_segs[ei] as Array).append({
			"value": int(hit["dmg"]), "dmg_type": "physical", "is_crit": bool(hit["is_crit"]),
			"delay": h * seg_delay + 0.13,   # 全局发序延迟 + damageAt(130ms), 与 bolt 落点同步
			"hp_after": float(e.get("hp", 0)), "shield_after": float(e.get("shield", 0)),
		})
		if hit["is_crit"]: any_crit = true
	var effects: Array = []
	for ei2 in per_enemy_segs:
		effects.append({
			"target_idx": ei2, "value": int(per_enemy_total[ei2]), "kind": "damage",
			"dmg_type": "physical", "is_crit": any_crit, "segments": per_enemy_segs[ei2],
		})
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "barrage_shots": shots, "log_text": "%s%s → 弹幕 %d 连" % ["💥 " if any_crit else "", caster.get("name", "?"), hits], "caster_idx": caster_idx}


## basicChiWave: chiWave buff(暴击/暴伤/吸血/穿甲)+立即recalc + 横排3段 atk×2.3/3
static func _basic_chi_wave(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	Buffs.add(caster, "chiWaveActive", 0, 1, "ignore", {"critGain": skill.get("critGain", 25), "critDmgGain": skill.get("critDmgGain", 20), "lifestealGain": skill.get("lifestealGain", 10), "armorPenDelta": roundi(caster.get("atk", 0) * skill.get("armorPenGain", 0.1))})
	StatsRecalc.recalc(caster)
	var targets: Array = SlotHelpers.same_column_fighters(all_fighters, target)
	if targets.is_empty(): targets = [target]
	var hits: int = skill.get("hits", 3)
	var per: float = caster.get("atk", 0) * skill.get("atkScale", 2.3) / float(hits)
	# 1:1 PoC basic.js: 3连弹空, 每发逐段飘字(0/220/440ms). 改聚合→逐发segments(delay=发序×220ms).
	var seg_delay: float = float(skill.get("hitStaggerMs", 220)) / 1000.0
	var per_enemy_segs: Dictionary = {}
	var per_enemy_total: Dictionary = {}
	var any_crit: bool = false
	for h in range(hits):
		for t in targets:
			if not t.get("alive", false): continue
			var ei: int = _find_idx(t, all_fighters)
			var hit: Dictionary = _one_hit(caster, t, per, "physical", all_fighters)
			if not hit["dodged"] and int(hit["dmg"]) > 0:
				if not per_enemy_segs.has(ei):
					per_enemy_segs[ei] = []
					per_enemy_total[ei] = 0
				per_enemy_total[ei] = int(per_enemy_total[ei]) + int(hit["dmg"])
				(per_enemy_segs[ei] as Array).append({
					"value": int(hit["dmg"]), "dmg_type": "physical", "is_crit": bool(hit["is_crit"]),
					"delay": h * seg_delay, "y_off": h * 18.0,   # 1:1 PoC floatNum yOff i×18 (3发竖向错开)
					"micro_shake": true,   # 每发微震 (1:1 PoC shake(90,0.0025))
					"hp_after": float(t.get("hp", 0)), "shield_after": float(t.get("shield", 0)),
				})
				if hit["is_crit"]: any_crit = true
	var effects: Array = []
	# 强化加成飘字 (1:1 PoC:906-907 floatNum +暴/+爆 + +生命偷取/+穿甲; 原漏 = chiWaveActive buff 静默生效)
	var cg: int = int(skill.get("critGain", 25))
	var cdg: int = int(skill.get("critDmgGain", 20))
	var lg: int = int(skill.get("lifestealGain", 10))
	var apd: int = roundi(caster.get("atk", 0) * skill.get("armorPenGain", 0.1))
	effects.append({"target_idx": caster_idx, "kind": "passive", "label": "+%d%%暴 +%d%%爆" % [cg, cdg]})
	effects.append({"target_idx": caster_idx, "kind": "passive", "label": "+%d%%生命偷取 +%d穿甲" % [lg, apd]})
	for ei2 in per_enemy_segs:
		effects.append({"target_idx": ei2, "value": int(per_enemy_total[ei2]), "kind": "damage", "dmg_type": "physical", "is_crit": any_crit, "segments": per_enemy_segs[ei2]})
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 气波 (强化)" % ["💥 " if any_crit else "", caster.get("name", "?")], "caster_idx": caster_idx}


## basicSlam: 主(atk×0.7 + tMaxHp×26%) + 溅射其余(atk×0.2 + 主tMaxHp×19%, 无暴击)
static func _basic_slam(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var t_max: int = target.get("maxHp", 0)
	var effects: Array = []
	var main_base: float = caster.get("atk", 0) * skill.get("atkScale", 0.7) + roundi(t_max * skill.get("targetHpPct", 26) / 100.0)
	var mh: Dictionary = _one_hit(caster, target, main_base, "physical", all_fighters)
	if not mh["dodged"] and mh["dmg"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": mh["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": mh["is_crit"]})
	var sp_base: float = caster.get("atk", 0) * skill.get("splashAtkScale", 0.2) + roundi(t_max * skill.get("splashHpPct", 19) / 100.0)
	for e in _alive_enemies(caster, all_fighters):
		if e == target: continue
		# PoC basicSlam 溅射走 dealPhysical(isCrit=false) = 可闪避但不暴击 (skill-handlers.ts:1176) — 原 _crit_hit_no_dodge 不判闪避
		var sdodge: Dictionary = _roll_dodge(e, caster, all_fighters)
		if sdodge["dodged"]:
			for de in sdodge["effects"]: effects.append(de)
			continue
		var sh: Dictionary = _crit_hit_no_dodge(caster, e, sp_base, "physical", false)
		if sh["dmg"] > 0:
			effects.append({"target_idx": _find_idx(e, all_fighters), "value": sh["dmg"], "kind": "damage", "dmg_type": "physical", "is_crit": false})
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 大地猛击" % caster.get("name", "?"), "caster_idx": caster_idx}


## stoneTaunt: 嘲讽(taunt 3回合) + 自盾 atk×1×shieldMult
static func _stone_taunt(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	Buffs.add(caster, "taunt", 1, skill.get("redirectTurns", 3), "refresh")
	var sh: int = roundi(roundi(caster.get("atk", 0) * skill.get("selfShieldAtkScale", 1)) * Rules.shield_mult())
	sh = Buffs.grant_shield(caster, sh)
	return {"type": "shield", "effects": [{"target_idx": caster_idx, "value": sh, "kind": "shield"}], "log_text": "%s → 嘲讽! 自盾 +%d" % [caster.get("name", "?"), sh], "caster_idx": caster_idx}


## angelSmite: 选【_dmgDealt 最高的敌】(集火本场输出最猛者, 非最低血) 3波 atk×1.5物理 + chilled + healReduce + 永久偷甲抗
static func _angel_smite(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	# auto-target: 选 _dmgDealt 最高的敌人 (PoC angelSmite:1276; 忽略传入 target) — 集火输出最猛的
	var en: Array = _alive_enemies(caster, all_fighters)
	if en.is_empty(): return _empty_result(caster_idx)
	var max_d: int = -1
	for e in en:
		max_d = maxi(max_d, int(e.get("_dmgDealt", 0)))
	var tied: Array = en.filter(func(e): return int(e.get("_dmgDealt", 0)) == max_d)
	var tgt: Dictionary = tied[randi() % tied.size()]
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC angelSmite waveCount 段 段间 sleep(160) (skill-handlers.ts). 否则 N 段聚成 1 跳字 + 血条没空就倒.
	var seg_list: Array = []
	var wi: int = 0
	for _w in range(skill.get("waveCount", 3)):
		if not tgt.get("alive", false): break
		var hit: Dictionary = _crit_hit_no_dodge(caster, tgt, caster.get("atk", 0) * skill.get("atkScale", 1.5), "physical")
		total += hit["dmg"]
		if hit["is_crit"]: any_crit = true
		_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], wi * 0.16, tgt)
		wi += 1
	var effects: Array = []
	if total > 0:
		var ed_a: Dictionary = {"target_idx": _find_idx(tgt, all_fighters), "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
		if seg_list.size() >= 2: ed_a["segments"] = seg_list
		ed_a["hits"] = maxi(1, seg_list.size())
		effects.append(ed_a)
	if tgt.get("alive", false):
		Buffs.add(tgt, "chilled", 20, int(skill.get("chillTurns", 3)) + 1, "refresh")
		Buffs.add(tgt, "healReduce", skill.get("healReducePct", 50), int(skill.get("healReduceTurns", 3)) + 1, "refresh")
	# 永久偷甲抗
	var lvl: int = maxi(1, int(caster.get("_level", 1)))
	var steal: int = roundi(skill.get("baseStealDR", 3) + (lvl - 1) * skill.get("perLevelStealDR", 0.2))
	tgt["baseDef"] = maxi(0, tgt.get("baseDef", 0) - steal); tgt["def"] = maxi(0, tgt.get("def", 0) - steal)
	tgt["baseMr"] = maxi(0, int(tgt.get("baseMr", tgt.get("baseDef", 0))) - steal); tgt["mr"] = maxi(0, tgt.get("mr", 0) - steal)
	caster["baseDef"] = caster.get("baseDef", 0) + steal; caster["def"] = caster.get("def", 0) + steal
	caster["baseMr"] = int(caster.get("baseMr", caster.get("baseDef", 0))) + steal; caster["mr"] = caster.get("mr", 0) + steal
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 圣裁 → %s" % ["💥 " if any_crit else "", caster.get("name", "?"), tgt.get("name", "?")], "caster_idx": caster_idx}


## headlessStorm (亡灵风暴): 全敌 hits 段 round(atk×atkScale) 固定物理(无暴击无减甲) + 临时吸血. PoC headless.js:47
static func _headless_storm(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var hits: int = int(skill.get("hits", 3))
	var atk_scale: float = skill.get("atkScale", 0.5)
	var temp_lifesteal: float = skill.get("tempLifesteal", 22)
	var per: int = maxi(1, roundi(caster.get("atk", 0) * atk_scale))
	var effects: Array = []
	var total_dmg: int = 0
	# 逐段飘字: PoC headlessStorm enemy-outer, 每段 sleep(95) (skill-handlers.ts:3974), physical 红 (3961,3966).
	#   全局段序 = enemy_i*hits + h, delay = 段序*0.095.
	var enemy_i: int = 0
	for e in _alive_enemies(caster, all_fighters):
		var ei: int = _find_idx(e, all_fighters)
		var shown: int = 0
		var seg_list: Array = []
		for h in range(hits):
			if not e.get("alive", false):
				break
			var r: Dictionary = Damage.apply_raw_damage(e, per, "physical")  # 无暴击无减甲 (固定值)
			var seg_shown: int = r["hpLoss"] + r["shieldAbs"]
			_seg_push(seg_list, seg_shown, "physical", false, (enemy_i * hits + h) * 0.095, e)
			shown += seg_shown
			# 逐段吸血绿字 (1:1 PoC doLifesteal per hit), delay 对齐该段 (原聚合成1个绿字)
			if temp_lifesteal > 0 and seg_shown > 0 and caster.get("alive", false):
				var hh: int = _heal_to(caster, roundi(seg_shown * temp_lifesteal / 100.0))
				if hh > 0:
					effects.append({"target_idx": caster_idx, "value": hh, "kind": "heal", "delay": (enemy_i * hits + h) * 0.095 + 0.05})
		if shown > 0:
			var ed: Dictionary = {"target_idx": ei, "value": shown, "kind": "damage", "dmg_type": "physical", "is_crit": false}
			if seg_list.size() >= 2: ed["segments"] = seg_list
			ed["hits"] = maxi(1, seg_list.size())
			effects.append(ed)
			total_dmg += shown
		enemy_i += 1
	# 临时吸血已改逐段绿字 (在上面 hit 循环里 per-hit, 1:1 PoC doLifesteal; 原此处聚合成1个绿字).
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 亡灵风暴 → 全敌 %d 物理" % [caster.get("name", "?"), total_dmg], "caster_idx": caster_idx}


## commonTeamShield: 全友盾 round(atk×0.5)
static func _common_team_shield(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var amt: int = roundi(caster.get("atk", 0) * skill.get("shieldScale", 0.5))
	var effects: Array = []
	for a in all_fighters:
		if a.get("side", "") == caster.get("side", "") and a.get("alive", false):
			var amt_a := Buffs.grant_shield(a, amt)
			effects.append({"target_idx": _find_idx(a, all_fighters), "value": amt_a, "kind": "shield"})
	return {"type": "shield", "effects": effects, "log_text": "%s → 全队护盾 +%d" % [caster.get("name", "?"), amt], "caster_idx": caster_idx}


## ghostPhase: 自 physImmune buff(90% 2回合) + 2段真伤 atk×0.6
static func _ghost_phase(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	Buffs.add(caster, "physImmune", skill.get("physReducePct", 90), int(skill.get("phantomTurns", 2)) + 1, "overwrite")
	if target == null or target.is_empty() or not target.get("alive", false):
		return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "👻 虚化"}], "log_text": "%s → 虚化" % caster.get("name", "?"), "caster_idx": caster_idx}
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC ghostPhase 2 段真伤 段间 sleep(500) (skill-handlers.ts:1528)
	var seg_list: Array = []
	for h in range(skill.get("hits", 2)):
		if not target.get("alive", false): break
		var hit: Dictionary = _crit_hit_no_dodge(caster, target, caster.get("atk", 0) * skill.get("atkScale", 0.6), "true")
		_seg_push(seg_list, hit["dmg"], "true", hit["is_crit"], h * 0.5, target)
		total += hit["dmg"]
		if hit["is_crit"]: any_crit = true
	var effects: Array = [{"target_idx": caster_idx, "kind": "passive", "label": "👻 虚化"}]
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": "true", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	return {"type": "damage", "effects": effects, "log_text": "%s → 虚影 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## diceFlashStrike: (4+1d6) 段随机敌 物理 atk×0.9×(1-0.1×i) 衰减
static func _dice_flash_strike(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var segs: int = skill.get("baseHits", 4) + 1 + randi() % 6
	var per_enemy: Dictionary = {}
	var any_crit: bool = false
	# 逐段飘字: PoC diceFlashStrike 每段 sleep(120) (skill-handlers.ts:5093), 段随机敌.
	#   每敌各自 seg_list, delay 用全局段序 i*0.12 (与 PoC 全局节奏一致).
	var per_seg: Dictionary = {}
	for i in range(segs):
		var enemies: Array = _alive_enemies(caster, all_fighters).filter(func(f): return not f.get("_isInBlackhole", false))   # 排除黑洞中敌(免伤) 1:1 PoC 不选, 原会浪费一段
		if enemies.is_empty(): break
		var e: Dictionary = enemies[randi() % enemies.size()]
		var scale: float = maxf(0.0, skill.get("perHitScale", 0.9) * (1.0 - 0.1 * i))
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, caster.get("atk", 0) * scale, "physical")
		if hit["dmg"] > 0:
			var ei: int = _find_idx(e, all_fighters)
			per_enemy[ei] = int(per_enemy.get(ei, 0)) + int(hit["dmg"])
			if not per_seg.has(ei): per_seg[ei] = []
			_seg_push(per_seg[ei], hit["dmg"], "physical", hit["is_crit"], i * 0.12, e)
			if hit["is_crit"]: any_crit = true
	var effects: Array = []
	for ei2 in per_enemy:
		var ed: Dictionary = {"target_idx": ei2, "value": int(per_enemy[ei2]), "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
		if per_seg.has(ei2) and (per_seg[ei2] as Array).size() >= 2: ed["segments"] = per_seg[ei2]
		effects.append(ed)
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 闪击 %d 连" % [caster.get("name", "?"), segs], "caster_idx": caster_idx}


## rainbowStorm: 全敌 hits 波, 每波每敌 magic(atkScale) + true(pierceScale) 双段 + 末尾 defDown
##   1:1 PoC skill-handlers.ts:3011-3056. 波间 sleep(500) (3046). magic蓝(3032) + true白(3041).
##   旧版 Godot 路由 _do_physical 只发 magic, 真伤 pierce 段 + defDown 整段丢失 (真数值 bug).
static func _rainbow_storm(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 4)
	var atk_scale: float = skill.get("atkScale", 0.2)
	var pierce_scale: float = skill.get("pierceScale", 0.1)
	var per_total: Dictionary = {}     # ei → 聚合伤 (procs/统计靠它)
	var per_crit: Dictionary = {}
	var per_seglist: Dictionary = {}
	var touched_idx: Array = []
	for wave in range(hits):
		for e in enemies:
			if not e.get("alive", false):
				continue
			var ei: int = _find_idx(e, all_fighters)
			if not per_seglist.has(ei):
				per_seglist[ei] = []
				touched_idx.append(ei)
			# magic 段 (走魔抗, 可暴击)
			var mh: Dictionary = _crit_hit_no_dodge(caster, e, caster.get("atk", 0) * atk_scale, "magic")
			if mh["dmg"] > 0:
				per_total[ei] = int(per_total.get(ei, 0)) + int(mh["dmg"])
				_seg_push(per_seglist[ei], mh["dmg"], "magic", mh["is_crit"], wave * 0.5, e)
				if mh["is_crit"]: per_crit[ei] = true
			# true 段 (pierce, 无视抗性; 复用同波暴击倍率 → 用 calc_crit_mult 经 _crit_hit_no_dodge 的 dmg)
			if pierce_scale > 0 and e.get("alive", false):
				var crit_mult: float = Damage.calc_crit_mult(caster) if mh["is_crit"] else 1.0
				var t_raw: int = roundi(caster.get("atk", 0) * pierce_scale * crit_mult)
				if t_raw > 0:
					var tr: Dictionary = Damage.apply_raw_damage(e, t_raw, "true")
					var t_shown: int = tr["hpLoss"] + tr["shieldAbs"]
					if t_shown > 0:
						per_total[ei] = int(per_total.get(ei, 0)) + t_shown
						_seg_push(per_seglist[ei], t_shown, "true", mh["is_crit"], wave * 0.5, e)
	# defDown buff (PoC 3049-3055: pct/turns, duration+1)
	var dd = skill.get("defDown", null)
	if dd is Dictionary and dd.get("pct", 0):
		for ei in touched_idx:
			var f: Dictionary = all_fighters[ei]
			if f.get("alive", false):
				Buffs.add(f, "defDown", dd.get("pct", 15), int(dd.get("turns", 3)) + 1)
	var effects: Array = []
	for ei2 in per_total:
		if int(per_total[ei2]) > 0:
			var ed: Dictionary = {"target_idx": ei2, "value": int(per_total[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": bool(per_crit.get(ei2, false))}
			if (per_seglist[ei2] as Array).size() >= 2: ed["segments"] = per_seglist[ei2]
			effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 全色风暴 → %d 敌 %d 波" % [caster.get("name", "?"), enemies.size(), hits], "caster_idx": caster_idx}


## rainbowReflect: 自疗 + 交替(敌魔法/友治疗), factor×0.85 floor0.4
static func _rainbow_reflect(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var base: int = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.5))
	var decay: float = skill.get("reflectDecay", 0.85)
	var floor_f: float = skill.get("reflectFloor", 0.4)
	var factor: float = 1.0
	var effects: Array = []
	var hit_enemies: Array = []
	var healed: Array = [caster]
	var h0: int = _heal_to(caster, maxi(1, roundi(base * maxf(floor_f, factor))))
	if h0 > 0: effects.append({"target_idx": caster_idx, "value": h0, "kind": "heal"})
	var want_enemy: bool = true
	var guard: int = 0
	while guard < 40:
		guard += 1
		factor *= decay
		var val: int = maxi(1, roundi(base * maxf(floor_f, factor)))
		if want_enemy:
			var e = null
			for x in _alive_enemies(caster, all_fighters):
				if not hit_enemies.has(x): e = x; break
			if e == null: break
			hit_enemies.append(e)
			var hit: Dictionary = _crit_hit_no_dodge(caster, e, val, "magic")   # 每跳滚暴击 (1:1 PoC rollCrit per hop), 原 calc_damage 无暴击
			if int(hit["dmg"]) > 0: effects.append({"target_idx": _find_idx(e, all_fighters), "value": int(hit["dmg"]), "kind": "damage", "dmg_type": "magic", "is_crit": bool(hit["is_crit"])})
		else:
			var a = null
			for x in all_fighters:
				if x.get("side", "") == caster.get("side", "") and x.get("alive", false) and not healed.has(x): a = x; break
			if a == null: break
			healed.append(a)
			var hh: int = _heal_to(a, val)
			if hh > 0: effects.append({"target_idx": _find_idx(a, all_fighters), "value": hh, "kind": "heal"})
		want_enemy = not want_enemy
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 七彩折射" % caster.get("name", "?"), "caster_idx": caster_idx}


## bubbleBurst: 消耗 bubbleStore → 整排敌 (magic consumed×0.4 + phys atk×0.8) 共用 crit
static func _bubble_burst(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var stored: int = int(caster.get("bubbleStore", 0))
	var consumed: int = roundi(stored * skill.get("bubbleConsumePct", 100) / 100.0)
	caster["bubbleStore"] = stored - consumed
	var magic_dmg: int = roundi(consumed * skill.get("bubbleMagicScale", 0.4))
	var phys_base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.8))
	var targets: Array = SlotHelpers.same_row_fighters(all_fighters, target)
	if targets.is_empty(): targets = [target]
	var effects: Array = []
	# 颜色修复: PoC bubbleBurst 每敌 magic蓝 + phys红 两独立飘字 (skill-handlers.ts:5532,5543);
	#   Godot 旧版求和成单 magic effect → 物理段错显蓝. 拆成两段, 各自 dmg_type 正确.
	for e in targets:
		if e.get("side", "") == caster.get("side", "") or not e.get("alive", false): continue
		var is_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))
		var cm: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
		var ei: int = _find_idx(e, all_fighters)
		if magic_dmg > 0:
			var mr: Dictionary = Damage.apply_raw_damage(e, roundi(magic_dmg * cm), "magic")
			var m_shown: int = mr["hpLoss"] + mr["shieldAbs"]
			if m_shown > 0:
				effects.append({"target_idx": ei, "value": m_shown, "kind": "damage", "dmg_type": "magic", "is_crit": is_crit})
		var pr: Dictionary = Damage.apply_raw_damage(e, Damage.calc_damage(caster, e, phys_base * cm, "physical"), "physical")
		var p_shown: int = pr["hpLoss"] + pr["shieldAbs"]
		if p_shown > 0:
			effects.append({"target_idx": ei, "value": p_shown, "kind": "damage", "dmg_type": "physical", "is_crit": is_crit})
	if effects.is_empty(): return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 泡泡爆破 (%d泡)" % [caster.get("name", "?"), consumed], "caster_idx": caster_idx}


## bubbleHeal: 治疗友 round(atk×1.2 + maxHp×10%) + 其余友 splashPct%
static func _bubble_heal(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var tgt: Dictionary = caster
	if target != null and not target.is_empty() and target.get("side", "") == caster.get("side", "") and target.get("alive", false):
		tgt = target
	var amt: int = roundi(caster.get("atk", 0) * skill.get("healAtkPct", 120) / 100.0) + roundi(caster.get("maxHp", 0) * skill.get("healHpPct", 10) / 100.0)
	var effects: Array = []
	var h: int = _heal_to(tgt, amt)
	if h > 0: effects.append({"target_idx": _find_idx(tgt, all_fighters), "value": h, "kind": "heal"})
	var splash: int = roundi(amt * skill.get("splashPct", 25) / 100.0)
	for a in all_fighters:
		if a.get("side", "") == caster.get("side", "") and a.get("alive", false) and a != tgt:
			var sh: int = _heal_to(a, splash)
			if sh > 0: effects.append({"target_idx": _find_idx(a, all_fighters), "value": sh, "kind": "heal"})
	return {"type": "heal", "effects": effects, "log_text": "%s → 泡泡治愈" % caster.get("name", "?"), "caster_idx": caster_idx}


## phoenixPurify: 清友军 debuff + recalc + 回 maxHp×10%×清除数
static func _phoenix_purify(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var tgt: Dictionary = caster
	if target != null and not target.is_empty() and target.get("side", "") == caster.get("side", "") and target.get("alive", false):
		tgt = target
	var debuffs := ["atkDown", "defDown", "mrDown", "burn", "curse", "healReduce", "poison", "bleed", "armorBreak", "chilled", "stun"]
	var before: int = 0
	var kept: Array = []
	for b in tgt.get("buffs", []):
		if b is Dictionary and debuffs.has(b.get("type", "")):
			before += 1
		else:
			kept.append(b)
	tgt["buffs"] = kept
	StatsRecalc.recalc(tgt)
	var effects: Array = [{"target_idx": _find_idx(tgt, all_fighters), "kind": "passive", "label": "✨ 净化 %d" % before}]
	if before > 0:
		var h: int = _heal_to(tgt, roundi(tgt.get("maxHp", 0) * 0.1 * before))
		if h > 0: effects.append({"target_idx": _find_idx(tgt, all_fighters), "value": h, "kind": "heal"})
	return {"type": "heal", "effects": effects, "log_text": "%s → 净化 (清 %d 减益)" % [caster.get("name", "?"), before], "caster_idx": caster_idx}


## shellCopy(shell): 复制 2 个敌方技能(×0.6数值)并施放
const SHELL_BLACKLIST := ["shellCopy", "cyberDeploy", "cyberBuff", "hidingDefend", "hidingCommand", "fortuneDice", "fortuneAllIn", "ghostPhase", "twoHeadSwitch", "mechAttack", "gamblerBet", "chestCount", "chestSmash", "starWormhole", "bubbleBurst", "shellAbsorb", "shellErode", "shellFortify", "fortuneBuyEquip", "fortuneGainCoins", "ghostPhantom", "starShieldBreak", "hidingBuffSummon", "stoneTaunt", "cyberBeam", "ninjaBackstab"]
const SHELL_SELF := ["phoenixShield", "volcanoArmor", "crystalBarrier", "lightningShield", "diamondFortify", "diceFate"]
const SHELL_ALLY := ["heal", "shield", "bubbleShield", "angelBless", "phoenixPurify", "commonTeamShield", "cyberSwarmShield", "bambooHeal", "bubbleHeal"]
const SHELL_SCALE_FIELDS := ["power", "pierce", "atkScale", "defScale", "hpPct", "totalScale", "pierceScale", "normalScale", "selfHpPct", "shield", "shieldFlat", "shieldHpPct", "shieldAtkScale", "heal"]

static func _shell_copy(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var pool: Array = []
	var seen: Dictionary = {}
	for e in _alive_enemies(caster, all_fighters):
		for s in e.get("skills", []):
			var st: String = s.get("type", "")
			if st == "" or SHELL_BLACKLIST.has(st) or seen.has(st) or s.get("passiveSkill", false):
				continue
			seen[st] = true
			pool.append(s)
	pool.shuffle()
	var effects: Array = []
	for i in range(mini(2, pool.size())):
		var copy: Dictionary = pool[i].duplicate(true)
		copy["cdLeft"] = 0
		for fld in SHELL_SCALE_FIELDS:
			if copy.has(fld) and (copy[fld] is float or copy[fld] is int):
				copy[fld] = copy[fld] * 0.6
		if copy.get("hot", null) is Dictionary and copy["hot"].has("hpPerTurn"):
			copy["hot"]["hpPerTurn"] = copy["hot"]["hpPerTurn"] * 0.6
		if copy.get("dot", null) is Dictionary and copy["dot"].has("dmg"):
			copy["dot"]["dmg"] = copy["dot"]["dmg"] * 0.6
		var ct: String = copy.get("type", "")
		var ctarget: Dictionary = target
		if SHELL_SELF.has(ct) or copy.get("selfCast", false) or copy.get("aoe", false) or copy.get("aoeAlly", false):
			ctarget = caster
		elif SHELL_ALLY.has(ct):
			var best = null; var lo := INF
			for a in all_fighters:
				if a.get("side", "") == caster.get("side", "") and a.get("alive", false) and float(a.get("hp", 0)) < lo:
					lo = a.get("hp", 0); best = a
			if best != null: ctarget = best
		else:
			var ben := _alive_enemies(caster, all_fighters)
			if not ben.is_empty():
				ben.sort_custom(func(a, b): return float(a.get("hp", 0)) < float(b.get("hp", 0)))
				ctarget = ben[0]
		var r: Dictionary = execute(caster, ctarget, all_fighters, copy)
		for ef in r.get("effects", []):
			effects.append(ef)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 模仿 → 复制敌技" % caster.get("name", "?"), "caster_idx": caster_idx}


## 治疗到 fighter (吃 healReduce + 潮汐涟漪 + 守护羁绊; 返回实际回血)
## 1:1 PoC applyHeal (skill-handlers.ts:442 / equipment.ts:12): healReduce → _equipRippleHealAmp → _synergyGuardAmp
static func _heal_to(f: Dictionary, amount: int) -> int:
	if amount <= 0 or not f.get("alive", false):
		return 0
	var hr = Buffs.find(f, "healReduce")
	if hr != null and int(hr.get("value", 0)) > 0:
		amount = roundi(amount * (1.0 - hr.get("value", 0) / 100.0))
	# 潮汐涟漪装备: 受治疗 +_equipRippleHealAmp% (PoC skill-handlers.ts:449)
	var ripple: float = float(f.get("_equipRippleHealAmp", 0))
	if ripple > 0:
		amount = roundi(amount * (1.0 + ripple / 100.0))
	# 守护羁绊: 受治疗 +_synergyGuardAmp (PoC skill-handlers.ts:451)
	var guard: float = float(f.get("_synergyGuardAmp", 0.0))
	if guard > 0.0:
		amount = roundi(amount * (1.0 + guard))
	amount = roundi(amount * Rules.heal_mult())   # 铁壁之日 受治疗 ×1.3 (原漏, 与护盾 shield_mult 同口径; PoC applyHeal:453)
	amount = Buffs.fatigue_amt(f, amount)   # 决胜局疲惫: 治疗 ×0.5
	var before: int = f.get("hp", 0)
	f["hp"] = mini(int(f.get("maxHp", 0)), before + amount)
	var _healed: int = int(f["hp"]) - before
	# 饰品[续航]溢出转盾 (规格#552): 满血仍受治疗 → 溢出量转护盾, 无上限。在留盾前算溢出。
	#   _heal_shield_gain 累计本次治疗顺带获得的护盾 → BattleScene._refresh_slot 读它一次, 飘"+N盾"+盾光 (原静默)。
	if f.get("_p2AccessoryOverflowShield", false):
		var overflow: int = amount - _healed
		if overflow > 0:
			f["shield"] = int(f.get("shield", 0)) + overflow
			f["_heal_shield_gain"] = int(f.get("_heal_shield_gain", 0)) + overflow
	if _healed > 0 and float(f.get("_tideHealShieldPct", 0.0)) > 0.0:   # 潮汐·治疗留盾(审计)
		var tide_sh: int = Buffs.grant_shield(f, roundi(float(_healed) * float(f.get("_tideHealShieldPct", 0.0))))
		if tide_sh > 0:
			f["_heal_shield_gain"] = int(f.get("_heal_shield_gain", 0)) + tide_sh
	return _healed


## volcanoSmash: (atk×1.3 + maxHp×8%) 物理 + lifestealPct% 生命偷取
static func _volcano_smash(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 1.3))
	if skill.get("selfHpPct", 0) > 0:
		base += roundi(caster.get("maxHp", 0) * skill.get("selfHpPct", 0) / 100.0)
	var hit: Dictionary = _crit_hit_no_dodge(caster, target, base, "physical")
	var dmg: int = hit["dmg"]
	if dmg > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": dmg, "kind": "damage", "dmg_type": "physical", "is_crit": hit["is_crit"]})
	var ls: float = skill.get("lifestealPct", 0)
	if ls > 0 and caster.get("alive", false):
		var before: int = caster.get("hp", 0)
		caster["hp"] = mini(int(caster.get("maxHp", 0)), before + Buffs.fatigue_amt(caster, roundi(dmg * ls / 100.0)))
		var actual: int = int(caster["hp"]) - before
		if actual > 0:
			effects.append({"target_idx": caster_idx, "value": actual, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 烈焰重击 → %s" % ["💥 " if hit["is_crit"] else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## volcanoArmor: 自盾 atk×0.9 + def/mrUp base×20% 3t + healLostPct% 已损 heal
static func _volcano_armor(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var effects: Array = []
	var shield_amt: int = roundi(roundi(caster.get("atk", 0) * skill.get("shieldAtkScale", 0.9)) * Rules.shield_mult())   # 铁壁之日 ×1.3 (原漏)
	if shield_amt > 0:
		shield_amt = Buffs.grant_shield(caster, shield_amt)
		effects.append({"target_idx": caster_idx, "value": shield_amt, "kind": "shield"})
	var pct: float = skill.get("defMrUpPct", 20)
	var turns: int = int(skill.get("defMrUpTurns", 3)) + 1
	var def_gain: int = roundi(caster.get("baseDef", 0) * pct / 100.0)
	var mr_gain: int = roundi(caster.get("baseMr", caster.get("baseDef", 0)) * pct / 100.0)
	if def_gain > 0:
		Buffs.add(caster, "defUp", def_gain, turns)
	if mr_gain > 0:
		Buffs.add(caster, "mrUp", mr_gain, turns)
	StatsRecalc.recalc(caster)
	var hlp: float = skill.get("healLostPct", 0)
	if hlp > 0 and caster.get("alive", false):
		var lost: int = int(caster.get("maxHp", 0)) - int(caster.get("hp", 0))
		var before: int = caster.get("hp", 0)
		caster["hp"] = mini(int(caster.get("maxHp", 0)), before + Buffs.fatigue_amt(caster, roundi(lost * hlp / 100.0)))
		var actual: int = int(caster["hp"]) - before
		if actual > 0:
			effects.append({"target_idx": caster_idx, "value": actual, "kind": "heal"})
	return {"type": "shield", "effects": effects, "log_text": "%s → 熔岩铠甲 → 自盾 +%d" % [caster.get("name", "?"), shield_amt], "caster_idx": caster_idx}


## volcanoErupt: 全敌 5 段 (atk×0.22 + maxHp×3%) magic + burn + 总伤 15% 生命偷取
static func _volcano_erupt(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 5)
	# 5 段全敌AOE: 逐波 segments(delay=波序×150ms), 逐波飘字+血条trail (原聚合成1飘字).
	var seg_delay: float = float(skill.get("hitStaggerMs", 150)) / 1000.0
	var per_enemy_segs: Dictionary = {}
	var per_enemy_total: Dictionary = {}
	var any_crit: bool = false
	var total_all: int = 0
	for h in range(hits):
		for e in enemies:
			if not e.get("alive", false):
				continue
			var ei: int = _find_idx(e, all_fighters)
			var mb: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.22))
			if skill.get("selfHpPct", 0) > 0:
				mb += roundi(caster.get("maxHp", 0) * skill.get("selfHpPct", 0) / 100.0)
			var hit: Dictionary = _crit_hit_no_dodge(caster, e, mb, "magic")
			if hit["dmg"] > 0:
				if not per_enemy_segs.has(ei):
					per_enemy_segs[ei] = []
					per_enemy_total[ei] = 0
				per_enemy_total[ei] = int(per_enemy_total[ei]) + int(hit["dmg"])
				total_all += int(hit["dmg"])
				(per_enemy_segs[ei] as Array).append({
					"value": int(hit["dmg"]), "dmg_type": "magic", "is_crit": bool(hit["is_crit"]),
					"delay": h * seg_delay,
					"hp_after": float(e.get("hp", 0)), "shield_after": float(e.get("shield", 0)),
				})
				if hit["is_crit"]:
					any_crit = true
	for e in enemies:
		if e.get("alive", false):
			Dot.apply_stacks(e, "burn", _default_burn_stacks(caster))
	var effects: Array = []
	for ei in per_enemy_segs:
		effects.append({"target_idx": ei, "value": int(per_enemy_total[ei]), "kind": "damage", "dmg_type": "magic", "is_crit": any_crit, "segments": per_enemy_segs[ei]})
	if caster.get("alive", false) and total_all > 0:
		var before: int = caster.get("hp", 0)
		caster["hp"] = mini(int(caster.get("maxHp", 0)), before + Buffs.fatigue_amt(caster, roundi(total_all * 0.15)))
		var actual: int = int(caster["hp"]) - before
		if actual > 0:
			effects.append({"target_idx": caster_idx, "value": actual, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 火山爆发 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## volcanoStomp: 全敌 atk×0.8 magic (无暴击) + stunChance% 眩晕 + healLostPct% 已损 heal
static func _volcano_stomp(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var effects: Array = []
	var stun_chance: float = skill.get("stunChance", 40)
	for e in enemies:
		if not e.get("alive", false):
			continue
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, caster.get("atk", 0) * skill.get("atkScale", 0.8), "magic", false)
		var ei: int = _find_idx(e, all_fighters)
		if hit["dmg"] > 0:
			effects.append({"target_idx": ei, "value": hit["dmg"], "kind": "damage", "dmg_type": "magic", "is_crit": false})
		if e.get("alive", false) and randf() * 100.0 < stun_chance:
			Buffs.add(e, "stun", 1, 2, "ignore")
			e["_stunUsed"] = false
			effects.append({"target_idx": ei, "kind": "passive", "label": "💫 眩晕", "flash": "freeze"})   # 眩晕施加闪 (原只飘字)
	var hlp: float = skill.get("healLostPct", 0)
	if hlp > 0 and caster.get("alive", false):
		var lost: int = int(caster.get("maxHp", 0)) - int(caster.get("hp", 0))
		var before: int = caster.get("hp", 0)
		caster["hp"] = mini(int(caster.get("maxHp", 0)), before + Buffs.fatigue_amt(caster, roundi(lost * hlp / 100.0)))
		var actual: int = int(caster["hp"]) - before
		if actual > 0:
			effects.append({"target_idx": caster_idx, "value": actual, "kind": "heal"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 岩浆践踏 → %d 敌" % [caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## gamblerCards: 3 段每段随机 0.3~0.6×ATK 物理
static func _gambler_cards(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(_find_idx(caster, all_fighters))
	var hits: int = skill.get("hits", 3)
	var min_s: float = skill.get("minScale", 0.3)
	var max_s: float = skill.get("maxScale", 0.6)
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC gamblerCards 每段 sleep(700+200)=900ms (skill-handlers.ts:4797)
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false):
			break
		var scale: float = randf_range(min_s, max_s)
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * scale, "physical", all_fighters, true)   # 卡牌射击必中 (1:1 PoC applyRawDamage 不过闪避)
		_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], h * 0.9, target)
		total += hit["dmg"]
		if hit["is_crit"]:
			any_crit = true
	return _multi_hit_result(caster, target, all_fighters, "卡牌射击", total, "physical", any_crit, [], seg_list)


## iceSpike: 6 段交替物理/魔法, 每段 atk×(totalScale/6)
static func _ice_spike(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(_find_idx(caster, all_fighters))
	var hits: int = skill.get("hits", 6)
	var per_scale: float = skill.get("totalScale", 1.4) / float(hits)
	var phys_total: int = 0
	var magic_total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC iceSpike 每段 sleep(180) (skill-handlers.ts:3740); 颜色随 h%2 交替 (物理红/魔法蓝)
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false):
			break
		var dt: String = "physical" if h % 2 == 0 else "magic"
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * per_scale, dt, all_fighters)
		_seg_push(seg_list, hit["dmg"], dt, hit["is_crit"], h * 0.18, target)
		if dt == "physical":
			phys_total += hit["dmg"]
		else:
			magic_total += hit["dmg"]
		if hit["is_crit"]:
			any_crit = true
	# 合并显示总伤 (主 dmg_type 用 physical)
	return _multi_hit_result(caster, target, all_fighters, "冰锥", phys_total + magic_total, "physical", any_crit, [], seg_list)


## twoHeadMagicWave: 4 段 — 前 2 物理 + 后 2 真伤, 每段 atk×0.4
static func _two_head_magic_wave(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(_find_idx(caster, all_fighters))
	var scale: float = skill.get("atkScale", 0.4)
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC twoHeadMagicWave 每段 sleep(180) (skill-handlers.ts:4045); h<2 物理红 / 否则真伤白
	var seg_list: Array = []
	for h in range(4):
		if not target.get("alive", false):
			break
		var dt: String = "true" if h % 2 == 1 else "physical"   # 红白交替 (1:1 PoC isPierceHit=i%2===1), 原 h<2=红红白白
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * scale, dt, all_fighters)
		_seg_push(seg_list, hit["dmg"], dt, hit["is_crit"], h * 0.18, target)
		total += hit["dmg"]
		if hit["is_crit"]:
			any_crit = true
	return _multi_hit_result(caster, target, all_fighters, "魔法波", total, "physical", any_crit, [], seg_list)


## hunterPoison: 物理 atk×0.8 + poison(round(dmg×turns/4)) + healReduce
static func _hunter_poison(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var result := _do_physical(caster, target, all_fighters, skill, "physical")
	if target != null and not target.is_empty() and target.get("alive", false):
		var dot = skill.get("dot", {"dmg": 15, "turns": 3})
		var stacks: int = maxi(1, roundi(float(dot.get("dmg", 15)) * float(dot.get("turns", 3)) / 4.0))
		Dot.apply_stacks(target, "poison", stacks)
		if skill.get("healReduce", false):
			Buffs.add(target, "healReduce", 50, 4, "refresh")
	return result


## angelEquality: 2 段物理 atk×1.0; target 稀有度≥A 追加真伤 atk×0.5 + 已损HP×10%; 全程10%吸血
static func _angel_equality(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(_find_idx(caster, all_fighters))
	var normal_scale: float = skill.get("normalScale", 1.0)
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC angelEquality 物理段 sleep(280) (skill-handlers.ts:5570), 真伤段 sleep(280) (5593)
	var seg_list: Array = []
	# 吸血: PoC 每【物理段】doLifesteal(shown + 该段判定, delay). 物理部分在此逐段吸; 判定部分由 BattleScene 审判块补.
	#   真伤段【不】吸血 (1:1 PoC: doLifesteal 在 h<2 物理循环内, 真伤段在循环外). 原: 从 total(含真伤)聚合1个绿字、且漏判定.
	var ls_pct: float = skill.get("lifestealPct", 10)
	var extra: Array = []
	var c_idx: int = _find_idx(caster, all_fighters)
	# 2 段物理 (各自吸血绿字)
	for h in range(skill.get("hits", 2)):
		if not target.get("alive", false):
			break
		var hit: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * normal_scale, "physical", all_fighters)
		_seg_push(seg_list, hit["dmg"], "physical", hit["is_crit"], h * 0.28, target)
		total += hit["dmg"]
		if hit["is_crit"]:
			any_crit = true
		if ls_pct > 0 and hit["dmg"] > 0 and caster.get("alive", false):
			var before_h: int = caster.get("hp", 0)
			caster["hp"] = mini(caster.get("maxHp", 0), before_h + Buffs.fatigue_amt(caster, roundi(hit["dmg"] * ls_pct / 100.0)))
			var ah: int = caster["hp"] - before_h
			if ah > 0:
				extra.append({"target_idx": c_idx, "value": ah, "kind": "heal", "delay": h * 0.28 + 0.12})
	# 高稀有度追加真伤 (单独真伤段, dmg_type:"true" 白字; 不吸血)
	var anti: Array = skill.get("antiHighRarity", ["A", "S", "SS", "SSS"])
	if target.get("alive", false) and target.get("rarity", "C") in anti:
		var lost_hp: float = target.get("maxHp", 0) - target.get("hp", 0)
		var true_base: float = caster.get("atk", 0) * skill.get("extraTrueAtkScale", 0.5) + lost_hp * skill.get("extraTrueLostHpPct", 10) / 100.0
		var t_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))   # 1:1 PoC 追加真伤段可暴击 (skill-handlers.ts:5575) — 原flat不暴击
		if t_crit:
			true_base *= Damage.calc_crit_mult(caster); any_crit = true
		var r: Dictionary = Damage.apply_raw_damage(target, maxi(1, roundi(true_base)), "true")
		var true_shown: int = r["hpLoss"] + r["shieldAbs"]
		_seg_push(seg_list, true_shown, "true", t_crit, 2.0 * 0.28, target)
		total += true_shown
	return _multi_hit_result(caster, target, all_fighters, "平等", total, "physical", any_crit, extra, seg_list)


# ══════════════════════════════════════════════════════════════
# B 组: 选择器技能 (1:1 PoC, 数据确认)
# ══════════════════════════════════════════════════════════════

## 多段打同一目标, 累加 total + 收集 dodge effects. 返 {total, any_crit}
static func _multi_hit_target(caster: Dictionary, target: Dictionary, base: float,
		dmg_type: String, hits: int, all_fighters: Array, effects: Array, no_dodge: bool = false) -> Dictionary:
	var total: int = 0
	var any_crit: bool = false
	for h in range(hits):
		if not target.get("alive", false):
			break
		var hit: Dictionary = _one_hit(caster, target, base, dmg_type, all_fighters, no_dodge)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
			continue
		total += hit["dmg"]
		if hit["is_crit"]:
			any_crit = true
	return {"total": total, "any_crit": any_crit}


## ghostTouch: 单体 物理 atk×0.4 + 真伤 atk×0.9, 两段共享同一 critMult
static func _ghost_touch(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	# PoC ghostTouch 两段都走 applyRawDamage 直落 = 必中 (不判闪避, skill-handlers.ts:1370-1380) — 原误加 _roll_dodge 会被闪避吞掉整技能
	var is_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))
	var crit_mult: float = Damage.calc_crit_mult(caster) if is_crit else 1.0
	var atk_v: float = caster.get("atk", 0)
	var total: int = 0
	# 逐段飘字: PoC ghostTouch 物理/真伤近即时同帧 (skill-handlers.ts:1374-1375),
	#   物理红 yOff=0 在下, 真伤白 yOff=22 在上 (1:1 ghost.js:32-33)
	var seg_list: Array = []
	# 物理段
	var phys: int = Damage.calc_damage(caster, target, atk_v * skill.get("normalScale", 0.4) * crit_mult, "physical")
	var r1: Dictionary = Damage.apply_raw_damage(target, phys, "physical")
	var phys_shown: int = r1["hpLoss"] + r1["shieldAbs"]
	_seg_push(seg_list, phys_shown, "physical", is_crit, 0.0, target, 0.0)
	total += phys_shown
	# 真伤段 (target 存活才打)
	if target.get("alive", false):
		var tru: int = Damage.calc_damage(caster, target, atk_v * skill.get("pierceScale", 0.9) * crit_mult, "true")
		var r2: Dictionary = Damage.apply_raw_damage(target, tru, "true")
		var true_shown: int = r2["hpLoss"] + r2["shieldAbs"]
		_seg_push(seg_list, true_shown, "true", is_crit, 0.0, target, 22.0)
		total += true_shown
	return _multi_hit_result(caster, target, all_fighters, "幽魂触碰", total, "physical", is_crit, [], seg_list)


## ninjaImpact: 主目标 atk×1.3 + 身后单位 atk×0.8 (各独立 crit)
static func _ninja_impact(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var effects: Array = []
	var atk_v: float = caster.get("atk", 0)
	# 主目标
	var main: Dictionary = _multi_hit_target(caster, target, atk_v * skill.get("atkScale", 1.3), "physical", 1, all_fighters, effects)
	if main["total"] > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": main["total"], "kind": "damage", "dmg_type": "physical", "is_crit": main["any_crit"]})
	_mark_knockup(target)   # 击飞靶子 (PoC api.knockup; e_dart 读); 017锚/龟蛋免击飞
	# 身后单位 (front→back 同 col 那一个, PoC fighterBehind)
	var behind = SlotHelpers.fighter_behind(all_fighters, target)
	if behind != null:
		var bh: Dictionary = _multi_hit_target(caster, behind, atk_v * skill.get("behindScale", 0.8), "physical", 1, all_fighters, effects)
		if bh["total"] > 0:
			effects.append({"target_idx": _find_idx(behind, all_fighters), "value": bh["total"], "kind": "damage", "dmg_type": "physical", "is_crit": bh["any_crit"]})
		_mark_knockup(behind)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 冲击 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## rockShockwave: 整横排 (def×0.5+mr×0.5)×(1+0.04×layers) + 眩晕
static func _rock_shockwave(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var targets: Array = SlotHelpers.same_column_fighters(all_fighters, target)
	if targets.is_empty():
		targets = [target]
	var layers: int = caster.get("_rockLayers", 0)
	var layer_mult: float = 1.0 + skill.get("rockLayerDmgScale", 0.04) * layers
	var base: float = roundi((caster.get("def", 0) * skill.get("defScale", 0.5) + caster.get("mr", caster.get("def", 0)) * skill.get("mrScale", 0.5)) * layer_mult)   # 1:1 PoC dealPhysical 前先取整(原未取整→±1)
	var effects: Array = []
	var any_crit: bool = false
	for t in targets:
		if not t.get("alive", false):
			continue
		var hit: Dictionary = _multi_hit_target(caster, t, base, "physical", 1, all_fighters, effects)
		if hit["total"] > 0:
			effects.append({"target_idx": _find_idx(t, all_fighters), "value": hit["total"], "kind": "damage", "dmg_type": "physical", "is_crit": hit["any_crit"]})
			if hit["any_crit"]:
				any_crit = true
		_mark_knockup(t)   # 冲击波击飞 (PoC api.knockup; e_dart 读); 锚/龟蛋免
		# 眩晕: min(100, 1×layers)% 概率
		if t.get("alive", false) and layers > 0:
			var stun_pct: float = minf(100.0, skill.get("rockStunPctPerLayer", 1) * layers)
			if randf() < stun_pct / 100.0:
				Buffs.add(t, "stun", 1, int(skill.get("stunTurns", 1)) + 1, "ignore")
				t["_stunUsed"] = false
				# 眩晕施加可见化: 飘"💫眩晕"标 + 冰罩闪 (原静默) — flash 走 BattleScene passive 分支
				effects.append({"target_idx": _find_idx(t, all_fighters), "kind": "passive", "label": "💫眩晕", "flash": "freeze"})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 磐石之躯 → 横扫 %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), targets.size()], "caster_idx": caster_idx}


## shellStrike: 2段交替物理/真伤 atk×0.6, 邻接溅射25%, 孤立×1.5
static func _shell_strike(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 2)
	var per_hit: float = caster.get("atk", 0) * skill.get("totalScale", 1.2) / float(hits)
	var splash_pct: float = skill.get("splashAdjacent", 25)
	var isolated_bonus: float = skill.get("isolatedBonus", 1.5)
	var effects: Array = []
	var main_total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC shellStrike 段间 sleep(500)+sleep(150)=650ms (skill-handlers.ts:2370-2372);
	#   偶段 physical 红 / 奇段 true 白 (2311,2337) — 每段 dmg_type 各自正确 (颜色修复 #4)
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false):
			break
		var dt: String = "physical" if h % 2 == 0 else "true"
		var splash_targets: Array = SlotHelpers.adjacent_fighters(all_fighters, target)
		var seg_base: float = per_hit
		if splash_targets.is_empty():
			seg_base = per_hit * isolated_bonus   # 孤立加成
		var hit: Dictionary = _one_hit(caster, target, seg_base, dt, all_fighters, false)   # 1:1 PoC 原版JS shell.js:14-19 主目标每段过闪避检测 (TS:2322漏dodge=退化, 不照TS); 溅射仍必中(2859)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
		else:
			_seg_push(seg_list, hit["dmg"], dt, hit["is_crit"], h * 0.65, target)
			main_total += hit["dmg"]
			if hit["is_crit"]:
				any_crit = true
		# 溅射 (基数 = per_hit×25%, 不含孤立加成)
		for sp in splash_targets:
			if not sp.get("alive", false):
				continue
			var sp_hit: Dictionary = _one_hit(caster, sp, per_hit * splash_pct / 100.0, dt, all_fighters, true)   # 必中
			if not sp_hit["dodged"] and sp_hit["dmg"] > 0:
				effects.append({"target_idx": _find_idx(sp, all_fighters), "value": sp_hit["dmg"], "kind": "damage", "dmg_type": dt, "is_crit": sp_hit["is_crit"]})
	if main_total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": main_total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 攻击 → %s" % ["💥 " if any_crit else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## shellErode: magic 主atk×0.25 + 同列另一敌atk×0.10, 波数=3+floor(crit×100/20)
static func _shell_erode(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var crit_pct: float = caster.get("crit", 0.0) * 100.0
	var wave_count: int = 3 + int(crit_pct / 20.0)
	var main_scale: float = skill.get("mainScale", 0.25)
	var behind_scale: float = skill.get("behindScale", 0.10)
	# 同列另一敌 (整排里除 target 第一个)
	var other = null
	for e in SlotHelpers.same_column_fighters(all_fighters, target):
		if e != target and e.get("alive", false):
			other = e
			break
	var effects: Array = []
	var main_total: int = 0
	var other_total: int = 0
	var any_crit: bool = false
	# 逐波飘字: PoC shellErode 每波 sleep(80) (skill-handlers.ts:2259), 全程 magic 蓝
	var seg_main: Array = []
	var seg_other: Array = []
	for w in range(wave_count):
		if target.get("alive", false):
			var h1: Dictionary = _one_hit(caster, target, caster.get("atk", 0) * main_scale, "magic", all_fighters)
			if not h1["dodged"]:
				_seg_push(seg_main, h1["dmg"], "magic", h1["is_crit"], w * 0.08, target)
				main_total += h1["dmg"]
				if h1["is_crit"]:
					any_crit = true
		if other != null and other.get("alive", false):
			var h2: Dictionary = _one_hit(caster, other, caster.get("atk", 0) * behind_scale, "magic", all_fighters)
			if not h2["dodged"]:
				_seg_push(seg_other, h2["dmg"], "magic", h2["is_crit"], w * 0.08, other)
				other_total += h2["dmg"]
	if main_total > 0:
		var em: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": main_total, "kind": "damage", "dmg_type": "magic", "is_crit": any_crit}
		if seg_main.size() >= 2: em["segments"] = seg_main
		effects.append(em)
	if other != null and other_total > 0:
		var eo: Dictionary = {"target_idx": _find_idx(other, all_fighters), "value": other_total, "kind": "damage", "dmg_type": "magic", "is_crit": false}
		if seg_other.size() >= 2: eo["segments"] = seg_other
		effects.append(eo)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 侵蚀 → %d 波" % [caster.get("name", "?"), wave_count], "caster_idx": caster_idx}


## cyberBeam: 整横排每敌 2段物理atk×0.5 + 真伤(droneCount×trueScale/2)
static func _cyber_beam(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var targets: Array = SlotHelpers.same_column_fighters(all_fighters, target)
	if targets.is_empty():
		targets = [target]
	var drone_count: int = (caster.get("_drones", []) as Array).size()
	var true_scale: float = skill.get("droneTrueScaleEnhanced", 0.07) if caster.get("_cyberEnhanced", false) else skill.get("droneTrueScale", 0.10)
	var per_seg_true: float = caster.get("atk", 0) * (true_scale / 2.0) * drone_count
	var atk_scale: float = skill.get("atkScale", 0.5)
	var effects: Array = []
	var any_crit_global: bool = false
	for t in targets:
		if not t.get("alive", false):
			continue
		var total: int = 0
		var any_crit: bool = false
		# 逐段飘字: PoC cyberBeam 每目标 2 seg 段间 sleep(280); 每 seg 物理红 + 真伤金(delay+100ms,yOff+24)独立跳出共4数字 (skill-handlers.ts:3306). hits=物理段数(真伤段不计 on-hit 次).
		var seg_list: Array = []
		var phys_hits: int = 0
		for seg in range(2):
			if not t.get("alive", false):
				break
			# 物理段 (吃 crit, 必中 1:1 PoC cyberBeam applyRawDamage skill-handlers.ts:3313 — 原可被闪避)
			var ph: Dictionary = _one_hit(caster, t, caster.get("atk", 0) * atk_scale, "physical", all_fighters, true)
			if not ph["dodged"]:
				total += ph["dmg"]
				phys_hits += 1
				if ph["is_crit"]:
					any_crit = true
					any_crit_global = true
				_seg_push(seg_list, ph["dmg"], "physical", ph["is_crit"], seg * 0.28, t)
			# 真伤段 (droneCount>0 才打, 无暴击)
			if drone_count > 0 and t.get("alive", false) and roundi(per_seg_true) > 0:   # 1:1 PoC round(trueDmgPerSeg)>0 (原 >=1.0 在 [0.5,1) 漏打真伤段)
				var r: Dictionary = Damage.apply_raw_damage(t, roundi(per_seg_true), "true")
				var ts: int = r["hpLoss"] + r["shieldAbs"]
				total += ts
				_seg_push(seg_list, ts, "true", false, seg * 0.28 + 0.10, t, 24.0)
		if total > 0:
			var ed_c: Dictionary = {"target_idx": _find_idx(t, all_fighters), "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": any_crit}
			if seg_list.size() >= 2: ed_c["segments"] = seg_list
			ed_c["hits"] = maxi(1, phys_hits)
			effects.append(ed_c)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 能量大炮 → %d 敌 (%d 炮)" % ["💥 " if any_crit_global else "", caster.get("name", "?"), targets.size(), drone_count], "caster_idx": caster_idx}


## starWormhole: 永久魔穿+=round(6+0.5×lv), 整横排 4段magic atk×1.5×(1+0.1×turn)/4
static func _star_wormhole(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	# 永久魔穿
	var lv: int = caster.get("_level", 1)
	var pen_gain: int = roundi(skill.get("magicPenBase", 6) + skill.get("magicPenPerLevel", 0.5) * lv)
	caster["magicPen"] = caster.get("magicPen", 0) + pen_gain
	var targets: Array = SlotHelpers.same_column_fighters(all_fighters, target)
	if targets.is_empty():
		targets = [target]
	# 总伤 = atk×1.5×(1 + turnDmgPct/100 × 回合数); 4 段平摊横排每敌 (PoC 4546)
	var turn_mult: float = 1.0 + skill.get("turnDmgPct", 10) / 100.0 * current_turn
	var total_base: float = caster.get("atk", 0) * skill.get("atkScale", 1.5) * turn_mult
	var n_hits: int = skill.get("hits", 4)
	var per_seg: float = total_base / float(n_hits)
	var effects: Array = []
	var any_crit_global: bool = false
	# 逐波飘字: PoC starWormhole wave-outer, 每波 sleep(120) (skill-handlers.ts:4562); 每敌各自 seg_list (delay=wave*0.12)
	var per_total: Dictionary = {}
	var per_crit: Dictionary = {}
	var per_seglist: Dictionary = {}
	for h in range(n_hits):
		for t in targets:
			if not t.get("alive", false):
				continue
			var ei: int = _find_idx(t, all_fighters)
			var hit: Dictionary = _multi_hit_target(caster, t, per_seg, "magic", 1, all_fighters, effects, true)   # PoC starWormhole applyRawDamage直落=必中 (skill-handlers.ts:4555)
			if hit["total"] > 0:
				per_total[ei] = int(per_total.get(ei, 0)) + int(hit["total"])
				if hit["any_crit"]: per_crit[ei] = true
				if not per_seglist.has(ei): per_seglist[ei] = []
				_seg_push(per_seglist[ei], hit["total"], "magic", hit["any_crit"], h * 0.12, t)
	for ei2 in per_total:
		if int(per_total[ei2]) > 0:
			var crit2: bool = bool(per_crit.get(ei2, false))
			var ed: Dictionary = {"target_idx": ei2, "value": int(per_total[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": crit2}
			if per_seglist.has(ei2) and (per_seglist[ei2] as Array).size() >= 2: ed["segments"] = per_seglist[ei2]
			effects.append(ed)
			if crit2:
				any_crit_global = true
			_star_charge(caster, int(per_total[ei2]))
	# 命中的敌人被击飞 → 标记靶子 (PoC api.knockup; e_dart 读); 锚/龟蛋免击飞
	for t in targets:
		_mark_knockup(t)
	_fire_star_passive(caster, target, all_fighters, effects)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 虫洞 → 魔穿+%d 横扫 %d 敌" % ["💥 " if any_crit_global else "", caster.get("name", "?"), pen_gain, targets.size()], "caster_idx": caster_idx}


# ─── 太空龟星能系统 (star, 1:1 PoC skill-handlers.ts:4218-4528) ───

## maxE = round(maxHp × maxChargePct/100)
static func _star_max_e(caster: Dictionary) -> int:
	var p = caster.get("passive", null)
	var mcp = p.get("maxChargePct", 40) if p is Dictionary else 40
	return roundi(caster.get("maxHp", 0) * mcp / 100.0)


## 充能: _starEnergy += round(shown × chargeRate/100), 钳 maxE
static func _star_charge(caster: Dictionary, shown: int) -> void:
	var p = caster.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "starEnergy" or shown <= 0:
		return
	var gain: int = roundi(shown * p.get("chargeRate", 62) / 100.0)
	caster["_starEnergy"] = mini(_star_max_e(caster), int(caster.get("_starEnergy", 0)) + gain)


## 余烬被动: 每次技能后对目标追加 round(储能 × passiveFirePct/100) 真伤, 命中后回充
static func _fire_star_passive(caster: Dictionary, target: Dictionary, all_fighters: Array, effects: Array) -> void:
	var p = caster.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "starEnergy":
		return
	if target == null or target.is_empty() or not target.get("alive", false):
		return
	var stored: int = int(caster.get("_starEnergy", 0))
	if stored <= 0:
		return
	var fire_dmg: int = roundi(stored * p.get("passiveFirePct", 30) / 100.0)
	if fire_dmg <= 0:
		return
	var r: Dictionary = Damage.apply_raw_damage(target, fire_dmg, "true")
	var shown: int = r["hpLoss"] + r["shieldAbs"]
	if shown > 0:
		effects.append({"target_idx": _find_idx(target, all_fighters), "value": shown, "kind": "damage", "dmg_type": "true", "is_crit": false})
		_star_charge(caster, shown)


## starBeam: 3 段 (atk×0.4 + 当前HP×6%) magic + 充能/段 + fireStarPassive
static func _star_beam(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 3)
	var total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC starBeam 每段 sleep(200) (skill-handlers.ts:4249); fireStar 真伤段 (_fire_star_passive) 已独立 effect
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false):
			break
		var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.4)) + roundi(target.get("hp", 0) * skill.get("currentHpPct", 6) / 100.0)
		var hit: Dictionary = _crit_hit_no_dodge(caster, target, base, "magic")
		if hit["dmg"] > 0:
			_seg_push(seg_list, hit["dmg"], "magic", hit["is_crit"], h * 0.2, target)
			total += hit["dmg"]
			if hit["is_crit"]:
				any_crit = true
			_star_charge(caster, hit["dmg"])
	var effects: Array = []
	if total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": total, "kind": "damage", "dmg_type": "magic", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	_fire_star_passive(caster, target, all_fighters, effects)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 星光射线 → %s" % ["💥 " if any_crit else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## starMeteor: 全敌 atk×1.0 magic + mrDown + 充能; 满能 burst(储能×burstPct% 真伤AOE) + fire
static func _star_meteor(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 1.0))
	var md = skill.get("mrDown", null)
	var per_enemy: Dictionary = {}
	var per_crit: Dictionary = {}
	var any_crit: bool = false
	for e in enemies:
		if not e.get("alive", false):
			continue
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, base, "magic")
		var ei: int = _find_idx(e, all_fighters)
		if hit["dmg"] > 0:
			per_enemy[ei] = int(per_enemy.get(ei, 0)) + int(hit["dmg"])
			per_crit[ei] = bool(hit["is_crit"])   # 每敌各自暴击色 (1:1 PoC per-enemy isCrit), 原用全局 any_crit → 一敌暴击全变蓝
			if hit["is_crit"]:
				any_crit = true
			_star_charge(caster, hit["dmg"])
		if md is Dictionary and e.get("alive", false):
			Buffs.add(e, "mrDown", md.get("pct", 20), int(md.get("turns", 3)), "overwrite")
			StatsRecalc.recalc(e)
	var effects: Array = []
	for ei2 in per_enemy:
		if int(per_enemy[ei2]) > 0:
			effects.append({"target_idx": ei2, "value": int(per_enemy[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": bool(per_crit.get(ei2, false))})
	# 满能 burst: 储能 × burstPct% 全敌真伤, 清能
	var max_e: int = _star_max_e(caster)
	if max_e > 0 and int(caster.get("_starEnergy", 0)) >= max_e:
		var pp = caster.get("passive", {})
		var burst: int = roundi(int(caster.get("_starEnergy", 0)) * (pp.get("burstPct", 100) if pp is Dictionary else 100) / 100.0)
		caster["_starEnergy"] = 0
		for e in enemies:
			if not e.get("alive", false):
				continue
			var r: Dictionary = Damage.apply_raw_damage(e, burst, "true")
			var sh: int = r["hpLoss"] + r["shieldAbs"]
			if sh > 0:
				effects.append({"target_idx": _find_idx(e, all_fighters), "value": sh, "kind": "damage", "dmg_type": "true", "is_crit": false})
	var first_alive = _first_alive_enemy(caster, all_fighters)
	if first_alive != null:
		_fire_star_passive(caster, first_alive, all_fighters, effects)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 流星暴击 → %d 敌" % ["💥 " if any_crit else "", caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## starBlackhole: 最后一敌→斩杀(HP%<=15)/1.8×atk; 否则 1.0×atk magic + 踢黑洞(stun+_isInBlackhole)
static func _star_blackhole(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	var is_last: bool = enemies.size() <= 1
	var atk_scale: float = skill.get("lastTargetAtkScale", 1.8) if is_last else skill.get("atkScale", 1.0)
	var exec: float = skill.get("executeThreshPct", 15)
	var effects: Array = []
	var t_idx := _find_idx(target, all_fighters)
	var actual: int = 0
	if is_last and target.get("maxHp", 0) > 0 and (float(target.get("hp", 0)) / float(target.get("maxHp", 1)) * 100.0) <= exec:
		# 黑洞斩杀
		var r: Dictionary = Damage.apply_raw_damage(target, int(target.get("hp", 0)) + 99999, "true")
		actual = r["hpLoss"] + r["shieldAbs"]
		if actual > 0:
			effects.append({"target_idx": t_idx, "value": actual, "kind": "damage", "dmg_type": "true", "is_crit": false})
	else:
		var hit: Dictionary = _crit_hit_no_dodge(caster, target, caster.get("atk", 0) * atk_scale, "magic", false)
		actual = hit["dmg"]
		if actual > 0:
			effects.append({"target_idx": t_idx, "value": actual, "kind": "damage", "dmg_type": "magic", "is_crit": false})
		if not is_last and target.get("alive", false):
			Buffs.add(target, "blackhole", 1, 2, "ignore")
			Buffs.add(target, "stun", 1, 2, "ignore")
			target["_isInBlackhole"] = true
			target["_stunUsed"] = false
			effects.append({"target_idx": t_idx, "kind": "passive", "label": "🌀 黑洞", "flash": "freeze"})   # 黑洞眩晕施加闪 (原只飘字)
	_star_charge(caster, actual)
	_fire_star_passive(caster, target, all_fighters, effects)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 黑洞 → %s" % [caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## starGravityWarp: 全敌 atk×0.8 magic + 充能; 满能换位(F0↔B2/F1↔B1/F2↔B0, 清能) + fire
static func _star_gravity_warp(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	if enemies.is_empty():
		return _empty_result(caster_idx)
	var base: float = roundi(caster.get("atk", 0) * skill.get("atkScale", 0.8))
	var per_enemy: Dictionary = {}
	for e in enemies:
		if not e.get("alive", false):
			continue
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, base, "magic", false)
		if hit["dmg"] > 0:
			var ei: int = _find_idx(e, all_fighters)
			per_enemy[ei] = int(per_enemy.get(ei, 0)) + int(hit["dmg"])
			_star_charge(caster, hit["dmg"])
	var effects: Array = []
	for ei2 in per_enemy:
		if int(per_enemy[ei2]) > 0:
			effects.append({"target_idx": ei2, "value": int(per_enemy[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": false})
	var relayout: bool = false
	var max_e: int = _star_max_e(caster)
	if max_e > 0 and int(caster.get("_starEnergy", 0)) >= max_e:
		# 换位: 敌方 F0↔B2 / F1↔B1 / F2↔B0
		var swaps := [["front-0", "back-2"], ["front-1", "back-1"], ["front-2", "back-0"]]
		for pair in swaps:
			var fa = _enemy_at_slot(caster, all_fighters, pair[0])
			var fb = _enemy_at_slot(caster, all_fighters, pair[1])
			if fa != null:
				fa["_slotKey"] = pair[1]
				fa["_position"] = "front" if (pair[1] as String).begins_with("front") else "back"
			if fb != null:
				fb["_slotKey"] = pair[0]
				fb["_position"] = "front" if (pair[0] as String).begins_with("front") else "back"
		caster["_starEnergy"] = 0
		relayout = true
		effects.append({"target_idx": caster_idx, "kind": "passive", "label": "🌀 扭曲空间"})
	var first_alive = _first_alive_enemy(caster, all_fighters)
	if first_alive != null:
		_fire_star_passive(caster, first_alive, all_fighters, effects)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "relayout": relayout, "log_text": "%s → 扭曲空间 → %d 敌" % [caster.get("name", "?"), enemies.size()], "caster_idx": caster_idx}


## 取敌方在指定 slot 的存活单位 (换位用)
static func _enemy_at_slot(caster: Dictionary, all_fighters: Array, slot_key: String):
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != caster.get("side", "") and f.get("_slotKey", "") == slot_key:
			return f
	return null


## 第一个存活敌 (fireStarPassive 收尾用)
static func _first_alive_enemy(caster: Dictionary, all_fighters: Array):
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != caster.get("side", ""):
			return f
	return null


# ─── 闪电龟电击层系统 (lightning, 1:1 PoC) ───

## 涌动加成: _lightningSurgeTurns>0 时被动电击真伤 ×(1+boost%)
static func _surge_boost(f: Dictionary) -> float:
	if int(f.get("_lightningSurgeTurns", 0)) > 0:
		return 1.0 + f.get("_lightningShockBoostPct", 50) / 100.0
	return 1.0


## 闪电龟攻击叠 1 层电击; 满 stackMax → 真伤引爆清零 (effects 追加引爆真伤)
static func _lightning_apply_shock(attacker: Dictionary, target: Dictionary, all_fighters: Array, effects: Array) -> void:
	var p = attacker.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "lightningStorm":
		return
	if target == null or target.is_empty() or not target.get("alive", false):
		return
	target["_shockStacks"] = int(target.get("_shockStacks", 0)) + 1
	if int(target["_shockStacks"]) >= int(p.get("stackMax", 8)):
		var det: int = roundi(attacker.get("atk", 0) * p.get("shockScale", 0.82) * _surge_boost(attacker))
		var r: Dictionary = Damage.apply_raw_damage(target, det, "true", true)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		target["_shockStacks"] = 0
		if shown > 0:
			# lightning:true → BattleScene 天降闪电 VFX (1:1 PoC passive-triggers 引爆前 fireLightningVfx); 原技能内引爆漏特效
			effects.append({"target_idx": _find_idx(target, all_fighters), "value": shown, "kind": "damage", "dmg_type": "true", "is_crit": false, "lightning": true})


## lightningBarrage: 20 次随机敌 magic atk×0.11 + 每次叠 1 层
static func _lightning_barrage(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var hits: int = skill.get("hits", 20)
	var scale: float = skill.get("arrowScale", 0.11)
	# 1:1 PoC lightning.js: 20 发, 每发随机敌, 逐发飘字 (350ms=280+70 一发). 改聚合→逐发segments.
	var seg_delay: float = float(skill.get("hitStaggerMs", 350)) / 1000.0
	var per_enemy_segs: Dictionary = {}
	var per_enemy_total: Dictionary = {}
	var any_crit: bool = false
	var effects: Array = []
	for h in range(hits):
		var enemies: Array = _alive_enemies(caster, all_fighters)
		if enemies.is_empty():
			break
		var e: Dictionary = enemies[randi() % enemies.size()]
		var ei: int = _find_idx(e, all_fighters)
		var hit: Dictionary = _one_hit(caster, e, caster.get("atk", 0) * scale, "magic", all_fighters)
		if not hit["dodged"] and int(hit["dmg"]) > 0:
			if not per_enemy_segs.has(ei):
				per_enemy_segs[ei] = []
				per_enemy_total[ei] = 0
			per_enemy_total[ei] = int(per_enemy_total[ei]) + int(hit["dmg"])
			(per_enemy_segs[ei] as Array).append({
				"value": int(hit["dmg"]), "dmg_type": "magic", "is_crit": bool(hit["is_crit"]),
				"delay": h * seg_delay,
				"hp_after": float(e.get("hp", 0)), "shield_after": float(e.get("shield", 0)),
			})
			if hit["is_crit"]:
				any_crit = true
		if e.get("alive", false):
			_lightning_apply_shock(caster, e, all_fighters, effects)
	for ei2 in per_enemy_segs:
		effects.append({"target_idx": ei2, "value": int(per_enemy_total[ei2]), "kind": "damage", "dmg_type": "magic", "is_crit": any_crit, "segments": per_enemy_segs[ei2]})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 雷暴 → %d 连击" % [caster.get("name", "?"), hits], "caster_idx": caster_idx}


## ninjaShuriken 手里剑: 单发 round(atk×atkScale). 暴击 → crit_total 的 (40+2×lv)% 转真伤(穿甲) + 余物理(吃减甲);
##   不暴击 → 全物理. 1:1 PoC skill-handlers.ts:1791. 暴击时红物理+白真伤同 hit 双段(白下移22).
static func _ninja_shuriken(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var t_idx := _find_idx(target, all_fighters)
	var base_dmg: int = roundi(caster.get("atk", 0) * skill.get("atkScale", 1.5))
	var is_crit: bool = Damage.roll_crit(caster.get("crit", 0.0))
	var effects: Array = []
	if is_crit:
		var crit_total: int = roundi(base_dmg * (1.5 + float(caster.get("_extraCritDmg", 0.0)) + float(caster.get("_extraCritDmgPerm", 0.0))))   # PoC 手里剑暴击用简化式(不走calc_crit_mult的溢出/_buffCritDmg, skill-handlers.ts:1729-1732)
		var lv: int = maxi(1, int(caster.get("_level", 1)))
		var true_raw: int = roundi(crit_total * minf(100.0, 40.0 + 2.0 * lv) / 100.0)
		var phys_raw: int = crit_total - true_raw
		var seg_list: Array = []
		var total: int = 0
		# 物理段 (吃减甲)
		var rp: Dictionary = Damage.apply_raw_damage(target, maxi(1, Damage.calc_damage(caster, target, phys_raw, "physical")), "physical")   # 1:1 PoC max(1,…) (skill-handlers.ts:1803) — 原floor0对高甲打0
		var phys_shown: int = rp["hpLoss"] + rp["shieldAbs"]
		if phys_shown > 0:
			total += phys_shown
			_seg_push(seg_list, phys_shown, "physical", true, 0.0, target)
		# 真伤段 (穿甲, 白字下移22)
		if true_raw > 0 and target.get("alive", false):
			var rt: Dictionary = Damage.apply_raw_damage(target, true_raw, "true")
			var true_shown: int = rt["hpLoss"] + rt["shieldAbs"]
			if true_shown > 0:
				total += true_shown
				_seg_push(seg_list, true_shown, "true", true, 0.0, target, 22.0)
		if total > 0:
			var ed: Dictionary = {"target_idx": t_idx, "value": total, "kind": "damage", "dmg_type": "physical", "is_crit": true, "hits": 1}
			if seg_list.size() >= 2: ed["segments"] = seg_list
			effects.append(ed)
	else:
		var rp2: Dictionary = Damage.apply_raw_damage(target, maxi(1, Damage.calc_damage(caster, target, base_dmg, "physical")), "physical")   # 1:1 PoC max(1,…)
		var ps2: int = rp2["hpLoss"] + rp2["shieldAbs"]
		if ps2 > 0:
			effects.append({"target_idx": t_idx, "value": ps2, "kind": "damage", "dmg_type": "physical", "is_crit": false})
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 手里剑 → %s" % ["💥 " if is_crit else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


## hunterBarrage 连珠箭: hits 发, 每发随机存活敌, 真伤 round(atk×arrowScale)×crit, 必中(无闪避), 逐发 segments.
##   1:1 PoC skill-handlers.ts:4960 alive[random] (原误走 _do_physical 单体=全砸一个).
static func _hunter_barrage(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var hits: int = skill.get("hits", 10)
	var base: float = roundi(caster.get("atk", 0) * skill.get("arrowScale", 0.24))
	var seg_delay: float = float(skill.get("hitStaggerMs", 120)) / 1000.0
	var per_enemy_segs: Dictionary = {}
	var per_enemy_total: Dictionary = {}
	var any_crit: bool = false
	for h in range(hits):
		var enemies: Array = _alive_enemies(caster, all_fighters)
		if enemies.is_empty():
			break
		var e: Dictionary = enemies[randi() % enemies.size()]
		var ei: int = _find_idx(e, all_fighters)
		var hit: Dictionary = _crit_hit_no_dodge(caster, e, base, "true")   # 真伤穿透 + 吃暴击 + 必中(PoC applyRawDamage 直接)
		if int(hit["dmg"]) > 0:
			if not per_enemy_segs.has(ei):
				per_enemy_segs[ei] = []
				per_enemy_total[ei] = 0
			per_enemy_total[ei] = int(per_enemy_total[ei]) + int(hit["dmg"])
			(per_enemy_segs[ei] as Array).append({
				"value": int(hit["dmg"]), "dmg_type": "true", "is_crit": bool(hit["is_crit"]),
				"delay": h * seg_delay,
				"hp_after": float(e.get("hp", 0)), "shield_after": float(e.get("shield", 0)),
			})
			if hit["is_crit"]:
				any_crit = true
	var effects: Array = []
	for ei2 in per_enemy_segs:
		var ed: Dictionary = {"target_idx": ei2, "value": int(per_enemy_total[ei2]), "kind": "damage", "dmg_type": "true", "is_crit": any_crit, "hits": (per_enemy_segs[ei2] as Array).size()}
		if (per_enemy_segs[ei2] as Array).size() >= 2:
			ed["segments"] = per_enemy_segs[ei2]
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 连珠箭 → %d 连射" % [caster.get("name", "?"), hits], "caster_idx": caster_idx}


## lightningSurgeBuff: 设涌动 buff + 立即电击 target (atk×0.82×1.5 真伤)
static func _lightning_surge_buff(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	caster["_lightningSurgeTurns"] = int(skill.get("surgeTurns", 2)) + 1   # 1:1 PoC +1 (turn-begin-1 → 持续surgeTurns回合, skill-handlers.ts:2983) — 原少1回合涌动窗口
	caster["_lightningShockBoostPct"] = skill.get("shockBoostPct", 50)
	var effects: Array = [{"target_idx": caster_idx, "kind": "passive", "label": "⚡ 涌动 %d 回合" % skill.get("surgeTurns", 2)}]
	if target != null and not target.is_empty() and target.get("alive", false):
		var p = caster.get("passive", {})
		var ss = p.get("shockScale", 0.82) if p is Dictionary else 0.82
		var dmg: int = roundi(caster.get("atk", 0) * ss * _surge_boost(caster))
		var r: Dictionary = Damage.apply_raw_damage(target, dmg, "true", true)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			effects.append({"target_idx": _find_idx(target, all_fighters), "value": shown, "kind": "damage", "dmg_type": "true", "is_crit": false})
		_lightning_apply_shock(caster, target, all_fighters, effects)
	return {"type": "damage", "effects": effects, "log_text": "%s → 涌动!" % caster.get("name", "?"), "caster_idx": caster_idx}


## lightningSurge: 全敌按其电击层数 真伤 (round(层×0.1×atk)) + 清层
static func _lightning_surge(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var enemies: Array = _alive_enemies(caster, all_fighters)
	var effects: Array = []
	var scale: float = skill.get("shockPerStackScale", 0.1)
	for e in enemies:
		var stacks: int = int(e.get("_shockStacks", 0))
		if stacks <= 0:
			continue
		var dmg: int = roundi(stacks * scale * caster.get("atk", 0))
		var r: Dictionary = Damage.apply_raw_damage(e, dmg, "true")
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			effects.append({"target_idx": _find_idx(e, all_fighters), "value": shown, "kind": "damage", "dmg_type": "true", "is_crit": false})
		if skill.get("shockConsume", true):
			e["_shockStacks"] = 0
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s → 感电 → 引爆电击层" % caster.get("name", "?"), "caster_idx": caster_idx}


## lightningShield: 自盾 atk×0.9 (counter-on-hit TODO: 需受击被动 hook)
static func _lightning_shield(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var shield_amt: int = roundi(caster.get("atk", 0) * skill.get("shieldScale", 0.9))
	var effects: Array = []
	if shield_amt > 0:
		shield_amt = Buffs.grant_shield(caster, shield_amt)
		caster["_lightningShieldCounter"] = skill.get("counterScale", 0.1)  # TODO: 受击反击
		effects.append({"target_idx": caster_idx, "value": shield_amt, "kind": "shield"})
	return {"type": "shield", "effects": effects, "log_text": "%s → 雷盾 → 自盾 +%d" % [caster.get("name", "?"), shield_amt], "caster_idx": caster_idx}


# ─── 赛博龟浮游炮/机甲系统 (cyber, 1:1 PoC) ───

## cyberDeploy: 部署 min(deployCount, maxD - 现有) 个浮游炮 (selfCast, 无伤害)
static func _cyber_deploy(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var drones: Array = caster.get("_drones", [])
	if not caster.has("_drones"):
		caster["_drones"] = drones
	var p = caster.get("passive", {})
	var max_d: int = 20 if caster.get("_cyberEnhanced", false) else (p.get("maxDrones", 10) if p is Dictionary else 10)
	var actual: int = mini(skill.get("deployCount", 3), max_d - drones.size())
	for _i in range(maxi(0, actual)):
		drones.append({"age": 0})
	var effects: Array = [{"target_idx": caster_idx, "kind": "passive", "label": "+%d🛰 浮游炮" % maxi(0, actual)}]
	return {"type": "shield", "effects": effects, "log_text": "%s → 部署 → +%d 浮游炮 (%d/%d)" % [caster.get("name", "?"), maxi(0, actual), drones.size(), max_d], "caster_idx": caster_idx}


# ─── 缩头龟召唤系统技能 (hiding, 1:1 PoC) ───

## hidingDefend: 自盾 round(maxHp×shieldHpPct%) (限时盾到期转生命由 BattleScene round-end 处理)
static func _hiding_defend(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	# 特殊限时盾 (独立池 _hidingShieldVal, 经 apply_raw_damage 吸收; 非普通 shield, 避免双重)
	var amt: int = roundi(caster.get("maxHp", 0) * skill.get("shieldHpPct", 20) / 100.0)
	caster["_hidingShieldVal"] = int(caster.get("_hidingShieldVal", 0)) + Buffs.fatigue_amt(caster, amt)
	caster["_hidingShieldTurns"] = skill.get("shieldDuration", 4)
	caster["_hidingShieldHealPct"] = skill.get("shieldHealPct", 20)
	var effects: Array = [{"target_idx": caster_idx, "kind": "passive", "label": "+%d🛡 缩壳(%d回合)" % [amt, skill.get("shieldDuration", 4)]}]
	return {"type": "shield", "effects": effects, "log_text": "%s → 缩壳防御 → 限时盾 +%d (%d回合)" % [caster.get("name", "?"), amt, skill.get("shieldDuration", 4)], "caster_idx": caster_idx}


## hidingCommand: 让 _summon 立即额外行动一次 (BattleScene 见 command_summon 标记)
static func _hiding_command(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var summon = caster.get("_summon", null)
	if not (summon is Dictionary) or not summon.get("alive", false):
		return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "随从已亡"}], "log_text": "%s → 指挥 (随从已亡)" % caster.get("name", "?"), "caster_idx": caster_idx}
	return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "📣 指挥!"}], "command_summon": true, "log_text": "%s → 指挥 随从!" % caster.get("name", "?"), "caster_idx": caster_idx}


## hidingBuffSummon: 给 _summon 4buff 2回合 (atk/def/mr +10%base, lifesteal+10, crit+20)
static func _hiding_buff_summon(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var summon = caster.get("_summon", null)
	if not (summon is Dictionary) or not summon.get("alive", false):
		return {"type": "shield", "effects": [{"target_idx": caster_idx, "kind": "passive", "label": "随从已亡"}], "log_text": "%s → 强化随从 (随从已亡)" % caster.get("name", "?"), "caster_idx": caster_idx}
	Buffs.add(summon, "atkUp", roundi(summon.get("baseAtk", 0) * 0.10), 2)
	Buffs.add(summon, "defUp", roundi(summon.get("baseDef", 0) * 0.10), 2)
	Buffs.add(summon, "mrUp", roundi(summon.get("baseMr", summon.get("baseDef", 0)) * 0.10), 2)
	Buffs.add(summon, "lifesteal", 10, 2)
	Buffs.add(summon, "critUp", 20, 2)
	StatsRecalc.recalc(summon)
	var si := _find_idx(summon, all_fighters)
	var effects: Array = [{"target_idx": si if si >= 0 else caster_idx, "kind": "passive", "label": "💪 强化随从"}]
	return {"type": "shield", "effects": effects, "log_text": "%s → 强化随从!" % caster.get("name", "?"), "caster_idx": caster_idx}


## cyberSwarmShield: 全友永久护盾 round(atk × (0.6 + perDronePct/100 × droneCount))
static func _cyber_swarm_shield(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	var drone_count: int = (caster.get("_drones", []) as Array).size()
	var per_pct: float = skill.get("shieldPerDroneEnhanced", 10) if caster.get("_cyberEnhanced", false) else skill.get("shieldPerDronePct", 15)
	var total_scale: float = skill.get("shieldAtkScale", 0.6) + (per_pct / 100.0) * drone_count
	var shield_amt: int = roundi(roundi(caster.get("atk", 0) * total_scale) * Rules.shield_mult())   # 铁壁之日 ×1.3 (原漏)
	var effects: Array = []
	for f in all_fighters:
		if f.get("side", "") != caster.get("side", "") or not f.get("alive", false):
			continue
		var sh_f := Buffs.grant_shield(f, shield_amt)
		effects.append({"target_idx": _find_idx(f, all_fighters), "value": sh_f, "kind": "shield"})
	return {"type": "shield", "effects": effects, "log_text": "%s → 浮游联防 → 全友 +%d 护盾" % [caster.get("name", "?"), shield_amt], "caster_idx": caster_idx}


## lightningStrike: 主目标 5段magic atk×0.23 + 每段25%随机溅射
static func _lightning_strike(caster: Dictionary, target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	var caster_idx := _find_idx(caster, all_fighters)
	if target == null or target.is_empty() or not target.get("alive", false):
		return _empty_result(caster_idx)
	var hits: int = skill.get("hits", 5)
	var per_hit: float = caster.get("atk", 0) * skill.get("atkScale", 1.15) / float(hits)
	var splash_pct: float = skill.get("splashPct", 25)
	var effects: Array = []
	var main_total: int = 0
	var any_crit: bool = false
	# 逐段飘字: PoC lightningStrike 主目标段间 sleep(600)+sleep(100)=700ms (skill-handlers.ts:2901-2904), magic 蓝.
	#   溅射打随机次目标 (每段不同), 保留为各自独立 effect, 不入主 seg_list.
	var seg_list: Array = []
	for h in range(hits):
		if not target.get("alive", false):
			break
		var hit: Dictionary = _one_hit(caster, target, per_hit, "magic", all_fighters)
		if hit["dodged"]:
			for de in hit["dodge_effects"]:
				effects.append(de)
		else:
			_seg_push(seg_list, hit["dmg"], "magic", hit["is_crit"], h * 0.7, target)
			main_total += hit["dmg"]
			if hit["is_crit"]:
				any_crit = true
		if target.get("alive", false):
			_lightning_apply_shock(caster, target, all_fighters, effects)   # 每段叠 1 层电击
		# 25% 随机溅射 (排除 target)
		var others: Array = []
		for e in _alive_enemies(caster, all_fighters):
			if e != target:
				others.append(e)
		if not others.is_empty():
			var sec: Dictionary = others[randi() % others.size()]
			var sp: Dictionary = _one_hit(caster, sec, per_hit * splash_pct / 100.0, "magic", all_fighters)
			if not sp["dodged"] and sp["dmg"] > 0:
				effects.append({"target_idx": _find_idx(sec, all_fighters), "value": sp["dmg"], "kind": "damage", "dmg_type": "magic", "is_crit": sp["is_crit"]})
			if not sp["dodged"] and sec.get("alive", false):
				_lightning_apply_shock(caster, sec, all_fighters, effects)   # 溅射也叠次目标1层电击 (1:1 PoC 溅射经dealMagic自动叠层; 原漏=满8层引爆慢)
	if main_total > 0:
		var ed: Dictionary = {"target_idx": _find_idx(target, all_fighters), "value": main_total, "kind": "damage", "dmg_type": "magic", "is_crit": any_crit}
		if seg_list.size() >= 2: ed["segments"] = seg_list
		ed["hits"] = maxi(1, seg_list.size())
		effects.append(ed)
	if effects.is_empty():
		return _empty_result(caster_idx)
	return {"type": "damage", "effects": effects, "log_text": "%s%s → 闪电打击 → %s" % ["💥 " if any_crit else "", caster.get("name", "?"), target.get("name", "?")], "caster_idx": caster_idx}


# ─── 治疗 ──────────────────────────────────────────────────────

static func _do_heal(caster: Dictionary, in_target: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	# 目标选择 (1:1 PoC heal:5781): 传入 target 是同侧友军则用它, 否则自己 (不自选最低血)
	var caster_idx := _find_idx(caster, all_fighters)
	var target: Dictionary = in_target if (in_target != null and not in_target.is_empty() and in_target.get("side", "") == caster.get("side", "")) else caster
	var target_idx: int = _find_idx(target, all_fighters)
	if target_idx < 0:
		return _empty_result(caster_idx)
	var hot = skill.get("hot", null)
	var has_hot: bool = hot is Dictionary and int((hot as Dictionary).get("turns", 0)) > 0
	var effects: Array = []
	var actual_heal: int = 0
	# 即时治疗 (1:1 PoC heal:5786): 仅当【无 hot 且显式给了 atkScale】才即时回 round(atk×atkScale).
	#   磐石/朗姆酒(纯 buff/hot, 无 atkScale) → 不回血 (修旧版兜底偷回10%maxHp 未描述治疗).
	if not has_hot and skill.has("atkScale"):
		var amt: int = roundi(caster.get("atk", 0) * float(skill.get("atkScale", 0)))
		if amt > 0:
			actual_heal = _heal_to(target, amt)
	elif float(skill.get("healPct", 0)) > 0 or float(skill.get("healHpPct", 0)) > 0 or int(skill.get("healAmt", 0)) > 0:
		var amt2: int = _calc_heal_amount(caster, target, skill)
		if amt2 > 0:
			actual_heal = _heal_to(target, amt2)
	if actual_heal > 0:
		effects.append({"target_idx": target_idx, "value": actual_heal, "kind": "heal"})

	# HoT 持续回血 buff (1:1 PoC heal:5793-5801)
	if has_hot and target.get("alive", false):
		var per_turn: int = roundi(target.get("maxHp", 0) * float((hot as Dictionary).get("pctMaxHp", 0)) / 100.0) \
			if (hot as Dictionary).has("pctMaxHp") else roundi(float((hot as Dictionary).get("hpPerTurn", 0)))
		if per_turn > 0:
			var tb: Array = target.get("buffs", [])
			tb.append({"type": "hot", "value": per_turn, "duration": int((hot as Dictionary).get("turns", 0)) + 1})
			target["buffs"] = tb

	# 护甲/魔抗加固 buff (1:1 PoC heal:5803-5824) — 之前整段缺失!
	var buffed := false
	var da = skill.get("defUpAtkPct", null)   # 朗姆酒: 护甲 += atk×pct%
	if da is Dictionary and float((da as Dictionary).get("pct", 0)) > 0:
		var g: int = roundi(caster.get("atk", 0) * float((da as Dictionary).get("pct", 0)) / 100.0)
		if g > 0:
			Buffs.add(target, "defUp", g, int((da as Dictionary).get("turns", 3)) + 1); buffed = true
	var dp = skill.get("defUpPct", null)      # 磐石: 护甲 += caster.baseDef×pct%
	if dp is Dictionary and float((dp as Dictionary).get("pct", 0)) > 0:
		var g2: int = roundi(float(caster.get("baseDef", caster.get("def", 0))) * float((dp as Dictionary).get("pct", 0)) / 100.0)
		if g2 > 0:
			Buffs.add(target, "defUp", g2, int((dp as Dictionary).get("turns", 3)) + 1); buffed = true
	var mp = skill.get("mrUpPct", null)        # 磐石: 魔抗 += caster.baseMr×pct%
	if mp is Dictionary and float((mp as Dictionary).get("pct", 0)) > 0:
		var g3: int = roundi(float(caster.get("baseMr", caster.get("mr", 0))) * float((mp as Dictionary).get("pct", 0)) / 100.0)
		if g3 > 0:
			Buffs.add(target, "mrUp", g3, int((mp as Dictionary).get("turns", 3)) + 1); buffed = true
	if buffed:
		StatsRecalc.recalc(target)

	if effects.is_empty() and not has_hot and not buffed:
		return _empty_result(caster_idx)
	var log_text := "%s → %s → %s%s" % [
		caster.get("name", "?"), skill.get("name", "?"), target.get("name", "?"),
		("  +%d HP" % actual_heal) if actual_heal > 0 else "  加固",
	]
	return {"type": "heal", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


static func _calc_heal_amount(caster: Dictionary, target: Dictionary, skill: Dictionary) -> int:
	# healAmt 平面值; healPct 治疗者 maxHp 的 %; healHpPct 目标 maxHp 的 %
	# 简化逻辑: healPct 优先, 然后 healHpPct, 最后 healAmt
	var flat: int = skill.get("healAmt", 0)
	var pct: float = skill.get("healPct", 0)
	var hp_pct: float = skill.get("healHpPct", 0)
	if pct > 0:
		return roundi(caster.get("maxHp", 0) * pct / 100.0) + flat
	if hp_pct > 0:
		return roundi(target.get("maxHp", 0) * hp_pct / 100.0) + flat
	if flat > 0:
		return flat
	# 都没字段, 用治疗者 maxHp 10% 兜底
	return roundi(caster.get("maxHp", 0) * 0.10)


# ─── 护盾 ──────────────────────────────────────────────────────

static func _do_shield(caster: Dictionary, all_fighters: Array, skill: Dictionary) -> Dictionary:
	# 目标:
	#   selfCast → 自己 (优先)
	#   aoeAlly → 全体存活友军
	#   默认 → 自己
	var caster_idx := _find_idx(caster, all_fighters)
	var shield_amt: int = _calc_shield_amount(caster, skill)
	if shield_amt <= 0:
		return _empty_result(caster_idx)

	var target_indices: Array[int] = []
	if skill.get("selfCast", false):
		target_indices.append(caster_idx)
	elif skill.get("aoeAlly", false):
		for i in range(all_fighters.size()):
			var f: Dictionary = all_fighters[i]
			if f["side"] == caster["side"] and f["alive"]:
				target_indices.append(i)
	else:
		target_indices.append(caster_idx)

	# 部分 shield 技能也带 heal 字段 (糖果龟 焦糖铠), 一并处理
	var heal_bonus_amt: int = 0
	if skill.get("healHpPct", 0) > 0:
		heal_bonus_amt = roundi(caster.get("maxHp", 0) * skill["healHpPct"] / 100.0)

	var effects: Array = []
	for idx in target_indices:
		var t: Dictionary = all_fighters[idx]
		var sh_t := Buffs.grant_shield(t, shield_amt)
		effects.append({
			"target_idx": idx,
			"value": sh_t,
			"kind": "shield",
		})
		# 附带回血给【每个】护盾目标 (PoC shield:1206 全友吃 heal, 非仅自己)
		if heal_bonus_amt > 0:
			var actual: int = _heal_to(t, heal_bonus_amt)
			if actual > 0:
				effects.append({"target_idx": idx, "value": actual, "kind": "heal"})

	var target_text: String
	if target_indices.size() == 1:
		target_text = all_fighters[target_indices[0]]["name"]
	else:
		target_text = "全队 %d 只" % target_indices.size()
	var log_text := "%s → %s → %s  +%d 盾" % [
		caster.get("name", "?"),
		skill.get("name", "?"),
		target_text,
		shield_amt,
	]
	return {"type": "shield", "effects": effects, "log_text": log_text, "caster_idx": caster_idx}


static func _calc_shield_amount(caster: Dictionary, skill: Dictionary) -> int:
	# shieldFlat + ATK × shieldAtkScale + maxHp × shieldHpPct/100
	# 兜底: 若全无字段, 用 ATK × 0.5
	var flat: int = skill.get("shieldFlat", 0)
	var atk_scale: float = skill.get("shieldAtkScale", 0)
	var hp_pct: float = skill.get("shieldHpPct", 0)
	if flat == 0 and atk_scale == 0 and hp_pct == 0:
		atk_scale = 0.5
	var atk_v: float = caster.get("atk", 0)
	var max_hp: float = caster.get("maxHp", 0)
	return roundi((flat + roundi(atk_v * atk_scale) + roundi(max_hp * hp_pct / 100.0)) * Rules.shield_mult())   # 铁壁之日 ×1.3 (原 _do_shield 漏, 与其它盾一致)


# ─── 工具 ──────────────────────────────────────────────────────

static func _find_idx(fighter: Dictionary, all_fighters: Array) -> int:
	for i in range(all_fighters.size()):
		if all_fighters[i] == fighter:
			return i
	return -1


## 击飞标记 (PoC api.knockup → 设 _knockedUpThisTurn, e_dart 侧回合末读). 统一收口免控守卫:
##   017不沉之锚 _p2AnchorImmune 免击飞 / 龟蛋 _eggImmune 免控制(含击飞) → 不标记.
static func _mark_knockup(target: Dictionary) -> void:
	if not target.get("alive", false):
		return
	if target.get("_p2AnchorImmune", false) or target.get("_eggImmune", false):
		return
	target["_knockedUpThisTurn"] = true


## 闪避判定 (1:1 PoC rollDodge:297) — 命中前调, 返 {dodged: bool, effects: Array}
## dodge 值 = dodge buff value + _extraDodge; roll < val/100 → 闪避
## 闪避时: miss 飘字 + e_ghost 闪避盾 (20×件数) + dodgeCounter 反击
static func _roll_dodge(target: Dictionary, attacker: Dictionary, all_fighters: Array) -> Dictionary:
	# 二阶段 瞄准镜 054: 攻击者伤害【不被闪避】(_cannotBeDodged) → 直接命中
	if attacker != null and attacker.get("_cannotBeDodged", false):
		return {"dodged": false, "effects": []}
	var dodge_buff = Buffs.find(target, "dodge")
	var dodge_val: float = 0.0
	if dodge_buff != null:
		dodge_val += float(dodge_buff.get("value", 0))
	dodge_val += float(target.get("_extraDodge", 0))
	if dodge_val <= 0 or randf() >= dodge_val / 100.0:
		return {"dodged": false, "effects": []}

	var effects: Array = []
	var t_idx := _find_idx(target, all_fighters)
	effects.append({"target_idx": t_idx, "value": 0, "kind": "miss"})

	# e_ghost 幽灵墨鱼: 闪避时 +20×件数 永久护盾
	if target.get("_equipGhostSquid", false):
		var equipped: Array = target.get("_equipped_ids", [])
		var ghost_count: int = 0
		for eq in equipped:
			if eq == "e_ghost":
				ghost_count += 1
		if ghost_count > 0:
			var shield_gain: int = 20 * ghost_count
			shield_gain = Buffs.grant_shield(target, shield_gain)
			effects.append({"target_idx": t_idx, "value": shield_gain, "kind": "shield"})

	# 二阶段 幽灵墨鱼 046: 闪避时给【永久护盾】(30/50/120 按星, apply_stats 设 _p2GhostShield)
	var p2gs: int = int(target.get("_p2GhostShield", 0))
	if p2gs > 0:
		var sg2: int = Buffs.grant_shield(target, p2gs)
		# 墨汁烟雾闪避 + 盾光 VFX 标记 (墨色烟雾粒子 + _play_shield_glow; 本身是 shield effect)。
		effects.append({"target_idx": t_idx, "value": sg2, "kind": "shield", "vfx": "inkdodge"})

	# dodgeCounter 闪避反击 (starWarp)
	var dc = Buffs.find(target, "dodgeCounter")
	if dc != null and attacker.get("alive", false):
		var c_dmg: int = int(dc.get("value", 0))
		var dt: String = dc.get("dmgType", "magic")
		var r: Dictionary = Damage.apply_raw_damage(attacker, c_dmg, dt)
		var shown: int = r["hpLoss"] + r["shieldAbs"]
		if shown > 0:
			var a_idx := _find_idx(attacker, all_fighters)
			effects.append({"target_idx": a_idx, "value": shown, "kind": "damage", "dmg_type": dt})

	# 灵物[召唤] 触手追击: 闪避方己侧每个触手 +1 本回合追击次数 (拍击时 cap 3 消费, 规格#553)。
	for tf in all_fighters:
		if tf is Dictionary and tf.get("_isTentacle", false) and tf.get("alive", false) \
				and str(tf.get("side", "")) == str(target.get("side", "")):
			tf["_tentacleDodgeChase"] = int(tf.get("_tentacleDodgeChase", 0)) + 1

	return {"dodged": true, "effects": effects}


## 全部存活敌人 (aoe 用)
static func _alive_enemies(caster: Dictionary, all_fighters: Array) -> Array:
	var out: Array = []
	for f in all_fighters:
		if f.get("side", "") != caster.get("side", "") and f.get("alive", false):
			out.append(f)
	return out


# 选择器全部迁到 SlotHelpers (1:1 PoC slot-helpers.ts):
#   横排(同 col) = SlotHelpers.same_column_fighters  ← rockShockwave/cyberBeam/shellErode/starWormhole
#   相邻         = SlotHelpers.adjacent_fighters     ← shellStrike 溅射
#   身后(同col)  = SlotHelpers.fighter_behind        ← ninjaImpact


static func _pick_lowest_hp_ally(caster: Dictionary, all_fighters: Array) -> int:
	var lowest: float = INF
	var pick: int = -1
	for i in range(all_fighters.size()):
		var f: Dictionary = all_fighters[i]
		if f["side"] != caster["side"] or not f["alive"]:
			continue
		var hp_v: float = f["hp"]
		if hp_v < lowest:
			lowest = hp_v
			pick = i
	return pick


static func _empty_result(caster_idx: int) -> Dictionary:
	return {"type": "none", "effects": [], "log_text": "", "caster_idx": caster_idx}


# ─── AI 选技能 (port 自 PoC ai.js 简化版) ──────────────────────

## 给一个 caster, 从其可用技能里选最合适的: 濒死优先 heal, 无盾优先 shield, 否则攻击
## 返回: {skill_idx: int, target_idx: int} 或 null
## 资源: AI 是否放得起 (龟能 energyCost / 熔岩龟怒气 rageCost; 都够才 true)
static func _ai_can_afford(f: Dictionary, skill: Dictionary) -> bool:
	if int(f.get("_maxEnergy", 0)) > 0 and int(f.get("_energy", 0)) < int(skill.get("energyCost", 0)):
		return false
	var rc := int(skill.get("rageCost", 0))   # 熔岩龟怒气
	if rc > 0 and int(f.get("_lavaRage", 0)) < rc:
		return false
	return true


## "大招"信号 = max(龟能消耗, 怒气消耗) — CD 取消后, 高消耗=强技能 (AI 偏好)
static func _cost_signal(skill: Dictionary) -> int:
	return maxi(int(skill.get("energyCost", 0)), int(skill.get("rageCost", 0)))


static func ai_pick(caster: Dictionary, all_fighters: Array) -> Variant:
	if not caster["alive"]:
		return null

	var ready_skills: Array = []  # [{idx, skill}]
	var skills: Array = caster.get("skills", [])
	for i in range(skills.size()):
		var s: Dictionary = skills[i]
		# 龟能: 只把放得起的算进可选 (放不起的过滤掉 → AI 自然退而求其次放便宜的; 基础0消耗永远在)
		if int(s.get("cdLeft", 0)) == 0 and _ai_can_afford(caster, s):
			ready_skills.append({"idx": i, "skill": s})
	if ready_skills.is_empty():
		return null

	# 熔岩龟 AI: 熔岩形态怒气接近变身阈值(>=65%)时, 攒着不花(只用免费技能, 普攻继续攒怒气)→ 冲满100变火山形态.
	#   变身后(volcanoSkills)走CD不受此限. = "现在花怒气 vs 攒着变身大招"的取舍, AI 倾向攒大招.
	var lpd = caster.get("passive")
	if lpd is Dictionary and str(lpd.get("type", "")) == "lavaRage" and not caster.get("_lavaTransformed", false):
		var lrmax: int = int(lpd.get("rageMax", 100))
		if int(caster.get("_lavaRage", 0)) >= int(lrmax * 0.65):
			var free_only: Array = ready_skills.filter(func(rs): return int(rs["skill"].get("rageCost", 0)) == 0)
			if not free_only.is_empty():
				ready_skills = free_only

	# 存活敌我 (ally 含自身)
	var allies: Array = []
	var has_enemy := false
	for f in all_fighters:
		if not f.get("alive", false):
			continue
		if f["side"] == caster["side"]:
			allies.append(f)
		else:
			has_enemy = true
	if not has_enemy:
		return null   # 没敌人, 不出招

	# 难度阈值 (normal 默认, hard=0.35) — PoC BattleScene.ts:2613
	var hp_thresh := 0.4
	# 1) heal: 任一队友 hp/maxHp < 阈值 → 治最低血比例队友 (PoC 2617-2621)
	for rs in ready_skills:
		if rs["skill"].get("type", "") == "heal":
			var need: Array = allies.filter(func(a): return float(a["hp"]) / float(a["maxHp"]) < hp_thresh)
			if not need.is_empty():
				need.sort_custom(func(a, b): return float(a["hp"]) / float(a["maxHp"]) < float(b["hp"]) / float(b["maxHp"]))
				return {"skill_idx": rs["idx"], "target_idx": _find_idx(need[0], all_fighters)}
			break
	# 2) shield: 任一队友 shield < 30 → 给首个存活队友 (PoC 2623-2627)
	for rs in ready_skills:
		if rs["skill"].get("type", "") == "shield":
			if allies.any(func(a): return int(a.get("shield", 0)) < 30):
				return {"skill_idx": rs["idx"], "target_idx": _find_idx(allies[0], all_fighters)}
			break
	# 2b) isAlly 增益技 (angelBless 等: type 非 heal/shield 但 handler 给友方盾/甲抗) → 选护盾最少友军
	#     修 BUG: 原落入输出技分支 → _pick_enemy_target → 天使龟给【敌方】加盾
	for _rsA in ready_skills:
		if _rsA["skill"].get("isAlly", false):
			if allies.any(func(a): return int(a.get("shield", 0)) < 30):
				var _na: Array = allies.duplicate()
				_na.sort_custom(func(a, b): return int(a.get("shield", 0)) < int(b.get("shield", 0)))
				return {"skill_idx": _rsA["idx"], "target_idx": _find_idx(_na[0], all_fighters)}
			break

	# 3) 输出: 偏好高 CD(ult), 65% 选 ult 组随机 / 35% 全输出技能随机 (PoC 2628-2642)
	var dmg_skills: Array = ready_skills.filter(func(rs):
		var t: String = rs["skill"].get("type", "physical")
		return t != "heal" and t != "shield" and not rs["skill"].get("isAlly", false)
	)
	var chosen: Dictionary
	if dmg_skills.is_empty():
		chosen = ready_skills[0]   # 没输出技能, 走第 1 个 ready 技能
	else:
		# CD 已全取消 → 用消耗(龟能/怒气)当"大招"信号 (高消耗=强技能); 无资源宠物全0=随机
		dmg_skills.sort_custom(func(a, b): return _cost_signal(a["skill"]) > _cost_signal(b["skill"]))
		var top_cd: int = _cost_signal(dmg_skills[0]["skill"])
		var ult_group: Array = dmg_skills.filter(func(x): return _cost_signal(x["skill"]) == top_cd)
		if randf() < 0.65:
			chosen = ult_group[randi() % ult_group.size()]
		else:
			chosen = dmg_skills[randi() % dmg_skills.size()]

	# 星能龟 pet-specific 覆盖 (PoC 2646-2692): meteor/warp 需满星才有意义
	var sp_passive = caster.get("passive", null)
	if sp_passive is Dictionary and sp_passive.get("type", "") == "starEnergy" and not dmg_skills.is_empty():
		var max_e: int = _star_max_e(caster)
		var cur_e: int = int(caster.get("_starEnergy", 0))
		var ct: String = chosen["skill"].get("type", "")
		if ct == "starMeteor" and cur_e < max_e:
			var o1: Array = dmg_skills.filter(func(x): return x["skill"].get("type", "") != "starMeteor")
			if not o1.is_empty():
				chosen = o1[0]   # dmg_skills 已 cd 降序
		elif ct == "starGravityWarp" and cur_e < max_e:
			var o2: Array = dmg_skills.filter(func(x): return x["skill"].get("type", "") != "starGravityWarp")
			if not o2.is_empty():
				chosen = o2[0]
		# 满星: 强制流星暴发 (若就绪)
		if cur_e >= max_e and max_e > 0:
			for rs in dmg_skills:
				if rs["skill"].get("type", "") == "starMeteor":
					chosen = rs
					break

	# pet-specific 技能可用条件 (PoC AI 2659-2705): 选中的技能条件不满足 → 换其他
	var cht: String = chosen["skill"].get("type", "")
	# bubbleBurst: 需 bubbleStore > 0
	if cht == "bubbleBurst" and int(caster.get("bubbleStore", 0)) <= 0:
		var o := ready_skills.filter(func(u): return u["skill"].get("type", "") != "bubbleBurst")
		if not o.is_empty(): chosen = o[0]; cht = chosen["skill"].get("type", "")
	# hidingCommand/hidingBuffSummon: 需随从存活
	if cht == "hidingCommand" or cht == "hidingBuffSummon":
		var sm = caster.get("_summon", null)
		if not (sm is Dictionary and sm.get("alive", false)):
			var o := ready_skills.filter(func(u): var x = u["skill"].get("type", ""); return x != "hidingCommand" and x != "hidingBuffSummon")
			if not o.is_empty(): chosen = o[0]; cht = chosen["skill"].get("type", "")
	# phoenixPurify: 队友需有可净化 debuff
	if cht == "phoenixPurify":
		var purifiable := ["atkDown", "defDown", "mrDown", "healReduce", "poison", "bleed", "burn", "curse", "chilled", "stun"]
		var has_deb := false
		for a in allies:
			for b in a.get("buffs", []):
				if b is Dictionary and b.get("type", "") in purifiable:
					has_deb = true; break
			if has_deb: break
		if not has_deb:
			var o := ready_skills.filter(func(u): return u["skill"].get("type", "") != "phoenixPurify")
			if not o.is_empty(): chosen = o[0]
	# fortuneGold 招财龟: 简化 3 阶段 coins/HP 经济 AI (PoC 2693-2705)
	var fg_passive = caster.get("passive", null)
	if fg_passive is Dictionary and fg_passive.get("type", "") == "fortuneGold":
		var coins: int = int(caster.get("_goldCoins", 0))
		var hp_pct: float = float(caster.get("hp", 0)) / float(caster.get("maxHp", 1))
		var fg: Dictionary = {}   # type → ready_skill 项
		for u in ready_skills:
			fg[u["skill"].get("type", "")] = u
		if fg.has("fortuneAllIn") and (coins >= 35 or (hp_pct < 0.25 and coins >= 12)):
			chosen = fg["fortuneAllIn"]
		elif fg.has("fortuneDice") and hp_pct < 0.55:
			chosen = fg["fortuneDice"]
		elif fg.has("fortuneGainCoins") and coins < 18:
			chosen = fg["fortuneGainCoins"]
		elif fg.has("fortuneStrike"):
			chosen = fg["fortuneStrike"]

	# 目标按该技能的 ignoreRow 选 (竹叶/忍者背刺越排)
	var ignore_row: bool = chosen["skill"].get("ignoreRow", false)
	if chosen["skill"].get("isAlly", false):   # 修: isAlly技作为唯一ready技被选中 → 仍给友军
		var _at: Dictionary = caster
		for _a in allies:
			if _a != caster:
				_at = _a
				break
		return {"skill_idx": chosen["idx"], "target_idx": _find_idx(_at, all_fighters)}
	return {"skill_idx": chosen["idx"], "target_idx": _pick_enemy_target(caster, all_fighters, ignore_row)}


# PoC 单体选目标 (AI 视角, 1:1 BattleScene.ts:2714-2736):
#   排除 黑洞/缩头随从/隐身/_untargetable → taunt 优先 → 非 ignoreRow 前排守门 → 绝对最低 HP
static func _pick_enemy_target(caster: Dictionary, all_fighters: Array, ignore_row: bool) -> int:
	var pool: Array = []
	for f in all_fighters:
		if f["side"] == caster["side"] or not f["alive"]:
			continue
		if f.get("_isInBlackhole", false) or f.get("_isSummon", false) or f.get("_untargetable", false):
			continue
		if Buffs.has(f, "stealth"):
			continue
		pool.append(f)
	# 兜底: 全潜行/只剩随从 → 放开 stealth/_isSummon (黑洞/_untargetable 仍排) — PoC :2723
	if pool.is_empty():
		for f in all_fighters:
			if f["side"] == caster["side"] or not f["alive"]:
				continue
			if f.get("_isInBlackhole", false) or f.get("_untargetable", false):
				continue
			pool.append(f)
		if pool.is_empty():
			return -1
	# taunt 优先 (强制只打嘲讽者, 跳过前排守门)
	var taunters: Array = pool.filter(func(f): return Buffs.has(f, "taunt"))
	if not taunters.is_empty():
		pool = taunters
	elif not ignore_row:
		# 前排守门: 前排存活则只能选前排
		var front: Array = pool.filter(func(f): return String(f.get("_slotKey", "")).begins_with("front-"))
		if not front.is_empty():
			pool = front
	# 绝对最低 HP (PoC P20: sort a.hp - b.hp, 非比例)
	pool.sort_custom(func(a, b): return float(a["hp"]) < float(b["hp"]))
	return _find_idx(pool[0], all_fighters)


# ─── 回合末 CD 递减 ────────────────────────────────────────────

static func tick_cooldowns(all_fighters: Array) -> void:
	for f in all_fighters:
		if not f["alive"]:
			continue
		var skills: Array = f.get("skills", [])
		for s in skills:
			var cd_left: int = s.get("cdLeft", 0)
			if cd_left > 0:
				s["cdLeft"] = cd_left - 1
