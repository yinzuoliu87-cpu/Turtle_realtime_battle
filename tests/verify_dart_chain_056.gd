extends Node
## verify_dart_chain_056.gd — 056 飞镖【完整因果链】的后三环
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 第六批方案书登记的风险②, 一直欠着
## ══════════════════════════════════════════════════════════════════
## 文案(原话):
##   「任何敌人被己方击飞时即挂上「靶子」标记(不会自行消失);
##    携带者每 2.5 秒向所有带靶子的敌人各射 1 镖, 造成(130/190/600+1.5/3.0/9.0×攻击力)物理伤害
##    并施加 10%攻击力的流血层数, 命中后移除该敌人的靶子;
##    …每 5 下普攻会强化下一次普攻, 命中时将目标击飞 1 秒。」
##
## 链有五环: ①第 5 下 → ②击飞 → ③挂靶子 → ④下个周期射镖(伤害+流血) → ⑤命中后靶子移除。
## ①② 已由 `verify_equip_batch_20260730d._t_dart` 守着; **③④⑤ 在这之前一条断言都没有**。
##
## ★判据量产品自己的账(不量血量差, 不数我插的标记):
##   ③ `eq_target_until`(产品写的靶子字段) · 反证: 己方没有飞镖携带者时击飞【不】挂靶子
##   ④ `_st_taken`(伤害累计账) 增量 ≈ 130 + 1.5×ATK · `dot_stacks.bleed` 增量 = round(0.1×ATK)
##   ⑤ 命中后 `eq_target_until` 归零 · 下一周期无新击飞【不】再射(账不再涨)
##     · 「不会自行消失」: 不射镖的话 30 秒后靶子仍在
## ★期望值写死在本文件(文案原话里的数), 不读被测常量。
const WANT_FLAT_1STAR := 130.0
const WANT_ATK_MULT_1STAR := 1.5
const WANT_BLEED_PER_ATK := 0.10

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


## 干净合成单位(同 verify_equip_batch_20260730d 的 _mk: 护甲/魔抗/减伤/暴击/闪避全清零)
func _mk(id: String, side: String, off: Vector2, hp: float = 900000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	return u


## 推弹道直到它落地(或超时) —— 飞镖伤害走 `_ballistics._push_proj`(sim 推进, 不挂 tween)。
func _fly(sec: float) -> void:
	var steps: int = int(sec / 0.02)
	for _k in range(steps):
		_s._ballistics._step_projectiles(0.02)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 056 飞镖因果链后三环: ③击飞挂靶子 ④下周期射镖 ⑤命中后靶子移除 ===")
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED   # 全部手动推, 不让场景自己的 _process 插一脚
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""

	_s._units.clear()
	var car: Dictionary = _mk("fortune", "left", Vector2(-160.0, 0.0))
	car["equips"] = [{"id": "p2eq_056", "star": 1}]
	car["eq_state"] = {}
	var tgt: Dictionary = _mk("green", "right", Vector2(120.0, 0.0))
	_s._units.append_array([car, tgt])
	_s._equip_sys._stats._eq_apply_all_stats()
	var atk: float = float(car["atk"])
	print("     [探针] 携带者 ATK=%.1f · 期望镖伤 %.1f · 期望流血 %d 层"
		% [atk, WANT_FLAT_1STAR + WANT_ATK_MULT_1STAR * atk, roundi(WANT_BLEED_PER_ATK * atk)])

	# ── ③ 击飞 → 挂靶子 ──
	_ok("★分母①: 击飞之前目标没有靶子(eq_target_until=%.1f ≤ _t=%.1f)"
		% [float(tgt.get("eq_target_until", 0.0)), _s._t],
		float(tgt.get("eq_target_until", 0.0)) <= _s._t, "")
	for _h in range(5):
		_s._equip_sys._eq_on_hit(car, tgt, 10, true)   # 第 5 下普攻 ⇒ 强化击飞(环①② 另有门禁)
	_ok("★分母②: 第 5 下之后目标真的在空中(airborne=%s)" % str(tgt.get("airborne", false)),
		bool(tgt.get("airborne", false)), "没被击飞 ⇒ 环③ 的输入不在场")
	## ③a 击退函数【当场】挂靶子(不等下一帧 _tick_unit 补) —— 挂靶子有两个写入点, 各验各的:
	##   这条守 `battle_damage.gd` 击退函数那一处, ③b 守 `_tick_unit` 那一处。
	##   (2026-09-15 反向验证: 只有 ③ 的话, 任一处改坏另一处都会替它补上 ⇒ 一条都不红)
	_ok("③a 击退函数当场挂上靶子(还没过帧, 剩 %.0f 秒)" % (float(tgt.get("eq_target_until", 0.0)) - _s._t),
		float(tgt.get("eq_target_until", 0.0)) - _s._t > 1000.0,
		"击退当下没挂 ⇒ 全靠下一帧 _tick_unit 补, 那条路一断就全断")
	_s._tick_unit(tgt, 0.016)   # 真入口: 挂靶子的判定在 _tick_unit 的 airborne 分支里
	_ok("③ 被己方击飞 ⇒ 挂上靶子(eq_target_until - _t = %.0f 秒, 文案「不会自行消失」)"
		% (float(tgt.get("eq_target_until", 0.0)) - _s._t),
		float(tgt.get("eq_target_until", 0.0)) - _s._t > 1000.0,
		"击飞了却没挂靶子")

	## ③b 另一条挂靶子的路 —— 技能【直接】把单位设成 airborne(不走击退函数)。
	## ★由来(2026-09-15 反向验证): 把 `_tick_unit` airborne 分支里挂靶子那一行改成 0,
	##   上面那条 ③ 照样绿 —— 因为第 5 下击飞走的是 `battle_damage.gd` 击退函数里的另一个写入点。
	##   `_tick_unit` 那一条是专门补「直接设 airborne 的技能 + 已在空中再击飞」的
	##   (主场景注释: 用户 2026-07-18「很多被击飞没触发」), 必须单独验到它。
	var tgt3: Dictionary = _mk("green", "right", Vector2(200.0, -90.0))
	_s._units.append(tgt3)
	tgt3["airborne"] = true
	tgt3["vy"] = 3.0
	tgt3["height"] = 0.2
	_s._tick_unit(tgt3, 0.016)
	_ok("③b 被技能【直接】设成击飞(不走击退函数) ⇒ 也挂上靶子(剩 %.0f 秒)" % (float(tgt3.get("eq_target_until", 0.0)) - _s._t),
		float(tgt3.get("eq_target_until", 0.0)) - _s._t > 1000.0,
		"直接设 airborne 的技能击飞不挂靶子 ⇒ 用户 07-18 那条「很多被击飞没触发」回来了")
	_s._units.erase(tgt3)

	## ③ 反证: 己方【没有】飞镖携带者时, 击飞不挂靶子(否则判据是恒真式)
	var tgt2: Dictionary = _mk("green", "right", Vector2(180.0, 90.0))
	_s._units.append(tgt2)
	car["equips"] = []
	tgt2["airborne"] = true
	tgt2["vy"] = 3.0
	tgt2["height"] = 0.2
	_s._tick_unit(tgt2, 0.016)
	_ok("③ 反证: 己方没有飞镖携带者时击飞【不】挂靶子(eq_target_until=%.1f)" % float(tgt2.get("eq_target_until", 0.0)),
		float(tgt2.get("eq_target_until", 0.0)) <= _s._t, "谁被击飞都挂 ⇒ 判据③ 分辨不出")
	car["equips"] = [{"id": "p2eq_056", "star": 1}]
	_s._units.erase(tgt2)

	## 「不会自行消失」: 过 30 秒(不射镖)靶子还在
	_s._t += 30.0
	_ok("③ 靶子【不会自行消失】: 30 秒后仍在(剩 %.0f 秒)" % (float(tgt.get("eq_target_until", 0.0)) - _s._t),
		float(tgt.get("eq_target_until", 0.0)) > _s._t, "")

	# ── ④ 下个周期射镖: 量伤害账与流血层 ──
	tgt["airborne"] = false
	tgt["height"] = 0.0
	var taken0: int = int(tgt.get("_st_taken", 0))
	var bleed0: int = int((tgt.get("dot_stacks", {}) as Dictionary).get("bleed", 0))
	car["eq_timer"] = float(_s.EQ_TICK)   # 逼出一个周期(真入口 _eq_tick 的节拍闸)
	_s._equip_sys._eq_tick(car, 0.0)
	## ⑤ 同步: 射镖那一刻靶子就该移除(文案「命中后移除」—— 产品在发射时清, 记录实际行为)
	var mark_after_fire: float = float(tgt.get("eq_target_until", -1.0))
	_fly(2.0)
	var dmg: int = int(tgt.get("_st_taken", 0)) - taken0
	var bleed: int = int((tgt.get("dot_stacks", {}) as Dictionary).get("bleed", 0)) - bleed0
	var want_dmg: float = WANT_FLAT_1STAR + WANT_ATK_MULT_1STAR * atk
	_ok("④ 下个周期真的射了镖并命中: 伤害账 +%d(期望 ≈ %.0f = 130 + 1.5×ATK)" % [dmg, want_dmg],
		dmg > 0 and absf(float(dmg) - want_dmg) <= maxf(2.0, want_dmg * 0.02),
		"没打中 / 数不对")
	_ok("④ 命中施加流血: +%d 层(期望 round(0.1×ATK) = %d)" % [bleed, roundi(WANT_BLEED_PER_ATK * atk)],
		bleed == maxi(1, roundi(WANT_BLEED_PER_ATK * atk)), "")

	# ── ⑤ 靶子移除 + 下一周期不再射 ──
	_ok("⑤ 射镖后靶子被移除(eq_target_until=%.1f)" % mark_after_fire,
		mark_after_fire <= _s._t, "靶子没清 ⇒ 每个周期都会一直射同一个人")
	var taken1: int = int(tgt.get("_st_taken", 0))
	car["eq_timer"] = float(_s.EQ_TICK)
	_s._equip_sys._eq_tick(car, 0.0)
	_fly(2.0)
	_ok("⑤ 没有新击飞 ⇒ 下一周期【不再】射镖(伤害账 +%d)" % (int(tgt.get("_st_taken", 0)) - taken1),
		int(tgt.get("_st_taken", 0)) == taken1, "靶子移除了还在射")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
