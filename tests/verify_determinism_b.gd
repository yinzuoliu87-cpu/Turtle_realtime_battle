extends Node
## verify_determinism_b.gd — 大轮赛制 v2【B 阶段】门禁: 同种子跑两遍, **逐步指纹**必须逐字相同。
##
## ═══ 为什么不是「比最终胜负」 ═══
## 只比终局会漏掉"中途分叉又收敛"的一整类(血量打回同一档、位置被 ARENA 钳到同一点)。
## 本门禁记的是**每一个 sim 步**的全场快照(每只单位的 hp / 坐标 / 存活 / 护盾, 按下标排),
## 两遍逐个下标比对, 报【分叉步数 / 总步数】与【首个分叉步】。
## ⇒ 这不是"过了就行"的判据, 它同时是一把**尺子**: 缺口有多大是量出来的数, 不是估的。
##
## ═══ 它抓到过什么(根因都是探针打出来的数值, 不是推理) ═══
## ① 海盗登场轰击的伤害挂在 `_pirate_cannonball` 的 `tween_callback` 末尾
##    (pirate_system.gd:208 → battle_spawn.gd:658), 而 tween 由 SceneTree 按【未钳制真实 delta】推进
##    ⇒ 同一发炮弹 A 跑落在 sim 步 93、B 跑落在 92 ⇒ 3v3 裸装 600 步里 **376 步**指纹不同。
##    修法: `RealtimeBattle3DScene._step_sim_tweens()` —— det 模式下 tween 改由 sim 步喂(`custom_step`)。
## ② 忍者冲刺 `ninja_system.gd:131` 用 `battle.get_process_delta_time()` 推位移
##    ⇒ 同种子两遍落点 x = 638.98 vs 639.01, 之后整局分叉(324/600)。
##    修法: 新增 `battle._frame_sim_dt`(本帧 sim 推进量), 全部同族协程改读它。
##
## ═══ 非恒真式的三道保险(CLAUDE.md:「判据不许是恒真式」「分母断言」) ═══
## · 分母: 打印【比对了多少步】; 步数为 0 直接判 FAIL(空检查不是通过)。
## · 有推进: 指纹必须【随步变化】(不同指纹数 > 1), 否则就是"两遍都没动"的假绿。
## · 吃种子: 换一个种子指纹序列必须不同, 否则说明结果根本不读 `_battle_rng`。
## · 走到了被修的那条路: 断言本局**真的建过 tween** 且**真的打出过伤害**——
##   否则 tween 时钟这条修不修都不会被量到。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond: print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 全场快照: 按 _units 下标排(不排序 —— 生成顺序本身也是确定性的一部分)。
func _fp(scene) -> String:
	var parts: Array = []
	var i := 0
	for u in scene._units:
		## ★除了血/位置/存活/盾, 还要记【金币 / 龟能 / 棱镜色】——
		##   它们同样是对局结果, 而且是 `_juice_rng`(每局 randomize) 的三个真实落点:
		##   财神每 3 秒 +4~7 金、无人机开火抖动、彩虹棱镜开局定色。不记 = 判据看不见那一类。
		##   ⚠ 只记**对局**字段: 纯演出的随机(火星位置/雾云)照旧不进指纹, 否则演出一抖就假红。
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.1f:%.2f:%d:%.4f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x),
			float((u.get("pos", Vector2()) as Vector2).y),
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)),
			float(u.get("gold", 0.0)),
			float(u.get("energy", 0.0)),
			int(u.get("prism_color", -1)),
			float(u.get("crit", 0.0))])
		i += 1
	return "|".join(parts)


## pairs = [[turtle_id, side, x, y, [装备 id...]], ...]
## 返回 [逐步指纹数组, det模式?, 最多同时在跑的tween数, 全场累计承伤]
func _trace(pairs: Array, frames: int, loadouts: Dictionary = {}) -> Array:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()   # 清掉上次遗留摆位(调试场存盘会跨 run 泄漏)
	## ★技能选择必须写在【建场之后】: `_edit_start_battle()` 会把 loadouts 存进 user://debug_setup.json,
	##   而下一次建场的 `_edit_load_setup()` 又把它灌回 GameState ⇒ 在 `_ready` 里设会被覆盖。
	##   实测代价: 骰子龟【稳定骰子】(skillPool[3]) 一次都没放出来(cover 探针数到 0), 那一条是空跑。
	if not loadouts.is_empty():
		var gs2 = get_node_or_null("/root/GameState")
		if gs2 != null:
			for k in loadouts:
				gs2.loadouts[str(k)] = int(loadouts[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true   # 满龟能: 主动技就绪 → 真的放技(练技能/RNG/演出结算路径)
	for p in pairs:
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):   # "__minion__:front" / ":back" —— 小将的前后排由笔刷字段决定
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
	s._debug._edit_start_battle()
	var tr: Array = []
	var tw_max := 0
	for _i in range(frames):
		await get_tree().process_frame
		tr.append(_fp(s))
		tw_max = maxi(tw_max, s._sim_tweens.size())
	var det: bool = bool(s._deterministic)
	var taken := 0.0
	for u in s._units:
		taken += float(u.get("_st_taken", 0.0))
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return [tr, det, tw_max, taken]


## 同种子跑两遍 → 逐步比对。返回 [分叉步数, 比对步数, 首个分叉步, A的trace, 附注]
func _two_runs(pairs: Array, frames: int, sd: String, loadouts: Dictionary = {}) -> Array:
	OS.set_environment("TURTLE_SEED", sd)
	var a: Array = await _trace(pairs, frames, loadouts)
	var b: Array = await _trace(pairs, frames, loadouts)
	OS.set_environment("TURTLE_SEED", "")
	var ta: Array = a[0]
	var tb: Array = b[0]
	var n: int = mini(ta.size(), tb.size())
	var first := -1
	var bad := 0
	for i in range(n):
		if str(ta[i]) != str(tb[i]):
			bad += 1
			if first < 0: first = i
	var uniq := {}
	for f in ta:
		uniq[str(f)] = true
	var note := "det=%s 比对步数=%d tween峰值=%d 全场承伤=%.0f 不同指纹=%d" % [
		str(a[1]), n, int(a[2]), float(a[3]), uniq.size()]
	return [bad, n, first, ta, note, int(a[2]), float(a[3]), uniq.size(), tb]


func _scenario(tag: String, pairs: Array, frames: int, sd: String, loadouts: Dictionary = {}) -> void:
	var r: Array = await _two_runs(pairs, frames, sd, loadouts)
	var bad: int = int(r[0])
	var n: int = int(r[1])
	var first: int = int(r[2])
	var note: String = str(r[4])
	# 分母断言: 比对步数必须等于要求的帧数(半路被掐断/场景没建起来都会让它对不上)
	_ok("分母 · %s · 逐步快照 %d 步(要求 %d)" % [tag, n, frames], n == frames, note)
	# 有推进: 指纹必须随步变化, 否则"两遍都是静止画面"也会全绿
	_ok("分母 · %s · 战斗真的在推进(不同指纹 %d 个 > 1, 累计承伤 %.0f > 0)" % [tag, int(r[7]), float(r[6])],
		int(r[7]) > 1 and float(r[6]) > 0.0)
	# 走到了被修的那条路: 本局真的建过演出 tween(tween 时钟这条修不修才量得到)
	_ok("分母 · %s · 本局真的建过演出 tween(峰值 %d > 0)" % [tag, int(r[5])], int(r[5]) > 0)
	# ★正题
	var d := ""
	if first >= 0:
		## 只打【真正不同的那几段】—— 整串截断会一直只看到前几只单位(踩过: 差异在第 5 只上, 怎么看都一样)
		var sa: PackedStringArray = str((r[3] as Array)[first]).split("|")
		var sb: PackedStringArray = str((r[8] as Array)[first]).split("|")
		var dl: Array = []
		for k in range(maxi(sa.size(), sb.size())):
			var xa: String = sa[k] if k < sa.size() else "<缺>"
			var xb: String = sb[k] if k < sb.size() else "<缺>"
			if xa != xb: dl.append("%s  ≠  %s" % [xa, xb])
		d = "首个分叉步=%d · 不同的段 %d/%d: %s" % [first, dl.size(), maxi(sa.size(), sb.size()), " ;; ".join(dl).substr(0, 420)]
	_ok("★%s · 同种子(%s)两遍 · 逐步指纹 %d/%d 步分叉 → 必须 0" % [tag, sd, bad, n], bad == 0, d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null: gs.test_mode = true   # 台子会写 user://debug_setup.json, 别碰玩家存档
	## ★钉住周锚点, 防止跑到一半换大轮(2026-09-20 主会话把赛季从「5 天滚」改成「自然周」,
	##   换轮判据只看 `week_anchor_ts`)。滚一次轮会清等级/装备/统领 ⇒ 两遍跑的根本不是同一局,
	##   指纹当然对不上。实测代价: 场景 ⑧ 从 0/1000 变成 493/1000 分叉, 而产品代码一个字没动。
	## ★★★2026-09-26 从「今天那一周」改成**钉死的绝对值**(`SC.PIN_WEEK_ANCHOR`)。
	##   原来用当周锚点对"同进程两遍"够用(两遍在同一周内), 但它让本门禁的输入
	##   **跟着星期几变** —— 而那是本仓栽过的一整类(memory: 判据挂在星期几上)。
	##   共用表那一侧(金标摘要)更是非钉死不可: 不钉的话下周一金标集体失效,
	##   而失效的理由跟确定性一点关系都没有。⇒ 两个门禁钉同一个常量。
	if gs != null:
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	## ══════════════════════════════════════════════════════════════════
	## ★★★2026-09-26 场景表搬到 `tests/_det_scenarios.gd`, **两个门禁共用一份**:
	##   · 本门禁            —— 同种子**同进程**两遍, 逐步指纹必须逐字相同
	##   · verify_determinism_cross —— 逐步指纹压成摘要, 与钉住的金标比
	##     (⇒ 换进程 / 换 OS / 换 libm 都得一样, 那是周日「服务端结算一次 + 双方看
	##      同一份重放」的前提, 原稿 §五.1 写着「排期在赛制上线之前」)
	## ★抄第二份的代价很实在: 场景里「为什么摆这个距离/为什么点这个技能」的理由一旦分家,
	##   改了其中一份, 另一份就静静地变成空跑(memory fb-hand-rolled-copies-drift)。
	##   ⇒ 表和它的理由都在那个文件里, 这里只负责跑。
	## ★分母: 表里必须正好 9 个场景 —— 少一个就是有人把场景删了而没人发现。
	var scs: Array = SC.all()
	_ok("分母 · 场景表读到 %d 个场景(与 verify_determinism_cross 同一份表)" % scs.size(),
		scs.size() == 9, "%d 个" % scs.size())
	for sc in scs:
		var scd: Dictionary = sc
		await _scenario(str(scd["tag"]), scd["pairs"] as Array, int(scd["frames"]),
			str(scd["seed"]), scd.get("loadouts", {}) as Dictionary)

	# ⑩ 反证(非恒真式): 换种子 → 逐步指纹序列必须不同; 否则说明结果根本不吃 _battle_rng
	## ★与场景 ② 同一套摆位(共用表里取) —— 唯一的变量只能是种子
	var cp_pairs: Array = SC.counter_proof_pairs()
	var r1: Array = await _two_runs(cp_pairs, 240, "424242")
	var r2: Array = await _two_runs(cp_pairs, 240, "77")
	var diff_seed := 0
	var nn: int = mini((r1[3] as Array).size(), (r2[3] as Array).size())
	for i in range(nn):
		if str((r1[3] as Array)[i]) != str((r2[3] as Array)[i]): diff_seed += 1
	_ok("分母 · 反证比对了 %d 步" % nn, nn == 240)
	_ok("★反证 · 换种子(424242→77) → 逐步指纹必须不同(%d/%d 步不同 > 0)" % [diff_seed, nn], diff_seed > 0,
		"全同 = 指纹根本没读到随机/没读到战斗状态, 上面几条就全是恒真式")

	# ═══ ⑧ 静态棘轮: 战斗路径里不许再出现 `get_process_delta_time()` ═══
	# ★为什么需要它(诚实地说清运行时判据守不住的那一半):
	#   ⑦ 的双头炮弹**射程只有 400 码** ⇒ 把它改回真实 delta, 弹丸在窗口内照样飞到,
	#   只是慢一点, 而两遍慢得一样 ⇒ 逐步指纹不分叉, 上面那条**不红**(实测: 单独变异它 30/30 全绿)。
	#   同族里凡是"飞得近/时间短"的站点都有这个盲区 —— 运行时判据只抓得到【够长】的那些。
	#   ⇒ 这一条补的是覆盖面: 源码级棘轮, 任何一处写回真实 delta 当场红。
	# ⚠ 它是**补充**不是替代: 源码扫描证明不了"改成 sim 钟之后结果真的一致"(那是上面七条的事)。
	# 逃生口: 纯演出确实需要真实 delta 的, 从 `_render_step(rd, …)` 的参数拿, 别直接调这个函数。
	var scan_dirs: Array = ["res://scripts/systems/skills", "res://scripts/systems/equip", "res://scripts/systems/trainer", "res://scripts/scenes/battle"]
	var files := 0
	var total_lines := 0
	var offenders: Array = []
	for d in scan_dirs:
		var dir := DirAccess.open(str(d))
		if dir == null: continue
		for f in dir.get_files():
			if not str(f).ends_with(".gd"): continue
			if str(f) == "battle_vfx_lab.gd": continue   # 开发台子(VFXLAB), 不在对局模拟路径上
			var fa := FileAccess.open(str(d) + "/" + str(f), FileAccess.READ)
			if fa == null: continue
			files += 1
			var ln := 0
			while not fa.eof_reached():
				var line: String = fa.get_line()
				ln += 1
				var s: String = line.strip_edges()
				if s.begins_with("#"): continue
				if line.find("get_process_delta_time()") >= 0:
					offenders.append("%s:%d" % [str(f), ln])
			total_lines += ln
			fa.close()
	# 主场景单独扫(它不在上面四个目录里)
	var mf := FileAccess.open("res://scripts/scenes/RealtimeBattle3DScene.gd", FileAccess.READ)
	if mf != null:
		files += 1
		var mn := 0
		while not mf.eof_reached():
			var line2: String = mf.get_line()
			mn += 1
			var s2: String = line2.strip_edges()
			if s2.begins_with("#"): continue
			if line2.find("get_process_delta_time()") >= 0:
				offenders.append("RealtimeBattle3DScene.gd:%d" % mn)
		total_lines += mn
		mf.close()
	_ok("分母 · 静态棘轮扫了 %d 个文件 / %d 行(0 个文件 = 空检查, 不是通过)" % [files, total_lines],
		files >= 30 and total_lines > 20000)
	_ok("★⑧ 战斗模拟路径里 `get_process_delta_time()` 必须 0 处(实测 %d 处)" % offenders.size(),
		offenders.is_empty(), "; ".join(offenders).substr(0, 300))


	print("")
	if _fail == 0: print("ALL PASS — B 阶段逐步确定性 %d 条(同种子逐步指纹逐字相同)" % _n)
	else: print("FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
