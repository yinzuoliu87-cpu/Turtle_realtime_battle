# -*- coding: utf-8 -*-
"""按事实源重生成 docs/design/装备逐件审查进度.md 的表格行。

由来 (2026-08-01): 这张表开头写着「本表由 phase2-equipment.json 直接生成，是当前权威状态」，
但仓库里【一直没有生成它的脚本】—— 生成过一次就再没重跑，于是它一边漂一边宣称自己权威。
2026-07-29 已把逐行对账焊进 tools/data_integrity.py，但每次改装备文案仍要【手修一行】，
而手修正是这类漂移的来源。这个脚本补上缺失的那一环：改完 json 跑一次，表就回到事实源。

用法:
    python tools/gen_equip_review_table.py            # 重写表格行(保留表头说明与非表格正文)
    python tools/gen_equip_review_table.py --check     # 只检查是否需要重生成, 不写盘(供门禁用)

★只重写【以 `| NN | p2eq_xxx |` 开头的行】。表头说明、评审结论等正文一个字不动 ——
  这张文档除了数据列还有人写的口径说明, 整篇重写会把那些抹掉。
"""
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON = os.path.join(ROOT, 'data', 'phase2-equipment.json')
DOC = os.path.join(ROOT, 'docs', 'design', '装备逐件审查进度.md')


def load_items():
    d = json.load(io.open(JSON, encoding='utf-8'))
    items = d if isinstance(d, list) else d.get('equipment', d.get('items', []))
    if isinstance(items, dict):
        items = list(items.values())
    return {it['id']: it for it in items}


def main():
    check_only = '--check' in sys.argv
    items = load_items()
    src = io.open(DOC, encoding='utf-8').read()
    lines = src.split('\n')
    out = []
    changed = []
    seen = 0
    for L in lines:
        cells = [c.strip() for c in L.split('|')]
        eid = None
        for c in cells:
            if c.startswith('p2eq_'):
                eid = c
                break
        if eid is None or eid not in items or not L.strip().startswith('|'):
            out.append(L)
            continue
        seen += 1
        it = items[eid]
        # 表列: | # | id | 名称 | 费用 | 类型 | 学派 | 属性 | 效果 |
        # 前六列(编号/类型/学派)是人维护的分档口径, json 里没有 → 原样保留;
        # 只把【属性】【效果】两列换成 json 的值(它们正是 data_integrity 逐行对账的两列)。
        parts = L.split('|')
        if len(parts) < 9:
            out.append(L)
            continue
        new_stats = ' %s ' % str(it.get('baseStats1', '')).strip()
        new_eff = ' %s ' % str(it.get('effectDesc1', '')).strip()
        if parts[7] != new_stats or parts[8] != new_eff:
            changed.append(eid)
            parts[7] = new_stats
            parts[8] = new_eff
        out.append('|'.join(parts))

    print('[分母] 表内匹配到 %d 行 / json %d 件' % (seen, len(items)))
    if seen == 0:
        print('[FAIL] 一行都没匹配到 —— 表格式变了? 这是空检查, 不是通过')
        return 1
    if not changed:
        print('ALL OK — 评审表已与 phase2-equipment.json 一致')
        return 0
    if check_only:
        print('[FAIL] %d 行需要重生成: %s' % (len(changed), ', '.join(changed)))
        print('       跑 python tools/gen_equip_review_table.py 重生成')
        return 1
    io.open(DOC, 'w', encoding='utf-8', newline='').write('\n'.join(out))
    print('已重生成 %d 行: %s' % (len(changed), ', '.join(changed)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
