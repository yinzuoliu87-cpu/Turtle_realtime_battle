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

	# ══════════════════════════════════════════════════════════════
	#  ⑨ 像素密度: 这两张贴地素材不许比别的特效粗一个数量级
	# ══════════════════════════════════════════════════════════════
	print("-- 9 像素密度(素材尺寸 ↔ 它要覆盖的场地范围) --")
	## 素材烤的时候每格覆盖 2 × 0.525 × BLADE_R_OUT 码(见 tools/gen_moonslash.py 的 VIEW)。
	## 这条把「贴图有多少像素」和「它要盖住多大地方」焊在一起 ——
	## 改了 MOON_CELL / BLADE_R_OUT 而没同步改 MOON_PIXEL_SIZE, 素材就会和判定范围对不上。
	var span_m: float = 1.05 * EQ.BLADE_R_OUT * _s.WS
	var cover_m: float = EQ.MOON_PIXEL_SIZE * float(EQ.MOON_CELL)
	_ok("⑨ %d px × %.3f 米/px = %.2f 米, 应等于 1.05 × R_OUT × WS = %.2f 米"
		% [EQ.MOON_CELL, EQ.MOON_PIXEL_SIZE, cover_m, span_m],
		absf(cover_m - span_m) < span_m * 0.02,
		"贴图覆盖范围与判定范围对不上 ⇒ 画在哪和打在哪就是两回事")
	## 与 007 剑气墙同档(不许粗一个数量级 —— 渲整圆盘那版是 0.40, 上屏是大色块)
	_ok("⑨b 像素密度 %.3f 米/px 与 007 剑气墙 %.3f 同档(不到 2 倍)"
		% [EQ.MOON_PIXEL_SIZE, EQ.BSW_WALL_PX],
		EQ.MOON_PIXEL_SIZE < EQ.BSW_WALL_PX * 2.0,
		"比别的特效粗一个数量级 = 上屏一堆大色块")
	_ok("⑩ MOON_ANCHOR %.0f == 判定带中心 (R_IN+R_OUT)/2 %.0f"
		% [EQ.MOON_ANCHOR, (EQ.BLADE_R_IN + EQ.BLADE_R_OUT) * 0.5],
		absf(EQ.MOON_ANCHOR - (EQ.BLADE_R_IN + EQ.BLADE_R_OUT) * 0.5) < 0.01,
		"素材是按【画布中心落在带心】烤的, 锚点一偏整条弧就错位")

	# ══════════════════════════════════════════════════════════════
	#  ⑪ 素材规格: 硬边 + 锁定调色板 + 表的排布对得上代码
	# ══════════════════════════════════════════════════════════════
	print("-- 11 素材规格: 硬边 + 锁定调色板 --")
	var sheets: Array = [["预警区", EQ.MOON_BAND_TEX, 1],
		["斩痕", EQ.MOON_SLASH_TEX, EQ.MOON_SLASH_FRAMES]]
	var band_img: Image = null
	var slash_img: Image = null
	for pair in sheets:
		var nm: String = str(pair[0])
		var tex: Texture2D = load(str(pair[1]))
		_ok("★分母: %s 素材在盘上" % nm, tex != null, str(pair[1]))
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img == null:
			_ok("%s: 读得到像素" % nm, false, "get_image() 为 null")
			continue
		if img.is_compressed():
			img.decompress()
		if nm == "预警区":
			band_img = img
		else:
			slash_img = img
		_ok("%s 尺寸 %dx%d = %d 向 × %d 帧 × %d px" % [nm, img.get_width(), img.get_height(),
			EQ.MOON_DIRS, int(pair[2]), EQ.MOON_CELL],
			img.get_width() == EQ.MOON_DIRS * EQ.MOON_CELL
			and img.get_height() == int(pair[2]) * EQ.MOON_CELL,
			"表的排布与代码的 hframes/vframes 对不上 ⇒ 选帧会选到别的格")
		var cols := {}
		var semi := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				if c.a < 1.0:
					semi += 1
				cols[Vector3i(int(c.r8), int(c.g8), int(c.b8))] = true
		_ok("%s 零半透边缘(实测 %d px)" % [nm, semi], semi == 0, "有半透 = 抗锯齿 = 不是像素画")
		_ok("%s 用色 %d 种 <= 6(锁定调色板)" % [nm, cols.size()], cols.size() <= 6,
			"超过就是没走 tools/pixelize_sheet.py 的锁定板")

	# ══════════════════════════════════════════════════════════════
	#  ⑫ ★预警必须是【一片填充的区域】, 不是几条线
	# ══════════════════════════════════════════════════════════════
	## ★★这一条是**照着被用户否掉的那一版立的**(2026-09-09):
	##   我把预警从"一整片半透扇带"改成"三条开口的同心弧", 面积感为零,
	##   用户第一眼就问「这个特效是什么鬼」。逐帧看完上一代 100 帧才明白:
	##   预警最重要的信息是**这一整片要挨打**, 只画边界等于什么都没说。
	##   ⇒ 判据落在**覆盖面积占扇区理论面积的比例**, 三条细弧会当场红。
	print("-- 12 预警是填充的区域, 不是几条线 --")
	if band_img != null:
		var opaque := 0
		for y in range(EQ.MOON_CELL):
			for x in range(EQ.MOON_CELL):
				if band_img.get_pixel(x, y).a > 0.0:
					opaque += 1
		## 环形扇区面积 = (Δθ/2)(R_out² − R_in²); 画布是 (2·MOON_VIEW)² 码² 摊在 CELL² 像素上
		var sector_yd2: float = deg_to_rad(EQ.BLADE_ARC_DEG) * 0.5 * (EQ.BLADE_R_OUT * EQ.BLADE_R_OUT - EQ.BLADE_R_IN * EQ.BLADE_R_IN)
		var canvas_yd2: float = (2.0 * EQ.MOON_VIEW) * (2.0 * EQ.MOON_VIEW)
		var expect_px: float = sector_yd2 / canvas_yd2 * float(EQ.MOON_CELL * EQ.MOON_CELL)
		var ratio: float = float(opaque) / maxf(1.0, expect_px)
		## ★覆盖率只当**下限**用: 填充走 Bayer 有序抖动(半调网点), 稀疏处故意透出地面,
		##   所以不可能也不应该接近 100%。真正的判据是下面那条【铺展检查】。
		_ok("⑫ 预警覆盖 %d px = 扇区理论面积 %.0f px 的 %d%%(须 >=55%%)" % [opaque, expect_px, int(ratio * 100.0)],
			ratio >= 0.55,
			"只画边界/几条弧 = 面积感为零, 用户看不出这一整片要挨打")
		## ★★铺展检查: 把扇区切成 6 径向 × 8 角向 = 48 个子格, **每一格都得有内容**。
		##   这一条才是能红"三条细弧"那一版的判据 —— 细弧只占几行子格, 会留下大片空格;
		##   而它对抖动免疫(抖动是均匀稀疏的, 每个子格里都有点)。
		var grid := []
		for gi in range(48):
			grid.append(0)
		for y in range(EQ.MOON_CELL):
			for x in range(EQ.MOON_CELL):
				if band_img.get_pixel(x, y).a <= 0.0:
					continue
				var gx: float = (float(x) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW + EQ.MOON_ANCHOR
				var gy: float = (float(y) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW
				var gr: float = Vector2(gx, gy).length()
				var ga: float = atan2(gy, gx)
				if gr < EQ.BLADE_R_IN or gr > EQ.BLADE_R_OUT or absf(ga) > deg_to_rad(EQ.BLADE_ARC_DEG * 0.5):
					continue
				var ri: int = mini(5, int((gr - EQ.BLADE_R_IN) / (EQ.BLADE_R_OUT - EQ.BLADE_R_IN) * 6.0))
				var ai: int = mini(7, int((ga + deg_to_rad(EQ.BLADE_ARC_DEG * 0.5)) / deg_to_rad(EQ.BLADE_ARC_DEG) * 8.0))
				grid[ri * 8 + ai] += 1
		var empty := 0
		for v in grid:
			if int(v) == 0:
				empty += 1
		_ok("⑫ ★铺展: 扇区切 6×8=48 个子格, 空格 %d 个(须 0)" % empty, empty == 0,
			"有空子格 = 预警没铺满这一片 = 只画了边界; 这条对抖动免疫, 专门红'三条细弧'那一版")
		## 同时不许**越界**画: 画出来的范围必须 == 打得到的范围
		var out_of_band := 0
		for y in range(EQ.MOON_CELL):
			for x in range(EQ.MOON_CELL):
				if band_img.get_pixel(x, y).a <= 0.0:
					continue
				var fx: float = (float(x) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW + EQ.MOON_ANCHOR
				var fy: float = (float(y) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW
				var rr: float = Vector2(fx, fy).length()
				if rr < EQ.BLADE_R_IN - 6.0 or rr > EQ.BLADE_R_OUT + 6.0:
					out_of_band += 1
		_ok("⑫ 预警没有画到判定带外(越界 %d px, 容差 6 码)" % out_of_band, out_of_band == 0,
			"画在带外 = 敌人身上画了光却不掉血 = 演出与判定不一致")

	# ══════════════════════════════════════════════════════════════
	#  ⑬ 方向表逐格量(新尺子: 以【释放点】为原点量平均角)
	# ══════════════════════════════════════════════════════════════
	## ★上一版的尺子量「最亮档相对整体质心的方向」—— 那是给"最亮档在外缘"的月牙用的。
	##   新斩痕的最亮档是**热核, 在正中**, 那把尺子当场失效。换尺子必须重新自证。
	## ★分母要够: 末帧只剩两百来个碎块, 拿它量方向会读出 +9.82°(实测) —— 不是素材偏了,
	##   是样本太散。所以只在**峰值帧**上量, 并断言分母。
	## ★★2026-09-09 换过一次口径, 记住为什么: 斩痕改成【扫过式】之后, 单帧是**故意不对称的**
	##   (刀刃在扫到的那一头、拖痕往回拖) ⇒ 拿单帧量"全部像素的平均角"会读出 +10.4° 而不是 0°,
	##   而素材一点没错。这是**尺子没跟着被测概念一起改**, 不是方向表烤反了。
	##   ⇒ 改量【五帧的并集】: 扫完之后覆盖的是整个对称扇区, 平均角必须回到 0°,
	##     既是能自证的已知答案, 又确实量的是斩痕这张表本身。
	##   (memory fb-verify-check-can-fail: 「能红」不证明它读的是那个量。)
	print("-- 13 方向表逐格(量五帧并集, 先自证) --")
	if slash_img != null:
		var angs: Array = []
		var cnts: Array = []
		for d in range(EQ.MOON_DIRS):
			var rv: Vector2 = _cell_dir(slash_img, d, -1)
			angs.append(rv.x)
			cnts.append(int(rv.y))
		_ok("★尺子自证: d0 量得 %.2f°(已知答案 0°)" % float(angs[0]), absf(float(angs[0])) < 3.0,
			"尺子在已知答案上就读错了, 下面 16 格全部不可信")
		var mincnt: int = 999999
		for cv in cnts:
			mincnt = mini(mincnt, int(cv))
		_ok("★分母: 并集每格至少 3000 个像素(最少 %d)" % mincnt, mincnt >= 3000,
			"样本太散时方向重心不稳, 量出来的角不可信")
		var bad := 0
		for d in range(EQ.MOON_DIRS):
			var want: float = 360.0 * float(d) / float(EQ.MOON_DIRS)
			var err: float = absf(fposmod(float(angs[d]) - want + 180.0, 360.0) - 180.0)
			if err > 3.0:
				bad += 1
				print("     d%d 应 %.1f° 实 %.1f° 差 %.1f°" % [d, want, float(angs[d]), err])
		_ok("⑬ %d 格逐格量, 超差(>3°) %d 格" % [EQ.MOON_DIRS, bad], bad == 0,
			"哪一格偏了就是那一格烤反了 —— 007 的剑气墙曾八格一致偏 175°, 肉眼看不出来")

	# ══════════════════════════════════════════════════════════════
	#  ⑭ ★斩痕必须【扫过去】且【盖满整条判定带】
	# ══════════════════════════════════════════════════════════════
	## ★★这一整节是照着用户 2026-09-09 的三句话立的, 每条对应一个当时真存在的缺陷:
	##   ①「更亮的线你这没有从一边到另一边的感觉啊」
	##      ⇒ 当时斩痕**每一帧都跨满 60 度**(实测 f0~f3 全是 -30.1~30.0), 是原地张开不是扫。
	##   ②「更亮的线根本比预警区小太多啊, 预警是告诉玩家要实际产生伤害的地区啊」
	##      ⇒ 当时斩痕最宽 166 码而判定带宽 304 码, 只盖 55% —— 看见细细一道却整片掉血,
	##        正是通病「画出来的和打到的不是一回事」。
	##   ③ 消散不许靠变暗(旧版实拍 #44-46 把颜色压暗成灰板)。
	print("-- 14 斩痕: 扫过去 + 盖满判定带 + 消散靠碎不靠暗 --")
	if slash_img != null:
		var fpx: Array = []
		var flum: Array = []
		var lead: Array = []
		var rmin: Array = []
		var rmax: Array = []
		var union := {}
		for f in range(EQ.MOON_SLASH_FRAMES):
			var n2 := 0
			var s2 := 0.0
			var la := -999.0
			var r0 := 9999.0
			var r1 := 0.0
			for y in range(EQ.MOON_CELL):
				for x in range(EQ.MOON_CELL):
					var cc: Color = slash_img.get_pixel(x, f * EQ.MOON_CELL + y)
					if cc.a <= 0.0:
						continue
					n2 += 1
					s2 += cc.r * 0.299 + cc.g * 0.587 + cc.b * 0.114
					var fx: float = (float(x) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW + EQ.MOON_ANCHOR
					var fy: float = (float(y) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW
					var rr: float = Vector2(fx, fy).length()
					var aa: float = rad_to_deg(atan2(fy, fx))
					la = maxf(la, aa)
					r0 = minf(r0, rr)
					r1 = maxf(r1, rr)
					union[Vector2i(x, y)] = true
			fpx.append(n2)
			flum.append(0.0 if n2 == 0 else s2 / float(n2))
			lead.append(la)
			rmin.append(r0)
			rmax.append(r1)
			print("     f%d 像素%5d 亮度%.3f 领先边%+6.1f° 径向 %.0f~%.0f 码(宽 %.0f)"
				% [f, n2, float(flum[f]), la, r0, r1, r1 - r0])

		## ── ①「从一边到另一边」: 领先边必须逐帧单调右移, 且真的扫完全程 ──
		## ★★判据的**时间范围**要卡对: 碎开之后根本没有"领先边"这个东西 ——
		##   碎裂会随机去掉最外侧那块, 于是"剩余碎片的最大角"会回退(实测 +30.1 → +28.2),
		##   而素材一点没错。第一版对全部 5 帧判单调, 当场误报。
		##   ⇒ 用【领先边到达峰值的那一帧】自动定界(不写死帧号), 只在扫的那几帧上判单调;
		##     并要求峰值**不在最后一帧** —— 扫完之后必须还留有帧用来碎开。
		##   (与 ⑬ 那把尺子同族: 判据没跟着被测概念一起改。)
		var lead_peak := 0
		for f in range(EQ.MOON_SLASH_FRAMES):
			if float(lead[f]) > float(lead[lead_peak]):
				lead_peak = f
		var mono := true
		for f in range(1, lead_peak + 1):
			if float(lead[f]) < float(lead[f - 1]) - 0.5:
				mono = false
		_ok("⑭ ★领先边在扫的那几帧里单调右移, 峰值在 f%d (%s)"
			% [lead_peak, " → ".join(lead.map(func(v): return "%+.1f" % float(v)))],
			mono and lead_peak > 0,
			"每帧都跨满全角 = 原地张开不是扫; 用户说的『没有从一边到另一边的感觉』就是这个")
		_ok("⑭ ★扫在最后一帧之前完成(峰值 f%d < 末帧 f%d), 之后才是碎开"
			% [lead_peak, EQ.MOON_SLASH_FRAMES - 1], lead_peak < EQ.MOON_SLASH_FRAMES - 1,
			"扫到最后一帧才完 = 没有留给碎开的时间")
		var swept: float = float(lead[lead_peak]) - float(lead[0])
		_ok("⑭ ★真的扫过了 %.1f°(须 >= 全角 %.0f° 的一半)" % [swept, EQ.BLADE_ARC_DEG],
			swept >= EQ.BLADE_ARC_DEG * 0.5,
			"扫的幅度太小 = 看不出是一刀扫过去")

		## ── ②「画的不能比打的小」: 每一帧的径向宽度都要盖满判定带 ──
		var hitband_w: float = EQ.BLADE_R_OUT - EQ.BLADE_R_IN
		var thin := 0
		for f in range(EQ.MOON_SLASH_FRAMES):
			if float(rmax[f]) - float(rmin[f]) < hitband_w * 0.95:
				thin += 1
		_ok("⑭ ★每帧都盖满判定带(%.0f 码), 偏窄的帧 %d 个" % [hitband_w, thin], thin == 0,
			"斩痕比伤害区窄 = 玩家看见细细一道却整片掉血 = 画出来的和打到的不是一回事")
		## 扫完之后整片都要被切过 —— 与预警的铺展检查同一把尺子
		var g2 := []
		for gi in range(48):
			g2.append(0)
		for k in union.keys():
			var ux: float = (float(k.x) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW + EQ.MOON_ANCHOR
			var uy: float = (float(k.y) + 0.5) / float(EQ.MOON_CELL) * 2.0 * EQ.MOON_VIEW - EQ.MOON_VIEW
			var ur: float = Vector2(ux, uy).length()
			var ua: float = atan2(uy, ux)
			if ur < EQ.BLADE_R_IN or ur > EQ.BLADE_R_OUT or absf(ua) > deg_to_rad(EQ.BLADE_ARC_DEG * 0.5):
				continue
			var ri2: int = mini(5, int((ur - EQ.BLADE_R_IN) / (EQ.BLADE_R_OUT - EQ.BLADE_R_IN) * 6.0))
			var ai2: int = mini(7, int((ua + deg_to_rad(EQ.BLADE_ARC_DEG * 0.5)) / deg_to_rad(EQ.BLADE_ARC_DEG) * 8.0))
			g2[ri2 * 8 + ai2] += 1
		var e2 := 0
		for v in g2:
			if int(v) == 0:
				e2 += 1
		_ok("⑭ ★五帧并集铺展: 48 子格空 %d 个(须 0 —— 扫完整片都被切过)" % e2, e2 == 0,
			"有子格从没被切过 = 那块地会掉血但从头到尾没画东西")

		## ── ③ 消散靠碎不靠暗 ──
		var peak_i := 0
		for f in range(EQ.MOON_SLASH_FRAMES):
			if int(fpx[f]) > int(fpx[peak_i]):
				peak_i = f
		var shrink := true
		for f in range(peak_i + 1, EQ.MOON_SLASH_FRAMES):
			if int(fpx[f]) >= int(fpx[f - 1]):
				shrink = false
		_ok("⑭ 峰值在 f%d, 之后逐帧变少(碎开)" % peak_i, shrink and peak_i < EQ.MOON_SLASH_FRAMES - 1,
			"末尾不减少 = 没有在碎")
		## ★判据从「首帧 vs 末帧」改成「满帧 vs 末帧」: 扫过式下首帧只是一小片刀刃(几乎全是热核),
		##   平均亮度天然最高, 拿它当基线会把正常的扫判成变暗。要卡的是**消散那一段**有没有被压暗。
		var drop: float = float(flum[peak_i]) - float(flum[EQ.MOON_SLASH_FRAMES - 1])
		_ok("⑭ 末帧亮度 %.3f vs 满帧(f%d) %.3f, 掉 %.3f(须 <0.05)"
			% [float(flum[EQ.MOON_SLASH_FRAMES - 1]), peak_i, float(flum[peak_i]), drop], drop < 0.05,
			"颜色被压暗 = 淡出病 = 黑场上读成灰板; 消散该交给代码侧 alpha")
		var dup := 0
		for f in range(1, EQ.MOON_SLASH_FRAMES):
			if int(fpx[f]) == int(fpx[f - 1]):
				dup += 1
		_ok("⑭ %d 帧没有重样的(重复 %d 对)" % [EQ.MOON_SLASH_FRAMES, dup], dup == 0, "两帧一模一样 = 白演一帧")

	# ══════════════════════════════════════════════════════════════
	#  ⑮ ★「画的方向」与「打的方向」必须是同一个
	# ══════════════════════════════════════════════════════════════
	## 贴图只有 16 档而判定用真实角 ⇒ 最多差 11.25°, 在带心 650 码处两端错开约 127 码。
	## 解法不是加档位, 是让判定也用吸附后的角 ⇒ 差值恒为 0。
	print("-- 15 画的方向 == 打的方向 --")
	var inv_bad := 0
	for k in range(EQ.MOON_DIRS):
		if _s._equip_sys._ground_dir_frame(_s._equip_sys._moon_dir_of(k), EQ.MOON_DIRS) != k:
			inv_bad += 1
	_ok("⑮ _moon_dir_of 与 _ground_dir_frame 严格互逆(%d 档全过)" % EQ.MOON_DIRS, inv_bad == 0,
		"两者不互逆 ⇒ 吸附回来的轴和贴图那一格不是同一个方向")
	## 吸附真的发生了: 一个不在 22.5° 网格上的角必须被拉到网格上
	var off_dir := Vector2(cos(deg_to_rad(10.0)), sin(deg_to_rad(10.0)))
	var snapped: Vector2 = _s._equip_sys._moon_dir_of(_s._equip_sys._ground_dir_frame(off_dir, EQ.MOON_DIRS))
	var snap_deg: float = rad_to_deg(atan2(snapped.y, snapped.x))
	_ok("⑮ 10° 被吸附到 %.1f°(必须是 22.5° 的整数倍)" % snap_deg,
		absf(fposmod(snap_deg, 360.0 / float(EQ.MOON_DIRS))) < 0.01, "没吸附 = 画的和打的还是两个角")

	# ══════════════════════════════════════════════════════════════
	#  ⑯ 预警的 alpha 包络: 从 0 淡入 + 脉动两个来回 + 全程半透
	# ══════════════════════════════════════════════════════════════
	## 上一代实拍逐帧量到: 从 alpha 0 淡入, 0.56 秒里峰-谷-峰-谷-峰, 且单位始终画在它上面。
	## 这三件是它"有呼吸感"且"不挡视野"的原因, 一条都不能丢。
	print("-- 16 预警 alpha 包络 --")
	var a0: float = _s._equip_sys._moon_tel_alpha(0.0)
	_ok("⑯ u=0 时 alpha=%.3f(必须从 0 淡入)" % a0, absf(a0) < 0.001, "一出生就满 = 突然出现")
	var amax := 0.0
	var peaks := 0
	var prev := -1.0
	var prev2 := -1.0
	for i in range(201):
		var u: float = float(i) / 200.0
		var av: float = _s._equip_sys._moon_tel_alpha(u)
		amax = maxf(amax, av)
		if prev2 >= 0.0 and prev > prev2 and prev >= av:
			peaks += 1
		prev2 = prev
		prev = av
	_ok("⑯ 峰值 alpha %.3f <= 0.60(半透, 单位要能画在它上面)" % amax, amax <= 0.60,
		"太不透明 = 挡住脚下的单位 = 上一代实心板的读感又回来了")
	_ok("⑯ 脉动 %d 个峰(须 2 个来回)" % peaks, peaks == 2, "不脉动 = 没有呼吸感")

	# ══════════════════════════════════════════════════════════════
	#  ⑰ 真入口是不是真的用了这两张素材, 且斩痕叠在预警上
	# ══════════════════════════════════════════════════════════════
	print("-- 17 真入口用的是这两张素材 --")
	var seen_band := false
	var seen_slash := false
	var frame_ok := true
	## ★★「斩痕出现时预警还在场」这条第一版写成"某一刻场上同时有两种贴图"——**是假判据**。
	##   2026-09-09 反向验证实测: 把代码改回"先 queue_free 预警再建斩痕", 它**照样全绿**。
	##   两个原因: ① `queue_free()` 是延迟删除, 同一帧里两者都还在树上;
	##             ② 前面几节留下的精灵也会被算进来(被测对象根本不是这一次施放的)。
	##   ⇒ 改成因果绑定的判据: **只看这一次施放新建的节点**, 且在【斩痕首次出现的那一帧】
	##     要求预警 ①还在树上 ②alpha>0.05 ③**没有被 queue_free**。
	##     (memory fb-gate-tautological-when-it-spans-a-frame / fb-gate-subject-never-constructed)
	var overlap := false
	var overlap_why := "斩痕始终没出现"
	var pre_ids := {}
	for ch0 in _s._world.get_children():
		pre_ids[ch0.get_instance_id()] = true
	var t2: int = Time.get_ticks_msec() + 12000
	var owner2: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-390.0, 0.0))
	owner2["no_basic"] = true
	owner2["no_move"] = true
	_s._units.append(owner2)
	_s._equip_sys._eq_wide_blade(owner2, real_foes[1], 2)
	while Time.get_ticks_msec() < t2 and not seen_slash:
		await get_tree().process_frame
		if not is_instance_valid(_s) or not is_instance_valid(_s._world):
			break
		var new_band: Sprite3D = null
		var new_slash: Sprite3D = null
		for ch in _s._world.get_children():
			if not (ch is Sprite3D) or pre_ids.has(ch.get_instance_id()):
				continue          # ★只看这一次施放新建的, 别把前面几节的残留算进来
			var t: Texture2D = (ch as Sprite3D).texture
			if t == null:
				continue
			var rp: String = t.resource_path
			if rp != EQ.MOON_BAND_TEX and rp != EQ.MOON_SLASH_TEX:
				continue
			if rp == EQ.MOON_BAND_TEX:
				seen_band = true
				new_band = ch as Sprite3D
			else:
				new_slash = ch as Sprite3D
			if (ch as Sprite3D).frame % EQ.MOON_DIRS != 0:
				frame_ok = false
			if (ch as Sprite3D).texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				frame_ok = false
		if new_slash != null:
			seen_slash = true       # ★只在【斩痕首次出现】这一帧判一次, 之后不再改口
			if new_band == null:
				overlap_why = "斩痕出现时预警已经不在树上了"
			elif new_band.is_queued_for_deletion():
				overlap_why = "斩痕出现时预警已被 queue_free(延迟删除也算收掉)"
			elif new_band.modulate.a <= 0.05:
				overlap_why = "斩痕出现时预警 alpha=%.3f, 等于看不见" % new_band.modulate.a
			else:
				overlap = true
				overlap_why = "预警 alpha=%.3f, 斩痕叠在它上面" % new_band.modulate.a
	_ok("⑰ 预警区真的出现在场上", seen_band, "没建出来 = 素材白做了")
	_ok("⑰ 斩痕真的出现在场上", seen_slash, "没建出来 = 素材白做了")
	_ok("⑰ ★斩痕出现时预警【还亮着】: %s" % overlap_why, overlap,
		"预警收掉再出现月牙 = 因果链断掉, 正是 2026-09-09 被否掉的那一版的毛病")
	## 本用例里敌人正在携带者的正右方(场地 +x)⇒ 方向格必须是 0
	_ok("⑰ 方向格选的是朝敌人那一格 + 贴图是 NEAREST", frame_ok, "选帧恒 0 或没设 NEAREST")

	_done()


## 【以释放点为原点】量一格的平均朝向, 返回 Vector2(角度°, 参与像素数)。
##
## ★为什么换掉旧尺子: 旧的量「最亮档质心 相对 整体质心」的方向, 那是给"最亮档在外缘"
##   的月牙用的。新斩痕的最亮档是**热核, 在正中**, 旧尺子当场失效(读出来的方向没有意义)。
## ★为什么原点是释放点而不是格心: 素材是按「画布中心 = 释放点 + dir × MOON_ANCHOR」烤的,
##   扇区是以**释放点**为圆心张开的 ⇒ 只有从释放点看过去, 平均角才等于瞄准角。
##   释放点在格内的像素坐标 = 格心 − dir × (ANCHOR / VIEW) × (CELL/2)。
## ★返回像素数是为了让调用方**断言分母**: 末帧只剩两百来个碎块时重心不稳,
##   实测会读出 +9.82° —— 那不是素材偏了, 是样本太散(2026-09-09 差点据此去"修"没坏的素材)。
## `row = -1` ⇒ 量**所有帧的并集**(见下面的说明)。
func _cell_dir(img: Image, d: int, row: int) -> Vector2:
	var cell: int = EQ.MOON_CELL
	var th: float = TAU * float(d) / float(EQ.MOON_DIRS)
	var k: float = EQ.MOON_ANCHOR / EQ.MOON_VIEW * (float(cell) * 0.5)
	var cx: float = float(cell) * 0.5 - cos(th) * k
	var cy: float = float(cell) * 0.5 - sin(th) * k
	var rows: int = int(img.get_height() / cell)
	var r0: int = row
	var r1: int = row
	if row < 0:
		r0 = 0
		r1 = rows - 1
	var sx := 0.0
	var sy := 0.0
	var n := 0
	for y in range(cell):
		for x in range(cell):
			var on := false
			for rr in range(r0, r1 + 1):
				if img.get_pixel(d * cell + x, rr * cell + y).a > 0.0:
					on = true
					break
			if not on:
				continue
			var a: float = atan2((float(y) + 0.5) - cy, (float(x) + 0.5) - cx)
			sx += cos(a)
			sy += sin(a)
			n += 1
	if n == 0:
		return Vector2(-999.0, 0.0)
	return Vector2(rad_to_deg(atan2(sy, sx)), float(n))


func _done() -> void:
	print("---- %d 条断言, %d 条 FAIL ----" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	else:
		print("FAILED")
	if _s != null and is_instance_valid(_s):
		_s.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
