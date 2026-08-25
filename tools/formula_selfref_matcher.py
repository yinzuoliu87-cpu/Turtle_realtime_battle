# -*- coding: utf-8 -*-
"""公式里的手写系数 → 【同一句话里已经点名的那个常量】。

★这条规则**不是猜**, 是文案自述的绑定。绝大多数详细文案长这样:

    （{C:BambooSystem.LEAF_ATK_COEF%}%×攻击力({ATK}) = {N:0.4*ATK}）

  左边已经写明"这个系数叫 LEAF_ATK_COEF", 右边却又把 0.4 手写了一遍 ——
  **同一个数在同一句话里存了两份**, 右边那份跟代码没有任何绑定。
  于是判据是: 左边点名的常量, 其**值等于**右边公式里乘那个变量的字面量 ⇒ 接上去。

★三重保险(缺一不可, 少一重就变成赌):
  ① 常量必须解析得出数值(`{C:}` 只认 const, 不认 static var);
  ② 该数值必须**等于**要替换掉的字面量(不等 = 文案本身就已经自相矛盾, 报出来给人看);
  ③ 变量必须对得上(攻击力→ATK / 最大生命值→HP / 护甲→DEF / 魔抗→MR),
     否则 `{N:0.4*ATK+HP*0.03}` 里两个系数会互换。
  再加上 `tools/text_value_golden.py` 兜底: 值一旦变了当场红。

    python tools/formula_selfref_matcher.py           # 试跑
    python tools/formula_selfref_matcher.py --write   # 真改
"""
import io, json, os, re, sys, importlib.util

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_spec = importlib.util.spec_from_file_location(
    'tfa', os.path.join(ROOT, 'tools/text_formula_audit.py'))
_tfa = importlib.util.module_from_spec(_spec)
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

VARMAP = {'攻击力': 'ATK', '最大生命值': 'HP', '自身最大生命值': 'HP',
          '护甲': 'DEF', '魔抗': 'MR', '生命值': 'HP'}
# 「{C:类.常量%}% × 中文变量」—— 文案自己点的名
NAMED = re.compile(r'\{C[:：]([A-Za-z][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]{2,})%\}%\s*[×x]\s*'
                   r'(自身最大生命值|最大生命值|攻击力|护甲|魔抗|生命值)')
PH = re.compile(r'\{([A-Z])[:：]([^{}]+)\}')
TEXT_KEYS = ('brief', 'desc', 'detail', 'effectDesc1', 'effectDesc2', 'effectDesc3', 'effectBrief')
LOOKBACK = 240      # 往前找"点名"最多看多少字符


def const_val(ref):
    v = _tfa.expand_c('{C:%s}' % ref)
    if v.startswith('{C:'):
        return None
    try:
        return float(v)
    except ValueError:
        return None


## 反方向: 「<写死的百分比>%×攻击力({ATK}) = {X:<已经是常量引用的公式>}」
##   —— 右边已经指着常量了, 左边那个百分比却还是手写的。它同样是"同一个数存两份",
##   而且方向反过来: 常量改了, 公式跟着变, **左边的百分比不会变** ⇒ 文案自相矛盾。
PCT_THEN_FORMULA = re.compile(
    r'(\d+(?:\.\d+)?)%\s*[×x]\s*(自身最大生命值|最大生命值|攻击力|护甲|魔抗)'
    r'(?:\(\{[A-Z]+\}\))?\s*=\s*(\{[A-Z][:：][^{}]+\})')


def back_convert(text):
    """把「写死的百分比」换成它右边公式里已经在用的那个常量。返回 (新文本, 替换数)。"""
    n = 0
    out = text
    for m in PCT_THEN_FORMULA.finditer(text):
        lit, cn, formula = float(m.group(1)), m.group(2), m.group(3)
        var = VARMAP.get(cn)
        if not var:
            continue
        # 公式里乘这个变量的那个常量
        mm = re.search(r'([A-Z][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]{2,})\s*\*\s*' + var + r'\b', formula) \
            or re.search(var + r'\s*\*\s*([A-Z][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]{2,})', formula)
        if not mm:
            continue
        cv = const_val(mm.group(1))
        if cv is None or abs(cv * 100.0 - lit) > 1e-6:
            continue
        old = m.group(0)
        new = old.replace(m.group(1) + '%', '{C:%s%%}%%' % mm.group(1), 1)
        out = out.replace(old, new, 1)
        n += 1
    return out, n


def convert(text):
    """返回 (新文本, [(旧公式, 新公式)], [不一致的说明])。"""
    reps, warn = [], []
    out = text
    for m in list(PH.finditer(text)):
        color, expr = m.group(1), m.group(2)
        if color == 'C':
            continue
        ## ★往前找"点名"必须**切在句子边界上**。第一版只截 240 字符, 结果捞到上一句
        ##   的常量: 双头龟被动一段里连着写"护甲增加(MELEE_DEF_COEF…)/魔抗增加(…)/
        ##   护盾(MELEE_SHIELD_COEF…)", 240 字符能同时看见三个 —— 靠"值相等"才没接错。
        ##   但**两个同值常量**同时在窗口里时, 值相等就不再能区分 ⇒ 必须先切边界。
        ##   绑定的真实作用域是那一对括号: `（{C:…%}%×攻击力({ATK}) = {N:…}）`。
        head = text[max(0, m.start() - LOOKBACK):m.start()]
        cut = max(head.rfind('）'), head.rfind('。'), head.rfind(chr(10)), head.rfind('；'))
        if cut >= 0:
            head = head[cut + 1:]
        # 这一句里点过名的 常量 → 变量。★倒序: 离公式最近的那个优先。
        named = [(g.group(1), VARMAP[g.group(2)]) for g in NAMED.finditer(head)][::-1]
        if not named:
            continue
        new = expr
        for ref, var in named:
            cv = const_val(ref)
            if cv is None:
                continue
            # 公式里乘这个变量的那个字面量
            pats = [(r'(?<![A-Za-z0-9_.])(\d+(?:\.\d+)?)\s*\*\s*' + var + r'\b', 1),
                    (r'\b' + var + r'\s*\*\s*(\d+(?:\.\d+)?)(?![\d.])', 1)]
            for pat, gi in pats:
                mm = re.search(pat, new)
                if not mm:
                    continue
                lit = float(mm.group(gi))
                if abs(lit - cv) > 1e-9:
                    warn.append('%s 点名 %s(=%s) 但公式里是 %s×%s' % (var, ref, cv, lit, var))
                    continue
                new = new[:mm.start(gi)] + ref + new[mm.end(gi):]
                break
        if new != expr:
            a = '{%s:%s}' % (color, expr)
            b = '{%s:%s}' % (color, new)
            reps.append((a, b))
            out = out.replace(a, b)
    return out, reps, warn


def main():
    write = '--write' in sys.argv
    total = nrep = 0
    warns = []
    for f in ('data/pets.json', 'data/phase2-equipment.json'):
        P = os.path.join(ROOT, f)
        raw = io.open(P, encoding='utf-8').read()
        data = json.loads(raw)
        lst = data if isinstance(data, list) else next(v for v in data.values() if isinstance(v, list))
        out = raw

        def walk(o):
            hits = []
            if isinstance(o, dict):
                for k, v in o.items():
                    if isinstance(v, str) and k in TEXT_KEYS:
                        hits.append(v)
                    else:
                        hits += walk(v)
            elif isinstance(o, list):
                for x in o:
                    hits += walk(x)
            return hits

        ## ★★写入必须【限定在这个主体的段落里】。第一版做的是全局字符串替换,
        ##   后果实测过两次, **两次都是同一个数在别的主体身上属于别的常量**:
        ##     · `{N:1.5*ATK}` → 无头龟「万千触须」接到骰子龟 `DiceSystem.ALLIN_DMG`
        ##     · `{M:0.5*ATK}` → 无头龟「灵魂打击」接到彩虹龟 `RainbowSystem.REFLECT_COEF`
        ##     · `{N:1.0*ATK}` → 天使/忍者/双头/赌神/猎人/海盗/赛博/宝箱 八只全被接到
        ##       石头龟的 `StoneSystem.SLAM_ATK_COEF`
        ##   **五条既有门禁一条都没拦住**(值相等时连值金样本都是绿的),
        ##   所以除了改写入路径, 还新建了 `tools/text_const_owner_audit.py` 守归属。
        for item in lst:
            iid = str(item.get('id', ''))
            if not iid:
                continue
            marks = [(m.group(1), m.start()) for m in re.finditer(r'"id":\s*"([A-Za-z0-9_]+)"', out)]
            idx = [i for i, (q, _s) in enumerate(marks) if q == iid]
            if not idx:
                continue
            i = idx[0]
            start = marks[i][1]
            end = marks[i + 1][1] if i + 1 < len(marks) else len(out)
            seg = out[start:end]
            for t in walk(item):
                total += 1
                ## 第二遍(反方向): 右边已是常量引用, 左边的百分比还写死 ⇒ 从右边反推左边。
                bt, bn = back_convert(t)
                if bn:
                    ja = json.dumps(t, ensure_ascii=False)[1:-1]
                    jb = json.dumps(bt, ensure_ascii=False)[1:-1]
                    if seg.count(ja):
                        nrep += bn
                        if write:
                            seg = seg.replace(ja, jb)
                        else:
                            print('  %-9s [反推] %s' % (iid[:9], ('%s%%→常量' % '写死百分比')))
                        t = bt
                _new, reps, warn = convert(t)
                warns += warn
                for a, b in reps:
                    ja = json.dumps(a, ensure_ascii=False)[1:-1]
                    jb = json.dumps(b, ensure_ascii=False)[1:-1]
                    c = seg.count(ja)
                    if c == 0:
                        continue
                    nrep += c
                    if write:
                        seg = seg.replace(ja, jb)
                    else:
                        print('  %-9s %-42s → %s' % (iid[:9], a[:42], b[:64]))
            if write:
                out = out[:start] + seg + out[end:]
        if write:
            io.open(P, 'w', encoding='utf-8', newline='').write(out)
            json.loads(io.open(P, encoding='utf-8').read())

    print('')
    print('  分母: 扫了 %d 段文案' % total)
    print('  可接(同句已点名 + 值相等 + 变量对得上): %d 处' % nrep)
    if warns:
        print('')
        print('  ★文案自相矛盾(点名的常量值 ≠ 公式里的数) %d 条 —— 这类【不动】, 交人判:' % len(warns))
        for w in sorted(set(warns))[:20]:
            print('     %s' % w)
    print('')
    print('  已写入' if write else '  (试跑; 加 --write 才真改)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
