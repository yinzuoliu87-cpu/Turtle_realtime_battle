# -*- coding: utf-8 -*-
"""bot_runner_queue_audit.py — 陪练号「轮流打到底」(bot_runner.py BOT_MODE=queue)的硬约束。

用户 2026-10-27:「你为啥要排班呢？…凌晨可以打，每个小时都可以打呀，就打到底就好了呀，所有的命都打完了。」
量的是 bot_runner.queue_tick 本身(真函数, 只把起进程 / 查进程活没活换成假的): 假时钟从周一 00:00 起每 5 分钟一拍推一整周,
假客户端积分赛打 45 分钟、闯关赛 1~20 分钟(没晋级的号进主菜单就被拦, 很快退)。
  ① 每个号本周积分赛恰好上线 1 次、闯关赛恰好 1 次; 积分赛 SIM_ROUNDS=16、闯关赛 6
  ② 同时在跑 ≤ 并发上限(平日 MAX_PAR / 周末 MAX_PAR_WEEKEND)
  ③ 每个钟点新开的号 ≤ PER_HOUR(积分赛) / PER_HOUR_GAUNTLET(闯关赛)
  ④ 周一、周五 22:30 后、周日 17:20 后一个都不起
  ⑤ 积分赛全部号在周五 22:30 前轮到(号数 30 / 150 / 300 三档; 另加「周二 15:00 才开始」的补跑一档)
  ⑥ 尺子自检: 把 PER_HOUR 放到 99 时 ③ 的量尺量得出超限(证明 ③ 不是空检查)
分母: 每档号数、积分赛 / 闯关赛上线次数、推演拍数。
"""
import datetime as dt
import importlib.util
import os
import random
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, 'server', 'referee', 'bot_runner.py')
spec = importlib.util.spec_from_file_location('bot_runner', SCRIPT)
br = importlib.util.module_from_spec(spec)
spec.loader.exec_module(br)

MON = dt.datetime(2026, 11, 2, tzinfo=dt.timezone.utc)
TICK = dt.timedelta(minutes=5)
PAR, PAR_WEEKEND = 6, 4
fails = []


def ok(name, cond, detail=''):
    print('  [%s] %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def simulate(n_bots, per_hour, start, per_hour_g=None):
    rng = random.Random(n_bots)
    procs = {}                       # pid -> 结束时刻
    launches = []                    # (时刻, 阶段, 号, 局数)
    max_run = {'weekday': 0, 'weekend': 0}
    state = {}
    seq = [0]
    now = start
    ticks = 0

    def alive(pid):
        return procs.get(pid, now) > now

    while now < MON + dt.timedelta(days=7):
        par = PAR_WEEKEND if now.weekday() >= 5 else PAR
        phase = br.queue_phase(now)

        def launch(slot, rounds):
            seq[0] += 1
            dur = dt.timedelta(minutes=45) if phase == 'ranked' else dt.timedelta(minutes=rng.randint(1, 20))
            procs[seq[0]] = now + dur
            launches.append((now, phase, slot, rounds))
            return seq[0]
        ph_now = per_hour if phase != 'gauntlet' else (per_hour_g if per_hour_g is not None else br.per_hour_limit(n_bots, 'gauntlet'))
        br.queue_tick(state, now, n_bots, par, ph_now, launch, alive)
        run = sum(1 for e in procs.values() if e > now)
        k = 'weekend' if now.weekday() >= 5 else 'weekday'
        max_run[k] = max(max_run[k], run)
        now += TICK
        ticks += 1
    return launches, max_run, ticks


for n in (30, 150, 300):
    ph = br.per_hour_limit(n, 'ranked')
    phg = br.per_hour_limit(n, 'gauntlet')
    launches, max_run, ticks = simulate(n, ph, MON)
    ranked = [x for x in launches if x[1] == 'ranked']
    gaunt = [x for x in launches if x[1] == 'gauntlet']
    ok('分母 N=%d: 推演 %d 拍, 积分赛 %d 次 / 闯关赛 %d 次上线' % (n, ticks, len(ranked), len(gaunt)), ticks > 2000 and len(ranked) > 0 and len(gaunt) > 0)
    ok('① N=%d 每号积分赛恰好 1 次、闯关赛恰好 1 次' % n,
       sorted(x[2] for x in ranked) == list(range(1, n + 1)) and sorted(x[2] for x in gaunt) == list(range(1, n + 1)))
    ok('① N=%d 积分赛 16 局 / 闯关赛 6 局' % n, all(x[3] == 16 for x in ranked) and all(x[3] == 6 for x in gaunt))
    ok('② N=%d 同时在跑 ≤ 上限(平日 %d / 周末 %d)' % (n, PAR, PAR_WEEKEND),
       max_run['weekday'] <= PAR and max_run['weekend'] <= PAR_WEEKEND, str(max_run))
    per = {}
    for t, p_, _s, _r in launches:
        h = (t.replace(minute=0), p_)
        per[h] = per.get(h, 0) + 1
    mr = max(v for (h, p_), v in per.items() if p_ == 'ranked')
    mg = max(v for (h, p_), v in per.items() if p_ == 'gauntlet')
    ok('③ N=%d 每个钟点新开 ≤ 积分赛 %d / 闯关赛 %d' % (n, ph, phg), mr <= ph and mg <= phg, 'max=%d/%d' % (mr, mg))
    bad = [t for t, *_ in launches if t.weekday() == 0 or (t.weekday() == 4 and t.hour * 60 + t.minute >= 22 * 60 + 30)
           or (t.weekday() == 6 and t.hour * 60 + t.minute >= 17 * 60 + 20)]
    ok('④ N=%d 周一 / 周五 22:30 后 / 周日 17:20 后不起号' % n, not bad, str(bad[:3]))
    last = max(t for t, *_ in ranked)
    ok('⑤ N=%d 积分赛全部在周五 22:30 前轮到' % n, last < MON + dt.timedelta(days=4, hours=22, minutes=30), last.isoformat())

## ⑤ 补跑: 周二 15:00 才开始(本周 10-27 就是这样)
n = 300
launches, _m, _t = simulate(n, br.per_hour_limit(n, 'ranked'), MON + dt.timedelta(days=1, hours=15))
ranked = [x for x in launches if x[1] == 'ranked']
ok('⑤ N=300 周二 15:00 才开始也在周五 22:30 前全部轮到', len(ranked) == n and max(t for t, *_ in ranked) < MON + dt.timedelta(days=4, hours=22, minutes=30),
   'n=%d last=%s' % (len(ranked), max(t for t, *_ in ranked).isoformat() if ranked else '-'))

## ⑥ 尺子自检: PER_HOUR 放到 99 ⇒ 每个钟点新开会超过 4(③ 的量法量得出来)
launches, _m, _t = simulate(300, 99, MON, per_hour_g=99)
per = {}
for t, *_ in launches:
    per[t.replace(minute=0)] = per.get(t.replace(minute=0), 0) + 1
ok('⑥ 尺子自检: PER_HOUR=99 时 ③ 的量法量出 > 4', max(per.values()) > 4, 'max=%d' % max(per.values()))

if fails:
    print('FAILED: %d 条' % len(fails))
    sys.exit(1)
print('ALL OK — 陪练号轮流打到底')
