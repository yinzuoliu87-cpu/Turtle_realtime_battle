# -*- coding: utf-8 -*-
"""批3 内容层: 生成 35 件新装备 (p2eq_060 ~ p2eq_094)。方案书 docs/plans/20260802-装备扩充.md §7 批3。

用法: python tools/oneoff/gen_batch3_items.py 3a      # 只写 3a 那一批
      python tools/oneoff/gen_batch3_items.py --check  # 只对账不写盘

★★这 35 件【全部是纯属性装备, 不带主动效果】—— 这是一个明确的范围决定, 不是偷懒:
  · 方案书 §4.4.3 已经量化过, 加 35 件的真正收益是【类型曝光被拉平】(标准差降 57~70%),
    让"想凑哪个羁绊"由玩家决定而不是由"这个类型有没有对应费用档的货"决定 ——
    这条收益与"每件有没有主动效果"完全无关。
  · 35 条新的主动效果 = 35 段没有任何门禁覆盖过的战斗代码, 且要和现有 59 件的触发钩互相干涉。
    对照: 靶向器【一件】的工作量"可能超过其余 12 条之和"(20260801-装备批次13条.md:174)。
  · 文案与实装因此 100% 一致。本项目最恨的就是"文案说得到、实装做不到"
    (方案书 R23 的净化就卡在这上面)。纯属性件的 effectDesc 只写风味, 不承诺任何机制。
  ⇒ 日后想给某件补主动效果, 逐件加即可, 【不影响池子的任何数学】(张数只看费用)。

★属性量级取自现有 59 件的实测区间(按费用分档), 不是拍脑袋:
  1费 atk 5~12→20~41 / hp 20~100→60~300 / def 5→18~20 / mr 8→18
  2费 atk 7~16→20~50 / hp 20~100→80~400 / armorPen 3~4→10~12
  3费 atk 8~25→21~70 / hp 20~100→80~300 / magicPen 5~8→13~27
  4费 atk 15~20→70~120 / hp 80~100→200~5000 / armorPen 5~10→18~30
  5费 atk 20~45→200~500 / hp 50~200→1000~4000 / armorPen 10~15→30~50
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EQ_JSON = os.path.join(ROOT, 'data', 'phase2-equipment.json')
TY_JSON = os.path.join(ROOT, 'data', 'p2eq-types.json')
STATS_GD = os.path.join(ROOT, 'scripts', 'gamedata', 'equip_stats.gd')

# 每个类型的属性身份（新字段用在最贴题的类型上）：
#   剑=攻击力+暴击 · 弓箭=暴击+暴伤+射程 · 枪=护甲穿透+攻速 · 盾=护甲+生命
#   药水=龟能+充能速率 · 食物=生命+治疗增幅 · 法器=法穿+龟能 · 奇械=魔抗+充能
#   灵物=闪避+移速 · 遗物=吸血+攻击力
# 每条: (id尾号, 批次, 类型, 费用, 名字, emoji, [1★,2★,3★] 属性, 风味文案)
ITEMS = [
    # ── 3a: 灵物 +5 / 药水 +4 / 食物 +4 = 13 件 ─────────────────────────
    (60, '3a', '灵物', 1, '磷光水母伞', '🎐', [{'dodgePct': 5, 'hp': 40}, {'dodgePct': 9, 'hp': 90}, {'dodgePct': 15, 'hp': 180}], '深海里飘着的一顶伞，看得见摸不着。'),
    (61, '3a', '灵物', 2, '游魂贝铃', '🔔', [{'dodgePct': 6, '_mspdPct': 5}, {'dodgePct': 11, '_mspdPct': 9}, {'dodgePct': 18, '_mspdPct': 15}], '响一声，海里就少一个影子。'),
    (62, '3a', '灵物', 2, '雾行海葵', '🌫️', [{'dodgePct': 6, 'hp': 60}, {'dodgePct': 11, 'hp': 140}, {'dodgePct': 18, 'hp': 300}], '它不躲，是你根本没看清它在哪。'),
    (63, '3a', '灵物', 3, '幽影墨囊', '🖤', [{'dodgePct': 8, '_mspdPct': 6}, {'dodgePct': 14, '_mspdPct': 11}, {'dodgePct': 24, '_mspdPct': 18}], '一口墨，把自己从战场上抹掉半秒。'),
    (64, '3a', '灵物', 4, '深渊招魂螺', '🐚', [{'dodgePct': 12, 'hp': 100}, {'dodgePct': 22, 'hp': 260}, {'dodgePct': 38, 'hp': 600}], '吹响它，海沟底下有东西会应你。'),
    (65, '3a', '药水', 3, '涌泉苔药剂', '🧴', [{'_maxEnergy': 20, '_echargePct': 8}, {'_maxEnergy': 35, '_echargePct': 14}, {'_maxEnergy': 60, '_echargePct': 24}], '喝下去像有股泉水从背甲里往上顶。'),
    (66, '3a', '药水', 4, '狂潮浓缩液', '⚗️', [{'_maxEnergy': 25, '_echargePct': 10}, {'_maxEnergy': 45, '_echargePct': 18}, {'_maxEnergy': 80, '_echargePct': 30}], '一小瓶，够一只龟连放三次大招。'),
    (67, '3a', '药水', 4, '猎人的酒囊', '🍶', [{'_maxEnergy': 20, 'atk': 15}, {'_maxEnergy': 35, 'atk': 40}, {'_maxEnergy': 60, 'atk': 95}], '黑礁的老规矩：开打前先灌一口。'),
    (68, '3a', '药水', 5, '万灵龟血', '🩸', [{'_maxEnergy': 40, '_echargePct': 12, 'atk': 25}, {'_maxEnergy': 70, '_echargePct': 22, 'atk': 70}, {'_maxEnergy': 120, '_echargePct': 38, 'atk': 220}], '传说只有活过三百年的龟才淌得出这种血。'),
    (69, '3a', '食物', 3, '珊瑚糖糕', '🍥', [{'hp': 90, 'healAmp': 10}, {'hp': 200, 'healAmp': 18}, {'hp': 420, 'healAmp': 30}], '珊瑚学院食堂的招牌，甜得发齁。'),
    (70, '3a', '食物', 4, '深海龟粮砖', '🍞', [{'hp': 120, 'def': 8}, {'hp': 300, 'def': 18}, {'hp': 700, 'def': 40}], '硬得能当盾牌用，据说也真有龟这么用过。'),
    (71, '3a', '食物', 4, '暖流海带汤', '🍲', [{'hp': 110, 'healAmp': 14}, {'hp': 280, 'healAmp': 26}, {'hp': 650, 'healAmp': 45}], '喝完从壳里暖到爪尖。'),
    (72, '3a', '食物', 5, '百年龟苓宴', '🍱', [{'hp': 200, 'healAmp': 18, 'def': 10}, {'hp': 550, 'healAmp': 32, 'def': 24}, {'hp': 1400, 'healAmp': 55, 'def': 55}], '一桌下去，能扛住三轮围攻。'),
    # ── 3b: 弓箭 +4 / 枪 +4 / 盾 +2 / 剑 +2 = 12 件 ─────────────────────
    (73, '3b', '弓箭', 1, '藤蔓短弓', '🏹', [{'crit': 0.10, '_rangePct': 5}, {'crit': 0.18, '_rangePct': 9}, {'crit': 0.30, '_rangePct': 15}], '海边藤条随手一绕，射得比看上去远。'),
    (74, '3b', '弓箭', 1, '骨簇箭袋', '🎯', [{'crit': 0.10, 'atk': 8}, {'crit': 0.18, 'atk': 18}, {'crit': 0.30, 'atk': 38}], '每一支都削自不同的鱼骨。'),
    (75, '3b', '弓箭', 2, '鹰眼镜片', '🔍', [{'crit': 0.12, '_rangePct': 6}, {'crit': 0.22, '_rangePct': 11}, {'crit': 0.38, '_rangePct': 18}], '看得清才射得准，这道理谁都懂。'),
    (76, '3b', '弓箭', 4, '腐蚀重弩', '☠️', [{'crit': 0.20, 'critDmg': 0.15, '_rangePct': 8}, {'crit': 0.35, 'critDmg': 0.28, '_rangePct': 14}, {'crit': 0.58, 'critDmg': 0.50, '_rangePct': 24}], '深渊议会的制式装备，箭头淬过东西。'),
    (77, '3b', '枪', 1, '铜管手铳', '🔫', [{'armorPen': 4, '_aspdPct': 5}, {'armorPen': 9, '_aspdPct': 9}, {'armorPen': 18, '_aspdPct': 15}], '打得不重，但打得快。'),
    (78, '3b', '枪', 2, '双管贝壳枪', '💥', [{'armorPen': 5, '_aspdPct': 6}, {'armorPen': 11, '_aspdPct': 11}, {'armorPen': 22, '_aspdPct': 18}], '两发一起出膛，后坐力也是两倍。'),
    (79, '3b', '枪', 3, '军械库连射机', '⚙️', [{'armorPen': 7, '_aspdPct': 8}, {'armorPen': 15, '_aspdPct': 15}, {'armorPen': 30, '_aspdPct': 25}], '深海军械库量产型，胜在不卡壳。'),
    (80, '3b', '枪', 5, '穿甲重炮', '🎇', [{'armorPen': 14, '_aspdPct': 10, 'atk': 30}, {'armorPen': 30, '_aspdPct': 18, 'atk': 90}, {'armorPen': 55, '_aspdPct': 30, 'atk': 260}], '不讲技巧，就是厚甲也给你捅穿。'),
    (81, '3b', '盾', 1, '藤编圆盾', '🛡️', [{'def': 6, 'hp': 50}, {'def': 13, 'hp': 120}, {'def': 22, 'hp': 260}], '轻，便宜，挡得住第一下。'),
    (82, '3b', '盾', 2, '砗磲护心甲', '🐚', [{'def': 7, 'hp': 70}, {'def': 15, 'hp': 170}, {'def': 26, 'hp': 380}], '砗磲壳磨薄了贴在胸前，凉丝丝的。'),
    (83, '3b', '剑', 3, '潮汐细剑', '🗡️', [{'atk': 18, 'crit': 0.10}, {'atk': 42, 'crit': 0.18}, {'atk': 92, 'crit': 0.30}], '出手像退潮，收手像涨潮。'),
    (84, '3b', '剑', 4, '血牙巨剑', '⚔️', [{'atk': 22, 'crit': 0.12}, {'atk': 55, 'crit': 0.22}, {'atk': 125, 'crit': 0.38}], '血牙帮的老家伙，砍卷了刃也不换。'),
    # ── 3c: 奇械 +3 / 法器 +3 / 遗物 +4 = 10 件 ─────────────────────────
    (85, '3c', '奇械', 1, '铜齿护符', '⚙️', [{'mr': 9, '_echargePct': 5}, {'mr': 19, '_echargePct': 9}, {'mr': 34, '_echargePct': 15}], '深海工坊的学徒作品，齿轮咬得还算齐。'),
    (86, '3c', '奇械', 5, '极地反冲装置', '❄️', [{'mr': 18, 'def': 12, '_echargePct': 10}, {'mr': 45, 'def': 30, '_echargePct': 18}, {'mr': 130, 'def': 80, '_echargePct': 30}], '被法术打中时会"咔"地弹一下，然后你就没那么疼了。'),
    (87, '3c', '奇械', 5, '深渊铸币机', '🪙', [{'mr': 20, 'hp': 150, '_echargePct': 8}, {'mr': 50, 'hp': 420, '_echargePct': 14}, {'mr': 145, 'hp': 1200, '_echargePct': 24}], '边打边印钱，工坊最得意的发明。'),
    (88, '3c', '法器', 1, '潮汐骨杖', '🔮', [{'magicPen': 5, '_maxEnergy': 12}, {'magicPen': 11, '_maxEnergy': 22}, {'magicPen': 20, '_maxEnergy': 40}], '握着它，能听见远处海浪的节拍。'),
    (89, '3c', '法器', 1, '蚀月符纸', '🌙', [{'magicPen': 5, '_echargePct': 6}, {'magicPen': 11, '_echargePct': 11}, {'magicPen': 20, '_echargePct': 18}], '月亏那晚写的符，字迹现在还在动。'),
    (90, '3c', '法器', 5, '万潮法典', '📕', [{'magicPen': 18, '_maxEnergy': 45, '_echargePct': 12}, {'magicPen': 42, '_maxEnergy': 80, '_echargePct': 22}, {'magicPen': 110, '_maxEnergy': 150, '_echargePct': 38}], '潮汐议会的全部记载，重得两只龟才抬得动。'),
    (91, '3c', '遗物', 1, '远古龟甲片', '🏺', [{'_lifestealPct': 4, 'hp': 50}, {'_lifestealPct': 8, 'hp': 120}, {'_lifestealPct': 14, 'hp': 260}], '不知道是谁的甲，反正比你老得多。'),
    (92, '3c', '遗物', 2, '沉船罗盘', '🧭', [{'_lifestealPct': 5, 'atk': 12}, {'_lifestealPct': 10, 'atk': 30}, {'_lifestealPct': 17, 'atk': 66}], '指针一直指着海沟，从来没指过北。'),
    (93, '3c', '遗物', 2, '祭坛残石', '🪨', [{'_lifestealPct': 5, 'def': 6}, {'_lifestealPct': 10, 'def': 14}, {'_lifestealPct': 17, 'def': 30}], '掰下来一块，祭坛照样还在那里。'),
    (94, '3c', '遗物', 4, '觉醒之核', '💠', [{'_lifestealPct': 9, 'atk': 25, 'hp': 120}, {'_lifestealPct': 18, 'atk': 62, 'hp': 300}, {'_lifestealPct': 30, 'atk': 140, 'hp': 700}], '贴着它的时候，心跳会和它同步。'),
]

# 属性 → 展示名与格式（与 EquipStats.lines_of 的口径一致；baseStats1 只是展示镜像）
LABEL = {
    'atk': ('攻', ''), 'hp': ('生命', ''), 'def': ('护甲', ''), 'mr': ('魔抗', ''),
    'crit': ('暴击', '%'), 'critDmg': ('暴伤', '%'), 'armorPen': ('破甲', ''),
    'magicPen': ('法穿', ''), '_lifestealPct': ('吸血', '%'), '_maxEnergy': ('龟能', ''),
    '_echargePct': ('充能', '%'), '_aspdPct': ('攻速', '%'), '_mspdPct': ('移速', '%'),
    '_rangePct': ('射程', '%'), 'dodgePct': ('闪避', '%'), 'healAmp': ('治疗', '%'),
}
ORDER = ['atk', 'hp', 'def', 'mr', 'crit', 'critDmg', 'armorPen', 'magicPen',
         '_lifestealPct', '_maxEnergy', '_echargePct', '_aspdPct', '_mspdPct',
         '_rangePct', 'dodgePct', 'healAmp']


def num(v):
    """0.15 → 15（暴击/暴伤在 STATS 里是小数，展示是百分比）。"""
    if isinstance(v, float) and v < 1.0:
        return '%g' % round(v * 100)
    return '%g' % v


def base_stats_str(stars):
    parts = []
    for k in ORDER:
        if k not in stars[0]:
            continue
        lab, suf = LABEL[k]
        vals = '/'.join(num(s.get(k, 0)) for s in stars)
        parts.append('+%s%s%s' % (lab, vals, suf))
    return '·'.join(parts)


def gd_dict(d):
    parts = []
    for k in ORDER:
        if k in d:
            v = d[k]
            parts.append('"%s": %s' % (k, ('%g' % v)))
    return '{' + ', '.join(parts) + '}'


def main():
    which = None
    check = '--check' in sys.argv
    for a in sys.argv[1:]:
        if a in ('3a', '3b', '3c'):
            which = a
    sel = [it for it in ITEMS if which is None or it[1] == which]
    if not sel:
        print('没有匹配的批次'); return 1

    eq = json.load(io.open(EQ_JSON, encoding='utf-8'))
    ty = json.load(io.open(TY_JSON, encoding='utf-8'))
    gd = io.open(STATS_GD, encoding='utf-8').read()
    have = {e['id'] for e in eq}
    names = {e['name'] for e in eq}

    added = 0
    new_gd_lines = []
    for n, batch, typ, cost, name, emoji, stars, flavor in sel:
        eid = 'p2eq_%03d' % n
        if eid in have:
            print('  跳过(已存在) %s' % eid); continue
        assert name not in names, '重名: %s' % name
        assert len(stars) == 3, eid
        eq.append({
            'id': eid, 'name': name, 'cost': cost,
            'baseStats1': base_stats_str(stars),
            'shopAvailable': 1, 'emoji': emoji,
            'effectDesc1': flavor, 'effectDesc3': '',
            'img': '',   # ★图标先用 emoji(用户 2026-08-02「图标先用emoji，到时候没问题再做图标」)
        })
        ty[eid] = typ
        new_gd_lines.append('\t"%s": [%s, %s, %s],   # %s · %d费 · %s' % (
            eid, gd_dict(stars[0]), gd_dict(stars[1]), gd_dict(stars[2]), typ, cost, name))
        added += 1

    print('[分母] 本次新增 %d 件 (批次=%s)' % (added, which or '全部'))
    if added == 0:
        print('无新增'); return 0
    if check:
        print('--check: 不写盘'); return 0

    # STATS 表：插在最后一条 p2eq_ 之后
    m = list(re.finditer(r'^\t"p2eq_\d+": \[.*$', gd, re.M))
    assert m, '找不到 STATS 表'
    ins = m[-1].end()
    gd = gd[:ins] + '\n' + '\n'.join(new_gd_lines) + gd[ins:]

    io.open(EQ_JSON, 'w', encoding='utf-8', newline='').write(
        json.dumps(eq, ensure_ascii=False, indent=1) + '\n')
    io.open(TY_JSON, 'w', encoding='utf-8', newline='').write(
        json.dumps(ty, ensure_ascii=False, indent=2) + '\n')
    io.open(STATS_GD, 'w', encoding='utf-8', newline='').write(gd)
    print('写盘完成: %d 件 → %d 件' % (len(eq) - added, len(eq)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
