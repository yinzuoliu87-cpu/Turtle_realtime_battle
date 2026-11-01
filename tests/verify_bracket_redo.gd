extends Node
## verify_bracket_redo.gd —— 周日对阵图 / 8 强图整页重做的判据(方案书 docs/plans/20261031c-周日赛事界面重做.md §6 第 3 条;
##   含 S 子方案书 docs/plans/20261101-决赛日开播一场接一场.md §4.4 交给对阵图的 10 个显示点)。
##
## 每条量的是**需求本身**(屏上真建出来的节点 / 字 / 矩形), 不是我写的钩子:
##   G2 未播不填 · G3 下一场条 · G4 本轮名牌墙 · G5 备战屏 · G9 红叉 + 光点 · G15 我这一路 · G22 收盘领奖台 + 滚动名单(收盘不预告下一场比赛)
##   · G23 全部组宫格 · G25 轮空主按钮「去看 X 对 Y」· P2 决赛格更大 + 奖杯 · P3 处境句 · P4 轮空小卡 · P5 列名
##   · P6 页面级开播提示 · P7 头像不写首字 · P8/P9 倒计时那一行不压 / 跟着在看的组 · P10 组页签 · P11 竞技场背景
##   · P12 18:00 前大倒计时 + 已报名人数 · P15 对局卡两侧头像对齐 · P22 倒计时归零 5 秒内重拉
##   · S 清单 1~10(即将开播签 / 句首轮名 / 我的场 X 后开播 / 观众第 k 场 / 场间主按钮不消失 / 版面收 / 即将开播小卡 /
##     等我那场「你的比赛 X 后开播」/ 看别的组跟着别的组 / 判负标「阵容无效 · 判负」)
##   · 两个比例(1560×720 / 960×720)下: 对阵卡互不重叠、不出屏、不压到顶上那几行与底部那一条。
## 数据全是造的, 时刻全钉死(`set_data(..., now)`), 档期照 20261101 迁移的 seq 形状。

const BMS := preload("res://scripts/scenes/BracketMapScene.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const PS := preload("res://scripts/systems/replay/premiere_schedule.gd")
const ST := preload("res://scripts/scenes/bracket/bracket_stage.gd")
const H := preload("res://scripts/scenes/bracket/bracket_hero.gd")
const CD := preload("res://scripts/scenes/bracket/champion_data.gd")
const CER := preload("res://scripts/scenes/bracket/bracket_ceremony.gd")
const CS := preload("res://scripts/scenes/bracket/champion_show.gd")
const CHK := preload("res://scripts/scenes/bracket/champion_hook.gd")
const SB := preload("res://scripts/net/supabase.gd")

const WEEK := 1792972800
const SUN := WEEK + 6 * 86400
const F := SUN + 18 * 3600 + 8 * 60
const C := SUN + P2C.FINALS_START_HOUR_UTC * 3600 + 2 * 60     # 冠军杯赛开赛后 2 分钟(钟点从常量推, 10-31 挪到 19:00)
const GN := [["吃货一枚", "小辉同学", "afei23", "huihui"], ["jyz11", "阿丽呀", "max5452", "阿芳"],
	["头发多多", "ykx1314", "kris520", "海盗龟王"], ["石头统领", "彩虹大师", "fish31", "haohao"]]

var _fail := 0
var _n := 0
var _m = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _grp(g: int, round_: int, done: Dictionary, scores: Dictionary, closed: bool, me: int, now: int, extra: Dictionary = {}) -> Dictionary:
	var accs: Array = []
	var tags: Array = []
	for i in range(4):
		accs.append("acc-%d-%d" % [g, i])
		tags.append(P2C.player_tag("acc-%d-%d" % [g, i]))
	var d := {"bucket": g, "size": 4, "round": round_, "me": me, "names": GN[g], "tags": tags, "accs": accs,
		"avatars": ["candy", "", "bubble", ""], "done": done, "scores": scores, "closed": closed, "revealed_at": 0,
		"round_at": 0, "srv_now": now, "recv_at": now}
	d.merge(extra, true)
	return d


func _seq() -> Dictionary:
	return {"v": 1, "until": F + 315, "p": {"1-0": [F, F + 130], "1-1": [F + 155, F + 290]}}


## 第 1 轮一场接一场(4 人组, 我 = 0 号, 半决赛第 1 场)
func _g_seq(g: int, me: int, now: int) -> Dictionary:
	return _grp(g, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1, "1-1": 0}, false, me, now,
		{"revealed_at": F, "round_at": F + 315, "seq": _seq()})


func _cup(round_: int, done: Dictionary, scores: Dictionary, closed: bool, me: int, now: int, extra: Dictionary = {}) -> Dictionary:
	var names: Array = []
	var accs: Array = []
	var tags: Array = []
	for g in range(6):
		names.append(["吃货一枚", "jyz11", "头发多多", "石头统领", "龟龟冲鸭", "竹子先生"][g])
		accs.append("acc-%d-0" % g)
		tags.append(P2C.player_tag("acc-%d-0" % g))
	var d := {"bucket": P2C.FINALS_CUP_BUCKET, "size": 6, "round": round_, "me": me, "names": names, "tags": tags,
		"accs": accs, "avatars": ["candy", "", "bubble", "", "stone", ""], "done": done, "scores": scores, "closed": closed,
		"revealed_at": 0, "round_at": 0, "srv_now": now, "recv_at": now}
	d.merge(extra, true)
	return d


func _closed_groups(now: int) -> Array:
	var out: Array = []
	for g in range(4):
		out.append(_grp(g, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {"1-0": 1, "1-1": 0, "2-0": 0}, true, 0 if g == 0 else -1, now))
	return out


## `pre` > 0: set_week 那一次重画先钉在这个时刻(默认 = now)。
## ★2026-11-01 查实: 原来 set_week 那一次重画走**真实时钟** —— WEEK 写死 2026-10-26 那一周, 真实日期恰好落在这一周
##   (2026-11-01 周日晚上)时, 那一次重画就把第 1 场揭晓了(红叉 + 光点), 紧接着 set_data 重画把画布清掉、
##   而「揭晓过」已记账不再放 ⇒ G9 只在这一周的这个时段红(与改动无关的日期偶发)。⇒ 一律钉住, 不读真实时钟。
func _open(bucket: Dictionary, finals: Dictionary, week: Dictionary, now: int, cup: bool, pre: int = 0) -> void:
	if _m != null and is_instance_valid(_m):
		_m.queue_free()
		await _frames(2)
	_m = BMS.new()
	get_tree().root.add_child(_m)
	await _frames(2)
	_m._now_override = pre if pre > 0 else now
	if not week.is_empty():
		_m.set_week(week)
	_m.set_data(bucket, finals, now)
	_m.pick_view(L.VIEW_FINALS if cup else L.VIEW_BUCKET)
	await _frames(3)


func _find(name: String, root: Node = null) -> Array:
	return (root if root != null else _m).find_children(name, "", true, false)


func _label_text(name: String) -> String:
	var a := _find(name)
	return str((a[0] as Label).text) if not a.is_empty() else ""


## ★同名兄弟会被引擎改成 @…@ 名 ⇒ 一律按 meta 认(对阵卡带 rm、其余带 bk / place / Portrait)。
func _cards() -> Array:
	var out: Array = []
	for c in _m._canvas.get_children():
		if c is Control and not (c is Button) and (c as Node).has_meta("rm"):
			out.append(c)
	return out


func _meta(root: Node, key: String, val = null) -> Array:
	var out: Array = []
	var q: Array = [root]
	while not q.is_empty():
		var nd: Node = q.pop_back()
		for k in nd.get_children():
			q.append(k)
			if k.has_meta(key) and (val == null or k.get_meta(key) == val):
				out.append(k)
	return out


func _card_at(r: int, mm: int) -> Control:
	for c in _cards():
		if (c as Control).get_meta("rm", Vector2i(-9, -9)) == Vector2i(r, mm):
			return c
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.finals_pending_reveal = {}
	for vp in [Vector2i(1560, 720), Vector2i(960, 720)]:
		get_tree().root.size = vp
		await _frames(2)
		print("── 视口 %s(可见区 %s) ──" % [str(vp), str(get_viewport().get_visible_rect().size)])
		await _t_group_live(vp)
		await _t_cup_live(vp)
		await _t_layout(vp)
		await _t_finals_bar(vp)
	get_tree().root.size = Vector2i(1280, 720)
	await _t_together()
	await _t_wall_prep()
	await _t_grid_peek()
	await _t_closing()
	await _t_preshow()
	await _t_popup_and_forfeit()
	await _t_defending()
	_finish()


# ─────────────────────────────────────────────────────────────
# 小组赛 · 第 1 场开播中、第 2 场即将开播(S 清单 1~5 · G2 G3 G15 · P3 P6 P7 P11)
# ─────────────────────────────────────────────────────────────
func _t_group_live(vp: Vector2i) -> void:
	var tag := "[%d]" % vp.x
	var wk: Array = [_g_seq(0, 0, F + 40)]
	for g in range(1, 4):
		wk.append(_g_seq(g, -1, F + 40))
	await _open(wk[0], {}, {"buckets": wk}, F + 40, false)
	_ok("%s 分母: 4 人组 · 第 1 场开播 / 第 2 场即将开播" % tag, str(_m.match_state(1, 0)) == BMS.ST_PREMIERE
		and str(_m.match_state(1, 1)) == BMS.ST_UPCOMING, "%s / %s" % [_m.match_state(1, 0), _m.match_state(1, 1)])
	## G2: 决赛那一格两侧都还没填(半决赛都还没播完)、✓ 一个都没有
	var ticks := 0
	for c in _m._canvas.find_children("*", "Label", true, false):
		if str((c as Label).text).begins_with("✓"):
			ticks += 1
	_ok("%s G2 ★未播完的场不填: 决赛两侧「等待中」、全图 0 个 ✓" % tag, ticks == 0
		and int(_m.competitor(2, 0, 0).get("seed", 0)) < 0 and int(_m.competitor(2, 0, 1).get("seed", 0)) < 0, "✓ %d" % ticks)
	## S1: 即将开播那一格有琥珀签 + 卡顶倒计时「…后」
	var up := _card_at(1, 1)
	## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 卡顶一件事: 即将开播 = 开播时刻(「第 2 场 18:10 开播」), 右边「即将开播」签
	_ok("%s S1 ★即将开播那一格: 「即将开播」签 + 卡顶写开播时刻" % tag, up != null and up.find_child("UpcomingTag", true, false) != null
		and str((up.find_child("CardHead", true, false) as Label).text).ends_with(" 开播"),
		str((up.find_child("CardHead", true, false) as Label).text) if up != null else "无卡")
	## S2: 顶上那一行句首带轮名
	## 选手那一行只数跟我有关的: 我那场在播 ⇒ 不出现(原来「半决赛第 1 场开播中 · 第 2 场 X 后开播」一行两件事, 还数别人那场)
	_ok("%s S2 ★我那场在播 ⇒ 倒计时行不出现" % tag, not _m._tip.visible, str(_m._tip.text))
	## P3 / S3: 处境句
	_ok("%s P3 ★处境句 = 「你的半决赛开播中」" % tag, _label_text("HeroStatus") == "你的半决赛开播中", _label_text("HeroStatus"))
	## P6: 页面级开播提示 —— 组页签上那一组挂红灯(开播中的组)
	var lamps := 0
	for chip in _m._spec_bar.get_children():
		if chip.has_meta("chip") and str(chip.get_meta("chip")) != "all" and chip.get_node_or_null("Plate") != null:
			for k in chip.get_node("Plate").get_children():
				if k is ColorRect and (k as ColorRect).color == H.LIVE:
					lamps += 1
	_ok("%s P6 ★开播中的组在组页签上挂红灯(4 组都在播 ⇒ 4 盏)" % tag, lamps == 4, "%d 盏" % lamps)
	## G3: 下一场条
	_ok("%s G3 ★底部「下一场」写的是第 2 场那一对" % tag, _label_text("NextPair") == "小辉同学 对 afei23", _label_text("NextPair"))
	## 主按钮: 我那场在播 ⇒ 观看我的比赛, 指向 1-0
	var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
	_ok("%s 主按钮「观看我的比赛」指向我那一场" % tag, cta != null and cta.visible and not cta.disabled and cta.text == "观看我的比赛"
		and cta.get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 0), str(cta.text) if cta != null else "无")
	## G15: 我这一路 —— 小组 2 格 + 冠军杯 2 格(4 组 ⇒ 杯 2 轮); 第 1 格在播
	var mp: Dictionary = _m._info.my_path()
	var cells: Array = mp.get("cells", [])
	_ok("%s G15 ★我这一路: 小组 2 格 + 冠军杯 2 格, 第 1 格「在播」" % tag, cells.size() == 4 and int(mp.get("split", 0)) == 2
		and str((cells[0] as Dictionary).get("state", "")) == "live" and not _find("MyPath").is_empty(), str(cells))
	## P7: 头像全是图(真头像或默认龟头像), 没有一个写名字首字
	var letters := 0
	var pics := 0
	for p in _meta(_m._canvas, "Portrait"):
		for k in (p as Node).get_children():
			if k is TextureRect and (k as TextureRect).texture != null:
				pics += 1
			elif k is Label and str((k as Label).text) != "?":
				letters += 1
	_ok("%s P7 ★头像不写首字(有图 %d / 首字 %d)" % [tag, pics, letters], letters == 0 and pics >= 4)
	## P11: 背景是竞技场像素图(不是黑底)
	var bg: TextureRect = null
	for t in _m.find_children("*", "TextureRect", true, false):
		if (t as TextureRect).texture != null and str((t as TextureRect).texture.resource_path).ends_with("bracket-bg-arena.png"):
			bg = t
	_ok("%s P11 ★背景铺的是竞技场像素图" % tag, bg != null and bg.is_visible_in_tree())
	H._seen_reveal.clear()
	## S4: 换到别的组(观众)⇒ 处境句「观战 · X · 半决赛第 1 场开播中」; 顶上那一行跟着那一组(S9 / P9)
	_m.pick_chip(2)
	await _frames(2)
	var gname: String = CD.group_name(2)
	## 旁观第三人称、一件事(缎带上已写着在看哪一组, 不再「观战 · C 组 · …」)
	_ok("%s S4 ★看别的组: 「半决赛第 1 场开播中」(缎带写「%s」)" % [tag, gname], _label_text("HeroStatus") == "半决赛第 1 场开播中",
		_label_text("HeroStatus"))
	_ok("%s S9 ★看别的组: 缎带写那一组, 顶上那一行仍是开播进度(那一组的)" % tag, _label_text("RibbonText").find(gname) >= 0
		and str(_m._tip.text).begins_with("距下一场开播 "), "%s / %s" % [_label_text("RibbonText"), _m._tip.text])
	## 场间(第 1 场揭晓、第 2 场还没开): S5 主按钮不消失、不可点、写倒计时
	## 进场那两次重画: 先钉在第 1 场揭晓之前(F+10), 再到 F+140 ⇒ 揭晓发生在最后那一次重画里(玩家停在页上等到揭晓那一刻)
	H._seen_reveal.clear()
	await _open(wk[0], {}, {"buckets": wk}, F + 140, false, F + 10)
	var cta2: Button = _m.find_child("PrimaryCta", true, false) as Button
	## 主按钮等待时只写状态词(倒计时只在处境句下面一行出现一次; 原来按钮与那一行逐字相同)
	_ok("%s S5 ★场间主按钮还在: 不可点「等待开播」" % tag, cta2 != null and cta2.visible and cta2.disabled
		and str(cta2.text) == "等待开播", str(cta2.text) if cta2 != null else "无")
	## G9: 第 1 场刚揭晓 ⇒ 输家头像盖红叉 + 一枚光点沿连线走
	_ok("%s G9 ★揭晓那一刻: 输家红叉 + 光点走线" % tag, not _m._canvas.find_children("LoseMark", "", true, false).is_empty()
		and not _m._canvas.find_children("TravelDot", "", true, false).is_empty())
	## S3: 我那场排在第 2 场时「你的半决赛 X 后开播」(我 = 1 号种子, 在 1-1)
	var mine2 := _g_seq(0, 2, F + 40)
	await _open(mine2, {}, {"buckets": [mine2]}, F + 40, false)
	_ok("%s S3 ★我那场排在后面: 「你的半决赛 HH:MM 开播」+ 下一行「距开播 X」" % tag, _label_text("HeroStatus").begins_with("你的半决赛 ")
		and _label_text("HeroStatus").ends_with(" 开播") and str(_m._tip.text).begins_with("距开播 "), _label_text("HeroStatus") + " / " + str(_m._tip.text))


# ─────────────────────────────────────────────────────────────
# 冠军杯赛 8 签 6 人(两个轮空)· 1/4 决赛第 1 场开播(G25 · P2 P4 P5 · ⑦)
# ─────────────────────────────────────────────────────────────
func _cup_live(now: int) -> Dictionary:
	var cseq := {"v": 1, "until": C + 320, "p": {"1-1": [C, C + 135], "1-3": [C + 160, C + 295]}}
	return _cup(2, {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0}, {"1-1": 1, "1-3": 0}, false, 0, now,
		{"revealed_at": C, "round_at": C + 320, "seq": cseq})


func _t_cup_live(vp: Vector2i) -> void:
	var tag := "[%d]" % vp.x
	var cup := _cup_live(C + 50)
	var grp := _closed_groups(C + 50)
	await _open(grp[0], cup, {"buckets": grp, "cup": cup}, C + 50, true)
	_ok("%s 分母: 冠军杯 6 人 8 签 · 1-1 开播 / 1-3 即将开播 / 1-0 1-2 轮空" % tag, str(_m.match_state(1, 1)) == BMS.ST_PREMIERE
		and str(_m.match_state(1, 3)) == BMS.ST_UPCOMING and bool(_m.competitor(1, 0, 1).get("bye", false)))
	## G25 / ⑳: 我首轮轮空 ⇒ 主按钮「去看 X 对 Y」指向正在播的那一场
	var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
	_ok("%s G25 ★轮空的人主按钮「观看 石头统领 对 龟龟冲鸭」" % tag, cta != null and cta.visible and not cta.disabled
		and cta.text == "观看 石头统领 对 龟龟冲鸭" and cta.get_meta("rm", Vector2i(-1, -1)) == Vector2i(1, 1), str(cta.text) if cta != null else "无")
	_ok("%s G25 处境句「首轮轮空，直接晋级半决赛」" % tag, _label_text("HeroStatus") == "首轮轮空，直接晋级半决赛", _label_text("HeroStatus"))
	## P4: 轮空格是小卡(比真对局矮), 卡顶写「轮空」
	var bye := _card_at(1, 0)
	var real := _card_at(1, 1)
	_ok("%s P4 ★轮空格是小卡(高 %.0f < 真对局 %.0f)、卡顶「轮空」" % [tag, bye.size.y if bye else 0.0, real.size.y if real else 0.0],
		bye != null and real != null and bye.size.y < real.size.y * 0.8
		and str((bye.find_child("CardHead", true, false) as Label).text) == "轮空")
	## P5: 首轮列名「1/4 决赛」(不是「第 1 轮」)
	var titles: Array = []
	for t in _meta(_m._canvas, "bk", "round_title"):
		titles.append(str((t as Label).text))
	_ok("%s P5 ★列名「1/4 决赛 · 半决赛」(不写「第 1 轮」)" % tag, titles.has("1/4 决赛") and titles.has("半决赛")
		and not titles.has("第 1 轮"), str(titles))
	## P2: 决赛格比别的格子宽, 正中有奖杯 + 冠军缎带
	var fin := _card_at(3, 0)
	## 奖杯 / 缎带按贴图认(重画时旧节点还没删, 同名新节点会被引擎改名)
	var trophy_n := 0
	var ribbon_n := 0
	for t in _m._canvas.find_children("*", "", true, false):
		if t.is_queued_for_deletion():
			continue
		if t is TextureRect and (t as TextureRect).texture != null and str((t as TextureRect).texture.resource_path).ends_with("bracket-trophy.png"):
			trophy_n += 1
		if t is NinePatchRect and str((t as NinePatchRect).texture.resource_path).ends_with("bracket-ribbon.png"):
			ribbon_n += 1
	_ok("%s P2 ★决赛格更宽(%.0f > %.0f) + 正中奖杯 + 冠军缎带" % [tag, fin.size.x if fin else 0.0, real.size.x if real else 0.0],
		fin != null and real != null and fin.size.x > real.size.x and trophy_n >= 1 and ribbon_n >= 1, "奖杯 %d 缎带 %d" % [trophy_n, ribbon_n])
	## ⑦ 来历: 每位都标是哪一组的冠军(组名与冠军收盘同一个来源)
	var origins: Array = []
	for o in _meta(_m._canvas, "bk", "seat_origin"):
		origins.append(str((o as Label).text))
	_ok("%s ⑦ ★来历标签「%s冠军」(%d 条)" % [tag, CD.group_name(3), origins.size()], origins.has("%s冠军" % CD.group_name(3))
		and origins.size() >= 4, str(origins))


# ─────────────────────────────────────────────────────────────
# 两个比例的版面: 卡互不重叠 / 不出屏 / 不压到顶上几行与底部
# ─────────────────────────────────────────────────────────────
func _t_layout(vp: Vector2i) -> void:
	var tag := "[%d]" % vp.x
	var vis: Vector2 = get_viewport().get_visible_rect().size
	for which in ["group", "cup"]:
		if which == "group":
			var wk: Array = [_g_seq(0, 0, F + 40)]
			for g in range(1, 4):
				wk.append(_g_seq(g, -1, F + 40))
			await _open(wk[0], {}, {"buckets": wk}, F + 40, false)
		else:
			var cup := _cup_live(C + 50)
			var grp := _closed_groups(C + 50)
			await _open(grp[0], cup, {"buckets": grp, "cup": cup}, C + 50, true)
		await _frames(30)
		var rects: Array = []
		for c in _cards():
			rects.append((c as Control).get_global_rect())
		var bad: Array = []
		for i in range(rects.size()):
			var a: Rect2 = rects[i]
			if a.position.x < 0 or a.position.y < 0 or a.end.x > vis.x or a.end.y > vis.y:
				bad.append("卡 %d 出屏 %s" % [i, str(a)])
			for j in range(i + 1, rects.size()):
				if a.grow(-1).intersects((rects[j] as Rect2).grow(-1)):
					bad.append("卡 %d 与 %d 重叠" % [i, j])
		## 顶上几行(处境句 / 倒计时 / 组页签 / 缎带)与底部(主按钮 / 我这一路 / 下一场)都不许压到卡
		var fixed: Array = []
		for nm in ["HeroStatus", "MyPath", "NextMatch"]:
			for nd in _find(nm):
				fixed.append([nm, (nd as Control).get_global_rect()])
		if _m._tip.visible:
			fixed.append(["_tip", Rect2(_m._tip.global_position, Vector2(vis.x, 22.0))])
		var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
		if cta != null and cta.visible:
			fixed.append(["CTA", cta.get_global_rect()])
		for k in _m._spec_bar.get_children():
			if k.has_meta("chip"):
				var pl: Control = k.get_node_or_null("Plate")
				if pl != null:
					fixed.append(["组页签", pl.get_global_rect()])
		for f in fixed:
			for i2 in range(rects.size()):
				if (f[1] as Rect2).intersects(rects[i2]):
					bad.append("%s 压到卡 %d" % [f[0], i2])
		## 冠军缎带不许压到两边的卡
		for rb in _m._canvas.find_children("Ribbon", "", true, false):
			var rr: Rect2 = (rb as Control).get_global_rect()
			for i3 in range(rects.size()):
				var cc: Rect2 = rects[i3]
				var is_final: bool = absf(cc.get_center().x - vis.x * 0.5) < 2.0
				if not is_final and rr.intersects(cc.grow(-2)):
					bad.append("冠军缎带压到卡 %d" % i3)
		_ok("%s 版面[%s] ★%d 张卡: 不重叠 / 不出屏 / 不压固定件(%d 件)" % [tag, which, rects.size(), fixed.size()],
			bad.is_empty() and rects.size() >= 3 and fixed.size() >= 3, str(bad.slice(0, 6)))


# ─────────────────────────────────────────────────────────────
# 小组赛同一轮同时开播(S 10-31 改「桶内同轮同时开播、冠军杯一场接一场」): 顶上那一行带轮名、没有「即将开播」、
#   观众句是真实的 N、我不在播时主按钮「观看开播 · N 场」点亮那几格
# ─────────────────────────────────────────────────────────────
func _g_together(g: int, me: int, now: int) -> Dictionary:
	return _grp(g, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1, "1-1": 0}, false, me, now,
		{"revealed_at": F, "round_at": F + 175, "seq": {"v": 1, "until": F + 175, "p": {"1-0": [F, F + 130], "1-1": [F, F + 150]}}})


func _t_together() -> void:
	var b := _g_together(0, 0, F + 40)
	await _open(b, {}, {"buckets": [b]}, F + 40, false)
	var tags: int = _m._canvas.find_children("PremiereTag", "", true, false).size()
	var ups: int = _m._canvas.find_children("UpcomingTag", "", true, false).size()
	_ok("同时开播 ★两格同时「开播」、没有「即将开播」签(那只在冠军杯)", tags == 2 and ups == 0
		and str(_m.match_state(1, 0)) == BMS.ST_PREMIERE and str(_m.match_state(1, 1)) == BMS.ST_PREMIERE, "开播 %d · 即将 %d" % [tags, ups])
	_ok("同时开播 ★我在播 ⇒ 处境句「你的半决赛开播中」、倒计时行不出现", _label_text("HeroStatus") == "你的半决赛开播中" and not _m._tip.visible,
		_label_text("HeroStatus") + " / " + str(_m._tip.text))
	var head := ""
	var c0 := _card_at(1, 0)
	if c0 != null:
		head = str((c0.find_child("CardHead", true, false) as Label).text)
	_ok("同时开播 卡顶只写轮名(没有「第 k 场」的先后)", head == "半决赛", head)
	var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
	_ok("同时开播 我在播 ⇒ 主按钮「观看我的比赛」", cta != null and cta.visible and cta.text == "观看我的比赛", str(cta.text) if cta else "无")
	## 观众(我不在这一组)
	var b2 := _g_together(0, -1, F + 40)
	await _open(b2, {}, {"buckets": [b2]}, F + 40, false)
	_ok("同时开播 ★观众句是真实的 N「半决赛 2 场开播中」",
		_label_text("HeroStatus") == "半决赛 2 场开播中", _label_text("HeroStatus"))
	var cta2: Button = _m.find_child("PrimaryCta", true, false) as Button
	_ok("同时开播 ★我不在播 ⇒ 主按钮「观看开播」", cta2 != null and cta2.visible and not cta2.disabled and cta2.text == "观看开播",
		str(cta2.text) if cta2 else "无")
	if cta2 != null:
		cta2.pressed.emit()
		## 弹起是 0.12 秒的 tween: 无头帧率极高时 4 帧才走几毫秒 ⇒ 逐帧看, 两格都弹起来就停(上限 3000 帧)
		var grown := 0
		for _f in range(3000):
			await get_tree().process_frame
			grown = 0
			for c in _cards():
				if (c as Control).scale.x > 1.0005:      # 开始往上弹了就算(不等弹到顶: CI 帧率高, 少花帧)
					grown += 1
			if grown >= 2:
				break
		_ok("同时开播 ★按「观看开播 · 2 场」⇒ 开播中那两格弹起(提示去点哪一格), 不替玩家挑、不弹窗", grown == 2
			and _m.find_child("MatchPopup", true, false) == null, "弹起 %d 格" % grown)


# ─────────────────────────────────────────────────────────────
# M 的全局决赛日小条(autoload FinalsDay)在对阵图上: 停在我留的停靠位, 不压「我这一路」/ 下一场 / 处境句 / 主按钮 / 卡
# ─────────────────────────────────────────────────────────────
func _t_finals_bar(vp: Vector2i) -> void:
	var tag := "[%d]" % vp.x
	var fd = get_node_or_null("/root/FinalsDay")
	_ok("%s 小条 分母: FinalsDay 在" % tag, fd != null)
	if fd == null:
		return
	var keep: int = P2C.now_override_ts
	P2C.now_override_ts = F + 40                       # 周日 18:08(决赛日)
	var wk: Array = [_g_seq(0, 0, F + 40)]
	for g in range(1, 4):
		wk.append(_g_seq(g, -1, F + 40))
	await _open(wk[0], {}, {"buckets": wk}, F + 40, false)
	fd.test_host = _m                                   # 把对阵图当成「这一屏」(M 门禁同一个做法)
	_m._rebuild()
	await _frames(2)
	fd.tick()
	await _frames(3)
	var bar: Control = fd.bar
	var dock: Control = _m.find_child("FinalsBarDock", true, false)
	var br := bar.get_global_rect() if bar != null else Rect2()
	var bad: Array = []
	for nm in ["MyPath", "NextMatch", "HeroStatus"]:
		for nd in _find(nm):
			if (nd as Control).is_visible_in_tree() and br.intersects((nd as Control).get_global_rect()):
				bad.append(nm)
	var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
	if cta != null and cta.visible and br.intersects(cta.get_global_rect()):
		bad.append("主按钮")
	for c in _cards():
		if br.intersects((c as Control).get_global_rect().grow(-1)):
			bad.append("对阵卡")
	for k in _m._spec_bar.get_children():
		if k.has_meta("chip") and k.get_node_or_null("Plate") != null and br.intersects((k.get_node("Plate") as Control).get_global_rect()):
			bad.append("组页签")
	if _m._tip.visible and br.intersects(Rect2(_m._tip.global_position, Vector2(_m._tip.size.x, 22.0))):
		bad.append("倒计时那一行")
	_ok("%s ★小条在场 ⇒ 停在我留的停靠位(居中), 不压我这一路 / 下一场 / 处境句 / 主按钮 / 卡 / 组页签" % tag,
		bar != null and bar.visible and dock != null and absf(br.get_center().x - dock.get_global_rect().get_center().x) <= 2.0
		and bad.is_empty() and br.size.x > 100.0, "条 %s · 压到 %s" % [str(br), str(bad)])
	fd.test_host = null
	fd.tick()
	P2C.now_override_ts = keep


# ─────────────────────────────────────────────────────────────
# 本轮名牌墙 → 3 分钟备战屏(G4 · G5 · S6)
# ─────────────────────────────────────────────────────────────
func _t_wall_prep() -> void:
	ST.wall_played.clear()
	ST.prep_dismissed.clear()
	var b := _g_seq(0, 0, F + 296)
	await _open(b, {}, {"buckets": [b]}, F + 296, false)
	var walls := _find("NameWall")
	_ok("G4 分母: 第 2 场揭晓之后、下一轮备战之前", str(_m.match_state(1, 1)) == BMS.ST_DONE and PS.before_shop(_m.cur(), F + 296))
	_ok("G4 ★本轮名牌墙出来了", walls.size() == 1)
	if walls.size() == 1:
		var w: Node = walls[0]
		var plates: Array = _meta(w, "bk", "wall_plate")
		var xs := 0
		for p in plates:
			if not (p as Node).find_children("LoseMark", "", true, false).is_empty():
				xs += 1
		_ok("G4 ★名牌 4 块, 输家 2 块盖红叉", plates.size() == 4 and xs == 2, "%d 块 / 红叉 %d" % [plates.size(), xs])
		_ok("G4 ★揭晓下一轮对阵「吃货一枚 对 afei23」", str((w.find_child("WallPairs", true, false) as Label).text).find("吃货一枚  对  afei23") >= 0,
			str((w.find_child("WallPairs", true, false) as Label).text))
	## 同一轮只放一次(轮询重画不再弹)
	_m._rebuild()
	await _frames(2)
	var live_walls := 0
	for w2 in _find("NameWall"):
		if not (w2 as Node).is_queued_for_deletion():
			live_walls += 1
	_ok("G4 ★同一轮只放一次(重画后不再弹第二块)", live_walls <= 1 and _find("NameWall").size() <= 1, "%d" % live_walls)
	_ok("G4 ★重画(轮询 / 回包)不打断正在放的那块墙", live_walls == 1, "%d" % live_walls)
	## S6: 开播段备战那一行不出现, 版面收 —— 对阵区顶边 = 处境句 + 倒计时两行, 不留备战那一行的空
	var top_live: float = _m._hero_line1_y
	_ok("S6 ★开播段: 备战那一行不出现", not _m._shop_row.visible, str(_m._shop_row.text))
	## 备战窗开了 ⇒ 备战屏
	var b2 := _g_seq(0, 0, F + 330)
	await _open(b2, {}, {"buckets": [b2]}, F + 330, false)
	var preps := _find("PrepScreen")
	_ok("G5 ★备战窗开着 ⇒ 备战屏(大倒计时 + 本轮进度 + 下一轮对阵 + 利害一句)", preps.size() == 1
		and str((preps[0] as Node).find_child("PrepCountdown", true, false).text).begins_with("剩余 ")
		and str((preps[0] as Node).find_child("PrepStake", true, false).text).find("冠军") >= 0 if preps.size() == 1 else false)
	_ok("S6 备战窗开着 ⇒ 备战那一行出现「备战剩余 …」", _m._shop_row.visible and str(_m._shop_row.text).begins_with("备战剩余"),
		str(_m._shop_row.text))
	if preps.size() == 1:
		## 「一样在动的东西」: 选手卡那一排真在走(量位置, 不量有没有 tween)
		var reel: Control = (preps[0] as Node).find_child("PrepCarousel", true, false).get_child(0)
		var x0 := reel.position.x
		_m._process(0.4)                   # 走场景自己的那一拍(不按墙钟等: CI 帧率不定)
		_ok("G5 ★选手卡那一排在动(0.4 秒走了 %.1f px)" % (x0 - reel.position.x), x0 - reel.position.x > 4.0)
		## 主按钮让位(同一个倒计时不在屏上说三遍)
		var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
		_ok("G5 备战屏在时主按钮让位", cta == null or not cta.visible)
		## 「查看对阵图」⇒ 收起, 这一轮不再自己弹
		var hide: Button = (preps[0] as Node).find_child("PrepHide", true, false) as Button
		hide.pressed.emit()
		_m._rebuild()
		await _frames(2)
		var alive := 0
		for p2 in _find("PrepScreen"):
			if not (p2 as Node).is_queued_for_deletion():
				alive += 1
		_ok("G5 ★「查看对阵图」⇒ 备战屏收起且这一轮不再弹", alive == 0, "%d" % alive)
		var cta2: Button = _m.find_child("PrimaryCta", true, false) as Button
		_ok("G5 收起后主按钮回来(不可点、写备战剩余)", cta2 != null and cta2.visible and cta2.disabled and str(cta2.text).begins_with("备战中"),
			str(cta2.text) if cta2 != null else "无")
	var _u := top_live


# ─────────────────────────────────────────────────────────────
# 全部组宫格 · 看别的组(G23 · P9 · P10 · S9)
# ─────────────────────────────────────────────────────────────
func _t_grid_peek() -> void:
	var wk: Array = [_g_seq(0, 0, F + 40), _g_seq(1, -1, F + 40),
		_grp(2, 2, {"1-0": 0, "1-1": 0, "2-0": 1}, {}, true, -1, F + 40), _grp(3, 1, {}, {}, false, -1, F + 40, {"round_at": F + 20})]
	await _open(wk[0], {}, {"buckets": wk}, F + 40, false)
	## P10: 组页签(全部 + 每组一枚), 不再是「上一组 / 下一组」
	var chips: Array = []
	for k in _m._spec_bar.get_children():
		if k.has_meta("chip") and (k as Control).visible:
			chips.append(str((k as Button).text))
	_ok("P10 ★组页签「全部 + 每组一枚」(%s)" % str(chips), chips.size() == 5 and chips[0] == "全部" and chips.has(CD.group_name(1))
		and not (_m._spec_bar.get_child(0) as Control).visible)
	_m.pick_chip("all")
	await _frames(2)
	var cells := _meta(_m, "bk", "grid_cell")
	_ok("G23 ★全部组宫格: 4 组 4 格", cells.size() == 4, "%d" % cells.size())
	var chips_txt: Array = []
	for cl in _meta(_m, "bk", "grid_chip"):
		chips_txt.append(str((cl as Label).text))
	_ok("G23 ★每格写状态(开播中 ×2 / 已结束 / 备战中)", chips_txt.count("开播中") == 2 and chips_txt.has("已结束") and chips_txt.has("备战中"),
		str(chips_txt))
	_ok("G23 宫格里不挂倒计时 / 备战那两行(那是某一组的)", not _m._tip.visible and not _m._shop_row.visible)
	(cells[1] as Button).pressed.emit()
	await _frames(2)
	_ok("G23 ★点第 2 格 ⇒ 进那一组(只能看)", int(_m.cur().get("bucket", -1)) == 1 and int(_m.cur().get("me", 0)) == -1 and not _m._grid_on)
	## P9: 看别的组时备战那一行不说我那组的事
	var mine := _grp(0, 1, {}, {}, false, 0, F + 40, {"round_at": F})
	var other := _grp(1, 1, {}, {}, false, -1, F + 40, {"round_at": F})
	await _open(mine, {}, {"buckets": [mine, other]}, F + 40, false)
	_ok("P9 分母: 看我那组时备战那一行在", _m._shop_row.visible and str(_m._shop_row.text).begins_with("备战剩余"), str(_m._shop_row.text))
	_m.pick_chip(1)
	await _frames(2)
	_m._process(0.6)
	_ok("P9 ★看别的组 ⇒ 备战那一行不出现(屏上写着在看 %s)" % CD.group_name(1), not _m._shop_row.visible and _label_text("RibbonText").find(CD.group_name(1)) >= 0,
		"%s / %s" % [_m._shop_row.text, _label_text("RibbonText")])


# ─────────────────────────────────────────────────────────────
# 冠军杯收盘(G22 · ⑰)+ 冠军决出那一刻的挂点
# ─────────────────────────────────────────────────────────────
func _t_closing() -> void:
	var grp := _closed_groups(SUN + (P2C.FINALS_START_HOUR_UTC + 1) * 3600)
	## 先看见决赛还在播(那一刻之前), 再看见收盘 ⇒ 挂点只报一次
	var done := {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0, "2-0": 0, "2-1": 1, "3-0": 0}
	var sc := {"1-1": 1, "1-3": 0, "2-0": 1, "2-1": 0, "3-0": 1}
	var t0 := SUN + P2C.FINALS_START_HOUR_UTC * 3600 + 40 * 60
	var playing := _cup(3, done, sc, true, 0, t0, {"revealed_at": t0 - 30})
	await _open(grp[0], playing, {"buckets": grp, "cup": playing}, t0, true)
	_ok("挂点 分母: 决赛开播中(冠军还没揭晓)", str(_m.match_state(3, 0)) == BMS.ST_PREMIERE and _m.last_champion_data.is_empty())
	CER.played.clear()
	_m.enable_ceremony(true)
	## 冠军本人在看(冠军杯 0 号签 = acc-0-0)⇒ 定格卡带奖励链
	var gs = get_node_or_null("/root/GameState")
	var acc0 = gs.get("account_id") if gs != null else ""
	if gs != null:
		gs.set("account_id", "acc-0-0")
	_m._now_override = t0 + 600
	_m._finals["srv_now"] = t0 + 600
	_m._finals["recv_at"] = t0 + 600
	_m._rebuild()
	await _frames(3)
	var d: Dictionary = _m.last_champion_data
	_ok("挂点 ★决赛揭晓那一刻调 `_on_champion_decided`: 冠军 / 亚军 / 四强 / 夺冠之路 / 人数", str(d.get("stage", "")) == "cup"
		and str((d.get("champion", {}) as Dictionary).get("name", "")) == "吃货一枚"
		and str((d.get("runner_up", {}) as Dictionary).get("name", "")) == "头发多多"
		and (d.get("semifinalists", []) as Array).size() == 2 and (d.get("path", []) as Array).size() == 3
		and int(d.get("total_entrants", 0)) == 16 and bool(d.get("is_me", false)) and d.has("view"), str(d.keys()))
	var seen := d.duplicate()
	_m._rebuild()
	await _frames(2)
	_ok("挂点 同一张图只报一次", _m.last_champion_data == seen)
	## 收盘画面
	var places: Array = []
	for st in _meta(_m._canvas, "place"):
		places.append(str(st.get_meta("place")))
	_ok("G22 ★领奖台: 1 / 2 / 3 台(两位四强)都站了人", places.count("1") == 1 and places.count("2") == 1 and places.count("3") == 2, str(places))
	_ok("G22 ★滚动全部参赛者(16 人)", _find("EntrantTicker").size() == 1
		and str(((_find("EntrantTicker")[0] as Node).get_child(0).get_child(0) as Label).text).begins_with("本周决赛日参赛选手（16 人）"))
	## ★收盘只讲结果, 不预告下一场比赛(用户 10-31「为什么在这儿提示新的比赛」; 「下一站」归主菜单每周赛程条):
	##   屏上任何一段字都不提闯关赛 / 积分赛 / 下周 / 新一大轮 / 开赛倒计时。分母: 屏上真有字(含处境句与领奖台名字)。
	var teaser: Array = []
	var nlab := 0
	for lb in _m.find_children("*", "Label", true, false):
		if not (lb as Label).is_visible_in_tree():
			continue
		nlab += 1
		var tx := str((lb as Label).text)
		for w in ["闯关赛", "积分赛", "下周", "新一大轮", "后开赛", "后开始"]:
			if tx.find(w) >= 0:
				teaser.append(tx.substr(0, 30))
	_ok("G22 ★收盘后不出现下一场比赛的预告(看得见的字 %d 段)" % nlab, teaser.is_empty() and nlab >= 20
		and _label_text("HeroStatus") == "你获得冠军杯赛冠军！", str(teaser))
	_ok("G22 收盘那一刻奖励行让给滚动名单(不叠字)", _m._canvas.find_child("RewardLine", true, false) == null)
	var cta: Button = _m.find_child("PrimaryCta", true, false) as Button
	_ok("G22 主按钮「重看决赛」", cta != null and cta.visible and cta.text == "重看决赛")
	## ★领奖台不挤: 两位四强左右分开、名字与 1 / 2 名同级大小, 头像与名字两两不重叠
	var seats: Array = []
	var names: Array = []
	for st2 in _meta(_m._canvas, "place"):
		for p in _meta(st2, "Portrait"):
			seats.append([int(st2.get_meta("place")), (p as Control).get_global_rect()])
		for nl in _meta(st2, "bk", "podium_name"):
			names.append([int(st2.get_meta("place")), (nl as Label).get_global_rect(), (nl as Label).get_theme_font_size("font_size"),
				(nl as Label).get_theme_font("font").get_string_size((nl as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					(nl as Label).get_theme_font_size("font_size")).x])
	var clash: Array = []
	for i in range(seats.size()):
		for j in range(i + 1, seats.size()):
			if (seats[i][1] as Rect2).grow(-1).intersects((seats[j][1] as Rect2).grow(-1)):
				clash.append("头像 %d/%d" % [seats[i][0], seats[j][0]])
	## 名字量**真正画出来的字宽**(居中), 不量 Label 控件的框
	var ink: Array = []
	for nm in names:
		var r0: Rect2 = nm[1]
		var tw: float = float(nm[3])
		ink.append([nm[0], Rect2(Vector2(r0.get_center().x - tw * 0.5, r0.position.y), Vector2(tw, r0.size.y))])
	for i in range(ink.size()):
		for j in range(i + 1, ink.size()):
			if (ink[i][1] as Rect2).grow(-1).intersects((ink[j][1] as Rect2).grow(-1)):
				clash.append("名字 %d/%d" % [ink[i][0], ink[j][0]])
		for sp in seats:
			if (ink[i][1] as Rect2).grow(-1).intersects((sp[1] as Rect2).grow(-1)):
				clash.append("名字 %d 压头像 %d" % [ink[i][0], sp[0]])
	var fs3: Array = []
	var fs2 := 0
	for nm2 in names:
		if int(nm2[0]) == 3:
			fs3.append(int(nm2[2]))
		elif int(nm2[0]) == 2:
			fs2 = int(nm2[2])
	_ok("G22 ★领奖台两位四强不挤: 头像 / 名字两两不重叠, 名字与亚军同级(%s vs %d)" % [str(fs3), fs2],
		seats.size() == 4 and names.size() == 4 and clash.is_empty() and fs3.size() == 2 and fs3[0] == fs2 and fs3[1] == fs2, str(clash))
	## ★冠军决出那一刻 ⇒ 冠军收盘(ChampionShow)真打开了; 同一周同一张图只演一次
	var shows: Array = []
	for k in _m.get_children():
		if k is CS:
			shows.append(k)
	_ok("G10 ★冠军揭晓那一刻 ⇒ 冠军收盘(ChampionShow)打开(冠军杯 · 我是冠军 ⇒ 带奖励链)", shows.size() == 1
		and str((shows[0] as Node).get("data").get("mode", "")) == "cup" and not ((shows[0] as Node).get("data").get("rewards", []) as Array).is_empty()
		if shows.size() == 1 else false, "%d 个" % shows.size())
	var again = _m._ceremony.play_champion(_m.last_champion_data)
	var shows2 := 0
	for k2 in _m.get_children():
		if k2 is CS and not k2.is_queued_for_deletion():
			shows2 += 1
	_ok("G10 ★同一周同一张图只演一次(再报一次不再开)", again == null and shows2 == 1, "%d 个" % shows2)
	## 观战那一侧(ChampionHook)已经演过这一周的冠军杯收盘 ⇒ 对阵图这边不再演
	CER.played.clear()
	var hk = CHK.new()
	get_tree().root.add_child(hk)
	hk.last_data = {"mode": "cup", "week": int(_m.last_champion_data.get("week", 0))}
	var dup = _m._ceremony.play_champion(_m.last_champion_data)
	_ok("G10 ★看直播看到决赛结束的人(ChampionHook 演过)回对阵图不再演第二遍", dup == null)
	hk.queue_free()
	for k3 in _m.get_children():
		if k3 is CS:
			k3.queue_free()
	## ★只认「刚刚」见过没揭晓的那一下: 18:10 看过 A 组(决赛没揭晓)、20:40 才回来 ⇒ 不弹 A 组冠军仪式(错过的补看归 M)
	var INF2 = load("res://scripts/scenes/bracket/bracket_info.gd")
	INF2.champ_waiting.clear()
	INF2.champ_fired.clear()
	var ga := _grp(0, 2, {"1-0": 0, "1-1": 1}, {}, false, 0, F + 600)
	await _open(ga, {}, {"buckets": [ga]}, F + 600, false)
	var gb := _grp(0, 2, {"1-0": 0, "1-1": 1, "2-0": 0}, {}, true, 0, F + 600 + 9000)
	_m.enable_ceremony(true)
	await _open(gb, {}, {"buckets": [gb]}, F + 600 + 9000, false)
	_ok("G10 ★很久以前见过没揭晓、隔了两个半小时才回来 ⇒ 不弹组冠军仪式(挂点不报)", _m.last_champion_data.is_empty())
	if gs != null:
		gs.set("account_id", acc0)


# ─────────────────────────────────────────────────────────────
# 18:00 前(P12)· 倒计时归零(P22)
# ─────────────────────────────────────────────────────────────
func _t_preshow() -> void:
	var now := SUN + 17 * 3600 + 41 * 60
	await _open({"reason": "not_seated", "entered": 24}, {}, {}, now, false)
	var seat := int(P2C.finals_seat_ts(WEEK))
	_ok("P12 分母: 未分组那一档", str(_m._empty_kind()) == BMS.EK_NOT_SEATED)
	## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 18:00 前那一页换成赛前页(bracket_preseat: 距小组赛开始 + 今晚赛程 + 晋级名单; 详量见 verify_finals_copy ①)
	_ok("P12 ★大倒计时数到 18:00(%s)" % _label_text("PreseatCountdown"), _label_text("PreseatCountdown") == _m._info.big_countdown(seat - now)
		and _label_text("PreseatCountdown").begins_with("19 分"), _label_text("PreseatCountdown"))
	_ok("P12 ★写出已报名人数(名单接口没回时用分组接口给的人数)", _label_text("PreseatListCount") == "24 人", _label_text("PreseatListCount"))
	_ok("P12 说明框藏起来(赛前页取代), 判断那一句仍从同一份分类出", not _m._empty_box.visible and str(_m._empty_lb.text) == str(_m._empty_text()))
	## P22: 倒计时归零 ⇒ 写「即将开播…」并 5 秒内重拉
	var b := _grp(0, 1, {}, {}, false, 0, F, {"left": 0, "recv_at": F, "round_at": F - 400})
	await _open(b, {}, {}, F, false)
	_m._fetch_left = 30.0
	_m._sync_tip()
	## 归零后不挂「0 秒」也不写会过去的时刻: 倒计时行收起、主按钮「等待开播」, 5 秒内重拉
	_ok("P22 ★归零: 倒计时行收起(不停在 0)+ 5 秒内重拉(原来要等满 30 秒)", not _m._tip.visible and float(_m._fetch_left) <= 5.0,
		"%s / %.1f" % [_m._tip.text if _m._tip.visible else "<不出现>", _m._fetch_left])


# ─────────────────────────────────────────────────────────────
# 对局卡两侧对齐(P15)· 即将开播小卡(S7)· 等我那场(S8)· 判负(S10)
# ─────────────────────────────────────────────────────────────
func _t_popup_and_forfeit() -> void:
	var b := _g_seq(0, 0, F + 140)
	await _open(b, {}, {"buckets": [b]}, F + 140, false)
	## P15: 点我那一场(已揭晓)⇒ 两侧头像同一高度; 对手那侧有举报入口, 我这侧同高空位
	var nb: Button = null
	for x in _m._canvas.find_children("NodeBtn", "Button", true, false):
		if (x as Button).get_meta("rm", Vector2i(-9, -9)) == Vector2i(1, 0):
			nb = x
	_ok("P15 分母: 1-0 那一格能点", nb != null)
	if nb != null:
		nb.pressed.emit()
		await _frames(3)
		var pop: Node = _m.find_child("MatchPopup", true, false)
		var ps: Array = []
		if pop != null:
			for p in _meta(pop, "Portrait"):
				ps.append((p as Control).get_global_rect())
		_ok("P15 ★对局卡两侧头像同一高度(差 ≤ 1px)", ps.size() == 2 and absf((ps[0] as Rect2).position.y - (ps[1] as Rect2).position.y) <= 1.0, str(ps))
		var entries: Array = pop.find_children("PlayerMenuEntry", "Button", true, false) if pop != null else []
		var big := 0
		for e in pop.find_children("*", "Button", true, false) if pop != null else []:
			if str((e as Button).text).find("举报") >= 0 and not (e as Button).flat:
				big += 1
		_ok("P15 ★不再有「举报 / 拉黑」石板大按钮(入口是一行字链)", big == 0, "%d" % big)
		_m._close_popup()
		await _frames(2)
		var _u := entries
	## S7: 即将开播那一格点开 ⇒ 只写「X 后开播」的小卡
	var ui: Array = _m._canvas.find_children("UpcomingInfo", "Button", true, false)
	_ok("S7 分母: 即将开播那一格有说明热区(不叫 NodeBtn, 不带 rm)", ui.size() == 1 and not (ui[0] as Button).has_meta("rm"))
	if ui.size() == 1:
		(ui[0] as Button).pressed.emit()
		await _frames(2)
		var uc: Node = _m.find_child("UpcomingCard", true, false)
		_ok("S7 ★小卡写「距开播 X」", uc != null and str((uc.find_child("UpcomingCountdown", true, false) as Label).text).begins_with("距开播 "))
		if uc != null:
			uc.queue_free()
			await _frames(1)
	## S8: 等我那场揭晓、而它排在后面 ⇒ 「你的比赛 X 后开播」
	var mine2 := _g_seq(0, 2, F + 40)
	await _open(mine2, {}, {"buckets": [mine2]}, F + 40, false)
	_m.await_watch = Vector2i(1, 1)
	_m._await_watch_view = _m._view
	_m._check_referee_watch()
	var rm: Label = _m.find_child("ReplayMsg", true, false) as Label
	_ok("S8 ★等我那场(排在第 2 场): 「你的比赛 HH:MM 开播」", rm != null and str(rm.text).begins_with("你的比赛 ") and str(rm.text).ends_with(" 开播"),
		str(rm.text) if rm != null else "无")
	_m.await_watch = Vector2i(-1, -1)
	## S10: 判负(有结果、无档期、不是轮空)⇒ 卡顶「判负」, 输方那一行「阵容无效 · 判负」
	var fb := _grp(0, 2, {"1-0": 0, "1-1": 1}, {"1-0": 1}, false, -1, F + 200,
		{"revealed_at": F, "round_at": F + 315, "seq": {"v": 1, "until": F + 315, "p": {"1-0": [F, F + 130]}}})
	await _open(fb, {}, {"buckets": [fb]}, F + 200, false)
	var c11 := _card_at(1, 1)
	var origins: Array = []
	if c11 != null:
		for o in _meta(c11, "bk", "seat_origin"):
			origins.append(str((o as Label).text))
	_ok("S10 ★判负那一场: 卡顶「判负」、输方「阵容无效，判负」", c11 != null and str((c11.find_child("CardHead", true, false) as Label).text) == "判负"
		and origins == ["阵容无效，判负"], "%s / %s" % [str((c11.find_child("CardHead", true, false) as Label).text) if c11 else "", str(origins)])
	var c10 := _card_at(1, 0)
	_ok("S10 对照: 有档期的那一场照常「已结束」", c10 != null and str((c10.find_child("CardHead", true, false) as Label).text) == "已结束")


# ─────────────────────────────────────────────────────────────
# ⑦「卫冕」的数据源(2026-10-31 write_orphan: 原来 defending_acc 产品侧没人写)
#   走真入口: 后端打开 + 注入传输(不碰网络), 场景自己问本周两份; 本周冠军杯成表后它再问**上周**那一份,
#   上周冠军杯冠军 = 本周 A 组冠军 ⇒ 冠军杯来历标签「卫冕 · A 组冠军」、开场亮相那一位标「卫冕」。
# ─────────────────────────────────────────────────────────────
var _def_reqs: Array = []
var _def_prev_body := ""
var _def_week_body := ""
var _def_mine_body := ""


func _def_spy(_method, url, _headers, body, cb) -> void:
	var u := str(url)
	_def_reqs.append({"url": u, "body": str(body)})
	if u.ends_with("/finals_week_view"):
		var j = JSON.parse_string(str(body))
		var wk := int((j as Dictionary).get("p_week", 0)) if j is Dictionary else 0
		if wk == WEEK - CD.WEEK_SEC:
			if _def_prev_body == "":
				cb.call({"ok": false, "code": 0, "body": ""})        # 连不上
			else:
				cb.call({"ok": true, "code": 200, "body": _def_prev_body})
		else:
			cb.call({"ok": true, "code": 200, "body": _def_week_body})
	elif u.ends_with("/finals_view"):
		cb.call({"ok": true, "code": 200, "body": _def_mine_body})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _def_ent(seed: int, name: String, acc: String) -> Dictionary:
	return {"seed": seed, "name": name, "account_id": acc}


func _def_prev_asks() -> int:
	var n := 0
	for r in _def_reqs:
		if str(r["url"]).ends_with("/finals_week_view"):
			var j = JSON.parse_string(str(r["body"]))
			if j is Dictionary and int((j as Dictionary).get("p_week", 0)) == WEEK - CD.WEEK_SEC:
				n += 1
	return n


## 进对阵图(真入口: 不 set_data), 一拍一拍地调场景自己的轮询。
func _def_enter() -> void:
	if _m != null and is_instance_valid(_m):
		_m.queue_free()
		await _frames(2)
	SB.finals_clear()
	SB.finals_week_clear()
	_m = BMS.new()
	get_tree().root.add_child(_m)
	_m._poll.stop()
	for _i in range(4):
		await _frames(2)
		_m._on_poll()


func _def_origins() -> Array:
	var out: Array = []
	for o in _meta(_m._canvas, "bk", "seat_origin"):
		if not (o as Node).is_queued_for_deletion():
			out.append(str((o as Label).text))
	return out


func _def_intro_flags() -> Dictionary:
	var it = _m._ceremony.last_intro
	var out := {}
	if it == null or not is_instance_valid(it):
		return out
	for e in (it.get("data").get("entrants", []) as Array):
		out[str((e as Dictionary).get("name", ""))] = bool((e as Dictionary).get("defending", false))
	return out


func _t_defending() -> void:
	var gs = get_node_or_null("/root/GameState")
	var acc0 = gs.get("account_id") if gs != null else ""
	var env0 := OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._token = "gate-token"
	SB._transport_for_test = _def_spy
	if gs != null:
		gs.set("account_id", "uid-new")
	var cup_at := SUN + int(P2C.FINALS_START_HOUR_UTC) * 3600
	var now := cup_at + 60                        # 冠军杯赛刚成表、第 1 场还在备战(开场亮相那一刻)
	P2C.now_override_ts = now
	## 本周: A 组冠军「老冠军」、B 组冠军「新人」(我); 冠军杯 2 人、第 1 轮备战中
	var ga := {"bucket": 0, "n": 2, "round": 1, "closed": true, "round_at": cup_at - 3600, "revealed_at": cup_at - 3000,
		"done": {"1-0": 0}, "entrants": [_def_ent(0, "老冠军", "uid-def"), _def_ent(1, "路人甲", "uid-a")]}
	var gb := {"bucket": 1, "n": 2, "round": 1, "closed": true, "round_at": cup_at - 3600, "revealed_at": cup_at - 3000,
		"done": {"1-0": 0}, "entrants": [_def_ent(0, "新人", "uid-new"), _def_ent(1, "路人乙", "uid-b")]}
	var cup := {"bucket": P2C.FINALS_CUP_BUCKET, "n": 2, "round": 1, "closed": false, "round_at": cup_at, "revealed_at": 0,
		"done": {}, "entrants": [_def_ent(0, "老冠军", "uid-def"), _def_ent(1, "新人", "uid-new")]}
	var mine := gb.duplicate(true)
	mine["ok"] = true
	mine["now"] = now
	_def_mine_body = JSON.stringify(mine)
	_def_week_body = JSON.stringify({"ok": true, "week": WEEK, "now": now, "buckets": [ga, gb], "cup": cup})
	## 上周: 冠军杯冠军 = uid-def
	var pcup := {"bucket": P2C.FINALS_CUP_BUCKET, "n": 2, "round": 1, "closed": true, "round_at": cup_at - 7 * 86400,
		"revealed_at": cup_at - 7 * 86400 + 600, "done": {"1-0": 0},
		"entrants": [_def_ent(0, "老冠军", "uid-def"), _def_ent(1, "上周亚军", "uid-old2")]}
	_def_prev_body = JSON.stringify({"ok": true, "week": WEEK - CD.WEEK_SEC, "now": now, "buckets": [], "cup": pcup})
	CER.defending_by_week.clear()
	CER.intro_played.clear()
	_def_reqs.clear()
	var asks0: int = CER.defending_asks
	await _def_enter()
	var want := "%s冠军（卫冕）" % CD.group_name(0)
	var org := _def_origins()
	_ok("卫冕 分母: 走的是真入口(没喂数据) · 冠军杯那一张 2 人", not bool(_m._injected) and str(_m._view) == L.VIEW_FINALS
		and int(_m.cur().get("size", 0)) == 2, "%s %s" % [str(_m._view), str(_m.cur().get("size", 0))])
	_ok("卫冕 ★分母: 真的问了上周那一份(冠军墙同一个读接口), 恰好一次", _def_prev_asks() == 1
		and CER.defending_asks - asks0 == 1, "%d 次" % _def_prev_asks())
	_ok("卫冕 ★★产品写进了 defending_acc(上周冠军杯冠军)", str(_m.defending_acc) == "uid-def", str(_m.defending_acc))
	_ok("卫冕 ★★★冠军杯来历标签「%s」(对照: 新人只写「%s冠军」)" % [want, CD.group_name(1)],
		org.has(want) and org.has("%s冠军" % CD.group_name(1)), str(org))
	var fl := _def_intro_flags()
	_ok("卫冕 ★★★开场亮相: 老冠军标「卫冕」、新人不标", fl.get("老冠军", false) == true and fl.get("新人", true) == false, str(fl))
	## 只取一次: 退出再进(新场景实例)不再问
	await _def_enter()
	_ok("卫冕 ★只取一次: 再进对阵图不再问上周(缓存), 标签照样在", _def_prev_asks() == 1 and _def_origins().has(want),
		"%d 次 / %s" % [_def_prev_asks(), str(_def_origins())])
	## 拿不到(连不上)⇒ 留空不显示, 开场照演
	_def_prev_body = ""
	CER.defending_by_week.clear()
	CER.intro_played.clear()
	_def_reqs.clear()
	await _def_enter()
	var org2 := _def_origins()
	var fl2 := _def_intro_flags()
	_ok("卫冕 ★拿不到上周 ⇒ 不标「卫冕」(分母: 真的问了 %d 次)" % _def_prev_asks(), _def_prev_asks() == 1
		and str(_m.defending_acc) == "" and org2.has("%s冠军" % CD.group_name(0)) and not str(org2).contains("卫冕"), str(org2))
	_ok("卫冕 ★拿不到上周 ⇒ 开场亮相照演(没卡在等)", fl2.size() == 2 and not fl2.values().has(true), str(fl2))
	## 收尾
	if _m != null and is_instance_valid(_m):
		_m.queue_free()
		await _frames(2)
	_m = null
	SB._transport_for_test = Callable()
	SB._token = ""
	SB.finals_clear()
	SB.finals_week_clear()
	OS.set_environment(SB.ENV_URL, env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)
	P2C.now_override_ts = 0
	CER.defending_by_week.clear()
	if gs != null:
		gs.set("account_id", acc0)


func _finish() -> void:
	if _m != null and is_instance_valid(_m):
		_m.queue_free()
	print("")
	print("  (共 %d 条断言 · %d 帧 · %.1f 秒)" % [_n, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 对阵图整页重做" if _fail == 0 and _n > 50 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
