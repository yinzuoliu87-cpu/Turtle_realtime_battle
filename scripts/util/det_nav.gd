class_name DetNav
extends RefCounted
## DetNav —— 绕障寻路的**确定性**实现(2026-10-10·方案书 `docs/plans/20261010-跨平台浮点确定性.md`)。
##
## 为什么不用 NavigationServer2D.map_get_path: 寻路图烘焙(NavMeshGenerator2D::bake)与 A* 查询
##   (NavMeshQueries2D::_query_task_search_polygon_connections)在 iOS 版引擎里都编成了 FMA(反汇编实测),
##   x86 版不是 ⇒ 同一张图、同一对起止点, 两台机器给出的路点末位不同 → 单位走向不同 → 回放分叉。
##   这是引擎 C++ 内部, GDScript 管不到 ⇒ 只能绕开不用。
##
## 做法: 障碍是 3 个椭圆(`battle._obstacles`), 寻路图里挖的洞就是它们的 14 边形(半径 + OBSTACLE_MARGIN)。
##   最短路一定贴着这些凸多边形的顶点走(可见图) ⇒
##   ① 起止点直连不被任何洞挡住 ⇒ 直接 [起, 止]
##   ② 否则 Dijkstra: 节点 = 洞的顶点 + 起止点; 边 = 不穿过任何洞内部的线段; 只保留「切线」边(最短路只会用到切线)。
##   全部只用 + - * / sqrt 与比较(DetMath 的规矩) ⇒ 各平台逐位一致。
##   与引擎寻路(optimize=true 的拉直路径)几何上是同一条最短路 —— 探针 `tests/_probe_det_nav.gd` 量过两者的偏差。
##
## 门禁开关: DetMath.raw = true ⇒ 退回引擎寻路(+ DetMath.perturb 扰动每个路点), 供 verify_determinism_ulp 做「加固前」对照。

var _polys: Array = []          # Array[PackedVector2Array], 每个凸多边形(顶点顺序一致)
var _nodes: PackedVector2Array = PackedVector2Array()     # 所有可用顶点
var _node_poly: PackedInt32Array = PackedInt32Array()     # 顶点属于哪个多边形
var _node_idx: PackedInt32Array = PackedInt32Array()      # 顶点在多边形里的下标
var _adj: Array = []            # 顶点间的可见切线边: _adj[i] = [[j, 距离], ...]
var _lo := Vector2.ZERO         # 可走矩形(寻路图外边界)
var _hi := Vector2.ZERO
var map_rid: RID                # raw 模式用的引擎寻路图

const _EPS := 1e-9


## polys: 每个洞的顶点(与烘焙寻路图时 add_obstruction_outline 传的同一组); lo/hi: 可走矩形。
func build(polys: Array, lo: Vector2, hi: Vector2) -> void:
	_polys = polys
	_lo = lo
	_hi = hi
	_nodes = PackedVector2Array()
	_node_poly = PackedInt32Array()
	_node_idx = PackedInt32Array()
	for pi in range(_polys.size()):
		var pts: PackedVector2Array = _polys[pi]
		for k in range(pts.size()):
			var v: Vector2 = pts[k]
			if v.x > lo.x and v.x < hi.x and v.y > lo.y and v.y < hi.y and not _inside_other(v, pi):
				_nodes.append(v)
				_node_poly.append(pi)
				_node_idx.append(k)
	_adj = []
	for i in range(_nodes.size()):
		_adj.append([])
	for i in range(_nodes.size()):
		for j in range(i + 1, _nodes.size()):
			var a: Vector2 = _nodes[i]
			var b: Vector2 = _nodes[j]
			if not _tangent_at(i, b) or not _tangent_at(j, a):
				continue
			if not _clear(a, b):
				continue
			var d: float = DetMath.dist(a, b)
			(_adj[i] as Array).append([j, d])
			(_adj[j] as Array).append([i, d])


## 顶点 v 是不是落在别的洞里(两个洞重叠时, 落在别人里面的顶点不能走)。
func _inside_other(v: Vector2, own: int) -> bool:
	for pi in range(_polys.size()):
		if pi != own and _inside(v, _polys[pi]):
			return true
	return false


## 严格在凸多边形内部(边上不算)。
func _inside(p: Vector2, pts: PackedVector2Array) -> bool:
	var n: int = pts.size()
	var sgn := 0
	for k in range(n):
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		var c: float = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		if c == 0.0:
			return false
		var s: int = 1 if c > 0.0 else -1
		if sgn == 0:
			sgn = s
		elif s != sgn:
			return false
	return true


## 从点 p 看过去, 第 i 个顶点是不是它所在多边形的「切点」(两条邻边一条朝向 p、一条背向 p, 或 p 在其延长线上)。
##   最短路只会在切点处拐弯 ⇒ 非切点的边全剪掉。
func _tangent_at(i: int, p: Vector2) -> bool:
	var pts: PackedVector2Array = _polys[_node_poly[i]]
	var n: int = pts.size()
	var k: int = _node_idx[i]
	var v: Vector2 = pts[k]
	var vp: Vector2 = pts[(k - 1 + n) % n]
	var vn: Vector2 = pts[(k + 1) % n]
	var c1: float = (v.x - vp.x) * (p.y - vp.y) - (v.y - vp.y) * (p.x - vp.x)
	var c2: float = (vn.x - v.x) * (p.y - v.y) - (vn.y - v.y) * (p.x - v.x)
	return (c1 >= 0.0) != (c2 >= 0.0) or c1 == 0.0 or c2 == 0.0


## 线段 ab 不穿过任何洞的内部(贴边、擦顶点都算通)。Cyrus–Beck: 求线段落在凸多边形里的参数区间 [t0, t1]。
func _clear(a: Vector2, b: Vector2) -> bool:
	for pts in _polys:
		if _cuts(a, b, pts):
			return false
	return true


func _cuts(a: Vector2, b: Vector2, pts: PackedVector2Array) -> bool:
	var n: int = pts.size()
	## 方向: 用第一个三角形的叉积定内侧(顶点顺序全局一致, 但不假设顺/逆时针)
	var o: float = (pts[1].x - pts[0].x) * (pts[2].y - pts[0].y) - (pts[1].y - pts[0].y) * (pts[2].x - pts[0].x)
	var t0 := 0.0
	var t1 := 1.0
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	for k in range(n):
		var e0: Vector2 = pts[k]
		var e1: Vector2 = pts[(k + 1) % n]
		## 内侧法向(朝多边形里面): o>0 时为左法向
		var nx: float = -(e1.y - e0.y)
		var ny: float = e1.x - e0.x
		if o < 0.0:
			nx = -nx
			ny = -ny
		var num: float = nx * (a.x - e0.x) + ny * (a.y - e0.y)    # a 在内侧 ⇒ >0
		var den: float = nx * dx + ny * dy
		if den == 0.0:
			if num <= 0.0:
				return false                                       # 平行且在外侧/边上 ⇒ 不进内部
			continue
		var t: float = -num / den
		if den > 0.0:
			t0 = maxf(t0, t)                                       # 进入
		else:
			t1 = minf(t1, t)                                       # 离开
		if t1 - t0 <= _EPS:
			return false
	return t1 - t0 > _EPS


## 点 p 若在某个洞里, 推到那个洞最近的边上(与引擎「起点不在图上 ⇒ 取最近的图上点」同义)。
func _snap_out(p: Vector2) -> Vector2:
	var q := Vector2(clampf(p.x, _lo.x, _hi.x), clampf(p.y, _lo.y, _hi.y))
	for pts in _polys:
		if _inside(q, pts):
			var best := q
			var bd := INF
			var n: int = (pts as PackedVector2Array).size()
			for k in range(n):
				var c: Vector2 = DetMath.seg_closest(q, pts[k], pts[(k + 1) % n])
				var d: float = DetMath.dist2(c, q)
				if d < bd:
					bd = d
					best = c
			q = best
	return q


## 从 a 走到 b 的路点(含起止)。raw 模式走引擎(加固前对照)。
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	if DetMath.raw:
		var pp: PackedVector2Array = NavigationServer2D.map_get_path(map_rid, a, b, true)
		if DetMath.perturb > 0:
			for k in range(pp.size()):
				pp[k] = DetMath._pv(pp[k])
		return pp
	var s: Vector2 = _snap_out(a)
	var g: Vector2 = _snap_out(b)
	if _clear(s, g):
		return PackedVector2Array([s, g])
	var n: int = _nodes.size()
	## 节点 n = 起点, n+1 = 终点
	var dist := PackedFloat64Array()
	dist.resize(n + 2)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n + 2)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n + 2)
	done.fill(0)
	var goal_vis := PackedFloat64Array()       # 顶点 → 终点 的距离(看不见 = INF)
	goal_vis.resize(n)
	goal_vis.fill(INF)
	for i in range(n):
		var v: Vector2 = _nodes[i]
		if _tangent_at(i, g) and _clear(v, g):
			goal_vis[i] = DetMath.dist(v, g)
	dist[n] = 0.0
	for i in range(n):
		var v2: Vector2 = _nodes[i]
		if _tangent_at(i, s) and _clear(s, v2):
			dist[i] = DetMath.dist(s, v2)
			prev[i] = n
	## Dijkstra(节点 ≤ 44, 线性取最小即可; 平手按下标小的先 —— 确定)
	while true:
		var u := -1
		var bu := INF
		for i in range(n + 2):
			if i == n:
				continue
			if done[i] == 0 and dist[i] < bu:
				bu = dist[i]
				u = i
		if u < 0 or u == n + 1:
			break
		done[u] = 1
		if goal_vis[u] < INF and dist[u] + goal_vis[u] < dist[n + 1]:
			dist[n + 1] = dist[u] + goal_vis[u]
			prev[n + 1] = u
		for e in (_adj[u] as Array):
			var j: int = e[0]
			var nd: float = dist[u] + float(e[1])
			if nd < dist[j]:
				dist[j] = nd
				prev[j] = u
	if prev[n + 1] < 0:
		return PackedVector2Array([s, g])          # 走不通(不该发生): 退回直线, 与引擎「无路径 ⇒ 直奔」同义
	var rev: Array = [g]
	var c: int = prev[n + 1]
	while c != n and c >= 0:
		rev.append(_nodes[c])
		c = prev[c]
	rev.append(s)
	rev.reverse()
	return PackedVector2Array(rev)
