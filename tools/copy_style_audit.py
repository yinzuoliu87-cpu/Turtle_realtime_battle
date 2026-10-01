# -*- coding: utf-8 -*-
"""文案体例纪律 —— 2026-10-01 建。

由来: 用户 2026-09-30「要统一吧, 按新的学习的语术来, 包括装备和技能」, 之前的原话是
「攒到 3 个就炸开? 有你这样子描述吗, 哪个游戏会这样子搞」。
体例来自实读 LoL 的 692 条 tooltip, 结论在 docs/plans/ref/20260930-LoL文案体例.md,
落成规矩在 docs/plans/20260930b-说明文案两层渲染.md §4.1。

★这里**只放量得准的两类**, 其余五条体例(三段式叠层 / 复合伤害末尾一次类型词 /
  「转而」/ 专名解释行)判不准, 留给人工 —— 判不准就写成判据等于造假 bug。

★★证据分级, 这是本脚本最要紧的一件事:
  ① **硬零**: 炸开 / 攒到 / 攒够 / 打满 —— 这四个在 LoL 的 692 条语料里**一次都没有**。
     用户骂的那两版正好各踩一个(「攒到 3 个就炸开」「普攻叠环」)。
  ② **只减不增的台账**: 叠满 / 攒满 —— ⚠ 这两个 **LoL 自己也在用**(攒满 4 次 / 叠满 2 次)。
     把它们也判成硬错就是**我自己发明一条规矩再拿它堵自己**(memory
     `fb-my-invented-rules-become-the-wall`)。它们只是没有「满层 / 可叠加 / 施加一层」
     那套读着顺, 所以记账只减不增, 不判硬错。
  ③ 只减不增的台账: 「X% 生命值」没写**是谁的**生命值。这条是真歧义 ——
     「回复 5/7/10% 最大生命值」是回复自己的还是目标的? 玩家读不出来。
     但改它必须**逐件读代码确认**, 不能照着文案猜, 所以先记账。

⚠ 台账只减不增, 不是"允许存在"。减到 0 了就把那一行改成硬零。
"""
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

LEDGER = 'tests/golden/copy_style_debt.txt'
HARD_ZERO = ['炸开', '攒到', '攒够', '打满']        # LoL 语料零命中
SOFT = ['叠满', '攒满']                              # LoL 自己也用, 只记账

TEXT_KEY = re.compile(r'(brief|desc|Desc|Brief|text|Text|tip|Tip)')
# 子句切分: 中文句读 + 真换行 + 括号
CLAUSE = re.compile(r'[，。；、\n（）()]')
PCT_HP = re.compile(r'%\s*(最大|已损失|当前)?生命值')
# 归属词 —— 「这是谁的生命值」
# ★2026-10-01 补了一批: 该单位 / 原龟 / 该目标 / 本体 / 原主。第一版漏了它们, 于是
#   「并造成**该单位** X% 最大生命值的真实伤害」「随从拥有**原龟** X% 最大生命值」
#   这种**写得很清楚**的句子被判成有歧义 —— 那是判据的词表缺口, 不是文案的毛病。
#   ⚠ 补词表会让计数下降, 那**不是**改进文案的成绩。台账里要把这两种下降分开记,
#     否则「只减不增」就能靠放宽判据刷出来。
OWNER = re.compile(r'(目标|自身|自己|其|该敌人|敌人|友军|己方|队友|携带者|持有者|全队|友方'
                   r'|该单位|原龟|该目标|本体|原主)')
# 阈值判定(「低于 30% 生命值时」)不需要归属 —— 它说的是状态, 不是伤害量
THRESH = re.compile(r'(低于|高于|不足|超过|以下|以上|每损失|生命百分比|血量低于)')

fails = []


def chk(name, bad):
    if bad:
        fails.append('%s: %s' % (name, bad if isinstance(bad, str) else ' / '.join(map(str, bad[:8]))))
        print('  [FAIL] %s' % name)
    else:
        print('  [ OK ] %s' % name)


def segments():
    out = []
    for path, tag in [('data/phase2-equipment.json', 'equip'), ('data/pets.json', 'pet')]:
        data = json.load(io.open(path, encoding='utf-8'))

        def walk(o, p):
            if isinstance(o, dict):
                for k, v in o.items():
                    walk(v, p + [k])
            elif isinstance(o, list):
                for i, v in enumerate(o):
                    walk(v, p + [str(i)])
            elif isinstance(o, str) and len(o) >= 6 and p and TEXT_KEY.search(p[-1]):
                out.append((tag, '/'.join(p), o))
        walk(data, [])
    return out


def read_ledger():
    if not os.path.exists(LEDGER):
        return None
    out = {}
    for line in io.open(LEDGER, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition('\t')
        out[k.strip()] = int(v.strip())
    return out


def main():
    segs = segments()
    n_eq = sum(1 for s in segs if s[0] == 'equip')
    print('  [分母] 玩家文案段落 %d 段 (装备 %d / 龟 %d)' % (len(segs), n_eq, len(segs) - n_eq))
    if len(segs) < 300:
        chk('★分母: 真的扫到文案(扫到 0 段则下面全是空检查)', '只扫到 %d 段' % len(segs))
        print('FAILED: %d 处' % len(fails))
        sys.exit(1)

    # ── ① 硬零 ──
    hard = []
    for tag, path, t in segs:
        for w in HARD_ZERO:
            if w in t:
                hard.append('%s 里有「%s」' % (path, w))
    chk('★四个口语动词硬零 %s(LoL 692 条语料里一次都没有)' % '/'.join(HARD_ZERO), hard)

    # ── ② 「X% 生命值」必须写明是谁的 —— 2026-10-01 清到 0, 从台账升级成硬零 ──
    #
    # ★这条原来是台账(45 起步)。台账头上写着「减到 0 了就把那一行改成硬零」, 现在兑现:
    #   留着一个 0 的台账等于留着一个"可以再涨回去"的额度。
    # ★45 条逐件改的时候量出一条通则, 已写进方案书 §4.1:
    #   **写丢归属的几乎全在 brief, 而同一条的 detail/desc 本来就写着**
    #   (钻石龟 detail「<b>目标</b>最大生命值」/ 糖果龟 detail「糖果龟最大生命值」/
    #    081 desc1「每累计受到**自身** 40/35/30%最大生命值的伤害」)。
    #   简介是照着详细版删出来的, 删的时候把归属词一起删了。**brief 删修饰, 不删归属。**
    n_pct = 0
    noown = []
    for tag, path, t in segs:
        for cl in CLAUSE.split(t):
            if not PCT_HP.search(cl):
                continue
            n_pct += 1
            if THRESH.search(cl) or OWNER.search(cl):
                continue
            noown.append('%s: %s' % (path, cl.strip()[:40]))
    print('  [分母] 含「%% … 生命值」的子句共 %d 条(0 条则下面是空检查)' % n_pct)
    # ★下限 30: 实测 38 条, 留一点余量。它挡的是"正则坏了于是一条都扫不到", 不是挡文案数量变化。
    chk('★分母: 真的扫到带百分比生命值的子句', [] if n_pct >= 30 else ['只有 %d 条' % n_pct])
    chk('★每处「X% 生命值」都写明是谁的(目标/自身/各自…) —— 2026-10-01 清零后焊死', noown)

    # ── ③ 台账 ──
    counts = {}
    for w in SOFT:
        counts['口语·' + w] = sum(t.count(w) for _, _, t in segs)

    led = read_ledger()
    if led is None:
        print('  [分母] 台账不存在, 本次测得:')
        for k in sorted(counts):
            print('      %s\t%d' % (k, counts[k]))
        chk('★台账文件在位(%s)' % LEDGER, '不存在 —— 先生成再提交')
    else:
        worse = []
        for k in sorted(counts):
            base = led.get(k)
            flag = '?' if base is None else ('↓' if counts[k] < base else ('=' if counts[k] == base else '↑'))
            print('  [分母] %-22s 现在 %3d / 台账 %s  %s' % (k, counts[k], str(base), flag))
            if base is None:
                worse.append('%s 没登记进台账' % k)
            elif counts[k] > base:
                worse.append('%s 从 %d 涨到 %d' % (k, base, counts[k]))
        chk('★台账只减不增(减下去要同时改台账的数, 不然下一次就把它当成新上限)', worse)
        shrunk = [k for k in counts if led.get(k) is not None and counts[k] < led[k]]
        if shrunk:
            chk('★减下去了就要把台账改小(否则留着的空额迟早被人用掉): %s' % ' '.join(shrunk),
                ['%s 台账还写着 %d, 实测已经 %d' % (k, led[k], counts[k]) for k in shrunk])

    print('')
    if fails:
        for f in fails:
            print('  %s' % f)
        print('FAILED: %d 处' % len(fails))
        sys.exit(1)
    print('ALL OK — 文案体例纪律(口语词硬零 / 「X% 生命值」必须写明是谁的 / 叠满攒满台账只减不增)')


main()
