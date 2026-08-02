extends Node
## 闪避: 通用 dodgePct 真的施加 + 不发双份 + 有硬上限。
##
## 由来〖2026-08-02 用户:「dodgePct 要修, 是提供闪避的」+「每个角色我记得有闪避上限做了吗」〗
##   查实两件事:
##   ① `dodgePct` **只在图鉴显示、从不施加** —— `equip_stats.gd:38` 有展示分支,
##      而 `equip_stats_apply.gd` 从来没有对应的施加分支, 全靠 p2eq_046 的专属分支兜着。
##      图鉴上写的"闪避 +15%"对别的装备是假的。
##   ② **没有闪避上限**。判定是 `randf() < dodge_bonus`(battle_damage.gd:71), randf ∈ [0,1)
##      ⇒ dodge_bonus ≥ 1.0 = 永远打不中。而单只装备上限 3 件,
##      **探针实测: 带 2 件 3★ 幽灵墨鱼(各 50%) → 1.00 = 100% 免疫**。这个 bug 当时就是活的。
##
## 修法: 通用分支施加 + 删掉 p2eq_046 的专属 _buff(否则双份, 与荆棘海胆同形状) + DODGE_CAP 钳在唯一写入点。
var _n := 0
var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond: _fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])

const WANT_046 := [0.15, 0.25, 0.50]   # 需求字面值(STATS 里 dodgePct 15/25/50)
const WANT_CAP := 0.75                 # 需求字面值, 不引用被测常量

var _s

func _ready() -> void:
	await get_tree().process_frame
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for i in range(40):
		await get_tree().process_frame
	_ok("★分母: DODGE_CAP 常量存在且 = %.2f" % WANT_CAP,
		absf(float(_s.DODGE_CAP) - WANT_CAP) < 0.001, "DODGE_CAP=%.2f" % float(_s.DODGE_CAP))

	# ① 单件三档: 通用路径真的施加了, 且不是双份
	for si in range(3):
		var d: float = await _dodge_of([{"id": "p2eq_046", "star": si + 1}])
		_ok("① %d★ 幽灵墨鱼闪避 = %d" % [si + 1, int(WANT_046[si] * 100.0)] + "% (通用 dodgePct 真施加, 且不是双份)",
			absf(d - WANT_046[si]) < 0.001, "实测 %.2f" % d)

	# ② 多件叠加必须被上限钳住 —— 不钳就是 100% 免疫
	var d2: float = await _dodge_of([{"id": "p2eq_046", "star": 3}, {"id": "p2eq_046", "star": 3}])
	_ok("② ★★2 件 3★(名义 100pct) 被钳到 %d" % int(WANT_CAP * 100.0) + "pct, 不是永久免疫",
		absf(d2 - WANT_CAP) < 0.001, "实测 %.2f" % d2)
	var d3: float = await _dodge_of([{"id": "p2eq_046", "star": 3}, {"id": "p2eq_046", "star": 3}, {"id": "p2eq_046", "star": 3}])
	_ok("② ★3 件 3★(名义 150pct) 同样钳在 %d" % int(WANT_CAP * 100.0) + "pct",
		absf(d3 - WANT_CAP) < 0.001, "实测 %.2f" % d3)
	_ok("② ★★关键: 生效闪避 < 1.0(否则 randf() < dodge 恒真 = 打不中)", d3 < 1.0, "%.2f" % d3)

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 闪避施加/不双份/有上限" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _dodge_of(equips: Array) -> float:
	_s._units.clear()
	var ctr: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", "right", ctr)
	u["maxHp"] = 99999.0; u["hp"] = 99999.0
	u["equips"] = equips.duplicate(true)
	u["eq_state"] = {}
	_s._units.append(u)
	_s._equip_sys._stats._eq_apply_all_stats()      # ★真入口
	await get_tree().process_frame
	return float(u.get("dodge_bonus", 0.0))
