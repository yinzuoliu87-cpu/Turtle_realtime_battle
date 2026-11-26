"""wire_spear_1126.py —— 长矛羁绊【百夫长】接线(方案书 docs/plans/20261126-长矛羁绊.md)。一次性; assert 计数防重复。"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")


def ed(rel, old, new, cnt=1):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    s = raw.decode("utf-8").replace("\r\n", "\n")
    if new in s and old not in s:
        print("已接过:", rel)
        return
    assert s.count(old) == cnt, (rel, old[:70], s.count(old))
    s = s.replace(old, new)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(p, "wb").write(s.encode("utf-8"))


T = "scripts/gamedata/phase2_types.gd"
ed(T, '''	"面具": {"tiers": [3, 6, 10],''', '''	"长矛": {"tiers": [2, 5, 8, 10], "stats": [{"_echargePct": 5}, {"_echargePct": 10}, {"_echargePct": 16}, {"_echargePct": 24}]},   # 2026-11-26 第六批(取代乐器; 方案书 20261126; 属性 = 用户 11-24 给乐器定的龟能回复速率)
	"面具": {"tiers": [3, 6, 10],''')
ed(T, '''	"面具": "res://assets/sprites/tags/tag-mask.png",''', '''	"面具": "res://assets/sprites/tags/tag-mask.png",
	"长矛": "res://assets/sprites/tags/tag-spear.png",''')
ed(T, '''	"面具": "面具·偷脸",''', '''	"面具": "面具·偷脸",
	"长矛": "长矛·百夫长",''')
ed(T, '''	"面具": [
		"面具提高携带者的减伤。''', '''	"长矛": [
		"长矛提高携带者的龟能回复速率。每个战场开打第 8 秒或我方生命值低于 60% 时，百夫长从天而降，击飞全场敌人。我方每有一件不同的长矛，百夫长按它的星级获得更多生命值与攻击力。",
	],
	"面具": [
		"面具提高携带者的减伤。''')
S = "SpearSynergySystem"
desc = [
    "每件长矛为携带者提供 +5%% 龟能回复速率 · 【百夫长】开打第 {C:%s.SUMMON_AT} 秒或我方生命值低于 {C:%s.TEAM_HP_LINE%%}%% 时，召唤百夫长：{C:%s.HP[0]} 生命值、{C:%s.ATK[0]} 攻击力、{C:%s.RES[0]} 护甲和魔抗，我方每有一件不同的长矛，按其星级每星使百夫长生命值与攻击力提高 {C:%s.STAR_PCT%%}%%。登场时击飞全场敌人 {C:%s.KNOCK_SEC} 秒，造成 {C:%s.ENTRY_COEF%%}%% 攻击力的魔法伤害。龟能满时释放【龟甲阵】：举盾 {C:%s.SHIELD_SEC} 秒，受到的伤害降低 {C:%s.SHIELD_DR%%}%%" % ((S,) * 10),
    "每件长矛为携带者提供 +10%% 龟能回复速率 · 百夫长：{C:%s.HP[1]} 生命值、{C:%s.ATK[1]} 攻击力、{C:%s.RES[1]} 护甲和魔抗。攻击贯穿直线，身后的敌人受到 {C:%s.PIERCE_BEHIND%%}%% 伤害。【龟甲阵】放下盾时横扫，对周围每个敌人造成 {C:%s.SWEEP_COEF%%}%% 攻击力的魔法伤害" % ((S,) * 5),
    "每件长矛为携带者提供 +16%% 龟能回复速率 · 百夫长：{C:%s.HP[2]} 生命值、{C:%s.ATK[2]} 攻击力、{C:%s.RES[2]} 护甲和魔抗。每次攻击使直线上每个敌人失去 1 点护甲和魔抗，每个敌人至多失去 {C:%s.SHRED_CAP} 点。【龟甲阵】举盾期间每 {C:%s.POKE_IV} 秒对周围敌人造成 {C:%s.POKE_COEF%%}%% 攻击力的魔法伤害" % ((S,) * 6),
    "每件长矛为携带者提供 +24%% 龟能回复速率 · 百夫长：{C:%s.HP[3]} 生命值、{C:%s.ATK[3]} 攻击力、{C:%s.RES[3]} 护甲和魔抗。每第 {C:%s.THROW_EVERY} 次攻击改为把长矛掷向最远的敌人，贯穿沿途敌人，造成 {C:%s.THROW_COEF%%}%% 攻击力的物理伤害。【龟甲阵】横扫后，我方身后冲出 {C:%s.CAV_N} 名持矛骑兵，各自冲向一名随机敌人，对途经的敌人造成百夫长 {C:%s.CAV_COEF%%}%% 攻击力的物理伤害并将其击飞" % ((S,) * 7),
]
ed(T, '''	"面具": [
		"每件面具为携带者提供''', '''	"长矛": [
''' + "".join('\t\t"%s",\n' % d for d in desc) + '''	],
	"面具": [
		"每件面具为携带者提供''')

ed("scripts/systems/equip/synergy_system.gd", '''		"dmgRed":   # 面具羁绊''', '''		"_echargePct":   # 长矛羁绊(2026-11-26): 龟能回复速率% → echarge_perm(同装备属性 _echargePct)
			u["echarge_perm"] = float(u.get("echarge_perm", 1.0)) + v / 100.0
		"dmgRed":   # 面具羁绊''')

M = "scripts/scenes/RealtimeBattle3DScene.gd"
ed(M, '''var _mask_syn := MaskSynergySystem.new(self)''', '''var _spear_syn := SpearSynergySystem.new(self)   # 长矛羁绊【百夫长】(2026-11-26 · 方案书 20261126)
var _mask_syn := MaskSynergySystem.new(self)''')
ed(M, '''		_mask_syn.tick(dt)    # 面具''', '''		_spear_syn.tick(dt)   # 长矛: 第 8 秒或我方生命值 < 60% 召唤百夫长(登场全场击飞) + 龟甲阵 / 掷矛 / 骑兵
		_mask_syn.tick(dt)    # 面具''')
ed(M, '''	_mask_syn.reset_match()''', '''	_spear_syn.reset_match()
	_mask_syn.reset_match()''')
ed("scripts/systems/equip/equip_system.gd", '''_mask_sys.on_any_basic(u, tgt)''', '''_mask_sys.on_any_basic(u, tgt); battle._spear_syn.on_any_basic(u, tgt)''')
print("ok")
