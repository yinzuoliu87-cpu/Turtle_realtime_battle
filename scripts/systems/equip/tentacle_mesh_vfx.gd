class_name TentacleMeshVfx
extends RefCounted
## 灵物触手 · 显示层(2026-10-31 重做, 方案书 docs/plans/20261031d-灵物触手重做.md §4「B」)
##
## 用户 2026-10-31:「这东西在抽搐，而且一直闪光，你得想办法啊」「回放的时候还掉帧」「建议是直接大重做」,
##   方向稿选「B」= 实心 3D 触手。
##
## ── 这一层只管【画】 ─────────────────────────────────────────────────────
## 每根触手 = 一个 MeshInstance3D + 一份 ShaderMaterial。网格开局建一次(`gen_tentacle_tube`, 所有触手共用),
##   之后每帧只写几个 uniform(32 个中心线控制点 + 32 个半径 + 朝向 + 白闪 + 地洞 + 拍痕), 弯曲在顶点着色器里做。
## **动作不在这里**: 中心线与半径由 `TentacleVfx._geom` 算 —— 8 月那版(姿态表 + 链式模拟 + 行波 / 惯性 / 重力)原样
##   (用户 2026-10-31:「甚至不如旧版，你完全不知道怎么动的」⇒ 动作 100% 用旧版, 只换渲染)。
## 状态机、拍击时刻、伤害、预警带、命中名单同样不在这里(`TentacleVfx` / `spirit_synergy_system.gd`)。

const SRC := "res://scripts/systems/equip/tentacle_mesh_vfx.gd"
const VfxTex := preload("res://scripts/util/vfx_textures.gd")
const SHADER: Shader = preload("res://assets/shaders/tentacle.gdshader")
## 贴地接触阴影(透明, 挂在触手节点下, 同一份网格; 只吃 ctrl_pts / ctrl_r)
const SHADOW_SHADER: Shader = preload("res://assets/shaders/tentacle_shadow.gdshader")
const SHADOW_PARAMS := ["ctrl_pts", "ctrl_r"]

## 中心线控制点数(着色器 `ctrl_pts[32]` / `ctrl_r[32]` 焊死同一个数; 录流约定 ≤ 32)。旧版链式模拟出 SEG+1 = 37 个节点, 按下标等距重采样成 32 个。
const NCP := 32
## 网格: 沿长 RINGS 段 × 一圈 SIDES 边(本体 + 描边外壳各一份) + 地洞 + 拍痕。整根约 2.4k 顶点 / 4.0k 三角形, 全部触手共用一份。
const RINGS := 84
const SIDES := 12
const DISC_N := 20
const TRAIL_N := 14
## 旧版半径(带状特效的半宽) → 实心管子半径的换算。旧版是半透明扁带、边缘 alpha 羽化, 看得见的宽度约为半宽的一半上下;
##   实心管子照搬整个半宽会胖成一团。
const TUBE_K := 0.36
## 每步会变的 uniform(录流约定: 节点 meta `stream_shader_params`, 逐帧直播只录这几个)
const STREAM_PARAMS := ["ctrl_pts", "ctrl_r", "arc_len", "fwd", "lat", "flash", "hole_r", "trail", "trail_fwd", "portal", "fin_open", "ctrl_n"]

## 命中闪时长(秒): 60fps 下 ≤2 帧(参考: 命中只闪 1~2 帧)
const FLASH_T := 0.03
## 拍痕: 命中后贴地停多久再开始退、退多久(参考共同规律 4「沿通道留 0.3~0.4 秒」)
## ★第一版按状态计时算、0.15 秒就开始退: 拍痕和收回的触手同步往根部退, 一直被身体挡着, 实拍几乎看不见。
##   现在按「命中后经过的秒数」算(进了待机也接着走): 停 0.30 秒(触手 0.15 秒后才开始抬), 再 0.35 秒变细、从远端退掉。
const TRAIL_HOLD := 0.30
## 贴地发光(2026-11-13 对照 LoL 实机: 本体贴地后整根发紫光约 0.3 秒再褪): 白闪那 2 帧之后接一段从 GLOW0 衰减到 0 的余辉
const GLOW0 := 0.28
const GLOW_T := 0.40
const TRAIL_FADE := 0.35

static var _mesh: ArrayMesh = null


## 所有触手共用的一份网格(开局建一次)。录流按出处键让手机调同一个函数建同一份。
static func shared_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = VfxTex.tag(gen_tentacle_tube(RINGS, SIDES, DISC_N, TRAIL_N), "gen_tentacle_tube",
			[RINGS, SIDES, DISC_N, TRAIL_N], SRC)
	return _mesh


## 固定网格(纯函数)。顶点位置全由着色器算, 这里只写「这个顶点是谁」: UV / UV2(见 tentacle.gdshader 头注)。
## ★Godot 正面 = 顺时针绕序。本体朝外为正面; 描边外壳绕序反过来(只看得见外壳的背面 = 轮廓一圈)。
static func gen_tentacle_tube(rings: int, sides: int, disc_n: int, trail_n: int) -> ArrayMesh:
	var vs := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for kind in range(2):
		var base: int = vs.size()
		for i in range(rings + 1):
			var m: float = float(i) / float(rings)
			for j in range(sides + 1):
				vs.append(Vector3(0.0, m, 0.0))
				uv.append(Vector2(m, float(j) / float(sides)))
				uv2.append(Vector2(float(kind), 0.0))
		for i in range(rings):
			for j in range(sides):
				var a: int = base + i * (sides + 1) + j
				var b: int = a + 1
				var c: int = a + sides + 1
				var d: int = c + 1
				if kind == 0:
					idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
				else:
					idx.append_array(PackedInt32Array([a, b, c, b, d, c]))
	## 地洞: 圆心 + 3 圈
	var c0: int = vs.size()
	vs.append(Vector3.ZERO)
	uv.append(Vector2(0.0, 0.0))
	uv2.append(Vector2(2.0, 0.0))
	var rads := [0.45, 0.80, 1.0]
	for ri in range(rads.size()):
		for k in range(disc_n):
			vs.append(Vector3.ZERO)
			uv.append(Vector2(float(rads[ri]), float(k) / float(disc_n)))
			uv2.append(Vector2(2.0, 0.0))
	for k in range(disc_n):
		var k1: int = (k + 1) % disc_n
		## 朝上为正面(Godot 顺时针): 角度从 fwd 转向 lat 在俯视里是顺时针 ⇒ 圆心 → k → k+1
		idx.append_array(PackedInt32Array([c0, c0 + 1 + k, c0 + 1 + k1]))
		for ri in range(rads.size() - 1):
			var o0: int = c0 + 1 + ri * disc_n
			var o1: int = o0 + disc_n
			idx.append_array(PackedInt32Array([o0 + k, o1 + k, o0 + k1, o0 + k1, o1 + k, o1 + k1]))
	## 拍痕: 沿长 trail_n 段 × 横向 2 列
	var t0: int = vs.size()
	for i in range(trail_n + 1):
		for j in range(2):
			vs.append(Vector3.ZERO)
			uv.append(Vector2(float(i) / float(trail_n), -1.0 if j == 0 else 1.0))
			uv2.append(Vector2(3.0, 0.0))
	for i in range(trail_n):
		var a2: int = t0 + i * 2
		idx.append_array(PackedInt32Array([a2, a2 + 2, a2 + 1, a2 + 1, a2 + 2, a2 + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	## 顶点着色器把它挪到哪都行 ⇒ 包围盒按「根部 ± 攻击长度」给足, 不然会被视锥剔掉
	mesh.custom_aabb = AABB(Vector3(-11.0, -1.0, -11.0), Vector3(22.0, 13.0, 22.0))
	return mesh


## ── 外形 / 配色(2026-11-13 用户「自己设计一款外形呢…可以不用紫色，你自己去设计」) ──
## style 0 = 原来照俄洛伊的(锯齿棱鳍 + 龟裂地 + 灵物紫); 1 = 自己设计的深海磷光灵体(软薄膜 + 灵脉 + 灯珠 + 发光水纹)。
## 配色要避开: 右方血条紫、左方血条绿、预警带蓝 / 红(按阵营)。
const PALETTES := {
	"illaoi": {"style": 0.0},
	"abyss_cyan": {"style": 1.0,
		"c_base": Color(0.06, 0.12, 0.34), "c_outline": Color(0.02, 0.05, 0.15),
		"c_core": Color(0.08, 0.52, 0.66), "c_inner": Color(0.50, 0.97, 0.95), "c_edge": Color(0.02, 0.08, 0.16),
		"c_tip": Color(0.55, 1.0, 0.95), "c_glow": Color(0.75, 1.0, 0.97), "c_spec": Color(0.9, 1.0, 1.0),
		"c_flash": Color(0.92, 1.0, 1.0), "c_hole": Color(0.01, 0.04, 0.07),
		"fx_core": Color(0.90, 1.0, 1.0), "fx_mid": Color(0.20, 0.85, 0.90), "fx_edge": Color(0.05, 0.40, 0.60)},
	## 深色剪影 + 霓虹亮边 + 中线发光点(11-13 第四版: 浅色半透明在浅沙地上压不出形)
	"abyss_neon": {"style": 1.0, "dots": 1.0, "rim_glow": 1.0,
		"c_base": Color(0.02, 0.03, 0.10), "c_outline": Color(0.0, 0.01, 0.05),
		## 截面改成圆的(11-13 用户「中间为什么会细」: 扁截面 1.35 : 0.72, 竖着的那段把窄的一面对着镜头, 画面上只剩 0.72 宽)
		"band_w": 1.0, "band_t": 1.0,
		"c_core": Color(0.05, 0.12, 0.27), "c_inner": Color(0.25, 0.90, 1.0), "c_edge": Color(0.01, 0.03, 0.08),
		"c_tip": Color(0.40, 1.0, 1.0), "c_glow": Color(0.62, 1.0, 1.0), "c_spec": Color(0.75, 1.0, 1.0),
		"c_flash": Color(0.9, 1.0, 1.0), "c_hole": Color(0.0, 0.02, 0.05),
		"fx_core": Color(0.90, 1.0, 1.0), "fx_mid": Color(0.20, 0.85, 1.0), "fx_edge": Color(0.04, 0.30, 0.65)},
	"amber": {"style": 1.0,
		"c_core": Color(0.42, 0.22, 0.05), "c_inner": Color(1.0, 0.78, 0.36), "c_edge": Color(0.16, 0.06, 0.01),
		"c_tip": Color(1.0, 0.86, 0.50), "c_glow": Color(1.0, 0.93, 0.62), "c_spec": Color(1.0, 0.97, 0.88),
		"c_flash": Color(1.0, 0.98, 0.90), "c_hole": Color(0.07, 0.03, 0.01),
		"fx_core": Color(1.0, 0.97, 0.85), "fx_mid": Color(1.0, 0.66, 0.15), "fx_edge": Color(0.75, 0.30, 0.02)},
	"moon_jade": {"style": 1.0,
		"c_core": Color(0.36, 0.56, 0.58), "c_inner": Color(0.88, 1.0, 0.96), "c_edge": Color(0.08, 0.16, 0.22),
		"c_tip": Color(0.90, 1.0, 0.97), "c_glow": Color(0.62, 1.0, 0.90), "c_spec": Color(1.0, 1.0, 1.0),
		"c_flash": Color(1.0, 1.0, 1.0), "c_hole": Color(0.03, 0.06, 0.08),
		"fx_core": Color(1.0, 1.0, 1.0), "fx_mid": Color(0.55, 0.95, 0.85), "fx_edge": Color(0.20, 0.55, 0.55)},
	"coral": {"style": 1.0,
		"c_core": Color(0.62, 0.18, 0.22), "c_inner": Color(1.0, 0.66, 0.58), "c_edge": Color(0.24, 0.04, 0.08),
		"c_tip": Color(1.0, 0.78, 0.70), "c_glow": Color(1.0, 0.90, 0.78), "c_spec": Color(1.0, 0.96, 0.94),
		"c_flash": Color(1.0, 0.97, 0.95), "c_hole": Color(0.08, 0.02, 0.03),
		"fx_core": Color(1.0, 0.95, 0.90), "fx_mid": Color(1.0, 0.45, 0.40), "fx_edge": Color(0.70, 0.12, 0.18)},
}
const PALETTE_DEFAULT := "illaoi"
## 调试场 / 实验台换配色用(不进 sim, 不进快照)
static var palette_override := ""


static func palette() -> Dictionary:
	var k: String = palette_override if PALETTES.has(palette_override) else PALETTE_DEFAULT
	return PALETTES[k]


## 尖芽的宽 / 身长(从根 u=0 到梢 u=1), 量出来的两次出土的平均
const BUD_W_U := [0.0, 0.08, 0.30, 0.50, 0.70, 0.85, 1.0]
const BUD_W := [0.10, 0.18, 0.27, 0.24, 0.18, 0.12, 0.05]


static func _bud_width(u: float) -> float:
	for i in range(BUD_W_U.size() - 1):
		if u <= float(BUD_W_U[i + 1]):
			return lerpf(float(BUD_W[i]), float(BUD_W[i + 1]), (u - float(BUD_W_U[i])) / (float(BUD_W_U[i + 1]) - float(BUD_W_U[i])))
	return float(BUD_W[BUD_W.size() - 1])


## 建一根触手的节点(挂到 world 下)。网格共用、材质各自一份(各写各的 uniform)。
static func make_node(world: Node, nm: String, len_full: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = shared_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("len_full", len_full)
	var pal: Dictionary = palette()
	for k in pal:
		mat.set_shader_parameter(k, pal[k])
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false                 # 第一次 apply 之前不画(着色器默认值 = 原点一团)
	mi.set_meta(&"stream_shader_params", PackedStringArray(STREAM_PARAMS))
	## 接触阴影: 子节点(跟着根部走), 透明、渲染优先级 -1(先于单位立绘画, 不盖到龟脚上)
	var sh := MeshInstance3D.new()
	sh.name = "Shadow"
	sh.mesh = shared_mesh()
	var smat := ShaderMaterial.new()
	smat.shader = SHADOW_SHADER
	smat.render_priority = -1
	sh.material_override = smat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.set_meta(&"stream_shader_params", PackedStringArray(SHADOW_PARAMS))
	mi.add_child(sh)
	world.add_child(mi)
	return mi


## 这一帧的白闪(0/1): 正常拍击在 T_TOUCH 贴地那一刻, 点刺在第 0 帧。
static func flash_at(st: int, ts: float, share: float) -> float:
	if st != TentacleVfx.ST_SLAM:
		return 0.0
	var t0: float = touch_ts(share)
	return 1.0 if (ts >= t0 and ts < t0 + FLASH_T) else 0.0


## 出土漩涡(0..1): 2026-11-13 照 LoL 实机 —— 出土头 1 秒落点是暗紫漩涡(0.25 秒亮起、0.8 秒起褪, 1.1 秒没了), 之后尖芽才长出来。
static func portal_at(st: int, ts: float) -> float:
	if st != TentacleVfx.ST_EMERGE:
		return 0.0
	## 录屏: 0.6–1.3 秒漩涡在转; 1.3–1.9 秒褪成黑影(旋臂跟着淡, 黑心最后淡没); 第 2 秒光柱时没了
	return smoothstep(0.50, 0.70, ts) * (1.0 - smoothstep(1.2, 1.9, ts) * 0.85) * (1.0 - smoothstep(1.85, 2.0, ts))


## 棱鳍张开(0..1): 出土时尖芽合拢长出, 展开那 0.4 秒(EMERGE_RISE_T0 + 0.5 起)才张开; 其余状态全开。
static func fin_open_at(st: int, ts: float) -> float:
	if st != TentacleVfx.ST_EMERGE:
		return 1.0
	return smoothstep(TentacleVfx.EMERGE_RISE_T0 + 0.45, TentacleVfx.EMERGE_RISE_T0 + 0.90, ts)


## 贴地余辉(0..GLOW0), `tau` = 命中后经过的秒数(负 = 还没命中过)。
static func glow_at(tau: float) -> float:
	if tau < 0.0:
		return 0.0
	return GLOW0 * (1.0 - smoothstep(FLASH_T, GLOW_T, tau))


## 地面拍痕(1 → 0), `tau` = 命中后经过的秒数(负 = 还没命中过): 先停 TRAIL_HOLD 秒, 再 TRAIL_FADE 秒变细、从远端退回根部。
static func trail_at(tau: float) -> float:
	if tau < 0.0:
		return 0.0
	return 1.0 - clampf((tau - TRAIL_HOLD) / TRAIL_FADE, 0.0, 1.0)


## 这一击贴地的时刻(状态计时): 正常拍击 T_TOUCH, 点刺第 0 帧。
static func touch_ts(share: float) -> float:
	return 0.0 if share < 0.9 else TentacleVfx.T_TOUCH



## 每帧: 收下旧版算好的中心线(世界坐标, SEG+1 点)与每点半径 → 重采样成 NCP 个控制点 → 写 uniform。
## `t` 是 TentacleVfx 那根触手的字典; 本层只往里写 mv_* 开头的键(自己的记账, 门禁 / 探针读)。
static func apply(t: Dictionary, root3: Vector3, pts_w: PackedVector3Array, radii: PackedFloat32Array, fwd: Vector3, lat: Vector3, gt: float, dors: PackedVector3Array = PackedVector3Array()) -> void:
	var mi = t.get("mi", null)
	if not is_instance_valid(mi) or pts_w.size() < 2:
		return
	var n: int = pts_w.size()
	var cp := PackedVector3Array()
	var cr := PackedFloat32Array()
	var cn := PackedVector3Array()
	cp.resize(NCP)
	cr.resize(NCP)
	cn.resize(NCP)
	for k in range(NCP):
		var s: float = float(k) * float(n - 1) / float(NCP - 1)
		var i: int = mini(int(s), n - 2)
		var f: float = s - float(i)
		cp[k] = pts_w[i].lerp(pts_w[i + 1], f) - root3
		cr[k] = lerpf(radii[mini(i, radii.size() - 1)], radii[mini(i + 1, radii.size() - 1)], f) * TUBE_K
		## 背侧(背鳍那一侧, TentacleRig 沿身体平行传递); 没给就退回固定侧向
		cn[k] = dors[i].lerp(dors[mini(i + 1, dors.size() - 1)], f).normalized() if dors.size() == n else -fwd
	var arc := 0.0
	for i2 in range(1, n):
		arc += pts_w[i2].distance_to(pts_w[i2 - 1])
	## 2026-11-13: 身子还短(出土刚冒头)时半径跟着收 —— 原来弧长≈0 半径满额 ⇒ 根部冒出一团扁的; 出土时芽身更细, 张开时才长到满
	var fo: float = float(t.get("rig_fin", 1.0))
	## 尖芽是胖的(录屏: 合拢的花苞, 不是针)
	var rk: float = smoothstep(0.0, 1.6, arc) * lerpf(0.85, 1.0, fo)
	## 2026-11-13 待机短身(IDLE_ARC_K)时跟着变细: 只缩身长不缩粗细 ⇒ 卷起来是一团, 读不出 LoL 那种细身子 + 尖钩的「?」; 拍下甩到全长时恢复
	rk *= lerpf(0.72, 1.0, clampf((arc / TentacleVfx.ARC_LEN - TentacleVfx.IDLE_ARC_K) / (1.0 - TentacleVfx.IDLE_ARC_K), 0.0, 1.0))
	## 自己设计的外形身子收细: 11-13 自评「太胖, 像一团」; LoL 那种细长利落 ⇒ 粗细 × 0.72
	if float(palette().get("style", 0.0)) > 0.5:
		rk *= 0.72
	for k2 in range(NCP):
		cr[k2] *= rk
	## 自己设计的外形: 粗细从根到头均匀慢慢变细(根 1 → 头 0.5), 只在最后 8% 收尖 ——
	##   11-13 量: 原来根 0.41 米 → 头 0.02 米, 后半截一路细成针, 对折时往下那一截像细绳
	if float(palette().get("style", 0.0)) > 0.5:
		var r_ref: float = cr[mini(5, NCP - 1)]
		for k5 in range(NCP):
			var u5: float = float(k5) / float(NCP - 1)
			var pinch: float = 1.0 - 0.75 * smoothstep(0.92, 1.0, u5)
			cr[k5] = r_ref * lerpf(1.0, 0.5, u5) * pinch
	## 出土是对折的发卡(11-13 用户逐张讲解): 不再套「尖芽」的粗细曲线(那是把对折的身子当成了一根往上长的芽量出来的), 用正常粗细
	## 底 = 倒沙漏(用户「它是由周围汇聚成这个身体」): 贴地那一截往外张开, 出土时张得更大
	## 11-13 晚用户「中间为什么会细」: 底下这圈张开原来 ×1.45–1.55, 底部鼓成一坨 ⇒ 中间显得细; 收到 ×1.15
	var flare: float = 0.15
	for k3 in range(NCP):
		var u3: float = float(k3) / float(NCP - 1)
		if u3 < 0.10:
			cr[k3] *= 1.0 + flare * pow(1.0 - u3 / 0.10, 2.0)
	## 钻进地下的那段(发卡另一条腿还扎在地里时)不画: 半径归零
	for k4 in range(NCP):
		if cp[k4].y < -0.03:
			cr[k4] = 0.0
	var st: int = int(t["state"])
	var ts: float = float(t["ts"])
	var share: float = float(t.get("share", 1.0))
	var fl: float = flash_at(st, ts, share)
	## 拍痕的钟: 拍击期贴地之后按状态计时反推「全局时钟上的命中时刻」, 之后(收回 / 待机)按全局时钟走
	if st == TentacleVfx.ST_SLAM and ts >= touch_ts(share):
		t["mv_touch_gt"] = gt - (ts - touch_ts(share))
		t["mv_trail_fwd"] = fwd
	var tr: float = trail_at(gt - float(t["mv_touch_gt"])) if t.has("mv_touch_gt") else 0.0
	if t.has("mv_touch_gt") and float(t.get("share", 1.0)) >= 0.9:
		fl = maxf(fl, glow_at(gt - float(t["mv_touch_gt"])))
	t["mv_pts"] = cp
	t["mv_r"] = cr
	t["mv_flash"] = fl
	t["mv_trail"] = tr
	(mi as Node3D).position = root3
	(mi as Node3D).visible = true
	var mat: ShaderMaterial = (mi as MeshInstance3D).material_override
	mat.set_shader_parameter("ctrl_pts", cp)
	mat.set_shader_parameter("ctrl_r", cr)
	mat.set_shader_parameter("ctrl_n", cn)
	mat.set_shader_parameter("arc_len", arc)
	mat.set_shader_parameter("fwd", fwd)
	mat.set_shader_parameter("lat", lat)
	mat.set_shader_parameter("flash", fl)
	var po: float = portal_at(st, ts)
	t["mv_portal"] = po
	mat.set_shader_parameter("portal", po)
	mat.set_shader_parameter("fin_open", fo)
	## 根部那片地: 身子露出来之后常驻; 出土漩涡期间身子还没露(arc≈0)也要有
	mat.set_shader_parameter("hole_r", maxf(maxf(cr[mini(4, NCP - 1)] * 1.45, 0.25) * smoothstep(0.0, 0.6, arc), 0.62 * smoothstep(0.0, 0.25, po)))
	mat.set_shader_parameter("trail", tr)
	mat.set_shader_parameter("trail_fwd", t.get("mv_trail_fwd", fwd))
	var sh = (mi as Node).get_node_or_null(^"Shadow")
	if sh is MeshInstance3D:
		var smat: ShaderMaterial = (sh as MeshInstance3D).material_override
		smat.set_shader_parameter("ctrl_pts", cp)
		smat.set_shader_parameter("ctrl_r", cr)
