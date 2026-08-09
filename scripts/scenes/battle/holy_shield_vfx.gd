class_name HolyShieldVfx
extends RefCounted
## holy_shield_vfx.gd — 095【圣光护盾】的演出层 (2026-08-09 逐件重做)
##
## 三个入口, 与规格的三句话一一对应:
##   · `grant_burst(u, amt)`  每 3 秒补 55 点 → 头顶降一道圣光柱 + 落一枚十字圣印 + 光粒
##   · `tick(delta)`          「圣光护盾存在时」→ 携带者身前**常驻一面圣光盾板**
##   · `riposte(u, src, dmg)` 反击 2 点真伤 → 盾板 → 攻击者一道白金光矢 + 攻击者身上一枚圣罚印
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
## 3. **反击的光矢没有飞行时间**: 伤害是瞬时结算的, 光矢在第 0 帧就是整条 ——
##    "伤害不等演出到达"是踩过的一整类毛病。
##
## ★素材(2026-08-09 新生成, PixelLab, 本件专用, 不复用任何现有 vfx):
##   · `eq095-holy-aegis.png` —— 悬浮圣光盾板(白金盾面 + 十字), 逐帧微光循环
##   · `eq095-holy-smite.png` —— 圣罚印(四芒十字 + 放射光刃), 反击时盖在攻击者身上
##   其余小件(光柱 / 光矢 / 光粒)是本文件逐像素现算的程序化贴图 —— 同 incense_vfx 的立场:
##   程序化不产出可复用的图, `resource_path` 是空串(门禁断言这一条)。

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
const AEGIS_TEX_PATH := "res://assets/sprites/vfx/eq095-holy-aegis.png"
const SMITE_TEX_PATH := "res://assets/sprites/vfx/eq095-holy-smite.png"
const AEGIS_FRAMES := 4
const SMITE_FRAMES := 9
## 盾板微光循环速度(帧/秒)。慢一点 —— 它是常驻物, 快了会变成闪烁噪点。
const AEGIS_FPS := 6.0

## 盾板: 宽(码) / 悬浮高度(米) / 朝敌方向的横向偏移(码) / 入场与收尾(秒)
## ★宽度 30 码 ≈ 一只龟(44 码宽)的 2/3 —— 举在身前读得出"他举着盾", 又不会把龟盖住。
const AEGIS_W_PX := 33.0
## 悬浮高度(米)。★**实拍量出来的, 不是按"龟高 1.13 米"推的** —— 第一版按推算取 0.62,
##   台上盾板落在肚子/脚边(还压住了腿), 读成"掉在地上的盾"而不是"举在身前的盾"。
##   零点(地面)在屏幕上比立绘的脚底还低一截(有影子那一圈), 所以推算值一律偏低。
const AEGIS_Y := 0.88
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

## 补盾: 光柱高(米) / 存活(秒)
## ★补盾那一下**不再另画一枚圣印** —— 圣印(smite_tex)是反击的形状, 两个入口用同一张图
##   就又变成"同一件装备的两个入口剪影撞车"(093 的刻痕/香刚踩过)。
##   补盾的身份 = 光柱 + 光粒 + **盾板当场出现并鼓一记高光**, 与反击的"光矢 + 圣罚印"完全分开。
const PILLAR_H_M := 2.05
const PILLAR_SEC := 0.46
## 光粒: 尺寸(码) / 升高(米) / 存活(秒) / 一次几粒
const MOTE_PX := 9.0
const MOTE_RISE_M := 0.72
const MOTE_SEC := 0.52
const MOTE_N := 5

## 反击: 光矢宽(码) / 存活(秒) / 贴地高度(米); 圣罚印 尺寸(码) / 起手倍率 / 存活(秒) / 高度(米)
const BEAM_W_PX := 12.0
const BEAM_SEC := 0.24
const BEAM_Y := 0.55
const SMITE_D := 42.0
const SMITE_K0 := 1.45
const SMITE_SEC := 0.36
const SMITE_Y := 0.95

## 节点身份标记(程序生成贴图 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "holy_shield_vfx"
## 最后一道闸: 同时在场的【一次性】节点上限(常驻盾板不受它约束)
const OWNED_CAP := 96

static var _tex_aegis: Texture2D = null
static var _tex_smite: Texture2D = null
static var _tex_pillar: ImageTexture = null
static var _tex_mote: ImageTexture = null
static var _tex_beam: ImageTexture = null

var battle
## 「这只龟身上有几件 095」。★构造注入的只读回调(拆分模板 dmg_stats_panel.gd 的做法) ——
##   演出层不认识 `ShieldSynergySystem`, 也就不可能反过来改它的数。
var _holy_count_cb: Callable = Callable()
## 正在播的一次性特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进
var _fx: Array = []
## 常驻盾板 [{node, u, t, out, flash}] —— 由 `u["shield"]` 驱动, 不自己计时
var _aegis: Array = []


func _init(b, holy_count_cb: Callable = Callable()) -> void:
	battle = b
	_holy_count_cb = holy_count_cb


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §贴图 —— 两张真像素素材 + 三张程序化小件
# ══════════════════════════════════════════════════════════════════

## 悬浮圣光盾板(素材)。
static func aegis_tex() -> Texture2D:
	if _tex_aegis == null:
		_tex_aegis = load(AEGIS_TEX_PATH)
	return _tex_aegis


## 圣罚印(素材)。
static func smite_tex() -> Texture2D:
	if _tex_smite == null:
		_tex_smite = load(SMITE_TEX_PATH)
	return _tex_smite


## 圣光柱: 竖直, 中央亮芯 + 左右软边; **上亮下淡**(光是从天上降下来的)。
## ★内容不铺满整张 —— 铺满的话缩放采样会在边界切出一圈硬边。
##
## ★★2026-08-09 实拍改两处(第一版在台上读成"一根灰色的雾柱, 还把龟盖住了"):
##   ① **太宽**: 贴图 32×96 + 柱高 2.6 米 ⇒ 世界宽 0.87 米 = **36 码**, 比一只龟(44 码)还宽。
##      改成 14 宽 ⇒ 约 16 码, 是一束光不是一堵墙。
##   ② **半透 + 近白 = 灰**。黑底上 alpha 0.4 的白像素合成出来就是 RGB(100,100,100),
##      肉眼读到的是灰色。⇒ 主体色改成【金】(只有 core > 0.45 才往近白推),
##      alpha 底也从 0 抬到 0.25 —— **"亮"只能由贴图自己给**(Sprite3D 没有加色混合)。
static func pillar_tex() -> ImageTexture:
	if _tex_pillar != null:
		return _tex_pillar
	var w := 14
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(w - 1) * 0.5
	for y in range(h):
		var fy: float = float(y) / float(h - 1)          # 0 = 顶
		# 上宽下窄一点点: 读起来是"一束落下来的光", 不是一根柱子
		var half: float = (cx - 0.4) * (0.95 - 0.20 * fy)
		# 竖直方向: 顶端满亮, 到底部落到 0.46; 最底 8% 再收一下, 免得是一刀切
		var va: float = lerpf(1.0, 0.46, fy)
		if fy > 0.92:
			va *= clampf((1.0 - fy) / 0.08, 0.0, 1.0)
		for x in range(w):
			var d: float = absf(float(x) - cx)
			if d > half:
				continue
			var core: float = clampf(1.0 - d / maxf(0.5, half), 0.0, 1.0)
			# ★主体必须是**金**: 第二版把 core > 0.45 就推近白, 而 14 像素宽的柱子里
			#   八成像素都满足 ⇒ 实拍量出来 RGB(228,236,218) —— **一根白灰色的杆**,
			#   压在龟壳上像插了根铁棍。现在只有最中间那一线(core > 0.82)才近白。
			var col: Color = HOLY_GOLD.lerp(HOLY_WHITE, clampf((core - 0.82) / 0.18, 0.0, 1.0))
			var a: float = va * clampf(0.20 + 0.80 * core, 0.0, 1.0)
			if a <= 0.02:
				continue
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	_tex_pillar = ImageTexture.create_from_image(img)
	return _tex_pillar


## 一粒上飘的光屑: **四芒小十字**(不是圆点) —— 与圣光的十字母题同族。
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


## 反击的光矢: 横向, 前端尖、后端收细, 中间一条近白亮芯。
## ★两端不等宽是有意的 —— 等宽的话就是一根棍子, 读不出"射出去的方向"。
static func beam_tex() -> ImageTexture:
	if _tex_beam != null:
		return _tex_beam
	var w := 96
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(h - 1) * 0.5
	for x in range(w):
		var fx: float = float(x) / float(w - 1)          # 0 = 尾, 1 = 矢尖
		# 尾部细 → 中后段最厚 → 矢尖收成一点
		var thick: float = (h * 0.5 - 0.6) * clampf(sin(pow(fx, 0.72) * PI) * 1.12, 0.0, 1.0)
		if thick < 0.5:
			continue
		for y in range(h):
			var dy: float = absf(float(y) - cy)
			if dy > thick:
				continue
			var core: float = clampf(1.0 - dy / maxf(0.5, thick), 0.0, 1.0)
			# 同 pillar/mote: 主体金, 芯部才近白; alpha 底抬到 0.55 —— 半透白 = 灰
			var col: Color = HOLY_GOLD.lerp(HOLY_WHITE, clampf((core - 0.55) / 0.45, 0.0, 1.0))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(0.55 + 0.45 * core, 0.0, 1.0)))
	_tex_beam = ImageTexture.create_from_image(img)
	return _tex_beam


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


## 竖直光柱(不 billboard 全轴 —— 全轴会让柱子随相机俯仰倒下去; FIXED_Y 只绕 Y 转)。
## `y_base` = 柱子**底端**离地多高(米)。★不是"中心高度" —— 光柱要**落在盾板上**而不是
##   从头贯到脚: 贯到脚时它整根压在龟壳上, 实拍读成"插了根杆子"而不是"一束光落下来"。
func _pillar(pos2: Vector2, h_m: float, y_base: float) -> Sprite3D:
	var tex := pillar_tex()
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 17
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = Color(1, 1, 1, 1)
	s.pixel_size = h_m / float(maxi(1, tex.get_height()))
	s.position = battle._world_pos(pos2, y_base + h_m * 0.5)
	return s


## 贴地光矢 a→b。几何照 synergy_vfx.energy_band: `axis = AXIS_Y`(**本身就是平铺, 不许再加
## rotation.x** —— memory [[fb-axis-y-plus-rotation-cancels]]), 沿 +X 拉伸后用 rotation.y 对齐。
func _beam(a2: Vector2, b2: Vector2) -> Sprite3D:
	var wf: Vector3 = battle._world_pos(a2, BEAM_Y)
	var wt: Vector3 = battle._world_pos(b2, BEAM_Y)
	var seg: Vector3 = wt - wf
	var seg_len: float = seg.length()
	if seg_len < 0.01:
		return null
	var tex := beam_tex()
	var ps: float = (BEAM_W_PX * float(battle.WS)) / float(maxi(1, tex.get_height()))
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 18
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = Color(1, 1, 1, 1)
	s.pixel_size = ps
	s.position = wf + seg * 0.5
	s.rotation.y = -atan2(seg.z, seg.x)
	s.scale = Vector3(seg_len / maxf(0.001, float(tex.get_width()) * ps), 1.0, 1.0)
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

## `amt` 只用来决定光粒多少 —— **一点数值都不算**。
func grant_burst(u, amt: float = 0.0) -> void:
	if not (u is Dictionary) or not (u as Dictionary).get("alive", false) or not _has_world():
		return
	var p: Vector2 = (u as Dictionary).get("pos", Vector2.ZERO)
	# 光柱落在**盾板**上(同一个 x 锚点、底端就是盾板高度) —— 读作"这束光就是来补这面盾的"
	var pil := _pillar(_aegis_anchor(u as Dictionary), PILLAR_H_M, AEGIS_Y)
	_adopt(pil, PILLAR_SEC, "pillar", {"p": p})
	var n: int = MOTE_N if amt > 0.0 else maxi(2, MOTE_N - 2)
	for i in range(n):
		var dx: float = (float(i) - float(n - 1) * 0.5) * 13.0
		var at: Vector2 = p + Vector2(dx, 0.0)
		var mo := _board(mote_tex(), at, 0.12, MOTE_PX, Color(1, 1, 1, 1.0))
		_adopt(mo, MOTE_SEC, "mote", {"p": at, "y0": 0.12, "delay": 0.03 * float(i)})
	# ★盾板【当场】出现, 不等下一帧的 tick —— 结算侧是先 `_grant_shield` 再调本函数,
	#   所以这一刻 `shield` 已经 > 0, 条件是成立的。等 tick 补的话补盾那一帧盾板还不在,
	#   而那正是最该看到它的一帧(而且拍点密排时一定会拍到那一帧)。
	_ensure_aegis(u)
	_flash_aegis(u)


# ══════════════════════════════════════════════════════════════════
#  §入口②  反击: 盾板 → 攻击者 一道光矢 + 一枚圣罚印
# ══════════════════════════════════════════════════════════════════

## ★**没有飞行时间**: 伤害在结算侧那一帧就打完了, 光矢在第 0 帧就是整条。
##   (memory [[fb-vfx-defect-families]]: "伤害不等演出到达"是一整类毛病。)
func riposte(u, src, _dmg: float = 0.0) -> void:
	if not (u is Dictionary) or not (src is Dictionary) or not _has_world():
		return
	var a: Vector2 = _aegis_anchor(u as Dictionary)
	var b: Vector2 = (src as Dictionary).get("pos", Vector2.ZERO)
	var bm := _beam(a, b)
	if bm != null:
		_adopt(bm, BEAM_SEC, "beam")
	var y: float = SMITE_Y + float((src as Dictionary).get("height", 0.0))
	var sm := _board(smite_tex(), b, y, SMITE_D * SMITE_K0, Color(1, 1, 1, 1.0), SMITE_FRAMES)
	_adopt(sm, SMITE_SEC, "smite", {"p": b, "y": y, "d": SMITE_D})
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
	if not (u is Dictionary) or not (u as Dictionary).get("alive", false):
		return false
	if _holy_of(u) <= 0:
		return false
	return float((u as Dictionary).get("shield", 0.0)) > 0.0


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


func _spawn_aegis(u: Dictionary) -> void:
	var s := _mk_sprite(aegis_tex(), AEGIS_W_PX, Color(1, 1, 1, 0.0), AEGIS_FRAMES)
	# ★出生就摆到位, 别等 tick 的第一帧 —— Node3D 默认在原点, 只在 tick 里写位置的话
	#   【第一帧整面盾板画在地图原点(0,0,0)】。一帧闪一下肉眼抓不到, 门禁一量就露。
	s.position = battle._world_pos(_aegis_anchor(u), AEGIS_Y)
	s.set_meta(META_KEY, "aegis")
	battle._world.add_child(s)
	_aegis.append({"node": s, "u": u, "t": 0.0, "out": -1.0, "flash": 0.0})


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween)
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
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
			"pillar":
				# 光柱: 落下来的那一下最亮, 前 50% 满亮
				s.modulate.a = _holdfade(q, 0.50)
			"mote":
				var dl: float = float(f.get("delay", 0.0))
				var qm: float = clampf((float(f["t"]) - dl) / maxf(0.01, float(f["life"]) - dl), 0.0, 1.0)
				s.position = battle._world_pos(f["p"], float(f["y0"]) + MOTE_RISE_M * qm)
				s.modulate.a = (0.0 if float(f["t"]) < dl else _holdfade(qm, 0.45))
			"smite":
				var k2: float = lerpf(SMITE_K0, 1.0, clampf(q / 0.30, 0.0, 1.0))
				s.pixel_size = _ps_for(s, float(f["d"]) * k2, SMITE_FRAMES)
				s.frame = mini(SMITE_FRAMES - 1, int(q * float(SMITE_FRAMES)))
				s.modulate.a = _holdfade(q, 0.58)
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
		if not (nd is Sprite3D) or not is_instance_valid(nd):
			_aegis.remove_at(i)
			continue
		var s: Sprite3D = nd
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
		if u is Dictionary and (u as Dictionary).get("alive", false):
			s.position = battle._world_pos(_aegis_anchor(u as Dictionary), AEGIS_Y)
		# 尺寸随剩余护盾: 见底时 AEGIS_MIN_K, ≥55 满尺寸 —— 这一件唯一的"还剩多少"读数
		var sh: float = float((u as Dictionary).get("shield", 0.0)) if u is Dictionary else 0.0
		var k: float = lerpf(AEGIS_MIN_K, 1.0, clampf(sh / AEGIS_REF, 0.0, 1.0))
		# 高光: 补盾/反击那一下鼓一记, 然后落回
		var fl: float = float(a.get("flash", 0.0))
		if fl > 0.0:
			fl = maxf(0.0, fl - delta)
			a["flash"] = fl
		var fk: float = AEGIS_FLASH * (fl / AEGIS_FLASH_SEC)
		s.pixel_size = _ps_for(s, AEGIS_W_PX * (k + fk * 0.22), AEGIS_FRAMES)
		s.frame = int(float(a["t"]) * AEGIS_FPS) % AEGIS_FRAMES
		var ina: float = clampf(float(a["t"]) / AEGIS_IN_SEC, 0.0, 1.0)
		# 常驻物不许"一出生就淡出": 底 alpha 恒 0.88, 只有入场/收尾/高光在动
		s.modulate.a = clampf(ina * out_a * (0.88 + fk * 0.20), 0.0, 1.0)


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
	return n


## 现存节点数(可按 kind 过滤)。`kind = "aegis"` 数的是常驻盾板。
func alive_count(kind: String = "") -> int:
	var n := 0
	if kind == "" or kind == "aegis":
		for a in _aegis:
			var y = a.get("node", null)
			if y is Node3D and is_instance_valid(y):
				n += 1
	if kind == "aegis":
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
func aegis_node_of(u) -> Sprite3D:
	var a: Dictionary = _aegis_of(u)
	if a.is_empty():
		return null
	var n = a.get("node", null)
	return n if (n is Sprite3D and is_instance_valid(n)) else null


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
