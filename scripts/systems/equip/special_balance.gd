class_name SpecialBalance
extends RefCounted

## special_balance.gd — 【特殊余额】统一基建（2026-08-05）
##
## ★★★为什么必须有这一层：
##   2026-08-05 用户逐件重做装备时，**一口气出现了五件都需要"独立于 u["shield"] 的第二条余额"**：
##     · 064 溺者的浮囊【幽灵护盾】 20 秒线性衰减，**耗尽也算被打破** ⇒ 必定爆炸(4 秒诅咒)
##     · 068 深海气压罐【法力护盾】 8 秒衰减，**存在时锁充能条**
##     · 070 压舱咸鱼砖【灰色血条】 不衰减，**每秒把 5% 转回生命**
##     · 071 炼乳罐    【奶油护盾】 **永久不衰减**，破了炸 300 码 + 给持有者永久 buff
##     · 072 铁皮蛋糕盒【终极护盾】 永久，**破了解除变身**
##
##   它们的共同需求是【**独立余额 + 各自的衰减曲线 + 破盾/耗尽回调**】。
##   而普通的 `u["shield"]` 归零时**不通知任何人** —— 这个回调在项目里根本不存在。
##
##   ⇒ 不抽这一层，就会写出五套互相不认识的护盾（各自记余额、各自在伤害路径里插一脚、
##     各自实现衰减），而且**每一套都要在两条伤害路径上各改一次**（CLAUDE.md §3.3）。
##     那正是本项目反复栽跟头的形状（"手抄的副本必然落后"）。
##
## ★吸收顺序：**普通 shield 恒定先扛**，然后按 `order` 从小到大依次扛特殊余额。
##   理由：普通盾是限时/易得的，特殊余额是装备的核心资源，后者更该留到最后。
##
## ★与 `_grant_shield` 的区别：那个走 `u["shield"]`，有 `shield_amp` 加成、有圣光转化、
##   会被"护盾增幅"影响。**特殊余额不吃这些** —— 它们是装备直接指定的数值。

const EPS := 0.001

var battle                       ## 注入: 主战斗场景
var _bal: Dictionary = {}        ## uid(String) → { key(String) → 条目 }

## 条目结构（不用类，省一层间接）:
##   { "u": 单位字典, "val": 当前余额, "max": 初始峰值(算线性衰减用),
##     "decay": 衰减总秒数(0=永不), "t0": 起算时刻, "on_break": Callable, "order": int }


func _init(b) -> void:
	battle = b


## ★单位的稳定标识。**绝不能拿单位字典当 Dictionary 的键**（CLAUDE.md §3.2：
##   Godot 会递归哈希整个字典，而单位字典互相引用成环 → 无限递归 → 卡死）。
func _uid(u: Dictionary) -> String:
	if not u.has("_spec_uid"):
		u["_spec_uid"] = "sb%d" % _next_uid
		_next_uid += 1
	return str(u["_spec_uid"])

var _next_uid: int = 1


## 给 u 挂一条特殊余额。同一个 key 再给一次 = **叠加到现有余额上**（并刷新衰减起点与峰值）。
## opts: { decay_sec: float=0, on_break: Callable, order: int=0 }
func grant(u: Dictionary, key: String, amount: float, opts: Dictionary = {}) -> void:
	if amount <= 0.0 or not u.get("alive", false):
		return
	var uid: String = _uid(u)
	if not _bal.has(uid):
		_bal[uid] = {}
	var slot: Dictionary = _bal[uid]
	var cur: float = float(slot[key]["val"]) if slot.has(key) else 0.0
	var nv: float = cur + amount
	slot[key] = {
		"u": u,
		"val": nv,
		"max": nv,                                     # 峰值重置 ⇒ 线性衰减从新的总量开始算
		"decay": float(opts.get("decay_sec", 0.0)),
		"t0": battle._t,
		"on_break": opts.get("on_break", Callable()),
		"order": int(opts.get("order", 0)),
	}


func val(u: Dictionary, key: String) -> float:
	var uid: String = str(u.get("_spec_uid", ""))
	if uid == "" or not _bal.has(uid):
		return 0.0
	var slot: Dictionary = _bal[uid]
	return float(slot[key]["val"]) if slot.has(key) else 0.0


func has(u: Dictionary, key: String) -> bool:
	return val(u, key) > EPS


## 手动清掉（触发 on_break，reason="clear"）
func clear(u: Dictionary, key: String) -> void:
	var uid: String = str(u.get("_spec_uid", ""))
	if uid == "" or not _bal.has(uid):
		return
	var slot: Dictionary = _bal[uid]
	if not slot.has(key):
		return
	var e: Dictionary = slot[key]
	slot.erase(key)
	_fire(e, u, key, "clear")


## 【伤害路径调用】普通盾吸收之后、扣血之前。返回穿透后剩余伤害。
## ⚠ 两条伤害路径(_apply_damage / _apply_damage_from)都要调 —— CLAUDE.md §3.3。
func absorb(u: Dictionary, d: float) -> float:
	if d <= 0.0:
		return d
	var uid: String = str(u.get("_spec_uid", ""))
	if uid == "" or not _bal.has(uid):
		return d
	var slot: Dictionary = _bal[uid]
	if slot.is_empty():
		return d
	# 按 order 升序扛（数字小的先扛）；同 order 按 key 排序，保证**确定性**
	var keys: Array = slot.keys()
	keys.sort_custom(func(a, b):
		var oa: int = int(slot[a]["order"])
		var ob: int = int(slot[b]["order"])
		return oa < ob if oa != ob else str(a) < str(b))
	for k in keys:
		if d <= 0.0:
			break
		var e: Dictionary = slot[k]
		var cur: float = float(e["val"])
		if cur <= EPS:
			continue
		var ab: float = minf(cur, d)
		e["val"] = cur - ab
		d -= ab
		if float(e["val"]) <= EPS:
			slot.erase(k)
			_fire(e, u, str(k), "damage")
	return d


## 【每帧】线性衰减 + 耗尽判定。
## ★衰减是**按初始峰值线性**的（用户对 064 明确要求"线性"），不是按当前值指数。
func tick(delta: float) -> void:
	if _bal.is_empty():
		return
	for uid in _bal.keys():
		var slot: Dictionary = _bal[uid]
		for k in slot.keys():
			var e: Dictionary = slot[k]
			var u = e["u"]
			# 携带者死了 → 余额一并清掉（不触发 on_break 的 damage 分支，用 clear）
			if not (u is Dictionary) or not u.get("alive", false):
				slot.erase(k)
				continue
			var dec: float = float(e["decay"])
			if dec <= 0.0:
				continue                                   # 永不衰减
			var rate: float = float(e["max"]) / dec         # 每秒掉多少（线性）
			e["val"] = float(e["val"]) - rate * delta
			if float(e["val"]) <= EPS:
				slot.erase(k)
				_fire(e, u, str(k), "decay")               # ★自然衰减完也算"被打破"
		if slot.is_empty():
			_bal.erase(uid)


## 换路 / 清场
func clear_all() -> void:
	_bal.clear()


func _fire(e: Dictionary, u: Dictionary, key: String, reason: String) -> void:
	var cb = e.get("on_break", null)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(u, key, reason)
