extends Node
## verify_stream_hud_parity.gd — 逐帧直播: 播放端的 HUD 与「本机直接跑」在同一步一致。
## 方案书 docs/plans/20261019-服务器逐帧直播.md §2.5「播放端 HUD」。
##
## 同一进程: 先原生跑一局裁判局(同时录流, 块留在内存), 每 EVERY 步拍一张 HUD 快照(tests/_stream_hud.gd);
## 再按流播, 在同一批步号拍同样的快照, 逐项比:
##   · `_ui_layer` 下所有可见文本(路名计时牌 / 名字 / PK 条百分比与血量 / 头像框名字与等级 / 羁绊档位 / 幕布内容 / 加时徽章 …)
##   · 可见贴图(头像 / 装备格图标 / 顶栏头像 / 路点)
##   · 头顶血条(hp% / 盾 / 龟能条宽 / 显隐)、头像框栏(顺序 / 血条比例 / 死亡变暗 / 装备格图标)、法术圆盘(图标 / 冷却 / 层数)、PK 条采样值
## ★分母: 每局比过的采样点数、文本数、头像框数、装备格图标数、龟能条数都 > 0, 圆盘至少出现过一次。
## 覆盖: tests/_stream_jobs.gd 两局(三路打满, 镜像局 + 真实快照局)。

const J := preload("res://tests/_stream_jobs.gd")
const P := preload("res://tests/_stream_play.gd")
const H := preload("res://tests/_stream_hud.gd")
const SIM_DT := 1.0 / 60.0
const EVERY := 60
## 入口(stream_watch.enter)给的两个名字。服务器本机跑时顶栏写的是服务器自己的账号名, 没有意义 ⇒ 名字不跟本机比, 跟这两个比。
const NAMES := {"l": "甲方玩家", "r": "乙方玩家"}

var _fail := 0
var _charge_tot := 0
var _dots_seen := {}
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var only := OS.get_environment("HUD_ONLY")
	for jj in [["镜像快照局", "m"], ["真实快照局(最重)", "h"]]:
		if only != "" and only != str(jj[1]):
			continue
		var job: Dictionary = J.mirror(gs) if str(jj[1]) == "m" else J.heavy()
		var nat: Dictionary = await _record(job)
		var res: Dictionary = nat["res"]
		_ok("分母 · %s 原生一遍三路打满、录到块" % str(jj[0]), bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3
			and (res.get("stream_chunks", []) as Array).size() > 100, "开打 %d" % int(res.get("fights", 0)))
		await _play_and_compare(str(jj[0]), res.get("stream_chunks", []), res.get("stream", {}), nat)
	_finish()


## 原生一遍: 裁判局 + 录流, 每 EVERY 步拍 HUD 快照(键 = sim 步号)
func _record(job: Dictionary) -> Dictionary:
	var snaps := {}
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if rec._step_n % EVERY <= 2:
					var ub := {}
					for i in range(rec._uk.size()):
						for v in (bt._units as Array):
							if is_same(v, rec._uk[i]):
								ub[i] = v
								break
					snaps[s] = H.snap(bt, ub)
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var st := {}
	var b64 := str(res.get("replay_b64", ""))
	if b64 != "":
		st = (ReplayRecorder.decode(Marshalls.base64_to_raw(b64)) as Dictionary).get("state", {})
	return {"res": res, "snaps": snaps, "state": st, "seed": RefereeJob.seed_of(job)}


func _play_and_compare(tag: String, chunks: Array, meta: Dictionary, nat: Dictionary) -> void:
	print("=== %s ===" % tag)
	var gs = get_node_or_null("/root/GameState")
	var backup: Dictionary = ReplayRecorder.capture_all()
	var au = get_node_or_null("/root/Audio")
	var muted0: bool = bool(au.mute_sfx) if au != null else false
	if au != null:
		au.mute_sfx = true
	var pn0: Dictionary = ReplayRecorder.play_names
	ReplayRecorder.play_names = NAMES.duplicate()
	var b: Node = P.make_player_battle(self, chunks, meta, int(nat["seed"]), nat.get("state", {}))
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · %s 播放模式建起来了" % tag, p != null and str(b._replay.mode) == "stream")
	if p == null or p.mirror == null or p.hud == null:
		return
	var snaps: Dictionary = nat["snaps"]
	var keys: Array = snaps.keys()
	keys.sort()
	var cmp := 0
	var elems := 0
	var bad: Array = []
	var boundary := 0
	var plates := 0
	var names_ok := 0
	var names_bad: Array = []
	var hdr_swaps := 0
	var hint_n := 0
	var built_at_frame := 0
	var fresh_n := 0
	var hint_bad := 0
	var tot := {"texts": 0, "texs": 0, "units": 0, "frames": 0, "icons": 0, "charge": 0, "disc": 0}
	var ki := 0
	var guard := 0
	p.advance(0.0)
	while ki < keys.size() and p.state != "error" and guard < 200000:
		guard += 1
		var nxt: int = int(keys[ki])
		var hd := int(roundf(p.head))
		if nxt <= hd:
			ki += 1
			continue
		## 每次推 2 步(= 服务器渲染步的节拍): 播放头落在采样步上, 两边的渲染步对齐(HUD 是渲染步里刷的)
		p.advance(2.0 * SIM_DT)
		## 这次渲染步刷头像框血条时, 新框排过版没有(排版要等一帧): 自上次等帧以来重建过 ⇒ 没排过
		var fresh := p.hud.panels_built != built_at_frame
		if int(roundf(p.head)) % 30 == 0:
			await get_tree().process_frame
			built_at_frame = p.hud.panels_built
		if int(roundf(p.head)) == nxt:
			var mine: Dictionary = H.snap(b, p.units, [p._sync_lbl])
			## 名字: 播放端顶栏 = 入口给的名字(本机那边是服务器自己的账号名, 不比)
			var nm: Array = mine["names"]
			if nm.size() == 2 and str(nm[0]) == NAMES["l"] and str(nm[1]) == NAMES["r"]:
				names_ok += 1
			else:
				names_bad.append("步%d %s" % [nxt, str(nm)])
			## 幕布对阵行的列头: 本机写「我方 / 对方」, 播放端写入口给的名字 ⇒ 换回来再比(换了几次要 > 0)
			var tx: Dictionary = mine["texts"]
			for pair in [[NAMES["l"], "我方"], [NAMES["r"], "对方"]]:
				var k0 := "PresentPanel|" + str(pair[0])
				if tx.has(k0):
					var k1 := "PresentPanel|" + str(pair[1])
					tx[k1] = int(tx.get(k1, 0)) + int(tx[k0])
					tx.erase(k0)
					hdr_swaps += 1
			## 「点击继续」: 播放端点不动(只认服务器那一下) ⇒ 不出这一行; 本机那边有 ⇒ 记分母后从本机拿掉
			var hint_k := "PresentPanel|点击继续"
			if tx.has(hint_k):
				hint_bad += 1
			if (snaps[nxt]["texts"] as Dictionary).has(hint_k):
				hint_n += 1
				(snaps[nxt]["texts"] as Dictionary).erase(hint_k)
			var dd: Dictionary = H.diff(snaps[nxt], mine, "步%d" % nxt, fresh)
			if fresh:
				fresh_n += 1
			boundary += int(dd["boundary"])
			if not (snaps[nxt]["plate"] as Array).is_empty() and str(snaps[nxt]["plate"][0]) != "":
				plates += 1
			cmp += 1
			elems += int(dd["n"])
			bad.append_array(dd["bad"])
			var c: Dictionary = H.count(snaps[nxt])
			for k in tot:
				tot[k] = int(tot[k]) + int(c[k])
			for x in (snaps[nxt]["pk"] as Array).slice(6):
				_dots_seen[str(x)] = true
			ki += 1
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		p.advance(2.0 * SIM_DT)
	var steps := int(meta.get("steps", 0))
	_charge_tot += int(tot["charge"])
	print("  [量] %s HUD 采样点 %d · 元素 %d · 文本 %d · 贴图键 %d · 头顶血条 %d · 头像框 %d · 装备格图标 %d · 充能条 %d · 圆盘出现 %d 次" % [tag, cmp, elems,
		int(tot["texts"]), int(tot["texs"]), int(tot["units"]), int(tot["frames"]), int(tot["icons"]), int(tot["charge"]), int(tot["disc"])])
	_ok("分母 · %s 播到结尾、比过的采样点 %d ≥ %d" % [tag, cmp, maxi(3, steps / EVERY - 1)], p.state == "ended" and cmp >= maxi(3, steps / EVERY - 1), "%s %s" % [p.state, p.err])
	_ok("分母 · %s HUD 各类元素都比到了(文本 %d / 头像框 %d / 装备格图标 %d / 头顶血条 %d / 圆盘 %d)" % [tag,
		int(tot["texts"]), int(tot["frames"]), int(tot["icons"]), int(tot["units"]), int(tot["disc"])],
		int(tot["texts"]) > 0 and int(tot["frames"]) > 0 and int(tot["icons"]) > 0 and int(tot["units"]) > 0 and int(tot["disc"]) > 0)
	if OS.get_environment("HUD_DIAG") != "":
		var seen := {}
		for x in bad:
			var kk := str(x).substr(str(x).find(" ") + 1).left(120)
			if not seen.has(kk):
				seen[kk] = true
				print("    [诊断] ", str(x).left(600))
			if seen.size() > 60:
				break
	_ok("★★%s HUD 在同一步一致(%d 个元素·点)" % [tag, elems], bad.is_empty(), "差 %d 处 · %s" % [bad.size(), str(bad.slice(0, 3))])
	## 路名计时牌: 整秒边界那一步允许差一秒(流里 t 是 float32); 但这种情况必须罕见, 且有分母
	_ok("★%s 路名计时牌 %d 次有字, 其中整秒边界差一秒 %d 次(≤ 5%%)" % [tag, plates, boundary], plates > 0 and boundary * 20 <= plates)
	_ok("★★%s 顶栏名字 = 入口给的名字(%d / %d 点)" % [tag, names_ok, cmp], names_bad.is_empty() and names_ok > 0, str(names_bad.slice(0, 3)))
	_ok("★%s 幕布对阵行列头写的是入口给的名字(%d 次)" % [tag, hdr_swaps], hdr_swaps > 0)
	print("  [量] %s 建栏当步(只不比头像框血条比例)%d 个采样点 · 头像框栏重建 %d 次 · 装备字段收到 %d 次" % [tag, fresh_n, p.hud.panels_built, p.hud.equips_set])
	_ok("分母 · %s 头像框栏重建过(%d 次, 每路至少一次)、建栏当步 %d ≤ 3" % [tag, p.hud.panels_built, fresh_n], p.hud.panels_built >= 3 and fresh_n <= 3)
	_ok("★%s 幕布不出「点击继续」(本机有它的采样点 %d 个, 播放端出现 %d 次)" % [tag, hint_n, hint_bad], hint_n > 0 and hint_bad == 0)
	b.queue_free()
	ReplayRecorder.play_names = pn0
	await get_tree().process_frame
	await get_tree().process_frame
	for k in backup:
		var v = backup[k]
		gs.set(str(k), v.duplicate(true) if (v is Array or v is Dictionary) else v)
	gs.test_mode = true
	if au != null:
		au.mute_sfx = muted0


func _finish() -> void:
	if OS.get_environment("HUD_ONLY") == "":
		_ok("分母 · 装备格充能条比到了 %d 个 · 路点颜色出现过 %d 种(没打 / 我方赢 / 对方赢)" % [_charge_tot, _dots_seen.size()],
			_charge_tot > 0 and _dots_seen.size() >= 3)
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 播放端 HUD 与本机直接跑在采样点一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
