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
			var lv: int = gs.get_pet_level(str(pet.get("id", "")))
			var m: float = float(dr.rarity_mult.get(pet.get("rarity", "C"), 1.0)) * (1.0 + (lv - 1) * 0.05)
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

	_check_rules_no_round()

	print("")
	if _fail == 0:
		print("ALL PASS — 图鉴文案: 无占位符残留 / 无回合制陈旧模型 / 无开发术语 / 无空白字段 / 占位符全部可求值 / 规则之日不提「回合」")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════════════
# ⑥ 规则之日不许提「回合」 (2026-09-29 用户「假规则要删掉」)
# ══════════════════════════════════════════════════════════════════════
## 这是一款**实时**游戏 —— 全仓零个回合计数器(`当前回合数`/`round_index`/`current_round`
## 命中数 0), 局内小商店也早删干净了(CodexScene.gd:532 注释)。可 battle-rules.json 里
## 「装备之日」写着「每 3 回合双方各选 1 件装备」、「下雨天」写着「每回合 5×N (N = 当前
## 回合数)」—— 两条描述的机制玩家永远遇不到, 那两条已按用户要求删掉。
##
## ★判据形状: **json 里任何一个字符串字段都不许出现「回合」这两个字**。
##   范围就卡在这一份文件 —— json 没有注释, 键只有 id/name/emoji/icon/desc/color,
##   实测(删前)3 处「回合」全在那两条的 `desc` 里, 没有任何"正当的回合"要豁免。
##   (`verify_codex_text` 上面那张 BANNED 表管的是 pets.json 的技能文案, 两条互不覆盖。)
## ★两条分母: ① 真的扫到了 N 条规则(N=0 就是空检查) ② 其中至少一条有正文(desc 非空),
##   不然"没扫到回合"可能只是因为根本没读到字。
## ★2026-10-02 扩面: 原来只扫 battle-rules.json。同一天查出 `data/equipment.json` 的
##   消耗品 `desc` 里也有 3 处「回合」, 而消耗品整个机制在实时版里**零实现**
##   (图鉴之外 grep 命中 0) —— 已把图鉴那个分组删掉, 数据文件留着当将来的起点。
##   ⇒ 判据一并扫它, 「回合」回潮(或分组被重新打开)会当场红。
const RULES_JSON := "res://data/battle-rules.json"
const ROUND_WORD := "回合"

func _check_rules_no_round() -> void:
	print("  ── ⑥ 规则之日(battle-rules.json)不许提「回合」 ──")
	var txt := FileAccess.get_file_as_string(RULES_JSON)
	_ok("★分母: 读得到 battle-rules.json", txt.length() > 0, "%d 字符" % txt.length())
	if txt.length() == 0:
		_fail += 1
		return
	var parsed = JSON.parse_string(txt)
	_ok("battle-rules.json 是合法 JSON 数组", parsed is Array, "got=%s" % type_string(typeof(parsed)))
	if not (parsed is Array):
		return
	var rules: Array = parsed
	# ── 分母① 真的有条目 ──
	_ok("★分母: 扫到 %d 条规则(0 条 = 空检查不是通过)" % rules.size(), rules.size() > 0)
	# ── 分母② 至少一条有正文 ──
	var bodied := 0
	var body_chars := 0
	for r in rules:
		if not (r is Dictionary):
			continue
		var d: String = str((r as Dictionary).get("desc", ""))
		if d.length() >= 8:
			bodied += 1
			body_chars += d.length()
	_ok("★分母: 至少一条规则有正文(有正文 %d 条 / 共 %d 字)" % [bodied, body_chars],
		bodied > 0 and body_chars > 0)
	# ── 自检探针: 扫描器本身必须真的会命中 ──
	var probe: Array = _scan_rules_for_round([{
		"id": "_probe", "desc": "每 3 回合双方各选 1 件装备。",
	}])
	_ok("自检·已知阳性(埋一条「每 3 回合…」被抓到)", probe.size() == 1, str(probe))
	var probe2: Array = _scan_rules_for_round([{
		"id": "_probe", "desc": "风平浪静的一天，场上只有平常那套规矩。",
	}])
	_ok("自检·已知阴性(干净文案不误报)", probe2.is_empty(), str(probe2))
	# ── 真判据 ──
	var bad: Array = _scan_rules_for_round(rules)
	_ok("★★★⑥ 规则之日一条都不提「回合」(实时版没有回合这个概念)", bad.is_empty(),
		"命中 %d 处: %s" % [bad.size(), str(bad)])

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


## 扫一组规则条目里所有【字符串字段】有没有「回合」。
## 抽成函数是为了让上面的自检探针走**同一条路** —— 否则探针验的是另一份代码。
func _scan_rules_for_round(rules: Array) -> Array:
	var out: Array = []
	for r in rules:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		for k in d.keys():
			var v = d[k]
			if v is String and (v as String).find(ROUND_WORD) >= 0:
				out.append("%s.%s 命中「%s」" % [str(d.get("id", "?")), str(k), ROUND_WORD])
	return out


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
