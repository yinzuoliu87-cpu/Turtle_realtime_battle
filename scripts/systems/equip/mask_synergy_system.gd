class_name MaskSynergySystem
extends RefCounted
## 面具羁绊【偷脸】(2026-11-25 · 方案书 docs/plans/20261125c-面具羁绊.md)
##
## 用户 11-25:「战斗开始时…根据档次来召唤属性相当于对面百分之五十属性的龟。拥有对面装备星级然后对面的装备星级是减一…
##   只有最大生命值和攻击力是百分之五十…其余的属性都是…跟它是一样的…一档的话就是偷一个，二档偷两个，三档偷三个…
##   这个偷来的这个替身，当他阵亡时，会把自己…最大生命值、攻击力、护甲魔抗的一定比例…给予最近的一名友军…包括召唤物」
##   「随机投的…对面三个目标里面随机投…对面终极战场可能只是活了两个…我们就只投两个」「一星的装备减一之后就是不带了」
##   「复制体会照原版放技能」「复制体出现在…我方阵地」「转化比例…百分之十、百分之二十、百分之三十五」「复制替代装备不算」「每路都偷」
##
## ── 规则 ──────────────────────────────────────────────────────
## · 每一路(上路 / 下路 / 终极战场)开打的第一帧, 有面具羁绊的一方从对面这一路**活着的龟**(统领 / 小将; 不含训龟大师、龟蛋、召唤物、
##   别人的复制体)里按对局种子随机挑 STEAL_N[档] 只(不够就有几只挑几只), 在我方阵地(跟原版左右对称的位置)生成复制体。
## · 复制体 = 同一种龟(小将同角色 / 精英标记), 等级按原版那一方; 装备照抄、每件星级 −1, 一星的不带;
##   装备效果照常生效, 但不算我方任何羁绊的件数(`_mask_copy` ⇒ synergy_system 场上口径跳过; 真实对局按全阵容名单数, 本来就数不到)。
## · 属性: 最大生命值、攻击力 = 原版最终值的 COPY_HP / COPY_ATK(50%); 其余(护甲 / 魔抗 / 暴击 / 暴伤 / 穿透 / 吸血 / 增伤 /
##   减伤 / 攻速 / 移速 / 射程 / 充能…)照抄原版最终值(INHERIT)。照原版放技能、带原版被动(`_make_unit` 同一条路)。
## · 复制体阵亡: 把自己最大生命值、攻击力、护甲、魔抗的 GIVE_PCT[档] 永久(当路)加给离它最近的一名友军(任意单位, 含召唤物)。
const STEAL_N := [1, 2, 3]
const COPY_HP := 0.5
const COPY_ATK := 0.5
const GIVE_PCT := [0.10, 0.20, 0.35]
## 照抄原版的属性字段(装备 / 羁绊 / 等级加完之后的最终值; base_* 是 _recalc_stats 的底数)
const INHERIT := ["base_def", "base_mr", "crit", "crit_dmg", "armor_pen", "magic_pen", "lifesteal", "damage_amp", "damage_reduction",
	"aspd_perm", "move_perm", "range_add", "range_perm", "echarge_perm", "heal_amp", "shield_amp", "reflect"]
## ⚠ 闪避走 buff 通道(equip_stats_apply: dodgePct → _buff "dodge"), 不在字段里 ⇒ 复制体的闪避来自它自己降星后的装备, 不照抄(待补)

var battle
var _lane_t0 := -1.0
var _done := {"left": false, "right": false}
## 门禁量: 本进程生成过几只复制体、阵亡转过几次属性
var stolen := 0
var gifted := 0


func _init(b) -> void:
	battle = b


func side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "面具")))
	return t


func tick(_dt: float) -> void:
	var t0 := float(battle._sd_t0)
	if t0 != _lane_t0:
		_lane_t0 = t0
		_done = {"left": false, "right": false}
	if bool(battle.get("_over")):
		return
	for side in ["left", "right"]:
		if bool(_done[side]):
			continue
		_done[side] = true
		var tier := side_tier(side)
		if tier > 0:
			steal(side, tier)


## 从对面这一路随机挑 n 只, 生成复制体。返回生成的复制体(门禁用)。
func steal(side: String, tier: int, extra: int = 0) -> Array:
	var foes: Array = []
	for o in battle._units:
		if not (o is Dictionary) or not o.get("alive", false) or str(o.get("side", "")) == side:
			continue
		if bool(o.get("_isEgg", false)) or bool(o.get("is_summon", false)) or bool(o.get("_mask_copy", false)) or battle._is_untouchable(o):
			continue
		foes.append(o)
	var n: int = mini(int(STEAL_N[clampi(tier, 1, 3) - 1]) + extra, foes.size())
	var out: Array = []
	for _i in range(n):
		var k: int = battle._battle_rng.randi() % foes.size()
		var o: Dictionary = foes[k]
		foes.remove_at(k)
		var c := make_copy(o, side, tier)
		if not c.is_empty():
			out.append(c)
	return out


## 生成 o 的复制体到 side 方(位置 = 跟原版左右对称)
func make_copy(o: Dictionary, side: String, tier: int) -> Dictionary:
	var cx: float = float(battle._arena_center.x)
	var p: Vector2 = Vector2(o["pos"])
	var pos := Vector2(2.0 * cx - p.x, p.y)
	if battle.get("_dl_sys") != null and battle._dl_sys.has_method("clamp_place_side"):
		pos = battle._dl_sys.clamp_place_side(pos, side)
	var minion: bool = str(o.get("id", "")) == "__minion__"
	var spec: Dictionary
	if minion:
		spec = {"minion": true, "role": str(o.get("minion_role", "front")), "elite": bool(o.get("is_elite", false)), "level": int(o.get("level", 1))}
	else:
		## 等级表按原版那一方查(同驯服归顺进终极战场的做法); 属性下面整份按原版最终值覆盖, 这里只影响固定值召唤的等级倍率
		spec = {"lv_side": str(o.get("lv_side", o.get("side", "")))}
	var c: Dictionary = battle._spawn._make_unit(str(o.get("id", "basic")), side, pos, spec)
	if c.is_empty():
		return {}
	if not minion:
		c["lv_side"] = str(spec["lv_side"])
	c["level"] = int(o.get("level", c.get("level", 1)))
	c["_mask_copy"] = true
	c["_mask_tier"] = tier
	c["_mask_of_id"] = str(o.get("id", ""))
	c["face_right"] = side == "left"
	c["_face_x"] = pos.x
	battle._units.append(c)
	## 装备: 每件星级 −1, 一星的不带
	var eqs: Array = []
	for e in o.get("equips", []):
		if e is Dictionary and int((e as Dictionary).get("star", 1)) > 1:
			eqs.append({"id": str((e as Dictionary)["id"]), "star": int((e as Dictionary)["star"]) - 1})
	c["equips"] = eqs
	for e in eqs:
		c["eq_state"][str(e["id"])] = {}
	battle._equip_sys._stats.apply_unit(c)
	battle._spawn._apply_spawn_passive_one(c)
	## 属性: 生命 / 攻击取原版一半, 其余照抄原版
	for f in INHERIT:
		if o.has(f):
			c[f] = o[f]
	c["maxHp"] = maxf(1.0, float(o.get("maxHp", 1.0)) * COPY_HP)
	c["hp"] = c["maxHp"]
	c["base_atk"] = float(o.get("base_atk", 0.0)) * COPY_ATK
	battle._recalc_stats(c)
	stolen += 1
	var v = _vfx()
	if v != null and v.has_method("mask_copy_spawn"):
		v.mask_copy_spawn(c, o)
	return c


## 主场景单位阵亡时调: 死的是复制体 ⇒ 把它的核心属性按比例加给最近的一名友军(含召唤物)
func on_death(u: Dictionary) -> void:
	if not bool(u.get("_mask_copy", false)):
		return
	var side := str(u.get("side", ""))
	var best = null
	var bd := INF
	for a in battle._units:
		if not (a is Dictionary) or is_same(a, u) or not a.get("alive", false) or str(a.get("side", "")) != side:
			continue
		if bool(a.get("_isEgg", false)) or battle._is_untouchable(a):
			continue
		var d: float = DetMath.dist(Vector2(a["pos"]), Vector2(u["pos"]))
		if d < bd:
			bd = d
			best = a
	if not (best is Dictionary):
		return
	var k: float = float(GIVE_PCT[clampi(int(u.get("_mask_tier", 1)), 1, 3) - 1])
	var b: Dictionary = best
	var add_hp: float = float(u.get("maxHp", 0.0)) * k
	b["maxHp"] = float(b.get("maxHp", 0.0)) + add_hp
	b["hp"] = float(b.get("hp", 0.0)) + add_hp
	b["base_atk"] = float(b.get("base_atk", 0.0)) + float(u.get("base_atk", 0.0)) * k
	b["base_def"] = float(b.get("base_def", 0.0)) + float(u.get("base_def", 0.0)) * k
	b["base_mr"] = float(b.get("base_mr", 0.0)) + float(u.get("base_mr", 0.0)) * k
	battle._recalc_stats(b)
	gifted += 1
	var v = _vfx()
	if v != null and v.has_method("mask_gift"):
		v.mask_gift(u, b)


func reset_match() -> void:
	_lane_t0 = -1.0
	_done = {"left": false, "right": false}


func _vfx():
	return null   # 演出层(面具特效)接上之前不画
