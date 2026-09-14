extends Node
## verify_timestop_global_freeze.gd — 时停期间【整个战斗世界的状态】有没有变
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：用户 2026-09-14
## ══════════════════════════════════════════════════════════════════
## 「触手和直升机只是我看到的典型，**还有无数东西是否被时停你怎么办**？」
##
## 他说中了要害。在这之前我的做法是**逐个补断言**：背景鱼群、非携带者立绘、
## 一笔护盾余额、触手的内部钟、直升机的坐标……**那是打地鼠**——
## 判据的覆盖面等于"我想得到的东西"，而我永远列不全。
##
## ⇒ 换判据的**形状**：不列举被测对象，改成**扫全部**。
##
## ══════════════════════════════════════════════════════════════════
##  判据：全域差分
## ══════════════════════════════════════════════════════════════════
## 把 `battle` 持有的**每一个系统对象**（`_tentacle_vfx` / `_gun_syn` / `_spec` /
## `_equip_sys` / …，靠 `get_property_list()` 枚举，不靠我手写名单）连同它们内部的
## Dictionary / Array 一起**递归摘要**成一串数字指纹，在时停期间前后各取一次，
## **要求指纹一个字节都不变**。
##
## 这样：**我没想到的东西也在扫描范围里**。以后有人加了新系统、新的每帧驱动，
## 它只要在时停期间动了内部状态，这条就会红——不需要谁记得来加一条断言。
##
## ★三条分母（缺一条这个判据就是空的）：
##   ① 扫到的对象数 / 字段数要够大（扫了个寂寞 = 恒真）
##   ② 时停**之前**同样的指纹**必须在变**（不变说明我摘要的东西本来就是死的）
##   ③ 时停真的进了
##
## ★白名单只放三类**本来就该动**的，每条都写清为什么：
##   · `_timestop` 自己（它在倒计时、在推自己的演出）
##   · 携带者自己的动作会碰到的（伤害统计 / 弹道在途表）
##   · 纯渲染侧的帧计数（不是战斗状态）
## 白名单是「我看过了」，不是「我懒得管」。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 这三类在时停期间**允许**变化，各有理由（见段头）。
const ALLOW := {
	"_timestop": "时停系统自己：在倒计时(_ts_remaining)、在推自己的演出(_ts_sand_t/_ts_vortex_t)",
	"_ballistics": "携带者的弹道在途表：文案写着「伤害即时结算」，只推 active 的那批",
	"_damage": "伤害统计累加器：携带者打出的伤害要记账",
	"_render": "纯渲染侧（相机/抖动/帧计数），不是战斗状态",
	"_vfx": "演出层：携带者自己的打击火花/飘字",
	"_hud": "UI 层：血条/面板刷新",
	"_equip_tick_sys": "携带者自己的延时结算队列（与 _ballistics 同族，见主场景 in_ts 分支）",
}

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


## 把任意值递归摘成一个数字指纹。★只摘**数**（float/int/bool/Vector/Color），
## 不摘对象引用与字符串 —— 前者会绕回 battle 自身成环，后者不是"在动"的东西。
func _fp(v, depth: int) -> float:
	if depth > 4:
		return 0.0
	var t := typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v)
	if t == TYPE_BOOL:
		return 1.0 if v else 0.0
	if t == TYPE_VECTOR2:
		return (v as Vector2).x * 1.7 + (v as Vector2).y * 2.3
	if t == TYPE_VECTOR3:
		return (v as Vector3).x * 1.7 + (v as Vector3).y * 2.3 + (v as Vector3).z * 3.1
	if t == TYPE_COLOR:
		var c: Color = v
		return c.r * 1.1 + c.g * 1.3 + c.b * 1.7 + c.a * 1.9
	if t == TYPE_ARRAY:
		var a: Array = v
		var acc := 0.0
		for i in range(mini(a.size(), 64)):
			acc += _fp(a[i], depth + 1) * float(i + 1)
		return acc + float(a.size()) * 0.5
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var acc2 := 0.0
		var ks: Array = d.keys()
		## ★键排序: 字典遍历顺序在两次快照之间可能不同, 不排序会读出假变化
		ks.sort_custom(func(x, y): return str(x) < str(y))
		for i in range(mini(ks.size(), 64)):
			## ★★单位字典**不能**当 key、也不能深递归 —— 它们互相引用成环
			##   (CLAUDE.md §3.2: Godot 递归哈希会无限递归卡死)。depth 上限挡住了这条。
			acc2 += _fp(d[ks[i]], depth + 1) * float(i + 1)
		return acc2 + float(ks.size()) * 0.5
	return 0.0


## 扫 battle 的每一个系统对象, 逐字段摘指纹。返回 {"<对象>.<字段>": 指纹}。
func _snap() -> Dictionary:
	var out: Dictionary = {}
	for p in _s.get_property_list():
		var pn: String = str(p.get("name", ""))
		if not pn.begins_with("_") or ALLOW.has(pn):
			continue
		var obj = _s.get(pn)
		if not (obj is RefCounted):
			continue
		for q in (obj as Object).get_property_list():
			var qn: String = str(q.get("name", ""))
			## ★不再只扫 `_` 开头的 —— 那样只扫到 55 个字段, 扫描面白白缩了一半。
			##   只跳过 `battle`(它绕回 battle 自身成环)与 Godot 自带的 `script`/`RefCounted` 属性。
			if qn == "battle" or qn == "script" or qn == "" or qn.begins_with("Ref"):
				continue
			var qt: int = int(q.get("type", 0))
			if qt != TYPE_FLOAT and qt != TYPE_INT and qt != TYPE_BOOL \
					and qt != TYPE_ARRAY and qt != TYPE_DICTIONARY \
					and qt != TYPE_VECTOR2 and qt != TYPE_VECTOR3:
				continue
			out[pn + "." + qn] = _fp((obj as Object).get(qn), 0)
	return out


func _diff(a: Dictionary, b: Dictionary) -> Array:
	var hit: Array = []
	for k in a.keys():
		if b.has(k) and absf(float(a[k]) - float(b[k])) > 1e-6:
			hit.append(k)
	hit.sort()
	return hit


func _wait(nf: int) -> void:
	for _i in range(nf):
		await get_tree().process_frame


func _mk(id: String, side: String, dx: float, star: int) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + Vector2(dx, 0))
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	if star > 0:
		u["equips"] = [{"id": "p2eq_059", "star": star}]
	_s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 059 时停: 全域差分(不列举被测对象, 扫 battle 持有的全部系统状态) ===")
	print("   用户 2026-09-14:「触手和直升机只是我看到的典型, 还有无数东西是否被时停你怎么办?」")
	_s = RB.new()
	add_child(_s)
	await _wait(40)

	_s._units.clear()
	var carrier: Dictionary = _mk("fortune", "left", -200.0, 3)
	var other: Dictionary = _mk("stone", "right", 260.0, 0)
	## 把场上尽量摆满: 触手 / 直升机 / 一笔会衰减的余额 —— 让扫描有东西可扫
	_s._tentacle_vfx.ensure_forced("right", 2)
	_s._equip_sys._gun_sys._spawn_heli(other, 2, 300.0)
	_s._spec.grant(other, "probe_decay", 1000.0, {"decay_sec": 40.0})
	await _wait(40)

	var a0: Dictionary = _snap()
	var objs: Dictionary = {}
	for k in a0.keys():
		objs[str(k).split(".")[0]] = true
	_ok("★分母①: 扫到 %d 个系统对象、共 %d 个字段" % [objs.size(), a0.size()],
		objs.size() >= 20 and a0.size() >= 90,
		"扫了个寂寞 ⇒ 下面那条是恒真式")

	await _wait(90)
	var a1: Dictionary = _snap()
	var pre: Array = _diff(a0, a1)
	_ok("★分母②: 时停【之前】这些字段里有 %d 个在变" % pre.size(),
		pre.size() >= 5,
		"一个都不变 ⇒ 我摘要的东西本来就是死的, 判据什么都验不到")
	print("     [探针] 时停前在变的(前 10): %s" % str(pre.slice(0, 10)))

	var ts = _s._timestop
	_s._t = 999.0
	ts._ts_update_trigger(0.016)
	ts._ts_update_trigger(10.0)
	_ok("★分母③: 时停真的进了(active=%d, 剩 %.1f 秒)"
		% [(ts._ts_active as Array).size(), float(ts._ts_remaining)],
		not (ts._ts_active as Array).is_empty() and float(ts._ts_remaining) > 5.0,
		"没进时停 ⇒ 下面是空检查")
	await _wait(50)   # 让入停那一下的演出自己跑完

	var b0: Dictionary = _snap()
	await _wait(120)
	var b1: Dictionary = _snap()
	var dur: Array = _diff(b0, b1)
	_ok("★★ 时停期间【全部系统状态】一个字段都不变(实测 %d 个变了, 时停前是 %d 个)"
		% [dur.size(), pre.size()],
		dur.is_empty(),
		"这些还在动: %s —— 白名单在本文件顶部 ALLOW, 加之前必须写清为什么它该动" % str(dur.slice(0, 8)))

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
