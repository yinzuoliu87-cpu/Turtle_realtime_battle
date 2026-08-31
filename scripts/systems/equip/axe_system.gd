class_name AxeSystem
extends RefCounted
## 小木斧 —— 斧头召唤物 + 通用主动 + 被动 2 (用户 2026-08-31·方案书三期)
##
## ★数值**全部**取自 `scripts/gamedata/axe_evolution.gd`(AxeEvolution)。
##   这里一个裸数字都不许有 —— 036 温泉蛋刚踩过"同一个数存两份必漂"。
##
## ★本期(三期)只做骨架:
##   · 登场召唤斧头(近战 / 1ATK / 0.8 攻速 / 双抗 5 / 血与攻随**历史累计经验**)
##   · 通用主动: 攒满 140 龟能 → 召唤物回 5% 最大生命 + 给自己 5% 最大生命护盾
##   · 被动 2(木斧就有): 召唤物普攻窃取目标 10% 护盾, **转成普通护盾**给自己
##   经验条/进化/商店换形态在四期; 被动 3~6 在五期; 最终造物在六期。
##
## ★「已收集的经验值」= **历史累计**(未决点 ⑥, 用户 2026-08-31「历史累计」)。
##   本期还没有攒经验的通路(那是四期), 所以读到的是 0 ⇒ 木斧召唤物 = 500 血 / 30 攻。
##   读的地方只有一个 `_exp_total()`, 四期把它接到 GameState 上即可。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AP := preload("res://scripts/systems/equip/axe_passives.gd")

var battle = null
var _pas = null                          # 被动 3~6(五期), 见 axe_passives.gd


func _init(b) -> void:
	battle = b
	_pas = AP.new(b)


## 历史累计经验。★四期之前恒为 0 —— 但**必须现在就走这个函数**,
##   否则四期接上经验时得回头找散落各处的 0。
func _exp_total() -> int:
	return _gs_int("axe_exp_total", 0)


## 当前档位索引(0=木斧)。四期之前恒为 0。
func _stage_idx() -> int:
	return clampi(_gs_int("axe_stage", 0), 0, AE.STAGES.size() - 1)


## 从 GameState 读一个整数, **null 安全**。
## ★★这条防的是 memory [[fb-null-readback-makes-test-silently-abort]] 那个坑:
##   `Node.get("不存在的属性")` 返回 **null**, 而 `int(null)` 是运行时错误 ——
##   它会让**调用它的那个函数当场中止**, 剩下的断言一条都不跑, 而门禁照样打 ALL PASS
##   (唯一线索是断言总数悄悄变少)。所以这里显式判 null 再转。
func _gs_int(prop: String, dflt: int) -> int:
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null:
		return dflt
	var v = gs.get(prop)
	if v == null:
		return dflt
	return int(v)


## 登场召唤斧头。照 058 炮台的 `_spawn_summon` 底座。
func summon(u: Dictionary) -> Variant:
	if not u.get("alive", false):
		return null
	var et: int = _exp_total()
	var si: int = _stage_idx()
	var pv: int = AE.passives_at(si)
	var ax = battle._spawn._spawn_summon(u, "axe", AE.minion_hp(et, pv), AE.minion_atk(et, pv),
		{"label": str(AE.stage(si)["name"]), "spr_id": "axe", "col_size": AE.MINION_COL_SIZE, "hp_w": 28.0,
		 "atk_interval": 1.0 / AE.MINION_ASPD, "melee": true})
	if ax == null:
		return null
	ax["eq_state"] = {}
	ax["equips"] = []
	ax["_eq_axe"] = true                    # 认亲标记: 被动 2 / 主动都靠它认出"这是斧头"
	## ★把档位解锁的被动条数**钉在召唤物身上**, 而不是每次用的时候回头问 GameState:
	##   一路打到一半玩家在别处进化了, 场上这只不该中途变身(它的血/攻也是登场那一刻算的)。
	ax["_axe_pv"] = pv
	ax["base_def"] = AE.MINION_DEF
	ax["base_mr"] = AE.MINION_MR
	## ★主动是**召唤物自己**攒龟能(需求「主动治疗140龟能：斧头召唤物回复…并为自己提供…」,
	##   而且最终造物 4 明写"处决一个单位会使召唤物获得150点龟能" ⇒ 龟能确实在召唤物身上)。
	ax["maxEnergy"] = AE.ACTIVE_ENERGY
	ax["energy"] = 0.0
	battle._recalc_stats(ax)
	ax["hp"] = float(ax["maxHp"])
	u["_axe_ref"] = ax                       # ★只用 is_same 比较, 绝不当 Dictionary 的键(CLAUDE.md §3.2)
	return ax


## 这一档的斧头召唤物**应该**是多少血/多少攻(纯函数, 门禁直接调它验数)。
func expected_hp() -> float:
	return AE.minion_hp(_exp_total(), AE.passives_at(_stage_idx()))


func expected_atk() -> float:
	return AE.minion_atk(_exp_total(), AE.passives_at(_stage_idx()))


## 通用主动: 攒满 140 龟能 → 回 5% 最大生命 + 给自己 5% 最大生命护盾, 然后清空龟能。
## ★结算与演出分开(CLAUDE.md §3.5): 这个函数是**纯结算**, 门禁直接调它;
##   演出(如果以后加)在末尾调它, 不许把数值埋进 tween 链。
func cast_heal(ax: Dictionary) -> bool:
	if not (ax is Dictionary) or not ax.get("alive", false):
		return false
	if float(ax.get("energy", 0.0)) < AE.ACTIVE_ENERGY:
		return false
	ax["energy"] = 0.0
	var mh: float = float(ax.get("maxHp", 0.0))
	battle._damage._heal(ax, mh * AE.ACTIVE_HEAL_PCT)
	battle._damage._grant_shield(ax, mh * AE.ACTIVE_SHIELD_PCT)
	return true


## 每帧: 龟能满了就放主动。
## ★放在装备层的 tick 里, 不进主场景(架构预算只减不增; 而且它不在 _sim_step 的必经链上)。
func tick(u: Dictionary, _delta: float) -> void:
	var ax = u.get("_axe_ref", null)
	if not (ax is Dictionary) or not ax.get("alive", false):
		return
	_pas.tick_smash(ax, _delta)
	## ★蓄力中不再放主动 —— 否则 140 龟能一满就把蓄力重开, 永远砸不下去。
	if _pas.tick_charge(ax, _delta) >= 0:
		return
	if cast_heal(ax):
		_pas.begin_charge(ax)            # 被动 6: 释放治疗时进入蓄力


## 被动 2(木斧解锁): 斧头**普攻**命中带护盾的目标 → 偷走 10% 护盾, **转成普通护盾**给自己。
## 返回偷到的量(门禁拿它当分母)。
## ★「比如有特殊护盾也转普通护盾给自己」——
##   本作只有一个护盾池 `u["shield"]`; 圣光盾是拿 `_holyShieldVal` 在这个池子上打的**标记**,
##   不是第二个池。所以"特殊护盾"要一起偷走, 做法是: 从池子里扣 10%, 并**按比例把标记也削掉**,
##   否则标记会大于池子本身(那会让血条的白黄段画出比护盾还长的一截)。
func steal_shield(ax: Dictionary, tgt: Dictionary) -> float:
	if not (ax is Dictionary) or not (tgt is Dictionary):
		return 0.0
	if not ax.get("_eq_axe", false) or not ax.get("alive", false) or not tgt.get("alive", false):
		return 0.0
	var sh: float = float(tgt.get("shield", 0.0))
	if sh <= 0.0:
		return 0.0
	var take: float = sh * AE.SHIELD_STEAL_PCT
	tgt["shield"] = sh - take
	var holy: float = float(tgt.get("_holyShieldVal", 0.0))
	if holy > 0.0:
		tgt["_holyShieldVal"] = minf(holy, float(tgt["shield"]))   # 标记不许超过池子
	battle._damage._grant_shield(ax, take)
	return take


## 斧头的 on-hit(只有普攻算)。
func on_hit(src: Dictionary, tgt: Dictionary, basic: bool) -> void:
	if not (src is Dictionary) or not src.get("_eq_axe", false):
		return
	if tgt is Dictionary:
		## 助攻窗的起点(四期)。★记在**被打的那个**身上, 而不是在斧头身上记一份名单 ——
		##   名单要拿单位字典当元素比对, 而单位字典之间互相引用成环(CLAUDE.md §3.2)。
		tgt["_axe_touch_t"] = float(battle._t)
	if not basic:
		return
	steal_shield(src, tgt)
	## ── 五期被动(只对【普攻】生效, 与被动 2 同一条闸) ──
	## ★顺序有意: 先记这是第几下, 再按奇偶分派横扫/竖劈, 最后才是强化 on-hit 与效率层。
	##   强化 on-hit 会击飞目标, 放在选靶之前会让横扫的名单跟着位移变(判据就飘了)。
	var sw: int = _pas.bump_swing(src)
	_pas.cleave_settle(src, tgt, sw)                       # 被动4: 偶数次 → 竖劈
	for o in _pas.sweep_targets(src, tgt, sw):             # 被动5: 奇数次 → 180° 横扫
		if not is_same(o, tgt) and o.get("alive", false):
			battle._damage._apply_damage_from(src, o, maxi(1, int(round(float(src.get("atk", 0.0))))),
				Color("#cfd8dc"), 0.0, false, true)
	_pas.smash_on_hit(src, tgt)                            # 被动3: 每 9 秒一次强化
	_pas.add_eff(src)                                      # 被动5: 效率层 +1


## ── 四期: 击杀 / 助攻 +2 砍伐经验 ────────────────────────────
## ★为什么不挂 `_eq_on_kill`: 那条钩子遍历**击杀者的 equips**, 而斧头是召唤物、
##   身上一件装备都没有, 永远轮不到它。而且它还要求击杀者 `alive` ——
##   斧头与目标同归于尽时就整条跳过了。
## ★为什么不靠 `on_hit` 认击杀: on-hit 那一整块被 `u["alive"]` 挡着,
##   **致命的那一下根本走不到** ⇒ 只用触碰时间戳会漏掉"斧头自己打死的"这一半。
##   所以分两路: 击杀看 killer 是不是斧头, 助攻看死者身上的触碰时间戳。
## 返回是否发生了进化(调用方将来放演出用)。
func on_death(victim: Dictionary, killer) -> bool:
	if not (victim is Dictionary):
		return false
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("axe_add_exp"):
		return false
	var hit := false
	if killer is Dictionary and (killer as Dictionary).get("_eq_axe", false):
		hit = true                                   # 斧头亲手打死
	elif float(battle._t) - float(victim.get("_axe_touch_t", -9999.0)) <= AE.ASSIST_WINDOW:
		hit = true                                   # 3 秒内被斧头碰过 = 参与击杀
	if not hit:
		return false
	return bool(gs.axe_add_exp(AE.EXP_ON_KILL))
