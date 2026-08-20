# -*- coding: utf-8 -*-
"""dead_preload_audit.py — 揪出 preload 了却没人用的常量。

★为什么要专门写: preload 会在解析期就把那个脚本拉起来, 但更糟的是它**谎称了一条依赖** ——
  读代码的人以为这里用到了那个模块。2026-08-20 普查出 6 处, 核实后只有 2 处真死。

★另外 4 处为什么不是死的 —— 这条是本审计器存在的全部理由:
  场景脚本里的 `const X := preload(...)` **可以被别的文件用 `host.X` / `battle.X` 跨文件访问**
  (例: `detail_views.gd` 里的 `host.EquipStats.stat_line_all_stars()`、
   `battle_hud.gd` 里的 `battle.VirtualJoystick.new()`)。
  只在**本文件内**数出现次数会把它们全判成死的, 删掉就编译不过。
  (同一个模式在同一天弄崩过一次构建: 删了 `MINION_SKILL_DESC` 而 info_panel 用的是 `battle.MINION_SKILL_DESC`。)
⇒ 判据 = 本文件内 0 次 **且** 全项目没有任何 `<something>.X` 形式的限定引用。
"""
import io, os, re, sys, glob

ROOTS = ['scripts', 'autoload']
DEF = re.compile(r'^[ \t]*(?:const|var)[ \t]+(\w+)[ \t]*(?::=|=|:[ \t]*\w+[ \t]*=)[ \t]*preload\(', re.M)

def main():
    files = []
    for r in ROOTS:
        files += glob.glob(os.path.join(r, '**', '*.gd'), recursive=True)
    srcs = {f: io.open(f, encoding='utf-8').read() for f in files}
    allsrc = '\n'.join(srcs.values())
    for f in glob.glob('tests/**/*.gd', recursive=True):
        allsrc += '\n' + io.open(f, encoding='utf-8').read()

    n_def = 0
    dead = []
    for f, s in srcs.items():
        for m in DEF.finditer(s):
            name = m.group(1)
            n_def += 1
            own = len(re.findall(r'\b' + re.escape(name) + r'\b', s))
            if own > 1:
                continue                      # 本文件自己在用
            qual = re.search(r'\w\.' + re.escape(name) + r'\b', allsrc)
            if qual:
                continue                      # 有 host.X / battle.X 这类跨文件限定引用
            dead.append((f.replace(chr(92), '/'), name))

    print('[分母] 扫到 preload 常量 %d 个 (%d 个文件)' % (n_def, len(files)))
    if not dead:
        print('\nALL OK — 没有"preload 了却没人用"的常量')
        return 0
    print('\n[FAIL] preload 了但全项目没人用 %d 处:' % len(dead))
    for f, n in dead:
        print('   %-52s %s' % (f, n))
    print('\n  (删之前再确认一遍: 有没有 `host.%s` / `battle.%s` 这种限定引用)' % (dead[0][1], dead[0][1]))
    return 1

if __name__ == '__main__':
    sys.exit(main())
