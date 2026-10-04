extends Node
## verify_replay_window.gd — 回放可见期改成「本周」+ 本机缓存清理(2026-10-04)
##
## ★由来: 服务端 `purge_old_matches()` 2026-10-04 上了生产 —— 每周二 00:00 UTC 删掉
##   「本周一 00:00 UTC 之前」的全部对局(用户:「照你原来定的，周二 0 点删」= U7「周一过后就没了」)。
##   客户端原来按「14 天内」出按钮 ⇒ 服务端已经删了的那一场还出按钮(点了必然「找不到」= 死按钮)。
##
## ① 纯函数 `ReplayFetcher.server_keeps(ts, now)` —— 注入时钟打边界: 周一 23:59 / 周二 00:00 / 周二 00:01
## ② 真入口: 真的实例化 `Record.tscn`, `Phase2Config.now_override_ts` 钉住「现在」, 数那一行有没有按钮;
##    本机有录像的那一行不受周界影响
## ③ 缓存清理纯判据 `stale_cache_ids` 的边界(上周一 00:00 前后一秒 / 在战绩里 / 在上传队列里 / 读不到时间)
## ④ 真入口: 在 user://replays/ 里真放文件 → 真的实例化 `Record.tscn` → 盘上真的少了 / 没少哪几个
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const SB := preload("res://scripts/net/supabase.gd")
const RECORD_SCENE := "res://scenes/Record.tscn"
const DAY := 86400

var _n := 0
var _fail := 0
var _gs = null
var _hist0: Array = []
var _queue0: Array = []


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	print("=== 回放可见期(本周) + 本机缓存清理 ===")
	if _gs == null:
		_ok("★分母: GameState 在", false)
		_finish()
		return
	_gs.test_mode = true
	_hist0 = (_gs.match_history as Array).duplicate(true)
	_queue0 = (_gs.replay_upload_pending as Array).duplicate(true)

	## 2026-10-05 是周一(UTC)。★不凭记忆: 下面先用产品自己的周界函数确认它真是周一 00:00。
	var mon: int = int(Time.get_unix_time_from_datetime_string("2026-10-05T00:00:00"))
	_ok("★分母: 基准时刻是周一 00:00 UTC(产品自己的 week_anchor_utc 认它)",
		P2C.iso_weekday_utc(mon) == 1 and P2C.week_anchor_utc(mon) == mon and P2C.week_anchor_utc(mon + 3 * DAY) == mon,
		"mon=%d" % mon)

	_t_pure(mon)
	await _t_record_buttons(mon)
	_t_stale_pure(mon)
	await _t_prune_real()

	_gs.match_history = _hist0
	_gs.replay_upload_pending = _queue0
	P2C.now_override_ts = 0
	_finish()


func _finish() -> void:
	if _n < 30:
		print("  [FAIL] ★分母: 断言只有 %d 条(<30) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 回放可见期 + 缓存清理(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ① server_keeps 边界
# ══════════════════════════════════════════════════════════════
func _t_pure(mon: int) -> void:
	print("--- ① server_keeps(ts, now) 边界 ---")
	var last_sun: int = mon - 12 * 3600                # 上周日 12:00
	var last_mon: int = mon - 7 * DAY                  # 上周一 00:00
	var older: int = last_mon - 1                      # 上上周日 23:59:59
	var this_mon: int = mon                            # 本周一 00:00
	var just_before: int = mon - 1                     # 上周日 23:59:59(上周最后一秒)
	var nows := {
		"周一 23:59": mon + 23 * 3600 + 59 * 60,
		"周二 00:00": mon + DAY,
		"周二 00:01": mon + DAY + 60,
		"周日 23:59": mon + 6 * DAY + 23 * 3600 + 59 * 60,
	}
	## 期望表: [上周日, 上周一00:00, 上上周最后一秒, 本周一00:00, 上周最后一秒]
	var want := {
		"周一 23:59": [true, true, false, true, true],
		"周二 00:00": [false, false, false, true, false],
		"周二 00:01": [false, false, false, true, false],
		"周日 23:59": [false, false, false, true, false],
	}
	var names := ["上周日 12:00", "上周一 00:00", "上上周最后一秒", "本周一 00:00", "上周最后一秒"]
	var tss := [last_sun, last_mon, older, this_mon, just_before]
	for k in nows.keys():
		var now: int = nows[k]
		for i in range(tss.size()):
			var got: bool = RF.server_keeps(tss[i], now)
			_ok("① 现在=%s, 比赛=%s ⇒ 服务端%s" % [k, names[i], "还留着" if want[k][i] else "已清掉"],
				got == want[k][i], "实得 %s" % str(got))
		_ok("① 现在=%s: 刚打完的那一场(ts=now)一定留着" % k, RF.server_keeps(now, now))


# ══════════════════════════════════════════════════════════════
#  ② 真入口: 战绩页出不出按钮
# ══════════════════════════════════════════════════════════════
func _buttons(rs: Node) -> Array:
	var ids: Array = []
	for b in rs.find_children("ReplayBtn", "Button", true, false):
		ids.append(str((b as Button).get_meta("replay_id", "")))
	return ids


func _open_record() -> Node:
	var rs: Node = (load(RECORD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(rs)
	await _frames(3)
	return rs


func _t_record_buttons(mon: int) -> void:
	print("--- ② 真入口: 战绩页的回放按钮 ---")
	var had_env: bool = OS.has_environment(SB.ENV_URL)
	var env0: String = OS.get_environment(SB.ENV_URL)
	var key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	_ok("★分母: 后端开着(关着时远端那一行本来就不出按钮, 下面全是空检查)", SB.enabled())
	var remote_last := "11111111-2222-4333-8444-555555555555"   # 上周日打的, 别的设备(本机没有文件)
	var remote_this := "66666666-7777-4888-8999-aaaaaaaaaaaa"   # 本周一打的, 别的设备
	var local_last := "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"    # 上周日打的, 本机有录像
	_write_rpl(local_last)
	_ok("★分母: 本机那一场的录像文件真的在", RF.local_available(local_last))
	_ok("★分母: 远端那两场本机确实没有文件", not RF.local_available(remote_last) and not RF.local_available(remote_this))
	_gs.match_history = [
		{"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 1, "ts": mon - 12 * 3600, "replay_id": remote_last},
		{"result": "lose", "lineup": ["basic"], "mode": "实时", "turn": 2, "ts": mon + 60, "replay_id": remote_this},
		{"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 3, "ts": mon - 12 * 3600, "replay_id": local_last},
	]
	var cases := {
		"周一 23:59": [mon + 23 * 3600 + 59 * 60, [remote_last, remote_this, local_last]],
		"周二 00:00": [mon + DAY, [remote_this, local_last]],
		"周二 00:01": [mon + DAY + 60, [remote_this, local_last]],
	}
	for k in cases.keys():
		P2C.now_override_ts = int(cases[k][0])
		var rs: Node = await _open_record()
		var ids: Array = _buttons(rs)
		_ok("② 现在=%s ⇒ 出按钮的行 = %s" % [k, str(cases[k][1])], ids == cases[k][1], "实得 %s" % str(ids))
		rs.queue_free()
		await _frames(1)
	P2C.now_override_ts = 0
	DirAccess.remove_absolute(ReplayRecorder.SAVE_DIR + local_last + ".rpl")
	if had_env:
		OS.set_environment(SB.ENV_URL, env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	ProjectSettings.set_setting(SB.SETTING_KEY, key0)


func _write_rpl(id: String) -> void:
	DirAccess.make_dir_recursive_absolute(ReplayRecorder.SAVE_DIR)
	var f := FileAccess.open(ReplayRecorder.SAVE_DIR + id + ".rpl", FileAccess.WRITE)
	if f != null:
		f.store_buffer(ReplayRecorder.encode({"id": id, "v": 1}))
		f.close()


# ══════════════════════════════════════════════════════════════
#  ③ 缓存清理纯判据边界
# ══════════════════════════════════════════════════════════════
func _t_stale_pure(mon: int) -> void:
	print("--- ③ stale_cache_ids 边界 ---")
	var now: int = mon + DAY + 60                      # 周二 00:01
	var cutoff: int = mon - 7 * DAY                    # 上周一 00:00
	var files := [
		{"id": "a0000000-0000-4000-8000-000000000001", "mtime": cutoff - 1},   # 上上周最后一秒, 无主 ⇒ 删
		{"id": "a0000000-0000-4000-8000-000000000002", "mtime": cutoff},       # 上周一 00:00 整 ⇒ 留
		{"id": "a0000000-0000-4000-8000-000000000003", "mtime": cutoff - 30 * DAY},   # 很旧但还在战绩里 ⇒ 留
		{"id": "a0000000-0000-4000-8000-000000000004", "mtime": cutoff - 30 * DAY},   # 很旧但还在上传队列 ⇒ 留
		{"id": "a0000000-0000-4000-8000-000000000005", "mtime": 0},            # 读不到时间 ⇒ 留
		{"id": "a0000000-0000-4000-8000-000000000006", "mtime": now},          # 本周的 ⇒ 留
		{"id": "a0000000-0000-4000-8000-000000000007", "mtime": cutoff - 30 * DAY},   # 很旧、无主 ⇒ 删
	]
	var keep := ["a0000000-0000-4000-8000-000000000003"]
	var queued := ["a0000000-0000-4000-8000-000000000004"]
	var got: Array = RF.stale_cache_ids(files, keep, queued, now)
	_ok("③ 只删「无主 + 比上周一还旧」的两份", got == ["a0000000-0000-4000-8000-000000000001", "a0000000-0000-4000-8000-000000000007"],
		"实得 %s" % str(got))
	## 周界跟着 now 所在的那一周走: 周一 23:59 与周二 00:01 在同一周 ⇒ 「上周一」是同一个时刻 ⇒ 结果应当一样。
	var got_mon: Array = RF.stale_cache_ids(files, keep, queued, mon + 23 * 3600 + 59 * 60)
	_ok("③ 同一周内(周一 23:59)周界不变, 结果同上", got_mon == got, "实得 %s" % str(got_mon))
	## 下一周的周一 00:00: cutoff 前移一周 ⇒ 「上周一 00:00 整」那份变成无主旧文件 ⇒ 也删
	var got_next: Array = RF.stale_cache_ids(files, keep, queued, mon + 7 * DAY)
	_ok("③ 到了下周一, 原来卡在边界上的那份也该删", got_next.has("a0000000-0000-4000-8000-000000000002")
		and not got_next.has("a0000000-0000-4000-8000-000000000003") and not got_next.has("a0000000-0000-4000-8000-000000000004")
		and not got_next.has("a0000000-0000-4000-8000-000000000005"), "实得 %s" % str(got_next))


# ══════════════════════════════════════════════════════════════
#  ④ 真入口: 进战绩页真的删盘上的文件
# ══════════════════════════════════════════════════════════════
func _t_prune_real() -> void:
	print("--- ④ 真入口: 进战绩页清缓存 ---")
	var dir := ReplayRecorder.SAVE_DIR
	var free_old := "c0000000-0000-4000-8000-000000000001"
	var in_hist := "c0000000-0000-4000-8000-000000000002"
	var in_queue := "c0000000-0000-4000-8000-000000000003"
	var bad_name := "NOT-A-SAFE-ID"
	for id in [free_old, in_hist, in_queue, bad_name]:
		_write_rpl(id)
	var nf := FileAccess.open(dir + "notes.txt", FileAccess.WRITE)
	if nf != null:
		nf.store_string("x")
		nf.close()
	_ok("★分母: 盘上真放了 4 份 .rpl + 1 个别的文件",
		FileAccess.file_exists(dir + free_old + ".rpl") and FileAccess.file_exists(dir + in_hist + ".rpl")
		and FileAccess.file_exists(dir + in_queue + ".rpl") and FileAccess.file_exists(dir + bad_name + ".rpl")
		and FileAccess.file_exists(dir + "notes.txt"))
	var mt: int = int(FileAccess.get_modified_time(dir + free_old + ".rpl"))
	_ok("★分母: 读得到文件修改时间(读不到的一律不删 ⇒ 下面会是空检查)", mt > 0, "mtime=%d" % mt)
	_gs.match_history = [{"result": "win", "lineup": ["basic"], "mode": "实时", "turn": 1, "ts": mt, "replay_id": in_hist}]
	_gs.replay_upload_pending = [{"id": in_queue, "wk": P2C.week_anchor_utc(mt), "acc": "", "t": mt, "ls": {}}]

	## (a) 「现在」= 真实时间: 刚写的文件都是本周的 ⇒ 一份都不删
	P2C.now_override_ts = 0
	var rs: Node = await _open_record()
	_ok("④a 本周刚写的文件: 进战绩页一份都不删", (rs.get("pruned_replays") as Array).is_empty()
		and FileAccess.file_exists(dir + free_old + ".rpl"), "删了 %s" % str(rs.get("pruned_replays")))
	rs.queue_free()
	await _frames(1)

	## (b) 「现在」= 三周之后: 刚写的文件已比「上周一」旧 ⇒ 只删无主那份
	P2C.now_override_ts = mt + 21 * DAY
	rs = await _open_record()
	var pr: Array = rs.get("pruned_replays")
	_ok("④b 三周后进战绩页: 恰好删了无主的那一份", pr == [free_old], "删了 %s" % str(pr))
	_ok("④b ★盘上那份真的没了", not FileAccess.file_exists(dir + free_old + ".rpl"))
	_ok("④b 还在战绩里的那份没动", FileAccess.file_exists(dir + in_hist + ".rpl"))
	_ok("④b 还在上传队列里的那份没动", FileAccess.file_exists(dir + in_queue + ".rpl"))
	_ok("④b 名字不像 id 的 .rpl 与别的文件都没动",
		FileAccess.file_exists(dir + bad_name + ".rpl") and FileAccess.file_exists(dir + "notes.txt"))
	rs.queue_free()
	await _frames(1)
	P2C.now_override_ts = 0
	for fn in [in_hist + ".rpl", in_queue + ".rpl", bad_name + ".rpl", "notes.txt"]:
		DirAccess.remove_absolute(dir + fn)
