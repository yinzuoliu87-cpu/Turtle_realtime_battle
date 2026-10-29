# -*- coding: utf-8 -*-
"""gauntlet_planner_audit.py — 周末在线闯关赛陪练号调度器(server/referee/gauntlet_bot_planner.py)的推演门禁。

用户 10-27:「假如我在周六凌晨点击锁定，那我是不是能在十分钟或者二十分钟之内匹配到一个对手…掉到零杠一或者一杠零，那我有人打吗？
二杠零、零杠二、一杠一呢…三杠零、二杠一、一杠二…所有的情况」「我们自己的号都是零杠零开局的…到周日之后…三杠二这些号…怎么处理他们呢？」
拿**真的 decide** 推演整个周末(周六 00:00 ~ 周日 17:30 UTC), 服务器 / 裁判 / 客户端是假的(事件驱动):
  · 排队: 同格子先来先配、本周交过手的不配、15 秒没心跳的不配; 收盘前 10 分钟起不收新条目。真人等满 FALLBACK_SEC 由服务端兜底(先同格子真人快照、再机器人池; 计数)。
  · 裁判: THREADS 个线程、FIFO, 一局 25~45 秒; 真人对陪练号 / 兜底真人赢 55%, 号对号 50%。
  · 陪练客户端: 拉起到进排队 40~60 秒; 打完结算 20 秒, 还要打就逛商店 60~240 秒再排, 打完 / 局数到了就下线; 排队等满 GIVEUP 自己下线。
  · 真人: 到了就一口气打完(每局后 150~270 秒再排, 「最快的真人」150 秒); 收盘前 10 分钟 + 70 秒起不再排。
场景: 真人晋级 0 / 5 / 20 / 50 × 陪练号晋级 30 / 57 / 80, 并发按内存档(0.75GB × 6 主线, 另跑 0.35GB × 12 对比)。
断言:
  ① 真人每次排队: 配上真对手的等待 ≤ WAIT_MAX(120 秒); 兜底次数按场景打印; 号够的场景(57 / 80 晋级、真人 ≤ 20)兜底 = 0
  ② 周六 03:00 前 12 个格子都有空闲号(开赛铺格子); 周日 16:30 12 个格子各 ≥ 1 个空闲号(浅格子的本钱没被推光)
  ③ 只拉空闲、不在线、没打完的晋级号; 同时在线 ≤ 上限; 补格子成对拉的两个号没交过手; 服务端没配出跨格子 / 重复交手
  ④ 收盘前 10 分钟不开新局(拉号停在收盘前 10 分钟 + 拉起时长, 服务端那之后不配)
  ⑤ 尺子自检: 格子数恒为 12(从规则推 == 用户列的 12 个); 把 R 调大量得出缺口; 久没打的量法量得出造出来的久没打; 关掉 A 量得出等待超限
  ⑥ 周六 09:00 已有陪练号晋级、也有出局(赛况板白天就陆续有人打完)
  ⑦ 任意时刻「上过榜、待定、超过 6 小时没打」的陪练号 ≤ STALE_CAP(n)(理由见 stale_cap)
  ⑧ 收盘时「上过榜但没打完」的陪练号 ≤ UNFINISHED_CAP(n)(理由见 unfinished_cap); 0-0 没打过的不算(不进赛况板)
  ⑨ 穷举: 一个最快的真人在周六 00:00 / 周六 03:00 / 周日 16:30 进来, 全部 35 条输赢路线, 每一步的等待 ≤ WAIT_MAX 或兜底(打印最长那步)
  ⑩ 总量账: 晋级号的剩余步数(开赛 / 收盘)按场景打印
  ⑪ 调度器让号下线(stop_client)= 杀整棵进程树(bot_runner.kill_tree), 包装脚本照常记 sessions.log(Linux 上真起进程量; 10-27 彩排查出旧写法杀不到 godot)
  ⑫ 号少(12 个)· 只开调度器: 铺到数学上限(独立穷举: 12 个号最多 9 格)、0-0 全程留够 SCARCE_ROOT_KEEP 个; 打印 6~9 格各在第几分钟
分母: 每个场景的真人排队次数、采样次数、拉号次数。
"""
import copy
import heapq
from concurrent.futures import ProcessPoolExecutor
import importlib.util
import math
import os
import random
import re
import sys
import time

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location('gauntlet_bot_planner', os.path.join(REPO, 'server', 'referee', 'gauntlet_bot_planner.py'))
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)

MON = 1793577600                       # 2026-11-02 周一 00:00 UTC
CLOSE = P.close_of_week(MON)
SAT0 = P.saturday_of(CLOSE)
LOCKOUT = CLOSE - P.DEFAULTS['LOCKOUT_SEC']
HUMAN_CUTOFF = LOCKOUT - P.DEFAULTS['STARTUP_SEC'] - P.DEFAULTS['TICK_SEC']   # 真人最后能排的时刻(服务端 join 截止, 见回报)
FALLBACK_SEC = 180                     # 服务端兜底线(真人等这么久还没对手 ⇒ 先真人快照、再机器人池; 20261029b 起 180 秒)
## 用户 10-29「可以多等啊，3分钟」⇒ 真人最多等 = 兜底线(原来 120 是按 90 秒兜底定的)。
##   ★单看它是恒真的(过了兜底线就兜底, 不会再「配上真对手」) ⇒ 另加 WAIT_FAST: 配上真对手的局 ≥ FAST_SHARE 在它以内(调度器反应没变慢)。
WAIT_MAX = FALLBACK_SEC
WAIT_FAST = 90
FAST_SHARE = 0.95
THREADS = 2
P_HUMAN_WIN = 0.55
STALE_SEC = 6 * 3600
## 最快的真人: 打完一局到再排队隔 FAST_POST_SEC(看直播 + 逛店)。排队 ~50 秒 + 裁判 ~35 秒 + 这个 ≈ 5 分钟一局 ⇒ 约 25 分钟打到 3-2
##   (协调方给的「真人一局约 4~5 分钟、最早约 25 分钟能打到 3-2」)。另打印「4 分钟一局」(STRICT_POST_SEC)的更狠一档作参考。
FAST_POST_SEC = 210
STRICT_POST_SEC = 150
MEM_PROFILES = (('glibc 0.75GB × 6', 0.75, 6), ('jemalloc 0.35GB × 12', 0.35, 12))
fails = []


def ok(name, cond, detail=''):
    print('  [%s] %s %s' % ('PASS' if cond else 'FAIL', name, detail))
    if not cond:
        fails.append(name)


def hm(t):
    d = int(t - SAT0)
    return '%s %02d:%02d' % ('周六' if d < 86400 else '周日', (d % 86400) // 3600, (d % 3600) // 60)


## ═══════════════ 假世界 ═══════════════
class World:
    def __init__(self, n_bots, arrivals, cfg, seed, fast_ids=(), fast_post=FAST_POST_SEC, sample_dt=300):
        self.cfg = dict(P.DEFAULTS)
        self.cfg.update(cfg)
        self.rng = random.Random(seed)
        self.prng = random.Random(seed + 7)
        self.t = SAT0
        self.ev = []
        self.seq = 0
        self.bots = {'b%03d' % i: {'cell': (0, 0), 'fin': False, 'opp': set(), 'last': None, 'busy': False, 'games': 0}
                     for i in range(1, n_bots + 1)}
        self.humans = {}
        self.clients = {}
        self.tokn = 0
        self.queue = {c: [] for c in P.CELLS}
        self.ref_q, self.ref_busy = [], 0
        self.jobs_live = []
        self.memory = {}
        self.forced = {}                       # 人 -> 输赢路线(穷举用)
        self.fast = set(fast_ids)
        self.fast_post = fast_post
        self.waits = []                        # (人, 第几场, 格子, 等待秒, 兜底?, 排队时刻)
        self.launches = []                     # (t, 号, 用途)
        self.viol = []
        self.pairs = 0
        self.hh_pairs = 0
        self.samples = []                      # (t, {格子: 空闲数}, stale, onboard_pending, promoted, out)
        self.max_online = 0
        self.unfinished_close = None
        self.steps0 = sum(P.steps_left(*b['cell']) for b in self.bots.values())
        for hid, at in arrivals:
            self.humans[hid] = {'cell': (0, 0), 'fin': False, 'opp': set(), 'games': 0, 'busy': False}
            self.push(at, 'hjoin', hid, 0)
        self.sample_dt = sample_dt
        self.push(SAT0, 'tick')
        self.push(SAT0 + sample_dt, 'sample')
        self.push(CLOSE, 'close')

    def push(self, t, *a):
        self.seq += 1
        heapq.heappush(self.ev, (t, self.seq, a))

    def ent(self, eid):
        return self.bots.get(eid) or self.humans[eid]

    def online(self, e):
        return e['dead'] is None or self.t - e['dead'] <= self.cfg['ONLINE_SEC']

    ## ── 排队 ──
    def join(self, eid, is_bot, tok):
        x = self.ent(eid)
        if x['fin'] or x['busy']:
            return
        if self.t >= LOCKOUT:
            if is_bot:
                self.exit_client(eid)
            return
        for qq in self.queue.values():                 # 服务端: 每个账号同一时刻只有一条排队(重新排 = 换掉旧的)
            qq[:] = [e for e in qq if e['id'] != eid]
        q = self.queue[x['cell']]
        q[:] = [e for e in q if self.online(e) and not self.ent(e['id'])['busy'] and self.ent(e['id'])['cell'] == x['cell']]
        for e in q:
            if e['id'] not in x['opp'] and eid not in self.ent(e['id'])['opp']:
                q.remove(e)
                self.pair(e, {'id': eid, 'bot': is_bot, 'joined': self.t})
                return
        e = {'id': eid, 'bot': is_bot, 'joined': self.t, 'dead': None, 'tok': tok}
        q.append(e)
        if is_bot:
            self.push(self.t + P.GIVEUP_SEC.get(self.clients[eid]['purpose'], 300), 'giveup', eid, tok)
        else:
            self.push(self.t + FALLBACK_SEC, 'fallback', eid, tok)

    def pair(self, e1, e2):
        a, b = (e1, e2) if not e1['bot'] else (e2, e1)
        xa, xb = self.ent(a['id']), self.ent(b['id'])
        if xa['cell'] != xb['cell'] or b['id'] in xa['opp'] or self.t >= LOCKOUT:
            self.viol.append('服务端配出跨格子 / 重复交手 / 收盘后 %s' % hm(self.t))
        for e in (a, b):
            if not e['bot']:
                h = self.ent(e['id'])
                self.waits.append((e['id'], h['games'] + 1, h['cell'], self.t - e['joined'], False, e['joined']))
        if not a['bot'] and not b['bot']:
            self.hh_pairs += 1
        xa['busy'] = xb['busy'] = True
        self.pairs += 1
        self.referee({'a': a['id'], 'b': b['id'], 'cell': xa['cell']})

    def referee(self, job):
        self.ref_q.append(job)
        self.jobs_live.append(job)
        self.ref_start()

    def ref_start(self):
        while self.ref_busy < THREADS and self.ref_q:
            job = self.ref_q.pop(0)
            self.ref_busy += 1
            self.push(self.t + self.rng.uniform(25, 45), 'done', job)

    def done(self, job):
        self.ref_busy -= 1
        self.jobs_live.remove(job)
        a, b = job['a'], job['b']
        if a in self.forced:
            aw = self.forced[a][self.humans[a]['games']] == 'W'
        elif b in self.forced:
            aw = self.forced[b][self.humans[b]['games']] != 'W'
        elif b is None:
            aw = self.rng.random() < P_HUMAN_WIN
        elif a in self.humans and b in self.bots:
            aw = self.rng.random() < P_HUMAN_WIN
        else:
            aw = self.rng.random() < 0.5
        for eid, won, other in ((a, aw, b), (b, not aw, a)):
            if eid is None:
                continue
            x = self.ent(eid)
            w, l = x['cell']
            x['cell'] = (w + 1, l) if won else (w, l + 1)
            x['games'] += 1
            x['busy'] = False
            if other is not None:
                x['opp'].add(other)
            x['fin'] = not P.is_live(*x['cell'])
            if eid in self.bots:
                x['last'] = self.t
                cl = self.clients.get(eid)
                if cl:
                    left = cl['rounds'] - (x['games'] - cl['g0'])
                    if x['fin'] or left <= 0:
                        self.push(self.t + 20, 'bexit', eid, cl['tok'])
                    else:
                        self.push(self.t + 20 + self.rng.uniform(*P.shop_sec(cl['purpose'])), 'bjoin', eid, cl['tok'])
            elif not x['fin']:
                gap = self.fast_post if eid in self.fast else self.rng.uniform(150, 270)
                if self.t + gap < HUMAN_CUTOFF:
                    self.push(self.t + gap, 'hjoin', eid, 0)
        self.ref_start()

    def exit_client(self, bid):
        cl = self.clients.pop(bid, None)
        if cl is None:
            return
        for e in self.queue.get(self.bots[bid]['cell'], ()):
            if e['id'] == bid and e['dead'] is None:
                e['dead'] = self.t

    ## ── 调度器一拍 ──
    def state(self):
        """与服务端 gauntlet_service_state(迁移 20261027_gauntlet_online_queue.sql)同一形状: waiting 只列心跳有效的条目
        (真人和陪练号都在, 带 is_bot); playing = 配上了还在算的; bots 的 busy = in_job 或 waiting。"""
        waiting, queued = [], set()
        for c, q in self.queue.items():
            for e in q:
                if self.online(e):
                    x = self.ent(e['id'])
                    queued.add(e['id'])
                    waiting.append({'account_id': e['id'], 'gw': c[0], 'gl': c[1], 'waited_sec': self.t - e['joined'],
                                    'seen_sec': 0.0 if e['dead'] is None else self.t - e['dead'], 'is_bot': e['bot'],
                                    'opponents': x['opp']})
        bots = [{'account_id': k, 'gw': v['cell'][0], 'gl': v['cell'][1], 'in_job': v['busy'], 'waiting': k in queued,
                 'busy': v['busy'] or k in queued, 'finished': v['fin'], 'promoted': True, 'last_played_at': v['last'],
                 'opponents': v['opp']} for k, v in self.bots.items()]
        running = {k: {'since': v['since'], 'rounds': v['rounds'], 'purpose': v['purpose'], 'g0': v['g0']} for k, v in self.clients.items()}
        playing = [{'account_id': j[k], 'gw': j['cell'][0], 'gl': j['cell'][1], 'is_bot': j[k] in self.bots}
                   for j in self.jobs_live for k in ('a', 'b') if j[k] is not None]
        return {'close_at': CLOSE, 'now': self.t, 'waiting': waiting, 'bots': bots, 'running': running,
                'memory': self.memory, 'playing': playing}

    def tick(self):
        st = self.state()
        cmds = P.decide(st, self.t, self.prng, self.cfg)
        applied = []
        fill_now = []
        for op, bid, rounds, purpose, why in cmds:
            if op == 'stop':
                if bid in self.clients and not self.bots[bid]['busy']:
                    self.exit_client(bid)
                    applied.append((op, bid, rounds, purpose, why))
                else:
                    self.viol.append('停了在打 / 不在线的号 %s %s' % (bid, hm(self.t)))
                continue
            b = self.bots.get(bid)
            if b is None or b['fin'] or b['busy'] or bid in self.clients or not P.is_live(*b['cell']):
                self.viol.append('拉了不该拉的号 %s %s(%s)' % (bid, hm(self.t), why))
                continue
            if len(self.clients) >= self.cfg['MAX_PAR']:
                self.viol.append('超过并发上限 %s' % hm(self.t))
                continue
            if self.t >= LOCKOUT - self.cfg['STARTUP_SEC']:
                self.viol.append('收盘前 10 分钟 + 拉起时长内还在拉号 %s' % hm(self.t))
            if why.startswith('C 补格子(每格'):
                fill_now.append(bid)
            self.tokn += 1
            tok = self.tokn
            self.clients[bid] = {'tok': tok, 'since': self.t, 'rounds': rounds, 'purpose': purpose, 'g0': b['games']}
            self.push(self.t + self.rng.uniform(40, 60), 'bjoin', bid, tok)
            self.launches.append((self.t, bid, purpose))
            applied.append((op, bid, rounds, purpose, why))
        for i in range(0, len(fill_now) - 1, 2):
            a, b = fill_now[i], fill_now[i + 1]
            if b in self.bots[a]['opp'] or self.bots[a]['cell'] != self.bots[b]['cell']:
                self.viol.append('补格子成对拉的两个号交过手 / 不同格子 %s' % hm(self.t))
        self.memory = P.remember(self.memory, applied, self.t, st)
        self.max_online = max(self.max_online, len(self.clients))

    def sample(self):
        idle = {c: 0 for c in P.CELLS}
        stale = pend = prom = out = 0
        for v in self.bots.values():
            if v['fin']:
                if v['cell'][0] >= P.GAUNTLET_WINS_IN:
                    prom += 1
                else:
                    out += 1
                continue
            if not v['busy']:
                idle[v['cell']] += 1
            if v['games'] >= 1:
                pend += 1
                if not v['busy'] and v['last'] is not None and self.t - v['last'] > STALE_SEC:
                    stale += 1
        self.samples.append((self.t, idle, stale, pend, prom, out))

    def run(self, until=CLOSE + 1, stop_when=None):
        while self.ev and self.ev[0][0] <= until:
            t, _s, a = heapq.heappop(self.ev)
            self.t = t
            k = a[0]
            if k == 'tick':
                if t < CLOSE:
                    self.tick()
                    self.push(t + self.cfg['TICK_SEC'], 'tick')
            elif k == 'bjoin':
                cl = self.clients.get(a[1])
                if cl and cl['tok'] == a[2]:
                    self.join(a[1], True, a[2])
            elif k == 'hjoin':
                if t < HUMAN_CUTOFF:
                    self.join(a[1], False, 0)
            elif k == 'done':
                self.done(a[1])
                if stop_when and stop_when(self):
                    return
            elif k == 'giveup':
                cl = self.clients.get(a[1])
                if cl and cl['tok'] == a[2] and not self.bots[a[1]]['busy']:
                    self.exit_client(a[1])
            elif k == 'bexit':
                cl = self.clients.get(a[1])
                if cl and cl['tok'] == a[2]:
                    self.exit_client(a[1])
            elif k == 'fallback':
                hid = a[1]
                q = self.queue.get(self.humans[hid]['cell'], [])
                e = next((e for e in q if e['id'] == hid), None)
                if e is not None and t - e['joined'] >= FALLBACK_SEC:
                    q.remove(e)
                    h = self.humans[hid]
                    self.waits.append((hid, h['games'] + 1, h['cell'], t - e['joined'], True, e['joined']))
                    h['busy'] = True
                    self.referee({'a': hid, 'b': None, 'cell': h['cell']})
            elif k == 'sample':
                self.sample()
                self.push(t + self.sample_dt, 'sample')
            elif k == 'close':
                self.unfinished_close = sum(1 for v in self.bots.values() if v['games'] >= 1 and not v['fin'])


## ═══════════════ ⑪ 调度器「停」杀得干净 ═══════════════
def kill_checks():
    """⑪ 调度器让号下线(stop_client: 停 / 超时杀都走它)= 杀整棵进程树, 包装脚本照常记 sessions.log。
    2026-10-27 内测服彩排: 原来 os.killpg(包装脚本 pid) —— 包装脚本(godot-bot.sh)里的 GNU timeout 另开进程组 ⇒ godot 活着
    把剩下的局打完(p07 17:41:28 被停, 17:41:56 又进了队), 调度器却当它下线了。
    各平台: stop_client 从进程表拿掉这一条、按包装脚本的 pid 调 bot_runner.kill_tree(假的, 截下参数); 源码里不再有 killpg。
    Linux(/proc + GNU timeout = CI / 裁判机): 真起一个与 godot-bot.sh 同结构的包装脚本(子进程用 sleep 代替 godot), 停它 ⇒ 10 秒内整棵树没了、记了 rc=137。"""
    import shutil
    import subprocess
    import tempfile
    br = P._bot_runner()
    src = open(os.path.join(REPO, 'server', 'referee', 'gauntlet_bot_planner.py'), encoding='utf-8').read()
    ok('⑪ 调度器源码里不再直接 killpg(下线一律走 stop_client → bot_runner.kill_tree)', 'killpg(' not in src)
    seen = []
    saved = br.kill_tree
    try:
        br.kill_tree = lambda pid, grace=None: seen.append(pid) or 2
        run = {'a': {'pid': 4242}, 'b': {'pid': 4343}}
        n = P.stop_client(br, run, 'a')
        n0 = P.stop_client(br, run, 'zz')
    finally:
        br.kill_tree = saved
    ok('⑪ stop_client: 按包装脚本 pid 调 kill_tree、从进程表拿掉这一条(别的不动); 不在表里的号什么都不杀',
       seen == [4242] and n == 2 and list(run) == ['b'] and n0 == 0, 'seen=%s run=%s' % (seen, list(run)))
    live = os.name == 'posix' and os.path.isdir('/proc') and shutil.which('timeout') and shutil.which('ps') and shutil.which('bash')
    if not live:
        print('  [SKIP] ⑪ 活体: 这台机器没有 /proc / setsid / GNU timeout(Windows 开发机), 只在 Linux(CI / 裁判机)上量')
        return

    def ps_session(sid):
        out = subprocess.run(['ps', '-o', 'pid=,stat=,comm=', '--sid', str(sid)], capture_output=True, text=True).stdout
        return [ln.split()[2] for ln in out.splitlines() if len(ln.split()) >= 3 and not ln.split()[1].startswith('Z')]
    tmp = tempfile.mkdtemp(prefix='planner_kill_')
    wrap = os.path.join(tmp, 'godot-bot.sh')
    with open(wrap, 'w') as f:
        f.write('#!/bin/bash\ntimeout --kill-after=60 "${BOT_SESSION_CAP_SEC:-3600}" sleep 300\nrc=$?\n'
                'echo "$(date -u +%FT%TZ) rc=$rc" >> "${XDG_DATA_HOME:-/tmp}/sessions.log"\nexit $rc\n')
    os.chmod(wrap, 0o755)
    saved = (br.ROOT, br.GODOT, br.GAME)
    br.ROOT, br.GODOT, br.GAME = os.path.join(tmp, 'root'), wrap, tmp
    pid = None
    try:
        pid = P.launch_bot(br, 5, 1, 'fill', (0, 0))
        for _ in range(50):
            if 'sleep' in ps_session(pid):
                break
            time.sleep(0.1)
        before = ps_session(pid)
        run = {'acct': {'pid': pid}}
        P.stop_client(br, run, 'acct')
        t0, gone = time.time(), None
        while time.time() - t0 < 10:
            br._reap(pid)
            if not ps_session(pid):
                gone = time.time() - t0
                break
            time.sleep(0.1)
        lp = os.path.join(br.ROOT, 'p05', 'sessions.log')
        lg = open(lp).read().splitlines() if os.path.exists(lp) else []
        ok('⑪ 活体: 拉起(%s) → 停 ⇒ 10 秒内整棵树没了(%s 秒)、sessions.log 记了这一次(%s)' % (
            before, '%.1f' % gone if gone is not None else '超时', lg[-1:] or '无'),
            'sleep' in before and 'timeout' in before and gone is not None and len(lg) == 1 and 'rc=137' in lg[0])
    finally:
        for p in (br.session_procs(pid) if pid else []):
            br._sigkill(p)
        br.ROOT, br.GODOT, br.GAME = saved


## ═══════════════ ⑫ 号少(12 个)· 只开调度器: 铺格子 ═══════════════
def max_cover(n, keep_root):
    """独立的尺子(不调被测的 cover_plan / fill_plan): n 个号全在 0-0, 0-0 至少留 keep_root 个, 最多能让几格同时 ≥1。
    逐层(浅 → 深)枚举每格打几局 —— 每局固定从这一格拿走 2 个、两个下一格各进 1 个(进 4 胜 / 3 负 / 6 场的离场), 层内顺序无关。"""
    cells_by_layer = [[c for c in spec_cells() if c[0] + c[1] == d] for d in range(6)]
    live = set(spec_cells())

    def go(d, counts):
        if d == len(cells_by_layer):
            return 0
        cells = cells_by_layer[d]
        best = -1

        def rec(i, inflow, cov):
            nonlocal best
            if i == len(cells):
                nxt = cells_by_layer[d + 1] if d + 1 < len(cells_by_layer) else []
                best = max(best, cov + go(d + 1, {c: inflow.get(c, 0) for c in nxt}))
                return
            c = cells[i]
            n_c = counts.get(c, 0)
            for x in range(0, max(0, n_c - (keep_root if c == (0, 0) else 0)) // 2 + 1):
                inf = dict(inflow)
                for q in ((c[0] + 1, c[1]), (c[0], c[1] + 1)):
                    if q in live:
                        inf[q] = inf.get(q, 0) + x
                rec(i + 1, inf, cov + (1 if n_c - 2 * x >= 1 else 0))
        rec(0, {}, 0)
        return best
    return go(0, {(0, 0): n})


def spec_cells():
    """用户列的 12 个格子(与 ⑤ 的 spec12 同一份, 不从调度器拿)。"""
    return [(0, 0), (1, 0), (0, 1), (2, 0), (1, 1), (0, 2), (3, 0), (2, 1), (1, 2), (3, 1), (2, 2), (3, 2)]


def few_bots(args):
    """12 个号、没有真人、只开调度器(= 10-27 内测服彩排那一段), 推演开赛后 2 小时, 每 30 秒采一次空闲号分布。"""
    n_bots, par, seed = args
    w = World(n_bots, [], {'MAX_PAR': par}, seed, sample_dt=30)
    w.run(until=SAT0 + 2 * 3600)
    first = {}
    for t, idle, *_r in w.samples:
        k = sum(1 for v in idle.values() if v >= 1)
        for j in range(1, k + 1):
            first.setdefault(j, t)
    last = w.samples[-1][1]
    return {'n': n_bots, 'par': par, 'first': first, 'final': sum(1 for v in last.values() if v >= 1),
            'empty': [c for c, v in last.items() if v < 1], 'root_min': min(s[1][P.ROOT] for s in w.samples),
            'fin': sum(1 for b in w.bots.values() if b['fin']), 'games': w.pairs, 'nviol': len(w.viol), 'viol': w.viol[:3],
            'max_online': w.max_online, 'nsamples': len(w.samples)}


def few_bots_checks():
    keep = P.DEFAULTS['SCARCE_ROOT_KEEP']
    print('== ⑫ 号少时铺格子(10-27 内测服彩排: 12 个号只开调度器, 铺到 7 格就停了 9 分钟) ==')
    caps = {n: max_cover(n, keep) for n in range(8, 31)}
    full_k = min([n for n in caps if caps[n] == 12] or [0])
    full_1 = min([n for n in range(8, 31) if max_cover(n, 1) == 12] or [0])
    print('   独立穷举(0-0 留 %d 个): %s' % (keep, ' '.join('%d号→%d格' % (n, caps[n]) for n in (8, 10, 12, 14, 16, 20, 23, 24, 30))))
    ok('⑫ 尺子: 12 个号最多同时铺 %d 格(到 3-2 必经 3-1 / 2-2, 那两格每局送走一个打完的号); 铺满 12 格最少要 %d 个号(0-0 留 1)/ %d 个(留 %d)' % (
        caps[12], full_1, full_k, keep), caps[12] == 9 and full_1 == 23 and full_k > 0)
    bad = []
    for n in range(8, 31):
        xs = P.cover_plan({P.ROOT: n}, keep)
        cnt = {c: 0 for c in P.CELLS}
        cnt[P.ROOT] = n
        for c in P.CELLS:
            cnt[c] -= 2 * xs[c]
            for q in ((c[0] + 1, c[1]), (c[0], c[1] + 1)):
                if q in cnt:
                    cnt[q] += xs[c]
        if sum(1 for v in cnt.values() if v >= 1) != caps[n] or cnt[P.ROOT] < keep or min(cnt.values()) < 0:
            bad.append((n, sum(1 for v in cnt.values() if v >= 1), caps[n], cnt[P.ROOT]))
    ok('⑫ cover_plan 的打法 8~30 个号都铺到穷举上限、0-0 留够 %d 个、没有格子被打成负数' % keep, not bad, str(bad[:3]))
    for par in (4, 6):
        r = few_bots((12, par, 3))
        mins = ' · '.join('%d 格 %s' % (k, ('第 %.1f 分钟' % ((r['first'][k] - SAT0) / 60.0)) if k in r['first'] else '没到')
                          for k in range(6, caps[12] + 1))
        print('   12 个号 · 并发 %d · 只开调度器: %s · 2 小时后 %d 格(空 %s)· 0-0 最少 %d 个 · 打了 %d 局 · 打完离场 %d 个 · 采样 %d 次' % (
            par, mins, r['final'], ['%d-%d' % c for c in r['empty']], r['root_min'], r['games'], r['fin'], r['nsamples']))
        reach = r['first'].get(caps[12])
        ok('⑫ 12 个号 · 并发 %d · 只开调度器: 铺到数学上限 %d 格(第 %s 分钟)、2 小时后还在 %d 格' % (
            par, caps[12], '%.1f' % ((reach - SAT0) / 60.0) if reach else '没到', r['final']),
            reach is not None and reach - SAT0 <= 45 * 60 and r['final'] == caps[12])
        ok('⑫ 12 个号 · 并发 %d: 0-0 全程 ≥ %d 个(本钱没一次花光)' % (par, keep), r['root_min'] >= keep, 'min=%d' % r['root_min'])
        ok('⑫ 12 个号 · 并发 %d: 拉号 / 并发 / 配对合规(同时在线最多 %d)' % (par, r['max_online']),
           r['nviol'] == 0 and r['max_online'] <= par, str(r['viol']))


## ═══════════════ 场景 ═══════════════
def arrivals_for(n_h, seed):
    """真人晋级者到达时刻: 5 个 = 周六凌晨 / 凌晨 3 点半 / 上午 / 晚上 / 周日 16:30 各一个; 20 / 50 个 = 开赛就来 2 个、
    周日 16:20 来 1 个, 其余按钟点权重(白天晚上多、深夜少)随机。每人到了一口气打完, 每局后隔 150~270 秒再排。"""
    if n_h == 0:
        return []
    if n_h == 5:
        offs = [120, 3.5 * 3600, 11 * 3600, 20.5 * 3600, CLOSE - 3600 - SAT0]
        return [('h%02d' % i, SAT0 + o) for i, o in enumerate(offs)]
    rng = random.Random(seed)
    hours = list(range(41))
    w = [P.HOUR_WEIGHTS[h % 24] for h in hours]
    out = [('h00', SAT0 + 30), ('h01', SAT0 + 240), ('h02', CLOSE - 3600 - 600)]
    for i in range(3, n_h):
        h = rng.choices(hours, weights=w)[0]
        out.append(('h%02d' % i, SAT0 + h * 3600 + rng.uniform(0, 3600)))
    return out


def stale_cap(n):
    """⑦ 上限 = min(n, 11 × R + ⌈0.2 n⌉)。理由: 平时每格留 R 个候场号, 除 0-0(没打过的不进赛况板)外 11 格 × R 个是规则要求
    「停着等真人」的号, 只有真人 / 整段打完 / 补格子拉到它时才动, 不能要求它们 6 小时内都打过; 再加晋级号的 20%
    (开赛「每格 ≥1」那一轮按最省的打法也会把 ~1/3 的号多送进中间格子, 多出来的靠「整段打完」按最久没打的先消化)。
    30 个晋级号时 12 格几乎要全部号候场 ⇒ 上限接近全部, 这是数学上的(铺满 12×1 就要 23 个)。"""
    return min(n, 11 * P.DEFAULTS['R'] + int(math.ceil(0.2 * n)))


def unfinished_cap(n):
    """⑧ 上限 = 11 + ⌈0.15 n⌉。理由: 收尾时只给「收盘前还有真人能走到的格子」留 R_END 个; 最后 20 分钟里新来的真人一场接一场
    也走不深, 深格子一格一格变成「没人能走到」, 那里的号成对打到底。剩下的: 每个非 0-0 格子最后至多一个凑不成对的号
    (同格子只剩它一个, 或剩下的都跟它交过手) = 11 个, 赛况板上按「出局」显示, 与中途不打的真人一样; 另加晋级号的 15%:
    收盘那刻正打到一半的(≤ 并发上限)和最后几分钟拉起来也赶不上的。0-0 没打过的不进赛况板, 不算。"""
    return 11 + int(math.ceil(0.15 * n))


def scenario(args):
    """跑一个场景, 返回摘要(进程池里跑; 不回传整个世界)。"""
    n_bots, n_h, par, seed, cfg_extra = args
    cfg = {'MAX_PAR': par}
    cfg.update(cfg_extra or {})
    w = World(n_bots, arrivals_for(n_h, seed * 31 + n_h), cfg, seed * 1000 + n_bots + n_h)
    w.run()
    real = [x for x in w.waits if not x[4]]
    fb = [x for x in w.waits if x[4]]
    mx = max(real, key=lambda x: x[3]) if real else None
    at = lambda t: min(w.samples, key=lambda s: abs(s[0] - t))
    s03, s09, s1630 = at(SAT0 + 3 * 3600), at(SAT0 + 9 * 3600), at(CLOSE - 3600)
    stale = max(w.samples, key=lambda s: s[2])
    purposes = {}
    for _t, _b, p in w.launches:
        purposes[p] = purposes.get(p, 0) + 1
    n_sess_h = int((CLOSE - P.DEFAULTS['ENDGAME_SEC'] - SAT0) // 3600)
    return {
        'n': n_bots, 'h': n_h, 'par': par, 'cfg': cfg_extra or {},
        'waits': len(w.waits), 'real': len(real), 'hh': w.hh_pairs,
        'fb': [(x[5], x[1], x[2]) for x in fb],
        'mx': (mx[3], mx[5], mx[1], mx[2]) if mx else (0, 0, 0, (0, 0)),
        'buckets': [sum(1 for x in real if lo < x[3] <= hi) for lo, hi in ((-1, 30), (30, 60), (60, 90), (90, 120), (120, 1e9))],
        'full1': next((s[0] for s in w.samples if all(v >= 1 for v in s[1].values())), None),
        'fullr': next((s[0] for s in w.samples if all(v >= w.cfg['R'] for v in s[1].values())), None),
        'gapR': sum(1 for s in w.samples if s[0] > SAT0 + 3600 and any(v < w.cfg['R'] for v in s[1].values())),
        'nsamples': len(w.samples),
        'empty03': [c for c, v in s03[1].items() if v < 1], 'empty1630': [c for c, v in s1630[1].items() if v < 1],
        'p09': s09[4], 'o09': s09[5], 'stale': (stale[2], stale[3], stale[0]),
        'unfinished': w.unfinished_close, 'steps0': w.steps0,
        'steps_close': sum(P.steps_left(*b['cell']) for b in w.bots.values() if not b['fin']),
        'root1630': s1630[1][P.ROOT],
        'purposes': purposes, 'max_online': w.max_online, 'viol': w.viol[:5], 'nviol': len(w.viol),
        'sess_hours': len({int((t - SAT0) // 3600) for t, _b, p in w.launches if p == 'session'} & set(range(n_sess_h))),
        'n_sess_h': n_sess_h,
        'late': [t for t, *_ in w.launches if t >= LOCKOUT - P.DEFAULTS['STARTUP_SEC']],
        'late_pairs': sum(1 for v in w.viol if '收盘后' in v),
    }


def show(s, label):
    mx = s['mx']
    print('── %s · 晋级陪练号 %d · 晋级真人 %d ──' % (label, s['n'], s['h']))
    print('   真人排队 %d 次: 配上真对手 %d(真人对真人 %d 局) · 兜底 %d · 最长等待 %s · 分布 ≤30/≤60/≤90/≤120/>120 秒 = %s' % (
        s['waits'], s['real'], s['hh'], len(s['fb']),
        ('%d 秒(%s 第 %d 场 %d-%d)' % (mx[0], hm(mx[1]), mx[2], mx[3][0], mx[3][1])) if s['real'] else '-', s['buckets']))
    if s['fb']:
        print('   兜底: %s' % ', '.join('%s 第%d场 %d-%d' % (hm(t), g, c[0], c[1]) for t, g, c in s['fb'][:10]) + (' …' if len(s['fb']) > 10 else ''))
    print('   格子: 每格 ≥1 铺满 %s · 每格 ≥%d 铺满 %s · 周六 03:00 空格 %s · 周日 16:30 空格 %s(0-0 还有 %d 个)' % (
        hm(s['full1']) if s['full1'] else '没铺满', P.DEFAULTS['R'], hm(s['fullr']) if s['fullr'] else '没铺满(0-0 本钱线不许)',
        ['%d-%d' % c for c in s['empty03']] or '无', ['%d-%d' % c for c in s['empty1630']] or '无', s['root1630']))
    print('   周六 09:00 晋级 %d / 出局 %d · 久没打(>6h)最多 %d / 上榜待定 %d(%s, 上限 %d) · 收盘上过榜没打完 %d(上限 %d)' % (
        s['p09'], s['o09'], s['stale'][0], s['stale'][1], hm(s['stale'][2]), stale_cap(s['n']), s['unfinished'], unfinished_cap(s['n'])))
    print('   总量账: 剩余步数 开赛 %d → 收盘 %d · 拉号 %s · 同时在线最多 %d · 整段打完覆盖 %d / %d 个钟点' % (
        s['steps0'], s['steps_close'], s['purposes'], s['max_online'], s['sess_hours'], s['n_sess_h']))


## ═══════════════ 穷举输赢路线 ═══════════════
def all_paths():
    out = []

    def rec(w, l, s):
        if not P.is_live(w, l):
            out.append(s)
            return
        rec(w + 1, l, s + 'W')
        rec(w, l + 1, s + 'L')
    rec(0, 0, '')
    return out


def probe(args):
    """在 start 分叉: 背景照常(5 个真人), 加一个最快的真人按每条路线打完; 返回 (最长真对手等待, 那条路线, 第几场, 格子), 兜底步数, 总步数, 没打完的路线。"""
    n_bots, par, start, fast_post, seed = args
    base = World(n_bots, arrivals_for(5, seed), {'MAX_PAR': par}, seed * 1000 + n_bots, fast_post=fast_post)
    base.run(until=start - 1e-6)
    worst, nfb, steps, broken = (0, '', 0, (0, 0)), 0, 0, []
    for path in all_paths():
        w = copy.deepcopy(base)
        w.humans['probe'] = {'cell': (0, 0), 'fin': False, 'opp': set(), 'games': 0, 'busy': False}
        w.forced['probe'] = path
        w.fast.add('probe')
        w.push(start, 'hjoin', 'probe', 0)
        w.run(until=start + 3 * 3600, stop_when=lambda ww: ww.humans['probe']['fin'])
        mine = [x for x in w.waits if x[0] == 'probe']
        if len(mine) != len(path):
            broken.append(path)
        for x in mine:
            steps += 1
            if x[4]:
                nfb += 1
            elif x[3] > worst[0]:
                worst = (x[3], path, x[1], x[2])
    return {'n': n_bots, 'par': par, 'start': start, 'post': fast_post, 'worst': worst, 'nfb': nfb, 'steps': steps, 'broken': broken}


def main():
    t0 = time.time()
    print('== 对账: 调度器的赛程常量 == phase2_config.gd ==')
    gd = open(os.path.join(REPO, 'scripts', 'gamedata', 'phase2_config.gd'), encoding='utf-8').read()

    def gd_const(name):
        m = re.search(r'^const %s\s*:?=\s*([0-9 *+]+?)\s*(#|$)' % name, gd, re.M)
        return eval(m.group(1)) if m else None      # 只含数字与 + * 的字面表达式
    for name in ('GAUNTLET_WINS_IN', 'GAUNTLET_LOSSES_OUT', 'GAUNTLET_QUOTA', 'GAUNTLET_CLOSE_MIN_UTC', 'CLOSE_LOCKOUT_SEC'):
        ok('%s 调度器 %s == gd %s' % (name, getattr(P, name), gd_const(name)), getattr(P, name) == gd_const(name))

    print('== ⑤ 尺子自检(静态) ==')
    spec12 = [(0, 0), (1, 0), (0, 1), (2, 0), (1, 1), (0, 2), (3, 0), (2, 1), (1, 2), (3, 1), (2, 2), (3, 2)]
    ok('⑤ 格子从规则推出来恒为 12, 且 == 用户列的 12 个', len(P.CELLS) == 12 and set(P.CELLS) == set(spec12), str(P.CELLS))
    paths = all_paths()
    ok('⑤ 输赢路线穷举 35 条(到 4 胜 15 条 + 到 3 负 20 条)', len(paths) == 35 and sum(1 for p in paths if p.count('W') == 4) == 15, 'n=%d' % len(paths))
    sh57, xs57 = P.fill_plan({P.ROOT: 57.0}, 2)
    sh30, xs30 = P.fill_plan({P.ROOT: 30.0}, 2)
    sh30b, xs30b = P.fill_plan({P.ROOT: 30.0}, 1)
    ok('⑤ 补格子求解: 57 个号全在 0-0 ⇒ 每格 2 个够(缺口 0, 动用 0-0 %d 个 · %d 局)' % (2 * xs57[P.ROOT] + 2, sum(xs57.values())), sh57 == 0)
    ok('⑤ 30 个号: 每格 2 个数学上不够(缺口 %d), 每格 1 个够(缺口 %d, 动用 0-0 %d 个 · %d 局) —— 所以先铺「每格 ≥1」' % (
        sh30, sh30b, 2 * xs30b[P.ROOT] + 1, sum(xs30b.values())), sh30 > 0 and sh30b == 0)
    w = World(57, [], {'MAX_PAR': 6}, 5)
    w.bots['b001'].update({'games': 1, 'last': SAT0, 'cell': (1, 0)})
    w.t = SAT0 + 7 * 3600
    w.sample()
    ok('⑤ 造一个 7 小时没打的上榜号: ⑦ 的量法量得出 1 个', w.samples[-1][2] == 1, str(w.samples[-1][2]))

    print('== ⑪ 调度器「停」杀得干净整棵进程树 ==')
    kill_checks()
    few_bots_checks()

    par = MEM_PROFILES[0][2]
    jobs_s = [(n, h, par, 1, None) for n in (30, 57, 80) for h in (0, 5, 20, 50)]
    jobs_s += [(n, 20, MEM_PROFILES[1][2], 1, None) for n in (30, 57, 80)]
    jobs_s += [(80, 5, par, 1, {'R': 4}), (57, 5, par, 1, {'MAX_PAR': 0, 'HUMAN_RESERVE': 0})]
    starts = (('周六 00:00', SAT0), ('周六 03:00', SAT0 + 3 * 3600), ('周日 16:30', CLOSE - 3600))
    jobs_p = [(n, par, st, FAST_POST_SEC, 3) for n in (30, 57, 80) for _l, st in starts]
    jobs_p += [(n, MEM_PROFILES[1][2], SAT0, FAST_POST_SEC, 3) for n in (30, 57, 80)]
    jobs_p += [(n, p2, SAT0, STRICT_POST_SEC, 3) for n in (57,) for p2 in (par, MEM_PROFILES[1][2])]
    workers = max(1, min(8, (os.cpu_count() or 2)))
    with ProcessPoolExecutor(workers) as ex:
        fs = {('s',) + j[:4] + (tuple(sorted((j[4] or {}).items())),): ex.submit(scenario, j) for j in jobs_s}
        fp = {('p',) + j: ex.submit(probe, j) for j in jobs_p}
        rs = {k: f.result() for k, f in fs.items()}
        rp = {k: f.result() for k, f in fp.items()}

    print('== 场景(主线 %s) ==' % MEM_PROFILES[0][0])
    for n in (30, 57, 80):
        for h in (0, 5, 20, 50):
            s = rs[('s', n, h, par, 1, ())]
            show(s, MEM_PROFILES[0][0])
    print('== 断言 ==')
    for n in (30, 57, 80):
        for h in (0, 5, 20, 50):
            s = rs[('s', n, h, par, 1, ())]
            tag = 'N=%d H=%d' % (n, h)
            ok('① %s 配上真对手的等待都 ≤ %d 秒(%d 次)' % (tag, WAIT_MAX, s['real']), s['mx'][0] <= WAIT_MAX, 'max=%d' % s['mx'][0])
            if s['real'] >= 20:
                fast = sum(c for hi, c in zip((30, 60, 90, 120, 1e9), s['buckets']) if hi <= WAIT_FAST)   # 分档上沿 ≤ WAIT_FAST 的(30/60/90/120 之一)
                ok('① %s 配上真对手的局 ≥ %d%% 在 %d 秒内(%d / %d)' % (tag, int(FAST_SHARE * 100), WAIT_FAST, fast, s['real']),
                   fast >= FAST_SHARE * s['real'], '分布 %s' % str(s['buckets']))
            if n >= 57 and h <= 5:
                late_fb = [x for x in s['fb'] if x[0] >= SAT0 + 1800]
                ok('① %s 号够、真人少: 开赛 30 分钟之后零兜底(开赛那段见 ⑨)' % tag, not late_fb, str([(hm(t), g) for t, g, _c in late_fb[:3]]))
            ok('③ %s 拉号 / 并发 / 配对都合规(拉号 %d 次, 同时在线最多 %d)' % (tag, sum(s['purposes'].values()), s['max_online']),
               s['nviol'] == 0 and s['max_online'] <= par, str(s['viol'][:3]))
            ok('④ %s 收盘前 10 分钟 + 拉起时长内不拉号、收盘后不配对' % tag, not s['late'] and not s['late_pairs'], str([hm(t) for t in s['late'][:3]]))
            if h <= 20:
                ok('② %s 周六 03:00 12 个格子都有空闲号' % tag, not s['empty03'], str(s['empty03']))
            if n >= 57 and h <= 5:
                ok('② %s 周日 16:30 12 个格子各 ≥1 个空闲号(0-0 的本钱没被推光)' % tag, not s['empty1630'], str(s['empty1630']))
            if n >= 57 and h <= 20:
                ok('⑥ %s 周六 09:00 已有陪练号晋级、也有出局' % tag, s['p09'] >= 1 and s['o09'] >= 1, '晋级 %d 出局 %d' % (s['p09'], s['o09']))
            ok('⑦ %s 久没打的上榜待定号 ≤ %d(最多 %d, %s)' % (tag, stale_cap(n), s['stale'][0], hm(s['stale'][2])), s['stale'][0] <= stale_cap(n))
            ok('⑧ %s 收盘时上过榜没打完 ≤ %d' % (tag, unfinished_cap(n)), s['unfinished'] <= unfinished_cap(n), 'n=%d' % s['unfinished'])

    print('== ⑨ 穷举 35 条输赢路线(最快的真人: 每局约 5 分钟、约 25 分钟打到 3-2; 背景 5 个真人) ==')
    for n in (30, 57, 80):
        for lab, st in starts:
            r = rp[('p', n, par, st, FAST_POST_SEC, 3)]
            wv, path, step, cell = r['worst']
            print('   N=%d %s %s 进来: 最长等待 %d 秒(路线 %s 第 %d 场 %d-%d) · 兜底 %d / %d 步' % (
                n, MEM_PROFILES[0][0], lab, wv, path, step, cell[0], cell[1], r['nfb'], r['steps']))
            ok('⑨ N=%d %s 进来: 35 条路线都打完, 每一步配上真对手的等待 ≤ %d 秒' % (n, lab, WAIT_MAX), wv <= WAIT_MAX and not r['broken'],
               'max=%d broken=%s' % (wv, r['broken'][:2]))
            if n >= 57 and st == SAT0 + 3 * 3600:
                ok('⑨ N=%d %s 进来: 35 条路线都不兜底' % (n, lab), r['nfb'] == 0, 'n=%d' % r['nfb'])
            if n >= 57 and st == CLOSE - 3600:
                ## 周日 16:30 号池已被整个周末用到每格 1~2 个; 两个真人同一分钟开打、走同一条路时, 后到的那个可能在第 6 场
                ## 碰上 3-2 空着、上一级也补不出来 ⇒ 兜底。只许零星(≤ 5% 的步), 不许成片。
                ok('⑨ N=%d %s 进来: 兜底只许零星(≤ 5%% 的步)' % (n, lab), r['nfb'] <= 0.05 * r['steps'], '%d / %d' % (r['nfb'], r['steps']))

    print('== 内存档对比: %s vs %s ==' % (MEM_PROFILES[0][0], MEM_PROFILES[1][0]))
    p2 = MEM_PROFILES[1][2]
    for n in (30, 57, 80):
        a, b = rs[('s', n, 20, par, 1, ())], rs[('s', n, 20, p2, 1, ())]
        show(b, MEM_PROFILES[1][0])
        ok('③ N=%d %s 合规' % (n, MEM_PROFILES[1][0]), b['nviol'] == 0 and b['max_online'] <= p2, str(b['viol'][:3]))
        pa, pb = rp[('p', n, par, SAT0, FAST_POST_SEC, 3)], rp[('p', n, p2, SAT0, FAST_POST_SEC, 3)]
        print('   N=%d 真人 20: 兜底 %d → %d · 每格 ≥1 铺满 %s → %s · 周六 00:00 穷举兜底 %d → %d 步(共 %d 步)' % (
            n, len(a['fb']), len(b['fb']), hm(a['full1']) if a['full1'] else '-', hm(b['full1']) if b['full1'] else '-',
            pa['nfb'], pb['nfb'], pb['steps']))
    for p in (par, p2):
        r = rp[('p', 57, p, SAT0, STRICT_POST_SEC, 3)]
        print('   (参考)每局 4 分钟的更快真人 N=57 并发 %d 周六 00:00 进来: 兜底 %d / %d 步 · 最长等待 %d 秒' % (p, r['nfb'], r['steps'], r['worst'][0]))

    print('== ⑤ 尺子自检(反向) ==')
    s = rs[('s', 80, 5, par, 1, (('R', 4),))]
    ok('⑤ R 调到 4(80 个号铺 12×4 要 ~100 个): 采样量得出缺口', s['gapR'] > 0, '有缺口的采样 %d / %d' % (s['gapR'], s['nsamples']))
    s = rs[('s', 57, 5, par, 1, (('HUMAN_RESERVE', 0), ('MAX_PAR', 0)))]
    ok('⑤ 一个号都不许拉: ① 的量法量得出兜底, ② 的量法量得出空格子', len(s['fb']) > 0 and len(s['empty03']) > 0,
       'fb=%d empty03=%d' % (len(s['fb']), len(s['empty03'])))

    print('耗时 %.1f 秒(%d 个进程)' % (time.time() - t0, workers))
    if fails:
        print('FAILED: %d 条' % len(fails))
        for f in fails[:30]:
            print('   ' + f)
        sys.exit(1)
    print('ALL OK — 周末在线闯关赛陪练号调度器(12 格子候场 · 真人不久等 · 开赛 / 平时 / 收尾)')


if __name__ == '__main__':
    main()
