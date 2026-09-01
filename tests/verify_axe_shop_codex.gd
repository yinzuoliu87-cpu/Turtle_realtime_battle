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
	await _t_codex(gs)
	_t_name_consistency(gs)

	gs.axe_stage = int(bak["st"])
	gs.axe_final = str(bak["fin"])
	gs.persistent_bench = (bak["bench"] as Array).duplicate(true)

	if _n < 15:
		print("  [FAIL] ★分母: 断言只有 %d 条(<15) —— 有整段被跳过了" % _n)
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
