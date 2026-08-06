extends Node
## verify_synergy_vfx.gd — 羁绊演出层【共用基建】门禁 (方案书 docs/plans/20260804-羁绊特效批.md · 批 A · A4 + A5)
##
## 守两件事:
##   ① `scripts/scenes/battle/synergy_vfx.gd` 的原语真的把节点【建进 _world】、参数对、贴地真贴地、撤场干净;
##   ② ★R11: GPUParticles3D 在 `--headless --audio-driver Dummy` 下【真的能建出来且参数对】——
##      在此之前这件事只有"间接证据"(冒烟测试里被调过而门禁没红), 现在有门禁守着了。
##
## ⚠ 铁律 (CLAUDE.md §3.5 / 方案书 §7.1·R1): **一条测特效的用例不该等任何动画 tween 跑完。**
##   `verify_pirate_hook` 连红三次(帧数→游戏时钟→墙钟), 根因是场景树 create_tween() 在无头 CI 下
##   推进不稳、判定埋在 tween 链末尾, 等多久都是 0, 本地永远复现不出来。
##   ⇒ 本文件【全部同步断言】: 调完原语下一行就判。原语本身也是照这条设计的 ——
##      节点与参数在函数返回时就已经是最终值, tween 只负责放大/淡出。
##
## ⚠ 绝不数粒子、不读画面 (方案书 R11): 无头 dummy renderer 下 GPU 模拟大概率不跑,
##   只断言【节点在 + 参数对】。
##
## 覆盖方案书 §7.2 的断言形态:
##   A 节点真的建出来了      → ②
##   B 参数对                → ③
##   C 贴地的真的贴地        → ④  (含反面: 光柱必须【不】贴地, 证明 ④ 不是恒真)
##   D 尺寸不离谱            → ⑤
##   E 同一件事只放一次      → ⑥  (⛔ 原来的"跨阈值才放"已按用户 2026-08-07 拍板拆掉)
##   F 撤场干净              → ⑦
##   G ★分母                → ①(接线) + ⑧(零素材·贴图真是现算的)
##   H 头顶徽章              → ★本文件【不做】, 见文件末尾 _note_h() 的理由(与 verify_head_badges 撞车 + 被未决点 U5 阻塞)
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_vfx.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SV := preload("res://scripts/scenes/battle/synergy_vfx.gd")

# 场上取两个点(都在 ARENA = Rect2(70,110,1596,728) 内)
const P_A := Vector2(700.0, 400.0)
const P_B := Vector2(1000.0, 400.0)

# 现有 live 粒子入口的粒子数 —— ★写【字面值】不引用常量: 引用就是拿代码跟它自己比 = 恒真式
const WANT_IMPACT_AMOUNT := 10        # battle_vfx.gd:_impact_particles
const WANT_BURST_AMOUNT := 90         # RealtimeBattle3DScene.gd:_particle_burst

var _n := 0
var _fail := 0
var _s
var _syn


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 羁绊演出层共用基建 (批 A) ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame

	await _g1_wiring()
	if _syn == null:
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	await _g2_nodes_built()
	await _g3_params()
	await _g4_grounded()
	await _g5_size()
	_g6_tier()
	await _g7_teardown()
	_g8_zero_asset()
	await _g9_world_guard()
	await _g10_gpu_particles()
	_note_h()
	await _done()


# ── ① ★分母 + 接线 ────────────────────────────────────────────────────────────
## ★不是"断言函数存在"(memory [[fb-verify-must-run-the-real-path]] 点名的假门禁),
##   而是断言 BattleVfx 真的把它 new 出来了 —— 批 B/C 的每条羁绊都会经 battle._vfx._syn 走。
func _g1_wiring() -> void:
	print("")
	print("  ① ★分母 + 接线:")
	_ok("① 世界节点 _world 在", is_instance_valid(_s._world))
	_ok("① 相机 _cam 在", is_instance_valid(_s._cam))
	_ok("① 场上有单位 (N=%d)" % _s._units.size(), _s._units.size() > 0)
	var got = _s._vfx._syn
	_ok("① ★BattleVfx 真的把 SynergyVfx 接出来了 (battle._vfx._syn)", got != null and got is SynergyVfx)
	if got != null and got is SynergyVfx:
		_syn = got
		_ok("① 它拿到的是同一个 battle", is_same(_syn.battle, _s))
	await get_tree().process_frame


# ── ② 形态A: 节点真的建进 _world 了 ──────────────────────────────────────────
## ★按【自定义 meta】数, 不按节点名也不按贴图 resource_path 数:
##   程序生成的贴图 resource_path 是空串(verify_ms_tier_vfx.gd:164 记的坑), 按路径数会全数成 0。
func _g2_nodes_built() -> void:
	print("")
	print("  ② 形态A — 节点真的建进 _world:")
	await _reset()
	_ok("② ★分母: 复位后本层节点 0 个", _count() == 0)

	_syn.ground_ring(P_A, Color(1.0, 0.85, 0.35, 0.9), 60.0)
	print("     ground_ring(单层) → 本层节点 %d 个 (需求 1)" % _count("ground_ring"))
	_ok("② 单层贴地环 = 1 个节点", _count("ground_ring") == 1)

	await _reset()
	_syn.ground_ring(P_A, Color(1.0, 0.85, 0.35, 0.9), 60.0, true)
	print("     ground_ring(bold 双层) → %d 个 (需求 2)" % _count("ground_ring"))
	_ok("② bold 贴地环 = 2 个节点(双层)", _count("ground_ring") == 2)

	await _reset()
	_syn.energy_band(P_A, P_B, Color(0.6, 0.9, 1.0, 0.9))
	_ok("② 能量带 = 1 个节点", _count("energy_band") == 1)

	await _reset()
	_syn.light_pillar(P_A, Color(1.0, 0.95, 0.6, 0.9))
	_ok("② 柱状光 = 1 个节点", _count("light_pillar") == 1)

	await _reset()
	_syn.spark_burst(P_A, Color(0.7, 1.0, 0.8, 1.0))
	_ok("② 粒子迸发 = 1 个节点", _count("spark_burst") == 1)

	# 反面: 零长度的带不该建东西(否则 ② 的"1 个"可能是"随便调都建")
	await _reset()
	_syn.energy_band(P_A, P_A, Color(1, 1, 1, 1))
	print("     energy_band(起终点重合) → %d 个 (需求 0)" % _count("energy_band"))
	_ok("② ★反面: 零长度的带不建节点", _count("energy_band") == 0)


# ── ③ 形态B: 参数对 ─────────────────────────────────────────────────────────
func _g3_params() -> void:
	print("")
	print("  ③ 形态B — 参数对(调用返回时就是最终值, 不等 tween):")
	await _reset()
	var r := _syn.ground_ring(P_A, Color(1.0, 0.85, 0.35, 0.9), 60.0) as Sprite3D
	_ok("③ ★分母: 环节点返回了", r != null)
	if r != null:
		print("     环: axis=%d billboard=%d modulate=%s no_depth_test=%s" % [
			r.axis, r.billboard, str(r.modulate), str(r.no_depth_test)])
		_ok("③ 环 axis = AXIS_Y(贴地)", r.axis == Vector3.AXIS_Y)
		_ok("③ 环 billboard 关(开了就不贴地了)", r.billboard == BaseMaterial3D.BILLBOARD_DISABLED)
		_ok("③ 环 modulate 用了传进去的颜色", absf(r.modulate.r - 1.0) < 0.01 and absf(r.modulate.g - 0.85) < 0.01)
		_ok("③ 单层环不关深度测试", not r.no_depth_test)

	await _reset()
	var rb := _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0, true) as Sprite3D
	if rb != null:
		print("     bold 环: no_depth_test=%s render_priority=%d" % [str(rb.no_depth_test), rb.render_priority])
		_ok("③ ★bold 环关深度测试(地板/珊瑚盖不住·同 _splash_ring_bold)", rb.no_depth_test)
		_ok("③ bold 环 render_priority > 0", rb.render_priority > 0)

	await _reset()
	var b := _syn.energy_band(P_A, P_B, Color(0.6, 0.9, 1.0, 0.9)) as Sprite3D
	_ok("③ ★分母: 带节点返回了", b != null)
	if b != null:
		var want_yaw: float = -atan2((P_B.y - P_A.y) * _s.WS, (P_B.x - P_A.x) * _s.WS)
		print("     带: axis=%d rotation.y=%.4f (需求 %.4f) scale.x=%.3f" % [
			b.axis, b.rotation.y, want_yaw, b.scale.x])
		_ok("③ 带 axis = AXIS_Y(贴地)", b.axis == Vector3.AXIS_Y)
		_ok("③ 带绕 Y 转到 A→B 方向", absf(b.rotation.y - want_yaw) < 0.001)
		_ok("③ 带沿 X 拉伸(scale.x > 1)", b.scale.x > 1.0)

	await _reset()
	var p := _syn.light_pillar(P_A, Color(1.0, 0.95, 0.6, 0.9)) as Sprite3D
	if p != null:
		print("     柱: billboard=%d (FIXED_Y=%d)" % [p.billboard, BaseMaterial3D.BILLBOARD_FIXED_Y])
		_ok("③ ★柱用 FIXED_Y 而非全轴 billboard(全轴会让柱子随俯仰倒下去)",
			p.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)


# ── ④ 形态C: 贴地的真的贴地 (方案书 R10) ────────────────────────────────────
## memory [[fb-axis-y-plus-rotation-cancels]]: axis=AXIS_Y 本身就是平铺, 再叠 rotation.x=-90
## 会把它掰成竖环(|世界法线·上| 1.000 → 0.000), 2026-07-30 立了整整一场。
func _g4_grounded() -> void:
	print("")
	print("  ④ 形态C — 贴地的真的贴地 (|世界法线·上| 该 ≈1.000, 竖立是 0.000):")
	await _reset()
	var r := _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0) as Sprite3D
	if r != null:
		var d := _updot(r)
		print("     贴地环 |n·上| = %.3f  (axis=%d rot=%s)" % [d, r.axis, str(r.rotation_degrees)])
		_ok("④ ★★贴地环真的平铺(别再叠 -90 旋转)", d > 0.99)
	var b := _syn.energy_band(P_A, P_B, Color(1, 1, 1, 1)) as Sprite3D
	if b != null:
		var d2 := _updot(b)
		print("     能量带 |n·上| = %.3f" % d2)
		_ok("④ ★★能量带真的平铺", d2 > 0.99)
	# ★反面: 柱状光必须【不】贴地 —— 否则 ④ 可能是"随便什么都 >0.99"的恒真式
	var p := _syn.light_pillar(P_A, Color(1, 1, 1, 1)) as Sprite3D
	if p != null:
		var d3 := _updot(p)
		print("     柱状光 |n·上| = %.3f (需求 <0.01 —— 它是【竖】的)" % d3)
		_ok("④ ★反面: 柱状光【不】贴地(证明 ④ 不是恒真式)", d3 < 0.01)


# ── ⑤ 形态D: 尺寸不离谱 (方案书 R9) ─────────────────────────────────────────
## memory [[fb-verify-must-run-the-real-path]]: 把"效果半径"当"贴片尺寸"→ 公式全对但算出
## 19.2 m 的贴片, 比战场还长。⇒ 量【真实米数】= tex 像素 × pixel_size × scale。
func _g5_size() -> void:
	print("")
	print("  ⑤ 形态D — 尺寸落在合理米数(战场 ARENA %.0f×%.0f px ≈ %.1f×%.1f m):" % [
		_s.ARENA.size.x, _s.ARENA.size.y, _s.ARENA.size.x * _s.WS, _s.ARENA.size.y * _s.WS])
	await _reset()
	var r := _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0) as Sprite3D
	if r != null:
		# ★两边都从【真实节点】上读: 起手用它当前的 pixel_size, 目标用它自己记的 target_ps meta。
		#   不在测试里抄一遍 `60*2*WS` 的公式 —— 那样把产品代码改成写死尺寸, 门禁照样绿
		#   (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
		var tw_px: float = float(r.texture.get_width())
		var dia_now: float = tw_px * r.pixel_size
		var dia: float = tw_px * float(r.get_meta("target_ps", 0.0))
		print("     环: 目标直径 %.2f m / 起手 %.2f m (龟身高 %.2f m·战场宽 %.1f m)" % [
			dia, dia_now, _s.TARGET_BODY_H, _s.ARENA.size.x * _s.WS])
		_ok("⑤ ★分母: 环自己记了 target_ps(没记就没得量)", r.has_meta("target_ps"))
		_ok("⑤ 环目标直径在 [1.0, 6.0] m(量真实节点, 不抄公式)", dia >= 1.0 and dia <= 6.0)
		_ok("⑤ 环起手比目标小(tween 只负责放大 → 门禁不必等它)", dia_now < dia)

	var b := _syn.energy_band(P_A, P_B, Color(1, 1, 1, 1), 26.0) as Sprite3D
	if b != null:
		var seg_m: float = (P_B - P_A).length() * _s.WS
		var len_m: float = float(b.texture.get_width()) * b.pixel_size * b.scale.x
		var wid_m: float = float(b.texture.get_height()) * b.pixel_size
		print("     带: 长 %.2f m (两点真实距离 %.2f m) / 宽 %.2f m" % [len_m, seg_m, wid_m])
		_ok("⑤ ★带长 = 两点真实距离(不是把'效果半径'当贴片尺寸)", absf(len_m - seg_m) < 0.05)
		_ok("⑤ 带宽在 [0.2, 2.0] m", wid_m >= 0.2 and wid_m <= 2.0)

	var p := _syn.light_pillar(P_A, Color(1, 1, 1, 1), 4.2) as Sprite3D
	if p != null:
		var h_m: float = float(p.texture.get_height()) * p.pixel_size
		print("     柱: 高 %.2f m (需求 4.20)" % h_m)
		_ok("⑤ 柱高 = 传进去的 height_m", absf(h_m - 4.2) < 0.01)


# ── ⑥ 形态E: 同一件事只放一次 ───────────────────────────────────────────────
## ⛔ 原本这里还守着一个 `tier_of(value, thresholds)` —— 用户 2026-08-07 拍板【不做阈值特效】,
##    三条阈值提示拆掉后它就零业务调用者了, 已连同那三条一起删(留空壳比留着更糟)。
##    `tier_advance` 【留着】: 弓箭腐蚀满 5 层还在用它当"这一轮放过了没"的闸。
func _g6_tier() -> void:
	print("")
	print("  ⑥ 形态E — 同一件事只放一次(tier_advance):")
	_ok("⑥ ⛔ tier_of 已随三条阈值特效一起删掉(不留空壳)", not _syn.has_method("tier_of"))
	_ok("⑥ ★反面: tier_advance 还在(证明上一条不是「查了个根本不存在的名字」)",
		_syn.has_method("tier_advance"))

	var store := {}
	_ok("⑥ tier 0 不放", not _syn.tier_advance(store, "k", 0))
	_ok("⑥ ★跨进 tier1 → 放一次", _syn.tier_advance(store, "k", 1))
	_ok("⑥ ★同档再喂 → 不重放", not _syn.tier_advance(store, "k", 1))
	_ok("⑥ ★同档再喂第三次 → 仍不重放", not _syn.tier_advance(store, "k", 1))
	_ok("⑥ ★★跨进 tier2 → 又放一次(反面: 证明上一条不是'永远不放')",
		_syn.tier_advance(store, "k", 2))
	_ok("⑥ 档位回落 → 不放(但要记下来)", not _syn.tier_advance(store, "k", 1))
	_ok("⑥ ★回落后再涨回 tier2 → 能重放", _syn.tier_advance(store, "k", 2))


# ── ⑦ 形态F: 撤场干净 (方案书 R7) ───────────────────────────────────────────
## 换路 _dl_clear_units() 只 free 单位、_reg_tween 只 kill tween —— 【不会】动挂在 _world 上的节点。
func _g7_teardown() -> void:
	print("")
	print("  ⑦ 形态F — 撤场干净:")
	await _reset()
	_syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0, true)
	_syn.energy_band(P_A, P_B, Color(1, 1, 1, 1))
	_syn.light_pillar(P_A, Color(1, 1, 1, 1))
	_syn.spark_burst(P_A, Color(1, 1, 1, 1))
	var before: int = _count()
	print("     撤之前 _world 里本层节点 %d 个 (需求 5 = 双层环2 + 带 + 柱 + 粒子)" % before)
	_ok("⑦ ★分母: 撤之前确实有节点", before == 5)
	var freed: int = _syn.clear()
	await get_tree().process_frame
	print("     clear() free 掉 %d 个 → 现在 %d 个 (需求 0)" % [freed, _count()])
	_ok("⑦ clear() 撤干净", _count() == 0)
	_ok("⑦ clear() 报的数对得上", freed == before)
	_ok("⑦ 内部记账也清了", _syn.alive_count() == 0)
	_syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0)
	print("     再建一次 → %d 个 (需求 1)" % _count())
	_ok("⑦ ★★装回来又建出来(证明上一条不是'永久坏了')", _count() == 1)


# ── ⑧ 形态G 的分母变体: 零素材 ──────────────────────────────────────────────
## 用户铁律「不要复用素材除非我指明了」(2026-08-03 定 / 08-04 重申)。
## 本层一张磁盘素材都不用 —— 贴图全是 VfxTex 逐像素现算的。
## ★判据: texture 非空 且 resource_path 是空串(= 不是从磁盘 load 来的资源)。
## ⚠ 方案书原版的形态 G 是 `ResourceLoader.exists(路径)`, 那要等批 D 有素材了才写得出来。
func _g8_zero_asset() -> void:
	print("")
	print("  ⑧ 形态G(分母) — 零素材: 贴图真是程序现算的:")
	for pair in [["ground_ring", _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0)],
			["energy_band", _syn.energy_band(P_A, P_B, Color(1, 1, 1, 1))],
			["light_pillar", _syn.light_pillar(P_A, Color(1, 1, 1, 1))]]:
		var nd = pair[1]
		var nm: String = str(pair[0])
		if nd == null:
			_ok("⑧ %s ★分母: 节点在" % nm, false); continue
		var tex: Texture2D = (nd as Sprite3D).texture
		var rp: String = "" if tex == null else str(tex.resource_path)
		print("     %s: 贴图 %dx%d resource_path=\"%s\"" % [
			nm, 0 if tex == null else tex.get_width(), 0 if tex == null else tex.get_height(), rp])
		_ok("⑧ %s 贴图非空且有像素" % nm, tex != null and tex.get_width() > 0)
		_ok("⑧ ★%s 是程序现算的(resource_path 空 = 没从磁盘复用任何素材)" % nm, rp == "")


# ── ⑨ 守 _world == null (方案书 R2) ─────────────────────────────────────────
## RB 的 _skill_ring / _bolt_line / _beam_vfx / _glow_bb 都【不守】——
## 在"只建单位不建世界"的数值测试里那是 SCRIPT ERROR 而不是 FAIL, 会被 FATAL 正则接住 ⇒ 整批红。
## ★本组【同帧内】改回来, 中间不 await, 免得 _process 拿着 null 跑一帧。
func _g9_world_guard() -> void:
	print("")
	print("  ⑨ R2 — _world 不在时不崩也不建:")
	await _reset()
	var saved = _s._world
	var n0: int = _syn.alive_count()
	_s._world = null
	var a = _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0)
	var b = _syn.energy_band(P_A, P_B, Color(1, 1, 1, 1))
	var c = _syn.light_pillar(P_A, Color(1, 1, 1, 1))
	var d = _syn.spark_burst(P_A, Color(1, 1, 1, 1))
	_s._world = saved
	print("     _world=null 时四个原语的返回值: %s / %s / %s / %s (全需求 <null>)" % [
		str(a), str(b), str(c), str(d)])
	_ok("⑨ 环守空", a == null)
	_ok("⑨ 带守空", b == null)
	_ok("⑨ 柱守空", c == null)
	_ok("⑨ 粒子守空", d == null)
	_ok("⑨ 一个节点都没记账(没偷偷建)", _syn.alive_count() == n0)
	# 反面: 世界装回来 → 立刻又能建 (证明上面不是"永久关掉了")
	var e = _syn.ground_ring(P_A, Color(1, 1, 1, 1), 60.0)
	_ok("⑨ ★反面: _world 装回来立刻又能建", e != null)


# ── ⑩ A5 / R11: GPU 粒子在无头下真的能建出来 ────────────────────────────────
## 方案书 R11 原文: 现有只有【间接证据】(冒烟测试里被调过而门禁一直绿)。这一组把它变成有门禁守着。
## ★走 live 入口: `_vfx._impact(tgt, dmg, "big")` —— 它是普攻/技能命中的真实分派口,
##   dmg ≥ JUICE_PARTICLE_MIN_DMG 时才转发到 _impact_particles(battle_vfx.gd:475-477)。
## ★只断言节点与参数, 绝不数粒子(无头 dummy renderer 下 GPU 模拟大概率不跑)。
func _g10_gpu_particles() -> void:
	print("")
	print("  ⑩ A5/R11 — GPUParticles3D 在 --headless 下真的建得出来:")
	await _reset()
	var tgt = null
	for u in _s._units:
		if u.get("alive", false):
			tgt = u; break
	_ok("⑩ ★分母: 找到一个活着的单位当靶子", tgt != null)
	if tgt == null:
		return

	var base10: int = _gpu_count(WANT_IMPACT_AMOUNT)
	_s._vfx._impact(tgt, 999, "big")            # ← live 入口(不是直接点 _impact_particles)
	var now10: int = _gpu_count(WANT_IMPACT_AMOUNT)
	print("     _vfx._impact(dmg=999,'big') → amount=%d 的粒子节点 %d → %d" % [
		WANT_IMPACT_AMOUNT, base10, now10])
	_ok("⑩ ★重击真的经 _impact 迸出一组 GPU 粒子", now10 == base10 + 1)
	var ps10 := _gpu_pick(WANT_IMPACT_AMOUNT)
	if ps10 != null:
		print("     参数: amount=%d lifetime=%.2f one_shot=%s emitting=%s pm=%s draw_pass_1=%s" % [
			ps10.amount, ps10.lifetime, str(ps10.one_shot), str(ps10.emitting),
			ps10.process_material.get_class() if ps10.process_material != null else "<null>",
			"有" if ps10.draw_pass_1 != null else "<null>"])
		_ok("⑩ one_shot", ps10.one_shot)
		_ok("⑩ emitting 已打开", ps10.emitting)
		_ok("⑩ process_material 是 ParticleProcessMaterial", ps10.process_material is ParticleProcessMaterial)
		_ok("⑩ draw_pass_1 在(没网格 = 什么都看不见)", ps10.draw_pass_1 != null)
		_ok("⑩ lifetime > 0", ps10.lifetime > 0.0)

	# ★反面: 轻击(dmg 低于门槛)不该迸粒子 —— 否则 ⑩ 可能是"随便调都增加"
	var b2: int = _gpu_count(WANT_IMPACT_AMOUNT)
	_s._vfx._impact(tgt, 1, "light")
	print("     _vfx._impact(dmg=1,'light') → %d → %d (需求不变)" % [b2, _gpu_count(WANT_IMPACT_AMOUNT)])
	_ok("⑩ ★反面: 轻击不迸粒子(证明上面不是'随便调都增加')", _gpu_count(WANT_IMPACT_AMOUNT) == b2)

	# 主场景的 _particle_burst(90 颗) —— 活代码, 3 处调用方(RB:3464 / equip_tick:460 / hookbomb:262)
	var b90: int = _gpu_count(WANT_BURST_AMOUNT)
	_s._particle_burst(P_A)
	print("     _particle_burst → amount=%d 的粒子节点 %d → %d" % [
		WANT_BURST_AMOUNT, b90, _gpu_count(WANT_BURST_AMOUNT)])
	_ok("⑩ _particle_burst 也建得出来", _gpu_count(WANT_BURST_AMOUNT) == b90 + 1)
	var ps90 := _gpu_pick(WANT_BURST_AMOUNT)
	if ps90 != null:
		_ok("⑩ 90 颗那组: one_shot + emitting + 有 draw_pass",
			ps90.one_shot and ps90.emitting and ps90.draw_pass_1 != null)
		_ok("⑩ 90 颗那组: color_ramp 在(白热→橙→红→透)",
			(ps90.process_material as ParticleProcessMaterial).color_ramp != null)

	# 本层自己的 spark_burst
	_syn.spark_burst(P_A, Color(0.7, 1.0, 0.8, 1.0), 0.6, 18)
	var ps18 := _gpu_pick(18)
	_ok("⑩ ★分母: 本层 spark_burst 的节点在", ps18 != null)
	if ps18 != null:
		_ok("⑩ 本层粒子: one_shot + emitting + ParticleProcessMaterial + draw_pass",
			ps18.one_shot and ps18.emitting
			and ps18.process_material is ParticleProcessMaterial and ps18.draw_pass_1 != null)


## 形态 H (头顶徽章) 为什么不在本文件里 —— 写下来免得下次有人当漏项。
func _note_h() -> void:
	print("")
	print("  ⑪ 形态H(头顶徽章) — ★本文件【不做】, 两条理由:")
	print("     · 方案书 A3「徽章行扩容/优先级」被未决点 U5 阻塞(HEAD_ROW_CAP=4 已满, 超出会【静默截断】);")
	print("     · 徽章几何已另有门禁 tests/verify_head_badges.gd 在写 —— 再写一份就是重复造轮子。")
	print("     ⇒ 腐蚀/僵硬/猎物的徽章断言等 U5 拍板后, 补在那个文件里。")


# ── 工具 ──────────────────────────────────────────────────────────────────────

## _world 里本层建的节点数 (按自定义 meta 数, 不按名字/贴图路径)。
func _count(kind: String = "") -> int:
	var n := 0
	for c in _s._world.get_children():
		if not c.has_meta(SV.META_KEY):
			continue
		if kind != "" and str(c.get_meta(SV.META_KEY)) != kind:
			continue
		n += 1
	return n


## _world 里 amount 恰好等于 amt 的 GPUParticles3D 个数 (用 amount 区分三个来源)。
func _gpu_count(amt: int) -> int:
	var n := 0
	for c in _s._world.get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).amount == amt:
			n += 1
	return n


func _gpu_pick(amt: int) -> GPUParticles3D:
	for c in _s._world.get_children():
		if c is GPUParticles3D and (c as GPUParticles3D).amount == amt:
			return c
	return null


## |世界法线 · 上|。Sprite3D 的局部法线由 axis 决定 (照 verify_ms_tier_vfx.gd:94-99)。
func _updot(spr: Sprite3D) -> float:
	var local_n := Vector3.BACK
	match spr.axis:
		Vector3.AXIS_X: local_n = Vector3.RIGHT
		Vector3.AXIS_Y: local_n = Vector3.UP
	return absf((spr.global_transform.basis * local_n).normalized().dot(Vector3.UP))


## 清掉本层节点并等一帧(queue_free 到帧末才真的离开父节点)。
func _reset() -> void:
	_syn.clear()
	await get_tree().process_frame


func _ok(what: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("     [PASS] ", what)
	else:
		_fail += 1
		print("     [FAIL] ", what, ("  " + detail) if detail != "" else "")


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	print("ALL PASS — 羁绊演出层共用基建(批 A)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
