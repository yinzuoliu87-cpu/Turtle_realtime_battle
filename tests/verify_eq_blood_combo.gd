extends Node
## verify_eq_blood_combo.gd —— 011「饮血护符坠」连斩的美术 + 演出 + 接线门禁。
##
## ★★为什么要这一份: 重做之前 011 的美术侧**一条断言都没有**, 于是
##   斩痕是程序生成的 92 色 / 1938 半透、末帧平均亮度只有峰值的 30%、
##   5 帧里有 2 帧逐像素相同、`from2d` 是个函数体一次都没读的死参数 —— 而门禁全绿。
##   (memory `fb-weld-visual-lessons-into-gate`: memory 靠我想起来, 门禁自己会红。)
##
## ★★★判据照着装备文案逐条钉:
##   「该法器**法力条集满**时**连斩 5/6/8 次**随机敌人，每次造成…物理伤害
##     （**后续每发逐渐衰减**）；携带者的溢出治疗转化为血护盾（上限 200/350/500）。」
##   ⇒ 画面上必须读得出的三件事, 各配一条:
##     ①「连」  → ⑦ 斩痕个数 == 刀数 & ⑧ 相邻两刀间隔恒为 BLOOD_BEAT
##     ②「随机敌」→ ⑥ 真入口(法力满 → StaffSynergy → _eq_bloodletting)敌人真的掉血
##     ③「逐渐衰减」→ ⑨ **画多大就是打多重**: 第 k 刀斩痕的世界宽度比 == 实测伤害比
##   文案没提预警/蓄力 ⇒ **不许加**(011 的"因"是装备框里那条紫色法力条, 它一直在屏幕上)。
##
## ★⑨ 是**非循环**的: 宽度取自演出真的建出来的精灵、伤害取自假人真的掉的血,
##   两边都是**跑出来的**, 不是拿同一个 `blood_decay()` 自乘一遍。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const BC := preload("res://scripts/systems/equip/eq_blood_combo.gd")

var _s = null
var _n := 0
var _fail := 0
var _img_cache := {}


func _ok(msg: String, cond: bool, extra: String = "") -> void:
	_n += 1
	if cond:
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [msg, extra])


func _spec(path: String) -> Array:
	var tex: Texture2D = load(path)
	if tex == null:
		return [-1, -1]
	var img: Image = tex.get_image()
	var cols := {}
	var semi := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var a: int = int(round(c.a * 255.0))
			if a <= 0:
				continue
			if a < 255:
				semi += 1
			cols["%d_%d_%d" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]] = true
	return [cols.size(), semi]


## 取一格(变体 vi, 帧 f)。表的排布是 (cell×变体, cell×帧): **变体在 X, 帧在 Y**。
func _cell(path: String, vi: int, f: int, cell: int) -> Image:
	if not _img_cache.has(path):
		_img_cache[path] = (load(path) as Texture2D).get_image()
	return (_img_cache[path] as Image).get_region(Rect2i(vi * cell, f * cell, cell, cell))


## 一格的 (不透明像素数, 平均亮度)
func _cell_stat(im: Image) -> Array:
	var n := 0
	var sum := 0.0
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c: Color = im.get_pixel(x, y)
			if c.a <= 0.03:
				continue
			n += 1
			sum += (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
	return [n, sum / maxf(1.0, float(n))]


## 场上现有的斩痕精灵(按 texture 认, 不数我插的标记)
func _live_slashes() -> Array:
	var out: Array = []
	if _s == null or not is_instance_valid(_s._world):
		return out
	for c in _s._world.get_children():
		if c is Sprite3D and c.texture != null and str(c.texture.resource_path) == BC.BLOOD_SLASH_TEX:
			out.append(c)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true   # 台子绝不写玩家存档(memory fb-debug-stage-writes-real-save)
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame

	print("")
	print("═══ 011 饮血护符坠 · 连斩素材/演出/接线 ═══")
	var CELL: int = int(BC.BLOOD_SLASH_CELL)

	# ══════════════════════════════════════════════════════════════
	#  ① 素材规格: 斩击表 + 图标都必须是锁定调色板的像素画
	# ══════════════════════════════════════════════════════════════
	print("-- 1 素材规格(色数 / 半透像素) --")
	var files := {
		"连斩斩痕": BC.BLOOD_SLASH_TEX,
		"图标": "res://assets/sprites/equip/eq011-icon.png",
	}
	var checked := 0
	for name in files.keys():
		var sp: Array = _spec(String(files[name]))
		checked += 1
		_ok("① %s 是像素画: %d 色(须 1~8) / %d 半透(须 0)" % [name, sp[0], sp[1]],
			sp[0] >= 1 and sp[0] <= 8 and sp[1] == 0,
			"旧的是 92 色 / 1938 半透(斩痕)、71 色 / 3721 半透(图标) —— 那是渲染图不是像素画")
	_ok("★分母: 查了 %d 张素材(应 2)" % checked, checked == 2)

	# ══════════════════════════════════════════════════════════════
	#  ② 五帧**帧帧不同** + 四变体互不相同
	# ══════════════════════════════════════════════════════════════
	print("-- 2 五帧帧帧不同 / 四变体互不相同(旧版帧1与帧2逐像素相同) --")
	var sigs := {}
	var empty_cells := 0
	var same_pairs: Array = []
	for vi in range(BC.BLOOD_SLASH_VARIANTS):
		for f in range(BC.BLOOD_SLASH_FRAMES):
			var im: Image = _cell(BC.BLOOD_SLASH_TEX, vi, f, CELL)
			var st: Array = _cell_stat(im)
			if int(st[0]) == 0:
				empty_cells += 1
			var key: String = im.get_data().hex_encode().md5_text()
			if sigs.has(key):
				same_pairs.append("%s == %s" % [sigs[key], "v%d_f%d" % [vi, f]])
			sigs[key] = "v%d_f%d" % [vi, f]
	var want_cells: int = BC.BLOOD_SLASH_VARIANTS * BC.BLOOD_SLASH_FRAMES
	_ok("★分母: 查了 %d 格(应 %d), 空格 %d 个(须 0)" % [sigs.size() + same_pairs.size(), want_cells, empty_cells],
		sigs.size() + same_pairs.size() == want_cells and empty_cells == 0)
	_ok("② %d 格两两互不相同(重复 %d 对)" % [want_cells, same_pairs.size()], same_pairs.is_empty(),
		"重复的: %s —— 旧版 5 帧只有 4 帧不同, 播起来会卡一拍" % str(same_pairs))

	# ══════════════════════════════════════════════════════════════
	#  ③ 消散靠碎不靠淡
	# ══════════════════════════════════════════════════════════════
	print("-- 3 消散靠碎开不靠变暗(旧素材末帧只有峰值的 30%) --")
	var worst_ratio := 9.0
	var worst_v := -1
	var lum_dump: Array = []
	for vi in range(BC.BLOOD_SLASH_VARIANTS):
		var lum: Array = []
		var npx: Array = []
		for f in range(BC.BLOOD_SLASH_FRAMES):
			var st: Array = _cell_stat(_cell(BC.BLOOD_SLASH_TEX, vi, f, CELL))
			npx.append(int(st[0]))
			lum.append(float(st[1]))
		var fullest := 0
		for f in range(npx.size()):
			if int(npx[f]) > int(npx[fullest]):
				fullest = f
		var lo := 9999.0
		for v in lum:
			lo = minf(lo, float(v))
		var r: float = lo / maxf(1.0, float(lum[fullest]))
		if vi == 0:
			lum_dump = lum
		if r < worst_ratio:
			worst_ratio = r
			worst_v = vi
	_ok("③ 逐帧平均亮度最低 / 最满帧 = %.0f%%(最差是变体 %d; 须 ≥ 70%%)" % [worst_ratio * 100.0, worst_v],
		worst_ratio >= 0.70,
		"靠压暗来消散 = 黑地上读成一抹暗棕。变体 0 逐帧 %s" % str(lum_dump))

	# ══════════════════════════════════════════════════════════════
	#  ④ 两个步长都必须落在 sim 步边界上
	# ══════════════════════════════════════════════════════════════
	print("-- 4 步长必须是 SIM_DT 的整数倍(否则 _wait_sim 向上取整, 节奏变慢) --")
	for pair in [["BLOOD_SLASH_STEP", BC.BLOOD_SLASH_STEP], ["BLOOD_BEAT", BC.BLOOD_BEAT]]:
		var q: float = float(pair[1]) / _s.SIM_DT
		_ok("④ %s = %.5f 秒 = %.3f × SIM_DT(余 %.4f ≤ 0.01)" % [pair[0], float(pair[1]), q, absf(q - round(q))],
			absf(q - round(q)) <= 0.01,
			"会被 _wait_sim 向上取整 ⇒ 画面节奏比常量写的慢(010 的 LASER_CHOP_STEP 上踩过)")

	# ══════════════════════════════════════════════════════════════
	#  ⑤ 斩痕落点朝【携带者那一侧】—— from2d 不再是死参数
	# ══════════════════════════════════════════════════════════════
	print("-- 5 落点朝携带者一侧(旧版 from2d 是死参数, 斩痕凭空出现在敌人身上) --")
	var tgt := Vector2(500.0, 300.0)
	var l_at: Vector2 = _s._equip_sys._blood_sys.blood_slash_at(tgt + Vector2(-200.0, 0.0), tgt)
	var r_at: Vector2 = _s._equip_sys._blood_sys.blood_slash_at(tgt + Vector2(200.0, 0.0), tgt)
	_ok("⑤ 携带者在左 ⇒ 落点也在左(dx = %.1f < 0)" % (l_at.x - tgt.x), l_at.x - tgt.x < -1.0)
	_ok("⑤ 携带者在右 ⇒ 落点跟着翻到右(dx = %.1f > 0)" % (r_at.x - tgt.x), r_at.x - tgt.x > 1.0,
		"不跟着翻 = from2d 又成了死参数")
	_ok("⑤ 偏移量 %.1f 码 == BLOOD_ENTER %.0f(±1)" % [l_at.distance_to(tgt), BC.BLOOD_ENTER],
		absf(l_at.distance_to(tgt) - BC.BLOOD_ENTER) <= 1.0)

	# ══════════════════════════════════════════════════════════════
	#  ⑥⑦⑧⑨⑩⑪ 真入口跑一遍, 一次采集全部演出证据
	# ══════════════════════════════════════════════════════════════
	print("-- 6 真入口: StaffSynergy 法力满 → fire_equip_effect → _eq_bloodletting --")
	print("     [探针] 清场前 _s._units = %d 个" % _s._units.size())
	_s._units.clear()
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	## ★★平台三件套 + **暴击必须关**: `_resolve_dmg` 会掷暴击(×1.5),
	##   而 ⑨ 量的是【第 k 刀 / 第 0 刀】的**比值** —— 只要有一刀暴击整条就成了掷骰子。
	##   010 那一轮的 ⑩c 就是这么单跑三次全绿、进并行门禁当场红的
	##   (memory `fb-make-assertions-rng-insensitive`: 拿干净合成单位隔离随机, 别把判据放宽)。
	var carrier: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-160.0, 0.0))
	carrier["no_basic"] = true
	carrier["no_move"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["crit"] = 0.0
	carrier["maxHp"] = 1.0e8
	carrier["hp"] = 1.0e8
	carrier["equips"] = [{"id": "p2eq_011", "star": 3}]
	carrier["eq_state"] = {}
	## ★合成单位没走 `equip_stats_apply`, 所以 011 的血护盾上限要自己摆上 ——
	##   产品里这一行是 `equip_stats_apply.gd:249` 按星级给的 [200/350/500]。
	carrier["overheal2shield_cap"] = 500.0
	## ★携带者的**基础吸血保持 0**: 连斩每一刀自带 `extra_ls = 0.33`,
	##   那才是 011 自己的账。第一版我在这里摆了 `lifesteal = 0.33`, 结果反向验证
	##   把那 0.33 从 `_eq_bloodletting` 里拿掉、⑫ **照样绿** —— 因为盾是我喂的吸血转的,
	##   不是被测那件事转的(memory `fb-gate-must-measure-requirement-not-my-hook`)。
	_s._units.append(carrier)
	var foes: Array = []
	for i in range(3):
		var f2: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(60.0 + 70.0 * float(i), 0.0))
		f2["maxHp"] = 1.0e8
		f2["hp"] = 1.0e8
		f2["_st_taken"] = 0
		f2["no_move"] = true
		f2["move_spd"] = 0.0
		f2["no_basic"] = true
		f2["active_skills"] = []
		_s._units.append(f2)
		foes.append(f2)
	var si: int = _s._equip_sys._eq_si(3)
	var want_n: int = [5, 6, 8][si]
	_ok("★分母: 场上 %d 个单位(应 4), 3★ ⇒ si=%d ⇒ 应斩 %d 刀" % [_s._units.size(), si, want_n],
		_s._units.size() == 4 and want_n == 8)

	func_taken(foes)   # 预热: 让 _st_taken 都存在
	## ★★对照组: 同一个平台**不带 011**, 灌同样多法力 —— 必须一点伤害都打不出来。
	carrier["equips"] = []
	var ctrl0: int = func_taken(foes)
	_s._staff_syn.add_mana(carrier, 400.0)
	var ctrl_end: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < ctrl_end:
		await get_tree().process_frame
	_ok("⑥ 对照组(不带 011)承伤 %d(须 = 0)" % (func_taken(foes) - ctrl0), func_taken(foes) - ctrl0 == 0,
		"普攻/龟能技没关干净, 下面那些就量不到被测那件事")

	carrier["equips"] = [{"id": "p2eq_011", "star": 3}]
	carrier["eq_state"] = {}
	var base_taken: int = func_taken(foes)
	## 采集: 每帧扫一次场上新出现的斩痕精灵 + 假人这一帧掉了多少血
	var seen: Array = []          # 已记过的精灵
	var hit_t: Array = []         # 每一刀的游戏时刻
	var hit_w: Array = []         # 每一刀斩痕的世界宽度(码)
	var hit_d: Array = []         # 每一刀实际打出的伤害
	var frame_t: Array = []       # 第 0 刀那张斩痕每次换帧的游戏时刻
	## ★只盯**第一张**斩痕: 量的是"同一张图换帧的间隔"。
	##   第一版用 `watch == null` 当"还没盯上"的判据 —— 精灵 queue_free 之后那个引用
	##   会重新满足 `== null`, 于是它又去盯下一张, 量出来的就成了"跨刀的间隔"(0.167 秒),
	##   ⑩ 当场红而产品其实是对的。⇒ 换成一个显式布尔, 盯上就再也不换。
	var watch: Sprite3D = null
	var watched := false
	var watch_f: int = -1
	var prev_taken: int = base_taken
	_s._staff_syn.add_mana(carrier, 400.0)   # ★真入口: 灌满法力条(满值 200)
	var t_end: int = Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now_taken: int = func_taken(foes)
		for sp in _live_slashes():
			if sp in seen:
				continue
			seen.append(sp)
			hit_t.append(float(_s._t))
			hit_w.append(float(sp.pixel_size) * BC.BLOOD_SLASH_CELL / _s.WS)
			hit_d.append(now_taken - prev_taken)
			if not watched:
				watched = true
				watch = sp
				watch_f = sp.frame
				frame_t.append(float(_s._t))
		prev_taken = now_taken
		if watch != null and is_instance_valid(watch) and watch.frame != watch_f:
			watch_f = watch.frame
			frame_t.append(float(_s._t))
		if hit_t.size() >= want_n and float(_s._t) - float(hit_t[hit_t.size() - 1]) > BC.BLOOD_BEAT * 2.0:
			break
	var dealt: int = func_taken(foes) - base_taken
	print("     [探针] 采到 %d 刀; 时刻 %s" % [hit_t.size(), str(hit_t)])
	print("     [探针] 宽度(码) %s" % str(hit_w))
	print("     [探针] 伤害      %s" % str(hit_d))
	_ok("⑥ 真入口打出 %d 点伤害(须 > 0 —— 法力满 → StaffSynergy → _eq_bloodletting 这条链是通的)"
		% dealt, dealt > 0,
		"0 = 接线断了(add_mana 没到 fire_equip_effect, 或 fire_equip_effect 没路由到 011)")

	# ⑦ 刀数
	print("-- 7/8/9/10 连斩的节拍、衰减、一条钟 --")
	_ok("⑦ 连斩 %d 刀(3★ 文案写的是 8 刀)" % hit_t.size(), hit_t.size() == want_n,
		"少了 = 演出没跟上刀数; 多了 = 有别的东西也在建斩痕精灵")

	# ⑧ 节拍恒定
	if hit_t.size() >= 3:
		var gap_lo := 9.0
		var gap_hi := -9.0
		for i in range(1, hit_t.size()):
			var g: float = float(hit_t[i]) - float(hit_t[i - 1])
			gap_lo = minf(gap_lo, g)
			gap_hi = maxf(gap_hi, g)
		## ★★这条量的是【节拍**恒定**】, 不是【节拍等于 0.3】——
		##   文案只说「连斩 N 次」, 没说间隔多少, 所以 0.3 是可调的设计数, 不是它必须满足的声称。
		##   反向验证抓到过一次: 我原本写成「== BLOOD_BEAT」, 把常量从 0.3 改成 0.25 **照样绿**
		##   —— 因为判据的两边都来自同一个常量, 那是**恒真式**(memory
		##   `fb-gate-tautological-when-it-spans-a-frame` 同族)。⇒ 判据落在"七个间隔彼此一致"上,
		##   它守得住"节拍乱了"(连斩读不成一刀接一刀), 而不假装守得住一个没人声称过的数。
		##   常量值本身由 ④ 守(必须是 SIM_DT 整数倍)。
		_ok("⑧ 七个间隔彼此一致: %.3f~%.3f 秒, 极差 %.4f(须 ≤ 1 sim 步 %.4f); 现役常量 %.3f"
			% [gap_lo, gap_hi, gap_hi - gap_lo, _s.SIM_DT, BC.BLOOD_BEAT],
			gap_hi - gap_lo <= _s.SIM_DT * 1.2 and gap_lo > 0.0,
			"节拍不齐 = 连斩读不成「一刀接一刀」")

	# ⑨ 画多大 == 打多重(两边都是跑出来的, 非循环)
	if hit_w.size() == want_n and hit_d.size() == want_n and int(hit_d[0]) > 0:
		var worst_err := 0.0
		var worst_k := -1
		for k in range(1, want_n):
			var wr: float = float(hit_w[k]) / maxf(0.001, float(hit_w[0]))
			var dr: float = float(hit_d[k]) / maxf(1.0, float(hit_d[0]))
			var e: float = absf(wr - dr)
			if e > worst_err:
				worst_err = e
				worst_k = k
		_ok("⑨ 画多大就是打多重: 宽度比 vs 伤害比 最大偏差 %.3f(第 %d 刀; 须 ≤ 0.05)" % [worst_err, worst_k],
			worst_err <= 0.05,
			"文案写着「后续每发逐渐衰减」而画面上八刀一样大 = 演出没有遵从效果")
		_ok("★分母: 第 0 刀宽 %.1f 码 / 打 %d, 末刀宽 %.1f 码 / 打 %d(必须真的在缩小)"
			% [hit_w[0], hit_d[0], hit_w[want_n - 1], hit_d[want_n - 1]],
			float(hit_w[want_n - 1]) < float(hit_w[0]) * 0.6 and int(hit_d[want_n - 1]) < int(hit_d[0]))

	# ⑩ 一条钟: 斩痕换帧的间隔恒为 BLOOD_SLASH_STEP
	if frame_t.size() >= 3:
		var flo := 9.0
		var fhi := -9.0
		for i in range(1, frame_t.size()):
			var g2: float = float(frame_t[i]) - float(frame_t[i - 1])
			flo = minf(flo, g2)
			fhi = maxf(fhi, g2)
		print("     [探针] 换帧时刻 %s" % str(frame_t))
		_ok("⑩ 斩痕换帧间隔 %.3f~%.3f 秒 == BLOOD_SLASH_STEP %.4f(±1 sim 步)" % [flo, fhi, BC.BLOOD_SLASH_STEP],
			absf(flo - BC.BLOOD_SLASH_STEP) <= _s.SIM_DT * 1.5 and absf(fhi - BC.BLOOD_SLASH_STEP) <= _s.SIM_DT * 1.5,
			"换帧不走游戏钟 = 又是两条钟(旧版走 create_tween, 实拍看到斩痕在游戏钟上连续 4 拍不动)")

	# ⑪ 收场干净
	_ok("⑪ 连斩结束后场上残留斩痕精灵 %d 个(须 0 —— 有开就有合)" % _live_slashes().size(),
		_live_slashes().is_empty())

	## ⑫ 「携带者的溢出治疗转化为血护盾(上限 200/350/500)」——
	##   携带者满血(1e8/1e8)⇒ 连斩的吸血全是**溢出**治疗 ⇒ 应该全部进血护盾, 且卡在上限。
	##   ★这条是把 A6「现状正常」焊住防回归: 探针实测过它是好的, 但美术侧一动就没人守着它了。
	var sh: float = float(carrier.get("shield", 0.0))
	var cap: float = float(carrier.get("overheal2shield_cap", 0.0))
	print("     [探针] 携带者血护盾 %.1f / 上限 %.0f" % [sh, cap])
	_ok("⑫ 溢出治疗转成血护盾 %.1f(须 > 0 且 ≤ 上限 %.0f)" % [sh, cap],
		sh > 0.0 and sh <= cap + 0.5,
		"0 = 溢出治疗没转盾; 超上限 = 封顶没生效")

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 011 饮血护符坠" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 三个假人累计承伤之和
func func_taken(foes: Array) -> int:
	var t := 0
	for f in foes:
		t += int((f as Dictionary).get("_st_taken", 0))
	return t
