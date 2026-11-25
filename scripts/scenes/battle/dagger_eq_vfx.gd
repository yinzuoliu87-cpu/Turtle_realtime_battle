class_name DaggerEqVfx
extends BombEqVfx
## dagger_eq_vfx.gd —— 匕首羁绊【刺杀】+ 匕首 9 件 + 暗影忍者 的演出层(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md)
##
## ★只画不判定: 结算全在 EqDaggerBatch / DaggerSynergySystem; 无头 / 没有世界节点时什么都不做(继承的 _ok())。
## ★生命周期 = 继承炸弹演出层的 `tick` / `_anim` / `_later`(不用 tween, CLAUDE.md §4.5); 本文件只换特效表(覆盖 `_row`),
##   另加三种自己的演出: "dart"(苦无直线飞向目标) / "stuck"(插在敌人身上的黑曜石匕首) / "flyline"(飞刀 / 手里剑沿直线飞)。
## 素材(如实): assets/sprites/vfx/dagger-*.png = PixelLab 特效工作台部件改配色导出, eq-ninja-*.png = PixelLab 生成的忍者动作帧,
##   dagger-kunai.png = 110 图标裁出的单把苦无; 飞刀 / 插着的黑曜石直接用 109 / 116 的装备图标。全部由
##   tools/assetgen/pack_dagger_art.py 打包(确定性)。逐帧研究: docs/studies/20261125-匕首羁绊特效逐帧.md。

## 特效表: 名 → [路径, 帧宽, 帧高, 内容直径(像素), 锚点 x, 锚点 y](锚点 = 特效工作台导出的 origin)
const DSHEETS := {
	"fang": ["vfx/dagger-fang-bite.png", 69, 72, 49.0, 40, 31],          # 111 毒牙: 蛇颚咬合 + 毒液
	"nsmoke": ["vfx/dagger-ninja-smoke.png", 73, 58, 67.0, 39, 35],      # 115 化烟 / 现身 / 登场 / 消散
	"nstrike": ["vfx/dagger-ninja-strike.png", 58, 67, 52.0, 29, 26],    # 115 影袭背刺: 紫色交叉斩
	"nslash": ["vfx/dagger-shade-cut.png", 26, 22, 20.0, 22, 11],      # 115 忍者普攻命中: 紫色单刀痕
	"astrike": ["vfx/dagger-assassin-strike.png", 123, 53, 114.0, 54, 21],   # 羁绊【刺杀】强化击: 猩红长斩线
	"amark": ["vfx/dagger-assassin-mark.png", 48, 45, 42.0, 23, 23],     # 羁绊【刺杀】挂上强化: 头顶暗红星芒
	"rexec": ["vfx/dagger-ritual-exec.png", 76, 65, 62.0, 37, 26],       # 114 斩杀: 猩红镰月 + 血花
	"rmark": ["vfx/dagger-ritual-mark.png", 54, 28, 36.0, 1, 13],        # 114 刻血契: 血气流进携带者
	"kris": ["vfx/dagger-kris-rush.png", 85, 39, 76.0, 60, 20],          # 113 弯匕攻速暴涨: 金色风纹(循环)
	"fold": ["vfx/dagger-fold-cut.png", 33, 42, 22.0, 9, 19],            # 108 折叠小刀: 钢白小刀口 + 血滴
	"khit": ["vfx/dagger-knife-hit.png", 46, 30, 40.0, 23, 16],          # 109 柳叶飞刀命中: 银蓝魔法火花
	"obs": ["vfx/dagger-obs-pull.png", 76, 95, 70.0, 37, 34],            # 116 黑曜石拔出: 黑玻璃碎片迸开
	"shur": ["vfx/dagger-shuriken-spin.png", 16, 16, 9.0, 7, 7],         # 115 手里剑旋转(循环)
	"kuhit": ["vfx/dagger-kunai-hit.png", 43, 35, 37.0, 18, 18],         # 110 苦无命中: 暗铁星形火花
	"kheal": ["vfx/dagger-kunai-heal.png", 22, 37, 24.0, 11, 26],        # 110 苦无回血: 青绿小十字
	"shit": ["vfx/dagger-shuriken-hit.png", 46, 29, 40.0, 23, 15],       # 115 手里剑命中: 紫色火花
}
## 暗影忍者动作帧(112 方帧, 与待机同贴地线): 背刺第 3 帧插中、掷剑第 3 帧出手(pack_dagger_art.py NINJA_HIT)
const NINJA_SHEETS := {
	"stab": "res://assets/sprites/vfx/eq-ninja-stab.png",
	"throw": "res://assets/sprites/vfx/eq-ninja-throw.png",
}
const NINJA_STAB_HIT := 3
const NINJA_THROW_HIT := 3
## 图标贴图里刀尖的朝向(度, 屏幕坐标 x 右 y 下): 109 / 116 图标刀尖朝右上 = -45°; 单把苦无刀尖朝上 = -90°
const KNIFE_TIP_DEG := -45.0
const KUNAI_TIP_DEG := -90.0

static var _nsd := {}
var _stuck: Array = []    ## {node, tgt, k}: 插在敌人身上的黑曜石匕首


func _row(key: String) -> Array:   # zero-caller-ok: 覆盖父类 BombEqVfx._row —— 父类的 _anim / _load 经它查表, 调用方在父类
	return DSHEETS.get(key, [])


## 头顶高度(身体中段再往上一个身体半高)
func _head_h(u) -> float:
	return BombEqVfx.body_h(u) * 2.0 if u is Dictionary else 2.0


## 一张静态小图(装备图标 / 苦无)按屏幕方向转过去: 贴图里刀尖朝 tip_deg, 让它朝 a3 → b3 的屏幕方向
func _point(s: Sprite3D, a3: Vector3, b3: Vector3, tip_deg: float) -> void:
	var cam = battle.get("_cam")
	if not is_instance_valid(cam) or not (cam is Camera3D):
		return
	var d: Vector2 = (cam as Camera3D).unproject_position(b3) - (cam as Camera3D).unproject_position(a3)
	if d.length() < 0.01:
		return
	## 屏幕 y 向下: 屏幕角 = atan2(d.y, d.x); 贴图角(同样 y 向下) tip_deg ⇒ 绕视线转 (tip − 屏幕角)
	s.global_transform.basis = (cam as Camera3D).global_transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(tip_deg) - atan2(d.y, d.x))


func _tex_sprite(path: String, px_world: float, pos3: Vector3, face_cam: bool = true) -> Sprite3D:
	var t: Texture2D = _load(path)
	if t == null or not _ok():
		return null
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 11
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_cam else BaseMaterial3D.BILLBOARD_DISABLED   # 要按飞行方向转的(face_cam=false)建的时候就定, sim 步里不再改这个属性(直播白名单)
	s.pixel_size = (px_world * float(battle.WS)) / float(maxi(t.get_width(), t.get_height()))
	s.position = pos3
	battle._world.add_child(s)
	return s


# ═══════════════════════════════ 羁绊【刺杀】 ═══════════════════════════════

## 挂上「下一击必暴击」: 每个友方头顶闪一下暗红星芒
func assassin_arm(who: Array) -> void:
	for u in who:
		if u is Dictionary and (u as Dictionary).get("alive", false):
			var s := _anim("amark", Vector2(u["pos"]), 46.0, 0.75, _head_h(u))
			if s != null:
				s.no_depth_test = true
				s.render_priority = 10


## 强化击命中: 一道猩红长斩线横切过目标(朝出手方向)
func assassin_strike(u: Dictionary, tgt: Dictionary) -> void:
	var s := _anim("astrike", Vector2(tgt["pos"]), 150.0, 0.5, 1.0, false, false, Color.WHITE, tgt)
	if s != null:
		s.flip_h = (Vector2(tgt["pos"]) - Vector2(u["pos"])).x < 0.0


# ═══════════════════════════════ 108 / 111 / 113 / 114 ═══════════════════════════════

func fold_cut(u: Dictionary, tgt: Dictionary) -> void:
	var s := _anim("fold", Vector2(tgt["pos"]), 56.0, 0.5, 1.0, false, false, Color.WHITE, tgt)
	if s != null:
		s.flip_h = (Vector2(tgt["pos"]) - Vector2(u["pos"])).x < 0.0


func fang_bite(tgt: Dictionary) -> void:
	_anim("fang", Vector2(tgt["pos"]), 60.0, 0.65, 1.0, false, false, Color.WHITE, tgt)


## 弯匕: 攻速暴涨那几秒, 携带者身上金色风纹一直往后掠(跟着人走)
func kris_rush(u: Dictionary, sec: float) -> void:
	var s := _anim("kris", Vector2(u["pos"]), 90.0, sec, 1.0, false, true, Color.WHITE, u)
	if s == null:
		return
	s.flip_h = not bool(u.get("face_right", u.get("side", "left") == "left"))
	var f: Dictionary = _fx[_fx.size() - 1]
	f["kind"] = "anim_follow"
	f["tgt"] = u


func ritual_execute(tgt: Dictionary) -> void:
	_anim("rexec", Vector2(tgt["pos"]), 110.0, 0.55, 1.0, false, false, Color.WHITE, tgt)


## 刻下血契: 一缕血气流进携带者 + 头顶跳「血契 N」
func ritual_mark(killer: Dictionary, n: int) -> void:
	_anim("rmark", Vector2(killer["pos"]), 70.0, 0.6, 1.0, false, false, Color.WHITE, killer)
	if _ok() and battle.get("_vfx") != null:
		battle._vfx._float_text(Vector2(killer["pos"]) + Vector2(0, -50), Lang.t("血契 %d") % n, Color("#ff4a5a"), true)


# ═══════════════════════════════ 109 柳叶飞刀 / 115 手里剑 ═══════════════════════════════

## 直线飞行物(与结算同速度同路程; 柳叶飞刀打中第一个敌人就停 ⇒ line_stop 收掉)
func line_launch(kind: String, from: Vector2, dir: Vector2, spd: float, length: float, src = null) -> void:
	if not _ok():
		return
	var life: float = length / maxf(1.0, spd)
	var h: float = BombEqVfx.body_h(src) if src is Dictionary else 1.0
	var s: Sprite3D = null
	match kind:
		"knife":
			s = _tex_sprite("equip/p2eq_109.png", 46.0, battle._world_pos(from, h), false)
			if s != null:
				_fx.append({"node": s, "t": 0.0, "life": life, "kind": "flyline", "line": kind, "from": from, "dir": dir, "spd": spd, "h": h, "tip": KNIFE_TIP_DEG})
		"shuriken":
			s = _anim("shur", from, 40.0, life, h, false, true)
			if s != null:
				s.no_depth_test = true
				s.render_priority = 11
				var f: Dictionary = _fx[_fx.size() - 1]
				f["kind"] = "move"
				f.merge({"from": from, "dir": dir, "spd": spd, "h": h, "loop_all": true, "fps": 24.0, "line": kind})


func line_stop(kind: String, at: Vector2) -> void:
	var best := -1
	var bd := 1.0e9
	for i in range(_fx.size()):
		var f: Dictionary = _fx[i]
		if str(f.get("line", "")) != kind:
			continue
		var p: Vector2 = Vector2(f["from"]) + Vector2(f["dir"]).normalized() * float(f["spd"]) * float(f["t"])
		var d := p.distance_to(at)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		_fx[best]["life"] = 0.0   # 下一拍 tick 收掉


func knife_hit(o: Dictionary) -> void:
	_anim("khit", Vector2(o["pos"]), 60.0, 0.45, 1.0, false, false, Color.WHITE, o)


func shuriken_hit(o: Dictionary) -> void:
	_anim("shit", Vector2(o["pos"]), 56.0, 0.45, 1.0, false, false, Color.WHITE, o)


# ═══════════════════════════════ 110 苦无 ═══════════════════════════════

func kunai_throw(u: Dictionary, tgt: Dictionary, delay: float, fly: float) -> void:
	if not _ok():
		return
	var uu: Dictionary = u
	var tt: Dictionary = tgt
	_later(delay, func() -> void:
		if not uu.get("alive", false):
			return
		var h0: float = BombEqVfx.body_h(uu)
		var s := _tex_sprite("vfx/dagger-kunai.png", 34.0, battle._world_pos(Vector2(uu["pos"]), h0), false)
		if s != null:
			_fx.append({"node": s, "t": 0.0, "life": fly, "kind": "dart", "from": Vector2(uu["pos"]), "h0": h0, "tgt": tt, "to": Vector2(tt["pos"]), "tip": KUNAI_TIP_DEG}))


func kunai_hit(tgt: Dictionary, src: Dictionary) -> void:
	_anim("kuhit", Vector2(tgt["pos"]), 48.0, 0.4, 1.0, false, false, Color.WHITE, tgt)
	if src.get("alive", false):
		_anim("kheal", Vector2(src["pos"]), 40.0, 0.85, 1.0, false, false, Color.WHITE, src)


# ═══════════════════════════════ 116 黑曜石匕首 ═══════════════════════════════

## 插一把: 黑曜石匕首(116 图标)斜插在敌人身上, 跟着它走; 几把错开位置
func obs_embed(tgt: Dictionary, count: int) -> void:
	if not _ok():
		return
	var s := _tex_sprite("equip/p2eq_116.png", 34.0, battle._world_pos(Vector2(tgt["pos"]), BombEqVfx.body_h(tgt)))
	if s == null:
		return
	s.rotation.z = deg_to_rad(180.0 + 20.0 * float((count - 1) % 3 - 1))   # 刀尖朝下插进去(图标刀尖朝右上, 转半圈 = 朝左下)
	_stuck.append({"node": s, "tgt": tgt, "k": count - 1})


func obs_pull(tgt: Dictionary, _n: int) -> void:
	for i in range(_stuck.size() - 1, -1, -1):
		if is_same(_stuck[i]["tgt"], tgt):
			if is_instance_valid(_stuck[i]["node"]):
				_stuck[i]["node"].queue_free()
			_stuck.remove_at(i)
	_anim("obs", Vector2(tgt["pos"]), 120.0, 0.8, 1.0, false, false, Color.WHITE, tgt)


# ═══════════════════════════════ 115 暗影忍者 ═══════════════════════════════

func _nsd_of(key: String, fps: float) -> Dictionary:
	if not _nsd.has(key):
		var path: String = NINJA_SHEETS[key]
		var sd := {}
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			sd = battle._sprite_dict_from(t, {"frames": t.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 800}, false)
		_nsd[key] = sd
	var out: Dictionary = (_nsd[key] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func _ninja_play(p: Dictionary, key: String, fps: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _nsd_of(key, fps)
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "ninja_" + key, true)


func ninja_spawn(p: Dictionary, _is_clone: bool) -> void:
	_anim("nsmoke", Vector2(p["pos"]), 100.0, 0.75, 0.6)


func ninja_slash(u: Dictionary, tgt: Dictionary) -> void:
	var s := _anim("nslash", Vector2(tgt["pos"]), 60.0, 0.4, 1.0, false, false, Color.WHITE, tgt)
	if s != null:
		s.flip_h = (Vector2(tgt["pos"]) - Vector2(u["pos"])).x > 0.0   # 贴图刀痕从右往左划(朝左打) ⇒ 朝右打时翻过来


## 影袭第一拍: 原地化成一团紫烟(本体由 battle_render 按 _ninja_gone 整个隐掉)
func ninja_vanish(p: Dictionary, _sec: float) -> void:
	_anim("nsmoke", Vector2(p["pos"]), 100.0, 0.75, 0.6)


## 影袭第二拍: 在目标身后冒烟现身, 背刺动作开播 —— 第 3 帧(刀插中)正好落在 windup 秒后(= sim 结算)
func ninja_appear(p: Dictionary, _from: Vector2, windup: float) -> void:
	_anim("nsmoke", Vector2(p["pos"]) + Vector2(36.0 if bool(p.get("face_right", false)) else -36.0, 0.0) * -1.0, 55.0, 0.45, 0.6)   # 小一团、落在身后(不盖住背刺动作)
	_ninja_play(p, "stab", float(NINJA_STAB_HIT) / maxf(0.05, windup))


func ninja_strike(_p: Dictionary, tgt: Dictionary, _from: Vector2) -> void:
	_anim("nstrike", Vector2(tgt["pos"]), 78.0, 0.75, 1.0, false, false, Color.WHITE, tgt)


## 掷手里剑: 手往后引 → 甩出, 第 3 帧(出手)正好落在 windup 秒后(= sim 放出手里剑那一刻)
func ninja_throw(p: Dictionary, windup: float) -> void:
	_ninja_play(p, "throw", float(NINJA_THROW_HIT) / maxf(0.05, windup))


func ninja_fade(p: Dictionary) -> void:
	_anim("nsmoke", Vector2(p["pos"]), 90.0, 0.75, 0.6)


# ═══════════════════════════════ 生命周期 ═══════════════════════════════

func tick(delta: float) -> void:
	super.tick(delta)
	for f in _fx:
		var n = f.get("node", null)
		if not is_instance_valid(n):
			continue
		var q: float = clampf(float(f["t"]) / maxf(0.001, float(f["life"])), 0.0, 1.0)
		match str(f["kind"]):
			"flyline":
				var dn: Vector2 = Vector2(f["dir"]).normalized()
				var pos: Vector2 = Vector2(f["from"]) + dn * float(f["spd"]) * float(f["t"])
				var a3: Vector3 = battle._world_pos(pos, float(f["h"]))
				(n as Node3D).position = a3
				_point(n, a3, battle._world_pos(pos + dn * 20.0, float(f["h"])), float(f["tip"]))
			"dart":
				var tg = f.get("tgt", null)
				var to: Vector2 = Vector2(tg["pos"]) if tg is Dictionary and tg.get("alive", false) else Vector2(f["to"])
				var h1: float = BombEqVfx.body_h(tg) if tg is Dictionary else 1.0
				var p3: Vector3 = battle._world_pos(Vector2(f["from"]).lerp(to, q), lerpf(float(f["h0"]), h1, q))
				var q2: float = minf(1.0, q + 0.05)
				var p3b: Vector3 = battle._world_pos(Vector2(f["from"]).lerp(to, q2), lerpf(float(f["h0"]), h1, q2))
				(n as Node3D).position = p3
				if q2 > q:
					_point(n, p3, p3b, float(f["tip"]))
	## 插着的黑曜石匕首: 跟着目标走; 目标死了 / 换路就收
	for i in range(_stuck.size() - 1, -1, -1):
		var e: Dictionary = _stuck[i]
		var nd = e["node"]
		var tg2 = e["tgt"]
		if not is_instance_valid(nd) or not (tg2 is Dictionary) or not (tg2 as Dictionary).get("alive", false):
			if is_instance_valid(nd):
				nd.queue_free()
			_stuck.remove_at(i)
			continue
		var k: int = int(e["k"])
		var off := Vector2(float(k % 3 - 1) * 14.0, float(k / 3) * -10.0)
		(nd as Node3D).position = battle._world_pos(Vector2(tg2["pos"]) + off, BombEqVfx.body_h(tg2) + 0.15 * float(k / 3))


func clear() -> void:
	super.clear()
	for e in _stuck:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	_stuck.clear()


func alive_count() -> int:
	return super.alive_count() + _stuck.size()
