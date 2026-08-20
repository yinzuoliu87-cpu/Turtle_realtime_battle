# -*- coding: utf-8 -*-
"""type_tables_audit.py — 装备类型的四张表必须是同一个键集。

★由来(2026-08-20): `TYPES` 里 2026-08-13 加了「香火」, 而 `TYPE_EMOJI` / `TYPE_NAME` 都没加
  ⇒ `emoji_of("香火")` 静默回落成 "🗡️", 界面上香火羁绊显示成一把剑。
  **四张表并排放着, 加类型时只改了一张** —— 这类"平行表"是最容易漏的形状:
  漏了不报错、不崩溃, 只是悄悄显示成别的东西。

★为什么是门禁而不是"下次记得改":
  我 2026-08-20 把四张表填齐了, 但那只是"此刻是对的"。加第 12 个类型时同样会漏一张。
  只有让它**漏了就红**, 这个形状才算根除。

★判据落在**解析出来的键集**上, 不是"文件里有没有出现某个字符串" ——
  后者会被注释里的提及骗到。
"""
import io, re, sys

sys.stdout.reconfigure(encoding='utf-8')

SRC = 'scripts/gamedata/phase2_types.gd'
TABLES = ['TYPES', 'TYPE_EMOJI', 'TYPE_NAME', 'TIER_DESCS']


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

def main():
    src = io.open(SRC, encoding='utf-8').read()
    ks = {}
    for t in TABLES:
        try:
            ks[t] = keys_of(src, t)
        except ValueError:
            print('[FAIL] 找不到 const %s —— 表被改名或删了, 这是空检查不是通过' % t)
            return 1

    base = ks['TYPES']
    print('[分母] %s: %d 个类型 (%s)' % ('TYPES', len(base), ' '.join(sorted(base))))
    if len(base) < 5:
        print('[FAIL] TYPES 只解析出 %d 个 —— 解析失效了, 不是真的只有这么少' % len(base))
        return 1

    bad = []
    for t in TABLES[1:]:
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
    print('\nALL OK — 四张类型表键集一致')
    return 0


if __name__ == '__main__':
    sys.exit(main())
