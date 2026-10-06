extends Node
## verify_elim_no_coin.gd —— 被打出局的那一局不发深海币(用户 2026-10-06「可以不发」)
##
## 由来: 60 人实操台账 —— 出局那局照发深海币, 但出局后商店锁住、深海币周一清零 ⇒ 一枚都花不出去。
## 走真入口 `_settle_season()` + 真结算屏 `_build_reward_chips()`, 钟钉在周二(积分赛日), 与跑门禁的星期几无关。
##   ① 分母: 满命赢一局 ⇒ 照发(>0), 结算屏有「深海币」那格
##   ② 剩 1 命输掉(这一局把人打出局) ⇒ 发 0, 钱包不变, 结算屏没有「深海币」那格
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
var _n := 0
var _fail := 0

func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if c: print("  [PASS] ", t, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", t, "  ", d)

func _chip_texts(scene) -> String:
	var box = scene._hud._build_reward_chips(GameState)
	var out := ""
	if box == null: return out
	var st: Array = [box]
	while not st.is_empty():
		var n = st.pop_back(); st.append_array(n.get_children())
		if n is Label: out += str((n as Label).text) + "|"
	box.free()
	return out

func _ready() -> void:
	await get_tree().process_frame
	print("=== 出局那一局不发深海币 ===")
	GameState.test_mode = true
	var real := int(Time.get_unix_time_from_system())
	var tue: int = P2C.week_anchor_utc(real) + 86400 + 12 * 3600     # 本周二 12:00 UTC
	P2C.now_override_ts = tue
	_ok("★分母: 钉的那一刻是积分赛日", str(P2C.phase_at_utc(tue)) == str(P2C.PHASE_RANKED), str(P2C.phase_at_utc(tue)))
	GameState.week_anchor_ts = P2C.week_anchor_utc(tue)
	var scene = RB.new()
	add_child(scene)
	for _i in range(30): await get_tree().process_frame
	GameState.season_leaders = ["basic", "fortune", "ninja"]
	GameState.week_anchor_ts = P2C.week_anchor_utc(tue)

	## ① 满命赢 ⇒ 照发
	GameState.hearts = int(P2C.HEARTS_MAX)
	GameState.ranked_used = 0
	var w0: int = int(GameState.meta_deepsea_coins)
	scene._settle_season(true)
	var got1: int = int(GameState.meta_deepsea_coins) - w0
	_ok("① ★分母: 满命赢一局照发深海币(>0)", got1 > 0 and int(scene._last_reward) == got1, "钱包 +%d / _last_reward %d" % [got1, int(scene._last_reward)])
	_ok("① 结算屏有「深海币」那格", _chip_texts(scene).find("深海币") >= 0, _chip_texts(scene))

	## ② 剩 1 命输掉 ⇒ 这一局把人打出局 ⇒ 不发
	GameState.hearts = 1
	var w1: int = int(GameState.meta_deepsea_coins)
	scene._settle_season(false)
	_ok("② ★分母: 这一局确实把人打出局了", GameState.is_eliminated(), "hearts=%d" % int(GameState.hearts))
	_ok("② ★★出局那一局钱包一枚不加", int(GameState.meta_deepsea_coins) == w1, "前 %d / 后 %d" % [w1, int(GameState.meta_deepsea_coins)])
	_ok("② _last_reward 记 0(结算屏读的就是它)", int(scene._last_reward) == 0, str(scene._last_reward))
	var ct := _chip_texts(scene)
	_ok("② 结算屏不放「深海币」那格(不写 +0)", ct.find("深海币") < 0, ct)

	P2C.now_override_ts = 0
	scene.queue_free()
	print("")
	if _fail == 0 and _n >= 7:
		print("ALL PASS — 出局那一局不发深海币 (%d 条)" % _n)
		get_tree().quit(0)
	else:
		print("FAILED %d / %d" % [_fail, _n])
		get_tree().quit(1)
