extends RefCounted

## 局中事件系统 — 1:1 PoC engine/events.ts
## 注: 不用 class_name (新增全局类需重导/重启才注册, 运行时会"未声明") → 引用方用 preload 直引, 稳定。
## 触发: 第 3/6/9/12 回合战斗开始时, 整场互斥 1 个 (env 事件 或 中立生物)。

# ── 环境事件 (6 个, JS events.js:33-98) ──
const ENV_EVENT_IDS := ["volcano", "tide", "thunder", "meteor", "treasure-rain", "fog"]

const ENV_EVENT_META := {
	"volcano":       {"name": "火山喷发", "emoji": "🌋", "desc": "所有前排损 8% 最大生命 (真伤)"},
	"tide":          {"name": "涨潮",    "emoji": "🌊", "desc": "全员 攻击 -15 / 护甲 +10 (2 回合)"},
	"thunder":       {"name": "雷暴",    "emoji": "⚡", "desc": "后续 3 回合每回合随机单位 40 真伤"},
	"meteor":        {"name": "流星雨",  "emoji": "🌠", "desc": "双方各 1 名随机龟受 100 法术"},
	"treasure-rain": {"name": "财宝雨",  "emoji": "💰", "desc": "双方各 +30 深海币"},
	"fog":           {"name": "浓雾",    "emoji": "🌫", "desc": "全员 闪避 +15% (2 回合)"},
}


## 应用环境事件效果 (1:1 PoC apply()). 直接改 fighter dict。币(treasure-rain)由 BattleScene 处理。
static func apply_env_event(event_id: String, all_fighters: Array) -> void:
	# 龟蛋(_isEgg)免疫所有环境事件 (基地, 只被攻击削血; 否则火山/流星/雷暴会绕过 _eggImmune+终极×5 直接砍蛋 — 双路bug)
	var targets: Array = all_fighters.filter(func(f): return not f.get("_isEgg", false))
	match event_id:
		"volcano":
			# 所有 front 排损 8% maxHp 真伤 (敌我都损) — ts:21
			for f in targets:
				if not f.get("alive", false) or str(f.get("_position", "")) != "front":
					continue
				var dmg: int = maxi(1, roundi(int(f.get("maxHp", 0)) * 0.08))
				f["hp"] = maxi(0, int(f.get("hp", 0)) - dmg)
				if int(f["hp"]) == 0:
					f["alive"] = false
		"tide":
			# 全员 atkDown15 + defUp10, 2 回合 — ts:34
			for f in targets:
				if not f.get("alive", false):
					continue
				(f["buffs"] as Array).append({"type": "atkDown", "value": 15, "duration": 2})
				(f["buffs"] as Array).append({"type": "defUp", "value": 10, "duration": 2})
				f["atk"] = maxi(0, int(f.get("baseAtk", 0)) - 15)
				f["def"] = int(f.get("baseDef", 0)) + 10
		"thunder":
			# 随机单位 40 真伤 + 标记后续 2 回合 (_thunderstormTurns) — ts:48
			var t_alive: Array = targets.filter(func(f): return f.get("alive", false))
			if t_alive.is_empty():
				return
			var t: Dictionary = t_alive[randi() % t_alive.size()]
			t["hp"] = maxi(0, int(t.get("hp", 0)) - 40)
			if int(t["hp"]) == 0:
				t["alive"] = false
			for f in targets:
				f["_thunderstormTurns"] = 2
		"meteor":
			# 双方各 1 随机龟受 100 法术 (PoC 简化不走 mr) — ts:64
			for side in ["left", "right"]:
				var sa: Array = targets.filter(func(f): return f.get("alive", false) and f.get("side", "") == side)
				if sa.is_empty():
					continue
				var mt: Dictionary = sa[randi() % sa.size()]
				mt["hp"] = maxi(0, int(mt.get("hp", 0)) - 100)
				if int(mt["hp"]) == 0:
					mt["alive"] = false
		"treasure-rain":
			pass   # 双方各 +30 币, 在 BattleScene 处理 (this.coins += 30 / aiGainCoins) — ts:79
		"fog":
			# 全员 dodge 15% 2 回合 — ts:87
			for f in targets:
				if not f.get("alive", false):
					continue
				(f["buffs"] as Array).append({"type": "dodge", "value": 15, "duration": 2})


## 第 turn 回合抽环境事件 (3/6/9/12, 已触发的排除). 返回 event_id 或 ""。1:1 PoC rollEventForTurn:97。
static func roll_event_for_turn(turn: int, already_fired: Array) -> String:
	if turn not in [3, 6, 9, 12]:
		return ""
	var pool: Array = ENV_EVENT_IDS.filter(func(e): return not already_fired.has(e))
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]


# ── 中立生物 (3 个, JS events.js:10-31) ──
const NEUTRAL_TEMPLATES := {
	"treasure": {"id": "treasure_golem", "name": "宝箱怪", "emoji": "🎁", "hp": 300, "atk": 30, "def": 0, "mr": 0, "atkScale": 0.5, "bigReward": {"coins": 30, "equip": 1}, "smallReward": {"coins": 25}},
	"crab":     {"id": "giant_crab",     "name": "巨蟹",   "emoji": "🦀", "hp": 400, "atk": 40, "def": 0, "mr": 0, "atkScale": 1.0, "bigReward": {"coins": 20, "equip": 1}, "smallReward": {"coins": 15}},
	# 海葵母: 寄生型不站场, 附双方各 1 寄主 (+350盾 +15攻); 盾被对面打穿=击杀, 首破拿大奖。满格只出它。
	"anemone":  {"id": "anemone_mother", "name": "海葵母", "emoji": "🪼", "hp": 0, "atk": 0, "def": 0, "mr": 0, "atkScale": 0, "parasiteShield": 350, "hostAtkBonus": 15, "bigReward": {"coins": 15, "debuff": "purify"}, "smallReward": {"coins": 10}},
}


## 第 turn 回合是否抽中立 (3/6/9/12, 60% 中立 / 40% 走 env). 返回 {"type": key} 或 {}。1:1 PoC rollNeutralForTurn:150。
##   both_sides_full: 双方 6 格都满 → 强制海葵母 (寄生型无需空位)。
static func roll_neutral_for_turn(turn: int, neutral_spawned: bool, both_sides_full: bool = false) -> Dictionary:
	if turn not in [3, 6, 9, 12]:
		return {}
	if neutral_spawned:
		return {}
	if randf() >= 0.6:
		return {}   # 40% → null, BattleScene 改走 roll_event_for_turn
	if both_sides_full:
		return {"type": "anemone"}
	var r: float = randf()
	var ntype: String = "treasure" if r < 1.0 / 3.0 else ("crab" if r < 2.0 / 3.0 else "anemone")
	return {"type": ntype}
