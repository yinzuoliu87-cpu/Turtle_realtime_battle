extends Node
## verify_sword_storm_chain.gd — 006 千刃风暴的【因果链】门禁 (2026-09-07)
##
## ══════════════════════════════════════════════════════════════════
##  ★这个文件要守住的是用户的哪句话
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-07:「我不知道，但**你不能凭空没有逻辑出现**」
##
## 这句话是在我把"蓄力软球"换成"一颗八向星"之后说的 —— 换个更漂亮的通用闪光
## 并**没有**解决问题: 星和球一样, 既不说明技能要干什么, 自己也照样是凭空出现的。
## 真正要的是一条【因果链】:
##       地面裂开 7 道口子 → 剑从口子里升起来 → 剑阵往前推
## 每一步都有因, 而且**口子的位置与数量就是剑阵的位置与数量**(预兆自带信息量)。
##
## 「有因果」不能靠我说了算, 所以判据落在可量的东西上:
##   ① 预兆**先于**正主出现, 且数量 = 剑数(不是随便闪一下)
##   ② 每把剑的出生点与某道地缝**重合**(这就是"从这道缝里长出来"这句话本身)
##   ③ 剑是**长出来**的: 出生只露剑尖, 且任何时刻【下沿钉在地面】
##   ④ 预兆不许比正主大(0.075 那版缝长 3.1 米 vs 剑 1.7 米, 实拍读成七个大灰盘子)
##   ⑤ 有开就有合: 地缝最后一定被收掉
##   ⑥ 两张素材是真像素画(硬边 + 锁定调色板), 不是又换回程序生成的软球
##
## ★★为什么不断言 tween: 无头 CI 推不动场景树 tween(CLAUDE.md §3.5 海盗钩索)。
##   所以 `sword_reveal` / `_close_slits` 都已经从 tween 里**抽成了具名函数** ——
##   演出调它们, 这里也直接调它们; 节点的创建则走 `_wait_sim` 主链, 与 tween 无关。
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


func _tex_path_of(node: Node) -> String:
	if not (node is Sprite3D):
		return ""
	var t: Texture2D = (node as Sprite3D).texture
	return t.resource_path if t != null else ""


func _collect(path: String) -> Array:
	var out: Array = []
	if _s == null or not is_instance_valid(_s) or not is_instance_valid(_s._world):
		return out
	for c in _s._world.get_children():
		if _tex_path_of(c) == path:
			out.append(c)
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true          # ★绝不写玩家存档
	print("=== 006 千刃风暴: 地裂 → 剑升 → 剑阵前推 ===")

	# ══════════════════════════════════════════════════════════════
	#  ④ 纯几何(不建场): 预兆不许比正主大
	# ══════════════════════════════════════════════════════════════
	print("-- 4 预兆不比正主大(纯几何) --")
	var slit_tex: Texture2D = load(EQ.SLIT_TEX_PATH)
	var sword_tex: Texture2D = load(EQ.SWORD_TEX_PATH)
	_ok("★分母: 两张素材都在盘上", slit_tex != null and sword_tex != null,
		"%s / %s" % [EQ.SLIT_TEX_PATH, EQ.SWORD_TEX_PATH])
	if slit_tex == null or sword_tex == null:
		_done()
		return
	var slit_frames: int = EQ.GROUND_SLIT_FRAMES
	var slit_cell_w: float = float(slit_tex.get_width()) / float(slit_frames)
	var slit_len_m: float = slit_cell_w * EQ.SLIT_PIXEL_SIZE
	var sword_h_m: float = float(sword_tex.get_height()) * EQ.SWORD_PIXEL_SIZE
	_ok("缝长 %.2f 米 <= 剑高 %.2f 米 x 1.2" % [slit_len_m, sword_h_m],
		slit_len_m <= sword_h_m * 1.2,
		"预兆比正主还大 ⇒ 实拍会变成一排大盘子把剑盖住")
	## 反过来也要卡: 缝小到看不见同样不行(它是唯一说明"剑要从哪出来"的东西)
	_ok("缝长 %.2f 米 >= 剑高 %.2f 米 x 0.5" % [slit_len_m, sword_h_m],
		slit_len_m >= sword_h_m * 0.5, "缝太小 ⇒ 预兆读不出来")

	# ══════════════════════════════════════════════════════════════
	#  ⑥ 素材是真像素画 (硬边 + 锁定调色板), 不是程序生成的软球
	# ══════════════════════════════════════════════════════════════
	print("-- 6 素材规格: 硬边 + 锁定调色板 --")
	for pair in [["地缝", slit_tex, slit_frames], ["剑", sword_tex, 1]]:
		var nm: String = str(pair[0])
		var tex: Texture2D = pair[1]
		var img: Image = tex.get_image()
		if img == null:
			_ok("%s: 读得到像素" % nm, false, "get_image() 为 null")
			continue
		if img.is_compressed():
			img.decompress()
		var cols := {}
		var semi := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var col: Color = img.get_pixel(x, y)
				var a: int = int(round(col.a * 255.0))
				if a > 16:
					cols[Vector3i(int(col.r8), int(col.g8), int(col.b8))] = true
					if a < 245:
						semi += 1
		_ok("%s: 零半透边缘(硬边像素画) —— 实测 %d 个" % [nm, semi], semi == 0,
			"有半透 = 抗锯齿 = 又回到软球/绘图")
		_ok("%s: 色数 %d <= 8(锁定调色板 6 色)" % [nm, cols.size()], cols.size() <= 8,
			"色数爆了 = 不是从 tools/pixelize_sheet.py 的锁定板出来的")
		var nfr: int = maxi(1, int(pair[2]))
		_ok("%s: 单元格 <= 64 像素" % nm,
			int(float(img.get_width()) / float(nfr)) <= 64 and img.get_height() <= 64,
			"%dx%d / %d 帧" % [img.get_width(), img.get_height(), nfr])
	## 用户 2026-08-29:「不要拿图片贴图敷衍我, 我要动画像素特效」⇒ 地缝必须是逐帧裂开
	_ok("地缝是 %d 帧逐帧动画(单帧 = 敷衍)" % slit_frames, slit_frames >= 4)

	# ══════════════════════════════════════════════════════════════
	#  建场 (③ 与 ①②⑤ 都要用真的 _equip_sys)
	# ══════════════════════════════════════════════════════════════
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	# ══════════════════════════════════════════════════════════════
	#  ③ 剑"从地里长出来": 下沿钉地的不变量 (直接调具名函数, 不等 tween)
	# ══════════════════════════════════════════════════════════════
	print("-- 3 长出来 = 下沿钉地(直接调 sword_reveal) --")
	var probe := Sprite3D.new()
	probe.texture = sword_tex
	probe.region_enabled = true
	add_child(probe)
	var last_tip := -1.0
	var rows_checked := 0
	for rows in [3.0, 8.0, 20.0, 34.0, 48.0]:
		_s._equip_sys.sword_reveal(probe, rows)
		rows_checked += 1
		var hi: float = probe.region_rect.size.y
		_ok("rows=%.0f → 只画最上 %.0f 行" % [rows, hi], absf(hi - rows) < 0.51,
			"实得 %.1f" % hi)
		## ★这条就是"下沿钉在地面"这句话本身。
		##   改回"整把剑从 y=-0.25 平移上来" ⇒ offset 恒为 0 ⇒ 当场红。
		_ok("rows=%.0f → 下沿钉地(offset.y x2 == 区域高)" % rows,
			absf(probe.offset.y * 2.0 - hi) < 0.01,
			"offset.y=%.2f 区域高=%.1f" % [probe.offset.y, hi])
		## 剑尖离地高度 = (露出的行数 - 剑尖所在行) x pixel_size, 必须**严格**变高
		var tip: float = (hi - float(EQ.SWORD_TIP_ROW)) * EQ.SWORD_PIXEL_SIZE
		_ok("rows=%.0f → 剑尖离地 %.2f 米(比上一档高)" % [rows, tip], tip > last_tip + 0.02,
			"上一档 %.2f" % last_tip)
		last_tip = tip
	_ok("★分母: 逐档验了 %d 个露出高度" % rows_checked, rows_checked == 5, "为 0 = 空检查")
	probe.queue_free()

	# ══════════════════════════════════════════════════════════════
	#  ①②⑤ 跑真入口: 顺序 / 重合 / 收尾
	# ══════════════════════════════════════════════════════════════
	print("-- 1/2/5 真入口 _eq_sword_storm: 顺序/重合/收尾 --")
	var c2: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var owner_u: Dictionary = _s._spawn._make_unit("basic", "left", c2 + Vector2(-300, 0))
	_s._units.append(owner_u)
	for k in range(3):
		var foe: Dictionary = _s._spawn._make_unit("basic", "right", c2 + Vector2(120 + 90 * k, 0))
		foe["maxHp"] = 1.0e8
		foe["hp"] = 1.0e8
		_s._units.append(foe)

	_s._equip_sys._eq_sword_storm(owner_u, 1)   # ★真入口, 不 await(它自己是协程)

	var first_slit := -1
	var first_sword := -1
	var max_slit := 0
	var max_sword := 0
	var sword_pos: Array = []
	var slit_pos: Array = []
	var born_rows: Array = []
	var slit_gone := -1
	## ★墙钟兜底 + 帧上限: 不拿游戏时钟当尺子(结算结束后 `_t` 会冻结, CLAUDE.md §3.5)
	var t0: int = Time.get_ticks_msec()
	var f := 0
	while f < 6000 and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
		f += 1
		var sl: Array = _collect(EQ.SLIT_TEX_PATH)
		var sw: Array = _collect(EQ.SWORD_TEX_PATH)
		if sl.size() > 0 and first_slit < 0:
			first_slit = f
		if sw.size() > 0 and first_sword < 0:
			first_sword = f
			for x in sw:
				sword_pos.append((x as Node3D).global_position)
				born_rows.append((x as Sprite3D).region_rect.size.y)
			for q in sl:
				slit_pos.append((q as Node3D).global_position)
		max_slit = maxi(max_slit, sl.size())
		max_sword = maxi(max_sword, sw.size())
		if first_sword > 0 and sl.size() == 0 and slit_gone < 0:
			slit_gone = f
		## ★到"缝已收掉"就够了 —— 再往后等剑淡出是 tween 的事, 无头推不动,
		##   等它只会白烧几千帧然后被 --quit-after 掐断(表现成"没打 ALL PASS")。
		if slit_gone > 0 and first_sword > 0:
			break

	_ok("★分母: 地缝真的建出来了(最多同时 %d 道)" % max_slit, max_slit == EQ.SWORD_RANK_N,
		"应为 %d 道 —— 0 = 整条链根本没跑" % EQ.SWORD_RANK_N)
	_ok("★分母: 剑真的建出来了(最多同时 %d 把)" % max_sword, max_sword == EQ.SWORD_RANK_N,
		"应为 %d 把" % EQ.SWORD_RANK_N)
	## ① 因果顺序: 先有口子才有剑。这是"不能凭空出现"最直接的一条。
	_ok("1 地缝(第 %d 帧)早于剑(第 %d 帧)出现" % [first_slit, first_sword],
		first_slit > 0 and first_sword > 0 and first_slit < first_sword,
		"预兆没有先于正主 = 剑还是凭空冒出来的")
	## ② 每把剑都能配到一道地缝(平面距离), 且一一对应
	var matched := 0
	var worst := 0.0
	for sp in sword_pos:
		var best := 1.0e9
		for q2 in slit_pos:
			var d: float = Vector2(sp.x - q2.x, sp.z - q2.z).length()
			best = minf(best, d)
		worst = maxf(worst, best)
		if best < 0.06:
			matched += 1
	_ok("2 七把剑全部长在地缝上(最远的一把偏 %.3f 米 < 0.06)" % worst,
		matched == EQ.SWORD_RANK_N and sword_pos.size() == EQ.SWORD_RANK_N,
		"配上 %d/%d 把 —— 位置对不上 = 预兆指的地方和剑出来的地方不是一回事"
		% [matched, sword_pos.size()])
	## ③(真入口版) 剑一出生只露剑尖
	var born_max := 0.0
	for r in born_rows:
		born_max = maxf(born_max, float(r))
	_ok("3 剑出生时只露 %.0f 行(<= 剑尖行 %d + 1)" % [born_max, EQ.SWORD_TIP_ROW],
		born_rows.size() > 0 and born_max <= float(EQ.SWORD_TIP_ROW + 1) + 0.51,
		"一出生就是整把 = 没有长出来这个过程")
	## ⑤ 有开就有合
	_ok("5 地缝在第 %d 帧被收掉(有开就有合)" % slit_gone, slit_gone > 0,
		"缝一直裂着 = 场上留垃圾")

	_done()


func _done() -> void:
	if _s != null and is_instance_valid(_s):
		_s._units.clear()
		_s.set_process(false)
		await get_tree().process_frame
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 006 因果链: 地裂 → 剑升 → 剑阵前推" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
