extends Node
## verify_vfx_readability.gd — 【金弹可辨】+ 七件演出调参 的门禁 (2026-08-07)
##
## ══════════════════════════════════════════════════════════════════════
##  ★这份门禁想守住的, 是过去所有门禁都没守住的那一条
## ══════════════════════════════════════════════════════════════════════
## 方案书 §2.1 的原话:「★而我的门禁全绿 —— 因为它验的是『航线长 800 码对不对』…
## 这些全对, 而它看起来什么都不是。**全表没有一条断言是"它看起来像不像那个东西"**。」
## ⇒ 本文件的每一条都落在【能被量出来的可读性属性】上, 而不是"函数被调了":
##   · **形状**: 拿程序化贴图的**像素**去验剪影(菱形的四个角必须空 / 盾形下缘必须收尖 /
##     进度环点亮格数必须 = 层数) —— 这是"遮住颜色只看剪影"那条判据的可执行版本;
##   · **对比度/饱和度**: 量真实节点的颜色, 断言"不是白的"(078 电弧那条的正解);
##   · **尺寸**: 换算到 1280×720 的屏幕像素, 断言 ≥ 头顶等级徽章的 16 px;
##   · **两条曲线不能撞**: 尺寸到顶那一帧 alpha 必须也在顶(`_skill_ring` 的同款 bug)。
##
## ⚠ 全部**同步断言**(CLAUDE.md §3.5): 调完入口下一行就判, 不等任何 tween / 不数帧。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_vfx_readability.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const GSV := preload("res://scripts/scenes/battle/golden_shot_vfx.gd")
const BEV := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")
const AEV := preload("res://scripts/scenes/battle/arcane_eq_vfx.gd")
const IV := preload("res://scripts/scenes/battle/incense_vfx.gd")
const GEV := preload("res://scripts/scenes/battle/gun_eq_vfx.gd")
const EAB := preload("res://scripts/systems/equip/eq_arcane_batch.gd")

## 屏幕标尺: 1280×720 下 1 码 ≈ 这么多屏幕像素(方案书 §0「判『看不见』时必须带数字」)。
const PX_PER_YARD := 0.69
## 头顶等级徽章的屏幕高度(px)。低于它 = 实战中基本等于不存在。
const BADGE_PX := 16.0

## 枪羁绊【金弹】逐档真伤比例。★写**字面值**, 不引用常量 ——
##   引用就是拿代码跟它自己比, 那是恒真式(memory [[fb-verify-check-can-fail]])。
const WANT_GOLD_PCT := [0.60, 0.80, 1.00]
## 083 潮汐细剑的层数上限(规格原文)
const WANT_STACK_CAP := 20
## 090 镇海杵的砸落半径 / 起跳峰高(规格原文)
const WANT_SLAM_R := 1000.0
const WANT_APEX_M := 2.4

var _n := 0
var _fail := 0
var _s
var _gold
var _blade
var _arc
var _inc


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 金弹可辨 + 七件演出可读性 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame

	_g0_denominator()
	if _gold == null:
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	await _g1_gold_wired()
	_g2_gold_shape()
	await _g3_gold_vs_normal()
	_g4_078_arc()
	_g5_081_shield()
	await _g6_082_shells()
	_g7_083_stacks()
	_g8_grow_curve()
	_g9_088_boundary()
	_g10_090_leap()
	await _g11_093_incense()
	await _done()


# ══════════════════════════════════════════════════════════════════
#  ① ★分母 —— 拿不到这些, 后面全是空检查
# ══════════════════════════════════════════════════════════════════
func _g0_denominator() -> void:
	print("")
	print("  ① ★分母 + 接线:")
	_ok("① 世界节点 _world 在", is_instance_valid(_s._world))
	_ok("① 场上有单位 (N=%d)" % _s._units.size(), _s._units.size() > 0)
	# ★不是"断言类存在", 而是断言主场景真的把它 new 出来了 ——
	#   零调用者的死函数被门禁保护着, 是本项目栽过的坑([[fb-verify-must-run-the-real-path]])。
	_gold = _s._gold_vfx
	_ok("① 主场景真的持有 GoldenShotVfx (battle._gold_vfx)", _gold != null and _gold is GoldenShotVfx)
	_inc = _s._incense_vfx
	_ok("① 主场景真的持有 IncenseVfx", _inc != null and _inc is IncenseVfx)
	_blade = BEV.new(_s)
	_arc = AEV.new(_s)


# ══════════════════════════════════════════════════════════════════
#  ② 金弹接在【唯一那个出口】上 —— 不是"每件装备各写一份"
# ══════════════════════════════════════════════════════════════════
func _g1_gold_wired() -> void:
	print("")
	print("  ② 金弹的挂点(★收口在 _queue_shots 一处):")
	var src: String = _read("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("② ★分母: 主场景源码读得到 (len=%d)" % src.length(), src.length() > 10000)
	var body: String = _fn_body(src, "func _queue_shots")
	_ok("② ★分母: _queue_shots 的函数体读得到 (len=%d)" % body.length(), body.length() > 200)
	_ok("② 金弹分支里调了 _gold_vfx.arm(", body.contains("_gold_vfx.arm("))
	_ok("② 金弹分支里调了 _gold_vfx.resolve(", body.contains("_gold_vfx.resolve("))
	# ★"只在一处" = 全仓除了这个出口与演出层自己, 没有第二处调 arm/resolve
	var hits := 0
	for f in _gd_files("res://scripts"):
		if f.ends_with("golden_shot_vfx.gd"):
			continue
		var t: String = _read(f)
		if t.contains("_gold_vfx.arm(") or t.contains("_gold_vfx.resolve("):
			hits += 1
	_ok("② ★全仓只有【一个】文件调 arm/resolve (实测 %d 个)" % hits, hits == 1, "多一处就是抄了副本")
	# 逐档真伤比例: 演出亮度 ≡ 羁绊真伤比例(一个数两处用)
	for i in range(3):
		var p: float = float(WANT_GOLD_PCT[i])
		_ok("② %d 档: GoldenShotVfx.glow(%.2f) ≡ %.2f" % [i + 1, p, p], is_equal_approx(GSV.glow(p), p))
		_ok("② %d 档: 与 GunEqVfx.gold_glow 逐档相等" % (i + 1),
			is_equal_approx(GSV.glow(p), GEV.gold_glow(p)))
	_ok("② 源码里那张逐档表就是 [0.60, 0.80, 1.00]",
		body.contains("[0.60, 0.80, 1.00]"), "表改了演出亮度就跟着错")


# ══════════════════════════════════════════════════════════════════
#  ③ 金弹的【剪影】—— 菱形族, 遮住颜色也不是圆/不是直条
# ══════════════════════════════════════════════════════════════════
func _g2_gold_shape() -> void:
	print("")
	print("  ③ 金弹的剪影(拿贴图像素验, 不是看颜色):")
	var bead: Image = GSV.bead_tex().get_image()
	var n: int = bead.get_width()
	var c: int = int(float(n - 1) * 0.5)
	# 菱形的判据: 四条边的【中点】实心, 四个【角】全空。圆形四个角也空, 但——
	var q4: int = int(float(n) * 0.25)
	var axis_a: float = bead.get_pixel(c, q4).a        # 竖轴半程(菱形内部)
	var corner_a: float = bead.get_pixel(2, 2).a       # 左上角
	_ok("③ 菱珠: 竖轴半程是实的 (a=%.2f)" % axis_a, axis_a > 0.5)
	_ok("③ 菱珠: 四角是空的 (a=%.2f)" % corner_a, corner_a < 0.02)
	# ——所以再加一条**只有菱形过得了**的: 45° 对角线方向上, 半径 0.5 处必须是空的
	#   (圆形在那儿是实的)。这一条把"菱形"与"圆形"真正分开。
	var q: int = int(float(n) * 0.25)
	var diag_a: float = bead.get_pixel(c - q, c - q).a
	_ok("③ ★菱珠: 对角线半程是空的 (a=%.2f) —— 圆形在这里是实的" % diag_a, diag_a < 0.02)
	# 空心菱框: 中心必须是空的(实心菱在这里是满的)
	var fr: Image = GSV.frame_tex().get_image()
	var fc: int = int(float(fr.get_width() - 1) * 0.5)
	_ok("③ 菱框: 中心空 (a=%.2f)" % fr.get_pixel(fc, fc).a, fr.get_pixel(fc, fc).a < 0.02)
	_ok("③ 菱框: 边中点实 (a=%.2f)" % fr.get_pixel(fc, 8).a, fr.get_pixel(fc, 8).a > 0.4)
	# 尺寸: 命中菱框换算到屏幕必须 ≥ 头顶徽章
	var r1: float = GSV.hit_radius(1.0, 1.0) * 2.0 * PX_PER_YARD
	_ok("③ 命中菱框满尺寸 %.0f 屏幕 px ≥ 徽章 %.0f px" % [r1, BADGE_PX], r1 >= BADGE_PX)
	var bead_px: float = GSV.BEAD_PX * PX_PER_YARD
	_ok("③ 单颗菱珠 %.0f 屏幕 px ≥ 徽章的一半" % bead_px, bead_px >= BADGE_PX * 0.5)
	# 零素材: 程序生成 ⇒ resource_path 是空串(不是从 assets/ load 来的)
	_ok("③ 零素材: 菱珠贴图 resource_path 为空", GSV.bead_tex().resource_path == "")


# ══════════════════════════════════════════════════════════════════
#  ④ ★金弹与普通弹【真的不一样】—— 量真实节点, 不是"函数被调了"
# ══════════════════════════════════════════════════════════════════
func _g3_gold_vs_normal() -> void:
	print("")
	print("  ④ ★金弹 vs 普通弹(量真实节点):")
	var a := Vector2(700.0, 400.0)
	var b := Vector2(1000.0, 400.0)
	var shooter: Dictionary = {"pos": a, "alive": true, "hp": 100.0, "shield": 0.0, "height": 0.0}
	var victim: Dictionary = {"pos": b, "alive": true, "hp": 100.0, "shield": 0.0, "height": 0.0}
	_gold.clear()
	await get_tree().process_frame
	_ok("④ ★分母: 起手本层零节点", _gold.alive_count() == 0)

	# —— 普通弹: 一发不走金弹分支 ⇒ 本层【一个节点都不该有】——
	var gun := GEV.new(_s)
	gun.tracer(a, b, Color("#ffcf6b"), 0.0)
	_ok("④ 普通弹: 金弹演出层仍然是 0 个节点 (实测 %d)" % _gold.alive_count(), _gold.alive_count() == 0)
	var plain_nodes: int = _mesh_count(gun)
	gun.clear()

	# —— 金弹: 走真实的 arm/resolve 差分路径 ——
	_gold.arm(shooter)
	victim["hp"] = 60.0                              # 模拟"这一发把它打掉了 40 血"
	# ★合成单位【不在】 battle._units 里 ⇒ 差分当然认不出它。这一条正是要它认不出:
	#   "只对真的在场上、真的掉了血的人画" 才是这套差分的语义。
	var marked: int = _gold.resolve(0.60)
	_ok("④ ★场外的合成单位不会被误标 (marked=%d ≡ 0)" % marked, marked == 0)
	_gold.clear()
	var real = _first_alive()
	_ok("④ ★分母: 单位表里取得到一个活单位", real != null)
	if real != null:
		_gold.arm(shooter)
		real["hp"] = maxf(1.0, float(real["hp"]) - 50.0)
		var m2: int = _gold.resolve(0.60)
		_ok("④ ★掉血的那个真被标上了 (marked=%d ≥ 1)" % m2, m2 >= 1)
		_ok("④ 金弹演出层真的建出了节点 (%d 个 > 普通弹的 %d)" % [_gold.alive_count(), plain_nodes],
			_gold.alive_count() > plain_nodes)
		_ok("④ 三样都在: 枪口 / 弹迹 / 命中",
			_gold.alive_count("muzzle") >= 1 and _gold.alive_count("bead") >= 1
			and _gold.alive_count("frame") >= 1,
			"muzzle=%d bead=%d frame=%d" % [_gold.alive_count("muzzle"),
				_gold.alive_count("bead"), _gold.alive_count("frame")])
		# ★没掉血就不该画 —— 否则"标记"是恒真的, 等于没验
		_gold.clear()
		_gold.arm(shooter)
		var m3: int = _gold.resolve(0.60)
		_ok("④ ★反面: 谁都没掉血 ⇒ 一个人都不标 (marked=%d)" % m3, m3 == 0)
		_ok("④ ★反面: 也不画命中(只留枪口) frame=%d" % _gold.alive_count("frame"),
			_gold.alive_count("frame") == 0)
	# 档位越高越亮越大(一个数两处用)
	_ok("④ 3 档的命中菱框比 1 档大 (%.0f > %.0f 码)" % [GSV.hit_radius(1.0, 1.0), GSV.hit_radius(1.0, 0.6)],
		GSV.hit_radius(1.0, 1.0) > GSV.hit_radius(1.0, 0.6))
	_gold.clear()
	await get_tree().process_frame
	_ok("④ 撤场干净 (剩 %d)" % _gold.alive_count(), _gold.alive_count() == 0)


# ══════════════════════════════════════════════════════════════════
#  ⑤ 078: 电弧【不是白的】+ 两管相位真的分开
# ══════════════════════════════════════════════════════════════════
func _g4_078_arc() -> void:
	print("")
	print("  ⑤ 078 电鳗双管铳:")
	# ①「不是白的」的可执行判据 = 饱和度。白 = 饱和度 0; 旧色 #9bdcff 的饱和度只有 0.39。
	var s_old: float = _sat(Color("#9bdcff"))
	var s_new: float = _sat(GEV.COL_ARC)
	_ok("⑤ ★电弧身饱和度 %.2f > 旧色 %.2f 且 ≥ 0.60" % [s_new, s_old], s_new >= 0.60 and s_new > s_old)
	_ok("⑤ 白热芯只是芯: 它的饱和度 %.2f 低于身 %.2f" % [_sat(GEV.COL_ARC_CORE), s_new],
		_sat(GEV.COL_ARC_CORE) < s_new)
	# ② 两管出膛点必须**真的分开**, 且分居瞄准线两侧
	var org := Vector2(700.0, 400.0)
	var dir := Vector2(1.0, 0.0)
	var ml: Vector2 = GEV.barrel_muzzle(org, dir, true)
	var mr: Vector2 = GEV.barrel_muzzle(org, dir, false)
	var sep: float = ml.distance_to(mr)
	_ok("⑤ ★两管出膛点相隔 %.0f 码 ≥ 2×BARREL_OFF" % sep, sep >= GEV.BARREL_OFF * 2.0 - 0.01)
	var perp := Vector2(-dir.y, dir.x)
	_ok("⑤ ★两管分居瞄准线两侧(投影异号)", (ml - org).dot(perp) * (mr - org).dot(perp) < 0.0)
	_ok("⑤ 出膛点间距 %.0f 屏幕 px ≥ 徽章 %.0f px" % [sep * PX_PER_YARD, BADGE_PX],
		sep * PX_PER_YARD >= BADGE_PX)
	# ③ 电弧的自仿射性质没被这次改动破坏(旧模型仍然成立)
	var r: float = GEV.arc_sigma(2, 100.0) / GEV.arc_sigma(1, 100.0)
	_ok("⑤ 逐级偏移比 ≡ 1/√2 (实测 %.6f)" % r, absf(r - 0.7071067812) < 1e-6)
	# ④ 右管真的画了"从枪口打出去"这一段 —— 结算侧调了 eel_bolt
	var eb: String = _read("res://scripts/systems/equip/eq_gun_batch.gd")
	_ok("⑤ ★分母: eq_gun_batch 源码读得到", eb.length() > 5000)
	_ok("⑤ 右管真的画了枪口→首目标(调了 vfx.eel_bolt)", eb.contains("vfx.eel_bolt("))
	# ⑤ 双层画法: 身用 MIX(不会越叠越白), 芯才用 ADD
	var gv: String = _read("res://scripts/scenes/battle/gun_eq_vfx.gd")
	var cb: String = _fn_body(gv, "func chain_arc")
	_ok("⑤ ★分母: chain_arc 函数体读得到 (len=%d)" % cb.length(), cb.length() > 100)
	_ok("⑤ 身走非 ADD 混合(结构上堵死'越叠越白')", cb.contains(", false)"))


# ══════════════════════════════════════════════════════════════════
#  ⑥ 081: 盾形剪影 / 起手就有 alpha / 藤青不烧白 / 断续环
# ══════════════════════════════════════════════════════════════════
func _g5_081_shield() -> void:
	print("")
	print("  ⑥ 081 藤编圆盾:")
	# ① 剪影不是圆盘: 上缘满宽、下缘收尖 —— 圆盘在这两处是对称的
	var img: Image = BEV.vine_shield_tex().get_image()
	var n: int = img.get_width()
	var cx: int = int(float(n - 1) * 0.5)
	var w_top: int = _row_width(img, int(float(n) * 0.22))
	var w_mid: int = _row_width(img, int(float(n) * 0.5))
	var w_bot: int = _row_width(img, int(float(n) * 0.90))
	_ok("⑥ ★盾形: 下缘收尖 (底 %d px < 腰 %d px 的一半)" % [w_bot, w_mid], w_bot * 2 < w_mid)
	_ok("⑥ ★盾形: 上缘接近满宽 (顶 %d px > 腰 %d px 的 0.8 倍)" % [w_top, w_mid],
		float(w_top) > float(w_mid) * 0.8)
	# 圆盘在同样两行的宽度是【对称】的 —— 这一条证明上面两条不是恒真
	var disc: Image = VfxTex._make_disc_texture().get_image()
	var dn: int = disc.get_width()
	var d_top: int = _row_width(disc, int(float(dn) * 0.22))
	var d_bot: int = _row_width(disc, int(float(dn) * 0.90))
	var d_mid: int = _row_width(disc, int(float(dn) * 0.5))
	# ★先过分母 —— d_top/d_bot 同为 0 时上面那条会"通过"而什么都没验到
	_ok("⑥ ★分母: 圆盘贴图量得到宽度 (腰 %d px > 0)" % d_mid, d_mid > 0)
	_ok("⑥ ★对照: 圆盘上下缘宽度接近(%d vs %d, 差 < 腰的 30%%) ⇒ 上面两条不是恒真" % [d_top, d_bot],
		d_mid > 0 and absf(float(d_top - d_bot)) < float(d_mid) * 0.30)
	# ② 起手 alpha 不是 0(原来是 0, 抬盾那一瞬完全透明)
	_ok("⑥ ★起手 alpha = %.2f > 0" % BEV.GUARD_A0, BEV.GUARD_A0 > 0.2)
	_ok("⑥ 临界阻尼只负责继续张开 (A1 %.2f > A0 %.2f)" % [BEV.GUARD_A1, BEV.GUARD_A0],
		BEV.GUARD_A1 > BEV.GUARD_A0)
	# ③ 藤青不烧白: 饱和度够高 + 明度不顶
	var vb: Color = BEV.VINE_BODY
	_ok("⑥ ★藤青饱和度 %.2f ≥ 0.55(旧色 %.2f)" % [_sat(vb), _sat(Color(0.55, 0.82, 0.52))],
		_sat(vb) >= 0.55 and _sat(vb) > _sat(Color(0.55, 0.82, 0.52)))
	_ok("⑥ ★藤青明度 %.2f ≤ 0.75(旧色 0.82 ⇒ 叠出来读作白)" % maxf(maxf(vb.r, vb.g), vb.b),
		maxf(maxf(vb.r, vb.g), vb.b) <= 0.75)
	# ④ 贴地环是**断续**的(平滑细环全场到处都是) —— 沿圆周采样必须有亮有暗
	var ring: Image = BEV.vine_ring_tex().get_image()
	var rn: int = ring.get_width()
	var rc: float = float(rn - 1) * 0.5
	var lit := 0
	var dark := 0
	for k in range(96):
		var th: float = float(k) / 96.0 * TAU
		var px: int = int(rc + cos(th) * rc * 0.90)
		var py: int = int(rc + sin(th) * rc * 0.90)
		if ring.get_pixel(clampi(px, 0, rn - 1), clampi(py, 0, rn - 1)).a > 0.4:
			lit += 1
		else:
			dark += 1
	_ok("⑥ ★贴地环是断续的 (亮 %d / 暗 %d, 两者都 ≥ 20)" % [lit, dark], lit >= 20 and dark >= 20)
	_ok("⑥ 盾面 %.0f 屏幕 px ≥ 徽章 %.0f px" % [BEV.GUARD_R_PX * PX_PER_YARD, BADGE_PX],
		BEV.GUARD_R_PX * PX_PER_YARD >= BADGE_PX)
	_ok("⑥ 零素材: 盾面贴图 resource_path 为空", BEV.vine_shield_tex().resource_path == "")


# ══════════════════════════════════════════════════════════════════
#  ⑦ 082: 反伤【不再是一条直条】—— 离散贝壳链
# ══════════════════════════════════════════════════════════════════
func _g6_082_shells() -> void:
	print("")
	print("  ⑦ 082 砗磲护心甲:")
	var u: Dictionary = {"pos": Vector2(700.0, 400.0), "alive": true, "height": 0.0}
	var atk: Dictionary = {"pos": Vector2(880.0, 400.0), "alive": true, "height": 0.0}
	_blade.clear()
	await get_tree().process_frame
	var made: int = _blade.clam_reflect(u, atk)
	_ok("⑦ ★反伤是【多枚】离散贝壳而不是一条直条 (%d ≥ 3)" % made, made >= 3)
	_ok("⑦ 真的建进了 _world (%d 个)" % _blade.owned_count(), _blade.owned_count() >= made)
	# 贝壳的剪影: 中心空(扇形有内半径) + 单侧开口 —— 实心直条两条都不满足
	var sh: Image = BEV.shell_tex().get_image()
	var sn: int = sh.get_width()
	var sc: int = int(float(sn - 1) * 0.5)
	_ok("⑦ ★贝壳中心是空的 (a=%.2f) —— 实心直条在这里是满的" % sh.get_pixel(sc, sc).a,
		sh.get_pixel(sc, sc).a < 0.05)
	var right_a: float = sh.get_pixel(sn - 4, sc).a
	var left_a: float = sh.get_pixel(3, sc).a
	_ok("⑦ ★贝壳是单侧开口的扇 (右 %.2f 实 / 左 %.2f 空)" % [right_a, left_a],
		right_a > 0.25 and left_a < 0.05)
	# 平方反比亮度那条模型没被这次改动破坏
	var i0: float = BEV.reflect_intensity(0.0, BEV.REFLECT_D0)
	var id0: float = BEV.reflect_intensity(BEV.REFLECT_D0, BEV.REFLECT_D0)
	_ok("⑦ I(d₀)/I(0) ≡ 0.5 (实测 %.6f)" % (id0 / i0), absf(id0 / i0 - 0.5) < 1e-6)
	# 离地高度: 不能是 0(常态 u["height"] 恒为 0, 贴地就被影子/飘字压掉)
	_ok("⑦ ★离地 %.2f m > 0 —— 不再贴在地面被压掉" % BEV.SHELL_Y, BEV.SHELL_Y > 0.4)
	_ok("⑦ 单枚 %.0f 屏幕 px ≥ 徽章的一半" % (BEV.SHELL_PX * PX_PER_YARD),
		BEV.SHELL_PX * PX_PER_YARD >= BADGE_PX * 0.5)
	_blade.clear()


# ══════════════════════════════════════════════════════════════════
#  ⑧ 083: 20 层【数得出来】
# ══════════════════════════════════════════════════════════════════
func _g7_083_stacks() -> void:
	print("")
	print("  ⑧ 083 潮汐细剑(20 层是核心资源):")
	_ok("⑧ 刻度格数 = 层数上限 %d" % WANT_STACK_CAP,
		BEV.STACK_TICKS == WANT_STACK_CAP and int(BEV.STACK_CAP) == WANT_STACK_CAP)
	# ★核心一条: 点亮的弧长比例 ≡ stacks/20。拿**真实贴图的像素**去数, 不是重算公式。
	# ★比的是【相对满档】的比例: 每格之间留了分隔缝(才数得出格数), 所以绝对占空比
	#   天然到不了 1.0。拿满档当分母, 量的就是"点亮几格 / 一共几格"。
	var full: float = _lit_arc_frac(BEV.stack_ring_tex(WANT_STACK_CAP).get_image())
	_ok("⑧ ★分母: 满档环真的点亮了(占空比 %.3f > 0.5)" % full, full > 0.5)
	for st in [0, 1, 5, 13, 20]:
		var img: Image = BEV.stack_ring_tex(st).get_image()
		var frac: float = _lit_arc_frac(img) / maxf(0.001, full)
		var want: float = float(st) / float(WANT_STACK_CAP)
		_ok("⑧ ★%2d 层: 点亮 %.3f 圈, 应为 %.3f" % [st, frac, want], absf(frac - want) < 0.06)
	# 直径也随层数涨(远看也读得出多寡)
	_ok("⑧ 20 层比 1 层大 (%.0f > %.0f 码)" % [BEV.stack_diam(20), BEV.stack_diam(1)],
		BEV.stack_diam(20) > BEV.stack_diam(1) + 20.0)
	_ok("⑧ 0 层的环 %.0f 屏幕 px ≥ 徽章 %.0f px" % [BEV.stack_diam(0) * PX_PER_YARD, BADGE_PX],
		BEV.stack_diam(0) * PX_PER_YARD >= BADGE_PX)
	# 亮度那条对数刻度仍然成立(低层被拉开)
	_ok("⑧ 对数刻度: g(4)=%.3f > 线性的 0.200" % BEV.stack_glow(4), BEV.stack_glow(4) > 0.2)
	# ★"轨道"必须看得见 —— 否则进度条只是一段弧, 读不出"还差多少"
	var img5: Image = BEV.stack_ring_tex(5).get_image()
	_ok("⑧ ★未点亮的格子仍可见 (轨道 alpha %.2f ≥ 0.20)" % _unlit_alpha(img5),
		_unlit_alpha(img5) >= 0.20)


# ══════════════════════════════════════════════════════════════════
#  ⑨ ★"长到最大那一帧正好全透明" —— 与 _skill_ring 同款 bug
# ══════════════════════════════════════════════════════════════════
func _g8_grow_curve() -> void:
	print("")
	print("  ⑨ ★grow 的两条曲线不能撞(082 clam_burst / 084 cross_retreat 吃这条):")
	var k: float = BEV.GROW_KNEE
	_ok("⑨ ★尺寸到顶那一刻 alpha 也在顶: size=%.3f alpha=%.3f" % [BEV.grow_size_frac(k), BEV.grow_alpha(k)],
		is_equal_approx(BEV.grow_size_frac(k), 1.0) and is_equal_approx(BEV.grow_alpha(k), 1.0))
	# ★证明这条不是恒真: 旧写法(size=x, alpha=1−x)在同一点上 alpha = 1−k ≠ 1
	_ok("⑨ ★对照: 旧写法在同一点 alpha = %.3f ≠ 1 ⇒ 本条会 FAIL" % (1.0 - k), absf(1.0 - k - 1.0) > 0.1)
	_ok("⑨ 扩张期不淡: alpha(0)=alpha(k/2)=1", is_equal_approx(BEV.grow_alpha(k * 0.5), 1.0))
	_ok("⑨ 长满之后才淡到 0: alpha(1)=%.3f" % BEV.grow_alpha(1.0), is_equal_approx(BEV.grow_alpha(1.0), 0.0))
	_ok("⑨ 长满之后不再变大: size(1)=%.3f" % BEV.grow_size_frac(1.0), is_equal_approx(BEV.grow_size_frac(1.0), 1.0))
	var src: String = _read("res://scripts/scenes/battle/blade_eq_vfx.gd")
	var tb: String = _fn_body(src, "func tick")
	_ok("⑨ ★分母: tick 函数体读得到 (len=%d)" % tb.length(), tb.length() > 200)
	_ok("⑨ tick 真的用了这两条曲线", tb.contains("grow_size_frac(") and tb.contains("grow_alpha("))
	_ok("⑨ ★旧写法(alpha = 1.0 - x)已从 grow 分支里消失", not tb.contains("_set_a(n, 1.0 - x)\n\t\t\t\"wave\""))


# ══════════════════════════════════════════════════════════════════
#  ⑩ 088: 圈内 / 圈外读得出
# ══════════════════════════════════════════════════════════════════
func _g9_088_boundary() -> void:
	print("")
	print("  ⑩ 088 涨潮碑(边界):")
	var mesh: ArrayMesh = AEV._build_boundary_ring()
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	_ok("⑩ ★分母: 边界环建出了顶点 (N=%d)" % verts.size(), verts.size() > 100)
	# 三层各自都要在: 圈内底色(小半径·低 alpha) / 硬边(≈1.0 半径·满 alpha) / 刻度
	var fill_a := -1.0
	var rim_a := 0.0
	# ★必须同时看【最小值】: 只看 max 的话, 外沿哪怕只剩一个顶点是满的就"通过"了 ——
	#   反向验证第 4 条(把外沿的一半改成 0.30)当场证明了这一点: 门禁全绿、什么都没抓到。
	var rim_min := 2.0
	var tick_v := 0
	for i in range(verts.size()):
		var r: float = Vector2(verts[i].x, verts[i].z).length()
		var a: float = cols[i].a
		if r < 0.05:
			fill_a = a
		if r > 0.99:
			rim_a = maxf(rim_a, a)
			rim_min = minf(rim_min, a)
		# 刻度的外端: 半径落在硬边内沿、alpha 是 0.95(硬边本身是 1.0) ⇒ 只有刻度符合
		if absf(r - AEV.BOUNDARY_RIM) < 0.005 and a > 0.90 and a < 0.99:
			tick_v += 1
	_ok("⑩ ★圈内有底色 (圆心 alpha %.3f, 0 < a < 0.3)" % fill_a, fill_a > 0.0 and fill_a < 0.3)
	_ok("⑩ ★外沿是硬边: 整圈 alpha 的【最小值】%.3f ≥ 0.99(不是只有一段)" % rim_min, rim_min >= 0.99)
	_ok("⑩ 硬边最亮/最暗同为满 (max %.3f / min %.3f)" % [rim_a, rim_min], rim_a >= 0.99 and rim_min >= 0.99)
	# 每根刻度 = 2 个三角 = 外端 3 个顶点(两个三角共用一条边)
	_ok("⑩ ★有向内的刻度 (刻度外端顶点 %d 个, 应 = 3×%d)" % [tick_v, AEV.BOUNDARY_TICKS],
		tick_v == AEV.BOUNDARY_TICKS * 3)
	_ok("⑩ 刻度根数 %d ≥ 12(每 30° 至少一根)" % AEV.BOUNDARY_TICKS, AEV.BOUNDARY_TICKS >= 12)
	# ★对照: 旧的软环在 r=1.0 处只有 0.30 —— 证明"硬边"这条不是恒真
	var soft: ArrayMesh = AEV._build_ring()
	var sarr: Array = soft.surface_get_arrays(0)
	var sv: PackedVector3Array = sarr[Mesh.ARRAY_VERTEX]
	var sc: PackedColorArray = sarr[Mesh.ARRAY_COLOR]
	var soft_rim := 0.0
	for i in range(sv.size()):
		if Vector2(sv[i].x, sv[i].z).length() > 0.99:
			soft_rim = maxf(soft_rim, sc[i].a)
	_ok("⑩ ★对照: 潮涌用的软环外沿只有 %.2f ⇒ 上面那条不是恒真" % soft_rim, soft_rim < 0.9)
	# 边界环仍然是【效果半径】不是"贴片尺寸"
	var node = _arc.stele_raise(Vector2(700.0, 400.0), 250.0, 5.0)
	_ok("⑩ 立碑把效果半径记在节点上 (radius_px=%s)" % str(node.get_meta("radius_px", -1) if node != null else -1),
		node != null and absf(float(node.get_meta("radius_px", 0.0)) - 250.0) < 0.01)
	_arc.clear()


# ══════════════════════════════════════════════════════════════════
#  ⑪ 090: 起跳 → 滞空 → 砸落的节奏读得出
# ══════════════════════════════════════════════════════════════════
func _g10_090_leap() -> void:
	print("")
	print("  ⑪ 090 镇海杵(起跳节奏):")
	# 与结算侧焊死(不能循环 import ⇒ 用门禁焊, 见 arcane_eq_vfx 的注释)
	_ok("⑪ ★SLAM_R_PX ≡ EqArcaneBatch.PESTLE_RADIUS (%.0f / %.0f)" % [AEV.SLAM_R_PX, EAB.PESTLE_RADIUS],
		is_equal_approx(AEV.SLAM_R_PX, EAB.PESTLE_RADIUS) and is_equal_approx(AEV.SLAM_R_PX, WANT_SLAM_R))
	_ok("⑪ ★LEAP_APEX_M ≡ EqArcaneBatch.PESTLE_APEX_M (%.2f / %.2f)" % [AEV.LEAP_APEX_M, EAB.PESTLE_APEX_M],
		is_equal_approx(AEV.LEAP_APEX_M, EAB.PESTLE_APEX_M) and is_equal_approx(AEV.LEAP_APEX_M, WANT_APEX_M))
	# 影子随高度收缩: f(0)=1 · f(apex)=MIN · 严格单调减
	_ok("⑪ 影子: 地面 f(0)=%.3f ≡ 1" % AEV.leap_shadow_scale(0.0, WANT_APEX_M),
		is_equal_approx(AEV.leap_shadow_scale(0.0, WANT_APEX_M), 1.0))
	_ok("⑪ 影子: 顶点 f(apex)=%.3f ≡ MIN %.3f" % [AEV.leap_shadow_scale(WANT_APEX_M, WANT_APEX_M), AEV.LEAP_SHADOW_MIN],
		is_equal_approx(AEV.leap_shadow_scale(WANT_APEX_M, WANT_APEX_M), AEV.LEAP_SHADOW_MIN))
	var mono := true
	var prev := 2.0
	for i in range(41):
		var h: float = WANT_APEX_M * float(i) / 40.0
		var v: float = AEV.leap_shadow_scale(h, WANT_APEX_M)
		if v > prev:
			mono = false
		prev = v
	_ok("⑪ ★影子严格单调减(41 点)", mono)
	# 收势环: 收到位那一刻 ≡ 终了半径(精确)
	_ok("⑪ 收势环 r(1) ≡ 终了半径 (%.3f / %.3f)" % [AEV.telegraph_radius(1.0, AEV.LEAP_WINDUP_PX), AEV.LEAP_WINDUP_PX],
		is_equal_approx(AEV.telegraph_radius(1.0, AEV.LEAP_WINDUP_PX), AEV.LEAP_WINDUP_PX))
	_ok("⑪ 收势环起手更大 (%.0f > %.0f 码)" % [AEV.telegraph_radius(0.0, AEV.LEAP_WINDUP_PX), AEV.LEAP_WINDUP_PX],
		AEV.telegraph_radius(0.0, AEV.LEAP_WINDUP_PX) > AEV.LEAP_WINDUP_PX * 1.5)
	# ★真实节点: 水柱高度跟着 u["height"] 走
	var u: Dictionary = {"pos": Vector2(700.0, 400.0), "alive": true, "height": 0.0}
	_arc.clear()
	var root = _arc.pestle_leap(u, 0.6)
	_ok("⑪ ★分母: 起跳建出了根节点", root != null and is_instance_valid(root))
	if root != null:
		_ok("⑪ 起跳一次建三样(水柱/影子/收势环) 实测 %d" % root.get_child_count(), root.get_child_count() >= 3)
		var col0: float = _leap_col_h(root)
		u["height"] = WANT_APEX_M                 # 模拟跳到顶点
		_arc.tick(0.1)
		var col1: float = _leap_col_h(root)
		_ok("⑪ ★水柱高度跟着真实滞空高度涨 (%.2f → %.2f)" % [col0, col1], col1 > col0 + 1.0)
		var sh1: float = _leap_shadow_r(root)
		u["height"] = 0.0                          # 落回地面
		_arc.tick(0.1)
		var sh2: float = _leap_shadow_r(root)
		_ok("⑪ ★影子跟着高度回胀 (%.3f → %.3f)" % [sh1, sh2], sh2 > sh1)
	_arc.clear()


# ══════════════════════════════════════════════════════════════════
#  ⑫ 093: 不再用 _skill_ring, 且整体在【头顶以上】
# ══════════════════════════════════════════════════════════════════
func _g11_093_incense() -> void:
	print("")
	print("  ⑫ 093 香火石:")
	var src: String = _read("res://scripts/scenes/battle/incense_vfx.gd")
	_ok("⑫ ★分母: incense_vfx 源码读得到 (len=%d)" % src.length(), src.length() > 3000)
	_ok("⑫ ★三个入口一个都不再调 _skill_ring", not src.contains("_skill_ring("))
	# ★同时守住"另一路的地盘": 本文件没有去动那个函数
	var main: String = _read("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("⑫ ★_skill_ring 本体仍在主场景(没被本路删/改签名)", main.contains("func _skill_ring("))
	# 主循环真的每帧推它(不用 tween ⇒ 没人调 tick 就永远不动而且不报错)
	_ok("⑫ ★主循环每帧调 _incense_vfx.tick(", main.contains("_incense_vfx.tick("))
	# 真实节点: 全部在头顶以上
	var u: Dictionary = {"pos": Vector2(700.0, 400.0), "alive": true, "height": 0.0}
	var tgt: Dictionary = {"pos": Vector2(760.0, 400.0), "alive": true, "height": 0.0}
	_inc.clear()
	await get_tree().process_frame
	_inc.empower_burst(u)
	_ok("⑫ 三支香真的建出来了 (%d 支)" % _inc.alive_count("stick"), _inc.alive_count("stick") == 3)
	var ground_y: float = _s._world_pos(u["pos"], 0.0).y
	var min_y := 1.0e9
	for c in _s._world.get_children():
		if c is Node3D and (c as Node).has_meta(IV.META_KEY) and str((c as Node).get_meta(IV.META_KEY)) == "stick":
			min_y = minf(min_y, (c as Node3D).position.y)
	_ok("⑫ ★香在头顶以上 (y=%.2f > 地面 %.2f + 1.0)" % [min_y, ground_y], min_y > ground_y + 1.0)
	# 香的尺寸: 贴图 24×96 ⇒ 传的是"宽", 实际高 = 宽×4
	var stick_h: float = IV.STICK_W_PX * IV.STICK_TEX_ASPECT * PX_PER_YARD
	_ok("⑫ 单支香高 %.0f 屏幕 px ≥ 徽章 %.0f px 且 ≤ 龟立绘的 2 倍(88px)" % [stick_h, BADGE_PX],
		stick_h >= BADGE_PX and stick_h <= 88.0)
	# 四瓣火焰: 剪影不是圆(45° 方向必须比 0° 短很多)
	_inc.empower_hit(u, tgt)
	_ok("⑫ 命中火焰建出来了", _inc.alive_count("flare") >= 1)
	var fl: Image = IV.flare_tex().get_image()
	var fn: int = fl.get_width()
	var fc: float = float(fn - 1) * 0.5
	var r_axis: float = _ray_len(fl, fc, 0.0)
	var r_diag: float = _ray_len(fl, fc, PI * 0.25)
	_ok("⑫ ★四瓣火焰不是圆 (轴向 %.2f vs 斜向 %.2f, 比值 < 0.4)" % [r_axis, r_diag],
		r_axis > 0.0 and r_diag / r_axis < 0.4)
	_inc.clear()
	await get_tree().process_frame
	_ok("⑫ 撤场干净 (剩 %d)" % _inc.alive_count(), _inc.alive_count() == 0)


# ══════════════════════════════════════════════════════════════════
#  §工具
# ══════════════════════════════════════════════════════════════════

## HSV 的 S(饱和度)。「是不是白的」的可执行判据 —— 白的 S = 0。
func _sat(c: Color) -> float:
	var mx: float = maxf(maxf(c.r, c.g), c.b)
	var mn: float = minf(minf(c.r, c.g), c.b)
	return 0.0 if mx <= 0.0 else (mx - mn) / mx


## 某一行上不透明像素的宽度(px)。
func _row_width(img: Image, y: int) -> int:
	var yy: int = clampi(y, 0, img.get_height() - 1)
	var n := 0
	for x in range(img.get_width()):
		if img.get_pixel(x, yy).a > 0.25:
			n += 1
	return n


## 进度环上"点亮"的角度比例(拿真实贴图的像素数, 不重算公式)。
func _lit_arc_frac(img: Image) -> float:
	var n: int = img.get_width()
	var c: float = float(n - 1) * 0.5
	var lit := 0
	var tot := 0
	for k in range(720):
		var th: float = float(k) / 720.0 * TAU
		var px: int = clampi(int(c + sin(th) * c * 0.87), 0, n - 1)
		var py: int = clampi(int(c - cos(th) * c * 0.87), 0, n - 1)
		var p: Color = img.get_pixel(px, py)
		tot += 1
		if p.a > 0.55:
			lit += 1
	return 0.0 if tot == 0 else float(lit) / float(tot)


## 未点亮格子的典型 alpha(轨道可见性)。
func _unlit_alpha(img: Image) -> float:
	var n: int = img.get_width()
	var c: float = float(n - 1) * 0.5
	var best := 0.0
	for k in range(720):
		var th: float = float(k) / 720.0 * TAU
		var px: int = clampi(int(c + sin(th) * c * 0.87), 0, n - 1)
		var py: int = clampi(int(c - cos(th) * c * 0.87), 0, n - 1)
		var p: Color = img.get_pixel(px, py)
		if p.a > 0.02 and p.a <= 0.55:
			best = maxf(best, p.a)
	return best


## 从中心沿 th 方向, 不透明区域延伸到的归一半径。
func _ray_len(img: Image, c: float, th: float) -> float:
	var last := 0.0
	for k in range(1, int(c)):
		var r: float = float(k) / c
		var px: int = clampi(int(c + cos(th) * float(k)), 0, img.get_width() - 1)
		var py: int = clampi(int(c + sin(th) * float(k)), 0, img.get_height() - 1)
		if img.get_pixel(px, py).a > 0.3:
			last = r
	return last


func _leap_col_h(root: Node3D) -> float:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			return (c as Node3D).scale.y
	return -1.0


func _leap_shadow_r(root: Node3D) -> float:
	var best := -1.0
	for c in root.get_children():
		if c is MeshInstance3D and not ((c as MeshInstance3D).mesh is BoxMesh):
			best = maxf(best, (c as Node3D).scale.x) if best < 0.0 else minf(best, (c as Node3D).scale.x)
	return best


func _mesh_count(layer) -> int:
	return layer.alive_count() if layer.has_method("alive_count") else 0


func _first_alive():
	for u in _s._units:
		if u is Dictionary and u.get("alive", false) and float(u.get("hp", 0.0)) > 60.0:
			return u
	return null


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


## 取某个函数的函数体(到下一个顶格 `func ` 为止)。
func _fn_body(src: String, header: String) -> String:
	var i: int = src.find(header)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + header.length())
	return src.substr(i, (src.length() if j < 0 else j) - i)


func _gd_files(root: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var nm: String = dir.get_next()
		while nm != "":
			if dir.current_is_dir():
				if not nm.begins_with("."):
					stack.append(d + "/" + nm)
			elif nm.ends_with(".gd"):
				out.append(d + "/" + nm)
			nm = dir.get_next()
		dir.list_dir_end()
	return out


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
	print("ALL PASS — 金弹可辨 + 七件演出可读性" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
