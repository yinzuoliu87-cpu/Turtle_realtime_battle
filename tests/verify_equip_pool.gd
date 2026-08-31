extends Node
## verify_equip_pool.gd — 装备【私人池】门禁（批 2 · 方案书 20260802-装备扩充 §4.6 · D6/D20~D23）
##
## 在此之前商店是【无限张有放回】—— 3★ 只受钱和运气限制。私人池给每件装备有限张数。
## ★池子出错是**玩家永远看不见**的那类 bug：少几张只表现为"这件我怎么老抽不到"，
##   多几张只表现为"好像挺好合"，两边都没有任何提示。所以门禁必须逐条量。
##
## 守六组：
##   ① 池深 == 云顶值 +1，且**每件都 ≥ 9**（张数 <9 ⇒ 该件 3★ 在数学上不可能，是硬约束）
##   ② 满池只收 shopAvailable==1 的件；件数对得上
##   ③ 买走扣 1 张；★张数不够时**整笔失败**（不能凭空造张，也不能扣成负数）
##   ④ ★★守恒律：买 9 张 → 合出 3★ → 卖掉，池子**恰好**回到原样
##      —— D21/D22 字面冲突就是被这条断言逼出来的（详见 equip_pool.gd 末尾）
##   ⑤ 赛季重置后池是满的
##   ⑥ 掷货只出【池里还有张】的件；抽空的件不再出现（D23 的配套：本轮不出重复）
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_equip_pool.tscn

const EquipPoolS := preload("res://scripts/gamedata/equip_pool.gd")
const Phase2Equip := preload("res://scripts/gamedata/phase2_equip.gd")

## ★写字面值，不引用被测常量 —— 引用的话把 DEPTH 改掉测试照样全绿（恒真式）。
const WANT_DEPTH := {1: 31, 2: 26, 3: 19, 4: 11, 5: 10}
const MIN_FOR_3STAR := 9      # 一件 3★ = 9 张 1★

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload GameState"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 装备私人池 (批2) ===")

	var eqs: Array = DataRegistry.phase2_equipment

	# ── ① 池深 ──────────────────────────────────────────────────
	var bad_depth: Array = []
	for c in [1, 2, 3, 4, 5]:
		var got: int = int(EquipPoolS.DEPTH.get(c, -1))
		if got != int(WANT_DEPTH[c]):
			bad_depth.append("%d费 期望 %d 实得 %d" % [c, int(WANT_DEPTH[c]), got])
		if got < MIN_FOR_3STAR:
			bad_depth.append("%d费 只有 %d 张 < 9 ⇒ 该费用的 3★ 数学上不可能" % [c, got])
	_ok("① 池深 == 云顶值+1 且每档 ≥9(3★ 的数学下限)", bad_depth.is_empty(), str(bad_depth))
	_ok("① 份数口径 1★=1 / 2★=3 / 3★=9",
		EquipPoolS.shares_of(1) == 1 and EquipPoolS.shares_of(2) == 3 and EquipPoolS.shares_of(3) == 9,
		"%d/%d/%d" % [EquipPoolS.shares_of(1), EquipPoolS.shares_of(2), EquipPoolS.shares_of(3)])

	# ── ② 满池 ──────────────────────────────────────────────────
	var full: Dictionary = EquipPoolS.full_pool(eqs)
	var want_n := 0
	var not_shop: Array = []
	for e in eqs:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			want_n += 1
		elif full.has(str((e as Dictionary).get("id", ""))):
			not_shop.append(str((e as Dictionary).get("id", "")))
	_ok("② ★分母: 满池 %d 件 == shopAvailable 的件数 %d" % [full.size(), want_n],
		full.size() == want_n and want_n > 0)
	_ok("② 不上商店的件不进池(反向断言)", not_shop.is_empty(), str(not_shop))
	var bad_v: Array = []
	for e in eqs:
		var eid: String = str((e as Dictionary).get("id", ""))
		if not full.has(eid):
			continue
		var want: int = int(WANT_DEPTH.get(int((e as Dictionary).get("cost", 3)), -1))
		if int(full[eid]) != want:
			bad_v.append("%s(费%d) 期望 %d 实得 %d" % [eid, int((e as Dictionary).get("cost", 3)), want, int(full[eid])])
	_ok("② 逐件张数 == 该费用的池深", bad_v.is_empty(), str(bad_v.slice(0, 4)))

	# ── ③ 买走 / 买不到 ─────────────────────────────────────────
	var pool: Dictionary = EquipPoolS.full_pool(eqs)
	var eid1: String = _first_cost(eqs, 1)
	var n0: int = int(pool[eid1])
	_ok("③ 买 1 张 → 剩 %d" % (n0 - 1),
		EquipPoolS.take(pool, eid1, 1) and int(pool[eid1]) == n0 - 1, "实得 %d" % int(pool[eid1]))
	pool[eid1] = 2
	_ok("③ ★张数不够时【整笔失败】且不扣(不能扣成负数)",
		EquipPoolS.take(pool, eid1, 3) == false and int(pool[eid1]) == 2, "实得 %d" % int(pool[eid1]))
	_ok("③ 池里没有的 id 买不到(不凭空造键)",
		EquipPoolS.take(pool, "p2eq_nonexistent", 1) == false and not pool.has("p2eq_nonexistent"))

	# ── ④ ★★守恒律 ─────────────────────────────────────────────
	# 买 9 张 → 合成 3★ → 卖掉，池子必须【恰好】回到原样。
	# ★这条是 D21(满3★冻结) 与 D22(卖出退张) 字面冲突的检出者：
	#   第一版把"冻结"写成池里的 -1，于是卖掉 3★ 退不回来 ⇒ 池子永久少 31 张，这条当场红。
	#   解法是不存冻结状态、改由库存(_maxed_item_ids)驱动，详见 equip_pool.gd 末尾。
	var pool2: Dictionary = EquipPoolS.full_pool(eqs)
	var base: int = int(pool2[eid1])
	for i in range(9):
		EquipPoolS.take(pool2, eid1, 1)
	_ok("④ 买 9 张后剩 %d" % (base - 9), int(pool2[eid1]) == base - 9, "实得 %d" % int(pool2[eid1]))
	# 合成不动池（9 张已经在买的时候扣过了；一件 3★ 就是"占着这 9 张"）
	_ok("④ 合成【不】再扣张(9 张买的时候已扣, 3★ 只是占着它们)", int(pool2[eid1]) == base - 9)
	EquipPoolS.give_back(pool2, eid1, EquipPoolS.shares_of(3))
	_ok("④ ★★守恒律: 买9张→合3★→卖掉, 池子恰好回到 %d" % base,
		int(pool2[eid1]) == base, "实得 %d" % int(pool2[eid1]))
	# 反向: 若按 1 张退(而不是按份数), 守恒立刻破 —— 证明 ④ 不是恒真式
	var pool3: Dictionary = EquipPoolS.full_pool(eqs)
	for i in range(9):
		EquipPoolS.take(pool3, eid1, 1)
	EquipPoolS.give_back(pool3, eid1, 1)
	_ok("④ ★对照: 若只退 1 张则池子少 8 张(证明守恒断言非恒真)",
		int(pool3[eid1]) == base - 8, "实得 %d" % int(pool3[eid1]))

	# ── ⑤ GameState 侧: 赛季重置后池是满的 ──────────────────────
	gs.start_new_season()
	gs.ensure_equip_pool()
	var same := true
	var fullref: Dictionary = EquipPoolS.full_pool(eqs)
	for k in fullref:
		if int(gs.equip_pool.get(k, -999)) != int(fullref[k]):
			same = false
			break
	_ok("⑤ 赛季重置后池是满的(逐件比对 %d 件)" % fullref.size(),
		same and gs.equip_pool.size() == fullref.size(),
		"池 %d 件" % gs.equip_pool.size())
	# 买 / 卖 走 GameState 的 API
	var before: int = gs.pool_left(eid1)
	_ok("⑤ GameState.pool_take 扣 1 张", gs.pool_take(eid1, 1) and gs.pool_left(eid1) == before - 1,
		"%d → %d" % [before, gs.pool_left(eid1)])
	gs.pool_give_back(eid1, 1)
	_ok("⑤ GameState.pool_give_back(1★) 退 1 张", gs.pool_left(eid1) == before,
		"实得 %d" % gs.pool_left(eid1))

	# ── ⑥ 掷货只出池里有货的 ────────────────────────────────────
	# 把 1 费的件全部抽空, 断言掷出来的 1 费件里没有它们。
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drained: Dictionary = EquipPoolS.full_pool(eqs)
	var drained_ids: Array = []
	for e in eqs:
		var eid: String = str((e as Dictionary).get("id", ""))
		## ★【无限件】(096 小木斧)不参与"抽空"这条 —— 它按设计就抽不空(用户 2026-08-31
		##   「在卡池没有数量限制」)。把它算进来的话这条断言必红, 而红的是需求不是 bug。
		##   ⇒ 下面单独给它一条**反向**断言: 抽 0 之后它必须**仍在**可掷货列表里。
		if EquipPoolS.UNLIMITED.has(eid):
			continue
		if int((e as Dictionary).get("cost", 0)) == 1 and drained.has(eid):
			drained[eid] = 0
			drained_ids.append(eid)
	_ok("⑥ ★分母: 抽空了 %d 件 1 费装备" % drained_ids.size(), drained_ids.size() >= 5)
	var avail: Array = EquipPoolS.available(drained, eqs)
	var leaked: Array = []
	for e in avail:
		if str((e as Dictionary).get("id", "")) in drained_ids:
			leaked.append(str((e as Dictionary).get("id", "")))
	_ok("⑥ 抽空的件不再进可掷货列表", leaked.is_empty(), str(leaked))
	## ★★无限件的反面: 把它的张数按到 0, 它**仍然**要在可掷货列表里。
	##   只写上面那条"抽空的不出"是不够的 —— 那样把 096 从 UNLIMITED 里删掉也照样绿。
	var un_ok := true
	var un_n := 0
	for eid2 in EquipPoolS.UNLIMITED.keys():
		drained[eid2] = 0
		un_n += 1
		var still := false
		for e2 in EquipPoolS.available(drained, eqs):
			if str((e2 as Dictionary).get("id", "")) == str(eid2):
				still = true
		if not still:
			un_ok = false
	_ok("⑥ ★★无限件张数按到 0 后【仍在】可掷货列表(卡池无数量限制)", un_ok and un_n > 0,
		"无限件 %d 个" % un_n)

	# D23 的配套: 同一次掷货不出重复
	var offer: Array = Phase2Equip.roll_shop(eqs, 10, 10, rng)
	var seen: Dictionary = {}
	var dup: Array = []
	for o in offer:
		if o == null:
			continue
		var oid: String = str((o as Dictionary).get("id", ""))
		if seen.has(oid):
			dup.append(oid)
		seen[oid] = true
	_ok("⑥ ★同一次掷货不出重复(D23 的配套: 池不动货架 ⇒ 重复要在掷货时去掉)",
		dup.is_empty(), "重复 %s / 本次掷出 %d 格" % [str(dup), offer.size()])

	# ════════════════════════════════════════════
	#  ★★⑦ 老存档必须能抽到【后来新加的装备】(2026-08-10 补)
	# ════════════════════════════════════════════
	# 用户 2026-08-10 实机反馈「为啥我手机上没看到新装备」。
	# 根因: `ensure_equip_pool()` 原本是 `if not equip_pool.is_empty(): return` ——
	# 而池子是**存进存档的**。于是老存档里那份池子是"当时那张装备表的快照",
	# 之后新加的件**永远进不去** ⇒ 商店一辈子抽不到它们。
	# ★断言的是【补齐】而不是【重建】: 已有 id 的张数一个都不能动 ——
	#   动了等于把玩家已经买走/卖掉的记录抹掉(池子记的是"还剩几张")。
	print("── ⑦ 老存档补齐新装备 ──")
	var full_now: Dictionary = EquipPoolS.full_pool(DataRegistry.phase2_equipment)
	var some_id: String = ""
	for k in full_now:
		some_id = str(k)
		break
	# 造一份"只有一件、且那件已经被买走一张"的老存档池
	GameState.equip_pool = {some_id: int(full_now[some_id]) - 1}
	GameState.ensure_equip_pool()
	_ok("★分母: 当前装备表 %d 件上架" % full_now.size(), full_now.size() >= 90)
	_ok("⑦ ★★老存档的池子会把【后来新加的装备】补进去(否则商店永远抽不到)",
		GameState.equip_pool.size() == full_now.size(),
		"补齐后 %d 个 id / 应为 %d" % [GameState.equip_pool.size(), full_now.size()])
	_ok("⑦ ★已有 id 的剩余张数**一个都没被动**(动了等于抹掉玩家的买卖记录)",
		int(GameState.equip_pool[some_id]) == int(full_now[some_id]) - 1,
		"%s 剩 %d / 应剩 %d" % [some_id, int(GameState.equip_pool[some_id]), int(full_now[some_id]) - 1])

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装备私人池(批2)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _first_cost(eqs: Array, c: int) -> String:
	for e in eqs:
		if int((e as Dictionary).get("cost", 0)) == c and int((e as Dictionary).get("shopAvailable", 0)) == 1:
			return str((e as Dictionary).get("id", ""))
	return ""
