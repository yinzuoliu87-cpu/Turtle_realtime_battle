extends Node
## verify_turtle_balance_r4.gd — 第四轮龟平衡·五只 (用户 2026-07-29)
##
## 方案书: docs/plans/20260729-第四轮龟平衡.md
##
## ★2026-07-30 第五轮移交: 骰子回血 / 龟派气波 / 过肩摔 这四条的数值已被第五轮改掉,
##   对应检查已移到 verify_turtle_balance_r5。这里【故意不把期望值改成第五轮的】——
##   改了就毁掉第四轮的留痕(它记录的是"第四轮当时改成了什么")。保留的是仍然成立的部分。
## 闪电单独一个门禁 (verify_lightning_buff)，这里管其余五只。
##
## ★期望值一律写【用户口述的字面需求值】，不从代码常量读回来 ——
##   拿代码跟它自己比是恒真式；verify_trainer_magicstone 曾经就是这样，把常量改坏照样 ALL PASS。
##
## 查什么：
##   财神   梭哈龟能 210 / 招财进宝首释 120·180·300 / 骰子回血 10%
##   双头   近战形态生命加成 250%×ATK  ＋ ★被动文案必须补全那五处漏写
##   幽灵   登场诅咒 2.5 秒，★且 CURSE_HP_PCT 仍是 0.05
##          (那是 battle_damage.gd 的共享常量，无头/彩虹也吃它；彩虹上轮刚调好，误伤它会掉出合理区)
##   忍者   忍术 +20%暴击/+15%暴伤/+10护穿 ＋ 手里剑打包 +15%闪避/+30%暴击
##   普通龟 龟盾 1.5A+13%已损 / 气波 3.0A / 过肩摔 23%·18%
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_turtle_balance_r4.tscn

# ── 需求值(改需求才动这里) ──
const WANT_ALLIN_ENERGY := 210.0
const WANT_BUYEQUIP_ADD := [60.0, 120.0, 240.0]   # 基础 60 + 这三档 = 120/180/300
const WANT_BUYEQUIP_BASE := 60.0
const WANT_DICE_HEAL := 0.10
const WANT_TH_HP_SCALE := 2.5
const WANT_TH_ATK_LOSS := 0.30                    # 本轮【不动】, 焊住防误改
const WANT_GHOST_SPAWN_CURSE := 2.5
const WANT_CURSE_PCT := 0.05                      # 本轮【不许动】—— 共享常量
const WANT_NINJA_CRIT := 0.20
const WANT_NINJA_CRITDMG := 0.15
const WANT_NINJA_PEN := 10.0
const WANT_SHURIKEN_DODGE := 0.15
const WANT_SHURIKEN_CRIT := 0.30
const WANT_SHIELD_ATK := 1.5
const WANT_SHIELD_LOST := 0.13
const WANT_CHIWAVE := 3.0
const WANT_SLAM_MAIN := 0.23
const WANT_SLAM_SPLASH := 0.18

## 双头被动必须补全的五处(方案书 §3.3)。缺一条就红 —— 这是本轮明确的交付物之一。
const TH_PASSIVE_MUST := [
	"自动切换形态",   # ① 什么时候切
	"400",            # ② 射程会变
	"70",             #    (同上)
	"滑退",           # ④ 切远程自动滑退
	"当前生命同时增加",  # ⑤ 切近战免费回血
]

var _fail := 0
var _src := {}


func _ready() -> void:
	print("=== 第四轮龟平衡·五只 ===")
	for k in ["res://scripts/systems/skill_energy.gd",
			"res://scripts/systems/skills/fortune_system.gd",
			"res://scripts/systems/skills/ghost_system.gd",
			"res://scripts/systems/skills/two_head_system.gd",
			"res://scripts/scenes/battle/battle_spawn.gd",
			"res://scripts/scenes/battle/battle_damage.gd",
			"res://scripts/scenes/RealtimeBattle3DScene.gd"]:
		_src[k] = FileAccess.get_file_as_string(k)
	var total := 0
	for v in _src.values():
		total += str(v).length()
	print("  ★分母: 读到 %d 份源码 / 共 %d 字符" % [_src.size(), total])
	_chk("★分母: 七份源码都非空", _src.size() == 7 and total > 200000)

	var pets: Array = _load_pets()
	_chk("★分母: pets.json 读到 %d 只龟" % pets.size(), pets.size() >= 28)
	var P := {}
	for p in pets:
		P[str(p.get("id", ""))] = p

	_fortune()
	_two_head(P)
	_ghost()
	_ninja()
	_basic()

	if _fail == 0:
		print("ALL PASS — 第四轮龟平衡(五只)")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


func _fortune() -> void:
	print("  ── 财神 ──")
	var se: String = _src["res://scripts/systems/skill_energy.gd"]
	var fs: String = _src["res://scripts/systems/skills/fortune_system.gd"]
	_chk("财神·梭哈龟能 = %d" % int(WANT_ALLIN_ENERGY), se.contains('"fortuneAllIn": %.1f' % WANT_ALLIN_ENERGY))
	_chk("财神·梭哈旧值 340 已消失", not se.contains('"fortuneAllIn": 340.0'))
	# 首释 = 基础 60 + [60,120,240] → 120/180/300
	_chk("财神·招财进宝首释 = %d + %s = %d/%d/%d" % [int(WANT_BUYEQUIP_BASE),
			str(WANT_BUYEQUIP_ADD), int(WANT_BUYEQUIP_BASE + WANT_BUYEQUIP_ADD[0]),
			int(WANT_BUYEQUIP_BASE + WANT_BUYEQUIP_ADD[1]), int(WANT_BUYEQUIP_BASE + WANT_BUYEQUIP_ADD[2])],
		fs.contains("%.1f + [%.1f, %.1f, %.1f]" % [WANT_BUYEQUIP_BASE,
			WANT_BUYEQUIP_ADD[0], WANT_BUYEQUIP_ADD[1], WANT_BUYEQUIP_ADD[2]]))
	_chk("财神·招财进宝旧值 100/180/400 已消失", not fs.contains("[100.0, 180.0, 400.0]"))
	# ⇢ 第五轮把骰子回血 10%→15%、金币 3~8→5~8 —— 已移交 verify_turtle_balance_r5。
	#   ★这里【不改成 15%】: 改了就毁掉第四轮的留痕(第四轮确实是 10%)。删掉这条, 由 r5 接管。
	_chk("财神·骰子回血旧值 8% 已消失(第四轮起就不是 8%)", not fs.contains('u["maxHp"] * 0.08'))


func _two_head(P: Dictionary) -> void:
	print("  ── 双头 ──")
	var ts: String = _src["res://scripts/systems/skills/two_head_system.gd"]
	_chk("双头·近战生命加成 = %.1f×ATK" % WANT_TH_HP_SCALE,
		ts.contains('u["_th_hp"] = a * %.1f' % WANT_TH_HP_SCALE))
	_chk("双头·旧值 1.5×ATK 已消失", not ts.contains('u["_th_hp"] = a * 1.5'))
	_chk("双头·攻击惩罚仍是 %.2f×ATK(本轮不动)" % WANT_TH_ATK_LOSS,
		ts.contains('u["_th_atk"] = a * %.2f' % WANT_TH_ATK_LOSS))
	# ★被动文案补全 —— 本轮明确的交付物, 缺一条就红
	var pas: Dictionary = (P["two_head"] as Dictionary)["passive"]
	var txt: String = str(pas.get("brief", "")) + "\n" + str(pas.get("desc", ""))
	_chk("双头·被动 hpScale 字段 = %.1f" % WANT_TH_HP_SCALE,
		abs(float(pas.get("hpScale", 0.0)) - WANT_TH_HP_SCALE) < 0.001)
	_chk("双头·被动文案含 250%×攻击力", txt.contains("250%×攻击力"))
	for must in TH_PASSIVE_MUST:
		_chk("★双头·被动必须写到「%s」(原来漏写)" % must, txt.contains(must))


func _ghost() -> void:
	print("  ── 幽灵 ──")
	var gs: String = _src["res://scripts/systems/skills/ghost_system.gd"]
	var dm: String = _src["res://scripts/scenes/battle/battle_damage.gd"]
	_chk("幽灵·登场诅咒 = %.1f 秒" % WANT_GHOST_SPAWN_CURSE,
		gs.contains("const SPAWN_CURSE_SEC := %.1f" % WANT_GHOST_SPAWN_CURSE))
	_chk("幽灵·登场诅咒旧值 4.0 已消失", not gs.contains("const SPAWN_CURSE_SEC := 4.0"))
	# ★这条是【防误伤】: 诅咒百分比是无头/彩虹共用的, 本轮不许动
	_chk("★CURSE_HP_PCT 仍是 %.2f(共享常量·动它会连累无头/彩虹)" % WANT_CURSE_PCT,
		dm.contains("const CURSE_HP_PCT := %.2f" % WANT_CURSE_PCT))


func _ninja() -> void:
	print("  ── 忍者 ──")
	var bs: String = _src["res://scripts/scenes/battle/battle_spawn.gd"]
	_chk("忍者·忍术 = +%d%%暴击 / +%d%%暴伤 / +%d护穿" % [
			int(WANT_NINJA_CRIT * 100.0), int(WANT_NINJA_CRITDMG * 100.0), int(WANT_NINJA_PEN)],
		bs.contains('u["crit"] += %.2f; u["crit_dmg"] += %.2f; u["armor_pen"] += %.1f' % [
			WANT_NINJA_CRIT, WANT_NINJA_CRITDMG, WANT_NINJA_PEN]))
	_chk("忍者·忍术旧值 30/20/8 已消失",
		not bs.contains('u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["armor_pen"] += 8.0'))
	_chk("忍者·手里剑打包 = +%d%%闪避 / +%d%%暴击" % [
			int(WANT_SHURIKEN_DODGE * 100.0), int(WANT_SHURIKEN_CRIT * 100.0)],
		bs.contains('_buff(u, "dodge", %.2f, false, 9999.0); u["crit"] += %.2f' % [
			WANT_SHURIKEN_DODGE, WANT_SHURIKEN_CRIT]))
	_chk("忍者·手里剑打包旧值 0.25/0.40 已消失",
		not bs.contains('_buff(u, "dodge", 0.25, false, 9999.0); u["crit"] += 0.40'))
	# 暴击总量: 基础 25% + 忍术 + 打包 —— 打出来给人复核
	print("     忍者暴击总量 = 25%%(基础) + %d%%(忍术) + %d%%(打包) = %d%%" % [
		int(WANT_NINJA_CRIT * 100.0), int(WANT_SHURIKEN_CRIT * 100.0),
		int(25.0 + WANT_NINJA_CRIT * 100.0 + WANT_SHURIKEN_CRIT * 100.0)])


func _basic() -> void:
	print("  ── 普通龟 ──")
	var rb: String = _src["res://scripts/scenes/RealtimeBattle3DScene.gd"]
	_chk("普通龟·龟盾 = %.1f×ATK + %d%%已损生命" % [WANT_SHIELD_ATK, int(WANT_SHIELD_LOST * 100.0)],
		rb.contains('(tgt["maxHp"] - tgt["hp"]) * %.2f' % WANT_SHIELD_LOST)
		and rb.contains('u["atk"] * %.1f' % WANT_SHIELD_ATK)
		and rb.contains('_atk_dmg(u, %.1f, tgt) + int(lost)' % WANT_SHIELD_ATK))
	_chk("普通龟·龟盾旧值 0.7A/20%已损 已消失",
		not rb.contains('(tgt["maxHp"] - tgt["hp"]) * 0.20'))
	# ⇢ 第五轮把气波 3.0→2.0 —— 已移交 r5。这里只保留"第四轮砍掉的 3.5 没回来"。
	_chk("普通龟·气波旧值 3.5 已消失", not rb.contains("_atk_dmg(uu2, 3.5, o)"))
	# ⇢ 第五轮把过肩摔改成【乘法结构】(1.0A + 0.2%×ATK×最大生命), 不再是纯 %最大生命 —— 已移交 r5。
	_chk("普通龟·过肩摔旧值 0.26/0.19 已消失",
		not rb.contains("int(tmax * 0.26)") and not rb.contains("int(tmax * 0.19)"))
	# 龟盾改的是【构成】不是单纯削弱 —— 打三档血量出来给人复核
	var A := 40.0
	var mx := 944.0
	print("     龟盾伤害(小龟攻40 / 敌血944):")
	for pct in [0.9, 0.5, 0.1]:
		var lost: float = mx * (1.0 - pct)
		print("        敌 %d%%血: 旧 %.0f  →  新 %.0f" % [
			int(pct * 100.0), 0.7 * A + 0.20 * lost, WANT_SHIELD_ATK * A + WANT_SHIELD_LOST * lost])


func _load_pets() -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/pets.json"))
	if j is Array:
		return j
	if j is Dictionary:
		for v in (j as Dictionary).values():
			if v is Array:
				return v
	return []


func _chk(name: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fail += 1
