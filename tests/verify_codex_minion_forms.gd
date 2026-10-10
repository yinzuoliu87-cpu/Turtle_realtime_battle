extends Node
## verify_codex_minion_forms.gd — 图鉴小将页与龟页同一套 + 双头龟形态切换(2026-10-10 图鉴体检)。
##
##   M 小将页(近战 / 远程 / 精英): 原来自己一套 —— 16px 大段正文、没有被动条 / 普通攻击条、
##     顶上一行灰字「不可编入阵容 · 开战时自动登场」。现在右栏走龟页同一段 `_render_right`。
##     判据(量真实节点): 有「技能」小节标题; 技能写在【龟页技能卡】里(codex_card_body 富文本 + 17px 卡名 + 「主动 · 龟能 N」签);
##     右栏不再有龟页没有的那种 fit_content 大段正文; 灰字两行不在了, 换成签牌「不可编入」「每级 ×1.05」;
##     精英小将另有被动条(PassiveBar)+ 普通攻击条(BasicBar) —— 与龟页同名同构。
##     对照组: 小龟页同一批判据也成立(证明比的是"同一套", 不是凑出来的小将专属判据)。
##   T 双头龟: 原来没有形态钮, 卡名「灵能冲击/锤击」「精神干扰/吸收」两招拼一张。
##     判据: 有形态钮; 默认(远程)卡名 = 灵能冲击 / 精神干扰 / 融合, 切到近战 = 锤击 / 吸收 / 融合; 任何卡名都不带「/」;
##     每种形态的卡里不出现另一形态的招名; 拆出的名字与 pets.json 详述里「· 远程形态【X】：」标的名字一致;
##     龟能与合写那条同值; 近战页立绘换成战斗近战形态那张; 点开锤击的详情页只讲锤击。
##   L 熔岩龟(对照): 形态钮照旧在, 火山形态卡名照旧。
##
## 跑法: <godot> --headless --path . res://tests/verify_codex_minion_forms.tscn --quit-after 2000

const SCN := preload("res://scenes/Codex.tscn")
const FV := preload("res://scripts/scenes/codex/form_variants.gd")

var _n := 0
var _fail := 0
var _c = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _idx(key: String, val: String) -> int:
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if it is Dictionary and str((it as Dictionary).get(key, "")) == val:
			if key == "id" and (it as Dictionary).has("_minion"):
				continue
			return i
	return -1


func _open(key: String, val: String, form_view: bool = false) -> Dictionary:
	var i := _idx(key, val)
	if i < 0:
		return {}
	_c._select(i)
	await _settle(2)
	if form_view:
		_c._codex_form_view = true
		_c._codex_detail._redraw()
	await _settle(5)
	return _c._items[i]


func _labels() -> Array:
	var out: Array = []
	for ch in _c.detail.get_children():
		if ch is Label:
			out.append(ch)
	return out


func _texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for l in _labels():
		out.append(str((l as Label).text))
	return out


## 技能卡的卡名 = 17px(CARD_NAME_PX) 的 Label, 落在右栏、且下面那张卡有 codex_card_body 正文。
func _card_names() -> PackedStringArray:
	var bodies: Array = []
	for ch in _c.detail.get_children():
		if ch is RichTextLabel and (ch as RichTextLabel).has_meta("codex_card_body"):
			bodies.append(ch)
	var out: PackedStringArray = []
	for l in _labels():
		var lb := l as Label
		if lb.get_theme_font_size("font_size") != CodexDetail.CARD_NAME_PX or lb.position.x < CodexDetail.RCOL_X:
			continue
		for b in bodies:
			var rb := b as RichTextLabel
			if absf(rb.position.x - lb.position.x) < 2.0 and rb.position.y > lb.position.y and rb.position.y - lb.position.y < 40.0:
				out.append(lb.text)
				break
	return out


func _card_bodies_text() -> String:
	var s := ""
	for ch in _c.detail.get_children():
		if ch is RichTextLabel and (ch as RichTextLabel).has_meta("codex_card_body"):
			s += (ch as RichTextLabel).get_parsed_text() + "\n"
	return s


func _named(nm: String) -> Node:
	for ch in _c.detail.get_children():
		## 前一页的同名节点还在 queue_free 途中时, 新节点会被引擎改名(PassiveBar2…) ⇒ 认前缀 + 跳过待删的
		if str(ch.name).begins_with(nm) and not ch.is_queued_for_deletion():
			return ch
	return null


## 右栏里「龟页没有的那种」正文: fit_content 撑高、不是卡片正文也不是一行条预览的富文本(旧小将页的 _minion_body 就是它)。
func _loose_bodies() -> int:
	var n := 0
	for ch in _c.detail.get_children():
		if ch is RichTextLabel and (ch as RichTextLabel).position.x >= CodexDetail.RCOL_X - 1.0:
			var rt := ch as RichTextLabel
			if not rt.has_meta("codex_card_body") and not rt.has_meta("preview_truncated"):
				n += 1
	return n


func _same_structure(tag: String) -> void:
	var t := _texts()
	_ok("%s 有「技能」小节标题" % tag, t.has("技能"))
	var names := _card_names()
	_ok("%s 技能写在龟页技能卡里(认到 %d 张: %s)" % [tag, names.size(), ", ".join(names)], names.size() >= 1)
	var chip := false
	for s in t:
		if s.begins_with("主动 · 龟能 "):
			chip = true
	_ok("%s 卡上有「主动 · 龟能 N」签" % tag, chip)
	_ok("%s 右栏没有卡片外的大段正文" % tag, _loose_bodies() == 0, "实 %d 段" % _loose_bodies())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 图鉴: 小将页同龟页 + 双头龟形态切换 ===")
	_c = SCN.instantiate()
	add_child(_c)
	await _settle(10)
	_c._switch_tab("pets")
	await _settle(4)

	# ── 对照: 小龟页 ──
	var b := await _open("id", "basic")
	_ok("分母: 小龟页打开了", not b.is_empty())
	_same_structure("小龟(对照)")

	# ── M 小将页 ──
	for kind in ["front", "back", "elite"]:
		var it := await _open("_minion", kind)
		_ok("M %s 分母: 小将页打开了" % kind, not it.is_empty())
		_same_structure("M %s" % kind)
		var t := _texts()
		var grey := false
		for s in t:
			if s.find("开战时自动登场") >= 0 or s.find("护甲与魔抗不变") >= 0:
				grey = true
		_ok("M %s 顶上灰字说明行不在了" % kind, not grey)
		_ok("M %s 签牌「不可编入」「每级 ×1.05」" % kind, t.has("不可编入") and t.has("每级 ×1.05"), str(t))
	## 精英: 被动条 + 普通攻击条, 与龟页同名同构; 铁锁是一张签「被动」的卡
	## (就在循环最后打开的这一页上量 —— 同一页连开两次, 新节点会撞上还没删掉的旧节点名而被引擎改名)
	_ok("M elite 被动条(PassiveBar)", _named("PassiveBar") != null)
	_ok("M elite 普通攻击条(BasicBar)", _named("BasicBar") != null)
	_ok("M elite 普通攻击条写的是长手刃", _texts().has("普通攻击 · 长手刃"))
	var en := _card_names()
	_ok("M elite 技能卡 = 铁锤 + 铁锁", en.has("铁锤") and en.has("铁锁"), ", ".join(en))
	## 点被动条展开 → 与龟页同一个展开态(「收起」), 重画回到的是小将页而不是别的龟
	_c._codex_passive_view = true
	_c._codex_detail._redraw()
	await _settle(4)
	_ok("M elite 被动展开后仍是小将页、出现「收起」", _texts().has("收起") and _texts().has("精英小将"))
	_c._codex_passive_view = false

	# ── T 双头龟 ──
	var th := await _open("id", "two_head")
	_ok("T 分母: 双头龟页打开了", not th.is_empty())
	_ok("T 默认页有形态钮「切换至近战形态」", _texts().has("切换至近战形态"), str(_texts()))
	var rn := _card_names()
	_ok("T 远程形态卡名 = 灵能冲击 / 精神干扰 / 融合", rn == PackedStringArray(["灵能冲击", "精神干扰", "融合"]), ", ".join(rn))
	var rb := _card_bodies_text()
	_ok("T 远程卡里不出现近战的招(锤击/吸收/近战形态)", rb.find("锤击") < 0 and rb.find("施展吸收") < 0 and rb.find("近战形态") < 0, rb.substr(0, 60))
	var chips_r: PackedStringArray = []
	for s in _texts():
		if s.begins_with("主动 · 龟能 "):
			chips_r.append(s)
	await _open("id", "two_head", true)
	_ok("T 近战页形态钮「切换至远程形态」", _texts().has("切换至远程形态"))
	var mn := _card_names()
	_ok("T 近战形态卡名 = 锤击 / 吸收 / 融合", mn == PackedStringArray(["锤击", "吸收", "融合"]), ", ".join(mn))
	var mb := _card_bodies_text()
	_ok("T 近战卡里不出现远程的招(灵能冲击/精神干扰/远程形态)", mb.find("灵能冲击") < 0 and mb.find("精神干扰") < 0 and mb.find("远程形态") < 0, mb.substr(0, 60))
	var chips_m: PackedStringArray = []
	for s in _texts():
		if s.begins_with("主动 · 龟能 "):
			chips_m.append(s)
	_ok("T 两种形态龟能签一样(同一槽位、同一个战斗花费)", chips_r.size() == 3 and chips_r == chips_m, "%s / %s" % [chips_r, chips_m])
	var slash: PackedStringArray = []
	for s2 in rn + mn:
		if s2.find("/") >= 0:
			slash.append(s2)
	_ok("T 两种形态的卡名都不带「/」拼名", slash.is_empty(), ", ".join(slash))
	var melee_art := false
	for ch in _c.detail.get_children():
		for n in [ch] + ch.get_children():
			if n is Sprite2D and (n as Sprite2D).texture != null and (n as Sprite2D).texture.resource_path.ends_with("two_head_melee.png"):
				melee_art = true
			if n is TextureRect and (n as TextureRect).texture != null and (n as TextureRect).texture.resource_path.ends_with("two_head_melee.png"):
				melee_art = true
	_ok("T 近战页立绘 = 战斗近战形态那张(TwoHeadSystem.FORM_ART)", melee_art)
	## 拆名与 pets.json 详述里标的名字一致(拆错方向会把锤击挂到远程)
	var sp: Array = th.get("skillPool", [])
	var n_var := 0
	for sk in sp:
		if FV.is_variant(sk) and str((sk as Dictionary).get("name", "")).find("/") >= 0:
			n_var += 1
			for f in [0, 1]:
				var a: String = FV.form_name(sk, f)
				var m: String = FV.marked_name(str((sk as Dictionary).get("detail", "")), f)
				_ok("T 拆名对得上详述标记 %s 形态%d: %s == %s" % [str(sk["name"]), f, a, m], a == m and a != "")
	_ok("T 分母: 认到 2 条随形态变招的技能", n_var == 2, "实 %d" % n_var)
	## 点开锤击 → 详情页只讲锤击
	var pool_m: Array = FV.pool(th, 1)
	var hammer: Dictionary = {}
	for sk in pool_m:
		if str((sk as Dictionary).get("name", "")) == "锤击":
			hammer = sk
	_ok("T 分母: 近战技能池里有锤击", not hammer.is_empty())
	_c._codex_skill_detail = hammer
	_c._codex_detail._redraw()
	await _settle(4)
	var all_rt := ""
	for ch in _c.detail.get_children():
		if ch is RichTextLabel:
			all_rt += (ch as RichTextLabel).get_parsed_text() + "\n"
	_ok("T 锤击详情页有锤击的数、没有灵能冲击", all_rt.find("锤击") >= 0 and all_rt.find("灵能冲击") < 0 and all_rt.find("随形态变体") < 0, all_rt.substr(0, 80))
	_c._codex_skill_detail = {}

	# ── L 熔岩龟(对照) ──
	await _open("id", "lava")
	_ok("L 熔岩龟形态钮照旧", _texts().has("切换至火山形态"))
	await _open("id", "lava", true)
	var ln := _card_names()
	_ok("L 火山形态卡名照旧(火山爆发)", ln.has("火山爆发"), ", ".join(ln))

	print("ALL PASS — 图鉴小将页/双头龟形态 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
