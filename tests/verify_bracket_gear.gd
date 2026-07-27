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

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const Backend := preload("res://scripts/net/backend.gd")

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
		var teams: Array = brackets[bk]
		var items := 0
		var strength := 0.0
		for team in teams:
			checked_teams += 1
			# ★装备容量统一规则(用户 2026-07-27): 单只(统领/小将) ≤ UNIT_EQUIP_CAP,
			#   且全队 6 只合计 ≤ team_equip_cap(该快照的赛季等级)。
			#   旧断言用的是 equip_slots_for_battles(每只固定N件) —— 那是【敌我两把尺子】里
			#   敌方那把, 玩家侧根本不走它。队列模拟(真玩家规则)在档1 装 2 件就被它误判成违规。
			#   老快照没有 season_level → 回落到 make_bot 的口径 clamp(2+档,1,10)。
			var lv: int = int((team as Dictionary).get("season_level", 0))
			if lv <= 0:
				lv = clampi(2 + b, 1, 10)
			var team_cap: int = P2.team_equip_cap(lv)
			var team_used := 0
			var eqd: Dictionary = (team as Dictionary).get("equipped", {})
			for pid in eqd:
				var arr: Array = eqd[pid]
				team_used += arr.size()
				if arr.size() > P2.UNIT_EQUIP_CAP:
					cap_bad.append("档%s %s 带了 %d 件(单只上限 %d)" % [bk, pid, arr.size(), P2.UNIT_EQUIP_CAP])
				for it in arr:
					items += 1
					strength += _strength(_cost_of(str((it as Dictionary).get("id", ""))),
										  int((it as Dictionary).get("star", 1)))
			# ★小将也算进【同一份】全队预算与单只上限 —— 旧版只查统领, 小将装多少都不管
			var mn: Dictionary = (team as Dictionary).get("minions", {})
			for lane in mn:
				for slot in (mn[lane] as Array):
					var me: Array = (slot as Dictionary).get("equips", [])
					team_used += me.size()
					if me.size() > P2.UNIT_EQUIP_CAP:
						cap_bad.append("档%s 小将带了 %d 件(单只上限 %d)" % [bk, me.size(), P2.UNIT_EQUIP_CAP])
					for it2 in me:
						items += 1
						strength += _strength(_cost_of(str((it2 as Dictionary).get("id", ""))),
											  int((it2 as Dictionary).get("star", 1)))
					if b == 0 and me.size() > 0:
						t0_bad.append("档0 小将带了 %d 件" % me.size())
			if team_used > team_cap:
				cap_bad.append("档%s 全队 %d 件 > 上限 %d (Lv%d)" % [bk, team_used, team_cap, lv])
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
	_ok("★装备容量: 单只≤%d 且 全队合计≤team_equip_cap(赛季等级)" % P2.UNIT_EQUIP_CAP,
		cap_bad.is_empty(), "%d 处违规; %s" % [cap_bad.size(), "; ".join(PackedStringArray(cap_bad.slice(0, 4)))])
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

	# ★匹配绝不越档 (用户 2026-07-27「±1 这东西去掉」)
	#   起因: 自动玩家 30 把实测 ±1 窗口(backend.gd 旧 find_opponent)的代价 ——
	#   第2把 档0(自己0件装备) 撞档1带3件; 第7把 我方强度43.0 撞99.0; 第10把 45.8 撞118.6(2.6倍)。
	#   现在 find_opponent 只抽本档、空了只往【低】档回落。这条断言守住"绝不往上"。
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260727
	var over: Array = []
	var draws := 0
	for b in range(0, 9):
		for _i in range(40):
			var g: Dictionary = Backend.find_opponent(b, [], rng2)
			draws += 1
			if int(g.get("bracket", 0)) > b:
				over.append("档%d 抽到档%d(%s)" % [b, int(g.get("bracket", 0)), str(g.get("ghost_id", "?"))])
	_ok("★匹配绝不越档(档N 玩家只遇 ≤N 档对手)", over.is_empty(),
		"分母 %d 抽; 越档 %d 例: %s" % [draws, over.size(), "; ".join(PackedStringArray(over.slice(0, 3)))])
	_ok("★分母非空(抽够了才算数)", draws == 360, "实抽 %d" % draws)

	print("ALL PASS — 快照档位装备配置" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 用户给的换算: 强度 ≈ M费基础值 × 1.8^(N-1) × 技能系数(低费技能弱→系数低)
func _strength(cost: int, star: int) -> float:
	var k := {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}
	return float(cost) * pow(1.8, float(star - 1)) * float(k.get(cost, 1.0))


func _cost_of(eid: String) -> int:
	var e: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	return int(e.get("cost", 1))
