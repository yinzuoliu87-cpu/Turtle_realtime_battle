class_name ArenaShape
extends RefCounted
## 竞技场【形状】—— 纯几何, 不依赖战斗状态。
##
## ★用户 2026-10-03:「要么中间就是可活动的陆地，外边为海，以此为边界」「**圆的岛吧**」
##
## 【为什么要有这个文件】可活动区原来是**矩形**, 因为钳位是
##   `pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)`(x/y 各自独立), 而且
##   **同一对代码在 13 个文件里抄了 31 份**(各自带不同的内缩量 0/14/20/30/40/50/60/80 px)。
##   ⇒ 海岸线只能是矩形, 画出来是「一张地毯」不是一座岛。
##   memory `fb-hand-rolled-copies-drift`: 就地手写而不调标准函数 = 抄一次永远落后。
##
## 【形状】超椭圆 |dx|^N + |dy|^N <= 1, 半轴 = 矩形半宽/半高 再各减 pad。
##   · N = 2 → **正椭圆**(最圆, 面积 = 矩形的 π/4 ≈ 78.5%)
##   · N = 4 → 圆角方(squircle, 保面积 ≈ 87%)
##   · N 很大 → 退回矩形(等价于改之前的行为)
##   ⇒ 想调「多圆 / 留多少活动面积」只动 `RealtimeBattle3DScene.ARENA_SHAPE_N` 一个数。
##
## ★★这里**不放** ARENA 本身 —— 战场矩形是主场景的常量, 本文件只做形状数学,
##   rect 由调用方传进来。这样地图生成器 `tools/gen_arena_map.py` 与门禁也能用同一套口径。
##
## ⚠ 放在 `scripts/util/` 而不是主场景: CLAUDE.md §5「不在 `_sim_step` 调用链上的不进主文件」——
##   这是纯几何工具, 全项目复用, 属于基础层。


## ★形状指数(本项目唯一一处)。2=正椭圆(面积 π/4≈78.5%) / 4=圆角方(≈87%) / 很大=退回矩形。
## ⚠ 改它要同步改 `tools/gen_arena_map.py` 的 `ISLE`(画出来的岛) —— 不一致就又回到
##   「看得见的和走得到的不是一个东西」; 判据 `tests/verify_island_boundary.gd` 守着这条。
const N := 2.0


## 点在不在竞技场形状里。调用方只需给 rect, 形状由本文件说了算。
static func in_rect_shape(p: Vector2, rect: Rect2, pad: float = 0.0, pad_y: float = -1.0) -> bool:
	return inside(p, rect, N, pad, pad_y)


## 把点钳进竞技场形状。调用方只需给 rect。
static func clamp_in(p: Vector2, rect: Rect2, pad: float = 0.0, pad_y: float = -1.0) -> Vector2:
	return clamp_to(p, rect, N, pad, pad_y)


## 超椭圆的"归一化半径": <=1 在形状内, >1 在外。
static func t_of(p: Vector2, rect: Rect2, n: float, pad: float, pad_y: float) -> float:
	var c: Vector2 = rect.position + rect.size * 0.5
	var py_: float = pad if pad_y < 0.0 else pad_y
	var rx: float = maxf(1.0, rect.size.x * 0.5 - pad)
	var ry: float = maxf(1.0, rect.size.y * 0.5 - py_)
	return pow(absf((p.x - c.x) / rx), n) + pow(absf((p.y - c.y) / ry), n)


## 点在不在形状里(pad = 往内缩的像素; pad_y < 0 表示跟随 pad)。
static func inside(p: Vector2, rect: Rect2, n: float, pad: float = 0.0, pad_y: float = -1.0) -> bool:
	return t_of(p, rect, n, pad, pad_y) <= 1.0


## 把一个点钳进形状 —— 沿着「从中心出发」的方向投到边上, **不是**按轴分别夹。
## ★按轴夹会把角上的点推到角里(那正是矩形的来源); 径向投影才给得出圆的岸线。
static func clamp_to(p: Vector2, rect: Rect2, n: float, pad: float = 0.0, pad_y: float = -1.0) -> Vector2:
	var tt: float = t_of(p, rect, n, pad, pad_y)
	if tt <= 1.0:
		return p
	var c: Vector2 = rect.position + rect.size * 0.5
	var py_: float = pad if pad_y < 0.0 else pad_y
	var rx: float = maxf(1.0, rect.size.x * 0.5 - pad)
	var ry: float = maxf(1.0, rect.size.y * 0.5 - py_)
	## ★径向投影: 把归一化坐标按 k 缩回边上, 再换算回像素。
	##   不要写成 `(p.x-c.x)/rx*k*rx` —— 先除再乘回同一个数是白绕一圈, 还平白引入浮点次序差异。
	var k: float = pow(tt, -1.0 / n)
	return Vector2(c.x + (p.x - c.x) * k, c.y + (p.y - c.y) * k)
