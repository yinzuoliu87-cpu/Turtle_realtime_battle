# -*- coding: utf-8 -*-
"""龟技能 brief ↔ detail 数值差分核查(只读)。2026-07-22 建。

【为什么要有】用户 2026-07-22:「怎么又来分歧了」。根因是**没有任何工具核对同一只龟的
brief 与 detail**: tri_audit 核 pets.json↔代码↔权威文档, tooltip_number_audit 核装备↔代码,
中间这条缝谁都没管 —— 于是选龟界面(读 brief)和战斗面板(读 detail)可以长期各说各的。

【不变式】brief 是 detail 的缩略, 所以
    brief 里出现的每一个【带单位的数值】, 都必须在 detail 里出现。
反过来不要求(detail 本来就更细)。这条既能抓住"同一个量写了两个值"(11% vs 8%),
也不会因为 brief 省略而误报。

【怎么比】解析成 float 比, 不比字符串(0.5 vs 0.50)。单位相同才算同一个量。
【要剔除的】
  · HTML 标签 —— <span class="val-def">5秒</span> 里的标签属性不含数值, 但保险起见先剥
  · {N:...}/{S:...}/{D:...} 占位符 —— 里面的 1.6/0.6667 是【公式系数】不是文案数值,
    而且 brief 与 detail 常用不同写法表达同一件事(brief 用占位符, detail 写"160%×攻击力"),
    照字面比会满屏假报
"""
import io, sys, json, re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 人工核实过的例外: (龟id, 技能序号, "值单位") -> 为什么可以不一致。
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


def main():
    pets = load_pets()
    n_pets = 0
    n_pairs = 0          # 同时有 brief 和 detail 的技能格数(分母)
    n_brief_nums = 0     # brief 里带单位的数值总数(分母)
    bad = []

    for p in pets:
        pid = str(p.get('id', ''))
        pname = str(p.get('name', ''))
        n_pets += 1
        for key in ('skillPool', 'skills'):
            pool = p.get(key)
            if not isinstance(pool, list):
                continue
            for idx, sk in enumerate(pool):
                if not isinstance(sk, dict):
                    continue
                brief = sk.get('brief')
                detail = sk.get('detail') or sk.get('desc')
                if not brief or not detail:
                    continue
                n_pairs += 1
                nb, nd = nums(brief), nums(detail)
                n_brief_nums += len(nb)
                for v, u in sorted(nb - nd):
                    tag = '%g%s' % (v, u)
                    if (pid, idx, tag) in VERIFIED_OK:
                        continue
                    bad.append((pid, pname, key, idx, tag,
                                sorted('%g%s' % (x, y) for x, y in nd if y == u)))

    print('龟 %d 只 · brief/detail 成对的技能格 %d 个 · brief 里带单位的数值 %d 个 · 白名单 %d 条'
          % (n_pets, n_pairs, n_brief_nums, len(VERIFIED_OK)))
    if n_pairs == 0 or n_brief_nums == 0:
        print('\n[FAIL] 分母为 0 —— 这是空检查不是通过(字段名改了? pets.json 结构变了?)')
        sys.exit(1)

    if bad:
        print('\n[FAIL] brief 里的数值在 detail 里找不到: %d 处' % len(bad))
        print('       (左=选龟界面看到的, 右=战斗面板里同单位的所有值; 代码是终审)')
        for pid, pname, key, idx, tag, same_unit in bad:
            print('   %-10s %-6s %s[%d]  brief有 %-8s  detail同单位: %s'
                  % (pid, pname, key, idx, tag, ('(无)' if not same_unit else '/'.join(same_unit))))
    print('\n' + ('ALL OK — brief 与 detail 数值一致' if not bad else 'NEEDS FIX: %d' % len(bad)))
    sys.exit(1 if bad else 0)


main()
