extends Node
## shot_skill_ring_phases.gd — `_skill_ring` 的【分相位定格胶片】(dev-only 取景工具, 2026-08-07)
##
## ★为什么要单独做这个而不是用 `VFXLAB=1` 拍:
##   一个环只活 0.35~0.48 秒, 而干净台是**按游戏秒排程**拍的 —— 拍到环的哪个相位纯属抽签,
##   两次运行(改前/改后)连单位站位都对不齐, 拿来做 A/B 是在比噪声。
##   ⇒ 本文件把环建出来后**手推它自己的 tween 到指定相位再定格**, 五个相位一次拍完。
##   同一张图里从左到右就是环的一生, 改前/改后逐格可比。
##
## 跑法(★不能加 --headless, 无头不渲染、截图是空的还不报错;
##      ★必须加 --position 5000,5000 把窗口挪出屏幕, 多路 agent 并行时别糊住用户的屏幕):
##   SHOT_OUT=res://_ringphase \
##   <godot> --path . --position 5000,5000 res://tests/shot_skill_ring_phases.tscn
##
## ⚠ 实测记录: `BLACKMAP=1` 【没有】把地图变黑(它管的是环境背景那一层), 所以这张图里
##   地形是照常画的。**这样反而更好** —— 环的可见性问题本来就是"在真实地图底色上读不读得出",
##   纯黑底会把对比度问题掩盖掉。单位立绘/血条则是本文件自己藏的, 免得挡住环。
##
## ⚠ 它不是门禁 —— 门禁是 `tests/verify_skill_ring_curve.gd`(量真实节点的 alpha 与 scale)。
##   本文件只负责"给人看"。文件名以 `shot_` 开头 ⇒ `run-tests.sh` 的 `verify_*` 自动发现不会捡到它。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 五个定格相位, 单位是【扩张段的倍数】。2 号那格就是本次修的那个 bug 所在:
## 环刚好长到 100% —— 改前它在这一格完全透明, 改后它在这一格最亮。
const PHASES := [0.0, 0.5, 1.0, 1.5, 1.9]

var _s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(20):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED

	# 干净台: 藏掉所有单位立绘与血条, 只留环。
	for u in _s._units:
		if u is Dictionary:
			for k in ["sprite", "hpbar", "shbar", "namelbl", "lvl_badge"]:
				var n = u.get(k, null)
				if is_instance_valid(n):
					n.visible = false

	var c: Vector2 = _s._arena_center
	var grow: float = RB.RING_GROW_T
	var fade: float = RB.RING_FADE_T
	print("[RINGPHASE] 扩张 %.3fs / 淡出 %.3fs / 起始尺寸 %.2f / 峰值 alpha %.2f" % [
		grow, fade, RB.RING_PS0, RB.RING_PEAK_A])
	for i in range(PHASES.size()):
		var p: Vector2 = c + Vector2((float(i) - 2.0) * 250.0, 0.0)
		var r: Sprite3D = _s._skill_ring(p, Color(1.0, 0.86, 0.42, 0.8), 105.0)
		if r == null:
			continue
		var tw: Tween = r.get_meta("ring_tw", null)
		var t: float = grow * float(PHASES[i])
		if tw != null:
			tw.pause()
			if t > 0.0:
				tw.custom_step(t)
		var tps: float = float(r.get_meta("ring_target_ps", 1.0))
		print("[RINGPHASE] 第%d格  t=%.3fs  尺寸 %.3f×  alpha %.3f" % [
			i, t, r.pixel_size / maxf(0.0001, tps), r.modulate.a])

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out: String = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "res://_ringphase"
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out + ".png")
	print("[RINGPHASE] → %s.png  (%dx%d)" % [out, img.get_width(), img.get_height()])
	get_tree().quit()
