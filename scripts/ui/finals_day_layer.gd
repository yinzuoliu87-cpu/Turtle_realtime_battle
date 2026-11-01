extends CanvasLayer
## 周日决赛日 · 全局层(autoload `FinalsDay`; 2026-10-31 方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M ④⑤⑥)。
## 不论人在哪一屏(主菜单 / 对阵图 / 商店 / 背包 / 观战页 …), 周日开赛期间:
##   ④ 全局决赛日小条: 阶段 + (开播中) + 我的处境 / 下一场 + 倒计时; 点了 ⇒ 直达对阵图(开播中 ⇒ 直达那一场)。(G16 / J-2 / 9-1)
##     ★条宽 ≤ BAR_MAX_W: 主菜单顶上玩家卡与货币条之间只空出 ~580(两比例同), 字一长条就被挤到第二行位置。
##   ⑤「你的比赛 30 秒后开播 · 观看」弹窗(还没开播点了 ⇒ 开播后自动进入)。(J-3 / J-5)
##   ⑥ 顶部跑马灯: 开播时刻 / 晋级 / 组冠军 / 冠军杯赛冠军(只收服务端下发的真东西)。(8-1)
## ★判据全在 finals_day_model(主菜单决赛日卡读同一份); 数据全在 finals_day_feed(只读 supabase.gd 已有接口)。
##
## ★什么时候在场(`active_at`): UTC 周日 17:30 闯关赛收盘之后 · 决赛日玩法已上线 · 当前这一屏是玩家的屏
##   (主菜单 / 对阵图 / 商店 / 背包 / 选龟 / 训龟大师 / 图鉴 / 排行榜 / 好友 / 战绩 / 赛况板 / 设置; 战斗屏只在看回放 / 开播时) ·
##   后端配了 · 不是无头(陪练号 / 门禁进程)。门禁用 `test_host` 把某个节点当成「这一屏」强制打开。
## ★摆在哪(`_place`): 按候选位一个个试, 取第一个不压当前这一屏任何看得见的按钮 / 输入框 / 进度条(以及 AVOID_GROUP 里登记的节点)的;
##   条只有 48 高, 点击区按触摸线 81 往外补, 量的是点击区。别的屏有不是按钮、但不该被盖住的东西 ⇒ 加进 AVOID_GROUP 即可。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _SB := preload("res://scripts/net/supabase.gd")
const _M := preload("res://scripts/ui/finals_day_model.gd")
const _FC := preload("res://scripts/ui/finals_copy.gd")
const _F := preload("res://scripts/ui/finals_day_feed.gd")
const _W := preload("res://scripts/ui/finals_day_watch.gd")
const _BAR := preload("res://scripts/ui/finals_day_bar.gd")
const _POP := preload("res://scripts/ui/finals_day_popup.gd")
const _MQ := preload("res://scripts/ui/finals_day_marquee.gd")
const _RC := preload("res://scripts/ui/finals_day_recap.gd")

const LAYER := 80
const POLL_SEC := 30
const POLL_FAST_SEC := 5
const POPUP_LEAD := 30            # 开播前这么多秒弹
const POPUP_LIVE_GRACE := 60      # 开播后这么久之内(人刚进来)还弹「开播中」
const POPUP_LINGER := 20          # 开播了没点 ⇒ 这么久后收起(条上还挂着「开播中 · 观看」)
const TOUCH_H := 81.0
const BAR_MAX_W := 560.0
## 别的屏要我让开的节点(不是按钮的标题条 / 比分条之类)加进这个组。
const AVOID_GROUP := "finals_bar_avoid"
## 别的屏想指定条放在哪: 放一个空 Control(大小 = 想让条待的那块地)进这个组, 条就居中贴在它上面(不再自己找位置)。
const DOCK_GROUP := "finals_bar_dock"
const SLOT_DOCK := 9
const BATTLE := "RealtimeBattle3D"
const BRACKET := "BracketMap"
const SCENES := ["MainMenu", "BracketMap", "Shop", "Inventory", "TeamSelect", "TrainerConfig", "Codex",
	"Leaderboard", "Friends", "Record", "GauntletBoard", "Settings", "RealtimeBattle3D"]
## 候选位(条的左上角怎么算), 按先后试。
const SLOT_TOP := 0
const SLOT_TOP_LOW := 1
const SLOT_BOTTOM := 2
const SLOT_RIGHT := 3
const SLOT_BOTTOM_LEFT := 4
const SLOT_BOTTOM_RIGHT := 5
const ORDER_DEFAULT := [SLOT_TOP, SLOT_TOP_LOW, SLOT_BOTTOM, SLOT_RIGHT, SLOT_BOTTOM_LEFT, SLOT_BOTTOM_RIGHT]
## 观战页顶上一整条是双方血量 / VS(不是按钮, 量不出来)⇒ 先试底下。
const ORDER_BATTLE := [SLOT_BOTTOM, SLOT_BOTTOM_RIGHT, SLOT_BOTTOM_LEFT, SLOT_TOP_LOW, SLOT_RIGHT, SLOT_TOP]

## 【门禁注入点】把这个节点当成「这一屏」强制打开(跳过 屏名 / 无头 / 后端 三道闸)。
var test_host: Node = null

var bar
var popup = null
var marquee
var line: Dictionary = {}         # 条上此刻那一行(门禁读)
var slot := -1                    # 条此刻在哪个候选位(门禁读)
var popped: Dictionary = {}       # 弹过的场(组:轮-场), 一场只弹一次
var opened: Array = []            # 门禁读: 弹过的场
var _hit: Button
var _target: Dictionary = {}      # 点条 ⇒ 去看哪一场(空 = 去对阵图)
var _facts_prev = null
var _had_data := false
var _cup_open_seen := false
var _next_poll := 0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	bar = _BAR.new()
	bar.visible = false
	add_child(bar)
	_hit = Button.new()
	_hit.name = "FinalsDayBarHit"
	_hit.flat = true
	_hit.focus_mode = Control.FOCUS_NONE
	_hit.visible = false
	_hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_hit.mouse_entered.connect(func() -> void: bar.modulate = Color(1.15, 1.12, 1.05))
	_hit.mouse_exited.connect(func() -> void: bar.modulate = Color.WHITE)
	_hit.pressed.connect(_on_bar_tap)
	add_child(_hit)
	marquee = _MQ.new()
	add_child(marquee)
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(tick)
	add_child(t)


# ══════════════════════════════ 在不在场 ══════════════════════════════

func host() -> Node:
	if test_host != null and is_instance_valid(test_host):
		return test_host
	return get_tree().current_scene if get_tree() != null else null


static func scene_key(n: Node) -> String:
	if n == null:
		return ""
	return str(n.scene_file_path).get_file().get_basename()


## 这台进程该不该挂全局层: 无头(陪练号 / 裁判机 / 门禁进程)不挂; 后端没配(没有赛程数据可言)不挂。纯函数, 门禁直接量。
static func gate_ok(display: String, sb_enabled: bool) -> bool:
	return display != "headless" and sb_enabled


func active_at(now: int) -> bool:
	if not _M.is_finals_time(now) or not _P2.phase_mode_live(_P2.PHASE_FINALS):
		return false
	var h := host()
	if h == null:
		return false
	if test_host != null and is_instance_valid(test_host):
		return true
	if not gate_ok(DisplayServer.get_name(), _SB.enabled()):
		return false
	var k := scene_key(h)
	if not (k in SCENES):
		return false
	if k == BATTLE:
		var rp = h.get("_replay")
		return rp != null and rp.has_method("is_playing") and bool(rp.is_playing())
	var td = get_node_or_null("/root/TutorialDirector")
	if td != null and td.has_method("in_sandbox") and bool(td.in_sandbox()):
		return false
	return true


# ══════════════════════════════ 每秒一拍 ══════════════════════════════

func tick() -> void:
	var now: int = _P2.now_utc()
	var on := active_at(now)
	bar.visible = on
	_hit.visible = on and bool(line.get("tap", false))
	if not on:
		if popup != null and is_instance_valid(popup):
			_close_popup()
		marquee.visible = false
		return
	if _F.override.is_empty() and now >= _next_poll:
		_F.pull(now)
		_next_poll = now + POLL_SEC
	var f: Dictionary = _F.feeds()
	var group: Dictionary = f["group"]
	var cup: Dictionary = f["cup"]
	var groups: Array = f["groups"]
	var ent := _F.entered()
	var mn: Dictionary = _M.my_next(ent, group, cup, now)
	## 我的场快到 / 等翻面 ⇒ 问勤一点(开播时刻要准)
	var at := int(mn.get("at", 0))
	if str(mn.get("k", "")) in [_M.K_WAIT, _M.K_UPCOMING, _M.K_NEXT] and at > 0 and at - now <= 40:
		_next_poll = mini(_next_poll, now + POLL_FAST_SEC)
	line = bar_line(now, group, cup, groups, mn, scene_key(host()) == BATTLE)
	_target = line.get("target", {})
	bar.paint(line)
	_hit.visible = bool(line.get("tap", false))
	_place()
	_popup_tick(now, mn)
	_marquee_tick(now, groups, cup, int(group.get("bucket", -1)) if ent else -1)
	_recap_mark(now, cup)


## 条上那一行: {"head", "live", "body", "cd", "act", "tap", "target"}。纯函数(门禁穷举)。
## `in_battle` = 正在观战页: 点条不跳走(会把正在看的那一场关掉)。
## ★2026-11-01 改写(用户「一定要按照商业游戏的口吻…不要乱乱用这种语句」):
##   · 正文一件事, 不再「· 观看」「备战中 · 不调整就沿用当前阵容」拼两件事; 能点的那一档在右边单列「观看」(act)。
##   · 倒计时只有一种写法(`finals_copy.dur`, 原来「2:58」「0:29:58」紧挨着「18:00 开赛」读着像钟点)。
##   · 「开播中」红签只在**真有一场在播**时亮(原来整段小组赛都亮, 18:05 一场都没播也写「开播中」)。
##   · 下一场的时刻走 `premiere_eta`(与对阵图处境句 / 底部「下一场」卡同一个答案)。
static func bar_line(now: int, group: Dictionary, cup: Dictionary, groups: Array, mn: Dictionary,
		in_battle: bool = false) -> Dictionary:
	var ph := _M.phase(now, groups, cup)
	## 条头一律「决赛日」(哪一段写在正文里, 不在条头再说一遍)
	var out := {"head": "决赛日", "live": false, "body": "", "cd": -1, "act": "", "tap": not in_battle, "target": {}}
	var at := int(mn.get("at", 0))
	var rn := ""
	if not (mn.get("b", {}) as Dictionary).is_empty() and int(mn.get("r", 0)) >= 1:
		rn = short_stage(mn["b"], int(mn["r"]))
	match str(mn.get("k", "")):
		_M.K_SHOP:
			out["body"] = "%s备战剩余" % rn
			out["cd"] = at - now
		_M.K_UPCOMING:
			out["body"] = "%s %s 开播" % [_FC.join("你的", rn), _P2.local_hhmm(at)]
			out["cd"] = at - now
		_M.K_LIVE:
			out["body"] = _FC.join("你的", rn)         # 「开播中」由左边红签说, 正文不再说一遍
			out["live"] = true
			out["act"] = "观看"
			out["target"] = mn
		_M.K_NEXT:
			out["body"] = "%s备战 %s 开始" % [rn, _P2.local_hhmm(at)]
			out["cd"] = at - now
		_M.K_WAIT:
			if at > now:
				out["body"] = "%s %s 开播" % [_FC.join("你的", rn), _P2.local_hhmm(at)]
				out["cd"] = at - now
			else:
				out["body"] = _FC.join("你的", rn) + "即将开播"
		_M.K_CUP_WAIT:
			out["body"] = "%s %s 开赛" % [_P2.STAGE_CUP, _P2.local_hhmm(at)]
			out["cd"] = at - now
	if str(out["body"]) != "":
		return _battle_trim(out, in_battle)
	match ph:
		_M.PH_PRE:
			out["body"] = "%s %s 开赛" % [_P2.STAGE_GROUP, _P2.local_hhmm(_M.seat_ts(now))]
			out["cd"] = _M.seat_ts(now) - now
		_M.PH_INTER:
			out["body"] = "%s %s 开赛" % [_P2.STAGE_CUP, _P2.local_hhmm(_M.cup_ts(now))]
			out["cd"] = _M.cup_ts(now) - now
		_M.PH_DONE:
			var sd := _M.champion_visible(cup, now)
			out["body"] = "你获得冠军杯赛冠军" if sd >= 0 and sd == int(cup.get("me", -1)) else _FC.kv("冠军杯赛冠军", _M.name_of(cup, sd))
		_:
			var live: Array = _M.live_all(groups, cup, now)
			## 我那一组排前面(组里输了的人最关心的还是自己那一组)
			var mine := int(group.get("bucket", -9))
			live.sort_custom(func(a, b): return int((a["b"] as Dictionary).get("bucket", 0)) == mine and int((b["b"] as Dictionary).get("bucket", 0)) != mine)
			var stage := _P2.STAGE_CUP if ph == _M.PH_CUP else _P2.STAGE_GROUP
			if not live.is_empty():
				var t: Dictionary = live[0]
				out["body"] = _M.stage_line(t["b"], int(t["r"])) if live.size() == 1 \
					else ("%s %d 场" % [stage, live.size()])
				out["live"] = true
				out["act"] = "观看"
				out["target"] = t
			else:
				var eta := 0
				for b in ([cup] if ph == _M.PH_CUP else groups):
					var e: Dictionary = _M.premiere_eta(b, now) if b is Dictionary else {}
					if not e.is_empty() and (eta == 0 or int(e["at"]) < eta):
						eta = int(e["at"])
				var prep := _M.prep_eta([cup] if ph == _M.PH_CUP else groups, now)
				if eta > now:
					out["body"] = "%s下一场 %s 开播" % [stage, _P2.local_hhmm(eta)]
					out["cd"] = eta - now
				elif prep > now:
					out["body"] = "%s下一轮备战 %s 开始" % [stage, _P2.local_hhmm(prep)]
					out["cd"] = prep - now
				else:
					out["body"] = "%s进行中" % stage
	return _battle_trim(out, in_battle)


## 观战页上点条不跳走 ⇒ 不写「观看」(写了点不动 = 骗人)。
static func _battle_trim(out: Dictionary, in_battle: bool) -> Dictionary:
	if in_battle:
		out["act"] = ""
	return out


## 我那一场叫什么: 冠军杯赛只说轮次(「半决赛」), 小组赛带组号前面那段由条头 / 弹窗里另说 ⇒ 只说轮次。
static func short_stage(b: Dictionary, r: int) -> String:
	return _M.round_name(int(b.get("size", 0)), r)


# ══════════════════════════════ 摆在哪 ══════════════════════════════

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


## 条在候选位 `s` 时的左上角。
func slot_pos(s: int, sz: Vector2) -> Vector2:
	var vp := _vp()
	var sm: Vector4 = SafeArea.margins(vp, 6.0)
	var cx := roundf((vp.x - sz.x) / 2.0)
	match s:
		SLOT_TOP:
			return Vector2(cx, sm.y)
		SLOT_TOP_LOW:
			return Vector2(cx, sm.y + 88.0)
		SLOT_BOTTOM:
			return Vector2(cx, vp.y - sm.w - sz.y)
		SLOT_RIGHT:
			return Vector2(vp.x - sm.z - sz.x - 8.0, sm.y + 96.0)
		SLOT_BOTTOM_LEFT:
			return Vector2(sm.x + 8.0, vp.y - sm.w - sz.y)
		_:
			return Vector2(vp.x - sm.z - sz.x - 8.0, vp.y - sm.w - sz.y)


## 条在这个位置时的点击区(条宽 × 81, 竖向以条为中心, 顶出屏就往里收)。
func hit_rect(pos: Vector2, sz: Vector2) -> Rect2:
	var vp := _vp()
	var y := clampf(pos.y + sz.y / 2.0 - TOUCH_H / 2.0, 0.0, maxf(0.0, vp.y - TOUCH_H))
	return Rect2(pos.x, y, sz.x, TOUCH_H)


## 当前这一屏看得见、点得着的东西(视口坐标)。
func blockers() -> Array:
	var out: Array = []
	var vp := _vp()
	_collect(host(), out, vp.x * vp.y)
	for n in get_tree().get_nodes_in_group(AVOID_GROUP):
		if n is Control and (n as Control).is_visible_in_tree() and not is_ancestor_of(n):
			out.append(_canvas_rect(n as Control))
	return out


func _collect(n: Node, out: Array, vp_area: float) -> void:
	if n == null or n is Node3D or n is SubViewport:
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is Control and ((n is BaseButton) or (n is LineEdit) or (n is Range) or (n is TextEdit)) \
			and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		var r := _canvas_rect(n as Control)
		if r.size.x > 4.0 and r.size.y > 4.0 and r.size.x * r.size.y < vp_area * 0.4:
			out.append(r)
	for ch in n.get_children():
		_collect(ch, out, vp_area)


static func _canvas_rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return Rect2(xf.origin, c.size * xf.get_scale()).abs()


static func _overlap(r: Rect2, blk: Array) -> float:
	var a := 0.0
	for b in blk:
		var i := r.intersection(b as Rect2)
		a += i.size.x * i.size.y
	return a


## 这一屏登记的停靠位(DOCK_GROUP 里第一个看得见、属于这一屏的); 没有 = Rect2()。
func dock_rect() -> Rect2:
	var h := host()
	for n in get_tree().get_nodes_in_group(DOCK_GROUP):
		if n is Control and (n as Control).is_visible_in_tree() and h != null and h.is_ancestor_of(n):
			return _canvas_rect(n as Control)
	return Rect2()


func slot_pos_any(s: int, sz: Vector2) -> Vector2:
	if s == SLOT_DOCK:
		var r := dock_rect()
		var vp := _vp()
		return Vector2(clampf(roundf(r.get_center().x - sz.x / 2.0), 0.0, maxf(0.0, vp.x - sz.x)),
			clampf(roundf(r.get_center().y - sz.y / 2.0), 0.0, maxf(0.0, vp.y - sz.y)))
	return slot_pos(s, sz)


func _place() -> void:
	var sz: Vector2 = bar.get_combined_minimum_size()
	bar.size = sz
	var best := -1
	if dock_rect().size.x > 0.0:
		best = SLOT_DOCK
	else:
		var blk := blockers()
		var order: Array = ORDER_BATTLE if scene_key(host()) == BATTLE else ORDER_DEFAULT
		var best_a := INF
		for s in order:
			var a := _overlap(hit_rect(slot_pos(int(s), sz), sz), blk)
			if a <= 0.0:
				best = int(s)
				break
			if a < best_a:
				best_a = a
				best = int(s)
	var pos := slot_pos_any(best, sz)
	if best != slot and slot >= 0 and bar.visible:
		bar.create_tween().tween_property(bar, "position", pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		bar.position = pos
	slot = best
	var hr := hit_rect(pos, sz)
	_hit.position = hr.position
	_hit.size = hr.size
	## 跑马灯: 条在顶上 ⇒ 挂在条下面; 否则挂顶上正中。
	var vp := _vp()
	var my := pos.y + sz.y + 8.0 if best in [SLOT_TOP, SLOT_TOP_LOW] else SafeArea.margins(vp, 6.0).y
	marquee.position = Vector2(roundf((vp.x - marquee.size.x) / 2.0), my)


# ══════════════════════════════ 点条 ══════════════════════════════

func _on_bar_tap() -> void:
	if not _target.is_empty():
		watch(_target)
		return
	if scene_key(host()) != BRACKET and test_host == null:
		SceneNav.go(get_tree(), _W.BRACKET)


## 去看某一场(开播中 / 已揭晓); 打不开(还没轮到 / 取不到)⇒ 去对阵图。
var last_watch: Dictionary = {}          # 门禁读: 最近一次要去看哪一场
func watch(t: Dictionary) -> bool:
	var b: Dictionary = t.get("b", {})
	var now: int = _P2.now_utc()
	last_watch = {"bucket": int(b.get("bucket", -1)), "r": int(t.get("r", 0)), "m": int(t.get("m", -1)), "at": now}
	if test_host != null:
		return _W.can_open(b, int(t.get("r", 0)), int(t.get("m", -1)), now)
	if _W.open(get_tree(), _P2.week_anchor_utc(now), b, int(t.get("r", 0)), int(t.get("m", -1)), now, _W.BRACKET, _on_watch_fail):
		return true
	if scene_key(host()) != BRACKET:
		SceneNav.go(get_tree(), _W.BRACKET)
	return false


func _on_watch_fail(_code: String, msg: String) -> void:
	if msg != "":
		marquee.push(msg)


# ══════════════════════════════ 30 秒弹窗 ══════════════════════════════

static func match_key(mn: Dictionary) -> String:
	var b: Dictionary = mn.get("b", {})
	return "%d:%d-%d" % [int(b.get("bucket", -1)), int(mn.get("r", 0)), int(mn.get("m", -1))]


## 横幅上的秒数: ≥ 0 = 「N 秒后开播」; -2 = 「即将开播」(过了服务端给的时刻还没翻面)。
static func popup_secs(k: String, at: int, now: int) -> int:
	if at - now > 0:
		return at - now
	return -2 if k == _M.K_WAIT else 1


## 横幅第二行那句: 「吃货一枚 对 Kiki」(哪一场写在横幅标题「你的 C 组半决赛…」里, 不在这一行再拼一遍)。
static func popup_line(mn: Dictionary) -> String:
	var b: Dictionary = mn.get("b", {})
	return "%s 对 %s" % [_M.name_of(b, int(mn.get("me_sd", -1))), str(mn.get("opp", ""))]


func _popup_tick(now: int, mn: Dictionary) -> void:
	var k := str(mn.get("k", ""))
	var key := match_key(mn) if k in [_M.K_UPCOMING, _M.K_LIVE, _M.K_WAIT] else ""
	var at := int(mn.get("at", 0))
	if popup != null and is_instance_valid(popup):
		if key != str(popup.key):
			_close_popup()
			return
		if k == _M.K_UPCOMING or k == _M.K_WAIT:
			popup.paint(popup_secs(k, at, now), popup_line(mn))
		else:
			if bool(popup.armed):
				_close_popup()
				watch(mn)
				return
			popup.paint(-1, popup_line(mn))
			if now - at > POPUP_LINGER:
				_close_popup()
		return
	if key == "" or popped.has(key):
		return
	## ★小组赛同一轮所有场在翻面那一刻同时开播(用户 10-31 纠正) ⇒ 我的场没有「即将开播」那一态, 只有「等翻面」(K_WAIT):
	##   按服务端给的翻面时刻(next_at)提前 30 秒弹, 数到 0 还没翻 ⇒ 「即将开播」(服务端每分钟推进, 会晚几十秒)。
	if (k == _M.K_UPCOMING and at - now <= POPUP_LEAD and at - now > 0) or (k == _M.K_WAIT and at > 0 and at - now <= POPUP_LEAD) 			or (k == _M.K_LIVE and now - at <= POPUP_LIVE_GRACE):
		## 正在看的就是这一场 ⇒ 不弹
		if scene_key(host()) == BATTLE and str(_W.last_ask.get("bucket", "")) == str(int((mn["b"] as Dictionary).get("bucket", -1))) 				and int(_W.last_ask.get("round", 0)) == int(mn["r"]) and int(_W.last_ask.get("match", -1)) == int(mn["m"]):
			popped[key] = true
			return
		_open_popup(key, mn, now)


## 横幅放在哪: 顶上正中, 从屏外滑下来; 盖住全局小条(横幅本身就说着同一件事)。
## ★顶上两角常是玩家卡 / 货币条(主菜单两者之间只空出 ~575): 正中压到哪颗按钮就左右挪一点(每次 6 像素, 最多 60), 挪不开才留在正中。
func popup_home() -> Vector2:
	var vp := _vp()
	var y := SafeArea.margins(vp, 6.0).y - 2.0
	var x0 := roundf((vp.x - _POP.W) / 2.0)
	var blk := blockers()
	for k in range(21):
		var dx := 6.0 * float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
		var r := Rect2(x0 + dx, y, _POP.W, _POP.H)
		if _overlap(r, blk) <= 0.0:
			return r.position
	return Vector2(x0, y)


func _open_popup(key: String, mn: Dictionary, now: int) -> void:
	popped[key] = true
	opened.append(key)
	popup = _POP.new()
	popup.key = key
	var b: Dictionary = mn["b"]
	popup.stage_name = _M.round_name(int(b.get("size", 0)), int(mn["r"]))
	add_child(popup)
	var wk: int = _P2.week_anchor_utc(now)
	popup.set_pair(_F.avatar_of(wk, _M.tag_of(b, int(mn.get("me_sd", -1)))), _F.avatar_of(wk, _M.tag_of(b, int(mn.get("opp_sd", -1)))))
	var at := int(mn.get("at", 0))
	var k := str(mn.get("k", ""))
	popup.paint(popup_secs(k, at, now) if k in [_M.K_UPCOMING, _M.K_WAIT] else -1, popup_line(mn))
	popup.enter(popup_home())
	popup.watch_pressed.connect(func() -> void: _on_popup_watch(mn))
	popup.later_pressed.connect(_close_popup)


func _on_popup_watch(mn: Dictionary) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	var now: int = _P2.now_utc()
	if _W.can_open(mn["b"], int(mn["r"]), int(mn["m"]), now):
		_close_popup()
		watch(mn)
		return
	## 还没开播: 不硬开, 开播那一拍自动进(`_popup_tick`)
	popup.armed = true
	popup.paint(maxi(1, int(mn.get("at", now)) - now), str(popup.sub.text))


func _close_popup() -> void:
	if popup != null and is_instance_valid(popup):
		var p = popup
		popup = null
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw: Tween = p.create_tween().set_parallel(true)
		tw.tween_property(p, "position:y", float(p.position.y) - float(_POP.H) - 20.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(p, "modulate:a", 0.0, 0.25)
		tw.chain().tween_callback(p.queue_free)
	popup = null


# ══════════════════════════════ 跑马灯 ══════════════════════════════

func _marquee_tick(now: int, groups: Array, cup: Dictionary, mine: int) -> void:
	var fa: Dictionary = _M.facts(groups, cup, now, mine)
	var has_data := not groups.is_empty() or not cup.is_empty()
	## 开屏那一拍 / 数据第一次到 ⇒ 只当底(已经发生的不刷一遍)
	if _facts_prev == null or (has_data and not _had_data):
		_facts_prev = fa
		_had_data = has_data
		return
	if popup == null or not is_instance_valid(popup):
		for k in fa:
			if not (_facts_prev as Dictionary).has(k):
				marquee.push(str(fa[k]))
	else:
		## 弹窗在场时先不播(一次一件事), 留到下一拍
		for k in fa:
			if not (_facts_prev as Dictionary).has(k):
				return
	_facts_prev = fa


# ══════════════════════════════ 收盘补看的「看过了」 ══════════════════════════════

## 这个进程亲眼见到冠军杯赛从「没决出」到「决出」(在场守到了最后)⇒ 记下, 下次打开不再补看(G21 只给没守到最后的人)。
func _recap_mark(now: int, cup: Dictionary) -> void:
	if cup.is_empty():
		return
	if _M.champion_visible(cup, now) < 0:
		_cup_open_seen = true
	elif _cup_open_seen:
		_cup_open_seen = false
		_RC.mark_seen(_P2.week_anchor_utc(now))
