extends Node
## 服务器裁判 · 周六一场: 提交 → 等结果 → 记账 → 取录像 → 播(2026-10-19 · 流程说明见 referee_watch.gd 头注)。
## 挂在匹配屏上(`MatchmakingScene._start_referee`); 匹配屏离场它就跟着没了 —— 交上去之后的单子在存档里
##   (`GameState.referee_pending`), 下次开主菜单 `RefereeWatch.resume_if_any` 补记。
## 状态: submit → wait → fetch → play; 停下 = error(屏上 msg 说清原因, 没有本地成绩) / local(服务端说开关已关 ⇒ 调用方走老路)。

const RW := preload("res://scripts/systems/replay/referee_watch.gd")

signal changed
var state := ""
var msg := ""
var job_id := -1
var match_id := ""
var polls := 0
var offline := 0
var view: Dictionary = {}
var _foe: Dictionary = {}
var _tm: Timer = null
var _inflight := false

func start(foe: Dictionary) -> void:
	_foe = foe.duplicate(true) if foe is Dictionary else {}
	_to(RW.ST_SUBMIT, RW.TXT_SUBMITTING)
	var snap: Dictionary = RW.my_snapshot()
	if snap.is_empty():
		_to(RW.ST_ERROR, RW.TXT_BAD_LINEUP)
		return
	var wk: int = RW.P2C.week_anchor_utc(int(RW.P2C.now_utc()))
	if not RW.RN.submit_gauntlet_async(wk, snap, _foe, func(res: Dictionary) -> void: _on_submit(wk, res)):
		_to(RW.ST_ERROR, RW.TXT_NEED_SERVER)

func _to(s: String, m: String) -> void:
	state = s
	msg = m
	changed.emit()

func _on_submit(wk: int, res: Dictionary) -> void:
	if not is_inside_tree():
		return
	var err := str(res.get("err", ""))
	match err:
		"":
			job_id = int(res.get("job_id", -1))
			match_id = str(res.get("match_id", ""))
			GameState.referee_pending = RW.pending_for(job_id, match_id, wk, _foe)
			GameState.save()
			_to(RW.ST_WAIT, RW.TXT_SETTLING)
			_tm = Timer.new()
			_tm.wait_time = RW.POLL_SEC
			_tm.timeout.connect(_poll)
			add_child(_tm)
			_tm.start()
			_poll()
		"off":
			RW.RN.note_flags({RW.RN.K_FINALS: RW.RN.finals_on(), RW.RN.K_GAUNTLET: false})
			_to(RW.ST_LOCAL, "")
		"update_required":
			_to(RW.ST_ERROR, RW.TXT_UPDATE)
		"closed", "wrong_week":
			_to(RW.ST_ERROR, RW.TXT_CLOSED)
		"finished":
			_to(RW.ST_ERROR, RW.TXT_FINISHED)
		"bad_snapshot", "bad_opponent":
			_to(RW.ST_ERROR, RW.TXT_BAD_LINEUP)
		_:
			_to(RW.ST_ERROR, RW.TXT_NEED_SERVER)   # offline / timeout / no_token / server / unavailable / not_signed_in

func _poll() -> void:
	if _inflight or state != RW.ST_WAIT:
		return
	_inflight = true
	polls += 1
	if not RW.RN.job_status_async(job_id, _on_status):
		_inflight = false
		_stop(RW.TXT_LATER)

func _stop(m: String) -> void:
	if _tm != null:
		_tm.stop()
	_to(RW.ST_ERROR, m)

func _on_status(res: Dictionary) -> void:
	_inflight = false
	if not is_inside_tree() or state != RW.ST_WAIT:
		return
	var err := str(res.get("err", ""))
	if err == "no_job":
		GameState.referee_pending = {}
		GameState.save()
		_stop(RW.TXT_FAILED)
		return
	if err != "":
		offline += 1
		if offline >= RW.OFFLINE_MAX:
			_stop(RW.TXT_LATER)          # 交上去了, 但问不到结果: 单子留着, 下次开主菜单补记
		return
	offline = 0
	match str(res.get("status", "")):
		"done":
			if _tm != null:
				_tm.stop()
			view = RW.settle(GameState, job_id, res)
			if view.is_empty():
				var gw := int(res.get("gw", -1))
				var gl := int(res.get("gl", -1))
				view = {"won": int(res.get("won", 0)) == 1, "reward": 0,
					"gw": gw if gw >= 0 else int(GameState.gauntlet_wins), "gl": gl if gl >= 0 else int(GameState.gauntlet_losses)}
			_fetch()
		"failed":
			GameState.referee_pending = {}
			GameState.save()
			_stop(RW.TXT_FAILED)
		_:
			if polls >= RW.POLL_MAX:
				_stop(RW.TXT_LATER)

func _fetch() -> void:
	_to(RW.ST_FETCH, RW.TXT_SETTLING)
	if not RW.SB.fetch_match_async(match_id, _on_match):
		_to(RW.ST_ERROR, RW.result_line(view) + " · " + RW.TXT_UNPLAYABLE)

func _on_match(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	var rec: Dictionary = {}
	var raw := PackedByteArray()
	if str(res.get("err", "")) == "":
		raw = RW.RF.decode_b64(str(res.get("b64", "")))
		rec = ReplayRecorder.decode(raw) if not raw.is_empty() else {}
	if rec.is_empty() or str(rec.get("id", "")) != match_id or not (rec.get("events", null) is Array) \
			or not (rec.get("cps", null) is Array) or not (rec.get("end", null) is Dictionary):
		_to(RW.ST_ERROR, RW.result_line(view) + " · " + RW.TXT_UNPLAYABLE)
		return
	RW.RF._cache(match_id, raw, true)      # 战绩页之后能在本机直接看(true = 服务器裁判局: 永不本机重算)
	_to(RW.ST_PLAY, "")
	## 逐帧直播 S5: 开关关 ⇒ 同步走 `play_settled`(本机重算, 与改之前一样); 开 ⇒ 播服务器的状态流
	RW.play_settled_route(get_tree(), rec, view, _on_routed)


## `play_settled_route` 的回调, 恰好一次(匹配屏已离场 ⇒ 不回调)。
func _on_routed(code: String, msg: String) -> void:
	if code == "":
		return
	var tail := msg if (code == "update_required" or code == "offline" or code == "no_stream") else RW.TXT_UNPLAYABLE
	_to(RW.ST_ERROR, RW.result_line(view) + " · " + tail)
