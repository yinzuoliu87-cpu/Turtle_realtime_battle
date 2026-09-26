extends Node
## verify_seed_battles_gear.gd — 守卫「种子池里每个【场次】的装备配置」
##
## ★★★2026-09-26 从 `verify_bracket_gear.gd` 改名而来。原名里的「bracket」= 9 档进度档,
##   那套东西已按 D5 彻底删除(方案书 `docs/plans/20260926-删掉9档进度档.md`), 名字留着
##   会让下一个人以为档还在。**同名但无关**的周日对阵图(`scripts/gamedata/bracket.gd`)
##   由 `verify_bracket.gd` 管, 一个字没动。
##
## 起因(用户 2026-07-21 需求4): 「档位0应该模拟的是所有玩家在第一大轮的第一把,
## 所以不应该有携带装备」。查下来数据在【两个方向】都违反了代码自己的规则:
##   ①档0 发了 3 件, 但上限本来就该 0 件
##   ②档7/档8 各 15 件, 但上限是 12 件
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
	if not (parsed is Dictionary) or not (parsed as Dictionary).has(Backend.POOL_KEY):
		_ok("ghost_seed.json 结构正确(顶层有 %s)" % Backend.POOL_KEY, false,
			"实得键: %s" % (str((parsed as Dictionary).keys()) if parsed is Dictionary else "非 Dictionary"))
		get_tree().quit(1)
		return
	var buckets: Dictionary = (parsed as Dictionary)[Backend.POOL_KEY]

	## ★★★分桶键必须是【场次】而不是【档】。怎么区分这两者? 数格子:
	##   9 档只有 9 个键(0..8), 而按场次分至少覆盖 0~24(RANKED_QUOTA 一周配额)。
	##   ⇒ 键数 ≤ 9 就说明有人把档接回来了, 或者种子文件是旧结构。
	_ok("★★★分桶键是【场次】不是【档】(键数必须远超 9)", buckets.size() >= 25,
		"%d 个桶: %s…" % [buckets.size(), str(buckets.keys().slice(0, 12))])

	## ★每条快照自报的场次必须 == 它所在的桶键。两者不符 = 又回到"镜像字段会漂"那个坑,
	##   而匹配读的是快照自己那份 ⇒ 桶里的东西永远抽不到, 且一声不吭。
	var key_bad: Array = []
	var bns: Array = []
	for bk in buckets.keys():
		bns.append(int(str(bk)))
		for t in (buckets[bk] as Array):
			var tb := int((t as Dictionary).get("season_total_battles", -999))
			if tb != int(str(bk)):
				key_bad.append("%s 在桶%s 却自报 %d" % [str((t as Dictionary).get("ghost_id", "?")), str(bk), tb])
	_ok("★★桶键 == 快照自报的 season_total_battles", key_bad.is_empty(),
		"%d 处不符; %s" % [key_bad.size(), "; ".join(PackedStringArray(key_bad.slice(0, 3)))])

	## ★前 RANKED_QUOTA 个场次一格都不许空 —— 空一格 = 那个场次的玩家**必定**打机器人。
	##   (D5 把回落砍到只剩 bot 之后, 这条从"多样性问题"升级成"能不能匹配到人"。)
	var holes: Array = []
	for n in range(0, int(P2.RANKED_QUOTA) + 1):
		if not buckets.has(str(n)) or (buckets[str(n)] as Array).is_empty():
			holes.append(n)
	_ok("★★★场次 0~%d 每一格都有人(空一格 = 那个场次必打 bot)" % int(P2.RANKED_QUOTA),
		holes.is_empty(), "空的场次: %s" % str(holes))

	bns.sort()
	var checked_teams := 0
	var cap_bad: Array = []
	var t0_bad: Array = []
	var per_item: Array = []       # [场次, 件数, 单件均强度]

	for b in bns:
		var teams: Array = buckets[str(b)]
		var items := 0
		var strength := 0.0
		for team in teams:
			checked_teams += 1
			# ★装备容量统一规则(用户 2026-07-27): 单只(统领/小将) ≤ UNIT_EQUIP_CAP,
			#   且全队 6 只合计 ≤ team_equip_cap(该快照的赛季等级)。
			#   ★★2026-09-26 等级兜底从 `clampi(2 + 档, 1, 10)` 换成
			#     `P2.bot_level_for_battles(场次)` —— 档已删, 而且那条曲线是**量出来的**
			#     (拿这份种子池的真实装备件数中位反解, 见 phase2_config 那边头注)。
			var lv: int = int((team as Dictionary).get("season_level", 0))
			if lv <= 0:
				lv = P2.bot_level_for_battles(b)
			var team_cap: int = P2.team_equip_cap(lv)
			var team_used := 0
			var eqd: Dictionary = (team as Dictionary).get("equipped", {})
			for pid in eqd:
				var arr: Array = eqd[pid]
				team_used += arr.size()
				if arr.size() > P2.UNIT_EQUIP_CAP:
					cap_bad.append("场次%d %s 带了 %d 件(单只上限 %d)" % [b, pid, arr.size(), P2.UNIT_EQUIP_CAP])
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
						cap_bad.append("场次%d 小将带了 %d 件(单只上限 %d)" % [b, me.size(), P2.UNIT_EQUIP_CAP])
					for it2 in me:
						items += 1
						strength += _strength(_cost_of(str((it2 as Dictionary).get("id", ""))),
											  int((it2 as Dictionary).get("star", 1)))
					if b == 0 and me.size() > 0:
						t0_bad.append("场次0 小将带了 %d 件" % me.size())
			if team_used > team_cap:
				cap_bad.append("场次%d 全队 %d 件 > 上限 %d (Lv%d)" % [b, team_used, team_cap, lv])
		var avg: float = (strength / float(items)) if items > 0 else 0.0
		per_item.append([b, items, avg])
		if b == 0:
			_ok("★场次0 完全无装备(人生第一把)", items == 0, "实发 %d 件" % items)

	_ok("★场次0 的小将也无装备", t0_bad.is_empty(), "; ".join(PackedStringArray(t0_bad.slice(0, 3))))
	_ok("★装备容量: 单只≤%d 且 全队合计≤team_equip_cap(赛季等级)" % P2.UNIT_EQUIP_CAP,
		cap_bad.is_empty(), "%d 处违规; %s" % [cap_bad.size(), "; ".join(PackedStringArray(cap_bad.slice(0, 4)))])
	_ok("★核对分母非空(防空检查)", checked_teams >= 100, "核了 %d 支队" % checked_teams)

	_t_strength_ramp(per_item)
	_t_bot_curve_fits_data(buckets)
	_t_exact_only()

	print("ALL PASS — 种子池按场次的装备配置" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ══════════════════════════════════════════════════════════════════════
#  强度阶梯: 随场次上升
# ══════════════════════════════════════════════════════════════════════
## ★★★2026-09-26 判据从「逐【档】严格递增」改成「逐【场次】平滑后上升」。
##   **不是放宽, 是换到被测的那个量上**: 9 档时每档 20 条、一档一个点, 严格递增本来
##   就成立; 换成 36 个场次后每格 12 条、相邻两格只差半件装备 ⇒ 单点噪声必然造出逆序。
##   拿严格递增去卡它 = 判据窄一格放过真 bug 的同时造出假 bug
##   (memory fb-judge-must-fit-the-shape: 先打剖面再定阈值)。
## ⇒ 量两件真正要保的事: ① 五格滑动均值绝大多数步不下降 ② 尾段明显高于头段。
const MA_WINDOW := 5
const MA_NONDROP_FLOOR := 0.80

func _t_strength_ramp(per_item: Array) -> void:
	var seq: Array = []
	for r in per_item:
		seq.append(float((r as Array)[2]))
	if seq.size() < MA_WINDOW * 2:
		_ok("★强度阶梯: 分母够(至少 %d 个场次)" % (MA_WINDOW * 2), false, "只有 %d 个" % seq.size())
		return
	var ma: Array = []
	for i in range(seq.size() - MA_WINDOW + 1):
		var acc := 0.0
		for j in range(MA_WINDOW):
			acc += float(seq[i + j])
		ma.append(acc / float(MA_WINDOW))
	var steps: int = ma.size() - 1
	var down := 0
	for i in range(steps):
		if float(ma[i + 1]) < float(ma[i]) - 1e-9:
			down += 1
	var head := 0.0
	var tail := 0.0
	for j in range(MA_WINDOW):
		head += float(seq[j])
		tail += float(seq[seq.size() - 1 - j])
	head /= float(MA_WINDOW)
	tail /= float(MA_WINDOW)
	_ok("★强度阶梯: 滑动均值不下降的步数 ≥ %.0f%%" % (MA_NONDROP_FLOOR * 100.0),
		float(steps - down) >= float(steps) * MA_NONDROP_FLOOR,
		"不降 %d / 共 %d 步" % [steps - down, steps])
	_ok("★强度阶梯: 尾段明显高于头段(场次越多对手越强)", tail > head,
		"头段 %.2f → 尾段 %.2f" % [head, tail])


# ══════════════════════════════════════════════════════════════════════
#  ★★★bot 强度曲线必须**贴着真人数据**, 不是我拍的
# ══════════════════════════════════════════════════════════════════════
## bot 的强度只体现在一个地方: 装备预算 `team_equip_cap(bot_level_for_battles(场次))`。
## (快照里的 `pet_levels` 战斗侧**没人读** —— 2026-09-26 grep 全仓确认。)
##
## ★所以「bot 强度对不对」是可以量的: 拿这份种子池里**同场次真人**的全队装备件数中位数
##   当尺子, bot 的预算不许差太多。这是外部尺子, 不是我自己写的文档
##   (memory fb-completeness-needs-external-yardstick)。
##
## ★★实测(2026-09-26): 36 个场次里 33 个**完全命中**, 场次 4/17/21 差 1 件。
##   旧算法 `2 + 档` 在**场次 0** 那格差 2 件 —— 给 bot 2 件而真人是 0 件,
##   直接违反「人生第一把没装备」那条锚点。新曲线把它修回 0。
const BOT_FIT_TOL := 2             # 允许差几件(实测最大差 1)
const BOT_FIT_EXACT_FLOOR := 0.80  # 至少这么多比例的场次要**完全命中**

func _t_bot_curve_fits_data(buckets: Dictionary) -> void:
	var bad: Array = []
	var exact := 0
	var n_cmp := 0
	for bk in buckets.keys():
		var b := int(str(bk))
		var counts: Array = []
		for t in (buckets[bk] as Array):
			counts.append(_team_items(t as Dictionary))
		if counts.is_empty():
			continue
		counts.sort()
		var med: int = int(counts[counts.size() / 2])
		var cap: int = P2.team_equip_cap(P2.bot_level_for_battles(b))
		n_cmp += 1
		if cap == med:
			exact += 1
		elif absi(cap - med) > BOT_FIT_TOL:
			bad.append("场次%d: bot %d 件 vs 真人中位 %d 件" % [b, cap, med])
	_ok("★分母: 比对了 %d 个场次" % n_cmp, n_cmp >= 25, "只比了 %d 个" % n_cmp)
	_ok("★★★bot 装备预算与同场次真人中位差 ≤ %d 件" % BOT_FIT_TOL, bad.is_empty(),
		"%d 处超差; %s" % [bad.size(), "; ".join(PackedStringArray(bad.slice(0, 4)))])
	var rate := float(exact) / float(maxi(1, n_cmp))
	_ok("★★完全命中率 ≥ %.0f%%(曲线是量出来的, 不是拍的)" % (BOT_FIT_EXACT_FLOOR * 100.0),
		rate >= BOT_FIT_EXACT_FLOOR, "%d/%d = %.3f" % [exact, n_cmp, rate])
	## ★场次0 单列: 它是用户点名的那条锚点, 不许被"平均下来还行"盖过去。
	_ok("★★★场次0 的 bot 必须全裸(旧算法 2+档0 = Lv2 = 2 件, 违反「人生第一把没装备」)",
		P2.team_equip_cap(P2.bot_level_for_battles(0)) == 0,
		"cap=%d" % P2.team_equip_cap(P2.bot_level_for_battles(0)))


func _team_items(t: Dictionary) -> int:
	var n := 0
	for pid in (t.get("equipped", {}) as Dictionary):
		n += ((t["equipped"] as Dictionary)[pid] as Array).size()
	for lane in (t.get("minions", {}) as Dictionary):
		for slot in ((t["minions"] as Dictionary)[lane] as Array):
			n += ((slot as Dictionary).get("equips", []) as Array).size()
	return n


# ══════════════════════════════════════════════════════════════════════
#  ★★★「绝不撞到明显更强的对手」——【尺子换了, 意图没变】
# ══════════════════════════════════════════════════════════════════════
# 用户 2026-07-27「±1 这东西去掉」的实测代价(那时废掉的是 ±1 **格子**窗口):
#   第2把 档0(自己0件装备) 撞档1带3件; 第7把 我方强度43.0 撞99.0; 第10把 45.8 撞118.6(2.6倍)。
# 那条约束当年只能用"格子"表达 —— 因为当时没有更细的尺子。
#
# ★2026-09-26 现在用最细的尺子表达同一个意图: **双方总场次完全相同**(D5)。
#   用户原话:「从始至终应该都是同场次的人开打…不应该有什么正负一」。
#
# ⚠⚠ 这条判据 2026-09-25 一度**静默变成恒真式**: 入参含义从「档」改成「场次」而循环
#    变量还叫 `b`、还在 0..8 上跑、还拿返回快照的**格子**去比 ⇒ 两个不同的量互相比,
#    0 例越线、全绿、什么都没验。**改参数含义的那一刻, 拿它当参数的判据全都要重读一遍。**
# ⚠⚠ 它 2026-09-25 的第二版判的是「对手场次 ≤ 我 + 1」—— 那条**保证了**用户投诉的
#    那件事不会被发现(5 场次打 6 场次)。现在判的是 `==`, 没有容差。
func _t_exact_only() -> void:
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 20260727
	var over: Array = []
	var draws := 0
	var real_snaps := 0          # ★分母: 有多少抽真的抽到了池里的快照(不是 bot)
	for n in range(0, 31):
		for _i in range(12):
			var g: Dictionary = Backend.find_opponent(n, [], rng2)
			draws += 1
			if not bool(g.get("is_bot", false)):
				real_snaps += 1
			var gb := int(g.get("season_total_battles", -1))
			if gb != n:
				over.append("我 %d 场 → 抽到 %d 场(%s)" % [n, gb, str(g.get("ghost_id", "?"))])
	_ok("★★★对手总场次 == 我的总场次, 一次例外都没有(D5: 不许有正负一)", over.is_empty(),
		"分母 %d 抽 / 其中真快照 %d; 越线 %d 例: %s"
		% [draws, real_snaps, over.size(), "; ".join(PackedStringArray(over.slice(0, 3)))])
	_ok("★分母: 抽够了(%d 次)" % draws, draws == 31 * 12, "实抽 %d" % draws)
	_ok("★★分母: 真的抽到过池里的快照(全是 bot 的话上面那条是空检查)",
		real_snaps >= 100, "真快照 %d / %d 抽" % [real_snaps, draws])


## 用户给的换算: 强度 ≈ M费基础值 × 1.8^(N-1) × 技能系数(低费技能弱→系数低)
func _strength(cost: int, star: int) -> float:
	var k := {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}
	return float(cost) * pow(1.8, float(star - 1)) * float(k.get(cost, 1.0))


func _cost_of(eid: String) -> int:
	var e: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
	return int(e.get("cost", 1))
