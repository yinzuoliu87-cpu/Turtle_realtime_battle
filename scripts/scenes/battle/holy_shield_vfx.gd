class_name HolyShieldVfx
extends RefCounted
## holy_shield_vfx.gd — 095【圣光护盾】的演出层 (2026-08-09 逐件重做)
##
## 三个入口, 与规格的三句话一一对应:
##   · `grant_burst(u, amt)`  每 3 秒补 55 点 → **罩子合拢**(26 块能量板飞入锁死) + 碎光被推开
##   · `tick(delta)`          「圣光护盾存在时」→ **包住携带者的 3D 球罩**(常驻)
##   · `riposte(u, src, dmg)` 反击 2 点真伤 → 罩面涟漪 + 一枚光弹飞回去, **飞到才出伤**
##   · `riposte_hit(src)`      光弹命中那一帧(由结算侧调) → 攻击者身上一枚圣罚印
##
## ══════════════════════════════════════════════════════════════════════
##  ★重做前是什么样(实拍为证, `_vfxlab_p2eq_095_base_*.png`)
## ══════════════════════════════════════════════════════════════════════
## 这一件在台上**几乎不存在**:
##   ① 每 3 秒补盾: 画面上只有 `_grant_shield` 的**通用金环**(半径 44) —— 全游戏 44 个
##      给盾点共用同一个环, 读不出"这是圣光护盾给的";
##   ② 「圣光护盾存在时」这个**持续态零显示** —— 而反击的开关正是它,
##      玩家看不出自己现在会不会反击;
##   ③ 反击**一点演出都没有**, 只有敌人头上一个 "2" 的伤害数字。
##      探针实测(t=3.05 / 6.13 / 6.57 / 9.40)确认它一直在触发 —— 是**看不见**, 不是没跑。
##
## ⇒ 本层给这三条各一个形状, 且**三个形状互不相同**, 免得又是"同一个环换个颜色"。
##
## ══════════════════════════════════════════════════════════════════════
##  ★母题: 十字 / 盾板 / 光柱 —— 刻意避开盾羁绊已经占掉的两个形状
## ══════════════════════════════════════════════════════════════════════
## 同一场里必然同时出现盾羁绊自己的两条演出(它们**不是**这件装备画的):
##   · 【怒气冲击波】琥珀色 `#ffd93d` **大爆环**  (synergy_vfx.rage_shockwave)
##   · 【收殓】       米金色 `#ffe9a8` **能量带**  (synergy_vfx.shield_reap)
## 所以圣光走**十字/盾板/竖光柱**, 与"圆环""横带"在剪影上正交; 颜色偏白(近白芯 + 金边),
## 与琥珀分得开。**只靠颜色分不开**是上一轮四件召唤物共用白光球的老教训。
##
## ══════════════════════════════════════════════════════════════════════
##  ★两条硬规矩(CLAUDE.md §3.5 / 演出八毛病)
## ══════════════════════════════════════════════════════════════════════
## 1. **不用 tween**: 无头 CI 下 `create_tween()` 推进不稳。生命周期由 `tick(delta)` 自推,
##    每个入口都能被门禁单独调用, 且**不参与任何结算**。
## 2. **盾板没有自己的秒表**: 它在不在、多大, 每帧从 `u["shield"]` 与"身上有没有 095"读 ——
##    所以它和反击的真实开关**永远同步**(反击的条件就是 `holy_count>0 and shield>0`)。
##    ⚠ `u["shield"]` 是**总护盾**不是"圣光那一份": 反击的条件读的也是它, 两边同源才不会
##    出现"盾板亮着却不反击"。
## 3. **反击的光弹飞到才出伤**: 飞行时间由纯函数 `bolt_flight` 给,
##    结算侧拿它延后、演出侧拿它推进 —— **同一个数**, 所以"弹到"与"出伤"永远同帧。
##    (“伤害不等演出到达”是踩过的一整类毛病; 反过来“演出到了但伤害早就出了”也是。)
##
## ★素材:
##   · `eq095-holy-smite.png` —— 圣罚印(四芒十字 + 放射光刃), 反击光弹命中时盖在攻击者身上。
##     2026-08-09 新生成(PixelLab, 本件专用, 不复用任何现有 vfx)。
##   · 光粒是本文件逐像素现算的程序化贴图 —— 同 incense_vfx 的立场:
##     程序化不产出可复用的图, `resource_path` 是空串(门禁断言这一条)。
##   · 罩子与合拢的板子是**真 3D 几何 + shader**, 根本不过贴图。
##
## ⚠ 2026-08-09 清掉了一整层死代码: 盾板贴图(`aegis_tex`/`eq095-holy-aegis.png`)已被
##   3D 球罩取代, 光矢(`beam_tex`/`_beam`)已被光弹取代 —— 两者都零调用者,
##   而门禁还在断言它们的尺寸/配色(memory [[fb-verify-must-run-the-real-path]]:
##   「断言函数存在」守不住「还有没有人调」)。

## 身份色。★近白芯 + 金边, 与盾羁绊的琥珀 `#ffd93d` / 米金 `#ffe9a8` 分开。
const HOLY_GOLD := Color(1.0, 0.847, 0.408, 0.95)
const HOLY_WHITE := Color(1.0, 0.988, 0.918, 1.0)

## 素材路径与帧数。
## ★★两张都做了**逐帧筛选 + 调色归一**, 不是把生成结果原样丢进来 ——
##   `animate_image` 出 9 帧, 而后半段【跑色】: 盾板第 4/8 帧的四格里出现了大片
##   青蓝(实测 31% 像素 blue-red > 0.05), 第 5~7 帧褪成米灰(亮度动态只剩 0.65~0.99)。
##   同一件东西一会儿金一会儿青, 在画面上会被读成两样东西。
##   ⇒ 盾板只留调色一致的 **4 帧**(0~3)做呼吸循环; 圣罚印 9 帧【重排】成
##     "最强迸发 → 逐步收回到光秃的十字"(order = 2,1,0,3,8,7,6,5,4), 一次性播完不循环。
##   两张再一起按同一条【近白芯 → 金 → 深金】亮度斜坡重映射, 保证两个入口同一个身份色。
const DOME_SHADER_PATH := "res://assets/shaders/holy_shield_dome.gdshader"
const SMITE_TEX_PATH := "res://assets/sprites/vfx/eq095-holy-smite.png"
## ══════════════════════════════════════════════════════════════════
##  ★★2026-08-09 补盾从「天上砸一道光柱」整个换成「罩子自己合拢」
## ══════════════════════════════════════════════════════════════════
## 用户:「改掉，不允许图片敷衍或简单圆特效」。
## 换掉的理由(自评 + 实拍):
##   ① **方向反了**。「获得护盾」的动作是罩子在身上成型; 从天上劈下来是"天罚/审判"的语言。
##   ② **主角被盖住**。光柱高 7.8 个世界单位、宽度又是按帧高折算的, 实拍里罩子被它糊没了。
##   ③ 那张 9 帧图的**爆闪在帧内 87% 处**, 底边贴地时爆闪浮在离地约 1 个世界单位的空中,
##      下面吊着一截细碎余烬 —— 用户读成"打到中间就跟碰到墙壁一样"。对齐能修, 但①②修不了。
## ⇒ 新做法: **26 块六边形能量板从罩外飞进来, 各自旋转着缩到位, 逐块锁死拼成罩子**。
##   每块板有自己的位置/自转/落位时刻, 是 26 个独立运动的刚体 —— 不是一张图整体缩放,
##   也不是圆环。几何贴在球面上, 落位后严丝合缝就是罩子本身。
const PANEL_SHADER_PATH := "res://assets/shaders/holy_shield_panels.gdshader"
## 板子块数。★26 是"看得清是拼起来的"与"密到能读成一个壳"之间的平衡:
##   太少(<14)读成几片碎玻璃, 太多(>40)单块在实战镜头下只剩几个像素, 又变回一团光。
const PANEL_N := 26
## 出生时离罩面多远(× 半径)。0.55 ⇒ 板子从罩外约半个身位冲进来。
const PANEL_FLY_K := 0.55
## 装配时长 / 装完之后板子退场的时长(秒)
const BUILD_SEC := 0.46
const BUILD_FADE := 0.30
## 总进度要跑过 1 —— 最后落位的那几块也得有时间闪完它的"锁死"高光。
const BUILD_OVER := 1.30
const SMITE_FRAMES := 9
## 盾板微光循环速度(帧/秒)。慢一点 —— 它是常驻物, 快了会变成闪烁噪点。

## 盾板: 宽(码) / 悬浮高度(米) / 朝敌方向的横向偏移(码) / 入场与收尾(秒)
## ★宽度 30 码 ≈ 一只龟(44 码宽)的 2/3 —— 举在身前读得出"他举着盾", 又不会把龟盖住。
## ★盾板是这件装备的**持续标识**, 33 码在实战镜头下只有 22 px, 几乎看不见 ⇒ 48。
## ★★2026-08-09 用户:「这是3D啊，是要罩子啊，设计个罩子啊」——
##   护盾从"身前一块平板"改成**包住单位的 3D 球罩**(SphereMesh + 菲涅尔 shader)。
##   ⚠ 用真 3D 球的理由: 透视/等距/前后遮挡**引擎自己算对**, 不用我去凑一个"看起来像罩子"
##   的二维形状 —— 之前那块平板读不出"罩", 根子就在这。
## 罩子半径(世界单位)。龟立绘约 1.06 个世界单位高 ⇒ 0.78 刚好包住又不糊住脚。
## ★★2026-08-09 实拍标定后重定(用户:「位置、等距、大小你完全错误」)。
##   标定法: 罩子直径 1.56 单位在 1280x720 实战镜头下约 25 px, 而龟立绘高约 42 px
##   ⇒ **龟高约 2.6 个世界单位, 中心在 1.3** —— 我之前按"44 码 × WS = 1.06"算, 差了 2.5 倍。
##   (那个 1.06 是把"码"当成了 `_world_pos` 的高度单位, 两者根本不是一回事。)
## 半径 1.55 ⇒ 直径 3.1 > 龟高 2.6, 真正包得住。
const DOME_R := 1.55
## 罩心离地(世界单位) —— 取龟身中段, 让罩子上下都包得住。
## ★罩心离地。龟立绘脚在 0、胸口约 0.88(旧盾板就挂那儿) ⇒ 全高约 1.2。
##   0.52 偏低(接近腰), 实拍罩子压在脚边 ⇒ 抬到 0.62 取真正的身体中段。
const DOME_Y := 1.30
## 补盾那一下的"弹出": 先撑到 POP_K 再回落到 1.0
const DOME_POP_K := 1.16
const DOME_POP_SEC := 0.22
## 涟漪(挨打)持续
const DOME_HIT_SEC := 0.42
## 悬浮高度(米)。★**实拍量出来的, 不是按"龟高 1.13 米"推的** —— 第一版按推算取 0.62,
##   台上盾板落在肚子/脚边(还压住了腿), 读成"掉在地上的盾"而不是"举在身前的盾"。
##   零点(地面)在屏幕上比立绘的脚底还低一截(有影子那一圈), 所以推算值一律偏低。
const AEGIS_OFF_PX := 15.0
const AEGIS_IN_SEC := 0.16
const AEGIS_OUT_SEC := 0.26
## 盾板大小随剩余护盾缩放的下限(护盾见底时是满尺寸的多少)。
## ★这是这一件唯一的"还剩多少"读数出口(装备图标框的进度条不在本层, 见文件末尾 §缺口)。
const AEGIS_MIN_K := 0.78
## 缩放参照量 = 一次补盾的量(55)。护盾 ≥ 55 就是满尺寸。
const AEGIS_REF := 55.0
## 补盾/反击那一下盾板的高光: 峰值倍率与衰减时长(秒)
const AEGIS_FLASH := 0.55
const AEGIS_FLASH_SEC := 0.30

## 补盾那一下**不另画圣印** —— 圣印(smite_tex)是反击的形状, 两个入口用同一张图
## 就又变成"同一件装备的两个入口剪影撞车"(093 的刻痕/香刚踩过)。
## 补盾的身份 = **能量板合拢** + 被推开的碎光 + 罩子弹一记, 与反击的"光弹 + 圣罚印"完全分开。
##
## 碎光: 尺寸(码) / 被推开多远(码) / 升高(世界单位) / 存活(秒) / 一次几粒
## ★★不再"往上飘"。飘是烟的语言(093 用的就是它); 这里的物理意义是
##   **罩子合拢把周围的光挤了出去** ⇒ 沿径向向外冲、越冲越慢。
const MOTE_PX := 12.0
const MOTE_PUSH_PX := 40.0
const MOTE_RISE_M := 0.26
const MOTE_SEC := 0.46
const MOTE_N := 7
## 芯: 极短白闪, 定住"合上了"的那一帧(一发冲击至少要有一个重音)。
const CORE_PX := 58.0
const CORE_SEC := 0.10

## 反击: 光矢宽(码) / 存活(秒) / 贴地高度(米); 圣罚印 尺寸(码) / 起手倍率 / 存活(秒) / 高度(米)
const BEAM_Y := 0.55
const SMITE_D := 42.0
const SMITE_K0 := 1.45
const SMITE_SEC := 0.36
const SMITE_Y := 0.95

## 节点身份标记(程序生成贴图 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "holy_shield_vfx"
## 最后一道闸: 同时在场的【一次性】节点上限(常驻盾板不受它约束)
const OWNED_CAP := 96

static var _tex_smite: Texture2D = null
static var _tex_mote: ImageTexture = null
## 合拢用的板子网格(全场共用一份 —— 26 块的几何是死的, 动的全在 shader 里)
static var _panel_mesh: ArrayMesh = null

var battle
## 「这只龟身上有几件 095」。★构造注入的只读回调(拆分模板 dmg_stats_panel.gd 的做法) ——
##   演出层不认识 `ShieldSynergySystem`, 也就不可能反过来改它的数。
var _holy_count_cb: Callable = Callable()
## 正在播的一次性特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进
var _fx: Array = []
## 常驻盾板 [{node, u, t, out, flash}] —— 由 `u["shield"]` 驱动, 不自己计时
var _aegis: Array = []
## 在途光弹(见 riposte / bolt_flight)。
var _bolts: Array = []


func _init(b, holy_count_cb: Callable = Callable()) -> void:
	battle = b
	_holy_count_cb = holy_count_cb


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §贴图 / 网格 —— 一张真像素素材 + 一张程序化小件 + 合拢用的板子网格
# ══════════════════════════════════════════════════════════════════

## 圣罚印(素材)。
static func smite_tex() -> Texture2D:
	if _tex_smite == null:
		_tex_smite = load(SMITE_TEX_PATH)
	return _tex_smite


## 【护盾合拢】用的板子网格: 26 块贴在球面上的正六边形。
## ★为什么是 ArrayMesh 手搓而不是拿 SphereMesh 加个 shader:
##   板子要**各自飞进来**, 就必须每块的顶点都知道"我属于哪一块"。共享顶点的球面网格
##   做不到 —— 相邻三角形共用顶点, 一动就撕裂。所以每块板子的 7 个顶点是独立的,
##   并把「本块的中心方向」烘进 NORMAL、「本块的延时/自转种子」烘进顶点色。
## ★六边形半径按**铺满球面**反解: 六边形面积 2.598·hr² × N = 4πR² ⇒ hr = R·√(4π/2.598N)。
##   ×1.06 让相邻板子微微交叠, 落位后不留缝。
static func panel_mesh() -> ArrayMesh:
	if _panel_mesh != null:
		return _panel_mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var hr: float = DOME_R * sqrt(4.0 * PI / (2.598 * float(PANEL_N))) * 1.06
	var golden: float = PI * (3.0 - sqrt(5.0))       # 黄金角 ⇒ 球面上最均匀的 N 点分布
	for i in range(PANEL_N):
		var yy: float = 1.0 - 2.0 * (float(i) + 0.5) / float(PANEL_N)
		var rr: float = sqrt(maxf(0.0, 1.0 - yy * yy))
		var th: float = golden * float(i)
		var c := Vector3(cos(th) * rr, yy, sin(th) * rr).normalized()
		# 切平面基底(极点附近换参考轴, 否则 cross 退化成零向量 ⇒ 那两块板子是坏的)
		var refv: Vector3 = Vector3.UP if absf(c.y) < 0.95 else Vector3.RIGHT
		var t1: Vector3 = refv.cross(c).normalized()
		var t2: Vector3 = c.cross(t1).normalized()
		# 延时: 大致**从下往上装**(yy 从 -1 到 1) + 一点错落, 免得整圈整齐得像机械
		var delay: float = clampf((yy + 1.0) * 0.5 * 0.82 + fmod(float(i) * 0.37, 1.0) * 0.18, 0.0, 1.0)
		var spin: float = fmod(float(i) * 0.61803, 1.0)
		var base: int = verts.size()
		verts.append(c * DOME_R)
		norms.append(c)
		uvs.append(Vector2(0.5, 0.5))
		cols.append(Color(delay, 0.0, spin, 1.0))
		for k in range(6):
			var a2: float = TAU * float(k) / 6.0
			# ★顶点投影回球面 ⇒ 板子是**弯的**, 贴合罩子; 平的六边形会在球面上翘起来
			var pv: Vector3 = (c * DOME_R + t1 * (cos(a2) * hr) + t2 * (sin(a2) * hr)).normalized() * DOME_R
			verts.append(pv)
			norms.append(c)
			uvs.append(Vector2(0.5 + 0.5 * cos(a2), 0.5 + 0.5 * sin(a2)))
			cols.append(Color(delay, 1.0, spin, 1.0))
		for k in range(6):
			idx.append(base)
			idx.append(base + 1 + k)
			idx.append(base + 1 + ((k + 1) % 6))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_panel_mesh = m
	return _panel_mesh


## 一粒被推开的光屑: **四芒小十字**(不是圆点) —— 与圣光的十字母题同族。
static func mote_tex() -> ImageTexture:
	if _tex_mote != null:
		return _tex_mote
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = absf(float(x) - c) / c
			var dy: float = absf(float(y) - c) / c
			# 四芒星: 沿两轴细长, 对角线上很快归零
			var arm: float = maxf(1.0 - (dx * 3.2 + dy * 0.55), 1.0 - (dy * 3.2 + dx * 0.55))
			if arm <= 0.0:
				continue
			var a: float = clampf(arm * 1.75, 0.0, 1.0)
			# 同 pillar: 主体金, 只有芯部推近白 —— 半透明的近白在黑底上就是灰
			var col: Color = HOLY_GOLD.lerp(HOLY_WHITE, clampf((arm - 0.55) / 0.45, 0.0, 1.0))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_tex_mote = ImageTexture.create_from_image(img)
	return _tex_mote




# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

## 一块面向相机的公告板。
## ⚠【探针实测, 见 incense_vfx 同名函数】`Sprite3D` **没有 `blend_mode` 属性** ⇒ 这一层做不出
##   加色发光, "亮"只能由贴图自己给(所以上面几张的芯部都推到近白)。
## ★`frames` 必须参与 `pixel_size` 的分母 —— 否则 9 帧条会按整条宽度折算, 画面上小 9 倍。
func _mk_sprite(tex: Texture2D, size_px: float, col: Color, frames: int = 1) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	if frames > 1:
		s.hframes = frames
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 19
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = (size_px * float(battle.WS)) / maxf(1.0, float(tex.get_width()) / float(maxi(1, frames)))
	return s


func _board(tex: Texture2D, pos2: Vector2, y_m: float, size_px: float, col: Color, frames: int = 1) -> Sprite3D:
	var s := _mk_sprite(tex, size_px, col, frames)
	s.position = battle._world_pos(pos2, y_m)
	return s




func _adopt(n: Node3D, life: float, kind: String, extra: Dictionary = {}) -> Node3D:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _fx.size() >= OWNED_CAP:
		var old: Dictionary = _fx.pop_front()
		var x = old.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
	var d: Dictionary = {"node": n, "t": 0.0, "life": maxf(0.01, life), "kind": kind}
	for k in extra:
		d[k] = extra[k]
	_fx.append(d)
	return n


## 统一淡出曲线: 前 `hold` 段**满亮**, 之后才落到 0。
## ★"淡出病"的解药 —— 短命特效一出生就线性淡出, 实拍会读成灰/土棕。
static func _holdfade(q: float, hold: float) -> float:
	if q <= hold:
		return 1.0
	var k: float = clampf((q - hold) / maxf(0.001, 1.0 - hold), 0.0, 1.0)
	return clampf(1.0 - k * k, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §入口①  每 3 秒补盾: 圣光降下
# ══════════════════════════════════════════════════════════════════

## `amt` 只用来决定碎光多少 —— **一点数值都不算**。
func grant_burst(u, amt: float = 0.0) -> void:
	if not (u is Dictionary) or not (u as Dictionary).get("alive", false) or not _has_world():
		return
	var p: Vector2 = (u as Dictionary).get("pos", Vector2.ZERO)
	# ★罩子【当场】出现, 不等下一帧的 tick —— 结算侧是先 `_grant_shield` 再调本函数,
	#   所以这一刻 `shield` 已经 > 0, 条件是成立的。等 tick 补的话补盾那一帧罩子还不在,
	#   而那正是最该看到它的一帧(而且拍点密排时一定会拍到那一帧)。
	_ensure_aegis(u)
	_flash_aegis(u)
	## ★★本体: 【护盾合拢】—— 26 块六边形能量板从罩外飞进来逐块锁死。
	##   同时罩子本体弹一记(DOME_POP_K) —— 板子锁上的那一下壳体鼓起来。
	var ad2: Dictionary = _aegis_of(u)
	if not ad2.is_empty():
		ad2["pop"] = DOME_POP_SEC
		_start_build(ad2)
	## ★芯: 极短白闪, 只活 CORE_SEC —— "合上了"那一帧的重音
	var co := _board(mote_tex(), p, DOME_Y, CORE_PX, Color(1, 1, 1, 1.0))
	_adopt(co, CORE_SEC, "core", {"p": p, "y0": DOME_Y})
	## ★★碎光被**推出去**(不是往上飘): 物理意义是罩子合拢把周围的光挤开了。
	##   往上飘是**烟**的语言(093 用的就是它), 两件装备的碎屑得分得开。
	##   ☆ y 分量乘 0.55: 这是等距镜头, 地面上的圆在屏幕上是扫圆 ——
	##   不压的话碎光会飞成一个正圆, 读成"地上一个圈"。
	var n: int = MOTE_N if amt > 0.0 else maxi(2, MOTE_N - 2)
	for i in range(n):
		var ang: float = TAU * (float(i) + 0.35) / float(n)
		var dir := Vector2(cos(ang), sin(ang) * 0.55)
		var far: float = MOTE_PUSH_PX * (0.78 + 0.34 * float(i % 3))
		var mo := _board(mote_tex(), p, DOME_Y * 0.82, MOTE_PX, Color(1, 1, 1, 1.0))
		_adopt(mo, MOTE_SEC, "mote", {"p": p, "y0": DOME_Y * 0.82, "dir": dir, "far": far,
			"delay": 0.02 * float(i)})


# ══════════════════════════════════════════════════════════════════
#  §入口②  反击: 盾板 → 攻击者 一道光矢 + 一枚圣罚印
# ══════════════════════════════════════════════════════════════════

## ★**没有飞行时间**: 伤害在结算侧那一帧就打完了, 光矢在第 0 帧就是整条。
##   (memory [[fb-vfx-defect-families]]: "伤害不等演出到达"是一整类毛病。)
## 光弹飞行时间(秒) = 距离 / 速度。★纯函数: 结算侧用它算延后多久出伤, 演出侧用它推进。
##   **同一个数**, 所以"弹到"和"出伤"永远同帧。
const BOLT_SPEED := 900.0        ## 码/秒
const BOLT_PX := 26.0            ## 光弹直径(码)
static func bolt_flight(a2: Vector2, b2: Vector2) -> float:
	return a2.distance_to(b2) / BOLT_SPEED


## 一枚光弹的节点(小而亮的四芒, 复用光屑贴图)。
func _bolt_node(at: Vector2) -> Sprite3D:
	var sp := _board(mote_tex(), at, BEAM_Y, BOLT_PX, Color(1, 1, 1, 1.0))
	sp.set_meta(META_KEY, "rbolt")
	return sp


## 光弹到达那一帧: 攻击者身上盖一枚圣罚印。由结算侧调(与伤害同帧)。
func riposte_hit(src) -> void:
	if not (src is Dictionary) or not _has_world():
		return
	var b: Vector2 = (src as Dictionary).get("pos", Vector2.ZERO)
	var y: float = SMITE_Y + float((src as Dictionary).get("height", 0.0))
	var sm := _board(smite_tex(), b, y, SMITE_D * SMITE_K0, Color(1, 1, 1, 1.0), SMITE_FRAMES)
	_adopt(sm, SMITE_SEC, "smite", {"p": b, "y": y, "d": SMITE_D})


func riposte(u, src, _dmg: float = 0.0) -> void:
	if not (u is Dictionary) or not (src is Dictionary) or not _has_world():
		return
	var a: Vector2 = _aegis_anchor(u as Dictionary)
	var b: Vector2 = (src as Dictionary).get("pos", Vector2.ZERO)
	## ★★2026-08-09 用户:「反击怎么做，你这是射金光吗」——
	##   反击的物理意义是**罩子把伤害弹回去**, 不是携带者主动射一发。⇒ 两步:
	##   ① 罩子在**被打的那个方向**上炸开一圈涟漪(打哪儿亮哪儿)
	##   ② 被弹回的能量沿罩面切出去打在攻击者身上(仍保留光矢, 但它现在是"弹出物"不是"发射物")
	var ad: Dictionary = _aegis_of(u)
	if not ad.is_empty():
		var dir2: Vector2 = (b - a)
		if dir2.length_squared() > 1e-9:
			dir2 = dir2.normalized()
			## 场地方向 → 模型空间方向(x 右, z 朝屏幕下方)。y 略抬, 让涟漪中心落在罩子腰线上。
			ad["hit_dir"] = Vector3(dir2.x, 0.18, dir2.y).normalized()
		ad["hit_t"] = 0.0
	## ★★2026-08-09 用户:「要光弹啊，弹命中了再出伤啊」+「两个都用光弹就好啊」——
	##   不分远近, 一律**一枚光弹从罩面飞回攻击者, 飞到才结算**。
	##   这样"看到弹中"与"打出伤害"仍是同一个事件, 同帧原则没破。
	##   ⚠ 圣罚印**不在这里画** —— 它由结算侧在光弹到达那一帧调 `riposte_hit`。
	var edge: Vector2 = a
	if (b - a).length_squared() > 1e-9:
		edge = a + (b - a).normalized() * (DOME_R / float(battle.WS))
	_bolts.append({"from": edge, "to": b, "t": 0.0,
		"T": maxf(bolt_flight(edge, b), 0.001), "node": _bolt_node(edge)})
	_flash_aegis(u)


# ══════════════════════════════════════════════════════════════════
#  §入口③(常驻)  「圣光护盾存在时」= 身前一面盾板
# ══════════════════════════════════════════════════════════════════

## 盾板锚点(场地坐标): 携带者朝敌那一侧偏 `AEGIS_OFF_PX` 码。
## ★`face_right` 是渲染层用的同一个字段(battle_render.gd:373), 缺省按阵营 —— 左队朝右。
func _aegis_anchor(u: Dictionary) -> Vector2:
	var right: bool = bool(u.get("face_right", str(u.get("side", "left")) == "left"))
	return Vector2(u.get("pos", Vector2.ZERO)) + Vector2(AEGIS_OFF_PX if right else -AEGIS_OFF_PX, 0.0)


## 身上有几件 095(靠构造注入的回调; 没注入就当没有 —— 演出层不自己认装备表)。
func _holy_of(u) -> int:
	if not (u is Dictionary) or not _holy_count_cb.is_valid():
		return 0
	return int(_holy_count_cb.call(u))


## 「该不该有盾板」—— 与 `ShieldSynergySystem._riposte` 的两个条件**逐字相同**:
## 身上有 095 且当前有护盾值。两边同源, 才不会出现"盾板亮着却不反击"。
func _should_hold(u) -> bool:
	## ★★判据 = 【这条特殊护盾条本身有值】, 不看身上装没装 095
	##   (2026-08-12 用户:「不需要圣光护盾这个装备, 只要持有这个特殊护盾条就有特效的」)。
	##   由来: 原来要求"身上有 095", 于是 收殓/圣光·强化 这些【不经过 095 装备】
	##   拿到的圣盾值一律没有球罩 —— 玩家看到血条上有那条白黄段, 身上却什么都没有。
	##   `_holyShieldVal` 正是 hp_bar 画那条白黄段读的同一个字段(单一事实源)。
	if not (u is Dictionary) or not (u as Dictionary).get("alive", false):
		return false
	return float((u as Dictionary).get("_holyShieldVal", 0.0)) > 0.0


func _aegis_of(u) -> Dictionary:
	for a in _aegis:
		if is_same(a.get("u", null), u):
			return a
	return {}


## 补盾/反击那一下, 盾板上闪一记高光(它是常驻物, 不然两个事件在它身上没有任何反应)。
func _flash_aegis(u) -> void:
	var a: Dictionary = _aegis_of(u)
	if not a.is_empty():
		a["flash"] = AEGIS_FLASH_SEC


## 该有盾板而还没有 ⇒ 当场建一面(补盾那一帧要用)。
func _ensure_aegis(u) -> void:
	if not _has_world() or not _should_hold(u):
		return
	if _aegis_of(u).is_empty():
		_spawn_aegis(u as Dictionary)


## 罩子 = 真 3D 球体 + 菲涅尔 shader。见 DOME_R 那段注释。
func _spawn_aegis(u: Dictionary) -> void:
	var sm := SphereMesh.new()
	sm.radius = DOME_R
	sm.height = DOME_R * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load(DOME_SHADER_PATH)
	mat.set_shader_parameter("tint", Vector3(HOLY_GOLD.r, HOLY_GOLD.g, HOLY_GOLD.b))
	mat.set_shader_parameter("alpha", 0.0)
	mat.set_shader_parameter("pop", 0.0)
	mat.set_shader_parameter("hit_t", 1.0)
	## ⚠ `render_priority` 在**材质**上, 不在 MeshInstance3D 上(写错会每帧刷一条 SCRIPT ERROR)
	mat.render_priority = 16
	mi.material_override = mat
	# ★出生就摆到位, 别等 tick 的第一帧(Node3D 默认在原点 ⇒ 第一帧整个罩子画在地图原点)
	mi.position = battle._world_pos((u["pos"] as Vector2), DOME_Y)
	mi.set_meta(META_KEY, "aegis")
	battle._world.add_child(mi)
	var a: Dictionary = {"node": mi, "u": u, "t": 0.0, "out": -1.0, "flash": 0.0,
		"pop": 0.0, "hit_t": 1.0, "hit_dir": Vector3(0, 0, 1), "build_t": -1.0}
	_aegis.append(a)
	_ensure_panels(a)


## 【护盾合拢】的板子层 —— 挂在罩子**底下**当子节点。
## ★为什么是子节点: 位置/缩放/朝向全跟着罩子走, 不用两处各算一遍(手抄的副本必然落后)。
func _ensure_panels(a: Dictionary) -> void:
	var old = a.get("panels", null)
	if old is MeshInstance3D and is_instance_valid(old):
		return
	var host = a.get("node", null)
	if not (host is Node3D) or not is_instance_valid(host):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = panel_mesh()
	## ⚠ 板子在出生时会飞到罩面外 `PANEL_FLY_K` 倍半径处, 而 AABB 是按**网格原始顶点**算的
	##   (都在半径 DOME_R 的球面上) ⇒ 视锥剔除会在板子还在外围时把整个节点剔掉。
	##   这正是"节点建出来了、参数也对、就是看不见"的第三类原因(取景/剔除/阈值)。
	var rr: float = DOME_R * (1.0 + PANEL_FLY_K) * 1.25
	mi.custom_aabb = AABB(Vector3(-rr, -rr, -rr), Vector3(rr * 2.0, rr * 2.0, rr * 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = load(PANEL_SHADER_PATH)
	## ★走金不走近白: 加色混合下近白会直接叠爆成一团白(实拍过的老账)
	mat.set_shader_parameter("tint", Vector3(HOLY_GOLD.r, HOLY_GOLD.g, HOLY_GOLD.b))
	mat.set_shader_parameter("radius", DOME_R)
	mat.set_shader_parameter("fly", PANEL_FLY_K)
	mat.set_shader_parameter("build", 0.0)
	mat.set_shader_parameter("fade", 1.0)
	## 板子压在罩壳之上(罩壳 16), 否则加色混合下会被壳吃掉一半
	mat.render_priority = 17
	mi.material_override = mat
	mi.visible = false
	mi.set_meta(META_KEY, "panels")
	(host as Node3D).add_child(mi)
	a["panels"] = mi


## 放一次合拢(补盾那一下)。重复调用就是重播 —— 每 3 秒补一次盾, 就装配一次。
func _start_build(a: Dictionary) -> void:
	_ensure_panels(a)
	a["build_t"] = 0.0
	var pn = a.get("panels", null)
	if pn is MeshInstance3D and is_instance_valid(pn):
		(pn as MeshInstance3D).visible = true


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween)
# ══════════════════════════════════════════════════════════════════

## 在途光弹: 沿直线飞, 到点自销(伤害由结算侧在同一时刻出 —— 两边用同一个 `bolt_flight`)。
func _tick_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		var nd = b.get("node", null)
		if not is_instance_valid(nd):
			_bolts.remove_at(i)
			continue
		b["t"] = float(b["t"]) + delta
		var q: float = clampf(float(b["t"]) / float(b["T"]), 0.0, 1.0)
		var at: Vector2 = (b["from"] as Vector2).lerp(b["to"] as Vector2, q)
		(nd as Sprite3D).position = battle._world_pos(at, BEAM_Y)
		(nd as Sprite3D).modulate.a = 1.0
		if q >= 1.0:
			(nd as Node).queue_free()
			_bolts.remove_at(i)


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick_bolts(delta)
	_tick_aegis(delta)
	if _fx.is_empty():
		return
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not (n is Sprite3D) or not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var s: Sprite3D = n
		var q: float = clampf(float(f["t"]) / float(f["life"]), 0.0, 1.0)
		match str(f.get("kind", "")):
			"mote":
				## 碎光: 沿径向被**推出去**, 越冲越慢(二次缓出) + 微微抬高。
				##   ★位移写回 `p + dir*far*e` 而不是每帧累加 —— 累加会跟帧率走(卡一帧就飞远一截)。
				var dl: float = float(f.get("delay", 0.0))
				var qm: float = clampf((float(f["t"]) - dl) / maxf(0.01, float(f["life"]) - dl), 0.0, 1.0)
				var em: float = 1.0 - pow(1.0 - qm, 2.6)
				var at: Vector2 = Vector2(f["p"]) + Vector2(f.get("dir", Vector2.RIGHT)) * float(f.get("far", 0.0)) * em
				s.position = battle._world_pos(at, float(f["y0"]) + MOTE_RISE_M * em)
				s.modulate.a = (0.0 if float(f["t"]) < dl else _holdfade(qm, 0.40))
			"smite":
				var k2: float = lerpf(SMITE_K0, 1.0, clampf(q / 0.30, 0.0, 1.0))
				s.pixel_size = _ps_for(s, float(f["d"]) * k2, SMITE_FRAMES)
				s.frame = mini(SMITE_FRAMES - 1, int(q * float(SMITE_FRAMES)))
				s.modulate.a = _holdfade(q, 0.58)
			"core":
				## 芯: 前 60% 满亮再收, 同时快速涨大一点(冲击的"顶")
				s.pixel_size = _ps_for(s, CORE_PX * (0.55 + 0.75 * q), 1)
				s.modulate.a = _holdfade(q, 0.60)
			"beam":
				s.modulate.a = _holdfade(q, 0.55)
			_:
				s.modulate.a = _holdfade(q, 0.55)
		if q >= 1.0:
			s.queue_free()
			_fx.remove_at(i)


## 按"想要多宽(码)"反算 `pixel_size`。★分母是**单帧宽**(整条 / 帧数), 不是整条宽。
func _ps_for(s: Sprite3D, size_px: float, frames: int) -> float:
	return (size_px * float(battle.WS)) / maxf(1.0, float(s.texture.get_width()) / float(maxi(1, frames)))


## 常驻盾板: 在不在、多大, **每帧从 `u["shield"]` 读**, 不自己计时。
func _tick_aegis(delta: float) -> void:
	# ① 该有而没有的, 补出来(护盾来自别的地方时也算 —— 反击的条件读的就是总护盾)
	if _has_world() and _holy_count_cb.is_valid():
		for u in battle._units:
			_ensure_aegis(u)
	# ② 推进已有的
	for i in range(_aegis.size() - 1, -1, -1):
		var a: Dictionary = _aegis[i]
		var nd = a.get("node", null)
		## ⚠ 罩子是 MeshInstance3D 不是 Sprite3D —— 这里漏改会让它一进 tick 就被当成
		##   无效条目移除掉(2026-08-09 实测: 罩子建出来了但下一帧就没了)
		if not (nd is Node3D) or not is_instance_valid(nd):
			_aegis.remove_at(i)
			continue
		var s: MeshInstance3D = nd
		a["t"] = float(a["t"]) + delta
		var u = a.get("u", null)
		var hold: bool = _should_hold(u)
		# 盾没了(或携带者倒下) ⇒ 开始收尾; 又有了 ⇒ 收尾取消(不重建, 免得闪一下)
		if not hold and float(a.get("out", -1.0)) < 0.0:
			a["out"] = 0.0
		elif hold and float(a.get("out", -1.0)) >= 0.0:
			a["out"] = -1.0
		var out_a := 1.0
		if float(a.get("out", -1.0)) >= 0.0:
			a["out"] = float(a["out"]) + delta
			out_a = clampf(1.0 - float(a["out"]) / AEGIS_OUT_SEC, 0.0, 1.0)
			if out_a <= 0.0:
				s.queue_free()
				_aegis.remove_at(i)
				continue
		## ★罩子跟着单位, 罩心取龟身中段 ⇒ 上下都包得住(位置/大小是这次的核心要求)
		if u is Dictionary and (u as Dictionary).get("alive", false):
			s.position = battle._world_pos((u as Dictionary)["pos"] as Vector2, DOME_Y)
		# 尺寸随剩余护盾: 见底时 AEGIS_MIN_K, ≥55 满尺寸 —— 这一件唯一的"还剩多少"读数
		var sh: float = float((u as Dictionary).get("shield", 0.0)) if u is Dictionary else 0.0
		var k: float = lerpf(AEGIS_MIN_K, 1.0, clampf(sh / AEGIS_REF, 0.0, 1.0))
		# 高光: 补盾/反击那一下鼓一记, 然后落回
		var fl: float = float(a.get("flash", 0.0))
		if fl > 0.0:
			fl = maxf(0.0, fl - delta)
			a["flash"] = fl
		var fk: float = AEGIS_FLASH * (fl / AEGIS_FLASH_SEC)
		## ★★弹出: 补盾那一下先撑到 DOME_POP_K 再回落 —— 罩子"合拢"的那一下
		var pp: float = float(a.get("pop", 0.0))
		if pp > 0.0:
			pp = maxf(0.0, pp - delta)
			a["pop"] = pp
		var pk: float = pp / DOME_POP_SEC
		var ina: float = clampf(float(a["t"]) / AEGIS_IN_SEC, 0.0, 1.0)
		## ★★2026-08-09 用户:「罩子为什么大小在变」—— 我把"剩余护盾"做成了罩子**尺寸**,
		##   护盾越少罩子越小。这是错的: 罩子是个物理外壳, 大小不该动, 会读成在呼吸。
		##   ⇒ 尺寸只由**入场**和**合拢弹一下**驱动; **剩余量改为驱动亮度**(见下面 alpha)。
		var scl: float = (1.0 + (DOME_POP_K - 1.0) * pk) * (0.72 + 0.28 * ina)
		s.scale = Vector3(scl, scl, scl)
		## ★★涟漪: 挨打那一下从命中方向扩开 —— 打哪儿亮哪儿
		var ht: float = float(a.get("hit_t", 1.0))
		if ht < 1.0:
			ht = minf(1.0, ht + delta / DOME_HIT_SEC)
			a["hit_t"] = ht
		var mat := s.material_override as ShaderMaterial
		if mat != null:
			## 常驻物不许"一出生就淡出": 底强度恒定, 只有入场/收尾/弹出/涟漪在动
			## 剩余护盾 ⇒ **亮度**(k 从 AEGIS_MIN_K 到 1.0), 尺寸恒定
			mat.set_shader_parameter("alpha", clampf(ina * out_a * (0.30 + 0.62 * k), 0.0, 1.0))
			mat.set_shader_parameter("pop", pk * 0.9 + fk * 0.5)
			mat.set_shader_parameter("hit_t", ht)
			mat.set_shader_parameter("hit_dir", a.get("hit_dir", Vector3(0, 0, 1)))
			mat.set_shader_parameter("t", float(a["t"]))
		_tick_build(a, delta, out_a)


## 【护盾合拢】的进度推进。★没有自己的秒表以外的任何状态 —— 起点由 `_start_build` 打,
## 之后纯靠 delta 累加; 装完就把板子层藏起来(不销毁, 下次补盾直接重播)。
func _tick_build(a: Dictionary, delta: float, out_a: float) -> void:
	var bt: float = float(a.get("build_t", -1.0))
	if bt < 0.0:
		return
	var pn = a.get("panels", null)
	if not (pn is MeshInstance3D) or not is_instance_valid(pn):
		a["build_t"] = -1.0
		return
	bt += delta
	a["build_t"] = bt
	var mi: MeshInstance3D = pn
	var pm := mi.material_override as ShaderMaterial
	if pm != null:
		## 总进度跑到 BUILD_OVER(>1) —— 最后落位的那几块也要有时间闪完"锁死"高光
		pm.set_shader_parameter("build", clampf(bt / BUILD_SEC, 0.0, 1.0) * BUILD_OVER)
		var fd: float = 1.0
		if bt > BUILD_SEC:
			fd = clampf(1.0 - (bt - BUILD_SEC) / BUILD_FADE, 0.0, 1.0)
		pm.set_shader_parameter("fade", fd * out_a)
	if bt >= BUILD_SEC + BUILD_FADE:
		a["build_t"] = -1.0
		mi.visible = false


# ══════════════════════════════════════════════════════════════════
#  §撤场 / 计数(门禁量真实对象用)
# ══════════════════════════════════════════════════════════════════

## 拔掉一切自己建的节点。返回拔了几个(门禁验"真的清干净了")。
func clear() -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
			n += 1
	_fx.clear()
	for a in _aegis:
		var y = a.get("node", null)
		if y is Node3D and is_instance_valid(y):
			y.queue_free()
			n += 1
	_aegis.clear()
	## ★在途光弹也要撤 —— 漏了它换路时会残留一枚在世界里
	##   (memory [[fb-write-without-reader-and-fake-gates]] 同族: 新增了一类节点却没接进撤场)
	for b in _bolts:
		var z = b.get("node", null)
		if z is Node3D and is_instance_valid(z):
			z.queue_free()
			n += 1
	_bolts.clear()
	return n


## 现存节点数(可按 kind 过滤)。`kind = "aegis"` 数的是常驻盾板。
func alive_count(kind: String = "") -> int:
	var n := 0
	if kind == "" or kind == "aegis":
		for a in _aegis:
			var y = a.get("node", null)
			if y is Node3D and is_instance_valid(y):
				n += 1
	## ★在途光弹存在 `_bolts` 里(不在 `_fx`) —— 漏了这一段, `alive_count("rbolt")` 永远是 0,
	##   门禁会把"光弹当场就在"判成没有(2026-08-09 实测)。
	if kind == "" or kind == "rbolt":
		for b in _bolts:
			var bn = b.get("node", null)
			if bn is Node3D and is_instance_valid(bn):
				n += 1
	if kind == "aegis" or kind == "rbolt":
		return n
	for f in _fx:
		var x = f.get("node", null)
		if not (x is Node3D) or not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n


## 本层【自己记着的】一次性节点(可按 kind 过滤)。
## ★门禁必须用它而不是 `battle._world.get_children()`: `queue_free()` 的节点要到帧末才真消失,
##   而门禁是同步跑的(不 await) ⇒ 遍历 _world 会把上一组已经撤掉的节点也数进来,
##   量出来的是**别人的参数**。这是"看起来没问题但量错了对象"的典型。
func fx_nodes(kind: String = "") -> Array:
	var out: Array = []
	for f in _fx:
		var x = f.get("node", null)
		if not (x is Node3D) or not is_instance_valid(x):
			continue
		if kind != "" and str(f.get("kind", "")) != kind:
			continue
		out.append(x)
	return out


## 某只龟当下那面盾板的节点(没有返回 null)。★门禁量真实对象用 —— 不返回记账字段。
## ★2026-08-09 返回类型 Sprite3D → Node3D: 盾板已换成 3D 球罩(MeshInstance3D)。
func aegis_node_of(u) -> Node3D:
	var a: Dictionary = _aegis_of(u)
	if a.is_empty():
		return null
	var n = a.get("node", null)
	return n if (n is Node3D and is_instance_valid(n)) else null


## 某只龟当下那层【合拢板】的节点(没有返回 null)。★门禁量真实对象用。
func panels_node_of(u) -> MeshInstance3D:
	var a: Dictionary = _aegis_of(u)
	if a.is_empty():
		return null
	var n = a.get("panels", null)
	return n if (n is MeshInstance3D and is_instance_valid(n)) else null


## 合拢进度(秒; < 0 表示当下没在装配)。门禁用它验"补盾真的放了一次合拢"。
func build_t_of(u) -> float:
	var a: Dictionary = _aegis_of(u)
	return -1.0 if a.is_empty() else float(a.get("build_t", -1.0))


# ══════════════════════════════════════════════════════════════════
#  §缺口(写下来免得下一个人当成"已经好了")
#
#  1. **装备图标框里没有"当前圣光护盾值"的读数**。095 不在
#     `RealtimeBattle3DScene.PANEL_CHARGE` / `PANEL_COUNT` 里, 而那两张表在主场景文件
#     (本轮不在可改范围)。盾板的尺寸只能表达"多还是少", 表达不了具体点数。
#     ⇒ 建议主会话加一行: `"p2eq_095": ["shield", 55.0, "#fff0b8"]`;
#       ⚠ 但 PANEL_CHARGE 现在读的是 `eq_state[id][字段]`, 而护盾值在 `u["shield"]` 上,
#       所以**不是加一行就完**, 要么在 eq_state 里镜像一份, 要么给那张表加"读单位字段"的模式。
#  2. **盾板读的是总护盾不是"圣光那一份"**。这是**有意的**(反击的条件读的也是总护盾,
#     两边同源), 但如果哪天规格改成"只有圣光那一份才算", 这里和 `_riposte` 要一起改。
# ══════════════════════════════════════════════════════════════════
