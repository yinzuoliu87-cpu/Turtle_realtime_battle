extends RefCounted
## 图鉴·状态页「来源」表 —— 哪些龟(技能)/装备/小将/羁绊会施加这个状态。
##
## ★这张表【不许凭印象写】(2026-10-10 图鉴体检: 25 个状态页只有一行「效果」,
##   其中 4 页写着「数值由来源决定」却一个来源都不点名)。每一条都钉着施加它的代码位置:
##     "at"  = "相对 res://scripts/ 的文件:函数名"   —— 这个函数里必须真有施加该状态的那行代码
##     "arm" = 函数里的 match 分支 / `== "x"` 判断(同一函数里装着好几件装备时用)
##     "re"  = 施加写法不是标准形状时, 自带一条正则(仍须在该函数 / 分支里命中)
##     "link"/"lf" = 证明「这段代码属于这只龟 / 这件装备」的正则(lf = 去哪个文件找, 默认 at 的文件)
##   守卫: tests/verify_codex_status_sources.gd
##     ① 每条来源: 函数存在、真的施加了该状态、确实属于所写的龟 / 装备、技能名在 pets.json 里查得到;
##     ② 全仓扫描每一处施加该状态的代码 —— 每一处要么被本表某条认领, 要么在门禁的忽略表里写明原因。
##        新加一个施加点而不登记 ⇒ 门禁红, 本表就不会悄悄落后于代码。
##     ③ "v"(数值)里的 {C:类.常量} 必须是该函数里真在用的常量; 裸数字必须是该函数里的字面量
##        (允许 ×100 与 1−x 两种换算: 0.65 ⇒ 「−35%」)。
##
## 键: "k" = pet | eq | minion | syn;  "id" = 龟 id / 装备 id / 小将 kind / 羁绊类型名;
##     "pv" = 小将被动名(MinionCodex.MINION_INFO 的 passives[].name; 小将被动没有 type)
##     "sk" = 技能 type(龟: skillPool / 形态技 / 被动的 type);  "to" = self | ally(省略 = 敌人)
##     "v" = 数值(可含 {C:类.常量} / {C:类.常量%} / {R:类.常量} = (1−值)×100)
##
## 反伤 / 闪避 这两个「属性型」状态, 装备与羁绊那一半**不在表里** —— 直接从属性表现算
## (EquipStats.STATS 的 reflectPct / dodgePct, Phase2Types.TYPES 的 dodgePct), 见 derived()。

const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

const MAIN := "scenes/RealtimeBattle3DScene.gd"
const EQS := "systems/equip/equip_system.gd"

const SRC := {
	"stun": [
		{"k": "pet", "id": "basic", "sk": "basicSlam", "at": MAIN + ":_basic_slam_run", "v": "{C:BasicConsts.SLAM_STUN_SEC} 秒"},
		{"k": "pet", "id": "bamboo", "sk": "bambooSmack", "at": "systems/skills/bamboo_system.gd:_sk_bamboo_smack", "v": "{C:BambooSystem.SMACK_STUN} 秒"},
		{"k": "pet", "id": "bubble", "sk": "bubbleBind", "at": "systems/skills/bubble_system.gd:_sk_bubble_bind", "v": "{C:BubbleSystem.BIND_SEC} 秒"},
		{"k": "pet", "id": "diamond", "sk": "diamondPowerball", "at": "systems/skills/diamond_system.gd:_diamond_roll_impact", "v": "{C:DiamondSystem.ROLL_STUN_MIN}~{C:DiamondSystem.ROLL_STUN_MAX} 秒",
			"link": "^func _diamond_roll_tick[\\s\\S]{0,2500}_diamond_roll_impact\\("},
		{"k": "pet", "id": "ice", "sk": "iceFreeze", "at": "systems/skills/ice_system.gd:_sk_ice_freeze"},
		{"k": "pet", "id": "headless", "sk": "headlessTendrils", "at": "systems/skills/headless_system.gd:_sk_headless_tendrils", "v": "{C:HeadlessSystem.TENDRIL_STUN_SEC} 秒"},
		{"k": "pet", "id": "stone", "sk": "rockShockwave", "at": "systems/skills/stone_system.gd:_sk_rock_shockwave", "v": "{C:StoneSystem.ROCK_WAVE_STUN} 秒"},
		{"k": "pet", "id": "pirate", "sk": "pirateShipPassive", "at": "scenes/battle/battle_spawn.gd:_spawn_pirate_ship", "v": "{C:PirateSystem.SHIP_CHARGE_STUN} 秒"},
		{"k": "pet", "id": "pirate", "sk": "pirateBarrage", "at": "systems/skills/pirate_system.gd:_pirate_death_grapple", "v": "{C:PirateSystem.HOOK_STUN} 秒",
			"lf": MAIN, "link": "== \"pirate\"[^\\n]*killer[^\\n]*\\n[^\\n]*_pirate_death_grapple\\(u, killer\\)"},
		{"k": "minion", "id": "front", "sk": "minionBodysurf", "at": "systems/skills/hiding_system.gd:_sk_minion_bodysurf", "v": "1.1 秒"},
		{"k": "minion", "id": "elite", "pv": "铁锁", "at": MAIN + ":_tick_elite_whip", "v": "0.4 秒", "link": "精英小将铁锁"},
		{"k": "minion", "id": "elite", "pv": "吞噬", "at": "systems/skills/elite_system.gd:_elite_try_consume", "v": "1.7 秒", "link": "^class_name EliteSystem"},
		{"k": "eq", "id": "p2eq_017", "at": EQS + ":_eq_on_basic_attack", "arm": "p2eq_017", "v": "{C:RealtimeBattle3DScene.CTRL_SEC} 秒"},
		{"k": "eq", "id": "p2eq_027", "at": EQS + ":_eq_on_basic_attack", "arm": "p2eq_027"},
		{"k": "eq", "id": "p2eq_029", "at": "systems/skills/ice_system.gd:_ice_fissure_hit", "v": "1/1.8/2.5 秒",
			"lf": EQS, "link": "\"p2eq_029\": _eq_ice_fissure"},
		{"k": "eq", "id": "p2eq_038", "at": "systems/equip/signal_wave_system.gd:_apply", "v": "{C:SignalWaveSystem.WAVE_STUN} 秒"},
		{"k": "eq", "id": "p2eq_053", "at": EQS + ":_eq_shotgun_blast", "v": "{C:RealtimeBattle3DScene.CTRL_SEC} 秒", "link": "霰弹贝古053"},
		{"k": "eq", "id": "p2eq_055", "at": "systems/equip/hookbomb_system.gd:_hb_detonate"},
		{"k": "eq", "id": "p2eq_056", "at": EQS + ":_eq_on_hit", "arm": "p2eq_056", "v": "{C:EquipSystem.DART_KNOCKUP_SEC} 秒"},
		{"k": "eq", "id": "p2eq_090", "at": "systems/equip/eq_arcane_batch.gd:pestle_slam"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_passives.gd:slam_settle", "v": "{C:AxeEvolution.SLAM_STUN} 秒", "link": "小木斧"},
		{"k": "syn", "id": "奇械", "at": "systems/equip/gadget_synergy_system.gd:on_hit", "v": "{C:GadgetSynergySystem.FREEZE_SEC} 秒"},
	],
	"fear": [
		{"k": "pet", "id": "headless", "sk": "headlessFear", "at": "systems/skills/headless_system.gd:_sk_headless_fear", "v": "3 秒"},
	],
	"airborne": [
		{"k": "pet", "id": "basic", "sk": "basicChiWave", "at": MAIN + ":_sk_basic_chiwave"},
		{"k": "pet", "id": "basic", "sk": "basicTurtle", "at": MAIN + ":_basic_shield_impact_hit",
			"link": "== \"basic\" and u\\.get\\(\"basic_enh_ready\"[\\s\\S]{0,200}_sk_basic_shield\\(u, tgt\\)"},
		{"k": "pet", "id": "bamboo", "sk": "bambooSpikes", "at": "systems/skills/bamboo_system.gd:_sk_bamboo_spikes"},
		{"k": "pet", "id": "ninja", "sk": "ninjaInstinct", "at": "systems/skills/ninja_system.gd:_ninja_glide",
			"link": "func _ninja_dash\\(u: Dictionary, target: Dictionary\\) -> void:    # 被动"},
		{"k": "pet", "id": "ghost", "sk": "ghostPhantom", "at": "systems/skills/ghost_system.gd:_ghost_phantom_hit"},
		{"k": "pet", "id": "diamond", "sk": "diamondPowerball", "at": "systems/skills/diamond_system.gd:_diamond_roll_impact",
			"link": "^func _diamond_roll_tick[\\s\\S]{0,2500}_diamond_roll_impact\\("},
		{"k": "pet", "id": "diamond", "sk": "diamondSmash", "at": "systems/skills/diamond_system.gd:_diamond_smash_impact"},
		{"k": "pet", "id": "pirate", "sk": "pirateShipPassive", "at": "scenes/battle/battle_spawn.gd:_spawn_pirate_ship"},
		{"k": "pet", "id": "crystal", "sk": "crystalBarrier", "at": "systems/skills/crystal_system.gd:_crystal_spike_line",
			"lf": MAIN, "link": "func _tick_bulwark[\\s\\S]{0,900}_crystal_spike_line\\(u\\)"},
		{"k": "pet", "id": "chest", "sk": "chestCannon", "at": "systems/skills/chest_system.gd:_sk_chest_cannon"},
		{"k": "pet", "id": "space", "sk": "starGravityWarp", "at": "systems/skills/star_system.gd:_sk_star_gravity_warp"},
		{"k": "pet", "id": "space", "sk": "starWormhole", "at": "systems/skills/star_system.gd:_sk_star_wormhole"},
		{"k": "pet", "id": "headless", "sk": "headlessSoulStrike", "at": "systems/skills/headless_system.gd:_headless_knock_out",
			"link": "func _headless_scythe[\\s\\S]{0,4000}_headless_knock_out\\(o,"},
		{"k": "pet", "id": "lava", "sk": "lavaSurge", "at": "systems/skills/lava_system.gd:_lava_magma_surge"},
		{"k": "pet", "id": "lava", "sk": "volcanoErupt", "at": "systems/skills/lava_system.gd:_lava_volcano_erupt",
			"link": "if volcano: _lava_volcano_erupt\\(u\\)"},
		{"k": "pet", "id": "lava", "sk": "volcanoSmash", "at": "systems/skills/lava_system.gd:_lava_flame_strike",
			"link": "if volcano: _lava_flame_strike\\(u, tgt\\)"},
		{"k": "pet", "id": "lava", "sk": "lavaRage", "at": "systems/skills/lava_system.gd:_lava_slam_impact",
			"link": "func _lava_transform[\\s\\S]{0,1500}_lava_volcano_slam\\(u\\)"},
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_sk_shell_shadow_dive"},
		{"k": "pet", "id": "stone", "sk": "stoneTaunt", "at": "systems/skills/stone_system.gd:_sk_stone_taunt"},
		{"k": "pet", "id": "stone", "sk": "rockShockwave", "at": "systems/skills/stone_system.gd:_sk_rock_shockwave"},
		{"k": "pet", "id": "two_head", "sk": "twoHeadFusion", "at": "systems/skills/two_head_system.gd:_two_head_fusion_wave_hit"},
		{"k": "minion", "id": "front", "sk": "minionBodysurf", "at": "systems/skills/hiding_system.gd:_minion_bodysurf_ride"},
		{"k": "minion", "id": "elite", "sk": "eliteHammer", "at": "systems/skills/elite_system.gd:_sk_elite_hammer"},
		{"k": "eq", "id": "p2eq_010", "at": EQS + ":_eq_laser_chop", "lf": EQS, "link": "\"p2eq_010\""},
		{"k": "eq", "id": "p2eq_017", "at": EQS + ":_eq_on_basic_attack", "arm": "p2eq_017"},
		{"k": "eq", "id": "p2eq_020", "at": MAIN + ":_dumbbell_hit", "link": "哑铃"},
		{"k": "eq", "id": "p2eq_028", "at": "systems/skills/ice_system.gd:_ice_bottle_hit",
			"lf": EQS, "link": "# 028 冰冻药剂[^\\n]*\\nfunc _eq_ice_throw"},
		{"k": "eq", "id": "p2eq_029", "at": "systems/skills/ice_system.gd:_ice_fissure_hit", "lf": EQS, "link": "\"p2eq_029\": _eq_ice_fissure"},
		{"k": "eq", "id": "p2eq_034", "at": MAIN + ":_summon_walking_bear", "link": "玩偶小熊仔"},
		{"k": "eq", "id": "p2eq_034", "at": "systems/equip/equip_tick_system.gd:_tick_bear_waves", "link": "_tick_bear_waves\\(_dt\\)   # 034"},
		{"k": "eq", "id": "p2eq_043", "at": EQS + ":_eq_water_wave"},
		{"k": "eq", "id": "p2eq_056", "at": EQS + ":_eq_on_hit", "arm": "p2eq_056"},
		{"k": "eq", "id": "p2eq_090", "at": "systems/equip/eq_arcane_batch.gd:_knock_for"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_passives.gd:smash_on_hit", "link": "小木斧"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_passives.gd:slam_settle", "link": "小木斧"},
	],
	"taunt": [
		{"k": "pet", "id": "stone", "sk": "stoneTaunt", "at": "systems/skills/stone_system.gd:_sk_stone_taunt", "v": "{C:StoneSystem.TAUNT_SEC} 秒"},
		{"k": "eq", "id": "p2eq_072", "at": "systems/equip/eq_food_batch.gd:_box_form_tick"},
	],
	"burn": [
		{"k": "pet", "id": "lava", "sk": "lavaBolt", "at": MAIN + ":_do_basic", "re": "\"burn\":\\s+_damage\\._apply_dot_stacks",
			"link": "\"lava\":\\s+\\{[^\\n]*\"rider\": \"burn\""},
		{"k": "pet", "id": "lava", "sk": "volcanoErupt", "at": "systems/skills/lava_system.gd:_lava_volcano_erupt", "link": "if volcano: _lava_volcano_erupt\\(u\\)"},
		{"k": "pet", "id": "lava", "sk": "lavaErupt", "at": "systems/skills/lava_system.gd:_lava_pierce_bolt",
			"lf": MAIN, "link": "lava_pierce_next[^\\n]*\\n[^\\n]*\\n[^\\n]*_lava_pierce_bolt\\(u, tgt\\)"},
		{"k": "pet", "id": "lava", "sk": "lavaRage", "at": "systems/skills/lava_system.gd:_lava_slam_impact",
			"link": "func _lava_transform[\\s\\S]{0,1500}_lava_volcano_slam\\(u\\)"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixBurn", "at": "systems/skills/phoenix_system.gd:_phoenix_flame_cone",
			"lf": MAIN, "link": "== \"phoenix\":\\s*\\n\\s*_phoenix_sys\\._phoenix_flame_channel"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixScald", "at": "systems/skills/phoenix_system.gd:_phoenix_scald_hit"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixRebirth", "at": "systems/skills/phoenix_system.gd:nirvana_begin", "link": "涅槃"},
		{"k": "pet", "id": "rainbow", "sk": "rainbowPrism", "at": "systems/skills/rainbow_system.gd:_rainbow_enh_prism_proc", "link": "棱镜"},
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_sk_shell_shadow_dive"},
		{"k": "pet", "id": "chest", "sk": "chestTreasure", "at": "scenes/battle/battle_damage.gd:_post_hit_hooks", "re": "\"burn\", maxi\\(1, roundi\\(float\\(src\\[\"atk\"\\]\\) \\* ChestSystem\\.FLINT",
			"link": "宝箱藏宝图 on-hit 战利品"},
		{"k": "eq", "id": "p2eq_022", "at": MAIN + ":_fuel_bottle_hit", "lf": EQS, "link": "battle\\._fuel_bottle_hit\\.bind"},
		{"k": "eq", "id": "p2eq_023", "at": EQS + ":_eq_on_hit", "arm": "p2eq_023"},
		{"k": "eq", "id": "p2eq_023", "at": EQS + ":_fire_coral_wave_hit", "link": "\"p2eq_023\""},
		{"k": "eq", "id": "p2eq_024", "at": "systems/equip/dragon_system.gd:_dragon_hit_enemy", "lf": EQS,
			"link": "\"p2eq_024\":[^\\n]*\\n(?:[^\\n]*\\n){0,6}[^\\n]*_eq_dragon_breath\\(u, si\\)"},
		{"k": "eq", "id": "p2eq_037", "at": EQS + ":_eq_candle_tick"},
		{"k": "eq", "id": "p2eq_045", "at": EQS + ":_eq_check_hp_threshold", "arm": "p2eq_045"},
		{"k": "eq", "id": "p2eq_080", "at": "systems/equip/eq_gun_batch.gd:heli_crash_explode"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_final_forms.gd:seraph_on_hit", "lf": "systems/equip/axe_system.gd", "link": "p2eq_096"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_final_forms.gd:_boom_sweep", "lf": "systems/equip/axe_system.gd", "link": "p2eq_096"},
	],
	"poison": [
		{"k": "pet", "id": "hunter", "sk": "hunterShot", "at": "systems/skills/hunter_system.gd:_sk_hunter_shot"},
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_shell_basic",
			"lf": MAIN, "link": "\"shellShadow\"[^\\n]*\\n\\s*_shell_sys\\._shell_enter_stealth"},
		{"k": "eq", "id": "p2eq_067", "at": "systems/equip/eq_potion_batch.gd:_eq_vial_land"},
		{"k": "eq", "id": "p2eq_067", "at": "systems/equip/eq_potion_batch.gd:_eq_poison_touch"},
		{"k": "eq", "id": "p2eq_092", "at": "systems/equip/eq_venom_drone.gd:_apply_fog_field"},
	],
	"bleed": [
		{"k": "pet", "id": "ninja", "sk": "ninjaSlash", "at": MAIN + ":_do_basic", "re": "\"bleed\":\\s+_damage\\._apply_dot_stacks",
			"link": "\"ninja\":\\s+\\{[^\\n]*\"rider\": \"bleed\""},
		{"k": "pet", "id": "diamond", "sk": "diamondSmash", "at": "systems/skills/diamond_system.gd:_diamond_smash_impact"},
		{"k": "eq", "id": "p2eq_002", "at": EQS + ":_eq_on_hit", "arm": "p2eq_002"},
		{"k": "eq", "id": "p2eq_015", "at": EQS + ":_eq_on_hit", "arm": "p2eq_015"},
		{"k": "eq", "id": "p2eq_051", "at": EQS + ":_eq_laser_pistol"},
		{"k": "eq", "id": "p2eq_056", "at": EQS + ":_eq_tick", "arm": "p2eq_056"},
		{"k": "eq", "id": "p2eq_075", "at": "systems/equip/eq_bow_batch.gd:rain_hop"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_passives.gd:cleave_settle", "link": "小木斧"},
	],
	"curse": [
		{"k": "pet", "id": "ghost", "sk": "ghostCurse", "at": "scenes/battle/battle_spawn.gd:_apply_spawn_passive_one", "arm": "ghost", "v": "{C:GhostSystem.SPAWN_CURSE_SEC} 秒"},
		{"k": "pet", "id": "ghost", "sk": "ghostCurse", "at": MAIN + ":_on_unit_death", "arm": "ghost"},
		{"k": "pet", "id": "ghost", "sk": "ghostStorm", "at": "systems/skills/ghost_system.gd:_sk_ghost_soulstorm", "v": "{C:GhostSystem.STORM_CURSE_SEC} 秒"},
		{"k": "pet", "id": "headless", "sk": "headlessSoulStrike", "at": "systems/skills/headless_system.gd:_headless_scythe", "v": "{C:HeadlessSystem.SCYTHE_CURSE_SEC} 秒"},
		{"k": "pet", "id": "rainbow", "sk": "rainbowPrism", "at": "systems/skills/rainbow_system.gd:_rainbow_enh_prism_proc", "v": "{C:RainbowSystem.PRISM_BUFF_SEC} 秒", "link": "棱镜"},
		{"k": "eq", "id": "p2eq_064", "at": "systems/equip/eq_spirit_batch.gd:_ghost_break", "v": "{C:EqSpiritBatch.GHOST_CURSE_SEC} 秒"},
	],
	"shield": [
		{"k": "pet", "id": "basic", "sk": "basicTurtle", "at": MAIN + ":_basic_shield_impact_hit", "to": "self",
			"link": "== \"basic\" and u\\.get\\(\"basic_enh_ready\"[\\s\\S]{0,200}_sk_basic_shield\\(u, tgt\\)"},
		{"k": "pet", "id": "stone", "sk": "stoneRockShield", "at": "systems/skills/stone_system.gd:_sk_stone_rock_shield", "to": "ally"},
		{"k": "pet", "id": "stone", "sk": "stoneTaunt", "at": "systems/skills/stone_system.gd:_sk_stone_taunt", "to": "self"},
		{"k": "pet", "id": "bamboo", "sk": "bambooHeal", "at": "systems/skills/bamboo_system.gd:_sk_bamboo_heal", "to": "ally"},
		{"k": "pet", "id": "angel", "sk": "angelBless", "at": "systems/skills/angel_system.gd:_sk_angel_bless", "to": "ally"},
		{"k": "pet", "id": "ice", "sk": "commonTeamShield", "at": "systems/skills/ice_system.gd:_sk_ice_team_shield", "to": "ally"},
		{"k": "pet", "id": "two_head", "sk": "twoHeadDual", "at": "systems/skills/two_head_system.gd:_two_head_apply_melee", "to": "self", "link": "^class_name TwoHeadSystem"},
		{"k": "pet", "id": "two_head", "sk": "twoHeadDual", "at": "systems/skills/two_head_system.gd:_two_head_enhanced_basic", "to": "self", "link": "^class_name TwoHeadSystem"},
		{"k": "pet", "id": "two_head", "sk": "twoHeadStrike", "at": "systems/skills/two_head_system.gd:_two_head_hammer_land", "to": "self"},
		{"k": "pet", "id": "diamond", "sk": "diamondFortify", "at": "systems/skills/diamond_system.gd:_sk_diamond_unbreak", "to": "self"},
		{"k": "pet", "id": "fortune", "sk": "fortuneAllIn", "at": "systems/skills/fortune_system.gd:_sk_fortune_allin", "to": "self"},
		{"k": "pet", "id": "fortune", "sk": "fortuneAllIn", "at": "systems/skills/fortune_system.gd:_sk_fortune_goldshield", "to": "self"},
		{"k": "pet", "id": "dice", "sk": "diceFlashStrike", "at": "systems/skills/dice_system.gd:_dice_dash_hit", "to": "self",
			"link": "^func _dice_dash_tick[\\s\\S]{0,2500}_dice_dash_hit\\("},
		{"k": "pet", "id": "rainbow", "sk": "rainbowPrism", "at": MAIN + ":_on_basic_hit", "arm": "rainbow", "to": "self"},
		{"k": "pet", "id": "rainbow", "sk": "shield", "at": "systems/skills/rainbow_system.gd:_sk_rainbow_shield", "to": "ally"},
		{"k": "pet", "id": "gambler", "sk": "gamblerDraw", "at": "systems/skills/gambler_system.gd:_sk_gambler_wild", "to": "self"},
		{"k": "pet", "id": "hunter", "sk": "hunterStealth", "at": "systems/skills/hunter_system.gd:_sk_hunter_hide", "to": "self"},
		{"k": "pet", "id": "candy", "sk": "candyBarrage", "at": "systems/skills/candy_system.gd:_sk_candy_barrage", "to": "ally"},
		{"k": "pet", "id": "bubble", "sk": "bubbleShield", "at": "systems/skills/bubble_system.gd:_sk_bubble_shield", "to": "ally"},
		{"k": "pet", "id": "lightning", "sk": "lightningShield", "at": "systems/skills/lightning_system.gd:_sk_lightning_shield", "to": "self"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixShield", "at": "systems/skills/phoenix_system.gd:_sk_phoenix_lavashield", "to": "self"},
		{"k": "pet", "id": "lava", "sk": "lavaSurge", "at": "systems/skills/lava_system.gd:_lava_magma_surge", "to": "self"},
		{"k": "pet", "id": "crystal", "sk": "crystalBarrier", "at": "systems/skills/crystal_system.gd:_sk_crystal_bulwark", "to": "self"},
		{"k": "pet", "id": "chest", "sk": "chestCount", "at": "systems/skills/chest_system.gd:_sk_chest_inventory", "to": "self"},
		{"k": "pet", "id": "hiding", "sk": "physical", "at": "systems/skills/hiding_system.gd:_hiding_shell_harden", "to": "self",
			"lf": MAIN, "link": "\"hiding\":\\s+\\{[^\\n]*\"rider\": \"shrink\""},
		{"k": "pet", "id": "hiding", "sk": "hidingDefend", "at": "systems/skills/hiding_system.gd:_sk_hiding_defend", "to": "self"},
		{"k": "eq", "id": "p2eq_007", "at": EQS + ":_eq_broadsword", "to": "self", "link": "锈蚀阔剑007"},
		{"k": "eq", "id": "p2eq_012", "at": "systems/equip/equip_tick_system.gd:_tick_jelly", "to": "self"},
		{"k": "eq", "id": "p2eq_013", "at": EQS + ":_eq_on_target", "arm": "p2eq_013", "to": "self"},
		{"k": "eq", "id": "p2eq_015", "at": EQS + ":_eq_on_target", "arm": "p2eq_015", "to": "self"},
		{"k": "eq", "id": "p2eq_016", "at": "systems/equip/equip_tick_system.gd:_tick_ironwall", "to": "ally"},
		{"k": "eq", "id": "p2eq_021", "at": "systems/equip/equip_tick_system.gd:_tick_barnacle", "to": "ally"},
		{"k": "eq", "id": "p2eq_029", "at": EQS + ":_eq_ice_fissure", "to": "self", "link": "\"p2eq_029\": _eq_ice_fissure"},
		{"k": "eq", "id": "p2eq_036", "at": "systems/equip/equip_tick_system.gd:_egg_add_progress", "to": "ally", "link": "温泉蛋\\(036\\)"},
		{"k": "eq", "id": "p2eq_043", "at": EQS + ":_eq_water_wave", "to": "ally"},
		{"k": "eq", "id": "p2eq_046", "at": EQS + ":_eq_on_dodge", "arm": "p2eq_046", "to": "self"},
		{"k": "eq", "id": "p2eq_069", "at": "systems/equip/eq_food_batch.gd:_cake_eat", "to": "self"},
		{"k": "eq", "id": "p2eq_074", "at": "systems/equip/eq_bow_batch.gd:on_basic_074", "to": "self"},
		{"k": "eq", "id": "p2eq_081", "at": "systems/equip/eq_blade_batch.gd:_b81_raise", "to": "self"},
		{"k": "eq", "id": "p2eq_088", "at": "systems/equip/eq_arcane_batch.gd:_stele_settle", "to": "ally",
			"link": "func _tick_steles[\\s\\S]{0,800}_stele_settle\\(st\\)"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_system.gd:cast_heal", "to": "self"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_system.gd:steal_shield", "to": "self"},
		{"k": "eq", "id": "p2eq_096", "at": "systems/equip/axe_final_forms.gd:holo_on_hit", "to": "ally", "lf": "systems/equip/axe_system.gd", "link": "p2eq_096"},
		{"k": "syn", "id": "盾", "at": "systems/equip/shield_synergy_system.gd:_shockwave", "to": "self"},
		{"k": "syn", "id": "盾", "at": "systems/equip/shield_synergy_system.gd:tick", "to": "self"},
		{"k": "syn", "id": "盾", "at": "systems/equip/shield_synergy_system.gd:on_enemy_died", "to": "ally"},
		{"k": "syn", "id": "盾", "at": "scenes/battle/battle_damage.gd:_holy_convert", "to": "self", "link": "盾羁绊9档"},
		{"k": "syn", "id": "枪", "at": "systems/equip/gun_synergy_system.gd:_turret_two", "to": "ally"},
		{"k": "syn", "id": "法器", "at": "systems/equip/staff_synergy_system.gd:on_healed", "to": "self"},
	],
	"magic-shield": [
		{"k": "eq", "id": "p2eq_012", "at": "systems/equip/magic_shield.gd:seaweed_on_spawn", "to": "self"},
	],
	"dodge": [
		{"k": "pet", "id": "ninja", "sk": "ninjaInstinct", "at": "scenes/battle/battle_spawn.gd:_apply_spawn_passive_one", "arm": "ninja", "to": "self", "v": "{C:NinjaSystem.FOOT_DODGE%}%"},
		{"k": "pet", "id": "ghost", "sk": "ghostPhantom", "at": "systems/skills/ghost_system.gd:_ghost_phantom_hit", "re": "\"selfDodge\":", "to": "self",
			"v": "{C:GhostSystem.RAID_DODGE%}% · {C:GhostSystem.RAID_DODGE_SEC} 秒"},
		{"k": "pet", "id": "hunter", "sk": "hunterStealth", "at": "systems/skills/hunter_system.gd:_sk_hunter_hide", "to": "self",
			"v": "{C:HunterSystem.ROLL_DODGE%}% · {C:HunterSystem.ROLL_DODGE_SEC} 秒"},
	],
	"stealth": [
		{"k": "pet", "id": "ghost", "sk": "ghostPhase", "at": "systems/skills/ghost_system.gd:_sk_ghost_phase", "to": "self", "v": "{C:GhostSystem.PHASE_SEC} 秒"},
	],
	"untargetable": [
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_shell_enter_stealth", "to": "self",
			"lf": MAIN, "link": "\"shellShadow\"[^\\n]*\\n\\s*_shell_sys\\._shell_enter_stealth"},
		{"k": "pet", "id": "lava", "sk": "lavaRage", "at": "systems/skills/lava_system.gd:_lava_volcano_slam", "to": "self",
			"link": "func _lava_transform[\\s\\S]{0,1500}_lava_volcano_slam\\(u\\)"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixRebirth", "at": "systems/skills/phoenix_system.gd:nirvana_begin", "to": "self",
			"v": "{C:PhoenixSystem.NIRVANA_SHOW_SEC} 秒", "link": "涅槃"},
		{"k": "pet", "id": "cyber", "sk": "cyberDrone", "at": "systems/skills/cyber_system.gd:_cyber_assemble_mech", "to": "self",
			"lf": MAIN, "link": "赛博龟阵亡 → 浮游炮组装成机甲"},
		{"k": "minion", "id": "elite", "sk": "eliteHammer", "at": "systems/skills/elite_system.gd:_sk_elite_hammer", "to": "self", "v": "1.6 秒"},
		{"k": "minion", "id": "elite", "pv": "吞噬", "at": "systems/skills/elite_system.gd:_elite_try_consume", "v": "1.7 秒", "link": "^class_name EliteSystem"},
	],
	"reflect": [
		{"k": "pet", "id": "stone", "sk": "stoneWall", "at": "systems/skills/stone_system.gd:reflect_generic", "arm": "stone", "re": "REFLECT_BASE \\+", "to": "self",
			"v": "{C:StoneSystem.REFLECT_BASE%}% + 护甲 / 魔抗加成", "link": "== \"stone\""},
		{"k": "pet", "id": "shell", "sk": "auraAwaken", "at": "systems/skills/shell_system.gd:_shell_apply_awaken", "to": "self",
			"v": "每次觉醒 +{C:ShellSystem.AWAKEN_PCT%}%", "link": "气场觉醒"},
	],
	"cyber-charge": [
		{"k": "pet", "id": "cyber", "sk": "cyberSmartAI", "at": "scenes/battle/battle_spawn.gd:_apply_spawn_passive_one", "arm": "cyber", "to": "self",
			"v": "登场 {C:CyberSystem.AI_START_CHARGE} 层"},
		{"k": "pet", "id": "cyber", "sk": "cyberSmartAI", "at": "systems/skills/cyber_system.gd:_sk_cyber_smart", "to": "self"},
	],
	"chilled": [
		{"k": "pet", "id": "ice", "sk": "frostAura", "at": "scenes/battle/battle_spawn.gd:_apply_spawn_passive_one", "arm": "ice",
			"v": "攻速 移速 龟能 −{C:IceSystem.AURA_SLOW%}% · {C:IceSystem.AURA_SEC} 秒"},
		{"k": "pet", "id": "bamboo", "sk": "bambooSmack", "at": "systems/skills/bamboo_system.gd:_sk_bamboo_smack",
			"v": "移速 −{C:BambooSystem.SMACK_CHILL_DOWN%}% · {C:BambooSystem.SMACK_CHILL_SEC} 秒"},
		{"k": "pet", "id": "crystal", "sk": "crystalBarrier", "at": "systems/skills/crystal_system.gd:_crystal_spike_line",
			"v": "移速 −{C:CrystalSystem.SPIKE_SLOW_PCT%}% · {C:CrystalSystem.SPIKE_SLOW_SEC} 秒",
			"lf": MAIN, "link": "func _tick_bulwark[\\s\\S]{0,900}_crystal_spike_line\\(u\\)"},
		{"k": "pet", "id": "rainbow", "sk": "rainbowPrism", "at": "systems/skills/rainbow_system.gd:_rainbow_enh_prism_proc",
			"v": "攻速 −{C:RainbowSystem.PRISM_CHILL_DOWN%}% · {C:RainbowSystem.PRISM_BUFF_SEC} 秒", "link": "棱镜"},
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_sk_shell_shadow_dive",
			"v": "移速 −{C:ShellSystem.BURN_SLOW_PCT%}%"},
		{"k": "eq", "id": "p2eq_028", "at": "systems/skills/ice_system.gd:_ice_bottle_hit",
			"v": "移速 −{C:IceSystem.VIAL_MOVE_DOWN%}% · 攻速 −{C:IceSystem.VIAL_ASPD_DOWN%}% · {C:IceSystem.VIAL_CHILL_SEC} 秒",
			"lf": EQS, "link": "# 028 冰冻药剂[^\\n]*\\nfunc _eq_ice_throw"},
	],
	"slow": [
		## 糖衣炮弹 10-16 起走普通减速通道(原写寒冰共享槽 spd_dbf_until, 显示成冰寒)
		{"k": "pet", "id": "candy", "sk": "candyBarrage", "at": "systems/skills/candy_system.gd:_sk_candy_barrage",
			"v": "−{C:CandySystem.BARRAGE_SLOW_PCT%}% · {C:CandySystem.BARRAGE_SLOW_SEC} 秒"},
		{"k": "pet", "id": "diamond", "sk": "diamondSmash", "at": "systems/skills/diamond_system.gd:_diamond_smash_impact",
			"v": "−{C:DiamondSystem.SMASH_SLOW_PCT%}% · {C:DiamondSystem.SMASH_SLOW_SEC} 秒"},
		{"k": "pet", "id": "lava", "sk": "lavaQuake", "at": "systems/skills/lava_system.gd:_tick_lava_zones", "v": "−35%",
			"link": "func _lava_quake[\\s\\S]{0,4000}_lava_zones\\.append"},
	],
	"heal-reduce": [
		{"k": "pet", "id": "hunter", "sk": "hunterShot", "at": "systems/skills/hunter_system.gd:_sk_hunter_shot",
			"v": "{C:HunterSystem.SHOT_HEALCUT_PCT%}% · {C:HunterSystem.SHOT_HEALCUT_SEC} 秒"},
		{"k": "pet", "id": "two_head", "sk": "twoHeadDisrupt", "at": "systems/skills/two_head_system.gd:_sk_two_head_disrupt",
			"v": "{C:TwoHeadSystem.DISRUPT_HEALCUT_PCT%}% · {C:TwoHeadSystem.DISRUPT_HEALCUT_SEC} 秒"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixScald", "at": "systems/skills/phoenix_system.gd:_phoenix_scald_hit",
			"v": "{C:PhoenixSystem.SCALD_HEALCUT%}%"},
		{"k": "pet", "id": "phoenix", "sk": "phoenixRebirth", "at": "systems/skills/phoenix_system.gd:nirvana_begin",
			"v": "{C:PhoenixSystem.NIRVANA_HEALCUT%}% · {C:RealtimeBattle3DScene.BUFF_SEC} 秒", "link": "涅槃"},
		{"k": "pet", "id": "shell", "sk": "shellShadow", "at": "systems/skills/shell_system.gd:_shell_basic",
			"v": "{C:ShellSystem.STEALTH_HEALCUT_PCT%}% · {C:ShellSystem.STEALTH_HEALCUT_SEC} 秒",
			"lf": MAIN, "link": "\"shellShadow\"[^\\n]*\\n\\s*_shell_sys\\._shell_enter_stealth"},
		{"k": "pet", "id": "chest", "sk": "chestTreasure", "at": "scenes/battle/battle_damage.gd:_post_hit_hooks", "v": "{C:ChestSystem.POISON_CUT%}% · {C:ChestSystem.POISON_SEC} 秒",
			"link": "宝箱藏宝图 on-hit 战利品"},
		{"k": "minion", "id": "back", "sk": "minionRocket", "at": "systems/skills/hiding_system.gd:_minion_rocket_nuke", "v": "50% · 4 秒"},
		{"k": "eq", "id": "p2eq_067", "at": "systems/equip/eq_potion_batch.gd:_vial_debuff_on", "v": "{C:EqPotionBatch.VIAL_CUT%}%"},
	],
	"energy-lock": [
		{"k": "pet", "id": "stone", "sk": "stoneTaunt", "at": "systems/skills/stone_system.gd:_sk_stone_taunt", "to": "self", "v": "{C:StoneSystem.SLAM_DELAY} 秒"},
		{"k": "pet", "id": "ghost", "sk": "ghostPhase", "at": "systems/skills/ghost_system.gd:_sk_ghost_phase", "to": "self", "v": "{C:GhostSystem.PHASE_SEC} 秒"},
		{"k": "pet", "id": "gambler", "sk": "gamblerFateWheel", "at": "systems/skills/gambler_system.gd:_sk_gambler_fate_wheel", "to": "self"},
		{"k": "pet", "id": "bubble", "sk": "bubbleShield", "at": "systems/skills/bubble_system.gd:_sk_bubble_shield", "to": "self", "v": "{C:BubbleSystem.SHIELD_SEC} 秒"},
		{"k": "pet", "id": "cyber", "sk": "cyberHijack", "at": "systems/skills/cyber_system.gd:_sk_cyber_hijack", "to": "self", "v": "{C:CyberSystem.HIJACK_SEC} 秒"},
		{"k": "pet", "id": "crystal", "sk": "crystalBurst", "at": "systems/skills/crystal_system.gd:_sk_crystal_burst", "to": "self"},
		{"k": "pet", "id": "space", "sk": "starWormhole", "at": "systems/skills/star_system.gd:_sk_star_wormhole", "to": "self"},
		{"k": "pet", "id": "space", "sk": "starWave", "at": "systems/skills/star_system.gd:_sk_star_wave", "to": "self"},
		{"k": "pet", "id": "space", "sk": "starGravityWarp", "at": "systems/skills/star_system.gd:_sk_star_gravity_warp", "to": "self"},
		{"k": "pet", "id": "headless", "sk": "headlessSoulStrike", "at": "systems/skills/headless_system.gd:_sk_headless_soul_charge", "to": "self"},
	],
	"true-fire": [
		{"k": "eq", "id": "p2eq_022", "at": MAIN + ":_fuel_bottle_hit", "v": "{C:EquipSystem.EMBER_TRUEFIRE_SEC} 秒", "lf": EQS, "link": "battle\\._fuel_bottle_hit\\.bind"},
	],
	"corrode": [
		{"k": "syn", "id": "弓箭", "at": "systems/equip/bow_synergy_system.gd:tick"},
		{"k": "eq", "id": "p2eq_076", "at": "systems/equip/eq_bow_batch.gd:on_basic_076"},
	],
	"ink": [
		{"k": "pet", "id": "line", "sk": "lineSketch", "at": MAIN + ":_on_basic_hit", "arm": "line"},
		{"k": "pet", "id": "line", "sk": "lineLink", "at": "systems/skills/line_system.gd:_sk_line_link"},
		{"k": "pet", "id": "line", "sk": "lineInkBomb", "at": "systems/skills/line_system.gd:_sk_line_ink_bomb"},
	],
	"crystal-mark": [
		{"k": "pet", "id": "crystal", "sk": "crystalResonance", "at": "systems/skills/crystal_system.gd:_crystal_stack",
			"lf": MAIN, "link": "\"crystal\":[^\\n]*\\n[^\\n]*\\n\\s*_crystal_sys\\._crystal_stack\\(u, tgt"},
	],
	"shock-mark": [
		{"k": "pet", "id": "lightning", "sk": "lightningStorm", "at": "systems/skills/lightning_system.gd:_lightning_electric",
			"lf": MAIN, "link": "\"lightning\":\\s*\\n\\s*_lightning_sys\\._lightning_electric\\(u, tgt\\)"},
		## 雷暴 / 雷盾 10-16 起改走 _lightning_electric(满层即引爆), 施加点随之移到这里
		{"k": "pet", "id": "lightning", "sk": "lightningBarrage", "at": "systems/skills/lightning_system.gd:_lightning_electric",
			"lf": MAIN, "link": "func _barrage_bolt[\\s\\S]{0,900}_lightning_sys\\._lightning_electric\\(u, e\\)"},
		{"k": "pet", "id": "lightning", "sk": "lightningShield", "at": "systems/skills/lightning_system.gd:_lightning_electric",
			"lf": "scenes/battle/battle_damage.gd", "link": "_lightning_sys\\._lightning_electric\\(u, src\\)"},
	],
	"hunt-mark": [
		{"k": "pet", "id": "hunter", "sk": "hunterShot", "at": "systems/skills/hunter_system.gd:_sk_hunter_shot", "v": "{C:HunterSystem.MARK_SEC} 秒"},
	],
}


## 状态 id → 来源列表(表里的 + 属性表现算的), 同一来源(同龟同技能 / 同装备 / 同羁绊)只留一条。
static func sources_of(status_id: String) -> Array:
	var raw: Array = (SRC.get(status_id, []) as Array).duplicate()
	raw.append_array(derived(status_id))
	var seen := {}
	var out: Array = []
	for e in raw:
		var key := "%s|%s|%s|%s" % [str(e.get("k", "")), str(e.get("id", "")), str(e.get("sk", "")), str(e.get("pv", ""))]
		if seen.has(key):
			var prev: Dictionary = out[int(seen[key])]
			if str(prev.get("v", "")) == "" and str(e.get("v", "")) != "":
				prev["v"] = e["v"]
			continue
		seen[key] = out.size()
		out.append((e as Dictionary).duplicate())
	return out


## 属性型来源: 装备逐星属性 / 羁绊逐档属性里带这一项的, 原样列出(数值就是属性表里的数)。
static func derived(status_id: String) -> Array:
	var field := ""
	match status_id:
		"reflect": field = "reflectPct"
		"dodge": field = "dodgePct"
		_: return []
	var out: Array = []
	var ids: Array = EquipStats.STATS.keys()
	ids.sort()
	for eid in ids:
		var tiers: Array = EquipStats.STATS[eid]
		var vals: PackedStringArray = []
		for t in tiers:
			if t is Dictionary and (t as Dictionary).has(field):
				vals.append(_num(float(t[field])))
		if vals.size() > 0:
			out.append({"k": "eq", "id": str(eid), "to": "self", "v": "/".join(vals) + "%", "derived": field})
	for tname in Phase2Types.TYPES.keys():
		var st: Array = (Phase2Types.TYPES[tname] as Dictionary).get("stats", [])
		var vals2: PackedStringArray = []
		for t in st:
			if t is Dictionary and (t as Dictionary).has(field):
				vals2.append(_num(float(t[field])))
		if vals2.size() > 0:
			out.append({"k": "syn", "id": str(tname), "to": "ally", "v": "/".join(vals2) + "%", "derived": field})
	return out


## 数值串渲染: {C:…} 交给 SkillText(与龟 / 装备文案同一套), {R:类.常量} = (1−值)×100。
static func render_value(v: String) -> String:
	if v == "":
		return ""
	var re := RegEx.create_from_string("[{]R:([^}]+)[}]")
	var out := ""
	var last := 0
	for m in re.search_all(v):
		out += v.substr(last, m.get_start() - last)
		var raw := SkillText.const_of(m.get_string(1))
		out += _num((1.0 - float(raw)) * 100.0) if raw.is_valid_float() else "{R:%s}" % m.get_string(1)
		last = m.get_end()
	out += v.substr(last)
	return SkillText.render_consts(out)


static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return str(snappedf(x, 0.01))
