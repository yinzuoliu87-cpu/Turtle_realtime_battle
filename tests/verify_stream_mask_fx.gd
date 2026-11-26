extends Node
## verify_stream_mask_fx.gd —— 面具批的单位着色与里世界按钮: 看直播(积分赛跟播 / 观战 / 录像)时与本机一样画(11-26 夜)
##
## 由来: 记忆 fb-sim-path-2d-ui-missing-in-stream-1122 —— 播放端不跑 sim, sim 步里建的 2D 界面一个都没有, 只镜像 3D 节点 + 录过的事件。
##   面具批新加的几样都可能踩:
##     · 单位着色按单位字段算(battle_render): 134 威尼斯倒地半透明(_ven_until / _ven_t0)、偷脸复制体偏蓝(_body_tint)、
##       136 被偷属性发灰(_ow_drained)、132 鬼面潜行(_ghost_hidden + untargetable_until) —— 字段不在录流名单就画不出
##     · 136 里世界: 「不在观众正在看的那个世界 ⇒ 隐去」问的是 sim 侧对象; 切换按钮是 sim 步里建的 2D 节点
## 做法同 verify_stream_head_badges: 裁判入口本机跑一局并录流 → 按跟播入口播刚录的流; 同一批采样步上分类数单位立绘, 再数里世界按钮。
## 由探针 tests/probes/_probe_stream_mask 转来: 修之前 本机隐去 178 / 播放 0 · 里世界按钮 89 / 0(其余几类当时碰巧对得上)。
## 判据:
##   ⓪ 分母: 五类在本机都出现过(数到 0 = 空检查)
##   ① 每一类: 播放端与本机在同一批采样步上的计数之差 ≤ 本机的 5%
## 反向验证(11-26 夜): 见文件尾注释。

const W := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")
const FMT := preload("res://scripts/systems/stream/stream_format.gd")
const SIM_DT := 1.0 / 60.0
const CATS := ["隐去", "半透明", "偏蓝", "发灰", "里世界按钮"]

var _nat := {}
var _nat_tot := {}
var _pl_tot := {}
var _steps := 0
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("" if cond or detail == "" else "  " + detail)])


static func _eqs(ids: Array) -> Array:
	var o: Array = []
	for i in ids:
		o.append({"id": "p2eq_%03d" % int(i), "star": 2})
	return o


func _cat(b: Node, unit_list: Array) -> Dictionary:
	var by := {}
	for u in unit_list:
		if not (u is Dictionary) or not (u as Dictionary).get("alive", false):
			continue
		var spr = (u as Dictionary).get("sprite", null)
		if not is_instance_valid(spr):
			continue
		var m: Color = (spr as Sprite3D).modulate
		var k := ""
		if m.a < 0.05:
			k = "隐去"
		elif m.b > m.r * 1.5 and m.b > 0.9:
			k = "偏蓝"          # 偷脸复制体(先判颜色: 它带 0.75 透明度, 放后面会被归进半透明)
		elif m.r < 0.75 and m.g < 0.7 and m.b < 0.8:
			k = "发灰"
		elif m.a < 0.85:
			k = "半透明"
		if k != "":
			by[k] = int(by.get(k, 0)) + 1
	for c in b._ui_layer.get_children():
		if c is Button and (c as Button).visible and str((c as Button).tooltip_text).contains("世界"):
			by["里世界按钮"] = int(by.get("里世界按钮", 0)) + 1
	return by


func _add(tot: Dictionary, by: Dictionary) -> void:
	for k in by:
		tot[k] = int(tot.get(k, 0)) + int(by[k])


func _ready() -> void:
	print("=== verify_stream_mask_fx ===")
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var w = W.new()
	var a: Dictionary = w._snap(gs, ["stone", "lava", "candy"], [_eqs([136, 134, 132]), _eqs([135, 130, 129]), _eqs([127, 131, 133])], "g_mk_a", "甲", 0)
	var b2: Dictionary = w._snap(gs, ["bubble", "hunter", "ninja"], [_eqs([137, 138, 139]), _eqs([140, 141, 142]), _eqs([143, 144, 145])], "g_mk_b", "乙", 1)
	w.free()
	await _run_one(J.job(a, b2, 7260001))
	print("")
	print("  采样步 %d" % _steps)
	print("  本机 %s" % str(_nat_tot))
	print("  播放 %s" % str(_pl_tot))
	for k in CATS:
		_ok("⓪ 分母 · 本机画过「%s」(%d 次)" % [k, int(_nat_tot.get(k, 0))], int(_nat_tot.get(k, 0)) > 0)
	for k in CATS:
		var nv := int(_nat_tot.get(k, 0))
		var pv := int(_pl_tot.get(k, 0))
		_ok("① ★看直播时「%s」与本机一样(本机 %d / 播放 %d)" % [k, nv, pv], nv > 0 and absf(float(pv - nv)) <= float(nv) * 0.05,
			"播放端画得不一样 —— 积分赛跟播 / 观战 / 录像里玩家看到的不是本机那样")
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 面具批着色 / 里世界按钮直播一致" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run_one(job: Dictionary) -> void:
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if rec._step_n % FMT.CONT_EVERY != 0 or s % 6 != 0:
					return
				_nat[s] = _cat(bt, bt._units)
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("  本机一遍: %d 块 · 采样 %d 步" % [chunks.size(), _nat.size()])
	if chunks.is_empty():
		_ok("录到了流", false)
		return
	var gs = get_node_or_null("/root/GameState")
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, res.get("stream", {})), "seed": RefereeJob.seed_of(job), "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	if p == null:
		_ok("播放端建起来了", false)
		return
	var guard := 0
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		## 每次推 CONT_EVERY 步 = 与服务器渲染步同一节奏(服务器每个采样步渲染一次, 衰减 2·SIM_DT)。11-27: 原来每步推一次 ⇒
		##   闪白计时(0.06 秒)在采样那一刻比本机晚一档, 鬼面暗紫被残余 0.01 闪白拉过「发灰 / 半透明」分界(探针 tests/probes/_probe_mask_tint_diff)
		p.advance(SIM_DT * float(FMT.CONT_EVERY) if p.cur_step % FMT.CONT_EVERY == 0 else SIM_DT)   # 先单步对齐到采样步(偶数), 之后两步一推
		if _nat.has(p.cur_step):
			_add(_nat_tot, _nat[p.cur_step])
			_add(_pl_tot, _cat(b, p.units.values()))
			_steps += 1
			_nat.erase(p.cur_step)
		if guard % 60 == 0:
			await get_tree().process_frame
	b.queue_free()
	await get_tree().process_frame
