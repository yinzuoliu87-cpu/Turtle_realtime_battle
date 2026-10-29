extends Node
## verify_reserve_minion_ui.gd —— 援军小将在图鉴与战斗界面上的样子(2026-10-29, 方案书 docs/plans/20261029-终极战场援军小将.md C 组)。
## 机制本身(谁上场 / 属性 / 技能伤害)在 verify_reserve_minion.gd; 这里量的是**玩家看到的字和图**:
##   ① 图鉴: 小将列表里有援军小将一行; 详情页名字 / 签牌(援军 · 不可编入 · 每场 +4%) / 七格属性 / 「主动 · 龟能 135」/
##      技能卡「四面合围」/ 被动条「援军」(出场条件 + 每场成长)都在, 文案里 {C:} 全展开、数字 == ReserveConsts;
##      签牌不出左栏、定高富文本没有被切成半截的行(排版不挤)。
##   ② 图鉴数值 == 真生成的援军小将(0 场): 血 / 攻 / 双抗 / 射程 / 攻击间隔 / 龟能。
##   ③ 战斗信息面板: 技能格取到「四面合围」+ 135 + 同一段文案(单一来源); 站位格「后排」; 面板上写着「援军小将」。
##   ④ 终极战场对阵幕布(真入口 _dl_build_present_overlay, 名单为空的那一方): 卡片上写「援军小将」、头像取援军立绘;
##      对照: 普通小将 / 精英小将的卡名不变。
##   ⑤ 结算表(真行 _st_row → SettleScreen.avatar)、⑥ 顶栏(真 portrait_candidates → _refresh_portrait)、
##      ⑦ 左右队头像框(_make_team_frame): 认得出援军小将、头像取援军立绘。
## ★援军立绘(pets/minion-reserve.png)美术还没交时, ④~⑦ 的头像按回落路径量(通用小将图 / 战场立绘首帧),
##   并打一行「立绘未交付」—— 交了之后同一条断言自动改量援军立绘, 不用改本文件。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_reserve_minion_ui.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SS := preload("res://scripts/scenes/battle/settle_screen.gd")
const TOP := preload("res://scripts/scenes/battle/topbar_status.gd")
const CODEX := preload("res://scenes/Codex.tscn")
const BATTLES := 5

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


static func _pct(v: float) -> String:
	return str(int(roundf(v * 100.0)))


## 一棵节点树里所有 Label / RichTextLabel 的字。
func _texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Label:
			out.append(str((n as Label).text))
		elif n is RichTextLabel:
			out.append((n as RichTextLabel).get_parsed_text())
		for ch in n.get_children():
			st.append(ch)
	return out


func _tex_paths(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var st: Array = [root]
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is TextureRect and (n as TextureRect).texture != null:
			out.append(str((n as TextureRect).texture.resource_path))
		for ch in n.get_children():
			st.append(ch)
	return out


## 贴图身份: 文件路径; 帧表裁出来的单帧(AtlasTexture, 自己没有路径)认它的底图 + 裁框。
static func _tex_id(t: Texture2D) -> String:
	if t == null:
		return "null"
	if t is AtlasTexture:
		var at := t as AtlasTexture
		return "%s@%s" % [str(at.atlas.resource_path) if at.atlas != null else "?", str(at.region)]
	return str(t.resource_path)


## 定高(非 fit_content)富文本里跨过下边缘的半截行数(与 verify_codex_beta_layout G 同一把尺)。
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _settle(2)
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_ok("GameState 在", false)
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 援军小将: 图鉴与战斗界面 ===")
	var art: String = MinionCodex.portrait_path("reserve")
	if art == "":
		print("  ⚠ 援军立绘 pets/minion-reserve.png 未交付 —— 头像断言按回落路径量; 交付后自动改量援军立绘")
	_pure()
	await _codex(art)
	await _battle(gs, art)
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n >= 40:
		print("ALL PASS — 援军小将图鉴与战斗界面")
	elif _n < 40:
		print("FAIL — 分母过小(%d 条), 有一段没跑到" % _n)
	get_tree().quit(1 if (_fail > 0 or _n < 40) else 0)


## 认种类 / 文案展开 —— 纯函数。
func _pure() -> void:
	print("-- 纯函数 --")
	_ok("认种类: 单位字典 minion_role=reserve ⇒ reserve", MinionCodex.kind_of({"minion_role": "reserve", "is_elite": false}) == "reserve")
	_ok("认种类: 阵容 spec role=reserve ⇒ reserve", MinionCodex.kind_of({"kind": "minion", "role": "reserve"}) == "reserve")
	_ok("认种类(对照): back / front / elite 不变", MinionCodex.kind_of({"role": "back"}) == "back"
		and MinionCodex.kind_of({"minion_role": "front"}) == "front" and MinionCodex.kind_of({"role": "front", "elite": true}) == "elite")
	_ok("结算快照行(只有 id + 名字)认得出援军小将", MinionCodex.is_reserve({"id": "__minion__", "name": ReserveConsts.NAME}))
	_ok("结算快照行(对照): 普通小将 / 精英小将不是援军", not MinionCodex.is_reserve({"id": "__minion__", "name": "小将"})
		and not MinionCodex.is_reserve({"id": "__minion__", "name": "精英小将"}))
	var kinds: Array = []
	for mk in MinionCodex.MINION_KINDS:
		kinds.append(str(mk["kind"]))
	_ok("★图鉴小将种类表里有援军小将(MINION_KINDS)", kinds.has("reserve"), str(kinds))
	_ok("技能 type ⇒ 种类(TYPE_TO_KIND)", str(MinionCodex.TYPE_TO_KIND.get(ReserveConsts.SKILL, "")) == "reserve")
	var mi: Dictionary = MinionCodex.info("reserve")
	_ok("分母: info(reserve) 取得到", not mi.is_empty())
	var desc := str(mi.get("skill_desc", ""))
	var pv: Array = mi.get("passives", [])
	var pdesc: String = str((pv[0] as Dictionary).get("desc", "")) if not pv.is_empty() else ""
	_ok("★文案里 {C:} 全展开(技能 / 被动 / 签牌)", desc != "" and pdesc != "" and (desc + pdesc + str(mi.get("growth_tag", ""))).find("{") < 0,
		desc.substr(0, 30))
	_ok("★技能文案: %s%% 攻击力物理 == ReserveConsts.ATK_COEF" % _pct(ReserveConsts.ATK_COEF),
		desc.find("%s%% 攻击力的物理伤害" % _pct(ReserveConsts.ATK_COEF)) >= 0, desc)
	_ok("★技能文案: 该敌人 %s%% 最大生命值魔法 == ReserveConsts.MAXHP_PCT(写明是谁的生命值)" % _pct(ReserveConsts.MAXHP_PCT),
		desc.find("该敌人 %s%% 最大生命值的魔法伤害" % _pct(ReserveConsts.MAXHP_PCT)) >= 0)
	_ok("技能文案: 前后左右 / 同时追向该敌人(追踪) / 命中的第一个敌人", desc.find("前后左右") >= 0 and desc.find("同时追向该敌人") >= 0 and desc.find("命中的第一个敌人") >= 0)
	_ok("★被动「援军」: 出场条件(终极战场 · 没有任何幸存单位)", pdesc.find("终极战场") >= 0 and pdesc.find("没有任何幸存单位") >= 0, pdesc.substr(0, 30))
	_ok("★被动「援军」: 每场 +%s%% == ReserveConsts.GROWTH_PER_BATTLE" % _pct(ReserveConsts.GROWTH_PER_BATTLE),
		pdesc.find("每进行一场对局") >= 0 and pdesc.find("提升 %s%%" % _pct(ReserveConsts.GROWTH_PER_BATTLE)) >= 0)
	_ok("签牌 = 「每场 +%s%%」" % _pct(ReserveConsts.GROWTH_PER_BATTLE), str(mi.get("growth_tag", "")) == "每场 +%s%%" % _pct(ReserveConsts.GROWTH_PER_BATTLE),
		str(mi.get("growth_tag", "")))
	var sd = MinionCodex.skill_desc(ReserveConsts.SKILL)
	_ok("★单一来源: 战斗取到的文案 == 图鉴那一段", sd is Dictionary and str((sd as Dictionary).get("desc", "")) == desc
		and str((sd as Dictionary).get("name", "")) == ReserveConsts.SKILL_NAME)
	var raw_ic := str((MinionCodex.MINION_INFO["reserve"] as Dictionary).get("skill_icon", ""))
	_ok("技能图标: 文件在才给路径, 不在给空串(不去 load 不存在的图)",
		str(mi.get("skill_icon", "")) == (raw_ic if ResourceLoader.exists("res://assets/sprites/" + raw_ic) else ""), raw_ic)


## ① 图鉴
func _codex(art: String) -> void:
	print("-- ① 图鉴 --")
	var c = CODEX.instantiate()
	add_child(c)
	await _settle(10)
	c._switch_tab("pets")
	await _settle(4)
	var idx := -1
	for i in range(c._items.size()):
		var it = c._items[i]
		if it is Dictionary and str((it as Dictionary).get("_minion", "")) == "reserve":
			idx = i
	_ok("★图鉴龟页签的小将组里有援军小将", idx >= 0)
	_ok("列表行写着「援军小将」", _texts(c.list_vbox).has(ReserveConsts.NAME))
	if idx < 0:
		c.queue_free()
		return
	c._codex_skill_detail = {}
	c._codex_passive_view = false
	c._codex_form_view = false
	c._select(idx)
	await _settle(6)
	var labels: PackedStringArray = []
	for ch in c.detail.get_children():
		if ch is Label:
			labels.append(str((ch as Label).text))
	_ok("详情页名字「援军小将」", labels.has(ReserveConsts.NAME), str(labels))
	if art != "":
		_ok("详情页立绘 = 援军立绘", _tex_paths(c.detail).has(art))
		_ok("列表行图标 = 援军立绘", _tex_paths(c.list_vbox).has(art))
	_ok("★签牌: 援军 / 不可编入 / 每场 +%s%%(不是「每级 ×1.05」)" % _pct(ReserveConsts.GROWTH_PER_BATTLE),
		labels.has("援军") and labels.has("不可编入") and labels.has("每场 +%s%%" % _pct(ReserveConsts.GROWTH_PER_BATTLE)) and not labels.has("每级 ×1.05"))
	var stat_ok := true
	var want := {"hp": ReserveConsts.HP, "atk": ReserveConsts.ATK, "def": ReserveConsts.DEF, "mr": ReserveConsts.MR,
		"move": ReserveConsts.MOVE, "range": ReserveConsts.RANGE}
	var seen := {}
	for ch in c.detail.get_children():
		if ch is Label and (ch as Label).has_meta("stat_num"):
			seen[str((ch as Label).get_meta("stat_num"))] = str((ch as Label).text)
	for k in want:
		if str(seen.get(k, "")) != str(int(want[k])):
			stat_ok = false
	_ok("★属性 7 格 == ReserveConsts(0 场底子, 整数不带 .0)", stat_ok and seen.has("aspd")
		and str(seen.get("aspd", "")) == "%.2f" % (1.0 / ReserveConsts.ATK_INTERVAL), str(seen))
	_ok("技能抬头「主动 · 龟能 %d」" % int(ReserveConsts.ENERGY), labels.has("主动 · 龟能 %d" % int(ReserveConsts.ENERGY)), str(labels))
	var all_txt := " ".join(_texts(c.detail))
	_ok("技能卡「%s」" % ReserveConsts.SKILL_NAME, all_txt.find(ReserveConsts.SKILL_NAME) >= 0)
	var pbar: Node = null
	for ch in c.detail.get_children():
		if str(ch.name) == "PassiveBar":
			pbar = ch
	_ok("被动条「援军」在(出场条件写在这里)", pbar != null and all_txt.find("援军") >= 0)
	_ok("详情页没有 {C:} 残留", all_txt.find("{C:") < 0)
	## 排版: 签牌不出左栏; 定高富文本没有被切成半截的行
	var lcol: float = float(c._codex_detail.LCOL_W)
	var over: PackedStringArray = []
	for ch in c.detail.get_children():
		if ch is Label and str((ch as Label).text) in ["援军", "不可编入", "每场 +%s%%" % _pct(ReserveConsts.GROWTH_PER_BATTLE), ReserveConsts.NAME]:
			var r: float = (ch as Label).position.x + (ch as Label).size.x
			if r > lcol + 0.5:
				over.append("%s 右缘 %.0f" % [(ch as Label).text, r])
	_ok("★名字与签牌都在左栏里(右缘 ≤ %.0f)" % lcol, over.is_empty(), ", ".join(over))
	var n_rt := 0
	var partial: PackedStringArray = []
	for ch in c.detail.get_children():
		if ch is RichTextLabel and not (ch as RichTextLabel).fit_content:
			n_rt += 1
			if _partial_lines(ch as RichTextLabel) > 0:
				partial.append((ch as RichTextLabel).get_parsed_text().substr(0, 12))
	_ok("定高富文本没有半截行(分母 %d 段)" % n_rt, n_rt > 0 and partial.is_empty(), ", ".join(partial))
	c.queue_free()
	await _settle(2)


## ②~⑦ 战斗
func _battle(gs, art: String) -> void:
	print("-- ②~⑦ 战斗界面 --")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await _settle(3)
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	## ② 图鉴数值 == 真生成的援军小将(0 场)
	var u0: Dictionary = s._spawn._make_unit("__minion__", "left", c, {"minion": true, "role": "reserve", "battles": 0})
	var mi: Dictionary = MinionCodex.info("reserve")
	var rows := [["生命", float(mi["hp"]), float(u0["maxHp"])], ["攻击", float(mi["atk"]), float(u0["atk"])],
		["护甲", float(mi["def"]), float(u0["def"])], ["魔抗", float(mi["mr"]), float(u0["mr"])],
		["射程", float(mi["range"]), float(u0["atk_range"])], ["攻击间隔", float(mi["interval"]), float(u0["atk_interval"])],
		["龟能", float(mi["skill_cost"]), float((u0.get("energy_cost", {}) as Dictionary).get(ReserveConsts.SKILL, -1.0))]]
	for r in rows:
		_ok("② 图鉴 %s %.2f == 战斗 %.2f" % [r[0], r[1], r[2]], absf(float(r[1]) - float(r[2])) < 0.006)

	## 调试场(开发工具): 「援军」笔刷在笔刷栏里, 摆出来的是援军小将、按玩家本周场数成长; 存盘重建也还是它
	var has_brush := false
	for pair in s._edit_brush_cells:
		if str(pair[1]) == "__minion__:reserve":
			has_brush = true
	_ok("调试场笔刷栏有「援军」(分母: 笔刷 %d 格)" % s._edit_brush_cells.size(), has_brush and s._edit_brush_cells.size() > 28)
	var n_b0: int = int(gs.season_total_battles)
	gs.season_total_battles = 7
	s._debug._edit_set_brush("__minion__:reserve")
	var pu: Dictionary = s._debug._edit_place_unit("__minion__", "left", c + Vector2(-200, 0))
	_ok("调试场摆出援军小将, 属性按本周 7 场(×1.28)", MinionCodex.is_reserve(pu)
		and absf(float(pu["maxHp"]) - float(ReserveConsts.base_stats(7)["hp"])) < 0.01, "%s %.1f" % [str(pu.get("name")), float(pu.get("maxHp", 0))])
	var ru: Dictionary = s._debug._edit_unit_from_setup({"minion": true, "role": "reserve", "side": "left", "pos": c, "level": 1, "hp": 500.0})
	_ok("调试场存盘重建仍是援军小将", MinionCodex.is_reserve(ru) and str(ru.get("_edit_minion_role", "")) == "reserve")
	gs.season_total_battles = n_b0
	s._units = s._units.filter(func(x): return not is_same(x, pu))
	## 单位字典上的 level = 这一侧的大轮等级(_make_unit 统一写) —— 对援军属性毫无影响, 界面上不该写出来。
	var u: Dictionary = s._spawn._make_unit("__minion__", "right", c + Vector2(200, 0), {"minion": true, "role": "reserve", "battles": BATTLES})
	var lv_u: int = int(u.get("level", 1))
	_ok("分母: 造出来的是援军小将", MinionCodex.is_reserve(u) and str(u.get("name", "")) == ReserveConsts.NAME, str(u.get("name")))
	s._units.append(u)

	## ③ 信息面板
	var ent: Array = s._info_sys._skill_bar_entries(u)
	var e0: Dictionary = ent[0] if not ent.is_empty() else {}
	_ok("③ 技能格「%s」· %d 龟能" % [ReserveConsts.SKILL_NAME, int(ReserveConsts.ENERGY)], ent.size() == 1
		and str(e0.get("name", "")) == ReserveConsts.SKILL_NAME and absf(float(e0.get("cost", -1.0)) - ReserveConsts.ENERGY) < 0.01, str(ent))
	_ok("③ 技能格正文 == 图鉴同一段(单一来源)", str(e0.get("desc", "")) == str(mi["skill_desc"]))
	s._hud._show_unit_info_panel(u)
	await _settle(2)
	var ip_txt: PackedStringArray = _texts(s._info_panel) if s._info_panel != null else PackedStringArray()
	_ok("③ 面板写着「援军小将」", ip_txt.has(ReserveConsts.NAME), str(ip_txt).substr(0, 120))
	_ok("③ 站位格「后排」(远程, 不是前排)", ip_txt.has("后排") and not ip_txt.has("前排"))
	var sub_lv := false
	for t in ip_txt:
		if t.find("Lv %d" % lv_u) >= 0:
			sub_lv = true
	_ok("③ 副标题不写等级(援军按场数成长, 等级对它无效)", not sub_lv and (ip_txt.has("敌方 · C") or ip_txt.has("友军 · C")), str(ip_txt).substr(0, 80))
	var ip_tex: PackedStringArray = _tex_paths(s._info_panel) if s._info_panel != null else PackedStringArray()
	if art != "":
		_ok("③ 面板头像 = 援军立绘", ip_tex.has(art), str(ip_tex))
	s._hud._close_info_panel()

	## ④ 终极战场对阵幕布(真入口): 两边名单都为空 ⇒ 两边各一只援军小将
	var lane0: String = str(gs.current_lane)
	var surv0 = gs.dual_survivors.duplicate(true) if gs.dual_survivors is Dictionary else {}
	gs.current_lane = "final"
	gs.dual_survivors = {"left": [], "right": [{"kind": "minion", "role": "front", "elite": false, "hp_frac": 0.5},
		{"kind": "minion", "role": "back", "elite": true, "hp_frac": 0.5}]}
	s._dl_sys._dl_build_present_overlay("preview")
	await _settle(2)
	var root: Node = s._dl_present_root
	var cur_txt: PackedStringArray = _texts(root) if root != null else PackedStringArray()
	var cur_tex: PackedStringArray = _tex_paths(root) if root != null else PackedStringArray()
	_ok("分母: 幕布建出来了", root != null and cur_txt.size() > 3, str(cur_txt.size()))
	_ok("★④ 我方名单为空 ⇒ 幕布卡片写「援军小将」", cur_txt.has(ReserveConsts.NAME), str(cur_txt))
	_ok("④ 对照: 对方幸存的普通 / 精英小将卡名不变", cur_txt.has("小将") and cur_txt.has("精英小将"))
	var want_cur: String = art if art != "" else s.SPRITE_DIR + "pets/minion.png"
	_ok("★④ 援军卡头像 = %s" % ("援军立绘" if art != "" else "回落: 通用小将图"), cur_tex.has(want_cur), str(cur_tex))
	_ok("④ 名字函数: 援军 / 普通 / 精英", s._dl_sys._dl_spec_name({"kind": "minion", "role": "reserve"}) == ReserveConsts.NAME
		and s._dl_sys._dl_spec_name({"kind": "minion", "role": "back"}) == "小将"
		and s._dl_sys._dl_spec_name({"kind": "minion", "role": "front", "elite": true}) == "精英小将")
	s._dl_sys._dl_clear_present_overlay()
	gs.current_lane = lane0
	gs.dual_survivors = surv0

	## ⑤ 结算表: 真行 → 头像
	var row: Dictionary = s._st_row(u)
	_ok("⑤ 结算行认得出援军小将(行里只有 id + 名字)", MinionCodex.is_reserve(row), "%s / %s" % [str(row.get("id")), str(row.get("name"))])
	var av: TextureRect = SS.avatar(row, 48.0)
	var av_p: String = str(av.texture.resource_path) if av.texture != null else ""
	_ok("★⑤ 结算头像 = %s" % ("援军立绘" if art != "" else "回落: 通用小将图"), av_p == want_cur, av_p)
	av.free()

	## ⑥ 顶栏: 这一边只剩援军小将 ⇒ 候选里有它、头像取它
	var tb = TOP.new(s._hud)
	var cands: Array = tb.portrait_candidates("right")
	_ok("⑥ 顶栏候选 = 这只援军小将", cands.size() == 1 and is_same(cands[0], u), str(cands.size()))
	var tr := TextureRect.new()
	tb._refresh_portrait("right", tr)
	var want_top: Texture2D = load(art) if art != "" else s._unit_portrait_texture(u)
	_ok("★⑥ 顶栏头像 = %s" % ("援军立绘" if art != "" else "回落: 原取图链(战场立绘首帧)"),
		_tex_id(tr.texture) == _tex_id(want_top) and (art == "" or _tex_id(tr.texture) == art), "%s / 应 %s" % [_tex_id(tr.texture), _tex_id(want_top)])
	tr.free()

	## ⑦ 左右队头像框
	var fr: Control = s._hud._make_team_frame(u)
	var fr_txt := _texts(fr)
	var fr_tex := _tex_paths(fr)
	_ok("⑦ 头像框写着「援军小将」", fr_txt.has(ReserveConsts.NAME), str(fr_txt))
	var ctl: Dictionary = s._spawn._make_unit("__minion__", "right", c + Vector2(300, 0), {"minion": true, "role": "back"})
	var fr_c: Control = s._hud._make_team_frame(ctl)
	var ctl_txt := _texts(fr_c)
	fr_c.free()
	_ok("⑦ 头像框不挂等级牌(对照: 同一侧远程小将挂着「%d」)" % int(ctl.get("level", 1)),
		not fr_txt.has(str(lv_u)) and ctl_txt.has(str(int(ctl.get("level", 1)))), "%s / 对照 %s" % [fr_txt, ctl_txt])
	if art != "":
		_ok("★⑦ 头像框头像 = 援军立绘", fr_tex.has(art), str(fr_tex))
	else:
		_ok("⑦ 立绘未交付 ⇒ 头像框走原取图链", _tex_id(s._hud.unit_portrait(u)) == _tex_id(s._unit_portrait_texture(u)), _tex_id(s._unit_portrait_texture(u)))
	fr.free()
	## 单位字典不能拿 == / erase 比(CLAUDE.md §3.2: 递归哈希成环) ⇒ 按 is_same 滤掉
	s._units = s._units.filter(func(x): return not is_same(x, u))
	s.queue_free()
	await _settle(2)
