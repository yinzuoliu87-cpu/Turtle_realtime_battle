class_name BombEqVfx
extends RefCounted
## bomb_eq_vfx.gd —— 炸弹羁绊【导弹轰炸】+ 炸弹 10 件 + 武士刀 的演出层（2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md）
##
## ★只管画，不管结算：结算全在 EqBombBatch / BombSynergySystem，本文件一个伤害都不发；没有它（无头 / 门禁）照样结算。
## ★不用 tween：生命周期全由 `tick(delta)` 推进（CLAUDE.md §4.5），EqBombBatch.tick 每步调一次。
## 素材（如实）：assets/sprites/vfx/bomb-*.png / katana-*.png 来自 PixelLab 特效工作台的预设 / 部件渲染（改过配色），
##   由 tools/assetgen/pack_bomb_vfx.py 切成横条；挂在身上的倒计时小图直接用该装备自己的图标。
##   龙卷风是程序画的（叠起来的细环，按高度变大、各自绕圈）。
##
## 尺寸口径：每张特效表登记「内容实际覆盖的像素直径」(FILL) ⇒ 世界大小 = 伤害直径，不靠目测系数。

const SPRITE_DIR := "res://assets/sprites/"
## 特效表：名 → [路径, 帧宽, 帧高, 内容直径(像素), 锚点 x, 锚点 y]（锚点 = 爆点 / 落点在帧里的位置）
const SHEETS := {
	"std": ["vfx/bomb-blast-std.png", 96, 96, 72.0, 48, 60],
	"big": ["vfx/bomb-blast-big.png", 224, 216, 160.0, 112, 172],
	"goo": ["vfx/bomb-goo-puddle.png", 132, 66, 104.0, 66, 60],
	"wave": ["vfx/katana-wave.png", 96, 96, 70.0, 48, 48],
	"pop": ["vfx/bomb-cracker-pop.png", 64, 64, 44.0, 32, 32],
	"smoke": ["vfx/bomb-smoke-cloud.png", 148, 80, 121.0, 74, 74],
	"missile": ["vfx/bomb-missile-strike.png", 132, 151, 64.0, 55, 128],
	"carpet": ["vfx/bomb-missile-carpet.png", 62, 53, 56.0, 32, 31],     # 羁绊导弹铺满全场的爆炸(11-25 特效工作台 cartoon_boom, 不带烟球)
	"drop": ["vfx/missile-drop.png", 72, 72, 40.0, 36, 60],             # 竖直下落的导弹(锚点 = 弹头)
	"laser": ["vfx/missile-laser.png", 24, 256, 24.0, 12, 256],         # 天降瞄准激光(show_locator 自己摆, 不走 _anim)
	"reticle": ["vfx/missile-reticle.png", 128, 128, 120.0, 64, 64],    # 地面靶心(同上)
	"zone": ["vfx/missile-zone.png", 256, 256, 256.0, 128, 128],        # 打击范围 = 整座岛(同上, _board_zone 自己摆)
	"crackle": ["vfx/bomb-tube-crackle.png", 83, 92, 77.0, 41, 46, 2],   # 第 7 项 = 跳过开头几帧(前两帧是一团白闪, 放大后像个白球盖住单位)
	"boom": ["vfx/bomb-barrel-boom.png", 56, 60, 50.0, 30, 37],
	"muzzle": ["vfx/bomb-cannon-muzzle.png", 35, 20, 28.0, 3, 10],
	"charge": ["vfx/katana-charge.png", 67, 67, 61.0, 33, 33],
	## 107 龙卷风(11-25 Blender 建模渲的 16 帧循环, tools/assetgen/blender_katana_tornado.py): 锚点 = 漏斗底(地面); 内容宽 123 像素(含摆动和底部扬尘)
	"tornado": ["vfx/katana-tornado.png", 192, 192, 123.0, 96, 131],
	## 107 普攻横斩刀光(11-25 特效工作台 slash_trail 压扁成横向): 锚点 = 弧心
	"hslash": ["vfx/katana-hslash.png", 85, 39, 79.0, 45, 21],
	"spark": ["vfx/bomb-cracker-spark.png", 66, 69, 60.0, 35, 30],
	"paper": ["vfx/bomb-cracker-paper.png", 96, 75, 90.0, 47, 39],
	"mine": ["vfx/bomb-mine-blast.png", 82, 78, 73.0, 41, 39],
	"timer": ["vfx/bomb-timer-blast.png", 82, 80, 75.0, 41, 40],
	"shell": ["vfx/bomb-cannon-shell.png", 74, 28, 60.0, 63, 15],
	"remote": ["vfx/bomb-remote-blast.png", 175, 97, 155.0, 88, 63],   # 106 专属: 锚点 = 地面爆点; 内容宽 = 地面那圈火团铺开后的宽度(第 17~25 帧 150~165 像素)
}
const COL_LOCATOR := Color(1.0, 0.18, 0.12, 0.85)
## 导弹从天上竖直落下要多久(提前这么多秒开播, 弹头砸地 = 结算那一刻)。11-25 用户「导弹移动速度太快了」: 0.45 → 1.4 秒
const MISSILE_LEAD := 1.4

var battle
var _fx: Array = []          ## {node, t, life, kind, ...}
var _mines: Array = []       ## {node, pos}
var _pending: Array = []     ## 延时出场的演出 {t, fn}(鞭炮一串连炸)
var _crack_n := 0            ## 鞭炮第几串(每串转一个角度, 不每次一模一样)
static var _tex := {}


func _init(b) -> void:
	battle = b


## 单位「真正的身体中心」世界高度(11-24 用户「又是在头上吗」): 不按整帧高度的一半算 —— 立绘帧上方有大片透明留白
##   (小将 192 像素高的帧里只有 77~176 行有画), 一半落在头上。⇒ 量这张贴图第一帧有画部分的上下边界取正中, 按贴图缓存。
static var _body_cache := {}
static func body_h(u) -> float:
	if not (u is Dictionary):
		return 1.0
	var sp = (u as Dictionary).get("sprite", null)
	if not is_instance_valid(sp) or not (sp is Sprite3D) or (sp as Sprite3D).texture == null:
		return GunEqVfx.body_mid_h(u)
	var s3: Sprite3D = sp
	var tex: Texture2D = s3.texture
	var fw: int = tex.get_width() / maxi(1, s3.hframes)
	var fh: int = tex.get_height() / maxi(1, s3.vframes)
	var key: String = "%s|%d|%d" % [str(tex.get_rid().get_id()), fw, fh]
	if not _body_cache.has(key):
		var img: Image = tex.get_image()
		var mid: float = float(fh) * 0.5
		if img != null:
			if img.is_compressed():
				img.decompress()
			var used: Rect2i = img.get_region(Rect2i(0, 0, fw, fh)).get_used_rect()
			if used.size.y > 0:
				mid = float(used.position.y) + float(used.size.y) * 0.5
		_body_cache[key] = mid
	var row: float = float(_body_cache[key])
	## 居中的 Sprite3D: 第 row 行(从顶数)的局部高度 = (帧高/2 − row) + offset.y(像素)
	return s3.global_position.y + ((float(fh) * 0.5 - row) + s3.offset.y) * s3.pixel_size * s3.scale.y


## 飞行物朝向(11-24 用户「弹道方向你觉得？弹道你到底怎么做的」): 贴图里飞行物都画成「朝右飞」;
##   每帧把「这一刻」和「下一瞬」的位置投到屏幕上, 按屏幕上真实的运动方向把贴图转过去(面朝镜头、绕视线转)
##   ⇒ 斜着飞时头朝前、走弧线时先抬头后低头, 尾焰 / 烟尾永远拖在后面。原来只会左右翻, 斜飞时是一根横棍在滑。
func _orient(s: Sprite3D, a3: Vector3, b3: Vector3) -> void:
	var cam = battle.get("_cam")
	if not (cam is Camera3D) or not is_instance_valid(cam):
		return
	var d: Vector2 = (cam as Camera3D).unproject_position(b3) - (cam as Camera3D).unproject_position(a3)
	if d.length() < 0.01:
		return
	s.flip_h = false
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.global_transform.basis = (cam as Camera3D).global_transform.basis * Basis(Vector3(0, 0, 1), atan2(-d.y, d.x))


func _ok() -> bool:
	return battle != null and battle.get("_world") != null and is_instance_valid(battle._world)


func _load(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var p: String = SPRITE_DIR + str(SHEETS[key][0]) if SHEETS.has(key) else SPRITE_DIR + key
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex[key] = t
	return t


## 播一张特效表：`world_d` = 想让内容覆盖的世界直径（码）；`flat` = 贴地（俯视盘面）
## `on` = 炸在哪个单位身上(给了就把爆点放在它的身体中段、且不被地面遮挡; 不给 = 落在地上的爆炸, 下沿贴地)
func _anim(key: String, pos: Vector2, world_d: float, life: float, h: float = 0.02, flat: bool = false, loop: bool = false, tint: Color = Color.WHITE, on = null) -> Sprite3D:
	if not _ok():
		return null
	var t: Texture2D = _load(key)
	if t == null:
		return null
	var row: Array = SHEETS[key]
	var fw: int = int(row[1])
	var fh: int = int(row[2])
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = maxi(1, t.get_width() / fw)
	s.frame = 0
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.modulate = tint
	s.pixel_size = (world_d * float(battle.WS)) / float(row[3])
	s.offset = Vector2(float(fw) * 0.5 - float(row[4]), float(row[5]) - float(fh) * 0.5)
	if flat:
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
	else:
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		## ★竖着的特效: 贴图最下沿不能低于地面, 不够就把整张往上抬(用户 11-24「下面被切了一半」——
		##   锚点在帧中间、贴图几米高, 放在离地 0.5 米 ⇒ 下半截埋进地里被地面挡掉)
		if on is String and on == "ground":
			## ★落在地上的爆炸(手雷 / 地雷 / 导弹 / 遥控炸弹): 爆炸中心 = 落地点(地面), 不悬在半空;
			##   火球下半截会低于地面 ⇒ 不做深度测试(不被地面挡), 屏幕上就是以敌人脚下为中心炸开(用户 11-24「爆炸点到底应该在哪」)
			h = 0.05
			s.no_depth_test = true
			s.render_priority = 10
		elif on is Dictionary:
			## ★炸在单位身上: 爆点 = 它的身体中段(用户 11-24「炸弹应该从人物中心爆炸吧」);
			##   这时贴图下半截会低于地面 ⇒ 不做深度测试(不被地面挡), 渲染排在前面
			h = body_h(on)
			s.no_depth_test = true
			s.render_priority = 10
		else:
			## 落在地上的爆炸: 火球(内容直径 row[3])的底部刚好贴地 ⇒ 锚点抬到内容半径的高度
			##   (原来按「整张贴图下沿贴地」抬, 贴图四周有透明边 ⇒ 火球整团飘在半空, 用户 11-24 手雷那段)
			h = maxf(h, float(row[3]) * 0.5 * s.pixel_size)
	s.position = battle._world_pos(pos, h)
	battle._world.add_child(s)
	var skip: int = int(row[6]) if row.size() > 6 else 0
	s.frame = skip
	_fx.append({"node": s, "t": 0.0, "life": life, "kind": "anim", "nf": s.hframes - skip, "skip": skip, "loop": loop})
	return s


func _icon(id: String, pos3: Vector3, px_world: float) -> Sprite3D:
	var t: Texture2D = _load("equip/%s.png" % id)
	if t == null or not _ok():
		return null
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.pixel_size = (px_world * float(battle.WS)) / float(t.get_height())
	s.position = pos3
	battle._world.add_child(s)
	return s


func _ring(pos: Vector2, radius: float, col: Color, life: float) -> void:
	if not _ok():
		return
	var tx: Texture2D = VfxTex._make_thin_ring_tex()
	var s := Sprite3D.new()
	s.texture = tx
	s.shaded = false
	s.transparent = true
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.modulate = col
	s.position = battle._world_pos(pos, 0.05)
	var ps1: float = (radius * 2.0 * float(battle.WS)) / float(tx.get_height())
	s.pixel_size = ps1 * 0.3
	battle._world.add_child(s)
	_fx.append({"node": s, "t": 0.0, "life": life, "kind": "ring", "ps0": ps1 * 0.3, "ps1": ps1, "a0": col.a})


# ═══════════════════════════════ 羁绊：导弹轰炸 ═══════════════════════════════

## ── 11-25 重做(用户「卫星定位器是这么指的吗？…它不是指向天空，然后天空落下一道这个红线吗？」
##   「整个导弹是要轰到覆盖整个棋盘的，所以到底这个特效怎么实现？」) ──
##   原来: 定位器 = 从我方阵地沿地面横拉到中心的一条红线; 落弹 = 中心一张爆炸 + 每个敌人身上一张 ⇒ 看着只炸了中间。
##   现在: ① 开打 → 天上竖直打下一道红色瞄准激光落在中心靶心上, 越接近落弹闪得越快;
##         ② 最后 EDGE_WARN 秒整座岛的边缘亮一圈红色警示线(打击范围 = 整个棋盘);
##         ③ 导弹顺着激光砸下 → 全屏白闪 + 中心大爆炸 → 一圈圈爆炸从中心往外推、CARPET_SEC 秒铺满整座岛 → 每个挨炸的敌人身上再炸一下。
##   贴图: missile-laser / missile-reticle(tools/assetgen/build_missile_marks.py 脚本画) · bomb-missile-carpet(特效工作台)。
const CARPET_STEP := 135.0     # 整座岛按这个间距(码)铺爆炸(11-25 用户「火海太密集了」: 70 → 135, 个数约四分之一)
const CARPET_JITTER := 0.15     # 同一时刻炸开, 各点只差这么一点(看着是一起炸, 不是一个个)


func show_locator(_side: String, fire_at: float) -> void:
	if not _ok():
		return
	var c: Vector2 = battle._arena_center
	## 天降激光: 竖条贴图, 底端落在中心地面, 绕竖轴朝镜头(BILLBOARD_FIXED_Y), 高 12 米
	var lt: Texture2D = _load("laser")
	if lt != null:
		var s := Sprite3D.new()
		s.texture = lt
		s.hframes = 4
		s.shaded = false
		s.transparent = true
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.pixel_size = 12.0 / float(lt.get_height())
		s.offset = Vector2(0.0, float(lt.get_height()) * 0.5)
		s.position = battle._world_pos(c, 0.0)
		s.render_priority = 8
		battle._world.add_child(s)
		_fx.append({"node": s, "t": 0.0, "life": fire_at, "kind": "laser"})
	## 地面靶心(俯视贴图平铺在地上), 慢慢转
	var rt: Texture2D = _load("reticle")
	if rt != null:
		var r := Sprite3D.new()
		r.texture = rt
		r.shaded = false
		r.transparent = true
		r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		r.axis = Vector3.AXIS_Y
		r.position = battle._world_pos(c, 0.06)
		r.pixel_size = (180.0 * float(battle.WS)) / float(rt.get_height())
		battle._world.add_child(r)
		_fx.append({"node": r, "t": 0.0, "life": fire_at, "kind": "reticle", "ps": r.pixel_size, "no_shrink": true})
	## ★打击范围 = 整个棋盘(用户 11-25「范围是整个棋盘，我再跟你说一遍」): 开打就把整座岛铺满红色斜纹危险区, 越接近落弹越亮、闪得越快
	_board_zone(fire_at)


func _board_zone(life: float) -> void:
	if not _ok():
		return
	var tx: Texture2D = _load("zone")
	if tx == null:
		return
	var s := Sprite3D.new()
	s.texture = tx
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.position = battle._world_pos(battle._arena_center, 0.04)
	var a: Vector2 = battle.ARENA.size * 0.5
	s.pixel_size = (a.x * 2.0 * float(battle.WS)) / float(tx.get_width())
	s.scale = Vector3(1.0, 1.0, a.y / a.x)    # 岛是椭圆(ArenaShape N=2): 按两条半轴拉
	battle._world.add_child(s)
	_fx.append({"node": s, "t": 0.0, "life": life, "kind": "board_zone"})


## 导弹顺着激光竖直落下(提前 MISSILE_LEAD 秒开播, 弹头砸地那一刻 = 结算): 从 DROP_H 米高处加速落到中心
const DROP_H := 11.0
func missile_launch(_side: String) -> void:
	var s := _anim("drop", battle._arena_center, 210.0, MISSILE_LEAD, DROP_H, false, true)   # 11-25 用户「导弹大小太小了」: 70 → 210 码
	if s != null:
		s.no_depth_test = true
		s.render_priority = 12
		var f: Dictionary = _fx[_fx.size() - 1]
		f["kind"] = "fall"
		f["at"] = battle._arena_center


## 砸地那一刻: 全屏白闪 → 整座岛同时炸成一片火海(不是从中心往外推: 用户「范围是整个棋盘」) → 每个挨炸的敌人身上再炸一下
func missile_impact(side: String) -> void:
	if not _ok():
		return
	var c: Vector2 = battle._arena_center
	if battle.has_method("_screen_flash_light"):
		battle._screen_flash_light()
	_anim("carpet", c, 380.0, 1.0, 0.02, false, false, Color.WHITE, "ground")
	var a: Vector2 = battle.ARENA.size * 0.5
	var n := 0
	var y := -a.y
	while y <= a.y:
		var x := -a.x
		var row := int(round((y + a.y) / (CARPET_STEP * 0.8)))
		while x <= a.x:
			var o := Vector2(x + (CARPET_STEP * 0.5 if row % 2 == 1 else 0.0), y)
			if (o.x * o.x) / (a.x * a.x) + (o.y * o.y) / (a.y * a.y) <= 1.0:   # 整座岛(椭圆)里每个格点都炸
				var p: Vector2 = c + o
				var sz: float = 100.0 + 30.0 * float((n * 7) % 3) / 2.0   # 火团之间留缝, 不糊成一整片
				_later(CARPET_JITTER * float((n * 5) % 7) / 6.0, func() -> void: _anim("carpet", p, sz, 1.0, 0.02, false, false, Color.WHITE, "ground"))
				n += 1
			x += CARPET_STEP
		y += CARPET_STEP * 0.8
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) != side and not bool(u.get("_isEgg", false)):
			var uu: Dictionary = u
			_anim("carpet", Vector2(uu["pos"]), 140.0, 1.0, 0.02, false, false, Color.WHITE, uu)


# ═══════════════════════════════ 十件装备 ═══════════════════════════════

## 097 鞭炮(11-24 重做, 用户「感觉这个特效不行」→「重做特效」): 一串鞭炮在伤害范围里噼里啪啦连着炸 ——
##   CRACK_N 响在 CRACK_SEC 秒内依次炸开(金角螺旋撒满半径 100 码的圈, 每串转一个角度), 红纸屑往上崩,
##   每个真挨炸的敌人身上补一个小火花(看得出谁被炸到); 地上一圈 = 真实伤害半径。
const CRACK_N := 9
const CRACK_SEC := 0.45
func cracker_burst(c: Vector2, _on = null, hits: Array = []) -> void:
	if not _ok():
		return
	_crack_n += 1
	_ring(c, EqBombBatch.CRACKER_R, Color(1.0, 0.75, 0.3, 1.0), 0.6)
	_anim("paper", c, 210.0, 1.0, 0.02)
	var rot: float = float(_crack_n) * 1.1
	for k in range(CRACK_N):
		var r: float = EqBombBatch.CRACKER_R * 0.85 * sqrt((float(k) + 0.5) / float(CRACK_N))
		var a: float = float(k) * 2.39996 + rot
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
		var hh: float = 0.4 + 0.5 * float((k * 7) % 5) / 4.0
		_later(CRACK_SEC * float(k) / float(CRACK_N), func() -> void: _anim("spark", p, 85.0, 0.45, hh))
	for o in hits:
		if o is Dictionary:
			var oo: Dictionary = o
			_later(0.0, func() -> void: _anim("spark", Vector2(oo["pos"]), 105.0, 0.45, 1.0, false, false, Color.WHITE, oo))


func _later(sec: float, fn: Callable) -> void:
	if sec <= 0.0:
		fn.call()
	else:
		_pending.append({"t": sec, "fn": fn})


func tube_blast(c: Vector2, r: float, on = null) -> void:
	_anim("crackle", c, r * 2.0, 1.0, 0.6, false, false, Color.WHITE, on)
	_ring(c, r, Color(1.0, 0.55, 0.2, 0.7), 0.35)


func grenade_throw(from: Vector2, to: Vector2, fly: float) -> void:
	var s := _icon("p2eq_099", battle._world_pos(from, 1.0), 42.0) if _ok() else null
	if s != null:
		_fx.append({"node": s, "t": 0.0, "life": fly, "kind": "arc", "from": from, "to": to, "h": 2.2})


## 火球固定 150 码大(约 3.6 米, 比单位高一些), 底部贴地; 伤害范围(半径 160 码)由地上一圈标出 ——
##   原来火球按伤害直径缩放成 7.7 米一大团飘在头顶(用户 11-24 看片)
## 手雷(11-24 用户「范围也没覆盖到啊」→ 重做): 爆炸要盖满整个伤害范围(半径 160 码) ——
##   ① 贴地火焰冲击: 爆炸贴图躺平铺在地上, 直径 = 伤害直径, 从落地点往外扩散到圈边;
##   ② 中心一团往上冒的火球(以落地点为中心);
##   ③ 破片火星四散飞到圈边(手雷的特征);  ④ 地上的范围圈。
func grenade_blast(c: Vector2, r: float) -> void:
	_anim("std", c, r * 2.0, 0.7, 0.04, true)
	_anim("std", c, 170.0, 0.7, 0.05, false, false, Color.WHITE, "ground")
	for k in range(8):
		var a: float = float(k) * TAU / 8.0 + 0.3
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * r * 0.85
		_later(0.08 + 0.02 * float(k % 3), func() -> void: _anim("spark", p, 60.0, 0.35, 0.3))
	_ring(c, r, Color(1.0, 0.6, 0.25, 0.95), 0.6)


## 烟雾: 从地面升起、罩住范围里的单位(不被地面 / 单位挡), 烟本身半透明 ⇒ 透过烟看得到里面潜行的人
##   (原来被「底部贴地」规则整团抬到半空, 用户 11-24 看片前自查抓到)
func smoke_cloud(c: Vector2, r: float, sec: float) -> void:
	var s := _anim("smoke", c, r * 2.0, sec + 0.8, 0.05, false, false, Color(1, 1, 1, 0.55), "ground")
	_ring(c, r, Color(0.75, 0.8, 0.9, 0.9), 0.8)


func smoke_strike(pos: Vector2, on = null) -> void:
	_anim("pop", pos, 120.0, 0.3, 0.6, false, false, Color(0.85, 0.9, 1.0), on)


## 粘弹(11-24 自查): 从携带者手里丢出一道弧线 → 粘到目标头顶(图标放大、越近引爆越闪) + 「减速」飘字
const STICKY_FLY := 0.35
func sticky_attach(tgt: Dictionary, fuse: float, from = null) -> void:
	if not _ok():
		return
	if from is Dictionary:
		var s := _icon("p2eq_101", battle._world_pos(Vector2(from["pos"]), 1.0), 40.0)
		if s != null:
			_fx.append({"node": s, "t": 0.0, "life": STICKY_FLY, "kind": "arc_to", "from": Vector2(from["pos"]), "tgt": tgt, "h": 1.4})
	_later(STICKY_FLY if from is Dictionary else 0.0, func() -> void:
		_attach("p2eq_101", tgt, maxf(0.1, fuse - STICKY_FLY), 46.0)
		if battle.get("_vfx") != null and tgt.get("alive", false):
			battle._vfx._float_text(Vector2(tgt["pos"]) + Vector2(0, -70), Lang.t("减速 %d%%") % int(round(EqBombBatch.STICKY_SLOW * 100.0)), VisualConstants.color_of("debuff-label")))


## 粘弹爆炸只伤被粘住的那一个 ⇒ 身体中心一团(不按粘液范围放大); 粘液坑贴地铺开(半径 = GOO_R), 地上一圈标范围
## 粘液坑: 地上铺一层半透明荧光绿(贴地, 直径 = 粘液范围) + 中间冒泡; 地上一圈标范围
func sticky_blast(c: Vector2, r: float, on = null) -> void:
	_anim("std", c, 120.0, 0.6, 0.02, false, false, Color(0.75, 1.0, 0.55), on)
	_splat(c, r, EqBombBatch.GOO_SEC)
	_ring(c, r, Color(0.6, 1.0, 0.35, 0.9), EqBombBatch.GOO_SEC)


## 粘液摊(11-24 重做, 用户「程序生成的？我感觉效果不好，没有商业的感觉」): 画好的像素粘液(8 帧冒泡循环) 平铺在地上,
##   宽 = 粘液直径; 落地 0.15 秒从中心弹开, 持续期间冒泡, 最后 0.3 秒收缩淡出。单位站在上面照常画在粘液之上。
const SPLAT_TEX := "res://assets/sprites/vfx/bomb-goo-splat.png"
const SPLAT_FW := 96
const SPLAT_CONTENT_W := 82.0
## 素材本身画成斜上方看下去的扁椭圆; 平铺到地面再被镜头压扁一次 ⇒ 纵向拉回这么多倍, 看起来与原画同比例
const SPLAT_Z := 1.7
func _splat(c: Vector2, r: float, life: float) -> void:
	if not _ok() or not ResourceLoader.exists(SPLAT_TEX):
		return
	var t: Texture2D = load(SPLAT_TEX)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = maxi(1, t.get_width() / SPLAT_FW)
	s.shaded = false
	s.transparent = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.pixel_size = (r * 2.0 * float(battle.WS)) / SPLAT_CONTENT_W
	s.position = battle._world_pos(c, 0.03)
	s.scale = Vector3(0.3, 1.0, 0.3 * SPLAT_Z)
	battle._world.add_child(s)
	_fx.append({"node": s, "t": 0.0, "life": life, "kind": "splat", "nf": s.hframes})


## 贴地的一片(软边圆), 存活 life 秒, 最后 30% 淡出
func _decal(c: Vector2, r: float, col: Color, life: float) -> void:
	if not _ok():
		return
	var tx: Texture2D = VfxTex._make_fire_glow_tex()
	var s := Sprite3D.new()
	s.texture = tx
	s.shaded = false
	s.transparent = true
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.modulate = col
	s.pixel_size = (r * 2.4 * float(battle.WS)) / float(tx.get_height())
	s.position = battle._world_pos(c, 0.03)
	battle._world.add_child(s)
	_fx.append({"node": s, "t": 0.0, "life": life, "kind": "decal", "a0": col.a})


## 定时炸弹(11-24 自查): 图标放大、挂到血条上方; 每秒在头上跳倒计时数字(4/3/2/1)
func timer_attach(tgt: Dictionary, fuse: float) -> void:
	_attach("p2eq_104", tgt, fuse, 72.0, 4.7)
	if _fx.size() > 0 and _fx[_fx.size() - 1].get("kind", "") == "attach":
		_fx[_fx.size() - 1]["count"] = int(ceil(fuse))


## 定时炸弹爆炸: 专属的红闪 + 准星环 + 火团(不再借手雷的火球), 在目标身体中心, 宽 = 伤害直径; 地上范围圈
func timer_blast(c: Vector2, r: float, on = null) -> void:
	_anim("timer", c, r * 2.7, 0.75, 0.02, false, false, Color.WHITE, on)   # 火团本身(约占内容 3/4)铺满伤害直径
	_ring(c, r, Color(1.0, 0.35, 0.3, 0.95), 0.5)


## 绑在目标头顶的小炸弹，跟着目标走，越到引爆闪得越快
func _attach(icon_id: String, tgt: Dictionary, fuse: float, px: float = 30.0, h: float = 2.9) -> void:
	var s := _icon(icon_id, battle._world_pos(Vector2(tgt["pos"]), h), px) if _ok() else null
	if s != null:
		s.no_depth_test = true
		s.render_priority = 12
		_fx.append({"node": s, "t": 0.0, "life": fuse, "kind": "attach", "tgt": tgt, "h": h})


## 地雷「对手看不见」(方案书 §4.2): 只画本方(左方 = 玩家视角)的雷; 对方的雷不画, 踩中才看到爆炸
func mine_place(p: Vector2, side: String) -> void:
	var s := _icon("p2eq_102", battle._world_pos(p, 0.05), 48.0) if _ok() else null
	if s != null:
		s.visible = side == "left"
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
		s.modulate = Color(1, 1, 1, 0.8)
		_mines.append({"node": s, "pos": p})


func mine_blast(c: Vector2, r: float) -> void:
	for i in range(_mines.size()):
		if Vector2(_mines[i]["pos"]).distance_to(c) < 1.0:
			if is_instance_valid(_mines[i]["node"]):
				_mines[i]["node"].queue_free()
			_mines.remove_at(i)
			break
	## 落地类: 以雷为中心从地面炸起的一整团(泥土碎石), 宽 = 伤害直径(靠爆炸本身盖满范围) + 范围圈
	##   (原来另有一层放平贴在地上的, 用户 11-24「怎么跟贴地上了」⇒ 去掉)
	_anim("mine", c, r * 2.0, 0.85, 0.05, false, false, Color.WHITE, "ground")
	_ring(c, r, Color(0.95, 0.8, 0.5, 0.95), 0.6)


## 炸药桶(11-24 自查): 原来 56 像素的卡通爆炸放大到 12 米, 像素块粗得和画面不是一个精度 ⇒ 换高精度大爆炸(224 像素:
##   火光 + 冲击波 + 飞石 + 黑烟柱), 从携带者脚下炸起, 宽 = 伤害直径
func barrel_blast(c: Vector2, r: float, _on = null) -> void:
	_anim("big", c, r * 2.0, 2.4, 0.05, false, false, Color.WHITE, "ground")
	_ring(c, r, Color(1.0, 0.4, 0.15, 0.7), 0.4)


## 106 遥控炸弹(11-24 专属, 不借炸药桶的大爆炸): 白闪 → 地面一圈火团往外推、正好铺满伤害直径 → 蘑菇云升起 → 渐隐
func remote_blast(c: Vector2, r: float) -> void:
	_anim("remote", c, r * 2.0, 2.8, 0.02, false, false, Color.WHITE, "ground")
	_ring(c, r, Color(1.0, 0.3, 0.1, 0.8), 0.5)


## 普通炮(11-24 用户「普通炮你没弹道出来没」): 炮口火光 + 一颗黑铁炮弹按弧线飞向目标(跟着目标走), 落到身上才炸(cannon_ball_hit)
const BALL_TEX := "res://assets/sprites/vfx/bomb-cannonball.png"
## 炮口位置(画里炮口在帧左侧 x≈8 / 离帧底 42 像素; 游戏里朝向敌人翻转): 返回 [地面坐标, 离地高度]
const MUZZLE_PX := Vector2(24.0, 42.0)
func muzzle(p, toward_x: float) -> Array:
	var sp = p.get("sprite", null) if p is Dictionary else null
	if not is_instance_valid(sp) or not (sp is Sprite3D):
		return [Vector2(p["pos"]) if p is Dictionary else Vector2.ZERO, 1.0]
	var s3: Sprite3D = sp
	var ps: float = s3.pixel_size * s3.scale.y
	var sgn: float = 1.0 if toward_x >= float(p["pos"].x) else -1.0
	return [Vector2(p["pos"]) + Vector2(sgn * MUZZLE_PX.x * ps / float(battle.WS), 0.0), MUZZLE_PX.y * ps]


func cannon_shot(from: Vector2, to: Vector2, tgt = null, fly: float = 0.0, src = null) -> void:
	var mz_h := 0.9
	if src is Dictionary:
		var mz: Array = muzzle(src, to.x)
		from = mz[0]
		mz_h = float(mz[1])
	if fly > 0.0 and _ok() and ResourceLoader.exists(BALL_TEX):
		var t: Texture2D = load(BALL_TEX)
		var bs := Sprite3D.new()
		bs.texture = t
		bs.shaded = false
		bs.transparent = true
		bs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bs.pixel_size = (34.0 * float(battle.WS)) / 50.0   # 炮弹比炮台小(原来 60 码比炮台还大)
		bs.offset = Vector2(32.0 - 44.0, 31.0 - 32.0)   # 锚点 = 球心(图里球在右、烟尾在左)
		bs.no_depth_test = true
		bs.render_priority = 11
		bs.position = battle._world_pos(from, mz_h)
		battle._world.add_child(bs)
		_fx.append({"node": bs, "t": 0.0, "life": fly, "kind": "ball", "from": from, "to": to, "tgt": tgt, "h0": mz_h})
	if fly <= 0.0:
		_anim("boom", to, 100.0, 0.6, 0.02, false, false, Color.WHITE, tgt)


## 炮筒动作 / 形态(11-24 用户「炮台攻击动画呢」「武器进入强化形态…武器会有什么变化」):
##   走引擎自己的动作通道 `_set_anim_sheet(单位, 帧表, 动作名, true)`: 动作播一遍自动回到这只单位【当前的】待机表。
##   · 普通形态: 待机 = 黑铁炮台; 开炮 = 喷火→后坐→回位
##   · 强化(重炮)形态: 待机换成「炮管烧红、裂纹明暗呼吸」; 进入时播「升温变身」(黑铁→烧红); 开炮 = 更猛的喷火 + 重后坐;
##     退出时待机换回黑铁, 播「冷却」(变身倒放)
##   帧表全在 assets/sprites/vfx/eq-cannon-*.png(tools/assetgen/pack_bomb_vfx.py 打包; 来历见那里)
const CANNON_SHEETS := {
	"fire": ["res://assets/sprites/vfx/eq-cannon-fire.png", 450],
	"heat": ["res://assets/sprites/vfx/eq-cannon-heat.png", 900],
	"cool": ["res://assets/sprites/vfx/eq-cannon-cool.png", 700],
	"hidle": ["res://assets/sprites/vfx/eq-cannon-hidle.png", 1100],
	"hfire": ["res://assets/sprites/vfx/eq-cannon-hfire.png", 550],
}
static var _cannon_sd := {}
func _csd(key: String) -> Dictionary:
	if _cannon_sd.has(key):
		return _cannon_sd[key]
	var row: Array = CANNON_SHEETS[key]
	var sd := {}
	if ResourceLoader.exists(str(row[0])):
		var t: Texture2D = load(str(row[0]))
		sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 64, "frameW": 64, "frameH": 64, "duration": int(row[1])}, false)
	_cannon_sd[key] = sd
	return sd


func _cannon_play(p, key: String, action: String) -> void:
	if not (p is Dictionary) or not _ok() or not (p as Dictionary).get("alive", false):
		return
	var sd: Dictionary = _csd(key)
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, action, true)


func cannon_fire(p) -> void:
	if not (p is Dictionary):
		return
	## 变身 / 冷却正在播 ⇒ 不打断(炮弹照常飞出, 只是这一下不播后坐)
	if str((p as Dictionary).get("anim_action", "")) in ["heat", "cool"]:
		return
	_cannon_play(p, "hfire" if bool((p as Dictionary).get("_cannon_heavy", false)) else "fire", "fire")


func cannon_heavy_on(p: Dictionary) -> void:
	if not p.has("_idle_norm_sd"):
		p["_idle_norm_sd"] = p.get("idle_sd", {})
	p["_cannon_heavy"] = true
	var hs: Dictionary = _csd("hidle")
	if not hs.is_empty():
		p["idle_sd"] = hs
	_cannon_play(p, "heat", "heat")
	_ring(Vector2(p["pos"]), 110.0, Color(1.0, 0.5, 0.15, 0.95), 0.45)


func cannon_heavy_off(p: Dictionary) -> void:
	p["_cannon_heavy"] = false
	if p.has("_idle_norm_sd"):
		p["idle_sd"] = p["_idle_norm_sd"]
	_cannon_play(p, "cool", "cool")


func cannon_ball_hit(c: Vector2, tgt = null) -> void:
	_anim("boom", c, 100.0, 0.6, 0.02, false, false, Color.WHITE, tgt)


## 重炮打中: 目标身上炸一下(用炸药桶以前那张卡通爆炸, 现在别处不用了)
func cannon_hit(o: Dictionary) -> void:
	_anim("boom", Vector2(o["pos"]), 120.0, 0.6, 0.02, false, false, Color.WHITE, o)


## ── 107 武士刀小将的动作(11-25 用户「武士这个动作…普通攻击应该是一个横横斩…把刀放下，然后往上挥出一道这个气波…
##   强化形态下…一套序列动作…刀会放到这个左身方，然后这样子挥出去，挥出这个龙卷风」) ──
##   帧表 assets/sprites/vfx/eq-katana-*.png(来历见 tools/assetgen/pack_bomb_vfx.py KATANA_SEQ), 走引擎动作通道
##   `_set_anim_sheet`: 动作播一遍自动回到这只单位【当前的】待机表(蓄力时待机临时换成蓄力循环)。
##   普攻横斩不在这里: 小将身上挂 `_act_rows`(普攻前摇 / 命中 / 后摇节奏由 AttackRhythm 对齐), 这里只画命中刀光。
const KATANA_SHEETS := {
	"rise": "res://assets/sprites/vfx/eq-katana-rise.png",        # 10 帧: 刀压低 → 上挑(第 6 帧 = 出波) → 收刀
	"coil": "res://assets/sprites/vfx/eq-katana-coil.png",        # 6 帧: 蹲低、刀收到身侧
	"hold": "res://assets/sprites/vfx/eq-katana-hold.png",        # 3 帧循环: 蓄力(身边风丝)
	"release": "res://assets/sprites/vfx/eq-katana-release.png",  # 9 帧: 绕身甩刀(第 4 帧 = 甩出龙卷风) → 刀举过头顶 → 收刀
}
const KATANA_RISE_HIT := 6
const KATANA_RELEASE_HIT := 4
const KATANA_ACT_FPS := 16.0
static var _katana_sd := {}
func _ksd(key: String, fps: float) -> Dictionary:
	if not _katana_sd.has(key):
		var path: String = KATANA_SHEETS[key]
		var sd := {}
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 800}, false)
		_katana_sd[key] = sd
	var out: Dictionary = (_katana_sd[key] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func _katana_play(p: Dictionary, key: String, fps: float, as_idle: bool = false) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _ksd(key, fps)
	if sd.is_empty():
		return
	if as_idle:
		if not p.has("_idle_norm_sd"):
			p["_idle_norm_sd"] = p.get("idle_sd", {})
		p["idle_sd"] = sd
	else:
		battle._set_anim_sheet(p, sd, "katana_" + key, true)


## 普攻命中: 敌人身上一道小切痕(刀光拖尾已经画进横斩动作帧里, 跟着刀走 —— tools/assetgen/katana_trail.py;
##   11-25 用户「这个普攻的特效，你这次怎么给的呢？我不太懂」: 原来在小将身前另播一张大刀光弧, 和刀实际走的路线对不上, 去掉)
func katana_hslash(u: Dictionary, tgt: Dictionary) -> void:
	var right: bool = (Vector2(tgt["pos"]) - Vector2(u["pos"])).x > 0.0
	var s := _anim("hslash", Vector2(tgt["pos"]), 64.0, 0.3, 1.0, false, false, Color.WHITE, tgt)
	if s != null:
		s.flip_h = right


## 技能: 刀压低 → 上挑, 上挑那一帧(第 6 帧)正好是 sim 出波那一刻(前摇 wsec 秒)
func katana_rise(p: Dictionary, wsec: float) -> void:
	_katana_play(p, "rise", float(KATANA_RISE_HIT) / maxf(0.05, wsec))


## 第 4 下: 蹲低收刀(6 帧) → 蓄力循环(身边风丝 + 聚气粒子) → 蓄满前 0.25 秒开甩, 甩出帧(第 4 帧)对上 sim 出龙卷风那一刻
func katana_charge(p: Dictionary, sec: float) -> void:
	if not _ok():
		return
	_katana_play(p, "hold", 8.0, true)          # 收刀播完自动回「当前待机」= 蓄力循环
	_katana_play(p, "coil", KATANA_ACT_FPS)
	var s := _anim("charge", Vector2(p["pos"]), 130.0, sec, 0.45, false, true, Color(0.55, 0.9, 1.0), p)   # 聚气中心 = 身体中段(on=单位; 原来按贴图半径抬高, 浮在头顶像个蓝球)
	if s != null:
		_fx[_fx.size() - 1]["kind"] = "anim_follow"
		_fx[_fx.size() - 1]["tgt"] = p
		_fx[_fx.size() - 1]["nmax"] = 7   # 只循环前 7 帧(风粒子往里收); 后几帧是聚成一团的光核, 压在身上像块蓝方块(11-25 自查)
	var pp: Dictionary = p
	_later(maxf(0.0, sec - float(KATANA_RELEASE_HIT) / KATANA_ACT_FPS), func() -> void:
		if pp.has("_idle_norm_sd"):
			pp["idle_sd"] = pp["_idle_norm_sd"]
			pp.erase("_idle_norm_sd")
		_katana_play(pp, "release", KATANA_ACT_FPS))


## 直线弹道：剑气波 / 龙卷风 / 重炮，与结算同一速度同一路程（演出只画，不判定）
func line_launch(kind: String, from: Vector2, dir: Vector2, spd: float, length: float, src = null) -> void:
	if not _ok():
		return
	var life: float = length / maxf(1.0, spd)
	match kind:
		"katana_wave":
			var s := _anim("wave", from, 120.0, life, 1.0, false, true)
			if s != null:
				s.flip_h = dir.x < 0.0
				_fx[_fx.size() - 1]["kind"] = "move"
				_fx[_fx.size() - 1].merge({"from": from, "dir": dir, "spd": spd, "nf": s.hframes, "h": 1.0})
		"katana_tornado":
			_tornado(from, dir, spd, life)
		"cannon_heavy":
			## 重炮: 炮台播开炮动作(炮口火光在动作里); 炮弹 = 带火焰尾巴的重炮弹, 沿直线飞
			cannon_fire(src)
			## ★飞行高度 = 敌人身体中心(11-24 用户「这个怎么又贴地下」: 原来 0.9 米、没影子 ⇒ 像一道火在地上滑);
			##   地上跟一块影子, 读得出它在空中飞
			var fh := 1.3
			if src is Dictionary:   # 从炮口打出去(位置 + 高度)
				var mz2: Array = muzzle(src, from.x + dir.x)
				from = mz2[0]
				fh = float(mz2[1])
			var b := _anim("shell", from, 130.0, life, fh, false, true)
			if b != null:
				b.no_depth_test = true
				b.render_priority = 11
				_fx[_fx.size() - 1]["kind"] = "move"
				_fx[_fx.size() - 1]["orient"] = true
				## 尾焰约 100 码长: 头飞出炮口 100 码之前不画, 否则整条火尾盖在炮台身上(11-24 自查)
				b.visible = false
				_fx[_fx.size() - 1].merge({"from": from, "dir": dir, "spd": spd, "h": fh, "loop_all": true, "show_after": 100.0 / maxf(1.0, spd)})
			_ground_shadow(from, dir, spd, life, 70.0, 100.0 / maxf(1.0, spd))


## 飞行物在地上的影子: 一块扁的暗色软斑, 跟着飞行物走(只在地上, 不画高度)
func _ground_shadow(from: Vector2, dir: Vector2, spd: float, life: float, w: float, show_after: float = 0.0) -> void:
	var sh := Sprite3D.new()
	sh.texture = VfxTex._make_blob_texture()
	sh.shaded = false
	sh.transparent = true
	sh.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sh.axis = Vector3.AXIS_Y
	sh.modulate = Color(0, 0, 0, 0.45)
	sh.pixel_size = (w * float(battle.WS)) / float(maxi(1, sh.texture.get_width()))
	sh.scale = Vector3(1.0, 1.0, 0.55)
	sh.position = battle._world_pos(from, 0.03)
	battle._world.add_child(sh)
	sh.visible = show_after <= 0.0
	_fx.append({"node": sh, "t": 0.0, "life": life, "kind": "move", "from": from, "dir": dir, "spd": spd, "h": 0.03, "nf": 1, "show_after": show_after})


## 龙卷风：五层细环叠成漏斗（下小上大），每层绕中心转、相位错开 ⇒ 读得出「旋」
## 龙卷风: Blender 渲的漏斗序列帧(16 帧/秒循环)沿路径走; 出生 0.15 秒从小长大, 最后 15% 渐隐。
##   (11-25 用户「这个龙卷风做的也不好…完全这个程序做的呀，太敷衍了」⇒ 换掉原来 VfxTex 细圆环叠出来的程序漏斗)
func _tornado(from: Vector2, dir: Vector2, spd: float, life: float) -> void:
	var s := _anim("tornado", from, 112.0, life, 0.05, false, true, Color.WHITE, "ground")   # 约 1.5 个单位高(亚索 Q3 的比例)
	if s == null:
		return
	var f: Dictionary = _fx[_fx.size() - 1]
	f["kind"] = "move"
	f.merge({"from": from, "dir": dir, "spd": spd, "h": 0.05, "loop_all": true, "fps": 16.0, "grow": 0.15, "fade_tail": 0.15, "ps": s.pixel_size})
	f["f0"] = int(absf(dir.angle()) * 20.0) % s.hframes   # 三道方向不同 ⇒ 各从不同帧起转, 不同步


# ═══════════════════════════════ 生命周期 ═══════════════════════════════

func tick(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i]["t"] = float(_pending[i]["t"]) - delta
		if float(_pending[i]["t"]) <= 0.0:
			var fn: Callable = _pending[i]["fn"]
			_pending.remove_at(i)
			fn.call()
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		var n = f.get("node", null)
		if not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		var q: float = clampf(float(f["t"]) / maxf(0.001, float(f["life"])), 0.0, 1.0)
		match str(f["kind"]):
			"anim":
				var nf: int = int(f["nf"])
				if bool(f.get("loop", false)):
					(n as Sprite3D).frame = int(f.get("skip", 0)) + int(float(f["t"]) * 12.0) % nf
					if q > 0.8:
						(n as Sprite3D).modulate.a = (1.0 - q) / 0.2
				else:
					(n as Sprite3D).frame = int(f.get("skip", 0)) + mini(nf - 1, int(q * float(nf)))
			"ring":
				var s: Sprite3D = n
				s.pixel_size = lerpf(float(f["ps0"]), float(f["ps1"]), minf(1.0, q / 0.4))
				s.modulate.a = float(f["a0"]) * (1.0 if q < 0.5 else (1.0 - q) / 0.5)
			"locator":
				var mat = (n as MeshInstance3D).material_override
				if mat is StandardMaterial3D:
					var blink: float = 0.55 + 0.45 * absf(sin(float(f["t"]) * (3.0 + 9.0 * q)))
					(mat as StandardMaterial3D).albedo_color.a = COL_LOCATOR.a * blink
			"reticle":
				var r: Sprite3D = n
				r.pixel_size = float(f["ps"]) * (1.0 if bool(f.get("no_shrink", false)) else (1.0 - 0.6 * q))
				r.rotation.y = float(f["t"]) * 1.5
				if bool(f.get("no_shrink", false)):
					r.modulate.a = 0.55 + 0.45 * absf(sin(float(f["t"]) * (3.0 + 12.0 * q)))
			"laser":
				var ls: Sprite3D = n
				ls.frame = int(float(f["t"]) * 16.0) % 4
				## 越接近落弹闪得越快; 最后 0.3 秒常亮(导弹就要顺着它下来)
				ls.modulate.a = 1.0 if q > 0.97 else (0.5 + 0.5 * absf(sin(float(f["t"]) * (2.0 + 14.0 * q))))
			"fall":
				## 加速下落(h = H × (1 - q²)), 帧循环
				(n as Node3D).position = battle._world_pos(Vector2(f["at"]), DROP_H * (1.0 - q * (0.35 + 0.65 * q)))   # 先慢后快(开头不至于停在天上不动)
				(n as Sprite3D).frame = int(float(f["t"]) * 16.0) % int(f["nf"])
			"board_zone":
				## 开头淡、越接近落弹越亮, 闪烁从慢到快
				## 11-25 用户「这个红色斜纹危险区太明显了」: 整体压淡到原来的 4 成左右, 看得出范围但不抢画面
				(n as Sprite3D).modulate.a = (0.12 + 0.28 * q) * (0.7 + 0.3 * absf(sin(float(f["t"]) * (2.0 + 10.0 * q))))
			"arc":
				var a: Vector2 = f["from"]
				var b: Vector2 = f["to"]
				(n as Node3D).position = battle._world_pos(a.lerp(b, q), 0.4 + float(f["h"]) * 4.0 * q * (1.0 - q))
				(n as Node3D).rotation.z = q * 9.0
			"splat":
				var sp2: Sprite3D = n
				var tt: float = float(f["t"])
				var lf: float = float(f["life"])
				var k: float = 1.0
				if tt < 0.15:
					k = 0.3 + 0.8 * (tt / 0.15)          # 弹开(略冲过头)
				elif tt < 0.25:
					k = 1.1 - 0.1 * ((tt - 0.15) / 0.1)  # 回弹到 1
				if tt > lf - 0.3:
					k *= 0.6 + 0.4 * clampf((lf - tt) / 0.3, 0.0, 1.0)   # 收缩
					sp2.modulate.a = clampf((lf - tt) / 0.3, 0.0, 1.0)
				sp2.scale = Vector3(k, 1.0, k * SPLAT_Z)
				sp2.frame = int(tt * 10.0) % int(f["nf"])
			"decal":
				(n as Sprite3D).modulate.a = float(f["a0"]) * (1.0 if q < 0.7 else (1.0 - q) / 0.3)
			"ball":
				var tb = f.get("tgt", null)
				var dst: Vector2 = Vector2(tb["pos"]) if tb is Dictionary and tb.get("alive", false) else Vector2(f["to"])
				var hb: float = body_h(tb) if tb is Dictionary else 1.0
				var h0b: float = float(f.get("h0", 0.9))
				var p3: Vector3 = battle._world_pos(Vector2(f["from"]).lerp(dst, q), lerpf(h0b, hb, q) + 1.6 * 4.0 * q * (1.0 - q))
				var q2: float = minf(1.0, q + 0.03)
				var p3b: Vector3 = battle._world_pos(Vector2(f["from"]).lerp(dst, q2), lerpf(h0b, hb, q2) + 1.6 * 4.0 * q2 * (1.0 - q2))
				(n as Node3D).position = p3
				if q2 > q:
					_orient(n, p3, p3b)
			"arc_to":
				var tg2: Dictionary = f["tgt"]
				var a2: Vector2 = f["from"]
				var b2: Vector2 = Vector2(tg2["pos"])
				(n as Node3D).position = battle._world_pos(a2.lerp(b2, q), 1.0 + float(f["h"]) * 4.0 * q * (1.0 - q) + 1.9 * q)
				(n as Node3D).rotation.z = q * 8.0
			"attach":
				var tg: Dictionary = f["tgt"]
				(n as Node3D).position = battle._world_pos(Vector2(tg["pos"]), float(f.get("h", 2.9)))
				if f.has("count"):   # 倒计时: 剩余整秒数一变就在头上跳一个数字
					var left: int = int(ceil(float(f["life"]) - float(f["t"])))
					if left < int(f["count"]) and left > 0 and battle.get("_vfx") != null:
						f["count"] = left
						battle._vfx._float_text(Vector2(tg["pos"]) + Vector2(0, -150), str(left), VisualConstants.color_of("debuff-label"), true)   # 飘字配色表: 挂在敌人身上的状态 = 减益标签色(不用伤害红)
				var hz: float = 2.0 + 10.0 * q
				(n as Sprite3D).modulate = Color(1, 1, 1, 1) if fmod(float(f["t"]) * hz, 1.0) < 0.6 else Color(1, 0.4, 0.35, 1)
			"move":
				if f.has("show_after"):
					(n as Node3D).visible = float(f["t"]) >= float(f["show_after"])
				var pos: Vector2 = Vector2(f["from"]) + Vector2(f["dir"]).normalized() * float(f["spd"]) * float(f["t"])
				(n as Node3D).position = battle._world_pos(pos, float(f.get("h", 1.0)))
				if bool(f.get("orient", false)):
					_orient(n, (n as Node3D).position, battle._world_pos(pos + Vector2(f["dir"]).normalized() * 20.0, float(f.get("h", 1.0))))
				if bool(f.get("loop_all", false)):
					(n as Sprite3D).frame = (int(f.get("f0", 0)) + int(float(f["t"]) * float(f.get("fps", 12.0)))) % int(f["nf"])
				if f.has("grow"):
					(n as Sprite3D).pixel_size = float(f["ps"]) * lerpf(0.3, 1.0, minf(1.0, float(f["t"]) / float(f["grow"])))
				if f.has("fade_tail") and q > 1.0 - float(f["fade_tail"]):
					(n as Sprite3D).modulate.a = (1.0 - q) / float(f["fade_tail"])
				elif int(f.get("nf", 1)) > 1:
					(n as Sprite3D).frame = mini(int(f["nf"]) - 1, 2 + int(float(f["t"]) * 10.0) % 2)
			"anim_follow":
				var tf = f.get("tgt", null)
				if tf is Dictionary and tf.get("alive", false):
					var keep_y: float = (n as Node3D).position.y
					(n as Node3D).position = battle._world_pos(Vector2(tf["pos"]), 0.0)
					(n as Node3D).position.y = keep_y
				(n as Sprite3D).frame = int(f.get("skip", 0)) + int(float(f["t"]) * 12.0) % mini(int(f["nf"]), int(f.get("nmax", 999)))
		if float(f["t"]) >= float(f["life"]):
			n.queue_free()
			_fx.remove_at(i)


func clear() -> void:
	_pending.clear()
	for f in _fx:
		if is_instance_valid(f.get("node", null)):
			f["node"].queue_free()
	_fx.clear()
	for m in _mines:
		if is_instance_valid(m["node"]):
			m["node"].queue_free()
	_mines.clear()


func alive_count() -> int:
	return _fx.size() + _mines.size()
