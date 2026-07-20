# -*- coding: utf-8 -*-
"""云端同步新鲜度自检(只读·不连网): 事实源文件是否在【上次实际同步】之后又改过。

★判据用的是同步脚本【运行时写出的 report 文件的 mtime】, 不是脚本自身的提交时间 ——
  第一版拿脚本 commit 当基准, 结果"补跑同步"这个动作本身不产生新 commit, 于是补完还报 STALE(误报)。
用途: 防"同步完又改了、以为还是一致的"。报 [STALE] 就补跑对应脚本。
"""
import io, sys, os, subprocess
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 事实源 → (同步脚本, 该脚本运行时写出的报告文件, 标签)
PAIRS = [
    ('docs/design/实时版-系统机制权威.md', 'tools/hp_s8_systems.py', 'tools/hp_s8_report.txt',  'S8  系统机制'),
    ('data/phase2-equipment.json',        'tools/hp_s9_equip.py',   'tools/hp_s9_report.txt',  'S9  59件装备'),
    ('docs/design/28龟技能设计-权威.md',    'tools/hp_s13_resync.py', 'tools/hp_s13_report.txt', 'S10/S13 28龟'),
]

def file_mtime(p):
    return os.path.getmtime(p) if os.path.exists(p) else None

stale = 0
for src, syncer, report, label in PAIRS:
    t_sync = file_mtime(report)
    t_src = file_mtime(src)
    if t_sync is None:
        print('  [ ?? ] %-16s 没有同步报告 %s → 大概从没同步过' % (label, report)); stale += 1; continue
    if t_src is None:
        print('  [ ?? ] %-16s 事实源不存在: %s' % (label, src)); continue
    if t_src > t_sync + 1.0:      # 1 秒容差
        stale += 1
        print('  [STALE] %-16s %s 改于同步之后 → 补跑 %s' % (label, src, syncer))
    else:
        print('  [ OK  ] %-16s %s' % (label, src))

print('\n%s' % ('云端可能已落后, 见上面 [STALE]' if stale else 'ALL OK — 事实源自上次同步后未再改动'))
sys.exit(1 if stale else 0)
