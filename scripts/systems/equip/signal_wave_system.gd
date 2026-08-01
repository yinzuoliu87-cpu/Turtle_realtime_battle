class_name SignalWaveSystem
extends RefCounted
## 信号放大器038 的【弧形电磁波】—— 效果重做(用户 2026-07-30)。
##
## 需求原文:
##   「提供30%攻击速度，携带者每次普攻会获得一层放大，使自己获得1/2/5%增伤，和5%攻击速度，
##     最多叠加20层，而每获得5层，由携带者中心会爆发出巨大的电磁能量波，朝着目标以90度角度
##     发射一道缓慢移动的弧形波，造成125/250/500魔法伤害并眩晕目标2.5秒，每一次释放会使波的
##     角度增加90度，最多到360度，还会使自己获得5/7/10点魔抗穿透」
##
## ★「90度角度」按【扇形张角】理解(用户 2026-07-31 确认选 A):
##   一次发射一道张角 90° 的弧形波, 每释放一次张角 +90°(90→180→270→360 封顶),
##   到 360° 就是整圈。★若理解成"朝偏离目标 90° 的方向发射", 这一项要返工。
##
## ★★为什么单独开一个文件, 不塞进 equip_system:
##   arch_budget 把 RealtimeBattle3DScene 冻结在 8600 行(已到顶), 而这套要
##   逐帧推进 + 碰撞 + 演出, 塞哪个既有文件都是"往大文件加代码"。
##
## ★★逐帧推进【不用 tween】—— CLAUDE.md §3.5: 场景树 tween 在无头 CI 下推进不稳,
##   伤害结算绝不能挂在 tween 末尾。判定与演出同走 _tick(delta)。

# ── 需求数值(全部按【三档】写成数组, 便于 tooltip_number_audit 对上文案) ──
const ASPD_FLAT := 0.30              # 装备提供的固定攻速(不分星)
const AMP_PER_STACK := [0.01, 0.02, 0.05]   # 每层放大提供的增伤
const ASPD_PER_STACK := 0.05         # 每层放大提供的攻速
const MAX_STACKS := 20               # 放大层数上限
const EVERY := 5                     # 每满这么多层放一次波
const WAVE_DMG := [125.0, 250.0, 500.0]     # 弧形波魔法伤害
const WAVE_STUN := 2.5               # 命中眩晕(秒)
const MR_PEN := [5.0, 7.0, 10.0]     # 每次释放给自己的魔抗穿透(永久累加)
const ARC_STEP_DEG := 90.0           # 每次释放张角 +90°
const ARC_MAX_DEG := 360.0           # 张角上限
const WAVE_SPD := 260.0              # 波前推进速度(码/秒·"缓慢移动")
const WAVE_RANGE := 700.0            # 波最远推到多少码
const WAVE_BAND := 70.0              # 波前厚度(码) —— 敌人落在 [r-band, r+band] 内且在张角内才算命中
const ARC_SEG_DEG := 18.0            # 每隔多少度放一个演出片(张角越大片越多)

var battle
var _waves: Array = []               # 在途弧形波


func _init(b) -> void:
	battle = b


## 普攻命中时叠一层放大; 每满 EVERY 层放一道波。由 EquipSystem._eq_on_hit 调。
## 返回本次是否触发了波(供门禁/调试)。
func on_hit(src: Dictionary, tgt: Dictionary, si: int, stt: Dictionary) -> bool:
	var st: int = mini(MAX_STACKS, int(stt.get("sig_stacks", 0)) + 1)
	var prev: int = int(stt.get("sig_stacks", 0))
	stt["sig_stacks"] = st
	if st != prev:
		_reapply_stack_bonus(src, st, si, stt)
	# ★用"跨过 EVERY 的倍数"判, 不是"st % EVERY == 0" —— 封顶后 st 不再变,
	#   用取模会在 20 层时每次普攻都触发(20 % 5 == 0)。
	var fired_before: int = int(prev / EVERY)
	var fired_now: int = int(st / EVERY)
	if fired_now > fired_before:
		_fire(src, tgt, si, stt)
		return true
	return false


## 把"层数带来的增伤/攻速"重算一遍。
## ★先撤掉本件上一次的贡献再加新的 —— 否则每层都在旧值上叠, 20 层会翻好几倍。
##   (深海堡垒甲那类"先撤旧贡献"的写法是本项目既有惯例, 见 _eq_signal_tick 原实现。)
func _reapply_stack_bonus(u: Dictionary, stacks: int, si: int, stt: Dictionary) -> void:
	var old_amp: float = float(stt.get("sig_amp_given", 0.0))
	var old_asp: float = float(stt.get("sig_aspd_given", 0.0))
	u["damage_amp"] = maxf(0.0, float(u.get("damage_amp", 0.0)) - old_amp)
	if old_asp > 0.0:
		u["aspd_perm"] = maxf(0.01, float(u.get("aspd_perm", 1.0)) / (1.0 + old_asp))
	var new_amp: float = AMP_PER_STACK[si] * float(stacks)
	var new_asp: float = ASPD_PER_STACK * float(stacks)
	u["damage_amp"] = float(u.get("damage_amp", 0.0)) + new_amp
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) * (1.0 + new_asp)
	stt["sig_amp_given"] = new_amp
	stt["sig_aspd_given"] = new_asp


## 发一道弧形波。张角每次 +90°, 到 360° 封顶。
func _fire(src: Dictionary, tgt: Dictionary, si: int, stt: Dictionary) -> void:
	var deg: float = minf(ARC_MAX_DEG, float(stt.get("sig_arc_deg", 0.0)) + ARC_STEP_DEG)
	stt["sig_arc_deg"] = deg
	# 每次释放给自己 5/7/10 点魔抗穿透(永久累加·本场)
	src["magic_pen"] = float(src.get("magic_pen", 0.0)) + MR_PEN[si]
	src["_sig_fired_n"] = int(src.get("_sig_fired_n", 0)) + 1   # 同步触发证据(供门禁·不看有没有建节点)
	var dir: Vector2 = Vector2.RIGHT
	if tgt != null and tgt.get("alive", false):
		var d: Vector2 = tgt["pos"] - src["pos"]
		if d.length() > 0.01:
			dir = d.normalized()
	_waves.append({
		"src": src, "from": src["pos"], "dir": dir, "half": deg_to_rad(deg * 0.5),
		"deg": deg, "dmg": WAVE_DMG[si], "t": 0.0, "hit": [], "nodes": [],
	})
	battle._skill_ring(src["pos"], Color(0.45, 0.9, 1.0, 0.8), 70.0)
	battle._vfx._float_text(src["pos"] + Vector2(0, -62), "电磁波 %d°" % int(deg), Color("#7fe8ff"))


## 每帧推进所有在途弧形波(由 RealtimeBattle3DScene 的 sim tick 调)。
func tick(delta: float) -> void:
	if _waves.is_empty():
		return
	var keep: Array = []
	for w in _waves:
		var src: Dictionary = w["src"]
		if not src.get("alive", false):
			_free_nodes(w)
			continue
		w["t"] = float(w["t"]) + delta
		var r: float = float(w["t"]) * WAVE_SPD
		if r >= WAVE_RANGE:
			_free_nodes(w)
			continue
		_place_nodes(w, r)
		for o in _hit_at(w, r):
			(w["hit"] as Array).append(o)
			_apply(src, o, float(w["dmg"]))
		keep.append(w)
	_waves = keep


## 此刻波前扫到的、还没打过的敌人。
## ★命中条件两条都要: ①径向落在波前厚度内 ②角向落在张角内。
## ★已命中名单用 is_same 比对, 绝不拿单位字典当 Dictionary 的键(CLAUDE.md §3.2 递归哈希卡死)。
func _hit_at(w: Dictionary, r: float) -> Array:
	var out: Array = []
	var src: Dictionary = w["src"]
	var from2d: Vector2 = w["from"]
	var dir: Vector2 = w["dir"]
	var half: float = float(w["half"])
	var already: Array = w["hit"]
	for o in battle._targeting._pick_enemies_of(src):
		var rel: Vector2 = o["pos"] - from2d
		var dist: float = rel.length()
		if absf(dist - r) > WAVE_BAND:
			continue
		# 张角判定: 360° 时全向命中(免得浮点角度比较在整圈边界上抖)
		if float(w["deg"]) < ARC_MAX_DEG - 0.01:
			if dist > 0.01 and absf(dir.angle_to(rel)) > half:
				continue
		var dup := false
		for h in already:
			if is_same(h, o):
				dup = true
				break
		if not dup:
			out.append(o)
	return out


## 命中一个敌人的【纯效果】: 魔法伤害 + 眩晕。
## ★抽成独立函数, 门禁可直接调它验数值, 不用等波扫到。
func _apply(src: Dictionary, o: Dictionary, dmg: float) -> void:
	if not o.get("alive", false):
		return
	battle._damage._apply_damage_from(src, o, battle._resolve_dmg(src, dmg, o, true),
		Color("#7fe8ff"), 0.0, false, true)          # 魔法伤害(走魔抗·与文案一致)
	o["stun_until"] = maxf(float(o.get("stun_until", 0.0)), battle._t + WAVE_STUN)
	o["_sig_hit_n"] = int(o.get("_sig_hit_n", 0)) + 1   # 同步触发证据(供门禁)
	battle._skill_ring(o["pos"], Color(0.55, 0.92, 1.0, 0.85), 44.0)


## 演出: 沿弧线摆一串发光片, 随波前外推。
## ★节点数按张角算(每 ARC_SEG_DEG 一片) —— 360° 时约 20 片, 不会爆。
## 画一道【实心环形扇带】—— 这才是"扇形波"。
##
## ★★2026-08-01 重做(用户:「什么是扇形波你不懂吗」)。原来是沿弧线摆一串发光公告板 ——
##   那是【虚线】不是扇形波: 没有厚度、没有实体感、张角变大只是点变多。
##   现在用 ImmediateMesh 画真几何(与水晶扫描 _crystal_sweep_step 同一套技术):
##     · 内外两条弧(r-BAND .. r+BAND)之间连三角带 = 有厚度的扇带
##     · 颜色从内缘暗、外缘(波前)亮白 = 冲击波该有的"前沿最烈"
##     · 张角 90°→360° 时它就是一整圈实心环, 而不是一圈点
## ★每帧重建 surface(顶点数随张角变), 与水晶扫描同代价; 波是短命的(≤2.7秒), 不做池化。
func _place_nodes(w: Dictionary, r: float) -> void:
	if battle._world == null:
		return
	var im: MeshInstance3D = w.get("mesh", null)
	var imesh: ImmediateMesh = w.get("imesh", null)
	if not is_instance_valid(im):
		im = MeshInstance3D.new()
		imesh = ImmediateMesh.new()
		im.mesh = imesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD       # 加色 = 能量波该有的发光
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		im.material_override = mat
		im.set_meta("mat", mat)
		battle._world.add_child(im)
		w["mesh"] = im
		w["imesh"] = imesh
	var mat2: StandardMaterial3D = im.get_meta("mat")
	var from2d: Vector2 = w["from"]
	var base: float = (w["dir"] as Vector2).angle()
	var half: float = float(w["half"])
	var segs: int = clampi(int(float(w["deg"]) / 6.0), 8, 90)    # 6° 一段 → 弧看着是圆的不是折线
	var fade: float = clampf(1.0 - r / WAVE_RANGE, 0.12, 1.0)
	# ★视觉厚度【比判定厚度薄】: 判定是 ±WAVE_BAND(70码), 但画满 140 码宽会糊成一坨云。
	#   画 0.62 倍 → 看着是"一道冲击波"而不是"一片雾"。判定不变(不是改玩法)。
	var r_in: float = maxf(2.0, r - WAVE_BAND * 0.62)
	var r_out: float = r + WAVE_BAND * 0.22                      # 前沿更薄 = 冲得更利
	# 配色迭代二: 第一版 c_out 近纯白 + 高 alpha, 加色叠出来是一块【白板】, 不像电磁波。
	#   现在压低整体不透明度、把主体推向青蓝, 只有最外一条crest保留近白 → 读起来是"电"不是"墙"。
	# 配色迭代三: 二版还是偏灰白(加色下低饱和会被背景冲淡)。现在把主体推到高饱和青,
	#   靠"蓝绿差"而不是靠亮度来立住 —— 暗海底背景上青色才跳得出来。
	var c_in := Color(0.02, 0.34, 0.90, 0.04 * fade)             # 内缘: 几乎透明(拖尾)
	var c_mid := Color(0.06, 0.78, 1.00, 0.16 * fade)   # 迭代四: 再压薄内部, 让波前+电弧主导(原来像一块平板)
	var c_out := Color(0.24, 0.96, 1.00, 0.52 * fade)            # 波前: 高饱和青
	imesh.clear_surfaces()
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat2)
	for i in range(segs):
		var t0: float = float(i) / float(segs) * 2.0 - 1.0
		var t1: float = float(i + 1) / float(segs) * 2.0 - 1.0
		var a0: float = base + half * t0
		var a1: float = base + half * t1
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		# ★波前【锯齿脉动】= 电磁的"炸毛"感。用角度+时间的确定性函数, 不用随机 ——
		#   本项目有 rng_discipline 门禁(裸随机会破坏对局确定性), 演出也一并守这条。
		var j0: float = sin(a0 * 17.0 + float(w["t"]) * 34.0) * 7.0
		var j1: float = sin(a1 * 17.0 + float(w["t"]) * 34.0) * 7.0
		var vi0: Vector3 = battle._world_pos(from2d + d0 * r_in, 0.55)
		var vi1: Vector3 = battle._world_pos(from2d + d1 * r_in, 0.55)
		var vo0: Vector3 = battle._world_pos(from2d + d0 * (r_out + j0), 0.55)
		var vo1: Vector3 = battle._world_pos(from2d + d1 * (r_out + j1), 0.55)
		# 内→外两个三角(带渐变: 内暗外亮)
		imesh.surface_set_color(c_in);  imesh.surface_add_vertex(vi0)
		imesh.surface_set_color(c_in);  imesh.surface_add_vertex(vi1)
		imesh.surface_set_color(c_out); imesh.surface_add_vertex(vo1)
		imesh.surface_set_color(c_in);  imesh.surface_add_vertex(vi0)
		imesh.surface_set_color(c_out); imesh.surface_add_vertex(vo1)
		imesh.surface_set_color(c_out); imesh.surface_add_vertex(vo0)
	imesh.surface_end()
	# 波前那条亮线(让"边缘"读得出来, 不然实心块看不出在推进)
	imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat2)
	for i in range(segs + 1):
		var tt: float = float(i) / float(segs) * 2.0 - 1.0
		var aa: float = base + half * tt
		var jj: float = sin(aa * 17.0 + float(w["t"]) * 34.0) * 7.0
		imesh.surface_set_color(Color(0.86, 0.99, 1.00, 0.92 * fade))   # crest 只有这一条近白
		imesh.surface_add_vertex(battle._world_pos(from2d + Vector2(cos(aa), sin(aa)) * (r_out + jj), 0.6))
	imesh.surface_end()
	# ★径向电弧: 沿张角每隔几段拉一条内→外的亮线, 是"电磁"而不是"水波"的关键特征。
	#   条数随张角走(90°约4条, 360°约16条), 相位随时间滚动 → 看着在噼啪窜。
	var spokes: int = clampi(int(float(w["deg"]) / 22.0), 3, 18)
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat2)
	for k in range(spokes):
		var ts: float = (float(k) + 0.5) / float(spokes) * 2.0 - 1.0
		var as_: float = base + half * ts
		var ds := Vector2(cos(as_), sin(as_))
		var flick: float = 0.45 + 0.55 * absf(sin(float(k) * 2.3 + float(w["t"]) * 26.0))
		var cs := Color(0.55, 0.98, 1.00, 0.80 * fade * flick)
		imesh.surface_set_color(Color(cs.r, cs.g, cs.b, 0.0))
		imesh.surface_add_vertex(battle._world_pos(from2d + ds * r_in, 0.58))
		imesh.surface_set_color(cs)
		imesh.surface_add_vertex(battle._world_pos(from2d + ds * (r_out + sin(as_ * 17.0 + float(w["t"]) * 34.0) * 7.0), 0.58))
	imesh.surface_end()
	# 中段稍暗的一条, 给扇带一点"体积"
	imesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat2)
	for i in range(segs + 1):
		var tm: float = float(i) / float(segs) * 2.0 - 1.0
		var am: float = base + half * tm
		imesh.surface_set_color(c_mid)
		imesh.surface_add_vertex(battle._world_pos(from2d + Vector2(cos(am), sin(am)) * ((r_in + r_out) * 0.5), 0.57))
	imesh.surface_end()


func _free_nodes(w: Dictionary) -> void:
	for nd in (w.get("nodes", []) as Array):
		if is_instance_valid(nd):
			(nd as Node).queue_free()
	w["nodes"] = []
	var im = w.get("mesh", null)
	if is_instance_valid(im):
		(im as Node).queue_free()
	w["mesh"] = null
	w["imesh"] = null
