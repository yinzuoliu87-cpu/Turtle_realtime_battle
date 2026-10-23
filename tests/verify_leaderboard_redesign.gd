extends Node
## verify_leaderboard_redesign — 排行榜重做的验收清单(2026-10-23)。
##
## 由来: 用户「排行榜需要大型重做」, 问他最在意哪条, 多选题只选了「看着像网页，没有游戏味」。
##   方案书 docs/plans/20261023-排行榜重做.md(§5 拍板: 三列不动 / 新增的只有头像 / 不加页签 / 不加个人卡)。
## 全部走**真场景实例 + 真节点**(读活节点的贴图 / 字号 / 对齐 / 染色), 不在源码里找字符串:
##   ① 头像 = 那一行的 `lead`(第一只统领): 服务端形状的行逐行对账 —— 头像贴图就是 avatars/<lead>.png;
##      没有 `lead` ⇒ 不编一只龟(头像槽里没贴图, 只写名字首字)
##   ② 本机那一路: 快照 leaders[0] → 头像; 自己那行 = GameState.season_leaders[0]
##   ③ 人少不画占位: 3 个人 ⇒ 列表恰 3 张行卡, 屏上没有「—」名字、没有第 4 名起的名次号
##   ④ 数字看得清: 三个成绩右对齐到列右沿、字号 ≥ 26 且大过名字、整个数放得下(不截断)
##   ⑤ 不是网页定宽栏: 面板宽 ≥ 设计框 90%(改前 760 = 59%), 两个比例下面板都在屏内
##   ⑥ 自己那张行卡是全屏最亮的一张(比每一张别人的卡都亮)
##   ⑦ 点别人名字的入口: 收得到点击(不是 IGNORE), 盖住头像和名字, 自己那行没有入口
##
## 跑法: TURTLE_SUPABASE=" " godot --headless --audio-driver Dummy --path . res://tests/verify_leaderboard_redesign.tscn --quit-after 500

const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const MC := preload("res://scripts/scenes/record/match_card.gd")
const PM := preload("res://scripts/scenes/social/player_menu.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

## 钉在周三(积分赛日, 本周榜; 周一看的是上周、自己那行画「—」)。
const PIN_WED := 1790553600 + 2 * 86400 + 12 * 3600
## 服务端形状的 6 行: 第 4 名故意不带 lead(老服务端 / 老快照的样子), 其余各是一只不同的龟。
const LEADS := ["stone", "ninja", "phoenix", "", "lava", "pirate"]
const NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将"]
const ME_LEAD := "ice"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	GameState.test_mode = true
	var ov0 := int(P2C.now_override_ts)
	var ld0 = GameState.season_leaders
	var w0 := int(GameState.season_wins)
	P2C.now_override_ts = PIN_WED
	GameState.season_leaders = [ME_LEAD, "stone", "basic"]
	GameState.season_wins = 2
	print("=== 排行榜重做: 头像 / 不画占位 / 大号数字 / 吃满宽 / 自己最亮 / 点名字 ===")
	await _t_server_shape()
	await _t_local()
	await _t_few()
	await _t_ratios()
	BE.pool_override = {}
	P2C.now_override_ts = ov0
	GameState.season_leaders = ld0
	GameState.season_wins = w0
	get_tree().root.size = Vector2i(1280, 720)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 排行榜重做" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _open() -> Node:
	var inst: Node = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(4):
		await get_tree().process_frame
	return inst


func _close(inst: Node) -> void:
	inst.queue_free()
	await get_tree().process_frame


## 服务端那一路回包解析之后的行形状(`SupabaseNet._week_lb_row` 的键 + 迁移后多下发的 `lead`)。
func _srv_rows(n: int) -> Array:
	var out := []
	for i in range(n):
		out.append({"rank": i + 1, "name": NAMES[i], "tag": P2C.player_tag("uid-rd-%d" % i), "account_id": "uid-rd-%d" % i,
			"wins": 12 - i, "hearts": 6 - (i % 3), "sweeps": 0, "battles": 14 + i, "title": "",
			"is_self": false, "lead": LEADS[i]})
	return out


## 列表里建着的行卡: 名次 → 行节点。
func _built(inst: Node) -> Dictionary:
	var out := {}
	var lst = inst.get("_list")
	if lst is Control:
		for ch in (lst as Control).get_children():
			if str(ch.name).begins_with("LbRow_") and not ch.is_queued_for_deletion():
				out[int(str(ch.name).substr(6))] = ch
	return out


## 一行里的头像件(MatchCard.avatar 打的 Portrait 标记)与它里面的贴图 / 首字。
func _avatar_of(row: Node) -> Dictionary:
	for ch in row.get_children():
		if ch.has_meta(MC.N_PORTRAIT):
			var r := {"pid": str(ch.get_meta(MC.N_PORTRAIT)), "tex": "", "letter": "", "node": ch}
			for g in ch.get_children():
				if g is TextureRect and (g as TextureRect).texture != null:
					r["tex"] = str((g as TextureRect).texture.resource_path)
				elif g is Label:
					r["letter"] = str((g as Label).text)
			return r
	return {}


func _label_at_x(row: Node, x: float) -> Label:
	for ch in row.get_children():
		if ch is Label and absf((ch as Label).position.x - x) < 0.5:
			return ch as Label
	return null


func _card_of(row: Node) -> Panel:
	for ch in row.get_children():
		if ch is Panel and (ch as Panel).size.x > LB.PANEL_W * 0.8:
			return ch as Panel
	return null


func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


# ─────────────────────────────────────────────────────────────
# ①④⑥⑦ 服务端形状的 6 行 + 钉住的我
# ─────────────────────────────────────────────────────────────
func _t_server_shape() -> void:
	print("── ① 服务端形状的行(带 lead) ──")
	BE.pool_override = {BE.POOL_KEY: {}}
	var inst := await _open()
	var me := {"rank": 9, "name": "我自己龟", "tag": BE.my_tag(), "account_id": "uid-rd-me", "wins": 2, "hearts": 3,
		"sweeps": 0, "battles": 11, "title": "", "is_self": true, "lead": ME_LEAD}
	inst.call("_render", _srv_rows(6), LB.SRC_SERVER, 6, me, 6)
	await get_tree().process_frame
	var b := _built(inst)
	_ok("① ★分母: 列表建出了 6 张行卡", b.size() == 6, str(b.keys()))
	var bad: Array = []
	var n_tex := 0
	for i in range(6):
		var row: Node = b.get(i + 1, null)
		if row == null:
			bad.append("第%d名 没建" % (i + 1))
			continue
		var av := _avatar_of(row)
		var want: String = LEADS[i]
		if av.is_empty():
			bad.append("第%d名 没头像件" % (i + 1))
		elif want != "":
			n_tex += 1
			if str(av["tex"]) != "res://assets/sprites/avatars/%s.png" % want or str(av["pid"]) != want:
				bad.append("第%d名 头像 %s ≠ %s" % [i + 1, str(av["tex"]), want])
		else:
			## 没 lead ⇒ 不编一只龟: 槽里没有贴图, 写名字首字。
			if str(av["tex"]) != "" or str(av["letter"]) != str(NAMES[i]).substr(0, 1):
				bad.append("第%d名(没 lead) 贴图「%s」首字「%s」" % [i + 1, str(av["tex"]), str(av["letter"])])
	_ok("① ★分母: 带 lead 的 5 行都画出了龟头像", n_tex == 5, "%d 张" % n_tex)
	_ok("① ★★每一行的头像 = 它自己的 lead(avatars/<lead>.png); 没 lead 的那行不编龟、写名字首字", bad.is_empty(),
		str(bad.slice(0, 3)))
	var pav := _avatar_of(inst.get("_pin") as Node)
	_ok("① 钉住的我: 头像 = 我的 lead(%s)" % ME_LEAD,
		str(pav.get("tex", "")) == "res://assets/sprites/avatars/%s.png" % ME_LEAD, str(pav.get("tex", "")))
	## 头像不进成绩列(用户「排行榜里的奖杯是？」: 成绩格里不画图标)。
	var into: Array = []
	for rk in b.keys():
		var av2 := _avatar_of(b[rk])
		if not av2.is_empty() and (av2["node"] as Control).get_global_rect().end.x \
				> (inst.get("_panel") as Control).get_global_rect().position.x + LB.STAT_X0:
			into.append(rk)
	_ok("① 头像整个落在成绩列左边", into.is_empty(), str(into))

	## ── ④ 数字看得清 ──
	print("── ④ 三个成绩: 右对齐 / 大号 / 放得下 ──")
	var nbad: Array = []
	var seen := 0
	for rk in b.keys():
		var row: Node = b[rk]
		var nm := _label_at_x(row, LB.NAME_X)
		var name_fs: int = nm.get_theme_font_size("font_size") if nm != null else 99
		for ci in range(3):
			var l := _label_at_x(row, LB.STAT_X0 + float(ci) * LB.STAT_CELL)
			if l == null:
				nbad.append("第%d名 第%d列 没有数字格" % [int(rk), ci])
				continue
			seen += 1
			var fs: int = l.get_theme_font_size("font_size")
			var f: Font = l.get_theme_font("font")
			var tw: float = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if f != null else 1e9
			if l.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT:
				nbad.append("第%d名 第%d列 不是右对齐" % [int(rk), ci])
			if fs < 26 or fs <= name_fs:
				nbad.append("第%d名 第%d列 字号 %d(名字 %d)" % [int(rk), ci, fs, name_fs])
			if tw > l.size.x or l.clip_text:
				nbad.append("第%d名 第%d列 「%s」放不下(%.0f > %.0f)" % [int(rk), ci, l.text, tw, l.size.x])
	_ok("④ ★分母: 量到 6 行 × 3 列 = 18 个数字格", seen == 18, "%d 格" % seen)
	_ok("④ ★★每个成绩数: 右对齐到列右沿 / 字号 ≥ 26 且大过名字 / 整个放得下", nbad.is_empty(), str(nbad.slice(0, 3)))

	## ── ⑥ 自己最亮 ──
	print("── ⑥ 自己那张行卡全屏最亮 ──")
	var pin_card := _card_of(inst.get("_pin") as Node)
	var self_l: float = -1.0
	if pin_card != null and pin_card.get_theme_stylebox("panel") is StyleBoxTexture:
		self_l = _lum((pin_card.get_theme_stylebox("panel") as StyleBoxTexture).modulate_color)
	var lums: Array = []
	for rk in b.keys():
		var cd := _card_of(b[rk])
		if cd != null and cd.get_theme_stylebox("panel") is StyleBoxTexture:
			lums.append(_lum((cd.get_theme_stylebox("panel") as StyleBoxTexture).modulate_color))
	_ok("⑥ ★分母: 6 张别人的行卡 + 钉住那张都取到了染色(贴图在, 不是兜底纯色)", lums.size() == 6 and self_l > 0.0,
		"%d 张 / 我 %.2f" % [lums.size(), self_l])
	var brighter := lums.filter(func(v): return float(v) >= self_l)
	_ok("⑥ ★★自己那张比每一张别人的卡都亮(含金牌那张)", brighter.is_empty() and lums.size() == 6,
		"我 %.2f / 别人 %s" % [self_l, str(lums)])

	## ── ⑦ 点名字 ──
	print("── ⑦ 点别人的名字 ──")
	var entries: Array = []
	var dead: Array = []
	var miss: Array = []
	for rk in b.keys():
		var row: Node = b[rk]
		var es: Array = row.find_children(PM.ENTRY, "Button", true, false)
		if es.size() != 1:
			miss.append("第%d名 入口 %d 个" % [int(rk), es.size()])
			continue
		var e := es[0] as Button
		entries.append(e)
		if e.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			dead.append(int(rk))
		var nm2 := _label_at_x(row, LB.NAME_X)
		var av3 := _avatar_of(row)
		var er: Rect2 = e.get_global_rect()
		if nm2 == null or av3.is_empty() or not er.has_point(nm2.get_global_rect().get_center()) \
				or not er.has_point((av3["node"] as Control).get_global_rect().get_center()):
			miss.append("第%d名 入口没盖住头像 + 名字" % int(rk))
	_ok("⑦ ★分母: 6 个别人各一颗入口", entries.size() == 6, str(miss.slice(0, 3)))
	_ok("⑦ ★★入口收得到点击(不是 IGNORE)", dead.is_empty() and entries.size() == 6, str(dead))
	_ok("⑦ 入口盖住头像和名字(整张卡高)", miss.is_empty(), str(miss.slice(0, 3)))
	_ok("⑦ 钉住的我那行没有入口(不举报自己)",
		(inst.get("_pin") as Node).find_children(PM.ENTRY, "Button", true, false).is_empty())
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ② 本机那一路: 快照 leaders[0] → 头像
# ─────────────────────────────────────────────────────────────
func _t_local() -> void:
	print("── ② 本机那一路: 快照 leaders[0] ──")
	var pool: Dictionary = {BE.POOL_KEY: {}}
	var leads := ["mech", "bamboo", "lightning"]
	for i in range(3):
		BE.pool_add(pool, {"schema_ver": BE.SCHEMA_VER, "ghost_id": "lbrd_%d" % i, "is_bot": false,
			"origin": BE.ORIGIN_REMOTE, "profile": {"name": "本机龟%d" % i},
			"leaders": [leads[i], "basic", "ice"],
			"season_wins": 9 - i, "hearts": 4, "season_sweeps": 0, "season_total_battles": 12})
	BE.pool_override = pool
	var inst := await _open()
	_ok("② ★分母: 画的是本机那一路", str(inst.get("source")) == LB.SRC_LOCAL, str(inst.get("source")))
	var got := {}
	for rk in _built(inst).keys():
		var row: Node = _built(inst)[rk]
		var nm := _label_at_x(row, LB.NAME_X)
		var av := _avatar_of(row)
		if nm != null and not av.is_empty():
			got[str(nm.text)] = str(av["tex"]).get_file().get_basename()
	var want := {"本机龟0": "mech", "本机龟1": "bamboo", "本机龟2": "lightning", BE.player_display_name(): ME_LEAD}
	_ok("② ★★每个人的头像 = 他快照的 leaders[0]; 我 = 本周阵容第一只(%s)" % ME_LEAD, got == want,
		"屏上 %s" % str(got))
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ③ 人少不画占位
# ─────────────────────────────────────────────────────────────
func _t_few() -> void:
	print("── ③ 3 个人: 只画 3 张卡 ──")
	BE.pool_override = {BE.POOL_KEY: {}}
	var inst := await _open()
	var rows := _srv_rows(3)
	rows[1] = (rows[1] as Dictionary).merged({"is_self": true, "name": "我自己龟", "lead": ME_LEAD}, true)
	inst.call("_render", rows, LB.SRC_SERVER, 3, {}, 3)
	await get_tree().process_frame
	var b := _built(inst)
	var ks: Array = b.keys()
	ks.sort()
	_ok("③ ★★3 个人 ⇒ 列表恰好 3 张行卡(第 1~3 名), 一张占位都没有", ks == [1, 2, 3], str(ks))
	var texts: Array = []
	var stk: Array = [inst.get("_list")]
	while not stk.is_empty():
		var nd = stk.pop_back()
		if nd is Label:
			texts.append(str((nd as Label).text))
		stk.append_array((nd as Node).get_children())
	_ok("③ ★分母: 列表里真有字(3 张卡的名字 / 名次 / 成绩)", texts.size() >= 12, "%d 段" % texts.size())
	var ph: Array = texts.filter(func(t): return str(t) == "—")
	_ok("③ ★★列表里没有「—」占位", ph.is_empty(), str(ph))
	var rank_bad: Array = []
	for rk in b.keys():
		var rl := _label_at_x(b[rk], LB.RANK_X)
		if rl != null and int(rl.text) >= 4:
			rank_bad.append(rl.text)
	_ok("③ 没有第 4 名起的名次号(原来空席照画名次 4~10)", rank_bad.is_empty(), str(rank_bad))
	var lst := inst.get("_list") as Control
	_ok("③ 列表长度 = 3 张卡那么高(不再按一屏撑开)", lst != null
		and absf(lst.custom_minimum_size.y - 3.0 * LB.ROW_H) < 0.5, str(lst.custom_minimum_size) if lst != null else "")
	await _close(inst)


# ─────────────────────────────────────────────────────────────
# ⑤ 宽度: 不是网页定宽栏
# ─────────────────────────────────────────────────────────────
func _t_ratios() -> void:
	BE.pool_override = {BE.POOL_KEY: {}}
	for sz in [Vector2i(1280, 720), Vector2i(1560, 720)]:
		print("── ⑤ 视口 %dx%d ──" % [sz.x, sz.y])
		get_tree().root.size = sz
		await get_tree().process_frame
		var inst := await _open()
		var vp := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
		var pr: Rect2 = (inst.get("_panel") as Control).get_global_rect()
		_ok("⑤[%dx%d] ★分母: 视口真的是这个尺寸" % [sz.x, sz.y], absf(vp.size.x - float(sz.x)) < 1.5, str(vp.size))
		_ok("⑤[%dx%d] ★★面板宽 ≥ 设计框的 90%%(改前 760 = 59%%, 两边各空一大块 = 网页定宽栏)" % [sz.x, sz.y],
			pr.size.x >= 1280.0 * 0.9, "%.0f" % pr.size.x)
		_ok("⑤[%dx%d] 面板整个在屏内、左右留白对称(≤2px)" % [sz.x, sz.y], vp.grow(0.5).encloses(pr)
			and absf(pr.position.x - (vp.size.x - pr.end.x)) <= 2.0, str(pr))
		await _close(inst)
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
