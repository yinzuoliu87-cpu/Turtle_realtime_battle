extends Node
## verify_arena_density.gd — 装饰的【成组度】与【中空外密】
##
## ★★为什么要这条: 我把装饰从「写死的坐标表」改成了「簇心 + 小半径散布」,
##   但**没有任何东西在量它** —— 改没改成、改到什么程度, 全凭我说。
##   而参考那边是有硬靶子的: 咩咩实测 Clark-Evans **R = 0.66**(23 张里 22 张 < 1 = 成组),
##   我们改前是 **R = 1.13**(比随机还均匀)。
##   (memory `fb-gate-must-measure-requirement-not-my-hook`: 要量需求, 不是量我插的标记。)
##
## ★Clark-Evans R = 实测最近邻平均距离 ÷ 同密度随机分布的期望值
##     期望 = 0.5 / sqrt(n / A)
##   R < 1 成组 · R ≈ 1 随机 · R > 1 比随机还均匀(= 排成行列那种)
##
## ★★判据量的是**产品真的摆出来的那些节点**, 不是我重算一遍坐标 ——
##   重算就又成了"插一行数一行"。做法: 建真战斗场, 把装饰层的子节点位置捞出来。
##
## ⚠ 本条只对**主题**生效。`base`(现状·已验收) 走的还是那张写死的坐标表, 不在此列 ——
##   它那个 R=1.13 是已知且被接受的现状, 不该被这条判据判红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")

## 参考靶子(咩咩实测, 见 docs/plans/ref/20261002-咩咩启示录地图参考.md)
const R_REF := 0.66
## 放行上限: 改前是 1.13(比随机还均匀)。要求**明确落到随机以下**, 但不强求一步到 0.66。
const R_MAX := 0.95

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 装饰成组度与中空外密 ===")
	var keep: String = AT.active
	AT.active = AT.V1_DUSK                      # 拿一版代表(四版共用同一套摆放逻辑)

	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame

	## ── 捞出装饰层真的摆出来的位置 ──────────────────────────────
	var pts: PackedVector2Array = PackedVector2Array()
	var A: Rect2 = RB.ARENA
	var inside := 0
	## ★★★只量**主题环**那一层(具名容器 `ThemeRing`), 不是全场所有精灵。
	##   第一版捞全场(214 个: 边框密植 + 中景 + 远景光斑 + 本层) ⇒ 被测对象被稀释:
	##   把本层散布半径从 118 改到 900(簇彻底消失), **判据照样绿** —— 反向验证当场抓到。
	##   (memory `fb-gate-subject-never-constructed`)
	var ring: Node = _find_named(s._world, "ThemeRing")
	_ok("★★分母: 找得到主题环容器 ThemeRing(找不到 = 这条判据什么都没量)", ring != null)
	if ring == null:
		_done(s, keep)
		return
	for n in _all_sprites(ring):
		var p: Vector3 = n.global_position
		var p2 := Vector2(p.x, p.z)             # 世界 xz ↔ 场地平面
		pts.append(p2)
	_ok("★分母: 场上真的有装饰精灵(0 的话下面全是空检查)", pts.size() >= 12,
		"%d 个" % pts.size())
	if pts.size() < 12:
		_done(s, keep)
		return

	## ── ① Clark-Evans R ────────────────────────────────────────
	var rr: float = _clark_evans(pts)
	_ok("①★★成组度 Clark-Evans R < %.2f（改前 1.13 = 比随机还均匀；参考 %.2f）" % [R_MAX, R_REF],
		rr < R_MAX, "实测 R = %.3f  (n=%d)" % [rr, pts.size()])

	## ── ② 中空外密: 战斗区内的件数应当远少于区外 ───────────────
	for p in pts:
		if A.has_point(p):
			inside += 1
	var outside: int = pts.size() - inside
	_ok("②★分母: 区外真的有装饰(0 的话下面恒真)", outside > 0, "区外 %d 个" % outside)
	_ok("②★★中空外密: 战斗区内的装饰件数 < 区外的 1/3（参考: 战斗区几乎是空的）",
		float(inside) < float(outside) / 3.0,
		"区内 %d / 区外 %d" % [inside, outside])

	_done(s, keep)


## 按名字找节点(递归)。
func _find_named(root: Node, nm: String) -> Node:
	if root == null:
		return null
	for c in root.get_children():
		if c.name == nm:
			return c
		var r: Node = _find_named(c, nm)
		if r != null:
			return r
	return null


## 场景树里所有 Sprite3D(装饰/物件都是 billboard 精灵)。
func _all_sprites(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is Sprite3D:
			out.append(c)
		out.append_array(_all_sprites(c))
	return out


## Clark-Evans R = 实测最近邻平均 ÷ 0.5/sqrt(n/A)
func _clark_evans(pts: PackedVector2Array) -> float:
	var n: int = pts.size()
	var minx := 1.0e9
	var maxx := -1.0e9
	var miny := 1.0e9
	var maxy := -1.0e9
	var sum := 0.0
	for i in range(n):
		var p: Vector2 = pts[i]
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		miny = minf(miny, p.y); maxy = maxf(maxy, p.y)
		var best := 1.0e9
		for j in range(n):
			if i == j:
				continue
			best = minf(best, p.distance_to(pts[j]))
		sum += best
	var area: float = maxf(1.0, (maxx - minx) * (maxy - miny))
	var expected: float = 0.5 / sqrt(float(n) / area)
	return (sum / float(n)) / maxf(0.0001, expected)


func _done(s, keep: String) -> void:
	AT.active = keep
	if s != null:
		s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装饰成组度" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
