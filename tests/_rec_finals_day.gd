extends Node
## _rec_finals_day.gd — 周日「入口与叫人」成品视频(探针, 不进门禁; 方案书 20261031c 块 M)。
## 走真主菜单(MainMenu.tscn) + 全局层(autoload FinalsDay), 数据 = tests/_finals_day_fixture.gd(照服务端一场接一场的排法), 假时钟一秒一拍。
## Movie Maker 下 游戏秒 = 视频秒(60 帧 = 1 秒)。时间线(每段 3~6 秒):
##   ① 17:40 晋级者主菜单: 决赛日卡 + 两张子卡倒计时 + 我这一路
##   ② 18:07:27 → 「你的半决赛 30 秒后开播」横幅从顶上滑下(小组赛同一轮同时开播: 数到服务端给的翻面时刻)→ 点「观看」
##      → 跳到 18:07:56, 数 4、3、2、1 → 18:08 翻面 = 开播那一拍自动进观战(硬切)
##   ③ 18:07:57 观众视角 → 18:08 小组翻面: 全局小条「开播中」+ 跑马灯「小组赛 半决赛开播 · 6 组同时进行」+ 主按钮「观看开播」
##   ④ 19:00 第 1 轮就输了的人: 我这一路 ✗ / 已止步
##   ⑤ 20:08:56 观众: 冠军杯赛第 1 场开播(冠军杯赛一场接一场)→「观看开播 / 冠军杯赛 · 第 1 轮开播中」
##   ⑥ 21:30 收盘后再次打开: 补看三拍全程(冠军 → 名次 → 我的比赛)
##   ⑦ 22:00 收盘后主菜单卡: 冠军杯赛冠军 + 冠军墙入口
## 跑法(静音、右屏、一次一个):
##   bash godot-quiet.sh --position 2000,80 --write-movie C:/tmp/sunday_redo/M/video/m.avi --fixed-fps 60 res://tests/_rec_finals_day.tscn

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const RC := preload("res://scripts/ui/finals_day_recap.gd")
const MON := 1789344000
const SUN := MON + 6 * 86400

var fx
var mm: Node = null
var fd
var ts := 0
var t_rec := 0.0


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	StudioIntro.played = true
	fx = FX.new(MON)
	fd = get_node("/root/FinalsDay")
	F.prev_champ = {"name": "风起", "tag": "#P0101", "avatar": "angel", "week": MON - 7 * 86400}
	F.avatars[MON] = {"#T000": "basic", "#T201": "bamboo", "#T102": "stone", "#T222": "angel"}
	GameState.account_id = "acc-2-2"
	await _seg("① 17:40 晋级者主菜单", "in", _hm(17, 40, 0), 5)
	await _seg("② 18:07:27 30 秒开播横幅", "in", _hm(18, 7, 27), 4, false)
	var pp = fd.popup
	if pp != null and is_instance_valid(pp):
		pp.watch.modulate = Color(1.6, 1.5, 1.2)
		pp.watch.pressed.emit()
	print("[REC] %.1fs 点「观看」⇒ 开播后自动进入" % t_rec)
	await _run(1)
	## 跳到开播前 4 秒(横幅还在, 数 4、3、2、1), 开播那一拍自动进
	ts = _hm(18, 7, 56)
	_feed()
	await _run(5)
	print("[REC] %.1fs 开播 ⇒ 自动进观战(硬切)" % t_rec)
	await _seg("③ 18:07:57 观众视角 · 小组翻面: 小条开播中 + 跑马灯", "plain", _hm(18, 7, 57), 7)
	await _seg("④ 19:00 第 1 轮就输了", "out", _hm(19, 0, 0), 5)
	await _seg("⑤ 20:08:56 观众 · 冠军杯赛开播", "plain", _hm(20, 8, 56), 6)
	await _seg_recap()
	await _seg("⑦ 22:00 收盘后主菜单卡 + 冠军墙入口", "in", _hm(22, 0, 0), 5)
	print("[REC] %.1fs 结束" % t_rec)
	get_tree().quit(0)


func _hm(h: int, m: int, s: int) -> int:
	return SUN + h * 3600 + m * 60 + s


func _who(kind: String) -> void:
	GameState.test_mode = true
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.season_total_battles = 7
	GameState.season_level = 3
	GameState.season_id = 2
	GameState.meta_deepsea_coins = 42
	GameState.ranked_used = 7
	GameState.onboarded = true
	GameState.nickname = "吃货一枚"
	GameState.first_tips_seen = {"finals_day": true, "gauntlet_day": true, "start_battle": true, "first_week": true}
	var inn := kind != "plain"
	GameState.promoted = inn
	GameState.season_wins = int(P2.PROMOTE_WINS) if inn else 2
	GameState.gauntlet_wins = int(P2.GAUNTLET_WINS_IN) if inn else 0
	GameState.gauntlet_losses = 0
	fx.me_in = inn
	fx.group_wins[FX.MY_GROUP] = {"1-1": 0} if kind == "out" else {"1-1": 1, "2-0": 1}


func _feed() -> void:
	P2.now_override_ts = ts
	F.override = fx.feeds(ts)
	if mm != null and is_instance_valid(mm):
		mm.clock_override_ts = ts
		mm._wk().fd.feed_override = F.override
	fd.tick()


## 一段: (重新)打开主菜单, 钟走 n 秒。fresh = false ⇒ 同一个主菜单接着走(只拨钟)。
func _seg(label: String, kind: String, at: int, n: int, fresh: bool = true) -> void:
	print("[REC] %.1fs %s" % [t_rec, label])
	_who(kind)
	ts = at
	if fresh or mm == null or not is_instance_valid(mm):
		if mm != null and is_instance_valid(mm):
			fd.test_host = null
			mm.queue_free()
			await get_tree().process_frame
		P2.now_override_ts = ts
		F.override = fx.feeds(ts)
		mm = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
		mm.clock_override_ts = ts
		add_child(mm)
		await get_tree().process_frame
		fd.test_host = mm
		fd._facts_prev = null
		fd._had_data = false
		fd.popped = {}
		## 跳时刻 = 另一次打开游戏: 上一段没播完的跑马灯不带过来
		fd.marquee.queue.clear()
		fd.marquee.visible = false
		fd.marquee._busy = false
		fd.marquee.current = ""
	_feed()
	await _run(n)


func _seg_recap() -> void:
	print("[REC] %.1fs ⑥ 21:30 收盘后再次打开: 补看三拍" % t_rec)
	_who("in")
	ts = _hm(21, 30, 0)
	if mm != null and is_instance_valid(mm):
		fd.test_host = null
		mm.queue_free()
		await get_tree().process_frame
	P2.now_override_ts = ts
	F.override = fx.feeds(ts)
	mm = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	mm.clock_override_ts = ts
	add_child(mm)
	await get_tree().process_frame
	fd.test_host = mm
	_feed()
	var f: Dictionary = fx.feeds(ts)
	RC.show_for(mm, MON, f["groups"], f["cup"], ts)
	var rc = mm.get_node_or_null(RC.NODE_NAME)
	## 三拍自己往下走(4.4 + 5.0 秒), 第 3 拍演完再停 3 秒, 然后点「关闭」
	await _run(13)
	if rc != null and is_instance_valid(rc):
		rc.close()
	await _sec(0.5)


func _sec(s: float) -> void:
	for _i in range(int(s * 60.0)):
		await get_tree().process_frame
	t_rec += s


## 钟走 n 秒(一秒一拍; 全局层 / 主菜单自己的 1 秒 Timer 照常拍)。
func _run(n: int) -> void:
	for _k in range(n):
		await _sec(1.0)
		ts += 1
		_feed()
