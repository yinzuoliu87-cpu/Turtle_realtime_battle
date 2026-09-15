class_name AxeHoloVfx
extends RefCounted
## 096 小木斧【全息斧】造物的演出 (2026-09-15 · 方案书 20260915g「E」)
##
## ══════════════════════════════════════════════════════════════════
##  ★由来
## ══════════════════════════════════════════════════════════════════
## 用户看完九段形态视频:「8/9也是，完全没达标」。被否的是 `axe_final_vfx.gd` 里:
##   法阵 = 两圈程序细环 + 一根 BoxMesh 竖条当「插地的斧头」/ 每 0.5 秒一跳 = 把这几个网格透明度闪一下 /
##   普攻给友军护盾 = **零演出**。
## 他同一段对别的形态说的尺子: **演出读得出机制 · 范围 = 判定 · 每个效果有自己的画面 · 生效要有反馈**。
##
## 文案(p2eq_096 effectDesc3)每一句对应一段(分段表见方案书):
##   H1 普攻给最低血友军 60 盾 + 5 龟能 → `eq096-holo-bit.png` 数据流(终点 = 那个友军)
##                                       + `eq096-holo-shield.png` 护盾展开 + 头顶龟能箭头
##   H2 插地 4 秒 30% 减伤 + 600 码法阵 → 斧头 `axe_plant` 帧 + `eq096-holo-deploy.png` 展开 / 倒放收拢
##                                       + `eq096-holo-field.png` 循环 + `eq096-holo-guard.png` 六角护罩
##   H3 每 0.5 秒 +100 血 +5 龟能 +30% 攻速 → `eq096-holo-pulse.png` 每跳一道波(从第 0 帧起)
##                                       + `eq096-holo-boost.png` 每个被治疗友军 + `eq096-holo-haste.png` 脚下加速圈
##
## ★结算不在这里(CLAUDE.md §3.5): 护盾 / 龟能 / 回血 / 攻速全在 `axe_final_forms.gd` 的同步函数里,
##   本文件的入口由那几个函数在【同一个模拟步】调用, 只负责画。
## ★法阵本体由 `plant_step` 每模拟步按「插地已过多久 / 还剩多久」切帧(展开 → 循环 → 倒放收拢),
##   **收拢的最后一帧落在 `_holo_until` 到期那一步**, 到期那一步 `end_plant` 释放 —— 演出不比效果长。
##   位置每步读 `ax.pos`: 结算的圆心就是它(插地期间斧头 no_move, 所以它就是插地点; 被击退时仍与判定一致)。
## ★数据流是 0.3 秒的纯观感 tween(`_reg_tween`, 时停冻得住), lambda 只捕获实例 id。
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const BladeVfx := preload("res://scripts/scenes/battle/blade_eq_vfx.gd")

const TEX_FIELD := "res://assets/sprites/vfx/eq096-holo-field.png"
const TEX_DEPLOY := "res://assets/sprites/vfx/eq096-holo-deploy.png"
const TEX_PULSE := "res://assets/sprites/vfx/eq096-holo-pulse.png"
const TEX_BIT := "res://assets/sprites/vfx/eq096-holo-bit.png"
const TEX_SHIELD := "res://assets/sprites/vfx/eq096-holo-shield.png"
const TEX_BOOST := "res://assets/sprites/vfx/eq096-holo-boost.png"
const TEX_HASTE := "res://assets/sprites/vfx/eq096-holo-haste.png"
const TEX_GUARD := "res://assets/sprites/vfx/eq096-holo-guard.png"

const FRAMES := 8
const GROUND_Y := 0.06
## 法阵三段(秒): 展开 / 循环 / 收拢。循环 8 帧 8fps = 1 秒一圈。
const DEPLOY_SEC := 0.5
const COLLAPSE_SEC := 0.4
const FIELD_FPS := 8.0
## 法阵常驻透明度: 1200 码直径几乎铺满半个战场, 全不透明的六角格会糊住所有单位
const FIELD_ALPHA := 0.80
## 护罩循环
const GUARD_FPS := 10.0
const GUARD_YARDS := 120.0
const GUARD_H := 0.8
## 数据流: 每隔多少码一块, 飞多久
const BIT_SPACING := 55.0
const BIT_MIN := 3
const BIT_MAX := 10
const BIT_FLY_SEC := 0.3
const BIT_YARDS := 22.0
const BIT_FROM_H := 1.0
const BIT_TO_H := 0.9
## 友军身上的一次性反馈
const SHIELD_YARDS := 115.0
const SHIELD_H := 1.0
const SHIELD_SEC := 0.5
const BOOST_YARDS := 85.0
const BOOST_H := 0.9
const BOOST_SEC := 0.45
## 加速圈(贴地)
const HASTE_YARDS := 72.0
const HASTE_FPS := 12.0

var battle = null


func _init(b) -> void:
	battle = b


func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调
# ══════════════════════════════════════════════════════════════════

## 数据流分几块: 按两点距离分段(每 BIT_SPACING 码一块), 夹在 [BIT_MIN, BIT_MAX]。
static func bit_count(dist_yd: float) -> int:
	return clampi(int(ceil(dist_yd / BIT_SPACING)), BIT_MIN, BIT_MAX)


## 插地已过 `elapsed` 秒、离到期还剩 `remain` 秒时, 法阵该用哪张表的第几帧。
## 返回 [贴图路径, 帧号]。★收拢是展开倒放: 还剩 COLLAPSE_SEC 时第 7 帧, 到期那一刻落到第 0 帧。
static func plant_frame(elapsed: float, remain: float) -> Array:
	if elapsed < DEPLOY_SEC:
		return [TEX_DEPLOY, clampi(int(elapsed / DEPLOY_SEC * float(FRAMES)), 0, FRAMES - 1)]
	if remain <= COLLAPSE_SEC:
		var k: int = clampi(int(remain / COLLAPSE_SEC * float(FRAMES)), 0, FRAMES - 1)
		return [TEX_DEPLOY, k]
	return [TEX_FIELD, int((elapsed - DEPLOY_SEC) * FIELD_FPS) % FRAMES]


## 脉冲帧率: 8 帧正好铺满一跳的间隔 ⇒ 下一跳从第 0 帧起时上一道刚放完。
static func pulse_fps() -> float:
	return float(FRAMES) / AF.HOLO_AURA_TICK


# ══════════════════════════════════════════════════════════════════
#  §建节点
# ══════════════════════════════════════════════════════════════════

func _sheet(path: String) -> Sprite3D:
	if not _has_world() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = maxi(1, int(tex.get_width() / maxi(1, tex.get_height())))
	s.frame = 0
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return s


func _size(s: Sprite3D, yards: float) -> void:
	s.pixel_size = yards * float(battle.WS) / float(maxi(1, s.texture.get_height()))


func _ground(s: Sprite3D, pos2d: Vector2, prio: int) -> void:
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s.basis = BladeVfx.ground_basis(Vector2.RIGHT, 0.0)
	s.position = battle._world_pos(pos2d, GROUND_Y)
	s.render_priority = prio


func _follow_once(s: Sprite3D, u: Dictionary, h: float, sec: float) -> void:
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": u, "h": h,
		"anim_fps": float(s.hframes) / maxf(0.05, sec), "anim_n": s.hframes, "anim_t0": float(battle._t)})


## ── H1 普攻给最低血友军盾 + 龟能 ─────────────────────────────────
## `holo_on_hit` 结算完、选中的就是 `ally` 之后调。返回 {"stream": 根节点, "shield": 精灵}。
## ★数据流根节点【放在终点(友军)上】, 数据块从斧头那一侧的局部偏移飞回原点 ——
##   所以"终点是谁"就是根节点自己的位置, 门禁量它, 不另记标记。
func on_hit(ax: Dictionary, ally: Dictionary) -> Dictionary:
	var out := {"stream": null, "shield": null}
	if not _has_world() or not (ally is Dictionary):
		return out
	var to3: Vector3 = battle._world_pos(ally.get("pos", Vector2.ZERO), float(ally.get("height", 0.0)) + BIT_TO_H)
	var from3: Vector3 = battle._world_pos(ax.get("pos", Vector2.ZERO), BIT_FROM_H)
	var root := Node3D.new()
	root.name = "holo_stream"
	root.position = to3
	battle._world.add_child(root)
	out["stream"] = root
	var dist_yd: float = (ax.get("pos", Vector2.ZERO) as Vector2).distance_to(ally.get("pos", Vector2.ZERO))
	var nb: int = bit_count(dist_yd)
	var off: Vector3 = from3 - to3
	var tex_ok: bool = ResourceLoader.exists(TEX_BIT)
	for i in range(nb):
		if not tex_ok:
			break
		var b: Sprite3D = _sheet(TEX_BIT)
		if b == null:
			break
		_size(b, BIT_YARDS)
		b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		b.render_priority = 9
		b.frame = i % FRAMES
		b.position = off
		root.add_child(b)
		## 一块接一块出发(间隔 = 飞行时长 / 块数), 同一条直线 ⇒ 读起来是一串流过去的数据
		var delay: float = BIT_FLY_SEC * float(i) / float(nb)
		var bid: int = b.get_instance_id()
		var tw: Tween = battle._reg_tween()
		tw.tween_interval(delay)
		tw.tween_method(func(x: float) -> void:
			var n = instance_from_id(bid)
			if not is_instance_valid(n):
				return
			(n as Sprite3D).position = off.lerp(Vector3.ZERO, x)
			(n as Sprite3D).frame = int(x * float(FRAMES * 2)) % FRAMES
		, 0.0, 1.0, BIT_FLY_SEC)
		tw.tween_callback(func() -> void:
			var n2 = instance_from_id(bid)
			if is_instance_valid(n2):
				(n2 as Node).queue_free())
	## 根节点在最后一块到站后释放
	var rid: int = root.get_instance_id()
	var tr: Tween = battle._reg_tween()
	tr.tween_interval(BIT_FLY_SEC * 2.0 + 0.05)
	tr.tween_callback(func() -> void:
		var r = instance_from_id(rid)
		if is_instance_valid(r):
			(r as Node).queue_free())
	## 护盾展开 + 头顶龟能箭头(同一张表), 跟着友军
	var sh: Sprite3D = _sheet(TEX_SHIELD)
	if sh != null:
		_size(sh, SHIELD_YARDS)
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sh.render_priority = 8
		sh.position = battle._world_pos(ally.get("pos", Vector2.ZERO), float(ally.get("height", 0.0)) + SHIELD_H)
		_follow_once(sh, ally, SHIELD_H, SHIELD_SEC)
		out["shield"] = sh
	return out


## ── H2 插地 ────────────────────────────────────────────────────
## `begin_active` 全息分支调。法阵(先放展开帧) + 减伤护罩, 都挂在 `_follow_vfx` 上跟斧头
## —— 只登记跟随(不登记 loop/anim), 帧号由 `plant_step` 每步设; 斧头死了渲染层自动收掉。
func begin_plant(ax: Dictionary) -> Dictionary:
	var out := {"field": null, "guard": null}
	end_plant(ax)
	if not _has_world():
		return out
	ax["_holo_vfx_t0"] = float(battle._t)
	var f: Sprite3D = _sheet(TEX_DEPLOY)
	if f != null:
		_size(f, AF.HOLO_AURA_R * 2.0)
		_ground(f, ax.get("pos", Vector2.ZERO), -2)
		f.modulate = Color(1.0, 1.0, 1.0, FIELD_ALPHA)
		battle._world.add_child(f)
		battle._follow_vfx.append({"spr": f, "unit": ax, "h": GROUND_Y})
		ax["_holo_field_spr"] = f
		out["field"] = f
	var g: Sprite3D = _sheet(TEX_GUARD)
	if g != null:
		_size(g, GUARD_YARDS)
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		g.render_priority = 8
		g.modulate = Color(1.0, 1.0, 1.0, 0.85)
		g.position = battle._world_pos(ax.get("pos", Vector2.ZERO), GUARD_H)
		battle._world.add_child(g)
		battle._follow_vfx.append({"spr": g, "unit": ax, "h": GUARD_H})
		ax["_holo_guard_spr"] = g
		out["guard"] = g
	return out


## 插地期间每模拟步调(`tick_active` 全息分支, 到期判断之后)。
func plant_step(ax: Dictionary) -> void:
	var f = ax.get("_holo_field_spr", null)
	var t: float = float(battle._t)
	var elapsed: float = t - float(ax.get("_holo_vfx_t0", t))
	var remain: float = float(ax.get("_holo_until", t)) - t
	if is_instance_valid(f):
		var pf: Array = plant_frame(elapsed, remain)
		var fs := f as Sprite3D
		if fs.texture == null or fs.texture.resource_path != str(pf[0]):
			fs.frame = 0
			fs.texture = load(str(pf[0]))
		fs.frame = int(pf[1])
		fs.position = battle._world_pos(ax.get("pos", Vector2.ZERO), GROUND_Y)
	var g = ax.get("_holo_guard_spr", null)
	if is_instance_valid(g):
		(g as Sprite3D).frame = int(elapsed * GUARD_FPS) % FRAMES


func end_plant(ax: Dictionary) -> void:
	for k in ["_holo_field_spr", "_holo_guard_spr"]:
		var n = ax.get(k, null)
		if is_instance_valid(n):
			(n as Node).queue_free()
		ax.erase(k)
	ax.erase("_holo_vfx_t0")


## ── H3 每 0.5 秒一跳 ────────────────────────────────────────────
## `holo_aura_tick` 结算完调。`healed` = 这一跳真的吃到治疗的友军(结算那边算好的同一批)。
## 返回 {"pulse", "boosts": [...], "hastes": [...]}。
func aura_tick(ax: Dictionary, healed: Array) -> Dictionary:
	var out := {"pulse": null, "boosts": [], "hastes": []}
	if not _has_world():
		return out
	var p: Sprite3D = _sheet(TEX_PULSE)
	if p != null:
		_size(p, AF.HOLO_AURA_R * 2.0)
		_ground(p, ax.get("pos", Vector2.ZERO), -1)
		battle._world.add_child(p)
		battle._follow_vfx.append({"spr": p, "unit": ax, "h": GROUND_Y,
			"anim_fps": pulse_fps(), "anim_n": FRAMES, "anim_t0": float(battle._t)})
		out["pulse"] = p
	for a in healed:
		if not (a is Dictionary):
			continue
		var b: Sprite3D = _sheet(TEX_BOOST)
		if b != null:
			_size(b, BOOST_YARDS)
			b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			b.render_priority = 8
			b.position = battle._world_pos(a.get("pos", Vector2.ZERO), float(a.get("height", 0.0)) + BOOST_H)
			_follow_once(b, a, BOOST_H, BOOST_SEC)
			(out["boosts"] as Array).append(b)
		var hm: Sprite3D = haste_mark(a)
		if hm != null:
			(out["hastes"] as Array).append(hm)
	return out


## 加速圈: 攻速 buff 在就在。★到期判据读结算写的 `haste_until`(`_follow_vfx` 的 until_key),
##   不另起计时; 离开范围后 buff 自己到期, 圈跟着收。已经有了就不重复建。
func haste_mark(a: Dictionary) -> Sprite3D:
	var cur = a.get("_holo_haste_spr", null)
	if is_instance_valid(cur) and not (cur as Node).is_queued_for_deletion():
		return cur
	var s: Sprite3D = _sheet(TEX_HASTE)
	if s == null:
		return null
	_size(s, HASTE_YARDS)
	_ground(s, a.get("pos", Vector2.ZERO), -1)
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": a, "h": GROUND_Y,
		"loop_fps": HASTE_FPS, "loop_n": FRAMES, "loop_t0": float(battle._t),
		"until_key": "haste_until", "clear_key": "_holo_haste_spr"})
	a["_holo_haste_spr"] = s
	return s
