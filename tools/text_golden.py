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
  python tools/text_golden.py             # 对账(进门禁)
  python tools/text_golden.py --gd-list   # 把 .gd 侧**全部**改/增/删逐条列出(对账时用)
  python tools/text_golden.py --update    # 确认这次改动是有意的, 重写两份快照
"""
import difflib, io, json, os, re, sys, glob

sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # 让 `import gd_text_scan` 在任何 cwd 下都成

GOLD = 'tests/golden/text_snapshot.txt'

## ══════════════════════════════════════════════════════════════════════
##  洞 ②：`.gd` 的屏幕文案**一条快照都没有** (2026-09-28 补)
## ══════════════════════════════════════════════════════════════════════
## 在此之前四条 golden(text_golden / text_prose_guard / text_value_golden /
## number_coverage) **只覆盖 data/pets.json + data/phase2-equipment.json**。
## 而屏幕上大半的字在 `scripts/scenes/**.gd` 里 —— 一句都没存快照
## ⇒「文案悄悄变了」在 .gd 侧完全看不见。
## 2026-09-27~28 二十几个 agent 并行改文案就撞上这个:
## **没有任何机制能说出谁改了哪句。**
##
## ★★为什么是**独立的一份**快照文件而不是混进现有 487 段:
##   混了会让现有判据的分母含义变味 —— 「487 段 = data 侧玩家文案」是别的审计器
##   引用的那个数(number_coverage / text_prose_guard 都按它对账)。
##   ⇒ 两份快照、两份分母、两段 diff, 一次 `--update` 一起重写。
GOLD_GD = 'tests/golden/gd_text_snapshot.txt'
## 取料走共享抽取器 `tools/gd_text_scan.py`(codex_text_lint 也从它取) ——
## memory [[fb-hand-rolled-copies-drift]]: 两边各写一遍正则, 抄一次就永远落后。
GD_ROOTS = ['scripts', 'autoload']
TEXT_KEYS = ['brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3']
# 结尾可带 % ⇒ 值×100(代码里比例存小数, 文案写百分比)
CREF = re.compile(r'\{C:([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)(%?)\}')


CONST_RE = re.compile(r'(?m)^\s*const\s+([A-Z][A-Z0-9_]*)\s*(?::=|=|:\s*\w+\s*=)\s*([^#\n]+)')


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
        ## ★★2026-08-22 支持【推导式常量】: const BURN_LIFE := float(BURN_TICKS) * BURN_TICK_SEC
        ##   推导是**正确设计**(总时长由次数×间隔算出, 不存第二份), 所以该教这个工具,
        ##   不该为了迁就工具而在代码里手写第二个 5.0。
        ##   只认“由本类已知常量 + 数字 + 四则运算 + float()/int()”组成的表达式。
        for m2 in re.finditer(CONST_RE, s):
            nm, val = m2.group(1), m2.group(2).strip().rstrip(chr(44))
            if nm in d:
                continue
            expr = re.sub(r"(?:float|int)\s*\(", "(", val)
            names = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", expr))
            if not names or not names.issubset(set(d.keys())):
                continue
            if not re.fullmatch(r"[A-Za-z0-9_.+*/() -]+", expr):
                continue
            env = {}
            ok = True
            for k in names:
                try:
                    env[k] = float(d[k])
                except ValueError:
                    ok = False
                    break
            if not ok:
                continue
            try:
                v2 = eval(expr, {"__builtins__": {}}, env)
            except Exception:
                continue
            if isinstance(v2, (int, float)):
                d[nm] = str(int(v2)) if float(v2) == int(v2) else str(float(v2))
        out[cm.group(1)] = d
    return out


def expand(t, cmap):
    def rep(m):
        v = cmap.get(m.group(1), {}).get(m.group(2))
        # ★取不到就原样留着 —— 不静默变成空, 否则"引用写错了"会伪装成"文案没变"
        if v is None:
            return m.group(0)
        if m.group(3) == "%":
            ## ★★数组(const_map 已拼成 a/b/c)也要逐项 ×100 —— 与游戏 `SkillText.const_of` 同一条规则。
            ##   原来这里 `float("0.03/0.06/0.1")` 抛 ValueError ⇒ 被 except 接住**原样留下占位符** ⇒
            ##   快照里存的是没展开的 `{C:EqBladeBatch.HH_MELEE_AMP%}`, 不是玩家看到的字。
            ##   于是游戏里显示「0.03/0.06/0.1%」这条审计从来没看见(2026-09-15 第九批 D1)。
            ##   round(…, 6): 0.03×100 = 3.0000000000000004, 不修整会渲成长尾小数(游戏侧用 is_equal_approx)。
            try:
                parts = []
                for x in str(v).split('/'):
                    f = round(float(x) * 100.0, 6)
                    parts.append(str(int(f)) if f == int(f) else str(f))
                return '/'.join(parts)
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


def collect_gd():
    """`.gd` 里含中文的字符串字面量 → 快照行 `路径|落点|原文`。

    ★**不记行号**: 7 个 agent 同时在改 scripts/, 按行号存快照等于每次提交都红,
      而「某句话挪了两行」根本不是这条门禁要抓的事 —— 它要抓的是**字变了**。
    ★同一文件里同一句话出现多次会去重(集合)。代价写在这里免得下一个人以为它全覆盖:
      「三处相同的字里只改了一处」看到的 diff 是"删一条增一条", 照样红, 但数不准。
    """
    import gd_text_scan as G
    rows, st = G.scan(GD_ROOTS)
    out = set()
    for path, _ln, sink, txt, _why in rows:
        out.add('%s|%s|%s' % (path, sink,
                              txt.replace(chr(10), chr(92) + 'n').replace(chr(13), '')))
    return sorted(out), st


def _gd_diff(old_rows, new_rows):
    """`.gd` 快照对账。→ 0/1。与 data 侧那段 diff **分开**打, 分母不混。

    ★★这里**不能**像 data 侧那样拿"键→值"比: data 侧的键是
      `pet|小龟/|brief`(主体+字段, 天然唯一), 而 .gd 侧一个文件的同一个落点下
      有**几十条**串。第一版拿 `path|sink` 当键, 于是 653 段只比了 ~60 个键 ——
      判据没错、**范围不含出问题的地方**, 正是这一轮在补的同一个形状(反向验证时露出来的)。
    ⇒ `.gd` 侧**原文本身就是身份的一部分**, 没有"键"这一维 ⇒ 直接比**行集合**。
      改一句话 = 一删一增; 下面再把同一 (文件, 落点) 下的一删一增配成可读的「改」。
    """
    o = set(r for r in old_rows if r.strip())
    n = set(r for r in new_rows if r.strip())
    ## ★分母: 真正逐条比了多少段。为 0 就是空检查, 不是"文案没变"。
    print('       [对账分母] 旧快照 %d 段 ↔ 本轮 %d 段 · 逐条(路径+落点+原文)比'
          % (len(o), len(n)))
    added = sorted(n - o)
    removed = sorted(o - n)
    if not (added or removed):
        return 0
    ## 同一 (文件, 落点) 下配对 —— 只为**打印好看**, 不影响判定
    def key2(r):
        a = r.split('|')
        return (a[0], a[1])

    def body(r):
        return r.split('|', 2)[2]

    pool = {}
    for r in removed:
        pool.setdefault(key2(r), []).append(r)
    pairs = []
    left_add = []
    for r in added:
        cand = pool.get(key2(r), [])
        if not cand:
            left_add.append(r)
            continue
        ## 最像的那条当"它的旧版"(difflib 相似度, 不是公共前缀)。
        ## ⚠ 不够像就**不配对** —— 一个文件的 `lit` 落点下有几十条串, 硬配会印出
        ##   「旧: 你不在这个桶里 · 只能观战 / 新: 你」这种**看着像改了实际是两码事**
        ##   的行。判定不受影响(增/删数一样), 但人会照着它找错地方 ⇒ 比不印更坏。
        ##   阈值 0.55 是拿 a5627f5f「去 AI 味九屏」那次真实改动调的: 199 条硬配里
        ##   只有 ~50 条是真同一句的改写。
        best = max(cand, key=lambda x: difflib.SequenceMatcher(None, body(x), body(r)).ratio())
        if difflib.SequenceMatcher(None, body(best), body(r)).ratio() >= 0.55:
            cand.remove(best)
            pairs.append((best, r))
        else:
            left_add.append(r)
    left_rm = [r for v in pool.values() for r in v]
    print('')
    print('[FAIL] .gd 屏幕文案变了: 改 %d · 新增 %d · 删除 %d'
          % (len(pairs), len(left_add), len(left_rm)))
    ## ★★`--gd-list`: 把**全部**改/增/删逐条打出来。
    ##   默认只印前 10/8/8 是给"顺手看一眼"用的; 而这份快照的全部价值在
    ##   **能说出谁改了哪句** —— 真要对账时 15 万字符的 diff 对人不友好,
    ##   所以给一个只印「增了哪几句 / 删了哪几句」的模式。
    _lim = 10 if '--gd-list' not in sys.argv else len(pairs)
    _lim2 = 8 if '--gd-list' not in sys.argv else max(len(left_add), len(left_rm))
    for a, b in pairs[:_lim]:
        print('   改  %s|%s' % (key2(a)[0], key2(a)[1]))
        print('       旧: %s' % body(a)[:150])
        print('       新: %s' % body(b)[:150])
    for r in left_add[:_lim2]:
        print('   增  %s|%s  「%s」' % (key2(r)[0], key2(r)[1], body(r)[:80]))
    for r in left_rm[:_lim2]:
        print('   删  %s|%s  「%s」' % (key2(r)[0], key2(r)[1], body(r)[:80]))
    print('')
    print('  ★这一份就是补「20 个 agent 并行改文案, 没人说得出谁改了哪句」那个洞的。')
    print('    确认这次改动是有意的 ⇒ `python tools/text_golden.py --update`, 两份快照一起提交。')
    return 1



def main():
    cmap = const_map()
    rows = collect(cmap)
    grows, gst = collect_gd()
    n_sink = len([r for r in grows if r.split('|')[1] != 'lit'])
    print('[分母] data 侧快照 %d 段文案 · 解析到 %d 个类的常量表'
          % (len(rows), len(cmap)))
    print('[分母] .gd 屏幕侧快照 %d 段(洞② 2026-09-28 补) · 扫 %d 个 .gd · 抽出含中文字面量 %d 条'
          % (len(grows), gst['files'], gst['lits']))
    print('       其中落点明确(.text/.tooltip_text/.placeholder_text/add_text…) %d 条 · 落点不明但含中文 %d 条'
          % (n_sink, len(grows) - n_sink))
    ## ★分母下限: 实测 1400+, 卡 800 留足余量。低于它 = 取料器坏了, **那不是"文案没变"**。
    if len(grows) < 800:
        print('')
        print('[FAIL] .gd 侧只收到 %d 段(<800) —— 取料失效了, 这是空检查不是通过' % len(grows))
        return 1
    if len(rows) < 200:
        print('\n[FAIL] 只收到 %d 段 —— 收集失效了, 这是空检查不是通过' % len(rows))
        return 1

    if '--update' in sys.argv:
        os.makedirs(os.path.dirname(GOLD), exist_ok=True)
        io.open(GOLD, 'w', encoding='utf-8', newline='\n').write('\n'.join(rows) + '\n')
        io.open(GOLD_GD, 'w', encoding='utf-8', newline='\n').write('\n'.join(grows) + '\n')
        print('\n已重写快照 %s (%d 段) + %s (%d 段)'
              % (GOLD, len(rows), GOLD_GD, len(grows)))
        return 0

    if not os.path.exists(GOLD) or not os.path.exists(GOLD_GD):
        print('\n[FAIL] 快照不存在 —— 先跑 `python tools/text_golden.py --update`')
        return 1
    ## 洞②: .gd 那一份**单独**对账(独立快照/独立分母/独立 diff, 不和 data 侧的 487 段混)
    _gold_gd = io.open(GOLD_GD, encoding='utf-8').read().rstrip('\n').split('\n')
    gd_rc = _gd_diff(_gold_gd, grows)

    old = io.open(GOLD, encoding='utf-8').read().rstrip('\n').split('\n')
    ok = {r.rsplit('|', 1)[0]: r.rsplit('|', 1)[1] for r in old if '|' in r}
    nk = {r.rsplit('|', 1)[0]: r.rsplit('|', 1)[1] for r in rows if '|' in r}
    added = sorted(set(nk) - set(ok))
    removed = sorted(set(ok) - set(nk))
    changed = sorted(k for k in set(ok) & set(nk) if ok[k] != nk[k])

    if not (added or removed or changed):
        if gd_rc:
            return 1
        print('\nALL OK — 玩家看到的文案与快照一字不差(data 侧 %d 段 + .gd 屏幕侧 %d 段)'
              % (len(rows), len(grows)))
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
    return 1                       # (.gd 侧若也变了, 上面 `_gd_diff` 已把它单独打出来)


if __name__ == '__main__':
    sys.exit(main())
