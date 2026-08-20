# -*- coding: utf-8 -*-
"""twin_const_audit.py — 同一个功能的「逻辑侧 ↔ 演出侧」两个文件里, 同名常量取值不同。

★由来(2026-08-20): 毒雾 `FOG_LIFE` 在 `eq_venom_drone.gd` 是 6.0(用户 2026-08-13 从 4 加强来的),
  在 `venom_drone_vfx.gd` 却还是 4.0。而中毒判定走**演出侧**的 `fog_radius(t)`, 它在 t >= FOG_LIFE
  返回 0 ⇒ **每团毒雾只毒 4 秒**, 那次加强从来没生效过。这是**真 bug 不是文案**,
  而两边注释都写着"门禁要能验两侧一致" —— 写了, 但没人验。

★判据为什么这么窄(先写宽后收窄的记录, 别再放宽):
  先按"全项目同名常量取值不同"扫, 得 **33 处, 绝大多数是假阳** ——
  `CARD_W` 在匹配屏和训龟屏本来就是两张不同的卡、`BOMB_COUNT` 在枪和钩雷是两种炸弹。
  收窄成"**同一功能组内**"(文件名去掉 eq_ / _vfx / _system / _batch 等后同名)之后:
  分母 11 组 / 22 个文件, **命中 1 处, 正是那个真 bug**。
  ⇒ 判据要刚好卡住那个形状: 宽一格造假 bug, 窄一格放过真 bug。

Color / Vector / preload 这类不比 —— 演出侧本来就该有自己的配色。
"""
import io, os, re, sys, glob, collections

DEF = re.compile(
    r'^[ \t]*const[ \t]+([A-Z][A-Z0-9_]{2,})[ \t]*(?::=|:[ \t]*\w+[ \t]*=|=)[ \t]*([^#\n]+)', re.M)
SKIP_PREFIX = ('Color', 'Vector', 'preload', '[Color', 'Rect2')


def stem(p):
    b = os.path.basename(p)[:-3]
    if b.startswith('eq_'):
        b = b[3:]
    for suf in ('_eq_vfx', '_vfx', '_system', '_batch', '_synergy_system', '_synergy'):
        if b.endswith(suf):
            b = b[:-len(suf)]
            break
    return b


def main():
    consts = {}
    for f in glob.glob(os.path.join('scripts', '**', '*.gd'), recursive=True):
        s = io.open(f, encoding='utf-8').read()
        consts[f.replace(chr(92), '/')] = {
            m.group(1): m.group(2).strip().rstrip(',') for m in DEF.finditer(s)}

    groups = collections.defaultdict(list)
    for f in consts:
        groups[stem(f)].append(f)
    groups = {k: v for k, v in groups.items() if len(v) > 1}

    hits = []
    for k, fs in groups.items():
        names = set()
        for f in fs:
            names |= set(consts[f])
        for n in sorted(names):
            vals = {f: consts[f][n] for f in fs if n in consts[f]}
            if len(vals) < 2 or len(set(vals.values())) < 2:
                continue
            if any(v.startswith(SKIP_PREFIX) for v in vals.values()):
                continue
            # ★一侧写成 `别的类名.同名常量` = 它就是在引用另一侧那一份, 这正是我们要的修法,
            #   不能报成分歧(第一版就把自己的正确修法判红了)。
            if any(re.fullmatch(r'\w+\.' + re.escape(n), v) for v in vals.values()):
                continue
            hits.append((k, n, vals))

    print('[分母] %d 个文件 → %d 组"同一功能的多个文件"(共 %d 个文件)'
          % (len(consts), len(groups), sum(len(v) for v in groups.values())))
    if not groups:
        print('\n[FAIL] 一组都没配上 —— 配对规则失效了, 这是空检查不是通过')
        return 1
    if not hits:
        print('\nALL OK — 同功能的逻辑侧/演出侧没有取值打架的同名常量')
        return 0
    print('\n[FAIL] 同一功能组内同名常量取值不同 %d 处:' % len(hits))
    for k, n, vals in hits:
        print('   [%s] %s' % (k, n))
        for f, v in vals.items():
            print('        %-50s = %s' % (f.replace('scripts/', ''), v[:36]))
    print('\n  修法: 让其中一侧 `const X := 另一侧的类名.X`, 从结构上只留一份。')
    return 1


if __name__ == '__main__':
    sys.exit(main())
