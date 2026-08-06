class_name IncenseVfx
extends RefCounted
## incense_vfx.gd — 093 香火石的演出层
##
## 三个入口, 全部**零素材**(逐像素程序化贴图 + 自管生命周期):
##   · `mark_carved(u, marks)`  刻成一道痕: 头顶落下一道金色刻痕 + 两粒上飘的火星 + 刻痕数飘字
##   · `empower_burst(u)`       主动就绪: 头顶腾起**三支香**(带火头与青烟)
##   · `empower_hit(u, tgt)`    强化普攻命中: 目标身上一朵**四瓣火焰**
##
## ══════════════════════════════════════════════════════════════════════
##  ★2026-08-07 重做: 三个入口原来全是 `battle._skill_ring` 的细环
## ══════════════════════════════════════════════════════════════════════
## 用户实拍结论:「三个入口全是细环, 被龟身与伤害数字压掉」。两条病因各治一条:
##   ① **形状撞车**: 细环是全场最泛滥的形状(命中环 / 技能环 / 目标环 / 各家羁绊环),
##      读不出"这是香火石"。⇒ 换成**竖直的香 + 火焰**母题, 剪影上与任何环都不同。
##   ② **位置被压**: 环贴在**脚下地面**, 而龟立绘、影子、伤害飘字全在那儿。
##      ⇒ 演出整体抬到**头顶以上**(HEAD_Y 起), 并 `no_depth_test` 保证不被立绘吞。
## ★注意分工: `_skill_ring` **本身**由另一路在修(它的尺寸/透明度两条曲线),
##   本文件只是**不再调用它**, 一行都没有动那个函数。
##
## ★为什么演出层与结算层分开(CLAUDE.md §3.5):
##   数值测试**不许依赖任何 tween 跑完** —— 无头 CI 下 `create_tween()` 推进不稳,
##   本地永远复现不出来(`verify_pirate_hook` 为此连红三次)。
##   所以 IncenseStoneSystem 里的伤害/刻痕**全部即时结算**, 这里只负责好看;
##   本文件的每个入口都能被单独调用(供门禁与 VFXPREVIEW 用), 不参与任何判定。
##   ⇒ 本文件也**不用 tween**: 生命周期由 `tick(delta)` 自己推, 由主循环每帧调一次。
##
## ★香火的视觉母题: **金红双色 + 竖直向上**。与 092 毒蛾茧的紫绿下沉、
##   094 祖龟碑的灰蓝厚重区分开 —— 三件同为遗物, 同场时要一眼分得出是谁在响。

const GOLD := Color(1.0, 0.82, 0.42, 0.95)     # 香火金
const EMBER := Color(0.98, 0.44, 0.20, 0.85)   # 香火红

## 演出基准高度(米): 头顶。★脚下那一层被龟身/影子/飘字占满了, 这一件不去挤。
const HEAD_Y := 1.55
## 三支香: **宽**(码) / 升起的高度(米) / 存活(秒)。
## ★`_board` 是按【贴图宽】换算 pixel_size 的 ⇒ 这里必须传"宽"; 香的贴图是 24×96,
##   所以实际高 = 宽 × 4 = 60 码。第一版误传了"高"(74) ⇒ 实际画出 74×296 码的巨柱,
##   干净台一拍就顶出画面外 —— 这类错**只看代码看不出来, 只有实拍能抓**。
const STICK_W_PX := 19.0
const STICK_TEX_ASPECT := 4.0
const STICK_RISE_M := 0.60
const STICK_SEC := 0.85
## 刻痕: 尺寸(码) / 存活(秒)
const TALLY_PX := 46.0
const TALLY_SEC := 0.55
## 火星(上飘的小粒): 尺寸(码) / 升高(米) / 存活(秒)
const SPARK_PX := 13.0
const SPARK_RISE_M := 0.85
const SPARK_SEC := 0.7
## 四瓣火焰(强化普攻命中): 起手/终了尺寸(码) / 存活(秒)
const FLARE_D0 := 44.0
const FLARE_D1 := 104.0
const FLARE_SEC := 0.36

## 节点身份标记(程序生成贴图 `resource_path` 是空串, 按路径数会全数成 0)
const META_KEY := "incense_vfx"
## 最后一道闸: 同时在场的本层节点上限
const OWNED_CAP := 96

static var _tex_stick: ImageTexture = null
static var _tex_tally: ImageTexture = null
static var _tex_flare: ImageTexture = null
static var _tex_spark: ImageTexture = null

var battle
## 正在播的特效 [{node, t, life, kind, …}] —— 每帧由 `tick()` 推进
var _fx: Array = []


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and battle._world != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §程序化贴图 —— 竖直母题, 一张圆环都没有
# ══════════════════════════════════════════════════════════════════

## 一支香: 细长竖杆(暗红香身) + 顶端一颗火头 + 一缕上飘的青烟。
static func stick_tex() -> ImageTexture:
	if _tex_stick != null:
		return _tex_stick
	var w := 24
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(w - 1) * 0.5
	for y in range(h):
		var fy: float = float(y) / float(h - 1)          # 0 = 顶(火头) .. 1 = 底
		for x in range(w):
			var dx: float = absf(float(x) - cx)
			# ① 香身: 下 3/5 的一根**细**杆(细 + 暗 ⇒ 让火头当主角; 第一版杆太粗,
			#    实拍读成了"三只棕色的角"而不是"三支点着的香")
			if fy > 0.42 and dx <= 1.6:
				var a: float = clampf((1.6 - dx) / 1.0, 0.25, 0.9) * clampf((1.0 - fy) * 2.0, 0.25, 1.0)
				img.set_pixel(x, y, Color(0.46, 0.20, 0.13, a))
			# ② 火头: 顶端一颗上尖下圆的火苗(占了整支的 2/5, 是这支香的主角)
			if fy <= 0.46:
				var ny: float = fy / 0.46                # 0 顶 .. 1 火苗底
				var wid: float = 1.8 + 8.4 * sin(ny * PI * 0.80)
				if dx <= wid:
					var core: float = clampf(1.0 - dx / maxf(0.5, wid), 0.0, 1.0)
					# 外焰橙 → 内焰金 → 焰心近白: 三段才读得出"这是火"而不是"一个棕色的角"
					var c: Color = EMBER.lerp(GOLD, clampf(core * 1.5, 0.0, 1.0))
					if core > 0.62:
						c = c.lerp(Color(1.0, 0.97, 0.86), (core - 0.62) / 0.38)
					img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(0.62 + 0.38 * core, 0.0, 1.0)))
	_tex_stick = ImageTexture.create_from_image(img)
	return _tex_stick


## 一道刻痕: 上宽下窄的凿痕(带一条亮芯) —— 读作"刻进去了", 不是"炸开了"。
static func tally_tex() -> ImageTexture:
	if _tex_tally != null:
		return _tex_tally
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(n - 1) * 0.5
	for y in range(n):
		var fy: float = float(y) / float(n - 1)
		if fy < 0.06 or fy > 0.94:
			continue
		var wid: float = 7.0 * (1.0 - fy * 0.72)         # 上宽下窄 = 凿痕
		for x in range(n):
			var dx: float = absf(float(x) - cx)
			if dx > wid:
				continue
			var core: float = clampf(1.0 - dx / maxf(0.5, wid), 0.0, 1.0)
			var c: Color = EMBER.lerp(GOLD, core)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(0.30 + 0.70 * core, 0.0, 1.0)))
	_tex_tally = ImageTexture.create_from_image(img)
	return _tex_tally


## 四瓣火焰: 上下左右四片火舌 + 亮芯。★不是环、不是圆盘 —— 剪影上与命中闪光分得开。
static func flare_tex() -> ImageTexture:
	if _tex_flare != null:
		return _tex_flare
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var dx: float = (float(x) - c) / c
			var dy: float = (float(y) - c) / c
			var r: float = sqrt(dx * dx + dy * dy)
			if r > 1.0 or r < 0.001:
				continue
			var th: float = atan2(dy, dx)
			var petal: float = absf(cos(th * 2.0))        # 四瓣: 0°/90°/180°/270° 最长
			var edge: float = petal * 0.94 + 0.10         # 花瓣边界半径
			if r > edge:
				continue
			var core: float = clampf(1.0 - r / maxf(0.05, edge), 0.0, 1.0)
			var col: Color = EMBER.lerp(GOLD, core * core)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(0.28 + 0.72 * core, 0.0, 1.0)))
	_tex_flare = ImageTexture.create_from_image(img)
	return _tex_flare


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


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

## 面向相机的公告板。★`no_depth_test` 是这一件的关键 —— 原来贴在地上被龟身压掉。
func _board(tex: Texture2D, pos2: Vector2, y_m: float, size_px: float, col: Color) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 18
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = col
	s.position = battle._world_pos(pos2, y_m)
	s.pixel_size = (size_px * float(battle.WS)) / maxf(1.0, float(tex.get_width()))
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


# ══════════════════════════════════════════════════════════════════
#  §三个入口
# ══════════════════════════════════════════════════════════════════

## 刻成一道痕。marks = 刻完之后的总数(飘字要显示它)。
func mark_carved(u: Dictionary, marks: int) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	var p: Vector2 = u.get("pos", Vector2.ZERO)
	if _has_world():
		# 一道金色凿痕落在头顶(自上而下"刻进去"), 两侧各飘一粒火星
		var t := _board(tally_tex(), p, HEAD_Y + 0.42, TALLY_PX, Color(1, 1, 1, 0.98))
		_adopt(t, TALLY_SEC, "tally", {"p": p, "y0": HEAD_Y + 0.42, "y1": HEAD_Y - 0.06})
		for dx in [-16.0, 16.0]:
			var s := _board(spark_tex(), p + Vector2(dx, 0.0), HEAD_Y, SPARK_PX, Color(1, 1, 1, 0.9))
			_adopt(s, SPARK_SEC, "spark", {"p": p + Vector2(dx, 0.0), "y0": HEAD_Y})
	# 刻痕数飘字。★满 300 时改文案 —— 到顶了却还在跳"+1"是最容易被当成 bug 的那种表现
	var txt := ("香火 %d" % marks) if marks < IncenseStoneSystem.MARK_CAP else "香火 满"
	battle._vfx._float_text(p + Vector2(0.0, -18.0), txt, GOLD, false, "buff", "")


## 主动就绪: 头顶腾起**三支香**(错开升起, 中间那支最高)。
func empower_burst(u: Dictionary) -> void:
	if not (u is Dictionary) or not u.get("alive", false) or not _has_world():
		return
	var p: Vector2 = u.get("pos", Vector2.ZERO)
	for i in range(3):
		var dx: float = [-22.0, 0.0, 22.0][i]
		var hh: float = [0.86, 1.0, 0.86][i]
		var at: Vector2 = p + Vector2(dx, 0.0)
		var s := _board(stick_tex(), at, HEAD_Y, STICK_W_PX * hh, Color(1, 1, 1, 0.0))
		_adopt(s, STICK_SEC, "stick", {"p": at, "y0": HEAD_Y, "rise": STICK_RISE_M * hh,
			"delay": 0.07 * float(i)})
		var sp := _board(spark_tex(), at, HEAD_Y + 0.5, SPARK_PX, Color(1, 1, 1, 0.85))
		_adopt(sp, SPARK_SEC, "spark", {"p": at, "y0": HEAD_Y + 0.5})


## 强化普攻命中: 目标身上一朵四瓣火焰(比普通命中大一圈, 让"这一下是强化的"读得出来)。
func empower_hit(_u: Dictionary, tgt: Dictionary) -> void:
	if not (tgt is Dictionary) or not tgt.get("alive", false) or not _has_world():
		return
	var p: Vector2 = tgt.get("pos", Vector2.ZERO)
	var y: float = 0.85 + float(tgt.get("height", 0.0))
	var f := _board(flare_tex(), p, y, FLARE_D0, Color(1, 1, 1, 0.98))
	_adopt(f, FLARE_SEC, "flare", {"d0": FLARE_D0, "d1": FLARE_D1})


# ══════════════════════════════════════════════════════════════════
#  §每帧推进(不用 tween) + 撤场
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if delta <= 0.0 or _fx.is_empty():
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
			"stick":
				# 错开起步 + 升起 + 先亮后隐(香点着了 → 烧起来 → 淡出)
				var d: float = float(f.get("delay", 0.0))
				var qq: float = clampf((float(f["t"]) - d) / maxf(0.01, float(f["life"]) - d), 0.0, 1.0)
				s.position = battle._world_pos(f["p"], float(f["y0"]) + float(f["rise"]) * qq)
				# ★淡出要【慢】: 原来 (1−q²) 在中段就掉到 0.36, 整支香被压成一根棕色的影子。
				#   改成 (1−q³) ⇒ 大半个生命周期都在满亮度上, 火头的金白色才读得出来。
				s.modulate.a = clampf(minf(qq * 6.0, 1.0) * (1.0 - qq * qq * qq), 0.0, 1.0)
			"spark":
				s.position = battle._world_pos(f["p"], float(f["y0"]) + SPARK_RISE_M * q)
				s.modulate.a = 0.9 * (1.0 - q * q)
			"tally":
				s.position = battle._world_pos(f["p"], lerpf(float(f["y0"]), float(f["y1"]), q * q))
				s.modulate.a = 1.0 - q * q * q
			"flare":
				var d0: float = float(f.get("d0", FLARE_D0))
				var d1: float = float(f.get("d1", FLARE_D1))
				s.pixel_size = (lerpf(d0, d1, q) * float(battle.WS)) / maxf(1.0, float(s.texture.get_width()))
				s.modulate.a = 1.0 - q * q
			_:
				s.modulate.a = 1.0 - q
		if q >= 1.0:
			s.queue_free()
			_fx.remove_at(i)


## 撤场: 拔掉一切自己建的节点。返回拔了几个(门禁验"真的清干净了")。
func clear() -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if x is Node3D and is_instance_valid(x):
			x.queue_free()
			n += 1
	_fx.clear()
	return n


## 现存节点数(可按 kind 过滤) —— 门禁量真实对象用。
func alive_count(kind: String = "") -> int:
	var n := 0
	for f in _fx:
		var x = f.get("node", null)
		if not (x is Node3D) or not is_instance_valid(x):
			continue
		if kind != "" and str((x as Node).get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
