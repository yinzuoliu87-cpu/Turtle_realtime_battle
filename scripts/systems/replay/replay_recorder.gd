class_name ReplayRecorder
extends RefCounted
## 对局回放 —— **录「重算这一局所需的全部输入」, 播 = 本机重算**(不是录像)。
## 方案书: docs/plans/20261003-跨设备回放.md §4(S1 本机录、本机播)。
##
## ══════════════════════════════════════════════════════════════════════
##  一份记录装什么
## ══════════════════════════════════════════════════════════════════════
##   v / client_version    格式版本 / `config/version`(播放前比, 不等就不播 —— §4.4)
##   seed                  `_battle_rng` 的种子(已经 `GameState.note_battle_seed` 规范化)
##   state                 开局那一刻 GameState 的**全部**脚本变量(去掉 STATE_DENY 里那几个)
##                         ★不列白名单: 白名单天生会漏(memory fb-recursive-scan-not-structured-walk)。
##                           漏没漏由门禁 V3 量: 播之前把 GameState 改成另一份, 结果仍须一致。
##   events                局内【改结果的】人为输入, 按 sim 步号:
##                           fight     开打(带那一刻双方全部单位的站位)
##                           present   点掉呈现幕布(它决定下一路在哪一步建场)
##                           surrender 认输
##                         ★训龟大师移动/施法**没有**: 母方案书 U2 已把大师改成不由人操控。
##   cps                   每 CP_EVERY 个 sim 步一个指纹摘要(校验点)
##   end                   结算那一刻的步号 + 指纹
##
## ★编码用 `var_to_bytes`(二进制, 逐位精确), 不用 JSON:
##   探针实测 `JSON.from_native` 把 0.30000000000000004 存成 "f:0.3",
##   `var_to_str` 也有回不去的值(123456789.12345679)。站位差一个末位, 第一步就分叉。
##
## ══════════════════════════════════════════════════════════════════════
##  时序约定(录与播必须对齐的唯一一件事)
## ══════════════════════════════════════════════════════════════════════
## 事件按「发生时 `_sim_step_n` 的值」记步号 S。人的输入都发生在两个 sim 步之间 ⇒
## 播放时在**第 S+1 步开头**(`pre_step`, `_sim_step_n` 仍是 S)重放 —— 同一个相对位置。
## 发生在 sim 步**里面**的(DL_AUTOFIGHT 等开发路径会在呈现推进里直接开打)记 `i=true`,
## 播放时不在 pre_step 里发, 而是等那条代码路径自己走到时放行(`allow_input`)。

const Phase2Cfg := preload("res://scripts/gamedata/phase2_config.gd")
const FORMAT_V := 1
const CP_EVERY := 60                       # 每 60 sim 步(=1 游戏秒)一个校验点
const PLACE_CP := "place"                  # 摆位期的校验点占位(见 _checkpoint)
const SAVE_DIR := "user://replays/"
const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
## 不进记录的 GameState 变量。★只放【与对局无关且不该外传】的 —— 每加一个都要想清楚
##   "战斗场读不读它"; 读的话 V3(篡改法)会红。
const STATE_DENY := ["test_mode", "auth_refresh", "account_email", "install_uid", "cloud_rev",
	"match_history", "finals_report_pending", "replay_pending_id",
	## S2 上传队列: 不进记录(否则每份录像都背着前几份的单子), 播放时也不许被记录覆盖(V5)。
	"replay_upload_pending"]
const Uploader := preload("res://scripts/systems/replay/replay_uploader.gd")

## 待播的那一份: 播放入口写、战斗场 `_ready` 里 `start()` 读走。
static var pending_play: Dictionary = {}
## 播放前 GameState 的整份备份(退出回放时还原)。静态: 要活过换场景。
static var _backup: Dictionary = {}
static var _backup_test_mode := false
static var _has_backup := false

var battle
var mode := ""                 # "rec" 录 / "play" 播 / "" 都不是
var rec: Dictionary = {}
var _ev_i := 0                 # 播放: 下一条待发事件下标
var _firing := false           # 播放: 正在由本模块自己触发事件(放行 allow_input)
var _in_step := false          # 现在是不是在某个 sim 步里面
var diverged_at := -1          # 播放: 第一个对不上的步号(-1 = 一直对得上)
var diverge_why := ""
var cp_checked := 0            # 播放: 已比对的校验点数(门禁的分母)
var finished := false
var _ui_built := false


func _init(b) -> void:
	battle = b


# ─────────────────────────────── 开局 ───────────────────────────────

## 战斗场 `_ready` 里、种子已登记之后、建单位之前调。
func start() -> void:
	if not battle.sim_stepped.is_connected(post_step):
		battle.sim_stepped.connect(post_step)   # ★最先连上 ⇒ 每步末尾第一个跑(先于任何协程)
	if not pending_play.is_empty():
		mode = "play"
		rec = pending_play
		pending_play = {}
		## ★种子从记录进来(方案书 §4.5 第 2 条 / B5 前半)。此刻 `_build_camera` 刚 `randomize()` 过、
		##   `note_battle_seed` 刚登记过, 还没有任何人从 `_battle_rng` 取过数 ⇒ 这里覆盖等价于开局就是它。
		##   (录制那边 `seed = note_battle_seed(seed)` 同样是「重设 seed ⇒ 状态归位」, 两边起点一致。)
		battle._battle_rng.seed = GameState.note_battle_seed(int(rec.get("seed", 0)))
		return
	if should_record():
		mode = "rec"
		rec = {
			"v": FORMAT_V,
			"client_version": client_version(),
			"seed": int(battle._battle_rng.seed),
			"state": capture_state(),
			"events": [],
			"cps": [],
		}


## 这一局录不录。Q3(用户授权按推荐): **先只录周六闯关赛**。
static func should_record() -> bool:
	if GameState == null or not bool(GameState.dual_active) or bool(GameState.get("tutorial_active")):
		return false
	var ph := str(GameState.week_phase)
	return Phase2Cfg.settle_kind(ph, Phase2Cfg.phase_mode_live(ph)) == Phase2Cfg.SETTLE_GAUNTLET


static func client_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func is_playing() -> bool:
	return mode == "play"


## 播放时 sim 推进倍率: 摆位阶段快进(那段只是录制者在想怎么摆, 对局结果与它无关 ——
## 步数照样一步不少地跑, 只是一帧多跑几步; 协程/补间都已挂在 sim 步上, 一帧几步不改结果)。
func time_mult() -> float:
	if mode == "play" and str(battle._dl_state) == "place":
		return 8.0
	return 1.0


# ─────────────────────────────── 每步 ───────────────────────────────

## `_sim_step` 第一行调(此刻 `_sim_step_n` 还是上一步的号 S)。
## 返回 true = 这一步之前重放了人的输入 ⇒ 调用方要重新取 frozen/in_ts:
##   录制时人是在两帧之间按的(例如「开打」会 `_add_hitstop(0.18)`), 下一步开头取 frozen 时已经看得到;
##   而播放时输入是在 `_sim_step` 里面才重放的, 那时 frozen 已经按旧值传进来了 ⇒ 不重取就差一步。
func pre_step() -> bool:
	_in_step = true
	if mode == "":
		return false
	var s: int = int(battle._sim_step_n)
	if mode == "play" and not _ui_built:
		_ui_built = true
		if battle._hud != null and battle._hud.has_method("build_replay_bar"):
			battle._hud.build_replay_bar()
	## ★先重放输入、再取校验点: 录制时人的输入发生在两步之间, 下一步开头取校验点时已经生效了。
	var fired := false
	if mode == "play" and diverged_at < 0:
		fired = _fire_due(s)
	if s > 0 and s % CP_EVERY == 0 and diverged_at < 0:
		_checkpoint(s)
		## 录制那一局在第 E 步就结算了, 本机却还在打 ⇒ 结局已经不同(例如漏了一条认输)。
		var end_s: int = int((rec.get("end", {}) as Dictionary).get("s", -1))
		if end_s >= 0 and s > end_s and not finished and diverged_at < 0:
			_diverge(s, "录制那一局在第 %d 步已经结束, 本机还没结束" % end_s)
	return fired


## `_sim_step` 末尾(sim_stepped 信号)调。
func post_step() -> void:
	_in_step = false


func _checkpoint(s: int) -> void:
	## ★摆位屏上的站位是**人还在拖**的中间态(录制方拖了几下, 播放方只在开打那一刻一次写回),
	##   它不进对局 —— 开打那一刻的站位由 fight 事件逐个比对(`_apply_positions`)。
	##   ⇒ 摆位期的校验点记成占位, 两边都不比。
	var h := PLACE_CP if str(battle._dl_state) == "place" else digest(battle)
	if mode == "rec":
		(rec["cps"] as Array).append(h)
		return
	var idx: int = s / CP_EVERY - 1
	var cps: Array = rec.get("cps", [])
	if idx >= cps.size():
		return              # 录制那一局在这之前就结束了; 结束点由 on_settle 比
	if h == PLACE_CP or str(cps[idx]) == PLACE_CP:
		if h != str(cps[idx]):
			_diverge(s, "校验点 %d: 一边在摆位一边不在" % idx)
		return
	cp_checked += 1
	if str(cps[idx]) != h:
		_diverge(s, "校验点 %d 对不上" % idx)


func _fire_due(s: int) -> bool:
	var fired := false
	var evs: Array = rec.get("events", [])
	while _ev_i < evs.size():
		var e: Dictionary = evs[_ev_i]
		var es: int = int(e.get("s", -1))
		if es < s:
			_diverge(s, "事件 %s(第 %d 步)没有发生" % [str(e.get("k", "?")), es])
			return fired
		if es > s or bool(e.get("i", false)):
			return fired
		_firing = true
		fired = true
		match str(e.get("k", "")):
			"fight": battle._dl_sys._dl_start_fight()
			"present": battle._dl_sys._dl_present_click()
			"surrender": battle._do_surrender()
		_firing = false
		if _ev_i < evs.size() and is_same(evs[_ev_i], e):
			_diverge(s, "事件 %s 在本机没能发生" % str(e.get("k", "?")))
			return fired
	return fired


## 改结果的人为输入进门之前问一声。
##   录: 记下来, 放行。  播: 只放行"本模块自己在发"或"录制时也是在步内这一刻发生"的那一条。
func allow_input(kind: String) -> bool:
	if mode == "rec":
		var e := {"s": int(battle._sim_step_n), "k": kind, "i": _in_step}
		if kind == "fight":
			e["p"] = positions(battle)
		(rec["events"] as Array).append(e)
		return true
	if mode != "play":
		return true
	var evs: Array = rec.get("events", [])
	if _ev_i >= evs.size() or diverged_at >= 0:
		return false
	var e2: Dictionary = evs[_ev_i]
	if str(e2.get("k", "")) != kind or int(e2.get("s", -1)) != int(battle._sim_step_n):
		return false
	if not _firing and not (bool(e2.get("i", false)) and _in_step):
		return false
	_ev_i += 1
	if kind == "fight" and not _apply_positions(e2.get("p", [])):
		_diverge(int(battle._sim_step_n), "开打时场上单位与录制时不同")
		return false
	return true


# ─────────────────────────────── 结束 ───────────────────────────────

## `_settle_season` 第一行调。返回 true = 这是回放, 结算一律跳过(V5 零副作用)。
func on_settle(won: bool) -> bool:
	if mode == "rec" and not finished:
		finished = true
		rec["end"] = {"s": int(battle._sim_step_n), "h": digest(battle), "won": won}
		var id := save_record(rec)
		if id != "" and GameState != null:
			GameState.replay_pending_id = id      # record_match 那一刻挂到战绩行上
			Uploader.enqueue(id)                  # S2: 先进落盘队列再发; 回读确认才销单
		return false
	if mode == "play":
		if not finished:
			finished = true
			var end: Dictionary = rec.get("end", {})
			if diverged_at < 0 and (int(end.get("s", -1)) != int(battle._sim_step_n) \
					or str(end.get("h", "")) != digest(battle) or bool(end.get("won", not won)) != won):
				_diverge(int(battle._sim_step_n), "终局对不上")
		return true
	return false


func _diverge(s: int, why: String) -> void:
	if diverged_at >= 0:
		return
	diverged_at = s
	diverge_why = why
	push_warning("[Replay] 第 %d 步: %s —— 停止播放" % [s, why])
	battle.set_process(false)          # Q7: 对不上就停, 不许默默播一场错的
	if battle._hud != null and battle._hud.has_method("show_replay_mismatch"):
		battle._hud.show_replay_mismatch()


# ─────────────────────────────── 站位 ───────────────────────────────

static func positions(b) -> Array:
	var out: Array = []
	for u in b._units:
		out.append([str(u.get("id", "")), str(u.get("side", "")), u.get("pos", Vector2.ZERO)])
	return out


func _apply_positions(ps: Array) -> bool:
	if ps.size() != battle._units.size():
		return false
	for i in range(ps.size()):
		var u: Dictionary = battle._units[i]
		var p: Array = ps[i]
		if str(p[0]) != str(u.get("id", "")) or str(p[1]) != str(u.get("side", "")):
			return false
		u["pos"] = p[2]
	return true


# ─────────────────────────────── 指纹 ───────────────────────────────

## 全场对局状态(与 verify_determinism_b 同一组字段: 不含纯演出)。
static func fingerprint(b) -> String:
	var parts: Array = ["t=%.4f" % float(b._t), str(b._dl_state)]
	var i := 0
	for u in b._units:
		var p: Vector2 = u.get("pos", Vector2())
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.2f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)), p.x, p.y,
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)), float(u.get("energy", 0.0))])
		i += 1
	return "|".join(parts)


static func digest(b) -> String:
	return fingerprint(b).md5_text().substr(0, 16)


# ─────────────────────────────── GameState ───────────────────────────────

static func capture_state() -> Dictionary:
	var out := {}
	if GameState == null:
		return out
	for p in GameState.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p.get("name", ""))
		if n in STATE_DENY:
			continue
		var v = GameState.get(n)
		if not _plain(v):
			continue
		out[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


static func apply_state(st: Dictionary) -> void:
	for n in st:
		var v = st[n]
		GameState.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)


static func _plain(v) -> bool:
	match typeof(v):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for x in v:
				if not _plain(x): return false
		TYPE_DICTIONARY:
			for k in v:
				if not _plain(k) or not _plain(v[k]): return false
	return true


# ─────────────────────────────── 存取 ───────────────────────────────

static func encode(r: Dictionary) -> PackedByteArray:
	return var_to_bytes(r).compress(FileAccess.COMPRESSION_DEFLATE)


static func decode(b: PackedByteArray) -> Dictionary:
	var raw := b.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	var v = bytes_to_var(raw)
	return v if v is Dictionary else {}


## 存本地 user://replays/<id>.rpl, 返回 id("" = 没存成)。上传(S2)见 `replay_uploader.gd`。
static func save_record(r: Dictionary) -> String:
	var id := new_id()
	r["id"] = id
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR + id + ".rpl", FileAccess.WRITE)
	if f == null:
		push_warning("[Replay] 存不了 " + SAVE_DIR + id)
		return ""
	f.store_buffer(encode(r))
	f.close()
	return id


static func load_record(id: String) -> Dictionary:
	var f := FileAccess.open(SAVE_DIR + id + ".rpl", FileAccess.READ)
	if f == null:
		return {}
	var b := f.get_buffer(f.get_length())
	f.close()
	return decode(b)


## uuid v4 —— S2 起它同时是服务端 `matches.match_id`(uuid 列), 本地文件名与战绩行 `replay_id` 也是它,
##   S3 按它去服务端取那一行。
static func new_id() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


# ─────────────────────────────── 播放入口 ───────────────────────────────

## 播一份记录。返回 "" = 已进战斗场; 否则是不能播的原因(V6: 版本不同就不进战斗场)。
static func play(tree: SceneTree, r: Dictionary) -> String:
	if r.is_empty():
		return "回放记录读不出来"
	if str(r.get("client_version", "")) != client_version():
		return "这场比赛是旧版本(%s)打的, 当前版本(%s)播不了" % [str(r.get("client_version", "?")), client_version()]
	if int(r.get("v", 0)) != FORMAT_V:
		return "回放格式不认识"
	begin_play(r)
	if tree != null:
		tree.change_scene_to_file(BATTLE_SCENE)
	return ""


## 只做「备份 GameState → 写入记录 → 挂上待播」, 不换场景(门禁直接实例化战斗场用)。
static func begin_play(r: Dictionary) -> void:
	if not _has_backup:
		_backup = capture_state()
		_backup_test_mode = bool(GameState.test_mode)
		_has_backup = true
	GameState.test_mode = true          # 回放期间任何 save() 都空转(V5)
	apply_state(r.get("state", {}))
	pending_play = r


## 退出回放(战斗场离树时一定会调): GameState 还原成播之前那一份。
static func end_play() -> void:
	pending_play = {}
	if not _has_backup:
		return
	apply_state(_backup)
	GameState.test_mode = _backup_test_mode
	_backup = {}
	_has_backup = false
