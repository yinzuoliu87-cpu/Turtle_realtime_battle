class_name Buffs extends RefCounted

## Buffs — buff CRUD + 判定 (1:1 PoC buff 系统)
##
## buff dict shape: {type: String, value: int/float, duration: int, ...extras}
## duration 约定: = turns + 1 (push 时 caller 加 1; 回合末 tick_duration 先 -1, 留本回合)
##
## ⚠️ DoT (burn/poison/bleed/curse) 不走这里 — 走 Dot.apply_stacks (层数模型独立)
## ⚠️ shield buff 是死 ledger (PoC) — 真盾走 fighter.shield 数值, 别 push shield buff
##
## merge_mode (默认 "push" = 1:1 PoC: 同 type 裸 push 多条独立, recalc 逐条 sum/连乘, 各自 duration):
##   "push"      (默认) — 不合并, 每次新增一条独立 buff. 绝大多数 stat buff/debuff (PoC 裸 push)
##   "overwrite" — 同 type 已存在则取 max(value) + max(duration). 逐技能特例 (lava mrDown / physImmune / diceFateCrit)
##   "stack"     — value 累加 (duration 取 max)
##   "refresh"   — 只刷 duration, value 不变 (PoC merge-guard: dodge/healReduce/chilled/taunt/dmgReduce)
##   "ignore"    — 已存在则不加 (一次性: stun/blackhole/hunterMark/chiWaveActive)


## 控制类 buff: 龟蛋 (_eggImmune) 完全免疫 — 中心 add 口统一拦 (不论哪个技能施加).
##   stun=眩晕 (冻结 freeze 也走 stun 实现), taunt=嘲讽. 击飞 (knockup) 不是 buff (走 _knockedUpThisTurn flag), 在各施加点单独守卫.
const _EGG_IMMUNE_CONTROL := ["stun", "freeze", "taunt"]

## 加 buff. extras 注入额外字段 (chiWaveActive 的 critGain 等; dodgeCounter 的 dmgType)
static func add(f: Dictionary, type: String, value: float, duration: int,
		merge_mode: String = "push", extras: Dictionary = {}) -> Dictionary:
	# 龟蛋免控/免嘲讽: _eggImmune 单位拒收 stun/freeze/taunt (返回空壳, caller 拿到也无害)
	if f.get("_eggImmune", false) and type in _EGG_IMMUNE_CONTROL:
		return {"type": type, "value": value, "duration": 0, "_eggImmuneBlocked": true}
	var buffs: Array = f.get("buffs", [])
	if not f.has("buffs"):
		f["buffs"] = buffs

	# push (默认): 不查重, 直接往下新建一条独立 buff (1:1 PoC target.buffs.push)
	if merge_mode != "push":
		var existing = find(f, type)   # Variant (Dictionary or null), 不用 := 防 4.6 Variant 推断报错
		if existing != null:
			match merge_mode:
				"ignore":
					return existing
				"refresh":
					existing["duration"] = maxi(existing.get("duration", 0), duration)
					return existing
				"stack":
					existing["value"] = existing.get("value", 0) + value
					existing["duration"] = maxi(existing.get("duration", 0), duration)
					for k in extras:
						existing[k] = extras[k]
					return existing
				_:  # overwrite — 取 max
					existing["value"] = maxf(existing.get("value", 0), value)
					existing["duration"] = maxi(existing.get("duration", 0), duration)
					for k in extras:
						existing[k] = extras[k]
					return existing

	# 新建
	var nb := {"type": type, "value": value, "duration": duration}
	for k in extras:
		nb[k] = extras[k]
	buffs.append(nb)
	return nb


## 找首个同 type buff, 无则 null。禁止 caller 自己 .find — 一律走此。
static func find(f: Dictionary, type: String) -> Variant:
	var buffs: Array = f.get("buffs", [])
	for b in buffs:
		if b is Dictionary and b.get("type", "") == type:
			return b
	return null


static func has(f: Dictionary, type: String) -> bool:
	return find(f, type) != null


## 求和某 type 全部 value (多数情况 1 个; 备 lifesteal 多源)
static func sum_value(f: Dictionary, type: String) -> float:
	var total: float = 0.0
	var buffs: Array = f.get("buffs", [])
	for b in buffs:
		if b is Dictionary and b.get("type", "") == type:
			total += b.get("value", 0)
	return total


## 消费一次 (一次性 buff 如 trap): 返 value, 同时移除。无则 0。
static func consume_one(f: Dictionary, type: String) -> float:
	var buffs: Array = f.get("buffs", [])
	for i in range(buffs.size()):
		var b = buffs[i]
		if b is Dictionary and b.get("type", "") == type:
			var v: float = b.get("value", 0)
			buffs.remove_at(i)
			return v
	return 0.0


## 移除所有同 type buff, 返移除数
static func remove_all(f: Dictionary, type: String) -> int:
	var buffs: Array = f.get("buffs", [])
	var before: int = buffs.size()
	var kept: Array = []
	for b in buffs:
		if not (b is Dictionary and b.get("type", "") == type):
			kept.append(b)
	f["buffs"] = kept
	return before - kept.size()


# ─── 集合判定 (target selector / next_actor 用) ──────────────────

## 是否被眩晕且本回合还没用过跳过 (stun value=1, _stunUsed 守卫)
static func is_stunned(f: Dictionary) -> bool:
	return has(f, "stun") and not f.get("_stunUsed", false)


static func is_stealth(f: Dictionary) -> bool:
	return has(f, "stealth")


static func is_blackhole(f: Dictionary) -> bool:
	return has(f, "blackhole") or f.get("_isInBlackhole", false)


## 返回带 taunt buff 的 fighter 子集 (target selector 用)
static func collect_taunters(fighters: Array, side: String) -> Array:
	var out: Array = []
	for f in fighters:
		if f.get("side", "") == side and f.get("alive", false) and has(f, "taunt"):
			out.append(f)
	return out


## 决胜局 疲惫 (overtime fatigue): 30 回合后全龟获得, 治疗/护盾效果 ×0.5 直到战斗结束。
## 由 BattleScene._apply_overtime_escalation 设 _overtimeFatigue=true。
static func is_fatigued(f: Dictionary) -> bool:
	return f.get("_overtimeFatigue", false)

## 受治疗/获护盾的量按 疲惫 折算 (疲惫 → ×0.5, 否则原值)。返回 int。
static func fatigue_amt(f: Dictionary, amt) -> int:
	var m := 0.5 if f.get("_overtimeFatigue", false) else 1.0
	return roundi(float(amt) * m)

## 给 f 加护盾 (吃 疲惫 折算), 返回实际加的量 (供飘字显示用)。
static func grant_shield(f: Dictionary, amt) -> int:
	# 011 饮血护符坠 护盾效果增幅: 接盾单位 shieldAmp% 放大 (统一收口, 同 PoC shieldMult 思路但 per-fighter)
	var amped = amt
	var sa: float = float(f.get("shieldAmp", 0.0))
	if sa > 0.0:
		amped = roundi(float(amt) * (1.0 + sa / 100.0))
	var add: int = fatigue_amt(f, amped)
	f["shield"] = int(f.get("shield", 0)) + add
	return add


## 回合开始: 重置 per-turn 标记
static func reset_per_turn_flags(f: Dictionary) -> void:
	f["_stunUsed"] = false
	f["_equipFireStackedThisCast"] = false
