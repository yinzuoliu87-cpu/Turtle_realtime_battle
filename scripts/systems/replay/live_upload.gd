extends RefCounted
## 周六直播 · 打的人这一侧: 边打边把「到目前为止的录像」整行覆盖到服务端 `live_matches`。
## 方案书 docs/plans/20261007-实时观赛.md「周六·正在打的」; 看的人那一侧在 `live_spectate.gd`。
## 用户 2026-10-07:「观赛和回放是两码事明白吗」「周六即有回放也有正在打的啊」。
##
## ══════════════════════════════════════════════════════════════════════
##  什么时候发
## ══════════════════════════════════════════════════════════════════════
##   · 第一路开打(fight 事件)那一下建行 —— 之前什么都不发(没开打的人不算「正在打」)。
##   · 之后每出现一个事件(present / fight / surrender)发一次。
##   · 每 HEARTBEAT_STEPS 个 sim 步心跳一次: 带上「已推进到的步号」horizon。
##     ★观众只许重算到 horizon(`live_spectate.gd` 的 cap): 过了它, 打的人可能在中间按过认输 / 点过幕布,
##       观众先跑过去就分叉了。心跳就是把「这段时间里什么都没按」这件事告诉观众。
##   · 结算那一刻(on_settle)发最后一次: 带 end、ended = true。
##
## ★horizon 的口径(与 `ReplayRecorder` 的时序约定对齐, 见那里的头注):
##   在 pre_step(第 S+1 步开头, `_sim_step_n` = S)取: 步号 ≤ S 的事件全都记下了 ⇒ horizon = S。
##   在步与步之间记的事件(步号 S): 同上 ⇒ horizon = S。
##   在 sim 步**里面**记的事件(i=true, 步号 S+1): 这一步后面可能还有 ⇒ horizon = S(退一步)。
##   观众那边「只在 `_sim_step_n` < horizon 时才跑下一步」⇒ 跑到的每一步, 它要的事件都已经到手。
##
## ★发送是**进程级**的(静态队列), 不挂在战斗场上: 结算那一下的最后一行发出去时, 玩家可能已经点了「返回」,
##   战斗场没了 —— 挂在它身上的回调会对着已释放的对象。每场只留**最新**一行待发(旧的被覆盖, 不排队)。
## ★只覆盖不读回: 直播行坏一次, 下一次心跳就覆盖掉; 正式录像仍走 `replay_uploader.gd` 那条「回读才销单」的路。

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")

## 每 180 sim 步(= 3 游戏秒)心跳一次。观众端缓冲(`live_spectate.LAG_STEPS`)必须比它 + 轮询间隔长。
const HEARTBEAT_STEPS := 180
## 结束那一行发不出去时重试几次(其余行不重试: 下一次心跳自己会覆盖)。
const END_RETRY := 3

var rp                          # ReplayRecorder
var started := false
var ended := false
var horizon := 0
var _wk := 0
var _acc := ""
var _left: Dictionary = {}
var _right: Dictionary = {}

## 进程级: match_id → 还没发出去的最新一行 / 正在路上 / 结束行已重试几次。
static var _latest: Dictionary = {}
static var _busy: Dictionary = {}
static var _end_tries: Dictionary = {}
## 观测量(门禁分母): 发出几次 / 服务端回 2xx 几次 / 最后发出去的那一行。
static var sent_count := 0
static var ok_count := 0
static var last_sent: Dictionary = {}


## 这一局要不要直播: 只有周六闯关赛、接了服务器、有账号。
static func wanted() -> bool:
	if GameState == null or not SB.enabled() or str(GameState.account_id) == "":
		return false
	return ReplayRecorder.current_settle_kind() == ReplayRecorder.Phase2Cfg.SETTLE_GAUNTLET


func _init(r) -> void:
	rp = r
	_wk = int(GameState.week_anchor_ts)
	_acc = str(GameState.account_id)
	var mine: Dictionary = RU.my_snapshot()
	_left = slim(mine)
	var g = GameState.dual_ghost
	_right = slim(RU.strip_ghost(g if g is Dictionary else {}))


## 快照 → 直播行里那一侧: 只要名字 / 头像 / #ID(profile)与三统领(leaders)。阵容装备不上直播行。
static func slim(snap: Dictionary) -> Dictionary:
	var lu: Array = []
	var src: Array = snap.get("leaders", []) if snap.get("leaders", []) is Array else []
	for x in src:
		if lu.size() < 3:
			lu.append(str(x))
	var prof = snap.get("profile", {})
	return {"profile": (prof as Dictionary).duplicate(true) if prof is Dictionary else {}, "leaders": lu}


## 录到一条事件(`ReplayRecorder.allow_input` 录制分支)。`h` = 此刻能保证的 horizon(见头注)。
func on_event(kind: String, h: int) -> void:
	if kind == "fight":
		started = true
	if not started or ended:
		return
	horizon = maxi(horizon, h)
	_push()


## 每步开头(`ReplayRecorder.pre_step` 录制分支, 校验点之后)。
func heartbeat(s: int) -> void:
	if not started or ended or s <= 0 or s % HEARTBEAT_STEPS != 0:
		return
	horizon = maxi(horizon, s)
	_push()


## 结算(`ReplayRecorder.on_settle`, end 已写进录像)。
func finish(s: int) -> void:
	if not started or ended:
		return
	ended = true
	horizon = maxi(horizon, s)
	_push()


func _push() -> void:
	var row := build_row(rp.rec, _wk, _acc, _left, _right, horizon, ended)
	if not row.is_empty():
		push(row)


## 纯函数: 拼一行。缺东西(没 id / 没账号 / 太大)⇒ {}。
static func build_row(rec: Dictionary, wk: int, acc: String, left: Dictionary, right: Dictionary,
		h: int, done: bool) -> Dictionary:
	var id := str(rec.get("id", ""))
	if not SB.is_uuid(id) or acc == "" or wk <= 0:
		return {}
	var b64: String = RU.upload_b64(rec)
	if b64 == "" or b64.length() > RU.REPLAY_MAX_B64:
		return {}
	return {
		"match_id": id,
		"season_week": wk,
		"account_id": acc,
		"phase": RU.PH_GAUNTLET,
		"left_snapshot": left,
		"right_snapshot": right,
		"replay": b64,
		"horizon": h,
		"ended": done,
		"client_version": str(rec.get("client_version", "")),
	}


# ─────────────────────────────── 发送(进程级) ───────────────────────────────

static func push(row: Dictionary) -> void:
	var id := str(row.get("match_id", ""))
	_latest[id] = row
	_drain(id)


static func _drain(id: String) -> void:
	if _busy.has(id) or not _latest.has(id):
		return
	var row: Dictionary = _latest[id]
	_latest.erase(id)
	_busy[id] = true
	if SB.live_upsert_async(row, func(ok: bool) -> void: _done(id, row, ok)):
		sent_count += 1
		last_sent = row
	else:
		_busy.erase(id)            # 没发出去(没配后端 / 表没部署): 不记账, 下一次心跳再说


static func _done(id: String, row: Dictionary, ok: bool) -> void:
	_busy.erase(id)
	if ok:
		ok_count += 1
	elif bool(row.get("ended", false)) and not _latest.has(id):
		var n := int(_end_tries.get(id, 0)) + 1
		_end_tries[id] = n
		if n <= END_RETRY:
			_latest[id] = row
	_drain(id)


## 门禁用: 清掉进程级状态。
static func _reset_for_test() -> void:
	_latest = {}
	_busy = {}
	_end_tries = {}
	sent_count = 0
	ok_count = 0
	last_sent = {}
