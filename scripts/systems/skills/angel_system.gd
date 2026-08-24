class_name AngelSystem
extends RefCounted
## 天使龟技能系统
## 类内名不变;外部名加 battle.

## ★天使数值单一事实源(用户2026-07-28 第三轮加强·祝福 14.5% 第76)。文案在 data/pets.json。
const BLESS_SHIELD := 2.5   # 祝福: 护盾 = ×ATK (1.2→2.5)
## 【祝福】给当前输出最高的友军: 盾 + 攻速, 同一时长; 打包被动是自身首死复活。
const BLESS_SEC := 5.0      # 盾与攻速的持续(秒)
const BLESS_HASTE := 0.50   # 攻速 +
const REVIVE_HP_PCT := 0.25 # 打包被动: 首次死亡以 ×最大生命 复活一次
## 【平等】多段圣光斩弧, 目标够稀有则追加一发真伤审判。
const EQUAL_SEGMENTS := 4   # 几段
const EQUAL_SEG_COEF := 0.5 # 每段 ×ATK 物理
const EQUAL_SEG_GAP := 0.10 # 段间隔(秒)
const EQUAL_LIFESTEAL := 0.10   # 本次施法附带生命偷取
const EQUAL_JUDGE_COEF := 0.5   # 追加审判 ×ATK 真实
const EQUAL_JUDGE_LOST := 0.10  # + 目标【已损】生命 ×
const ASCEND_ENERGY_PER_HIT := 5.0   # 飞升打包被动: 每次普攻命中给自己的龟能
const ASCEND_ATK_PER_HIT := 0.01     # 飞升打包被动: 每次普攻命中 +1% 攻击力(乘算·持续到战斗结束)

var battle

func _init(b) -> void:
	battle = b

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	# 用户2026-07-28: 「最低血友军」→「当前输出最高的友军」(原设定实测里几乎总是喂给陪跑小将)
	var ally = battle._targeting._top_dps_ally(u)
	if ally == null:
		ally = u
	battle._damage._grant_shield(ally, u["atk"] * BLESS_SHIELD, BLESS_SEC)   # 天使祝福护盾5秒(封板L145·与攻速/龟能buff同步)
	ally["haste_until"] = battle._t + BLESS_SEC; ally["haste_mult"] = 1.0 + BLESS_HASTE       # +50% 攻速 5秒(用户2026-07-11: 30%→50%)
	battle._skill_ring(ally["pos"], Color(1.0, 0.9, 0.5, 0.5), 48.0)   # 祝福: 金色圣光环 (用户2026-07-11: 取消原龟能充能+30%buff)

## 飞升·打包被动 (用户2026-07-28「天使龟的每次攻击还会为自己提供5点龟能和1%攻击力, 持续到战斗结束」)
##
## ★龟能在实时版【不是累加值, 是逐技冷却】(SkillEnergy.CD_FACTOR=0.075 → 充能秒数 = 龟能×0.075),
##   所以"给5点龟能" = 把每个技能的剩余冷却各减 5×0.075 = 0.375 秒。
##   同一换算见 _tick_skill_cd 里装备的 init_energy_bonus。别写成 u["energy"] += 5 —— 没有那个字段。
## ★攻击力走 base_atk 乘算后 _recalc_stats: 与飞升主动的 aspd_perm 同一套"永久成长"写法,
##   直接改 u["atk"] 会被下一次 _recalc_stats 覆盖掉。
func _ascend_growth_tick(u: Dictionary) -> void:
	var cds: Dictionary = u.get("skill_cd", {})
	var d: float = ASCEND_ENERGY_PER_HIT * battle.SkillEnergy.CD_FACTOR
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - d)
	u["base_atk"] = float(u["base_atk"]) * (1.0 + ASCEND_ATK_PER_HIT)
	battle._recalc_stats(u)

func _sk_angel_ascend(u: Dictionary) -> void:                   # 天使龟·飞升 (用户2026-07-06: +20%攻速+25码射程·到战斗结束·可叠加无上限; 移速2026-07-11改+5%)
	u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) * 1.2       # +20%攻速(永久·叠加)
	u["move_spd"] = float(u["move_spd"]) * 1.05                 # +5%移速(永久·叠加·用户2026-07-11: 10%→5%)
	u["atk_range"] = float(u["atk_range"]) + 25.0              # +25码射程(永久·叠加)
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 88.0, Color(1.0, 0.92, 0.55, 0.62), 2.4)   # 金光飞升圣环(施法瞬间圣环渐亮)

# 天使龟·平等 ✅ (封板2026-07-06 选A远程投射·60龟能): 站原地射4道圣光斩弧各50%ATK·合计200%物理·带10%施法吸血; 目标A级及以上追加从天而降审判光柱=(50%ATK+目标已损生命10%)真伤·无视双抗·同10%吸血
func _sk_angel_equality(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	battle._vfx._flash(u, Color(1.0, 0.92, 0.6))                            # 举裁蓄力·自身泛淡金吸血光
	var order = {"C": 0, "B": 1, "A": 2, "S": 3, "SS": 4, "SSS": 5}
	# 4道圣光斩弧(远程投射·站原地不突进): 各50%ATK物理·共200%(2ATK)·带10%施法吸血(用户2026-07-11:2道100%→4道50%)
	for i in range(EQUAL_SEGMENTS):
		battle._pending_shots.append({"delay": EQUAL_SEG_GAP * float(i), "src": u, "fn": func():
			if tgt == null or not tgt.get("alive", false): return
			battle._bolt_line(u["pos"], tgt["pos"], Color(1.0, 0.92, 0.66))      # 金白斩弧曳光
			battle._skill_ring(tgt["pos"], Color(1.0, 0.9, 0.6, 0.5), 44.0)
			battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, EQUAL_SEG_COEF, tgt, false), Color("#ffe9a8"), EQUAL_LIFESTEAL)   # 单道50%物理(4道合计200%)·10%吸血
			battle._damage._apply_damage_from(u, tgt, battle._mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 审判(每段攻击命中都吃·独立结算不触发其他被动·用户2026-07-10"每次攻击都要吃")
		})
	# A级及以上→第3段从天而降审判光柱: (50%ATK + 目标已损生命10%)真伤·无视双抗·同10%吸血
	if int(order.get(str(tgt.get("rarity", "C")), 0)) >= 2:
		battle._pending_shots.append({"delay": 0.42, "src": u, "fn": func():
			if tgt == null or not tgt.get("alive", false): return
			_angel_judgment_pillar(tgt["pos"])
			var lost: float = maxf(0.0, float(tgt["maxHp"]) - float(tgt["hp"]))
			var tru: int = maxi(1, int(float(u["atk"]) * EQUAL_JUDGE_COEF + lost * EQUAL_JUDGE_LOST))
			battle._damage._apply_damage_from(u, tgt, tru, Color(1.0, 0.96, 0.76), 0.10, true)   # 真伤无视双抗·10%吸血
			battle._damage._apply_damage_from(u, tgt, battle._mitigate(u, tgt["hp"] * 0.08, tgt, true), Color("#9be7ff"), 0.0, false)   # 光柱也带审判(用户2026-07-11:附带被动·8%当前HP·与上面每段斩弧同一系数)
			battle._vfx._flash(tgt, Color(1.0, 0.96, 0.76))
		})

# 天使审判光柱: 从天而降金白光束(强闪骤降) + 命中金环 (平等第3段·A级以上)
# 天使审判光柱: 从天而降金白光束(强闪骤降) + 命中金环 (平等第3段·A级以上)
func _angel_judgment_pillar(pos2d: Vector2) -> void:
	battle._skill_ring(pos2d, Color(1.0, 0.9, 0.5, 0.85), 70.0)
	var pil = Sprite3D.new()
	pil.texture = VfxTex._make_fire_glow_tex()
	pil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pil.shaded = false; pil.transparent = true
	pil.pixel_size = 0.013
	pil.modulate = Color(1.0, 0.96, 0.7, 0.0)
	pil.scale = Vector3(0.5, 3.0, 1.0)
	pil.position = battle._world_pos(pos2d, 2.4)                       # 高空起
	battle._world.add_child(pil)
	var tp = battle._reg_tween(); tp.set_parallel(true)
	tp.tween_property(pil, "modulate:a", 0.95, 0.08)           # 骤降强闪
	tp.tween_property(pil, "position", battle._world_pos(pos2d, 0.7), 0.14)
	tp.chain().tween_property(pil, "modulate:a", 0.0, 0.22)
	tp.chain().tween_callback(pil.queue_free)
