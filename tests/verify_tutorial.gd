extends Node

## verify_tutorial.gd — 新手引导真的跑得起来 (2026-07-22)
##
## 用户需求1:「全面优化新手引导…比如右上角新手引导模式」。
## 调查结论: scripts/scenes/TutorialGuide.gd 143 行【完整实现】, 但**全项目零引用** ——
## 主菜单「❓教程」只设了 GameState.tutorial=true 就进普通战斗, 而战斗场零处读这个 flag。
## 教程步骤数据也不存在。等于一套写好的东西从来没人按开关。
##
## ★所以这条门禁的重点是【它真的被接上了】, 而不是"代码写得对不对":
##   死代码永远是"对"的。

const TutorialGuide := preload("res://scripts/scenes/TutorialGuide.gd")
const STEPS_JSON := "res://data/tutorial-steps.json"

var _fail := 0
var _done_called := false


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	_test_steps_data()
	await _test_guide_runs()
	_test_wired_in()
	_test_touch_only()
	await _test_tutorial_claims()
	await _test_guide_host()
	print("  [耗帧] 本测试共跑 %d 帧(默认预算 500 帧; 超了会被 --quit-after 掐断 ⇒ 打不出 ALL PASS)"
		% Engine.get_process_frames())
	print("ALL PASS — 新手引导已接线且能推进" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## ① 步骤数据本身
func _test_steps_data() -> void:
	var raw := FileAccess.get_file_as_string(STEPS_JSON)
	_ok("读得到 tutorial-steps.json", raw != "")
	var parsed = JSON.parse_string(raw)
	_ok("是合法 JSON 对象", parsed is Dictionary)
	if not (parsed is Dictionary):
		return
	var n_keys := 0
	var n_steps := 0
	for k in (parsed as Dictionary).keys():
		if str(k).begins_with("_"):
			continue
		var arr = parsed[k]
		if arr is Array:
			n_keys += 1
			n_steps += (arr as Array).size()
			for st in arr:
				_ok("%s 的每一步都有 text" % str(k), st is Dictionary and str(st.get("text", "")) != "",
					"缺 text: %s" % str(st))
	print("  [分母] 引导场景 %d 个, 步骤共 %d 步" % [n_keys, n_steps])
	_ok("★步骤分母非 0(N=0 是空检查不是通过)", n_keys > 0 and n_steps > 0)
	# steps_for 取得到
	## 2026-10-19 去掉 place(对局里没有摆位了); 2026-10-21 v4 去掉 team_select(进教程直接进战斗, 阵容预配)
	for key in ["battle", "settle", "shop", "inventory"]:
		var steps := TutorialGuide.steps_for(key)
		_ok("steps_for(\"%s\") 取得到步骤" % key, steps.size() > 0, "%d 步" % steps.size())
	_ok("★v5: 选龟屏有引导步骤(分镜 B1~B4: 教程又经过选龟屏)", TutorialGuide.steps_for("team_select").size() >= 4)
	_ok("steps_for 对不存在的 key 返回空而不是崩",
		TutorialGuide.steps_for("__不存在的场景__").is_empty())


## ② 真跑一遍: 建 UI → 只靠动作事件推进 → 结束回调
## (2026-10-07 重做: 引导条没有「下一步」按钮了, 每一步都靠 advanceOn 事件; 细节见 verify_tutorial_steps_v2)
func _test_guide_runs() -> void:
	var g = TutorialGuide.new()
	add_child(g)
	var steps := [
		{"text": "第一步", "highlight": "t", "advanceOn": "e1"},
		{"text": "第二步", "highlight": "t", "advanceOn": "手动事件"},
		{"text": "第三步", "highlight": "t", "advanceOn": "e3"},
	]
	g.start(steps, func() -> void: _done_called = true, func(_n: String) -> Rect2: return Rect2(100, 100, 200, 60))
	for _i in range(TutorialGuide.STABLE_FRAMES + 3):
		await get_tree().process_frame
	_ok("★引导真的显示出来了", g.is_showing())
	print("  [实测] 第1步显示 = %s" % g.current_text())
	_ok("★显示的是第一步的内容", g.current_text() == "第一步", g.current_text())
	g.notify("e1")
	_ok("★做了第一步的动作 ⇒ 第二步", g.current_text() == "第二步")
	# notify: 名字不对不该推进 —— 否则任何事件都能乱推
	g.notify("不相干的事件")
	_ok("★notify 事件名不匹配时【不】推进", g.current_text() == "第二步", "被别的事件推走了")
	g.notify("手动事件")
	_ok("★notify 事件名匹配时推进到第三步", g.current_text() == "第三步")
	_ok("结束前 on_done 还没被调用", not _done_called)
	g.notify("e3")
	await get_tree().process_frame
	_ok("★走完最后一步会调 on_done", _done_called)


## ③ 真的被接上了 —— 这才是本轮的核心, 死代码永远是"对"的
## (2026-10-07: 五屏都经导演 `attach_guide` 挂; 导演自己在非教程时返回 null —— 正常对局不弹)
func _test_wired_in() -> void:
	var hosts := {
		"res://scripts/scenes/TeamSelectScene.gd": 'attach_guide(self, "team_select")',
		"res://scripts/scenes/battle/battle_hud.gd": 'attach_guide(battle, "settle"',
		"res://scripts/scenes/ShopScene.gd": 'attach_guide(self, "shop")',
		"res://scripts/scenes/InventoryScene.gd": 'attach_guide(self, "inventory")',
	}
	var refs := 0
	for path in hosts.keys():
		var src := _code_only(FileAccess.get_file_as_string(path))
		var hit: bool = src.contains(str(hosts[path]))
		_ok("★%s 接上了引导(%s)" % [str(path).get_file(), str(hosts[path])], hit)
		if hit:
			refs += 1
	print("  [分母] 接上引导的屏 %d 个" % refs)
	var dsrc := _code_only(FileAccess.get_file_as_string("res://autoload/tutorial_director.gd"))
	var body := dsrc.substr(dsrc.find("func attach_guide"), 400)
	_ok("★引导只在教程里才建(attach_guide 第一件事就是 is_active 判断; 正常对局不该弹)",
		body.contains("if not is_active():") and body.contains("return null"))
	var bat := _code_only(FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd"))
	_ok("★★战斗场 _ready 里不挂引导(开场演出期间不许出提示, 方案书 B1)", not bat.contains("attach_guide("))
	## ★2026-10-19 对局里没有摆位环节了(站位在背包里摆) ⇒ 开打前不挂任何引导; 战斗里只剩结算那一句(battle_hud)。
	var dlf := _code_only(FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd"))
	_ok("★★对局开打前不挂引导(dual_lane_flow 里没有 attach_guide)", dlf.length() > 1000 and not dlf.contains("attach_guide("))


func _find_rich(n: Node) -> RichTextLabel:
	if n is RichTextLabel:
		return n
	for c in n.get_children():
		var r := _find_rich(c)
		if r != null:
			return r
	return null


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


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("\n"):
		out += _strip_comment(str(l)) + "\n"
	return out


# ══════════════════════════════════════════════════════════════════════════
#  ④ ★TOUCH_ONLY —— 玩家可见文案里不许出现 PC 专属操作词
# ══════════════════════════════════════════════════════════════════════════
## 由来 (2026-09-29 台账 ①): team_select 第 2 步原文是「把**鼠标停在**技能图标上看说明」,
##   而这是 iOS 触屏游戏。★产品自己的代码写着相反的话 ——
##   `scripts/scenes/team_select/skill_picker.gd` 注释「点/触 技能图标 → 弹窗…(手机无 hover 的唯一途径)」
##   并且真接了点击弹窗。同族还有战斗教学的「滚轮缩放 / 按住左键拖动视角」。
## ★判据不是"改掉那一句", 是**这一类词不许再出现** —— 改文案的人想不起这条纪律, 门禁会。
## ★分母 = 扫到多少条玩家可见字符串。扫到 0 条就是空检查, 不是通过。
const TOUCH_BANNED := {
	"鼠标": "触屏游戏, 玩家手上没有鼠标",
	"悬停": "手机没有 hover 态",
	"滚轮": "手机没有滚轮",
	"右键": "手机没有右键",
	"左键": "手机没有左键",
	"中键": "手机没有中键",
	"hover": "同上",
	"回车键": "手机上只有输入框才弹软键盘",
	"快捷键": "手机没有键盘快捷键",
}


func _test_touch_only() -> void:
	var files := _json_files("res://data")
	var n_str := 0
	var hits: Array = []
	for f in files:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(f))
		var strs: Array = []
		_collect_strings(parsed, strs)
		n_str += strs.size()
		for s in strs:
			for w in TOUCH_BANNED.keys():
				if str(s).contains(str(w)):
					hits.append("%s 出现「%s」(%s): %s" % [
						f.get_file(), str(w), str(TOUCH_BANNED[w]), str(s).substr(0, 36)])
	print("  [分母] TOUCH_ONLY: 扫了 %d 个 json / %d 条玩家可见字符串" % [files.size(), n_str])
	_ok("★分母>0(扫不到字符串 ⇒ 下一条是空检查)", files.size() > 0 and n_str > 100, "n=%d" % n_str)
	_ok("★★TOUCH_ONLY: 玩家可见文案里 0 个 PC 专属操作词", hits.is_empty(),
		" / ".join(hits) if not hits.is_empty() else "")


## res://data 下所有 .json (不递归 —— 本仓 data 是平的)
func _json_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.get_extension() == "json":
			out.append(dir_path + "/" + fn)
		fn = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## 递归收字符串。★跳过 `_` 开头的键 —— 那是给开发者的注记(`_note`/`_schema`/`_anchors`),
##   玩家一个字都看不到。不跳的话这条判据会被自己的文档注释绊倒。
func _collect_strings(v, out: Array) -> void:
	if v is String:
		if str(v).length() > 0:
			out.append(str(v))
	elif v is Dictionary:
		for k in (v as Dictionary).keys():
			if str(k).begins_with("_"):
				continue
			_collect_strings((v as Dictionary)[k], out)
	elif v is Array:
		for e in (v as Array):
			_collect_strings(e, out)


# ══════════════════════════════════════════════════════════════════════════
#  ⑤ ★★★TUTORIAL_CLAIM —— 教学说的那句话是不是真的
# ══════════════════════════════════════════════════════════════════════════
## 由来 (2026-09-29 台账 ③): 五个教学门禁全绿, 而新手流程是断的。三条实例:
##   · team_select[2] 写「三只龟**已经帮你放好了**」, 而那三格是空的
##     (`_ready` 开头就 `GameState.clear_team()`, 全仓零处教学自动入队);
##   · 下一步让点「**确认出战**」, 而按钮上写的是「挑 3 只龟上阵」而且 disabled
##     ⇒ 玩家被留在一个点不动的按钮前, 教学随即结束;
##   · 三处写「点**右上角**『去背包』」, 而那颗按钮在顶部正中偏左。
##   五条判据(verify_tutorial / _anchors / _director / _highlight / verify_onboarding)
##   没有一条去问【这句话是不是真的】—— 它们问的是「锚点在不在」「节点存不存在」。
##
## ★★判据的形状 = **提取 + 必须解析掉**:
##   从文案里机器提取"声称", 每一条都要被某个核实器接走; **提取到而没人接 ⇒ FAIL**。
##   所以以后写「点右上角的『XXX』」, 要么屏上真有这颗按钮、真在右上半区、真点得动,
##   要么门禁当场红 —— 而不是像原来那样静默通过。
## ★分母两层: 扫到 N 条教学文案 / 其中 M 条是"声称当前状态"。M=0 就是空检查。

const CLAIM_SCENES := {
	"team_select": "res://scenes/TeamSelect.tscn",
	"shop": "res://scenes/Shop.tscn",
	"inventory": "res://scenes/Inventory.tscn",
}
## place/battle 的锚点要 3D 运行态才有(太重, 见 verify_tutorial_anchors 头注) ⇒ 这两套走源码证据。
## ★只认**赋给 .text 的字符串字面量**, 不是"源码里出现过这几个字" —— 注释里出现不算。
const CLAIM_SRC := {
	"place": ["res://scripts/scenes/battle/dual_lane_flow.gd",
		"res://scripts/scenes/RealtimeBattle3DScene.gd"],
	"settle": ["res://scripts/scenes/battle/battle_hud.gd"],
}
## 屏上找不到的按钮(要先点开一层才出现, 例如商店的「买下」在卡详情里) → 退到该屏自己的脚本找字面量。
const CLAIM_SCRIPT := {
	"team_select": "res://scripts/scenes/TeamSelectScene.gd",
	"shop": "res://scripts/scenes/ShopScene.gd",
	"inventory": "res://scripts/scenes/InventoryScene.gd",
}

const CJK_NUM := {"一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "1 ": 1, "2 ": 2, "3 ": 3}
const CLAIM_UNITS := ["只", "格", "条", "件", "级"]
## 方位词 → 期望方向。x/y: -1=左/上, 1=右/下, 0=这一轴不管。
## ★★阈值是**按剖面分两档定的**, 不是拍的(memory `fb-judge-must-fit-the-shape`:
##   宽一格造假 bug、窄一格放过真 bug):
##   · 「上面/下面/右侧/上方…」= 边侧词, 用**半区**。三分区会让几何上明明在上面的目标
##     (inventory 的 lanes 锚点中心 y=237/720)红, 而那不是错。
##   · 「右上角/左下角…」= **角落词**, 用**三分区**。半区放得过真 bug: 商店那颗
##     「装备买好了 → 去背包」中心 x=782(1280 宽) —— 只比屏幕中线右 11%, 玩家读到的是
##     "顶部正中偏左", 而真正的右上角坐着「买经验」和钱箱。台账 ② 报的就是这一条,
##     半区判据会把它判成通过。
const DIR_WORDS := {
	"右上角": Vector2(1, -1), "左上角": Vector2(-1, -1),
	"右下角": Vector2(1, 1), "左下角": Vector2(-1, 1),
	"左半场": Vector2(-1, 0), "右半场": Vector2(1, 0),
	"右侧": Vector2(1, 0), "右边": Vector2(1, 0), "右栏": Vector2(1, 0),
	"左侧": Vector2(-1, 0), "左边": Vector2(-1, 0), "左栏": Vector2(-1, 0),
	"上方": Vector2(0, -1), "顶部": Vector2(0, -1), "上面": Vector2(0, -1),
	"下方": Vector2(0, 1), "底部": Vector2(0, 1), "下面": Vector2(0, 1),
}
## 角落词 —— 比边侧词严一档(见 DIR_WORDS 头注)。
const DIR_CORNER := ["右上角", "左上角", "右下角", "左下角"]
## 「已经…好了 / 帮你… / 给了你…」= 声称一个**已完成的状态**。这一族就是台账 ② 那条 bug 的形状。
const PRESET_PAT := ["已经", "帮你", "给了你", "给你"]

## 【认领表】"key|步序|词" → 核实器名。提取到而这里没人认领 ⇒ FAIL。
const PRESET_CHECK := {}
const COUNT_CHECK := {
	"team_select|三只": "roster_is_3",
	"team_select|三格": "slots_is_3",
	## 2026-10-07 新文案是阿拉伯数字的指令句(「选择 3 只龟上阵」「购买 1 件装备」「升到 2 级」):
	##   指令里的数也是声称 —— 候选池真有 3 只 / 教学币真买得起 1 件 / 买一次经验真升到 2 级且能装备。
	"team_select|3 只": "roster_is_3",
	"shop|1 件": "one_item_affordable",
	"shop|2 级": "xp_buy_reaches_2",
	## v5(分镜 E1/E2/F3, 照云顶原句的完整句): 「1 级时全队还不能装备任何装备」「全队就能装备 2 件装备」「集齐 3 件同名同星」
	"shop|1 级": "lv1_cap_zero",
	"shop|2 件": "lv2_cap_two",
	## 10-21: 合成那一句(原背包 F3)挪到商店买下那一刻(E4b) —— 同一个核实器
	"shop|3 件": "merge_takes_3",
}
## 「点击X」里的 X 不是按钮名, 而是「一类东西」—— 由该步 highlight 锚点核实(锚点解析得出 = 屏上真有)。
## v5: 文案是完整句, X 取到第一个「，/。」为止, 按前缀认(「一件装备」「一只龟，…」「一个技能装备它」「刚买的【{item}】」)。
const CLICK_OBJECTS := ["一件装备", "一只龟", "一个技能", "刚买的"]
## 方位词既绑不到「按钮名」也绑不到 highlight 锚点时, 在这里指认它说的是屏上哪块。
const DIR_EXTRA := {
	"team_select|1|右侧": "detail_column",   # 「点龟头像时, 右侧会显示它的属性和技能」
}
## 【补登的声称】机器提取抓不到的句式 —— 数词+量词后面直接跟名词(「两条战线」)。
## ★手登的是"这句话在哪", **不是**"就算它通过": 它照样跑核实器, 而且句子改没了会红
##   (免得表里留一条早就不存在的登记, memory `fb-registered-todos-rot`)。
const EXTRA_CLAIM := {}
## 手势词 → 代码里必须存在的证据。★这是 ① 的另一半: 换成触屏说法之后,
##   得证明**触屏那条路真的实现了**, 否则只是把一句假话换成另一句假话。
const GESTURE_EVIDENCE := {
	"两指捏合": ["_pinch_dist", "_touch_pts"],
	"一根手指拖": ["InputEventScreenDrag", "_touch_pts.size() == 1"],
}

## 选龟屏的未确认阵容草稿(`TeamSelectScene.TEAM_DRAFT_PATH`)。
## ★★本测试要**真点三只龟**才验得了「点满之后钮点得动」, 而 `_on_pick_pet` 会顺手
##   `_save_team()` 落盘 ⇒ 下一次跑这个测试, `_load_team()` 把上次那三只读回来,
##   起手就是满的 ⇒ 分母a 假红。CLAUDE.md §2:「看到测试依赖另一个测试留下的文件就是这一类」。
## ⇒ 进来先存盘内容 + 清掉, 出去还原 —— 测试一个字节都不留在盘上。
const TEAM_DRAFT := "user://team_draft.json"

var _claim_n_text := 0
var _claim_n := 0
var _claim_unresolved: Array = []
var _draft_backup: String = ""
var _draft_existed: bool = false


func _test_tutorial_claims() -> void:
	var raw := FileAccess.get_file_as_string(STEPS_JSON)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		_ok("TUTORIAL_CLAIM: 读得到步骤", false)
		return

	# 教学态: 商店要 tutorial_active 才开店; 背包/图鉴要 season_leaders 才建阵容
	var lt: Array[String] = ["basic", "stone", "bamboo"]
	GameState.test_mode = true
	GameState.tutorial = true
	GameState.tutorial_active = true
	GameState.meta_deepsea_coins = 20
	GameState.season_level = 1
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	_draft_stash()

	var screens := {}
	for key in CLAIM_SCENES.keys():
		if key == "team_select":
			GameState.tutorial_stage = "match1_pick"
			GameState.season_leaders = []
			GameState.left_team = []
		else:
			GameState.tutorial_stage = str(key)
			GameState.season_leaders = lt.duplicate()
			GameState.left_team = lt.duplicate()
		GameState.dual_lineup = {}
		## v5 F1「点击刚买的【{item}】」: 进背包那一刻背包里是商店里买下、合成好的那一件(教程开局配置 + 正式合成)
		var bench_keep: Array = GameState.persistent_bench.duplicate(true)
		if key == "inventory":
			GameState.persistent_bench = [{"id": str(get_node("/root/TutorialDirector").TUT_MERGE_ITEM), "star": 2}]
		screens[key] = await _harvest(str(key))
		GameState.persistent_bench = bench_keep

	# ── 逐步逐句提取声称并解析 ──
	for key in (parsed as Dictionary).keys():
		if str(key).begins_with("_"):
			continue
		var steps = (parsed as Dictionary)[key]
		if not (steps is Array):
			continue
		for i in range((steps as Array).size()):
			var st = (steps as Array)[i]
			if not (st is Dictionary):
				continue
			var text := _plain(str((st as Dictionary).get("text", "")))
			var hl := str((st as Dictionary).get("highlight", ""))
			_claim_n_text += 1
			_check_step_claims(str(key), i, text, hl, screens.get(str(key), {}))

	print("  [分母] TUTORIAL_CLAIM: 扫到 %d 条教学文案 / 其中 %d 条声称当前状态" % [
		_claim_n_text, _claim_n])
	## 2026-10-19 摆位那两句(拖动龟 / 点击开始战斗)随摆位环节删掉: 11 → 9 条。
	_ok("★分母: 扫到教学文案(N=0 是空检查)", _claim_n_text >= 9, "N=%d" % _claim_n_text)
	_ok("★★分母: 提取出声称(M=0 就是空检查, 这条判据白写)", _claim_n >= 8, "M=%d" % _claim_n)
	_ok("★★★TUTORIAL_CLAIM: 每一条声称都被核实器接走了(接不走=没人验这句话是真的)",
		_claim_unresolved.is_empty(), " / ".join(_claim_unresolved))

	# ── ② 那条 bug 的正面判据: 三格起手是空的 ⇒ 文案不许说"已经放好了", 而且点满才活 ──
	_check_team_flow(screens.get("team_select", {}))
	# ── ① 的另一半: 换成触屏说法后, 触屏那条路真的实现了 ──
	_check_gestures(parsed as Dictionary)

	_draft_restore()
	GameState.tutorial_active = false
	GameState.tutorial = false
	GameState.tutorial_stage = ""
	GameState.season_leaders = []


## 草稿存盘 → 内存, 然后清掉(见 TEAM_DRAFT 头注)
func _draft_stash() -> void:
	_draft_existed = FileAccess.file_exists(TEAM_DRAFT)
	if _draft_existed:
		_draft_backup = FileAccess.get_file_as_string(TEAM_DRAFT)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEAM_DRAFT))


## 逐字节还原(没有过就删掉本测试写出来的那份)
func _draft_restore() -> void:
	if _draft_existed:
		var f := FileAccess.open(TEAM_DRAFT, FileAccess.WRITE)
		if f != null:
			f.store_string(_draft_backup)
			f.close()
	elif FileAccess.file_exists(TEAM_DRAFT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEAM_DRAFT))


## 一屏的实测数据: 控件文字+矩形+可点性 / 锚点 / 计数 / 指认得出的区块
func _harvest(key: String) -> Dictionary:
	var out := {"vp": Vector2.ZERO, "texts": [], "anchors": {}, "counts": {}, "blocks": {}}
	var scn = load(str(CLAIM_SCENES[key]))
	if scn == null:
		return out
	var inst = (scn as PackedScene).instantiate()
	add_child(inst)
	for _i in range(40):
		await get_tree().process_frame
	out["vp"] = get_viewport().get_visible_rect().size
	_walk_texts(inst, out["texts"], "A")
	if inst.has_method("_tutorial_anchor"):
		for nm in ["roster", "roster_pet", "skill_choices", "slots", "confirm", "offer", "shelf", "offer_card", "coins", "xp_button", "bag_button", "lanes", "backpack", "first_item", "first_leader", "finish_button", "formation_button"]:
			var r: Rect2 = inst.call("_tutorial_anchor", nm)
			if r.size != Vector2.ZERO:
				(out["anchors"] as Dictionary)[nm] = r
	if key == "team_select":
		(out["counts"] as Dictionary)["roster"] = (int(inst._grid_flow.get_child_count())
			if inst._grid_flow != null else -1)
		(out["counts"] as Dictionary)["slots"] = int((inst._slot_nodes as Array).size())
		var ur := Rect2()
		for nd in [inst._dt_name, inst._dt_stats, inst._dt_passive]:
			if nd is Control and is_instance_valid(nd):
				var gr: Rect2 = (nd as Control).get_global_rect()
				if gr.size.x > 0.0 and gr.size.y > 0.0:
					ur = gr if ur.size == Vector2.ZERO else ur.merge(gr)
		(out["blocks"] as Dictionary)["detail_column"] = ur
		## 起手态(一只都没点)的确认钮 —— 台账 ② 那条 bug 就在这一刻
		out["confirm_empty_text"] = str(inst._start_btn.text)
		out["confirm_empty_disabled"] = bool(inst._start_btn.disabled)
		## 再按【第 1 步说的那样】把三只都点上; 第 4 步的声称("三只齐了")以此为前提
		var td = get_node_or_null("/root/TutorialDirector")
		var fixed: Array = (td.FIXED_TEAM as Array) if td != null else ["basic", "stone", "bamboo"]
		for pid in fixed:
			inst._on_pick_pet(str(pid))
		for _i2 in range(4):
			await get_tree().process_frame
		_walk_texts(inst, out["texts"], "B")
		out["confirm_full_text"] = str(inst._start_btn.text)
		out["confirm_full_disabled"] = bool(inst._start_btn.disabled)
		out["placed"] = int(_placed_count(inst))
	if key == "shop":
		(out["blocks"] as Dictionary)["coins"] = _num_in_anchor(out, "coins")
	if key == "inventory":
		var lanes := 0
		for t in (out["texts"] as Array):
			if str(t["raw"]).contains("战场"):
				lanes += 1
		(out["counts"] as Dictionary)["lanes"] = lanes
	inst.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return out


func _placed_count(inst) -> int:
	var n := 0
	for t in (inst.team as Array):
		if t != null and not inst._is_special_mark(t):
			n += 1
	return n


func _walk_texts(root_n: Node, out: Array, tag: String) -> void:
	var st: Array = [root_n]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			var c := n as Control
			var txt := ""
			var is_btn := false
			var dis := false
			if c is Button:
				txt = str((c as Button).text)
				is_btn = true
				dis = bool((c as Button).disabled)
			elif c is Label:
				txt = str((c as Label).text)
			if txt.strip_edges() != "":
				out.append({"raw": txt, "norm": _norm(txt), "rect": c.get_global_rect(),
					"btn": is_btn, "disabled": dis, "tag": tag})
		for ch in n.get_children():
			st.append(ch)


## 锚点矩形里那个数字读数(商店的深海币就画在 coins 锚点里)
func _num_in_anchor(screen: Dictionary, anchor: String) -> int:
	var a: Rect2 = (screen["anchors"] as Dictionary).get(anchor, Rect2())
	if a.size == Vector2.ZERO:
		return -1
	var best := -1
	for t in (screen["texts"] as Array):
		var r: Rect2 = t["rect"]
		if a.encloses(r) or a.intersection(r).size.x > r.size.x * 0.5:
			var s := str(t["raw"]).strip_edges()
			if s.is_valid_int():
				best = maxi(best, int(s))
	return best


## 去掉 <b>/</b> —— 玩家看到的就是这一串
func _plain(s: String) -> String:
	return s.replace("<b>", "").replace("</b>", "")


## 比对按钮名用的归一化: 去空白与装饰字符。
## ★为什么要它: 开打钮的真文字是「▶  开  打」(字间加空格做气势), 玩家读的是"开打";
##   「去背包」在屏上是「装备买好了 → 去背包」。判据要卡的是"这个词在不在这颗按钮上",
##   不是逐字节相等。
func _norm(s: String) -> String:
	var skip: Array = ["　", "·", "▶", "◀", "→", "←", "»", "«", "⚔", "🎒", "🐢", "🛠", "⬆", "⬇", "🔒"]
	var out := ""
	for i in s.length():
		var ch := s[i]
		if ch.unicode_at(0) <= 32:
			continue
		if ch in skip:
			continue
		out += ch
	return out


func _check_step_claims(key: String, idx: int, text: String, hl: String, screen: Dictionary) -> void:
	var tag := "%s[%d]" % [key, idx]
	# ── ① 按钮名声称: 「X」且前面 8 个字里有"点/按/戳" ⇒ 屏上真得有这颗按钮 ──
	var labels: Array = []          # [{name, pos}]
	var terms: Array = []
	var p := 0
	while true:
		var a := text.find("「", p)
		if a < 0:
			break
		var b := text.find("」", a + 1)
		if b < 0:
			break
		var nm := text.substr(a + 1, b - a - 1)
		var lead := text.substr(maxi(0, a - 8), mini(8, a))
		if lead.contains("点") or lead.contains("按") or lead.contains("戳"):
			labels.append({"name": nm, "pos": a})
		else:
			terms.append(nm)          # 「站位」这种是**术语引号**, 不是按钮名
		p = b + 1
	## 2026-10-07 新文案: 「点击X」不带引号, X 直接就是按钮名(或一类东西, 见 CLICK_OBJECTS)
	## v5(照云顶原句): 「点击」可以在句中(「教程完成。点击【完成教程】，…」「再点击一只龟，…」), X 到第一个「，/。」为止;
	##   X 是「【名字】」⇒ 按钮名; 是一类东西 ⇒ 由 highlight 锚点核实。每一处「点击」都要被接走。
	var cp := text.find("点击")
	while cp >= 0:
		var rest := text.substr(cp + 2)
		var cut := rest.length()
		for sep in ["，", "。"]:
			var k := rest.find(sep)
			if k >= 0 and k < cut:
				cut = k
		var nm2 := rest.substr(0, cut).strip_edges()
		var obj := false
		for co in CLICK_OBJECTS:
			if nm2.begins_with(str(co)):
				obj = true
		if obj:
			_claim_n += 1
			var ar2: Rect2 = (screen.get("anchors", {}) as Dictionary).get(hl, Rect2())
			_ok("%s 「点击%s」⇒ 高亮锚点 %s 在屏上解析得出" % [tag, nm2, hl], ar2.size != Vector2.ZERO or CLAIM_SRC.has(key),
				str(ar2))
		elif nm2.begins_with("【") and nm2.ends_with("】"):
			labels.append({"name": nm2.substr(1, nm2.length() - 2), "pos": cp})
		else:
			labels.append({"name": nm2, "pos": cp})
		cp = text.find("点击", cp + 2)
	for L in labels:
		_claim_n += 1
		var found := _find_label(key, str(L["name"]), screen)
		if found.is_empty():
			_ok("%s 声称的按钮「%s」找得到" % [tag, str(L["name"])], false,
				"屏上与该屏脚本里都没有叫这个名字的控件")
		else:
			_ok("%s 声称的按钮「%s」真的有 (%s)" % [tag, str(L["name"]), str(found["how"])], true,
				"实为「%s」" % str(found.get("raw", "")))
			if bool(found.get("live", false)):
				_ok("%s 让玩家点「%s」, 它真的点得动(台账 ②「点了没反应」)" % [tag, str(L["name"])],
					not bool(found.get("disabled", false)))
	if not terms.is_empty():
		print("  [记] %s 里 %d 处是术语引号(不当按钮名): %s" % [tag, terms.size(), str(terms)])

	# ── ② 方位声称 ──
	for w in DIR_WORDS.keys():
		var wp := text.find(str(w))
		if wp < 0:
			continue
		_claim_n += 1
		var want: Vector2 = DIR_WORDS[w]
		var target := ""
		var rect := Rect2()
		# 绑定顺序: 这句话后面第一颗按钮名 → 本步的 highlight 锚点 → 认领表 → 源码里的锚点公式
		for L2 in labels:
			if int(L2["pos"]) > wp:
				var f := _find_label(key, str(L2["name"]), screen)
				if not f.is_empty() and bool(f.get("live", false)):
					target = "按钮「%s」" % str(L2["name"])
					rect = f["rect"]
				break
		if rect.size == Vector2.ZERO and hl != "":
			var ar: Rect2 = (screen.get("anchors", {}) as Dictionary).get(hl, Rect2())
			if ar.size != Vector2.ZERO:
				target = "锚点 %s" % hl
				rect = ar
		if rect.size == Vector2.ZERO:
			var ek := "%s|%d|%s" % [key, idx, str(w)]
			if DIR_EXTRA.has(ek):
				var bn := str(DIR_EXTRA[ek])
				var br: Rect2 = (screen.get("blocks", {}) as Dictionary).get(bn, Rect2())
				if br.size != Vector2.ZERO:
					target = "区块 %s" % bn
					rect = br
		if rect.size == Vector2.ZERO:
			# place/battle 是源码层: 方位靠**锚点公式自己的数**(不是关键字), 见 _src_dir_ok
			if CLAIM_SRC.has(key):
				var srcok := _src_dir_ok(hl, want)
				if srcok != "":
					_ok("%s 方位「%s」对得上 (%s)" % [tag, str(w), srcok], true)
					continue
			_claim_unresolved.append(("%s 的方位词「%s」找不到它指的是哪一块 —— 要么在文案里点名那颗按钮, "
				+ "要么给这一步配 highlight 锚点, 要么登进 DIR_EXTRA") % [tag, str(w)])
			continue
		var vp: Vector2 = screen.get("vp", Vector2(1280, 720))
		var c := rect.get_center()
		var frac: float = (1.0 / 3.0) if (str(w) in DIR_CORNER) else 0.5
		var okx: bool = want.x == 0.0 or ((c.x > vp.x * (1.0 - frac)) if want.x > 0.0
			else (c.x < vp.x * frac))
		var oky: bool = want.y == 0.0 or ((c.y > vp.y * (1.0 - frac)) if want.y > 0.0
			else (c.y < vp.y * frac))
		_ok("%s 说在「%s」, %s 中心 (%.0f,%.0f) 真在那一块(阈值 %.2f 屏)" % [
			tag, str(w), target, c.x, c.y, frac], okx and oky, "视口 %s" % str(vp))

	# ── ③ 数量声称: 数词+量词, 且句式在**陈述现状**(给你三只 / 这三格是 / 三只齐了) ──
	for nw in CJK_NUM.keys():
		for u in CLAIM_UNITS:
			var phrase := str(nw) + str(u)
			var pp := text.find(phrase)
			if pp < 0:
				continue
			var lead2 := text.substr(maxi(0, pp - 4), mini(4, pp))
			var tail := text.substr(pp + phrase.length(), 1)
			var is_claim: bool = lead2.contains("给你") or lead2.contains("给了你") \
				or lead2.contains("有") or lead2.contains("这") \
				or tail in ["是", "都", "齐", "在"] or str(nw).strip_edges().is_valid_int()
			if not is_claim:
				continue
			_claim_n += 1
			var ck := "%s|%s" % [key, phrase]
			if not COUNT_CHECK.has(ck):
				_claim_unresolved.append("%s 声称「%s」, 而 COUNT_CHECK 里没人核实这个数" % [tag, phrase])
				continue
			_run_counter(tag, phrase, str(COUNT_CHECK[ck]), screen)

	# ── ④ 「已经…好了 / 帮你… / 给了你…」: 声称一个**已完成的状态** ──
	for pw in PRESET_PAT:
		if not text.contains(str(pw)):
			continue
		_claim_n += 1
		var pk := "%s|%d|%s" % [key, idx, str(pw)]
		if not PRESET_CHECK.has(pk):
			_claim_unresolved.append(("%s 用「%s」声称了一个已完成的状态, 而没有任何断言核实它 —— "
				+ "台账 ② 就是这么断的(「三只龟已经帮你放好了」而那三格是空的)。"
				+ "要么改成让玩家自己做的说法, 要么把那个状态真做出来并登进 PRESET_CHECK") % [tag, str(pw)])
			continue
		_run_counter(tag, str(pw), str(PRESET_CHECK[pk]), screen)

	# ── ⑤ 补登的声称 ──
	for xk in EXTRA_CLAIM.keys():
		var parts := str(xk).split("|")
		if parts.size() != 3 or str(parts[0]) != key or int(str(parts[1])) != idx:
			continue
		var needle := str(parts[2])
		if not text.contains(needle):
			_claim_unresolved.append("EXTRA_CLAIM 登记了 %s 的「%s」, 而这句话已经不在文案里了(登记烂了)" % [tag, needle])
			continue
		_claim_n += 1
		_run_counter(tag, needle, str(EXTRA_CLAIM[xk]), screen)


## 核实器: 拿**实测**的屏上数据去核对那句话
func _run_counter(tag: String, phrase: String, checker: String, screen: Dictionary) -> void:
	match checker:
		"roster_is_3":
			var got: int = int((screen.get("counts", {}) as Dictionary).get("roster", -1))
			_ok("%s 「%s」 ⇒ 候选池真的有 3 只" % [tag, phrase], got == 3, "实测 %d 只" % got)
		"slots_is_3":
			var got2: int = int((screen.get("counts", {}) as Dictionary).get("slots", -1))
			_ok("%s 「%s」 ⇒ 阵容槽真的是 3 格" % [tag, phrase], got2 == 3, "实测 %d 格" % got2)
		"lanes_is_2":
			var got3: int = int((screen.get("counts", {}) as Dictionary).get("lanes", -1))
			_ok("%s 「%s」 ⇒ 屏上真有 2 条战线" % [tag, phrase], got3 == 2, "实测 %d" % got3)
		"one_item_affordable":
			var td2 = get_node_or_null("/root/TutorialDirector")
			var P2c = load("res://scripts/gamedata/phase2_config.gd")
			var left: int = int(td2.TUT_COINS) - int(P2c.BUY_XP_COST)
			var cheapest := 999
			for e in DataRegistry.phase2_equipment:
				cheapest = mini(cheapest, maxi(1, int((e as Dictionary).get("cost", 1))))
			_ok("%s 「%s」 ⇒ 教学币买完经验还买得起 1 件(剩 %d, 最便宜 %d)" % [tag, phrase, left, cheapest], left >= cheapest)
		"lv1_cap_zero":
			var P2e = load("res://scripts/gamedata/phase2_config.gd")
			_ok("%s 「%s」 ⇒ 1 级全队可装备数真的是 0" % [tag, phrase], int(P2e.team_equip_cap(1)) == 0, "cap(1)=%d" % int(P2e.team_equip_cap(1)))
		"lv2_cap_two":
			var P2f = load("res://scripts/gamedata/phase2_config.gd")
			_ok("%s 「%s」 ⇒ 2 级全队可装备数真的是 2" % [tag, phrase], int(P2f.team_equip_cap(2)) == 2, "cap(2)=%d" % int(P2f.team_equip_cap(2)))
		"merge_takes_3":
			## 真跑正式合成函数: 2 件不合、3 件合成 1 件 2 星(用完还原背包)
			var keep_b: Array = GameState.persistent_bench.duplicate(true)
			var keep_e = GameState.persistent_equipped.duplicate(true)
			var keep_d = GameState.dual_lineup.duplicate(true)
			var td4 = get_node_or_null("/root/TutorialDirector")
			var mid: String = str(td4.TUT_MERGE_ITEM)
			GameState.persistent_equipped = {}
			GameState.dual_lineup = {}
			GameState.persistent_bench = [{"id": mid, "star": 1}, {"id": mid, "star": 1}]
			GameState.auto_merge_all()
			var two_stay: bool = GameState.persistent_bench.size() == 2
			GameState.persistent_bench.append({"id": mid, "star": 1})
			GameState.auto_merge_all()
			var merged: bool = GameState.persistent_bench.size() == 1 and int((GameState.persistent_bench[0] as Dictionary).get("star", 1)) == 2
			GameState.persistent_bench = keep_b
			GameState.persistent_equipped = keep_e
			GameState.dual_lineup = keep_d
			_ok("%s 「%s」 ⇒ 2 件不合、凑满 3 件同名同星真的合成 1 件 2 星(正式 auto_merge_all)" % [tag, phrase], two_stay and merged,
				"2 件留 %s / 3 件合 %s" % [str(two_stay), str(merged)])
		"xp_buy_reaches_2":
			var td3 = get_node_or_null("/root/TutorialDirector")
			var P2d = load("res://scripts/gamedata/phase2_config.gd")
			var ok_lv: bool = int(td3.TUT_COINS) >= int(P2d.BUY_XP_COST) and int(P2d.BUY_XP_AMOUNT) >= int(P2d.xp_to_next(1))
			_ok("%s 「%s」 ⇒ 1 级买一次经验真的升到 2 级, 而且 2 级能装备(X1)" % [tag, phrase],
				ok_lv and int(P2d.team_equip_cap(2)) > 0 and int(P2d.team_equip_cap(1)) == 0,
				"cap(1)=%d cap(2)=%d" % [int(P2d.team_equip_cap(1)), int(P2d.team_equip_cap(2))])
		"coins_on_screen":
			var coin: int = int((screen.get("blocks", {}) as Dictionary).get("coins", -1))
			_ok("%s 「%s」 ⇒ 屏上那个币数真的 > 0" % [tag, phrase], coin > 0, "实测读数 %d" % coin)
		_:
			_claim_unresolved.append("%s 的核实器 '%s' 没实现" % [tag, checker])


## 屏上/脚本里找这个按钮名。返回 {} = 没找到
func _find_label(key: String, nm: String, screen: Dictionary) -> Dictionary:
	var want := _norm(nm)
	var best := {}
	## ★先找**名字恰好相等**的按钮: 「背包」在商店里既是顶栏那颗「🎒 背包」, 也是底栏「背包 0 件」——
	##   取第一个「包含」会拿底栏那颗冒充, 通过了但理由是错的。
	for t in (screen.get("texts", []) as Array):
		if bool(t["btn"]) and str(t["norm"]) == want:
			return {"how": "屏上按钮(同名)", "live": true, "rect": t["rect"],
				"disabled": bool(t["disabled"]), "raw": str(t["raw"])}
	for t in (screen.get("texts", []) as Array):
		if str(t["norm"]).contains(want):
			# 按钮优先(文案说的是"点"), 同名 Label 只当兜底
			if bool(t["btn"]):
				return {"how": "屏上按钮", "live": true, "rect": t["rect"],
					"disabled": bool(t["disabled"]), "raw": str(t["raw"])}
			if best.is_empty():
				best = {"how": "屏上文字", "live": true, "rect": t["rect"],
					"disabled": false, "raw": str(t["raw"])}
	if not best.is_empty():
		return best
	# 退一步: 该屏脚本里赋给 .text 的字面量(要先点开一层才出现的按钮, 例如商店卡详情里的「买下」)
	var srcs: Array = []
	if CLAIM_SCRIPT.has(key):
		srcs.append(str(CLAIM_SCRIPT[key]))
	if CLAIM_SRC.has(key):
		srcs.append_array(CLAIM_SRC[key] as Array)
	for s in srcs:
		var lit := _text_literal_with(str(s), want)
		if lit != "":
			return {"how": "源码 .text 字面量", "live": false, "rect": Rect2(), "raw": lit}
		## 按钮字抽成常量的(结算「前往商店」= battle_hud.SHOP_BTN_TEXT): 认 `*BTN_TEXT := "…"`
		var src2 := FileAccess.get_file_as_string(str(s))
		var re := RegEx.new()
		re.compile("const ([A-Z_]*BTN_TEXT) := \"([^\"]*)\"")
		for m in re.search_all(src2):
			if _norm(m.get_string(2)) == want:
				return {"how": "源码按钮字常量 %s" % m.get_string(1), "live": false, "rect": Rect2(), "raw": m.get_string(2)}
	return {}


## 源码里所有 `xxx.text = "…"` 的字面量, 归一化后含 want 就返回「赋值目标 → 字面量」。
## ★不用 `src.contains(want)` —— 那样注释里提到这个词也算, 而注释不是屏幕。
## ★★优先**名字像按钮**的赋值目标: 「开打」在 dual_lane_flow 里既出现在标题 Label
##   (`title.text = "【%s战场】 马上开打"`)也出现在真按钮(`_dl_go_btn.text = "▶  开  打"`)上。
##   取第一个命中会拿标题冒充按钮 —— 通过了, 但通过的理由是错的, 而文案说的是"点"。
func _text_literal_with(path: String, want: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	if src == "":
		return ""
	var fallback := ""
	var p := 0
	while true:
		var i := src.find(".text", p)
		if i < 0:
			break
		p = i + 5
		var j := p
		while j < src.length() and (src[j] == " " or src[j] == "=" or src[j] == "+"):
			j += 1
		if j >= src.length() or src[j] != '"':
			continue
		var k := src.find('"', j + 1)
		if k < 0:
			continue
		var lit := src.substr(j + 1, k - j - 1)
		if not _norm(lit).contains(want):
			continue
		var ls := i
		while ls > 0:
			var pc := src[ls - 1]
			if pc.unicode_at(0) <= 32 or pc == "(" or pc == ",":
				break
			ls -= 1
		var shown := "%s.text = 「%s」" % [src.substr(ls, i - ls), lit]
		if shown.to_lower().contains("btn") or shown.to_lower().contains("button"):
			return shown
		if fallback == "":
			fallback = shown
	return fallback


## place 的方位: 锚点是**公式**不是控件 ⇒ 读那条公式自己的四个数, 不是查关键字。
## 形如  "field": … return Rect2(vp.x * 0.05, vp.y * 0.30, vp.x * 0.45, vp.y * 0.42)
## 返回 "" = 核实不了(调用方会把这条声称记成"没人接")。
func _src_dir_ok(hl: String, want: Vector2) -> String:
	if hl == "":
		return ""
	var src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	if src == "":
		return ""
	var a := src.find('"' + hl + '"')
	if a < 0:
		return ""
	var b := src.find("Rect2(", a)
	if b < 0 or b - a > 400:
		return ""
	var c := src.find(")", b)
	if c < 0:
		return ""
	var args := src.substr(b + 6, c - b - 6).split(",")
	if args.size() != 4:
		return ""
	var f: Array = []
	for s in args:
		var t := str(s)
		var star := t.find("*")
		f.append((t.substr(star + 1) if star >= 0 else t).strip_edges().to_float())
	var cx: float = float(f[0]) + float(f[2]) * 0.5
	var cy: float = float(f[1]) + float(f[3]) * 0.5
	var okx: bool = want.x == 0.0 or (cx - 0.5) * want.x > 0.0
	var oky: bool = want.y == 0.0 or (cy - 0.5) * want.y > 0.0
	if okx and oky:
		return "锚点 %s 的公式中心在视口比例 (%.2f,%.2f)" % [hl, cx, cy]
	return ""


## 台账 ② 的正面判据。三条一起才说明"流程接得上":
##   a) 起手三格是**空的** —— 所以文案不许声称"已经帮你放好了"(那一族由 PRESET 认领表堵着);
##   b) 起手确认钮 disabled —— 所以第 4 步的"三只齐了"是个**前提**, 不是现状;
##   c) 按第 1 步说的把三只都点上 ⇒ 钮变成文案写的那个名字 **且点得动**。
## ★a) 同时是分母: 哪天教学真的预置了三只, a) 会红 —— 那时该改的是文案与认领表, 不是偷偷放过。
func _check_team_flow(screen: Dictionary) -> void:
	if screen.is_empty():
		_ok("TUTORIAL_CLAIM: 采到选龟屏", false)
		return
	print("  [实测] 选龟屏起手: 确认钮「%s」disabled=%s / 点满三只后「%s」disabled=%s (placed=%d)" % [
		str(screen.get("confirm_empty_text", "")), str(screen.get("confirm_empty_disabled", "")),
		str(screen.get("confirm_full_text", "")), str(screen.get("confirm_full_disabled", "")),
		int(screen.get("placed", -1))])
	## ★红了不代表"又坏了": 也可能是有人真给教学预置了阵容 —— 那时该改的是文案与 PRESET 认领表。
	_ok("★分母a: 教学起手三格是空的(全仓零处自动入队) ⇒ 文案只能让玩家自己点",
		bool(screen.get("confirm_empty_disabled", false)),
		"起手钮「%s」disabled=%s" % [str(screen.get("confirm_empty_text", "")),
			str(screen.get("confirm_empty_disabled", ""))])
	_ok("★分母b: 按第 1 步说的点满三只之后真的放进去了", int(screen.get("placed", -1)) == 3,
		"placed=%d" % int(screen.get("placed", -1)))
	_ok("★★点满三只之后确认钮点得动(台账 ②「点了没反应」)",
		not bool(screen.get("confirm_full_disabled", true)))
	## 第 1 步的完成信号: 文案说"三只都点上", 那满的那一刻它得**自己翻页**
	var raw := FileAccess.get_file_as_string(STEPS_JSON)
	var pj = JSON.parse_string(raw)
	var adv := ""
	if pj is Dictionary and (pj as Dictionary).has("team_select"):
		var arr = (pj as Dictionary)["team_select"]
		if arr is Array and (arr as Array).size() > 0 and (arr as Array)[0] is Dictionary:
			adv = str(((arr as Array)[0] as Dictionary).get("advanceOn", ""))
	## v5(2026-10-21 分镜 B1): 选龟回来了, 第 1 步「先选择【{pet}】」⇒ 每上阵一只就是完成信号(pet_picked)。
	var has_ts: bool = pj is Dictionary and (pj as Dictionary).has("team_select")
	_ok("★team_select[0]「先选择【{pet}】」挂了完成信号 pet_picked", has_ts and adv == "pet_picked",
		"has_team_select=%s advanceOn=%s" % [str(has_ts), adv])
	var ts_src := _code_only(FileAccess.get_file_as_string("res://scripts/scenes/TeamSelectScene.gd"))
	_ok("★选龟屏真的发这个信号(不然 advanceOn 永远等不到)",
		ts_src.contains('_tut_notify("pet_picked")'))


## ① 的另一半: 文案换成触屏说法之后, 触屏那条路真的实现了
func _check_gestures(parsed: Dictionary) -> void:
	var all := ""
	for key in parsed.keys():
		if str(key).begins_with("_"):
			continue
		var steps = parsed[key]
		if not (steps is Array):
			continue
		for st in (steps as Array):
			if st is Dictionary:
				all += _plain(str((st as Dictionary).get("text", ""))) + " "
	var bsrc := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd") \
		+ FileAccess.get_file_as_string("res://scripts/scenes/battle/dual_lane_flow.gd")
	var seen := 0
	for g in GESTURE_EVIDENCE.keys():
		if not all.contains(str(g)):
			continue
		seen += 1
		var miss: Array = []
		for needle in (GESTURE_EVIDENCE[g] as Array):
			if not bsrc.contains(str(needle)):
				miss.append(str(needle))
		_ok("★教学说的手势「%s」代码里真的实现了" % str(g), miss.is_empty(), "缺: %s" % str(miss))
	print("  [分母] 教学文案里出现的手势词 %d 个" % seen)
	## ★2026-10-19 唯一的手势句「拖动龟调整站位」随摆位环节删掉 ⇒ 现在教学文案里 seen = 0 是真实情况。
	##   为了不让这一节变成空检查: 表里每个手势词的证据都要在代码里找得到(文案以后再用到它时, 它是真的)。
	var ev_ok := 0
	for g2 in GESTURE_EVIDENCE.keys():
		var all_in := true
		for needle2 in (GESTURE_EVIDENCE[g2] as Array):
			if not bsrc.contains(str(needle2)):
				all_in = false
		if all_in:
			ev_ok += 1
	_ok("★分母: 手势表 %d 个词的证据都在代码里(文案用到时不是假话)" % GESTURE_EVIDENCE.size(),
		GESTURE_EVIDENCE.size() > 0 and ev_ok == GESTURE_EVIDENCE.size(), "%d / %d" % [ev_ok, GESTURE_EVIDENCE.size()])


# ══════════════════════════════════════════════════════════════════════════
#  ⑤ ★★GUIDE_HOST —— 教学第一把: 开场演出完直接开打, 中间不挂引导、不卡住
# ══════════════════════════════════════════════════════════════════════════
## 由来: 原来这一节量「教站位」那两步(拖动龟 → 点击开始战斗)真的出场并挡对东西(2026-09-29 台账 ⑧)。
## ★2026-10-19 用户「我想在背包里实现站位修改，这样在对局内将不再有拖动站位环节」⇒ 摆位屏整个删掉,
##   教学第一把也没有那两步了。风险变成另一个形状: **教程会不会卡死在一个已经不存在的步骤上**
##   (例如导演还给战斗挂 place 引导、而那两步的锚点 / 完成事件都没了)。
## ⇒ 本节走真路径(教学沙盒 + 真战斗场), 量产品自己的账:
##   · 导演对战斗这一屏给的引导是空(`steps_key_for("battle") == ""`)
##   · 真战斗场自己从演出走到 fight(没有任何人按任何东西), 期间一帧都不停在 place
##   · 场上一个教学浮层都没有(group `tut_overlay`)
func _test_guide_host() -> void:
	print("  ── ⑤ GUIDE_HOST: 教学第一把开场即开打, 不挂引导 ──")
	var gs = get_node_or_null("/root/GameState")
	var td = get_node_or_null("/root/TutorialDirector")
	_ok("★分母 GUIDE_HOST: GameState / TutorialDirector 两个 autoload 都在", gs != null and td != null)
	if gs == null or td == null:
		return
	var snap := {
		"test_mode": bool(gs.test_mode), "tutorial": bool(gs.tutorial),
		"tutorial_active": bool(gs.tutorial_active), "tutorial_stage": str(gs.tutorial_stage),
		"dual_active": bool(gs.dual_active),
		"dual_ghost": gs.dual_ghost, "season_leaders": gs.season_leaders.duplicate(),
		"left_team": Array(gs.left_team), "dual_lineup": gs.dual_lineup,
	}
	var no_present0: bool = DualLaneFlow.NO_PRESENT
	gs.test_mode = true             # 绝不写玩家存档
	gs.tutorial = true
	gs.tutorial_active = true
	gs.tutorial_stage = "match1"
	var lt: Array[String] = []
	for id in td.FIXED_TEAM:
		lt.append(str(id))
	gs.season_leaders = lt.duplicate()
	gs.left_team.assign(lt)
	gs.dual_lineup = {}
	gs.reset_dual_lane()
	td.arm_battle_sandbox()         # 真入口: 教学弱 ghost + dual_active
	DualLaneFlow.NO_PRESENT = true   # 跳掉 5+5 秒纯演出(本测试帧预算 500; 带演出的那条路由 verify_no_place_stage 逐步量)
	_ok("★分母 GUIDE_HOST: 教学沙盒真的武装了(stage=match1 + 弱 ghost + 双路)",
		td.is_active() and str(td.stage()) == "match1" and bool(gs.dual_active)
			and str(gs.dual_ghost.get("ghost_id", "")) == "tutorial_weak")
	## v3(2026-10-20): 战斗这一屏只给两句**不阻塞**提示(开打后才出、不挡点击), 不再是空。
	_ok("★GUIDE_HOST: 战斗这一屏导演只给不阻塞提示那一套(battle)", td.steps_key_for("battle") == "battle",
		"steps_key=%s" % td.steps_key_for("battle"))
	_ok("★分母 GUIDE_HOST: 结算那一句还在(只删了摆位)", td.steps_key_for("settle") == "settle")

	var s = load("res://scripts/scenes/RealtimeBattle3DScene.gd").new()
	s._deterministic = true
	add_child(s)
	var w := 0
	var place_f := 0
	var overlay_f := 0
	while w < 900 and str(s._dl_state) != "fight":
		await get_tree().process_frame
		w += 1
		if str(s._dl_state) == "place":
			place_f += 1
		if _blocking_overlays() > 0:
			overlay_f += 1
	_ok("★★GUIDE_HOST: 教学第一把自己开打了(等了 %d 帧)" % w,
		str(s._dl_state) == "fight", "_dl_state=%s" % str(s._dl_state))
	_ok("★★GUIDE_HOST: 一帧都没停在摆位(%d 帧)" % place_f, place_f == 0)
	for _k in range(30):
		await get_tree().process_frame
		if _blocking_overlays() > 0:
			overlay_f += 1
	_ok("★★GUIDE_HOST: 开打前后场上没有任何挡点击的教学浮层(%d 帧)" % overlay_f, overlay_f == 0)
	_ok("★GUIDE_HOST: 教学阶段没被推走(仍是 match1, 结算后才进商店)", str(td.stage()) == "match1")
	s.queue_free()
	await get_tree().process_frame
	_guide_host_restore(gs, snap, no_present0)


## 场上「挡点击」的教学浮层个数(v3 的战斗提示是不阻塞的, 不算; 暗幕 / 吃点击的控件才算)。
func _blocking_overlays() -> int:
	var n := 0
	for o in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(o) and o.has_method("is_blocking") and o.is_blocking():
			n += 1
	return n


## 还原本节改过的全局态 + static。★不还原会波及同进程后面的一切(本仓栽过 static 没还原那一类)。
func _guide_host_restore(gs, snap: Dictionary, no_present0: bool) -> void:
	DualLaneFlow.NO_PRESENT = no_present0
	gs.tutorial = bool(snap["tutorial"])
	gs.tutorial_active = bool(snap["tutorial_active"])
	gs.tutorial_stage = str(snap["tutorial_stage"])
	gs.dual_active = bool(snap["dual_active"])
	gs.dual_ghost = snap["dual_ghost"]
	gs.season_leaders = snap["season_leaders"]
	gs.left_team.assign(snap["left_team"])
	gs.dual_lineup = snap["dual_lineup"]
	gs.test_mode = bool(snap["test_mode"])
	_ok("★GUIDE_HOST 收尾: static `DualLaneFlow.NO_PRESENT` 还原了(不还原 = 污染同进程后面每一条)",
		DualLaneFlow.NO_PRESENT == no_present0, "现在=%s" % str(DualLaneFlow.NO_PRESENT))
