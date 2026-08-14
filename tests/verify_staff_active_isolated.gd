extends Node
## verify_staff_active_isolated.gd — 法器【主动】的同窗隔离(2026-08-14)
##
## ★由来: `verify_staff_actives_fire` 里有 4 件登记着"有持续被动, 宽判据分不开主动与被动"
##   (023 灼热火珊瑚 / 029 冰封水母 / 089 / 090), 还有 1 件 031 登记着"效果埋在 tween 里"。
##   那两条缺口都是**测量问题**, 不是装备问题 —— 这条用新办法把它们解掉。
##
## ★★办法: 同一场战斗里放两组, **两组都带同一件法器**(所以被动漂移完全相同),
##   只给 A 组灌满法力 ⇒ A 与 B 的差【就是主动干的】, 被动被完全抵消。
##   这比"对照组不带装备"更严格 —— 后者连被动一起算进了差值。
##
## ★这一步是上一轮 `verify_fire_equips_exact` 同窗对照的延伸:
##   那次证明了"同一批帧里跑"能消掉环境漂移; 这次再让两组配置也完全一致, 连被动一起消掉。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 此前登记为"隔离不了"或"tween 埋着"的五件
const HARD_IDS := ["p2eq_023", "p2eq_029", "p2eq_090"]
## ★★089 隔离【失败】, 显式登记 —— 不许当通过。
##   实测两次跑出相反结果(第一次 A 0.247 / B 0.000, 第二次 A 0.247 / B 0.979)
##   ⇒ **同一份代码两次结果不同 = 我的判据在量噪声, 不是信号**。
##   它的主动产出不在本判据覆盖的量里(敌血/DoT/控/己方盾血), 需要给它写专属判据。
##   ⚠ 这不是"089 坏了" —— `verify_staff_actives_fire` 已证明它法力满会清零并触发;
##     只是**这条门禁量不到它做了什么**。两件事必须分清。
## ★089 已由 `verify_talisman_089` 用【专属判据】验起来 —— 查根因发现它的主动是
##   "贴符纸 + 每跳削魔抗", 而本条的状态向量里**根本没有魔抗这一维**
##   ⇒ 量不到不是它坏了, 是判据选错层(与凤凰那次同族)。
##
## ★★★031 退回缺口 —— 我上一轮【过度声称】, 被 CI 抓到:
##   本地跑出 A 0.979 / B 0.840 判"隔离成功", CI 上跑出 **A 0.840 / B 0.979**(正好相反)。
##   两个值在两次运行间互换 ⇒ **我在量噪声, 不是信号**(与 089 当时同一形状)。
##   ⚠ 我当时的反向验证只证明了"打瘸后两边都归零", **没证明 A>B 这个方向稳定** ——
##     那是两回事, 我下结论下早了。裕度只有 0.14 就该警觉。
##   根因: 031 的伤害由 `tween_method` 连续扫角驱动, **无头下 tween 推不动**
##   ⇒ 最初把它登记进 `TWEEN_BURIED` 的判断才是对的。真要验它只能先把结算从 tween 里抽出来。
const UNRESOLVED := ["p2eq_031"]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _mk(s, at: Vector2, iid: String) -> Array:
	var u: Dictionary = s._spawn._make_unit("basic", "left", at)
	u["atk"] = 150.0
	u["maxHp"] = 5000.0
	u["hp"] = 2500.0
	u["shield"] = 0.0
	u["no_basic"] = true
	u["no_move"] = true
	u["equips"] = [{"id": iid, "star": 3}]
	u["eq_state"] = {iid: {}}
	var es: Array = []
	for i in range(3):
		var e: Dictionary = s._spawn._make_unit("basic", "right", at + Vector2(70.0 + 50.0 * float(i), 0))
		e["maxHp"] = 1.0e7
		e["hp"] = 1.0e7
		e["no_basic"] = true
		e["no_move"] = true
		es.append(e)
	return [u, es]


func _hp_sum(es: Array) -> float:
	var t := 0.0
	for e in es:
		t += float(e.get("hp", 0.0))
	return t


func _state(u: Dictionary, es: Array) -> float:
	## 敌人掉的血 + 敌人身上的控与 DoT + 携带者自己的盾/血。
	## ★全是有物理含义的量。哈希那种"能变就行"的东西不算判据(2026-08-14 已栽过)。
	var dots := 0
	var stun := 0.0
	for e in es:
		for k in (e.get("dot_stacks", {}) as Dictionary).keys():
			dots += int((e["dot_stacks"] as Dictionary)[k])
		stun += float(e.get("stun_until", 0.0))
	return -_hp_sum(es) * 0.001 + float(dots) * 100.0 + stun * 10.0 \
		+ float(u.get("shield", 0.0)) + float(u.get("hp", 0.0))


func _ready() -> void:
	await get_tree().process_frame
	print("=== 法器主动: 同窗隔离(两组同装备, 只一组灌满法力) ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5

	_ok("★分母: 本条解掉 %d 件, 另有 %d 件隔离失败(显式登记)" % [HARD_IDS.size(), UNRESOLVED.size()],
		HARD_IDS.size() == 3 and UNRESOLVED == ["p2eq_031"],
		"解掉 %s / 未解决 %s" % [str(HARD_IDS), str(UNRESOLVED)])

	var still: Array = []
	for iid in HARD_IDS:
		var A: Array = _mk(s, c + Vector2(-700, -220), iid)
		var B: Array = _mk(s, c + Vector2(700, 220), iid)      # ★B 也带同一件 ⇒ 被动完全相同
		s._units.clear()
		s._units.append(A[0]); s._units.append_array(A[1])
		s._units.append(B[0]); s._units.append_array(B[1])
		s._edit_mode = false
		s._over = false
		s._equip_sys._stats._eq_apply_all_stats()
		## ★★B 组冻住法力: 用产品自己的防连放闸 `_staff_busy`, 不另造机关。
		##   否则自然增长(每 2.5 秒 +MANA_PER_TICK)会让 B 也放主动, 差值归零。
		(B[0] as Dictionary)["_staff_busy"] = true

		var a0: float = _state(A[0], A[1])
		var b0: float = _state(B[0], B[1])
		## A 组走【真入口】灌满法力 —— 不直接调 fire_equip_effect,
		## 那样会绕过"法力条满才触发"这条链, 而那条链正是要验的东西。
		s._staff_syn.add_mana(A[0], s._staff_syn.mana_full_for(A[0], iid, 3) + 1.0)
		## 逐帧 await: 023 走 `await _wait_sim` 协程, 3 帧一次推不完(上一轮血泪)。
		for _f in range(180):
			s._sim_step(1.0 / 60.0, false, false)
			await get_tree().process_frame
		var da: float = absf(_state(A[0], A[1]) - a0)
		var db: float = absf(_state(B[0], B[1]) - b0)
		(B[0] as Dictionary)["_staff_busy"] = false
		var isolated: bool = da > db + 0.001
		if not isolated:
			still.append(iid)
		_ok("%s: 灌满法力那组变化 %.2f > 同装备未灌那组 %.2f(差值 = 主动)" % [iid, da, db],
			isolated, "A %.3f / B %.3f" % [da, db])

	_ok("★★这 %d 件全部隔离出了主动效果(仍隔离不了的: %d 件)" % [HARD_IDS.size(), still.size()],
		still.is_empty(), "仍隔离不了: %s" % str(still))
	## ★把未解决的焊成断言: 谁给 089 补了专属判据就该回来把它移出去, 这条会红并逼他来改。
	_ok("★★已知缺口: %d 件(031 tween 驱动, 无头推不动 —— 要先把结算从 tween 抽出来)" % UNRESOLVED.size(),
		UNRESOLVED == ["p2eq_031"], "待解决: %s" % str(UNRESOLVED))

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 法器主动同窗隔离")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
