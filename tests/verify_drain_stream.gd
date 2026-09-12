extends Node
## verify_drain_stream.gd — 014 深海堡垒甲【汲取生命】演出的门禁 (2026-09-12)
##
## ════════════════════════════════════════════════════════════════════════
##  ★由来 —— 用户逐字定的四拍, 钉在这里不许漂
## ════════════════════════════════════════════════════════════════════════
## 他否掉的第一版是拿 `_bolt_line`(一条直线排一串方块)当"汲取"用:
##   「**为什么又用什么长方形来敷衍**」「**你怎么能这样敷衍我呢**」
## 他给的四拍:
##   ① 一道**绿色粒子波纹**从**目标身上抽取出来**
##   ② 在**空中飘舞**
##   ③ **飞到携带者身上**
##   ④ 携带者身上**绿色粒子爆发**
##
## 第二版(粒子做出来了)在 1:1 实拍里仍然**读成白色亮片**, 量出来是两个独立毛病:
##   ⓐ **配色串档**: 素材重索引到了 `pixelize_sheet` 的 `jade` 板 —— jade 是**薄荷青**
##      (主色 110,200,148)。战场上龟本身就是青身 + 暗绿壳, 同色系 + 泛光 ⇒ 认不出是绿的。
##   ⓑ **贴图被压 3.4 倍**: 染色实测(品红 + 关泛光)一粒在屏幕上只有 **7×7 像素**,
##      而贴图一格是 **24×24**。像素画非整数倍缩放 = 像素网格被打烂
##      (像素风三条硬约束之首, `battle_ballistics.gd:675`), 菱形糊成一坨亮点。
##
## ── 判据怎么定的 ────────────────────────────────────────────────────────
## ⚠ 不许断言"函数存在"或"我插的标记"(memory `fb-gate-must-measure-requirement-not-my-hook`),
##   也不许拿产品自己的常量两边一约(memory: 恒真式判据)。
## ⇒ 这里量的全是**真实产出**: 调完 `drain_stream` 从 `_world` 里把新 Sprite3D 捞出来,
##   读它**贴图里的真实像素**、读它的 `pixel_size`、手推它自己的 tween 量位置与 alpha。
##
## ★"正绿 vs 薄荷青"的判据形状(memory `fb-judge-must-fit-the-shape`):
##   光说"g 最大"卡不住 —— jade 的主色 g 也最大。**区别在蓝**:
##     · 正绿  life (104,244,112): b-r = +8    蓝红几乎相等
##     · 薄荷青 jade (110,200,148): b-r = +38   蓝明显高于红 ⇒ 偏青
##   ⇒ 判据 = `g - r ≥ 100` 且 `|b - r| ≤ 25`。两条都能把 jade 判红。
##
## ★"1 texel : 1 屏幕像素"的判据不是拿常量约常量:
##   `0.0426 m/屏幕像素` 是**染色实测量出来的**(台子 1280×720 · zoom=1.0,
##   一粒 7×7 px / 一只龟 ≈45 px 高而立绘帧高 = TARGET_BODY_H = 2.0 m ⇒ ≈23.5 px/m)。
##   门禁把【贴图一格的真实像素数】和【MOTE_YARDS】乘到一起去对这个实测值 ——
##   任一边单独改了就会红。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## ★实测常数(染色法量的, 不是产品里的常量): 台子镜头下一个屏幕像素 = 多少米。
const M_PER_SCREEN_PX := 0.0426
const PS_TOL := 0.15                       # pixel_size 允许偏离 ±15%

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


## 调一次演出, 把它新建出来的 Sprite3D 全捞回来。
func _spawn(f: Callable) -> Array:
	var before: Array = []
	for c in _s._world.get_children():
		before.append(c)
	f.call()
	var out: Array = []
	for c in _s._world.get_children():
		if c is Sprite3D and not before.has(c):
			out.append(c)
	return out


## 捞出"这一刻之后新建的、还在跑的" tween, 全部暂停, 之后统一手推。
## (无头 CI 下 tween 自走不稳 —— CLAUDE.md §3.5)
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true            # ★台子要渲染 ⇒ 非 headless ⇒ test_mode 不自动置位, 会写真存档
	print("=== 014 汲取生命: 绿色粒子从目标抽出 → 飘舞 → 飞到携带者 → 爆发 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	var src := Vector2(900.0, 400.0)         # 被汲取的目标
	var dst := Vector2(560.0, 430.0)         # 携带者

	var tw_before: Array = []
	for t in _s.get_tree().get_processed_tweens():
		tw_before.append(t)
	var motes: Array = _spawn(func() -> void: _s._vfx.drain_stream(src, dst))
	var tws: Array = _grab_tweens(tw_before)

	# ── ① ★分母: 真的生出了一串粒子(不是一两颗, 要连得成一道波纹) ────────
	_ok("① ★分母: drain_stream 往 _world 里生出了粒子(实得 %d 个 Sprite3D)" % motes.size(),
		motes.size() >= 8, "少于 8 粒连不成「一道波纹」")
	if motes.size() < 8:
		_done(); return
	var m0: Sprite3D = motes[0]
	var tex: Texture2D = m0.texture
	_ok("① ★分母: 粒子带贴图(不是程序画的白球)", tex != null)
	if tex == null:
		_done(); return

	# ── ② ★★配色: 必须是【正绿】, 不是薄荷青 ─────────────────────────
	var img: Image = tex.get_image()
	var cnt: Dictionary = {}
	var opaque := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			opaque += 1
			var key := "%d_%d_%d" % [int(round(c.r8)), int(round(c.g8)), int(round(c.b8))]
			cnt[key] = int(cnt.get(key, 0)) + 1
	_ok("② ★分母: 贴图里有不透明像素(实得 %d px / 共 %d px)"
		% [opaque, img.get_width() * img.get_height()], opaque > 40)
	var top_key := ""
	var top_n := 0
	for k in cnt.keys():
		if int(cnt[k]) > top_n:
			top_n = int(cnt[k]); top_key = str(k)
	var parts: PackedStringArray = top_key.split("_")
	var tr := int(parts[0])
	var tg := int(parts[1])
	var tb := int(parts[2])
	_ok("② 主色占比够高(实得 %d/%d = %.0f%%) —— 主色说了算" % [top_n, opaque,
		100.0 * float(top_n) / float(maxi(1, opaque))], float(top_n) / float(maxi(1, opaque)) >= 0.35)
	_ok("② ★★主色是绿的: g-r ≥ 100 (实得 rgb(%d,%d,%d), g-r=%d)" % [tr, tg, tb, tg - tr],
		tg - tr >= 100)
	_ok("② ★★主色是【正绿】不是薄荷青: |b-r| ≤ 25 (实得 %d) —— jade 主色这里是 38"
		% absi(tb - tr), absi(tb - tr) <= 25)
	var semi := 0
	for y2 in range(img.get_height()):
		for x2 in range(img.get_width()):
			var a2: float = img.get_pixel(x2, y2).a
			if a2 > 0.02 and a2 < 0.98:
				semi += 1
	_ok("② 硬边: 没有半透明羽化像素(实得 %d)" % semi, semi == 0)

	# ── ③ 一格是方的, 而且美术真占满格(不是一小点飘在空白里) ─────────────
	var cell: int = int(img.get_width() / maxi(1, m0.hframes))
	_ok("③ 一格是正方形(%d × %d)" % [cell, img.get_height()], cell == img.get_height())
	var bx0 := 9999
	var bx1 := -1
	var by0 := 9999
	var by1 := -1
	for y3 in range(img.get_height()):
		for x3 in range(cell):
			if img.get_pixel(x3, y3).a >= 0.5:
				bx0 = mini(bx0, x3); bx1 = maxi(bx1, x3)
				by0 = mini(by0, y3); by1 = maxi(by1, y3)
	var artw: int = bx1 - bx0 + 1
	var arth: int = by1 - by0 + 1
	_ok("③ ★美术占满格: 本体 %d×%d / 格 %d (应 ≥ 60%%)" % [artw, arth, cell],
		artw >= int(float(cell) * 0.6) and arth >= int(float(cell) * 0.6))

	# ── ④ ★★1 texel : 1 屏幕像素(治"贴图被压 3.4 倍"那条) ──────────────
	_ok("④ ★★pixel_size ≈ 一个屏幕像素的世界尺寸(实得 %.4f m / 实测应 %.4f m)"
		% [m0.pixel_size, M_PER_SCREEN_PX],
		absf(m0.pixel_size - M_PER_SCREEN_PX) <= M_PER_SCREEN_PX * PS_TOL,
		"贴图一格 %d px × pixel_size = %.3f m" % [cell, float(cell) * m0.pixel_size])
	_ok("④ 用 NEAREST 取样(像素风不许双线性)",
		m0.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)

	# ── ⑤ ①③ 两拍: 从目标身上出发, 最后落到携带者身上 ────────────────────
	var p_from: Vector3 = _s._world_pos(src, 0.0)
	var p_to: Vector3 = _s._world_pos(dst, 0.0)
	var d0: float = Vector2(m0.position.x - p_from.x, m0.position.z - p_from.z).length()
	var d0b: float = Vector2(m0.position.x - p_to.x, m0.position.z - p_to.z).length()
	_ok("⑤ ①抽取: 粒子出生在【目标】身上(离目标 %.2f m / 离携带者 %.2f m)" % [d0, d0b],
		d0 < d0b)
	## 手推它自己的 tween, 在飞行途中【三点采样】(0.16 / 0.42 / 0.66 秒)。
	## ★只看 0 号粒子: 只有它的出发延迟是 0, 全局时间轴才和它自己的阶段对得上
	##   (其余粒子被 DRAIN_STAGGER 错开, 同一时刻各在各的阶段)。
	_step(tws, 0.16)                      # ①抽取结束的那一刻
	var q1 := Vector2(m0.position.x, m0.position.z)
	_step(tws, 0.26)                      # ②飘到半路
	var q2 := Vector2(m0.position.x, m0.position.z)
	var a_mid: float = m0.modulate.a
	_ok("⑥ ★★治淡出病: 飞到一半时仍是满亮(实得 alpha %.2f) —— 一出生就淡是被治的那个病"
		% a_mid, a_mid >= 0.95)
	_step(tws, 0.24)                      # ③快到终点(0.66 < 0.68 的自销时刻)
	if is_instance_valid(m0):
		var d1: float = Vector2(m0.position.x - p_to.x, m0.position.z - p_to.z).length()
		var d1b: float = Vector2(m0.position.x - p_from.x, m0.position.z - p_from.z).length()
		_ok("⑤ ③飞到: 飞行末尾落在【携带者】身上(离携带者 %.2f m / 离目标 %.2f m)" % [d1, d1b],
			d1 < d1b)
	else:
		_ok("⑤ ③飞到: 粒子在量之前就被销毁了", false)

	# ── ⑥ ②飘舞: 轨迹必须【弯】, 不是直线 ──────────────────────────────
	## ★这一条正是用户否掉第一版的原因(「长方形」= 一条直线排方块)。
	## ★★判据换过一次形状(memory `fb-judge-must-fit-the-shape`):
	##   第一版量的是【粒子到「起点—终点」直线的垂距】, **卡不住** ——
	##   粒子在①抽取那一步本来就会左右扇开一段(那是「抽」不是「飘」),
	##   于是把摆幅 DRAIN_WAVE 改成 0(= 退回直线)之后它照样有垂距, 门禁照样绿。
	##   ⇒ 改成量【这一粒自己的轨迹弯不弯】: 三点采样, 看中点离「首尾两点连成的弦」
	##     有多远(弧垂)。直线的话中点就贴在弦上, 弧垂趋近 0。
	var q3 := (Vector2(m0.position.x, m0.position.z) if is_instance_valid(m0) else q2)
	var chd := q3 - q1
	var sag := 0.0
	if chd.length() > 0.01:
		var uu := chd.normalized()
		var rel2 := q2 - q1
		sag = absf(rel2.x * uu.y - rel2.y * uu.x)
	_ok("⑥ ②飘舞: 轨迹是弯的 —— 中点离首尾弦 %.2f m(直线排方块正是被否掉的那一版)" % sag,
		sag > 0.35,
		"首(%.2f,%.2f) 中(%.2f,%.2f) 尾(%.2f,%.2f)" % [q1.x, q1.y, q2.x, q2.y, q3.x, q3.y])

	# ── ⑦ ④爆发: 携带者身上炸开一圈 ────────────────────────────────────
	var tw_b2: Array = []
	for t2 in _s.get_tree().get_processed_tweens():
		tw_b2.append(t2)
	var burst: Array = _spawn(func() -> void: _s._vfx._drain_burst(dst))
	var tws2: Array = _grab_tweens(tw_b2)
	_ok("⑦ ★分母: 爆发生出了粒子(实得 %d)" % burst.size(), burst.size() >= 6)
	if burst.size() >= 6:
		var r0 := 0.0
		for bb in burst:
			r0 = maxf(r0, Vector2(bb.position.x - p_to.x, bb.position.z - p_to.z).length())
		_ok("⑦ 爆发起点贴在携带者身上(最大半径 %.2f m)" % r0, r0 < 0.20)
		_step(tws2, BattleVfx.BURST_T * 0.9)
		var r1 := 0.0
		var alive := 0
		for bb2 in burst:
			if not is_instance_valid(bb2):
				continue
			alive += 1
			r1 = maxf(r1, Vector2(bb2.position.x - p_to.x, bb2.position.z - p_to.z).length())
		_ok("⑦ ★分母: 推完 tween 还剩 %d 粒活着" % alive, alive >= 6)
		_ok("⑦ ④爆发: 粒子向外散开(半径 %.2f m → %.2f m)" % [r0, r1], r1 > r0 + 0.30)

	_done()


func _done() -> void:
	if is_instance_valid(_s):
		_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  分母: 共 %d 条断言" % _n)
	if _n < 16:
		print("  [FAIL] ★断言只有 %d 条(<16) —— 有用例中途中止了" % _n)
		_fail += 1
	print("ALL PASS — 014 汲取生命" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
