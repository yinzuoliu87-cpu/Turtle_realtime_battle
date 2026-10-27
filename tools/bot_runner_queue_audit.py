# -*- coding: utf-8 -*-
"""bot_runner_queue_audit.py — 陪练号「轮流打到底」(bot_runner.py BOT_MODE=queue)按赛程的硬约束。

用户 2026-10-27:「你为啥要排班呢？…凌晨可以打，每个小时都可以打呀，就打到底就好了呀，所有的命都打完了。」
「只有在周五晋级的这个机器人号，你周六才可以去使用…每个小时你看多少个号去打，你得安排好呀。」
量的是 bot_runner.queue_tick 本身(真函数; 起进程 / 查进程活没活 / 读存档换成假的): 假时钟从周一 00:00 起每 5 分钟一拍推一整周。
假客户端: 积分赛 45 分钟、打完按 55% 胜率写本周胜场(实测 10-27 正式服陪练号 40 胜 32 负); 闯关赛 6 分钟一场、55% 胜、写回闯关胜负。
赛程(phase2_config): 积分赛周二 ~ 周五 23:00, 11 胜晋级; 闯关赛周六 00:00 ~ 周日 17:30, 4 胜晋级 / 3 负出局 / 最多 6 场。
  ① 积分赛: 每个号恰好上线 1 次、SIM_ROUNDS=16; 每个钟点新开 ≤ PER_HOUR; 全部在周五 22:30 前轮到(30/150/300 三档 + 周二 15:00 才开始)
  ② 闯关赛只起晋级(本周 ≥11 胜)的号; 没晋级的一次都不起
  ③ 每个晋级号打到 4 胜 / 3 负 / 6 场就不再起; 收盘(周日 17:20)前全部打完
  ④ 每次闯关上线 SIM_ROUNDS=1; 同一个号两次上线间隔 ≥ GAUNTLET_GAP_H
  ⑤ 周六 00:00 ~ 周日 17:00 每个钟点都有号在打(真人闯关时有 30 分钟内刚打过的同战绩真号可配)
  ⑥ 同时在跑 ≤ 上限(平日 MAX_PAR / 周末 MAX_PAR_WEEKEND); 周一 / 周五 22:30 后 / 周日 17:20 后不起号
  ⑦ 尺子自检: ⑤ 的量法在「只有 1 个晋级号」时量得出空档; ② 的量法在「全员都当晋级」时量得出没晋级的也起了
分母: 每档号数、晋级号数、积分赛 / 闯关赛上线次数、推演拍数。
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
P_WIN = 0.55
fails = []


def ok(name, cond, detail=''):
    print('  [%s] %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def simulate(n_bots, start, promote_all=False, promote_only=None):
    rng = random.Random(n_bots * 7 + (1 if promote_all else 0))
    anchor = int(MON.timestamp())
    saves = {s: {'week_anchor_ts': anchor, 'season_wins': 0, 'gauntlet_wins': 0, 'gauntlet_losses': 0} for s in range(1, n_bots + 1)}
    procs = {}                       # pid -> (结束时刻, 号, 阶段)
    applied = set()
    launches = []                    # (时刻, 阶段, 号, 局数)
    max_run = {'weekday': 0, 'weekend': 0}
    state = {}
    seq = [0]
    now = start
    ticks = 0

    def alive(pid):
        return procs[pid][0] > now if pid in procs else False

    while now < MON + dt.timedelta(days=7):
        ## 打完的进程把结果写回存档(真客户端结算时写)
        for pid, (end, slot, phase) in procs.items():
            if end <= now and pid not in applied:
                applied.add(pid)
                sv = saves[slot]
                if phase == 'ranked':
                    w = 11 if promote_all else sum(1 for _ in range(16) if rng.random() < P_WIN)
                    sv['season_wins'] = w if w >= 11 or promote_all else min(w, 10)
                    if promote_only is not None:
                        sv['season_wins'] = 11 if slot in promote_only else 5
                else:
                    if rng.random() < P_WIN:
                        sv['gauntlet_wins'] += 1
                    else:
                        sv['gauntlet_losses'] += 1
        par = PAR_WEEKEND if now.weekday() >= 5 else PAR
        phase = br.queue_phase(now)

        def launch(slot, rounds):
            seq[0] += 1
            dur = dt.timedelta(minutes=45) if phase == 'ranked' else dt.timedelta(minutes=6)
            procs[seq[0]] = (now + dur, slot, phase)
            launches.append((now, phase, slot, rounds))
            return seq[0]
        br.queue_tick(state, now, n_bots, par, br.per_hour_limit(n_bots), launch, alive, lambda s: saves[s])
        run = sum(1 for e, *_ in procs.values() if e > now)
        k = 'weekend' if now.weekday() >= 5 else 'weekday'
        max_run[k] = max(max_run[k], run)
        now += TICK
        ticks += 1
    return launches, max_run, ticks, saves


def hour_counts(launches, phase):
    per = {}
    for t, p, *_ in launches:
        if p == phase:
            per[t.replace(minute=0)] = per.get(t.replace(minute=0), 0) + 1
    return per


for n in (30, 150, 300):
    launches, max_run, ticks, saves = simulate(n, MON)
    ranked = [x for x in launches if x[1] == 'ranked']
    gaunt = [x for x in launches if x[1] == 'gauntlet']
    promoted = {s for s, sv in saves.items() if sv['season_wins'] >= 11}
    ok('分母 N=%d: 推演 %d 拍 · 晋级 %d 个号 · 积分赛 %d 次 / 闯关赛 %d 次上线' % (n, ticks, len(promoted), len(ranked), len(gaunt)),
       ticks > 2000 and len(ranked) == n and len(promoted) > 0 and len(gaunt) > 0)
    ok('① N=%d 积分赛每号恰好 1 次、16 局' % n, sorted(x[2] for x in ranked) == list(range(1, n + 1)) and all(x[3] == 16 for x in ranked))
    pr = hour_counts(launches, 'ranked')
    ok('① N=%d 积分赛每个钟点新开 ≤ %d' % (n, br.per_hour_limit(n)), max(pr.values()) <= br.per_hour_limit(n), 'max=%d' % max(pr.values()))
    ok('① N=%d 积分赛全部在周五 22:30 前轮到' % n, max(t for t, *_ in ranked) < MON + dt.timedelta(days=4, hours=22, minutes=30))
    ok('② N=%d 闯关赛只起晋级的号' % n, {x[2] for x in gaunt} <= promoted, '起了没晋级的 %s' % sorted({x[2] for x in gaunt} - promoted)[:5])
    unfinished = [s for s in promoted if br.gauntlet_left(saves[s], int(MON.timestamp())) > 0]
    over = [s for s in promoted if saves[s]['gauntlet_wins'] > 4 or saves[s]['gauntlet_losses'] > 3
            or saves[s]['gauntlet_wins'] + saves[s]['gauntlet_losses'] > 6]
    ok('③ N=%d 晋级号全部在收盘前打完(4 胜 / 3 负 / 6 场), 没有多打' % n, not unfinished and not over,
       '没打完 %d · 多打 %d' % (len(unfinished), len(over)))
    gap_bad = []
    last = {}
    for t, p, s, r in sorted(gaunt):
        if s in last and t - last[s] < dt.timedelta(hours=br.GAUNTLET_GAP_H):
            gap_bad.append((s, t.isoformat()))
        last[s] = t
    ok('④ N=%d 闯关每次 1 局、同一号两次上线隔 ≥ %g 小时' % (n, br.GAUNTLET_GAP_H), all(x[3] == 1 for x in gaunt) and not gap_bad, str(gap_bad[:3]))
    pg = hour_counts(launches, 'gauntlet')
    hours = [MON + dt.timedelta(days=5, hours=h) for h in range(41)]       # 周六 00:00 ~ 周日 16:00 起头的每个钟点
    empty = [h.strftime('%a %H:00') for h in hours if pg.get(h, 0) == 0]
    if len(promoted) >= 10:
        ok('⑤ N=%d 周六 00:00 ~ 周日 17:00 每个钟点都有号在打(晋级 %d 个)' % (n, len(promoted)), not empty, '空档 %s' % empty[:6])
    ok('⑥ N=%d 同时在跑 ≤ 上限(平日 %d / 周末 %d)' % (n, PAR, PAR_WEEKEND), max_run['weekday'] <= PAR and max_run['weekend'] <= PAR_WEEKEND, str(max_run))
    bad = [t for t, *_ in launches if t.weekday() == 0 or (t.weekday() == 4 and t.hour * 60 + t.minute >= 22 * 60 + 30)
           or (t.weekday() == 6 and t.hour * 60 + t.minute >= 17 * 60 + 20)]
    ok('⑥ N=%d 周一 / 周五 22:30 后 / 周日 17:20 后不起号' % n, not bad, str(bad[:3]))

## ① 补跑: 周二 15:00 才开始(本周 10-27 就是这样)
launches, _m, _t, _s = simulate(300, MON + dt.timedelta(days=1, hours=15))
ranked = [x for x in launches if x[1] == 'ranked']
ok('① N=300 周二 15:00 才开始也在周五 22:30 前全部轮到', len(ranked) == 300 and max(t for t, *_ in ranked) < MON + dt.timedelta(days=4, hours=22, minutes=30),
   'n=%d last=%s' % (len(ranked), max(t for t, *_ in ranked).isoformat() if ranked else '-'))

## ④ 间隔真起作用的场景: 只有 4 个号晋级、运维把每小时闯关场数调到 20 —— 没有间隔这条, 同一个号会一场接一场连着打
os.environ['PER_HOUR_GAUNTLET'] = '20'
launches, _m, _t, saves = simulate(300, MON, promote_only={11, 22, 33, 44})
os.environ.pop('PER_HOUR_GAUNTLET')
gaunt = sorted(x for x in launches if x[1] == 'gauntlet')
gap_bad, last = [], {}
for t, p, s, r in gaunt:
    if s in last and t - last[s] < dt.timedelta(hours=br.GAUNTLET_GAP_H):
        gap_bad.append((s, t.isoformat()))
    last[s] = t
left4 = [s for s in (11, 22, 33, 44) if br.gauntlet_left(saves[s], int(MON.timestamp())) > 0]
ok('④ 只有 4 个晋级号、每小时 20 场: 同一号两次上线仍隔 ≥ %g 小时, 且都打完' % br.GAUNTLET_GAP_H,
   len(gaunt) > 0 and not gap_bad and not left4 and {x[2] for x in gaunt} <= {11, 22, 33, 44},
   '上线 %d 次 · 间隔不足 %s · 没打完 %s' % (len(gaunt), gap_bad[:3], left4))

## ⑦ 尺子自检
pg = {}
for t, p, *_ in [x for x in [(MON + dt.timedelta(days=5, hours=2), 'gauntlet', 1, 1)]]:
    pg[t.replace(minute=0)] = 1
hours = [MON + dt.timedelta(days=5, hours=h) for h in range(41)]
ok('⑦ 尺子自检: 只有 1 场闯关时 ⑤ 的量法量得出空档', sum(1 for h in hours if pg.get(h, 0) == 0) == 40)
launches, _m, _t, saves = simulate(30, MON, promote_all=True)
fake_promoted = {s for s in saves if s % 2 == 0}
gaunt_slots = {x[2] for x in launches if x[1] == 'gauntlet'}
ok('⑦ 尺子自检: 全员都当晋级时 ② 的量法量得出「起了没晋级的」', bool(gaunt_slots - fake_promoted), '多出 %d 个' % len(gaunt_slots - fake_promoted))

if fails:
    print('FAILED: %d 条' % len(fails))
    sys.exit(1)
print('ALL OK — 陪练号轮流打到底(按赛程)')
