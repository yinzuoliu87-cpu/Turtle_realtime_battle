class_name ChestSystem
extends RefCounted
## 宝箱龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# 宝箱·藏宝图(封板L590-594·完整15件专属池): 造成伤害积累财宝值, 过阈值开专属战利品(分档池·不重复)+回血, 一大轮最多5件
func _chest_treasure_tick(u: Dictionary) -> void:
	# 大轮制(用户2026-07-16): 财宝值跨场累积·阈值3000/6000/10000/18000/30000(用户2026-08-14上调)·开出=一大轮常驻
	## ★2026-08-15 起【敌我同一套阈值】(用户拍板 A)。
	##   原来敌侧走的是"单场旧制": 一套比我方低 12~50 倍的阈值,
	##   于是对面那只宝箱龟在一场里就能开满 5 件传说, 而我方要跨大轮攒 30000。
	##   根因查清楚了: 敌方 = 真人玩家的 ghost 快照, 带了龟/装备/等级, **唯独宝箱进度一件不带**,
	##   代码就用这套低阈值去"补偿"——等于凭空编一个假对手。
	##   现在快照带上真实进度(backend.SCHEMA_VER = 2), 敌方按对手【真的攒到哪】走同一套阈值。
	## ★2026-10-22 起财宝值 / 已开数只从 `treasure_progress` 取(本场宝箱账, 见下方那一节):
	##   原来这里分三支各算各的 —— 我方读存档并在这里补记、敌方读单位字典上的快照基数 + 本路 dmg_dealt,
	##   于是敌方换路就丢进度(B)、持续伤害不计(F)、阵亡后的几跳漏记(G)。
	var tp: Dictionary = treasure_progress(u)
	var opened: int = int(tp["opened"])
	if opened >= CHEST_MAX_OPEN:
		return
	if float(tp["value"]) < float(battle._CHEST_THRESH[opened]):
		return
	if _per_unit(u):
		u["chest_opened"] = opened + 1
	var group: String = ["basic", "basic", "adv", "adv", "legend"][opened]   # 第1-2箱基础/3-4进阶/5传说
	var heal_pct: float = CHEST_HEAL_PCT[opened]
	var tid: String = _chest_pick_treasure(u, group)
	if tid != "":
		_chest_apply_treasure(u, tid)
		if u.get("chest_greed", false): _chest_greed_apply(u, 1)   # 贪婪: 新开1件→+4%攻+7%最大生命
		_ledger_note_open(u, tid)                                  # 记进本场宝箱账(计分对局的我方同时写存档并当场落盘)
		battle._vfx._float_text(u["pos"] + Vector2(0, -72), "开箱 " + str(battle._CHEST_TREASURE_NAME.get(tid, tid)), Color("#ffd93d"))
		var ipath: String = "res://assets/sprites/equip/chest-t-%s.png" % tid   # 头顶弹出战利品图标(用户2026-07-15: 看清开了什么)
		if ResourceLoader.exists(ipath):
			var ic = Sprite3D.new()
			ic.texture = load(ipath)
			ic.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ic.shaded = false; ic.transparent = true
			ic.pixel_size = (44.0 * battle.WS) / 32.0
			ic.modulate = Color(1, 1, 1, 0.0)
			ic.position = battle._world_pos(u["pos"], 2.3)
			battle._world.add_child(ic)
			var it = battle._reg_tween()
			it.tween_property(ic, "modulate:a", 1.0, 0.12)
			it.parallel().tween_property(ic, "scale", Vector3(1.25, 1.25, 1.25), 0.25).from(Vector3(0.5, 0.5, 0.5)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			it.tween_interval(0.9)
			it.tween_property(ic, "position", battle._world_pos(u["pos"], 2.9), 0.3)
			it.parallel().tween_property(ic, "modulate:a", 0.0, 0.3)
			it.tween_callback(ic.queue_free)
	battle._damage._heal(u, u["maxHp"] * heal_pct)
	battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.5), 52.0)


## ══════════════════════════════════════════════════════════════════════
##  本场宝箱账(2026-10-22 · 修 B/C/D/E/F/G)
## ══════════════════════════════════════════════════════════════════════
## 按【左右两侧】各记一本, 挂在本系统(= 这一场战斗)上, 不挂单位字典 ⇒ 换路重建单位字典也不丢。
##   base_value / base_won : 起点。左方 = 存档(GameState), 右方 = 对手快照(dual_ghost);
##                           开发工具场(调试场 / 特效台 / 地图编辑器)= 0 / 空 —— 沙盒, 不读也不写真存档(E)。
##   gain / won            : 这一场累计的财宝增量 / 这一场开出的战利品(按开出顺序)。
##   write                 : 这一本要不要同步写存档 —— 只有【计分对局的左方】(`_is_scored_match`, E)。
## 进账发生在【伤害落地那一刻】(battle_damage 两条伤害路各一处, CLAUDE.md §3.3):
##   持续伤害也算(F, 用户 2026-10-22「算」); 宝箱龟阵亡后风暴余下几跳照样进账(G, 原来靠存活时的逐帧同步, 死了就漏)。
##   ★口径与原来的 dmg_dealt 相同(减伤后、护盾前的那个数), 只是多了持续伤害这条路; dmg_dealt 本身不动。
## 评审台 / 召唤物不进这本账(`_per_unit`): 没有大轮进度可言, 走单位自己身上的 `_chest_gain` / `chest_opened`。
var _ledger: Dictionary = {}


## 评审台的假人 / 召唤物: 各算各的单场进度(单位字典上), 不碰两侧的账。
func _per_unit(u: Dictionary) -> bool:
	return battle._review_demo() or bool(u.get("is_summon", false))


func _ledger_of(side: String) -> Dictionary:
	if not _ledger.has(side):
		_ledger[side] = _ledger_start(side)
	return _ledger[side]


## 一本账的起点。★只读不写 —— `ledger_final` 在这一侧没开过账时也拿它当答案。
func _ledger_start(side: String) -> Dictionary:
	var bv := 0.0
	var bw: Array = []
	var carries: bool = GameState != null and not battle._world_builder._is_dev_tool_battle()
	if carries and side == "left":
		bv = _num(GameState.chest_treasure_value)
		bw = _str_list(GameState.chest_treasures_won)
	elif carries and side == "right":
		var gh = GameState.dual_ghost
		if gh is Dictionary:
			bv = _num((gh as Dictionary).get("chest_treasure_value", 0.0))
			bw = _str_list((gh as Dictionary).get("chest_treasures_won", []))
	var write: bool = carries and side == "left" and battle._world_builder._is_scored_match()
	return {"base_value": bv, "base_won": bw, "gain": 0.0, "won": [], "write": write}


static func _num(v) -> float:
	return float(v) if (v is int or v is float) else 0.0


static func _str_list(v) -> Array:
	var out: Array = []
	if v is Array:
		for t in v:
			out.append(str(t))
	return out


## ★取数口(唯一): 这只宝箱龟【此刻】的财宝值与已开箱数 {"value": float, "opened": int}。
##   开箱判据(`_chest_treasure_tick`)/ 清点财宝治疗加成(`_sk_chest_inventory`)/ 详情面板财宝条(info_panel)三处都读它,
##   原来三处各取各的(敌方面板读本路 dmg_dealt、清点财宝敌方不读快照基数 —— C / D 就是这么来的)。
func treasure_progress(u: Dictionary) -> Dictionary:
	if _per_unit(u):
		return {"value": _num(u.get("_chest_gain", 0.0)), "opened": int(u.get("chest_opened", 0))}
	var lg: Dictionary = _ledger_of(str(u.get("side", "")))
	return {"value": float(lg["base_value"]) + float(lg["gain"]),
		"opened": (lg["base_won"] as Array).size() + (lg["won"] as Array).size()}


## 伤害进账。调用方(battle_damage 两条伤害路)已判过: 来源是宝箱龟、打的不是自己。
func note_damage(src: Dictionary, dmg: int) -> void:
	if dmg <= 0:
		return
	if _per_unit(src):
		src["_chest_gain"] = _num(src.get("_chest_gain", 0.0)) + float(dmg)
		return
	var lg: Dictionary = _ledger_of(str(src.get("side", "")))
	lg["gain"] = float(lg["gain"]) + float(dmg)
	if bool(lg["write"]):
		GameState.chest_treasure_value = _num(GameState.chest_treasure_value) + float(dmg)


## 开出一件: 记进账; 计分对局的左方同时写存档并当场落盘(大轮常驻装备, 用户 2026-07-16 · 防闪退丢件)。
func _ledger_note_open(u: Dictionary, tid: String) -> void:
	if _per_unit(u):
		return
	var lg: Dictionary = _ledger_of(str(u.get("side", "")))
	(lg["won"] as Array).append(tid)
	if bool(lg["write"]):
		GameState.chest_treasures_won.append(tid)
		GameState.save()


## 登场时要回装的战利品 = 起点那几件 + 这一场前几路已开出的(B: 敌方原来换路就丢)。评审台 / 召唤物没有。
func spawn_loot(u: Dictionary) -> Array:
	if _per_unit(u):
		return []
	var lg: Dictionary = _ledger_of(str(u.get("side", "")))
	var out: Array = (lg["base_won"] as Array).duplicate()
	out.append_array(lg["won"])
	return out


## 调试场每次「▶开始」= 一场新的战斗: 账从头记(否则上一次试打开出的件会被装到下一次)。
func reset_ledger() -> void:
	_ledger.clear()


## ★给裁判结果单 / 回写存档的取数口(纯读, 不改任何状态): 某一侧【这一局此刻】的累计财宝值 + 已开战利品。
##   形状与存档 / 快照里那两个字段同名同型: {"chest_treasure_value": float, "chest_treasures_won": Array[String]}。
##   这一侧这局一只宝箱龟都没出场 ⇒ 原样返回起点(左 = GameState 里的, 右 = 对手快照里的)。
##   ⚠ 要在战斗场释放之前读; 裁判跑局(RefereeRunner.run)结束时会把 GameState 还原, 那之后起点就不是这一局的了。
func ledger_final(side: String = "left") -> Dictionary:
	var lg: Dictionary = _ledger[side] if _ledger.has(side) else _ledger_start(side)
	var won: Array = (lg["base_won"] as Array).duplicate()
	won.append_array(lg["won"])
	return {"chest_treasure_value": float(lg["base_value"]) + float(lg["gain"]), "chest_treasures_won": won}

func _chest_pick_treasure(u: Dictionary, group: String) -> String:   # 该档随机1件(不重复)·档抽光→退回全池任意未拥有
	var owned: Dictionary = u.get("chest_treasures", {})
	var avail: Array = []
	for tid in battle._CHEST_TREASURE_POOL.get(group, []):
		if not owned.has(tid): avail.append(tid)
	if avail.is_empty():
		for g in ["basic", "adv", "legend"]:
			for tid in battle._CHEST_TREASURE_POOL[g]:
				if not owned.has(tid): avail.append(tid)
	if avail.is_empty(): return ""
	return str(avail[battle._battle_rng.randi() % avail.size()])

## 战利品数值(用户 2026-08-14 调整) —— 集中在这里, 别散在各自的钩子里。
## ★消费点在别处(battle_damage / RealtimeBattle3DScene 的周期 tick), 但**数值只有这一份**,
##   否则就是"手抄的副本必然落后"。
const RUM_HEAL_PCT := 0.005     # 朗姆酒: 每秒回 0.5% 最大生命(原每 10 秒 8%)
const GEM_HP := 500.0           # 宝石甲: +500 最大生命(原 +60)
## 2026-10-22 其余战利品的数也收进来: 原来写在 _chest_apply_treasure / battle_damage 的字面量里,
##   说明(ChestLoot.DESC)只能手抄 —— 手抄的那份已经漂了(星辉 08-14 收窄成只算攻击和技能, 说明还写「所有伤害」)。
const DAGGER_ATK := 0.25        # 短刃: 攻击力 +25%
const WOOD_RES := 0.20          # 木盾: 护甲与魔抗 +20%
const DICE_CRIT := 0.35         # 血筛子: 暴击率 +35%
const CHAIN_AOE_UP := 1.0       # 锁链: 宝箱砸击的长度与宽度 +100%
const STONE_RES_COEF := 1.0     # 石头: 宝箱砸击额外 +(护甲 + 魔抗)×
const SWORD_ATK := 0.45         # 长剑: 攻击力 +45%
const BLADE_LS := 0.25          # 嗜血之刃: 生命偷取 +25%
const GEM_RES := 0.25           # 宝石甲: 护甲与魔抗 +25%
const POISON_CUT := 0.5         # 毒箭: 治疗削减
const POISON_SEC := 5.0         # 毒箭: 持续秒
const CROWN_ATK := 0.40         # 王冠: 攻击力 +40%
const CROWN_CRIT := 0.40        # 王冠: 暴击率 +40%
const CROWN_CRIT_DMG := 0.25    # 王冠: 暴击伤害 +25%
const CROWN_LS := 0.15          # 王冠: 生命偷取 +15%
const THUNDER_STACKS := 5       # 雷刃: 叠满几层引爆
const THUNDER_ATK_COEF := 1.0   # 雷刃: 引爆 ×ATK 真实伤害
## 【财宝风暴】以目标为心的圆形风暴, 逐跳结算。
const STORM_RADIUS := 400.0     # 半径(码)
const STORM_TICKS := 5          # 共几跳
const STORM_TICK_SEC := 0.5     # 每几秒一跳
const STORM_ATK_COEF := 0.2     # 每跳 ×ATK 物理
const STORM_LIFE := STORM_TICKS * STORM_TICK_SEC   # 总时长(推导, 文案里那个 2.5 秒)
const STORM_TOTAL_COEF := STORM_ATK_COEF * STORM_TICKS   # 推导: 全部跳完合计 ×ATK(文案那个 100%)
## 【藏宝图】开箱后额外回复的最大生命比例(逐箱)。阈值在主场景 `_CHEST_THRESH`。
## 【清点财宝】回血(吃财宝加成) + 护盾(不吃加成)。
## 【财宝炮击】一条直线的长激光; 打包被动【贪婪】按携带装备数永久涨属性。
const CANNON_COEF := 3.0       # 线上每敌 ×ATK 物理
const GREED_ATK_PER_EQ := 0.04 # 每件装备永久 + 攻击力 ×(基础值)
const GREED_HP_PER_EQ := 0.07  # 每件装备永久 + 最大生命 ×
## 专属战利品池的总件数。★不是手抄: `tests/verify_chest_treasures.gd` 逐件遍历
##   `_CHEST_TREASURE_POOL` 并断言"件数 == 本常量", 池子增删一件那条测试立刻红。
const TREASURE_TOTAL := 15
const CHEST_MAX_OPEN := 5      # 一大轮最多开几件(第 1-2 基础 / 3-4 进阶 / 5 传说)
const COUNT_HEAL_PCT := 0.05     # 回复 = 自身最大生命 ×
const COUNT_SHIELD_COEF := 0.6   # 护盾 = ×ATK(不吃财宝加成)
const COUNT_PER_TREASURE := 1000.0  # 每这么多财宝值
const COUNT_HEAL_BONUS := 0.10      # 治疗效果就 +
const CHEST_HEAL_PCT := [0.08, 0.08, 0.11, 0.11, 0.15]
const FLINT_BURN_COEF := 0.05   # 火石: 命中给 0.05×ATK 层灼烧(原 0.1)


func _chest_apply_treasure(u: Dictionary, tid: String) -> void:   # 逐件bespoke效果(属性即时应用·机制类置flag由钩子读)
	if not u.has("chest_treasures"): u["chest_treasures"] = {}
	u["chest_treasures"][tid] = true
	match tid:
		"dagger":         battle._damage._buff(u, "atk", DAGGER_ATK, true, 99999.0)                                              # 短刃: +25%攻
		"wood_shield":    battle._damage._buff(u, "def", WOOD_RES, true, 99999.0); battle._damage._buff(u, "mr", WOOD_RES, true, 99999.0)          # 木盾: +20%双抗
		"rum":            u["chest_rum_t"] = 0.0                                                             # 朗姆酒: 每秒回 RUM_HEAL_PCT(0.5%) maxHp(周期tick读flag)
		"blood_dice":     u["crit"] = float(u.get("crit", 0.0)) + DICE_CRIT                                       # 血筛子: +35%暴击
		"chain":          u["chest_aoe_mult"] = 1.0 + CHAIN_AOE_UP                                                          # 锁链: 砸击AOE距离/射程翻倍(_chest_basic钩子)
		"stone":          u["chest_rock_bonus"] = float(u.get("chest_rock_bonus", 0.0)) + STONE_RES_COEF                # 石头: 砸击额外+100%护甲+100%魔抗(_chest_basic钩子)
		"long_sword":     battle._damage._buff(u, "atk", SWORD_ATK, true, 99999.0)                                               # 长剑: +45%攻
		"bloodblade":     u["lifesteal"] = float(u.get("lifesteal", 0.0)) + BLADE_LS                             # 嗜血之刃: +25%吸血
		"flint":          pass                                                                               # 火石: 命中→灼烧(_apply_damage_from钩子·防循环)
		"gem_armor":      battle._damage._buff(u, "def", GEM_RES, true, 99999.0); battle._damage._buff(u, "mr", GEM_RES, true, 99999.0); u["maxHp"] += GEM_HP; u["hp"] += GEM_HP   # 宝石甲: +25%双抗 + GEM_HP(500)血
		"poison":         pass                                                                               # 毒箭: 命中→治疗削减-50%5秒(_apply_damage_from钩子·防循环)
		"phoenix_statue": u["_chest_revive"] = true                                                          # 凤凰雕像: 首死25%最大生命复活(_kill钩子)
		"crown":          battle._damage._buff(u, "atk", CROWN_ATK, true, 99999.0); u["crit"] = float(u.get("crit", 0.0)) + CROWN_CRIT; u["crit_dmg"] = float(u.get("crit_dmg", 1.5)) + CROWN_CRIT_DMG; u["lifesteal"] = float(u.get("lifesteal", 0.0)) + CROWN_LS   # 王冠: +40攻/+40暴/+25爆伤/+15吸血
		"thunder":        pass                                                                               # 雷刃: 命中叠金闪电满5引爆1.0A真伤(_apply_damage_from钩子·防循环)
		"starlight":      u["chest_starlight"] = true                                                        # 星辉: 所有伤害转真实(battle._damage._apply_damage_from raw钩子·armor全绕层过局限留F5)

func _chest_pick_equip(costs: Array) -> String:
	var pool: Array = []
	for eq in DataRegistry.phase2_equipment:
		if int(eq.get("cost", 0)) in costs:
			pool.append(str(eq.get("id", "")))
	if pool.is_empty():
		return ""
	return str(pool[battle._battle_rng.randi() % pool.size()])

func _chest_basic(u: Dictionary, tgt: Dictionary) -> void:       # 普攻·宝箱砸击(封板): K'Sante一段Q式·朝目标前方短直线AOE·各1A物理(近战扫一小片非单体)
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
	dir = DetMath.norm(dir)
	var aoe_mult: float = float(u.get("chest_aoe_mult", 1.0))       # 锁链loot将来翻倍AOE距离/射程钩子(=1未装)
	var reach: float = 170.0 * aoe_mult
	var halfw: float = 62.0 * aoe_mult
	var rock: float = float(u.get("chest_rock_bonus", 0.0))         # 石头loot将来额外+100%护甲+100%魔抗钩子(=0未装)
	var bonus: int = int((u["def"] + u["mr"]) * rock)
	# 逐帧订正(2026-07-16问责轮): 一段Q=砸地→金波头0.18s推进→扫到谁谁炸(错峰)→贴地燃金痕依次铺→尽头残亮头熄灭
	var wave_t: float = 0.18                                        # 波头跑完170码用时(s16砸→s21到敌≈0.15-0.2s)
	var uu: Dictionary = u
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = DetMath.dot(rel, dir)
		if along < -18.0 or along > reach: continue
		if DetMath.vlen((rel - dir * along)) > halfw: continue
		var oref: Dictionary = o
		battle._pending_shots.append({"delay": wave_t * clampf(along / reach, 0.0, 1.0), "fn": func() -> void:   # 波头扫到才结算(近先远后)
			if not oref.get("alive", false) or not uu.get("alive", false): return
			battle._damage._apply_basic_hit_from(uu, oref, battle._atk_dmg(uu, 1.0, oref) + bonus, Color("#ffd93d"))
			battle._burst_vfx("res://assets/sprites/vfx/treasure-slam.png", oref["pos"], 130.0)                  # 命中放射爆闪(s21·波到才炸)
		, "src": u})
	# ① 砸点层(s16): 尘环+金爆+轻震
	battle._shake(0.05)
	battle._skill_ring(u["pos"] + dir * 42.0, Color(1.0, 0.85, 0.3, 0.7), 30.0)
	battle._burst_vfx("res://assets/sprites/vfx/treasure-slam.png", u["pos"] + dir * 46.0, 120.0)
	# ② 金波头推进(0.18s冲到尽头→残亮头0.3s熄灭·不凭空消失)
	var glowt = VfxTex._make_fire_glow_tex()
	var wh = Sprite3D.new()
	wh.texture = glowt
	wh.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wh.shaded = false; wh.transparent = true
	wh.pixel_size = (44.0 * battle.WS) / float(maxi(1, glowt.get_width()))
	wh.modulate = Color(1.0, 0.85, 0.35, 0.95)
	wh.position = battle._world_pos(u["pos"] + dir * 46.0, 0.18)
	battle._world.add_child(wh)
	var wt = battle._reg_tween()
	wt.tween_property(wh, "position", battle._world_pos(u["pos"] + dir * reach, 0.18), wave_t)
	wt.tween_property(wh, "pixel_size", (20.0 * battle.WS) / float(maxi(1, glowt.get_width())), 0.3)   # 尽头残亮头收小熄灭(s26远端)
	wt.parallel().tween_property(wh, "modulate:a", 0.0, 0.3)
	wt.chain().tween_callback(wh.queue_free)
	# ③ 贴地痕迹(height压到0.06·原0.5悬空是错的): 冲击带短亮+燃金痕渐隐
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * reach, 96.0, Color(1.0, 0.85, 0.25, 0.7), 0.16, 0.06)
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * reach, 58.0, Color(1.0, 0.6, 0.15, 0.5), 0.6, 0.06)
	# ④ 尘旋圈随波头依次留下(s26·非同帧全出)
	for r in range(3):
		var rq: float = 0.3 + 0.28 * float(r)
		var rp: Vector2 = u["pos"] + dir * (reach * rq)
		battle._pending_shots.append({"delay": wave_t * rq, "fn": func() -> void:
			battle._skill_ring(rp, Color(1.0, 0.8, 0.35, 0.4), 26.0)
		, "src": u})

func _chest_coin_spray(pos2d: Vector2, n: int) -> void:        # 金币弹飞(抛物线落地淡出·命中反馈)
	var ctex: Texture2D = load("res://assets/sprites/vfx/storm-coin.png")
	if ctex == null: return
	for k in range(n):
		var ck = Sprite3D.new()
		ck.texture = ctex
		ck.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		ck.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ck.shaded = false; ck.transparent = true
		ck.pixel_size = 0.024 + 0.006 * randf()
		ck.position = battle._world_pos(pos2d, 0.5)
		battle._world.add_child(ck)
		var ang: float = randf() * TAU
		var dst: Vector2 = pos2d + Vector2(DetMath.dcos(ang), DetMath.dsin(ang)) * randf_range(40.0, 90.0)
		var dur: float = randf_range(0.35, 0.5)
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(ck, "position", battle._world_pos(dst, 0.05), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(ck, "modulate:a", 0.0, 0.15).set_delay(dur - 0.15)
		tw.chain().tween_callback(ck.queue_free)
		var up = battle._reg_tween()
		up.tween_property(ck, "position:y", ck.position.y + randf_range(0.15, 0.4), dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _chest_greed_apply(u: Dictionary, n: int) -> void:        # 贪婪(技三打包被动): 每携带1件装备永久+4%攻+7%最大生命 (单位=登场base快照·不复利)
	if n <= 0: return
	u["base_atk"] = float(u["base_atk"]) + float(u.get("chest_greed_atk_unit", 0.0)) * n
	var hb: float = float(u.get("chest_greed_hp_unit", 0.0)) * n
	u["maxHp"] = float(u["maxHp"]) + hb
	u["hp"] = float(u["hp"]) + hb
	battle._recalc_stats(u)

## 战利品浮层的正文(BBCode): 每件「图标 + 名字」一行, 下面一行效果 —— 面板的「战利品」入口条点开后显示。
##   用户 2026-10-22「然后在哪里有显示获得的装备？图标？」: 原来只有名字和效果两行纯文本, 看不到图标。
##   名字 / 说明 / 图标都取 ChestLoot(与背包宝箱龟卡的「藏宝图」同一份); 说明走装备说明同一条上色管线。
const LOOT_POPUP_ICON := 28
func loot_detail_text(owned: Dictionary) -> String:
	if owned == null or owned.is_empty():
		return ""                      # 标题「战利品 0/5」已经说明了(用户 2026-10-22: 不许自编「还没开出」这类话)
	var out: PackedStringArray = []
	for tid in owned.keys():
		var k := str(tid)
		var head := "[color=#ffd93d]%s[/color]" % str(ChestLoot.NAME.get(k, k))
		var ip := ChestLoot.icon_path(k)
		if ResourceLoader.exists(ip):
			head = "[img=%dx%d]%s[/img] %s" % [LOOT_POPUP_ICON, LOOT_POPUP_ICON, ip, head]
		out.append(head + "\n" + ChestLoot.desc_bb(k, 13))
	return "\n\n".join(out)

# 技能条目 [{name, desc}]: 取该龟已选的主动技 (走 _chosen_skill_types) + 普攻名 (skillPool[0]).
## 小将技能文案表 —— 小将 id 是 "__minion__", pets.json 里【没有】这个条目,
## 于是 _panel_skill_entries 查不到 pool → 详情面板整个「技能」区不渲染
## (用户 2026-07-21:「小将的技能描述要在面板里去显示」)。
## 文案取自各技能实现函数的头注释(那里就是权威描述), 数值口径见对应 _sk_* 实现。

func _sk_chest_inventory(u: Dictionary) -> void:                 # 宝箱龟·清点财宝(用户2026-07-16改: 每1000财宝→治疗+10%·盾不吃加成; 财宝值=大轮累积)
	## ★财宝值走同一个取数口(D, 2026-10-22): 原来敌方只看本路 dmg_dealt、不读快照基数 ⇒ 财宝值相同时敌方回得少。
	var tv: float = float(treasure_progress(u)["value"])
	var bonus: float = 1.0 + COUNT_HEAL_BONUS * floorf(tv / COUNT_PER_TREASURE)
	battle._damage._heal(u, u["maxHp"] * COUNT_HEAL_PCT * bonus)
	battle._damage._grant_shield(u, u["atk"] * COUNT_SHIELD_COEF)

func _sk_chest_cannon(u: Dictionary, tgt) -> void:              # 技三·财宝炮击(封板·120龟能): 蓄力→朝一条直线发长激光→线上所有敌各3A物理+击飞+击退 (贪婪打包被动在登场gate)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if DetMath.vlen(dir) < 1.0: dir = Vector2.RIGHT
	dir = DetMath.norm(dir)
	var uu = u
	var fire = func() -> void:                                     # 蓄力0.4s→喷金币洪流(用户2026-07-15确认换皮: 激光→金币+宝物炮流·机制不动)
		if not uu.get("alive", false): return
		for o in battle._targeting._enemies_of(uu):
			if not o.get("alive", false): continue
			if not battle._on_line(uu["pos"], dir, o["pos"], 58.0): continue
			battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, CANNON_COEF, o), Color("#ffe066"))
			battle._damage._knockback(uu, o, 60.0, 1.2, 1.4)                       # 击飞+击退
			battle._burst_vfx("res://assets/sprites/vfx/fortune-coin-burst.png", o["pos"], 130.0, 0.5)   # 命中金币爆
		battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", uu["pos"], uu["pos"] + dir * 1300.0, 110.0, Color(1.0, 0.85, 0.35, 0.5), 0.5)   # 金色气浪底
		battle._shake(battle.JUICE_SHAKE_BIG)
		var ctex: Texture2D = load("res://assets/sprites/vfx/storm-coin.png")
		var gtex: Texture2D = load("res://assets/sprites/vfx/gold-chunk.png")
		for k in range(26):                                         # 金币+金块洪流沿线喷射(散布±40码·翻滚)
			var pk = Sprite3D.new()
			pk.texture = ctex if k % 3 != 0 else gtex
			pk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			pk.billboard = BaseMaterial3D.BILLBOARD_ENABLED; pk.shaded = false; pk.transparent = true
			pk.pixel_size = 0.028 * randf_range(0.8, 1.3)
			pk.position = battle._world_pos(uu["pos"] + dir * 30.0, 0.8)
			battle._world.add_child(pk)
			var endp: Vector2 = uu["pos"] + dir * randf_range(300.0, 1250.0) + Vector2(-dir.y, dir.x) * randf_range(-40.0, 40.0)
			var life: float = randf_range(0.3, 0.55)
			var pt = battle._reg_tween()
			pt.tween_interval(randf() * 0.18)
			pt.tween_property(pk, "position", battle._world_pos(endp, randf_range(0.2, 1.2)), life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			pt.parallel().tween_property(pk, "modulate:a", 0.0, life)
			pt.tween_callback(pk.queue_free)
	battle._muzzle_flash(u["pos"], dir, Color("#ffd93d"))
	battle._anticipate(u)
	battle._pending_shots.append({"delay": 0.4, "fn": fire, "src": u, "cc": {}})   # 蓄力期被控 / 阵亡即取消(10-16)

func _sk_chest_storm(u: Dictionary, tgt) -> void:              # 技二·财宝风暴(2026-07-16重做·照Janna Q龙卷j006形成/j012风柱/j018螺旋盘): 金币龙卷风; 判定不变(400码·5跳各0.2A物理)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var center: Vector2 = tgt["pos"]
	var uu = u
	var stex: Texture2D = load("res://assets/sprites/vfx/coin-storm-spiral.png")
	var disc: Sprite3D = null
	var disc_ps: float = 0.01
	if stex != null:                                            # ① 贴地大螺旋底盘(500码·3金臂·整体旋转)
		disc = Sprite3D.new()
		disc.texture = stex
		disc.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		disc.axis = Vector3.AXIS_Y
		disc.shaded = false; disc.transparent = true
		disc.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		disc_ps = (500.0 * battle.WS) / float(maxi(1, stex.get_width()))
		disc.pixel_size = disc_ps * 0.3
		disc.modulate = Color(1.25, 1.05, 0.5, 0.0)   # 过曝亮金(青地砖上要压得住·自验后调)
		disc.position = battle._world_pos(center, 0.12)
		battle._world.add_child(disc)
	var disc2: Sprite3D = null                                  # 第二层小螺旋盘(260码·1.6倍速·纵深感)
	if stex != null:
		disc2 = Sprite3D.new()
		disc2.texture = stex
		disc2.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		disc2.axis = Vector3.AXIS_Y
		disc2.shaded = false; disc2.transparent = true
		disc2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		disc2.pixel_size = (260.0 * battle.WS) / float(maxi(1, stex.get_width()))
		disc2.modulate = Color(1.35, 1.1, 0.55, 0.0)
		disc2.position = battle._world_pos(center, 0.16)
		battle._world.add_child(disc2)
	var glow = VfxTex._make_fire_glow_tex()
	var pillars: Array = []
	for pi in range(3):                                         # ② 中心风柱(3层金光叠柱·底粗顶细·脉动)
		var pg = Sprite3D.new()
		pg.texture = glow
		pg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		pg.shaded = false; pg.transparent = true
		pg.pixel_size = ((130.0 - 32.0 * float(pi)) * battle.WS) / float(maxi(1, glow.get_width()))
		pg.modulate = Color(1.0, 0.85, 0.4, 0.0)
		pg.position = battle._world_pos(center, 0.35 + 0.72 * float(pi))
		battle._world.add_child(pg)
		pillars.append(pg)
	var ctex: Texture2D = load("res://assets/sprites/vfx/storm-coin.png")
	var coins: Array = []
	var lay_cfg = [[210.0, 0.35, 12, 4.2], [150.0, 0.95, 9, 4.8], [100.0, 1.5, 7, 5.6], [62.0, 2.05, 4, 6.4]]
	for li in range(lay_cfg.size()):                            # ③ 金币漏斗: 4层32枚·统一风向·底大顶小·从地面卷起(不凭空)
		var lay: Array = lay_cfg[li]
		for k in range(int(lay[2])):
			var ck = Sprite3D.new()
			ck.texture = ctex
			ck.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ck.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			ck.shaded = false; ck.transparent = true
			ck.pixel_size = 0.030 + 0.008 * randf()
			var a0: float = TAU * float(k) / float(lay[2]) + randf() * 0.4
			ck.position = battle._world_pos(center + Vector2(DetMath.dcos(a0), DetMath.dsin(a0)) * float(lay[0]) * 0.25, 0.04)
			battle._world.add_child(ck)
			coins.append({"spr": ck, "r": float(lay[0]), "h": float(lay[1]), "spd": float(lay[3]),
				"a0": a0, "rj": randf_range(0.85, 1.15), "up": randf_range(0.0, 0.28), "ph": randf() * TAU})
	var drv = battle._reg_tween()                                     # ④ 主驱动0→2.1s: 形成0.45s卷起→全速旋转(消散另段)
	drv.tween_method(func(t: float) -> void:
		var T: float = t * 2.1
		var form: float = clampf(T / 0.45, 0.0, 1.0)
		if is_instance_valid(disc):
			disc.rotation.y = -T * 5.5
			disc.modulate.a = maxf(disc.modulate.a - 0.04, 0.78 * form)   # 脉冲闪亮后回落(0.55→0.78自验后调亮)
			disc.pixel_size = disc_ps * (0.3 + 0.7 * form)
		if is_instance_valid(disc2):
			disc2.rotation.y = -T * 8.8
			disc2.modulate.a = 0.6 * form
		for pi2 in range(pillars.size()):
			var pg2 = pillars[pi2]
			if is_instance_valid(pg2):
				pg2.modulate.a = 0.42 * form * (0.85 + 0.15 * DetMath.dsin(T * 9.0 + float(pi2) * 1.7))   # 0.28→0.42自验后调亮
		for c in coins:
			var sp = c["spr"]
			if not is_instance_valid(sp): continue
			var rise: float = clampf((T - float(c["up"])) / 0.35, 0.0, 1.0)
			var aa: float = float(c["a0"]) + T * float(c["spd"])
			var rr: float = float(c["r"]) * (0.25 + 0.75 * rise) * float(c["rj"]) * (1.0 + 0.06 * DetMath.dsin(T * 3.0 + float(c["ph"])))
			var hh: float = 0.04 + (float(c["h"]) - 0.04) * rise
			sp.position = battle._world_pos(center + Vector2(DetMath.dcos(aa), DetMath.dsin(aa)) * rr, hh)
			var mb: float = 0.85 + 0.3 * absf(DetMath.dsin(T * 7.0 + float(c["ph"])))
			sp.modulate = Color(mb, mb, mb, 1.0)
	, 0.0, 1.0, 2.1)
	drv.tween_callback(func() -> void:                          # ⑤ 消散: 金币沿切线甩出抛物线落地(动量延续)·盘减速缩小淡出·柱下沉
		for c in coins:
			var sp = c["spr"]
			if not is_instance_valid(sp): continue
			var af: float = float(c["a0"]) + 2.1 * float(c["spd"])
			var pcur: Vector2 = center + Vector2(DetMath.dcos(af), DetMath.dsin(af)) * float(c["r"]) * float(c["rj"])
			var tangent: Vector2 = Vector2(-DetMath.dsin(af), DetMath.dcos(af))
			var dst: Vector2 = pcur + tangent * randf_range(130.0, 230.0) + Vector2(DetMath.dcos(af), DetMath.dsin(af)) * randf_range(20.0, 80.0)
			var fdur: float = randf_range(0.4, 0.55)
			var ft = battle._reg_tween(); ft.set_parallel(true)
			ft.tween_property(sp, "position", battle._world_pos(dst, 0.05), fdur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			ft.tween_property(sp, "modulate:a", 0.0, 0.2).set_delay(fdur - 0.12)
			ft.chain().tween_callback(sp.queue_free)
		if is_instance_valid(disc2):
			var d2t = battle._reg_tween(); d2t.set_parallel(true)
			d2t.tween_property(disc2, "modulate:a", 0.0, 0.4)
			d2t.tween_property(disc2, "rotation:y", disc2.rotation.y - 1.8, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			d2t.chain().tween_callback(disc2.queue_free)
		if is_instance_valid(disc):
			var dt2 = battle._reg_tween(); dt2.set_parallel(true)
			dt2.tween_property(disc, "rotation:y", disc.rotation.y - 1.4, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 减速尾旋
			dt2.tween_property(disc, "modulate:a", 0.0, 0.45)
			dt2.tween_property(disc, "pixel_size", disc.pixel_size * 0.88, 0.45)
			dt2.chain().tween_callback(disc.queue_free)
		for pg3 in pillars:
			if is_instance_valid(pg3):
				var pt3 = battle._reg_tween(); pt3.set_parallel(true)
				pt3.tween_property(pg3, "modulate:a", 0.0, 0.4)
				pt3.tween_property(pg3, "position", pg3.position + Vector3(0, -0.3, 0), 0.4)
				pt3.chain().tween_callback(pg3.queue_free)
		for _res in range(7):                                    # 风暴过后地面残留金币0.7s渐隐
			var rs = Sprite3D.new()
			rs.texture = ctex
			rs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			rs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			rs.shaded = false; rs.transparent = true
			rs.pixel_size = 0.026
			var ra2: float = randf() * TAU
			rs.position = battle._world_pos(center + Vector2(DetMath.dcos(ra2), DetMath.dsin(ra2)) * randf_range(30.0, 170.0), 0.05)
			rs.modulate = Color(1, 1, 1, 0.9)
			battle._world.add_child(rs)
			var rt2 = battle._reg_tween()
			rt2.tween_property(rs, "modulate:a", 0.0, 0.7)
			rt2.tween_callback(rs.queue_free))
	## ★捕获 weakref 不捕获 disc 本身(tween_capture_audit 台账 2026-10-04)。
	##   这几跳走 `_pending_shots`(sim 时钟, 顿帧期间不走), 而 disc 由上面那条 tween 链在 2.6 秒处释放
	##   (tween 顿帧期间照走) ⇒ 一场里累计顿帧超过 0.6 秒, 最后一跳就落在 disc 释放之后,
	##   Godot 在调用 lambda 之前就报「Lambda capture ... freed」—— 函数体里的 is_instance_valid 拦不住。
	##   只改了"拿 disc"这一步, 伤害那几行一个字没动。门禁: verify_tween_capture_lane。
	var disc_w: WeakRef = weakref(disc) if disc != null else null
	for i in range(STORM_TICKS):                                # ⑥ 5跳结算(数值不动)+命中特效+脉冲
		var fn = func():
			var dn = disc_w.get_ref() if disc_w != null else null
			if is_instance_valid(dn):
				dn.modulate.a = minf(0.85, dn.modulate.a + 0.25)   # 风暴脉冲闪亮(驱动器逐帧回落)
			for o in battle._targeting._enemies_of(uu):
				if o.get("alive", false) and DetMath.dist(o["pos"], center) <= STORM_RADIUS:
					battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, STORM_ATK_COEF, o), Color("#ffd93d"))
					battle._burst_vfx("res://assets/sprites/vfx/treasure-slam.png", o["pos"], 74.0)   # 命中金光爆
					_chest_coin_spray(o["pos"], 2)                                              # 敌身金币被抽飞
			battle._skill_ring(center, Color(1.0, 0.82, 0.2, 0.35), STORM_RADIUS)
			for _d in range(2):                                                                 # 边缘扬尘
				var da: float = randf() * TAU
				battle._skill_ring(center + Vector2(DetMath.dcos(da), DetMath.dsin(da)) * randf_range(330.0, 390.0), Color(1.0, 0.85, 0.4, 0.3), 22.0)
		battle._pending_shots.append({"delay": float(i) * STORM_TICK_SEC, "fn": fn, "src": u})

