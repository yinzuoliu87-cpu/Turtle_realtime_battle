class_name PetXp
extends RefCounted
## 龟经验的显示口径(2026-11-09 · 方案书 docs/plans/20261107b-龟等级与经验.md §4.5)。纯函数, 门禁直接调。
## 数值全部来自 TurtleLevel(升级曲线 / 胜负经验 / 满级封顶), 这里不另抄一份。
## 用的人: 选龟卡片的经验条(pet_grid)、图鉴 Lv 签里的经验条(detail_views)、结算页「上场三只龟的经验」(settle_screen)。


## 累计经验 → {lv, cur, need, frac, maxed}: cur = 这一级里已攒的, need = 这一级升下一级一共要的, frac = cur / need。
##   满级(10 级, 累计 1350)⇒ maxed = true、frac = 1。负数 / 超过封顶一律夹进 0 ~ 封顶。
static func progress(xp: int) -> Dictionary:
	var x := clampi(xp, 0, TurtleLevel.xp_cap())
	var lv := TurtleLevel.level_for_xp(x)
	if lv >= TurtleLevel.MAX:
		return {"lv": lv, "cur": 0, "need": 0, "frac": 1.0, "maxed": true}
	var base := TurtleLevel.xp_to_reach(lv)
	var need := TurtleLevel.xp_to_reach(lv + 1) - base
	return {"lv": lv, "cur": x - base, "need": need, "frac": float(x - base) / float(need), "maxed": false}


## 这一局这只龟拿多少经验: 拥有的(不是限免)才给, 赢 WIN_XP 输 LOSE_XP; 离满级不够一整份时只给到封顶(满级后不再累计)。
static func gain(xp_before: int, won: bool, owned: bool) -> int:
	if not owned:
		return 0
	var room := maxi(0, TurtleLevel.xp_cap() - maxi(0, xp_before))
	return mini(TurtleLevel.WIN_XP if won else TurtleLevel.LOSE_XP, room)


## 本机缓存里这只龟的累计经验(PetLevelsNet.levels 只有服务器有记录的龟; 没有 ⇒ 0)。
static func cached_xp(pid: String) -> int:
	var e = PetLevelsNet.levels.get(pid, null)
	if not (e is Dictionary):
		return 0
	var x = (e as Dictionary).get("xp", 0)
	return maxi(0, int(x) if (x is int or x is float) else 0)


## 这只龟要不要挂经验条: 拉到了拥有表、要按拥有过滤(有账号且不在教学里)、而且是拥有的。限免 / 没拉到 ⇒ 不挂。
static func shows_bar(pid: String) -> bool:
	return PetLevelsNet.fetched and PetLevelsNet.filter_on() and PetLevelsNet.owned.has(pid)
