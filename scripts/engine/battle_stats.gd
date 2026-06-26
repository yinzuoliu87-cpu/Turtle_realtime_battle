class_name BattleStats
extends RefCounted
# ══════════════════════════════════════════════════════════
# battle_stats.gd — 局内战斗统计 tracker (1:1 PoC src/systems/battle-stats.ts)
# 4 维: dmgDealt(输出) / dmgTaken(承受) / healDone+healTaken(治疗) / shieldGained(护盾) / kills(击杀)
# dmgDealt·dmgTaken 各按 4 dmgType 拆分: phy 物理 / mag 法术 / tru 真实 / dot DoT。
# 每场战斗 reset(); 开战 register_all(fighters) 预登记; 结算面板读取展示。
#
# ── 与 PoC 不同点: keying 方案 (关键, 必须看) ──────────────────────────────
# PoC 用 Map<Fighter, FighterStats> 按 *对象引用* keying (battle-stats.ts:42-46):
#   test 模式 6 个假人 id 都是 'basic', 玩家小龟也 'basic' → 若按 f.id 会全挤进一条,
#   玩家"造成"与假人"承受"写进同一行 → 显示成小龟自己承伤 (用户报的 bug)。
#
# Godot 里 fighter 是 Dictionary。GDScript 虽可拿 Dictionary 当 key, 但它按内容/引用的
#   比较语义随版本&可变性不稳, 且 fighter 在战斗中被大量原地改写 → 不可靠。
# 所以本移植给每个 fighter 在 register_all 时盖一个稳定整数 _uid (从 1 递增), 按 _uid keying。
#   _uid 一旦盖上不再变, 与 PoC "对象引用每只龟独立" 等价; 且绝不能用 f.id (会撞, 见上)。
#   record_* 收到未登记的 fighter 时 _ensure 会补盖 _uid 并登记 (对齐 PoC ensure 惰性建桶)。
# ══════════════════════════════════════════════════════════

const DMG_TYPES: Array[String] = ["phy", "mag", "tru", "dot"]

## P23 统计面板 bar 配色 1:1 (JS battle.css:629-633): 物理红/法术蓝/真实白/dot橙。
const DMG_TYPE_INFO := {
	"phy": {"label": "物理", "color": 0xff4444, "css": "#ff4444"},
	"mag": {"label": "法术", "color": 0x4dabf7, "css": "#4dabf7"},
	"tru": {"label": "真实", "color": 0xffffff, "css": "#ffffff"},
	"dot": {"label": "DoT", "color": 0xff6600, "css": "#ff6600"},
}

# _uid(int) → FighterStats(Dictionary)。1:1 PoC bucket: Map<Fighter, FighterStats>。
var _bucket: Dictionary = {}
var _next_uid: int = 1


static func _zero_breakdown() -> Dictionary:
	return {"phy": 0, "mag": 0, "tru": 0, "dot": 0}


## 1:1 PoC reset(): 清空所有桶。每场战斗开始调一次。
func reset() -> void:
	_bucket.clear()
	_next_uid = 1


## 1:1 PoC registerAll(): 开战预登记全体 → 面板初始就能列出所有龟(值 0), 而非空白。
## 对齐 JS updateDmgStats 遍历 allFighters。
func register_all(fighters: Array) -> void:
	for f in fighters:
		_ensure(f)


## 取 / 建 fighter 的统计桶。1:1 PoC ensure(): 惰性建桶, 顺带盖 _uid。
func _ensure(f: Dictionary) -> Dictionary:
	var uid: int = int(f.get("_uid", 0))
	if uid == 0:
		uid = _next_uid
		_next_uid += 1
		f["_uid"] = uid
	var s = _bucket.get(uid, null)
	if s == null:
		# _isNeutral / _isMasterTrainer: 中立生物, side 虽左/右但不算玩家战绩 → 面板单独排除。
		var is_neutral: bool = f.get("_isNeutral", false) or f.get("_isMasterTrainer", false)
		s = {
			"id": f.get("id", ""), "name": f.get("name", ""), "side": f.get("side", ""),
			"isNeutral": is_neutral,
			"dmgDealt": 0, "dmgDealtByType": _zero_breakdown(),
			"dmgTaken": 0, "dmgTakenByType": _zero_breakdown(),
			"healDone": 0, "healTaken": 0, "shieldGained": 0, "kills": 0, "crits": 0,
			"_uid": uid, "_fighter": f,  # _fighter: 反查活/死状态供面板 ds-dead 标记
		}
		_bucket[uid] = s
	return s


## 记暴击命中 (attacker +1, 1:1 PoC actor.stats.crits++ BattleScene.ts:3289/3537) — 结算面板"暴击"列。
func record_crit(fighter) -> void:
	if not (fighter is Dictionary):
		return
	var s := _ensure(fighter)
	s["crits"] = int(s.get("crits", 0)) + 1


## caster 对 target 造成 amount 伤害; dmg_type 默认 "phy" (向后兼容)。1:1 PoC recordDamage (L75)。
## caster 可为 null (无来源伤害, e.g. 中毒/环境)。
func record_damage(caster, target: Dictionary, amount: int, dmg_type: String = "phy") -> void:
	if amount <= 0:
		return
	if caster is Dictionary:
		var cs := _ensure(caster)
		cs["dmgDealt"] = int(cs["dmgDealt"]) + amount
		cs["dmgDealtByType"][dmg_type] = int(cs["dmgDealtByType"][dmg_type]) + amount
		# P19 1:1 JS combat.js:205 — 累计到 fighter 自身 _dmgDealt (神罚 angelSmite 自动选
		#   "造成伤害最高"敌人读它; 之前从不赋值 → 全员 0 平手 → 神罚随机选, 非最高伤害)。
		caster["_dmgDealt"] = int(caster.get("_dmgDealt", 0)) + amount
	var ts := _ensure(target)
	ts["dmgTaken"] = int(ts["dmgTaken"]) + amount
	ts["dmgTakenByType"][dmg_type] = int(ts["dmgTakenByType"][dmg_type]) + amount


## caster 给 target 治疗 amount (实际回的)。1:1 PoC recordHeal (L93)。caster 可为 null。
func record_heal(caster, target: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	if caster is Dictionary:
		var cs := _ensure(caster)
		cs["healDone"] = int(cs["healDone"]) + amount
	var ts := _ensure(target)
	ts["healTaken"] = int(ts["healTaken"]) + amount


## target 获得 amount 护盾。1:1 PoC recordShield (L101)。
func record_shield(target: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	var ts := _ensure(target)
	ts["shieldGained"] = int(ts["shieldGained"]) + amount


## caster 击杀 target。1:1 PoC recordKill (L108)。caster 可为 null。
## 注: PoC 这里还 emit 'fighter:died' bus 事件 (中立 KO reward 等订阅) — Godot 侧该 bus
##   信号由调用方/BattleScene 负责发, 本 tracker 只记 kills 计数 (不引入 bus 依赖)。
func record_kill(caster, _target: Dictionary) -> void:
	if caster is Dictionary:
		var cs := _ensure(caster)
		cs["kills"] = int(cs["kills"]) + 1


# ─── 取数接口 (供结算面板读) ─────────────────────────────────────────────

## 全部记录 (含中立)。1:1 PoC all()。每项是 FighterStats Dictionary。
func all() -> Array:
	return _bucket.values()


## 按 side ("left"/"right") 过滤。1:1 PoC bySide()。
func by_side(side: String) -> Array:
	var out: Array = []
	for s in _bucket.values():
		if s.get("side", "") == side:
			out.append(s)
	return out


## 某 fighter 的统计桶 (没记录返回 null)。便捷取数, PoC 无对应但面板可用 _uid 直查。
func for_fighter(f: Dictionary) -> Dictionary:
	var uid: int = int(f.get("_uid", 0))
	if uid == 0:
		return {}
	return _bucket.get(uid, {})
