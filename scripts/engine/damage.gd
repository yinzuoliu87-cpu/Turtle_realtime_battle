class_name Damage extends RefCounted

## Damage — 战斗伤害公式 (从 Phaser PoC src/engine/damage.ts 翻译)
##
## 纯静态函数, 不持有状态, 不接 Scene/Node。给 Battle 系统用。
##
## ⚠️ W3 移植阶段范围 (核心公式 + 简版 applyRawDamage):
##   - calcEffArmor / calcEffMr / calcEffDef ✓
##   - calcDmgMult ✓
##   - calcDamage (基础版, 不含 ocho/synergy/basicTurtle/bonusDmgAbove60/fear 加成)
##   - rollCrit / calcCritMult ✓
##   - applyRawDamage (简版: 护盾→血. 不含 anemone/aura/bubble/lava/hiding 特殊盾,
##     不含 physImmune/dmgReduce/rockLayer/diamondStructure/crystalResonance 等被动减伤,
##     不含 markedDmg / FPGA增伤 / 海葵母 / inkLink / hunterMark execute)
##
## 后续 W5-W8 移植 skill/equipment 时按 type 补齐。

const DEF_CONSTANT: int = 40   # 跟 src/data/pets.ts DEF_CONSTANT 同

## inkLink 传递可见化钩子: BattleScene 注入 (partner, shown, dmg_type, owner) → 飘字+战绩 (1:1 PoC setInkTransferHook)
static var ink_transfer_hook: Callable = Callable()


# ─── 有效护甲 / 魔抗 / 通用减伤 ───────────────────────────────────

## 物理: 有效护甲 = def×(1-armorPenPct) - armorPen
static func calc_eff_armor(atk: Dictionary, tgt: Dictionary) -> float:
	return tgt.get("def", 0) * (1.0 - atk.get("armorPenPct", 0.0)) - atk.get("armorPen", 0)


## 魔法: 有效魔抗
static func calc_eff_mr(atk: Dictionary, tgt: Dictionary) -> float:
	return tgt.get("mr", 0) * (1.0 - atk.get("magicPenPct", 0.0)) - atk.get("magicPen", 0)


## dmgType: "physical" / "magic" / "true"
static func calc_eff_def(atk: Dictionary, tgt: Dictionary, dmg_type: String) -> float:
	if dmg_type == "magic":
		return calc_eff_mr(atk, tgt)
	if dmg_type == "true":
		return 0.0
	return calc_eff_armor(atk, tgt)


## 减伤倍率: 正防御=减伤(<1), 负防御=增伤(>1, 上限~2)
##   mult = 1 - def/(def+K)   if def >= 0
##   mult = 1 + |def|/(|def|+K)  if def < 0
static func calc_dmg_mult(eff_def: float) -> float:
	if eff_def >= 0:
		return 1.0 - eff_def / (eff_def + DEF_CONSTANT)
	var abs_def := absf(eff_def)
	return 1.0 + abs_def / (abs_def + DEF_CONSTANT)


# ─── 伤害计算 (预演, 不应用) ──────────────────────────────────────

## 给定 attacker + target + base + dmgType → 最终伤害 (整数)
## W3 简版: 不含 ocho/synergy/basicTurtle/bonusDmgAbove60/fear 加成。
## 后续 W6-W7 翻 passive/skill 时再补这些 if-else 分支。
static func calc_damage(atk: Dictionary, tgt: Dictionary, base: float, dmg_type: String) -> int:
	# 章鱼爪 e_octo: 攻击者带 _equipBackrowBonus + 目标在后排 → base 先 ×(1+bonus%) 再走护甲 (PoC damage.ts:51-52)
	var backrow: float = atk.get("_equipBackrowBonus", 0)
	if backrow > 0 and tgt.get("_position", "") == "back":
		base *= (1.0 + backrow / 100.0)
	var eff_def := calc_eff_def(atk, tgt, dmg_type)
	var final_dmg := base * calc_dmg_mult(eff_def)
	# 刺杀羁绊 tier3: 【目标】<50% HP 时 +10% 伤害 (PoC damage.ts:57-58 — 是目标不是攻击者!)
	if atk.get("_synergyAssassinExecute", false) and tgt.get("maxHp", 0) > 0 \
			and float(tgt.get("hp", 0)) / float(tgt.get("maxHp", 1)) < 0.5:
		final_dmg *= 1.10
	# 小龟 basicTurtle: 对不同稀有度目标增伤 bonusMap[tgt.rarity]% (PoC damage.ts:66-71)
	var apv = atk.get("passive", null)
	if apv is Dictionary and apv.get("type", "") == "basicTurtle":
		var bm = apv.get("bonusMap", null)
		if bm is Dictionary:
			var bpct: float = bm.get(tgt.get("rarity", ""), 0)
			if bpct > 0:
				final_dmg *= (1.0 + bpct / 100.0)
	# 寒冰 frostAura: 攻击者被动 frostAura + 目标 id 在 bonusTargets → +bonusDmgPct% (1:1 PoC passiveDmgMult; 原 Godot 漏 → 冰系对熔岩/凤凰不增伤)
	if apv is Dictionary and apv.get("type", "") == "frostAura":
		var bt = apv.get("bonusTargets", null)
		if bt is Array and (bt as Array).has(tgt.get("id", "")):
			final_dmg *= (1.0 + float(apv.get("bonusDmgPct", 0)) / 100.0)
	# 恐惧 fear: 攻击者被恐惧 → 对该来源的 物理/魔法 伤害 -value% (真伤不减) (PoC damage.ts:72-76)
	if dmg_type != "true":
		var fear = Buffs.find(atk, "fear")
		if fear != null:
			final_dmg *= (1.0 - float(fear.get("value", 0)) / 100.0)
	# 装备本回合增伤: 放大器/FPGA-10 共用 _dmgBonusThisTurnPct, 乘所有出伤 (PoC engine.js:233)
	var dmg_bonus: float = atk.get("_dmgBonusThisTurnPct", 0)
	if dmg_bonus > 0:
		final_dmg *= (1.0 + dmg_bonus / 100.0)
	# 决胜局 怒气 (overtime rage): 30 回合后每层 +30% 伤害 (BattleScene._apply_overtime_escalation)
	var rage_stacks: int = atk.get("_overtimeRage", 0)
	if rage_stacks > 0:
		final_dmg *= (1.0 + 0.30 * rage_stacks)
	# 永恒 buff (二阶段双路, 每场第30回合后, 仅统领): 每层 造成+50%(atk端) & 受到+50%(tgt端), 线性
	var atk_eternal: int = atk.get("_eternalStack", 0)
	if atk_eternal > 0:
		final_dmg *= (1.0 + 0.5 * atk_eternal)
	var tgt_eternal: int = tgt.get("_eternalStack", 0)
	if tgt_eternal > 0:
		final_dmg *= (1.0 + 0.5 * tgt_eternal)
	return roundi(maxf(0.0, final_dmg))


# ─── 暴击 ───────────────────────────────────────────────────────

## 暴击伤害倍率 (爆击溢出: crit>1 时多余转加伤)
##   critMult = 1.5 + extraCritDmg(临时) + extraCritDmgPerm(永久) + buffCritDmg + overflow×overflowMult
##   overflowMult 默认 1.5, 可被 passive 覆盖
static func calc_crit_mult(attacker: Dictionary) -> float:
	var crit_v: float = attacker.get("crit", 0.0)
	var extra_temp: float = attacker.get("_extraCritDmg", 0.0)
	var extra_perm: float = attacker.get("_extraCritDmgPerm", 0.0)
	var buff_crit: float = attacker.get("_buffCritDmg", 0.0)
	var overflow_crit := maxf(0.0, crit_v - 1.0)
	# passive 可能是 null (没被动龟) 或 Dictionary, 不能直接 var passive: Dictionary = .get(),
	# 因 .get() 在键存在但值为 null 时返回 null → 赋给 Dictionary 类型变量会爆 "Nil to Dictionary"。
	var passive_raw = attacker.get("passive")
	var overflow_mult: float = 1.5
	if passive_raw is Dictionary:
		overflow_mult = (passive_raw as Dictionary).get("overflowMult", 1.5)
	return 1.5 + extra_temp + extra_perm + buff_crit + overflow_crit * overflow_mult


# ─── 应用伤害到 target (改写 fighter 状态) ────────────────────────

## 把 final_dmg 落到 target 身上, 走护盾 → HP 顺序, 触发死亡。
##
## W3 简版: 标准护盾(shield) + HP, 真伤(true) 也走护盾(同 JS), pierce 跳过护盾。
##
## 返回 {hpLoss: int, shieldAbs: int}
## 后续 W6-W8 补:
##   - bubble/aura/lava/hiding 特殊盾池
##   - markedDmg / FPGA增伤 / physImmune / dmgReduce / rockLayer / diamondStructure /
##     crystalResonance / undeadLock / anemoneShield / hunterMark execute / inkLink transfer
##   - bubbleStore / auraEnergy / lavaRage / twoHeadResilience 受伤累积
static func apply_raw_damage(tgt: Dictionary, final_dmg: int, dmg_type: String = "physical",
		is_pierce: bool = false, skip_link: bool = false) -> Dictionary:
	if final_dmg <= 0:
		return {"hpLoss": 0, "shieldAbs": 0}

	# 守护贝母 021: 链接友军受伤 → pct 部分转移给守护者 (先分流, 守护者自己再走减伤; 守护者无链不递归)
	var _gl = tgt.get("_p2GuardLink", null)
	if _gl is Dictionary:
		var _guard = _gl.get("to", null)
		if _guard is Dictionary and _guard.get("alive", false) and not is_same(_guard, tgt):
			var _gp: float = clampf(float(_gl.get("pct", 0.0)), 0.0, 0.9)
			var _moved: int = int(round(float(final_dmg) * _gp))
			if _moved > 0:
				apply_raw_damage(_guard, _moved, dmg_type, is_pierce)
				final_dmg = final_dmg - _moved

	# ── 减伤/吸收链 (1:1 PoC damage.ts:131-272, 顺序固定) ──
	# 完全免伤: _untargetable(训龟大师) / _isInBlackhole(黑洞)
	if tgt.get("_untargetable", false) or tgt.get("_isInBlackhole", false):
		return {"hpLoss": 0, "shieldAbs": 0}
	# markedDmg 必中标记: 所有伤害 +value% (含真伤)
	var mk = Buffs.find(tgt, "markedDmg")
	if mk != null and int(mk.get("value", 0)) > 0:
		final_dmg = roundi(final_dmg * (1.0 + mk.get("value", 0) / 100.0))
	# 深渊议会[腐蚀]学派: 每层使目标 +pct% 受伤 (含真伤, markedDmg 后)。满 5 层 → 30% 无视护盾(下方 corrode_pierce)。
	var corrode = Buffs.find(tgt, "corrode")
	var corrode_layers: int = int(corrode.get("value", 0)) if corrode != null else 0
	if corrode_layers > 0:
		final_dmg = roundi(final_dmg * (1.0 + corrode_layers * float(corrode.get("pct", 0.0))))
	# 极地小队 9档易碎: 被冻结/眩晕且带 _iceShatter 标记的敌人 受到的伤害 +25%
	if tgt.get("_iceShatter", false) and Buffs.is_stunned(tgt):
		final_dmg = roundi(final_dmg * 1.25)
	# 黑礁猎团: 被标记的猎物受到的伤害 +_huntDmgBoost% (15/25/40%; 只猎方攻它, 全局标记即等效)
	var hunt_b: float = float(tgt.get("_huntDmgBoost", 0.0))
	if hunt_b > 0.0:
		final_dmg = roundi(final_dmg * (1.0 + hunt_b))
	# 小龟壳 _turtleShellBlock: 非真伤 -flat
	if dmg_type != "true" and int(tgt.get("_turtleShellBlock", 0)) > 0 and final_dmg > 0:
		final_dmg = maxi(1, final_dmg - mini(int(tgt.get("_turtleShellBlock", 0)), final_dmg))
	# 二阶段 铁壁盾 016 _p2DmgReduce: 非真伤 每段 -flat (同 _turtleShellBlock 减伤链)
	if dmg_type != "true" and int(tgt.get("_p2DmgReduce", 0)) > 0 and final_dmg > 0:
		final_dmg = maxi(1, final_dmg - mini(int(tgt.get("_p2DmgReduce", 0)), final_dmg))
	# physImmune 虚化 (physical): ≥100% 全免, 否则部分减
	if dmg_type == "physical":
		var pi = Buffs.find(tgt, "physImmune")
		if pi != null:
			var rp: float = pi.get("value", 100)
			if rp >= 100:
				return {"hpLoss": 0, "shieldAbs": 0}
			final_dmg = maxi(1, roundi(final_dmg * (1.0 - rp / 100.0)))
	# dmgReduce buff (非真伤)
	if dmg_type != "true":
		var dr = Buffs.find(tgt, "dmgReduce")
		if dr != null and int(dr.get("value", 0)) > 0:
			final_dmg = maxi(0, roundi(final_dmg * (1.0 - dr.get("value", 0) / 100.0)))
	# 磐石岩层: 每层 1% 减伤 (cap 30%), 非真伤
	if dmg_type != "true" and final_dmg > 0:
		var rl: int = mini(30, int(tgt.get("_rockLayers", 0)))
		if rl > 0:
			final_dmg = maxi(1, roundi(final_dmg * (1.0 - rl / 100.0)))
	var dp = tgt.get("passive", null)
	# diamondStructure 固定减伤 (非真伤): def×defPct + mr×mrPct (强化 def20+mr10, 否则 def20)
	if dmg_type != "true" and final_dmg > 0 and dp is Dictionary and dp.get("type", "") == "diamondStructure":
		var enh: bool = tgt.get("_diamondEnhanced", false)
		var def_pct: float = 20 if enh else dp.get("flatReductionPct", 20)
		var mr_pct: float = 10 if enh else 0
		var flat: int = roundi(tgt.get("def", 0) * def_pct / 100.0) + roundi(tgt.get("mr", 0) * mr_pct / 100.0)
		if flat > 0:
			final_dmg = maxi(1, final_dmg - flat)
	# crystalResonance 法术额外减免 (magic)
	if dmg_type == "magic" and dp is Dictionary and dp.get("type", "") == "crystalResonance":
		var ab: float = dp.get("magicAbsorb", 0)
		if ab > 0:
			final_dmg = roundi(final_dmg * (1.0 - ab / 100.0))
	# undeadLockTurns: HP 不能 <1 (吃盾后锁血 1)
	var lock: int = int(tgt.get("_undeadLockTurns", 0))
	if lock > 0:
		var rem2: int = final_dmg
		var sh2: int = 0
		if int(tgt.get("shield", 0)) > 0:
			sh2 = mini(tgt.get("shield", 0), rem2); tgt["shield"] = tgt.get("shield", 0) - sh2; rem2 -= sh2
		var before2: int = tgt.get("hp", 0)
		tgt["hp"] = maxi(1, before2 - rem2)
		var hl2: int = before2 - int(tgt["hp"])
		_accumulate_on_damage(tgt, hl2, final_dmg)
		_apply_ink_link_transfer(tgt, hl2 + sh2, skip_link)
		return {"hpLoss": hl2, "shieldAbs": sh2}

	# ── 护盾顺序: bubble → aura → 熔岩盾 → 缩头盾 → 普通盾 (真伤也走, pierce 跳过) ──
	var goes_through_shield := (dmg_type == "true") or (not is_pierce)
	var remaining := final_dmg
	var shield_abs := 0
	# 深渊腐蚀满5层: 30% 伤害无视护盾, 直击 HP (无视护甲已在 calc 阶段处理) → 护盾最多吸 70%。
	#   corrode_pierce=0 时 max_shield=final_dmg, 与原逻辑完全一致(向后兼容)。
	var corrode_pierce: int = roundi(final_dmg * 0.30) if corrode_layers >= 5 else 0
	var max_shield: int = final_dmg - corrode_pierce
	if goes_through_shield:
		for pool in ["bubbleShieldVal", "_auraShield", "_lavaShieldVal", "_hidingShieldVal"]:
			if remaining <= 0 or shield_abs >= max_shield:
				break
			var pv: int = tgt.get(pool, 0)
			if pv > 0:
				var a: int = mini(mini(pv, remaining), max_shield - shield_abs)
				tgt[pool] = pv - a; remaining -= a; shield_abs += a
		var shield_val: int = tgt.get("shield", 0)
		if shield_val > 0 and remaining > 0 and shield_abs < max_shield:
			var sa: int = mini(mini(shield_val, remaining), max_shield - shield_abs)
			tgt["shield"] = shield_val - sa; remaining -= sa; shield_abs += sa

	# HP
	var hp_val: int = tgt.get("hp", 0)
	var hp_loss := mini(hp_val, remaining)
	tgt["hp"] = hp_val - hp_loss
	if tgt["hp"] <= 0:
		tgt["hp"] = 0
		tgt["alive"] = false

	# 猎人标记斩杀: 存活但 HP 跌破 mark.value% → 秒杀 (017不沉之锚 _p2AnchorImmune 免疫斩杀; 龟蛋 _eggImmune 免处决/斩杀)
	if tgt.get("alive", false) and int(tgt.get("hp", 0)) > 0 and not tgt.get("_p2AnchorImmune", false) and not tgt.get("_eggImmune", false):
		var hm = Buffs.find(tgt, "hunterMark")
		if hm != null and int(tgt.get("maxHp", 0)) > 0 \
				and (float(tgt.get("hp", 0)) / float(tgt.get("maxHp", 1)) * 100.0) <= float(hm.get("value", 0)):
			tgt["hp"] = 0; tgt["alive"] = false; tgt["_executedByMark"] = true

	_accumulate_on_damage(tgt, hp_loss, final_dmg)
	_apply_ink_link_transfer(tgt, hp_loss + shield_abs, skip_link)
	return {"hpLoss": hp_loss, "shieldAbs": shield_abs}


## inkLink 30% 分流 (1:1 PoC damage.ts:308-324): 挂 _inkLink 的 target 受伤后把 totalShown×transferPct% 分给 partner.
##   skip_link=true (递归内) 防 partner 回弹给 target. dmgType 走 link.dmgType (magic/true); true 则 pierce.
static func _apply_ink_link_transfer(tgt: Dictionary, total_shown: int, skip_link: bool) -> void:
	if skip_link or total_shown <= 0:
		return
	var link = tgt.get("_inkLink", null)
	if not (link is Dictionary):
		return
	var partner = link.get("partner", null)
	if not (partner is Dictionary) or not partner.get("alive", false):
		return
	var transfer_amt: int = roundi(float(total_shown) * float(link.get("transferPct", 0)) / 100.0)
	if transfer_amt <= 0:
		return
	var link_type: String = str(link.get("dmgType", "magic"))
	if link_type != "true":
		link_type = "magic"
	var tr: Dictionary = apply_raw_damage(partner, transfer_amt, link_type, link_type == "true", true)
	var t_shown: int = int(tr.get("hpLoss", 0)) + int(tr.get("shieldAbs", 0))
	if ink_transfer_hook.is_valid():
		ink_transfer_hook.call(partner, t_shown, link_type, link.get("owner", null))


## 受伤端被动累积 (中心扣血点统一: lavaRage / twoHeadResilience)
static func _accumulate_on_damage(tgt: Dictionary, hp_loss: int, final_dmg: int) -> void:
	# ── 受伤端被动累积 (PoC damage.ts:293-306, 用 target 自身被动, 中心扣血点确保 DoT/真伤也算) ──
	# 泡泡龟 bubbleStore: 受伤(hpLoss, 打盾不积) → 累积 bubbleStore round(hpLoss×pct%), cap maxHp。
	#   1:1 PoC damage.ts:283-286 存 acc.bubbleStore (爆破 bubbleBurst 消耗的资源) —— 非 bubbleShieldVal(那是独立护盾)。
	#   旧版误存 bubbleShieldVal → bubbleBurst 读 bubbleStore 恒 0 = 放不出/无效。
	if hp_loss > 0:
		var bp = tgt.get("passive", null)
		if bp is Dictionary and bp.get("type", "") == "bubbleStore":
			var stored: int = roundi(hp_loss * bp.get("pct", 100) / 100.0)
			if stored > 0:
				tgt["bubbleStore"] = mini(int(tgt.get("maxHp", 0)), int(tgt.get("bubbleStore", 0)) + stored)
	# 龟壳 auraAwaken 储能 (hpLoss, 打盾不积; 仅存活; cap=maxHp×energyMaxStorePct) — PoC damage.ts:288-292
	if hp_loss > 0 and tgt.get("alive", false):
		var ap = tgt.get("passive", null)
		if ap is Dictionary and ap.get("type", "") == "auraAwaken" and ap.get("energyStore", false):
			var cap: int = roundi(tgt.get("maxHp", 0) * ap.get("energyMaxStorePct", 0.5))
			tgt["_auraEnergy"] = mini(cap, int(tgt.get("_auraEnergy", 0)) + hp_loss)
	# 熔岩龟 lavaRage 受伤怒气 (hpLoss, 打盾不积; 变身中不累积)
	if hp_loss > 0:
		var tp = tgt.get("passive", null)
		if tp is Dictionary and tp.get("type", "") == "lavaRage" \
				and not tgt.get("_lavaSpent", false) and not tgt.get("_lavaTransformed", false):
			var rmax: int = tp.get("rageMax", 100)
			var nxt: int = mini(rmax, int(tgt.get("_lavaRage", 0)) + roundi(hp_loss * tp.get("rageTakenPct", 20) / 100.0))
			tgt["_lavaRage"] = nxt
			if nxt >= rmax:
				tgt["_lavaRageReady"] = true
	# 双头龟 twoHeadResilience 受击叠甲抗 (finalDmg>0, 每段 +1甲+1抗, cap 20)
	if final_dmg > 0 and tgt.get("_twoHeadResilience", false) and int(tgt.get("_twoHeadResStacks", 0)) < 20:
		tgt["_twoHeadResStacks"] = int(tgt.get("_twoHeadResStacks", 0)) + 1
		tgt["baseDef"] = tgt.get("baseDef", 0) + 1
		tgt["def"] = tgt.get("def", 0) + 1
		tgt["baseMr"] = tgt.get("baseMr", tgt.get("baseDef", 0)) + 1
		tgt["mr"] = tgt.get("mr", 0) + 1
