class_name NoviceMenu
extends RefCounted
## 新手主菜单「逐个点亮」(方案书 docs/plans/20261020-教程重写.md §v4 第 3 步)。
##
## 用户 2026-10-21:「要教程: …→ 起名 → 主菜单（首次进入只亮「开始战斗」，其余按教程进度点亮——照皇室战争逐个开放的做法）」;
##   「不要教程: 起名 → 主菜单（照现在的解锁规则）」。
## 参考(实机, docs/plans/ref/20261021-新手引导实机/皇室战争ClashRoyale/):
##   01m37.5s_大厅_训练进度1of3.jpg —— 训练 1 打完第一次见大厅, 只有 Battle 一个大钮;
##   之后按场次逐个开放(宝箱 → 升级 → 起名 → 奖杯之路 → 模式 → 商店, 06m32.5s_游戏模式_未解锁.jpg「Unlocks at Arena 12」)。
##
## 只对 `GameState.novice_menu == true` 的号生效(导演在首启走完教程时置位); 跳过教程的号恒为 false。
## 按**累计**对战场次(`battles_total`, 跨大轮不清)点亮 —— 用本大轮场次会让老号每周一重新被锁。
## ★「开始战斗」本身被锁着(周末没资格 / 配额满 / 出局)时一律不加新手锁:
##   否则整屏没有一个能点的入口(memory fb-a-wall-must-let-the-unblocking-action-through)。

## 入口名 → 累计打满几场后点亮。与主菜单上的字一致(主菜单按这个名字问)。
const UNLOCK_AT := {
	"背包": 1,
	"商店": 1,
	"图鉴": 2,
	"排行榜": 2,
	"训龟大师": 2,
}


const _FT := preload("res://scripts/systems/onboarding/first_tips.gd")


## GameState 走首次提示那一份取法(同一个 onboarding 目录, 不再抄一份 —— dup_primitive_audit)。
static func _gs() -> Object:
	return _FT._gs()


## 新手锁开着吗(与具体入口无关)。battle_locked = 主菜单「开始战斗」此刻是否被它自己的门拦着。
static func active(battle_locked: bool) -> bool:
	var gs := _gs()
	if gs == null or battle_locked or not bool(gs.get("novice_menu")):
		return false
	return int(gs.get("battles_total")) < max_unlock()


static func max_unlock() -> int:
	var m := 0
	for v in UNLOCK_AT.values():
		m = maxi(m, int(v))
	return m


## 这个入口的新手锁原因(短句, 贴在入口底边); 空串 = 不锁。
static func lock_reason(entry: String, battle_locked: bool) -> String:
	if not active(battle_locked) or not UNLOCK_AT.has(entry):
		return ""
	var need := int(UNLOCK_AT[entry])
	if int(_gs().get("battles_total")) >= need:
		return ""
	return reason_text(need)


## 「首战后解锁」与商店既有的锁同一句(MainMenuScene._shop_lock_reason)。
static func reason_text(need: int) -> String:
	return "首战后解锁" if need <= 1 else "%d 场后解锁" % need
