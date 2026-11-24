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
	"crackle": ["vfx/bomb-tube-crackle.png", 83, 92, 77.0, 41, 46, 2],   # 第 7 项 = 跳过开头几帧(前两帧是一团白闪, 放大后像个白球盖住单位)
	"boom": ["vfx/bomb-barrel-boom.png", 56, 60, 50.0, 30, 37],
	"muzzle": ["vfx/bomb-cannon-muzzle.png", 35, 20, 28.0, 3, 10],
	"charge": ["vfx/katana-charge.png", 67, 67, 61.0, 33, 33],
	"spark": ["vfx/bomb-cracker-spark.png", 66, 69, 60.0, 35, 30],
	"paper": ["vfx/bomb-cracker-paper.png", 96, 75, 90.0, 47, 39],
}
const COL_LOCATOR := Color(1.0, 0.18, 0.12, 0.85)
## 导弹特效表里砸地是第 8 帧(共 17 帧, 播 0.95 秒) ⇒ 提前这么多秒开播, 砸地正好落在结算那一刻
const MISSILE_SEC := 0.95
const MISSILE_LEAD := MISSILE_SEC * 8.0 / 17.0

var battle
var _fx: Array = []          ## {node, t, life, kind, ...}
var _mines: Array = []       ## {node, pos}
var _pending: Array = []     ## 延时出场的演出 {t, fn}(鞭炮一串连炸)
var _crack_n := 0            ## 鞭炮第几串(每串转一个角度, 不每次一模一样)
static var _tex := {}


func _init(b) -> void:
	battle = b


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
			h = GunEqVfx.body_mid_h(on)
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

## 开打：从本方阵地拉一条红线指向战场中心（定位器），持续到导弹落下
func show_locator(side: String, fire_at: float) -> void:
	if not _ok():
		return
	var c: Vector2 = battle._arena_center
	var from := Vector2(battle.ARENA.position.x + 60.0, c.y) if side == "left" else Vector2(battle.ARENA.end.x - 60.0, c.y)
	var mi := MeshInstance3D.new()
	var d: Vector2 = c - from
	var p: Vector2 = Vector2(-d.y, d.x).normalized() * 6.0
	mi.mesh = GunEqVfx.gen_band(from, c, 0.06, 0.06, p, battle._arena_center, battle.WS)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = COL_LOCATOR
	mi.material_override = mat
	battle._world.add_child(mi)
	_fx.append({"node": mi, "t": 0.0, "life": fire_at, "kind": "locator"})
	## 靶心：中心一个收缩的红环，越到落弹越快
	var tx: Texture2D = VfxTex._make_thin_ring_tex()
	var s := Sprite3D.new()
	s.texture = tx
	s.shaded = false
	s.transparent = true
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.axis = Vector3.AXIS_Y
	s.modulate = COL_LOCATOR
	s.position = battle._world_pos(c, 0.07)
	s.pixel_size = (160.0 * float(battle.WS)) / float(tx.get_height())
	battle._world.add_child(s)
	_fx.append({"node": s, "t": 0.0, "life": fire_at, "kind": "reticle", "ps": s.pixel_size})


## 导弹从天而降(提前 MISSILE_LEAD 秒开播)
func missile_launch(_side: String) -> void:
	_anim("missile", battle._arena_center, 200.0, MISSILE_SEC, 0.02)


## 砸地那一刻: 每个挨炸的敌人身上一记爆炸
func missile_impact(side: String) -> void:
	if not _ok():
		return
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) != side and not bool(u.get("_isEgg", false)):
			_anim("std", Vector2(u["pos"]), 110.0, 0.7, 0.02)


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
			battle._vfx._float_text(Vector2(tgt["pos"]) + Vector2(0, -70), Lang.t("减速 %d%%") % int(round(EqBombBatch.STICKY_SLOW * 100.0)), Color("#a8ff6a")))


## 粘弹爆炸只伤被粘住的那一个 ⇒ 身体中心一团(不按粘液范围放大); 粘液坑贴地铺开(半径 = GOO_R), 地上一圈标范围
## 粘液坑: 地上铺一层半透明荧光绿(贴地, 直径 = 粘液范围) + 中间冒泡; 地上一圈标范围
func sticky_blast(c: Vector2, r: float, on = null) -> void:
	_anim("std", c, 120.0, 0.6, 0.02, false, false, Color(0.75, 1.0, 0.55), on)
	_decal(c, r, Color(0.45, 0.95, 0.25, 0.55), EqBombBatch.GOO_SEC)
	_anim("goo", c, r * 1.3, EqBombBatch.GOO_SEC, 0.05, false, true, Color.WHITE, "ground")
	_ring(c, r, Color(0.6, 1.0, 0.35, 0.9), EqBombBatch.GOO_SEC)


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


func timer_attach(tgt: Dictionary, fuse: float) -> void:
	_attach("p2eq_104", tgt, fuse)


func timer_blast(c: Vector2, r: float, on = null) -> void:
	_anim("std", c, r * 2.2, 0.7, 0.02, false, false, Color.WHITE, on)


## 绑在目标头顶的小炸弹，跟着目标走，越到引爆闪得越快
func _attach(icon_id: String, tgt: Dictionary, fuse: float, px: float = 30.0) -> void:
	var s := _icon(icon_id, battle._world_pos(Vector2(tgt["pos"]), 2.9), px) if _ok() else null
	if s != null:
		_fx.append({"node": s, "t": 0.0, "life": fuse, "kind": "attach", "tgt": tgt})


## 地雷「对手看不见」(方案书 §4.2): 只画本方(左方 = 玩家视角)的雷; 对方的雷不画, 踩中才看到爆炸
func mine_place(p: Vector2, side: String) -> void:
	var s := _icon("p2eq_102", battle._world_pos(p, 0.05), 34.0) if _ok() else null
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
	_anim("std", c, r * 2.0, 0.7)
	_ring(c, r, Color(0.9, 0.8, 0.5, 0.6), 0.3)


func barrel_blast(c: Vector2, r: float, on = null) -> void:
	_anim("boom", c, r * 2.0, 0.9, 0.02, false, false, Color.WHITE, on)
	_ring(c, r, Color(1.0, 0.4, 0.15, 0.7), 0.4)


func remote_blast(c: Vector2, r: float) -> void:
	_anim("big", c, r * 1.2, 2.2, 0.02)
	_ring(c, r, Color(1.0, 0.3, 0.1, 0.8), 0.5)


func cannon_shot(from: Vector2, to: Vector2) -> void:
	var m := _anim("muzzle", from + (to - from).normalized() * 30.0, 70.0, 0.3, 0.7)
	if m != null and to.x > from.x:
		m.flip_h = false
	elif m != null:
		m.flip_h = true
		m.offset.x = -m.offset.x
	_anim("boom", to, 90.0, 0.6, 0.02)


func katana_charge(p: Dictionary, sec: float) -> void:
	_anim("charge", Vector2(p["pos"]), 120.0, sec, 1.0, false, false, Color(0.75, 0.95, 1.0))


## 直线弹道：剑气波 / 龙卷风 / 重炮，与结算同一速度同一路程（演出只画，不判定）
func line_launch(kind: String, from: Vector2, dir: Vector2, spd: float, length: float) -> void:
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
			var b := _icon("p2eq_105", battle._world_pos(from, 0.8), 30.0)
			if b != null:
				b.texture = VfxTex._make_fire_glow_tex()
				b.pixel_size = (40.0 * float(battle.WS)) / 64.0
				b.modulate = Color(0.25, 0.22, 0.2, 1.0)
				_fx.append({"node": b, "t": 0.0, "life": life, "kind": "move", "from": from, "dir": dir, "spd": spd, "h": 0.8, "nf": 1})
			cannon_shot(from, from + dir * 60.0)


## 龙卷风：五层细环叠成漏斗（下小上大），每层绕中心转、相位错开 ⇒ 读得出「旋」
func _tornado(from: Vector2, dir: Vector2, spd: float, life: float) -> void:
	var root := Node3D.new()
	root.position = battle._world_pos(from, 0.0)
	battle._world.add_child(root)
	var tx: Texture2D = VfxTex._make_thin_ring_tex()
	## 9 层、每层两圈(内圈略小) ⇒ 线够密, 远看是一根旋转的漏斗而不是几道细线(录像台实拍第一版太淡)
	for i in range(9):
		for dr in [0.0, -5.0]:
			var s := Sprite3D.new()
			s.texture = tx
			s.shaded = false
			s.transparent = true
			s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			s.axis = Vector3.AXIS_Y
			s.modulate = Color(0.92, 0.98, 1.0, 1.0 - 0.05 * float(i))
			s.pixel_size = ((20.0 + 11.0 * float(i) + dr) * 2.0 * float(battle.WS)) / float(tx.get_height())
			s.position = Vector3(0.0, 0.15 + 0.3 * float(i), 0.0)
			root.add_child(s)
	var dust := Sprite3D.new()   # 底部一团卷起的尘
	dust.texture = VfxTex._make_fire_glow_tex()
	dust.shaded = false
	dust.transparent = true
	dust.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dust.modulate = Color(0.85, 0.82, 0.72, 0.55)
	dust.pixel_size = (70.0 * float(battle.WS)) / 64.0
	dust.position = Vector3(0.0, 0.3, 0.0)
	root.add_child(dust)
	_fx.append({"node": root, "t": 0.0, "life": life, "kind": "tornado", "from": from, "dir": dir, "spd": spd})


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
				r.pixel_size = float(f["ps"]) * (1.0 - 0.6 * q)
				r.rotation.y = float(f["t"]) * 1.5
			"arc":
				var a: Vector2 = f["from"]
				var b: Vector2 = f["to"]
				(n as Node3D).position = battle._world_pos(a.lerp(b, q), 0.4 + float(f["h"]) * 4.0 * q * (1.0 - q))
				(n as Node3D).rotation.z = q * 9.0
			"decal":
				(n as Sprite3D).modulate.a = float(f["a0"]) * (1.0 if q < 0.7 else (1.0 - q) / 0.3)
			"arc_to":
				var tg2: Dictionary = f["tgt"]
				var a2: Vector2 = f["from"]
				var b2: Vector2 = Vector2(tg2["pos"])
				(n as Node3D).position = battle._world_pos(a2.lerp(b2, q), 1.0 + float(f["h"]) * 4.0 * q * (1.0 - q) + 1.9 * q)
				(n as Node3D).rotation.z = q * 8.0
			"attach":
				var tg: Dictionary = f["tgt"]
				(n as Node3D).position = battle._world_pos(Vector2(tg["pos"]), 2.9)
				var hz: float = 2.0 + 10.0 * q
				(n as Sprite3D).modulate = Color(1, 1, 1, 1) if fmod(float(f["t"]) * hz, 1.0) < 0.6 else Color(1, 0.4, 0.35, 1)
			"move":
				var pos: Vector2 = Vector2(f["from"]) + Vector2(f["dir"]).normalized() * float(f["spd"]) * float(f["t"])
				(n as Node3D).position = battle._world_pos(pos, float(f.get("h", 1.0)))
				if int(f.get("nf", 1)) > 1:
					(n as Sprite3D).frame = mini(int(f["nf"]) - 1, 2 + int(float(f["t"]) * 10.0) % 2)
			"tornado":
				var tp: Vector2 = Vector2(f["from"]) + Vector2(f["dir"]).normalized() * float(f["spd"]) * float(f["t"])
				(n as Node3D).position = battle._world_pos(tp, 0.0)
				var k := 0
				for ch in (n as Node3D).get_children():
					var ph: float = float(f["t"]) * 14.0 + float(k / 2) * 0.9
					var rr: float = 0.05 + 0.02 * float(k / 2)
					(ch as Node3D).position.x = cos(ph) * rr
					(ch as Node3D).position.z = sin(ph) * rr
					k += 1
				if q > 0.85:
					for ch in (n as Node3D).get_children():
						(ch as Sprite3D).modulate.a *= 0.8
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
