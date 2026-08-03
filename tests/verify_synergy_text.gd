extends Node
## verify_synergy_text.gd — 羁绊【文案数值 == 实装数值】（2026-08-03）
##
## ★为什么必须有它：v0.19.3 重标定羁绊强度时，改了 `TYPES` 的 `stats` 表，
##   **忘了改 `TIER_DESCS` 的文案** —— 结果 8 个类型、**30 条**文案在骗玩家：
##   盾写着「每件 +8 护甲」实发 5、奇械写着「+105 魔抗」实发 23、
##   弓箭的暴击伤害压根**没写进文案**（玩家看不到自己吃了什么）。
##   这正是本项目最恨的那类问题（`tooltip_number_audit` 就是为装备文案建的同款门禁），
##   而羁绊这一侧一直没人守。
##
## ★这条门禁的判据是 `tooltip_number_audit` 的同一套思路：
##   **从文案里把「+N 属性名」抠出来，和 `TYPES.stats` 逐个比。**
##   与"断言某个函数存在"不同 —— 它比的是**玩家真正看到的那串字**。
##
## 守四组：
##   ① 每个类型每一档的**每一条属性**都在文案里出现，且数字一致
##   ② 反过来：文案里出现的「+N 属性名」都能在 `stats` 里找到（防写了不存在的加成）
##   ③ ★分母：真的抠出了 ≥25 条属性（抠不到就是正则失效，那是空检查不是通过）
##   ④ 文案段数 == 档数，且每段非空
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_text.tscn

const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

## 属性 key → 文案里用的中文名。★加新属性时这里也要加，否则 ② 会把它当"文案里多出来的"。
const LABEL := {
	"atk": "攻击力", "def": "护甲", "mr": "魔法抗性", "crit": "暴击率",
	"critDmg": "暴击伤害", "armorPen": "护甲穿透", "magicPen": "法术穿透",
	"_lifestealPct": "生命偷取", "_maxEnergy": "最大龟能", "dodgePct": "闪避率",
}
## 这些 key 在文案里带 % 号
const PCT_KEYS := ["crit", "critDmg", "dodgePct", "_lifestealPct"]
## 这些 key 在 stats 里是小数（0.09），文案里是百分数（9）
const X100_KEYS := ["crit", "critDmg"]
## ★负向前瞻：有的标签是另一个标签的前缀 ——「护甲」会匹配到「护甲穿透」里去，
##   于是门禁报"枪的文案写了护甲但 stats 里没有"，其实那是护甲穿透。
##   一开始漏了这条，②当场误红 3 次。加新标签时如果又出现前缀包含关系，这里要跟着加。
const NEG_LOOKAHEAD := {"护甲": "(?!穿透)"}
## 文案口径与 per-piece 不同的类型（食物数的是"全队每件装备"，不是本类型件数）⇒ 不参与逐字比对
const TEXT_EXEMPT := ["食物"]

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
	print("=== 羁绊文案 == 实装数值 ===")

	var missing: Array = []      # 实装有、文案没有（或数字不符）
	var extra: Array = []        # 文案有、实装没有
	var seg_bad: Array = []
	var checked := 0

	for t in Phase2Types.TYPES:
		var stats: Array = (Phase2Types.TYPES[t] as Dictionary).get("stats", [])
		var tiers: Array = (Phase2Types.TYPES[t] as Dictionary).get("tiers", [])
		var descs: Array = Phase2Types.TIER_DESCS.get(t, [])
		if descs.size() != tiers.size():
			seg_bad.append("%s 文案 %d 段 ≠ %d 档" % [t, descs.size(), tiers.size()])
		for i in range(mini(stats.size(), descs.size())):
			var txt: String = str(descs[i])
			if txt.strip_edges() == "":
				seg_bad.append("%s 档%d 文案是空的" % [t, i + 1])
				continue
			if t in TEXT_EXEMPT:
				continue
			var st: Dictionary = stats[i]
			# ① 实装的每条属性都要在文案里, 数字一致
			for k in st:
				if not LABEL.has(k):
					missing.append("%s 档%d 的 %s 没有登记中文名(LABEL 表要补)" % [t, i + 1, k])
					continue
				var want: float = float(st[k]) * (100.0 if k in X100_KEYS else 1.0)
				var pat := "\\+\\s*([0-9.]+)\\s*%s\\s*%s%s" % ["%" if k in PCT_KEYS else "",
					LABEL[k], str(NEG_LOOKAHEAD.get(LABEL[k], ""))]
				var re := RegEx.new()
				re.compile(pat)
				var m := re.search(txt)
				checked += 1
				if m == null:
					missing.append("%s 档%d 文案里【没写】%s(实发 %.2f)" % [t, i + 1, LABEL[k], want])
				elif absf(float(m.get_string(1)) - want) > 0.005:
					missing.append("%s 档%d 文案写 %s %s, 实发 %.2f" % [t, i + 1, LABEL[k], m.get_string(1), want])
			# ② 文案里写的「每件…提供 +N XX」都要在 stats 里
			var head: String = txt.split(" · ")[0]
			for k2 in LABEL:
				var re2 := RegEx.new()
				re2.compile("\\+\\s*([0-9.]+)\\s*%s\\s*%s%s" % ["%" if k2 in PCT_KEYS else "",
					LABEL[k2], str(NEG_LOOKAHEAD.get(LABEL[k2], ""))])
				if re2.search(head) != null and not st.has(k2):
					extra.append("%s 档%d 文案写了 %s, 但 stats 里没有" % [t, i + 1, LABEL[k2]])

	_ok("③ ★分母: 逐条比对了 %d 个属性数值" % checked, checked >= 25, "只比到 %d 个" % checked)
	_ok("① ★实装的每条属性都写进文案且数字一致", missing.is_empty(),
		"%d 条不符: %s" % [missing.size(), str(missing.slice(0, 6))])
	_ok("② ★文案里没有实装里不存在的加成", extra.is_empty(),
		"%d 条: %s" % [extra.size(), str(extra.slice(0, 4))])
	_ok("④ 文案段数 == 档数, 且每段非空", seg_bad.is_empty(), str(seg_bad))

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 羁绊文案与实装一致" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
