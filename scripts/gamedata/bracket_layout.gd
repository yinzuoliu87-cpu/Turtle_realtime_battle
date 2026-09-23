extends RefCounted
## bracket_layout.gd — 桶地图的版式（纯计算，不碰节点树）(E-B2, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  ★★版式 = **左右镜像、决赛在正中**（用户 2026-09-23 给的世界杯晋级图）
## ══════════════════════════════════════════════════════════════════════
## 用户原话：「这个也可以参考看看，**但我们是横屏的**」。
## 参考图顶部那一行标签就是结论：`32强 | 16强 | 8强 | 半决赛 | 决赛 | 半决赛 | 8强 | 16强 | 32强`
## —— 两侧各自向中间收，决赛在正中。
##
## ★我第一版照 LoL Worlds 做的是**单向三列**，方向错了。横屏该用镜像，而且不只是好看：
##
##   | 32 人桶 | 首轮节点 | 需要高度 |
##   |---|---|---|
##   | 单向 | 16 场竖着排 | ≈1136px ⇒ **必须拖** |
##   | 镜像 | 每侧 8 场    | ≈536px  ⇒ **720 屏放得下** |
##
##   镜像把高度砍掉一半、用宽度换 —— 而横屏正好是宽的多、高的少。
##
## ══════════════════════════════════════════════════════════════════════
##  比例：量的，不是拍的
## ══════════════════════════════════════════════════════════════════════
## 从 Worlds 2024 官方对阵图（1280×720 帧，亮像素带统计）量到的两条还继续用：
##   · 节点是**横条**不是卡片，高 ≈39px = 屏高 5.4%
##   · **同半区两场间隔 32px；半区之间 94px —— 正好 3 倍**（分组全靠留白，一个框不画）
## 列间距不照 LoL 那个 26%：镜像布局列数翻倍（2R−1 列），得按屏宽反算。

const _B := preload("res://scripts/gamedata/bracket.gd")

const DESIGN := Vector2(1280.0, 720.0)
const ROW_H_RATIO := 0.054         # 节点条高 / 屏高（量自 Worlds）
const GAP_IN_HALF := 32.0          # 同半区两场之间
const GAP_HALF_MULT := 3.0         # ★半区之间 = 同半区的 3 倍
const SIDE_PAD := 28.0             # 左右边距
const NODE_MIN_W := 104.0          # 节点条最窄到这里（再窄写不下名字）


static func row_h() -> float:
	return DESIGN.y * ROW_H_RATIO


## 镜像布局的列数：两侧各 R−1 轮 + 中间决赛 = 2R−1。
static func columns(n: int) -> int:
	var r := _B.rounds_for(n)
	return maxi(0, r * 2 - 1)


## 列间距与节点宽：按屏宽**反算**，不是写死 ——
## 4 人桶只有 3 列（宽松），32 人桶有 9 列（紧），同一套比例撑不住两头。
static func col_gap(n: int) -> float:
	var c := columns(n)
	if c <= 1:
		return 0.0
	return (DESIGN.x - SIDE_PAD * 2.0) / float(c)


static func node_w(n: int) -> float:
	return maxf(NODE_MIN_W, col_gap(n) * 0.86)


## ─────────────────────────────────────────────────────────────
## 一场对局在哪一侧。★左半区 = 坑位前一半；右半区 = 后一半。
## 决赛（末轮）不属于任何一侧，它在正中。
## ─────────────────────────────────────────────────────────────
const SIDE_LEFT := 0
const SIDE_RIGHT := 1
const SIDE_CENTER := -1
static func side_of(n: int, r: int, m: int) -> int:
	var total := _B.rounds_for(n)
	if r >= total:
		return SIDE_CENTER
	var cnt := _B.matches_in_round(n, r)
	return SIDE_LEFT if m < cnt / 2 else SIDE_RIGHT


## 这一场在**它那一侧**里是第几场（0 起）。
static func idx_in_side(n: int, r: int, m: int) -> int:
	var cnt := _B.matches_in_round(n, r)
	return m if m < cnt / 2 else m - cnt / 2


## 这一侧这一轮有几场。
static func matches_per_side(n: int, r: int) -> int:
	var total := _B.rounds_for(n)
	if r >= total:
		return 1
	return maxi(1, _B.matches_in_round(n, r) / 2)


## 第 r 轮（1 起）第 m 场（0 起）的矩形。
static func node_rect(n: int, r: int, m: int) -> Rect2:
	var total := _B.rounds_for(n)
	if r < 1 or r > total or m < 0 or m >= _B.matches_in_round(n, r):
		return Rect2()
	var h := row_h()
	var w := node_w(n)
	var gap := col_gap(n)
	var sd := side_of(n, r, m)
	var x := 0.0
	if sd == SIDE_LEFT:
		x = SIDE_PAD + float(r - 1) * gap
	elif sd == SIDE_RIGHT:
		x = DESIGN.x - SIDE_PAD - float(r - 1) * gap - w
	else:
		x = (DESIGN.x - w) * 0.5              # 决赛居中
	return Rect2(Vector2(x, _center_y(n, r, m) - h * 0.5), Vector2(w, h))


## 这一场的中心 y。
## ★第一轮按节距铺满**本侧**；后面每一轮取本侧两个来源的中点
##   —— "两场的赢家会碰"这件事在视觉上成立，全靠这条。
## ★决赛取整张图的竖向正中。
static func _center_y(n: int, r: int, m: int) -> float:
	var h := row_h()
	var total := _B.rounds_for(n)
	if r >= total:
		return _span_mid(n)                   # 决赛: 正中
	if r == 1:
		var i := idx_in_side(n, 1, m)
		var per := matches_per_side(n, 1)
		var pitch := h + GAP_IN_HALF
		## ★本侧内部再分上下两个 1/4 区时, 中间那道缝拉成 3 倍(与参考图一致)
		var extra := 0.0
		if per >= 4 and i >= per / 2:
			extra = GAP_IN_HALF * (GAP_HALF_MULT - 1.0)
		return h * 0.5 + float(i) * pitch + extra
	return (_center_y(n, r - 1, m * 2) + _center_y(n, r - 1, m * 2 + 1)) * 0.5


## 首轮铺出来的竖向跨度的中点（决赛落这里）。
static func _span_mid(n: int) -> float:
	var per := matches_per_side(n, 1)
	if per <= 0:
		return DESIGN.y * 0.5
	var h := row_h()
	var pitch := h + GAP_IN_HALF
	var extra := GAP_IN_HALF * (GAP_HALF_MULT - 1.0) if per >= 4 else 0.0
	var last := h * 0.5 + float(per - 1) * pitch + extra
	return (h * 0.5 + last) * 0.5


## 整张图的包围盒。
## ★宽度要**量真节点**，不能图省事返回 `DESIGN.x` —— 那样 `needs_pan()` 永远为真
##   （1280 > 1280−48），4 人桶也会被判成"要拖"。门禁当场拓出来了。
static func content_size(n: int) -> Vector2:
	var total := _B.rounds_for(n)
	if total <= 0:
		return Vector2.ZERO
	var left := INF
	var right := -INF
	var bot := 0.0
	for r in range(1, total + 1):
		for m in range(_B.matches_in_round(n, r)):
			var rc: Rect2 = node_rect(n, r, m)
			left = minf(left, rc.position.x)
			right = maxf(right, rc.end.x)
			bot = maxf(bot, rc.end.y)
	if left == INF:
		return Vector2.ZERO
	return Vector2(right - left, bot)


## 轮次标签：`32强 / 16强 / 8强 / 半决赛 / 决赛`（参考图顶部那一行）。
## ★末轮=决赛、倒数第二=半决赛、再前一轮=8强，更早的按"还剩几个人"叫。
static func round_label(n: int, r: int) -> String:
	var total := _B.rounds_for(n)
	if r < 1 or r > total:
		return ""
	if r == total:
		return "决赛"
	if r == total - 1:
		return "半决赛"
	if r == total - 2:
		return "8强"
	return "%d强" % (_B.slots_for(n) >> (r - 1))


## 塞进视口要缩放多少。★上限 1.0 —— 小桶不放大（放大像素字会糊，而这屏全是字）。
static func fit_scale(n: int, viewport: Vector2, pad: float = 24.0) -> float:
	var cs := content_size(n)
	if cs.x <= 0.0 or cs.y <= 0.0:
		return 1.0
	return minf(1.0, minf((viewport.x - pad * 2.0) / cs.x,
		(viewport.y - pad * 2.0) / cs.y))


## 这个规模需要拖动吗？
## ★★判据 = **按 1:1 画放不放得下**，不是"人数多不多"。
##   镜像布局之后 32 人桶的高度从 ≈1136 降到 ≈536 —— 这条的答案也跟着变了。
static func needs_pan(n: int, viewport: Vector2, pad: float = 24.0) -> bool:
	var cs := content_size(n)
	return cs.x > viewport.x - pad * 2.0 or cs.y > viewport.y - pad * 2.0


## 让某一场落在视口正中所需的画布偏移。
static func center_offset_on(n: int, r: int, m: int, viewport: Vector2, sc: float) -> Vector2:
	var rect := node_rect(n, r, m)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	return viewport * 0.5 - (rect.position + rect.size * 0.5) * sc
