extends RefCounted
## battle_log_card.gd —— 战绩页一场对局的卡(2026-11-18 · 方案书 docs/plans/20261118-对局记录重做.md §4.2)。
##
## 用户 11-18「时间、双方的装备也没有…你看看这个整个页面怎么做吧」。参考:
##   · 云顶之弈对局记录 —— 每只单位头像下面一排它带的装备(带星);
##   · 皇室战争 Battle Log —— 双方阵容左右对照、中间 VS、右侧「观看」;
##   · 荒野乱斗 Battle Log —— 结果一眼可读(色带 + 字), 不只靠颜色。
## 一张卡: 左一条胜负色带 | 头行[赛事签 · 胜利/失败 · 时间 · 时长 …… 上路 胜 / 下路 负] | 主体[我方三统领(各带装备) VS 对方三统领 …… 观看]。
## 行数据形状见 `BattleLogNet`(服务器行与本机老记录同一个形状)。

const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const BLN := preload("res://scripts/net/battle_log_net.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const CARD_W := 1060.0
const PORTRAIT := 54.0
const SLOT := 24.0
const SLOT_GAP := 2.0
const COL_W := 3.0 * SLOT + 2.0 * SLOT_GAP      # 一只统领那一列的宽 = 三格装备
const COL_GAP := 10.0

const COL_WIN := Color("#e8b437")
const COL_LOSS := Color("#a8343c")
const TXT_WIN := "胜利"
const TXT_LOSS := "失败"

## 赛事签: 文字 + 底色。偷袭分进攻 / 防守。
const KIND_TXT := {"ranked": "积分赛", "gauntlet": "周六闯关赛", "finals": "周日决赛", "raid": "偷袭", "local": "对局"}
const KIND_COL := {"ranked": Color("#2f5f93"), "gauntlet": Color("#a3621f"), "finals": Color("#6b46a3"),
	"raid": Color("#9a3434"), "local": Color("#3d4a57")}
const RAID_TXT := {"attack": "进攻", "defend": "防守"}

## 节点名(门禁按名字找)
const N_KIND := "KindTag"
const N_RESULT := "ResultText"
const N_TIME := "TimeText"
const N_LANE := "LaneTag"           # + top / bottom
const N_EQ := "EqSlot"              # 装备格 + 0/1/2(meta eq_id / star)
const N_SIDE_ME := "SideMe"
const N_SIDE_FOE := "SideFoe"


## 赛事签上的字。
static func kind_text(row: Dictionary) -> String:
	var k := str(row.get("kind", "local"))
	var t := str(KIND_TXT.get(k, "对局"))
	if k == "raid":
		t += " · " + str(RAID_TXT.get(str(row.get("raid_role", "")), ""))
	elif k == "finals":
		var r := int((row.get("finals", {}) as Dictionary).get("round", 0))
		if r > 0:
			t += " · 第%d轮" % r
	return t


## 时间那一行: 「今天 19:32 · 时长 1:52」。本地时区(P2C.local_dict 是全仓唯一的换算点)。`now` 由调用方注入(门禁钉时钟)。
static func time_text(at: int, secs: int, now: int) -> String:
	var parts: Array = []
	if at > 0:
		var d: Dictionary = P2C.local_dict(at)
		var t: Dictionary = P2C.local_dict(now)
		var hm := "%02d:%02d" % [int(d.get("hour", 0)), int(d.get("minute", 0))]
		var days := _day_no(t) - _day_no(d)
		if days == 0:
			parts.append("今天 " + hm)
		elif days == 1:
			parts.append("昨天 " + hm)
		elif days > 1 and days < 7:
			parts.append(P2C.local_wd_hhmm(at))
		else:
			parts.append("%d-%02d %s" % [int(d.get("month", 1)), int(d.get("day", 1)), hm])
	if secs > 0:
		parts.append("时长 %d:%02d" % [secs / 60, secs % 60])
	return "  ·  ".join(parts)


## 本地日期 → 天号(只用来比「隔了几天」)。
static func _day_no(d: Dictionary) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": int(d.get("year", 1970)), "month": int(d.get("month", 1)),
		"day": int(d.get("day", 1)), "hour": 0, "minute": 0, "second": 0}) / 86400)


## 一张卡。`watch` = 「观看」按钮(调用方做好、已连信号; null = 不出)。`idx` 给卡起确定的名字。
static func make(row: Dictionary, now: int, idx: int, card_name: String, watch: Control, foe_name_node: String) -> Control:
	var won := bool(row.get("won", false))
	var pc := PanelContainer.new()
	pc.name = card_name + str(idx)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.set_meta("row_kind", str(row.get("kind", "")))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#101a26ee")
	sb.border_color = Color("#2c3a4c")
	sb.set_border_width_all(2)
	sb.border_width_left = 0
	sb.set_corner_radius_all(0)
	sb.content_margin_right = 14
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(CARD_W, 0)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(outer)
	var strip := ColorRect.new()
	strip.color = COL_WIN if won else COL_LOSS
	strip.custom_minimum_size = Vector2(8, 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(strip)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(main)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 2)
	top_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(top_pad)
	main.add_child(_header(row, won, now))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(body)
	body.add_child(_side(row.get("me", {}), N_SIDE_ME, ""))
	body.add_child(MatchCard.vs_label(PORTRAIT + SLOT + 26.0))
	body.add_child(_side(row.get("foe", {}), N_SIDE_FOE, foe_name_node))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(sp)
	if watch != null:
		var wrap := CenterContainer.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(watch)
		body.add_child(wrap)
	var bot_pad := Control.new()
	bot_pad.custom_minimum_size = Vector2(0, 4)
	bot_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(bot_pad)
	return pc


## 头行: [赛事签] 胜利/失败 · 时间 · 时长 ……… 上路 胜 · 下路 负
static func _header(row: Dictionary, won: bool, now: int) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := str(row.get("kind", "local"))
	h.add_child(_chip(kind_text(row), KIND_COL.get(k, KIND_COL["local"]), Color("#f2f6fa"), N_KIND, 14))
	var res := Label.new()
	res.name = N_RESULT
	res.text = TXT_WIN if won else TXT_LOSS
	res.add_theme_font_size_override("font_size", 20)
	res.add_theme_color_override("font_color", Color("#ffd65c") if won else Color("#ff8c8c"))
	res.add_theme_color_override("font_outline_color", Color("#0b0f16"))
	res.add_theme_constant_override("outline_size", 4)
	h.add_child(res)
	var tm := Label.new()
	tm.name = N_TIME
	tm.text = time_text(int(row.get("at", 0)), int(row.get("secs", 0)), now)
	tm.add_theme_font_size_override("font_size", 14)
	tm.add_theme_color_override("font_color", Color("#9fb2c4"))
	tm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tm)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var lanes: Dictionary = row.get("lanes", {})
	for key in ["top", "bottom"]:
		var who := str(lanes.get(key, ""))
		if who == "":
			continue
		var t := ("上路 " if key == "top" else "下路 ") + ("胜" if who == "me" else "负")
		h.add_child(_chip(t, Color("#5b4512") if who == "me" else Color("#4a1e22"),
			Color("#ffd65c") if who == "me" else Color("#ff9c9c"), N_LANE + key, 13))
	return h


## 实心小签(像素斜面: 右下 2px 暗边)。
static func _chip(text: String, bg: Color, fg: Color, node_name: String, fs: int) -> Control:
	var pc := PanelContainer.new()
	pc.name = node_name
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", MatchCard.bevel(bg, bg.darkened(0.45), 8, 2))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", fg)
	pc.add_child(l)
	return pc


## 一方: 名字一行 + 三列(头像 + 下面三格装备)。
static func _side(side_v, node_name: String, name_node: String) -> Control:
	var side: Dictionary = side_v if side_v is Dictionary else {}
	var vb := VBoxContainer.new()
	vb.name = node_name
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Label.new()
	if name_node != "":
		nm.name = name_node
	var who := str(side.get("name", ""))
	var tag := str(side.get("tag", ""))
	nm.text = who + ("  " + tag if tag != "" and who != "" else "")
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color("#e8f0f6"))
	nm.custom_minimum_size = Vector2(3.0 * COL_W + 2.0 * COL_GAP, 0)
	nm.clip_text = true
	vb.add_child(nm)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(COL_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	var leaders: Array = side.get("leaders", [])
	for i in range(3):
		var pid := str(leaders[i]) if i < leaders.size() else ""
		row.add_child(_leader_col(side, pid))
	return vb


## 一只统领: 头像(左上角标上 / 下路) + 下面三格装备(右下角星数)。
static func _leader_col(side: Dictionary, pid: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(COL_W, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cc)
	## ★头像外包一层自由定位的 Control: 路标签挂在它上面(左上角一小块)。挂进头像(PanelContainer)会被撑满整格盖住头像(11-18 实拍)。
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(wrap)
	var av := MatchCard.avatar(pid, PORTRAIT)
	wrap.add_child(av)
	var lane := BLN.lane_of(side, pid) if pid != "" else ""
	if lane != "":
		var lt := Label.new()
		lt.text = "上" if lane == "top" else "下"
		lt.add_theme_font_size_override("font_size", 11)
		lt.add_theme_color_override("font_color", Color("#0b0f16"))
		var lb := PanelContainer.new()
		lb.name = "LaneMark"
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_theme_stylebox_override("panel", MatchCard.bevel(Color("#7fc8ff") if lane == "top" else Color("#ffb46b"),
			Color("#1c3550"), 3, 0))
		lb.add_child(lt)
		lb.position = Vector2(-3, -3)
		wrap.add_child(lb)
	var eqs := HBoxContainer.new()
	eqs.add_theme_constant_override("separation", int(SLOT_GAP))
	eqs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(eqs)
	var items: Array = (side.get("equipped", {}) as Dictionary).get(pid, []) if pid != "" else []
	for i in range(3):
		eqs.add_child(_eq_slot(items[i] if i < items.size() else {}, i))
	return col


## 一格装备: 深底方格 + 图标 + 右下角星数。空格 = 只有方格。
static func _eq_slot(it: Dictionary, i: int) -> Control:
	var slot := Panel.new()
	slot.name = N_EQ + str(i)   # 同一排三格各有名字(同名兄弟会被引擎改成 @…@ 名)
	slot.custom_minimum_size = Vector2(SLOT, SLOT)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0a121c")
	sb.border_color = Color("#2a3a4c")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	slot.add_theme_stylebox_override("panel", sb)
	var eid := str(it.get("id", ""))
	if eid == "":
		return slot
	slot.set_meta("eq_id", eid)
	slot.set_meta("star", int(it.get("star", 1)))
	var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	var ic := EquipIcon.make(edef, Vector2(SLOT - 2.0, SLOT - 2.0), true)
	ic.position = Vector2(1, 1)
	slot.add_child(ic)
	var st := int(it.get("star", 1))
	if st >= 2:
		var sl := Label.new()
		sl.text = str(st)
		sl.add_theme_font_size_override("font_size", 10)
		sl.add_theme_color_override("font_color", Color("#ffd65c"))
		sl.add_theme_color_override("font_outline_color", Color("#000000"))
		sl.add_theme_constant_override("outline_size", 3)
		sl.position = Vector2(SLOT - 8.0, SLOT - 13.0)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(sl)
	return slot
