extends Node
## verify_sim_step_rate.gd — B 阶段门禁:【一帧喂 k 个 sim 步】时结果必须与【一帧 1 步】逐字相同。
##
## ══════════════════════════════════════════════════════════════════════════
##  ★为什么需要它: 全仓所有确定性门禁都跑在「恒 1 步/帧」下
## ══════════════════════════════════════════════════════════════════════════
## 2026-10-02 的现状调查(`docs/plans/20261002-B阶段确定性现状调查.md` §2.4)把四份门禁
## 摊开量过一遍, 结论是同一个洞:
##
##   · `verify_determinism_b` / `_cross` / `_battle_determinism` —— **全是 det 模式**。
##     det 的 `_process` 每帧恰调一次 `_sim_step(SIM_DT)`(主场景 :2182) ⇒ **恒 1 步/帧**。
##   · `verify_interactive_determinism` —— 主体 `set_process(false)` **纯同步喂**累加器,
##     一帧都不 pump ⇒ 14 处 `await get_tree().process_frame` 协程**全程挂着不动**;
##     它唯一 pump 帧的地方(`_measure_wait`)喂的也是 `_advance_sim_accum(1/60)` = **恰 1 步/帧**。
##
## ⇒ **全仓没有任何一条判据跑过「一帧 ≥2 个 sim 步 + 协程在推进」。**
## 而那正是 B2/B4 全部 14 处协程 + `_wait_sim` 的 25 个调用点所在的那条路:
## 它们的形状是「每渲染帧醒一次, 累加 `battle._frame_sim_dt`」——
## 一帧 1 步时 `_frame_sim_dt == SIM_DT`(与 det 无差别), 一帧 k 步时它变成 `k × SIM_DT`,
## 于是协程**一帧走 k 步的量**, 而它中间那些 `if traveled >= …` 的判定**只有帧粒度**。
## 这跟 memory `fb-headless-one-step-per-frame-hides-frame-keyed-bugs` 是同一个坑,
## 只不过这次藏住的不是「按帧号去重」, 是「按渲染帧累加 `_frame_sim_dt`」。
##
## ══════════════════════════════════════════════════════════════════════════
##  怎么量
## ══════════════════════════════════════════════════════════════════════════
## 同一份摆位 + 同一个 `TURTLE_SEED`, **唯一的变量是每帧喂几个 sim 步**:
##   · A 遍: 每帧 1 步 × N 帧
##   · B 遍: 每帧 k 步 × N/k 帧        (k = 2 / 3 / 4)
## 指纹**按 sim 步号 `_sim_step_n` 对齐**(不按帧号 —— 帧号本来就不一样), 在两遍都采到的
## 步号上逐个比对, 报【分叉步数 / 比对步数】与【首个分叉的 sim 步号】。
##
## ★驱动方式与两个盲点各打一半:
##   · `set_process(false)` + 自己喂 `_advance_sim_accum()` ⇒ 每帧步数**完全受控**
##   · **每帧之间 `await get_tree().process_frame`** ⇒ 协程真的醒、真的推进
##     (这正是 `verify_interactive_determinism` 缺的那一半)
##   · `TURTLE_SEED` 设着 ⇒ `_deterministic = true` ⇒ 演出 tween 由 `_step_sim_tweens`
##     按 sim 步喂。**不这样不行**: 交互模式下 tween 走 SceneTree 的真实 delta,
##     两遍的墙钟不可能一样 ⇒ 判据会因为"tween 快慢"而红, 和 k 一点关系都没有。
##   · 每帧先 `_sim_accum = 0.0` 再喂 `k × SIM_DT + 1e-9` ⇒ **恰好 k 步**。
##     不加那个 epsilon 的话 `3 × (1/60)` 的浮点值会差一点点进不去第三步
##     ⇒ 实际跑出 2/4/3/… 的抖动, 步号对不齐(本测的对齐靠"每帧恰 k 步")。
##     丢掉的余量在这里无所谓: sim 本身永远只按整 `SIM_DT` 步走。
##
## ★★这把尺子**先于代码**: 它红了不等于必须立刻改产品。
##   「红在哪一步、第几个 sim 步开始分叉」比强行改绿有价值得多 —— 照实报。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")

## ══════════════════════════════════════════════════════════════════════════
##  ★★★已知差距台账(2026-10-02 本机实测) —— **只减不增**
## ══════════════════════════════════════════════════════════════════════════
## 这把尺子**第一次跑就是红的**, 而且红得完全是现状调查预言的那个形状:
## 14 处对局协程全都是「每渲染帧醒一次, 把 `battle._frame_sim_dt` 一整帧的量一次加完」。
## ⇒ 一帧 k 步时, 协程**在同一个 sim 步上走到的位置不一样**(忍者冲击: 基准 x=320 /
##   k=2 时 330 / k=3 时 340 / k=4 时 350, 首个分叉在 sim 步 14~16),
##   而它那些 `if traveled >= h["proj"]` 的命中判定**只有帧粒度** ⇒
##   **命中落在不同的 sim 步** ⇒ 从 sim 步 66 起 hp/护盾 这类**结果字段**也不一样了。
##
## ★这不是"把它改绿"的事, 是 B2/B4 本体(把协程搬进 sim 队列)的事。
##   所以照 `verify_determinism_cross.gd` 的 `KNOWN_DIVERGE` 同一条纪律处理:
##   **存量记进台账, 只减不增**; 台账里每条都带实测数, 修好一条就把它划掉。
## ★台账**不许当垃圾桶**: 下面断言「台账里的 k 现在仍然在分叉」——
##   谁把协程搬进 sim 队列、这一条不分叉了, 门禁会红, 逼你来删这一行。
## ⚠ 这些数是**本机(Windows)实测**。CI(Linux) 没验过 —— 如果 CI 上对不上,
##   那本身就是新信息(**别放宽台账**, 去看为什么)。
const KNOWN_GAP := {
	## k: [全部分叉步数, 结果字段分叉步数, 比对步数]
	2: [294, 268, 300],
	3: [196, 179, 200],
	4: [147, 134, 150],
}

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond: print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 全场快照(与 verify_determinism_b 同一组字段: 对局状态, 不含纯演出)
func _fp(scene) -> String:
	var parts: Array = []
	var i := 0
	for u in scene._units:
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.2f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x),
			float((u.get("pos", Vector2()) as Vector2).y),
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)),
			float(u.get("energy", 0.0))])
		i += 1
	return "|".join(parts)


## ★摆位: 两条**协程位移**站点同时在场, 而且都在射程内 ——
##   · 忍者【冲击】(`ninja_system.gd:93 _ninja_glide`): 被动, 不花龟能, 开局就冲。
##     它命中主目标时写 `o["_ninja_dash_until"]`(:149) —— 那是产品自己的字段(两个读者:
##     `battle_render.gd:411` 画锁定标记、主场景 :6831 选靶) ⇒ **拿它当"协程真的推进过"的分母**。
##   · 双头【灵能冲击炮弹】(`two_head_system.gd:104`): 必须摆在射程内。
##     场景表 ④ 的注释已经踩过 —— 隔 580 码时弹丸在窗口内飞不到, "什么都没发生"在两遍之间
##     是一样的 ⇒ 判据看不见。这里 200 码。
func _pairs() -> Array:
	return [
		["ninja", "left", 320.0, 300.0],
		["two_head", "left", 320.0, 420.0],
		["basic", "right", 520.0, 300.0],
		["basic", "right", 520.0, 420.0]]


## 用【每帧 k 个 sim 步】驱动一局, 跑到 `_sim_step_n` 至少 target 步。
## 返回 {steps: {步号: 指纹}, frames, max_per_frame, max_frame_sim_dt, dash_marks, taken, last_step}
func _run(k: int, target: int) -> Dictionary:
	var SIM_DT: float = 1.0 / 60.0
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	## ★必须在建场之后、开打之前关掉 `_process`: 开着的话 det 模式会自己每帧跑 1 步,
	##   和我手喂的叠在一起 ⇒ "每帧 k 步"这个唯一变量就不唯一了。
	s.set_process(false)
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in _pairs():
		s._debug._edit_place_unit(str(p[0]), str(p[1]), Vector2(float(p[2]), float(p[3])))
	s._debug._edit_start_battle()
	var base: int = int(s._sim_step_n)
	var out: Dictionary = {}
	var frames := 0
	var max_pf := 0
	var max_fsd := 0.0
	var guard := 0
	while int(s._sim_step_n) - base < target and guard < target + 64:
		var before: int = int(s._sim_step_n)
		s._sim_accum = 0.0
		s._advance_sim_accum(float(k) * SIM_DT + 1.0e-9)
		await get_tree().process_frame
		frames += 1
		guard += 1
		max_pf = maxi(max_pf, int(s._sim_step_n) - before)
		max_fsd = maxf(max_fsd, float(s._frame_sim_dt))
		out[int(s._sim_step_n) - base] = _fp(s)
	## 分母用的产品字段: 忍者冲击真的命中过几个(协程推进到命中判定才会写)
	var dash := 0
	var taken := 0.0
	for u in s._units:
		if float(u.get("_ninja_dash_until", 0.0)) > 0.0: dash += 1
		taken += float(u.get("_st_taken", 0.0))
	var last: int = int(s._sim_step_n) - base
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return {"steps": out, "frames": frames, "max_per_frame": max_pf,
		"max_frame_sim_dt": max_fsd, "dash": dash, "taken": taken, "last_step": last}


## ★分叉要**分类**, 否则报出来的数没法用:
##   · 「相位」= 只有 `pos` 不同 —— 协程一帧走一整帧的量, 同一 sim 步上它在路上的位置不同。
##     总位移仍 = 速度 × 总 sim 时间, 协程跑完就追平。
##   · 「结果」= `hp / alive / shield / energy` 任一不同 —— **这才是对局结果真的不一样**,
##     (命中落在不同的 sim 步、少打一跳、死亡顺序变)。
## 判据仍然是「必须 0 分叉」(逐位一致是周日"服务端结算一次 + 双方看同一份重放"的前提),
## 但报告里要把这两个数**分开打**, 不然"98% 步分叉"会被误读成"结果全乱了"。
func _outcome_part(fp: String) -> String:
	var out: Array = []
	for seg in fp.split("|"):
		var bits: PackedStringArray = str(seg).split(":")
		if bits.size() < 7: out.append(str(seg)); continue
		## 丢掉 x / y(下标 1、2), 留 hp(0 的尾部) + alive/shield/energy(3/4/5)
		out.append("%s:%s:%s:%s:%s" % [bits[0], bits[3], bits[4], bits[5], bits[6]])
	return "|".join(out)


func _compare(a: Dictionary, b: Dictionary) -> Array:
	var common: Array = []
	for sn in (b["steps"] as Dictionary):
		if (a["steps"] as Dictionary).has(sn): common.append(int(sn))
	common.sort()
	var bad := 0
	var first := -1
	var bad_out := 0
	var first_out := -1
	for sn in common:
		var fa: String = str((a["steps"] as Dictionary)[sn])
		var fb: String = str((b["steps"] as Dictionary)[sn])
		if fa != fb:
			bad += 1
			if first < 0: first = int(sn)
			if _outcome_part(fa) != _outcome_part(fb):
				bad_out += 1
				if first_out < 0: first_out = int(sn)
	return [bad, common.size(), first, bad_out, first_out]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		## 钉死周锚点(与 `_det_scenarios` 同一个常量): 滚一次大轮会清等级/装备 ⇒
		## 两遍跑的根本不是同一局, 而失效的理由跟确定性一点关系都没有。
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	var SIM_DT: float = 1.0 / 60.0
	var TARGET := 600            # 600 sim 步 = 10 游戏秒: 够忍者冲击 + 双头炮弹各打几轮
	OS.set_environment("TURTLE_SEED", "424242")
	var a: Dictionary = await _run(1, TARGET)
	OS.set_environment("TURTLE_SEED", "")

	# ── 分母 ①: 一帧 1 步那遍本身要成立(步数到位 / 指纹随步变化 / 真的打出过伤害) ──
	var uniq := {}
	for v in (a["steps"] as Dictionary).values(): uniq[str(v)] = true
	_ok("分母 · 基准遍(1 步/帧) 跑到 %d 个 sim 步 / %d 帧(要求 ≥ %d 步)" % [
		int(a["last_step"]), int(a["frames"]), TARGET], int(a["last_step"]) >= TARGET)
	_ok("分母 · 基准遍真的在推进(不同指纹 %d 个 > 1, 累计承伤 %.0f > 0)" % [uniq.size(), float(a["taken"])],
		uniq.size() > 1 and float(a["taken"]) > 0.0)
	# ── 分母 ②: 协程真的在推进, 不是全程挂着不动 ──
	## ★量的是产品自己写的 `_ninja_dash_until`(ninja_system.gd:149) —— 它只在
	##   `_ninja_glide` 这个 `await process_frame` 协程把 `traveled` 推到命中投影时才写。
	##   它为 0 ⇒ 协程压根没动过 ⇒ 下面"k 步与 1 步同结果"全是恒真式。
	_ok("分母 · 协程真的在推进: 忍者冲击(协程位移)命中并写过 `_ninja_dash_until` 的单位 %d 个 > 0" % int(a["dash"]),
		int(a["dash"]) > 0, "为 0 = 14 处 `await process_frame` 协程全程挂着不动, 本测恒真")

	var worst := ""
	for k in [2, 3, 4]:
		OS.set_environment("TURTLE_SEED", "424242")
		var b: Dictionary = await _run(int(k), TARGET)
		OS.set_environment("TURTLE_SEED", "")
		# ── 分母 ③: k 真的生效了 ──
		## 两条一起才说明"这一帧真的跑了 k 步": 步号增量 == k, 且产品发布的
		## `_frame_sim_dt` 真的取到 k × SIM_DT(协程读的就是它)。
		_ok("分母 · k=%d 真的生效(单帧最大步数 %d == %d; `_frame_sim_dt` 峰值 %.5f == %.5f)" % [
			int(k), int(b["max_per_frame"]), int(k), float(b["max_frame_sim_dt"]), float(k) * SIM_DT],
			int(b["max_per_frame"]) == int(k) and absf(float(b["max_frame_sim_dt"]) - float(k) * SIM_DT) < 1.0e-9,
			"步数没变 ⇒ 这一轮其实还是 1 步/帧, 判据恒真")
		## 帧数应约为 1/k —— 这一条是"k 生效"的旁证, 而且挡住"我把 k 喂进去了但循环多跑了"
		var want_frames: int = int(ceil(float(TARGET) / float(k)))
		_ok("分母 · k=%d 的帧数 %d ≈ 基准 %d 的 1/%d(=%d, 容差 ±2)" % [
			int(k), int(b["frames"]), int(a["frames"]), int(k), want_frames],
			absi(int(b["frames"]) - want_frames) <= 2)
		_ok("分母 · k=%d 的协程也在推进(`_ninja_dash_until` %d 个 > 0)" % [int(k), int(b["dash"])],
			int(b["dash"]) > 0)
		# ── ★正题 ──
		var r: Array = _compare(a, b)
		var bad: int = int(r[0])
		var n: int = int(r[1])
		var first: int = int(r[2])
		_ok("分母 · k=%d 与基准共有 %d 个 sim 步号可比(0 个 = 空检查)" % [int(k), n], n >= TARGET / int(k) - 2)
		var d := ""
		if first >= 0:
			var sa: PackedStringArray = str((a["steps"] as Dictionary)[first]).split("|")
			var sb: PackedStringArray = str((b["steps"] as Dictionary)[first]).split("|")
			var dl: Array = []
			for i in range(maxi(sa.size(), sb.size())):
				var xa: String = sa[i] if i < sa.size() else "<缺>"
				var xb: String = sb[i] if i < sb.size() else "<缺>"
				if xa != xb: dl.append("%s  ≠  %s" % [xa, xb])
			d = "首个分叉 sim 步=%d · 不同的段 %d/%d: %s" % [
				first, dl.size(), maxi(sa.size(), sb.size()), " ;; ".join(dl).substr(0, 420)]
			worst += "k=%d: 全部 %d/%d@%d · 其中【结果字段】%d/%d@%d  " % [
				int(k), bad, n, first, int(r[3]), n, int(r[4])]
		## ★正题的判据形状: 目标是 0 分叉; 现状是台账里那个数。两条一起:
		##   ① 不许比台账**更差**(只减不增)
		##   ② 台账里这一条**现在仍然在分叉** —— 不分叉了就把它从台账划掉
		var led: Array = KNOWN_GAP.get(int(k), [0, 0, 0])
		if bad == 0:
			_ok("★一帧 %d 步 与 一帧 1 步 · 逐 sim 步指纹 0/%d 分叉" % [int(k), n], true,
				"★★台账里 k=%d 记着 %d 步分叉 —— 现在 0 了, **把它从 KNOWN_GAP 里划掉**" % [int(k), int(led[0])])
			_fail += 1
			print("  [FAIL] ★台账过期: k=%d 已经不分叉了, 删掉 KNOWN_GAP 里那一行(台账只减不增, 不许当垃圾桶)" % int(k))
		else:
			print("  [台账] 一帧 %d 步 vs 一帧 1 步: 全部 %d/%d 步分叉(首个 sim 步 %d) · 其中**结果字段**(hp/存活/护盾/龟能) %d 步(首个 sim 步 %d)" % [
				int(k), bad, n, first, int(r[3]), int(r[4])])
			print("      ", d)
			_ok("★一帧 %d 步 与 一帧 1 步 · 分叉**只减不增**(实测 %d/%d · 台账 %d/%d; 结果字段 实测 %d · 台账 %d)" % [
				int(k), bad, n, int(led[0]), int(led[2]), int(r[3]), int(led[1])],
				bad <= int(led[0]) and int(r[3]) <= int(led[1]) and n == int(led[2]),
				"比台账更差 = 有人又往协程里塞了一处按渲染帧推进的东西; 目标仍是 0(B2/B4 把协程搬进 sim 队列)")

	print("")
	if worst != "": print("  分叉汇总: ", worst)
	if _fail == 0: print("ALL PASS — 一帧多步/一帧1步 差距台账 %d 条(协程真在推进 · k 真生效 · 只减不增)" % _n)
	else: print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
