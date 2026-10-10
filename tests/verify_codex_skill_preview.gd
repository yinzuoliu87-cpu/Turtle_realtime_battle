extends Node
const FormVariantsRef := preload("res://scripts/scenes/codex/form_variants.gd")
## verify_codex_skill_preview.gd — 图鉴龟页: 技能标签/龟能 == 战斗; 一行预览截断; 小标题行; 字号(2026-10-10 视觉体检)。
##
##   ① 每只龟每个技能(含熔岩龟火山形态组), 图鉴卡片签「主动 · 龟能 N」/「被动」/「普通攻击」与详情页标题里的「龟能 N」
##      == 战斗真实行为: 主动与否问战斗自己的 `_resolve_active_skills`(按 foe_loadouts 逐槽选中),
##      龟能问战斗自己的 `_skill_cost`(火山形态带 volcano=true)。
##      改前: 赌神龟「命运之轮」/ 海盗龟「海盗船」/ 水晶龟「水晶球」标「被动」不显龟能(战斗 110/120/70 照放);
##            火山形态「熔岩弹（火山形态）」(普攻)标「龟能 95」; 火山三张卡显 95/95/80, 实发 115/150/120。
##   ② 技能详情页: 标题折行时正文不压在标题上(造一个超长名字的技能, 先断言它真的折行了)。
##   ③ 被动条/普攻条: 只占一行; 放不下就以「…」收尾, 截断处是原文的前缀(没切进标签、没漏标签字);
##      没截断的就是全文; 「查看全部」只在截断时出现。简述/卡片正文不以纯小标题行开头(海盗龟「登场轰击：」/
##      龟壳「主被动·潜影：」), 卡片可见的最后一行也不是纯小标题(石头龟「磐石之躯」停在「被动：」)。
##   ④ 字号: 技能卡正文 / 一行条简述 ≥ 16, 「技能」小节标题 ≥ 16; 卡名行的龟能签不与「查看全部」相撞。
##
## 跑法: <godot> --headless --path . res://tests/verify_codex_skill_preview.tscn --quit-after 14000

const SCN := preload("res://scenes/Codex.tscn")
const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SkillText := preload("res://scripts/util/skill_text.gd")
const MIN_PX := 16

var _n := 0
var _fail := 0
var _c = null
var _b = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


## 测试自己的「纯小标题行」定义(不借产品的 PreviewText): 冒号收尾、≤ 12 字。
func _is_heading(t: String) -> bool:
	var s := t.strip_edges()
	return s.length() >= 2 and s.length() <= 12 and (s.ends_with("：") or s.ends_with(":"))


## 战斗真相: 这只龟第 idx 槽被选中时, 战斗把它放进主动轮转吗 / 花多少龟能。
func _battle_truth(pet: Dictionary, idx: int, volcano: bool) -> Dictionary:
	var id := str(pet["id"])
	var pool: Array = pet.get("skillPool", [])
	if idx == 0:
		return {"role": "basic", "cost": 0}
	GameState.foe_loadouts[id] = idx
	var act: Array = _b._resolve_active_skills(id, false)
	var ty := str((pool[idx] as Dictionary).get("type", ""))
	var u := {"energy_cost": BattleSpawn.energy_cost_table(pet), "volcano": volcano}
	return {"role": "active" if act.has(ty) else "passive", "cost": int(round(float(_b._skill_cost(u, ty)))),
		"reached": _b._resolve_chosen_index(id, false) == idx}


func _expected_chip(t: Dictionary) -> String:
	match str(t["role"]):
		"basic": return "普通攻击"
		"passive": return "被动"
	return "主动 · 龟能 %d" % int(t["cost"])


func _chips() -> Array:
	var out: Array = []
	for ch in _c.detail.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Label:
			var t := str((ch as Label).text)
			if t == "被动" or t == "普通攻击" or t.begins_with("主动 · 龟能 "):
				out.append(ch)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	var saved_foe: Dictionary = GameState.foe_loadouts.duplicate(true)
	_b = Battle.new()
	for p in DataRegistry.all_pets:
		_b._data_by_id[str(p["id"])] = p
	_c = SCN.instantiate()
	add_child(_c)
	await _settle(10)
	_c._switch_tab("pets")
	await _settle(4)
	print("=== 图鉴龟页: 技能标签/龟能 == 战斗 · 一行预览 · 字号 ===")
	await _check_roles_and_energy()
	await _check_detail_title()
	await _check_previews()
	GameState.foe_loadouts = saved_foe
	_b.free()
	print("ALL PASS — 图鉴龟页技能预览 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)


## ① 卡片签 + 详情页标题 == 战斗
func _check_roles_and_energy() -> void:
	print("-- ① 卡片签 / 详情标题 vs 战斗 --")
	var bad_chip: PackedStringArray = []
	var bad_title: PackedStringArray = []
	var unreached: PackedStringArray = []
	var n_chip := 0
	var n_title := 0
	var n_form := 0
	var named: Dictionary = {}   # 点名的三张 + 火山普攻, 单独报
	for i in range(_c._items.size()):
		var pet: Dictionary = _c._items[i]
		for key in ["skillPool", "volcanoSkills", "meleeSkills"]:
			var pool: Variant = pet.get(key, [])
			if not (pool is Array) or (pool as Array).is_empty():
				continue
			var form: bool = key != "skillPool"
			_c._codex_skill_detail = {}
			_c._codex_passive_view = false
			_c._select(i)
			await _settle(2)
			_c._codex_form_view = form
			_c._codex_detail._show_pet(pet)
			await _settle(3)
			var chips := _chips()
			var want: Array = []
			var truths: Array = []
			for k in range((pool as Array).size()):
				var t := _battle_truth(pet, k, form)
				truths.append(t)
				if k > 0 and not bool(t.get("reached", true)):
					unreached.append("%s/%s" % [pet["id"], (pool as Array)[k].get("name", "?")])
				if k > 0:
					want.append(_expected_chip(t))
			var got: Array = []
			for ch in chips:
				got.append(str((ch as Label).text))
			n_chip += got.size()
			if form:
				n_form += got.size()
			if got != want:
				bad_chip.append("%s%s 图鉴 %s / 战斗 %s" % [pet["id"], "(形态)" if form else "", str(got), str(want)])
			for k in range((pool as Array).size()):
				var sk: Dictionary = (pool as Array)[k]
				var nm := str(sk.get("name", ""))
				if nm in ["命运之轮", "海盗船", "水晶球", "熔岩弹（火山形态）", "烈焰暴走"]:
					named[nm] = "%s | 战斗 %s" % [(got[k - 1] if k > 0 and k - 1 < got.size() else "(普攻条)"), _expected_chip(truths[k])]
				## 详情页标题
				_c._codex_skill_detail = sk
				_c._codex_detail._show_pet(pet)
				await _settle(1)
				var title: RichTextLabel = _detail_title()
				if title == null:
					bad_title.append("%s/%s 没找到标题" % [pet["id"], nm])
					continue
				n_title += 1
				var tt := str(title.text)
				var t: Dictionary = truths[k]
				var ok: bool
				if str(t["role"]) == "active":
					ok = tt.find("龟能 %d" % int(t["cost"])) >= 0
				else:
					ok = tt.find("龟能") < 0
				if not ok:
					bad_title.append("%s/%s 标题「%s」战斗 %s" % [pet["id"], nm, title.get_parsed_text(), _expected_chip(t)])
			_c._codex_skill_detail = {}
	_c._codex_form_view = false
	_ok("① 分母: 卡片签 %d 个(其中形态组 %d)、详情标题 %d 个" % [n_chip, n_form, n_title],
		n_chip >= 28 * 3 + 3 and n_form >= 3 and n_title >= 28 * 4 + 4)
	_ok("① 分母: 每个候选槽都真能被战斗选中(否则这条对的是回落技)", unreached.is_empty(), ", ".join(unreached))
	_ok("① 点名的五张都量到了", named.size() == 5, str(named))
	for nm in named.keys():
		print("      %s: 图鉴 %s" % [nm, named[nm]])
	_ok("★① 卡片签(主动·龟能 N / 被动 / 普通攻击) == 战斗", bad_chip.is_empty(), "; ".join(bad_chip))
	_ok("★① 详情页标题的「龟能 N」== 战斗(非主动不显)", bad_title.is_empty(), "; ".join(bad_title.slice(0, 6)))


func _detail_title() -> RichTextLabel:
	for ch in _c.detail.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is RichTextLabel and (ch as RichTextLabel).fit_content and str((ch as RichTextLabel).text).find("[font_size=32]") >= 0:
			return ch
	return null


## ② 标题折行时正文让开 —— 造一个超长名字的主动技(先断言它真折行了, 否则就是空检查)。
func _check_detail_title() -> void:
	print("-- ② 详情页标题折行不压正文 --")
	var pet: Dictionary = (_c._items[0] as Dictionary).duplicate(true)
	var sk: Dictionary = (pet["skillPool"] as Array)[1]
	sk["name"] = "超长超长超长超长超长的技能名字"
	_c._codex_form_view = false
	_c._codex_skill_detail = sk
	_c._codex_detail._show_pet(pet)
	await _settle(2)
	var title := _detail_title()
	var body: RichTextLabel = null
	for ch in _c.detail.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is RichTextLabel and (ch as RichTextLabel).fit_content and ch != title and (ch as RichTextLabel).position.y > 40.0:
			body = ch
	_ok("② 分母: 标题与正文都找到了, 标题真的折成了多行", title != null and body != null and title.get_line_count() >= 2,
		"行数 %d" % (title.get_line_count() if title != null else -1))
	if title != null and body != null:
		var t_bot := title.position.y + title.get_content_height()
		_ok("★② 正文上沿 ≥ 标题下沿(不重叠)", body.position.y >= t_bot - 0.5,
			"标题下沿 %.1f / 正文上沿 %.1f" % [t_bot, body.position.y])
	## 真数据也逐只扫: 所有详情页正文都在标题下面
	var overl: PackedStringArray = []
	var n := 0
	for i in range(_c._items.size()):
		var p: Dictionary = _c._items[i]
		for key in ["skillPool", "volcanoSkills"]:
			var pool: Variant = p.get(key, [])
			if not (pool is Array):
				continue
			_c._codex_form_view = key != "skillPool"
			for s in pool:
				_c._codex_skill_detail = s
				_c._codex_detail._show_pet(p)
				await _settle(1)
				var tl := _detail_title()
				for ch in _c.detail.get_children():
					if ch.is_queued_for_deletion():
						continue
					if ch is RichTextLabel and (ch as RichTextLabel).fit_content and ch != tl and tl != null \
						and (ch as RichTextLabel).position.y > tl.position.y:
						n += 1
						if (ch as RichTextLabel).position.y < tl.position.y + tl.get_content_height() - 0.5:
							overl.append("%s/%s" % [p["id"], s.get("name", "?")])
	_c._codex_skill_detail = {}
	_c._codex_form_view = false
	_ok("② 全部 28 只 × 全部技能(含形态组)的详情正文都在标题下面(量了 %d 页)" % n, n >= 28 * 4 and overl.is_empty(), ", ".join(overl))


## ③ + ④ 一行条 / 卡片正文
func _check_previews() -> void:
	print("-- ③ 一行预览 / 小标题行 · ④ 字号 --")
	var tmp := RichTextLabel.new()   # 只用来把整段 BBCode 拍平成纯文字(核对截断处是不是原文前缀)
	tmp.bbcode_enabled = true
	tmp.size = Vector2(4000, 400)
	add_child(tmp)
	var n_bar := 0
	var n_cut := 0
	var n_card := 0
	var bad_line: PackedStringArray = []
	var bad_prefix: PackedStringArray = []
	var bad_hint: PackedStringArray = []
	var bad_head: PackedStringArray = []
	var bad_tail: PackedStringArray = []
	var bad_font: PackedStringArray = []
	var bad_collide: PackedStringArray = []
	var firsts: Dictionary = {}
	var stone_rock := ""
	var n_section := 0
	for i in range(_c._items.size()):
		var pet: Dictionary = _c._items[i]
		if not pet.has("skillPool"):
			continue   # 龟页签列表尾部还挂着小将条目(没有 skillPool), 它们不走龟页
		var pid := str(pet["id"])
		_c._codex_skill_detail = {}
		_c._codex_passive_view = false
		_c._codex_form_view = false
		_c._select(i)
		await _settle(6)
		var ctx = _c._ctx_for(pet)
		## ★双头龟(2026-10-10): 普攻条按形态只印默认(远程)那一半 —— 原文取同一个拆法(FormVariants), 不拿合写的整段比。
		var _pool0: Array = FormVariantsRef.pool(pet, 0) if FormVariantsRef.has_variants(pet) else (pet.get("skillPool", []) as Array)
		var sources: Array = [str((pet.get("passive", {}) as Dictionary).get("brief", "")), str((_pool0[0] as Dictionary).get("brief", ""))]
		var bars: Array = []
		var cards: Array = []
		var row_hints := 0
		var card_hints: Array = []
		for ch in _c.detail.get_children():
			if ch.is_queued_for_deletion():
				continue
			if ch is RichTextLabel and (ch as RichTextLabel).has_meta("preview_truncated"):
				bars.append(ch)
			elif ch is RichTextLabel and (ch as RichTextLabel).has_meta("codex_card_body"):
				cards.append(ch)
			elif ch is Label and str((ch as Label).text) == "查看全部":
				if (ch as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
					card_hints.append(ch)
				else:
					row_hints += 1
			elif ch is Label and str((ch as Label).text) == "技能":
				n_section += 1
				if (ch as Label).get_theme_font_size("font_size") < MIN_PX:
					bad_font.append("%s「技能」%d" % [pid, (ch as Label).get_theme_font_size("font_size")])
		var cut_here := 0
		for bi in range(bars.size()):
			var rt: RichTextLabel = bars[bi]
			n_bar += 1
			var shown := rt.get_parsed_text()
			if rt.get_theme_font_size("normal_font_size") < MIN_PX:
				bad_font.append("%s 一行条 %d" % [pid, rt.get_theme_font_size("normal_font_size")])
			if rt.get_line_count() != 1 or rt.get_content_height() > rt.size.y + 0.5:
				bad_line.append("%s#%d 行数 %d" % [pid, bi, rt.get_line_count()])
			if shown.find("[") >= 0 or shown.find("]") >= 0:
				bad_prefix.append("%s#%d 漏出标签「%s」" % [pid, bi, shown])
			if _is_heading(shown.split("\n")[0]):
				bad_head.append("%s#%d「%s」" % [pid, bi, shown])
			firsts["%s#%d" % [pid, bi]] = shown
			## 原文拍平(整段, 去换行): 截断处必须是它的一段连续原文
			var src_pv: Dictionary = pet.get("passive", {}) if bi == 0 else (pet.get("skillPool", []) as Array)[0]
			tmp.text = SkillText.render_bbcode(sources[bi] if bi < sources.size() else "", ctx, src_pv, 16)
			var full := tmp.get_parsed_text().replace("\n", "")
			if shown.ends_with("…"):
				cut_here += 1
				var stem := shown.substr(0, shown.length() - 1)
				if stem.strip_edges() == "" or full.find(stem) < 0:
					bad_prefix.append("%s#%d「%s」不是原文前缀" % [pid, bi, stem])
			else:
				## 没截断 = 全文(去掉开头小标题行后)都在这一行里
				if full.find(shown.strip_edges()) < 0 or shown.strip_edges().length() + 12 < full.strip_edges().length():
					bad_prefix.append("%s#%d 没「…」却不是全文「%s」" % [pid, bi, shown])
		n_cut += cut_here
		if row_hints != cut_here:
			bad_hint.append("%s 提示 %d / 截断 %d" % [pid, row_hints, cut_here])
		## 卡片正文
		for ci in range(cards.size()):
			var rt: RichTextLabel = cards[ci]
			n_card += 1
			if rt.get_theme_font_size("normal_font_size") < MIN_PX:
				bad_font.append("%s 卡 %d" % [pid, rt.get_theme_font_size("normal_font_size")])
			var pt := rt.get_parsed_text()
			var first := ""
			if rt.get_line_count() > 0:
				var r0 := rt.get_line_range(0)
				first = pt.substr(r0.x, r0.y - r0.x)
			firsts["%s/card%d" % [pid, ci]] = first
			if _is_heading(first):
				bad_head.append("%s 卡%d「%s」" % [pid, ci, first])
			## 可见的最后一整行
			## 可见的最后一整行; 只在它【整段】就是一个小标题时算(行首 = 段首) —— 长句折行剩下的「性：」不算
			var last := ""
			var last_para := false
			for li in range(rt.get_line_count()):
				var nxt: float = rt.get_line_offset(li + 1) if li + 1 < rt.get_line_count() else rt.get_content_height()
				if nxt <= rt.size.y + 0.5:
					var r := rt.get_line_range(li)
					last = pt.substr(r.x, r.y - r.x)
					last_para = r.x == 0 or pt.substr(r.x - 1, 1) == "\n"
			if pid == "stone" and ci == 1:
				stone_rock = last
			if last_para and _is_heading(last) and rt.get_content_height() > rt.size.y + 0.5:
				bad_tail.append("%s 卡%d 停在「%s」" % [pid, ci, last.strip_edges()])
		## ④ 名字行: 龟能签与「查看全部」不相撞
		for ch in _chips():
			var cl := ch as Label
			var cr: float = cl.position.x + cl.get_minimum_size().x
			if cr > float(_c.DETAIL_W) - 20.0:
				bad_collide.append("%s「%s」越过右缘 %.0f" % [pid, cl.text, cr])
			for h in card_hints:
				var hl := h as Label
				var hleft: float = hl.position.x + hl.size.x - hl.get_minimum_size().x
				var hcy: float = hl.position.y + hl.size.y / 2.0
				var ccy: float = cl.position.y + cl.size.y / 2.0
				if absf(hcy - ccy) < 14.0 and cr + 6.0 > hleft:
					bad_collide.append("%s「%s」右缘 %.0f 撞「查看全部」%.0f" % [pid, cl.text, cr, hleft])
	tmp.queue_free()
	## 真数据里 28 条被动全都长到要截断 ⇒「完整的被动条不挂提示」这一面量不到。造一只被动只有一句短话的龟补上。
	var short_pet: Dictionary = (_c._items[0] as Dictionary).duplicate(true)
	(short_pet["passive"] as Dictionary)["brief"] = "登场后变得更加勇敢。"
	_c._codex_passive_view = false
	_c._codex_detail._show_pet(short_pet)
	await _settle(3)
	var s_hint := 0
	var s_text := ""
	for ch in _c.detail.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is Label and str((ch as Label).text) == "查看全部" and (ch as Label).horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT \
			and absf((ch as Label).position.y + (ch as Label).size.y / 2.0 - 35.0) < 20.0:
			s_hint += 1
		elif ch is RichTextLabel and (ch as RichTextLabel).has_meta("preview_truncated") and (ch as RichTextLabel).position.y < 60.0:
			s_text = (ch as RichTextLabel).get_parsed_text()
	_ok("★③ 一句写完的被动条: 全文显示、不加「…」、不挂「查看全部」", s_text == "登场后变得更加勇敢。" and s_hint == 0,
		"文字「%s」提示 %d" % [s_text, s_hint])
	_ok("③ 分母: 一行条 %d 条(截断 %d / 完整 %d)、卡片正文 %d 张、「技能」标题 %d 个" % [n_bar, n_cut, n_bar - n_cut, n_card, n_section],
		n_bar == 28 * 2 and n_cut > 0 and n_bar - n_cut > 0 and n_card >= 28 * 3 and n_section >= 28)
	_ok("★③ 一行条都只占一行、不藏字", bad_line.is_empty(), ", ".join(bad_line))
	_ok("★③ 截断以「…」收尾且截断处是原文前缀(没切进标签); 没截断的是全文", bad_prefix.is_empty(), "; ".join(bad_prefix.slice(0, 6)))
	_ok("★③「查看全部」只在一行条截断时出现(提示数 == 截断数)", bad_hint.is_empty(), ", ".join(bad_hint))
	_ok("★③ 预览不以纯小标题行开头", bad_head.is_empty(), ", ".join(bad_head))
	_ok("③ 点名: 海盗龟被动条从效果那句起(原来只有「登场轰击：」)", str(firsts.get("pirate#0", "")).begins_with("海盗龟登场"),
		"「%s」" % str(firsts.get("pirate#0", "")))
	_ok("③ 点名: 龟壳「暗影」卡从效果那句起(原来是「主被动·潜影：」)", str(firsts.get("shell/card2", "")).begins_with("龟壳"),
		"「%s」" % str(firsts.get("shell/card2", "")))
	_ok("★③ 被截的卡片, 可见的最后一行不是纯小标题", bad_tail.is_empty(), ", ".join(bad_tail))
	_ok("③ 点名: 石头龟「磐石之躯」卡不停在「被动：」", stone_rock != "" and not _is_heading(stone_rock), "最后一行「%s」" % stone_rock.strip_edges())
	_ok("★④ 卡片正文 / 一行条 / 「技能」标题字号 ≥ %d" % MIN_PX, bad_font.is_empty(), ", ".join(bad_font.slice(0, 6)))
	_ok("★④ 龟能签不越右缘、不撞「查看全部」", bad_collide.is_empty(), ", ".join(bad_collide.slice(0, 6)))
