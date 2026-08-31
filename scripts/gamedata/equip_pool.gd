extends RefCounted
## EquipPool — 装备「私人池」（方案书 docs/plans/20260802-装备扩充.md §4.6 · D6/D20~D23）。
##
## 在此之前商店是**无限张有放回**（`phase2_equip.roll_shop` 每次从全表随机取），
## 想要几件同款就有几件 —— 3★ 只受钱和运气限制，不受"这件还剩几张"限制。
## 私人池给每一件装备一个**有限张数**：买走扣张、卖出退张、赛季重置补满。
##
## ★口径（最容易被下一个人读错的一处）：
##   **张数是「每一件装备」在池子里的数量，不是「有几种」。**
##   例：5 费有 13 种，每一种 10 张 ⇒ 5 费池总容量 = 130 张。
##
## ★为什么是这几个数（`DEPTH`）：照云顶之弈 Set 16/17 的每件张数 **+1**（用户 D13）。
##   云顶是 **8 人共享**一份池，本作是**私人池**（1v1 打的是快照，对手不实时抽卡，没有竞争者）
##   ⇒ 实际比云顶宽松约 8.3 倍，**1~3 费近似无限，紧张感只在 4/5 费才真正体现**。
##   若日后想让中低费也有"抢不到"的感觉，**调法是把整体张数除以 2~3**，
##   **不是**改 `SHOP_COST_ODDS`（那张表是照云顶 shop odds 抄的，改了就没有参照系了）。
##
## ★一条硬约束（纯算术）：张数必须 ≥ 9，否则该件的 3★ 在数学上不可能
##   （3 件 1★ → 1 件 2★，3 件 2★ → 1 件 3★ ⇒ 一件 3★ = 9 张）。
##   5 费的 10 张是**贴着下限**设的 —— 合出一件 5 费 3★ 之后，那件只剩 1 张，
##   这正是用户点名要的"极难但可能"。
##
## 四个实现问题的拍板（D20~D23，理由见方案书 §4.6.6）：
##   D20 糖果罐 / 财神 / 宝箱发的装备**不占池**（它们本来就绕开商店）
##   D21 某件合到 3★ 后，池里**剩下的张不再流通**
##       ★★实现上**没有**单独的"冻结"状态，理由见文件末尾那段 —— D21 与 D22 字面冲突，
##       用「库存驱动」解掉了，而且解法比存一个冻结标记更简单也更不容易错
##   D22 卖出**按份数退**：1★ 退 1 张 / 2★ 退 3 张 / 3★ 退 9 张
##       ⇒ 守恒律：买 9 张合出 3★ 再卖掉，池子必须**恰好**回到原样
##   D23 货架上还没买的**不算已扣**（成交才扣）。⇒ 池只在「买 / 卖 / 满星冻结 / 赛季重置」
##       四个时刻变，**与货架无关** —— 这让存档不必和 `meta_shop_offer` 成对回滚。
##       代价是同一次刷新可能掷出两个一样的格子 ⇒ `roll_shop` 里做**本轮去重**（不碰池状态）。

class_name EquipPool

## 费用 → 每件张数（云顶值 +1）。★改这张表 = 改整个赛季的抽卡手感，动之前先读上面那段。
## 【不受张数限制】的件(用户 2026-08-31 小木斧:「这个装备不会进行升星, 在卡池没有数量限制」)。
## ★为什么需要这张名单: 商店出货有两层 —— `phase2_equip.roll_shop` 那层确实是无限有放回,
##   但 ShopScene 先用 `available()` 按**私人池剩余张数**过滤过一遍。
##   我在方案书里一度写成"无数量限制现在就成立", 那是只看了第一层就下的结论, 错的。
## ★口径: 无限件**不扣张、不退张、永远可掷货**, 也不占 `available()` 的名额判断。
const UNLIMITED := {"p2eq_096": true}
## 【不参与三合一升星】的件(同一条被动的另一半: 用户「这个装备不会进行升星」)。
## ★与 UNLIMITED 放在一起是刻意的 —— 它俩是同一句需求拆出来的两半, 分开放必然漏一半。
##   消费者: GameState.try_merge_all(真合成) + ShopScene._purchase_merge_star(卡上的预告)。
const NO_STAR := {"p2eq_096": true}
## 无限件在 `left()` 里回报的张数 —— 只要远大于任何一次购买量即可, 不参与守恒律。
const UNLIMITED_LEFT := 999999

const DEPTH := {1: 31, 2: 26, 3: 19, 4: 11, 5: 10}
const DEPTH_FALLBACK := 19          # 费用字段异常时的兜底（按 3 费）

## 一件 N★ 占用的张数。★与 `phase2_equip.MERGE_COUNT = 3` 是同一套语义，不是新定义：
##   1★=1 / 2★=3（3 件 1★ 合成） / 3★=9（3 件 2★ = 9 件 1★）。
static func shares_of(star: int) -> int:
	match clampi(star, 1, 3):
		2: return 3
		3: return 9
		_: return 1


## 满池：{装备id: 张数}。只收 `shopAvailable == 1` 的件 —— 不上商店的件没有"池"这个概念。
static func full_pool(equipment: Array) -> Dictionary:
	var out: Dictionary = {}
	for e in equipment:
		if not (e is Dictionary):
			continue
		if int((e as Dictionary).get("shopAvailable", 0)) != 1:
			continue
		var eid: String = str((e as Dictionary).get("id", ""))
		if eid == "":
			continue
		out[eid] = int(DEPTH.get(int((e as Dictionary).get("cost", 3)), DEPTH_FALLBACK))
	return out


## 还剩几张。池里没有这个键 = 该件不参与池（不上商店），返回 0。
static func left(pool: Dictionary, eid: String) -> int:
	if UNLIMITED.has(eid):
		return UNLIMITED_LEFT
	return int(pool.get(eid, 0))


## 买走 n 张。返回是否真的扣到了（张数不够就不扣，整笔失败）。
static func take(pool: Dictionary, eid: String, n: int = 1) -> bool:
	if UNLIMITED.has(eid):
		return n > 0          # 无限件: 买得到, 但不扣张
	if n <= 0 or not pool.has(eid):
		return false
	if int(pool[eid]) < n:
		return false
	pool[eid] = int(pool[eid]) - n
	return true


## 卖出退回 n 张。★不设上限钳制 —— 退多了说明调用侧算错了份数，
## 与其静默吃掉（池子凭空少张、玩家永远发现不了），不如让门禁的守恒律断言当场红。
static func give_back(pool: Dictionary, eid: String, n: int) -> void:
	if UNLIMITED.has(eid):
		return                # 无限件: 卖了也不退张(它本来就没扣过)
	if n <= 0 or not pool.has(eid):
		return
	pool[eid] = int(pool[eid]) + n


## 可掷货的件（张数 > 0）。抽空（0）不出。
static func available(pool: Dictionary, equipment: Array) -> Array:
	var out: Array = []
	for e in equipment:
		if not (e is Dictionary):
			continue
		if left(pool, str((e as Dictionary).get("id", ""))) > 0:
			out.append(e)
	return out


# ══════════════════════════════════════════════════════════════════════
#  ★D21 与 D22 字面冲突，怎么解的（2026-08-03 实现时发现，写在这里免得被"修回去"）
# ══════════════════════════════════════════════════════════════════════
#  D21：某件合到 3★ → 池里剩下的张【冻结，不再流通】
#  D22：卖出按份数退 ⇒ 守恒律「买 9 张合出 3★ 再卖掉，池子恰好回到原样」
#
#  第一版实现按字面写：freeze 把张数置成 -1。结果是 ——
#    买9张(31→22) → 合3★(冻结 → -1) → 卖掉3★(已冻结, 退不回来) ⇒ 池子【永久少 31 张】。
#  两条决定同时成立是不可能的：只要"冻结"是写在池子上的一个状态，卖出就解不开它。
#
#  ★解法：**根本不需要冻结状态。**
#  「满 3★ 的件不出现在商店」这件事**早就实现了** —— `ShopScene._maxed_item_ids()`
#  扫背包 + 统领身上 + 小将身上，把 star>=3 的 id 全部排除出掷货池。
#  它是**库存驱动**的：你手里有 3★ 就排除，卖掉之后自动不再排除。
#  ⇒ D21 想要的行为（满星件别再占货架、别稀释别的件）**已经达成**，
#    而且因为它读的是库存而不是一个独立状态，**天然与 D22 的守恒律不冲突**。
#
#  ⇒ 池子只管一件事：**这件还剩几张**。谁该不该出现在货架，由库存那条既有规则管。
#  这也少了一份要跟存档同步的状态 —— 多一份状态就多一处会漂
#  （memory [[fb-write-without-reader-and-fake-gates]]：生产侧写了、消费侧没读，一天踩过三次）。
