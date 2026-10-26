extends RefCounted
class_name WeekCloseCard
## 周末收盘卡(2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 A+B / C)。
##
## 用户 10-26:「晋级的人……补发深海币和经验，有任何提示方式吗」→ 选「登录弹一次结算卡」;
##   「没晋级的你第一次进搞个弹窗？你设计一下」;「文案你学习商业游戏的说法」。
## 收盘之后第一次进主菜单弹, 每周每张各一次(存档 `close_card_ranked_wk` / `close_card_gauntlet_wk` 记弹过的那一周):
##   积分赛收盘(周五 23:00 UTC)后: 晋级 ⇒ RANKED_IN(没打的场次化成的奖励) / 没晋级且打过 ⇒ RANKED_OUT(去观战)
##   闯关赛收盘(周日 17:30 UTC)后: 4 胜 ⇒ GAUNTLET_IN(决赛日几点; 省下的场次第 4 胜当场就发了) / 打过但没打完 ⇒ GAUNTLET_CUT
## ★文案照商业游戏中文原文的写法(docs/plans/ref/20261026-周末文案参考.md): 标题只说发生了什么,
##   正文第一句复述结果带数字、第二句说下一步去哪; 奖励单独一行「名称 +数量」; 不用「补发 / 折算」(那是运营词)。
##   ★2026-10-26 用户「玩家比如4-0，他是不明白为什么会有未打完的2场的」⇒ 把上限说出来(括号里: 每周 16 场, 未进行的 N 场按场发放)。
##   ★★同日用户「我还需要怎么强调商业游戏的描述和口语？」⇒ 不用「你 + 口语动词」(「你用 4 场就晋级了」「省下的」「照发」「看看」「没打的」):
##     标题只写状态; 正文是数据式短陈述(「本周积分赛战绩 12 胜 1 负，晋级周六闯关赛。」); 奖励给名词标签, 规则放括号里;
##     下一步写成「下一轮积分赛：下周二开始。」(memory fb-no-colloquial-copy)。
## ★金额一个数都不自己算: 读 `backfill_summary()` —— 与真发钱那个函数同一份账。
## ★时刻一律按玩家设备时区说(用户「根据机子的时间去显示正确时间」): `phase2_config.local_wd_hhmm`。
## ★样子与教程选择框同一套(TutorialChoice): 压暗 + panel-frame 九宫格 + `UISkin.card_button`(卡片里不用木牌按钮)。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const COIN_TEX := preload("res://assets/sprites/menu/ic-deepsea.png")
## 经验图标: 与商店等级行同一个含义(赛季经验), 全游戏一张(asset_borrow_audit CROSS_OK 写了理由)。
const XP_TEX := preload("res://assets/sprites/shop/icon-xp.png")
## 周末弹窗专用素材(2026-10-26 PixelLab 新生成, assets/sprites/menu/weekend/)。徽章 = 三站的正式标识(赛程页同一套)。
const BADGE_TEX := {
	"ranked": preload("res://assets/sprites/menu/weekend/badge-ranked.png"),
	"gauntlet": preload("res://assets/sprites/menu/weekend/badge-gauntlet.png"),
	"finals": preload("res://assets/sprites/menu/weekend/badge-finals.png"),
	"rest": preload("res://assets/sprites/menu/weekend/badge-rest.png"),
}
const LOCK_TEX := preload("res://assets/sprites/menu/weekend/badge-lock.png")
const SLOT_TEX := preload("res://assets/sprites/menu/weekend/reward-slot.png")
const RIBBON_GOLD := "gold"
const RIBBON_SLATE := "slate"
## 缎带: [贴图, 左右九宫格边距(原图像素), 中间那条带子的高(原图像素, 标题字压在带子上)]。
const RIBBON := {
	"gold": [preload("res://assets/sprites/menu/weekend/ribbon-gold.png"), 26, 20],
	"slate": [preload("res://assets/sprites/menu/weekend/ribbon-slate.png"), 18, 19],
}
## 像素画只按整数倍放大(非整数倍会出现粗细不一的像素)。
const PX := 3
## 压灰徽章(没晋级 / 被拦): 去饱和 + 压暗, 不另画一套灰图。
const DIM_SHADER := "shader_type canvas_item;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat g = dot(c.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR = vec4(vec3(g) * 0.62, c.a);\n}\n"

const NODE_NAME := "WeekCloseCard"
const KIND_RANKED_IN := "ranked_in"
const KIND_RANKED_OUT := "ranked_out"
const KIND_GAUNTLET_IN := "gauntlet_in"
const KIND_GAUNTLET_CUT := "gauntlet_cut"
## 按钮去处(主菜单按它接场景)
const DOOR_NONE := ""
const DOOR_BOARD := "board"        # 全场赛况(闯关赛)
const DOOR_BRACKET := "bracket"    # 对阵图(决赛日)

const TXT_CLAIM := "领取"
const TXT_OK := "确定"
const TXT_CLOSE := "关闭"
const TXT_WATCH := "观战"
const TXT_BRACKET := "查看对阵图"
## 下一次机会(周一休赛 ⇒ 下一轮积分赛是周二)。收盘卡与拦截提示共用这一句。
const TXT_NEXT_WEEK := "下一轮积分赛：下周二开始。"
const BODY_W := 640.0
const BTN_SIZE := Vector2(168, 81)


## 这一刻该弹哪几张, 按先后。★纯函数(gs 可以是门禁造的替身, 只读字段 / 调那几个查询)。
## ★存档还没滚到这一周(`week_anchor_ts` ≠ 本周锚点)⇒ 一张都不弹: 那时 promoted / 战绩还是上一周的。
static func due(gs, now: int) -> Array:
	var a: int = _P2.week_anchor_utc(now)
	if gs == null or int(gs.week_anchor_ts) != a:
		return []
	var out: Array = []
	if now >= _P2.ranked_close_ts(a) and int(gs.close_card_ranked_wk) != a and _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		if bool(gs.promoted):
			out.append(KIND_RANKED_IN)
		elif int(gs.ranked_used) > 0:
			out.append(KIND_RANKED_OUT)
	if now >= _P2.gauntlet_close_ts(a) and int(gs.close_card_gauntlet_wk) != a and bool(gs.promoted):
		var w: int = int(gs.gauntlet_wins)
		var l: int = int(gs.gauntlet_losses)
		var st: String = _P2.gauntlet_state(w, l)
		if st == _P2.GAUNTLET_IN:
			out.append(KIND_GAUNTLET_IN)
		elif st == _P2.GAUNTLET_RUNNING and w + l > 0:
			out.append(KIND_GAUNTLET_CUT)
	return out


## 记「本周这张弹过了」。★在弹出那一刻记(不是关掉时): 杀进程不会让同一张再弹一次; 钱早已入账, 不会少。
static func mark_seen(gs, kind: String, now: int) -> void:
	var a: int = _P2.week_anchor_utc(now)
	if kind == KIND_RANKED_IN or kind == KIND_RANKED_OUT:
		gs.close_card_ranked_wk = a
	else:
		gs.close_card_gauntlet_wk = a


## 积分赛本周战绩: 胜 = 赛季胜场 − 闯关胜场(周六的胜场也记进 season_wins); 负 = 掉了几条命(只有积分赛输了掉命)。
static func ranked_record(gs) -> Vector2i:
	var w: int = maxi(0, int(gs.season_wins) - int(gs.gauntlet_wins))
	var l: int = maxi(0, int(_P2.HEARTS_MAX) - int(gs.hearts))
	return Vector2i(w, l)


## 一张卡的内容: {kind, title, ribbon, badge, dim, lock, record_cap, record:[胜, 负] 或 [], status, body:[段],
##   coins, xp, primary:[字, 去处], secondary:[字, 去处] 或 []}。
## ★2026-10-26 美术重做(方案书 docs/plans/20261026c-周末弹窗美术.md, 逐秒参考 docs/plans/ref/20261026-周末弹窗商业参考.md):
##   照荒野乱斗战队联赛「周结束后登录」那一串, 一屏一件事:
##   ① 整屏「积分赛已结束」+ 本站徽章, 自动过(StageCeremony; ceremony_badge / ceremony_title);
##   ② 这张卡: 缎带标题「积分赛战绩」+ 战绩大字 + 一句状态 + 规则小字 + 奖励格 + 按钮;
##   ③ 领取 ⇒ 回主菜单币飞进钱包(CoinFly)。
##   ★晋级的庆祝(徽章变身)在晋级那一局的结算屏上演过了(battle_hud._promotion_moment), 这里只平实说结果、不再演一遍。
static func spec(kind: String, gs, now: int) -> Dictionary:
	var a: int = _P2.week_anchor_utc(now)
	var g_close: int = _P2.gauntlet_close_ts(a)
	var seat: int = _P2.finals_seat_ts(a)
	var d := {"kind": kind, "title": "", "ceremony_badge": "", "ceremony_title": "",
		"ribbon": RIBBON_SLATE, "badge": "", "dim": false, "lock": false,
		"record_cap": "", "record": [], "status": "", "body": [], "coins": 0, "xp": 0,
		"primary": [TXT_OK, DOOR_NONE], "secondary": []}
	match kind:
		KIND_RANKED_IN:
			var r := ranked_record(gs)
			var bf: Dictionary = gs.backfill_summary()
			var n: int = int(bf.get("games", 0))
			d["ceremony_badge"] = _P2.PHASE_RANKED
			d["ceremony_title"] = "积分赛已结束"
			d["title"] = "积分赛战绩"
			d["ribbon"] = RIBBON_GOLD
			d["record"] = [r.x, r.y]
			d["status"] = "已晋级周六闯关赛"
			if n > 0:
				(d["body"] as Array).append("未进行场次奖励（积分赛每周 %d 场，未进行的 %d 场按场发放）" % [int(_P2.RANKED_QUOTA), n])
			if now < g_close:
				(d["body"] as Array).append("闯关赛：%d 胜晋级决赛日，%d 负淘汰，%s 截止。" % [
					int(_P2.GAUNTLET_WINS_IN), int(_P2.GAUNTLET_LOSSES_OUT), _P2.local_wd_hhmm(g_close)])
			if n > 0:
				d["coins"] = int(bf.get("coins", 0))
				d["xp"] = int(bf.get("xp", 0))
				d["primary"] = [TXT_CLAIM, DOOR_NONE]
		KIND_RANKED_OUT:
			var r2 := ranked_record(gs)
			d["ceremony_badge"] = _P2.PHASE_RANKED
			d["ceremony_title"] = "积分赛已结束"
			d["title"] = "积分赛战绩"
			d["dim"] = true
			d["record"] = [r2.x, r2.y]
			if bool(gs.is_eliminated()):
				d["status"] = "生命已耗尽，未晋级闯关赛"
			else:
				d["status"] = "距晋级还差 %d 胜，未晋级闯关赛" % maxi(1, int(_P2.PROMOTE_WINS) - r2.x)
			if now < g_close:
				(d["body"] as Array).append("闯关赛与决赛日开放观战。" + TXT_NEXT_WEEK)
				d["primary"] = [TXT_WATCH, DOOR_BOARD]
			else:
				(d["body"] as Array).append("决赛日开放观战。" + TXT_NEXT_WEEK)
				d["primary"] = [TXT_WATCH, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
		KIND_GAUNTLET_IN:
			## ★2026-10-26 「省下的场次」在第 4 胜那一刻就发了、结算屏上说过(GameState.gauntlet_promote_bonus),
			##   这张卡只提醒决赛日几点开始, 不再发奖励(否则同一笔钱领两遍的样子)。
			d["ceremony_badge"] = _P2.PHASE_GAUNTLET
			d["ceremony_title"] = "闯关赛已结束"
			d["title"] = "闯关赛战绩"
			d["ribbon"] = RIBBON_GOLD
			d["record"] = [int(gs.gauntlet_wins), int(gs.gauntlet_losses)]
			d["status"] = "已晋级周日决赛日"
			if now < seat:
				(d["body"] as Array).append("决赛日%s：%s 开始。" % [_P2.STAGE_GROUP, _P2.local_wd_hhmm(seat)])
			else:
				(d["body"] as Array).append("决赛日已开始，比赛在对阵图中进行。")
			d["primary"] = [TXT_BRACKET, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
		KIND_GAUNTLET_CUT:
			d["ceremony_badge"] = _P2.PHASE_GAUNTLET
			d["ceremony_title"] = "闯关赛已结束"
			d["title"] = "闯关赛战绩"
			d["dim"] = true
			d["record"] = [int(gs.gauntlet_wins), int(gs.gauntlet_losses)]
			d["status"] = "闯关赛已于%s 截止，未晋级决赛日" % _P2.local_wd_hhmm(g_close)
			d["body"] = ["决赛日开放观战。" + TXT_NEXT_WEEK]
			d["primary"] = [TXT_WATCH, DOOR_BRACKET]
			d["secondary"] = [TXT_CLOSE, DOOR_NONE]
	return d


## 建卡挂到 host 上。on_done(door: String, from_pos: Vector2) 在点了按钮、卡关掉之后调:
##   door = 按钮的去处(DOOR_*), from_pos = 奖励行那枚币的画布坐标(点「领取」时飞币的起点; 其它按钮 = (-1, -1))。
static func open(host: Node, d: Dictionary, on_done: Callable) -> Control:
	var ov := ColorRect.new()
	ov.name = str(d.get("node_name", NODE_NAME))
	ov.color = Color(0, 0, 0, 0.6)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_meta("kind", str(d.get("kind", "")))
	## 整张卡 = 缎带(骑在框上沿) + 框。缎带画在框上面(z_index), 下半截压住框的上边。
	var card := VBoxContainer.new()
	card.name = "Box"
	card.anchor_left = 0.5; card.anchor_top = 0.5; card.anchor_right = 0.5; card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH; card.grow_vertical = Control.GROW_DIRECTION_BOTH
	ov.add_child(card)
	var title_txt: String = str(d.get("title", ""))
	var rib: Control = null
	if title_txt != "":
		rib = _ribbon(title_txt, str(d.get("ribbon", RIBBON_SLATE)))
		card.add_child(rib)
		card.add_theme_constant_override("separation", -int(rib.custom_minimum_size.y * 0.5))
	var box := PanelContainer.new()
	box.name = "Frame"
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#16213a")
	bsb.set_border_width_all(0)
	bsb.set_corner_radius_all(0)
	var bframe := UISkin.nine("panel-frame.png", 20, bsb)
	bframe.content_margin_left = 44; bframe.content_margin_right = 44
	bframe.content_margin_top = (24 + int(rib.custom_minimum_size.y * 0.5)) if rib != null else 30
	bframe.content_margin_bottom = 28
	box.add_theme_stylebox_override("panel", bframe)
	card.add_child(box)
	if rib != null:
		rib.z_index = 1
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(vb)
	var badge_key: String = str(d.get("badge", ""))
	if BADGE_TEX.has(badge_key):
		vb.add_child(_badge(badge_key, bool(d.get("dim", false)), bool(d.get("lock", false))))
	var rec: Array = d.get("record", []) as Array
	if rec.size() == 2:
		vb.add_child(_record(str(d.get("record_cap", "")), int(rec[0]), int(rec[1])))
	var st_txt: String = str(d.get("status", ""))
	if st_txt != "":
		var st := Label.new()
		st.name = "Status"
		st.text = st_txt
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.add_theme_font_size_override("font_size", 26)
		st.add_theme_color_override("font_color", Color("#9fb3c8") if bool(d.get("dim", false)) else Color("#ffd93d"))
		st.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		st.add_theme_constant_override("outline_size", 5)
		vb.add_child(st)
	var bi := 0
	for para in (d.get("body", []) as Array):
		var l := Label.new()
		l.name = "Body%d" % bi
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		## 拦截卡没有战绩行: 第一句就是要说的事, 用正文大字; 收盘卡的正文都是规则小字。
		var lead: bool = bi == 0 and rec.is_empty()
		var fs: int = 22 if lead else 19
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", Color("#f2ead8") if lead else Color("#b9c4d2"))
		var lay: Array = sentence_lines(l, str(para), fs)
		l.text = str(lay[0])
		l.custom_minimum_size = Vector2(float(lay[1]), 0)
		vb.add_child(l)
		bi += 1
	var coin_icon: Control = null
	if int(d.get("coins", 0)) > 0 or int(d.get("xp", 0)) > 0:
		var rr := HBoxContainer.new()
		rr.name = "Rewards"
		rr.alignment = BoxContainer.ALIGNMENT_CENTER
		rr.add_theme_constant_override("separation", 18)
		vb.add_child(rr)
		if int(d.get("coins", 0)) > 0:
			var cs: Control = _reward_slot(COIN_TEX, "深海币", "+%d" % int(d["coins"]), Color("#ffd93d"), "CoinAmount", "CoinIcon")
			coin_icon = cs.find_child("CoinIcon", true, false) as Control
			rr.add_child(cs)
		if int(d.get("xp", 0)) > 0:
			rr.add_child(_reward_slot(XP_TEX, "经验", "+%d" % int(d["xp"]), Color("#8fe0ff"), "XpAmount", "XpIcon"))
	var bh := HBoxContainer.new()
	bh.name = "Buttons"
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 18)
	vb.add_child(bh)
	var btns: Array = [d.get("primary", [])]
	if not (d.get("secondary", []) as Array).is_empty():
		btns.append(d["secondary"])
	for i in range(btns.size()):
		var spec_b: Array = btns[i]
		if spec_b.is_empty():
			continue
		var b := Button.new()
		b.name = "Primary" if i == 0 else "Secondary"
		b.text = str(spec_b[0])
		b.custom_minimum_size = BTN_SIZE
		b.add_theme_font_size_override("font_size", 24)
		UISkin.card_button(b)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		bh.add_child(b)
		var door: String = str(spec_b[1])
		var claim: bool = str(spec_b[0]) == TXT_CLAIM
		b.pressed.connect(func() -> void:
			## ★领取: 先记下币的位置(卡一关它就没了), 再关卡, 再交给主菜单去飞。
			var from_icon: Control = coin_icon if claim else null
			var from_pos: Vector2 = from_icon.get_global_rect().get_center() if from_icon != null and is_instance_valid(from_icon) else Vector2(-1, -1)
			ov.queue_free()
			on_done.call(door, from_pos))
	host.add_child(ov)
	## 弹入: 卡从 0.85 放大到 1(与结算屏大字同一种 BACK 缓动), 压暗淡入。时长走 UIPalette 节拍表(tools/ui_tempo_audit.py)。
	card.pivot_offset = card.size / 2.0
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)
	card.scale = Vector2(0.85, 0.85)
	ov.modulate.a = 0.0
	var tw := ov.create_tween().set_parallel(true)
	tw.tween_property(ov, "modulate:a", 1.0, UIPalette.T_BASE)
	tw.tween_property(card, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return ov


## 标题缎带: 九宫格横向拉伸到标题宽, 整数倍放大; 标题字压在中间那条带子上。
static func _ribbon(txt: String, which: String) -> Control:
	var r: Array = RIBBON.get(which, RIBBON[RIBBON_SLATE]) as Array
	var tex: Texture2D = r[0]
	var m: int = int(r[1])
	var band_h: int = int(r[2])
	var lab := Label.new()
	lab.name = "Title"
	lab.text = txt
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 32)
	UISkin.title_label(lab, 36)
	lab.add_theme_color_override("font_color", Color("#fff6dc"))
	lab.add_theme_color_override("font_outline_color", Color("#2a1406") if which == RIBBON_GOLD else Color("#0c1220"))
	lab.add_theme_constant_override("outline_size", 7)
	var f: Font = lab.get_theme_font("font")
	var tf: Font = UISkin.title_font() if UISkin.title_font() != null else f
	var tw: float = tf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.get_theme_font_size("font_size")).x if tf != null else 200.0
	## 原图像素宽: 两端边距 + 标题宽(放大前) + 左右各留 6 像素
	var w_src: int = 2 * m + int(ceil(tw / float(PX))) + 12
	var holder := Control.new()
	holder.name = "Ribbon"
	holder.custom_minimum_size = Vector2(w_src * PX, tex.get_height() * PX)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = m
	np.patch_margin_right = m
	np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	np.size = Vector2(w_src, tex.get_height())
	np.scale = Vector2(PX, PX)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(np)
	lab.position = Vector2.ZERO
	lab.size = Vector2(w_src * PX, band_h * PX)
	holder.add_child(lab)
	return holder


## 赛事徽章: 整数倍放大居中; 没晋级 / 被拦 ⇒ 压灰; 被拦再挂一把锁在右下角。
static func _badge(key: String, dim: bool, lock: bool) -> Control:
	var tex: Texture2D = BADGE_TEX[key]
	var holder := Control.new()
	holder.name = "Badge"
	holder.custom_minimum_size = Vector2(tex.get_width() * PX, tex.get_height() * PX)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta("badge", key)
	var tr := TextureRect.new()
	tr.name = "BadgeArt"
	tr.texture = tex
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = holder.custom_minimum_size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		var sh := Shader.new()
		sh.code = DIM_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		tr.material = mat
	holder.add_child(tr)
	if lock:
		var lk := TextureRect.new()
		lk.name = "BadgeLock"
		lk.texture = LOCK_TEX
		lk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lk.stretch_mode = TextureRect.STRETCH_SCALE
		lk.size = Vector2(LOCK_TEX.get_width() * PX, LOCK_TEX.get_height() * PX)
		lk.position = holder.custom_minimum_size - lk.size + Vector2(PX * 4, PX * 2)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(lk)
	return holder


## 战绩: 小字说明在上, 「12 胜 1 负」大字在下(胜金色、负灰色, 数字比单位大一号)。
static func _record(cap: String, w: int, l: int) -> Control:
	var v := VBoxContainer.new()
	v.name = "Record"
	v.add_theme_constant_override("separation", -4)
	if cap != "":
		var c := Label.new()
		c.name = "RecordCap"
		c.text = cap
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_theme_font_size_override("font_size", 18)
		c.add_theme_color_override("font_color", Color("#9fb3c8"))
		v.add_child(c)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	for part in [[str(w), 48, Color("#ffd93d"), "RecordW"], ["胜", 26, Color("#f2ead8"), ""],
			[str(l), 48, Color("#dfe6ee"), "RecordL"], ["负", 26, Color("#f2ead8"), ""]]:
		var lb := Label.new()
		if str(part[3]) != "":
			lb.name = str(part[3])
		lb.text = str(part[0])
		lb.add_theme_font_size_override("font_size", int(part[1]))
		lb.add_theme_color_override("font_color", part[2])
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lb.add_theme_constant_override("outline_size", 6)
		lb.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(lb)
	return v


## 正文怎么折行: 返回 [要显示的字, 标签宽]。
##   ① 一行放得下 ⇒ 一行;
##   ② 放不下 ⇒ 在句号处换行(每句各占一行, 句子短的拼在一起), 不在词中间断开(实拍:「本周未晋 / 级」);
##   ③ 某一句本身就放不下 ⇒ 按「行数均分」的宽交给引擎折(+ 两个字的余量), 不让最后一行只剩一两个字(实拍:「未能晋级闯关 / 赛。」)。上限 BODY_W。
static func sentence_lines(l: Label, txt: String, fs: int) -> Array:
	var f: Font = l.get_theme_font("font")
	if f == null:
		return [txt, BODY_W]
	var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w <= BODY_W:
		return [txt, maxf(360.0, ceilf(w) + 4.0)]
	var parts: PackedStringArray = txt.split("。", false)
	var sents: Array = []
	for i in range(parts.size()):
		sents.append(parts[i] + ("。" if i < parts.size() - 1 or txt.ends_with("。") else ""))
	var lines: Array = []
	var cur := ""
	var widest := 0.0
	for s in sents:
		if f.get_string_size(str(s), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BODY_W:
			var n: int = int(ceil(w / BODY_W))
			return [txt, minf(BODY_W, ceilf(w / float(n)) + fs * 2.0)]
		var tryline: String = cur + str(s)
		if cur != "" and f.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BODY_W:
			lines.append(cur)
			cur = str(s)
		else:
			cur = tryline
	if cur != "":
		lines.append(cur)
	for ln in lines:
		widest = maxf(widest, f.get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return ["\n".join(PackedStringArray(lines)), maxf(360.0, ceilf(widest) + 4.0)]


## 奖励格: 格框(整数倍放大) + 图标撑满 + 数量压在格子下沿(皇室战争「You Got」那种) + 名称小字。
static func _reward_slot(icon: Texture2D, cap: String, val: String, col: Color, amt_name: String, icon_name: String) -> Control:
	var side: float = float(SLOT_TEX.get_width() * PX)
	var s := Control.new()
	s.custom_minimum_size = Vector2(side, side + 36.0)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fr := TextureRect.new()
	fr.texture = SLOT_TEX
	fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fr.stretch_mode = TextureRect.STRETCH_SCALE
	fr.size = Vector2(side, side)
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(fr)
	var ic := TextureRect.new()
	ic.name = icon_name
	ic.texture = icon
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.position = Vector2(12.0, 8.0)
	ic.size = Vector2(side - 24.0, side - 24.0)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(ic)
	var n := Label.new()
	n.name = amt_name
	n.text = val
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 28)
	n.add_theme_color_override("font_color", col)
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	n.add_theme_constant_override("outline_size", 7)
	n.position = Vector2(0.0, side - 26.0)
	n.size = Vector2(side, 38.0)
	s.add_child(n)
	## 名称小字在格子下面(新玩家不一定认得图标)。
	var c := Label.new()
	c.text = cap
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_theme_font_size_override("font_size", 17)
	c.add_theme_color_override("font_color", Color("#9fb3c8"))
	c.position = Vector2(-20.0, side + 12.0)
	c.size = Vector2(side + 40.0, 24.0)
	s.add_child(c)
	return s
