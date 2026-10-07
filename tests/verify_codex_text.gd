extends Node
## verify_codex_text.gd — 守卫: data/pets.json 里【会显示给玩家】的文案不许再出现陈旧/开发术语/占位符
##
## 由来 (2026-07-10 图鉴文案对账 轮A~H′):
##   逐轮撞出来的教训是「我只审我正在看的那个字段」。pets.json 里会显示的文案字段共 5 类:
##     passive.brief   → 选龟界面 被动 chip 的 tooltip   (TeamSelectScene.gd:1155)
##     passive.desc    → 图鉴被动区 (CodexScene.gd:1069) + 局内信息面板 (RealtimeBattle3DScene.gd:13555)
##     skillPool[i].brief / .detail → 图鉴技能卡 (CodexScene.gd:943 / 1060)
##     volcanoSkills[i].brief / .detail → 图鉴【双形态】切换区 (CodexScene.gd:873-879) — 仅熔岩
##   历史事故:
##     · `_lineFinishBrief_` / `_lineFinishDetail_` 占位符【直接显示给玩家】(轮E)
##     · 凤凰/熔岩 整块还是回合制的「灼烧【值】」模型 (轮E/F)
##     · pirate.brief 写着「海盗龟无被动技能(掠夺已移除)」, 与实装的死亡钩索正面冲突 (轮H′)
##     · cyber 的技能说明里漏出「F5精修」「kite近似」这类开发术语 (轮H′)
##
## 本测试做【便宜且不会误伤】的黑名单扫描 + 结构完整性检查 + 占位符可求值(第5节·2026-07-28补)。
## 它拦不住"数值写错", 但能拦住"占位符/陈旧模型/开发术语/整块空白/公式印到界面上"这五类已真实发生过的事故。

var _fail := 0

# (子串, 为什么禁)
const BANNED := [
	["_lineFinish", "占位符: 曾直接显示给玩家"],
	["灼烧值", "回合制模型: 实时版是灼烧【层】"],
	["无被动技能", "pirate.brief 曾这样写, 与实装的死亡钩索冲突"],
	["掠夺已移除", "同上"],
	["F5", "开发术语, 不该出现在玩家看的文案里"],
	["TODO", "开发术语"],
	["待接入", "开发术语"],
	["占位", "开发术语"],
	["kite", "开发术语"],
	["A级及以下", "缩头召唤池实为12只固定名单(含SS级无头龟)"],
	["每2.5秒获得", "财神聚宝盆实为每3秒 4~7 枚"],
]

# 每只龟至少要有的文案字段
const REQUIRED_PASSIVE := ["brief", "desc"]


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	if f == null:
		print("  [FAIL] 读不到 data/pets.json")
		get_tree().quit(1)
		return
	var txt := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	_ok("pets.json 是合法 JSON", parsed != null)
	if parsed == null:
		get_tree().quit(1)
		return
	var pets: Array = parsed["pets"] if (parsed is Dictionary and parsed.has("pets")) else parsed
	_ok("28 只龟", pets.size() == 28, "got=%d" % pets.size())

	# ── 1. 自检探针: 黑名单机制本身必须真的会命中 ──────────────────────────
	#    (我被自己的普查脚本骗过 3 次 → 扫描器先证明自己没瞎)
	var probe_hit := _scan_text("basic", "x.y", "这里故意塞一个 灼烧值 试试", "灼烧值")
	_ok("自检·已知阳性(埋入「灼烧值」被抓到)", probe_hit)
	var probe_miss := _scan_text("basic", "x.y", "一段完全干净的文案", "灼烧值")
	_ok("自检·已知阴性(干净文案不误报)", not probe_miss)

	# ── 2. 黑名单扫描: 5 类会显示的字段 ────────────────────────────────────
	var offenders: Array = []
	for p in pets:
		var pid := str(p.get("id", "?"))
		var pas: Dictionary = p.get("passive", {})
		for k in REQUIRED_PASSIVE:
			offenders.append_array(_check(pid, "passive." + k, str(pas.get(k, ""))))
		for arr_key in ["skillPool", "volcanoSkills", "meleeSkills"]:
			var arr = p.get(arr_key, [])
			if not (arr is Array):
				continue
			for i in (arr as Array).size():
				var sk: Dictionary = arr[i]
				offenders.append_array(_check(pid, "%s[%d].brief" % [arr_key, i], str(sk.get("brief", ""))))
				offenders.append_array(_check(pid, "%s[%d].detail" % [arr_key, i], str(sk.get("detail", ""))))
	_ok("黑名单扫描 (5 类会显示的字段)", offenders.is_empty(),
		"命中 %d 处: %s" % [offenders.size(), str(offenders.slice(0, 5))])

	# ── 3. 结构完整性: 会显示的字段不许为空 ────────────────────────────────
	var empties: Array = []
	for p in pets:
		var pid := str(p.get("id", "?"))
		var pas: Dictionary = p.get("passive", {})
		for k in REQUIRED_PASSIVE:
			if str(pas.get(k, "")).strip_edges() == "":
				empties.append("%s.passive.%s" % [pid, k])
		var pool = p.get("skillPool", [])
		if pool is Array:
			for i in (pool as Array).size():
				var sk: Dictionary = pool[i]
				for k2 in ["brief", "detail"]:
					if str(sk.get(k2, "")).strip_edges() == "":
						empties.append("%s.skillPool[%d].%s" % [pid, i, k2])
	_ok("会显示的文案字段无空白", empties.is_empty(), str(empties.slice(0, 5)))

	# ── 4. 每只龟 skillPool 恰好 4 格 (普攻 + 3选1 候选) ───────────────────
	var wrong_pool: Array = []
	for p in pets:
		var pool = p.get("skillPool", [])
		if not (pool is Array) or (pool as Array).size() != 4:
			wrong_pool.append("%s=%d" % [str(p.get("id", "?")), (pool as Array).size() if pool is Array else -1])
	_ok("每只龟 skillPool = 4 格 (普攻 + 3选1)", wrong_pool.is_empty(), str(wrong_pool))

	# ── 5. 占位符可求值 (2026-07-28 新增) ─────────────────────────────────
	#    图鉴不是直接显示原文, 而是过 SkillText.render_html 把 {N:1.1*ATK} 这类占位符算成数字。
	#    ★eval_expr 求值失败时返回的是【去掉花括号的原始表达式】(skill_text.gd:70) ——
	#      所以坏占位符渲染成 "0.8*BADTOKEN" 而不是 "{0.8*BADTOKEN}"。
	#      判定必须放在【模板层】: 在渲染结果里找 "{…}" 是找不到的, 那样写出来的是假绿灯(实测过)。
	#    2026-07-28 用它抓到: 石头龟被动的 {D:initDef*maxDefInitPct/100/capTurns} 求不出值,
	#      玩家在图鉴上直接看到公式原文。
	## ⚠ 这条正则是**本文件自己的一份**, 和 skill_text.gd 里那条是两份手抄 —— 加 token 要两边都改。
	## ★不自己抄正则 —— 字母表的唯一出处是 SkillText.COLOR_CLASS, 见 token_regex() 的头注。
	##   这里原来写死 `[NPHSBDMTC]`, 新增 `{E:}` 之后它不认, 把一个**正确**的占位符判成求不出数字。
	var tok := SkillText.token_regex()
	var dr = get_node_or_null("/root/DataRegistry")
	var gs = get_node_or_null("/root/GameState")
	var unresolved: Array = []
	var n_tok := 0
	if dr != null and gs != null:
		for p2 in pets:
			var pet: Dictionary = p2
			var lv: int = 1
			var m: float = 1.0   # 只验占位符求不求得出值; 数值口径由 verify_codex_battle_parity 管(图鉴不乘稀有度)
			var ctx := {
				"atk": roundi(pet.get("atk", 0) * m), "def": roundi(pet.get("def", 0) * m),
				"mr": roundi(pet.get("mr", pet.get("def", 0)) * m), "maxHp": roundi(pet.get("hp", 0) * m),
				"crit": pet.get("crit", 0.0), "lv": lv,
			}
			var fields: Array = []
			var pas2: Dictionary = pet.get("passive", {})
			for k in ["brief", "desc"]:
				fields.append(["passive." + k, str(pas2.get(k, "")), pas2])
			for arr_key in ["skillPool", "volcanoSkills", "meleeSkills"]:
				var arr2 = pet.get(arr_key, [])
				if not (arr2 is Array):
					continue
				for i in (arr2 as Array).size():
					var sk2: Dictionary = arr2[i]
					for k2 in ["brief", "detail"]:
						fields.append(["%s[%d].%s" % [arr_key, i, k2], str(sk2.get(k2, "")), sk2])
			for fd in fields:
				var raw: String = str(fd[1])
				if raw == "":
					continue
				var vars2 := SkillText.build_vars(ctx, fd[2])
				for mm in tok.search_all(raw):
					n_tok += 1
					var expr: String = mm.get_string(2)
					if expr == "":
						expr = mm.get_string(3)
					## ★2026-08-20: {C:类名.常量名} 走的是另一条求值路(直接读代码常量, 不经 vars),
					##   `eval_expr` 对它只会原样吐回字符串。判据得认这一支, 否则会把**正确的引用**判成"求不出数字"。
					##   —— 这是同一晚第三次踩"消费方各写各的求值器": 商店、verify_equip_batch3、这里。
					var v
					if mm.get_string(1) == "C":
						var cv: String = SkillText.const_of(expr)
						## 取不到时 const_of 原样吐回 "{C:...}" ⇒ 这里就会判成没求出来, 正是我们要的
						v = (float(cv) if cv.is_valid_float() else (cv if cv.contains("/") and not cv.begins_with("{") else cv))
						if v is String and (v as String).contains("/") and not (v as String).begins_with("{"):
							v = 0.0   # 三档 "3/5/8" 是合法渲染结果, 算求得出
					else:
						v = SkillText.eval_expr(expr, vars2)
					if not (v is int or v is float):
						unresolved.append("%s %s %s→印出\"%s\"" % [str(pet.get("id", "?")), str(fd[0]), mm.get_string(), str(v)])
	else:
		_fail += 1
		print("  [FAIL] 缺 autoload, 占位符求值检查没跑")
	_ok("占位符全部能求出数字 (扫了 %d 个)" % n_tok, unresolved.is_empty(), str(unresolved.slice(0, 4)))

	## ★★全仓只许 `skill_text.gd` 自己写占位符正则 (2026-10-02 焊进来)。
	## 【由来】这张字母表在仓里有过**三份**: `COLOR_CLASS`(颜色) / `_token_re`(求值) /
	##   **本文件自己又抄了一份**。往 COLOR_CLASS 加 `"E"` 之后前两份对上了、第三份没有,
	##   于是一个**正确**的占位符被判成"求不出数字"。
	##   而本文件 160 行附近的注释里早就写着「这是同一晚第三次踩**消费方各写各的求值器**」
	##   —— 这回是第四次。记 memory `fb-hand-rolled-copies-drift`。
	## ⇒ 判据量的是**源码事实**: 除了 skill_text.gd, 没有第二个文件在构造这个形状的正则。
	var copies: Array[String] = []
	var n_scan := 0
	for d in ["res://scripts", "res://tests", "res://autoload"]:
		n_scan += _scan_gd(d, copies)
	print("  [分母] 扫了 %d 个 .gd 找手抄的占位符正则" % n_scan)
	_ok("★分母: 真的扫到 .gd(0 个 ⇒ 下一条是空检查)", n_scan >= 100, "只有 %d 个" % n_scan)
	_ok("★占位符正则全仓只许一份(在 skill_text.gd; 别处要扫占位符请调 SkillText.token_regex())",
		copies.is_empty(), str(copies))
	_ok("★分母: 占位符数 > 0 (0 个 = 空检查不是通过)", n_tok > 0, "n_tok=%d" % n_tok)

	_check_no_rules_tab()

	print("")
	if _fail == 0:
		print("ALL PASS — 图鉴文案: 无占位符残留 / 无回合制陈旧模型 / 无开发术语 / 无空白字段 / 占位符全部可求值 / 没有规则页签")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════════════
# ⑥ 图鉴里没有「规则」页签(2026-10-07 用户「规则页直接删掉，我们没有这东西」)
# ══════════════════════════════════════════════════════════════════════
## 历史: 2026-09-29 先按「假规则要删掉」删了「装备之日/下雨天」两条(写着「每 3 回合…」),
##   这里原来守的是「battle-rules.json 不许提回合」。2026-10-07 用户拍板整页删除 ——
##   剩下 5 条「XX之日」在实时版战斗里**一条都没生效**, 唯一读者就是图鉴的规则页签。
## ★判据量产品自己的账(不 grep 我的注释):
##   ① CodexScene.TABS(页签的唯一出处)里没有 rules, 且恰好剩 4 个(分母: 页签表真读到了)
##   ② DataRegistry 上不再有 battle_rules 这个属性, 数据文件也不在了
##   ③ 图鉴两份源码的**代码部分**(去掉注释)不再出现 _show_rule / battle_rules / sprites/rules
func _check_no_rules_tab() -> void:
	print("  ── ⑥ 图鉴里没有「规则」页签 ──")
	var codex_scr: Script = load("res://scripts/scenes/CodexScene.gd")
	var cm: Dictionary = codex_scr.get_script_constant_map()
	var tabs: Array = cm.get("TABS", [])
	var ids: Array = []
	for t in tabs:
		ids.append(str((t as Array)[0]))
	_ok("★分母: 读到了 CodexScene.TABS(%d 个页签: %s)" % [ids.size(), str(ids)], ids.size() >= 4)
	_ok("★★⑥ 页签表里没有 rules, 恰好 龟/装备/羁绊/状态 四个", not ids.has("rules") and ids.size() == 4, str(ids))
	var dr = get_node_or_null("/root/DataRegistry")
	_ok("★分母: DataRegistry 在", dr != null)
	if dr != null:
		var has_prop := false
		for pr in dr.get_property_list():
			if str(pr.get("name", "")) == "battle_rules":
				has_prop = true
		_ok("★⑥ DataRegistry 不再载入规则表(没有 battle_rules 属性)", not has_prop)
	_ok("★⑥ data/battle-rules.json 已删", not FileAccess.file_exists("res://data/battle-rules.json"))
	var n_src := 0
	var hits: Array = []
	for f in ["res://scripts/scenes/CodexScene.gd", "res://scripts/scenes/codex/detail_views.gd",
			"res://scripts/scenes/codex/list_builder.gd"]:
		var src := FileAccess.get_file_as_string(f)
		if src.length() > 500:
			n_src += 1
		var ln_i := 0
		for ln in src.split(String.chr(10)):
			ln_i += 1
			var code := ln.split("#")[0]
			for w in ["_show_rule", "battle_rules", "sprites/rules", "icon-rules"]:
				if code.contains(w):
					hits.append("%s:%d %s" % [f.get_file(), ln_i, w])
	_ok("★分母: 读到 3 份图鉴源码", n_src == 3)
	_ok("★★⑥ 图鉴源码(代码部分)不再碰规则页", hits.is_empty(), str(hits))

	## ⑥b 图鉴不许再建【消耗品分组】。
	##
	## ★★判据形状换过一次, 记下来: 第一版我去扫 `data/equipment.json` 里还有没有「回合」
	##   —— **卡错了形状**。那个数据文件现在是**死的**(图鉴之外 grep 命中 0, 分组也删了),
	##   它里面写什么都不影响玩家; 而且它那 3 条「回合」是回合制时代的原话,
	##   消耗品**一行实现都没有** ⇒ 我没有任何依据把「3 回合」翻译成「N 秒」,
	##   硬翻就是**替一个不存在的功能编规格**。
	## ⇒ 真正要挡的是**分组被重新打开**。那一刻玩家才会看到回合制文案。
	##   判据就卡这件事: `list_builder.gd` 里不许出现 `consumable`。
	var lb := FileAccess.get_file_as_string("res://scripts/scenes/codex/list_builder.gd")
	_ok("★分母: 读得到 list_builder.gd", lb.length() > 500, "%d 字符" % lb.length())
	var n_c := 0
	for ln in lb.split("
"):
		var code := ln.split("#")[0]
		if code.contains("consumable"):
			n_c += 1
	_ok("★⑥b 图鉴不再建消耗品分组(整个机制实时版零实现, 文案还是回合制的)",
		n_c == 0, "list_builder.gd 里有 %d 行代码提到 consumable" % n_c)


func _scan_text(_pid: String, _path: String, text: String, needle: String) -> bool:
	return text.find(needle) >= 0


func _check(pid: String, path: String, text: String) -> Array:
	var out: Array = []
	if text == "":
		return out
	for row in BANNED:
		if text.find(str(row[0])) >= 0:
			out.append("%s.%s 命中「%s」(%s)" % [pid, path, str(row[0]), str(row[1])])
	return out

## 递归找「自己构造占位符正则」的 .gd。★递归走, 不按我以为的层级。
## ★返回扫到的 .gd 个数 —— 第一版用 `counter: Callable` 往外加,
##   而 **GDScript 的 lambda 是按值捕获的**, 外面那个 `n_scan` 永远是 0 ⇒
##   「只许一份」那条当场变成空检查(配套的分母断言把它抓住了, 这就是分母断言的用处)。
func _scan_gd(dir_path: String, out: Array[String]) -> int:
	var n := 0
	var da := DirAccess.open(dir_path)
	if da == null:
		return 0
	da.list_dir_begin()
	var nm := da.get_next()
	while nm != "":
		var p := dir_path + "/" + nm
		if da.current_is_dir():
			if not nm.begins_with("."):
				n += _scan_gd(p, out)
		elif nm.ends_with(".gd"):
			n += 1
			if p.ends_with("/skill_text.gd"):
				nm = da.get_next()
				continue
			var src := FileAccess.get_file_as_string(p)
			## 形状: create_from_string 里带着 `{`…`:` 的 token 文法。
			## ★针要【拼出来】—— 整串写在一行里的话, 这条判据会匹配到它自己(第一版就是这样当场假红)。
			var needle := "]):(" + "[^}]+)"
			for ln in src.split("\n"):
				if ln.contains("create_from_string") and ln.contains(needle):
					out.append(p.replace("res://", ""))
					break
		nm = da.get_next()
	da.list_dir_end()
	return n
