extends RefCounted
## 触手门禁共用(下划线开头: 不是门禁)。2026-10-31 灵物触手重做(方案书 docs/plans/20261031d-灵物触手重做.md §4.3)。
##
## 新触手: 每根一个 MeshInstance3D(共用一份固定网格)+ 一份 ShaderMaterial, 形状全由 uniform 决定 ——
##   ctrl_pts(24 个中心线控制点, 相对根部; 节点放在根部、不旋转)/ vis(露出比例)/ flash / trail …
## ★判据一律读【材质上的 uniform】—— 那就是 GPU 拿到的那一份(顶点着色器沿它弯曲), 不读产品自己记账的
##   `mv_*` 字段、不重推姿态公式(memory fb-gate-must-measure-requirement-not-my-hook / fb-hand-rolled-copies-drift)。
## 节点与材质从 `TentacleVfx.probe_data()` 拿(公开探针, 不碰私有字典)。

const SIM_DT := 1.0 / 60.0


## 第 side/idx 根触手的节点(没有 ⇒ null)
static func node_of(tv, side: String, idx: int) -> MeshInstance3D:
	for e in tv.probe_data():
		if str((e as Dictionary)["side"]) == side and int((e as Dictionary)["idx"]) == idx:
			var n = (e as Dictionary).get("node")
			return n as MeshInstance3D if is_instance_valid(n) else null
	return null


static func mat_of(mi: MeshInstance3D) -> ShaderMaterial:
	return mi.material_override as ShaderMaterial if mi != null else null


static func uni(mi: MeshInstance3D, nm: String) -> Variant:
	var m := mat_of(mi)
	return m.get_shader_parameter(nm) if m != null else null


## 着色器拿到的中心线, 换成世界坐标(节点位置 + 相对根部的控制点)
static func world_pts(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cp = uni(mi, "ctrl_pts")
	if not (cp is PackedVector3Array):
		return out
	for p in (cp as PackedVector3Array):
		out.append(mi.position + p)
	return out


## 折线弧长
static func arc(pts: PackedVector3Array) -> float:
	var s := 0.0
	for i in range(1, pts.size()):
		s += (pts[i] - pts[i - 1]).length()
	return s


## 两帧之间逐点位移的最大值(点数不同 ⇒ -1)
static func max_disp(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return -1.0
	var m := 0.0
	for i in range(a.size()):
		m = maxf(m, (a[i] - b[i]).length())
	return m


## 推进一步 sim 时长: 战斗时钟 `_t` 与触手状态机一起走(待机慢摆读的是 `_t`; 只调 tick 不推 `_t` 待机就是定住的)。
static func step(tv, n: int = 1) -> void:
	for _i in range(n):
		tv.battle._t = float(tv.battle._t) + SIM_DT
		tv.tick(SIM_DT)


## 推到某根触手进入某个状态(最多 limit 步); 返回是否到了
static func until_state(tv, side: String, idx: int, st: int, limit: int = 600) -> bool:
	var g := 0
	while int(tv.state_of(side, idx)) != st and g < limit:
		step(tv)
		g += 1
	return int(tv.state_of(side, idx)) == st


## 控制点换到这根触手自己的坐标系(朝向 fwd / 竖直 / 侧向 lat, 都是着色器拿到的 uniform), 原点在根部。
##   着色器没有 fwd / lat 这两个 uniform(第一路改了做法)⇒ 退回相对根部的世界方向。
static func local_pts(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cp = uni(mi, "ctrl_pts")
	var f = uni(mi, "fwd")
	var l = uni(mi, "lat")
	if not (cp is PackedVector3Array):
		return out
	if not (f is Vector3) or not (l is Vector3):
		return PackedVector3Array(cp)
	for p in (cp as PackedVector3Array):
		out.append(Vector3((p as Vector3).dot(f), (p as Vector3).y, (p as Vector3).dot(l)))
	return out


## 露出比例(着色器没有 `vis` 这个 uniform ⇒ 整根都在地面上, 记 1)
static func vis_of(mi: MeshInstance3D) -> float:
	var v = uni(mi, "vis")
	return float(v) if v != null else 1.0
