"""status_sources_mask_spear_1127.py —— 图鉴状态页来源表补登面具 / 长矛 / 筹码批 16 处施加点(verify_codex_status_sources ③ 抓到)
一次性; 原行尾二进制读写; 每条插到对应状态列表的末尾。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MB = "systems/equip/eq_mask_batch.gd"
SB = "systems/equip/eq_spear_batch.gd"
SS = "systems/equip/spear_synergy_system.gd"

ADD = {
    "stun": [
        r'{"k": "eq", "id": "p2eq_130", "at": "%s:_lion_hit", "link": "130 舞狮头[\\s\\S]*func _lion_hit"},   # 130 舞狮冲撞眩晕(11-27)' % MB,
        r'{"k": "eq", "id": "p2eq_140", "at": "%s:on_basic", "arm": "p2eq_140"},   # 140 骑枪冲势耗尽那一下(11-27)' % SB,
        r'{"k": "eq", "id": "p2eq_138", "at": "%s:_harpoon", "link": "\"p2eq_138\":[\\s\\S]{0,300}_harpoon\\("},   # 138 鱼叉命中眩晕 + 拽回(11-27)' % SB,
        r'{"k": "eq", "id": "p2eq_145", "at": "%s:_eternal", "link": "\"p2eq_145\":[\\s\\S]{0,400}_eternal\\("},   # 145 永恒之枪(待用户重新设计, 11-27)' % SB,
    ],
    "airborne": [
        r'{"k": "eq", "id": "p2eq_130", "at": "%s:_lion_hit", "link": "130 舞狮头[\\s\\S]*func _lion_hit"},   # 130 舞狮冲撞击退(11-27)' % MB,
        r'{"k": "eq", "id": "p2eq_140", "at": "%s:on_basic", "arm": "p2eq_140"},   # 140 骑枪冲势耗尽击退(11-27)' % SB,
        r'{"k": "eq", "id": "p2eq_143", "at": "%s:_tick_slams", "link": "_slams: Array = \\[\\][^\\n]*143"},   # 143 砸地击飞(11-27)' % SB,
        r'{"k": "syn", "id": "长矛", "at": "%s:_land"},   # 长矛羁绊百夫长从天而降(11-27)' % SS,
        r'{"k": "syn", "id": "长矛", "at": "%s:_tick_cavs"},   # 长矛羁绊骑兵冲锋(11-27)' % SS,
    ],
    "taunt": [
        r'{"k": "eq", "id": "p2eq_131", "at": "%s:on_unit_cast", "link": "func on_unit_cast[\\s\\S]{0,600}p2eq_131"},   # 131 小丑面具放技能嘲讽(11-27)' % MB,
    ],
    "bleed": [
        r'{"k": "eq", "id": "p2eq_139", "at": "%s:_javelin", "link": "\"p2eq_139\":[\\s\\S]{0,400}_javelin\\("},   # 139 标枪流血(11-27)' % SB,
    ],
    "shield": [
        r'{"k": "eq", "id": "p2eq_131", "at": "%s:on_unit_cast", "to": "self", "link": "func on_unit_cast[\\s\\S]{0,600}p2eq_131"},   # 131 小丑面具放技能给自己护盾(11-27)' % MB,
        r'{"k": "eq", "id": "p2eq_142", "at": "%s:_tick_shield_spear", "to": "self", "link": "\"p2eq_142\":[\\s\\S]{0,200}_tick_shield_spear\\("},   # 142 盾矛(11-27)' % SB,
    ],
    "untargetable": [
        r'{"k": "eq", "id": "p2eq_132", "at": "%s:tick_unit", "arm": "p2eq_132", "to": "self"},   # 132 鬼面半血潜行(11-27)' % MB,
        r'{"k": "eq", "id": "p2eq_134", "at": "%s:revive", "to": "self", "link": "func revive[\\s\\S]{0,400}_ven_ready"},   # 134 威尼斯面具倒地复活(11-27)' % MB,
        r'{"k": "eq", "id": "p2eq_154", "at": "%s:revive", "to": "self", "link": "func revive[\\s\\S]{0,600}_chip_revive_ready"},   # 154 棕色筹码倒地复活(同一套流程, 11-27)' % MB,
    ],
}


def rw(rel, fn):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    s = fn(s)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


def add_sources(s):
    for key, rows in ADD.items():
        head = '\n\t"%s": [\n' % key
        assert s.count(head) == 1, key
        i = s.index(head)
        j = s.index("\n\t],", i)
        s = s[:j] + "".join("\n\t\t" + r for r in rows) + s[j:]
    return s


rw("scripts/scenes/codex/status_sources.gd", add_sources)


def add_ignore(s):
    a = '\t"stun|scenes/battle/battle_damage.gd:_stun#": "眩晕的通用入口",\n'
    assert s.count(a) == 1
    return s.replace(a, a + '\t"untargetable|scenes/battle/battle_damage.gd:revive_begin#": "复活的通用入口(真正的来源是调它的天使 / 凤凰 / 驯服 / 威尼斯面具 / 棕色筹码 / 斧头, 已逐个认领; 11-27)",\n')


rw("tests/verify_codex_status_sources.gd", add_ignore)
print("ok")
