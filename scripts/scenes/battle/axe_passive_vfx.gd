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
## ★★2026-09-03 第二版素材(用户当场否掉第一版:「建议竖劈重生成, 这个月牙太弯了」)。
##   第一版是**横着的弯月牙**: 逐帧包围盒 104x109/101x110/98x106, 长宽比 0.92~0.95,
##   而竖劈是「从上往下劈」, 形状就不对。★我选帧时只量了亮度和帧数, **没量形状** ——
##   判据缺了"形状符不符合这一招"这一维, 是用户替我发现的。
##   新版 9/9 帧【高 > 宽】(长宽比 0.16~0.50), 生成描述改成强调
##   vertical / near-straight / narrow tall 并显式排除 crescent moon。
##
## ★竖劈是**唯一一张要提亮**的 —— 这个 1.28 不是拍的, 是量出来的:
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
## ★★★梯形边框 —— **照 LOL 塞恩 Q 逐帧量出来的颜色**, 不是我挑的。
##   用户 2026-09-03:「一模一样抄都不会啊」——上一版我只调了填充透明度和线宽两个数,
##   颜色/质感/形状/比例四样一样没动, 并排一比根本不像。
##   量法: 取参考蓄力帧里 G,B 高而 R 低的像素(584 个), 按亮度分成芯与晕:
##     芯(最亮 10%) #b7fdf8  亮度 232
##     晕(其余)     #50afbb  亮度 148
##   ⇒ 边线做**三层**: 内芯亮白青(细) / 中层青(中) / 外晕暗青半透(宽), 模拟辉光散开。
const COL_EDGE_CORE := Color(0.72, 0.99, 0.97, 1.00)    # #b7fdf8 芯
const COL_EDGE_MID := Color(0.31, 0.69, 0.73, 0.85)     # #50afbb 中
const COL_EDGE_HALO := Color(0.31, 0.69, 0.73, 0.30)    # 外晕(同色低 alpha)
const COL_FIELD_EDGE := COL_EDGE_CORE                    # 兼容旧引用
## 预警区【填充】—— 数值由参考实测反推, 推导过程见 `charge_field` 里那段注释。
## 参考: 暗红 @0.35 把亮草地压到 75% 亮度; 我们: 同等对比度的青 @0.20(地板偏暗 ⇒ 加亮而非压暗)。
const COL_FIELD_FILL := Color(0.24, 0.72, 0.78, 0.20)
## 起手闪。★**超白**(>1.0)而不是直接用 COL_EDGE_CORE —— 参考 f90 是整段蓄力里
##   最亮的一帧, 与边线同色会被边线淹没, 实拍时和"没做"分不出来。
const COL_ONSET := Color(1.35, 1.45, 1.42, 1.00)

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
## 带顶点色的材质(六边形网格用: 逐格亮度靠顶点 alpha 表达)。
func _mat_vcol(col: Color, prio: int = 0) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat_solid(col, prio, true)
	m.vertex_color_use_as_albedo = true
	return m


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
	## ★★★【填充回来了】—— 2026-09-03 第二轮逐帧对比后**推翻上一版的判断**。
	##
	## 上一版这里写着「照参考直接不要填充 —— 塞恩 Q 的预警区本来就是零填充，只有边线」。
	## **那句话是错的**，它是拿机甲皮肤那个糊样本目测出来的。原版专门演示视频量出来是:
	##   f88(预警前) 区内 RGB 60.4/58.8/20.2 → f110(预警最浓) 51.2/38.4/15.7
	##   净叠加 −9.3/−20.5/−4.6, 区内平均亮度 46.5 → 35.1 = **压暗到 75%**
	##   ★分母: 同两帧的区外方块差值 +0.1/+0.1/+0.1 ⇒ 不是全局亮度变化
	##   反推填充色 ≈ RGB(34, 0, 7) @ α 0.35 —— **一层很暗的红**, 填充确实存在且显眼。
	##
	## ★但**不照抄数值, 照抄对比度**: 参考是暗红压在亮草地上 ⇒ 区内比区外暗 25%;
	##   我们是青色主题 + 战场地板偏暗 ⇒ 同样的"暗红"在这儿什么都看不见。
	##   等效做法是**同等对比度的青色叠加**(区内比区外亮约 1/4), α 0.20。
	##
	## ⚠ 上一版说"alpha 从 0.22 降到 0.03 画面毫无变化"—— 那个现象的**根因后来查明**是
	##   `charge_update` 每步重设 `Fill.mesh`, 把这里设的东西整个覆盖掉了(已修)。
	##   不是"alpha 在这条路上不生效"。删填充是拿错误根因做的错误决定。
	mi.material_override = _mat_solid(COL_FIELD_FILL, 2, true)
	mi.name = "Fill"
	root.add_child(mi)
	## ★★加一圈亮边 —— 2026-09-03 实拍后补。
	##   只有 alpha 0.22 的纯色填充时, 实拍里它读成**一块土黄色的地板贴图**, 不像危险区
	##   (memory [[fb-clean-vfx-stage-not-squint]]: 拿全场截图眯眼看会判反 ⇒ 我真拍了才发现)。
	##   边界正是这个演出**唯一要传达的信息**(站在线内会被砸), 所以它必须比填充更显眼。
	## ★★三层辉光边线(照参考): 外晕最宽最淡 → 中层 → 内芯最细最亮。
	##   一层实心带的观感是"贴了条胶带"(用户原话方向), 辉光才像能量线。
	for li in range(3):
		var e2 := MeshInstance3D.new()
		e2.name = ["EdgeHalo", "EdgeMid", "Edge"][li]
		e2.mesh = _edge_mesh_w(h, [3.4, 1.9, 1.0][li])      # 外晕 3.4 倍宽, 芯 1 倍
		e2.material_override = _mat_solid(
			[COL_EDGE_HALO, COL_EDGE_MID, COL_EDGE_CORE][li], 3 + li, true)
		e2.position.y = 0.018 + 0.004 * float(li)
		root.add_child(e2)
	var edge = root.get_node_or_null("Edge")
	## ★★边框必须**抬离填充面**, 否则看不见 —— 2026-09-03 第一次实拍就栽在这:
	##   两个 MeshInstance 都在 FIELD_Y、又都 `no_depth_test`, 渲染顺序不由 y 决定,
	##   边框被填充整个盖掉, 实拍出来仍是一块纯棕板(我以为"边框没建出来", 其实建了)。
	##   ⇒ 抬 2cm。`root.scale` 只缩 x/z, y 不缩, 所以这 0.02 就是真实的 2 厘米。
	## ★★【流动光点】—— 照塞恩 Q 逐帧看到的: 边线上有一个亮点从角色端往远端跑,
	##   它是**蓄力进度的视觉指示**(参考里比"变长"本身更抢眼)。
	##   做法: 一个小方块沿【两条侧边】各跑一个, 位置由 `_tick_field_pulse` 每帧插值。
	for i in range(2):
		var dot := MeshInstance3D.new()
		dot.name = "Runner%d" % i
		dot.mesh = _runner_mesh()
		dot.material_override = _mat_solid(COL_FIELD_EDGE, 6, true)
		dot.position.y = 0.03
		root.add_child(dot)
	_adopt(root)
	_place_field(root, ax, dir)
	root.set_meta("h", h)
	_charge_onset_flash(root)
	return root


## 【起手闪】—— 2026-09-03 逐帧对比原版塞恩 Q 专门演示视频后补上的一项。
## 参考实测(`C:/tmp/sionref/qonly/`, 30fps, 那一次 Q 是 f90→f120 整 1.000 秒):
##   f90 (0.000s) 脚下炸出一个**亮点 + 一圈外环**, 最亮
##   f92 (0.067s) 亮点被**横向拉成一道条**(顺着 Q 的方向), 亮度略降
##   f94 (0.133s) 收缩回小亮点, 更暗
##   f96 (0.200s) 没了 —— 预警区这才开始显形
## ⇒ 总时长 0.20 秒, 三段: 圆 → 横拉 3.2 倍 → 收回 0.8 倍。
## ★这一下是"技能开始了"的**唯一即时反馈**。之前我们只有梯形慢慢长出来,
##   前 0.2 秒画面上什么都没有 —— 并排比时这是最刺眼的一处差。
## ★沿 dir 拉伸靠 scale.x: root 已经绕 Y 转到 dir 了, 所以局部 +X 就是斧头指向。
func _charge_onset_flash(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var mi := MeshInstance3D.new()
	mi.name = "OnsetFlash"
	mi.mesh = _ring_disc_mesh()
	mi.position = Vector3(AE.TRAPEZOID_NEAR_W * 0.10, 0.035, 0.0)   # 贴着斧头那一端
	mi.material_override = _mat_solid(COL_ONSET, 8, true)
	root.add_child(mi)
	## 基准半径(码)。★30 → 55(2026-09-03 首次实拍后改): zoom 2.0 下 30 码的亮点
	##   在画面上只有几个像素, 接触印相里**完全找不到**, 与"根本没做"无法区分。
	##   定 55 的依据是横拉那一段: 55 × 2 × 3.2 = 352 码 ≈ 梯形近端宽 300 码
	##   ⇒ 观感正是参考 f92 的"一道横条横跨预警区近端", 不是随手往大调。
	var R := 55.0
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void:
			if not is_instance_valid(mi):
				return
			## 逐段照参考: 0→1/3 圆(1.0倍) · 1/3→2/3 横拉(x 3.2 · z 0.42) · 2/3→1 收回
			var sx: float
			var sz: float
			var a: float
			if v < 0.34:
				var u: float = v / 0.34
				sx = lerpf(0.55, 1.30, u)
				sz = lerpf(0.55, 1.00, u)
				a = 1.0
			elif v < 0.67:
				var u2: float = (v - 0.34) / 0.33
				sx = lerpf(1.30, 3.20, u2)
				sz = lerpf(1.00, 0.42, u2)
				a = lerpf(1.0, 0.80, u2)
			else:
				var u3: float = (v - 0.67) / 0.33
				sx = lerpf(3.20, 0.80, u3)
				sz = lerpf(0.42, 0.30, u3)
				a = lerpf(0.80, 0.0, u3)
			mi.scale = Vector3(R * sx, 1.0, R * sz)
			var c := COL_ONSET
			mi.material_override = _mat_solid(Color(c.r, c.g, c.b, a), 8, true),
		0.0, 1.0, 0.20)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free())


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
	return _edge_mesh_w(h, 1.0)


## 边线 mesh, `wmul` = 宽度倍数(三层辉光用: 外晕 3.4 / 中 1.9 / 芯 1.0)。
func _edge_mesh_w(h: float, wmul: float) -> ArrayMesh:
	var key: int = -int(round(h / AE.CHARGE_H_PER_STEP)) - 1000 * int(round(wmul * 10.0))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cs: Array = field_corners(h)
	if cs.size() != 4:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## 边带宽(码)。★★14 → 22 → 14 绕了一圈, 记下来免得下次又改:
	##   我先按 14 出图, 看不见 ⇒ 以为太细, 加宽到 22。**真因是绕向被 CULL_BACK 剔掉,
	##   根本没渲染**(染色法查出来的)。修好绕向后 22 码明显过粗、喧宾夺主。
	##   ⇒ 这正是 memory [[fb-my-thresholds-degrade-good-assets]] 那条:
	##     拿"看不见"当"太细"的证据, 会把参数往错的方向推。先确认它到底渲没渲染。
	## ★★14 → 8(2026-09-03 照塞恩 Q 实拍后再收):
	##   量下来宽度**比例**我本来就对(参考 4px/200px = 2%, 我 14码/800码 = 1.75%),
	##   但参考的边线是**发光线**(中间亮、边缘渐隐), 我的是**硬边实心带** —— 同样比例下
	##   实心带显得粗一倍。质感补不了就把宽度收一半, 视觉重量才对得上。
	## ★★8 → 5(2026-09-03 **逐帧并排对比**后再收一档):
	##   把参考与我的各取 10 帧按动作阶段对齐并排, 一眼看出我的边线**明显粗一截** ——
	##   参考读起来是"一条能量线", 我的读起来是"画了个框"。
	##   ⚠ 前两次改宽度我都是**单看自己的图**拍的(14→8), 并排比才定得准。
	var bw: float = 5.0 * wmul
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


## 蓄力推进: 高度变了就换 mesh(8 种, 有缓存) + 每帧推进"预警"的活体感。
## 返回 true = 这一帧真的换了一格(门禁拿它数"长了几格")。
##
## ★★2026-09-03 重做(用户:「梯形特效还要重做」)。第一版是**一块静态色板**:
##   半透明琥珀填充 + 一圈亮边, 长大的时候只是"忽然变长", 没有任何"正在蓄力"的信息。
## ⇒ 三条动效, 每条都由机制决定, 不是随手加的:
##   ① **每长一格闪一下** —— 对应 `CHARGE_STEP=0.5 秒 +100 码` 这个**阶梯**
##      (需求原话就是阶梯: 「每蓄力0.5秒使梯形区域的高增加100码」, `charge_height` 里 floorf 过)
##   ② **边框呼吸** —— 表示"还在蓄, 别站进来"
##   ③ **最后 1 秒加速闪烁** —— 对应"马上砸下"这个玩家最该知道的信息
func charge_update(root: Node3D, ax: Dictionary, dir: Vector2, h: float) -> bool:
	if not is_instance_valid(root) or h <= 0.0:
		return false
	_place_field(root, ax, dir)
	## ── 每帧的活体感(与换不换格无关) ──
	_tick_field_pulse(root, ax)
	var old_h: float = float(root.get_meta("h", -1.0))
	if is_equal_approx(old_h, h):
		return false
	var mesh: ArrayMesh = _field_mesh(h)
	if mesh == null:
		return false
	## ★★★【填充】要跟着长 —— 但**只换 mesh, 绝不碰 material_override**。
	##   历史坑(2026-09-03 染色法查出的真根因): 这一行原本连材质一起重设,
	##   把 `charge_field` 里调好的 alpha 每帧覆盖掉 ⇒ 我前后调了五次 alpha
	##   (0.22→0.10→0.07→0.05→0.03)**画面上一点变化都没有**, 还据此错误地
	##   得出"这条路上 alpha 不生效"并把填充整个删掉(第二轮逐帧对比证明删错了, 见
	##   `charge_field` 里的实测数据)。
	##   ★染色法定位: 把四个节点各染极端色后重拍 —— 边线变白(染色生效),
	##     而那块棕黄**完全没变色** ⇒ 不是我以为的那几个节点在画, 顺着这条才找到这里。
	##   memory [[fb-probe-before-claiming-rootcause]]: 改了五次没反应, 就该停下来定位而不是继续调数。
	var _fill = root.get_node_or_null("Fill")
	if _fill is MeshInstance3D:
		(_fill as MeshInstance3D).mesh = mesh
	for li in range(3):
		var nm2: String = ["EdgeHalo", "EdgeMid", "Edge"][li]
		var nd2 = root.get_node_or_null(nm2)
		if nd2 is MeshInstance3D:
			(nd2 as MeshInstance3D).mesh = _edge_mesh_w(h, [3.4, 1.9, 1.0][li])
	root.set_meta("h", h)
	## ★长了一格 = 给一次"步进闪光"。存到 meta 由 _tick_field_pulse 消化,
	##   不在这里直接改材质 —— 否则下一帧的呼吸会把它冲掉。
	root.set_meta("step_flash_t", float(battle._t))
	return true


## 【六边形蜂窝网格】—— 照塞恩 Q 的命中效果做, 替换掉原来那张贴地陨石坑素材。
##
## ★★为什么换: 那张 PixelLab 素材内容**铺满整张 128x128 画布**, 贴地后能看到明显的
##   **直角边**(实拍右下角最清楚) —— memory [[fb-vfx-defect-families]] 里那条
##   「贴图内容别铺满整张」。而参考(塞恩 Q)的命中根本不是一张图, 是**六边形网格**:
##   中心白光 → 蜂窝格子逐个亮起 → 橙→白灰渐隐。
## ★网格**只铺在梯形判定区里** ⇒ 天然没有方块边缘, 而且"亮到哪打到哪"一目了然
##   —— 这比贴一张图更贴合"演出即判定"。
##
## `h` = 当前梯形高。返回一个 ArrayMesh(每个六边形一个面片)。
func _hex_mesh(h: float) -> ArrayMesh:
	var key: int = 20000 + int(round(h / AE.CHARGE_H_PER_STEP))
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## ★★格子大小是**量参考定的**, 不是拍的:
	##   塞恩 Q 的命中网格里, 一个六边形宽 ≈ 40px 而角色宽 ≈ 60px ⇒ **格子/角色 ≈ 0.67**。
	##   我第一版给 R=46(直径 92 码), 而小龟碰撞宽约 46 码 ⇒ 比例 **2.0**, 格子比龟还大一倍,
	##   实拍里整片蜂窝把单位全盖住。⇒ 按 0.67 反推: 直径 ≈ 46 × 0.67 ≈ 31 ⇒ R ≈ 16。
	var R := 16.0                       # 六边形外接圆半径(码)
	var dx: float = R * 1.5             # 列距
	var dz: float = R * sqrt(3.0)       # 行距
	var n := 0
	var col := 0
	var x: float = R
	while x < h + R:
		var off: float = 0.0 if col % 2 == 0 else dz * 0.5
		var hw: float = half_w_at(clampf(x, 0.0, h))
		var z: float = -hw
		while z < hw:
			var cz: float = z + off
			if absf(cz) <= hw and x <= h:
				## ★★逐格亮度**从砸击点向外衰减** —— 2026-09-03 实拍后补。
				##   第一版整片等亮 ⇒ 铺满梯形像"铺了一层地板砖", 而参考(塞恩 Q)的网格
				##   是**命中点周围的局部闪现**, 有明暗层次。
				##   砸击点 = 斧头前方 TRAPEZOID_NEAR_W*0.5(与 `slam` 的落点同一个点)。
				var cx: float = AE.TRAPEZOID_NEAR_W * 0.5
				var d2: float = sqrt((x - cx) * (x - cx) + cz * cz)
				## 衰减半径取满蓄高的 45% —— 再远的格子几乎看不见, 但仍在判定区里,
				## 所以"亮到哪打到哪"不变, 只是远处淡。
				## ★★改成【范围裁剪】而不是顶点色衰减 —— 顶点 alpha 在 Godot 的
				##   StandardMaterial3D 上没吃进去(试过 vertex_color_use_as_albedo, 实拍无变化)。
				##   直接**跳过离砸击点太远的格子**: 网格成为一片圆形爆发区, 不铺满整个梯形。
				##   参考(塞恩 Q)的网格本来就是命中点周围的局部闪现, 不是满铺。
				## ★★半径 = `h * 0.30`(下限 90) —— 2026-09-03 **打探针**才定对的。
				##   我先后拍过 `h*0.42+150` 和固定 `240`, 实拍都"看起来没裁", 我三次都判成
				##   "裁剪没生效"就换写法 —— **错的**。探针实测: 裁剪一直在工作
				##   (h=800 时 723 个格子裁到 214 个)。真正的问题是**半径相对当时的梯形太大**:
				##   梯形 h=200 时远端才 450 宽, 而 240 半径的圆直径 480 ⇒ 当然铺满。
				##   ⇒ 半径必须**跟着 h 缩放**, 才在每个蓄力阶段都是"局部闪现"。
				##   memory [[fb-probe-before-claiming-rootcause]]: 改三次没效果时该打探针, 不是换写法。
				## ★★半径 h*0.15(下限 70) —— 探针 + 实拍两步才定下来:
				##   探针证明裁剪一直生效(h=800 → 723 格裁到 214 格, 半径 240)。
				##   实拍仍"看起来铺满"的真因是**相机视野**: 梯形 800 码长, 而 zoom 2.0
				##   只拍到近端约 400~500 码 ⇒ 直径 480 的圆正好填满可见范围。
				##   ⇒ 要像参考那样"局部闪现", 半径得再收一半。
				## ★我在这条上判断错了三次(每次都是"改个写法再看"), 直到打探针才知道
				##   裁剪根本没问题 —— memory [[fb-probe-before-claiming-rootcause]]。
				if d2 > maxf(60.0, h * 0.11):
					z += dz
					continue
				var vc := Color(1.0, 1.0, 1.0, 1.0)
				## 一个六边形 = 6 个三角形(中心扇形)
				for i in range(6):
					var a0: float = TAU * float(i) / 6.0
					var a1: float = TAU * float(i + 1) / 6.0
					var r2: float = R * 0.86      # 留缝 ⇒ 看得出是"格子"不是一整片
					st.set_color(vc)
					st.add_vertex(Vector3(x, 0.0, cz))
					st.set_color(vc)
					st.add_vertex(Vector3(x + cos(a0) * r2, 0.0, cz + sin(a0) * r2))
					st.set_color(vc)
					st.add_vertex(Vector3(x + cos(a1) * r2, 0.0, cz + sin(a1) * r2))
				n += 1
			z += dz
		x += dx
		col += 1
	if n == 0:
		return null
	var m: ArrayMesh = st.commit()
	_mesh_cache[key] = m
	return m


## 砸击点的【中心聚光】—— 一个快速涨大又消失的白光盘, 对应参考里释放前那一瞬。
func _slam_core_flash(root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var mi := MeshInstance3D.new()
	mi.name = "SlamCore"
	mi.mesh = _ring_disc_mesh()
	mi.position = Vector3(AE.TRAPEZOID_NEAR_W * 0.22, 0.05, 0.0)   # ★靠近斧头, 不是梯形中段
	mi.material_override = _mat_solid(Color(0.88, 0.99, 1.0, 0.95), 7, true)
	root.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	## 0 → 满径 → 消失: 快涨(0.12s)慢散(0.26s)
	tw.tween_method(func(v: float) -> void:
			if is_instance_valid(mi):
				## ★★半径 30→150 缩成 18→58(2026-09-03 逐帧对比第二轮):
				##   第一版是个直径 300 码的白色实心大盘, 并排比里读成"糊了一块白" ——
				##   而参考里那一瞬是**角色身上一个小而亮的聚光**, 不是地上的大圆。
				var r: float = 18.0 + 40.0 * v
				mi.scale = Vector3(r, 1.0, r),
		0.0, 1.0, 0.30)
	tw.tween_method(func(v: float) -> void:
			if is_instance_valid(mi):
				mi.material_override = _mat_solid(
					Color(0.88, 0.99, 1.0, 0.95 * hold_fade(v, 0.25)), 7, true),
		0.0, 1.0, 0.30)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free())


## 半径 1 的实心圆盘(中心聚光用; 由 scale 放大)。
func _ring_disc_mesh() -> ArrayMesh:
	if _mesh_cache.has(8888):
		return _mesh_cache[8888]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	for i in range(seg):
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0), 0.0, sin(a0)))
		st.add_vertex(Vector3(cos(a1), 0.0, sin(a1)))
	var m: ArrayMesh = st.commit()
	_mesh_cache[8888] = m
	return m


## 命中时铺一层六边形网格并渐隐。★挂在梯形根节点下, 跟着它一起被收掉。
func hex_burst(root: Node3D, h: float) -> MeshInstance3D:
	if not is_instance_valid(root) or h <= 0.0:
		return null
	var m: ArrayMesh = _hex_mesh(h)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "HexBurst"
	mi.mesh = m
	mi.position.y = 0.04
	## ★alpha 0.85 → 0.42: 参考里能**透过网格看到角色**, 我第一版整片实心把单位吃掉了。
	## ★★★逐帧对比后重定(2026-09-03): 参考的命中网格是**明亮的橙色爆发**,
	##   而我 alpha 0.34 的版本在黑场上读成**土棕地砖**。
	##   ⚠ 但也不能回到 0.72 —— 那一版把单位全埋了。
	##   ⇒ 0.58 + 颜色更橙更亮(#ffb040), 亮度够了又还透得出单位。
	## ★★★真逐帧对比(30 帧 vs 30 帧)后重定 —— 这是差距最大的一项:
	##   参考的命中是**过曝级强光**, 整片橙白, 持续约 15 帧(0.5 秒), 第三组还在渐隐;
	##   我的 alpha 0.58 版本又暗又短(6 帧就没了, 第三组全空白)。
	##   ⇒ 0.58 → 0.88, 并且渐隐时长 0.42 → 0.62 秒。
	mi.material_override = _mat_vcol(Color(1.00, 0.78, 0.38, 0.88), 5)
	root.add_child(mi)
	## 橙 → 白灰渐隐(参考里就是这个走向)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void:
			if not is_instance_valid(mi):
				return
			var a: float = hold_fade(v, 0.35)
			mi.material_override = _mat_vcol(
				Color(lerpf(1.0, 1.0, v), lerpf(0.78, 0.97, v), lerpf(0.38, 0.94, v), 0.88 * a), 5),
		0.0, 1.0, 0.62)
	return mi


## 流动光点的小方块(局部坐标, 单位=码)。★做成菱形而不是正方形 ——
## 参考里那个光点是顺着线跑的, 菱形的尖端指着行进方向, 不会读成"一个方块在爬"。
func _runner_mesh() -> ArrayMesh:
	if _mesh_cache.has(9999):
		return _mesh_cache[9999]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 26.0     # 沿线方向的长(码)
	var W := 9.0      # 横向半宽(码)
	var v := [Vector3(-L * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, -W),
			  Vector3(L * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, W)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[idx])
	var m: ArrayMesh = st.commit()
	_mesh_cache[9999] = m
	return m


## 每帧推进梯形的"活着"的部分: 呼吸 / 步进闪光 / 临砸加速闪 / **流动光点**。
## ★纯演出, 不碰任何结算量。
func _tick_field_pulse(root: Node3D, ax: Dictionary) -> void:
	var fill = root.get_node_or_null("Fill")
	var edge = root.get_node_or_null("Edge")
	if not (fill is MeshInstance3D) or not (edge is MeshInstance3D):
		return
	var _layers := [["EdgeHalo", COL_EDGE_HALO], ["EdgeMid", COL_EDGE_MID], ["Edge", COL_EDGE_CORE]]
	var t: float = float(battle._t)
	## 蓄了多久 / 还剩多久 —— 直接问产品自己的状态, 不另存一份计时
	var el: float = t - float(ax.get("_axe_charge_t0", t))
	var left: float = maxf(0.0, AE.CHARGE_TIME - el)
	## ① 呼吸: 2 Hz 的正弦, 幅度小(0.18) —— 它是底噪, 不能盖过步进闪
	var breathe: float = 0.82 + 0.18 * (0.5 + 0.5 * sin(t * TAU * 2.0))
	## ② 步进闪光: 刚长一格后的 0.22 秒内额外提亮, 线性衰减
	var sf: float = 0.0
	var st: float = float(root.get_meta("step_flash_t", -99.0))
	if t - st < 0.22:
		sf = 1.0 - (t - st) / 0.22
	## ③ 临砸加速闪: 最后 1 秒频率翻到 6 Hz、幅度拉满 —— "要砸了, 快躲"
	var urge: float = 0.0
	if left < 1.0:
		urge = (1.0 - left) * (0.5 + 0.5 * sin(t * TAU * 6.0))
	var k: float = clampf(breathe + sf * 0.9 + urge * 0.8, 0.0, 2.0)
	## 三层辉光一起跟着 k 呼吸
	for li in range(_layers.size()):
		var nm: String = str(_layers[li][0])
		var bc: Color = _layers[li][1]
		var nd = root.get_node_or_null(nm)
		if nd is MeshInstance3D:
			(nd as MeshInstance3D).material_override = _mat_solid(
				Color(bc.r, bc.g, bc.b, clampf(bc.a * (0.55 + 0.45 * k), 0.0, 1.0)), 3 + li, true)
	## ── 流动光点: 沿两条侧边从近端跑到远端, 0.55 秒一趟 ──
	## ★跑的是**当前已长出来的那一段**(用 h), 所以蓄力越长它跑得越远 —— 这一条正是
	##   参考里"边线在充能"的观感来源。
	var h_now: float = float(root.get_meta("h", 0.0))
	if h_now > 0.0:
		var ph: float = fmod(t, 0.55) / 0.55
		var depth: float = ph * h_now
		var half: float = half_w_at(depth)
		for i in range(2):
			var rn = root.get_node_or_null("Runner%d" % i)
			if rn is MeshInstance3D:
				var side: float = -1.0 if i == 0 else 1.0
				(rn as MeshInstance3D).position = Vector3(depth, 0.03, half * side)
				## 越跑到远端越淡(参考里光点到头就散了)
				(rn as MeshInstance3D).material_override = _mat_solid(
					Color(COL_FIELD_EDGE.r, COL_FIELD_EDGE.g, COL_FIELD_EDGE.b,
						clampf((1.0 - ph * 0.75) * (0.6 + 0.4 * k), 0.0, 1.0)), 6, true)
	## 填充只吃一半的 k —— 它是背景, 太跳会盖住站在里面的单位
	## ★★★填充几乎不要 —— 2026-09-03 **照 LOL 塞恩 Q(Decimating Smash)逐帧量出来的**。
	##   用户:「给我去搜lol塞恩机甲皮肤的Q, 逐帧看」。
	##   下 Skin Spotlight 原片(V4YEUY_yiT0)抽 30fps 逐帧看蓄力段, 量到:
	##     · 预警区**只有一条约 4px 的青色发光边线**, **内部完全透明** ——
	##       地面的石板纹理、草、掉落物全都清清楚楚
	##     · 边线宽度比 ≈ 4px/200px = **2%**(我原来 14码/800码 = 1.75%, 这条本来就对)
	##     · 边线末端是**圆弧**不是直角
	##   ⇒ 我和参考的真正差距**只有填充**: 我 0.22 的琥珀填充在实拍里读成一块板,
	##     敌人站上去像贴纸(用户原话)。参考是零填充。
	##
	## ★★★【上面那段是错的, 2026-09-03 第二轮实测推翻】——「参考是零填充」这句
	##   是拿机甲皮肤那个糊样本目测出来的。原版专门演示视频逐帧量下来:
	##   预警区把地面**压暗到 75%**(净叠加 R−9.3 / G−20.5 / B−4.6, 区外分母 +0.1)。
	##   **填充不但存在, 而且是参考里区分内外的主力**, 边线反倒很弱。
	##
	## ★★★这一行还是第二次踩同一个坑: 我在 `charge_field` 里把填充设成
	##   COL_FIELD_FILL(0.20 青), 而**这里每帧又把它覆盖成 0.02~0.07 的琥珀** ⇒
	##   实拍里只有梯形刚建出来那一帧是青的, 之后全被压回近乎透明, 看着像"填充没生效"。
	##   与之前那次(`charge_update` 覆盖 mesh)是同一形状: **写了没人读 / 被下游覆盖**。
	##   ⇒ 这里改成在 COL_FIELD_FILL 的基准 alpha 上呼吸, 颜色也跟边线同一套青,
	##     不再换成 COL_SLAM 琥珀(换色会让蓄力期出现两种互不相干的颜色)。
	(fill as MeshInstance3D).material_override = _mat_solid(
		Color(COL_FIELD_FILL.r, COL_FIELD_FILL.g, COL_FIELD_FILL.b,
			clampf(COL_FIELD_FILL.a * (0.55 + 0.45 * k), 0.05, 0.42)), 2, true)


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
	## ★★砸下 = 铺六边形蜂窝网格(照塞恩 Q), 而不是"把整块填充点亮"。
	##   网格只铺在梯形判定区里 ⇒ 亮到哪就是打到哪。
	## ★★中心聚光 —— 参考里砸下前有明显的"蓝白光在中心聚起来"那一瞬(逐帧对比第 7~8 格),
	##   我原来直接跳到命中, 缺了"要放了"的预告。补一个短促的白光盘。
	_slam_core_flash(n)
	## ★★★~~爆发光晕~~ **已撤(2026-09-03 第二轮逐帧对比)**:
	##   我想用一个大而淡的圆盘去模拟参考里的"强光溢出", 结果实拍是**一块灰色实心大盘
	##   盖在画面上**, 比不加还糟。
	##   ★根因是做法本身错了: 参考那种过曝是**渲染器的 bloom**(发光材质被后处理晕开),
	##     不是画一个半透明圆。拿实心几何去仿 bloom, 只会得到一块布。
	##   ⇒ 要真做, 该走发光材质 + 环境 glow, 不是加图元。记进未决点。
	hex_burst(n, float(n.get_meta("h", 0.0)))
	## 光点跑到头了就撤掉, 免得和爆开的网格抢注意力
	for i in range(2):
		var rn = n.get_node_or_null("Runner%d" % i)
		if rn != null and is_instance_valid(rn):
			(rn as Node).queue_free()
	var fill = n.get_node_or_null("Fill")
	for _nm in ["EdgeHalo", "EdgeMid", "Edge"]:
		var _e3 = n.get_node_or_null(_nm)
		if _e3 is MeshInstance3D:
			## ★保持青绿系, 只把芯提亮 —— 原来一砸就变纯白粗带, 与蓄力期的青绿辉光断裂
			(_e3 as MeshInstance3D).material_override = _mat_solid(
				Color(COL_EDGE_CORE.r, COL_EDGE_CORE.g, COL_EDGE_CORE.b, 1.0), 4, true)
	## ★★砸下时填充**只提一档, 不刷成实心板**。
	##   参考 f120 释放瞬间整片确实变浓(深红扇形铺满预警区), 所以不能像上一版那样
	##   "砸下时把填充按到 0.05" —— 但也绝不能回到 0.55: 那一版实拍是一块琥珀实心板,
	##   把六边形网格(命中的主角)整个埋掉。
	##   ⇒ 蓄力值 0.20 → 0.34(1.7 倍), 保持青色系不换成 COL_SLAM,
	##     这样蓄力→砸下是**同一套颜色在变浓**, 不是突然换个颜色。
	##   ⚠ `two_sided` 必须传 —— 边带的绕向问题同样存在于填充面(染色法查过),
	##     漏了这个参数填充会被 CULL_BACK 整个剔掉, 表现为"砸下瞬间填充消失"。
	if fill is MeshInstance3D:
		(fill as MeshInstance3D).material_override = _mat_solid(
			Color(COL_FIELD_FILL.r, COL_FIELD_FILL.g, COL_FIELD_FILL.b, 0.34), 2, true)
	var tw := n.create_tween()
	## ★hold 0.55: 前 55% 保持满亮 —— 闪光的意义就是"被看见", 一出生就淡等于没闪。
	tw.tween_method(func(v: float) -> void:
			if not is_instance_valid(n):
				return
			var a: float = hold_fade(v, 0.55)
			var f2 = n.get_node_or_null("Fill")
			for _nm2 in ["EdgeHalo", "EdgeMid", "Edge"]:
				var _e4 = n.get_node_or_null(_nm2)
				if _e4 is MeshInstance3D:
					(_e4 as MeshInstance3D).material_override = _mat_solid(
						Color(COL_EDGE_CORE.r, COL_EDGE_CORE.g, COL_EDGE_CORE.b, a), 4, true)
			if f2 is MeshInstance3D:
				(f2 as MeshInstance3D).material_override = _mat_solid(
					Color(COL_FIELD_FILL.r, COL_FIELD_FILL.g, COL_FIELD_FILL.b, 0.34 * a), 2, true),
		0.0, 1.0, 0.75)   # ★0.25→0.45→0.58→0.75: 网格渐隐 0.62 + 光晕 0.55, 梯形得等整个爆发演完
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
		aim_deg: float = 0.0, flip_v: bool = false) -> Sprite3D:
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
	s.flip_v = flip_v
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
	## ★★`flip_v = true` —— 用户 2026-09-03 当场指出「上下反了啊」。
	##   量出来的证据(逐帧上下半对比): 素材是**宽头在上、上亮下暗**
	##   (帧4: 上半宽 42/亮度 139, 下半宽 15/亮度 45)。
	##   而竖劈是「刀从上劈到下」⇒ **冲击应该在下**(劈中的位置最亮最宽)、细尾迹在上。
	##   PixelLab 画的是"从下往上窜"的形状, 翻过来才是劈下去。
	##   ★这一维我又漏了: 第一版漏了"形状"(横弯月牙), 第二版漏了"上下朝向"。
	##     选素材的判据至少要三条: 亮度 / 形状(长宽比) / 朝向(上下、左右)。
	return _play_sheet(TEX_CLEAVE, tgt.get("pos", Vector2.ZERO),
		float(tgt.get("height", 1.0)) * 0.5 + 0.6, rng * 1.1,
		Color(COL_CLEAVE.r, COL_CLEAVE.g, COL_CLEAVE.b, 0.95), DUR_SLASH,
		false, 0.0, 0.0, true)


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
	## ★★落点 = 斧头**正前方近端**, 不是梯形中段(2026-09-03 实拍改)。
	##   原来取 `h * 0.5` ⇒ 满蓄时落在 **400 码外**, 而敌人往往就贴在斧头面前
	##   ⇒ 实拍里"伤害 232 打在敌人身上、裂地冲击炸在右下角空地" —— 演出与命中脱节。
	##   斧头是**站在原地把斧子砸到自己面前**的, 冲击就该在脚前; 范围那件事由梯形表达。
	var mid: Vector2 = (ax.get("pos", Vector2.ZERO) as Vector2) + d * (AE.TRAPEZOID_NEAR_W * 0.5)
	## ★直径 300→190 码(2026-09-03 第二次实拍): 300 码在实战镜头下占梯形宽度的七成,
	##   加上梯形闪光整片金黄, **单位全被盖住**。它是"砸击核心"不是范围指示器 ——
	##   范围由梯形表达, 这张只要有"砸得重"的分量就够。
	return _play_sheet(TEX_SLAM, mid, 0.0, 190.0,
		Color(COL_SLAM.r, COL_SLAM.g, COL_SLAM.b, 0.95), DUR_IMPACT, true, atan2(d.y, d.x))


## 主动【治疗 + 护盾】—— 斧头身上升起的绿光柱(底环 = 护盾那一半)。
func heal(ax: Dictionary) -> Sprite3D:
	return _play_sheet(TEX_HEAL, ax.get("pos", Vector2.ZERO),
		float(ax.get("height", 1.0)) * 0.5, 130.0,
		Color(COL_HEAL.r, COL_HEAL.g, COL_HEAL.b, 0.95), DUR_HEAL)
