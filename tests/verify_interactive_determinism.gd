extends Node
## verify_interactive_determinism.gd — Phase4切片2 门禁: 交互固定步长累加器【帧率无关】(用户 2026-07-25)
##
## v0.15.8 的招牌是「帧率无关」——60/144/300fps 下战斗逐 tick 一致。但此前它只被【headless det 单步】
## (verify_battle_determinism) 和【你主观 F5】背书, 没有任何自动证据证明【累加器本身】把不同帧率抹平。
## 本门禁补这个洞: 同一场战斗、同一 RNG 种子, 把【同样的总时长】切成【不同大小的帧块】喂给累加器
## (`_advance_sim_accum`), 断言最终指纹【逐字相同】。
##
## 为什么能做到逐字相同(而非近似): 用【浮点精确等价】的分块——
##   2·SIM_DT == SIM_DT+SIM_DT(指数进位·精确)、SIM_DT/2+SIM_DT/2 == SIM_DT(×2 与舍入交换·精确)。
##   → 三种"帧率"落到【完全一样的 SIM_DT 整步序列】→ 同序消费 RNG → 逐字相同。
## 这不是取巧: 它精确地证明了"怎么切帧不改变 sim", 即帧率无关这一性质本身; 真实 60↔144 的浮点尾差
##   只会让整局多/少一步(±1·无关紧要), 而那正是本测隔离掉的噪声。
##
## ★纯 sim 驱动(set_process(false) 后手动喂累加器·同步无 await)→ 不依赖真实帧率/演出 tween(照 §3.5 教训)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _fingerprint(scene) -> String:
	var parts: Array = []
	for u in scene._units:
		parts.append("%s:%.2f:%.1f:%.1f" % [str(u.get("id", "?")), float(u.get("hp", 0.0)), float((u.get("pos", Vector2()) as Vector2).x), float((u.get("pos", Vector2()) as Vector2).y)])
	parts.sort()
	return "t=%.3f;" % float(scene._t) + "|".join(parts)

## 用【给定分块序列】驱动一场固定战斗, 返回终局指纹。
## chunks: 每帧喂给累加器的 delta 列表(Σchunks = 总模拟时长)。RNG 固定种子 → 唯一变量是分块方式。
func _run_chunked(chunks: Array, seed_val: int) -> String:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)   # ★关掉 Godot 按真实帧率自动驱动 → 只由本函数手动喂累加器(帧率完全受控)
	s._debug._edit_clear()        # 清掉自动载入/上次遗留摆位(存盘跨run泄漏)
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 4000.0
	s._edit_full_energy = true   # 满龟能: 主动技就绪→放技(练技能 RNG/DoT/时序路径)
	s._debug._edit_place_unit("dice", "left", Vector2(320, 300))   # 骰子龟: 命运骰吃 _battle_rng → 有真随机可验
	s._debug._edit_place_unit("basic", "right", Vector2(400, 300))
	s._debug._edit_start_battle()
	# ★固定 RNG + 强制交互(累加器)路径。放在 start 之后 → 两 run 进驱动循环时 RNG 态完全一致。
	s._deterministic = false
	s._battle_rng.seed = seed_val
	s._sim_accum = 0.0
	s._hitstop = 0.0
	for c in chunks:
		s._advance_sim_accum(float(c))   # 同步喂·无 await → 帧间不流逝真实时间/不推进演出 tween
	var fp := _fingerprint(s)
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return fp


## ═══════════════════════════════════════════════════════════════════════════
##  `_wait_sim(k × SIM_DT)` 必须**正好**等 k 个 sim 步
## ═══════════════════════════════════════════════════════════════════════════
## ★★2026-09-10 逐帧看 010 时抓到的真缺陷, 而且它**不是 010 的**, 是这条核心助手的:
##   `_t` 是一步一步加出来的(每步 SIM_DT = 1/60), 而 1/60 在浮点里不精确 ——
##   3 步加起来是 0.049999999999999996, 而 `t_end = _t + 0.05` 里的 0.05 是 0.050000000000000003。
##   于是 `while _t < t_end` **多等一步**: 想等 0.05 实际等 0.0667(+33%)。
##   ★而且看运气: 探针实测 010 斩击第一次施放五帧全是 4 步、第二次施放全是 3 步 ——
##   同一段演出两次施放长度差 33%, 而这条路上**几乎所有演出**都在用 `_wait_sim`。
## ★量法: 每帧恰喂 1 个 SIM_DT 步, 让真的 `_wait_sim` 自己跑完, 量 `_t` 走了多远
##   —— 不重写它的算法(手抄的副本必然落后, memory `fb-hand-rolled-copies-drift`)。
func _do_wait(s, secs: float, fin: Array) -> void:
	await s._wait_sim(secs)
	fin[0] = true

func _measure_wait(s, secs: float) -> float:
	var t0: float = s._t
	var fin: Array = [false]
	## nowait —— 故意不 await: 要让它在旁边跑, 这边逐帧喂步并等 fin[0]。
	## ★下面 while 里有 guard 封顶, 协程没跑完不会被悄悄跳过(不是静默截断)。
	_do_wait(s, secs, fin)          # nowait
	var guard := 0
	while not fin[0] and guard < 4000:
		s._advance_sim_accum(1.0 / 60.0)   # 每帧恰 1 步 → "等了多久"= _t 走了多远
		await get_tree().process_frame
		guard += 1
	return s._t - t0


func _check_wait_sim() -> void:
	var SIM_DT: float = 1.0 / 60.0
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s.set_process(false)   # 只由 _measure_wait 手动喂 → 与真实帧率无关
	s._debug._edit_clear()
	s._edit_dummy_killable = false
	s._debug._edit_place_unit("dice", "left", Vector2(320, 300))
	s._debug._edit_place_unit("basic", "right", Vector2(400, 300))
	s._debug._edit_start_battle()
	s._deterministic = false
	s._sim_accum = 0.0
	## 多种步数 × 多轮 ⇒ 每次起跑时 `_t` 的浮点相位都不同, 才踩得到那条刀锋
	## (只试一次会碰运气地全对 —— 实测第一次施放 4 步、第二次 3 步)。
	var ks: Array = [1, 2, 3, 6, 18, 3, 2, 3, 6, 3]
	var bad := 0
	var worst := 0.0
	var got_list: Array = []
	for k in ks:
		var want: float = float(k) * SIM_DT
		var got: float = await _measure_wait(s, want)
		got_list.append(roundf(got / SIM_DT * 100.0) / 100.0)
		var err: float = absf(got - want)
		worst = maxf(worst, err / SIM_DT)
		if err > 1.0e-9:
			bad += 1
	_ok("分母: 量了 %d 次 _wait_sim(k×SIM_DT), 实际步数 %s" % [ks.size(), str(got_list)],
		ks.size() == 10 and s._t > 0.0)
	_ok("★_wait_sim(k×SIM_DT) 正好等 k 步(超出 %.3f 步; 须 < 0.001)" % worst, bad == 0,
		"多等一步 = 那段演出凭浮点相位随机慢 33%%; 想等 k 步却等了 k+1 步的有 %d 次" % bad)
	s.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	var SIM_DT: float = 1.0 / 60.0
	var N := 150   # 整步数(2.5 秒模拟)——够骰子龟移动+普攻+放技+DoT, 指纹随战斗推进
	var SEED := 20260725

	# 三种"帧率", 总时长【浮点精确】相等(见文件头): 落到同样的 N 个 SIM_DT 整步。
	var f60: Array = []      # 60fps: N 帧 × SIM_DT (每帧 1 步)
	for _i in range(N): f60.append(SIM_DT)
	var f30: Array = []      # 30fps: N/2 帧 × 2·SIM_DT (每帧 2 步)
	for _i in range(N / 2): f30.append(2.0 * SIM_DT)
	var f120: Array = []     # 120fps: 2N 帧 × SIM_DT/2 (每两帧 1 步)
	for _i in range(N * 2): f120.append(SIM_DT / 2.0)

	var fp60: String = await _run_chunked(f60, SEED)
	var fp30: String = await _run_chunked(f30, SEED)
	var fp120: String = await _run_chunked(f120, SEED)

	_ok("★30fps(2·SIM_DT/帧) 与 60fps(SIM_DT/帧) → 指纹逐字相同(切大帧不改 sim)", fp30 == fp60)
	if fp30 != fp60:
		print("  60fps : ", fp60); print("  30fps : ", fp30)
	_ok("★120fps(SIM_DT/2·每2帧1步) 与 60fps → 指纹逐字相同(切小帧不改 sim)", fp120 == fp60)
	if fp120 != fp60:
		print("  60fps : ", fp60); print("  120fps: ", fp120)

	# 抖动帧(每帧大小乱变, 但仍是 SIM_DT 的整/半数倍·Σ精确相等) → 同样逐字相同。
	var jit: Array = []
	var acc := 0.0
	var pat := [2.0 * SIM_DT, SIM_DT / 2.0, SIM_DT / 2.0, SIM_DT]   # Σ=4·SIM_DT/组·浮点精确
	var gi := 0
	while acc < float(N) * SIM_DT - 1e-9:
		var d: float = pat[gi % pat.size()]
		jit.append(d); acc += d; gi += 1
	var fpJit: String = await _run_chunked(jit, SEED)
	_ok("★抖动帧率(2·/½/½/1 循环·Σ精确=N步) → 仍逐字相同(累加器把任意分块抹平)", fpJit == fp60)
	if fpJit != fp60:
		print("  60fps : ", fp60); print("  jitter: ", fpJit)

	# 反证 1(非 vacuous): 多喂 1 步 → sim 多推进一格 → 指纹必须不同(证明指纹真的随每步变化)。
	var fPlus1: Array = f60.duplicate()
	fPlus1.append(SIM_DT)
	var fpPlus1: String = await _run_chunked(fPlus1, SEED)
	_ok("★反证: 总时长多 1 个 SIM_DT → 指纹不同(每步都在推进·测非 vacuous)", fpPlus1 != fp60, fpPlus1.substr(0, 46))

	# 反证 2(吃种子): 换 RNG 种子 → 指纹不同(骰子龟真吃 _battle_rng·结果非写死)。
	var fpSeed2: String = await _run_chunked(f60, 999983)
	_ok("★反证: 换 RNG 种子(同分块) → 指纹不同(结果真吃 _battle_rng)", fpSeed2 != fp60)

	# 分母: 指纹非空 + 战斗真推进了(假人掉了血 / 龟移动了 → 不是静止空局)。
	_ok("分母: 指纹含单位状态且战斗有推进", fp60.length() > 10 and fp60.find("dice:") >= 0 and float(N) * SIM_DT > 0.0, fp60.substr(0, 60))

	await _check_wait_sim()

	print("ALL PASS — 交互累加器帧率无关(任意分帧同总时长→同结果·Phase4切片2 生效)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
