class_name AxeFinalVfx
extends RefCounted
## 四个最终造物的演出 (2026-09-01·方案书六期 A1~A10)
##
## ══════════════════════════════════════════════════════════════════
##  ★怎么读这个文件
## ══════════════════════════════════════════════════════════════════
## 照仓库里 `arcane_eq_vfx.gd` 的规矩分两半：
##   **上半 §纯函数** —— 运动曲线。门禁直接调，不建节点、不等演出。
##     这是本仓库对"特效也能被门禁守住"的答案：形状可以被量，而不是"我看着像"。
##   **下半 §建节点** —— 真往 `battle._world` 里挂东西。
##
## ★结算不在这里（CLAUDE.md §3.5）：伤害/回血/处决全在 `axe_final_forms.gd` 的纯结算里，
##   演出只负责画。把数值埋进 tween 链 = 无头 CI 推不动 = 本地永远复现不出来的红。
##
## ★★两条从别人身上学来的教训（写在最前面，免得我又踩）：
##   · **ADD 混合会把实心体爆成白**（088 祖龟碑：一块 #5fd8ff 的盒子正反面叠加 → 纯白方块）
##     ⇒ 实心用 `_mat_solid`(MIX + 只画正面)，只有"发光"才用 ADD。
##   · **短命特效一出生就线性淡出会被读成土棕/灰**（memory [[fb-vfx-defect-families]]，一天踩四次）
##     ⇒ 前 70% 保持满亮，最后 30% 才淡（`hold_fade`）。
const COL_UNDEAD := Color(0.49, 0.88, 0.51)     # 亡灵绿
const COL_SERAPH := Color(1.00, 0.70, 0.28)     # 炽天使橙
const COL_HOLO := Color(0.37, 0.85, 1.00)       # 全息青
const COL_EMBER := Color(1.00, 0.44, 0.26)      # 余烬红

var battle = null
var _mesh_ring: ArrayMesh = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调，不建节点、不等演出
# ══════════════════════════════════════════════════════════════════

## 短命特效的透明度：**前 70% 满亮，后 30% 才淡**。
## ★不是 `1-t`。一出生就线性淡出的话，实拍读到的平均亮度只有一半，
##   于是"金色"会被读成土棕、"白"会被读成灰（memory [[fb-vfx-defect-families]] 淡出病）。
## 性质（门禁逐条验）：hold_fade(0)=1 · hold_fade(0.7)=1 · hold_fade(1)=0 · 单调不增。
static func hold_fade(t: float, hold: float = 0.7) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	if x <= hold:
		return 1.0
	if hold >= 1.0:
		return 1.0
	return 1.0 - (x - hold) / (1.0 - hold)


## 亡灵环的**呼吸**：半径在 [1-amp, 1] 之间来回，周期 `period` 秒。
## ★环是常驻场（不是一次性爆发），所以它要"活着"而不是"闪一下"。
## 性质：恒在 [1-amp, 1] 内 · t=0 时为 1 · 半周期时取到最小。
static func ring_breath(t: float, period: float = 2.0, amp: float = 0.06) -> float:
	if period <= 0.0:
		return 1.0
	var ph: float = TAU * (t / period)
	return 1.0 - amp * 0.5 * (1.0 - cos(ph))


## 回旋镖的飞行进度 → 位置系数（0=出手，1=飞到最远）。
## ★需求写的是「**直直飞过**」⇒ 匀速直线，不是抛物线也不是回旋。
##   （名字叫回旋镖，但需求明确是"沿着目标所在的一条直线直直飞过"。）
static func boomerang_frac(t: float, fly_sec: float) -> float:
	if fly_sec <= 0.0:
		return 1.0
	return clampf(t / fly_sec, 0.0, 1.0)


## 10 把回旋镖在 4 秒里的**出手时刻**（第 i 把，i 从 0 起）。
## ★均匀铺开而不是一次性甩出去 —— 需求是「4秒内投掷10把」。
## 性质：t(0)=0 · 严格递增 · t(n-1) < 总时长（最后一把也得有飞行时间）。
static func boomerang_launch_t(i: int, total: int, cast_sec: float) -> float:
	if total <= 1:
		return 0.0
	return cast_sec * float(clampi(i, 0, total - 1)) / float(total)


## 全息法阵每一跳的**脉冲亮度**：跳的那一刻最亮，然后在这一拍内衰减。
## ★用它把"每 0.5 秒回一次血"这件事**看得见** —— 光环恒亮的话玩家读不出节拍。
## 性质：phase=0 时为 1 · 单调减 · 到下一拍前落到 base。
static func aura_pulse(phase01: float, base: float = 0.35) -> float:
	var x: float = clampf(phase01, 0.0, 1.0)
	return base + (1.0 - base) * (1.0 - x) * (1.0 - x)


## 重生的聚拢进度 x̂(t/T)：0=散成一团亡魂，1=重新站起来。
## ★用**先慢后快**（三次方）而不是线性 —— 前段是"魂在飘"，末段是"啪地成形"。
##   线性的话看着像匀速滑进来，读不出"聚拢"。
## 性质：f(0)=0 · f(1)=1 · 严格单调增 · f(0.5) < 0.5（前段慢）。
static func revive_gather(t01: float) -> float:
	var x: float = clampf(t01, 0.0, 1.0)
	return x * x * x


## 余烬种子层数 → 目标身上那圈火星的**颜色浓度**（0~1）。
## ★叠满不封顶（需求「无限叠加」），但视觉要有上限，否则 200 层是一团纯白。
##   30 层封顶：那时处决线已经 15%，再浓也没有信息量了。
static func seed_glow(stacks: int) -> float:
	return clampf(float(maxi(0, stacks)) / 30.0, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

## 统一的材质：`solid=true` 走 MIX（实心体，防 ADD 把它爆成白），否则走 ADD（发光）。
static func _mat(col: Color, solid: bool, prio: int = 8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if solid else BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_BACK if solid else BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = prio
	m.albedo_color = col
	return m


## 一圈贴地的细环（内外双圆环带）。整局只建一次网格。
func _ring_mesh() -> ArrayMesh:
	if _mesh_ring != null:
		return _mesh_ring
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 72
	var inner := 0.94
	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		var q0: Vector3 = p0 * inner
		var q1: Vector3 = p1 * inner
		for v in [q0, p0, p1, q0, p1, q1]:
			st.add_vertex(v)
	_mesh_ring = st.commit()
	return _mesh_ring


func _adopt(n: Node3D) -> void:
	battle._world.add_child(n)


## A1 亡灵环：300 码贴地绿环，常驻并呼吸。返回根节点（调用方自己持有/释放）。
func undead_ring(ax: Dictionary, radius_px: float) -> Node3D:
	if not _has_world() or not (ax is Dictionary):
		return null
	var root := Node3D.new()
	root.position = battle._world_pos(ax.get("pos", Vector2.ZERO), 0.02)
	_adopt(root)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh()
	ring.material_override = _mat(Color(COL_UNDEAD.r, COL_UNDEAD.g, COL_UNDEAD.b, 0.55), false)
	var r: float = radius_px * float(battle.WS)
	ring.scale = Vector3(r, 1.0, r)
	root.add_child(ring)
	root.set_meta("axe_ring", true)
	return root


## A2 吸取丝线：从敌人脚下抽一条绿线回到斧头。一次性、短命。
func undead_leech_line(from2d: Vector2, to2d: Vector2) -> void:
	if not _has_world():
		return
	var n := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var a: Vector3 = battle._world_pos(from2d, 0.35)
	var b: Vector3 = battle._world_pos(to2d, 0.55)
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(9):
		var f: float = float(i) / 8.0
		var p: Vector3 = a.lerp(b, f)
		p.y += sin(f * PI) * 0.22          # 微微拱起，看得出是"被抽走"不是一条直棍
		im.surface_add_vertex(p - a)
	im.surface_end()
	n.mesh = im
	n.position = a
	n.material_override = _mat(COL_UNDEAD, false, 10)
	_adopt(n)
	_fade_out(n, 0.45)


## A3 重生：亡魂聚拢再立起。★不播死亡动画（用户两次点名），这就是"倒下→回来"的全部表现。
func undead_revive(pos2d: Vector2, sec: float) -> void:
	if not _has_world():
		return
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.05)
	_adopt(root)
	## 六缕魂从外圈向心聚拢 —— 用 revive_gather 的三次方曲线（前慢后快）
	for i in range(6):
		var a: float = TAU * float(i) / 6.0
		var wisp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, 0.42, 0.10)
		wisp.mesh = bm
		wisp.material_override = _mat(COL_UNDEAD, false, 11)
		var r0: float = 1.5
		wisp.position = Vector3(cos(a) * r0, 0.2, sin(a) * r0)
		root.add_child(wisp)
		## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
		var tw: Tween = battle._reg_tween()
		## ★捕获实例 id 不捕获节点(见 `_fade_out` 头注)
		var wid: int = wisp.get_instance_id()
		tw.tween_method(func(x: float) -> void:
			var w = instance_from_id(wid)
			if not is_instance_valid(w):
				return
			var g: float = revive_gather(x)
			(w as Node3D).position = Vector3(cos(a) * r0 * (1.0 - g), 0.2 + g * 0.5, sin(a) * r0 * (1.0 - g))
			(w as Node3D).scale = Vector3.ONE * (0.6 + g * 0.8)
		, 0.0, 1.0, sec)
	_fade_out(root, sec + 0.25)


## A4 回旋镖：一把橙色斧刃沿 dir 匀速飞过。**只是演出** —— 伤害由调用方在出手时结算。
func seraph_boomerang(from2d: Vector2, dir: Vector2, dist_px: float, fly_sec: float) -> void:
	if not _has_world():
		return
	var d: Vector2 = dir.normalized()
	if d == Vector2.ZERO:
		return
	var n := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.10, 0.16)
	n.mesh = bm
	## 斧刃是**实心**的 ⇒ MIX，不用 ADD（088 那块被 ADD 爆成白的碑就是教训）
	n.material_override = _mat(COL_SERAPH, true, 9)
	n.position = battle._world_pos(from2d, 0.55)
	_adopt(n)
	var to2d: Vector2 = from2d + d * dist_px
	n.set_meta("boom_to2d", to2d)   # 画到哪 —— 门禁量「演出长度 ≥ 判定打中的最远处」(第十批 E10)
	## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
	var tw: Tween = battle._reg_tween()
	## ★捕获实例 id 不捕获节点(见 `_fade_out` 头注)
	var nid: int = n.get_instance_id()
	tw.tween_method(func(x: float) -> void:
		var m = instance_from_id(nid)
		if not is_instance_valid(m):
			return
		var f: float = boomerang_frac(x, 1.0)
		(m as Node3D).position = battle._world_pos(from2d.lerp(to2d, f), 0.55)
		(m as Node3D).rotation.y += 0.55                # 自旋，读得出是"甩出去的"
	, 0.0, 1.0, fly_sec)
	_fade_out(n, fly_sec)


## A6+A7 全息法阵：插地的斧头 + 600 码青色地面阵。返回根节点。
func holo_field(pos2d: Vector2, radius_px: float, sec: float) -> Node3D:
	if not _has_world():
		return null
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.02)
	_adopt(root)
	## 地面阵：外环 + 内环（双环读得出"这是个阵"，单圈只是个圈）
	for k in [1.0, 0.62]:
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh()
		ring.material_override = _mat(Color(COL_HOLO.r, COL_HOLO.g, COL_HOLO.b, 0.5), false)
		var r: float = radius_px * float(battle.WS) * k
		ring.scale = Vector3(r, 1.0, r)
		root.add_child(ring)
	## 插在中间的斧头（实心 ⇒ MIX）
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.14, 0.85, 0.14)
	blade.mesh = bm
	blade.material_override = _mat(COL_HOLO, true, 10)
	blade.position = Vector3(0.0, 0.42, 0.0)
	root.add_child(blade)
	root.set_meta("axe_holo", true)
	_fade_out(root, sec)
	return root


## A7 法阵的一跳：整个阵闪一下（配合 aura_pulse 的节拍）。
func holo_pulse(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
	var tw: Tween = battle._reg_tween()
	## ★★捕获实例 id, 不捕获 `root`(2026-09-15 录 096 九个形态时查到)。
	##   法阵本体按 tween 时钟 `sec` 秒后释放, 脉冲却按战斗时钟每 0.5 秒排一次 ——
	##   顿帧时战斗时钟停、tween 照走 ⇒ 最后一次脉冲的 0.45 秒 tween 跑过本体释放的时刻,
	##   lambda 捕获的 `root` 已释放 ⇒ 引擎每帧报一条 `Lambda capture at index 0 was freed`
	##   (全息斧整段 19 条; 函数体里的 is_instance_valid 拦不住, 报错发生在调用 lambda 那一刻)。
	##   探针: 关掉本函数 ⇒ 同一 16 秒窗口 3 → 0 条。
	var rid: int = root.get_instance_id()
	tw.tween_method(func(x: float) -> void:
		var r = instance_from_id(rid)
		if not is_instance_valid(r):
			return
		var a: float = aura_pulse(x)
		for c in (r as Node).get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).transparency = 1.0 - a
	, 0.0, 1.0, 0.45)


## A8 余烬种子：目标脚下一圈火星，浓度随层数。
func ember_seed(tgt: Dictionary, stacks: int) -> void:
	if not _has_world() or not (tgt is Dictionary):
		return
	var n := MeshInstance3D.new()
	n.mesh = _ring_mesh()
	var g: float = seed_glow(stacks)
	n.material_override = _mat(Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.25 + 0.55 * g), false)
	var r: float = 26.0 * float(battle.WS)
	n.scale = Vector3(r, 1.0, r)
	n.position = battle._world_pos(tgt.get("pos", Vector2.ZERO), 0.03)
	_adopt(n)
	_fade_out(n, 0.5)


## A9 处决: 2026-09-15 移到 `axe_ember_vfx.gd`(天降轨道激光)。原来这里是一根红色 BoxMesh, 用户否掉。


## A10 余烬之光：斧头身上一圈红环（有就有，多层不叠强度 —— 与结算口径一致）。
func ember_light(ax: Dictionary) -> Node3D:
	if not _has_world() or not (ax is Dictionary):
		return null
	var n := MeshInstance3D.new()
	n.mesh = _ring_mesh()
	n.material_override = _mat(Color(COL_EMBER.r, COL_EMBER.g, COL_EMBER.b, 0.6), false)
	var r: float = 34.0 * float(battle.WS)
	n.scale = Vector3(r, 1.0, r)
	n.position = battle._world_pos(ax.get("pos", Vector2.ZERO), 0.04)
	_adopt(n)
	n.set_meta("axe_ember_light", true)
	return n


## 公开的淡出释放 —— 给"常驻但要按拍重建"的东西用(亡灵环 / 余烬之光环)。
## ★它就是 `_fade_out` 的对外名字: 有了它, 调用方不必碰下划线私有函数。
func fade_and_free(n, sec: float) -> void:
	if n is Node3D and is_instance_valid(n):
		_fade_out(n, sec)


## 统一淡出并释放。★走 `hold_fade`：前 70% 满亮，最后 30% 才淡。
func _fade_out(n: Node3D, sec: float) -> void:
	## ★显式标注类型: `battle` 是无类型的注入宿主, `:=` 推不出 Tween(Parse Error)。
	var tw: Tween = battle._reg_tween()
	## ★★本文件的 tween lambda 一律捕获实例 id、调用时再取节点, 不直接捕获节点。
	##   捕获的节点若先被释放(别处释放 / 两条时钟错开), Godot 在【调用 lambda 那一刻】就报
	##   `Lambda capture at index 0 was freed` —— 函数体里的 is_instance_valid 来不及拦。
	##   实例 id 是整数, 释放后 instance_from_id 返回 null, 静默跳过。
	var nid: int = n.get_instance_id()
	tw.tween_method(func(x: float) -> void:
		var n2 = instance_from_id(nid)
		if not is_instance_valid(n2):
			return
		var a: float = hold_fade(x)
		for m in ([n2] as Array) + (n2 as Node).get_children():
			if m is MeshInstance3D:
				(m as MeshInstance3D).transparency = 1.0 - a
	, 0.0, 1.0, maxf(0.05, sec))
	tw.tween_callback(func() -> void:
		var n3 = instance_from_id(nid)
		if is_instance_valid(n3):
			(n3 as Node).queue_free())
