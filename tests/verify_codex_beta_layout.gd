extends Node
## verify_codex_beta_layout.gd — 内测前图鉴体检(2026-10-07)里的版式/交互项, 每项量真实节点。
##
##   B 普攻条: 简述定高一行 + clip, 原来**没有任何办法看到被切掉的部分**(15 只龟)。
##     判据: 每只龟的普攻条右端都有「看全部」; 点普攻条(真发一次鼠标事件) ⇒ 进技能详情,
##     忍者龟那句「暴击时 3 层」流血能读到。
##   F 熔岩龟形态页: 「换成 X 形态」钮压在普攻条上 / 「熔岩弹（火山形态）」名字压着简述 /
##     三选一卡片只剩 1 行正文。判据: 钮与普攻条矩形不相交; 名字右缘 ≤ 简述左缘; 每张卡 ≥ 2 整行。
##   G 技能卡最后一行被切成半截(15 张) / 只切掉尾部空行却提示「点开看全部」(26 张)。
##     判据: 全部 28 只龟, 每个定高富文本里**没有一行跨过下边缘**; 画了提示的卡, 被藏起来的部分里有字。
##   H 小将页: 攻速单位与龟页同一种(「每秒攻击」); 技能图标画出来; 抬头「主动 · 龟能 N」;
##     不再出现「顶上统领位」。
##   I 圣光护盾(095)没有分档却挂着「数值分档 ★1/★2/★3」(判据 `bb.find("/")` 被 [/b] 恒真)。
##     判据: 095 没有图例; 木制长剑(001, 真有三档)仍有图例 —— 正反两面。
##
## 跑法: bash godot-quiet.sh res://tests/verify_codex_beta_layout.tscn --quit-after 1500

const SCN := preload("res://scenes/Codex.tscn")

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


func _open(key: String, val: String) -> Dictionary:
	_c._codex_skill_detail = {}
	_c._codex_passive_view = false
	_c._codex_form_view = false
	var i := _idx(key, val)
	if i < 0:
		return {}
	_c._select(i)
	await _settle(5)
	return _c._items[i]


func _labels_text() -> PackedStringArray:
	var out: PackedStringArray = []
	for ch in _c.detail.get_children():
		if ch is Label:
			out.append(str((ch as Label).text))
	return out


func _rich() -> String:
	var s := ""
	for ch in _c.detail.get_children():
		if ch is RichTextLabel:
			s += (ch as RichTextLabel).get_parsed_text() + "\n"
	return s


func _label_starting(prefix: String) -> Label:
	for ch in _c.detail.get_children():
		if ch is Label and str((ch as Label).text).begins_with(prefix):
			return ch
	return null


## 普攻条那块底板。★2026-10-08 两栏后不再是「宽 > 800、高 36」⇒ 按产品给它起的节点名找。
func _basic_bar() -> Panel:
	for ch in _c.detail.get_children():
		if ch is Panel and str(ch.name) == "BasicBar":
			return ch
	return null


## 定高(非 fit_content)富文本: 跨过下边缘的半截行数、整行可见数。
func _partial_lines(rt: RichTextLabel) -> int:
	var h := rt.size.y
	var lc := rt.get_line_count()
	var ch := rt.get_content_height()
	var bad := 0
	for li in range(lc):
		var off := rt.get_line_offset(li)
		var nxt: float = rt.get_line_offset(li + 1) if li + 1 < lc else ch
		if off < h - 1.0 and nxt > h + 2.0:
			bad += 1
	return bad


func _full_lines(rt: RichTextLabel) -> int:
	var h := rt.size.y
	var lc := rt.get_line_count()
	var n := 0
	for li in range(lc):
		var nxt: float = rt.get_line_offset(li + 1) if li + 1 < lc else rt.get_content_height()
		if nxt <= h + 0.5:
			n += 1
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 图鉴内测前体检: 版式/交互 ===")
	_c = SCN.instantiate()
	add_child(_c)
	await _settle(10)
	_c._switch_tab("pets")
	await _settle(4)

	_check_removed_pages()
	await _check_g_and_b_all()
	await _check_b_ninja_click()
	await _check_f_lava()
	await _check_h_minion()
	await _check_i_tiers()
	await _check_status_page()

	print("ALL PASS — 图鉴内测前体检版式项 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


## 2026-10-07 用户追加两条: 「规则页直接删掉，我们没有这东西」「右上角调试器直接删掉」。
## 量真实建出来的整棵树: 没有任何按钮/字写着「规则」页签或 🛠, 没有 DebugOverlay 节点, 也没有那两个入口函数。
func _all_texts(n: Node, acc: PackedStringArray) -> void:
	for ch in n.get_children():
		if ch is Button:
			acc.append(str((ch as Button).text))
		elif ch is Label:
			acc.append(str((ch as Label).text))
		_all_texts(ch, acc)


func _check_removed_pages() -> void:
	print("-- 删掉的两块: 规则页签 / 调试面板 --")
	var acc: PackedStringArray = []
	_all_texts(_c, acc)
	_ok("分母: 图鉴整棵树抽到 %d 段字(页签「装备」在其中)" % acc.size(),
		acc.size() > 20 and " ".join(acc).find("装备") >= 0)
	var rule_hits: PackedStringArray = []
	var dbg_hits: PackedStringArray = []
	for t in acc:
		if t.begins_with("规则"):
			rule_hits.append(t)
		if t.find("🛠") >= 0 or t.find("调试") >= 0:
			dbg_hits.append(t)
	_ok("没有「规则」页签", rule_hits.is_empty(), str(rule_hits))
	_ok("右上角没有调试按钮/面板(🛠/调试)", dbg_hits.is_empty() and _c.get_node_or_null("DebugOverlay") == null, str(dbg_hits))
	_ok("调试面板与规则详情的入口函数都已删", not _c.has_method("_toggle_debug_overlay")
		and not _c._codex_detail.has_method("_show_rule"))


## G + B(每只龟): 半截行 / 假提示 / 普攻条有「看全部」
func _check_g_and_b_all() -> void:
	print("-- G/B 全部龟 --")
	var n_pet := 0
	var n_rt := 0
	var partial: PackedStringArray = []
	var false_hint: PackedStringArray = []
	var no_basic_hint: PackedStringArray = []
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if not (it is Dictionary) or (it as Dictionary).has("_minion"):
			continue
		var pid := str((it as Dictionary).get("id", ""))
		_c._codex_skill_detail = {}
		_c._codex_passive_view = false
		_c._codex_form_view = false
		_c._select(i)
		await _settle(5)
		n_pet += 1
		## 「看全部」: 被动条一个 + 普攻条一个
		var n_all := 0
		for ch in _c.detail.get_children():
			if ch is Label and str((ch as Label).text) == "查看全部" and (ch as Label).horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT:
				n_all += 1
		if n_all < 2:
			no_basic_hint.append("%s(%d)" % [pid, n_all])
		for ch in _c.detail.get_children():
			if not (ch is RichTextLabel) or (ch as RichTextLabel).fit_content:
				continue
			var rt := ch as RichTextLabel
			n_rt += 1
			if _partial_lines(rt) > 0:
				partial.append("%s「%s」" % [pid, rt.get_parsed_text().substr(0, 14)])
			## 假提示: 被切了(content > size), 但被藏起来的只有空白
			if rt.get_content_height() > rt.size.y + 0.5 and rt.size.y > 40.0:
				var full := _full_lines(rt)
				var trimmed := rt.get_parsed_text().strip_edges(false, true)
				if trimmed.count("\n") + 1 <= full and trimmed != rt.get_parsed_text():
					false_hint.append("%s「%s」" % [pid, trimmed.substr(0, 14)])
	_ok("G 分母: 逐只量了 %d 只龟 / %d 个定高富文本" % [n_pet, n_rt], n_pet >= 28 and n_rt >= 28 * 4)
	_ok("G 没有一行被切成半截(原 15 处)", partial.is_empty(), ", ".join(partial))
	_ok("G 没有「只切掉尾部空行却提示看全部」(原 26 处)", false_hint.is_empty(), ", ".join(false_hint))
	_ok("B 每只龟的普攻条都有「看全部」(被动 + 普攻 ≥ 2)", no_basic_hint.is_empty(), ", ".join(no_basic_hint))


## B: 忍者龟, 真发一次鼠标点击到普攻条上
func _check_b_ninja_click() -> void:
	print("-- B 忍者龟普攻条点开 --")
	await _open("id", "ninja")
	var bar := _basic_bar()
	_ok("B 分母: 找到普攻条", bar != null)
	if bar == null:
		return
	var hit: Control = null
	for ch in _c.detail.get_children():
		if ch.get_class() == "Control" and absf((ch as Control).position.y - bar.position.y) < 0.5 \
				and absf((ch as Control).size.y - bar.size.y) < 0.5:
			hit = ch
	_ok("B 普攻条上盖着一块可点区域(MOUSE_FILTER_STOP)", hit != null and hit.mouse_filter == Control.MOUSE_FILTER_STOP)
	if hit == null:
		return
	var before := _rich()
	## ★2026-10-08 技能/装备文案按 LoL 体例整体改写(copy_lol_style_lint)后, 句式变了、数值与归属没变: 「暴击时 3 层」→「暴击时改为 3 层」, 改认「暴击时」+「3 层」。
	_ok("B 反面: 点开前那句「暴击时…3 层」读不到", before.find("暴击时改为 3 层") < 0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	hit.gui_input.emit(ev)
	await _settle(4)
	var after := _rich()
	_ok("B 点普攻条 ⇒ 进技能详情, 流血那句可见(「暴击时 3 层」)", after.find("暴击时改为 3 层") >= 0 and after.find("流血") >= 0,
		after.substr(0, 60).replace("\n", "⏎"))
	_c._codex_skill_detail = {}


## F: 熔岩龟(普通 + 火山形态页)。★双头龟的 meleeSkills 已经是空的(只剩熔岩龟一只双形态), 不在这里列。
func _check_f_lava() -> void:
	print("-- F 双形态龟版式 --")
	for pid in ["lava"]:
		for form in [false, true]:
			var it := await _open("id", pid)
			if form:
				_c._codex_form_view = true
				_c._codex_detail._show_pet(it)
				await _settle(5)
			var tag := "%s%s" % [pid, "·形态页" if form else ""]
			var bar := _basic_bar()
			var btn_lbl := _label_starting("切换至")
			_ok("F %s 分母: 普攻条与形态切换钮都在" % tag, bar != null and btn_lbl != null)
			if bar == null or btn_lbl == null:
				continue
			## 钮的底板: 与钮文字同中心的 196×34 Panel
			var btn_rect := Rect2()
			for ch in _c.detail.get_children():
				if ch is Panel and absf((ch as Panel).size.x - 196.0) < 0.5:
					btn_rect = Rect2((ch as Panel).position, (ch as Panel).size)
			var bar_rect := Rect2(bar.position, bar.size)
			_ok("F %s 形态切换钮不压普攻条" % tag, btn_rect.size.x > 0.0 and not btn_rect.intersects(bar_rect),
				"钮 %s / 普攻条 %s" % [str(btn_rect), str(bar_rect)])
			var nm := _label_starting("普通攻击 · ")
			var brief: RichTextLabel = null
			for ch in _c.detail.get_children():
				## 普攻简述 = 落在普攻条里面的那个定高富文本(两行条: 名字一行、简述一行)
				if ch is RichTextLabel and not (ch as RichTextLabel).fit_content \
						and (ch as RichTextLabel).position.y > bar.position.y \
						and (ch as RichTextLabel).position.y < bar.position.y + bar.size.y:
					brief = ch
			if nm != null and brief != null:
				## ★2026-10-08 两行条: 名字在上一行、简述在下一行 ⇒ 判据从「名字右缘 ≤ 简述左缘」换成「两块矩形不相交」(意思不变: 不压字)。
				var nm_rect := Rect2(nm.position, nm.get_combined_minimum_size())
				var br_rect := Rect2(brief.position, brief.size)
				_ok("F %s 普攻名字 %s 不压简述 %s「%s」" % [tag, str(nm_rect), str(br_rect), nm.text],
					not nm_rect.intersects(br_rect))
			else:
				_ok("F %s 分母: 普攻名字与简述都在" % tag, false)
			## ★2026-10-08 竖排后卡片变宽(正文 412), 短简述本来就只有 1~2 行 ⇒ 不能再拿「高 > 40」认卡片、也不能要求人人 ≥2 行。
			##   意思不变: 每张卡至少露出 min(2, 它自己的总行数) 整行 —— 卡片没被形态钮那一行挤扁。分母: 认到 ≥3 张卡。
			var n_cards := 0
			var squeezed: PackedStringArray = []
			for ch in _c.detail.get_children():
				if ch is RichTextLabel and (ch as RichTextLabel).has_meta("codex_card_body"):
					n_cards += 1
					var need: int = mini(2, (ch as RichTextLabel).get_line_count())
					if _full_lines(ch) < need:
						squeezed.append("%s(%d/%d)" % [(ch as RichTextLabel).get_parsed_text().substr(0, 8), _full_lines(ch), need])
			_ok("F %s 分母: 认到 %d 张三选一卡片" % [tag, n_cards], n_cards >= 3)
			_ok("F %s 三选一卡片每张至少露出 2 整行正文(不足 2 行的露全)" % tag, squeezed.is_empty(), ", ".join(squeezed))


## H: 小将页
func _check_h_minion() -> void:
	print("-- H 小将页 --")
	var icons := {"front": "minion-bodysurf.png", "back": "minion-rocket.png"}
	for kind in ["front", "back", "elite"]:
		var it := await _open("_minion", kind)
		_ok("H %s 分母: 小将页打开了" % kind, not it.is_empty())
		var labels := _labels_text()
		_ok("H %s 攻速单位与龟页同一种(「每秒攻击」, 不再写「间隔 X 秒」)" % kind,
			labels.has("每秒攻击") and not labels.has("间隔"), str(labels))
		_ok("H %s 技能抬头「主动 · 龟能 N」" % kind, _label_starting("主动 · 龟能 ") != null)
		_ok("H %s 射程印的是实际生效值" % kind,
			labels.has(str(int(MinionCodex.MINION_INFO[kind]["range"]))))
		var joined := " ".join(labels)
		_ok("H %s 不再出现开发者用词「统领位」" % kind, joined.find("统领位") < 0)
		if icons.has(kind):
			var found := false
			for ch in _c.detail.get_children():
				if ch is TextureRect and (ch as TextureRect).texture != null \
						and (ch as TextureRect).texture.resource_path.ends_with(str(icons[kind])):
					found = true
			_ok("H %s 技能图标画出来了(%s)" % [kind, icons[kind]], found)


## 状态页(2026-10-07 用户追加): 补齐战斗里看得到的状态; 说明一律「一句话只讲机制」, 数值走 {C:} 常量。
##   判据: 每一条渲染后都没有 `{` 残留(占位符全求出了值)、有正文; 恐惧那条不再说「龟能照常」;
##   新补的几条都在; 叙事腔的旧开头一个都不剩。
func _check_status_page() -> void:
	print("-- 状态页 --")
	_c._switch_tab("status")
	await _settle(4)
	var names: PackedStringArray = []
	var leftover: PackedStringArray = []
	var fear_txt := ""
	var dodge_txt := ""
	for i in range(_c._items.size()):
		_c._select(i)
		await _settle(2)
		var it: Dictionary = _c._items[i]
		var nm := str(it.get("name", ""))
		names.append(nm)
		var txt := _rich()
		if txt.find("{") >= 0 or txt.strip_edges().length() < 6:
			leftover.append(nm)
		if nm == "恐惧":
			fear_txt = txt
		if nm == "闪避":
			dodge_txt = txt
	_ok("状态 分母: 状态页列出 %d 条" % names.size(), names.size() >= 24, ", ".join(names))
	for want in ["减速", "不可选中", "龟能锁", "真火", "击飞", "腐蚀", "墨迹", "结晶印记", "电击标记", "充能", "猎杀印记"]:
		_ok("状态 补上了「%s」" % want, names.has(want))
	_ok("状态 每条渲染后没有占位符残留、都有正文", leftover.is_empty(), ", ".join(leftover))
	_ok("状态 恐惧: 写明龟能不增长(不再是「照常攒」)", fear_txt.find("龟能不增长") >= 0 and fear_txt.find("照常") < 0, fear_txt.strip_edges())
	_ok("状态 闪避上限从代码常量求出(75%)", dodge_txt.find("75%") >= 0, dodge_txt.strip_edges())
	var raw := FileAccess.get_file_as_string("res://data/status.json")
	var narr: PackedStringArray = []
	for w in ["身上着了火", "打懵了", "吓住的一方", "眼里只剩", "伤口不肯收口", "冻得动作发僵", "半透明地晃着", "挨一下就还一下"]:
		if raw.find(w) >= 0:
			narr.append(w)
	_ok("状态 拟人叙事腔的旧开头一个不剩", narr.is_empty(), ", ".join(narr))
	_c._switch_tab("pets")
	await _settle(2)


## I: 分档图例只给真有分档的装备
func _check_i_tiers() -> void:
	print("-- I 数值分档图例 --")
	_c._switch_tab("equips")
	await _settle(4)
	for cs in [["p2eq_095", false], ["p2eq_001", true]]:
		var it := await _open("id", str(cs[0]))
		_ok("I 分母: %s 打开了" % cs[0], not it.is_empty())
		var has_legend := _rich().find("数值分档") >= 0
		_ok("I %s %s「数值分档」图例" % [cs[0], "有" if cs[1] else "没有"], has_legend == bool(cs[1]))
	_c._switch_tab("pets")
	await _settle(2)
