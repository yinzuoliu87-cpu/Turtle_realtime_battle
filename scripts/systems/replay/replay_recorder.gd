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
##   state                 开局那一刻 GameState 里**重放这一场真正要的**那几个变量(`STATE_KEYS`, 2026-10-04 瘦身)
##                         ★这张表不是凭印象列的, 是**量**出来的(方案书 §9.5):
##                           ① 量「回放那一遍实际读了 GameState 的哪些变量」(运行时给每个变量补 getter 记读,
##                              `tests/_gs_read_trace.gd` + `tests/_probe_replay_gs_reads.gd`, 4 种阵容并集 24 个)
##                              + 静态扫战斗侧 `GameState.<变量>` 补上没走到的读者(gambler_wheel_stacks);
##                           ② 对这 25 个逐个变异(`tests/_probe_replay_field_mut.gd`): 录像里拿掉 F、本机 F 换成
##                              另一台设备的值 ⇒ 分叉的进表, 不分叉的不进。
##                         门禁(`verify_replay_roundtrip` V3): 播之前把**所有**不在表里的变量都换成另一份, 仍逐步一致;
##                           录像里不许出现表外的键(币/邮箱/账号/背包/装备池……), 配分母断言。
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
## ★录像里装的 GameState 变量 —— **全部**(`capture_state` 只取这些)。每一个都写了「怎么量出来的」:
##   「必需」= 逐字段变异实测: 录像里拿掉它、本机换成另一台设备的值 ⇒ 重放分叉(分叉步号在括号里)。
##   ⚠ 「不分叉」不等于「没用」: incense_charge 第一次量(录制方 3 / 看的人 0)不分叉, 前提造到 3999(差 1 满一刻)才分叉。
##     ⇒ 一个字段要拿出去, 判据是「回放那一遍根本没读它」(读记录), 而不是「这一局改了它没看出来」。
const STATE_KEYS := [
	"dual_active",          # 必需(第 60 步): 不为真就不走双路
	"dual_lineup",          # 必需(347 开打时单位不同): 我方分路/槽位/小将装备
	"season_leaders",       # 必需(347): 三统领 id(dual_lineup 按 slot 读它)
	"persistent_equipped",  # 必需(360): 统领身上的装备 ★只留上场统领那几把(见 _fielded_equips) —— 未上场的装备池不进录像
	"loadouts",             # 必需(360): 每只龟选的技能(敌方复制技能时也按 id 查, 不按上场裁)
	"season_level",         # 必需(360): 等级 ⇒ 属性
	"candy_temp_levels",    # 必需(360): 糖果临时等级
	"debug_level",          # 必需(360): >0 强制全体等级(正式版 0; 看的人那台若开着就会分叉)
	"trainer_skill",        # 必需(480): 大师技能(U2 后自动放)
	"gambler_wheel_stacks", # 必需(360): 赌神命运之轮跨场累积(★回放那一遍没读到它 —— 是静态扫补进来的, 选了命运之轮才读)
	"chest_treasure_value", # 必需(2640): 宝箱财宝值(开箱阈值)
	"chest_treasures_won",  # 必需(2640): 已开战利品开局回装
	"incense_marks",        # 必需(420): 093 香火石刻痕
	"incense_charge",       # 必需(终局): 093 充能(见上面的 ⚠)
	"dual_ghost",           # 必需(347): 对手快照(上传那份再摘机器人标记, 见 replay_uploader.GHOST_STRIP)
	"trainer_appearance",   # 不改 sim(实测拿掉不分叉), 但它是**画面**: 不录的话看的人看到的是自己的大师形象
	"tutorial_active",      # 必需(选图): v0.19.533 起教学固定暗林、正式对局按种子随机 ⇒ 不录的话看的人那台若在教学中就放成另一张图(合批门禁 V7 实测: 录 shoal 放 dusk)
]
## 回放那一遍读了、但**不进录像**的(实测拿掉都不分叉 + 读代码确认原因):
##   test_mode / tutorial      播放入口自己设(test_mode=true 不落盘; tutorial=false 回放不挂教学引导)
##   current_lane / egg_hp / lane_results / dual_survivors / dual_ms_stacks / foe_loadouts
##                             战斗场开局自己初始化(foe_loadouts 从 dual_ghost 取)
##   perf_lite                 看的人那台设备的画质设置
## ★门禁 `verify_replay_roundtrip` V3c 每次都**重新量**一遍「回放读了哪些」, 必须 ⊆ STATE_KEYS ∪ 本表 ——
##   以后谁在战斗里新读一个 GameState 变量, 门禁当场红, 逼着回答「它进不进录像」。
const PLAY_READS_NOT_RECORDED := ["test_mode", "tutorial", "current_lane", "egg_hp", "lane_results",
	"dual_survivors", "dual_ms_stacks", "foe_loadouts", "perf_lite"]
## 其余约 100 个变量回放那一遍**一次都没读**(币/邮箱/昵称/账号/背包/装备池/赛季战绩/宝箱以外的进度……)。

## 播放前备份 / 退出还原时**不碰**的变量(令牌 / 设备身份 / 战绩 / 补报单 / 上传队列):
##   回放期间它们可能被别的路径真改了(例如续登录换了 refresh 令牌), 还原成旧值反而写坏。
const BACKUP_SKIP := ["test_mode", "auth_refresh", "account_email", "install_uid", "cloud_rev",
	"match_history", "finals_report_pending", "replay_pending_id",
	## S2 上传队列: 播放时不许被覆盖(V5)。E7 快照上传队列同理。
	"replay_upload_pending", "ghost_upload_pending"]
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


## 这一局录不录。Q3(用户授权按推荐): 先只录周六闯关赛;
## 2026-10-04 周末看回放(docs/plans/20261004-周末看回放.md): **周日决赛场也录** —— 对阵图点已揭晓那一格要看它。
##   决赛场的身份是 `finals_match`(对阵图开打时盖章, 结算尾部才清; `on_settle` 在它之前跑)。
## ★★2026-10-05 用户改 Q3:「积分赛也录」(docs/plans/20261005-回放体验打磨.md · 主会话实玩: 打完一局积分赛,
##   战绩页没有「回放」、服务端也没收到 —— 原来只录周六/周日)。原话目标:「理想效果是我能在其他设备上看到比赛回放」
##   ⇒ 自己打的每一局正式对局都录: 积分赛(周一~周五 + 休赛日按积分赛算)、表演赛(淘汰后的积分赛)、周六、周日。
##   不录: 教学(沙盒、不计成绩)、非双路对局(调试场 / 审阅台等开发入口)、周日没有对阵坐标的那种(不是决赛场)。
static func should_record() -> bool:
	if GameState == null or not bool(GameState.dual_active) or bool(GameState.get("tutorial_active")):
		return false
	var sk := current_settle_kind()
	if sk == Phase2Cfg.SETTLE_FINALS:
		var fm = GameState.get("finals_match")
		return fm is Dictionary and not (fm as Dictionary).is_empty()
	return sk == Phase2Cfg.SETTLE_GAUNTLET or sk == Phase2Cfg.SETTLE_RANKED


## 这一局按哪一种结算(与 `_settle_season` 同一个判据: `settle_kind(week_phase, phase_mode_live)`)。
static func current_settle_kind() -> String:
	var ph := str(GameState.week_phase)
	return Phase2Cfg.settle_kind(ph, Phase2Cfg.phase_mode_live(ph))


static func client_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func is_playing() -> bool:
	return mode == "play"


## 播放时 sim 推进倍率: 摆位阶段快进(那段只是录制者在想怎么摆, 对局结果与它无关 ——
## 步数照样一步不少地跑, 只是一帧多跑几步; 协程/补间都已挂在 sim 步上, 一帧几步不改结果)。
## 2026-10-05 回放体验打磨(docs/plans/20261005-回放体验打磨.md): 看的人能**暂停 / 2 倍 / 4 倍**。
##   ★倍速只改「这一帧跑几步」, 不改步长 SIM_DT ⇒ 每一步算的东西与 1 倍逐位相同(校验点照比);
##   暂停 = 这一帧一步都不跑(累加器不进账, 恢复时不会一口气补跑)。
func time_mult() -> float:
	if mode != "play":
		return 1.0
	if paused:
		return 0.0
	if str(battle._dl_state) == "place":
		return maxf(8.0, speed)
	return speed


## 看的人选的倍速(1 / 2 / 4)与暂停。只在播放时有意义; 录制那一局永远是 1。
##   倍速记在静态变量里: 「再看一遍」/ 看下一场时沿用上一次选的(与市面上回放器一致), 暂停不沿用。
const SPEEDS := [1.0, 2.0, 4.0]
static var _pref_speed := 1.0
var speed := _pref_speed
var paused := false


## 倍速轮换 1 → 2 → 4 → 1, 返回新倍速。
func cycle_speed() -> float:
	var i := SPEEDS.find(speed)
	speed = float(SPEEDS[(i + 1) % SPEEDS.size()])
	_pref_speed = speed
	return speed


## 这一场一共多少 sim 步(录制那一局结算时的步号; 读不到 = -1)。进度条与「全场时长」用它。
func total_steps() -> int:
	return int((rec.get("end", {}) as Dictionary).get("s", -1))


## 每一路开打的步号(进度条上的刻度: 上路 / 下路 / 终极)。
func fight_steps() -> Array:
	var out: Array = []
	for e in rec.get("events", []):
		if e is Dictionary and str((e as Dictionary).get("k", "")) == "fight":
			out.append(int((e as Dictionary).get("s", 0)))
	return out


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
## ★★浮点一律走 `exact()`(位模式), 不许 `%.2f`(2026-10-05):
##   `%.Nf` 落到各平台自己的 printf, 而**恰好是 .5 的二进制精确值**两家舍入方向不同 ——
##   实测同一个 x = 1274.125(位模式逐位相同), Windows 印「1274.13」、Linux/glibc 印「1274.12」。
##   ⇒ 状态完全一致, 指纹却不同 ⇒ 跨设备回放会**假报分叉**(verify_determinism_cross ⑬ 就是这么红的)。
static func fingerprint(b) -> String:
	var parts: Array = ["t=" + exact(float(b._t)), str(b._dl_state)]
	var i := 0
	for u in b._units:
		var p: Vector2 = u.get("pos", Vector2())
		parts.append("%d/%s/%s:%s:%s:%s:%d:%s:%s" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			exact(float(u.get("hp", 0.0))), exact(p.x), exact(p.y),
			1 if bool(u.get("alive", false)) else 0,
			exact(float(u.get("shield", 0.0))), exact(float(u.get("energy", 0.0)))])
		i += 1
	return "|".join(parts)


## 浮点 → 与平台无关的字符串: float64 的 8 个字节(小端; x86/ARM64 都是小端)转十六进制。
## ★不经 printf ⇒ 没有「.5 往哪边舍」这一维; 而且比 `%.2f` 更严 —— 差一个 ulp 也看得见。
static func exact(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


static func digest(b) -> String:
	return fingerprint(b).md5_text().substr(0, 16)


# ─────────────────────────────── GameState ───────────────────────────────

## 录像用: 只取 `STATE_KEYS`(持久装备只留上场统领的)。
static func capture_state() -> Dictionary:
	var out := {}
	if GameState == null:
		return out
	for n in STATE_KEYS:
		var v = GameState.get(n)
		if v == null or not _plain(v):
			continue
		out[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	if out.get("persistent_equipped", null) is Dictionary:
		out["persistent_equipped"] = _fielded_equips(out["persistent_equipped"], out)
	return out


## 持久装备只留**上场统领**的(season_leaders ∪ 分路里的统领 id)。
##   战斗场读它的只有 `_inject_equipment`: 逐个非召唤单位按 id 取 ⇒ 不在场上的龟一件都不会被读。
static func _fielded_equips(pe: Dictionary, st: Dictionary) -> Dictionary:
	var on := {}
	for id in st.get("season_leaders", []):
		on[str(id)] = true
	var dl = st.get("dual_lineup", {})
	if dl is Dictionary:
		for lane in dl:
			if dl[lane] is Array:
				for e in dl[lane]:
					if e is Dictionary and str((e as Dictionary).get("kind", "")) == "leader":
						on[str((e as Dictionary).get("id", ""))] = true
	var out := {}
	for k in pe:
		if on.has(str(k)):
			out[k] = pe[k]
	return out


## 备份用: GameState 全部脚本变量(去掉 BACKUP_SKIP)。
static func capture_all() -> Dictionary:
	var out := {}
	if GameState == null:
		return out
	for p in GameState.get_property_list():
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n := str(p.get("name", ""))
		if n in BACKUP_SKIP:
			continue
		var v = GameState.get(n)
		if not _plain(v):
			continue
		out[n] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## 只写 `STATE_KEYS` 里的(★录像是别人传上来的数据: 表外的键一律不认, 不让一份录像改写看的人的币/账号/背包)。
static func apply_state(st: Dictionary) -> void:
	for n in st:
		if not str(n) in STATE_KEYS:
			continue
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

## 看完回哪一页(场景路径)。空 = 战绩页(S3 原来的去处)。每次 `play` 都重写 ⇒ 不会残留上一次的。
static var return_scene := ""
## 回放结束那句话里的双方名字 {"l": 录像方, "r": 对手}。空 = 照旧说「胜利 / 失败」(那是看自己的录像)。
static var play_names: Dictionary = {}
## 看的人自己的名字(`play()` 进场前取; 门禁直接 begin_play 时为空 ⇒ 铭牌左边留空)。
static var viewer_name := ""
const DEFAULT_EXIT_SCENE := "res://scenes/Record.tscn"


static func exit_scene() -> String:
	return return_scene if return_scene != "" else DEFAULT_EXIT_SCENE


## 回放结束那一句(收尾卡的大标题)。看别人的录像时「胜利」是录像方的视角, 对旁观者是错话 ⇒ 有名字就说谁赢了。
static func end_caption(won: bool) -> String:
	var who := str(play_names.get("l" if won else "r", ""))
	if who != "":
		return "%s 获胜" % who
	return "胜利" if won else "失败"


## 回放里左右两边各是谁 {"l": 录像方, "r": 对手}(不知道就是 "")。回放条与开打前的阵容牌用它。
##   · 赛况板传了 l / r(两个不同的名字)⇒ 直接用。
##   · 对阵图只知道这一场的两个人 `pair`, 不知道谁是录像方 ⇒ 对手 = 录像里那份对手快照的名字, 录像方 = 另一个。
##   · 什么都没传 = 战绩页看自己的录像 ⇒ 录像方 = 我。
static func side_names(r: Dictionary, me: String = "") -> Dictionary:
	var g = (r.get("state", {}) as Dictionary).get("dual_ghost", {})
	var foe := ""
	if g is Dictionary and (g as Dictionary).get("profile", null) is Dictionary:
		foe = str(((g as Dictionary)["profile"] as Dictionary).get("name", ""))
	var l := str(play_names.get("l", ""))
	var rr := str(play_names.get("r", ""))
	if l != "" and rr != "" and l != rr:
		return {"l": l, "r": rr}
	var pair = play_names.get("pair", [])
	if pair is Array and (pair as Array).size() == 2:
		if foe == str(pair[0]):
			return {"l": str(pair[1]), "r": foe}
		if foe == str(pair[1]):
			return {"l": str(pair[0]), "r": foe}
		return {"l": "", "r": ""}
	if play_names.is_empty():
		return {"l": me, "r": foe}
	return {"l": "", "r": foe}


## 「再看一遍」: 从头再播同一份。见 `end_play` 里那一段。
static var _again: Dictionary = {}


static func play_again(tree: SceneTree, r: Dictionary) -> void:
	if r.is_empty() or tree == null:
		return
	_again = r
	tree.change_scene_to_file(BATTLE_SCENE)


## 播一份记录。返回 "" = 已进战斗场; 否则是不能播的原因(V6: 版本不同就不进战斗场)。
## `back` = 看完回哪一页(空 = 战绩页); `names` 见 `play_names`。
static func play(tree: SceneTree, r: Dictionary, back: String = "", names: Dictionary = {}) -> String:
	if r.is_empty():
		return "回放记录读不出来"
	if str(r.get("client_version", "")) != client_version():
		return "这场比赛是旧版本(%s)打的, 当前版本(%s)播不了" % [str(r.get("client_version", "?")), client_version()]
	if int(r.get("v", 0)) != FORMAT_V:
		return "回放格式不认识"
	return_scene = back
	play_names = names.duplicate()
	## 看的人自己的名字(看自己的录像时铭牌左边写它)。★在 begin_play 之前读:
	##   回放那一遍读到的 GameState 变量必须 ⊆ STATE_KEYS ∪ PLAY_READS_NOT_RECORDED(roundtrip V3c), 昵称不该进那张表。
	viewer_name = Uploader.BE.player_display_name()
	begin_play(r)
	if tree != null:
		tree.change_scene_to_file(BATTLE_SCENE)
	return ""


## 只做「备份 GameState → 写入记录 → 挂上待播」, 不换场景(门禁直接实例化战斗场用)。
static func begin_play(r: Dictionary) -> void:
	if not _has_backup:
		_backup = capture_all()
		_backup_test_mode = bool(GameState.test_mode)
		_has_backup = true
	GameState.test_mode = true          # 回放期间任何 save() 都空转(V5)
	GameState.tutorial = false          # 回放不挂教学引导(战斗场 _ready 看它; 不进录像)
	apply_state(r.get("state", {}))
	pending_play = r


## 退出回放(战斗场离树时一定会调): GameState 还原成播之前那一份。
static func end_play() -> void:
	pending_play = {}
	if not _has_backup:
		return
	for n in _backup:
		var v = _backup[n]
		GameState.set(str(n), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	GameState.test_mode = _backup_test_mode
	_backup = {}
	_has_backup = false
	## 「再看一遍」: 旧战斗场离树(这里)先于新战斗场 `_ready` ⇒ 先还原成播之前那一份, 再按原样重新挂上待播。
	##   ★不能在离场之前就 `begin_play`: 离场这一下会把 `pending_play` 清掉、把 GameState 还原, 新场就成了一局普通对战。
	if not _again.is_empty():
		var r := _again
		_again = {}
		begin_play(r)
