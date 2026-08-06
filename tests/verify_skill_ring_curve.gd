extends Node
## verify_skill_ring_curve.gd — `_skill_ring` 公共原语的【两条曲线】门禁 (2026-08-07)
##
## ★守的是一个【已确诊的 bug】(方案书 docs/plans/20260807-表现层方案书.md §1.3):
##   原实现里尺寸和 alpha 走**同一条 0.35 秒曲线** —— 环从 40% 扩到 100% 的同时
##   alpha 从 1 拉到 0 ⇒ **环放到最大的那一帧正好完全透明**, 肉眼只看得到 40~70% 那一段。
##   影响 083 潮汐细剑的叠层环 / 093 香火石的唯一主动 / 081 藤编圆盾 / 目标环 —— 全是同族细环。
##
## ── 怎么量(★这一节是本文件的全部价值所在) ──────────────────────────────────
## ⚠ **不许在测试里把曲线公式再实现一遍然后跟自己比** —— 那是恒真式,
##    把产品代码改成写死也照样绿 (memory [[fb-write-without-reader-and-fake-gates]]:
##    「门禁模拟公式 ≠ 量真实对象」)。
## ⇒ 本文件的做法: 拿 `_skill_ring` **返回的真实 Sprite3D**, 手推它自己的那条 tween
##    (`ring_tw` meta), 每一步都去读节点【当前的】`pixel_size` 与 `modulate.a`。
##    分母 `ring_target_ps` 也是产品代码自己写在节点上的, 测试不重算。
## ⚠ 手推而不是 `await` 真实时间: 无头 CI 下 `create_tween` 自走不稳 (CLAUDE.md §3.5),
##    等多久都可能是 0。`tw.pause()` + `custom_step(dt)` 是确定性的。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_skill_ring_curve.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

const P := Vector2(700.0, 400.0)
## 取样步长(秒)。总时长 RING_GROW_T + RING_FADE_T ≈ 0.48 ⇒ 约 240 个采样点。
const DT := 0.002

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
	print("=== _skill_ring 公共原语: 尺寸与 alpha 必须是两条曲线 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(8):
		await get_tree().process_frame
	# 关掉战斗 _process: 本文件全部手推 tween, 不让 sim 每帧再造别的环进来干扰计数。
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	_g1_denominator()
	if not is_instance_valid(_s._world):
		print("")
		print("FAIL x%d — ★分母没过, 后面全是空检查" % maxi(1, _fail))
		get_tree().quit(1); return
	await _g2_curve()
	await _g3_geometry_unchanged()
	await _g4_other_callers_ok()
	await _done()


# ── ① ★分母 ─────────────────────────────────────────────────────────────────
func _g1_denominator() -> void:
	print("")
	print("  ① ★分母:")
	_ok("① 世界节点 _world 在", is_instance_valid(_s._world))
	print("     曲线常量: 起始尺寸 %.2f / 扩张 %.3fs / 淡出 %.3fs / 峰值 alpha %.2f" % [
		RB.RING_PS0, RB.RING_GROW_T, RB.RING_FADE_T, RB.RING_PEAK_A])
	# ★这一条就是"两条曲线"的结构前提: 淡出段必须真的占时间, 否则又退化成同步淡出。
	_ok("① 扩张段与淡出段都 > 0(两条曲线的结构前提)",
		RB.RING_GROW_T > 0.0 and RB.RING_FADE_T > 0.0)
	_ok("① 起始尺寸在 (0,1) 之间(环要真的会长大)", RB.RING_PS0 > 0.0 and RB.RING_PS0 < 1.0)


# ── ② ★★核心: 长到最大的那一帧必须还看得见 ────────────────────────────────
func _g2_curve() -> void:
	print("")
	print("  ② ★★核心 — 环长到最大时【仍有可见 alpha】(量真实节点, 不重算公式):")
	var r: Sprite3D = _s._skill_ring(P, Color(1.0, 0.85, 0.4, 0.6), 60.0)
	if r == null or not is_instance_valid(r):
		_ok("② ★分母: _skill_ring 返回了真实节点", false); return
	_ok("② ★分母: _skill_ring 返回了真实节点", true)
	var target_ps: float = float(r.get_meta("ring_target_ps", 0.0))
	_ok("② ★分母: 节点自己写了 ring_target_ps(分母来自产品代码, 不是测试重算)", target_ps > 0.0)
	if target_ps <= 0.0:
		return
	var tw: Tween = r.get_meta("ring_tw", null)
	_ok("② ★分母: 拿到了这个环自己的那条 tween", tw != null and tw is Tween)
	if tw == null:
		return

	# 起点
	var f0: float = r.pixel_size / target_ps
	var a0: float = r.modulate.a
	print("     t=0.000  尺寸 %.3f×  alpha %.3f" % [f0, a0])
	_ok("② 起手就是小环(尺寸 < 0.6×)", f0 < 0.6)
	_ok("② 起手 alpha 就在峰值", absf(a0 - RB.RING_PEAK_A) < 0.01)

	# ★手推这条 tween, 每步都读【节点当前的】两个值。
	tw.pause()
	var t := 0.0
	var a_at_full := -1.0          # 尺寸首次 ≥0.99× 时的 alpha
	var t_at_full := -1.0
	var best_vis := -1.0           # 可见度 = 尺寸 × alpha 的峰值
	var f_at_best := -1.0
	var t_at_best := -1.0
	var min_a_while_growing := 9.0 # 扩张段里 alpha 的最低点
	var samples: Array = []
	for i in range(400):
		tw.custom_step(DT)
		t += DT
		if not is_instance_valid(r):
			break
		var f: float = r.pixel_size / target_ps
		var a: float = r.modulate.a
		samples.append([t, f, a])
		if f < 0.999:
			min_a_while_growing = minf(min_a_while_growing, a)
		if a_at_full < 0.0 and f >= 0.99:
			a_at_full = a
			t_at_full = t
		var vis: float = f * a
		if vis > best_vis:
			best_vis = vis
			f_at_best = f
			t_at_best = t
		if t > RB.RING_GROW_T + RB.RING_FADE_T + 0.05:
			break

	print("     采样 %d 点, 步长 %.3fs" % [samples.size(), DT])
	for k in [0.15, 0.35, 0.55, 0.75, 0.95]:                   # 打几个中间点便于人眼看
		var idx: int = clampi(int(float(samples.size() - 1) * k), 0, maxi(0, samples.size() - 1))
		if idx < samples.size():
			print("       t=%.3f  尺寸 %.3f×  alpha %.3f" % [
				float(samples[idx][0]), float(samples[idx][1]), float(samples[idx][2])])
	print("     ★尺寸首次到 0.99× 是在 t=%.3f, 那一刻 alpha = %.3f  (旧实现这里是 ~0.03)" % [
		t_at_full, a_at_full])
	print("     ★可见度(尺寸×alpha)峰值 %.3f 出现在 t=%.3f, 那时尺寸 %.3f×" % [
		best_vis, t_at_best, f_at_best])
	print("     扩张段里 alpha 的最低点 = %.3f (需求 ≥ %.2f —— 长大的全程都保持峰值)" % [
		min_a_while_growing, RB.RING_PEAK_A - 0.01])

	_ok("② ★分母: 环真的长到了 100%(不是 tween 没推动)", a_at_full >= 0.0)
	_ok("② ★★环长到最大那一刻 alpha 仍 ≥ 0.9(这就是修的那个 bug)", a_at_full >= 0.9)
	_ok("② ★★可见度峰值出现在【环已经长大之后】(尺寸 ≥ 0.95×)", f_at_best >= 0.95)
	_ok("② ★扩张全程 alpha 都保持峰值(没有边长边淡)",
		min_a_while_growing >= RB.RING_PEAK_A - 0.01)

	# 淡出段确实存在: 最后要淡到 0 并把自己 free 掉(不能永久留在场上)。
	tw.custom_step(RB.RING_GROW_T + RB.RING_FADE_T + 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	print("     推完全程 + 2 帧后, 节点还在不在: %s (需求 false —— 淡完要自销)" % str(is_instance_valid(r)))
	_ok("② ★环最终淡完并自销(淡出段不是摆设)", not is_instance_valid(r))


# ── ③ 尺寸/朝向一个都没动 ───────────────────────────────────────────────────
## 改的只有时间轴。这一组保证"公共原语"的几何口径跟改之前一模一样。
func _g3_geometry_unchanged() -> void:
	print("")
	print("  ③ 只改时间轴 —— 几何口径一点没动:")
	for radius in [26.0, 46.0, 60.0, 130.0, 200.0]:
		var r: Sprite3D = _s._skill_ring(P, Color(0.5, 0.9, 1.0, 0.7), float(radius))
		if r == null:
			_ok("③ radius=%.0f 建出了环" % radius, false); continue
		var tps: float = float(r.get_meta("ring_target_ps", 0.0))
		# 量【真实节点】: 长满后的直径(米) = 贴图宽 × 最终 pixel_size
		var dia_m: float = float(r.texture.get_width()) * tps
		var want_m: float = float(radius) * 2.0 * _s.WS
		if radius == 60.0:
			print("     radius=%.0f → 长满直径 %.3f m (需求 %.3f m = 2r×WS)" % [radius, dia_m, want_m])
		_ok("③ radius=%.0f 长满直径 = 2r×WS" % radius, absf(dia_m - want_m) < 0.01,
			"实得 %.3f 需求 %.3f" % [dia_m, want_m])
		# 贴地: axis=AXIS_Y 本身就是平铺, 不许再叠 rotation (memory [[fb-axis-y-plus-rotation-cancels]])
		var up: float = absf((r.global_transform.basis * Vector3.UP).normalized().dot(Vector3.UP))
		_ok("③ radius=%.0f 环是躺平贴地的 (|法线·上| = %.3f)" % [radius, up], up > 0.99)
		r.queue_free()
	await get_tree().process_frame


# ── ④ ★公共原语: 别的调用者没被搞坏 ────────────────────────────────────────
## `_skill_ring` 全仓 60+ 个调用点。这一组盯两件真实风险:
##   ① 返回值/tween 结构变了会不会让高频调用点漏 free(083 的 20 层叠层环就是高频)
##   ② `_splash_ring_bold`(另一条同族环, 本次【没动】) 还照旧工作
func _g4_other_callers_ok() -> void:
	print("")
	print("  ④ ★公共原语 — 别的调用者没被搞坏:")
	var rings: Array = []
	for i in range(30):                                # 模拟 083 那种一口气刷一堆环的调用点
		var r: Sprite3D = _s._skill_ring(P + Vector2(float(i) * 3.0, 0.0),
			Color(0.6, 0.9, 1.0, 0.6), 40.0)
		if r != null:
			rings.append(r)
	print("     连开 30 个环 → 真的建出 %d 个" % rings.size())
	_ok("④ ★分母: 30 次调用建出 30 个环", rings.size() == 30)
	for r in rings:
		var tw: Tween = r.get_meta("ring_tw", null)
		if tw != null:
			tw.pause()
			tw.custom_step(RB.RING_GROW_T + RB.RING_FADE_T + 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	var alive := 0
	for r in rings:
		if is_instance_valid(r):
			alive += 1
	print("     推完全程后还活着 %d 个 (需求 0 —— 高频调用点不能漏 free)" % alive)
	_ok("④ ★30 个环全部自销(queue_free 藏在两层 chain 后面也照样跑到)", alive == 0)

	# `_splash_ring_bold` 这次没动 —— 但它跟 _skill_ring 同族, 顺手证明它还活着。
	var before: int = _s._world.get_child_count()
	_s._splash_ring_bold(P, Color(1.0, 0.6, 0.2, 0.6), 80.0)
	var made: int = _s._world.get_child_count() - before
	print("     _splash_ring_bold(本次没动) → 新增 %d 个节点 (需求 2 = 双层)" % made)
	_ok("④ _splash_ring_bold 照旧建双层环(同族原语没被波及)", made == 2)


# ── 工具 ────────────────────────────────────────────────────────────────────
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
	print("ALL PASS — _skill_ring 两条曲线" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
