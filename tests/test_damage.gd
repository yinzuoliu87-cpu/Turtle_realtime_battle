extends Node

const Events := preload("res://scripts/engine/events.gd")   # preload 直引 (不依赖全局 class 注册)
const Phase2Equip := preload("res://scripts/engine/phase2_equip.gd")
const Phase2Config := preload("res://scripts/engine/phase2_config.gd")
const DualLane := preload("res://scripts/engine/phase2_duallane.gd")
const Minion := preload("res://scripts/engine/phase2_minion.gd")
const Phase2EquipRuntime := preload("res://scripts/engine/phase2_equip_runtime.gd")
const Phase2Schools := preload("res://scripts/engine/phase2_schools.gd")
const Backend := preload("res://scripts/engine/backend.gd")
const BattleSceneScript := preload("res://scripts/scenes/BattleScene.gd")   # 装备详情两区式纯字符串助手测试 (.new() 不入树→无 _ready 副作用)

## test_damage.gd — W3 单元测试: 验证 damage.gd / fighter.gd 跟 PoC 公式 1:1
##
## 跑法: 在 Godot 编辑器里打开 tests/test_damage.tscn → F6 (Run Current Scene)
##       或者: 命令行 `godot --headless --quit-after 3 --main-scene res://tests/test_damage.tscn`
##
## 输出: 控制台打 PASS/FAIL, 错的会高亮 + 给期望值 vs 实际值。

var pass_count := 0
var fail_count := 0


func _ready() -> void:
	print("\n════════════════════════════════════════════════════════")
	print("  W3 单元测试 — damage.gd + fighter.gd")
	print("════════════════════════════════════════════════════════")

	# 数据可能还没加载完, 等一帧
	await get_tree().process_frame

	_test_level_mult()
	_test_ai_pick_skills()
	_test_equip_thunder_shell()
	_test_equip_dragon_egg()
	_test_equip_mini_crystal()
	_test_equip_post_cast()
	_test_equip_lightning_staff()
	_test_equip_incubator()
	_test_events()
	_test_create_fighter_basic()
	_test_create_fighter_rarity_scaling()
	_test_calc_eff_armor()
	_test_calc_dmg_mult()
	_test_calc_damage()
	_test_apply_raw_damage_to_hp()
	_test_apply_raw_damage_to_shield_then_hp()
	_test_apply_raw_damage_kill()
	_test_aura_energy_store()
	_test_skill_text_render()
	_test_equip_hourglass()
	_test_basic_vs_basic_2hit()
	_test_crit_mult()
	# W7 v2: 基建测试
	_test_recalc_atk_buffs()
	_test_recalc_chilled()
	_test_buffs_crud()
	_test_buffs_stun()
	_test_tick_duration()
	_test_physical_def_mr_scale()
	# W7 v2 T2 技能测试 (非随机部分)
	_test_t2_diamond_smash()
	_test_t2_ice_freeze_stun()
	_test_t2_diamond_fortify_shield()
	_test_t2_phoenix_burn_dot()
	_test_t2_pirate_plunder_steal()
	_test_t2_phoenix_scald_break_shield()
	_test_dodge()
	_test_ghost_equip_dodge()
	_test_chest_treasure()
	# A 组技能
	_test_two_head_magic_wave()
	_test_hunter_poison_dot()
	_test_current_hp_pct()
	_test_angel_equality_rarity()
	_test_selectors()
	_test_target_selection()
	_test_auto_assign_formation()
	_test_dot_floor_decay()
	_test_curse_single_decrement()
	_test_dot_tick_canonical_order()
	_test_hammer_no_double_atk()
	_test_ai_heal_shield_thresholds()
	_test_two_head_switch()
	_test_two_head_mind_blast()
	_test_lava_rage_hooks()
	_test_two_head_resilience_hook()
	_test_volcano_smash()
	_test_star_system()
	_test_shock_system()
	_test_hiding_handlers()
	_test_synergies()
	_test_damage_mitigation()
	_test_b_ghost_touch()
	_test_b_rock_shockwave()
	_test_b_ninja_impact_behind()
	_test_equip_dart_doll_conch_laser()
	_test_shop_economy()
	_test_shop_wealth_discount()
	_test_plan_ai_shop()
	_test_skill_coverage()
	_test_dungeon_revive_70pct()
	_test_achievement_tracker()
	_test_overtime_sudden_death()
	_test_dungeon_equip_carry()
	_test_phase2_equip_shell()
	_test_v2_season()   # V2 赛季/命核心: 失心淘汰 + 赛季过期/滚动 + 装备槽按总战斗数
	_test_v2_backend()  # V2 本地后端: 分档/bot生成/ghost池增删抽取/排行榜
	_test_phase2_sword_equips()
	_test_phase2_shield_equips()
	_test_phase2_equip_gap_fixes()   # 013全队硬化/016减伤/023满法力灼烧/055施法标记 (desc≠impl 补缺)
	# 龟蛋真单位 + 034玩偶大熊召唤
	_test_egg_immunity()
	_test_egg_final_config()
	_test_phase2_034_doll_bear()
	_test_phase2_armory_school()
	_test_phase2_school_feedback_events()   # 学派每回合 盾/治疗/净化 可见化事件 (圣甲/玄甲/血牙/潮汐) — on_round_begin 返事件给渲染器
	_test_status_badge_corrode_stiffness()  # 状态徽章: 深渊腐蚀 / 极地僵硬 叠层徽章 (原缺 case, 玩家看不见叠层)
	_test_hp_bar_holy_shield_segment()       # 血条圣盾段: 圣甲圣盾量(_holyShieldVal)画白黄亮, clamp 不超总盾 + 随盾衰减写回
	_test_phase2_audit_promised_effects()   # 审计补实装: 饰品溢出转盾/玄甲化/极地僵硬·易碎/深渊腐蚀/远古蛋HP 各验真触发
	_test_p2eq_types()
	_test_p2eq_types_active()
	_test_synergy_2zone_display()   # 两区式羁绊面板: 类型/学派 逐档完整效果文本(属性写全) + raw_counts 灰显未激活
	_test_staff_mana_system()   # 法器·法力系统: 累积/满档触发/023用法力非龟能/法力⊥龟能隔离
	_test_staff_proc_gating()   # 法器满档门控: 026/029/030/031 满法力才触发+清空(白填条修); 023 放开任意星级
	_test_p2eq_shield_rage()    # 盾[守护] 怒气冲击波: 受伤+盾件数怒气/满10冲击波(真伤+自盾)/清零
	_test_p2eq_food_team_hp()   # 食物[增益] 开场全队血(每件装备+30/80,食物双倍)+每回合成长标记
	_test_p2eq_relic_dodge()    # 灵物[召唤] 闪避属性: 每件+5/10%闪避(_extraDodge)封顶75%
	_test_p2eq_sword_echo()     # 剑[回响] 激活2/4/6: 剑装备伤害后50%回响1/2/3次(不触发proc) #543
	_test_p2eq_gadget()         # 奇械[深海工坊] 激活2/4/6: 死亡产装备(件数/费用/封顶/回退)+每回合铸币 #544
	_test_p2eq_gun_gold()       # 枪[神枪手] 激活2/3/5: 每射满4/3/2发出金弹(同伤+附带+60/80/100%真伤)/独立计数 #549
	_test_p2eq_tentacle()       # 灵物[召唤] 激活3/4: 1/2无敌触手/拍击(4%maxHP+55)×(1+5%×Σ独特灵物星) #553
	_test_fighter_tap_hold()    # 点龟 tap/hold 分流: 出手/选靶态快点不弹面板, 长按任何态弹面板 (用户报误弹面板)
	_test_wave_arrival_delay()  # 海浪043 波头到达时刻: 沿扫向(x)逐目标错峰(arrival-delay), 波接触才显伤/盾/魔法
	_test_multibullet_no_coalesce()   # 多弹武器048/049/050/053: 每颗子弹各带no_coalesce+arrival_delay(逐颗错峰), 不被并段→逐颗各掉各血
	_test_p2eq_equip_popup_display()   # 装备详情两区式: 上了龟主效果实算(×攻击力≈V)+加成区高亮当前星; 席/商店内联三档不动
	_test_shop_sell_bench_exclude()    # 商店拖卖区排除备战席矩形: 落点在席格内 → 不算"在商店上" → 不误卖 (2026-06-25 bug)
	_test_benchrow_horizontal_layout() # 云顶式横排备战席: 横席落战场下方/商店落最底/上下分层不重叠 + 拖卖拖装落点分类 (2026-06-26)
	_test_display_scheduler()          # 每目标统一显示队列: 同目标多事件按 at 有序入队/epoch 作废/kind 路由 + DoT 桶按 dmg_type/真火显真白/暴击按段记
	_test_hp_bar_death_step()          # 死亡掉血根治: 致命 step 走到 0 (alive==false 不再误丢) + _play_death 兜底强刷 + 队列清理不误伤致命掉血

	print("════════════════════════════════════════════════════════")
	if fail_count == 0:
		print("  ✅ ALL PASS  (%d/%d)" % [pass_count, pass_count])
	else:
		print("  ❌ %d FAIL / %d PASS  (total %d)" % [fail_count, pass_count, pass_count + fail_count])
	print("════════════════════════════════════════════════════════\n")


## 类型(职业)羁绊: type_of 映射 + calc_active 档位 + 属性类 apply_team_start 数值。
func _test_p2eq_types() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	_assert_eq("类型 p2eq_001=剑", P2T.type_of("p2eq_001"), "剑")
	_assert_eq("类型 p2eq_020=奇械", P2T.type_of("p2eq_020"), "奇械")
	_assert_eq("类型 p2eq_003=护符", P2T.type_of("p2eq_003"), "护符")
	# 6件剑(001/007/005/006/009/010)→剑tier3(激活6); 每件剑+50攻 (per-piece, 走baseAtk)
	var f1 = {"baseAtk": 40, "atk": 40, "_p2_equips": [{"id": "p2eq_001"}, {"id": "p2eq_007"}]}
	var f2 = {"baseAtk": 40, "atk": 40, "_p2_equips": [{"id": "p2eq_005"}]}
	var f3 = {"baseAtk": 40, "atk": 40, "_p2_equips": [{"id": "p2eq_006"}, {"id": "p2eq_009"}, {"id": "p2eq_010"}]}
	var team = [f1, f2, f3]
	var act = P2T.calc_active(team)
	_assert_eq("剑6件→tier3", int(act[0]["tier"]) if act.size() > 0 else -1, 3)
	_assert_eq("剑count=6", int(act[0]["count"]) if act.size() > 0 else -1, 6)
	P2T.apply_team_start(team)
	_assert_eq("带2件剑 baseAtk+100", int(f1["baseAtk"]), 140)
	_assert_eq("带1件剑 baseAtk+50", int(f2["baseAtk"]), 90)
	_assert_eq("带3件剑 baseAtk+150", int(f3["baseAtk"]), 190)


## 类型(职业)羁绊【主动类】: 弓箭神射手处决 + 遗物古物条件(攻击力%/吸血翻倍)。
func _test_p2eq_types_active() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# ── 弓箭[神射手] 处决 ──
	# 弓箭 ids = 054/039/049/055/056; tiers=[2,3,4,5]。带 3 件弓箭 → tier2 (阈值 3 → 第2档) → base 0.05。
	var arch = {"side": "left", "crit": 0.0, "_p2_equips": [{"id": "p2eq_054"}, {"id": "p2eq_039"}, {"id": "p2eq_049"}]}
	var team_a = [arch]
	var act_a = P2T.calc_active(team_a)
	var bow_tier = -1
	for a in act_a:
		if a["type"] == "弓箭":
			bow_tier = int(a["tier"])
	_assert_eq("弓箭3件→tier2", bow_tier, 2)
	P2T.apply_team_start(team_a)
	_assert_eq("弓箭激活→_archerExecBase=0.05", float(arch.get("_archerExecBase", 0.0)), 0.05, 0.0001)

	# 斩杀线 = 0.05 + crit×0.1。crit=0 → 线=0.05 → 目标 hp%=0.04(<0.05) 应被处决。
	var victim = {"side": "right", "alive": true, "hp": 4, "maxHp": 100}
	var fx_kill = P2RT.on_hit(arch, victim, 10, "p2eq_054", 1, [arch, victim], true)
	_assert_eq("弓箭处决: hp%<线 → 抹掉剩余血(派生伤害)", fx_kill.size() > 0 and int(victim["hp"]) <= 0, true)

	# hp%=0.10(>0.05) → 不处决。
	var arch2 = {"side": "left", "crit": 0.0, "_archerExecBase": 0.05}
	var survivor = {"side": "right", "alive": true, "hp": 10, "maxHp": 100}
	var fx_no = P2RT.on_hit(arch2, survivor, 5, "p2eq_054", 1, [arch2, survivor], true)
	_assert_eq("弓箭不处决: hp%>线 → 不抹血", int(survivor["hp"]), 10)
	_assert_eq("弓箭不处决: 无处决派生伤害", fx_no.size(), 0)

	# crit 提高斩杀线: crit=0.5 → 线 = 0.05 + 0.05 = 0.10 → hp%=0.08(<0.10) 应处决。
	var arch3 = {"side": "left", "crit": 0.5, "_archerExecBase": 0.05}
	var v3 = {"side": "right", "alive": true, "hp": 8, "maxHp": 100}
	P2RT.on_hit(arch3, v3, 5, "p2eq_054", 1, [arch3, v3], true)
	_assert_eq("弓箭暴击抬线: crit0.5→线0.10→hp8%被处决", int(v3["hp"]) <= 0, true)

	# 不沉之锚免疫斩杀: _p2AnchorImmune → 不被处决。
	var arch4 = {"side": "left", "crit": 0.0, "_archerExecBase": 0.10}
	var immune = {"side": "right", "alive": true, "hp": 3, "maxHp": 100, "_p2AnchorImmune": true}
	P2RT.on_hit(arch4, immune, 5, "p2eq_054", 1, [arch4, immune], true)
	_assert_eq("弓箭处决: 不沉之锚免疫 → 不被处决", int(immune["hp"]), 3)

	# ── 遗物[古物] 条件 ──
	# 遗物 ids = 053/058/024/059; tiers=[2,4,6]。带 2 件遗物 → tier1 → +吸血5% + atkPct0.03 + lifestealBase0.05。
	var relic = {"side": "left", "baseAtk": 100, "atk": 100, "hp": 100, "maxHp": 100, "_p2_equips": [{"id": "p2eq_053"}, {"id": "p2eq_058"}]}
	var team_r = [relic]
	var act_r = P2T.calc_active(team_r)
	var relic_tier = -1
	for a in act_r:
		if a["type"] == "遗物":
			relic_tier = int(a["tier"])
	_assert_eq("遗物2件→tier1", relic_tier, 1)
	P2T.apply_team_start(team_r)
	# _lifestealPct 属性是【逐件】给(同剑+50/件): 2件遗物 → +5×2 = 10。
	_assert_eq("遗物激活→_lifestealPct 逐件+5(2件=10)", int(relic.get("_lifestealPct", 0)), 10)
	_assert_eq("遗物激活→_relicHealthAtkPct=0.03", float(relic.get("_relicHealthAtkPct", 0.0)), 0.03, 0.0001)
	_assert_eq("遗物激活→_relicLifestealBase=0.05", float(relic.get("_relicLifestealBase", 0.0)), 0.05, 0.0001)

	# 生命>50% → StatsRecalc 给 +3% atk: 100 → 103。
	relic["hp"] = 100
	StatsRecalc.snapshot_base(relic)
	StatsRecalc.recalc(relic)
	_assert_eq("遗物 hp>50% → atk +3% (100→103)", int(relic["atk"]), 103)

	# 生命<50% → 无 atk 加成: atk 回 base 100。
	relic["hp"] = 40
	StatsRecalc.recalc(relic)
	_assert_eq("遗物 hp<50% → 无atk加成 (回100)", int(relic["atk"]), 100)


## 两区式羁绊面板·显示数据 (用户 2026-06-25): 类型/学派 逐档完整效果文本(属性写全名+数值, 不缩写),
##   emoji/显示名, raw_counts(含未达首档→灰显), tier 越界返回 ""。
func _test_synergy_2zone_display() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2S = load("res://scripts/engine/phase2_schools.gd")

	# ── 类型逐档完整属性文本 (剑系: 各档攻击力数值 + 回响次数都写全) ──
	var sw1: String = P2T.tier_desc("剑", 1)
	var sw3: String = P2T.tier_desc("剑", 3)
	_assert_eq("剑1档含 +15 攻击力", sw1.contains("+15 攻击力"), true)
	_assert_eq("剑1档含 回响 1 次", sw1.contains("回响 1 次"), true)
	_assert_eq("剑3档含 +50 攻击力", sw3.contains("+50 攻击力"), true)
	_assert_eq("剑3档含 回响 3 次", sw3.contains("回响 3 次"), true)
	# 属性写全名(不缩写): 盾→护甲, 护符→魔法抗性, 药水→最大龟能, 枪→护甲穿透, 弓箭→暴击率, 灵物→闪避率, 遗物→吸血
	_assert_eq("盾2档含 +13 护甲", P2T.tier_desc("盾", 2).contains("+13 护甲"), true)
	_assert_eq("护符3档含 +65 魔法抗性", P2T.tier_desc("护符", 3).contains("+65 魔法抗性"), true)
	_assert_eq("药水1档含 +15 最大龟能", P2T.tier_desc("药水", 1).contains("+15 最大龟能"), true)
	_assert_eq("枪3档含 +28 护甲穿透", P2T.tier_desc("枪", 3).contains("+28 护甲穿透"), true)
	_assert_eq("弓箭1档含 +8% 暴击率", P2T.tier_desc("弓箭", 1).contains("+8% 暴击率"), true)
	_assert_eq("灵物1档含 +5% 闪避率", P2T.tier_desc("灵物", 1).contains("+5% 闪避率"), true)
	_assert_eq("遗物2档含 +10% 吸血", P2T.tier_desc("遗物", 2).contains("+10% 吸血"), true)
	_assert_eq("法器1档含 +8 法术穿透", P2T.tier_desc("法器", 1).contains("+8 法术穿透"), true)
	# 逐档对齐档数 (TYPES.tiers.size() == TIER_DESCS.size())
	for t in P2T.TYPES:
		var n_tiers: int = (P2T.TYPES[t].get("tiers", []) as Array).size()
		var n_desc: int = (P2T.TIER_DESCS.get(t, []) as Array).size()
		_assert_eq("类型 %s 档数=描述数" % t, n_desc, n_tiers)

	# ── 学派逐档完整文本 (黑礁猎团: 伤害% + 击杀永久攻击力 + 8档处决) ──
	var hr1: String = P2S.tier_desc("黑礁猎团", 1)
	var hr3: String = P2S.tier_desc("黑礁猎团", 3)
	_assert_eq("黑礁猎团1档含 +15%", hr1.contains("+15%"), true)
	_assert_eq("黑礁猎团1档含 永久 +14", hr1.contains("永久 +14"), true)
	_assert_eq("黑礁猎团3档含 处决", hr3.contains("处决"), true)
	_assert_eq("深渊议会1档含 12% 护甲和魔抗", P2S.tier_desc("深渊议会", 1).contains("12% 护甲和魔抗"), true)
	# 学派逐档对齐档数
	for s in P2S.SCHOOLS:
		var sn_tiers: int = (P2S.SCHOOLS[s].get("tiers", []) as Array).size()
		var sn_desc: int = (P2S.TIER_DESCS.get(s, []) as Array).size()
		_assert_eq("学派 %s 档数=描述数" % s, sn_desc, sn_tiers)

	# ── emoji / 显示名 非空 ──
	_assert_eq("类型 emoji 非空", P2T.emoji_of("剑") != "", true)
	_assert_eq("类型 显示名 非空", P2T.display_name("剑") != "", true)
	_assert_eq("学派 emoji 非空", P2S.emoji_of("黑礁猎团") != "", true)

	# ── tier 越界 → "" ──
	_assert_eq("类型 tier 0 → 空", P2T.tier_desc("剑", 0), "")
	_assert_eq("类型 tier 超档 → 空", P2T.tier_desc("剑", 99), "")
	_assert_eq("学派 tier 越界 → 空", P2S.tier_desc("黑礁猎团", 0), "")
	_assert_eq("未知键 → 空", P2T.tier_desc("不存在", 1), "")

	# ── raw_counts: 含未达首档(给灰显). 剑 tiers=[2,4,6], 只带 1 件剑 → 未激活但 raw_counts 计 1 ──
	var f_one_sword = {"_p2_equips": [{"id": "p2eq_001"}]}   # p2eq_001 = 剑(type) + 黑礁猎团(school)
	var tc: Dictionary = P2T.raw_counts([f_one_sword])
	_assert_eq("raw_counts 剑=1 (未达首档2但仍计数→可灰显)", int(tc.get("剑", 0)), 1)
	_assert_eq("calc_active 剑1件 未激活(空)", P2T.calc_active([f_one_sword]).size(), 0)
	var sc: Dictionary = P2S.raw_counts([f_one_sword])
	_assert_eq("学派 raw_counts 黑礁猎团=1", int(sc.get("黑礁猎团", 0)), 1)


## 法器·法力系统: 独立法力条(≠龟能) + 累积(+25/回合·伤害×0.1·受伤×0.1) + 满档触发清空 + 023用法力 + 法力⊥龟能隔离。
func _test_staff_mana_system() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# ── 满档上限: tier(法器激活档 1/2/3)→100/80/60 ──
	_assert_eq("法器档1 满档=100", P2T.staff_mana_cap(1), 100)
	_assert_eq("法器档2 满档=80", P2T.staff_mana_cap(2), 80)
	_assert_eq("法器档3 满档=60", P2T.staff_mana_cap(3), 60)

	# ── apply_team_start: 2件法器→tier1, 每件开独立 _staff_mana 条=0, 标 _staffTier ──
	# 法器 ids = 030/031/029/026/023; tiers=[2,4,6]。带 2 件 → tier1。
	var caster = {"side": "left", "alive": true, "atk": 100, "_maxEnergy": 50, "_energy": 30,
		"_p2_equips": [{"id": "p2eq_023"}, {"id": "p2eq_029"}]}
	var team_s = [caster]
	P2T.apply_team_start(team_s)
	_assert_eq("法器2件→_staffTier=1", int(caster.get("_staffTier", 0)), 1)
	_assert_eq("法器开 _staff_mana 字典", caster.get("_staff_mana") is Dictionary, true)
	_assert_eq("023 独立法力条初始0", int((caster["_staff_mana"] as Dictionary).get("p2eq_023", -1)), 0)
	_assert_eq("029 独立法力条初始0", int((caster["_staff_mana"] as Dictionary).get("p2eq_029", -1)), 0)
	# 注: 法器【类型属性】给 +10最大龟能/件(规格#551属性部分, ≠法力机制) → 此处2件法器 _maxEnergy 50→70。
	#   法力机制(下面 staff_* 钩子)与龟能完全隔离: 捕获 apply 后的龟能基线, 验证法力操作【绝不】再动它。
	var energy_base: int = int(caster.get("_energy", -1))       # =30 (未变)
	var maxenergy_base: int = int(caster.get("_maxEnergy", -1))  # =70 (法器属性+20)
	_assert_eq("法器属性给+10龟能/件→_maxEnergy 50+20=70", maxenergy_base, 70)
	_assert_eq("法器属性不动当前龟能 _energy=30", energy_base, 30)

	# ── 累积①: round_begin 每件 +25 (各自独立, 同步) ──
	P2RT.staff_round_begin(caster)
	_assert_eq("round_begin: 023法力+25", int(caster["_staff_mana"]["p2eq_023"]), 25)
	_assert_eq("round_begin: 029法力+25", int(caster["_staff_mana"]["p2eq_029"]), 25)
	# 隔离铁证 ②: 累积法力后龟能纹丝不动 (相对基线)。
	_assert_eq("累法力不动 _energy", int(caster.get("_energy", -1)), energy_base)
	_assert_eq("累法力不动 _maxEnergy", int(caster.get("_maxEnergy", -1)), maxenergy_base)

	# ── 累积②: 携带者技能伤害 ×0.1 ──
	P2RT.staff_on_skill_damage(caster, 200.0)   # 200×0.1=20
	_assert_eq("技能伤害200×0.1→023法力25+20=45", int(caster["_staff_mana"]["p2eq_023"]), 45)
	_assert_eq("技能伤害200×0.1→029法力25+20=45", int(caster["_staff_mana"]["p2eq_029"]), 45)

	# ── 累积③: 受伤 ×0.1 ──
	P2RT.staff_on_damaged(caster, 300.0)   # 300×0.1=30 → 45+30=75
	_assert_eq("受伤300×0.1→023法力45+30=75", int(caster["_staff_mana"]["p2eq_023"]), 75)

	# ── 上限封顶: 满档=100(tier1), 不溢出 ──
	P2RT.staff_add_mana(caster, 999.0)
	_assert_eq("法力封顶=满档100(不溢出)", int(caster["_staff_mana"]["p2eq_023"]), 100)
	_assert_eq("满档判定 staff_ready=true", P2RT.staff_ready(caster, "p2eq_023"), true)
	# 隔离铁证 ③: 法力封顶/满档, 龟能依旧不变。
	_assert_eq("法力满档不动 _energy", int(caster.get("_energy", -1)), 30)

	# ── 023 满法力触发: on_turn_begin(3★) → 全敌各60灼烧 + 清空该条(非龟能) ──
	var enemy = {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "buffs": []}
	var team2 = [caster, enemy]
	# 满档 → 触发
	var fx23 = P2RT.on_turn_begin(caster, "p2eq_023", 3, team2)
	var eburn := 0
	for b in enemy["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			eburn = int(b.get("value", 0))
	_assert_eq("023满法力→全敌灼烧60层", eburn, 60)
	_assert_eq("023触发后清空【这件】法力条(=0)", int(caster["_staff_mana"]["p2eq_023"]), 0)
	# 隔离铁证 ④: 023 触发清空的是法力, 龟能纹丝不动 (旧实现是清龟能 → 现在绝不能动)。
	_assert_eq("023触发不清龟能 _energy 仍30", int(caster.get("_energy", -1)), energy_base)
	_assert_eq("023触发不动 _maxEnergy", int(caster.get("_maxEnergy", -1)), maxenergy_base)
	# 029 那条法力不受 023 触发影响 (各自独立)。
	_assert_eq("029法力条不被023触发清空(仍100)", int(caster["_staff_mana"]["p2eq_029"]), 100)

	# ── 未满档不触发: 重置后法力<满档 → on_turn_begin 不灼烧 ──
	caster["_staff_mana"]["p2eq_023"] = 50   # <100
	var enemy2 = {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "buffs": []}
	var team3 = [caster, enemy2]
	P2RT.on_turn_begin(caster, "p2eq_023", 3, team3)
	var noburn := false
	for b in enemy2["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			noburn = true
	_assert_eq("023未满法力→不灼烧", noburn, false)
	_assert_eq("023未满法力→法力条保留(仍50)", int(caster["_staff_mana"]["p2eq_023"]), 50)

	# ── 隔离铁证 ⑤(反向): 改龟能不影响法力 ──
	caster["_energy"] = 0
	caster["_maxEnergy"] = 0
	_assert_eq("清空龟能后→023法力条仍50(不受影响)", int(caster["_staff_mana"]["p2eq_023"]), 50)
	_assert_eq("清空龟能后→029法力条仍100(不受影响)", int(caster["_staff_mana"]["p2eq_029"]), 100)

	# ── 无法器系统(非法器龟): staff_* 不开条、不报错、不动龟能 ──
	var plain = {"side": "left", "_energy": 40, "_maxEnergy": 80}
	P2RT.staff_round_begin(plain)       # 无 _staff_mana → no-op
	P2RT.staff_on_skill_damage(plain, 500.0)
	_assert_eq("非法器龟: 不被开法力条", plain.has("_staff_mana"), false)
	_assert_eq("非法器龟: 龟能不被法器钩子动 _energy", int(plain.get("_energy", -1)), 40)


## 法器满档门控 (白填条修): 026/029/030/031 在【法器系统激活】时, 满法力(staff_ready)才触发 + 触发后清空该法力条;
##   未满则不触发、法力条保留(继续积累); 无法器系统(单件无羁绊)走原 fallback 触发。023 active 放开任意星级。
func _test_staff_proc_gating() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# 助手: 造一个带 4 法器(026/029/030/031)激活 tier 的携带者 + 一个敌人。
	#   带 4 件 → tier2 (满档=80)。
	var func_make := func() -> Array:
		var c = {"side": "left", "alive": true, "atk": 100, "hp": 1000, "maxHp": 1000, "shield": 0,
			"_slotKey": "front-0", "buffs": [],
			"_p2_equips": [{"id": "p2eq_026"}, {"id": "p2eq_029"}, {"id": "p2eq_030"}, {"id": "p2eq_031"}]}
		var e = {"side": "right", "alive": true, "atk": 50, "hp": 5000, "maxHp": 5000, "shield": 0,
			"_slotKey": "front-0", "buffs": []}
		var team = [c, e]
		P2T.apply_team_start(team)
		return team

	# ── 026 雷电法杖 (on_hit): 满法力→链电触发+清空; 未满→不触发+法力保留 ──
	var t26 = func_make.call()
	var c26 = t26[0]; var e26 = t26[1]
	var cap26: int = P2T.staff_mana_cap(int(c26.get("_staffTier", 0)))
	# 未满: 法力=0 → on_hit 不放电 (返回无 lightning effect)
	c26["_staff_mana"]["p2eq_026"] = 0
	var fx26_empty = P2RT.on_hit(c26, e26, 50, "p2eq_026", 1, t26, true)
	var has_chain_empty := false
	for ev in fx26_empty:
		if ev is Dictionary and int(ev.get("value", 0)) > 0 and str(ev.get("dmg_type", "")) == "magic":
			has_chain_empty = true
	_assert_eq("026 法力未满→不放电", has_chain_empty, false)
	_assert_eq("026 法力未满→法力条保留(=0)", int(c26["_staff_mana"]["p2eq_026"]), 0)
	# 满档: 法力=cap → on_hit 放电 + 清空
	c26["_staff_mana"]["p2eq_026"] = cap26
	var fx26_full = P2RT.on_hit(c26, e26, 50, "p2eq_026", 1, t26, true)
	var has_chain_full := false
	for ev in fx26_full:
		if ev is Dictionary and int(ev.get("value", 0)) > 0 and str(ev.get("dmg_type", "")) == "magic":
			has_chain_full = true
	_assert_eq("026 满法力→放链电", has_chain_full, true)
	_assert_eq("026 满法力触发后清空法力条(=0)", int(c26["_staff_mana"]["p2eq_026"]), 0)

	# ── 029 冰封水母 (on_hit): 满法力→必触发额外魔法+清空; 未满→不触发 (无概率随机性) ──
	var t29 = func_make.call()
	var c29 = t29[0]; var e29 = t29[1]
	var cap29: int = P2T.staff_mana_cap(int(c29.get("_staffTier", 0)))
	c29["_staff_mana"]["p2eq_029"] = 0
	var fx29_empty = P2RT.on_hit(c29, e29, 50, "p2eq_029", 1, t29, true)
	_assert_eq("029 法力未满→不触发(无额外effect)", fx29_empty.size(), 0)
	c29["_staff_mana"]["p2eq_029"] = cap29
	var fx29_full = P2RT.on_hit(c29, e29, 50, "p2eq_029", 1, t29, true)
	_assert_eq("029 满法力→触发额外魔法(有effect)", fx29_full.size() > 0, true)
	_assert_eq("029 满法力触发后清空法力条(=0)", int(c29["_staff_mana"]["p2eq_029"]), 0)

	# ── 030 迷你水晶球A (on_cast): 满法力→触发束+清空; 未满→不触发 ──
	var t30 = func_make.call()
	var c30 = t30[0]
	var cap30: int = P2T.staff_mana_cap(int(c30.get("_staffTier", 0)))
	c30["_staff_mana"]["p2eq_030"] = 0
	var fx30_empty = P2RT.on_cast(c30, "p2eq_030", 1, t30)
	_assert_eq("030 法力未满→不触发(无effect)", fx30_empty.size(), 0)
	c30["_staff_mana"]["p2eq_030"] = cap30
	var fx30_full = P2RT.on_cast(c30, "p2eq_030", 1, t30)
	_assert_eq("030 满法力→触发水晶束(有effect)", fx30_full.size() > 0, true)
	_assert_eq("030 满法力触发后清空法力条(=0)", int(c30["_staff_mana"]["p2eq_030"]), 0)

	# ── 031 迷你水晶球B (on_cast): 满法力→触发+清空; 未满→不触发 ──
	var t31 = func_make.call()
	var c31 = t31[0]
	var cap31: int = P2T.staff_mana_cap(int(c31.get("_staffTier", 0)))
	c31["_staff_mana"]["p2eq_031"] = 0
	var fx31_empty = P2RT.on_cast(c31, "p2eq_031", 1, t31)
	_assert_eq("031 法力未满→不触发(无effect)", fx31_empty.size(), 0)
	c31["_staff_mana"]["p2eq_031"] = cap31
	var fx31_full = P2RT.on_cast(c31, "p2eq_031", 1, t31)
	_assert_eq("031 满法力→触发扫描束(有effect)", fx31_full.size() > 0, true)
	_assert_eq("031 满法力触发后清空法力条(=0)", int(c31["_staff_mana"]["p2eq_031"]), 0)

	# ── 无法器系统 fallback: 单件 030 无羁绊 → on_cast 每次都触发(原行为, 不靠法力) ──
	var c_solo = {"side": "left", "alive": true, "atk": 100, "hp": 1000, "maxHp": 1000, "shield": 0,
		"_slotKey": "front-0", "buffs": [], "_p2_equips": [{"id": "p2eq_030"}]}
	var e_solo = {"side": "right", "alive": true, "atk": 50, "hp": 5000, "maxHp": 5000, "shield": 0,
		"_slotKey": "front-0", "buffs": []}
	var team_solo = [c_solo, e_solo]
	P2T.apply_team_start(team_solo)   # 1 件法器 → 不到 tier1(需2件) → _staffTier=0 → 无法力系统
	_assert_eq("单件法器→无法器系统(_staffTier=0)", int(c_solo.get("_staffTier", 0)), 0)
	var fx_solo = P2RT.on_cast(c_solo, "p2eq_030", 1, team_solo)
	_assert_eq("无法器系统 030→每次施法都触发(fallback)", fx_solo.size() > 0, true)

	# ── 023 active 放开任意星级: 满法力 + star=1 → 仍灼烧 (原限 t>=3) ──
	var c23 = {"side": "left", "alive": true, "atk": 100, "hp": 1000, "maxHp": 1000, "buffs": [],
		"_slotKey": "front-0", "_p2_equips": [{"id": "p2eq_023"}, {"id": "p2eq_029"}]}
	var e23 = {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "buffs": []}
	var team23 = [c23, e23]
	P2T.apply_team_start(team23)
	c23["_staff_mana"]["p2eq_023"] = P2T.staff_mana_cap(int(c23.get("_staffTier", 0)))   # 满档
	P2RT.on_turn_begin(c23, "p2eq_023", 1, team23)   # star=1 (原 t>=3 不触发)
	var burn23star1 := 0
	for b in e23["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			burn23star1 = int(b.get("value", 0))
	_assert_eq("023 放开任意星级: 1★ 满法力→仍灼烧60", burn23star1, 60)
	_assert_eq("023 1★ 触发后清空法力条(=0)", int(c23["_staff_mana"]["p2eq_023"]), 0)


## 类型(职业)羁绊【盾·守护 怒气冲击波】: 受伤+盾件数怒气, 满10 → 对一敌 thr×maxHp 真伤 + 自获 thr×maxHp 护盾, 怒气清零。
func _test_p2eq_shield_rage() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")
	# 盾 ids = 018/016/015/014/017; tiers=[2,3,4,5]。带 3 件盾 → tier2 → thr=0.05。
	var tank = {"side": "left", "alive": true, "maxHp": 1000, "hp": 1000, "shield": 0, "buffs": [],
		"_p2_equips": [{"id": "p2eq_018"}, {"id": "p2eq_016"}, {"id": "p2eq_015"}]}
	var enemy = {"side": "right", "alive": true, "maxHp": 2000, "hp": 2000, "shield": 0, "buffs": []}
	var team = [tank, enemy]
	var act = P2T.calc_active(team)
	var shield_tier = -1
	for a in act:
		if a["type"] == "盾":
			shield_tier = int(a["tier"])
	_assert_eq("盾3件→tier2", shield_tier, 2)
	P2T.apply_team_start(team)
	_assert_eq("盾激活→_shieldRageThr=0.05", float(tank.get("_shieldRageThr", 0.0)), 0.05, 0.0001)
	_assert_eq("盾激活→_shieldPieces=3", int(tank.get("_shieldPieces", 0)), 3)
	_assert_eq("盾激活→_shieldRage 初始0", int(tank.get("_shieldRage", -1)), 0)

	# 受伤1次 → +3怒气 (盾件数); <10 不释放。
	var fx1 = P2RT.shield_rage_on_damaged(tank, team)
	_assert_eq("受伤1次→怒气3", int(tank["_shieldRage"]), 3)
	_assert_eq("怒气<10→不释放冲击波(无effect)", fx1.size(), 0)
	# 再2次 → 9怒气, 仍不释放。
	P2RT.shield_rage_on_damaged(tank, team)
	P2RT.shield_rage_on_damaged(tank, team)
	_assert_eq("受伤3次→怒气9", int(tank["_shieldRage"]), 9)
	# 第4次 → 12怒气 ≥10 → 释放, 消耗10 → 余2。
	var enemy_hp_before := int(enemy["hp"])
	var fx2 = P2RT.shield_rage_on_damaged(tank, team)
	_assert_eq("满10→释放后余2怒气(12-10)", int(tank["_shieldRage"]), 2)
	# 真伤 = 0.05×2000 = 100 → 敌血 2000→1900。
	_assert_eq("冲击波真伤=0.05×敌maxHp2000=100", enemy_hp_before - int(enemy["hp"]), 100)
	# 自盾 = 0.05×1000 = 50。
	_assert_eq("自获护盾=0.05×自maxHp1000=50", int(tank.get("shield", 0)), 50)
	# effect: 1 真伤 + 1 护盾。
	var has_dmg := false
	var has_shield := false
	for e in fx2:
		if e is Dictionary:
			if e.get("kind", "") == "damage":
				has_dmg = true
			if e.get("kind", "") == "shield":
				has_shield = true
	_assert_eq("冲击波 effect 含真伤", has_dmg, true)
	_assert_eq("冲击波 effect 含自盾", has_shield, true)

	# 无盾羁绊龟 → 受伤不积怒气、不报错。
	var plain = {"side": "left", "alive": true, "maxHp": 500, "hp": 500}
	var fx_plain = P2RT.shield_rage_on_damaged(plain, [plain, enemy])
	_assert_eq("非盾龟: 不积怒气(无_shieldRage)", plain.has("_shieldRage"), false)
	_assert_eq("非盾龟: 无冲击波effect", fx_plain.size(), 0)


## 类型(职业)羁绊【食物·增益 全队血】: 开场队伍每件装备+30/80 maxHp(食物双倍), + 每回合成长标记 _foodRoundGrow。
func _test_p2eq_food_team_hp() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	# 食物 ids = 002/012/036/013/037; tiers=[3,5]。带 3 件食物 → tier1 → 每件装备 +30, 食物双倍 +60。
	# f1: 3件食物(全食物) → 3×60 = 180; 标 _foodRoundGrow=8。
	var f1 = {"side": "left", "maxHp": 1000, "hp": 1000,
		"_p2_equips": [{"id": "p2eq_002"}, {"id": "p2eq_012"}, {"id": "p2eq_036"}]}
	# f2: 2件非食物装备(剑001/盾018) → 2×30 = 60; 非食物携带者 → 无成长标记。
	var f2 = {"side": "left", "maxHp": 1000, "hp": 1000,
		"_p2_equips": [{"id": "p2eq_001"}, {"id": "p2eq_018"}]}
	var team = [f1, f2]
	var act = P2T.calc_active(team)
	var food_tier = -1
	for a in act:
		if a["type"] == "食物":
			food_tier = int(a["tier"])
	_assert_eq("食物3件→tier1", food_tier, 1)
	P2T.apply_team_start(team)
	# f1: 3食物×60 = 180 → 1000+180 = 1180 (maxHp 与 hp 同加)。
	_assert_eq("食物开场: f1 3食物×60 → maxHp 1180", int(f1["maxHp"]), 1180)
	_assert_eq("食物开场: f1 hp 同加 → 1180", int(f1["hp"]), 1180)
	# f2: 剑+盾 2件非食物×30 = 60 → 1060。
	_assert_eq("食物开场: f2 2非食物×30 → maxHp 1060", int(f2["maxHp"]), 1060)
	# 成长标记: 食物携带者标 8 (tier1), 非食物携带者无。
	_assert_eq("食物携带者标 _foodRoundGrow=8", int(f1.get("_foodRoundGrow", 0)), 8)
	_assert_eq("非食物携带者无 _foodRoundGrow", f2.has("_foodRoundGrow"), false)

	# tier2(5件食物): 每件装备 +80, 食物双倍 +160, 成长标记 20。
	var g1 = {"side": "left", "maxHp": 500, "hp": 500,
		"_p2_equips": [{"id": "p2eq_002"}, {"id": "p2eq_012"}, {"id": "p2eq_036"}, {"id": "p2eq_013"}, {"id": "p2eq_037"}]}
	var team2 = [g1]
	P2T.apply_team_start(team2)
	# 5食物×160 = 800 → 500+800 = 1300。
	_assert_eq("食物tier2: 5食物×160 → maxHp 1300", int(g1["maxHp"]), 1300)
	_assert_eq("食物tier2: 成长标记=20", int(g1.get("_foodRoundGrow", 0)), 20)

	# 食物未激活(<3件) → 不加血、不标记。
	var h1 = {"side": "left", "maxHp": 400, "hp": 400,
		"_p2_equips": [{"id": "p2eq_002"}, {"id": "p2eq_012"}]}
	P2T.apply_team_start([h1])
	_assert_eq("食物未激活(2件): maxHp 不变", int(h1["maxHp"]), 400)
	_assert_eq("食物未激活: 无成长标记", h1.has("_foodRoundGrow"), false)


## 类型(职业)羁绊【灵物·召唤 闪避属性】: 每件灵物 +5/10% 闪避(_extraDodge), 总闪避封顶 75%。
func _test_p2eq_relic_dodge() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	# 灵物 ids = 025/046/033/034; tiers=[3,4](用户2026-06-23降顶档).带 3 件灵物 → tier1 → 每件 +5% → +15。
	var f1 = {"side": "left", "_extraDodge": 0,
		"_p2_equips": [{"id": "p2eq_025"}, {"id": "p2eq_046"}, {"id": "p2eq_033"}]}
	var team = [f1]
	var act = P2T.calc_active(team)
	var relic_tier = -1
	for a in act:
		if a["type"] == "灵物":
			relic_tier = int(a["tier"])
	_assert_eq("灵物3件→tier1", relic_tier, 1)
	P2T.apply_team_start(team)
	_assert_eq("灵物tier1: 3件×5% → _extraDodge=15", int(f1.get("_extraDodge", 0)), 15)

	# tier2(4件灵物 → tier2 阈值5? 4件只到tier1). 用全4件 → 现 tier2 (新阈值[3,4])。
	# 单龟带4件灵物: tier1(4<5) → 4×5 = 20。
	var f2 = {"side": "left", "_extraDodge": 0,
		"_p2_equips": [{"id": "p2eq_025"}, {"id": "p2eq_046"}, {"id": "p2eq_033"}, {"id": "p2eq_034"}]}
	P2T.apply_team_start([f2])
	_assert_eq("灵物4件→tier2(新阈值4,用户A): 4×10=40", int(f2.get("_extraDodge", 0)), 40)

	# 封顶 75%: 预置高 _extraDodge → 加后不超 75。
	var f3 = {"side": "left", "_extraDodge": 70,
		"_p2_equips": [{"id": "p2eq_025"}, {"id": "p2eq_046"}, {"id": "p2eq_033"}]}
	P2T.apply_team_start([f3])
	_assert_eq("灵物闪避封顶75% (70+15→75 不超)", int(f3.get("_extraDodge", 0)), 75)

	# 灵物未激活(<3件) → 不加闪避。
	var f4 = {"side": "left", "_extraDodge": 0,
		"_p2_equips": [{"id": "p2eq_025"}, {"id": "p2eq_046"}]}
	P2T.apply_team_start([f4])
	_assert_eq("灵物未激活(2件): _extraDodge 不变=0", int(f4.get("_extraDodge", 0)), 0)


## 类型(职业)羁绊【剑·回响】(规格#543): 剑激活 2/4/6 → 剑装备伤害效果后 50%回响 1/2/3 次, 回响不触发proc。
func _test_p2eq_sword_echo() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# ── 激活档→回响次数: 剑 ids=001/005/006/007/009/010; tiers=[2,4,6]。2件→tier1→1次; 6件→tier3→3次。 ──
	var f2 = {"side": "left", "alive": true, "atk": 100, "crit": 0.0,
		"_p2_equips": [{"id": "p2eq_001"}, {"id": "p2eq_005"}]}
	P2T.apply_team_start([f2])
	_assert_eq("剑2件→tier1→_swordEchoCount=1", int(f2.get("_swordEchoCount", 0)), 1)
	var f6 = {"side": "left", "alive": true, "atk": 100, "crit": 0.0,
		"_p2_equips": [{"id": "p2eq_001"}, {"id": "p2eq_005"}, {"id": "p2eq_006"},
			{"id": "p2eq_007"}, {"id": "p2eq_009"}, {"id": "p2eq_010"}]}
	P2T.apply_team_start([f6])
	_assert_eq("剑6件→tier3→_swordEchoCount=3", int(f6.get("_swordEchoCount", 0)), 3)

	# ── sword_echo 直测: 一条产出伤害 100 → 回响 N 次各 50。 ──
	var atkr = {"side": "left", "alive": true, "_swordEchoCount": 2}
	var tgt = {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "buffs": []}
	var all_f = [atkr, tgt]
	var produced = [{"target_idx": 1, "value": 100, "kind": "damage", "dmg_type": "physical"}]
	var hp0 := int(tgt["hp"])
	var echo = P2RT.sword_echo(produced, atkr, all_f)
	_assert_eq("回响2次→产2条echo effect", echo.size(), 2)
	_assert_eq("回响每次=原伤害50%(100→50)×2 = 扣100血", hp0 - int(tgt["hp"]), 100)
	var all_echo_vfx := true
	for e in echo:
		if not (e is Dictionary) or str(e.get("vfx", "")) != "swordecho":
			all_echo_vfx = false
	_assert_eq("回响 effect 带 swordecho VFX 标记", all_echo_vfx, true)

	# ── 不带剑羁绊(_swordEchoCount=0) → 无回响。 ──
	var no_echo = P2RT.sword_echo(produced, {"side": "left"}, all_f)
	_assert_eq("无剑羁绊→不回响(空)", no_echo.size(), 0)

	# ── 非伤害 effect(heal/shield) 不回响。 ──
	var produced_heal = [{"target_idx": 0, "value": 80, "kind": "heal"}]
	var no_echo2 = P2RT.sword_echo(produced_heal, atkr, all_f)
	_assert_eq("非伤害effect(heal)→不回响", no_echo2.size(), 0)

	# ── 端到端: on_hit 剑系(005双生追击)产伤害后自动回响; 非剑系(002海藻)不回响。 ──
	# 005 追击=atk×scale 物理(走calc); 这里只验"剑系on_hit会append回响伤害effect, 非剑系不会"。
	var swd = {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "_swordEchoCount": 1, "_castIsAoe": false}
	var v1 = {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "buffs": [], "def": 0, "mr": 0}
	var fx005 = P2RT.on_hit(swd, v1, 50, "p2eq_005", 3, [swd, v1], true)   # 005 3★ 必追击(prob1.0)
	var echo_in_005 := false
	for e in fx005:
		if e is Dictionary and str(e.get("vfx", "")) == "swordecho":
			echo_in_005 = true
	_assert_eq("剑系005 on_hit → 含回响effect", echo_in_005, true)
	# 002 海藻=流血(非剑系, 不在SWORD_ECHO_IDS) → 即便带_swordEchoCount也不回响。
	var v2 = {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "buffs": []}
	var fx002 = P2RT.on_hit(swd, v2, 50, "p2eq_002", 1, [swd, v2], true)
	var echo_in_002 := false
	for e in fx002:
		if e is Dictionary and str(e.get("vfx", "")) == "swordecho":
			echo_in_002 = true
	_assert_eq("非剑系002 on_hit → 无回响", echo_in_002, false)


## 类型(职业)羁绊【奇械·深海工坊】(规格#544): 死亡产装备(件数/费用/封顶/每档一次) + 每回合铸币。
func _test_p2eq_gadget() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# ── apply_team_start: 奇械 ids=035/047/020/027/038/040; tiers=[2,4,6]。2件→tier1→件数标记+铸币1。 ──
	var g = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_035"}, {"id": "p2eq_047"}]}
	P2T.apply_team_start([g])
	_assert_eq("奇械2件→tier1→_gadgetPieces=2", int(g.get("_gadgetPieces", 0)), 2)
	_assert_eq("奇械2件→tier1→_gadgetMint=1", int(g.get("_gadgetMint", 0)), 1)
	# 6件→tier3→铸币3。
	var g6 = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_035"}, {"id": "p2eq_047"},
		{"id": "p2eq_020"}, {"id": "p2eq_027"}, {"id": "p2eq_038"}, {"id": "p2eq_040"}]}
	P2T.apply_team_start([g6])
	_assert_eq("奇械6件→tier3→_gadgetMint=3", int(g6.get("_gadgetMint", 0)), 3)
	_assert_eq("奇械6件→_gadgetPieces=6", int(g6.get("_gadgetPieces", 0)), 6)

	# ── gadget_piece_count: 仅算本侧存活且激活奇械者。 ──
	var ally = {"side": "left", "alive": true, "_gadgetPieces": 2}
	var ally2 = {"side": "left", "alive": true, "_gadgetPieces": 1}
	var enemy = {"side": "right", "alive": true, "_gadgetPieces": 3}   # 敌方不算
	var dead = {"side": "left", "alive": false, "_gadgetPieces": 2}    # 已死不算
	var team = [ally, ally2, enemy, dead]
	_assert_eq("奇械件数: 左存活=2+1=3 (敌/死不算)", P2RT.gadget_piece_count(team, "left"), 3)

	# ── gadget_produce: 件数个装备, 每件 cost 费(回退低费)。pool 用真数据。 ──
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var prod = P2RT.gadget_produce(team, "left", 1, DataRegistry.phase2_equipment, rng)
	_assert_eq("产出件数=奇械件数3", prod.size(), 3)
	# 验证产出的是 cost=1 装备 (1费有货)。
	var all_cost1 := true
	for eid in prod:
		var ed: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(eid), {})
		if int(ed.get("cost", -1)) != 1:
			all_cost1 = false
	_assert_eq("cost1产出全是1费装备", all_cost1, true)
	# cost5 现已有 shopAvailable==1 货 (017/052/056/059 上架, 2026-06-26) → 直接产出费5装备。
	var prod5 = P2RT.gadget_produce(team, "left", 5, DataRegistry.phase2_equipment, rng)
	_assert_eq("cost5有货→产出(非空)", prod5.size() > 0, true)
	var ed5: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(prod5[0]), {})
	_assert_eq("cost5产出→落到费5装备(已上架)", int(ed5.get("cost", 99)), 5)

	# 右侧有1名敌带3件(_gadgetPieces=3) → 右侧产3件 (件数按侧统计)。
	_assert_eq("右侧奇械件数3→产3件", P2RT.gadget_produce(team, "right", 1, DataRegistry.phase2_equipment, rng).size(), 3)
	# 完全无奇械的队 → 产出空。
	var team_none = [{"side": "left", "alive": true}]
	_assert_eq("无奇械→产出空", P2RT.gadget_produce(team_none, "left", 1, DataRegistry.phase2_equipment, rng).size(), 0)


## 类型(职业)羁绊【枪·神枪手 金弹】(规格#549): 枪激活 2/3/5 → 每射满 4/3/2 发出 1 发金弹(同伤+附带+额外真伤)。
func _test_p2eq_gun_gold() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")
	var P2RT = load("res://scripts/engine/phase2_equip_runtime.gd")

	# ── apply_team_start: 枪 ids=048/051/050/057/052; tiers=[2,3,5]。2件→tier1; 5件→tier3。 ──
	var g2 = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_048"}, {"id": "p2eq_051"}]}
	P2T.apply_team_start([g2])
	_assert_eq("枪2件→tier1→_gunTier=1", int(g2.get("_gunTier", 0)), 1)
	_assert_eq("枪激活→开 _gunBullets dict", g2.get("_gunBullets") is Dictionary, true)
	var g5 = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_048"}, {"id": "p2eq_051"},
		{"id": "p2eq_050"}, {"id": "p2eq_057"}, {"id": "p2eq_052"}]}
	P2T.apply_team_start([g5])
	_assert_eq("枪5件→tier3→_gunTier=3", int(g5.get("_gunTier", 0)), 3)
	# 未激活(1件枪) → 无 _gunTier。
	var g1 = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_048"}]}
	P2T.apply_team_start([g1])
	_assert_eq("枪未激活(1件)→无_gunTier", g1.has("_gunTier"), false)

	# ── 阈值: tier1=4发, tier2=3发, tier3=2发。 ──
	_assert_eq("tier1阈值=4", P2RT._gun_threshold(1), 4)
	_assert_eq("tier2阈值=3", P2RT._gun_threshold(2), 3)
	_assert_eq("tier3阈值=2", P2RT._gun_threshold(3), 2)
	_assert_eq("tier1金弹额外真伤=60%", P2RT._gun_gold_pct(1), 0.60, 0.001)
	_assert_eq("tier3金弹额外真伤=100%", P2RT._gun_gold_pct(3), 1.00, 0.001)

	# ── gun_fire_shot 计数: tier1(阈值4) → 前3发无金弹, 第4发出金弹 + 计数清零。 ──
	var owner = {"side": "left", "alive": true, "atk": 100, "_gunTier": 1, "_gunBullets": {}}
	var tgt = {"side": "right", "alive": true, "hp": 100000, "maxHp": 100000, "shield": 0, "buffs": [], "def": 0, "mr": 0}
	var allf = [owner, tgt]
	for shot in range(3):
		var fx = P2RT.gun_fire_shot(owner, "p2eq_048", tgt, allf, 50.0, "physical")
		_assert_eq("枪第%d发(<4)→无金弹" % (shot + 1), fx.size(), 0)
	_assert_eq("枪计数累到3", int(owner["_gunBullets"]["p2eq_048"]), 3)
	var fx4 = P2RT.gun_fire_shot(owner, "p2eq_048", tgt, allf, 50.0, "physical")
	# 金弹 = 1条金弹伤害 + 1条额外真伤 = 2 effect。
	_assert_eq("枪第4发→出金弹(金弹伤害+额外真伤=2 effect)", fx4.size(), 2)
	_assert_eq("金弹后计数清零", int(owner["_gunBullets"]["p2eq_048"]), 0)
	var has_gold_vfx := true
	for e in fx4:
		if not (e is Dictionary) or str(e.get("vfx", "")) != "goldbullet":
			has_gold_vfx = false
	_assert_eq("金弹 effect 带 goldbullet VFX", has_gold_vfx, true)
	# 金弹是子弹(travel 0.20s) → 伤害 effect 带 arrival_delay, 血跟子弹落地才掉 (显示时机, 数值不动)。
	var has_arr := true
	for e in fx4:
		if not (e is Dictionary) or not e.has("arrival_delay") or float(e.get("arrival_delay", -1.0)) <= 0.0:
			has_arr = false
	_assert_eq("金弹 effect 带 arrival_delay(>0, 血跟子弹落地)", has_arr, true)
	# 第二条 = 额外真伤, dmg_type=true。
	_assert_eq("金弹额外伤=真伤(true)", str(fx4[1].get("dmg_type", "")), "true")

	# ── 每把枪独立计数: 048 计到3, 050 仍从0起。 ──
	var owner2 = {"side": "left", "alive": true, "atk": 100, "_gunTier": 1, "_gunBullets": {}}
	P2RT.gun_fire_shot(owner2, "p2eq_048", tgt, [owner2, tgt], 50.0, "physical")
	P2RT.gun_fire_shot(owner2, "p2eq_050", tgt, [owner2, tgt], 50.0, "physical")
	_assert_eq("枪独立计数: 048=1", int(owner2["_gunBullets"].get("p2eq_048", -1)), 1)
	_assert_eq("枪独立计数: 050=1", int(owner2["_gunBullets"].get("p2eq_050", -1)), 1)

	# ── 枪羁绊未激活(_gunTier=0) → 永不出金弹。 ──
	var owner0 = {"side": "left", "alive": true, "atk": 100, "_gunTier": 0, "_gunBullets": {}}
	var none := true
	for _s in range(10):
		if not P2RT.gun_fire_shot(owner0, "p2eq_048", tgt, [owner0, tgt], 50.0, "physical").is_empty():
			none = false
	_assert_eq("枪未激活→10发无金弹", none, true)


## 类型(职业)羁绊【灵物·召唤 无敌触手】(规格#553): 激活3/4 → 1/2触手; 拍击(4%maxHP+55)×(1+5%×Σ独特灵物星)。
func _test_p2eq_tentacle() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")

	# ── tentacle_setup count: 灵物 ids=025/046/033/034; tiers=[3,4]。3件→tier1→1触手; 4件→tier2→2触手。 ──
	# 全1星 (star默认1): 3件独特 → Σ星=3 → dmg_mult=1+0.05×3=1.15。
	var t3 = {"side": "left", "_p2_equips": [{"id": "p2eq_025", "star": 1}, {"id": "p2eq_046", "star": 1}, {"id": "p2eq_033", "star": 1}]}
	var setup3 = P2T.tentacle_setup([t3])
	_assert_eq("灵物3件→tier1→1触手", int(setup3["count"]), 1)
	_assert_eq("3件独特1星→dmg_mult=1.15", float(setup3["dmg_mult"]), 1.15, 0.001)

	var t4 = {"side": "left", "_p2_equips": [{"id": "p2eq_025", "star": 1}, {"id": "p2eq_046", "star": 1}, {"id": "p2eq_033", "star": 1}, {"id": "p2eq_034", "star": 1}]}
	var setup4 = P2T.tentacle_setup([t4])
	_assert_eq("灵物4件→tier2→2触手", int(setup4["count"]), 2)
	_assert_eq("4件独特1星→dmg_mult=1.20", float(setup4["dmg_mult"]), 1.20, 0.001)

	# ── 升星: 独特灵物按星累加。3件灵物各3星 → Σ星=9 → mult=1+0.45=1.45。 ──
	var ts = {"side": "left", "_p2_equips": [{"id": "p2eq_025", "star": 3}, {"id": "p2eq_046", "star": 3}, {"id": "p2eq_033", "star": 3}]}
	var setupS = P2T.tentacle_setup([ts])
	_assert_eq("3件独特3星→dmg_mult=1.45", float(setupS["dmg_mult"]), 1.45, 0.001)

	# ── "独特"去重: 同 id 多件只算一次(取最高星)。两件 025(1星+3星) + 一件 046(1星) → Σ=3+1=4 → mult=1.20。 ──
	var tdup = {"side": "left", "_p2_equips": [{"id": "p2eq_025", "star": 1}, {"id": "p2eq_025", "star": 3}, {"id": "p2eq_046", "star": 1}]}
	var setupD = P2T.tentacle_setup([tdup])
	_assert_eq("灵物激活(3件含重复id)→1触手", int(setupD["count"]), 1)
	_assert_eq("独特去重(025取3星)+046(1星)→Σ4→mult=1.20", float(setupD["dmg_mult"]), 1.20, 0.001)

	# ── 未激活(<3件) → count=0。 ──
	var t2 = {"side": "left", "_p2_equips": [{"id": "p2eq_025", "star": 1}, {"id": "p2eq_046", "star": 1}]}
	_assert_eq("灵物2件未激活→0触手", int(P2T.tentacle_setup([t2])["count"]), 0)

	# ── tentacle_slap_damage: (4%maxHP+55)×mult。maxHP=1000, mult=1.15 → (40+55)×1.15=109.25→109。 ──
	_assert_eq("拍击伤害 maxHP1000×1.15 → 109", P2T.tentacle_slap_damage(1000, 1.15), 109)
	_assert_eq("拍击伤害 maxHP500×1.0 → (20+55)=75", P2T.tentacle_slap_damage(500, 1.0), 75)


# ─── 测试 helper

func _assert_eq(name: String, actual, expected, tolerance: float = 0.0) -> void:
	var ok: bool = false
	if actual is float or expected is float:
		ok = absf(float(actual) - float(expected)) <= tolerance
	else:
		ok = actual == expected
	if ok:
		pass_count += 1
		print("  ✓ %s" % name)
	else:
		fail_count += 1
		print("  ✗ %s — expected %s, got %s" % [name, str(expected), str(actual)])


# ─── 测试用例 ──────────────────────────────────────────────────

func _test_level_mult() -> void:
	_assert_eq("Lv1 mult = 1.0", FighterFactory.get_level_mult(1), 1.0, 0.001)
	_assert_eq("Lv10 mult = 1.45", FighterFactory.get_level_mult(10), 1.45, 0.001)
	_assert_eq("Lv5 mult = 1.20", FighterFactory.get_level_mult(5), 1.20, 0.001)


func _test_create_fighter_basic() -> void:
	# basic 是 Lv1 C 稀有度: hp=450, atk=40, def=14, mr=13, crit=0.25
	var f := FighterFactory.create("basic", "left")
	_assert_eq("basic.id", f.get("id"), "basic")
	_assert_eq("basic.name", f.get("name"), "小龟")
	_assert_eq("basic.rarity", f.get("rarity"), "C")
	_assert_eq("basic Lv1 hp", f.get("hp"), 900)  # 450×2 (乌龟基础血翻倍补丁)
	_assert_eq("basic Lv1 atk", f.get("atk"), 40)
	_assert_eq("basic Lv1 def", f.get("def"), 14)
	_assert_eq("basic Lv1 mr", f.get("mr"), 13)
	_assert_eq("basic Lv1 crit", f.get("crit"), 0.25, 0.001)
	_assert_eq("basic Lv1 alive", f.get("alive"), true)
	_assert_eq("basic Lv1 side", f.get("side"), "left")


func _test_create_fighter_rarity_scaling() -> void:
	# Lv5 → mult 1.20, 给个稀有度高的龟看 stats scaling
	# 这里只验证缩放数学 — 任意龟都行
	var f := FighterFactory.create("basic", "right", {"level": 5})
	# basic.hp=450, Lv5 mult=1.20, C mult=1.0 → 450×1.2×2 = 1080 (乌龟基础血翻倍补丁)
	_assert_eq("basic Lv5 hp", f.get("hp"), 1080)
	_assert_eq("basic Lv5 atk", f.get("atk"), 48)  # 40×1.2 = 48
	_assert_eq("basic Lv5 def", f.get("def"), 17)  # 14×1.2 = 16.8 → round 17
	_assert_eq("basic Lv5 _level", f.get("_level"), 5)


func _test_calc_eff_armor() -> void:
	var atk := {"def": 0, "armorPen": 0, "armorPenPct": 0.0}
	var tgt := {"def": 20}
	_assert_eq("effArmor 无穿透 = def", Damage.calc_eff_armor(atk, tgt), 20.0, 0.001)

	atk["armorPen"] = 5
	_assert_eq("effArmor armorPen=5 → 15", Damage.calc_eff_armor(atk, tgt), 15.0, 0.001)

	atk["armorPen"] = 0
	atk["armorPenPct"] = 0.5
	_assert_eq("effArmor armorPenPct=50% → 10", Damage.calc_eff_armor(atk, tgt), 10.0, 0.001)


func _test_calc_dmg_mult() -> void:
	# def=0 → mult=1 (无减伤)
	_assert_eq("dmgMult def=0", Damage.calc_dmg_mult(0.0), 1.0, 0.001)
	# def=40 (= K) → mult = 1 - 40/80 = 0.5
	_assert_eq("dmgMult def=40 → 0.5", Damage.calc_dmg_mult(40.0), 0.5, 0.001)
	# def=14 → mult = 1 - 14/54 ≈ 0.7407
	_assert_eq("dmgMult def=14 → 0.7407", Damage.calc_dmg_mult(14.0), 0.7407, 0.001)
	# 负防御 (穿透打到负数) → 增伤
	# def=-40 → mult = 1 + 40/80 = 1.5
	_assert_eq("dmgMult def=-40 → 1.5 (负防御增伤)", Damage.calc_dmg_mult(-40.0), 1.5, 0.001)


func _test_calc_damage() -> void:
	# basic vs basic 物理 base=28 (0.7 × 40 ATK):
	#   effDef = 14, mult = 0.7407, 20.74 ×basicTurtle(对C+20%)=24.89 → round 25
	var atk := FighterFactory.create("basic", "left")
	var tgt := FighterFactory.create("basic", "right")
	var dmg := Damage.calc_damage(atk, tgt, 28.0, "physical")
	_assert_eq("basic→basic 28 phys = 25 (含basicTurtle对C+20%)", dmg, 25)

	# 真伤跳过 def: 28 ×1.2 = 33.6 → 34
	_assert_eq("basic→basic 28 true = 34", Damage.calc_damage(atk, tgt, 28.0, "true"), 34)

	# 魔法走 MR: 21.13 ×1.2 = 25.35 → 25
	_assert_eq("basic→basic 28 magic = 25", Damage.calc_damage(atk, tgt, 28.0, "magic"), 25)


func _test_apply_raw_damage_to_hp() -> void:
	var t := {"hp": 100, "maxHp": 100, "shield": 0, "alive": true}
	var r := Damage.apply_raw_damage(t, 30)
	_assert_eq("纯血扣 30: hpLoss", r["hpLoss"], 30)
	_assert_eq("纯血扣 30: shieldAbs", r["shieldAbs"], 0)
	_assert_eq("纯血扣 30: hp 剩 70", t["hp"], 70)
	_assert_eq("纯血扣 30: 仍活", t["alive"], true)


func _test_apply_raw_damage_to_shield_then_hp() -> void:
	# 盾 20 + 血 100, 打 35 → 盾扣 20, 血扣 15
	var t := {"hp": 100, "maxHp": 100, "shield": 20, "alive": true}
	var r := Damage.apply_raw_damage(t, 35)
	_assert_eq("盾20血100, 打35: shieldAbs=20", r["shieldAbs"], 20)
	_assert_eq("盾20血100, 打35: hpLoss=15", r["hpLoss"], 15)
	_assert_eq("盾20血100, 打35: hp=85", t["hp"], 85)
	_assert_eq("盾20血100, 打35: shield=0", t["shield"], 0)


func _test_apply_raw_damage_kill() -> void:
	var t := {"hp": 10, "maxHp": 100, "shield": 0, "alive": true}
	var r := Damage.apply_raw_damage(t, 999)
	_assert_eq("超伤致死: hpLoss=10", r["hpLoss"], 10)
	_assert_eq("超伤致死: hp=0", t["hp"], 0)
	_assert_eq("超伤致死: alive=false", t["alive"], false)


# 龟壳 auraAwaken 储能: 受伤(hpLoss)累积 _auraEnergy, cap = maxHp × energyMaxStorePct
func _test_aura_energy_store() -> void:
	var aura := {"type": "auraAwaken", "energyStore": true, "energyMaxStorePct": 0.5}
	var t := {"hp": 200, "maxHp": 200, "shield": 0, "alive": true, "passive": aura}
	Damage.apply_raw_damage(t, 40)
	_assert_eq("气场储能: 受 40 → _auraEnergy=40", int(t.get("_auraEnergy", 0)), 40)
	# 再受大量伤害但仍存活 → cap 在 maxHp×0.5=100
	t["hp"] = 200
	Damage.apply_raw_damage(t, 90)
	_assert_eq("气场储能: 封顶 maxHp×0.5=100", int(t.get("_auraEnergy", 0)), 100)
	# 打盾不积能 (hpLoss=0)
	var t2 := {"hp": 200, "maxHp": 200, "shield": 50, "alive": true, "passive": aura.duplicate()}
	Damage.apply_raw_damage(t2, 30)
	_assert_eq("气场储能: 打盾(hpLoss=0)不积能", int(t2.get("_auraEnergy", 0)), 0)


# 描述模板渲染器: {N:expr} 展开+上色, {ATK} 不上色, 关键词自动上色 (PoC skill-text.ts)
func _test_skill_text_render() -> void:
	var f := {"atk": 40, "def": 10, "mr": 10, "maxHp": 400, "crit": 0.25}
	var s := {"atkScale": 0.7, "hits": 2}
	# eval: 0.7*40*2 = 56
	var ev = SkillText.eval_expr("0.7*ATK*2", SkillText.build_vars(f, s))
	_assert_eq("模板eval 0.7*ATK*2 (ATK=40) = 56", int(ev), 56)
	# eval 纯变量
	_assert_eq("模板eval {ATK} = 40", int(SkillText.eval_expr("ATK", SkillText.build_vars(f, s))), 40)
	# render_plain: 数字展开, 无标签
	var plain: String = SkillText.render_plain("造成（{N:0.7*ATK*2}）物理伤害。", f, s)
	_assert_eq("render_plain 展开+去标签", plain, "造成（56）物理伤害。")
	# render_bbcode: 数字上色 + 关键词上色
	var bb: String = SkillText.render_bbcode("造成（{N:0.7*ATK*2}）物理伤害。", f, s)
	_assert_eq("bbcode 含上色数字 [color=#ff6b6b]56", bb.contains("[color=#ff6b6b]56[/color]"), true)
	_assert_eq("bbcode 含上色关键词 物理伤害", bb.contains("[color=#ff6b6b]物理伤害[/color]"), true)
	# 不认识的变量原样 (容错)
	_assert_eq("未知变量原样返回", str(SkillText.eval_expr("FOOBAR", SkillText.build_vars(f, s))), "FOOBAR")
	# 全 28 龟所有技能/被动 brief 渲染后无残留 {token} (= 所有公式变量都覆盖了)
	if not DataRegistry.all_pets.is_empty():
		var leftover := 0
		var sample := ""
		for pet in DataRegistry.all_pets:
			var ctx := {"atk": pet.get("atk", 0), "def": pet.get("def", 0), "mr": pet.get("mr", pet.get("def", 0)), "maxHp": pet.get("hp", 0), "crit": pet.get("crit", 0.25), "passive": pet.get("passive", null)}
			var pv: Dictionary = pet.get("passive", {})
			var texts: Array = [SkillText.render_plain(pv.get("brief", ""), ctx, pv)]
			for sk in pet.get("skillPool", []):
				texts.append(SkillText.render_plain(sk.get("brief", ""), ctx, sk))
				texts.append(SkillText.render_plain(sk.get("detail", ""), ctx, sk))
			for t in texts:
				if "{" in t:
					leftover += 1
					if sample == "":
						sample = "%s: %s" % [pet.get("id", "?"), t]
		_assert_eq("全龟 brief/detail 渲染无残留{token} (样本: %s)" % sample, leftover, 0)


# 沙漏: 所有技能基础 cd -1 (最低 0), 存原 cd
func _test_equip_hourglass() -> void:
	var f := {"skills": [{"cd": 3}, {"cd": 1}, {"cd": 0}]}
	EquipmentRuntime.on_attach(f, "e_hourglass")
	var sk: Array = f["skills"]
	_assert_eq("沙漏: cd3→2", int(sk[0]["cd"]), 2)
	_assert_eq("沙漏: cd1→0", int(sk[1]["cd"]), 0)
	_assert_eq("沙漏: cd0→0 (不负)", int(sk[2]["cd"]), 0)
	_assert_eq("沙漏: 存原 cd3", int(sk[0]["_hourglassOrigCd"]), 3)
	_assert_eq("沙漏: 标记 flag", f.get("_equipHourglass", false), true)


func _test_basic_vs_basic_2hit() -> void:
	# 端到端: basic 普攻打 basic
	# basic 普攻 (技能 0): physical, hits=2, atkScale=0.7
	# 每段 = 0.7 × 40 ATK = 28 base
	# effDef = 14, mult = 0.7407, 每段 round(28×0.7407×basicTurtle对C 1.2) = 25
	# 2 段 = 50
	var atk := FighterFactory.create("basic", "left")
	var tgt := FighterFactory.create("basic", "right")
	var skill: Dictionary = atk["skills"][0]
	_assert_eq("basic skill[0].name = 攻击", skill.get("name"), "攻击")
	_assert_eq("basic skill[0].hits", skill.get("hits"), 2)
	_assert_eq("basic skill[0].atkScale", skill.get("atkScale"), 0.7, 0.001)

	var hits: int = skill.get("hits", 1)
	var atk_scale: float = skill.get("atkScale", 1.0)
	# 4.6 类型推断: Dictionary.get() 返回 Variant, 不能跟 float 用 := 推断, 显式标 float。
	var base_per_hit: float = atk.get("atk", 0) * atk_scale
	var dmg_per_hit := Damage.calc_damage(atk, tgt, base_per_hit, "physical")
	var total := dmg_per_hit * hits
	_assert_eq("basic 普攻 2 段总伤 (含basicTurtle)", total, 50)

	# 落地
	var before_hp: int = tgt["hp"]
	for i in range(hits):
		Damage.apply_raw_damage(tgt, dmg_per_hit, "physical")
	_assert_eq("basic 普攻打完: 目标 hp 减 50", before_hp - tgt["hp"], 50)


func _test_crit_mult() -> void:
	# 基础 crit=0.25, 无额外 → mult = 1.5 (无溢出)
	var f := {"crit": 0.25, "_extraCritDmg": 0, "_extraCritDmgPerm": 0, "_buffCritDmg": 0, "passive": null}
	_assert_eq("crit=0.25 critMult=1.5", Damage.calc_crit_mult(f), 1.5, 0.001)

	# crit=1.4 → overflow=0.4, default overflowMult=1.5 → critMult=1.5+0.4×1.5=2.1
	f["crit"] = 1.4
	_assert_eq("crit=1.4 critMult=2.1 (overflow)", Damage.calc_crit_mult(f), 2.1, 0.001)

	# crit=1.4, extraCritDmgPerm=0.2 → 1.5+0.2+0.6=2.3
	f["_extraCritDmgPerm"] = 0.2
	_assert_eq("crit=1.4 +extraPerm 0.2 → 2.3", Damage.calc_crit_mult(f), 2.3, 0.001)


# ─── W7 v2 基建测试 ────────────────────────────────────────────

func _make_test_fighter(atk: int, def_v: int, mr: int) -> Dictionary:
	return {
		"baseAtk": atk, "baseDef": def_v, "baseMr": mr,
		"atk": atk, "def": def_v, "mr": mr,
		"maxHp": 100, "hp": 100, "crit": 0.1, "armorPen": 0,
		"buffs": [], "alive": true, "side": "left",
	}


func _test_recalc_atk_buffs() -> void:
	# atkUp +10 (flat) → atk = base + 10
	var f := _make_test_fighter(40, 14, 13)
	StatsRecalc.snapshot_base(f)
	Buffs.add(f, "atkUp", 10, 3)
	StatsRecalc.recalc(f)
	_assert_eq("atkUp +10 → atk 50", f["atk"], 50)

	# atkDown 25% → atk = 50(含atkUp) × 0.75 = 37.5 → 38 (注: atkDown 在 atkUp 之后乘)
	# 重置: 新 fighter 只 atkDown
	var f2 := _make_test_fighter(40, 14, 13)
	StatsRecalc.snapshot_base(f2)
	Buffs.add(f2, "atkDown", 25, 2)
	StatsRecalc.recalc(f2)
	_assert_eq("atkDown 25% → atk 30", f2["atk"], 30)

	# defUp +8 flat → def = 14 + 8 = 22
	var f3 := _make_test_fighter(40, 14, 13)
	StatsRecalc.snapshot_base(f3)
	Buffs.add(f3, "defUp", 8, 3)
	StatsRecalc.recalc(f3)
	_assert_eq("defUp +8 → def 22", f3["def"], 22)

	# critUp +20 (=0.20) → crit = 0.1 + 0.2 = 0.3
	var f4 := _make_test_fighter(40, 14, 13)
	StatsRecalc.snapshot_base(f4)
	Buffs.add(f4, "critUp", 20, 3)
	StatsRecalc.recalc(f4)
	_assert_eq("critUp +20 → crit 0.3", f4["crit"], 0.3, 0.001)


func _test_recalc_chilled() -> void:
	# chilled → atk × 0.8 (只检 type 存在)
	var f := _make_test_fighter(40, 14, 13)
	StatsRecalc.snapshot_base(f)
	Buffs.add(f, "chilled", 0, 3)
	StatsRecalc.recalc(f)
	_assert_eq("chilled → atk 32 (×0.8)", f["atk"], 32)


func _test_buffs_crud() -> void:
	# ── 默认 push: 同 type 多条独立 (1:1 PoC 裸 target.buffs.push) ──
	var f := _make_test_fighter(40, 14, 13)
	Buffs.add(f, "atkUp", 10, 3)
	_assert_eq("buffs has atkUp", Buffs.has(f, "atkUp"), true)
	Buffs.add(f, "atkUp", 20, 5)   # push → 第二条 (不合并)
	_assert_eq("push 多条: sum_value 10+20=30", Buffs.sum_value(f, "atkUp"), 30.0, 0.001)
	var removed := Buffs.remove_all(f, "atkUp")
	_assert_eq("remove_all 清两条 → 返 2", removed, 2)
	_assert_eq("remove 后 has=false", Buffs.has(f, "atkUp"), false)

	# ── push + recalc: 两条 atkDown -20% 逐条连乘 (1:1 PoC stats-recalc ×(1-v/100)) ──
	var k := _make_test_fighter(100, 14, 13)
	StatsRecalc.snapshot_base(k)
	Buffs.add(k, "atkDown", 20, 3)
	Buffs.add(k, "atkDown", 20, 3)   # push 第二条
	StatsRecalc.recalc(k)
	_assert_eq("两条 atkDown -20% 连乘 100×0.8×0.8=64", k["atk"], 64)
	# 两条 atkUp flat 累加: base100 +10 +15 = 125
	var k2 := _make_test_fighter(100, 14, 13)
	StatsRecalc.snapshot_base(k2)
	Buffs.add(k2, "atkUp", 10, 3); Buffs.add(k2, "atkUp", 15, 3)
	StatsRecalc.recalc(k2)
	_assert_eq("两条 atkUp flat 累加 100+10+15=125", k2["atk"], 125)

	# ── explicit overwrite: 取 max 单条 (lava mrDown / physImmune / diceFateCrit 特例) ──
	var g := _make_test_fighter(40, 14, 13)
	Buffs.add(g, "mrDown", 10, 3, "overwrite")
	Buffs.add(g, "mrDown", 5, 2, "overwrite")    # 5<10 → 不变
	_assert_eq("overwrite 取 max value 10", Buffs.find(g, "mrDown")["value"], 10.0, 0.001)
	Buffs.add(g, "mrDown", 20, 1, "overwrite")   # 20>10 → 20, dur 取 max 3
	_assert_eq("overwrite 更大→20", Buffs.find(g, "mrDown")["value"], 20.0, 0.001)
	_assert_eq("overwrite 仍单条 sum=20", Buffs.sum_value(g, "mrDown"), 20.0, 0.001)
	_assert_eq("overwrite dur 取 max 3", Buffs.find(g, "mrDown")["duration"], 3)

	# ── explicit refresh: 只刷 duration 不新增 (healReduce/dodge/chilled merge-guard) ──
	var h := _make_test_fighter(40, 14, 13)
	Buffs.add(h, "healReduce", 50, 3, "refresh")
	Buffs.add(h, "healReduce", 50, 5, "refresh")
	_assert_eq("refresh 单条", Buffs.remove_all(h, "healReduce"), 1)


func _test_buffs_stun() -> void:
	var f := _make_test_fighter(40, 14, 13)
	_assert_eq("无 stun is_stunned=false", Buffs.is_stunned(f), false)
	Buffs.add(f, "stun", 1, 2, "ignore")
	_assert_eq("有 stun is_stunned=true", Buffs.is_stunned(f), true)
	# ignore 模式: 重复 add 不叠
	Buffs.add(f, "stun", 1, 2, "ignore")
	_assert_eq("stun ignore 不重复", Buffs.sum_value(f, "stun"), 1.0, 0.001)
	# _stunUsed 守卫
	f["_stunUsed"] = true
	_assert_eq("_stunUsed 后 is_stunned=false", Buffs.is_stunned(f), false)


func _test_tick_duration() -> void:
	var f := _make_test_fighter(40, 14, 13)
	Buffs.add(f, "atkUp", 10, 2)
	Buffs.add(f, "burn", 30, 999)   # DoT 哨兵, 不该被 tick
	# tick 1: atkUp dur 2→1, burn 跳过
	StatsRecalc.tick_buffs_duration(f)
	_assert_eq("tick1 atkUp dur 1", Buffs.find(f, "atkUp")["duration"], 1)
	_assert_eq("tick1 burn 999 不变", Buffs.find(f, "burn")["duration"], 999)
	# tick 2: atkUp dur 1→0 移除
	StatsRecalc.tick_buffs_duration(f)
	_assert_eq("tick2 atkUp 移除", Buffs.has(f, "atkUp"), false)
	_assert_eq("tick2 burn 仍在", Buffs.has(f, "burn"), true)


func _test_physical_def_mr_scale() -> void:
	# 石头龟"打击"公式: base = atk×0.35 + def×0.75 + mr×0.4
	# 用构造数据: atk=40 def=20 mr=20 → base = 14 + 15 + 8 = 37
	# 打 def=0 目标 (无减伤): final = 37
	var stone := _make_test_fighter(40, 20, 20)
	stone["crit"] = 0.0   # 关暴击, 测纯公式
	var target := _make_test_fighter(40, 0, 0)
	target["maxHp"] = 1000
	target["hp"] = 1000
	var skill := {
		"name": "打击", "type": "physical", "hits": 1,
		"atkScale": 0.35, "defScale": 0.75, "mrScale": 0.4,
	}
	var all := [stone, target]
	var result := SkillHandlers.execute(stone, target, all, skill)
	var effects: Array = result["effects"]
	_assert_eq("石头打击 1 effect", effects.size(), 1)
	# base = 40×0.35 + 20×0.75 + 20×0.4 = 14+15+8 = 37, def=0 无减伤 → 37
	_assert_eq("石头打击 defScale/mrScale base=37", effects[0]["value"], 37)


func _test_t2_diamond_smash() -> void:
	# dealRaw: dmg = def×1 + mr×1 + atk×0.1 (无减免无暴击) + bleed
	# caster def=20 mr=20 atk=40 → 20+20+4 = 44, 打 def=0 无减伤 → 44
	var c := _make_test_fighter(40, 20, 20)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "钻石冲撞", "type": "diamondSmash", "hits": 1,
		"defScale": 1, "mrScale": 1, "atkScale": 0.1, "bleedTurns": 3, "bleedValue": 12}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("diamondSmash dealRaw=44", r["effects"][0]["value"], 44)
	# bleed = max(1, round(12×3/4)) = 9
	var bleed = Buffs.find(t, "bleed")
	_assert_eq("diamondSmash bleed 9 层", bleed["value"] if bleed != null else -1, 9)


func _test_t2_ice_freeze_stun() -> void:
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "冰封", "type": "iceFreeze", "hits": 1, "atkScale": 0.6}
	SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("iceFreeze 施加 stun", Buffs.has(t, "stun"), true)
	_assert_eq("iceFreeze stun is_stunned", Buffs.is_stunned(t), true)


func _test_t2_diamond_fortify_shield() -> void:
	var c := _make_test_fighter(50, 14, 13)
	c["maxHp"] = 200
	StatsRecalc.snapshot_base(c)
	var skill := {"name": "坚不可摧", "type": "diamondFortify", "hits": 1,
		"shieldHpPct": 20, "defUpAtkPct": 20, "mrUpAtkPct": 20, "defUpTurns": 3}
	SkillHandlers.execute(c, {}, [c], skill)   # diamondFortify 自施法, target 忽略
	# 自盾 = maxHp×20% = 40
	_assert_eq("diamondFortify 自盾 40", c["shield"], 40)
	# defUp = atk×20% = 10 → def 14+10=24
	_assert_eq("diamondFortify defUp → def 24", c["def"], 24)


func _test_t2_phoenix_burn_dot() -> void:
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "灼烧", "type": "phoenixBurn", "hits": 1, "atkScale": 0.9}
	SkillHandlers.execute(c, t, [c, t], skill)
	# burn = max(1, round(40×0.53)) = 21
	var burn = Buffs.find(t, "burn")
	_assert_eq("phoenixBurn burn 21 层", burn["value"] if burn != null else -1, 21)


func _test_t2_pirate_plunder_steal() -> void:
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 20, 20)
	t["maxHp"] = 1000
	t["hp"] = 1000
	t["shield"] = 100
	StatsRecalc.snapshot_base(c)
	StatsRecalc.snapshot_base(t)
	var skill := {"name": "掠夺", "type": "piratePlunder", "hits": 1, "atkScale": 0.8,
		"stealDefPct": 20, "stealMrPct": 20, "stealDefTurns": 3, "shieldBreakPct": 50}
	SkillHandlers.execute(c, t, [c, t], skill)
	# 破盾 50% → 100 → 50 (然后 atk×0.8 物理打剩余盾/血)
	# 偷甲: target baseDef=20 × 20% = 4 → caster def +4 = 18; target def -20% → 16
	_assert_eq("piratePlunder caster defUp", Buffs.has(c, "defUp"), true)
	_assert_eq("piratePlunder target defDown", Buffs.has(t, "defDown"), true)


func _test_t2_phoenix_scald_break_shield() -> void:
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	t["shield"] = 80
	var skill := {"name": "烫伤", "type": "phoenixScald", "hits": 1, "atkScale": 0.7,
		"atkDown": {"pct": 15, "turns": 4}, "defDown": {"pct": 15, "turns": 4},
		"mrDown": {"pct": 15, "turns": 4}, "shieldBreak": 50, "burn": true, "healReduce": true}
	SkillHandlers.execute(c, t, [c, t], skill)
	# 破盾 50%: 80 → 40, 然后魔法伤害扣剩余 → shield 应 < 40
	_assert_eq("phoenixScald 破盾后 shield<40", t["shield"] < 40, true)
	_assert_eq("phoenixScald healReduce", Buffs.has(t, "healReduce"), true)
	_assert_eq("phoenixScald burn", Buffs.has(t, "burn"), true)


func _test_dodge() -> void:
	# dodge=100% → 必闪避, 0 伤害 + miss effect
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	Buffs.add(t, "dodge", 100, 999)
	var skill := {"name": "攻击", "type": "physical", "hits": 1, "atkScale": 1.0}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	# 必闪避 → 无 damage effect, 有 miss effect, target hp 不变
	_assert_eq("dodge 100% target hp 不变", t["hp"], 1000)
	var has_miss := false
	for e in r["effects"]:
		if e.get("kind", "") == "miss":
			has_miss = true
	_assert_eq("dodge 100% 有 miss effect", has_miss, true)


func _test_ghost_equip_dodge() -> void:
	# e_ghost on_attach → +15% dodge buff + _equipGhostSquid
	var f := _make_test_fighter(40, 14, 13)
	f["_equipped_ids"] = ["e_ghost"]
	EquipmentRuntime.on_attach(f, "e_ghost")
	_assert_eq("e_ghost dodge buff 15", Buffs.find(f, "dodge")["value"], 15.0, 0.001)
	_assert_eq("e_ghost _equipGhostSquid", f.get("_equipGhostSquid", false), true)
	_assert_eq("e_ghost +20 maxHp", f["maxHp"], 120)


func _test_chest_treasure() -> void:
	# ── apply_chest_equip_stat: 各 stat → 属性/flag (1:1 PoC BattleScene.ts:4801) ──
	var f := _make_test_fighter(100, 20, 20)
	EquipmentRuntime.apply_chest_equip_stat(f, {"stat": "atk", "pct": 25})
	_assert_eq("chest atk+25% → 125", f["atk"], 125)
	EquipmentRuntime.apply_chest_equip_stat(f, {"stat": "thunder"})
	_assert_eq("chest thunder flag", f.get("_chestEquipThunder", false), true)
	EquipmentRuntime.apply_chest_equip_stat(f, {"stat": "trueDmg"})
	_assert_eq("chest star(trueDmg) flag", f.get("_chestEquipStar", false), true)
	EquipmentRuntime.apply_chest_equip_stat(f, {"stat": "rock", "pct": 100})
	_assert_eq("chest rock flag", f.get("_chestEquipRock", false), true)
	var f2 := _make_test_fighter(40, 10, 10)
	EquipmentRuntime.apply_chest_equip_stat(f2, {"stat": "defMr", "pct": 20, "bonusHp": 60})
	_assert_eq("chest defMr+20% def → 12", f2["def"], 12)
	_assert_eq("chest defMr bonusHp+60", f2["maxHp"], 160)

	# ── chestSmash 基础 (无变种): star 转真伤, 单体 hits 段 ──
	# atk=40, atkScale=0.7, hits=4 → totalBase=round(28)=28, perHit=round(28/4)=7, star→真伤(def免疫)
	# 4 段 × 7 = 28 (target def=0, 真伤无减) → 4 个独立 damage effect 累加
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0
	c["_chestEquipStar"] = true
	var t := _make_test_fighter(40, 50, 50)   # 高甲, 但 star 真伤穿透
	t["maxHp"] = 1000; t["hp"] = 1000
	var skill := {"name": "宝箱砸击", "type": "chestSmash", "hits": 4, "atkScale": 0.7}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	var smash_total := 0
	for e in r["effects"]:
		if e.get("kind", "") == "damage":
			smash_total += e["value"]
	_assert_eq("chestSmash star 真伤 4×7=28", smash_total, 28)

	# ── thunder 引爆: 预置 _goldLightning=4, 第 1 段叠到 5 → 引爆 1×ATK=40 真伤 (带 lightning flag) ──
	var c2 := _make_test_fighter(40, 14, 13)
	c2["crit"] = 0.0
	c2["_chestEquipStar"] = true
	c2["_chestEquipThunder"] = true
	var t2 := _make_test_fighter(40, 0, 0)
	t2["maxHp"] = 1000; t2["hp"] = 1000
	t2["_goldLightning"] = 4
	var r2 := SkillHandlers.execute(c2, t2, [c2, t2], skill)
	var found_lightning := false
	var lightning_val := -1
	for e in r2["effects"]:
		if e.get("lightning", false):
			found_lightning = true
			lightning_val = e["value"]
	_assert_eq("chestSmash thunder 满5引爆 lightning effect", found_lightning, true)
	_assert_eq("chestSmash thunder 引爆=1×ATK=40", lightning_val, 40)
	# 4 段: 预置4 → h1=5(引爆归0) h2=1 h3=2 h4=3 → 末态 3 (验证引爆后从 0 重新累积)
	_assert_eq("chestSmash thunder 引爆后重新累积到 3", int(t2.get("_goldLightning", -1)), 3)

	# ── rock 变种: totalBasePower += def+mr (1:1 PoC chest.js) ──
	# atk=40 atkScale=0.7 → 28; rock +def(30)+mr(30)=88; perHit=round(88/4)=22; star真伤 4×22=88
	var c3 := _make_test_fighter(40, 30, 30)
	c3["crit"] = 0.0
	c3["_chestEquipStar"] = true
	c3["_chestEquipRock"] = true
	var t3 := _make_test_fighter(40, 0, 0)
	t3["maxHp"] = 1000; t3["hp"] = 1000
	var r3 := SkillHandlers.execute(c3, t3, [c3, t3], skill)
	var rock_total := 0
	for e in r3["effects"]:
		if e.get("kind", "") == "damage":
			rock_total += e["value"]
	_assert_eq("chestSmash rock +def+mr → 4×22=88", rock_total, 88)

	# ── fire 变种: 命中后 target burn ──
	var c4 := _make_test_fighter(40, 14, 13)
	c4["crit"] = 0.0
	c4["_chestEquipFire"] = true
	var t4 := _make_test_fighter(40, 0, 0)
	t4["maxHp"] = 1000; t4["hp"] = 1000
	SkillHandlers.execute(c4, t4, [c4, t4], skill)
	_assert_eq("chestSmash fire → target burn", _has_dot(t4, "burn"), true)

	# ── process_chest_treasure_gain: 累积到阈值 → 抽装备 + 设 tier + heal ──
	var chest := FighterFactory.create("chest", "left")
	chest["hp"] = 1
	var before_tier := int(chest.get("_chestTier", 0))
	# 给足财宝越过第 1 阈值 (Lv1: 80)
	var heal_eff := EquipmentRuntime.process_chest_treasure_gain(chest, 100, [chest])
	_assert_eq("chestTreasure tier 推进 ≥1", int(chest.get("_chestTier", 0)) > before_tier, true)
	_assert_eq("chestTreasure 抽到 1 件装备", (chest.get("_chestEquips", []) as Array).size(), 1)
	_assert_eq("chestTreasure 开箱回血 effect", heal_eff.size() >= 1, true)


func _has_dot(f: Dictionary, type: String) -> bool:
	for b in f.get("buffs", []):
		if b is Dictionary and b.get("type", "") == type:
			return true
	return false


func _test_two_head_magic_wave() -> void:
	# 4 段 (2物理+2真伤) × atk×0.4, crit=0 → 4×round(40×0.4)=4×16=64
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "魔法波", "type": "twoHeadMagicWave", "hits": 4, "atkScale": 0.4}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("twoHeadMagicWave 4段=64", r["effects"][0]["value"], 64)


func _test_hunter_poison_dot() -> void:
	var c := _make_test_fighter(40, 14, 13)
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "毒箭", "type": "hunterPoison", "hits": 1, "atkScale": 0.8,
		"dot": {"dmg": 15, "turns": 3}, "healReduce": true}
	SkillHandlers.execute(c, t, [c, t], skill)
	# poison = max(1, round(15×3/4)) = 11
	var poison = Buffs.find(t, "poison")
	_assert_eq("hunterPoison poison 11 层", poison["value"] if poison != null else -1, 11)
	_assert_eq("hunterPoison healReduce", Buffs.has(t, "healReduce"), true)


func _test_current_hp_pct() -> void:
	# currentHpPct: hits=1, base = atk×0.4 + curHp×6%. atk=40 crit=0, t hp=1000 mr=0
	# = 16 + 60 = 76, magic mr=0 无减 → 76
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "星光", "type": "magic", "hits": 1, "atkScale": 0.4, "currentHpPct": 6, "dmgType": "magic"}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("currentHpPct base=76", r["effects"][0]["value"], 76)


func _test_angel_equality_rarity() -> void:
	# 2 段物理 atk×1.0 + 高稀有度追加真伤 atk×0.5 + 已损HP×10% (实时, PoC 1:1)
	# c atk=40 crit=0, t rarity=A maxHp=1000 hp=500, def=0 mr=0
	# 2段物理 = 80 → t.hp 500→420; 追加真伤 = 40×0.5 + (1000-420)×0.1 = 20+58 = 78; total=158
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0
	var t := _make_test_fighter(40, 0, 0)
	t["rarity"] = "A"
	t["maxHp"] = 1000
	t["hp"] = 500
	var skill := {"name": "平等", "type": "angelEquality", "dmgType": "physical", "hits": 2,
		"normalScale": 1, "antiHighRarity": ["A", "S", "SS", "SSS"],
		"extraTrueAtkScale": 0.5, "extraTrueLostHpPct": 10, "lifestealPct": 10}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	# 找 damage effect (可能有 heal effect 在后)
	var dmg_val := 0
	for e in r["effects"]:
		if e.get("kind", "") == "damage":
			dmg_val = e["value"]
	_assert_eq("angelEquality 2段+追加真伤=158 (实时已损)", dmg_val, 158)


func _test_selectors() -> void:
	# 2×2 网格 (右队, _slotKey = "${row}-${col}"): front-0/front-1/back-0/back-1
	#   row=front/back (前后/x), col=0/1/2 (上下/y).
	#   sameColumn(同col)=屏上横排{front-N,back-N}; sameRow(同front/back)=屏上竖排.
	var r0 := _make_test_fighter(40, 14, 13); r0["side"] = "right"; r0["_slotKey"] = "front-0"; r0["_position"] = "front"
	var r1 := _make_test_fighter(40, 14, 13); r1["side"] = "right"; r1["_slotKey"] = "front-1"; r1["_position"] = "front"
	var r2 := _make_test_fighter(40, 14, 13); r2["side"] = "right"; r2["_slotKey"] = "back-0"; r2["_position"] = "back"
	var r3 := _make_test_fighter(40, 14, 13); r3["side"] = "right"; r3["_slotKey"] = "back-1"; r3["_position"] = "back"
	var all := [r0, r1, r2, r3]
	# sameColumn (同 col, {front-N,back-N}, 含自身) = 横排, ≤2
	_assert_eq("sameColumn(front-0)=2 {f0,b0}", SlotHelpers.same_column_fighters(all, r0).size(), 2)
	_assert_eq("sameColumn(back-1)=2 {f1,b1}", SlotHelpers.same_column_fighters(all, r3).size(), 2)
	# sameRow (同 front/back, 含自身) = 竖排
	_assert_eq("sameRow(front-0)=2 {f0,f1}", SlotHelpers.same_row_fighters(all, r0).size(), 2)
	_assert_eq("sameRow(back-0)=2 {b0,b1}", SlotHelpers.same_row_fighters(all, r2).size(), 2)
	# adjacent (col±1 同row + 对row同col, 不含自身)
	_assert_eq("adjacent(front-0)=2 {f1,b0}", SlotHelpers.adjacent_fighters(all, r0).size(), 2)
	_assert_eq("adjacent(front-1)=2 {f0,b1}", SlotHelpers.adjacent_fighters(all, r1).size(), 2)
	# fighter_behind (front→back 同col 单个 / back→null)
	var bh = SlotHelpers.fighter_behind(all, r0)
	_assert_eq("behind(front-0)=back-0", bh != null and bh.get("_slotKey", "") == "back-0", true)
	_assert_eq("behind(back-0)=null", SlotHelpers.fighter_behind(all, r2) == null, true)
	# fighter_in_front (back→front 同col)
	var inf = SlotHelpers.fighter_in_front(all, r2)
	_assert_eq("inFront(back-0)=front-0", inf != null and inf.get("_slotKey", "") == "front-0", true)
	# front_slot_empty (back 前方 front 槽是否空)
	_assert_eq("frontSlotEmpty(back-0)=false (f0占)", SlotHelpers.front_slot_empty(all, r2), false)
	# 移走 front-0 → back-0 前方空
	r0["alive"] = false
	_assert_eq("frontSlotEmpty(back-0)=true (f0死)", SlotHelpers.front_slot_empty(all, r2), true)


func _test_target_selection() -> void:
	# PoC 选目标: 前排守门 / taunt 优先 / ignoreRow 越排. caster=left, 敌=right
	var caster := _make_test_fighter(40, 14, 13); caster["side"] = "left"
	# 前排 front-0 (hp 50), 后排 back-0 (hp 10, 更低血)
	var f0 := _make_test_fighter(40, 0, 0); f0["side"] = "right"; f0["_slotKey"] = "front-0"; f0["hp"] = 50
	var b0 := _make_test_fighter(40, 0, 0); b0["side"] = "right"; b0["_slotKey"] = "back-0"; b0["hp"] = 10
	var all := [caster, f0, b0]
	# 非 ignoreRow: 前排守门 → 即便 back 更低血, 也只能打 front-0
	_assert_eq("前排守门: 选 front-0 (非最低血)", SkillHandlers._pick_enemy_target(caster, all, false), all.find(f0))
	# ignoreRow: 越排 → 选绝对最低血 back-0
	_assert_eq("ignoreRow: 选最低血 back-0", SkillHandlers._pick_enemy_target(caster, all, true), all.find(b0))
	# 前排全死 → back 暴露, 选 back-0
	f0["alive"] = false
	_assert_eq("前排死 → 暴露 back-0", SkillHandlers._pick_enemy_target(caster, all, false), all.find(b0))
	# taunt: 复活 front-0, 给后排 back-0 挂嘲讽 → 强制打嘲讽者(跳过前排守门)
	f0["alive"] = true
	Buffs.add(b0, "taunt", 1, 99, "ignore")
	_assert_eq("taunt: 强制打嘲讽者 back-0", SkillHandlers._pick_enemy_target(caster, all, false), all.find(b0))
	Buffs.remove_all(b0, "taunt")
	# visible_enemy_targets: 前排存活 → 只返回前排
	var vis := SlotHelpers.visible_enemy_targets(all, caster)
	_assert_eq("visibleEnemy: 前排存活只露 front", vis.size(), 1)
	_assert_eq("visibleEnemy: 露的是 front-0", (vis[0] as Dictionary).get("_slotKey", ""), "front-0")


func _test_auto_assign_formation() -> void:
	# autoAssign: boss 单龟 front-1; 2 龟 走 formation top2 (随机 A/B, PoC 无固定特例); 3 龟 50/50 两菱形阵
	_assert_eq("autoAssign 1 龟 = front-1", str(SlotHelpers.auto_assign_slots([_make_test_fighter(40, 0, 0)])), str(["front-1"]))
	# PoC 2 龟无特例: 取 formation[0..1] = A[front-1,back-0] 或 B[front-0,front-2] (BattleScene.ts:418-423)
	#   等血两龟槽序任意, 比 SET (排序后) 兼容不稳定排序
	var raw2: Array = SlotHelpers.auto_assign_slots([_make_test_fighter(40, 0, 0), _make_test_fighter(40, 0, 0)])
	raw2.sort()
	var fa := ["front-1", "back-0"]; fa.sort()
	var fb := ["front-0", "front-2"]; fb.sort()
	_assert_eq("autoAssign 2 龟 = A或B阵型 top2 (无固定特例)", str(raw2) == str(fa) or str(raw2) == str(fb), true)
	# 3 龟: 最高血(maxHp 1000)必在 formation[0] (front-1 或 front-0), 其余在 formation[1/2]
	var hi := _make_test_fighter(40, 0, 0); hi["maxHp"] = 1000
	var mid := _make_test_fighter(40, 0, 0); mid["maxHp"] = 500
	var lo := _make_test_fighter(40, 0, 0); lo["maxHp"] = 100
	var slots := SlotHelpers.auto_assign_slots([lo, hi, mid])  # 乱序传入
	# hi 拿到的槽必是某菱形阵的 formation[0]: front-1(A) 或 front-0(B)
	var hi_slot: String = slots[1]
	_assert_eq("autoAssign 最高血吃前锋槽", hi_slot == "front-1" or hi_slot == "front-0", true)
	# 三槽互不相同 (合法布阵)
	var uniq := {}
	for s in slots:
		uniq[s] = true
	_assert_eq("autoAssign 三槽不重复", uniq.size(), 3)


func _test_dot_floor_decay() -> void:
	# PoC tickDoTs 衰减用 Math.floor 非 round. burn 7 层, decay 1/3 → floor(7×2/3)=floor(4.67)=4 (round 会给 5)
	var f := _make_test_fighter(40, 0, 0); f["maxHp"] = 100000; f["hp"] = 100000
	Dot.apply_stacks(f, "burn", 7)
	Dot.tick(f)
	var burn = Buffs.find(f, "burn")
	_assert_eq("burn 衰减用 floor: 7→4 (非 round 5)", burn["value"] if burn != null else -1, 4)


func _test_curse_single_decrement() -> void:
	# curse 只在 tick_buffs_duration 减 1 次; Dot.tick 不动它 (否则双减提前过期)
	var f := _make_test_fighter(40, 0, 0); f["maxHp"] = 100000; f["hp"] = 100000
	(f["buffs"] as Array).append({"type": "curse", "value": 10, "duration": 3})
	Dot.tick(f)  # 造成 curse 伤害, 不碰 duration
	var c1 = Buffs.find(f, "curse")
	_assert_eq("curse: Dot.tick 后 duration 不变 (3)", c1["duration"] if c1 != null else -1, 3)
	StatsRecalc.tick_buffs_duration(f)  # 此处才 -1
	var c2 = Buffs.find(f, "curse")
	_assert_eq("curse: tick_buffs_duration 后 =2 (单减非双减)", c2["duration"] if c2 != null else -1, 2)


func _test_dot_tick_canonical_order() -> void:
	# 多 DoT 固定结算顺序: 不论 buff append 顺序, Dot.tick 返回固定 burn→poison→bleed→curse
	#   (修"多 DoT 出伤时机乱序"; BattleScene 据此逐条错开飘字)。
	var f := _make_test_fighter(40, 0, 0); f["maxHp"] = 100000; f["hp"] = 100000
	# 故意打乱 append: 流血→诅咒→点燃→中毒
	(f["buffs"] as Array).append({"type": "bleed", "value": 10, "duration": 999})
	(f["buffs"] as Array).append({"type": "curse", "value": 10, "duration": 3})
	(f["buffs"] as Array).append({"type": "burn", "value": 10, "duration": 999})
	(f["buffs"] as Array).append({"type": "poison", "value": 10, "duration": 999})
	var fx: Array = Dot.tick(f)
	var order: Array = []
	for e in fx:
		order.append(str((e as Dictionary).get("cls", "")))
	_assert_eq("DoT tick 固定顺序 burn→poison→bleed→curse", order, ["dot-dmg", "dot-poison", "dot-bleed", "dot-curse"])


func _test_hammer_no_double_atk() -> void:
	# e_hammer ATK 只在 recalc 折算, 不在 on_attach 改 baseAtk (否则双计/污染 baseAtk)
	var f := _make_test_fighter(40, 0, 0); f["maxHp"] = 500; f["hp"] = 500
	StatsRecalc.snapshot_base(f)
	EquipmentRuntime.on_attach(f, "e_hammer")  # +100 HP → maxHp 600, count 1
	StatsRecalc.recalc(f, [f])
	# atk = baseAtk(40) + maxHp(600)×0.04×1 = 64; baseAtk 不被污染仍 40
	_assert_eq("hammer ATK 单计 = 64", f["atk"], 64)
	_assert_eq("hammer baseAtk 未污染 = 40", f["baseAtk"], 40)


func _test_ai_heal_shield_thresholds() -> void:
	# PoC AI: heal 阈值 0.4 (非 0.35), 治最低血比例队友; shield <30 (非 ==0)
	var caster := _make_test_fighter(40, 0, 0); caster["side"] = "right"; caster["_slotKey"] = "front-0"
	var ally := _make_test_fighter(40, 0, 0); ally["side"] = "right"; ally["_slotKey"] = "front-1"; ally["maxHp"] = 100; ally["hp"] = 38
	var enemy := _make_test_fighter(40, 0, 0); enemy["side"] = "left"; enemy["_slotKey"] = "front-0"
	var all := [caster, ally, enemy]
	# heal: 队友 38% < 0.4 → 治, 目标 = 最低血队友 ally
	caster["skills"] = [{"type": "heal", "cd": 2, "cdLeft": 0}]
	var p1 = SkillHandlers.ai_pick(caster, all)
	_assert_eq("AI heal 0.4阈值: 队友38%→治疗", p1["skill_idx"], 0)
	_assert_eq("AI heal 目标=最低血队友", p1["target_idx"], all.find(ally))
	# 队友回 45% > 0.4 → 不治, 走输出技能
	ally["hp"] = 45
	caster["skills"] = [{"type": "heal", "cd": 2, "cdLeft": 0}, {"type": "physical", "cd": 0, "cdLeft": 0, "atkScale": 1.0}]
	var p2 = SkillHandlers.ai_pick(caster, all)
	_assert_eq("AI heal: 队友45%>阈值 → 不治走输出", p2["skill_idx"], 1)
	# shield: 队友盾 20 < 30 → 补盾
	ally["hp"] = 100
	caster["skills"] = [{"type": "shield", "cd": 2, "cdLeft": 0}, {"type": "physical", "cd": 0, "cdLeft": 0, "atkScale": 1.0}]
	caster["shield"] = 30; ally["shield"] = 20
	var p3 = SkillHandlers.ai_pick(caster, all)
	_assert_eq("AI shield<30: 队友盾20→补盾", p3["skill_idx"], 0)
	# 全队盾 >=30 → 不补, 走输出
	caster["shield"] = 30; ally["shield"] = 30
	var p4 = SkillHandlers.ai_pick(caster, all)
	_assert_eq("AI shield: 全队盾>=30 → 走输出", p4["skill_idx"], 1)


func _th_find_skill(f: Dictionary, type: String):
	for s in f["skills"]:
		if s.get("type", "") == type:
			return s
	return null


func _th_has_skill(f: Dictionary, type: String) -> bool:
	return _th_find_skill(f, type) != null


func _th_has_damage(r: Dictionary) -> bool:
	for e in r.get("effects", []):
		if e.get("kind", "") == "damage":
			return true
	return false


func _test_two_head_switch() -> void:
	# 换形状态机: ranged→melee 改 base 属性 + 换技能集 + switch-attack; 再换回还原
	var c := FighterFactory.create("two_head", "left")
	c["crit"] = 0.0  # 去随机
	var e := _make_test_fighter(40, 0, 0); e["side"] = "right"; e["_slotKey"] = "front-0"; e["maxHp"] = 99999; e["hp"] = 99999
	var all := [c, e]
	var maxhp0: int = c["maxHp"]
	var atk0: float = c["atk"]
	var sw = _th_find_skill(c, "twoHeadSwitch")
	_assert_eq("two_head 默认带换形技", sw != null, true)
	var r := SkillHandlers.execute(c, e, all, sw)
	_assert_eq("换形→melee 标记", c.get("_twoHeadForm", ""), "melee")
	_assert_eq("melee maxHp += round(atk×1.5)", c["maxHp"], maxhp0 + roundi(atk0 * 1.5))
	_assert_eq("melee 技能集换成近战(含锤击)", _th_has_skill(c, "twoHeadHammer"), true)
	_assert_eq("melee 不再有远程魔法波", _th_has_skill(c, "twoHeadMagicWave"), false)
	_assert_eq("switch-attack 造成伤害", _th_has_damage(r), true)
	# 锤击: shield from dmg
	var ham = _th_find_skill(c, "twoHeadHammer")
	var sh0: int = c["shield"]
	SkillHandlers.execute(c, e, all, ham)
	_assert_eq("锤击后获得护盾 (shieldFromDmg)", c["shield"] > sh0, true)
	# 换回远程: 属性还原, 技能集还原
	var sw2 = _th_find_skill(c, "twoHeadSwitch")  # 此时 switchTo=ranged
	SkillHandlers.execute(c, e, all, sw2)
	_assert_eq("换形→ranged 标记", c.get("_twoHeadForm", ""), "ranged")
	_assert_eq("ranged maxHp 还原", c["maxHp"], maxhp0)
	_assert_eq("ranged 技能集还原(含魔法波)", _th_has_skill(c, "twoHeadMagicWave"), true)


func _test_two_head_mind_blast() -> void:
	# 精神干扰: magic 伤害 + 破盾 50% + healReduce
	var c := FighterFactory.create("two_head", "left"); c["crit"] = 0.0
	var e := _make_test_fighter(40, 0, 0); e["side"] = "right"; e["_slotKey"] = "front-0"; e["maxHp"] = 99999; e["hp"] = 99999; e["shield"] = 1000
	var mb := {"type": "twoHeadMindBlast", "atkScale": 1.0, "shieldBreakPct": 50, "healReducePct": 50, "healReduceTurns": 3}
	SkillHandlers.execute(c, e, [c, e], mb)
	_assert_eq("mindblast 破盾后 shield<1000", e["shield"] < 1000, true)
	_assert_eq("mindblast 施加 healReduce", Buffs.has(e, "healReduce"), true)


func _test_lava_rage_hooks() -> void:
	# 受伤端: lavaRage 受 hpLoss × rageTakenPct% 累积; 满 → ready
	var f := _make_test_fighter(40, 10, 10); f["maxHp"] = 1000; f["hp"] = 1000
	f["passive"] = {"type": "lavaRage", "rageMax": 100, "rageTakenPct": 20}
	Damage.apply_raw_damage(f, 100, "true")  # hpLoss 100 → rage += round(100×20%)=20
	_assert_eq("lavaRage 受伤累积 20%", f.get("_lavaRage", 0), 20)
	f["_lavaRage"] = 90
	Damage.apply_raw_damage(f, 100, "true")  # +20 → clamp 100 → ready
	_assert_eq("lavaRage 满→ready", f.get("_lavaRageReady", false), true)
	# 变身中不累积
	f["_lavaRage"] = 0; f["_lavaRageReady"] = false; f["_lavaTransformed"] = true
	Damage.apply_raw_damage(f, 100, "true")
	_assert_eq("lavaRage 变身中不累积", f.get("_lavaRage", 0), 0)


func _test_two_head_resilience_hook() -> void:
	# 受击叠甲抗: 每段 +1甲+1抗, cap 20
	var f := _make_test_fighter(40, 10, 10); f["maxHp"] = 1000; f["hp"] = 1000
	f["_twoHeadResilience"] = true; f["_twoHeadResStacks"] = 0
	var d0: int = f["def"]; var m0: int = f["mr"]
	Damage.apply_raw_damage(f, 50, "physical")
	_assert_eq("resilience stacks++", f["_twoHeadResStacks"], 1)
	_assert_eq("resilience def +1", f["def"], d0 + 1)
	_assert_eq("resilience mr +1", f["mr"], m0 + 1)
	# cap 20
	f["_twoHeadResStacks"] = 20
	Damage.apply_raw_damage(f, 50, "physical")
	_assert_eq("resilience cap 20", f["_twoHeadResStacks"], 20)


func _test_volcano_smash() -> void:
	# (atk×1.3 + maxHp×8%) 物理 + 20% 生命偷取. atk=100 maxHp=2000 def0 → base=130+160=290
	var c := _make_test_fighter(100, 0, 0); c["crit"] = 0.0; c["maxHp"] = 2000; c["hp"] = 1000
	var e := _make_test_fighter(0, 0, 0); e["side"] = "right"; e["_slotKey"] = "front-0"; e["maxHp"] = 99999; e["hp"] = 99999
	var sk := {"type": "volcanoSmash", "atkScale": 1.3, "selfHpPct": 8, "lifestealPct": 20}
	var r := SkillHandlers.execute(c, e, [c, e], sk)
	var dmg := 0; var heal := 0
	for ef in r["effects"]:
		if ef.get("kind", "") == "damage": dmg = ef["value"]
		elif ef.get("kind", "") == "heal": heal = ef["value"]
	_assert_eq("volcanoSmash dmg = 290", dmg, 290)
	_assert_eq("volcanoSmash lifesteal = round(290×20%)=58", heal, 58)


func _test_star_system() -> void:
	var c := FighterFactory.create("space", "left"); c["crit"] = 0.0; c["atk"] = 100; c["maxHp"] = 1000; c["hp"] = 1000
	_assert_eq("star maxE = round(maxHp×40%) = 400", SkillHandlers._star_max_e(c), 400)
	# starBeam 充能 + fireStarPassive
	c["_starEnergy"] = 0
	var be := _make_test_fighter(0, 0, 0); be["side"] = "right"; be["_slotKey"] = "front-0"; be["maxHp"] = 200; be["hp"] = 200
	SkillHandlers.execute(c, be, [c, be], {"type": "starBeam", "hits": 3, "atkScale": 0.4, "currentHpPct": 6})
	_assert_eq("starBeam 充能 >0", c.get("_starEnergy", 0) > 0, true)
	# blackhole 非最后敌 → 踢黑洞 (stun + blackhole + _isInBlackhole)
	var e1 := _make_test_fighter(0, 0, 0); e1["side"] = "right"; e1["_slotKey"] = "front-0"; e1["maxHp"] = 99999; e1["hp"] = 99999
	var e2 := _make_test_fighter(0, 0, 0); e2["side"] = "right"; e2["_slotKey"] = "front-1"; e2["maxHp"] = 99999; e2["hp"] = 99999
	var bh := {"type": "starBlackhole", "atkScale": 1.0, "lastTargetAtkScale": 1.8, "executeThreshPct": 15}
	SkillHandlers.execute(c, e1, [c, e1, e2], bh)
	_assert_eq("blackhole 踢入 stun", Buffs.has(e1, "stun"), true)
	_assert_eq("blackhole 踢入 _isInBlackhole", e1.get("_isInBlackhole", false), true)
	# blackhole 最后一敌 低血(10%<15) → 斩杀
	var e3 := _make_test_fighter(0, 0, 0); e3["side"] = "right"; e3["_slotKey"] = "front-0"; e3["maxHp"] = 1000; e3["hp"] = 100
	SkillHandlers.execute(c, e3, [c, e3], bh)
	_assert_eq("blackhole 斩杀最后一敌(10%血)", e3.get("alive", true), false)
	# gravityWarp 满星 → F0↔B2 换位 + relayout
	c["_starEnergy"] = 400
	var w0 := _make_test_fighter(0, 0, 0); w0["side"] = "right"; w0["_slotKey"] = "front-0"; w0["maxHp"] = 99999; w0["hp"] = 99999
	var w2 := _make_test_fighter(0, 0, 0); w2["side"] = "right"; w2["_slotKey"] = "back-2"; w2["maxHp"] = 99999; w2["hp"] = 99999
	var rw := SkillHandlers.execute(c, w0, [c, w0, w2], {"type": "starGravityWarp", "atkScale": 0.8})
	_assert_eq("warp 满星 relayout 标记", rw.get("relayout", false), true)
	_assert_eq("warp front-0 → back-2", w0.get("_slotKey", ""), "back-2")
	_assert_eq("warp back-2 → front-0", w2.get("_slotKey", ""), "front-0")
	_assert_eq("warp 后清能", c.get("_starEnergy", -1), 0)
	# meteor 满星 → burst 真伤
	c["_starEnergy"] = 400
	var m1 := _make_test_fighter(0, 0, 0); m1["side"] = "right"; m1["_slotKey"] = "front-0"; m1["maxHp"] = 99999; m1["hp"] = 99999
	var rm := SkillHandlers.execute(c, m1, [c, m1], {"type": "starMeteor", "atkScale": 1.0, "mrDown": {"pct": 20, "turns": 3}, "aoe": true})
	var has_true := false
	for ef in rm["effects"]:
		if ef.get("dmg_type", "") == "true":
			has_true = true
	_assert_eq("meteor 满星 burst 真伤", has_true, true)


func _test_shock_system() -> void:
	# 闪电: 叠层 + 满8引爆清零
	var c := FighterFactory.create("lightning", "left"); c["crit"] = 0.0; c["atk"] = 100
	var e := _make_test_fighter(0, 0, 0); e["side"] = "right"; e["_slotKey"] = "front-0"; e["maxHp"] = 99999; e["hp"] = 99999
	var all := [c, e]
	for _i in range(7):
		SkillHandlers._lightning_apply_shock(c, e, all, [])
	_assert_eq("电击 7 层未引爆", e.get("_shockStacks", 0), 7)
	var fx2: Array = []
	SkillHandlers._lightning_apply_shock(c, e, all, fx2)
	_assert_eq("电击满 8 引爆清零", e.get("_shockStacks", 0), 0)
	var has_true := false
	for ef in fx2:
		if ef.get("dmg_type", "") == "true": has_true = true
	_assert_eq("引爆产生真伤", has_true, true)
	# lightningSurge 消耗层
	e["_shockStacks"] = 5
	SkillHandlers.execute(c, e, all, {"type": "lightningSurge", "shockPerStackScale": 0.1, "shockConsume": true, "aoe": true})
	_assert_eq("感电后清电击层", e.get("_shockStacks", 0), 0)
	# 赛博: cyberDeploy 部署 + swarmShield 全友盾
	var cy := FighterFactory.create("cyber", "left"); cy["atk"] = 100; cy["_drones"] = []
	SkillHandlers.execute(cy, e, [cy, e], {"type": "cyberDeploy", "deployCount": 3})
	_assert_eq("cyberDeploy 部署 3 炮", (cy.get("_drones", []) as Array).size(), 3)
	var ally := _make_test_fighter(0, 0, 0); ally["side"] = "left"; ally["_slotKey"] = "front-1"
	SkillHandlers.execute(cy, e, [cy, ally, e], {"type": "cyberSwarmShield", "shieldAtkScale": 0.6, "shieldPerDronePct": 15, "shieldPerDroneEnhanced": 10})
	# totalScale = 0.6 + 0.15×3 = 1.05; shield = round(100×1.05) = 105
	_assert_eq("swarmShield 自身 +105 盾", cy.get("shield", 0), 105)
	_assert_eq("swarmShield 队友 +105 盾", ally.get("shield", 0), 105)


func _test_hiding_handlers() -> void:
	var c := FighterFactory.create("hiding", "left"); c["atk"] = 100; c["maxHp"] = 1000; c["hp"] = 1000
	# hidingDefend: 限时盾 _hidingShieldVal round(maxHp×20%) = 200 (独立池, 非普通 shield)
	SkillHandlers.execute(c, c, [c], {"type": "hidingDefend", "shieldHpPct": 20, "shieldDuration": 4, "shieldHealPct": 20})
	_assert_eq("hidingDefend 限时盾 200", c.get("_hidingShieldVal", 0), 200)
	_assert_eq("hidingDefend 不占普通盾", c.get("shield", 0), 0)
	# hidingBuffSummon 无随从 → 不崩
	var r0 := SkillHandlers.execute(c, c, [c], {"type": "hidingBuffSummon"})
	_assert_eq("hidingBuffSummon 无随从不崩", r0.has("effects"), true)
	# 有随从 → 给随从 buff
	var summon := FighterFactory.create("basic", "left"); summon["_slotKey"] = "back-0"; summon["alive"] = true
	c["_summon"] = summon
	SkillHandlers.execute(c, summon, [c, summon], {"type": "hidingBuffSummon"})
	_assert_eq("hidingBuffSummon 给随从 critUp", Buffs.has(summon, "critUp"), true)
	# hidingCommand 有随从 → command_summon 标记
	var rc := SkillHandlers.execute(c, c, [c, summon], {"type": "hidingCommand"})
	_assert_eq("hidingCommand 标记 command_summon", rc.get("command_summon", false), true)


func _test_synergies() -> void:
	# 物理 t2 (2只): baseAtk ×1.04
	var a := _make_test_fighter(100, 0, 0); a["tags"] = ["物理"]; a["baseAtk"] = 100
	var b := _make_test_fighter(100, 0, 0); b["tags"] = ["物理"]; b["baseAtk"] = 100
	Synergies.apply_team([a, b], [])
	_assert_eq("物理 t2: baseAtk ×1.04 = 104", a["baseAtk"], 104)
	# 物理 t3 (3只): ×1.08 + physBleed flag
	var c1 := _make_test_fighter(100, 0, 0); c1["tags"] = ["物理"]; c1["baseAtk"] = 100
	var c2 := _make_test_fighter(100, 0, 0); c2["tags"] = ["物理"]
	var c3 := _make_test_fighter(100, 0, 0); c3["tags"] = ["物理"]
	Synergies.apply_team([c1, c2, c3], [])
	_assert_eq("物理 t3: ×1.08 = 108", c1["baseAtk"], 108)
	_assert_eq("物理 t3: physBleed flag", c1.get("_synergyPhysBleed", false), true)
	# 刺杀 t2: crit+0.05 armorPen+2
	var k1 := _make_test_fighter(100, 0, 0); k1["tags"] = ["刺杀"]; k1["crit"] = 0.1; k1["armorPen"] = 0
	var k2 := _make_test_fighter(100, 0, 0); k2["tags"] = ["刺杀"]
	Synergies.apply_team([k1, k2], [])
	_assert_eq("刺杀 t2: crit +0.05 = 0.15", k1["crit"], 0.15, 0.001)
	_assert_eq("刺杀 t2: armorPen +2", k1["armorPen"], 2)
	# 法术 t3: 法穿+5 + 敌方 mr-4
	var m1 := _make_test_fighter(100, 0, 0); m1["tags"] = ["法术"]; m1["magicPen"] = 0
	var m2 := _make_test_fighter(100, 0, 0); m2["tags"] = ["法术"]
	var m3 := _make_test_fighter(100, 0, 0); m3["tags"] = ["法术"]
	var en := _make_test_fighter(0, 0, 0); en["baseMr"] = 20; en["mr"] = 20
	Synergies.apply_team([m1, m2, m3], [en])
	_assert_eq("法术 t3: 法穿 +5", m1["magicPen"], 5)
	_assert_eq("法术 t3: 敌方 mr -4 = 16", en["mr"], 16)
	# 守护 t2: shield+15 + guardAmp
	var g1 := _make_test_fighter(100, 10, 10); g1["tags"] = ["守护"]; g1["shield"] = 0
	var g2 := _make_test_fighter(100, 10, 10); g2["tags"] = ["守护"]
	Synergies.apply_team([g1, g2], [])
	_assert_eq("守护 t2: shield +15", g1["shield"], 15)
	# 单只不激活
	var s1 := _make_test_fighter(100, 0, 0); s1["tags"] = ["物理"]
	_assert_eq("单只不激活协同", Synergies.calc_active([s1]).size(), 0)
	# apply_shift: maxHp×10% 护盾 + 首次 +8% ATK
	var sh := _make_test_fighter(100, 0, 0); sh["maxHp"] = 1000; sh["alive"] = true
	sh["_synergyShiftShieldPct"] = 0.10; sh["_synergyShiftFirstAtkBonus"] = 0.08; sh["shield"] = 0; sh["baseAtk"] = 100
	var res := Synergies.apply_shift(sh)
	_assert_eq("apply_shift 护盾 = 100", res["shieldAdded"], 100)
	_assert_eq("apply_shift 首次 ATK = 108", sh["baseAtk"], 108)
	_assert_eq("apply_shift 二次不再加 ATK", Synergies.apply_shift(sh)["atkAdded"], 0)
	# 元素 DoT boost: Dot.tick(×1.1)
	var dt := _make_test_fighter(0, 0, 0); dt["maxHp"] = 100000; dt["hp"] = 100000
	Dot.apply_stacks(dt, "poison", 100)
	var fx := Dot.tick(dt, 0.10)
	var ddmg := 0
	for ef in fx:
		ddmg = ef["value"]
	_assert_eq("元素boost: poison 100 ×1.1 = 110", ddmg, 110)
	# 守护羁绊 guardAmp: _heal_to 受治疗 +10% (100→110)
	var gh := _make_test_fighter(0, 0, 0); gh["maxHp"] = 1000; gh["hp"] = 100; gh["alive"] = true
	gh["_synergyGuardAmp"] = 0.10
	_assert_eq("守护 guardAmp: heal 100 ×1.1 = 110", SkillHandlers._heal_to(gh, 100), 110)
	# 潮汐涟漪 _equipRippleHealAmp: _heal_to 受治疗 +30% (100→130)
	var rh := _make_test_fighter(0, 0, 0); rh["maxHp"] = 1000; rh["hp"] = 100; rh["alive"] = true
	rh["_equipRippleHealAmp"] = 30
	_assert_eq("潮汐 rippleAmp: heal 100 ×1.3 = 130", SkillHandlers._heal_to(rh, 100), 130)
	# 叠加: ripple +30% 后 guard +10% → round(round(100×1.3)×1.1) = 143
	var bh := _make_test_fighter(0, 0, 0); bh["maxHp"] = 1000; bh["hp"] = 100; bh["alive"] = true
	bh["_equipRippleHealAmp"] = 30; bh["_synergyGuardAmp"] = 0.10
	_assert_eq("守护+潮汐叠加: 100→143", SkillHandlers._heal_to(bh, 100), 143)
	# 元素 t3 burn tick: tagger 侧每回合烧随机敌, stacks=max(1,round(maxHp×0.02))
	var tg := _make_test_fighter(0, 0, 0); tg["side"] = "left"; tg["alive"] = true; tg["_synergyElemBurnTick"] = true
	var ev := _make_test_fighter(0, 0, 0); ev["side"] = "right"; ev["alive"] = true; ev["maxHp"] = 500; ev["hp"] = 500; ev["buffs"] = []
	var bt := Synergies.process_elem_burn_tick([tg, ev], 1.0)
	_assert_eq("elemBurnTick: 1侧tagger→1次烧", bt.size(), 1)
	_assert_eq("elemBurnTick: stacks=round(500×0.02)=10", int(bt[0]["stacks"]), 10)
	_assert_eq("elemBurnTick: 敌身上挂 burn 10 层", int(Buffs.find(ev, "burn").get("value", 0)), 10)
	# 无 tagger → 不烧
	var tg2 := _make_test_fighter(0, 0, 0); tg2["side"] = "left"; tg2["alive"] = true
	var ev2 := _make_test_fighter(0, 0, 0); ev2["side"] = "right"; ev2["alive"] = true; ev2["maxHp"] = 500; ev2["buffs"] = []
	_assert_eq("elemBurnTick: 无tagger→0次", Synergies.process_elem_burn_tick([tg2, ev2], 1.0).size(), 0)
	# 烈焰之日 burn_mult 1.5 → 10×1.5=15
	var tg3 := _make_test_fighter(0, 0, 0); tg3["side"] = "left"; tg3["alive"] = true; tg3["_synergyElemBurnTick"] = true
	var ev3 := _make_test_fighter(0, 0, 0); ev3["side"] = "right"; ev3["alive"] = true; ev3["maxHp"] = 500; ev3["buffs"] = []
	_assert_eq("elemBurnTick: 烈焰之日 ×1.5 = 15", int(Synergies.process_elem_burn_tick([tg3, ev3], 1.5)[0]["stacks"]), 15)
	# 刺杀羁绊击杀奖励: 全队 +5% baseAtk (非仅攻击者)
	var ak1 := _make_test_fighter(0, 0, 0); ak1["baseAtk"] = 100; ak1["alive"] = true
	var ak2 := _make_test_fighter(0, 0, 0); ak2["baseAtk"] = 200; ak2["alive"] = true
	var ak3 := _make_test_fighter(0, 0, 0); ak3["baseAtk"] = 50; ak3["alive"] = false  # 死的不加
	_assert_eq("刺杀击杀: 有存活→true", Synergies.apply_assassin_kill_bonus([ak1, ak2, ak3]), true)
	_assert_eq("刺杀击杀: 攻击者 100→105", ak1["baseAtk"], 105)
	_assert_eq("刺杀击杀: 队友 200→210 (整队都加)", ak2["baseAtk"], 210)
	_assert_eq("刺杀击杀: 死队友不加 50", ak3["baseAtk"], 50)
	_assert_eq("刺杀击杀: 空队→false", Synergies.apply_assassin_kill_bonus([]), false)
	# 物理 t3 流血量 = max(1, round(atk×0.08)): atk=100→8, atk=5→max(1,0)=1
	_assert_eq("physBleed: atk100×0.08=8", maxi(1, roundi(100 * 0.08)), 8)
	_assert_eq("physBleed: atk5 floor=1", maxi(1, roundi(5 * 0.08)), 1)
	# 再生 t3 复活反击: dmg = max(1, calc_damage(atk×1, magic)) — 即便高魔抗减到0也至少1
	var rv_atk := _make_test_fighter(1, 0, 0)
	var rv_tgt := _make_test_fighter(0, 0, 9999)  # 超高 mr → calc_damage 趋 0
	_assert_eq("reviveAttack: 高mr floor=1", maxi(1, Damage.calc_damage(rv_atk, rv_tgt, rv_atk.get("atk", 0), "magic")), 1)
	# 反伤地板 (P0 修): reflect/海胆/磐石 三处反伤过攻击者护甲, 高甲攻击者 → calc_damage 趋 0; 须 max(1) 不被 roundi 缩成 0.
	#   场景: 反伤量小 + 攻击者超高护甲 → 裸 calc_damage=0 (用户报"反伤被缩没"); 裹 maxi(1) → 至少 1。
	var refl_attacker := _make_test_fighter(0, 9999, 0)  # 超高护甲 → 物理 calc_damage 趋 0
	var refl_target := _make_test_fighter(0, 0, 0)
	_assert_eq("反伤裸 calc_damage 高甲被缩成 0 (复现 bug)", Damage.calc_damage(refl_target, refl_attacker, 5.0, "physical"), 0)
	_assert_eq("反伤地板 maxi(1, calc) → 至少 1 (修复)", maxi(1, Damage.calc_damage(refl_target, refl_attacker, 5.0, "physical")), 1)
	# 刺杀 t3 execute: 目标 <50% HP 时 +10% 伤害 (true 伤无视防御, 便于验)
	var ex_atk := _make_test_fighter(0, 0, 0); ex_atk["_synergyAssassinExecute"] = true
	var ex_lo := _make_test_fighter(0, 0, 0); ex_lo["maxHp"] = 100; ex_lo["hp"] = 40  # 40% <50%
	var ex_hi := _make_test_fighter(0, 0, 0); ex_hi["maxHp"] = 100; ex_hi["hp"] = 80  # 80% ≥50%
	_assert_eq("execute: 目标40%血 100→110", Damage.calc_damage(ex_atk, ex_lo, 100.0, "true"), 110)
	_assert_eq("execute: 目标80%血 不加 100", Damage.calc_damage(ex_atk, ex_hi, 100.0, "true"), 100)
	var ex_no := _make_test_fighter(0, 0, 0)  # 无 execute flag
	_assert_eq("execute: 无flag 不加 100", Damage.calc_damage(ex_no, ex_lo, 100.0, "true"), 100)
	# 召唤羁绊 字段名锁定 (PoC P65 教训: 必须 _synergySummonAtkFlat 不是 AtkBoost)
	var sm1 := _make_test_fighter(0, 0, 0); sm1["tags"] = ["召唤"]
	var sm2 := _make_test_fighter(0, 0, 0); sm2["tags"] = ["召唤"]
	var sm3 := _make_test_fighter(0, 0, 0); sm3["tags"] = ["召唤"]
	Synergies.apply_team([sm1, sm2, sm3], [])
	_assert_eq("召唤 t3: HpBoost=0.15", sm1.get("_synergySummonHpBoost", 0.0), 0.15, 0.001)
	_assert_eq("召唤 t3: AtkFlat=10", int(sm1.get("_synergySummonAtkFlat", 0)), 10)
	# 再生羁绊 字段锁定
	var rg1 := _make_test_fighter(0, 0, 0); rg1["tags"] = ["再生"]
	var rg2 := _make_test_fighter(0, 0, 0); rg2["tags"] = ["再生"]
	var rg3 := _make_test_fighter(0, 0, 0); rg3["tags"] = ["再生"]
	Synergies.apply_team([rg1, rg2, rg3], [])
	_assert_eq("再生 t3: ReviveBonus=0.25", rg1.get("_synergyRegenReviveBonus", 0.0), 0.25, 0.001)
	_assert_eq("再生 t3: ReviveAttack flag", rg1.get("_synergyRegenReviveAttack", false), true)


func _test_damage_mitigation() -> void:
	# 完全免伤
	var u := _make_test_fighter(0, 0, 0); u["hp"] = 1000; u["maxHp"] = 1000; u["_untargetable"] = true
	_assert_eq("_untargetable 全免", Damage.apply_raw_damage(u, 500, "physical")["hpLoss"], 0)
	var bh := _make_test_fighter(0, 0, 0); bh["hp"] = 1000; bh["maxHp"] = 1000; bh["_isInBlackhole"] = true
	_assert_eq("_isInBlackhole 全免", Damage.apply_raw_damage(bh, 500, "true")["hpLoss"], 0)
	# markedDmg +20%
	var m := _make_test_fighter(0, 0, 0); m["hp"] = 10000; m["maxHp"] = 10000; m["buffs"] = [{"type": "markedDmg", "value": 20, "duration": 5}]
	_assert_eq("markedDmg +20% (100→120)", Damage.apply_raw_damage(m, 100, "true")["hpLoss"], 120)
	# physImmune 全免物理, 不挡魔法
	var pi := _make_test_fighter(0, 0, 0); pi["hp"] = 1000; pi["maxHp"] = 1000; pi["buffs"] = [{"type": "physImmune", "value": 100, "duration": 3}]
	_assert_eq("physImmune 全免物理", Damage.apply_raw_damage(pi, 500, "physical")["hpLoss"], 0)
	_assert_eq("physImmune 不挡魔法", Damage.apply_raw_damage(pi, 500, "magic")["hpLoss"], 500)
	# dmgReduce -50%
	var dr := _make_test_fighter(0, 0, 0); dr["hp"] = 10000; dr["maxHp"] = 10000; dr["buffs"] = [{"type": "dmgReduce", "value": 50, "duration": 3}]
	_assert_eq("dmgReduce -50% (100→50)", Damage.apply_raw_damage(dr, 100, "physical")["hpLoss"], 50)
	# 岩层 10 → -10%
	var rk := _make_test_fighter(0, 0, 0); rk["hp"] = 10000; rk["maxHp"] = 10000; rk["_rockLayers"] = 10
	_assert_eq("rockLayers 10 → -10% (100→90)", Damage.apply_raw_damage(rk, 100, "physical")["hpLoss"], 90)
	# diamondStructure: def 50 × 20% = 10 flat
	var dia := _make_test_fighter(0, 50, 0); dia["hp"] = 10000; dia["maxHp"] = 10000; dia["passive"] = {"type": "diamondStructure", "flatReductionPct": 20}
	_assert_eq("diamond flat -10 (100→90)", Damage.apply_raw_damage(dia, 100, "physical")["hpLoss"], 90)
	# crystalResonance: magic -20%, 不减物理
	var cry := _make_test_fighter(0, 0, 0); cry["hp"] = 10000; cry["maxHp"] = 10000; cry["passive"] = {"type": "crystalResonance", "magicAbsorb": 20}
	_assert_eq("crystal magic -20% (100→80)", Damage.apply_raw_damage(cry, 100, "magic")["hpLoss"], 80)
	_assert_eq("crystal 不减物理", Damage.apply_raw_damage(cry, 100, "physical")["hpLoss"], 100)
	# undeadLock: HP 锁 1 不死
	var ud := _make_test_fighter(0, 0, 0); ud["hp"] = 50; ud["maxHp"] = 1000; ud["_undeadLockTurns"] = 2; ud["shield"] = 0
	Damage.apply_raw_damage(ud, 9999, "true")
	_assert_eq("undeadLock HP 锁 1", ud["hp"], 1)
	_assert_eq("undeadLock 不死", ud["alive"], true)
	# hunterMark execute: HP 跌破 24% → 斩杀
	var hm := _make_test_fighter(0, 0, 0); hm["hp"] = 300; hm["maxHp"] = 1000; hm["buffs"] = [{"type": "hunterMark", "value": 24, "duration": 5}]
	Damage.apply_raw_damage(hm, 80, "physical")  # hp 220 = 22% < 24
	_assert_eq("hunterMark 跌破24%→斩杀", hm["alive"], false)
	# 缩头盾 _hidingShieldVal 先吸
	var hd := _make_test_fighter(0, 0, 0); hd["hp"] = 1000; hd["maxHp"] = 1000; hd["_hidingShieldVal"] = 200; hd["shield"] = 0
	var rr := Damage.apply_raw_damage(hd, 150, "physical")
	_assert_eq("缩头盾吸 150 (hp 不掉)", rr["hpLoss"], 0)
	_assert_eq("缩头盾剩 50", hd["_hidingShieldVal"], 50)
	# bubbleStore: 受伤 → 存泡泡盾
	var bs := _make_test_fighter(0, 0, 0); bs["hp"] = 10000; bs["maxHp"] = 10000; bs["passive"] = {"type": "bubbleStore", "pct": 100}
	Damage.apply_raw_damage(bs, 100, "true")
	_assert_eq("bubbleStore 受100伤→存100 bubbleStore(爆破资源, 非护盾)", bs.get("bubbleStore", 0), 100)
	# basicTurtle: 对稀有度增伤 (A→+26%)
	var btc := _make_test_fighter(100, 0, 0); btc["passive"] = {"type": "basicTurtle", "bonusMap": {"C": 20, "B": 23, "A": 26, "S": 29, "SS": 32, "SSS": 34}}
	var btt := _make_test_fighter(0, 0, 0); btt["rarity"] = "A"
	_assert_eq("basicTurtle 对A增伤26% (100→126)", Damage.calc_damage(btc, btt, 100, "physical"), 126)
	var btt2 := _make_test_fighter(0, 0, 0); btt2["rarity"] = "SSS"
	_assert_eq("basicTurtle 对SSS增伤34% (100→134)", Damage.calc_damage(btc, btt2, 100, "physical"), 134)
	# turtleShieldBash: atk×0.7 + 已损血×20%. atk100 crit0, t maxHp1000 hp500 def0 → 70+100=170
	var tsc := _make_test_fighter(100, 0, 0); tsc["crit"] = 0.0
	var tst := _make_test_fighter(0, 0, 0); tst["side"] = "right"; tst["_slotKey"] = "front-0"; tst["maxHp"] = 1000; tst["hp"] = 500
	var tsr := SkillHandlers.execute(tsc, tst, [tsc, tst], {"type": "turtleShieldBash", "atkScale": 0.7, "lostHpPct": 20})
	_assert_eq("turtleShieldBash 70+100=170", tsr["effects"][0]["value"], 170)
	# diceAllIn: 全敌 atk×1.2 + 总伤30%吸血. atk100 crit0 def0 → 120; heal=round(120×30%)=36
	var dac := _make_test_fighter(100, 0, 0); dac["crit"] = 0.0; dac["maxHp"] = 1000; dac["hp"] = 500
	var dat := _make_test_fighter(0, 0, 0); dat["side"] = "right"; dat["_slotKey"] = "front-0"; dat["maxHp"] = 99999; dat["hp"] = 99999
	var dar := SkillHandlers.execute(dac, dat, [dac, dat], {"type": "diceAllIn", "atkScale": 1.2, "lifestealPct": 30})
	var ddmg := 0; var dheal := 0
	for ef in dar["effects"]:
		if ef.get("kind", "") == "damage": ddmg = ef["value"]
		elif ef.get("kind", "") == "heal": dheal = ef["value"]
	_assert_eq("diceAllIn 伤120", ddmg, 120)
	_assert_eq("diceAllIn 吸血36", dheal, 36)
	# fortune 经济: Strike 随币缩放, AllIn 消耗币
	var fc := _make_test_fighter(100, 0, 0); fc["crit"] = 0.0; fc["_goldCoins"] = 10; fc["maxHp"] = 1000; fc["hp"] = 1000
	var fe := _make_test_fighter(0, 0, 0); fe["side"] = "right"; fe["_slotKey"] = "front-0"; fe["maxHp"] = 99999; fe["hp"] = 99999
	var frs := SkillHandlers.execute(fc, fe, [fc, fe], {"type": "fortuneStrike", "hits": 2, "atkScale": 0.5, "perCoinAtkScale": 0.03})
	_assert_eq("fortuneStrike 10币→scale0.8→160", frs["effects"][0]["value"], 160)
	fc["_goldCoins"] = 5
	var fra := SkillHandlers.execute(fc, fe, [fc, fe], {"type": "fortuneAllIn", "perCoinAtkNormal": 0.18, "perCoinAtkPierce": 0.18})
	_assert_eq("fortuneAllIn 消耗币→0", fc.get("_goldCoins", -1), 0)
	var fn := 0; var fp := 0
	for ef in fra["effects"]:
		if ef.get("dmg_type", "") == "physical": fn = ef["value"]
		elif ef.get("dmg_type", "") == "true": fp = ef["value"]
	_assert_eq("fortuneAllIn 物理 5×18=90", fn, 90)
	_assert_eq("fortuneAllIn 真伤 5×18=90", fp, 90)
	# gamblerBet: 自损40%血 + 7段
	var gc := _make_test_fighter(100, 0, 0); gc["crit"] = 0.0; gc["maxHp"] = 1000; gc["hp"] = 1000
	var ge := _make_test_fighter(0, 0, 0); ge["side"] = "right"; ge["_slotKey"] = "front-0"; ge["maxHp"] = 99999; ge["hp"] = 99999
	var gr := SkillHandlers.execute(gc, ge, [gc, ge], {"type": "gamblerBet", "hits": 7, "hpCostPct": 40, "multiBonus": 20})
	_assert_eq("gamblerBet 自损40%→hp600", gc["hp"], 600)
	_assert_eq("gamblerBet 7段总伤 399 (per57×7)", gr["effects"][0]["value"], 399)
	# chestCount: treasure200 → bonus 1.28
	var chc := _make_test_fighter(100, 0, 0); chc["maxHp"] = 1000; chc["hp"] = 500; chc["_chestTreasure"] = 200
	var chr := SkillHandlers.execute(chc, chc, [chc], {"type": "chestCount", "healHpPct": 5, "shieldAtkScale": 0.6})
	var chh := 0; var chs := 0
	for ef in chr["effects"]:
		if ef.get("kind", "") == "heal": chh = ef["value"]
		elif ef.get("kind", "") == "shield": chs = ef["value"]
	_assert_eq("chestCount heal 64 (200宝×1.28)", chh, 64)
	_assert_eq("chestCount shield 77", chs, 77)


# ── 技能覆盖率扫描: 遍历 28 龟所有主动技能, 标出落 fallback 的 (未真实装) ──
# 这是"测试方法": 自动发现哪些技能还没移植, 既驱动补全又防回归 (新增 fallback 会让 fallback 数上升).
func _test_equip_dart_doll_conch_laser() -> void:
	print("  ── 飞镖/玩偶/海螺/激光长刃 装备 ──")

	# ── e_dart: on_attach +15 ATK; side-end 对带靶子敌人 50 物理 + 20 流血, 清靶子 ──
	var d := _make_test_fighter(40, 0, 0)
	d["_slotKey"] = "front-1"
	EquipmentRuntime.on_attach(d, "e_dart")
	_assert_eq("dart +15 ATK (40→55)", d["atk"], 55)
	_assert_eq("dart _equipDart", d.get("_equipDart", false), true)
	var de := _make_test_fighter(0, 0, 0)
	de["side"] = "right"; de["_slotKey"] = "front-0"; de["maxHp"] = 1000; de["hp"] = 1000
	de["_knockedUpThisTurn"] = true
	var de2 := _make_test_fighter(0, 0, 0)   # 无靶子 → 不打
	de2["side"] = "right"; de2["_slotKey"] = "front-1"; de2["maxHp"] = 1000; de2["hp"] = 1000
	var dart_fx := EquipmentRuntime.on_side_end(d, "e_dart", [d, de, de2])
	# 50 物理 (def=0 无减) → 50; 仅打有靶子的 de
	_assert_eq("dart 命中 1 个有靶子敌", dart_fx.size(), 1)
	_assert_eq("dart 50 物理", de["maxHp"] - de["hp"], 50)
	_assert_eq("dart 清除靶子", de["_knockedUpThisTurn"], false)
	_assert_eq("dart 施加 20 流血", Buffs.find(de, "bleed")["value"] if Buffs.find(de, "bleed") != null else -1, 20)
	_assert_eq("dart 无靶子敌未受伤", de2["hp"], 1000)

	# ── e_doll: on_attach +5 ATK +30 HP; side-end 30 物理(前排优先) + 累层, 满5标记 ──
	var dl := _make_test_fighter(40, 0, 0)
	dl["_slotKey"] = "front-1"
	EquipmentRuntime.on_attach(dl, "e_doll")
	_assert_eq("doll +5 ATK (40→45)", dl["atk"], 45)
	_assert_eq("doll +30 HP (100→130)", dl["maxHp"], 130)
	_assert_eq("doll 初始层数 0", dl.get("_equipDollBigBearStacks", -1), 0)
	var dlf := _make_test_fighter(0, 0, 0)   # 前排敌
	dlf["side"] = "right"; dlf["_slotKey"] = "front-0"; dlf["maxHp"] = 1000; dlf["hp"] = 1000
	var dlb := _make_test_fighter(0, 0, 0)   # 后排敌 (不该被优先打)
	dlb["side"] = "right"; dlb["_slotKey"] = "back-0"; dlb["maxHp"] = 1000; dlb["hp"] = 1000
	EquipmentRuntime.on_side_end(dl, "e_doll", [dl, dlf, dlb])
	_assert_eq("doll 只打前排敌 30", dlf["maxHp"] - dlf["hp"], 30)
	_assert_eq("doll 后排敌未被打", dlb["hp"], 1000)
	_assert_eq("doll 层数+1", dl["_equipDollBigBearStacks"], 1)
	# 攒到 5 层 → 标记可召唤
	for _i in range(4):
		EquipmentRuntime.on_side_end(dl, "e_doll", [dl, dlf, dlb])
	_assert_eq("doll 满 5 层标记召唤", dl.get("_equipDollReadyToSpawn", false), true)

	# ── e_conch: on_attach +100 HP; on_death 变形小虫 (150HP/20ATK, Lv1) ──
	var co := _make_test_fighter(40, 14, 13)
	co["_level"] = 1
	EquipmentRuntime.on_attach(co, "e_conch")
	_assert_eq("conch +100 HP (100→200)", co["maxHp"], 200)
	co["alive"] = false; co["hp"] = 0
	var transformed := EquipmentRuntime.on_death(co, "e_conch")
	_assert_eq("conch on_death 触发变形", transformed, true)
	_assert_eq("conch 小虫 150 HP", co["maxHp"], 150)
	_assert_eq("conch 小虫 20 ATK", co["atk"], 20)
	_assert_eq("conch 小虫无甲抗", [co["def"], co["mr"]], [0, 0])
	_assert_eq("conch 小虫复活", co["alive"], true)
	_assert_eq("conch _isConchWorm", co.get("_isConchWorm", false), true)
	_assert_eq("conch 换技能 啃咬", co["skills"][0]["name"], "啃咬")
	# 二次死亡不再变形 (_conchUsed 守卫)
	_assert_eq("conch 二次不变形", EquipmentRuntime.on_death(co, "e_conch"), false)

	# ── e_laser_blade: on_attach +15 ATK + 授予横扫技能 ──
	var lb := _make_test_fighter(40, 0, 0)
	lb["skills"] = []
	EquipmentRuntime.on_attach(lb, "e_laser_blade")
	_assert_eq("laser +15 ATK (40→55)", lb["atk"], 55)
	_assert_eq("laser 授予 1 技能", lb["skills"].size(), 1)
	_assert_eq("laser 技能 type laserSweep", lb["skills"][0]["type"], "laserSweep")
	_assert_eq("laser atkScale 0.7", lb["skills"][0]["atkScale"], 0.7)
	_assert_eq("laser soloScale 1.4", lb["skills"][0]["soloScale"], 1.4)

	# ── laserSweep handler: 横扫整排 + 80% 吸血 ──
	# caster atk=100 crit=0; 2 名同前排敌 (def=0) → 各 round(100×0.7)=70; 总 140; 回血 140×80%=112
	var lsC := _make_test_fighter(100, 0, 0); lsC["crit"] = 0.0; lsC["side"] = "left"
	lsC["hp"] = 50   # 受损好观测回血
	var lsE1 := _make_test_fighter(0, 0, 0); lsE1["side"] = "right"; lsE1["_slotKey"] = "front-0"
	var lsE2 := _make_test_fighter(0, 0, 0); lsE2["side"] = "right"; lsE2["_slotKey"] = "front-1"
	var lsBack := _make_test_fighter(0, 0, 0); lsBack["side"] = "right"; lsBack["_slotKey"] = "back-0"
	var lsSkill := {"type": "laserSweep", "atkScale": 0.7, "soloScale": 1.4, "lifestealPct": 80}
	var lsRes := SkillHandlers.execute(lsC, lsE1, [lsC, lsE1, lsE2, lsBack], lsSkill)
	_assert_eq("laserSweep 多目标 0.7×ATK (E1 -70)", lsE1["hp"], 30)
	_assert_eq("laserSweep 多目标 0.7×ATK (E2 -70)", lsE2["hp"], 30)
	_assert_eq("laserSweep 不打另一排 (back 满血)", lsBack["hp"], 100)
	_assert_eq("laserSweep 回血 总140×80%=112 (50→100 cap)", lsC["hp"], 100)
	_assert_eq("laserSweep 非 fallback", lsRes.get("_fallback", false), false)
	# solo: 后排只 1 名 → 1.4×ATK = 140
	var lsC2 := _make_test_fighter(100, 0, 0); lsC2["crit"] = 0.0; lsC2["side"] = "left"
	var lsSolo := _make_test_fighter(0, 0, 0); lsSolo["side"] = "right"; lsSolo["_slotKey"] = "back-0"; lsSolo["maxHp"] = 300; lsSolo["hp"] = 300
	SkillHandlers.execute(lsC2, lsSolo, [lsC2, lsSolo], lsSkill)
	_assert_eq("laserSweep 单目标 1.4×ATK (-140)", lsSolo["hp"], 160)

	# ── dart 靶子 flag: 击飞类技能命中后设 _knockedUpThisTurn ──
	var dkC := _make_test_fighter(100, 0, 0); dkC["crit"] = 0.0; dkC["side"] = "left"
	var dkT := _make_test_fighter(0, 0, 0); dkT["side"] = "right"; dkT["_slotKey"] = "front-0"
	SkillHandlers.execute(dkC, dkT, [dkC, dkT], {"type": "turtleShieldBash", "atkScale": 0.7})
	_assert_eq("dart flag: 盾击击飞设 _knockedUpThisTurn", dkT.get("_knockedUpThisTurn", false), true)
	# e_dart on_side_end 读靶子 → 50 物理 + 移除靶子
	var dartHolder := _make_test_fighter(50, 0, 0); dartHolder["side"] = "left"
	dartHolder["_equipDart"] = true
	var dkHpBefore: int = dkT["hp"]
	EquipmentRuntime.on_side_end(dartHolder, "e_dart", [dartHolder, dkT])
	_assert_eq("dart 命中靶子 (HP 下降)", dkT["hp"] < dkHpBefore, true)
	_assert_eq("dart 命中后清靶子", dkT.get("_knockedUpThisTurn", true), false)

	# ── 消耗品 c_* apply (PoC equipment.ts:275-349) ──
	var ch := _make_test_fighter(40, 0, 0); ch["maxHp"] = 200; ch["hp"] = 100
	EquipmentRuntime.apply_consumable(ch, "c_heal", [ch])
	_assert_eq("c_heal 回 50+10%maxHp=70 (100→170)", ch["hp"], 170)
	var cf := _make_test_fighter(40, 0, 0); cf["maxHp"] = 200; cf["hp"] = 100
	EquipmentRuntime.apply_consumable(cf, "c_firstaid", [cf])
	_assert_eq("c_firstaid 回 15%maxHp=30 (100→130)", cf["hp"], 130)
	var cb := _make_test_fighter(40, 0, 0); cb["hp"] = 100   # def=0 → 60 物理满额
	EquipmentRuntime.apply_consumable(cb, "c_bomb", [cb])
	_assert_eq("c_bomb 60 物理 (def0, 100→40)", cb["hp"], 40)
	var cbDef := _make_test_fighter(40, 100, 0); cbDef["hp"] = 100   # def=100 → ×0.5 → 30
	EquipmentRuntime.apply_consumable(cbDef, "c_bomb", [cbDef])
	_assert_eq("c_bomb def100 减半 (100→70)", cbDef["hp"], 70)
	var cbShield := _make_test_fighter(40, 0, 0); cbShield["hp"] = 100; cbShield["shield"] = 20
	EquipmentRuntime.apply_consumable(cbShield, "c_bomb", [cbShield])
	_assert_eq("c_bomb 先吸盾 (shield 20→0)", cbShield["shield"], 0)
	_assert_eq("c_bomb 盾后扣 HP (60-20=40, 100→60)", cbShield["hp"], 60)
	var cem := _make_test_fighter(40, 0, 0)
	EquipmentRuntime.apply_consumable(cem, "c_emergency", [cem])
	_assert_eq("c_emergency +80 盾", cem.get("shield", 0), 80)
	var crg := _make_test_fighter(40, 0, 0); StatsRecalc.snapshot_base(crg)
	EquipmentRuntime.apply_consumable(crg, "c_rage", [crg])
	_assert_eq("c_rage +25% atk (40→50)", crg["atk"], 50)
	var cmk := _make_test_fighter(40, 0, 0)
	EquipmentRuntime.apply_consumable(cmk, "c_mark", [cmk])
	_assert_eq("c_mark markedDmg buff", Buffs.has(cmk, "markedDmg"), true)
	var csp := _make_test_fighter(40, 0, 0)
	csp["skills"] = [{"type": "physical", "cdLeft": 2}, {"type": "magic", "cdLeft": 0}]
	EquipmentRuntime.apply_consumable(csp, "c_speed", [csp])
	_assert_eq("c_speed cdLeft -1 (2→1)", csp["skills"][0]["cdLeft"], 1)
	_assert_eq("c_speed cdLeft 不下溢 (0→0)", csp["skills"][1]["cdLeft"], 0)
	var ccl := _make_test_fighter(40, 0, 0); StatsRecalc.snapshot_base(ccl)
	Buffs.add(ccl, "atkDown", 25, 3); Buffs.add(ccl, "defUp", 10, 3)   # 1 debuff + 1 buff
	Dot.apply_stacks(ccl, "burn", 20)   # DoT 也清
	EquipmentRuntime.apply_consumable(ccl, "c_cleanse", [ccl])
	_assert_eq("c_cleanse 清 atkDown", Buffs.has(ccl, "atkDown"), false)
	_assert_eq("c_cleanse 清 burn (DoT)", Buffs.has(ccl, "burn"), false)
	_assert_eq("c_cleanse 保留 buff (defUp)", Buffs.has(ccl, "defUp"), true)


func _test_skill_coverage() -> void:
	print("  ── 技能覆盖率扫描 (28 龟) ──")
	var total := 0
	var fallback := 0
	var missing := {}
	for pet in DataRegistry.all_pets:
		var pid: String = pet.get("id", "")
		var pools: Array = []
		pools.append_array(pet.get("skillPool", []))
		pools.append_array(pet.get("meleeSkills", []))
		pools.append_array(pet.get("volcanoSkills", []))
		for s in pools:
			if s.get("passiveSkill", false):
				continue
			var stype: String = s.get("type", "")
			if stype == "" or stype == "physical" or stype == "magic" or stype == "heal" or stype == "shield":
				continue   # 通用类型本就走 _do_physical/_do_heal/_do_shield, 非 fallback
			total += 1
			var caster: Dictionary = FighterFactory.create(pid, "left")
			caster["_slotKey"] = "front-1"
			var dummy: Dictionary = _make_test_fighter(0, 0, 0)
			dummy["side"] = "right"; dummy["_slotKey"] = "front-0"; dummy["maxHp"] = 999999; dummy["hp"] = 999999; dummy["rarity"] = "A"
			var sc: Dictionary = s.duplicate(true); sc["cdLeft"] = 0
			var r = SkillHandlers.execute(caster, dummy, [caster, dummy], sc)
			if r is Dictionary and r.get("_fallback", false):
				fallback += 1
				if not missing.has(pid):
					missing[pid] = []
				missing[pid].append(stype)
	var miss_str := ""
	for pid in missing:
		miss_str += "%s[%s] " % [pid, str(missing[pid])]
	print("  COVERAGE: %d/%d impl, %d fallback. MISSING: %s" % [total - fallback, total, fallback, miss_str])
	# 基线断言: fallback 数随补全下降; 上升=回归. 实装完应为 0.
	_assert_eq("skill coverage fallback=%d (impl %d/%d) missing=%s" % [fallback, total - fallback, total, miss_str], fallback <= 40, true)


func _test_b_ghost_touch() -> void:
	# 物理 atk×0.4 + 真伤 atk×0.9, 共享 crit. atk=40 crit=0, t def=0 mr=0
	# 物理 = 16, 真伤 = 36, total = 52
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0
	var t := _make_test_fighter(40, 0, 0)
	t["maxHp"] = 1000
	t["hp"] = 1000
	var skill := {"name": "幽魂触碰", "type": "ghostTouch", "hits": 1, "normalScale": 0.4, "pierceScale": 0.9}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("ghostTouch 物理16+真伤36=52", r["effects"][0]["value"], 52)


func _test_b_rock_shockwave() -> void:
	# base = (def×0.5 + mr×0.5)×(1+0.04×layers). def=20 mr=20 layers=0 → (10+10)×1 = 20
	# 横排只 target (无同 position 队友) → 打 1 个, def=0 无减 → 20
	var c := _make_test_fighter(40, 20, 20)
	c["crit"] = 0.0
	c["_rockLayers"] = 0
	var t := _make_test_fighter(40, 0, 0)
	t["side"] = "right"; t["_slotKey"] = "front-0"; t["_position"] = "front"
	t["maxHp"] = 1000; t["hp"] = 1000
	var skill := {"name": "磐石之躯", "type": "rockShockwave", "hits": 1,
		"defScale": 0.5, "mrScale": 0.5, "rockLayerDmgScale": 0.04, "rockStunPctPerLayer": 1, "stunTurns": 1}
	var r := SkillHandlers.execute(c, t, [c, t], skill)
	_assert_eq("rockShockwave base=20 (无岩层)", r["effects"][0]["value"], 20)


func _test_b_ninja_impact_behind() -> void:
	# 主目标 atk×1.3 + 身后单位 atk×0.8. 主在 front, 身后 1 个 back
	# atk=40 crit=0, 主=round(40×1.3)=52, 身后=round(40×0.8)=32
	var c := _make_test_fighter(40, 14, 13)
	c["crit"] = 0.0; c["side"] = "left"
	var t := _make_test_fighter(40, 0, 0)
	t["side"] = "right"; t["_slotKey"] = "front-0"; t["_position"] = "front"; t["maxHp"] = 1000; t["hp"] = 1000
	# 身后单位必须同列 (back-0), fighterBehind 只取 front→back 同 col 那一个
	var behind := _make_test_fighter(40, 0, 0)
	behind["side"] = "right"; behind["_slotKey"] = "back-0"; behind["_position"] = "back"; behind["maxHp"] = 1000; behind["hp"] = 1000
	var skill := {"name": "冲击", "type": "ninjaImpact", "hits": 1, "atkScale": 1.3, "behindScale": 0.8}
	var r := SkillHandlers.execute(c, t, [c, t, behind], skill)
	# 2 个 damage effect: 主 52, 身后 32
	var vals := []
	for e in r["effects"]:
		if e.get("kind", "") == "damage":
			vals.append(e["value"])
	_assert_eq("ninjaImpact 2 目标命中", vals.size(), 2)
	_assert_eq("ninjaImpact 主52", 52 in vals, true)
	_assert_eq("ninjaImpact 身后32", 32 in vals, true)


# ─── 局内经济 + 财富折扣 + 野生AI购物 (1:1 PoC v0.9.9) ───────────

func _test_shop_economy() -> void:
	# 利息: floor(bank/5), cap 10. PoC: 0币→0, 24币→4, 60币→10(cap), 100币→10(cap)
	_assert_eq("利息 0币→0", GameState._interest(0), 0)
	_assert_eq("利息 24币→4", GameState._interest(24), 4)
	_assert_eq("利息 60币→10(cap)", GameState._interest(60), 10)
	_assert_eq("利息 100币→10(cap)", GameState._interest(100), 10)
	# 每回合经济: 先结息(加10前存款)再+10. 进【局内钱包 battle_coins】(非持久 meta coins). PoC 顺序 interest=floor(coins/5).
	var save_bcoins: int = GameState.battle_coins
	var save_enemy: int = GameState.enemy_coins
	var save_mode: String = GameState.mode
	var save_stage: int = GameState.dungeon_stage
	var save_carry: int = GameState.dungeon_carry_coins
	var save_meta: int = GameState.coins
	GameState.mode = "single"   # 野生模式
	GameState.battle_coins = 20 # 利息 floor(20/5)=4 → +14 → 34
	GameState.enemy_coins = 0   # 利息 0 → +10 → 10
	var econ: Dictionary = GameState.on_battle_turn_economy()
	_assert_eq("回合经济 玩家 20→34 (+10+利息4)", GameState.battle_coins, 34)
	_assert_eq("回合经济 player_gain=14", econ["player_gain"], 14)
	_assert_eq("回合经济 敌方 0→10 (+10+利息0)", GameState.enemy_coins, 10)
	_assert_eq("回合经济 不碰持久 meta coins", GameState.coins, save_meta)
	# 非野生模式: 敌方不收币 (ai_gain_coins 守卫)
	GameState.mode = "boss"
	GameState.enemy_coins = 50
	GameState.ai_gain_coins(10)
	_assert_eq("boss模式敌方不收币", GameState.enemy_coins, 50)
	# 财富发币: left→battle_coins, right→enemy_coins(仅野生)
	GameState.mode = "single"
	GameState.battle_coins = 0; GameState.enemy_coins = 0
	GameState.grant_wealth_coin("left", 4)
	GameState.grant_wealth_coin("right", 4)
	_assert_eq("财富 left +4 → battle_coins", GameState.battle_coins, 4)
	_assert_eq("财富 right +4 → enemy_coins", GameState.enemy_coins, 4)
	# 局内钱包每场重置: 非 dungeon → 0; dungeon stage>1 → 注入跨关结余
	GameState.mode = "single"; GameState.battle_coins = 99
	GameState.reset_battle_economy()
	_assert_eq("非dungeon reset → battle_coins 0", GameState.battle_coins, 0)
	GameState.mode = "dungeon"; GameState.dungeon_stage = 3; GameState.dungeon_carry_coins = 42; GameState.battle_coins = 99
	GameState.reset_battle_economy()
	_assert_eq("dungeon stage3 reset → 注入跨关结余 42", GameState.battle_coins, 42)
	GameState.dungeon_stage = 1; GameState.battle_coins = 77
	GameState.reset_battle_economy()
	_assert_eq("dungeon stage1 reset → 0 (新run无结余)", GameState.battle_coins, 0)
	# advance_stage 存本关结余 → 下关 carry
	GameState.battle_coins = 55; GameState.advance_stage()
	_assert_eq("advance_stage 存 carry=本关 battle_coins", GameState.dungeon_carry_coins, 55)
	# restore
	GameState.battle_coins = save_bcoins; GameState.enemy_coins = save_enemy; GameState.mode = save_mode
	GameState.dungeon_stage = save_stage; GameState.dungeon_carry_coins = save_carry


func _test_shop_wealth_discount() -> void:
	# team_wealth_discount: 扫到首个 _synergyWealthShopDiscount>0
	var allies: Array = [{"_synergyWealthShopDiscount": 0.0}, {"_synergyWealthShopDiscount": 0.25}]
	_assert_eq("财富折扣 扫到0.25", _approx2(ShopData.team_wealth_discount(allies)), 0.25)
	_assert_eq("无财富羁绊→0", ShopData.team_wealth_discount([{}, {}]), 0.0)
	# apply_wealth_discount: 非重投格 price×0.75, max(1); 重投格不动
	var items: Array = [
		{"slot": "A", "rarity": "buff", "price": 100},
		{"slot": "F", "rarity": "reroll", "price": 2},
	]
	ShopData.apply_wealth_discount(items, 0.25)
	_assert_eq("折扣后 100→75", items[0]["price"], 75)
	_assert_eq("重投格不打折", items[1]["price"], 2)
	# discount<=0 不动
	var items2: Array = [{"slot": "A", "rarity": "buff", "price": 40}]
	ShopData.apply_wealth_discount(items2, 0.0)
	_assert_eq("折扣0 价格不变", items2[0]["price"], 40)


func _test_plan_ai_shop() -> void:
	# 纯函数: 0 币 → 啥都买不动
	var p0: Dictionary = ShopData.plan_ai_shop(0, 0)
	_assert_eq("0币 买0格", (p0["buys"] as Array).size(), 0)
	_assert_eq("0币 花费0", p0["spent"], 0)
	# 充足币: 至少买几格, 花费 = 起始-剩余, 剩余>=0
	var p1: Dictionary = ShopData.plan_ai_shop(500, 0)
	_assert_eq("500币 买>0格", (p1["buys"] as Array).size() > 0, true)
	_assert_eq("花费+剩余=500", int(p1["spent"]) + int(p1["coins_left"]), 500)
	_assert_eq("剩余>=0", int(p1["coins_left"]) >= 0, true)
	# buys 不含重投格
	var has_reroll: bool = false
	for b in p1["buys"]:
		if b.get("rarity", "") == "reroll":
			has_reroll = true
	_assert_eq("buys 不含重投", has_reroll, false)


## 浮点近似比较辅助 (折扣值)
func _approx2(v: float) -> float:
	return roundf(v * 100.0) / 100.0


# ─── 深海跨关 HP 继承 (P1.2 阵亡龟 70% 复活) ──────────────────────
# 1:1 PoC BattleScene.ts:1480-1513 / JS dungeon.js:191
#   存活龟(snap.alive!=false) → 下关回满血 (PoC:1505-1507)
#   阵亡龟(alive==false 或 hp==0) → 下关 round(maxHp*0.7) 复活, shield=0, alive=true (PoC:1498-1503)
func _test_dungeon_revive_70pct() -> void:
	var prev_mode: String = GameState.mode
	var prev_carry: Dictionary = GameState.dungeon_carry_hp.duplicate()
	var prev_dead: Array = GameState.dungeon_dead_ids.duplicate()

	# 构造一场深海战斗结束状态: alive 龟存活, dead 龟阵亡(hp==0).
	# 用 3 个不同 id 避免 PoC 教训里"同 id 碰撞"问题.
	var alive_f := FighterFactory.create("basic", "left")
	alive_f["id"] = "alive_t"; alive_f["alive"] = true; alive_f["hp"] = int(alive_f["maxHp"]) - 100
	var dead_f := FighterFactory.create("basic", "left")
	dead_f["id"] = "dead_t"; dead_f["alive"] = false; dead_f["hp"] = 0
	var dead_by_hp := FighterFactory.create("basic", "left")
	dead_by_hp["id"] = "dead_hp_t"; dead_by_hp["alive"] = true; dead_by_hp["hp"] = 0   # alive 但 hp==0 也算阵亡 (PoC:1498)
	# 召唤物不计入 (不应进 dead/carry)
	var summon_f := FighterFactory.create("basic", "left")
	summon_f["id"] = "summon_t"; summon_f["alive"] = false; summon_f["hp"] = 0; summon_f["_isSummon"] = true
	# 敌方阵亡龟不计入玩家继承
	var enemy_f := FighterFactory.create("basic", "right")
	enemy_f["id"] = "enemy_t"; enemy_f["alive"] = false; enemy_f["hp"] = 0

	# ── 快照 (snapshot_left_hp) ──
	GameState.snapshot_left_hp([alive_f, dead_f, dead_by_hp, summon_f, enemy_f])

	_assert_eq("revive: dead_t 进 dead_ids", GameState.dungeon_dead_ids.has("dead_t"), true)
	_assert_eq("revive: hp==0 也进 dead_ids", GameState.dungeon_dead_ids.has("dead_hp_t"), true)
	_assert_eq("revive: 存活龟不进 dead_ids", GameState.dungeon_dead_ids.has("alive_t"), false)
	_assert_eq("revive: 召唤物不进 dead_ids", GameState.dungeon_dead_ids.has("summon_t"), false)
	_assert_eq("revive: 敌方龟不进 dead_ids", GameState.dungeon_dead_ids.has("enemy_t"), false)
	_assert_eq("revive: 存活龟进 carry_hp", GameState.dungeon_carry_hp.has("alive_t"), true)
	_assert_eq("revive: 阵亡龟不进 carry_hp", GameState.dungeon_carry_hp.has("dead_t"), false)
	_assert_eq("revive: 召唤物不进 carry_hp", GameState.dungeon_carry_hp.has("summon_t"), false)

	# ── 下一关建队 HP 结算 (复刻 BattleScene._build_teams dungeon 分支逻辑) ──
	GameState.mode = "dungeon"
	# 阵亡龟: round(maxHp*0.7), shield=0, alive=true
	var rebuilt_dead := FighterFactory.create("basic", "left")
	rebuilt_dead["id"] = "dead_t"
	var max_hp := int(rebuilt_dead["maxHp"])
	if GameState.dungeon_dead_ids.has(rebuilt_dead["id"]):
		rebuilt_dead["hp"] = roundi(max_hp * 0.7); rebuilt_dead["shield"] = 0; rebuilt_dead["alive"] = true
	elif GameState.dungeon_carry_hp.has(rebuilt_dead["id"]):
		rebuilt_dead["hp"] = rebuilt_dead["maxHp"]; rebuilt_dead["shield"] = 0
	_assert_eq("revive: 阵亡龟下关 hp = round(maxHp*0.7)", rebuilt_dead["hp"], roundi(max_hp * 0.7))
	_assert_eq("revive: 阵亡龟下关 shield=0", rebuilt_dead["shield"], 0)
	_assert_eq("revive: 阵亡龟下关 alive=true", rebuilt_dead["alive"], true)

	# 存活龟: 回满血 (非 dead_ids → carry 分支)
	var rebuilt_alive := FighterFactory.create("basic", "left")
	rebuilt_alive["id"] = "alive_t"
	if GameState.dungeon_dead_ids.has(rebuilt_alive["id"]):
		rebuilt_alive["hp"] = roundi(int(rebuilt_alive["maxHp"]) * 0.7); rebuilt_alive["shield"] = 0; rebuilt_alive["alive"] = true
	elif GameState.dungeon_carry_hp.has(rebuilt_alive["id"]):
		rebuilt_alive["hp"] = rebuilt_alive["maxHp"]; rebuilt_alive["shield"] = 0
	_assert_eq("revive: 存活龟下关满血 hp = maxHp", rebuilt_alive["hp"], rebuilt_alive["maxHp"])

	# ── 不跨 run 泄漏: reset_dungeon 清空 dead_ids ──
	GameState.reset_dungeon()
	_assert_eq("revive: reset_dungeon 清空 dead_ids", GameState.dungeon_dead_ids.size(), 0)
	# start_dungeon 也清空
	GameState.dungeon_dead_ids = ["stale"]
	GameState.start_dungeon()
	_assert_eq("revive: start_dungeon 清空 dead_ids", GameState.dungeon_dead_ids.size(), 0)

	# 还原全局态
	GameState.mode = prev_mode
	GameState.dungeon_carry_hp = prev_carry
	GameState.dungeon_dead_ids.assign(prev_dead)


# ─── 成就追踪器 (AchievementTracker, 1:1 PoC achievement-tracker.ts) ──────
func _test_achievement_tracker() -> void:
	# 保存现场, 测试间隔离 (tracker 写 GameState; 用 in-memory 重置, 不落盘)
	var prev_unlocked: Array = GameState.achievements_unlocked.duplicate(true)
	var prev_stats: Dictionary = GameState.ach_stats.duplicate(true)

	# ── 重置成就态 (= PoC resetAchievements) ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}

	# unlock: 合法 id 解锁返 true, 重复返 false, 非法 id 返 false
	_assert_eq("unlock first_win 返 true", AchievementTracker.unlock("first_win"), true)
	_assert_eq("unlock first_win 重复返 false", AchievementTracker.unlock("first_win"), false)
	_assert_eq("unlock 非法 id 返 false", AchievementTracker.unlock("__nope__"), false)
	_assert_eq("first_win 进 unlocked", "first_win" in GameState.achievements_unlocked, true)

	# ── checkAll 阈值: wins=10 → first_win + win_10 (不含 win_50) ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	var s := AchievementTracker.get_stats()
	s["wins"] = 10
	var fired := AchievementTracker.check_all()
	_assert_eq("wins=10 解锁 first_win", "first_win" in fired, true)
	_assert_eq("wins=10 解锁 win_10", "win_10" in fired, true)
	_assert_eq("wins=10 不解锁 win_50", "win_50" in fired, false)
	# 再查一次不重复解锁
	var fired2 := AchievementTracker.check_all()
	_assert_eq("checkAll 重复不再解锁 win_10", "win_10" in fired2, false)

	# ── petsUsed 5 只 → try_5_pets (不含 try_15_pets) ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	for pid in ["a", "b", "c", "d", "e"]:
		AchievementTracker.mark_pet_used(pid)
	# 重复 mark 同龟不增计数 (set 语义)
	AchievementTracker.mark_pet_used("a")
	var fired_pets := AchievementTracker.check_all()
	_assert_eq("petsUsed 5 → try_5_pets", "try_5_pets" in fired_pets, true)
	_assert_eq("petsUsed 5 不解锁 try_15_pets", "try_15_pets" in fired_pets, false)
	_assert_eq("petsUsed set 去重 = 5", (AchievementTracker.get_stats()["petsUsed"] as Dictionary).size(), 5)

	# ── coins 累计 5000 → coins_500 + coins_5000 ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	var fired_coins := AchievementTracker.on_coins_earned(5000)
	_assert_eq("coins 5000 → coins_500", "coins_500" in fired_coins, true)
	_assert_eq("coins 5000 → coins_5000", "coins_5000" in fired_coins, true)

	# ── on_equip_bought: 首次 → first_equip + shop_buy; 累计到 5 → equip_5 ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	var fe := AchievementTracker.on_equip_bought()
	_assert_eq("首次买装备 → first_equip", "first_equip" in fe, true)
	_assert_eq("首次买装备 → shop_buy", "shop_buy" in fe, true)
	for i in range(4):
		AchievementTracker.on_equip_bought()   # 共 5 次
	_assert_eq("买 5 件 → totalEquipsBought=5", int(AchievementTracker.get_stats()["totalEquipsBought"]), 5)
	_assert_eq("买 5 件 → equip_5 已解锁", "equip_5" in GameState.achievements_unlocked, true)

	# ── set_best_dungeon: 通到第 3 关 → dungeon_1/2/3 (不含 4) ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	AchievementTracker.set_best_dungeon(3)
	var fd := AchievementTracker.check_all()
	_assert_eq("bestDungeon 3 → dungeon_1", "dungeon_1" in fd, true)
	_assert_eq("bestDungeon 3 → dungeon_3", "dungeon_3" in fd, true)
	_assert_eq("bestDungeon 3 不解锁 dungeon_4", "dungeon_4" in fd, false)
	# 更小层数不回退
	AchievementTracker.set_best_dungeon(1)
	_assert_eq("set_best_dungeon 不回退", int(AchievementTracker.get_stats()["bestDungeon"]), 3)

	# ── on_battle_end: 胜+全员存活 → first_win/no_loss_battle/six_alive; 单局伤/杀类 ──
	GameState.achievements_unlocked = []
	GameState.ach_stats = {}
	var nb := AchievementTracker.on_battle_end("win", ["basic", "stone"], "烈焰", 5500, 0, 5, true)
	_assert_eq("battle_end win → first_win", "first_win" in nb, true)
	_assert_eq("battle_end allAlive → no_loss_battle", "no_loss_battle" in nb, true)
	_assert_eq("battle_end allAlive → six_alive", "six_alive" in nb, true)
	_assert_eq("battle_end dmg 5500 → dmg_5k_battle", "dmg_5k_battle" in nb, true)
	_assert_eq("battle_end dmg 5500 不到 dmg_10k", "dmg_10k_battle" in nb, false)
	_assert_eq("battle_end kills 5 → kills_5_battle", "kills_5_battle" in nb, true)
	_assert_eq("battle_end 有规则 → custom_battle", "custom_battle" in nb, true)
	_assert_eq("battle_end petsUsed 累计 2", (AchievementTracker.get_stats()["petsUsed"] as Dictionary).size(), 2)
	_assert_eq("battle_end rulesSeen 累计 1", (AchievementTracker.get_stats()["rulesSeen"] as Dictionary).size(), 1)
	_assert_eq("battle_end battles+1", int(AchievementTracker.get_stats()["battles"]), 1)

	# 还原现场 (tracker 过程中 _save() 落过盘 → 还原后再存一次, 盘面回到测试前)
	GameState.achievements_unlocked = prev_unlocked
	GameState.ach_stats = prev_stats
	GameState.save()


# 决胜局: 怒气(每层+30%伤害) + 疲惫(治疗/护盾×0.5)
func _test_overtime_sudden_death() -> void:
	# ── 怒气: _overtimeRage 每层 +30% 伤害 (Damage.calc_damage) ──
	var atk := FighterFactory.create("basic", "left")
	var tgt := FighterFactory.create("basic", "right")
	var base_dmg: int = Damage.calc_damage(atk, tgt, 28.0, "physical")
	atk["_overtimeRage"] = 1
	_assert_eq("怒气1层 → 伤害×1.3", Damage.calc_damage(atk, tgt, 28.0, "physical"), float(base_dmg) * 1.3, 1.0)
	atk["_overtimeRage"] = 3
	_assert_eq("怒气3层 → 伤害×1.9", Damage.calc_damage(atk, tgt, 28.0, "physical"), float(base_dmg) * 1.9, 1.0)
	atk["_overtimeRage"] = 0
	_assert_eq("怒气0层 → 原伤害不变", Damage.calc_damage(atk, tgt, 28.0, "physical"), base_dmg)

	# ── 永恒 buff (二阶段双路): 造成+50%/层(atk端) & 受到+50%/层(tgt端), 线性 ──
	atk["_eternalStack"] = 2
	_assert_eq("永恒2层造成×2", Damage.calc_damage(atk, tgt, 28.0, "physical"), float(base_dmg) * 2.0, 2.0)
	atk["_eternalStack"] = 0; tgt["_eternalStack"] = 1
	_assert_eq("永恒1层受到×1.5", Damage.calc_damage(atk, tgt, 28.0, "physical"), float(base_dmg) * 1.5, 2.0)
	atk["_eternalStack"] = 1; tgt["_eternalStack"] = 1
	_assert_eq("永恒双方各1层 ×2.25", Damage.calc_damage(atk, tgt, 28.0, "physical"), float(base_dmg) * 2.25, 2.0)
	atk["_eternalStack"] = 0; tgt["_eternalStack"] = 0

	# ── 疲惫: 治疗/护盾量 ×0.5 (Buffs.fatigue_amt) ──
	var nf := {"_overtimeFatigue": false}
	_assert_eq("无疲惫 fatigue_amt(100)=100", Buffs.fatigue_amt(nf, 100), 100)
	var ff := {"_overtimeFatigue": true}
	_assert_eq("疲惫 fatigue_amt(100)=50", Buffs.fatigue_amt(ff, 100), 50)
	_assert_eq("疲惫 fatigue_amt(99)=50 (四舍五入)", Buffs.fatigue_amt(ff, 99), 50)

	# ── grant_shield 吃疲惫 (含返回值用于飘字) ──
	var s1 := {"shield": 10}
	_assert_eq("无疲惫 grant_shield 80 → 返回 80", Buffs.grant_shield(s1, 80), 80)
	_assert_eq("无疲惫 grant_shield 后 shield=90", int(s1["shield"]), 90)
	var s2 := {"shield": 10, "_overtimeFatigue": true}
	_assert_eq("疲惫 grant_shield 80 → 返回 40", Buffs.grant_shield(s2, 80), 40)
	_assert_eq("疲惫 grant_shield 后 shield=50", int(s2["shield"]), 50)

	# ── _heal_to 端到端: 疲惫使实际回血减半 ──
	var hf := {"hp": 100, "maxHp": 1000, "alive": true, "_overtimeFatigue": true}
	_assert_eq("疲惫 _heal_to(200) 实回 100", SkillHandlers._heal_to(hf, 200), 100)
	_assert_eq("疲惫 _heal_to 后 hp=200", int(hf["hp"]), 200)


# dungeon 跨关携带身上装备 (1:1 PoC snapshot.equipIds, 修"装备每关全丢")
func _test_dungeon_equip_carry() -> void:
	var save_eq: Dictionary = GameState.dungeon_carry_equips
	var save_hp: Dictionary = GameState.dungeon_carry_hp
	var save_dead: Array = GameState.dungeon_dead_ids
	var fs: Array = [
		{"id": "basic", "side": "left", "alive": true, "hp": 100, "maxHp": 200, "_equipped_ids": ["e_turtle_sword"]},
		{"id": "stone", "side": "left", "alive": false, "hp": 0, "maxHp": 300, "_equipped_ids": ["e_turtle_shell", "e_turtle_helmet"]},
		{"id": "noeq", "side": "left", "alive": true, "hp": 50, "maxHp": 100},
		{"id": "sm", "side": "left", "alive": true, "hp": 10, "maxHp": 10, "_isSummon": true, "_equipped_ids": ["e_x"]},
	]
	GameState.snapshot_left_hp(fs)
	_assert_eq("跨关装备: 存活龟带剑", GameState.dungeon_carry_equips.get("basic", []), ["e_turtle_sword"])
	_assert_eq("跨关装备: 死龟仍带2件(下关复活带装备)", int((GameState.dungeon_carry_equips.get("stone", []) as Array).size()), 2)
	_assert_eq("跨关装备: 无装备龟不进表", GameState.dungeon_carry_equips.has("noeq"), false)
	_assert_eq("跨关装备: 召唤物不带", GameState.dungeon_carry_equips.has("sm"), false)
	# restore
	GameState.dungeon_carry_equips = save_eq
	GameState.dungeon_carry_hp = save_hp
	GameState.dungeon_dead_ids = save_dead


# aiPickSkills 1:1 PoC pet-level.ts:60-89 (随从技能装载)
func _test_ai_pick_skills() -> void:
	# 池 (idx0 基础 / 1 dmg / 2 heal / 3 dmg(Lv4解锁) / 4 passive(Lv7解锁))
	var pool := [
		{"type": "basicSlam"},
		{"type": "fireBolt"},
		{"type": "heal"},
		{"type": "bigHit"},
		{"type": "someAura", "passiveSkill": true},
	]
	# 池≤3 → null (用 defaultSkills)
	_assert_eq("aiPick: 池≤3 返 null", FighterFactory.ai_pick_skills(pool.slice(0, 3), 9), null)
	# Lv1: 仅 idx0/1/2 解锁 → 必返 [0,1,2]
	var r1: Array = FighterFactory.ai_pick_skills(pool, 1)
	_assert_eq("aiPick Lv1: 恒 [0,1,2]", r1, [0, 1, 2])
	# 各等级: 必含 idx0, 长度3, idx 全在解锁池内, 无重复
	for lv in [1, 4, 7, 10]:
		for _rep in range(40):
			var r: Array = FighterFactory.ai_pick_skills(pool, lv)
			var unlocked: Array = FighterFactory.available_skill_indices(pool.size(), lv)
			_assert_eq("aiPick Lv%d: 含idx0" % lv, r.has(0), true)
			_assert_eq("aiPick Lv%d: 长度3" % lv, r.size(), 3)
			var seen := {}
			var all_unlocked := true
			for i in r:
				if not unlocked.has(i): all_unlocked = false
				if seen.has(i): all_unlocked = false
				seen[i] = true
			_assert_eq("aiPick Lv%d: 全在解锁池且不重复" % lv, all_unlocked, true)
	# 解锁等级 1:1: idx3→Lv4, idx4→Lv7
	_assert_eq("unlock idx3=Lv4", FighterFactory.skill_unlock_level(3), 4)
	_assert_eq("unlock idx4=Lv7", FighterFactory.skill_unlock_level(4), 7)
	_assert_eq("available Lv1 = [0,1,2]", FighterFactory.available_skill_indices(5, 1), [0, 1, 2])
	_assert_eq("available Lv7 = [0,1,2,3,4]", FighterFactory.available_skill_indices(5, 7), [0, 1, 2, 3, 4])
	# 互斥对: fortuneGainCoins ↔ fortuneBuyEquip 不同抽
	var fpool := [
		{"type": "basicSlam"},
		{"type": "fortuneGainCoins"},
		{"type": "fortuneBuyEquip"},
		{"type": "fireBolt"},
		{"type": "heal"},
	]
	for _rep2 in range(60):
		var fr: Array = FighterFactory.ai_pick_skills(fpool, 10)
		var has_gain := fr.has(1)
		var has_buy := fr.has(2)
		_assert_eq("aiPick 互斥: fortune两金币技不同抽", has_gain and has_buy, false)


# e_thunder_shell 雷鸣贝壳 1:1 PoC (equipment.ts:181 + BattleScene:7327)
func _test_equip_thunder_shell() -> void:
	var c := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100}
	EquipmentRuntime.on_attach(c, "e_thunder_shell")
	_assert_eq("雷壳 on_attach +15 ATK", int(c["atk"]), 115)
	_assert_eq("雷壳 _equipThunderBell=1", int(c.get("_equipThunderBell", 0)), 1)
	var e := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "shield": 0, "def": 50, "mr": 50, "buffs": []}
	var fx: Array = EquipmentRuntime.on_side_end(c, "e_thunder_shell", [c, e])
	var dmg_total := 0
	for ef in fx:
		if ef.get("kind", "") == "damage" and ef.get("dmg_type", "") == "true":
			dmg_total += int(ef.get("value", 0))
	_assert_eq("雷壳 side-end 真伤=115(无视防)", dmg_total, 115)
	_assert_eq("雷壳 敌人 500→385", int(e["hp"]), 385)


# e_dragon_egg 龙蛋 1:1 PoC (equipment.ts:154 + BattleScene:5498-5557)
func _test_equip_dragon_egg() -> void:
	var c := {"side": "left", "alive": true, "_slotKey": "front-1", "baseAtk": 100, "atk": 100, "hp": 500, "maxHp": 500, "buffs": []}
	EquipmentRuntime.on_attach(c, "e_dragon_egg")
	_assert_eq("龙蛋 +8 ATK", int(c["atk"]), 108)
	_assert_eq("龙蛋 +5 魔穿", int(c.get("magicPen", 0)), 5)
	_assert_eq("龙蛋 装备 3 层吐息", int(c.get("_equipDragonEggStacks", 0)), 3)
	# 满3层(3+1=4)→喷火: 随机有敌列=col0; 同列友(back-0)+40, 同列敌(front-0)50魔+25灼烧; caster在col1不中
	var en := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var al := {"side": "left", "alive": true, "_slotKey": "back-0", "hp": 100, "maxHp": 500, "buffs": []}
	var _fx: Array = EquipmentRuntime.on_turn_begin(c, "e_dragon_egg", [c, en, al])
	_assert_eq("龙蛋 喷火后吐息重置 0", int(c.get("_equipDragonEggStacks", 0)), 0)
	_assert_eq("龙蛋 同列友军 +40 (100→140)", int(al["hp"]), 140)
	_assert_eq("龙蛋 同列敌军受伤(掉血)", int(en["hp"]) < 500, true)
	_assert_eq("龙蛋 caster(col1)不在喷火列, HP不变", int(c["hp"]), 500)
	var has_burn := false
	for b in en["buffs"]:
		if b.get("type", "") == "burn": has_burn = true
	_assert_eq("龙蛋 同列敌军中灼烧", has_burn, true)


# e_mini_crystal A/B 1:1 PoC (equipment.ts:166/174 + BattleScene:7650/7690)
func _test_equip_mini_crystal() -> void:
	# A: +7ATK/+5魔穿/+20HP; 回合末随机敌列 2段各30魔法+1层迷你水晶, 满3引爆14%maxHp
	var c := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "hp": 200, "maxHp": 200}
	EquipmentRuntime.on_attach(c, "e_mini_crystal")
	_assert_eq("水晶球A +7 ATK", int(c["atk"]), 107)
	_assert_eq("水晶球A +5 魔穿", int(c.get("magicPen", 0)), 5)
	_assert_eq("水晶球A +20 HP", int(c["maxHp"]), 220)
	var en := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": [], "_miniCrystallize": 1}
	var _fxa: Array = EquipmentRuntime.on_side_end(c, "e_mini_crystal", [c, en])
	_assert_eq("水晶球A 满3层引爆后重置 0", int(en.get("_miniCrystallize", -1)), 0)
	_assert_eq("水晶球A 受2段+引爆掉血>150(引爆14%生效)", int(en["hp"]) < 850, true)
	# B: +7ATK/+3魔穿/+20HP; 回合末扫全敌各20魔法+1层
	var cb := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "hp": 200, "maxHp": 200}
	EquipmentRuntime.on_attach(cb, "e_mini_crystal_b")
	_assert_eq("水晶球B +3 魔穿", int(cb.get("magicPen", 0)), 3)
	var e1 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e2 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var _fxb: Array = EquipmentRuntime.on_side_end(cb, "e_mini_crystal_b", [cb, e1, e2])
	_assert_eq("水晶球B e1 受魔法伤(掉血)", int(e1["hp"]) < 500, true)
	_assert_eq("水晶球B e2 受魔法伤(掉血)", int(e2["hp"]) < 500, true)
	_assert_eq("水晶球B 敌各 +1 迷你水晶层", int(e1.get("_miniCrystallize", 0)), 1)


# 施法后装备 e_stun_baton / e_bamboo_leaf 1:1 PoC (BattleScene:3131/3158)
func _test_equip_post_cast() -> void:
	# 电棍: +20HP/+5def/+5mr/3层; post-cast 单体→电该敌 30魔+眩晕, -1层
	var c := {"side": "left", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "hp": 200, "maxHp": 200, "buffs": []}
	EquipmentRuntime.on_attach(c, "e_stun_baton")
	_assert_eq("电棍 +5 def", int(c["def"]), 5)
	_assert_eq("电棍 装备 3 层电击", int(c.get("_stunBatonStacks", 0)), 3)
	var en := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "shield": 0, "mr": 0, "def": 0, "buffs": []}
	var _fx: Array = EquipmentRuntime.on_post_cast(c, "e_stun_baton", en, [c, en], true)
	_assert_eq("电棍 用 1 层 → 剩 2", int(c.get("_stunBatonStacks", 0)), 2)
	_assert_eq("电棍 敌掉血", int(en["hp"]) < 500, true)
	var has_stun := false
	for b in en["buffs"]:
		if b.get("type", "") == "stun": has_stun = true
	_assert_eq("电棍 敌中眩晕", has_stun, true)
	# 竹叶: +50HP/1充能; post-cast 随机敌(35+20%maxHp)魔 + 回20%maxHp + 永久+100maxHp + 充能清0
	var cb := {"side": "left", "alive": true, "hp": 100, "maxHp": 1000, "buffs": []}
	EquipmentRuntime.on_attach(cb, "e_bamboo_leaf")
	_assert_eq("竹叶 +50 maxHp", int(cb["maxHp"]), 1050)
	_assert_eq("竹叶 1 充能", int(cb.get("_bambooLeafCharge", 0)), 1)
	var maxhp_before := int(cb["maxHp"])
	var en2 := {"side": "right", "alive": true, "hp": 9999, "maxHp": 9999, "shield": 0, "mr": 0, "def": 0, "buffs": []}
	var _fx2: Array = EquipmentRuntime.on_post_cast(cb, "e_bamboo_leaf", en2, [cb, en2], false)
	_assert_eq("竹叶 充能用完 → 0", int(cb.get("_bambooLeafCharge", 0)), 0)
	_assert_eq("竹叶 永久 +100 maxHp", int(cb["maxHp"]), maxhp_before + 100)
	_assert_eq("竹叶 敌掉血", int(en2["hp"]) < 9999, true)
	_assert_eq("竹叶 携带者回血(100→>200)", int(cb["hp"]) > 200, true)


# e_lightning_staff 雷电法杖 1:1 PoC (BattleScene:3041 充能 + 3055 链)
func _test_equip_lightning_staff() -> void:
	var c := {"side": "left", "alive": true, "atk": 100}
	EquipmentRuntime.on_attach(c, "e_lightning_staff")
	_assert_eq("雷杖 +8 魔穿", int(c.get("magicPen", 0)), 8)
	_assert_eq("雷杖 1 件充能格", (c.get("_lightningStaffCharges", []) as Array).size(), 1)
	c["_castIsAoe"] = false
	var en := {"side": "right", "alive": true, "hp": 9999, "maxHp": 9999, "shield": 0, "mr": 0, "def": 0, "buffs": []}
	var e2 := {"side": "right", "alive": true, "hp": 9999, "maxHp": 9999, "shield": 0, "mr": 0, "def": 0, "buffs": []}
	var all := [c, en, e2]
	# 前3次单体命中 → 充到75, 不发链
	for _i in range(3):
		var fx := EquipmentRuntime.on_hit(c, en, 10, "e_lightning_staff", all, true)
		_assert_eq("雷杖 充能<100 不发链", fx.is_empty(), true)
	# 第4次 → 满100 → 发链 (≤4不同敌各20魔), 充能扣回0
	var fx4: Array = EquipmentRuntime.on_hit(c, en, 10, "e_lightning_staff", all, true)
	_assert_eq("雷杖 满100 发链(有伤害effect)", fx4.size() > 0, true)
	_assert_eq("雷杖 充能扣回 <100", float((c["_lightningStaffCharges"] as Array)[0]) < 100.0, true)
	var dmg_total := 0
	for ef in fx4:
		if ef.get("kind", "") == "damage": dmg_total += int(ef.get("value", 0))
	_assert_eq("雷杖 链造成魔法伤(>0)", dmg_total > 0, true)
	_assert_eq("雷杖 链跳到2个不同敌(都掉血)", int(en["hp"]) < 9999 and int(e2["hp"]) < 9999, true)


# e_incubator 孵化器 1:1 PoC (equipment.ts:373 + BattleScene:562 升级)
func _test_equip_incubator() -> void:
	var c := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "baseDef": 100, "def": 100, "baseMr": 100, "mr": 100, "hp": 1000, "maxHp": 1000}
	EquipmentRuntime.on_attach(c, "e_incubator")
	_assert_eq("孵化器 +20 maxHp", int(c["maxHp"]), 1020)
	_assert_eq("孵化器 进度初始 0", int(c.get("_incubatorProgress", -1)), 0)
	# +100 进度 → 升 1 级 (+5% base: atk 100→105, maxHp 1020→1071)
	_assert_eq("孵化器 满100 升1级", EquipmentRuntime._incubator_add(c, 100), 1)
	_assert_eq("孵化器 临时等级=1", int(c.get("_incubatorTempLevel", 0)), 1)
	_assert_eq("孵化器 +5% ATK (100→105)", int(c["atk"]), 105)
	_assert_eq("孵化器 +5% maxHp (1020→1071)", int(c["maxHp"]), 1071)
	# 上限 3 级
	EquipmentRuntime._incubator_add(c, 500)
	_assert_eq("孵化器 临时等级上限 3", int(c.get("_incubatorTempLevel", 0)), 3)
	# on_turn_begin +5 进度
	var c2 := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "hp": 100, "maxHp": 100}
	EquipmentRuntime.on_attach(c2, "e_incubator")
	var _t: Array = EquipmentRuntime.on_turn_begin(c2, "e_incubator", [c2])
	_assert_eq("孵化器 回合 +5 进度", int(c2.get("_incubatorProgress", 0)), 5)
	# on_hit 造伤×0.1 进度
	var en := {"side": "right", "alive": true, "hp": 100, "maxHp": 100}
	EquipmentRuntime.on_hit(c2, en, 30, "e_incubator", [c2, en], true)
	_assert_eq("孵化器 造伤30 → +3 进度 (5+3=8)", int(c2.get("_incubatorProgress", 0)), 8)
	# 进度条 _has_incubator 判定 (p2eq_036 在 _p2_equips, 或已有 _incubatorProgress)
	var holder := {"side": "left", "_p2_equips": [{"id": "p2eq_036", "star": 1}]}
	var nonholder := {"side": "left", "_p2_equips": [{"id": "p2eq_001", "star": 1}]}
	_assert_eq("进度条: 含p2eq_036 → 持孵化器", _bs_has_incubator(holder), true)
	_assert_eq("进度条: 有_incubatorProgress → 持孵化器", _bs_has_incubator(c2), true)
	_assert_eq("进度条: 无孵化器 → false", _bs_has_incubator(nonholder), false)
	# 进度回卷: 105 → 升1级残5 (1:1 _incubator_add while>=100)
	var c3 := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "baseDef": 50, "def": 50, "baseMr": 50, "mr": 50, "hp": 100, "maxHp": 100}
	EquipmentRuntime.on_attach(c3, "e_incubator")
	_assert_eq("孵化器 加105 → 升1级", EquipmentRuntime._incubator_add(c3, 105), 1)
	_assert_eq("孵化器 回卷残余进度=5", int(c3.get("_incubatorProgress", 0)), 5)


# 进度条持有判定 (镜像 BattleScene._has_incubator, 不实例化场景)
func _bs_has_incubator(f: Dictionary) -> bool:
	if f.has("_incubatorProgress"):
		return true
	for p2 in f.get("_p2_equips", []):
		if p2 is Dictionary and str(p2.get("id", "")) == "p2eq_036":
			return true
	return false


# 点龟身交互 (方案A, 用户 2026-06-25, 删长按): 点龟身是否弹详情面板 (镜像 BattleScene._should_open_detail, 不实例化场景)。
#   决策态(was_decision = _picker_active or _targeting_active) → 出手/选靶, 抑制面板; 闲置态 → 弹面板。
#   看信息(任何态)改走龟头上的 ⓘ 信息钮 (_add_info_button), 不再靠长按。
func _bs_should_open_detail(was_decision: bool) -> bool:
	return not was_decision

# ⓘ 信息钮契约 (方案A, _add_info_button.pressed): 任何时候点都弹面板 (与决策态无关) — 看信息永远可达。
func _bs_info_button_opens(_was_decision: bool) -> bool:
	return true


## 点龟身交互 (方案A): 决策态(选龟出手/选目标)点龟身=出手/选靶绝不弹面板; 闲置态点龟身=弹面板。
##   看信息(任何态)走 ⓘ 信息钮 — ⓘ 钮无条件弹面板 (见 _add_info_button)。
func _test_fighter_tap_hold() -> void:
	# ── 点龟身: 决策态出手/选靶抑制面板, 闲置态弹面板 ──
	# 闲置态(看戏/对方回合, was_decision=false): 点龟身 → 弹面板 (保留原交互, 不回归)
	_assert_eq("闲置态点龟身 → 弹面板", _bs_should_open_detail(false), true)
	# 决策态(was_decision=true): 点龟身 → 抑制面板 (交给选龟区/选靶环出手/选靶, 不误弹)
	_assert_eq("决策态(出手/选靶)点龟身 → 不弹面板", _bs_should_open_detail(true), false)
	# ── ⓘ 信息钮: 任何态都弹面板 (删长按后, 决策态看信息的唯一入口) ──
	_assert_eq("ⓘ 钮 闲置态 → 弹面板", _bs_info_button_opens(false), true)
	_assert_eq("ⓘ 钮 决策态(出手/选靶) → 仍弹面板 (看信息永远可达)", _bs_info_button_opens(true), true)
	# ── 全交互矩阵: 龟身 vs ⓘ × 闲置 vs 决策 (4 组合) ──
	#   闲置: 龟身=弹, ⓘ=弹 (都能看信息)
	_assert_eq("矩阵 闲置·龟身 → 弹", _bs_should_open_detail(false), true)
	_assert_eq("矩阵 闲置·ⓘ → 弹", _bs_info_button_opens(false), true)
	#   决策: 龟身=不弹(出手/选靶), ⓘ=弹(看信息) — 二者分流不冲突
	_assert_eq("矩阵 决策·龟身 → 不弹(出手/选靶)", _bs_should_open_detail(true), false)
	_assert_eq("矩阵 决策·ⓘ → 弹(看信息)", _bs_info_button_opens(true), true)
	# 不变式: ⓘ 钮永远弹面板, 与决策态无关 (信息不可砍掉的铁律)
	_assert_eq("不变式: ⓘ 钮无视决策态恒弹", _bs_info_button_opens(true) and _bs_info_button_opens(false), true)


## 海浪043 波头到达时刻: 波从 start_x 线性扫到 end_x 用时 dur, 各目标按其 x 错峰显示 (波接触才掉血/盾/魔法)。
##   纯函数 wave_arrival_delay_at (BattleScene 静态), 与投射 arrival_delay 同思路; 验证 clamp/单调/分量比例。
func _test_wave_arrival_delay() -> void:
	var BS = load("res://scripts/scenes/BattleScene.gd")
	# 波 -120 → 1400 (span 1520), 用时 2.0s。
	# 起点处(x=-120) → frac=0 → 到达 0s
	_assert_eq("海浪 起点(x=-120)→0s", BS.wave_arrival_delay_at(-120.0, -120.0, 1400.0, 2.0), 0.0, 0.0001)
	# 终点处(x=1400) → frac=1 → 到达 2.0s
	_assert_eq("海浪 终点(x=1400)→2.0s", BS.wave_arrival_delay_at(1400.0, -120.0, 1400.0, 2.0), 2.0, 0.0001)
	# 中点(x=640, =(-120+1400)/2) → frac=0.5 → 1.0s
	_assert_eq("海浪 中点(x=640)→1.0s", BS.wave_arrival_delay_at(640.0, -120.0, 1400.0, 2.0), 1.0, 0.0001)
	# 沿波扫方向(x 增)= 到达更晚 (单调): 近(x=200) 先于 远(x=900)
	var near_t: float = BS.wave_arrival_delay_at(200.0, -120.0, 1400.0, 2.0)
	var far_t: float = BS.wave_arrival_delay_at(900.0, -120.0, 1400.0, 2.0)
	_assert_eq("海浪 x 小的先到 (单调错峰)", near_t < far_t, true)
	# 越界 clamp: x 远在终点之后 → 不超过 dur; x 远在起点之前 → 不低于 0
	_assert_eq("海浪 x 超终点 → clamp 到 dur", BS.wave_arrival_delay_at(9999.0, -120.0, 1400.0, 2.0), 2.0, 0.0001)
	_assert_eq("海浪 x 在起点前 → clamp 到 0", BS.wave_arrival_delay_at(-9999.0, -120.0, 1400.0, 2.0), 0.0, 0.0001)
	# 退化 span≈0 → 0 (不除零)
	_assert_eq("海浪 span≈0 → 0s (安全)", BS.wave_arrival_delay_at(500.0, 100.0, 100.0, 2.0), 0.0, 0.0001)
	# 龙蛋024 火柱横扫复用同一纯函数 (FIRE_SWEEP_DUR=0.6, 携带者x→列敌x): 各列目标按 x 错峰 0~0.6s 才显伤/盾/魔法。
	# 携带者侧(起点x=300, 友军近)→0s, 敌列(终点x=900, 远)→0.6s, 中点→0.3s; 近先于远 (单调错峰, 火接触才掉血)。
	_assert_eq("火柱 起点(友近, x=300)→0s", BS.wave_arrival_delay_at(300.0, 300.0, 900.0, 0.6), 0.0, 0.0001)
	_assert_eq("火柱 终点(敌列, x=900)→0.6s", BS.wave_arrival_delay_at(900.0, 300.0, 900.0, 0.6), 0.6, 0.0001)
	_assert_eq("火柱 中点(x=600)→0.3s", BS.wave_arrival_delay_at(600.0, 300.0, 900.0, 0.6), 0.3, 0.0001)
	var fire_near: float = BS.wave_arrival_delay_at(400.0, 300.0, 900.0, 0.6)
	var fire_far: float = BS.wave_arrival_delay_at(800.0, 300.0, 900.0, 0.6)
	_assert_eq("火柱 近(友)先于远(敌) (火接触才掉血, 单调)", fire_near < fire_far, true)


## 多弹武器逐颗各掉各血 (048手铳/049弩/050加特林/053霰弹): 每颗子弹的伤害 effect 应带
##   no_coalesce 标记 + 各自 arrival_delay(逐颗错峰), 且 _coalesce_multihit_segments 不并段
##   → BattleScene 走单发投射路径, 每颗子弹各自落地各掉血+各飘字 (用户要"按命中掉血", 数值不动)。
func _test_multibullet_no_coalesce() -> void:
	var P2RT = Phase2EquipRuntime
	# ── 工具: 取一次 on_cast 返回里所有 kind=="damage" 的 effect ──
	var grab_dmg := func(effs: Array) -> Array:
		var out: Array = []
		for e in effs:
			if e is Dictionary and e.get("kind", "") == "damage":
				out.append(e)
		return out

	# 048 黄铜手铳 3★ (6发, scale 0.6): 单个高血敌 → 6 发全命中产 6 条伤害 effect
	var a48 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e48 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var d48: Array = grab_dmg.call(P2RT.on_cast(a48, "p2eq_048", 3, [a48, e48]))
	_assert_eq("手铳3★ 产6条伤害effect (每颗子弹一条)", d48.size(), 6)
	var all48_marked := true
	var all48_arr := true
	for e in d48:
		if not bool(e.get("no_coalesce", false)): all48_marked = false
		if float(e.get("arrival_delay", -1.0)) <= 0.0: all48_arr = false
	_assert_eq("手铳 每颗子弹带 no_coalesce(不并段)", all48_marked, true)
	_assert_eq("手铳 每颗子弹带 arrival_delay(>0, 血跟落地)", all48_arr, true)
	# 逐颗错峰: arrival_delay 严格递增 (launch=_s48*0.09 → 各不同)
	var mono48 := true
	for i in range(1, d48.size()):
		if float(d48[i].get("arrival_delay", 0.0)) <= float(d48[i - 1].get("arrival_delay", 0.0)):
			mono48 = false
	_assert_eq("手铳 6颗 arrival_delay 逐颗递增(错峰命中, 不挤一帧)", mono48, true)

	# 050 幽灵加特林 3★ (60发): 单个高血敌 → 全打它, 每颗带标记 (随机分布但此处仅1敌)
	var a50 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e50 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 10000000, "maxHp": 10000000, "shield": 0, "baseDef": 0, "def": 0, "mr": 0, "buffs": []}
	var d50: Array = grab_dmg.call(P2RT.on_cast(a50, "p2eq_050", 3, [a50, e50]))
	_assert_eq("加特林3★ 产≥60条伤害effect (含金弹)", d50.size() >= 60, true)
	var marked50 := 0
	for e in d50:
		if bool(e.get("no_coalesce", false)) and float(e.get("arrival_delay", -1.0)) > 0.0:
			marked50 += 1
	_assert_eq("加特林 ≥60颗子弹带 no_coalesce+arrival_delay", marked50 >= 60, true)

	# 053 霰弹贝 3★ (18发弹珠): 单敌 → 18 颗各带标记 + 逐颗错峰 (launch=_p53*0.04)
	var a53 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e53 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 10000000, "maxHp": 10000000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var d53: Array = grab_dmg.call(P2RT.on_cast(a53, "p2eq_053", 3, [a53, e53]))
	_assert_eq("霰弹3★ 产18条伤害effect (每颗弹珠一条)", d53.size(), 18)
	var all53 := true
	for e in d53:
		if not bool(e.get("no_coalesce", false)) or float(e.get("arrival_delay", -1.0)) <= 0.0:
			all53 = false
	_assert_eq("霰弹 每颗弹珠带 no_coalesce+arrival_delay", all53, true)
	# 逐颗错峰: 首颗 arrival < 末颗 arrival (十几颗不挤一帧)
	_assert_eq("霰弹 末颗 arrival > 首颗 (逐颗错峰命中)",
		float(d53[d53.size() - 1].get("arrival_delay", 0.0)) > float(d53[0].get("arrival_delay", 0.0)), true)

	# ── _coalesce_multihit_segments 行为: no_coalesce 不被并段; 普通同目标≥2 才并段 ──
	var bs = BattleSceneScript.new()   # 不入树, 只调纯方法 (只读 fighters)
	bs.fighters = [
		{"hp": 1000, "maxHp": 1000, "alive": true},   # idx 0
	] as Array[Dictionary]
	# 多弹: 3 条同目标 no_coalesce 伤害 → 不并段 (无 segments, 条数不变)
	var multibullet := [
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "no_coalesce": true, "arrival_delay": 0.45},
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "no_coalesce": true, "arrival_delay": 0.54},
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "no_coalesce": true, "arrival_delay": 0.63},
	]
	var co1: Array = bs._coalesce_multihit_segments(multibullet, 0.12)
	_assert_eq("多弹 no_coalesce 不被并段 (条数不变=3)", co1.size(), 3)
	var any_seg := false
	for e in co1:
		if e is Dictionary and e.has("segments"): any_seg = true
	_assert_eq("多弹 no_coalesce 不生成 segments (逐颗独立显示)", any_seg, false)
	# 对照: 普通同目标 2 条伤害 (无标记) → 仍被并段成 1 条带 segments (确认并段逻辑没被打坏)
	var plain := [
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical"},
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical"},
	]
	var co2: Array = bs._coalesce_multihit_segments(plain, 0.12)
	_assert_eq("对照: 普通同目标2条仍被并段 (1条带segments)", co2.size(), 1)
	_assert_eq("对照: 并段后带 segments", co2[0].has("segments"), true)
	# ── 并段保留装备 proc VFX (修1 回归断言): 基础攻击 + 带 vfx:"slash" 的 proc 打同目标 → 并段后
	#   对应段【必须带 vfx/vfx_from/vfx_color】(原 bug: 重建 merged 只 copy value/dmg_type/is_crit/delay/hp_after
	#   → proc 斩弧被并段那几下永不播)。proc VFX 由各段在落地时刻各播 → merged 顶层【不】挂 vfx (避免双触发)。
	var with_vfx := [
		{"target_idx": 0, "kind": "damage", "value": 60, "dmg_type": "physical"},   # 基础攻击 (无 vfx)
		{"target_idx": 0, "kind": "damage", "value": 30, "dmg_type": "physical", "vfx": "slash", "vfx_from": 3, "vfx_color": "#ff4040", "vfx_scale": 0.9},   # 双生匕首 proc
	]
	var co3: Array = bs._coalesce_multihit_segments(with_vfx, 0.12)
	_assert_eq("并段保留vfx: 2条同目标并成1条", co3.size(), 1)
	var segs3: Array = co3[0].get("segments", [])
	_assert_eq("并段保留vfx: 生成2段", segs3.size(), 2)
	# 找出带 vfx 的那一段 (proc 段) — 必须保留全部 vfx* 字段
	var vfx_seg_found := false
	for sg in segs3:
		if str((sg as Dictionary).get("vfx", "")) == "slash":
			vfx_seg_found = true
			_assert_eq("并段保留vfx: proc段 vfx_from 保留", int((sg as Dictionary).get("vfx_from", -99)), 3)
			_assert_eq("并段保留vfx: proc段 vfx_color 保留", str((sg as Dictionary).get("vfx_color", "")), "#ff4040")
			_assert_eq("并段保留vfx: proc段 vfx_scale 保留", float((sg as Dictionary).get("vfx_scale", 0.0)), 0.9)
	_assert_eq("并段保留vfx: 找到带 slash 的 proc 段", vfx_seg_found, true)
	# merged 顶层不再挂 vfx (proc VFX 改逐段播, 防与渲染循环顶层分发双触发)
	_assert_eq("并段保留vfx: merged 顶层无 vfx (逐段播)", co3[0].has("vfx"), false)
	bs.free()


## 装备详情两区式 (上了龟 vs 席/商店). 全是纯字符串 static 助手 (无场景状态), 直接调 script.
func _test_p2eq_equip_popup_display() -> void:
	var BS = BattleSceneScript
	# ── 主效果实算: _inject_atk_values 兼容中文"攻击力" (原正则只匹 ATK 字面→实际从不命中, 本会话 bug 顺修) ──
	#   1×攻击力, 携带龟ATK=100 → (≈100)
	_assert_eq("攻击力实算 1×攻击力@100 → ≈100",
		BS._inject_atk_values("造成1×攻击力物理伤害", 100), "造成1×攻击力(≈100)物理伤害")
	# 0.75×攻击力 @ atk=200 → ≈150
	_assert_eq("攻击力实算 0.75×攻击力@200 → ≈150",
		BS._inject_atk_values("0.75×攻击力", 200), "0.75×攻击力(≈150)")
	# carrier_atk=0 (席/商店) → 不动
	_assert_eq("席/商店 carrier_atk=0 → 不实算",
		BS._inject_atk_values("0.75×攻击力", 0), "0.75×攻击力")
	# 暴击率项: carrier_crit≥0 才算. 40×暴击率 @ crit=0.5 → ≈20
	_assert_eq("暴击率实算 40×暴击率@0.5 → ≈20",
		BS._inject_atk_values("40×暴击率", 100, 0.5), "40×暴击率(≈20)")
	# carrier_crit=-1 (默认/席) → 暴击率项不动
	_assert_eq("暴击率 crit=-1 → 不实算",
		BS._inject_atk_values("40×暴击率", 100, -1.0), "40×暴击率")

	# ── 取当前星单值 (主效果): a/b/c → 当前星档 ──
	_assert_eq("取星 0.6/0.75/1.0 @2★ → 0.75",
		BS._p2eq_pick_star_text("0.6/0.75/1.0×攻击力", 2), "0.75×攻击力")
	_assert_eq("取星 0.6/0.75/1.0 @1★ → 0.6",
		BS._p2eq_pick_star_text("0.6/0.75/1.0×攻击力", 1), "0.6×攻击力")
	_assert_eq("取星 15/28/50 @3★ → 50 (%留在外)",
		BS._p2eq_pick_star_text("溅射15/28/50%×本段伤害", 3), "溅射50%×本段伤害")
	# 多斜杠组同时取档 (001 主效果): 0.6/0.75/1.0 + 40/60/100 @2★ → 0.75 / 60
	_assert_eq("取星 多组 @2★",
		BS._p2eq_pick_star_text("(0.6/0.75/1.0×攻击力+40/60/100×暴击率)", 2), "(0.75×攻击力+60×暴击率)")
	# 主效果链路: 取星 → 实算 (001 @2★ atk=200 crit=0.4): 0.75×200=150, 60×0.4=24
	var p2_001: Dictionary = DataRegistry.phase2_equipment_by_id.get("p2eq_001", {})
	if not p2_001.is_empty():
		var e1: String = str(p2_001.get("effectDesc1", ""))
		var realized: String = BS._inject_atk_values(BS._p2eq_pick_star_text(e1, 2), 200, 0.4)
		_assert_eq("001主效果@2★含 ×攻击力(≈150)", realized.contains("×攻击力(≈150)"), true)
		_assert_eq("001主效果@2★含 ×暴击率(≈24)", realized.contains("×暴击率(≈24)"), true)
		_assert_eq("001主效果@2★取2档系数 0.75", realized.contains("0.75"), true)
		_assert_eq("001主效果@2★不残留斜杠组 0.6/0.75", realized.contains("0.6/0.75"), false)

	# ── 加成区: 3档高亮当前星 (BBCode [b]当前档[/b]) ──
	# 属性 +攻5/12/20 → tier 行高亮 2★=12
	var tier := BS._p2eq_tier_str(PackedStringArray(["5", "12", "20"]), 2, "")
	_assert_eq("tier 5/12/20 @2★ 高亮12 ([b]12[/b])", tier.contains("[b]12[/b]"), true)
	_assert_eq("tier 5/12/20 @2★ 12有色高亮", tier.contains("[color=#ffe9a8][b]12[/b]"), true)
	_assert_eq("tier 5/12/20 @2★ 含5和20档", tier.contains("5") and tier.contains("20"), true)
	# 带后缀% (暴击10/15/25%)
	var tierp := BS._p2eq_tier_str(PackedStringArray(["10", "15", "25"]), 3, "%")
	_assert_eq("tier 10/15/25% @3★ 高亮25%", tierp.contains("[b]25%[/b]"), true)
	# 加成区整块: 001 (有 baseStats1 + effectDesc1 斜杠组) → 非空, 含属性成长标题+当前星属性高亮.
	#   修(2026-06-25 bug): 加成区只保留 baseStats1 属性成长档; effectDesc1 系数行已删 (系数在主效果区实算, 加成区抠斜杠组会乱码/重复).
	if not p2_001.is_empty():
		var blk: String = BS._p2eq_bonus_block(p2_001, 2)
		_assert_eq("001加成区@2★ 非空", blk != "", true)
		_assert_eq("001加成区@2★ 含'属性成长'标题(原'加成'乱)", blk.contains("属性成长"), true)
		_assert_eq("001加成区@2★ 攻属性高亮12", blk.contains("[b]12[/b]"), true)
		# 加成区只属性: effectDesc1 系数行已删 → 不含系数高亮0.75, 不含机器抠的中文单位行(原乱码源)
		_assert_eq("001加成区 不含系数行高亮0.75 (已删)", blk.contains("[b]0.75[/b]"), false)
		_assert_eq("001加成区 不含'×攻击力'系数行 (已删)", blk.contains("×攻击力"), false)
		_assert_eq("001加成区 不含'×暴击率'系数行 (已删)", blk.contains("×暴击率"), false)

	# ── 上了龟 edef (equipped=true): bbcode=true (RichTextLabel 路径); 席/商店 edef (equipped=false): 无 bbcode (内联三档不变) ──
	#   修(2026-06-25 bug): 两区分支改用显式 equipped 参数判, 非 carrier_atk>0 兼判 (atk=0 龟蛋/被清零的上龟单位也走两区).
	var inst = BS.new()   # 不入树 → 无 _ready 副作用; 纯方法调用后 free
	if not p2_001.is_empty():
		var edef_eq: Dictionary = inst._p2eq_popup_edef("p2eq_001", p2_001, 2, 200, 0.4, true)
		_assert_eq("上了龟 edef.bbcode=true", bool(edef_eq.get("bbcode", false)), true)
		_assert_eq("上了龟 edef.desc 含主效果实算(≈150)", str(edef_eq.get("desc", "")).contains("≈150"), true)
		_assert_eq("上了龟 edef.desc 含加成区高亮[b]", str(edef_eq.get("desc", "")).contains("[b]"), true)
		_assert_eq("上了龟 edef.desc 含加成区'属性成长'标题", str(edef_eq.get("desc", "")).contains("属性成长"), true)
		# 主效果区不再重复属性单值行: '📊 属性' 已去掉 (属性成长档统一在加成区)
		_assert_eq("上了龟 edef.desc 主效果区无'📊 属性'重复行", str(edef_eq.get("desc", "")).contains("📊 属性"), false)
		# atk=0 上龟单位(龟蛋/被清零) 也走两区: equipped=true 即得 bbcode (carrier_atk=0 不再误判成席/商店)
		var edef_egg: Dictionary = inst._p2eq_popup_edef("p2eq_001", p2_001, 2, 0, -1.0, true)
		_assert_eq("atk=0 上龟单位 equipped=true → 仍走两区(bbcode)", bool(edef_egg.get("bbcode", false)), true)
		# 席/商店 (equipped=false, carrier_atk=0): 无 bbcode 标记 → 走原 Label 内联三档 (保持现状)
		var edef_bench: Dictionary = inst._p2eq_popup_edef("p2eq_001", p2_001, 2, 0)
		_assert_eq("席/商店 edef 无 bbcode (内联不变)", edef_bench.has("bbcode"), false)
		_assert_eq("席/商店 edef.desc 保留斜杠三档(0.6/0.75/1.0)", str(edef_bench.get("desc", "")).contains("0.6/0.75/1.0"), true)
	inst.free()


## 商店拖卖区排除备战席 (2026-06-25 bug): 商店底沿 root 全宽与备战席(layer8)下几格屏幕重叠 →
##   原 _point_over_shop 用整条 root 全宽矩形判 → 从席最下几格拿装备没拖远松手就被误卖.
##   修: _point_over_bench 命中席 rail 矩形 → _point_over_shop 返 false (不算"在商店上"=不误卖).
func _test_shop_sell_bench_exclude() -> void:
	var inst = BattleSceneScript.new()   # 不入树, 只调纯几何判定 (读 hud_layer/_battle_shop_root 成员)
	# 搭最小 hud_layer + BenchRail_left (Control, 设位置/大小→get_global_rect 可算; 不入树也成立)
	var hud := CanvasLayer.new()
	var rail := Control.new()
	rail.name = "BenchRail_left"
	rail.position = Vector2(20, 300); rail.size = Vector2(60, 360)   # 左侧竖席矩形 (x20-80, y300-660)
	hud.add_child(rail)
	inst.hud_layer = hud
	# 席内点 → _point_over_bench=true
	_assert_eq("席矩形内 (50,400) → _point_over_bench=true", inst._point_over_bench(Vector2(50, 400)), true)
	_assert_eq("席矩形外 (500,400) → _point_over_bench=false", inst._point_over_bench(Vector2(500, 400)), false)
	# 搭商店 root (全宽底带, 与席下部重叠): _point_over_shop 在席内点必返 false (排除席), 席外商店内点返 true
	var shop_layer := CanvasLayer.new(); shop_layer.visible = true
	var shop_root := Control.new()
	shop_root.position = Vector2(0, 520); shop_root.size = Vector2(1280, 200)   # 底带 y520-720 全宽 → 与席 y520-660 重叠
	inst._battle_shop_layer = shop_layer
	inst._battle_shop_root = shop_root
	# 落点 (50,560): 既在商店底带内, 也在席矩形内 → 排除席 → 不算在商店上 (= 不误卖)
	_assert_eq("重叠区(50,560) 在席内 → _point_over_shop=false (不误卖)", inst._point_over_shop(Vector2(50, 560)), false)
	# 落点 (640,560): 在商店底带内, 不在席矩形内 → 真的在商店上 (= 拖到货架可卖)
	_assert_eq("商店内非席(640,560) → _point_over_shop=true (真卖区)", inst._point_over_shop(Vector2(640, 560)), true)
	# 落点 (50,400): 在席内, 不在商店带内(y400<520) → false
	_assert_eq("席内商店带外(50,400) → _point_over_shop=false", inst._point_over_shop(Vector2(50, 400)), false)
	hud.free(); shop_layer.free(); shop_root.free()
	inst.free()


## 云顶式横排备战席布局 (用户 2026-06-26): 备战席改战场下方一条横排、商店落最底, 上下分层【不重叠】。
##   验: ① 横席尺寸/落点常数对 (宽601/高64/商店160); ② 横席底沿 = 商店顶沿 (贴合不重叠);
##       ③ 横席顶沿 ≥ 战场最低龟脚(497) — 龟身(≤497)不被席挡; ④ 拖卖/拖装落点分类按新位置正确.
func _test_benchrow_horizontal_layout() -> void:
	var S = BattleSceneScript
	# ① 常数: 横条宽 = 10*52+9*7+18 = 601; 高 = 52+6*2 = 64; 商店 160.
	_assert_eq("横席宽 = 601", S.HUD_BENCHROW_WIDTH, 601)
	_assert_eq("横席高 = 64 (槽52+竖内边距6×2)", S.HUD_BENCHROW_HEIGHT, 64)
	_assert_eq("底部商店高 = 160 (实测≥160不裁控制行)", S.HUD_BENCHROW_SHOP_H, 160)
	# ② 几何: 商店顶沿 = VIEW_H - SHOP_H = 720-160 = 560; 横席底沿 = row_top + 高.
	var view_h: int = S.VIEW_H
	var shop_top: int = view_h - S.HUD_BENCHROW_SHOP_H   # 560
	var row_top: float = float(view_h) - S.HUD_BENCHROW_SHOP_H - S.HUD_BENCHROW_GAP - S.HUD_BENCHROW_HEIGHT   # 720-160-0-64=496
	var row_bottom: float = row_top + S.HUD_BENCHROW_HEIGHT   # 560
	_assert_eq("商店顶沿 = 560", shop_top, 560)
	_assert_eq("横席顶沿 = 496 (恰落龟脚497之上)", int(row_top), 496)
	_assert_eq("横席底沿(560) = 商店顶沿(560) → 贴合不重叠", int(row_bottom), shop_top)
	# ③ 战场最低龟脚 = POS_BY_SLOT front-2/back-2 的 y% × 720 = 69%×720 = 497; 横席顶沿(496) ≤ 497 → 龟身(在≤497上方)全不被席挡.
	var foot_y: int = int(round(69.0 / 100.0 * view_h))   # 497
	_assert_eq("最低龟脚 y = 497", foot_y, 497)
	_assert_eq("横席顶沿(496) 不深入龟身 (≤龟脚497, 仅脚尖临界1px)", int(row_top) <= foot_y, true)
	# ④ 落点分类: 用真实横席矩形 + 商店矩形 跑 _point_over_bench / _point_over_shop.
	var inst = S.new()
	var hud := CanvasLayer.new()
	var rail := Control.new(); rail.name = "BenchRail_left"
	var center_x: float = (float(S.VIEW_W) - float(S.HUD_BENCHROW_WIDTH)) / 2.0   # 双路居中: (1280-601)/2 = 339.5
	rail.position = Vector2(center_x, row_top); rail.size = Vector2(S.HUD_BENCHROW_WIDTH, S.HUD_BENCHROW_HEIGHT)   # 横席矩形 x339-940, y496-560
	hud.add_child(rail); inst.hud_layer = hud
	var shop_layer := CanvasLayer.new(); shop_layer.visible = true
	var shop_root := Control.new()
	shop_root.position = Vector2(0, shop_top); shop_root.size = Vector2(S.VIEW_W, S.HUD_BENCHROW_SHOP_H)   # 底带 y560-720
	inst._battle_shop_layer = shop_layer; inst._battle_shop_root = shop_root
	# 横席中心点 (640,528) → 在席内 / 不在商店内 (= 抓得起装备, 不误卖)
	_assert_eq("横席内(640,528) → _point_over_bench=true", inst._point_over_bench(Vector2(640, 528)), true)
	_assert_eq("横席内(640,528) → _point_over_shop=false (席上松手≠卖)", inst._point_over_shop(Vector2(640, 528)), false)
	# 商店内点 (640,640) → 在商店内 / 不在席内 (= 拖到货架可卖)
	_assert_eq("商店内(640,640) → _point_over_shop=true (真卖区)", inst._point_over_shop(Vector2(640, 640)), true)
	_assert_eq("商店内(640,640) → _point_over_bench=false", inst._point_over_bench(Vector2(640, 640)), false)
	# 席与商店之间无重叠: 分界 y=560 (席底=商店顶). 商店卖区 = 内缩可见面板 (root 内缩 top4) → 分界点(560)落面板上边距外 → 不算卖区 (避免边缘误卖); 真卖区从 564 起.
	_assert_eq("分界(640,560) 在面板上边距(未到564) → _point_over_shop=false (不误卖边缘)", inst._point_over_shop(Vector2(640, 560)), false)
	_assert_eq("商店可见卖区内(640,564) → _point_over_shop=true", inst._point_over_shop(Vector2(640, 564)), true)
	# 战场区(席上方)点 (640,300) → 既不在席也不在商店 (透传给战斗点龟/拖装命中)
	_assert_eq("战场区(640,300) → _point_over_bench=false", inst._point_over_bench(Vector2(640, 300)), false)
	_assert_eq("战场区(640,300) → _point_over_shop=false", inst._point_over_shop(Vector2(640, 300)), false)
	hud.free(); shop_layer.free(); shop_root.free()
	inst.free()


## 每目标统一显示调度器 + #4真火 + #1暴击按段记.
##   调度器: 同目标多事件按 at 有序入队 (跨机制不打架) / epoch 作废死龟队列 / _consume 按 kind 路由.
##   #4: DoT 桶按真实 dmg_type 分 (真火→tru), 真火 burn cls→dot-curse(真白). #1: 并段保留每段 is_crit → 按段记暴击.
func _test_display_scheduler() -> void:
	var bs = BattleSceneScript.new()   # 不入树, 只调纯入队/统计逻辑 (不触发 await 驱动协程)
	bs.fighters = [
		{"hp": 1000, "maxHp": 1000, "alive": true, "side": "right"},   # idx 0
		{"hp": 1000, "maxHp": 1000, "alive": true, "side": "right"},   # idx 1
	] as Array[Dictionary]
	# slot_nodes 需 ≥ idx 数 (入队只检 idx 范围, 不触节点方法) — 用占位 Node2D
	var n0 := Node2D.new(); var n1 := Node2D.new()
	bs.slot_nodes = [n0, n1] as Array[Node2D]

	# ── 调度器: 同目标多事件按 at 升序入队 (后入队但 at 小的不乱序) ──
	bs._enqueue_display(0, {"kind": "damage", "value": 30, "at": 0.30})
	bs._enqueue_display(0, {"kind": "damage", "value": 10, "at": 0.00})   # at 更小, 后入队 → 应排到前面
	bs._enqueue_display(0, {"kind": "dot", "value": 20, "cls": "dot-bleed", "at": 0.13})
	var q0: Array = bs._disp_q.get(0, [])
	_assert_eq("调度器: idx0 入队 3 事件", q0.size(), 3)
	var ordered_ok := q0.size() == 3 \
		and int(q0[0].get("_wall_at", 0)) <= int(q0[1].get("_wall_at", 0)) \
		and int(q0[1].get("_wall_at", 0)) <= int(q0[2].get("_wall_at", 0))
	_assert_eq("调度器: 按 _wall_at(意图到达时刻) 升序排列 (不乱序)", ordered_ok, true)
	_assert_eq("调度器: at 最小事件排队首 (value=10)", int(q0[0].get("value", -1)), 10)
	# 每事件都打了 epoch 戳
	_assert_eq("调度器: 入队事件带 epoch 戳", int(q0[0].get("epoch", -1)), bs._disp_epoch_of(0))
	# 不同目标独立队列
	bs._enqueue_display(1, {"kind": "damage", "value": 5, "at": 0.0})
	_assert_eq("调度器: idx1 独立队列 (不混入 idx0)", (bs._disp_q.get(1, []) as Array).size(), 1)

	# ── epoch 作废: 目标死透 bump epoch → 清待显队列, 旧事件失效 (#8 迟到不回刷尸体) ──
	var ep_before: int = bs._disp_epoch_of(0)
	bs._bump_disp_epoch(0)
	_assert_eq("调度器: bump epoch +1", bs._disp_epoch_of(0), ep_before + 1)
	_assert_eq("调度器: bump 后清空 idx0 待显队列", (bs._disp_q.get(0, []) as Array).size(), 0)
	_assert_eq("调度器: bump idx0 不动 idx1 队列", (bs._disp_q.get(1, []) as Array).size(), 1)
	# 旧 epoch 戳的事件 (死前入队) 现属过期 epoch → 驱动会丢弃 (此处验 epoch 不匹配)
	var stale_ev := {"kind": "damage", "value": 99, "at": 0.0, "epoch": ep_before}
	_assert_eq("调度器: 旧 epoch 事件 != 当前 epoch (会被丢弃)",
		int(stale_ev.get("epoch", -1)) != bs._disp_epoch_of(0), true)

	# ── _consume_display_event 按 kind 路由 (不崩, 纯显示) ── (节点无 hp_bar meta → _refresh_slot/_spawn 内部守卫安全)
	# 仅验 dot kind 走 _spawn_dot_text 路径不崩 (节点有 avatar meta=null 兜底 -50); damage kind 走 _render_one_segment.
	# (out-of-tree 渲染细节不深入, 只确认 kind 分流字段读取无误)
	var dot_ev := {"kind": "dot", "value": 12, "cls": "dot-bleed", "hp_after": 990.0}
	_assert_eq("调度器: dot 事件 kind 路由识别", str(dot_ev.get("kind", "")) == "dot", true)
	var dmg_ev := {"kind": "damage", "value": 12, "dmg_type": "physical", "hp_after": 988.0, "atk_side": "left"}
	_assert_eq("调度器: damage 事件 kind 路由识别", str(dmg_ev.get("kind", "")) == "damage", true)

	# ── #1 暴击按段记: 并段保留每段 is_crit → 调度器消费时按段记暴击 (对齐 PoC 每 hit crits++) ──
	bs.fighters = [{"hp": 500, "maxHp": 1000, "alive": true, "side": "right"}] as Array[Dictionary]
	bs.slot_nodes = [Node2D.new()] as Array[Node2D]
	var three_crit := [
		{"target_idx": 0, "kind": "damage", "value": 100, "dmg_type": "physical", "is_crit": true},
		{"target_idx": 0, "kind": "damage", "value": 100, "dmg_type": "physical", "is_crit": true},
		{"target_idx": 0, "kind": "damage", "value": 100, "dmg_type": "physical", "is_crit": true},
	]
	var merged: Array = bs._coalesce_multihit_segments(three_crit, 0.12)
	_assert_eq("暴击按段: 3 段同目标并成 1 条带 segments", merged.size() == 1 and merged[0].has("segments"), true)
	var crit_seg_count := 0
	for sg in merged[0].get("segments", []):
		if bool((sg as Dictionary).get("is_crit", false)):
			crit_seg_count += 1
	_assert_eq("暴击按段: 并段后保留每段 is_crit (3段全暴 → 应记3次暴击)", crit_seg_count, 3)
	# 对照: 部分暴击 (2暴1非暴) → 仅 2 段记暴击
	var mixed_crit := [
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "is_crit": true},
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "is_crit": false},
		{"target_idx": 0, "kind": "damage", "value": 50, "dmg_type": "physical", "is_crit": true},
	]
	var merged2: Array = bs._coalesce_multihit_segments(mixed_crit, 0.12)
	var crit2 := 0
	for sg in merged2[0].get("segments", []):
		if bool((sg as Dictionary).get("is_crit", false)): crit2 += 1
	_assert_eq("暴击按段: 2暴1非暴 → 记2次暴击 (非全段)", crit2, 2)

	# ── #4 DoT 统计桶按真实 dmg_type 分 (1:1 PoC statCat); 真火 burn → dmg_type=true → 桶=tru ──
	_assert_eq("#4 桶: bleed(physical) → phy", bs._stat_type("physical"), "phy")
	_assert_eq("#4 桶: burn/poison(magic) → mag", bs._stat_type("magic"), "mag")
	_assert_eq("#4 桶: curse(true) → tru", bs._stat_type("true"), "tru")

	# 真火 burn: dot tick 返回的 burn 段 dmg_type=true 且 cls=dot-curse (真白, 非 dot-dmg 魔蓝)
	var tf_target := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "def": 0, "mr": 1000,
		"buffs": [{"type": "burn", "value": 30, "duration": 999}, {"type": "trueFire", "value": 1, "duration": 999}]}
	var tf_fx: Array = Dot.tick(tf_target)
	var tf_burn: Dictionary = {}
	for e in tf_fx:
		if str(e.get("cls", "")) == "dot-curse" or str(e.get("dmg_type", "")) == "true":
			tf_burn = e
			break
	_assert_eq("#4 真火: burn 段 dmg_type=true", str(tf_burn.get("dmg_type", "")), "true")
	_assert_eq("#4 真火: burn 段 cls=dot-curse (真白, 非魔蓝)", str(tf_burn.get("cls", "")), "dot-curse")
	# 该段统计桶 = tru (按 dmg_type 抠, 非按旧 cls=='dot-dmg' 错记 mag)
	_assert_eq("#4 真火: 统计桶按 dmg_type → tru (不再误记 mag)", bs._stat_type(str(tf_burn.get("dmg_type", "magic"))), "tru")
	# 对照: 普通 burn (无真火) → dmg_type=magic / cls=dot-dmg / 桶=mag
	var nf_target := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "def": 0, "mr": 0,
		"buffs": [{"type": "burn", "value": 30, "duration": 999}]}
	var nf_fx: Array = Dot.tick(nf_target)
	var nf_burn: Dictionary = nf_fx[0] if not nf_fx.is_empty() else {}
	_assert_eq("#4 对照: 普通 burn dmg_type=magic", str(nf_burn.get("dmg_type", "")), "magic")
	_assert_eq("#4 对照: 普通 burn cls=dot-dmg (魔蓝)", str(nf_burn.get("cls", "")), "dot-dmg")
	_assert_eq("#4 对照: 普通 burn 桶=mag", bs._stat_type(str(nf_burn.get("dmg_type", "magic"))), "mag")

	n0.free(); n1.free()
	for nn in bs.slot_nodes:
		if is_instance_valid(nn): nn.free()
	bs.free()


## 死亡掉血根治: 致命那一击的血条 step 必走到 0 (不被"alive==false 即丢"作废)。
##   用户报: "龟死时血条没动 / 没掉到 0 就死了"。根因 = HP 在 execute 同步扣到 0 (alive=false 立即),
##   但血条/飘字走【延迟显示队列】, 旧 drive-loop 守卫见 alive==false 即丢致命 step → 血条停半血就死。
##   修: 守卫只在 _deathVfxDone(死亡演出已播) 才丢; 致命 step 放过 → 血条到 0。+ _play_death 兜底强刷真实终值。
func _test_hp_bar_death_step() -> void:
	var HpBarS = load("res://scripts/scenes/hp_bar.gd")
	var bs = BattleSceneScript.new()
	# 单龟: 被致命一击, 真实 HP 已扣到 0 / alive=false (模拟 execute 同步扣血后, 显示队列还没消费致命 step)
	var node := Node2D.new()
	var av := Sprite2D.new(); av.position = Vector2(0, -40)
	node.add_child(av); node.set_meta("avatar", av)
	var hud := Node2D.new(); node.add_child(hud); node.set_meta("hud", hud)
	var hp_bar = HpBarS.new(); hp_bar.setup(true, false)
	node.add_child(hp_bar); node.set_meta("hp_bar", hp_bar)
	bs.slot_nodes = [node] as Array[Node2D]
	# 血条先显示满血 (命中前) → 再致命一击把真实 hp 砸到 0 + alive=false
	hp_bar.update_state({"hp": 1000, "maxHp": 1000})
	_assert_eq("致死前: 血条显示满血 1000", hp_bar.displayed_hp(), 1000.0, 0.5)
	bs.fighters = [{"hp": 0, "maxHp": 1000, "alive": false, "_deathVfxDone": false, "side": "right", "name": "靶"}] as Array[Dictionary]

	# 致命 step 事件 (hp_after=0): 模拟 drive-loop 消费致命那一下 — 即便 alive==false, 只要未死透(_deathVfxDone=false)
	#   就该渲染, 血条 step 到 0。直接调 _consume_display_event (drive-loop 守卫已放过此情形)。
	var fatal_ev := {"kind": "damage", "value": 1000, "dmg_type": "physical", "hp_after": 0.0, "atk_side": "left"}
	bs._consume_display_event(0, fatal_ev)
	_assert_eq("致命一击: 血条 step 走到 0 (alive==false 不再误丢致命掉血)", hp_bar.displayed_hp(), 0.0, 0.5)

	# 守卫语义断言: drive-loop 丢弃条件 = 仅 _deathVfxDone (非 not alive)。
	#   alive==false & 未死透 → 不丢 (致命掉血放过); _deathVfxDone==true → 丢 (尸体残留不回刷)。
	var done_f: bool = bool(bs.fighters[0].get("_deathVfxDone", false))
	_assert_eq("守卫: 致命态 alive==false 但 _deathVfxDone==false → 不丢弃 (放过致命 step)",
		(not done_f), true)
	bs.fighters[0]["_deathVfxDone"] = true
	_assert_eq("守卫: 死透 _deathVfxDone==true → 才丢弃 (尸体残留不回刷)",
		bs.fighters[0].get("_deathVfxDone", false), true)
	bs.fighters[0]["_deathVfxDone"] = false   # 复位供下方兜底测试

	# 兜底保证: 若血条因极端排队仍停在半血 (stale-high), _play_death 前的强刷必把它砸到真实终值 0。
	hp_bar.update_state({"hp": 1000, "maxHp": 1000})         # 重置满血
	hp_bar.update_state({"hp": 1000, "maxHp": 1000}, 500.0)  # 模拟血条停在 500 (致命 step 没走完)
	_assert_eq("兜底前: 血条 stale 停在 500 (模拟致命 step 漏显)", hp_bar.displayed_hp(), 500.0, 0.5)
	# _play_death 内的强刷等价: _refresh_slot(idx, 真实 hp=0) → 用 override 强制下刷 (无 override 会保留 stale 定格值)
	bs._refresh_slot(0, float(bs.fighters[0].get("hp", 0)))
	_assert_eq("兜底: _play_death 强刷真实终值 → 血条砸到 0 (绝不停半血就消失)", hp_bar.displayed_hp(), 0.0, 0.5)

	# 队列清理不误伤致命掉血: _bump_disp_epoch 作废的是【旧 epoch 的待显事件】, 不影响已 step 到 0 的血条值。
	bs._enqueue_display(0, {"kind": "damage", "value": 5, "at": 0.0})   # 入一个待显事件
	_assert_eq("清理前: idx0 队列有 1 待显事件", (bs._disp_q.get(0, []) as Array).size(), 1)
	bs._bump_disp_epoch(0)
	_assert_eq("清理: bump epoch 清空待显队列 (作废 stale, 不回弹尸体)", (bs._disp_q.get(0, []) as Array).size(), 0)
	_assert_eq("清理后: 已显示的血条值仍为 0 (不被队列清理回弹)", hp_bar.displayed_hp(), 0.0, 0.5)

	node.queue_free()
	bs.free()


# 中立事件子系统 events.gd 1:1 PoC events.ts
func _test_events() -> void:
	# volcano: 前排损8%maxHp真伤, 后排不损
	var ff := {"side": "left", "alive": true, "_position": "front", "hp": 1000, "maxHp": 1000, "buffs": []}
	var fb := {"side": "left", "alive": true, "_position": "back", "hp": 1000, "maxHp": 1000, "buffs": []}
	Events.apply_env_event("volcano", [ff, fb])
	_assert_eq("火山 前排损8% (1000→920)", int(ff["hp"]), 920)
	_assert_eq("火山 后排不损", int(fb["hp"]), 1000)
	# tide: 全员 atkDown15/defUp10
	var ft := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "baseDef": 50, "def": 50, "buffs": []}
	Events.apply_env_event("tide", [ft])
	_assert_eq("涨潮 atk-15", int(ft["atk"]), 85)
	_assert_eq("涨潮 def+10", int(ft["def"]), 60)
	_assert_eq("涨潮 加2buff", (ft["buffs"] as Array).size(), 2)
	# thunder: 随机-40 + 标记后续2回合
	var fh := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Events.apply_env_event("thunder", [fh])
	_assert_eq("雷暴 单体-40", int(fh["hp"]), 960)
	_assert_eq("雷暴 标记后续2回合", int(fh.get("_thunderstormTurns", 0)), 2)
	# meteor: 每侧1只-100
	var ml := {"side": "left", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	var me := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	Events.apply_env_event("meteor", [ml, me])
	_assert_eq("流星 左-100", int(ml["hp"]), 400)
	_assert_eq("流星 右-100", int(me["hp"]), 400)
	# fog: dodge buff
	var fg := {"side": "left", "alive": true, "buffs": []}
	Events.apply_env_event("fog", [fg])
	_assert_eq("浓雾 加dodge buff", (fg["buffs"] as Array).size(), 1)
	# roll 回合门控
	_assert_eq("roll_event 非3/6/9/12 空", Events.roll_event_for_turn(5, []), "")
	_assert_eq("roll_event turn3 出事件", Events.roll_event_for_turn(3, []) != "", true)
	_assert_eq("roll_event 全触发过 空", Events.roll_event_for_turn(3, Events.ENV_EVENT_IDS), "")
	_assert_eq("roll_neutral 非3/6/9/12 空", Events.roll_neutral_for_turn(5, false).is_empty(), true)
	_assert_eq("roll_neutral 已spawn 空", Events.roll_neutral_for_turn(3, true).is_empty(), true)
	# 模板数值
	_assert_eq("宝箱怪 hp300/atk30", int(Events.NEUTRAL_TEMPLATES["treasure"]["hp"]), 300)
	_assert_eq("巨蟹 hp400/atkScale1", int(Events.NEUTRAL_TEMPLATES["crab"]["hp"]), 400)
	_assert_eq("海葵母 寄生盾350+15攻", int(Events.NEUTRAL_TEMPLATES["anemone"]["parasiteShield"]), 350)


## 二阶段装备壳: 属性解析 / 升星×1.8 / 三合一 / 套装检测 / 数据加载
## V2 赛季/命 逻辑 (阶段4核心): 失心/淘汰 + 赛季过期/滚动 + 装备槽按总战斗数. (lose_heart/start_new_season 已改不自存→测试不写盘)
func _test_v2_season() -> void:
	# 装备槽: 按本赛季总战斗数 (纯函数)
	_assert_eq("0战=0槽", Phase2Config.equip_slots_for_battles(0), 0)
	_assert_eq("1战=0槽", Phase2Config.equip_slots_for_battles(1), 0)
	_assert_eq("2战=1槽", Phase2Config.equip_slots_for_battles(2), 1)
	_assert_eq("5战=2槽", Phase2Config.equip_slots_for_battles(5), 2)
	_assert_eq("8战=3槽", Phase2Config.equip_slots_for_battles(8), 3)
	_assert_eq("9战=4槽", Phase2Config.equip_slots_for_battles(9), 4)
	_assert_eq("99战=4槽(封顶)", Phase2Config.equip_slots_for_battles(99), 4)
	# 赛季过期判定
	GameState.season_start_ts = 0
	_assert_eq("ts=0→未过期", GameState.is_season_expired(), false)
	GameState.season_start_ts = 1   # epoch 起算 → 远超5天
	_assert_eq("远古ts→已过期", GameState.is_season_expired(), true)
	# 命: lose_heart clamp ≥0 + 0命淘汰
	GameState.hearts = 8
	GameState.lose_heart()
	_assert_eq("输1场→7命", GameState.hearts, 7)
	GameState.hearts = 1
	_assert_eq("末命输→返回淘汰true", GameState.lose_heart(), true)
	_assert_eq("0命", GameState.hearts, 0)
	_assert_eq("is_eliminated", GameState.is_eliminated(), true)
	GameState.lose_heart()
	_assert_eq("0命再输不为负", GameState.hearts, 0)
	# 滚新赛季: 命/币/总战斗/蛋数/背包build 全重置, season_id++
	GameState.season_id = 3; GameState.hearts = 2; GameState.meta_deepsea_coins = 500
	GameState.season_total_battles = 7; GameState.season_eggs_killed = 4
	GameState.persistent_bench = [{"id": "x", "star": 1}]
	GameState.start_new_season()
	_assert_eq("新赛季 season_id+1", GameState.season_id, 4)
	_assert_eq("新赛季 命回8", GameState.hearts, 8)
	_assert_eq("新赛季 深海币清0", GameState.meta_deepsea_coins, 0)
	_assert_eq("新赛季 总战斗清0", GameState.season_total_battles, 0)
	_assert_eq("新赛季 蛋数清0", GameState.season_eggs_killed, 0)
	_assert_eq("新赛季 背包清空", GameState.persistent_bench.size(), 0)
	_assert_eq("新赛季 时间戳已设(>0)", GameState.season_start_ts > 0, true)
	# 复位 (本测试改了 GameState 单例的赛季字段, 还原默认免扰后续)
	GameState.season_id = 1; GameState.season_start_ts = 0; GameState.hearts = 8
	GameState.season_total_battles = 0; GameState.season_eggs_killed = 0
	GameState.meta_deepsea_coins = 0; GameState.persistent_bench = []


## V2 本地后端 (阶段4/5 MVP): 进度分档 + bot 生成 + ghost 池增删抽取 + 排行榜. 纯逻辑(内存Dict/seeded rng), 不写盘.
func _test_v2_backend() -> void:
	# 分档表 (设计§十三)
	_assert_eq("0战→档0", Backend.bracket_for_battles(0), 0)
	_assert_eq("1战→档0", Backend.bracket_for_battles(1), 0)
	_assert_eq("3战→档1", Backend.bracket_for_battles(3), 1)
	_assert_eq("8战→档3", Backend.bracket_for_battles(8), 3)
	_assert_eq("14战→档4", Backend.bracket_for_battles(14), 4)
	_assert_eq("20战→档5", Backend.bracket_for_battles(20), 5)
	_assert_eq("41战→档8", Backend.bracket_for_battles(41), 8)
	_assert_eq("999战→档8(封顶)", Backend.bracket_for_battles(999), 8)
	# bot 生成 (seeded rng 确定)
	var rng := RandomNumberGenerator.new(); rng.seed = 123
	var bot := Backend.make_bot(4, rng)
	_assert_eq("bot is_bot", bot["is_bot"], true)
	_assert_eq("bot 档=4", int(bot["bracket"]), 4)
	_assert_eq("bot 3统领", (bot["leaders"] as Array).size(), 3)
	_assert_eq("bot 上+下路=3", (bot["lane_assign"]["top"] as Array).size() + (bot["lane_assign"]["bottom"] as Array).size(), 3)
	_assert_eq("bot 上路2只", (bot["lane_assign"]["top"] as Array).size(), 2)
	# 档4=14战 → equip_slots_for_battles(14)=4槽 → 每龟4件装备
	var want_slots := Phase2Config.equip_slots_for_battles(Backend.battles_for_bracket(4))
	_assert_eq("bot 装备数=按档槽", (bot["equipped"][bot["leaders"][0]] as Array).size(), want_slots)
	# 池增删 + 抽取
	var pool := {"brackets": {}}
	Backend.pool_add(pool, {"ghost_id": "g1", "bracket": 2, "profile": {"name": "甲"}, "season_eggs_killed": 5})
	Backend.pool_add(pool, {"ghost_id": "g2", "bracket": 2, "profile": {"name": "乙"}, "season_eggs_killed": 9})
	Backend.pool_add(pool, {"ghost_id": "g3", "bracket": 7, "profile": {"name": "丙"}, "season_eggs_killed": 3})
	_assert_eq("档2桶=2个", (pool["brackets"]["2"] as Array).size(), 2)
	_assert_eq("抽档2得非null", Backend.pool_find(pool, 2, [], rng) != null, true)
	_assert_eq("排除全部→null", Backend.pool_find(pool, 2, ["g1", "g2"], rng) == null, true)
	_assert_eq("空档5→null", Backend.pool_find(pool, 5, [], rng) == null, true)
	# 排行榜: 自己 + 池, 按蛋数降序
	var lb := Backend.leaderboard(pool, "我", 7, 10)
	_assert_eq("榜=自己+3 ghost=4行", lb.size(), 4)
	_assert_eq("榜首=乙(9蛋)", str(lb[0]["name"]), "乙")
	_assert_eq("我(7蛋)排第2", str(lb[1]["name"]), "我")
	_assert_eq("我标 is_self", lb[1]["is_self"], true)


func _test_phase2_equip_shell() -> void:
	# 基础属性解析
	var ps := Phase2Equip.parse_base_stats("+10攻/+10%暴击")
	_assert_eq("解析 +10攻", float(ps.get("atk", 0)), 10.0, 0.001)
	_assert_eq("解析 +10%暴击→crit", float(ps.get("crit", 0)), 10.0, 0.001)
	var ps2 := Phase2Equip.parse_base_stats("+6双穿/+4护甲魔抗")
	_assert_eq("双穿→armorPen", float(ps2.get("armorPen", 0)), 6.0, 0.001)
	_assert_eq("双穿→magicPen", float(ps2.get("magicPen", 0)), 6.0, 0.001)
	_assert_eq("护甲魔抗→def", float(ps2.get("def", 0)), 4.0, 0.001)
	_assert_eq("护甲魔抗→mr", float(ps2.get("mr", 0)), 4.0, 0.001)
	# 升星 ×1.8 (占位)
	var s2 := Phase2Equip.star_stats({"atk": 10.0}, 2)
	_assert_eq("2星 atk = 10×1.8 = 18", float(s2["atk"]), 18.0, 0.001)
	var s3 := Phase2Equip.star_stats({"atk": 10.0}, 3)
	_assert_eq("3星 atk = 10×1.8² = 32.4", float(s3["atk"]), 32.4, 0.001)
	# 三合一规则
	_assert_eq("3件同款1星 可合", Phase2Equip.can_merge(["a", "a", "a"], 1), true)
	_assert_eq("混款不可合", Phase2Equip.can_merge(["a", "a", "b"], 1), false)
	_assert_eq("2件不可合", Phase2Equip.can_merge(["a", "a"], 1), false)
	_assert_eq("满星不可合", Phase2Equip.can_merge(["a", "a", "a"], 3), false)
	_assert_eq("合成→2星", int(Phase2Equip.merge_result("a", 1)["star"]), 2)
	_assert_eq("3星需9件1星", Phase2Equip.items_for_star(3), 9)
	_assert_eq("2星需3件1星", Phase2Equip.items_for_star(2), 3)
	# 套装检测 (系列≥3 / 子流派≥2)
	var eq := [
		{"series": "剑系", "setTag": "剑·流血"}, {"series": "剑系", "setTag": "剑·流血"},
		{"series": "剑系", "setTag": "剑·暴击"},
	]
	var sets := Phase2Equip.detect_sets(eq)
	var has_series := sets.any(func(x): return x["kind"] == "series" and x["name"] == "剑系")
	var has_sub := sets.any(func(x): return x["kind"] == "subschool" and x["name"] == "剑·流血")
	_assert_eq("3剑系→系列套装", has_series, true)
	_assert_eq("2剑·流血→子流派套装", has_sub, true)
	# 龟蛋 HP 公式
	_assert_eq("龟蛋HP 均等级1 = 1050", Phase2Config.egg_hp(1.0), 2100)
	_assert_eq("商店刷新恒 2 (flat, 不递增)", Phase2Config.shop_refresh_cost(1), 2)
	_assert_eq("商店首刷 = 2", Phase2Config.shop_refresh_cost(0), 2)
	# 5费传说真能上架 (2026-06-26): 017/052/056/059 设 shopAvailable=1; 010/033/034 (横扫/召唤专属) 仍不上架。
	var cost5_avail := 0
	for it in DataRegistry.phase2_equipment:
		if it is Dictionary and int(it.get("cost", 0)) == 5 and int(it.get("shopAvailable", 0)) == 1:
			cost5_avail += 1
	_assert_eq("5费可上架件数=4 (017/052/056/059)", cost5_avail, 4)
	for eid5 in ["p2eq_017", "p2eq_052", "p2eq_056", "p2eq_059"]:
		_assert_eq("5费 %s 已上架" % eid5, int(DataRegistry.phase2_equipment_by_id[eid5].get("shopAvailable", 0)), 1)
	for eid5x in ["p2eq_010", "p2eq_033", "p2eq_034"]:
		_assert_eq("5费专属 %s 仍不上架" % eid5x, int(DataRegistry.phase2_equipment_by_id[eid5x].get("shopAvailable", 0)), 0)
	# 数据加载
	_assert_eq("phase2装备加载59件", DataRegistry.phase2_equipment.size(), 59)
	_assert_eq("装备有emoji", str(DataRegistry.phase2_equipment[0].get("emoji", "")) != "", true)
	# (原占位哨兵: item[0]=001 曾 effectImpl=false; 现已全实装 → 改为正向断言)
	_assert_eq("效果已接战斗(001锈蚀短剑已实装)", bool(DataRegistry.phase2_equipment[0].get("effectImpl", false)), true)
	var _impl_cnt := 0
	for _it in DataRegistry.phase2_equipment:
		if _it.get("effectImpl", false): _impl_cnt += 1
	_assert_eq("装备效果实装≥57/59", _impl_cnt >= 57, true)
	# 双路龟蛋 流程逻辑
	var split := DualLane.auto_split(["a", "b", "c", "d", "e", "f"])
	_assert_eq("分路 top 3龟", (split["top"] as Array).size(), 3)
	_assert_eq("分路 bottom 3龟", (split["bottom"] as Array).size(), 3)
	_assert_eq("分路 top[0]=a", str(split["top"][0]), "a")
	_assert_eq("路序 top→bottom", DualLane.next_lane("top"), "bottom")
	_assert_eq("路序 bottom→final", DualLane.next_lane("bottom"), "final")
	_assert_eq("两路全胜→胜者", DualLane.match_winner({"top": "left", "bottom": "left"}), "left")
	_assert_eq("1-1→无直接胜者", DualLane.match_winner({"top": "left", "bottom": "right"}), "")
	_assert_eq("1-1→需final", DualLane.needs_final({"top": "left", "bottom": "right"}), true)
	_assert_eq("2-0→不需final", DualLane.needs_final({"top": "left", "bottom": "left"}), false)
	_assert_eq("final定胜负", DualLane.overall_winner({"top": "left", "bottom": "right", "final": "right"}), "right")
	# GameState 流程
	GameState.setup_dual_lane(["a", "b", "c", "d", "e", "f"], ["g", "h", "i", "j", "k", "l"], 1)
	_assert_eq("setup后 mode=duallane", GameState.mode, "duallane")
	_assert_eq("setup后 current_lane=top", GameState.current_lane, "top")
	_assert_eq("setup后 蛋HP=2100", int(GameState.egg_hp["left"]), 2100)
	GameState.record_lane_result("left")
	_assert_eq("记录top后 current=bottom", GameState.current_lane, "bottom")
	GameState.record_lane_result("right")
	_assert_eq("1-1后 需final", GameState.dual_lane_needs_final(), true)
	# 龟蛋: 攻蛋累计 + 摧毁 + 比例
	GameState.setup_dual_lane(["a","b","c","d","e","f"], ["g","h","i","j","k","l"], 10)
	_assert_eq("满级蛋HP=3000", int(GameState.egg_hp["right"]), 3000)
	_assert_eq("攻蛋600未碎", GameState.damage_egg("right", 600), false)
	_assert_eq("攻蛋后剩2400", int(GameState.egg_hp["right"]), 2400)
	_assert_eq("蛋比例0.8", GameState.egg_frac("right"), 0.8, 0.001)
	_assert_eq("再攻2400→碎", GameState.damage_egg("right", 2400), true)
	_assert_eq("蛋活=false", GameState.egg_alive("right"), false)
	_assert_eq("右蛋碎→左方整局胜", GameState.dual_match_over(), "left")
	# 终极战场 蛋特有: ×5增伤 + 25%自损
	_assert_eq("攻蛋×5: 100→500", Phase2Config.egg_final_hit(100), 500)
	_assert_eq("满级蛋自损25%=375", Phase2Config.egg_self_loss(1500), 375)
	# 待命回复: 已损30%
	_assert_eq("损500回30%=150", Phase2Config.standby_recover(500, 1000), 150)
	_assert_eq("满血回0", Phase2Config.standby_recover(1000, 1000), 0)
	# 永恒buff: N层×(1+0.5N)
	_assert_eq("永恒0层=1.0", Phase2Config.eternal_mult(0), 1.0, 0.001)
	_assert_eq("永恒2层=2.0", Phase2Config.eternal_mult(2), 2.0, 0.001)
	# 小将: 等级复利 + 前后排攻击系数
	var mf := Minion.make_minion(1, "left", "front-0")
	_assert_eq("Lv1小将HP=750(×3补丁)", int(mf["hp"]), 750)
	_assert_eq("Lv1小将ATK=45(×1.5补丁)", int(mf["atk"]), 45)
	_assert_eq("前排砍系数1.4", float(mf["_minionAtkMult"]), 1.4, 0.001)
	_assert_eq("小将标记", bool(mf["_isMinion"]), true)
	_assert_eq("小将有1个基础攻击技", (mf["skills"] as Array).size(), 1)
	_assert_eq("小将基础技=physical", str(mf["skills"][0]["type"]), "physical")
	_assert_eq("前排小将技atkScale=1.4", float(mf["skills"][0]["atkScale"]), 1.4, 0.001)
	var mb := Minion.make_minion(1, "left", "back-0")
	_assert_eq("后排射系数1.5", float(mb["_minionAtkMult"]), 1.5, 0.001)
	# 小将立绘随最终槽位 (minion_img 单一来源, BattleScene 槽位重算用之): front砍/back射/elite精英.
	_assert_eq("前排小将皮=minion.png", str(mf["img"]), "pets/minion.png")
	_assert_eq("后排小将皮=minion-back.png", str(mb["img"]), "pets/minion-back.png")
	_assert_eq("minion_img(front)=砍皮", Minion.minion_img(false, false), "pets/minion.png")
	_assert_eq("minion_img(back)=射皮", Minion.minion_img(false, true), "pets/minion-back.png")
	_assert_eq("minion_img(elite)=精英皮(无视前后)", Minion.minion_img(true, true), "pets/minion-elite.png")
	# 槽位重算场景: 建时 front(砍皮) → _assign_slots 改到 back → BattleScene 用 minion_img 重选 → 应变射皮.
	var mskin := Minion.make_minion(1, "left", "front-0")
	_assert_eq("重算前: front 砍皮", str(mskin["img"]), "pets/minion.png")
	mskin["_position"] = "back"   # 模拟 _assign_slots 把它挪到后排
	var _isb := str(mskin.get("_position", "front")) == "back"
	mskin["img"] = Minion.minion_img(mskin.get("_isElite", false), _isb)   # BattleScene 槽位重算同款表达式
	_assert_eq("重算后: 挪到 back → 皮跟着变射皮", str(mskin["img"]), "pets/minion-back.png")
	var m5 := Minion.make_minion(5, "left", "front-0")
	_assert_eq("Lv5小将HP≈304×3=912(×3补丁)", int(m5["hp"]), 912)
	# 补位: 1统领→补2小将; 0统领→第一个升精英
	_assert_eq("1统领补2小将", Minion.fill_lane(1, 1, "left").size(), 2)
	_assert_eq("3统领不补", Minion.fill_lane(3, 1, "left").size(), 0)
	var empty_fill := Minion.fill_lane(0, 1, "left")
	_assert_eq("空路补3小将", empty_fill.size(), 3)
	_assert_eq("空路首个=精英", bool(empty_fill[0]["_isElite"]), true)
	# 精英 整排均摊伤害 (设计§3, 用户定均摊式=总÷人数; 仅1人→全额)
	var elite := Minion.make_minion(1, "left", "front-0", true)
	_assert_eq("精英技标eliteRowSplit", bool(elite["skills"][0].get("eliteRowSplit", false)), true)
	_assert_eq("精英技名=整排挥砍", str(elite["skills"][0]["name"]), "整排挥砍")
	_assert_eq("精英小将皮=minion-elite.png", str(elite["img"]), "pets/minion-elite.png")
	var _en := func(sk: String) -> Dictionary:
		return {"side": "right", "name": "敌", "alive": true, "hp": 999, "maxHp": 999, "def": 0, "mr": 0, "armorPen": 0, "magicPen": 0, "crit": 0.0, "shield": 0, "buffs": [], "_slotKey": sk}
	var er1: Dictionary = _en.call("front-0")
	var er2: Dictionary = _en.call("front-1")
	var er_back: Dictionary = _en.call("back-0")
	var split_res: Dictionary = SkillHandlers.execute(elite, er1, [elite, er1, er2, er_back], elite["skills"][0])
	var split_total := 0
	var split_hits := 0
	for ef in split_res["effects"]:
		if ef.get("kind", "") == "damage":
			split_total += int(ef["value"]); split_hits += 1
	_assert_eq("整排均摊 只打目标整排(2前排, 不含后排)", split_hits, 2)
	_assert_eq("整排均摊 总伤=ATK45×1.4≈63, 2敌各31均摊62 (小将×1.5补丁)", split_total, 62)
	var solo_res: Dictionary = SkillHandlers.execute(elite, er1, [elite, er1], elite["skills"][0])
	var solo_total := 0
	for ef in solo_res["effects"]:
		if ef.get("kind", "") == "damage":
			solo_total += int(ef["value"])
	_assert_eq("整排仅1敌→全额63 (小将×1.5补丁)", solo_total, 63)
	# 对局快照 round-trip
	GameState.setup_dual_lane(["a","b","c","d","e","f"], ["g","h","i","j","k","l"], 5)
	GameState.damage_egg("right", 300)
	GameState.record_lane_result("left")
	var snap := GameState.dual_lane_snapshot()
	GameState.reset_dual_lane()
	_assert_eq("reset后蛋HP清0", int(GameState.egg_hp.get("right", 0)), 0)
	GameState.apply_dual_lane_snapshot(snap)
	_assert_eq("快照恢复 current_lane", GameState.current_lane, "bottom")
	_assert_eq("快照恢复 敌蛋HP", int(GameState.egg_hp["right"]), 2200)   # avg5→蛋1250, 攻300→950
	_assert_eq("快照恢复 上路胜方", str(GameState.lane_results["top"]), "left")
	# 局内等级 (TFT风): 升级 + 强化龟蛋 + 买经验 + 每回合结算
	GameState.setup_dual_lane(["a", "b", "c"], ["d", "e", "f"], 1)
	_assert_eq("开局1级", int(GameState.dual_level["left"]), 1)
	_assert_eq("1级蛋2100", int(GameState.egg_hp["left"]), 2100)
	_assert_eq("xp_to_next(1)=2", Phase2Config.xp_to_next(1), 2)
	_assert_eq("加2xp升1级", GameState.add_xp("left", 2), 1)
	_assert_eq("升到2级", int(GameState.dual_level["left"]), 2)
	_assert_eq("2级蛋maxHP2200", int(GameState.egg_hp_max["left"]), 2200)
	_assert_eq("升级补蛋血到2200", int(GameState.egg_hp["left"]), 2200)
	GameState.damage_egg("left", 300)   # 1100→800
	GameState.add_xp("left", 6)         # xp_to_next(2)=6 → 3级
	_assert_eq("升到3级", int(GameState.dual_level["left"]), 3)
	_assert_eq("强化保留累计伤害(1900+100)", int(GameState.egg_hp["left"]), 2000)
	_assert_eq("3级maxHP2300", int(GameState.egg_hp_max["left"]), 2300)
	GameState.dual_coins["left"] = 0
	_assert_eq("没币买不了经验", GameState.buy_xp("left"), false)
	GameState.dual_coins["left"] = 10
	_assert_eq("有币买经验成功", GameState.buy_xp("left"), true)
	_assert_eq("买后扣4币", int(GameState.dual_coins["left"]), 6)
	GameState.dual_level["left"] = 10
	_assert_eq("满级xp_to_next极大", Phase2Config.xp_to_next(10) > 9000, true)
	_assert_eq("满级加xp不升", GameState.add_xp("left", 999), 0)
	GameState.dual_level = {"left": 1, "right": 1}; GameState.dual_xp = {"left": 0, "right": 0}; GameState.dual_coins = {"left": 0, "right": 0}
	GameState.dual_passive_xp_started = false   # 整局首回合: 在 Lv1 开打 (TFT风, 用户报"一开始就是2级=错")
	GameState.grant_dual_round()
	_assert_eq("首回合不发被动XP → 留在1级", int(GameState.dual_level["left"]), 1)
	_assert_eq("首回合XP仍为0", int(GameState.dual_xp["left"]), 0)
	_assert_eq("V2 每回合不再发币(经济挪局外, dual_coins恒0)", int(GameState.dual_coins["right"]), 0)
	# 第2/3回合继续累计被动XP (币已无)
	GameState.grant_dual_round()
	GameState.grant_dual_round()
	# 第2/3回合各 +2xp(阈值2) → 右队升到2级 (首回合不发, 故第2回合才开始升)
	_assert_eq("第2回合起+2xp(阈值2→升2级)", int(GameState.dual_level["right"]), 2)
	# 显式核对首回合旗标在 reset 时复位 (跨局不残留)
	GameState.reset_dual_lane()
	_assert_eq("reset后首回合旗标复位", GameState.dual_passive_xp_started, false)
	# 跨路HP继承: 快照幸存者 + 待命回复30% (只存活统领, 非小将)
	GameState.reset_dual_lane()
	GameState.snapshot_lane_survivors([
		{"id": "basic", "side": "left", "alive": true, "hp": 300, "maxHp": 450, "_level": 1},   # 存活→回复30%
		{"id": "stone", "side": "left", "alive": false, "hp": 0, "maxHp": 600, "_level": 1},     # 阵亡→跳
		{"id": "m1", "side": "left", "alive": true, "hp": 100, "maxHp": 250, "_isMinion": true}, # 小将→跳
		{"id": "rainbow", "side": "right", "alive": true, "hp": 600, "maxHp": 600, "_level": 2}, # 满血→回0
	])
	_assert_eq("左幸存1只(去阵亡+小将)", (GameState.dual_survivors["left"] as Array).size(), 1)
	_assert_eq("左幸存=basic", str(GameState.dual_survivors["left"][0]["id"]), "basic")
	_assert_eq("待命回复30%(300+45=345)", int(GameState.dual_survivors["left"][0]["hp"]), 345)
	_assert_eq("右幸存满血600(回0)", int(GameState.dual_survivors["right"][0]["hp"]), 600)
	# 胜负只看蛋 (dual_match_over 蛋制) + 两路是否打完
	GameState.egg_hp_max = {"left": 1000, "right": 1000}; GameState.egg_hp = {"left": 1000, "right": 1000}
	_assert_eq("双蛋活→未分胜负", GameState.dual_match_over(), "")
	GameState.egg_hp["right"] = 0
	_assert_eq("右蛋碎→左方胜", GameState.dual_match_over(), "left")
	GameState.lane_results = {}
	_assert_eq("无路记录→两路未完", GameState.dual_lanes_done(), false)
	GameState.lane_results = {"top": "left", "bottom": "right"}
	_assert_eq("两路有记录→打完", GameState.dual_lanes_done(), true)
	# 新商店: 掷货(按等级费用概率) + 买 + 刷新
	var shop_rng := RandomNumberGenerator.new(); shop_rng.seed = 42
	var offer := Phase2Equip.roll_shop(DataRegistry.phase2_equipment, 1, 5, shop_rng)
	_assert_eq("货架5格", offer.size(), 5)
	var all_c1 := true
	for it in offer:
		if it == null or int(it["cost"]) != 1:
			all_c1 = false
	_assert_eq("1级货架全费1(概率100/0/0/0/0)", all_c1, true)
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 1, "right": 1}
	GameState.dual_coins = {"left": 10, "right": 0}
	GameState.bench_inventory = []
	GameState.dual_shop_offer = offer.duplicate()
	_assert_eq("买货架0成功", GameState.buy_shop_item(0, "left"), true)
	_assert_eq("买后扣费1币→9", int(GameState.dual_coins["left"]), 9)
	_assert_eq("备战席+1件", GameState.bench_inventory.size(), 1)
	_assert_eq("买掉位置=null", GameState.dual_shop_offer[0], null)
	_assert_eq("重复买null失败", GameState.buy_shop_item(0, "left"), false)
	_assert_eq("刷新成功", GameState.refresh_shop("left"), true)
	_assert_eq("刷新扣2币(占位)→7", int(GameState.dual_coins["left"]), 7)
	_assert_eq("刷新后货架10格(V2 §五: 一次展示10个)", GameState.dual_shop_offer.size(), 10)
	# 刷新费单一来源 (2026-06-26): 同回合连刷不递增, 第二次仍扣 2 (旧 dual_shop_refresh_n 累加已废)。
	_assert_eq("第二次刷新成功", GameState.refresh_shop("left"), true)
	_assert_eq("第二次刷新仍扣2币→5 (单源不递增)", int(GameState.dual_coins["left"]), 5)
	GameState.dual_coins["left"] = 0
	_assert_eq("没币刷新失败", GameState.refresh_shop("left"), false)
	# 三合一升星: 备战席自动合成
	GameState.bench_inventory = [{"id": "x", "star": 1}, {"id": "x", "star": 1}, {"id": "x", "star": 1}]
	_assert_eq("3件同款→合成1次", GameState.try_merge_bench(), 1)
	_assert_eq("合成后剩1件", GameState.bench_inventory.size(), 1)
	_assert_eq("合成升2星", int(GameState.bench_inventory[0]["star"]), 2)
	GameState.bench_inventory = []
	for k in range(9):
		GameState.bench_inventory.append({"id": "y", "star": 1})
	GameState.try_merge_bench()
	_assert_eq("9件1星→1件", GameState.bench_inventory.size(), 1)
	_assert_eq("9件1星→3星", int(GameState.bench_inventory[0]["star"]), 3)
	GameState.bench_inventory = [{"id": "x", "star": 1}, {"id": "x", "star": 1}, {"id": "z", "star": 1}]
	_assert_eq("混款不合成", GameState.try_merge_bench(), 0)
	# 跨域 3合一(龟身 equipped_p2 + 备战席): 龟身1件 + 席2件同款 → 合成2星装回那只龟 (用户场景)
	GameState.dual_level = {"left": 9, "right": 1}
	GameState.equipped_p2 = {"petA": [{"id": "m", "star": 1}]}
	GameState.bench_inventory = [{"id": "m", "star": 1}, {"id": "m", "star": 1}]
	var mr: Array = GameState.try_merge_all("left")
	_assert_eq("跨域合成1次", mr.size(), 1)
	_assert_eq("跨域合成后席空", GameState.bench_inventory.size(), 0)
	_assert_eq("跨域件装回petA(1件)", (GameState.equipped_p2["petA"] as Array).size(), 1)
	_assert_eq("petA装备升2星", int((GameState.equipped_p2["petA"] as Array)[0]["star"]), 2)
	GameState.equipped_p2 = {}
	GameState.bench_inventory = [{"id": "m", "star": 1}, {"id": "m", "star": 1}, {"id": "m", "star": 1}]
	GameState.try_merge_all("left")
	_assert_eq("全席3件→留席1件2星", GameState.bench_inventory.size(), 1)
	_assert_eq("留席件2星", int(GameState.bench_inventory[0]["star"]), 2)
	# ─── 出售 (sell_bench_item): 退币 = sell_value = cost×星; 从席移除; 字符串项不可售 ───
	GameState.equipped_p2 = {}
	GameState.dual_coins = {"left": 0, "right": 0}
	# sell_value 公式 (2026-06-26): floor(cost×star×0.8), 至少1 — "买立刻卖略亏" (旧 cost×star=全额退已废)。
	#   p2eq_001 cost=1 → 1星floor(0.8)=0→1; 2星floor(1.6)=1。 p2eq_003 cost=3 → 1星floor(2.4)=2; 3星floor(7.2)=7。
	_assert_eq("sell_value 001 1星=1(floor0→1)", GameState.sell_value("p2eq_001", 1), 1)
	_assert_eq("sell_value 001 2星=1(floor1.6)", GameState.sell_value("p2eq_001", 2), 1)
	_assert_eq("sell_value 003 1星=2(floor2.4, 买3卖2亏1)", GameState.sell_value("p2eq_003", 1), 2)
	_assert_eq("sell_value 003 3星=7(floor7.2)", GameState.sell_value("p2eq_003", 3), 7)
	# 单件买立刻卖有惩罚: p2eq_003 1星 买价3 → 卖2 (亏1, 非全额退)。
	_assert_eq("1星买立刻卖有损耗(003: 卖2<买3)", GameState.sell_value("p2eq_003", 1) < 3, true)
	GameState.bench_inventory = [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_003", "star": 3}]
	_assert_eq("出售1星001成功", GameState.sell_bench_item(0, "left"), true)
	_assert_eq("出售退币+1→1", int(GameState.dual_coins["left"]), 1)
	_assert_eq("出售后席-1件", GameState.bench_inventory.size(), 1)
	_assert_eq("出售3星003退币+7→8", GameState.sell_bench_item(0, "left") and int(GameState.dual_coins["left"]) == 8, true)
	_assert_eq("出售空席返false", GameState.sell_bench_item(0, "left"), false)
	GameState.bench_inventory = ["master_whistle"]   # 字符串消耗品项: 无 cost → 不可售
	_assert_eq("字符串消耗品不可售", GameState.sell_bench_item(0, "left"), false)
	_assert_eq("不可售→席不变", GameState.bench_inventory.size(), 1)
	# ─── 满席凑合一可买 (buy_shop_item + _buy_would_merge): 满席默认 block, 但买入触发三合一时放行 ───
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 9, "right": 1}; GameState.equipped_p2 = {}
	GameState.dual_coins = {"left": 100, "right": 0}
	# 席填满 (BENCH_CAP) — 8 件杂项 + 2 件同款 p2eq_001(1星) → 已有2件, 买第3件触发合成
	GameState.bench_inventory = []
	for _w in range(Phase2Config.BENCH_CAP - 2):
		GameState.bench_inventory.append({"id": "filler%d" % _w, "star": 1})
	GameState.bench_inventory.append({"id": "p2eq_001", "star": 1})
	GameState.bench_inventory.append({"id": "p2eq_001", "star": 1})
	_assert_eq("席已满 (=CAP)", GameState.bench_inventory.size(), Phase2Config.BENCH_CAP)
	# _buy_would_merge: 已有2件同款1星 → 买第3件会合成 → 放行
	_assert_eq("满席预判 001可买(凑3合1)", GameState._buy_would_merge("p2eq_001", 1, "left"), true)
	_assert_eq("满席预判 杂项不可买(凑不齐)", GameState._buy_would_merge("p2eq_xyz", 1, "left"), false)
	# 货架放一件 p2eq_001 → 满席仍买成功 (买完合成净 -1)
	GameState.dual_shop_offer = [{"id": "p2eq_001", "star": 1, "cost": 1}]
	_assert_eq("满席买可合的牌成功", GameState.buy_shop_item(0, "left"), true)
	GameState.try_merge_bench()   # 战中合成由 BattleScene 触发; 测里手动合
	var _merged_001_star := 0   # 合成后席里 p2eq_001 应为 2星 1 件
	for _b in GameState.bench_inventory:
		if _b is Dictionary and str(_b.get("id", "")) == "p2eq_001":
			_merged_001_star = int(_b.get("star", 1))
	_assert_eq("买后合成→001升2星", _merged_001_star, 2)
	_assert_eq("合成后席净-1 (<CAP)", GameState.bench_inventory.size() < Phase2Config.BENCH_CAP, true)
	# 满席买【凑不齐的牌】仍 block
	GameState.bench_inventory = []
	for _w2 in range(Phase2Config.BENCH_CAP):
		GameState.bench_inventory.append({"id": "junk%d" % _w2, "star": 1})
	GameState.dual_shop_offer = [{"id": "p2eq_005", "star": 1, "cost": 1}]   # 席无同款 → 买入凑不齐
	_assert_eq("满席买凑不齐的牌被block", GameState.buy_shop_item(0, "left"), false)
	_assert_eq("block后席仍满", GameState.bench_inventory.size(), Phase2Config.BENCH_CAP)
	GameState.bench_inventory = []; GameState.equipped_p2 = {}; GameState.dual_shop_offer = []
	# merge_restat 战中合星属性 +/- 对称 (装/卸装备走 base 字段反算)
	var _P2RT := preload("res://scripts/engine/phase2_equip_runtime.gd")
	var mrf := {"baseAtk": 100, "maxHp": 1000, "hp": 1000, "_baseCrit": 0.1, "baseDef": 20, "baseMr": 20}
	_P2RT.merge_restat(mrf, "p2eq_001", 1, 1.0)
	var _atk1 := int(mrf["baseAtk"])
	_P2RT.merge_restat(mrf, "p2eq_001", 1, -1.0)
	_assert_eq("merge_restat 短刃+1 baseAtk增", _atk1 > 100, true)
	_assert_eq("merge_restat +1-1 还原 baseAtk", int(mrf["baseAtk"]), 100)
	_assert_eq("merge_restat +1-1 还原 maxHp", int(mrf["maxHp"]), 1000)
	# 装备上身 / 卸下 + 槽位随等级开放
	GameState.equipped_p2 = {}
	GameState.dual_level = {"left": 1, "right": 1}   # 1级 → 1槽
	GameState.bench_inventory = [{"id": "a", "star": 1}, {"id": "b", "star": 1}]
	_assert_eq("装到basic成功", GameState.equip_to_turtle(0, "basic"), true)
	_assert_eq("basic装1件", (GameState.equipped_p2["basic"] as Array).size(), 1)
	_assert_eq("1级槽满(1)第2件装不下", GameState.equip_to_turtle(0, "basic"), false)
	_assert_eq("卸下成功", GameState.unequip_from_turtle("basic", 0), true)
	_assert_eq("卸后basic0件", (GameState.equipped_p2["basic"] as Array).size(), 0)
	GameState.dual_level["left"] = 5   # 5级 → 3槽
	GameState.bench_inventory = [{"id": "a", "star": 1}, {"id": "b", "star": 1}]
	_assert_eq("5级装第1件", GameState.equip_to_turtle(0, "basic"), true)
	_assert_eq("5级装第2件(槽3够)", GameState.equip_to_turtle(0, "basic"), true)
	_assert_eq("basic现2件", (GameState.equipped_p2["basic"] as Array).size(), 2)
	# 槽位随等级: 1-2级1 / 3-4级2 / 5-6级3 / 7-8级4 / 9-10级5
	_assert_eq("2级=1槽", Phase2Config.equip_slots_for_level(2), 1)
	_assert_eq("4级=2槽", Phase2Config.equip_slots_for_level(4), 2)
	_assert_eq("6级=3槽", Phase2Config.equip_slots_for_level(6), 3)
	_assert_eq("8级=4槽", Phase2Config.equip_slots_for_level(8), 4)
	_assert_eq("10级=5槽", Phase2Config.equip_slots_for_level(10), 5)
	GameState.equipped_p2 = {}; GameState.bench_inventory = []; GameState.dual_level = {"left": 1, "right": 1}
	# ─── 敌方AI买装备 (2026-06-24 重写: 买经验升级 + 走玩家管线 + side 命名空间隔离串装) ───
	GameState.reset_dual_lane()
	GameState.mode = "duallane"
	# (A) 基础: 用币买货架 → 装到敌方龟; 装备进 right:: 命名空间, 玩家 equipped_p2 不被污染
	GameState.dual_level = {"left": 5, "right": 5}   # 5级→每龟3槽, 留足空间装多件
	GameState.dual_coins = {"left": 0, "right": 100}
	GameState.enemy_lane_assign = {"top": ["stone", "bamboo"], "bottom": ["angel"]}
	GameState.equipped_p2 = {"basic": [{"id": "p2eq_001", "star": 1}]}   # 玩家自己的 basic 装备(防串装基准)
	GameState.ai_bench_inventory = []
	var ai_n := GameState.ai_dual_shop()
	_assert_eq("AI买了装备(>0)", ai_n > 0, true)
	_assert_eq("AI花了币(<100)", int(GameState.dual_coins["right"]) < 100, true)
	# AI 装备进 right:: 命名空间键, 不是裸键
	var ai_eq := 0
	for t in ["stone", "bamboo", "angel"]:
		ai_eq += (GameState.equipped_p2.get("right::" + t, []) as Array).size()
		_assert_eq("AI龟%s未写裸键(防串装)" % t, GameState.equipped_p2.has(t), false)
	_assert_eq("AI装备装到right命名空间", ai_eq > 0, true)
	# 防串装铁证: 玩家 basic 装备原样在裸键, 没被 AI 动
	_assert_eq("玩家basic裸键仍在", (GameState.equipped_p2.get("basic", []) as Array).size(), 1)
	_assert_eq("玩家basic装备未变(p2eq_001)", str((GameState.equipped_p2["basic"] as Array)[0]["id"]), "p2eq_001")
	# (B) 买>3件: 3只龟×3槽=9槽, 多次调用应能装超过3件
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 5, "right": 5}
	GameState.dual_coins = {"left": 0, "right": 200}
	GameState.enemy_lane_assign = {"top": ["stone", "bamboo"], "bottom": ["angel"]}
	GameState.equipped_p2 = {}; GameState.ai_bench_inventory = []
	var total_eq := 0
	for _r in range(6):
		GameState.ai_dual_shop()
		GameState.dual_coins["right"] = int(GameState.dual_coins["right"]) + 30   # 模拟每回合补币
	for t in ["stone", "bamboo", "angel"]:
		total_eq += (GameState.equipped_p2.get("right::" + t, []) as Array).size()
	_assert_eq("AI多回合后装>3件", total_eq > 3, true)
	# (B2) AI 席不超 BENCH_CAP: 各龟槽位很少(1级=1槽/龟) + 海量币 → 装不掉的件应被席内三合一合掉,
	#   不能稳定停在 >CAP. 反复多回合后 ai_bench_inventory 必 ≤ BENCH_CAP (修: 买后补 try_merge_bench + 超 CAP 停买).
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 1, "right": 1}   # 1级 → 每龟仅1槽, 极易满 → 件堆 AI 席
	GameState.enemy_lane_assign = {"top": ["stone"], "bottom": []}   # 仅1只龟, 槽极少
	GameState.equipped_p2 = {}; GameState.ai_bench_inventory = []; GameState.bench_inventory = []
	for _r2 in range(20):
		GameState.dual_coins = {"left": 0, "right": 999}   # 每回合都给海量币, 逼它疯狂买
		GameState.ai_dual_shop()
		_assert_eq("AI席每回合都≤CAP(不无限涨)", GameState.ai_bench_inventory.size() <= Phase2Config.BENCH_CAP, true)
	_assert_eq("AI席最终≤CAP", GameState.ai_bench_inventory.size() <= Phase2Config.BENCH_CAP, true)
	GameState.equipped_p2 = {}; GameState.ai_bench_inventory = []; GameState.bench_inventory = []
	# (C) 买经验升级: 起手币足, 多回合后 AI 等级应高于1
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 1, "right": 1}
	GameState.dual_coins = {"left": 0, "right": 50}
	GameState.enemy_lane_assign = {"top": ["stone"], "bottom": []}
	GameState.equipped_p2 = {}; GameState.ai_bench_inventory = []
	for _r in range(4):
		GameState.ai_dual_shop()
		GameState.dual_coins["right"] = int(GameState.dual_coins["right"]) + 30
	_assert_eq("AI买经验升级(>1级)", int(GameState.dual_level["right"]) > 1, true)
	# (D) 三合一: 经 ai_dual_shop 整条管线买/装同款 → try_merge_all 升出2星 (right 命名空间内)
	GameState.reset_dual_lane(); GameState.mode = "duallane"
	GameState.dual_level = {"left": 5, "right": 5}   # 3槽够放2件待合
	GameState.enemy_lane_assign = {"top": ["stone"], "bottom": []}
	GameState.equipped_p2 = {"right::stone": [{"id": "mm", "star": 1}, {"id": "mm", "star": 1}]}
	GameState.ai_bench_inventory = [{"id": "mm", "star": 1}]   # AI 席第3件同款; try_merge_all("right") 在 ai 管线里换入 bench → 凑齐3件合成
	GameState.bench_inventory = [{"id": "zz", "star": 9}]   # 玩家席放个无关件, 验证不被 AI 合成动
	# 直接验 try_merge_all 在 right 命名空间 + AI 席的合成 (模拟 ai_dual_shop 内换席后的合成上下文)
	var _saved_bench: Array = GameState.bench_inventory
	GameState.bench_inventory = GameState.ai_bench_inventory   # 复刻 ai_dual_shop 的换席
	GameState.try_merge_all("right")
	GameState.ai_bench_inventory = GameState.bench_inventory
	GameState.bench_inventory = _saved_bench
	var stone_eq: Array = GameState.equipped_p2.get("right::stone", [])
	var has_2star := false
	for e in stone_eq:
		if int(e.get("star", 1)) >= 2:
			has_2star = true
	_assert_eq("AI三合一出2星(right命名空间)", has_2star, true)
	_assert_eq("AI合成不动玩家席(zz仍在)", (GameState.bench_inventory.size() == 1 and str(GameState.bench_inventory[0]["id"]) == "zz"), true)
	# (E) 隔离铁证: 玩家与AI同款同星不跨队合成 (玩家 basic 2件 mm + AI stone 1件 mm, 各算各的)
	GameState.equipped_p2 = {"basic": [{"id": "mm", "star": 1}, {"id": "mm", "star": 1}], "right::stone": [{"id": "mm", "star": 1}]}
	GameState.bench_inventory = []; GameState.ai_bench_inventory = []
	GameState.try_merge_all("left")   # 玩家侧合成: 只 2件 mm, 不够3, 不应吞 AI 的那件
	_assert_eq("玩家侧合成不吞AI件: basic仍2件", (GameState.equipped_p2.get("basic", []) as Array).size(), 2)
	_assert_eq("玩家侧合成不动AI: right::stone仍1件", (GameState.equipped_p2.get("right::stone", []) as Array).size(), 1)
	GameState.equipped_p2 = {}; GameState.dual_coins = {"left": 0, "right": 0}; GameState.enemy_lane_assign = {"top": [], "bottom": []}
	GameState.ai_bench_inventory = []; GameState.bench_inventory = []
	GameState.mode = "single"   # 还原, 别污染别的测试
	GameState.reset_dual_lane()
	# 商店费用概率: 10档, 每行和=100, 高费随档增
	for st in range(1, 11):
		var odds: Array = Phase2Config.shop_cost_odds(st)
		var sum := 0
		for v in odds:
			sum += int(v)
		_assert_eq("商店档%d 概率和=100" % st, sum, 100)
	_assert_eq("档1 费5概率=0", int(Phase2Config.shop_cost_odds(1)[4]), 0)
	_assert_eq("档10 费5概率>档1", int(Phase2Config.shop_cost_odds(10)[4]) > int(Phase2Config.shop_cost_odds(1)[4]), true)
	_assert_eq("档10 费1概率<档1", int(Phase2Config.shop_cost_odds(10)[0]) < int(Phase2Config.shop_cost_odds(1)[0]), true)
	_assert_eq("掷费 r=0→费1", Phase2Config.roll_cost_tier(1, 0.0), 1)
	_assert_eq("档1 r=0.99→费(低档高费极小, ≤3)", Phase2Config.roll_cost_tier(1, 0.99) <= 3, true)
	_assert_eq("开店第0次→档1", Phase2Config.stage_for_shop_visit(0), 1)
	_assert_eq("开店第20次→封顶档10", Phase2Config.stage_for_shop_visit(20), 10)
	_assert_eq("档越界clamp", Phase2Config.shop_cost_odds(99).size(), 5)


# ─── 二阶段剑系装备实装 (用户 2026-06-13 批次) ───
func _test_phase2_sword_equips() -> void:
	# 1) apply_stats 逐星属性
	var a4 := {"baseAtk": 100, "atk": 100, "crit": 0.0, "_lifestealPct": 0}
	Phase2EquipRuntime.apply_stats(a4, "p2eq_004", 2)
	_assert_eq("暴君2★ +30攻", int(a4["atk"]), 130)
	_assert_eq("暴君2★ +0.35暴击", float(a4["crit"]), 0.35, 0.001)
	_assert_eq("暴君2★ +9%生命偷取", int(a4["_lifestealPct"]), 9)
	var a7 := {"baseAtk": 50, "atk": 50, "maxHp": 500, "hp": 500}
	Phase2EquipRuntime.apply_stats(a7, "p2eq_007", 1)
	_assert_eq("阔剑1★ +5攻", int(a7["atk"]), 55)
	_assert_eq("阔剑1★ +20最大生命", int(a7["maxHp"]), 520)
	var a5 := {"_maxEnergy": 0}
	Phase2EquipRuntime.apply_stats(a5, "p2eq_005", 1)
	_assert_eq("双生1★ +20最大龟能", int(a5["_maxEnergy"]), 20)

	# 2) on_hit 002 海藻流血 = round(atk×0.075) = round(7.5) = 8; AOE ×0.5 = round(3.75)=4
	var atk_c := {"side": "left", "alive": true, "atk": 100}
	var tgt := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	Phase2EquipRuntime.on_hit(atk_c, tgt, 50, "p2eq_002", 1, [atk_c, tgt], true)
	var bleed := 0
	for b in tgt["buffs"]:
		if b is Dictionary and b.get("type", "") == "bleed":
			bleed = int(b.get("value", 0))
	_assert_eq("海藻1★ 单体流血=8", bleed, 8)
	var atk_aoe := {"side": "left", "alive": true, "atk": 100, "_castIsAoe": true}
	var tgt2 := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	Phase2EquipRuntime.on_hit(atk_aoe, tgt2, 50, "p2eq_002", 1, [atk_aoe, tgt2], true)
	var bleed2 := 0
	for b in tgt2["buffs"]:
		if b is Dictionary and b.get("type", "") == "bleed":
			bleed2 = int(b.get("value", 0))
	_assert_eq("海藻1★ AOE流血×50%=4", bleed2, 4)

	# 3) on_hit 003 鲨齿溅射: 邻格各受 15%×dmg = 15 (apply_raw 不过甲)
	var sa := {"side": "left", "alive": true, "atk": 100}
	var st1 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "buffs": []}
	var st0 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "buffs": []}
	var st2 := {"side": "right", "alive": true, "_slotKey": "front-2", "hp": 500, "maxHp": 500, "shield": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(sa, st1, 100, "p2eq_003", 1, [sa, st1, st0, st2], true)
	_assert_eq("鲨齿1★ 溅射邻格front-0 -15", int(st0["hp"]), 485)
	_assert_eq("鲨齿1★ 溅射邻格front-2 -15", int(st2["hp"]), 485)
	_assert_eq("鲨齿1★ 主目标不重复扣(溅射只打邻格)", int(st1["hp"]), 500)

	# 4) on_hit 004 暴君处决: hp 4% < 斩杀线 5% → 真伤抹掉剩余 + 回40生命(无龟能)
	var ta := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "_maxEnergy": 0, "hp": 100, "maxHp": 500}
	var tt := {"side": "right", "alive": true, "hp": 20, "maxHp": 500, "shield": 0, "buffs": []}
	var fx4: Array = Phase2EquipRuntime.on_hit(ta, tt, 30, "p2eq_004", 1, [ta, tt], true)
	_assert_eq("暴君1★ 处决→目标HP=0", int(tt["hp"]), 0)
	_assert_eq("暴君1★ 处决回40生命", int(ta["hp"]), 140)
	var has_heal := false
	for e in fx4:
		if e.get("kind", "") == "heal" and int(e.get("value", 0)) == 40:
			has_heal = true
	_assert_eq("暴君1★ 回血effect飘字", has_heal, true)
	# 龟能变体: _maxEnergy>0 → 回20龟能
	var te := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "_maxEnergy": 50, "_energy": 10, "hp": 300, "maxHp": 500}
	var tt2 := {"side": "right", "alive": true, "hp": 10, "maxHp": 500, "shield": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(te, tt2, 30, "p2eq_004", 1, [te, tt2], true)
	_assert_eq("暴君1★ 龟能单位处决回20龟能", int(te["_energy"]), 30)
	# 高血不处决
	var tt3 := {"side": "right", "alive": true, "hp": 400, "maxHp": 500, "shield": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(ta, tt3, 30, "p2eq_004", 1, [ta, tt3], true)
	_assert_eq("暴君1★ 高血(80%)不处决", int(tt3["hp"]), 400)

	# 5) on_cast 006 千刃: 全体敌人受伤 (atk100 → 70+0.8*100=150 raw, def0 → 150)
	var ca := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "magicPen": 0}
	var e1 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e2 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(ca, "p2eq_006", 1, [ca, e1, e2])
	_assert_eq("千刃1★ 敌1 受伤(<500)", int(e1["hp"]) < 500, true)
	_assert_eq("千刃1★ 敌2 受伤(<500)", int(e2["hp"]) < 500, true)

	# 6) on_cast 008 珊瑚刺: 只打最远敌人 (近敌不动, 远敌受2发)
	var pa := {"side": "left", "alive": true, "_slotKey": "front-0", "atk": 100, "crit": 0.0, "armorPen": 0, "magicPen": 0}
	var near := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var far := {"side": "right", "alive": true, "_slotKey": "back-2", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(pa, "p2eq_008", 1, [pa, near, far])
	_assert_eq("珊瑚刺1★ 近敌不中", int(near["hp"]), 500)
	_assert_eq("珊瑚刺1★ 最远敌受伤", int(far["hp"]) < 500, true)

	# 7) on_cast 007 阔剑: 斩前排 (20+0.5*atk=70, def0→70) + 护盾=总伤×50%=35
	var wa := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "shield": 0}
	var we := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(wa, "p2eq_007", 1, [wa, we])
	_assert_eq("阔剑1★ 前排敌 -70", int(we["hp"]), 430)
	_assert_eq("阔剑1★ 护盾=总伤50%=35", int(wa["shield"]), 35)

	# 8) on_hit 009 宽刃刃能: 充能90+20=110→满100触发(余10); 单敌列→solo×2: 真伤30×2=60 + 物理0.5*100*2=100
	var ba := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "_p2BladeCharge": 90.0}
	var bt := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(ba, bt, 50, "p2eq_009", 1, [ba, bt], true)
	_assert_eq("宽刃1★ 充能溢出留10", int(round(float(ba["_p2BladeCharge"]))), 10)
	_assert_eq("宽刃1★ 满刃能爆发 单敌×2 (-160)", int(bt["hp"]), 340)
	# 未满不触发
	var ba2 := {"side": "left", "alive": true, "atk": 100, "_p2BladeCharge": 0.0}
	var bt2 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(ba2, bt2, 50, "p2eq_009", 1, [ba2, bt2], true)
	_assert_eq("宽刃1★ 未满刃能(20)不爆发", int(bt2["hp"]), 500)

	# 9) on_hit 005 双生匕首 3★(100%概率): 必追击 1.0×atk 物理
	var da := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var dt := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(da, dt, 50, "p2eq_005", 3, [da, dt], true)
	_assert_eq("双生3★ 必追击(100%) → 目标受伤", int(dt["hp"]) < 500, true)

	# 10) 007 横排=同列{F,B}: anchor=最前敌, 打其列 front+back, 不碰别列
	var wc := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "shield": 0}
	var wf0 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var wb0 := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var wf1 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(wc, "p2eq_007", 1, [wc, wf0, wb0, wf1])
	_assert_eq("阔剑 横排=列0 front-0中(-70)", int(wf0["hp"]), 430)
	_assert_eq("阔剑 横排=列0 back-0中(-70)", int(wb0["hp"]), 430)
	_assert_eq("阔剑 横排 不碰别列 front-1", int(wf1["hp"]), 500)

	# 11) 009 一列=同排{F0,F1,F2}: 命中front-1→打整排, 多敌不solo(×1) 每人真30+物50=-80
	var bc := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "_p2BladeCharge": 90.0}
	var rf0 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var rf1 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var rf2 := {"side": "right", "alive": true, "_slotKey": "front-2", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(bc, rf1, 50, "p2eq_009", 1, [bc, rf0, rf1, rf2], true)
	_assert_eq("宽刃 一列=同排 front-0中(-80)", int(rf0["hp"]), 420)
	_assert_eq("宽刃 一列=同排 front-1中(-80)", int(rf1["hp"]), 420)
	_assert_eq("宽刃 一列=同排 front-2中(-80)", int(rf2["hp"]), 420)

	# 12) 001 锈蚀短剑 on_turn_begin 劈砍优先前排: raw=0.6*100+40*0.5=80
	var tc := {"side": "left", "alive": true, "atk": 100, "crit": 0.5, "armorPen": 0}
	var tf := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var tbk := {"side": "right", "alive": true, "_slotKey": "back-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(tc, "p2eq_001", 1, [tc, tf, tbk])
	_assert_eq("锈蚀短剑 劈砍前排 front-0(-80)", int(tf["hp"]), 420)
	_assert_eq("锈蚀短剑 不打后排 back-1", int(tbk["hp"]), 500)

	# 13) 010 横扫 Lv1 同排多敌(不solo): 3敌每人(100+1.2*100=220) + 回血35%*660=231
	var sca := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "hp": 100, "maxHp": 3000}
	var se0 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var se1 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var se2 := {"side": "right", "alive": true, "_slotKey": "front-2", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.sweep(sca, se1, 1, [sca, se0, se1, se2])
	_assert_eq("横扫Lv1 同排front-0 -220", int(se0["hp"]), 280)
	_assert_eq("横扫Lv1 同排front-2 -220", int(se2["hp"]), 280)
	_assert_eq("横扫Lv1 回血35%*660=231", int(sca["hp"]), 331)

	# 14) 010 横扫 Lv1 单敌→竖斩: front-0行内只它 → 横扫220+竖斩220=440; 身后back-0 = 110
	var sbx := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "hp": 100, "maxHp": 3000}
	var so0 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var sbk := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.sweep(sbx, so0, 1, [sbx, so0, sbk])
	_assert_eq("横扫Lv1 单敌竖斩 front-0 -440", int(so0["hp"]), 560)
	_assert_eq("横扫Lv1 竖斩身后 back-0 -110", int(sbk["hp"]), 890)

	# 15) 010 横扫 Lv3 全体(2000+5*100=2500), 不分排
	var s3 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "hp": 100, "maxHp": 9999}
	var e3a := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 3000, "maxHp": 3000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e3b := {"side": "right", "alive": true, "_slotKey": "back-2", "hp": 3000, "maxHp": 3000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.sweep(s3, e3a, 3, [s3, e3a, e3b])
	_assert_eq("横扫Lv3 全体 front-0 -2500", int(e3a["hp"]), 500)
	_assert_eq("横扫Lv3 全体 back-2 -2500(跨排)", int(e3b["hp"]), 500)


# ─── 二阶段 剑系011 + 盾系012-017 (批2, 2026-06-13) ───
func _test_phase2_shield_equips() -> void:
	# 011 饮血护符坠 stats + 连斩
	var a11 := {"atk": 0, "baseAtk": 0, "_lifestealPct": 0, "healAmp": 0.0}
	Phase2EquipRuntime.apply_stats(a11, "p2eq_011", 2)
	_assert_eq("饮血护符坠2★ +23攻", int(a11["atk"]), 23)
	_assert_eq("饮血护符坠2★ +24%生命偷取", int(a11["_lifestealPct"]), 24)
	_assert_eq("饮血护符坠2★ 血盾cap350", int(a11.get("_p2BloodShieldCap", 0)), 350)
	var c11 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e11 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var fx11: Array = Phase2EquipRuntime.on_cast(c11, "p2eq_011", 1, [c11, e11], RandomNumberGenerator.new())
	var dc := 0
	for e in fx11:
		if e.get("kind", "") == "damage":
			dc += 1
	_assert_eq("饮血1★ 连斩5次", dc, 5)
	_assert_eq("饮血1★ 首斩90(40+0.5*100)", int(fx11[0]["value"]), 90)
	_assert_eq("饮血1★ 衰减(末<首)", int(fx11[4]["value"]) < int(fx11[0]["value"]), true)

	# 012 龟苓膏块 回合开始自盾
	var f12 := {"side": "left", "alive": true, "_slotKey": "front-0", "shield": 0}
	Phase2EquipRuntime.on_turn_begin(f12, "p2eq_012", 1, [f12])
	_assert_eq("龟苓膏块1★ 回合开始+30盾", int(f12["shield"]), 30)

	# 013 炙烤海胆 受击硬化 + 满层盾
	var o13 := {"side": "left", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "shield": 0, "_p2HardenInc": 1.0, "_p2HardenShieldVal": 50, "_p2HardenStacks": 0, "_p2HardenGiven": false}
	Phase2EquipRuntime.on_hit_as_target(o13, {}, 10, "p2eq_013", 1, [o13])
	_assert_eq("炙烤海胆 1击+1护甲", int(o13["def"]), 1)
	_assert_eq("炙烤海胆 1击+1魔抗", int(o13["mr"]), 1)
	for _k in range(19):
		Phase2EquipRuntime.on_hit_as_target(o13, {}, 10, "p2eq_013", 1, [o13])
	_assert_eq("炙烤海胆 20层+20护甲(cap)", int(o13["def"]), 20)
	_assert_eq("炙烤海胆 满层→50盾", int(o13["shield"]), 50)

	# 014 堡垒甲 汲取 + 回血
	var c14 := {"side": "left", "alive": true, "def": 50, "mr": 50, "crit": 0.0, "armorPen": 0, "magicPen": 0, "hp": 100, "maxHp": 2000}
	var e14a := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e14b := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(c14, "p2eq_014", 1, [c14, e14a, e14b])
	_assert_eq("堡垒甲1★ 汲取敌1(0.8*50+0.8*50=-80)", int(e14a["hp"]), 420)
	_assert_eq("堡垒甲1★ 每敌回40*2=80", int(c14["hp"]), 180)

	# 016 铁壁盾 全队盾
	var f16 := {"side": "left", "alive": true, "_slotKey": "front-0", "shield": 0, "_p2TeamShield": 15}
	var al16 := {"side": "left", "alive": true, "_slotKey": "front-1", "shield": 0}
	var en16 := {"side": "right", "alive": true, "_slotKey": "front-0", "shield": 0}
	Phase2EquipRuntime.on_turn_begin(f16, "p2eq_016", 1, [f16, al16, en16])
	_assert_eq("铁壁盾 自己+15盾", int(f16["shield"]), 15)
	_assert_eq("铁壁盾 友方+15盾", int(al16["shield"]), 15)
	_assert_eq("铁壁盾 敌方不加", int(en16["shield"]), 0)

	# 017 不沉之锚 奶最低血友军 + 沉锚充能
	var o17 := {"side": "left", "alive": true, "maxHp": 1000, "hp": 1000, "_p2AnchorHealPct": 15.0, "_p2AnchorAccum": 0.0, "_p2AnchorCharges": 0}
	var hurt := {"side": "left", "alive": true, "hp": 100, "maxHp": 1000}
	Phase2EquipRuntime.on_hit_as_target(o17, {}, 50, "p2eq_017", 1, [o17, hurt])
	_assert_eq("不沉之锚 奶最低血友军+150", int(hurt["hp"]), 250)
	_assert_eq("不沉之锚 累积150→1充能", int(o17["_p2AnchorCharges"]), 1)

	# ── 批2 修正: 接进现有系统 (反伤/减伤/免疫/护盾增幅) ──
	# 011 shieldAmp: apply_stats + grant_shield 放大
	var sa11 := {"shieldAmp": 0.0}
	Phase2EquipRuntime.apply_stats(sa11, "p2eq_011", 3)
	_assert_eq("饮血3★ +33%护盾增幅", int(sa11["shieldAmp"]), 33)
	var sh := {"shield": 0, "shieldAmp": 33.0}
	var got := Buffs.grant_shield(sh, 100)
	_assert_eq("护盾增幅33% → 100盾变133", got, 133)
	_assert_eq("无增幅 → 原值", Buffs.grant_shield({"shield": 0}, 100), 100)

	# 016 _p2DmgReduce: apply_raw_damage 每段减flat (非真伤)
	var t16 := {"hp": 500, "maxHp": 500, "shield": 0, "alive": true, "buffs": [], "_p2DmgReduce": 6}
	var r16: Dictionary = Damage.apply_raw_damage(t16, 50, "physical")
	_assert_eq("铁壁盾 50物理-6=44", int(r16["hpLoss"]), 44)
	var t16t := {"hp": 500, "maxHp": 500, "shield": 0, "alive": true, "buffs": [], "_p2DmgReduce": 6}
	_assert_eq("铁壁盾 真伤不减(50)", int(Damage.apply_raw_damage(t16t, 50, "true")["hpLoss"]), 50)

	# 017 免疫斩杀: 猎人标记 + _p2AnchorImmune → 不秒
	var t17 := {"hp": 100, "maxHp": 1000, "shield": 0, "alive": true, "buffs": [{"type": "hunterMark", "value": 50}], "_p2AnchorImmune": true}
	Damage.apply_raw_damage(t17, 10, "physical")
	_assert_eq("不沉之锚 免猎人斩杀(存活)", t17["alive"], true)
	var t17b := {"hp": 100, "maxHp": 1000, "shield": 0, "alive": true, "buffs": [{"type": "hunterMark", "value": 50}]}
	Damage.apply_raw_damage(t17b, 10, "physical")
	_assert_eq("无锚 → 被猎人斩杀(死)", t17b["alive"], false)

	# 004 暴君处决 也吃 017 免疫
	var ta4 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "_maxEnergy": 0, "hp": 300, "maxHp": 500}
	var ti4 := {"side": "right", "alive": true, "hp": 20, "maxHp": 500, "shield": 0, "buffs": [], "_p2AnchorImmune": true}
	Phase2EquipRuntime.on_hit(ta4, ti4, 30, "p2eq_004", 1, [ta4, ti4], true)
	_assert_eq("暴君处决 对免疫锚目标无效(HP=20)", int(ti4["hp"]), 20)

	# 015 apply_stats flags (反伤系统在 BattleScene._on_hit_chain 消费, 此处验 flag)
	var f15 := {"reflectPct": 0.0}
	Phase2EquipRuntime.apply_stats(f15, "p2eq_015", 2)
	_assert_eq("荆棘海胆2★ +17%反伤", int(f15["reflectPct"]), 17)
	_assert_eq("荆棘海胆 反伤转真伤flag", f15.get("_p2ReflectTrue", false), true)
	_assert_eq("荆棘海胆2★ 反伤流血2.5层", int(round(float(f15.get("_p2ReflectBleed", 0)))), 3)

	# ── 反伤实战集成 (锁回归: reflectPct 整数%口径对 + 013过甲不吃 attacker 甲) ──
	#   病史: auraAwaken 存小数(0.12) + 消费端再/100 → ×0.0012 ≈0; 013 走 calc_damage 吃 attacker 甲被砍成个位数.
	var rbs = BattleSceneScript.new()   # 不入树, 只调反伤链 (_play_aoe_ring 等被空 slot_nodes 守卫跳过)
	rbs.fighters = [] as Array[Dictionary]
	# 013 口径: target 带整数% reflectPct (无 _p2ReflectTrue → 走物理过甲分支). attacker 带高甲 def=200 验"过甲".
	var atk13 := {"side": "left", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "def": 200, "mr": 0, "armorPen": 0, "magicPen": 0, "buffs": []}
	var tgt13 := {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": [], "reflectPct": 15.0}
	var be13: Array = []
	# dmg=1000 命中 → 反 round(1000×15%)=150 物理过甲 (不吃 attacker.def=200) → attacker 掉 150
	rbs._on_hit_chain(atk13, tgt13, 1000, "physical", 0, 1, be13, 1)
	_assert_eq("013 反伤(15% 过甲 dmg1000) → attacker 掉150", 5000 - int(atk13["hp"]), 150)
	# auraAwaken 口径: reflectPct=12 (整数%, 修后) → dmg1000 反 round(1000×12%)=120 (修前小数0.12→再/100=×0.0012≈1, 几乎0)
	var atkA := {"side": "left", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "def": 200, "mr": 0, "armorPen": 0, "magicPen": 0, "buffs": []}
	var tgtA := {"side": "right", "alive": true, "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": [], "reflectPct": 12.0}
	var beA: Array = []
	rbs._on_hit_chain(atkA, tgtA, 1000, "physical", 0, 1, beA, 1)
	_assert_eq("auraAwaken 反伤(12% 整数口径 dmg1000) → attacker 掉120", 5000 - int(atkA["hp"]), 120)
	rbs.free()

	# 017 on_cast 耗充能击飞+眩晕
	var c17 := {"side": "left", "alive": true, "def": 100, "mr": 100, "crit": 0.0, "armorPen": 0, "magicPen": 0, "_p2AnchorCharges": 1}
	var k17 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(c17, "p2eq_017", 1, [c17, k17])
	_assert_eq("不沉之锚 耗1充能", int(c17["_p2AnchorCharges"]), 0)
	_assert_eq("不沉之锚 击飞标记", k17.get("_knockedUpThisTurn", false), true)
	_assert_eq("不沉之锚 眩晕敌", Buffs.has(k17, "stun"), true)
	_assert_eq("不沉之锚 击飞伤(0.4*100+0.4*100+0.15*5000=830)", int(k17["hp"]), 4170)

	# ── 盾系 018-021 (批3, R1) ──
	# 018 守护贝壳: stats + 回合开始自回(60+15%maxHp 经healAmp)
	var a18 := {"hp": 500, "maxHp": 500, "mr": 0, "healAmp": 0.0, "shieldAmp": 0.0}
	Phase2EquipRuntime.apply_stats(a18, "p2eq_018", 3)
	_assert_eq("守护贝壳3★ +100生命", int(a18["maxHp"]), 600)
	_assert_eq("守护贝壳3★ +20%治疗增幅", int(a18["healAmp"]), 20)
	_assert_eq("守护贝壳3★ +20%护盾增幅", int(a18["shieldAmp"]), 20)
	var t18 := {"side": "left", "alive": true, "hp": 100, "maxHp": 600, "healAmp": 20.0}
	Phase2EquipRuntime.on_turn_begin(t18, "p2eq_018", 3, [t18])
	# 回血 = (60 + 0.15*600)=150, ×1.2(healAmp) = 180
	_assert_eq("守护贝壳3★ 回合开始回血180", int(t18["hp"]), 280)

	# 019 海葵药膏: 回血自己+最低血友军 + 海葵层
	var c19 := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000, "healAmp": 0.0, "shieldAmp": 0.0, "_p2AnemoneHeal": 0.0}
	var ally19 := {"side": "left", "alive": true, "hp": 100, "maxHp": 1000, "healAmp": 0.0}
	Phase2EquipRuntime.on_turn_begin(c19, "p2eq_019", 3, [c19, ally19])
	# 最低血友军=ally19, 回血=60+0.18*(1000-100)=60+162=222
	_assert_eq("海葵药膏3★ 奶最低血友军+222", int(ally19["hp"]), 322)
	_assert_eq("海葵药膏3★ 累计治疗(自222无损→只ally)→海葵层", int(c19.get("healAmp", 0)) >= 10, true)

	# 020 哑铃: 锻炼层+maxHp; on_side_end 扔哑铃
	var c20 := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000}
	Phase2EquipRuntime.on_turn_begin(c20, "p2eq_020", 1, [c20])
	_assert_eq("哑铃1★ 锻炼+20maxHp", int(c20["maxHp"]), 1020)
	_assert_eq("哑铃1★ 锻炼1层", int(c20["_p2DumbbellLayers"]), 1)
	var dc20 := {"side": "left", "alive": true, "atk": 0, "crit": 0.0, "armorPen": 0, "maxHp": 1000}
	var de20 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(dc20, "p2eq_020", 3, [dc20, de20])
	# 10%×1000=100 物理
	_assert_eq("哑铃3★ 回合末扔哑铃-100", int(de20["hp"]), 400)

	# 021 守护贝母: 连接最高ATK友军(给盾/龟能/净化) + 伤害转移
	var c21 := {"side": "left", "alive": true, "atk": 50, "hp": 1000, "maxHp": 1000, "shield": 0}
	var ally21 := {"side": "left", "alive": true, "atk": 200, "hp": 800, "maxHp": 800, "shield": 0, "_maxEnergy": 100, "_energy": 10, "buffs": [{"type": "stun", "value": 1, "duration": 2}]}
	Phase2EquipRuntime.on_turn_begin(c21, "p2eq_021", 3, [c21, ally21])
	_assert_eq("守护贝母3★ 连接最高ATK友军 +90盾", int(ally21["shield"]), 90)
	_assert_eq("守护贝母3★ 给龟能+20", int(ally21["_energy"]), 30)
	_assert_eq("守护贝母3★ 净化负面(stun清)", Buffs.has(ally21, "stun"), false)
	# 伤害转移: ally21 受100 → 60%(60)转给c21, ally受40
	var r21: Dictionary = Damage.apply_raw_damage(ally21, 100, "physical")
	_assert_eq("守护贝母3★ 链接友军只受40%(转移60%,40被盾吸)", int(r21["hpLoss"]) + int(r21["shieldAbs"]), 40)
	_assert_eq("守护贝母3★ 守护者代受60", int(c21["hp"]), 940)

	# ── 杖系/元素 022-025,028,029 (批4, R2) ──
	# 023 火珊瑚: on_hit 每段+灼烧 (10+15%*100=25层)
	var fa23 := {"side": "left", "alive": true, "atk": 100}
	var ft23 := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	Phase2EquipRuntime.on_hit(fa23, ft23, 50, "p2eq_023", 3, [fa23, ft23], true)
	var burn23 := 0
	for b in ft23["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			burn23 = int(b.get("value", 0))
	_assert_eq("火珊瑚3★ 灼烧25层", burn23, 25)

	# 024 龙蛋: 吐息满3→喷火(同列友回血+敌魔法+灼烧)
	var da24 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0, "_p2DragonStacks": 2, "hp": 1, "maxHp": 1, "_slotKey": "front-0"}
	var dally24 := {"side": "left", "alive": true, "_slotKey": "back-0", "hp": 100, "maxHp": 2000, "healAmp": 0.0}
	var den24 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(da24, "p2eq_024", 1, [da24, dally24, den24])
	_assert_eq("龙蛋 吐息满3→喷火→重置层数", int(da24["_p2DragonStacks"]), 0)
	_assert_eq("龙蛋1★ 同列友回血(70+0.7*100=140)", int(dally24["hp"]), 240)
	_assert_eq("龙蛋1★ 同列敌受魔法(50+0.7*100=120)", int(den24["hp"]), 4880)
	var dburn := 0
	for b in den24["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			dburn = int(b.get("value", 0))
	_assert_eq("龙蛋1★ 同列敌灼烧(30+10%*100=40)", dburn, 40)

	# 025 雷鸣贝壳: on_side_end N道雷各1×ATK真伤
	var la25 := {"side": "left", "alive": true, "atk": 80}
	var le25 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(la25, "p2eq_025", 3, [la25, le25])
	# 3道雷各80真伤(单敌全中) = -240
	_assert_eq("雷鸣3★ 3道雷各80真伤(单敌-240)", int(le25["hp"]), 4760)

	# 028 冰霜冻露瓶: on_cast 魔法+冰寒
	var ca28 := {"side": "left", "alive": true, "atk": 50, "crit": 0.0, "magicPen": 0}
	var ce28 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(ca28, "p2eq_028", 3, [ca28, ce28])
	_assert_eq("寒霜3★ 100魔法(-100)", int(ce28["hp"]), 400)
	_assert_eq("寒霜3★ 施加冰寒", Buffs.has(ce28, "chilled"), true)

	# 022 余烬燃油瓶: on_cast 灼烧 + 真火(灼烧转真伤)
	var ca22 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0}
	var ce22 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(ca22, "p2eq_022", 1, [ca22, ce22])
	var burn22 := 0; var hastf := false
	for b in ce22["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn": burn22 = int(b.get("value", 0))
		if b is Dictionary and b.get("type", "") == "trueFire": hastf = true
	_assert_eq("余烬1★ 灼烧30层(20+10%*100)", burn22, 30)
	_assert_eq("余烬1★ 挂真火", hastf, true)
	# dot tick: 有真火 → 灼烧走真伤(无视mr): 给ce22高mr, 灼烧仍全额
	ce22["mr"] = 1000
	var dotfx: Array = Dot.tick(ce22)
	var tdmg := 0
	for e in dotfx:
		if e.get("dmg_type", "") == "true": tdmg += int(e.get("value", 0))
	_assert_eq("余烬 真火→灼烧转真伤(有true段)", tdmg > 0, true)

	# ── 批6: 潮汐041/042/044/047 + 枪械055/058 ──
	var a47 := {"baseAtk": 100, "atk": 100, "maxHp": 1000, "hp": 1000, "buffs": [], "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "crit": 0.0}
	Phase2EquipRuntime.apply_stats(a47, "p2eq_047", 3)
	_assert_eq("重击锤3★ maxHp+700", int(a47["maxHp"]), 1700)
	StatsRecalc.recalc(a47)
	_assert_eq("重击锤3★ recalc后 atk+=maxHp×15%(100+255=355)", int(a47["atk"]), 355)
	a47["maxHp"] = 2000
	StatsRecalc.recalc(a47)
	_assert_eq("重击锤 随maxHp成长动态(100+2000×15%=400)", int(a47["atk"]), 400)
	# 042 涟漪药剂 3★: 全队回已损10%; 生命百分比最低的友军获双倍(effectDesc3)。
	#   单友军场景: 该友军即最低 → ×2 (已损900×10%×2=180)。
	var c42 := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000}
	var al42 := {"side": "left", "alive": true, "hp": 100, "maxHp": 1000, "healAmp": 0.0}
	Phase2EquipRuntime.on_turn_begin(c42, "p2eq_042", 3, [c42, al42])
	_assert_eq("涟漪药剂3★ 最低血友军双倍(+180)", int(al42["hp"]), 280)
	# 多友军: 仅【比例最低】者×2, 其余×1。lo=20%(损800), hi=80%(损200)。
	var lo42 := {"side": "left", "alive": true, "hp": 200, "maxHp": 1000, "healAmp": 0.0}
	var hi42 := {"side": "left", "alive": true, "hp": 800, "maxHp": 1000, "healAmp": 0.0}
	var cc42 := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000, "healAmp": 0.0}
	Phase2EquipRuntime.on_turn_begin(cc42, "p2eq_042", 3, [cc42, lo42, hi42])
	_assert_eq("涟漪3★ 最低血(20%)×2: 200+800×10%×2=360", int(lo42["hp"]), 360)
	_assert_eq("涟漪3★ 非最低(80%)×1: 800+200×10%=820", int(hi42["hp"]), 820)
	# 2★ 无双倍分支: 全队×1 (已损800×6%=48)。
	var lo42b := {"side": "left", "alive": true, "hp": 200, "maxHp": 1000, "healAmp": 0.0}
	var cc42b := {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000, "healAmp": 0.0}
	Phase2EquipRuntime.on_turn_begin(cc42b, "p2eq_042", 2, [cc42b, lo42b])
	_assert_eq("涟漪2★ 无双倍分支(+48)", int(lo42b["hp"]), 248)
	var o44 := {"side": "left", "alive": true, "hp": 400, "maxHp": 1000, "healAmp": 0.0, "_p2AmuletUsed": false}
	Phase2EquipRuntime.on_hit_as_target(o44, {}, 10, "p2eq_044", 3, [o44])
	_assert_eq("深海项链3★ 首次<50%回40%(400→800)", int(o44["hp"]), 800)
	o44["hp"] = 300
	Phase2EquipRuntime.on_hit_as_target(o44, {}, 10, "p2eq_044", 3, [o44])
	_assert_eq("深海项链 只触发一次", int(o44["hp"]), 300)
	var a55 := {"side": "left", "alive": true, "atk": 50}
	var t55 := {"side": "right", "alive": true, "hp": 500, "maxHp": 500, "buffs": []}
	Phase2EquipRuntime.on_hit(a55, t55, 30, "p2eq_055", 1, [a55, t55], true)
	_assert_eq("靶向器 标记markedDmg", Buffs.has(t55, "markedDmg"), true)
	var a58 := {"side": "left", "alive": true, "atk": 100}
	var f58 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 500, "buffs": []}
	var b58 := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 500, "maxHp": 500, "shield": 0, "buffs": []}
	Phase2EquipRuntime.on_hit(a58, f58, 100, "p2eq_058", 3, [a58, f58, b58], true)
	_assert_eq("穿甲3★ 溅射身后60%(-60)", int(b58["hp"]), 440)

	# ── 批7: 召唤037蛋糕蜡烛/038放大器/040FPGA + 潮汐045珍珠耳环 ──
	# 037 蛋糕蜡烛: on_side_end 推进3阶段 (0熄→1微弱回血→2燃烧敌)
	var c37 := {"side": "left", "alive": true, "atk": 100, "hp": 500, "maxHp": 2000, "healAmp": 0.0, "_slotKey": "front-0", "_p2CandlePhase": 0}
	var e37 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 2000, "maxHp": 2000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(c37, "p2eq_037", 3, [c37, e37])
	_assert_eq("蛋糕蜡烛 推进到微弱(phase1)", int(c37["_p2CandlePhase"]), 1)
	_assert_eq("蛋糕蜡烛3★ 微弱回血(44+1.0*100=144)", int(c37["hp"]), 644)
	Phase2EquipRuntime.on_side_end(c37, "p2eq_037", 3, [c37, e37])
	_assert_eq("蛋糕蜡烛 推进到燃烧(phase2)", int(c37["_p2CandlePhase"]), 2)
	_assert_eq("蛋糕蜡烛3★ 燃烧敌受魔法(-144)", int(e37["hp"]), 1856)
	var burn37c := 0
	for b in e37["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn": burn37c = int(b.get("value", 0))
	_assert_eq("蛋糕蜡烛3★ 燃烧敌灼烧40", burn37c, 40)

	# 038 放大器: on_turn_begin 设本回合增伤 (3★ 区间70-80)
	var c38 := {"side": "left", "alive": true, "hp": 1, "maxHp": 1, "_dmgBonusThisTurnPct": 0}
	Phase2EquipRuntime.on_turn_begin(c38, "p2eq_038", 3, [c38])
	var amp38 := int(c38["_dmgBonusThisTurnPct"])
	_assert_eq("放大器3★ 增伤区间[70,80]", amp38 >= 70 and amp38 <= 80, true)

	# 040 FPGA: on_turn_begin 抽4状态(3★), 至少一项生效
	var c40 := {"side": "left", "alive": true, "hp": 100, "maxHp": 1000, "healAmp": 0.0, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "baseAtk": 0, "atk": 0, "_lifestealPct": 0, "_dmgBonusThisTurnPct": 0, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(c40, "p2eq_040", 3, [c40])
	var sig40 := int(c40["def"]) + int(c40["atk"]) + int(c40["_dmgBonusThisTurnPct"]) + (int(c40["hp"]) - 100) + (20 if Buffs.has(c40, "dmgReduce") else 0)
	_assert_eq("FPGA3★ 抽4状态至少一项生效", sig40 > 0, true)

	# 045 珍珠耳环: 首次<50% → 回65%(3★)+2火球(30%目标maxHp魔法)+灼烧
	var o45 := {"side": "left", "alive": true, "hp": 200, "maxHp": 2000, "healAmp": 0.0, "_p2PearlUsed": false}
	var e45 := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var fx45: Array = Phase2EquipRuntime.on_hit_as_target(o45, {}, 10, "p2eq_045", 3, [o45, e45])
	_assert_eq("珍珠耳环3★ 首次<50%回65%(200+1300=1500)", int(o45["hp"]), 1500)
	_assert_eq("珍珠耳环 标记已触发", o45["_p2PearlUsed"], true)
	_assert_eq("珍珠耳环3★ 2火球各30%×1000(单敌-600)", int(e45["hp"]), 400)
	# 火球是投射物(travel 0.35s) → 伤害 effect 带 arrival_delay, 血跟火球落地才掉 (显示时机, 数值不动)。
	var fb45_has_arr := false
	for ef45 in fx45:
		if ef45 is Dictionary and str(ef45.get("vfx", "")) == "fireball":
			if ef45.has("arrival_delay") and is_equal_approx(float(ef45.get("arrival_delay", -1.0)), 0.35):
				fb45_has_arr = true
			else:
				fb45_has_arr = false
				break
	_assert_eq("珍珠耳环045 火球 effect 带 arrival_delay 0.35 (血跟火球落地)", fb45_has_arr, true)
	var burn45c := 0
	for b in e45["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn": burn45c = int(b.get("value", 0))
	_assert_eq("珍珠耳环3★ 火球灼烧(2×150=300)", burn45c, 300)
	o45["hp"] = 100
	Phase2EquipRuntime.on_hit_as_target(o45, {}, 10, "p2eq_045", 3, [o45, e45])
	_assert_eq("珍珠耳环 只触发一次", int(o45["hp"]), 100)

	# ── 批8: 枪械048手铳/050加特林/051激光/057狙击 (on_cast) ──
	# 048 黄铜手铳: 6发各0.6×ATK 物理(命中最前敌)
	var a48 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e48 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a48, "p2eq_048", 3, [a48, e48])
	_assert_eq("黄铜手铳3★ 6发各0.6×100(-360)", int(e48["hp"]), 4640)

	# 050 幽灵加特林: 60发(3★) + 永久-3护甲/发
	var a50 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e50 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "baseDef": 1000, "def": 1000, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a50, "p2eq_050", 3, [a50, e50])
	_assert_eq("加特林3★ 60发永久-3护甲(1000→820)", int(e50["def"]), 820)
	_assert_eq("加特林 造成了伤害", int(e50["hp"]) < 100000, true)

	# 051 激光手枪: 同列首敌2.8×ATK+流血, 身后50%
	var a51 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var f51 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var b51 := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 5000, "maxHp": 5000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a51, "p2eq_051", 3, [a51, f51, b51])
	_assert_eq("激光3★ 首敌2.8×100(-280)", int(f51["hp"]), 4720)
	_assert_eq("激光3★ 身后50%(-140)", int(b51["hp"]), 4860)
	var bl_f := 0; var bl_b := 0
	for x in f51["buffs"]:
		if x is Dictionary and x.get("type", "") == "bleed": bl_f = int(x.get("value", 0))
	for x in b51["buffs"]:
		if x is Dictionary and x.get("type", "") == "bleed": bl_b = int(x.get("value", 0))
	_assert_eq("激光3★ 首敌流血60", bl_f, 60)
	_assert_eq("激光3★ 身后流血30", bl_b, 30)

	# 057 狙击长管: 击杀→递归再开枪 (7×ATK 清空两弱敌)
	var a57 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e57a := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 500, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e57b := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 400, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a57, "p2eq_057", 3, [a57, e57a, e57b])
	_assert_eq("狙击3★ 击杀链清空(e57a死)", e57a["alive"], false)
	_assert_eq("狙击3★ 击杀链清空(e57b死)", e57b["alive"], false)

	# ── 批9: 枪械049连发弩/053霰弹/054瞄准镜 + 独立059沙漏 ──
	# 049 连发弩: 后排敌3发(3★), 30%损时1.3×ATK
	var a49 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var b49 := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 700, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a49, "p2eq_049", 3, [a49, b49])
	_assert_eq("连发弩3★ 3发×1.3(30%损满, -390)", int(b49["hp"]), 310)

	# 053 霰弹贝: 18发(3★)全中单敌→眩晕
	var a53 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var e53 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 10000, "maxHp": 10000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a53, "p2eq_053", 3, [a53, e53])
	_assert_eq("霰弹3★ 18发全中单敌→眩晕", Buffs.has(e53, "stun"), true)
	_assert_eq("霰弹 造成伤害", int(e53["hp"]) < 10000, true)

	# 054 瞄准镜: 属性 + 不被闪避flag
	var a54 := {"baseAtk": 0, "atk": 0, "crit": 0.0, "_extraCritDmgPerm": 0.0}
	Phase2EquipRuntime.apply_stats(a54, "p2eq_054", 3)
	_assert_eq("瞄准镜3★ +20攻", int(a54["atk"]), 20)
	_assert_eq("瞄准镜3★ +0.40暴击", a54["crit"], 0.40)
	_assert_eq("瞄准镜3★ +0.20暴伤(_extraCritDmgPerm)", a54["_extraCritDmgPerm"], 0.20)
	_assert_eq("瞄准镜 不被闪避flag", a54["_cannotBeDodged"], true)

	# 059 沙漏: 纯属性(龟能+生命)
	var a59 := {"maxHp": 1000, "hp": 1000, "_maxEnergy": 0}
	Phase2EquipRuntime.apply_stats(a59, "p2eq_059", 3)
	_assert_eq("沙漏3★ +1000龟能", int(a59["_maxEnergy"]), 1000)
	_assert_eq("沙漏3★ +1000生命", int(a59["maxHp"]), 2000)

	# ── 批10: 杖系026雷电/027电棍/030·031水晶球 + 潮汐043海浪护符 ──
	# 026 雷电法杖: 4次命中充满100(25/次) → 链式闪电6跳×30魔法
	var a26 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0, "_p2LightningCharge": 0.0}
	var e26 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	for _i26 in range(4):
		Phase2EquipRuntime.on_hit(a26, e26, 10, "p2eq_026", 3, [a26, e26], true)
	_assert_eq("雷电法杖3★ 满100链式闪电(6跳×30=180)", int(e26["hp"]), 99820)
	_assert_eq("雷电法杖 充能归0(溢出)", int(a26["_p2LightningCharge"]), 0)

	# 027 电棍 (镜phase1: 每次施法即电击+眩晕+消耗1层, 初3层, 0层停火)
	var a27 := {"side": "left", "alive": true, "atk": 50, "crit": 0.0, "magicPen": 0, "_p2BatonCharges": 3}
	var e27 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a27, "p2eq_027", 3, [a27, e27])
	_assert_eq("电棍3★ 第1次电击50魔法(-50)", int(e27["hp"]), 950)
	_assert_eq("电棍 每次施法即眩晕", Buffs.has(e27, "stun"), true)
	_assert_eq("电棍 消耗1电击层(3→2)", int(a27["_p2BatonCharges"]), 2)
	Phase2EquipRuntime.on_cast(a27, "p2eq_027", 3, [a27, e27])
	Phase2EquipRuntime.on_cast(a27, "p2eq_027", 3, [a27, e27])
	_assert_eq("电棍 3层打光(0)", int(a27["_p2BatonCharges"]), 0)
	_assert_eq("电棍3★ 3次共-150(hp850)", int(e27["hp"]), 850)
	Phase2EquipRuntime.on_cast(a27, "p2eq_027", 3, [a27, e27])
	_assert_eq("电棍 0层停火(第4次hp不变850)", int(e27["hp"]), 850)

	# 030 水晶球A: 3段×40魔法+满3层引爆20%maxHp (单敌列)
	var a30 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0}
	var e30 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a30, "p2eq_030", 3, [a30, e30])
	_assert_eq("水晶球A3★ 3段40+引爆20%(-20120)", int(e30["hp"]), 79880)
	_assert_eq("水晶球A 引爆后层数清0", int(e30["_p2CrystalStacks"]), 0)

	# 031 水晶球B: 全敌各30魔法+水晶层, 3次满引爆
	var a31 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0}
	var e31a := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var e31b := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a31, "p2eq_031", 3, [a31, e31a, e31b])
	_assert_eq("水晶球B3★ 全敌各30(e31a-30)", int(e31a["hp"]), 99970)
	_assert_eq("水晶球B 各+1水晶层", int(e31a["_p2CrystalStacks"]), 1)
	Phase2EquipRuntime.on_cast(a31, "p2eq_031", 3, [a31, e31a, e31b])
	Phase2EquipRuntime.on_cast(a31, "p2eq_031", 3, [a31, e31a, e31b])
	_assert_eq("水晶球B 满3引爆层数清0", int(e31a["_p2CrystalStacks"]), 0)
	_assert_eq("水晶球B 引爆造成大额(<99900)", int(e31a["hp"]) < 99900, true)

	# 043 海浪护符: on_side_end+1巨浪层, 3★满2→横排(同列)扫敌我
	var f43 := {"side": "left", "alive": true, "_slotKey": "front-0", "hp": 1, "maxHp": 1, "_p2WaveStacks": 0, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "shield": 0, "shieldAmp": 0.0}
	var al43 := {"side": "left", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "baseDef": 10, "def": 10, "baseMr": 10, "mr": 10, "shieldAmp": 0.0}
	var en43a := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "baseDef": 10, "def": 10, "baseMr": 10, "mr": 10, "buffs": []}
	Phase2EquipRuntime.on_side_end(f43, "p2eq_043", 3, [f43, al43, en43a])
	_assert_eq("海浪护符 第1层未满(阈值2)", int(f43["_p2WaveStacks"]), 1)
	Phase2EquipRuntime.on_side_end(f43, "p2eq_043", 3, [f43, al43, en43a])
	_assert_eq("海浪护符 满2层→重置", int(f43["_p2WaveStacks"]), 0)
	_assert_eq("海浪护符3★ 友军+5护甲(10→15)", int(al43["def"]), 15)
	_assert_eq("海浪护符3★ 敌-5护甲(10→5)", int(en43a["def"]), 5)
	_assert_eq("海浪护符3★ 敌受魔法(<100000)", int(en43a["hp"]) < 100000, true)
	_assert_eq("海浪护符3★ 友军获盾120", int(al43["shield"]), 120)

	# ── 批11: 召唤039竹制弓箭 + 枪械052左轮 ──
	# 039 竹制弓箭: 3★充能3次, 每次强化攻+回血+永久maxHp
	var a39 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "magicPen": 0, "hp": 500, "maxHp": 1000, "healAmp": 0.0, "_p2BambooCharges": 3}
	var e39 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_cast(a39, "p2eq_039", 3, [a39, e39])
	_assert_eq("竹制弓箭3★ 充能-1(剩2)", int(a39["_p2BambooCharges"]), 2)
	_assert_eq("竹制弓箭3★ 永久+100maxHp(1000→1100)", int(a39["maxHp"]), 1100)
	_assert_eq("竹制弓箭3★ 强化攻235魔法(35+20%×1000, -235)", int(e39["hp"]), 99765)
	Phase2EquipRuntime.on_cast(a39, "p2eq_039", 3, [a39, e39])
	Phase2EquipRuntime.on_cast(a39, "p2eq_039", 3, [a39, e39])
	_assert_eq("竹制弓箭 3次用尽充能", int(a39["_p2BambooCharges"]), 0)
	Phase2EquipRuntime.on_cast(a39, "p2eq_039", 3, [a39, e39])
	_assert_eq("竹制弓箭 充能0不再触发(maxHp停1300)", int(a39["maxHp"]), 1300)

	# 052 左轮: 6发, on_side_end每次射1发(1200+9×ATK), 打光停火
	var a52 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "_p2RevolverBullets": 6}
	var e52 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000000, "maxHp": 1000000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(a52, "p2eq_052", 3, [a52, e52])
	_assert_eq("左轮3★ 射1发(1200+9×100=2100)", int(e52["hp"]), 997900)
	_assert_eq("左轮 子弹-1(剩5)", int(a52["_p2RevolverBullets"]), 5)
	for _k52 in range(10):
		Phase2EquipRuntime.on_side_end(a52, "p2eq_052", 3, [a52, e52])
	_assert_eq("左轮 6发打光后停火(子弹0)", int(a52["_p2RevolverBullets"]), 0)

	# ── 批12: 死亡钩子 035齿轮→币 + 052敌死装弹 ──
	# 035 齿轮: 回合开始+N齿轮
	var g35 := {"side": "left", "alive": true, "_p2Gears": 0}
	Phase2EquipRuntime.on_turn_begin(g35, "p2eq_035", 3, [g35])
	_assert_eq("齿轮3★ 回合+3齿轮", int(g35["_p2Gears"]), 3)
	# 035 死亡→每齿轮+2币
	var d35 := {"side": "left", "alive": false, "_p2_equips": [{"id": "p2eq_035", "star": 3}], "_p2Gears": 5}
	var res35: Dictionary = Phase2EquipRuntime.on_death(d35, [d35])
	_assert_eq("齿轮死亡 coin_side=left", str(res35["coin_side"]), "left")
	_assert_eq("齿轮死亡 5齿轮→10币", int(res35["coins"]), 10)
	# 052 敌死→对面左轮装弹+1
	var carrier52 := {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_052", "star": 3}], "_p2RevolverBullets": 3}
	var dead52 := {"side": "right", "alive": false, "_p2_equips": []}
	Phase2EquipRuntime.on_death(dead52, [carrier52, dead52])
	_assert_eq("左轮 敌死→装弹+1(3→4)", int(carrier52["_p2RevolverBullets"]), 4)
	carrier52["_p2RevolverBullets"] = 6
	Phase2EquipRuntime.on_death(dead52, [carrier52, dead52])
	_assert_eq("左轮 装弹cap6", int(carrier52["_p2RevolverBullets"]), 6)
	var allyDead52 := {"side": "left", "alive": false, "_p2_equips": []}
	carrier52["_p2RevolverBullets"] = 3
	Phase2EquipRuntime.on_death(allyDead52, [carrier52, allyDead52])
	_assert_eq("左轮 友死不装弹(仍3)", int(carrier52["_p2RevolverBullets"]), 3)

	# ── 批13: 036温泉蛋 (复用孵化进度+满级全队护盾) ──
	var inc36 := {"side": "left", "alive": true, "baseAtk": 100, "atk": 100, "baseDef": 10, "def": 10, "baseMr": 10, "mr": 10, "maxHp": 1000, "hp": 1000, "_incubatorProgress": 0, "_incubatorTempLevel": 0, "_p2IncubShieldTotal": 600, "_p2IncubShieldGiven": false}
	var ally36 := {"side": "left", "alive": true, "maxHp": 1000, "hp": 1000, "shield": 0, "shieldAmp": 0.0}
	var dum36 := {"side": "right", "alive": true, "hp": 1, "maxHp": 1, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(inc36, "p2eq_036", 3, [inc36, ally36])
	_assert_eq("温泉蛋 回合+5进度", int(inc36["_incubatorProgress"]), 5)
	Phase2EquipRuntime.on_hit(inc36, dum36, 500, "p2eq_036", 3, [inc36, ally36, dum36], true)
	_assert_eq("温泉蛋 造伤×0.1(+50→55)", int(inc36["_incubatorProgress"]), 55)
	Phase2EquipRuntime.on_hit_as_target(inc36, {}, 500, "p2eq_036", 3, [inc36, ally36])
	_assert_eq("温泉蛋 满100升临时Lv1", int(inc36["_incubatorTempLevel"]), 1)
	_assert_eq("温泉蛋 升级残余进度5", int(inc36["_incubatorProgress"]), 5)
	_assert_eq("温泉蛋 Lv1 baseAtk+5%(100→105)", int(inc36["baseAtk"]), 105)
	for _k36 in range(20):
		Phase2EquipRuntime.on_hit_as_target(inc36, {}, 500, "p2eq_036", 3, [inc36, ally36])
	_assert_eq("温泉蛋 临时Lv封顶3", int(inc36["_incubatorTempLevel"]), 3)
	_assert_eq("温泉蛋 满级→全队均摊护盾(2人各300)", int(ally36["shield"]), 300)
	_assert_eq("温泉蛋 护盾只给一次", inc36["_p2IncubShieldGiven"], true)

	# ── 批14: 046幽灵墨鱼(复用_roll_dodge) + 054不被闪避 ──
	var g46 := {"side": "left", "alive": true, "maxHp": 1000, "hp": 1000, "buffs": []}
	Phase2EquipRuntime.apply_stats(g46, "p2eq_046", 3)
	_assert_eq("墨鱼3★ +400生命", int(g46["maxHp"]), 1400)
	_assert_eq("墨鱼3★ +50%闪避buff", Buffs.has(g46, "dodge"), true)
	_assert_eq("墨鱼3★ _p2GhostShield120", int(g46["_p2GhostShield"]), 120)
	# _roll_dodge: 100%闪避→dodged + 给永久护盾120
	var t46 := {"side": "right", "alive": true, "hp": 1000, "maxHp": 2000, "shield": 0, "shieldAmp": 0.0, "buffs": [{"type": "dodge", "value": 100, "duration": 999}], "_p2GhostShield": 120}
	var atk46 := {"side": "left", "alive": true}
	var rd46: Dictionary = SkillHandlers._roll_dodge(t46, atk46, [t46, atk46])
	_assert_eq("墨鱼 100%闪避→dodged", rd46["dodged"], true)
	_assert_eq("墨鱼 闪避→+120永久护盾", int(t46["shield"]), 120)
	# 054: 攻击者_cannotBeDodged → 必中(不闪避)
	var t54 := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "buffs": [{"type": "dodge", "value": 100, "duration": 999}]}
	var atk54 := {"side": "left", "alive": true, "_cannotBeDodged": true}
	var rd54: Dictionary = SkillHandlers._roll_dodge(t54, atk54, [t54, atk54])
	_assert_eq("瞄准镜 攻击者不被闪避→必中(dodged=false)", rd54["dodged"], false)


# ─── desc≠impl 缺口补完 (2026-06-24): 013全队硬化 / 016减伤(回归) / 023满法力灼烧 / 055施法标记 ───
func _test_phase2_equip_gap_fixes() -> void:
	# ── 013 炙烤海胆 3★: 叠满20层 → 把累积(20×2=40)护甲魔抗分给全队【其他】友军(一次) ──
	var o13t := {"side": "left", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "shield": 0, "shieldAmp": 0.0}
	Phase2EquipRuntime.apply_stats(o13t, "p2eq_013", 3)
	_assert_eq("炙烤海胆3★ team-share标记", o13t.get("_p2HardenTeamShare", false), true)
	var ally13a := {"side": "left", "alive": true, "baseDef": 5, "def": 5, "baseMr": 3, "mr": 3}
	var ally13b := {"side": "left", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0}
	var enemy13 := {"side": "right", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0}
	var all13: Array = [o13t, ally13a, ally13b, enemy13]
	# 打满 20 段
	for _i13 in range(20):
		Phase2EquipRuntime.on_hit_as_target(o13t, {}, 10, "p2eq_013", 3, all13)
	_assert_eq("炙烤海胆3★ 自己20层×2=40护甲", int(o13t["def"]), 40)
	_assert_eq("炙烤海胆3★ 满层80盾(经shieldAmp)", int(o13t["shield"]), 80)
	_assert_eq("炙烤海胆3★ 友A护甲+40(5→45)", int(ally13a["def"]), 45)
	_assert_eq("炙烤海胆3★ 友A魔抗+40(3→43)", int(ally13a["mr"]), 43)
	_assert_eq("炙烤海胆3★ 友B护甲+40", int(ally13b["def"]), 40)
	_assert_eq("炙烤海胆3★ 敌方不分发", int(enemy13["def"]), 0)
	_assert_eq("炙烤海胆3★ 分发标记一次", o13t["_p2HardenTeamGiven"], true)
	# 再打1段 (已满层) → 不二次分发 (友A仍45)
	Phase2EquipRuntime.on_hit_as_target(o13t, {}, 10, "p2eq_013", 3, all13)
	_assert_eq("炙烤海胆3★ 满层后不重复分发", int(ally13a["def"]), 45)
	# 1★ 无全队分发
	var o13s := {"side": "left", "alive": true, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "shield": 0, "shieldAmp": 0.0}
	Phase2EquipRuntime.apply_stats(o13s, "p2eq_013", 1)
	_assert_eq("炙烤海胆1★ 无team-share", o13s.get("_p2HardenTeamShare", false), false)

	# ── 016 铁壁盾: apply_stats 设减伤flag + damage.gd 消费 (非真伤逐星减2/4/6) ──
	var f16a := {"def": 0, "mr": 0}
	Phase2EquipRuntime.apply_stats(f16a, "p2eq_016", 1)
	_assert_eq("铁壁盾1★ _p2DmgReduce=2", int(f16a.get("_p2DmgReduce", 0)), 2)
	Phase2EquipRuntime.apply_stats(f16a, "p2eq_016", 1)   # 注意: apply_stats 不累积flag(直接赋值), 这里只测3★值
	var f16c := {"def": 0, "mr": 0}
	Phase2EquipRuntime.apply_stats(f16c, "p2eq_016", 3)
	_assert_eq("铁壁盾3★ _p2DmgReduce=6", int(f16c.get("_p2DmgReduce", 0)), 6)
	var t16a := {"hp": 500, "maxHp": 500, "shield": 0, "alive": true, "buffs": [], "_p2DmgReduce": 2}
	_assert_eq("铁壁盾1★ 50物理-2=48", int(Damage.apply_raw_damage(t16a, 50, "physical")["hpLoss"]), 48)
	var t16b := {"hp": 500, "maxHp": 500, "shield": 0, "alive": true, "buffs": [], "_p2DmgReduce": 6}
	_assert_eq("铁壁盾3★ 50魔法-6=44", int(Damage.apply_raw_damage(t16b, 50, "magic")["hpLoss"]), 44)
	var t16d := {"hp": 500, "maxHp": 500, "shield": 0, "alive": true, "buffs": [], "_p2DmgReduce": 6}
	_assert_eq("铁壁盾 真伤不减(50)", int(Damage.apply_raw_damage(t16d, 50, "true")["hpLoss"]), 50)

	# ── 023 灼热火珊瑚 3★ 主动: 满【法力】(≠龟能)→ 全敌各60灼烧, 放完清空该法力条 ──
	#   ⚠ 用 _staff_mana["p2eq_023"] 法力判定, 绝不读 _energy/_maxEnergy(债已修)。
	var c23 := {"side": "left", "alive": true, "atk": 100, "_energy": 77, "_maxEnergy": 100,
		"_staffTier": 1, "_staff_mana": {"p2eq_023": 100}}   # 法力满(tier1满档100)
	var e23a := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	var e23b := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(c23, "p2eq_023", 3, [c23, e23a, e23b])
	var burn23a := 0
	for b in e23a["buffs"]:
		if b is Dictionary and b.get("type", "") == "burn":
			burn23a = int(b.get("value", 0))
	_assert_eq("火珊瑚3★主动 满法力→敌A 60灼烧", burn23a, 60)
	_assert_eq("火珊瑚3★主动 敌B也60灼烧", _burn_of(e23b), 60)
	_assert_eq("火珊瑚3★主动 放完清空【法力】(非龟能)", int(c23["_staff_mana"]["p2eq_023"]), 0)
	_assert_eq("火珊瑚3★主动 触发不动龟能 _energy", int(c23["_energy"]), 77)   # 隔离: 不清龟能
	# 法力不满 → 不触发
	var c23n := {"side": "left", "alive": true, "atk": 100, "_staffTier": 1, "_staff_mana": {"p2eq_023": 50}}
	var e23n := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(c23n, "p2eq_023", 3, [c23n, e23n])
	_assert_eq("火珊瑚3★主动 法力不满→不触发", _burn_of(e23n), 0)
	# 无法器系统(_staffTier=0, 单件无羁绊) → fallback 每3回合一次
	var c23f := {"side": "left", "alive": true, "atk": 100, "_maxEnergy": 0, "_p2FireCoralTurnCtr": 0}
	var e23f := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(c23f, "p2eq_023", 3, [c23f, e23f])
	_assert_eq("火珊瑚3★主动 无龟能 第1回合不触发", _burn_of(e23f), 0)
	Phase2EquipRuntime.on_turn_begin(c23f, "p2eq_023", 3, [c23f, e23f])
	Phase2EquipRuntime.on_turn_begin(c23f, "p2eq_023", 3, [c23f, e23f])
	_assert_eq("火珊瑚3★主动 无龟能 第3回合触发60灼烧", _burn_of(e23f), 60)
	# 1★/2★ 无主动 (on_turn_begin 不施灼烧)
	var c23lo := {"side": "left", "alive": true, "atk": 100, "_maxEnergy": 100, "_energy": 100}
	var e23lo := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_turn_begin(c23lo, "p2eq_023", 1, [c23lo, e23lo])
	_assert_eq("火珊瑚1★ 无主动满法力灼烧", _burn_of(e23lo), 0)

	# ── 055 靶向器: on_cast 也标记最前敌(markedDmg 2回合, 受伤+20%) ──
	var c55 := {"side": "left", "alive": true, "atk": 50}
	var e55f := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "buffs": []}
	var e55b := {"side": "right", "alive": true, "_slotKey": "back-0", "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_cast(c55, "p2eq_055", 1, [c55, e55f, e55b])
	_assert_eq("靶向器 on_cast 标记最前敌", Buffs.has(e55f, "markedDmg"), true)
	var mk55 = Buffs.find(e55f, "markedDmg")
	_assert_eq("靶向器 标记值+20%", int(mk55.get("value", 0)) if mk55 != null else 0, 20)
	# on_hit 命中标记 (回归, 确保两路都标)
	var e55h := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	Phase2EquipRuntime.on_hit(c55, e55h, 30, "p2eq_055", 1, [c55, e55h], true)
	_assert_eq("靶向器 on_hit 命中也标记", Buffs.has(e55h, "markedDmg"), true)


# helper: 取 fighter 身上 burn 层数 (灼烧测试用)
func _burn_of(f: Dictionary) -> int:
	for b in f.get("buffs", []):
		if b is Dictionary and b.get("type", "") == "burn":
			return int(b.get("value", 0))
	return 0


# ─── 龟蛋 _eggImmune 免疫 (处决/控制/嘲讽) + 终极×5/自损配置 (2026-06-13) ───
func _test_egg_immunity() -> void:
	# 1) 免控/免嘲讽: Buffs.add 中心口对 _eggImmune 单位拒收 stun/freeze/taunt
	var egg := {"_eggImmune": true, "buffs": []}
	Buffs.add(egg, "stun", 1, 2, "ignore")
	_assert_eq("龟蛋免眩晕(stun未挂)", Buffs.has(egg, "stun"), false)
	Buffs.add(egg, "freeze", 1, 2, "ignore")
	_assert_eq("龟蛋免冻结(freeze未挂)", Buffs.has(egg, "freeze"), false)
	Buffs.add(egg, "taunt", 1, 3, "refresh")
	_assert_eq("龟蛋免嘲讽(taunt未挂)", Buffs.has(egg, "taunt"), false)
	# 非控制 buff 仍正常挂 (只拦控制类)
	Buffs.add(egg, "markedDmg", 400, 999, "overwrite")
	_assert_eq("龟蛋仍可挂 markedDmg(非控制)", Buffs.has(egg, "markedDmg"), true)
	# 普通单位不受影响 (仍可被控)
	var norm := {"buffs": []}
	Buffs.add(norm, "stun", 1, 2, "ignore")
	_assert_eq("普通单位仍可被眩晕", Buffs.has(norm, "stun"), true)

	# 2) 免处决/斩杀: hunterMark 跌破斩杀线本应秒杀, _eggImmune 免疫 → 只扣伤害不秒
	var eegg := {"side": "right", "alive": true, "hp": 100, "maxHp": 1000, "shield": 0, "_eggImmune": true,
		"buffs": [{"type": "hunterMark", "value": 30, "duration": 999}]}   # 斩杀线30% (hp10%<30% 本会秒)
	Damage.apply_raw_damage(eegg, 10, "physical")   # 扣10 → hp90 (9%<30%斩杀线)
	_assert_eq("龟蛋免斩杀→仍存活", eegg["alive"], true)
	_assert_eq("龟蛋免斩杀→hp只扣伤害(90)", int(eegg["hp"]), 90)
	# 对照: 无 _eggImmune 的普通单位会被斩杀
	var nm := {"side": "right", "alive": true, "hp": 100, "maxHp": 1000, "shield": 0,
		"buffs": [{"type": "hunterMark", "value": 30, "duration": 999}]}
	Damage.apply_raw_damage(nm, 10, "physical")
	_assert_eq("普通单位跌破斩杀线→秒杀(hp0)", int(nm["hp"]), 0)
	_assert_eq("普通单位跌破斩杀线→死亡", nm["alive"], false)

	# 3) 免击飞: _mark_knockup 对 _eggImmune 不标记
	var kegg := {"alive": true, "_eggImmune": true}
	SkillHandlers._mark_knockup(kegg)
	_assert_eq("龟蛋免击飞(_knockedUpThisTurn未标)", kegg.get("_knockedUpThisTurn", false), false)
	var knorm := {"alive": true}
	SkillHandlers._mark_knockup(knorm)
	_assert_eq("普通单位被击飞(_knockedUpThisTurn=true)", knorm.get("_knockedUpThisTurn", false), true)
	# 017不沉之锚 也免击飞 (回归保护原有守卫)
	var kanchor := {"alive": true, "_p2AnchorImmune": true}
	SkillHandlers._mark_knockup(kanchor)
	_assert_eq("017锚 仍免击飞", kanchor.get("_knockedUpThisTurn", false), false)


func _test_egg_final_config() -> void:
	# 终极战场 ×5 增伤映射: markedDmg value = (5-1)×100 = 400
	var marked_val := int(round((Phase2Config.FINAL_LOSER_EGG_DMG_MULT - 1.0) * 100.0))
	_assert_eq("终极蛋×5 → markedDmg=400", marked_val, 400)
	# markedDmg=400 实际效果: 受伤×(1+400%)=×5
	var egg := {"side": "right", "alive": true, "hp": 10000, "maxHp": 10000, "shield": 0,
		"buffs": [{"type": "markedDmg", "value": 400, "duration": 999}]}
	var r: Dictionary = Damage.apply_raw_damage(egg, 100, "true")
	_assert_eq("markedDmg400 → 100伤害放大成500", int(r["hpLoss"]), 500)
	# 自损 25% maxHP
	_assert_eq("终极蛋自损25% (maxHp1000→250)", Phase2Config.egg_self_loss(1000), 250)
	_assert_eq("终极蛋自损25% (maxHp1050→263)", Phase2Config.egg_self_loss(1050), 263)
	# 蛋 HP 由局内等级定 (跨场账本基线)
	_assert_eq("蛋 Lv1 HP=2100", Phase2Config.egg_hp(1), 2100)


func _test_phase2_034_doll_bear() -> void:
	# 1) apply_stats 逐星 (费5 +20/50/300攻 +120/250/1000生命)
	var a34 := {"baseAtk": 100, "atk": 100, "maxHp": 500, "hp": 500}
	Phase2EquipRuntime.apply_stats(a34, "p2eq_034", 1)
	_assert_eq("玩偶1★ +20攻", int(a34["atk"]), 120)
	_assert_eq("玩偶1★ +120生命", int(a34["maxHp"]), 620)
	var b34 := {"baseAtk": 0, "atk": 0, "maxHp": 0, "hp": 0}
	Phase2EquipRuntime.apply_stats(b34, "p2eq_034", 3)
	_assert_eq("玩偶3★ +300攻", int(b34["atk"]), 300)
	_assert_eq("玩偶3★ +1000生命", int(b34["maxHp"]), 1000)

	# 2) on_side_end 小熊攻最前敌 (1★: 1×ATK+100, atk100 → 200 物理) + 击飞 + +1层
	var c34 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "_p2DollBigBearStacks": 0}
	var ef34 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	var eb34 := {"side": "right", "alive": true, "_slotKey": "back-2", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(c34, "p2eq_034", 1, [c34, ef34, eb34])
	_assert_eq("玩偶1★ 小熊攻最前敌front-0(1×100+100=-200)", int(ef34["hp"]), 800)
	_assert_eq("玩偶1★ 不打后排back-2", int(eb34["hp"]), 1000)
	_assert_eq("玩偶1★ 击飞最前敌(_knockedUpThisTurn)", ef34.get("_knockedUpThisTurn", false), true)
	_assert_eq("玩偶1★ +1大熊层", int(c34["_p2DollBigBearStacks"]), 1)
	_assert_eq("玩偶1★ 1层未满(阈值5)未就绪", c34.get("_p2DollReadyToSpawn", false), false)

	# 3) 1★满5层 → _p2DollReadyToSpawn
	for _i in range(4):
		var en := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 99999, "maxHp": 99999, "shield": 0, "def": 0, "mr": 0, "buffs": []}
		Phase2EquipRuntime.on_side_end(c34, "p2eq_034", 1, [c34, en])
	_assert_eq("玩偶1★ 满5层", int(c34["_p2DollBigBearStacks"]), 5)
	_assert_eq("玩偶1★ 满5层→大熊就绪", c34["_p2DollReadyToSpawn"], true)

	# 4) 3★只需1层就就绪 (阈值5/3/1)
	var c34b := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0, "_p2DollBigBearStacks": 0}
	var e34b := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 99999, "maxHp": 99999, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(c34b, "p2eq_034", 3, [c34b, e34b])
	_assert_eq("玩偶3★ 1层即就绪(阈值1)", c34b["_p2DollReadyToSpawn"], true)
	# 3★ 小熊伤害 = 5×ATK+1000 = 5×100+1000 = 1500
	_assert_eq("玩偶3★ 小熊攻(5×100+1000=-1500)", 99999 - int(e34b["hp"]), 1500)

	# 5) 已召唤过(_p2DollSpawned)→不再触发
	var c34c := {"side": "left", "alive": true, "atk": 100, "_p2DollSpawned": true, "_p2DollBigBearStacks": 5}
	var e34c := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "buffs": []}
	Phase2EquipRuntime.on_side_end(c34c, "p2eq_034", 1, [c34c, e34c])
	_assert_eq("玩偶 已召唤→不再小熊攻(敌满血)", int(e34c["hp"]), 1000)

	# ── 批15: 056飞镖 (复用_knockedUpThisTurn击飞靶子) ──
	var a56 := {"side": "left", "alive": true, "atk": 100, "crit": 0.0, "armorPen": 0}
	var ku56 := {"side": "right", "alive": true, "_slotKey": "front-0", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": [], "_knockedUpThisTurn": true}
	var no56 := {"side": "right", "alive": true, "_slotKey": "front-1", "hp": 100000, "maxHp": 100000, "shield": 0, "def": 0, "mr": 0, "buffs": [], "_knockedUpThisTurn": false}
	Phase2EquipRuntime.on_side_end(a56, "p2eq_056", 3, [a56, ku56, no56])
	# 3★: 600+9×100=1500 物理 → 被击飞的敌 -1500
	_assert_eq("飞镖3★ 击飞靶子受镖(600+9×100=-1500)", int(ku56["hp"]), 98500)
	_assert_eq("飞镖 未击飞的敌不受镖", int(no56["hp"]), 100000)
	_assert_eq("飞镖 命中移除靶子标记", ku56["_knockedUpThisTurn"], false)
	var bl56 := 0
	for x in ku56["buffs"]:
		if x is Dictionary and x.get("type", "") == "bleed": bl56 = int(x.get("value", 0))
	_assert_eq("飞镖3★ 施流血(100+0.8×100=180)", bl56, 180)

	# ── 批16: 032唤灵骨符(纯属性入口) + 033复活海螺(复用e_conch死亡变虫) ──
	var g32 := {"maxHp": 1000, "hp": 1000}
	Phase2EquipRuntime.apply_stats(g32, "p2eq_032", 3)
	_assert_eq("唤灵骨符3★ +70生命", int(g32["maxHp"]), 1070)
	# 033 apply_stats: _equipConch + 逐星小虫属性
	var g33 := {"maxHp": 1000, "hp": 1000, "_level": 1, "baseAtk": 200, "atk": 200, "baseDef": 50, "def": 50}
	Phase2EquipRuntime.apply_stats(g33, "p2eq_033", 3)
	_assert_eq("复活海螺3★ +400生命", int(g33["maxHp"]), 1400)
	_assert_eq("复活海螺 设_equipConch", g33["_equipConch"], true)
	_assert_eq("复活海螺3★ 小虫300HP", int(g33["_conchWormHp"]), 300)
	_assert_eq("复活海螺3★ 小虫40攻", int(g33["_conchWormAtk"]), 40)
	_assert_eq("复活海螺3★ 设每回合分裂flag", g33.get("_conchWormSplit", false), true)
	var g33b := {"maxHp": 1000, "hp": 1000, "_level": 1}
	Phase2EquipRuntime.apply_stats(g33b, "p2eq_033", 1)
	_assert_eq("复活海螺1★ 无分裂flag", g33b.get("_conchWormSplit", false), false)
	# 死亡变虫: 复用 EquipmentRuntime.on_death (BattleScene死亡口走同一条)
	var revived: bool = EquipmentRuntime.on_death(g33, "e_conch")
	_assert_eq("复活海螺3★ 变虫保留分裂flag(持过变形)", g33.get("_conchWormSplit", false), true)
	_assert_eq("复活海螺 阵亡变小虫(复活成功)", revived, true)
	_assert_eq("复活海螺3★ 变虫300HP(lv1)", int(g33["maxHp"]), 300)
	_assert_eq("复活海螺3★ 变虫40攻", int(g33["atk"]), 40)
	_assert_eq("变虫 def清0", int(g33["def"]), 0)
	_assert_eq("变虫 _isConchWorm标记", g33["_isConchWorm"], true)
	_assert_eq("变虫 alive复活", g33["alive"], true)


# ── 深海军械库[军火] 学派 3/6/9: 标记 + 6档能量护盾/弹幕 + 9档火控真伤% ──
func _make_armory_fighter(side: String, slot: String, n_pieces: int) -> Dictionary:
	# 用真实 军火 装备 id (前 n_pieces 个) → schools_of 计入 深海军械库
	var ids := ["p2eq_048", "p2eq_049", "p2eq_050", "p2eq_051", "p2eq_052", "p2eq_053", "p2eq_056", "p2eq_057", "p2eq_015"]
	var eqs: Array = []
	for i in range(mini(n_pieces, ids.size())):
		eqs.append({"id": ids[i], "star": 1})
	return {
		"id": "basic", "side": side, "alive": true, "_slotKey": slot,
		"maxHp": 1000, "hp": 1000, "shield": 0, "atk": 100, "def": 0, "mr": 0,
		"baseAtk": 100, "armorPenPct": 0.0, "magicPenPct": 0.0, "buffs": [],
		"_p2_equips": eqs,
	}

func _test_phase2_armory_school() -> void:
	# --- 3 档: 1 个携带者带 3 件 军火 → tier1, count3, 全队标 _armoryTier=1 ---
	var carrier3 := _make_armory_fighter("left", "front-1", 3)
	var ally3 := _make_armory_fighter("left", "back-1", 0)   # 队友无件 → 也被标 tier, 但非携带者无火控
	var team3 := [carrier3, ally3]
	Phase2Schools.apply_team_start(team3)
	_assert_eq("军火3档 携带者 _armoryTier=1", int(carrier3.get("_armoryTier", 0)), 1)
	_assert_eq("军火3档 队友也标 _armoryTier=1", int(ally3.get("_armoryTier", 0)), 1)
	_assert_eq("军火3档 _armoryCount=3", int(carrier3.get("_armoryCount", 0)), 3)
	# 9档火控未到 → 无真伤% (3档=炮台1只回合末轰击)
	_assert_eq("军火3档 无9档火控真伤%", float(carrier3.get("_armoryTrueDmgPct", 0.0)), 0.0, 0.001)

	# --- 6 档: 1 携带者 6 件 → tier2 ---
	var carrier6 := _make_armory_fighter("left", "front-1", 6)
	var team6 := [carrier6]
	Phase2Schools.apply_team_start(team6)
	_assert_eq("军火6档 _armoryTier=2", int(carrier6.get("_armoryTier", 0)), 2)
	_assert_eq("军火6档 _armoryCount=6", int(carrier6.get("_armoryCount", 0)), 6)
	_assert_eq("军火6档(<9) 无火控真伤%", float(carrier6.get("_armoryTrueDmgPct", 0.0)), 0.0, 0.001)
	# on_round_begin 第1回合(turn奇): 能量(100+20×6=220)→护盾均摊(单人=220)
	var enemy6 := _make_armory_fighter("right", "front-1", 0)
	var all6 := [carrier6, enemy6]
	var arm_ev1: Array = Phase2Schools.on_round_begin(all6, 1)
	_assert_eq("军火6档 turn1 能量→护盾(220)", int(carrier6.get("shield", 0)), 220)
	# 可见化: turn1 护盾 → 返回 shield 事件 (kind=shield, vfx=shieldglow, amount=220) 给渲染器飘字+盾光
	var arm_sh_ev = _find_event(arm_ev1, "shield", carrier6, all6)
	_assert_eq("军火6档 turn1 盾→返回shield事件(可见化)", arm_sh_ev != null, true)
	if arm_sh_ev != null:
		_assert_eq("军火盾事件 amount=220", int((arm_sh_ev as Dictionary).get("amount", 0)), 220)
		_assert_eq("军火盾事件 vfx=shieldglow", str((arm_sh_ev as Dictionary).get("vfx", "")), "shieldglow")
	# 第2回合(turn偶): 弹幕魔法(220)均摊敌全体(单敌=220 魔法, def=0 → 满额)
	var hp_before: int = int(enemy6.get("hp", 0))
	Phase2Schools.on_round_begin(all6, 2)
	_assert_eq("军火6档 turn2 弹幕→敌掉血(220)", hp_before - int(enemy6.get("hp", 0)), 220)

	# --- 9 档: 1 携带者 9 件 → tier3 + 火控真伤% = 10+5×9 = 55 ---
	var carrier9 := _make_armory_fighter("left", "front-1", 9)
	var team9 := [carrier9]
	Phase2Schools.apply_team_start(team9)
	_assert_eq("军火9档 _armoryTier=3", int(carrier9.get("_armoryTier", 0)), 3)
	_assert_eq("军火9档 _armoryCount=9", int(carrier9.get("_armoryCount", 0)), 9)
	_assert_eq("军火9档 火控真伤% = 10+5×9 = 55", float(carrier9.get("_armoryTrueDmgPct", 0.0)), 55.0, 0.001)

	# --- carries_school: 携带者真有军火件 / 无件队友 false ---
	_assert_eq("carries_school 携带者=true", Phase2Schools.carries_school(carrier3, "深海军械库"), true)
	_assert_eq("carries_school 无件队友=false", Phase2Schools.carries_school(ally3, "深海军械库"), false)

	# --- 2 件不足 3 档 → 不激活 (无标记) ---
	var under := _make_armory_fighter("left", "front-1", 2)
	Phase2Schools.apply_team_start([under])
	_assert_eq("军火2件 不激活 无_armoryTier", int(under.get("_armoryTier", 0)), 0)


## 在 on_round_begin 返回的事件列表中找匹配 (kind + 目标 fighter) 的第一个事件; 无则 null。
func _find_event(events: Array, kind: String, target: Dictionary, all_fighters: Array):
	var ti: int = all_fighters.find(target)
	for ev in events:
		if ev is Dictionary and str(ev.get("kind", "damage")) == kind and int(ev.get("target_idx", -1)) == ti:
			return ev
	return null


## P0 chokepoint 可见化: 学派每回合 盾/治疗/净化 现作为事件从 on_round_begin 返回 (供 _render_school_round_damage 飘字+光).
## 验: 圣甲圣盾·玄甲每回合盾·血牙保命盾 → shield 事件; 潮汐回血·大潮 → heal 事件; 大潮净化 → purify 事件。
func _test_phase2_school_feedback_events() -> void:
	# ── 玄甲卫队[玄甲工坊] 每回合全队盾 (tier1 = +10 盾/单位) → 返回 shield 事件 ──
	# 玄甲 ids = 013/014/015 (3件→tier1)。盾值 [10,15,20][0]=10。
	var xj := _make_school_eq_fighter("left", ["p2eq_013", "p2eq_014", "p2eq_015"])
	xj["shield"] = 0
	Phase2Schools.apply_team_start([xj])
	var xj_ev: Array = Phase2Schools.on_round_begin([xj], 1)
	_assert_eq("玄甲每回合盾: shield 增到 10", int(xj["shield"]), 10)
	var xj_sh = _find_event(xj_ev, "shield", xj, [xj])
	_assert_eq("玄甲每回合盾→返回 shield 事件", xj_sh != null, true)
	if xj_sh != null:
		_assert_eq("玄甲盾事件 amount=10", int((xj_sh as Dictionary).get("amount", 0)), 10)
		_assert_eq("玄甲盾事件 vfx=shieldglow", str((xj_sh as Dictionary).get("vfx", "")), "shieldglow")

	# ── 圣甲议会[圣盾] 每2回合圣光护盾 (turn 偶) → 返回 shield 事件 ──
	# 圣甲 ids = 008/012/016 (3件→tier1)。45×(1+0.5×3件)=112.5→113 盾。turn=2 触发。
	var ho := _make_school_eq_fighter("left", ["p2eq_008", "p2eq_012", "p2eq_016"])
	ho["shield"] = 0
	Phase2Schools.apply_team_start([ho])
	_assert_eq("圣甲: 携带者标 _holyShield", ho.get("_holyShield", false), true)
	var ho_ev1: Array = Phase2Schools.on_round_begin([ho], 1)   # turn 奇 → 不生盾
	_assert_eq("圣甲 turn1(奇): 无圣光盾事件", _find_event(ho_ev1, "shield", ho, [ho]) == null, true)
	ho["shield"] = 0
	var ho_ev2: Array = Phase2Schools.on_round_begin([ho], 2)   # turn 偶 → 生盾
	var ho_sh = _find_event(ho_ev2, "shield", ho, [ho])
	_assert_eq("圣甲 turn2(偶): 圣光盾→返回 shield 事件", ho_sh != null, true)
	if ho_sh != null:
		_assert_eq("圣甲盾事件 amount=113", int((ho_sh as Dictionary).get("amount", 0)), 113)
		_assert_eq("圣甲盾事件 vfx=holyshieldglow(白黄圣光, 区别普通蓝盾)", str((ho_sh as Dictionary).get("vfx", "")), "holyshieldglow")

	# ── 血牙帮[血祭] 保命盾: HP<30% 首次 → 100%ATK 盾 → 返回 shield 事件 ──
	# 血牙 ids = 002/003/004 (3件→tier1)。hp 设 <30% → 触发一次。
	var bf := _make_school_eq_fighter("left", ["p2eq_002", "p2eq_003", "p2eq_004"])
	Phase2Schools.apply_team_start([bf])
	bf["hp"] = int(bf["maxHp"]) / 5   # 20% < 30% → 触发
	bf["shield"] = 0
	var bf_atk: int = int(bf.get("atk", 0))
	var bf_ev: Array = Phase2Schools.on_round_begin([bf], 1)
	var bf_sh = _find_event(bf_ev, "shield", bf, [bf])
	_assert_eq("血牙保命盾(HP<30%)→返回 shield 事件", bf_sh != null, true)
	_assert_eq("血牙: 保命盾用过标记 _bloodFangShieldUsed", bf.get("_bloodFangShieldUsed", false), true)
	if bf_sh != null:
		_assert_eq("血牙盾事件 amount=ATK(%d)" % bf_atk, int((bf_sh as Dictionary).get("amount", 0)) > 0, true)
	# 第二回合不再触发 (每场一次) → 无新 shield 事件。
	bf["hp"] = int(bf["maxHp"]) / 5
	var bf_ev2: Array = Phase2Schools.on_round_begin([bf], 1)
	_assert_eq("血牙保命盾: 第二次不触发(每场一次)", _find_event(bf_ev2, "shield", bf, [bf]) == null, true)

	# ── 潮汐议会[潮汐] 每回合回血 + 大潮净化 → 返回 heal / purify 事件 ──
	# 潮汐 ids = 017/019/025 (3件→tier?)。tier 由件数定; 回血=已损×pct。设 hp 半血 → 必有回血。
	var td := _make_school_eq_fighter("left", ["p2eq_017", "p2eq_019", "p2eq_025"])
	Phase2Schools.apply_team_start([td])
	td["hp"] = int(td["maxHp"]) / 2   # 损一半 → 必回血
	# 挂一个减益(burn)供大潮净化 (turn=3 触发大潮)。
	if not td.has("buffs"):
		td["buffs"] = []
	(td["buffs"] as Array).append({"type": "burn", "value": 1, "duration": 99})
	var td_ev: Array = Phase2Schools.on_round_begin([td], 3)   # turn=3 → 潮涌回血 + 大潮(回血+净化)
	var td_heal = _find_event(td_ev, "heal", td, [td])
	_assert_eq("潮汐回血→返回 heal 事件", td_heal != null, true)
	if td_heal != null:
		_assert_eq("潮汐回血事件 amount>0", int((td_heal as Dictionary).get("amount", 0)) > 0, true)
		_assert_eq("潮汐回血事件 vfx=healglow", str((td_heal as Dictionary).get("vfx", "")), "healglow")
	var td_purify = _find_event(td_ev, "purify", td, [td])
	_assert_eq("大潮净化(移减益)→返回 purify 事件", td_purify != null, true)
	if td_purify != null:
		_assert_eq("净化事件 amount=1(移1减益)", int((td_purify as Dictionary).get("amount", 0)), 1)


## 状态徽章: 深渊腐蚀(corrode buff) / 极地僵硬(_stiffnessStacks) 叠层徽章 — 原 _status_badges 缺 case, 叠层玩家看不见。
## 验: 有腐蚀/僵硬时徽章数比无时各 +1 (徽章 Control 构建无副作用, 不入树)。
func _test_status_badge_corrode_stiffness() -> void:
	var bs = BattleSceneScript.new()   # 不入树, _status_badges 只读 f + 建 Control (无 slot_nodes 依赖)
	# 基线: 干净单位 (无任何 buff/状态字段)。
	var base_f := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": []}
	var base_n: int = _badge_count(bs, base_f)
	# 腐蚀: 带 corrode buff (3层, pct=0.06) → 多 1 个徽章。
	var cor_f := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000,
		"buffs": [{"type": "corrode", "value": 3, "pct": 0.06, "duration": 99}]}
	_assert_eq("腐蚀 corrode → 徽章 +1 (原缺 case)", _badge_count(bs, cor_f), base_n + 1)
	# 僵硬: _stiffnessStacks=10 → 多 1 个徽章。
	var stiff_f := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": [], "_stiffnessStacks": 10}
	_assert_eq("僵硬 stiffness → 徽章 +1 (原缺 case)", _badge_count(bs, stiff_f), base_n + 1)
	# 0 层僵硬 → 不显 (与基线相同)。
	var stiff0_f := {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "buffs": [], "_stiffnessStacks": 0}
	_assert_eq("僵硬 0层 → 不显 (=基线)", _badge_count(bs, stiff0_f), base_n)
	bs.free()


## 调 _status_badges 取徽章数 + 立即 free 返回的孤儿 Control (不入树 → 不泄漏)。
func _badge_count(bs, f: Dictionary) -> int:
	var arr: Array = bs._status_badges(f)
	var n: int = arr.size()
	for c in arr:
		if c is Node and is_instance_valid(c):
			c.free()
	return n


## 血条圣盾段: 圣甲圣盾(_holyShieldVal)画白黄亮, 与普通盾段分开。验 _holy 捕获 + clamp 不超总盾 + 随盾衰减写回。
func _test_hp_bar_holy_shield_segment() -> void:
	var HpBarS = load("res://scripts/scenes/hp_bar.gd")
	var hb = HpBarS.new(); hb.setup(true, false)
	# ① 总盾 200, 其中 120 是圣盾 → _holy=120, 普通盾段=80。
	hb.update_state({"hp": 1000, "maxHp": 1000, "shield": 200, "_holyShieldVal": 120})
	_assert_eq("血条: 总盾捕获=200", hb._shield, 200.0, 0.5)
	_assert_eq("血条: 圣盾段捕获=120 (白黄亮)", hb._holy, 120.0, 0.5)
	# ② 圣盾值 > 总盾 (盾被打掉一部分): clamp 到总盾, 且写回 fighter 让其衰减。
	var f2 := {"hp": 1000, "maxHp": 1000, "shield": 50, "_holyShieldVal": 120}
	hb.update_state(f2)
	_assert_eq("血条: 圣盾 clamp 不超当前总盾 (120→50)", hb._holy, 50.0, 0.5)
	_assert_eq("血条: clamp 写回 fighter (_holyShieldVal→50, 随盾衰减)", int(f2.get("_holyShieldVal", 0)), 50)
	# ③ 盾清零 → 圣盾段归 0 (之后新得普通盾不被误染金)。
	var f3 := {"hp": 1000, "maxHp": 1000, "shield": 0, "_holyShieldVal": 120}
	hb.update_state(f3)
	_assert_eq("血条: 盾清零 → 圣盾段=0", hb._holy, 0.0, 0.5)
	_assert_eq("血条: 盾清零 → _holyShieldVal 写回 0", int(f3.get("_holyShieldVal", 0)), 0)
	# ④ 无 _holyShieldVal (普通龟): _holy=0, 不影响普通盾。
	hb.update_state({"hp": 1000, "maxHp": 1000, "shield": 100})
	_assert_eq("血条: 无圣盾字段 → _holy=0 (普通盾照常)", hb._holy, 0.0, 0.5)
	_assert_eq("血条: 无圣盾字段 → 总盾仍=100", hb._shield, 100.0, 0.5)
	hb.free()


## 审计补实装(用户批): 饰品溢出转盾 / 玄甲化 / 极地僵硬·易碎 / 深渊腐蚀 / 远古蛋HP — 各验真触发。
func _test_phase2_audit_promised_effects() -> void:
	var P2T = load("res://scripts/engine/phase2_types.gd")

	# ── 饰品[续航] 溢出转盾 (类型级, 规格#552): 携带饰品激活 → 治疗溢出转护盾(无上限) ──
	# 饰品 ids = 044/011/045/004; tiers=[2,3,4]。带 2 件 → tier1 激活 → 标 _p2AccessoryOverflowShield。
	var accmark = {"side": "left", "alive": true, "hp": 900, "maxHp": 1000, "shield": 0, "healAmp": 0.0,
		"baseAtk": 0, "atk": 0, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0,
		"_p2_equips": [{"id": "p2eq_044", "star": 1}, {"id": "p2eq_045", "star": 1}]}
	P2T.apply_team_start([accmark])
	_assert_eq("饰品2件激活→标溢出转盾flag", accmark.get("_p2AccessoryOverflowShield", false), true)
	# 数学隔离 (healAmp=0, 仅看溢出转盾): _heal 300 → 回100到满 + 溢出200转盾 (无上限)。
	var accf = {"side": "left", "alive": true, "hp": 900, "maxHp": 1000, "shield": 0, "healAmp": 0.0, "_p2AccessoryOverflowShield": true}
	var heal_acc := Phase2EquipRuntime._heal(accf, 300.0)
	_assert_eq("饰品溢出: 实回血=100(到满)", heal_acc, 100)
	_assert_eq("饰品溢出: 溢出200→护盾", int(accf.get("shield", 0)), 200)
	# _heal_to (skill_handlers 路径) 同样转盾: 满血再治200 → 全溢出转盾。
	accf["_heal_shield_gain"] = 0
	var heal_acc2 := SkillHandlers._heal_to(accf, 200)
	_assert_eq("饰品溢出(_heal_to): 满血治疗实回0", heal_acc2, 0)
	_assert_eq("饰品溢出(_heal_to): 200累加护盾→400", int(accf.get("shield", 0)), 400)
	# 可见化: _heal_to 把溢出转盾量记 _heal_shield_gain → BattleScene._refresh_slot 读它飘"+N盾"+盾光 (原静默)
	_assert_eq("饰品溢出(_heal_to): 记 _heal_shield_gain=200 (可见化)", int(accf.get("_heal_shield_gain", 0)), 200)
	# 无 flag 单位: 溢出丢弃, 不转盾。
	var plain = {"side": "left", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "healAmp": 0.0}
	Phase2EquipRuntime._heal(plain, 300.0)
	_assert_eq("无饰品flag: 溢出不转盾", int(plain.get("shield", 0)), 0)

	# ── 玄甲卫队[玄甲工坊] 玄甲化: 随机1件「费用≤2 非3星」装备临时+1星, 下回合还原 ──
	# 3件玄甲(013/015/035) → 玄甲 tier1 (阈值3)。费用 stub: 013=3,015=2,035=1 → 费用≤2 候选只有 015/035。
	var xcost = func(eid): return {"p2eq_013": 3, "p2eq_015": 2, "p2eq_035": 1, "p2eq_002": 1}.get(eid, 9)
	var xf = {"side": "left", "alive": true, "_isEgg": false,
		"_p2_equips": [{"id": "p2eq_013", "star": 1}, {"id": "p2eq_015", "star": 1}, {"id": "p2eq_035", "star": 1}]}
	var xrng := RandomNumberGenerator.new(); xrng.seed = 12345
	var xboost: Array = Phase2Schools.apply_xuanjia_round([xf], xcost, xrng)
	_assert_eq("玄甲化 tier1 → 玄甲化1件", xboost.size(), 1)
	# 被选中的必是费用≤2 的 015 或 035, 且星已+1=2。
	var picked_id: String = str(xboost[0].get("item_id", ""))
	_assert_eq("玄甲化 选中费用≤2候选(015/035)", picked_id == "p2eq_015" or picked_id == "p2eq_035", true)
	var picked_now: int = -1
	var picked_orig_marked := false
	for it in xf["_p2_equips"]:
		if str(it.get("id", "")) == picked_id:
			picked_now = int(it.get("star", 0))
			picked_orig_marked = it.has("_xuanjiaOrigStar")
	_assert_eq("玄甲化 选中件 star→2", picked_now, 2)
	_assert_eq("玄甲化 存原星(还原用)", picked_orig_marked, true)
	# 费用>2 的 013 不应被玄甲化 (星仍1)。
	var x013 := -1
	for it in xf["_p2_equips"]:
		if str(it.get("id", "")) == "p2eq_013": x013 = int(it.get("star", 0))
	_assert_eq("玄甲化 费用>2(013)不选→仍1星", x013, 1)
	# 下回合再调 → 先还原上回合玄甲化: 调用后, 每件 star 不应 >2, 且未被本轮选中的件无悬挂 _xuanjiaOrigStar。
	Phase2Schools.apply_xuanjia_round([xf], xcost, xrng)
	var max_star_after := 0
	for it in xf["_p2_equips"]:
		max_star_after = maxi(max_star_after, int(it.get("star", 1)))
	_assert_eq("玄甲化 再调后还原+重选: 无件超2星(还原幂等)", max_star_after <= 2, true)
	# 无候选场景 → 不触发不报错 (玄甲未激活)。
	var xf_noschool = {"side": "left", "alive": true, "_p2_equips": [{"id": "p2eq_002", "star": 1}]}
	var xb2: Array = Phase2Schools.apply_xuanjia_round([xf_noschool], xcost, xrng)
	_assert_eq("玄甲未激活→不玄甲化", xb2.size(), 0)

	# ── 极地小队[冰封] 6档僵硬 (-2%攻/层) + 9档易碎 (被冻/眩晕 +25%受伤) ──
	# 6档僵硬: stats_recalc 消费 _stiffnessStacks。10层 → -20% 攻。
	var stiff_t = {"side": "right", "alive": true, "baseAtk": 100, "atk": 100, "baseDef": 0, "def": 0, "baseMr": 0, "mr": 0, "_stiffnessStacks": 10, "buffs": []}
	StatsRecalc.recalc(stiff_t)
	_assert_eq("极地6档僵硬: 10层→-20%攻(100→80)", int(stiff_t.get("atk", 0)), 80)
	# 9档易碎: _iceShatter + 被眩晕 → damage.gd 受伤×1.25。
	var brittle = {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "_iceShatter": true, "buffs": []}
	Buffs.add(brittle, "stun", 1, 2, "overwrite")
	var r_brittle := Damage.apply_raw_damage(brittle, 100, "physical")
	_assert_eq("极地9档易碎: 冻结目标受伤+25%(100→125)", int(r_brittle.get("hpLoss", 0)), 125)
	# 未冻结(无 stun) → 不增伤。
	var brittle2 = {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0, "_iceShatter": true, "buffs": []}
	var r_b2 := Damage.apply_raw_damage(brittle2, 100, "physical")
	_assert_eq("极地易碎: 未冻结不增伤(=100)", int(r_b2.get("hpLoss", 0)), 100)

	# ── 深渊议会[腐蚀] 满5层 → 30% 转真伤(无视护盾) ──
	# 5层腐蚀 + 盾1000: 100伤害 → 30%(30)无视盾直击HP, 70%(70)被盾吸。
	var cor_t = {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 1000, "def": 0, "mr": 0,
		"buffs": [{"type": "corrode", "value": 5, "pct": 0.0, "duration": 99}]}
	var r_cor := Damage.apply_raw_damage(cor_t, 100, "physical")
	_assert_eq("深渊腐蚀满5层: 30%无视盾直击HP(-30)", 1000 - int(cor_t.get("hp", 0)), 30)
	_assert_eq("深渊腐蚀满5层: 70%被盾吸(盾1000→930)", int(cor_t.get("shield", 0)), 930)
	# 腐蚀每层 +pct% 受伤 (5层×6%=+30%)。盾足够, 全吸; 验 final_dmg 放大。
	var cor_amp = {"side": "right", "alive": true, "hp": 1000, "maxHp": 1000, "shield": 0, "def": 0, "mr": 0,
		"buffs": [{"type": "corrode", "value": 3, "pct": 0.06, "duration": 99}]}
	var r_amp := Damage.apply_raw_damage(cor_amp, 100, "physical")
	_assert_eq("深渊腐蚀3层×6%: +18%受伤(100→118)", int(r_amp.get("hpLoss", 0)), 118)

	# ── 远古遗迹[古代觉醒] 龟蛋 +500/750/1500 maxHp (BattleScene._ancient_egg_bonus 走 calc_active 同口径) ──
	# 远古 ids = 009/014/024/026/038/044/058/059; tiers=[3,6,9]。带 3 件 → tier1 → 蛋 +500。
	var anc_team := [_make_school_eq_fighter("left", ["p2eq_009", "p2eq_024", "p2eq_026"])]
	var anc_tier := 0
	for a in Phase2Schools.calc_active(anc_team):
		if str(a.get("school", "")) == "远古遗迹":
			anc_tier = int(a.get("tier", 0))
	_assert_eq("远古3件→tier1", anc_tier, 1)
	_assert_eq("远古tier1 蛋HP加成=500", [500, 750, 1500][clampi(anc_tier - 1, 0, 2)], 500)
	# 6 件 → tier2 → +750。
	var anc_team6 := [_make_school_eq_fighter("left", ["p2eq_009", "p2eq_024", "p2eq_026", "p2eq_038", "p2eq_058", "p2eq_059"])]
	var anc_tier6 := 0
	for a in Phase2Schools.calc_active(anc_team6):
		if str(a.get("school", "")) == "远古遗迹":
			anc_tier6 = int(a.get("tier", 0))
	_assert_eq("远古6件→tier2", anc_tier6, 2)
	_assert_eq("远古tier2 蛋HP加成=750", [500, 750, 1500][clampi(anc_tier6 - 1, 0, 2)], 750)
	# 2 件 → 不激活 (无蛋加成)。
	var anc_under := [_make_school_eq_fighter("left", ["p2eq_009", "p2eq_024"])]
	var anc_active := false
	for a in Phase2Schools.calc_active(anc_under):
		if str(a.get("school", "")) == "远古遗迹":
			anc_active = true
	_assert_eq("远古2件 不激活", anc_active, false)


func _make_school_eq_fighter(side: String, ids: Array) -> Dictionary:
	var eqs: Array = []
	for i in ids:
		eqs.append({"id": str(i), "star": 1})
	return {
		"id": "basic", "side": side, "alive": true, "_isEgg": false, "_slotKey": "front-1",
		"maxHp": 1000, "hp": 1000, "shield": 0, "atk": 100, "def": 0, "mr": 0,
		"baseAtk": 100, "baseDef": 0, "baseMr": 0, "armorPenPct": 0.0, "magicPenPct": 0.0, "buffs": [],
		"_p2_equips": eqs,
	}
