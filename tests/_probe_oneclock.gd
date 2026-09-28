extends Node
## _probe_oneclock.gd — 最后四份时钟 override 的**兜底**到底读谁?
##
## 钉住全局缝 `phase2_config.now_override_ts`(主菜单已经在用), 然后逐处量
## 「它以为今天是哪一天」。四处**各自的 override 一律不写**(=0), 走兜底那条路:
##   · BracketMapScene._clock()            (_now_override = 0)
##   · TeamSelectScene 封盘闸               (lockout_now_override = 0)
##   · GameState.settle_ranked_close()      (不传 now_override)
##   · GameState.settle_gauntlet_close()    (不传 now_override)
##
## 修前预期: 四处兜底 = `int(Time.get_unix_time_from_system())` ⇒ **与钉住的那一天无关**,
##   两个相隔六天的注入值量出来**一模一样**(那正是「两条时钟必然丢事件」)。
## 修后预期: 四处跟着注入值走, 两个注入值给出**不同**答案。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_oneclock.tscn --quit-after 1500

const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const BRACKET := preload("res://scripts/scenes/BracketMapScene.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const TS_SCENE := preload("res://scenes/TeamSelect.tscn")
const TS := preload("res://scripts/scenes/TeamSelectScene.gd")

const NAMES := ["甲龟", "乙龟", "丙龟", "丁龟", "戊龟", "己龟", "庚龟", "辛龟"]
const KEYS := ["promoted", "ranked_used", "backfill_paid", "gauntlet_backfill_paid",
	"meta_deepsea_coins", "season_xp", "season_level", "season_wins",
	"week_anchor_ts", "season_start_ts", "season_id", "week_phase", "left_team",
	"gauntlet_wins", "gauntlet_losses", "titles"]

var _anchor := 0
var _bak := {}
## ★缓存场景树: C 段末尾那次 `_on_start()` 会真的 `change_scene_to_file`, 之后 `get_tree()` 是 null。
var _tree: SceneTree = null


func _d(ts: int) -> String:
	return "%s(周%d)" % [Time.get_datetime_string_from_unix_time(ts, true), P2C.iso_weekday_utc(ts)]


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	for k in KEYS:
		_bak[k] = GameState.get(k)

	var real_now := int(Time.get_unix_time_from_system())
	_anchor = P2C.week_anchor_utc(real_now)
	print("=== 四份时钟 override 的兜底读谁 ===")
	print("  真实系统钟   : %s" % _d(real_now))
	print("  本周锚点     : %s" % _d(_anchor))
	print("  积分赛收盘   : %s" % _d(P2C.ranked_close_ts(_anchor)))
	print("  闯关赛收盘   : %s" % _d(P2C.gauntlet_close_ts(_anchor)))
	print("")

	var pin_sun: int = _anchor + 6 * 86400 + 21 * 3600   # 本周周日 21:00 UTC
	var pin_mon: int = _anchor + 10 * 3600               # 本周周一 10:00 UTC
	await _measure("A 注周日 21:00", pin_sun)
	await _measure("B 注周一 10:00", pin_mon)
	await _ts_gate(pin_sun, pin_mon)

	P2C.now_override_ts = 0
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (还原: now_override_ts=%d)" % int(P2C.now_override_ts))
	if _tree != null:
		_tree.quit(0)


## 量 ①BracketMapScene._clock() ②settle_ranked_close() ③settle_gauntlet_close()
func _measure(tag: String, pin: int) -> void:
	P2C.now_override_ts = pin
	print("── %s  注入值=%s ──" % [tag, _d(pin)])
	print("     缝本身 now_utc()      = %s  相位=%s" % [
		_d(int(P2C.now_utc())), P2C.phase_at_utc(int(P2C.now_utc()))])

	## ① 桶地图: `set_data(..., now=0)` ⇒ `_now_override=0` ⇒ 走兜底
	var map = BRACKET.new()
	get_tree().root.add_child(map)
	await get_tree().process_frame
	map.set_data(
		{"size": 8, "round": 5, "me": 2, "names": NAMES, "done": {}},
		{"size": 4, "round": 1, "me": -1, "names": ["甲龟", "乙龟", "丙龟", "丁龟"], "done": {}},
		0)
	await get_tree().process_frame
	print("     ①桶地图 _clock()      = %s  默认视图=%s" % [_d(int(map._clock())), str(map._view)])
	map.queue_free()
	await get_tree().process_frame

	## ②③ 收盘补算: 摆干净局面, 走**不传参**的产品路径
	_setup_gs()
	var paid_r: int = int(GameState.settle_ranked_close())
	print("     ②settle_ranked_close()   补发=%d 场  promoted=%s" % [paid_r, str(GameState.promoted)])
	_setup_gs()
	GameState.gauntlet_wins = 4          # 4-0 ⇒ 该补 2 场
	GameState.gauntlet_losses = 0
	var paid_g: int = int(GameState.settle_gauntlet_close())
	print("     ③settle_gauntlet_close() 补发=%d 场" % paid_g)
	print("")


func _setup_gs() -> void:
	GameState.week_anchor_ts = _anchor
	GameState.season_start_ts = _anchor
	GameState.ranked_used = int(P2C.RANKED_QUOTA) - 5
	GameState.season_wins = int(P2C.PROMOTE_WINS_FLOOR)
	GameState.backfill_paid = 0
	GameState.gauntlet_backfill_paid = 0
	GameState.promoted = false
	GameState.meta_deepsea_coins = 1000


## ④ 选阵容屏的封盘闸 —— 只能从**行为**上量(那一行读的时刻没有访问器)。
##   顺序要紧: 不被拦那一次会真的 `change_scene_to_file` 把场景树掀掉 ⇒ 放最后, 且不 await。
func _ts_gate(pin_lockout_src: int, pin_free: int) -> void:
	var pin_lock: int = P2C.ranked_close_ts(_anchor) - int(P2C.CLOSE_LOCKOUT_SEC / 2)
	print("── C 选阵容屏封盘闸(lockout_now_override 不写) ──")
	print("     封盘窗内注入值 = %s  can_start_match_utc=%s" % [
		_d(pin_lock), str(P2C.can_start_match_utc(pin_lock))])
	print("     自由注入值     = %s  can_start_match_utc=%s" % [
		_d(pin_free), str(P2C.can_start_match_utc(pin_free))])

	var inst = TS_SCENE.instantiate()
	add_child(inst)
	var w := 0
	while w < 600 and not inst.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(10):
		await get_tree().process_frame

	var pool: Array = []
	for p in DataRegistry.all_pets:
		if p is Dictionary and p.has("id"):
			pool.append(str(p["id"]))
		if pool.size() >= int(TS.REQUIRED_PETS):
			break
	print("     ★分母: 填满阵容 %d/%d 只" % [pool.size(), int(TS.REQUIRED_PETS)])
	for i in range(int(TS.REQUIRED_PETS)):
		inst.team[i] = pool[i]

	## 第一次: 注封盘窗内 ⇒ 修后应当被拦(left_team 不写)
	P2C.now_override_ts = pin_lock
	GameState.left_team = [] as Array[String]
	inst._on_start()
	print("     ④注封盘窗内: left_team=%d 只  封盘toast=%s  ⇒ %s" % [
		GameState.left_team.size(),
		str(inst.get_node_or_null("LockoutToast") != null),
		"【被拦住】" if GameState.left_team.is_empty() else "【放过去了】"])

	for c in inst.get_children():
		if c.name == "LockoutToast":
			c.queue_free()
			inst.remove_child(c)

	## 第二次: 注周一 ⇒ 不该被这条闸拦。★不 await(会换场景)
	P2C.now_override_ts = pin_free
	GameState.left_team = [] as Array[String]
	inst._on_start()
	print("     ④注周一10:00: left_team=%d 只  封盘toast=%s  ⇒ %s" % [
		GameState.left_team.size(),
		str(inst.get_node_or_null("LockoutToast") != null),
		"【被拦住】" if GameState.left_team.is_empty() else "【放过去了】"])
