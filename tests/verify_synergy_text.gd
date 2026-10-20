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
	"atk": "攻击力", "def": "护甲", "mr": "魔抗", "crit": "暴击率",
	"critDmg": "暴击伤害", "armorPen": "护甲穿透", "magicPen": "魔法穿透",   # 2026-10-07 统一成战斗面板的「魔法穿透」
	"_lifestealPct": "生命偷取", "_maxEnergy": "最大龟能", "dodgePct": "闪避",
	"_aspdPct": "攻击速度", "healAmp": "治疗强度", "shieldAmp": "护盾强度",
}
## 这些 key 在文案里带 % 号
const PCT_KEYS := ["crit", "critDmg", "dodgePct", "_lifestealPct", "_aspdPct", "_mspdPct", "_rangePct",
	"healAmp", "shieldAmp"]
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

	_wording_1020()

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 羁绊文案与实装一致" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## ⑤~⑨ 羁绊描述措辞五点(待拍板清单 三、2; 用户 2026-10-20「你自己推进不要等我」⇒ 按建议全部执行)。
##   ⑤ 「每场 / 本场」统一成「每局 / 本局」
##   ⑥ 词条名【腐蚀·穿透】→【穿透】、【腐蚀叠层】→【腐蚀】
##   ⑦ 高档不重复写已解锁且没变的效果: 高档里每个 {C:类.常量[k]} 的值必须 ≠ 上一档 [k-1]
##      (值没变还写出来 = 重复; 判的是【渲染出来的值】, 不是字面量)
##   ⑧ 灵物触手高档写「变为原来的 X%」, X 读 SpiritSynergySystem.HIT_MULT
##   ⑨ 枪【金弹】逐档的发数与真伤比例读 GunSynergySystem.GOLD_EVERY / GOLD_TRUE_PCT, 不写字面量
func _wording_1020() -> void:
	var all_txt: Array = []
	for t in Phase2Types.TIER_DESCS:
		for d in Phase2Types.TIER_DESCS[t]:
			all_txt.append(str(d))
	for t in Phase2Types.TYPE_INTRO:
		for d in Phase2Types.TYPE_INTRO[t]:
			all_txt.append(str(d))
	_ok("⑤⑥ ★分母: 扫了 %d 段羁绊文案" % all_txt.size(), all_txt.size() >= 30)
	var bad_word: Array = []
	for s in all_txt:
		for w in ["每场", "本场", "腐蚀·穿透", "腐蚀叠层"]:
			if str(s).contains(w):
				bad_word.append(w)
	_ok("⑤⑥ 羁绊文案里没有「每场/本场/腐蚀·穿透/腐蚀叠层」", bad_word.is_empty(), str(bad_word))

	var re := RegEx.create_from_string("\\{C:([A-Za-z0-9_]+\\.[A-Z0-9_]+)\\[(\\d+)\\](%?)\\}")
	var compared := 0
	var repeated: Array = []
	for t in Phase2Types.TIER_DESCS:
		var descs: Array = Phase2Types.TIER_DESCS[t]
		for i in range(1, descs.size()):
			for m in re.search_all(str(descs[i])):
				var k: int = int(m.get_string(2))
				if k < 1:
					continue
				var ref: String = m.get_string(1)
				var pc: String = m.get_string(3)
				var cur: String = SkillText.const_of("%s[%d]%s" % [ref, k, pc])
				var prev: String = SkillText.const_of("%s[%d]%s" % [ref, k - 1, pc])
				compared += 1
				if cur.begins_with("{C:") or cur == prev:
					repeated.append("%s 档%d %s[%d]=%s 上一档=%s" % [t, i + 1, ref, k, cur, prev])
	_ok("⑦ ★分母: 比了 %d 个高档占位符" % compared, compared >= 40, "只比到 %d 个" % compared)
	_ok("⑦ 高档没有重复写值没变的效果(且每个占位符都解析得出)", repeated.is_empty(), str(repeated))

	var spirit: Array = Phase2Types.TIER_DESCS.get("灵物", [])
	var mult_ok := spirit.size() == 4
	for i in [2, 3]:
		if i < spirit.size():
			var s: String = str(spirit[i])
			mult_ok = mult_ok and s.contains("变为原来的 {C:SpiritSynergySystem.HIT_MULT[%d]%%}%%" % i)
	_ok("⑧ 灵物 3/4 档触手写「变为原来的 {C:HIT_MULT[i]%}%」", mult_ok)
	_ok("⑧ 渲染出来是「变为原来的 150%」(第 3 档)",
		SkillText.render_consts(str(spirit[2]) if spirit.size() > 2 else "").contains(
			"变为原来的 %s%%" % SkillText.const_of("SpiritSynergySystem.HIT_MULT[2]%")))

	var gun: Array = Phase2Types.TIER_DESCS.get("枪", [])
	var gold_ok := gun.size() == 3
	var gold_lit: Array = []
	var dig := RegEx.create_from_string("[0-9]+")
	for i in range(gun.size()):
		var seg := ""
		for part in str(gun[i]).split(" · "):
			if str(part).begins_with("【金弹】"):
				seg = str(part)
		gold_ok = gold_ok and seg.contains("{C:GunSynergySystem.GOLD_EVERY[%d]}" % i) \
			and seg.contains("{C:GunSynergySystem.GOLD_TRUE_PCT[%d]%%}%%" % i)
		## 去掉占位符后剩下的数字只许是「1 发」的 1
		var bare: String = RegEx.create_from_string("\\{C:[^}]+\\}").sub(seg, "", true)
		for m in dig.search_all(bare):
			if m.get_string(0) != "1":
				gold_lit.append("档%d:%s" % [i + 1, m.get_string(0)])
	_ok("⑨ 枪【金弹】三档都读 GOLD_EVERY[i] / GOLD_TRUE_PCT[i]", gold_ok)
	_ok("⑨ 枪【金弹】段里没有手写数字(除「1 发」)", gold_lit.is_empty(), str(gold_lit))
