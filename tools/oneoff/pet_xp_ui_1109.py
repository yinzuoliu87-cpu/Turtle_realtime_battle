"""龟经验条三处界面(2026-11-09 · 方案书 20261107b §4.5): 选龟卡片 / 图鉴 Lv 签 / 结算页上场三只龟。
一次性改文件脚本: 二进制读写、保留行尾、每处替换断言恰命中一次。"""
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


# ── 选龟卡片: 拥有的龟在等级牌下面挂一根经验条(位置与限免角标同一处, 两者互斥) ──
edit("scripts/scenes/team_select/pet_grid.gd", [
    ("""	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lv)
""", """	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lv)
	## 经验条(2026-11-09 · 方案书 20261107b §4.5「拥有的龟挂等级牌和经验条」): 拥有的(不是限免)在等级牌正下方、右对齐,
	##   与下面的限免角标同一个位置(一只龟要么拥有要么限免, 两者不会同时出现)。
	if PetXp.shows_bar(pid):
		var xb := PetXpBar.new()
		xb.name = "XpBar"
		xb.frac = float(PetXp.progress(PetXp.cached_xp(pid))["frac"])
		var xbw: float = roundf(sz.x * 0.34)
		xb.size = Vector2(xbw, maxf(5.0, roundf(sz.y * 0.035)))
		xb.position = Vector2(sz.x - b - 10.0 - xbw, lv.position.y + lv.size.y - 1.0)
		card.add_child(xb)
"""),
])

# ── 图鉴: Lv 签底部一条经验条(拥有的龟) + 限免的龟多挂一块「限免」签 ──
edit("scripts/scenes/codex/detail_views.gd", [
    ("""		else:
			_tag_chip(cx, cy, str(c["text"]), str(c["color"]))
		cx += w + 8.0
""", """		else:
			_tag_chip(cx, cy, str(c["text"]), str(c["color"]))
			## Lv 签底部的经验条(2026-11-09 · 方案书 20261107b §4.5): 贴着签牌九宫格边带(4px)的里沿, 在字的下面。
			if c.has("xp_frac"):
				var xb := PetXpBar.new()
				xb.name = "CodexXpBar"
				xb.frac = float(c["xp_frac"])
				xb.position = Vector2(cx + 7.0, cy + TAG_H / 2.0 - 9.0)
				xb.size = Vector2(w - 14.0, 4.0)
				host.detail.add_child(xb)
		cx += w + 8.0
"""),
    ("""	var _chips: Array = [{"kind": "badge", "text": rarity, "color": rarity_color},
		{"kind": "tag", "text": "Lv %d" % lv, "color": "#ffd93d"}]
""", """	## 经验(2026-11-09 · 方案书 20261107b §4.5): 拥有的龟 Lv 签底部挂经验条; 本周限免的龟多挂一块「限免」签(固定 1 级, 不涨经验)。
	##   还没拉到拥有表 ⇒ 先问一次服务器, 问到了把这一页重画(PetLevelsNet.fetch 只在问到时回调; 离线 / 门禁不回调, 这一页照常)。
	var _pid := str(pet.get("id", ""))
	if not PetLevelsNet.fetched and PetLevelsNet.filter_on():
		PetLevelsNet.fetch(func() -> void:
			if _rerender.is_valid():
				_rerender.call())
	var _lv_chip := {"kind": "tag", "text": "Lv %d" % lv, "color": "#ffd93d"}
	if PetXp.shows_bar(_pid):
		_lv_chip["xp_frac"] = float(PetXp.progress(PetXp.cached_xp(_pid))["frac"])
	var _chips: Array = [{"kind": "badge", "text": rarity, "color": rarity_color}, _lv_chip]
	if PetLevelsNet.is_free_pick(_pid):
		_chips.append({"kind": "tag", "text": "限免", "color": "#8fe3ff"})
"""),
])

# ── 结算页: 战果页奖励块下面一行「上场三只龟的经验」 ──
edit("scripts/scenes/battle/settle_screen.gd", [
    ("""		hud._banner_fade_in(chips, 0.42)
		_pop_coin_chip(chips, tw, 0.42)
""", """		hud._banner_fade_in(chips, 0.42)
		_pop_coin_chip(chips, tw, 0.42)
	## ④b 上场三只龟的经验(2026-11-09 · 方案书 20261107b §4.5), 见 _xp_row
	var xp_row: Control = _xp_row(won, sealed, gs, tw)
	if xp_row != null:
		v.add_child(xp_row)
		hud._banner_fade_in(xp_row, XP_T0 - 0.3)
"""),
    ("""## 录像里的胜方(left / right)⇒ 看的人口径(left = 我方赢)""", """## ── ④b 上场三只龟的经验条(2026-11-09 · 方案书 docs/plans/20261107b-龟等级与经验.md §4.5) ──
##   积分赛 / 闯关 / 决赛日每一局, 上场的三只统领里拥有的: 胜 +8 / 负 +6(服务器在算完那一刻发, 迁移 20261109b)。
##   这里按同一条规则(PetXp.gain)把经验条从旧值涨到新值, 跨级时等级牌换数字 + 放大回弹 + 升级音效;
##   演完前就把本机缓存改成新值(下次进选龟页 / 图鉴就是新的; PetLevelsNet 每 REFRESH_SEC 再问服务器一次对齐)。
##   限免龟「限免 · 不获得经验」(灰条), 满级「满级」。
##   不放: 封存(周日决赛不宣布胜负 —— +8 / +6 一露就等于说了输赢)、练习赛 / 切磋 / 教程(不给经验)、
##   没拉到拥有表或不按拥有过滤(不知道哪只是自己的)。
## ★挂在胜负大字那一条并行 tween 上(同 _pop_coin_chip): 结算屏的裸 tween 有台账(tools/tween_freeze_audit.py)。
const XP_AVATAR := 52.0
const XP_BAR_W := 150.0
const XP_BAR_H := 10.0
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
	var row := HBoxContainer.new()
	row.name = "PetXpRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	it.add_theme_constant_override("separation", 10)
	it.mouse_filter = Control.MOUSE_FILTER_IGNORE
	it.set_meta("xp", [x0, x0 + g])
	var av := avatar({"id": pid}, XP_AVATAR)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	it.add_child(av)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	it.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	top.add_child(_lbl(_pet_name(pid), F_CAP + 2, Color("#ffffff")))
	var lv := _lbl("Lv.%d" % int(p0["lv"]), F_CAP + 2, COL_GOLD)
	lv.name = "XpLv"
	top.add_child(lv)
	var bar := PetXpBar.new()
	bar.name = "XpBar"
	bar.custom_minimum_size = Vector2(XP_BAR_W, XP_BAR_H)
	bar.frac = float(p0["frac"])
	col.add_child(bar)
	var note: Label
	if not owned:
		note = _lbl("限免 · 不获得经验", F_CAP, COL_SUB)
		bar.fill_color = Color("#5b6672")
	elif bool(p0["maxed"]):
		note = _lbl("满级", F_CAP, COL_GOLD)
	else:
		note = _lbl("+0 经验", F_CAP, Color("#8fe0ff"))
	note.name = "XpNote"
	col.add_child(note)
	if g <= 0:
		return it
	## 涨: 不跨级 = 一段 p0 → p1; 跨级 = 先涨满 → 等级牌换数字 + 放大回弹 + 升级音效 → 从 0 涨到 p1(一局最多 +8, 每级至少 70 ⇒ 最多跨一级)
	var up: bool = int(p1["lv"]) > int(p0["lv"])
	var f_end: float = 1.0 if up else float(p1["frac"])
	tw.tween_method(func(f: float) -> void:
		bar.frac = f, float(p0["frac"]), f_end, XP_FILL_SEC).set_delay(t0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(x: float) -> void:
		note.text = "+%d 经验" % int(round(x)), 0.0, float(g), XP_FILL_SEC).set_delay(t0)
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


static func _pet_name(pid: String) -> String:
	for p in DataRegistry.launch_pets:
		if str((p as Dictionary).get("id", "")) == pid:
			return str((p as Dictionary).get("name", pid))
	return pid


## 录像里的胜方(left / right)⇒ 看的人口径(left = 我方赢)"""),
])
print("ok")
