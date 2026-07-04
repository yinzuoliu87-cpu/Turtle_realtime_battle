extends RefCounted
## Phase2EquipRuntime — 二阶段【剑系】装备战斗实装 (用户 2026-06-13 批次)。
##
## 用 preload 引 (不用 class_name — 防 F5 未声明崩):
##   const P2RT = preload("res://scripts/engine/phase2_equip_runtime.gd")
##
## 结构 (mirror equipment_runtime.gd 的 phase-1 钩子协议):
##   - apply_stats(f, id, star): 逐星基础属性直接加到 fighter (battle init, snapshot 前)。
##   - on_hit(attacker, target, dmg, id, star, all, is_first) -> Array effects: 逐段命中后。
##   - on_cast(caster, id, star, all) -> Array effects: 携带者释放技能后一次。
##   - on_turn_begin(f, id, star, all) -> Array effects: 携带者回合开始 (锈蚀短剑劈砍)。
## effects shape 同 EquipmentRuntime: {target_idx, value, kind:"damage"/"heal", dmg_type, is_crit}。
##
## 单位 (从代码核实): crit=小数0~1 · _lifestealPct=整数% · armorPen/magicPen=flat · _maxEnergy=flat。
## 规格见 docs/specs/PHASE2-EQUIP-SWORD-SPEC.md。002 海藻流血=0.075/0.1/0.15 (用户确认)。

const Dot := preload("res://scripts/engine/dot.gd")
const Damage := preload("res://scripts/engine/damage.gd")
const SlotHelpers := preload("res://scripts/engine/slot_helpers.gd")
const Buffs := preload("res://scripts/engine/buffs.gd")   # grant_shield (护盾增幅+疲惫统一收口)

# ── 逐星基础属性 (idx 0=1★ / 1=2★ / 2=3★)。crit=小数。_lifestealPct=整数%。──
const STATS := {
	"p2eq_001": [{"atk": 5, "crit": 0.10}, {"atk": 12, "crit": 0.15}, {"atk": 20, "crit": 0.25}],
	"p2eq_002": [{"atk": 12}, {"atk": 24}, {"atk": 40}],
	"p2eq_003": [{"atk": 8, "armorPen": 5, "crit": 0.15}, {"atk": 14, "armorPen": 7, "crit": 0.25}, {"atk": 30, "armorPen": 10, "crit": 0.40}],
	"p2eq_004": [{"atk": 15, "crit": 0.25, "_lifestealPct": 5}, {"atk": 30, "crit": 0.35, "_lifestealPct": 9}, {"atk": 90, "crit": 0.60, "_lifestealPct": 15}],
	"p2eq_005": [{"atk": 14, "_lifestealPct": 4, "_maxEnergy": 20}, {"atk": 30, "_lifestealPct": 7, "_maxEnergy": 20}, {"atk": 50, "_lifestealPct": 10, "_maxEnergy": 20}],
	"p2eq_006": [{"atk": 18, "armorPen": 6}, {"atk": 40, "armorPen": 12}, {"atk": 90, "armorPen": 20}],
	"p2eq_007": [{"atk": 5, "hp": 20}, {"atk": 10, "hp": 45}, {"atk": 20, "hp": 100}],
	"p2eq_008": [{"atk": 8, "armorPen": 4, "magicPen": 4}, {"atk": 15, "armorPen": 8, "magicPen": 8}, {"atk": 30, "armorPen": 12, "magicPen": 12}],
	"p2eq_009": [{"atk": 12, "_maxEnergy": 20}, {"atk": 25, "_maxEnergy": 20}, {"atk": 40, "_maxEnergy": 20}],
	"p2eq_010": [{"atk": 30, "armorPen": 10, "hp": 50}, {"atk": 75, "armorPen": 18, "hp": 120}, {"atk": 200, "armorPen": 30, "hp": 1300}],
	# ── 剑系 011 (饮血护符坠) ──
	"p2eq_011": [{"atk": 10, "_lifestealPct": 15, "healAmp": 15, "shieldAmp": 15}, {"atk": 23, "_lifestealPct": 24, "healAmp": 24, "shieldAmp": 24}, {"atk": 40, "_lifestealPct": 33, "healAmp": 33, "shieldAmp": 33}],
	# ── 盾系 012-017 ──
	"p2eq_012": [{"hp": 40, "def": 5}, {"hp": 70, "def": 10}, {"hp": 100, "def": 18}],
	"p2eq_013": [{"hp": 60, "reflectPct": 8}, {"hp": 110, "reflectPct": 11}, {"hp": 200, "reflectPct": 15}],
	"p2eq_014": [{"hp": 80, "def": 14, "mr": 14}, {"hp": 160, "def": 25, "mr": 25}, {"hp": 600, "def": 50, "mr": 50}],
	"p2eq_015": [{"hp": 50, "reflectPct": 10}, {"hp": 80, "reflectPct": 17}, {"hp": 130, "reflectPct": 25}],
	"p2eq_016": [{"def": 6, "mr": 6}, {"def": 13, "mr": 13}, {"def": 21, "mr": 21}],
	"p2eq_017": [{"hp": 150, "def": 15, "mr": 15}, {"hp": 250, "def": 35, "mr": 35}, {"hp": 4000, "def": 150, "mr": 150}],
	# ── 盾系 018-021 (批3) ──
	"p2eq_018": [{"hp": 50, "mr": 8, "healAmp": 5, "shieldAmp": 5}, {"hp": 70, "mr": 13, "healAmp": 13, "shieldAmp": 13}, {"hp": 100, "mr": 18, "healAmp": 20, "shieldAmp": 20}],
	"p2eq_019": [{"def": 5, "mr": 10}, {"def": 10, "mr": 15}, {"def": 16, "mr": 21}],
	"p2eq_020": [{"hp": 100, "def": 3, "mr": 3, "_echargePct": 10}, {"hp": 140, "def": 4, "mr": 4, "_echargePct": 10}, {"hp": 210, "def": 6, "mr": 6, "_echargePct": 10}],
	"p2eq_021": [{"hp": 60, "_maxEnergy": 20}, {"hp": 100, "_maxEnergy": 20}, {"hp": 180, "_maxEnergy": 20}],
	# ── 杖系/元素 022-025,028,029 (批4) ──
	"p2eq_022": [{"atk": 8, "_echargePct": 10}, {"atk": 15, "_echargePct": 10}, {"atk": 25, "_echargePct": 10}],
	"p2eq_023": [{"hp": 40, "atk": 10, "magicPen": 5}, {"hp": 60, "atk": 25, "magicPen": 8}, {"hp": 80, "atk": 40, "magicPen": 13}],
	"p2eq_024": [{"atk": 30, "magicPen": 15, "_maxEnergy": 20}, {"atk": 55, "magicPen": 25, "_maxEnergy": 20}, {"atk": 300, "magicPen": 50, "_maxEnergy": 20}],
	"p2eq_025": [{"atk": 25}, {"atk": 35}, {"atk": 55}],
	"p2eq_028": [{"hp": 30, "magicPen": 5}, {"hp": 40, "magicPen": 9}, {"hp": 60, "magicPen": 14}],
	"p2eq_029": [{"hp": 50, "def": 9}, {"hp": 110, "def": 15}, {"hp": 150, "def": 25}],
	# ── 潮汐系 041/042/044/047 + 枪械 055/058 (批6) ──
	"p2eq_041": [{"hp": 40, "shieldHealPct": 10}, {"hp": 90, "shieldHealPct": 15}, {"hp": 170, "shieldHealPct": 20}],
	"p2eq_042": [{"hp": 60, "shieldHealPct": 20}, {"hp": 100, "shieldHealPct": 25}, {"hp": 180, "shieldHealPct": 30}],
	"p2eq_044": [{"hp": 40, "def": 5}, {"hp": 60, "def": 12}, {"hp": 90, "def": 20}],
	"p2eq_047": [{"hp": 100}, {"hp": 200}, {"hp": 700}],
	"p2eq_055": [{"atk": 9, "_maxEnergy": 20}, {"atk": 15, "_maxEnergy": 20}, {"atk": 21, "_maxEnergy": 20}],
	"p2eq_058": [{"atk": 17, "_maxEnergy": 20}, {"atk": 29, "_maxEnergy": 20}, {"atk": 41, "_maxEnergy": 20}],
	# ── 召唤系 037/038/040 + 潮汐 045 (批7) ──
	"p2eq_037": [{"atk": 10, "hp": 80}, {"atk": 25, "hp": 130}, {"atk": 40, "hp": 180}],
	"p2eq_038": [{"hp": 80}, {"hp": 140}, {"hp": 200}],
	"p2eq_040": [{"hp": 100}, {"hp": 200}, {"hp": 500}],
	"p2eq_045": [{"hp": 90, "def": 4, "mr": 4}, {"hp": 170, "def": 8, "mr": 8}, {"hp": 300, "def": 15, "mr": 15}],
	# ── 枪械系 048/050/051/057 (批8, on_cast 连射) ──
	"p2eq_048": [{"atk": 12}, {"atk": 25}, {"atk": 41}],
	"p2eq_050": [{"atk": 20, "armorPen": 5}, {"atk": 50, "armorPen": 11}, {"atk": 120, "armorPen": 18}],
	"p2eq_051": [{"atk": 16, "armorPen": 3, "_lifestealPct": 4}, {"atk": 28, "armorPen": 6, "_lifestealPct": 6}, {"atk": 42, "armorPen": 10, "_lifestealPct": 9}],
	"p2eq_057": [{"atk": 18, "armorPen": 10}, {"atk": 30, "armorPen": 16}, {"atk": 70, "armorPen": 30}],
	# ── 枪械049连发弩/053霰弹/054瞄准镜 + 独立059沙漏 (批9) ──
	"p2eq_049": [{"atk": 15, "crit": 0.15}, {"atk": 32, "crit": 0.25}, {"atk": 50, "crit": 0.40}],
	"p2eq_053": [{"atk": 14, "crit": 0.10}, {"atk": 25, "crit": 0.15}, {"atk": 41, "crit": 0.25}],
	"p2eq_054": [{"atk": 10, "crit": 0.15, "critDmg": 0.10}, {"atk": 15, "crit": 0.25, "critDmg": 0.15}, {"atk": 20, "crit": 0.40, "critDmg": 0.20}],
	"p2eq_059": [{"hp": 100, "_echargePct": 10}, {"hp": 210, "_echargePct": 10}, {"hp": 1000, "_echargePct": 10}],   # 沙漏: +生命 + 龟能充能+10%(echarge_perm×1.1); 主动=JoJo时停(登场10s触发, _eq_hourglass_timestop)
	# ── 杖系026雷电/027电棍/030·031水晶球 + 潮汐043海浪护符 (批10) ──
	"p2eq_026": [{"magicPen": 8}, {"magicPen": 13}, {"magicPen": 20}],
	"p2eq_027": [{"hp": 20, "def": 5, "mr": 5}, {"hp": 40, "def": 8, "mr": 8}, {"hp": 80, "def": 13, "mr": 13}],
	"p2eq_030": [{"atk": 7, "hp": 20, "magicPen": 5}, {"atk": 12, "hp": 40, "magicPen": 8}, {"atk": 20, "hp": 80, "magicPen": 13}],
	"p2eq_031": [{"atk": 7, "hp": 20, "magicPen": 3}, {"atk": 12, "hp": 40, "magicPen": 6}, {"atk": 20, "hp": 80, "magicPen": 10}],
	"p2eq_043": [{"hp": 80, "shieldHealPct": 10}, {"hp": 200, "shieldHealPct": 20}, {"hp": 5000, "shieldHealPct": 30}],
	# ── 召唤034玩偶小熊 (批12, 召唤大熊fighter — spawn管线在BattleScene) ──
	"p2eq_034": [{"atk": 20, "hp": 120}, {"atk": 50, "hp": 250}, {"atk": 300, "hp": 1000}],
	# ── 召唤039竹制弓箭 + 枪械052左轮 (批11) ──
	"p2eq_039": [{"hp": 80}, {"hp": 140}, {"hp": 200}],
	"p2eq_052": [{"atk": 40, "armorPen": 15}, {"atk": 90, "armorPen": 24}, {"atk": 500, "armorPen": 50}],
	# ── 召唤035黄铜齿轮 (批12, 死亡钩子) ──
	"p2eq_035": [{"hp": 100, "atk": 5}, {"hp": 130, "atk": 13}, {"hp": 180, "atk": 22}],
	# ── 召唤036温泉蛋 (批13, 复用孵化进度) ──
	"p2eq_036": [{"hp": 70}, {"hp": 120}, {"hp": 180}],
	# ── 潮汐046幽灵墨鱼 (批14, 复用_roll_dodge) ──
	"p2eq_046": [{"hp": 80}, {"hp": 140}, {"hp": 400}],
	# ── 枪械056飞镖 (批15, 复用_knockedUpThisTurn击飞靶子) ──
	"p2eq_056": [{"atk": 45}, {"atk": 90}, {"atk": 400}],
	# ── 召唤032唤灵骨符(纯属性) + 033复活海螺(复用e_conch死亡变虫) (批16) ──
	"p2eq_032": [{"hp": 50}, {"hp": 60}, {"hp": 70}],
	"p2eq_033": [{"hp": 110}, {"hp": 270}, {"hp": 3000}],
}


## 治疗 helper: base 经携带者 healAmp + 接收者已有逻辑放大, 加到 hp (capped), 返实际回血量。
static func _heal(target: Dictionary, amount: float) -> int:
	if amount <= 0.0 or not target.get("alive", false):
		return 0
	var amp: float = 1.0 + float(target.get("healAmp", 0.0)) / 100.0
	var amt: int = roundi(amount * amp)
	var lb: int = int(target.get("hp", 0))
	target["hp"] = mini(int(target.get("maxHp", 0)), lb + amt)
	var _healed: int = int(target.get("hp", 0)) - lb
	# 饰品[续航]溢出转盾 (规格#552): 满血仍受治疗 → 溢出量转护盾, 无上限。在留盾前算溢出。
	if target.get("_p2AccessoryOverflowShield", false):
		var overflow: int = amt - _healed
		if overflow > 0:
			target["shield"] = int(target.get("shield", 0)) + overflow
	if _healed > 0 and float(target.get("_tideHealShieldPct", 0.0)) > 0.0:   # 潮汐·治疗留盾(审计)
		Buffs.grant_shield(target, roundi(float(_healed) * float(target.get("_tideHealShieldPct", 0.0))))
	return _healed


## 逐星基础属性加到 fighter (mirror equipment_runtime._add_atk 等字段约定: 写 base + 同步当前值)。
## 战中合星: 调整 fighter【基础】属性 ±装备属性 (sign=+1装上/-1卸下), StatsRecalc.recalc 从 base 重建 live。
##   走 base 字段(baseAtk/_baseCrit/...)而非 live (避免与 buff 互撞/快照重算坑)。
##   注: 不处理逐件特殊状态(_p2Harden/血盾上限/010横扫技 等); 带这类的罕见装备战中合星属性需 F5 核。
static func merge_restat(f: Dictionary, item_id: String, star: int, sign: float) -> void:
	var arr: Array = STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		return
	var st: Dictionary = arr[i]
	if st.has("atk"): f["baseAtk"] = int(f.get("baseAtk", 0)) + roundi(sign * float(st["atk"]))
	if st.has("hp"):
		f["maxHp"] = maxi(1, int(f.get("maxHp", 0)) + roundi(sign * float(st["hp"])))
		f["hp"] = clampi(int(f.get("hp", 0)) + roundi(sign * float(st["hp"])), 1, int(f["maxHp"]))
	if st.has("crit"): f["_baseCrit"] = maxf(0.0, float(f.get("_baseCrit", f.get("crit", 0.0))) + sign * float(st["crit"]))
	if st.has("armorPen"): f["_baseArmorPen"] = int(f.get("_baseArmorPen", f.get("armorPen", 0))) + roundi(sign * float(st["armorPen"]))
	if st.has("magicPen"): f["magicPen"] = int(f.get("magicPen", 0)) + roundi(sign * float(st["magicPen"]))
	if st.has("_lifestealPct"): f["_lifestealPct"] = int(f.get("_lifestealPct", 0)) + roundi(sign * float(st["_lifestealPct"]))
	if st.has("_maxEnergy"): f["_maxEnergy"] = int(f.get("_maxEnergy", 0)) + roundi(sign * float(st["_maxEnergy"]))
	if st.has("def"): f["baseDef"] = int(f.get("baseDef", 0)) + roundi(sign * float(st["def"]))
	if st.has("mr"): f["baseMr"] = int(f.get("baseMr", 0)) + roundi(sign * float(st["mr"]))
	if st.has("reflectPct"): f["reflectPct"] = float(f.get("reflectPct", 0.0)) + sign * float(st["reflectPct"])
	if st.has("healAmp"): f["healAmp"] = float(f.get("healAmp", 0.0)) + sign * float(st["healAmp"])
	if st.has("shieldAmp"): f["shieldAmp"] = float(f.get("shieldAmp", 0.0)) + sign * float(st["shieldAmp"])
	if st.has("shieldHealPct"): f["shieldHealPct"] = float(f.get("shieldHealPct", 0.0)) + sign * float(st["shieldHealPct"])
	if st.has("critDmg"): f["_extraCritDmgPerm"] = float(f.get("_extraCritDmgPerm", 0.0)) + sign * float(st["critDmg"])


static func apply_stats(f: Dictionary, item_id: String, star: int, scale: float = 1.0) -> void:
	var arr: Array = STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		return
	var st: Dictionary = arr[i]
	if scale != 1.0:   # 017 熔装备进锚: 原属性 × meltPct (锚星 25/50/1000%)
		var st_s: Dictionary = {}
		for k in st:
			st_s[k] = (roundi(float(st[k]) * scale) if st[k] is int else float(st[k]) * scale)
		st = st_s
	if st.has("atk"):
		f["baseAtk"] = int(f.get("baseAtk", 0)) + int(st["atk"])
		f["atk"] = f["baseAtk"]
	if st.has("hp"):
		f["maxHp"] = int(f.get("maxHp", 0)) + int(st["hp"])
		f["hp"] = int(f.get("hp", 0)) + int(st["hp"])
	if st.has("crit"):
		f["crit"] = float(f.get("crit", 0.0)) + float(st["crit"])
	if st.has("armorPen"):
		f["armorPen"] = int(f.get("armorPen", 0)) + int(st["armorPen"])
	if st.has("magicPen"):
		f["magicPen"] = int(f.get("magicPen", 0)) + int(st["magicPen"])
	if st.has("_lifestealPct"):
		f["_lifestealPct"] = int(f.get("_lifestealPct", 0)) + int(st["_lifestealPct"])
	if st.has("_maxEnergy"):
		f["_maxEnergy"] = int(f.get("_maxEnergy", 0)) + int(st["_maxEnergy"])
	if st.has("def"):
		f["baseDef"] = int(f.get("baseDef", 0)) + int(st["def"])
		f["def"] = f["baseDef"]
	if st.has("mr"):
		f["baseMr"] = int(f.get("baseMr", 0)) + int(st["mr"])
		f["mr"] = f["baseMr"]
	if st.has("reflectPct"):
		f["reflectPct"] = float(f.get("reflectPct", 0.0)) + float(st["reflectPct"])
	if st.has("healAmp"):
		f["healAmp"] = float(f.get("healAmp", 0.0)) + float(st["healAmp"])
	if st.has("shieldAmp"):
		f["shieldAmp"] = float(f.get("shieldAmp", 0.0)) + float(st["shieldAmp"])
	if st.has("shieldHealPct"):
		f["shieldHealPct"] = float(f.get("shieldHealPct", 0.0)) + float(st["shieldHealPct"])
	if st.has("critDmg"):
		f["_extraCritDmgPerm"] = float(f.get("_extraCritDmgPerm", 0.0)) + float(st["critDmg"])

	# ── 逐件被动 flag (受击/施法/回合钩子读) ──
	var si: int = clampi(star, 1, 3) - 1
	match item_id:
		"p2eq_011":  # 饮血护符坠: 溢出治疗 → 血护盾 (cap)
			f["_p2BloodShieldCap"] = [200, 350, 500][si]
		"p2eq_012":  # 龟苓膏块: 回合开始 +护盾
			f["_p2TurnShield"] = [30, 40, 55][si]
		"p2eq_013":  # 炙烤海胆: 受击硬化 +def/mr (cap20), 满层 → 护盾; 3★ 满层把累积护甲魔抗分给全队(一次)
			f["_p2HardenInc"] = [1.0, 1.5, 2.0][si]
			f["_p2HardenShieldVal"] = [50, 60, 80][si]
			f["_p2HardenStacks"] = 0
			f["_p2HardenGiven"] = false
			f["_p2HardenTeamShare"] = (si == 2)   # 仅3★: 叠满20层 → 把累积(20×inc)护甲魔抗给全队友军
			f["_p2HardenTeamGiven"] = false
		"p2eq_014":  # 深海堡垒甲: 受击硬化(无满层盾) + 施法汲取 (on_cast)
			f["_p2HardenInc"] = [1.0, 1.5, 2.0][si]
			f["_p2HardenShieldVal"] = 0
			f["_p2HardenStacks"] = 0
		"p2eq_015":  # 荆棘海胆: 反伤转真伤 + 反伤施流血 (flag, 反伤系统读)
			f["_p2ReflectTrue"] = true
			f["_p2ReflectBleed"] = [2.0, 2.5, 3.0][si]
		"p2eq_016":  # 铁壁盾: 每段受伤减flat + 回合开始全队盾
			f["_p2DmgReduce"] = [2, 4, 6][si]
			f["_p2TeamShield"] = [15, 20, 25][si]
		"p2eq_017":  # 不沉之锚: 免击飞/斩杀 + 受击奶最低血友军 + 沉锚充能 (on_cast)
			f["_p2AnchorImmune"] = true
			f["_p2AnchorHealPct"] = [1.0, 2.0, 15.0][si]
			f["_p2AnchorAccum"] = 0.0
			f["_p2AnchorCharges"] = 0
		"p2eq_019":  # 海葵药膏: 累计治疗 → 海葵层
			f["_p2AnemoneHeal"] = 0.0
		"p2eq_020":  # 哑铃: 锻炼层
			f["_p2DumbbellLayers"] = 0
		"p2eq_023":  # 灼热火珊瑚 3★: 主动 = 满法力对全敌各60灼烧 (无能量系统则每N回合)。计数器供 fallback。
			if si == 2:
				f["_p2FireCoralTurnCtr"] = 0
		"p2eq_024":  # 龙蛋: 装备即 3 层吐息
			f["_p2DragonStacks"] = 3
		"p2eq_037":  # 蛋糕蜡烛: 三阶段循环 (0熄灭/1微弱/2燃烧), on_side_end 推进
			f["_p2CandlePhase"] = 0
		"p2eq_044":  # 深海项链: 首次<50%回血触发标记
			f["_p2AmuletUsed"] = false
		"p2eq_045":  # 珍珠耳环: 首次<50%回血+火球触发标记
			f["_p2PearlUsed"] = false
		"p2eq_054":  # 瞄准镜: 携带者伤害不被闪避 (闪避系统读 _cannotBeDodged)
			f["_cannotBeDodged"] = true
		"p2eq_039":  # 竹制弓箭: 生长充能数 (3★ 可触发3次)
			f["_p2BambooCharges"] = [1, 1, 3][si]
		"p2eq_052":  # 左轮: 装弹6发 (敌死+1上限6, on_death 补)
			f["_p2RevolverBullets"] = 6
		"p2eq_035":  # 黄铜齿轮: 齿轮层 (每回合+N, 携带者死亡→每齿轮+2深海币)
			f["_p2Gears"] = 0
		"p2eq_036":  # 温泉蛋: 复用phase1孵化进度(_incubatorProgress, 死亡+10/+15自动); 满级→全队均摊护盾(一次)
			f["_incubatorProgress"] = 0
			f["_incubatorTempLevel"] = 0
			f["_p2IncubShieldTotal"] = [300, 400, 600][si]
			f["_p2IncubShieldGiven"] = false
		"p2eq_046":  # 幽灵墨鱼: 永久闪避buff(复用dodge系统) + 闪避时给永久护盾(skill_handlers._roll_dodge 读 _p2GhostShield)
			Buffs.add(f, "dodge", [15, 25, 50][si], 999, "refresh")
			f["_p2GhostShield"] = [30, 50, 120][si]
		"p2eq_033":  # 复活海螺: 阵亡变小虫(复用phase1 e_conch死亡变形, BattleScene死亡口读_equipConch); 逐星小虫属性
			f["_equipConch"] = true
			f["_conchUsed"] = false
			f["_conchWormHp"] = [150, 200, 300][si]
			f["_conchWormAtk"] = [20, 30, 40][si]
			if si == 2:
				f["_conchWormSplit"] = true   # 3★: 变虫后每回合分裂 (BattleScene._split_conch_worms; 持过e_conch变形)
		"p2eq_047":  # 重击锤: ATK += maxHp×pct, 随 maxHp 成长【动态】(stats_recalc 算, 镜 phase1 e_hammer; 原静态一次定=偏弱)
			f["_p2HammerAtkPct"] = float(f.get("_p2HammerAtkPct", 0.0)) + [0.04, 0.06, 0.15][si]
		"p2eq_027":  # 电棍: 电击层 (镜 phase1 e_stun_baton 初始3层)
			f["_p2BatonCharges"] = 3


# ── helper: 取某 fighter 在 all_fighters 的索引 (effects.target_idx 用) ──
static func _idx(all_fighters: Array, f: Dictionary) -> int:
	return all_fighters.find(f)


# ── helper: 对一个目标造一发"派生"物理/真伤 (apply_raw 不再过护甲, 用于已是最终值的溅射/处决) ──
static func _raw_hit(all_fighters: Array, target: Dictionary, amount: int, dmg_type: String, is_crit: bool) -> Dictionary:
	var r: Dictionary = Damage.apply_raw_damage(target, amount, dmg_type)
	var shown: int = int(r["hpLoss"]) + int(r["shieldAbs"])
	return {"target_idx": _idx(all_fighters, target), "value": shown, "kind": "damage", "dmg_type": dmg_type, "is_crit": is_crit}


# ── helper: 走完整 calc (过护甲/穿透/暴击) 对目标造一发技能伤害 ──
static func _skill_hit(all_fighters: Array, attacker: Dictionary, target: Dictionary, raw: float, dmg_type: String) -> Dictionary:
	var dmg: int = Damage.calc_damage(attacker, target, raw, dmg_type)
	var r: Dictionary = Damage.apply_raw_damage(target, dmg, dmg_type)
	var shown: int = int(r["hpLoss"]) + int(r["shieldAbs"])
	return {"target_idx": _idx(all_fighters, target), "value": shown, "kind": "damage", "dmg_type": dmg_type, "is_crit": false}


# ── helper: 给一条伤害 effect 标记直线投射物 VFX (BattleScene on_side_end 分发 _fire_projectile) ──
#   tex_path=投射物贴图, size=显示高度(px), dur=飞行时长(s)。1:1 复用 phase-1 装备弹道协议字段。
static func _attach_projectile(eff: Dictionary, from_idx: int, tex_path: String, size: float, dur: float) -> void:
	eff["vfx"] = "projectile"
	eff["vfx_from"] = from_idx
	eff["vfx_path"] = tex_path
	eff["vfx_size"] = size
	eff["vfx_dur"] = dur


# ── helper: 给一条剑系伤害 effect 标记【斩击弧】月牙刃光 VFX (BattleScene 效果循环消费 _play_slash_at) ──
#   from_idx=携带者idx (刀光方向 携带者→目标), color=刃光色(#hex), scale=弧大小。视觉=月牙斩, 数值不动。
static func _attach_slash(eff: Dictionary, all_fighters: Array, carrier: Dictionary, color: String = "#e8eef5", scale: float = 1.0) -> void:
	eff["vfx"] = "slash"
	eff["vfx_from"] = _idx(all_fighters, carrier)
	eff["vfx_color"] = color
	eff["vfx_scale"] = scale


# ══════════════════════════════════════════════════════════════════
# 【枪系弹道/激光 VFX 标记】(批2: 048/049/050/051/057/058)
#   枪系伤害走 on_cast/on_hit → p2_extra → _coalesce_multihit_segments(只并 kind=="damage")。
#   多发同目标弹道(048/050/057 等)会被并段, 并段时丢 vfx 字段 → 弹道演出会丢。
#   解法: 弹道/激光/贯穿 VFX 用【独立 passive 标记 effect】承载(kind=="passive" 不被并段),
#   与伤害 effect 分开 append。BattleScene on_cast 消费循环按 vfx 分发后 continue(标记不飘字)。
#   全部复用现有 primitive (_fire_projectile 直线弹 / _play_laser_beam 光束), 不下外部素材, 数值不动。
# ══════════════════════════════════════════════════════════════════
# 枪口弹珠贴图 (复用左轮子弹) / 弩箭贴图 (复用猎人箭).
const GUN_BULLET_TEX := "res://assets/sprites/vfx/revolver-bullet.png"
const GUN_BOLT_TEX := "res://assets/sprites/vfx/hunter-arrow.png"

## 一发直线弹/弩箭弹道标记: 从 from_idx 沿直线飞向 target (枪口火光 + 直线弹珠). fire-and-forget, 不飘字.
##   tex=弹珠/弩箭贴图, size=显示高度px, dur=飞行时长s, delay=发射前延迟s (连发逐发错开 stagger, 让每颗都看得到).
static func _gun_shot_marker(all_fighters: Array, carrier: Dictionary, target: Dictionary, tex: String, size: float, dur: float, delay: float = 0.0) -> Dictionary:
	return {
		"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "",
		"vfx": "gunshot", "vfx_from": _idx(all_fighters, carrier),
		"vfx_path": tex, "vfx_size": size, "vfx_dur": dur, "vfx_delay": delay,
	}

## 激光束标记 (051 激光手枪/057 狙击): 从 carrier 朝 target 射一道光束 (颜色/粗细/时长可调). fire-and-forget.
##   color=#hex 束色 (051 红 / 057 青白细). width=束宽px. dur=持续s. pierce=贯穿到屏幕边缘(狙击穿透感, 057 用).
static func _gun_beam_marker(all_fighters: Array, carrier: Dictionary, target: Dictionary, color: String, width: float, dur: float, pierce: bool = false) -> Dictionary:
	return {
		"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "",
		"vfx": "laserbeam", "vfx_from": _idx(all_fighters, carrier),
		"vfx_color": color, "vfx_width": width, "vfx_dur": dur, "vfx_pierce": pierce,
	}

## 贯穿弹道标记 (058 穿甲遗弹): 从 carrier 穿过 front 命中身后 behind 的一道贯穿光弹.
##   front=被普攻的最前敌(穿透起点参考), behind=身后同列敌(终点). 视觉=一条穿透线弹珠飞过 front 打到 behind.
static func _gun_pierce_marker(all_fighters: Array, carrier: Dictionary, behind: Dictionary) -> Dictionary:
	return {
		"target_idx": _idx(all_fighters, behind), "kind": "passive", "label": "",
		"vfx": "gunpierce", "vfx_from": _idx(all_fighters, carrier),
		"vfx_path": GUN_BULLET_TEX,
	}


## ── helper: 给一发【投射物伤害 effect】标 arrival_delay = 发射延迟 + 飞行时长 ──
##   投射物(枪弹/弩箭/霰弹弹珠) 是纯视觉飞行 (travel ~0.16~0.45s), 但伤害 effect 默认 delay 0 →
##   血/飘字在子弹落地【前】就掉, 与子弹脱节。stamp arrival_delay 后, BattleScene 效果循环把该 effect 的
##   飘字+血条 step 延到子弹落地时刻才显 (数值不动, 只推迟显示时机)。launch=发射前错开延迟, travel=飞行时长。
##   多发同目标会被 _coalesce_multihit_segments 并段: 并段时取该组最小 arrival 当基线, 段内 stagger 仍逐段错开。
static func _stamp_arrival(eff: Dictionary, launch: float, travel: float) -> Dictionary:
	eff["arrival_delay"] = maxf(0.0, launch) + maxf(0.0, travel)
	return eff


## ── helper: 多弹武器【每颗子弹】伤害 effect ── (霰弹053/加特林050/手铳048/连发弩049 等一次多颗)
##   = _stamp_arrival(各颗自己的 arrival_delay) + no_coalesce 标记 → 不被 _coalesce_multihit_segments 并段。
##   用户要求: 十几颗子弹从龟中心打出, 按【各自命中时刻】逐颗各掉各血+各飘字, 不合并成一次掉血。
##   每颗的 arrival_delay = launch(发射前错开) + travel(飞行时长), 同目标多颗也因 launch 逐颗错峰 →
##   BattleScene 效果循环走【单发投射 arrival_delay 路径】把飘字/血条 step/juice 各自延到落地时刻 (数值不动)。
static func _stamp_bullet(eff: Dictionary, launch: float, travel: float) -> Dictionary:
	eff["arrival_delay"] = maxf(0.0, launch) + maxf(0.0, travel)
	eff["no_coalesce"] = true   # 多弹: 每颗独立显示, 绕过并段
	return eff


# ── helper: 存活敌人列表 (按 side 区分) ──
static func _enemies(all_fighters: Array, owner: Dictionary) -> Array:
	var out: Array = []
	for x in all_fighters:
		if x is Dictionary and x.get("alive", false) and x.get("side", "") != owner.get("side", ""):
			out.append(x)
	return out


# ══════════════════════════════════════════════════════════════════
# 【剑·回响】(类型·剑 激活 2/4/6 → 回响 1/2/3 次)
#   携带剑的宠物, 其【剑系装备】触发伤害效果后, 再以 50% 伤害把该次效果回响 N 次。
#   回响伤害【不触发任何装备效果】(无嵌套回响 / 无后续 proc): 因回响 effect 由各剑钩子 append 进
#   返回的 fx, 走 BattleScene 的 p2_extra 路径在 proc 循环【之后】flush → 天然不再被扫 on_hit/on_cast。
#   规格: docs/specs/类型效果-实装规格.md #543。N 由 Phase2Types.apply_team_start 标到 _swordEchoCount。
#
#   用法: 剑系钩子产出伤害后, 把【本次产出的伤害 effect 子数组】传进来, 返回回响 effect(已含伤害结算),
#   调用方 append 即可。echo 用 _raw_hit 直接落 50% 已结算伤害值 (≠重走 calc): 与原伤害严格半价,
#   不重复过护甲/暴击 (规格"以50%的伤害效果触发", 是伤害值减半而非重算)。
# ══════════════════════════════════════════════════════════════════
# 剑系装备里【产出伤害】的 id (回响只包裹这些; 001 在 on_turn_begin, 005/009 在 on_hit, 006/007 在 on_cast)。
#   010 激光长刃=纯属性无主动伤害钩子, 不在此列。p2eq-types.json 映射: 剑=001/005/006/007/009/010。
const SWORD_ECHO_IDS := {"p2eq_001": true, "p2eq_005": true, "p2eq_006": true, "p2eq_007": true, "p2eq_009": true}

static func sword_echo(produced: Array, attacker: Dictionary, all_fighters: Array) -> Array:
	var fx: Array = []
	if not (attacker is Dictionary):
		return fx
	var n: int = int(attacker.get("_swordEchoCount", 0))
	if n <= 0:
		return fx
	for eff in produced:
		if not (eff is Dictionary) or str(eff.get("kind", "")) != "damage":
			continue
		var ti: int = int(eff.get("target_idx", -1))
		if ti < 0 or ti >= all_fighters.size():
			continue
		var orig_val: int = int(eff.get("value", 0))
		if orig_val <= 0:
			continue
		var dt: String = str(eff.get("dmg_type", "physical"))
		var tgt: Dictionary = all_fighters[ti]
		# 回响 N 次, 每次以原伤害 50% 落 (raw, 不再过护甲/暴击/proc); 目标已死则停 (回响打不出额外死亡连锁)。
		for _i in range(n):
			if not (tgt is Dictionary) or not tgt.get("alive", false):
				break
			var echo_amt: int = maxi(1, roundi(float(orig_val) * 0.5))
			var ee: Dictionary = _raw_hit(all_fighters, tgt, echo_amt, dt, false)
			if int(ee.get("value", 0)) > 0:
				ee["vfx"] = "swordecho"   # 剑[回响]: 目标处斩击弧 VFX (BattleScene 效果循环消费)
				ee["vfx_from"] = all_fighters.find(attacker)   # 携带者idx → 刃光方向(carrier→target)
				fx.append(ee)
	return fx


# ══════════════════════════════════════════════════════════════════
# 【枪·神枪手 金弹】(类型·枪 激活 2/3/5 → 每射满 4/3/2 发额外 1 发金弹)
#   每把枪独立子弹计数(owner._gunBullets[枪id])。枪每射满 N 发 → 额外射 1 发金弹(不计入计数,
#   金弹不再生成金弹), 金弹 = 与原子弹效果完全相同(伤害+流血/减甲等附带继承) + 额外 60/80/100% 真伤,
#   跟随触发它那发子弹的目标。规格 #549。_gunTier 由 Phase2Types.apply_team_start 标(1/2/3 = 2/3/5件)。
#
#   用法: 枪系钩子【每发子弹命中后】调 gun_fire_shot(owner, gun_id, target, all, base_raw, dmg_type)。
#   它累加该枪计数; 满 N → 返回金弹 effect(已含金弹伤害结算+附带), 调用方 append。未满返 []。
# ══════════════════════════════════════════════════════════════════
# 枪满档阈值(每射满 N 发出金弹): tier 1/2/3 → 4/3/2。
static func _gun_threshold(tier: int) -> int:
	return [4, 3, 2][clampi(tier, 1, 3) - 1]
# 金弹额外真伤系数: tier 1/2/3 → 0.60/0.80/1.00。
static func _gun_gold_pct(tier: int) -> float:
	return [0.60, 0.80, 1.00][clampi(tier, 1, 3) - 1]

## 某把枪射 1 发后调: 累加计数, 满阈值 → 返回金弹效果(同子弹伤害 + 附带 + 额外真伤), 否则 []。
##   base_raw = 这发子弹的原始伤害值(未过护甲, 与该枪 _skill_hit 同口径)。金弹对【同一目标 target】结算。
static func gun_fire_shot(owner: Dictionary, gun_id: String, target: Dictionary, all_fighters: Array, base_raw: float, dmg_type: String) -> Array:
	var fx: Array = []
	var tier: int = int(owner.get("_gunTier", 0))
	if tier <= 0 or not (owner.get("_gunBullets") is Dictionary):
		return fx   # 枪羁绊未激活 → 无金弹
	var bullets: Dictionary = owner["_gunBullets"]
	var n: int = int(bullets.get(gun_id, 0)) + 1
	var thr: int = _gun_threshold(tier)
	if n < thr:
		bullets[gun_id] = n
		return fx
	bullets[gun_id] = 0   # 满阈值 → 清零(金弹不计入计数, 不会再生成金弹)
	if not (target is Dictionary) or not target.get("alive", false):
		return fx
	# 金弹: 同子弹伤害(走完整 calc, 与原子弹一致) + 该枪附带效果 + 额外 60/80/100% 真伤。
	var gold: Dictionary = _skill_hit(all_fighters, owner, target, base_raw, dmg_type)
	gold["vfx"] = "goldbullet"   # 金色子弹 VFX (BattleScene: 金色子弹弹道)
	gold["vfx_from"] = all_fighters.find(owner)   # 枪携带者idx → 金弹弹道起点(owner→target)
	_stamp_arrival(gold, 0.0, 0.20)   # 金弹 travel 0.20s → 血跟金弹落地才掉
	fx.append(gold)
	var dealt: int = int(gold.get("value", 0))
	# 该枪原本子弹的附带效果(减甲/流血)在金弹上继承一份。
	match gun_id:
		"p2eq_050":   # 加特林: 永久 -护甲 (继承原 on_cast 减甲, 固定 3)
			if target.get("alive", false):
				target["baseDef"] = int(target.get("baseDef", 0)) - 3
				target["def"] = target["baseDef"]
		"p2eq_051", "p2eq_052":   # 激光手枪/左轮: 流血 (按金弹实伤的一部分)
			if target.get("alive", false) and dealt > 0:
				Dot.apply_stacks(target, "bleed", maxi(1, roundi(float(dealt) * 0.3)))
	# 额外真伤 = gold_pct × 金弹实际造成伤害。
	if dealt > 0 and target.get("alive", false):
		var extra: int = maxi(1, roundi(float(dealt) * _gun_gold_pct(tier)))
		var ge: Dictionary = _raw_hit(all_fighters, target, extra, "true", false)
		ge["vfx"] = "goldbullet"
		ge["vfx_from"] = all_fighters.find(owner)   # 金弹额外真伤段同弹道起点
		_stamp_arrival(ge, 0.0, 0.20)   # 金弹额外真伤段同弹道 → 血跟金弹落地才掉
		fx.append(ge)
	return fx


# ══════════════════════════════════════════════════════════════════
# 【法器·法力】helpers — 法力(mana) ≠ 龟能(energy)！独立字段 _staff_mana={装备id:当前值}。
#   绝不读写 _energy/_maxEnergy。满档(100/80/60, 按 _staffTier 1/2/3)→ 该法器触发 → 清空该条。
#   累积口: round_begin +25 · 携带者技能伤害×0.1 · 受伤×0.1。法器效果自身伤害不计(防连放)。
#   规格: docs/specs/类型效果-实装规格.md #551。tier 由 Phase2Types.apply_team_start 标到 _staffTier。
#
#   本次范围: 法力【追踪+显示】+ 023 灼热火珊瑚改用法力门控(满法力→全敌灼烧)。
#   TODO(待确认行为再做): 其余 4 件法器(030/031 迷你水晶球A/B · 029 冰封水母 · 026 雷电法杖)
#     现有触发(on_cast/on_hit 概率/层数)尚【未】改成"法力满才触发"。改造需对齐各自现有触发交互,
#     待用户确认门控细节后, 用 staff_ready()/staff_clear() 包裹其触发即可(法力已在累积)。
# ══════════════════════════════════════════════════════════════════

# 法器满档(触发阈值): tier(法器激活档 1/2/3 = 2/4/6件)→ 100/80/60。
static func _staff_mana_cap(f: Dictionary) -> int:
	return [100, 80, 60][clampi(int(f.get("_staffTier", 0)), 1, 3) - 1]

# 该 fighter 是否有法力系统(携带法器且法器激活, apply_team_start 已开 _staff_mana 条)。
static func _has_staff(f: Dictionary) -> bool:
	return f is Dictionary and int(f.get("_staffTier", 0)) > 0 and (f.get("_staff_mana") is Dictionary)

# 给该 fighter 的【每件法器】法力条 +amount(各自独立, 同步累积, 不超满档)。
#   ⚠ 只动 _staff_mana, 绝不碰 _energy/_maxEnergy。
static func staff_add_mana(f: Dictionary, amount: float) -> void:
	if not _has_staff(f) or amount <= 0.0:
		return
	var cap: int = _staff_mana_cap(f)
	var sm: Dictionary = f["_staff_mana"]
	for sid in sm.keys():
		sm[sid] = mini(cap, int(sm[sid]) + roundi(amount))

# 回合开始: 每件法器 +25 法力。
static func staff_round_begin(f: Dictionary) -> void:
	staff_add_mana(f, 25.0)

# 携带者打出技能伤害(原始伤害值之和)→ ×0.1 入每件法器法力。法器效果自身伤害【不】走这里。
static func staff_on_skill_damage(f: Dictionary, total_dmg: float) -> void:
	staff_add_mana(f, total_dmg * 0.1)

# 携带者受伤(实际承受值)→ ×0.1 入每件法器法力。
static func staff_on_damaged(f: Dictionary, dmg_taken: float) -> void:
	staff_add_mana(f, dmg_taken * 0.1)

# 某件法器法力是否满档(可触发)。
static func staff_ready(f: Dictionary, staff_id: String) -> bool:
	if not _has_staff(f):
		return false
	var sm: Dictionary = f["_staff_mana"]
	return sm.has(staff_id) and int(sm[staff_id]) >= _staff_mana_cap(f)

# 触发后清空该件法器法力条(重新积累)。
static func staff_clear(f: Dictionary, staff_id: String) -> void:
	if _has_staff(f) and (f["_staff_mana"] as Dictionary).has(staff_id):
		f["_staff_mana"][staff_id] = 0


# ══════════════════════════════════════════════════════════════════
# 【盾·守护 怒气冲击波】(类型·盾 激活 2/3/4/5)
#   携带盾的宠物每次【受到伤害】→ +(身上盾件数)怒气; 累计满 10 → 消耗全部, 对敌方一个单位
#   释放冲击波 = thr×目标最大生命 真伤 + 自获 thr×自身最大生命 护盾。thr = 4/5/6/8% (按盾激活档)。
#   ⚠ 每个【伤害实例】调一次 (≠每件盾装备), 由 BattleScene 承伤口调用; 怒气是【携带者级】非每盾。
#   规格: docs/specs/类型效果-实装规格.md #546。flag(_shieldRageThr/_shieldPieces/_shieldRage) 由 Phase2Types.apply_team_start 标。
# ══════════════════════════════════════════════════════════════════
static func shield_rage_on_damaged(owner: Dictionary, all_fighters: Array) -> Array:
	var fx: Array = []
	if not (owner is Dictionary) or not owner.get("alive", false):
		return fx
	var thr: float = float(owner.get("_shieldRageThr", 0.0))
	if thr <= 0.0:
		return fx   # 无盾羁绊 → 不积怒气
	var pieces: int = maxi(1, int(owner.get("_shieldPieces", 1)))
	owner["_shieldRage"] = int(owner.get("_shieldRage", 0)) + pieces
	while int(owner.get("_shieldRage", 0)) >= 10:
		owner["_shieldRage"] = int(owner["_shieldRage"]) - 10
		# 对敌方一个单位 (优先前排) 释放冲击波: thr×目标maxHp 真伤。
		var enemies: Array = _enemies(all_fighters, owner)
		if not enemies.is_empty():
			var tgt: Dictionary = _front_most(enemies)
			var dmg: int = maxi(1, roundi(float(tgt.get("maxHp", 0)) * thr))
			var sw_e: Dictionary = _raw_hit(all_fighters, tgt, dmg, "true", false)
			sw_e["vfx"] = "shockwave"   # 盾[守护]怒气冲击波: 目标处扩散冲击波环 VFX (BattleScene 效果循环消费)
			sw_e["vfx_from"] = _idx(all_fighters, owner)   # 冲击波源(携带者)idx
			fx.append(sw_e)
		# 自获 thr×自身maxHp 护盾 (经 grant_shield → 吃护盾增幅/疲惫统一收口)。
		var sv: int = roundi(float(owner.get("maxHp", 0)) * thr)
		if sv > 0:
			var sg: int = Buffs.grant_shield(owner, sv)
			fx.append({"target_idx": _idx(all_fighters, owner), "value": sg, "kind": "shield", "vfx": "shieldgain"})   # 自身护盾光 VFX
	return fx


# ── helper: 孵化器进度 (036) — +delta 进度(满100升临时Lv+5%基础, cap3, 1:1 phase1 _incubator_add); 满级→全队均摊护盾(一次) ──
# (内联进度数学, 不 preload EquipmentRuntime — 跨脚本 preload 成环。与 BattleScene 死亡口的 _incubator_add 同逻辑, 共用 _incubatorProgress/_incubatorTempLevel 字段保持一致。)
static func _p2_incub_tick(f: Dictionary, all_fighters: Array, delta: int) -> Array:
	var fx: Array = []
	if delta > 0 and f.has("_incubatorProgress"):
		f["_incubatorProgress"] = int(f.get("_incubatorProgress", 0)) + delta
		while int(f["_incubatorProgress"]) >= 100 and int(f.get("_incubatorTempLevel", 0)) < 3:
			f["_incubatorProgress"] = int(f["_incubatorProgress"]) - 100
			f["_incubatorTempLevel"] = int(f.get("_incubatorTempLevel", 0)) + 1
			var atk_b: int = roundi(int(f.get("baseAtk", 0)) * 0.05)
			var def_b: int = roundi(int(f.get("baseDef", 0)) * 0.05)
			var mr_b: int = roundi(int(f.get("baseMr", f.get("baseDef", 0))) * 0.05)
			var hp_b: int = roundi(int(f.get("maxHp", 0)) * 0.05)
			f["baseAtk"] = int(f.get("baseAtk", 0)) + atk_b
			f["atk"] = f["baseAtk"]
			f["baseDef"] = int(f.get("baseDef", 0)) + def_b
			f["def"] = f["baseDef"]
			f["baseMr"] = int(f.get("baseMr", f.get("baseDef", 0))) + mr_b
			f["mr"] = f["baseMr"]
			f["maxHp"] = int(f.get("maxHp", 0)) + hp_b
			f["hp"] = int(f.get("hp", 0)) + hp_b
	if int(f.get("_incubatorTempLevel", 0)) >= 3 and not f.get("_p2IncubShieldGiven", false):
		f["_p2IncubShieldGiven"] = true
		var allies: Array = []
		for a in all_fighters:
			if a is Dictionary and a.get("alive", false) and a.get("side", "") == f.get("side", ""):
				allies.append(a)
		if not allies.is_empty():
			var per: int = int(round(float(f.get("_p2IncubShieldTotal", 0)) / float(allies.size())))
			for a in allies:
				var sg: int = Buffs.grant_shield(a, per)
				fx.append({"target_idx": _idx(all_fighters, a), "value": sg, "kind": "shield", "vfx": "shieldglow"})   # 满级全队盾光
	return fx


# ── helper: 链式闪电 (026 雷电法杖) — jumps 跳, 每跳随机不重复敌 dmg_per 魔法 ──
static func _p2_lightning_chain(caster: Dictionary, all_fighters: Array, jumps: int, dmg_per: float) -> Array:
	var fx: Array = []
	var hit: Array = []
	var prev_idx: int = _idx(all_fighters, caster)   # 链起点 = 携带者 (供 chainbolt VFX 画首段)
	var chain_i: int = 0   # 第几跳 (0-based) → BattleScene 据此给逐跳递增延时 (1:1 PoC idx*220ms 链式逐跳)
	for _j in range(jumps):
		var pool: Array = []
		for e in _enemies(all_fighters, caster):
			if not hit.has(e):
				pool.append(e)
		if pool.is_empty():
			pool = _enemies(all_fighters, caster)   # 敌不够 → 允许重复跳
		if pool.is_empty():
			break
		var tg: Dictionary = pool[randi() % pool.size()]
		hit.append(tg)
		var eff: Dictionary = _skill_hit(all_fighters, caster, tg, dmg_per, "magic")
		eff["vfx"] = "chainbolt"   # BattleScene 据此画 prev→tg 锯齿闪电 (1:1 PoC drawLightningBolt)
		eff["vfx_from"] = prev_idx
		eff["chain_idx"] = chain_i   # 跳序 → 渲染时延 chain_idx*0.22s 错峰亮起 (链式逐跳观感)
		fx.append(eff)
		prev_idx = _idx(all_fighters, tg)
		chain_i += 1
	return fx


# ── helper: 水晶光束 (030/031 迷你水晶球) — 每目标 dmg_per 魔法 + 水晶层, 满3引爆 detonate_pct×maxHp ──
static func _p2_crystal_beam(caster: Dictionary, all_fighters: Array, targets: Array, dmg_per: float, detonate_pct: float, splash: bool) -> Array:
	var fx: Array = []
	for tg in targets:
		if not (tg is Dictionary) or not tg.get("alive", false):
			continue
		fx.append(_skill_hit(all_fighters, caster, tg, dmg_per, "magic"))
		tg["_p2CrystalStacks"] = int(tg.get("_p2CrystalStacks", 0)) + 1
		if int(tg["_p2CrystalStacks"]) >= 3 and tg.get("alive", false):
			tg["_p2CrystalStacks"] = 0
			var expl: float = float(tg.get("maxHp", 0)) * detonate_pct
			fx.append(_skill_hit(all_fighters, caster, tg, expl, "magic"))
			if splash:   # 3★ 引爆范围+50%: 邻格敌也受 50% 引爆
				for adj in SlotHelpers.adjacent_fighters(all_fighters, tg):
					if adj is Dictionary and adj.get("alive", false) and adj.get("side", "") != caster.get("side", ""):
						fx.append(_skill_hit(all_fighters, caster, adj, expl * 0.5, "magic"))
	return fx


# ════════════════════════════════════════════════════════════════════
# on_hit — 逐段命中后 (dmg = 该段已落 HP 损失)。
#   p2eq_002 海带卷刀 (流血) / p2eq_003 锋利鲨齿 (溅射) / p2eq_004 暴君之牙 (处决)
#   p2eq_005 双生匕首 (追击) / p2eq_009 宽刃弯刀 (刃能)。
# ════════════════════════════════════════════════════════════════════
static func on_hit(attacker: Dictionary, target: Dictionary, dmg: int, item_id: String, star: int, all_fighters: Array, _is_first: bool, rng: RandomNumberGenerator = null) -> Array:
	var fx: Array = []
	if dmg <= 0 or not target.get("alive", false):
		return fx
	var t: int = clampi(star, 1, 3)
	var is_aoe: bool = attacker.get("_castIsAoe", false)

	# ── 弓箭[神射手]羁绊处决 (复用暴君之牙处决机制) ──
	#   携带弓箭(_archerExecBase 由 Phase2Types.apply_team_start 标), 目标 hp% < 斩杀线 → 处决。
	#   斩杀线 = base + crit×0.1。该 on_hit 每件 p2 装备各调一次, 处决幂等 (处决后 target.alive=false, 下次早退)。
	if float(attacker.get("_archerExecBase", 0.0)) > 0.0:
		var arch_line: float = float(attacker.get("_archerExecBase", 0.0)) + float(attacker.get("crit", 0.0)) * 0.1
		var arch_hp_pct: float = float(target.get("hp", 0)) / maxf(1.0, float(target.get("maxHp", 1)))
		if arch_hp_pct < arch_line and int(target.get("hp", 0)) > 0 \
				and not target.get("_p2AnchorImmune", false) and target.get("side", "") != attacker.get("side", ""):
			var arch_e: Dictionary = _raw_hit(all_fighters, target, int(target.get("hp", 0)), "true", true)   # 真伤抹掉剩余血 = 处决
			arch_e["vfx"] = "execute"   # 弓箭[神射手]处决: 目标处白闪斩首 VFX (BattleScene 效果循环消费)
			fx.append(arch_e)
			return fx

	match item_id:
		"p2eq_002":
			# 海带卷刀: 每段施加 X×ATK 流血 (0.075/0.1/0.15); AOE 技能效果 ×50%。
			var scale: float = [0.075, 0.1, 0.15][t - 1]
			var amt: float = float(attacker.get("atk", 0)) * scale
			if is_aoe:
				amt *= 0.5
			var stacks: int = maxi(1, roundi(amt))
			Dot.apply_stacks(target, "bleed", stacks)
			# 血滴溅射 VFX 标记 (普攻施流血 — 纯视觉, passive kind 不被并段)。
			fx.append({"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "", "vfx": "blood"})

		"p2eq_003":
			# 锋利鲨齿: 每段溅射邻格单位 X%×原伤害 物理 (15/28/50)。
			var pct: float = [0.15, 0.28, 0.50][t - 1]
			var splash: int = roundi(float(dmg) * pct)
			# 撕咬白闪 VFX 标记 (主命中目标处 — 锐齿撕咬, 纯视觉 passive 不被并段)。
			fx.append({"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "", "vfx": "bite"})
			if splash > 0:
				for adj in SlotHelpers.adjacent_fighters(all_fighters, target):
					if adj is Dictionary and adj.get("alive", false):
						var e: Dictionary = _raw_hit(all_fighters, adj, splash, "physical", false)
						if int(e["value"]) > 0:
							# 溅射弧 VFX 标记 (邻格受溅射处 _play_aoe_ring 白弧 — 独立 passive 不被并段吞 vfx)。
							fx.append({"target_idx": _idx(all_fighters, adj), "kind": "passive", "label": "", "vfx": "splashring"})
							fx.append(e)

		"p2eq_004":
			# 暴君之牙: 伤害处决 HP<斩杀线 单位; 斩杀线 = base + coef×暴击率。
			#   处决 → 回 20 龟能 (非龟能单位回 40 生命)。
			var base_line: float = [0.05, 0.07, 0.10][t - 1]
			var coef: float = [0.10, 0.15, 0.40][t - 1]
			var line: float = base_line + coef * float(attacker.get("crit", 0.0))
			var hp_pct: float = float(target.get("hp", 0)) / maxf(1.0, float(target.get("maxHp", 1)))
			# 不沉之锚 017 免疫斩杀 → 不被处决
			if hp_pct < line and int(target.get("hp", 0)) > 0 and not target.get("_p2AnchorImmune", false):
				var remain: int = int(target.get("hp", 0))
				var exec4: Dictionary = _raw_hit(all_fighters, target, remain, "true", true)   # 真伤抹掉剩余血 = 处决
				exec4["vfx"] = "execute"   # 暴君之牙处决: 目标处斩首白闪 VFX (复用 _play_execute_flash; 同弓箭神射手)
				fx.append(exec4)
				if int(attacker.get("_maxEnergy", 0)) > 0:
					attacker["_energy"] = mini(int(attacker.get("_maxEnergy", 0)), int(attacker.get("_energy", 0)) + 20)
				else:
					var lb: int = int(attacker.get("hp", 0))
					attacker["hp"] = mini(int(attacker.get("maxHp", 0)), lb + 40)
					var healed: int = int(attacker.get("hp", 0)) - lb
					if healed > 0:
						fx.append({"target_idx": _idx(all_fighters, attacker), "value": healed, "kind": "heal", "vfx": "healglow"})   # 暴君处决回血绿光 (原无 vfx)

		"p2eq_005":
			# 双生匕首: 每段 X% 概率追加双生刺击 Y×ATK 物理 (50%/0.7 · 75%/0.8 · 100%/1.0)。
			var prob: float = [0.5, 0.75, 1.0][t - 1]
			var scale2: float = [0.7, 0.8, 1.0][t - 1]
			var roll: float = rng.randf() if rng != null else randf()
			if roll < prob:
				var e005: Dictionary = _skill_hit(all_fighters, attacker, target, float(attacker.get("atk", 0)) * scale2, "physical")
				_attach_slash(e005, all_fighters, attacker, "#cfe0f0", 0.85)   # 双生匕首: 追加双生刺斩击弧 (钢蓝小刃)
				fx.append(e005)

		"p2eq_009":
			# 宽刃弯刀: 每段攻击充能 N 刃能 (AOE×50%); 满100 → 消耗对【命中目标所在列】敌人每人
			#   (M真实 + K×ATK物理); 只命中1敌则该列伤害 ×倍率。
			var gain: float = ([20.0, 20.0, 25.0][t - 1] + float(int(attacker.get("_coralShards", 0))) * 3.0) * (0.5 if is_aoe else 1.0)  # 珊瑚×碎片
			attacker["_p2BladeCharge"] = float(attacker.get("_p2BladeCharge", 0.0)) + gain
			if float(attacker["_p2BladeCharge"]) >= 100.0:
				attacker["_p2BladeCharge"] = float(attacker["_p2BladeCharge"]) - 100.0
				var true_amt: int = [30, 45, 60][t - 1]
				var atk_scale: float = [0.5, 0.7, 0.9][t - 1]
				var solo_mult: float = [2.0, 2.5, 3.0][t - 1]
				# 命中目标所在【一列】= 同排 {front-0/1/2} 的存活敌人 (用户定义: 列=F0+F1+F2 同排)
				var col: Array = []
				for c in SlotHelpers.same_row_fighters(all_fighters, target):
					if c is Dictionary and c.get("alive", false) and c.get("side", "") != attacker.get("side", ""):
						col.append(c)
				if not col.has(target):
					col.append(target)
				var mult: float = solo_mult if col.size() <= 1 else 1.0
				for c in col:
					var part_true: int = roundi(float(true_amt) * mult)
					var part_phys: float = float(attacker.get("atk", 0)) * atk_scale * mult
					fx.append(_raw_hit(all_fighters, c, part_true, "true", false))
					var e009: Dictionary = _skill_hit(all_fighters, attacker, c, part_phys, "physical")
					_attach_slash(e009, all_fighters, attacker, "#9fe8ff", 1.0)   # 宽刃弯刀: 月牙刃能弧扫一列 (青能量刃)
					fx.append(e009)

		"p2eq_023":
			# 灼热火珊瑚: 每段攻击 +灼烧 (5+7%ATK)/(7+11%ATK)/(10+15%ATK)
			fx.append({"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "", "vfx": "flameburst"})   # 火焰喷溅 VFX 标记 (每段灼烧 — 纯视觉)
			Dot.apply_stacks(target, "burn", maxi(1, roundi([5.0, 7.0, 10.0][t - 1] + [0.07, 0.11, 0.15][t - 1] * float(attacker.get("atk", 0))) + int(attacker.get("_coralShards", 0))))  # 珊瑚×碎片

		"p2eq_029":
			# 冰封水母: 额外魔法 + 冻结眩晕1回合(已晕不叠) + 成功冻结→携带者护盾。
			#   法器满法力→ 满档(staff_ready)必触发、放完清空该法力条 (白填条修, 范式同 023)。
			#   无法器系统→ fallback: X%概率触发 (原行为)。
			var fire29: bool = false
			if _has_staff(attacker):
				if staff_ready(attacker, "p2eq_029"):
					staff_clear(attacker, "p2eq_029")
					fire29 = true
			else:
				var roll29: float = rng.randf() if rng != null else randf()
				fire29 = roll29 < [0.20, 0.25, 0.30][t - 1]
			if fire29:
				fx.append(_skill_hit(all_fighters, attacker, target, float([10, 15, 25][t - 1]), "magic"))
				# 冰晶爆 + 冻结青蓝罩 VFX 标记 (额外魔法触发 — 纯视觉, passive kind 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "", "vfx": "freeze"})
				if not Buffs.has(target, "stun"):
					Buffs.add(target, "stun", 1, 2, "ignore")
					var sg29: int = Buffs.grant_shield(attacker, [20, 30, 50][t - 1])
					if sg29 > 0:
						fx.append({"target_idx": _idx(all_fighters, attacker), "value": sg29, "kind": "shield", "vfx": "shieldglow"})   # 成功冻结→携带者盾光

		"p2eq_055":
			# 靶向器: 命中→标记目标2回合(markedDmg, 受伤+20%)
			Buffs.add(target, "markedDmg", 20, 3, "refresh")
			# 标记准星/红圈 VFX 标记 (目标处红色准星十字 — 独立 passive 不被并段)。
			fx.append({"target_idx": _idx(all_fighters, target), "kind": "passive", "label": "", "vfx": "reticle"})

		"p2eq_058":
			# 穿甲遗弹: 每段伤害溅射身后目标(fighter_behind) (25/40/60%)×原伤害 物理
			var behind58 = SlotHelpers.fighter_behind(all_fighters, target)
			if behind58 != null and behind58 is Dictionary and behind58.get("alive", false):
				var e58: Dictionary = _raw_hit(all_fighters, behind58, roundi(float(dmg) * [0.25, 0.40, 0.60][t - 1]), "physical", false)
				if int(e58["value"]) > 0:
					fx.append(_gun_pierce_marker(all_fighters, attacker, behind58))   # 贯穿弹道: 穿透前敌打到身后同列敌
					fx.append(_stamp_arrival(e58, 0.0, 0.24))   # 血跟贯穿弹落地才掉 (_play_gun_pierce travel 0.24s)

		"p2eq_026":
			# 雷电法杖: 链式闪电跳 N 个不重复敌各 X 魔法。
			#   法器满法力(_staffTier>0)→ 满档(staff_ready)放电、放完清空该法力条 (白填条修, 范式同 023)。
			#   无法器系统(单件无羁绊)→ fallback: 每段充能 +25(AOE+12.5), 满100 放一道、保留溢出。
			var jumps26: int = [4, 5, 6][t - 1] + int(attacker.get("_coralShards", 0))  # 珊瑚×碎片
			var dmg26: float = [20.0, 25.0, 30.0][t - 1]
			if _has_staff(attacker):
				if staff_ready(attacker, "p2eq_026"):
					staff_clear(attacker, "p2eq_026")
					fx.append_array(_p2_lightning_chain(attacker, all_fighters, jumps26, dmg26))
			else:
				var inc26: float = 12.5 if is_aoe else 25.0
				attacker["_p2LightningCharge"] = float(attacker.get("_p2LightningCharge", 0.0)) + inc26
				while float(attacker.get("_p2LightningCharge", 0.0)) >= 100.0:
					attacker["_p2LightningCharge"] = float(attacker["_p2LightningCharge"]) - 100.0
					fx.append_array(_p2_lightning_chain(attacker, all_fighters, jumps26, dmg26))

		"p2eq_036":
			# 温泉蛋: 每段造成伤害 ×0.1 → 孵化进度 (满级→全队均摊护盾)。
			fx.append_array(_p2_incub_tick(attacker, all_fighters, maxi(0, roundi(float(dmg) * 0.1))))

	# 剑[回响]: 剑系 on_hit 装备(005双生追击/009宽刃刃能)产出伤害后 → 50%回响 N 次(不触发proc)。规格#543。
	if SWORD_ECHO_IDS.has(item_id) and int(attacker.get("_swordEchoCount", 0)) > 0:
		fx.append_array(sword_echo(fx, attacker, all_fighters))
	return fx


# ════════════════════════════════════════════════════════════════════
# on_cast — 携带者释放技能后一次 (整段技能伤害结算后)。
#   p2eq_006 千刃风暴 (排穿全体) / p2eq_007 锈蚀阔剑 (横排+护盾) / p2eq_008 双穿珊瑚刺 (最远敌)。
# ════════════════════════════════════════════════════════════════════
static func on_cast(caster: Dictionary, item_id: String, star: int, all_fighters: Array, rng: RandomNumberGenerator = null) -> Array:
	var fx: Array = []
	if not caster.get("alive", false):
		return fx
	var t: int = clampi(star, 1, 3)
	var atk: float = float(caster.get("atk", 0))
	var enemies: Array = _enemies(all_fighters, caster)
	if enemies.is_empty():
		return fx

	match item_id:
		"p2eq_011":
			# 饮血护符坠: 连斩 N 次随机敌, 每次 (base+coef×ATK) 物理, 后续 ×(1-decay)^i 衰减。
			var hits: int = [5, 6, 8][t - 1]
			var sbase: float = [40.0, 50.0, 70.0][t - 1]
			var scoef: float = [0.5, 0.7, 1.0][t - 1]
			var decay: float = [0.11, 0.08, 0.04][t - 1]
			var mult: float = 1.0
			for _h in range(hits):
				var al: Array = _enemies(all_fighters, caster)
				if al.is_empty():
					break
				var ridx: int = (rng.randi() if rng != null else randi()) % al.size()
				var e011: Dictionary = _skill_hit(all_fighters, caster, al[ridx], (sbase + scoef * atk) * mult, "physical")
				_attach_slash(e011, all_fighters, caster, "#ff5a5a", 1.0)   # 饮血护符坠: 连斩斩击弧 (吸血红光)
				fx.append(e011)
				mult *= (1.0 - decay)

		"p2eq_014":
			# 深海堡垒甲: 施法后对全体敌人汲取生命, 每敌 (coef×def + coef×mr) 魔法; 每汲取一个回 X 生命。
			var dcoef: float = [0.8, 1.0, 1.5][t - 1]
			var heal_each: int = [40, 65, 130][t - 1]
			var draw_raw: float = dcoef * float(caster.get("def", 0)) + dcoef * float(caster.get("mr", 0))
			var total_heal: int = 0
			for e in enemies:
				# 魔法吸取束 VFX 标记 (敌→携带者 紫 Line2D 汲取束 — 独立 passive 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, caster), "kind": "passive", "label": "", "vfx": "drainbeam", "vfx_from": _idx(all_fighters, e)})
				fx.append(_skill_hit(all_fighters, caster, e, draw_raw, "magic"))
				total_heal += heal_each
			if total_heal > 0:
				var lb0: int = int(caster.get("hp", 0))
				caster["hp"] = mini(int(caster.get("maxHp", 0)), lb0 + total_heal)
				var hh: int = int(caster.get("hp", 0)) - lb0
				if hh > 0:
					fx.append({"target_idx": _idx(all_fighters, caster), "value": hh, "kind": "heal", "vfx": "healglow"})   # 汲取回血绿光

		"p2eq_006":
			# 千刃风暴: 1排剑穿过【全体敌方】, 每敌 (base + coef×ATK) 物理。
			var base: float = [70.0, 100.0, 400.0][t - 1]
			var coef: float = [0.8, 1.3, 4.0][t - 1]
			for e in enemies:
				var e006: Dictionary = _skill_hit(all_fighters, caster, e, base + coef * atk, "physical")
				_attach_slash(e006, all_fighters, caster, "#eef4ff", 1.0)   # 千刃风暴: 每敌一道月牙弧 → 排扫剑刃风暴 (亮钢白)
				fx.append(e006)

		"p2eq_007":
			# 锈蚀阔剑: 斩击【一横排】= 最前敌人所在列的 {front-N, back-N} (用户定义: 横排=F0+B0 同列前后);
			#   每敌 (base + coef×ATK) 物理; 获本次总伤害 X% 护盾。
			var base2: float = [20.0, 35.0, 60.0][t - 1]
			var coef2: float = [0.5, 0.8, 1.1][t - 1]
			var shield_pct: float = [0.5, 0.75, 1.0][t - 1]
			var anchor: Dictionary = _front_most(enemies)
			var hrow: Array = []
			for c in SlotHelpers.same_column_fighters(all_fighters, anchor):
				if c is Dictionary and c.get("alive", false) and c.get("side", "") != caster.get("side", ""):
					hrow.append(c)
			if hrow.is_empty():
				hrow = [anchor]
			var total: int = 0
			for e in hrow:
				var ed: Dictionary = _skill_hit(all_fighters, caster, e, base2 + coef2 * atk, "physical")
				_attach_slash(ed, all_fighters, caster, "#caa46a", 1.15)   # 锈蚀阔剑: 重剑横劈大月牙弧 (锈金, 护盾光留批3)
				total += int(ed["value"])
				fx.append(ed)
			if total > 0:
				var sg007: int = Buffs.grant_shield(caster, roundi(float(total) * shield_pct))   # 走收口(吃shieldAmp+疲惫), 原直加绕过
				fx.append({"target_idx": _idx(all_fighters, caster), "value": sg007, "kind": "shield", "vfx": "shieldglow"})   # 锈蚀阔剑 自身护盾光

		"p2eq_008":
			# 双穿珊瑚刺: 对【相距携带者最远】的敌人, (1.x×ATK 物理 + Y%目标最大生命 魔法)。
			var atk_scale: float = [1.0, 1.2, 1.5][t - 1]
			var maxhp_pct: float = [0.08, 0.12, 0.18][t - 1] + 0.02 * float(int(caster.get("_coralShards", 0)))  # 珊瑚×碎片
			var far: Dictionary = _farthest(caster, enemies)
			if not far.is_empty():
				# 珊瑚长刺穿刺射线 VFX 标记 (携带者→最远敌 细长珊瑚刺 Line2D — 独立 passive 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, far), "kind": "passive", "label": "", "vfx": "coralpierce", "vfx_from": _idx(all_fighters, caster)})
				fx.append(_skill_hit(all_fighters, caster, far, atk * atk_scale, "physical"))
				var magic_raw: float = float(far.get("maxHp", 0)) * maxhp_pct
				fx.append(_skill_hit(all_fighters, caster, far, magic_raw, "magic"))

		"p2eq_017":
			# 不沉之锚: 施法后消耗1沉锚充能 → 击飞最前敌 (coef(def+mr)+pct×maxHp 物理) + 眩晕1回合。
			if int(caster.get("_p2AnchorCharges", 0)) > 0:
				var tgt17: Dictionary = _front_most(enemies)
				if not tgt17.is_empty() and not tgt17.get("_p2AnchorImmune", false):
					caster["_p2AnchorCharges"] = int(caster.get("_p2AnchorCharges", 0)) - 1
					var acoef: float = [0.4, 0.6, 3.0][t - 1]
					var ahp: float = [0.15, 0.25, 0.70][t - 1]
					var raw17: float = acoef * float(caster.get("def", 0)) + acoef * float(caster.get("mr", 0)) + ahp * float(tgt17.get("maxHp", 0))
					# 铁锚砸击 + 锚链 VFX 标记 (携带者→最前敌 下砸冲击 + 锚链 Line2D — 独立 passive 不被并段)。
					fx.append({"target_idx": _idx(all_fighters, tgt17), "kind": "passive", "label": "", "vfx": "anchorslam", "vfx_from": _idx(all_fighters, caster)})
					fx.append(_skill_hit(all_fighters, caster, tgt17, raw17, "physical"))
					if tgt17.get("alive", false) and not tgt17.get("_eggImmune", false):
						tgt17["_knockedUpThisTurn"] = true        # 击飞标记 (视觉juggle需BattleScene补, F5); 龟蛋免击飞
						Buffs.add(tgt17, "stun", 1, 2, "ignore")   # 眩晕1回合 (duration2=跳1回合); 龟蛋免控(Buffs.add已中心拦)

		"p2eq_055":
			# 靶向器: 施法→标记最前敌2回合 (markedDmg, 受伤+20%); 与 on_hit 命中标记同款。
			#   on_cast 拿不到本次技能目标 → 标记最前敌 (其余 on_cast 杖件同样取 _front_most)。
			var tgt55: Dictionary = _front_most(enemies)
			if not tgt55.is_empty():
				Buffs.add(tgt55, "markedDmg", 20, 3, "refresh")
				# 标记准星/红圈 VFX 标记 (最前敌处红色准星十字 — 独立 passive 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, tgt55), "kind": "passive", "label": "", "vfx": "reticle"})

		"p2eq_028":
			# 冰霜冻露瓶: 施法后对最前敌 (40/60/100) 魔法 + 冰寒 3 回合
			var ft28: Dictionary = _front_most(enemies)
			if not ft28.is_empty():
				fx.append(_skill_hit(all_fighters, caster, ft28, float([40.0, 60.0, 100.0][t - 1]), "magic"))
				Buffs.add(ft28, "chilled", 20, 4, "refresh")
				# 冰晶/寒霜爆点 VFX 标记 (魔法+冰寒 — 纯视觉, passive kind 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, ft28), "kind": "passive", "label": "", "vfx": "freeze"})

		"p2eq_022":
			# 余烬燃油瓶: 施法后对最前敌施加 (20+10%ATK)/(35+15%)/(60+20%) 灼烧 + 真火1回合(灼烧转真伤)
			var ft22: Dictionary = _front_most(enemies)
			if not ft22.is_empty():
				Dot.apply_stacks(ft22, "burn", maxi(1, roundi([20.0, 35.0, 60.0][t - 1] + [0.10, 0.15, 0.20][t - 1] * atk) + int(caster.get("_coralShards", 0)) * 5))  # 珊瑚×碎片
				Buffs.add(ft22, "trueFire", 1, 2, "refresh")
				# 火焰喷吐 VFX 标记 (灼烧+真火 — 纯视觉, passive kind 不被并段)。
				fx.append({"target_idx": _idx(all_fighters, ft22), "kind": "passive", "label": "", "vfx": "flameburst"})

		"p2eq_048":
			# 黄铜手铳: 施法后射 N 发, 每发命中沿途首个单位(可被挡=最前敌) X×ATK 物理。
			var shots48: int = [4, 5, 6][t - 1]
			var scale48: float = [0.5, 0.54, 0.6][t - 1]
			for _s48 in range(shots48):
				var en48: Array = _enemies(all_fighters, caster)
				if en48.is_empty():
					break
				var tg48: Dictionary = _front_most(en48)
				fx.append(_gun_shot_marker(all_fighters, caster, tg48, GUN_BULLET_TEX, 16.0, 0.45, _s48 * 0.09))   # 枪口火光+直线弹珠连发 (F5: 慢飞0.45 + 逐发错开0.09s 让每颗看得到)
				fx.append(_stamp_bullet(_skill_hit(all_fighters, caster, tg48, atk * scale48, "physical"), _s48 * 0.09, 0.45))   # 每颗子弹各自落地各掉血 (no_coalesce 不并段; launch=_s48*0.09 逐颗错峰)
				fx.append_array(gun_fire_shot(caster, "p2eq_048", tg48, all_fighters, atk * scale48, "physical"))   # 枪[神枪手]金弹

		"p2eq_050":
			# 幽灵加特林: 施法后 N 发随机分布敌, 每发 X×ATK 物理 + 永久 -护甲。
			var shots50: int = [20, 30, 60][t - 1]
			var scale50: float = [0.1, 0.12, 0.14][t - 1]
			var shred50: int = [1, 2, 3][t - 1]
			for _s50 in range(shots50):
				var en50: Array = _enemies(all_fighters, caster)
				if en50.is_empty():
					break
				var tg50: Dictionary = en50[randi() % en50.size()]
				fx.append(_gun_shot_marker(all_fighters, caster, tg50, GUN_BULLET_TEX, 12.0, 0.16, _s50 * 0.025))   # 加特林密集弹幕扫射 (F5: 稍放慢0.16 + 密集错开0.025s 保扫射感)
				fx.append(_stamp_bullet(_skill_hit(all_fighters, caster, tg50, atk * scale50, "physical"), _s50 * 0.025, 0.16))   # 每颗子弹各自落地各掉血 (no_coalesce 不并段; launch=_s50*0.025 密集错峰)
				if tg50.get("alive", false):
					tg50["baseDef"] = int(tg50.get("baseDef", 0)) - shred50
					tg50["def"] = tg50["baseDef"]
				fx.append_array(gun_fire_shot(caster, "p2eq_050", tg50, all_fighters, atk * scale50, "physical"))   # 枪[神枪手]金弹

		"p2eq_051":
			# 激光手枪: 对一横排(同列 F+B)首敌 X×ATK 物理 + Y×ATK 流血; 身后敌 50%。
			var scale51: float = [1.5, 2.0, 2.8][t - 1]
			var bleed51: float = [0.5, 0.5, 0.6][t - 1]
			var front51: Dictionary = _front_most(enemies)
			if not front51.is_empty():
				var col51: Array = []
				for c in SlotHelpers.same_column_fighters(all_fighters, front51):
					if c is Dictionary and c.get("alive", false) and c.get("side", "") != caster.get("side", ""):
						col51.append(c)
				if col51.is_empty():
					col51 = [front51]
				for e51 in col51:
					var m51: float = 1.0 if e51 == front51 else 0.5
					fx.append(_gun_beam_marker(all_fighters, caster, e51, "#ff3838", 7.0, 0.30))   # 红色激光束 (从龟射向该列敌)
					fx.append(_skill_hit(all_fighters, caster, e51, atk * scale51 * m51, "physical"))
					Dot.apply_stacks(e51, "bleed", maxi(1, roundi(atk * bleed51 * m51)))
					fx.append_array(gun_fire_shot(caster, "p2eq_051", e51, all_fighters, atk * scale51 * m51, "physical"))   # 枪[神枪手]金弹

		"p2eq_057":
			# 狙击长管: 对最低血%敌开枪 X×ATK 物理; 击杀 → 立即再开一枪(递归, 上限12)。
			var scale57: float = [2.0, 3.0, 7.0][t - 1]
			var guard57: int = 0
			while guard57 < 12:
				guard57 += 1
				var en57: Array = _enemies(all_fighters, caster)
				if en57.is_empty():
					break
				var tg57: Dictionary = _lowest_hp_enemy(en57)
				fx.append(_gun_beam_marker(all_fighters, caster, tg57, "#cdfcff", 3.0, 0.22, true))   # 狙击穿透细光束: 一枪射到屏幕边缘(穿透感, F5)
				fx.append(_skill_hit(all_fighters, caster, tg57, atk * scale57, "physical"))
				fx.append_array(gun_fire_shot(caster, "p2eq_057", tg57, all_fighters, atk * scale57, "physical"))   # 枪[神枪手]金弹(金弹击杀照常连锁: 下方 while 判 tg57.alive)
				if tg57.get("alive", false):
					break   # 没击杀(含金弹也没杀) → 停火

		"p2eq_049":
			# 连发弩: 向【后排敌】每人连射 N 发, 每发按目标已损血 (0.8~1.3×ATK, 30%损时达最大)。
			var shots49: int = [1, 2, 3][t - 1]
			var back49: Array = []
			for e in enemies:
				if str(e.get("_slotKey", "")).begins_with("back"):
					back49.append(e)
			if back49.is_empty():
				back49 = enemies
			for tg49 in back49:
				for _s49 in range(shots49):
					if not tg49.get("alive", false):
						break
					var lost49: float = 1.0 - float(tg49.get("hp", 0)) / maxf(1.0, float(tg49.get("maxHp", 1)))
					var scale49: float = 0.8 + 0.5 * minf(lost49 / 0.3, 1.0)
					fx.append(_gun_shot_marker(all_fighters, caster, tg49, GUN_BOLT_TEX, 22.0, 0.20, _s49 * 0.10))   # 弩箭连射弹道 (复用猎人箭, 逐发错开0.10s)
					fx.append(_stamp_bullet(_skill_hit(all_fighters, caster, tg49, atk * scale49, "physical"), _s49 * 0.10, 0.20))   # 每发弩箭各自落地各掉血 (no_coalesce 不并段; launch=_s49*0.10 逐发错峰)

		"p2eq_053":
			# 霰弹贝古: N 发弹珠随机分布敌, 每颗 0.22×ATK 物理; 被 ≥8 发命中的敌眩晕 1 回合。
			var pellets53: int = [12, 14, 18][t - 1]
			# 霰弹扇形 VFX 标记 (BattleScene _play_shotgun_blast): 从携带者中心 40°扇形 N 发弹珠 + 枪口火光 — 装备VFX视觉规格.md
			if not _enemies(all_fighters, caster).is_empty():
				fx.append({"target_idx": _idx(all_fighters, _front_most(_enemies(all_fighters, caster))), "kind": "passive", "vfx": "shotgun", "vfx_from": _idx(all_fighters, caster), "vfx_pellets": pellets53})
			var hits53: Dictionary = {}
			for _p53 in range(pellets53):
				var en53: Array = _enemies(all_fighters, caster)
				if en53.is_empty():
					break
				var tg53: Dictionary = en53[randi() % en53.size()]
				fx.append(_stamp_bullet(_skill_hit(all_fighters, caster, tg53, atk * 0.22, "physical"), _p53 * 0.04, 0.28))   # 每颗弹珠各自落地各掉血+各飘字 (no_coalesce 不并段; launch=_p53*0.04 让十几颗逐颗错峰命中, 用户原话"按命中掉血")
				var k53: int = _idx(all_fighters, tg53)
				hits53[k53] = int(hits53.get(k53, 0)) + 1
			for k in hits53:
				if int(hits53[k]) >= 8:
					var u53 = all_fighters[k]
					if u53 is Dictionary and u53.get("alive", false):
						Buffs.add(u53, "stun", 1, 2, "ignore")

		"p2eq_027":
			# 电棍 (镜 phase1 e_stun_baton): 有电击层时施法后 → 电击随机敌 X 魔法 + 眩晕1回合, 消耗1层 (初3层, 0层停火不消失)。
			#   (phase1: 单体技打该目标/AOE随机; phase2 on_cast 拿不到本次技能目标 → 统一随机敌, 等同 AOE 分支。每次施法都眩晕, 非"攒N次")
			if int(caster.get("_p2BatonCharges", 0)) > 0 and not enemies.is_empty():
				caster["_p2BatonCharges"] = int(caster["_p2BatonCharges"]) - 1
				var tgt27: Dictionary = enemies[(rng.randi() if rng != null else randi()) % enemies.size()]
				var e27: Dictionary = _skill_hit(all_fighters, caster, tgt27, float([30.0, 40.0, 50.0][t - 1]), "magic")
				e27["vfx"] = "lightning"   # 天降闪电 VFX (BattleScene main loop _play_lightning_strike) — 1:1 phase1 e_stun_baton
				fx.append(e27)
				if tgt27.get("alive", false) and not Buffs.has(tgt27, "stun"):
					Buffs.add(tgt27, "stun", 1, 2, "ignore")

		"p2eq_030":
			# 迷你水晶球A: 沿【一列(same_row F0F1F2)】发 N 段, 每段每敌 X 魔法 + 水晶层, 满3引爆 pct×maxHp。
			#   法器满法力→ 满档(staff_ready)才放、放完清空法力条 (白填条修, 范式同 023); 无法器系统→ 每次施法都放(原行为)。
			var fire30: bool = (not _has_staff(caster)) or staff_ready(caster, "p2eq_030")
			if fire30:
				if _has_staff(caster):
					staff_clear(caster, "p2eq_030")
				var seg30: int = [2, 2, 3][t - 1] + int(caster.get("_coralShards", 0))  # 珊瑚×碎片
				var dmg30: float = [30.0, 35.0, 40.0][t - 1]
				var pct30: float = [0.14, 0.17, 0.20][t - 1]
				var anchor30: Dictionary = _front_most(enemies)
				var col30: Array = []
				for c in SlotHelpers.same_row_fighters(all_fighters, anchor30):
					if c is Dictionary and c.get("alive", false) and c.get("side", "") != caster.get("side", ""):
						col30.append(c)
				if col30.is_empty():
					col30 = [anchor30]
				for _s30 in range(seg30):
					fx.append_array(_p2_crystal_beam(caster, all_fighters, col30, dmg30, pct30, false))
				# 水晶光束 VFX 标记 (BattleScene _play_crystal_beam): 从携带者朝该列锚敌射束 — 1:1 PoC castCrystalBeam
				fx.append({"target_idx": _idx(all_fighters, anchor30), "kind": "passive", "vfx": "crystalbeam", "vfx_from": _idx(all_fighters, caster)})

		"p2eq_031":
			# 迷你水晶球B: 对【全体敌】各 X 魔法 + 水晶层, 满3引爆 pct×maxHp; 3★ 引爆范围+50%(邻格)。
			#   法器满法力→ 满档(staff_ready)才放、放完清空法力条 (白填条修, 范式同 023); 无法器系统→ 每次施法都放(原行为)。
			var fire31: bool = (not _has_staff(caster)) or staff_ready(caster, "p2eq_031")
			if fire31:
				if _has_staff(caster):
					staff_clear(caster, "p2eq_031")
				var dmg31: float = [20.0, 25.0, 30.0][t - 1] + float(int(caster.get("_coralShards", 0))) * 3.0  # 珊瑚×碎片
				var pct31: float = [0.14, 0.17, 0.20][t - 1]
				fx.append_array(_p2_crystal_beam(caster, all_fighters, _enemies(all_fighters, caster), dmg31, pct31, t >= 3))
				# 旋转扫描束 VFX 标记: 从携带者旋转180°扫全敌 — 1:1 PoC launchMiniCrystalBeam (031=旋转激光)
				fx.append({"target_idx": _idx(all_fighters, _front_most(_enemies(all_fighters, caster))), "kind": "passive", "vfx": "minicrystalbeam", "vfx_from": _idx(all_fighters, caster)})

		"p2eq_039":
			# 竹制弓箭: 持生长充能时施法后→强化攻随机敌(base+20%携带者maxHp)魔法 + 回20%maxHp + 永久+maxHp(消耗1充能)。
			if int(caster.get("_p2BambooCharges", 0)) > 0:
				caster["_p2BambooCharges"] = int(caster["_p2BambooCharges"]) - 1
				var lt39: Dictionary = enemies[randi() % enemies.size()]
				var base39: float = [25.0, 30.0, 35.0][t - 1] + 0.20 * float(caster.get("maxHp", 0))
				fx.append(_skill_hit(all_fighters, caster, lt39, base39, "magic"))
				var heal39: int = _heal(caster, 0.20 * float(caster.get("maxHp", 0)))
				if heal39 > 0:
					fx.append({"target_idx": _idx(all_fighters, caster), "value": heal39, "kind": "heal", "vfx": "healglow"})   # 竹叶强袭回血绿光 (原无 vfx)
				var perma39: int = [90, 95, 100][t - 1]
				caster["maxHp"] = int(caster.get("maxHp", 0)) + perma39
				caster["hp"] = int(caster.get("hp", 0)) + perma39
				# 竹叶龟生命球 VFX (装备VFX视觉规格.md): 绿生命球从被击敌抛物线飞回携带者(回血/永久生命) + 落点爆 + 绿拖尾
				fx.append({"target_idx": _idx(all_fighters, caster), "kind": "passive", "vfx": "bambooorb", "vfx_from": _idx(all_fighters, lt39)})

	# 剑[回响]: 剑系 on_cast 装备(006千刃排穿/007锈蚀阔剑横排)产出伤害后 → 50%回响 N 次(不触发proc)。规格#543。
	#   (on_cast 每件装备各调一次, 本次 fx 仅含该件产出 → 安全只回响本剑伤害。)
	if SWORD_ECHO_IDS.has(item_id) and int(caster.get("_swordEchoCount", 0)) > 0:
		fx.append_array(sword_echo(fx, caster, all_fighters))
	return fx


# ── 最靠前的敌人 (front 排优先, 同排取列号小; 无 front 取 back 列号小) ──
static func _front_most(enemies: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = 1.0e9
	for e in enemies:
		var is_front: bool = str(e.get("_slotKey", "")).begins_with("front")
		var score: float = (0.0 if is_front else 100.0) + float(_slot_col(e))
		if score < best_score:
			best_score = score
			best = e
	if best.is_empty() and not enemies.is_empty():
		best = enemies[0]
	return best


# ── 敌方"前排一行" = front-* 槽的存活敌人 (无前排则全体); 仅 001 劈砍"优先前排"用 ──
static func _front_row(enemies: Array) -> Array:
	var front: Array = []
	for e in enemies:
		if str(e.get("_slotKey", "")).begins_with("front"):
			front.append(e)
	return front if not front.is_empty() else enemies


# ── 相距 caster 最远的敌人 (槽距: 前后排差 + 列差; 平手取列差大者) ──
static func _farthest(caster: Dictionary, enemies: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = -1.0
	for e in enemies:
		var d: float = _slot_dist(caster, e)
		if d > best_d:
			best_d = d
			best = e
	return best


static func _slot_dist(a: Dictionary, b: Dictionary) -> float:
	# slotKey "row-col" → row(front=0/back=1), col(0/1/2)。敌我对阵: 横向距离 = 双方 row 之和 + 常量。
	var ar: int = 1 if str(a.get("_slotKey", "")).begins_with("back") else 0
	var br: int = 1 if str(b.get("_slotKey", "")).begins_with("back") else 0
	var ac: int = _slot_col(a)
	var bc: int = _slot_col(b)
	return float(ar + br) * 3.0 + absf(float(ac - bc))


static func _slot_col(f: Dictionary) -> int:
	var parts: PackedStringArray = str(f.get("_slotKey", "front-0")).split("-")
	return int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 0


# ════════════════════════════════════════════════════════════════════
# on_turn_begin — 携带者回合开始 (p2eq_001 锈蚀短剑: 劈砍1目标优先前排)。
#   返 effects (调用方负责飘字/演出)。
# ════════════════════════════════════════════════════════════════════
static func on_turn_begin(f: Dictionary, item_id: String, star: int, all_fighters: Array) -> Array:
	var fx: Array = []
	if not f.get("alive", false):
		return fx
	var t: int = clampi(star, 1, 3)
	match item_id:
		"p2eq_001":
			# 锈蚀短剑: 劈砍1目标(优先前排) (atkScale×ATK + critCoef×暴击率) 物理。
			var atk_scale: float = [0.6, 0.75, 1.0][t - 1]
			var crit_coef: float = [40.0, 60.0, 100.0][t - 1]
			var enemies: Array = _enemies(all_fighters, f)
			if enemies.is_empty():
				return fx
			var row: Array = _front_row(enemies)
			var tgt: Dictionary = row[0] if not row.is_empty() else enemies[0]
			var raw: float = float(f.get("atk", 0)) * atk_scale + crit_coef * float(f.get("crit", 0.0))
			var e001: Dictionary = _skill_hit(all_fighters, f, tgt, raw, "physical")
			_attach_slash(e001, all_fighters, f, "#c9b48a", 1.0)   # 锈蚀短剑: 单体斩击弧 (锈刃灰金)
			fx.append(e001)

		"p2eq_012":
			# 龟苓膏块: 回合开始 → 自身 +护盾 (走 grant_shield → 吃护盾增幅+疲惫统一收口)。
			var sg12: int = Buffs.grant_shield(f, [30, 40, 55][t - 1])
			fx.append({"target_idx": _idx(all_fighters, f), "value": sg12, "kind": "shield", "vfx": "shieldglow"})   # 盾光

		"p2eq_016":
			# 铁壁盾: 回合开始 → 全队(含自己)+护盾。
			var tsv: int = [15, 20, 25][t - 1] + int(f.get("_coralShards", 0)) * 5  # 珊瑚×碎片
			for a in all_fighters:
				if a is Dictionary and a.get("alive", false) and a.get("side", "") == f.get("side", ""):
					var sg16: int = Buffs.grant_shield(a, tsv)
					fx.append({"target_idx": _idx(all_fighters, a), "value": sg16, "kind": "shield", "vfx": "shieldglow"})   # 全队逐个盾光

		"p2eq_018":
			# 守护贝壳: 回合开始自回 (base + pct×maxHp), 经 healAmp。
			var h18: int = _heal(f, [30.0, 45.0, 60.0][t - 1] + [0.05, 0.09, 0.15][t - 1] * float(f.get("maxHp", 0)))
			if h18 > 0:
				fx.append({"target_idx": _idx(all_fighters, f), "value": h18, "kind": "heal", "vfx": "healglow"})   # 治疗绿光

		"p2eq_019":
			# 海葵药膏: 回合开始 自己+最低血友军 回 (base + pct×目标已损HP); 累计治疗→海葵层(每层+治疗护盾强度)。
			var b19: float = [30.0, 45.0, 60.0][t - 1]
			var p19: float = [0.12, 0.14, 0.18][t - 1]
			var thr19: float = [200.0, 180.0, 150.0][t - 1]
			var per19: float = [8.0, 9.0, 10.0][t - 1]
			var tg19: Array = [f]
			var low19: Dictionary = _lowest_hp_ally(all_fighters, f)
			if not low19.is_empty() and low19 != f:
				tg19.append(low19)
			for tg in tg19:
				var lost19: float = float(int(tg.get("maxHp", 0)) - int(tg.get("hp", 0)))
				var hh: int = _heal(tg, b19 + p19 * lost19)
				if hh > 0:
					fx.append({"target_idx": _idx(all_fighters, tg), "value": hh, "kind": "heal", "vfx": "healglow"})   # 治疗绿光 (2目标各一)
					f["_p2AnemoneHeal"] = float(f.get("_p2AnemoneHeal", 0.0)) + float(hh)
					while float(f.get("_p2AnemoneHeal", 0.0)) >= thr19:
						f["_p2AnemoneHeal"] = float(f["_p2AnemoneHeal"]) - thr19
						f["healAmp"] = float(f.get("healAmp", 0.0)) + per19
						f["shieldAmp"] = float(f.get("shieldAmp", 0.0)) + per19

		"p2eq_020":
			# 哑铃: 回合开始 +1 锻炼层 (每层 +maxHp&hp); 扔哑铃在 on_side_end。
			var g20: int = [20, 25, 30][t - 1]
			f["maxHp"] = int(f.get("maxHp", 0)) + g20
			f["hp"] = int(f.get("hp", 0)) + g20
			f["_p2DumbbellLayers"] = int(f.get("_p2DumbbellLayers", 0)) + 1

		"p2eq_021":
			# 守护贝母: 回合开始连接【伤害最高友军(ATK近似)】→ 给龟能/盾/净化/转移其受伤X%给携带者(每回合重连)。
			for a in all_fighters:
				if a is Dictionary:
					a.erase("_p2GuardLink")
			var best21: Dictionary = _highest_atk_ally(all_fighters, f)
			if not best21.is_empty():
				if int(best21.get("_maxEnergy", 0)) > 0:
					best21["_energy"] = mini(int(best21["_maxEnergy"]), int(best21.get("_energy", 0)) + 20)
				var sg21: int = Buffs.grant_shield(best21, [40, 60, 90][t - 1])
				fx.append({"target_idx": _idx(all_fighters, best21), "value": sg21, "kind": "shield", "vfx": "shieldlink", "vfx_from": _idx(all_fighters, f)})   # 连接光链 + 盾光
				_cleanse_debuffs(best21, [1, 1, 2][t - 1])
				if best21 != f:   # 不给自己挂转移链 (避免自伤循环)
					best21["_p2GuardLink"] = {"to": f, "pct": [0.25, 0.40, 0.60][t - 1]}

		"p2eq_023":
			# 灼热火珊瑚 主动(任意星级): 【这件法器自己的法力满】→ 对全敌各 60 灼烧, 放完清空该法力条。
			#   ⚠ 用 _staff_mana["p2eq_023"](法力, 独立)判定, 绝不读 _energy/_maxEnergy(龟能)。法力累积见 staff_* 钩子。
			#   法器未激活(_staffTier==0, 如单件法器无羁绊)→ 无法力系统 → 退化为每 3 回合一次 (counter fallback)。
			#   (放开任意星级: 原限 3★, 现满档即触发, 与 026/029/030/031 法器门控一致)
			var ready23: bool = false
			if _has_staff(f):
				# 满法力判定: 这件火珊瑚自己的法力条已满档 (回合开始 +25 已在本钩子前由 staff_round_begin 加)
				ready23 = staff_ready(f, "p2eq_023")
			else:
				# fallback: 法器羁绊未激活, 无法力条 → 每 3 回合一次
				f["_p2FireCoralTurnCtr"] = int(f.get("_p2FireCoralTurnCtr", 0)) + 1
				if int(f["_p2FireCoralTurnCtr"]) >= 3:
					f["_p2FireCoralTurnCtr"] = 0
					ready23 = true
			if ready23:
				if _has_staff(f):
					staff_clear(f, "p2eq_023")   # 主动消耗满法力(清空这件法器自己的法力条)
				var burn23: int = 60 + int(f.get("_coralShards", 0))   # 珊瑚×碎片
				for e23 in _enemies(all_fighters, f):
					Dot.apply_stacks(e23, "burn", burn23)
					fx.append({"target_idx": _idx(all_fighters, e23), "kind": "passive", "label": "🔥 灼烧+%d" % burn23, "vfx": "flameburst"})   # 火幕: 全敌各一团火焰喷溅 (多点火幕)

		"p2eq_024":
			# 龙蛋: 回合开始 +1 吐息, 满3层→喷火龙沿随机有敌列(同列F+B): 友回血/敌魔法+灼烧, 重置。
			f["_p2DragonStacks"] = int(f.get("_p2DragonStacks", 0)) + 1
			if int(f.get("_p2DragonStacks", 0)) >= 3:
				f["_p2DragonStacks"] = 0
				var en24: Array = _enemies(all_fighters, f)
				if not en24.is_empty():
					var atk24: float = float(f.get("atk", 0))
					var heal24: float = [70.0, 150.0, 1000.0][t - 1] + [0.7, 1.0, 2.0][t - 1] * atk24
					var mag24: float = [50.0, 120.0, 1500.0][t - 1] + [0.7, 1.0, 2.0][t - 1] * atk24
					var burn24: int = maxi(1, roundi([30.0, 50.0, 100.0][t - 1] + [0.10, 0.15, 0.15][t - 1] * atk24))
					var col24: int = _slot_col(_front_most(en24))
					for c in all_fighters:
						if not (c is Dictionary) or not c.get("alive", false) or _slot_col(c) != col24:
							continue
						if c.get("side", "") == f.get("side", ""):
							var hh24: int = _heal(c, heal24)
							if hh24 > 0:
								fx.append({"target_idx": _idx(all_fighters, c), "value": hh24, "kind": "heal", "vfx": "healglow"})   # 龙蛋整列回血绿光 (原无 vfx 静默回血)
						else:
							fx.append(_skill_hit(all_fighters, f, c, mag24, "magic"))
							Dot.apply_stacks(c, "burn", burn24)
					# 火柱横扫 VFX 标记 (BattleScene _play_fire_sweep): 龙息从携带者扫向该列最前敌 — 1:1 PoC spawnFireSweep
					fx.append({"target_idx": _idx(all_fighters, _front_most(en24)), "kind": "passive", "vfx": "firesweep", "vfx_from": _idx(all_fighters, f)})

		"p2eq_042":
			# 涟漪药剂: 回合开始为全队回 已损生命×(3/6/10%)
			# 3★: 找 hp/maxHp 比例最低的友军, 其回复 ×2 (effectDesc3 "生命最低的友军获双倍回复")。
			var allies42: Array = []
			for a42 in all_fighters:
				if a42 is Dictionary and a42.get("alive", false) and a42.get("side", "") == f.get("side", "") and not a42.get("_isEgg", false):
					allies42.append(a42)
			var low42 = null
			if t >= 3:
				var low_ratio42: float = INF
				for a42 in allies42:
					var ratio42: float = float(a42.get("hp", 0)) / float(maxi(1, int(a42.get("maxHp", 1))))
					if ratio42 < low_ratio42:
						low_ratio42 = ratio42
						low42 = a42
			for a42 in allies42:
				var heal_mult42: float = 2.0 if (t >= 3 and a42 == low42) else 1.0
				var hh42: int = _heal(a42, float(int(a42.get("maxHp", 0)) - int(a42.get("hp", 0))) * [0.03, 0.06, 0.10][t - 1] * heal_mult42)
				if hh42 > 0:
					fx.append({"target_idx": _idx(all_fighters, a42), "value": hh42, "kind": "heal", "vfx": "waterripple"})   # 水波涟漪 + 全队绿光

		"p2eq_038":
			# 信号放大器: 回合开始获本回合临时增伤 (区间随机, 取与现值大者; damage.gd _dmgBonusThisTurnPct 乘所有出伤)。
			var rng38: Array = [[10, 16], [25, 40], [70, 80]][t - 1]
			var amp38: int = rng38[0] + (randi() % (rng38[1] - rng38[0] + 1))
			f["_dmgBonusThisTurnPct"] = maxi(int(f.get("_dmgBonusThisTurnPct", 0)), amp38)
			# 信号增益光环 VFX 标记 (自身处青色脉冲环 _play_aoe_ring — 纯增益视觉, passive label 飘增伤%)。
			fx.append({"target_idx": _idx(all_fighters, f), "kind": "passive", "label": "📡 +%d%%伤害" % amp38, "color": "#5cf0ff", "vfx": "signalaura"})

		"p2eq_040":
			# FPGA 板: 回合开始随机抽 N 个 2-bit 状态 (星1/2/3 = 抽1/2/4 个), 各当回合生效。
			#   00=回5%maxHp+永久+2护甲魔抗 / 01=永久+5攻+4%生命偷取 / 10=本回合+15%增伤 / 11=本回合受伤-25%(非真伤)。
			var draws40: int = [1, 2, 4][t - 1]
			var bits40: Array = []   # 抽中的 2-bit 串 (VFX 标记显示)
			for _d40 in range(draws40):
				var roll40: int = randi() % 4
				bits40.append(["00", "01", "10", "11"][roll40])
				match roll40:
					0:  # 00
						var hh40: int = _heal(f, float(f.get("maxHp", 0)) * 0.05)
						if hh40 > 0:
							fx.append({"target_idx": _idx(all_fighters, f), "value": hh40, "kind": "heal", "vfx": "healglow"})   # FPGA 00回血绿光 (原无 vfx)
						f["baseDef"] = int(f.get("baseDef", 0)) + 2
						f["def"] = f["baseDef"]
						f["baseMr"] = int(f.get("baseMr", 0)) + 2
						f["mr"] = f["baseMr"]
					1:  # 01
						f["baseAtk"] = int(f.get("baseAtk", 0)) + 5
						f["atk"] = f["baseAtk"]
						f["_lifestealPct"] = int(f.get("_lifestealPct", 0)) + 4
					2:  # 10
						f["_dmgBonusThisTurnPct"] = maxi(int(f.get("_dmgBonusThisTurnPct", 0)), 15)
					3:  # 11
						Buffs.add(f, "dmgReduce", 25, 1, "refresh")   # 本回合受伤 -25% (非真伤; duration1=仅本回合, 对齐phase1 e_fpga:684, 原误用2多撑一回合)
			# 电路/比特闪 VFX 标记 (抽中时短电闪 + 方块粒子 — 纯视觉, passive label 飘抽中的 bit 串)。
			fx.append({"target_idx": _idx(all_fighters, f), "kind": "passive", "label": "▦ %s" % " ".join(bits40), "color": "#7df5c0", "vfx": "bitflash"})

		"p2eq_035":
			# 黄铜齿轮: 回合开始 +N 齿轮层 (死亡时每齿轮→+2深海币, on_death 结算)。
			f["_p2Gears"] = int(f.get("_p2Gears", 0)) + [1, 2, 3][t - 1]

		"p2eq_036":
			# 温泉蛋: 回合开始 +5 孵化进度 (满级→全队均摊护盾)。
			fx.append_array(_p2_incub_tick(f, all_fighters, 5))

	# 剑[回响]: 剑系 on_turn_begin 装备(001锈蚀短剑劈砍)产出伤害后 → 50%回响 N 次(不触发proc)。规格#543。
	if SWORD_ECHO_IDS.has(item_id) and int(f.get("_swordEchoCount", 0)) > 0:
		fx.append_array(sword_echo(fx, f, all_fighters))
	return fx


# ════════════════════════════════════════════════════════════════════
# on_side_end — 本侧回合末 (p2eq_020 哑铃: 扔哑铃 5/7/10%×携带者maxHp 物理给最前敌)。
# ════════════════════════════════════════════════════════════════════
static func on_side_end(f: Dictionary, item_id: String, star: int, all_fighters: Array) -> Array:
	var fx: Array = []
	if not f.get("alive", false):
		return fx
	var t: int = clampi(star, 1, 3)
	match item_id:
		"p2eq_020":
			var pct: float = [0.05, 0.07, 0.10][t - 1]
			var enemies: Array = _enemies(all_fighters, f)
			if not enemies.is_empty():
				var tgt20: Dictionary = _front_most(enemies)
				var e20: Dictionary = _skill_hit(all_fighters, f, tgt20, pct * float(f.get("maxHp", 0)), "physical")
				_attach_projectile(e20, _idx(all_fighters, f), "res://assets/sprites/equip/dungeon-dumbbell.png", 42.0, 0.42)   # 哑铃直线投射 (1:1 phase1 e_dumbbell)
				fx.append(e20)

		"p2eq_034":
			# 玩偶小熊: on_side_end 小熊攻最前敌 (coef×ATK + base) 物理 + 击飞; +1大熊层;
			#   满 (5/3/1) 层 → 标记可召唤大熊 (实际 spawn fighter+view 在 BattleScene; 没空位则继续小熊攻直到有空位).
			#   已召唤过 (_p2DollSpawned) 则不再触发 (装备销毁后整件移除, 此守卫只防 spawn 帧前的重入).
			if not f.get("_p2DollSpawned", false):
				var en34: Array = _enemies(all_fighters, f)
				if not en34.is_empty():
					var tgt34: Dictionary = _front_most(en34)
					var coef34: float = [1.0, 2.0, 5.0][t - 1]
					var base34: float = [100.0, 210.0, 1000.0][t - 1]
					fx.append(_skill_hit(all_fighters, f, tgt34, coef34 * float(f.get("atk", 0)) + base34, "physical"))
					# 击飞靶子 (017锚/龟蛋免击飞) — e_dart 侧回合末读 _knockedUpThisTurn
					if tgt34.get("alive", false) and not tgt34.get("_p2AnchorImmune", false) and not tgt34.get("_eggImmune", false):
						tgt34["_knockedUpThisTurn"] = true
				# +1 大熊层
				f["_p2DollBigBearStacks"] = int(f.get("_p2DollBigBearStacks", 0)) + 1
				# 满阈值 (1★5 / 2★3 / 3★1) → 标记可召唤大熊
				if int(f.get("_p2DollBigBearStacks", 0)) >= [5, 3, 1][t - 1]:
					f["_p2DollReadyToSpawn"] = true
					fx.append({"target_idx": _idx(all_fighters, f), "kind": "passive", "label": "🧸 大熊就绪!"})

		"p2eq_025":
			# 雷鸣贝壳: 回合末 N 道雷各随机电击一敌 1×ATK 真伤 (天降闪电VFX, 镜phase1 e_thunder_shell)
			for _bi in range([1, 2, 3][t - 1] + int(f.get("_coralShards", 0))):  # 珊瑚×碎片
				var en25: Array = _enemies(all_fighters, f)
				if en25.is_empty():
					break
				var hit25: Dictionary = _raw_hit(all_fighters, en25[randi() % en25.size()], maxi(1, int(f.get("atk", 0))), "true", false)
				hit25["vfx"] = "lightning"   # 1:1 PoC: phase1带闪电VFX, 原phase2漏=只飘字
				fx.append(hit25)

		"p2eq_052":
			# 左轮手枪: 回合末若有子弹 → 向随机敌射1发 (base+coef×ATK) 物理, 0弹停火。
			if int(f.get("_p2RevolverBullets", 0)) > 0:
				var en52: Array = _enemies(all_fighters, f)
				if not en52.is_empty():
					f["_p2RevolverBullets"] = int(f["_p2RevolverBullets"]) - 1
					var raw52: float = [150.0, 310.0, 1200.0][t - 1] + [3.0, 5.0, 9.0][t - 1] * float(f.get("atk", 0))
					var tg52: Dictionary = en52[randi() % en52.size()]
					var e52: Dictionary = _skill_hit(all_fighters, f, tg52, raw52, "physical")
					_attach_projectile(e52, _idx(all_fighters, f), "res://assets/sprites/vfx/revolver-bullet.png", 30.0, 0.30)   # 左轮子弹直线投射 (1:1 phase1 e_revolver)
					fx.append(e52)
					fx.append_array(gun_fire_shot(f, "p2eq_052", tg52, all_fighters, raw52, "physical"))   # 枪[神枪手]金弹

		"p2eq_056":
			# 飞镖: 回合末向所有【被击飞的敌(_knockedUpThisTurn)】各射1镖 (base+coef×ATK 物理 + 流血), 命中移除靶子。
			var base56: float = [130.0, 190.0, 600.0][t - 1]
			var coef56: float = [1.5, 3.0, 9.0][t - 1]
			var bleed56: int = [40, 60, 100][t - 1]
			for e56 in _enemies(all_fighters, f):
				if e56.get("_knockedUpThisTurn", false):
					var e56fx: Dictionary = _skill_hit(all_fighters, f, e56, base56 + coef56 * float(f.get("atk", 0)), "physical")
					_attach_projectile(e56fx, _idx(all_fighters, f), "res://assets/sprites/equip/dungeon-dart.png", 30.0, 0.34)   # 飞镖直线投射 (1:1 phase1 e_dart)
					fx.append(e56fx)
					Dot.apply_stacks(e56, "bleed", maxi(1, roundi(float(bleed56) + 0.8 * float(f.get("atk", 0)))))
					e56["_knockedUpThisTurn"] = false   # 命中移除靶子

		"p2eq_037":
			# 蛋糕蜡烛: on_side_end 推进 3 阶段循环 → 应用新阶段效果。
			#   1微弱=携带者回(base+coef×ATK)+邻格友半效 / 2燃烧=随机敌横排(同列F+B)各魔法+灼烧 / 0熄灭=无。
			var ph37: int = (int(f.get("_p2CandlePhase", 0)) + 1) % 3
			f["_p2CandlePhase"] = ph37
			var atk37: float = float(f.get("atk", 0))
			if ph37 == 1:
				# 微弱: 携带者回血 + 邻格友军半效
				var heal37: float = [20.0, 30.0, 44.0][t - 1] + [0.5, 0.7, 1.0][t - 1] * atk37
				var h37: int = _heal(f, heal37)
				if h37 > 0:
					fx.append({"target_idx": _idx(all_fighters, f), "value": h37, "kind": "heal", "vfx": "healglow"})   # 回血段绿光
				for adj37 in SlotHelpers.adjacent_fighters(all_fighters, f):
					if adj37 is Dictionary and adj37.get("alive", false) and adj37.get("side", "") == f.get("side", ""):
						var ha37: int = _heal(adj37, heal37 * 0.5)
						if ha37 > 0:
							fx.append({"target_idx": _idx(all_fighters, adj37), "value": ha37, "kind": "heal", "vfx": "healglow"})   # 邻格友军回血绿光
			elif ph37 == 2:
				# 燃烧: 随机敌所在横排(同列 F+B)各受魔法 + 灼烧
				var en37: Array = _enemies(all_fighters, f)
				if not en37.is_empty():
					var dmg37: float = [20.0, 30.0, 44.0][t - 1] + [0.5, 0.7, 1.0][t - 1] * atk37 + float(int(f.get("_coralShards", 0))) * 3.0  # 珊瑚×碎片
					var burn37: int = [20, 30, 40][t - 1] + int(f.get("_coralShards", 0))  # 珊瑚×碎片
					var anchor37: Dictionary = en37[randi() % en37.size()]
					var row37: Array = []
					for c in SlotHelpers.same_column_fighters(all_fighters, anchor37):
						if c is Dictionary and c.get("alive", false) and c.get("side", "") != f.get("side", ""):
							row37.append(c)
					if row37.is_empty():
						row37 = [anchor37]
					for e37 in row37:
						var h37e: Dictionary = _skill_hit(all_fighters, f, e37, dmg37, "magic")
						h37e["vfx"] = "flameburst"   # 燃烧段: 该横排各点火焰喷溅 (火焰横扫感; 数值不动)
						fx.append(h37e)
						Dot.apply_stacks(e37, "burn", burn37)

		"p2eq_043":
			# 海浪护符: on_side_end +1 巨浪层, 满(3/2/2)→ 随机一横排(same_column F+B)扫敌我; 友+盾+永久护甲魔抗, 敌魔法+永久减; 重置。
			f["_p2WaveStacks"] = int(f.get("_p2WaveStacks", 0)) + 1
			if int(f["_p2WaveStacks"]) >= [3, 2, 2][t - 1]:
				f["_p2WaveStacks"] = 0
				var en43: Array = _enemies(all_fighters, f)
				if not en43.is_empty():
					var col43: int = _slot_col(en43[randi() % en43.size()])
					var shieldv43: int = [40, 95, 120][t - 1]
					var armorv43: int = [2, 3, 5][t - 1]
					var magicv43: float = float([60, 110, 200][t - 1])
					for c in all_fighters:
						if not (c is Dictionary) or not c.get("alive", false) or _slot_col(c) != col43:
							continue
						if c.get("side", "") == f.get("side", ""):
							var sg43: int = Buffs.grant_shield(c, shieldv43)
							fx.append({"target_idx": _idx(all_fighters, c), "value": sg43, "kind": "shield", "vfx": "shieldglow"})   # 海浪护符 友军盾光
							c["baseDef"] = int(c.get("baseDef", 0)) + armorv43
							c["def"] = c["baseDef"]
							c["baseMr"] = int(c.get("baseMr", 0)) + armorv43
							c["mr"] = c["baseMr"]
						else:
							fx.append(_skill_hit(all_fighters, f, c, magicv43, "magic"))
							c["baseDef"] = int(c.get("baseDef", 0)) - armorv43
							c["def"] = c["baseDef"]
							c["baseMr"] = int(c.get("baseMr", 0)) - armorv43
							c["mr"] = c["baseMr"]
	return fx


# ════════════════════════════════════════════════════════════════════
# on_death — 任意单位死亡时 (BattleScene 死亡口调用 1 次, dead=刚死的)。
#   035 黄铜齿轮: 携带者死亡 → 每齿轮 +2 深海币 (返 {coin_side, coins} 给 BattleScene 落 GameState.dual_coins)。
#   052 左轮手枪: 敌方单位死亡 → 该死者的对面所有左轮持有者 +1 子弹 (cap 6, 直接改 fighter 状态)。
# 返回 {coin_side:String, coins:int} (coins=0 表示无币产出)。
# ════════════════════════════════════════════════════════════════════
static func on_death(dead: Dictionary, all_fighters: Array) -> Dictionary:
	var out: Dictionary = {"coin_side": "", "coins": 0}
	if not (dead is Dictionary):
		return out
	# 035: 死者自带齿轮 → 给死者所属方深海币 (每齿轮 +2)
	for p2 in dead.get("_p2_equips", []):
		if p2 is Dictionary and str(p2.get("id", "")) == "p2eq_035":
			out["coin_side"] = str(dead.get("side", ""))
			out["coins"] = int(out["coins"]) + int(dead.get("_p2Gears", 0)) * 2
	# 052: 死者是左轮持有者的敌人 → 对面所有左轮 +1 子弹 (cap 6)
	for f in all_fighters:
		if not (f is Dictionary) or not f.get("alive", false) or f == dead:
			continue
		if f.get("side", "") == dead.get("side", ""):
			continue
		for p2 in f.get("_p2_equips", []):
			if p2 is Dictionary and str(p2.get("id", "")) == "p2eq_052":
				f["_p2RevolverBullets"] = mini(6, int(f.get("_p2RevolverBullets", 0)) + 1)
				break
	return out


# ══════════════════════════════════════════════════════════════════
# 【奇械·深海工坊 死亡产装备】(类型·奇械 激活 2/4/6)
#   本局每累计失去一名我方统领/小将 → 该侧【每件奇械】各产一件装备, 费用=当前累计失去数(封顶5)。
#   每个累计死亡数档位一局仅触发一次, 产出装备【永久进背包】(GameState.bench_inventory)。规格 #544。
#
#   本 helper 纯函数: 统计某侧场上【激活奇械】的总件数(= _gadgetPieces 之和, 仅算携带且激活者),
#   按 cost 从 pool 掷出等量装备 id, 返回 [id, id, ...](件数个)。掷选/封顶/触发去重由 BattleScene 死亡口管。
#   ⚠ cost 对应费用档(1-5); 该费用没货则回退低费(镜 phase2_equip.roll_shop 回退); pool 用 shopAvailable==1 池
#   (cost5 装备全 shopAvailable==0 → 回退到费4, 是已知数据现状, 见报告)。
# ══════════════════════════════════════════════════════════════════
static func gadget_piece_count(all_fighters: Array, side: String) -> int:
	var n: int = 0
	for f in all_fighters:
		if not (f is Dictionary) or f.get("side", "") != side or not f.get("alive", false):
			continue
		n += int(f.get("_gadgetPieces", 0))   # apply_team_start 已标 = 该龟身上奇械件数(仅激活时标)
	return n

## 按 cost 从 pool 掷一件装备 id (shopAvailable==1; 该费没货回退低费); 无货返 ""。
static func _roll_equip_of_cost(pool: Array, cost: int, rng: RandomNumberGenerator) -> String:
	var by_cost: Dictionary = {}
	for it in pool:
		if not (it is Dictionary) or int(it.get("shopAvailable", 0)) != 1:
			continue
		var c: int = int(it.get("cost", 1))
		if not by_cost.has(c):
			by_cost[c] = []
		(by_cost[c] as Array).append(str(it.get("id", "")))
	var tier: int = clampi(cost, 1, 5)
	while tier >= 1 and (not by_cost.has(tier) or (by_cost[tier] as Array).is_empty()):
		tier -= 1   # 该费没货 → 回退低费 (cost5 现无 shopAvailable 货 → 落费4)
	if tier < 1:
		return ""
	var lst: Array = by_cost[tier]
	return str(lst[rng.randi() % lst.size()])

## 一次死亡产出: 某侧激活奇械总件数 × 一件 cost 费装备 → 返回产出的装备 id 数组(件数个, 每件独立掷)。
static func gadget_produce(all_fighters: Array, side: String, cost: int, pool: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pieces: int = gadget_piece_count(all_fighters, side)
	if pieces <= 0:
		return out
	for _i in range(pieces):
		var eid: String = _roll_equip_of_cost(pool, cost, rng)
		if eid != "":
			out.append(eid)
	return out


# ── 同侧存活、ATK 最高的友军 (021 伤害最高友军的近似) ──
static func _highest_atk_ally(all_fighters: Array, owner: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_atk: float = -1.0
	for a in all_fighters:
		if a is Dictionary and a.get("alive", false) and a.get("side", "") == owner.get("side", "") and not a.get("_isEgg", false):
			var av: float = float(a.get("atk", 0))
			if av > best_atk:
				best_atk = av
				best = a
	return best


# ── 净化 target 的前 n 个负面 buff (burn/poison/bleed/curse/stun/freeze/chilled/armorBreak 等) ──
static func _cleanse_debuffs(target: Dictionary, n: int) -> void:
	var debuffs := ["stun", "freeze", "curse", "poison", "bleed", "burn", "chilled", "armorBreak", "mrDown", "atkDown", "healReduce", "dmgReduce"]
	var buffs: Array = target.get("buffs", [])
	var removed := 0
	for i in range(buffs.size() - 1, -1, -1):
		if removed >= n:
			break
		var b = buffs[i]
		if b is Dictionary and str(b.get("type", "")) in debuffs:
			buffs.remove_at(i)
			removed += 1


# ════════════════════════════════════════════════════════════════════
# on_hit_as_target — 携带者每受一段伤害后 (owner=被打者)。
#   p2eq_013/014 受击硬化 (+def/mr cap20, 013满层→护盾) · p2eq_017 奶最低血友军+沉锚充能。
# ════════════════════════════════════════════════════════════════════
static func on_hit_as_target(owner: Dictionary, _attacker: Dictionary, dmg: int, item_id: String, _star: int, all_fighters: Array) -> Array:
	var fx: Array = []
	if dmg <= 0 or not owner.get("alive", false):
		return fx
	match item_id:
		"p2eq_013", "p2eq_014":
			# 受击硬化: 每段 +inc def/mr (cap 20 层); 013 满层 → 一次性护盾; 013 3★ 满层 → 累积护甲魔抗分全队(一次)。
			var cur: float = float(owner.get("_p2HardenStacks", 0.0))
			if cur < 20.0:
				var inc: float = float(owner.get("_p2HardenInc", 1.0))
				owner["_p2HardenStacks"] = cur + 1.0
				owner["baseDef"] = float(owner.get("baseDef", 0)) + inc
				owner["def"] = owner["baseDef"]
				owner["baseMr"] = float(owner.get("baseMr", 0)) + inc
				owner["mr"] = owner["baseMr"]
				var sv: int = int(owner.get("_p2HardenShieldVal", 0))
				if cur + 1.0 >= 20.0 and sv > 0 and not owner.get("_p2HardenGiven", false):
					owner["_p2HardenGiven"] = true
					var sg13: int = Buffs.grant_shield(owner, sv)
					fx.append({"target_idx": _idx(all_fighters, owner), "value": sg13, "kind": "shield", "vfx": "shieldglow"})   # 满层护盾光
				# 013 3★: 叠满20层 → 把累积(20×inc)护甲魔抗分给全队【其他】友军(一次, 携带者本身已自带)。
				if cur + 1.0 >= 20.0 and owner.get("_p2HardenTeamShare", false) and not owner.get("_p2HardenTeamGiven", false):
					owner["_p2HardenTeamGiven"] = true
					var share: int = roundi(20.0 * inc)
					if share > 0:
						for a in all_fighters:
							if a is Dictionary and a.get("alive", false) and a != owner \
									and a.get("side", "") == owner.get("side", ""):
								a["baseDef"] = int(a.get("baseDef", 0)) + share
								a["def"] = a["baseDef"]
								a["baseMr"] = int(a.get("baseMr", a.get("baseDef", 0))) + share
								a["mr"] = a["baseMr"]
								fx.append({"target_idx": _idx(all_fighters, a), "kind": "passive", "label": "🦪 硬化+%d抗" % share})

		"p2eq_017":
			# 不沉之锚: 每受一段伤害 → 奶【最低血%友军】X% 携带者maxHp; 累积治疗100 → +1 沉锚充能。
			var heal_amt: int = roundi(float(owner.get("maxHp", 0)) * float(owner.get("_p2AnchorHealPct", 1.0)) / 100.0)
			if heal_amt > 0:
				var ally: Dictionary = _lowest_hp_ally(all_fighters, owner)
				if not ally.is_empty():
					var lb: int = int(ally.get("hp", 0))
					ally["hp"] = mini(int(ally.get("maxHp", 0)), lb + heal_amt)
					var healed: int = int(ally.get("hp", 0)) - lb
					if healed > 0:
						fx.append({"target_idx": _idx(all_fighters, ally), "value": healed, "kind": "heal", "vfx": "healglow"})   # 不沉之锚友军回血绿光 (原无 vfx)
						owner["_p2AnchorAccum"] = float(owner.get("_p2AnchorAccum", 0.0)) + float(healed)
						while float(owner.get("_p2AnchorAccum", 0.0)) >= 100.0:
							owner["_p2AnchorAccum"] = float(owner["_p2AnchorAccum"]) - 100.0
							owner["_p2AnchorCharges"] = int(owner.get("_p2AnchorCharges", 0)) + 1

		"p2eq_044":
			# 深海项链: 生命首次<50% → 回 (12/27/40%)maxHp (一次)
			if not owner.get("_p2AmuletUsed", false) and float(owner.get("hp", 0)) < float(owner.get("maxHp", 1)) * 0.5:
				owner["_p2AmuletUsed"] = true
				var hh44: int = _heal(owner, float(owner.get("maxHp", 0)) * [0.12, 0.27, 0.40][clampi(_star, 1, 3) - 1])
				if hh44 > 0:
					fx.append({"target_idx": _idx(all_fighters, owner), "value": hh44, "kind": "heal", "vfx": "healglow"})   # 首次<50% 治疗绿光

		"p2eq_045":
			# 珍珠耳环: 生命首次<50% → 回 (15/29/65%)maxHp + 向 N 个随机敌射火球 (X%目标maxHp 魔法) + 灼烧 (一次)。
			if not owner.get("_p2PearlUsed", false) and float(owner.get("hp", 0)) < float(owner.get("maxHp", 1)) * 0.5:
				owner["_p2PearlUsed"] = true
				var si45: int = clampi(_star, 1, 3) - 1
				var hh45: int = _heal(owner, float(owner.get("maxHp", 0)) * [0.15, 0.29, 0.65][si45])
				if hh45 > 0:
					fx.append({"target_idx": _idx(all_fighters, owner), "value": hh45, "kind": "heal", "vfx": "healglow"})   # 生命珍珠自愈回血绿光 (原无 vfx, 与兄弟044一致)
				var balls45: int = [1, 1, 2][si45]
				var fire_pct45: float = [0.08, 0.17, 0.30][si45]
				var burn45: int = [30, 70, 150][si45]
				var en45: Array = _enemies(all_fighters, owner)
				for _b45 in range(balls45):
					if en45.is_empty():
						break
					var tgt45: Dictionary = en45[randi() % en45.size()]
					var fb45: Dictionary = _skill_hit(all_fighters, owner, tgt45, float(tgt45.get("maxHp", 0)) * fire_pct45, "magic")
					fb45["vfx"] = "fireball"   # 火球飞行 VFX (BattleScene _play_fireball): owner→敌 — 1:1 PoC e_pearl castFireball
					fb45["vfx_from"] = _idx(all_fighters, owner)
					_stamp_arrival(fb45, 0.0, 0.35)   # 血跟火球落地才掉 (_play_fireball travel 0.35s, 同金弹法) — 显示时机, 数值不动
					fx.append(fb45)
					Dot.apply_stacks(tgt45, "burn", burn45)

		"p2eq_036":
			# 温泉蛋: 每段承受伤害 ×0.1 → 孵化进度 (满级→全队均摊护盾)。
			fx.append_array(_p2_incub_tick(owner, all_fighters, maxi(0, roundi(float(dmg) * 0.1))))
	return fx


# ── 存活、生命值百分比最低的敌人 (057 狙击长管选靶) ──
static func _lowest_hp_enemy(enemies: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_pct: float = 2.0
	for e in enemies:
		if e is Dictionary and e.get("alive", false):
			var pct: float = float(e.get("hp", 0)) / maxf(1.0, float(e.get("maxHp", 1)))
			if pct < best_pct:
				best_pct = pct
				best = e
	if best.is_empty() and not enemies.is_empty():
		best = enemies[0]
	return best


# ── 同侧存活、生命值百分比最低的友军 (含自身) ──
static func _lowest_hp_ally(all_fighters: Array, owner: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_pct: float = 2.0
	for a in all_fighters:
		if a is Dictionary and a.get("alive", false) and a.get("side", "") == owner.get("side", ""):
			var pct: float = float(a.get("hp", 0)) / maxf(1.0, float(a.get("maxHp", 1)))
			if pct < best_pct:
				best_pct = pct
				best = a
	return best


# ════════════════════════════════════════════════════════════════════
# sweep — 010 激光长刃【授予的主动技能 横扫】(0龟能)。skill_handlers "p2Sweep" 调用。
#   Lv1/2 横扫【一列=target所在排 F0F1F2】; Lv3 横扫【全体敌人】; 每人 (base+coef×ATK) 物理。
#   若只命中1个 → 追加【竖斩】: 该单位再受一发 + 其正身后单位(fighter_behind) 50%。
#   携带者回复【全程总伤】× heal_pct (35/80/100%)。
# ════════════════════════════════════════════════════════════════════
static func sweep(caster: Dictionary, target: Dictionary, star: int, all_fighters: Array) -> Array:
	var fx: Array = []
	if not caster.get("alive", false):
		return fx
	var t: int = clampi(star, 1, 3)
	var base: float = [100.0, 200.0, 2000.0][t - 1]
	var coef: float = [1.2, 2.5, 5.0][t - 1]
	var heal_pct: float = [0.35, 0.80, 1.0][t - 1]
	var raw: float = base + coef * float(caster.get("atk", 0))
	var targets: Array = []
	if t >= 3:
		targets = _enemies(all_fighters, caster)   # Lv3 全体敌人
	else:
		if target != null and not (target as Dictionary).is_empty():
			for c in SlotHelpers.same_row_fighters(all_fighters, target):
				if c is Dictionary and c.get("alive", false) and c.get("side", "") != caster.get("side", ""):
					targets.append(c)
		if targets.is_empty():
			targets = _enemies(all_fighters, caster)
	var total: int = 0
	for e in targets:
		var ed: Dictionary = _skill_hit(all_fighters, caster, e, raw, "physical")
		total += int(ed["value"])
		fx.append(ed)
	# 只命中1个单位 → 竖斩 (该单位再受一发 + 正身后单位 50%)
	if targets.size() == 1:
		var single: Dictionary = targets[0]
		var ed2: Dictionary = _skill_hit(all_fighters, caster, single, raw, "physical")
		total += int(ed2["value"])
		fx.append(ed2)
		var behind = SlotHelpers.fighter_behind(all_fighters, single)
		if behind != null and behind is Dictionary and behind.get("alive", false):
			var eb: Dictionary = _skill_hit(all_fighters, caster, behind, raw * 0.5, "physical")
			total += int(eb["value"])
			fx.append(eb)
	# 携带者回血 = 全程总伤 × heal_pct
	if total > 0:
		var lb: int = int(caster.get("hp", 0))
		caster["hp"] = mini(int(caster.get("maxHp", 0)), lb + roundi(float(total) * heal_pct))
		var healed: int = int(caster.get("hp", 0)) - lb
		if healed > 0:
			fx.append({"target_idx": _idx(all_fighters, caster), "value": healed, "kind": "heal", "vfx": "healglow"})   # on_cast 吸血回血绿光 (原无 vfx)
	return fx
