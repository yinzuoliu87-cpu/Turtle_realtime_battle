extends Node

# 赛博龟·侵入 敌我关系守卫 (2026-07-22)
#
# 用户口径(原话):「场上我方有赛博龟和两个友军，敌方只有一个单位，那在侵入敌方后，
#   敌方应该直接发呆，而我方是要直接全部攻击该敌军的」
# 权威文档 docs/design/28龟技能设计-权威.md:1467 同口径:「被黑单位不算友军·会被打」。
#
# ★2026-07-22 之前的实现是【改写 side】, 把被侵入者变成了赛博方的真友军 →
#   赛博全队索敌/技能都跳过它, 还会给它加治疗。现在改为只挂标记, 由 _is_hostile 统一裁决。
#
# 本测试是【纯逻辑测试】: 直接复刻 _is_hostile/_is_ally/_eff_side 的语义做真值表校验,
# 再用源码扫描确认战斗场里没有残留的裸 side 敌我判定 —— 后者才是防回归的关键,
# 因为"漏改某一处"正是这个 bug 的成因(全工程曾有 20 处裸 side 判定)。

const SCENE_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fails: Array[String] = []


# ---- 被测语义的独立复刻(与战斗场实现对照, 不 import 以免被同一个 bug 同时污染) ----
func _hostile(a: Dictionary, b: Dictionary) -> bool:
	if a == b: return false                       # 测试内是纯数据字典, 无互引成环, 可安全用 ==
	if bool(b.get("hijacked", false)): return true
	if bool(a.get("hijacked", false)):
		return str(b.get("side", "")) == str(a.get("_hijack_orig_side", ""))
	return str(a.get("side", "")) != str(b.get("side", ""))

func _ally(a: Dictionary, b: Dictionary) -> bool:
	if a == b: return false
	return (not _hostile(a, b)) and (not _hostile(b, a))

func _eff(u: Dictionary) -> String:
	return str(u.get("_hijack_orig_side", u.get("side", ""))) if u.get("hijacked", false) else str(u.get("side", ""))


func _ready() -> void:
	_check_truth_table()
	_check_user_scenario()
	_check_source_has_primitive()
	_check_no_raw_side_targeting()
	_check_no_unit_dict_eq()
	_done()


## ① 敌我真值表 —— 不对称性是核心
func _check_truth_table() -> void:
	var cy := {"n": "赛博", "side": "left"}
	var v := {"n": "被侵入者", "side": "right", "hijacked": true, "_hijack_orig_side": "right"}
	var foe := {"n": "原队友", "side": "right"}
	var pal := {"n": "赛博队友", "side": "left"}
	var cases := [
		[cy, v, true,  "赛博方 → 被侵入者 必须能打(用户主诉)"],
		[pal, v, true, "赛博队友 → 被侵入者 必须能打"],
		[v, cy, false, "被侵入者 不打赛博方"],
		[v, foe, true, "被侵入者 打原队友"],
		[foe, v, true, "原队友 → 被侵入者 也能打(文档:也被原队友打)"],
		[cy, pal, false, "赛博 与 自家队友 不敌对"],
		[foe, cy, true, "原队友 与 赛博 正常敌对"],
	]
	for c in cases:
		var got: bool = _hostile(c[0], c[1])
		if got != bool(c[2]):
			_fail("真值表: %s —— 期望 %s 实得 %s" % [str(c[3]), str(c[2]), str(got)])
	# 友军判定: 被侵入者对谁都不是友军(孤军)
	for other in [cy, pal, foe]:
		if _ally(v, other) or _ally(other, v):
			_fail("被侵入者不该与 %s 互为友军(会导致赛博方给敌人加治疗/护盾)" % str(other["n"]))
	print("  [真值表] 校验 %d 条敌对关系 + 3 条友军关系" % cases.size())


## ② 用户给的具体场景: 我方赛博+2友军, 敌方仅 1 个被侵入单位
func _check_user_scenario() -> void:
	var cy := {"n": "赛博", "side": "left"}
	var f1 := {"n": "友军1", "side": "left"}
	var f2 := {"n": "友军2", "side": "left"}
	var v := {"n": "被侵入者", "side": "right", "hijacked": true, "_hijack_orig_side": "right"}
	var units := [cy, f1, f2, v]

	# 我方三个都要能打它
	for a in [cy, f1, f2]:
		if not _hostile(a, v):
			_fail("场景: %s 打不到被侵入者 —— 这正是用户主诉的 bug" % str(a["n"]))
	# 被侵入者【无目标 = 发呆】(原阵营已无其他存活单位)
	var tgts: Array = []
	for b in units:
		if _hostile(v, b):
			tgts.append(str(b["n"]))
	if not tgts.is_empty():
		_fail("场景: 被侵入者应当无目标(站着发呆), 实得目标 %s" % str(tgts))
	# 存活数按原阵营算 → 双方都没被抹空, 不会提前判胜负
	var l := 0
	var r := 0
	for u in units:
		if _eff(u) == "left": l += 1
		else: r += 1
	if l != 3 or r != 1:
		_fail("场景: 有效阵营存活数应为 left=3/right=1, 实得 left=%d/right=%d —— 会误判胜负" % [l, r])
	print("  [用户场景] 我方3打1 + 被侵入者发呆 + 存活数 left=%d/right=%d" % [l, r])


## ③ 战斗场里确实建了统一原语, 且侵入不再改写 side
func _check_source_has_primitive() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		_fail("读不到 %s" % SCENE_PATH)
		return
	for f in ["func _is_hostile(", "func _is_ally(", "func _eff_side(", "func _credit_killer("]:
		if src.find(f) < 0:
			_fail("缺少统一原语 %s" % f)
	# ★侵入本体绝不能再改写 side —— 那会让它变成赛博方的真友军
	var body := _func_body(src, "_sk_cyber_hijack")
	if body == "":
		_fail("找不到 _sk_cyber_hijack")
	else:
		# ★必须先剥注释: 函数里有一段注释在解释"旧实现 v["side"] = u["side"] 错在哪",
		#   不剥的话会把这段说明文字当成活代码报错(第一版就这么误报了)
		for bl in body.split("\n"):
			var code := _strip_comment(bl)
			if code.find("v[\"side\"] =") >= 0 or code.find("v[\"side\"]=") >= 0:
				_fail("_sk_cyber_hijack 又在改写 side —— 会让被侵入者变成赛博方真友军(赛博全队打不到它)")
				break
	# 嘲讽分支必须过敌我判定(否则同阵营互殴)
	# ★这里必须比【剥掉注释后的代码】: 那段函数的注释里本身就写着 _is_hostile 三个字,
	#   直接 find 会让"拆掉真调用"照样通过(2026-07-22 反向验证时实测到这个假通过)
	if _code_only(_func_body(src, "_acquire_target")).find("_is_hostile") < 0:
		_fail("_acquire_target 的嘲讽分支没过 _is_hostile —— 会出现同阵营互殴")
	# 终局判定必须用有效阵营(否则侵入掉最后一敌=瞬间判胜)
	if _code_only(_func_body(src, "_check_end")).find("_eff_side") < 0:
		_fail("_check_end 没用 _eff_side —— 侵入掉对方最后一只会瞬间判胜")
	print("  [源码] 原语齐备 + 侵入不改 side + 嘲讽/终局已收口")


## ④ 防回归的关键: 战斗场里不该再有【裸 side 敌我判定】
##   口径: 两个单位的 side 互比(如 o["side"] != u["side"])。
##   与字面量 "left"/"right" 比的那些是"判是不是玩家方"(UI配色/技能选择/局外数据), 不算。
## ⑤ 不得拿【单位字典】做 == / != 比较 (2026-07-22 补)
##
## ★项目铁律(CLAUDE.md §3.2 + _allies_of 的注释「is_same: 单位字典互引成环, ==/!= 会深比较
##   →有卡死风险(同053教训)」): 单位字典之间互相引用成环, Godot 的 == 是深比较, 会无限递归。
##   查侵入的召唤物联动(方案书 H9)时发现三处漏网: _sk_candy_bomb_feed / _hiding_minion_of /
##   缩头本体死亡同步杀随从, 全在写 `o.get("summon_owner", null) == u`。
##   同文件 8959 行早就用了正确写法 is_same(...), 所以不是不知道, 是漏改。
##   H9 本身的结论是【不受侵入影响】—— 那条链按 summon_owner 身份判定, 不看 side。
func _check_no_unit_dict_eq() -> void:
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		return
	var re := RegEx.new()
	# 形如  x.get("summon_owner", null) == u   /   x["taunt_by"] == y
	# ★必须排除与 null 比 —— `u["taunt_by"] != null` 是合法的空值判断, 不会触发深比较。
	#   第一版没排, 把它误报成违规(2026-07-22 实测)。
	# ★前瞻要把空白【包进去】写成 (?!\s*null) —— 写成 \s*(?!null) 会被回溯绕过:
	#   \s* 退回匹配零个空格后, 前瞻看到的是 " null" 而不是 "null", 于是判定通过(2026-07-22 实测)。
	re.compile("(get\\(\"(summon_owner|taunt_by|_hijack_by)\"[^)]*\\)|\\[\"(summon_owner|taunt_by|_hijack_by)\"\\])\\s*(==|!=)(?!\\s*null)")
	var hits: Array[String] = []
	var ln := 0
	for line in src.split("\n"):
		ln += 1
		var code := _strip_comment(str(line))
		if re.search(code) != null:
			hits.append("%d: %s" % [ln, code.strip_edges().substr(0, 72)])
	print("  [单位字典==] 命中 %d 处" % hits.size())   # ★打印分母
	if hits.is_empty():
		# 反向自检: 正则必须能命中人造样本, 否则 0 是假通过
		if re.search('if o.get("summon_owner", null) == u:') == null:
			_fail("单位字典== 扫描的正则失效(人造样本都匹配不到) —— 这个 0 是假通过")
	else:
		for h in hits:
			_fail("拿单位字典做 ==/!= 深比较, 互引成环会卡死, 应用 is_same() → %s" % h)


func _check_no_raw_side_targeting():
	var src := FileAccess.get_file_as_string(SCENE_PATH)
	if src == "":
		return
	var re := RegEx.new()
	# 形如  x["side"] == y["side"]  /  != 。排除与字面量比的。
	re.compile("\\[\"side\"\\]\\s*(==|!=)\\s*[A-Za-z_][A-Za-z0-9_]*(\\[\"side\"\\]|\\.get\\(\"side\")")
	var hits: Array[String] = []
	var lineno := 0
	for line in src.split("\n"):
		lineno += 1
		var code := _strip_comment(str(line))   # ★行尾注释也要剥: 收口时留下的"★原为 o["side"] == u["side"]"说明会被误报
		if code.strip_edges() == "":
			continue
		if re.search(code) != null:
			hits.append("%d: %s" % [lineno, code.strip_edges().substr(0, 70)])
	print("  [裸 side 扫描] 命中 %d 处" % hits.size())   # ★打印分母: N=0 要能区分"真干净"与"正则失效"
	if hits.is_empty():
		# 反向自检: 正则必须能命中一条人造样本, 否则 0 是假通过
		if re.search('if o["side"] != u["side"]:') == null:
			_fail("裸 side 扫描的正则失效(连人造样本都匹配不到) —— 这个 0 是假通过")
	else:
		for h in hits:
			_fail("残留裸 side 敌我判定, 侵入下会失效 → %s" % h)


## 去掉行尾注释, 但【不能】简单按第一个 # 截断 —— 本文件里满是 Color("#ff9a5a") 这类
## 带 # 的字符串字面量, 那样切会把有效代码也切掉(造成漏报)。所以要判引号状态。
func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


## 整段剥注释 —— 任何"函数体里有没有某个调用"的断言都必须先过这一层,
## 否则注释里提到那个名字就会造成假通过。
func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out


func _func_body(src: String, fname: String) -> String:
	var head := "\nfunc %s(" % fname
	var i := src.find(head)
	if i < 0:
		return ""
	var start := i + 1
	var j := src.find("\nfunc ", start)
	if j < 0:
		j = src.length()
	return src.substr(start, j - start)


func _fail(msg: String) -> void:
	_fails.append(msg)


func _done() -> void:
	if _fails.is_empty():
		print("ALL PASS — 赛博侵入敌我关系正确")
	else:
		for f in _fails:
			printerr("FAIL: %s" % f)
		printerr("FAIL — 赛博侵入 %d 项不通过" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
