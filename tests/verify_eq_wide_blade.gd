extends Node
## verify_eq_wide_blade.gd — 009 宽刃弯刀【扇形带要真的罩住敌群】门禁 (2026-09-08)
##
## ══════════════════════════════════════════════════════════════════
##  这个文件要守住的是文案里的哪句话
## ══════════════════════════════════════════════════════════════════
## `data/phase2-equipment.json` 的 effectDesc1 原话:
##     「在 {BLADE_SEEK} 码内自动选定释放点, **使其 {R_IN}~{R_OUT} 码扇形带罩住敌群**」
##
## 2026-09-08 在 VFXLAB 实拍 009, 花名册量到的真实布局是:
##     携带者 (398,474)  敌人 (1018,474) (1178,474) (1338,474)   ← 160 码等距排开
## 老规则「带心 650 码对准敌群质心」算出 org=(528,474), 三敌距 org = 490 / 650 / 810,
## 而带是 500~800 ⇒ **外侧两个各差 10 码落在带外, 三打三只命中中间一个**。
## 更糟的是它会误触发「仅命中 1 名敌人 ⇒ 伤害 x2/2.5/3」—— 那条补偿本该只在单挑时给。
##
## ★判据落在**抽出来的具名纯函数**上(`blade_release_point` / `blade_hit_test`),
##   演出与伤害结算调的是同一对函数 ⇒ 画到哪就打到哪, 不存在"两份手抄各自漂"。
##   (memory [[fb-hand-rolled-copies-drift]]: 原来伤害那段是就地手写的第二份判定。)
##
## ★★这里最要紧的一条是【②】: 它先证明"这个布局确实会漏", 否则 ③ 就是恒真式 ——
##   随便一个布局都罩得住的话, ③ 全绿也说明不了任何事。
##   (memory [[fb-verify-check-can-fail]]: 打印分母, 并先证明检查会 FAIL。)
##
## 反向验证(2026-09-08 实跑过, 见 §末):
##   把 `blade_release_point` 改回「return src.pos + dir * base」(即老的对准质心规则)
##   ⇒ ③ 当场红「罩住 1 个(应 3 个)」、⑧ 真入口红「只有 1 个敌人吃到伤害」。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const EQ := preload("res://scripts/systems/equip/equip_system.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


func _mk(pos: Vector2) -> Dictionary:
	## 干净合成单位: 只带这两个函数真正会读的字段, 不 spawn 真队伍
	## (memory: 拿随机 spawn 单位测精确数值 ⇒ CI 偶发红)
	return {"pos": pos, "alive": true}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # ★绝不写玩家存档
	print("=== 009 宽刃弯刀: 扇形带要真的罩住敌群 ===")

	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var eq = _s._equip_sys
	_ok("★分母: 拿得到 EquipSystem", eq != null, "拿不到就下面全是空检查")
	if eq == null:
		_done()
		return

	# ══════════════════════════════════════════════════════════════
	#  ① 量纲: 带比敌群还窄 —— 这就是"必须挪释放点"的原因
	# ══════════════════════════════════════════════════════════════
	print("-- 1 量纲: 带宽 vs 敌群跨度 --")
	var band_w: float = EQ.BLADE_R_OUT - EQ.BLADE_R_IN
	var span: float = 320.0                      # 实拍布局: 三敌 160 码等距 ⇒ 跨度 320
	_ok("带宽 %.0f 码 < 敌群跨度 %.0f 码" % [band_w, span], band_w < span,
		"带比敌群宽的话这条门禁就没意义了 —— 说明常量被改过, 下面的判据要重新定")

	# ══════════════════════════════════════════════════════════════
	#  ②③ 实拍那组坐标: 老规则漏两个 / 新规则全罩住
	# ══════════════════════════════════════════════════════════════
	print("-- 2/3 实拍布局(携带者398 · 敌 1018/1178/1338 · 同一条 y) --")
	var src: Dictionary = _mk(Vector2(398.0, 474.0))
	var foes: Array = [_mk(Vector2(1018.0, 474.0)), _mk(Vector2(1178.0, 474.0)), _mk(Vector2(1338.0, 474.0))]
	_ok("★分母: 造了 %d 个敌人(应 3)" % foes.size(), foes.size() == 3, "为 0 = 空检查")

	var cen := Vector2.ZERO
	for f in foes:
		cen += f["pos"]
	cen /= float(foes.size())
	var dir: Vector2 = (cen - src["pos"]).normalized()
	var aim_dist: float = (cen - src["pos"]).length()

	## ② 老规则(带心对准质心)在这个布局下确实会漏 —— 不先证明这一点, ③ 就是恒真式
	var old_off: float = clampf(aim_dist - (EQ.BLADE_R_IN + EQ.BLADE_R_OUT) * 0.5, -EQ.BLADE_SEEK, EQ.BLADE_SEEK)
	var old_org: Vector2 = src["pos"] + dir * old_off
	var old_hits: int = eq.blade_hit_test(old_org, dir, foes).size()
	_ok("② 老规则「带心对准质心」只罩住 %d 个(应 1, 证明这个布局真的会漏)" % old_hits, old_hits == 1,
		"若它本来就罩住 3 个, 说明常量或布局变了 ⇒ ③ 变成恒真式, 必须重新挑一个会漏的布局")

	## ③ 新规则要选到【理论最优】的释放点。
	##   ★判据不写死数字, 而是拿暴力扫描当对照 —— 因为"最多能罩几个"是布局决定的:
	##     这个布局带宽 300 < 跨度 320, 3 个在几何上就不可能同时罩住(判据①已经量过这条)。
	##     第一版我把 ③ 写成"应 3", 门禁当场红, 红的是我的期望值不是代码。
	##   扫描只存在于门禁里做对照, 产品代码走的是"边界候选点"解析解(不引入步长参数)。
	var org: Vector2 = eq.blade_release_point(src, dir, foes, aim_dist)
	var hits: Array = eq.blade_hit_test(org, dir, foes)
	var brute_best: int = 0
	var brute_n: int = 0
	for step in range(int(-EQ.BLADE_SEEK), int(EQ.BLADE_SEEK) + 1, 5):
		brute_n += 1
		var bn: int = eq.blade_hit_test(src["pos"] + dir * float(step), dir, foes).size()
		if bn > brute_best:
			brute_best = bn
	_ok("★分母: 暴力扫描试了 %d 个释放点" % brute_n, brute_n > 100, "扫描没跑 = 对照是空的")
	_ok("③ 自选释放点罩住 %d 个 = 理论最优 %d 个" % [hits.size(), brute_best], hits.size() == brute_best,
		"文案原话是「自动选定释放点使其扇形带罩住敌群」⇒ 选不到最优就是没做到; org=%s" % str(org))
	_ok("③b 比老规则(罩 %d 个)严格更好: 罩 %d 个" % [old_hits, hits.size()], hits.size() > old_hits,
		"没变好的话这次改动等于没做")

	## ④ 释放点不许跑出文案写的 ±BLADE_SEEK
	var off_used: float = (org - src["pos"]).dot(dir)
	_ok("④ 释放点偏移 %.0f 码 <= BLADE_SEEK %.0f" % [absf(off_used), EQ.BLADE_SEEK],
		absf(off_used) <= EQ.BLADE_SEEK + 0.01, "文案写的是在 SEEK 码内自选")

	# ══════════════════════════════════════════════════════════════
	#  ⑤ 单挑时命中数必须真的是 1 —— x2/2.5/3 那条补偿该给的时候还要给
	# ══════════════════════════════════════════════════════════════
	print("-- 5 单挑: 命中数 = 1(补偿仍该触发) --")
	var solo: Array = [_mk(Vector2(1018.0, 474.0))]
	var sdir: Vector2 = (solo[0]["pos"] - src["pos"]).normalized()
	var sorg: Vector2 = eq.blade_release_point(src, sdir, solo, (solo[0]["pos"] - src["pos"]).length())
	var sh: int = eq.blade_hit_test(sorg, sdir, solo).size()
	_ok("⑤ 单个敌人 ⇒ 命中 %d(应 1)" % sh, sh == 1,
		"连唯一那个都罩不住的话, 自选释放点写反了")

	# ══════════════════════════════════════════════════════════════
	#  ⑥ 扇面还在: 侧后方的敌人不许被打到(别为了"罩住"把角度谓词也放开了)
	# ══════════════════════════════════════════════════════════════
	print("-- 6 扇面仍然收着(不是全场 AOE) --")
	var behind: Array = [_mk(src["pos"] - Vector2(650.0, 0.0))]
	var bh: int = eq.blade_hit_test(src["pos"], Vector2.RIGHT, behind).size()
	_ok("⑥ 正后方 650 码的敌人未命中", bh == 0, "扇形变成了整圆")
	var side: Array = [_mk(src["pos"] + Vector2(0.0, 650.0))]
	var sdh: int = eq.blade_hit_test(src["pos"], Vector2.RIGHT, side).size()
	_ok("⑥ 正侧方(90°)650 码的敌人未命中", sdh == 0,
		"BLADE_ARC_DEG=%.0f ⇒ 半角 %.0f 度, 90 度必须在外" % [EQ.BLADE_ARC_DEG, EQ.BLADE_ARC_DEG * 0.5])

	# ══════════════════════════════════════════════════════════════
	#  ⑦ 文案里写死的数字 ↔ 代码常量
	# ══════════════════════════════════════════════════════════════
	print("-- 7 文案数字 ↔ 常量 --")
	_ok("BLADE_AOE_FACTOR = 0.5 (文案:范围技能减半)", absf(EQ.BLADE_AOE_FACTOR - 0.5) < 1e-6,
		"实际 %.3f" % EQ.BLADE_AOE_FACTOR)
	_ok("BLADE_ARC_DEG = 60 (文案用占位符取它)", absf(EQ.BLADE_ARC_DEG - 60.0) < 1e-6,
		"实际 %.1f" % EQ.BLADE_ARC_DEG)
	_ok("BLADE_FULL = 100 (文案用占位符取它)", absf(EQ.BLADE_FULL - 100.0) < 1e-6,
		"实际 %.1f" % EQ.BLADE_FULL)

	# ══════════════════════════════════════════════════════════════
	#  ⑧ 跑真入口 _eq_wide_blade: 三个敌人都要真的吃到伤害
	#     (断言"函数存在"守不住"还有没有人调" —— memory fb-verify-must-run-the-real-path)
	# ══════════════════════════════════════════════════════════════
	print("-- 8 真入口 _eq_wide_blade: 三个敌人都吃到伤害 --")
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	## ★★场上必须只有我造的这 4 个单位。
	##   探针实测: 不清场时 `_s._units` 里已经有战斗自己 spawn 的默认队伍, 它们照样在互殴 ⇒
	##   `_st_taken` 里混进了别人的账(量到"敌0 +1 / 敌1 +0 / 敌2 +104", 数字与月光斩毫无关系),
	##   于是反向验证时 ⑧ 恒绿。判据要量被测那件事的账。
	print("     [探针] 清场前 _s._units = %d 个" % _s._units.size())
	_s._units.clear()
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-390.0, 0.0))
	## ★★携带者必须【不普攻 + 不走位】, 否则这条断言量不到被测的那件事:
	##   反向验证时 ③③b 都红了而 ⑧ 照样绿 —— 因为普攻也在往 _st_taken 里加,
	##   "这个敌人掉血了"里混着普攻的账。no_basic 之后 _st_taken 的增量只可能来自月光斩。
	##   不走位则是为了让 org 与②③算的是同一个(它在预警开始那一刻按携带者位置定)。
	owner_u["no_basic"] = true
	owner_u["no_move"] = true
	owner_u["move_spd"] = 0.0
	_s._units.append(owner_u)
	var real_foes: Array = []
	for k in range(3):
		var f: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(230.0 + 160.0 * k, 0.0))
		f["maxHp"] = 1.0e8
		f["hp"] = 1.0e8
		f["_st_taken"] = 0
		## ★钉住不许走: 预警有 0.56 游戏秒, 敌人会在这段时间里往携带者挪、把布局挪成别的样子
		##   ⇒ 第一版这条断言拿到 3/3, 而几何上最多只可能 2 —— 那 3 是"他们自己挤过来了"。
		##   判据要卡住被测的那件事(释放点选得对不对), 不能把敌人的走位也算进来。
		f["no_move"] = true
		f["move_spd"] = 0.0
		_s._units.append(f)
		real_foes.append(f)
	_ok("★分母: 场上 %d 个真敌人(应 3)" % real_foes.size(), real_foes.size() == 3)

	var before: Array = []
	for f in real_foes:
		before.append(int(f.get("_st_taken", 0)))

	_s._equip_sys._eq_wide_blade(owner_u, real_foes[1], 2)   # ★真入口, 不 await(它自己是协程)

	## 等演出走完预警(0.56 游戏秒)+ 结算。用**墙钟**当上限(CLAUDE.md §3.5: 帧数/游戏钟都不能当尺子)
	var t_end: int = Time.get_ticks_msec() + 12000
	var got := 0
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		got = 0
		for i in range(real_foes.size()):
			if int(real_foes[i].get("_st_taken", 0)) > int(before[i]):
				got += 1
		if got >= 2:
			break
	## 量【累计承伤】而不是血量差 —— 血量会被别的东西动(memory fb-make-the-noise-deterministic)
	var detail := ""
	for i in range(real_foes.size()):
		detail += " 敌%d(距携带者%.0f码) +%d" % [i,
			(real_foes[i]["pos"] as Vector2).distance_to(owner_u["pos"]),
			int(real_foes[i].get("_st_taken", 0)) - int(before[i])]
	print("     [探针] 真入口承伤明细:%s" % detail)
	## 布局与②③同一组(620/780/940 码, 跨度 320 > 带宽 300)⇒ 真入口也只可能打到 2 个。
	## 老规则在这里打到的是 1 个, 所以 ">=2" 就是"改动真的传到了真入口"这件事的账。
	_ok("⑧ 真入口打到 %d 个敌人(应 2 = 该布局的理论最优; 老规则只有 1)" % got, got == 2,
		"打到 1 = 改动没接到真入口; 打到 3 = 敌人挪过位置了(no_move 没生效)。%s" % detail)

	_done()


func _done() -> void:
	print("---- %d 条断言, %d 条 FAIL ----" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	else:
		print("FAILED")
	if _s != null and is_instance_valid(_s):
		_s.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
