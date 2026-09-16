extends Node
## _probe_timestop_lanes.gd — 059 沙漏在【上路 / 下路 / 终极战场】三个战场里到底发生了什么(探针, 不进门禁)
##
## 由来: 用户 2026-09-16 实测「沙漏有严重 bug, 需要对上战场, 下战场, 终极战场进行细节观测」。
## 读代码读出来的两条【怀疑】—— 本探针要的是真实对局里的证据, 不是推理:
##   ① `_ts_fired` 全仓没有任何地方重置回 false(timestop_system.gd:27/78/92 是它仅有的三处出现),
##      而换路清场(dual_lane_flow.gd:937-945)也没碰它 ⇒ 怀疑「整场只触发一次」, 下路与终极战场再无时停。
##   ② 换路只清 `_ts_charge_casters`, 没清 `_ts_charging` / `_ts_charge_t` ⇒ 怀疑蓄力中换路会让下一路把释放吞掉
##      (`_ts_fire()` 见 casters 为空直接 return, 而 `_ts_fired` 仍是 true ⇒ 这一整场沙漏白买)。
##
## 跑法(必须 headless —— 本机开 3D 窗口有 BSOD 记录):
##   SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260916 TURTLE_BACKEND=" " APPDATA=<隔离目录> \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_timestop_lanes.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FRAME_CAP := 18000

var _rows: Array = []
var _lane_stat: Dictionary = {}

## 时停时长核对用(见循环里的说明)
var _ts_f0 := -1
var _ts_f1 := -1
var _ts_total_at_fire := 0.0
var _ts_rem_at_fire := 0.0
var _ts_rem_last := 0.0
var _ts_frozen_by_hitstop := 0


func _lane_row(lane: String) -> Dictionary:
	if not _lane_stat.has(lane):
		_lane_stat[lane] = {"charge_frames": 0, "active_frames": 0, "active_max": 0,
			"t0": -1.0, "t1": -1.0, "fired_at_entry": false}
	return _lane_stat[lane]


## 分母诊断: 这一路开打后场上【真的】有谁、各带什么装 —— 探针自己配错环境同样表现成「效果没生效」,
## 第一版探针就是因为阵容被判不合法换成默认阵容(059 跟着丢), 跑出「全程没时停」的假结论。
func _dump_units(s, lane: String) -> void:
	print("── [%s] 场上单位(分母检查) ──" % lane)
	var n59 := 0
	for u in s._units:
		if not (u is Dictionary):
			continue
		var eqs: Array = u.get("equips", []) if u.get("equips", null) is Array else []
		var ids: Array = []
		for e in eqs:
			if not (e is Dictionary):
				continue
			ids.append("%s★%d" % [str((e as Dictionary).get("id", "?")), int((e as Dictionary).get("star", 1))])
			if str((e as Dictionary).get("id", "")) == "p2eq_059":
				n59 += 1
		print("  %-6s %-10s trainer=%-5s equips=%s" % [str(u.get("side", "?")), str(u.get("name", "?")),
			str(u.get("is_trainer", false)), str(ids)])
	print("  ⇒ 这一路场上带 059 的单位数 = %d(为 0 则本路本来就不该有时停, 不构成 bug 证据)" % n59)
	## 演出叠加层还在不在、可不可见 —— 换路清场把它们 visible=false 了, 而全仓没有一处写回 true。
	## 灰世界 / 能量波 / 空间扭曲 / 停摆钟都挂在 _ts_overlay, 反色闪挂在 _ts_flash_overlay:
	## 这两层只要是隐藏的, 后面就算逻辑上真定格了也【一个画面都没有】。
	var ts = s._timestop
	for nm in ["_ts_overlay", "_ts_flash_overlay"]:
		var ly = ts.get(nm)
		print("  %s: 存在=%s 可见=%s" % [nm, str(is_instance_valid(ly)),
			str(ly.visible) if is_instance_valid(ly) else "n/a"])


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[FAIL] 没有 GameState")
		get_tree().quit(1)
		return
	gs.test_mode = true   # 台子/探针一律先置位, 绝不写玩家存档

	## 阵容两种模式(`PROBE_MODE` 环境变量):
	##   默认(split)   上路 = 带 059 3★ 的统领 + 1 小将; 下路 = 2 统领 + 1 小将 —— 实测四个种子全是 2-0, 打不到终极战场。
	##   final        三个统领全堆上路、下路只留一个小将 ⇒ 上路赢下路输 = 1-1 ⇒ **进终极战场**。
	##                (`dual_lane_needs_final()` 只认 1-1; 2-0 会走 `_dl_finish` 横扫收场, 终极路根本不建。)
	var _star := int(OS.get_environment("PROBE_STAR")) if OS.has_environment("PROBE_STAR") else 3
	var eq59: Array = [{"id": "p2eq_059", "star": clampi(_star, 1, 3)}]
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var mode: String = OS.get_environment("PROBE_MODE") if OS.has_environment("PROBE_MODE") else "split"
	if mode == "final":
		gs.dual_lineup = {
			"top": [
				{"kind": "leader", "slot": 0, "id": "basic", "equips": eq59.duplicate(true)},
				{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
				{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			],
			"bottom": [
				{"kind": "minion", "role": "front", "equips": []},
			],
		}
	elif mode == "both" or mode == "charge":
		## ★对照组: 上路和下路【各有一个】059★3 携带者。
		##   没有这一组, 「下路没时停」就不算 bug 证据 —— split 组的下路分母本来就是 0(没人带 059)。
		gs.dual_lineup = {
			"top": [
				{"kind": "leader", "slot": 0, "id": "basic", "equips": eq59.duplicate(true)},
				{"kind": "minion", "role": "front", "equips": []},
			],
			"bottom": [
				{"kind": "leader", "slot": 1, "id": "stone", "equips": eq59.duplicate(true)},
				{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
				{"kind": "minion", "role": "front", "equips": []},
			],
		}
	else:
		gs.dual_lineup = {
			## ★slot 必须写: `GameState._dl_structure_ok` 要求三个统领的 slot 恰好覆盖 0/1/2,
			##   少了它整份阵容会被判不合法 → 换成默认阵容, 装备跟着一起丢(第一版探针就栽在这)。
			"top": [
				{"kind": "leader", "slot": 0, "id": "basic", "equips": eq59.duplicate(true)},
				{"kind": "minion", "role": "front", "equips": []},
			],
			"bottom": [
				{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
				{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
				{"kind": "minion", "role": "front", "equips": []},
			],
		}
	gs.season_level = 5
	gs.hearts = 8
	gs.season_total_battles = 12

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260916
	gs.dual_ghost = Backend.make_bot(5, rng)   # 对手: 同档机器人快照
	gs.reset_dual_lane()
	gs.dual_active = true

	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	var ts = s._timestop

	## 分母诊断: 开打后我方单位【真的】带了什么装备 —— 探针自己配错环境也会表现成「效果没生效」
	for _w in range(120):
		await get_tree().process_frame
		if (s._units as Array).size() > 0:
			break
	_dump_units(s, str(gs.current_lane))

	## 【D 的实拍 A/B】"uniform 喂进去了"不等于"画面真的扭了"(fb-verify-artifact-not-steps)。
	##   判据: **同一时刻、只改 warp 一个参数**, 看画面差多少像素 —— 其它全不动, 所以差异只能是扭曲造成的。
	##   必须开窗口(headless 是 dummy 渲染器, 截出来是空的)。
	if mode == "shot":
		## 不等真时停触发: warp 这条路径与"时停有没有开始"无关(叠加层一建好就在画 world_tex),
		## 等真时停只会把窗口模式跑到超时。把除 warp 外的所有效果参数全部按到 0 ⇒ 两张图的唯一差别只能是扭曲。
		s._timestop._ts_ensure_overlay()
		var _m2: ShaderMaterial = s._timestop._ts_rect.material
		for _k in ["amount", "wave_a", "violet", "hue_flip", "zoom_blur", "core_flash"]:
			_m2.set_shader_parameter(_k, 0.0)
		var _shots: Array = []
		for _w in [0.0, 1.0]:
			_m2.set_shader_parameter("warp", _w)
			_m2.set_shader_parameter("warp_r", 0.45)
			for _i in range(8):
				await RenderingServer.frame_post_draw
			var _img: Image = get_viewport().get_texture().get_image()
			if _img == null:
				print("[FAIL] 截不到图 —— 这一跑不提供证据")
				get_tree().quit(1)
				return
			_shots.append(_img)
			_img.save_png("user://ts_warp_%d.png" % int(_w * 10))
		var _a: Image = _shots[0]
		var _b: Image = _shots[1]
		var _diff := 0
		var _tot := 0
		var _maxd := 0.0
		var _nonblack := 0
		for _y in range(0, _a.get_height(), 2):
			for _x in range(0, _a.get_width(), 2):
				_tot += 1
				var _c1 := _a.get_pixel(_x, _y)
				var _c2 := _b.get_pixel(_x, _y)
				if _c1.r + _c1.g + _c1.b > 0.06:
					_nonblack += 1
				var _d: float = absf(_c1.r - _c2.r) + absf(_c1.g - _c2.g) + absf(_c1.b - _c2.b)
				_maxd = maxf(_maxd, _d)
				if _d > 0.02:
					_diff += 1
		print("── [D 实拍] warp=0 vs warp=1(同一画面, 只改这一个参数) ──")
		print("  ★分母: 采样 %d 点, 其中非黑 %d 点(%.1f%%) —— 非黑近 0 说明截到的是空屏, 那这次比对没有意义"
			% [_tot, _nonblack, 100.0 * float(_nonblack) / maxf(1.0, float(_tot))])
		print("  变了的 %d 点 = %.2f%%, 单点最大色差 %.3f" % [_diff, 100.0 * float(_diff) / maxf(1.0, float(_tot)), _maxd])
		print("  截图目录: %s" % ProjectSettings.globalize_path("user://"))
		print("PROBE_DONE")
		get_tree().quit(0)
		return

	## 【D 的验证】shader 能不能真编译 —— 必须【开窗口】跑: headless 用 dummy 渲染器, shader 压根不编译,
	##   报不出错 ⇒ 拿 headless 全绿当"shader 没问题"是假绿灯。走真入口 `_ts_ensure_overlay()`,
	##   不自己另抄一份 shader 字符串(抄的那份永远落后)。编译失败 Godot 会往 stderr 打 SHADER ERROR。
	if mode == "shader":
		s._timestop._ts_ensure_overlay()
		for _i in range(30):
			await get_tree().process_frame
		var _rect = s._timestop._ts_rect
		var _m: ShaderMaterial = _rect.material if is_instance_valid(_rect) else null
		print("── [D] 灰世界叠加层 ──")
		print("  _ts_rect 存在=%s  material=%s" % [str(is_instance_valid(_rect)), str(_m != null)])
		if _m != null:
			var _code: String = _m.shader.code
			print("  shader 里 warp 出现 %d 次 / warp_r %d 次 / zoom_blur %d 次 (三个都 >1 才说明 fragment 真在用)"
				% [_code.count("warp"), _code.count("warp_r"), _code.count("zoom_blur")])
			print("  world_tex 参数 = %s (null 就是没喂进去, 画面会全黑)" % str(_m.get_shader_parameter("world_tex")))
			print("  还在读屏吗(hint_screen_texture) = %s (应为 false)" % str(_code.contains("hint_screen_texture")))
			_m.set_shader_parameter("warp", 1.0)
			_m.set_shader_parameter("warp_r", 0.5)
			for _i in range(10):
				await get_tree().process_frame
			print("  喂 warp=1.0 跑 10 帧后回读 = %s" % str(_m.get_shader_parameter("warp")))
		print("PROBE_DONE")
		get_tree().quit(0)
		return

	## 【怀疑②】蓄力中换路。自然对局里上路恰好在第 10.0~11.0 秒结束的概率太低, 所以由探针主动切 ——
	##   但必须走【产品真入口】`_dl_lane_over()`(`_dl_present_advance` 的 lane_settle 分支调的就是它),
	##   不许自己手搓清场, 否则量的是我写的清场而不是产品的清场。
	if mode == "charge":
		var waited := 0
		while waited < 3000 and not bool(ts._ts_charging):
			await get_tree().process_frame
			waited += 1
		print("── [怀疑②] 等到蓄力中: 第 %d 帧, t=%.2f, charging=%s, 蓄力剩 %.2f 秒, casters=%d"
			% [waited, float(s._t), str(ts._ts_charging), float(ts._ts_charge_t), (ts._ts_charge_casters as Array).size()])
		if bool(ts._ts_charging):
			s._dl_sys._dl_lane_over("right")   # 右边输 → 上路结束 → 真清场 → 进下路
			print("   ↳ 刚换完路: lane=%s fired=%s charging=%s charge_t=%.2f casters=%d"
				% [str(gs.current_lane), str(ts._ts_fired), str(ts._ts_charging),
				float(ts._ts_charge_t), (ts._ts_charge_casters as Array).size()])

	var last_lane := ""
	var last_state := ""
	var fr := 0
	var dump_at := -1          # 换路后第 N 帧再打分母(等新一路 spawn 完, 别把上一路的残影当新场上单位)
	while fr < FRAME_CAP and str(s._dl_state) != "done":
		await get_tree().process_frame
		fr += 1
		if fr == dump_at:
			_dump_units(s, str(gs.current_lane))
		var lane := str(gs.current_lane)
		var st := str(s._dl_state)
		var row: Dictionary = _lane_row(lane)
		if float(row["t0"]) < 0.0:
			row["t0"] = float(s._t)
			row["fired_at_entry"] = bool(ts._ts_fired)
		row["t1"] = float(s._t)
		if bool(ts._ts_charging):
			row["charge_frames"] = int(row["charge_frames"]) + 1
			## 【用户问: 每一路都是在第几秒开始时停】记下本路【第一次】进入蓄力与第一次定格的时刻,
			## 并换算成"本战场已打了几秒"(= battle._t - battle._sd_t0, 正是产品判据用的那个量)。
			if not row.has("charge_at"):
				row["charge_at"] = float(s._t)
				row["charge_lane_sec"] = float(s._t) - float(s._sd_t0)
				row["sd_t0"] = float(s._sd_t0)
		var act: int = (ts._ts_active as Array).size()
		if act > 0:
			row["active_frames"] = int(row["active_frames"]) + 1
			if not row.has("froze_at"):
				row["froze_at"] = float(s._t)
				row["froze_lane_sec"] = float(s._t) - float(s._sd_t0)
		row["active_max"] = maxi(int(row["active_max"]), act)
		## 【时长核对】用户 2026-09-16 问「确定时停时间正确吗」。
		## ★不能拿"定格帧数 ÷ 60"当结论就完事 —— 那只说明【我数了几帧】, 说不清多出来的帧是哪来的。
		##   所以同时记 `_ts_remaining` 的首帧值(应 = TS_DUR[星级-1])与末帧值, 首末帧号之差 = 真正的定格跨度。
		##   det 模式每帧恰 1 个 SIM_DT(=1/60) 步 ⇒ 帧数 ↔ 游戏秒是 1:1 可换算的(交互模式 sim 也走同一固定步长)。
		if act > 0 and _ts_f0 < 0:
			_ts_f0 = fr
			_ts_total_at_fire = float(ts._ts_total)
			_ts_rem_at_fire = float(ts._ts_remaining)
		if act > 0:
			_ts_f1 = fr
			_ts_rem_last = float(ts._ts_remaining)
			## 【C 的判据】定格【期间】演出层可不可见 —— 换路后那个采样点看不出来(那时还没触发),
			## 必须在真的定格着的时候量。两层只要有一帧是隐藏的, 这一路就是"有定格没画面"。
			for _nm in ["_ts_overlay", "_ts_flash_overlay"]:
				var _ly = ts.get(_nm)
				if is_instance_valid(_ly) and not _ly.visible:
					row["vis_hidden"] = int(row.get("vis_hidden", 0)) + 1
			## 定格比设定长出来的那几帧去哪了: `_sim_step` 里是 `if frozen: ... elif in_ts: _ts_remaining -= dt`
			## —— 二选一 ⇒ 顿帧(hit-stop)的每一帧, 时停倒计时【不走】, 而 `_ts_active` 还在 ⇒ 定格被白白拉长。
			if float(s._hitstop) > 0.0:
				_ts_frozen_by_hitstop += 1
		if lane != last_lane and last_lane != "":
			dump_at = fr + 90
		if lane != last_lane or st != last_state:
			_rows.append("f%-6d t=%7.2f  战场=%-7s 流程=%-10s | fired=%-5s charging=%-5s active=%d 剩=%.2f"
				% [fr, float(s._t), lane, st, str(ts._ts_fired), str(ts._ts_charging), act, float(ts._ts_remaining)])
			last_lane = lane
			last_state = st

	print("── 流程时间线 ──")
	for r in _rows:
		print("  ", r)
	print("── 每个战场里的时停 ──")
	var lanes: Array = _lane_stat.keys()
	lanes.sort()
	for lane in lanes:
		var d: Dictionary = _lane_stat[lane]
		print("  战场 %-7s 游戏时钟 %6.2f → %6.2f 秒 | 进这一路时 fired=%-5s | 蓄力帧 %4d | 定格帧 %5d | 同时可动人数上限 %d"
			% [lane, float(d["t0"]), float(d["t1"]), str(d["fired_at_entry"]),
			int(d["charge_frames"]), int(d["active_frames"]), int(d["active_max"])])
		print("      └ 定格期间演出层被隐藏的帧数 = %d(必须为 0, 否则就是有定格没画面)" % int(d.get("vis_hidden", 0)))
		if d.has("charge_at"):
			print("      └ 本路开打时刻 _sd_t0=%.2f | 开始蓄力 _t=%.2f(本路第 %.2f 秒) | 真正定格 _t=%.2f(本路第 %.2f 秒)"
				% [float(d.get("sd_t0", -1.0)), float(d["charge_at"]), float(d["charge_lane_sec"]),
				float(d.get("froze_at", -1.0)), float(d.get("froze_lane_sec", -1.0))])
		else:
			print("      └ 本路没触发过时停")
	print("── 时停时长核对(det 模式: 1 帧 = 1 个 SIM_DT = 1/60 游戏秒) ──")
	var star := int(OS.get_environment("PROBE_STAR")) if OS.has_environment("PROBE_STAR") else 3
	var want: float = [4.0, 7.0, 20.0][clampi(star, 1, 3) - 1]
	if _ts_f0 < 0:
		print("  ⚠ 整场一次都没定格 —— 这一跑不提供时长证据")
	else:
		var span: int = _ts_f1 - _ts_f0 + 1
		print("  星级 %d ⇒ 设定 TS_DUR = %.2f 秒" % [star, want])
		print("  定格首帧 f%d(此时 _ts_total=%.4f, _ts_remaining=%.4f) → 末帧 f%d(_ts_remaining=%.4f)"
			% [_ts_f0, _ts_total_at_fire, _ts_rem_at_fire, _ts_f1, _ts_rem_last])
		print("  其中【顿帧 hit-stop】帧数 = %d ⇒ 这些帧 _ts_remaining 不扣, 定格被拉长 %.4f 秒"
			% [_ts_frozen_by_hitstop, float(_ts_frozen_by_hitstop) / 60.0])
		print("  跨度 %d 帧 = %.4f 游戏秒 | 与设定差 %+.4f 秒(%+.2f%%)"
			% [span, float(span) / 60.0, float(span) / 60.0 - want, (float(span) / 60.0 / want - 1.0) * 100.0])
	print("── 收场状态 ──")
	print("  跑了 %d 帧, _dl_state=%s, lane_results=%s" % [fr, str(s._dl_state), str(gs.lane_results)])
	print("  _ts_fired=%s _ts_charging=%s _ts_charge_t=%.2f _ts_active=%d _ts_remaining=%.2f"
		% [str(ts._ts_fired), str(ts._ts_charging), float(ts._ts_charge_t), (ts._ts_active as Array).size(), float(ts._ts_remaining)])
	print("PROBE_DONE")
	get_tree().quit(0)
