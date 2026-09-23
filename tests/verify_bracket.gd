extends Node
## verify_bracket.gd — 周日单败对阵图的纯函数层 (E-B1, 2026-09-23)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## 「谁打谁、谁轮空、打到第几轮」——**服务端推进赛程与客户端画对阵图用的是同一份答案**。
## 这三件事算错了不会报错，只会表现成「对阵图画歪了」或者更糟：
## 两个人被排进同一个坑、某个人凭空少打一轮、最高与次高种子第一轮就撞上。
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① **人数 1~40 全量扫**，不抽查 —— 缺口的形状就是"某个人数下算错了"。
##     每条都打印分母（扫了几个人数）。
## ★② 判据落在**结构性质**上，不落在"我算一遍再跟它比"：
##     · 每个人恰好占一个坑，没人重号、没人没坑（这条能一次抓住座次表写错）
##     · 每轮场数减半，末轮恰好 1 场
##     · 轮空只发生在第一轮，且**只发生在高种子那一侧**
##     拿我自己写的公式再算一遍 = 拿被测函数当尺子（今天已经栽过一次）。
## ★③ **最高与次高种子最晚相遇**：这条是单败座次的全部意义。
##     照顺序坐也能通过"每人一个坑"，但会让 1 号 2 号第一轮就打掉一个。
## ★④ **n = 2/3/4 单独验**：那不是边界情况，那是**当前唯一会发生的情况**
##     （测试者个位数 ⇒ 真跑起来就是 4 人桶）。
##
## 跑法: <godot> --headless --path . res://tests/verify_bracket.tscn --quit-after 600

const B := preload("res://scripts/gamedata/bracket.gd")

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
	print("=== 单败对阵图 (E-B1) ===")
	_t_bucket_split()
	_t_shape()
	_t_seats()
	_t_meet_late()
	_t_byes()
	_t_small()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 单败对阵图" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 切桶: 容量自适应 + 蛇形
# ─────────────────────────────────────────────────────────────
func _t_bucket_split() -> void:
	print("── ① 切桶 ──")
	## U3 逐字: >16 → 32 人桶; ≤16 → 16 人桶, 再少依次减半(8 / 4)
	_ok("① 17 人 → 32 人桶", B.bucket_size_for(17) == 32, "%d" % B.bucket_size_for(17))
	_ok("① 16 人 → 16 人桶", B.bucket_size_for(16) == 16, "%d" % B.bucket_size_for(16))
	_ok("① 9 人 → 16 人桶", B.bucket_size_for(9) == 16, "%d" % B.bucket_size_for(9))
	_ok("① 8 人 → 8 人桶", B.bucket_size_for(8) == 8, "%d" % B.bucket_size_for(8))
	_ok("① 5 人 → 8 人桶", B.bucket_size_for(5) == 8, "%d" % B.bucket_size_for(5))
	_ok("① 4 人 → 4 人桶", B.bucket_size_for(4) == 4, "%d" % B.bucket_size_for(4))
	_ok("① ★3 人不再减半(1 人桶不是比赛)", B.bucket_size_for(3) == 3, "%d" % B.bucket_size_for(3))
	_ok("① ★2 人同理", B.bucket_size_for(2) == 2, "%d" % B.bucket_size_for(2))

	## ★蛇形: 每个桶的人数差不超过 1(均匀), 且每个种子恰好进一个桶
	var uneven := 0
	var scanned := 0
	for players in range(2, 41):
		scanned += 1
		var nb := B.bucket_count(players)
		if nb <= 1:
			continue
		var cnt := {}
		for i in range(players):
			var bk := B.bucket_of_seed(i, nb)
			cnt[bk] = int(cnt.get(bk, 0)) + 1
		var lo := 999
		var hi := -1
		for k in range(nb):
			var c: int = int(cnt.get(k, 0))
			lo = mini(lo, c)
			hi = maxi(hi, c)
		if hi - lo > 1:
			uneven += 1
			print("       ★不均: %d 人 %d 桶 → 最多 %d 最少 %d" % [players, nb, hi, lo])
	_ok("① ★分母: 扫了 %d 个人数" % scanned, scanned == 39, "%d" % scanned)
	_ok("① 各桶人数差 ≤ 1", uneven == 0, "不均的有 %d 个人数" % uneven)

	## ★★上面那条**守不住蛇形** —— 顺序轮转切(`seed_idx % nb`)的人数同样均匀。
	##   实测: 把蛇形改成轮转, 上面那条照样绿(反向验证 B4 第一版没红)。
	##   蛇形要的是**强度均匀**(种子号之和), 不是人数均匀 ⇒ 判据得问这个。
	##   期望序列**写死**, 不拿公式再算一遍。
	var snake2: Array = []
	for i in range(8):
		snake2.append(B.bucket_of_seed(i, 2))
	_ok("① ★★8 个种子切 2 桶 = 蛇形 [0,1,1,0,0,1,1,0](轮转切会是 [0,1,0,1,...])",
		snake2 == [0, 1, 1, 0, 0, 1, 1, 0], str(snake2))
	var s0 := 0
	var s1 := 0
	for i in range(8):
		if int(snake2[i]) == 0:
			s0 += i
		else:
			s1 += i
	_ok("① ★★两桶的【种子号之和】相等(14 vs 14) —— 这才是蛇形的意义",
		s0 == s1, "%d vs %d" % [s0, s1])

	var snake3: Array = []
	for i in range(9):
		snake3.append(B.bucket_of_seed(i, 3))
	_ok("① ★9 个种子切 3 桶 = [0,1,2,2,1,0,0,1,2]",
		snake3 == [0, 1, 2, 2, 1, 0, 0, 1, 2], str(snake3))
	var sums := [0, 0, 0]
	for i in range(9):
		sums[int(snake3[i])] = int(sums[int(snake3[i])]) + i
	_ok("① ★3 桶的种子号之和差 ≤ 2(轮转切会差到 6)",
		int(sums.max()) - int(sums.min()) <= 2, str(sums))


# ─────────────────────────────────────────────────────────────
# ② 形状: 轮数 / 每轮场数 / 末轮一场
# ─────────────────────────────────────────────────────────────
func _t_shape() -> void:
	print("── ② 对阵表形状 ──")
	_ok("② 4 人 → 2 轮", B.rounds_for(4) == 2, "%d" % B.rounds_for(4))
	_ok("② 5 人 → 3 轮(补到 8)", B.rounds_for(5) == 3, "%d" % B.rounds_for(5))
	_ok("② 32 人 → 5 轮", B.rounds_for(32) == 5, "%d" % B.rounds_for(32))

	var bad_halve := 0
	var bad_final := 0
	var bad_total := 0
	var scanned := 0
	for n in range(2, 41):
		scanned += 1
		var total := B.rounds_for(n)
		## 每轮场数必须严格减半
		for r in range(1, total):
			if B.matches_in_round(n, r) != B.matches_in_round(n, r + 1) * 2:
				bad_halve += 1
		## 末轮恰好 1 场(决赛)
		if B.matches_in_round(n, total) != 1:
			bad_final += 1
		## 总场数 = 坑位数 - 1(单败: 每场淘汰一个人)
		var shape: Array = B.bracket_shape(n)
		if shape.size() != B.slots_for(n) - 1:
			bad_total += 1
			print("       ★总场数不对: %d 人 → %d 场, 应为 %d" % [n, shape.size(), B.slots_for(n) - 1])
	_ok("② ★分母: 扫了 %d 个人数" % scanned, scanned == 39, "%d" % scanned)
	_ok("② ★每轮场数严格减半", bad_halve == 0, "%d 处不对" % bad_halve)
	_ok("② ★末轮恰好 1 场(决赛)", bad_final == 0, "%d 处不对" % bad_final)
	_ok("② ★★总场数 = 坑位数 − 1(单败每场淘汰一人, 这条一次卡住整个形状)",
		bad_total == 0, "%d 处不对" % bad_total)


# ─────────────────────────────────────────────────────────────
# ③ 座次: 每人恰好一个坑, 不重号不缺号
# ─────────────────────────────────────────────────────────────
func _t_seats() -> void:
	print("── ③ 座次 ──")
	var bad := 0
	var scanned := 0
	for n in range(2, 41):
		scanned += 1
		var slots := B.slots_for(n)
		var seen := {}
		var dup := false
		for i in range(slots):
			var st := B.seat_of_seed(i, n)
			if st < 0 or st >= slots or seen.has(st):
				dup = true
				break
			seen[st] = true
		if dup or seen.size() != slots:
			bad += 1
			print("       ★座次有问题: %d 人(%d 坑) → 占了 %d 个坑" % [n, slots, seen.size()])
	_ok("③ ★分母: 扫了 %d 个人数" % scanned, scanned == 39, "%d" % scanned)
	_ok("③ ★★每个种子恰好占一个坑, 不重号不缺号(这条一次抓住座次表写错)",
		bad == 0, "%d 个人数出问题" % bad)


# ─────────────────────────────────────────────────────────────
# ④ ★最高与次高种子【最晚】相遇 —— 单败座次的全部意义
# ─────────────────────────────────────────────────────────────
func _round_they_meet(a_seed: int, b_seed: int, n: int) -> int:
	## 两个种子在第几轮相遇 = 他们的坑位第一次落进同一场对局的那一轮。
	var sa := B.seat_of_seed(a_seed, n)
	var sb := B.seat_of_seed(b_seed, n)
	var total := B.rounds_for(n)
	for r in range(1, total + 1):
		var blk: int = int(pow(2, r))
		if sa / blk == sb / blk:
			return r
	return -1


func _t_meet_late() -> void:
	print("── ④ 最高与次高种子最晚相遇 ──")
	var bad := 0
	var scanned := 0
	for n in [4, 8, 16, 32]:
		scanned += 1
		var total := B.rounds_for(n)
		var r12 := _round_they_meet(0, 1, n)
		if r12 != total:
			bad += 1
			print("       ★%d 人: 1 号与 2 号在第 %d 轮就撞上了(应为决赛第 %d 轮)" % [n, r12, total])
	_ok("④ ★分母: 扫了 %d 种桶容量" % scanned, scanned == 4)
	_ok("④ ★★1 号与 2 号种子在【决赛】才相遇", bad == 0, "%d 种出问题" % bad)

	## ★★对照: 该在半决赛碰的是 1 号与 **4** 号 ——
	##   标准单败里 3 号被排进 2 号那半区, 所以 **1v3 本来就是决赛才碰**。
	##   ⚠ 我第一版把这条写成「1v3 半决赛」, 门禁红了 —— 错的是**我的判据**不是代码
	##     (memory `fb-my-goal-can-be-wrong-not-just-my-code`: 方案书/判据里我定的目标也会是错的)。
	##   只验 1v2 不够: "把所有人堆在一侧"也能让 1v2 最晚相遇, 所以这条对照必须在。
	var bad3 := 0
	for n in [8, 16, 32]:
		var total := B.rounds_for(n)
		if _round_they_meet(0, 3, n) != total - 1:
			bad3 += 1
			print("       ★4 号在第 %d 轮碰 1 号(%d 人, 应为第 %d 轮半决赛)"
				% [_round_they_meet(0, 3, n), n, total - 1])
		if _round_they_meet(0, 2, n) != total:
			bad3 += 1
			print("       ★3 号在第 %d 轮碰 1 号(%d 人, 应为决赛第 %d 轮)"
				% [_round_they_meet(0, 2, n), n, total])
	_ok("④ ★★对照: 1v4 半决赛碰、1v3 决赛碰(标准单败就是这个形状)",
		bad3 == 0, "%d 处出问题" % bad3)


# ─────────────────────────────────────────────────────────────
# ⑤ 轮空: 只在第一轮, 且只给高种子
# ─────────────────────────────────────────────────────────────
func _t_byes() -> void:
	print("── ⑤ 轮空 ──")
	var bad_count := 0
	var bad_high := 0
	var scanned := 0
	for n in range(2, 41):
		scanned += 1
		var slots := B.slots_for(n)
		## 轮空人数 = 坑位数 − 实际人数
		var byes: Array = []
		for i in range(n):
			if B.has_first_round_bye(B.seat_of_seed(i, n), n):
				byes.append(i)
		if byes.size() != slots - n:
			bad_count += 1
			print("       ★%d 人(%d 坑): 轮空 %d 人, 应为 %d" % [n, slots, byes.size(), slots - n])
		## ★轮空的必须是**种子号最小的那几个**(高种子)
		for i in byes:
			if int(i) >= byes.size():
				bad_high += 1
				print("       ★%d 人: 种子 %d 轮空了, 但轮空名额只有 %d 个(该给最高的几个)"
					% [n, i, byes.size()])
				break
	_ok("⑤ ★分母: 扫了 %d 个人数" % scanned, scanned == 39, "%d" % scanned)
	_ok("⑤ ★轮空人数 = 坑位数 − 实际人数", bad_count == 0, "%d 个人数不对" % bad_count)
	_ok("⑤ ★★轮空只给【高种子】(原稿: 人数不整则高种子轮空)",
		bad_high == 0, "%d 个人数不对" % bad_high)

	## ★分母: 人数正好是 2 的幂时**一个轮空都没有** —— 否则"永远轮空"也能过上面两条
	var none_when_power := true
	for n in [4, 8, 16, 32]:
		for i in range(n):
			if B.has_first_round_bye(B.seat_of_seed(i, n), n):
				none_when_power = false
	_ok("⑤ ★★分母: 人数正好 4/8/16/32 时一个轮空都没有(证明上面不是恒真)",
		none_when_power)


# ─────────────────────────────────────────────────────────────
# ⑥ ★n = 2/3/4: 这不是边界, 这是当前唯一会发生的情况
# ─────────────────────────────────────────────────────────────
func _t_small() -> void:
	print("── ⑥ 小规模(当前真实人数) ──")
	## 4 人: 2 轮 3 场, 没有轮空
	var s4: Array = B.bracket_shape(4)
	_ok("⑥ 4 人 → 2 轮 3 场", B.rounds_for(4) == 2 and s4.size() == 3,
		"%d 轮 %d 场" % [B.rounds_for(4), s4.size()])
	_ok("⑥ 4 人: 一个轮空都没有",
		not B.has_first_round_bye(B.seat_of_seed(0, 4), 4))

	## 3 人: 补到 4 坑, 2 轮, 最高种子轮空
	_ok("⑥ 3 人 → 补到 4 个坑", B.slots_for(3) == 4, "%d" % B.slots_for(3))
	_ok("⑥ 3 人 → 2 轮", B.rounds_for(3) == 2, "%d" % B.rounds_for(3))
	_ok("⑥ ★3 人: 1 号种子轮空", B.has_first_round_bye(B.seat_of_seed(0, 3), 3))
	_ok("⑥ ★3 人: 2 号与 3 号要打第一轮(不轮空)",
		not B.has_first_round_bye(B.seat_of_seed(1, 3), 3)
		and not B.has_first_round_bye(B.seat_of_seed(2, 3), 3))

	## 2 人: 1 轮 1 场, 就是决赛
	_ok("⑥ 2 人 → 1 轮 1 场(直接决赛)",
		B.rounds_for(2) == 1 and B.bracket_shape(2).size() == 1)

	## 1 人 / 0 人: 不崩, 且不造出"没有对手的冠军"
	_ok("⑥ 1 人 → 0 轮(一个人不是比赛)", B.rounds_for(1) == 0, "%d" % B.rounds_for(1))
	_ok("⑥ 0 人 → 0 轮 0 场且不崩",
		B.rounds_for(0) == 0 and B.bracket_shape(0).is_empty())

	## 晋级走向
	_ok("⑥ 第 1 轮第 0/1 场的赢家都进下一轮第 0 场",
		B.winner_goes_to(0) == 0 and B.winner_goes_to(1) == 0)
	_ok("⑥ 第 2/3 场的赢家进下一轮第 1 场",
		B.winner_goes_to(2) == 1 and B.winner_goes_to(3) == 1)
