class_name MagicEqVfx
extends BombEqVfx
## magic_eq_vfx.gd —— 魔法书羁绊【飞弹】+ 魔法书 10 件 + 三种骷髅 的演出层(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md)
##
## ★只画不判定: 结算全在 EqMagicBatch / MagicbookSynergySystem; 无头 / 没有世界节点时什么都不做(继承的 _ok())。
## ★生命周期 = 继承炸弹演出层的 `tick` / `_anim` / `_later`(不用 tween, CLAUDE.md §4.5); 本文件只换特效表(覆盖 `_row`),
##   另加两种自己的: 飞行物(位置由结算侧每步回调摆, 演出不按固定秒数补间) / 126 书页(每帧按批系统里的角度 / 张数摆)。
## 素材(如实): assets/sprites/vfx/magic-*.png = PixelLab 特效工作台预设改配色 / 改参数导出; magic-page.png = PixelLab 生成的单张书页;
##   eq-skel*-*.png = PixelLab 生成的骷髅龟动作帧。全部由 tools/assetgen/pack_magic_art.py 打包(确定性)。
##   逐帧研究: docs/studies/20261125-魔法书羁绊特效逐帧.md。

## 特效表: 名 → [路径, 帧宽, 帧高, 内容直径(像素), 锚点 x, 锚点 y](pack_magic_art.py 打印, 照抄)
const MSHEETS := {
	"missile-orb": ["vfx/magic-missile-orb.png", 48, 48, 37.0, 24, 24],   # 8 帧 · 循环 ·【飞弹】弹头: 蓝色奥术球
	"missile-hit": ["vfx/magic-missile-hit.png", 64, 64, 44.0, 32, 32],   # 5 帧 ·【飞弹】命中: 蓝白闪 + 射线 + 环
	"note-bolt": ["vfx/magic-note-bolt.png", 32, 32, 24.0, 16, 16],   # 8 帧 · 循环 · 117 学徒笔记飞弹: 小而淡的青白球(与羁绊飞弹区分)
	"note-hit": ["vfx/magic-note-hit.png", 43, 42, 37.0, 18, 23],   # 5 帧 · 117 命中: 青白小十字环
	## 119 / 120 第三版(11-25): 贴安妮 Q 官网演示视频 / 冰雪墨菲特 E 展示视频逐帧做(参考研究 docs/studies/20261125-参考-*.md, 分段表见方案书附录);
	##   工作台里自己写的图层(水滴弹头 / 光团 / 横条星芒 / 舔火 / 贴地亮圈 / 冰火圆盘 / 压暗区 / 冻印 / 细冰条), 不是现成模板
	"fire-head": ["vfx/magic-fire-head.png", 84, 36, 54.0, 64, 18],   # 8 帧 · 循环 · 119 弹头: 前沿黄白月牙 · 中橙 · 后深红火舌往后飘 · 外包品红辉光(锚点 = 弹头前沿; 引擎按飞行方向转)
	"fire-hit3": ["vfx/magic-fire-hit3.png", 96, 84, 78.0, 48, 44],   # 17 帧 · 119 命中: 小爆点 → 圆光团鼓到约一个目标大 → 横条 + 星芒 → 余火往上舔 + 碎片蹦出 + 脚下暗烟
	"fire-cast": ["vfx/magic-fire-cast.png", 48, 48, 34.0, 24, 24],   # 5 帧 · 119 出手: 施法点一团橙光 + 品红晕
	"fire-ember": ["vfx/magic-fire-ember.png", 28, 28, 16.0, 14, 14],   # 10 帧 · 119 沿路火星: 几颗火星往外蹦、冷成暗红
	"frost-e": ["vfx/magic-frost-e.png", 200, 132, 194.0, 100, 66],   # 39 帧 · 120 贴地: 亮圈 3 帧胀满 + 冰火圆盘 + 毛刺环 + 雾 → 压暗区留 1.1 秒 + 圆心冻印 1.2 秒后淡掉(亮圈半径 = 92 像素)
	"frost-shard": ["vfx/magic-frost-shard.png", 48, 60, 29.0, 24, 46],   # 17 帧 · 120 圆面上的细冰条: 3 帧长出 → 停 → 碎, 碎冰上抛落地(锚点 = 冰条根部)
	"storm-bolt": ["vfx/magic-storm-bolt.png", 96, 128, 127.0, 48, 110, 2],   # 8 帧 · 121 风暴之书: 天降黄色闪电(第 7 列 = 从第 2 帧开播: 闪电已快到地面, 落地格对上伤害那一刻)
	"holy-chest": ["vfx/magic-holy-chest.png", 43, 57, 45.0, 20, 30],   # 12 帧 · 循环 · 122 治愈圣典持续回复(第二版): 胸口一团绿光脉动 + 绿色光点 / 加号往上飘(锚点 = 光团中心)
	"scroll-shield": ["vfx/magic-scroll-shield.png", 96, 96, 81.0, 48, 48],   # 8 帧 · 循环 · 118 羊皮咒卷护盾: 金色符文环
	"skel-rise": ["vfx/magic-skel-rise.png", 64, 63, 58.0, 32, 18],   # 9 帧 · 123 骷髅破土: 绿环 + 骨灰 + 骨头蹦出
	"skel-crumble": ["vfx/magic-skel-crumble.png", 54, 91, 71.0, 26, 27],   # 8 帧 · 123 骷髅时间到化灰: 灰烟 + 骨头往下掉
	"skel-blast": ["vfx/magic-skel-blast.png", 128, 128, 105.0, 64, 64],   # 10 帧 · 123 骷髅法师骨火爆裂: 紫色爆炸
	"skel-wave": ["vfx/magic-skel-wave.png", 60, 76, 70.0, 30, 46],   # 8 帧 · 循环 · 123 骷髅祭司亡灵浪潮: 青色鬼火团 + 骷髅头
	"wave-hit": ["vfx/magic-wave-hit.png", 51, 47, 45.0, 23, 24],   # 5 帧 · 浪潮打到敌人: 青色爆闪 + 骷髅头飞散
	"wave-heal": ["vfx/magic-wave-heal.png", 46, 51, 31.0, 23, 28],   # 5 帧 · 浪潮经过友军: 青绿光球 + 加号
	"mirror-shatter": ["vfx/magic-mirror-shatter.png", 83, 99, 77.0, 41, 36],   # 10 帧 · 124 镜像分身碎裂: 紫白闪 + 光环 + 镜片碎屑往外飞
	"forbidden-blast": ["vfx/magic-forbidden-blast.png", 78, 94, 80.0, 39, 39],   # 10 帧 · 125 禁咒弹命中: 品红爆炸 + 符文碎片
	"page-cut": ["vfx/magic-page-cut.png", 47, 42, 41.0, 22, 26],   # 6 帧 · 126 近战书页划过敌人: 青色纸刃弧
	"page-block": ["vfx/magic-page-block.png", 51, 46, 45.0, 23, 23],   # 5 帧 · 126 远程书页格挡: 纸白闪 + 碎纸片
	"tome-hp": ["vfx/magic-tome-hp.png", 46, 51, 45.0, 23, 28],   # 5 帧 · 126 释放技能后临时最大生命: 金闪 + 上飘加号
	## 下面两张给骷髅远程普攻的弹道用(battle_ballistics._fire_bolt_from 直接 load, 取第 0 帧), 这里登记尺寸备查
	"skelm-bolt": ["vfx/magic-skelm-bolt.png", 40, 40, 30.0, 20, 20],   # 8 帧 · 循环 · 骷髅法师暗影弹: 紫球 + 小骷髅头
	"skelp-bolt": ["vfx/magic-skelp-bolt.png", 33, 33, 26.0, 16, 16],   # 8 帧 · 循环 · 骷髅祭司鬼火光: 青球 + 白点
}
const PAGE_TEX := "vfx/magic-page-anim.png"   ## 8 帧循环: 书页在空中翻转飘(PixelLab animate_image, 11-25)
const ANIM_FPS := 10.0
const PAGE_PX := 58.0           ## 书页显示大小(世界码; 11-25 第二版放大: 26 / 40 时录出来只是几个小纸片)
const PAGE_ORBIT_H := 1.05      ## 近战书页环绕高度(米)

var _flies: Array = []          ## 飞行物节点(换路清)
var _pages: Array = []          ## 126 书页 {u, ck, melee, nodes:[]}


func _row(key: String) -> Array:   # zero-caller-ok: 覆盖父类 BombEqVfx._row —— 父类的 _anim / _load 经它查表, 调用方在父类
	return MSHEETS.get(key, [])


# ═══════════════════════════════ 飞行物(结算侧每步摆位置) ═══════════════════════════════

func _fly_node(key: String, u: Dictionary, world_d: float) -> Sprite3D:
	var s := _anim(key, Vector2(u["pos"]), world_d, 60.0, 0.02, false, true)
	if s == null:
		return null
	s.no_depth_test = true
	s.render_priority = 11
	s.set_meta("h", body_h(u))
	s.position = battle._world_pos(Vector2(u["pos"]), float(s.get_meta("h")))
	_flies.append(s)
	return s


func _fly_to(node, p2: Vector2) -> void:
	if node is Sprite3D and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, float((node as Sprite3D).get_meta("h", 1.0)))


func _fly_end(node) -> void:
	if node is Sprite3D and is_instance_valid(node):
		(node as Sprite3D).queue_free()


## 羁绊【飞弹】(11-25 用户「太大了，而且没有轨迹…是这么直直飞吗？一般飞弹不这么做的吧」):
##   照卡莎 Q「艾卡西亚暴雨」的做法 —— 小而亮的弹头, 出手先朝两侧扇形散开、走一条往外鼓的弧线再拐进目标, 身后拖一条渐隐光尾。
##   ★只是画法: 结算仍是 launch_flight 按速度追身体(k = 已飞 / 总路程), 这里按同一个 k 在「出手点 → 外鼓控制点 → 目标当前位置」的
##     二次贝塞尔上取位置 ⇒ k = 1(碰到身体、结算)那一刻画面也正好在目标身上, 不会出现画面没到就掉血。
const MB_PX := 18.0              ## 弹头大小(世界码)
const MB_FAN_DEG := 32.0         ## 相邻两枚出手方向错开的角度
const MB_BULGE := 0.55           ## 外鼓程度(控制点离连线的距离 / 直线距离)
const MB_ARC_H := 0.9            ## 弧线额外抬高(米, 正中间最高)
const MB_TRAIL_LIFE := 0.22      ## 每段光带存在多久(秒) = 光尾长度(按飞行速度 ≈ 200 码)
const MB_TRAIL_W := 10.0         ## 光带最粗处的宽度(世界码, 比弹头细)
const MB_TRAIL_COL := Color(0.62, 0.78, 1.0, 0.9)   ## 羁绊飞弹光尾: 跟弹头同一种蓝
const NOTE_PX := 16.0            ## 117 学徒笔记: 比羁绊飞弹再小一圈(单发、青白)
const NOTE_TRAIL_W := 6.0
const NOTE_TRAIL_COL := Color(0.7, 1.0, 0.95, 0.8)
const TRAIL_TEX := "vfx/magic-missile-trail.png"
const GLOW_TRAIL_TEX := "vfx/magic-glow-trail.png"   ## 灰白光带(颜色由引擎按年龄染)
var _trail: Array = []           ## 光尾段 {node, t, sx}


func mb_launch(u: Dictionary, tgt: Dictionary, i: int, n: int):
	return _arc_launch("missile-orb", u, tgt, MB_PX, i, n, MB_TRAIL_COL, MB_TRAIL_W)


func mb_step(node, _from2: Vector2, _p2: Vector2, to2: Vector2, k: float, _i: int) -> void:
	_arc_step(node, to2, k)


## 弧线飞行物(羁绊【飞弹】/ 117 学徒笔记): 出手点 → 外鼓控制点 → 目标当前位置的二次贝塞尔, 按结算侧同一个 k 取位置;
##   第 i 枚(共 n 枚)往哪一侧鼓、鼓多少: 正中间那枚也略鼓(不走直线), 两侧依次加大角度, 左右交替。身后铺丝带光尾(颜色 / 宽度各自定)。
func _arc_launch(key: String, u: Dictionary, tgt: Dictionary, px: float, i: int, n: int, col: Color, width: float, bulge: float = 1.0, tex: String = TRAIL_TEX) -> Sprite3D:
	var s := _fly_node(key, u, px)
	if s == null:
		return null
	var a := Vector2(u["pos"])
	var b := Vector2(tgt["pos"])
	var d := b - a
	var L: float = maxf(1.0, d.length())
	var side_k: float = float(i) - float(n - 1) * 0.5
	if absf(side_k) < 0.01:
		side_k = 0.35 if (i % 2 == 0) else -0.35
	var ang: float = deg_to_rad(clampf(side_k * MB_FAN_DEG, -80.0, 80.0))
	var perp := Vector2(-d.y, d.x) / L
	s.set_meta("ctrl_off", (d * 0.35) + perp * L * MB_BULGE * sin(ang) * 2.0 * bulge)
	s.set_meta("from", a)
	s.set_meta("trail_col", col)
	s.set_meta("trail_w", width)
	s.set_meta("trail_tex", tex)
	return s


func _arc_step(node, to2: Vector2, k: float) -> void:
	if not (node is Sprite3D) or not is_instance_valid(node):
		return
	var s: Sprite3D = node
	var a: Vector2 = s.get_meta("from", to2)
	var c: Vector2 = a + Vector2(s.get_meta("ctrl_off", Vector2.ZERO))
	var q: float = clampf(k, 0.0, 1.0)
	var p: Vector2 = a * (1.0 - q) * (1.0 - q) + c * 2.0 * (1.0 - q) * q + to2 * q * q
	var h: float = float(s.get_meta("h", 1.0)) + MB_ARC_H * sin(PI * q)
	var prev: Vector3 = s.position
	s.position = battle._world_pos(p, h)
	if s.has_meta("orient"):
		_orient_screen(s, s.position - prev)   # 119 火球: 弹头朝前进方向
	if s.has_meta("book"):
		s.frame = int(float(battle._t) * ANIM_FPS * 1.6) % 8   # 125 飞书: 飞的时候书页翻得快一点(逐帧动画, 不是缩放)
	_trail_seg(prev, s.position, s.get_meta("trail_col", MB_TRAIL_COL), float(s.get_meta("trail_w", MB_TRAIL_W)), str(s.get_meta("trail_tex", TRAIL_TEX)),
		float(s.get_meta("trail_life", MB_TRAIL_LIFE)), s.get_meta("trail_grad", []))
	if s.has_meta("embers"):
		## 119 沿路火星: 每飞过一段撒一小簇(贴安妮 Q 尾巴两侧蹦出的橙色火星)
		var acc: float = float(s.get_meta("ember_acc", 0.0)) + prev.distance_to(s.position)
		if acc >= FIRE_EMBER_GAP * float(battle.WS):
			acc = 0.0
			_anim("fire-ember", p, 40.0, 0.42, h, false, false)
		s.set_meta("ember_acc", acc)


## 光尾 = 一条丝带(拖尾渲染器的做法): 每个 sim 步从上一位置到这一位置铺一段光带, 按路径方向转、按段长拉伸, 段与段首尾相接;
##   每段随年龄变细、变淡 ⇒ 弹头后面是一条连续、越往后越细的光尾。
##   (11-25 用户「这个飞弹的轨迹…就是这个图片叠在一起吗？」—— 第一版是弹头贴图的残影一个个摞起来, 不是轨迹。)
##   ★不用每帧现画的 ImmediateMesh(直播录不进流, memory fb-no-immediatemesh-vfx-stream): 每段是一个 Sprite3D,
##     位置 / 旋转 / 缩放 / 颜色都在录流器的跟踪表里。
func _trail_seg(a3: Vector3, b3: Vector3, col: Color, width: float, tex: String = TRAIL_TEX, life: float = MB_TRAIL_LIFE, grad: Array = []) -> void:
	if not _ok():
		return
	var cam = battle.get("_cam")
	if not is_instance_valid(cam) or not (cam is Camera3D):
		return
	var t: Texture2D = _load(tex)
	if t == null:
		return
	var cb: Basis = (cam as Camera3D).global_transform.basis
	var v: Vector3 = b3 - a3
	var vx: float = v.dot(cb.x)
	var vy: float = v.dot(cb.y)
	var seg: float = sqrt(vx * vx + vy * vy)
	if seg < 0.0005:
		return
	var g := Sprite3D.new()
	g.texture = t
	g.shaded = false
	g.transparent = true
	g.no_depth_test = true
	g.render_priority = 10
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 方向自己转(面朝镜头、绕视线转到路径方向); 建好之后不再改这个属性(直播白名单)
	g.pixel_size = (width * float(battle.WS)) / float(t.get_height())
	g.modulate = col   # 压成弹头同色(白芯在游戏尺寸下太白)
	battle._world.add_child(g)
	g.global_transform = Transform3D(cb * Basis(Vector3(0, 0, 1), atan2(vy, vx)), (a3 + b3) * 0.5)
	var sx: float = seg / (float(t.get_width()) * g.pixel_size) * 1.12   # 略长一点, 段与段之间不留缝
	g.scale = Vector3(sx, 1.0, 1.0)
	_trail.append({"node": g, "t": 0.0, "sx": sx, "a0": col.a, "life": life, "grad": grad})


## 颜色曲线取值: grad = [[q, Color], ...](q 升序)
func _grad_at(grad: Array, q: float) -> Color:
	for k in range(1, grad.size()):
		if q <= float(grad[k][0]):
			var a: Array = grad[k - 1]
			var b: Array = grad[k]
			return (a[1] as Color).lerp(b[1], clampf((q - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0])), 0.0, 1.0))
	return grad.back()[1]


func _tick_trail(delta: float) -> void:
	for j in range(_trail.size() - 1, -1, -1):
		var r: Dictionary = _trail[j]
		var g = r["node"]
		if not is_instance_valid(g):
			_trail.remove_at(j)
			continue
		r["t"] = float(r["t"]) + delta
		var q: float = float(r["t"]) / float(r.get("life", MB_TRAIL_LIFE))
		if q >= 1.0:
			(g as Node3D).queue_free()
			_trail.remove_at(j)
			continue
		var grad: Array = r.get("grad", [])
		if grad.is_empty():
			(g as Sprite3D).modulate.a = float(r.get("a0", 0.9)) * (1.0 - q)
		else:
			(g as Sprite3D).modulate = _grad_at(grad, q)
		(g as Sprite3D).scale = Vector3(float(r["sx"]), 1.0 - 0.85 * q, 1.0)   # 越旧越细 ⇒ 光尾往后收成一根线


func mb_land(node, tgt: Dictionary, hit: bool) -> void:
	_fly_end(node)
	if hit:
		_anim("missile-hit", Vector2(tgt["pos"]), 42.0, 0.35, 0.02, false, false, Color.WHITE, tgt)


var _note_n := 0   ## 第几发学徒笔记(左右交替鼓)


func note_launch(u: Dictionary, tgt: Dictionary):
	_note_n += 1
	return _arc_launch("note-bolt", u, tgt, NOTE_PX, _note_n % 2, 2, NOTE_TRAIL_COL, NOTE_TRAIL_W)   # 当成一对里的一发: 左右各鼓 16°, 一发往左一发往右


func note_land(node, tgt: Dictionary, hit: bool) -> void:
	_fly_end(node)
	if hit:
		_anim("note-hit", Vector2(tgt["pos"]), 50.0, 0.32, 0.02, false, false, Color.WHITE, tgt)


## 119 火球(11-25 第三版, 贴安妮 Q 官网演示视频逐帧做; 研究 docs/studies/20261125-参考-安妮Q.md, 分段表见方案书附录):
##   ① 出手: 施法点一团橙光 + 品红晕 ② 弹头: 水滴形, 前沿黄白月牙最亮, 火舌往后飘, 外包品红辉光, 按屏幕上的飞行方向转
##   ③ 拖尾: 每段活 0.4 秒, 颜色按年龄 粉亮 → 红(33%) → 暗紫半透明(53%) → 没 ⇒ 同一时刻整条「头粉尾红」
##   ④ 沿路撒火星 ⑤⑥ 命中: 小爆点 → 圆光团 → 横条 + 星芒 → 余火往上舔 / 碎片蹦 / 脚下暗烟 ⑦ 弹头碰到即删, 尾迹原地照年龄暗掉
const FIRE_PX := 84.0            ## 弹头连火舌的长度(世界码)
const FIRE_TRAIL_W := 22.0
const FIRE_TRAIL_LIFE := 0.4
const FIRE_EMBER_GAP := 55.0     ## 每飞多少码撒一簇火星
const FIRE_TRAIL_GRAD := [[0.0, Color(1.0, 0.82, 0.92, 0.95)], [0.15, Color(1.0, 0.5, 0.78, 0.95)], [0.33, Color(0.95, 0.24, 0.14, 0.85)],
	[0.53, Color(0.42, 0.1, 0.34, 0.5)], [1.0, Color(0.3, 0.05, 0.25, 0.0)]]
func fire_launch(u: Dictionary, tgt: Dictionary):
	_anim("fire-cast", Vector2(u["pos"]), 52.0, 0.18, 0.02, false, false, Color.WHITE, u)
	var s := _arc_launch("fire-head", u, tgt, FIRE_PX, 0, 1, Color.WHITE, FIRE_TRAIL_W, 0.0, GLOW_TRAIL_TEX)
	if s != null:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED   # 建出来这一帧就定(直播只在建点录这一项); 朝向每步在 _arc_step 里按路径转
		s.set_meta("orient", true)
		s.set_meta("trail_life", FIRE_TRAIL_LIFE)
		s.set_meta("trail_grad", FIRE_TRAIL_GRAD)
		s.set_meta("embers", true)
		_orient_to(s, Vector2(tgt["pos"]) - Vector2(u["pos"]))
	return s


func fire_land(node, tgt: Dictionary) -> void:
	_fly_end(node)   # 弹头碰到即消失; 尾段各自照年龄淡完
	_anim("fire-hit3", Vector2(tgt["pos"]), 132.0, 0.6, 0.02, false, false, Color.WHITE, tgt)


## 飞行物朝向: 面朝镜头, 绕视线转到「屏幕上的前进方向」(贴图里弹头朝右)
func _orient_screen(s: Sprite3D, v3: Vector3) -> void:
	var cam = battle.get("_cam")
	if not is_instance_valid(cam) or not (cam is Camera3D):
		return
	var cb: Basis = (cam as Camera3D).global_transform.basis
	var vx: float = v3.dot(cb.x)
	var vy: float = v3.dot(cb.y)
	if vx * vx + vy * vy < 0.0000001:
		return
	s.global_transform = Transform3D(cb * Basis(Vector3(0, 0, 1), atan2(vy, vx)), s.global_transform.origin)


func _orient_to(s: Sprite3D, d2: Vector2) -> void:
	_orient_screen(s, battle._world_pos(d2, 0.0) - battle._world_pos(Vector2.ZERO, 0.0))


# ═══════════════════════════════ 125 禁咒全书: 飞书 ═══════════════════════════════
## 11-25 用户「身上出现一个飞书…一个大一点的、比较好看一点的飞书, 然后下次普攻之后, 这个飞书就直接游到这个敌人身上, 碰到敌人的时候就爆炸」:
##   放过技能 ⇒ 携带者身后肩头浮起一本翻开的禁咒书(上下浮动、书页一开一合); 下一次攻击 ⇒ 就是这本书从肩头飞出去,
##   拖一条品红光尾、走一条略鼓的弧线, 碰到敌人身体(结算侧按速度追身体, 同一个 k)那一刻炸开。原来的三枚红符文删掉。
##   (书 = PixelLab 生成的一张 64×64 图; 浮动 / 开合是引擎里按时间摆位置 / 横向缩放, 不是逐帧画的)
const FORB_TEX := "vfx/magic-forbook-anim.png"   ## 8 帧循环: 书页一开一合、符文亮暗(PixelLab animate_image, 11-25)
const FORB_PX := 74.0            ## 书的显示大小(世界码; 52 时录出来只是肩后一小块, 11-25 录像自查)
const FORB_SIDE := 46.0          ## 浮在身后多远(码)
const FORB_BULGE := 0.62        ## 弧线外鼓程度(控制点离连线的距离 / 直线距离; 羁绊飞弹两侧那几枚约 0.5~0.7)
var _forb_n := 0
const FORB_TRAIL_TEX := "vfx/magic-forb-trail.png"
var _books: Array = []           ## 浮在身边的书 {u, node}


func _book_node(u: Dictionary) -> Sprite3D:
	var t: Texture2D = _load(FORB_TEX)
	if t == null:
		return null
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 11
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.hframes = 8
	s.pixel_size = (FORB_PX * float(battle.WS)) / float(t.get_height())   # 8 帧横条, 单帧 64 方
	battle._world.add_child(s)
	return s


func _book_hover_pos(u: Dictionary, t: float) -> Vector3:
	var back: float = -1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else 1.0
	return battle._world_pos(Vector2(u["pos"]) + Vector2(back * FORB_SIDE, 0.0), body_h(u) + 0.55 + 0.09 * sin(t * 2.4))


func forb_ready(u: Dictionary, on: bool) -> void:
	for i in range(_books.size() - 1, -1, -1):
		if is_same(_books[i]["u"], u):
			if is_instance_valid(_books[i]["node"]):
				(_books[i]["node"] as Node3D).queue_free()
			_books.remove_at(i)
	if not on or not _ok():
		return
	var s := _book_node(u)
	if s == null:
		return
	s.position = _book_hover_pos(u, float(battle._t))
	s.scale = Vector3(0.2, 0.2, 1.0)   # 浮起时从小长大(tick 里 0.25 秒长到原大)
	_books.append({"u": u, "node": s, "t": 0.0})


func _tick_books(delta: float) -> void:
	var t := float(battle._t)
	for i in range(_books.size() - 1, -1, -1):
		var r: Dictionary = _books[i]
		var s = r["node"]
		var u: Dictionary = r["u"]
		if not is_instance_valid(s) or not u.get("alive", false):
			if is_instance_valid(s):
				(s as Node3D).queue_free()
			_books.remove_at(i)
			continue
		r["t"] = float(r["t"]) + delta
		var grow: float = minf(1.0, float(r["t"]) / 0.25)
		(s as Sprite3D).position = _book_hover_pos(u, t)
		(s as Sprite3D).scale = Vector3(grow, grow, 1.0)
		(s as Sprite3D).frame = int(t * ANIM_FPS) % 8   # 书页一开一合(逐帧动画)


## 下一次攻击: 就是身边那本书飞出去(从它浮着的位置起飞); 没浮着(演出层后建 / 直播中途进)就从肩头新建一本
func forb_launch(u: Dictionary, tgt: Dictionary):
	if not _ok():
		return null
	var start: Vector3 = _book_hover_pos(u, float(battle._t))
	var s := _book_node(u)
	if s == null:
		return null
	s.position = start
	var a := Vector2(u["pos"])
	var b := Vector2(tgt["pos"])
	var d := b - a
	var L: float = maxf(1.0, d.length())
	s.set_meta("h", body_h(u) + 0.55)
	s.set_meta("from", a)
	_forb_n += 1
	var side: float = 1.0 if _forb_n % 2 == 0 else -1.0
	s.set_meta("ctrl_off", d * 0.2 + Vector2(-d.y, d.x) / L * L * FORB_BULGE * side)   # 跟羁绊飞弹一样: 先朝一侧甩出去、走一条大弧再拐进敌人(11-25 用户「这个弹道太直了吧，希望做成飞弹那样」); 左右轮换
	s.set_meta("trail_col", Color(1, 1, 1, 0.92))
	s.set_meta("trail_w", 18.0)
	s.set_meta("trail_tex", FORB_TRAIL_TEX)
	s.set_meta("book", true)
	_flies.append(s)
	return s


func forb_land(node, tgt: Dictionary) -> void:
	_fly_end(node)
	_anim("forbidden-blast", Vector2(tgt["pos"]), 200.0, 0.75, 0.02, false, false, Color.WHITE, tgt)


func bolt_step(node, _from2: Vector2, p2: Vector2, to2: Vector2, k: float) -> void:
	if node is Sprite3D and is_instance_valid(node) and (node as Sprite3D).has_meta("ctrl_off"):
		_arc_step(node, to2, k)   # 117 学徒笔记 / 119 火球 / 125 飞书走弧线 + 光尾
	else:
		_fly_to(node, p2)


# ═══════════════════════════════ 释放技能时 ═══════════════════════════════

func scroll_shield(u: Dictionary) -> void:
	_follow("scroll-shield", u, 125.0, 4.0, body_h(u))   # 环要把整只龟圈在里面才像护盾(80 时像一圈细箍压在身上, 11-25 录像自查)


## 120 冰霜新星(11-25 第三版, 贴冰雪墨菲特 E 展示视频逐帧做; 研究 docs/studies/20261125-参考-冰雪墨菲特E与R.md, 分段表见方案书附录):
##   贴地一张: 亮圈 3 帧胀到半径 r + 里面冰火圆盘 + 毛刺环 + 雾 → 压暗区留到 1.1 秒 + 圆心冻印 1.2 秒后淡掉(亮圈半径 92 像素 / 内容直径 194);
##   圆面上撒几簇细冰条「站起来」再碎、碎冰上抛落地。第二版的「一圈圈大冰刺破土」是大招 R 的东西, 撤掉。
const FROST_SHARDS := [[0.0, 0.0, 0.0], [0.45, 0.4, 0.04], [0.5, 2.3, 0.05], [0.42, 4.1, 0.06], [0.75, 1.2, 0.08], [0.8, 3.0, 0.09],
	[0.72, 5.0, 0.1], [0.62, 5.9, 0.07], [0.3, 3.2, 0.03]]   ## [半径比例, 角度(弧度), 延迟秒]
const FROST_SHARD_PX := 78.0   ## 48 时录出来只是几粒白点(11-25 录像自查)
func frost_nova(c: Vector2, r: float) -> void:
	var g := _anim("frost-e", c, r * 2.0 * 194.0 / 184.0, 1.3, 0.05, false, false, Color.WHITE, "ground")
	if g != null:
		g.render_priority = -1   # 贴地的一层画在单位底下(参考里墨菲特站在圈上); 不做深度测试照旧(下半张不被地面挡)
	for sh in FROST_SHARDS:
		var p: Vector2 = c + Vector2(cos(float(sh[1])), sin(float(sh[1]))) * r * float(sh[0])
		_later(float(sh[2]), func() -> void:
			_anim("frost-shard", p, FROST_SHARD_PX, 0.6, 0.05, false, false, Color.WHITE, "ground"))


func storm_bolt(o: Dictionary) -> void:
	var s := _anim("storm-bolt", Vector2(o["pos"]), 300.0, 0.5, 0.05, false, false)   # 300 码高: 从画面上方劈下来
	if s != null:
		## 锚点在闪电落地点(贴图第 110 行): 落点放在敌人脚下
		s.position = battle._world_pos(Vector2(o["pos"]), 0.05)
		s.no_depth_test = true
		s.render_priority = 10


## 122 持续回复(11-25 第二版, 用户「别搞这种环…回血是应该是人物的这个胸部去冒这种绿光、绿粒子特效」):
##   胸口一团绿光一明一暗地脉动, 绿色光点 / 小加号从胸口往上飘; 跟着人走, 回复多久就亮多久。
func holy_mark(o: Dictionary, sec: float) -> void:
	_follow("holy-chest", o, 105.0, sec, body_h(o) * 1.1)   # 66 码时录出来胸口只有一粒绿点、上飘的光点几乎看不见(11-25 录像自查)


func tome_hp(u: Dictionary, _sec: float) -> void:
	_anim("tome-hp", Vector2(u["pos"]), 60.0, 0.45, 0.02, false, false, Color.WHITE, u)


## 124 镜像魔典(11-25 第二版, 用户「你这个就在角色身上贴个这个法阵贴图嘛？你太敷衍了」):
##   像镜子里走出一个自己 —— 拷一份携带者当前的立绘帧, 染成半透明紫色, 从身上往身后滑出一步、越来越实;
##   到「再放一次」那一刻分身闪白、碎成紫色镜片往外飞(镜片碎裂特效), 分身随即淡掉。没有贴在身上的法阵。
const MIRROR_SLIDE := 85.0       ## 分身往身后滑多远(码; 52 时录出来分身大半叠在本体和本体的技能特效后面, 11-25 录像自查)
const MIRROR_COL := Color(0.62, 0.38, 1.0, 0.0)
var _clones: Array = []          ## {node, u, t, delay, back}


func mirror_echo(u: Dictionary, delay: float) -> void:
	if not _ok():
		return
	var src = u.get("sprite")
	if not is_instance_valid(src) or not (src is Sprite3D):
		return
	var o: Sprite3D = src
	var s := Sprite3D.new()
	_copy_look(o, s)
	s.centered = o.centered
	s.billboard = o.billboard
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.render_priority = 12
	s.no_depth_test = true   # 分身画在本体技能特效前面(否则被挡住看不见)
	s.modulate = MIRROR_COL
	battle._world.add_child(s)
	s.global_position = o.global_position
	var back: float = -1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else 1.0
	_clones.append({"node": s, "u": u, "t": 0.0, "delay": delay, "back": back, "y0": o.global_position.y - battle._world_pos(Vector2(u["pos"]), 0.0).y})


func _copy_look(o: Sprite3D, s: Sprite3D) -> void:
	if s.texture != o.texture:
		s.texture = o.texture
	if s.hframes != o.hframes:
		s.hframes = o.hframes
	if s.vframes != o.vframes:
		s.vframes = o.vframes
	s.region_enabled = o.region_enabled
	s.region_rect = o.region_rect
	s.frame = mini(o.frame, s.hframes * s.vframes - 1)
	s.flip_h = o.flip_h
	s.offset = o.offset
	s.pixel_size = o.pixel_size


func _tick_clones(delta: float) -> void:
	for i in range(_clones.size() - 1, -1, -1):
		var r: Dictionary = _clones[i]
		var s = r["node"]
		if not is_instance_valid(s):
			_clones.remove_at(i)
			continue
		r["t"] = float(r["t"]) + delta
		var t: float = float(r["t"])
		var dl: float = float(r["delay"])
		var u: Dictionary = r["u"]
		var k: float = clampf(t / dl, 0.0, 1.0)
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢地滑出
		var base := Vector2(u["pos"]) + Vector2(float(r["back"]) * MIRROR_SLIDE * e, 0.0)
		(s as Sprite3D).global_position = battle._world_pos(base, 0.0) + Vector3(0, float(r["y0"]), 0)
		var src = u.get("sprite")
		if is_instance_valid(src) and src is Sprite3D:
			_copy_look(src, s)   # 分身跟本体同一个动作(本体换动作表时一起换)
		if t < dl:
			(s as Sprite3D).modulate = Color(MIRROR_COL.r, MIRROR_COL.g, MIRROR_COL.b, 0.35 + 0.55 * e)
		else:
			if not r.get("burst", false):
				r["burst"] = true
				_anim("mirror-shatter", base, 96.0, 0.6, 0.02, false, false, Color.WHITE, u)   # on = 单位 ⇒ 炸在分身的身体中段
			var q: float = clampf((t - dl) / 0.3, 0.0, 1.0)
			(s as Sprite3D).modulate = Color(1.0, 0.9, 1.0, 0.9 * (1.0 - q)) if q < 0.35 else Color(MIRROR_COL.r, MIRROR_COL.g, MIRROR_COL.b, 0.75 * (1.0 - q))
			if q >= 1.0:
				(s as Node3D).queue_free()
				_clones.remove_at(i)


## 跟着单位走的循环特效(护盾环 / 持续回复 / 再放法阵 / 装填标记)
func _follow(key: String, u: Dictionary, world_d: float, life: float, h: float) -> Sprite3D:
	var s := _anim(key, Vector2(u["pos"]), world_d, life, h, false, true)
	if s == null:
		return null
	s.position = battle._world_pos(Vector2(u["pos"]), h)
	s.no_depth_test = true
	s.render_priority = 10
	for f in _fx:
		if f.get("node") == s:
			f["kind"] = "anim_follow"
			f["tgt"] = u
	return s


# ═══════════════════════════════ 123 骷髅 ═══════════════════════════════

func skel_rise(p: Dictionary, _kind: String) -> void:
	_anim("skel-rise", Vector2(p["pos"]), 90.0, 0.7, 0.05, false, false, Color.WHITE, "ground")


func skel_crumble(p: Dictionary) -> void:
	_anim("skel-crumble", Vector2(p["pos"]), 80.0, 0.65, 0.02, false, false, Color.WHITE, p)


func skm_blast(_p: Dictionary, c: Vector2, r: float) -> void:
	_anim("skel-blast", c, r * 1.5, 0.55, 0.05, false, false, Color.WHITE, "ground")   # 内容直径按 1.5 × 半径: 火团最大时盖住范围内的人, 后半段烟团不至于糊满屏(11-25 录像自查)


func wave_launch(p: Dictionary, _dir: Vector2):
	var s := _anim("skel-wave", Vector2(p["pos"]), 90.0, 60.0, 0.05, false, true)
	if s == null:
		return null
	s.no_depth_test = true
	s.render_priority = 10
	s.set_meta("h", 0.05 + 70.0 * 0.5 * s.pixel_size)
	s.position = battle._world_pos(Vector2(p["pos"]), float(s.get_meta("h")))
	_flies.append(s)
	return s


func wave_step(node, b: Vector2, _dir) -> void:
	_fly_to(node, b)


func wave_end(node) -> void:
	_fly_end(node)


func wave_hit(o: Dictionary) -> void:
	_anim("wave-hit", Vector2(o["pos"]), 56.0, 0.35, 0.02, false, false, Color.WHITE, o)


func wave_heal(o: Dictionary) -> void:
	_anim("wave-heal", Vector2(o["pos"]), 44.0, 0.35, 0.02, false, false, Color.WHITE, o)


# ═══════════════════════════════ 126 浮空魔典 · 书页 ═══════════════════════════════

## 11-25 第二版(用户「书页一样的，太敷衍了…转速这么快吗？」): 书页 = PixelLab 生成的一张带青色符文的书页图(64×64);
##   飞的时候横向一缩一放(纸页扑扇, 每张相位错开), 近战绕身转得慢(角速度在结算侧 EqMagicBatch.PAGE_W), 身后拖一条青色细光尾;
##   远程在身后扇形叠着、上下轻浮; 挡下一击时最上面那张飞到身前、亮一下碎成纸片(书页格挡特效)。
const PAGE_TRAIL_COL := Color(0.55, 1.0, 0.95, 0.55)
const PAGE_TRAIL_W := 7.0
var _page_fly: Array = []        ## 远程挡刀时飞到身前的那张 {node, u, t, from, to}


func _page_node(t: Texture2D) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.hframes = 8
	s.pixel_size = (PAGE_PX * float(battle.WS)) / float(t.get_height())   # 8 帧横条, 单帧 64 方
	battle._world.add_child(s)
	return s


func pages_spawn(u: Dictionary, ck: String, n: int, melee: bool) -> void:
	if not _ok():
		return
	var t: Texture2D = _load(PAGE_TEX)
	if t == null:
		return
	var nodes: Array = []
	for i in range(n):
		var s := _page_node(t)
		s.position = battle._world_pos(Vector2(u["pos"]), PAGE_ORBIT_H)
		nodes.append(s)
	_pages.append({"u": u, "ck": ck, "melee": melee, "nodes": nodes})


func _page_acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_magic_acc", {})
	return float(d.get(key, 0.0))


func _back_of(u: Dictionary) -> float:
	return -1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else 1.0


func _tick_pages() -> void:
	var t := float(battle._t)
	for i in range(_pages.size() - 1, -1, -1):
		var g: Dictionary = _pages[i]
		var u: Dictionary = g["u"]
		var nodes: Array = g["nodes"]
		if not u.get("alive", false):
			for s in nodes:
				if is_instance_valid(s):
					(s as Node3D).queue_free()
			_pages.remove_at(i)
			continue
		var n: int = nodes.size()
		var c := Vector2(u["pos"])
		if bool(g["melee"]):
			## 近战: 按批系统里的角度绕身转(结算判定用同一个角度、同一个半径 ⇒ 画面上碰到身体才挨打)
			var ang: float = _page_acc(u, "pang:" + str(g["ck"]))
			for j in range(n):
				var s: Sprite3D = nodes[j]
				var th: float = ang + TAU * float(j) / float(n)
				var p := c + Vector2(cos(th), sin(th)) * EqMagicBatch.PAGE_R
				var prev: Vector3 = s.position
				s.position = battle._world_pos(p, PAGE_ORBIT_H + 0.1 * sin(t * 3.0 + float(j) * 1.7))
				s.frame = (int(t * ANIM_FPS) + j * 3) % 8   # 纸页在空中翻转(逐帧动画, 每张错开相位)
				if prev.distance_to(s.position) < 1.5:
					_trail_seg(prev, s.position, PAGE_TRAIL_COL, PAGE_TRAIL_W)
		else:
			## 远程: 身后扇形叠着现有的张数(用掉一张少一张, 长回来再出现)
			var have: int = int(_page_acc(u, "pages:" + str(g["ck"])))
			var back: float = _back_of(u)
			for j in range(n):
				var s: Sprite3D = nodes[j]
				s.visible = j < have
				var p := _page_stack_pos(u, j, n, back, t)
				s.position = p
				s.frame = (int(t * ANIM_FPS * 0.6) + j * 2) % 8


func _page_stack_pos(u: Dictionary, j: int, n: int, back: float, t: float) -> Vector3:
	var fan: float = (float(j) - float(n - 1) * 0.5)
	var p := Vector2(u["pos"]) + Vector2(back * (40.0 + 9.0 * absf(fan)), 0.0)
	return battle._world_pos(p, body_h(u) + 0.35 + fan * 0.22 + 0.06 * sin(t * 2.0 + float(j)))


func page_cut(o: Dictionary) -> void:
	_anim("page-cut", Vector2(o["pos"]), 52.0, 0.3, 0.02, false, false, Color.WHITE, o)


func page_block(u: Dictionary, ck: String, absorbed: float = 0.0) -> void:
	## 最上面那张(刚用掉的那一张, 下标 = 现有张数)从身后飞到身前, 0.16 秒到位后亮一下、碎成纸片
	if _ok():
		var t: Texture2D = _load(PAGE_TEX)
		if t != null:
			var n: int = 1
			for g in _pages:
				if is_same(g["u"], u) and str(g["ck"]) == ck:
					n = (g["nodes"] as Array).size()
			var have: int = int(_page_acc(u, "pages:" + ck))
			var s := _page_node(t)
			s.render_priority = 12
			var back: float = _back_of(u)
			s.position = _page_stack_pos(u, mini(have, n - 1), n, back, float(battle._t))
			var to3: Vector3 = battle._world_pos(Vector2(u["pos"]) + Vector2(-back * 44.0, 0.0), body_h(u) + 0.15)
			_page_fly.append({"node": s, "u": u, "t": 0.0, "from": s.position, "to": to3, "ab": absorbed})
	## 伤害飘字照常显示格挡前的数(同护盾口径) ⇒ 另跳一个「格挡 N」, 看得出书页吃掉了多少(11-25 录像自查)
	if absorbed >= 1.0 and battle.get("_vfx") != null:
		battle._vfx._float_text(Vector2(u["pos"]) + Vector2(0, -70), "格挡 %d" % int(round(absorbed)), Color("#f2e6c0"))


const PAGE_FLY_SEC := 0.16
func _tick_page_fly(delta: float) -> void:
	for i in range(_page_fly.size() - 1, -1, -1):
		var r: Dictionary = _page_fly[i]
		var s = r["node"]
		if not is_instance_valid(s):
			_page_fly.remove_at(i)
			continue
		r["t"] = float(r["t"]) + delta
		var q: float = clampf(float(r["t"]) / PAGE_FLY_SEC, 0.0, 1.0)
		(s as Sprite3D).position = (r["from"] as Vector3).lerp(r["to"], 1.0 - (1.0 - q) * (1.0 - q))
		(s as Sprite3D).scale = Vector3(1.0 + 0.5 * q, 1.0 + 0.5 * q, 1.0)   # 挡到身前时放大、正对来势
		(s as Sprite3D).modulate = Color(1.0 + q, 1.0 + q, 1.0 + q, 1.0)
		if q >= 1.0:
			var u: Dictionary = r["u"]
			_anim("page-block", Vector2(u["pos"]) + Vector2(-_back_of(u) * 44.0, 0.0), 70.0, 0.34, 0.02, false, false, Color.WHITE, u)
			(s as Node3D).queue_free()
			_page_fly.remove_at(i)


func page_regen(_u: Dictionary, _ck: String, _n: int) -> void:
	pass   # 张数一变, _tick_pages 下一帧就把那张显示出来


# ═══════════════════════════════ 123 亡者之书 · 骷髅技能动作 ═══════════════════════════════

## 技能动作帧条(112 方帧, 与待机同贴地线); 出招帧 = SKEL_SKILL_HIT(从 0 数), 帧率 = 出招帧 / 前摇秒数 ⇒ 出招帧落在结算那一刻
const SKEL_SKILL := {
	"skel_warrior": "res://assets/sprites/vfx/eq-skelw-skill.png",
	"skel_mage": "res://assets/sprites/vfx/eq-skelm-skill.png",
	"skel_priest": "res://assets/sprites/vfx/eq-skelp-skill.png",
}
const SKEL_SKILL_HIT := {"skel_warrior": 2, "skel_mage": 3, "skel_priest": 3}   # 抄自 pack_magic_art.py SKEL_HIT(怒吼 / 火团最大 / 双手前推)
static var _ssd := {}


func _skel_sd(kind: String, fps: float) -> Dictionary:
	if not _ssd.has(kind):
		var path: String = SKEL_SKILL.get(kind, "")
		var sd := {}
		if path != "" and ResourceLoader.exists(path):
			var tx: Texture2D = load(path)
			sd = battle._sprite_dict_from(tx, {"frames": tx.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 800}, false)
		_ssd[kind] = sd
	var out: Dictionary = (_ssd[kind] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func skel_cast(p: Dictionary, kind: String, windup: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _skel_sd(kind, float(SKEL_SKILL_HIT.get(kind, 4)) / maxf(0.05, windup))
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "skel_" + kind, true)


# ═══════════════════════════════ 生命周期 ═══════════════════════════════

func tick(delta: float) -> void:
	super.tick(delta)
	_tick_pages()
	_tick_page_fly(delta)
	_tick_books(delta)
	_tick_clones(delta)
	_tick_trail(delta)


func clear() -> void:
	super.clear()
	for s in _flies:
		if is_instance_valid(s):
			(s as Node3D).queue_free()
	_flies.clear()
	for g in _pages:
		for s in g["nodes"]:
			if is_instance_valid(s):
				(s as Node3D).queue_free()
	_pages.clear()
	for arr in [_books, _clones, _page_fly]:
		for r in arr:
			if is_instance_valid(r["node"]):
				(r["node"] as Node3D).queue_free()
		arr.clear()
	for r in _trail:
		if is_instance_valid(r["node"]):
			(r["node"] as Node3D).queue_free()
	_trail.clear()
