class_name FortuneSystem
extends RefCounted
## 财神龟技能系统
## 类内名不变;外部名加 battle.

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

func _sk_fortune_buyequip(u: Dictionary) -> void:              # 财神龟·招财进宝(封板·60龟能起): 首抽1件1/2/3费临时装备(1★·战后消失不占槽)→消耗变160/240/460; 后续释放升1星(精确数值delta) → 3★后消耗回60且每次释放回复1×ATK生命
	var star: int = int(u.get("buyequip_star", 0))
	if star == 0:                                               # 首抽临时装备
		var iid: String = battle._chest_sys._chest_pick_equip([1, 2, 3])
		if iid == "": return
		if not u.has("equips"): u["equips"] = []
		u["equips"].append({"id": iid, "star": 1})
		battle._equip_sys._eq_apply_one_stats(u, iid, 1)
		u["buyequip_id"] = iid; u["buyequip_star"] = 1
		var tier: int = int(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("cost", 1))
		u["energy_cost"]["fortuneBuyEquip"] = 60.0 + [100.0, 180.0, 400.0][clampi(tier - 1, 0, 2)]   # 消耗随抽到费拉长
		battle._float_text(u["pos"] + Vector2(0, -72), "招财! " + str(DataRegistry.phase2_equipment_by_id.get(iid, {}).get("name", iid)), Color("#ffd93d"))
	elif star >= 3:                                             # 3★满: 回复1×ATK生命
		battle._heal(u, u["atk"])
		battle._float_text(u["pos"] + Vector2(0, -72), "招财·满! 回血", Color("#ffd93d"))
	else:                                                       # 升星: 应用精确数值delta(旧星→新星) + 同步equips条目星级
		var iid2: String = str(u.get("buyequip_id", ""))
		battle._equip_sys._eq_star_delta_stats(u, iid2, star, star + 1)          # 精确升星: 加(新星-旧星)属性差量(flag类缩放留F5)
		for e in u.get("equips", []):                          # 同步equips条目(战后清理/信息面板显示星级一致)
			if str(e.get("id", "")) == iid2:
				e["star"] = star + 1
				break
		u["buyequip_star"] = star + 1
		if star + 1 >= 3: u["energy_cost"]["fortuneBuyEquip"] = 60.0   # 满星→价回60
		battle._float_text(u["pos"] + Vector2(0, -72), "招财·升星 %d★" % (star + 1), Color("#ffd93d"))
	battle._burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", u["pos"], 104.0, 0.7)   # 招财: 金币聚宝爆(用户2026-07-12)
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.6), 56.0)
	battle._refresh_panel_equips(u)   # ★抽到/升星的临时装备图标即时显进左右信息框(用户2026-07-12)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子(用户2026-07-12补特效): 掷骰3~8金币+回8%maxHP
	var g: int = randi_range(3, 8)   # 2~6→3~8 (恢复文本设计值)
	u["gold"] += g
	battle._heal(u, u["maxHp"] * 0.08)
	battle._burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", u["pos"], 120.0, 0.75)   # 金币爆
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.55), 52.0)
	battle._float_text(u["pos"] + Vector2(0, -66), "掷骰 +%d金币" % g, Color("#ffd93d"))
	for _k in range(5):   # 金块从脚下冒出(聚财)
		battle._gold_chunk_erupt(u["pos"] + Vector2(randf_range(-30.0, 30.0), randf_range(-14.0, 14.0)))
	# (删: "放梭哈后给护盾"=4选1下死逻辑, 不可能同时有骰子+梭哈, 用户指出)

# 财神·梭哈: 一场限一次, 消耗全部金币, 每枚 0.18×ATK物理 + 0.18×ATK真实 (cd999)
func _sk_fortune_goldshield(u: Dictionary) -> void:   # 财神·金盾(梭哈用过后该技变身·用户2026-07-12): 80龟能·护盾=当前金币数(不消耗金币)·持盾期锁龟能(盾破/4s到期解锁)
	var amt: float = float(int(u.get("gold", 0)))
	if amt <= 0.0:
		return
	battle._grant_shield(u, amt, 4.0)                 # 通用护盾4s
	u["gold_shield_until"] = battle._t + 4.0          # 持盾期锁龟能(与shield同4s·盾破/到期即恢复·同钻石坚不可摧节奏)
	battle._flash(u, Color(1.6, 1.35, 0.5))
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.7), 60.0)
	battle._float_text(u["pos"] + Vector2(0, -66), "金盾 +%d" % int(amt), Color("#ffd93d"))
	for _k in range(4):                        # 金块绕身聚成盾
		battle._gold_chunk_erupt(u["pos"] + Vector2(randf_range(-26.0, 26.0), randf_range(-12.0, 12.0)))

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
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.2, 0.65), 66.0)   # 蓄力金环
	battle._flash(u, Color(1.5, 1.3, 0.6))

# 梭哈 channel: 蓄力后每隔投币间隔朝目标投1金币(0.18ATK物+0.18ATK真), 目标死换最近敌; 投完结束; 眩晕/击飞期暂停
# 梭哈 channel: 蓄力后每隔投币间隔朝目标投1金币(0.18ATK物+0.18ATK真), 目标死换最近敌; 投完结束; 眩晕/击飞期暂停
func _fortune_allin_channel(u: Dictionary, delta: float) -> void:
	if battle._t < float(u.get("stun_until", 0.0)):
		return
	u["allin_throw_t"] = float(u.get("allin_throw_t", 0.0)) - delta
	if u["allin_throw_t"] > 0.0:
		return
	var tgt = u.get("allin_target", null)
	if tgt == null or not tgt.get("alive", false):
		tgt = battle._nearest_enemy(u)
		u["allin_target"] = tgt
	if tgt == null:
		u["allin_coins"] = 0
		return
	battle._throw_gold_coin(u, tgt)
	u["allin_coins"] = int(u["allin_coins"]) - 1
	u["allin_throw_t"] = 0.11
	if int(u["allin_coins"]) <= 0:
		u["allin_target"] = null

# 投1枚金币弹道 (命中→0.18ATK物理+0.18ATK真实)
