# -*- coding: utf-8 -*-
"""text_golden.py — 玩家文案的快照对账(Golden / Approval Test)。

★由来(2026-08-20, 用户「到底网上怎么处理」): 行业里治"文案悄悄变了没人知道"的标准做法之一
  就是 Golden/Approval Test —— 把**渲染后的**文案整份存档, 下次跑跟存档比,
  **一个字不一样就红**, 逼人明确确认这次改动是有意的。
  它不需要理解文案的含义, 所以覆盖面是 100%(不像数值审计器只能覆盖它认识的形状)。

★为什么比"人肉复查"强: 今晚实测, 同一段文案在五个层里各写一份, 改一层另外四层不会跟。
  Golden 不管你改哪一层 —— 只要**玩家看到的字**变了, 它就把新旧两版摆出来。

★快照里存的是 `{C:类名.常量}` **展开之后**的文本:
  · 改代码常量 ⇒ 玩家看到的数变了 ⇒ 快照 diff 出来 ✅(这正是要抓的)
  · 改一句话   ⇒ 同上 ✅
  · 只是把写死的数字换成等值的 {C:...} ⇒ 展开后一样 ⇒ **不报**(那次改动确实没改变玩家看到的东西)

用法:
  python tools/text_golden.py            # 对账(进门禁)
  python tools/text_golden.py --update   # 确认这次改动是有意的, 重写快照
"""
import io, json, os, re, sys, glob

sys.stdout.reconfigure(encoding='utf-8')

GOLD = 'tests/golden/text_snapshot.txt'
TEXT_KEYS = ['brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3']
# 结尾可带 % ⇒ 值×100(代码里比例存小数, 文案写百分比)
CREF = re.compile(r'\{C:([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)(%?)\}')


def const_map():
    """class_name → {常量名: 渲染后的字符串}。数组按本项目惯例渲染成 a/b/c。"""
    out = {}
    for f in glob.glob('scripts/**/*.gd', recursive=True):
        s = io.open(f, encoding='utf-8').read()
        cm = re.search(r'(?m)^class_name\s+(\w+)', s)
        if not cm:
            continue
        d = {}
        for m in re.finditer(
                r'(?m)^\s*const\s+([A-Z][A-Z0-9_]*)\s*(?::=|=|:\s*\w+\s*=)\s*([^#\n]+)', s):
            nm, val = m.group(1), m.group(2).strip().rstrip(',')
            if re.fullmatch(r'-?\d+(?:\.\d+)?', val):
                v = float(val)
                d[nm] = str(int(v)) if v == int(v) else str(v)
            elif re.fullmatch(r'\[\s*-?[\d.]+(?:\s*,\s*-?[\d.]+)*\s*\]', val):
                parts = []
                for x in re.findall(r'-?[\d.]+', val):
                    fx = float(x)
                    parts.append(str(int(fx)) if fx == int(fx) else str(fx))
                d[nm] = '/'.join(parts)
        out[cm.group(1)] = d
    return out


def expand(t, cmap):
    def rep(m):
        v = cmap.get(m.group(1), {}).get(m.group(2))
        # ★取不到就原样留着 —— 不静默变成空, 否则"引用写错了"会伪装成"文案没变"
        if v is None:
            return m.group(0)
        if m.group(3) == "%":
            try:
                f = float(v) * 100.0
                return str(int(f)) if f == int(f) else str(f)
            except ValueError:
                return m.group(0)
        return v
    return CREF.sub(rep, t)


## 换行必须转成字面 backslash-n, 否则一段多行文案会被拆成多行, 快照行数对不上、比对全乱。
## (2026-08-20 踩到: heredoc 把源码里的双反斜杠收成了真换行, 替换变成"换行换成换行"的空操作。
##  用 chr(92) 构造反斜杠可以绕开这类被中间层吃掉转义的问题。)
def collect(cmap):
    rows = []

    def walk(o, path, src):
        if isinstance(o, dict):
            nm = o.get('name') or o.get('id') or ''
            for k in TEXT_KEYS:
                v = o.get(k)
                if isinstance(v, str) and v.strip():
                    rows.append('%s|%s%s|%s|%s' % (
                        src, path, nm, k, expand(v, cmap).replace(chr(10), chr(92) + "n").replace(chr(13), "")))
            for k, v in o.items():
                if not (isinstance(v, str) and k in TEXT_KEYS):
                    walk(v, path + (str(nm) + '/' if nm else ''), src)
        elif isinstance(o, list):
            for x in o:
                walk(x, path, src)

    for f, tag in [('data/pets.json', 'pet'), ('data/phase2-equipment.json', 'eq')]:
        walk(json.load(io.open(f, encoding='utf-8')), '', tag)
    rows.sort()
    return rows


def main():
    cmap = const_map()
    rows = collect(cmap)
    print('[分母] 快照 %d 段文案 · 解析到 %d 个类的常量表'
          % (len(rows), len(cmap)))
    if len(rows) < 200:
        print('\n[FAIL] 只收到 %d 段 —— 收集失效了, 这是空检查不是通过' % len(rows))
        return 1

    if '--update' in sys.argv:
        os.makedirs(os.path.dirname(GOLD), exist_ok=True)
        io.open(GOLD, 'w', encoding='utf-8', newline='\n').write('\n'.join(rows) + '\n')
        print('\n已重写快照 %s (%d 段)' % (GOLD, len(rows)))
        return 0

    if not os.path.exists(GOLD):
        print('\n[FAIL] 快照不存在 —— 先跑 `python tools/text_golden.py --update`')
        return 1

    old = io.open(GOLD, encoding='utf-8').read().rstrip('\n').split('\n')
    ok = {r.rsplit('|', 1)[0]: r.rsplit('|', 1)[1] for r in old if '|' in r}
    nk = {r.rsplit('|', 1)[0]: r.rsplit('|', 1)[1] for r in rows if '|' in r}
    added = sorted(set(nk) - set(ok))
    removed = sorted(set(ok) - set(nk))
    changed = sorted(k for k in set(ok) & set(nk) if ok[k] != nk[k])

    if not (added or removed or changed):
        print('\nALL OK — 玩家看到的文案与快照一字不差')
        return 0

    print('\n[FAIL] 文案变了: 新增 %d · 删除 %d · 改动 %d'
          % (len(added), len(removed), len(changed)))
    for k in changed[:6]:
        print('   改  %s' % k)
        ## ★只印开头 110 字等于没印 —— 改动往往在句子中段, 人得自己数字符找。
        ##   改成【只印真正不同的那一段 + 左右各 30 字上下文】。
        a, b = ok[k], nk[k]
        i = 0
        while i < min(len(a), len(b)) and a[i] == b[i]:
            i += 1
        j = 0
        while j < min(len(a), len(b)) - i and a[len(a)-1-j] == b[len(b)-1-j]:
            j += 1
        lo = max(0, i - 30)
        pre = ('…' if lo > 0 else '')
        print('       旧: %s%s【%s】%s%s' % (pre, a[lo:i], a[i:len(a)-j], a[len(a)-j:len(a)-j+30],
                                            '…' if len(a)-j+30 < len(a) else ''))
        print('       新: %s%s【%s】%s%s' % (pre, b[lo:i], b[i:len(b)-j], b[len(b)-j:len(b)-j+30],
                                            '…' if len(b)-j+30 < len(b) else ''))
    for k in added[:4]:
        print('   增  %s' % k)
    for k in removed[:4]:
        print('   删  %s' % k)
    print('\n  确认这次改动是有意的 ⇒ `python tools/text_golden.py --update` 并把快照一起提交。')
    return 1


if __name__ == '__main__':
    sys.exit(main())
