extends Node
## verify_untargetable.gd — 守卫「不可选中 / 组装期免疫」不被处决和伤害打穿
##
## 起因(用户 2026-07-19 实测):「赛博机甲变身的时候怎么被猎人龟直接处决了」。
## 根因是个【幽灵字段】: 免疫判定写的是 `_untargetable`(布尔), 但全项目【从来没有任何地方给它赋过值】
## —— 只在回合制遗留的 damage.gd 注释里出现过。真正生效的是 `untargetable_until`(时间戳)。
## 于是那四处判定恒为 false, 保护不了任何东西:
##   _update_hunter_passive / _hunter_exec_arrow_hit / _update_ninja_marks / _sk_hunter_barrage
## 组装期机甲血量从 1% 往上爬, 正卡在 14% 处决线下 → 猎人扫场射处决箭 → 直接 hp=0 + _kill,
## 绕过了 _apply_damage_from 里的 _assembling 免疫闸。黑洞中 / 滞空中的单位同样能被处决。
##
## 断言:
##   A. `_is_untargetable` 对 untargetable_until 未到期 / _assembling 都返回 true
##   B. 组装期机甲【不会】被猎人处决扫描选中
##   C. 组装期机甲【不会】被 _apply_damage(DoT/真伤路径) 扣血 —— 这条路径原先没有免疫闸
##   D. 源码里不允许再出现 `_untargetable` 这个幽灵字段(防复发)

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC_PATH := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame

	# ── A. _is_untargetable 判定 ──
	scene._t = 100.0
	var u_norm := {"alive": true, "hp": 10.0, "maxHp": 100.0}
	var u_air := {"alive": true, "hp": 10.0, "maxHp": 100.0, "untargetable_until": 105.0}
	var u_expired := {"alive": true, "hp": 10.0, "maxHp": 100.0, "untargetable_until": 99.0}
	var u_asm := {"alive": true, "hp": 10.0, "maxHp": 100.0, "_assembling": true}
	_ok("普通单位 可选中", not scene._is_untargetable(u_norm))
	_ok("滞空/黑洞(untargetable_until 未到期) 不可选中", scene._is_untargetable(u_air))
	_ok("untargetable_until 已过期 → 恢复可选中", not scene._is_untargetable(u_expired))
	_ok("组装期(_assembling) 不可选中", scene._is_untargetable(u_asm))

	# ── B. 猎人处决扫描不选组装期机甲 ──
	var hunter: Dictionary = scene._make_unit("hunter", "left", Vector2(0, 0))
	var mech: Dictionary = scene._make_unit("basic", "right", Vector2(100, 0))
	mech["_assembling"] = true
	mech["maxHp"] = 1000.0
	mech["hp"] = 10.0                      # 1% 血, 远低于 14% 处决线
	scene._units.clear()
	scene._units.append(hunter)
	scene._units.append(mech)
	hunter["_hunt_scan_t"] = -999.0
	scene._update_hunter_passive(hunter)
	_ok("★组装期机甲 不被猎人处决扫描选中", not mech.get("_hunt_exec_pending", false),
		"_hunt_exec_pending=%s" % [mech.get("_hunt_exec_pending", false)])

	# 对照: 同样残血但【不在组装期】→ 应该被选中(证明测试本身有效, 不是恒过)
	var normal: Dictionary = scene._make_unit("basic", "right", Vector2(120, 0))
	normal["maxHp"] = 1000.0
	normal["hp"] = 10.0
	scene._units.append(normal)
	hunter["_hunt_scan_t"] = -999.0
	scene._update_hunter_passive(hunter)
	_ok("对照·普通残血单位 会被处决扫描选中(证明断言非恒真)", normal.get("_hunt_exec_pending", false))

	# ── C. _apply_damage(DoT/真伤路径) 打不动组装期机甲 ──
	var hp_before: float = float(mech["hp"])
	scene._apply_damage(mech, 999, Color.WHITE, null, "dot")
	_ok("★组装期机甲 免疫 _apply_damage(DoT/真伤路径)", is_equal_approx(float(mech["hp"]), hp_before),
		"%.0f → %.0f" % [hp_before, float(mech["hp"])])

	scene.queue_free()
	await get_tree().process_frame

	# ── D. 幽灵字段不许复活 ──
	var f := FileAccess.open(SRC_PATH, FileAccess.READ)
	var ghost := 0
	var ln := 0
	while f != null and not f.eof_reached():
		var line := f.get_line()
		ln += 1
		if line.contains("\"_untargetable\"") and not line.strip_edges().begins_with("#"):
			ghost += 1
	if f != null: f.close()
	_ok("源码无 `_untargetable` 幽灵字段(真字段是 untargetable_until)", ghost == 0, "残留 %d 处" % ghost)

	print("ALL PASS — 不可选中/组装期免疫 守卫通过" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
