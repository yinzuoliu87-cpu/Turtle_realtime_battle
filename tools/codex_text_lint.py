# -*- coding: utf-8 -*-
"""图鉴文案体检 —— 判据不是我拍脑袋定的, 是从 489 条真实同类游戏文案里量出来的。

═══ 来源(2026-08-18 实抓, 去重后 489 条 / 14 款游戏) ═══
  Super Auto Pets 60 · Slay the Spire 45 · Risk of Rain 2 45 · Binding of Isaac 90
  Darkest Dungeon 30 · Noita 40 · Enter the Gungeon 80 · Dead Cells 70
  云顶之弈(中) · 金铲铲(中) · 明日方舟(中·银灰/陈) 等

═══ 从样本里量出来的共同规律 ═══
  1. **短**: 英文 11~18 词; 中文 明日方舟 15~50 字 / 金铲铲 12~20 字 / 云顶 45~85 字
  2. **不称呼玩家**: SAP / StS / 暗黑地牢 / 明日方舟 **零**第二人称;
     云顶用「携带者」、以撒用「Isaac」—— 都拿一个第三人称的名字顶替"你"
  3. **零评价词**: 14 款里 13 款的机制描述**没有一个**"强力/好用/推荐"
  4. **零教学**: 489 条里只有 **1 条**例外(SAP 蓝莓「Prioritize this for enemy random
     abilities」), 其余**没有一句**告诉玩家什么时候用、怎么配
  5. **数值全给死**: 阿拉伯数字 + %; 没有"少量/大量/略微/显著"这类模糊量词
  6. **条件在前效果在后**: 死亡细胞 73% / 明日方舟 / StS「Whenever…, draw 1 card」
  7. **风味话是【另一个字段】**: 死亡细胞的「One hit and you're dead.」是 flavor 行,
     和机制描述分开; 机制行里不掺形容词

═══ 用户 2026-08-18 的原话 ═══
  「图鉴所有的描述都不应该有 ai 味和教导玩家的味道」
  ⇒ "教导味" = 规律 4 的反面; "ai 味" = 规律 3、5 的反面(空泛吹捧 + 模糊量词)。

跑法: python tools/codex_text_lint.py [--list]
"""
import io
import sys
import json
import re
import collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
NL = chr(10)

# ── 判据 ────────────────────────────────────────────────────────────────
# 一句"简述"的字数上限。中文同类实测 12~85 字, 取 60 —— 比最宽松的云顶还宽一点,
# 因为我们一件装备常带 1/2/3 星三档数值。超过就是"讲不完的第二件事"。
BRIEF_MAX = 60
# 【全文档】的上限 —— 龟的 `detail`/`desc` 和装备的 `effectDesc1` 是**同一层东西**:
# 都是"点开看全部"里那份完整机制说明。原来给 detail 定 200、给装备定 400 是两套尺子,
# 那不是标准, 是我随手拍的。统一到 400(实测最长一件装备 329 字, 是真机制不是废话)。
DETAIL_MAX = 400

## 【明确豁免】超过上限但**经过复核认为该留**的全文, 连理由一起登记。
##
## ★为什么用名单而不是把上限调高: 调高上限是"把尺子改到能量过为止", 那不是标准;
##   名单摆在这里, 谁都能看见到底破了几个例、各是什么理由。
DETAIL_ALLOW = {
    ('龟技能', 'pirate/海盗船', 'detail'):
        '召唤物完整属性表(生命/攻击/双抗/攻速/射程)+ 三段行为, 删任何一段都会让玩家算不出账',
    ('龟技能', 'shell/暗影', 'detail'):
        '一个技能同时带主动与被动两套机制(潜影/暗影), 本身就是两条技能的信息量',
}

# 教导句: 直接告诉玩家该怎么打。489 条样本里只出现过 1 次。
# ⚠ 判据太宽第 11 次: 「优先」原本在名单里, 结果逮到的是
#   「护盾优先于生命值消耗」「优先攻击最近的敌人」—— 这是**机制说明**(结算顺序/选靶),
#   不是教玩家怎么打。只留真正带指导口气的组合词。
TEACH = ['建议', '推荐', '适合', '优先考虑', '建议优先', '记得', '注意', '尽量', '最好',
         '可以考虑', '不妨', '试试', '用来对付', '用于应对', '搭配', '配合使用',
         '效果更好', '更划算', '性价比', '值得', '别忘了', '需要注意']
# 评价词: 对自己强度下判断。样本里 13/14 款为零。
# ⚠ 同上: 「相当」逮到的是「相当于攻击力的 200%」(等于, 机制), 「万能」逮到的是
#   技能名【万能牌】。判据要卡住"对自己下评价"这个形状, 不是卡住这两个字。
JUDGE = ['强力', '极强', '很强', '强势', '核心地位', '至关重要', '非常', '极其',
         '相当强', '十分', '显著', '大幅', '极佳', '优秀', '出色', '爆发力', '恐怖',
         '无解', '逆天', '神级', '顶级']
# 模糊量词: 样本里数值一律给死, 没有一个"少量/大量"。
VAGUE = ['少量', '大量', '略微', '稍微', '轻微', '巨额', '海量', '若干', '一定量',
         '不少', '很多', '极大地', '大幅度', '小幅']
# 第二人称: 样本里要么零, 要么用「携带者」这类第三人称顶替。
YOU = ['你的', '你会', '你能', '你可以', '玩家']
# 风味/吹捧从句: 机制行里不该出现的抒情
# 开发备注混进玩家文案 —— 实测抓到两条(赛博龟「尚未定义消耗方式与收益（待设计）」、
# 黄铜齿轮「（仅玩家/左队）…并飘字」)。这比"ai 味"更糟: 玩家读到的是我的 TODO。
DEVNOTE = ['待设计', '待定', '尚未定义', '后续精修', '暂未', '待补', 'TODO', '飘字',
           '仅玩家', '左队', '右队', '占位', '未实现']
FLAVOR = ['越战越勇', '所向披靡', '势不可挡', '锐不可当', '战意', '热血',
          '令人', '仿佛', '宛如', '犹如']


def load(p):
    d = json.load(io.open(p, encoding='utf-8'))
    return d if isinstance(d, list) else list(d.values())[0]


def collect():
    rows = []
    for p in load('data/pets.json'):
        pid = str(p.get('id', ''))
        pa = p.get('passive') or {}
        for k in ('brief', 'desc', 'detail'):
            v = str(pa.get(k, '') or '')
            if v:
                rows.append(['龟被动', pid, k, v])
        for grp in ('skillPool', 'volcanoSkills', 'meleeSkills'):
            for s in (p.get(grp) or []):
                for k in ('brief', 'detail', 'desc'):
                    v = str(s.get(k, '') or '')
                    if v:
                        rows.append(['龟技能', '%s/%s' % (pid, s.get('name', '')), k, v])
    for e in load('data/phase2-equipment.json'):
        for k in ('effectBrief', 'effectDesc1', 'effectDesc3'):
            v = str(e.get(k, '') or '')
            if v:
                rows.append(['装备', '%s/%s' % (e.get('id', ''), e.get('name', '')), k, v])
    for f, tag in [('data/status.json', '状态'), ('data/battle-rules.json', '规则'),
                   ('data/p2eq-types.json', '羁绊')]:
        for e in load(f):
            if not isinstance(e, dict):
                continue
            for k, v in e.items():
                if isinstance(v, str) and len(v) >= 8 and k not in (
                        'id', 'name', 'icon', 'color', 'img', 'emoji'):
                    rows.append([tag, str(e.get('id', e.get('name', ''))), k, v])
    return rows


def plain(t):
    """去掉占位符和标记, 只留玩家真正读到的字。

    ★不去掉的话字数会被 {N:0.6*atk} 这种模板撑大, 量出来的"太长"是假的。
    """
    t = re.sub(r'\{[A-Za-z]:[^}]*\}', '00', t)      # 数值占位符 → 当两个字
    t = re.sub(r'<[^>]+>', '', t)                    # html/bbcode
    return t


def main():
    rows = collect()
    hits = collections.defaultdict(list)
    for tag, ident, field, txt in rows:
        p = plain(txt)
        n = len(p)
        is_brief = field in ('brief', 'effectDesc1', 'effectDesc3', 'desc') and tag != '龟被动'
        # ★2026-08-19: 装备补了 `effectBrief`(一句话) 之后, `effectDesc1` 的身份从
        #   "简述"变成了"全文"(点开看全部那一层) ⇒ 它按详情的上限算, 不再按简述。
        #   全文档放到 400: 实测最长一件 329 字, 而这些是真机制说明, 不是废话。
        if field in ('brief', 'effectBrief'):
            cap = BRIEF_MAX
        elif field.startswith('effectDesc'):
            cap = 400
        else:
            cap = DETAIL_MAX
        if n > cap and (tag, ident, field) not in DETAIL_ALLOW:
            hits['太长(上限%d)' % cap].append((tag, ident, field, n, p[:40]))
        for w in TEACH:
            if w in p:
                hits['教导玩家'].append((tag, ident, field, w, p[:40]))
                break
        for w in JUDGE:
            if w in p:
                hits['自夸/评价'].append((tag, ident, field, w, p[:40]))
                break
        for w in VAGUE:
            if w in p:
                hits['模糊量词'].append((tag, ident, field, w, p[:40]))
                break
        for w in YOU:
            if w in p:
                hits['称呼玩家'].append((tag, ident, field, w, p[:40]))
                break
        for w in FLAVOR:
            if w in p:
                hits['抒情/风味混进机制'].append((tag, ident, field, w, p[:40]))
                break
        for w in DEVNOTE:
            if w in p:
                hits['开发备注混进玩家文案'].append((tag, ident, field, w, p[:40]))
                break

    print('=== 图鉴文案体检(判据取自 489 条真实同类游戏文案) ===')
    print('受检文本 %d 条' % len(rows))
    total = 0
    for k in ['开发备注混进玩家文案', '教导玩家', '自夸/评价', '模糊量词', '称呼玩家', '抒情/风味混进机制',
              '太长(上限%d)' % BRIEF_MAX, '太长(上限%d)' % DETAIL_MAX]:
        v = hits.get(k, [])
        total += len(v)
        print('  %-18s %4d 条' % (k, len(v)))
        for r in v[:6] if '--list' not in sys.argv else v:
            print('       %s %s.%s  「%s」  %s' % (r[0], r[1], r[2], r[3], r[4]))
    print('  ── 合计 %d 处 ──' % total)
    if DETAIL_ALLOW:
        print('  明确豁免 %d 条(超上限但复核认为该留):' % len(DETAIL_ALLOW))
        for k, why in DETAIL_ALLOW.items():
            print('       %s %s.%s —— %s' % (k[0], k[1], k[2], why))
    return 0


if __name__ == '__main__':
    sys.exit(main())
