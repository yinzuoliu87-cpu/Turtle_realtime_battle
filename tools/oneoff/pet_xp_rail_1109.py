"""结算屏龟经验挪到左栏(2026-11-09): 战果页最高那一版(闯关晋级, 两行说明)放一行经验会把 MVP 挤出 52px(verify_settle_fit 实测)。
左栏页签下面是弹性空白、三页都看得到 ⇒ 竖排放这里。一次性改文件脚本: 二进制读写、保留行尾、每处断言恰命中一次。"""
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"


def edit(rel, pairs):
    p = ROOT + rel
    b = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in b
    s = b.replace("\r\n", "\n")
    for a, c in pairs:
        assert s.count(a) == 1, (rel, a[:100], s.count(a))
        s = s.replace(a, c)
    open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))


S = "scripts/scenes/battle/settle_screen.gd"
src = open(ROOT + S, "rb").read().decode("utf-8").replace("\r\n", "\n")
i0 = src.index("## ── ④b 上场三只龟的经验条(2026-11-09")
i1 = src.index("static func _pet_name(pid: String) -> String:")
old_block = src[i0:i1]

NEW_BLOCK = '''## ── ④b 上场三只龟的经验(2026-11-09 · 方案书 docs/plans/20261107b-龟等级与经验.md §4.5) ──
##   积分赛 / 闯关 / 决赛日每一局, 上场的三只统领里拥有的: 胜 +8 / 负 +6(服务器在算完那一刻发, 迁移 20261109b)。
##   这里按同一条规则(PetXp.gain)把经验条从旧值涨到新值, 跨级时等级牌换数字 + 放大回弹 + 升级音效;
##   建的时候就把本机缓存改成新值(下次进选龟页 / 图鉴就是新的; PetLevelsNet 每 REFRESH_SEC 再问服务器一次对齐)。
##   限免龟「限免」(灰条), 满级「满级」。
##   不放: 封存(周日决赛不宣布胜负 —— +8 / +6 一露就等于说了输赢)、练习赛 / 切磋 / 教程(不给经验)、
##   没拉到拥有表或不按拥有过滤(不知道哪只是自己的)。
## ★放在左栏页签下面, 不放战果页: 战果页最高那一版(闯关晋级, 两行说明)只剩约 17px 余量, 放一行经验会把「本场 MVP」
##   挤出可视区 52px(verify_settle_fit 1280×720 实测)。左栏页签下面是弹性空白, 三页都看得到; 左栏最窄 RAIL_MIN = 150 ⇒
##   一只龟一行 = 头像 + 「Lv.N +8」+ 一根条, 不放名字(头像就是哪只), 「经验」二字放在这一块的小标题里。
## ★挂在胜负大字那一条并行 tween 上(同 _pop_coin_chip): 结算屏的裸 tween 有台账(tools/tween_freeze_audit.py)。
const XP_AVATAR := 32.0
const XP_BAR_H := 8.0
const XP_T0 := 0.95          # 开始涨: 金币格(0.42 起数 0.45 秒)数完之后
const XP_FILL_SEC := 0.55    # 一段涨满用时(跨级 = 两段)
const XP_STAGGER := 0.12     # 三只依次起步
const XP_POP := 1.45         # 升级那一下等级牌放大到多少


## 看的人这一局的三只统领(周六配对局看的人是 B ⇒ 取右方快照里那三只, 同 battle_hud._build_reward_chips 的口径)。纯函数。
static func xp_leaders(b, gs) -> Array:
	if gs == null:
		return []
	var src = gs.get("season_leaders")
	if b != null and ReplayRecorder.viewer_side(b) == "b" and gs.get("dual_ghost") is Dictionary:
		src = (gs.get("dual_ghost") as Dictionary).get("leaders", [])
	var out: Array = []
	if src is Array:
		for p in src:
			if p is String and WeeklyFree.ALL.has(p) and not out.has(p) and out.size() < 3:
				out.append(p)
	return out


func _xp_row(won: bool, sealed: bool, gs, tw: Tween) -> Control:
	if sealed or gs == null or not battle._had_season or battle._last_was_exhibition:
		return null
	if not (PetLevelsNet.fetched and PetLevelsNet.filter_on()):
		return null
	var leaders := xp_leaders(battle, gs)
	if leaders.is_empty():
		return null
	## 这一局开演前的经验: 结算屏可能重建 ⇒ 第一次建时记在战斗场上, 之后都从这份算(同一局的经验不会加两次)
	var x0s: Dictionary = battle.get_meta("_pet_xp0", {})
	if x0s.is_empty():
		for p in leaders:
			x0s[p] = PetXp.cached_xp(p)
		battle.set_meta("_pet_xp0", x0s)
	var row := VBoxContainer.new()
	row.name = "PetXpRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hd := _lbl("龟经验", F_CAP, COL_DIM)
	hd.name = "XpHead"
	row.add_child(hd)
	var i := 0
	for pid in leaders:
		var owned: bool = PetLevelsNet.owned.has(pid)
		var x0: int = int(x0s.get(pid, 0))
		var g: int = PetXp.gain(x0, won, owned)
		row.add_child(_xp_item(pid, owned, x0, g, tw, XP_T0 + XP_STAGGER * float(i)))
		if g > 0:
			PetLevelsNet.levels[pid] = {"lv": int(PetXp.progress(x0 + g)["lv"]), "xp": x0 + g}
		i += 1
	PetLevelsNet._write_table()
	return row


func _xp_item(pid: String, owned: bool, x0: int, g: int, tw: Tween, t0: float) -> Control:
	var p0 := PetXp.progress(x0)
	var p1 := PetXp.progress(x0 + g)
	var it := HBoxContainer.new()
	it.name = "PetXp_" + pid
	it.add_theme_constant_override("separation", 8)
	it.mouse_filter = Control.MOUSE_FILTER_IGNORE
	it.set_meta("xp", [x0, x0 + g])
	var av := avatar({"id": pid}, XP_AVATAR)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	it.add_child(av)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	it.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var lv := _lbl("Lv.%d" % int(p0["lv"]), F_CAP, COL_GOLD)
	lv.name = "XpLv"
	top.add_child(lv)
	var note: Label
	if not owned:
		note = _lbl("限免", F_CAP, COL_SUB)
	elif bool(p0["maxed"]):
		note = _lbl("满级", F_CAP, COL_GOLD)
	else:
		note = _lbl("+0", F_CAP, Color("#8fe0ff"))
	note.name = "XpNote"
	top.add_child(note)
	var bar := PetXpBar.new()
	bar.name = "XpBar"
	bar.custom_minimum_size = Vector2(40.0, XP_BAR_H)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.frac = float(p0["frac"])
	if not owned:
		bar.fill_color = Color("#5b6672")
	col.add_child(bar)
	if g <= 0:
		return it
	## 涨: 不跨级 = 一段 p0 → p1; 跨级 = 先涨满 → 等级牌换数字 + 放大回弹 + 升级音效 → 从 0 涨到 p1(一局最多 +8, 每级至少 70 ⇒ 最多跨一级)
	var up: bool = int(p1["lv"]) > int(p0["lv"])
	var f_end: float = 1.0 if up else float(p1["frac"])
	tw.tween_method(func(f: float) -> void:
		bar.frac = f, float(p0["frac"]), f_end, XP_FILL_SEC).set_delay(t0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(x: float) -> void:
		note.text = "+%d" % int(round(x)), 0.0, float(g), XP_FILL_SEC).set_delay(t0)
	if not up:
		return it
	var t1: float = t0 + XP_FILL_SEC
	tw.tween_callback(func() -> void:
		lv.text = "Lv.%d" % int(p1["lv"])
		lv.pivot_offset = lv.size / 2.0
		bar.frac = 0.0
		Audio.play_sfx("level_up")).set_delay(t1)
	tw.tween_method(func(s: float) -> void:
		lv.scale = Vector2.ONE * s, XP_POP, 1.0, 0.35).set_delay(t1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var f2: float = 1.0 if bool(p1["maxed"]) else float(p1["frac"])
	tw.tween_method(func(f: float) -> void:
		bar.frac = f, 0.0, f2, XP_FILL_SEC * 0.6).set_delay(t1 + 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return it


'''

edit(S, [
    (old_block, NEW_BLOCK),
    ("""var rail_word: Label""", """var _rail: VBoxContainer = null       # 左栏(页签那一竖条): 龟经验挂在页签下面, 见 _xp_row
var rail_word: Label"""),
    ("""	rail.name = "SettleRail"
""", """	rail.name = "SettleRail"
	_rail = rail
"""),
    ("""	## ④b 上场三只龟的经验(2026-11-09 · 方案书 20261107b §4.5), 见 _xp_row
	var xp_row: Control = _xp_row(won, sealed, gs, tw)
	if xp_row != null:
		v.add_child(xp_row)
		hud._banner_fade_in(xp_row, XP_T0 - 0.3)
""", """	## ④b 上场三只龟的经验(2026-11-09 · 方案书 20261107b §4.5): 挂在左栏页签下面(为什么不放这一页见 _xp_row 头注)
	var xp_row: Control = _xp_row(won, sealed, gs, tw)
	if xp_row != null and _rail != null:
		_rail.add_child(xp_row)
		_rail.move_child(xp_row, tab_btns.size() + 1)
		hud._banner_fade_in(xp_row, XP_T0 - 0.3)
"""),
])

edit("tests/verify_settle_fit.gd", [
    ("""	## 「上场三只龟的经验」: 积分赛 / 闯关真的建出来三只; 封存(不宣布胜负) / 练习赛(不给经验)不放
	var xr: Node = p1.find_child("PetXpRow", true, false)
	var want_xp: bool = kind in ["ranked", "ranked6", "gauntlet"]
	_ok("[%s] ★分母: 上场三只龟的经验%s" % [vt, "建出来了(三只)" if want_xp else "不放"],
		(xr != null and xr.get_child_count() == 3) if want_xp else xr == null, "有 %s 个" % (str(xr.get_child_count()) if xr != null else "0"))
""", """	## 「上场三只龟的经验」(左栏页签下面): 积分赛 / 闯关真的建出来三只; 封存(不宣布胜负) / 练习赛(不给经验)不放
	var xr: Node = scr.find_child("PetXpRow", true, false)
	var nxp := 0
	if xr != null:
		for c in xr.get_children():
			if str(c.name).begins_with("PetXp_"):
				nxp += 1
	var want_xp: bool = kind in ["ranked", "ranked6", "gauntlet"]
	_ok("[%s] ★分母: 上场三只龟的经验%s" % [vt, "建出来了(三只)" if want_xp else "不放"],
		nxp == 3 if want_xp else xr == null, "有 %d 只" % nxp)
	## 而且整块在可视区里(左栏最窄 150、最矮 720 也要放得下): 头像 / 字 / 条每一件的矩形都在安全区里
	if xr != null:
		var vis := (scr as Control).get_viewport_rect()
		var bad: Array = []
		for n in xr.find_children("*", "Control", true, false):
			var r := (n as Control).get_global_rect()
			if r.size.x > 0.0 and not vis.grow(TOL).encloses(r):
				bad.append("%s %s" % [n.name, str(r)])
		_ok("[%s] ★上场三只龟的经验整块在屏幕里" % vt, bad.is_empty(), str(bad.slice(0, 3)))
"""),
])
print("ok")
