# -*- coding: utf-8 -*-
"""给【装备文案里剩下的裸数字】定位它在代码里的出处, 并判断能不能自动接常量。

由来(2026-08-25): 棘轮剩 365, 其中装备侧 186 个全在占位符【外面】
(effectDesc/effectBrief 里的"5 秒""250 码""8 点"), 而且同一个数在 desc 和 brief
各写一遍 —— 抽一个常量能同时消掉两个。

## 判据(★为什么敢自动提)
装备的实现散在三处: `eq_*_batch.gd`(077~094) / `RealtimeBattle3DScene.gd` 的 `_eq_*`
/ `equip_system.gd`。定位办法**不猜文件**, 而是**全仓扫**「提到这件 id 的行」,
以那些行为锚点取上下 ±N 行的窗口, 在窗口里找:
  · 已有常量 == 这个值 且【只有一个】      → 可自动接
  · 窗口里有裸字面量 == 这个值             → 要先抽常量(报出 file:line 供人写)
  · 都没有                                → 这个数在代码里根本不存在(**可能是文案在编**)

★第三类最值钱 —— 它不是"还没转"而是"文案说了代码没有的事"。
  第 58 批就抓到过一个(冰霜瓶写了个代码里不存在的机制)。

    python tools/equip_const_locator.py           # 列清单
    python tools/equip_const_locator.py --auto    # 只列可自动接的
"""
import io, json, os, re, sys, glob

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PLACEHOLDER = re.compile(r'\{[A-Z]?:?[^}]*\}')
TAG = re.compile(r'<[^>]+>')
NUM = re.compile(r'(?<![\w.])\d+(?:\.\d+)?')
TRIPLE = re.compile(r'\d+(?:\.\d+)?/\d+(?:\.\d+)?/\d+(?:\.\d+)?')
LABEL_NUM = re.compile(r'(?:00|01|10|11)=')
NOISE = {'0', '1', '2', '3'}
CONST_DEF = re.compile(r'^\s*const\s+([A-Z][A-Z0-9_]*)\s*:?=\s*(-?[\d.]+)')

WIN = 60          # 锚点上下各取多少行当窗口
SRC_GLOBS = ['scripts/**/*.gd']


def load_sources():
    out = {}
    for g in SRC_GLOBS:
        for p in glob.glob(os.path.join(ROOT, g), recursive=True):
            rel = os.path.relpath(p, ROOT).replace(chr(92), '/')
            out[rel] = io.open(p, encoding='utf-8', errors='replace').read().split('\n')
    return out


def num_eq(a, b):
    try:
        return abs(float(a) - float(b)) < 1e-9
    except ValueError:
        return False


def main():
    only_auto = '--auto' in sys.argv
    src = load_sources()
    eq = json.load(io.open(os.path.join(ROOT, 'data/phase2-equipment.json'), encoding='utf-8'))
    lst = eq if isinstance(eq, list) else next(v for v in eq.values() if isinstance(v, list))

    auto, need_const, ghost = [], [], []
    n_total = 0
    for e in lst:
        eid = str(e.get('id', ''))
        name = str(e.get('name', ''))
        want = []
        for k in ('effectDesc1', 'effectDesc2', 'effectDesc3', 'effectBrief'):
            t = str(e.get(k) or '')
            if not t:
                continue
            body = TAG.sub('', PLACEHOLDER.sub(' ', t))
            body = LABEL_NUM.sub(' ', TRIPLE.sub(' ', body))
            for x in NUM.findall(body):
                if x not in NOISE:
                    want.append((k, x))
        if not want:
            continue
        ## 这件装备在代码里的所有锚点行。
        ## ★★2026-08-25 只按 `eid` 锚定会**造出假的「文案在编」**: 实现代码常常
        ##   一次都不写 id —— dragon_system.gd 里 `p2eq_024` 出现 **0 次**, 而 88 码
        ##   就写在它第 20 行。第一版因此把 024/033/058/070 四条报成"代码里找不到",
        ##   逐条查完**四条全是我的盲区**。⇒ 三路锚定: id / 三位数注释 / 中文名。
        num3 = eid.split('_')[-1]        # "024"
        anchors = [eid, name]
        wins = []          # (file, lineno0, lines)
        for f, lines in src.items():
            for i, ln in enumerate(lines):
                hit = any(a and a in ln for a in anchors)
                if not hit and num3 in ln and ('#' in ln or 'func ' in ln):
                    hit = True           # `# 033: 海螺阵亡→变小虫` / `func _eq_033(...)`
                if hit:
                    wins.append((f, i, lines))
        ## ★★2026-08-25 第二次收紧。「窗口里有一个同值常量」**判据太松** ——
        ##   实测 35 条提案里**约一半是垃圾**: 复活海螺的 2.5 秒被接到
        ##   `SHOTGUN_PELLET_DEG`(散弹角度)、龙蛋的 2.5 接到 `TAME_REVIVE_SEC`(驯服复活)。
        ##   本轮已经栽过一次同形状(骰子龟 ALLIN_DMG), 而且**所有门禁都会绿**
        ##   (它确实渲染得出数字、常量也确实有人读)。
        ## ⇒ 判据换成【归属】而不是【邻近】:
        ##    这个常量必须有一处**使用点**(不是声明行), 其**所在函数**提到这件装备
        ##    (id / `# 0NN` / 中文名)。函数是代码自己划的边界, 比"±60 行"这个我拍的数字可信。
        vals = {}          # 值 → 常量名集合(通过归属校验的)
        lits = {}          # 值 → [file:line]
        for f, i, lines in wins:
            lo, hi = max(0, i - WIN), min(len(lines), i + WIN)
            for j in range(lo, hi):
                for x in NUM.findall(lines[j]):
                    lits.setdefault(x, set()).add('%s:%d' % (f, j + 1))
        # 全仓的常量声明: 名字 → 值
        allc = {}
        for f, lines in src.items():
            for ln in lines:
                m = CONST_DEF.match(ln)
                if m:
                    allc[m.group(1)] = m.group(2)
        # 归属校验: 常量的使用点所在函数, 要提到这件装备
        for cname, cval in allc.items():
            if not any(num_eq(cval, x) for _k, x in want):
                continue
            for f, lines in src.items():
                for j, ln in enumerate(lines):
                    if cname not in ln or CONST_DEF.match(ln):
                        continue
                    # 往上找到所在 func 头, 再取整个函数体
                    a = j
                    while a > 0 and not lines[a].startswith('func ') and not lines[a].startswith('static func '):
                        a -= 1
                    b = j
                    while b + 1 < len(lines) and not (lines[b + 1].startswith('func ')
                                                     or lines[b + 1].startswith('static func ')):
                        b += 1
                    # 函数头往上的文档注释也算(实现说明常写在那)
                    c = a
                    while c > 0 and lines[c - 1].lstrip().startswith('#'):
                        c -= 1
                    blob = chr(10).join(lines[c:b + 1])
                    if eid in blob or (name and name in blob) or ('%s' % num3) in blob:
                        vals.setdefault(cval, set()).add(cname)
                        break
        for k, x in want:
            n_total += 1
            cands = set()
            for v, names in vals.items():
                if num_eq(v, x):
                    cands |= names
            if len(cands) == 1:
                auto.append((eid, name, k, x, sorted(cands)[0]))
            elif len(cands) > 1:
                need_const.append((eid, name, k, x, '歧义:' + ','.join(sorted(cands))))
            else:
                sites = set()
                for v, s in lits.items():
                    if num_eq(v, x):
                        sites |= s
                if sites:
                    need_const.append((eid, name, k, x, '裸字面量@' + ';'.join(sorted(sites)[:2])))
                else:
                    ghost.append((eid, name, k, x))

    print('=' * 74)
    print('  装备文案裸数字 → 代码出处  定位器      (窗口 ±%d 行)' % WIN)
    print('=' * 74)
    print('  分母: 装备文案里没人验的裸数字 %d 个' % n_total)
    print('  ✔ 窗口里恰好一个同值常量(可自动接): %d' % len(auto))
    print('  ○ 有出处但还没抽常量 / 歧义:        %d' % len(need_const))
    print('  ★ 代码里【根本找不到这个值】:       %d   ← 优先看这类' % len(ghost))
    print()
    if ghost:
        print('  ★★ 找不到出处的(文案可能在编, 或换算过):')
        for eid, name, k, x in ghost:
            print('     %-10s %-8s %-13s %s' % (eid, name[:8], k, x))
        print()
    if not only_auto:
        for eid, name, k, x, why in need_const[:40]:
            print('  ○ %-10s %-8s %-13s %-7s %s' % (eid, name[:8], k, x, why[:60]))
        if len(need_const) > 40:
            print('  ... 另 %d 条' % (len(need_const) - 40))
        print()
    for eid, name, k, x, c in auto:
        print('  ✔ %-10s %-8s %-13s %-7s → %s' % (eid, name[:8], k, x, c))
    return 0


if __name__ == '__main__':
    sys.exit(main())
