extends RefCounted
## 观赛 —— 看**正在打的**(周六直播)与**本轮刚开播的**(周日开播)。与回放分开: 方案书 docs/plans/20261007-实时观赛.md。
## 用户 2026-10-07:「观赛和回放是两码事明白吗」「周六即有回放也有正在打的啊」。
##
## ══════════════════════════════════════════════════════════════════════
##  与回放的区别(全仓统一用词)
## ══════════════════════════════════════════════════════════════════════
##   回放: 已经打完、结果公开; 屏上有暂停 / 倍速 / 进度条 / 全场时长 / 再看一遍(`replay_controls.gd`)。
##   观赛: 看之前不知道结果; 屏上只有对战 HUD + 「直播」/「开播」小签 + 「退出」; 收尾卡才揭晓谁赢。
##   参考 docs/plans/ref/20261007-周末观战参考/live_spectate.jpg(皇室战争观战: 同一套 HUD + 红底 Live, 没有播放控制)。
##
## ══════════════════════════════════════════════════════════════════════
##  播 = 本机重算(与回放同一条路: `ReplayRecorder` 的 play 模式), 这里只管「这一帧跑几步」
## ══════════════════════════════════════════════════════════════════════
##   战斗场 `_process` 把真实帧时长交给 `ReplayRecorder.sim_feed(rd)` → 本模块 `feed(rd)` 决定喂给累加器多少。
##   ★不改步长、不另起推进路径: 每一步仍是 `_sim_step(SIM_DT)`, 校验点照样逐个比(与倍速同一个道理)。
##   · cap(只直播有): 只许跑到 `horizon`(打的人最后一次心跳时的步号)。过了它, 打的人可能在中间认过输 /
##     点过幕布 —— 先跑过去就分叉了。
##   · target: 该到的那一步。直播 = horizon − LAG_STEPS(留出心跳 + 轮询的空当, 不至于一卡一卡);
##     开播 = (服务端此刻 − 翻面时刻) × 60(迟到的人从当前进度看, 不能倒回)。
##   · 落后 target 超过 CATCH_SLACK ⇒ 追帧(一帧 8 步, 屏上「同步中」); 追上了 ⇒ 1 倍跟播。
##   · 跑到 cap ⇒ 停住攒一点(RESUME_STEPS)再放 —— 不攒的话每次心跳只放 3 秒、停 3 秒。
##   · 停在幕布 / 摆位上、打的人还没按下一路开打 ⇒ 屏上「下路准备中」。
##   · horizon 超过 LIVE_STALE_SEC 没涨(打的人断网 / 杀进程)⇒ 「直播中断」收尾卡。
##
## ★这一层**不碰任何对局状态**: 只读 `_sim_step_n` / `_dl_state`, 只写累加器余量 `_sim_accum`。

const SB := preload("res://scripts/net/supabase.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")

const KIND_LIVE := "live"
const KIND_PREMIERE := "premiere"
## 屏上的字(短名词 / 短指令; 不拟人、不加语气词)。
const TAG_LIVE := "直播"
const TAG_PREMIERE := "开播"
const TXT_WAIT := "下路准备中"
const TXT_SYNC := "同步中"
const TXT_BROKEN := "直播中断"
const TXT_VERSION := "版本不同，无法观赛"
const BTN_WATCH := "观赛"

## 观众每隔几秒问一次服务端(内测规模可接受; 上量后换 Supabase Realtime 推送, 见方案书风险 2)。
const POLL_SEC := 2.5
## 直播: 跟在 horizon 后面多少步(6 秒)。必须 > 心跳(`live_upload.HEARTBEAT_STEPS` 3 秒) + 轮询(2.5 秒)。
const LAG_STEPS := 360
## 跑到 cap 停住后, cap 再往前长出多少步才接着放(4 秒)。
const RESUME_STEPS := 240
## 落后 target 多少步算「要追」(1.5 秒)。
const CATCH_SLACK := 90
## 追帧时一帧跑几步(= 战斗场累加器每帧上限 8)。
const CATCH_PER_FRAME := 8
## horizon 多久没涨算中断: 与赛况板「还在打吗」同一个数(`gauntlet_board.LIVE_STALE_SEC`, 墙钟秒)。
##   打的人每 3 秒一次心跳, 摆位思考期间心跳照发 ⇒ 不会误判。
## 开播窗口: 翻面时刻起多久之内不揭晓胜负。一场时长不知道时用上限(4 分钟, 与服务端「4 分钟重放」同一个数);
##   看过那一场(拿到了录像)就按真实时长 + 缓冲。
const PREMIERE_SEC := 240
const PREMIERE_BUFFER := 15
## 挂上去的会话多久没被战斗场取走就作废(取录像失败 / 人走了 —— 别让它被下一场不相干的回放捡走)。
const PENDING_TTL_MS := 30000

## 下一场要不要按观赛播(进场前挂上, 战斗场 `ReplayRecorder.start()` 里 `take()` 取走)。
static var pending: Dictionary = {}
## 开播: 这台设备上看完了的场次(key → true)。看完的那一场在对阵图上立刻揭晓, 不必等窗口过去。
static var watched: Dictionary = {}
## 开播: 拿到过录像的场次的真实步数(key → 步数), 开播窗口按它算。
static var known_len: Dictionary = {}
## 只给门禁: > 0 时替代 LIVE_STALE_SEC。
static var stale_sec_for_test := 0.0

var rp                          # ReplayRecorder
var battle
var kind := ""
var match_id := ""
var horizon := 0
var ended := false
var flip_ts := 0
var srv_ref := 0
var ref_ms := 0
var key := ""
var catching := true
var buffering := false
var broken := false
var broken_why := ""
var status := ""                # 屏上那句话("" = 不显示)
var polls := 0                  # 门禁分母: 问过几次 / 合并进来几次新数据
var merges := 0
var max_ahead := -1             # 门禁: 跑到过的最大「步号 − cap」(必须 ≤ 0)
var _last_adv_ms := 0
var _inflight := false


func _init(r, p: Dictionary) -> void:
	rp = r
	battle = r.battle
	kind = str(p.get("kind", ""))
	match_id = str(p.get("id", ""))
	horizon = int(p.get("horizon", 0))
	ended = bool(p.get("ended", false))
	flip_ts = int(p.get("flip_ts", 0))
	srv_ref = int(p.get("srv_now", 0))
	ref_ms = int(p.get("t_ms", Time.get_ticks_msec()))
	key = str(p.get("key", ""))
	_last_adv_ms = Time.get_ticks_msec()


## 战斗场开局(`ReplayRecorder.start` 播放分支)取走挂着的会话。没有 / 过期 ⇒ null(照常回放)。
## 开播那一场如果此刻已经播完了(迟到太久)⇒ 记成看过、返回 null ⇒ 当回放放(带控件)。
static func take(r) -> RefCounted:
	if pending.is_empty():
		return null
	var p: Dictionary = pending
	pending = {}
	if Time.get_ticks_msec() - int(p.get("t_ms", 0)) > PENDING_TTL_MS:
		return null
	var me = new(r, p)
	if me.kind == KIND_PREMIERE:
		var tot: int = r.total_steps()
		if tot > 0:
			known_len[me.key] = tot
		if tot > 0 and me.target_step() >= tot:
			watched[me.key] = true
			return null
	if me.kind == KIND_LIVE:
		me._start_poll()
	return me


func tag() -> String:
	return TAG_PREMIERE if kind == KIND_PREMIERE else TAG_LIVE


# ─────────────────────────────── 每帧 ───────────────────────────────

## 只许跑到第几步(-1 = 不限: 开播 / 已经打完的直播, 录像是全的)。
func cap_step() -> int:
	if kind != KIND_LIVE or ended:
		return -1
	return horizon


## 现在该到第几步。
func target_step() -> int:
	if kind == KIND_PREMIERE:
		var el: float = float(srv_ref - flip_ts) + float(Time.get_ticks_msec() - ref_ms) / 1000.0
		return maxi(0, int(floor(el * 60.0)))
	return maxi(0, horizon - LAG_STEPS)


## 战斗场 `_process` → `ReplayRecorder.sim_feed(rd)` → 这里。返回喂给累加器的秒数。
## ★追帧 / 卡住时直接把累加器余量清零再喂「k 步 + 半步」: 恰好跑 k 步, 不多不少(累加器每帧上限 8 步)。
func feed(rd: float) -> float:
	_tick()
	var dt: float = battle.SIM_DT
	if broken or rp.finished or rp.diverged_at >= 0:
		battle._sim_accum = 0.0
		return 0.0
	var n: int = int(battle._sim_step_n)
	var tgt := target_step()
	var cap := cap_step()
	var left: int = (cap - n) if cap >= 0 else 1 << 30
	if catching and n >= tgt:
		catching = false
	elif not catching and n < tgt - CATCH_SLACK:
		catching = true
	if buffering and (cap < 0 or left >= RESUME_STEPS):
		buffering = false
	if not buffering and cap >= 0 and left <= 0:
		buffering = true
	var k := -1
	if buffering:
		k = 0
	elif catching or (str(battle._dl_state) == "place" and n < tgt):
		k = clampi(tgt - n, 1, CATCH_PER_FRAME)
	if k < 0:
		var would := int(floor((float(battle._sim_accum) + rd) / dt))
		if would <= left:
			_note_ahead(n + would, cap)
			return rd
		k = left
	k = clampi(k, 0, mini(left, CATCH_PER_FRAME))
	battle._sim_accum = 0.0
	_note_ahead(n + k, cap)
	return (float(k) + 0.5) * dt if k > 0 else 0.0


func _note_ahead(n_after: int, cap: int) -> void:
	if cap >= 0:
		max_ahead = maxi(max_ahead, n_after - cap)


## 每帧: 中断判定 + 屏上那句话。
func _tick() -> void:
	if broken:
		return
	if rp.finished:
		status = ""
		return
	if kind == KIND_LIVE and not ended:
		var lim: float = stale_sec_for_test if stale_sec_for_test > 0.0 else float(Board.LIVE_STALE_SEC)
		if float(Time.get_ticks_msec() - _last_adv_ms) > lim * 1000.0:
			_break(TXT_BROKEN)
			return
	if catching:
		status = TXT_SYNC
	elif waiting_next():
		status = TXT_WAIT
	elif buffering:
		status = TXT_SYNC
	else:
		status = ""


## 停在幕布 / 摆位上、打的人还没按下一路开打(已知事件都放完了)。
func waiting_next() -> bool:
	if kind != KIND_LIVE or ended:
		return false
	var st := str(battle._dl_state)
	if st == "fight" or st == "eggwindow" or st == "done" or st == "":
		return false
	return int(rp._ev_i) >= (rp.rec.get("events", []) as Array).size()


func _break(why: String) -> void:
	if broken:
		return
	broken = true
	broken_why = why
	status = why
	if battle._hud != null and battle._hud.has_method("show_live_broken"):
		battle._hud.show_live_broken(why)


## 播完(`ReplayRecorder.on_settle` 播放分支)。开播那一场: 记成看过 ⇒ 回到对阵图立刻揭晓。
func on_end() -> void:
	status = ""
	if kind == KIND_PREMIERE and key != "":
		watched[key] = true
		known_len[key] = int(battle._sim_step_n)


# ─────────────────────────────── 直播: 轮询 ───────────────────────────────

func _start_poll() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	var tm := Timer.new()
	tm.name = "LivePoll"
	tm.wait_time = POLL_SEC
	tm.autostart = true
	tm.process_mode = Node.PROCESS_MODE_ALWAYS
	tm.timeout.connect(poll)
	battle.add_child(tm)


func poll() -> void:
	if broken or ended or _inflight or kind != KIND_LIVE:
		return
	_inflight = true
	polls += 1
	if not SB.fetch_live_async(match_id, _on_polled):
		_inflight = false


func _on_polled(res: Dictionary) -> void:
	_inflight = false
	var err := str(res.get("err", ""))
	if err == "missing":
		_break(TXT_BROKEN)
		return
	if err != "":
		return                          # 网络抖一下: 不动, 中断由 LIVE_STALE_SEC 判
	var nr: Dictionary = decode_row(str(res.get("b64", "")), match_id)
	if nr.is_empty():
		return
	merge(nr, int(res.get("horizon", 0)), bool(res.get("ended", false)))


## 新拿到的一份录像并进正在播的那一份。★已经放过的事件必须一条不差(前缀相同), 否则就是另一场 ⇒ 中断。
func merge(nr: Dictionary, h: int, e: bool) -> void:
	if broken:
		return
	var old: Array = rp.rec.get("events", [])
	var ne: Array = nr.get("events", []) if nr.get("events", []) is Array else []
	if ne.size() < old.size():
		_break(TXT_BROKEN)
		return
	for i in range(old.size()):
		var a: Dictionary = old[i]
		var b: Dictionary = ne[i] if ne[i] is Dictionary else {}
		if int(a.get("s", -1)) != int(b.get("s", -2)) or str(a.get("k", "")) != str(b.get("k", "~")):
			_break(TXT_BROKEN)
			return
	rp.rec["events"] = ne
	if nr.get("cps", null) is Array:
		rp.rec["cps"] = nr["cps"]
	if e and nr.get("end", null) is Dictionary:
		rp.rec["end"] = nr["end"]
	merges += 1
	if h > horizon or (e and not ended):
		_last_adv_ms = Time.get_ticks_msec()
	horizon = maxi(horizon, h)
	ended = ended or (e and rp.rec.get("end", null) is Dictionary)


## base64 → 录像; 认出是这一场(id 对得上、有 events / cps)才要。
static func decode_row(b64: String, id: String) -> Dictionary:
	var raw: PackedByteArray = RF.decode_b64(b64)
	if raw.is_empty():
		return {}
	var r: Dictionary = ReplayRecorder.decode(raw)
	if r.is_empty() or str(r.get("id", "")) != id or not (r.get("events", null) is Array) \
			or not (r.get("cps", null) is Array):
		return {}
	return r


# ─────────────────────────────── 入口 ───────────────────────────────

## 赛况板点「观赛」。`done.call(code, msg)` 恰好一次(约定同 `ReplayFetcher.open`): code == "" ⇒ 已进战斗场。
static func open_live(tree: SceneTree, id: String, done: Callable, back: String = "", names: Dictionary = {}) -> void:
	if not SB.enabled():
		RF._reply(done, "no_backend", RF.message("no_backend"))
		return
	if not SB.fetch_live_async(id, func(res: Dictionary) -> void: _on_live_fetched(tree, id, res, done, back, names)):
		RF._reply(done, "corrupt", RF.message("corrupt"))


static func _on_live_fetched(tree: SceneTree, id: String, res: Dictionary, done: Callable,
		back: String, names: Dictionary) -> void:
	if not done.is_valid():
		return
	var why := str(res.get("err", ""))
	if why == "missing":
		RF._reply(done, "stale", TXT_BROKEN)
		return
	if why != "":
		RF._reply(done, why, RF.message(why, int(res.get("code", 0))))
		return
	var rec: Dictionary = decode_row(str(res.get("b64", "")), id)
	if rec.is_empty():
		RF._reply(done, "corrupt", RF.message("corrupt"))
		return
	## ★版本闸在挂会话之前: 版本不同就重算不出同一场(V6), 观赛说自己的那句话。
	if str(rec.get("client_version", "")) != ReplayRecorder.client_version() or int(rec.get("v", 0)) != ReplayRecorder.FORMAT_V:
		RF._reply(done, "version", TXT_VERSION)
		return
	var e := bool(res.get("ended", false)) and rec.get("end", null) is Dictionary
	if not e and Board.live_stale(Board.iso_to_unix(str(res.get("updated_at", ""))), P2C.now_utc()):
		RF._reply(done, "stale", TXT_BROKEN)
		return
	## 已经打完 ⇒ 就是一场回放(带控件), 不挂观赛会话。
	if not e:
		pending = {"kind": KIND_LIVE, "id": id, "horizon": int(res.get("horizon", 0)),
			"t_ms": Time.get_ticks_msec()}
	var w := ReplayRecorder.play(tree, rec, back, names)
	if w != "":
		pending = {}
		RF._reply(done, "unplayable", w)
		return
	RF._reply(done, "", "")




# ─────────────────────────────── 周日开播窗口(纯函数) ───────────────────────────────
## 对阵图一组(`SupabaseNet._bucket_from` 的形状)。

## 最近一次翻面的是第几轮(0 = 还没翻过)。没收盘: 当前轮的上一轮; 收盘: 最后一轮。
static func premiere_round(b: Dictionary) -> int:
	var rnd := int(b.get("round", 1))
	return rnd if bool(b.get("closed", false)) else rnd - 1


## 那一次翻面的时刻(服务端 unix 秒; 0 = 不知道 ⇒ 不开播、直接揭晓)。
##   有 `revealed_at`(服务端 20261007 迁移)⇒ 用它; 没有 ⇒ 没收盘时退回 `round_at`
##   (`finals_advance` 进下一轮那条 update 同时写 round_at, 它就是上一轮翻面的时刻); 收盘了就不知道。
static func flip_ts_of(b: Dictionary) -> int:
	var rv := int(b.get("revealed_at", 0))
	if rv > 0:
		return rv
	if bool(b.get("closed", false)):
		return 0
	return int(b.get("round_at", 0)) if premiere_round(b) >= 1 else 0


## 这一场的身份(组 / 翻面时刻 / 轮 / 场)。翻面时刻在里面 ⇒ 下周同一个坐标不会撞上本周看过的。
static func premiere_key(b: Dictionary, r: int, m: int) -> String:
	return "%d:%d:%d-%d" % [int(b.get("bucket", -1)), flip_ts_of(b), r, m]


## 开播窗口什么时候结束(翻面时刻 + 一场时长 + 缓冲)。一场时长不知道 ⇒ 用上限 PREMIERE_SEC。
static func premiere_end(flip: int, steps: int) -> int:
	if steps > 0:
		return flip + int(ceil(float(steps) / 60.0)) + PREMIERE_BUFFER
	return flip + PREMIERE_SEC


## ★判据中心: 这一场此刻是不是在开播窗口里(⇒ 不许显示胜负)。`now` = 服务端时钟。
##   只管「已翻面的那一轮」: 更早的轮一轮至少 8 分钟(`finals_round_sec`), 窗口早过了。
static func premiere_hidden(b: Dictionary, r: int, m: int, now: int) -> bool:
	if not (b.get("done", {}) as Dictionary).has("%d-%d" % [r, m]):
		return false
	if r < 1 or r != premiere_round(b):
		return false
	var ft := flip_ts_of(b)
	if ft <= 0 or now < ft:
		return false
	var k := premiere_key(b, r, m)
	if watched.has(k):
		return false
	return now < premiere_end(ft, int(known_len.get(k, 0)))


## 点「观赛」之前挂上的会话。`now` = 服务端此刻。
static func premiere_session(b: Dictionary, r: int, m: int, now: int) -> Dictionary:
	return {"kind": KIND_PREMIERE, "flip_ts": flip_ts_of(b), "srv_now": now,
		"t_ms": Time.get_ticks_msec(), "key": premiere_key(b, r, m)}
