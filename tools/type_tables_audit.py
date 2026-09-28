# -*- coding: utf-8 -*-
"""type_tables_audit.py — 装备类型的四张表必须是同一个键集。

★由来(2026-08-20): `TYPES` 里 2026-08-13 加了「香火」, 而 `TYPE_ICON`(当时叫 TYPE_EMOJI) /
  `TYPE_NAME` 都没加 ⇒ 取图标时静默回落成剑, 界面上香火羁绊显示成一把剑。
  **四张表并排放着, 加类型时只改了一张** —— 这类"平行表"是最容易漏的形状:
  漏了不报错、不崩溃, 只是悄悄显示成别的东西。

★为什么是门禁而不是"下次记得改":
  我 2026-08-20 把四张表填齐了, 但那只是"此刻是对的"。加第 12 个类型时同样会漏一张。
  只有让它**漏了就红**, 这个形状才算根除。

★判据落在**解析出来的键集**上, 不是"文件里有没有出现某个字符串" ——
  后者会被注释里的提及骗到。
"""
import io, os, re, sys

sys.stdout.reconfigure(encoding='utf-8')

SRC = 'scripts/gamedata/phase2_types.gd'
TABLES = ['TYPES', 'TYPE_ICON', 'TYPE_NAME', 'TIER_DESCS']

## ★★2026-09-28 `TYPE_EMOJI` → `TYPE_ICON`(类型图标 emoji → assets/sprites/tags 像素图)。
##   **光改表名是不够的** —— 键集一致守不住「值里到底是什么」:
##     · 值被换回一个 emoji  ⇒ 键集照样一致, 本审计器绿
##     · 值被打成错路径      ⇒ 键集照样一致, 本审计器绿
##     · 值被改成空串        ⇒ 键集照样一致, 本审计器绿
##   三种都是**界面上悄悄不画一个图标 / 画成另一张图**, 不报错不崩溃。
## ⇒ 加一节【值的形状】: 逐个类型的图标必须是 tags/tag-*.png 且**文件真的在盘上**。
##   这一张表与 `CodexScene.TYPE_STYLE` 的 `icon` 是同一批文件, 两张一起查。
ICON_TABLES = [
    (SRC, 'TYPE_ICON', None),                                   # 商店/出战/战斗HUD/背包羁绊面板
    ('scripts/scenes/CodexScene.gd', 'TYPE_STYLE', 'icon'),      # 图鉴(值是 dict, 取 icon 这一项)
]
ICON_DIR_PREFIX = 'res://assets/sprites/tags/tag-'


def keys_of(src, name):
    """取【顶层】键。三张表是"一行多个键", TYPES 的值里还有嵌套 dict ——
    所以既不能按行取(会漏同行的后几个), 也不能全抓(会抓进 tiers/stats)。
    按**花括号深度**走一遍, 只收深度 1 的键。"""
    i = src.index("const " + name)
    i = src.index("{", i) if "{" in src[i:i+80] else src.index("[", i)
    depth = 0
    keys = set()
    k = i
    while k < len(src):
        c = src[k]
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
            if depth == 0:
                break
        elif c == chr(34) and depth == 1:
            e = src.index(chr(34), k + 1)
            rest = src[e + 1:e + 3]
            if rest.lstrip().startswith(":"):
                keys.add(src[k + 1:e])
            k = e
        k += 1
    return keys

## ★★★2026-09-28 平行表**不止住在一个文件里**。
##   `CodexScene.TYPE_STYLE` 是第五张(羁绊页的颜色+图标)，而本审计器的 SRC 写死
##   `phase2_types.gd` ⇒ **那张表从来不在视野里**。
## ★后果不是假想: 斧头 2026-08-31 进了 TYPES，TYPE_STYLE 没跟着加 ⇒ 羁绊页把斧头
##   画成默认的 🔗。而**同一张表同一个病 2026-08-15 在「香火」上刚犯过一次** ——
##   那次补完了数据，却没做「让门禁盯住它」这一步，于是原样重演。
## ⇒ 扫描范围改成「一张表 = (文件, 表名)」。以后再有第六张，加一行即可。
EXTRA_TABLES = [('scripts/scenes/CodexScene.gd', 'TYPE_STYLE')]


def main():
    src = io.open(SRC, encoding='utf-8').read()
    ks = {}
    for t in TABLES:
        try:
            ks[t] = keys_of(src, t)
        except ValueError:
            print('[FAIL] 找不到 const %s —— 表被改名或删了, 这是空检查不是通过' % t)
            return 1
    for path, t in EXTRA_TABLES:
        label = '%s::%s' % (path.split('/')[-1], t)
        try:
            ks[label] = keys_of(io.open(path, encoding='utf-8').read(), t)
        except (ValueError, IOError, OSError):
            print('[FAIL] 找不到 %s —— 表被改名/搬家了, 这是空检查不是通过' % label)
            return 1

    base = ks['TYPES']
    print('[分母] %s: %d 个类型 (%s)' % ('TYPES', len(base), ' '.join(sorted(base))))
    if len(base) < 5:
        print('[FAIL] TYPES 只解析出 %d 个 —— 解析失效了, 不是真的只有这么少' % len(base))
        return 1

    bad = []
    for t in TABLES[1:] + ['%s::%s' % (p.split('/')[-1], n) for p, n in EXTRA_TABLES]:
        miss = sorted(base - ks[t])
        extra = sorted(ks[t] - base)
        print('  %-12s %2d 个%s%s' % (
            t, len(ks[t]),
            ('  缺: ' + ','.join(miss)) if miss else '',
            ('  多: ' + ','.join(extra)) if extra else ''))
        if miss or extra:
            bad.append((t, miss, extra))

    if bad:
        print('\n[FAIL] 类型表键集不一致 %d 张:' % len(bad))
        for t, miss, extra in bad:
            print('   %s  缺 %s  多 %s' % (t, miss or '无', extra or '无'))
        print('\n  后果不是崩溃, 是**静默显示成别的东西**(缺 emoji ⇒ 回落成 🗡️)。')
        return 1
    rc = check_icon_values()
    if rc != 0:
        return rc
    print('\nALL OK — 四张类型表键集一致 + 两张图标表的值都指向盘上的 tags/*.png')
    return 0


def icon_values_of(src, name, subkey):
    """顶层键 → 图标路径。subkey=None 时值本身就是路径; 否则值是 dict, 取 dict[subkey]。

    ★与 keys_of 同一条走法(按花括号深度), 因为同样的理由: 一行多个键 / 值里有嵌套 dict。
      只多做一件事 —— **把值也收下来**。键集一致守不住值里是什么。"""
    i = src.index('const ' + name)
    i = src.index('{', i)
    depth = 0
    out = {}
    cur = None            # 当前顶层键
    want_sub = False      # 刚读到 subkey 这个子键 ⇒ 下一个字符串就是它的值
    k = i
    while k < len(src):
        c = src[k]
        if c in '{[':
            depth += 1
        elif c in '}]':
            depth -= 1
            if depth == 0:
                break
        elif c == chr(34):
            e = src.index(chr(34), k + 1)
            tok = src[k + 1:e]
            is_key = src[e + 1:e + 3].lstrip().startswith(':')
            if depth == 1:
                if is_key:
                    cur = tok
                elif cur is not None and subkey is None:
                    out[cur] = tok
                    cur = None
            elif depth == 2 and cur is not None and subkey is not None:
                if is_key:
                    want_sub = (tok == subkey)
                elif want_sub:
                    out[cur] = tok
                    want_sub = False
            k = e
        k += 1
    return out


def check_icon_values():
    """★★【值的形状】: 每个类型的图标必须是 tags/tag-*.png, 而且文件真的在盘上。

    由来(2026-09-28): 把某个类型的 icon **删掉 / 打错路径 / 换回一个 emoji**,
    全仓一条判据都不会红 —— 键集一致(本审计器旧版)、静态 emoji 台账看不到、
    运行时什么都不画也不报错。三种都是"悄悄少一个图标 / 画成另一张图"。
    ⇒ 这一节把三种全钉住, 两张图标表一起。"""
    print('')
    bad = []
    for path, name, subkey in ICON_TABLES:
        label = '%s::%s' % (path.split('/')[-1], name)
        try:
            vals = icon_values_of(io.open(path, encoding='utf-8').read(), name, subkey)
        except (ValueError, IOError, OSError):
            print('[FAIL] %s 解析不出来 —— 表被改名/搬家了, 这是空检查不是通过' % label)
            return 1
        # ★分母: 解析不出值就是空检查。12 个类型, 少于 5 个一定是解析失效。
        if len(vals) < 5:
            print('[FAIL] %s 只解析出 %d 个值 —— 解析失效了, 不是真的只有这么少'
                  % (label, len(vals)))
            return 1
        uniq = set(vals.values())
        print('  %-26s %2d 个值 / %2d 张互不相同的图' % (label, len(vals), len(uniq)))
        for t in sorted(vals):
            v = vals[t]
            if not v.startswith(ICON_DIR_PREFIX) or not v.endswith('.png'):
                bad.append('%s 的「%s」= %r 不是 %s*.png(emoji/空串/写错都在这一支)'
                           % (label, t, v, ICON_DIR_PREFIX))
                continue
            if not os.path.isfile(v.replace('res://', '')):
                bad.append('%s 的「%s」→ %s 文件不在盘上' % (label, t, v))
        # ★同一张图被两个类型共用 = 分不清谁是谁(「香火显示成一把剑」的另一种长相)。
        if len(uniq) != len(vals):
            bad.append('%s 有类型共用同一张图(%d 个值只有 %d 张图)'
                       % (label, len(vals), len(uniq)))
    if bad:
        print('\n[FAIL] 图标值 %d 处不对:' % len(bad))
        for b in bad:
            print('   %s' % b)
        print('\n  后果不是崩溃, 是**界面上悄悄少一个图标 / 画成另一张图**。')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
