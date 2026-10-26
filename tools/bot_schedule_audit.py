# -*- coding: utf-8 -*-
"""bot_schedule_audit.py — 常驻陪练号排班表的硬约束(方案书 docs/plans/20261026d-服务器常驻陪练号.md)。

量的是 server/referee/bot_schedule.py 产出的真表(不是重抄一遍它的算法):
  ① 规模公式: 上周真人 0 / 50 / 200 ⇒ 90 / 50 / 30(clamp(100 − 真人, 30, 90))
  ② 每个号本周积分赛 ≤ 16 场(RANKED_QUOTA), 认真 / 冲得快的恰好 16
  ③ 积分赛上线全在周二 00:00 ~ 周五 22:30 之间开打(22:50 封盘); 闯关赛在周六 00:00 ~ 周日 17:30
  ④ 冲得快的那批: 积分赛全在周二
  ⑤ 同场次覆盖: 周二 20:00 时, 第 1~16 场每档都至少 MIN_COVER 份陪练快照(严格同场次配对, 不垫就只剩 0~2 份)
  ⑥ 同一个种子两次生成逐字相同(每周可复现)
分母: 排出来的号数与上线次数都 > 0。
"""
import datetime as dt
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location('bot_schedule', os.path.join(ROOT, 'server', 'referee', 'bot_schedule.py'))
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

MIN_COVER = 3
fails = []


def ok(name: str, cond: bool, detail: str = '') -> None:
    print('  [%s] %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


monday = dt.datetime(2026, 11, 16, tzinfo=dt.timezone.utc)
ok('① 规模公式 0/50/200 ⇒ 90/50/30', [bs.bot_count(0), bs.bot_count(50), bs.bot_count(200)] == [90, 50, 30],
   str([bs.bot_count(0), bs.bot_count(50), bs.bot_count(200)]))
plan = bs.build(monday, 90, 20261116)
bots = plan['plan']
n_sess = sum(len(b['sessions']) for b in bots)
ok('分母: 排出 90 个号、上线次数 > 0', len(bots) == 90 and n_sess > 0, '%d 号 / %d 次' % (len(bots), n_sess))
over = [b['slot'] for b in bots if sum(s['rounds'] for s in b['sessions'] if s['mode'] == 'ranked') > bs.QUOTA]
full = [b['slot'] for b in bots if b['kind'] in ('hardcore', 'fast')
        and sum(s['rounds'] for s in b['sessions'] if s['mode'] == 'ranked') != bs.QUOTA]
ok('② 每号积分赛 ≤ %d 场' % bs.QUOTA, not over, str(over[:5]))
ok('② 认真 / 冲得快的恰好 %d 场' % bs.QUOTA, not full, str(full[:5]))
r_lo = monday + dt.timedelta(days=1)
r_hi = monday + dt.timedelta(days=4, hours=22, minutes=30)
g_lo = monday + dt.timedelta(days=5)
g_hi = monday + dt.timedelta(days=6, hours=17, minutes=30)
bad_r, bad_g, bad_fast = [], [], []
for b in bots:
    for s in b['sessions']:
        t = dt.datetime.fromisoformat(s['at'])
        if s['mode'] == 'ranked' and not (r_lo <= t < r_hi):
            bad_r.append((b['slot'], s['at']))
        if s['mode'] == 'gauntlet' and not (g_lo <= t < g_hi):
            bad_g.append((b['slot'], s['at']))
        if b['kind'] == 'fast' and s['mode'] == 'ranked' and (t - monday).days != 1:
            bad_fast.append((b['slot'], s['at']))
ok('③ 积分赛上线都在周二 00:00 ~ 周五 22:30', not bad_r, str(bad_r[:3]))
ok('③ 闯关赛上线都在周六 00:00 ~ 周日 17:30', not bad_g, str(bad_g[:3]))
ok('④ 冲得快的积分赛全在周二', not bad_fast and any(b['kind'] == 'fast' for b in bots), str(bad_fast[:3]))
at = monday + dt.timedelta(days=1, hours=20)
cnt = [0] * bs.QUOTA
for b in bots:
    n = 0
    for s in b['sessions']:
        if s['mode'] != 'ranked':
            continue
        t = dt.datetime.fromisoformat(s['at'])
        for _ in range(s['rounds']):
            if t <= at:
                cnt[n] += 1
            n += 1
ok('⑤ 周二 20:00 第 1~%d 场每档 ≥ %d 份陪练快照' % (bs.QUOTA, MIN_COVER), min(cnt) >= MIN_COVER, str(cnt))
ok('⑥ 同一种子两次生成逐字相同', bs.build(monday, 90, 20261116) == plan)
print('ALL OK — 陪练号排班表硬约束' if not fails else 'FAILED: %d 条' % len(fails))
sys.exit(1 if fails else 0)
