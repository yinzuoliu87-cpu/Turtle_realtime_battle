extends RefCounted
## 逐帧直播 S5 · 「看服务器算的局」的唯一分流口(2026-10-19 · 方案书 docs/plans/20261019-服务器逐帧直播.md §4 接线 / §5 录像)。
## 用户 10-19「万一对不上？不能啊，一点概率都不能出现啊」「按云顶和lol的做法呢」「不行，周日也得改」。
##
## ══════════════════════════════════════════════════════════════════════
##  谁走这里
## ══════════════════════════════════════════════════════════════════════
##   周六闯关看自己那一场(referee_run → RefereeWatch.play_settled_route)/ 周日对阵图(自己那一场与别人的)/
##   赛况板「观看」/ 战绩页「观看」—— 它们原来都在拿到录像之后调 `ReplayRecorder.play`(本机重算),
##   现在一律先进 `route`:
##     开关关(`RefereeNet.stream_on()` 假: 没问到 / 服务端没上 20261019c / 本机版本低于 stream_version)
##       ⇒ **同步**调调用方给的 `legacy`(就是原来那一行 `ReplayRecorder.play`)——与改之前逐字一致。
##     开关开 ⇒ 问一次 end.json(`StreamSource.probe`):
##       200 有流         ⇒ 播状态流(`ReplayRecorder.mode == "stream"`, 手机一步 sim 都不跑)
##       404 没有这份流   ⇒ 服务器裁判局(`known`: 调用方确知, 或 `matches.result.referee` / `finals_replay` 回的 referee)
##                          ⇒ 请求补流(`referee_request_restream`, 裁判机按原快照 + 种子重算一遍只录流), 进场显示「画面生成中」,
##                            块按 404 退避等着(`RESTREAM_GIVEUP_SEC` 内没出来 ⇒「画面无法播放」); 补流请求被拒 / 服务端没部署 ⇒ 不播,
##                            说「画面无法播放」。★裁判局永不本机重算(2026-10-20)。
##                          不是裁判局(积分赛本机局: 那一行没有 referee 标记)⇒ 老路(本机重算)
##       426 版本过旧     ⇒ 交给版本墙, 不播
##       网络问题        ⇒ 不播, 说网络那句话 —— ★不许当成 404 去走本机重算
##   ★录像(matches.replay)照样先取: 它给出种子(选同一张地图)、开局状态(幕布上的阵容)、版本号(版本闸)、
##     确认「是这一场」; 但**不再拿它重算**。方案书 §5:「matches.replay 照常保留, 相当于 LoL 的 SNR」。
##
## ══════════════════════════════════════════════════════════════════════
##  进场之后
## ══════════════════════════════════════════════════════════════════════
##   · GameState 照回放那样备份 → 写入录像的开局状态 → 离场还原(`ReplayRecorder.begin_play` / `end_play`);
##     战斗场 `_exit_tree` 只在 play 模式调 `end_play`, 所以由本模块的守卫节点(Guard)在 stream 模式的战斗场离树时调。
##   · `current`: 这一场的会话(kind = referee / premiere / replay、服务器结果 `result`、match_id)—— 收尾屏(HUD)读它。
##   · 周日开播窗口(premiere): 迟到的人从「翻面至今」那一步看(LoL 观战: 跳到最近的 keyframe 再往后放)。
##     守卫先让播放器停着, 拉到够用的块之后 `seek` 过去再放。开播窗口已经过了 ⇒ 当回放从头放。
##   · 回放 / 观赛(memory fb-spectate-is-not-replay): 只有 kind = replay(已打完、结果公开)给操作条(暂停 / 倍速 / 进度条拖动,
##     `controls_for`); 观赛(live 正在算 / referee 周六自己那一场 / premiere 周日开播)只有「退出」。
##   · 周六「观赛」正在算的裁判局(`open_live`, 20261020 迁移 `referee_live_gauntlet`): 边算边播(块没到就「同步中」等, 永不判没有)。
##     那一场还没有录像(matches 里没有这一行), 种子 / 名字 / 版本取自列表那一行; 没有阵容 ⇒ 不建换路幕布(`no_curtain`)。

const RN := preload("res://scripts/net/referee_net.gd")
const SB := preload("res://scripts/net/supabase.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
const BE := preload("res://scripts/net/backend.gd")
const NR := preload("res://scripts/net/net_route.gd")
## 运行期才 load(不 preload): replay_fetcher / live_spectate 都 preload 本文件, 反过来再 preload 就成环。
const RF_PATH := "res://scripts/systems/replay/replay_fetcher.gd"
const LS_PATH := "res://scripts/systems/replay/live_spectate.gd"

## 裁判机上的 Caddy(server/stream/README.md)。环境变量 TURTLE_STREAM_BASE 可改(门禁指到本进程起的 HTTP 服务)。
## ★没设环境变量时跟 API 走同一条入口(net_route.gd `stream_base`: 走中转 ⇒ 中转/streams, 2026-10-20 大陆中转)。
## ★直连地址读设置 `turtle/stream_base`(默认 = 下面这个常量, 逐字等于原来的写死值); 内测服包读
##   `turtle/stream_base.beta_server` = `…/beta/streams`(方案书 20261020-内测服.md §4.4, 取值走 NR.stream_direct)。
const BASE := NR.STREAM_DIRECT
const ENV_BASE := "TURTLE_STREAM_BASE"

const KIND_REFEREE := "referee"
const KIND_PREMIERE := "premiere"
const KIND_REPLAY := "replay"
const KIND_LIVE := "live"
## 屏上的字(短、名词化; 不拟人)。
const TXT_UPDATE := "版本过旧，请更新"
const TXT_GENERATING := "画面生成中"
## 补流: 等第一块等多久就算没有(墙钟秒)。= 裁判机一局的墙钟上限(轮询器 JOB_TIMEOUT_SEC 默认 600)。
const RESTREAM_GIVEUP_SEC := 600.0
## 补流请求服务端回了这些状态才进场等(failed = 补过而且失败了 ⇒ 不等)。
const RESTREAM_WAIT := ["pending", "claimed", "done"]
## 守卫等战斗场出现的时限(换场景没成就别把 GameState 一直留在回放那一份上)。
const GUARD_TTL_MS := 30000

## 这一场(进了战斗场、还没离场)的会话; 没有 = {}。
static var current: Dictionary = {}
## 观测量(门禁分母)
static var routes := 0
static var legacy_calls := 0
static var probes := 0
static var enters := 0
static var probe_codes: Array = []
static var restreams := 0
static var live_enters := 0


static func base_url() -> String:
	var e := OS.get_environment(ENV_BASE).strip_edges()
	return e if e != "" else NR.stream_base()


static func wanted() -> bool:
	return RN.stream_on()


## 这一种会话给不给回放操作条(暂停 / 倍速 / 进度条)。只有已打完的回放给; 观赛三种(正在算 / 周六自己那一场 / 周日开播)不给。
static func controls_for(kind: String) -> bool:
	return kind == KIND_REPLAY


## ★唯一分流口。`legacy.call() -> String` = 原来那一行(`ReplayRecorder.play`, 返回 "" 已进场 / 否则原因);
##   `done.call(code: String, msg: String)` 恰好一次(约定同 `ReplayFetcher.open`): code == "" ⇒ 已进战斗场。
##   `known` = 调用方确知这是服务器裁判局(没有流就不播, 也不重算)。`sess` 并进 `current`(kind / result …)。
static func route(tree: SceneTree, rec: Dictionary, back: String, names: Dictionary, known: bool,
		legacy: Callable, done: Callable, sess: Dictionary = {}) -> void:
	routes += 1
	if not wanted():
		legacy_calls += 1
		var w: String = legacy.call()
		load(RF_PATH)._reply(done, "" if w == "" else "unplayable", w)
		return
	## 版本闸与回放同一句话(V6): 不同版本的流格式也不同(R7), 拉下来也播不了
	var why := check(rec)
	if why != "":
		load(RF_PATH)._reply(done, "unplayable", why)
		return
	var id := str(rec.get("id", ""))
	probes += 1
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	StreamSource.probe(base_url(), id, ver,
		func(code: int) -> void: _on_probe(code, tree, rec, back, names, known, legacy, done, sess))


static func _on_probe(code: int, tree: SceneTree, rec: Dictionary, back: String, names: Dictionary, known: bool,
		legacy: Callable, done: Callable, sess: Dictionary) -> void:
	probe_codes.append(code)
	if not done.is_valid():
		return                          # 人已经走了: 不回调、不播
	match code:
		200:
			var w2 := enter(tree, rec, back, names, sess)
			load(RF_PATH)._reply(done, "" if w2 == "" else "unplayable", w2)
		404:
			if known:
				_restream(tree, rec, back, names, done, sess)   # ★裁判局: 补流等画面, 永不本机重算
			else:
				legacy_calls += 1
				var w3: String = legacy.call()
				load(RF_PATH)._reply(done, "" if w3 == "" else "unplayable", w3)
		426:
			SB._note_update_signal({"code": 426})
			load(RF_PATH)._reply(done, "update_required", TXT_UPDATE)
		_:
			load(RF_PATH)._reply(done, "offline", load(RF_PATH).message("offline"))


## 与 `ReplayRecorder.play` 同一套闸、同一句话。
static func check(rec: Dictionary) -> String:
	return ReplayRecorder.play_check(rec)


## 裁判局没有流(开流之前算的 / 录流失败过): 请求服务器补流, 排上了就进场等画面(「画面生成中」), 没排上就说「画面无法播放」。
static func _restream(tree: SceneTree, rec: Dictionary, back: String, names: Dictionary, done: Callable, sess: Dictionary) -> void:
	restreams += 1
	var id := str(rec.get("id", ""))
	var cb := func(res: Dictionary) -> void:
		if not done.is_valid():
			return
		var err := str(res.get("err", ""))
		if err == "" and str(res.get("status", "")) in RESTREAM_WAIT:
			var w := enter(tree, rec, back, names, sess, true)
			load(RF_PATH)._reply(done, "" if w == "" else "unplayable", w)
		elif err == "offline" or err == "timeout" or err == "no_token":
			load(RF_PATH)._reply(done, "offline", load(RF_PATH).message("offline"))
		else:
			load(RF_PATH)._reply(done, "no_stream", StreamPlayer.TXT_ERROR)
	if not RN.request_restream_async(id, cb):
		load(RF_PATH)._reply(done, "no_stream", StreamPlayer.TXT_ERROR)


## 进战斗场播状态流。返回 "" = 已进场(tree 为 null 时只挂好待播, 门禁自己实例化战斗场)。
##   `restream` = 刚请求了补流: 块还没生成 ⇒ 屏上「画面生成中」, 404 等到 RESTREAM_GIVEUP_SEC 才算没有。
static func enter(tree: SceneTree, rec: Dictionary, back: String, names: Dictionary, sess: Dictionary = {},
		restream: bool = false) -> String:
	var why := check(rec)
	if why != "":
		return why
	var id := str(rec.get("id", ""))
	var so := {"finished": true}
	if restream:
		so["giveup_sec"] = RESTREAM_GIVEUP_SEC
	var src := StreamSource.Http.new(base_url(), id, so)
	src.on_update_required = func() -> void: SB._note_update_signal({"code": 426})
	## 周日开播: 对阵图在取录像之前挂的观赛会话(重算那条路由 `Live.take` 取走)⇒ 改由守卫按它跳转
	var s := sess.duplicate(true)
	var ls = load(LS_PATH)
	var lp: Dictionary = ls.pending
	if not lp.is_empty():
		if str(lp.get("kind", "")) == KIND_PREMIERE and not s.has("kind"):
			s["kind"] = KIND_PREMIERE
			s["premiere"] = lp.duplicate()
		ls.pending = {}                 # 别留给下一场不相干的回放
	if not s.has("kind"):
		s["kind"] = KIND_REPLAY
	s["id"] = id
	s["t_ms"] = Time.get_ticks_msec()
	if restream:
		s["restream"] = true
	ReplayRecorder.return_scene = back
	ReplayRecorder.play_names = names.duplicate()
	ReplayRecorder.viewer_name = BE.player_display_name()
	ReplayRecorder.begin_play(rec)
	ReplayRecorder.pending_play = {}    # ★begin_play 挂的是「重算」待播; 这里只要它的备份 / 写状态那一半
	var fights: Array = []
	for e in rec.get("events", []):
		if e is Dictionary and str((e as Dictionary).get("k", "")) == "fight":
			fights.append(int((e as Dictionary).get("s", 0)))
	StreamPlayer.pending = {"source": src, "seed": int(rec.get("seed", 0)), "controls": controls_for(str(s["kind"])),
		"speed": ReplayRecorder._pref_speed if controls_for(str(s["kind"])) else 1.0,
		"wait_text": TXT_GENERATING if restream else "", "fights": fights,
		"total": int((rec.get("end", {}) as Dictionary).get("s", -1)) if rec.get("end", null) is Dictionary else -1}
	current = s
	enters += 1
	_guard(tree)
	if tree != null:
		tree.change_scene_to_file(ReplayRecorder.BATTLE_SCENE)
	return ""


# ─────────────────────────────── 周六观赛: 正在算的裁判局 ───────────────────────────────

## 赛况板「观赛」点了正在算的裁判局(`referee_live_gauntlet` 那一行, gauntlet_board.live_games 的形状 + referee / seed)。
##   `done.call(code, msg)` 恰好一次(同步): "" = 已进场。观赛: 没有操作条; 块没到 ⇒「同步中」一直等(服务器还在算, 不判没有)。
static func open_live(tree: SceneTree, g: Dictionary, done: Callable, back: String = "", names: Dictionary = {}) -> void:
	var w := enter_live(tree, g, back, names)
	load(RF_PATH)._reply(done, "" if w == "" else ("version" if w == load(LS_PATH).TXT_VERSION else "unplayable"), w)


## 返回 "" = 已进场(tree 为 null 时只挂好待播)。
static func enter_live(tree: SceneTree, g: Dictionary, back: String, names: Dictionary) -> String:
	if not wanted():
		return StreamPlayer.TXT_ERROR
	if str(g.get("ver", "")) != ReplayRecorder.client_version():
		return load(LS_PATH).TXT_VERSION     # 流格式绑版本(R7): 版本不同拉下来也播不了
	var id := str(g.get("id", ""))
	if not SB.is_uuid(id) or int(g.get("seed", 0)) <= 0:
		return StreamPlayer.TXT_ERROR
	var src := StreamSource.Http.new(base_url(), id, {"finished": false})
	src.on_update_required = func() -> void: SB._note_update_signal({"code": 426})
	load(LS_PATH).pending = {}
	ReplayRecorder.return_scene = back
	ReplayRecorder.play_names = names.duplicate()
	ReplayRecorder.viewer_name = BE.player_display_name()
	## 这一场还没有录像: 只把 GameState 备份起来、存盘空转(离场还原), 开局状态只给「双路」这一项 —— 阵容不知道, 不建换路幕布
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	StreamPlayer.pending = {"source": src, "seed": int(g["seed"]), "controls": controls_for(KIND_LIVE), "no_curtain": true}
	current = {"kind": KIND_LIVE, "id": id, "t_ms": Time.get_ticks_msec()}
	enters += 1
	live_enters += 1
	_guard(tree)
	if tree != null:
		tree.change_scene_to_file(ReplayRecorder.BATTLE_SCENE)
	return ""


# ─────────────────────────────── 守卫 ───────────────────────────────

static func _guard(tree: SceneTree) -> void:
	var t: SceneTree = tree if tree != null else Engine.get_main_loop() as SceneTree
	if t == null or t.root == null:
		return
	for c in t.root.get_children():
		if c is Guard:
			(c as Guard).retire()       # 上一场的守卫(换场景还没走完): 交给这一场的
	var g := Guard.new()
	g.name = "StreamWatchGuard"
	g.sess = current
	g.left = _left
	t.root.add_child.call_deferred(g)


## 播放模式的战斗场离树(或者一直没等到它)⇒ 还原 GameState、清会话; 开播那一场看完了 ⇒ 对阵图立刻揭晓(同 `Live.on_end`)。
static func _left(player, sess: Dictionary) -> void:
	if player != null and str(sess.get("kind", "")) == KIND_PREMIERE and str(player.state) == "ended":
		var key := str((sess.get("premiere", {}) as Dictionary).get("key", ""))
		if key != "":
			var ls = load(LS_PATH)
			ls.watched[key] = true
			ls.known_len[key] = int(player.applied)
	ReplayRecorder.end_play()
	if is_same(current, sess) or str(current.get("id", "")) == str(sess.get("id", "")):
		current = {}


## 开播: 现在该到第几步(与 `live_spectate.target_step` 同一个口径: 翻面至今 × 60)。
static func premiere_target(p: Dictionary) -> int:
	var el: float = float(int(p.get("srv_now", 0)) - int(p.get("flip_ts", 0))) \
		+ float(Time.get_ticks_msec() - int(p.get("t_ms", 0))) / 1000.0
	return maxi(0, int(floor(el * 60.0)))


class Guard extends Node:
	var sess: Dictionary = {}
	var left: Callable = Callable()
	var battle: Node = null
	var player = null
	var t0 := 0
	var _prem_pending := false
	var _done := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		t0 = Time.get_ticks_msec()

	func retire() -> void:
		## 新的一场接手之前, 上一场还没出现战斗场的守卫不再等(备份由同一个 begin_play / end_play 管, 不重复还原)
		_done = true
		queue_free()

	func _process(_dt: float) -> void:
		if _done:
			return
		if battle == null:
			var cs := get_tree().current_scene
			if cs != null and cs.get("_replay") != null and cs._replay.player != null:
				battle = cs
				player = cs._replay.player
				battle.tree_exiting.connect(_on_exit)
				if str(sess.get("kind", "")) == "premiere":
					_prem_pending = true
					player.paused = true
			elif Time.get_ticks_msec() - t0 > GUARD_TTL_MS:
				_finish(null)
			return
		if _prem_pending:
			_premiere_step()

	## 开播迟到入场: 块拉到目标步之后跳过去; 目标已过全场 ⇒ 从头当回放放。
	func _premiere_step() -> void:
		var p: Dictionary = sess.get("premiere", {})
		var tgt: int = (load("res://scripts/systems/replay/stream_watch.gd") as GDScript).premiere_target(p)
		var src = player.src
		if src == null or str(player.state) == "error":
			_prem_pending = false
			player.paused = false
			return
		var last := int((src.end_meta() as Dictionary).get("last_step", -1)) if src.ended() else -1
		if last >= 0 and tgt >= last:
			_prem_pending = false
			player.paused = false
			return
		if int(player.first_step) < 0:
			return
		var have: int = int(player.first_step) + int(src.available()) * F.CHUNK_STEPS
		if tgt <= int(player.first_step) + F.CHUNK_STEPS:
			_prem_pending = false
			player.paused = false
		elif have > tgt + F.CHUNK_STEPS or src.ended():
			player.seek(tgt)
			_prem_pending = false
			player.paused = false

	func _on_exit() -> void:
		_finish(player)

	func _finish(p) -> void:
		if _done:
			return
		_done = true
		if left.is_valid():
			left.call(p, sess)
		queue_free()
