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
	# ★2026-07-30(需求3 大师技能审核): 也读 trainer_system 的常量表。
	#   原来只读战斗主文件, 而怒火药水/口哨/冰川的实质数值全是散在 trainer_system 函数里的
	#   【字面量】(那个文件一个 const 都没有) → 没法从常量推期望值 → 于是这三个技能
	#   下面的 want 表里【只有射程和 CD】, 实质数值一个都不查。已把它们提成常量。
	var ts: Script = load(TRAINER_SYS_PATH)
	var TK: Dictionary = ts.get_script_constant_map()
	if TK.is_empty():
		print("  [FAIL] ★分母: 读不到 trainer_system 常量表"); get_tree().quit(1); return

	# id → [[人话标签, 该出现在描述里的子串(由代码常量算出来)], ...]
	# ★右边一律【从常量算】。写死字面量就变成拿文案跟文案比, 等于没查。
	var want := {
		"magic_stone": [
			["攻击力倍数", "×%d" % int(K["TRAINER_ATK_MAGIC_STONE"] / K["TRAINER_ATK"])],
			# ★2026-07-30 削弱成【常驻 2%】(不随大轮等级涨) —— 原来这里三行验的是
			#   每级增幅 / Lv1 / Lv10 三个不同的值。现在只有一个数, 文案里也只该出现一个数。
			["附带魔法伤害", "%d%% 目标最大生命" % int(round(K["MS_MAXHP_PCT"] * 100.0))],
			# ★反面: 文案里不许再留"随等级涨"的说法(否则玩家按旧文案理解)
			["不许提大轮等级", "!大轮等级"],
			# ↓2026-07-30 补: 每层攻速原来是 trainer_system 里的裸 0.05, 门禁不查
			["每层攻速", "+%d%%攻速" % int(round(TK["MS_HASTE_PER_STACK"] * 100.0))],
		],
		"hook": [
			["射程", "%d" % int(K["HOOK_RANGE"])],
			["眩晕", "%d秒" % int(K["HOOK_STUN"])],
			["受伤加成", "+%d%%" % int(round((K["HOOK_VULN_MULT"] - 1.0) * 100.0))],
			["冷却", "CD%d" % int(SK["hook"]["cd"])],
		],
		# ↓2026-07-30 补: 原来这三个技能【只查射程和 CD】, 实质数值一个都不查 ——
		#   因为数值是 trainer_system 里的裸字面量, 没有常量可以推。现已提成常量。
		"fury_potion": [
			["射程", "%d" % int(SK["fury_potion"]["range"])],
			["生效半径", "%d码" % int(TK["FURY_RADIUS"])],
			["持续", "%d秒" % int(TK["FURY_SEC"])],
			["攻速", "+%d%%攻速" % int(round((TK["FURY_HASTE"] - 1.0) * 100.0))],
			["龟能充能", "+%d%%龟能充能" % int(round((TK["FURY_ECHARGE"] - 1.0) * 100.0))],
			["移速", "+%d%%移速" % int(round((TK["FURY_MOVE"] - 1.0) * 100.0))],
			["冷却", "CD%d" % int(SK["fury_potion"]["cd"])],
		],
		"whistle": [
			["临时生命", "%d临时生命" % int(TK["WHISTLE_TEMPHP"])],
			["气波伤害", "%d物理" % int(TK["WHISTLE_WAVE_DMG"])],
			["削甲", "削甲%d%%" % int(round((1.0 - K["WHISTLE_SHRED_MULT"]) * 100.0))],
			["狂暴攻击力", "+%d%%攻" % int(round(TK["WHISTLE_BERSERK_ATK"] * 100.0))],
			["免死时长", "免死%d秒" % int(TK["WHISTLE_BERSERK_SEC"])],
			["冷却", "CD%d" % int(SK["whistle"]["cd"])],
		],
		"glacier": [
			["长度", "%d码" % int(SK["glacier"]["range"])],
			["持续", "(%d秒)" % int(K["GLACIER_SEC"])],
			["减速", "-%d%%移速" % int(round((1.0 - TK["GLACIER_SLOW_MAG"]) * 100.0))],
			["受伤加成", "+%d%%" % int(round((K["GLACIER_VULN_MULT"] - 1.0) * 100.0))],
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
			# ★"!" 前缀 = 【否定断言】: 这个片段【不许】出现在文案里(2026-07-30 加)。
			#   由来: 魔法石从"(2+0.1×大轮等级)%"削弱成"常驻 2%", 光断言"文案里有 2%"不够 ——
			#   旧文案里也有"2"; 真正要守的是【旧说法不许残留】, 否则玩家按旧文案理解。
			#   只有正向断言的门禁抓不到"多写了一句过时的话"。
			var neg: bool = frag.begins_with("!")
			if neg:
				frag = frag.substr(1)
			var found: bool = d.find(frag) >= 0
			var ok: bool = (not found) if neg else found
			if not ok:
				if neg:
					print("  [FAIL] ② %s·%s: 描述里【不该】出现「%s」却出现了" % [nm, label, frag])
				else:
					print("  [FAIL] ② %s·%s: 描述里找不到「%s」" % [nm, label, frag])
				print("         描述原文: %s" % descs[sid])
				_fail += 1
			else:
				print("     ② %-4s %-6s → %s「%s」 ✓" % [nm, label, "不含" if neg else "", frag])

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
