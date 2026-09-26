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

## ══════════════════════════════════════════════════════════════════════
## 「那个坑位上坐着谁」与「我走到了第几轮」—— 纯函数, 只吃 (n, done)
## ══════════════════════════════════════════════════════════════════════
## ★★★2026-09-26 这段递归**原来只住在 `BracketMapScene.competitor()` 里**。
##   搬下来是因为发头衔也要它, 而那是第二个消费者 ——
##   抄第二份就是「抄一次永远落后一次」(memory fb-hand-rolled-copies-drift)。
##   `BracketMapScene.competitor()` 现在**调这里**, 自己只负责把种子号换成名字。
##
## ★为什么服务端不算: 算得出就等于把对阵规则在 SQL 里写第二遍(E-B3 定死的)。
##   服务端只存 `done`(哪一场哪一侧赢), 谁打谁一律客户端推。


const OCC_TBD := -1     # 待定: 上一轮还没翻面
const OCC_BYE := -2     # 轮空: 这个坑位本来就没人


## 第 r 轮(1 起)第 m 场的 `side` 侧坐着几号种子。OCC_TBD / OCC_BYE 见上。
## ★轮空要单独有个值: 「待定」会等出人来, 「轮空」永远不会 —— 两者混成一个
##   的后果是有轮空的桶在第二轮显示「待定 vs 待定」(2026-09-25 修过一次)。
static func occupant_seed(r: int, m: int, side: int, n: int, done: Dictionary) -> int:
	if r <= 1:
		var seat: int = m * 2 + side
		var sd := seed_at_seat(seat, n)
		if sd < 0 or sd >= n:
			return OCC_BYE
		return sd
	var src_m: int = m * 2 + side
	var key := "%d-%d" % [r - 1, src_m]
	if done.has(key):
		return occupant_seed(r - 1, src_m, int(done[key]), n, done)
	## ★轮空自动晋级: 上一轮那一场有一侧是空位 ⇒ 另一侧不必等 `done` 里有记录。
	if r - 1 == 1:
		var a0 := occupant_seed(1, src_m, 0, n, done)
		var b0 := occupant_seed(1, src_m, 1, n, done)
		if (a0 == OCC_BYE) != (b0 == OCC_BYE):
			return b0 if a0 == OCC_BYE else a0
	return OCC_TBD


## 我在这一场的哪一侧(0 / 1); -1 = 我不在这一场。
static func my_side_in(me: int, r: int, m: int, n: int, done: Dictionary) -> int:
	if me < 0:
		return -1
	for side in [0, 1]:
		if occupant_seed(r, m, side, n, done) == me:
			return side
	return -1


## 「我这一周在决赛日走到哪儿了」—— 发冠军/四强头衔的**唯一依据**。
##
## 返回 `{"total": 共几轮, "deepest": 我被排进的最深那一轮(0 = 没进), "champion": 赢下决赛没有}`
##
## ★★`deepest` 取的是「**被排进**」不是「打过」—— 原稿「四强 = 打进四强」问的是名次,
##   而被排进倒数第二轮就已经是前 4 名了(那一轮正好 4 个人)。
## ★★`champion` **必须看 `done`**, 不能用「被排进决赛」——
##   周日现在是双方各自在本地打对方快照、两边都可能算出自己赢
##   (服务端 `on conflict do nothing` 先报的算), 所以**本地结果不是权威**。
##   `done["<总轮数>-0"]` 一个桶里只有一个值, 那才是权威。
static func my_progress(me: int, n: int, done: Dictionary) -> Dictionary:
	var total := rounds_for(n)
	var out := {"total": total, "deepest": 0, "champion": false}
	## ★`me < 0` 这一半是**防御性, 不承重**(2026-09-26 反向验证查实): 把它拿掉
	##   一条断言都不红 —— `my_side_in()` 自己第一行就挡 `me < 0`, 于是循环里
	##   一次都不会命中, `deepest` 照旧是 0。留着是把「纯观众没有名次」写在明面上。
	##   ⚠ 不要因为它在这儿就以为「纯观众」这件事有判据在守 —— 守它的是
	##   `verify_titles` ⑤a 那条「纯观众(me < 0) ⇒ 最深 0、不夺冠」, 它量的是**结果**,
	##   所以无论哪一层挡住的都算。(memory fb-mutation-not-reddening-can-mean-dead-code)
	## ★`n <= 1 or total <= 0` 这一半**是承重的**: 一人一桶时 `rounds_for` 没有意义。
	if me < 0 or n <= 1 or total <= 0:
		return out
	for r in range(1, total + 1):
		for m in range(matches_in_round(n, r)):
			if my_side_in(me, r, m, n, done) >= 0:
				out["deepest"] = r
	var fs := my_side_in(me, total, 0, n, done)
	if fs >= 0:
		var w = done.get("%d-0" % total, -1)
		out["champion"] = int(w) == fs
	return out


## 这一周该不该发「四强」。★2 人桶(只有决赛那一轮)**不发** —— 那一轮就是冠军赛。
static func semifinal_reached(deepest: int, total: int) -> bool:
	return total >= 2 and deepest >= total - 1

