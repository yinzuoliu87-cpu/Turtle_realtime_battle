extends Node
## verify_bracket_gear.gd — 守卫「快照档位的装备配置」(用户 2026-07-21 需求4)
##
## 起因: 用户「档位0应该模拟的是所有玩家在第一大轮的第一把, 所以不应该有携带装备」。
## 查下来数据在【两个方向】都违反了代码自己的规则:
##   ①档0 发了 3 件, 但 equip_slots_for_battles(1) == 0 —— 本来就该 0 槽
##   ②档7/档8 各 15 件, 但上限是 4槽×3龟 = 12 件
## 而且强度梯度不按用户给的云顶梯队走(旧档8 全 5费3星, 用户明确说 5费3星"几乎不存在")。
##
## ★这类数据错误【不报错、不崩溃】, 只会让匹配到的对手强度失真, 只能靠测试守。

const P2 := preload("res://scripts/engine/phase2_config.gd")
const Backend := preload("res://scripts/engine/backend.gd")

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	var f := FileAccess.open("res://data/ghost_seed.json", FileAccess.READ)
	if f == null:
		_ok("读取 ghost_seed.json", false, "打不开")
		get_tree().quit(1)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("brackets"):
		_ok("ghost_seed.json 结构正确", false)
		get_tree().quit(1)
		return
	var brackets: Dictionary = (parsed as Dictionary)["brackets"]
	_ok("解析到档位", brackets.size() >= 9, "%d 档" % brackets.size())

	var prev_avg := 0.0
	var checked_teams := 0
	var cap_bad: Array = []
	var t0_bad: Array = []
	var ramp: Array = []

	for bk in ["0", "1", "2", "3", "4", "5", "6", "7", "8"]:
		if not brackets.has(bk):
			continue
		var b := int(bk)
		var battles: int = Backend.battles_for_bracket(b)
		var cap_per_pet: int = P2.equip_slots_for_battles(battles)
		var teams: Array = brackets[bk]
		var items := 0
		var strength := 0.0
		for team in teams:
			checked_teams += 1
			var eqd: Dictionary = (team as Dictionary).get("equipped", {})
			for pid in eqd:
				var arr: Array = eqd[pid]
				# ★每龟件数不得超过该档槽位上限
				if arr.size() > cap_per_pet:
					cap_bad.append("档%s %s 带了 %d 件(上限 %d)" % [bk, pid, arr.size(), cap_per_pet])
				for it in arr:
					items += 1
					strength += _strength(_cost_of(str((it as Dictionary).get("id", ""))),
										  int((it as Dictionary).get("star", 1)))
			# 档0 连小将也不能有装备
			if b == 0:
				var mn: Dictionary = (team as Dictionary).get("minions", {})
				for lane in mn:
					for slot in (mn[lane] as Array):
						var me: Array = (slot as Dictionary).get("equips", [])
						if me.size() > 0:
							t0_bad.append("档0 小将带了 %d 件" % me.size())
		var avg: float = (strength / float(items)) if items > 0 else 0.0
		ramp.append([b, items, avg])
		if b == 0:
			_ok("★档0 完全无装备(第一大轮第一把)", items == 0, "实发 %d 件" % items)
		else:
			if avg > 0.0 and prev_avg > 0.0:
				# 强度必须单调递增(档越高对手越强)
				if avg <= prev_avg:
					_ok("★档%d 强度高于上一档" % b, false,
						"本档均强度 %.2f <= 上档 %.2f" % [avg, prev_avg])
			if avg > 0.0:
				prev_avg = avg

	_ok("★档0 的小将也无装备", t0_bad.is_empty(), "; ".join(PackedStringArray(t0_bad.slice(0, 3))))
	_ok("★每龟装备件数不超该档槽位上限(代码 equip_slots_for_battles 说了算)",
		cap_bad.is_empty(), "; ".join(PackedStringArray(cap_bad.slice(0, 4))))
	_ok("★核对分母非空(防空检查)", checked_teams >= 100, "核了 %d 支队" % checked_teams)

	# 强度阶梯单调递增
	var mono := true
	var last := 0.0
	var ramp_txt := ""
	for r in ramp:
		var a: float = float((r as Array)[2])
		ramp_txt += "档%d:%.1f " % [int((r as Array)[0]), a]
		if a > 0.0:
			if a <= last:
				mono = false
			last = a
	_ok("★强度阶梯单调递增(档越高对手越强)", mono, ramp_txt)

	print("ALL PASS — 快照档位装备配置" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 用户给的换算: 强度 ≈ M费基础值 × 1.8^(N-1) × 技能系数(低费技能弱→系数低)
func _strength(cost: int, star: int) -> float:
	var k := {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}
	return float(cost) * pow(1.8, float(star - 1)) * float(k.get(cost, 1.0))


func _cost_of(eid: String) -> int:
	var e: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	return int(e.get("cost", 1))
