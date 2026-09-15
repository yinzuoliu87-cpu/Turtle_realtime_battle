extends Node
## verify_axe_undead_holo_vfx.gd — 096 亡灵之斧 / 全息斧 造物演出 (2026-09-15 · 方案书 20260915g「E」)
##
## ★由来: 用户「6/9亡灵斧你这是在敷衍我啊，完全没按标准来」「8/9也是，完全没达标」。
##   他的尺子(同一段对别的形态说的): 演出读得出机制 · 范围 = 判定 · 每个效果有自己的画面 · 生效有反馈。
##   原来的程序细环 / ImmediateMesh 线 / BoxMesh 方块 / 改透明度脉冲已删, 换成 Blender 烘焙帧表
##   (AxeUndeadVfx / AxeHoloVfx)。
##
## ★本门禁的规矩:
##   · 量【世界里真的节点】: 按贴图路径从 `battle._world` 里数 Sprite3D, 读 pixel_size × 帧高 ÷ WS 反推码数,
##     读 basis 判贴地, 读 position 判跟随 / 终点 —— 不数我插的标记。
##   · 「同一个模拟步」= 结算函数返回之后**不 await 任何一帧**就去数节点。
##   · 能走真入口的走真入口(`AxeSystem.tick` / `AxeSystem.on_hit` / `battle._kill`);
##     渲染层的跟随与切帧直接调产品自己的 `_render._tick_follow_vfx()` / `_tick_anim_fx()` / `_advance_anim()`。
##   · 每条关键断言配分母断言。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AF := preload("res://scripts/gamedata/axe_final_stats.gd")
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AUV := preload("res://scripts/scenes/battle/axe_undead_vfx.gd")
const AHV := preload("res://scripts/scenes/battle/axe_holo_vfx.gd")

const DT := 1.0 / 60.0

var _s = null
var _n := 0
var _fail := 0
var _made: Array = []          # 本门禁建出来的所有精灵(最后统一验 NEAREST)


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _c() -> Vector2:
	return _s.ARENA.position + _s.ARENA.size * 0.5


func _mk_axe(fk: String, off: Vector2 = Vector2.ZERO) -> Dictionary:
	var ax: Dictionary = _s._spawn._make_unit("basic", "left", _c() + off)
	_s._units.append(ax)
	ax["_eq_axe"] = true
	ax["_axe_pv"] = 4
	ax["_axe_final"] = fk
	ax["id"] = "__axe_probe__"
	ax["crit"] = 0.0
	ax["atk"] = 100.0
	ax["maxHp"] = 10000.0
	ax["hp"] = 10000.0
	ax["maxEnergy"] = AE.ACTIVE_ENERGY
	ax["energy"] = 0.0
	ax["atk_range"] = 200.0
	return ax


func _mk_owner() -> Dictionary:
	var o: Dictionary = _s._spawn._make_unit("basic", "left", _c() + Vector2(-60, 200))
	o["id"] = "__owner_probe__"
	return o


func _mk_foe(off: Vector2, hp: float = 200000.0) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", "right", _c() + off)
	_s._units.append(u)
	u["id"] = "__foe_probe__"
	u["maxHp"] = hp
	u["hp"] = hp
	u["def"] = 0.0
	u["mr"] = 0.0
	u["flat_dr"] = 0.0
	u["damage_reduction"] = 0.0
	u["shield"] = 0.0
	u["dodge_bonus"] = 0.0
	return u


func _mk_ally(off: Vector2, ratio: float) -> Dictionary:
	var a: Dictionary = _s._spawn._make_unit("basic", "left", _c() + off)
	_s._units.append(a)
	a["id"] = "__ally_probe__"
	a["maxHp"] = 5000.0
	a["hp"] = 5000.0 * ratio
	a["shield"] = 0.0
	return a


## 世界里贴图是 `path` 的活精灵(没被 queue_free 的)
func _sprites(path: String) -> Array:
	var out: Array = []
	_collect(_s._world, path, out)
	return out


func _collect(n: Node, path: String, out: Array) -> void:
	for c in n.get_children():
		if c is Sprite3D and not (c as Node).is_queued_for_deletion():
			var t: Texture2D = (c as Sprite3D).texture
			if t != null and t.resource_path == path:
				out.append(c)
		_collect(c, path, out)


func _fresh(path: String, before: Array) -> Array:
	var out: Array = []
	for s in _sprites(path):
		if not before.has(s):
			out.append(s)
			if not _made.has(s):
				_made.append(s)
	return out


func _alive_node(n) -> bool:
	return is_instance_valid(n) and not (n as Node).is_queued_for_deletion()


## 真实节点反推的世界尺寸(码): pixel_size × 单帧高 ÷ WS
func _yards(s: Sprite3D) -> float:
	return s.pixel_size * float(s.texture.get_height()) / float(_s.WS)


## 贴地 = 公告板关掉 + 贴图法线(本地 +Z)朝上
func _is_ground(s: Sprite3D) -> bool:
	return s.billboard == BaseMaterial3D.BILLBOARD_DISABLED and s.basis.z.normalized().dot(Vector3.UP) > 0.99


func _near(a: Vector3, b: Vector3, eps: float = 0.05) -> bool:
	return a.distance_to(b) < eps


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 096 亡灵之斧 / 全息斧 演出 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	## ★场景自己的 _process 会推 sim —— 本门禁手动推时钟, 关掉它免得两边一起动
	_s.set_process(false)

	_t_sheets()
	_t_u1_field()
	_t_u2_tick()
	_t_u3_death_revive()
	_t_h1_on_hit()
	_t_h2_plant()
	_t_h3_range()
	_t_nearest()

	if _n < 60:
		print("  [FAIL] ★分母: 断言只有 %d 条(<60) —— 有整段被跳过了" % _n)
		_fail += 1
	print("ALL PASS — 亡灵之斧 / 全息斧演出(%d 条)" % _n if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ══════════════════════════════════════════════════════════════
#  ⓪ 帧表规格: 在盘上、帧数对、贴地大图外缘贴着画布边、一次性表前 70% 满亮
# ══════════════════════════════════════════════════════════════
func _sheet_img(path: String) -> Image:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## 每帧【最亮那一档】的亮度(不透明像素里的最大亮度)。`fade = true` 时按 1 − f/帧数 逐帧压暗(反证用)。
## ★量「高光档还在不在」, 不量平均亮度 —— 第一版量平均亮度 ≥ 最亮帧 85%, 6 张全红:
##   平均亮度随【画了什么】变(崩散第 0 帧是亮白斧、第 3 帧是碎骨与魂火), 那不是淡出。
##   锁调色板的像素表淡出 = 高光一帧比一帧掉档, 每帧最高亮度正好卡住这个形状(反证: 人为逐帧压暗必须红)。
func _frame_peaks(img: Image, nfr: int, fade: bool) -> Array:
	var fw: int = img.get_width() / nfr
	var h: int = img.get_height()
	var step: int = maxi(1, fw / 96)
	var out: Array = []
	for f in range(nfr):
		var k: float = (1.0 - float(f) / float(nfr)) if fade else 1.0
		var top := 0.0
		for y in range(0, h, step):
			for x in range(f * fw, (f + 1) * fw, step):
				var p: Color = img.get_pixel(x, y)
				if p.a > 0.5:
					top = maxf(top, (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) * k)
		out.append(top)
	return out


## [前 70% 帧里最暗的那帧高光 ≥ 全表最高高光 × 0.85 ?, 最低, 最高]
func _hold_bright(peaks: Array, nfr: int) -> Array:
	var hold: int = int(0.7 * float(nfr))
	var top := 0.0
	for v in peaks:
		top = maxf(top, float(v))
	var lo := 9.0
	for i in range(mini(hold, peaks.size())):
		lo = minf(lo, float(peaks[i]))
	return [peaks.size() == nfr and top > 0.2 and lo >= top * 0.85, lo, top]


## 第 0 帧中线上最左 / 最右的不透明像素离帧边几格
func _rim_gap(path: String, nfr: int) -> int:
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var fw: int = img.get_width() / nfr
	var y: int = img.get_height() / 2
	var left := fw
	var right := -1
	for x in range(fw):
		if img.get_pixel(x, y).a > 0.5:
			left = mini(left, x)
			right = maxi(right, x)
	return maxi(left, fw - 1 - right)


func _t_sheets() -> void:
	print("--- ⓪ 帧表规格 ---")
	var specs := {
		AUV.TEX_FIELD: 8, AUV.TEX_PULSE: 8, AUV.TEX_SOUL: 8, AUV.TEX_DRINK: 8,
		AUV.TEX_SHATTER: 8, AUV.TEX_WAKE: 16, AUV.TEX_RISE: 8,
		AHV.TEX_FIELD: 8, AHV.TEX_DEPLOY: 8, AHV.TEX_PULSE: 8, AHV.TEX_BIT: 8,
		AHV.TEX_SHIELD: 8, AHV.TEX_BOOST: 8, AHV.TEX_HASTE: 8, AHV.TEX_GUARD: 8,
	}
	var bad: Array = []
	for p in specs:
		var tex = load(p) if ResourceLoader.exists(p) else null
		if tex == null or tex.get_width() != tex.get_height() * int(specs[p]):
			bad.append(str(p).get_file())
	_ok("★分母: 15 张帧表都在盘上且【宽 = 高 × 帧数】(横排方格)", bad.is_empty() and specs.size() == 15, str(bad))
	## 贴地的领域 / 法阵: 画布边就是判定圆 ⇒ 第 0 帧中线上的亮边必须贴着帧边(≤ 2 格)
	for p in [AUV.TEX_FIELD, AHV.TEX_FIELD]:
		var g: int = _rim_gap(p, 8)
		_ok("★%s 第 0 帧外缘离帧边 %d 格(≤2) —— 画布边 = 判定圆, 边缘画进去了才对得上" % [str(p).get_file(), g], g <= 2)
	## 一次性帧表: 前 70% 帧的高光档不许掉(淡出病)。判据 = 每帧最高亮度不低于全表最高的 85%。
	for p in [AUV.TEX_PULSE, AUV.TEX_DRINK, AUV.TEX_SHATTER, AUV.TEX_RISE, AHV.TEX_PULSE, AHV.TEX_SHIELD,
			AHV.TEX_BOOST, AHV.TEX_DEPLOY]:
		var img: Image = _sheet_img(p)
		var r: Array = _hold_bright(_frame_peaks(img, 8, false), 8) if img != null else [false, 0.0, 0.0]
		_ok("★%s 前 5 帧高光最低 %.2f ≥ 全表最高 %.2f 的 85%%(一出生就淡 = 淡出病)"
			% [str(p).get_file(), float(r[1]), float(r[2])], bool(r[0]))
	## ★反证: 同一张表人为逐帧线性压暗(= 一出生就淡), 这条判据必须红 —— 否则上面 8 条是恒真式
	var probe_img: Image = _sheet_img(AHV.TEX_SHIELD)
	var fr: Array = _hold_bright(_frame_peaks(probe_img, 8, true), 8) if probe_img != null else [true, 0.0, 0.0]
	_ok("★分母(反证): 护盾表逐帧线性压暗后判据判它不合格(前 5 帧最低 %.2f < 最高 %.2f × 0.85)"
		% [float(fr[1]), float(fr[2])], probe_img != null and not bool(fr[0]))


# ══════════════════════════════════════════════════════════════
#  ① U1 常驻亡灵领域(走真入口 AxeSystem.tick)
# ══════════════════════════════════════════════════════════════
func _t_u1_field() -> void:
	print("--- ① U1 常驻亡灵领域 ---")
	_s._units.clear()
	var axs = _s._equip_sys._axe
	var ax: Dictionary = _mk_axe("undead")
	var owner: Dictionary = _mk_owner()
	owner["_axe_ref"] = ax
	var before: Array = _sprites(AUV.TEX_FIELD)
	axs.tick(owner, DT)
	var made: Array = _fresh(AUV.TEX_FIELD, before)
	_ok("★分母: 真入口 tick 一步后世界里多出【恰好 1 片】亡灵领域", made.size() == 1, "%d 片" % made.size())
	if made.size() != 1:
		return
	var f: Sprite3D = made[0]
	_ok("★U1 领域挂在 battle._world 里", _s._world.is_ancestor_of(f))
	_ok("★U1 领域贴地(公告板关 + 法线朝上)", _is_ground(f))
	var yd: float = _yards(f)
	_ok("★★U1 领域外径 %.1f 码 = 2 × 判定半径 %.0f(演出 = 判定)" % [yd, AF.UNDEAD_RING_R],
		absf(yd - 2.0 * AF.UNDEAD_RING_R) < 1.0)
	_ok("U1 领域中心在斧头脚下", _near(f.position, _s._world_pos(ax["pos"], AUV.GROUND_Y)))
	axs.tick(owner, DT)
	_ok("★U1 再 tick 一步不重复建(仍是 1 片)", _fresh(AUV.TEX_FIELD, before).size() == 1)
	## 跟随: 挪斧头, 调产品自己的跟随层
	ax["pos"] = (ax["pos"] as Vector2) + Vector2(160, 45)
	_s._render._tick_follow_vfx()
	_ok("★★U1 斧头挪了 (160,45) 码, 领域跟着到了新脚下",
		_alive_node(f) and _near(f.position, _s._world_pos(ax["pos"], AUV.GROUND_Y)),
		"差 %.3f 米" % f.position.distance_to(_s._world_pos(ax["pos"], AUV.GROUND_Y)))
	## 循环切帧走游戏钟
	var t0: float = float(_s._t)
	_s._t = t0 + 0.26
	_s._render._tick_follow_vfx()
	var fr1: int = f.frame
	_s._t = t0 + 0.51
	_s._render._tick_follow_vfx()
	_ok("U1 领域按游戏钟循环切帧(0.26 秒 → 第 %d 帧, 0.51 秒 → 第 %d 帧)" % [fr1, f.frame], fr1 != f.frame)
	_s._t = t0
	## 死亡: 真入口 _kill
	var foe: Dictionary = _mk_foe(Vector2(900, 0))
	ax["hp"] = 0.0
	_s._kill(ax, foe)
	_ok("★分母: _kill 之后斧头死了并排上了复活", not bool(ax.get("alive", true)) and ax.has("_axe_revive_at"))
	_ok("★★U1 斧头死亡那一步领域就被释放(不等渲染帧)", not _alive_node(f))


# ══════════════════════════════════════════════════════════════
#  ② U2 每秒一跳: 环内几个敌人挨扣 ⇒ 几缕魂; 与伤害同一步
# ══════════════════════════════════════════════════════════════
func _t_u2_tick() -> void:
	print("--- ② U2 每秒一跳 ---")
	_s._units.clear()
	var axs = _s._equip_sys._axe
	var ax: Dictionary = _mk_axe("undead")
	var owner: Dictionary = _mk_owner()
	owner["_axe_ref"] = ax
	var inside: Array = [_mk_foe(Vector2(110, 0)), _mk_foe(Vector2(-60, 190)), _mk_foe(Vector2(0, -AF.UNDEAD_RING_R + 20.0))]
	var outside: Dictionary = _mk_foe(Vector2(AF.UNDEAD_RING_R + 140.0, 0))
	axs.tick(owner, DT)                       # 第一步: 领域 + 排下一跳
	var hp0: Array = []
	for e in inside:
		hp0.append(float(e["hp"]))
	var out_hp0: float = float(outside["hp"])
	var b_soul: Array = _sprites(AUV.TEX_SOUL)
	var b_pulse: Array = _sprites(AUV.TEX_PULSE)
	var b_drink: Array = _sprites(AUV.TEX_DRINK)
	ax["_undead_ring_at"] = float(_s._t) - 0.001     # 这一步该跳了
	axs.tick(owner, DT)                       # ★真入口; 之后不 await 任何一帧
	var hit_n := 0
	for i in range(inside.size()):
		if float(inside[i]["hp"]) < float(hp0[i]):
			hit_n += 1
	_ok("★分母: 这一步环内 %d 个敌人真的掉了血, 环外那个没掉" % hit_n,
		hit_n == 3 and is_equal_approx(float(outside["hp"]), out_hp0))
	var souls: Array = _fresh(AUV.TEX_SOUL, b_soul)
	_ok("★★U2 同一步建出的魂 = 挨扣的敌人数(%d 缕 / %d 人)" % [souls.size(), hit_n], souls.size() == hit_n)
	var matched := 0
	for e in inside:
		var want: Vector3 = _s._world_pos(e["pos"], float(e.get("height", 0.0)) + AUV.SOUL_FROM_H)
		for sp in souls:
			if _near((sp as Sprite3D).position, want):
				matched += 1
				break
	var at_out := false
	var want_out: Vector3 = _s._world_pos(outside["pos"], AUV.SOUL_FROM_H)
	for sp in souls:
		if _near((sp as Sprite3D).position, want_out, 0.5):
			at_out = true
	_ok("★★U2 每缕魂都从一个挨扣的敌人身上起飞(对上 %d / %d), 环外那个身上没有" % [matched, inside.size()],
		matched == inside.size() and not at_out)
	var pulses: Array = _fresh(AUV.TEX_PULSE, b_pulse)
	_ok("★★U2 同一步领域内收 1 次(贴地、外径 = 2×%.0f、从第 0 帧起)" % AF.UNDEAD_RING_R,
		pulses.size() == 1 and _is_ground(pulses[0]) and absf(_yards(pulses[0]) - 2.0 * AF.UNDEAD_RING_R) < 1.0
		and (pulses[0] as Sprite3D).frame == 0, "%d 个" % pulses.size())
	var drinks: Array = _fresh(AUV.TEX_DRINK, b_drink)
	_ok("★U2 斧头「吸到了」反馈 1 个, 挂在斧头身上",
		drinks.size() == 1 and _near((drinks[0] as Sprite3D).position, _s._world_pos(ax["pos"], AUV.DRINK_H)))
	## 分母: 空跳(环内没人) —— 仍脉动一次, 但没有魂也没有回血反馈
	for e in inside:
		e["pos"] = _c() + Vector2(AF.UNDEAD_RING_R + 400.0, 100.0)
	var b2_soul: Array = _sprites(AUV.TEX_SOUL)
	var b2_drink: Array = _sprites(AUV.TEX_DRINK)
	var b2_pulse: Array = _sprites(AUV.TEX_PULSE)
	ax["_undead_ring_at"] = float(_s._t) - 0.001
	axs.tick(owner, DT)
	_ok("★U2 空跳: 领域照样内收 1 次, 魂 0 缕、吸到了 0 个(没回血就不演回血)",
		_fresh(AUV.TEX_PULSE, b2_pulse).size() == 1 and _fresh(AUV.TEX_SOUL, b2_soul).is_empty()
		and _fresh(AUV.TEX_DRINK, b2_drink).is_empty())


# ══════════════════════════════════════════════════════════════
#  ③ U3 死亡 → 倒计时 → 复活(真入口 _kill + AxeSystem.tick)
# ══════════════════════════════════════════════════════════════
func _t_u3_death_revive() -> void:
	print("--- ③ U3 死亡 → 倒计时 → 复活 ---")
	_s._units.clear()
	_s._anim_fx.clear()
	var axs = _s._equip_sys._axe
	var ax: Dictionary = _mk_axe("undead")
	var owner: Dictionary = _mk_owner()
	owner["_axe_ref"] = ax
	var foe: Dictionary = _mk_foe(Vector2(150, 0))
	axs.tick(owner, DT)
	var b_sh: Array = _sprites(AUV.TEX_SHATTER)
	var b_wk: Array = _sprites(AUV.TEX_WAKE)
	var t_die: float = float(_s._t)
	ax["hp"] = 0.0
	_s._kill(ax, foe)
	var shs: Array = _fresh(AUV.TEX_SHATTER, b_sh)
	var wks: Array = _fresh(AUV.TEX_WAKE, b_wk)
	_ok("★分母: 死了并排上复活(%.2f 秒后)" % (float(ax.get("_axe_revive_at", 0.0)) - t_die),
		not bool(ax.get("alive", true)) and absf(float(ax.get("_axe_revive_at", 0.0)) - t_die - AF.UNDEAD_REVIVE_DELAY) < 1e-4)
	_ok("★★U3 死亡那一步崩散成亡魂(1 个, 在死亡位置)",
		shs.size() == 1 and _near((shs[0] as Sprite3D).position, _s._world_pos(ax["pos"], AUV.SHATTER_H)))
	_ok("★★U3 死亡那一步倒计时起(1 个, 贴地)", wks.size() == 1 and _is_ground(wks[0]))
	if wks.size() != 1:
		return
	var wk: Sprite3D = wks[0]
	## 逐模拟步推: 记下倒计时最后还活着的那一步、复活结算的那一步
	var t_rev: float = float(ax["_axe_revive_at"])
	var last_wake_t := -1.0
	var last_wake_fr := -1
	var alive_t := -1.0
	var untargetable_ok := true
	var b_rise: Array = _sprites(AUV.TEX_RISE)
	var b_field: Array = _sprites(AUV.TEX_FIELD)
	var rise_n := 0
	var field_n := 0
	var steps := 0
	while steps < 400:
		steps += 1
		_s._t = float(_s._t) + DT
		axs.tick(owner, DT)
		_s._render._tick_anim_fx()
		if bool(ax.get("alive", false)):
			alive_t = float(_s._t)
			rise_n = _fresh(AUV.TEX_RISE, b_rise).size()
			field_n = _fresh(AUV.TEX_FIELD, b_field).size()
			break
		for u in _s._targeting._targetable_enemies(foe):
			if is_same(u, ax):
				untargetable_ok = false
		if _alive_node(wk):
			last_wake_t = float(_s._t)
			last_wake_fr = wk.frame
	_ok("★分母: 推了 %d 步后复活(结算时刻 %.3f, 排好的时刻 %.3f)" % [steps, alive_t, t_rev],
		alive_t >= t_rev and alive_t <= t_rev + DT + 1e-6)
	_ok("★★U3 倒计时一直活到复活的上一步(%.3f), 那时已放到最后一帧(第 %d 帧)" % [last_wake_t, last_wake_fr],
		last_wake_t >= alive_t - DT - 1e-6 and last_wake_fr == AUV.WAKE_FRAMES - 1)
	_ok("★★U3 复活结算那一步倒计时收掉(演出结束 = 结算时刻 ±1 步)", not _alive_node(wk))
	_ok("★U3 复活前斧头一直不可选靶(现有行为没被破坏)", untargetable_ok)
	_ok("★★U3 复活那一步起复活柱(1 个) + 领域同步重建(1 片)", rise_n == 1 and field_n == 1,
		"柱 %d 领域 %d" % [rise_n, field_n])
	## 第二次倒下: 只崩散, 不再倒计时
	var b_sh2: Array = _sprites(AUV.TEX_SHATTER)
	var b_wk2: Array = _sprites(AUV.TEX_WAKE)
	ax["hp"] = 0.0
	_s._kill(ax, foe)
	_ok("★U3 第二次倒下: 崩散 1 个、倒计时 0 个、不排复活(一场只复活一次)",
		_fresh(AUV.TEX_SHATTER, b_sh2).size() == 1 and _fresh(AUV.TEX_WAKE, b_wk2).is_empty()
		and not ax.has("_axe_revive_at"))


# ══════════════════════════════════════════════════════════════
#  ④ H1 普攻给最低血友军盾(真入口 AxeSystem.on_hit)
# ══════════════════════════════════════════════════════════════
func _t_h1_on_hit() -> void:
	print("--- ④ H1 普攻给盾 ---")
	_s._units.clear()
	var axs = _s._equip_sys._axe
	var ax: Dictionary = _mk_axe("holo")
	## ★名单顺序故意让最低血的不在第一个(变异「随便指一个友军」在这里才红得出来)
	var high: Dictionary = _mk_ally(Vector2(-220, 0), 0.9)
	var mid: Dictionary = _mk_ally(Vector2(0, 170), 0.5)
	var low: Dictionary = _mk_ally(Vector2(330, -120), 0.2)
	var foe: Dictionary = _mk_foe(Vector2(120, 0))
	var sh0: float = float(low["shield"])
	var b_bit: Array = _sprites(AHV.TEX_BIT)
	var b_shield: Array = _sprites(AHV.TEX_SHIELD)
	var roots_before: Array = []
	for c in _s._world.get_children():
		if str(c.name).begins_with("holo_stream"):
			roots_before.append(c)
	axs.on_hit(ax, foe, true)                 # ★真入口
	_ok("★分母: 最低血那个友军拿到了 %.0f 护盾(%.0f → %.0f)" % [AF.HOLO_ONHIT_SHIELD, sh0, float(low["shield"])],
		float(low["shield"]) >= sh0 + AF.HOLO_ONHIT_SHIELD - 0.01 and float(high["shield"]) < 0.01)
	var roots: Array = []
	for c in _s._world.get_children():
		if str(c.name).begins_with("holo_stream") and not roots_before.has(c) and _alive_node(c):
			roots.append(c)
	_ok("★分母: 同一步建出 1 条数据流", roots.size() == 1, "%d 条" % roots.size())
	if roots.size() == 1:
		var r: Node3D = roots[0]
		var want: Vector3 = _s._world_pos(low["pos"], float(low.get("height", 0.0)) + AHV.BIT_TO_H)
		_ok("★★H1 数据流终点 = 血量最低那个友军(差 %.3f 米; 离另两个 %.2f / %.2f 米)"
			% [r.position.distance_to(want), r.position.distance_to(_s._world_pos(high["pos"], AHV.BIT_TO_H)),
			   r.position.distance_to(_s._world_pos(mid["pos"], AHV.BIT_TO_H))],
			_near(r.position, want))
		var bits: Array = _fresh(AHV.TEX_BIT, b_bit)
		var dist: float = (ax["pos"] as Vector2).distance_to(low["pos"])
		_ok("H1 数据块按距离分段: %.0f 码 → %d 块(应 %d)" % [dist, bits.size(), AHV.bit_count(dist)],
			bits.size() == AHV.bit_count(dist) and bits.size() >= AHV.BIT_MIN)
		var from_ok := bits.size() > 0
		for b in bits:
			if not _near((b as Sprite3D).global_position, _s._world_pos(ax["pos"], AHV.BIT_FROM_H)):
				from_ok = false
		_ok("H1 数据块从斧头那一侧出发", from_ok)
	var shields: Array = _fresh(AHV.TEX_SHIELD, b_shield)
	var follow_low := false
	if shields.size() == 1:
		for e in _s._follow_vfx:
			if e.get("spr", null) == shields[0] and is_same(e.get("unit", null), low):
				follow_low = true
	_ok("★★H1 护盾展开 1 个, 挂在那个友军身上并跟着他",
		shields.size() == 1 and follow_low
		and _near((shields[0] as Sprite3D).position, _s._world_pos(low["pos"], AHV.SHIELD_H)))


# ══════════════════════════════════════════════════════════════
#  ⑤ H2 插地 + H3 每 0.5 秒一跳(真入口 AxeSystem.tick, 逐模拟步推满 4 秒)
# ══════════════════════════════════════════════════════════════
func _t_h2_plant() -> void:
	print("--- ⑤ H2 插地 / H3 节拍 ---")
	_s._units.clear()
	var axs = _s._equip_sys._axe
	var ax: Dictionary = _mk_axe("holo")
	AxeArt.apply(_s, ax, "holo")              # 与真实召唤同一套帧表(插地帧要按形态取)
	ax["energy"] = AE.ACTIVE_ENERGY
	var owner: Dictionary = _mk_owner()
	owner["_axe_ref"] = ax
	var near_ally: Dictionary = _mk_ally(Vector2(250, 0), 0.3)
	_mk_foe(Vector2(900, 300))
	var b_dep: Array = _sprites(AHV.TEX_DEPLOY)
	var b_guard: Array = _sprites(AHV.TEX_GUARD)
	var b_pulse: Array = _sprites(AHV.TEX_PULSE)
	var t0: float = float(_s._t)
	axs.tick(owner, DT)                       # ★真入口: 龟能满 ⇒ 主动 ⇒ 插地
	_ok("★分母: 真入口 tick 后插地主动起来了(_holo_until 在)", ax.has("_holo_until"))
	var fields: Array = _fresh(AHV.TEX_DEPLOY, b_dep)
	_ok("★分母: 插地那一步法阵 1 片(展开帧)、减伤护罩 1 个",
		fields.size() == 1 and _fresh(AHV.TEX_GUARD, b_guard).size() == 1)
	if fields.size() != 1:
		return
	var f: Sprite3D = fields[0]
	var plant2d: Vector2 = ax["pos"]
	_ok("★H2 法阵挂在 battle._world 里且贴地", _s._world.is_ancestor_of(f) and _is_ground(f))
	_ok("★★H2 法阵外径 %.1f 码 = 2 × 判定半径 %.0f" % [_yards(f), AF.HOLO_AURA_R],
		absf(_yards(f) - 2.0 * AF.HOLO_AURA_R) < 1.0)
	_ok("★★H2 插地期间斧头 no_move(结算圆心 = ax.pos, 走了就对不上插地点)", bool(ax.get("no_move", false)))
	## 逐步推 4 秒: 记每一跳是不是同一步建出脉冲、法阵帧、插地帧
	var ticks := 0
	var pulse_same_step := 0
	var pulse_frame0 := 0
	var pinned := true
	var tex_at_quarter := ""
	var fr_at_quarter := -1
	var tex_at_mid := ""
	var tex_near_end := ""
	var fr_near_end := -1
	var plant_ok := 0
	var plant_samples := 0
	var freed_at := -1.0
	var until: float = float(ax["_holo_until"])
	var steps := 0
	while steps < 400:
		steps += 1
		var next_before: float = float(ax.get("_holo_next", 0.0))
		var hp_before: float = float(near_ally["hp"])
		var bp: Array = _sprites(AHV.TEX_PULSE)
		_s._t = float(_s._t) + DT
		axs.tick(owner, DT)
		_s._render._advance_anim(ax, DT)
		if not ax.has("_holo_until"):
			freed_at = float(_s._t)
			break
		if float(ax.get("_holo_next", 0.0)) != next_before:
			ticks += 1
			var np: Array = _fresh(AHV.TEX_PULSE, bp)
			if np.size() == 1 and float(near_ally["hp"]) > hp_before:
				pulse_same_step += 1
				## ★按产品自己的跟随层在【同一个游戏时刻】切一次帧再读 —— 刚建出来的精灵帧号天生是 0,
				##   不切一次就读等于量我自己的初始化(晚一帧起播的实现照样绿)
				_s._render._tick_follow_vfx()
				if (np[0] as Sprite3D).frame == 0:
					pulse_frame0 += 1
		near_ally["hp"] = 5000.0 * 0.3               # 留出回血空间, 每跳都量得到
		var el: float = float(_s._t) - t0
		if _alive_node(f) and not _near(f.position, _s._world_pos(plant2d, AHV.GROUND_Y)):
			pinned = false
		if el >= 0.25 and tex_at_quarter == "" and _alive_node(f):
			tex_at_quarter = f.texture.resource_path.get_file()
			fr_at_quarter = f.frame
		if el >= 1.0 and tex_at_mid == "" and _alive_node(f):
			tex_at_mid = f.texture.resource_path.get_file()
		## 最后一个还在插地的模拟步(离到期不足一步): 收拢必须正好倒放到第 0 帧
		if until - float(_s._t) <= DT + 1e-6 and tex_near_end == "" and _alive_node(f):
			tex_near_end = f.texture.resource_path.get_file()
			fr_near_end = f.frame
		if el >= 0.9 and el <= 3.8:
			plant_samples += 1
			if str(ax.get("anim_action", "")) == "axe_plant":
				plant_ok += 1
	_ok("★分母: 4 秒里法阵跳了 %d 次(每 %.1f 秒一次 ⇒ 应 7~8 次, 第 0 跳在插地那一步)" % [ticks, AF.HOLO_AURA_TICK],
		ticks >= 7 and ticks <= 8)
	_ok("★★H3 每一跳都在【回血结算的同一步】建出 1 道脉冲(%d / %d)" % [pulse_same_step, ticks],
		ticks > 0 and pulse_same_step == ticks)
	_ok("★★H3 每道脉冲从第 0 帧起播(%d / %d)" % [pulse_frame0, ticks], ticks > 0 and pulse_frame0 == ticks)
	_ok("★H2 法阵 4 秒里一直钉在插地点", pinned)
	_ok("★H2 插地 0.25 秒: 展开帧第 %d 帧(%s)" % [fr_at_quarter, tex_at_quarter],
		tex_at_quarter == AHV.TEX_DEPLOY.get_file() and fr_at_quarter == 4)
	_ok("★H2 插地 1 秒: 已切到循环法阵(%s)" % tex_at_mid, tex_at_mid == AHV.TEX_FIELD.get_file())
	_ok("★★H2 到期前最后一步: 收拢正好倒放到第 0 帧(%s 第 %d 帧) —— 演出不比效果长、也不提前收完"
		% [tex_near_end, fr_near_end],
		tex_near_end == AHV.TEX_DEPLOY.get_file() and fr_near_end == 0)
	_ok("★★H2 插地帧 4 秒内一直在播(采样 %d 次里 %d 次是 axe_plant)" % [plant_samples, plant_ok],
		plant_samples > 100 and plant_ok == plant_samples)
	_ok("★分母: 到期那一步是 %.3f(排好的 %.3f)" % [freed_at, until], freed_at >= until and freed_at <= until + DT + 1e-6)
	_ok("★★H2 到期那一步法阵与护罩释放", not _alive_node(f) and _fresh(AHV.TEX_GUARD, b_guard).is_empty())
	_ok("★H2 到期后 no_move 与减伤还原、斧头拔出来回待机",
		not bool(ax.get("no_move", true)) and is_equal_approx(float(ax.get("damage_reduction", -1.0)), 0.0)
		and str(ax.get("anim_action", "?")) == "")


# ══════════════════════════════════════════════════════════════
#  ⑥ H3 范围内 / 外: 反馈与加速圈只在吃到治疗的友军身上
# ══════════════════════════════════════════════════════════════
func _t_h3_range() -> void:
	print("--- ⑥ H3 范围内 / 外 ---")
	_s._units.clear()
	var fin = _s._equip_sys._axe._fin
	var ax: Dictionary = _mk_axe("holo")
	var a_in: Dictionary = _mk_ally(Vector2(300, 0), 0.5)
	var b_in: Dictionary = _mk_ally(Vector2(0, AF.HOLO_AURA_R - 50.0), 0.5)
	var c_out: Dictionary = _mk_ally(Vector2(AF.HOLO_AURA_R + 120.0, 0), 0.5)
	var hc0: float = float(c_out["hp"])
	var b_boost: Array = _sprites(AHV.TEX_BOOST)
	var b_haste: Array = _sprites(AHV.TEX_HASTE)
	## ★斧头自己也在友军名单里(`_allies_share_pool` 含召唤物本身, 距离 0) —— 结算奶到它, 演出也要有它。
	##   第一版我按「两个友军」写死期望, 门禁当场红「吃到 3 人」: 错的是我的期望, 不是产品。
	var in_range: Array = [a_in, b_in, ax]
	var n: int = fin.holo_aura_tick(ax)
	_ok("★分母: 这一跳吃到治疗 %d 人(两个友军 + 斧头自己), 范围外那个一点没回" % n,
		n == in_range.size() and is_equal_approx(float(c_out["hp"]), hc0))
	var boosts: Array = _fresh(AHV.TEX_BOOST, b_boost)
	var at_in := 0
	var at_out := false
	for u in in_range:
		for bo in boosts:
			if _near((bo as Sprite3D).position, _s._world_pos(u["pos"], AHV.BOOST_H)):
				at_in += 1
				break
	for bo in boosts:
		if _near((bo as Sprite3D).position, _s._world_pos(c_out["pos"], AHV.BOOST_H), 0.5):
			at_out = true
	_ok("★★H3 治疗/龟能反馈 = 吃到治疗的人数(%d 个, 对上 %d 人), 范围外没有" % [boosts.size(), at_in],
		boosts.size() == n and at_in == n and not at_out)
	var hastes: Array = _fresh(AHV.TEX_HASTE, b_haste)
	var marked := 0
	for u in in_range:
		if _alive_node(u.get("_holo_haste_spr", null)):
			marked += 1
	_ok("★★H3 加速圈只在吃到治疗的 %d 人身上(%d 个, 挂上 %d 人), 范围外没有" % [n, hastes.size(), marked],
		hastes.size() == n and marked == n and not _alive_node(c_out.get("_holo_haste_spr", null)))
	if hastes.size() > 0:
		_ok("H3 加速圈贴地", _is_ground(hastes[0]))
	fin.holo_aura_tick(ax)
	_ok("★H3 再跳一次不重复建加速圈(仍是 %d 个)" % n, _fresh(AHV.TEX_HASTE, b_haste).size() == n)
	## 离开范围 ⇒ buff 到期 ⇒ 圈收掉(跟随层读结算写的 haste_until)
	var sp_a = a_in["_holo_haste_spr"]
	a_in["pos"] = _c() + Vector2(AF.HOLO_AURA_R + 300.0, 0)
	var t0: float = float(_s._t)
	_s._t = float(a_in["haste_until"]) - 0.01
	_s._render._tick_follow_vfx()
	var still: bool = _alive_node(sp_a)
	_s._t = float(a_in["haste_until"]) + 0.01
	_s._render._tick_follow_vfx()
	_ok("★★H3 离开范围后加速圈跟着 buff 到期收掉(到期前还在 %s / 到期后 %s)" % [str(still), str(_alive_node(sp_a))],
		still and not _alive_node(sp_a) and not a_in.has("_holo_haste_spr"))
	_s._t = t0


# ══════════════════════════════════════════════════════════════
#  ⑦ 本门禁建出来的每一个精灵都是 NEAREST
# ══════════════════════════════════════════════════════════════
func _t_nearest() -> void:
	print("--- ⑦ NEAREST ---")
	var bad := 0
	for s in _made:
		if is_instance_valid(s) and (s as Sprite3D).texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
			bad += 1
	_ok("★分母: 本门禁一共量到 %d 个新精灵(≥ 20)" % _made.size(), _made.size() >= 20)
	_ok("★★像素帧表一律 NEAREST(LINEAR 会把像素糊掉)(违规 %d 个)" % bad, bad == 0)
