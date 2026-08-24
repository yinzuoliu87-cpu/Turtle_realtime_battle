# -*- coding: utf-8 -*-
"""文案占位符指向的常量, 必须【真的有产品代码读它】。

由来(2026-08-24·根除第 22 批): 我在第 19 批给财神加了 `LOWHP_TRIGGER := 0.20`,
文案改成指它。门禁全绿 —— 因为它确实渲染成了 20%。
但产品真正读的是【早就存在】的 `LOWHP_PCT`(battle_damage.gd:445), 值也是 0.20。
于是同一个数存了两份, 文案指着没人读的那份。

**这正是根除本身要消灭的毛病, 却被根除动作制造了出来。**
只要以后有人改 LOWHP_PCT 而没改 LOWHP_TRIGGER, 文案就开始说谎, 而且
所有现有门禁都发现不了 —— 它们只验"占位符能渲染成数字", 不问"这个数字是不是活的"。

判据: 每个 `{C:Class.CONST}` 引用的常量, 在【声明行以外】至少还有一处 .gd 引用。
      零引用 = 它只为文案而活 = 天然会漂 ⇒ FAIL。

豁免只在**结构上不可能被引用**时给, 且每条必须写清为什么(见 EXEMPT)。
"""
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSONS = ['data/pets.json', 'data/phase2-equipment.json']

# 豁免表: (Class, CONST) -> 为什么它不可能有第二处引用。
# ★给豁免 = 承认这个数会漂, 所以每条都得说明真值由谁保证。
EXEMPT = {
    ('BambooSystem', 'SPIKE_KNOCK_SEC'):
        '击飞滞空秒数不是被读的输入, 是 _knockback(70, 2.75) 抛物线【算出来的输出】; '
        '代码里没有"1.5"这个量可引用。真值由 verify_bamboo_spikes 的落地耗时断言守。',
    ('DiamondSystem', 'SMASH_KNOCK_DIST'):
        '击退距离同样是输出不是输入 —— 代码给的是 push_mult(RealtimeBattle3DScene.DIAMOND_SMASH_PUSH '
        '= 9.25, headless 探针 @60fps 调出来的), 300 码是它跑出来的结果; 源码里没有 300 可引用。',
    ('EqFoodBatch', 'CAKE_COUNT'):
        '糖糕块数 = CAKE_LINES.size(), 代码遍历数组不读计数; '
        'const 不能写 CAKE_LINES.size()(GDScript 常量表达式不允许调方法)。下面有等值校验。',
}

# 结构性等值校验: 豁免掉的常量若能和别的常量对上, 就在这里对, 别只靠注释。
DERIVED = [
    ('EqFoodBatch', 'CAKE_COUNT', 'EqFoodBatch', 'CAKE_LINES', 'len'),
]

# 击飞调用不在常量所在文件时, 在这里登记它在哪(仍要人工确认过)。
KNOCK_ELSEWHERE = {
    ('BasicConsts', 'CHI_KNOCK_SEC'): 'RealtimeBattle3DScene._sk_basic_chi',
    ('BasicConsts', 'SHIELD_KNOCK_SEC'): 'RealtimeBattle3DScene._sk_basic_shield',
    ('EquipTickSystem', 'BEAR_WAVE_KNOCK_SEC'): 'RealtimeBattle3DScene 熊冲击波',
}

REF = re.compile(r'\{C:([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)%?\}')


def walk_gd():
    for base in ('scripts', 'autoload', 'tests'):
        d = os.path.join(ROOT, base)
        if not os.path.isdir(d):
            continue
        for dp, _, fns in os.walk(d):
            for fn in fns:
                if fn.endswith('.gd'):
                    yield os.path.join(dp, fn)


def main():
    srcs = {}
    for p in walk_gd():
        srcs[p] = io.open(p, encoding='utf-8', errors='replace').read()

    # class_name -> 文件
    owner = {}
    for p, s in srcs.items():
        m = re.match(r'class_name\s+(\w+)', s)
        if m:
            owner[m.group(1)] = p

    refs = {}
    for jp in JSONS:
        raw = io.open(os.path.join(ROOT, jp), encoding='utf-8').read()
        for cls, const in REF.findall(raw):
            refs.setdefault((cls, const), 0)
            refs[(cls, const)] += 1

    print('=' * 66)
    print('  文案常量「有没有人读」体检')
    print('=' * 66)
    print('  分母: 文案里出现 %d 个不同的 {C:Class.CONST} 引用' % len(refs))
    if len(refs) < 40:
        print('  [FAIL] 分母太小(%d < 40) —— 扫串了, 不是真通过' % len(refs))
        return 1

    fails = []
    orphan_ok = []
    derived = []
    knock = []
    for (cls, const), _n in sorted(refs.items()):
        fp = owner.get(cls)
        if fp is None:
            # 主场景那种没 class_name 的走文件名兜底
            cand = [p for p in srcs if os.path.basename(p)[:-3].replace('_', '').lower() == cls.lower()]
            if not cand:
                cand = [p for p in srcs if os.path.basename(p) == cls + '.gd']
            if not cand:
                fails.append('%s.%s —— 找不到声明 class_name %s 的文件' % (cls, const, cls))
                continue
            fp = cand[0]

        decl = re.compile(r'^\s*const\s+' + re.escape(const) + r'\s*:?=', re.M)
        if not decl.search(srcs[fp]):
            fails.append('%s.%s —— %s 里没有这个 const' % (cls, const, os.path.basename(fp)))
            continue

        # 声明行以外的引用(全仓)
        use = re.compile(r'\b' + re.escape(const) + r'\b')
        hits = 0
        for p, s in srcs.items():
            for line in s.split('\n'):
                if not use.search(line):
                    continue
                if p == fp and decl.search(line + '\n'):
                    continue          # 自己的声明行不算
                if line.lstrip().startswith('#'):
                    continue          # 注释里提到不算"有人读"
                hits += 1
        # 推导常量(值本身就是别的常量算出来的)结构上不可能漂 —— 自动豁免。
        dm = re.search(r'^\s*const\s+' + re.escape(const) + r'\s*:?=\s*(.+?)\s*(?:#|$)',
                       srcs[fp], re.M)
        if hits == 0 and dm and re.search(r'[A-Z][A-Z0-9_]{2,}', dm.group(1)):
            derived.append((cls, const, dm.group(1)))
            continue

        # ★族豁免: `*_KNOCK_SEC` = 击飞【滞空秒数】。它不是代码读的输入, 是
        #   _knockback(dist, vy_mult) / _knock_up(vy) 抛物线【算出来的输出】——
        #   源码里根本没有"0.82"这样一个量可以引用。
        #   第二只眼: 该文件必须真的在调击飞, 否则就是机制被删了而文案还在吹。
        if hits == 0 and const.endswith('_KNOCK_SEC'):
            if re.search(r'_knock(back|_up)\s*\(', srcs[fp]) or KNOCK_ELSEWHERE.get((cls, const)):
                knock.append((cls, const))
                continue
            fails.append('%s.%s —— 豁免不成立: %s 里根本没有击飞调用'
                         % (cls, const, os.path.basename(fp)))
            continue

        if hits == 0:
            if (cls, const) in EXEMPT:
                orphan_ok.append((cls, const))
            else:
                fails.append('%s.%s —— 只有文案在指它, 没有任何产品代码读 (声明在 %s)'
                             % (cls, const, os.path.basename(fp)))

    # 豁免项的结构性等值校验
    for cls_a, ca, cls_b, cb, mode in DERIVED:
        fa, fb = owner.get(cls_a), owner.get(cls_b)
        if not fa or not fb:
            fails.append('等值校验找不到文件: %s / %s' % (cls_a, cls_b))
            continue
        va = re.search(r'^\s*const\s+' + ca + r'\s*:?=\s*(.+?)\s*(?:#|$)', srcs[fa], re.M)
        vb = re.search(r'^\s*const\s+' + cb + r'\s*:?=\s*(.+?)\s*(?:#|$)', srcs[fb], re.M)
        if not va or not vb:
            fails.append('等值校验读不到常量值: %s.%s / %s.%s' % (cls_a, ca, cls_b, cb))
            continue
        if mode == 'len':
            n = len([x for x in vb.group(1).strip(' []').split(',') if x.strip()])
            if int(float(va.group(1))) != n:
                fails.append('%s.%s = %s, 但 %s.%s 有 %d 项 —— 对不上'
                             % (cls_a, ca, va.group(1), cls_b, cb, n))
            else:
                print('  [ OK ] 等值校验 %s.%s(%s) == len(%s.%s)=%d'
                      % (cls_a, ca, va.group(1), cls_b, cb, n))

    if knock:
        print('  [族豁免] %d 个 *_KNOCK_SEC —— 滞空秒数是抛物线的输出不是输入; '
              '已逐个确认所在文件真的在调击飞:' % len(knock))
        print('           ' + ' '.join('%s.%s' % (c, k) for c, k in knock))
    if derived:
        print('  [推导] %d 个常量的值是别的常量算出来的(结构上不可能漂, 自动豁免):' % len(derived))
        for cls, const, expr in derived[:6]:
            print('         %s.%s = %s' % (cls, const, expr))
        if len(derived) > 6:
            print('         ... 另 %d 个' % (len(derived) - 6))
    for cls, const in orphan_ok:
        print('  [豁免] %s.%s —— %s' % (cls, const, EXEMPT[(cls, const)].split(';')[0]))

    if fails:
        print()
        for f in fails:
            print('  [FAIL] ' + f)
        print()
        print('FAIL x%d — 文案常量「有没有人读」体检' % len(fails))
        return 1

    print('  [ OK ] %d 个文案常量全部有产品代码在读(豁免 %d 条·各有结构性理由)'
          % (len(refs), len(orphan_ok)))
    print()
    print('ALL OK — 文案常量「有没有人读」体检')
    return 0


if __name__ == '__main__':
    sys.exit(main())
