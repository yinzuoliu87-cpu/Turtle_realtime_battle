extends Node
## 荆棘海胆(p2eq_015) 反伤只发一次 —— 别的反伤装备不受影响。
##
## 由来〖2026-08-02 逐份复验方案书时查出〗:
##   p2eq_015 同时走两条反伤路 ——
##     ① 通用钩: equip_stats_apply.gd 把 STATS.reflectPct 写进 u["reflect"],
##        battle_damage.gd:171 的通用块据此发一发
##     ② 专属分支: equip_system.gd:1104 的 _eq_on_target 拿【同一个 dmg】再发一发
##   两者都在 battle_damage.gd 同一个 `if not from_equip` 块里触发, 无互斥
##   ⇒ 实际反伤 = 名义值的【两倍】(探针: 1★ 12% 打 1000 → 反伤 240),
##     而累计器 thorn_accum 只统计其中一半 ⇒ 阈值触发也慢一倍。
##   修法: 通用钩跳过 p2eq_015(专属分支拥有它)。
##
## ★为什么这个 bug 活了这么久: tooltip_number_audit 只保证"文案里的数字在代码里存在同样的数组",
##   不验行为、不验用在了对的地方 —— 双发它完全看不见。数值审计 ≠ 行为门禁。
var _n := 0
var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond: _fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])

const WANT_THORN_PCT := [0.12, 0.25, 0.40]   # 需求字面值(不引用被测常量, 否则恒真式)
const WANT_URCHIN_PCT := [0.08, 0.11, 0.15]  # p2eq_013 海胆壳: 走通用钩, 不该被误伤
const HIT := 1000

var _s

func _ready() -> void:
	await get_tree().process_frame
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for i in range(40):
		await get_tree().process_frame

	for si in range(3):
		await _one("p2eq_015", si, WANT_THORN_PCT[si], "① 荆棘海胆")
	for si in range(3):
		await _one("p2eq_013", si, WANT_URCHIN_PCT[si], "② 海胆壳(对照·必须仍生效)")

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 荆棘海胆反伤只发一次" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _one(iid: String, si: int, want_pct: float, tag: String) -> void:
	_s._units.clear()
	var ctr: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var d: Dictionary = _s._spawn._make_unit("green", "right", ctr)
	d["maxHp"] = 999999.0; d["hp"] = 999999.0
	# ★★把【防守方的暴击】清零 —— 反伤那一发是防守方打出去的, 会吃暴击(默认暴伤 1.5×)。
	#   不清零的话同一个测试每次跑结果都不一样(实测: 1★ 这次 120、下次 180), 是【偶发红】。
	#   memory fb-ci-vs-local-divergence: 拿带随机的单位测精确数值必然 CI 偶发红, 要用干净合成单位隔离。
	d["crit"] = 0.0; d["crit_dmg"] = 1.5
	d["equips"] = [{"id": iid, "star": si + 1}]
	d["eq_state"] = {}
	_s._units.append(d)
	var a: Dictionary = _s._spawn._make_unit("green", "left", ctr + Vector2(-200, 0))
	a["maxHp"] = 999999.0; a["hp"] = 999999.0
	a["def"] = 0.0; a["mr"] = 0.0; a["base_def"] = 0.0; a["base_mr"] = 0.0
	a["shield"] = 0.0; a["flat_dr"] = 0.0
	_s._units.append(a)
	_s._equip_sys._stats._eq_apply_all_stats()      # ★真入口: 开战时统一应用装备属性
	await get_tree().process_frame
	var hp0: float = a["hp"]
	_s._damage._apply_damage_from(a, d, HIT, Color("#ffffff"))
	await get_tree().process_frame
	var got: float = hp0 - float(a["hp"])
	var want: float = float(HIT) * want_pct
	_ok("%s %d★ 反伤 = %.0f(名义 %.0f%%), 不是两倍" % [tag, si + 1, want, want_pct * 100.0],
		absf(got - want) <= 1.0, "实测 %.0f (%.2f×名义)" % [got, got / maxf(1.0, want)])
