extends Node
## verify_eq_relic_batch.gd — 遗物 2 件(091 远古龟甲片 / 094 祖龟碑)逐条焊死 + 演出几何门禁
##
## 规格: docs/plans/20260805-装备逐件重做.md §0.5 ★091 / ★094【用户逐件亲手写的定稿】
## 契约: docs/plans/20260806-实装契约-批④.md
## 实装: scripts/systems/equip/eq_relic_batch.gd · 演出: scripts/scenes/battle/relic_eq_vfx.gd
##
## ★本文件的规矩(契约 §8, 逐条对应 CLAUDE.md / memory):
##   · 全部用【干净合成单位】—— 随机 spawn 的敌带盾/flat_dr/未播种 RNG 会让精确数值
##     在 CI 上偶发红(memory [[fb-ci-vs-local-divergence]])。
##   · 合成单位坐标放 ARENA 【内】—— 放外面会被钳到同一点(500 帧红 1500 帧绿那次)。
##   · 期望值一律【写字面量】, **绝不引用被测的那个常量** —— 引用常量就是拿代码跟自己比。
##     (唯一例外是"两处必须相等"这类同一性断言, 那本来就要读两边。)
##   · 减伤/增伤验的是**实际打出来的血量差**, **不重实现一遍 resist 公式跟自己比**(恒真式)。
##   · 触发一律走【真入口】: `_eq_tick`(091 的每帧)/`_eq_on_death` 与 `battle._kill`(094 立碑)/
##     本系统自己的 `tick()`(石雷节拍)。memory [[fb-verify-must-run-the-real-path]]:
##     「断言函数存在」守不住「还有没有人调它」。
##   · **不依赖任何 tween**(CLAUDE.md §3.5): 演出全由 `tick(delta)` 同步推进。
##   · 美术断言量**真实节点/真实材质**, 不是在测试里把公式抄一遍
##     (memory [[fb-write-without-reader-and-fake-gates]]: 抄公式的门禁, 产品改成写死也照样绿)。
##   · 每组带一条【分母】断言 —— N=0 是空检查不是通过。
##
## 跑法: <godot> --headless --path . res://tests/verify_eq_relic_batch.tscn --quit-after 3000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## ★2026-08-07 表现层放大后的【设计值】—— 写字面值, **不引用 RelicEqVfx 的常量**
##   (引用就是拿代码跟它自己比 = 恒真式)。改了演出层的尺寸就要同步改这两行, 这正是本门禁的作用。
##   · 甲片外接圆 13 → 21 码: 13 码在实战默认视角只有 17.6×13.7 屏幕像素, 整环跨度 30 px
##   · 碑高 1.90 → 2.95 米:   1.90 米只有 22.5×33.5 屏幕像素, 碑面上刻什么都是 2~3 px
##   两条的可见性判据由 tests/verify_eq_vfx_visibility.gd 单独守。
const WANT_PLATE_R_PX := 21.0
## ★2026-08-09 碑体重做后 2.95 → 3.60 米: 屏幕 63.4 px 高(龟立绘 44 px), 碑该是地标。
const WANT_STELE_H := 3.60
## 实战默认视角的两把尺子(字面值, 与 verify_eq_vfx_visibility 同源):
## 相机 (0,28,22) look_at (0,0.6,0) fov40 ⇒ 横向 28.14758 px/米、世界竖直 17.62155 px/米。
const PX_PER_M_LIT := 28.147577
const PX_PER_M_VERT_LIT := 17.621551

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _near(a: float, b: float, eps: float = 1e-4) -> bool:
	return absf(a - b) <= eps


## 一张立绘片投到实战镜头屏幕上的**包围盒尺寸(像素)**。
## ★量的是四个真实顶点经 `global_transform` 之后的世界坐标, 再乘两把尺子 ——
##   不是"拿 scale 乘一乘"(那样父节点的补偿、旋转都会被漏掉, 正是要抓的那个 bug)。
func _screen_wh(sp: Sprite3D) -> Vector2:
	if sp == null or sp.texture == null:
		return Vector2.ZERO
	var hw: float = float(sp.texture.get_width()) * sp.pixel_size * 0.5
	var hh: float = float(sp.texture.get_height()) * sp.pixel_size * 0.5
	var gx: Transform3D = sp.global_transform
	var xs: Array = []
	var ys: Array = []
	for c in [Vector3(-hw, -hh, 0.0), Vector3(hw, -hh, 0.0), Vector3(hw, hh, 0.0), Vector3(-hw, hh, 0.0)]:
		var w: Vector3 = gx * (c as Vector3)
		xs.append(w.x)
		ys.append(w.y)
	xs.sort()
	ys.sort()
	return Vector2((float(xs[3]) - float(xs[0])) * PX_PER_M_LIT,
		(float(ys[3]) - float(ys[0])) * PX_PER_M_VERT_LIT)


## 干净合成单位。★用 `fortune` 不用 `basic`: 小龟·不屈会给小龟造成的一切伤害 +20%。
func _mk(side: String, off: Vector2, hp: float = 100000.0, spec: Dictionary = {}) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("fortune", side, c + off, spec)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["dodge_bonus"] = 0.0
	u["damage_reduction"] = 0.0
	u["damage_amp"] = 0.0
	u["crit"] = 0.0
	u["crit_dmg"] = 1.5
	u["heal_amp"] = 0.0
	u["shield_amp"] = 0.0
	u["reflect"] = 0.0
	u["lifesteal"] = 0.0
	u["ls_bonus"] = 0.0
	u["armor_pen"] = 0.0
	u["magic_pen"] = 0.0
	u["armor_pen_pct"] = 0.0
	u["magic_pen_pct"] = 0.0
	u["heal_reduce_until"] = 0.0
	u["heal_reduce_pct"] = 0.0
	u["dots"] = []
	u["buffs"] = []
	u["equips"] = []
	u["eq_state"] = {}
	_s._units.append(u)
	return u


func _equip(u: Dictionary, entries: Array) -> Dictionary:
	u["equips"] = entries
	u["eq_state"] = {}
	u["_b4_eq"] = true
	return u


## 剥掉行内注释后的源码(否则会命中我自己写的说明文字 —— 前几份门禁的作者都吃过这个亏)。
func _strip(path: String) -> String:
	var raw: String = FileAccess.get_file_as_string(path)
	var out := ""
	for ln in raw.split("\n"):
		var hi: int = ln.find("#")
		out += (ln if hi < 0 else ln.substr(0, hi)) + "\n"
	return out


## 清掉本轮造的所有单位(每组之间互不污染)。
func _reset_units() -> void:
	_s._equip_sys._relic_sys.clear_all()
	_s._units.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 遗物 2 件(091 远古龟甲片 / 094 祖龟碑) ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0        # 决胜增伤会给【所有】伤害再乘一次, 关掉才量得准

	_t_wiring()
	_t_discipline()
	_t_stats()
	_t091_amount()
	_t091_cliff()
	_t091_cadence()
	_t091_healcut()
	_t091_multi_copy()
	_t091_endtoend()
	_t094_raise()
	await _t094_global_tick_wired()
	_t094_aura_scope()
	_t094_aura_stack()
	_t094_resist_real()
	_t094_amp_real()
	_t094_bolt()
	_t094_lane()
	await _t_vfx_geometry()

	_s._equip_sys._relic_sys.clear_all()
	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 遗物 2 件" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ═════════════════════════════════════════════════════════════
# ⓪ 接线 —— 091/094 真的被路由到本系统, 而且演出层真的被 new 出来了
# ═════════════════════════════════════════════════════════════
func _t_wiring() -> void:
	print("── ⓪ 接线 ──")
	var owner: Dictionary = _s._equip_sys.B4_OWNER
	_ok("B4_OWNER 有 091", str(owner.get("p2eq_091", "")) == "relic", "→ %s" % str(owner.get("p2eq_091", "(缺)")))
	_ok("B4_OWNER 有 094", str(owner.get("p2eq_094", "")) == "relic", "→ %s" % str(owner.get("p2eq_094", "(缺)")))
	var sys = _s._equip_sys._relic_sys
	_ok("_relic_sys 已构造", sys != null and sys is EqRelicBatch)
	_ok("_b4(091) 指向本系统", sys != null and _s._equip_sys._b4("p2eq_091") == sys)
	_ok("_b4(094) 指向本系统", sys != null and _s._equip_sys._b4("p2eq_094") == sys)
	_ok("演出层已构造", sys != null and sys.vfx != null and sys.vfx is RelicEqVfx)
	# ★"函数存在"不算接线证据 —— 这里断言的是【六个批系统的 tick 遍历里真的有我这一个】
	var all: Array = _s._equip_sys._b4_all()
	var found := false
	for x in all:
		if x == sys:
			found = true
	_ok("_b4_all() 含本系统(全局 tick 能扫到)", found, "N=%d" % all.size())


# ═════════════════════════════════════════════════════════════
# ① 三条焊死的口径 —— 源码级(剥注释后扫)
# ═════════════════════════════════════════════════════════════
func _t_discipline() -> void:
	print("── ① 三条焊死的口径 ──")
	var src: String = _strip("res://scripts/systems/equip/eq_relic_batch.gd")
	var vsrc: String = _strip("res://scripts/scenes/battle/relic_eq_vfx.gd")
	_ok("源码分母", src.length() > 3000 and vsrc.length() > 3000,
		"eq=%d 字符 · vfx=%d 字符" % [src.length(), vsrc.length()])

	# ①-a 零裸随机(唯一允许的随机是 battle._battle_rng.*)
	var bare := 0
	for pat in ["randi(", "randf(", "randfn(", "randi_range(", "randf_range("]:
		var i: int = src.find(pat)
		while i >= 0:
			var pre: String = src.substr(maxi(0, i - 12), mini(12, i))
			if not pre.ends_with("_battle_rng."):
				bare += 1
			i = src.find(pat, i + 1)
		var j: int = vsrc.find(pat)
		while j >= 0:
			var pre2: String = vsrc.substr(maxi(0, j - 12), mini(12, j))
			if not pre2.ends_with("_battle_rng."):
				bare += 1
			j = vsrc.find(pat, j + 1)
	_ok("口径①: 零裸随机", bare == 0, "裸调用 %d 处" % bare)

	# ①-b 每一段伤害都 from_equip = true
	var dmg_lines := 0
	var dmg_ok := 0
	for ln in src.split("\n"):
		if ln.find("_apply_damage_from(") >= 0:
			dmg_lines += 1
			if ln.find("false, true)") >= 0:
				dmg_ok += 1
	_ok("口径②: 伤害调用点分母", dmg_lines >= 1, "N=%d" % dmg_lines)
	_ok("口径②: 每段伤害都 from_equip=true", dmg_lines > 0 and dmg_ok == dmg_lines,
		"%d/%d" % [dmg_ok, dmg_lines])

	# ①-c `_t` 不做"和常数比"的计时(必须自管累加器)
	var bad_t := 0
	for ln in src.split("\n"):
		if ln.find("battle._t") < 0:
			continue
		for op in [">=", "<=", " > ", " < "]:
			if ln.find(op) >= 0:
				bad_t += 1
				break
	_ok("口径③: `_t` 不参与任何比较(全自管累加器)", bad_t == 0, "违规 %d 行" % bad_t)

	# ①-d 演出不靠 tween(CLAUDE.md §3.5)
	_ok("演出零 create_tween", src.find("create_tween") < 0 and vsrc.find("create_tween") < 0)
	_ok("演出零 _reg_tween", src.find("_reg_tween") < 0 and vsrc.find("_reg_tween") < 0)

	# ①-e 093 不归本批
	_ok("不碰 093(归主会话)", src.find("p2eq_093") < 0 and vsrc.find("p2eq_093") < 0)

	# ①-f 选靶走标准函数, 没有就地手写(memory [[fb-hand-rolled-copies-drift]])
	_ok("选靶走 _targeting._nearest_enemy_from", src.find("_targeting._nearest_enemy_from(") >= 0)

	# ①-g 双抗必须走 buffs 通道 —— 直接写 u["def"] 会被 _recalc_stats 抹掉
	_ok("双抗走 buffs 而不是直写 def/mr",
		src.find("\"stat\": \"def\"") >= 0 and src.find("\"stat\": \"mr\"") >= 0
		and src.find("o[\"def\"] =") < 0 and src.find("o[\"mr\"] =") < 0)


# ═════════════════════════════════════════════════════════════
# ② STATS 三星属性(规格 §0.5 用户指定, 一个数都不许改)
# ═════════════════════════════════════════════════════════════
func _t_stats() -> void:
	print("── ② STATS 三星属性 ──")
	var a: Array = _s.EquipStats.STATS.get("p2eq_091", [])
	_ok("091 三星分母", a.size() == 3, "N=%d" % a.size())
	if a.size() == 3:
		_ok("091 攻击 5/12/20", float(a[0].get("atk", 0)) == 5.0 and float(a[1].get("atk", 0)) == 12.0 and float(a[2].get("atk", 0)) == 20.0,
			"%s/%s/%s" % [a[0].get("atk", 0), a[1].get("atk", 0), a[2].get("atk", 0)])
		_ok("091 射程 +50 三星同值", float(a[0].get("_rangeAdd", 0)) == 50.0 and float(a[1].get("_rangeAdd", 0)) == 50.0 and float(a[2].get("_rangeAdd", 0)) == 50.0)
		_ok("091 护甲 6/13/22", float(a[0].get("def", 0)) == 6.0 and float(a[1].get("def", 0)) == 13.0 and float(a[2].get("def", 0)) == 22.0,
			"%s/%s/%s" % [a[0].get("def", 0), a[1].get("def", 0), a[2].get("def", 0)])
	var b: Array = _s.EquipStats.STATS.get("p2eq_094", [])
	_ok("094 三星分母", b.size() == 3, "N=%d" % b.size())
	if b.size() == 3:
		_ok("094 攻击 25/62/140", float(b[0].get("atk", 0)) == 25.0 and float(b[1].get("atk", 0)) == 62.0 and float(b[2].get("atk", 0)) == 140.0)
		_ok("094 破甲 6/13/22", float(b[0].get("armorPen", 0)) == 6.0 and float(b[1].get("armorPen", 0)) == 13.0 and float(b[2].get("armorPen", 0)) == 22.0)
		_ok("094 生命 120/300/700", float(b[0].get("hp", 0)) == 120.0 and float(b[1].get("hp", 0)) == 300.0 and float(b[2].get("hp", 0)) == 700.0)
		_ok("094 移速 5/9/14", float(b[0].get("_mspdPct", 0)) == 5.0 and float(b[1].get("_mspdPct", 0)) == 9.0 and float(b[2].get("_mspdPct", 0)) == 14.0)


# ═════════════════════════════════════════════════════════════
# ③ 091 每跳回复量 —— 期望值直接抄规格 §0.5 的量级表(折合每秒)
#    规格表(平时, 每秒 4 跳):
#      maxHp 3000 → 1★ 16/秒 · 2★ 26/秒 · 3★ 36/秒
#      maxHp 6000 → 1★ 28/秒 · 2★ 44/秒 · 3★ 60/秒
# ═════════════════════════════════════════════════════════════
func _t091_amount() -> void:
	print("── ③ 091 每跳回复量(对规格量级表) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var cases := [
		[3000.0, 0, 16.0], [3000.0, 1, 26.0], [3000.0, 2, 36.0],
		[6000.0, 0, 28.0], [6000.0, 1, 44.0], [6000.0, 2, 60.0],
	]
	var n := 0
	for cs in cases:
		var mx: float = float(cs[0])
		var si: int = int(cs[1])
		var per_sec: float = float(cs[2])
		var u: Dictionary = _mk("left", Vector2(-200 + n * 8, -120), mx)
		var got: float = sys.scute_amount(u, si) * 4.0
		n += 1
		_ok("091 %d★ maxHp %d → %.0f/秒" % [si + 1, int(mx), per_sec], _near(got, per_sec, 1e-3),
			"实测 %.3f/秒" % got)
	_ok("③ 分母", n == 6, "N=%d" % n)
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ④ 25% 那道悬崖 —— 用户 2026-08-06 拍板【严格低于】
#    规格量级表(<25% 时, 3★):
#      maxHp 945 → 117/秒 · 3000 → 216/秒 · 6000 → 360/秒
# ═════════════════════════════════════════════════════════════
func _t091_cliff() -> void:
	print("── ④ 091 的 25% 悬崖(严格「低于」) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var u: Dictionary = _mk("left", Vector2(-200, -80), 4000.0)
	# 24.9% / 25.0% / 25.1% —— 三个点都要有断言
	u["hp"] = 4000.0 * 0.249
	_ok("24.9% → 翻 6 倍", _near(sys.scute_mult(u), 6.0), "mult=%.3f" % sys.scute_mult(u))
	u["hp"] = 1000.0                                   # 4000×0.25 精确
	_ok("25.0% 整 → 不翻(严格低于)", _near(sys.scute_mult(u), 1.0), "mult=%.3f" % sys.scute_mult(u))
	u["hp"] = 4000.0 * 0.251
	_ok("25.1% → 不翻", _near(sys.scute_mult(u), 1.0), "mult=%.3f" % sys.scute_mult(u))
	u["hp"] = 0.0
	_ok("0% → 翻 6 倍", _near(sys.scute_mult(u), 6.0), "mult=%.3f" % sys.scute_mult(u))
	# 规格量级表(3★ 爆发态)
	var cases := [[945.0, 117.36], [3000.0, 216.0], [6000.0, 360.0]]
	var n := 0
	for cs in cases:
		var mx: float = float(cs[0])
		var v: Dictionary = _mk("left", Vector2(-160 + n * 8, -80), mx)
		v["hp"] = mx * 0.10
		var got: float = sys.scute_amount(v, 2) * 4.0
		n += 1
		_ok("091 3★ maxHp %d 爆发 → %.2f/秒" % [int(mx), float(cs[1])], _near(got, float(cs[1]), 0.02),
			"实测 %.3f/秒" % got)
	_ok("④ 分母", n == 3, "N=%d" % n)
	# 悬崖是【每帧连续判】的 —— 被治疗拉回 25% 以上要立刻停爆发
	u["maxHp"] = 4000.0
	u["hp"] = 100.0
	var burst: float = sys.scute_amount(u, 2)
	u["hp"] = 3000.0
	var calm: float = sys.scute_amount(u, 2)
	_ok("回到高血立刻停爆发(比值恰为 6)", _near(burst / maxf(calm, 1e-6), 6.0, 1e-3),
		"%.3f / %.3f = %.4f" % [burst, calm, burst / maxf(calm, 1e-6)])
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑤ 0.25 秒节拍 = 自管累加器(★不吃 `_t` 跨路累加, CLAUDE.md §3.4)
# ═════════════════════════════════════════════════════════════
func _t091_cadence() -> void:
	print("── ⑤ 091 的 0.25 秒节拍(自管累加器) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var u: Dictionary = _equip(_mk("left", Vector2(-180, -40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	u["hp"] = 1500.0
	for _i in range(5):
		sys.tick_unit(u, 0.05)                        # 累计 0.25
	_ok("0.05×5 = 恰好 1 跳", int(u.get("_scute_n", 0)) == 1, "n=%d" % int(u.get("_scute_n", 0)))
	sys.tick_unit(u, 0.24)                            # 累计 0.49 → 仍是 1 跳
	_ok("再喂 0.24 仍是 1 跳", int(u.get("_scute_n", 0)) == 1, "n=%d" % int(u.get("_scute_n", 0)))
	sys.tick_unit(u, 0.01)                            # 累计 0.50 → 第 2 跳
	_ok("再喂 0.01 → 第 2 跳", int(u.get("_scute_n", 0)) == 2, "n=%d" % int(u.get("_scute_n", 0)))
	# 一秒 = 4 跳
	var v: Dictionary = _equip(_mk("left", Vector2(-160, -40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	v["hp"] = 1500.0
	for _i in range(20):
		sys.tick_unit(v, 0.05)
	_ok("1.0 秒 = 4 跳", int(v.get("_scute_n", 0)) == 4, "n=%d" % int(v.get("_scute_n", 0)))
	# ★跨路证明: 把全局时钟推到很大, 新携带者【仍要攒够 0.25 秒】才回第一跳。
	#   拿 `_t` 和常数比的实现会在这里当场触发。
	var t0 = _s._t
	_s._t = 9999.0
	var w: Dictionary = _equip(_mk("left", Vector2(-140, -40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	w["hp"] = 1500.0
	sys.tick_unit(w, 0.10)
	_ok("_t=9999 时新携带者 0.10 秒仍不触发(不吃跨路时钟)", int(w.get("_scute_n", 0)) == 0,
		"n=%d" % int(w.get("_scute_n", 0)))
	sys.tick_unit(w, 0.16)
	_ok("再喂 0.16(共 0.26) → 触发", int(w.get("_scute_n", 0)) == 1, "n=%d" % int(w.get("_scute_n", 0)))
	_s._t = t0
	# 补跳上限: 一次喂 10 秒不会补 40 跳
	var z: Dictionary = _equip(_mk("left", Vector2(-120, -40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	z["hp"] = 1500.0
	sys.tick_unit(z, 10.0)
	_ok("单次 10 秒的补跳被封在 8 跳", int(z.get("_scute_n", 0)) == 8, "n=%d" % int(z.get("_scute_n", 0)))
	# 死人不回血
	var d: Dictionary = _equip(_mk("left", Vector2(-100, -40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	d["hp"] = 1500.0
	d["alive"] = false
	sys.tick_unit(d, 1.0)
	_ok("阵亡后不再回血", int(d.get("_scute_n", 0)) == 0, "n=%d" % int(d.get("_scute_n", 0)))
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑥ 走标准 `_heal` 通道 ⇒ 吃【治疗削减】(用户 2026-08-06 拍板"能")
# ═════════════════════════════════════════════════════════════
func _t091_healcut() -> void:
	print("── ⑥ 091 吃治疗削减(用户拍板「能」) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var a: Dictionary = _mk("left", Vector2(-80, 0), 6000.0)
	a["hp"] = 100.0
	var got_full: float = sys.scute_heal_once(a, 2)    # 满速: 3 + 12 = 15, 但 <25% ⇒ ×6 = 90
	_ok("无削减时一跳回 90(3★·6000 血·爆发)", _near(got_full, 90.0, 0.51), "实测 %.2f" % got_full)
	var b: Dictionary = _mk("left", Vector2(-60, 0), 6000.0)
	b["hp"] = 100.0
	b["heal_reduce_until"] = _s._t + 60.0
	b["heal_reduce_pct"] = 0.5
	var got_cut: float = sys.scute_heal_once(b, 2)
	_ok("50% 治疗削减 → 回一半", _near(got_cut / maxf(got_full, 1e-6), 0.5, 0.02),
		"%.2f / %.2f = %.3f" % [got_cut, got_full, got_cut / maxf(got_full, 1e-6)])
	# 治疗加成也照吃(同一条通道)
	var c: Dictionary = _mk("left", Vector2(-40, 0), 6000.0)
	c["hp"] = 100.0
	c["heal_amp"] = 1.0
	var got_amp: float = sys.scute_heal_once(c, 2)
	_ok("+100% 治疗加成 → 回两倍", _near(got_amp / maxf(got_full, 1e-6), 2.0, 0.02),
		"%.2f / %.2f = %.3f" % [got_amp, got_full, got_amp / maxf(got_full, 1e-6)])
	# 满血时实际回复为 0(_heal 的口径)
	var d: Dictionary = _mk("left", Vector2(-20, 0), 6000.0)
	_ok("满血时实际回复 0", _near(sys.scute_heal_once(d, 2), 0.0), "")
	_ok("⑥ 分母", _n > 0, "本组 4 条")
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑦ 091 多带同一件 → 取最高星, 不相加(契约 §4 全表通用口径)
# ═════════════════════════════════════════════════════════════
func _t091_multi_copy() -> void:
	print("── ⑦ 091 多件取最高星 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var one: Dictionary = _equip(_mk("left", Vector2(0, 40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	var three: Dictionary = _equip(_mk("left", Vector2(20, 40), 3000.0), [
		{"id": "p2eq_091", "star": 1}, {"id": "p2eq_091", "star": 3}, {"id": "p2eq_091", "star": 2}])
	one["hp"] = 2000.0
	three["hp"] = 2000.0
	sys.tick_unit(one, 0.25)
	sys.tick_unit(three, 0.25)
	_ok("装 3 件也只跳一次", int(three.get("_scute_n", 0)) == 1, "n=%d" % int(three.get("_scute_n", 0)))
	_ok("装 3 件 = 单件 3★ 的量(不相加)",
		_near(float(three.get("_scute_last", -1.0)), float(one.get("_scute_last", -2.0)), 0.01),
		"三件 %.2f vs 单件 %.2f" % [float(three.get("_scute_last", -1.0)), float(one.get("_scute_last", -2.0))])
	# 没带这件的单位一跳都不跳
	var none: Dictionary = _equip(_mk("left", Vector2(40, 40), 3000.0), [{"id": "p2eq_094", "star": 3}])
	none["hp"] = 2000.0
	sys.tick_unit(none, 1.0)
	_ok("不带 091 的单位不回血", int(none.get("_scute_n", 0)) == 0, "n=%d" % int(none.get("_scute_n", 0)))
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑧ 091 端到端 —— 走【真入口】`EquipSystem._eq_tick`(含 `_b4_eq` 守卫)
# ═════════════════════════════════════════════════════════════
func _t091_endtoend() -> void:
	print("── ⑧ 091 端到端(真入口 _eq_tick) ──")
	_reset_units()
	var u: Dictionary = _equip(_mk("left", Vector2(60, 40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	u["hp"] = 1000.0
	var hp0: float = u["hp"]
	_s._equip_sys._eq_tick(u, 0.25)
	_ok("_eq_tick 一拍后血量真的涨了", u["hp"] > hp0, "%.2f → %.2f" % [hp0, float(u["hp"])])
	# 3★ / maxHp 3000 / 血量 33% ⇒ 不爆发 ⇒ 一跳 3 + 6 = 9
	_ok("_eq_tick 一拍恰好回 9(3★·3000 血·非爆发)", _near(float(u["hp"]) - hp0, 9.0, 0.01),
		"Δ=%.3f" % (float(u["hp"]) - hp0))
	# `_b4_eq` 守卫: 把它摘掉就不该再回血(证明守卫是真的在挡)
	var v: Dictionary = _equip(_mk("left", Vector2(80, 40), 3000.0), [{"id": "p2eq_091", "star": 3}])
	v["hp"] = 1000.0
	v["_b4_eq"] = false
	var hp1: float = v["hp"]
	_s._equip_sys._eq_tick(v, 0.25)
	_ok("_b4_eq=false 时不进本批 tick_unit", _near(float(v["hp"]), hp1), "%.2f → %.2f" % [hp1, float(v["hp"])])
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑨ 094 立碑 —— 阵亡触发 · 一只龟装 3 件只立一座(取最高星) · 各自立各自的
# ═════════════════════════════════════════════════════════════
func _t094_raise() -> void:
	print("── ⑨ 094 立碑 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var a: Dictionary = _equip(_mk("left", Vector2(-120, 80)), [{"id": "p2eq_094", "star": 3}])
	_ok("开局没有碑", sys.stele_count() == 0, "N=%d" % sys.stele_count())
	# 真入口①: EquipSystem._eq_on_death(阵亡装备钩的分发点)
	_s._equip_sys._eq_on_death(a, null)
	_ok("阵亡 → 立起 1 座碑", sys.stele_count() == 1, "N=%d" % sys.stele_count())
	_ok("碑在【原地】", sys._steles[0]["pos"].distance_to(a["pos"]) < 0.01,
		"碑 %s vs 死点 %s" % [str(sys._steles[0]["pos"]), str(a["pos"])])
	# 装 3 件只立一座, 取最高星
	sys.clear_all()
	var b: Dictionary = _equip(_mk("left", Vector2(-100, 80)), [
		{"id": "p2eq_094", "star": 1}, {"id": "p2eq_094", "star": 3}, {"id": "p2eq_094", "star": 2}])
	_s._equip_sys._eq_on_death(b, null)
	_ok("装 3 件只立 1 座", sys.stele_count() == 1, "N=%d" % sys.stele_count())
	_ok("取最高星(si=2)", int(sys._steles[0]["si"]) == 2, "si=%d" % int(sys._steles[0]["si"]))
	# 不同携带者各自立碑
	var c: Dictionary = _equip(_mk("left", Vector2(-80, 80)), [{"id": "p2eq_094", "star": 1}])
	_s._equip_sys._eq_on_death(c, null)
	_ok("第二个携带者另立一座", sys.stele_count() == 2, "N=%d" % sys.stele_count())
	# 真入口②: battle._kill 全链路
	sys.clear_all()
	var d: Dictionary = _equip(_mk("left", Vector2(-60, 80), 500.0), [{"id": "p2eq_094", "star": 2}])
	_s._kill(d, null)
	_ok("battle._kill 全链路也立碑", sys.stele_count() == 1, "N=%d" % sys.stele_count())
	_ok("_kill 立的碑取到正确星级(si=1)", sys.stele_count() == 1 and int(sys._steles[0]["si"]) == 1,
		"si=%d" % (int(sys._steles[0]["si"]) if sys.stele_count() > 0 else -1))
	# 不带 094 的单位死了不立碑
	sys.clear_all()
	var e: Dictionary = _equip(_mk("left", Vector2(-40, 80)), [{"id": "p2eq_091", "star": 3}])
	_s._equip_sys._eq_on_death(e, null)
	_ok("不带 094 的单位阵亡不立碑", sys.stele_count() == 0, "N=%d" % sys.stele_count())
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑨-b 094 的【全局 tick】真的有人调
#      ★memory [[fb-verify-must-run-the-real-path]]:「断言函数存在」守不住「还有没有人调它」。
#      前面几组都是我在测试里自己调 `sys.tick()` —— 那证明不了游戏里有人调。
#
#      ★★2026-08-06 改口径(主会话改了共享接线):
#      全局推进原来挂在 `EquipSystem._eq_tick` 里、用帧号去重。但 `_eq_tick` 在主循环里被
#      `if not u.get("equips", []).is_empty():` 包着 ⇒ **场上没有一个带装备的活单位时全部停摆**,
#      而 094 恰恰是"携带者已经死了、碑还要继续动"的那件 —— 这正是本路报上去的耦合。
#      现已抽成 `EquipSystem.tick_global(delta)`, 由主循环每帧无条件调一次。
#      ⇒ 这里改喂 `tick_global`; 帧号去重闸也随之取消(不再需要 await 换帧)。
#      另加一条**接线**断言: 主循环源码里真的有 `_equip_sys.tick_global(dt)` ——
#      抽出来没人调的话, 上面那条喂 `tick_global` 的行为断言照样绿。
# ═════════════════════════════════════════════════════════════
func _t094_global_tick_wired() -> void:
	print("── ⑨-b 094 全局 tick 的真入口 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var carrier: Dictionary = _equip(_mk("left", Vector2(140, 80)), [{"id": "p2eq_094", "star": 3}])
	var ally: Dictionary = _mk("left", Vector2(180, 80))
	_s._equip_sys._eq_on_death(carrier, null)
	_ok("分母: 碑已立起", sys.stele_count() == 1, "N=%d" % sys.stele_count())
	var age0: float = float(sys._steles[0]["age"])
	_s._equip_sys.tick_global(0.05)
	_ok("★碑的年龄被 tick_global 推进了(全局 tick 真的接上了)",
		float(sys._steles[0]["age"]) > age0,
		"age %.4f → %.4f" % [age0, float(sys._steles[0]["age"])])
	_ok("★光环也由 tick_global 那条路写上了", _near(float(ally.get("damage_amp", 0.0)), 0.35),
		"amp=%.4f" % float(ally.get("damage_amp", 0.0)))
	# ★★接线: 主循环真的每帧调它。★另外守住"全局的 .tick(delta) 不许再留在逐单位的 _eq_tick 里" ——
	#   搬走后两边都留一份就是每帧推进两次(碑会走得比设定快一倍)。
	var rb_src: String = FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★★主循环源码里真的有 `_equip_sys.tick_global(dt)`",
		rb_src.contains("_equip_sys.tick_global(dt)"), "len=%d" % rb_src.length())
	var eq_src: String = FileAccess.get_file_as_string("res://scripts/systems/equip/equip_system.gd")
	var _i: int = eq_src.find("func _eq_tick")
	var _e: int = eq_src.find("
func ", _i + 1)
	var eq_tick_body: String = eq_src.substr(_i, (_e - _i) if _e > _i else -1) if _i >= 0 else ""
	_ok("★分母: 取到了 _eq_tick 的函数体", eq_tick_body.length() > 200, "len=%d" % eq_tick_body.length())
	_ok("★全局的 .tick(delta) 没有【同时】留在逐单位的 _eq_tick 里(否则每帧推两次)",
		not eq_tick_body.contains("_b4s.tick(delta)"), "")
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑩ 094 光环的作用域 —— 全场不设半径 · 排除龟蛋与训龟大师 · 只给友军
# ═════════════════════════════════════════════════════════════
func _t094_aura_scope() -> void:
	print("── ⑩ 094 光环作用域 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	# 碑立在 ARENA 左下角, 友军放右上角 —— 相距 1000+ 码
	var half: Vector2 = _s.ARENA.size * 0.5
	var carrier: Dictionary = _equip(_mk("left", -half + Vector2(30, 30)), [{"id": "p2eq_094", "star": 3}])
	var far_ally: Dictionary = _mk("left", half - Vector2(30, 30))
	var near_ally: Dictionary = _mk("left", -half + Vector2(60, 30))
	var foe: Dictionary = _mk("right", Vector2(0, 0))
	var egg: Dictionary = _mk("left", Vector2(-20, 100), 3000.0, {"egg": true})
	var trainer: Dictionary = _mk("left", Vector2(20, 100), 500.0, {"trainer": true})
	var dist: float = carrier["pos"].distance_to(far_ally["pos"])
	_s._equip_sys._eq_on_death(carrier, null)
	sys.tick(0.016)
	_ok("远近分母(碑到远方友军的距离)", dist > 900.0, "%.0f 码" % dist)
	_ok("近处友军吃到 +35% 增伤", _near(float(near_ally.get("damage_amp", 0.0)), 0.35),
		"amp=%.4f" % float(near_ally.get("damage_amp", 0.0)))
	_ok("★全场生效: %.0f 码外的友军照样吃到 +35%%" % dist, _near(float(far_ally.get("damage_amp", 0.0)), 0.35),
		"amp=%.4f" % float(far_ally.get("damage_amp", 0.0)))
	_ok("敌人不吃光环", _near(float(foe.get("damage_amp", 0.0)), 0.0), "amp=%.4f" % float(foe.get("damage_amp", 0.0)))
	_ok("龟蛋不吃光环(全表通用口径)", _near(float(egg.get("damage_amp", 0.0)), 0.0), "amp=%.4f" % float(egg.get("damage_amp", 0.0)))
	_ok("训龟大师不吃光环(全表通用口径)", _near(float(trainer.get("damage_amp", 0.0)), 0.0), "amp=%.4f" % float(trainer.get("damage_amp", 0.0)))
	_ok("双抗: 近处友军 +50/+50", _near(float(near_ally.get("def", 0.0)), 50.0) and _near(float(near_ally.get("mr", 0.0)), 50.0),
		"def=%.1f mr=%.1f" % [float(near_ally.get("def", 0.0)), float(near_ally.get("mr", 0.0))])
	_ok("双抗: 远方友军 +50/+50", _near(float(far_ally.get("def", 0.0)), 50.0) and _near(float(far_ally.get("mr", 0.0)), 50.0),
		"def=%.1f mr=%.1f" % [float(far_ally.get("def", 0.0)), float(far_ally.get("mr", 0.0))])
	# 幂等: 连续跑 30 帧不许越加越多
	for _i in range(30):
		sys.tick(0.016)
	_ok("幂等: 30 帧后仍是 +35%(不越加越多)", _near(float(far_ally.get("damage_amp", 0.0)), 0.35),
		"amp=%.4f" % float(far_ally.get("damage_amp", 0.0)))
	_ok("幂等: 30 帧后双抗仍是 +50", _near(float(far_ally.get("def", 0.0)), 50.0),
		"def=%.1f" % float(far_ally.get("def", 0.0)))
	_ok("幂等: buffs 里只留 2 条(def/mr 各一)", far_ally["buffs"].size() == 2, "N=%d" % far_ally["buffs"].size())
	# 撤销
	sys.clear_all()
	_ok("撤场后增伤归零", _near(float(far_ally.get("damage_amp", 0.0)), 0.0), "amp=%.4f" % float(far_ally.get("damage_amp", 0.0)))
	_ok("撤场后双抗归零", _near(float(far_ally.get("def", 0.0)), 0.0) and _near(float(far_ally.get("mr", 0.0)), 0.0),
		"def=%.1f mr=%.1f" % [float(far_ally.get("def", 0.0)), float(far_ally.get("mr", 0.0))])
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑪ 094 光环不叠加、取最高(否则三件 = +105% 增伤)
# ═════════════════════════════════════════════════════════════
func _t094_aura_stack() -> void:
	print("── ⑪ 094 光环取最高不叠加 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var c1: Dictionary = _equip(_mk("left", Vector2(-120, -100)), [{"id": "p2eq_094", "star": 1}])
	var c2: Dictionary = _equip(_mk("left", Vector2(-100, -100)), [{"id": "p2eq_094", "star": 3}])
	var c3: Dictionary = _equip(_mk("left", Vector2(-80, -100)), [{"id": "p2eq_094", "star": 2}])
	var ally: Dictionary = _mk("left", Vector2(0, -100))
	for x in [c1, c2, c3]:
		_s._equip_sys._eq_on_death(x, null)
	sys.tick(0.016)
	_ok("三座碑立起来了(分母)", sys.stele_count() == 3, "N=%d" % sys.stele_count())
	_ok("★增伤取最高 = 0.35, 不是 0.12+0.22+0.35=0.69", _near(float(ally.get("damage_amp", 0.0)), 0.35),
		"amp=%.4f" % float(ally.get("damage_amp", 0.0)))
	_ok("★双抗取最高 = 50, 不是 18+32+50=100", _near(float(ally.get("def", 0.0)), 50.0),
		"def=%.1f" % float(ally.get("def", 0.0)))
	# 逐星值(规格 §0.5): 12/22/35% 与 18/32/50
	sys.clear_all()
	var per := [[0, 0.12, 18.0], [1, 0.22, 32.0], [2, 0.35, 50.0]]
	var cnt := 0
	for p in per:
		sys.clear_all()
		var cc: Dictionary = _equip(_mk("left", Vector2(-60 + cnt * 10, -100)), [{"id": "p2eq_094", "star": int(p[0]) + 1}])
		_s._equip_sys._eq_on_death(cc, null)
		sys.tick(0.016)
		cnt += 1
		_ok("%d★ 增伤 %.0f%% · 双抗 %.0f" % [int(p[0]) + 1, float(p[1]) * 100.0, float(p[2])],
			_near(float(ally.get("damage_amp", 0.0)), float(p[1])) and _near(float(ally.get("def", 0.0)), float(p[2])),
			"amp=%.4f def=%.1f" % [float(ally.get("damage_amp", 0.0)), float(ally.get("def", 0.0))])
	_ok("⑪ 分母", cnt == 3, "N=%d" % cnt)
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑫ 双抗的【实际减伤比例】—— 量真的少掉多少血, 不重实现 resist 公式
#    规格 §0.5 的量级表(龟基础双抗按 15 算): 1★ 25% · 2★ 37% · 3★ 48%
# ═════════════════════════════════════════════════════════════
func _t094_resist_real() -> void:
	print("── ⑫ 094 双抗的实际减伤比例(量真实掉血) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var atk: Dictionary = _mk("right", Vector2(100, -40))
	var expect := [[0, 25.0], [1, 37.0], [2, 48.0]]
	var cnt := 0
	for p in expect:
		sys.clear_all()
		# 基线: 无碑, 双抗 15
		var t0: Dictionary = _mk("left", Vector2(-100 + cnt * 10, -40), 1000000.0)
		t0["base_def"] = 15.0
		t0["base_mr"] = 15.0
		_s._recalc_stats(t0)
		var h0: float = t0["hp"]
		# ★必须先过 `_resolve_dmg` —— 护甲/魔抗是在【那里】算的, 直接把裸数喂给
		#   `_apply_damage_from` 会原样打进去(第一版就这么写, 三条全量到"降低 0%")。
		_s._damage._apply_damage_from(atk, t0, _s._resolve_dmg(atk, 100000.0, t0, true), Color.WHITE, 0.0, false, true)
		var base_loss: float = h0 - float(t0["hp"])
		# 有碑: 同样的一发
		var carrier: Dictionary = _equip(_mk("left", Vector2(-140 + cnt * 10, -40)), [{"id": "p2eq_094", "star": int(p[0]) + 1}])
		var t1: Dictionary = _mk("left", Vector2(-120 + cnt * 10, -40), 1000000.0)
		t1["base_def"] = 15.0
		t1["base_mr"] = 15.0
		_s._recalc_stats(t1)
		_s._equip_sys._eq_on_death(carrier, null)
		sys.tick(0.016)
		var h1: float = t1["hp"]
		_s._damage._apply_damage_from(atk, t1, _s._resolve_dmg(atk, 100000.0, t1, true), Color.WHITE, 0.0, false, true)
		var aura_loss: float = h1 - float(t1["hp"])
		var cut: float = (1.0 - aura_loss / maxf(base_loss, 1e-6)) * 100.0
		cnt += 1
		_ok("%d★ 双抗 +%.0f → 受伤降低 %.0f%%" % [int(p[0]) + 1, [18.0, 32.0, 50.0][int(p[0])], float(p[1])],
			absf(cut - float(p[1])) <= 1.0,
			"基线掉 %.0f · 带碑掉 %.0f ⇒ 降低 %.2f%%" % [base_loss, aura_loss, cut])
		_ok("%d★ 分母: 基线伤害 > 0" % [int(p[0]) + 1], base_loss > 100.0, "%.0f" % base_loss)
	_ok("⑫ 分母", cnt == 3, "N=%d" % cnt)
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑬ 增伤的【实际效果】—— 同一发打出去真的多了 35%
# ═════════════════════════════════════════════════════════════
func _t094_amp_real() -> void:
	print("── ⑬ 094 增伤的实际效果(量真实掉血) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var foe0: Dictionary = _mk("right", Vector2(120, 0), 1000000.0)
	var shooter0: Dictionary = _mk("left", Vector2(-120, 0))
	var h0: float = foe0["hp"]
	_s._damage._apply_damage_from(shooter0, foe0, _s._resolve_dmg(shooter0, 1000.0, foe0, true), Color.WHITE, 0.0, false, true)
	var base_hit: float = h0 - float(foe0["hp"])
	var carrier: Dictionary = _equip(_mk("left", Vector2(-140, 0)), [{"id": "p2eq_094", "star": 3}])
	var shooter1: Dictionary = _mk("left", Vector2(-100, 0))
	var foe1: Dictionary = _mk("right", Vector2(140, 0), 1000000.0)
	_s._equip_sys._eq_on_death(carrier, null)
	sys.tick(0.016)
	var h1: float = foe1["hp"]
	_s._damage._apply_damage_from(shooter1, foe1, _s._resolve_dmg(shooter1, 1000.0, foe1, true), Color.WHITE, 0.0, false, true)
	var amp_hit: float = h1 - float(foe1["hp"])
	_ok("分母: 基线一发 > 0", base_hit > 10.0, "%.0f" % base_hit)
	_ok("★带碑的友军一发打出 1.35 倍", _near(amp_hit / maxf(base_hit, 1e-6), 1.35, 0.01),
		"%.0f / %.0f = %.4f" % [amp_hit, base_hit, amp_hit / maxf(base_hit, 1e-6)])
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑭ 石雷 —— 每 3 秒 · 130/260/500 魔法伤害 · 打最近的敌人 · 落地才结算
# ═════════════════════════════════════════════════════════════
func _t094_bolt() -> void:
	print("── ⑭ 094 石雷 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	# 逐星基数(规格 §0.5)
	_ok("石雷基数 130/260/500",
		_near(sys.stele_bolt_base(0), 130.0) and _near(sys.stele_bolt_base(1), 260.0) and _near(sys.stele_bolt_base(2), 500.0),
		"%.0f/%.0f/%.0f" % [sys.stele_bolt_base(0), sys.stele_bolt_base(1), sys.stele_bolt_base(2)])
	# 端到端: 立碑 → 喂 3 秒 → 石块在途(还没掉血) → 再喂 0.5 秒 → 落地掉血
	var carrier: Dictionary = _equip(_mk("left", Vector2(-200, 140)), [{"id": "p2eq_094", "star": 3}])
	var foe: Dictionary = _mk("right", Vector2(-160, 140), 1000000.0)
	_s._equip_sys._eq_on_death(carrier, null)
	var hp0: float = foe["hp"]
	# ★61 拍不是 60: 0.05 累加 60 次的浮点和可能落在 2.9999999 一侧 ——
	#   拿"恰好 3.0"当断言点会偶发红(第一版就在这儿红过)。多喂一拍, 判据仍是"3 秒到点发一发"。
	for _i in range(61):
		sys.tick(0.05)                                   # 3.05 秒
	_ok("3 秒到点: 石块已发射(在途 1 发)", sys._bolts.size() == 1, "N=%d" % sys._bolts.size())
	_ok("在途期间还没掉血(落地才结算)", _near(float(foe["hp"]), hp0), "hp=%.1f" % float(foe["hp"]))
	# ★系统侧的在途表与演出侧的石块是**两份累加器**(伤害用前者、画面用后者)。
	#   它们必须由同一个 tick 同一个 delta 推 ⇒ 落地那一帧两边一起结束。
	#   这条守的就是"伤害不许比石头早/晚半秒"(memory [[fb-vfx-defect-families]] 的第三类)。
	var rock_in_air: int = sys.vfx.alive_count("stone_bolt")
	_ok("在途期间演出侧有 1 个蓄能点(分母)", rock_in_air == 1, "N=%d" % rock_in_air)
	## ★2026-08-09 石雷改成闪电(用户:「石雷我要闪电高高劈下来，不要图片」)后,
	##   在途期间画面上是**蓄能预兆**, 真正的闪电在【伤害那一帧】才劈 ⇒ 此刻不该有闪电。
	_ok("★在途期间【还没有】闪电(闪电是瞬时的, 不该提前出现)",
		sys.vfx.alive_count("thunder") == 0, "N=%d" % sys.vfx.alive_count("thunder"))
	for _i in range(11):
		sys.tick(0.05)                                   # 再 0.55 秒 > 落时 0.5
	_ok("落地后真的掉血", float(foe["hp"]) < hp0, "%.1f → %.1f" % [hp0, float(foe["hp"])])
	_ok("★结算那一帧蓄能点收掉(伤害与演出同帧, 不是各走各的秒表)",
		sys.vfx.alive_count("stone_bolt") == 0, "N=%d" % sys.vfx.alive_count("stone_bolt"))
	_ok("★★结算那一帧【闪电劈下来了】(由 stele_bolt_land 在打出伤害的同一帧发出)",
		sys.vfx.alive_count("thunder") >= 1, "N=%d" % sys.vfx.alive_count("thunder"))
	_ok("落地证据挂在目标身上", int(foe.get("_stele_bolt_n", 0)) == 1, "n=%d" % int(foe.get("_stele_bolt_n", 0)))
	_ok("在途表已出清", sys._bolts.is_empty(), "N=%d" % sys._bolts.size())
	# 节拍: 再喂 6 秒 ⇒ 再来 2 发(共 3 发)
	for _i in range(120):
		sys.tick(0.05)
	_ok("每 3 秒一发: 9 秒共发 3 发", int(sys._steles[0]["n_bolt"]) == 3, "n_bolt=%d" % int(sys._steles[0]["n_bolt"]))
	# 伤害是【魔法】: 只吃魔抗、不吃护甲
	_reset_units()
	var c2: Dictionary = _equip(_mk("left", Vector2(-200, 180)), [{"id": "p2eq_094", "star": 3}])
	var mr_foe: Dictionary = _mk("right", Vector2(-160, 180), 1000000.0)
	mr_foe["base_mr"] = 40.0
	_s._recalc_stats(mr_foe)
	var def_foe: Dictionary = _mk("right", Vector2(-140, 180), 1000000.0)
	def_foe["base_def"] = 40.0
	_s._recalc_stats(def_foe)
	_s._equip_sys._eq_on_death(c2, null)
	var d_mr: int = sys.stele_bolt_land({"carrier": c2, "tgt": mr_foe, "si": 2})
	var d_def: int = sys.stele_bolt_land({"carrier": c2, "tgt": def_foe, "si": 2})
	_ok("石雷吃魔抗(40 魔抗 → 减半)", _near(float(d_mr) / 500.0, 0.5, 0.02), "%d / 500" % d_mr)
	_ok("石雷不吃护甲(40 护甲 → 不减)", _near(float(d_def) / 500.0, 1.0, 0.02), "%d / 500" % d_def)
	# 选靶: 训龟大师不被主动索敌(证明走的是 _nearest_enemy_from 而不是手写循环)
	_reset_units()
	var c3: Dictionary = _equip(_mk("left", Vector2(0, -160)), [{"id": "p2eq_094", "star": 1}])
	var tr: Dictionary = _mk("right", Vector2(10, -160), 500.0, {"trainer": true})
	var real_foe: Dictionary = _mk("right", Vector2(200, -160), 1000000.0)
	_s._equip_sys._eq_on_death(c3, null)
	var b3: Dictionary = sys.stele_fire(sys._steles[0])
	_ok("分母: 大师比真敌人近", c3["pos"].distance_to(tr["pos"]) < c3["pos"].distance_to(real_foe["pos"]),
		"%.0f vs %.0f" % [c3["pos"].distance_to(tr["pos"]), c3["pos"].distance_to(real_foe["pos"])])
	_ok("★石雷跳过训龟大师, 打真敌人", not b3.is_empty() and is_same(b3.get("tgt", null), real_foe),
		"tgt=%s" % (str(b3.get("tgt", {}).get("name", "?")) if not b3.is_empty() else "(空)"))
	# 没有敌人时不发
	_reset_units()
	var c4: Dictionary = _equip(_mk("left", Vector2(0, -200)), [{"id": "p2eq_094", "star": 1}])
	_s._equip_sys._eq_on_death(c4, null)
	_ok("场上没敌人时不发石雷", sys.stele_fire(sys._steles[0]).is_empty())
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑮ 换路口径 —— 碑清除, 每路一次重新计
# ═════════════════════════════════════════════════════════════
func _t094_lane() -> void:
	print("── ⑮ 094 换路清除(每路一次) ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var carrier: Dictionary = _equip(_mk("left", Vector2(-60, 160)), [{"id": "p2eq_094", "star": 3}])
	var ally: Dictionary = _mk("left", Vector2(-40, 160))
	_s._equip_sys._eq_on_death(carrier, null)
	sys.tick(0.016)
	_ok("换路前: 有碑 + 友军带光环", sys.stele_count() == 1 and _near(float(ally.get("damage_amp", 0.0)), 0.35),
		"N=%d amp=%.3f" % [sys.stele_count(), float(ally.get("damage_amp", 0.0))])
	# ★正规入口: clear_all()
	sys.clear_all()
	_ok("clear_all 后碑清空", sys.stele_count() == 0, "N=%d" % sys.stele_count())
	_ok("clear_all 后光环撤干净", _near(float(ally.get("damage_amp", 0.0)), 0.0) and _near(float(ally.get("def", 0.0)), 0.0),
		"amp=%.3f def=%.1f" % [float(ally.get("damage_amp", 0.0)), float(ally.get("def", 0.0))])
	# ★自愈入口: 模拟 `_dl_clear_units()`(清空 battle._units 再重建一批新的)
	_reset_units()
	var c2: Dictionary = _equip(_mk("left", Vector2(-60, 200)), [{"id": "p2eq_094", "star": 3}])
	_s._equip_sys._eq_on_death(c2, null)
	sys.tick(0.016)
	_ok("分母: 自愈测试前确实有碑", sys.stele_count() == 1, "N=%d" % sys.stele_count())
	_s._units.clear()                                    # = _dl_clear_units 干的事
	var fresh: Dictionary = _mk("left", Vector2(0, 200))
	for _i in range(40):
		sys.tick(0.05)                                   # 2 秒 > 自扫节拍 0.5 秒
	_ok("★换路自愈: 立碑者不在 _units 里 → 碑自清", sys.stele_count() == 0, "N=%d" % sys.stele_count())
	_ok("★下一路的新单位不带上一路的光环", _near(float(fresh.get("damage_amp", 0.0)), 0.0),
		"amp=%.4f" % float(fresh.get("damage_amp", 0.0)))
	_reset_units()


# ═════════════════════════════════════════════════════════════
# ⑯ 演出层 —— 精确几何 / 闭式解 / 量真实节点(不抄公式)
# ═════════════════════════════════════════════════════════════
func _t_vfx_geometry() -> void:
	print("── ⑯ 演出层几何与物理 ──")
	_reset_units()
	var sys = _s._equip_sys._relic_sys
	var vfx = sys.vfx
	_ok("演出层挂在活着的世界上(分母)", is_instance_valid(_s._world))

	# ⑯-a 正六边形密铺: 中心距 = √3·R, 方位 30°+k·60° —— 量【纯函数】
	var cs: Array = RelicEqVfx.hex_ring_centers(13.0)
	_ok("甲片数 = 6(密铺邻居数)", cs.size() == 6, "N=%d" % cs.size())
	var d_ok := 0
	var a_ok := 0
	for k in range(cs.size()):
		var v: Vector2 = cs[k]
		if _near(v.length(), sqrt(3.0) * 13.0, 1e-4):
			d_ok += 1
		var ang: float = rad_to_deg(atan2(v.y, v.x))
		if ang < 0.0:
			ang += 360.0
		if _near(ang, 30.0 + 60.0 * float(k), 1e-3):
			a_ok += 1
	_ok("六片中心距全 = √3·R", d_ok == 6, "%d/6" % d_ok)
	_ok("六片方位角全 = 30°+k·60°", a_ok == 6, "%d/6" % a_ok)
	# 相邻两片之间也是 √3·R(三角晶格的另一半)
	var nb_ok := 0
	for k in range(cs.size()):
		var p: Vector2 = cs[k]
		var q: Vector2 = cs[(k + 1) % cs.size()]
		if _near(p.distance_to(q), sqrt(3.0) * 13.0, 1e-4):
			nb_ok += 1
	_ok("相邻两片间距也 = √3·R(密铺)", nb_ok == 6, "%d/6" % nb_ok)

	# ⑯-b 量【真实节点】: 甲片环真的建出来了, 而且位置与密铺一致
	var u: Dictionary = _equip(_mk("left", Vector2(0, -60), 3000.0), [{"id": "p2eq_091", "star": 3}])
	u["hp"] = 2000.0
	var h: Dictionary = vfx.ensure_scutes(u)
	_ok("甲片环真的进了 _world", not h.is_empty() and is_instance_valid(h["root"]) and h["root"].get_parent() == _s._world)
	var plates: Array = h.get("plates", [])
	_ok("真实甲片节点数 = 6(分母)", plates.size() == 6, "N=%d" % plates.size())
	var rp_ok := 0
	for mi in plates:
		if not is_instance_valid(mi):
			continue
		var lp: Vector3 = mi.position
		var r_px: float = Vector2(lp.x, lp.z).length() / float(_s.WS)
		if _near(r_px, sqrt(3.0) * WANT_PLATE_R_PX, 1e-2):
			rp_ok += 1
	_ok("真实节点的环半径 = √3 × 甲片半径(21 码)", rp_ok == 6, "%d/6" % rp_ok)

	# ⑯-c 柱面波振幅: a(4x)/a(x) ≡ 1/2(能量守恒), 与 x 无关
	var w_ok := 0
	for x in [0.0625, 0.08, 0.12, 0.2, 0.25]:
		var r: float = RelicEqVfx.wave_amp(4.0 * float(x)) / RelicEqVfx.wave_amp(float(x))
		if _near(r, 0.5, 1e-6):
			w_ok += 1
	_ok("柱面波 a(4x)/a(x) ≡ 1/2(与 x 无关)", w_ok == 5, "%d/5" % w_ok)

	# ⑯-d ★振幅与回复量焊死: 爆发态亮度 = √6 倍。量【真实材质的 alpha】。
	var na: Dictionary = _equip(_mk("left", Vector2(30, -60), 3000.0), [{"id": "p2eq_091", "star": 3}])
	na["hp"] = 2000.0                                    # 66% ⇒ 不爆发
	sys.scute_heal_once(na, 2)
	var hn: Dictionary = vfx.ensure_scutes(na)
	var a_norm: float = ((hn["plates"] as Array)[0] as MeshInstance3D).material_override.albedo_color.a
	var lo: Dictionary = _equip(_mk("left", Vector2(60, -60), 3000.0), [{"id": "p2eq_091", "star": 3}])
	lo["hp"] = 100.0                                     # 3.3% ⇒ 爆发
	sys.scute_heal_once(lo, 2)
	var hl: Dictionary = vfx.ensure_scutes(lo)
	var a_low: float = ((hl["plates"] as Array)[0] as MeshInstance3D).material_override.albedo_color.a
	_ok("分母: 平时甲片确实亮了", a_norm > 0.01, "a=%.4f" % a_norm)
	_ok("★<25% 时甲片亮度 = √6 倍(与 ×6 回复焊死)", _near(a_low / maxf(a_norm, 1e-6), sqrt(6.0), 2e-3),
		"%.4f / %.4f = %.4f (√6=%.4f)" % [a_low, a_norm, a_low / maxf(a_norm, 1e-6), sqrt(6.0)])
	_ok("亮度量程内不被钳(< 1.0)", a_low < 0.999, "a_low=%.4f" % a_low)
	# 爆发态才放脉冲波; 平时不放(4 次/秒会糊)
	_ok("★爆发态放柱面波、平时不放", vfx.alive_count("heal_wave") == 1, "N=%d" % vfx.alive_count("heal_wave"))

	# ⑯-d2 ★回复微粒 —— 2026-08-09 补。为什么要有它: 甲片脉冲的峰谷比被 PLATE_A 的
	#   天花板(1/√6)锁死, 实拍量到"一跳只把环带总亮度推 5%", 机制在跑却**读不出在回血**
	#   (用"变亮像素数"量出来的: 21393 像素亮起、间隔 0.24 秒 = 节拍, 肉眼看不见)。
	var n_mote: int = vfx.alive_count("heal_mote")
	_ok("★每一跳都升起回复微粒(平时 %d + 爆发 %d)" % [RelicEqVfx.MOTE_N, RelicEqVfx.MOTE_N_LOW],
		n_mote == RelicEqVfx.MOTE_N + RelicEqVfx.MOTE_N_LOW, "N=%d" % n_mote)
	_ok("爆发档微粒更密(读得出两个状态不同)", RelicEqVfx.MOTE_N_LOW > RelicEqVfx.MOTE_N,
		"%d > %d" % [RelicEqVfx.MOTE_N_LOW, RelicEqVfx.MOTE_N])
	# ★甲片/微粒都**不许**开 no_depth_test —— 开了就画在龟立绘之上, 六倍档整片压住龟壳和脸
	#   (2026-08-09 实拍确认的真缺陷; 这条守的就是它本身, 不是它的替身)。
	var pl0 := ((hl["plates"] as Array)[0] as MeshInstance3D).material_override as StandardMaterial3D
	var mo0: StandardMaterial3D = null
	for x in vfx._owned:
		if is_instance_valid(x) and str((x as Node).get_meta("relic_eq_vfx", "")) == "heal_mote":
			mo0 = (x as MeshInstance3D).material_override as StandardMaterial3D
			break
	_ok("分母: 拿到微粒材质", mo0 != null)
	_ok("★甲片不画在龟身之上(no_depth_test = false)", pl0 != null and not pl0.no_depth_test)
	_ok("★微粒不画在龟身之上(no_depth_test = false)", mo0 != null and not mo0.no_depth_test)
	# 微粒: holdfade(前 55% 满亮) + 真的在升 —— 纯同步, 不等任何 tween
	var mtest := {"node": MeshInstance3D.new(), "t": 0.0, "p0": Vector3(1.0, 0.06, 2.0),
		"dx": 0.0, "dz": 0.0, "rise": RelicEqVfx.MOTE_RISE_M}
	(mtest["node"] as MeshInstance3D).material_override = StandardMaterial3D.new()
	vfx.apply_mote(mtest, RelicEqVfx.MOTE_LIFE * 0.30)
	var a_hold: float = ((mtest["node"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a
	var y_hold: float = (mtest["node"] as MeshInstance3D).position.y
	vfx.apply_mote(mtest, RelicEqVfx.MOTE_LIFE * 0.95)
	var a_late: float = ((mtest["node"] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a
	var y_late: float = (mtest["node"] as MeshInstance3D).position.y
	_ok("★微粒 holdfade: 前 55% 满亮(不是从出生就淡)", _near(a_hold, 1.0, 1e-3), "a=%.3f" % a_hold)
	_ok("微粒末段确实淡出", a_late < 0.25, "a=%.3f" % a_late)
	_ok("★微粒真的在升(末段高于前段, 且升满接近 MOTE_RISE_M)",
		y_late > y_hold + 0.5 and _near(y_late - 0.06, RelicEqVfx.MOTE_RISE_M * 0.95, 0.05),
		"y %.3f → %.3f (rise=%.2f)" % [y_hold, y_late, RelicEqVfx.MOTE_RISE_M])
	(mtest["node"] as MeshInstance3D).free()

	# ⑯-e 立碑: 匀减速上升(软着陆的唯一解)
	_ok("rise(0)=0", _near(RelicEqVfx.rise_profile(0.0), 0.0))
	_ok("rise(0.5)=0.75(线性给 0.5 / ease_out_cubic 给 0.875)", _near(RelicEqVfx.rise_profile(0.5), 0.75, 1e-9),
		"%.6f" % RelicEqVfx.rise_profile(0.5))
	_ok("rise(1)=1", _near(RelicEqVfx.rise_profile(1.0), 1.0))
	var dv: float = (RelicEqVfx.rise_profile(1.0) - RelicEqVfx.rise_profile(1.0 - 1e-4)) / 1e-4
	_ok("rise'(1)=0(到位速度恰为 0 = 软着陆)", absf(dv) < 2e-4, "%.6f" % dv)
	var carrier: Dictionary = _equip(_mk("left", Vector2(-160, -140)), [{"id": "p2eq_094", "star": 3}])
	_s._equip_sys._eq_on_death(carrier, null)
	var sh: Dictionary = sys._steles[0]["h"]
	_ok("碑真的进了 _world", not sh.is_empty() and is_instance_valid(sh["root"]) and sh["root"].get_parent() == _s._world)
	var y_ground: float = _s._world_pos(carrier["pos"], 0.0).y
	# ⑯-e1 ★升起靠 region_rect 逐行揭开立绘, **不靠"埋下去让地板挡住"**
	#   (地板挡不挡得住取决于地图 —— VFXLAB 黑场/镂空地面都会漏; region 是画多少就是多少)
	var spr = sh.get("sprite", null)
	_ok("碑体是新立绘 Sprite3D(分母)", spr != null and is_instance_valid(spr) and (spr as Sprite3D).texture != null)
	if spr != null and is_instance_valid(spr) and (spr as Sprite3D).texture != null:
		var th: float = float((spr as Sprite3D).texture.get_height())
		vfx.apply_stele(sh, 0.0)
		var f0: float = (spr as Sprite3D).region_rect.size.y / th
		vfx.apply_stele(sh, 0.5)
		var f_half: float = (spr as Sprite3D).region_rect.size.y / th
		var off_half: float = (spr as Sprite3D).offset.y
		vfx.apply_stele(sh, 1.0)
		var f1: float = (spr as Sprite3D).region_rect.size.y / th
		_ok("τ=0 时几乎一点没露头(露出比 ≤ 1/贴图高)", f0 <= 1.5 / th, "露出 %.4f" % f0)
		_ok("★τ=0.5 时真实节点露出 75%(量 region_rect, 不是抄公式)",
			_near(f_half, 0.75, 2e-3), "露出 %.4f" % f_half)
		_ok("τ=1 时整张碑立绘都露出来", _near(f1, 1.0, 1e-6), "露出 %.6f" % f1)
		_ok("★露出区域的**下边缘恒钉在地面**(offset = 区域半高)",
			_near(off_half, th * 0.75 * 0.5, 1e-3), "offset=%.3f (期望 %.3f)" % [off_half, th * 0.75 * 0.5])
		_ok("碑体贴图按 NEAREST 取样", (spr as Sprite3D).texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		# ⑯-e2 ★碑体在屏幕上保住立绘的长宽比(漏掉竖直 0.626 压缩就会变成横匾)
		var tw: float = float((spr as Sprite3D).texture.get_width())
		var s_w: float = tw * (spr as Sprite3D).pixel_size * (spr as Sprite3D).scale.x * PX_PER_M_LIT
		var s_h: float = th * (spr as Sprite3D).pixel_size * (spr as Sprite3D).scale.y * PX_PER_M_VERT_LIT
		_ok("★碑体屏幕长宽比 == 立绘长宽比", _near(s_w / maxf(s_h, 1e-6), tw / th, 0.02),
			"屏幕 %.1f×%.1f=%.3f vs 立绘 %.0f×%.0f=%.3f" % [s_w, s_h, s_w / maxf(s_h, 1e-6), tw, th, tw / th])
		_ok("碑体屏幕高 = 碑高 × 17.62(≥ 龟立绘 44 px)", s_h >= 44.0, "%.1f px" % s_h)
	# ⑯-e3 ★root 从头到尾不动 + 碑基石台**钉在地面**
	#   (旧版石台挂在会上下移动的 root 下, 实拍量到它在屏幕上整整跑了 148 px)
	var y_root0: float = (sh["root"] as Node3D).position.y
	var base_n = sh.get("base", null)
	_ok("碑基石台建出来了(分母)", base_n != null and is_instance_valid(base_n))
	var by0: float = (base_n as Node3D).global_position.y if base_n != null and is_instance_valid(base_n) else -999.0
	vfx.apply_stele(sh, 0.3)
	vfx.advance_stele(sh, 0.1)
	var y_root1: float = (sh["root"] as Node3D).position.y
	var by1: float = (base_n as Node3D).global_position.y if base_n != null and is_instance_valid(base_n) else -998.0
	_ok("★升起过程中 root 一动不动(升起不靠移动整座碑)", _near(y_root1, y_root0, 1e-6),
		"y %.5f → %.5f" % [y_root0, y_root1])
	_ok("★碑基石台的世界高度恒 = 地面(不随碑升起上下跑)",
		_near(by1, by0, 1e-6) and _near(by0 - y_ground, RelicEqVfx.GROUND_Y, 1e-4),
		"y %.5f → %.5f (地面 %.5f)" % [by0, by1, y_ground])
	# ⑯-e4 ★碑顶符石 = 分星信息, 屏幕上必须分得开
	var slots2: Array = RelicEqVfx.crest_slots(2, WANT_STELE_H)
	var ns_crest: Array = []
	for si in [0, 1, 2]:
		ns_crest.append(RelicEqVfx.crest_slots(si, WANT_STELE_H).size())
	_ok("★碑顶符石颗数 = 1/2/3(分星靠数颗数)", ns_crest == [1, 2, 3], "实测 %s" % str(ns_crest))
	var pitch_px: float = absf(float((slots2[1] as Vector2).x) - float((slots2[0] as Vector2).x)) * PX_PER_M_LIT
	var crest_px: float = 2.0 * RelicEqVfx.CREST_R_M * PX_PER_M_LIT
	_ok("★相邻两颗的屏幕间距 > 单颗宽度(数得清的充要条件)", pitch_px > crest_px,
		"间距 %.2f px vs 宽 %.2f px" % [pitch_px, crest_px])
	_ok("3★ 真的建了 3 颗符石节点", (sh.get("crests", []) as Array).size() == 3,
		"N=%d" % (sh.get("crests", []) as Array).size())
	# ⑯-e5 ★破土爆点是暖尘不是石头本色(旧版 luma 0.257, 实拍是全屏最暗的东西)
	var blast_col: Color = Color(0, 0, 0, 1)
	if not (vfx._shocks as Array).is_empty():
		blast_col = (vfx._shocks[0] as Dictionary)["col"]
	var blast_luma: float = 0.2126 * blast_col.r + 0.7152 * blast_col.g + 0.0722 * blast_col.b
	_ok("破土爆点建出来了(分母)", not (vfx._shocks as Array).is_empty(), "N=%d" % (vfx._shocks as Array).size())
	_ok("★破土爆点亮度 ≥ 0.60(旧版 0.257 在黑场里几乎看不见)", blast_luma >= 0.60,
		"luma=%.4f" % blast_luma)

	# ⑯-f 石雷: 真自由落体
	_ok("fall(0)=1 · fall(1)=0", _near(RelicEqVfx.fall_profile(0.0), 1.0) and _near(RelicEqVfx.fall_profile(1.0), 0.0))
	var sd_ok := 0
	var nn := 40
	for i in range(1, nn):
		var z0: float = RelicEqVfx.fall_profile(float(i - 1) / float(nn))
		var z1: float = RelicEqVfx.fall_profile(float(i) / float(nn))
		var z2: float = RelicEqVfx.fall_profile(float(i + 1) / float(nn))
		if _near(z2 - 2.0 * z1 + z0, -2.0 / float(nn * nn), 1e-9):
			sd_ok += 1
	_ok("★等距二阶差分恒为 −2/N²(抛物线的定义·匀速给 0)", sd_ok == nn - 1, "%d/%d" % [sd_ok, nn - 1])
	var t1: float = RelicEqVfx.fall_time(1.0, 40.0)
	var t4: float = RelicEqVfx.fall_time(4.0, 40.0)
	_ok("落时尺度律 T(4H)/T(H) ≡ 2", _near(t4 / maxf(t1, 1e-9), 2.0, 1e-6), "%.6f" % (t4 / maxf(t1, 1e-9)))
	_ok("落地速度 = g·T", _near(RelicEqVfx.impact_speed(1.0, 40.0), 40.0 * t1, 1e-6))
	_ok("石雷落时 = 0.5 秒(H=5.25 / g=42 的闭式解)",
		_near(RelicEqVfx.fall_time(RelicEqVfx.BOLT_H, RelicEqVfx.BOLT_G), 0.5, 1e-6),
		"%.6f 秒" % RelicEqVfx.fall_time(RelicEqVfx.BOLT_H, RelicEqVfx.BOLT_G))
	# ⑯-f2 ★★石雷 = 闪电(2026-08-09 重做)。旧版是一张**静态石头贴图**自由落体 —— 那正是"图片"。
	#   这一节原本钉的是落石(Δy ≈ BOLT_H / 只绕 z 翻滚 / 90° 长宽对调), 石头没了, 整节按闪电重写。
	#   ⚠ 两个渲染坑各配一条断言, 都是实拍 + 染色探针钉出来的:
	#     ① `BILLBOARD_ENABLED` 会让精灵**完全**对齐相机(含 roll), 而本作相机 52° 俯视
	#        ⇒ 一道竖直闪电被掰成斜的短条。必须 `BILLBOARD_FIXED_Y`。
	#     ② `region_enabled` 那条路**根本画不出来**: 节点 visible=true/alpha=1/挂在 World 下、
	#        区域也在逐帧推进, 就是不显示。把它染成品红后全屏**零个品红像素**; 去掉 region 后 4071 个。
	_ok("⑯-f2 闪电素材在位: " + RelicEqVfx.THUNDER_TEX, ResourceLoader.exists(RelicEqVfx.THUNDER_TEX))
	var th: Dictionary = vfx.thunder_strike(carrier["pos"] + Vector2(60, 0), 2)
	_ok("闪电建出来了(分母)", not th.is_empty() and is_instance_valid(th.get("node", null)))
	if not th.is_empty() and is_instance_valid(th.get("node", null)):
		var tn := th["node"] as Sprite3D
		_ok("闪电真的进了 _world", tn.get_parent() == _s._world)
		_ok("★闪电是逐帧动画(%d 帧, 不是一张静图)" % RelicEqVfx.THUNDER_FRAMES,
			tn.hframes == RelicEqVfx.THUNDER_FRAMES and tn.hframes > 1, "hframes=%d" % tn.hframes)
		_ok("★★必须 BILLBOARD_FIXED_Y —— ENABLED 会把竖直闪电掰成斜条",
			tn.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y,
			"billboard=%d" % int(tn.billboard))
		_ok("★★不许开 region_enabled(开了整道闪电画不出来, 染色实证零像素)",
			not tn.region_enabled)
		_ok("不许 ALPHA_CUT_DISCARD(阈值 0.5 会把压暗的整道闪电丢光)",
			tn.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED)
		_ok("闪电贴图按 NEAREST 取样", tn.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		## "高高劈下来": 整道闪电的世界高度必须远高于一只龟(龟立绘约 1 个世界单位)
		var th_h: float = float(tn.texture.get_height()) * tn.pixel_size
		_ok("★闪电够高(≥ 6 个世界单位 ≈ 6 只龟高)", th_h >= 6.0, "%.2f" % th_h)
		## 逐帧真的在换帧 + holdfade
		vfx.apply_thunder(th, 0.0)
		var f0: int = tn.frame
		var th_a0: float = tn.modulate.a
		vfx.apply_thunder(th, 0.5)
		var f_mid: int = tn.frame
		vfx.apply_thunder(th, 0.95)
		var th_late: float = tn.modulate.a
		_ok("★闪电通道逐帧在变(不是定格一张)", f_mid != f0, "帧 %d → %d" % [f0, f_mid])
		_ok("★holdfade: 前 55%% 满亮(不是一出生就淡)", _near(th_a0, 1.0, 1e-3), "a=%.3f" % th_a0)
		_ok("末段确实淡出", th_late < 0.2, "a=%.3f" % th_late)

	# ⑯-g 贴地: |三角面法线·上| ≈ 1(memory [[fb-axis-y-plus-rotation-cancels]])
	var mi0 = plates[0]
	var arr: Array = (mi0.mesh as ArrayMesh).surface_get_arrays(0)
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var flat := 0
	for nv in norms:
		if absf((nv as Vector3).normalized().dot(Vector3.UP)) > 0.99:
			flat += 1
	_ok("甲片法线分母", norms.size() > 0, "N=%d" % norms.size())
	_ok("甲片贴地(|法线·上| > 0.99)", flat == norms.size(), "%d/%d" % [flat, norms.size()])

	# ⑯-h 全队印记数 == 吃到光环的友军数(把"全场不设半径"变成可判定的形式)
	var half: Vector2 = _s.ARENA.size * 0.5
	var a1: Dictionary = _mk("left", half - Vector2(40, 40))
	var a2: Dictionary = _mk("left", Vector2(0, 0))
	var e1: Dictionary = _mk("right", Vector2(40, 0))
	var eg: Dictionary = _mk("left", Vector2(-40, 0), 3000.0, {"egg": true})
	sys.tick(0.016)
	var buffed := 0
	for o in _s._units:
		if float(o.get("_stele_amp", 0.0)) > 0.0:
			buffed += 1
	_ok("吃到光环的友军数(分母)", buffed >= 2, "N=%d" % buffed)
	_ok("★头顶印记数 == 吃到光环的友军数", vfx.mark_count() == buffed,
		"印记 %d vs 友军 %d" % [vfx.mark_count(), buffed])
	# ⑯-h2 ★印记必须是**立着**的片, 而且屏幕上过 16 px 的存在阈值。
	#   旧版拿【贴地】的六边形悬在头顶 1.15 米, 实拍在实战镜头下整只友军身上只剩
	#   **10 个琥珀像素**(2026-08-09 逐像素数出来的) —— 全队增伤/双抗这条核心信息等于没画。
	var mk_node = null
	for x in vfx._owned:
		if is_instance_valid(x) and str((x as Node).get_meta("relic_eq_vfx", "")) == "aura_mark":
			mk_node = x
			break
	_ok("拿到印记节点(分母)", mk_node != null)
	if mk_node != null:
		var mk_arr: Array = ((mk_node as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		var mk_nm: PackedVector3Array = mk_arr[Mesh.ARRAY_NORMAL]
		var up_n := 0
		for nv in mk_nm:
			if absf((nv as Vector3).normalized().dot(Vector3.UP)) > 0.01:
				up_n += 1
		_ok("印记法线分母", mk_nm.size() > 0, "N=%d" % mk_nm.size())
		_ok("★印记是**立着**的(|法线·上| ≈ 0, 不是躺在头顶的一张片)", up_n == 0,
			"%d/%d 个法线朝上" % [up_n, mk_nm.size()])
		var mk_w_px: float = 2.0 * (mk_node as Node3D).scale.x * PX_PER_M_LIT
		_ok("★印记屏幕宽 ≥ 16 px(龟头顶等级徽章的边长; 旧版只有 10 个像素)",
			mk_w_px >= 16.0, "%.2f px" % mk_w_px)
	# ⑯-h3 ★碑基石台的闪光是【事件驱动】的: 只有 stele_fire 真的发射了才亮, 演出侧不自己数秒
	var fh: Dictionary = sys._steles[0]["h"]
	fh["flash"] = 0.0
	for _i in range(40):
		vfx.advance_stele(fh, 0.05)                     # 空推 2 秒 —— 没发射就不该亮
	var flash_idle: float = float(fh.get("flash", 0.0))
	sys.stele_fire(sys._steles[0])
	var flash_fire: float = float(fh.get("flash", 0.0))
	vfx.advance_stele(fh, 0.42)                          # 一个衰减时间常数
	var flash_decay: float = float(fh.get("flash", 0.0))
	_ok("★没发射石雷时石台不亮(演出层没有自己的秒表)", _near(flash_idle, 0.0, 1e-6),
		"flash=%.6f" % flash_idle)
	_ok("★发射的那一刻石台被推到满亮", _near(flash_fire, 1.0, 1e-6), "flash=%.6f" % flash_fire)
	_ok("★之后指数衰减(1 个时间常数后 ≈ 1/e)", _near(flash_decay, 1.0 / exp(1.0), 0.02),
		"flash=%.4f (1/e=%.4f)" % [flash_decay, 1.0 / exp(1.0)])

	# ⑯-i 撤场: 真的 free 掉(不是只清账)
	var root_ref = sh["root"]
	var before: int = vfx.alive_count()
	sys.clear_all()
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("撤场前有节点(分母)", before > 0, "N=%d" % before)
	_ok("clear_all 后账面清零", vfx.alive_count() == 0, "N=%d" % vfx.alive_count())
	_ok("clear_all 后碑节点真的被 free", not is_instance_valid(root_ref))
	_ok("clear_all 后印记也清零", vfx.mark_count() == 0, "N=%d" % vfx.mark_count())
	_reset_units()
