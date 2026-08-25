# -*- coding: utf-8 -*-
"""散文守卫: 去掉占位符与数字之后, 玩家文案的【文字部分】必须逐字不变。

★由来(2026-08-25): 批量转引用的脚本如果位置算错, 会把 token 插进散文中间 ——
  `class="val-{C:X}ef"`(本该 val-def) / `永久 +1{C:X}甲`(本该 +1 护甲) /
  `{{C:A}bcSystem.B}`(插进另一个占位符里)。
  这类损坏**已有门禁全看不见**: 渲染得出数字(绿) / 值没变(绿) / 类名属于本主体(绿) /
  brief↔detail 数值一致(绿)。而且带中文时连"} 后跟字母"这种形状扫描也漏
  (`}甲` 里的"甲"不是 ASCII 字母)。

★判据: 把每段文案里的**占位符整段**与**所有数字**都抹掉, 剩下的纯文字与快照比 ——
  根除工作只应该把"数字"换成"占位符", 一个汉字、一个标点都不该动。
  这条与 `text_value_golden`(管值) / `text_const_owner_audit`(管归属) 三条互补, 覆盖面不重叠。

    python tools/text_prose_guard.py            # 比对(进门禁)
    python tools/text_prose_guard.py --update   # 文案确有文字改动时更新
"""
import io, json, os, re, sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAP = os.path.join(ROOT, 'tests/golden/text_prose.txt')

PH = re.compile(r'\{[^{}]*\}')
NUM = re.compile(r'\d+(?:\.\d+)?')
WS = re.compile(r'\s+')
TEXT_KEYS = {'brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3'}


def prose(t):
    """只留【文字】: 占位符整段抹掉、数字抹掉、空白归一。"""
    t = PH.sub('', t)
    t = NUM.sub('', t)
    return WS.sub(' ', t).strip()


def collect():
    out = []

    def walk(o, path, src):
        if isinstance(o, dict):
            nm = o.get('name') or o.get('id') or ''
            for k, v in o.items():
                if isinstance(v, str) and k in TEXT_KEYS:
                    out.append('%s|%s%s|%s\t%s' % (src, path, nm, k, prose(v)))
                else:
                    walk(v, path + (str(nm) + '/' if nm else ''), src)
        elif isinstance(o, list):
            for x in o:
                walk(x, path, src)

    for f, tag in [('data/pets.json', 'pet'), ('data/phase2-equipment.json', 'eq')]:
        walk(json.load(io.open(os.path.join(ROOT, f), encoding='utf-8')), '', tag)
    return sorted(out)


def main():
    rows = collect()
    if '--update' in sys.argv or not os.path.exists(SNAP):
        io.open(SNAP, 'w', encoding='utf-8', newline='\n').write('\n'.join(rows) + '\n')
        print('散文快照已写: %d 段' % len(rows))
        return 0
    old = {}
    for ln in io.open(SNAP, encoding='utf-8'):
        k, _t, v = ln.rstrip('\n').partition('\t')
        if k:
            old[k] = v
    cur = {}
    for r in rows:
        k, _t, v = r.partition('\t')
        cur[k] = v
    diff = [(k, old[k], cur[k]) for k in old if k in cur and old[k] != cur[k]]
    print('[分母] 快照 %d 段散文' % len(old))
    if len(old) < 300:
        print('[FAIL] ★分母只有 %d —— 空检查不是通过' % len(old))
        return 1
    if diff:
        print('')
        print('★★ 有 %d 段的【文字】变了 —— 转引用不该动任何一个字:' % len(diff))
        for k, a, b in diff[:12]:
            print('   %s' % k)
            print('     旧: …%s…' % a[:110])
            print('     新: …%s…' % b[:110])
        print('')
        print('[FAIL] 文字被改动。若确实在改文案措辞 ⇒ --update 并说明。')
        return 1
    print('')
    print('ALL OK — 文案的文字部分逐字未动')
    return 0


if __name__ == '__main__':
    sys.exit(main())
