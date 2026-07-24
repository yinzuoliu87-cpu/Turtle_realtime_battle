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

	# ── E. 训龟大师(场外监视者)不被【单体定向】技选中 ──
	# 起因(用户 2026-07-24):「双穿珊瑚刺为啥还能锁到训龟大师」。根因: 珊瑚刺/竹击/背刺 这类"挑最远一个"
	# 的单体定向技原走 _enemies_of(含大师) → 而大师在场外·永远最远 → 每次都锁它(飞去角落/瞬移过去)。
	# 铁律(§PICK-TARGET): 单体挑选必须走 _pick_enemies_of(排除大师+不可选中); 真 AOE 才用 _enemies_of。
	var caster: Dictionary = scene._make_unit("basic", "left", Vector2(0, 0))
	var real_foe: Dictionary = scene._make_unit("basic", "right", Vector2(200, 0))               # 近敌(真目标)
	var foe_trainer: Dictionary = scene._make_unit("basic", "right", Vector2(3000, 0), {"trainer": true})   # 场外大师·永远最远
	scene._units.clear()
	scene._units.append(caster); scene._units.append(real_foe); scene._units.append(foe_trainer)
	_ok("★_enemies_of 含训龟大师(真AOE仍会溅到它·吃1)", scene._arr_has_unit(scene._enemies_of(caster), foe_trainer))
	_ok("★_pick_enemies_of 排除训龟大师(单体定向不锁)", not scene._arr_has_unit(scene._pick_enemies_of(caster), foe_trainer))
	_ok("★_pick_enemies_of 仍含真敌(非空检查·断言非恒真)", scene._arr_has_unit(scene._pick_enemies_of(caster), real_foe))
	# 端到端: 竹击(钩全场最远)→ 应钩近处真敌、不碰场外大师(远)。改回 _enemies_of 则相反 → 本条转红。
	foe_trainer["spd_dbf_until"] = 0.0; real_foe["spd_dbf_until"] = 0.0
	scene._sk_bamboo_smack(caster, real_foe)
	_ok("★竹击不冰寒场外大师(没锁它)", float(foe_trainer.get("spd_dbf_until", 0.0)) <= scene._t,
		"大师 spd_dbf_until=%.1f _t=%.1f" % [float(foe_trainer.get("spd_dbf_until", 0.0)), scene._t])
	_ok("★竹击命中真敌(证明钩到了近敌·非空)", float(real_foe.get("spd_dbf_until", 0.0)) > scene._t)

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
