class_name EquipmentRuntime extends RefCounted

## EquipmentRuntime — 装备运行时, 1:1 移植 PoC src/data/equipment.ts apply() + passive-triggers
##
## 重写说明 (2026-05-30): 上一版本数值是我自己拍脑袋造的, 用户提醒 "记住我们是迁移 phaser"
## 后, 全部抠 PoC 真实数值。
##
## 各 hook 出处:
##   - on_attach: PoC src/data/equipment.ts 各 EquipmentDef.apply() 闭包
##   - on_hit: PoC src/engine/passive-triggers.ts (blade bleed / fire burn / ghost dodge 等)
##   - on_hit_as_target: PoC src/engine/equipment-runtime.ts (carapace / pearl 等)
##   - on_turn_begin: PoC BattleScene.processSideEnd / processComplexEquipEffects
##                    (大部分装备的 turn 触发是 SIDE-END 不是 turn-begin, 这里 round-end 触发)
##   - on_death: PoC BattleScene.processDeathPassives (conch 等, 暂留 stub)
##
## W7 v1.1 已正确实装的 (用 PoC 真实公式):
##   完全 1:1:
##     e_blade   +20 ATK, _equipBladeBleed=2 (onHit 施加 max(1, atk×0.15×count/4) 流血)
##     e_tooth   +8 ATK +5 armorPen +25% crit (纯属性)
##     e_piercer +8 ATK +6 armorPen +6 magicPen (纯属性)
##     e_carapace +60 HP, onHitAsTarget +1 def+1 mr cap 20 → 满层 +40 盾
##     e_pearl   +20 HP +4 def +4 mr, onHitAsTarget hp<50% 回 20%maxHp + 销毁
##     e_urchin  +50 HP, _equipReflect=10 (受击反弹 10% 真伤 — 收口在 BattleScene)
##     e_fire    +50 HP, _equipBurn=true (onHit 施加 20 灼烧, per cast 1 次)
##     e_jelly   +20 HP +5 def, _equipStun=25 (onHit 25% 概率眩晕1回合, 已接眩晕系统)
##     e_anemone +5 def +10 mr, _equipHot=8 (round-begin +8% maxHp HoT)
##     e_octo    +15 ATK, _equipBackrowBonus=20 (后排目标 +20% — 在 Damage.calc_damage 读)
##     e_star    +12% lifesteal, _equipStarOverflow=50 (溢出治疗 50% 转盾, 已接吸血块)
##     e_anemone HoT — 见 anemone
##     e_ripple  +100 HP +30% healAmp +3% allyHotPct (round-begin 全队 HoT)
##     e_hammer  +100 HP, _equipHammer++ (ATK = baseAtk + maxHp×4%×count, 在 recalc 算)
##
## 暂留 stub (复杂或需要 VFX, W7 v2 再做):
##   e_ghost (闪避 +15% + 闪避时 +20 盾) — 需要先实装 dodge buff
##   e_conch (死亡变小虫) — 召唤物系统未做
##   e_dragon_egg (3 回合喷火龙) — 飞行 VFX 需要
##   e_fpga / e_amplifier — 复杂 buff
##   e_dumbbell side-end +25 maxHp + 投掷 5% maxHp — TODO


# ─── on_attach (PoC apply() 1:1) ────────────────────────────────

static func on_attach(fighter: Dictionary, equip_id: String) -> void:
	match equip_id:
		"e_blade":
			# 海藻短刃: +20 ATK + 装记号 (onHit 时算流血层数)
			_add_atk(fighter, 20)
			fighter["_equipBladeBleed"] = 2     # 流血持续 2 回合 (combat.js)

		"e_carapace":
			# 珊瑚硬壳: +60 HP, 受击 +1 def/mr (cap 20/件, 满层 +40 盾)
			_add_max_hp(fighter, 60)
			fighter["_equipCarapaceGain"] = fighter.get("_equipCarapaceGain", 0)
			fighter["_equipCarapaceCap"] = fighter.get("_equipCarapaceCap", 0) + 20
			fighter["_equipCarapaceShieldGiven"] = false

		"e_pearl":
			# 生命珍珠: +20 HP +4 def/mr, hp<50% 触发回 20% maxHp + 销毁
			_add_max_hp(fighter, 20)
			_add_def(fighter, 4)
			_add_mr(fighter, 4)
			fighter["_equipPearl"] = true

		"e_tooth":
			# 锋利鲨齿: +8 ATK +5 护甲穿透 +25% 暴击
			_add_atk(fighter, 8)
			fighter["armorPen"] = fighter.get("armorPen", 0) + 5
			fighter["crit"] = fighter.get("crit", 0.0) + 0.25

		"e_piercer":
			# 双穿珊瑚刺: +8 ATK +6 护甲穿透 +6 魔法穿透
			_add_atk(fighter, 8)
			fighter["armorPen"] = fighter.get("armorPen", 0) + 6
			fighter["magicPen"] = fighter.get("magicPen", 0) + 6

		"e_hammer":
			# 重击锤: +100 HP, ATK = baseAtk + maxHp×4%×count (在 recalc 算)
			_add_max_hp(fighter, 100)
			fighter["_equipHammer"] = fighter.get("_equipHammer", 0) + 1
			# ATK 加成完全收口到 StatsRecalc (ATK += maxHp×4%×count). PoC equipment-runtime.ts:108 明确:
			# attach 期改 baseAtk 会被 recalc 抹掉/重复叠加+覆盖 atkUp/atkDown (用户报过"重击锤没正确施加攻击力").

		"e_urchin":
			# 荆棘海胆: +50 HP, +10% 反伤
			_add_max_hp(fighter, 50)
			fighter["_equipReflect"] = fighter.get("_equipReflect", 0) + 10

		"e_fire":
			# 灼热火珊瑚: +50 HP, _equipBurn=true (onHit 施加 20 灼烧, per cast 1 次)
			_add_max_hp(fighter, 50)
			fighter["_equipBurn"] = true

		"e_jelly":
			# 冰封水母: +20 HP +5 def, onHit 25% 概率眩晕 1 回合 (已接眩晕系统)
			_add_max_hp(fighter, 20)
			_add_def(fighter, 5)
			fighter["_equipStun"] = 25

		"e_anemone":
			# 治愈海葵: +5 def +10 mr, _equipHot=8 (回合开始 +8% maxHp HoT)
			_add_def(fighter, 5)
			_add_mr(fighter, 10)
			fighter["_equipHot"] = fighter.get("_equipHot", 0) + 8

		"e_octo":
			# 暗袭章鱼爪: +15 ATK, 对后排目标 +20% (Damage.calc_damage 读 _equipBackrowBonus)
			_add_atk(fighter, 15)
			fighter["_equipBackrowBonus"] = fighter.get("_equipBackrowBonus", 0) + 20

		"e_thunder_shell":
			# 雷鸣贝壳: +15 ATK, 自己回合结束电击 1 随机敌 round(ATK×1.0) 真伤 (PoC equipment.ts:181-184)
			_add_atk(fighter, 15)
			fighter["_equipThunderBell"] = int(fighter.get("_equipThunderBell", 0)) + 1

		"e_dragon_egg":
			# 龙蛋: +8 ATK +5 魔穿, 装备即得 3 层吐息 (PoC equipment.ts:154-158; turn1:3+1=4≥3触发)
			_add_atk(fighter, 8)
			fighter["magicPen"] = int(fighter.get("magicPen", 0)) + 5
			fighter["_equipDragonEgg"] = true
			fighter["_equipDragonEggStacks"] = 3

		"e_mini_crystal":
			# 迷你水晶球A: +20 HP +5 魔穿 +7 ATK, 回合末沿列射魔光 (PoC equipment.ts:166-169)
			_add_max_hp(fighter, 20)
			fighter["magicPen"] = int(fighter.get("magicPen", 0)) + 5
			_add_atk(fighter, 7)
			fighter["_equipMiniCrystal"] = true

		"e_mini_crystal_b":
			# 迷你水晶球B: +20 HP +3 魔穿 +7 ATK, 回合末旋转激光扫全敌 (PoC equipment.ts:173-177)
			_add_max_hp(fighter, 20)
			fighter["magicPen"] = int(fighter.get("magicPen", 0)) + 3
			_add_atk(fighter, 7)
			fighter["_equipMiniCrystalB"] = true

		"e_stun_baton":
			# 电棍: +20 HP +5 def +5 mr, 装备时 3 层电击 (PoC equipment.ts:384-388)
			_add_max_hp(fighter, 20)
			_add_def(fighter, 5)
			_add_mr(fighter, 5)
			fighter["_stunBatonStacks"] = 3

		"e_bamboo_leaf":
			# 竹叶: +50 HP + 1 次生长充能 (PoC equipment.ts:397-398)
			_add_max_hp(fighter, 50)
			fighter["_bambooLeafCharge"] = 1

		"e_lightning_staff":
			# 雷电法杖: +8 魔穿, 每件独立充能(push 0; 每段单体伤害充25/AOE12.5, 满100链式闪电) (PoC equipment.ts:408-411)
			fighter["magicPen"] = int(fighter.get("magicPen", 0)) + 8
			if not (fighter.get("_lightningStaffCharges", null) is Array):
				fighter["_lightningStaffCharges"] = []
			(fighter["_lightningStaffCharges"] as Array).append(0.0)

		"e_incubator":
			# 孵化器: +20 HP + 初始化孵化进度/临时等级 (PoC equipment.ts:373-376)
			_add_max_hp(fighter, 20)
			fighter["_incubatorProgress"] = 0
			fighter["_incubatorTempLevel"] = 0

		"e_star":
			# 生命偷取海星: +12% 生命偷取, 溢出治疗 50% 转盾 (已接吸血块)
			fighter["_lifestealPct"] = fighter.get("_lifestealPct", 0) + 12
			fighter["_equipStarOverflow"] = 50

		"e_ripple":
			# 潮汐涟漪: +100 HP, +30% 治疗/盾强度, 每回合全队 +3% 已损 HP HoT
			_add_max_hp(fighter, 100)
			fighter["_equipRippleHealAmp"] = fighter.get("_equipRippleHealAmp", 0) + 30
			fighter["_equipRippleAllyHotPct"] = fighter.get("_equipRippleAllyHotPct", 0) + 3

		"e_ghost":
			# 幽灵墨鱼: +20 HP +15% 闪避 (永久 dodge buff), 闪避时 +20 盾 (在 _roll_dodge)
			_add_max_hp(fighter, 20)
			Buffs.add(fighter, "dodge", 15, 999, "refresh")   # 永久装备闪避: refresh 防重复 attach 叠多条 999
			fighter["_equipGhostSquid"] = true

		"e_hourglass":
			# 沙漏: 携带者所有技能基础冷却永久 -1 (最低 0); 存原 cd 供未来卸装还原 (PoC equipment.ts:185)
			var skills: Array = fighter.get("skills", [])
			for s in skills:
				if not (s is Dictionary) or not (s.get("cd", null) is int or s.get("cd", null) is float):
					continue
				if not (s.get("_hourglassOrigCd", null) is int):
					s["_hourglassOrigCd"] = int(s.get("cd", 0))
				s["cd"] = maxi(0, int(s.get("cd", 0)) - 1)
			fighter["_equipHourglass"] = true

		"e_dumbbell":
			# 哑铃: +100 HP +3 def/mr; side-end 每回合 +25 maxHp + 扔哑铃 5%maxHp 物理 (PoC 197)
			_add_max_hp(fighter, 100); _add_def(fighter, 3); _add_mr(fighter, 3)
			fighter["_equipDumbbell"] = true
			fighter["_equipDumbbellGain"] = 0

		"e_candle":
			# 蜡烛: +10 ATK +50 HP; side-end 3阶段循环(熄灭/微弱疗/燃烧AOE) (PoC 218)
			_add_atk(fighter, 10); _add_max_hp(fighter, 50)
			fighter["_equipCandle"] = true
			fighter["_equipCandleStage"] = 0

		"e_revolver":
			# 左轮: +10 ATK +5 穿甲; 6发子弹, 敌死+1(cap6); side-end 射随机敌 40物理 (PoC 226)
			_add_atk(fighter, 10)
			fighter["armorPen"] = fighter.get("armorPen", 0) + 5
			fighter["_equipRevolver"] = true
			fighter["_equipRevolverBullets"] = 6

		"e_wave":
			# 海浪: +50 HP +10%盾/疗强度; side-end 每回合+1层, 满3横扫一排(友+20盾+2甲抗/敌20魔-2甲抗) (PoC 263)
			_add_max_hp(fighter, 50)
			fighter["_equipRippleHealAmp"] = fighter.get("_equipRippleHealAmp", 0) + 10
			fighter["_equipWave"] = true
			fighter["_equipWaveStacks"] = 0

		"e_amplifier":
			# 信号放大器: +50 HP; 每回合起手 16-24% 临时增伤 (PoC 212)
			_add_max_hp(fighter, 50)
			fighter["_equipAmplifier"] = true

		"e_fpga":
			# FPGA板: +50 HP; 每回合起手抽 2-bit 状态(00回血+甲抗/01攻+吸血/10增伤/11减伤) (PoC 206)
			_add_max_hp(fighter, 50)
			fighter["_equipFpga"] = true

		"e_dart":
			# 飞镖: +15 ATK; side-end 向所有带"靶子"(_knockedUpThisTurn)敌人射飞镖 50 物理 + 20 流血 (PoC equipment.ts:257)
			_add_atk(fighter, 15)
			fighter["_equipDart"] = true

		"e_doll":
			# 玩偶小熊: +5 ATK +30 HP; side-end 小熊攻击随机敌(前排优先) 30 物理 + 1 层大熊; 满 5 层召唤大熊 (PoC equipment.ts:248)
			_add_atk(fighter, 5)
			_add_max_hp(fighter, 30)
			fighter["_equipDoll"] = true
			fighter["_equipDollBigBearStacks"] = 0
			fighter["_equipDollSpawned"] = false

		"e_conch":
			# 复活海螺: +100 HP; 彻底阵亡时变形为小虫 (on_death 处理, PoC equipment.ts:138)
			_add_max_hp(fighter, 100)
			fighter["_equipConch"] = true

		"e_laser_blade":
			# 激光长刃: +15 ATK; 授予"横扫"技能 (对敌方一排各 0.7×ATK, 仅 1 名 1.4×ATK, 回血 80%) (PoC equipment.ts:234)
			_add_atk(fighter, 15)
			fighter["_equipLaserBlade"] = true
			var skills_arr: Array = fighter.get("skills", [])
			if skills_arr is Array:
				skills_arr.append({
					"name": "横扫", "type": "laserSweep", "hits": 1, "power": 0, "pierce": 0,
					"cd": 0, "cdLeft": 0, "dmgType": "physical", "_fromEquip": "e_laser_blade",
					"atkScale": 0.7, "soloScale": 1.4, "lifestealPct": 80,
					"brief": "对敌方一排 (F0/F1/F2 或 B0/B1/B2 整行) 各 0.7×ATK 物理; 只命中 1 名 1.4×ATK。回复造伤的 80%",
					"detail": "激光长刃横扫. 对目标所在前排/后排同时挥砍:\n· 多目标命中: 每个敌人 70%×攻击力 物理\n· 单目标命中 (只 1 名): 140%×攻击力 物理\n\n携带者回血 = 造成总伤害 × 80%.\n冷却 0 回合.",
				})
				fighter["skills"] = skills_arr


# ─── 消耗品 c_* apply (PoC equipment.ts:275-349 各 apply() 1:1) ──────────
##
## 拖拽消耗品到目标上使用 (target:'ally' 拖友方 / target:'enemy' 拖敌方扔出).
## 返 effects 数组供 caller 飘字: [{target_idx, value, kind, source/dmg_type/label}]
## 调用后由 caller 销毁消耗品 (从 bench/_equipped_ids 移除).
## helper applyHeal/recalc/renderStatusIcons (PoC) 对应 Godot: _consumable_heal (吃 healReduce) / StatsRecalc.recalc.
static func apply_consumable(fighter: Dictionary, equip_id: String, all_fighters: Array = []) -> Array:
	var effects: Array = []
	if fighter == null or fighter.is_empty():
		return effects
	var idx: int = _find_idx(fighter, all_fighters)
	match equip_id:
		"c_heal":
			# 治疗药水: 回复 (50 + 10% 目标 maxHp) 生命 (PoC equipment.ts:277)
			var amt: int = 50 + roundi(int(fighter.get("maxHp", 0)) * 0.10)
			var healed: int = _consumable_heal(fighter, amt)
			if healed > 0:
				effects.append({"target_idx": idx, "value": healed, "kind": "heal", "source": "💧 治疗药水"})

		"c_speed":
			# 加速药水: 目标所有技能当前剩余冷却 -1 (最低 0) (PoC equipment.ts:284)
			var skills: Array = fighter.get("skills", [])
			for s in skills:
				if s is Dictionary and (s.get("cdLeft", null) is int or s.get("cdLeft", null) is float):
					if int(s.get("cdLeft", 0)) > 0:
						s["cdLeft"] = maxi(0, int(s.get("cdLeft", 0)) - 1)
			effects.append({"target_idx": idx, "kind": "passive", "label": "⏩ 冷却 -1"})

		"c_bomb":
			# 炸弹: 60 物理 (不归属任何龟, 不触发吸血/on-hit, 仅按目标护甲减免) (PoC equipment.ts:293)
			# 1:1 PoC inline: 物理走 def 减免, shield 先吸再扣 HP
			var base_dmg: int = 60
			var def_v: float = fighter.get("def", 0)
			var mult: float = (1.0 - def_v / (def_v + 100.0)) if def_v >= 0 else (1.0 + abs(def_v) / (abs(def_v) + 100.0))
			var final_dmg: int = maxi(1, roundi(base_dmg * mult))
			var remaining: int = final_dmg
			var shield_v: int = int(fighter.get("shield", 0))
			if shield_v > 0:
				var absorbed: int = mini(shield_v, remaining)
				fighter["shield"] = shield_v - absorbed
				remaining -= absorbed
			if remaining > 0:
				fighter["hp"] = maxi(0, int(fighter.get("hp", 0)) - remaining)
				if int(fighter.get("hp", 0)) <= 0:
					fighter["alive"] = false
			effects.append({"target_idx": idx, "value": final_dmg, "kind": "damage", "dmg_type": "physical", "source": "💣 炸弹"})

		"c_rage":
			# 怒火药水: +25% 攻击 buff 3 回合 (折 flat = baseAtk×25%) (PoC equipment.ts:316)
			var atk_base: float = fighter.get("baseAtk", fighter.get("atk", 0))
			Buffs.add(fighter, "atkUp", roundi(atk_base * 25.0 / 100.0), 3)
			StatsRecalc.recalc(fighter)
			effects.append({"target_idx": idx, "kind": "passive", "label": "🔥 攻击+25%"})

		"c_emergency":
			# 应急护盾: +80 护盾 (PoC equipment.ts:324)
			var emer_sh: int = Buffs.grant_shield(fighter, 80)
			effects.append({"target_idx": idx, "value": emer_sh, "kind": "shield", "source": "⛑ 应急护盾"})

		"c_firstaid":
			# 急救包: 回复 15% 目标 maxHp (PoC equipment.ts:330)
			var amt2: int = roundi(int(fighter.get("maxHp", 0)) * 0.15)
			var healed2: int = _consumable_heal(fighter, amt2)
			if healed2 > 0:
				effects.append({"target_idx": idx, "value": healed2, "kind": "heal", "source": "🌿 急救包"})

		"c_cleanse":
			# 净化: 清除所有负面状态 (DoT + stat debuff + 标记/束缚) (PoC equipment.ts:337)
			var buffs: Array = fighter.get("buffs", [])
			if buffs is Array and not buffs.is_empty():
				var debuff_types := {
					"dot": true, "curse": true, "burn": true, "poison": true, "bleed": true,
					"chilled": true, "atkDown": true, "defDown": true, "mrDown": true,
					"healReduce": true, "markedDmg": true, "bubbleBind": true,
				}
				var kept: Array = []
				for b in buffs:
					if b is Dictionary and debuff_types.has(b.get("type", "")):
						continue
					kept.append(b)
				fighter["buffs"] = kept
				StatsRecalc.recalc(fighter)   # 削减类清掉后属性还原
			effects.append({"target_idx": idx, "kind": "passive", "label": "✨ 净化"})

		"c_mark":
			# 必中标记: 标记 2 回合, 期间受到所有伤害 +20% (PoC equipment.ts:345)
			Buffs.add(fighter, "markedDmg", 20, 2)
			effects.append({"target_idx": idx, "kind": "passive", "label": "🎯 易伤+20%"})

	return effects


## 消耗品治疗 (吃 healReduce, 1:1 PoC applyHeal): 返回实际回血量
static func _consumable_heal(f: Dictionary, amount: int) -> int:
	if amount <= 0 or not f.get("alive", false):
		return 0
	var hr = Buffs.find(f, "healReduce")
	if hr != null and int(hr.get("value", 0)) > 0:
		amount = roundi(amount * (1.0 - hr.get("value", 0) / 100.0))
	# 潮汐涟漪装备: 受治疗 +_equipRippleHealAmp% (PoC equipment.ts:22)
	var ripple: float = float(f.get("_equipRippleHealAmp", 0))
	if ripple > 0:
		amount = roundi(amount * (1.0 + ripple / 100.0))
	# 守护羁绊: 受治疗 +_synergyGuardAmp (PoC equipment.ts:23)
	var guard: float = float(f.get("_synergyGuardAmp", 0.0))
	if guard > 0.0:
		amount = roundi(amount * (1.0 + guard))
	amount = Buffs.fatigue_amt(f, amount)   # 决胜局疲惫: 治疗 ×0.5
	var before: int = int(f.get("hp", 0))
	f["hp"] = mini(int(f.get("maxHp", 0)), before + amount)
	return int(f["hp"]) - before


## 孵化器进度 (1:1 PoC _incubatorProgress:562): +delta; 满100升临时等级(上限3, 每级+5%基础属性直加base). 返升级数。
static func _incubator_add(carrier: Dictionary, delta: int) -> int:
	if not carrier.has("_incubatorProgress") or delta <= 0:
		return 0
	carrier["_incubatorProgress"] = int(carrier.get("_incubatorProgress", 0)) + delta
	var gained: int = 0
	while int(carrier["_incubatorProgress"]) >= 100 and int(carrier.get("_incubatorTempLevel", 0)) < 3:
		carrier["_incubatorProgress"] = int(carrier["_incubatorProgress"]) - 100
		carrier["_incubatorTempLevel"] = int(carrier.get("_incubatorTempLevel", 0)) + 1
		gained += 1
		var atk_b: int = roundi(int(carrier.get("baseAtk", 0)) * 0.05)
		var def_b: int = roundi(int(carrier.get("baseDef", 0)) * 0.05)
		var mr_b: int = roundi(int(carrier.get("baseMr", carrier.get("baseDef", 0))) * 0.05)
		var hp_b: int = roundi(int(carrier.get("maxHp", 0)) * 0.05)
		carrier["baseAtk"] = int(carrier.get("baseAtk", 0)) + atk_b
		carrier["atk"] = carrier["baseAtk"]
		carrier["baseDef"] = int(carrier.get("baseDef", 0)) + def_b
		carrier["def"] = carrier["baseDef"]
		carrier["baseMr"] = int(carrier.get("baseMr", carrier.get("baseDef", 0))) + mr_b
		carrier["mr"] = carrier["baseMr"]
		carrier["maxHp"] = int(carrier.get("maxHp", 0)) + hp_b
		carrier["hp"] = int(carrier.get("hp", 0)) + hp_b
	return gained


## 连锁闪电: 从 attacker 朝 ≤4 个【不同】随机存活敌各 20 魔法 (1:1 PoC fireLightningChain:3055)
static func _lightning_chain(attacker: Dictionary, all_fighters: Array) -> Array:
	var fx: Array = []
	var pool: Array = []
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != attacker.get("side", ""):
			pool.append(f)
	for _j in range(4):
		if pool.is_empty():
			break
		var k: int = randi() % pool.size()
		var t: Dictionary = pool[k]
		pool.remove_at(k)
		var d: int = maxi(1, roundi(20.0 * Damage.calc_dmg_mult(Damage.calc_eff_mr(attacker, t))))
		var r: Dictionary = Damage.apply_raw_damage(t, d, "magic")
		var s: int = int(r["hpLoss"]) + int(r["shieldAbs"])
		if s > 0:
			fx.append({"target_idx": _idx(t, all_fighters), "value": s, "kind": "damage", "dmg_type": "magic", "label": "⚡链"})
	return fx


# ─── on_hit (attacker 角度, 攻击落地后) ────────────────────────
##
## 返 effects 数组让 caller 飘字 (跟 SkillHandlers.execute 同 shape)
##   每段命中后调一次. dmg = 该段已落 (含 shield_abs 不算) 的 HP 损失。
static func on_hit(attacker: Dictionary, target: Dictionary, dmg: int,
		equip_id: String, all_fighters: Array, is_first_hit_this_skill: bool = true) -> Array:
	var effects: Array = []
	if dmg <= 0 or not target.get("alive", false):
		return effects

	match equip_id:
		"e_blade":
			# PoC passive-triggers.ts:417-424 (6n bladeBleed):
			# stacks = max(1, round(atk × 0.15 × bladeCount / 4))
			# bladeCount = attacker._equipBladeBleed (实际是回合数 2, 用作 count 占位)
			var blade_count: int = attacker.get("_equipBladeBleed", 0)
			if blade_count > 0 and target.get("alive", false):
				var atk_v: float = attacker.get("atk", 0)
				var stacks: int = maxi(1, roundi(atk_v * 0.15 * blade_count / 4.0))
				Dot.apply_stacks(target, "bleed", stacks)
				# 注: 流血不立即扣血, 在回合末 Dot.tick 才扣. 这里不飘字, 仅施加层数。

		"e_fire":
			# PoC passive-triggers.ts:430-432 (6o equipBurn):
			# 携带者每次施法 per-cast 1 次施加 20 灼烧 (用 _equipFireStackedThisCast flag)
			# 这里简化: is_first_hit_this_skill=true 时施加, 多段攻击只第 1 段触发
			if is_first_hit_this_skill and attacker.get("_equipBurn", false) and target.get("alive", false):
				Dot.apply_stacks(target, "burn", 20)

		"e_lightning_staff":
				# 雷电法杖 (PoC BattleScene:3041): 每件充能 +25(AOE +12.5); 满100→链式闪电(20魔跳≤4不同敌)+保留溢出
				var charges = attacker.get("_lightningStaffCharges", null)
				if charges is Array and not (charges as Array).is_empty():
					var inc: float = 12.5 if attacker.get("_castIsAoe", false) else 25.0
					var fires: int = 0
					for i in range((charges as Array).size()):
						charges[i] = float(charges[i]) + inc
						while float(charges[i]) >= 100.0:
							charges[i] = float(charges[i]) - 100.0
							fires += 1
					for _fc in range(fires):
						effects.append_array(_lightning_chain(attacker, all_fighters))

		"e_incubator":
			# 孵化器: 造成伤害 ×0.1 进度 (PoC passive-triggers.ts:411-412)
			_incubator_add(attacker, roundi(dmg * 0.1))

	return effects


# ─── on_hit_as_target (target 角度, 自己被打后) ────────────────

static func on_hit_as_target(owner: Dictionary, attacker: Dictionary,
		dmg: int, equip_id: String, all_fighters: Array) -> Array:
	var effects: Array = []
	if dmg <= 0:
		return effects

	match equip_id:
		"e_incubator":
			# 孵化器: 承受伤害 ×0.1 进度 (PoC passive-triggers.ts:413-414)
			_incubator_add(owner, roundi(dmg * 0.1))

		"e_carapace":
			# PoC equipment-runtime.ts:42-61: 每次受击 +1 def/+1 mr (不论件数), 累积 cap
			var cap: int = owner.get("_equipCarapaceCap", 20)
			var cur: int = owner.get("_equipCarapaceGain", 0)
			if cur < cap:
				var after: int = mini(cap, cur + 1)
				var inc: int = after - cur
				owner["_equipCarapaceGain"] = after
				owner["baseDef"] = owner.get("baseDef", 0) + inc
				owner["def"] = owner["baseDef"]
				owner["baseMr"] = owner.get("baseMr", owner.get("def", 0)) + inc
				owner["mr"] = owner["baseMr"]
				# 满 cap → 一次性给盾
				if after >= cap and not owner.get("_equipCarapaceShieldGiven", false):
					owner["_equipCarapaceShieldGiven"] = true
					var pieces: int = maxi(1, roundi(float(cap) / 20.0))
					var bonus: int = Buffs.grant_shield(owner, 40 * pieces)
					var owner_idx := _find_idx(owner, all_fighters)
					effects.append({
						"target_idx": owner_idx,
						"value": bonus,
						"kind": "shield",
						"source": "🐢 硬化满层",
					})

		"e_pearl":
			# PoC equipment-runtime.ts:64-77: 被攻击者 hp<50% 时触发一次, 回 20% maxHp + 销毁
			# 注: PoC 用 target.hp/maxHp 判 (target=被打的人就是 owner), 这里同
			if owner.get("_equipPearl", false):
				var hp_pct: float = float(owner.get("hp", 0)) / float(owner.get("maxHp", 1))
				if hp_pct < 0.5:
					owner["_equipPearl"] = false   # 销毁
					var heal_amt: int = Buffs.fatigue_amt(owner, roundi(owner.get("maxHp", 0) * 0.2))
					var before_hp: int = owner.get("hp", 0)
					owner["hp"] = mini(owner.get("maxHp", 0), before_hp + heal_amt)
					var actual: int = owner["hp"] - before_hp
					var owner_idx2 := _find_idx(owner, all_fighters)
					if actual > 0:
						effects.append({
							"target_idx": owner_idx2,
							"value": actual,
							"kind": "heal",
							"source": "🦪 珍珠",
						})
					# 火球 (1:1 PoC BattleScene.ts:8522-8536): 对随机存活敌 8% 其maxHp 魔伤(吃mr) + 30 灼烧
					var p_enemies: Array = []
					for ef in all_fighters:
						if ef.get("alive", false) and ef.get("side", "") != owner.get("side", "") and not ef.get("_isSummon", false):
							p_enemies.append(ef)
					if not p_enemies.is_empty():
						var pe: Dictionary = p_enemies[randi() % p_enemies.size()]
						var fb_base: int = roundi(pe.get("maxHp", 0) * 0.08)
						var fb_dmg: int = maxi(1, roundi(fb_base * Damage.calc_dmg_mult(Damage.calc_eff_mr(owner, pe))))
						var pr: Dictionary = Damage.apply_raw_damage(pe, fb_dmg, "magic")
						var shown_fb: int = pr["hpLoss"] + pr["shieldAbs"]
						Dot.apply_stacks(pe, "burn", 30)
						var pe_idx := _find_idx(pe, all_fighters)
						if shown_fb > 0:
							# 血跟火球落地才掉: arrival_delay = 火球飞行 0.35s (_play_fireball travel, 对齐金弹 _stamp_arrival(.,0,0.20) 同法) — 显示时机, 数值不动
							effects.append({"target_idx": pe_idx, "value": shown_fb, "kind": "damage", "dmg_type": "magic", "is_crit": false, "source": "🔥 珍珠火球", "vfx": "fireball", "vfx_from": owner_idx2, "arrival_delay": 0.35})
						effects.append({"target_idx": pe_idx, "kind": "passive", "label": "🔥灼烧"})

	return effects


# ─── on_turn_begin (round-begin 全员触发) ─────────────────────

## 取 _slotKey 列号 (尾部数字, 1:1 PoC k.match(/-(\d+)$/)); 无效返 -1
static func _slot_col(f: Dictionary) -> int:
	var parts: PackedStringArray = str(f.get("_slotKey", "")).split("-")
	if parts.size() == 0:
		return -1
	var last: String = parts[parts.size() - 1]
	return int(last) if last.is_valid_int() else -1


## 迷你水晶球魔光命中: 对 targets 各 dmg_per 魔法 + 1 迷你水晶层; 满3层引爆 round(maxHp×14%) 魔法+重置 (1:1 PoC BattleScene:7704-7720)
static func _mini_crystal_hit(fighter: Dictionary, all_fighters: Array, targets: Array, dmg_per: int) -> Array:
	var fx: Array = []
	for t in targets:
		if not t.get("alive", false):
			continue
		var d: int = maxi(1, roundi(float(dmg_per) * Damage.calc_dmg_mult(Damage.calc_eff_mr(fighter, t))))
		var r: Dictionary = Damage.apply_raw_damage(t, d, "magic")
		var s: int = int(r["hpLoss"]) + int(r["shieldAbs"])
		if s > 0:
			fx.append({"target_idx": _idx(t, all_fighters), "value": s, "kind": "damage", "dmg_type": "magic"})
		t["_miniCrystallize"] = int(t.get("_miniCrystallize", 0)) + 1
		if int(t["_miniCrystallize"]) >= 3:
			t["_miniCrystallize"] = 0
			var expl: int = maxi(1, roundi(float(roundi(int(t.get("maxHp", 0)) * 0.14)) * Damage.calc_dmg_mult(Damage.calc_eff_mr(fighter, t))))
			var er: Dictionary = Damage.apply_raw_damage(t, expl, "magic")
			var es: int = int(er["hpLoss"]) + int(er["shieldAbs"])
			if es > 0:
				fx.append({"target_idx": _idx(t, all_fighters), "value": es, "kind": "damage", "dmg_type": "magic", "is_crit": true})
	return fx


static func on_turn_begin(fighter: Dictionary, equip_id: String, all_fighters: Array) -> Array:
	var effects: Array = []
	if not fighter.get("alive", false):
		return effects

	match equip_id:
		"e_anemone":
			# PoC equipment.ts: 携带者每回合 +8% maxHp HoT
			var hot_pct: int = fighter.get("_equipHot", 0)
			if hot_pct > 0:
				var heal_amt: int = Buffs.fatigue_amt(fighter, roundi(fighter.get("maxHp", 0) * hot_pct / 100.0))
				var before: int = fighter.get("hp", 0)
				fighter["hp"] = mini(fighter.get("maxHp", 0), before + heal_amt)
				var actual: int = fighter["hp"] - before
				if actual > 0:
					var idx := _find_idx(fighter, all_fighters)
					effects.append({
						"target_idx": idx,
						"value": actual,
						"kind": "heal",
						"source": "🌸 海葵",
					})

		"e_ripple":
			# PoC: 每回合给全体友方 (含自己) 回已损 HP × allyHotPct% (3% per 件)
			var pct: int = fighter.get("_equipRippleAllyHotPct", 0)
			if pct > 0:
				for ally in all_fighters:
					if ally.get("side", "") != fighter.get("side", "") or not ally.get("alive", false):
						continue
					var miss_hp: int = ally.get("maxHp", 0) - ally.get("hp", 0)
					var heal2: int = roundi(miss_hp * pct / 100.0)
					if heal2 > 0:
						var before2: int = ally.get("hp", 0)
						ally["hp"] = mini(ally.get("maxHp", 0), before2 + heal2)
						var actual2: int = ally["hp"] - before2
						if actual2 > 0:
							effects.append({
								"target_idx": _find_idx(ally, all_fighters),
								"value": actual2,
								"kind": "heal",
								"source": "🌊 涟漪",
							})

		"e_dragon_egg":
			# 龙蛋喷火 (PoC BattleScene:5498-5557): 每回合 +1 吐息; 满3层→重置+龙飞过随机有敌列:
			#   该列友军各 +40HP, 该列敌军各 50魔法 + 25灼烧。喷火横扫 VFX 先缓(逻辑先 1:1)。
			var d_st: int = int(fighter.get("_equipDragonEggStacks", 0)) + 1
			if d_st < 3:
				fighter["_equipDragonEggStacks"] = d_st
				effects.append({"target_idx": _find_idx(fighter, all_fighters), "kind": "passive", "label": "🐉%d/3" % d_st})
			else:
				fighter["_equipDragonEggStacks"] = 0
				var de_cols: Array = []
				for e in all_fighters:
					if e.get("alive", false) and e.get("side", "") != fighter.get("side", ""):
						var ec: int = _slot_col(e)
						if ec >= 0 and not de_cols.has(ec):
							de_cols.append(ec)
				if not de_cols.is_empty():
					var pc: int = de_cols[randi() % de_cols.size()]
					for u in all_fighters:
						if not u.get("alive", false) or _slot_col(u) != pc:
							continue
						if u.get("side", "") == fighter.get("side", ""):
							var amt: int = Buffs.fatigue_amt(u, 40)
							var bef: int = int(u.get("hp", 0))
							u["hp"] = mini(int(u.get("maxHp", 0)), bef + amt)
							if int(u["hp"]) - bef > 0:
								effects.append({"target_idx": _find_idx(u, all_fighters), "value": int(u["hp"]) - bef, "kind": "heal", "source": "🐉 龙息"})
						else:
							var mdmg: int = maxi(1, roundi(50.0 * Damage.calc_dmg_mult(Damage.calc_eff_mr(fighter, u))))
							var rdd: Dictionary = Damage.apply_raw_damage(u, mdmg, "magic")
							var sdd: int = int(rdd["hpLoss"]) + int(rdd["shieldAbs"])
							if sdd > 0:
								effects.append({"target_idx": _find_idx(u, all_fighters), "value": sdd, "kind": "damage", "dmg_type": "magic"})
							Dot.apply_stacks(u, "burn", 25)

		"e_amplifier":
			var amp_pct: int = 16 + randi() % 9   # 1:1 PoC 16-24% (BattleScene.ts:5469)
			fighter["_dmgBonusThisTurnPct"] = maxi(int(fighter.get("_dmgBonusThisTurnPct", 0)), amp_pct)
			effects.append({"target_idx": _find_idx(fighter, all_fighters), "kind": "passive", "label": "📡放大器 +%d%% 增伤" % amp_pct})   # 1:1 PoC:5472 (原"讯放大器"简写)

		"e_incubator":
			# 孵化器: 每回合 +5 孵化进度 (PoC:578 回合+5); 满100升临时等级
			if _incubator_add(fighter, 5) > 0:
				effects.append({"target_idx": _find_idx(fighter, all_fighters), "kind": "passive", "label": "🥚 临时Lv+%d" % int(fighter.get("_incubatorTempLevel", 0))})

		"e_fpga":
			var fpga_i: int = _find_idx(fighter, all_fighters)
			var fpga_st: int = randi() % 4
			if fpga_st == 0:
				var b0: int = int(fighter.get("hp", 0))
				fighter["hp"] = mini(int(fighter.get("maxHp", 0)), b0 + roundi(fighter.get("maxHp", 0) * 0.05))
				_add_def(fighter, 2)
				_add_mr(fighter, 2)
				# 1:1 PoC:5435 单条 passive label 含回血(原 Godot 分 heal float + "FPGA00"简写 = 双飘+措辞偏差)
				effects.append({"target_idx": fpga_i, "kind": "passive", "label": "🔧FPGA-00 +%dHP +2甲/抗" % (int(fighter["hp"]) - b0)})
			elif fpga_st == 1:
				_add_atk(fighter, 5)
				fighter["_lifestealPct"] = int(fighter.get("_lifestealPct", 0)) + 4
				effects.append({"target_idx": fpga_i, "kind": "passive", "label": "🔧FPGA-01 +5 ATK +4% 生命偷取"})   # 1:1 PoC:5444
			elif fpga_st == 2:
				fighter["_dmgBonusThisTurnPct"] = maxi(int(fighter.get("_dmgBonusThisTurnPct", 0)), 15)
				effects.append({"target_idx": fpga_i, "kind": "passive", "label": "🔧FPGA-10 本回合 +15% 增伤"})   # 1:1 PoC:5453
			else:
				Buffs.add(fighter, "dmgReduce", 25, 1, "refresh")
				effects.append({"target_idx": fpga_i, "kind": "passive", "label": "🔧FPGA-11 本回合 -25% 受伤"})   # 1:1 PoC:5461

	return effects


# ─── on_side_end (回合末装备通道, PoC processSideEndEquipment:7484) ──────
## 应用 candle/dumbbell/revolver/wave 的回合末效果, 返回 effect 描述供 BattleScene 飘字.
## 直接落伤害/治疗 (静态无视图), 返 [{owner_idx?, target_idx, value, kind, dmg_type, label}].
## 施法后装备 (post-cast, 1:1 PoC processSkillEquipEffects:3125+). target=主目标(可能友/自), is_single=单体技能。
##   施法后装备只打敌人(治疗/友方技能 target 是友军→视为无主敌)。返回 effects 供主流程渲染。
static func on_post_cast(caster: Dictionary, equip_id: String, target, all_fighters: Array, is_single: bool) -> Array:
	var out: Array = []
	if not caster.get("alive", false):
		return out
	var enemies: Array = []
	for f in all_fighters:
		if f.get("alive", false) and f.get("side", "") != caster.get("side", ""):
			enemies.append(f)
	if enemies.is_empty():
		return out
	var tgt_enemy = null
	if target is Dictionary and target.get("alive", false) and target.get("side", "") != caster.get("side", ""):
		tgt_enemy = target
	match equip_id:
		"e_stun_baton":
			# 电棍 (PoC BattleScene:3131): 施法后, 单体技→电该目标/否则随机敌, 30魔法+眩1回, -1层
			if int(caster.get("_stunBatonStacks", 0)) > 0:
				var st = tgt_enemy if (is_single and tgt_enemy != null) else enemies[randi() % enemies.size()]
				if st != null and st.get("alive", false):
					caster["_stunBatonStacks"] = int(caster["_stunBatonStacks"]) - 1
					var d: int = maxi(1, roundi(30.0 * Damage.calc_dmg_mult(Damage.calc_eff_mr(caster, st))))
					var r: Dictionary = Damage.apply_raw_damage(st, d, "magic")
					var s: int = int(r["hpLoss"]) + int(r["shieldAbs"])
					if s > 0:
						out.append({"target_idx": _idx(st, all_fighters), "value": s, "kind": "damage", "dmg_type": "magic", "label": "⚡电棍"})
					if not Buffs.has(st, "stun"):
						Buffs.add(st, "stun", 1, 2, "ignore")   # 眩晕 1 回合 (duration2: turn-end-1)
						st["_stunUsed"] = false
		"e_bamboo_leaf":
			# 竹叶 (PoC BattleScene:3158): 持充能时施法后→随机敌 (35+20%maxHp)魔法, 回20%maxHp, 永久+100maxHp, 充能清0
			if int(caster.get("_bambooLeafCharge", 0)) > 0:
				caster["_bambooLeafCharge"] = 0
				var lt = enemies[randi() % enemies.size()]
				if lt.get("alive", false):
					var base: int = 35 + roundi(int(caster.get("maxHp", 0)) * 0.20)
					var d2: int = maxi(1, roundi(float(base) * Damage.calc_dmg_mult(Damage.calc_eff_mr(caster, lt))))
					var r2: Dictionary = Damage.apply_raw_damage(lt, d2, "magic")
					var s2: int = int(r2["hpLoss"]) + int(r2["shieldAbs"])
					if s2 > 0:
						out.append({"target_idx": _idx(lt, all_fighters), "value": s2, "kind": "damage", "dmg_type": "magic", "label": "🌿竹叶"})
					var heal: int = Buffs.fatigue_amt(caster, roundi(int(caster.get("maxHp", 0)) * 0.20))
					var bef: int = int(caster.get("hp", 0))
					caster["hp"] = mini(int(caster.get("maxHp", 0)), bef + heal)
					if int(caster["hp"]) - bef > 0:
						out.append({"target_idx": _idx(caster, all_fighters), "value": int(caster["hp"]) - bef, "kind": "heal", "label": "🌿"})
					caster["maxHp"] = int(caster.get("maxHp", 0)) + 100
					caster["hp"] = int(caster.get("hp", 0)) + 100
					out.append({"target_idx": _idx(caster, all_fighters), "kind": "passive", "label": "🌿+100maxHp"})
	return out


static func on_side_end(fighter: Dictionary, equip_id: String, all_fighters: Array) -> Array:
	var out: Array = []
	if not fighter.get("alive", false):
		return out
	var enemies: Array = []
	var allies: Array = []
	for f in all_fighters:
		if not f.get("alive", false):
			continue
		if f.get("side", "") == fighter.get("side", ""):
			allies.append(f)
		else:
			enemies.append(f)
	match equip_id:
		"e_candle":
			fighter["_equipCandleStage"] = (int(fighter.get("_equipCandleStage", 0)) + 1) % 3
			var stage: int = int(fighter.get("_equipCandleStage", 0))
			if stage == 1:   # 微弱: 自己 +20, 其余友军各 +10
				var a0: int = _heal_raw(fighter, 20)
				if a0 > 0: out.append({"target_idx": _idx(fighter, all_fighters), "value": a0, "kind": "heal", "label": "🕯"})
				for nb in allies:
					if nb == fighter: continue
					var a2: int = _heal_raw(nb, 10)
					if a2 > 0: out.append({"target_idx": _idx(nb, all_fighters), "value": a2, "kind": "heal", "label": "🕯"})
			elif stage == 2 and not enemies.is_empty():   # 燃烧: 随机敌所在横排 30 魔法 + 20 灼烧
				var aim: Dictionary = enemies[randi() % enemies.size()]
				var row: String = str(aim.get("_slotKey", "front-0")).split("-")[-1]
				for t in enemies:
					if not str(t.get("_slotKey", "")).ends_with("-" + row): continue
					var r: Dictionary = Damage.apply_raw_damage(t, maxi(1, roundi(30 * Damage.calc_dmg_mult(Damage.calc_eff_mr(fighter, t)))), "magic")
					var shown: int = r["hpLoss"] + r["shieldAbs"]
					if shown > 0: out.append({"target_idx": _idx(t, all_fighters), "value": shown, "kind": "damage", "dmg_type": "magic"})
					Dot.apply_stacks(t, "burn", 20)
		"e_dumbbell":
			fighter["maxHp"] = int(fighter.get("maxHp", 0)) + 25
			fighter["hp"] = int(fighter.get("hp", 0)) + 25
			fighter["_equipDumbbellGain"] = int(fighter.get("_equipDumbbellGain", 0)) + 25
			out.append({"target_idx": _idx(fighter, all_fighters), "kind": "passive", "label": "🏋+25"})
			if not enemies.is_empty():
				var tgt: Dictionary = enemies[randi() % enemies.size()]
				var dmg: int = maxi(1, Damage.calc_damage(fighter, tgt, maxi(1, roundi(fighter.get("maxHp", 0) * 0.05)), "physical"))
				var r2: Dictionary = Damage.apply_raw_damage(tgt, dmg, "physical")
				var s2: int = r2["hpLoss"] + r2["shieldAbs"]
				if s2 > 0: out.append({"target_idx": _idx(tgt, all_fighters), "value": s2, "kind": "damage", "dmg_type": "physical", "vfx": "projectile", "vfx_from": _idx(fighter, all_fighters), "vfx_path": "res://assets/sprites/equip/dungeon-dumbbell.png", "vfx_size": 42.0, "vfx_dur": 0.42})
		"e_revolver":
			if int(fighter.get("_equipRevolverBullets", 0)) > 0 and not enemies.is_empty():
				fighter["_equipRevolverBullets"] = int(fighter["_equipRevolverBullets"]) - 1
				var tgt2: Dictionary = enemies[randi() % enemies.size()]
				var dmg2: int = maxi(1, Damage.calc_damage(fighter, tgt2, 40, "physical"))
				var r3: Dictionary = Damage.apply_raw_damage(tgt2, dmg2, "physical")
				var s3: int = r3["hpLoss"] + r3["shieldAbs"]
				if s3 > 0: out.append({"target_idx": _idx(tgt2, all_fighters), "value": s3, "kind": "damage", "dmg_type": "physical", "vfx": "projectile", "vfx_from": _idx(fighter, all_fighters), "vfx_path": "res://assets/sprites/vfx/revolver-bullet.png", "vfx_size": 30.0, "vfx_dur": 0.30})
		"e_thunder_shell":
			# 雷鸣贝壳 (PoC BattleScene:7327): 每件 → 电击 1 随机存活敌, round(ATK×1.0) 真伤
			var zt_i: int = 0
			for _zt in range(int(fighter.get("_equipThunderBell", 0))):
				if not fighter.get("alive", false):
					break
				var alive_ts: Array = enemies.filter(func(e): return e.get("alive", false))
				if alive_ts.is_empty():
					break
				var tgt_ts: Dictionary = alive_ts[randi() % alive_ts.size()]
				var rts: Dictionary = Damage.apply_raw_damage(tgt_ts, roundi(fighter.get("atk", 0) * 1.0), "true")
				var sts: int = rts["hpLoss"] + rts["shieldAbs"]
				# delay 600ms/发(1:1 PoC sleep600) + hp_after逐发步进血条 + 天降闪电 VFX
				if sts > 0: out.append({"target_idx": _idx(tgt_ts, all_fighters), "value": sts, "kind": "damage", "dmg_type": "true", "delay": (0.6 if zt_i > 0 else 0.0), "hp_after": int(tgt_ts.get("hp", 0)), "vfx": "lightning"})
				zt_i += 1
		"e_mini_crystal":
			# 迷你水晶球A (PoC BattleScene:7690): 回合末→随机敌列发 2 段魔光(各30魔法+1迷你水晶层). castCrystalBeam VFX 缓.
			var mc_en: Array = enemies.filter(func(e): return e.get("alive", false))
			if not mc_en.is_empty():
				var aim_col: int = _slot_col(mc_en[randi() % mc_en.size()])
				var col_tgts: Array = mc_en.filter(func(e): return _slot_col(e) == aim_col)
				if col_tgts.is_empty():
					col_tgts = [mc_en[0]]
				for _seg in range(2):
					out.append_array(_mini_crystal_hit(fighter, all_fighters, col_tgts, 30))
		"e_mini_crystal_b":
			# 迷你水晶球B (PoC BattleScene:7650): 回合末旋转红光扫全敌, 各 20魔法+1迷你水晶层(满3引爆14%). launchMiniCrystalBeam VFX 缓.
			out.append_array(_mini_crystal_hit(fighter, all_fighters, enemies.filter(func(e): return e.get("alive", false)), 20))
		"e_wave":
			fighter["_equipWaveStacks"] = int(fighter.get("_equipWaveStacks", 0)) + 1
			if int(fighter["_equipWaveStacks"]) >= 3:
				fighter["_equipWaveStacks"] = 0
				var rk: String = str(randi() % 3)
				for u in all_fighters:
					if not u.get("alive", false) or not str(u.get("_slotKey", "")).ends_with("-" + rk): continue
					if u.get("side", "") == fighter.get("side", ""):   # 友方 +20盾 +2甲抗永久
						Buffs.grant_shield(u, 20)
						u["baseDef"] = int(u.get("baseDef", 0)) + 2; u["def"] = int(u.get("def", 0)) + 2
						u["baseMr"] = int(u.get("baseMr", u.get("baseDef", 0))) + 2; u["mr"] = int(u.get("mr", 0)) + 2
						out.append({"target_idx": _idx(u, all_fighters), "value": 20, "kind": "shield", "label": "🌊"})
					else:   # 敌方 20魔法 + -2甲抗永久
						var rw: Dictionary = Damage.apply_raw_damage(u, maxi(1, roundi(20 * Damage.calc_dmg_mult(Damage.calc_eff_mr(fighter, u)))), "magic")
						var sw: int = rw["hpLoss"] + rw["shieldAbs"]
						u["baseDef"] = maxi(0, int(u.get("baseDef", 0)) - 2); u["def"] = u["baseDef"]
						u["baseMr"] = maxi(0, int(u.get("baseMr", u.get("baseDef", 0))) - 2); u["mr"] = u["baseMr"]
						if sw > 0: out.append({"target_idx": _idx(u, all_fighters), "value": sw, "kind": "damage", "dmg_type": "magic"})
		"e_dart":
			# 飞镖 (PoC BattleScene:7563): 向所有带"靶子"(_knockedUpThisTurn)的敌人各射 1 枚 → 50 物理 + 20 流血, 命中后移除靶子
			if fighter.get("_equipDart", false):
				for e in enemies:
					if not e.get("_knockedUpThisTurn", false):
						continue
					var dd: int = maxi(1, Damage.calc_damage(fighter, e, 50, "physical"))
					var rd: Dictionary = Damage.apply_raw_damage(e, dd, "physical")
					var sd: int = rd["hpLoss"] + rd["shieldAbs"]
					if sd > 0:
						out.append({"target_idx": _idx(e, all_fighters), "value": sd, "kind": "damage", "dmg_type": "physical", "vfx": "projectile", "vfx_from": _idx(fighter, all_fighters), "vfx_path": "res://assets/sprites/equip/dungeon-dart.png", "vfx_size": 30.0, "vfx_dur": 0.34})
					Dot.apply_stacks(e, "bleed", 20)   # 20 层流血累加
					e["_knockedUpThisTurn"] = false   # 移除靶子
		"e_doll":
			# 玩偶小熊 (PoC BattleScene:7730): 已召唤过(_equipDollSpawned)则不再触发
			if fighter.get("_equipDoll", false) and not fighter.get("_equipDollSpawned", false):
				if not enemies.is_empty():
					# 小熊走向随机敌人 (前排优先): 有前排就只从前排选
					var front: Array = []
					for e2 in enemies:
						if str(e2.get("_slotKey", "")).begins_with("front-"):
							front.append(e2)
					var pool: Array = front if not front.is_empty() else enemies
					var tgt: Dictionary = pool[randi() % pool.size()]
					var dmg: int = maxi(1, Damage.calc_damage(fighter, tgt, 30, "physical"))
					var rb: Dictionary = Damage.apply_raw_damage(tgt, dmg, "physical")
					var sb: int = rb["hpLoss"] + rb["shieldAbs"]
					if sb > 0:
						out.append({"target_idx": _idx(tgt, all_fighters), "value": sb, "kind": "damage", "dmg_type": "physical"})
				# 携带者每次 +1 层大熊层数
				fighter["_equipDollBigBearStacks"] = int(fighter.get("_equipDollBigBearStacks", 0)) + 1
				# 满 5 层 → 标记可召唤大熊 (实际 spawn fighter+view 在 BattleScene; 没空位时不归零, 继续攒)
				if int(fighter.get("_equipDollBigBearStacks", 0)) >= 5:
					fighter["_equipDollReadyToSpawn"] = true
					out.append({"target_idx": _idx(fighter, all_fighters), "kind": "passive", "label": "🧸 大熊就绪!"})
	return out


# ─── on_death (PoC BattleScene.processDeathPassives:4358) ─────────
## 携带者彻底阵亡 (所有复活机会用尽) 时调用. 返回是否发生了变形 (供 BattleScene 重渲染/记 _isConchWorm).
## 1:1 PoC: 复活海螺 → 原位变形小虫 (150 HP, 20 ATK, 无甲抗, 等级每级 +5%), 替换技能为"啃咬".
## 注: 小虫每回合自动攻击最低血敌 (1×ATK 物理) 由 BattleScene side-end 读 _isConchWorm 驱动 (本文件只做属性/技能变形).
static func on_death(dead: Dictionary, equip_id: String) -> bool:
	if equip_id != "e_conch":
		return false
	if not dead.get("_equipConch", false) or dead.get("_conchUsed", false):
		return false
	dead["_conchUsed"] = true
	# 召唤物级联清理 (PoC equip-effects.js:153-164): 自身的召唤物一同倒下
	var summon = dead.get("_summon", null)
	if summon is Dictionary and summon.get("alive", false):
		summon["alive"] = false; summon["hp"] = 0
	# 变形为小虫 (等级每级 +5%); 小虫基础 HP/ATK 可被 _conchWormHp/_conchWormAtk 覆盖 (二阶段033复活海螺逐星; phase1 e_conch 不设 → 默认 150/20)
	var lv: int = int(dead.get("_level", 1))
	var lv_bonus: float = 1.0 + (lv - 1) * 0.05
	dead["maxHp"] = roundi(int(dead.get("_conchWormHp", 150)) * lv_bonus)
	dead["hp"] = dead["maxHp"]
	dead["baseAtk"] = roundi(int(dead.get("_conchWormAtk", 20)) * lv_bonus); dead["atk"] = dead["baseAtk"]
	dead["baseDef"] = 0; dead["def"] = 0
	dead["baseMr"] = 0; dead["mr"] = 0
	dead["crit"] = 0.0
	dead["armorPen"] = 0; dead["armorPenPct"] = 0
	dead["magicPen"] = 0; dead["magicPenPct"] = 0
	dead["shield"] = 0
	dead["alive"] = true
	dead["buffs"] = []
	dead["_isConchWorm"] = true
	dead["name"] = "海螺小虫"; dead["emoji"] = "🐛"
	dead["passive"] = null   # 独立召唤物实体, 清原龟被动/身份
	# 替换技能: 啃咬 (每回合末自动攻击最低血敌人)
	dead["skills"] = [{
		"name": "啃咬", "type": "physical", "hits": 1, "power": 0, "pierce": 0,
		"cd": 0, "cdLeft": 0, "atkScale": 1.0,
		"brief": "每回合自动攻击当前生命值最低的敌人, 造成 (1×ATK) 物理伤害。",
		"detail": "海螺小虫每回合末自动咬向当前生命值最低的敌人, 造成 100%×攻击力 物理伤害。",
	}]
	# 清装备 flag (PoC equip-effects.js:180-188)
	dead["_equipConch"] = false
	dead["_equipped_ids"] = []
	return true


# ─── helpers ───────────────────────────────────────────────────

static func _heal_raw(f: Dictionary, amt: int) -> int:
	amt = Buffs.fatigue_amt(f, amt)   # 决胜局疲惫: 治疗 ×0.5
	var before: int = int(f.get("hp", 0))
	f["hp"] = mini(int(f.get("maxHp", 0)), before + amt)
	return int(f["hp"]) - before


static func _idx(f: Dictionary, all_fighters: Array) -> int:
	return all_fighters.find(f)


static func _add_atk(f: Dictionary, n: int) -> void:
	f["baseAtk"] = f.get("baseAtk", 0) + n
	f["atk"] = f["baseAtk"]

static func _add_def(f: Dictionary, n: int) -> void:
	f["baseDef"] = f.get("baseDef", 0) + n
	f["def"] = f["baseDef"]

static func _add_mr(f: Dictionary, n: int) -> void:
	f["baseMr"] = f.get("baseMr", 0) + n
	f["mr"] = f["baseMr"]

static func _add_max_hp(f: Dictionary, n: int) -> void:
	f["maxHp"] = f.get("maxHp", 0) + n
	f["hp"] = f.get("hp", 0) + n

static func _find_idx(fighter: Dictionary, all_fighters: Array) -> int:
	for i in range(all_fighters.size()):
		if all_fighters[i] == fighter:
			return i
	return -1


# ─── 宝箱龟 treasure 变种系统 (1:1 PoC BattleScene.ts:4746-4861) ──────────────
##
## 宝箱龟(chestTreasure 被动)按造成伤害累积 _chestTreasure (累积由 BattleScene 受伤端 hook 做,
## 1:1 PoC passive-triggers.ts:247-252). 达到阈值时从 pets.json 的 passive.pools 抽装备:
##   tier 0-1 → pool 0 (基础, 回 8% maxHp), tier 2-3 → pool 1 (进阶, 11%), tier 4 → pool 2 (传说, 15%)
## 抽到的装备调 apply_chest_equip_stat 落属性 / 设 _chestEquip* flag (供 chestSmash/chestStorm 读).
## 返回 effects 数组 (heal / passive 飘字) 供 caller (BattleScene side-end / on-hit) 飘字.
## 注: 闪电劈下 VFX 不在此 (thunder 引爆在 SkillHandlers 落, 见 _chest_smash/_chest_storm).
static func process_chest_treasure_gain(f: Dictionary, gain: int, all_fighters: Array = []) -> Array:
	var out: Array = []
	var p = f.get("passive", null)
	if not (p is Dictionary) or p.get("type", "") != "chestTreasure":
		return out
	# 寻宝直觉(chestIntuition)装备时阈值整体降低 (PoC:4756)
	var thresholds: Array = [60, 120, 220, 350, 500] if f.get("_chestIntuition", false) \
		else p.get("thresholds", [80, 130, 240, 360, 590])
	var pools: Array = p.get("pools", [])
	var lv_mult: float = 1.0 + (int(f.get("_level", 1)) - 1) * 0.03
	var heal_pct_by_pool: Array = [8, 11, 15]
	f["_chestTreasure"] = int(f.get("_chestTreasure", 0)) + gain
	if not (f.get("_chestEquips", null) is Array):
		f["_chestEquips"] = []
	var equips: Array = f["_chestEquips"]

	while int(f.get("_chestTier", 0)) < thresholds.size() \
			and int(f.get("_chestTreasure", 0)) >= roundi(float(thresholds[int(f.get("_chestTier", 0))]) * lv_mult):
		var tier: int = int(f.get("_chestTier", 0))
		var pool_idx: int = 0 if tier < 2 else (1 if tier < 4 else 2)
		if pool_idx >= pools.size() or not (pools[pool_idx] is Array) or (pools[pool_idx] as Array).is_empty():
			f["_chestTier"] = tier + 1
			continue
		var pool: Array = pools[pool_idx]
		var owned: Array = []
		for e in equips:
			owned.append(e.get("id", ""))
		var available: Array = []
		for e in pool:
			if not owned.has(e.get("id", "")):
				available.append(e)
		if available.is_empty():
			f["_chestTier"] = tier + 1
			continue
		var drawn: Dictionary = available[randi() % available.size()]
		equips.append(drawn.duplicate())
		f["_chestTier"] = tier + 1

		# 应用 stat / 设 flag
		apply_chest_equip_stat(f, drawn)
		# 应用后立即 recalc (PoC:4780-4783, 让 lifestealPct/crit 等同步进面板/实战, 不滞后一回合)
		if not (f.get("_baseCrit", null) is float or f.get("_baseCrit", null) is int):
			StatsRecalc.snapshot_base(f)
		var allies: Array = []
		for a in all_fighters:
			if a.get("side", "") == f.get("side", "") and a.get("alive", false):
				allies.append(a)
		StatsRecalc.recalc(f, allies)

		# Heal
		var heal_pct: int = heal_pct_by_pool[pool_idx]
		var heal_amt: int = Buffs.fatigue_amt(f, roundi(f.get("maxHp", 0) * heal_pct / 100.0))
		var before: int = int(f.get("hp", 0))
		f["hp"] = mini(int(f.get("maxHp", 0)), before + heal_amt)
		var actual: int = int(f["hp"]) - before
		var idx: int = _find_idx(f, all_fighters)
		if actual > 0:
			out.append({"target_idx": idx, "value": actual, "kind": "heal", "source": "📦 " + str(drawn.get("name", ""))})
		else:
			out.append({"target_idx": idx, "kind": "passive", "label": "📦 " + str(drawn.get("name", ""))})
	return out


## 宝箱装备 stat 应用 (1:1 PoC BattleScene.ts:4801-4861)
static func apply_chest_equip_stat(f: Dictionary, equip: Dictionary) -> void:
	var pct: float = equip.get("pct", 0)
	match str(equip.get("stat", "")):
		"atk":
			f["baseAtk"] = int(f.get("baseAtk", 0)) + roundi(f.get("baseAtk", 0) * pct / 100.0)
			f["atk"] = f["baseAtk"]
		"defMr":
			f["baseDef"] = int(f.get("baseDef", 0)) + roundi(f.get("baseDef", 0) * pct / 100.0)
			var base_mr: int = int(f.get("baseMr", f.get("baseDef", 0)))
			f["baseMr"] = base_mr + roundi(base_mr * pct / 100.0)
			f["def"] = f["baseDef"]
			f["mr"] = f["baseMr"]
			if int(equip.get("bonusHp", 0)) > 0:
				f["maxHp"] = int(f.get("maxHp", 0)) + int(equip.get("bonusHp", 0))
				f["hp"] = int(f.get("hp", 0)) + int(equip.get("bonusHp", 0))
		"crit":
			f["crit"] = minf(1.0, f.get("crit", 0.0) + pct / 100.0)
		"lifesteal":
			f["_lifestealPct"] = f.get("_lifestealPct", 0) + pct
		"crown":
			f["baseAtk"] = int(f.get("baseAtk", 0)) + roundi(f.get("baseAtk", 0) * 40 / 100.0)
			f["atk"] = f["baseAtk"]
			f["crit"] = minf(1.0, f.get("crit", 0.0) + 0.40)
			f["_extraCritDmgPerm"] = f.get("_extraCritDmgPerm", 0.0) + 0.25
			f["_lifestealPct"] = f.get("_lifestealPct", 0) + 15
		"hot":
			# 海盗龟酒: 每回合回 X% maxHp (turn-begin 处理, 设 flag)
			f["_chestEquipRum"] = true
			f["_chestEquipRumPct"] = pct
		"trueDmg":
			f["_chestEquipStar"] = true
		"thunder":
			f["_chestEquipThunder"] = true
		"chain":
			f["_chestEquipChain"] = true
		"rock":
			f["_chestEquipRock"] = true
		"burn":
			f["_chestEquipFire"] = true
		"healReduce":
			f["_chestEquipPoison"] = true
		"revive":
			f["_chestEquipRevive"] = true
	# 贪婪 passive: 抽到的每件装备额外 +4%baseAtk +7%maxHp (1:1 PoC BattleScene.ts:4862-4868)
	#   登场结算只覆盖开局已带装备; 局内开宝箱抽到的新装备走这里, 之前漏算贪婪加成。
	if f.get("_chestGreed", false):
		var greed_atk: int = roundi(float(f.get("baseAtk", 0)) * 0.04)
		var greed_hp: int = roundi(float(f.get("maxHp", 0)) * 0.07)
		f["baseAtk"] = int(f.get("baseAtk", 0)) + greed_atk
		f["atk"] = f["baseAtk"]
		f["maxHp"] = int(f.get("maxHp", 0)) + greed_hp
		f["hp"] = int(f.get("hp", 0)) + greed_hp


# ─── 战利品池 ──────────────────────────────────────────────────

const LOOT_POOL: Array[String] = [
	"e_blade", "e_carapace", "e_pearl", "e_tooth", "e_piercer", "e_hammer",
	"e_urchin", "e_fire", "e_jelly", "e_anemone", "e_octo", "e_star", "e_ripple",
	"e_ghost", "e_hourglass", "e_dumbbell", "e_candle", "e_revolver", "e_wave", "e_amplifier", "e_fpga",
	"e_dart", "e_doll", "e_conch", "e_laser_blade",
]

static func random_loot(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return LOOT_POOL[rng.randi_range(0, LOOT_POOL.size() - 1)]


static func display_name(equip_id: String) -> String:
	var eq: Dictionary = DataRegistry.equipment_by_id.get(equip_id, {})
	return eq.get("name", equip_id)
