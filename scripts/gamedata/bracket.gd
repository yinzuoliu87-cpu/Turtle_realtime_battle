extends RefCounted
## bracket.gd — 单败对阵图的纯函数层（E-B1, 2026-09-23）
##
## ══════════════════════════════════════════════════════════════════════
##  这一层为什么存在
## ══════════════════════════════════════════════════════════════════════
## 周日决赛日的「谁打谁、谁轮空、打到第几轮」这三个答案，
## **服务端（`pg_cron` 推进赛程）与客户端（桶地图画对阵）必须完全一致**。
## 两边各写一套必然漂 —— 周六闯关赛那次「同一判据五份副本」就是这么来的
## （memory `fb-hand-rolled-copies-drift`）。
##
## ⇒ 规则只在这里写一遍。客户端直接调；服务端那份 SQL 由
##   `tools/gen_bracket_sql.py` 从**本文件的判据**生成，不手抄。
##
## ══════════════════════════════════════════════════════════════════════
##  口径（都来自用户原稿 §四 与母方案书 U3）
## ══════════════════════════════════════════════════════════════════════
## · 桶容量**随人数自适应**：>16 人 → 32 人桶；≤16 → 16 人桶，再少依次减半（8 / 4）。
## · **人数不整 → 高种子轮空**（原稿：「人数不整则高种子轮空」）。
## · 切桶用**蛇形**（原稿：「按种子蛇形切成 32 人单败桶」）—— 让每个桶的强度尽量均匀。
## · 单败：输一场就出局；赢到最后是桶冠军。
##
## ★★**现在真跑起来大概率是 4 人桶**（测试者个位数）。所有函数必须在 n=2/3/4 时
##   也给出干净的答案 —— 那不是边界情况，那是**当前唯一会发生的情况**。

## 桶容量档位：从大到小。★不写死 32 —— U3 的规则是"依次减半"，
##   而"减到哪一档"取决于人数，写死任何一档都会在小规模时崩。
const BUCKET_SIZES := [32, 16, 8, 4]
const MIN_BUCKET := 4          # 再少就不分桶了（2~3 人直接一个桶，见 bucket_size_for）


## 这么多人，一个桶装多少？
## ★>16 → 32；≤16 → 16；依次减半到 4（U3 已定）。
## ⚠ 人数比 4 还少时**不再减半**，直接返回人数本身 —— 2 个人分成两个"1 人桶"
##   会造出一个没有对手的冠军，那不是比赛。
static func bucket_size_for(players: int) -> int:
	if players <= 0:
		return 0
	if players < MIN_BUCKET:
		return players          # 2~3 人: 一个桶装下所有人
	for sz in BUCKET_SIZES:
		if players > sz / 2:
			return sz
	return MIN_BUCKET


## 要分几个桶。★向上取整 —— 剩下的人不能没地方去。
static func bucket_count(players: int) -> int:
	var sz := bucket_size_for(players)
	if sz <= 0:
		return 0
	return int(ceil(float(players) / float(sz)))


## 蛇形切桶：第 i 号种子（0 = 最高种子）进哪个桶。
## ★蛇形 = 1,2,3,4 / 4,3,2,1 / 1,2,3,4 …… 来回走。
##   目的是让每个桶的强度均匀 —— 顺序切（前 32 名全进 1 号桶）会造出一个死亡之桶。
static func bucket_of_seed(seed_idx: int, n_buckets: int) -> int:
	if n_buckets <= 1 or seed_idx < 0:
		return 0
	var row: int = seed_idx / n_buckets        # 第几趟
	var col: int = seed_idx % n_buckets        # 这一趟里的第几个
	return col if row % 2 == 0 else (n_buckets - 1 - col)


## 桶里有 n 个人 → 打几轮。★补到 2 的幂再取 log2：
##   5 个人 → 补到 8 → 3 轮（3 个人轮空第一轮）。
static func rounds_for(n: int) -> int:
	if n <= 1:
		return 0
	var slots := 1
	var r := 0
	while slots < n:
		slots *= 2
		r += 1
	return r


## 桶里有 n 个人时，对阵表有几个位置（补到 2 的幂）。
static func slots_for(n: int) -> int:
	if n <= 1:
		return maxi(0, n)
	var slots := 1
	while slots < n:
		slots *= 2
	return slots


## 第 r 轮（1 起）有几场对局。★末轮 = 1 场（决赛）。
static func matches_in_round(n: int, r: int) -> int:
	var total := rounds_for(n)
	if r < 1 or r > total:
		return 0
	return slots_for(n) / int(pow(2, r))


## 一个桶的全部对局位置：[{r=轮次, m=本轮第几场, a=位置A, b=位置B}]。
## ★位置(slot)是**对阵表里的坑位**，不是玩家 —— 谁坐哪个坑由 `seat_of_seed` 决定，
##   坑位空着就是轮空。两件事分开，形状才不会跟着人数抖。
static func bracket_shape(n: int) -> Array:
	var out: Array = []
	var total := rounds_for(n)
	for r in range(1, total + 1):
		var cnt := matches_in_round(n, r)
		for m in range(cnt):
			out.append({"r": r, "m": m, "a": m * 2, "b": m * 2 + 1})
	return out


## 标准单败座次：第 i 号种子（0 起）坐对阵表的哪个坑。
## ★★这条决定「1 号种子和 2 号种子会不会第一轮就碰上」——
##   标准做法是 1 对末位、2 对倒数第二…… 让最高与次高**尽可能晚**相遇。
##   照顺序坐（0 对 1、2 对 3）会让前两号种子第一轮就打掉一个，那是把赛制做废。
## 座次表：第 `pos` 个坑坐的是哪一号种子。
## 经典构造 = 逐轮镜像展开：seats = [0]；每轮 seats = 交错(seats, 镜像(seats))。
## 8 坑的结果是 `[0,7,3,4,1,6,2,5]` ⇒ 配对 (1-8)(4-5)(2-7)(3-6)，就是标准表。
static func _seat_table(slots: int) -> Array:
	var seats: Array = [0]
	var size := 1
	while size < slots:
		var nxt: Array = []
		for x in seats:
			nxt.append(x)
			nxt.append(size * 2 - 1 - int(x))
		seats = nxt
		size *= 2
	return seats


static func seat_of_seed(seed_idx: int, n: int) -> int:
	var slots := slots_for(n)
	if slots <= 1 or seed_idx < 0 or seed_idx >= slots:
		return -1
	return int(_seat_table(slots).find(seed_idx))


## 坐在这个坑的是哪一号种子。★`seat_of_seed` 的逆映射。
static func seed_at_seat(seat: int, n: int) -> int:
	var slots := slots_for(n)
	if slots <= 0 or seat < 0 or seat >= slots:
		return -1
	return int(_seat_table(slots)[seat])


## 这个坑位是空的吗？
## ★★判据是【坐在这个坑的种子号 ≥ 实际人数】，**不是「坑位号 ≥ 人数」** ——
##   坑位根本不是按种子号排的（8 坑的顺序是 0,7,3,4,1,6,2,5）。
##   我第一版写成了 `slot >= n`，**门禁当场把它拓出来**：5 人时只算出 1 个轮空，
##   实际该有 3 个（坑位数 8 − 人数 5），而且轮空的人也挑错了。
static func is_bye_slot(slot: int, n: int) -> bool:
	var sd := seed_at_seat(slot, n)
	return sd < 0 or sd >= n


## 第一轮里，坐在坑位 `slot` 的人是不是**直接轮空进第二轮**（对手那个坑是空的）。
## ★原稿:「人数不整则**高种子轮空**」—— 标准座次天然满足这一条:
##   空位都排在坑位号大的一侧, 而高种子坐的是与之配对的那一侧。
static func has_first_round_bye(slot: int, n: int) -> bool:
	if is_bye_slot(slot, n):
		return false                      # 自己就是空位, 谈不上轮空
	var foe := slot + 1 if slot % 2 == 0 else slot - 1
	return is_bye_slot(foe, n)


## 赢家从第 r 轮的第 m 场，晋级到下一轮的第几场。
static func winner_goes_to(m: int) -> int:
	return m / 2
