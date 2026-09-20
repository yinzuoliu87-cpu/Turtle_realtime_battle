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
	if gs != null:
		var _P2 = load("res://scripts/gamedata/phase2_config.gd")
		if _P2 != null and _P2.has_method("week_anchor_utc"):
			gs.week_anchor_ts = int(_P2.week_anchor_utc(int(Time.get_unix_time_from_system())))

	# ① 基线: 两只裸装(与 verify_battle_determinism 同场景, 只是改成逐步比)
	await _scenario("① 2 单位裸装", [
		["basic", "left", 320.0, 300.0, []],
		["basic", "right", 400.0, 300.0, []]], 200, "424242")

	# ② ★抓到 bug 的那一局: 海盗(登场轰击挂 tween 末尾) + 忍者(冲刺吃真实 delta) + 骰子(吃 _battle_rng)
	var bare3: Array = [
		["stone", "left", 320.0, 220.0, []], ["basic", "left", 320.0, 320.0, []], ["ninja", "left", 320.0, 420.0, []],
		["lightning", "right", 900.0, 220.0, []], ["dice", "right", 900.0, 320.0, []], ["pirate", "right", 900.0, 420.0, []]]
	await _scenario("② 3v3 裸装(海盗/忍者/骰子/闪电)", bare3, 600, "424242")

	# ③ 满装备: 每只 3 件 3★, 覆盖召唤/弹道/周期/羁绊多条路径
	var full3: Array = [
		["stone", "left", 320.0, 220.0, ["p2eq_001", "p2eq_010", "p2eq_022"]],
		["basic", "left", 320.0, 320.0, ["p2eq_032", "p2eq_058", "p2eq_073"]],
		["ninja", "left", 320.0, 420.0, ["p2eq_061", "p2eq_084", "p2eq_091"]],
		["lightning", "right", 900.0, 220.0, ["p2eq_006", "p2eq_009", "p2eq_026"]],
		["dice", "right", 900.0, 320.0, ["p2eq_065", "p2eq_070", "p2eq_077"]],
		["pirate", "right", 900.0, 420.0, ["p2eq_080", "p2eq_087", "p2eq_094"]]]
	await _scenario("③ 3v3 满装备(每只 3 件 3★)", full3, 600, "424242")

	# ④ 双头/藏身(小将踩背)/宽刃扫描 —— 都是"协程按真实 delta 推进"的同族站点
	var co3: Array = [
		["two_head", "left", 320.0, 240.0, ["p2eq_009"]],
		["hiding", "left", 320.0, 380.0, []],
		["gambler", "right", 900.0, 240.0, []],
		["basic", "right", 900.0, 380.0, []]]
	await _scenario("④ 双头/藏身/宽刃(协程位移同族)", co3, 1000, "424242")

	# ⑤ 剑线装备: 007 锈蚀阔剑(每 6 秒)与 006 千刃风暴(每 7 秒) —— 推进都写在
	#    `await process_frame` 协程里(equip_system.gd:948 / :1303), 原来按真实 delta 走。
	#    1400 步 = 23.3 游戏秒 ⇒ 两件都至少触发一次(6s / 7s), 不然这一条就是空跑。
	## ★携带者用【远程】猎人: 近战龟会贴到脸上, 剑气墙一出生就命中 ⇒ 到达时刻没有可观测差异,
	##   把"推进用哪条钟"整条藏起来(改坏了门禁也不红)。拉开距离才量得到"走了多久才打到"。
	await _scenario("⑤ 007阔剑+006千刃(协程扫描同族)", [
		["hunter", "left", 320.0, 300.0, ["p2eq_007", "p2eq_006"]],
		["basic", "right", 900.0, 300.0, []],
		["basic", "right", 980.0, 380.0, []]], 1400, "424242")

	# ⑥ 小将: 近战浪板的"踩背滑行 0.833 秒"与远程火箭的"慢速追踪导弹"都是协程位移
	#    (hiding_system.gd:107 / :345 / :376) —— 它们改的是**攻守双方**的 pos, 分叉会立刻进指纹。
	await _scenario("⑥ 小将浪板/追踪火箭(协程位移)", [
		["__minion__:front", "left", 320.0, 260.0, []],
		["__minion__:back", "left", 320.0, 400.0, []],
		["basic", "right", 820.0, 260.0, []],
		["basic", "right", 820.0, 400.0, []]], 800, "424242")

	# ⑦ 双头【灵能冲击炮弹】(two_head_system.gd:104): 同样是"协程按 delta 推位移"。
	#    ★摆在它射程内(200 码)才量得到 —— ④ 里两只隔 580 码, 改坏了炮弹在窗口内根本飞不到,
	#      "什么都没发生"在两遍之间是一样的 ⇒ 判据看不见(实测 ④ 单独变异它不红)。
	await _scenario("⑦ 双头灵能炮弹(协程位移)", [
		["two_head", "left", 320.0, 300.0, []],
		["basic", "right", 520.0, 300.0, []]], 700, "424242")

	# ⑧ ★`_juice_rng` 的四个【对局】落点 —— 它在 battle_world_builder.gd:762 每局无条件 `randomize()`,
	#    连 TURTLE_SEED 设了也照样随机 ⇒ 这四处天生不可复现, 与 tween/协程那两族无关:
	#      · 闪电龟雷暴挑谁挨雷(RealtimeBattle3DScene.gd `_barrage_bolt`)
	#      · `_sk_dmg_wave` 的 random_aoe 挑谁挨这一段(多技能共用通道)
	#      · 财神聚宝盆每 3 秒 +4~7 金(数额本身就是随机)
	#      · 赛博无人机打谁 + 开火间隔抖动(后者原来还是**裸 randf()**)
	#    再加彩虹龟开局的棱镜色(battle_spawn.gd:609)。
	## ★闪电龟默认选中的是 skillPool[1](涌动), **雷暴是 [2]** —— 不点名就根本放不出来,
	##   这一条会变成"摆了个闪电龟但从没打雷"的空跑(分母断言看不出这种空跑, 所以写在这里)。
	##   骰子龟同理: 命运骰(_sk_dice_fate, 掷暴击点数)是 [2], 默认 [1] 是梭哈。
	await _scenario("⑧ 雷暴/random_aoe/聚宝盆/无人机/棱镜(受控 PRNG 落点)", [
		["lightning", "left", 320.0, 220.0, []],
		["fortune", "left", 320.0, 320.0, []],
		["cyber", "left", 320.0, 420.0, []],
		["rainbow", "left", 320.0, 520.0, []],
		["dice", "left", 320.0, 620.0, []],
		["basic", "right", 820.0, 260.0, []],
		["basic", "right", 820.0, 380.0, []],
		["basic", "right", 820.0, 500.0, []]], 1000, "424242", {"lightning": 2, "dice": 2})

	# ⑨ 骰子龟【稳定骰子】: 掷出几段 = 打几下(dice_system.gd:185, 原来是裸全局 randi_range),
	#    它是 skillPool[3], 默认选不到 ⇒ 必须点名, 否则这一条又是空跑。
	#    ★窗口要 1800 步(30 秒): 7~11 段每段都要冲刺 + 顿 0.2 秒, 600 步里两遍都还在冲到一半,
	#      "掷了几段"根本还没兑现完 ⇒ 判据看不见(实测 600 步时单独变异它不红)。
	await _scenario("⑨ 骰子龟稳定骰子(掷段数)", [
		["dice", "left", 320.0, 300.0, []],
		["basic", "right", 560.0, 300.0, []],
		["basic", "right", 640.0, 380.0, []]], 1800, "424242", {"dice": 3})

	# ⑩ 反证(非恒真式): 换种子 → 逐步指纹序列必须不同; 否则说明结果根本不吃 _battle_rng
	var r1: Array = await _two_runs(bare3, 240, "424242")
	var r2: Array = await _two_runs(bare3, 240, "77")
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
