class_name StreamPlayer
extends RefCounted
## 服务器逐帧直播 · 手机播放(S2)。方案书 docs/plans/20261019-服务器逐帧直播.md §4「手机侧: 只播不算」。
##
## ★手机一步 sim 都不跑。战斗场照常建(相机 / 地面 / UI 层), 但 `ReplayRecorder.mode == "stream"`:
##   · `_spawn_teams` 不建单位(battle_spawn 第一行), `sim_feed` 返回 0 ⇒ `_advance_sim_accum` 一步都不推;
##   · 每帧由 `advance(rd)` 推播放头(60 步/秒), 把流里到期的那几步「应用」到画面上, 再自己跑一次渲染步。
##   门禁 verify_stream_no_sim: 整局播完 `_sim_step` 一次都没被调用(`_sim_step_n` 不变 + `sim_stepped` 0 次)。
##
## 应用三层(格式见 stream_format.gd / 方案 §2.2):
##   ① 单位层 → 单位代理字典(`battle._units` 里放的是代理, 不是战斗单位): 流里给什么字段就写什么,
##      外观节点(立绘 / 影 / 核影 / 环)由节点层镜像出来, 代理用 `@n` 认领; 血条 / 龟能条 / 等级牌由手机按字段自己建。
##      单位字段是服务器**渲染步之前**采的 ⇒ 手机跑同一个渲染步(同一个 rd), 立绘的位置 / 呼吸 / 形变 / 闪白 / 朝向与服务器逐位相同;
##      帧号 / 贴图 / 显隐由镜像给(代理恒 `_manual_anim`, 手机不推帧), 单位死了之后整个外观改由镜像给(死亡淡出是 sim tween)。
##   ② 节点层 → StreamMirror(建 / 改 / 删 / 资源)。
##   ③ 事件层 → 到步号就调原来唯一的实现(飘字 `_float_text` / `_shake` / `_add_hitstop` / 闪屏 / 音效 / 换路幕布)。
##      飘字按**本机相机**换算屏幕位置(流里记的是世界坐标)。
##
## 插值(30 Hz 采样之间): 连续量(单位 pos / height, 节点 position / rotation / scale / modulate, 全局 t)在「当前值」和
##   「下一个采样值」之间线性插, 角度 lerp_angle; 离散量(帧号 / 显隐 / 贴图 / 存活 / 动作)不插, 到步就换。
## 缓冲: 开播前攒够 START_STEPS 步(3 秒)或服务器已录完; 播到直播边沿停住显示「同步中」, 新块到了接着播。
## 跳转: `seek(步号)` 从最近的 keyframe 块重解(清空全部镜像状态 → 快进不放事件、不跑渲染 → 到目标步)。
## ★出错(版本不符 / 块坏 / 解不开): 停在「无法播放」, **绝不改成本机重算**。
## 回放 / 观赛(2026-10-20, memory fb-spectate-is-not-replay): 入口给 `controls = true`(已打完的回放)⇒ 底部操作条
##   暂停 / 倍速 / 进度条拖动(拖动 = `seek`, 从 keyframe 解); 观赛(正在算 / 周六自己那一场 / 周日开播)不给, 只有「退出」。
##   操作条就是回放那一条(replay_controls.gd), 它在 stream 模式下改的是本播放器的 `paused` / `speed`。

const F := preload("res://scripts/systems/stream/stream_format.gd")
const Live := preload("res://scripts/systems/replay/live_spectate.gd")
const SIM_DT := 1.0 / 60.0
const START_STEPS := 180          # 开播前缓冲 3 秒
const RESUME_STEPS := 60          # 卡在直播边沿后, 攒够 1 秒再接着播
## 一帧推的步数不超过它时, 中间每个采样步补跑渲染步(_apply_paced); 超过 = 快进(15 帧手机 × 4 倍速 = 16 步)
const PACED_MAX_STEPS := 16
const TXT_ERROR := "画面无法播放"
## 单位外观件的键(与录流器 APPEAR_KEYS 同序; `@n` 按这个顺序给 id)。
const APPEAR_KEYS := ["sprite", "shadow", "contact", "ring"]

## 播放入口写、战斗场 `_ready` 里 `ReplayRecorder.start()` 读走: {source(块来源), seed(int), state(可选: GameState 那几个键, 换路幕布要读阵容),
##   controls(可选: 回放操作条), wait_text(可选: 一块都还没到时屏上那句, 例如补流时「画面生成中」), fights / total(可选: 进度条的
##   路名刻度与全场步数, 取自录像), no_curtain(可选: 入口没有阵容 —— 观赛正在算的局 —— 不建换路幕布)}。
static var pending: Dictionary = {}

var battle
var src
var mirror: StreamMirror
var state := "buffering"          # buffering / playing / stalled / ended / error
var err := ""
var speed := 1.0
var paused := false
var head := -1.0                  # 播放头(步号, 小数)
var applied := -1                 # 已应用到的步号
var first_step := -1
var units := {}                   # 流里的单位 idx → 代理字典
var _steps: Array = []            # 已解码、还没应用的步: [步号, keyframe?, ops]
var _next_seq := 0
var _strtab := {}
var _last_step := -1              # 已解码的最后一步
var _utruth := {}                 # idx → [pos, height](插值用的真值)
var _gt := 0.0                    # 全局 t 的真值
var _last_cont := -1              # 最近一次采了连续量的步号
var _new_units: Array = []        # 这一步新登场、还没建血条的
var _kf_units := {}
var _in_kf := false
var _sync_lbl: Label = null
var _seed_seen := -1
var _lane_clears := 0             # 服务器到这一步为止换路清场过几次(全局 lcn)
var _bad := ""                    # 解到一块坏的: 原因(播放头走到它跟前才报错)
var _theme_seen := ""
## 计数(门禁分母)
var chunks_decoded := 0
var steps_applied := 0
var events := {}                  # 已触发的事件: 类型 → 次数
var sim_calls := 0                # 播放模式下 `_sim_step` 被调用的次数(ReplayRecorder.pre_step 里数; 必须恒 0)
var seeks := 0
var layout_cleared := 0
var on_applied: Callable = Callable()   # 门禁: 每应用完一步回调(步号)
## 播放端 HUD(头像框栏 / 法术圆盘 / 羁绊 chips / 路名计时牌的状态): 见 stream_hud.gd
var hud: StreamHud
## 播放入口给了阵容(`state`)⇒ 入口负责事后还原 GameState(与录像回放同一套 capture_all / 还原), 这里才许写 GameState
var _sandbox := false
## 这一步的事件放不放(快进 / 跳转时 false): HUD 里「到某个状态才播一次」的演出(加时大字)跟着它
var firing := true
var _bar_built := false
## 回放操作条(暂停 / 倍速 / 进度条)。false = 观赛, 只有「退出」。
var controls := false
## 一块都还没到时屏上那句(空 = 照常「同步中」)。
var wait_text := ""
## 进度条: 每一路开打的步号、全场步数(流的 end.json 到了以它为准)。
var fights: Array = []
var total_hint := -1
var _no_curtain := false
## 上一次跑渲染步时的播放头(这一帧的渲染步只补「从那以后」的那一段时长)
var _rh := -1.0
## 一帧推多步时, 在中间的采样步上补跑的渲染步次数(观测量)
var mid_renders := 0
## 这一次渲染步是不是落在采样步上(服务器只在采样步跑渲染步): 渲染步里「按状态冒东西」的判定只在它为真时做(battle_render._update_dot_floats)
var at_sample := true
## 正在应用 / 最近应用的那一步的步号(飘字合并的步号窗用, 同服务器 `_sim_step_n`)
var cur_step := -1


func _init(b, opts: Dictionary) -> void:
	battle = b
	src = opts.get("source")
	if opts.has("seed"):
		battle._battle_rng.seed = int(opts["seed"])     # 只为选同一张地图(ArenaTheme 读种子整数做哈希, 不从 rng 取数)
	battle._deterministic = false                       # TURTLE_SEED 设了也不许走「每帧一步 sim」那条
	mirror = StreamMirror.new(battle._world)
	hud = StreamHud.new(battle, self)
	_sandbox = opts.has("state") and opts["state"] is Dictionary and not (opts["state"] as Dictionary).is_empty()
	controls = bool(opts.get("controls", false))
	speed = float(opts.get("speed", 1.0))       # 回放: 入口给的上一次选的倍速(与重算回放同一个 ReplayRecorder._pref_speed)
	wait_text = str(opts.get("wait_text", ""))
	fights = (opts.get("fights", []) as Array).duplicate() if opts.get("fights", null) is Array else []
	total_hint = int(opts.get("total", -1))
	_no_curtain = bool(opts.get("no_curtain", false))
	mirror.unit_parent = func(idx: int, key: String):
		var u = units.get(idx)
		return u.get(key) if u is Dictionary else null


# ═══════════════════════════════════════════════════════════════════════
#  每帧(ReplayRecorder.sim_feed 调; 返回 0 ⇒ 战斗场的 sim 累加器一步都不推)
# ═══════════════════════════════════════════════════════════════════════
func advance(rd: float) -> float:
	if not _bar_built and battle._hud != null and battle._ui_layer != null:
		_bar_built = true
		battle._hud.build_replay_bar()     # 「退出」(缓冲 / 同步中也要能走)与收尾卡的容器, 见 replay_controls.gd
	var h0 := head
	_rh = h0
	_tick(rd)
	if state == "ended":
		hud.on_ended()
	var adv := maxf(0.0, head - _rh) if _rh >= 0.0 else 0.0
	_render(adv * SIM_DT)
	_rh = head
	_update_label()
	return 0.0


func _tick(rd: float) -> void:
	if state == "error" or state == "ended":
		return
	if src == null:
		_fail("no source")
		return
	_pump(int(maxf(head, 0.0)) + START_STEPS + 2)
	if first_step < 0:
		if _bad != "":
			_fail(_bad)
		return
	if head < 0.0:
		head = float(first_step) - 1.0
	var ahead := _last_step - int(head)
	if state == "buffering" or state == "stalled":
		var need := START_STEPS if state == "buffering" else RESUME_STEPS
		if ahead >= need or src.ended() or _bad != "":
			state = "playing"
		else:
			return
	if paused:
		return
	var target := head + rd * 60.0 * speed
	if absf(target - roundf(target)) < 1.0e-6:
		target = roundf(target)      # 2/60 × 60 在浮点里可能是 1.9999…: 别因此少应用一步
	if target >= float(_last_step):
		target = float(_last_step)
		if _bad == "" and not (src.ended() and _next_seq >= src.available()):
			state = "stalled"        # 追上了服务器: 停在缓冲尾部「同步中」, 新块到了接着播(绝不本机补算)
	_apply_paced(int(floor(target)))
	head = target
	if _bad != "" and _steps.is_empty() and applied >= _last_step:
		_fail(_bad)
		return
	if src.ended() and _next_seq >= src.available() and _steps.is_empty() and applied >= _last_step:
		state = "ended"
	_interp()


## 把能解的块解出来, 直到已解码的步号 ≥ want(或者块来源暂时没有更多)。
func _pump(want: int) -> void:
	while _bad == "" and _last_step < want and _next_seq < src.available():
		if not _decode(_next_seq):
			return


func _decode(seq: int) -> bool:
	## 解不开的块: 先记下, 前面已经解好的照常播完, 播放头走到这里才停在「无法播放」
	var data: PackedByteArray = src.chunk(seq)
	if data.is_empty():
		_bad = "chunk %d missing" % seq
		return false
	var d := F.parse_chunk(data, _strtab.duplicate())
	if not bool(d.get("ok", false)):
		_bad = "chunk %d: %s" % [seq, str(d.get("err", ""))]
		return false
	if int(d["seq"]) != seq:
		_bad = "chunk seq %d != %d" % [int(d["seq"]), seq]
		return false
	_strtab = d["st"]                # 字符串表跨块延续(keyframe 块里清零); 解码成功才接上
	if first_step < 0:
		first_step = int(d["first_step"])
	for st in (d["list"] as Array):
		_steps.append(st)
		_last_step = int(st[0])
	_next_seq = seq + 1
	chunks_decoded += 1
	return true


func _fail(why: String) -> void:
	state = "error"
	err = why
	push_warning("[StreamPlayer] 无法播放: " + why)


## 正常播放推到第 s 步(放全部事件)。★一帧推多步(低帧率手机 / 慢机 / 倍速 / 追帧)时, 每越过一个采样步就照服务器的节奏
##   在那一步跑一次渲染步(服务器录流时每 2 步按 2·SIM_DT 跑一次, `StreamRecorder` 渲染步对齐) —— 渲染步里按状态冒的东西
##   (DOT 常驻数字结束时的弹射飘字 `_update_dot_floats`、闪白 / 形变衰减 …)才与帧率无关。原来一帧只跑一次渲染步,
##   一帧推 4 步时中间那个采样步上的「桶结束」看不到 ⇒ 少一条飘字(2026-10-20 CI 慢机 verify_stream_parity 红)。
##   一帧最多越过 1 个采样步时(60 帧 / 秒、门禁一次推 2 步)与原来逐字相同。跳转(seek)的快进不走这里。
func _apply_paced(s: int) -> void:
	if s - applied > PACED_MAX_STEPS:
		_apply_until(s, true)      # 一帧推得更多(门禁 40 倍速 / 追帧): 当快进, 只在帧尾跑一次渲染步(事件照样全放)
		return
	while _rh >= 0.0 and first_step >= 0 and not _steps.is_empty():
		var nx := applied + 1 if ((applied + 1 - first_step) % F.CONT_EVERY) == 1 else applied + 2
		if nx >= s or int(_steps[0][0]) > nx:
			break
		_apply_until(nx, true)
		if applied != nx:
			break
		head = float(nx)
		_interp()
		_render((head - _rh) * SIM_DT)
		_rh = head
		mid_renders += 1
	_apply_until(s, true)


func _apply_until(s: int, fire: bool) -> void:
	while not _steps.is_empty() and int(_steps[0][0]) <= s:
		var st: Array = _steps.pop_front()
		_apply_step(st, fire)
		if not fire and int(st[0]) < s and (int(st[0]) - first_step) % F.CONT_EVERY == 1:
			## 快进(跳转)不跑渲染步, 但渲染步会改的那几个单位字段(形变 / 闪白计时)服务器那边是改过的,
			##   流里只在它们又被 sim 改了才重发 ⇒ 这里照服务器的节奏(每个采样步 2·SIM_DT)把它们衰减掉, 跳进来那一帧才对得上
			##   (目标那一步不在这里衰减: 跳完紧接着那次渲染步会做)
			_set_ts_active()
			battle._vfx._juice_decay(F.CONT_EVERY * SIM_DT)


# ═══════════════════════════════════════════════════════════════════════
#  应用一步
# ═══════════════════════════════════════════════════════════════════════
func _apply_step(st: Array, fire: bool) -> void:
	var key := bool(st[1])
	cur_step = int(st[0])          # 这一步的事件放的时候, 「现在是第几步」= 服务器 sim 那一步(_sim_step 开头就 +1 了)
	firing = fire
	mirror.restore()
	if key:
		_in_kf = true
		_kf_units = {}
		mirror.kf_begin()
	for op in (st[2] as Array):
		match int(op[0]):
			F.OP_GLOBAL:
				_globals(op[1] as Dictionary)
			F.OP_UNIT_NEW:
				_unit_new(int(op[1]), str(op[2]), str(op[3]))
			F.OP_UNIT_SET:
				_unit_set(int(op[1]), op[2] as Dictionary)
			F.OP_UNIT_DEL:
				_unit_del(int(op[1]))
			F.OP_NODE_NEW:
				mirror.node_new(int(op[1]), int(op[2]), int(op[3]), str(op[4]), str(op[5]), op[6] as Array)
			F.OP_NODE_SET:
				mirror.node_set(int(op[1]), op[2] as Array)
			F.OP_NODE_DEL:
				mirror.node_del(int(op[1]))
			F.OP_RES_DEF:
				mirror.res_def(int(op[1]), int(op[2]), op[3], op[4], op[5])
			F.OP_RES_SET:
				mirror.res_set(int(op[1]), op[2] as Array)
			F.OP_EVENT:
				if fire:
					_event(str(op[1]), op[2] as Array)
	if key:
		mirror.kf_end()
		for idx in units.keys():
			if not _kf_units.has(idx):
				_unit_del(int(idx))
		_in_kf = false
	applied = int(st[0])
	var cont := key or (applied - first_step) % F.CONT_EVERY == 1
	## ★血条 / 头像框只在采样步(全字段都到了)建: 非采样步登场的单位流里只带 id / 阵营,
	##   是不是大师 / 蛋 / 召唤物、名字、装备要到下一个采样步才到 ⇒ 早建会给大师建出血条、头像框写成「__trainer__」
	_finish_units(cont)
	if cont:
		_last_cont = applied        # 最近一次采了连续量的步(插值的起点; keyframe 之后下一个采样只隔 1 步)
		hud.after_step()
	steps_applied += 1
	if on_applied.is_valid():
		on_applied.call(applied)


func _globals(g: Dictionary) -> void:
	for k in g:
		var v = g[k]
		match str(k):
			"dl": battle._dl_state = str(v)
			"over": battle._over = bool(v)
			"t":
				_gt = float(v)
				battle._t = _gt
			"hs": battle._hitstop = float(v)
			"seed": _seed_seen = int(v)
			"lcn": _lane_clears = int(v)
			"lc":
				if v is PackedVector3Array:
					_layout_clear(v)
			"theme": _theme_seen = str(v)
			_ when str(k).begins_with("h."):
				hud.apply_glob({str(k).substr(2): v})   # 播放端 HUD 的全局项(stream_hud.gd glob), 一项一项来
			"lane":
				if gs_sandboxed():
					battle.get_node_or_null("/root/GameState").current_lane = str(v)


# ── 单位代理 ──
func _unit_new(idx: int, id: String, side: String) -> void:
	_kf_units[idx] = true
	if units.has(idx):
		return
	var u := {"id": id, "side": side, "alive": true, "pos": Vector2.ZERO, "height": 0.0,
		"sprite": null, "shadow": null, "contact": null, "ring": null,
		"bar_root": null, "hp_bar": null, "en_fill": null, "level_badge": null,
		"hp": 1.0, "maxHp": 1.0, "shield": 0.0, "skill_cd": {}, "active_skills": [], "energy_cost": {},
		"_manual_anim": true, "_stream_idx": idx}
	units[idx] = u
	battle._units.append(u)
	_new_units.append(u)


func _unit_set(idx: int, kv: Dictionary) -> void:
	var u = units.get(idx)
	if not (u is Dictionary):
		return
	var d: Dictionary = u
	for k in kv:
		var ks := str(k)
		var v = kv[k]
		if ks == "_manual_anim":
			continue                  # 帧号由镜像给, 代理恒手动帧(见文件头)
		if ks == "@n":
			d["@n"] = v
			continue
		if ks == "@eq" or ks == "@hud":
			hud.apply_unit(d, ks, v)
			continue
		if ks == "@mv":
			d["vel"] = Vector2(BattleVfx.BOB_STILL_SPD * 2.0, 0.0) if bool(v) else Vector2.ZERO   # 渲染步只拿 vel 判「走着不呼吸」
			continue
		d[ks] = v
	if kv.has("pos") or kv.has("height"):
		## ★没给的那一项取真值表, 不取代理: 代理上的 pos / height 可能是上一帧插出来的中间值
		var old: Array = _utruth.get(idx, [d.get("pos", Vector2.ZERO), float(d.get("height", 0.0))])
		var tp = kv["pos"] if kv.has("pos") else old[0]
		var th: float = float(kv["height"]) if kv.has("height") else float(old[1])
		_utruth[idx] = [tp, th]
		d["pos"] = tp
		d["height"] = th
		d["_prev_pos"] = d["pos"]
		d["_prev_height"] = d.get("height", 0.0)


func _unit_del(idx: int) -> void:
	var u = units.get(idx)
	units.erase(idx)
	_utruth.erase(idx)
	if not (u is Dictionary):
		return
	var root = (u as Dictionary).get("bar_root")
	if root != null and is_instance_valid(root):
		(root as Node).queue_free()
	var ul: Array = battle._units
	for i in range(ul.size()):
		if is_same(ul[i], u):
			ul.remove_at(i)
			break


## 一步应用完: 认领外观节点(`@n` 里的镜像 id → 节点), 给新登场的单位建血条。
func _finish_units(bars: bool = true) -> void:
	for idx in units:
		var u: Dictionary = units[idx]
		var ids = u.get("@n")
		if ids is Array:
			for i in range(mini(APPEAR_KEYS.size(), (ids as Array).size())):
				var nid := int(ids[i])
				var nd = mirror.nodes.get(nid) if nid > 0 else null
				u[APPEAR_KEYS[i]] = nd if (nd != null and is_instance_valid(nd)) else null
	if not bars:
		return
	for u in _new_units:
		var d: Dictionary = u
		if not units.has(int(d.get("_stream_idx", -1))):
			continue
		if bool(d.get("is_trainer", false)) or battle._ui_layer == null:
			continue
		var summon := bool(d.get("is_summon", false))
		var bar: Dictionary = battle._make_status_bar(str(d["side"]), 0 if summon else int(d.get("level", 0)))
		if summon and bar.get("en") != null:
			(bar["en"] as Control).visible = false
		battle._ui_layer.add_child(bar["root"])
		d["bar_root"] = bar["root"]
		d["hp_bar"] = bar["hp_bar"]
		d["en_fill"] = bar["en"]
		d["level_badge"] = bar.get("level_badge", null)
	_new_units.clear()


# ── 事件: 调原来唯一的实现 ──
func _event(kind: String, a: Array) -> void:
	events[kind] = int(events.get(kind, 0)) + 1
	match kind:
		"float":
			if a.size() >= 7:
				battle._vfx._float_text(a[0], str(a[1]), a[2], bool(a[3]), str(a[4]), str(a[5]), float(a[6]))
		"shake":
			battle._shake(float(a[0]))
		"hitstop":
			battle._add_hitstop(float(a[0]))
		"flash":
			if a.size() >= 1 and str(a[0]) == "light":
				battle._vfx.screen_flash_light()
			elif a.size() >= 3:
				battle._dl_sys._dl_flash_screen(a[1], float(a[2]))
		"sfx":
			var au = battle.get_node_or_null("/root/Audio")
			if au != null and a.size() >= 3:
				au.play_sfx(str(a[0]), float(a[1]), float(a[2]))
		"curtain_in":
			if not DualLaneFlow.NO_PRESENT and _curtain_ok():
				battle._dl_sys._dl_enter_present(str(a[0]))
		"curtain_out":
			battle._dl_sys._dl_clear_present_overlay()
		"lane_clear":
			_lane_clear()
		"dotacc":
			var u = units.get(int(a[0])) if a.size() >= 3 else null
			if u is Dictionary:
				battle._damage._dot_accumulate(u, str(a[1]), int(a[2]))
		"layout_clear":
			if a.size() >= 1:
				_layout_clear(a[0])
		"finish":
			if a.size() >= 2:
				hud.on_finish(bool(a[0]), float(a[1]))


## 换路建场时删掉压在障碍上的地图摆件: 地图是手机按同一张图自己建的, 按位置删同一批(全局 `lc` 在 keyframe 里也带, 跳进来照样删)。
func _layout_clear(pos: PackedVector3Array) -> void:
	var lp: Node = battle._world.find_child("LayoutProps", true, false)
	if lp == null:
		return
	for ch in lp.get_children():
		if not (ch is Node3D) or ch.is_queued_for_deletion():
			continue
		for q in pos:
			if (ch as Node3D).position.distance_squared_to(q) < 1.0e-8:
				(ch as Node3D).visible = false
				ch.queue_free()
				layout_cleared += 1
				break


## 换路清场(服务器 `dual_lane_flow._dl_clear_units` 发): 手机这边清掉**自己**造的那部分 ——
##   手机侧 tween、全屏闪、飘字排行窗、`_world` 里不常驻且不是镜像的节点(渲染步按状态造的特效)、UI 层短命节点。
##   镜像节点不在这里删: 服务器扫掉的那些会照常发 DEL。
func _lane_clear() -> void:
	for tw in battle._sim_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	battle._sim_tweens.clear()
	for fl in battle.get_tree().get_nodes_in_group(battle.SCREEN_FLASH_GROUP):
		if is_instance_valid(fl):
			fl.queue_free()
	battle._float_dmg_window.clear()
	battle._float_nd_window.clear()
	battle._float_merge.clear()
	_sweep_own(false)
	if battle._hud != null:
		battle._hud.sweep_ui_vfx()


func _has_bands() -> bool:
	for c in battle._world.get_children():
		if c.has_meta("fg_band") and not c.is_queued_for_deletion():
			return true
	if battle._cam != null:
		for c in battle._cam.get_children():
			if c.has_meta("fg_band") and not c.is_queued_for_deletion():
				return true
	return false


## 清掉 `_world` 里手机自己按状态造的节点(不常驻、不是镜像)。
##   前景带(`fg_band`)建场后才挪进世界、不在常驻表里 ⇒ 服务器第一次换路清场就把它扫掉了(之后各路都没有);
##   换路事件照扫(keep_bands = false), 跳转重置先留着、快进完再按「换过几次路」(全局 lcn)决定扫不扫。
func _sweep_own(keep_bands: bool) -> void:
	var mine := {}
	for id in mirror.nodes:
		var n = mirror.nodes[id]
		if n != null and is_instance_valid(n):
			mine[(n as Object).get_instance_id()] = true
	for c in battle._world.get_children():
		var iid: int = c.get_instance_id()
		if battle._world_permanent.has(iid) or mine.has(iid) or (keep_bands and c.has_meta("fg_band")):
			continue
		c.queue_free()


## 幕布内容按 GameState 里的阵容建; 播放入口没给阵容(state)就不建(只留战场画面), 免得读到本机自己的阵容。
func _curtain_ok() -> bool:
	var gs = battle.get_node_or_null("/root/GameState")
	return not _no_curtain and gs != null and bool(gs.get("dual_active")) and gs_sandboxed()


## 许不许写 GameState(当前路 / 各路胜负): 播放入口给了阵容(它负责事后还原)或测试模式。
##   没给 ⇒ GameState 是看的人自己的存档, 一个字都不许动(路名计时牌 / 路点就停在它原来的值)。
func gs_sandboxed() -> bool:
	var gs = battle.get_node_or_null("/root/GameState")
	return gs != null and (_sandbox or bool(gs.test_mode))


# ═══════════════════════════════════════════════════════════════════════
#  插值: 用下一个(至多两步外的)采样值插当前显示
# ═══════════════════════════════════════════════════════════════════════
func _interp() -> void:
	mirror.restore()
	## 单位代理先回真值
	for idx in _utruth:
		var u = units.get(idx)
		if u is Dictionary:
			var tr: Array = _utruth[idx]
			u["pos"] = tr[0]
			u["height"] = tr[1]
			u["_prev_pos"] = tr[0]
			u["_prev_height"] = tr[1]
	battle._t = _gt
	var base := floorf(head)
	for j in range(mini(2, _steps.size())):
		var st: Array = _steps[j]
		var s := int(st[0])
		if s > int(base) + 2:
			break
		if bool(st[1]):
			continue              # keyframe 步是全量重发(不是 30 Hz 采样点), 不拿它插
		var k := clampf((head - float(_last_cont)) / float(maxi(1, s - _last_cont)), 0.0, 1.0)
		if k <= 0.0:
			continue
		for op in (st[2] as Array):
			match int(op[0]):
				F.OP_NODE_SET:
					mirror.lerp_to(int(op[1]), op[2] as Array, k)
				F.OP_UNIT_SET:
					var u2 = units.get(int(op[1]))
					var kv: Dictionary = op[2]
					if u2 is Dictionary and _utruth.has(int(op[1])):
						var tr2: Array = _utruth[int(op[1])]
						if kv.has("pos") and kv["pos"] is Vector2:
							u2["pos"] = DetMath.vlerp(tr2[0] as Vector2, kv["pos"], k)
							u2["_prev_pos"] = u2["pos"]
						if kv.has("height"):
							u2["height"] = DetMath.flerp(float(tr2[1]), float(kv["height"]), k)
							u2["_prev_height"] = u2["height"]
				F.OP_GLOBAL:
					var g: Dictionary = op[1]
					if g.has("t"):
						battle._t = DetMath.flerp(_gt, float(g["t"]), k)


# ═══════════════════════════════════════════════════════════════════════
#  渲染(手机自己的渲染步: 变换 / 闪白 / 血条 / 跟着状态走的特效 / 震屏)
# ═══════════════════════════════════════════════════════════════════════
func _render(dt: float) -> void:
	if not is_instance_valid(battle) or battle._render == null:
		return
	at_sample = applied >= 0 and applied == _last_cont
	if dt > 0.0:
		battle._step_sim_tweens(dt)   # 手机自己造的演出(渲染步里按状态建的特效)的 tween; 流里的镜像节点不挂 tween
	battle._render_alpha = 0.0
	## 时停: 服务器那边哪几个单位在时停里能动(`@ts`)。手机只拿它决定谁的形变计时继续衰减(`_juice_decay` 自己读这张表);
	##   时停的全屏视觉(钟表 / 暗角, `_ts_tick_visual`)读的是 sim 里建的覆盖层, 手机没有 ⇒ in_ts 仍传 false(S3 长尾)。
	_set_ts_active()
	## 时停全屏层(S3 伪节点 @ts_screen → StreamMirror.ScreenFx): 由播放头推(跟暂停 / 倍速 / 跳转走), 不按真实帧自己推
	for fx in mirror.fx_nodes.values():
		if fx != null and is_instance_valid(fx) and fx.get("ts") != null:
			if (fx as Node).is_processing():
				(fx as Node).set_process(false)
			if dt > 0.0:
				fx.ts.ts_screen_tick(dt)
	battle._render._render_step(dt, float(battle._hitstop) > 0.0, false)


func _set_ts_active() -> void:
	var tsa: Array = []
	for u in units.values():
		if bool((u as Dictionary).get("@ts", false)):
			tsa.append(u)
	battle._timestop._ts_active = tsa


# ═══════════════════════════════════════════════════════════════════════
#  跳转: 从目标步之前最近的 keyframe 块重解
# ═══════════════════════════════════════════════════════════════════════
func seek(target: int) -> bool:
	if src == null:
		return false
	if first_step < 0:
		_pump(0)
		if first_step < 0:
			return false
	var seq := maxi(0, (target - first_step) / F.CHUNK_STEPS)
	seq = mini(seq, src.available() - 1)
	var kseq := seq - (seq % F.KEY_CHUNKS)
	if kseq < 0:
		return false
	seeks += 1
	_reset_all()
	_next_seq = kseq
	_strtab = {}
	_steps.clear()
	_last_step = -1
	_bad = ""
	_pump(target + 2)
	if _bad != "" and _last_step < target:
		_fail(_bad)
		return false
	_apply_until(target, false)
	head = float(applied)
	if _lane_clears > 0:
		_sweep_own(false)
	elif not _has_bands():
		battle._world_builder._build_foreground_band()   # 往回跳到第一次换路之前: 前景带被扫过了, 按同一张图重建(建好下一帧挪进世界)
	_restore_curtain()
	_interp()
	_render(F.CONT_EVERY * SIM_DT)   # 服务器在采样步跑的就是 2·SIM_DT 的渲染步: 跳进来那一帧与顺播到这一步画得一样
	state = "playing"
	return true


## 清空全部镜像状态: 镜像节点、单位代理(连血条)、手机自己按状态造的特效、飘字、手机侧 tween。
func _reset_all() -> void:
	mirror.clear()
	for idx in units.keys():
		_unit_del(int(idx))
	units.clear()
	_utruth.clear()
	_new_units.clear()
	battle._units.clear()
	_sweep_own(true)
	if battle._hud != null:
		battle._hud.sweep_ui_vfx()
	for tw in battle._sim_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	battle._sim_tweens.clear()
	battle._follow_vfx.clear()
	battle._anim_fx.clear()
	battle._coin_fx.clear()
	battle._dl_sys._dl_clear_present_overlay()
	hud.reset()
	applied = -1


## 跳进幕布中间: 事件没放(快进), 按全局 dl 把幕布补上。
func _restore_curtain() -> void:
	var dl := str(battle._dl_state)
	if dl in ["overview", "preview", "lane_settle"] and not DualLaneFlow.NO_PRESENT and _curtain_ok():
		battle._dl_sys._dl_enter_present(dl)


## 全场步数(进度条 / 全场时长): 流录完了(end.json)按它, 否则按入口给的(录像结算那一步); 都没有 = -1。
func total_steps() -> int:
	if src != null and src.ended():
		var ls := int((src.end_meta() as Dictionary).get("last_step", -1))
		if ls > 0:
			return ls
	return total_hint


# ── 「同步中」/「无法播放」 ──
func status_text() -> String:
	match state:
		"buffering", "stalled":
			if first_step < 0 and wait_text != "":
				return wait_text
			return Live.TXT_SYNC
		"error":
			return TXT_ERROR
	return ""


func _update_label() -> void:
	var t := status_text()
	if t == "" and _sync_lbl == null:
		return
	if _sync_lbl == null or not is_instance_valid(_sync_lbl):
		if battle._ui_layer == null:
			return
		_sync_lbl = Label.new()
		_sync_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_sync_lbl.position = Vector2(-60, 96)
		_sync_lbl.size = Vector2(120, 28)
		_sync_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sync_lbl.add_theme_font_size_override("font_size", 18)
		_sync_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battle._ui_layer.add_child(_sync_lbl)
	_sync_lbl.text = t
	_sync_lbl.visible = t != ""


## 地图种子: 流里的(keyframe 全局 seed)与开播时给的不同 ⇒ 地图选错了(门禁要量)。
func seed_mismatch() -> bool:
	return _seed_seen >= 0 and _seed_seen != int(battle._battle_rng.seed)


## 地图主题: 流里的与手机建的不同(播放入口没给对种子 / 正式对局判定不同)。
func theme_mismatch() -> bool:
	return _theme_seen != "" and _theme_seen != str(ArenaTheme.active)
