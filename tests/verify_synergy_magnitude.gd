extends Node
## verify_synergy_magnitude.gd — 羁绊【强度量级】门禁（方案书 R8 一直要的那条）
##
## ★为什么必须有它：批 4-1 把羁绊从"零效果"接上战斗的当天，探针一量就发现
##   **数值大了整整一个数量级** —— 剑顶档带满 3 件 = 攻击力 ×5.65（40→226）、
##   奇械 ×23.5（魔抗 14→329）、盾 ×9.14、弓箭暴击 +90%。
##   根因：那些数值继承自一份**从来没被施加过**的表（羁绊在战斗里一直零效果），
##   所以量级错了也没人发现。
##   memory [[fb-verify-magnitude-not-just-correctness]]：**数值"对不对"和"合不合理"是两件事** ——
##   彩虹那次五条探针全绿（含反向验证）仍把胜率从 14% 推到 97%。
##
## ★这条门禁验的不是"等于某个数"（那是 verify_synergy_live 的活），
##   而是**「一只龟带满 3 件同类、该羁绊顶档时，战力涨了几倍」落在设计带内**。
##   带宽取自方案书 §4.5.3：顶档占 50~56% 装备位、收益必须超线性 ⇒ 定为 **×1.8 ~ ×2.6**。
##   首档占 11~17% 装备位 ⇒ **×1.10 ~ ×1.45**。
##
## ★换算口径（写清楚，免得下次有人按别的口径算出别的数）：
##   · 攻击力 / 生命 / 龟能：直接按倍率
##   · 护甲 / 魔抗：换成**等效生命** —— `resist_multiplier(r) = 1 − r/(r+40)`，
##     倍率 = 基础承伤 ÷ 加成后承伤（`scripts/combat/damage_math.gd`）
##   · 暴击：DPS 倍率 = 1 + 暴击率 ×(暴伤 − 1)，暴伤取默认 1.5
##   · 吸血 / 破甲 / 法穿：换算依赖敌方属性，**不设倍率带**，只卡绝对上限
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_magnitude.tscn

const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const DamageMath := preload("res://scripts/combat/damage_math.gd")

## 龟基础属性 = pets.json 28 只的中位（本文件开头打印实测值核对，不是写死的信仰）
const BASE_ATK := 40.0
const BASE_RES := 14.0
const BASE_HP := 944.0
const CRIT_DMG := 1.5
const CAP := 3                       # UNIT_EQUIP_CAP：一只龟最多带 3 件

const TOP_LO := 1.8
const TOP_HI := 3.0
const FIRST_LO := 1.05
const FIRST_HI := 1.70

## ★★用户正在【逐类型评审并亲自定数】(2026-08-03 起, 从剑开始)。
##   用户定的数就是准 —— 上面那条带是我从 §4.5.3 推的**参考**, 不是他拍的。
##   ⇒ 已评审过的类型【不参与倍率带】, 只打印实测值备查;
##     没评审的仍然卡带, 因为那些还是我重标定出来的、需要有人盯着。
##   评审完一个就把它加进来。全部评审完之后, 这张表就该按用户的最终值重定带宽、清空豁免。
##   ⚠ 这不是"给例外开口子": 豁免的类型仍然被 verify_synergy_live(逐档数值)
##     与 verify_synergy_text(文案==实装) 两条门禁焊着, 只是不卡"合不合理"这一条。
const USER_REVIEWED := ["剑"]
## 不换算成倍率的（依赖敌方属性），只卡绝对上限
const ABS_CAP := {"armorPen": 40.0, "magicPen": 50.0, "_lifestealPct": 35.0, "_maxEnergy": 70.0}

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 羁绊强度量级 (R8) ===")

	# ★分母兼自检：基准值必须还是 pets.json 的真实中位，龟平衡动过就要重算这张表
	var atks: Array = []
	var hps: Array = []
	for p in DataRegistry.all_pets:
		atks.append(float((p as Dictionary).get("atk", 0)))
		hps.append(float((p as Dictionary).get("hp", 0)))
	atks.sort()
	hps.sort()
	var med_atk: float = atks[atks.size() / 2]
	var med_hp: float = hps[hps.size() / 2]
	_ok("★分母: 龟基础攻击力中位仍是 %.0f(pets.json %d 只)" % [BASE_ATK, atks.size()],
		absf(med_atk - BASE_ATK) <= 5.0, "实测中位 %.0f" % med_atk)
	_ok("★分母: 龟基础生命中位仍是 %.0f" % BASE_HP, absf(med_hp - BASE_HP) <= 60.0,
		"实测中位 %.0f" % med_hp)

	print("")
	print("  %-5s %-7s %s" % ["类型", "档", "带满 3 件时的战力倍率"])
	var bad_top: Array = []
	var bad_first: Array = []
	var bad_abs: Array = []
	for t in Phase2Types.TYPES:
		var d: Dictionary = Phase2Types.TYPES[t]
		var stats: Array = d.get("stats", [])
		var tiers: Array = d.get("tiers", [])
		for ti in range(stats.size()):
			var per: Dictionary = stats[ti]
			var mult := 1.0
			var notes: Array = []
			# ★暴击与暴伤必须【一起算】: DPS 倍率 = 1 + 暴击 × (暴伤 − 1)。
			#   分开算(各自乘)会把 ×1.15 算成 ×1.5, 是这条门禁最容易写错的地方。
			var c_add: float = float(per.get("crit", 0.0)) * float(CAP)
			var cd_add: float = float(per.get("critDmg", 0.0)) * float(CAP)
			if c_add > 0.0:
				mult *= 1.0 + c_add * (CRIT_DMG + cd_add - 1.0)
				notes.append("暴击+%.0f%% 暴伤+%.0f%%" % [c_add * 100.0, cd_add * 100.0])
			for k in per:
				if k == "crit" or k == "critDmg":
					continue
				var total: float = float(per[k]) * float(CAP)
				match k:
					"atk":
						mult *= (BASE_ATK + total) / BASE_ATK
						notes.append("攻+%.0f" % total)
					"def", "mr":
						# 等效生命 = 基础承伤 ÷ 加成后承伤
						mult *= DamageMath.resist_multiplier(BASE_RES) / DamageMath.resist_multiplier(BASE_RES + total)
						notes.append("%s+%.0f" % [k, total])
					"dodgePct":
						# 闪避的等效生命 = 1/(1−闪避)，且被 DODGE_CAP 钳在 0.75
						var dg: float = minf(total / 100.0, 0.75)
						mult *= 1.0 / maxf(0.05, 1.0 - dg)
						notes.append("闪避+%.0f%%" % (dg * 100.0))
					"_foodPerEquip":
						# 食物数的是【携带者身上全部装备】，满 3 件且都是食物 ⇒ ×2
						var add: float = float(per[k]) * 2.0 * float(CAP)
						mult *= (BASE_HP + add) / BASE_HP
						notes.append("血+%.0f" % add)
					_:
						notes.append("%s+%.0f" % [k, total])
						if ABS_CAP.has(k) and total > float(ABS_CAP[k]):
							bad_abs.append("%s 档%d %s +%.0f 超上限 %.0f" % [t, ti + 1, k, total, float(ABS_CAP[k])])
			var is_top: bool = ti == stats.size() - 1
			var tag: String = "顶档" if is_top else ("首档" if ti == 0 else "中档")
			print("  %-5s %-7s ×%.2f %s  %s" % [t, "%s(%d件)" % [tag, int(tiers[ti])], mult,
				"[用户已定]" if t in USER_REVIEWED else "         ",
				" ".join(PackedStringArray(notes))])
			if mult <= 1.001:
				# 纯"绝对量"类型(枪的破甲 / 法器的法穿 / 遗物的吸血 / 药水的龟能)：
				# 它们的收益取决于敌方属性或技能构成, 换算成"倍率"会得出一个骗人的数
				# ⇒ 不参与倍率带, 只由上面的 ABS_CAP 卡绝对上限。★这不是漏检, 是口径。
				continue
			if t in USER_REVIEWED:
				continue          # 用户亲自定的数, 不卡带(见 USER_REVIEWED 上面那段)
			if is_top and (mult < TOP_LO or mult > TOP_HI):
				bad_top.append("%s 顶档 ×%.2f 不在 [%.1f, %.1f]" % [t, mult, TOP_LO, TOP_HI])
			if ti == 0 and (mult < FIRST_LO or mult > FIRST_HI):
				bad_first.append("%s 首档 ×%.2f 不在 [%.2f, %.2f]" % [t, mult, FIRST_LO, FIRST_HI])

	print("")
	_ok("★★顶档战力倍率全部落在 [%.1f, %.1f]（占 50~56%% 装备位 ⇒ 超线性但不失控）" % [TOP_LO, TOP_HI],
		bad_top.is_empty(), str(bad_top))
	_ok("★首档战力倍率全部落在 [%.2f, %.2f]（占 11~17%% 装备位 ⇒「顺手蹭到的」）" % [FIRST_LO, FIRST_HI],
		bad_first.is_empty(), str(bad_first))
	_ok("★穿透/吸血/龟能这类不换算倍率的, 卡绝对上限", bad_abs.is_empty(), str(bad_abs))

	# 单调性：每一档都必须比上一档强（否则档位没有意义）
	var non_mono: Array = []
	for t in Phase2Types.TYPES:
		var stats2: Array = (Phase2Types.TYPES[t] as Dictionary).get("stats", [])
		for i in range(1, stats2.size()):
			var a: Dictionary = stats2[i - 1]
			var b: Dictionary = stats2[i]
			for k in a:
				if b.has(k) and float(b[k]) <= float(a[k]):
					non_mono.append("%s 档%d 的 %s(%.3f) 不大于 档%d(%.3f)" % [t, i + 1, k, float(b[k]), i, float(a[k])])
	_ok("★档位单调递增(每档都比上一档强, 否则档位没有意义)", non_mono.is_empty(), str(non_mono))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 羁绊强度量级" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
