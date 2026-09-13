extends Node
## verify_fire_coral_wave.gd — 023 灼热火珊瑚【火焰波】的门禁 (2026-09-13)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来 —— 文案就是规格
## ════════════════════════════════════════════════════════════════════════
## 023 effectDesc1:「主动(法力条集满时自动释放): 蓄力后朝敌方挥出一道**火焰波**,
##   在 {CORAL_ARC_DEG} 度扇形内**缓慢移动** {CORAL_TRAVEL} 码, 对扫过的敌人各施加
##   40/60/90 层灼烧」。
##
## ★★改之前那一版的三条硬伤(实拍 + 探针确诊, 这套门禁就是照它们配的):
##   ① 波是 `VfxTex._make_qi_texture()` **程序生成的气波**染橙 —— 复用别件的原语
##      (素材不复用铁律), 也不是像素画;
##   ② **没设 texture_filter** ⇒ 探针实测 Sprite3D 默认 `LINEAR_WITH_MIPMAPS`(=3);
##      而且每帧 `wave.scale = ...` **连续缩放** —— 像素风三条硬约束破了两条;
##   ③ 推进与判定都挂在 `get_process_delta_time()` 上 = **第二条钟**
##      (CLAUDE.md §3.5 / memory [[fb-second-clock-drops-events]])。
##
## ★★判据都落在**真实产出的 Sprite3D** 与**抽出来的结算函数**上,
##   不断言「我插的标记」(memory [[fb-gate-must-measure-requirement-not-my-hook]])。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")
const TEX := "res://assets/sprites/vfx/fire-crest.png"

## 实测常数(染色法): 台子镜头下 1 屏幕像素 = 多少米
const M_PER_SCREEN_PX := 0.0426

var _s = null
var _eq = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(px: float, py: float) -> Dictionary:
	return {
		"pos": Vector2(px, py), "alive": true, "hp": 9000.0, "maxHp": 9000.0,
		"height": 0.0, "eq_state": {}, "equips": [], "side": "right", "id": "basic",
		## ★字段要和 battle_spawn 造的真单位一致 —— 少一个 `dot_src`,
		##   `_apply_dot_stacks` 里写它那一行就抛 SCRIPT ERROR、函数**当场中止**,
		##   而断言照样绿(memory [[fb-null-readback-makes-test-silently-abort]])。
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0, "_dot_float": {},
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 023 火焰波: 60 度扇形里推出去的一排直立火簇 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_eq = _s._equip_sys

	# ── ① ★分母: 素材载得到, 且是像素画 ───────────────────────────
	var tex: Texture2D = load(TEX)
	_ok("① ★分母: fire-crest.png 载得到(换了 png 没 --import 会返回 null)", tex != null)
	if tex == null:
		_done(); return
	var img: Image = tex.get_image()
	var cell: int = int(img.get_width()) / maxi(1, ES.CORAL_CREST_FRAMES)
	_ok("① 一格是方的 %d×%d, 共 %d 帧" % [cell, img.get_height(), ES.CORAL_CREST_FRAMES],
		cell == img.get_height() and ES.CORAL_CREST_FRAMES >= 4)
	var cnt: Dictionary = {}
	var semi := 0
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.02 and c.a < 0.98:
				semi += 1
			if c.a < 0.5:
				continue
			opaque += 1
			var k := "%d_%d_%d" % [int(round(c.r8)), int(round(c.g8)), int(round(c.b8))]
			cnt[k] = int(cnt.get(k, 0)) + 1
	_ok("① ★分母: 贴图里有不透明像素(实得 %d)" % opaque, opaque > 500)
	_ok("① 硬边: 没有半透明羽化像素(实得 %d)" % semi, semi == 0)
	_ok("① ★横截面分档 ≥3 档(实得 %d) —— 外焰/火体/亮芯" % cnt.size(), cnt.size() >= 3)
	## ★主色不许太亮: 台子泛光会把亮色洗白(memory [[fb-vfx-defect-families]])
	var top_k := ""
	var top_v := 0
	for k in cnt.keys():
		if int(cnt[k]) > top_v:
			top_v = int(cnt[k]); top_k = str(k)
	var parts: PackedStringArray = top_k.split("_")
	var tl: float = 0.299 * float(parts[0]) + 0.587 * float(parts[1]) + 0.114 * float(parts[2])
	_ok("① ★主色亮度 %.0f ≤ 175(再亮就被泛光洗成奶白)" % tl, tl <= 175.0)

	# ── ② ★★摆出来的是真 Sprite3D, 而且【不转、不连续缩放】 ──────
	var carrier: Dictionary = _mk(500.0, 400.0)
	carrier["side"] = "left"
	var pool: Array = []
	var dir := Vector2.RIGHT
	_eq._fire_coral_place(pool, Vector2(500.0, 400.0), dir, 200.0, 0.0)
	_ok("② ★分母: 摆出了 Sprite3D(实得 %d 个)" % pool.size(),
		pool.size() >= 2 and pool[0] is Sprite3D)
	if pool.is_empty() or not (pool[0] is Sprite3D):
		_done(); return
	var bad_scale := 0
	var bad_rot := 0
	var bad_filter := 0
	var bad_px := 0
	for sp in pool:
		if not (sp is Sprite3D):
			continue
		if not sp.scale.is_equal_approx(Vector3.ONE):
			bad_scale += 1
		if absf(sp.rotation.x) + absf(sp.rotation.y) + absf(sp.rotation.z) > 0.001:
			bad_rot += 1
		if sp.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			bad_filter += 1
		if absf(sp.pixel_size - M_PER_SCREEN_PX) > 0.004:
			bad_px += 1
	_ok("② ★★没有连续缩放: scale 全是 1(违规 %d/%d)" % [bad_scale, pool.size()], bad_scale == 0,
		"上一版每帧 wave.scale = Vector3(2.2 + traveled/TRAVEL*4.5, ...) —— 这一条把它判红")
	_ok("② ★★贴片不许自由旋转(违规 %d/%d)" % [bad_rot, pool.size()], bad_rot == 0,
		"火焰永远朝上 ⇒ 一次都不用转; 转了就打烂像素网格")
	_ok("② ★★texture_filter 必须显式 NEAREST(违规 %d/%d)" % [bad_filter, pool.size()],
		bad_filter == 0, "★不设 = LINEAR_WITH_MIPMAPS(探针实测默认值 3), 硬边像素图会糊")
	_ok("② 1 texel : 1 屏幕像素(违规 %d/%d)" % [bad_px, pool.size()], bad_px == 0)

	# ── ③ ★★摆几簇是【算出来的整数】, 随距离涨 ────────────────────
	var near_pool: Array = []
	var far_pool: Array = []
	_eq._fire_coral_place(near_pool, Vector2(500.0, 400.0), dir, 80.0, 0.0)
	_eq._fire_coral_place(far_pool, Vector2(500.0, 400.0), dir, 520.0, 0.0)
	var n_near := 0
	var n_far := 0
	for sp in near_pool:
		if is_instance_valid(sp) and sp.visible:
			n_near += 1
	for sp in far_pool:
		if is_instance_valid(sp) and sp.visible:
			n_far += 1
	_ok("③ ★★波越远摆得越多(80 码 %d 簇 → 520 码 %d 簇)" % [n_near, n_far], n_far > n_near,
		"扇形的弧长随半径线性涨 ⇒ 用「多摆几个」代替「把一张图拉大」")
	_ok("③ 护栏: 最远也不超过 CORAL_CREST_MAX=%d" % ES.CORAL_CREST_MAX,
		n_far <= ES.CORAL_CREST_MAX, "实得 %d" % n_far)

	# ── ④ ★★几何: 全在 ±ARC/2 内, 且都落在波前那一圈上 ────────────
	var half: float = deg_to_rad(ES.CORAL_ARC_DEG * 0.5)
	var org3: Vector3 = _s._world_pos(Vector2(500.0, 400.0), ES.CORAL_CREST_H)
	var r_want: float = 520.0 * _s.WS
	var worst_r := 0.0
	var worst_a := 0.0
	for sp in far_pool:
		if not (is_instance_valid(sp) and sp.visible):
			continue
		var rel: Vector3 = sp.position - org3
		var flat := Vector2(rel.x, rel.z)
		worst_r = maxf(worst_r, absf(flat.length() - r_want))
		worst_a = maxf(worst_a, absf(flat.angle_to(Vector2(dir.x, dir.y))))
	_ok("④ ★★全都落在波前那一圈上(半径最大偏差 %.3f m, 上限 0.30)" % worst_r, worst_r <= 0.30,
		"应半径 %.2f m —— 「波在移动」不是「一排静态条依次点亮」" % r_want)
	_ok("④ ★★张角全在 ±%.0f° 内(实测最大 %.1f°)" % [ES.CORAL_ARC_DEG * 0.5, rad_to_deg(worst_a)],
		worst_a <= half + 0.02)

	# ── ⑤ ★★★伤害: 直调抽出来的结算函数, 不等演出 ────────────────
	## CLAUDE.md §3.5: 一个测「数值对不对」的用例, 不该依赖任何动画跑完。
	var inside: Dictionary = _mk(500.0 + 300.0, 400.0)          # 正前方 300 码
	## ★★位置必须【只被扇形这一条】挡住: 第一版放在 (600,800) —— 偏角 76° 没错,
	##   但它离原点 412 码而波前在 300 码, **波前带那一条也把它挡了** ⇒ 两个条件搅在一起,
	##   把扇形判定整条拆掉这条断言照样绿(反向验证 M4 当场抓到)。
	##   现在放在**同一半径 300 码**上、偏角 76° ⇒ 只有扇形能挡它。
	var outside_ang: Dictionary = _mk(572.58, 691.09)  # 半径 300 码 · 偏角 76°
	var outside_r: Dictionary = _mk(500.0 + 900.0, 400.0)       # 正前方但远在波前之外
	_s._units.append(carrier)
	_s._units.append(inside)
	_s._units.append(outside_ang)
	_s._units.append(outside_r)
	var hit: Array = []
	var got: int = _eq._fire_coral_wave_hit(carrier, Vector2(500.0, 400.0), dir, 300.0, hit, 2)
	_ok("⑤ ★分母: 波前扫到了人(实得 %d 个)" % got, got >= 1)
	_ok("⑤ ★★扇形内 + 波前带上的敌人吃到 %d 层灼烧" % ES.CORAL_BURN[2],
		int(inside["dot_stacks"].get("burn", 0)) == ES.CORAL_BURN[2],
		"实得 %d 层" % int(inside["dot_stacks"].get("burn", 0)))
	_ok("⑤ ★★扇形【外】的不吃(挡多了也是错)",
		int(outside_ang["dot_stacks"].get("burn", 0)) == 0,
		"实得 %d 层" % int(outside_ang["dot_stacks"].get("burn", 0)))
	_ok("⑤ ★★波前还没到的不吃(它是一道推进的波, 不是一次全场 AOE)",
		int(outside_r["dot_stacks"].get("burn", 0)) == 0,
		"实得 %d 层" % int(outside_r["dot_stacks"].get("burn", 0)))
	## 同一个人不许被同一道波打两次
	var again: int = _eq._fire_coral_wave_hit(carrier, Vector2(500.0, 400.0), dir, 300.0, hit, 2)
	_ok("⑤ 同一道波不重复命中(第二次扫到 %d 个)" % again, again == 0,
		"实得灼烧 %d 层(应还是 %d)" % [int(inside["dot_stacks"].get("burn", 0)), ES.CORAL_BURN[2]])
	## ★星级要吃到: 40/60/90
	var s1: Dictionary = _mk(500.0 + 300.0, 400.0)
	_s._units.append(s1)
	var hit1: Array = []
	_eq._fire_coral_wave_hit(carrier, Vector2(500.0, 400.0), dir, 300.0, hit1, 0)
	_ok("⑤ ★1 星是 %d 层不是 %d 层(2026-07-19 用户点名: 原来固定 60 不吃星级)"
		% [ES.CORAL_BURN[0], ES.CORAL_BURN[2]],
		int(s1["dot_stacks"].get("burn", 0)) == ES.CORAL_BURN[0],
		"实得 %d 层" % int(s1["dot_stacks"].get("burn", 0)))

	# ── ⑥ 火底齐地(022 那条教训: TRUEFIRE_H 拍成半格以外就埋进地里) ──
	var half_cell: float = float(cell) * 0.5 * M_PER_SCREEN_PX
	_ok("⑥ 火底齐地: 贴图中心 %.3f m = 半格 %.3f m(±0.05)" % [ES.CORAL_CREST_H, half_cell],
		absf(ES.CORAL_CREST_H - half_cell) <= 0.05)

	for sp in pool + near_pool + far_pool:
		if is_instance_valid(sp):
			sp.queue_free()
	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 20:
		print("  [FAIL] ★断言只有 %d 条(<20) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 023 火焰波" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
