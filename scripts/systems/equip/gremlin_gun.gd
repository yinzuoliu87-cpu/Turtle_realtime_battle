class_name GremlinGun
extends RefCounted
## 古灵精怪枪 —— 送给敌人的「毒苹果」(用户 2026-08-31)
##
## ★需求原文:
##   「技能或装备，会扔给目标一把古灵精怪枪。
##     古灵精怪枪：提供1攻击力，1生命值，1攻击速度。
##     携带者每次普攻会使自己受到1%最大生命值真实伤害。」
##
## ★为什么它不是一件真装备(方案书「出入」第 2 条):
##   本作装备是**局外背包**的东西, 战斗中没有"给某个单位临时挂一件装备"的通路。
##   所以它实现成**战斗内的一个标记 + 属性增量**, 名字仍叫古灵精怪枪。
##
## ★「1攻击速度」= **+1%**(未决点 ①, 用户 2026-08-31「是1%」)。
##   按字面 +1 的话是"每秒多打一次" —— 本作 aspd 的单位就是每秒攻击次数
##   (058 炮台的 TURRET_ASPD 才 0.5/秒), 那会把这把毒苹果做成大礼包。
##
## ★自伤是**真实伤害**且**能打死携带者**(未决点 ⑤, 用户「能打死」)。
##   真实伤害不吃任何减免 —— 这正是它作为负面道具的全部意义。

## 一把枪给的三项(需求字面值)。★只存这一份, 门禁拿它当分母。
const ATK_PER_GUN := 1.0
const HP_PER_GUN := 1.0
const ASPD_PCT_PER_GUN := 0.01          # +1%(不是 +1 次/秒)
## 携带者每次普攻的自伤 = 自己最大生命 × 这个比例, 真实伤害
const SELF_TRUE_PCT := 0.01

var battle = null


func _init(b) -> void:
	battle = b


## 给 `u` 塞一把枪。可叠加 —— 两个 FPGA 携带者都抽中同一个倒霉蛋时该给两把。
## 返回这个单位现在总共有几把(门禁拿它当分母, 免得"给了没给上"看不出来)。
func give(u: Dictionary) -> int:
	if not (u is Dictionary) or not u.get("alive", false):
		return 0
	var n: int = int(u.get("gremlin_guns", 0)) + 1
	u["gremlin_guns"] = n
	## ★属性直接加在单位上 —— 它不在 `u["equips"]` 里, 走不了 `_eq_apply_all_stats`。
	##   `aspd_perm` 是攻速的永久乘区(战斗侧 atk_cd 除以它), 与 `_aspdPct` 同一个通道。
	u["atk"] = float(u.get("atk", 0.0)) + ATK_PER_GUN
	u["maxHp"] = float(u.get("maxHp", 0.0)) + HP_PER_GUN
	u["hp"] = float(u.get("hp", 0.0)) + HP_PER_GUN
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + ASPD_PCT_PER_GUN
	## ★★读数要有出口: 镜像一份到 `eq_state`, 头像下的装备格就能显
	##   【枪图标 + 右下角枚数】—— 走的是既有的 `EquipReadouts.COUNT` 通道,
	##   不自造头顶条(memory: 读数一律进装备图标框)。
	if not (u.get("eq_state", null) is Dictionary):
		u["eq_state"] = {}
	u["eq_state"]["gremlin_gun"] = {"n": n}
	if battle != null and battle.has_method("_refresh_panel_equips"):
		battle._refresh_panel_equips(u)
	return n


## 这个单位打出一次**普攻**之后要自伤多少(纯函数, 门禁直接调它验数)。
## 没枪 = 0。★按【当前最大生命】算, 不是登场时的快照 —— 中途涨血就该疼得更多。
func self_damage(u: Dictionary) -> float:
	var n: int = int(u.get("gremlin_guns", 0))
	if n <= 0:
		return 0.0
	return float(u.get("maxHp", 0.0)) * SELF_TRUE_PCT * float(n)


## 普攻命中钩子 —— 挂在 battle_damage 的 on-hit 那一排里(与弓箭处决/药水斩首同排)。
## ★只有 `basic` 才算。技能、装备造的段都不触发(与 002 辣椒 / 023 / 026 同口径)。
func on_hit(src: Dictionary, basic: bool) -> void:
	if not basic:
		return
	var d: float = self_damage(src)
	if d <= 0.0:
		return
	## ★`_apply_damage(u, dmg, ...)` 是**无来源**那条伤害路(DoT/真伤走它) ——
	##   自伤没有"攻击者", 走 `_apply_damage_from(自己, 自己, ...)` 会把自己算成
	##   攻击者去触发一堆 on-hit(反伤/吸血/法力), 那是错的。
	##   CLAUDE.md §3.3: 两条伤害路各自扣盾扣血, 选错一条就会出现只在某类伤害下的诡异行为。
	## ★`bucket="tru"` 才是真伤(battle_damage.gd:153「bucket=="tru" 视为真伤」);
	##   `is_self=true` 让它记在"自伤"账上而不是算成谁打的。
	##   ⚠ 我第一版把 `true` 传在第 4 位 —— 那一位是 `src`, 不是 bool。签名是
	##   `_apply_damage(u, dmg, col, src, bucket, is_self, ...)`。
	battle._damage._apply_damage(src, maxi(1, int(round(d))), Color("#a06cd5"), null, "tru", true)

## ★★2026-09-13 从 `equip_system.gd` 搬过来 —— 「把枪发出去」本来就是
## 这把枪自己的事, 放在装备系统的大文件里只是历史位置。
## (直接因: `equip_system.gd` 撑到 3001 行 > 架构预算 3000 —— 不再靠删注释凑行数,
##  上一次那么干在 CRLF/LF 混排下**吃掉了两行代码**。)
## FPGA板【登场】: 给**对方**随机 1/2/3 个敌人各一把古灵精怪枪(用户 2026-08-31 新增)。
## ★这是【新增】的一条效果, 原来那条"每 N 秒抽 2-bit 状态给自己上 buff"一条没动。
## ★挑人是**不重复**的 —— 需求说"1/2/3 个敌人", 同一个人塞两把不算两个敌人。
##   (敌人不够时有几个给几个; 返回真给出去的把数, 门禁拿它当分母。)
## ★用 `battle._battle_rng` 而不是裸 randi —— 确定性门禁(rng_discipline)守着这条。
func hand_out(u: Dictionary, si: int) -> int:
	var want: int = EquipSystem.FPGA_GUNS[si]
	var foes: Array = []
	var my_side: String = str(u.get("side", ""))
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) != my_side 				and not o.get("_isEgg", false):
			foes.append(o)
	if foes.is_empty():
		return 0
	var given: int = 0
	while given < want and not foes.is_empty():
		var k: int = battle._battle_rng.randi() % foes.size()
		give(foes[k])
		## ★★「**扔**给目标一把古灵精怪枪」—— 需求原话里的动作。
		##   之前这条路径**一个 vfx 调用都没有**: 属性静悄悄加上去, 玩家看不到发生过什么
		##   (2026-09-01 逐句核对原话时抓到, 第 2 句)。
		##   ★演出在结算【之后】—— give() 已经同步做完, 这条 tween 推不动也不影响数值。
		battle._vfx._throw_item(u, foes[k], "gremlin-gun.png", "古灵精怪枪", Color("#8ae06a"))
		foes.remove_at(k)          # ★不重复: 挑过就拿掉
		given += 1
	return given
