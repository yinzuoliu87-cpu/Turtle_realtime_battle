# -*- coding: utf-8 -*-
"""云端同步新鲜度自检(只读·不连网): 事实源文件是否在【上次实际同步】之后又改过。

★判据用的是同步脚本【运行时写出的 report 文件的 mtime】, 不是脚本自身的提交时间 ——
  第一版拿脚本 commit 当基准, 结果"补跑同步"这个动作本身不产生新 commit, 于是补完还报 STALE(误报)。
用途: 防"同步完又改了、以为还是一致的"。报 [STALE] 就补跑对应脚本。
"""
import io, sys, os, subprocess
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 事实源 → (同步脚本, 该脚本运行时写出的报告文件【glob·取最新一份】, 标签)
#
# ★2026-07-28 修: 原来每个事实源只认【一个写死的报告文件】(如 hp_s13_report.txt), 但同一份事实源
#   后来又被 S14/S15/S17 等新批次同步过, 报告文件名不同、还写在 tools/ 而不是 tools/oneoff/ ——
#   于是"明明刚推完云端"却照报 STALE。这种狼来了会让人以后忽略真警报, 所以改成 glob 取最新。
# ★路径 2026-07-21 随「常备工具 / 一次性脚本」分离改到 tools/oneoff/。
#   同步脚本是【一次性批次】(hp_s8..s13), 归 oneoff; 本检查器是【常备】, 留在 tools/。
#   搬完当场跑这个检查器才发现路径写死了 —— 工具搬家必须逐个跑一遍, 不能只看目录整齐了。
ONEOFF = 'tools/oneoff'
PAIRS = [
    ('docs/design/实时版-系统机制权威.md', ONEOFF + '/hp_s8_systems.py',
     [ONEOFF + '/hp_s8_report.txt', 'tools/hp_s8_report.txt'], 'S8  系统机制'),
    ('data/phase2-equipment.json',        ONEOFF + '/hp_s9_equip.py',
     [ONEOFF + '/hp_s9_report.txt', 'tools/hp_s9_report.txt'], 'S9  59件装备'),
    # 28龟这份被多批同步过(S10/S13/S14/S15/S17…) —— 任何一批跑完都算"云端已同步", 取最新
    ('docs/design/28龟技能设计-权威.md',    'tools/oneoff/hp_s17_round3.py (或同类最新批次)',
     ['tools/oneoff/hp_s1*_report.txt', 'tools/hp_s1*_report.txt'], 'S10..S17 28龟'),
]

def file_mtime(p):
    return os.path.getmtime(p) if os.path.exists(p) else None


def newest_mtime(patterns):
    """一组 glob 里最新那份报告的 mtime; 都不存在则 None。"""
    import glob
    ts = []
    for pat in patterns:
        for f in glob.glob(pat):
            t = file_mtime(f)
            if t is not None:
                ts.append(t)
    return max(ts) if ts else None

stale = 0
for src, syncer, report, label in PAIRS:
    t_sync = newest_mtime(report)
    t_src = file_mtime(src)
    if t_sync is None:
        print('  [ ?? ] %-16s 没有任何同步报告 %s → 大概从没同步过' % (label, report)); stale += 1; continue
    if t_src is None:
        print('  [ ?? ] %-16s 事实源不存在: %s' % (label, src)); continue
    if t_src > t_sync + 1.0:      # 1 秒容差
        stale += 1
        print('  [STALE] %-16s %s 改于同步之后 → 补跑 %s' % (label, src, syncer))
    else:
        print('  [ OK  ] %-16s %s' % (label, src))

print('\n%s' % ('云端可能已落后, 见上面 [STALE]' if stale else 'ALL OK — 事实源自上次同步后未再改动'))
sys.exit(1 if stale else 0)
