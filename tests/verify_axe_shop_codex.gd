extends Node
## verify_axe_shop_codex.gd — 096 在【商店卡片】与【图鉴详情】上**真的画出了什么** (2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么要有这一份
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01:「跟商店和图鉴有关的测试用例呢」。查下来: 仓库里 4 个 shop 测试
## + 6 个 codex 测试, **没有一个碰过 096**。
##
## 而 `verify_axe_evolution` 查的是 `ShopScene._deco()` **返回**了什么 —— 那是函数返回值,
## 不是屏幕。这与今天连着栽的两次**是同一个形状**:
##     素材在盘上   ≠ 引擎读得到
##     登记在表里   ≠ 真的播出来
##     _deco 返回对 ≠ 卡片真的画出来
## ⇒ 这份门禁**建真商店/真图鉴场景、真重绘**, 然后**遍历节点树**把屏幕上的
##   Label 文本与 TextureRect 贴图路径抓出来比。
##
## ★★它抓到的第一个真问题: **同一件装备在商店和图鉴里叫两个名字** ——
##   图鉴渲染 `eq["name"]`(json 里的「小木斧」), 而商店 `_deco` 在木斧档把它改成「木斧」。
##   玩家在图鉴里记住「小木斧」, 到商店找不到它。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const SkillText := preload("res://scripts/util/skill_text.gd")
const EquipIcon := preload("res://scripts/util/equip_icon.gd")
const CODEX_SCN := preload("res://scenes/Codex.tscn")
const EquipStatsRef := preload("res://scripts/gamedata/equip_stats.gd")
const EID := "p2eq_096"

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 把一棵节点树上所有 Label / RichTextLabel 的文字收集起来。
func _texts(n: Node, out: Array) -> Array:
	if n is Label:
		out.append(str((n as Label).text))
	elif n is RichTextLabel:
		out.append(str((n as RichTextLabel).text))
	elif n is Button:
		out.append(str((n as Button).text))
	for c in n.get_children():
		_texts(c, out)
	return out


## 把一棵节点树上所有 TextureRect 的贴图**像素内容指纹**收集起来。
##
## ★★为什么不比 `resource_path`(我第一版就是这么写的, 三条当场误报):
##   `EquipIcon.make` 走 `_trimmed()` —— 它把原图裁掉透明边后**新建一个 ImageTexture**,
##   而新建的纹理 `resource_path` 是**空串**。于是我抓到的全是金币图标 + 一个空,
##   看着像"图标根本没画", 其实画了、只是我的尺子量不到它。
##   (判据不合身 = 造假 bug, memory [[fb-judge-must-fit-the-shape]])
##   ⇒ 改成量**像素**: 拿期望的源图同样裁一遍, 比 PNG 字节。
func _texs(n: Node, out: Array) -> Array:
	if n is TextureRect and (n as TextureRect).texture != null:
		var im: Image = (n as TextureRect).texture.get_image()
		out.append(im.get_data().hex_encode() if im != null else "")
	for c in n.get_children():
		_texs(c, out)
	return out


## 期望图标的像素指纹(与屏幕上那张同样经过 EquipIcon._trimmed)。
func _want_fp(rel: String) -> String:
	var full := "res://assets/sprites/" + rel
	if not ResourceLoader.exists(full):
		return ""
	var t2: Texture2D = load(full)
	var tr: Texture2D = EquipIcon._trimmed(t2)
	var im: Image = tr.get_image() if tr != null else null
	return im.get_data().hex_encode() if im != null else ""


func _has(arr: Array, s: String) -> bool:
	for x in arr:
		if str(x).contains(s):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 096 在商店卡片 / 图鉴详情上真的画出了什么 ===")
	var bak := {"st": int(gs.axe_stage), "fin": str(gs.axe_final),
		"bench": gs.persistent_bench.duplicate(true)}

	await _t_shop(gs)
	await _t_panel(gs)
	await _t_codex(gs)
	await _t_icon_single_exit(gs)
	_t_desc_complete(gs)
	_t_name_consistency(gs)

	gs.axe_stage = int(bak["st"])
	gs.axe_final = str(bak["fin"])
	gs.persistent_bench = (bak["bench"] as Array).duplicate(true)

	if _n < 47:
		print("  [FAIL] ★分母: 断言只有 %d 条(<47) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 096 商店/图鉴渲染(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① 商店: 卡片与详情面板【真的画出】进化后的形态
# ══════════════════════════════════════════════════════════════
func _t_shop(gs) -> void:
	print("--- ① 商店真重绘 ---")
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)
	for _i in range(6):
		await get_tree().process_frame
	var raw: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	_ok("★分母: 商店场景起得来 + 拿得到 096 原件", shop != null and not raw.is_empty())

	for cs in [[0, ""], [4, ""], [4, "ember"]]:
		gs.axe_stage = int(cs[0])
		gs.axe_final = str(cs[1])
		shop._offer = [raw, null, null, null, null, null, null, null, null, null]
		shop._sel = 0
		shop._rebuild()
		for _i in range(3):
			await get_tree().process_frame
		var disp: Dictionary = AE.display(int(cs[0]), str(cs[1]))
		var want_name: String = str(disp["name"])
		var want_icon: String = AE.icon_path(int(cs[0]), str(cs[1])).get_file()
		var want_fp: String = _want_fp(AE.icon_path(int(cs[0]), str(cs[1])))
		var txts: Array = _texts(shop, [])
		var texs: Array = _texs(shop, [])
		_ok("★★档%d/最终「%s」: 屏幕上真的出现了名字「%s」"
			% [int(cs[0]), str(cs[1]), want_name], _has(txts, want_name),
			"分母: 抓到 %d 个文本节点" % txts.size())
		var hit := false
		for fp in texs:
			if str(fp) != "" and str(fp) == want_fp:
				hit = true
				break
		_ok("★★档%d/最终「%s」: 屏幕上真的用了图标 %s(比像素, 不比路径)"
			% [int(cs[0]), str(cs[1]), want_icon], hit and want_fp != "",
			"分母: 抓到 %d 张贴图 / 期望指纹 %d 字节" % [texs.size(), want_fp.length()])
	shop.queue_free()


# ══════════════════════════════════════════════════════════════
#  ② 图鉴: 096 详情渲染得出来、没有占位符残留、不显示星级
# ══════════════════════════════════════════════════════════════
func _t_codex(gs) -> void:
	print("--- ② 图鉴真重绘 ---")
	## ★用 **.tscn 实例化**, 不是 `CodexScene.gd.new()` ——
	##   图鉴的 UI 节点长在场景文件里, 只 new 脚本会拿到一堆 null,
	##   表现是 `Invalid assignment ... on a null instance` + 列表 0 条。
	##   现有的 verify_codex_browse 就是这么起的(照仓库的先例, 别自己发明)。
	var cx = CODEX_SCN.instantiate()
	add_child(cx)
	for _i in range(8):
		await get_tree().process_frame
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	## ★走**真入口**: 切到装备页 → 在列表里找到 096 → `_select(idx)`。
	##   我第一版直接调 `_show_detail(eq)`(猜的函数名), 结果 `null instance` 报错、
	##   整段中止 —— 而"分母断言"把它抓了出来(memory [[fb-verify-must-run-the-real-path]])。
	cx._switch_tab("equips")
	for _i in range(4):
		await get_tree().process_frame
	var idx := -1
	for i in range(cx._items.size()):
		if str((cx._items[i] as Dictionary).get("id", "")) == EID:
			idx = i
			break
	_ok("★分母: 装备页列表里找得到 096(找不到 = 它压根没进图鉴)", idx >= 0,
		"列表 %d 条" % cx._items.size())
	if idx >= 0:
		cx._select(idx)
	_ok("★分母: 图鉴详情入口调得到(走真 _select, 不是猜函数名)", idx >= 0)
	for _i in range(4):
		await get_tree().process_frame
	var txts: Array = _texts(cx, [])
	_ok("★分母: 图鉴屏幕上抓到 %d 个文本节点(0 就是空检查)" % txts.size(), txts.size() >= 3)
	_ok("★★图鉴上出现了它的名字「%s」" % str(eq.get("name", "?")),
		_has(txts, str(eq.get("name", "?"))))
	## ★占位符残留会直接把 `{C:AxeEvolution.XXX}` 显示给玩家看
	var leaked := ""
	for x in txts:
		if str(x).contains("{C:"):
			leaked = str(x).substr(maxi(0, str(x).find("{C:")), 50)
			break
	_ok("★★图鉴渲染后**没有** {C: 占位符残留", leaked == "", leaked)
	## ★096 不升星 ⇒ 属性行只该有【一档】数值, 不是 `+17/+29/+41` 那种三档串。
	##
	## ★★判据走过两次弯路, 两次都是**判据太宽在造假 bug**:
	##   ① 第一版数"有没有两个斜杠 + 生命/攻击" → 匹配到 **BBCode** 里的斜杠(`[b]…[/b]`)。
	##   ② 第二版用正则扫**整屏文本**找「数字/数字/数字」→ 匹配到效果文案里
	##      **合法的**「攒够 80/110/130/160」(那是进化阈值, 不是星级属性)。
	##   ⇒ 判据必须落在**属性行那一处**, 不是满屏乱扫。
	##      属性行的来源是 `EquipStats.stat_line_all_stars(eid)`(detail_views.gd 就是拿它渲的)。
	## ★GDScript 字符串里 `\d` 是**非法转义**(Parse Error), 要写 `\\d`。
	## ★三档串长这样: `+17/+29/+41` —— 斜杠后面还有个 `+`, 第一版漏了它, 于是
	##   058 那条**分母当场红**(它明明是三档却匹配不上)。分母就是干这个用的。
	var star_re := RegEx.create_from_string("\\d+\\s*/\\s*\\+?\\s*\\d+\\s*/\\s*\\+?\\s*\\d+")
	var line96: String = EquipStatsRef.stat_line_all_stars(EID)
	var line58: String = EquipStatsRef.stat_line_all_stars("p2eq_058")
	_ok("★★不升星的 096 属性行只有一档(实测「%s」)" % line96,
		star_re.search(line96) == null and line96 != "")
	## ★分母: 换成会升星的 058, 同一个函数**确实**给出三档串 —— 否则上一条是恒真式
	_ok("★★分母: 会升星的 058 属性行确实是三档(实测「%s」)" % line58,
		star_re.search(line58) != null)
	## 屏幕上真的画的就是这一行(渲染层可能自己又拼了一遍)
	var on_screen := false
	for x in txts:
		if str(x).contains("+10") and str(x).contains("+20"):
			on_screen = true
			break
	_ok("★图鉴屏幕上真的画出了这一档属性(+10 / +20)", on_screen,
		"分母: %d 个文本节点" % txts.size())
	cx.queue_free()


# ══════════════════════════════════════════════════════════════
#  ③ ★★名字一致性: 图鉴与商店在同一档位下必须叫同一个名字
# ══════════════════════════════════════════════════════════════
func _t_name_consistency(gs) -> void:
	print("--- ③ 名字一致性 ---")
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	var codex_name: String = str(eq.get("name", ""))
	var shop_name: String = str(AE.display(0, "")["name"])
	_ok("★★木斧档: 图鉴叫「%s」而商店叫「%s」—— 必须一致" % [codex_name, shop_name],
		codex_name == shop_name,
		"玩家在图鉴记住一个名字, 到商店找不到它")
	## 分母: 后面几档【本来就该】不一样(它们是进化形态)
	_ok("★分母: 进化后的档位与原名不同才对(石斧「%s」≠「%s」)"
		% [str(AE.display(1, "")["name"]), codex_name],
		str(AE.display(1, "")["name"]) != codex_name)


# ══════════════════════════════════════════════════════════════
#  ④ ★★玩家看得见进度条吗 / 选得到最终造物吗
# ══════════════════════════════════════════════════════════════
## 用户 2026-09-01:「用户难道就这么玩吗，则怎么选择最终造物呢，进度条呢」。
## 到 v0.19.311 为止, 机制全做完了、门禁也全绿, **但玩家一样都看不见** ——
## 经验在涨屏幕上没地方显示、`final_ready()` 变 true 却没有任何入口能选。
## ⇒ 这一节的判据全部落在【屏幕上有没有】和【点下去有没有用】, 不是"函数返回对不对"。
func _t_panel(gs) -> void:
	print("--- ④ 进度条 / 四选一 ---")
	var shop = load("res://scripts/scenes/ShopScene.gd").new()
	add_child(shop)
	for _i in range(6):
		await get_tree().process_frame
	var raw: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	var bak_bench: Array = gs.persistent_bench.duplicate(true)
	gs.persistent_bench = [{"id": EID, "star": 1}]      # 拥有一把 ⇒ 该看得见进度

	# ── 情形 A: 攒了一半, 只该看到进度条, 不该有四选一 ──
	gs.axe_stage = 0
	gs.axe_final = ""
	gs.axe_exp_bar = 40
	gs.axe_exp_total = 40
	shop._offer = [raw, null, null, null, null, null, null, null, null, null]
	shop._sel = 0
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	var txts: Array = _texts(shop, [])
	_ok("★★进度条真的画在屏幕上了(「砍伐经验 40/%d」)" % AE.need_for_next(0),
		_has(txts, "砍伐经验 40/%d" % AE.need_for_next(0)),
		"分母: 抓到 %d 个文本节点" % txts.size())
	_ok("★屏幕上写了当前形态与历史累计", _has(txts, "小木斧") and _has(txts, "累计 40"))
	## ★★没攒够时**点也点不动** —— 我第一版只验了"按钮不出现",
	##   而"按钮不出现"守不住"用别的路径调进来会不会生效"(反向验证当场证明:
	##   把 axe_pick_final 里的 final_ready 检查改成 if false, 一条都不红)。
	var before_fin: String = str(gs.axe_final)
	var got: bool = gs.axe_pick_final(str((AE.FINALS[0] as Dictionary)["key"]))
	_ok("★★没攒够(40/%d)时 axe_pick_final 直接拒绝, 最终造物没被写进去"
		% AE.need_for_next(0),
		not got and str(gs.axe_final) == before_fin,
		"返回 %s, axe_final=「%s」" % [str(got), str(gs.axe_final)])
	var btns_a: Array = _buttons(shop, [])
	_ok("★★没攒够时【不该】出现四选一按钮(分母: 屏幕上共 %d 个按钮)" % btns_a.size(),
		not _has(btns_a, "亡灵之斧") and not _has(btns_a, "余烬"), str(btns_a.slice(0, 6)))

	# ── 情形 B: 钻石斧攒满 400 ⇒ 四选一必须出现, 且点得动 ──
	gs.axe_stage = AE.STAGES.size() - 1
	gs.axe_final = ""
	gs.axe_exp_bar = AE.FINAL_NEED
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	var btns: Array = _buttons(shop, [])
	var missing: Array = []
	for f in AE.FINALS:
		if not _has(btns, str((f as Dictionary)["name"])):
			missing.append(str((f as Dictionary)["name"]))
	_ok("★★攒够 %d ⇒ 四个最终造物按钮全在屏幕上(分母: 共 %d 个按钮)"
		% [AE.FINAL_NEED, btns.size()], missing.is_empty(), str(missing))
	## ★★真按下去 —— 只验"按钮画出来了"守不住"按了没用"
	var target := ""
	var pressed := false
	for b in _button_nodes(shop, []):
		if str((b as Button).text) == str((AE.FINALS[2] as Dictionary)["name"]):
			target = str((AE.FINALS[2] as Dictionary)["key"])
			(b as Button).emit_signal("pressed")
			pressed = true
			break
	_ok("★分母: 真的找到了那个按钮并按了下去", pressed and target != "")
	for _i in range(3):
		await get_tree().process_frame
	_ok("★★按下去之后最终造物真的定了(axe_final == 「%s」)" % target,
		str(gs.axe_final) == target, "实测 %s" % str(gs.axe_final))
	_ok("★选完进度条清零, 但【历史累计不动】(未决点 ⑥)",
		int(gs.axe_exp_bar) == 0 and int(gs.axe_exp_total) == 40,
		"bar=%d tot=%d" % [int(gs.axe_exp_bar), int(gs.axe_exp_total)])
	## ★★选完本大轮锁定(未决点 ⑩)。判据必须摆在**只有这条闸挡得住**的场景里:
	##   第一版我选完就直接再点一次, 那时 `axe_exp_bar` 已经清零 ⇒ 是"没攒够"把它挡下的,
	##   反向验证当场证明(把 final_ready 里的 `final_key == ""` 删掉, 一条都不红)。
	##   ⇒ 把进度条**灌回 400** 再点, 这时只剩"已经选过"这一条理由能拒绝它。
	gs.axe_exp_bar = AE.FINAL_NEED
	var again: bool = gs.axe_pick_final(str((AE.FINALS[0] as Dictionary)["key"]))
	_ok("★★本大轮锁定: 就算再攒满 %d, 选过了也改不了" % AE.FINAL_NEED,
		not again and str(gs.axe_final) == target, "实测 %s" % str(gs.axe_final))
	## ★需求「选择最终造物后经验值封顶」—— 选完之后经验不许再涨
	gs.axe_exp_bar = 0
	var tot_before: int = int(gs.axe_exp_total)
	gs.axe_add_exp(AE.EXP_ON_MATCH)
	_ok("★★选完最终造物后【经验封顶】: 再打一场也不涨(%d → %d)"
		% [tot_before, int(gs.axe_exp_total)],
		int(gs.axe_exp_total) == tot_before and int(gs.axe_exp_bar) == 0)
	## ★分母: 没选最终造物时同样的调用**确实**会涨 —— 否则上一条是恒真式
	var bak_fin: String = str(gs.axe_final)
	gs.axe_final = ""
	gs.axe_add_exp(AE.EXP_ON_MATCH)
	_ok("★★分母: 没选最终造物时同一个调用确实会涨(%d → %d)"
		% [tot_before, int(gs.axe_exp_total)], int(gs.axe_exp_total) > tot_before)
	gs.axe_final = bak_fin
	## ★选完之后屏幕上该显示最终造物的名字, 四选一按钮消失
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	var btns2: Array = _buttons(shop, [])
	_ok("★选完之后四选一按钮消失(分母: 仍有 %d 个按钮)" % btns2.size(),
		not _has(btns2, str((AE.FINALS[0] as Dictionary)["name"])))
	# ── ★三条"玩家在哪看得到"的补充(用户 2026-09-01 逐条点名) ──
	## ①「应该是在羁绊里显示最好啊，这是跟着羁绊走的」⇒ 羁绊 chip 上要带进度
	gs.axe_final = ""
	gs.axe_stage = 0
	gs.axe_exp_bar = 35
	var bak_eq = gs.persistent_equipped.duplicate(true)
	var bak_ld = gs.season_leaders.duplicate(true)
	gs.season_leaders = ["basic"]
	gs.persistent_equipped = {"basic": [{"id": EID, "star": 1}]}   # 装上 ⇒ 羁绊激活
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	var t_syn: Array = _texts(shop, [])
	_ok("★★羁绊那一行上直接带砍伐进度(「斧头 … 小木斧 35/%d」)"
		% AE.need_for_next(0),
		_has(t_syn, "斧头") and _has(t_syn, "小木斧 35/%d" % AE.need_for_next(0)),
		"分母: 抓到 %d 个文本节点" % t_syn.size())
	## ② 什么都没选中时, 攒够 400 也要能选造物(错过就再也做不了最终进化)
	gs.axe_stage = AE.STAGES.size() - 1
	gs.axe_exp_bar = AE.FINAL_NEED
	gs.axe_final = ""
	shop._sel = -1
	shop._sel_own = ""
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	var b_nosel: Array = _buttons(shop, [])
	_ok("★★什么都没选中时, 攒够 %d 照样能看到四选一(分母: 共 %d 个按钮)"
		% [AE.FINAL_NEED, b_nosel.size()],
		_has(b_nosel, str((AE.FINALS[0] as Dictionary)["name"])), str(b_nosel.slice(0, 6)))
	## ③ 背包里那件也要显示【进化后】的形态(原来它不走 _deco)
	## ★★先把装备**摘下来** —— 否则羁绊 chip 上也写着「铁斧 10/130」,
	##   `_has(txts,"铁斧")` 会从那儿读到, 判据就穿帮了(反向验证当场证明: 把
	##   背包那处的 _deco 拆掉, 门禁一条都不红)。摘掉之后羁绊不激活、chip 消失,
	##   屏幕上"铁斧"这三个字**只可能**来自背包详情面板。
	gs.persistent_equipped = {"basic": []}
	gs.axe_final = ""
	gs.axe_stage = 2                                  # 铁斧
	gs.axe_exp_bar = 10
	shop._sel = -1
	shop._sel_own = EID
	shop._sel_own_star = 1
	shop._rebuild()
	for _i in range(3):
		await get_tree().process_frame
	## ★★判据落在**图标像素**上, 不落在"屏幕上有没有『铁斧』这三个字" ——
	##   我连试两版都穿帮: 第一版被羁绊 chip 读到、第二版被**我自己那块进度面板的标题**
	##   读到(它也写着「🪓 铁斧」)。反向验证两次都是"一条都没红"。
	##   而**图标只有详情面板画** ⇒ 屏幕上出现 axe-iron 的像素, 只可能是 `_deco` 生效了。
	var t_own_tex: Array = _texs(shop, [])
	var fp_iron: String = _want_fp("equip/axe-iron.png")
	var fp_wood: String = _want_fp("equip/axe-wood.png")
	var has_iron := false
	var has_wood := false
	for fp in t_own_tex:
		if str(fp) == fp_iron and fp_iron != "":
			has_iron = true
		if str(fp) == fp_wood and fp_wood != "":
			has_wood = true
	_ok("★★背包里选中它时画的是【铁斧图标】而不是木斧(原来不走 _deco)",
		has_iron and not has_wood,
		"铁斧=%s 木斧=%s · 分母: 抓到 %d 张贴图" % [str(has_iron), str(has_wood), t_own_tex.size()])
	shop._sel_own = ""
	gs.persistent_equipped = bak_eq
	gs.season_leaders = bak_ld
	gs.persistent_bench = bak_bench
	shop.queue_free()


func _buttons(n: Node, out: Array) -> Array:
	for b in _button_nodes(n, []):
		out.append(str((b as Button).text))
	return out


func _button_nodes(n: Node, out: Array) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_button_nodes(c, out)
	return out


# ══════════════════════════════════════════════════════════════
#  ⑤ ★★图标的【唯一出口】—— 换形态只许在 EquipIcon 里做
# ══════════════════════════════════════════════════════════════
## 用户 2026-09-01:「图标我在对局内和背包里看有问题啊」。
## 我原来把「随进化换形态」做成了 `ShopScene._deco()` —— **商店自己的私有方法**,
## 于是六处画图标的地方**只有商店那一屏是对的**:
##   背包 / 对局内龟身装备格 / 换路展示 / 图鉴详情 / 图鉴列表 —— 五处全画着小木斧。
## ★而 `equip_icon.gd` 的头注早就写着这条教训(「同一件事在 7 处各写了一遍」),
##   我却又抄了一份。⇒ 收口到 `EquipIcon.stage_img()`, 六处一起好。
## ★★这一节焊死的是**纪律**: 换形态只许在唯一出口做, 别处不许另抄一份。
func _t_icon_single_exit(gs) -> void:
	print("--- ⑤ 图标唯一出口 ---")
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	var bak_st: int = int(gs.axe_stage)
	var bak_fin: String = str(gs.axe_final)
	## 唯一出口随档位变(六种形态各不相同)
	var seen: Dictionary = {}
	for i in range(AE.STAGES.size()):
		gs.axe_stage = i
		gs.axe_final = ""
		seen[EquipIcon.stage_img(eq)] = true
	gs.axe_stage = AE.STAGES.size() - 1
	gs.axe_final = "ember"
	seen[EquipIcon.stage_img(eq)] = true
	_ok("★★EquipIcon.stage_img 六种形态给出**六张不同的图**(实测 %d 种)" % seen.size(),
		seen.size() == 6, str(seen.keys()))
	## ★分母: 别的装备不许被斧头逻辑污染
	gs.axe_stage = 3
	gs.axe_final = ""
	var other: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_058", {})
	_ok("★★分母: 别的装备(058)的图纹丝不动 —— 唯一出口不许把所有件都改了",
		EquipIcon.stage_img(other) == str(other.get("img", "")),
		"实测 %s" % EquipIcon.stage_img(other))
	## ★★纪律: 画图标的地方**不许自己另算一份**形态
	##   判据: 除了 EquipIcon 与 AxeEvolution 本身, 没有别的文件同时碰
	##   `EquipIcon.make` 和 `axe_stage` —— 碰了就是又抄了一份。
	var dirs: Array = ["res://scripts/scenes/InventoryScene.gd",
		"res://scripts/scenes/battle/info_panel.gd",
		"res://scripts/scenes/battle/dual_lane_flow.gd",
		"res://scripts/scenes/codex/detail_views.gd",
		"res://scripts/scenes/codex/list_builder.gd"]
	var copies: Array = []
	var scanned := 0
	for f in dirs:
		var s: String = FileAccess.get_file_as_string(f)
		if s == "":
			continue
		scanned += 1
		if s.contains("axe_stage") or s.contains("AxeEvolution"):
			copies.append(f.get_file())
	_ok("★★五个消费方都**不自己算形态**(分母: 扫了 %d 个文件)" % scanned,
		copies.is_empty() and scanned == 5, str(copies))
	## 真建背包场景, 从屏幕像素验它真的画了进化后的图
	gs.axe_stage = 2
	gs.axe_final = ""
	var bak_bench: Array = gs.persistent_bench.duplicate(true)
	gs.persistent_bench = [{"id": EID, "star": 1}]
	var inv = load("res://scripts/scenes/InventoryScene.gd").new()
	add_child(inv)
	for _i in range(8):
		await get_tree().process_frame
	var fps: Array = _texs(inv, [])
	var w_iron: String = _want_fp("equip/axe-iron.png")
	var w_wood: String = _want_fp("equip/axe-wood.png")
	var iron := false
	var wood := false
	for f in fps:
		if str(f) == w_iron and w_iron != "":
			iron = true
		if str(f) == w_wood and w_wood != "":
			wood = true
	_ok("★★★背包屏幕(档=铁斧)画的是**铁斧图**且不再画木斧(分母: 抓到 %d 张贴图)" % fps.size(),
		iron and not wood, "铁斧=%s 木斧=%s" % [str(iron), str(wood)])
	inv.queue_free()
	gs.persistent_bench = bak_bench
	gs.axe_stage = bak_st
	gs.axe_final = bak_fin


# ══════════════════════════════════════════════════════════════
#  ⑥ ★★描述【玩家读得到】—— 被动3~6 与四个最终造物
# ══════════════════════════════════════════════════════════════
## ★由来(2026-09-01 逐句核对原话): 商店与图鉴的描述**停在被动2** ——
##   被动3(强化砍)/4(竖劈)/5(横扫+效率)/6(蓄力猛砸) 与四个最终造物, 玩家在游戏里
##   **一个字都读不到**。而机制全都做了、64 条门禁全绿。
##   (用户此前已经为同一形状说过一次:「用户难道就这么玩吗，则怎么选择最终造物呢」)
## ★判据落在**渲染后的文本**上, 不落在 json 字段里 —— json 里写了但占位符没展开、
##   或者消费方压根不读这个字段, 都是"写了没人读"。
## ★完整性是硬指标、长度是软指标(memory [[fb-style-reference-not-length-target]]):
##   判据问的是"每一类机制在不在", 不是字数。
func _t_desc_complete(gs) -> void:
	print("--- ⑥ 描述完整性 ---")
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	## ★★图鉴看到的是【当前档位的全文 + 四个造物那一段】。
	##   商店/对局内只给 desc1(按档位生长) —— 因为那两个框小得多(商店 246 px),
	##   一次把八条全塞进去会**静默截断**(排版门禁当场抓到: 要 520 px)。
	var bak_st: int = int(gs.axe_stage)
	gs.axe_stage = AE.STAGES.size() - 1        # 钻石斧: 四条被动全解锁
	var full: String = SkillText.equip_full(eq) + "
" + str(eq.get("effectDesc3", ""))
	full = SkillText.render_consts(full)
	_ok("★分母: 渲染后拿到 %d 字(为 0 就是消费方压根没读到)" % full.length(),
		full.length() > 200, full.substr(0, 40))
	## ★★占位符必须**全部展开** —— 展不开会把 {C:AxeFinalStats.XXX} 原样显示给玩家
	var re := RegEx.create_from_string("[{]C:([^}]+)[}]")
	var leftover: Array = []
	for m in re.search_all(full):
		leftover.append(m.get_string(1))
	_ok("★★没有一个占位符漏展开(漏了会把 {C:...} 原样显示给玩家)",
		leftover.is_empty(), str(leftover))
	## ★★逐条: 每一类机制都要在渲染后的文本里
	var need := {
		"被动3 强化砍(每 9 秒)": ["%d 秒" % int(AE.SMASH_IV), "击退"],
		"被动4 竖劈(流血)": ["竖劈", "%d 层流血" % AE.CLEAVE_BLEED],
		"被动5 横扫 + 效率层": ["横扫", "效率"],
		"被动6 蓄力猛砸(眩晕)": ["蓄力", "眩晕"],
		"最终造物·亡灵之斧": ["亡灵之斧", "重生"],
		"最终造物·炽天使": ["炽天使", "回旋镖"],
		"最终造物·全息斧": ["全息斧", "友军"],
		"最终造物·余烬": ["余烬", "处决线"],
	}
	for k in need:
		var miss: Array = []
		for kw in (need[k] as Array):
			if not full.contains(str(kw)):
				miss.append(str(kw))
		_ok("★★玩家读得到【%s】" % k, miss.is_empty(), "缺: %s" % str(miss))
	## ★分母: 别的装备没被这段文案污染
	var other: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_058", {})
	_ok("★分母: 别的装备(058)的描述里没有斧头的字",
		not SkillText.equip_full(other).contains("亡灵之斧"),
		SkillText.equip_full(other).substr(0, 30))

	## ★★★说明【随档位生长】—— 木斧那一屏不该背着钻石斧的说明
	var lens: Array = []
	for i in range(AE.STAGES.size()):
		gs.axe_stage = i
		lens.append(SkillText.equip_full(eq).length())
	var mono := true
	for i in range(1, lens.size()):
		if int(lens[i]) < int(lens[i - 1]):
			mono = false
	_ok("★★说明随档位【只增不减】(五档字数 %s)" % str(lens), mono)
	_ok("★★木斧那一屏【不】含钻石斧的蓄力说明(否则商店框放不下→静默截断)",
		int(lens[0]) < int(lens[lens.size() - 1]) and not _stage_text(gs, eq, 0).contains("蓄力"),
		"木斧 %d 字 vs 钻石斧 %d 字" % [int(lens[0]), int(lens[lens.size() - 1])])
	_ok("★★钻石斧那一屏【含】四条被动各自的关键词(分母: 逐条查)",
		_stage_text(gs, eq, 4).contains("击退") and _stage_text(gs, eq, 4).contains("竖劈")
		and _stage_text(gs, eq, 4).contains("横扫") and _stage_text(gs, eq, 4).contains("蓄力"))
	gs.axe_stage = bak_st


## 某一档位下, 说明渲染成什么。★换档位要**真的走 GameState**(消费方就是从那儿读的),
## 不许自己拼字符串 —— 那样测的是我的拼法, 不是玩家会看到的东西。
func _stage_text(gs, eq: Dictionary, stage_i: int) -> String:
	var bak: int = int(gs.axe_stage)
	gs.axe_stage = stage_i
	var s: String = SkillText.equip_full(eq)
	gs.axe_stage = bak
	return s