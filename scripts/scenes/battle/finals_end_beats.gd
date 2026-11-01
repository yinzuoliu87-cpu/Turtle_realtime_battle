extends RefCounted
## finals_end_beats.gd — 观战 / 回放每场结束: 分三拍走, 不是一张卡(方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C ②③④⑧ · G8 G18 G25 · P1 P16)。
##
## 用户 10-31 指着旧卡(「X 获胜 / A 对 B / 返回对阵图」三行)问「比如这个框，这是商业游戏吗」。商业做法(研究笔记 §二.2、§3.2):
##   ① 标语: 压在战场上的一个短词(看别人「X 获胜」/ 自己赢「胜利」/ 自己输「惜败」—— 压低, 不用大红字)
##   ② 双方结果: 两边都在画面里 —— 阵容卡并排, 阵亡的划掉, 赢家那张发光、输家压灰下沉; 中间比分逐路数上去, 下面三路灯一路一盏
##   ③ 我的处境: 自己赢 = 晋级 + 本轮奖励(+8 深海币 +2 经验, 数字滚出来)+ 下一轮; 自己输 = 出局卡「止步半决赛 · 输给 X」+ 名次 + 奖励
##      + 主按钮「去看 X 对 Y」(G25; 留下就到点自动跟过去, G18); 看别人 = 下一场条 +「返回对阵图」, 决赛日到点自动回(P16: 回刚才在看的那一组)
##   时长: 看别人约 4 秒、自己赢约 7 秒、自己输约 6 秒(G8); 自动前进, 点一下只跳到这一拍的终态(C-8)。
## ★动画不用 tween: `pose(t)` 按时刻把全部节点摆好, 每帧推 t; 门禁摆到任意时刻去量(CLAUDE.md §3.5)。
## ★节点名沿用旧卡(`ReplayEndCard` / `ReplayResult` / `ReplayBack` / `ReplayAgain`): 观赛 / 回放的十几个门禁按名字认它们。
## ★冠军杯决赛: 第二拍落定时交给冠军仪式(D 块, `champion_hook`), 这里不做冠军仪式。

const SettleScreenS := preload("res://scripts/scenes/battle/settle_screen.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")
const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const DualLaneS := preload("res://scripts/gamedata/phase2_duallane.gd")
const BackendS := preload("res://scripts/net/backend.gd")

## 每种情况的三拍: [名字, 时长(秒)]
const BEATS := {
	"watch": [["slogan", 0.9], ["result", 2.0], ["next", 1.3]],
	"win": [["slogan", 1.4], ["result", 2.6], ["reward", 3.0]],
	"lose": [["slogan", 1.2], ["result", 2.4], ["out", 2.4]],
	"broken": [["slogan", 0.6]],
}
const PRIMARY_H := 100.0          # 主按钮高(次按钮照结算屏 84)
const SECONDARY_W := 210.0
const PRIMARY_BG := Color("#c27a1c")   # 主按钮底: card_button 的深棕提亮成琥珀(同一个皮, 换一档颜色)
const PRIMARY_EDGE := Color("#ffe08a")
const LAYOUT_H := 720.0           # 版心高(手机横屏的逻辑高); 更高的屏整块竖向居中
const MID_W := 230.0              # 第二拍中间那一栏(比分两位数 + 三路灯)的宽
const AUTO_HOLD := 1.6            # 看别人(决赛日): 三拍走完再停这么久, 自动回对阵图
const FOLLOW_LEAD := 3            # 出局卡: 下一场开播前几秒自动跟过去
const LANE_KEYS := ["top", "bottom", "final"]
const DEFAULT_PID := "basic"
## 本轮奖励那一行的两枚图标: 与主菜单 / 商店 / 周末战绩卡同一张(货币图标全游戏一张, 换图会被当成另一种东西)
const TEX_COIN := "res://assets/sprites/menu/ic-deepsea.png"
const TEX_XP := "res://assets/sprites/shop/icon-xp.png"

## 文案
const TXT_WIN := "胜利"             # = 普通战斗结算的大字(BigTitle.BIG 那一张)
const TXT_LOSE := "惜败"
const TXT_WON_FMT := "%s 获胜"
const TXT_OVER := "比赛结束"
const TXT_ME := "（我）"
const TXT_AGAIN := "再看一遍"
const TXT_REWARD := "本轮奖励"
const TXT_COINS := "深海币"
const TXT_XP := "经验"
const TXT_AUTO_BACK := "即将返回对阵图"
const TXT_NEXT_AT := "距开播 %s"

## 节点名(门禁按名字找)
const N_CARD := "ReplayEndCard"
const N_RESULT := "ReplayResult"
const N_BACK := "ReplayBack"
const N_AGAIN := "ReplayAgain"
const N_GO := "ReplayGoNext"        # 「去看 X 对 Y」
const N_KICKER := "EndKicker"
const N_HEAD := "EndHead"
const N_RIBBON := "EndRibbon"
const N_SIDE := "EndSide_"          # + left / right: 双方结果卡; meta won / dim
const N_HERO := "EndHero_"          # + left / right: 卡上的立绘舞台; meta pid
const N_NAME := "EndName_"
const N_ORIGIN := "EndOrigin_"
const N_CHIP := "EndChip_"          # + left_0 …; meta pid / fallen
const N_SCORE := "EndScore_"        # + left / right
const N_LAMP := "EndLamp_"          # + top / bottom / final; meta side
const N_RANK := "EndRank"
const N_OUT := "EndOut"             # 出局卡那一句
const N_REWARD := "EndReward"
const N_NEXT := "EndNext"
const N_AUTO := "EndAuto"           # 自动前进进度条
const N_DUR := "EndDuration"
const N_SUB := "EndSub"
const N_BTNS := "EndButtons"
const N_BAR_DOCK := "EndBarDock"      # 全局决赛日小条的停靠位
## 冠军杯决赛结束时交给冠军仪式(D 块): 第二拍落定那一刻对这个组里的节点调 `on_cup_final_end(info, host)`;
##   组里有节点 = 它接管(这里停在第二拍、收起卡)。组里没人 ⇒ 照常走第三拍「冠军杯赛冠军」+ 按钮。
const CHAMPION_GROUP := "finals_champion"

## 颜色(C26: 金 = 胜者; 左蓝右红 = 与开场 VS 同一套左右色)
const COL_INK := Color("#070b16")
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const COL_GOLD := Color("#ffd93d")
const COL_GOLD_DIM := Color("#c9a24a")
const COL_LOSE := Color("#7f8ea2")
const COL_MUTE := Color("#c9d3de")
const SIDE_COL := {"left": Color("#5f8fe0"), "right": Color("#e0606e")}

var battle
var host: Control = null          # 挂在哪(replay_controls.root)
var root: Control = null          # = 旧卡的 `card`(节点名 ReplayEndCard)
var info: Dictionary = {}
var t := 0.0
var beats: Array = []
var finished := false
var _n: Dictionary = {}
var _chips: Array = []
var _plates: Array = []
var _btns: Array = []
var _champ_called := false
var _left := false                # 已经离场(按了按钮 / 自动)
var _ticker = null                # 每帧钟(Ctx.start_ticker); 不标类型: 根释放后这里是失效实例


func _init(b) -> void:
	battle = b


# ═══════════════════════════ 纯函数(门禁直接调) ═══════════════════════════

## 看的人是哪一边: "left" / "right" / ""(看别人)。见旧卡同名函数(搬过来, 口径不变)。
static func me_side_of(names: Dictionary, pn: Dictionary, viewer: String) -> String:
	if pn.is_empty():
		return "left"
	if str(pn.get("side", "")) == "b":
		return "right"
	var me := viewer.strip_edges()
	if pn.has("me"):
		var mi := int(pn["me"])
		var pair = pn.get("pair", [])
		if mi < 0 or not (pair is Array) or mi >= (pair as Array).size():
			return ""
		me = str(pair[mi]).strip_edges()
	if me == "":
		return ""
	if str(names.get("l", "")).strip_edges() == me:
		return "left"
	if str(names.get("r", "")).strip_edges() == me:
		return "right"
	return ""


static func end_case(me: String, win: String) -> String:
	if me == "":
		return "watch"
	return "win" if me == win else "lose"


## 各路谁赢 [[路, 胜方], …]; `fill` = 状态流播放端补定局那一路(见旧卡注释)。
static func end_lanes(lr: Dictionary, win: String, cur_lane: String, fill: bool) -> Array:
	var m := {}
	for ln in LANE_KEYS:
		var w := str(lr.get(ln, ""))
		if w == "left" or w == "right":
			m[ln] = w
	if fill and (win == "left" or win == "right") and LANE_KEYS.has(cur_lane) and not m.has(cur_lane):
		var nw := 0
		for ln in m:
			if str(m[ln]) == win:
				nw += 1
		if nw < 2:
			m[cur_lane] = win
	var out: Array = []
	for ln in LANE_KEYS:
		if m.has(ln):
			out.append([ln, str(m[ln])])
	return out


static func end_score(lanes: Array, win: String, code: int = -1) -> Dictionary:
	var s := {"left": 0, "right": 0}
	for p in lanes:
		s[str(p[1])] = int(s[str(p[1])]) + 1
	if lanes.is_empty() and (win == "left" or win == "right"):
		var pr: Array = DualLaneS.score_pair(code)
		if pr.size() == 2:
			s[win] = int(pr[0])
			s["right" if win == "left" else "left"] = int(pr[1])
	return s


## 输在第 rnd 轮(共 rounds 轮)⇒ 名次。
static func place_text(rnd: int, rounds: int, cup: bool) -> String:
	if rnd < 1 or rounds < 1 or rnd > rounds:
		return ""
	if rnd == rounds:
		return "亚军" if cup else "小组第 2 名"
	var lo := (1 << (rounds - rnd)) + 1
	var hi := 1 << (rounds - rnd + 1)
	return "%s第 %d~%d 名" % ["" if cup else "小组", lo, hi]


## 赢了之后那一行(晋级哪一轮 / 夺冠)。没给轮次 = ""(不编)。
static func advance_line(st: Dictionary) -> String:
	var r := int(st.get("round", 0))
	var n := int(st.get("rounds", 0))
	if r < 1 or n < 1 or r > n:
		return ""
	if r == n:
		return "冠军杯赛冠军" if bool(st.get("cup", false)) else "小组第 1 名，晋级冠军杯赛"
	var nx := str(st.get("next_name", ""))
	return Ctx.join_words("晋级", nx) if nx != "" else "晋级下一轮"


## 顶上一行小字: 哪一项比赛哪一轮; 没给 ⇒ 按回哪一页说哪一天; 战绩页不写。
static func stage_kicker(st: Dictionary, back: String) -> String:
	var t0 := Ctx.stage_tag(st)
	if t0 != "":
		return t0
	if back.ends_with("BracketMap.tscn"):
		return "决赛日"
	if back.ends_with("GauntletBoard.tscn"):
		return "闯关赛"
	return ""


static func pid_or_default(pid: String) -> String:
	return pid if pid != "" and DataRegistry.pet_by_id.has(pid) else DEFAULT_PID


## 一边的统领(开局阵容): 左 = 录像方的分路阵容(slot → season_leaders), 右 = 对手快照(lane_assign / 老结构 dg[路])。
static func leaders_of(lineup: Dictionary, leaders: Array, ghost: Dictionary) -> Dictionary:
	var l: Array = []
	for ln in ["top", "bottom"]:
		for s in lineup.get(ln, []):
			if s is Dictionary and str((s as Dictionary).get("kind", "")) == "leader":
				var pid := str((s as Dictionary).get("id", ""))
				var sl := int((s as Dictionary).get("slot", -1))
				if pid == "" and sl >= 0 and sl < leaders.size():
					pid = str(leaders[sl])
				if pid != "" and not l.has(pid):
					l.append(pid)
	if l.is_empty():
		for p in leaders:
			if str(p) != "" and not l.has(str(p)):
				l.append(str(p))
	var r: Array = []
	for ln in ["top", "bottom"]:
		var arr = ghost.get(ln, null)
		if arr is Array and not (arr as Array).is_empty():
			for s in arr:
				if s is Dictionary and str((s as Dictionary).get("kind", "leader")) != "minion" and not (s as Dictionary).has("role"):
					var pid := str((s as Dictionary).get("id", ""))
					if pid != "" and not r.has(pid):
						r.append(pid)
			continue
		var la = ghost.get("lane_assign", {})
		if la is Dictionary and (la as Dictionary).get(ln, null) is Array:
			for p in (la as Dictionary)[ln]:
				if str(p) != "" and not r.has(str(p)):
					r.append(str(p))
	if r.is_empty() and ghost.get("leaders", null) is Array:
		for p in ghost["leaders"]:
			if str(p) != "" and not r.has(str(p)):
				r.append(str(p))
	return {"left": l, "right": r}


## 阵亡划掉: 收尾那一刻场上的单位表里, 这一只死了 ⇒ 划; 不在场上 ⇒ 输的一方划(那一路已经输掉), 赢的一方不划。
static func fallen(pids: Array, side: String, units: Array, win: String) -> Array:
	var out: Array = []
	for pid in pids:
		var seen := false
		var alive := false
		for u in units:
			if u is Dictionary and str((u as Dictionary).get("id", "")) == str(pid) and str((u as Dictionary).get("side", "")) == side:
				seen = true
				alive = alive or bool((u as Dictionary).get("alive", false))
		out.append((seen and not alive) or (not seen and side != win))
	return out


## 三拍的起止 [[名字, 起, 止], …]。
static func beat_times(cs: String) -> Array:
	var out: Array = []
	var t0 := 0.0
	for b in BEATS.get(cs, BEATS["broken"]):
		out.append([str(b[0]), t0, t0 + float(b[1])])
		t0 += float(b[1])
	return out


static func total_of(cs: String) -> float:
	var bt := beat_times(cs)
	return float(bt[bt.size() - 1][2]) if not bt.is_empty() else 0.0


## 点一下: 跳到「这一拍」的终态(= 下一拍的起点); 已在最后一拍 ⇒ 跳到全长。
static func skip_to(cs: String, x: float) -> float:
	for b in beat_times(cs):
		if x < float(b[2]):
			return float(b[2])
	return maxf(x, total_of(cs))


# ═══════════════════════════ 内容 ═══════════════════════════

## 收尾要写的全部内容(门禁直接调)。`names` = 录像左右是谁 {"l", "r"}。
func end_info(won: bool, broken: bool, names: Dictionary, stream: bool, stream_ctl: bool) -> Dictionary:
	var pn: Dictionary = ReplayRecorder.play_names
	var rp = battle._replay
	var lv = rp.live if rp.is_live() else null
	var win := "left" if won else "right"
	var st := Ctx.stage_of(pn)
	var finals := Ctx.is_finals(pn) or ReplayRecorder.exit_scene().ends_with("BracketMap.tscn")
	var info0 := {"win": win, "again": not broken and lv == null and not stream, "dur": "", "kicker": "", "rank": "",
		"sub": "", "me": "", "lanes": [], "score": {"left": 0, "right": 0}, "stage": st, "finals": finals,
		"next": pn.get("next", {}) if pn.get("next", {}) is Dictionary else {}, "gold": Ctx.is_cup_final(st)}
	if broken:
		var tt := "回放中断"
		if lv != null:
			tt = str(lv.broken_why) if str(lv.broken_why) != "" else str(lv.TXT_BROKEN)
		info0["case"] = "broken"
		info0["title"] = tt
		info0["sub"] = "回放异常，无法继续播放" if lv == null else ""
		return info0
	var nl := str(names.get("l", ""))
	var nr := str(names.get("r", ""))
	var me := me_side_of(names, pn, ReplayRecorder.viewer_name)
	var cs := end_case(me, win)
	var who := str(pn.get("l" if won else "r", ""))
	if who == "":
		who = nl if won else nr
	info0["case"] = cs
	info0["me"] = me
	if cs == "watch":
		info0["title"] = (TXT_WON_FMT % who) if who != "" else TXT_OVER
	else:
		info0["title"] = TXT_WIN if cs == "win" else TXT_LOSE
	info0["names"] = {"left": nl, "right": nr}
	info0["kicker"] = stage_kicker(st, ReplayRecorder.exit_scene())
	if cs == "win":
		info0["rank"] = advance_line(st)
	elif cs == "lose":
		info0["rank"] = place_text(int(st.get("round", 0)), int(st.get("rounds", 0)), bool(st.get("cup", false)))
		info0["out"] = Ctx.out_line(st, nl if me == "right" else nr)
	info0["reward"] = Ctx.is_finals(pn) and cs != "watch"
	var lr: Dictionary = GameState.lane_results if GameState != null and GameState.lane_results is Dictionary else {}
	var cur := str(GameState.current_lane) if GameState != null and GameState.current_lane != null else ""
	var lanes := end_lanes(lr, win, cur, stream)
	info0["lanes"] = lanes
	info0["score"] = end_score(lanes, win, int(pn.get("score", -1)))
	var tot: int = rp.total_steps()
	if tot > 0 and lv == null and (not stream or stream_ctl):
		info0["dur"] = "全场 " + ReplayControls.clock(tot)
	var ghost: Dictionary = GameState.dual_ghost if GameState != null and GameState.dual_ghost is Dictionary else {}
	var ld: Array = GameState.season_leaders if GameState != null and GameState.season_leaders is Array else []
	var lu: Dictionary = GameState.dual_lineup if GameState != null and GameState.dual_lineup is Dictionary else {}
	var lead := leaders_of(lu, ld, ghost)
	var units: Array = battle.get("_units") if battle.get("_units") is Array else []
	info0["leaders"] = lead
	info0["fallen"] = {"left": fallen(lead["left"], "left", units, win), "right": fallen(lead["right"], "right", units, win)}
	var lp := str((lead["left"] as Array)[0]) if not (lead["left"] as Array).is_empty() else ""
	info0["pids"] = {"left": pid_or_default(lp), "right": pid_or_default(BackendS.lead_of(ghost))}
	var cards := Ctx.side_cards(pn, {"l": nl, "r": nr})
	info0["origins"] = {"left": Ctx.origin_of(cards["left"], st), "right": Ctx.origin_of(cards["right"], st)}
	return info0


# ═══════════════════════════ 建 ═══════════════════════════

func build(parent: Control, inf: Dictionary, vp: Vector2) -> Control:
	host = parent
	info = inf
	beats = beat_times(str(info["case"]))
	var dim := ColorRect.new()
	dim.name = N_CARD
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = vp
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	dim.gui_input.connect(_on_input)
	parent.add_child(dim)
	root = dim
	## 版心: 按 720 高排版, 比 720 高的屏(iPad 逻辑 1280×960)整块竖向居中; 暗幕仍铺满全屏
	var lay := Vector2(vp.x, minf(vp.y, LAYOUT_H))
	var body := Control.new()
	body.name = "EndBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = lay
	body.position = Vector2(0.0, roundf((vp.y - lay.y) * 0.5))
	dim.add_child(body)
	_n["body"] = body
	var cs := str(info["case"])
	var cx: float = roundf(vp.x * 0.5)
	## 全局决赛日小条的停靠位:
	##   · 版心上方有 ≥ 60 的空(iPad 逻辑 1280×960)⇒ 那一条正中, 赛事小字照旧;
	##   · 没有上方空位(手机横屏)而小条在场 ⇒ 小条就停在赛事小字那一行(它写的就是「冠军杯赛 · 半决赛…」), 赛事小字让出来不再写一遍;
	##   · 小条不在场(周六 / 战绩页)⇒ 不留停靠位。
	if body.position.y >= 60.0:
		var dock := Ctx.bar_dock(N_BAR_DOCK, Rect2(cx - Ctx.BAR_W * 0.5, roundf((body.position.y - Ctx.BAR_H) * 0.5), Ctx.BAR_W, Ctx.BAR_H))
		dim.add_child(dock)
		_n["bar_dock"] = dock
	elif Ctx.bar_on():
		var dock2 := Ctx.bar_dock(N_BAR_DOCK, Rect2(cx - Ctx.BAR_W * 0.5, body.position.y + 2.0, Ctx.BAR_W, Ctx.BAR_H))
		dim.add_child(dock2)
		_n["bar_dock"] = dock2
		info["kicker"] = ""
	## ① 标语带(压在战场上): 一条横贯的深色带, 先在屏中, 第二拍收到顶上
	var band := Control.new()
	band.name = "EndBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(vp.x, 132)
	band.pivot_offset = band.size * 0.5
	band.draw.connect(_draw_band.bind(band))
	body.add_child(band)
	_n["band"] = band
	_n["band_y0"] = roundf(lay.y * 0.42 - 66.0)
	## 收到顶上后标语中线在 84(缩到 0.62), 不压 36 号的赛事小字 / 停在那一行的全局小条; 两样都没有 ⇒ 54
	_n["band_y1"] = 18.0 if str(info.get("kicker", "")) != "" or _n.has("bar_dock") else -12.0
	_build_head(band, cx)
	if str(info.get("kicker", "")) != "":
		var kl := Ctx.title_lbl(str(info["kicker"]), 36, Color("#ffd668"))
		kl.name = N_KICKER
		kl.size = Vector2(vp.x, 44)
		kl.position = Vector2(0, 0)
		body.add_child(kl)
		_n["kicker"] = kl
	if cs == "broken":
		if str(info.get("sub", "")) != "":
			var sl := SettleScreenS._lbl(str(info["sub"]), 22, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
			sl.name = N_SUB
			Ctx.outline(sl, 6)
			sl.size = Vector2(vp.x, 30)
			sl.position = Vector2(0, (_n["band_y0"] as float) + 140.0)
			body.add_child(sl)
			_n["sub"] = sl
		_build_buttons(body, lay, (_n["band_y0"] as float) + 190.0)
	else:
		_build_sides(body, lay)
		_build_score(body, cx)
		_build_third(body, lay)
	Ctx.bar_avoid([_n.get("kicker"), _n.get("head"), _n.get("side_left"), _n.get("side_right"), _n.get("btnrow"), _n.get("reward"),
		_n.get("out"), _n.get("rank"), _n.get("next")])
	t = 0.0
	pose(0.0)
	_disconnect()                      # 同一个对象再搭一次(换比例)⇒ 钟跟着挂到新根上
	_ticker = Ctx.start_ticker(dim, self)
	return dim


## 标语: 看别人 = 金色横幅里「X 获胜」(昵称 = 正文字体); 自己赢 = 「胜利」大字(普通结算那一张美术字); 自己输 = 「惜败」压低一档; 中断 = 红字。
func _build_head(band: Control, cx: float) -> void:
	var cs := str(info["case"])
	var head := Control.new()
	head.name = N_HEAD
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(head)
	_n["head"] = head
	if cs == "watch":
		## 缎带里: 胜者名字(玩家输入的字 ⇒ 正文字体)+「获胜」美术字。标签 ReplayResult 的字仍是「X 获胜」(门禁 / 读屏读它), 自己透明。
		var tl := SettleScreenS._lbl(str(info["title"]), 40, Color("#fff6dc"), HORIZONTAL_ALIGNMENT_CENTER)
		tl.name = N_RESULT
		tl.self_modulate.a = 0.0
		head.add_child(tl)
		var row := HBoxContainer.new()
		row.name = "EndWinner"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(row)
		var who := str(info["title"]).trim_suffix(TXT_WON_FMT.trim_prefix("%s"))
		var nm := SettleScreenS._lbl(who, 40, Color("#fff6dc"), HORIZONTAL_ALIGNMENT_CENTER)
		nm.add_theme_color_override("font_outline_color", Color("#5a2e08"))
		nm.add_theme_constant_override("outline_size", 10)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nm)
		var won_art := Ctx.art_rect("bt-huosheng") if str(info["title"]) != TXT_OVER else null
		if won_art != null:
			won_art.custom_minimum_size = won_art.size
			won_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(won_art)
		else:
			nm.text = str(info["title"])
		var tw: float = nm.get_theme_font("font").get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		var aw: float = won_art.size.x + 14.0 if won_art != null else 0.0
		var w: float = clampf(roundf(tw + aw + 2.0 * 48.0 + 64.0), 420.0, maxf(420.0, band.size.x - 160.0))
		nm.custom_minimum_size.x = minf(tw, w - aw - 160.0)
		head.size = Vector2(w, 84)
		head.position = Vector2(roundf(cx - w * 0.5), 24.0)
		head.pivot_offset = head.size * 0.5
		var rib := Control.new()
		rib.name = N_RIBBON
		rib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rib.size = head.size
		rib.draw.connect(_draw_rib.bind(rib))
		head.add_child(rib)
		head.move_child(rib, 0)
		tl.position = Vector2(56.0, 0.0)
		tl.size = Vector2(w - 112.0, 70.0)
		row.position = Vector2(56.0, 0.0)
		row.size = Vector2(w - 112.0, 70.0)
		_n["head_kind"] = "ribbon"
		return
	head.size = Vector2(band.size.x, 100)
	head.position = Vector2(0, 16)
	head.pivot_offset = head.size * 0.5
	var col: Color = COL_GOLD if cs == "win" else (Color("#b4cce8") if cs == "lose" else Color("#ff6b6b"))
	var bl := SettleScreenS._lbl(str(info["title"]), 72, col, HORIZONTAL_ALIGNMENT_CENTER)
	bl.name = N_RESULT
	if cs == "broken":
		UISkin.title_label(bl, 48)
		bl.add_theme_constant_override("outline_size", 16)
	else:
		UISkin.title_label(bl, 72)
		bl.add_theme_constant_override("outline_size", 24)
	bl.add_theme_color_override("font_outline_color", COL_INK)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = head.size
	head.add_child(bl)
	if cs == "win":
		BigTitle.apply(bl, BigTitle.BIG)          # 「胜利」= 普通结算那一张
	elif cs == "lose":
		Ctx.dress_art(bl)                          # 「惜败」冷色美术字(不用红)
	_n["head_kind"] = "title"


## ② 双方结果卡: 立绘 + 名字 + 来历 + 统领一排(阵亡划掉)。赢家金边发光, 输家压灰下沉。
func _build_sides(dim: Control, vp: Vector2) -> void:
	## 卡贴着中间那一栏(比分 + 三路灯, 宽 MID_W)两边排; 窄屏(iPad 960)卡跟着变窄, 不压中间
	var cw: float = clampf(roundf(vp.x * 0.5 - MID_W * 0.5 - 12.0 - 16.0), 240.0, 400.0)
	var ch := 280.0
	var win := str(info["win"])
	var me := str(info["me"])
	var names: Dictionary = info.get("names", {})
	for side in ["left", "right"]:
		var ccx: float = roundf(vp.x * 0.5 + (-1.0 if side == "left" else 1.0) * (MID_W * 0.5 + 12.0 + cw * 0.5))
		var card := Control.new()
		card.name = N_SIDE + side
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size = Vector2(cw, ch)
		card.position = Vector2(ccx - cw * 0.5, 128.0)
		card.pivot_offset = Vector2(cw * 0.5, ch)
		card.set_meta("won", side == win)
		card.set_meta("x0", card.position.x)
		card.draw.connect(_draw_side.bind(card, side))
		dim.add_child(card)
		_n["side_" + side] = card
		_n["side_y_" + side] = card.position.y
		var stage := Control.new()
		stage.name = N_HERO + side
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.size = Vector2(150, 150)
		stage.position = Vector2(roundf((cw - 150.0) * 0.5), 6.0)
		var pid := str((info.get("pids", {}) as Dictionary).get(side, DEFAULT_PID))
		stage.set_meta("pid", pid)
		card.add_child(stage)
		if side == win:
			var rays := Control.new()
			rays.name = "EndRays"
			rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rays.size = Vector2(220, 220)
			rays.position = Vector2(-35, -35)
			rays.pivot_offset = rays.size * 0.5
			rays.draw.connect(_draw_rays.bind(rays))
			stage.add_child(rays)
			_n["rays"] = rays
		var body: Control = UnitCardArt.portrait_anim(pid, Rect2(Vector2(8, 4), Vector2(134, 136)), 140.0, true)
		if body == null:
			body = UnitCardArt.portrait_anim(DEFAULT_PID, Rect2(Vector2(8, 4), Vector2(134, 136)), 140.0, true)
		if body != null:
			stage.add_child(body)
		var nm := str(names.get(side, ""))
		if nm == "":
			nm = "—"
		if side == me:
			nm += TXT_ME
		var nl := SettleScreenS._lbl(nm, 30, Color("#ffe7a0") if side == win else Color("#b4c0d0"), HORIZONTAL_ALIGNMENT_CENTER)
		nl.name = N_NAME + side
		Ctx.outline(nl, 6)
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.size = Vector2(cw - 16.0, 36)
		nl.position = Vector2(8, 158)
		card.add_child(nl)
		var org := str((info.get("origins", {}) as Dictionary).get(side, ""))
		if org != "":
			var ol := SettleScreenS._lbl(org, 24, COL_GOLD if side == win else COL_GOLD_DIM, HORIZONTAL_ALIGNMENT_CENTER)
			ol.name = N_ORIGIN + side
			Ctx.outline(ol, 6)
			ol.size = Vector2(cw - 16.0, 26)
			ol.position = Vector2(8, 190)
			card.add_child(ol)
		if side == win:
			## 赢家那张左上角一枚「胜」章(结算屏各路胜负那一张美术字)
			var badge := Label.new()
			badge.name = "EndWinBadge"
			badge.text = "胜"
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.size = Vector2(64, 64)
			badge.position = Vector2(-14, -18)
			card.add_child(badge)
			BigTitle.apply(badge, BigTitle.LANE)
		var pids: Array = (info.get("leaders", {}) as Dictionary).get(side, [])
		var fl: Array = (info.get("fallen", {}) as Dictionary).get(side, [])
		var cpx := 52.0
		var gap := 8.0
		var x0: float = roundf((cw - (float(pids.size()) * (cpx + gap) - gap)) * 0.5)
		for i in range(pids.size()):
			var chip := MatchCard.avatar(str(pids[i]), cpx, side == "right", false)
			chip.name = "%s%s_%d" % [N_CHIP, side, i]
			chip.set_meta("pid", str(pids[i]))
			var dead: bool = i < fl.size() and bool(fl[i])
			chip.set_meta("fallen", dead)
			chip.position = Vector2(x0 + float(i) * (cpx + gap), 222.0)
			chip.size = Vector2(cpx, cpx)
			card.add_child(chip)
			if dead:
				var xm := Control.new()
				xm.name = "Cross"
				xm.mouse_filter = Control.MOUSE_FILTER_IGNORE
				xm.size = Vector2(cpx, cpx)
				xm.draw.connect(_draw_cross.bind(xm))
				chip.add_child(xm)
				_chips.append([chip, xm])


## ② 中间: 比分(从 0 逐路数上去)+ 三路灯(一路一盏, 灯色 = 赢下那一路的那一边)。
func _build_score(dim: Control, cx: float) -> void:
	var win := str(info["win"])
	_n["digits"] = {}
	for side in ["left", "right"]:
		var dg := Ctx.title_lbl("0", 72, COL_GOLD if side == win else COL_LOSE)
		dg.name = N_SCORE + side
		dg.set_meta("gold", side == win)
		dg.set_meta("final", int((info["score"] as Dictionary).get(side, 0)))
		dg.size = Vector2(80, 96)
		dg.pivot_offset = dg.size * 0.5
		dg.position = Vector2(cx + (-104.0 if side == "left" else 24.0), 172.0)
		dg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dim.add_child(dg)
		_n["digits"][side] = dg
	var colon := Ctx.title_lbl(":", 72, COL_TEXT)
	colon.size = Vector2(40, 96)
	colon.position = Vector2(cx - 20.0, 168.0)
	colon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dim.add_child(colon)
	_n["colon"] = colon
	var lanes: Array = info["lanes"]
	var won_map := {}
	for p in lanes:
		won_map[str(p[0])] = str(p[1])
	var lw := 56.0
	var x0: float = cx - (3.0 * lw + 2.0 * 6.0) * 0.5
	var i := 0
	for ln in LANE_KEYS:
		var lamp := Control.new()
		lamp.name = N_LAMP + ln
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lamp.size = Vector2(lw, 52)
		lamp.position = Vector2(roundf(x0 + float(i) * (lw + 6.0)), 284.0)
		lamp.pivot_offset = Vector2(lw * 0.5, 14)
		lamp.set_meta("side", str(won_map.get(ln, "")))
		lamp.set_meta("lit", 0.0)
		lamp.draw.connect(_draw_lamp.bind(lamp, str(Ctx.LANE_SHORT[ln])))
		dim.add_child(lamp)
		if won_map.has(ln):
			_plates.append(lamp)
		i += 1


## ③ 第三拍: 自己赢 = 晋级 + 奖励; 自己输 = 出局卡; 看别人 = 下一场条。底下是按钮。
func _build_third(dim: Control, vp: Vector2) -> void:
	var cs := str(info["case"])
	var y := 420.0
	var st: Dictionary = info.get("stage", {})
	if cs == "lose" and str(info.get("out", "")) != "":
		var ol := Ctx.title_lbl(str(info["out"]), 36, COL_MUTE)
		ol.name = N_OUT
		ol.size = Vector2(vp.x, 44)
		ol.position = Vector2(0, y)
		dim.add_child(ol)
		_n["out"] = ol
		y += ol.size.y + 2.0
	if str(info.get("rank", "")) != "":
		var rl := Ctx.title_lbl(str(info["rank"]), 36 if cs == "win" else 24, COL_GOLD if cs == "win" else COL_SUB)
		rl.name = N_RANK
		rl.size = Vector2(vp.x, 66 if cs == "win" else 32)
		rl.position = Vector2(0, y)
		dim.add_child(rl)
		if cs == "win":
			Ctx.dress_art(rl)
		_n["rank"] = rl
		y += rl.size.y + 2.0
	if bool(info.get("reward", false)):
		var row := HBoxContainer.new()
		row.name = N_REWARD
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size = Vector2(vp.x, 40)
		row.position = Vector2(0, y)
		dim.add_child(row)
		var cap := SettleScreenS._lbl(TXT_REWARD, 24, COL_SUB)
		Ctx.outline(cap, 6)
		row.add_child(cap)
		row.add_child(_icon(TEX_COIN, 32.0))

		var cl := SettleScreenS._lbl("+0 " + TXT_COINS, 30, COL_GOLD)
		Ctx.outline(cl, 8)
		cl.name = "EndCoins"
		row.add_child(cl)
		row.add_child(_icon(TEX_XP, 24.0))
		var xl := SettleScreenS._lbl("+0 " + TXT_XP, 30, Color("#9ae6b0"))
		Ctx.outline(xl, 8)
		xl.name = "EndXp"
		row.add_child(xl)
		_n["reward"] = row
		_n["coins"] = cl
		_n["xp"] = xl
		y += 42.0
	var nx: Dictionary = info.get("next", {})
	var nline := Ctx.next_line(nx) if bool(info.get("finals", false)) else ""
	if nline != "" and cs == "watch":                 # 自己那一场: 第三拍说的是自己(晋级 / 出局卡的「去看」), 不另挂别人的下一场
		var nl := SettleScreenS._lbl(nline, 26, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		nl.name = N_NEXT
		Ctx.outline(nl, 6)
		nl.size = Vector2(vp.x, 34)
		nl.position = Vector2(0, y)
		dim.add_child(nl)
		_n["next"] = nl
		y += 36.0
	if str(info.get("dur", "")) != "" and not bool(info.get("finals", false)):
		var dl := SettleScreenS._lbl(str(info["dur"]), 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
		dl.name = N_DUR
		Ctx.outline(dl, 6)
		dl.size = Vector2(vp.x, 26)
		dl.position = Vector2(0, y)
		dim.add_child(dl)
		_n["dur"] = dl
		y += 28.0
	## 看别人第三拍只有一行下一场: 按钮跟在它下面(不沉到屏底留一大块空); 自己那一场内容多, 按钮靠屏底
	_build_buttons(dim, vp, (y + 30.0) if cs == "watch" else maxf(y + 6.0, vp.y - 120.0))


func _build_buttons(dim: Control, vp: Vector2, y: float) -> void:
	var hb := HBoxContainer.new()
	hb.name = N_BTNS
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.size = Vector2(vp.x, PRIMARY_H)
	hb.position = Vector2(0, minf(y, vp.y - PRIMARY_H - 20.0))
	dim.add_child(hb)
	_n["btnrow"] = hb
	_n["btn_y"] = hb.position.y
	var cs := str(info["case"])
	var go := Ctx.go_label(info.get("next", {}))
	var go_main: bool = cs == "lose" and go != "" and bool(info.get("finals", false))
	if bool(info.get("again", false)):
		var ag := _btn(TXT_AGAIN, N_AGAIN, COL_MUTE, false, vp)
		ag.pressed.connect(func() -> void: ReplayRecorder.play_again(battle.get_tree(), battle._replay.rec))
		hb.add_child(ag)
	var bk := _btn(ReplayControls.back_label(), N_BACK, COL_MUTE if go_main else Color("#fff2c8"), not go_main, vp)
	bk.pressed.connect(go_back)
	hb.add_child(bk)
	## 出局卡主按钮「去看 X 对 Y」(G25): 主按钮在右、最大最亮、呼吸; 次按钮「返回对阵图」降一级在左
	if go_main:
		var gb := _btn(go, N_GO, Color("#fff2c8"), true, vp)
		gb.pressed.connect(go_next)
		hb.add_child(gb)
		var sub := SettleScreenS._lbl("", 20, COL_SUB, HORIZONTAL_ALIGNMENT_CENTER)
		sub.name = "EndGoWhen"
		Ctx.outline(sub, 6)
		sub.size = Vector2(vp.x, 26)
		sub.position = Vector2(0, hb.position.y - 30.0)          # 按钮那一排正上方(下面没地方了)
		dim.add_child(sub)
		_n["go_when"] = sub
	## 看别人(决赛日): 自动回对阵图的进度条(细金条, 走完就回)
	if cs == "watch" and _auto_back():
		var ab := Control.new()
		ab.name = N_AUTO
		ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ab.size = Vector2(320, 26)
		ab.position = Vector2(roundf(vp.x * 0.5 - 160.0), hb.position.y + PRIMARY_H + 4.0)
		ab.set_meta("p", 0.0)
		ab.draw.connect(_draw_auto.bind(ab))
		dim.add_child(ab)
		_n["auto"] = ab


## 货币小图标: 源图按整数分之一缩(64 → 32、48 → 24), 最近邻, 不糊。
func _icon(path: String, px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path) if ResourceLoader.exists(path) else null
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 主按钮: 高 PRIMARY_H、字 32、底与边亮一档(card_button 那一套换色), 呼吸; 次按钮: 宽 SECONDARY_W、字 24、字压暗。
func _btn(txt: String, nm: String, fc: Color, primary: bool, vp: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	SettleScreenS.dress_btn(b, fc)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_meta("primary", primary)
	if primary:
		b.add_theme_font_size_override("font_size", 32)
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb = b.get_theme_stylebox(st)
			if sb is StyleBoxFlat:
				var nb := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
				nb.bg_color = PRIMARY_BG.darkened(0.15) if st.begins_with("press") or st == "hover_pressed" else PRIMARY_BG
				nb.border_color = PRIMARY_EDGE
				nb.set_border_width_all(3)
				b.add_theme_stylebox_override(st, nb)
		var tw: float = b.get_theme_font("font").get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
		b.custom_minimum_size = Vector2(clampf(tw + 88.0, 300.0, vp.x - 2.0 * SECONDARY_W - 120.0), PRIMARY_H)
		b.clip_text = true
		b.pivot_offset = b.custom_minimum_size * 0.5
		_n["primary"] = b
	else:
		b.add_theme_font_size_override("font_size", 24)
		b.custom_minimum_size = Vector2(SECONDARY_W, SettleScreenS.BTN_SIZE.y)
		b.size_flags_vertical = Control.SIZE_SHRINK_END
	_btns.append(b)
	return b


# ═══════════════════════════ 离场 ═══════════════════════════

## 决赛日看别人: 三拍走完自动回对阵图。
func _auto_back() -> bool:
	return bool(info.get("finals", false)) and Ctx.is_finals(ReplayRecorder.play_names) \
		and ReplayRecorder.exit_scene().ends_with("BracketMap.tscn") and not Ctx.is_cup_final(info.get("stage", {}))


## 「返回对阵图」: 回到刚才在看的那一组(P16)。看别人自动回时顺带挂上「下一场」(到点自动开播)。
func go_back(follow_next: bool = false) -> void:
	if _left:
		return
	_left = true
	var pn: Dictionary = ReplayRecorder.play_names
	if bool(info.get("finals", false)):
		var f := {"view": str(pn.get("view", "")), "bucket": int(pn.get("bucket", -1))}
		var nx: Dictionary = info.get("next", {})
		if follow_next and not nx.is_empty():
			f["r"] = int(nx.get("r", 0))
			f["m"] = int(nx.get("m", 0))
			f["at"] = int(nx.get("at", 0))
		Ctx.follow = f
	battle._hud._replay_exit()


## 出局卡「去看 X 对 Y」: 回对阵图并挂上那一场(对阵图到点自动开播)。
func go_next() -> void:
	go_back(true)


# ═══════════════════════════ 动 ═══════════════════════════

func _bt(nm: String) -> Array:
	for b in beats:
		if str(b[0]) == nm:
			return [float(b[1]), float(b[2])]
	return [INF, INF]


func pose(x: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	var cs := str(info["case"])
	var b2: Array = _bt("result")
	var b3: Array = _bt(beats[beats.size() - 1][0] if beats.size() >= 3 else "~")
	## 暗幕: 第一拍只压一条带(战场照样看得见), 第二拍整屏压暗
	var dim_a: float = 0.0 if cs != "broken" else 0.62 * Ctx.ease_out(Ctx.k01(x, 0.0, 0.2))
	if b2[0] < INF:
		dim_a = 0.88 * Ctx.ease_out(Ctx.k01(x, b2[0], 0.3))      # 第二拍起几乎不透: 对局顶栏 / 头像框栏不再透出来抢字
	(root as ColorRect).color.a = dim_a
	## 标语带: 0 → 屏中展开; 第二拍收到顶上并缩小
	var band: Control = _n["band"]
	var up := Ctx.ease_out(Ctx.k01(x, b2[0], 0.35)) if b2[0] < INF else 0.0
	band.position.y = Ctx.mix(_n["band_y0"], _n["band_y1"], up)
	band.scale = Vector2(Ctx.mix(1.0, 0.62, up), maxf(0.001, Ctx.ease_out(Ctx.k01(x, 0.0, 0.2))) * Ctx.mix(1.0, 0.62, up))
	band.set_meta("fill", 1.0 - up)
	band.queue_redraw()
	var hd: Control = _n["head"]
	var ph := Ctx.k01(x, 0.08, 0.3)
	if str(_n.get("head_kind", "")) == "ribbon":
		hd.scale = Vector2(maxf(0.001, Ctx.ease_back(ph)), 1.0)
		hd.modulate.a = Ctx.k01(x, 0.08, 0.08)
	elif cs == "win":
		hd.position.x = -260.0 * (1.0 - Ctx.ease_back(ph))       # 「胜利」从左冲进来
		hd.modulate.a = Ctx.k01(x, 0.08, 0.12)
	else:
		hd.position.y = 16.0 - 20.0 * (1.0 - Ctx.ease_out(ph))   # 「惜败」从上面落下, 不冲不弹
		hd.modulate.a = Ctx.k01(x, 0.08, 0.3)
	if _n.has("kicker"):
		(_n["kicker"] as Control).modulate.a = Ctx.k01(x, b2[0], 0.3) if b2[0] < INF else 0.0
	if _n.has("sub"):
		(_n["sub"] as Control).modulate.a = Ctx.k01(x, 0.25, 0.2)
	if b2[0] < INF:
		_pose_result(x, b2[0], b2[1])
	if b3[0] < INF:
		_pose_third(x, b3[0])
	## 按钮: 最后一拍起点 + 0.3 秒淡入; 淡到一半才吃点击(之前点到它的位置 = 跳拍)
	if _n.has("btnrow"):
		var t_btn: float = (b3[0] + 0.3) if b3[0] < INF else 0.3
		var pb := Ctx.k01(x, t_btn, 0.28)
		var br: Control = _n["btnrow"]
		br.modulate.a = pb
		br.position.y = float(_n["btn_y"]) + 24.0 * (1.0 - Ctx.ease_out(pb))
		for b in _btns:
			(b as Control).mouse_filter = Control.MOUSE_FILTER_STOP if pb >= 0.5 else Control.MOUSE_FILTER_IGNORE
		if _n.has("primary"):
			var pr: Control = _n["primary"]
			pr.pivot_offset = pr.size * 0.5
			pr.scale = Vector2.ONE * (1.0 + 0.05 * Ctx.wave(x * 0.7)) if pb >= 1.0 else Vector2.ONE
	if _n.has("auto"):
		var tot := total_of(cs)
		var ab: Control = _n["auto"]
		ab.modulate.a = Ctx.k01(x, tot, 0.2)
		ab.set_meta("p", Ctx.k01(x, tot, AUTO_HOLD))
		ab.queue_redraw()


func _pose_result(x: float, t0: float, t1: float) -> void:
	var win := str(info["win"])
	for side in ["left", "right"]:
		var c: Control = _n["side_" + side]
		var p := Ctx.k01(x, t0 + (0.0 if side == "left" else 0.08), 0.32)
		var dx: float = (-1.0 if side == "left" else 1.0) * 160.0 * (1.0 - Ctx.ease_out(p))
		c.position.x = roundf(float(c.get_meta("x0", 0.0)) + dx)
		## 胜负落定(第二拍 0.9 秒起): 赢家放大一点 + 发光; 输家压灰 + 下沉
		var q := Ctx.k01(x, t0 + 0.9, 0.35)
		var won: bool = side == win
		c.scale = Vector2.ONE * (Ctx.mix(1.0, 1.04, Ctx.ease_back(q)) if won else 1.0)
		c.position.y = float(_n["side_y_" + side]) + (0.0 if won else 10.0 * Ctx.ease_out(q))
		var g: float = Ctx.mix(1.0, 0.55, q) if not won else 1.0
		c.modulate = Color(g, g, g * 1.04, p)
		c.set_meta("glow", q * (0.7 + 0.3 * Ctx.wave(x * 0.8)) if won else 0.0)
		c.queue_redraw()
	if _n.has("rays"):
		var ry: Control = _n["rays"]
		ry.modulate.a = Ctx.k01(x, t0 + 0.9, 0.4)
		ry.rotation = 0.25 * x
	## 阵亡划掉: 第二拍 1.1 秒起逐个划(每个隔 0.08 秒, 一笔一笔画出来)
	for i in range(_chips.size()):
		var xm: Control = _chips[i][1]
		xm.set_meta("p", Ctx.k01(x, t0 + 1.1 + 0.08 * float(i), 0.18))
		xm.queue_redraw()
	## 比分逐路亮: 第 i 盏灯在 t0 + 0.5 + 0.22i 点亮, 同一刻那一边的分 +1 并弹一下
	var a_mid := Ctx.k01(x, t0 + 0.2, 0.25)
	(_n["colon"] as Control).modulate.a = a_mid
	var shown := {"left": 0, "right": 0}
	var last := {"left": -1.0, "right": -1.0}
	for i in range(_plates.size()):
		var lp: Control = _plates[i]
		var ti: float = lamp_t(t0, i)
		lp.set_meta("lit", Ctx.k01(x, ti, 0.18))
		lp.scale = Vector2.ONE * (Ctx.mix(1.5, 1.0, Ctx.ease_out(Ctx.k01(x, ti, 0.25))) if x >= ti else 1.0)
		lp.queue_redraw()
		if x >= ti:
			var sd := str(lp.get_meta("side", ""))
			shown[sd] = int(shown[sd]) + 1
			last[sd] = ti
	for ln in LANE_KEYS:
		var lamp := (_n["body"] as Node).find_child(N_LAMP + ln, false, false) as Control
		if lamp != null:
			lamp.modulate.a = a_mid
	for sd in ["left", "right"]:
		var dg: Label = _n["digits"][sd]
		var v: int = int(shown[sd])
		if _plates.is_empty() and x >= lamp_t(t0, 0):
			v = int(dg.get_meta("final", 0))
			last[sd] = lamp_t(t0, 0) if v > 0 else -1.0
		if dg.text != str(v) or dg.get_node_or_null(Ctx.ART_NODE) == null:
			Ctx.set_digit(dg, v, bool(dg.get_meta("gold", false)))
		dg.modulate.a = a_mid
		var lt: float = float(last[sd])
		dg.scale = Vector2.ONE * ((1.0 + 0.5 * (1.0 - Ctx.ease_out(Ctx.k01(x, lt, 0.25)))) if lt >= 0.0 else 1.0)
	if x >= t1 and not _champ_called and Ctx.is_cup_final(info.get("stage", {})):
		_champ_called = true
		var tree := root.get_tree()
		if tree != null and not tree.get_nodes_in_group(CHAMPION_GROUP).is_empty():
			tree.call_group(CHAMPION_GROUP, "on_cup_final_end", info, host)
			finished = true
			root.visible = false


## 第 i 盏灯点亮的时刻。
static func lamp_t(t0: float, i: int) -> float:
	return t0 + 0.5 + 0.22 * float(i)


func _pose_third(x: float, t0: float) -> void:
	var p := Ctx.k01(x, t0, 0.3)
	for k in ["out", "rank", "next", "dur"]:
		if _n.has(k):
			var c: Control = _n[k]
			var d: float = {"out": 0.0, "rank": 0.15, "next": 0.2, "dur": 0.2}[k]
			c.modulate.a = Ctx.k01(x, t0 + d, 0.25)
			c.scale = Vector2.ONE
	if _n.has("out"):
		var ol: Control = _n["out"]
		ol.pivot_offset = ol.size * 0.5
		ol.scale = Vector2.ONE * Ctx.mix(1.25, 1.0, Ctx.ease_out(Ctx.k01(x, t0, 0.3)))
	if _n.has("reward"):
		var rw: Control = _n["reward"]
		rw.modulate.a = Ctx.k01(x, t0 + 0.35, 0.2)
		## 数字滚出来(0.8 秒), 落定弹一下
		var q := Ctx.k01(x, t0 + 0.45, 0.8)
		(_n["coins"] as Label).text = "+%d %s" % [int(roundf(float(P2C.FINALS_COINS_PER_ROUND) * Ctx.ease_out(q))), TXT_COINS]
		(_n["xp"] as Label).text = "+%d %s" % [int(roundf(float(P2C.FINALS_XP_PER_ROUND) * Ctx.ease_out(q))), TXT_XP]
		rw.pivot_offset = rw.size * 0.5
		rw.scale = Vector2.ONE * (1.0 + 0.08 * (1.0 - Ctx.ease_out(Ctx.k01(x, t0 + 1.25, 0.25))) if q >= 1.0 else 1.0)
	if _n.has("go_when"):
		var gw: Label = _n["go_when"]
		gw.modulate.a = Ctx.k01(x, t0 + 0.5, 0.25)
		gw.text = _go_when_text()


## 「距开播 1 分 05 秒」(下一场有时刻时; 与对阵图下一行同一种写法)。
func _go_when_text() -> String:
	var at := int((info.get("next", {}) as Dictionary).get("at", 0))
	if at <= 0:
		return ""
	var now := int(Time.get_unix_time_from_system()) + int(ReplayRecorder.play_names.get("srv_off", 0))
	return (TXT_NEXT_AT % Ctx.span_text(at - now)) if at > now else "开播中"


func _tick(dt: float) -> void:
	if root == null or not is_instance_valid(root) or finished:
		_disconnect()
		return
	t += dt
	pose(t)
	_check_auto()


## 自动前进到头: 看别人(决赛日)停 AUTO_HOLD 后回对阵图; 出局卡下一场到点自动跟过去。
func _check_auto() -> void:
	if _left:
		return
	var cs := str(info["case"])
	var tot := total_of(cs)
	if cs == "watch" and _auto_back() and t >= tot + AUTO_HOLD:
		go_back(true)
	elif cs == "lose" and t >= tot and bool(info.get("finals", false)):
		var at := int((info.get("next", {}) as Dictionary).get("at", 0))
		var now := int(Time.get_unix_time_from_system()) + int(ReplayRecorder.play_names.get("srv_off", 0))
		if at > 0 and now >= at - FOLLOW_LEAD:
			go_next()


func _disconnect() -> void:
	Ctx.stop_ticker(_ticker)
	_ticker = null


## 点一下(暗处 / 还没淡出来的按钮位置): 跳到这一拍的终态。
func _on_input(ev: InputEvent) -> void:
	var press: bool = (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if press:
		skip_beat()


func skip_beat() -> void:
	t = skip_to(str(info["case"]), t)
	pose(t)


## 直接到全长(门禁 / 中断卡)。
func skip_all() -> void:
	t = maxf(t, total_of(str(info["case"])))
	pose(t)


# ═══════════════════════════ 画(硬边像素: 直角、整数像素, 不做平滑渐变) ═══════════════════════════

func _draw_band(c: Control) -> void:
	var s := c.size
	var f := float(c.get_meta("fill", 1.0))
	if f <= 0.01:
		return
	var a := 0.9 * f
	c.draw_rect(Rect2(0, 0, s.x, s.y), Color(0.03, 0.05, 0.095, a))
	c.draw_rect(Rect2(0, roundf(s.y * 0.2), s.x, roundf(s.y * 0.6)), Color(0.07, 0.11, 0.19, 0.5 * f))
	var line := Color(0.85, 0.71, 0.35, f)
	var seg: float = roundf(s.x * 0.04)
	for y in [0.0, s.y - 3.0]:
		c.draw_rect(Rect2(seg * 8.0, y, s.x - seg * 16.0, 3.0), line)
		for i in range(8):
			var col := Color(line.r, line.g, line.b, f * float(i + 1) / 9.0)
			c.draw_rect(Rect2(seg * float(i), y, seg, 3.0), col)
			c.draw_rect(Rect2(s.x - seg * float(i + 1), y, seg, 3.0), col)


## 结果卡: 厚边选手卡 —— 深底 + 斜纹 + 立绘那一块亮一档 + 两级斜面边(亮边在上左、暗边在下右)+ 四角铆钉;
##   边色左蓝右红(与开场同一套左右色), 赢家落定后换金并在外面加三圈金光(按 glow 呼吸)。硬边, 不做平滑渐变。
func _draw_side(c: Control, side: String) -> void:
	var s := c.size
	var won := bool(c.get_meta("won", false))
	var g := float(c.get_meta("glow", 0.0))
	if won and g > 0.0:
		for k in range(4):
			var w := float(4 - k) * 5.0
			c.draw_rect(Rect2(-w, -w, s.x + 2.0 * w, s.y + 2.0 * w), Color(1.0, 0.82, 0.30, g * (0.10 + 0.12 * float(k))))
	var edge: Color = Color("#ffd23a") if won and g > 0.3 else SIDE_COL[side]
	var hi := edge.lightened(0.35)
	var lo := edge.darkened(0.45)
	c.draw_rect(Rect2(-6, -6, s.x + 12.0, s.y + 12.0), COL_INK)
	c.draw_rect(Rect2(-4, -4, s.x + 8.0, s.y + 8.0), lo)
	c.draw_rect(Rect2(-4, -4, s.x + 8.0, 4.0), hi)
	c.draw_rect(Rect2(-4, -4, 4.0, s.y + 8.0), hi)
	c.draw_rect(Rect2(Vector2.ZERO, s), edge)
	var inner := Rect2(Vector2(6, 6), s - Vector2(12, 12))
	c.draw_rect(inner, Color(0.03, 0.05, 0.10))
	Ctx.draw_hatch(c, inner, Color(1, 1, 1, 0.035), 10.0)
	var top := Rect2(inner.position, Vector2(inner.size.x, 150.0 - 6.0))
	c.draw_rect(top, Color(edge.r * 0.18, edge.g * 0.18, edge.b * 0.22 + 0.04))
	Ctx.draw_hatch(c, top, Color(edge.r, edge.g, edge.b, 0.10), 10.0)
	c.draw_rect(Rect2(inner.position.x, top.end.y, inner.size.x, 3.0), Color(edge.r, edge.g, edge.b, 0.7))
	for p in [Vector2(2, 2), Vector2(s.x - 10.0, 2), Vector2(2, s.y - 10.0), Vector2(s.x - 10.0, s.y - 10.0)]:
		c.draw_rect(Rect2(p, Vector2(8, 8)), COL_INK)
		c.draw_rect(Rect2(p + Vector2(1, 1), Vector2(6, 6)), hi)
		c.draw_rect(Rect2(p + Vector2(2, 2), Vector2(2, 2)), Color("#ffffff"))


## 缎带 / 光芒(画法在 finals_ctx, 开场 / 结束 / 路间同一份; 这里只是绑到节点上, 不捕获节点)
func _draw_rib(c: Control) -> void:
	Ctx.draw_ribbon(c, c.size, 70.0, true)        # 红缎带: 上面压的「获胜」是金色美术字


func _draw_rays(c: Control) -> void:
	Ctx.draw_rays(c, c.size * 0.5, c.size.x * 0.5, 26.0, Color(1.0, 0.86, 0.42, 0.22))


## 阵亡划掉: 两笔红斜线, 按 p 一笔一笔画出来; 头像压灰。
func _draw_cross(c: Control) -> void:
	var p := float(c.get_meta("p", 0.0))
	if p <= 0.0:
		return
	var s := c.size
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.05, 0.55 * p))
	var col := Color("#e04848")
	var p1 := clampf(p * 2.0, 0.0, 1.0)
	var p2 := clampf(p * 2.0 - 1.0, 0.0, 1.0)
	c.draw_line(Vector2(6, 6), Vector2(6, 6) + (s - Vector2(12, 12)) * p1, col, 5.0)
	if p2 > 0.0:
		c.draw_line(Vector2(s.x - 6.0, 6), Vector2(s.x - 6.0, 6) + Vector2(-(s.x - 12.0), s.y - 12.0) * p2, col, 5.0)


## 路灯: 方形像素灯(暗座 + 亮芯), 亮了是赢下那一路的那一边的颜色; 下面写路名。
func _draw_lamp(c: Control, lab: String) -> void:
	var lit := float(c.get_meta("lit", 0.0))
	var sd := str(c.get_meta("side", ""))
	var box := Rect2(roundf(c.size.x * 0.5 - 14.0), 0, 28, 28)
	c.draw_rect(box.grow(3), COL_INK)
	c.draw_rect(box, Color("#1a2230"))
	if lit > 0.0 and sd != "":
		var col: Color = SIDE_COL[sd]
		c.draw_rect(box.grow(-3), Color(col.r, col.g, col.b, lit))
		c.draw_rect(Rect2(box.position + Vector2(5, 5), Vector2(8, 6)), Color(1, 1, 1, 0.55 * lit))
		c.draw_rect(box.grow(7), Color(col.r, col.g, col.b, 0.22 * lit), false, 4.0)
	var f := c.get_theme_default_font()
	var fs := 20
	var w := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string_outline(f, Vector2(roundf(c.size.x * 0.5 - w * 0.5), 50), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, COL_INK)
	c.draw_string(f, Vector2(roundf(c.size.x * 0.5 - w * 0.5), 50), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		COL_TEXT if lit > 0.5 else COL_SUB)


## 自动回对阵图: 一条细金条走完 + 一行字。
func _draw_auto(c: Control) -> void:
	var p := float(c.get_meta("p", 0.0))
	var s := c.size
	c.draw_rect(Rect2(0, 0, s.x, 6), COL_INK)
	c.draw_rect(Rect2(1, 1, s.x - 2.0, 4), Color("#1a2230"))
	c.draw_rect(Rect2(1, 1, roundf((s.x - 2.0) * p), 4), COL_GOLD_DIM)
	var f := c.get_theme_default_font()
	var w := f.get_string_size(TXT_AUTO_BACK, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	c.draw_string(f, Vector2(roundf(s.x * 0.5 - w * 0.5), 24), TXT_AUTO_BACK, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_SUB)
