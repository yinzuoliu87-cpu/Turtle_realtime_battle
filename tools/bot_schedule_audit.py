# -*- coding: utf-8 -*-
"""bot_schedule_audit.py — 常驻陪练号排班表的硬约束(方案书 docs/plans/20261026d-服务器常驻陪练号.md)。

量的是 server/referee/bot_schedule.py 产出的真表(不是重抄一遍它的算法), 而且是**线上真会出的那些表**:
  种子 = 当周周一日期的序号(monday.toordinal(), 即 bot_schedule.main 不给 --seed 时的默认),
  扫 2026-10-26 起 WEEKS 周 × N = 30 / 150 / 300(规模下限 / 中间 / 上限)。②~⑤ 逐份表量。
  ① 规模公式: 上周真人 0 / 50 / 280 ⇒ 300 / 250 / 30(clamp(300 − 真人, 30, 300); 10-27 用户「不能300-上周真人数吗」, 原 100 / 90)
  ② 每个号本周积分赛 ≤ 16 场(RANKED_QUOTA), 认真 / 冲得快的恰好 16
  ③ 积分赛上线全在周二 00:00 ~ 周五 22:30 之间开打(22:50 封盘); 闯关赛在周六 00:00 ~ 周日 17:30
  ④ 冲得快的那批: 积分赛全在周二
  ⑤ 同场次覆盖: 每一份表在周二 20:00 时, 第 1~16 场每档都至少 MIN_COVER 份陪练快照(严格同场次配对) ——
     任何一周、任何一档 N 不达标就红。
     ⑤a 按开打时刻算(这次上线 20:00 前开打, 这几局都算有了; 与 bot_schedule.summary 同一把尺)
     ⑤b 按打完时刻算(第 j 局到 开打 + j × ROUND_MIN 分钟才有快照) —— 量的是「真人 20:00 打第 k 场时真有人可配」
  ⑥ 同一个种子两次生成逐字相同(每周可复现)
  ⑦ 真入口: 命令行 --week <周一> 与 --week <周二>(周一没跑上、周二补跑)出的表 == build(周一, N, 周一.toordinal())
     —— 证明上面扫的种子就是线上用的种子, 不是门禁自己编的。
★2026-10-27 之前 ⑤ 只量了**一个固定种子 20261116** 的一周, 而线上种子根本不是它。按真实种子一扫,
  旧排法 N=90 有 4 周、N=60 有 16 周、N=30 有 48 周不达标(10-26 这周 N=90 第 14~16 场只有 2 份) ——
  一个随机过程, 量一个样本就判绿 = 碰运气。现在排法按构造保证(垫底号, 见 bot_schedule.py 头注), 门禁按真实种子扫。
分母: 份表数 == WEEKS × 3、每份号数 == N、上线次数 > 0。
"""
import datetime as dt
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, 'server', 'referee', 'bot_schedule.py')
spec = importlib.util.spec_from_file_location('bot_schedule', SCRIPT)
bs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bs)

MIN_COVER = 3
START = dt.datetime(2026, 10, 26, tzinfo=dt.timezone.utc)    # 陪练号上线的第一周(周一)
WEEKS = 52
TIERS = (30, 150, 300)     # 与 ① 同一组: 规模下限 / 中间 / 上限
ROUND_MIN = 8              # ⑤b 每局按几分钟打完: bot_runner.py MIN_PER_ROUND 的默认值(那是超时预算, 偏保守)
fails = []


def ok(name: str, cond: bool, detail: str = '') -> None:
    print('  [%s] %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def ranked_total(b: dict) -> int:
    return sum(s['rounds'] for s in b['sessions'] if s['mode'] == 'ranked')


def coverage(plan: dict, monday: dt.datetime, finish: bool) -> list:
    """周二 20:00 时, 第 k 场(下标 k-1)已有多少个陪练号打完 —— 一个号打完第 k 场才有那一份同场次快照。"""
    at = monday + dt.timedelta(days=1, hours=20)
    cnt = [0] * bs.QUOTA
    for b in plan['plan']:
        n = 0
        for s in b['sessions']:
            if s['mode'] != 'ranked':
                continue
            t = dt.datetime.fromisoformat(s['at'])
            for j in range(s['rounds']):
                done = t + dt.timedelta(minutes=ROUND_MIN * (j + 1)) if finish else t
                if done <= at and n < bs.QUOTA:
                    cnt[n] += 1
                n += 1
    return cnt


ok('① 规模公式 0/50/280 ⇒ 300/250/30', [bs.bot_count(0), bs.bot_count(50), bs.bot_count(280)] == [300, 250, 30],
   str([bs.bot_count(0), bs.bot_count(50), bs.bot_count(280)]))

plans = {}
for wk in range(WEEKS):
    monday = START + dt.timedelta(weeks=wk)
    for n in TIERS:
        plans[(wk, n)] = (monday, bs.build(monday, n, monday.toordinal()))
n_bots = sum(len(p['plan']) for _m, p in plans.values())
n_sess = sum(len(b['sessions']) for _m, p in plans.values() for b in p['plan'])
bad_size = [(m.date().isoformat(), n) for (wk, n), (m, p) in plans.items()
            if len(p['plan']) != n or not any(b['sessions'] for b in p['plan'])]
ok('分母: %d 周 × N=%s = %d 份表, 每份号数 == N、有上线' % (WEEKS, '/'.join(map(str, TIERS)), WEEKS * len(TIERS)),
   len(plans) == WEEKS * len(TIERS) and not bad_size and n_sess > 0,
   '%d 份 / %d 号 / %d 次上线 %s' % (len(plans), n_bots, n_sess, bad_size[:3]))

over, full, bad_r, bad_g, bad_fast, no_fast = [], [], [], [], [], []
for (wk, n), (monday, plan) in plans.items():
    tag = '%s N=%d' % (monday.date().isoformat(), n)
    r_lo = monday + dt.timedelta(days=1)
    r_hi = monday + dt.timedelta(days=4, hours=22, minutes=30)
    g_lo = monday + dt.timedelta(days=5)
    g_hi = monday + dt.timedelta(days=6, hours=17, minutes=30)
    if not any(b['kind'] == 'fast' for b in plan['plan']):
        no_fast.append(tag)
    for b in plan['plan']:
        if ranked_total(b) > bs.QUOTA:
            over.append((tag, b['slot']))
        if b['kind'] in ('hardcore', 'fast') and ranked_total(b) != bs.QUOTA:
            full.append((tag, b['slot']))
        for s in b['sessions']:
            t = dt.datetime.fromisoformat(s['at'])
            if s['mode'] == 'ranked' and not (r_lo <= t < r_hi):
                bad_r.append((tag, b['slot'], s['at']))
            if s['mode'] == 'gauntlet' and not (g_lo <= t < g_hi):
                bad_g.append((tag, b['slot'], s['at']))
            if b['kind'] == 'fast' and s['mode'] == 'ranked' and (t - monday).days != 1:
                bad_fast.append((tag, b['slot'], s['at']))
ok('② 每号积分赛 ≤ %d 场' % bs.QUOTA, not over, str(over[:5]))
ok('② 认真 / 冲得快的恰好 %d 场' % bs.QUOTA, not full, str(full[:5]))
ok('③ 积分赛上线都在周二 00:00 ~ 周五 22:30', not bad_r, str(bad_r[:3]))
ok('③ 闯关赛上线都在周六 00:00 ~ 周日 17:30', not bad_g, str(bad_g[:3]))
ok('④ 冲得快的积分赛全在周二(且每份表都有冲得快的)', not bad_fast and not no_fast, str((bad_fast[:3], no_fast[:3])))

for label, finish in (('⑤a', False), ('⑤b', True)):
    bad = []
    worst = {n: bs.QUOTA * 999 for n in TIERS}
    for (wk, n), (monday, plan) in plans.items():
        cnt = coverage(plan, monday, finish)
        worst[n] = min(worst[n], min(cnt))
        lows = ['第%d场=%d' % (k + 1, c) for k, c in enumerate(cnt) if c < MIN_COVER]
        if lows:
            bad.append('%s N=%d: %s' % (monday.date().isoformat(), n, ' '.join(lows)))
    how = '按开打时刻' if not finish else '按打完时刻·每局 %d 分钟' % ROUND_MIN
    per_n = ' · '.join('N=%d 不达标 %d/%d 周·最差一档 %d 份' % (
        n, sum(1 for x in bad if (' N=%d:' % n) in x), WEEKS, worst[n]) for n in TIERS)
    ok('%s 周二 20:00 第 1~%d 场每档 ≥ %d 份陪练快照(%s, 真实种子 %d 周 × 3 档)' % (
        label, bs.QUOTA, MIN_COVER, how, WEEKS), not bad, '| ' + per_n)
    for x in bad[:12]:
        print('        不达标 %s' % x)
    if len(bad) > 12:
        print('        …… 另有 %d 份表不达标' % (len(bad) - 12))

monday0, plan0 = plans[(0, bs.MAX_BOTS)]
ok('⑥ 同一种子两次生成逐字相同', bs.build(monday0, bs.MAX_BOTS, monday0.toordinal()) == plan0)

entry_bad = []
with tempfile.TemporaryDirectory() as td:
    for wk in (0, 1):
        monday, want = plans[(wk, bs.MAX_BOTS)]
        for day in (monday, monday + dt.timedelta(days=1)):
            out = os.path.join(td, 'sched_%s.json' % day.date().isoformat())
            r = subprocess.run([sys.executable, SCRIPT, '--week', day.date().isoformat(), '--bots', str(bs.MAX_BOTS), '--out', out],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            got = None
            if r.returncode == 0 and os.path.exists(out):
                with open(out, encoding='utf-8') as f:
                    got = json.load(f)
            if got != want:
                entry_bad.append('--week %s rc=%d' % (day.date().isoformat(), r.returncode))
ok('⑦ 真入口(命令行 --week 周一 / 周二补跑)出的表 == build(周一, N, 周一.toordinal())', not entry_bad, str(entry_bad))

print('ALL OK — 陪练号排班表硬约束' if not fails else 'FAILED: %d 条' % len(fails))
sys.exit(1 if fails else 0)
