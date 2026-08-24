# -*- coding: utf-8 -*-
"""把 docs/design/装备逐件审查进度.md 的【属性/效果】两列按事实源重生成。

由来(2026-08-24): 那张表里存的是 phase2-equipment.json 的**手抄副本**,
`data_integrity` 有一条专门盯它有没有漂。我把 6 件装备的 effectDesc1 换成占位符,
表就红了 —— 这类红的正确处置是【按事实源重生成】, 不是手改那几行
(手改一行 = 下次再漂一行; 见 memory「自称当前权威的文档最危险」)。

做法: 拿 git HEAD 里的旧 json 值当"要被替换掉的旧串", 在表里做精确替换。
      格式无关(不管它在第几列), 且**只动值确实变了的行**。

    python tools/review_table_sync.py            # 只报告会改哪几行
    python tools/review_table_sync.py --write     # 真写
"""
import io
import json
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REV = os.path.join(ROOT, 'docs/design/装备逐件审查进度.md')
EQ = 'data/phase2-equipment.json'
FIELDS = (('baseStats1', '属性'), ('effectDesc1', '效果'))


def norm(v):
    return str(v or '').strip().replace('\r\n', '\n').replace('\n', '<br>')


def load(raw):
    d = json.loads(raw)
    lst = d if isinstance(d, list) else next(v for v in d.values() if isinstance(v, list))
    return {str(e.get('id')): e for e in lst}


def main():
    write = '--write' in sys.argv
    new = load(io.open(os.path.join(ROOT, EQ), encoding='utf-8').read())
    old_raw = subprocess.run(['git', 'show', 'HEAD:' + EQ], capture_output=True, cwd=ROOT).stdout
    if not old_raw:
        print('读不到 HEAD 版本的 json —— 无法确定"旧串", 中止'); return 1
    old = load(old_raw.decode('utf-8'))

    md = io.open(REV, encoding='utf-8').read()
    changed, missing = [], []
    for eid, e in new.items():
        for field, label in FIELDS:
            nv, ov = norm(e.get(field)), norm(old.get(eid, {}).get(field))
            if not nv or nv == ov:
                continue
            if not ov or ov not in md:
                missing.append('%s %s —— 表里找不到旧串(可能它本来就没进表)' % (eid, label))
                continue
            md = md.replace(ov, nv)
            changed.append('%s %s' % (eid, label))

    print('  会改 %d 处: %s' % (len(changed), ', '.join(changed) if changed else '(无)'))
    for m in missing:
        print('  跳过: ' + m)
    if write and changed:
        io.open(REV, 'w', encoding='utf-8', newline='').write(md)
        print('  已写回 ' + os.path.basename(REV))
    elif not write:
        print('  (试跑; 加 --write 才真改)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
