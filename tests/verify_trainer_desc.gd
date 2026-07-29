extends Node
## verify_trainer_desc.gd — 训龟大师技能【描述文案】必须与代码常量一致
##
## 由来（2026-07-29 用户「确认训龟大师的技能描述没问题」）：
##   0.17.0 把魔法石从「2% 目标最大生命」改成「(2+0.1×大轮等级)%」、攻击力 1→10，
##   代码和门禁都改了，**配置页那行描述没人动** —— 玩家看到的还是旧数字。
##   七条描述里就这一条烂了，而当时【没有任何检查会响】。这就是这个门禁存在的理由。
##
## 判据：每条描述里的每个数字，都必须由代码常量【推导出来】再回去字符串里找。
##   不是"人眼比一遍"，也不是"描述里有个数字就行" —— 常量一改、描述不改，这里就红。
##
## ★注意它查的是【文案 ↔ 代码】的一致性，不查数值本身合不合理。
##   数值对不对由 verify_trainer_magicstone / verify_trainer_hunt_tame 打真实伤害验。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_trainer_desc.tscn

const CFG := preload("res://scripts/scenes/TrainerConfigScene.gd")
const BATTLE_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const TRAINER_SYS_PATH := "res://scripts/systems/trainer/trainer_system.gd"

var _fail := 0
var _checked := 0


func _ready() -> void:
	print("=== 训龟大师技能描述 ↔ 代码常量 ===")
	var bs: Script = load(BATTLE_PATH)
	var K: Dictionary = bs.get_script_constant_map()
	if K.is_empty():
		print("  [FAIL] ★分母: 读不到战斗脚本常量表"); get_tree().quit(1); return
	var SK: Dictionary = K["TRAINER_SKILLS"]

	# id → [[人话标签, 该出现在描述里的子串(由代码常量算出来)], ...]
	# ★右边一律【从常量算】。写死字面量就变成拿文案跟文案比, 等于没查。
	var want := {
		"magic_stone": [
			["攻击力倍数", "×%d" % int(K["TRAINER_ATK_MAGIC_STONE"] / K["TRAINER_ATK"])],
			["每级增幅", "0.%d×大轮等级" % int(K["MS_MAXHP_PER_LV"] * 1000.0)],
			["Lv1 实际值", "%.1f%%" % ((K["MS_MAXHP_BASE"] + K["MS_MAXHP_PER_LV"] * 1.0) * 100.0)],
			["Lv10 实际值", "%.1f%%" % ((K["MS_MAXHP_BASE"] + K["MS_MAXHP_PER_LV"] * 10.0) * 100.0)],
		],
		"hook": [
			["射程", "%d" % int(K["HOOK_RANGE"])],
			["眩晕", "%d秒" % int(K["HOOK_STUN"])],
			["受伤加成", "+%d%%" % int(round((K["HOOK_VULN_MULT"] - 1.0) * 100.0))],
			["冷却", "CD%d" % int(SK["hook"]["cd"])],
		],
		"fury_potion": [
			["射程", "%d" % int(SK["fury_potion"]["range"])],
			["冷却", "CD%d" % int(SK["fury_potion"]["cd"])],
		],
		"whistle": [
			["冷却", "CD%d" % int(SK["whistle"]["cd"])],
		],
		"glacier": [
			["长度", "%d码" % int(SK["glacier"]["range"])],
			["冷却", "CD%d" % int(SK["glacier"]["cd"])],
		],
		"hunt_order": [
			["射程", "%d码" % int(K["HUNT_RANGE"])],
			["持续", "%d秒" % int(K["HUNT_SEC"])],
			["受伤加成", "+%d%%" % int(round((K["HUNT_VULN"] - 1.0) * 100.0))],
			["嘲讽半径", "%d码" % int(K["HUNT_TAUNT_R"])],
			["冷却", "CD%d" % int(K["HUNT_CD"])],
		],
		"tame": [
			["射程", "%d码" % int(K["TAME_RANGE"])],
			["重生血量", "%d%%最大生命" % int(K["TAME_REVIVE_PCT"] * 100.0)],
			["无敌时长", "%.1f秒无敌" % K["TAME_REVIVE_SEC"]],
			["每秒衰减", "每秒损失%d%%最大生命" % int(K["TAME_DECAY_PCT"] * 100.0)],
			["冷却", "CD%d" % int(K["TAME_CD"])],
		],
	}

	var descs := {}
	for s in CFG.SKILLS:
		descs[str(s["id"])] = str(s["desc"])

	# ── ① 每个技能都得有描述, 且七个技能一个不少(分母) ──
	print("  技能数: 配置页 %d 个 / 注册表 %d 个(主动) + 1(魔法石被动)" % [CFG.SKILLS.size(), SK.size()])
	_chk("① 配置页技能数 = 主动注册表 + 1 个被动", CFG.SKILLS.size() == SK.size() + 1)
	for sid in SK.keys():
		_chk("① 主动技「%s」在配置页有描述" % sid, descs.has(sid) and str(descs[sid]).length() > 10)

	# ── ② 描述里的数字必须与代码常量一致 ──
	for sid in want.keys():
		if not descs.has(sid):
			print("  [FAIL] ★分母: 配置页没有「%s」的描述" % sid); _fail += 1
			continue
		# 描述里的中文标点/空格不影响子串查找, 但全角"％"会 → 统一成半角再找
		var d: String = str(descs[sid]).replace("％", "%").replace(" ", "").replace(" ", "")
		var nm: String = str(SK[sid]["name"]) if SK.has(sid) else "魔法石"
		for pair in want[sid]:
			var label: String = str(pair[0])
			var frag: String = str(pair[1]).replace(" ", "")
			_checked += 1
			var ok: bool = d.find(frag) >= 0
			if not ok:
				print("  [FAIL] ② %s·%s: 描述里找不到「%s」" % [nm, label, frag])
				print("         描述原文: %s" % descs[sid])
				_fail += 1
			else:
				print("     ② %-4s %-6s → 「%s」 ✓" % [nm, label, frag])

	# ── ③ 分母自检: 比对过的片段数 ──
	print("  比对片段数 = %d" % _checked)
	_chk("③ ★分母: 比对片段数 ≥ 20 (太少说明 want 表没填/没跑到)", _checked >= 20)

	if _fail == 0:
		print("ALL PASS — 训龟大师技能描述")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


func _chk(name: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fail += 1
