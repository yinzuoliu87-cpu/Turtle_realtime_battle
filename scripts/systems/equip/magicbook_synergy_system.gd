class_name MagicbookSynergySystem
extends RefCounted
## 魔法书羁绊【飞弹】(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md §4.1)
##
## 用户 11-25:「每释放一次技能的话，我方所有单位啊，包括召唤物啊，每释放一次技能，会召唤一定数量的这个魔法飞弹，
##   魔法飞弹的数量等于就是消耗技能消耗的龟能除以一个值，就可以这可以按档变化嘛。然后飞向随机敌人，
##   造成每个飞弹造成固定加上目标百分比的魔法伤害」「骷髅放技能也会触发飞弹，肯定是的」
##
## ── 规则 ─────────────────────────────────────────────────────────────
## · 入口 `on_cast(u, cost)`: 我方任意单位(龟 / 小将 / 召唤物)释放一次技能、消耗 cost 龟能时调。
##   龟与小将: 主场景施法成功处(`_cast_skill` 之后, 同 `_eq_on_cast`); 召唤物: 各自的技能入口(暗影忍者影袭 / 炮筒进重炮 /
##   武士刀小将 / 骷髅…)。训龟大师不调(装饰, 免疫一切)。镜像魔典「再放一次」也算一次释放技能, 照样调。
## · 枚数 = floor(cost / PER_ENERGY[档]), 至少 1 枚; cost ≤ 0(没耗龟能的被动)不出。
## · 每枚挑一个随机敌人(对局种子 `_battle_rng`; 龟蛋 / 训龟大师 / 不可选中除外, 走 `_pick_enemies_of`), 可重复挑同一个;
##   按 SPD 追着目标飞(通用飞行物 `launch_flight`), 打到才结算; 目标半路死了 ⇒ 落空。
## · 伤害 = DMG_FLAT[档] + DMG_MAXHP[档] × 目标最大生命(真实 maxHp, CLAUDE.md §4.1), 魔法, 不暴击(羁绊没有攻击力来源)。
## · 属性: 每件魔法书给携带者增伤(Phase2Types.TYPES["魔法书"], 逐档)。
const PER_ENERGY := [20.0, 15.0, 10.0]
const DMG_FLAT := [20.0, 35.0, 60.0]
const DMG_MAXHP := [0.01, 0.015, 0.025]
const SPD := 900.0
const COL_MAGIC := Color("#8fd3ff")

var battle
## 门禁量: 本进程发出 / 打中的飞弹数
var fired := 0
var landed := 0


func _init(b) -> void:
	battle = b


func side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "魔法书")))
	return t


## 这次释放能出几枚(纯函数, 门禁与文案对账用)
static func missiles_for(cost: float, tier: int) -> int:
	if cost <= 0.0 or tier <= 0:
		return 0
	return maxi(1, int(floor(cost / float(PER_ENERGY[clampi(tier, 1, PER_ENERGY.size()) - 1]))))


## 龟本体释放了一次技能(主场景施法成功处 / 双头延后施法 / 124 镜像魔典的「再放一次」都走这里):
##   先让携带者身上的魔法书逐件生效(EqMagicBatch.on_unit_cast), 再出【飞弹】。cost = 这次消耗的龟能(_skill_cost, 已扣 125 的减少)。
func after_cast(u: Dictionary, tgt, stype: String, echo: bool = false) -> void:
	var cost: float = float(battle._skill_cost(u, stype)) if stype != "" else 0.0
	battle._equip_sys._magic_sys.on_unit_cast(u, tgt, stype, cost, echo)
	on_cast(u, cost)


## 召唤物 / 小将等「自己管龟能」的单位放了一次技能(各自的技能入口直接调, cost = 它那条技能条的满值)。
func on_cast(u: Dictionary, cost: float) -> void:
	if not (u is Dictionary) or not u.get("alive", false) or battle._is_untouchable(u):
		return
	if bool(battle.get("_over")):
		return
	var side := str(battle._eff_side(u))
	var tier := side_tier(side)
	var n := missiles_for(cost, tier)
	if n <= 0:
		return
	var foes: Array = battle._targeting._pick_enemies_of(u)
	if foes.is_empty():
		return
	var k := clampi(tier, 1, DMG_FLAT.size()) - 1
	var from2: Vector2 = u["pos"]
	for i in range(n):
		var tgt: Dictionary = foes[battle._battle_rng.randi() % foes.size()]
		fired += 1
		var node = _vfx_launch(u, tgt, i, n)
		var src: Dictionary = u
		battle._ballistics.launch_flight(u, from2, tgt, SPD,
			func(hit: bool) -> void:
				_vfx_land(node, tgt, hit)
				if not hit:
					return
				landed += 1
				var base: float = float(DMG_FLAT[k]) + float(DMG_MAXHP[k]) * float(tgt.get("maxHp", 0.0))
				var dmg: int = battle._resolve_dmg(src, base, tgt, true, false)
				battle._damage._apply_damage_from(src, tgt, dmg, COL_MAGIC, 0.0, false, true),
			func(kk: float, p2: Vector2, to2: Vector2) -> void: _vfx_step(node, from2, p2, to2, kk, i))


## ── 演出(只画不算; 无头 / 没有世界节点时什么都不做) ──────────────────────
func _vfx():
	var es = battle.get("_equip_sys")
	if es == null or es.get("_magic_sys") == null:
		return null
	return es._magic_sys.vfx


func _vfx_launch(u: Dictionary, tgt: Dictionary, i: int, n: int):
	var v = _vfx()
	return v.mb_launch(u, tgt, i, n) if v != null else null


func _vfx_step(node, from2: Vector2, p2: Vector2, to2: Vector2, k: float, i: int) -> void:
	var v = _vfx()
	if v != null:
		v.mb_step(node, from2, p2, to2, k, i)


func _vfx_land(node, tgt: Dictionary, hit: bool) -> void:
	var v = _vfx()
	if v != null:
		v.mb_land(node, tgt, hit)


func reset_match() -> void:
	pass
