extends Node
## verify_menu_finals_hero.gd — 周日主菜单: 「今天的事」卡 + 按身份的主按钮(方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M ①②③⑦)
##
## 由来(2026-10-31 内测服彩排实走 + 百款调研): 决赛日主菜单最大的按钮是上了锁的「开始战斗」(P17); 17:30 收盘后倒计时没了(P18);
##   「查看对阵图 »」先进赛程页还要再点一次(P19)。商业游戏(王者 / 8BP / HB2 / RAID / Stumble Guys / LoL 活动中心)的共同做法 G14 / G15:
##   赛事当天最大位置是一张「今天的事」卡(倒计时 / 进行中 / 已结束三态, 下挂小组赛 / 冠军杯赛两张子卡各自倒计时),
##   按身份给主按钮(晋级者「我的比赛」/ 其他人「观看开播」), 「我这一路」格子条打完翻 ✓ / ✗, 开播中进来主按钮直达观看(G17)。
##   改法在 scripts/scenes/menu_finals_day.gd + scripts/ui/finals_day_card.gd, 判据在 scripts/ui/finals_day_model.gd。
##
## ① 周一~周六主按钮 / 模式卡与改动前**完全相同**(从 git 取改动前的主菜单现编一份逐节点比签名; 浅克隆比签名摘要表)。
## ② 周日一整晚(数据照服务端一场接一场排: tests/_finals_day_fixture.gd)逐时刻: 主按钮大字 / 副标 / 点了去哪、
##    卡的状态带三态 / 两张子卡 / 我这一路每一格 / 模式卡倒计时与读数 —— 晋级者、观众、第 1 轮就输的人三种。
## ③ ★不剧透: 我那场开播中(结果已在服务端、还没播完)⇒ 格子是「进行中」、主按钮不写止步。
## ④ 每秒一拍: 跨 18:00 / 冠军杯赛开赛 副标换字 + 闪 + 飘一句(人人都飘); 只走倒计时不闪; 结果揭晓 ⇒ 格子翻牌; 17:30 / 周一 00:00 主按钮当场换。
## ⑤ 就绪光 / 卡在动(开播点 / 子卡金边 / 我这一格 / 奖杯); 字装得下; 卡不压主按钮 / 训龟大师 / 模式卡 / 绑定提示, 两比例都量。
## ⑥ 上周冠军挂门面(名字 + 头像); 拿不到 ⇒ 写今天的看点。
## ⑦ 周日这一屏只读一次钟。
##
## 跑法: bash godot-quiet.sh res://tests/verify_menu_finals_hero.tscn --quit-after 3000

const MENU := preload("res://scripts/scenes/MainMenuScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const FD := preload("res://scripts/scenes/menu_finals_day.gd")
const CARD := preload("res://scripts/ui/finals_day_card.gd")
const M := preload("res://scripts/ui/finals_day_model.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")

const BASE := "b98325c8"
const MENU_FILE := "scripts/scenes/MainMenuScene.gd"
const MON := 1789344000                  # 2026-09-14 周一 00:00 UTC(本周锚点)
const SUN := MON + 6 * 86400
const H := 3600
const MI := 60
## 改动前那份主菜单在周一~周六 12:00 两种人(plain = 积分赛打着、没资格; in = 已晋级决赛日)的签名摘要。
const PINNED := {
	"plain/1": "86ca4f054b9ac4d66d949b6d995ebe9e1f32fb23b7160303524256e63afbe45b",
	"plain/2": "312fd090dfcc78d3aa0ef58fdd121d25a4f22d864a00654dc68fddf85f6643fd",
	"plain/3": "7684fd62415b9f4592757c71405090de04b504e327ea9135abe368677b926c53",
	"plain/4": "b5219aa606f2bdb5242d36985def0019956d4e1625c56b1b5e4056eb9f2f4ed8",
	"plain/5": "05a27a627234b85d177a16cd16f98e712b040d481fc62c94b5603e4126c6ef59",
	"plain/6": "9aa6b8f98be18253d980d53a5a6a63dc12250a87a1285d01ac69cc4a14b51c4a",
	"in/1": "86ca4f054b9ac4d66d949b6d995ebe9e1f32fb23b7160303524256e63afbe45b",
	"in/2": "312fd090dfcc78d3aa0ef58fdd121d25a4f22d864a00654dc68fddf85f6643fd",
	"in/3": "7684fd62415b9f4592757c71405090de04b504e327ea9135abe368677b926c53",
	"in/4": "b5219aa606f2bdb5242d36985def0019956d4e1625c56b1b5e4056eb9f2f4ed8",
	"in/5": "05a27a627234b85d177a16cd16f98e712b040d481fc62c94b5603e4126c6ef59",
	"in/6": "ad582841d771e8d0f0ebc6dcb1b3650fde05117b6bf94025ca4ace6bc091f1e2",   # 2026-11-01 改字后(见 _intended)
}

const KEYS := ["hearts", "ranked_used", "season_total_battles", "season_id", "season_wins", "promoted",
	"gauntlet_wins", "gauntlet_losses", "finals_champion", "finals_runner_up", "finals_cup_champion",
	"finals_cup_runner_up", "test_mode"]

var _n := 0
var _fail := 0
var _pend := 0
var _bak := {}
var fx


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日主菜单: 「今天的事」卡 + 按身份的主按钮 + 我这一路 + 上周冠军 ===")
	for k in KEYS:
		_bak[k] = GameState.get(k)
	GameState.test_mode = true
	fx = FX.new(MON)
	F.prev_champ = {}
	var mm = await _mk(MENU, MON + 12 * H)
	var old_s = _old_script()
	var om = null
	if old_s != null:
		om = await _mk(old_s, MON + 12 * H)
	_ok("★分母: 现在的主菜单建起来了", mm != null and mm.page_box != null and mm.content_root != null)
	if mm == null or mm.page_box == null:
		_done()
		return
	_quiet(mm)
	_quiet(om)
	_t_weekdays(mm, om)
	_t_sunday(mm)
	_t_nospoil(mm)
	await _t_tick(mm)
	await _t_motion(mm)
	_t_champ(mm)
	await _t_layout(mm)
	if om != null:
		om.queue_free()
	mm.queue_free()
	await get_tree().process_frame
	await _t_clock_reads()
	_done()


func _done() -> void:
	for k in _bak.keys():
		GameState.set(k, _bak[k])
	F.prev_champ = {}
	if _fail == 0:
		print("ALL PASS (%d%s)" % [_n, (" · %d 条待复核" % _pend) if _pend > 0 else ""])
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


# ───────────────────────────── 搭台 ─────────────────────────────

func _mk(script, ts: int):
	var m = script.new()
	m.clock_override_ts = ts
	add_child(m)
	for _i in range(6):
		await get_tree().process_frame
	return m


## 主菜单每秒那一拍(`_sb_poll`)停掉: 这份测试自己按时刻调 `tick`, 不让真实时间插进来改屏。
func _quiet(m) -> void:
	if m == null:
		return
	for c in m.get_children():
		if c is Timer:
			for cn in (c as Timer).timeout.get_connections():
				if (cn["callable"] as Callable).get_method() == "_sb_poll":
					(c as Timer).stop()


## 两种人。plain = 积分赛打着(没资格进周六); in = 闯关赛 4-0 已晋级决赛日。名次一律清零。
func _state(kind: String) -> void:
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.ranked_used = 3
	GameState.season_total_battles = 3
	GameState.season_id = 2
	GameState.season_wins = 2
	GameState.promoted = false
	GameState.gauntlet_wins = 0
	GameState.gauntlet_losses = 0
	GameState.finals_champion = false
	GameState.finals_runner_up = false
	GameState.finals_cup_champion = false
	GameState.finals_cup_runner_up = false
	if kind == "in":
		GameState.promoted = true
		GameState.season_wins = int(P2.PROMOTE_WINS)
		GameState.gauntlet_wins = int(P2.GAUNTLET_WINS_IN)


## 照产品那一下重建主按钮那一栏 + 模式卡(同一刻)。
func _rebuild(m, ts: int) -> void:
	m.clock_override_ts = ts
	for c in m.page_box.get_children():
		m.page_box.remove_child(c)
		c.queue_free()
	m._build_page_buttons(ts)
	m._mode_card(ts)


## 喂这一刻服务端会给的数据(晋级者 / 观众 / 第 1 轮就输)。
func _feed(m, ts: int, who: String) -> void:
	fx.me_in = who != "plain"
	fx.group_wins[FX.MY_GROUP] = {"1-1": 0} if who == "out" else {"1-1": 1, "2-0": 1}
	m._wk().fd.feed_override = fx.feeds(ts)


# ───────────────────────────── 签名 ─────────────────────────────

## ★2026-11-01 全游戏文案按商业口吻(方案书 docs/plans/20261101f-全游戏文案按商业口吻.md): 周六已晋级那一格(in/6)的模式卡第二行
##   有意改字 —— 「4-0 · 已晋级决赛日」(「·」拼两件事)→「已晋级决赛日（4-0）」。比对前把改动前那份签名里的这一句换成新写法
##   (只换这一处字, 其余节点 / 位置 / 颜色照旧逐个比); 摘要表 in/6 = 换过之后那份的摘要。其余 11 格一个字没动。
func _intended(key: String, s: String) -> String:
	if key != "in/6":
		return s
	var lab: String = P2.gauntlet_label(int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	return s.replace("text=%s · 已晋级决赛日 " % lab, "text=已晋级决赛日（%s） " % lab)


func _sig(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "<null>"
	var out := PackedStringArray()
	_walk_sig(n, 0, out)
	return "\n".join(out)


func _cs(c: Color) -> String:
	return "%.2f,%.2f,%.2f,%.2f" % [c.r, c.g, c.b, c.a]


func _walk_sig(n: Node, depth: int, out: PackedStringArray) -> void:
	var p := PackedStringArray([str(depth), n.get_class()])
	var nm := str(n.name)
	p.append("" if nm.begins_with("@") else nm)
	var sc = n.get_script()
	if sc != null:
		p.append(str(sc.resource_path).get_file())
	if n is Control:
		var c := n as Control
		p.append("pos=%s" % str(c.position.round()))
		if not (n is Label):
			p.append("size=%s" % str(c.size.round()))
		p.append("vis=%s mf=%d" % [str(c.visible), c.mouse_filter])
	if n is CanvasItem:
		p.append("mod=%s smod=%s" % [_cs((n as CanvasItem).modulate), _cs((n as CanvasItem).self_modulate)])
	if n is Label:
		var l := n as Label
		p.append("text=%s fs=%d col=%s" % [l.text, l.get_theme_font_size("font_size"), _cs(l.get_theme_color("font_color"))])
	if n is Button:
		var b := n as Button
		p.append("btext=%s dis=%s go=%s" % [b.text, str(b.disabled), _dest(b)])
	var tex: Texture2D = null
	if n is TextureRect:
		tex = (n as TextureRect).texture
	elif n is NinePatchRect:
		tex = (n as NinePatchRect).texture
	if tex != null:
		p.append("tex=%s" % (str(tex.resource_path).get_file() if str(tex.resource_path) != "" else "gen%dx%d" % [tex.get_width(), tex.get_height()]))
	if n is ColorRect:
		p.append("color=%s" % _cs((n as ColorRect).color))
	out.append(" | ".join(p))
	for ch in n.get_children():
		_walk_sig(ch, depth + 1, out)


## 这颗按钮点下去走哪个方法(`_frame_button` 包了一层 `_btn_press`, 拆开看里面那个)。
func _dest(b: BaseButton) -> String:
	var names := PackedStringArray()
	for sg in ["button_down", "pressed"]:
		for cn in b.get_signal_connection_list(sg):
			var cl: Callable = cn["callable"]
			if cl.get_method() == "_btn_press":
				var ba: Array = cl.get_bound_arguments()
				names.append(str((ba[2] as Callable).get_method()) if ba.size() >= 3 and ba[2] is Callable else "_btn_press?")
			elif cl.get_method() != "_btn_hover":
				names.append(str(cl.get_method()))
	return ",".join(names)


func _hero_go(m) -> String:
	var h: Node = m._hero_btn
	if h == null or not is_instance_valid(h):
		return ""
	for c in h.get_children():
		if c is Button:
			return _dest(c)
	return ""


# ───────────────────────────── ① 周一~周六一字不动 ─────────────────────────────

func _t_weekdays(mm, om) -> void:
	print("--- ① 周一~周六: 主按钮 / 模式卡与改动前完全相同 ---")
	print("  改动前那份主菜单(%s)现编出来了: %s" % [BASE, str(om != null)])
	if om == null:
		print("  [PEND] 本机取不到 %s(浅克隆)或编不过: 改走签名摘要表" % BASE)
		_pend += 1
	var same := 0
	var cmp := 0
	var bad: Array = []
	var bad_pin: Array = []
	var prov_bad: Array = []
	var start_n := 0
	for kind in ["plain", "in"]:
		_state(kind)
		for d in range(6):
			var ts: int = MON + d * 86400 + 12 * H
			_rebuild(mm, ts)
			var key := "%s/%d" % [kind, d + 1]
			var s_new: String = _sig(mm._hero_btn) + "\n#\n" + _sig(mm._mode_box)
			var dg := s_new.sha256_text()
			if _sig(mm._hero_btn).find("text=开始战斗") >= 0 and mm.page_box.find_child(FD.N_HERO, true, false) == null \
					and mm.page_box.find_child(CARD.NODE_NAME, true, false) == null:
				start_n += 1
			if om != null:
				_rebuild(om, ts)
				var s_old: String = _intended(key, _sig(om._hero_btn) + "\n#\n" + _sig(om._mode_box))
				cmp += 1
				if s_old == s_new:
					same += 1
				else:
					bad.append("%s 第一处不同: %s" % [key, _first_diff(s_old, s_new)])
				if PINNED.has(key) and str(PINNED[key]) != s_old.sha256_text():
					prov_bad.append(key)
			if PINNED.has(key) and str(PINNED[key]) != dg:
				bad_pin.append("%s(现 %s)" % [key, dg])
	_ok("① ★平日主按钮全是「开始战斗」、没有决赛日那一颗 / 没有决赛日卡(12 格)", start_n == 12, "%d / 12" % start_n)
	if om != null:
		_ok("① ★★周一~周六 × 两种人: 主按钮 + 模式卡与改动前逐节点相同(分母 12)", cmp == 12 and same == 12, "%d / %d · %s" % [same, cmp, str(bad)])
		_state("in")
		_rebuild(mm, SUN + 19 * H)
		_rebuild(om, SUN + 19 * H)
		_ok("① ★分母: 周日 19:00 同一份存档, 改动前后主按钮不同(尺子量得出差别)", _sig(mm._hero_btn) != _sig(om._hero_btn)
			and _sig(om._hero_btn).find("text=开始战斗") >= 0 and _sig(mm._hero_btn).find(FD.N_HERO) >= 0)
		_ok("① 签名摘要表 = 从 %s 现编那份算的(出处可复核)" % BASE, prov_bad.is_empty(), str(prov_bad))
	_ok("① ★★周一~周六 × 两种人: 签名 == 摘要表(CI 浅克隆时就靠这一条)", PINNED.size() == 12 and bad_pin.is_empty(), str(bad_pin))


func _first_diff(a: String, b: String) -> String:
	var la := a.split("\n")
	var lb := b.split("\n")
	for i in range(mini(la.size(), lb.size())):
		if la[i] != lb[i]:
			return "改前「%s」/ 现在「%s」" % [la[i], lb[i]]
	return "行数 %d / %d" % [la.size(), lb.size()]


# ───────────────────────────── ② 周日一整晚 ─────────────────────────────

func _txt(root: Node, nm: String) -> String:
	if root == null or not is_instance_valid(root):
		return "<null>"
	var n := root.find_child(nm, true, false)
	return str((n as Label).text) if n is Label else "<无 %s>" % nm


func _card(m) -> Node:
	return m.page_box.find_child(CARD.NODE_NAME, true, false)


## 卡上「我这一路」此刻每一格的状态串: "group:半决赛=won,..." 。
func _cells(m) -> String:
	var c = _card(m)
	if c == null:
		return "<无卡>"
	var out := PackedStringArray()
	for x in (c.cells as Array):
		out.append("%s:%s=%s" % [str(x["sec"]), str(x["label"]), str(x["st"])])
	return ",".join(out)


## 卡上所有字里预告下一场比赛的那几个词(空 = 没有)。
const NEXT_WORDS := ["下周", "周二", "周六", "闯关赛", "积分赛", "大轮"]
func _words_in(root: Node, words: Array) -> Array:
	var out: Array = []
	for l in root.find_children("*", "Label", true, false):
		for w in words:
			if str((l as Label).text).find(w) >= 0:
				out.append("%s「%s」" % [l.name, (l as Label).text])
	return out


func _next_event_words(root: Node) -> Array:
	var out: Array = []
	for l in root.find_children("*", "Label", true, false):
		for w in NEXT_WORDS:
			if str((l as Label).text).find(w) >= 0:
				out.append("%s「%s」" % [l.name, (l as Label).text])
	return out


func _hm(ts: int) -> String:
	return P2.local_hhmm(ts)


func _t_sunday(mm) -> void:
	print("--- ② 周日一整晚(晋级者 / 观众 / 第 1 轮就输) ---")
	var fd = mm._wk().fd
	var seat: int = P2.finals_seat_ts(MON)
	var cup: int = SUN + int(P2.FINALS_START_HOUR_UTC) * H
	_ok("★分母: 分组 = 周日 %d:00 / 冠军杯赛 = 周日 %d:00(UTC, 常量)" % [int(P2.FINALS_SEAT_HOUR_UTC), int(P2.FINALS_START_HOUR_UTC)],
		seat == SUN + 18 * H and fx.seat() == seat and fx.cup_start() == cup and cup - seat >= 3600)
	var r1 := M.round_name(4, 1)
	var r2 := M.round_name(4, 2)
	var c1 := M.round_name(6, 1)
	## ★18:00 分组之前一个组都没有 ⇒ 冠军杯赛按 8 签估(之后按真实组数, 6 组 ⇒ 6 人 8 签)
	var t_mine1: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][0])
	var t_r2: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[1]["round_at"])
	var t_cup_mine: int = int(fx.timeline(6, cup, {})[0]["slots"]["1-3"][0])
	var t_cup_first: int = int(fx.timeline(6, cup, {})[0]["slots"]["1-1"][0])
	print("  (我那场小组赛 %s 开播 · 冠军杯赛第 1 轮第 1 场 %s / 我那场 %s)" % [_hm(t_mine1), _hm(t_cup_first), _hm(t_cup_mine)])
	## [标签, 时刻, 人, 主按钮大字, 副标, 点了去哪(watch/bracket), 卡状态带, 小组赛子卡, 冠军杯赛子卡, 我这一路(空 = 观众), 模式卡倒计时, 模式卡读数]
	var rows: Array = [
		## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 卡状态签「未开始 / 进行中 / 已结束」(原「开赛倒计时 / 开播中」: 18:05 一场没播也写开播中);
		##   子卡只写状态(倒计时在模式卡上沿与全局小条数, 原来同一屏三处三种写法); 副标一件事(不再「· 还剩 2:00」「· 点击观看」);
		##   分组前没晋级的人主按钮「查看赛况」(那时没有能看的, 原「观看开播」)。
		["17:40 晋级者", SUN + 17 * H + 40 * MI, "in", "我的比赛", "小组赛 %s 开赛" % _hm(seat), "bracket",
			"未开始", "未开始", "CUPCD",
			"group:%s=pending,group:%s=pending,cup:%s=pending,cup:%s=pending,cup:%s=pending" % [r1, r2, M.round_name(8, 1), M.round_name(8, 2), M.round_name(8, 3)],
			"距小组赛开始 20 分 00 秒", "已晋级"],
		["17:40 观众", SUN + 17 * H + 40 * MI, "plain", "查看赛况", "小组赛 %s 开赛" % _hm(seat), "bracket",
			"未开始", "未开始", "CUPCD", "", "距小组赛开始 20 分 00 秒", "未晋级"],
		["18:01 备战", SUN + 18 * H + 1 * MI, "in", "我的比赛", "%s备战中" % r1, "bracket",
			"进行中", "进行中", "CUPCD", "group:%s=now" % r1, "MODECD", "已晋级"],
		["18:05 备战结束等开播", SUN + 18 * H + 5 * MI, "in", "我的比赛", "%s %s 开播" % [r1, _hm(SUN + 18 * H + 480)], "bracket",
			"进行中", "进行中", "CUPCD", "group:%s=now" % r1, "MODECD", "已晋级"],
		## ★小组赛同一轮所有场同时开播(用户 10-31 纠正): 18:08 翻面, 我那场与同组另一场一起开播
		["18:10 我的比赛开播中(本轮同时开播)", SUN + 18 * H + 10 * MI, "in", "我的比赛", "%s开播中" % r1, "watch",
			"进行中", "进行中", "CUPCD", "group:%s=now" % r1, "MODECD", "已晋级"],
		["18:13 我那场已揭晓 · 决赛备战中", SUN + 18 * H + 13 * MI, "in", "我的比赛", "%s备战中" % r2, "bracket",
			"进行中", "进行中", "CUPCD", "group:%s=won,group:%s=now" % [r1, r2], "MODECD", "已晋级"],
		["18:10 观众(6 组 × 2 场同时开播中)", SUN + 18 * H + 10 * MI, "plain", "观看开播", "12 场开播中", "watch",
			"进行中", "进行中", "CUPCD", "", "MODECD", "未晋级"],
		["18:40 我拿下小组(各组已决出, 等冠军杯赛)", SUN + 18 * H + 40 * MI, "in", "我的比赛", "冠军杯赛 %s 开赛" % _hm(cup), "bracket",
			"未开始", "已结束", "CUPCD",
			"group:%s=won,group:%s=won,cup:%s=pending" % [r1, r2, c1], "MODECD", "已晋级冠军杯赛"],
		["18:40 第 1 轮就输了(等冠军杯赛)", SUN + 18 * H + 40 * MI, "out", "我的比赛", "冠军杯赛 %s 开赛" % _hm(cup), "bracket",
			"未开始", "已结束", "CUPCD",
			"group:%s=lost,group:%s=skip,cup:%s=skip" % [r1, r2, c1], "MODECD", "已止步"],
		["冠军杯赛 +9 分 开播中(我那场还没到)", cup + 9 * MI, "in", "我的比赛", "%s %s 开播" % [c1, _hm(t_cup_mine)], "bracket",
			"进行中", "已结束", "进行中", "group:%s=won,group:%s=won,cup:%s=now" % [r1, r2, c1], "冠军杯赛进行中", "已晋级冠军杯赛"],
		["冠军杯赛 +9 分 观众", cup + 9 * MI, "plain", "观看开播", "%s开播中" % M.stage_line(fx.cup(cup + 9 * MI), 1), "watch",
			"进行中", "已结束", "进行中", "", "冠军杯赛进行中", "未晋级"],
		["22:00 半决赛止步(冠军杯赛已决出)", SUN + 22 * H, "in", "我的比赛", "冠军杯赛已结束", "bracket",
			"已结束", "已结束", "已结束", "group:%s=won,group:%s=won,cup:%s=won,cup:%s=lost,cup:%s=skip" % [r1, r2, c1, M.round_name(6, 2), M.round_name(6, 3)],
			"冠军杯赛已结束", "已止步"],
		["22:00 观众", SUN + 22 * H, "plain", "查看结果", "冠军杯赛已结束", "bracket",
			"已结束", "已结束", "已结束", "", "冠军杯赛已结束", "未晋级"],
		["周日上午 12:00 晋级者", SUN + 12 * H, "in", "我的比赛", "小组赛 %s 开赛" % _hm(seat), "bracket",
			"未开始", "未开始", "CUPCD", "", "", ""],
	]
	for r in rows:
		_state("in" if str(r[2]) != "plain" else "plain")
		var ts := int(r[1])
		_feed(mm, ts, str(r[2]))
		_rebuild(mm, ts)
		var tag := "② [%s]" % str(r[0])
		var hero: Node = mm._hero_btn
		_ok("%s 主按钮是决赛日那一颗(不是「开始战斗」)" % tag, hero != null and str(hero.name) == FD.N_HERO
			and _sig(hero).find("text=开始战斗") < 0, str(hero.name) if hero != null else "无")
		_ok("%s 大字「%s」" % [tag, r[3]], _txt(hero, FD.N_TITLE) == str(r[3]), _txt(hero, FD.N_TITLE))
		_ok("%s 副标「%s」" % [tag, r[4]], _txt(hero, FD.N_SUB) == str(r[4]), _txt(hero, FD.N_SUB))
		_ok("%s 主按钮接 `on_hero`、能点(不灰不挂锁)" % tag, _hero_go(mm) == "on_hero" and _sig(hero).find(str(mm.LOCK_ICON_NAME)) < 0
			and _sig(hero).find("HeroFace") >= 0, _hero_go(mm))
		fd.last_go = ""
		fd.on_hero()
		_ok("%s ★点主按钮 ⇒ %s" % [tag, "直达正在播的那一场(G17)" if str(r[5]) == "watch" else "对阵图"], fd.last_go == str(r[5]), fd.last_go)
		var c = _card(mm)
		_ok("%s ★决赛日卡在场、整张点了直达对阵图(P19)" % tag, c != null and _dest(c.find_child(CARD.N_TAP, true, false) as BaseButton) == "_open_bracket_map")
		if c == null:
			continue
		_ok("%s 卡状态带「%s」(三态)" % [tag, r[6]], _txt(c, CARD.N_STATE) == str(r[6]), _txt(c, CARD.N_STATE))
		_ok("%s 小组赛子卡「%s」· %s" % [tag, r[7], _hm(seat)], _txt(c.find_child(CARD.N_SUB_G, true, false), "Line") == str(r[7])
			and _txt(c.find_child(CARD.N_SUB_G, true, false), "Time") == _hm(seat), _txt(c.find_child(CARD.N_SUB_G, true, false), "Line"))
		if str(r[8]) == "CUPCD":
			r[8] = "未开始"
		if str(r[10]) == "MODECD":
			r[10] = "距冠军杯赛开始 %s" % M.clock_text(cup - ts)
		_ok("%s 冠军杯赛子卡「%s」· %s" % [tag, r[8], _hm(cup)], _txt(c.find_child(CARD.N_SUB_C, true, false), "Line") == str(r[8])
			and _txt(c.find_child(CARD.N_SUB_C, true, false), "Time") == _hm(cup), _txt(c.find_child(CARD.N_SUB_C, true, false), "Line"))
		var want_cells := str(r[9])
		## ★卡上不预告下一场比赛(用户 10-31「为什么在这儿提示新的比赛」: 下一站归每周赛程条)
		var nx := _next_event_words(c)
		_ok("%s ★卡上一个字都不预告下一场比赛(下周 / 周二 / 周六 / 闯关赛 / 积分赛 / 大轮)" % tag, nx.is_empty(), str(nx))
		## ★周日是服务器算好再播 ⇒ 叫「开播」不叫「直播」(对阵图 / 观战页同一个叫法)
		var lv := _words_in(c, ["直播"]) + _words_in(hero, ["直播"])
		_ok("%s 卡与主按钮不写「直播」(周日叫「开播」)" % tag, lv.is_empty(), str(lv))
		if str(r[2]) == "plain":
			var sl: Array = CARD.spectator_lines(ts, (fd.feed_override["groups"] as Array), (fd.feed_override["cup"] as Dictionary))
			_ok("%s 观众没有「我这一路」, 那一格只写今天的事「%s」/「%s」" % [tag, sl[0], sl[1]], (c.cells as Array).is_empty()
				and _txt(c, "FcSpect1") == str(sl[0]) and _txt(c, "FcSpect2") == str(sl[1]), "%s / %s" % [_txt(c, "FcSpect1"), _txt(c, "FcSpect2")])
		elif want_cells != "":
			_ok("%s ★我这一路「%s…」" % [tag, want_cells.left(40)], _cells(mm).begins_with(want_cells), _cells(mm))
		if str(r[10]) == "":
			continue
		_ok("%s ★模式卡倒计时 / 当前阶段「%s」(17:30 收盘后不丢, P18)" % [tag, r[10]], _txt(mm._mode_box, "ModeCountdown") == str(r[10]),
			_txt(mm._mode_box, "ModeCountdown"))
		_ok("%s 模式卡读数「%s」" % [tag, r[11]], _txt(mm._mode_box, "ModeRule") == str(r[11]), _txt(mm._mode_box, "ModeRule"))
		_ok("%s 赛程页决赛日那张卡的时间 == 模式卡倒计时" % tag,
			str(mm.week_card_info(P2.PHASE_FINALS, ts)["time"]) == str(r[10]), str(mm.week_card_info(P2.PHASE_FINALS, ts)["time"]))
	fd.feed_override = {}
	## 周日上午没晋级的人还在打闯关赛 ⇒ 主按钮照旧是「开始战斗」
	_state("plain")
	GameState.promoted = true
	GameState.gauntlet_wins = 2
	GameState.gauntlet_losses = 1
	_rebuild(mm, SUN + 12 * H)
	_ok("② [周日上午还在打闯关赛 2-1] 主按钮照旧「开始战斗」、没有决赛日卡", _sig(mm._hero_btn).find("text=开始战斗") >= 0
		and mm.page_box.find_child(FD.N_HERO, true, false) == null and _card(mm) == null)
	_state("in")
	_rebuild(mm, SUN + 18 * H + 5 * MI)
	var tap := mm._mode_box.find_child("ModeTap", true, false) as BaseButton
	_ok("② 模式卡本身仍接 `_on_mode_tap`(赛程页 / 规则; 对阵图的门在决赛日卡与主按钮上)", tap != null and _dest(tap) == "_on_mode_tap")
	_ok("② ★最大位置不再是锁住的按钮(P17): 主按钮没挂锁、没灰", mm._hero_locked == false and _sig(mm._hero_btn).find(str(mm.LOCK_ICON_NAME)) < 0)


# ───────────────────────────── ③ 不剧透 ─────────────────────────────

func _t_nospoil(mm) -> void:
	print("--- ③ ★不剧透: 开播中那一场的胜负不算数 ---")
	var fd = mm._wk().fd
	var t := SUN + 18 * H + 10 * MI           # 我那场(1-1)开播中(18:08 本轮同时开播): 服务端 done 里已经有结果
	for who in ["in", "out"]:
		_state("in")
		_feed(mm, t, who)
		_rebuild(mm, t)
		var g: Dictionary = fd.feed_override["group"]
		_ok("③ [%s] ★分母: 服务端回包里我那场(1-1)的结果已经在 done 里" % who, (g.get("done", {}) as Dictionary).has("1-1"))
		_ok("③ [%s] ★格子是「进行中」不是 ✓ / ✗、主按钮没写止步" % who, _cells(mm).begins_with("group:%s=now" % M.round_name(4, 1))
			and _txt(mm._hero_btn, FD.N_SUB).find("止步") < 0, "%s / %s" % [_cells(mm), _txt(mm._hero_btn, FD.N_SUB)])
		_ok("③ [%s] 模式卡读数还是「已晋级」" % who, _txt(mm._mode_box, "ModeRule") == "已晋级", _txt(mm._mode_box, "ModeRule"))
	## 播完(揭晓)⇒ 输的那个当场看见
	var t2: int = int(fx.timeline(4, SUN + 18 * H, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][1]) + 5
	_feed(mm, t2, "out")
	_rebuild(mm, t2)
	_ok("③ [out] 播完那一刻 ⇒ 格子翻成 ✗、模式卡「已止步」(尺子量得出差别)", _cells(mm).begins_with("group:%s=lost" % M.round_name(4, 1))
		and _txt(mm._mode_box, "ModeRule") == "已止步", _cells(mm))
	fd.feed_override = {}


# ───────────────────────────── ④ 每秒一拍 ─────────────────────────────

func _toast_has(m, msg: String) -> bool:
	for c in m.get_children():
		if c is Label and str((c as Label).text) == msg:
			return true
	return false


func _tick_to(mm, ts: int, who: String) -> void:
	_feed(mm, ts, who)
	mm.clock_override_ts = ts
	mm._wk().fd.tick(ts)


func _t_tick(mm) -> void:
	print("--- ④ 每秒一拍: 跨点换字 / 闪 / 飘一句 / 翻牌 ---")
	var fd = mm._wk().fd
	## a) 17:59:58 建好 → 18:00:01 那一拍(晋级者)
	_state("in")
	_feed(mm, SUN + 18 * H - 2, "in")
	_rebuild(mm, SUN + 18 * H - 2)
	var f0: int = int(fd.flashes)
	var a0: int = (fd.announced as Array).size()
	_tick_to(mm, SUN + 18 * H + 1, "in")
	var sub := mm._hero_btn.find_child(FD.N_SUB, true, false) as Label
	var want_sub := "%s备战中" % M.round_name(4, 1)
	_ok("④a 跨 18:00 ⇒ 副标换成「%s」" % want_sub, sub != null and sub.text == want_sub, sub.text if sub else "-")
	_ok("④a ★跨 18:00 ⇒ 副标闪一下(当场冲亮)", int(fd.flashes) == f0 + 1 and sub != null and sub.modulate.r >= 1.5,
		"闪 %d 次 · 亮度 %.2f" % [int(fd.flashes) - f0, sub.modulate.r if sub else 0.0])
	var want_a := "小组赛已开赛"
	_ok("④a ★跨 18:00 ⇒ 飘「%s」" % want_a, (fd.announced as Array).size() == a0 + 1 and _toast_has(mm, want_a), str(fd.announced))
	_ok("④a 卡的状态带同一拍换成「进行中」", _txt(_card(mm), CARD.N_STATE) == "进行中", _txt(_card(mm), CARD.N_STATE))
	## b) 只走倒计时: 不闪不飘, 但卡上的秒在走
	_feed(mm, SUN + 17 * H + 40 * MI, "in")
	_rebuild(mm, SUN + 17 * H + 40 * MI)
	f0 = int(fd.flashes)
	a0 = (fd.announced as Array).size()
	var l0 := _txt(_card(mm).find_child(CARD.N_SUB_G, true, false), "Line")
	_tick_to(mm, SUN + 17 * H + 41 * MI + 7, "in")
	sub = mm._hero_btn.find_child(FD.N_SUB, true, false) as Label
	_ok("④b 只走倒计时 ⇒ 主按钮副标不变(倒计时只在卡上数, 一屏一个)", sub != null and sub.text == "小组赛 %s 开赛" % _hm(SUN + 18 * H), sub.text if sub else "-")
	_ok("④b ★只走倒计时 ⇒ 不闪、不飘(闪只给阶段切换)", int(fd.flashes) == f0 and (fd.announced as Array).size() == a0)
	## 子卡只写状态(「未开始」), 这一屏数秒的是模式卡上沿(与全局小条同一种写法)
	_ok("④b ★子卡写状态「未开始」、模式卡上沿的倒计时每秒在走(20 分 00 秒 → 18 分 53 秒)", l0 == "未开始"
		and fd.band_text(SUN + 17 * H + 40 * MI) == "距小组赛开始 20 分 00 秒" and fd.band_text(SUN + 17 * H + 41 * MI + 7) == "距小组赛开始 18 分 53 秒",
		"%s / %s" % [l0, fd.band_text(SUN + 17 * H + 41 * MI + 7)])
	## c) 观众也飘(原来没晋级的人直接 return)
	_state("plain")
	_feed(mm, SUN + 18 * H - 2, "plain")
	_rebuild(mm, SUN + 18 * H - 2)
	a0 = (fd.announced as Array).size()
	_tick_to(mm, SUN + 18 * H + 1, "plain")
	var want_c := "小组赛已开赛"
	_ok("④c ★观众跨 18:00 也飘「%s」(原来没晋级的人收不到)" % want_c, (fd.announced as Array).size() == a0 + 1 and _toast_has(mm, want_c), str(fd.announced))
	## d) 冠军杯赛开赛前 1 秒(已晋级冠军杯赛)→ 开赛后 1 秒(FINALS_START_HOUR_UTC)
	var cup_at: int = SUN + int(P2.FINALS_START_HOUR_UTC) * H
	_state("in")
	_feed(mm, cup_at - 1, "in")
	_rebuild(mm, cup_at - 1)
	f0 = int(fd.flashes)
	_tick_to(mm, cup_at + 1, "in")
	sub = mm._hero_btn.find_child(FD.N_SUB, true, false) as Label
	var want_d := "冠军杯赛已开赛"
	_ok("④d 跨冠军杯赛开赛 ⇒「%s备战中」, 闪一下, 飘「%s」" % [M.round_name(6, 1), want_d], sub != null
		and sub.text == "%s备战中" % M.round_name(6, 1) and int(fd.flashes) == f0 + 1 and _toast_has(mm, want_d), sub.text if sub else "-")
	## e) 我那场揭晓那一拍: 格子翻牌(横向压扁再弹回), 主按钮闪
	var t_end: int = int(fx.timeline(4, SUN + 18 * H, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][1])
	_feed(mm, t_end - 10, "in")
	_rebuild(mm, t_end - 10)
	var c = _card(mm)
	var fl0: int = int(c.flips)
	f0 = int(fd.flashes)
	_tick_to(mm, t_end + 1, "in")
	var cell0 := c.find_child("FcCell0", true, false) as Control
	var min_sx := 1.0
	for _i in range(30):
		await get_tree().process_frame
		if cell0 != null:
			min_sx = minf(min_sx, cell0.scale.x)
	## 这一拍变了两格: 第 1 格(进行中 → ✓)与第 2 格(未到 → 轮到我), 两格都翻
	_ok("④e ★揭晓那一拍 ⇒ 第 1 格翻牌(真压扁过)且翻成 ✓、主按钮闪", int(c.flips) == fl0 + 2 and cell0 != null and min_sx < 0.6
		and _cells(mm).begins_with("group:%s=won" % M.round_name(4, 1)) and int(fd.flashes) == f0 + 1,
		"翻 %d · 最扁 %.2f · %s" % [int(c.flips) - fl0, min_sx, _cells(mm)])
	## f) 17:29:59 没资格的人(还是闯关赛 ⇒「开始战斗」)→ 17:30:01 当场换成「观看开播」
	_state("plain")
	_feed(mm, SUN + 17 * H + 30 * MI - 1, "plain")
	_rebuild(mm, SUN + 17 * H + 30 * MI - 1)
	var was := _sig(mm._hero_btn).find("text=开始战斗") >= 0
	_tick_to(mm, SUN + 17 * H + 30 * MI + 1, "plain")
	_ok("④f ★17:30 收盘那一拍 ⇒ 主按钮当场从「开始战斗」换成「查看赛况」(分组前没有能看的)+ 决赛日卡", was and mm._hero_btn != null and is_instance_valid(mm._hero_btn)
		and _txt(mm._hero_btn, FD.N_TITLE) == "查看赛况" and _card(mm) != null, _txt(mm._hero_btn, FD.N_TITLE))
	## g) 周日 23:59:59 → 周一 00:00:01 换回「开始战斗」(周一休赛, 锁着)
	_rebuild(mm, SUN + 86400 - 1)
	_tick_to(mm, SUN + 86400 + 1, "plain")
	_ok("④g 周一 00:00 那一拍 ⇒ 换回「开始战斗」、卡收走", mm._hero_btn != null and _sig(mm._hero_btn).find("text=开始战斗") >= 0
		and mm.page_box.find_child(FD.N_HERO, true, false) == null and _card(mm) == null)
	fd.feed_override = {}


# ───────────────────────────── ⑤ 动 / 字 ─────────────────────────────

func _t_motion(mm) -> void:
	print("--- ⑤ 就绪光 / 卡在动 / 字装得下 ---")
	_state("in")
	var ts := SUN + 18 * H + 10 * MI
	_feed(mm, ts, "in")
	_rebuild(mm, ts)
	var hero: Control = mm._hero_btn
	var glow: Node = null
	for c in hero.get_children():
		if c is MenuCtaGlow:
			glow = c
	_ok("⑤ 主按钮挂着呼吸光晕(与「开始战斗」同一个 MenuCtaGlow)", glow != null)
	if glow != null:
		var a0: float = (glow as CanvasItem).modulate.a
		glow.step(0.45)
		_ok("⑤ ★光晕真在呼吸(推 0.45 秒透明度变了)", absf((glow as CanvasItem).modulate.a - a0) > 0.1, "%.2f → %.2f" % [a0, (glow as CanvasItem).modulate.a])
	var sh := hero.get_node_or_null("Sheen") as Control
	_ok("⑤ 面上挂着选龟页出战键那道扫光(TsMotion.sheen), 框住亮黄面", sh != null and sh.clip_contents
		and sh.position == mm.HERO_FACE_INSET and sh.get_child_count() == 1)
	## 卡在动: 推 _process(开播点 / 开播子卡金边 / 我这一格 / 奖杯)
	var c = _card(mm)
	var dot := c._state_dot as CanvasItem
	var edge := (c._subs["g"] as Dictionary)["edge"] as CanvasItem
	var me_cell: CanvasItem = (c._cell_nodes[0] as Dictionary)["edge"]
	var tro := c.find_child("FcTrophy", true, false) as CanvasItem
	var s0 := [dot.modulate.a, edge.modulate.r, me_cell.modulate.r, tro.self_modulate.r if tro else 0.0]
	var mx := [0.0, 0.0, 0.0, 0.0]
	for i in range(40):
		c._process(0.1)
		mx[0] = maxf(mx[0], absf(dot.modulate.a - float(s0[0])))
		mx[1] = maxf(mx[1], absf(edge.modulate.r - float(s0[1])))
		mx[2] = maxf(mx[2], absf(me_cell.modulate.r - float(s0[2])))
		mx[3] = maxf(mx[3], absf((tro.self_modulate.r if tro else 0.0) - float(s0[3])))
	_ok("⑤ ★开播点一闪一闪 / 开播子卡金边呼吸 / 我这一格呼吸 / 奖杯隔几秒亮一下(推 4 秒各自变过)",
		mx[0] > 0.2 and mx[1] > 0.15 and mx[2] > 0.15 and mx[3] > 0.3, str(mx))
	## 字装得下: 主按钮最长的副标 / 卡上每个 Label 的字宽 ≤ 框宽
	var font: Font = mm._bold_font()
	var face := Rect2(mm.HERO_FACE_INSET, mm.HERO_SIZE - mm.HERO_FACE_INSET * 2.0)
	var widest := 0.0
	var wtxt := ""
	for txt in ["小组赛 23:59 开赛 · 还有 23 小时 59 分", "已止步 · 冠军杯赛 23:59 开赛", "冠军杯赛 23:59 开赛 · 还有 1 小时 59 分",
			"%s开播中 · 点击观看" % M.round_name(6, 1), "已止步 · 下一场 23:59 开播", "%s · 半决赛开播中" % ChampionData.group_name(5), "12 场开播中 · 点击观看",
			"%s冠军 %s" % [P2.STAGE_CUP, "WWWWWWWWWWWW"], "%s备战中 · 还剩 2:59" % M.round_name(6, 1), "已夺得%s冠军" % P2.STAGE_CUP]:
		var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FD.SUB_FONT).x
		if w > widest:
			widest = w
			wtxt = txt
	_ok("⑤ 最长的副标装得下(墨宽 + 描边 ≤ 面宽)", widest + 2.0 * 7.0 <= face.size.x, "%.0f / %.0f「%s」" % [widest, face.size.x, wtxt])
	for t in ["我的比赛", "观看开播", "查看结果"]:
		_ok("⑤ 大字「%s」装得下" % t, font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FD.TITLE_FONT).x + 24.0 <= face.size.x)
	var over: Array = []
	var nlab := 0
	for l in c.find_children("*", "Label", true, false):
		var lb := l as Label
		if lb.text == "" or not lb.is_visible_in_tree() or lb.clip_text:
			continue
		nlab += 1
		var w2: float = font.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.get_theme_font_size("font_size")).x
		if w2 > lb.size.x + 1.0:
			over.append("%s「%s」%.0f>%.0f" % [lb.name, lb.text, w2, lb.size.x])
	_ok("⑤ ★卡上每一行字都装在自己的框里(分母 %d 行)" % nlab, nlab >= 10 and over.is_empty(), str(over))
	_flash_check(mm)


func _flash_check(mm) -> void:
	var fd = mm._wk().fd
	var glow: CanvasItem = null
	for c in mm._hero_btn.get_children():
		if c is MenuCtaGlow:
			glow = c
	fd._flash(false)
	_ok("⑤ ★亮起那一下: 光晕当场冲亮(与选龟页出战键刚能点时同一组数)", glow != null and glow.self_modulate.r >= 1.9,
		_cs(glow.self_modulate) if glow != null else "-")


# ───────────────────────────── ⑥ 上周冠军 ─────────────────────────────

func _t_champ(mm) -> void:
	print("--- ⑥ 上周冠军挂门面 ---")
	_state("in")
	var ts := SUN + 17 * H + 40 * MI
	F.prev_champ = {}
	_feed(mm, ts, "in")
	_rebuild(mm, ts)
	var c = _card(mm)
	_ok("⑥ 拿不到上周冠军 ⇒ 那一行写今天的看点(冠军拿什么), 不空着", _txt(c, "FcChampHead").find("头衔") >= 0
		and c.find_child("FcChampName", true, false) == null, _txt(c, "FcChampHead"))
	F.prev_champ = {"name": "风起", "tag": "#P0101", "avatar": "angel", "week": MON - 7 * 86400}
	_rebuild(mm, ts)
	c = _card(mm)
	var por := c.find_child("Portrait", true, false)
	_ok("⑥ ★上周冠军: 「上周冠军」+ 名字 + 真头像(avatars/angel.png)", _txt(c, "FcChampHead") == "上周冠军" and _txt(c, "FcChampName") == "风起"
		and por != null and str(por.get_meta("Portrait", "")) == "angel" and por.find_children("*", "TextureRect", true, false).size() > 0,
		"%s / %s" % [_txt(c, "FcChampHead"), _txt(c, "FcChampName")])
	_ok("⑥ 冠军杯赛还没决出 ⇒ 没有「冠军墙」入口", c.find_child(CARD.N_WALL, true, false) == null)
	## 冠军杯赛决出(已揭晓)⇒ 换成这一届的冠军杯赛冠军 + 「冠军墙」入口(块 D 的 ChampionWall)
	var t2 := SUN + 22 * H
	_feed(mm, t2, "in")
	F.avatars[MON] = {"#T000": "basic"}
	_rebuild(mm, t2)
	c = _card(mm)
	var fd = mm._wk().fd
	var wb := c.find_child(CARD.N_WALL, true, false) as BaseButton
	_ok("⑥ ★冠军杯赛决出 ⇒ 这一行换成「冠军杯赛冠军 小辉同学」+ 他的头像", _txt(c, "FcChampHead") == "本届冠军" and _txt(c, "FcChampName") == "小辉同学"
		and str(c.find_child("Portrait", true, false).get_meta("Portrait", "")) == "basic", "%s / %s" % [_txt(c, "FcChampHead"), _txt(c, "FcChampName")])
	var w0: int = int(fd.walls)
	if wb != null:
		wb.pressed.emit()
	_ok("⑥ ★「冠军墙」入口在场、点了接到 ChampionWall(块 D)、触摸线 81、叠在整张卡的点击区上面", wb != null and int(fd.walls) == w0 + 1
		and wb.size.y >= 81.0 and wb.get_index() >= 0 and wb.is_visible_in_tree()
		and (c.find_child(CARD.N_TAP, true, false) as Control).get_index() < c.find_child(CARD.N_CHAMP, true, false).get_index())
	F.avatars.erase(MON)
	mm._wk().fd.feed_override = {}
	F.prev_champ = {}


# ───────────────────────────── ⑦ 版面(两比例) ─────────────────────────────

func _t_layout(mm) -> void:
	print("--- ⑦ 版面: 卡不压任何入口(两比例) ---")
	for vp in [Vector2i(1560, 720), Vector2i(1280, 960)]:
		get_tree().root.size = vp
		await get_tree().process_frame
		_state("in")
		var ts := SUN + 19 * H
		_feed(mm, ts, "in")
		mm._mq().quiet = true                  # 不播滑入(量落定后的位置)
		_rebuild(mm, ts)
		mm._mq().quiet = false
		mm._center_content()
		await get_tree().process_frame
		var c := _card(mm) as Control
		var cr := c.get_global_rect()
		var hr := (mm._hero_btn as Control).get_global_rect()
		var mr := (mm._mode_box as Control).get_global_rect()
		var tr := Rect2()
		for ch in mm.page_box.get_children():
			if ch is Control and (ch as Control).position == mm.TRAINER_POS:
				tr = (ch as Control).get_global_rect()
		var root_r := Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
		var cur := mm.content_root.get_node_or_null(str(mm.CURRENCY_BAR_NAME)) as Control
		var cur_r := cur.get_global_rect() if cur != null else Rect2()
		var content_r := Rect2(mm.content_root.global_position, Vector2(mm.W, mm.H))
		var tag := "⑦ [%dx%d]" % [vp.x, vp.y]
		_ok("%s ★分母: 卡 / 主按钮 / 训龟大师 / 模式卡 / 货币条都量到了" % tag, cr.size.x > 0 and hr.size.x > 0 and tr.size.x > 0 and mr.size.x > 0 and cur_r.size.x > 0)
		_ok("%s ★卡整张在屏内、在 1280×720 内容框内" % tag, root_r.encloses(cr) and content_r.encloses(cr), "%s / %s" % [str(cr), str(content_r)])
		_ok("%s ★卡不压主按钮 / 训龟大师 / 模式卡 / 货币条" % tag, not cr.intersects(hr) and not cr.intersects(tr) and not cr.intersects(mr)
			and not cr.intersects(cur_r), "卡 %s 训龟大师 %s" % [str(cr), str(tr)])
		_ok("%s ★卡顶不进绑定提示条的点击区(底沿 %.0f)" % [tag, content_r.position.y + 195.0], cr.position.y >= content_r.position.y + 195.0, str(cr.position.y))
		_ok("%s 卡与主按钮右沿同轴(读成一组)" % tag, absf(cr.end.x - hr.end.x) < 1.0, "%.0f / %.0f" % [cr.end.x, hr.end.x])
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	mm._wk().fd.feed_override = {}


# ───────────────────────────── 一屏一次钟 ─────────────────────────────

func _t_clock_reads() -> void:
	print("--- ⑦ 周日这一屏只读一次钟 ---")
	_state("in")
	var m = MENU.new()
	m.clock_override_ts = SUN + 18 * H + 5 * MI
	add_child(m)
	for _i in range(3):
		await get_tree().process_frame
	_ok("⑦ ★分母: 周日这一屏建起来了、主按钮是决赛日那一颗", m.page_box != null and m.page_box.find_child(FD.N_HERO, true, false) != null)
	_ok("⑦ ★周日这一屏只问了一次「现在几点」(verify_quota_clock ④ 同一条)", int(m._clock_reads) == 1, "_clock_reads=%d" % int(m._clock_reads))
	m.queue_free()
	await get_tree().process_frame


# ───────────────────────────── 改动前那份源码 ─────────────────────────────

func _old_script():
	var out: Array = []
	var rc := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "cat-file", "-e", BASE + "^{commit}"], out, true)
	if rc != 0:
		return null
	var src := _git_show(MENU_FILE, BASE)
	if src.length() < 1000:
		return null
	var s := GDScript.new()
	s.source_code = src
	if s.reload() != OK:
		return null
	return s


## ★读原始字节再按 UTF-8 解(OS.execute 在 Windows 上按本地代码页解 git 的输出, 中文全坏) —— 同 verify_gauntlet_online_queue。
func _git_show(f: String, sha: String) -> String:
	var d := OS.execute_with_pipe("git", PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "show",
		"%s:%s" % [sha, f]]), true)
	var fa = d.get("stdio", null)
	if not (fa is FileAccess):
		return ""
	var buf := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		var chunk: PackedByteArray = (fa as FileAccess).get_buffer(65536)
		if chunk.is_empty():
			if not OS.is_process_running(int(d.get("pid", -1))):
				break
			continue
		buf.append_array(chunk)
	return buf.get_string_from_utf8()
