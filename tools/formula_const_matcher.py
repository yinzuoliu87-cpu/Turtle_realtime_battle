# -*- coding: utf-8 -*-
"""给公式占位符里的手写系数**找归属常量**，只提「唯一匹配」的，有歧义的交人判。

由来(2026-08-25): 量清楚"没人验的数字"里有 289 个藏在占位符**内部**
(`{N:0.9*ATK}` 里的那个 0.9), 占 60%。`SkillText.eval_expr` 已支持
`{N:StoneSystem.HIT_ATK_COEF*ATK}` 这种写法, 剩下的活是**给每个系数找到主人**。

## 判据（★为什么敢自动提）
只在**该龟自己的 system 文件里，恰好有且只有一个常量等于这个值**时才提。
· 多个常量同值 → 不提, 列出来给人判(比如海盗的 BLADE_COEF 与 SHIP_ATK_SCALE 都是 1.0,
  自动选一个就是在赌, 赌错了普攻会静默换成船的系数)。
· 没有常量等于这个值 → 不提, 说明那个数还没抽成常量, 得先抽。

**宁可少提, 不可提错** —— 提错的代价是文案指向一个不相干的常量,
而所有门禁都会绿(它确实渲染得出数字、常量也确实有人读)。

    python tools/formula_const_matcher.py            # 列提案 + 歧义
    python tools/formula_const_matcher.py --write    # 写入提案(歧义的不动)
"""
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLS = os.path.join(ROOT, 'scripts/systems/skills')

# 占位符: {颜色:表达式}
PH = re.compile(r'\{([A-Z])[:：]([^{}]+)\}')
# 表达式里的裸数字(排除已是常量引用的部分)
LIT = re.compile(r'(?<![A-Za-z_.\d])(\d+(?:\.\d+)?)(?![\d.]*[A-Za-z_])')
CONST = re.compile(r'^\s*const\s+([A-Z][A-Z0-9_]*)\s*:?=\s*(-?\d+(?:\.\d+)?)\s*(?:#|$)', re.M)

# 这些值在任何文件里都会撞一堆常量, 提了也是赌 —— 直接不提。
TOO_COMMON = {'0', '1', '2', '3', '0.0', '1.0', '2.0'}

# 龟 id → 它的 system 文件(小龟没有自己的 system, 用 basic_consts)
SPECIAL = {'basic': 'scripts/gamedata/basic_consts.gd'}
CLASSNAME = {}


def system_file(pid):
    if pid in SPECIAL:
        return os.path.join(ROOT, SPECIAL[pid])
    p = os.path.join(SKILLS, '%s_system.gd' % pid)
    return p if os.path.exists(p) else None


def consts_of(path):
    s = io.open(path, encoding='utf-8', errors='replace').read()
    m = re.match(r'class_name\s+(\w+)', s)
    cls = m.group(1) if m else None
    out = {}
    for cm in CONST.finditer(s):
        out.setdefault(cm.group(2), []).append(cm.group(1))
    return cls, out


def pets():
    d = json.load(io.open(os.path.join(ROOT, 'data/pets.json'), encoding='utf-8'))
    return d if isinstance(d, list) else next(v for v in d.values() if isinstance(v, list))


def main():
    write = '--write' in sys.argv
    proposals = []      # (pid, 字段路径, 旧占位符, 新占位符)
    ambiguous = []
    nofit = []
    n_ph = 0

    for p in pets():
        pid = str(p.get('id', ''))
        sf = system_file(pid)
        if sf is None:
            continue
        cls, cmap = consts_of(sf)
        if not cls or not cmap:
            continue

        segs = []
        pa = p.get('passive')
        if isinstance(pa, dict):
            segs += [('被动.' + k, pa.get(k)) for k in ('brief', 'desc', 'detail')]
        for sk in (p.get('skillPool') or []):
            segs += [('%s.%s' % (sk.get('name'), k), sk.get(k)) for k in ('brief', 'desc', 'detail')]

        for label, txt in segs:
            if not txt:
                continue
            for m in PH.finditer(str(txt)):
                color, expr = m.group(1), m.group(2)
                if color == 'C':
                    continue
                lits = [x for x in LIT.findall(expr) if x not in TOO_COMMON]
                if not lits:
                    continue
                n_ph += 1
                new_expr = expr
                ok_all = True
                for lit in set(lits):
                    cands = cmap.get(lit, [])
                    # 也认 "0.5" ↔ "0.50" 这种写法差异
                    if not cands:
                        alt = str(float(lit))
                        cands = cmap.get(alt, [])
                    if len(cands) == 1:
                        new_expr = re.sub(
                            r'(?<![A-Za-z_.\d])' + re.escape(lit) + r'(?![\d.]*[A-Za-z_])',
                            '%s.%s' % (cls, cands[0]), new_expr)
                    elif len(cands) > 1:
                        ambiguous.append((pid, label, expr, lit, cands))
                        ok_all = False
                    else:
                        nofit.append((pid, label, expr, lit))
                        ok_all = False
                if ok_all and new_expr != expr:
                    proposals.append((pid, label,
                                      '{%s:%s}' % (color, expr),
                                      '{%s:%s}' % (color, new_expr)))

    print('=' * 66)
    print('  公式系数 → 归属常量  匹配器')
    print('=' * 66)
    print('  分母: 扫到含手写系数的公式占位符 %d 处' % n_ph)
    print('  ✔ 唯一匹配(可自动接): %d' % len(proposals))
    print('  ? 多个常量同值(要人判): %d' % len(ambiguous))
    print('  ✖ 没有常量等于它(得先抽常量): %d' % len(nofit))
    print()
    for pid, label, a, b in proposals[:20]:
        print('  ✔ %-9s %-22s %s' % (pid, label[:22], a))
        print('       → %s' % b)
    if len(proposals) > 20:
        print('  ... 另 %d 条' % (len(proposals) - 20))
    print()
    for pid, label, expr, lit, cands in ambiguous[:12]:
        print('  ? %-9s %-20s %s   里的 %s 撞上: %s' % (pid, label[:20], expr[:26], lit, ','.join(cands)))
    if len(ambiguous) > 12:
        print('  ... 另 %d 条歧义' % (len(ambiguous) - 12))

    if write and proposals:
        ## ★★写入必须【限定在那只龟的段落里】, 不能全局字符串替换 ——
        ##   提案是按龟算的(每只龟查自己的 system 文件), 而同一个 `{N:1.5*ATK}`
        ##   在别的龟身上属于别的常量。第一版做了全局 replace, 结果把
        ##   **无头龟**「万千触须」的公式接到了**骰子龟**的 DiceSystem.ALLIN_DMG 上。
        ##   渲染门禁全绿(它确实渲染得出数字), 是 text_formula_audit 抓的。
        ##
        ## 用**段落切片**而不是 json.dumps 重写: 后者会把整个文件格式重排。
        P = os.path.join(ROOT, 'data/pets.json')
        raw = io.open(P, encoding='utf-8').read()
        by_pid = {}
        for pid, _label, a, b in proposals:
            by_pid.setdefault(pid, []).append((a, b))
        # 每只龟在原文里的区间: 从它的 "id": "x" 到下一个 "id": " 之前
        marks = [(m.group(1), m.start()) for m in re.finditer(r'"id":\s*"([a-z_]+)"', raw)]
        done = 0
        out = raw
        for i, (pid, start) in enumerate(marks):
            reps = by_pid.get(pid, [])
            if not reps:
                continue
            end = marks[i + 1][1] if i + 1 < len(marks) else len(out)
            # 因为替换会改变长度, 从后往前做; 这里先取当前切片再整体拼回
            seg = out[start:end]
            for a, b in reps:
                ja = json.dumps(a, ensure_ascii=False)[1:-1]
                jb = json.dumps(b, ensure_ascii=False)[1:-1]
                c = seg.count(ja)
                if c:
                    seg = seg.replace(ja, jb)
                    done += c
            out = out[:start] + seg + out[end:]
            # 长度变了, 后面的 mark 位置要重算
            marks = [(m.group(1), m.start()) for m in re.finditer(r'"id":\s*"([a-z_]+)"', out)]
        io.open(P, 'w', encoding='utf-8', newline='').write(out)
        json.load(io.open(P, encoding='utf-8'))
        print()
        print('  已写入 %d 处(**限定在各自的龟段落内**, 不跨龟)' % done)
    elif not write:
        print()
        print('  (试跑; 加 --write 才真改)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
