extends Node
## verify_heal_burst.gd — 019 海葵药膏【治疗绿光 + 绿粒子】的门禁 (2026-09-12)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来 —— 用户原话钉在这里
## ════════════════════════════════════════════════════════════════════════
## 看 019 的窗口之后:「**应该要身上冒绿光和绿粒子，但不要复用**」
##
## 被否的是「治疗只有脚下一圈淡绿地环 + 一个飘字」——
## **治疗这个动作在画面上读不出来**(和 015 的反伤同类: 文案写了、画面读不出)。
##
## ★★然后我立刻犯了第二个错: 把它挂到 `battle_damage._heal_flush()`
##   ——`_heal` 全仓 **80 个调用点**的中央收口, 等于全游戏所有治疗一起换演出。他当场否:
##     「**我只让你对019做这次的绿光和绿粒子，你不对把其他的也全用了吧**」
##   ⇒ 下面 ⑤ 那条判据就是**专门防这个复发的**, 而且它不是源码字串匹配 ——
##     它真的走一遍 `_heal` + `_heal_flush`, 断言**没有**光束被生出来。
##
## ── 判据怎么定的 ────────────────────────────────────────────────────────
## 全部量**真实产出**: 调完 `heal_burst` 从 `_world` 里捞新建的 Sprite3D,
## 读它贴图里的真实像素、读 `pixel_size`、读材质的混合模式、手推它自己的 tween。
##
## ★「加色下颜色必须够暗」这条判据是 1:1 实拍逼出来的:
##   第一版素材用 `jade` 板(主色 110,200,148, 亮度 167), 加色叠上去**屏幕上读成一排白针**,
##   连是不是绿的都看不出。加色是"往背景上加", 源越亮越快冲到 255。
##   ⇒ 另立 `heal` 板(主色 36,178,112, 亮度 128)。判据卡在**亮度 ≤ 160**, 正好把 jade 判红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## ★实测常数(染色法量的, 不是产品里的常量): 台子镜头下一个屏幕像素 = 多少米。
const M_PER_SCREEN_PX := 0.0426
const PS_TOL := 0.15
## 加色层的主色亮度上限(jade 主色 167 会被这条判红, heal 主色 128 过)
const ADD_LUMA_MAX := 160.0
## 药滴至少要往上飘这么多米(**绝对值**, 不许拿产品常量算 —— 那是恒真式)
const DROP_RISE_MIN_M := 0.50

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _new_sprites(f: Callable) -> Array:
	var before: Array = []
	for c in _s._world.get_children():
		before.append(c)
	f.call()
	var out: Array = []
	for c in _s._world.get_children():
		if c is Sprite3D and not before.has(c):
			out.append(c)
	return out


func _grab_tweens(before: Array) -> Array:
	var out: Array = []
	for t in _s.get_tree().get_processed_tweens():
		if t is Tween and (t as Tween).is_valid() and not before.has(t):
			(t as Tween).pause()
			out.append(t)
	return out


func _step(tws: Array, dt: float) -> void:
	for t in tws:
		if is_instance_valid(t) and (t as Tween).is_valid():
			(t as Tween).custom_step(dt)


## 返回 [主色 r, g, b, 主色占比, 不透明像素数, 实体填充率(实体/包围盒)]
func _stats(tex: Texture2D, frames: int) -> Array:
	var img: Image = tex.get_image()
	var cnt: Dictionary = {}
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a < 0.5:
				continue
			opaque += 1
			var c: Color = img.get_pixel(x, y)
			var key := "%d_%d_%d" % [int(round(c.r8)), int(round(c.g8)), int(round(c.b8))]
			cnt[key] = int(cnt.get(key, 0)) + 1
	var top_key := ""
	var top_n := 0
	for k in cnt.keys():
		if int(cnt[k]) > top_n:
			top_n = int(cnt[k]); top_key = str(k)
	var p: PackedStringArray = top_key.split("_")
	## 第 0 格的实体填充率(圆的高、带尖芒的低)
	var cell: int = int(img.get_width() / maxi(1, frames))
	var bx0 := 9999
	var bx1 := -1
	var by0 := 9999
	var by1 := -1
	var solid := 0
	for y2 in range(img.get_height()):
		for x2 in range(cell):
			if img.get_pixel(x2, y2).a >= 0.5:
				solid += 1
				bx0 = mini(bx0, x2); bx1 = maxi(bx1, x2)
				by0 = mini(by0, y2); by1 = maxi(by1, y2)
	var box: int = maxi(1, (bx1 - bx0 + 1) * (by1 - by0 + 1))
	return [int(p[0]), int(p[1]), int(p[2]), float(top_n) / float(maxi(1, opaque)),
			opaque, float(solid) / float(box), cell]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 019 治疗: 身上冒绿光 + 绿粒子(只有 019) ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	## 合成一只干净单位(别拿随机 spawn 的, memory fb-ci-vs-local-divergence)
	var u: Dictionary = {
		"pos": Vector2(700.0, 400.0), "alive": true, "hp": 300.0, "maxHp": 1000.0,
		"height": 0.0, "shield": 0.0, "eq_state": {}, "equips": [],
	}

	var tw_before: Array = []
	for t in _s.get_tree().get_processed_tweens():
		tw_before.append(t)
	var sps: Array = _new_sprites(func() -> void: _s._vfx.heal_burst(u))
	var tws: Array = _grab_tweens(tw_before)

	# ── ① ★分母: 光束 + 粒子都生出来了 ────────────────────────────────
	_ok("① ★分母: heal_burst 往 _world 里生出了 %d 个 Sprite3D" % sps.size(),
		sps.size() >= 6, "1 束光 + 至少 5 粒药滴")
	if sps.size() < 6:
		_done(); return
	## 光束 = 唯一带 material_override 的那个(它要设 BLEND_MODE_ADD)
	var plume: Sprite3D = null
	var drops: Array = []
	for sp in sps:
		if (sp as Sprite3D).material_override != null:
			plume = sp as Sprite3D
		else:
			drops.append(sp)
	_ok("① ★分母: 认出了光束(带覆盖材质)与 %d 粒药滴" % drops.size(),
		plume != null and drops.size() >= 5)
	if plume == null or drops.size() < 5:
		_done(); return

	# ── ② 绿光: 加色 + 主色是绿的 + 够暗(加色下亮色必洗白) ───────────────
	var mat: StandardMaterial3D = plume.material_override as StandardMaterial3D
	_ok("② ★分母: 光束的覆盖材质是 StandardMaterial3D", mat != null)
	if mat != null:
		_ok("② ★★光束用【加色】混合 —— 加色下暗像素不贡献, 光叠在龟身上=龟被照亮, 黑背景仍黑",
			mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD)
	var ps: Array = _stats(plume.texture, plume.hframes)
	var pr: int = int(ps[0])
	var pg: int = int(ps[1])
	var pb: int = int(ps[2])
	var luma: float = 0.299 * float(pr) + 0.587 * float(pg) + 0.114 * float(pb)
	_ok("② 光束主色是绿的(实得 rgb(%d,%d,%d), g-r=%d, g-b=%d)" % [pr, pg, pb, pg - pr, pg - pb],
		pg - pr >= 80 and pg - pb >= 30)
	_ok("② ★★加色层主色必须够暗: 亮度 %.0f ≤ %.0f —— jade 主色亮度 167 会被这条判红"
		% [luma, ADD_LUMA_MAX], luma <= ADD_LUMA_MAX)
	_ok("② 光束主色占比够高(实得 %.0f%%)" % (float(ps[3]) * 100.0), float(ps[3]) >= 0.30)

	# ── ③ 1 texel : 1 屏幕像素(治「贴图被压」那条) ─────────────────────
	_ok("③ ★★光束 pixel_size ≈ 一个屏幕像素的世界尺寸(实得 %.4f / 应 %.4f)"
		% [plume.pixel_size, M_PER_SCREEN_PX],
		absf(plume.pixel_size - M_PER_SCREEN_PX) <= M_PER_SCREEN_PX * PS_TOL,
		"贴图一格 %d px" % int(ps[6]))
	var d0: Sprite3D = drops[0]
	var ds: Array = _stats(d0.texture, d0.hframes)
	_ok("③ ★★药滴 pixel_size ≈ 一个屏幕像素(实得 %.4f / 应 %.4f)"
		% [d0.pixel_size, M_PER_SCREEN_PX],
		absf(d0.pixel_size - M_PER_SCREEN_PX) <= M_PER_SCREEN_PX * PS_TOL,
		"贴图一格 %d px" % int(ds[6]))
	_ok("③ 光束与药滴都用 NEAREST(像素风不许双线性)",
		plume.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
		and d0.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)

	# ── ④ 「不要复用」: 药滴不是 014 汲取那颗四芒星 ────────────────────
	## ★判据落在**形状**上而不是文件名(文件名不同是随手就能满足的):
	##   圆药滴的实体填充率高(实测 0.81), 四芒星低(实测 0.40) —— 尖芒之间全是空。
	var lm: Texture2D = load("res://assets/sprites/vfx/life-mote.png")
	_ok("④ ★分母: 拿得到 014 的汲取粒子当对照", lm != null)
	_ok("④ ★★药滴是【圆】的不是四芒星: 实体填充率 %.2f ≥ 0.60" % float(ds[5]),
		float(ds[5]) >= 0.60, "014 那颗四芒星实测 0.40")
	if lm != null:
		var ls: Array = _stats(lm, 4)
		_ok("④ 两者主色不同(治疗 rgb(%d,%d,%d) / 汲取 rgb(%d,%d,%d))"
			% [int(ds[0]), int(ds[1]), int(ds[2]), int(ls[0]), int(ls[1]), int(ls[2])],
			int(ds[0]) != int(ls[0]) or int(ds[1]) != int(ls[1]) or int(ds[2]) != int(ls[2]))

	# ── ⑤ ★★范围只有 019: 普通治疗【不】该冒绿光 ──────────────────────
	## 这一条是防我自己复发的。我一度把 heal_burst 挂在 `_heal_flush`(全仓 80 个治疗点的
	## 中央收口), 被用户当场否。判据**不是**扫源码字串(那是假判据),
	## 而是真走一遍 `_heal` + `_heal_flush`, 断言没有光束被生出来。
	var v: Dictionary = {
		"pos": Vector2(900.0, 400.0), "alive": true, "hp": 200.0, "maxHp": 1000.0,
		"height": 0.0, "shield": 0.0, "eq_state": {}, "equips": [],
	}
	var leaked: Array = _new_sprites(func() -> void:
		_s._damage._heal(v, 120.0)
		v["_heal_acc_t"] = -99.0            # 让累加器立刻到点, 真的走一遍弹绿字那条路
		_s._damage._heal_flush(v)
	)
	var leaked_plume := 0
	for sp2 in leaked:
		if (sp2 as Sprite3D).material_override != null:
			leaked_plume += 1
	_ok("⑤ ★分母: 那次普通治疗真的进了结算(血量 200 → %.0f)" % float(v["hp"]),
		float(v["hp"]) > 200.0)
	_ok("⑤ ★★普通治疗【不】冒绿光(实得光束 %d 个, 应 0) —— 范围只有 019, 不是全游戏"
		% leaked_plume, leaked_plume == 0,
		"我一度挂到 _heal_flush, 被用户当场否")

	# ── ⑥ 治淡出病 + 药滴真的往上飘 ───────────────────────────────────
	## ★★起点必须在【推 tween 之前】取。第一版我先推了 0.27 秒量 alpha, 再去取药滴起点 ——
	##   那时药滴已经飞了 77% 的路, 于是「涨了多少」量出来只有 0.19 m 而判据要 0.55 m,
	##   门禁报红而产品是对的。**判据自己的锚点错了, 不是被测对象错。**
	var y0: float = d0.position.y
	var a0: float = plume.modulate.a
	_step(tws, BattleVfx.HEAL_PLUME_HOLD * 0.9)
	_ok("⑥ ★★满亮段 alpha 不降(出生 %.2f → hold 末 %.2f) —— 一出生就淡是被治的那个病"
		% [a0, plume.modulate.a], plume.modulate.a >= a0 - 0.02)
	_step(tws, BattleVfx.HEAL_DROP_T * 0.85)
	if is_instance_valid(d0):
		## ★★阈值必须是【绝对值】, 不能拿 HEAL_DROP_RISE 自己算 —— 那就是恒真式:
		##   把常量改小, 阈值跟着变小, 门禁照样绿(反向验证 M5 当场抓到: 改成 2 码也没红)。
		##   0.50 m ≈ 12 屏幕像素 ≈ 1/4 个龟高; 低于这个数屏幕上读不出「往上飘」。
		_ok("⑥ 药滴往【上】飘(y %.2f → %.2f, 涨了 %.2f m, 至少 %.2f m)"
			% [y0, d0.position.y, d0.position.y - y0, DROP_RISE_MIN_M],
			d0.position.y - y0 >= DROP_RISE_MIN_M)
	else:
		_ok("⑥ 药滴在量之前就被销毁了", false)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 15:
		print("  [FAIL] ★断言只有 %d 条(<15) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 019 治疗绿光" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
