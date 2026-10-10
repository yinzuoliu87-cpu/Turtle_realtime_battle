extends Node
## verify_codex_equip_star.gd — 图鉴装备页按云顶装备卡/技能卡重排 (2026-10-10)
##
## 用户 2026-10-10:「所以其实整个图鉴都有问题是吧，比如左轮手枪玩家看到的是什么东西，玩家觉得呢，
##   这有任何其他游戏是这样的吗」。左轮手枪(p2eq_052)那一页实拍的三个毛病, 每个一组判据:
##   ① 效果说两遍且对不上: 简述「造成 150/310/1200 点物理伤害」+ 全文「造成（150/310/1200+3/5/9×攻击力）物理伤害」
##      ⇒ 图鉴只留一段, 简述(effectBrief)不上屏。
##   ② 三档挤在一串里(「150/310/1200+3/5/9×攻击力」)靠三色 + 页底图例读
##      ⇒ 右上 ★1/★2/★3 选档, 正文只写选中那一档的数; 底下分档表一行一个量、三档并排。
##   ③ 羁绊只写「装满 3/6/9 件同类型装备」, 不说是哪个羁绊、每档给什么
##      ⇒ 写出羁绊名(图标 + 名字) + 逐档效果(Phase2Types.TIER_DESCS)。
##
## ★全部量【活场景里真画出来的字】(走真入口 _switch_tab → _select → 点签牌), 不 grep 源码。
## ★每条断言配分母: 选不到那件装备 / 一行文字都没抓到 = 空检查, 先红分母。

const CODEX_SCN := preload("res://scenes/Codex.tscn")
const EID := "p2eq_052"
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _c = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int = 4) -> void:
	for _i in range(n):
		await get_tree().process_frame


## BBCode 标记去掉, 只留玩家读到的字。
func _plain(t: String) -> String:
	return RegEx.create_from_string("[\\[][^\\]]*[\\]]").sub(t, "", true)


func _open(eid: String) -> bool:
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if it is Dictionary and str(it.get("id", "")) == eid:
			_c._select(i)
			await _settle(3)
			return true
	return false


## 详情里带某个 meta 的那个 RichTextLabel。
func _rtl_with(meta: String) -> RichTextLabel:
	for ch in _c.detail.get_children():
		if ch is RichTextLabel and not ch.is_queued_for_deletion() and ch.has_meta(meta):
			return ch
	return null


## 详情里全部 RichTextLabel / Label 的字(去标记)。
func _all_text() -> String:
	var acc: PackedStringArray = []
	for ch in _c.detail.get_children():
		if ch.is_queued_for_deletion():
			continue
		if ch is RichTextLabel:
			acc.append(_plain((ch as RichTextLabel).text))
		elif ch is Label:
			acc.append((ch as Label).text)
	return "\n".join(acc)


func _star_node(nm: String) -> Node:
	for ch in _c.detail.get_children():
		if not ch.is_queued_for_deletion() and str(ch.name) == nm:
			return ch
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 图鉴装备页: 一段效果 + 选档 + 分档表 + 羁绊名 ===")
	_c = CODEX_SCN.instantiate()
	add_child(_c)
	await _settle(8)
	_c._switch_tab("equips")
	await _settle(4)
	var found: bool = await _open(EID)
	_ok("★分母: 装备页里找得到 %s 左轮手枪(走真 _select)" % EID, found)
	if not found:
		_finish()
		return

	# ── ① 只有一段效果, 简述不上屏 ──────────────────────────────────────
	var eq: Dictionary = DataRegistry.phase2_equipment_by_id.get(EID, {})
	var brief_raw: String = SkillText.render_consts(str(eq.get("effectBrief", "")))
	var eff := _rtl_with("codex_eq_effect")
	_ok("★分母: 052 有简述(否则①是空检查)且效果段画出来了", brief_raw.length() > 8 and eff != null,
		"简述「%s」" % brief_raw)
	var shown := _all_text()
	_ok("★★★① 052 的简述「点物理伤害」那句不在页面上(只留一段效果)",
		shown.find("点物理伤害") < 0 and shown.find(_plain(brief_raw)) < 0,
		"页面字数 %d" % shown.length())
	## 全量: 每一件装备的简述都不上屏。分母 = 简述不是全文子串的那些件(是子串的话全文本来就含着它)。
	var n_brief := 0
	var leaked: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid2: String = str(e.get("id", ""))
		var b: String = SkillText.render_consts(str(e.get("effectBrief", ""))).strip_edges()
		if b == "" or SkillText.equip_full(e).find(b) >= 0:
			continue
		if not await _open(eid2):
			continue
		n_brief += 1
		if _all_text().find(b) >= 0:
			leaked.append(eid2)
	_ok("★分母: 量了 %d 件有独立简述的装备" % n_brief, n_brief >= 80)
	_ok("★★① 图鉴装备页一件都不再显示简述", leaked.is_empty(), "仍显示: %s" % str(leaked.slice(0, 6)))

	# ── ② 选档: ★1 与 ★3 正文的数不同, 走真点击 ──────────────────────────
	await _open(EID)
	_ok("★分母: 052 有 ★1/★2/★3 三块签牌", _star_node("EqStarHit1") != null and _star_node("EqStarHit3") != null)
	var t1: String = _plain(_rtl_with("codex_eq_effect").text)
	_ok("★★② ★1(默认)正文写「150+3×」, 不再是三档串", t1.find("150+3×") >= 0 and t1.find("150/310/1200") < 0,
		t1.substr(t1.find("造成"), 30))
	var hit3: Control = _star_node("EqStarHit3")
	if hit3 != null:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		hit3.gui_input.emit(ev)   # 与玩家点签牌同一条路(信号 → _set_eq_star → 重画)
		await _settle(3)
	var e3 := _rtl_with("codex_eq_effect")
	var t3: String = _plain(e3.text) if e3 != null else ""
	_ok("★★★② 点 ★3 后正文写「1200+9×」(数真的换了)", t3.find("1200+9×") >= 0 and t3.find("150+3×") < 0,
		t3.substr(maxi(0, t3.find("造成")), 30))
	_ok("★② ★1 与 ★3 正文不同", t1 != t3 and t3 != "")
	var srt := _rtl_with("codex_eq_stats")
	_ok("★② 属性一排也跟着换档(★3 攻击力 +500)", srt != null and _plain(srt.text).find("+500") >= 0,
		_plain(srt.text) if srt != null else "<无>")
	## 分档表: 一行一个量, 三档并排
	var tb := _rtl_with("codex_eq_tiers")
	var tbt: String = _plain(tb.text) if tb != null else ""
	_ok("★★② 分档表在, 且「150 / 310 / 1200」三档并排写出", tb != null and int(tb.get_meta("codex_eq_tiers")) >= 2
		and tbt.find("150 / 310 / 1200") >= 0 and tbt.find("3 / 5 / 9") >= 0, tbt.replace("\n", " | "))
	_ok("★② 当前档(★3)在分档表里是亮色", tb != null and tb.text.find("[color=%s]1200[/color]" % CodexDetail.TIER_HI) >= 0)
	## 全量: 每件会升星的装备, ★2 正文里不许再剩「a/b/c」三档串(拆分漏一处就是又一串乱码)
	var n_t := 0
	var left: Array = []
	for e in DataRegistry.phase2_equipment:
		var eid3: String = str(e.get("id", ""))
		if not await _open(eid3):
			continue
		var h2: Control = _star_node("EqStarHit2")
		if h2 == null:
			continue
		n_t += 1
		_c._codex_detail._set_eq_star(e, 2)
		await _settle(1)
		var et := _rtl_with("codex_eq_effect")
		if et != null and not CodexDetail.tier_matches(_plain(et.text)).is_empty():
			left.append(eid3)
	_ok("★分母: 有选档的装备 %d 件" % n_t, n_t >= 80)
	_ok("★★② 选了 ★2 之后正文里一个「a/b/c」都不剩", left.is_empty(), str(left.slice(0, 6)))
	## 不升星的 096 不给选档
	await _open("p2eq_096")
	_ok("★★② 096 小木斧(不升星)没有选档签牌", _star_node("EqStarHit1") == null and _rtl_with("codex_eq_effect") != null)

	# ── ③ 羁绊写出名字 + 逐档效果 ─────────────────────────────────────────
	await _open(EID)
	var tp: String = Phase2Types.type_of(EID)
	var head := _rtl_with("codex_eq_synergy")
	_ok("★分母: 052 有羁绊类型", tp != "", tp)
	_ok("★★★③ 羁绊那一块写出羁绊名「%s」" % tp, head != null and str(head.get_meta("codex_eq_synergy")) == tp
		and _plain(head.text).find(tp) >= 0)
	var tiers: Array = (Phase2Types.TYPES.get(tp, {}) as Dictionary).get("tiers", [])
	var page := _all_text()
	var miss: Array = []
	for i in range(tiers.size()):
		var first: String = SkillText.render_consts(Phase2Types.tier_desc(tp, i + 1)).substr(0, 10)
		if page.find("%d 件" % int(tiers[i])) < 0 or page.find(first) < 0:
			miss.append(int(tiers[i]))
	_ok("★★③ 每一档(%s 件)都写了给什么" % str(tiers), tiers.size() >= 2 and miss.is_empty(), "缺 %s" % str(miss))
	_ok("★③ 旧的笼统句「依次激活各档位效果」不在了", page.find("依次激活各档位效果") < 0)
	_finish()


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴装备页选档/一段效果/羁绊名")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
