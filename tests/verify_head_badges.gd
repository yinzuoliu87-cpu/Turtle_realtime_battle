extends Node
## verify_head_badges.gd — 头顶徽章的【几何不重叠】（2026-08-05）
##
## ★★★为什么要有它：
##   用户 2026-08-04 说"头顶徽章加就行"。扩容前先量了一下，量出一个
##   **本来就存在、但没人发现的问题**：
##     相邻单位在屏幕上只隔 **64.7 px**（分离半径 92 码）
##     而 4 项 × 间距 40 的一行已经宽 **154 px** = 单位间距的 2.4 倍
##   ⇒ 4 项时就已经在跟邻居的徽章互相覆盖了，直接调 CAP 到 6 只会更糟。
##
##   没门禁守着，这种"几何上早就崩了但看不出是 bug"的问题会一直躺着。
##
## 守四条：
##   ① ★徽章行宽 ≤ 相邻单位屏幕间距 × 1.3（留一点余量，完全不重叠不现实）
##   ② ★容量真的是 6（网格 3 列 × 2 行）
##   ③ ★满 6 项时**每一项都摆得出来**且互不重叠（逐对查包围盒）
##   ④ ★分母：真的建出了 6 个徽章节点（不是画了个寂寞）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_head_badges.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		# detail 是【失败时才有意义的解释】(例: "没冲过 1 就是没动效"), PASS 时打出来自相矛盾
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 头顶徽章: 几何不重叠 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	# ★★★先证明【被测对象真的建起来了】再断言任何东西。
	#   2026-08-05 实测: 战场脚本因为依赖的脚本编译失败而整个没起来时(`RB.new()` 返回 null),
	#   这个文件照样打出了 3 个 [PASS] —— 断言在垃圾数上成立, 是**假绿灯**。
	#   Godot 在脚本报错后会继续跑, 所以"没崩"绝不等于"跑对了"。
	if s == null:
		print("  [FAIL] ⓪ ★被测对象没建起来(RB.new() 返回 null, 多半是依赖脚本编译失败)")
		print("FAIL x1")
		get_tree().quit(1)
		return
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("⓪ ★分母: 战场与相机真的起来了", is_instance_valid(s) and s._cam != null,
		"s=%s cam=%s —— 后面所有断言都建立在这个之上" % [str(s), str(s._cam if is_instance_valid(s) else null)])
	if not is_instance_valid(s) or s._cam == null:
		print("FAIL x1  (被测对象无效, 不再往下断言 —— 免得在垃圾数上打出 PASS)")
		get_tree().quit(1)
		return

	# ── 相邻单位在屏幕上隔多远（分离半径 92 码，与 _separate 同源）──
	var o := Vector2(s.ARENA.position.x + s.ARENA.size.x * 0.5,
		s.ARENA.position.y + s.ARENA.size.y * 0.5)
	var cam: Camera3D = s._cam
	var pa: Vector2 = cam.unproject_position(s._world_pos(o, 2.4))
	var pb: Vector2 = cam.unproject_position(s._world_pos(o + Vector2(92.0, 0.0), 2.4))
	var sep_raw: float = (pb - pa).length()
	# ★★★必须归一化到设计画布高度, 否则这条门禁在 CI 上是【放松近一倍】的假绿灯:
	#   无头视口是 **1280×1280 方形**(不是 1280×720), 而 Camera3D 默认 keep_height ⇒
	#   水平投影像素 ∝ viewport.size.y ⇒ 无头量到 115.6px, 真实窗口只有 65.0px。
	#   实测两边 × (720/size.y) 后都回到 65.0 —— 用这个口径, 有头无头判据才一样严。
	#   (相关: memory「无头视口是方形, 据此判可见性会错」)
	var vh: float = float(get_viewport().get_visible_rect().size.y)
	var sep: float = sep_raw * (720.0 / maxf(vh, 1.0))

	# ── 徽章行宽（按常量算，与布局代码同源）──
	var cols: int = RB.HEAD_COLS
	var row_w: float = float(cols - 1) * RB.HEAD_ITEM_STEP + RB.HEAD_ITEM_SZ
	_ok("① ★徽章行宽 ≤ 相邻单位间距 × 1.3 (行宽 %.0f / 间距 %.0f, 视口高 %.0f)" % [row_w, sep, vh],
		row_w <= sep * 1.3,
		"%.1f 倍" % (row_w / maxf(sep, 1.0)))
	_ok("② ★容量 6（网格 %d 列 × %d 行）" % [cols, int(ceil(6.0 / float(cols)))],
		RB.HEAD_ROW_CAP == 6 and cols >= 2)

	# ── 真的摆一行 6 项，逐对查重叠 ──
	var u: Dictionary = s._spawn._make_unit("basic", "left", o)
	u["alive"] = true
	s._units.append(u)
	var items: Array = []
	for i in range(6):
		items.append({"icon": "res://assets/sprites/vfx/crystal-shard.png",
			"tint": Color(1, 1, 1), "n": i + 1, "sz": 32.0})
	s._layout_head_row(u, "_hbrow_stack", items, Vector2(640, 360), -34.0, true, false)
	await get_tree().process_frame
	var pool: Array = u.get("_hbrow_stack", [])
	var shown: Array = []
	for b in pool:
		if is_instance_valid(b) and b.visible:
			shown.append(Rect2(b.position, Vector2(RB.HEAD_ITEM_SZ, RB.HEAD_ITEM_SZ)))
	_ok("④ ★分母: 6 项真的都建出来且可见(建出 %d 个)" % shown.size(), shown.size() == 6,
		"%d 个" % shown.size())
	var hits: Array = []
	for i in range(shown.size()):
		for j in range(i + 1, shown.size()):
			var ra: Rect2 = shown[i]
			var rb2: Rect2 = shown[j]
			if ra.intersects(rb2):
				hits.append("#%d↔#%d" % [i, j])
	_ok("③ ★满 6 项时【每一项互不重叠】", hits.is_empty(),
		"%d 对重叠: %s" % [hits.size(), str(hits.slice(0, 5))])

	# ── ⑤ ★两行之间也不许撞 ──
	# 这条是【补上来的】: 上面 ①③ 只看单行内部, 而叠层行改成网格后会**向上长**
	# (3 项以内 1 行底 -34, 4 项起 2 行顶跑到 -62), 状态行原本钉死在 -74、图标 26px 高
	# ⇒ 两行**重叠 12px**。单行门禁全绿也照样撞 —— 所以必须走 `_layout_head_badges`
	# 这个【真入口】(不是直接调 _layout_head_row), 让它自己算状态行该放哪。
	var u2: Dictionary = s._spawn._make_unit("basic", "left", o)
	u2["alive"] = true
	u2["pos"] = o
	# 4 个叠层(逼出 2 行) + 2 个状态图标, 都走真实字段, 不手搓 items
	u2["stacks"] = {"electric": 3, "ink": 4, "crystal": 5}
	u2["cyber_ai_charge"] = 2
	u2["hunt_mark_until"] = s._t + 99.0
	u2["hijacked"] = true
	s._units.append(u2)
	s._layout_head_badges(u2)
	await get_tree().process_frame
	var rs: Array = []
	var rt: Array = []
	for b in u2.get("_hbrow_stack", []):
		if is_instance_valid(b) and b.visible:
			rs.append(Rect2(b.position, Vector2(RB.HEAD_ITEM_SZ, RB.HEAD_ITEM_SZ)))
	for b in u2.get("_hbrow_status", []):
		if is_instance_valid(b) and b.visible:
			rt.append(Rect2(b.position, Vector2(RB.HEAD_ITEM_SZ, RB.HEAD_ITEM_SZ)))
	_ok("⑤a ★分母: 叠层 4 个 + 状态 2 个都建出来了(实测 %d + %d)" % [rs.size(), rt.size()],
		rs.size() == 4 and rt.size() == 2)
	var cross: Array = []
	for a in rs:
		for c in rt:
			if (a as Rect2).intersects(c as Rect2):
				cross.append("%.0f↔%.0f" % [(a as Rect2).position.y, (c as Rect2).position.y])
	_ok("⑤b ★叠层行(2 行) 与 状态行 之间不重叠", cross.is_empty(),
		"%d 对撞上: %s" % [cross.size(), str(cross.slice(0, 4))])

	# ── ⑥ 弹入动效: 必须真的过冲, 且过冲峰值仍塞得进格子 ──
	# 两头都要守:
	#   · 不过冲 = 白写。我第一版 `lerp(0.4,1,pk)+sin(pk*PI)*k` 的峰值只有 0.86 —— **根本没冲过 1**
	#     (sin 峰在 pk=0.5, 那时基底才 0.7)。所以这里断言峰值 > 1。
	#   · 过冲太大 = 弹的那 0.2 秒里撞上邻居。所以断言 峰值 × 格内边长 < 列距/行距。
	# 曲线是【纯时间函数】(刻意不用 tween: 徽章每帧重排+节点复用, 且无头 CI 下 tween 推进不稳),
	# 所以能在测试里直接扫出峰值, 不用等演出。
	# ★★★量【节点上真实的 scale】, 不许在测试里抄一份同样的公式 ——
	#   抄公式 = 恒真式: 产品那边公式改坏了(比如改回不过冲的那版), 测试自己算自己的照样绿。
	#   做法: 拨动 `_t` 反复调真入口 `_layout_head_badges`, 读回 b.scale。
	var u3: Dictionary = s._spawn._make_unit("basic", "left", o)
	u3["alive"] = true
	u3["pos"] = o
	u3["stacks"] = {"electric": 1}
	s._units.append(u3)
	var t0: float = s._t
	s._layout_head_badges(u3)          # 第一次: 内容变了 ⇒ 打上 pop_t0
	var bp = (u3.get("_hbrow_stack", []) as Array)[0]
	var peak: float = 0.0
	var peak_at: float = 0.0
	var at_end: float = -1.0
	for i in range(121):
		var frac: float = float(i) / 100.0          # 扫到 1.2 倍时长, 顺带验落回 1.0
		s._t = t0 + frac * RB.HEAD_POP_T
		s._layout_head_badges(u3)                   # 内容没变 ⇒ pop_t0 不重置
		var v: float = float(bp.scale.x)
		if v > peak:
			peak = v
			peak_at = frac
		if i == 120: at_end = v
	s._t = t0
	_ok("⑥a ★弹入真的过冲(实测节点 scale 峰值 %.3f 倍 @ 时长的 %.0f%%)" % [peak, peak_at * 100.0],
		peak > 1.02,
		"峰值只有 %.3f —— 没冲过 1 就是没动效(我第一版就栽在这: sin 峰在 50%% 而基底才 0.7)" % peak)
	_ok("⑥c ★弹完落回 1.0(实测 %.4f)" % at_end, absf(at_end - 1.0) < 0.001,
		"结束时是 %.4f, 没归位" % at_end)
	var foot: float = peak * RB.HEAD_ITEM_SZ
	var step_min: float = minf(RB.HEAD_ITEM_STEP, RB.HEAD_ROW_STEP)
	_ok("⑥b ★过冲峰值仍塞得进格子(%.2f px < 间距 %.0f)" % [foot, step_min], foot < step_min,
		"弹到 %.2f px 超过间距 %.0f —— 弹的时候会撞邻居" % [foot, step_min])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 头顶徽章几何" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
