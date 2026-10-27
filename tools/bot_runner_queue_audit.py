# -*- coding: utf-8 -*-
"""bot_runner_queue_audit.py — 陪练号「轮流打到底」(bot_runner.py BOT_MODE=queue)按赛程的硬约束。

用户 2026-10-27:「你为啥要排班呢？…凌晨可以打，每个小时都可以打呀，就打到底就好了呀，所有的命都打完了。」
「周六周日我们讲究是在线啊」(闯关赛改在线瑞士轮, 方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md):
  周末的陪练号由常驻的 server/referee/gauntlet_bot_planner.py 按 12 个战绩格子拉上线(推演门禁 tools/gauntlet_planner_audit.py),
  本文件 queue 模式周六 / 周日一个号都不起。
量的是 bot_runner.queue_tick 本身(真函数; 起进程 / 查进程活没活 / 读存档换成假的): 假时钟从周一 00:00 起每 5 分钟一拍推一整周。
假客户端: 积分赛 45 分钟、打完按 55% 胜率写本周胜场(实测 10-27 正式服陪练号 40 胜 32 负)。
赛程(phase2_config): 积分赛周二 ~ 周五 23:00, 11 胜晋级; 闯关赛周六 00:00 ~ 周日 17:30(在线瑞士轮, 不归本文件)。
  ① 积分赛: 每个号恰好上线 1 次、SIM_ROUNDS=16; 每个钟点新开 ≤ PER_HOUR; 全部在周五 22:30 前轮到(30/150/300 三档 + 周二 15:00 才开始)
  ② 周六 / 周日一个号都不起(包括本周晋级的号; 在线闯关由 gauntlet_bot_planner.py 拉号)
  ⑥ 同时在跑 ≤ 上限(平日 MAX_PAR); 周一 / 周五 22:30 后 / 周六 / 周日不起号
  ⑦ 尺子自检: ② 的量法在「造一条周六的上线」时量得出来
  ⑧ launch: BOT_JEMALLOC 没开 ⇒ 客户端环境里没有 LD_PRELOAD / MALLOC_CONF(积分赛照旧); 开了 ⇒ 两个都设(库不在就不设);
     extra_env 原样传给客户端; SUPABASE_SERVICE_KEY 不传给客户端
  ⑨ reap_overdue / kill_tree 杀得干净整棵进程树(包装脚本里的 timeout 另开进程组), 包装脚本照常记 sessions.log(Linux 上真起进程量)
分母: 每档号数、晋级号数、积分赛上线次数、推演拍数。
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
    weekend = [x for x in launches if x[0].weekday() >= 5]
    promoted = {s for s, sv in saves.items() if sv['season_wins'] >= 11}
    ok('分母 N=%d: 推演 %d 拍 · 晋级 %d 个号 · 积分赛 %d 次上线' % (n, ticks, len(promoted), len(ranked)),
       ticks > 2000 and len(ranked) == n and len(promoted) > 0)
    ok('① N=%d 积分赛每号恰好 1 次、16 局' % n, sorted(x[2] for x in ranked) == list(range(1, n + 1)) and all(x[3] == 16 for x in ranked))
    pr = hour_counts(launches, 'ranked')
    ok('① N=%d 积分赛每个钟点新开 ≤ %d' % (n, br.per_hour_limit(n)), max(pr.values()) <= br.per_hour_limit(n), 'max=%d' % max(pr.values()))
    ok('① N=%d 积分赛全部在周五 22:30 前轮到' % n, max(t for t, *_ in ranked) < MON + dt.timedelta(days=4, hours=22, minutes=30))
    ok('② N=%d 周六 / 周日一个号都不起(晋级 %d 个号也不起)' % (n, len(promoted)), not weekend, str([(t.isoformat(), s) for t, _p, s, _r in weekend[:3]]))
    ok('⑥ N=%d 同时在跑 ≤ 上限(平日 %d; 周末没有本文件的号)' % (n, PAR), max_run['weekday'] <= PAR and max_run['weekend'] == 0, str(max_run))
    bad = [t for t, *_ in launches if t.weekday() == 0 or (t.weekday() == 4 and t.hour * 60 + t.minute >= 22 * 60 + 30)
           or t.weekday() >= 5]
    ok('⑥ N=%d 周一 / 周五 22:30 后 / 周六 / 周日不起号' % n, not bad, str(bad[:3]))

## ① 补跑: 周二 15:00 才开始(本周 10-27 就是这样)
launches, _m, _t, _s = simulate(300, MON + dt.timedelta(days=1, hours=15))
ranked = [x for x in launches if x[1] == 'ranked']
ok('① N=300 周二 15:00 才开始也在周五 22:30 前全部轮到', len(ranked) == 300 and max(t for t, *_ in ranked) < MON + dt.timedelta(days=4, hours=22, minutes=30),
   'n=%d last=%s' % (len(ranked), max(t for t, *_ in ranked).isoformat() if ranked else '-'))

## ⑦ 尺子自检: ② 的量法在「造一条周六的上线」时量得出来
fake = [(MON + dt.timedelta(days=5, hours=2), 'ranked', 7, 16)]
ok('⑦ 尺子自检: 造一条周六的上线, ② 的量法量得出 1 条', len([x for x in fake if x[0].weekday() >= 5]) == 1)

## ⑧ launch 给客户端的环境(假 Popen 截下来; 不起真进程)
import tempfile
captured = []


class FakePopen:
    def __init__(self, cmd, env=None, **_kw):
        captured.append(dict(env or {}))
        self.pid = 4242


root_saved, popen_saved = br.ROOT, br.subprocess.Popen
tmp = tempfile.mkdtemp(prefix='botrun_audit_')
lib = os.path.join(tmp, 'libjemalloc.so.2')
open(lib, 'w').close()
saved_env = {k: os.environ.get(k) for k in ('BOT_JEMALLOC', 'BOT_JEMALLOC_LIB', 'BOT_MALLOC_CONF', 'SUPABASE_SERVICE_KEY')}
try:
    br.ROOT = tmp
    br.subprocess.Popen = FakePopen
    os.environ['SUPABASE_SERVICE_KEY'] = 'secret-for-audit'
    for k in ('BOT_JEMALLOC', 'BOT_JEMALLOC_LIB', 'BOT_MALLOC_CONF'):
        os.environ.pop(k, None)
    br.launch(1, 16)
    os.environ.update({'BOT_JEMALLOC': '1', 'BOT_JEMALLOC_LIB': lib})
    br.launch(2, 1, extra_env={'SIM_GAUNTLET_ONLINE': '1', 'SIM_ROUNDS': '3'})
    os.environ['BOT_JEMALLOC_LIB'] = os.path.join(tmp, 'missing.so')
    br.launch(3, 1)
finally:
    br.ROOT, br.subprocess.Popen = root_saved, popen_saved
    for k, v in saved_env.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
e0, e1, e2 = captured
ok('⑧ 分母: 截到 3 次拉号的环境', len(captured) == 3)
ok('⑧ BOT_JEMALLOC 没开: 没有 LD_PRELOAD / MALLOC_CONF(积分赛照旧), SIM_ROUNDS=16', 'LD_PRELOAD' not in e0 and 'MALLOC_CONF' not in e0 and e0.get('SIM_ROUNDS') == '16')
ok('⑧ BOT_JEMALLOC=1: LD_PRELOAD = 库路径、MALLOC_CONF = 内存调查那组参数', e1.get('LD_PRELOAD') == lib and e1.get('MALLOC_CONF') == br.MALLOC_CONF_DEFAULT,
   '%s / %s' % (e1.get('LD_PRELOAD'), e1.get('MALLOC_CONF')))
ok('⑧ extra_env 原样传给客户端(周末调度器的 SIM_GAUNTLET_ONLINE / SIM_ROUNDS 盖过默认)', e1.get('SIM_GAUNTLET_ONLINE') == '1' and e1.get('SIM_ROUNDS') == '3')
ok('⑧ 库不在: 不设 LD_PRELOAD(照旧 glibc, 不让客户端起不来)', 'LD_PRELOAD' not in e2)
ok('⑧ SUPABASE_SERVICE_KEY 一次都没传给客户端', all('SUPABASE_SERVICE_KEY' not in e for e in captured))

## ⑨ 超时杀(reap_overdue)/ kill_tree 杀得干净整棵进程树, 且包装脚本照常记 sessions.log
##   2026-10-27 内测服彩排实测: 原来 os.killpg(包装脚本 pid) —— 包装脚本(godot-bot.sh)里的 GNU timeout 另开进程组,
##   godot 在那一组里 ⇒ 杀完 10 秒后 timeout / godot 都还在, sessions.log 也没记这一次。
##   纯函数部分各平台都量; 活体部分要 Linux(/proc + setsid + GNU timeout = CI / 裁判机), 包装脚本与机器上的
##   godot-bot.sh 同结构(bash → timeout → 子进程; 子进程退了再记一行), 子进程用 sleep 代替 godot。
ok('⑨ parse_stat: 普通一行 ⇒ (状态, 父, 进程组, 会话)', br.parse_stat('4321 (godot) S 4300 4310 4300 0 -1') == ('S', 4300, 4310, 4300))
ok('⑨ parse_stat: 进程名带空格 / 括号也切得对', br.parse_stat('77 (a (b) c) R 5 6 7 0 0') == ('R', 5, 6, 7))
ok('⑨ parse_stat: 认不出 ⇒ None', br.parse_stat('garbage') is None and br.parse_stat('1 (x) S 2') is None)

import shutil
import subprocess
import time as _time


def _ps_session(sid):
    """独立的尺子(不用被测的 session_procs): ps 列出会话 sid 里没死的进程名。"""
    out = subprocess.run(['ps', '-o', 'pid=,stat=,comm=', '--sid', str(sid)], capture_output=True, text=True).stdout
    return [ln.split()[2] for ln in out.splitlines() if len(ln.split()) >= 3 and not ln.split()[1].startswith('Z')]


LIVE = os.name == 'posix' and os.path.isdir('/proc') and shutil.which('timeout') and shutil.which('ps') and shutil.which('bash')
if not LIVE:
    print('  [SKIP] ⑨ 活体杀进程: 这台机器没有 /proc / setsid / GNU timeout(Windows 开发机), 只在 Linux(CI / 裁判机)上量')
else:
    tmp9 = tempfile.mkdtemp(prefix='botrun_kill_')
    wrap = os.path.join(tmp9, 'godot-bot.sh')
    with open(wrap, 'w') as f:
        f.write('#!/bin/bash\nt0=$(date +%s)\ntimeout --kill-after=60 "${BOT_SESSION_CAP_SEC:-3600}" sleep 300\nrc=$?\n'
                'echo "$(date -u +%FT%TZ) rc=$rc wall=$(( $(date +%s) - t0 ))s" >> "${XDG_DATA_HOME:-/tmp}/sessions.log"\nexit $rc\n')
    os.chmod(wrap, 0o755)
    saved9 = (br.ROOT, br.GODOT, br.GAME)
    br.ROOT, br.GODOT, br.GAME = os.path.join(tmp9, 'root'), wrap, tmp9
    pids9 = []

    def _up(slot):
        pid = br.launch(slot, 1)
        pids9.append(pid)
        for _ in range(50):
            if 'sleep' in _ps_session(pid):
                break
            _time.sleep(0.1)
        return pid

    def _gone_within(pid, sec=10.0):
        t0 = _time.time()
        while _time.time() - t0 < sec:
            br._reap(pid)
            if not _ps_session(pid):
                return _time.time() - t0
            _time.sleep(0.1)
        return None

    def _log(slot):
        p = os.path.join(br.ROOT, 'p%02d' % slot, 'sessions.log')
        return open(p).read().splitlines() if os.path.exists(p) else []
    try:
        ## 尺子自检: 旧写法 killpg(包装脚本 pid) ⇒ 量得出 sleep(= godot)还活着、sessions.log 没记
        pid = _up(7)
        before = _ps_session(pid)
        os.killpg(pid, 9)
        _time.sleep(1.5)
        br._reap(pid)
        left = _ps_session(pid)
        ok('⑨ 尺子自检: 包装脚本 → timeout(另开进程组)→ 子进程 三层都在(%s); 旧写法 killpg 之后量得出子进程还活着(%s)、没记 sessions.log' % (
            before, left), len(before) == 3 and 'timeout' in before and 'sleep' in before and 'sleep' in left and not _log(7))
        for p in br.session_procs(pid):
            br._sigkill(p)
        ## reap_overdue: 超时那一条 ⇒ 10 秒内整棵树没了, 包装脚本记了 rc=137
        pid = _up(8)
        st9 = {'k': {'pid': pid, 'at': (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=5)).isoformat(), 'rounds': 1}}
        nk = br.reap_overdue(st9, dt.datetime.now(dt.timezone.utc))
        g = _gone_within(pid)
        lg = _log(8)
        ok('⑨ reap_overdue 超时杀: 10 秒内整棵树没了(%s 秒)、sessions.log 记了这一次(%s)、标 killed' % (
            '%.1f' % g if g is not None else '超时', lg[-1:] or '无'),
            nk == 1 and g is not None and len(lg) == 1 and 'rc=137' in lg[0] and bool(st9['k'].get('killed')))
        ## kill_tree 直接调(调度器「停」走的就是它)
        pid = _up(9)
        nk = br.kill_tree(pid)
        g = _gone_within(pid)
        lg = _log(9)
        ok('⑨ kill_tree: 杀了 %d 个进程(timeout + 子进程)、10 秒内整棵树没了(%s 秒)、sessions.log 记了 rc=137' % (
            nk, '%.1f' % g if g is not None else '超时'), nk == 2 and g is not None and len(lg) == 1 and 'rc=137' in lg[0], str(lg))
    finally:
        for p0 in pids9:                      # 断言红了也别在机器上留 sleep / timeout
            for p in br.session_procs(p0):
                br._sigkill(p)
        br.ROOT, br.GODOT, br.GAME = saved9

if fails:
    print('FAILED: %d 条' % len(fails))
    sys.exit(1)
print('ALL OK — 陪练号轮流打到底(积分赛按赛程; 周末不起号, 由在线闯关调度器拉)')
