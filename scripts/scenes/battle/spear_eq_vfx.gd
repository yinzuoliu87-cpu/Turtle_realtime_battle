class_name SpearEqVfx
extends MaskEqVfx
## spear_eq_vfx.gd —— 长矛羁绊【百夫长】+ 10 件长矛 + 筹码的演出层(2026-11-26 · 方案书 20261126 / 20261126b)。结算全在 sim 侧, 这里只画。
## 继承面具演出层拿帧条工具(_strip / _tick_mfx)与炸弹层的 _ring / _anim。
## 素材来源见 tools/assetgen/pack_spear_chip_art.py 头注(全部 PixelLab 生成, 没有照参考)。
##
## 分段:
##   百夫长登场(11-26 夜重做, 用户「召唤物的登场，登场动画…别敷衍了」):
##     0 ~ 0.7 秒  落点先打下一道金色光柱(逐帧闪动), 地上影子随高度由小变大; 百夫长举着盾从 9 米高处加速落下(下落途中把盾举起)
##     0.7 秒落地  金色冲击环 + 尘土裂地(逐帧, 不是程序圆环)+ 重震屏; 全场敌人同一步被击飞(sim 在落地那一步结算, 画面对得上)
##   普攻        刺(attack 帧条, 命中帧见 AttackHits); 第 4 下掷矛: 掷矛帧条 + 一根罗马重标枪按 sim 位置飞
##   龟甲阵      举盾帧条放慢到 3 秒; 3 档的连刺 = 脚下一圈小闪; 放盾横扫 = 一圈大环; 4 档骑兵 = 奔马帧条沿 sim 路线跑
const V := "res://assets/sprites/vfx/"
const CENT_SHEETS := {"attack": "eq-centurion-attack.png", "throw": "eq-centurion-throw.png", "shield": "eq-centurion-shield.png"}
const CENT_FW := 128
const LAND_H := 9.0
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
func cent_land(p: Dictionary, sec: float) -> void:
	p["_slam_voff"] = Vector3(0.0, LAND_H, 0.0)
	_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec)})
	var beam := _strip(V + "spear-cent-beam.png", 6, battle._world_pos(Vector2(p["pos"]), 0.0), 9.5, 14.0, true, sec + 0.15, false, null, 0.0)
	if beam != null:
		## 光柱画在人后面、半透明: 原来不透明 + 渲染优先级高, 把顺着光柱落下来的百夫长整个挡住了(11-26 夜录像探针量出人在落、画面上看不见)
		beam.render_priority = -2
		beam.no_depth_test = false
		beam.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_cent_play(p, "shield", 42.0 / maxf(0.1, sec))   # 下落途中把盾举起, 落地时正好举满


func cent_impact(p: Dictionary) -> void:
	p["_slam_voff"] = Vector3.ZERO
	var d_m: float = 380.0 * float(battle.WS)   # 560 时裂坑盖住大半个场地(11-26 夜录像量过)
	_strip(V + "spear-cent-impact.png", 8, battle._world_pos(Vector2(p["pos"]), 0.07), d_m, 14.0, false, 8.0 / 14.0, true, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	## 全场击飞(11-27 用户「它是全屏击飞的」): 结算同一步, 每个敌人脚下裂地爆 + 落点到每个敌人一道贴地地裂(与 _land 同一个 _enemies_of)
	for o in battle._targeting._enemies_of(p):
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		var er := _strip(V + "spear-cent-erupt.png", 10, battle._world_pos(Vector2(o["pos"]), 0.0), ERUPT_H, 16.0, false, 10.0 / 16.0, false, null, 0.0)
		if er != null:
			er.offset = Vector2(0.0, ERUPT_ROW - ERUPT_FH * 0.5)   # 帧里地面点那一行压在敌人脚下(原 _strip 是底边着地)
		_ground_crack(Vector2(p["pos"]), Vector2(o["pos"]))


const ERUPT_H := 3.6        # 裂地爆整帧高(米; 帧 134×92, 敌方小将约 1.3 米宽)
const ERUPT_FH := 92.0      # 帧高(像素)
const ERUPT_ROW := 58.0     # 帧里地面点所在行(打包时由工作台锚点量出)
const CRACK_W := 0.9        # 贴地地裂宽(米); 一段帧 128×28


## 从 a 到 b 沿地面铺地裂: 一段 128×28 的帧条首尾相接, 段数 = 距离 / 段长取整, 每段等长(只差几成, 不拉伸像素)
func _ground_crack(a: Vector2, b: Vector2) -> void:
	if not _ok() or not ResourceLoader.exists(V + "spear-cent-crack.png"):
		return
	var d: Vector2 = b - a
	var dist_m: float = d.length() * float(battle.WS)
	if dist_m < 0.5:
		return
	var seg0: float = CRACK_W * 128.0 / 28.0
	var n: int = maxi(1, int(round(dist_m / seg0)))
	var seg: float = dist_m / float(n)
	var t: Texture2D = load(V + "spear-cent-crack.png")
	var w3: Vector3 = battle._world_pos(b, 0.0) - battle._world_pos(a, 0.0)
	var ang: float = atan2(-w3.z, w3.x)
	for i in range(n):
		var s := Sprite3D.new()
		s.texture = t
		s.hframes = 8
		s.shaded = false
		s.transparent = true
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
		s.no_depth_test = false
		s.render_priority = -1   # 贴地的先画, 单位压在上面(同 _strip flat)
		s.pixel_size = seg / 128.0
		s.flip_v = (i % 2) == 1   # 隔段上下翻: 同一段裂纹不连着重复
		s.position = battle._world_pos(a + d * ((float(i) + 0.5) / float(n)), 0.06)
		s.rotation.y = ang
		battle._world.add_child(s)
		_mfx.append({"node": s, "nf": 8, "fps": 16.0, "t": 0.0, "life": 0.5, "loop": false, "follow": null, "h": 0.0})


## 普攻(11-27 用户「普攻也没有特效」): 刺出那一下(sim 结算同一步)从矛尖朝目标射出一道金白突刺气劲(逐帧: 矛尖闪 → 光尾拉长 → 碎成火星),
##   2 档起贯穿 ⇒ 气劲一路穿到目标身后(长度 = 结算的贯穿线); 目标身上迸火星
const CENT_TIP_H := 1.3     # 矛尖离地高(米, 新画的百夫长平端长矛的高度)


func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:
	var a := Vector2(u["pos"])
	var b := Vector2(t["pos"])
	var d: Vector2 = b - a
	if d.length() < 1.0:
		d = _face(u)
	var dir := d.normalized()
	var ln: float = maxf(80.0, d.length()) + (SpearSynergySystem.LINE_LEN if n > 1 else 20.0)
	var mid: Vector2 = a + dir * (ln * 0.5)
	_dir_strip(SV + "spear-cent-thrust.png", 7, mid, dir, ln * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(b, 0.6), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)


func cent_throw(u: Dictionary, s: Dictionary) -> void:
	_cent_play(u, "throw", 20.0)
	_dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(s["pos"]) + Vector2(s["dir"]) * 90.0, Vector2(s["dir"]), 180.0 * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)   # 出手那一下的气劲
	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 2.4)
	if n != null:
		_spear_nodes.append({"s": s, "node": n})


## 11-27: 三批里程序画的圆圈全部换成画出来的帧条(用户「lion 太敷衍了吧」之后自查出 18 处)
func cent_spear_hit(o: Dictionary) -> void:
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.6, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 1.0, 16.0, false, 7.0 / 16.0, false, null, 0.0)


func cent_spear_drop(s: Dictionary) -> void:
	for r in _spear_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
	_spear_nodes = _spear_nodes.filter(func(r): return not is_same(r["s"], s))


## 龟甲阵(11-27 用户「技能特效感觉都不明显」): 举盾那一刻身前立起一面金色能量巨盾(逐帧: 光纹流过、边缘明暗、光点上飘),
##   跟着百夫长、朝最近的敌人那一侧, 半透明叠在盾前; 举盾结束收掉。落盾时扬尘 + 轻震屏
var _aegis: Array = []      # {u, node}
const AEGIS_FWD := 46.0     # 立在身前多远(码)
const AEGIS_H_M := 3.4      # 能量盾高(米)


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))
	cent_shield_off(u)
	var s := _strip(SV + "spear-cent-aegis.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), AEGIS_H_M, 10.0, true, sec, false, null, 0.0)
	if s != null:
		s.modulate = Color(1.15, 1.1, 1.0, 0.86)
		_aegis.append({"u": u, "node": s})
		_tick_aegis()
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.5)


func cent_shield_off(u: Dictionary) -> void:
	for a in _aegis:
		if is_same(a["u"], u) and a["node"] != null and is_instance_valid(a["node"]):
			_fade_out(a["node"] as Sprite3D, 0.15)
	_aegis = _aegis.filter(func(a): return not is_same(a["u"], u))


func _tick_aegis() -> void:
	var keep: Array = []
	for a in _aegis:
		var n = a["node"]
		var u: Dictionary = a["u"]
		if n == null or not is_instance_valid(n) or not u.get("alive", false):
			_free(n)
			continue
		var tg = battle._targeting._nearest_enemy(u)
		var fx: float = (1.0 if Vector2(tg["pos"]).x >= Vector2(u["pos"]).x else -1.0) if tg is Dictionary else _face(u).x
		(n as Sprite3D).position = battle._world_pos(Vector2(u["pos"]) + Vector2(fx * AEGIS_FWD, 6.0), 0.0)
		(n as Sprite3D).flip_h = fx < 0.0
		keep.append(a)
	_aegis = keep


## 3 档举盾期间每 0.5 秒刺周围: 朝范围里每个敌人各一道短突刺气劲 + 火星(结算同一步, 范围 = POKE_R)
func cent_poke(u: Dictionary) -> void:
	var a := Vector2(u["pos"])
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or DetMath.dist(Vector2(o["pos"]), a) > SpearSynergySystem.POKE_R:
			continue
		var d: Vector2 = Vector2(o["pos"]) - a
		var dir: Vector2 = d.normalized() if d.length() > 1.0 else _face(u)
		var ln: float = maxf(60.0, d.length())
		_dir_strip(SV + "spear-cent-thrust.png", 7, a + dir * (ln * 0.5), dir, ln * float(battle.WS), 28.0, 7.0 / 28.0, CENT_TIP_H * 0.8)
		_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.0, 20.0, false, 6.0 / 20.0, false, null, 0.0)


func cent_sweep(u: Dictionary) -> void:
	## 一圈金白横扫气刃贴地转开、往外甩土(spear-cent-sweep, 俯视画); 画里气刃外缘约占画布 0.8 ⇒ 按横扫半径 260 换算
	var sw := _strip(SV + "spear-cent-sweep.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), 260.0 * 2.0 * float(battle.WS) / 0.8, 16.0, false, 9.0 / 16.0, true, null, 0.0)
	if sw != null:
		sw.modulate = Color(1.35, 1.25, 1.0, 1.0)   # 11-27「技能特效感觉都不明显」: 提亮、放慢一点
	for o in battle._targeting._enemies_of(u):   # 扫到的每个敌人身上迸火星(结算同一步, 范围 = SWEEP_R)
		if o.get("alive", false) and DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= SpearSynergySystem.SWEEP_R:
			_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.3, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.6)


## 骑兵冲锋(11-27 补, 同舞狮冲撞那次用户「冲锋方向什么特效都没有吗？」): 马身后灰白风线 + 马头前一团被冲开的尘浪 + 马蹄一路扬土
##   (原画都给「朝左冲」画: 风线往右拖、尘浪往左翻 ⇒ 往右冲一律翻过来)
func cent_cav(c: Dictionary) -> void:
	var dir: Vector2 = Vector2(c["dir"])
	var fr: bool = dir.x > 0.0
	var parts: Array = []
	for spec in [["spear-cav-speed.png", 4, 1.3, 12.0, 80.0, 0.35], ["spear-cav-dustbow.png", 6, 1.5, 14.0, -50.0, 0.0]]:
		var sp := _strip(V + str(spec[0]), int(spec[1]), battle._world_pos(Vector2(c["pos"]), float(spec[5])), float(spec[2]), float(spec[3]), true, 0.0)
		if sp != null:
			sp.flip_h = fr
			parts.append({"n": sp, "back": float(spec[4]), "h": float(spec[5])})
	var n := _strip(V + "eq-cavalry-run.png", 8, battle._world_pos(Vector2(c["pos"]), 0.0), 2.6, 14.0, true, 0.0)   # 最后加 ⇒ 画在最上面
	if n != null:
		n.flip_h = fr   # 原画朝左; 往右冲就翻过来
		_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0})


func cent_cav_hit(_c: Dictionary, o: Dictionary) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 1.4, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 马蹄踏过扬土(底层扬尘)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(o["pos"]), 0.5), 1.5, 20.0, false, 6.0 / 20.0, false, null, 0.0)


func cent_cav_end(c: Dictionary) -> void:
	for r in _cav_nodes:
		if is_same(r["c"], c):
			_free(r["node"])
			for pt in r.get("parts", []):
				if pt["n"] != null and is_instance_valid(pt["n"]):
					_fade_out(pt["n"] as Sprite3D, 0.12)
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


## ── 10 件长矛的演出(11-26 夜按用户改过的机制重做; 素材来历见 pack_spear_chip_art.py, 全部 PixelLab 逐帧, 没照参考) ──
##   137 竹矛    出手处一圈尘; 浪头每推进 45 码地里刺出一丛竹刺(刺出 → 停 → 缩回, 逐帧), 一路连成一道浪
##   138 鱼叉    叉按速度飞, 尾巴拖一根绳连回携带者; 叉中后绳子绷在两人之间直到松开, 每拽一下目标脚下起尘
##   139 标枪    飞矛照旧, 命中处一点红(流血)
##   140 骑枪    冲势攒满: 头顶燃烧的枪尖标记(逐帧)亮到这一击打出; 命中: 朝出手方向的冲击波 + 尘(目标被击飞由引擎抛)
##   141 长戟    钢蓝新月横扫, 大小按这一下实际扫的半径(= 射程)、朝出手方向
##   142 盾矛    举盾: 身前立起一面大盾(0.2 秒升起, 鹰徽随存下的伤害越来越亮); 放盾: 盾收起, 扇形冲击波按结算同一速度推出去
##   143 方天画戟 蓄力: 脚下红金火焰聚气(逐帧); 跃起: 携带者真的跳起来再砸下(抛物线); 落地: 大裂坑冲击(逐帧)+ 震屏;
##              之后 4 秒脚下留余焰, 每次攻击一圈红金刃环(大小 = 结算半径)
##   144 投矛器  目标那一圈先亮红色警示圈; 矛一根根从高处按速度落下, 扎进地里起尘、矛杆抖两下(逐帧)
##   146 圣枪    (待重新设计)圣痕: 头顶金色矛十字印记; 第 3 层引爆: 金光十字炸开
const SV := "res://assets/sprites/vfx/"
const RING_FILL := 1.16   # 刃环在 128 帧里约占 110 像素 ⇒ 帧宽 = 直径 × 1.16
const CRATER_FILL := 1.1  # 裂坑冲击在 128 帧里约占 116 像素
var _stig := {}           # 目标立绘实例 id → _mfx 那一条
const ROPE_THICK_M := 0.14
var _ropes: Array = []    # 138 {a(携带者), b(目标或 null), node(绳), harp(飞行中的叉节点)}
var _lance_on := {}       # 140 携带者立绘实例 id → _mfx 那一条
var _shields: Array = []  # 142 {u, node, t, sec}
var _swv: Array = []      # 142 冲击波 {node, o, dir, r}
var _leaps: Array = []    # 143 {u, t, air}
var _fall: Array = []     # 144 {d, node, t, dur}


## 一条横排帧条, 按 2D 方向转(飞行物同款 _orient_to), 记进 _mfx 推帧 / 到时收
func _dir_strip(path: String, nf: int, at: Vector2, dir: Vector2, len_m: float, fps: float, life: float, h: float = 1.0) -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = nf
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = len_m / float(t.get_width() / nf)
	s.position = battle._world_pos(at, h)
	battle._world.add_child(s)
	_orient_to(s, dir)
	_mfx.append({"node": s, "nf": nf, "fps": fps, "t": 0.0, "life": life, "loop": false, "follow": null, "h": h})
	return s


func _uid(u: Dictionary) -> int:
	var spr = u.get("sprite", null)
	return (spr as Object).get_instance_id() if is_instance_valid(spr) else 0


func _face(u: Dictionary) -> Vector2:
	return Vector2(1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else -1.0, 0.0)


# ── 137 竹矛 ──
func bamboo_wave(u: Dictionary, _dir: Vector2) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 0.8, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 竹刺破土那一下脚下扬土


func bamboo_spike(at: Vector2, _dir: Vector2) -> void:
	_strip(SV + "spear-bamboo-spike.png", 13, battle._world_pos(at, 0.0), 1.3, 26.0, false, 13.0 / 26.0, false, null, 0.0)


# ── 138 鱼叉 ──
func harpoon_fly(u: Dictionary, tg: Dictionary):
	var n := _proj("spear-harpoon.png", Vector2(u["pos"]), Vector2(tg["pos"]) - Vector2(u["pos"]), 1.3)
	var rope := _rope_node()
	_ropes.append({"a": u, "b": null, "node": rope, "harp": n})
	return n


func _rope_node() -> Sprite3D:
	if not _ok() or not ResourceLoader.exists(SV + "spear-rope.png"):
		return null
	var t: Texture2D = load(SV + "spear-rope.png")
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 8
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.01
	battle._world.add_child(s)
	return s


func harpoon_step(node, p2: Vector2, to2: Vector2) -> void:
	if node != null and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, 1.0)
		_orient_to(node, to2 - p2)


func harpoon_end(node, hit: bool, _me: Dictionary, tg: Dictionary) -> void:
	for r in _ropes:
		if is_same(r["harp"], node):
			r["harp"] = null
			if hit and tg.get("alive", false):
				r["b"] = tg   # 叉中: 绳子改绷在两人之间, 直到 harpoon_release
				_strip(SV + "spear-harpoon-splash.png", 9, battle._world_pos(Vector2(tg["pos"]), 0.0), 1.3, 18.0, false, 9.0 / 18.0, false, null, 0.0)   # 叉中: 溅一团海水
			else:
				_free(r["node"])
				r["node"] = null
	_ropes = _ropes.filter(func(r): return r["node"] != null)
	_free(node)


func harpoon_pull(_src: Dictionary, o: Dictionary) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(o["pos"]), 0.0), 0.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 被拽一下脚下蹭起土


func harpoon_release(_src: Dictionary, o: Dictionary) -> void:
	for r in _ropes:
		if is_same(r["b"], o):
			_free(r["node"])
			r["node"] = null
	_ropes = _ropes.filter(func(r): return r["node"] != null)


func _tick_ropes() -> void:
	for r in _ropes:
		var n = r["node"]
		if n == null or not is_instance_valid(n):
			continue
		var a: Dictionary = r["a"]
		var bp: Vector3
		if r["b"] is Dictionary:
			bp = battle._world_pos(Vector2((r["b"] as Dictionary)["pos"]), 0.9)
		elif r["harp"] != null and is_instance_valid(r["harp"]):
			bp = (r["harp"] as Sprite3D).position
		else:
			continue
		var ap: Vector3 = battle._world_pos(Vector2(a["pos"]), 0.9)
		var mid: Vector3 = (ap + bp) * 0.5
		(n as Sprite3D).position = mid
		var len_m: float = maxf(0.05, Vector2(bp.x - ap.x, bp.z - ap.z).length())
		var tex: Texture2D = (n as Sprite3D).texture
		(n as Sprite3D).pixel_size = ROPE_THICK_M / float(tex.get_height())   # 粗细固定, 只沿长度方向拉(统一缩放时一拉长就粗成一条木板, 11-26 夜录像)
		_orient_screen(n, bp - ap)
		(n as Sprite3D).scale = Vector3(len_m / (float(tex.get_width()) * (n as Sprite3D).pixel_size), 1.0, 1.0)


# ── 139 标枪 ──
func javelin_bleed(tg: Dictionary) -> void:
	_strip(SV + "spear-javelin-blood.png", 7, battle._world_pos(Vector2(tg["pos"]), 0.3), 1.1, 18.0, false, 7.0 / 18.0, false, null, 0.0)   # 扎中迸血(流血)


# ── 140 骑枪 ──
func lance_ready(u: Dictionary, on: bool) -> void:
	var k := _uid(u)
	var f = _lance_on.get(k, null)
	if on:
		if f is Dictionary and is_instance_valid((f as Dictionary)["node"]):
			return
		var s := _strip(SV + "spear-lance-ready.png", 4, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.55, 10.0, true, 0.0, false, u, HEAD_H)
		if s != null:
			_lance_on[k] = _mfx.back()
	else:
		if f is Dictionary:
			_free((f as Dictionary)["node"])
		_lance_on.erase(k)


func lance_hit(u: Dictionary, t: Dictionary) -> void:
	_dir_strip(SV + "spear-lance-hit.png", 7, Vector2(t["pos"]), Vector2(t["pos"]) - Vector2(u["pos"]), 1.8, 18.0, 7.0 / 18.0, 0.8)


# ── 141 长戟 ──
func halb_sweep(u: Dictionary, fdir: Vector2, rng: float) -> void:
	var r_m: float = rng * float(battle.WS)
	var at: Vector2 = Vector2(u["pos"]) + fdir * rng * 0.45
	var s := _strip(SV + "spear-halb-sweep.png", 7, battle._world_pos(at, 0.0), maxf(1.2, r_m * 1.3), 20.0, false, 7.0 / 20.0, false, null, 0.0)
	if s != null:
		s.flip_h = fdir.x < 0.0   # 原画朝右扫
		s.position.y -= r_m * 0.25


# ── 142 盾矛 ──
func shsp_raise(u: Dictionary, sec: float) -> void:
	var s := _strip(SV + "spear-scutum.png", 4, battle._world_pos(Vector2(u["pos"]), 0.0), 1.15, 6.0, true, 0.0, false, null, 0.0)
	if s != null:
		s.scale = Vector3(1.0, 0.05, 1.0)
		_shields.append({"u": u, "node": s, "t": 0.0, "sec": sec})


func shsp_release(u: Dictionary, dir: Vector2, _sh: float, _store: float) -> void:
	for sd in _shields:
		if is_same(sd["u"], u):
			_free(sd["node"])
	_shields = _shields.filter(func(sd): return not is_same(sd["u"], u))
	var n := _dir_strip(SV + "spear-shsp-wave.png", 7, Vector2(u["pos"]), dir, 2.2, 7.0 * EqSpearBatch.SHSP_WAVE_SPD / EqSpearBatch.SHSP_WAVE_LEN, EqSpearBatch.SHSP_WAVE_LEN / EqSpearBatch.SHSP_WAVE_SPD + 0.05, 0.6)
	if n != null:
		_swv.append({"node": n, "o": Vector2(u["pos"]), "dir": dir, "r": 0.0})


func _tick_shields(delta: float) -> void:
	var keep: Array = []
	for sd in _shields:
		var u: Dictionary = sd["u"]
		var n = sd["node"]
		if n == null or not is_instance_valid(n) or not u.get("alive", false):
			_free(n)
			continue
		sd["t"] = float(sd["t"]) + delta
		var k: float = clampf(float(sd["t"]) / 0.2, 0.0, 1.0)
		(n as Sprite3D).scale = Vector3(1.0, maxf(0.05, k), 1.0)   # 0.2 秒从地上升起
		(n as Sprite3D).position = battle._world_pos(Vector2(u["pos"]) + _face(u) * 30.0, 0.0)
		var store := 0.0
		for a in (u.get("_shsp_act", {}) as Dictionary).values():
			store += float((a as Dictionary).get("store", 0.0))
		var g: float = clampf(store / maxf(1.0, float(u.get("maxHp", 1.0)) * 0.3), 0.0, 1.0)
		(n as Sprite3D).modulate = Color(1.0 + 0.7 * g, 1.0 + 0.55 * g, 1.0 + 0.1 * g, 1.0)   # 存得越多鹰徽越亮
		keep.append(sd)
	_shields = keep
	var keep2: Array = []
	for w in _swv:
		var n2 = w["node"]
		if n2 == null or not is_instance_valid(n2):
			continue
		w["r"] = minf(EqSpearBatch.SHSP_WAVE_LEN, float(w["r"]) + EqSpearBatch.SHSP_WAVE_SPD * delta)
		(n2 as Sprite3D).position = battle._world_pos(Vector2(w["o"]) + Vector2(w["dir"]) * float(w["r"]), 0.6)
		keep2.append(w)
	_swv = keep2


# ── 143 方天画戟 ──
func ftj_charge(_u: Dictionary, _frac: float) -> void:
	pass   # 挨打攒战意没有单独的画面(信息面板里有读数); 攒满那一下由 ftj_wind 起演出


func ftj_wind(u: Dictionary, wind: float, _air: float) -> void:
	_strip(SV + "spear-ftj-charge.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), 1.7, 14.0, true, wind + 0.1, false, u, 0.0)


func ftj_leap(u: Dictionary, air: float) -> void:
	_leaps.append({"u": u, "t": 0.0, "air": air})


func ftj_slam(u: Dictionary, r: float, buff: float) -> void:
	var d_m: float = r * 2.0 * float(battle.WS) * CRATER_FILL * 0.85   # 裂坑的碎石圈 ≈ 结算半径; 满尺寸不透明时铺满半个画面(11-26 夜录像)
	var cr := _strip(SV + "spear-ftj-crater.png", 9, battle._world_pos(Vector2(u["pos"]), 0.06), d_m, 14.0, false, 9.0 / 14.0, true, null, 0.0)
	if cr != null:
		cr.modulate = Color(1.0, 1.0, 1.0, 0.8)
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	var s := _strip(SV + "spear-ftj-charge.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), 1.1, 12.0, true, buff, false, u, 0.0)
	if s != null:
		s.modulate = Color(1.0, 1.0, 1.0, 0.6)   # 横扫状态里脚下留一小簇余焰


func _tick_leaps(delta: float) -> void:
	var keep: Array = []
	for l in _leaps:
		var u: Dictionary = l["u"]
		l["t"] = float(l["t"]) + delta
		var k: float = clampf(float(l["t"]) / maxf(0.05, float(l["air"])), 0.0, 1.0)
		if not u.get("alive", false) or k >= 1.0:
			u["_slam_voff"] = Vector3.ZERO
			continue
		u["_slam_voff"] = Vector3(0.0, 4.0 * 3.0 * k * (1.0 - k), 0.0)   # 抛物线, 顶点 3 米
		keep.append(l)
	_leaps = keep


# ── 144 投矛器 ──
func atl_cast(_u: Dictionary, c: Vector2, r: float) -> void:
	## 落点画一块红色警示区(俯视, 虚线边 + 往里指的矛形箭头, 循环闪), 直到最后一根矛落地; 画里圆约占画布 0.9
	_strip(SV + "spear-atl-target.png", 4, battle._world_pos(c, 0.05), r * 2.0 * float(battle.WS) / 0.9, 8.0, true,
		EqSpearBatch.ATL_SPREAD_SEC + EqSpearBatch.ATL_FALL_H / EqSpearBatch.ATL_FALL_SPD, true, null, 0.0)


func atl_drop(d: Dictionary) -> void:
	if not _ok() or not ResourceLoader.exists(SV + "spear-atl-fall.png"):
		return
	var t: Texture2D = load(SV + "spear-atl-fall.png")
	var s := Sprite3D.new()
	s.texture = t
	s.shaded = false
	s.transparent = true
	s.no_depth_test = true
	s.render_priority = 9
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.offset = Vector2(0.0, float(t.get_height()) * 0.5)
	s.pixel_size = 2.0 / float(t.get_height())   # 11-27 自查录像: 1.3 米在正常镜头下像一根细棍, 看不出是矛 ⇒ 2 米
	battle._world.add_child(s)
	var h0: float = EqSpearBatch.ATL_FALL_H * float(battle.WS)
	s.position = battle._world_pos(Vector2(d["at"]), h0)
	_fall.append({"d": d, "node": s, "t": 0.0, "dur": EqSpearBatch.ATL_FALL_H / EqSpearBatch.ATL_FALL_SPD, "h0": h0})


func atl_land(d: Dictionary, _hit: bool) -> void:
	for f in _fall:
		if is_same(f["d"], d):
			_free(f["node"])
	_fall = _fall.filter(func(f): return not is_same(f["d"], d))
	_strip(SV + "spear-atl-stuck.png", 7, battle._world_pos(Vector2(d["at"]), 0.0), 1.6, 12.0, false, 7.0 / 12.0, false, null, 0.0)


func _tick_fall(delta: float) -> void:
	for f in _fall:
		var n = f["node"]
		if n == null or not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var k: float = clampf(float(f["t"]) / float(f["dur"]), 0.0, 1.0)
		(n as Sprite3D).position = battle._world_pos(Vector2(f["d"]["at"]), float(f["h0"]) * (1.0 - k))   # 按速度匀速落


func ftj_spin(u: Dictionary) -> void:
	var d_m: float = EqSpearBatch.FTJ_R * 2.0 * float(battle.WS) * RING_FILL
	_strip(SV + "spear-ftj-ring.png", 6, battle._world_pos(Vector2(u["pos"]), 0.08), d_m, 24.0, true, 0.5, true, u, 0.08)


func holy_stigma(t: Dictionary, n: int) -> void:
	var k := _uid(t)
	var f = _stig.get(k, null)
	var s: Sprite3D = null
	if f is Dictionary and is_instance_valid((f as Dictionary)["node"]):
		s = (f as Dictionary)["node"]
		(f as Dictionary)["t"] = 0.0
	else:
		s = _strip(SV + "spear-holy-mark.png", 4, battle._world_pos(Vector2(t["pos"]), HEAD_H), 0.5, 7.0, true, 6.0, false, t, HEAD_H)
		if s != null:
			_stig[k] = _mfx.back()
	if s != null:
		var sc: float = 0.8 + 0.25 * float(n)   # 1 层 / 2 层越来越大越亮
		s.scale = Vector3(sc, sc, sc)
		s.modulate = Color(1.0 + 0.2 * float(n), 1.0 + 0.15 * float(n), 1.0, 1.0)


func holy_burst(_u: Dictionary, t: Dictionary) -> void:
	var k := _uid(t)
	var f = _stig.get(k, null)
	if f is Dictionary:
		_free((f as Dictionary)["node"])
		_stig.erase(k)
	_strip(SV + "spear-holy-burst.png", 9, battle._world_pos(Vector2(t["pos"]), 0.0), 2.2, 18.0, false, 9.0 / 18.0, false, null, 0.0)


# ── 筹码 ──
## 151 黑 / 152 紫: 开场每个友军头顶落下一枚旋转的筹码(0.5 秒落到胸口), 落下时一圈对应颜色的环(物理盾灰白 / 魔法盾紫)
var _drops: Array = []   # {f(_mfx 那一条), a(友军), t, phys}


func chip_team_shield(u: Dictionary, phys: bool) -> void:
	var side := str(u.get("side", ""))
	for a in battle._units:
		if not (a is Dictionary) or not (a as Dictionary).get("alive", false) or str((a as Dictionary).get("side", "")) != side:
			continue
		var s := _strip(SV + ("chip-spin-black.png" if phys else "chip-spin-purple.png"), 6, battle._world_pos(Vector2(a["pos"]), 2.6), 0.8, 14.0, true, 0.0, false, a, 2.6)
		if s != null:
			s.offset = Vector2.ZERO
			_drops.append({"f": _mfx.back(), "a": a, "t": 0.0, "phys": phys})


func _tick_drops(delta: float) -> void:
	var keep: Array = []
	for d in _drops:
		var f: Dictionary = d["f"]
		d["t"] = float(d["t"]) + delta
		var k: float = clampf(float(d["t"]) / 0.5, 0.0, 1.0)
		f["h"] = lerpf(2.6, 1.0, k * k)
		if k >= 1.0:
			_free(f["node"])
			var a: Dictionary = d["a"]
			if a.get("alive", false):
				var g := _strip(SV + "chip-shield-glint.png", 7, battle._world_pos(Vector2(a["pos"]), 0.5), 1.1, 18.0, false, 7.0 / 18.0, false, null, 0.0)
				if g != null:   # 落进胸口: 盾光一闪(物理灰白 / 魔法紫)
					g.modulate = Color(0.92, 0.92, 1.0, 1.0) if bool(d["phys"]) else Color(0.8, 0.55, 1.0, 1.0)
			continue
		keep.append(d)
	_drops = keep


## 153 黄: 登场 / 每挡掉一次控制 ⇒ 头顶黄色筹码转一圈(它自己的图标转一圈的帧条) + 胸口金色盾光(同一枚 0.5 秒内只画一次)
var _cc_last := {}


func chip_cc_block(u: Dictionary) -> void:
	var key: int = (u.get("sprite") as Object).get_instance_id() if is_instance_valid(u.get("sprite")) else 0
	var t := float(battle._t)
	if t - float(_cc_last.get(key, -9.0)) < 0.5:
		return
	_cc_last[key] = t
	var s := _strip(SV + "chip-spin-yellow.png", 6, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.8, 12.0, false, 6.0 / 12.0, false, u, HEAD_H)
	if s != null:
		s.offset = Vector2.ZERO
	var g := _strip(SV + "chip-shield-glint.png", 7, battle._world_pos(Vector2(u["pos"]), 0.5), 1.1, 18.0, false, 7.0 / 18.0, false, u, 0.5)
	if g != null:
		g.modulate = Color(1.0, 0.85, 0.3, 1.0)


func chip_grey_full(u: Dictionary) -> void:
	_strip(SV + "chip-grey-flare.png", 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 14.0, false, 7.0 / 14.0, false, u, 0.0)


## 155 金: 第 8 秒每个友军身上罩一个金色护罩(逐帧闪动, 半透明 —— 人隔着护罩看得见), 罩 3 秒
##   (11-26 夜录像自查: 原来只有一圈程序画的黄线, 看不出「护罩」; 用户 11-25 说过不许拿程序圆环交差)
func chip_gold_guard(u: Dictionary, sec: float) -> void:
	var side := str(u.get("side", ""))
	for a in battle._units:
		if not (a is Dictionary) or not (a as Dictionary).get("alive", false) or str((a as Dictionary).get("side", "")) != side:
			continue
		var s := _strip(SV + "chip-gold-dome.png", 6, battle._world_pos(Vector2(a["pos"]), -0.15), 2.2, 12.0, true, sec, false, a, -0.15)
		if s != null:
			s.modulate = Color(1.0, 1.0, 1.0, 0.5)


## 154 棕色筹码复活(11-26 夜): 倒地 ⇒ 一枚大棕色筹码在头顶转 2.5 秒(它自己的图标转一圈的帧条, 不借威尼斯的面具和光环);
##   身体半透明随血量变实与威尼斯同一段渲染(battle_render 读 _ven_until); 起身 ⇒ 筹码 0.15 秒落进胸口 + 一圈金棕环
var _browns: Array = []   # {u, f(_mfx 那一条), up(-1 = 未起)}


func chip_brown_down(u: Dictionary, sec: float) -> void:
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.1, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 倒地扬土
	var s := _strip(SV + "chip-spin-brown.png", 6, battle._world_pos(Vector2(u["pos"]), HEAD_H), 0.8, 10.0, true, sec + 0.5, false, u, HEAD_H)
	if s != null:
		s.offset = Vector2.ZERO
		_browns.append({"u": u, "f": _mfx.back(), "up": -1.0})


func chip_brown_up(u: Dictionary) -> void:
	for b in _browns:
		if is_same(b["u"], u):
			b["up"] = 0.0
	_strip(SV + "chip-brown-rise.png", 7, battle._world_pos(Vector2(u["pos"]), 0.0), 2.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)   # 起身: 金棕光柱带着筹码往上冲


func _tick_browns(delta: float) -> void:
	var keep: Array = []
	for b in _browns:
		var f: Dictionary = b["f"]
		if not is_instance_valid(f["node"]):
			continue
		if float(b["up"]) < 0.0:
			keep.append(b)
			continue
		b["up"] = float(b["up"]) + delta
		var k: float = clampf(float(b["up"]) / 0.15, 0.0, 1.0)
		f["h"] = lerpf(HEAD_H, 0.6, k * k)
		if k >= 1.0:
			_free(f["node"])
			continue
		keep.append(b)
	_browns = keep


# ── 帧推进 ──
func tick(delta: float) -> void:
	super.tick(delta)
	_tick_drops(delta)
	_tick_browns(delta)
	_tick_ropes()
	_tick_shields(delta)
	_tick_leaps(delta)
	_tick_fall(delta)
	_tick_aegis()
	## 百夫长从天上砸下来
	var keep: Array = []
	for l in _lands:
		var u: Dictionary = l["u"]
		l["t"] = float(l["t"]) + delta
		var k: float = clampf(float(l["t"]) / float(l["sec"]), 0.0, 1.0)
		u["_slam_voff"] = Vector3(0.0, LAND_H * (1.0 - k * k), 0.0)   # 加速落下(落地那一刻由 cent_impact 归零)
		if k >= 1.0 or not u.get("alive", false):
			u["_slam_voff"] = Vector3.ZERO
			continue
		keep.append(l)
	_lands = keep
	## 飞矛 / 投矛器的矛 / 骑兵: 位置跟 sim
	for r in _spear_nodes:
		var n = r["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).position = battle._world_pos(Vector2(r["s"]["pos"]), 1.0)
	for r3 in _cav_nodes:
		var n3 = r3["node"]
		if n3 != null and is_instance_valid(n3):
			var cp: Vector2 = Vector2(r3["c"]["pos"])
			var face: float = 1.0 if Vector2(r3["c"]["dir"]).x > 0.0 else -1.0
			(n3 as Sprite3D).position = battle._world_pos(cp, 0.0)
			for pt in r3.get("parts", []):
				if pt["n"] != null and is_instance_valid(pt["n"]):
					(pt["n"] as Sprite3D).position = battle._world_pos(cp - Vector2(face, 0.0) * float(pt["back"]), float(pt["h"]))
			r3["dust_t"] = float(r3.get("dust_t", 0.0)) + delta
			if float(r3["dust_t"]) >= 0.08:   # 马蹄一路扬土(底层扬尘)
				r3["dust_t"] = 0.0
				var ds := _strip(LION_DUST, 7, battle._world_pos(cp - Vector2(face, 0.0) * 40.0, 0.0), 0.55, 16.0, false, 7.0 / 16.0, false, null, 0.0)
				if ds != null:
					ds.flip_h = face < 0.0


func clear() -> void:
	super.clear()
	_stig.clear()
	_drops.clear()
	_browns.clear()
	_cc_last.clear()
	_lance_on.clear()
	for a in _aegis:
		_free(a["node"])
	_aegis.clear()
	for r4 in _cav_nodes:
		for pt in r4.get("parts", []):
			_free(pt["n"])
	for arr in [_spear_nodes, _cav_nodes, _ropes, _shields, _swv, _fall]:
		for r in arr:
			_free(r["node"])
	_spear_nodes.clear()
	_cav_nodes.clear()
	_ropes.clear()
	_shields.clear()
	_swv.clear()
	_fall.clear()
	for l in _leaps:
		if (l["u"] as Dictionary).has("_slam_voff"):
			(l["u"] as Dictionary)["_slam_voff"] = Vector3.ZERO
	_leaps.clear()
	_lands.clear()
