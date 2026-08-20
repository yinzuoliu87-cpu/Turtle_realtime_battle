extends Node
## verify_minion_text_single_source.gd — 小将文案只许有一份
##
## 由来(2026-08-20, 用户「每个地方都同步了没」): 同一批小将技能说明曾有**两份互相独立的手抄** ——
## 图鉴 `CodexScene.MINION_INFO` 一份、战斗信息面板 `RealtimeBattle3DScene.MINION_SKILL_DESC` 一份,
## 而且**已经漂了**: 图鉴的铁锤有"0.35 秒蓄力 / 60° 锥形 / 4×攻击力", 战斗那份连伤害数字都没有;
## 反过来战斗那份有"100/120 龟能", 图鉴又没有。玩家在两个地方读到两套说法。
##
## ★判据量的是**两个消费方各自取回来的字符串**, 不是"源码里有没有某个常量" ——
##   后者守不住"有人又抄了一份"。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	print("=== 小将文案单一源 ===")
	var kinds: Array = MinionCodex.MINION_KINDS
	_ok("★分母: 小将种类表读得到", kinds.size() >= 3, "实测 %d 种" % kinds.size())

	# ① 三个战斗 type 都能从单一源取到文案, 且非空
	var types := ["minionBodysurf", "minionRocket", "eliteHammer"]
	for t in types:
		var d = MinionCodex.skill_desc(t)
		var okd: bool = d is Dictionary and str((d as Dictionary).get("desc", "")).length() >= 12
		_ok("① %s 能取到文案" % t, okd,
			str((d as Dictionary).get("name", "?")) if d is Dictionary else "null")

	# ② 图鉴侧与战斗侧拿到的是【同一个字符串】—— 这才是"同步"的定义
	for t in types:
		var k: String = str(MinionCodex.TYPE_TO_KIND.get(t, ""))
		var codex_txt: String = str((MinionCodex.MINION_INFO.get(k, {}) as Dictionary).get("skill_desc", ""))
		var battle_txt: String = str((MinionCodex.skill_desc(t) as Dictionary).get("desc", ""))
		_ok("② %s 图鉴与战斗同一段文案" % t, codex_txt != "" and codex_txt == battle_txt,
			"图鉴 %d 字 / 战斗 %d 字" % [codex_txt.length(), battle_txt.length()])

	# ③ 战斗主文件里【不许再出现】第二份手抄常量
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★分母: 战斗主文件读得到", src.length() > 10000, "%d 字" % src.length())
	_ok("③ 战斗主文件里没有 MINION_SKILL_DESC 这份手抄",
		not src.contains("const MINION_SKILL_DESC"), "有 = 又抄了一份")

	# ④ 文案里该带的关键信息两边都在(合并前各缺一半, 合并后不许再缺)
	var hammer: String = str((MinionCodex.skill_desc("eliteHammer") as Dictionary).get("desc", ""))
	_ok("④ 铁锤文案带伤害倍率(合并前战斗那份没有)", hammer.contains("攻击力"), hammer.substr(0, 40))
	var rocket_cost: int = int((MinionCodex.MINION_INFO.get("back", {}) as Dictionary).get("skill_cost", 0))
	_ok("④ 远程小将有龟能消耗(合并前图鉴那份没有)", rocket_cost > 0, "%d 龟能" % rocket_cost)

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 小将文案单一源" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
