# -*- coding: utf-8 -*-
"""text_value_golden.py — 玩家文案里每个占位符【算出来的那个数】的金样本。

★为什么要有它(2026-08-25, 一次真事故):
  `tools/text_golden.py` 存的是**原文**, 所以把 `{N:1.5*ATK}` 改成
  `{N:DiceSystem.ALLIN_DMG*ATK}` 时它只报"这行变了", **报不出数变没变**。
  那次事故里无头龟的公式被接到骰子龟的常量上, 数从 1.5 变成 0.5,
  而**渲染门禁全绿**(它确实渲染得出一个数)、原文金样本也只说"改了一行"。
  最后是 `text_formula_audit` 用另一条路(文字 ↔ 公式)抓到的 —— 那条只覆盖
  「同时写了百分比文字」的 125 句, 剩下的没有任何人验。

⇒ 这条门禁把每个占位符在**同一组样本属性**下算出的数存下来。
  根除工作的每一步都应当**值不变**: 只是把手写的 1.5 换成"代码里的那个 1.5"。
  值一旦变了, 要么是接错了常量(事故), 要么是真的改了平衡(那就 --update 并说明)。

★判据落在【算出来的数】, 不落在原文 —— 原文本来就要变, 那正是根除在做的事。

    python tools/text_value_golden.py            # 比对(进门禁)
    python tools/text_value_golden.py --update   # 确认改动是有意的, 更新快照
"""
import io, json, os, re, sys, importlib.util

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNAP = os.path.join(ROOT, 'tests/golden/text_values.txt')

# 复用 text_formula_audit 的常量解析(★不另抄一份 —— 抄一次永远落后一次)
_spec = importlib.util.spec_from_file_location(
    'tfa', os.path.join(ROOT, 'tools/text_formula_audit.py'))
_tfa = importlib.util.module_from_spec(_spec)
## ★它在模块级就把整套审计跑完并打印, 吞输出有三个坑, 三个都踩过:
##   ① 它重绑 `sys.stdout = TextIOWrapper(sys.stdout.buffer, ...)` ⇒ 顶替物必须有 `.buffer`
##      (StringIO 没有);
##   ② 那一行会**接管**我给的流, 我这边的包装器一被回收就把底层关掉,
##      于是它自己后面的 print 撞上 "I/O operation on closed file";
##      ⇒ 用 devnull 并**在模块级持一个强引用**, 不让它被回收;
##   ③ 它可能 sys.exit。
_devnull = io.open(os.devnull, 'w', encoding='utf-8')
_old = sys.stdout
try:
    sys.stdout = _devnull
    try:
        _spec.loader.exec_module(_tfa)
    except SystemExit:
        pass
finally:
    sys.stdout = _old

PH = re.compile(r'\{([A-Z])[:：]([^{}]+)\}')
CONST_REF = re.compile(r'[A-Z][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]{2,}')
IDENT = re.compile(r'(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_]*)')
TEXT_KEYS = {'brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3'}

## 样本属性。★取值刻意【互不相同且非整倍数】: 若两个不同变量取同一个数,
##   把 `DEF` 写成 `MR` 这种错就会算出同样的结果 = 门禁看不见。
VARS = {
    'ATK': 137.0, 'DEF': 53.0, 'MR': 29.0, 'HP': 1811.0,
    'rockLayers': 7.0, 'stacks': 3.0, 'layers': 4.0, 'lvl': 5.0,
}


def collect():
    out = []

    def walk(o, path, src):
        if isinstance(o, dict):
            nm = o.get('name') or o.get('id') or ''
            for k, v in o.items():
                if isinstance(v, str) and k in TEXT_KEYS:
                    out.append(('%s|%s%s|%s' % (src, path, nm, k), v))
                else:
                    walk(v, path + (str(nm) + '/' if nm else ''), src)
        elif isinstance(o, list):
            for x in o:
                walk(x, path, src)

    for f, tag in [('data/pets.json', 'pet'), ('data/phase2-equipment.json', 'eq')]:
        walk(json.load(io.open(os.path.join(ROOT, f), encoding='utf-8')), '', tag)
    return out


def value_of(expr, unknown):
    """把表达式里的常量换成数、变量换成样本值, 再算。算不动返回 None。"""
    e = CONST_REF.sub(lambda m: _tfa._const_num(m.group(0)) or 'NOCONST', expr)
    if 'NOCONST' in e:
        return None

    def sub_ident(m):
        n = m.group(1)
        if n in VARS:
            return repr(VARS[n])
        unknown.add(n)
        return '1.0'

    e = IDENT.sub(sub_ident, e)
    if re.search(r'[^0-9eE\.\+\-\*/\(\)\s]', e):
        return None
    try:
        return round(float(eval(e, {'__builtins__': {}}, {})), 6)   # noqa: S307 — 已过白名单
    except Exception:
        return None


def snapshot():
    """每段文案 → 它所有占位符算出来的值(排序后的多重集)。

    ★为什么按【段落 → 值的多重集】而不是【第几个占位符 → 值】:
      根除工作**天天往同一段里插新占位符**(把占位符外面的裸数字也转掉),
      一插后面所有占位符的序号全错位 ⇒ 按序号存会每批报几十个假"变了"。
      多重集不受插入位置影响。
    ★判据(见 main): 旧值必须仍是新值的**子多重集** —— 根除只会让值【多】,
      不会让某个值【消失】: 把 1.5 改写成引用同值常量, 值还在;
      把外面的裸数字转成占位符, 是新增一个值。**某个值不见了 = 接错常量。**
    """
    rows = []
    unknown = set()
    for who, t in collect():
        vals = []
        for m in PH.finditer(t):
            color, expr = m.group(1), m.group(2)
            if color == 'C':
                raw = _tfa.expand_c('{C:%s}' % expr.rstrip('%'))
                if raw.startswith('{C:'):
                    continue
                vals.append(round(float(raw) * (100.0 if expr.endswith('%') else 1.0), 6))
                continue
            v = value_of(expr, unknown)
            if v is not None:
                vals.append(v)
        if vals:
            rows.append('%s\t%s' % (who, ' '.join(str(x) for x in sorted(vals))))
    return rows, unknown


def main():
    update = '--update' in sys.argv
    rows, unknown = snapshot()
    cur = {}
    for r in rows:
        k, _t, v = r.partition('\t')
        cur[k] = v
    if update or not os.path.exists(SNAP):
        io.open(SNAP, 'w', encoding='utf-8', newline='\n').write('\n'.join(sorted(rows)) + '\n')
        print('快照已写: %d 个占位符的值 → %s' % (len(rows), os.path.relpath(SNAP, ROOT)))
        if unknown:
            print('  (公式里出现、但不在样本表里的变量, 一律按 1.0 代入: %s)'
                  % ', '.join(sorted(unknown)))
        return 0
    old = {}
    for ln in io.open(SNAP, encoding='utf-8'):
        k, _t, v = ln.rstrip('\n').partition('\t')
        if k:
            old[k] = v
    import collections
    lost = []      # (段落, 消失了的值)
    added = 0
    gone_seg = [k for k in old if k not in cur]
    n_val = 0
    for k, ov in old.items():
        if k not in cur:
            continue
        a = collections.Counter(ov.split())
        b = collections.Counter(cur[k].split())
        n_val += sum(a.values())
        miss = a - b
        if miss:
            lost.append((k, ' '.join(sorted(miss.elements()))))
        added += sum((b - a).values())

    print('[分母] 快照 %d 段 / %d 个值; 本次 %d 段' % (len(old), n_val, len(cur)))
    if not old or n_val == 0:
        print('[FAIL] 快照是空的 —— 空检查不是通过')
        return 1
    if lost:
        print('')
        print('★★ 有 %d 段里的值【消失】了 —— 根除只会让值变多, 不会让值不见:' % len(lost))
        for k, v in lost[:25]:
            print('   %-52s 丢了: %s' % (k[:52], v))
            print('        旧: %s' % old[k][:96])
            print('        新: %s' % cur[k][:96])
        if len(lost) > 25:
            print('   ... 另 %d 段' % (len(lost) - 25))
    if gone_seg:
        print('')
        print('  整段消失 %d 段: %s' % (len(gone_seg), ', '.join(gone_seg[:6])))
    if added:
        print('  新增 %d 个值(把占位符外的裸数字转进来了, 正常)' % added)
    if lost or gone_seg:
        print('')
        print('[FAIL] 有值消失了。若是有意的平衡改动 ⇒ --update 并在提交信息里说明。')
        return 1
    print('')
    print('ALL OK — 旧的值一个都没丢')
    return 0


if __name__ == '__main__':
    sys.exit(main())
