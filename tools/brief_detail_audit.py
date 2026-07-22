# -*- coding: utf-8 -*-
"""龟文案 brief ↔ 详细 数值差分核查(只读)。2026-07-22 建。

【为什么要有】用户 2026-07-22:「怎么又来分歧了」。根因是**没有任何工具核对同一只龟的
两份手写副本**: tri_audit 核 pets.json↔代码↔权威文档, tooltip_number_audit 核装备↔代码,
中间这条缝谁都没管 —— 于是选龟界面(读 brief)和战斗面板(读详细)可以长期各说各的。

【不变式】brief 是缩略, 所以
    brief 里出现的每一个【带单位的数值】, 都必须在详细里出现。
反过来不要求(详细本来就更细)。这条既能抓住"同一个量写了两个值"(11% vs 8%),
也不会因为 brief 省略而误报。

【覆盖哪些区块】每只龟身上有两类两份副本, 【两类都要查】:
    skillPool[i].brief ↔ skillPool[i].detail     (技能)
    passive.brief      ↔ passive.desc            (被动 —— 详细字段叫 desc 不叫 detail!)
★初版只查了 skillPool, 把 28 对 passive 整个漏掉了, 而分歧恰恰全在 passive 里。
  当时打印的"分母 112"看着很足, 我却把【覆盖面】读成了【通过率】。
  现在 main() 里有一条覆盖自检: 少一对 passive 就当场红, 而不是安静地报 ALL OK。

【怎么比】解析成 float 比, 不比字符串(0.5 vs 0.50)。单位相同才算同一个量。
【要剔除的】
  · HTML 标签
  · {N:...}/{S:...}/{D:...} 占位符 —— 里面是【公式系数】不是文案数值, 而且 brief 与详细
    常用不同写法表达同一件事(brief 用占位符, 详细写"160%×攻击力"), 照字面比会满屏假报
"""
import io, sys, json, re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 人工核实过的例外: (龟id, 区块, 序号, "值单位") -> 为什么可以不一致。
# ★往这里加之前必须先看代码确认哪个是真值 —— 白名单是"已核实", 不是"懒得改"。
VERIFIED_OK = {}

TAG = re.compile(r'<[^>]*>')
PLACEHOLDER = re.compile(r'\{[^{}]*\}')
# 带单位的数值。单位表按项目文案实际用到的收: 百分比/码/秒/层/段/点/级/次
NUMU = re.compile(r'(\d+(?:\.\d+)?)\s*(%|码|秒|层|段|点|级|次)')


def clean(s):
    s = TAG.sub(' ', str(s or ''))
    s = PLACEHOLDER.sub(' ', s)
    return s


def nums(s):
    """→ {(值, 单位)} 集合"""
    return set((float(m.group(1)), m.group(2)) for m in NUMU.finditer(clean(s)))


def load_pets():
    d = json.load(io.open('data/pets.json', encoding='utf-8'))
    if isinstance(d, dict):
        for k in ('pets', 'items', 'data'):
            if k in d:
                return d[k]
    return d


def pairs_of(p):
    """→ [(区块名, 序号, brief, 详细)] —— 一只龟身上【所有】两份手写副本"""
    out = []
    for key in ('skillPool', 'skills'):
        pool = p.get(key)
        if isinstance(pool, list):
            for idx, sk in enumerate(pool):
                if isinstance(sk, dict) and sk.get('brief') and (sk.get('detail') or sk.get('desc')):
                    out.append((key, idx, sk['brief'], sk.get('detail') or sk.get('desc')))
    pa = p.get('passive')
    if isinstance(pa, dict) and pa.get('brief') and pa.get('desc'):
        out.append(('passive', 0, pa['brief'], pa['desc']))
    return out


def main():
    pets = load_pets()
    n_pets = 0
    n_pairs = 0          # 两份副本成对的区块数(分母)
    n_brief_nums = 0     # brief 里带单位的数值总数(分母)
    n_passive = 0        # 其中 passive 对数 —— 单独记, 防止再被整体漏掉
    bad = []

    for p in pets:
        pid = str(p.get('id', ''))
        pname = str(p.get('name', ''))
        n_pets += 1
        for key, idx, brief, detail in pairs_of(p):
            n_pairs += 1
            if key == 'passive':
                n_passive += 1
            nb, nd = nums(brief), nums(detail)
            n_brief_nums += len(nb)
            for v, u in sorted(nb - nd):
                tag = '%g%s' % (v, u)
                if (pid, key, idx, tag) in VERIFIED_OK:
                    continue
                bad.append((pid, pname, key, idx, tag,
                            sorted('%g%s' % (x, y) for x, y in nd if y == u)))

    print('龟 %d 只 · 两份副本成对的区块 %d 个(其中 passive %d 个) · brief 带单位数值 %d 个 · 白名单 %d 条'
          % (n_pets, n_pairs, n_passive, n_brief_nums, len(VERIFIED_OK)))
    if n_pairs == 0 or n_brief_nums == 0:
        print()
        print('[FAIL] 分母为 0 —— 这是空检查不是通过(字段名改了? pets.json 结构变了?)')
        sys.exit(1)
    # ★覆盖自检: 每只龟都该有 passive 那一对。少了就是【又漏掉一整个字段】,
    #   而不是"没有分歧" —— 初版正是这么静悄悄漏了 28 对。
    if n_passive < n_pets:
        print()
        print('[FAIL] 只核对到 %d 对 passive, 但有 %d 只龟 —— 漏字段了, 不是没分歧'
              % (n_passive, n_pets))
        sys.exit(1)

    if bad:
        print()
        print('[FAIL] brief 里的数值在详细文案里找不到: %d 处' % len(bad))
        print('       (左=选龟界面看到的, 右=详细里同单位的所有值; 代码是终审)')
        for pid, pname, key, idx, tag, same_unit in bad:
            loc = key if key == 'passive' else '%s[%d]' % (key, idx)
            print('   %-10s %-6s %-14s brief有 %-8s  详细同单位: %s'
                  % (pid, pname, loc, tag, ('(无)' if not same_unit else '/'.join(same_unit))))
    print()
    print('ALL OK — brief 与详细文案数值一致' if not bad else 'NEEDS FIX: %d' % len(bad))
    sys.exit(1 if bad else 0)


main()
