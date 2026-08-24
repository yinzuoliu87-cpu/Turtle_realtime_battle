class_name FortuneSystem
extends RefCounted
## 财神龟技能系统
## 类内名不变;外部名加 battle.

## ★财神数值单一事实源(用户2026-07-28 第三轮加强·梭哈 8.4% 第83)。文案在 data/pets.json。
const ALLIN_SHIELD_SEC := 6.0   # 梭哈首发金盾持续秒数(不锁龟能·与变身后的金盾区分)
const LOWHP_PCT := 0.20          # 【通用被动·聚宝盆】: 首次跌破该血量比例触发(不论带哪个技能)
## 【聚宝盆】局内金币产出 + 低血一次性龟能。
const COIN_IV := 3.0             # 每几秒产一次金币
const COIN_MIN := 4              # 每次产出下限
const COIN_MAX := 7              # 每次产出上限
const COIN_ON_DEATH := 9         # 场上任意单位阵亡额外获得
const LOWHP_TRIGGER := 0.20      # 首次血量降到 × 最大生命 以下时触发
const LOWHP_ENERGY := 70.0       # 【通用被动·聚宝盆】: 触发时立得的龟能

var battle

func _init(b) -> void:
	battle = b

func _fortune_strike_fx(u: Dictionary, tgt: Dictionary) -> void:   # 财神金剑打击: 金色斩弧(随方向翻转)+目标迸金(复用斩弧染金·用户2026-07-12)
	var to_r: bool = tgt["pos"].x >= u["pos"].x
	var b = Sprite3D.new()
	b.texture = load("res://assets/sprites/vfx/diamond-slash.png")
	b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED; b.shaded = false; b.transparent = true
	b.modulate = Color(1.0, 0.82, 0.25, 0.95)                       # 金色(财神金剑)
	b.flip_h = not to_r
	var th = float(maxi(1, int(b.texture.get_height())))
	b.pixel_size = (80.0 * battle.WS) / th
	b.position = battle._world_pos(u["pos"].lerp(tgt["pos"], 0.7) + Vector2(0, -6), 0.7)
	battle._world.add_child(b)
	var t = battle._reg_tween()
	t.tween_property(b, "scale", Vector3.ONE, 0.08).from(Vector3(0.55, 0.55, 0.55)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.05)
	t.tween_property(b, "modulate:a", 0.0, 0.18)
	t.tween_callback(b.queue_free)
	battle._gold_chunk_erupt(tgt["pos"] + Vector2(8.0, -4.0))              # 目标迸金

func _sk_fortune_buyequip(u: Dictionary) -> void:              # 财神龟·招财进宝(封板·60龟能起): 首抽1件1/2/3费临时装备(1★·战后消失不占槽)→消耗变120/180/300(用户2026-07-29 第四轮·原160/240/460); 后续释放升1星(精确数值delta) → 3★后消耗回60且每次释放回复1×ATK生命
	var star: int = int(u.get("buyequip_star", 0))
	if star == 0:                                               # 首抽临时装备
		var iid: String = battle._chest_sys._chest_pick_equip([1, 2, 3])
		if iid == "": return
		if not u.has("equips"): u["equips"] = []
		u["equips"].append({"id": iid, "star": 1})
		battle._equip_sys._stats._eq_apply_one_stats(u, iid, 1)
		u["buyequip_id"] = iid; u["buyequip_star"] = 1
		var tier: int = int(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("cost", 1))
		u["energy_cost"]["fortuneBuyEquip"] = 60.0 + [60.0, 120.0, 240.0][clampi(tier - 1, 0, 2)]   # 消耗随抽到费拉长(用户2026-07-29 第四轮: 160/240/460 → 120/180/300)
		# ★注意这是【抽完之后】才改写 energy_cost —— 首次释放本身花的是 skill_energy 里的基准,
		#   实测 `skill_energy.gd` 的 "fortuneBuyEquip": **10.0**(2026-08-20 核对时发现本注释
		#   原来写的是 60, 与那张表对不上 —— 注释也是手抄的副本, 一样会漂)。
		#   我 2026-07-29 一度把这组数说成"首释价", 是错的; 它是【第2、3次(升星)】的价。
		battle._vfx._float_text(u["pos"] + Vector2(0, -72), "招财! " + str(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("name", iid)), Color("#ffd93d"))
	elif star >= 3:                                             # 3★满: 回复1×ATK生命
		battle._damage._heal(u, u["atk"])
		battle._vfx._float_text(u["pos"] + Vector2(0, -72), "招财·满! 回血", Color("#ffd93d"))
	else:                                                       # 升星: 应用精确数值delta(旧星→新星) + 同步equips条目星级
		var iid2: String = str(u.get("buyequip_id", ""))
		battle._equip_sys._stats._eq_star_delta_stats(u, iid2, star, star + 1)          # 精确升星: 加(新星-旧星)属性差量(flag类缩放留F5)
		for e in u.get("equips", []):                          # 同步equips条目(战后清理/信息面板显示星级一致)
			if str(e.get("id", "")) == iid2:
				e["star"] = star + 1
				break
		u["buyequip_star"] = star + 1
		if star + 1 >= 3: u["energy_cost"]["fortuneBuyEquip"] = 60.0   # 满星→价回60
		battle._vfx._float_text(u["pos"] + Vector2(0, -72), "招财·升星 %d★" % (star + 1), Color("#ffd93d"))
	battle._burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", u["pos"], 104.0, 0.7)   # 招财: 金币聚宝爆(用户2026-07-12)
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.6), 56.0)
	battle._refresh_panel_equips(u)   # ★抽到/升星的临时装备图标即时显进左右信息框(用户2026-07-12)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子(用户2026-07-12补特效): 掷骰5~8金币+回15%maxHP
	var g: int = randi_range(5, 8)   # 2~6→3~8→5~8 (用户2026-07-29 第五轮)
	u["gold"] += g
	battle._damage._heal(u, u["maxHp"] * 0.15)   # 骰子回血 8%→10%→15% 最大生命(用户2026-07-29 第五轮·财神实测33秒就死, 回血=活久点)
	battle._burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", u["pos"], 120.0, 0.75)   # 金币爆
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.55), 52.0)
	battle._vfx._float_text(u["pos"] + Vector2(0, -66), "掷骰 +%d金币" % g, Color("#ffd93d"))
	for _k in range(5):   # 金块从脚下冒出(聚财)
		battle._gold_chunk_erupt(u["pos"] + Vector2(randf_range(-30.0, 30.0), randf_range(-14.0, 14.0)))
	# (删: "放梭哈后给护盾"=4选1下死逻辑, 不可能同时有骰子+梭哈, 用户指出)

# 财神·梭哈: 一场限一次, 消耗全部金币, 每枚 0.30×ATK物理 + 0.30×ATK真实 (cd999·数值在 RealtimeBattle3DScene 的 coin_true/coin_phys)
const GOLD_SHIELD_MULT := 5.0   # 金盾盾量 = 金币数 × 这个倍率(用户 2026-08-01: 1 → 5)

func _sk_fortune_goldshield(u: Dictionary) -> void:   # 财神·金盾(梭哈用过后该技变身·用户2026-07-12): 80龟能·护盾=当前金币数×GOLD_SHIELD_MULT(5)(不消耗金币)·持盾期锁龟能(盾破/4s到期解锁)
	# ★盾量 = 金币数 ×5(用户 2026-08-01 拍板加强; 原来是 ×1)。
	#   背景: 修好"金盾压根没生效"之后, 梭哈这一路仍是全表倒数第 4(16.9%),
	#   而且"放技/场 1.99"是全表最低 —— 一场只放两次(梭哈限一次 + 金盾)。
	#   ★这一轮的胜率数据【不含】本次加强(金盾在那轮还是刚修好的 ×1)。
	var amt: float = float(int(u.get("gold", 0))) * GOLD_SHIELD_MULT
	if amt <= 0.0:
		return
	battle._damage._grant_shield(u, amt, 4.0)                 # 通用护盾4s
	u["gold_shield_until"] = battle._t + 4.0          # 持盾期锁龟能(与shield同4s·盾破/到期即恢复·同钻石坚不可摧节奏)
	battle._vfx._flash(u, Color(1.6, 1.35, 0.5))
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.7), 60.0)
	battle._vfx._float_text(u["pos"] + Vector2(0, -66), "金盾 +%d" % int(amt), Color("#ffd93d"))
	for _k in range(4):                        # 金块绕身聚成盾
		battle._gold_chunk_erupt(u["pos"] + Vector2(randf_range(-26.0, 26.0), randf_range(-12.0, 12.0)))

## 财神【通用被动】(用户2026-07-28: 原定为梭哈打包, 同日改为通用 ——
## 「改为财神的通用被动吧: 当首次血量降低至20%以下时, 立即获得70龟能」)
## 不论带哪个技能都生效, 所以不走 _chosen_skill_types 绑定, 直接在受伤钩子里认龟 id。
##
## ★龟能是【逐技冷却】不是累加值(SkillEnergy.CD_FACTOR=0.075) → "得70龟能" = 各技冷却各减 70×0.075=5.25 秒。
##   同一换算见 _tick_skill_cd 的 init_energy_bonus、天使飞升的 _ascend_growth_tick。
## ★只触发一次: u["_lowhp_fired"] 标记(读者在 battle_damage.gd 的 HP 阈值钩)。触发点在 battle_damage._apply_damage_from 的 HP 阈值钩里,
##   与装备的"首次<50%"同处 —— 那里是每次受伤后【无条件】查的, 不会漏掉某条伤害路径
##   (本项目有两条独立伤害路径 _apply_damage / _apply_damage_from, 各自扣血)。
func _fortune_lowhp_burst(u: Dictionary) -> void:
	u["_lowhp_fired"] = true
	var cds: Dictionary = u.get("skill_cd", {})
	var d: float = LOWHP_ENERGY * battle.SkillEnergy.CD_FACTOR
	for k in cds:
		cds[k] = maxf(0.0, float(cds[k]) - d)
	battle._vfx._float_text(u["pos"] + Vector2(0, -70), "龟能 +%d" % int(LOWHP_ENERGY), Color("#ffd93d"))
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.7), 58.0)

func _sk_fortune_allin(u: Dictionary, tgt) -> void:                 # 财神龟·梭哈 ✅ (蓄力→持续投金币, 目标死换下个; 用过后该技变金盾)
	if tgt == null or u.get("allin_used", false):
		return
	u["allin_used"] = true
	u["energy_cost"]["fortuneAllIn"] = 80.0    # ★梭哈后该技变「金盾」→ 龟能消耗 340→80(用户2026-07-12)
	var coins: int = int(u["gold"])
	u["gold"] = 0.0
	if coins <= 0:
		return
	u["allin_coins"] = coins              # 待投金币数 = 全部金币
	u["allin_throw_t"] = 0.6              # 蓄力(首投前)
	u["allin_target"] = tgt
	# 用户2026-07-28 加强: 首次梭哈【同时】按当时金币数给金盾 + 投币全程免控。
	#   原设计梭哈只投币不给盾(盾要等技能变身后再花 80 龟能), 而投币期还会被眩晕/击飞打断 ——
	#   实测 8.4%(第83/84)、释放仅 1.3 次/场。金盾这里【不锁龟能】(与变身后的金盾不同):
	#   梭哈一场限一次, 放完就只剩金盾可放, 再锁龟能等于自断后路。
	battle._damage._grant_shield(u, float(coins), ALLIN_SHIELD_SEC)
	battle._vfx._float_text(u["pos"] + Vector2(0, -66), "金盾 +%d" % coins, Color("#ffd93d"))
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.65), 66.0)   # 蓄力金环
	battle._vfx._flash(u, Color(1.5, 1.3, 0.6))

# 梭哈 channel: 蓄力后每隔投币间隔朝目标投1金币(0.30ATK物+0.30ATK真), 目标死换最近敌; 投完结束; 眩晕/击飞期暂停
func _fortune_allin_channel(u: Dictionary, delta: float) -> void:
	# 投币期免控(用户2026-07-28): 每帧把免控窗口往后续一点 —— 投完(allin_coins 归零后不再进本函数)
	# 窗口自然到期。原先这里是"被眩晕就 return 暂停投币", 现在根本不会被眩晕。
	u["cc_immune_until"] = battle._t + 0.5
	u["allin_throw_t"] = float(u.get("allin_throw_t", 0.0)) - delta
	if u["allin_throw_t"] > 0.0:
		return
	var tgt = u.get("allin_target", null)
	if tgt == null or not tgt.get("alive", false):
		tgt = battle._targeting._nearest_enemy(u)
		u["allin_target"] = tgt
	if tgt == null:
		u["allin_coins"] = 0
		return
	battle._throw_gold_coin(u, tgt)
	u["allin_coins"] = int(u["allin_coins"]) - 1
	u["allin_throw_t"] = 0.11
	if int(u["allin_coins"]) <= 0:
		u["allin_target"] = null

# 投1枚金币弹道 (命中→0.30ATK物理+0.30ATK真实)
