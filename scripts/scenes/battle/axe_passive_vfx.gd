class_name AxePassiveVfx
extends RefCounted
## 小木斧·被动 3~6 与主动的演出 (2026-09-03)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: `axe_passives.gd` 建视觉的调用是 **0 处**
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-03:「所以是钻石以及4个最终造物什么特效都没有是吧」
##                 「斧头特效要全部补齐且不能敷衍」
##
## 四条被动的伤害/击飞/眩晕**全都在生效**, 但屏幕上一个节点都不建 ——
## 玩家看到的是斧头站着不动就把人打飞了。这是「写了没人读」的镜像:
## 结算齐全、演出为零(memory [[fb-zero-caller-is-a-whole-class]])。
##
## ══════════════════════════════════════════════════════════════════
##  ★不敷衍的判据 —— 每个演出都要能说出"它为什么长这样"
## ══════════════════════════════════════════════════════════════════
## memory [[fb-vfx-defect-families]] 里那条「无含义的圆环与白球」就是敷衍的定义。
## 本文件每个演出的形状都**由机制决定**, 不是随手挑的:
##   · 蓄力梯形  = `AE.in_trapezoid()` 的判定区**本身**, 逐码对齐(见 charge_field)
##   · 横扫弧    = `AE.SWEEP_ARC_DEG` 的 180° 扇形, 半径 = 斧头的 atk_range
##   · 竖劈      = 一道竖直下劈的刀光, 对应"每第二次普攻竖劈"
##   · 强化猛砸  = 冲击环 + 击飞尘, 对应 `SMASH_KNOCK_VY/PUSH`
##   · 主动治疗  = 上升的绿光, 对应回血 + 给盾
##
## ★★两条从 axe_final_vfx.gd 继承来的硬规矩(那边的头注记着由来):
##   · **短命特效不许一出生就线性淡出** —— 会被实拍读成土棕/灰。
##     前 70% 保持满亮, 最后 30% 才淡(`_hold_fade`)。
##   · **实心体不用 ADD 混合** —— 正反面叠加会爆成纯白方块。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
## ★★贴地朝向【调 blade 那份已验收的 ground_basis】, 不自己写第二套。
##   由来(2026-09-03): 我一开始用 `Sprite3D.axis = AXIS_Y` + `rotation.y = -yaw`,
##   实拍横扫的弧一直在斧头**正下方**、不跟着攻击方向转; 我转了 180° 也没用。
##   而 blade 在 2026-08-29「横斩铺到地面平面」那次已经把这件事做对了, 并且
##   `_t084_ground_plane` 有断言量着它落在哪儿 —— 它的头注写着「符号不靠推理」。
##   ⇒ memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后, 直接调它。
const BladeVfx := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")

## 横扫素材里【弧身中线】在贴图平面的角度(y 向上) —— **量出来的, 不是拍的**。
## 逐帧量 eq096-sweep.png 的不透明像素重心: -71.9° → +12.4°(弧在扫), 圆平均 -20.9°。
const SWEEP_AIM_DEG := -20.9

## ── 配色: 跟着档位材质走, 不是随便挑的颜色 ──
## ★★竖劈是**唯一一张要提亮**的 —— 这个 1.28 不是拍的, 是量出来的:
##   逐张量五张素材的亮度分布(只统计不透明像素)——
##     cleave 中位数 **65** / P25 46 / **23.1% 暗于 40**
##     sweep 108 · smash 104 · slam 105 · heal 184
##   它比别的四张暗一档(我选帧时挑了"黑红裂纹"那版, 材质最足但整体压得很低),
##   在黑场里整个沉下去 —— 实拍时**伤害数字 45000 照常跳、刀光一点都看不见**。
##   ⇒ 提亮到 1.28(memory [[fb-texture-has-usable-size-range]]: modulate 别过 1.3)。
## ★为什么不改素材本身: PixelLab 的**原始帧比我加工的好** —— build_eq084_vfx.py 的头注
##   记着 2026-08-29 那次我照自己拍的阈值把分层刀光洗白、把辐射细丝剁成碎条。
##   提亮放在渲染侧, 素材一个像素不动。
const COL_CLEAVE := Color(1.28, 1.28, 1.30)     # 铁斧竖劈: 冷铁白(已提亮, 见上)
const COL_SWEEP := Color(1.00, 0.82, 0.35)      # 金斧横扫: 金
const COL_SMASH := Color(0.78, 0.60, 0.34)      # 石斧强化砸: 土石棕
const COL_SLAM := Color(0.94, 0.72, 0.28)       # 钻石斧猛砸: 琥珀金
const COL_HEAL := Color(0.45, 0.92, 0.55)       # 主动治疗: 生命绿
## 梯形边框 —— **不是 COL_SLAM 的加深版**, 是与它拉开明度差的亮白黄(见 charge_field 注释)。
const COL_FIELD_EDGE := Color(1.00, 0.97, 0.80, 0.98)

## 蓄力梯形的地面标记高度(米) —— 略高于地面, 免得被地板 z-fight 吃掉。
## ★不是 0: memory [[fb-axis-y-plus-rotation-cancels]] 那次量过, 环 y=0.05 > 顶面 y=0 才稳。
const FIELD_Y := 0.06

var battle = null
var _mesh_cache: Dictionary = {}      # h(取整到 CHARGE_H_PER_STEP) → ArrayMesh


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出
# ══════════════════════════════════════════════════════════════════

## 梯形在纵深 t 处的**半宽**。★这是把 `AE.in_trapezoid` 的判据抄成可画的形式,
## 所以它必须跟那边**逐字同一个公式** —— 特别是:
##   半宽按【满蓄高 CHARGE_TIME/CHARGE_STEP*CHARGE_H_PER_STEP = 800】插值,
##   **不是按当前高 h**。判定那边的注释写着「否则梯形长大的时候会跟着变胖,
##   而需求只说高在长、没说宽在长」。画的时候跟着变胖 ⇒ 演出比判定宽 ⇒
##   玩家站在亮区里却没被打到(或反过来), 这正是"演出即判定"最常见的破法。
static func half_w_at(t: float) -> float:
	var full_h: float = AE.CHARGE_TIME / AE.CHARGE_STEP * AE.CHARGE_H_PER_STEP
	var k: float = clampf(t / maxf(1.0, full_h), 0.0, 1.0)
	return lerpf(AE.TRAPEZOID_NEAR_W, AE.TRAPEZOID_FAR_W, k) * 0.5


## 演出用的四个角(局部坐标, 单位=码; +X 是朝向 dir 的纵深)。
## ★门禁拿它跟 `AE.in_trapezoid` 对账: 角点必须**恰好在判定边界上**。
static func field_corners(h: float) -> Array:
	if h <= 0.0:
		return []
	var wn: float = half_w_at(0.0)
	var wf: float = half_w_at(h)
	return [Vector2(0.0, -wn), Vector2(h, -wf), Vector2(h, wf), Vector2(0.0, wn)]


## 短命特效的透明度曲线: 前 `hold` 比例保持满亮, 之后才线性淡出。
## ★memory [[fb-vfx-defect-families]] 的「淡出病」—— 一出生就淡的特效在实拍里
##   读成土棕/灰, 一天踩过四次。
static func hold_fade(p: float, hold: float = 0.7) -> float:
	var x: float = clampf(p, 0.0, 1.0)
	if x <= hold:
		return 1.0
	return clampf(1.0 - (x - hold) / maxf(0.001, 1.0 - hold), 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

func _adopt(n: Node3D) -> void:
	if _has_world():
		battle._world.add_child(n)


## 半透明填充材质(MIX·只画正面)。★不用 ADD —— 实心体正反面叠加会爆成纯白,
##   axe_final_vfx 的头注记着 088 祖龟碑那次。
func _mat_solid(col: Color, prio: int = 0, two_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## ★★`two_sided` 存在的唯一理由 —— 2026-09-03 染色法查出来的真根因:
	##   边框是【四条独立的带】, 每条的法线由 `Vector2(-d.y, d.x)` 算,
	##   四条边方向各不相同 ⇒ **有些带的绕向朝下**, 被 CULL_BACK 整条剔掉。
	##   填充是一个绕向一致的四边形, 所以它可见 —— 于是表现成"填充有、边框没有"。
	##   ★我在这上面连猜三次全错(抬高 y / render_priority / 换颜色), 直到把边框
	##     染成纯品红重拍、数出 **0 个品红像素**, 才确定它是"根本没渲染"而不是"不显眼"。
	##     memory [[fb-probe-before-claiming-rootcause]]: 推理出的根因不算根因。
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK
	m.albedo_color = col
	m.no_depth_test = true
	## ★★`no_depth_test = true` ⇒ **深度测试关掉了, 抬高 y 完全不影响谁盖谁**。
	##   2026-09-03 我先把边框抬高 2cm, 重拍仍看不见, 探针证明 mesh 建了、y 也确实是 0.020
	##   —— 决定顺序的是这个 `render_priority`, 不是高度。
	##   (同族: memory [[fb-axis-y-plus-rotation-cancels]] —— 3D 里"我以为的那个属性"
	##    常常不是真正起作用的那个, 必须拿探针读回来。)
	m.render_priority = prio
	return m


## 蓄力梯形的地面 mesh。★按 CHARGE_H_PER_STEP 取整做缓存 ——
## 蓄力是**阶梯**(每 0.5 秒 +100 码, `AE.charge_height` 里 floorf 过),
## 所以只有 8 种高度, 建 8 个 mesh 就够, 不必每帧重建。
func _field_mesh(h: float) -> ArrayMesh:
	var key: int = int(round(h / AE.CHARGE_H_PER_STEP))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cs: Array = field_corners(float(key) * AE.CHARGE_H_PER_STEP)
	if cs.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## 局部坐标: x = 纵深(码) / z = 横向(码)。摆位时再乘 WS 转成世界尺度。
	var v: Array = []
	for c in cs:
		v.append(Vector3(float((c as Vector2).x), 0.0, float((c as Vector2).y)))
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[idx])
	var mesh: ArrayMesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh


## 被动 6【蓄力梯形预警】—— 每 0.5 秒长一格, 一直画到砸下。
##
## ★★这是本次特效里最不能敷衍的一个: 它**就是判定区**。
##   玩家看到的亮区边界 = `AE.in_trapezoid` 返回 true 的边界, 逐码对齐。
##   拿一个"大概那么大的圆"糊过去, 就是 memory 里那条「无含义的圆环」。
##
## 返回根节点; 调用方持有它, 每帧调 `charge_update`, 结束时 `charge_clear`。
func charge_field(ax: Dictionary, dir: Vector2, h: float) -> Node3D:
	if not _has_world() or h <= 0.0:
		return null
	var root := Node3D.new()
	root.name = "AxeChargeField"
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = _field_mesh(h)
	if mesh == null:
		return null
	mi.mesh = mesh
	## 填充要**压得住但不挡住脚下的单位** —— 0.22 是"看得出边界、看得见站在里面的人"。
	mi.material_override = _mat_solid(Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.22), 2)
	mi.name = "Fill"
	root.add_child(mi)
	## ★★加一圈亮边 —— 2026-09-03 实拍后补。
	##   只有 alpha 0.22 的纯色填充时, 实拍里它读成**一块土黄色的地板贴图**, 不像危险区
	##   (memory [[fb-clean-vfx-stage-not-squint]]: 拿全场截图眯眼看会判反 ⇒ 我真拍了才发现)。
	##   边界正是这个演出**唯一要传达的信息**(站在线内会被砸), 所以它必须比填充更显眼。
	var edge := MeshInstance3D.new()
	edge.name = "Edge"
	edge.mesh = _edge_mesh(h)
	## ★颜色不能跟填充同色相 —— 第一版边框用的就是 COL_SLAM 本色, 只是 alpha 不同,
	##   实拍里跟填充糊成一片(填充 0.22 的琥珀金在黑场上已经是可见的棕, 0.95 只是更饱和)。
	##   ⇒ 换成**亮白黄**, 与琥珀填充拉开明度差, 边界才读得出来。
	edge.material_override = _mat_solid(COL_FIELD_EDGE, 4, true)   # ★true = 双面, 见 _mat_solid
	## ★★边框必须**抬离填充面**, 否则看不见 —— 2026-09-03 第一次实拍就栽在这:
	##   两个 MeshInstance 都在 FIELD_Y、又都 `no_depth_test`, 渲染顺序不由 y 决定,
	##   边框被填充整个盖掉, 实拍出来仍是一块纯棕板(我以为"边框没建出来", 其实建了)。
	##   ⇒ 抬 2cm。`root.scale` 只缩 x/z, y 不缩, 所以这 0.02 就是真实的 2 厘米。
	edge.position.y = 0.02
	root.add_child(edge)
	_adopt(root)
	_place_field(root, ax, dir)
	root.set_meta("h", h)
	return root


## 摆位 + 定向。★朝向由 `dir` 决定(几何), 不靠 billboard 猜 ——
##   blade_eq_vfx 的 `_quad_along` 头注记着: BILLBOARD 会吃掉 roll, 而且不报错。
func _place_field(root: Node3D, ax: Dictionary, dir: Vector2) -> void:
	if not is_instance_valid(root):
		return
	var org: Vector2 = ax.get("pos", Vector2.ZERO)
	root.position = battle._world_pos(org, FIELD_Y)
	root.scale = Vector3(battle.WS, 1.0, battle.WS)
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	## 场地 2D 的 +X/+Y 到世界 3D 的映射由 `_world_pos` 定; 这里只需要绕 Y 转到 dir。
	root.rotation = Vector3(0.0, -atan2(d.y, d.x), 0.0)


## 梯形的**边框** mesh(四条细带)。★宽度用码而不是像素 —— 它跟填充在同一个局部坐标系里。
func _edge_mesh(h: float) -> ArrayMesh:
	var key: int = -int(round(h / AE.CHARGE_H_PER_STEP))   # 负号: 与填充的缓存键分开
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cs: Array = field_corners(float(-key) * AE.CHARGE_H_PER_STEP)
	if cs.size() != 4:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## 边带宽(码)。★★14 → 22 → 14 绕了一圈, 记下来免得下次又改:
	##   我先按 14 出图, 看不见 ⇒ 以为太细, 加宽到 22。**真因是绕向被 CULL_BACK 剔掉,
	##   根本没渲染**(染色法查出来的)。修好绕向后 22 码明显过粗、喧宾夺主。
	##   ⇒ 这正是 memory [[fb-my-thresholds-degrade-good-assets]] 那条:
	##     拿"看不见"当"太细"的证据, 会把参数往错的方向推。先确认它到底渲没渲染。
	var bw := 14.0
	for i in range(4):
		var a: Vector2 = cs[i]
		var b: Vector2 = cs[(i + 1) % 4]
		var d: Vector2 = (b - a)
		if d.length() < 0.001:
			continue
		var nrm: Vector2 = Vector2(-d.y, d.x).normalized() * (bw * 0.5)
		var q: Array = [a + nrm, b + nrm, b - nrm, a - nrm]
		for idx in [0, 1, 2, 0, 2, 3]:
			var p: Vector2 = q[idx]
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	var mesh: ArrayMesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh


## 蓄力推进: 高度变了就换 mesh(8 种, 有缓存)。
## 返回 true = 这一帧真的换了一格(门禁拿它数"长了几格")。
func charge_update(root: Node3D, ax: Dictionary, dir: Vector2, h: float) -> bool:
	if not is_instance_valid(root) or h <= 0.0:
		return false
	_place_field(root, ax, dir)
	var old_h: float = float(root.get_meta("h", -1.0))
	if is_equal_approx(old_h, h):
		return false
	var mesh: ArrayMesh = _field_mesh(h)
	if mesh == null:
		return false
	var fill = root.get_node_or_null("Fill")
	if fill is MeshInstance3D:
		(fill as MeshInstance3D).mesh = mesh
	var edge = root.get_node_or_null("Edge")
	if edge is MeshInstance3D:
		(edge as MeshInstance3D).mesh = _edge_mesh(h)
	root.set_meta("h", h)
	return true


## 收梯形。`flash` = 砸下时的收法: **先闪一下再消失**, 不是直接抹掉。
##
## ★★2026-09-03 实拍后补。原来砸下瞬间梯形直接 queue_free ⇒
##   最该让玩家看清"打的就是这一块"的那一帧, 判定区的信息反而没了
##   (实拍 shot 6: 只剩一个大圆冲击, 完全读不出它是梯形范围)。
##   ⇒ 砸下时把边框拉满亮度闪 0.25 秒再淡掉, 让范围与冲击**同框出现一次**。
func charge_clear(root, flash: bool = false) -> void:
	if root == null or not is_instance_valid(root):
		return
	var n := root as Node3D
	if not flash:
		n.queue_free()
		return
	var edge = n.get_node_or_null("Edge")
	var fill = n.get_node_or_null("Fill")
	if edge is MeshInstance3D:
		(edge as MeshInstance3D).material_override = _mat_solid(Color(1.0, 0.96, 0.80, 1.0), 4, true)
	if fill is MeshInstance3D:
		(fill as MeshInstance3D).material_override = _mat_solid(
			Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.55))
	var tw := n.create_tween()
	## ★hold 0.55: 前 55% 保持满亮 —— 闪光的意义就是"被看见", 一出生就淡等于没闪。
	tw.tween_method(func(v: float) -> void:
			if not is_instance_valid(n):
				return
			var a: float = hold_fade(v, 0.55)
			var e2 = n.get_node_or_null("Edge")
			var f2 = n.get_node_or_null("Fill")
			if e2 is MeshInstance3D:
				(e2 as MeshInstance3D).material_override = _mat_solid(Color(1.0, 0.96, 0.80, a), 4, true)
			if f2 is MeshInstance3D:
				(f2 as MeshInstance3D).material_override = _mat_solid(
					Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.55 * a)),
		0.0, 1.0, 0.25)
	tw.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.queue_free())


# ══════════════════════════════════════════════════════════════════
#  §逐帧动画素材 (PixelLab 2026-09-03 · 斧头专属, 不复用别人的)
# ══════════════════════════════════════════════════════════════════
## ★用户 2026-08-29:「**不要拿图片贴图敷衍我, 我要动画像素特效**」——
##   所以这五张全是 8 帧横排 sheet, 不是一张静止图。
## ★用户 2026-08-03 铁律「素材不复用除非点名」: 这五张是为斧头新生成的,
##   没有拿剑(eq084)那套顶替。
const TEX_CLEAVE := "res://assets/sprites/vfx/eq096-cleave.png"
const TEX_SWEEP := "res://assets/sprites/vfx/eq096-sweep.png"
const TEX_SMASH := "res://assets/sprites/vfx/eq096-smash.png"
const TEX_SLAM := "res://assets/sprites/vfx/eq096-slam.png"
const TEX_HEAL := "res://assets/sprites/vfx/eq096-heal.png"

## 一张 sheet 播多久(秒) —— 跟各自的机制节拍对齐, 不是随手给的:
##   斩击类挂在一次普攻上(间隔 1/MINION_ASPD = 1.25 秒) ⇒ 占 60% = 0.75 秒;
##   猛砸落地是"砸完的余韵" ⇒ 稍长;
##   治疗光柱跟着主动 ⇒ 与 axe_cast 帧表同长。
const DUR_SLASH := 0.75
const DUR_IMPACT := 0.90
const DUR_HEAL := 0.80


## 播一张横排 sheet。返回根 Sprite3D(调用方一般不用管, 到时自己消失)。
##
## ★★三个坑, 都是本仓库付过学费的:
##   ① **帧宽按单帧算, 不是整张 sheet** —— blade 那边的注释:「9 帧的 sheet 直接用
##      会让弧只有该有的 1/9 大」, 这是挂多帧贴图最常见的翻车。
##   ② **必须 NEAREST** —— 否则像素贴图被线性插值糊掉(memory [[fb-vfx-defect-families]])。
##   ③ **不许一出生就线性淡出** —— 走 `hold_fade`, 前 70% 满亮。
func _play_sheet(path: String, pos2d: Vector2, height_m: float, size_px: float,
		col: Color, dur: float, ground: bool = false, yaw: float = 0.0,
		aim_deg: float = 0.0) -> Sprite3D:
	if not _has_world() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST      # 坑②
	s.render_priority = 7
	s.modulate = col
	## ★帧宽 = 图高(横排正方帧) ⇒ hframes = 宽/高。坑①
	var fh: int = maxi(1, tex.get_height())
	var nf: int = maxi(1, int(tex.get_width() / fh))
	s.hframes = nf
	s.frame = 0
	s.pixel_size = (size_px * battle.WS) / float(fh)              # 按【单帧】归一
	if ground:
		## 贴地(横扫/冲击/裂地): 铺在**地面平面**上 —— "看到多宽 = 打到多宽" 才成立。
		## ★用 `ground_basis(dir, aim)` 设整个 basis, **不是** `axis=AXIS_Y + rotation.y`:
		##   后者我试过, 弧永远趴在斧头正下方、不跟攻击方向转(转 180° 也没用)。
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.position = battle._world_pos(pos2d, FIELD_Y)
		s.basis = BladeVfx.ground_basis(Vector2(cos(yaw), sin(yaw)), deg_to_rad(aim_deg))
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.position = battle._world_pos(pos2d, height_m)
	_adopt(s)
	_animate_sheet(s, nf, dur, col)
	return s


## 逐帧推进 + 到期消失。★用 tween 只驱动**演出**, 结算一律不放这里
##   (CLAUDE.md §3.5: 无头 CI 推不动 tween, 数值埋进去 = 本地复现不出来的红)。
func _animate_sheet(s: Sprite3D, nf: int, dur: float, col: Color) -> void:
	if not is_instance_valid(s):
		return
	var tw := s.create_tween()
	tw.set_parallel(true)
	## 帧序: 0 → nf-1 线性。**不 drop 最后一帧** ——
	## memory [[fb-weld-visual-lessons-into-gate]]: 「6 帧只播 5 帧」的真凶就是 drop_last。
	tw.tween_method(func(v: float) -> void:
			if is_instance_valid(s):
				s.frame = clampi(int(v), 0, nf - 1),
		0.0, float(nf) - 0.001, dur)
	## 透明度走 hold_fade: 前 70% 满亮, 后 30% 才淡。
	tw.tween_method(func(v: float) -> void:
			if is_instance_valid(s):
				s.modulate = Color(col.r, col.g, col.b, col.a * hold_fade(v)),
		0.0, 1.0, dur)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(s):
			s.queue_free())


## 被动 4【竖劈】—— 一道竖直下劈的刀光, 落在目标身上。
## ★尺寸 = 斧头攻击距离的 1.1 倍: 这一劈打的就是当前普攻目标, 视觉别比够得着的范围大太多。
func cleave(ax: Dictionary, tgt: Dictionary) -> Sprite3D:
	if not (tgt is Dictionary):
		return null
	var rng: float = float(ax.get("atk_range", 120.0))
	return _play_sheet(TEX_CLEAVE, tgt.get("pos", Vector2.ZERO),
		float(tgt.get("height", 1.0)) * 0.5 + 0.6, rng * 1.1,
		Color(COL_CLEAVE.r, COL_CLEAVE.g, COL_CLEAVE.b, 0.95), DUR_SLASH)


## 被动 5【180° 横扫】—— 贴地的金色大弧。
## ★★直径必须 = `atk_range * 2`: 判定就是"以斧头为心、半径 atk_range 的正面半圆"
##   (`sweep_targets` 里 `rel.length() > rng` 那一行)。画大了 = 玩家以为扫得到却没伤害,
##   画小了 = 反过来。这是"演出即判定"在横扫上的具体含义。
func sweep(ax: Dictionary, dir: Vector2) -> Sprite3D:
	var rng: float = float(ax.get("atk_range", 120.0))
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	## ★朝向交给 `ground_basis` + 量出来的 `SWEEP_AIM_DEG`, 不再自己凑 ±180
	##   (我凑过一次, 没用 —— 根因是 rotation.y 那条路本身就不对)。
	return _play_sheet(TEX_SWEEP, ax.get("pos", Vector2.ZERO), 0.0, rng * 2.0,
		Color(COL_SWEEP.r, COL_SWEEP.g, COL_SWEEP.b, 0.92), DUR_SLASH,
		true, atan2(d.y, d.x), SWEEP_AIM_DEG)


## 被动 3【强化猛砸】—— 目标脚下的贴地冲击环 + 裂纹。
## ★尺寸对应"短暂击退"的推力(SMASH_KNOCK_PUSH), 不是随便一个圈:
##   推力 0.6 是标准击飞的六成 ⇒ 环也取一个偏小的直径, 免得看着像大范围 AOE(它只打一个人)。
func smash(tgt: Dictionary) -> Sprite3D:
	if not (tgt is Dictionary):
		return null
	return _play_sheet(TEX_SMASH, tgt.get("pos", Vector2.ZERO), 0.0, 150.0,
		Color(COL_SMASH.r, COL_SMASH.g, COL_SMASH.b, 0.95), DUR_IMPACT, true, 0.0)


## 被动 6【蓄力猛砸·砸下】—— 落在梯形【中段】的重击裂地。
## ★为什么摆在中段而不是斧头脚下: 判定区是一个从斧头伸出去 h 码的梯形,
##   把冲击画在原点会让玩家以为"只砸了自己脚下"。取 h*0.5 的中轴点。
## ★★尺寸: **它是砸击核心, 不是范围指示器**(2026-09-03 实拍后改)。
##   第一版按"均宽"给了 600 码 ⇒ 实拍 shot 6 里一个大圆盘占满右半屏, 而判定是**梯形**
##   —— 圆盖不住梯形, 形状对不上, 反而制造了"演出≠判定"。
##   范围这件事由**梯形预警**表达(它就是判定区, 而且砸下时会闪一下再消失);
##   这张图负责"砸得很重"这个感受, 取梯形近边宽即可。
##   同族教训 memory [[fb-verify-must-run-the-real-path]]:「把效果半径当贴片尺寸 ⇒
##   公式全对但 19.2m 比战场还长」。
func slam(ax: Dictionary, dir: Vector2, h: float) -> Sprite3D:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var mid: Vector2 = (ax.get("pos", Vector2.ZERO) as Vector2) + d * (h * 0.5)
	return _play_sheet(TEX_SLAM, mid, 0.0, AE.TRAPEZOID_NEAR_W,
		Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.95), DUR_IMPACT, true, atan2(d.y, d.x))


## 主动【治疗 + 护盾】—— 斧头身上升起的绿光柱(底环 = 护盾那一半)。
func heal(ax: Dictionary) -> Sprite3D:
	return _play_sheet(TEX_HEAL, ax.get("pos", Vector2.ZERO),
		float(ax.get("height", 1.0)) * 0.5, 130.0,
		Color(COL_HEAL.r, COL_HEAL.g, COL_HEAL.b, 0.95), DUR_HEAL)
