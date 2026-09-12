extends Node
## verify_true_fire.gd — 022 余烬燃油瓶【真火】的门禁 (2026-09-12)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来 —— 用户原话钉在这里
## ════════════════════════════════════════════════════════════════════════
## 「**022只需要做一个真火的特效**」「**真火是个buff你明白吗**」「**去网上找燃烧例子**」
##
## ⇒ 真火是**挂在目标身上的状态**(EquipSystem.EMBER_TRUEFIRE_SEC = 5 秒),
##   不是命中那一下的爆点。在此之前画面上**完全没有表现** —— 只有灼烧飘字从蓝变白。
##   所以这套门禁量的是三件事: **挂上了没 / 是不是持续循环 / 到点撤没撤**,
##   外加素材本身长得像不像火。
##
## ── 参考 ────────────────────────────────────────────────────────────────
## `5db7V-YGslo`「Burning knight - Real time VFX (UE5)」, **上传 2026-02-20**。
## ★★先看上传日期: 上一件(021)我拿了 2013 年的视频当基准, 被用户当场抓。
##
## 实测(扣背景, 同一把尺子):
##   火高/角色高 1.5~1.7 · 火宽/角色高 1.6~2.1
##   填充率(火占包围盒) **0.44** · 亮度内/外(离边3px vs 0px) **1.26**(芯亮边暗)
##   单段宽(横扫描线游程, 按面积加权) 38.2px / 火高 149 = **0.256** ⇒ 80 格里 20.5 texel
##   连通块 38 个, **82% 是 ≤12px 的碎火星**
##
## ★★我在这一件上连烤废四版, 每一版的病都写进 tools/blender_truefire.py 头注:
##   ①实心橙板 ②细树枝 ③**一丛橙色的草**(它真进了游戏, 实拍才看出来) ④光滑面条+水洼。
##   ⇒ 判据落在**能把这四版判红**的量上: 分档、填充率、宽高比、循环, 不是「有没有贴图」。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ES := preload("res://scripts/systems/equip/equip_system.gd")
const TEX := "res://assets/sprites/vfx/true-fire.png"

## 实测常数(染色法量的): 台子镜头下 1 屏幕像素 = 多少米
const M_PER_SCREEN_PX := 0.0426
## 龟高(TARGET_BODY_H)
const TURTLE_H := 2.0

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 022 真火: 挂在目标身上的持续燃烧状态 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	var u: Dictionary = {
		"pos": Vector2(600.0, 400.0), "alive": true, "hp": 500.0, "maxHp": 1000.0,
		"height": 0.0, "eq_state": {}, "equips": [],
	}
	## 产品里怎么设的, 这里就怎么设(_fuel_bottle_hit 紧挨着这一行调 true_fire_aura)
	u["true_fire_until"] = _s._t + ES.EMBER_TRUEFIRE_SEC
	var n0: int = _s._follow_vfx.size()
	_s._vfx.true_fire_aura(u)

	# ── ① ★分母: 真的挂上了 ──────────────────────────────────────────
	var spr = u.get("_truefire_spr", null)
	_ok("① ★分母: true_fire_aura 在目标身上建出 Sprite3D", spr is Sprite3D and is_instance_valid(spr))
	_ok("① ★分母: 它进了 _follow_vfx(会跟着单位走)", _s._follow_vfx.size() == n0 + 1,
		"实得 %d → %d" % [n0, _s._follow_vfx.size()])
	if not (spr is Sprite3D) or _s._follow_vfx.size() != n0 + 1:
		_done(); return
	var f: Dictionary = _s._follow_vfx[_s._follow_vfx.size() - 1]

	# ── ② ★★是【持续循环】不是放一遍就完 ──────────────────────────
	## 被否的形状是「命中那一下闪一个爆点」。真火是 buff, 必须一直烧到状态结束。
	_ok("② ★★循环播放(loop_fps), 不是 anim_fps 的一次性动画",
		f.has("loop_fps") and not f.has("anim_fps"))
	_ok("② 循环帧数 = 贴图帧数 %d" % int(f.get("loop_n", 0)),
		int(f.get("loop_n", 0)) == int(spr.hframes) and int(spr.hframes) >= 4,
		"loop_n %d / hframes %d" % [int(f.get("loop_n", 0)), int(spr.hframes)])
	## ★到期判据必须读**单位身上那个时间字段**, 不许另起第二条计时
	##   (memory [[fb-second-clock-drops-events]]: 两条钟必然丢事件)
	_ok("② ★到期读的是单位的 true_fire_until, 不是自己另起的钟",
		str(f.get("until_key", "")) == "true_fire_until")

	# ── ③ ★★到点自己撤 ────────────────────────────────────────────
	## 直接推进游戏钟再喂一次跟随 tick —— 不等 tween(CLAUDE.md §3.5)
	_s._render._tick_follow_vfx()
	_ok("③ ★分母: 没到期时【还在】(推了一次 tick 也不许消失)",
		is_instance_valid(u.get("_truefire_spr", null)) and _s._follow_vfx.size() == n0 + 1)
	_s._t = float(u["true_fire_until"]) + 0.01
	_s._render._tick_follow_vfx()
	_ok("③ ★★过了 %.0f 秒就撤(Sprite 销毁 + 字段清掉)" % ES.EMBER_TRUEFIRE_SEC,
		_s._follow_vfx.size() == n0 and not u.has("_truefire_spr"),
		"follow_vfx %d(应 %d) / 还留着 _truefire_spr: %s" % [
			_s._follow_vfx.size(), n0, str(u.has("_truefire_spr"))])

	# ── ④ ★★尺寸照实测(火把目标整个吞掉) ──────────────────────────
	var tex: Texture2D = load(TEX)
	_ok("④ ★分母: 贴图载得到(换了 png 没 --import 会返回 null)", tex != null)
	if tex == null:
		_done(); return
	var cell: int = int(tex.get_width()) / maxi(1, int(spr.hframes))
	## ★★量的必须是**露出地面的火**, 不是【贴图格子有多高】。
	##   第一版量 cell × pixel_size = 3.41 m 恒定 —— 贴图整个沉到地下它也一样绿。
	##   实际就出过这个事: TRUEFIRE_H 拍成 1.30 ⇒ 火底在脚下 -0.404 m,
	##   露出地面的只有 1.33~1.42 龟高(低于参考 1.5~1.7), 而这条判据全程绿。
	##   现在从**真实 Sprite3D 的 AABB** 取底/顶, 底被地面切掉的部分不算数。
	var _ab: AABB = spr.get_aabb()
	var _foot: float = _s._world_pos(u["pos"] as Vector2, 0.0).y
	var _bot: float = spr.position.y + _ab.position.y - _foot
	var _top: float = _bot + _ab.size.y
	var _vis: float = _top - maxf(_bot, 0.0)
	_ok("④ ★★火底齐脚: 离脚 %+.3f m(容差 ±0.06)" % _bot, absf(_bot) <= 0.06,
		"负数=埋进地里(黑场台子上看不出来, 真实地图/被击飞时会穿地)")
	## ★AABB 是**整个贴图方片**(3.41 m), 不是画到的火 —— 拿它报「火多高」是虚的。
	##   用贴图里**真的画到的行**把方片顶往下切, 才是火本身。
	var _img0: Image = tex.get_image()
	var _rowtop: int = 1 << 30
	var _rowbot: int = -1
	for _y in range(_img0.get_height()):
		for _x in range(_img0.get_width()):
			if _img0.get_pixel(_x, _y).a >= 0.5:
				_rowtop = mini(_rowtop, _y); _rowbot = maxi(_rowbot, _y); break
	var _ftop: float = _top - float(_rowtop) * spr.pixel_size
	var _fbot: float = _top - float(_rowbot + 1) * spr.pixel_size
	var _fvis: float = _ftop - maxf(_fbot, 0.0)
	_ok("④ ★★露出地面的火 = %.2f 龟高(参考实测 1.5~1.7)" % (_fvis / TURTLE_H),
		_fvis / TURTLE_H >= 1.45 and _fvis / TURTLE_H <= 1.80,
		"火 %.2f~%.2f m(露出 %.2f m) / 龟高 %.1f m —— 沉下去多少这条就掉多少" % [_fbot, _ftop, _fvis, TURTLE_H])
	_ok("④ 1 texel : 1 屏幕像素(像素画不许非整数缩放)",
		absf(spr.pixel_size - M_PER_SCREEN_PX) < 0.004,
		"pixel_size %.4f / 应 %.4f" % [spr.pixel_size, M_PER_SCREEN_PX])
	_ok("④ 像素画用 NEAREST(LINEAR 会糊)",
		spr.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)

	# ── ⑤ ★★素材本身: 分档 + 形状 ────────────────────────────────
	var img: Image = tex.get_image()
	var cnt: Dictionary = {}
	var opaque := 0
	var semi := 0
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
	_ok("⑤ ★分母: 贴图里有不透明像素(实得 %d)" % opaque, opaque > 2000)
	_ok("⑤ 硬边: 没有半透明羽化像素(实得 %d)" % semi, semi == 0)
	## ★★分档: 第 3 版(那丛草)与量化前的第 4 版都只有 1~2 档 ⇒ 实拍是一张纯色剪影。
	_ok("⑤ ★★横截面分档 ≥3 档(实得 %d) —— 外焰/火体/亮芯" % cnt.size(), cnt.size() >= 3)
	## ★★主色不许太亮: 台子泛光会把亮色洗白(memory [[fb-vfx-defect-families]])。
	##   实拍验过两轮: 主色亮度 205 洗成奶白、166 还是奶油色、**119 才读成橙火**。
	var top_k := ""
	var top_v := 0
	for k in cnt.keys():
		if int(cnt[k]) > top_v:
			top_v = int(cnt[k]); top_k = str(k)
	var parts: PackedStringArray = top_k.split("_")
	var tl: float = 0.299 * float(parts[0]) + 0.587 * float(parts[1]) + 0.114 * float(parts[2])
	_ok("⑤ ★★主色亮度 %.0f ≤ 175(再亮就被泛光洗成奶白)" % tl, tl <= 175.0,
		"主色 (%s,%s,%s) 占 %.0f%%" % [parts[0], parts[1], parts[2], 100.0 * top_v / maxi(1, opaque)])

	# ── ⑥ ★★形状: 填充率与宽高比照实测 ──────────────────────────
	## 参考: 填充率 0.44 · 火宽/火高 ≈ 1.05~1.15。
	## 第 1 版(实心橙板)填充率接近 1.0、第 2 版(细树枝)只有 0.2 ⇒ 这一条把两头都拦住。
	var cw: int = cell
	var fill_sum := 0.0
	var ratio_sum := 0.0
	var frames: int = int(spr.hframes)
	for fi in range(frames):
		var x0 := 1 << 30
		var x1 := -1
		var y0 := 1 << 30
		var y1 := -1
		var solid := 0
		for y in range(img.get_height()):
			for x in range(fi * cw, (fi + 1) * cw):
				if img.get_pixel(x, y).a < 0.5:
					continue
				solid += 1
				x0 = mini(x0, x - fi * cw); x1 = maxi(x1, x - fi * cw)
				y0 = mini(y0, y); y1 = maxi(y1, y)
		if x1 < 0:
			continue
		fill_sum += float(solid) / float(maxi(1, (x1 - x0 + 1) * (y1 - y0 + 1)))
		ratio_sum += float(x1 - x0 + 1) / float(maxi(1, y1 - y0 + 1))
	var fill: float = fill_sum / float(maxi(1, frames))
	var ratio: float = ratio_sum / float(maxi(1, frames))
	_ok("⑥ ★★填充率 %.2f ≈ 参考 0.44(±0.14)" % fill, absf(fill - 0.44) <= 0.14,
		"实心板会到 ~1.0, 细树枝只有 ~0.2 —— 这一条把两头都拦住")
	_ok("⑥ ★宽/高 %.2f(参考 火宽1.6~2.1 / 火高1.5~1.7 ⇒ 1.0~1.3)" % ratio,
		ratio >= 0.80 and ratio <= 1.40)

	# ── ⑦ ★★逐帧都在动, 而且第 8 帧接得回第 1 帧(它是循环) ────────
	var diffs: Array = []
	for fi in range(frames):
		var nx: int = (fi + 1) % frames
		var d := 0
		for y in range(img.get_height()):
			for x in range(cw):
				var a1: bool = img.get_pixel(fi * cw + x, y).a >= 0.5
				var a2: bool = img.get_pixel(nx * cw + x, y).a >= 0.5
				if a1 != a2:
					d += 1
		diffs.append(d)
	var dmin: int = 1 << 30
	var dsum := 0
	for d in diffs:
		dmin = mini(dmin, int(d)); dsum += int(d)
	var davg: float = float(dsum) / float(maxi(1, diffs.size()))
	_ok("⑦ ★分母: 每一帧都和下一帧不同(最小帧间差 %d px)" % dmin, dmin > 100)
	## 收尾那一帧(第 8 → 第 1)的跳变不许明显大于平均 ⇒ 循环无缝
	var dlast: int = int(diffs[diffs.size() - 1])
	_ok("⑦ ★★循环无缝: 末帧→首帧的跳变 %d ≤ 平均 %.0f × 1.8" % [dlast, davg],
		float(dlast) <= davg * 1.8)

	# ── ⑧ 已经在烧就不重复挂(续时间由 true_fire_until 自己管) ──────
	var u2: Dictionary = {
		"pos": Vector2(700.0, 400.0), "alive": true, "hp": 500.0, "maxHp": 1000.0,
		"height": 0.0, "eq_state": {}, "equips": [],
	}
	u2["true_fire_until"] = _s._t + ES.EMBER_TRUEFIRE_SEC
	var m0: int = _s._follow_vfx.size()
	_s._vfx.true_fire_aura(u2)
	_s._vfx.true_fire_aura(u2)
	_ok("⑧ 同一只龟连调两次只挂一个(否则 5 秒里会叠出几十层)",
		_s._follow_vfx.size() == m0 + 1, "实得 +%d" % (_s._follow_vfx.size() - m0))


	# ── ⑨ ★★真入口: 产品里没人直接调 true_fire_aura ────────────────
	## 接线在 `battle_render._tick_true_fire()`: 它逐帧扫 `_units`, 谁身上
	## `true_fire_until` 还没过就给谁点上。**只断言 true_fire_aura 建得出 Sprite**
	## 守不住「还有没有人调它」(memory [[fb-verify-must-run-the-real-path]]:
	## 我曾对着一个零调用者的死函数报「目视确认新实现」)。
	## ⇒ 这里只写状态, 然后走**产品自己的那条 tick**, 看火起不起来。
	var u3: Dictionary = {
		"pos": Vector2(800.0, 400.0), "alive": true, "hp": 500.0, "maxHp": 1000.0,
		"height": 0.0, "eq_state": {}, "equips": [],
	}
	_s._units.append(u3)
	var k0: int = _s._follow_vfx.size()
	_s._render._tick_true_fire()
	_ok("⑨ ★分母: 没写 true_fire_until 时, 真入口**不**点火",
		_s._follow_vfx.size() == k0 and not u3.has("_truefire_spr"))
	u3["true_fire_until"] = _s._t + ES.EMBER_TRUEFIRE_SEC
	_s._render._tick_true_fire()
	_ok("⑨ ★★只写状态 + 走产品自己的 tick ⇒ 火自己起来了",
		is_instance_valid(u3.get("_truefire_spr", null)) and _s._follow_vfx.size() == k0 + 1,
		"follow_vfx %d → %d" % [k0, _s._follow_vfx.size()])
	_s._render._tick_true_fire()
	_ok("⑨ 再扫一遍不重复点(否则每帧叠一层)", _s._follow_vfx.size() == k0 + 1)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 24:
		print("  [FAIL] ★断言只有 %d 条(<24) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 022 真火" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
