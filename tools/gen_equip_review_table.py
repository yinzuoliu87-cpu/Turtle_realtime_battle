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
TYPES_JSON = os.path.join(ROOT, 'data', 'p2eq-types.json')
DOC = os.path.join(ROOT, 'docs', 'design', '装备逐件审查进度.md')


def load_items():
    d = json.load(io.open(JSON, encoding='utf-8'))
    items = d if isinstance(d, list) else d.get('equipment', d.get('items', []))
    if isinstance(items, dict):
        items = list(items.values())
    return {it['id']: it for it in items}


def load_types():
    """id → 类型。★2026-08-03 起【类型列也由脚本生成】。

    原来类型列是"人维护的分档口径"、脚本不碰 —— 于是批1 把 9 件装备从「护符/饰品」
    改归类之后，表里那 9 行还写着两个【已经不存在的类型】，而两个审计器都不看这一列。
    事实源是 data/p2eq-types.json，让它直接生成，这一列就再也漂不了
    （同 memory fb-self-claiming-authority-docs-rot：手改一行 = 必漂）。
    """
    return json.load(io.open(TYPES_JSON, encoding='utf-8'))



def _cell(t):
    """把描述写进 markdown 表格单元格。

    ★换行必须转义成 <br> —— markdown 表格的一个单元格【不能跨行】, 原样写进去
      整张表就从那一行断掉, 而 data_integrity 的"评审表 ↔ json 一致"当场红。
      (2026-08-16: 描述改成"一句一行"后踩到, 生成器不转义就永远对不上。)
    """
    return str(t).strip().replace(chr(13) + chr(10), chr(10)).replace(chr(10), "<br>")


def main():
    check_only = '--check' in sys.argv
    items = load_items()
    types = load_types()
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
        # 表列: | # | id | 名称 | 费用 | 类型 | 属性 | 效果 |
        # 前五列(编号/名称/费用/类型)是人维护的分档口径, json 里没有 → 原样保留;
        # 只把【属性】【效果】两列换成 json 的值(它们正是 data_integrity 逐行对账的两列)。
        #
        # ★★2026-08-03 删学派列时【必须同步改的下标】—— 这是方案书 R1 点名的假绿灯, 已实测复现:
        #   删掉「学派」列后 len(parts) 从 10 变 9, 而原来的守卫写的是 `len(parts) < 9` —— 【拦不住】,
        #   于是 parts[7]/parts[8] 整体错位一格, 把【属性】写进了原本是【效果】的位置。
        #   实测后果: 表变成 "…| 属性 | 属性 | 效果" (属性列出现两次、效果被挤到末尾),
        #   而 gen_equip_review_table 照样报"改写 59 行"、data_integrity 直接报【ALL OK】——
        #   因为 data_integrity 的对账是【整行子串匹配】(v not in L), 与列位置无关, 抓不到错位。
        #   ⇒ 列数变了就必须同时改这里的下标与守卫, 两者【只改一边就是静默写坏数据】。
        parts = L.split('|')
        if len(parts) < 8:
            out.append(L)
            continue
        # ★★2026-08-05 补【名称】与【费用】两列 —— 它们原来【不同步】, 上面那段注释写的
        #   "名称/费用是人维护的分档口径, json 里没有" **是错的**: json 里就有 name / cost。
        #   后果实测: 用户 2026-08-05 逐件重做时改了一批名字(游魂贝铃→钻孔螺、雾行海葵→
        #   螳螂虾钳、幽影墨囊→白鲸气环、深渊招魂螺→溺者的浮囊…), 表里仍是旧名,
        #   而这张表开头自称"由 phase2-equipment.json 直接生成、当前权威状态" ⇒ 它在说谎。
        #   ⚠ data_integrity 的逐行对账只比【属性】【效果】两列, 抓不到名字漂 ——
        #     所以这不是"审计器会兜住"的漏, 是真的会一直烂下去
        #     (memory fb-self-claiming-authority-docs-rot: 自称"由X生成"的文档一定已经烂了)。
        new_name = ' %s ' % str(it.get('name', '')).strip()
        new_cost = ' %d ' % int(it.get('cost', 1))
        new_type = ' %s ' % str(types.get(eid, '?')).strip()
        new_stats = ' %s ' % str(it.get('baseStats1', '')).strip()
        new_eff = ' %s ' % _cell(it.get('effectDesc1', ''))
        if (parts[3] != new_name or parts[4] != new_cost or parts[5] != new_type
                or parts[6] != new_stats or parts[7] != new_eff):
            changed.append(eid)
            parts[3] = new_name
            parts[4] = new_cost
            parts[5] = new_type
            parts[6] = new_stats
            parts[7] = new_eff
        out.append('|'.join(parts))

    # ★2026-08-03 批3: 生成器原来【只会重写已有行、不会新增】—— 加了 35 件之后
    #   表里还是 59 行, 而 data_integrity 的逐行对账当场判红("p2eq_060 不在评审表里")。
    #   审计器抓到了是好事; 但正确的修法是让生成器把新件补进去, 而不是手写 35 行
    #   (memory fb-self-claiming-authority-docs-rot: 手改一行 = 必漂)。
    #   新行插在【最后一条数据行之后】, 编号接着排。
    in_table = {}
    last_row = -1
    for i, L in enumerate(out):
        for c in L.split('|'):
            if c.strip().startswith('p2eq_'):
                in_table[c.strip()] = True
                last_row = i
    missing = [k for k in items if k not in in_table]
    if missing and last_row >= 0:
        # 按 id 排序, 编号从表里已有的最大号往后接
        nums = []
        for L in out:
            parts = L.split('|')
            if len(parts) > 1 and parts[1].strip().isdigit():
                nums.append(int(parts[1].strip()))
        nxt = (max(nums) + 1) if nums else 1
        add = []
        for k in sorted(missing):
            it = items[k]
            add.append('| %02d | %s | %s | %d | %s | %s | %s |' % (
                nxt, k, str(it.get('name', '')), int(it.get('cost', 1)),
                str(types.get(k, '?')), str(it.get('baseStats1', '')).strip(),
                _cell(it.get('effectDesc1', ''))))
            nxt += 1
        out[last_row + 1:last_row + 1] = add
        changed.extend(missing)
        seen += len(missing)

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
