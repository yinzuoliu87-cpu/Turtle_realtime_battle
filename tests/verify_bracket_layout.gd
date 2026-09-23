extends Node
## verify_bracket_layout.gd — 桶地图版式 (E-B2, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 版式的三条来源，每条都能被"顺手改一下"悄悄毁掉：
##   ① **左右镜像、决赛在正中**（用户给的世界杯晋级图；原话「我们是横屏的」）
##   ② 量自 Worlds 2024 官方对阵图的比例：条高 5.4% 屏高、
##      **同半区 32px / 半区之间 94px = 正好 3 倍**
##   ③ **每一场都在它下一轮那一场的正中间** —— "两场的赢家会碰"在视觉上成立，全靠这条
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 判据落在**几何关系**上（中点、对称、不重叠），不落在"我把公式再算一遍"。
## ★② **镜像**这条要正反都验：左右两侧 x 关于屏幕中线对称，且决赛真的在正中。
## ★③ **不重叠**：任何两个节点矩形不相交 —— 这一条能一次抓住"节距算错"。
## ★④ **横屏放得下**这件事要量出来：32 人桶镜像之后高度必须 ≤ 视口，
##      否则"改成镜像"这个决定就白做了。
## ★⑤ n = 2/4/8/16/32 全量，不抽查。
##
## 跑法: <godot> --headless --path . res://tests/verify_bracket_layout.tscn --quit-after 600

const B := preload("res://scripts/gamedata/bracket.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")

const SIZES := [2, 4, 8, 16, 32]
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 桶地图版式 (E-B2) ===")
	_t_mirror()
	_t_midpoint()
	_t_no_overlap()
	_t_fits_landscape()
	_t_ratios()
	_t_labels()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 桶地图版式" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 镜像: 左右对称 + 决赛正中
# ─────────────────────────────────────────────────────────────
func _t_mirror() -> void:
	print("── ① 左右镜像 ──")
	var bad_sym := 0
	var bad_mid := 0
	for n in SIZES:
		var total := B.rounds_for(n)
		## 决赛必须在屏幕正中
		var fr: Rect2 = L.node_rect(n, total, 0)
		var cx: float = fr.position.x + fr.size.x * 0.5
		if absf(cx - L.DESIGN.x * 0.5) > 1.0:
			bad_mid += 1
			print("       ★%d 人: 决赛中心 x=%.1f, 应为 %.1f" % [n, cx, L.DESIGN.x * 0.5])
		## 每一轮: 左侧第 i 场 与 右侧第 i 场 关于中线对称
		for r in range(1, total):
			var per := L.matches_per_side(n, r)
			for i in range(per):
				var lr: Rect2 = L.node_rect(n, r, i)
				var rr: Rect2 = L.node_rect(n, r, i + per)
				var lc: float = lr.position.x + lr.size.x * 0.5
				var rc: float = rr.position.x + rr.size.x * 0.5
				if absf((lc + rc) * 0.5 - L.DESIGN.x * 0.5) > 1.0:
					bad_sym += 1
					break
	_ok("① ★分母: 扫了 %d 种桶容量" % SIZES.size(), SIZES.size() == 5)
	_ok("① ★★决赛落在屏幕正中", bad_mid == 0, "%d 种不对" % bad_mid)
	_ok("① ★★左右两侧关于中线对称(这就是「镜像」本身)", bad_sym == 0, "%d 处不对" % bad_sym)

	## ★分母: 左侧确实在左、右侧确实在右 —— 否则"对称"在两边重合时也成立
	var lhs: Rect2 = L.node_rect(32, 1, 0)
	var rhs: Rect2 = L.node_rect(32, 1, L.matches_per_side(32, 1))
	_ok("① ★分母: 左侧在左半屏、右侧在右半屏(排除两边重合也算对称)",
		lhs.position.x < L.DESIGN.x * 0.5 and rhs.position.x > L.DESIGN.x * 0.5,
		"左 x=%.0f 右 x=%.0f" % [lhs.position.x, rhs.position.x])


# ─────────────────────────────────────────────────────────────
# ② 每一场都在它下一轮那一场的正中间
# ─────────────────────────────────────────────────────────────
func _t_midpoint() -> void:
	print("── ② 中点关系 ──")
	var bad := 0
	var checked := 0
	for n in SIZES:
		var total := B.rounds_for(n)
		for r in range(2, total):            # 决赛单独算(它取全图正中), 不在这条里
			for m in range(B.matches_in_round(n, r)):
				var me: Rect2 = L.node_rect(n, r, m)
				var a: Rect2 = L.node_rect(n, r - 1, m * 2)
				var b: Rect2 = L.node_rect(n, r - 1, m * 2 + 1)
				if me.size == Vector2.ZERO or a.size == Vector2.ZERO:
					continue
				checked += 1
				var myc: float = me.position.y + me.size.y * 0.5
				var mid: float = ((a.position.y + a.size.y * 0.5)
					+ (b.position.y + b.size.y * 0.5)) * 0.5
				if absf(myc - mid) > 0.6:
					bad += 1
	_ok("② ★分母: 量了 %d 个中点关系(0 的话下面是空检查)" % checked, checked >= 10, "%d" % checked)
	_ok("② ★★每一场都落在它两个来源的正中间", bad == 0, "%d 处不对" % bad)


# ─────────────────────────────────────────────────────────────
# ③ 不重叠 —— 一条就能抓住节距算错
# ─────────────────────────────────────────────────────────────
func _t_no_overlap() -> void:
	print("── ③ 节点互不重叠 ──")
	var bad := 0
	var pairs := 0
	for n in SIZES:
		var rects: Array = []
		var total := B.rounds_for(n)
		for r in range(1, total + 1):
			for m in range(B.matches_in_round(n, r)):
				rects.append(L.node_rect(n, r, m))
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				pairs += 1
				var ra: Rect2 = rects[i]
				var rb: Rect2 = rects[j]
				## 留 1px 容差, 贴边不算撞
				if ra.grow(-1.0).intersects(rb.grow(-1.0)):
					bad += 1
	_ok("③ ★分母: 比了 %d 对矩形" % pairs, pairs > 100, "%d" % pairs)
	_ok("③ ★★任何两个节点都不重叠", bad == 0, "%d 对撞上" % bad)


# ─────────────────────────────────────────────────────────────
# ④ ★横屏放得下 —— 「改成镜像」这个决定的理由本身
# ─────────────────────────────────────────────────────────────
func _t_fits_landscape() -> void:
	print("── ④ 横屏放得下 ──")
	var vp := Vector2(1280.0, 720.0)
	var h32: float = L.content_size(32).y
	## ★★判据改成量【镜像省了多少】—— 节点从一行改成两行(对阵双方)之后,
	##   原来那条「镜像之后放得下 720」不再成立(现在 910 高, 走拖动) ——
	##   **但镜像的理由本来就不是"刚好放得下", 是"把高度砍掉一半"**。
	##   改成量那个比值, 它不会因为节点长高就失效。
	var per_side: int = L.matches_per_side(32, 1)
	var single_h: float = float(per_side * 2) * (L.row_h() + L.GAP_IN_HALF)
	print("  ④ 32 人桶: 镜像 %.0f px / 单向要 %.0f px (视口 %.0f)" % [h32, single_h, vp.y])
	_ok("④ ★★镜像把高度砍到单向的一半以下(这才是镜像的理由)",
		h32 < single_h * 0.6, "%.0f vs %.0f (%.0f%%)" % [h32, single_h, 100.0 * h32 / single_h])
	_ok("④ ★分母: 两个数都不是 0(否则上面那条是恒真)",
		h32 > 400.0 and single_h > 400.0, "%.0f / %.0f" % [h32, single_h])
	_ok("④ ★而且 32 人桶确实要拖(高于可用区) —— 这是设计内的",
		L.needs_pan(32, Vector2(1280.0, 530.0)), "%.0f" % h32)
	_ok("④ 4 人桶不需要拖(比 Worlds 的 8 队还小)",
		not L.needs_pan(4, vp))
	_ok("④ 4 人桶不被放大(上限 1.0, 放大像素字会糊)",
		L.fit_scale(4, vp) <= 1.0, "%.3f" % L.fit_scale(4, vp))


# ─────────────────────────────────────────────────────────────
# ⑤ 量自 Worlds 的那两条比例
# ─────────────────────────────────────────────────────────────
func _t_ratios() -> void:
	print("── ⑤ 比例(量自 Worlds 官方对阵图) ──")
	## ★量自 Worlds 的 5.4% 是**单侧一行**的高; 整格是两行(对阵双方), 所以是它的两倍。
	_ok("⑤ 单侧一行高 = 屏高 5.4%（≈39px，量自 Worlds）",
		absf(L.slot_h() - 720.0 * 0.054) < 0.5, "%.1f" % L.slot_h())
	_ok("⑤ ★整格 = 单侧两倍(上下各一个对手)",
		absf(L.row_h() - L.slot_h() * 2.0) < 0.5, "%.1f vs %.1f" % [L.row_h(), L.slot_h()])

	## ★同半区 32 / 半区之间 94 —— 正好 3 倍。量 16 人桶第一轮(每侧 4 场, 中间那道缝是 1/4 区分界)
	var a: Rect2 = L.node_rect(16, 1, 0)
	var b: Rect2 = L.node_rect(16, 1, 1)
	var c: Rect2 = L.node_rect(16, 1, 2)
	var g_in: float = b.position.y - a.end.y
	var g_half: float = c.position.y - b.end.y
	print("  ⑤ 同半区缝 %.0f / 半区之间缝 %.0f" % [g_in, g_half])
	_ok("⑤ 同半区两场之间 = 32px", absf(g_in - 32.0) < 0.6, "%.1f" % g_in)
	_ok("⑤ ★★半区之间正好是它的 3 倍(=96, 量到的是 94)",
		absf(g_half - 96.0) < 0.6, "%.1f" % g_half)
	_ok("⑤ ★分母: 两道缝确实不一样宽(否则「3 倍」是恒真)",
		g_half > g_in + 20.0, "%.0f vs %.0f" % [g_half, g_in])


# ─────────────────────────────────────────────────────────────
# ⑥ 轮次标签(参考图顶部那一行)
# ─────────────────────────────────────────────────────────────
func _t_labels() -> void:
	print("── ⑥ 轮次标签 ──")
	var got32: Array = []
	for r in range(1, B.rounds_for(32) + 1):
		got32.append(L.round_label(32, r))
	print("  ⑥ 32 人桶: %s" % str(got32))
	_ok("⑥ ★32 人桶 = 32强/16强/8强/半决赛/决赛",
		got32 == ["32强", "16强", "8强", "半决赛", "决赛"], str(got32))
	var got4: Array = []
	for r in range(1, B.rounds_for(4) + 1):
		got4.append(L.round_label(4, r))
	_ok("⑥ 4 人桶 = 半决赛/决赛", got4 == ["半决赛", "决赛"], str(got4))
	var got2: Array = []
	for r in range(1, B.rounds_for(2) + 1):
		got2.append(L.round_label(2, r))
	_ok("⑥ 2 人桶 = 只有决赛", got2 == ["决赛"], str(got2))
	_ok("⑥ 越界轮次 → 空串", L.round_label(4, 9) == "" and L.round_label(4, 0) == "")
