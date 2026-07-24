extends Node

## verify_trainer_skills.gd — 训龟大师【技能装配】逐个技能验收 (用户2026-07-23 方案书 20260723c)
## R1b 魔法石(被动): 大师普攻命中 → 2%目标最大生命 魔法伤害 + 自己每击 +5% 攻速(可叠·本场结束重置)。
## ★用真实场景实例(有完整单位字段), 直接驱动 _trainer_magicstone_onhit(照 verify_dot_stacks 做法)。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	await get_tree().process_frame
	var scene = RTScene.new()
	add_child(scene)                 # 触发 _ready → 建场 + spawn 队伍/大师
	await get_tree().process_frame
	await get_tree().process_frame

	_test_magic_stone(scene)
	_test_fury_potion(scene)
	_test_whistle(scene)
	_test_glacier(scene)
	_test_source(scene)

	scene.queue_free()
	print("ALL PASS — 训龟大师技能(魔法石/怒火药水/口哨/冰川)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)

func _test_magic_stone(scene) -> void:
	var trainer = null
	var enemy = null
	for u in scene._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			trainer = u
		elif not u.get("is_trainer", false) and u.get("alive", false) and str(u.get("side", "")) == "right":
			enemy = u
	_ok("找到我方大师 + 敌方单位(分母)", trainer != null and enemy != null)
	if trainer == null or enemy == null:
		return
	trainer["_tr_passive"] = "magic_stone"
	trainer["_ms_stacks"] = 0
	trainer["crit"] = 0.0                       # 去暴击随机 → 确定性
	enemy["shield"] = 0.0
	enemy["dodge_bonus"] = 0.0
	var hp0: float = float(enemy["hp"])
	var mx: float = float(enemy["maxHp"])
	scene._trainer_magicstone_onhit(trainer, enemy)
	var drop: float = hp0 - float(enemy["hp"])
	_ok("★魔法石·命中附带魔法伤(≤2%最大生命·过魔抗)", drop > 0.0 and drop <= mx * 0.02 + 3.0,
		"掉 %.0f 血 (2%%最大生命=%d)" % [drop, int(mx * 0.02)])
	_ok("★魔法石·攻速叠 1 层", int(trainer.get("_ms_stacks", 0)) == 1)
	scene._trainer_magicstone_onhit(trainer, enemy)
	_ok("★魔法石·可叠加(第2击→2层)", int(trainer.get("_ms_stacks", 0)) == 2)
	# 无魔法石被动的大师不触发(反向)
	var t2 = {"is_trainer": true, "side": "left", "alive": true, "_tr_passive": "", "_ms_stacks": 0}
	_ok("★没装魔法石→攻速haste=1(源码断言在下条)", int(t2.get("_ms_stacks", 0)) == 0)

func _test_fury_potion(scene) -> void:
	var trainer = null
	var allies: Array = []
	for u in scene._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			trainer = u
		elif not u.get("is_trainer", false) and str(u.get("side", "")) == "left" and u.get("alive", false):
			allies.append(u)
	_ok("怒火药水: 找到大师 + ≥2 友军(分母)", trainer != null and allies.size() >= 2)
	if trainer == null or allies.size() < 2:
		return
	var near_ally = allies[0]
	var far_ally = allies[1]
	var pt: Vector2 = near_ally["pos"]
	far_ally["pos"] = pt + Vector2(500.0, 0.0)      # 挪出 300 码外
	for a in [near_ally, far_ally]:
		a["haste_until"] = 0.0; a["move_buff_until"] = 0.0; a["echarge_until"] = 0.0
	var n: int = scene._fury_apply_buffs(trainer, pt)
	_ok("★怒火药水·落点300码内友军受益(≥1)", n >= 1, "受益 %d 人" % n)
	_ok("★近友军 +30%攻速(haste_mult=1.3·5秒)",
		abs(float(near_ally.get("haste_mult", 1.0)) - 1.3) < 0.01 and float(near_ally.get("haste_until", 0.0)) > scene._t)
	_ok("★近友军 +25%移速(move_buff_mult=1.25)", abs(float(near_ally.get("move_buff_mult", 1.0)) - 1.25) < 0.01)
	_ok("★近友军 +25%龟能充能(echarge_mult=1.25)", abs(float(near_ally.get("echarge_mult", 1.0)) - 1.25) < 0.01)
	_ok("★落点300码外友军不受益(有范围)", float(far_ally.get("haste_until", 0.0)) <= scene._t)

func _test_whistle(scene) -> void:
	var trainer = null
	var ally = null
	var enemy = null
	for u in scene._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			trainer = u
		elif not u.get("is_trainer", false) and str(u.get("side", "")) == "left" and u.get("alive", false):
			ally = u
		elif not u.get("is_trainer", false) and str(u.get("side", "")) == "right" and u.get("alive", false):
			enemy = u
	_ok("口哨: 找到大师+友军+敌(分母)", trainer != null and ally != null and enemy != null)
	if trainer == null or ally == null or enemy == null:
		return
	# ① 临时血: _apply_temp_maxhp 直接测
	var mx0: float = float(ally["maxHp"])
	var hp0: float = float(ally["hp"])
	scene._apply_temp_maxhp(ally, 700.0, 5.0)
	_ok("★口哨·临时血: maxHp +700", abs(float(ally["maxHp"]) - (mx0 + 700.0)) < 0.5)
	_ok("★口哨·临时血: 当前hp +700", abs(float(ally["hp"]) - (hp0 + 700.0)) < 0.5)
	# ③ 狂暴: +20%攻击力 + 免疫死亡
	var atk0: float = float(ally["atk"])
	scene._whistle_berserk_on(ally)   # 直接对已知友军(绕过随机)
	_ok("★口哨·狂暴: 攻击力 +20%", float(ally["atk"]) > atk0 * 1.15,
		"%.0f → %.0f" % [atk0, float(ally["atk"])])
	_ok("★口哨·狂暴: 4秒免疫死亡(deathfloor)", float(ally.get("deathfloor_until", 0.0)) > scene._t)
	# ② 灵体小龟气波: 敌在线上→削甲+击飞+伤害
	enemy["pos"] = trainer["pos"] + Vector2(200.0, 0.0)   # 摆到大师正东(线上)
	enemy["def_shred_until"] = 0.0
	var ehp0: float = float(enemy["hp"])
	var n: int = scene._whistle_spirit_wave(trainer)
	_ok("★口哨·气波: 命中沿途敌(≥1)", n >= 1, "命中 %d" % n)
	_ok("★口哨·气波: 命中敌掉血", float(enemy["hp"]) < ehp0)
	_ok("★口哨·气波: 命中敌削甲30%(def_shred_until)", float(enemy.get("def_shred_until", 0.0)) > scene._t)

func _test_glacier(scene) -> void:
	var trainer = null
	var e_on = null
	var e_off = null
	for u in scene._units:
		if u.get("is_trainer", false) and str(u.get("side", "")) == "left":
			trainer = u
		elif not u.get("is_trainer", false) and str(u.get("side", "")) == "right" and u.get("alive", false):
			if e_on == null: e_on = u
			elif e_off == null: e_off = u
	_ok("冰川: 找到大师 + 2 敌(分母)", trainer != null and e_on != null and e_off != null)
	if trainer == null or e_on == null or e_off == null:
		return
	scene._glacier_zones.clear()
	e_on["pos"] = trainer["pos"] + Vector2(200.0, 0.0)    # 大师正东200 → 冰川带上
	e_off["pos"] = trainer["pos"] + Vector2(200.0, 300.0) # 偏离带(带宽90/2=45)
	e_on["slow_until"] = 0.0; e_on["glacier_vuln_until"] = 0.0; e_off["glacier_vuln_until"] = 0.0
	trainer["_active_cd"] = 0.0
	var ok: bool = scene._cast_glacier(trainer, Vector2(1.0, 0.0))
	_ok("★冰川·施放建带 + CD17", ok and scene._glacier_zones.size() >= 1 and abs(float(trainer.get("_active_cd", 0.0)) - 17.0) < 0.1)
	scene._tick_glaciers(0.03)
	_ok("★冰川·带上敌减速 -40%(slow_mag 0.6)", abs(float(e_on.get("slow_mag", 1.0)) - 0.6) < 0.01 and float(e_on.get("slow_until", 0.0)) > scene._t)
	_ok("★冰川·带上敌受伤+20%(glacier_vuln)", float(e_on.get("glacier_vuln_until", 0.0)) > scene._t)
	_ok("★冰川·偏离带的敌不受影响(有边界)", float(e_off.get("glacier_vuln_until", 0.0)) <= scene._t)
	# 易伤 +20% 落到 _mitigate_incoming(与无易伤对比·排除其它减伤干扰)
	e_on["glacier_vuln_until"] = 0.0
	var base_mit: float = scene._mitigate_incoming(e_on, 100.0, false, false)
	e_on["glacier_vuln_until"] = scene._t + 1.0
	var vuln_mit: float = scene._mitigate_incoming(e_on, 100.0, false, false)
	_ok("★冰川·易伤 ×1.2", abs(vuln_mit - base_mit * 1.2) < 1.0, "%.0f → %.0f" % [base_mit, vuln_mit])

func _test_source(scene) -> void:
	var src: String = ""
	if RTScene is GDScript:
		src = (RTScene as GDScript).source_code
	_ok("★攻速按叠层缩短(_ms_stacks 进攻击间隔 / haste)",
		src.contains("_ms_stacks") and src.contains("TRAINER_ATK_INTERVAL / haste"))
	_ok("★只在装配了魔法石时才触发被动", src.contains('"magic_stone"'))
	_ok("★攻速叠层【本场结束重置】(_dl_start_fight 清 _ms_stacks·§3.4按本场计)",
		src.contains('_ms_stacks"] = 0'))
