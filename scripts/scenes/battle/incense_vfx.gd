class_name IncenseVfx
extends RefCounted
## incense_vfx.gd — 093 香火石的演出层
##
## 三个入口:
##   · `empower_burst(u)`        主动就绪: 头顶点起**一排香**(4 支 = 还剩几次强化普攻)
##   · `empower_hit(u, tgt)`     强化普攻命中: 目标身上盖一枚**火印**; 香台自动少一支
##   · `mark_carved(u, m, n)`    刻成痕: 头顶落下 n 道凿痕 + 火星 + 飘字
##
## ══════════════════════════════════════════════════════════════════════
##  ★2026-08-09 逐件重做(第二轮) —— 每一条都由实拍/探针抓出来的
## ══════════════════════════════════════════════════════════════════════
## 上一轮(08-07)把三个入口从"细环"改成了程序化贴图, 方向对, 但在**实战镜头(zoom 1.0)**
## 下重拍之后, 五个问题一个都跑不掉:
##
## ① **一帧刻 5 道 ⇒ 5 份完全重叠的演出**。探针实测: 携带者一次斩击打出 2 万伤害,
##    `tick_unit` 的 while 在同一帧转了 5 圈, `mark_carved` 被连调 5 次
##    (t=13.58 marks=1,2,3,4,5) ⇒ 同一个点上摞 5 道一模一样的凿痕、
##    5 条"香火 N"飘字完全重合(谁都读不出来), 还白跑 5 遍全场 `_reapply`。
##    ⇒ 结算侧改成【一帧只结算一次、把道数传进来】, 演出侧按道数**横向排开**。
##
## ② **三支香读成"三只角"**。旧贴图 24×96, 火头占了整支的 46% 且几乎顶满宽度,
##    香身只有 3.2px 宽 ⇒ 剪影就是个圆锥。而且 `STICK_W_PX=19 × 4` = **76 码高**,
##    实测一只龟才 44×47 码 —— 香比龟还高 1.6 倍, 三支并排就是一顶王冠。
##    ⇒ 换成**真像素素材**(PixelLab 生成, 见下), 尺寸压到 20 码宽 × 40 码高。
##
## ③ **旧文档说"带火头与青烟", 代码里根本没有烟**(逐像素读过, 只有杆 + 火头两段)。
##    ⇒ 新素材自带一缕上飘的青烟, 这条注释才对得上代码。
##
## ④ **四瓣火焰从未在任何一张实拍里出现**。它 0.36 秒、贴在目标身体正中,
##    而那儿正是 basic 龟通用斩击(一道横贯全屏的金色大弧)糊住的地方。
##    A/B 基线 `ab_attacker` 逐张对照证明: 金色大弧、蓝白能量球、黄色小方块
##    **全是通用演出**, 换成 p2eq_047 照样在。⇒ 火印**抬到目标上半身以上**、
##    换成八角勋章剪影(与弧/环/球都不撞), 并且**盖章式**(1.7×→1.0×)+ holdfade。
##
## ⑤ **淡出病**: 旧 spark `0.9*(1−q²)` / flare `1−q²` 都是**一出生就开始掉**,
##    0.36 秒的东西在实拍里只剩灰影。⇒ 全部走 `_holdfade()`: 前 55~68% 满亮, 之后才落。
##
## ══════════════════════════════════════════════════════════════════════
##  ★香台【没有自己的秒表】(CLAUDE.md 的同族教训: 演出别自己计时)
## ══════════════════════════════════════════════════════════════════════
## "还剩几次强化普攻"是**结算侧的状态**(`eq_state["p2eq_093"]["emp"]`)。
## 香台每帧去读它决定亮着几支香 —— 所以不管这 4 拳打了 1 秒还是 6 秒(实测两种都有:
## 无加速时 4 拳摊在 5.3 秒里), 台上的支数**永远等于真实剩余次数**, 不会各走各的。
## emp 归零(或携带者倒下)才开始 0.3 秒的收尾淡出。
##
## ★为什么演出层与结算层分开(CLAUDE.md §3.5):
##   数值测试**不许依赖任何 tween 跑完** —— 无头 CI 下 `create_tween()` 推进不稳。
##   所以本文件**不用 tween**: 生命周期由 `tick(delta)` 自己推, 主循环每帧调一次;
##   每个入口都能被单独调用(供门禁用), 不参与任何判定。
##
## ★素材(2026-08-09 新生成, PixelLab, 本件专用, 不复用任何现有 vfx):
##   · `eq093-incense-stick.png` 32×64 —— 一支点着的香(木杆 + 橙色火头 + 上飘青烟)
##   · `eq093-ember-seal.png`    64×64 —— 八角石印, 外圈橙焰 + 放射火星
##   两张都按 `TEXTURE_FILTER_NEAREST` 取样(像素风不许糊)。

## 香火金 / 香火红。★这两个色是这一件的身份, 与 092 毒蛾茧的紫绿、094 祖龟碑的灰蓝分开。
const GOLD := Color(1.0, 0.82, 0.42, 0.95)
const EMBER := Color(0.98, 0.44, 0.20, 0.85)

const STICK_TEX_PATH := "res://assets/sprites/vfx/eq093-incense-stick.png"
const SEAL_TEX_PATH := "res://assets/sprites/vfx/eq093-ember-seal.png"

## 演出基准高度(米): 头顶。★实测一只龟高约 47 码 = 1.13 米, 所以 1.55 米确实在头顶之上。
const HEAD_Y := 1.55
## 一排香: 单支**宽**(码) / 支距(码) / 升起(米) / 入场与收尾(秒)
## ★`_board` 是按【贴图宽】换算 pixel_size 的 ⇒ 这里传的必须是"宽";
##   贴图 32×64 ⇒ 实际高 = 宽 × 2 = 40 码, 与龟(47 码)同量级, 不再是 76 码的巨柱。
const STICK_W_PX := 20.0
const STICK_TEX_ASPECT := 2.0
const STICK_GAP_PX := 12.0
const STICK_RISE_M := 0.30
const ALTAR_IN_SEC := 0.22
const ALTAR_OUT_SEC := 0.30
## 一支香被消耗掉的熄灭时长(秒) —— 看得见"少了一支", 又不拖泥带水
const STICK_SNUFF_SEC := 0.20
## 火头的光晕(码): 让 20 码宽的香在实战镜头下也有一点"亮"
const GLOW_PX := 13.0

## 刻痕凿沟: 单道**宽**(码, 贴图 64×24 ⇒ 高 = 宽 × 0.375) / 上下道距(米) /
## 一次最多摆几道 / 存活(秒)
const TALLY_PX := 40.0
const TALLY_ROW_M := 0.20
const TALLY_MAX := 5
const TALLY_SEC := 0.60
## 刻痕落点高度(米)。★必须**高过香台顶**(HEAD_Y + STICK 半高 0.48 + 升起 0.30 ≈ 2.33),
##   否则刻痕会直接盖在香上 —— zoom 6 实拍抓到过, 两个入口挤在同一块地方。
const TALLY_Y := 2.45
## 火星(上飘小粒): 尺寸(码) / 升高(米) / 存活(秒)
const SPARK_PX := 11.0
const SPARK_RISE_M := 0.75
const SPARK_SEC := 0.65
## 火印(强化普攻命中): 盖章起手倍率 → 落定尺寸(码) / 存活(秒)
const SEAL_D := 52.0
const SEAL_K0 := 1.70
const SEAL_SEC := 0.42
## 火印贴在目标身上的高度(米)。★不能贴身体正中 —— 通用斩击就糊在那儿(实拍为证)
const SEAL_Y := 0.95

## 节点身份标记(程序生成贴图 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "incense_vfx"
## 最后一道闸: 同时在场的本层【一次性】节点上限(香台是常驻的, 不受它约束)
const OWNED_CAP := 96

static var _tex_stick: Texture2D = null
static var _tex_seal: Texture2D = null
static var _tex_tally: ImageTexture = null
static var _tex_spark: ImageTexture = null
static var _tex_glow: ImageTexture = null

var battle
## 正在播的一次性特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进
var _fx: Array = []
## 常驻香台 [{node, u, sticks, glows, t, out, …}] —— 由携带者的 `emp` 驱动, 不自己计时
var _altars: Array = []


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §贴图 —— 两张真像素素材 + 两张程序化小件
# ══════════════════════════════════════════════════════════════════

## 一支点着的香(素材)。
static func stick_tex() -> Texture2D:
	if _tex_stick == null:
		_tex_stick = load(STICK_TEX_PATH)
	return _tex_stick


## 火印(素材)。
static func seal_tex() -> Texture2D:
	if _tex_seal == null:
		_tex_seal = load(SEAL_TEX_PATH)
	return _tex_seal


## 一道刻痕: **横向**的凿沟(两端收尖 + 一条亮芯) —— 读作"在石头上划了一道"。
##
## ★★为什么是横的(2026-08-09 实拍改): 上一版是**竖直**的锥形亮条, 而这一件的
##   主母题(香)也是竖直的 —— zoom 6 实拍里 4 道刻痕整整齐齐排在香台旁边,
##   看上去就是"四支没点着的香"。同一件装备的两个入口**剪影撞车**, 比看不见更糟:
##   看得见, 但读成了别的东西。⇒ 刻痕转 90°, 与香在剪影上正交。
static func tally_tex() -> ImageTexture:
	if _tex_tally != null:
		return _tex_tally
	var w := 64
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cy := float(h - 1) * 0.5
	for x in range(w):
		var fx: float = float(x) / float(w - 1)
		if fx < 0.03 or fx > 0.97:
			continue
		# 两端收尖: 中段最厚, 到两头几乎归零 ⇒ 是"划痕", 不是"一根棍"
		var thick: float = 8.2 * sin(clampf((fx - 0.03) / 0.94, 0.0, 1.0) * PI)
		if thick < 0.6:
			continue
		for y in range(h):
			var dy: float = absf(float(y) - cy)
			if dy > thick:
				continue
			var core: float = clampf(1.0 - dy / maxf(0.5, thick), 0.0, 1.0)
			var c: Color = EMBER.lerp(GOLD, core)
			if core > 0.66:
				c = c.lerp(Color(1.0, 0.98, 0.90), (core - 0.66) / 0.34)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(0.40 + 0.60 * core, 0.0, 1.0)))
	_tex_tally = ImageTexture.create_from_image(img)
	return _tex_tally


## 一粒上飘的火星(菱形小粒, 免得又是圆点)。
static func spark_tex() -> ImageTexture:
	if _tex_spark != null:
		return _tex_spark
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var m: float = absf(float(x) - c) / c + absf(float(y) - c) / c
			if m > 1.0:
				continue
			var a: float = clampf((1.0 - m) * 2.6, 0.0, 1.0)
			var col: Color = EMBER.lerp(GOLD, clampf((0.5 - m) * 2.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_tex_spark = ImageTexture.create_from_image(img)
	return _tex_spark


## 火头的光晕: 一团中心亮、边缘 0 的软圆(加色混合用)。
## ★内容**不铺满整张** —— 铺满的话缩放采样会在边界切出一圈硬边。
static func glow_tex() -> ImageTexture:
	if _tex_glow != null:
		return _tex_glow
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			if r > 0.92:
				continue
			var a: float = pow(clampf(1.0 - r / 0.92, 0.0, 1.0), 2.2)
			var core: float = clampf(1.0 - r * 1.6, 0.0, 1.0)
			var col: Color = EMBER.lerp(GOLD, core)
			# 芯部推到接近白 —— 加色混合在这一层做不到(见 _mk_sprite 的探针注释),
			# "亮"只能由贴图自己给
			if core > 0.55:
				col = col.lerp(Color(1.0, 0.98, 0.90), (core - 0.55) / 0.45)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	_tex_glow = ImageTexture.create_from_image(img)
	return _tex_glow


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

## 一块面向相机的公告板。★`no_depth_test` 是这一件的关键 —— 原来贴地被龟身压掉。
##
## ⚠【探针实测, 不是推断】`Sprite3D` **没有 `blend_mode` 属性**
##   (跑了一遍 `get_property_list()` 逐项找 "blend_mode" ⇒ false)。
##   本仓所有 `blend_mode = BLEND_MODE_ADD` 都写在 `StandardMaterial3D` 上,
##   而 Sprite3D 的材质是引擎内部生成的、拿不到 ⇒ **这一层做不出加色发光**。
##   ⇒ 火头的"亮"改由贴图自己给(`glow_tex` 芯部接近白 + 高 alpha), 在暗底上一样读得出。
func _mk_sprite(tex: Texture2D, size_px: float, col: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 18
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.pixel_size = (size_px * float(battle.WS)) / maxf(1.0, float(tex.get_width()))
	return s


## 世界坐标上的公告板(一次性特效用)。
func _board(tex: Texture2D, pos2: Vector2, y_m: float, size_px: float, col: Color) -> Sprite3D:
	var s := _mk_sprite(tex, size_px, col)
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


## 统一的淡出曲线: 前 `hold` 段**满亮**, 之后才落到 0。
## ★这一条是"淡出病"的解药 —— 短命特效一出生就线性淡出, 实拍就会读成灰/土棕。
static func _holdfade(q: float, hold: float) -> float:
	if q <= hold:
		return 1.0
	var k: float = clampf((q - hold) / maxf(0.001, 1.0 - hold), 0.0, 1.0)
	return clampf(1.0 - k * k, 0.0, 1.0)


# ══════════════════════════════════════════════════════════════════
#  §入口①  刻成痕
# ══════════════════════════════════════════════════════════════════

## `marks` = 刻完之后的总数(飘字要显示它); `gained` = **这一帧一共刻了几道**。
## ★`gained` 不是装饰: 结算侧一帧可能刻 5 道(探针实测), 不合成一次就会摞 5 份重叠演出。
func mark_carved(u: Dictionary, marks: int, gained: int = 1) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var n: int = clampi(gained, 1, TALLY_MAX)
	var p: Vector2 = u.get("pos", Vector2.ZERO)
	if _has_world():
		# n 道横沟**自上而下一道一道刻**(错开 0.045 秒), 摞成一小叠 —— 不再全压在一个点上。
		# 最下面那道先刻, 后面的往上加, 读起来就是"又添了几道"。
		for i in range(n):
			var y1: float = TALLY_Y + float(i) * TALLY_ROW_M
			# 每道左右错开一点、长短也差一点 —— 整整齐齐的等长横条会读成"一摞盘子",
			# 手刻出来的痕本来就参差
			var jx: float = (-7.0 if i % 2 == 0 else 7.0) * (0.6 + 0.4 * float(i % 3))
			var at: Vector2 = p + Vector2(jx, 0.0)
			var t := _board(tally_tex(), at, y1 + 0.26, TALLY_PX * (0.82 + 0.09 * float(i % 3)),
				Color(1, 1, 1, 1.0))
			_adopt(t, TALLY_SEC, "tally",
				{"p": at, "y0": y1 + 0.26, "y1": y1, "delay": 0.045 * float(i)})
		for dx in [-24.0, 24.0]:
			var sp := _board(spark_tex(), p + Vector2(dx, 0.0), TALLY_Y, SPARK_PX, Color(1, 1, 1, 1.0))
			_adopt(sp, SPARK_SEC, "spark", {"p": p + Vector2(dx, 0.0), "y0": TALLY_Y})
	# 飘字。★满 300 改文案 —— 到顶了还在跳 "+1" 是最容易被当成 bug 的那种表现
	var txt: String = "香火 满" if marks >= IncenseStoneSystem.MARK_CAP else ("香火 +%d" % n)
	battle._vfx._float_text(p + Vector2(0.0, -18.0), txt, GOLD, false, "buff", "")


# ══════════════════════════════════════════════════════════════════
#  §入口②  主动就绪: 头顶点起一排香
# ══════════════════════════════════════════════════════════════════

## ★不接受"点几支"参数: 支数**每帧从 `emp` 读**(见 tick 的 altar 分支),
##   所以它永远等于真实剩余次数, 不会和结算各走各的。
func empower_burst(u: Dictionary) -> void:
	if not (u is Dictionary) or not u.get("alive", false) or not _has_world():
		return
	_drop_altar_of(u)          # 同一只龟重复就绪: 先撤旧台, 不叠两排
	var n: int = _emp_of(u)
	if n <= 0:
		return
	var root := Node3D.new()
	root.set_meta(META_KEY, "altar")
	# ★★出生就摆到位, 别等 `_tick_altars` 的第一帧 —— Node3D 默认在原点,
	#   只在 tick 里写位置的话【第一帧整座香台画在地图原点(0,0,0)】。
	#   一帧闪一下, 肉眼几乎抓不到, 但门禁一量就露(实测 y=0.00)。
	root.position = battle._world_pos(Vector2(u.get("pos", Vector2.ZERO)), HEAD_Y)
	battle._world.add_child(root)
	var sticks: Array = []
	var glows: Array = []
	var x0: float = -0.5 * float(n - 1) * STICK_GAP_PX
	for i in range(n):
		var lx: float = (x0 + float(i) * STICK_GAP_PX) * float(battle.WS)
		var g := _mk_sprite(glow_tex(), GLOW_PX, Color(1, 1, 1, 0.0))
		# 光晕对准火头(贴图上部约 1/4 处), 香整体高 = 宽 × STICK_TEX_ASPECT
		g.position = Vector3(lx, STICK_W_PX * STICK_TEX_ASPECT * float(battle.WS) * 0.22, 0.0)
		root.add_child(g)
		glows.append(g)
		var s := _mk_sprite(stick_tex(), STICK_W_PX, Color(1, 1, 1, 0.0))
		s.position = Vector3(lx, 0.0, 0.0)
		root.add_child(s)
		sticks.append(s)
		# 点火那一下: 每支各飘一粒火星
		var at: Vector2 = Vector2(u.get("pos", Vector2.ZERO)) + Vector2(x0 + float(i) * STICK_GAP_PX, 0.0)
		var sp := _board(spark_tex(), at, HEAD_Y + 0.25, SPARK_PX, Color(1, 1, 1, 1.0))
		_adopt(sp, SPARK_SEC, "spark", {"p": at, "y0": HEAD_Y + 0.25})
	_altars.append({"node": root, "u": u, "sticks": sticks, "glows": glows,
		"t": 0.0, "out": -1.0, "lit": n, "snuff": {}})


# ══════════════════════════════════════════════════════════════════
#  §入口③  强化普攻命中: 目标身上盖一枚火印
# ══════════════════════════════════════════════════════════════════

## ★高度 `SEAL_Y` 抬到上半身以上, 是因为**通用斩击正好糊在身体正中**(A/B 基线实拍为证)。
##   香台那边少一支香不在这里写 —— 它由 `emp` 驱动, 见 tick。
func empower_hit(_u: Dictionary, tgt: Dictionary) -> void:
	if not (tgt is Dictionary) or not tgt.get("alive", false) or not _has_world():
		return
	var p: Vector2 = tgt.get("pos", Vector2.ZERO)
	var y: float = SEAL_Y + float(tgt.get("height", 0.0))
	var f := _board(seal_tex(), p, y, SEAL_D * SEAL_K0, Color(1, 1, 1, 1.0))
	_adopt(f, SEAL_SEC, "seal", {"p": p, "y": y})
	for dx in [-13.0, 0.0, 13.0]:
		var at: Vector2 = p + Vector2(dx, 0.0)
		var sp := _board(spark_tex(), at, y - 0.30, SPARK_PX, Color(1, 1, 1, 1.0))
		_adopt(sp, SPARK_SEC, "spark", {"p": at, "y0": y - 0.30})


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween)
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick_altars(delta)
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
			"spark":
				s.position = battle._world_pos(f["p"], float(f["y0"]) + SPARK_RISE_M * q)
				s.modulate.a = _holdfade(q, 0.45)
			"tally":
				# 错开落下 + 自上而下"刻进去" + 前 60% 满亮
				var d: float = float(f.get("delay", 0.0))
				var qq: float = clampf((float(f["t"]) - d) / maxf(0.01, float(f["life"]) - d), 0.0, 1.0)
				s.position = battle._world_pos(f["p"], lerpf(float(f["y0"]), float(f["y1"]), qq * qq))
				s.modulate.a = (0.0 if float(f["t"]) < d else _holdfade(qq, 0.60))
			"seal":
				# 盖章: 1.7× 砸到 1.0×(前 35% 完成), 然后按住不动直到 68% 才淡出
				var k: float = lerpf(SEAL_K0, 1.0, clampf(q / 0.35, 0.0, 1.0))
				s.pixel_size = (SEAL_D * k * float(battle.WS)) / maxf(1.0, float(s.texture.get_width()))
				s.modulate.a = _holdfade(q, 0.68)
			_:
				s.modulate.a = _holdfade(q, 0.55)
		if q >= 1.0:
			s.queue_free()
			_fx.remove_at(i)


## 常驻香台: 支数**读 `emp`**, 不自己计时。
func _tick_altars(delta: float) -> void:
	for i in range(_altars.size() - 1, -1, -1):
		var a: Dictionary = _altars[i]
		var root = a.get("node", null)
		if not (root is Node3D) or not is_instance_valid(root):
			_altars.remove_at(i)
			continue
		a["t"] = float(a["t"]) + delta
		var u = a.get("u", null)
		var alive: bool = (u is Dictionary) and bool((u as Dictionary).get("alive", false))
		var emp: int = _emp_of(u) if alive else 0
		# 收尾: emp 用完 / 携带者倒下 ⇒ 淡出 ALTAR_OUT_SEC 后拔掉
		if emp <= 0 and float(a.get("out", -1.0)) < 0.0:
			a["out"] = 0.0
		var out_a := 1.0
		if float(a.get("out", -1.0)) >= 0.0:
			a["out"] = float(a["out"]) + delta
			out_a = clampf(1.0 - float(a["out"]) / ALTAR_OUT_SEC, 0.0, 1.0)
			if out_a <= 0.0:
				(root as Node3D).queue_free()
				_altars.remove_at(i)
				continue
		# 跟着携带者走 + 入场升起
		if alive:
			var rise: float = STICK_RISE_M * clampf(float(a["t"]) / ALTAR_IN_SEC, 0.0, 1.0)
			(root as Node3D).position = battle._world_pos(Vector2((u as Dictionary)["pos"]), HEAD_Y + rise)
		var sticks: Array = a.get("sticks", [])
		var glows: Array = a.get("glows", [])
		var snuff: Dictionary = a.get("snuff", {})
		for k in range(sticks.size()):
			var sp = sticks[k]
			if not (sp is Sprite3D) or not is_instance_valid(sp):
				continue
			# 第 k 支还亮着 ⇔ k < emp。灭掉的那一支走 STICK_SNUFF_SEC 的熄灭
			var lit: bool = k < emp
			if not lit and not snuff.has(k):
				snuff[k] = 0.0
			var la := 1.0
			if snuff.has(k):
				snuff[k] = float(snuff[k]) + delta
				la = clampf(1.0 - float(snuff[k]) / STICK_SNUFF_SEC, 0.0, 1.0)
			var ina: float = clampf(float(a["t"]) / ALTAR_IN_SEC, 0.0, 1.0)
			(sp as Sprite3D).modulate.a = ina * la * out_a
			if k < glows.size() and glows[k] is Sprite3D and is_instance_valid(glows[k]):
				# 火头呼吸: 0.72~1.0 之间脉动, 让 20 码宽的香在实战镜头下也有一点"活气"
				var puls: float = 0.86 + 0.14 * sin(float(a["t"]) * 7.4 + float(k) * 1.9)
				(glows[k] as Sprite3D).modulate.a = ina * la * out_a * puls
		a["snuff"] = snuff


func _emp_of(u) -> int:
	if not (u is Dictionary):
		return 0
	var st = (u as Dictionary).get("eq_state", {})
	if not (st is Dictionary):
		return 0
	var stt = (st as Dictionary).get(IncenseStoneSystem.EID, null)
	return int((stt as Dictionary).get("emp", 0)) if stt is Dictionary else 0


func _drop_altar_of(u: Dictionary) -> void:
	for i in range(_altars.size() - 1, -1, -1):
		var a: Dictionary = _altars[i]
		if is_same(a.get("u", null), u):
			var x = a.get("node", null)
			if x is Node3D and is_instance_valid(x):
				x.queue_free()
			_altars.remove_at(i)


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
	for a in _altars:
		var y = a.get("node", null)
		if y is Node3D and is_instance_valid(y):
			y.queue_free()
			n += 1
	_altars.clear()
	return n


## 现存节点数(可按 kind 过滤)。`kind = "altar"` 数的是常驻香台。
func alive_count(kind: String = "") -> int:
	var n := 0
	if kind == "" or kind == "altar":
		for a in _altars:
			var y = a.get("node", null)
			if y is Node3D and is_instance_valid(y):
				n += 1
	if kind == "altar":
		return n
	for f in _fx:
		var x = f.get("node", null)
		if not (x is Node3D) or not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n


## 某个香台当下点着几支香(门禁量真实对象: 数 alpha > 0.5 的 Sprite3D, 不读记账字段)。
## ★不返回 `emp` —— 那是结算侧的数, 拿它当断言等于"自己证明自己"。
func lit_sticks_of(u: Dictionary) -> int:
	for a in _altars:
		if not is_same(a.get("u", null), u):
			continue
		var n := 0
		for sp in (a.get("sticks", []) as Array):
			if sp is Sprite3D and is_instance_valid(sp) and float((sp as Sprite3D).modulate.a) > 0.5:
				n += 1
		return n
	return -1
