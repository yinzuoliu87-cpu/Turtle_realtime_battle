class_name PullCurve
extends RefCounted
## 铁链把自己拉向目标的运动曲线(精英小将铁锁 / 近战小将人体浪板共用)。
## 用户 2026-11-11:「其实就是你把自己拉向对面，其实是有个由快到中速这样一个…变化…先拉…抓住个绳子，然后你将自己扯向对面，
##   首先是一个快的一个动作，然后慢慢的到这个中中等的这个平滑…然后再到这个敌人身上就是落脚」「对于精英小将的那个铁锁，就那个铁链一样的道理」;
##   「将自己拉向对方的时候，其实并不是直直的这样子落下来，而是应该有一个横的这个加速度…肯定是要向上面走一点点的呀」。
## 速度: 起步 = 中速 × START_MULT, 前 EASE_SPAN 的时间里按二次曲线降到中速, 之后匀速到落点(约为平均速度的 2.4 倍 → 0.75 倍)。
##   平均速度不变 ⇒ 拉人时长照旧 = 距离 ÷ 拉速(EliteSystem.whip_pull_sec / HidingSystem.surf_pull_sec)。
## sim 路径(写单位 pos / height): 只用四则运算, 跨平台确定(tools/det_math_lint.py)。门禁 tests/verify_pull_curve.gd。
const START_MULT := 3.2
const EASE_SPAN := 0.45
## 近战俯冲起步往上带的幅度: s·(1-s)² 的峰值是 4/27(在 s = 1/3), 乘这个 ≈ 0.8 米。
const RISE_COEF := 5.4


## 0 ~ s 这段时间走过的「面积」(中速 = 1 的单位)
static func _area(s: float) -> float:
	var t: float = clampf(s, 0.0, 1.0)
	var k: float = minf(t, EASE_SPAN) / EASE_SPAN
	var m: float = 1.0 - k
	return t + (START_MULT - 1.0) * EASE_SPAN / 3.0 * (1.0 - m * m * m)


## 时间进度 s(0 ~ 1)→ 路程进度(0 ~ 1)
static func frac(s: float) -> float:
	return _area(s) / _area(1.0)


## 近战小将俯冲高度: 下落基线(先慢后快, h0 → h1)+ 起步往上带一点 ⇒ 先往上走一点再弧线落到目标身上
static func dive_height(s: float, h0: float, h1: float) -> float:
	var t: float = clampf(s, 0.0, 1.0)
	return h0 - (h0 - h1) * t * t + RISE_COEF * t * (1.0 - t) * (1.0 - t)
