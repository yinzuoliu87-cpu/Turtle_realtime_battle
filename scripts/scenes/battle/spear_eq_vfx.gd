class_name SpearEqVfx
extends MaskEqVfx
## spear_eq_vfx.gd —— 长矛羁绊【百夫长】+ 10 件长矛 + 筹码的演出层(2026-11-26 · 方案书 20261126 / 20261126b)。结算全在 sim 侧, 这里只画。
## 继承面具演出层拿帧条工具(_strip / _tick_mfx)与炸弹层的 _ring / _anim。
## 素材来源见 tools/assetgen/pack_spear_chip_art.py 头注(全部 PixelLab 生成, 没有照参考)。
##
## 分段:
##   百夫长登场  从 6 米高处 0.3 秒砸到地上(落地那一帧全场敌人被击飞 —— sim 同帧结算), 脚下一圈尘浪
##   普攻        刺(attack 帧条, 命中帧见 AttackHits); 第 4 下掷矛: 掷矛帧条 + 一根罗马重标枪按 sim 位置飞
##   龟甲阵      举盾帧条放慢到 3 秒; 3 档的连刺 = 脚下一圈小闪; 放盾横扫 = 一圈大环; 4 档骑兵 = 奔马帧条沿 sim 路线跑
const V := "res://assets/sprites/vfx/"
const CENT_SHEETS := {"attack": "eq-centurion-attack.png", "throw": "eq-centurion-throw.png", "shield": "eq-centurion-shield.png"}
const CENT_FW := 112
const LAND_H := 6.0
const LAND_SEC := 0.3
var _cent_cache := {}
var _lands: Array = []       # {u, t}
var _spear_nodes: Array = [] # {s, node}
var _cav_nodes: Array = []   # {c, node}


func _cent_sd(key: String, fps: float) -> Dictionary:
	if not _cent_cache.has(key):
		var p: String = V + str(CENT_SHEETS[key])
		var sd := {}
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			sd = battle._sprite_dict_from(t, {"frames": t.get_width() / CENT_FW, "frameW": CENT_FW, "frameH": CENT_FW, "duration": 800}, false)
		_cent_cache[key] = sd
	var out: Dictionary = (_cent_cache[key] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func _cent_play(p: Dictionary, key: String, fps: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _cent_sd(key, fps)
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "cent_" + key, true)


func _proj(tex: String, from: Vector2, dir: Vector2, len_m: float) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(V + tex):
		return null
	var t: Texture2D = load(V + tex)
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width())
	s.position = battle._world_pos(from, 1.0)
	battle._world.add_child(s)
	_orient_to(s, dir)
	return s


# ── 百夫长 ──
func cent_land(p: Dictionary) -> void:
	p["_slam_voff"] = Vector3(0.0, LAND_H, 0.0)
	_lands.append({"u": p, "t": 0.0})


func cent_thrust(_u: Dictionary, _t: Dictionary, _n: int) -> void:
	pass   # 刺的动作走普攻节奏(AttackRhythm 播 attack 帧条), 这里不重播


func cent_throw(u: Dictionary, s: Dictionary) -> void:
	_cent_play(u, "throw", 20.0)
	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 1.9)
	if n != null:
		_spear_nodes.append({"s": s, "node": n})


func cent_spear_hit(o: Dictionary) -> void:
	_ring(Vector2(o["pos"]), 40.0, Color(1.0, 0.85, 0.6, 0.9), 0.25)


func cent_spear_drop(s: Dictionary) -> void:
	for r in _spear_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
	_spear_nodes = _spear_nodes.filter(func(r): return not is_same(r["s"], s))


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))


func cent_shield_off(_u: Dictionary) -> void:
	pass


func cent_poke(u: Dictionary) -> void:
	_ring(Vector2(u["pos"]), 200.0, Color(1.0, 0.8, 0.5, 0.55), 0.2)


func cent_sweep(u: Dictionary) -> void:
	_ring(Vector2(u["pos"]), 260.0, Color(1.0, 0.95, 0.8, 0.9), 0.4)


func cent_cav(c: Dictionary) -> void:
	var n := _strip(V + "eq-cavalry-run.png", 8, battle._world_pos(Vector2(c["pos"]), 0.0), 2.6, 14.0, true, 0.0)
	if n != null:
		n.flip_h = Vector2(c["dir"]).x > 0.0   # 原画朝左; 往右冲就翻过来
		_cav_nodes.append({"c": c, "node": n})


func cent_cav_hit(_c: Dictionary, o: Dictionary) -> void:
	_ring(Vector2(o["pos"]), 50.0, Color(1.0, 0.9, 0.7, 0.9), 0.25)


func cent_cav_end(c: Dictionary) -> void:
	for r in _cav_nodes:
		if is_same(r["c"], c):
			_free(r["node"])
	_cav_nodes = _cav_nodes.filter(func(r): return not is_same(r["c"], c))


# ── 10 件长矛 ──


func javelin_fly(u: Dictionary, tg: Dictionary):
	return _proj("spear-javelin.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 1.4)


func javelin_step(node, p2: Vector2, to2: Vector2) -> void:
	if node != null and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, 1.0)
		_orient_to(node, to2 - p2)


func javelin_end(node, _hit: bool) -> void:
	_free(node)


func eternal_fly(u: Dictionary, tg: Dictionary):
	return _proj("spear-gungnir.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 2.0)


func eternal_step(node, p2: Vector2, to2: Vector2) -> void:
	javelin_step(node, p2, to2)


func eternal_end(node, hit: bool, tg: Dictionary) -> void:
	_free(node)
	if hit and tg.get("alive", false):
		_ring(Vector2(tg["pos"]), 70.0, Color(0.85, 0.95, 1.0, 0.95), 0.4)


var _atl_nodes: Array = []


func atl_spear(s: Dictionary) -> void:
	var n := _proj("spear-dart.png", Vector2(s["pos"]), Vector2(s["dir"]), 1.0)
	if n != null:
		_atl_nodes.append({"s": s, "node": n})


func atl_end(s: Dictionary, _hit: bool) -> void:
	for r in _atl_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
	_atl_nodes = _atl_nodes.filter(func(r): return not is_same(r["s"], s))


func holy_burst(_u: Dictionary, t: Dictionary) -> void:
	_ring(Vector2(t["pos"]), 90.0, Color(1.0, 0.97, 0.75, 0.95), 0.4)


func ftj_spin(u: Dictionary) -> void:
	_ring(Vector2(u["pos"]), 170.0, Color(1.0, 0.6, 0.4, 0.8), 0.3)


# ── 筹码 ──
func chip_gold_guard(u: Dictionary, _sec: float) -> void:
	_ring(Vector2(u["pos"]), 600.0, Color(1.0, 0.85, 0.3, 0.9), 0.6)


## 154 棕色筹码复活: 暂时只有倒下 / 起身两道金棕光圈 + 身体灰白回色(battle_render); 专属素材待画(不借威尼斯面具的面具与光环)
func chip_brown_down(u: Dictionary, _sec: float) -> void:
	_ring(Vector2(u["pos"]), 110.0, Color(0.75, 0.5, 0.25, 0.9), 0.4)


func chip_brown_up(u: Dictionary) -> void:
	_ring(Vector2(u["pos"]), 180.0, Color(0.95, 0.75, 0.4, 0.95), 0.45)


# ── 帧推进 ──
func tick(delta: float) -> void:
	super.tick(delta)
	## 百夫长从天上砸下来
	var keep: Array = []
	for l in _lands:
		var u: Dictionary = l["u"]
		l["t"] = float(l["t"]) + delta
		var k: float = clampf(float(l["t"]) / LAND_SEC, 0.0, 1.0)
		u["_slam_voff"] = Vector3(0.0, LAND_H * (1.0 - k * k), 0.0)
		if k >= 1.0:
			u["_slam_voff"] = Vector3.ZERO
			_ring(Vector2(u["pos"]), 420.0, Color(0.95, 0.85, 0.65, 0.9), 0.5)
			continue
		keep.append(l)
	_lands = keep
	## 飞矛 / 投矛器的矛 / 骑兵: 位置跟 sim
	for r in _spear_nodes:
		var n = r["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).position = battle._world_pos(Vector2(r["s"]["pos"]), 1.0)
	for r2 in _atl_nodes:
		var n2 = r2["node"]
		if n2 != null and is_instance_valid(n2):
			(n2 as Sprite3D).position = battle._world_pos(Vector2(r2["s"]["pos"]), 0.9)
	for r3 in _cav_nodes:
		var n3 = r3["node"]
		if n3 != null and is_instance_valid(n3):
			(n3 as Sprite3D).position = battle._world_pos(Vector2(r3["c"]["pos"]), 0.0)


func clear() -> void:
	super.clear()
	for arr in [_spear_nodes, _cav_nodes, _atl_nodes]:
		for r in arr:
			_free(r["node"])
	_spear_nodes.clear()
	_cav_nodes.clear()
	_atl_nodes.clear()
	_lands.clear()
