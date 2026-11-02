extends Node
## _probe_d4b.gd —— D-4b 真 Supabase 端到端探针（不是门禁，跑完就删）
##
## 验的是门禁永远验不到的那一段：**A 传上去的，B 真的能拉回来并入池；而 A 自己拉不到自己。**
##
## ★★隔离手段：`season_week = 1`（一个**不可能存在的周**，真实周锚点是 ~1.79e9）。
##   这样探针行永远不会被真实玩家的查询 `season_week=eq.<真周>` 命中。
##   ⚠ 这很重要：`ghosts` 表**故意没给 delete 策略**，写进去就删不掉。

const SB := preload("res://scripts/net/supabase.gd")
const BE := preload("res://scripts/net/backend.gd")
const RP := preload("res://scripts/net/remote_pool.gd")

const FAKE_WEEK := 1        # 不可能的周 ⇒ 真实玩家永远查不到这些行
const BATTLES := 7

var _tree: SceneTree = null


func _p(s: String) -> void:
	print("[D4B] " + s)


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await get_tree().process_frame


## 造一份**能通过 `snapshot_valid()`** 的快照（手写，不走 GameState）
func _snap(gid: String) -> Dictionary:
	return {
		"schema_ver": BE.SCHEMA_VER,
		"ghost_id": gid,
		"is_bot": false,
		"bracket": 3,
		"profile": {"name": "探针阵容", "avatar": "basic", "id": gid},
		"leaders": ["basic", "stone", "ice"],
		"lane_assign": {},
		"minions": {},
		"loadouts": {},
		"equipped": {},
		"pet_levels": {"basic": 3, "stone": 3, "ice": 3},
		"season_total_battles": BATTLES,
		"season_eggs_killed": 1,
		"season_wins": 2,
		"hearts": 6,
		"season_sweeps": 0,
	}


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	_p("后端启用=%s  url=%s" % [str(SB.enabled()), SB.base_url()])
	if not SB.enabled():
		_p("没配后端, 探针无意义")
		_tree.quit(1)
		return

	# ── ① 账号 A 登录 ──
	GameState.account_id = ""
	SB.ensure_signed_in_async()
	await _wait(6.0)
	var acc_a := str(GameState.account_id)
	_p("① 账号A = %s" % acc_a)
	if acc_a == "":
		_p("★A 没登上, 后面全没意义"); _tree.quit(1); return

	# ── ② A 上传一份【结构合法】的快照 ──
	var gid_a := "g_probeA_%d_basic-ice-stone" % FAKE_WEEK
	var row := SB.ghost_row_from_snapshot(_snap(gid_a), acc_a, FAKE_WEEK, BATTLES, "probe")
	_p("② A 的行: 非空=%s  battles=%s" % [str(not row.is_empty()), str(row.get("battles", "?"))])
	SB.upload_ghost_async(row)
	await _wait(6.0)
	_p("② 上传记账: try=%d ok=%d" % [SB.upload_try_count(), SB.upload_ok_count()])

	# ── ③ A 自己拉 —— 应该【拉不到自己】 ──
	SB._reset_pull_for_test()
	SB.pull_opponents_async(FAKE_WEEK, BATTLES, acc_a)
	await _wait(6.0)
	var st_a: Dictionary = SB.last_pull_stats()
	_p("③ A 自己拉: try=%d ok=%d  total=%d added=%d 拒=%d %s"
		% [SB.pull_try_count(), SB.pull_ok_count(), int(st_a.get("total", -1)),
			int(st_a.get("added", -1)), int(st_a.get("rejected", -1)), str(st_a.get("reasons", []))])

	# ── ④ 换成账号 B（另一个匿名号），再拉 —— 应该【拉得到 A】 ──
	GameState.account_id = ""
	SB._reset_auth_for_test()
	SB.ensure_signed_in_async()
	await _wait(6.0)
	var acc_b := str(GameState.account_id)
	_p("④ 账号B = %s   (与A不同=%s)" % [acc_b, str(acc_b != acc_a and acc_b != "")])
	if acc_b == "":
		_p("★B 没登上"); _tree.quit(1); return

	SB._reset_pull_for_test()
	SB.pull_opponents_async(FAKE_WEEK, BATTLES, acc_b)
	await _wait(8.0)
	var st_b: Dictionary = SB.last_pull_stats()
	_p("④ B 拉 A: try=%d ok=%d  total=%d added=%d 拒=%d %s"
		% [SB.pull_try_count(), SB.pull_ok_count(), int(st_b.get("total", -1)),
			int(st_b.get("added", -1)), int(st_b.get("rejected", -1)), str(st_b.get("reasons", []))])

	# ── ⑤ 查询串长什么样 ──
	_p("⑤ 查询串 = %s" % SB.opponents_query(FAKE_WEEK, BATTLES, acc_b))

	# ── ⑥ 判定 ──
	var ok3: bool = int(st_a.get("total", -1)) == 0
	var ok4: bool = int(st_b.get("total", -1)) >= 1 and int(st_b.get("added", -1)) >= 1
	_p("══ ③ A 拉不到自己(total==0): %s" % ("通过" if ok3 else "★没通过"))
	_p("══ ④ B 拉得到 A 且入池:     %s" % ("通过" if ok4 else "★没通过"))
	GameState.account_id = ""
	_tree.quit(0 if (ok3 and ok4) else 1)
