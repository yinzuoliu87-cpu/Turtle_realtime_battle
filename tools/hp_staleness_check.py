# -*- coding: utf-8 -*-
"""云端同步新鲜度自检(只读·不连网): 上次同步之后, 这几个事实源文件又改过几次?
用途: 防"同步完又改了、以为还是一致的"。改动 >0 就该补跑对应的 hp_sXX 脚本。"""
import io, sys, subprocess
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 事实源 → 负责同步它的脚本
PAIRS = [
    ('docs/design/实时版-系统机制权威.md', 'tools/hp_s8_systems.py',  'S8  系统机制'),
    ('data/phase2-equipment.json',        'tools/hp_s9_equip.py',    'S9  59件装备'),
    ('docs/design/28龟技能设计-权威.md',    'tools/hp_s13_resync.py',  'S10/S13 28龟'),
]
def last_commit(path):
    r = subprocess.run(['git', 'log', '-1', '--format=%H', '--', path], capture_output=True, text=True, encoding='utf-8')
    return r.stdout.strip()

stale = 0
for src, syncer, label in PAIRS:
    base = last_commit(syncer)
    if not base:
        print('  [ ?? ] %-16s 找不到同步脚本的提交: %s' % (label, syncer)); continue
    r = subprocess.run(['git', 'log', '--oneline', '%s..HEAD' % base, '--', src], capture_output=True, text=True, encoding='utf-8')
    n = len([x for x in r.stdout.strip().split('\n') if x])
    if n:
        stale += 1
        print('  [STALE] %-16s %s 在上次同步后改了 %d 次 → 该补跑 %s' % (label, src, n, syncer))
    else:
        print('  [ OK  ] %-16s %s' % (label, src))
print('\n%s' % ('云端可能已落后, 见上面 [STALE]' if stale else 'ALL OK — 事实源自上次同步后未再改动'))
sys.exit(1 if stale else 0)
