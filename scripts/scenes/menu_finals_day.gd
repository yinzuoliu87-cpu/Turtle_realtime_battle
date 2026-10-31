extends RefCounted
class_name MenuFinalsDay
## 周日决赛日的主菜单(2026-10-31 · 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M ①②③⑦⑧ · P17 / P18 / P19 / G14 / G15 / G17 / G21)。
## 从 MainMenuScene 拆出来(那边有 3000 行上限 `tools/arch_budget.py`): 构造注入主菜单, 那边只剩几行转调。由 MenuWeekend 持有(`_wk().fd`)。
##   · 「今天的事」卡(scripts/ui/finals_day_card.gd): 状态带三态 + 小组赛 / 冠军杯赛两张子卡各自倒计时 + 我这一路格子条 + 上周冠军;
##     整张点了直达对阵图(P19)。摆在右栏训龟大师上面, 与主按钮读成一组。
##   · 主按钮(P17 最大位置不再是上锁的「开始战斗」): 晋级者「我的比赛」/ 其他人「观看开播」(赛事结束后「查看结果」), 下面一行我的处境;
##     开播中 ⇒ 点了直达正在播的那一场(G17 / 5-10, 不先停在对阵图); 其余 ⇒ 对阵图。
##     皮与「开始战斗」同一块(木框 + 亮黄面 + 呼吸光晕 MenuCtaGlow + 选龟页出战键那道扫光 TsMotion.sheen)。
##   · 模式卡: 17:30 收盘后也带倒计时 / 当前阶段(`band_text`, 赛程页决赛日那张卡同一句)(P18)。
##   · 每秒一拍(`tick`, 主菜单 `_sb_poll` 转调): 卡 / 副标跟着时刻与赛果走; 阶段一变副标闪一下; 跨 18:00 / 20:00 飘一句。
##   · 收盘补看(`start` → finals_day_recap, G21): 没守到最后的人下次打开先补冠军 → 名次 → 我的几轮。
## ★周一到周六一个字都不动: `hero_on` 只在 UTC 周日成立(周日上午只对已晋级的人 —— 他今天的事就是 18:00 的小组赛)。
##   门禁 verify_menu_finals_hero 拿改动前的主菜单源码现编一份, 七天逐天比主按钮 / 模式卡。
## ★判据全在 finals_day_model(全局小条 / 30 秒弹窗 / 跑马灯读同一份); 「现在」一律由调用方传进来(主菜单一屏只读一次钟)。
## ★不剧透: 赛果只认已揭晓的(开播中 / 即将开播那几场不算) —— 原来的试做直接读 `done`, 18:05 我那场还在开播主菜单就写「已止步」。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _TSM := preload("res://scripts/scenes/team_select/ts_motion.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _F := preload("res://scripts/ui/finals_day_feed.gd")
const _W := preload("res://scripts/ui/finals_day_watch.gd")
const _CARD := preload("res://scripts/ui/finals_day_card.gd")
const _RC := preload("res://scripts/ui/finals_day_recap.gd")

## 节点名(门禁按名字找)
const N_HERO := "FinalsHero"
const N_TITLE := "FinalsHeroTitle"
const N_SUB := "FinalsHeroSub"

## 主按钮按身份(G14): 晋级者 / 其他人(赛事结束后改「查看结果」—— 没东西可看还写「观看开播」是骗人)
const TXT_MINE := "我的比赛"
const TXT_WATCH := "观看开播"
const TXT_RESULT := "查看结果"
## 模式卡第二行的读数(「决赛日 · 」后半句; 主菜单 `_finals_status_line` 拼)
const TXT_W_IN := "已晋级"
const TXT_W_OUT := "已止步"
const TXT_W_CHAMP := "冠军杯赛冠军"

## 卡的位置(主菜单 content_root 坐标): 右栏、训龟大师正上方, 右沿与主按钮同轴。
##   ★顶沿 196: 绑定提示条的点击区底沿 195(menu `_nudge_strip`: 114 + 81)。底沿 468 = 训龟大师顶沿 478 − 10。
const CARD_TOP := 196.0

const TITLE_FONT := 36
const SUB_FONT := 20
## 大字 / 副标中线在亮黄面高度的几分之几处(面 88 高 ⇒ 第 32 / 70 像素)。
##   ★两行的行框都要落在亮黄面去掉 5px 边带之内(verify_ui_consistency「文字压边带」)。
const TITLE_MID := 0.364
const SUB_MID := 0.795
## 「刚亮起 / 阶段切换」那一下(与选龟页出战键刚能点时同一组数: 先冲到很亮再落回)
const FLASH_GLOW := Color(2.0, 1.8, 1.3, 1.0)
const FLASH_FACE := Color(1.35, 1.3, 1.15, 1.0)
const FLASH_SUB := Color(1.9, 1.75, 1.3, 1.0)
## 我那一组 / 冠军杯赛打着的时候主菜单开着也要知道结果: 隔这么久(秒)再问一次。
const REFETCH_SEC := 30
## 缓存里那份赛果收包时刻离「现在」超过这么久 ⇒ 当成别的周留下的, 不用。
const STALE_SEC := 4 * 86400

var menu                                   # MainMenuScene
## 【门禁注入点】{"group": 我那一组, "cup": 冠军杯赛, "groups": [本周各组]}。空 = 读 Supabase 缓存(玩家路径)。
var feed_override: Dictionary = {}
## 门禁读: 阶段切换闪过几次 / 飘过几句 / 主按钮最近一次点了去哪
var flashes := 0
var announced: Array = []
var last_go := ""
var card = null
var _hero: Control = null
var _title: Label = null
var _sub: Label = null
var _glow: Control = null
var _shown := ""                           # 主按钮此刻画的是哪一步(阶段签名)
var _good: Dictionary = {}                 # 最近一份好的三份数据(主菜单开屏那次头衔账会先清缓存再问, 这里留着不闪回空)
var _next_fetch := 0


func _init(m) -> void:
	menu = m


# ══════════════════════════════ 读数 ══════════════════════════════

## 主按钮换不换成决赛日那一颗。★只有 UTC 周日: 17:30 收盘后人人都换; 上午只换已晋级的人(其余人上午还在打闯关赛)。
func hero_on(now: int) -> bool:
	if _P2.iso_weekday_utc(now) != 7 or not menu._finals_live():
		return false
	var ph: String = _P2.phase_at_utc(now)
	if ph == _P2.PHASE_FINALS:
		return true
	return ph == _P2.PHASE_GAUNTLET and entered()


func entered() -> bool:
	return str(GameState.gauntlet_state()) == _P2.GAUNTLET_IN


## 三份数据: {"group", "cup", "groups"}。缓存一时被清空(开屏那次头衔账)⇒ 用上一份好的。
func feeds(now: int = 0) -> Dictionary:
	if not feed_override.is_empty():
		return {"group": feed_override.get("group", {}), "cup": feed_override.get("cup", {}), "groups": feed_override.get("groups", [])}
	var f: Dictionary = _F.feeds()
	for k in ["group", "cup"]:
		if int((f[k] as Dictionary).get("size", 0)) >= 1:
			_good[k] = f[k]
		elif _good.has(k) and (now <= 0 or absi(now - int((_good[k] as Dictionary).get("recv_at", now))) < STALE_SEC):
			f[k] = _good[k]
	if not (f["groups"] as Array).is_empty():
		_good["groups"] = f["groups"]
	elif _good.has("groups"):
		f["groups"] = _good["groups"]
	return f


## 主按钮此刻: {"title", "sub", "sig"(阶段签名: 变了才闪), "target"(点了去看哪一场; 空 = 对阵图)}。
func hero_state(now: int) -> Dictionary:
	var f := feeds(now)
	var group: Dictionary = f["group"]
	var cup: Dictionary = f["cup"]
	var groups: Array = f["groups"]
	var ent := entered()
	var ph := _M.phase(now, groups, cup)
	var mn: Dictionary = _M.my_next(ent, group, cup, now)
	var k := str(mn.get("k", ""))
	var at := int(mn.get("at", 0))
	var end := _M.path_end(_M.path_cells(ent, group, cup, groups, now))
	var out := {"title": TXT_MINE if ent else (TXT_RESULT if ph == _M.PH_DONE else TXT_WATCH), "sub": "", "target": {}}
	var rn := ""
	if not (mn.get("b", {}) as Dictionary).is_empty() and int(mn.get("r", 0)) >= 1:
		rn = _M.round_name(int((mn["b"] as Dictionary).get("size", 0)), int(mn["r"]))
	match k:
		_M.K_SHOP:
			out["sub"] = "%s备战中 · 还剩 %s" % [rn, _M.clock_text(at - now)]
		_M.K_UPCOMING:
			out["sub"] = "%s %s 开播" % [rn, _P2.local_hhmm(at)]
		_M.K_LIVE:
			out["sub"] = "%s开播中 · 点击观看" % rn
			out["target"] = mn
		_M.K_NEXT:
			out["sub"] = "%s备战 %s 开始" % [rn, _P2.local_hhmm(at)]
		_M.K_WAIT:
			out["sub"] = "%s即将开播" % rn
		_M.K_CUP_WAIT:
			out["sub"] = "%s %s 开赛" % [_P2.STAGE_CUP, _P2.local_hhmm(at)]
	if str(out["sub"]) == "":
		var live: Array = _M.live_all(groups, cup, now)
		var mine := int(group.get("bucket", -9))
		live.sort_custom(func(a, b): return int((a["b"] as Dictionary).get("bucket", 0)) == mine and int((b["b"] as Dictionary).get("bucket", 0)) != mine)
		## 开赛前 / 两段之间: 倒计时只在卡上那张子卡里数(带秒、在走), 主按钮不再重复一遍(一屏一个倒计时)
		if ph == _M.PH_PRE:
			out["sub"] = "%s %s 开赛" % [_P2.STAGE_GROUP, _P2.local_hhmm(_M.seat_ts(now))]
		elif end == 1:
			out["sub"] = "已夺得%s冠军" % _P2.STAGE_CUP
		elif ph == _M.PH_DONE:
			## 冠军是谁写在卡上那一行 + 全局小条上, 主按钮不再说第三遍
			out["sub"] = "%s已结束" % _P2.STAGE_CUP
		elif not live.is_empty():
			var t: Dictionary = live[0]
			out["sub"] = ("%s开播中" % _M.stage_line(t["b"], int(t["r"]))) if live.size() == 1 else ("%d 场开播中 · 点击观看" % live.size())
			out["target"] = t
		elif ph == _M.PH_INTER:
			out["sub"] = ("已止步 · " if end == -1 else "") + "%s %s 开赛" % [_P2.STAGE_CUP, _P2.local_hhmm(_M.cup_ts(now))]
		else:
			var nx: Dictionary = _M.next_all(groups, cup, now)
			var tail := ("下一场 %s 开播" % _P2.local_hhmm(int(nx["at"]))) if not nx.is_empty() else ("%s进行中" % (_P2.STAGE_CUP if ph == _M.PH_CUP else _P2.STAGE_GROUP))
			out["sub"] = ("已止步 · %s" % tail) if end == -1 else tail
	out["sig"] = "%s|%s|%d" % [ph, k, end]
	return out


## 模式卡上沿那一格(= 赛程页决赛日那张卡的时间, 都走主菜单 `_mode_countdown`)。17:30 收盘后也是倒计时 / 当前阶段(P18)。
func band_text(now: int) -> String:
	var seat: int = _M.seat_ts(now)
	var cup: int = _M.cup_ts(now)
	if now < seat:
		return "距%s开始 %s" % [_P2.STAGE_GROUP, menu._left_text(seat - now)]
	if now < cup:
		return "距%s开始 %s" % [_P2.STAGE_CUP, menu._left_text(cup - now)]
	if _M.champion_visible(feeds(now)["cup"], now) >= 0:
		return "%s已结束" % _P2.STAGE_CUP
	return "%s进行中" % _P2.STAGE_CUP


## 模式卡第二行(进了决赛日的人)「决赛日 · 」后半句: 跟着赛果走(只认已揭晓的)。
func entered_word(now: int) -> String:
	var f := feeds(now)
	var cells: Array = _M.path_cells(true, f["group"], f["cup"], f["groups"], now)
	var end := _M.path_end(cells)
	if end == 1:
		return TXT_W_CHAMP
	if end == -1:
		return TXT_W_OUT
	for c in cells:
		if str(c["sec"]) == "group" and str(c["st"]) == _M.C_WON and int(c["r"]) == _group_rounds(cells):
			return "%s%s" % [TXT_W_IN, _P2.STAGE_CUP]
	if bool(GameState.finals_champion):
		return "%s%s" % [TXT_W_IN, _P2.STAGE_CUP]
	return TXT_W_IN


static func _group_rounds(cells: Array) -> int:
	var n := 0
	for c in cells:
		if str(c["sec"]) == "group":
			n += 1
	return n


# ══════════════════════════════ 主按钮 + 卡 ══════════════════════════════

## `_build_page_buttons` 建「开始战斗」之前调: 今天是决赛日 ⇒ 建卡 + 决赛日那一颗, 返回 true(调用方不再建「开始战斗」)。
func build_hero(now: int) -> bool:
	_hero = null
	_title = null
	_sub = null
	_glow = null
	card = null
	_shown = ""
	if not hero_on(now):
		return false
	## 「今天的事」卡: 右栏训龟大师上面(进 page_box: 重建那一栏时一起清)
	card = _CARD.new(menu._bold_font())
	card.position = Vector2(float(menu.HERO_POS.x), CARD_TOP)
	menu.page_box.add_child(card)
	var tap := Button.new()
	tap.name = _CARD.N_TAP
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	tap.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	tap.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	tap.mouse_entered.connect(func() -> void: card.modulate = Color(1.1, 1.08, 1.03))
	tap.mouse_exited.connect(func() -> void: card.modulate = Color.WHITE)
	tap.pressed.connect(Callable(menu, "_open_bracket_map"))
	card.add_child(tap)
	card.on_wall = Callable(self, "open_wall")
	card.paint(now, entered(), feeds(now))
	## 卡的整张点击区在最底下; 「冠军墙」那颗(paint 里建)要叠在它上面
	card.move_child(tap, 1)
	menu._slide_in(card, 3)
	var size: Vector2 = menu.HERO_SIZE
	var inset: Vector2 = menu.HERO_FACE_INSET
	## 同一块皮: 木框 + 亮黄面(primary), 字自己排两行。点 = `on_hero`(具名方法, 门禁看得到去处)。
	var h: Control = menu._frame_button("", Callable(self, "on_hero"), false, size, int(menu.FONT_HERO), "", false, true)
	h.name = N_HERO
	h.position = menu.HERO_POS
	var face := Rect2(inset, size - inset * 2.0)
	## 两行按字的中线排(Label 的框会被字体行高撑大, 按框排会叠): 大字中线在面高 1/3, 副标在 4/5。
	_title = _line(N_TITLE, TITLE_FONT, 12, face, face.position.y + face.size.y * TITLE_MID)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_constant_override("shadow_outline_size", 12)
	h.add_child(_title)
	_sub = _line(N_SUB, SUB_FONT, 7, face, face.position.y + face.size.y * SUB_MID)
	h.add_child(_sub)
	menu._hero_btn = h
	menu._hero_locked = false
	menu.page_box.add_child(h)
	## 就绪光: 呼吸光晕(与「开始战斗」同一个)+ 面上隔几秒一道扫光(选龟页出战键那一道)+ 落定那一下闪一次。
	_glow = MenuCtaGlow.attach(h, size)
	_TSM.sheen(h, face, 0.6)
	menu._slide_in(h, 5)
	_hero = h
	_repaint(now, false)
	var tw := h.create_tween()
	tw.tween_interval(0.0 if menu._mq().quiet else 0.85 + 0.06 * 5.0 + 0.42)   # = `_slide_in(h, 5)` 落定的那一刻
	tw.tween_callback(_flash.bind(false))
	return true


## 一行字: 横向铺满亮黄面、居中; 竖向让字的中线落在 mid_y(框高取字体行高)。
func _line(nm: String, font: int, outline: int, face: Rect2, mid_y: float) -> Label:
	var l: Label = menu._menu_label("", font, Color("#fffaf0"))
	l.name = nm
	l.add_theme_color_override("font_outline_color", Color("#3a1a02"))
	l.add_theme_constant_override("outline_size", outline)
	l.set_anchors_preset(Control.PRESET_TOP_LEFT)
	## 框高取这套字体的行高再留几像素: 框比行高矮的话填字时会往下长, 字的中线就不在 mid_y 了。
	var hh: float = ceilf((menu._bold_font() as Font).get_height(font)) + 6.0
	l.size = Vector2(face.size.x, hh)
	l.position = Vector2(face.position.x, roundf(mid_y - hh / 2.0))
	l.pivot_offset = l.size / 2.0
	return l


## 点主按钮: 开播中 ⇒ 直达那一场(G17); 其余 ⇒ 对阵图。取不到录像 ⇒ 也去对阵图(那边有完整的状态句)。
func on_hero() -> void:
	var now: int = menu._now_ts()
	var t: Dictionary = hero_state(now).get("target", {})
	## ★只在自己就是 current_scene 时才真跳(门禁把主菜单挂成子节点量东西时, 跳了会把宿主的场景树换掉)。
	var real: bool = menu.get_tree() != null and menu.get_tree().current_scene == menu
	if not t.is_empty() and _W.can_open(t["b"], int(t["r"]), int(t["m"]), now):
		last_go = "watch"
		if not real:
			return
		if _W.open(menu.get_tree(), _P2.week_anchor_utc(now), t["b"], int(t["r"]), int(t["m"]), now, _W.BRACKET,
				func(code: String, _msg: String) -> void:
					if code != "" and is_instance_valid(menu) and menu.is_inside_tree():
						menu._open_bracket_map()):
			return
	last_go = "bracket"
	if real:
		menu._open_bracket_map()


## 冠军墙(块 D 的 ChampionWall: 历届冠军杯冠军一届一块铭牌)。只在主菜单真是当前这一屏时开(门禁挂子节点时只记一下)。
var walls := 0
func open_wall() -> void:
	walls += 1
	if menu.get_tree() == null or menu.get_tree().current_scene != menu:
		return
	ChampionWall.open(menu, {"loading": true}).load_weeks(_P2.week_anchor_utc(menu._now_ts()), 8)


## 字跟着「现在」走; 阶段变了(且不是刚建好那一下)⇒ 副标闪一下, 跨 18:00 / 20:00 ⇒ 飘一句。
func _repaint(now: int, animate: bool) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	var hs := hero_state(now)
	if _title.text != str(hs["title"]):
		_title.text = str(hs["title"])
	if _sub.text != str(hs["sub"]):
		_sub.text = str(hs["sub"])
	if card != null and is_instance_valid(card):
		card.paint(now, entered(), feeds(now))
	var st := str(hs["sig"])
	if st == _shown:
		return
	var prev := _shown
	_shown = st
	if animate and prev != "":
		_flash(true)
		_announce(prev, st)


## 亮一下: 光晕 / 亮黄面冲亮再落回(选龟页出战键刚能点时那一下); strong = 阶段切换, 副标也冲亮 + 弹一下。
func _flash(strong: bool) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	if strong:
		flashes += 1
	if _glow != null and is_instance_valid(_glow):
		_glow.self_modulate = FLASH_GLOW
		_glow.create_tween().tween_property(_glow, "self_modulate", Color.WHITE, UIPalette.T_SLOW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var face := _hero.get_node_or_null(str(menu.HERO_FACE_NAME)) as CanvasItem
	if face != null:
		face.modulate = FLASH_FACE
		face.create_tween().tween_property(face, "modulate", Color.WHITE, UIPalette.T_SLOW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if strong and _sub != null and is_instance_valid(_sub):
		_sub.modulate = FLASH_SUB
		_sub.scale = Vector2(1.12, 1.12)
		var tw := _sub.create_tween().set_parallel(true)
		tw.tween_property(_sub, "modulate", Color.WHITE, UIPalette.T_SLOW).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_sub, "scale", Vector2.ONE, UIPalette.T_TRANS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 跨 18:00 / 20:00(主菜单开着)⇒ 飘一句(对标笔记 C31)。人人都飘(没晋级的人也要知道开赛了), 按身份指主按钮上那几个字。
func _announce(prev: String, st: String) -> void:
	var p0 := prev.get_slice("|", 0)
	var s0 := st.get_slice("|", 0)
	var stage := ""
	if p0 == _M.PH_PRE and s0 != _M.PH_PRE:
		stage = _P2.STAGE_GROUP
	elif p0 in [_M.PH_GROUP, _M.PH_INTER] and s0 == _M.PH_CUP:
		stage = _P2.STAGE_CUP
	if stage == "":
		return
	var msg := "%s已开赛，点「%s」%s。" % [stage, TXT_MINE if entered() else TXT_WATCH, "查看" if entered() else "进入"]
	announced.append(msg)
	menu._toast(msg)


# ══════════════════════════════ 每秒一拍 ══════════════════════════════

## 主菜单 `_sb_poll` 每秒调一次(`now` = 那一拍的钟)。
func tick(now: int) -> void:
	## 17:30(闯关赛 → 决赛日)/ 周一 00:00 这种「换不换成决赛日那一颗」变了 ⇒ 重建主按钮那一栏(不重播滑入)。
	if menu.page_box != null and not MenuQueue.locked() and hero_on(now) != (_hero != null and is_instance_valid(_hero)):
		for c in menu.page_box.get_children():
			menu.page_box.remove_child(c)
			c.queue_free()
		menu._mq().quiet = true
		menu._build_page_buttons(now)
		menu._mq().quiet = false
		return
	_refetch(now)
	_repaint(now, true)


## 赛中隔一会儿再问一次(主菜单开屏那次头衔账问完就停了; 全局层只在玩家屏上问, 门禁 / 子节点挂法不问)。
func _refetch(now: int) -> void:
	if not _SB.enabled() or _hero == null or now < _next_fetch or not _M.is_finals_time(now):
		return
	if menu.get("_ft_timer") != null and is_instance_valid(menu.get("_ft_timer")):
		return
	_next_fetch = now + REFETCH_SEC
	_F.pull(now)


## 主菜单开屏调一次: 去问上周冠军(挂门面); 收盘后没守到最后 ⇒ 补看(等收盘卡 / 晋级仪式都弹完再出, 一次一件事)。
func start(now: int) -> void:
	if hero_on(now):
		_F.pull_prev_champ(now)
	if not menu._wk().cards_enabled():
		return
	while is_instance_valid(menu) and menu.is_inside_tree() \
			and (menu.get_node_or_null(StageCeremony.NODE_NAME) != null or menu.get_node_or_null(WeekCloseCard.NODE_NAME) != null
				or not (menu._wk().queue as Array).is_empty()):
		await menu.get_tree().process_frame
	if is_instance_valid(menu) and menu.is_inside_tree():
		_RC.maybe_show(menu, menu._now_ts())
