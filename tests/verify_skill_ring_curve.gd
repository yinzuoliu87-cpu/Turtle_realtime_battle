extends Node
## verify_skill_ring_curve.gd — 共享 `_skill_ring` 原语的门禁
##
## ★★2026-09-11 整段重写。旧版守的是「尺寸与 alpha 必须是两条曲线」——
##   那是给**tween 连续放大**那套实现写的判据, 而那套实现**就是被否掉的东西本身**:
##     2026-08-09 看 095:「又是程序生成的环？哪个商业游戏是你这么做啊」
##     2026-09-11 看 012:「**为什么那个地面的东西糊弄啊**」
##   根因不是曲线错, 是 **tween 连续缩放像素贴图 = 非整数倍缩放 = 像素网格被打烂**
##   (tools/blender_ring.py:13 白纸黑字写着, 还抄了用户原话「最好不要程序弄吧」)。
##   ⇒ 现在是 **Blender 逐帧烤好的 10 帧扩散 + pixel_size 固定只切帧**(与 003 同一条路)。
##
## ── 新判据(每条都卡住新模型的一个要害) ──────────────────────────────
##   ① 分母: 世界节点在 · 常量自洽
##   ② ★★`pixel_size` **全程恒定** —— 这就是这次修的那个 bug。旧实现在这里是变的。
##      帧号随**游戏时钟**单调上升 · 放完从 `_anim_fx` 摘销并 queue_free。
##   ③ 几何没动: 末帧外径 == 调用点给的 radius(换算靠产品自己写在节点上的 ring_target_ps)
##   ④ 30 次调用全部自销(不残留)
##   ⑤ 贴图本身是像素画 —— **这一段原样保留**: `_make_ring_texture` 还有 16 处调用者
##      (瞄准线/HUD/出生环/羁绊/彩虹/火箭/龟壳/星星), 它们没跟着这次一起改。
##
## ⚠ 不许在测试里把公式再实现一遍跟自己比(恒真式) —— 分母 `ring_target_ps` 由产品代码
##   自己写在节点上, 测试只读不算。
## ⚠ 帧推进用**手动设 `battle._t` + 调真的 `_tick_anim_fx()`**, 不 await 真实时间:
##   无头 CI 下帧率极高, await 等多久都不确定(CLAUDE.md §3.5)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_skill_ring_curve.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const P := Vector2(700.0, 400.0)
## 推进步长(秒)。总时长 = 10 帧 / 21fps ≈ 0.48 秒。
const DT := 0.008

var _n := 0
var _fail := 0
var _s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== _skill_ring 共享原语: pixel_size 恒定 + 逐帧扩散 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame
	# 关掉战斗 _process: 本文件自己推帧, 不让 sim 每帧再造别的环进来干扰计数。
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	_g1_denominator()
	if not is_instance_valid(_s._world):
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	await _g2_frames()
	await _g3_geometry_unchanged()
	await _g4_other_callers_ok()
	await _g5_ring_is_pixel_art()
	await _done()


# ── ① ★分母 ─────────────────────────────────────────────────────────────────
func _g1_denominator() -> void:
	print("  ① 分母")
	_ok("① 世界节点 _world 在", is_instance_valid(_s._world))
	_ok("① 帧数/帧率/画布/末帧外径 四个常量自洽 (%d 帧 @%.0ffps · 画布 %.0fpx · 末帧外径 %.1fpx)"
		% [RB.RING_ANIM_FRAMES, RB.RING_ANIM_FPS, RB.RING_CELL_PX, RB.RING_LAST_R_PX],
		RB.RING_ANIM_FRAMES >= 4 and RB.RING_ANIM_FPS > 0.0
			and RB.RING_LAST_R_PX > 0.0 and RB.RING_LAST_R_PX <= RB.RING_CELL_PX * 0.5)
	_ok("① 峰值 alpha 在 (0,1](换它 = 全游戏 187 处一起变亮/变暗)",
		RB.RING_PEAK_A > 0.0 and RB.RING_PEAK_A <= 1.0)


# ── ② ★★新模型: pixel_size 恒定 + 帧号随游戏时钟走 + 放完自销 ──────────────
func _g2_frames() -> void:
	print("  ② 逐帧扩散(pixel_size 必须恒定)")
	var r: Sprite3D = _s._skill_ring(P, Color(1.0, 0.85, 0.4, 0.6), 60.0)
	if r == null or not is_instance_valid(r):
		_ok("② ★分母: _skill_ring 返回了真实节点", false); return
	_ok("② ★分母: _skill_ring 返回了真实节点", true)
	var target_ps: float = float(r.get_meta("ring_target_ps", 0.0))
	_ok("② ★分母: 节点自己写了 ring_target_ps(分母来自产品代码, 不是测试重算)", target_ps > 0.0)
	_ok("② ★分母: 它真的挂进了帧动画表(没挂 = 永远停在第 0 帧)",
		_ring_entry(r) != null)
	_ok("② ★分母: hframes 与素材帧数对得上", r.hframes == RB.RING_ANIM_FRAMES,
		"hframes=%d" % r.hframes)
	## 推: 手动设游戏时钟 + 调真的 `_tick_anim_fx()`
	var t0: float = _s._t
	var seen: Array = []
	var ps_seen: Array = []
	for step in range(RB.RING_ANIM_FRAMES):
		if not is_instance_valid(r):
			break
		## 落在每帧正中, 避开 float 边界(_wait_sim 那个刀口同族)
		_s._t = t0 + (float(step) + 0.5) / RB.RING_ANIM_FPS
		_s._render._tick_anim_fx()
		if is_instance_valid(r):
			seen.append(int(r.frame))
			ps_seen.append(float(r.pixel_size))
	var rising := true
	for i in range(1, seen.size()):
		if int(seen[i]) <= int(seen[i - 1]):
			rising = false
	_ok("② 帧号随游戏时钟单调上升 0…%d" % (RB.RING_ANIM_FRAMES - 1),
		seen.size() == RB.RING_ANIM_FRAMES and rising and int(seen[0]) == 0
			and int(seen[-1]) == RB.RING_ANIM_FRAMES - 1,
		"帧序列 %s" % str(seen))
	var ps_spread := 0.0
	for v in ps_seen:
		ps_spread = maxf(ps_spread, absf(float(v) - target_ps))
	## ★阈值用**相对**不用绝对: 写 <1e-9 时反向验证量到正好 1e-9 ⇒ 假红(float 刀口)。
	_ok("② ★★pixel_size 全程恒定(极差 %.9f) —— 连续缩放像素贴图正是被否掉的那个糊" % ps_spread,
		ps_spread <= target_ps * 1.0e-6 and ps_seen.size() == RB.RING_ANIM_FRAMES,
		"采到 %d 个值" % ps_seen.size())
	## 推过总时长: 从表里摘销 + 节点排队销毁
	_s._t = t0 + float(RB.RING_ANIM_FRAMES) / RB.RING_ANIM_FPS + 0.5
	_s._render._tick_anim_fx()
	_ok("② ★放完从帧动画表里摘销(否则每帧白跑一遍)", _ring_entry(r) == null)
	_ok("② ★放完节点排了销毁(不残留在场上)",
		(not is_instance_valid(r)) or r.is_queued_for_deletion())


## 量【贴图本身】末帧的外径(像素) —— 独立锚点, 不读产品常量。
func _last_frame_outer_r(tex: Texture2D) -> float:
	if tex == null:
		return -1.0
	var img: Image = tex.get_image()
	var cell: int = img.get_height()
	var k: int = RB.RING_ANIM_FRAMES - 1
	var c: float = float(cell - 1) * 0.5
	var best := 0.0
	for y in range(cell):
		for x in range(cell):
			if img.get_pixel(k * cell + x, y).a > 0.001:
				best = maxf(best, Vector2(float(x) - c, float(y) - c).length())
	return best


## 在 `_anim_fx` 里找这个精灵的那一条; 找不到返回 null。
func _ring_entry(spr):
	for f in _s._anim_fx:
		if f.get("spr", null) == spr:
			return f
	return null


# ── ③ 几何没动: 末帧外径 == 调用点给的 radius ──────────────────────────────
func _g3_geometry_unchanged() -> void:
	print("  ③ 几何(换的是怎么画, 不是画多大)")
	for radius in [40.0, 60.0, 105.0]:
		var r: Sprite3D = _s._skill_ring(P, Color(1, 1, 1, 0.6), radius)
		if r == null or not is_instance_valid(r):
			_ok("③ radius=%.0f 建出了环" % radius, false); continue
		## ★★这里必须拿**素材本身量出来的外径**当锚点, 不能用 RING_LAST_R_PX ——
		##   产品的 pixel_size 公式里就有这个常量, 拿它去验会**在等式两边约掉** ⇒ 恒真式
		##   (把常量改成 24.0 这条照样绿 —— 反向验证当场拓到的)。
		var meas_r: float = _last_frame_outer_r(r.texture)
		_ok("③ radius=%.0f ★分母: 从素材量出末帧外径 %.1fpx" % [radius, meas_r], meas_r > 1.0)
		_ok("③ ★常量 RING_LAST_R_PX(%.1f) 与素材实测(%.1f) 对得上" % [RB.RING_LAST_R_PX, meas_r],
			absf(RB.RING_LAST_R_PX - meas_r) < 1.0)
		var dia_m: float = meas_r * 2.0 * float(r.pixel_size)
		var want_m: float = radius * 2.0 * _s.WS
		_ok("③ radius=%.0f 末帧直径 = 2r×WS" % radius, absf(dia_m - want_m) < 0.01,
			"实得 %.4f m / 应 %.4f m" % [dia_m, want_m])
		## 贴地: axis=AXIS_Y 本身就是平铺, 不许再叠 rotation (memory [[fb-axis-y-plus-rotation-cancels]])
		var up: float = absf((r.global_transform.basis * Vector3.UP).normalized().dot(Vector3.UP))
		_ok("③ radius=%.0f 环是躺平贴地的 (|法线·上| = %.3f)" % [radius, up], up > 0.99)
		r.queue_free()
	await get_tree().process_frame


# ── ④ 30 次调用全部自销 ────────────────────────────────────────────────────
func _g4_other_callers_ok() -> void:
	print("  ④ 批量调用不残留")
	var rings: Array = []
	var t0: float = _s._t
	for i in range(30):
		var rr: Sprite3D = _s._skill_ring(P + Vector2(float(i) * 3.0, 0.0),
			Color(1, 1, 1, 0.6), 44.0)
		if rr != null:
			rings.append(rr)
	_ok("④ ★分母: 30 次调用建出 30 个环", rings.size() == 30, "实得 %d" % rings.size())
	_s._t = t0 + float(RB.RING_ANIM_FRAMES) / RB.RING_ANIM_FPS + 0.5
	_s._render._tick_anim_fx()
	await get_tree().process_frame
	var alive := 0
	for rr in rings:
		if is_instance_valid(rr) and not (rr as Node).is_queued_for_deletion():
			alive += 1
	_ok("④ ★30 个环全部自销", alive == 0, "还活着 %d 个" % alive)
	_ok("④ ★帧动画表清空(没有泄漏的条目)", _s._anim_fx.is_empty(),
		"表里还剩 %d 条" % _s._anim_fx.size())
	## 同族原语没被波及
	var before: int = _s._world.get_child_count()
	_s._splash_ring_bold(P, Color(1, 1, 1, 1), 200.0)
	var made: int = _s._world.get_child_count() - before
	_ok("④ _splash_ring_bold 照旧建双层环(同族原语没被波及)", made == 2, "实得 %d" % made)


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
	print("ALL PASS — _skill_ring 逐帧扩散原语" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

## ══════════════════════════════════════════════════════════════════════
##  ⑤ 环的**素材本身**必须是像素画 —— 不是软边现算圆
## ══════════════════════════════════════════════════════════════════════
## ★★为什么补这一段(用户 2026-08-09 原话):
##   「**又是程序生成的环？哪个商业游戏是你这么做啊**」
##   被否的那个东西是 `VfxTex._make_ring_texture` 里 96×96 的逐像素现算
##   (`a = clamp(1-|d-0.82|/0.18)*0.6`), 规格是 **半透 4184 / 全不透明 0 /
##   alpha 148 档连续斜坡 / 峰值只有 153**。它封着全游戏 187 处调用。
##   2026-09-11 换成烤好的像素图, 但**换掉不等于回不来** —— 上面那 26 条断言
##   全是量【曲线】的, 软边圆照样能全绿。⇒ 这一段量【贴图本身】。
##
## ★判据走**真函数返回的那张贴图**, 不读源码子串
##   (memory `fb-weld-visual-lessons-into-gate`: 源码子串匹配是假判据要走真函数) ——
##   所以不论是把现算逻辑加回来、还是换成另一张软边 PNG, 这里都会红。
func _g5_ring_is_pixel_art() -> void:
	print("")
	print("  ⑤ 环的素材本身: 必须是像素画(硬 alpha / 锁定色阶 / 纯灰)")
	var tex: Texture2D = VfxTex._make_ring_texture(Color.WHITE)
	_ok("⑤ ★分母: _make_ring_texture 真的返回了贴图", tex != null)
	if tex == null:
		return
	var img: Image = tex.get_image()
	var cols := {}
	var semi := 0
	var opaque := 0
	var tinted := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			var a: int = int(round(c.a * 255.0))
			if a <= 0:
				continue
			if a < 255:
				semi += 1
			else:
				opaque += 1
			var r: int = int(round(c.r * 255.0))
			var g: int = int(round(c.g * 255.0))
			var b: int = int(round(c.b * 255.0))
			if r != g or g != b:
				tinted += 1
			cols["%d_%d_%d" % [r, g, b]] = true
	print("     %dx%d  色数 %d  半透 %d  不透明 %d  带色相 %d"
		% [img.get_width(), img.get_height(), cols.size(), semi, opaque, tinted])
	_ok("⑤ 尺寸 %dx%d(须 96x96 —— 几何/pixel_size 换算依赖它)" % [img.get_width(), img.get_height()],
		img.get_width() == 96 and img.get_height() == 96)
	_ok("⑤ 色数 %d(须 1~8 —— 锁定色阶, 不是连续渐变)" % cols.size(),
		cols.size() >= 1 and cols.size() <= 8,
		"旧的现算环是 1 色但 148 档连续 alpha —— 软的那一面由下一条抓")
	_ok("⑤ ★★半透明像素 %d(须 0 —— 反锯齿软边正是被否掉的那个观感)" % semi, semi == 0,
		"旧的现算环这里是 4184, 且全不透明像素 0 个")
	_ok("⑤ 全不透明像素 %d(须 > 1000 —— 只有【没有半透】还不够, 整张空的也满足)" % opaque,
		opaque > 1000)
	_ok("⑤ ★必须是纯灰 R=G=B(带色相的像素 %d 个, 须 0)" % tinted, tinted == 0,
		"环的颜色由 187 个调用点各自 modulate 决定; 素材带色相会串到每一处")
