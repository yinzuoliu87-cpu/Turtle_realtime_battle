# -*- coding: utf-8 -*-
"""一次性: 召唤物属性的行内字面量提成具名常量(值不变, 对局结果不变), 给图鉴「角色」栏召唤物页读(方案书 20261127d)。

用户 11-27「全部都搞好吧」。手抄必漂(minion_codex 的教训) ⇒ 页面一律读代码常量; 这些数原来直接写在召唤调用行里, 读不到。
保留各文件原行尾(CRLF / LF 混用)。每处替换断言恰好命中一次。
"""
import io, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


_N = [0]
_SKIP = int(os.environ.get("SKIP", "0"))   # 中途断了重跑: 跳过前 N 次已成功的 patch


def patch(rel, subs, inserts=()):
	_N[0] += 1
	if _N[0] <= _SKIP:
		return
	p = os.path.join(ROOT, rel)
	raw = io.open(p, "rb").read().decode("utf-8")
	crlf = "\r\n" in raw
	s = raw.replace("\r\n", "\n")
	for a, b in subs:
		n = s.count(a)
		assert n == 1, (rel, n, a)
		s = s.replace(a, b)
	for anchor, text in inserts:
		i = s.index(anchor)
		j = s.index("\n", i) + 1
		s = s[:j] + text + s[j:]
	if crlf:
		s = s.replace("\n", "\r\n")
	io.open(p, "wb").write(s.encode("utf-8"))
	print("ok", rel)


# ── 058 炮台 / 033 海螺虫(EquipSystem) ──
patch("scripts/systems/equip/equip_system.gd", [], [
	("const TURRET_BUFF_ASPD :=",
	 "const TURRET_HP := [650.0, 1400.0, 2500.0]    # 炮台基础生命(★1/★2/★3; 另加 TURRET_HP_PER_ATK × 携带者攻击力)\n"
	 "const TURRET_ATK := [70.0, 120.0, 180.0]      # 炮台基础攻击(另加携带者攻击力)\n"
	 "const TURRET_RES := [70.0, 85.0, 100.0]       # 携带者存活时炮台的护甲与魔抗(阵亡后归零)\n"),
	("const WORM_HP :=",
	 "const WORM_ATK := [50.0, 80.0, 200.0]         # 海螺虫攻击力(用户 2026-07-30)\n"),
])
patch("scripts/systems/equip/equip_system.gd", [
	('_spawn_summon(u, "worm", float(WORM_HP[si]), [50.0, 80.0, 200.0][si],', '_spawn_summon(u, "worm", float(WORM_HP[si]), float(WORM_ATK[si]),'),
])
patch("scripts/systems/equip/eq_summons.gd", [
	('_spawn_summon(u, "turret", [650.0, 1400.0, 2500.0][si] + EquipSystem.TURRET_HP_PER_ATK * float(u.get("atk", 0.0)), [70.0, 120.0, 180.0][si] + float(u.get("atk", 0.0)),',
	 '_spawn_summon(u, "turret", float(EquipSystem.TURRET_HP[si]) + EquipSystem.TURRET_HP_PER_ATK * float(u.get("atk", 0.0)), float(EquipSystem.TURRET_ATK[si]) + float(u.get("atk", 0.0)),'),
	('var res: float = ([70.0, 85.0, 100.0][si] if u.get("alive", false) else 0.0)', 'var res: float = (float(EquipSystem.TURRET_RES[si]) if u.get("alive", false) else 0.0)'),
	('_spawn_summon(u, "skeleton", [16.0, 31.0, 55.0][si], [3.0, 5.0, 8.0][si], {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / 1.2, "atk_range": 70.0, "melee": true, "move_spd": 110.0})',
	 '_spawn_summon(u, "skeleton", float(SKEL_HP[si]), float(SKEL_ATK[si]), {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / SKEL_ASPD, "atk_range": SKEL_RANGE, "melee": true, "move_spd": SKEL_MOVE})'),
	('sk["summon_life"] = [13.0, 17.0, 23.0][si]', 'sk["summon_life"] = float(SKEL_LIFE[si])'),
	('sk["boom_pct_true"] = [0.08, 0.13, 0.20][si]', 'sk["boom_pct_true"] = float(SKEL_BOOM_PCT[si])'),
	('sk["boom_radius"] = 200.0', 'sk["boom_radius"] = SKEL_BOOM_R'),
], [
	("extends RefCounted",
	 "\n## 032 亡灵骷髅(用户 2026-08-01 定): 图鉴召唤物页读这几条(11-27 从召唤行提出来, 值不变)\n"
	 "const SKEL_HP := [16.0, 31.0, 55.0]\n"
	 "const SKEL_ATK := [3.0, 5.0, 8.0]\n"
	 "const SKEL_ASPD := 1.2                 # 每秒攻击次数\n"
	 "const SKEL_RANGE := 70.0\n"
	 "const SKEL_MOVE := 110.0\n"
	 "const SKEL_LIFE := [13.0, 17.0, 23.0]  # 存活秒数, 到点爆炸\n"
	 "const SKEL_BOOM_PCT := [0.08, 0.13, 0.20]   # 爆炸: 目标最大生命值 × 它 真实伤害\n"
	 "const SKEL_BOOM_R := 200.0\n"
	 "const SKEL_DMG_CAP := 1.0              # 受到的任何伤害(含真伤)恒为它(闸在 _mitigate_incoming, 那边写的是 1.0)\n"),
])

# ── 034 大熊 ──
patch("scripts/systems/equip/equip_tick_system.gd", [], [
	("const BEAR_RESIST :=",
	 "const BEAR_HP := [1600.0, 3000.0, 15000.0]   # 大熊生命(★1/★2/★3)\n"
	 "const BEAR_ATK := [70.0, 120.0, 2000.0]      # 大熊攻击\n"),
])
patch("scripts/scenes/RealtimeBattle3DScene.gd", [
	('_spawn_summon(u, "bear", [1600.0, 3000.0, 15000.0][si], [70.0, 120.0, 2000.0][si],', '_spawn_summon(u, "bear", float(EquipTickSystem.BEAR_HP[si]), float(EquipTickSystem.BEAR_ATK[si]),'),
])

# ── 106 遥控炸弹 / 107 武士刀小将 ──
patch("scripts/systems/equip/eq_bomb_batch.gd", [
	('"label": "遥控炸弹", "spr_id": "eq-remote-bomb", "col_size": 34.0, "hp_w": 40.0,\n\t\t "atk_interval": 1.0, "atk_range": 30.0, "melee": true})',
	 '"label": "遥控炸弹", "spr_id": "eq-remote-bomb", "col_size": 34.0, "hp_w": 40.0,\n\t\t "atk_interval": 1.0, "atk_range": REMOTE_RANGE, "melee": true})'),
	('"label": "武士刀小将", "spr_id": "eq-katana", "col_size": 46.0, "hp_w": 36.0,\n\t\t "atk_interval": 1.0, "atk_range": 60.0, "melee": true})',
	 '"label": "武士刀小将", "spr_id": "eq-katana", "col_size": 46.0, "hp_w": 36.0,\n\t\t "atk_interval": 1.0 / KATANA_ASPD, "atk_range": KATANA_RANGE, "melee": true})'),
], [
	("const REMOTE_HP :=", "const REMOTE_RANGE := 30.0      # 追身距离(不攻击)\n"),
	("const KATANA_EN_MAX :=", "const KATANA_ASPD := 1.0        # 每秒攻击次数\nconst KATANA_RANGE := 60.0\n"),
])

# ── 130 舞狮 ──
patch("scripts/systems/equip/eq_mask_batch.gd", [
	('"label": "舞狮", "spr_id": "eq-mask-lion", "col_size": 52.0, "hp_w": 40.0,\n\t\t "atk_interval": 1.0, "atk_range": 70.0, "melee": true})',
	 '"label": "舞狮", "spr_id": "eq-mask-lion", "col_size": 52.0, "hp_w": 40.0,\n\t\t "atk_interval": 1.0 / LION_ASPD, "atk_range": LION_RANGE, "melee": true})'),
], [
	("const LION_HP :=", "const LION_ASPD := 1.0          # 每秒攻击次数\nconst LION_RANGE := 70.0\n"),
])

# ── 123 骷髅三种 ──
patch("scripts/systems/equip/eq_magic_batch.gd", [
	('"atk_interval": 1.0, "atk_range": 60.0, "melee": true})\n\t\t"skel_mage":', '"atk_interval": SKW_IV, "atk_range": SKW_RANGE, "melee": true})\n\t\t"skel_mage":'),
	('"atk_interval": 1.3, "atk_range": 420.0, "melee": false})', '"atk_interval": SKM_IV, "atk_range": SKM_RANGE, "melee": false})'),
	('"atk_interval": 1.2, "atk_range": 400.0, "melee": false})', '"atk_interval": SKP_IV, "atk_range": SKP_RANGE, "melee": false})'),
], [
	("const SKW_HP :=",
	 "const SKW_IV := 1.0       # 攻击间隔(秒)\nconst SKW_RANGE := 60.0\n"
	 "const SKM_IV := 1.3\nconst SKM_RANGE := 420.0\n"
	 "const SKP_IV := 1.2\nconst SKP_RANGE := 400.0\n"),
])

# ── 115 暗影忍者 ──
patch("scripts/systems/equip/eq_dagger_batch.gd", [
	('"atk_interval": 0.8, "atk_range": 60.0, "melee": true, "crit": float(NINJA_CRIT[si])})', '"atk_interval": NINJA_IV, "atk_range": NINJA_RANGE, "melee": true, "crit": float(NINJA_CRIT[si])})'),
], [
	("const NINJA_HP :=", "const NINJA_IV := 0.8           # 攻击间隔(秒)\nconst NINJA_RANGE := 60.0\n"),
])

# ── 072 蛋糕礼盒 ──
patch("scripts/systems/equip/eq_food_batch.gd", [
	('var per: float = [20.0, 30.0, 60.0][si]   # 每个锁定自己的敌人 +20/30/60 双抗', 'var per: float = float(BOX_RES_PER_LOCKER[si])   # 每个锁定自己的敌人 +双抗'),
	('battle._atk_dmg(u, 1.0, tgt), Color("#ffd0dc"), 0.0, false, true)', 'battle._atk_dmg(u, BOX_HIT_COEF, tgt), Color("#ffd0dc"), 0.0, false, true)'),
	('var heal: float = [50.0, 70.0, 120.0][si]     # 每秒回 50/70/120 生命', 'var heal: float = float(BOX_FIELD_HEAL[si])     # 每秒回生命'),
	('var energy: float = [2.0, 4.0, 6.0][si]       # 每秒给 2/4/6 龟能', 'var energy: float = float(BOX_FIELD_ENERGY[si])       # 每秒给龟能'),
	('var hp_pct: float = [0.20, 0.40, 1.00][si]   # 携带者最大生命的 20/40/100%', 'var hp_pct: float = float(BOX_SPLIT_HP_PCT[si])   # 携带者最大生命的百分比'),
	('b["eq_state"] = {"p2eq_072": {"opened": true, "field_iv": 8.0, "field_t": 4.0}}', 'b["eq_state"] = {"p2eq_072": {"opened": true, "field_iv": BOX_SPLIT_FIELD_IV, "field_t": BOX_SPLIT_FIELD_FIRST}}'),
], [
	("const BOX_FIELD_SEC :=",
	 "const BOX_RES_PER_LOCKER := [20.0, 30.0, 60.0]   # 每个锁定礼盒的敌人 +双抗(★1/★2/★3)\n"
	 "const BOX_FIELD_HEAL := [50.0, 70.0, 120.0]      # 蛋糕领域: 每秒回生命\n"
	 "const BOX_FIELD_ENERGY := [2.0, 4.0, 6.0]        # 蛋糕领域: 每秒给龟能\n"
	 "const BOX_HIT_COEF := 1.0                        # 礼盒攻击 × 攻击力 物理\n"
	 "const BOX_SPLIT_HP_PCT := [0.20, 0.40, 1.00]     # 携带者阵亡分裂出的礼盒: 携带者最大生命 ×\n"
	 "const BOX_SPLIT_FIELD_IV := 8.0                  # 分裂礼盒每隔几秒放一次蛋糕领域\n"
	 "const BOX_SPLIT_FIELD_FIRST := 4.0               # 分裂礼盒第一次放领域在第几秒\n"),
])

# ── 077 小手枪 / 079 急救塔 ──
patch("scripts/systems/equip/eq_gun_batch.gd", [
	('_spawn_pistol(u, si, [30.0, 60.0, 100.0][si], [15.0, 25.0, 40.0][si])', '_spawn_pistol(u, si, float(PISTOL_HP[si]), float(PISTOL_ATK[si]))'),
	('_spawn_tower(u, si, [700.0, 1200.0, 2500.0][si], [15.0, 20.0, 30.0][si], [50.0, 70.0, 100.0][si])', '_spawn_tower(u, si, float(TOWER_HP[si]), float(TOWER_ATK[si]), float(TOWER_RES[si]))'),
	('p["_dmg_cap_val"] = 2.0', 'p["_dmg_cap_val"] = PISTOL_DMG_CAP'),
	('p["_heal_cap_val"] = 1.0', 'p["_heal_cap_val"] = PISTOL_HEAL_CAP'),
	('battle._damage._apply_damage_from(p, tgt, battle._atk_dmg(p, 1.0, tgt), COL_PHYS, 0.0, false, true)', 'battle._damage._apply_damage_from(p, tgt, battle._atk_dmg(p, PISTOL_COEF, tgt), COL_PHYS, 0.0, false, true)'),
	('var hp_pct: float = [0.01, 0.015, 0.02][si]', 'var hp_pct: float = float(TOWER_MAXHP_PCT[si])'),
	('var heal: float = [10.0, 15.0, 20.0][si]', 'var heal: float = float(TOWER_HEAL[si])'),
	('var gold_pct: float = [0.60, 0.80, 1.00][clampi(int(battle._synergy.tier_for(t,', 'var gold_pct: float = TOWER_GOLD_PCT[clampi(int(battle._synergy.tier_for(t,'),
	('var per_gold: int = [4, 3, 2][clampi(', 'var per_gold: int = TOWER_GOLD_EVERY[clampi('),
	('battle._damage._apply_damage_from(t, vt, battle._atk_dmg(t, 1.0, vt), COL_PHYS, 0.0, false, true)', 'battle._damage._apply_damage_from(t, vt, battle._atk_dmg(t, TOWER_COEF, vt), COL_PHYS, 0.0, false, true)'),
], [
	("const PISTOL_PEN_PER_SHOT :=",
	 "const PISTOL_HP := [30.0, 60.0, 100.0]     # 小手枪生命(★1/★2/★3)\n"
	 "const PISTOL_ATK := [15.0, 25.0, 40.0]     # 小手枪攻击\n"
	 "const PISTOL_COEF := 1.0                   # 每发 × 攻击力 物理\n"
	 "const PISTOL_DMG_CAP := 2.0                # 携带者存活时受到的任何伤害封顶\n"
	 "const PISTOL_HEAL_CAP := 1.0               # 受到的治疗封顶\n"
	 "const TOWER_HP := [700.0, 1200.0, 2500.0]  # 急救塔生命\n"
	 "const TOWER_ATK := [15.0, 20.0, 30.0]      # 急救塔攻击\n"
	 "const TOWER_RES := [50.0, 70.0, 100.0]     # 急救塔护甲与魔抗\n"
	 "const TOWER_COEF := 1.0                    # 每发 × 攻击力 物理\n"
	 "const TOWER_MAXHP_PCT := [0.01, 0.015, 0.02]   # 每发另加目标最大生命值 × 它 魔法伤害\n"
	 "const TOWER_HEAL := [10.0, 15.0, 20.0]     # 每发治疗生命百分比最低的友军(金弹翻倍)\n"
	 "const TOWER_GOLD_PCT := [0.60, 0.80, 1.00] # 枪羁绊 (1)(2)(3) 档: 金弹真实伤害比例\n"
	 "const TOWER_GOLD_EVERY := [4, 3, 2]        # 枪羁绊各档: 每几发一颗金弹\n"),
])

# ── 龟技能召唤物 / 龟蛋 / 召唤默认值 ──
patch("scripts/scenes/battle/battle_spawn.gd", [
	('"move_spd": 90.0, "atk_range": CrystalSystem.ORB_RANGE, "no_basic": true,', '"move_spd": CrystalSystem.ORB_MOVE, "atk_range": CrystalSystem.ORB_RANGE, "no_basic": true,'),
	('"move_spd": 40.0, "atk_range": PirateSystem.SHIP_RANGE, "no_basic": true,', '"move_spd": PirateSystem.SHIP_MOVE, "atk_range": PirateSystem.SHIP_RANGE, "no_basic": true,'),
	('battle._damage._apply_damage_from(src, e, battle._atk_dmg(uu, 1.0, e, true), Color("#e8c07a"), 0.0, true)', 'battle._damage._apply_damage_from(src, e, battle._atk_dmg(uu, PirateSystem.SHIP_CHARGE_COEF, e, true), Color("#e8c07a"), 0.0, true)'),
	('var _egg_res: float = 60.0 + 15.0 * float(int(spec.get("level", u.get("level", 1))))', 'var _egg_res: float = EGG_RES_BASE + EGG_RES_PER_LV * float(int(spec.get("level", u.get("level", 1))))'),
	('"atk_interval": float(behavior.get("atk_interval", 1.2)),', '"atk_interval": float(behavior.get("atk_interval", SUMMON_DEFAULT_IV)),'),
	('"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else 70.0)),', '"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else SUMMON_DEFAULT_RANGE)),'),
], [
	("const SUMMON_DEFAULT_SPD :=",
	 "const SUMMON_DEFAULT_IV := 1.2      # 召唤物没给攻击间隔时的默认值(秒)\n"
	 "const SUMMON_DEFAULT_RANGE := 70.0  # 召唤物没给射程时的默认值\n"
	 "const EGG_RES_BASE := 60.0          # 龟蛋护甲与魔抗 = 它 + EGG_RES_PER_LV × 等级(用户 2026-07-19), 围栏立着时另加 EGG_FENCE_RES\n"
	 "const EGG_RES_PER_LV := 15.0\n"),
])
patch("scripts/systems/skills/crystal_system.gd", [], [("const ORB_HP_PCT :=", "const ORB_MOVE := 90.0           # 水晶球移速\n")])
patch("scripts/systems/skills/pirate_system.gd", [], [("const SHIP_HP_SCALE :=", "const SHIP_MOVE := 40.0              # 海盗船移速(用户「再慢一点」)\n")])
patch("scripts/systems/skills/cyber_system.gd", [
	('"move_spd": 95.0, "atk_interval": 1.0, "atk_range": MECH_RANGE,', '"move_spd": MECH_MOVE, "atk_interval": 1.0 / MECH_ASPD, "atk_range": MECH_RANGE,'),
], [("const MECH_RANGE :=", "const MECH_MOVE := 95.0          # 机甲移速\nconst MECH_ASPD := 1.0          # 机甲每秒攻击次数\n")])
patch("scripts/systems/skills/candy_system.gd", [
	('"no_basic": true, "no_move": true, "self_decay": 0.08, "death_aoe": BOMB_DEATH_AOE,', '"no_basic": true, "no_move": true, "self_decay": BOMB_DECAY_PCT, "death_aoe": BOMB_DEATH_AOE,'),
])
patch("scripts/scenes/battle/dual_lane_flow.gd", [
	("static func egg_max_for(lv: int) -> float:\n\treturn 3000.0 + 300.0 * float(lv)", "static func egg_max_for(lv: int) -> float:\n\treturn EGG_HP_BASE + EGG_HP_PER_LV * float(lv)"),
], [("extends RefCounted", "\nconst EGG_HP_BASE := 3000.0     # 龟蛋满血 = 它 + EGG_HP_PER_LV × 等级(用户 2026-07-19)\nconst EGG_HP_PER_LV := 300.0\n")])
print("done")
