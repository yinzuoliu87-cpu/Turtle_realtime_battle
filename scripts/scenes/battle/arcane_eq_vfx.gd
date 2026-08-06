class_name ArcaneEqVfx
extends RefCounted
## arcane_eq_vfx.gd — 法器三件新装备的演出层
## 088 涨潮碑 · 089 蚀月符纸 · 090 镇海杵
##
## 效果本体在 `scripts/systems/equip/eq_arcane_batch.gd`(EqArcaneBatch), 由它 `new` 出本类。
## 契约 = `docs/plans/20260806-实装契约-批④.md` §7。
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条自我约束(逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **零素材**: 全部是程序化 `ArrayMesh`/`SurfaceTool` + Godot 内置图元, 不新建资源、
##    也**没有借用任何别件装备的立绘**(用户铁律「不复用素材除非点名」——程序化几何不产图,
##    不吃这条约束)。
## ② **不用 tween**: 无头 CI 下 `create_tween()` 推进不稳(CLAUDE.md §3.5,
##    `verify_pirate_hook` 为此连红三次), 且走 sim 的 delta 才跟时停/换路同步。
##    全部生命周期由本文件的 `tick(delta)` 推进 —— 门禁可以同步喂任意 delta。
## ③ **形态由闭式解给, 不手调系数**(memory [[fb-match-reference-by-measured-curve]]):
##    三条曲线各有物理模型, 全部抽成 `static func` 供门禁直接验, 不必建节点、不必等演出。
##
## ⚠ 朝向坑(memory [[fb-axis-y-plus-rotation-cancels]]): 本文件**不用 Sprite3D**,
##   直接建世界坐标顶点 —— 没有 `axis = AXIS_Y` 与 `rotation.x = -90` 互相抵消那层歧义。
##   贴地几何一律是 y = GROUND_Y 的水平顶点。
##
## ⚠ 材质一律走 `material_override`, 不用 `set_surface_override_material` ——
##   后者在 `--headless` dummy renderer 下每设一次刷一条 `Parameter "material" is null.`。


# ══════════════════════════════════════════════════════════════════
#  §物理常数 —— 每条都对应一个模型, 不是手调出来的
# ══════════════════════════════════════════════════════════════════

## ① 088 碑体上涌: 临界阻尼(ζ=1)阶跃响应 x̂(t) = 1 − (1+ωt)·e^(−ωt)。
##    性质: x̂(0)=0 · 单调增 · **恒 < 1(永不过冲)** —— 碑是"顶上来"不是"弹出来"。
##    ω 用「上涌到 98% 所需时间」定标: (1+ωt)e^(−ωt)=0.02 ⇒ ωt≈5.83。
const RISE_WT98 := 5.834681
## 碑从冒头到站定用的秒数
const RISE_SEC := 0.55
## 碑体尺寸(码): 宽 / 厚 / 高
const STELE_W_PX := 26.0
const STELE_D_PX := 14.0
const STELE_H_PX := 78.0

## ② 潮涌环(每秒一跳的那一圈): **匀速**外扩 —— 浅水重力波在固定水深下相速恒定,
##    所以 r(t) = R·(t/T) 是线性的, 不是爆轰那种减速的。
const PULSE_SEC := 0.55

## ③ 090 猛砸: **Sedov–Taylor 点爆轰** r ∝ t^(2/5) —— 强激波在均匀介质里的自相似解。
##    与潮涌环的线性外扩形成对比(一个是波、一个是爆), 肉眼分得出来。
const SEDOV_EXP := 0.4
const SLAM_SEC := 0.85

## ④ 089 符纸悬浮: 简谐上下 + 慢自转。周期 1.6 秒, 幅度 4 码。
const BOB_OMEGA := 3.926990816987241
const BOB_AMP_PX := 4.0
const TALISMAN_SPIN := 1.35
## 符纸尺寸(码)与悬停高度(米)
const TALISMAN_W_PX := 16.0
const TALISMAN_H_PX := 22.0
const TALISMAN_Y := 1.05

## ⑤ 090 浪潮每一跳的抛物线拱高 = 跨度的这个比例(4·h·s(1−s) 的 h)
const ARC_PEAK_FRAC := 0.18
## 浪潮折线的带宽(码)与存活秒数
const WAVE_W_PX := 18.0
const WAVE_SEC := 0.42
## 符纸转移那道光带的存活秒数
const TRANSFER_SEC := 0.30
## 起跳光柱的存活秒数(由调用方传入起跳时长时以它为准)
const PILLAR_H_M := 3.6

## 贴地几何的离地高度(米) —— 高于地板顶面才不会被吞
const GROUND_Y := 0.06
## 环的经向分段
const RING_LON := 48
## 浪潮拱线的分段数
const ARC_SEG := 12

## 四件演出的语义色。★**颜色的单一事实源在演出层**(本文件), 效果本体
## `EqArcaneBatch` 反过来引用 `ArcaneEqVfx.COL_*` 当伤害飘字色 —— 引用是**单向**的,
## 免得两个 class_name 互相引用形成循环依赖(Godot 解析 const 时会炸)。
const COL_TIDE := Color("#5fd8ff")     # 088 潮汐(青)
const COL_MOON := Color("#b98cff")     # 089 蚀月(紫)
const COL_SLAM := Color("#7ec8ff")     # 090 猛砸(蓝白)
const COL_WAVE := Color("#8ff0ff")     # 090 浪潮(浅青)

## 节点身份标记(程序生成的网格 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "arcane_eq_vfx"
## `_owned` 上限, 同 SynergyVfx.OWNED_CAP 的口径(最后一道闸)
const OWNED_CAP := 256

var battle

## 本层建出来、还活着的节点(撤场用)。★存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []
## 正在播的特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进, **不用 tween**。
var _fx: Array = []
## 单位半径的贴地环网格(整局建一次; 材质**不能**共享, 会串色)
var _mesh_ring: ArrayMesh = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出(契约 §7: 全部同步判定)
# ══════════════════════════════════════════════════════════════════

## 碑体上涌的归一高度 x̂(t/T)。ζ=1 临界阻尼阶跃响应的解析解。
## ★性质(门禁逐条验): x̂(0)=0 · 严格单调增 · **恒 < 1** · x̂(T)≈0.98。
static func rise_frac(t: float, sec: float) -> float:
	if t <= 0.0 or sec <= 0.0:
		return 0.0
	var w: float = RISE_WT98 * (t / sec)
	return 1.0 - (1.0 + w) * exp(-w)


## 潮涌环半径: **匀速**外扩(浅水波相速恒定) r(t) = R·t/T。
static func pulse_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * clampf(t / sec, 0.0, 1.0)


## 猛砸激波半径: Sedov–Taylor 自相似解 r(t) = R·(t/T)^(2/5)。
## ★与 `pulse_radius` 的**线性**形成对比: 同样走到一半时间, 爆轰已经跑了 R·0.5^0.4 = 0.758R,
##   而潮涌环才 0.5R —— 前段快后段慢, 这是"爆"该有的样子。
static func blast_radius(t: float, sec: float, r_max: float) -> float:
	if sec <= 0.0:
		return r_max
	return r_max * pow(clampf(t / sec, 0.0, 1.0), SEDOV_EXP)


## 符纸悬浮的竖直偏移(码)。简谐: A·sin(ωt)。
static func bob_offset(t: float) -> float:
	return BOB_AMP_PX * sin(BOB_OMEGA * t)


## 浪潮一跳的拱高(米制无关的比例形): 4·h·s(1−s), s∈[0,1]。
## ★s=0 与 s=1 处为 0(两端贴着单位), 峰在 s=0.5 处 = h。
static func arc_height(s: float, peak: float) -> float:
	var x: float = clampf(s, 0.0, 1.0)
	return 4.0 * peak * x * (1.0 - x)


## 折线总长(码) —— 浪潮跳了多远的可量形式。
static func path_length(pts: Array) -> float:
	var sum: float = 0.0
	for i in range(1, pts.size()):
		sum += (pts[i] as Vector2).distance_to(pts[i - 1] as Vector2)
	return sum


# ══════════════════════════════════════════════════════════════════
#  §几何 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _flat(r: float, th: float, a: float) -> Array:
	return [Vector3(r * cos(th), GROUND_Y, r * sin(th)), Color(1, 1, 1, a)]


## 单位半径的贴地环(外沿硬 = 区域边界, 内沿渐隐)。
static func _build_ring() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(RING_LON):
		var t0: float = float(j) / float(RING_LON) * TAU
		var t1: float = float(j + 1) / float(RING_LON) * TAU
		for q in [[0.80, 0.0, 0.96, 0.85], [0.96, 0.85, 1.0, 0.30]]:
			var r0: float = q[0]
			var a0: float = q[1]
			var r1: float = q[2]
			var a1: float = q[3]
			_tri(st, _flat(r0, t0, a0), _flat(r1, t0, a1), _flat(r1, t1, a1))
			_tri(st, _flat(r0, t0, a0), _flat(r1, t1, a1), _flat(r0, t1, a0))
	st.commit(mesh)
	return mesh


func _ring_mesh() -> ArrayMesh:
	if _mesh_ring == null:
		_mesh_ring = _build_ring()
	return _mesh_ring


static func _mat(col: Color, prio: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	## ⚠ render_priority 在【材质】上, MeshInstance3D 没有这个属性
	m.render_priority = prio
	m.albedo_color = col
	return m


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


func _node(mesh: Mesh, mat: StandardMaterial3D, org: Vector3, kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = org
	_adopt(mi, kind)
	return mi


## 一条 A→B 的光带(细长盒体, 沿 +X 拉伸后绕 Y 对齐)。
func _band(a2d: Vector2, b2d: Vector2, col: Color, width_px: float, y_m: float) -> MeshInstance3D:
	var wf: Vector3 = battle._world_pos(a2d, y_m)
	var wt: Vector3 = battle._world_pos(b2d, y_m)
	var seg: Vector3 = wt - wf
	var l: float = seg.length()
	if l < 0.001:
		return null
	var bm := BoxMesh.new()
	bm.size = Vector3(l, width_px * float(battle.WS), width_px * float(battle.WS))
	var mi := _node(bm, _mat(col, 12), wf + seg * 0.5, "band")
	mi.rotation.y = -atan2(seg.z, seg.x)
	return mi


# ══════════════════════════════════════════════════════════════════
#  §088 涨潮碑
# ══════════════════════════════════════════════════════════════════

## 立碑: 一圈贴地边界(半径 = 效果半径) + 一块从地里顶上来的碑体。
## ★环的半径**就是** 250 码的效果半径 —— 不是"贴片尺寸"
##   (memory [[fb-verify-must-run-the-real-path]] 那次把效果半径当贴片尺寸, 公式全对但长 19.2 米)。
func stele_raise(pos2d: Vector2, radius_px: float, sec: float) -> Node3D:
	if not _has_world():
		return null
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.0)
	_adopt(root, "stele")
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh()
	ring.material_override = _mat(COL_TIDE, 9)
	ring.scale = Vector3(radius_px * float(battle.WS), 1.0, radius_px * float(battle.WS))
	root.add_child(ring)
	var bm := BoxMesh.new()
	bm.size = Vector3(STELE_W_PX * float(battle.WS), STELE_H_PX * float(battle.WS),
		STELE_D_PX * float(battle.WS))
	var slab := MeshInstance3D.new()
	slab.mesh = bm
	slab.material_override = _mat(COL_TIDE, 10)
	root.add_child(slab)
	## ★把【效果半径】记在节点自己身上, 门禁量真实对象而不是在测试里把公式抄一遍
	##   (memory [[fb-write-without-reader-and-fake-gates]]:「门禁模拟公式 ≠ 量真实对象」)。
	root.set_meta("radius_px", radius_px)
	_fx.append({"node": root, "slab": slab, "t": 0.0, "life": maxf(0.05, sec), "kind": "stele"})
	return root


## 每秒一跳的潮涌环(匀速外扩)。
func stele_pulse(pos2d: Vector2, radius_px: float) -> Node3D:
	return _ring_fx(pos2d, radius_px, COL_TIDE, PULSE_SEC, "pulse")


# ══════════════════════════════════════════════════════════════════
#  §089 蚀月符纸
# ══════════════════════════════════════════════════════════════════

## 给目标贴一张悬浮符纸(跟着它走, 上下轻浮 + 慢自转)。
## ★状态里存的是**单位字典本身**(放在 `_fx` 条目的 value 位) —— 允许;
##   禁止的是拿它当 Dictionary 的**键**(CLAUDE.md §3.2)。
func talisman_stick(u, sec: float) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	var bm := BoxMesh.new()
	bm.size = Vector3(TALISMAN_W_PX * float(battle.WS), TALISMAN_H_PX * float(battle.WS),
		0.6 * float(battle.WS))
	var mi := _node(bm, _mat(COL_MOON, 11),
		battle._world_pos((u as Dictionary)["pos"] as Vector2, TALISMAN_Y), "talisman")
	_fx.append({"node": mi, "unit": u, "t": 0.0, "life": maxf(0.05, sec), "kind": "talisman"})
	return mi


## 符纸从尸体飞向新目标的那道紫光。
func talisman_transfer(from2d: Vector2, to2d: Vector2) -> Node3D:
	if not _has_world():
		return null
	var mi := _band(from2d, to2d, COL_MOON, 10.0, TALISMAN_Y)
	if mi == null:
		return null
	_fx.append({"node": mi, "t": 0.0, "life": TRANSFER_SEC, "kind": "transfer"})
	return mi


# ══════════════════════════════════════════════════════════════════
#  §090 镇海杵
# ══════════════════════════════════════════════════════════════════

## 起跳: 携带者脚下一道上冲的光柱(存活 = 起跳到砸落的时长)。
func pestle_leap(u, sec: float) -> Node3D:
	if not _has_world() or not (u is Dictionary):
		return null
	var bm := BoxMesh.new()
	bm.size = Vector3(20.0 * float(battle.WS), PILLAR_H_M, 20.0 * float(battle.WS))
	var mi := _node(bm, _mat(COL_SLAM, 10),
		battle._world_pos((u as Dictionary)["pos"] as Vector2, PILLAR_H_M * 0.5), "leap")
	_fx.append({"node": mi, "t": 0.0, "life": maxf(0.05, sec), "kind": "leap"})
	return mi


## 砸落: 一圈 Sedov 激波(半径 = 1000 码的真实效果半径)。
func pestle_slam(pos2d: Vector2, radius_px: float) -> Node3D:
	return _ring_fx(pos2d, radius_px, COL_SLAM, SLAM_SEC, "slam")


## 浪潮折线: 每一跳画一段拱形(4·h·s(1−s)), 拱高 = 跨度的 ARC_PEAK_FRAC。
## ★同步建完就返回 —— 伤害早在 `EqArcaneBatch.wave_chain` 里结算过了, 这里纯画。
func wave_path(pts: Array) -> Node3D:
	if not _has_world() or pts.size() < 2:
		return null
	var root := Node3D.new()
	root.position = Vector3.ZERO
	_adopt(root, "wave")
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var span: float = a.distance_to(b)
		var peak: float = span * ARC_PEAK_FRAC * float(battle.WS)
		var prev: Vector3 = battle._world_pos(a, 0.55)
		for k in range(1, ARC_SEG + 1):
			var s: float = float(k) / float(ARC_SEG)
			var p2: Vector2 = a.lerp(b, s)
			var cur: Vector3 = battle._world_pos(p2, 0.55 + arc_height(s, peak))
			var seg: Vector3 = cur - prev
			var l: float = seg.length()
			if l > 0.0005:
				var bm := BoxMesh.new()
				bm.size = Vector3(l, WAVE_W_PX * float(battle.WS), WAVE_W_PX * float(battle.WS))
				var mi := MeshInstance3D.new()
				mi.mesh = bm
				mi.material_override = _mat(COL_WAVE, 12)
				mi.position = prev + seg * 0.5
				mi.rotation.y = -atan2(seg.z, seg.x)
				mi.rotation.z = asin(clampf(seg.y / l, -1.0, 1.0))
				root.add_child(mi)
			prev = cur
	root.set_meta("path_len", path_length(pts))
	_fx.append({"node": root, "t": 0.0, "life": WAVE_SEC, "kind": "wave"})
	return root


# ══════════════════════════════════════════════════════════════════
#  §驱动与撤场
# ══════════════════════════════════════════════════════════════════

func _ring_fx(pos2d: Vector2, radius_px: float, col: Color, sec: float, kind: String) -> Node3D:
	if not _has_world():
		return null
	var mi := _node(_ring_mesh(), _mat(col, 9), battle._world_pos(pos2d, 0.0), kind)
	mi.scale = Vector3(0.001, 1.0, 0.001)
	mi.set_meta("radius_px", radius_px)
	_fx.append({"node": mi, "t": 0.0, "life": sec, "kind": kind, "r": radius_px})
	return mi


## 每帧推进。★纯同步, 门禁可以喂任意 delta; 不依赖 tween。
func tick(delta: float) -> void:
	if delta <= 0.0 or _fx.is_empty():
		return
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var t: float = float(f["t"])
		var life: float = maxf(0.001, float(f["life"]))
		var k: String = str(f["kind"])
		match k:
			"stele":
				var slab = f.get("slab", null)
				if is_instance_valid(slab):
					var h: float = STELE_H_PX * float(battle.WS)
					var fr: float = rise_frac(t, RISE_SEC)
					## 碑从地下顶上来: 站定时中心在 h/2, 冒头时中心在 −h/2
					(slab as Node3D).position.y = h * (fr - 0.5)
				if t >= life:
					_free_fx(i)
			"pulse", "slam":
				var rp: float = float(f.get("r", 100.0))
				var r: float = (blast_radius(t, life, rp) if k == "slam" else pulse_radius(t, life, rp))
				var s: float = maxf(0.001, r * float(battle.WS))
				(n as Node3D).scale = Vector3(s, 1.0, s)
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)
			"talisman":
				var u = f.get("unit", null)
				if u is Dictionary and (u as Dictionary).get("alive", false):
					var p: Vector2 = (u as Dictionary)["pos"]
					(n as Node3D).position = battle._world_pos(p, TALISMAN_Y + bob_offset(t) * float(battle.WS))
					(n as Node3D).rotation.y = TALISMAN_SPIN * t
				if t >= life or not (u is Dictionary) or not (u as Dictionary).get("alive", false):
					_free_fx(i)
			"leap":
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0) * 0.7)
				if t >= life:
					_free_fx(i)
			_:
				_set_alpha(n, 1.0 - clampf(t / life, 0.0, 1.0))
				if t >= life:
					_free_fx(i)


func _set_alpha(n, a: float) -> void:
	if n is MeshInstance3D:
		var m = (n as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			(m as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))
	elif n is Node3D:
		for ch in (n as Node3D).get_children():
			_set_alpha(ch, a)


func _free_fx(i: int) -> void:
	var f: Dictionary = _fx[i]
	var n = f.get("node", null)
	if is_instance_valid(n):
		(n as Node).queue_free()
	_fx.remove_at(i)


## 撤场: 全部释放。返回释放了几个(门禁数它)。
func clear() -> int:
	var n: int = 0
	for x in _owned:
		if is_instance_valid(x):
			(x as Node).queue_free()
			n += 1
	_owned.clear()
	_fx.clear()
	return n


## 还活着的本层节点数(可按 kind 过滤) —— 门禁量真实对象用。
func alive_count(kind: String = "") -> int:
	var n: int = 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
