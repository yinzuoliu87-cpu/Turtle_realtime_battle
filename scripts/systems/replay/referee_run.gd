extends Node
## 服务器裁判 · 周六一场: 提交 → 等结果 → 记账 → 取录像 → 播(2026-10-19 · 流程说明见 referee_watch.gd 头注)。
## 挂在匹配屏上(`MatchmakingScene._server_pick`); 匹配屏离场它就跟着没了 —— 交上去之后的单子在存档里
##   (`GameState.referee_pending`), 主菜单 `RefereeWatch.resume_if_any` 补记。
## 状态: submit → wait → fetch → play; 停下 = error(屏上 msg 说清原因, 没有本地成绩) / local(服务端说开关已关 ⇒ 调用方走老路) /
##   later(交上去了、等到上限还没算完或问不到 ⇒ 单子留着, 匹配屏回主菜单, 主菜单补记)。
## ★2026-10-20 起对手由服务端挑(`referee_gauntlet_start`): 这里只交「我的阵容 + 第几场」, 对手卡片从回包里来(`opp`),
##   匹配屏拿它画 VS 卡。客户端不再有任何途径指定对手或种子。
## ★2026-10-27 起先在线排队(`start_queue`; 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md): 进队 → queue(心跳)→ 配上 ⇒
##   接回上面那条路(wait → fetch → play), 任务号 / 我是 a 还是 b 由服务端定; 取消 = cancel → left; 心跳回过期 = left(「已退出排队」)。
##   ★旧入口 referee_gauntlet_start 周六不再调(服务端线 10-27: 旧入口还开着, 但客户端别走它; 原来的 `start` 已删)。
##     服务端没有排队(404)⇒ 与断网同一句「连接服务器后才能比赛」, 不退回旧入口。

const RW := preload("res://scripts/systems/replay/referee_watch.gd")

signal changed
var state := ""
var msg := ""
var job_id := -1
var match_id := ""
var polls := 0
var offline := 0
var view: Dictionary = {}
var opp: Dictionary = {}          # 服务端挑的对手卡片 {profile{name, avatar, id, tag}, leaders}; 交上去之前是空的
var _tm: Timer = null
var _inflight := false
## ── 在线排队(2026-10-27 · 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.4)──
##   start_queue: 进队(锁定的阵容)→ waiting ⇒ 落排队单, 每 QUEUE_POLL_SEC 秒心跳 → paired ⇒ `_on_submit`(与开战回包同一条路)。
var side := "a"                   # 我在这一局是 a(左)还是 b(右); 只有在线排队配上的那一局可能是 b
var cell := Vector2i(-1, -1)      # 排队的战绩格子(几胜几负; 服务端回包为准)
var q_polls := 0                  # 心跳次数(门禁分母)
var _q_wk := 0
var _qtm: Timer = null
var _q_inflight := false
var _waited := 0                  # 服务端上一次回的「已等待秒数」
var _waited_at := 0               # 那一刻(本机毫秒); 两次心跳之间按墙钟往上数
var _opp_tries := 0

## 在线排队: 交锁定的阵容进队(本局唯一的开始入口)。
func start_queue() -> void:
	opp = {}
	side = "a"
	_opp_tries = 0
	_to(RW.ST_SUBMIT, RW.TXT_SUBMITTING)
	var snap: Dictionary = RW.my_snapshot()
	if snap.is_empty():
		_to(RW.ST_ERROR, RW.TXT_BAD_LINEUP)
		return
	_q_wk = RW.P2C.week_anchor_utc(int(RW.P2C.now_utc()))
	cell = Vector2i(int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))
	if not RW.RN.queue_join_async(_q_wk, snap, cell.x + cell.y, _on_join):
		_to(RW.ST_ERROR, RW.TXT_NEED_SERVER)


## 已等待多少秒(服务端那一份 + 本机墙钟补上两次心跳之间)。
func waited_now() -> int:
	return _waited + maxi(0, Time.get_ticks_msec() - _waited_at) / 1000


func _note_wait(res: Dictionary) -> void:
	if int(res.get("gw", -1)) >= 0 and int(res.get("gl", -1)) >= 0:
		cell = Vector2i(int(res["gw"]), int(res["gl"]))
	if res.has("waited"):
		_waited = maxi(0, int(res["waited"]))
		_waited_at = Time.get_ticks_msec()


func _on_join(res: Dictionary) -> void:
	if not is_inside_tree() or state != RW.ST_SUBMIT:
		return
	var err := str(res.get("err", ""))
	if err != "":
		_on_submit(_q_wk, res)            # 拒收原因与开战同一套(off / update_required / closed / finished / stale / unavailable …)
		return
	match str(res.get("status", "")):
		RW.RN.Q_WAITING:
			_note_wait(res)
			GameState.referee_pending = RW.queue_bill(_q_wk, cell.x, cell.y)
			GameState.save()
			_beat_on()
			_to(RW.ST_QUEUE, RW.queue_cell_text(cell.x, cell.y))
		RW.RN.Q_PAIRED:
			_paired(res)
		_:
			_to(RW.ST_ERROR, RW.TXT_NEED_SERVER)


## 开心跳计时器(只建一个)。
func _beat_on() -> void:
	if _qtm == null:
		_qtm = Timer.new()
		_qtm.wait_time = RW.QUEUE_POLL_SEC
		_qtm.timeout.connect(_heartbeat)
		add_child(_qtm)
	_qtm.start()


## 心跳(= 「我还在」): 服务端 15 秒没收到就让这一条过期、不会被配上。
func _heartbeat() -> void:
	if _q_inflight or state != RW.ST_QUEUE:
		return
	_q_inflight = true
	q_polls += 1
	if not RW.RN.queue_poll_async(_q_wk, _on_heartbeat):
		_q_inflight = false
		_queue_lost()


func _on_heartbeat(res: Dictionary) -> void:
	_q_inflight = false
	if not is_inside_tree() or state != RW.ST_QUEUE:
		return
	if str(res.get("err", "")) != "":
		offline += 1
		if offline >= RW.OFFLINE_MAX:
			_queue_lost()
		return
	offline = 0
	match str(res.get("status", "")):
		RW.RN.Q_WAITING:
			_note_wait(res)
			_to(RW.ST_QUEUE, RW.queue_cell_text(cell.x, cell.y))
		RW.RN.Q_PAIRED:
			_paired(res)
		_:
			## 过期(切后台太久 / 心跳断了)/ 不在队里 ⇒「已退出排队」; 收盘(reason closed)⇒「当前不在闯关赛时段」;
			##   配上的那一局算失败了(none + reason job_failed)⇒「结算失败，请重新开战」(回主菜单重新排)
			var why := str(res.get("reason", ""))
			_queue_left(RW.TXT_CLOSED if why == "closed" else (RW.TXT_FAILED if why == "job_failed" else RW.TXT_QUEUE_LEFT))


## 排队中按「取消」。返回 false = 不在排队(调用方照原来的「←」离开)。
func cancel_queue() -> bool:
	if state != RW.ST_QUEUE:
		return false
	if _qtm != null:
		_qtm.stop()
	_to(RW.ST_CANCEL, RW.TXT_QUEUE_CANCELLING)
	if not RW.RN.queue_cancel_async(_q_wk, _on_cancel_reply):
		_to(RW.ST_LEFT, "")
	return true


func _on_cancel_reply(res: Dictionary) -> void:
	if not is_inside_tree() or state != RW.ST_CANCEL:
		return
	if str(res.get("err", "")) != "":
		## 不知道取消成没成(断网): 排队单留着, 主菜单补查(配上了照样补记, 没配上就销单)
		_to(RW.ST_LEFT, "")
		return
	if str(res.get("status", "")) == RW.RN.Q_PAIRED:
		_paired(res)                      # 点取消的那一刻刚好配上: 这一局照样算, 照配上处理
		return
	_queue_left("")


## 已出队、没有对局: 销排队单(只销排队单, 不碰任务单)。
func _queue_left(m: String) -> void:
	if _qtm != null:
		_qtm.stop()
	if RW.is_queue_bill(GameState.referee_pending):
		GameState.referee_pending = {}
		GameState.save()
	_to(RW.ST_LEFT, m)


## 连着问不到: 不知道配没配上 ⇒ 排队单留着(主菜单补查), 匹配屏回主菜单。
func _queue_lost() -> void:
	if _qtm != null:
		_qtm.stop()
	_to(RW.ST_LATER, RW.TXT_QUEUE_LOST)


## 配上了: 接回开战那条路(`_on_submit` 成功分支: 落任务单 → 查任务 → 记账 → 取录像 → 播)。
##   取消回包只带任务号(没有对手卡片)⇒ 回到排队状态、马上再心跳一次拿卡片(心跳对已配上的人回 paired + 卡片); 问两次还没有就不等了。
func _paired(res: Dictionary) -> void:
	_note_wait(res)
	side = str(res.get("side", "a"))
	if (res.get("opp", {}) as Dictionary).is_empty() and _opp_tries < 2:
		_opp_tries += 1
		state = RW.ST_QUEUE
		_beat_on()
		_heartbeat()
		return
	if _qtm != null:
		_qtm.stop()
	_on_submit(_q_wk, {"err": "", "job_id": int(res.get("job_id", -1)), "match_id": str(res.get("match_id", "")),
		"opp": res.get("opp", {})})


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
			opp = (res.get("opp", {}) as Dictionary).duplicate(true)
			GameState.referee_pending = RW.pending_for(job_id, match_id, wk, opp, side)
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
		"stale":
			## 本机战绩落后于服务端账本(上一场的账没补上): 以账本为准对齐, 让玩家重新开战(那一场按账本上的第 N 场重交)。
			RW.adopt_ledger(GameState, int(res.get("gw", -1)), int(res.get("gl", -1)))
			_to(RW.ST_ERROR, RW.TXT_STALE)
		"no_opponent":
			_to(RW.ST_ERROR, RW.TXT_NO_MATCH)
		_:
			_to(RW.ST_ERROR, RW.TXT_NEED_SERVER)   # offline / timeout / no_token / server / unavailable / not_signed_in

func _poll() -> void:
	if _inflight or state != RW.ST_WAIT:
		return
	_inflight = true
	polls += 1
	if not RW.RN.job_status_async(job_id, _on_status):
		_inflight = false
		_later()

func _stop(m: String) -> void:
	if _tm != null:
		_tm.stop()
	_to(RW.ST_ERROR, m)


## 交上去了、这一屏等不到结果: 单子留着(主菜单补记), 匹配屏据此回主菜单。
func _later() -> void:
	if _tm != null:
		_tm.stop()
	_to(RW.ST_LATER, RW.TXT_LATER)

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
			_later()                     # 交上去了, 但问不到结果: 单子留着, 主菜单补记
		return
	offline = 0
	if not RW.SB.is_uuid(match_id) and RW.SB.is_uuid(str(res.get("match_id", ""))):
		## 排队配上时回包只给了任务号(2026-10-27): 录像号用任务状态里的那个(取录像 / 战绩页都按它)
		match_id = str(res["match_id"])
		if GameState.referee_pending is Dictionary and int((GameState.referee_pending as Dictionary).get("job_id", -1)) == job_id:
			GameState.referee_pending["match_id"] = match_id
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
			if side == "b":
				## 我在右边: 播录像时左边写对手名、右边写我(`RefereeWatch.watch_names`); 胜负服务端已按 B 给
				view["side"] = "b"
				view["foe_name"] = str((opp.get("profile", {}) as Dictionary).get("name", "")) if opp.get("profile", null) is Dictionary else ""
			_fetch()
		"failed":
			GameState.referee_pending = {}
			GameState.save()
			_stop(RW.TXT_FAILED)
		_:
			if polls >= RW.poll_max():
				_later()                 # 裁判机排队 / 算得慢: 等到上限还没算完 ⇒ 不在这一屏干等

func _fetch() -> void:
	if RW.skip_play:
		_to(RW.ST_SKIPPED, RW.result_line(view))   # 陪练号(SIM_SKIP_WATCH): 账已记完, 不取录像、不播
		return
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
