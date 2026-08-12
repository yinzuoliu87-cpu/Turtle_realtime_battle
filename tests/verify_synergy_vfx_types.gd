extends Node
## verify_synergy_vfx_types.gd — 十类羁绊【各自的视觉母题】门禁 (批 B3 · 2026-08-06)
##
## 姊妹件 `verify_synergy_vfx.gd` 守的是**共用基建**(5 个原语本身)。
## 本文件守的是 **B3 新加的那一层**: 两个新原语 + 十条羁绊演出入口 + **它们真的被羁绊系统调到**。
##
## ── 守六件事 ────────────────────────────────────────────────────────────────
##  ① ★分母 + 接线            —— 新入口挂在 battle._vfx._syn 上, 且羁绊系统能拿到它
##  ② 新原语 polygon_ring     —— 节点/边数/贴地/尺寸/bold/零素材, 含反面
##  ③ 新原语 radial_spokes    —— N 个目标 = N 条带, 含反面(重合点不建)
##  ④ ★★★走【羁绊系统的真入口】—— 不是"断言函数存在"(memory [[fb-verify-must-run-the-real-path]]:
##     「断言函数存在守不住还有没有人调」)。每条都调 *_synergy_system 里的真函数, 数本层节点。
##  ⑤ ★母题可分辨          —— 三个多边形边数互不相同 + 十类的主色两两色距够大
##     (装备那边的教训: 四件召唤物共用一个白光球, 玩家分不出谁是谁)
##  ⑥ ★演出不参与结算      —— 调完每个演出入口, 单位的 hp/shield/base_atk/damage_amp 一个字节都没变
##  ⑦ 撤场干净 + 守 _world==null
##
## ⛔ 2026-08-07: 三条【阈值提示】(遗物·远古之力 34/67/100% · 食物·成长 100/300/600 ·
##    奇械·僵硬 5/10/20 层) 已按用户拍板【整条拆掉】。④ 里对应位置换成了**反向守卫**
##    (跑真入口 → 断"一个演出节点都不建"), 外加一组"演出函数/常量都没留空壳"。
##    别把它们加回来。
##
## ⚠ 铁律 (CLAUDE.md §3.5 / 方案书 R1): **全部同步断言, 不等任何 tween。**
##    原语的参数在函数返回时就是最终值, tween 只负责放大/淡出。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_vfx_types.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SV := preload("res://scripts/scenes/battle/synergy_vfx.gd")

const P_A := Vector2(700.0, 400.0)
const P_B := Vector2(1000.0, 400.0)
const P_C := Vector2(700.0, 620.0)

var _n := 0
var _fail := 0
var _s
var _syn
var _type_map: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 十类羁绊的视觉母题 (批 B3) ===")

	_load_type_map()
	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame
	# ★★把战斗的 _process 关掉 —— 否则每次 `await process_frame` 都会让
	#   `_gun_syn.tick / _bow_syn.tick / _relic_syn.tick …` 自己也跑一次,
	#   它们【现在会建本层节点】⇒ 计数里混进不属于这一条的东西, CI 上就是偶发红。
	#   本文件全部是同步断言、一个 tween 都不等 ⇒ 关掉 _process 不影响任何一条。
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	_g1_wiring()
	if _syn == null:
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	await _g2_polygon_ring()
	await _g3_radial_spokes()
	await _g4_real_paths()
	_g5_motifs()
	await _g6_no_side_effects()
	await _g7_teardown_and_guard()
	await _done()


## 装备 id → 类型 的真实映射(不写死 id —— 写死就是抄一份会漂的副本)。
func _load_type_map() -> void:
	var f := FileAccess.open("res://data/p2eq-types.json", FileAccess.READ)
	if f == null:
		return
	var p = JSON.parse_string(f.get_as_text())
	if p is Dictionary:
		_type_map = p


func _an_equip_of(t: String) -> String:
	var ids: Array = _type_map.keys()
	ids.sort()          # 确定性: 同一份数据永远取到同一件
	for k in ids:
		if str(_type_map[k]) == t:
			return str(k)
	return ""


# ── ① ★分母 + 接线 ──────────────────────────────────────────────────────────
func _g1_wiring() -> void:
	print("")
	print("  ① ★分母 + 接线:")
	_ok("① 世界节点 _world 在", is_instance_valid(_s._world))
	_ok("① 场上有单位 (N=%d)" % _s._units.size(), _s._units.size() > 0)
	_ok("① 装备类型映射读到了 (N=%d)" % _type_map.size(), _type_map.size() > 0)
	var got = _s._vfx._syn
	_ok("① battle._vfx._syn 在", got != null and got is SynergyVfx)
	if got != null and got is SynergyVfx:
		_syn = got
	# ★十个羁绊系统各自都要能拿到同一个 battle(它们就是靠 battle._vfx._syn 走演出的)
	for pair in [["gun", _s._gun_syn], ["staff", _s._staff_syn], ["relic", _s._relic_syn],
			["food", _s._food_syn], ["potion", _s._potion_syn], ["shield", _s._shield_syn],
			["bow", _s._bow_syn], ["gadget", _s._gadget_syn]]:
		_ok("① %s_synergy_system 拿到的是同一个 battle" % str(pair[0]),
			pair[1] != null and is_same(pair[1].battle, _s))


# ── ② 新原语: polygon_ring ───────────────────────────────────────────────────
func _g2_polygon_ring() -> void:
	print("")
	print("  ② 新原语 polygon_ring — 十类里有四类都要「脚下一圈」, 靠边数分开:")
	await _reset()
	_ok("② ★分母: 复位后本层节点 0 个", _count() == 0)

	for sides in [3, 6, 8]:
		await _reset()
		var r := _syn.polygon_ring(P_A, Color(1, 1, 1, 1), 50.0, sides) as Sprite3D
		_ok("② %d 边环建出 1 个节点" % sides, _count("polygon_ring") == 1 and r != null)
		if r == null:
			continue
		print("     %d 边: axis=%d billboard=%d sides_meta=%d |n·上|=%.3f" % [
			sides, r.axis, r.billboard, int(r.get_meta("sides", -1)), _updot(r)])
		_ok("② %d 边环 axis = AXIS_Y(贴地)" % sides, r.axis == Vector3.AXIS_Y)
		_ok("② %d 边环 billboard 关" % sides, r.billboard == BaseMaterial3D.BILLBOARD_DISABLED)
		_ok("② ★%d 边环真的平铺(R10: 别再叠 -90 旋转)" % sides, _updot(r) > 0.99)
		_ok("② %d 边环自己记了 sides meta" % sides, int(r.get_meta("sides", -1)) == sides)
		# 零素材: 贴图是逐像素现算的
		var tex: Texture2D = r.texture
		_ok("② %d 边环贴图非空且有像素" % sides, tex != null and tex.get_width() > 0)
		_ok("② ★%d 边环是程序现算的(resource_path 空 = 没复用任何素材)" % sides,
			tex != null and str(tex.resource_path) == "")
		# 尺寸: 量真实节点(tex 像素 × 节点自己记的 target_ps), 不在测试里抄公式
		var dia: float = float(tex.get_width()) * float(r.get_meta("target_ps", 0.0))
		var dia_now: float = float(tex.get_width()) * r.pixel_size
		print("     %d 边: 目标直径 %.2f m / 起手 %.2f m (龟身高 %.2f m)" % [
			sides, dia, dia_now, _s.TARGET_BODY_H])
		_ok("② %d 边环目标直径在 [1.0, 6.0] m" % sides, dia >= 1.0 and dia <= 6.0)
		_ok("② %d 边环起手比目标小(tween 只放大 ⇒ 门禁不必等它)" % sides, dia_now < dia)

	# ★不同边数的贴图【真的不是同一张】—— 否则"母题可分辨"是空话
	var t3 := SV._make_poly_ring_tex(3)
	var t6 := SV._make_poly_ring_tex(6)
	var t8 := SV._make_poly_ring_tex(8)
	_ok("② ★3/6/8 边是三张【不同】的贴图(不是同一张换色)",
		not is_same(t3, t6) and not is_same(t6, t8) and not is_same(t3, t8))
	_ok("② ★同一边数复用缓存(不是每次重画)", is_same(t3, SV._make_poly_ring_tex(3)))
	# 反面: 逐像素比一下 3 边与 6 边的中线, 不同边数在同一角度上的边界半径必然不同
	var d36: int = _tex_diff(t3, t6)
	print("     3 边 vs 6 边: 不同像素 %d 个 (需求 > 200)" % d36)
	_ok("② ★★3 边与 6 边的像素真的不一样(证明边数参数真的进了绘制)", d36 > 200)

	await _reset()
	var rb := _syn.polygon_ring(P_A, Color(1, 1, 1, 1), 50.0, 6, true) as Sprite3D
	if rb != null:
		_ok("② ★bold 关深度测试(地板/珊瑚盖不住·同 _splash_ring_bold)", rb.no_depth_test)
		_ok("② bold render_priority > 0", rb.render_priority > 0)
	# 边数越界要被钳住, 而不是画出一张空贴图
	await _reset()
	var r2 := _syn.polygon_ring(P_A, Color(1, 1, 1, 1), 50.0, 1) as Sprite3D
	_ok("② 边数 1 被钳到 3(不产出空贴图)", r2 != null and int(r2.get_meta("sides", -1)) == 3)


# ── ③ 新原语: radial_spokes ──────────────────────────────────────────────────
func _g3_radial_spokes() -> void:
	print("")
	print("  ③ 新原语 radial_spokes — 「一点向多点」这个构图本身就是信息:")
	await _reset()
	var n: int = _syn.radial_spokes(P_A, [P_B, P_C], Color(1, 1, 1, 1))
	print("     2 个目标 → 报 %d 条 / 场上 %d 条带" % [n, _count("energy_band")])
	_ok("③ 2 个目标 = 2 条带", n == 2 and _count("energy_band") == 2)

	await _reset()
	var n0: int = _syn.radial_spokes(P_A, [], Color(1, 1, 1, 1))
	_ok("③ ★反面: 0 个目标 = 0 条(不是「随便调都建」)", n0 == 0 and _count("energy_band") == 0)

	await _reset()
	var n1: int = _syn.radial_spokes(P_A, [P_A, P_B], Color(1, 1, 1, 1))
	print("     其中一个目标与起点重合 → 报 %d 条 (需求 1)" % n1)
	_ok("③ ★零长度那条被 energy_band 自己挡掉", n1 == 1)

	await _reset()
	var n2: int = _syn.radial_spokes(P_A, [P_B, "不是Vector2", null], Color(1, 1, 1, 1))
	_ok("③ 非 Vector2 的项被跳过(不崩)", n2 == 1)


# ── ④ ★★★走【羁绊系统的真入口】 ────────────────────────────────────────────
## memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调」。
## 本组每一条都调 `*_synergy_system.gd` 里的真函数, 然后数本层节点 —— 没接线就红。
func _g4_real_paths() -> void:
	print("")
	print("  ④ ★★★走羁绊系统真入口(不是直接点演出层):")
	var left = _side_unit("left")
	var right = _side_unit("right")
	_ok("④ ★分母: 找到左右各一只活单位", left != null and right != null)
	if left == null or right == null:
		return

	# ── 枪·第一座炮台 ──────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"枪": 3})
	_s._gun_syn._turret_one("left")
	print("     _gun_syn._turret_one('left') → 柱 %d / 火花 %d" % [
		_count("light_pillar"), _count("spark_burst")])
	_ok("④ 枪·第一座: 炮位真的立了一根柱", _count("light_pillar") >= 1)

	# ── 枪·第二座(两个相位各跑一次, 必须分得开) ──────────────────
	await _reset()
	_s._gun_syn._t2_shield_phase["left"] = true
	## ★★2026-08-12 炮台二重做(用户:「不应该有炮管, 而是放射性炮台 …… 放盾白色冲击波,
	##   打伤害红色冲击波, 炮台本身的颜色也变红变白 …… 有个蓄力, 然后释放」):
	##   相位不再靠"环 vs 火花"表达, 而是【白波 / 红波 + 炮台本体换色】。判据随之改写。
	var sv2 = _s._vfx._syn
	sv2.gun_turret_ensure("left|1", _s._gun_syn._turret_pos("left", 1), 1)
	## ① 护盾相位: 蓄力 → 炮台变【白】
	sv2.gun_wave_charge("left|1", true)
	var col_shield: Color = (sv2._turrets["left|1"]["mat_r"] as StandardMaterial3D).albedo_color
	## ② 弹幕相位: 蓄力 → 炮台变【红】
	sv2.gun_wave_charge("left|1", false)
	var col_dmg: Color = (sv2._turrets["left|1"]["mat_r"] as StandardMaterial3D).albedo_color
	print("     炮台本体色: 护盾相位 rgb(%.2f,%.2f,%.2f) ｜ 弹幕相位 rgb(%.2f,%.2f,%.2f)" % [
		col_shield.r, col_shield.g, col_shield.b, col_dmg.r, col_dmg.g, col_dmg.b])
	_ok("④ 枪·第二座 ★炮台本体【护盾相位=白】(g/b 都高)",
		col_shield.g > 0.85 and col_shield.b > 0.85)
	_ok("④ 枪·第二座 ★炮台本体【弹幕相位=红】(r 高而 g/b 低)",
		col_dmg.r > 0.85 and col_dmg.g < 0.5 and col_dmg.b < 0.5)
	_ok("④ ★★两个相位【颜色真的不一样】—— 相位可辨是这条效果的核心信息",
		absf(col_shield.g - col_dmg.g) > 0.4)
	## ③ 释放: 星浪节点真的建出来, 且两个相位的波色不同
	var w_s: Dictionary = sv2.gun_wave_release("left|1", true)
	var w_d: Dictionary = sv2.gun_wave_release("left|1", false)
	_ok("④ 枪·第二座 ★释放真的建出星浪(白/红各一道)",
		is_instance_valid(w_s.get("node", null)) and is_instance_valid(w_d.get("node", null)))
	_ok("④ 枪·第二座 ★白波 vs 红波的波色不同",
		absf((w_s.get("col", Color.WHITE) as Color).g - (w_d.get("col", Color.WHITE) as Color).g) > 0.4)
	## ④ 波【会扩散】: 推进后半径真的变大(它是"扫到才生效"的那把尺子)
	var r0: float = SynergyVfx.wave_radius(0.05)
	var r1: float = SynergyVfx.wave_radius(0.40)
	_ok("④ 枪·第二座 ★波在扩散: r(0.05)=%.0f 码 → r(0.40)=%.0f 码(速度 %.0f 码/秒)"
			% [r0, r1, SynergyVfx.WAVE_SPEED],
		r1 > r0 and absf(r1 - r0 - SynergyVfx.WAVE_SPEED * 0.35) < 1.0)

	# ── 剑·血祭(2026-08-12 补: 十条里唯一零演出的一条) ─────────────────
	## 机制是【常驻·连续】的(每损失 1% 生命 → +N% 攻击力) ⇒ 判据也必须是连续的:
	## 血丝条数随"已损失生命"涨, **满血时必须是 0**(没有加成就不该有表现 —— 这条是分母)。
	await _reset()
	## ★本测试只验演出层, 不建真单位 —— 血气接口要的就是 pos/alive/hp 三个字段
	var bu: Dictionary = {"pos": Vector2(400.0, 400.0), "alive": true,
		"maxHp": 1000.0, "hp": 1000.0, "side": "left"}
	var n_full: int = _s._vfx._syn.blood_rite_update(bu, 0.0, 0.0)
	var n_half: int = _s._vfx._syn.blood_rite_update(bu, 0.5, 0.0)
	var n_low: int = _s._vfx._syn.blood_rite_update(bu, 0.9, 0.0)
	print("     血祭血丝: 满血 %d 条 ｜ 半血 %d 条 ｜ 残血(10%%) %d 条" % [n_full, n_half, n_low])
	_ok("⑨ 剑·血祭 ★满血【一条都不画】(没有加成就没有表现)", n_full == 0)
	_ok("⑨ 剑·血祭 血丝随已损失生命变多(半血 %d < 残血 %d)" % [n_half, n_low], n_half < n_low)
	_ok("⑨ 剑·血祭 残血时接近上限 %d 条" % SynergyVfx.BLOOD_WISPS, n_low >= SynergyVfx.BLOOD_WISPS - 1)
	## 亮度也随之涨(量真实材质, 不是"条数够了就算")
	_s._vfx._syn.blood_rite_update(bu, 0.2, 0.0)
	var a_lo := 0.0
	var a_hi := 0.0
	var wisp0 = ((bu.get("_blood_vfx", {}) as Dictionary).get("wisps", []) as Array)[0]
	if is_instance_valid(wisp0):
		a_lo = (wisp0.material_override as StandardMaterial3D).albedo_color.a
	_s._vfx._syn.blood_rite_update(bu, 0.95, 0.0)
	if is_instance_valid(wisp0):
		a_hi = (wisp0.material_override as StandardMaterial3D).albedo_color.a
	_ok("⑨ 剑·血祭 ★血丝亮度也随残血涨(%.2f → %.2f)" % [a_lo, a_hi], a_hi > a_lo + 0.2)
	## 撤场: 单位死了要收干净
	var freed: int = _s._vfx._syn.blood_rite_free(bu)
	_ok("⑨ 剑·血祭 ★撤场 free 了 %d 个节点且引用清干净" % freed,
		freed >= SynergyVfx.BLOOD_WISPS and not bu.has("_blood_vfx"))

	# ── 法器·共鸣 ──────────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"法器": 4})
	_s._staff_syn._resonance()
	print("     _staff_syn._resonance() → 光柱 %d 根" % _count("light_pillar"))
	_ok("④ 法器·共鸣: 全队同时立柱(≥1)", _count("light_pillar") >= 1)

	# ── 法器·净化(★只有真的清掉了才放) ────────────────────────────
	await _reset()
	left["stun_until"] = _s._t + 5.0
	left["slow_until"] = _s._t + 5.0
	var cleared: int = _s._staff_syn.dispel(left, 2)
	print("     dispel(清 2 种) → 实清 %d 种 / 白环 %d 火花 %d" % [
		cleared, _count("ground_ring"), _count("spark_burst")])
	_ok("④ 法器·净化: 真的清掉了 2 种", cleared == 2)
	_ok("④ 法器·净化: 放了环 + 火花", _count("ground_ring") >= 1 and _count("spark_burst") >= 1)
	await _reset()
	left["dot_stacks"] = {}       # ★把别的减益也清空 —— 否则"什么都没清掉"这条反面可能被灼烧/中毒顶掉
	left["dots"] = []
	var cleared0: int = _s._staff_syn.dispel(left, 2)     # 已经干净了
	print("     ★反面: 身上没有减益时 dispel → 实清 %d 种 / 本层节点 %d 个 (需求 0/0)" % [
		cleared0, _count()])
	_ok("④ ★反面: 什么都没清掉时【不放】特效(否则是「没净化却闪了一下」)",
		cleared0 == 0 and _count() == 0)

	# ── 遗物·觉醒 ──────────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"遗物": 4})
	var awoke: int = _s._relic_syn._awaken_vfx("left")
	print("     _relic_syn._awaken_vfx('left') → 涉及 %d 只 / 柱%d 八边环%d 火花%d" % [
		awoke, _count("light_pillar"), _count("polygon_ring"), _count("spark_burst")])
	_ok("④ 遗物·觉醒: 柱 + 环 + 火花三样都有",
		awoke >= 1 and _count("light_pillar") >= 1 and _count("polygon_ring") >= 1
		and _count("spark_burst") >= 1)

	# ── 遗物·生死界跨线(★滞回 + 首次静默) ────────────────────────
	await _reset()
	left["_relic_atk_bonus"] = 0.05
	left.erase("_relic_gate_vfx")
	left["hp"] = float(left["maxHp"])
	_s._relic_syn._gate_tick()
	print("     首次观测(满血) → 本层节点 %d 个 (需求 0 —— 开局不该闪)" % _count())
	_ok("④ ★遗物·生死界: 第一次观测只记状态、不放特效", _count() == 0)
	left["hp"] = float(left["maxHp"]) * 0.30
	_s._relic_syn._gate_tick()
	print("     跌破 50% → 八边环 %d 个 (需求 ≥1)" % _count("polygon_ring"))
	_ok("④ 遗物·生死界: 跌破 50% 放一次", _count("polygon_ring") >= 1)
	var after_down: int = _count("polygon_ring")
	_s._relic_syn._gate_tick()
	_s._relic_syn._gate_tick()
	_ok("④ ★同一侧反复喂不重放", _count("polygon_ring") == after_down)
	left["hp"] = float(left["maxHp"]) * 0.51        # 落在滞回带内(50%±2pp)
	_s._relic_syn._gate_tick()
	print("     回到 51%(滞回带内) → %d 个 (需求仍 %d)" % [_count("polygon_ring"), after_down])
	_ok("④ ★★滞回带内不抖(51% 不算「回到线上」)", _count("polygon_ring") == after_down)
	left["hp"] = float(left["maxHp"]) * 0.90
	_s._relic_syn._gate_tick()
	print("     回到 90% → %d 个 (需求 > %d)" % [_count("polygon_ring"), after_down])
	_ok("④ ★★回到线上又放一次(证明上面不是「永远不放」)", _count("polygon_ring") > after_down)

	# ── 遗物·远古之力【不再有任何演出】(用户 2026-08-07 拍板拆掉阈值特效) ──
	#    ★这是【反向守卫】而不是"删掉一组断言": 只删断言的话, 谁把演出加回来都不会红。
	#    ★用档 3 不用档 4 —— 档 4 有【觉醒】(20 秒那一下, 那条留着), 会自己建节点, 就分不清了。
	await _reset()
	_set_tiers("left", {"遗物": 3})
	for u in _s._units:
		if u is Dictionary:
			u["_ancient"] = 0.0
			u.erase("_ancient_vfx")
			u.erase("_relic_gate_vfx")
	_s._relic_syn._t_acc = 0.0
	for i in range(12):                            # 12 跳足够跨完原来的 34/67/100% 三档
		_s._relic_syn._t_acc = 0.0
		_s._relic_syn.tick(_s._relic_syn.PERIOD)
	var anc_grown: float = float(left.get("_ancient", 0.0))
	print("     ⛔ 遗物档3 跑 12 跳(远古之力涨到 %.3f) → 本层节点 %d 个 (需求 0)" % [
		anc_grown, _count()])
	_ok("④ ⛔遗物·远古之力: 拆掉后【一个演出节点都不建】", _count() == 0)
	_ok("④ ★分母: 远古之力确实在涨(证明上面不是「tick 根本没跑」)", anc_grown > 0.0)

	# ── 食物·学院(开场一次性) ──────────────────────────────────────
	await _reset()
	_set_tiers("left", {"食物": 2})
	for u in _s._units:
		if u is Dictionary:
			u.erase("_academy_done")
	_s._food_syn.apply_all()
	print("     _food_syn.apply_all() → 绿环 %d / 火花 %d" % [
		_count("ground_ring"), _count("spark_burst")])
	_ok("④ 食物·学院: 开场放一次", _count("ground_ring") >= 1)
	var aca: int = _count("ground_ring")
	_s._food_syn.apply_all()                      # 已经 _academy_done ⇒ 一点血都不加
	print("     ★反面: 再调一次(已 _academy_done, 一点血都不加) → %d 个 (需求仍 %d)" % [
		_count("ground_ring"), aca])
	_ok("④ ★反面: 重调不白闪(没加血就不该有特效)", _count("ground_ring") == aca)

	# ── 食物·成长【不再有任何演出】(用户 2026-08-07 拍板拆掉阈值特效) ────
	#    ★这一条是【反向守卫】: 不是"少写一组断言"就完了 —— 那样把演出加回来也不会红。
	await _reset()
	left.erase("_food_vfx")
	left["_food_grown"] = 0.0
	_s._food_syn._grow(left, 700.0)               # 一口气跨过原来的 100/300/600 三档
	print("     ⛔ 一次涨 700(原本会跨完三档) → 本层节点 %d 个 (需求 0)" % _count())
	_ok("④ ⛔食物·成长: 拆掉后【一个演出节点都不建】", _count() == 0)
	_ok("④ ★分母: 数值照常涨(证明上面不是「函数没跑」)",
		float(left.get("_food_grown", 0.0)) >= 700.0)

	# ── 药水·战利品 ────────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"药水": 3})
	_s._potion_syn._prey["left"] = right
	_s._potion_syn.on_death(right)
	print("     _potion_syn.on_death(猎物) → 辐射带 %d / 火花 %d" % [
		_count("energy_band"), _count("spark_burst")])
	_ok("④ 药水·战利品: 从尸体向全队辐射(带 ≥1 且火花 ≥1)",
		_count("energy_band") >= 1 and _count("spark_burst") >= 1)

	# ── 药水·猎物标记 ──────────────────────────────────────────────
	await _reset()
	_s._potion_syn._prey = {"left": null, "right": null}
	_s._potion_syn._t_mark = 0.0
	_s._potion_syn.tick(3.0)
	print("     _potion_syn.tick(3.0)(重选猎物) → 环 %d 个 (需求 2 = 准星双环)" % _count("ground_ring"))
	_ok("④ 药水·猎物: 选中那一刻放准星双环", _count("ground_ring") >= 2)

	# ── 盾·收殓 ────────────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"盾": 3})
	var sid: String = _an_equip_of("盾")
	_ok("④ ★分母: 从真实映射里取到一件盾装备 (%s)" % sid, sid != "")
	left["equips"] = [{"id": sid, "star": 1}]
	_s._shield_syn.on_enemy_died(right)
	## ★2026-08-12 收殓重做: 旧的"一道灵魂流"已被【金球高抛物线转移】取代。
	print("     _shield_syn.on_enemy_died(敌尸) → 金球 %d 个" % _count("reap_orb"))
	_ok("④ 盾·收殓: 尸体上生成【金球】飞向受益者(不再是一道灵魂流)",
		_count("reap_orb") >= 1)

	# ── 弓箭·腐蚀满 5 层 ───────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"弓箭": 3})
	for u in _s._units:
		if u is Dictionary:
			u["corrode_stacks"] = 0
			u["_corrode_vfx"] = 0
	for i in range(4):
		_s._bow_syn._t_corrode = 0.0
		_s._bow_syn.tick(3.0)
	print("     叠到 4 层 → 三角环 %d 个 (需求 0)" % _count("polygon_ring"))
	_ok("④ 弓箭·腐蚀: 没满 5 层不放", _count("polygon_ring") == 0)
	_s._bow_syn._t_corrode = 0.0
	_s._bow_syn.tick(3.0)
	print("     叠满 5 层 → 三角环 %d 个 (需求 ≥1)" % _count("polygon_ring"))
	_ok("④ 弓箭·腐蚀: 刚满 5 层放一次", _count("polygon_ring") >= 1)
	var cor: int = _count("polygon_ring")
	_s._bow_syn._t_corrode = 0.0
	_s._bow_syn.tick(3.0)
	_ok("④ ★满层后继续喂不重放", _count("polygon_ring") == cor)

	# ── 奇械·冰封 ──────────────────────────────────────────────────
	await _reset()
	# ★用【档 2】不是档 4: 僵硬从档 3 起才有(STIFF_TIER=3), 而僵硬跨 5 层【也会】画六边环。
	#   用档 4 的话这一条就分不清"环是冻结画的还是僵硬画的" —— 那就是个假断言。
	_set_tiers("left", {"奇械": 2})
	right["_gad_freeze_cd"] = 0.0
	right["_gad_freeze_immune"] = 0.0
	right["stiff_stacks"] = 0
	var froze := false
	for i in range(90):                     # p=0.25 ⇒ 90 次一次都不中的概率 ≈ 4e-12
		_s._gadget_syn.on_hit(left, right)
		if _count("polygon_ring") > 0:
			froze = true
			break
	print("     _gadget_syn.on_hit ×N(25%% 冻结概率·档2 无僵硬) → 六边霜环 %d 个 / 僵硬层 %d" % [
		_count("polygon_ring"), int(right.get("stiff_stacks", 0))])
	_ok("④ 奇械·冰封: 冻结那一下有专属六边霜环", froze)
	_ok("④ ★分母: 档 2 确实一层僵硬都没叠(证明上面那个环是冻结画的)",
		int(right.get("stiff_stacks", 0)) == 0)

	# ── 奇械·僵硬【不再有任何演出】(用户 2026-08-07 拍板拆掉阈值特效) ──
	#    ★同样是【反向守卫】: 走 add_stiff 的真入口, 一路叠满 20 层, 断"一个节点都不建"。
	await _reset()
	_set_tiers("left", {"奇械": 4})
	right["stiff_stacks"] = 0
	right.erase("_stiff_vfx")
	for i in range(25):                            # 叠到封顶, 原来会跨完 5/10/20 三档
		_s._gadget_syn.add_stiff(right, 1)
	print("     ⛔ add_stiff ×25(僵硬 %d 层, 原本会跨完三档) → 本层节点 %d 个 (需求 0)" % [
		int(right.get("stiff_stacks", 0)), _count()])
	_ok("④ ⛔奇械·僵硬: 拆掉后【一个演出节点都不建】", _count() == 0)
	_ok("④ ★分母: 层数确实叠满了(证明上面不是「函数没跑」)",
		int(right.get("stiff_stacks", 0)) == _s._gadget_syn.STIFF_MAX)

	# ── 法器·法力条满 ──────────────────────────────────────────────
	await _reset()
	_set_tiers("left", {"法器": 4})
	var stid: String = _an_equip_of("法器")
	_ok("④ ★分母: 从真实映射里取到一件法器 (%s)" % stid, stid != "")
	left["equips"] = [{"id": stid, "star": 1}]
	left["eq_state"] = {stid: {}}
	_s._staff_syn.add_mana(left, 999.0)          # 一口气灌满 ⇒ 真的 _fire
	print("     _staff_syn.add_mana(灌满) → 光柱 %d 根 (需求 ≥1)" % _count("light_pillar"))
	_ok("④ 法器·法力条满: 触发那一瞬有闪光", _count("light_pillar") >= 1)

	# ── ⛔ 三条阈值特效【拆干净了没】(用户 2026-08-07 拍板不做) ─────
	#    上面三条反向守卫管"跑真入口时不建节点"; 这一条管"演出层/常量层没留空壳" ——
	#    留空壳比留着更糟: 零调用者的死代码会被"断言函数存在"型门禁保护住
	#    (memory [[fb-verify-must-run-the-real-path]])。
	for m in ["relic_ancient_step", "food_growth_step", "gadget_stiff_step", "tier_of"]:
		_ok("④ ⛔ SynergyVfx 里没有 %s()(不留空壳)" % str(m), not _syn.has_method(str(m)))
	_ok("④ ⛔ relic_synergy_system 里没有 _ancient_step_vfx()",
		not _s._relic_syn.has_method("_ancient_step_vfx"))
	# ★常量用 `get_script_constant_map()` 查, 不用 `"X" in obj` —— `in` 查的是【属性】,
	#   const 不在属性表里, 那么写会永远返回 false = 恒真式(下面的反面组就是防这个的)。
	var kc: Dictionary = _s._relic_syn.get_script().get_script_constant_map()
	var kf: Dictionary = _s._food_syn.get_script().get_script_constant_map()
	var kg: Dictionary = _s._gadget_syn.get_script().get_script_constant_map()
	print("     ⛔ 三档常量还在不在 → ANCIENT=%s / GROW=%s / STIFF=%s (需求 全 false)" % [
		str(kc.has("ANCIENT_VFX_STEPS")), str(kf.has("GROW_VFX_STEPS")),
		str(kg.has("STIFF_VFX_STEPS"))])
	_ok("④ ⛔ 三个阈值常量都删了", not kc.has("ANCIENT_VFX_STEPS")
		and not kf.has("GROW_VFX_STEPS") and not kg.has("STIFF_VFX_STEPS"))
	# ★反面: 证明上面两组不是恒真式 —— 拿【留着的】那几条同名检查一遍, 必须全部还在。
	_ok("④ ★反面: 留着的演出入口确实还在(证明 has_method 检查有效)",
		_syn.has_method("relic_awaken") and _syn.has_method("food_academy")
		and _syn.has_method("gadget_freeze") and _syn.has_method("tier_advance"))
	_ok("④ ★反面: 留着的常量确实还在(证明常量表查得到东西)",
		kg.has("STIFF_MAX") and kf.has("GROW_PER_FOOD") and kc.has("GATE_DEADBAND"))


# ── ⑤ ★母题可分辨 ───────────────────────────────────────────────────────────
## 装备那边的教训: 四件召唤物共用一个白光球, 玩家分不出谁是谁。
## 这一组把"分得开"变成可判定的: 边数互不相同 + 主色两两色距够大。
func _g5_motifs() -> void:
	print("")
	print("  ⑤ ★母题可分辨(形状 + 颜色两道):")
	print("     边数: 弓箭=%d 奇械=%d 遗物=%d" % [SV.SIDES_BOW, SV.SIDES_GADGET, SV.SIDES_RELIC])
	_ok("⑤ ★三类的多边形边数两两不同",
		SV.SIDES_BOW != SV.SIDES_GADGET and SV.SIDES_GADGET != SV.SIDES_RELIC
		and SV.SIDES_BOW != SV.SIDES_RELIC)

	# 每条演出的【形状 + 颜色】。★两条都一样就是"四个白光球"那个坑。
	var motif := [
		["盾·怒气",     "圆冲击波", SV.RAGE_COL],
		["盾·收殓",     "带",       SV.COL_SHIELD_REAP],
		["枪·弹幕",     "辐射带",   SV.COL_GUN_BARRAGE],
		["枪·护盾",     "辐射带",   SV.COL_GUN_SHIELD],
		["法器·共鸣",   "柱",       SV.COL_STAFF],
		["法器·净化",   "圆环",     SV.COL_STAFF_PURE],
		["遗物·觉醒",   "八边环",   SV.COL_RELIC],
		["遗物·生死界", "八边环",   SV.COL_RELIC_LOW],
		["食物",        "圆环",     SV.COL_FOOD],
		["药水",        "辐射带",   SV.COL_POTION],
		["弓箭",        "三角环",   SV.COL_BOW],
		["奇械",        "六边环",   SV.COL_GADGET],
	]
	var worst := 999.0
	var worst_pair := ""
	var same_shape_worst := 999.0
	var same_shape_pair := ""
	for i in range(motif.size()):
		for j in range(i + 1, motif.size()):
			var a: Color = motif[i][2]
			var b: Color = motif[j][2]
			var d: float = Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			var tag: String = "%s ↔ %s" % [str(motif[i][0]), str(motif[j][0])]
			if d < worst:
				worst = d
				worst_pair = tag
			if str(motif[i][1]) == str(motif[j][1]) and d < same_shape_worst:
				same_shape_worst = d
				same_shape_pair = tag + " (同为「%s」)" % str(motif[i][1])
	print("     %d 条演出里最接近的一对: %s, RGB 距离 %.3f (需求 > 0.15)" % [
		motif.size(), worst_pair, worst])
	print("     其中【形状也相同】的最接近一对: %s, 距离 %.3f (需求 > 0.30 —— 形状撞了颜色就得更开)" % [
		same_shape_pair, same_shape_worst])
	_ok("⑤ ★任意两条的主色都拉得开 (RGB 距离 > 0.15)", worst > 0.15)
	_ok("⑤ ★★形状相同的两条, 颜色必须拉得更开 (> 0.30)", same_shape_worst > 0.30)
	# ★反面: 证明这两条会 FAIL —— 往表里塞一条"跟枪·弹幕一模一样"的, 距离必然是 0
	var fake: Color = SV.COL_GUN_BARRAGE
	var d0: float = Vector3(fake.r - SV.COL_GUN_BARRAGE.r, fake.g - SV.COL_GUN_BARRAGE.g,
		fake.b - SV.COL_GUN_BARRAGE.b).length()
	print("     ★反面: 拿「复制粘贴同一个颜色」进表 → 距离 %.3f (< 0.15 ⇒ 上面两条会红)" % d0)
	_ok("⑤ ★反面: 同色同形的一对距离是 0(证明上面不是恒真式)", d0 < 0.15)


# ── ⑥ ★演出不参与结算 ───────────────────────────────────────────────────────
## 「判定与演出分开」不能只写在注释里 —— 这一组把它变成可判定的。
func _g6_no_side_effects() -> void:
	print("")
	print("  ⑥ ★演出层【不参与任何结算】:")
	await _reset()
	var u = _side_unit("left")
	var v = _side_unit("right")
	if u == null or v == null:
		_ok("⑥ ★分母: 找到两只单位", false); return
	var snap := {
		"hp": float(u.get("hp", 0.0)), "shield": float(u.get("shield", 0.0)),
		"base_atk": float(u.get("base_atk", 0.0)), "damage_amp": float(u.get("damage_amp", 0.0)),
		"maxHp": float(u.get("maxHp", 0.0)),
	}
	var p: Vector2 = Vector2(u["pos"])
	var q: Vector2 = Vector2(v["pos"])
	# 把 B3 的每个演出入口都点一遍
	_syn.gun_turret_one(p, [q])
	_syn.gun_turret_two(p, [q], true)
	_syn.gun_turret_two(p, [q], false)
	_syn.staff_resonance([p, q])
	_syn.staff_dispel(p, 2)
	_syn.staff_mana_full(p)
	_syn.relic_awaken([p])
	_syn.relic_gate(p, true)
	_syn.relic_gate(p, false)
	_syn.food_academy([p])
	_syn.potion_harvest(q, [p])
	_syn.potion_prey_mark(q)
	_syn.shield_reap(q, p)
	_syn.bow_corrode_full(q)
	_syn.gadget_freeze(q)
	print("     15 次演出调用后: hp %.2f→%.2f  shield %.2f→%.2f  base_atk %.2f→%.2f  增伤 %.4f→%.4f" % [
		snap["hp"], float(u.get("hp", 0.0)), snap["shield"], float(u.get("shield", 0.0)),
		snap["base_atk"], float(u.get("base_atk", 0.0)),
		snap["damage_amp"], float(u.get("damage_amp", 0.0))])
	for k in snap:
		_ok("⑥ ★演出没动 %s" % str(k), absf(float(u.get(k, 0.0)) - float(snap[k])) < 0.0001)
	_ok("⑥ ★分母: 这 15 次真的建出了节点(不是「什么都没调所以什么都没变」)", _count() > 15)


# ── ⑦ 撤场干净 + 守 _world == null ──────────────────────────────────────────
func _g7_teardown_and_guard() -> void:
	print("")
	print("  ⑦ 撤场干净 + R2 守空:")
	var before: int = _count()
	var freed: int = _syn.clear()
	await get_tree().process_frame
	print("     撤之前 %d 个 → clear() free 掉 %d → 现在 %d 个" % [before, freed, _count()])
	_ok("⑦ ★分母: 撤之前确实有节点", before > 0)
	_ok("⑦ clear() 撤干净", _count() == 0)
	_ok("⑦ clear() 报的数对得上", freed == before)
	_syn.polygon_ring(P_A, Color(1, 1, 1, 1), 40.0, 6)
	_ok("⑦ ★★装回来又建得出(证明上一条不是「永久坏了」)", _count() == 1)

	await _reset()
	var saved = _s._world
	var n0: int = _syn.alive_count()
	_s._world = null
	var res := [
		_syn.polygon_ring(P_A, Color(1, 1, 1, 1), 40.0, 6),
		_syn.gun_turret_one(P_A, [P_B]),
		_syn.staff_dispel(P_A, 2),
		_syn.staff_mana_full(P_A),
		_syn.relic_gate(P_A, true),
		_syn.potion_prey_mark(P_A),
		_syn.shield_reap(P_A, P_B),
		_syn.bow_corrode_full(P_A),
		_syn.gadget_freeze(P_A),
	]
	var ints := [
		_syn.radial_spokes(P_A, [P_B], Color(1, 1, 1, 1)),
		_syn.gun_turret_two(P_A, [P_B], true),
		_syn.staff_resonance([P_A]),
		_syn.relic_awaken([P_A]),
		_syn.food_academy([P_A]),
		_syn.potion_harvest(P_A, [P_B]),
	]
	_s._world = saved
	var all_null := true
	for r in res:
		if r != null:
			all_null = false
	var all_zero := true
	for i in ints:
		if int(i) != 0:
			all_zero = false
	print("     _world=null 时: %d 个返回节点的入口全 null=%s / 6 个返回计数的全 0=%s" % [
		res.size(), str(all_null), str(all_zero)])
	_ok("⑨ ★R2: %d 个返回节点的新入口全部守空" % res.size(), all_null)
	_ok("⑨ ★R2: 6 个返回计数的新入口全部返回 0", all_zero)
	_ok("⑨ 一个节点都没偷偷记账", _syn.alive_count() == n0)
	var e = _syn.polygon_ring(P_A, Color(1, 1, 1, 1), 40.0, 6)
	_ok("⑨ ★反面: _world 装回来立刻又能建", e != null)


# ── 工具 ────────────────────────────────────────────────────────────────────

func _count(kind: String = "") -> int:
	var n := 0
	for c in _s._world.get_children():
		if not c.has_meta(SV.META_KEY):
			continue
		if kind != "" and str(c.get_meta(SV.META_KEY)) != kind:
			continue
		n += 1
	return n


## 两张贴图 alpha 不同的像素数(用来证明"边数"真的进了绘制, 不是同一张换色)。
func _tex_diff(a: Texture2D, b: Texture2D) -> int:
	if a == null or b == null:
		return -1
	var ia := a.get_image()
	var ib := b.get_image()
	if ia.get_width() != ib.get_width() or ia.get_height() != ib.get_height():
		return 999999
	var n := 0
	for y in range(ia.get_height()):
		for x in range(ia.get_width()):
			if absf(ia.get_pixel(x, y).a - ib.get_pixel(x, y).a) > 0.2:
				n += 1
	return n


func _side_unit(side: String):
	for u in _s._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side \
				and not u.get("_isEgg", false) and not u.get("is_trainer", false):
			return u
	return null


## 直接写羁绊档位表 —— 走的仍是 `_synergy.tier_for()` 那条真实查询链。
func _set_tiers(side: String, d: Dictionary) -> void:
	_s._synergy._by_side[side] = d.duplicate()


func _updot(spr: Sprite3D) -> float:
	var local_n := Vector3.BACK
	match spr.axis:
		Vector3.AXIS_X: local_n = Vector3.RIGHT
		Vector3.AXIS_Y: local_n = Vector3.UP
	return absf((spr.global_transform.basis * local_n).normalized().dot(Vector3.UP))


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
	print("ALL PASS — 十类羁绊的视觉母题(批 B3)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
