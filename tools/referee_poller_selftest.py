# -*- coding: utf-8 -*-
"""referee_poller_selftest —— 裁判机轮询器「补流」任务的自证门禁(2026-10-20 · 方案书 docs/plans/20261019-服务器逐帧直播.md §5)。

不连库、不起 Godot: 把 server/referee/referee_poller.py 当模块载入, 换掉它的 `rpc`(记账 + 假回包)和
`subprocess.Popen`(假 Godot: 按命令行里的 --stream / --out 写块、end.json、结果单), 其余代码(StreamPublisher 的
边算边发布 / 撤流、run_godot、handle_restream、worker_loop 的领活顺序)全是真的。

断言:
  ① 补流成功: 对外目录有全部块 + end.json; 只调 referee_restream_done(ok); ★一次 referee_complete 都没有(不写回结果、不改账)
  ② 重算胜方与原结果不同: 对外目录被撤掉(没有 end.json); done(ok=false, permanent)
  ③ 指纹不同: 同 ②
  ④ 没设 STREAM_ROOT: 不起 Godot, done(stream_off, permanent)
  ⑤ 对外目录已有 end.json: 不起 Godot, done(ok)
  ⑥ worker_loop: 正常任务领空了才领补流; 补流任务交给 handle_restream(不走 handle)
  ⑦ referee_claim_restream 404(服务端没部署): 本进程以后不再领补流
  ⑧ 正常任务照旧: handle 调 referee_complete(补流的改动没碰它)
  ⑨ 空闲放慢: 真 worker_loop + 假时钟走满一小时, 领活次数和补流次数都降下来, 头 30 秒仍 2 秒
  ⑩ 放慢后来了任务: 6 秒内领到, 之后回到 2 秒
  ⑪ 补流有积压: 领到一份立刻接着问, 不等 60 秒
  ⑫ 补流限频窗口内来了任务: 下一次询问就领到
  ⑬ 领补流网络失败也限频: 不因为出错退回每轮都问
  ⑭~⑳ 局外经济流水重放(2026-11-06 · 方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.5 S4b):
     ⑭ 领一批(econ_replay_claim)、一个 Godot 进程(--econ-replay)算完、econ_replay_done 回写那一批;
        strict = referee_flags 的 econ_on; ★每个号的 facts 原样进输入文件(丢了 ⇒ 重放什么收入都不认)
     ⑮ ★比赛工作线程不领(开局要等重放, 排在比赛后面 ⇒ 越忙越卡)  ⑯ ★单开的线程 econ_loop 领完回写、main 真起了它
     ⑰ econ_replay_claim 404 ⇒ 本进程不再领  ⑱ 用的工程 = 最新且带 econ_replay.gd 的版本
     ⑲ 整批算不出来 ⇒ 拆开一个一个算: 算得出的回写, 算不出的不回写(不堵别人)
     ⑳ econ_loop 空闲也放慢(和 ⑨ 同一个 IdlePacer, 2026-11-08 合 main 时接上): 一小时约 610 次不是 1800 次
  ㉑~㉔ 空闲省流量第二步(#23 · 2026-11-10, 内测服实测一个轮询器空转一天约 3.4 万次):
     ㉑ econ_on 关着: econ_loop 一小时只领 12 次(5 分钟一次) + 读开关 60 次; 有积压仍一口气领完
     ㉒ econ_on 中途打开: 一分钟内回到正常节奏(6 秒一次)
     ㉓ econ_on 关着: 发件箱空闲 5 分钟才领一次; 开着仍 30 秒
     ㉔ 三条比赛线程都闲着只有一条在问(真线程); 来了一对任务, 两条线程各领一份、同时算
  ㉕~㉚ 空闲省流量第三步(#23 · 2026-11-16 · 迁移 20261116b): 比赛线程一次请求 rpc/referee_poll 问完
     (正常任务 → 补流 → 开关 → 有没有经济重放 / 发件); ⑥~⑬ 默认就走这条路(假服务端把库内两步也记进 calls), ⑦⑬ 走旧库路径
     ㉕ 空闲一小时只发 referee_poll(约 610 个, 其中约 60 个要补流); 旧库(404)问一次就退回分开问、节奏同 ⑨
     ㉖ 回包里的开关进缓存(不再读 referee_flags); 要了补流却领到正常任务 ⇒ 下一轮仍要; 回包里的补流交给 handle_restream
     ㉗ 经济线程: 合并轮询说「没有」⇒ 一小时不发请求(旧做法约 610 次); 说「有」⇒ 当秒领走  ㉘ 消息过期 ⇒ 20 秒后照旧自己问
     ㉙ 发件箱同 ㉗(旧做法 econ_on 开着约 130 次)  ㉚ 回包不是对象 ⇒ 当领活失败(等 ≥5 秒); worker_loop 真走 claim_work
进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import importlib.util
import threading
import time
import io
import json
import os
import shutil
import sys
import tempfile
import urllib.error

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'server', 'referee', 'referee_poller.py')

fails = [0]
n = [0]


def ok(name, cond, detail=''):
    n[0] += 1
    if cond:
        print('  [PASS] ' + name + (('   ' + detail) if detail else ''))
    else:
        fails[0] += 1
        print('  [FAIL] ' + name + '   ' + detail)


def load():
    spec = importlib.util.spec_from_file_location('referee_poller_under_test', SRC)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


MID = '5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b'
VER = '9.9.9'


class Env:
    """一份干净的环境: 版本工程目录(带录流代码)/ 对外目录 / 临时目录 / 工作目录。"""

    def __init__(self, m):
        self.m = m
        self.tmp = tempfile.mkdtemp(prefix='g20_poller_')
        self.proj = os.path.join(self.tmp, 'proj')
        os.makedirs(os.path.join(self.proj, 'scripts', 'systems', 'stream'))
        os.makedirs(os.path.join(self.proj, 'scenes'))
        open(os.path.join(self.proj, 'scripts', 'systems', 'stream', 'stream_recorder.gd'), 'w').close()
        open(os.path.join(self.proj, 'scenes', 'Referee.tscn'), 'w').close()
        with open(os.path.join(self.proj, 'project.godot'), 'w', encoding='utf-8') as f:
            f.write('config/version="%s"\n' % VER)
        self.root = os.path.join(self.tmp, 'streams')
        os.makedirs(self.root)
        self.calls = []
        self.popens = 0
        self.fake_res = {}
        self.chunks = 5
        self.claims = {'referee_claim': [], 'referee_claim_restream': [], 'econ_replay_claim': []}
        self.econ_in = None
        self.econ_404 = False
        self.econ_poison = None
        self.flags = {}
        self.godot_proj = None
        self.restream_404 = False
        self.restream_err = False
        self.on_complete = None
        self.echo_mid = False            # 假 Godot 的结果单照任务单回填 match_id(真 Godot 就是这样); 默认 False = 一律写 fake_res 原样
        self.poll_404 = False            # True = 旧库(没有 referee_poll): 轮询器退回分开问
        self.econ_pending = False        # 假 referee_poll 回包里的 econ / outbox
        self.outbox_pending = False
        self.times = []                  # (函数名, 当时的 _now()) —— 量「多快领到」
        for k in ('POLL_SEC', 'IDLE_POLL_SEC', 'IDLE_AFTER_SEC', 'RESTREAM_POLL_SEC', 'IDLE_FOLLOW_SEC', 'FLAGS_TTL_SEC',
                  'ECON_OFF_POLL_SEC', 'OUTBOX_OFF_POLL_SEC', 'HINT_STALE_SEC'):
            os.environ.pop(k, None)
        m._flags.reset()                 # 开关缓存是模块级的, 每份环境从头读
        m._poll_off.clear()
        m._hint_econ.reset()
        m._hint_outbox.reset()
        m._workers = 1
        os.environ['STREAM_ROOT'] = self.root
        os.environ.pop('STREAM_TMP', None)
        os.environ['JOB_TIMEOUT_SEC'] = '30'
        os.environ['VERSIONS_DIR'] = self.tmp
        # ★工作目录也必须指到临时目录: 不设就落到轮询器默认的 /var/lib/turtle-referee ——
        #   Windows 上静默建出 C:\var\lib\... (本机绿), Linux CI 上没权限 ⇒ PermissionError ⇒ ⑥⑧红(2026-10-20)。
        os.environ['WORK_DIR'] = os.path.join(self.tmp, 'work')
        env = self

        def fake_rpc(fn, body, timeout=20.0):
            env.calls.append((fn, body))
            env.times.append((fn, env.m._now()))
            if fn == 'referee_poll':
                ## 假服务端 20261116b: 库里照 referee_claim → (空了且 p_restream) referee_claim_restream 的顺序领;
                ##   库内这两步也记进 calls(三元组, 第三项 'in_poll'), 好让「领了几次 / 问了几次补流」的老断言照样量; HTTP 请求数看 http()
                if env.poll_404:
                    raise urllib.error.HTTPError('http://x/rpc/' + fn, 404, 'Not Found', None, None)
                env.calls.append(('referee_claim', body, 'in_poll'))
                got = []
                if env.claims['referee_claim']:
                    got = [env.claims['referee_claim'].pop(0)]
                elif body.get('p_restream'):
                    env.calls.append(('referee_claim_restream', body, 'in_poll'))
                    if env.claims['referee_claim_restream']:
                        got = [env.claims['referee_claim_restream'].pop(0)]
                return {'v': 1, 'jobs': got, 'flags': dict(env.flags), 'econ': env.econ_pending, 'outbox': env.outbox_pending}
            if fn == 'referee_complete' and env.on_complete:
                env.on_complete()
            if fn == 'econ_replay_claim' and env.econ_404:
                raise urllib.error.HTTPError('http://x/rpc/' + fn, 404, 'Not Found', None, None)
            if fn == 'econ_replay_claim':
                q = env.claims[fn]
                return q.pop(0) if q else []
            if fn == 'referee_flags':
                return env.flags
            if fn == 'referee_claim_restream' and env.restream_404:
                raise urllib.error.HTTPError('http://x/rpc/' + fn, 404, 'Not Found', None, None)
            if fn == 'referee_claim_restream' and env.restream_err:
                raise urllib.error.URLError('连不上')
            if fn in env.claims:
                q = env.claims[fn]
                return [q.pop(0)] if q else []
            return {'ok': True}

        class FakePopen:
            def __init__(self, cmd, stdout=None, stderr=None, env=None):
                me.popens += 1
                stream = out = econ = jobp = None
                if '--path' in cmd:
                    me.godot_proj = cmd[cmd.index('--path') + 1]
                for a in cmd:
                    if a.startswith('--econ-replay='):
                        econ = a[len('--econ-replay='):]
                    if a.startswith('--stream='):
                        stream = a[len('--stream='):]
                    if a.startswith('--out='):
                        out = a[len('--out='):]
                    if a.startswith('--job='):
                        jobp = a[len('--job='):]
                if stream:
                    os.makedirs(stream, exist_ok=True)
                    for i in range(me.chunks):
                        with open(os.path.join(stream, '%06d.bin' % i), 'wb') as f:
                            f.write(b'chunk%d' % i)
                    with open(os.path.join(stream, 'end.json'), 'w', encoding='utf-8') as f:
                        json.dump({'chunks': me.chunks, 'last_step': 600}, f)
                if econ:
                    with open(econ, encoding='utf-8') as f:
                        me.econ_in = json.load(f)
                    if me.econ_poison is None or not any(j['account_id'] == me.econ_poison for j in me.econ_in['jobs']):
                        with open(out, 'w', encoding='utf-8') as f:
                            json.dump({'results': [{'account_id': j['account_id'], 'week': j['week'], 'seen': j['seen'],
                                                    'result': {'upto': len(j['rows']), 'bad_at': -1, 'assets': {}}}
                                                   for j in me.econ_in['jobs']]}, f)
                elif out:
                    r = dict(me.fake_res)
                    if me.echo_mid and jobp:
                        with open(jobp, encoding='utf-8') as f:
                            r['match_id'] = json.load(f).get('match_id')
                    with open(out, 'w', encoding='utf-8') as f:
                        json.dump(r, f)

            def wait(self, timeout=None):
                return 0

            def kill(self):
                pass

        me = self
        m.rpc = fake_rpc
        m.subprocess.Popen = FakePopen

    def names(self, fn):
        return [c for c in self.calls if c[0] == fn]

    def http(self, fn=None):
        """真发出去的请求(不含 referee_poll 库内那两步)。"""
        return [c for c in self.calls if len(c) == 2 and (fn is None or c[0] == fn)]

    def pub(self):
        return os.path.join(self.root, MID)

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


def job(**kw):
    j = {'v': 1, 'task': 'restream', 'job_id': 77, 'match_id': MID, 'mode': 'gauntlet', 'key': {'week': 1},
         'seed': 2000023, 'client_version': VER, 'level': None, 'a': {}, 'b': {},
         'expect_winner': 'a', 'expect_digest': 'abc123'}
    j.update(kw)
    return j


def res(**kw):
    r = {'ok': True, 'match_id': MID, 'winner': 'a', 'digest': 'abc123', 'steps': 600, 'seed': 2000023,
         'client_version': VER, 'replay_b64': 'eJw='}
    r.update(kw)
    return r


class FakeStop:
    """假 _stop: wait() 只拨假时钟, 到点触发 hooks, 走满 end 就停, 每次等待都记下来。"""

    def __init__(self, clock, end, hooks):
        self.clock, self.end, self.hooks, self.waits = clock, end, list(hooks), []

    def is_set(self):
        return self.clock[0] >= self.end

    def wait(self, sec):
        self.waits.append(sec)
        self.clock[0] += sec
        for h in list(self.hooks):
            if self.clock[0] - 1000.0 >= h[0]:
                self.hooks.remove(h)
                h[1]()


def run_sim(m, sec, hooks=(), e=None, job_sec=0.0, loop=None, pre=None):
    """跑真 worker_loop(或 loop 给的那条循环), 时钟是假的。hooks = [(第几秒, 函数)]。job_sec = 一局在假时钟上算多久。
    pre = 换好假时钟之后、循环开始之前调一次(第 0 秒就该在的状态)。"""
    clock = [1000.0]
    if e is not None:
        e.on_complete = lambda: clock.__setitem__(0, clock[0] + job_sec)
    st = FakeStop(clock, 1000.0 + sec, hooks)
    old_now, old_stop = m._now, m._stop
    m._now, m._stop = (lambda: clock[0]), st
    try:
        if pre is not None:
            pre()
        if loop is None:
            m.worker_loop(0, False)
        else:
            loop()
    finally:
        m._now, m._stop = old_now, old_stop
    return st


def every(step, end, fn, start=0):
    """FakeStop 的 hooks: 从 start 到 end 每 step 秒调一次 fn(t)。"""
    return [(t, (lambda t=t: fn(t))) for t in range(start, end, step)]


def third_step(m, ejobs):
    print('=== 空闲省流量第三步(#23 · 合并轮询 referee_poll) ===')
    # ㉕ 比赛线程一小时全空闲: 每轮只发一个请求; 补流跟在同一个请求里
    e = Env(m)
    run_sim(m, 3600)
    h = e.http()
    hp = e.http('referee_poll')
    rs = [c for c in hp if c[1].get('p_restream')]
    ok('㉕ 空闲一小时比赛线程发了 %d 个请求, 全是 referee_poll(%d 个)' % (len(h), len(hp)), len(h) == len(hp) and 560 <= len(hp) <= 660,
       str(sorted({c[0] for c in h})))
    ok('㉕ 其中要补流的 %d 个(约 60, 同旧节奏)、库里真问补流 %d 次' % (len(rs), len(e.names('referee_claim_restream'))),
       55 <= len(rs) <= 66 and len(e.names('referee_claim_restream')) == len(rs))
    ok('㉕ ★不再单独发 referee_claim / referee_claim_restream / referee_flags',
       not e.http('referee_claim') and not e.http('referee_claim_restream') and not e.http('referee_flags'))
    e.close()
    # ㉕ 旧库(404): 问一次 referee_poll 之后退回分开问, 节奏同 ⑨
    e = Env(m)
    e.poll_404 = True
    run_sim(m, 3600)
    ok('㉕ 旧库: referee_poll 只问 1 次(%d), 之后 referee_claim %d 次 / 补流 %d 次(同 ⑨)' % (
        len(e.http('referee_poll')), len(e.http('referee_claim')), len(e.http('referee_claim_restream'))),
       len(e.http('referee_poll')) == 1 and 560 <= len(e.http('referee_claim')) <= 660
       and 55 <= len(e.http('referee_claim_restream')) <= 66 and m._poll_off.is_set())
    e.close()
    # ㉖ 回包里的开关进缓存: 之后 econ_on_now() 不再单独读
    e = Env(m)
    e.flags = {'econ_on': True}
    m.worker_loop(0, True)
    on = m.econ_on_now()
    ok('㉖ 合并轮询带回 econ_on = 开 ⇒ econ_on_now() 为真、没发 referee_flags', on is True and not e.http('referee_flags'),
       str([c[0] for c in e.http()]))
    e.close()
    # ㉖ 要了补流却领到正常任务 ⇒ 不算问过补流(下一轮仍要)
    e = Env(m)
    e.fake_res = res()
    nj = job()
    nj.pop('task')
    e.claims['referee_claim'] = [nj]
    run_sim(m, 4)
    hp = e.http('referee_poll')
    ok('㉖ 第一轮领到正常任务、第二轮仍要补流(p_restream: %s)' % [c[1].get('p_restream') for c in hp],
       len(hp) >= 2 and hp[0][1].get('p_restream') is True and hp[1][1].get('p_restream') is True
       and len(e.names('referee_complete')) == 1)
    e.close()
    # ㉖ 回包里的补流交给 handle_restream
    e = Env(m)
    e.fake_res = res()
    e.claims['referee_claim_restream'] = [job()]
    m.worker_loop(0, True)
    ok('㉖ 合并轮询领到的补流交给 handle_restream(done 一次、没有 complete)',
       len(e.names('referee_restream_done')) == 1 and not e.names('referee_complete'))
    e.close()
    # ㉗ 经济线程: 合并轮询每 6 秒说一次「没有」⇒ 一小时一个请求都不发; 第 600 秒起说「有」⇒ 一两秒内领走
    e = Env(m)
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    e.flags = {'econ_on': True}
    m._econ_off.clear()

    def econ_tick(t):
        m._flags.put(e.flags)
        m._hint_econ.put(600 <= t < 612)
        if t == 600:
            e.claims['econ_replay_claim'].append(ejobs)
    run_sim(m, 3600, every(6, 3600, econ_tick), loop=m.econ_loop, pre=lambda: econ_tick(0))
    cl = [t for fn, t in e.times if fn == 'econ_replay_claim']
    fr = [t for fn, t in e.times if fn == 'referee_flags' and t < 1600.0]
    ok('㉗ 空闲一小时经济线程只在「有」的那十几秒里发请求(领 %d 次, 旧做法约 610 次; 之前读开关 %d 次)' % (len(cl), len(fr)),
       1 <= len(cl) <= 8 and not fr and min(cl or [0]) >= 1600.0, str(cl))
    ok('㉗ 第 600 秒说「有」⇒ %.1f 秒内领走并回写' % ((cl[0] - 1600.0) if cl else -1),
       bool(cl) and 1600.0 <= cl[0] <= 1602.0 and len(e.names('econ_replay_done')) == 1)
    e.close()
    # ㉘ 消息过期(只在第 0 秒说过一次「没有」, 之后比赛线程一直在算长局)⇒ 20 秒后照旧自己问
    e = Env(m)
    e.flags = {'econ_on': True}
    m._econ_off.clear()
    run_sim(m, 3600, loop=m.econ_loop, pre=lambda: m._hint_econ.put(False))
    cl = [t for fn, t in e.times if fn == 'econ_replay_claim']
    ok('㉘ 消息过期 ⇒ 照旧自己问(一小时 %d 次, 应约 600)、第一次在第 %.0f 秒(应 ≥20)' % (len(cl), (cl[0] - 1000.0) if cl else -1),
       550 <= len(cl) <= 660 and cl[0] - 1000.0 >= 20.0)
    e.close()
    # ㉙ 发件箱: 合并轮询说「没有」⇒ 一小时不发请求(旧做法 econ_on 开着约 130 次); 第 600 秒说「有」⇒ 一两秒内领
    e = Env(m)
    e.flags = {'econ_on': True}
    e.claims['mainsite_outbox_claim'] = []
    os.environ['MAINSITE_BASE'] = 'http://127.0.0.1:9'
    os.environ['MAINSITE_HOOK_SECRET'] = 'f' * 64
    m._outbox_off.clear()

    def ob_tick(t):
        m._flags.put(e.flags)
        m._hint_outbox.put(600 <= t < 606)
    try:
        run_sim(m, 3600, every(6, 3600, ob_tick), loop=m.outbox_loop, pre=lambda: ob_tick(0))
    finally:
        os.environ.pop('MAINSITE_BASE', None)
        os.environ.pop('MAINSITE_HOOK_SECRET', None)
    cl = [t for fn, t in e.times if fn == 'mainsite_outbox_claim']
    ok('㉙ 发件箱空闲一小时只在说「有」时领(%d 次)、第一次在第 %.0f 秒(应 600~602)' % (len(cl), (cl[0] - 1000.0) if cl else -1),
       1 <= len(cl) <= 3 and 1600.0 <= cl[0] <= 1602.0 and not e.http('referee_flags'), str(cl))
    e.close()
    # ㉚ 回包坏了(不是对象)⇒ 当领活失败处理(等 ≥5 秒再问), 不当成「没活」也不崩
    e = Env(m)
    real = m.rpc
    m.rpc = lambda fn, body, timeout=20.0: (e.calls.append((fn, body)) or ['oops']) if fn == 'referee_poll' else real(fn, body, timeout)
    st = run_sim(m, 30)
    m.rpc = real
    ok('㉚ 回包不是对象 ⇒ 记一行 WARN、每次等 ≥5 秒(%s)' % st.waits[:3], len(st.waits) >= 3 and min(st.waits) >= 5.0)
    e.close()
    src = open(m.__file__, encoding='utf-8').read()
    ok('㉚ ★worker_loop 真用 claim_work(不是直接 rpc referee_claim)',
       'claim_work(worker, versions, want_rs)' in src and 'jobs = rpc("referee_claim"' not in src)


def main():
    m = load()
    print('=== 补流(restream)任务 ===')
    # ① 成功
    e = Env(m)
    e.fake_res = res()
    vers = m.discover_versions(e.tmp)
    ok('分母 · 假版本目录被认出(%s)' % sorted(vers), vers.get(VER) == e.proj)
    m.handle_restream(job(), vers, 'w-0', os.path.join(e.tmp, 'w0'))
    done = e.names('referee_restream_done')
    files = sorted(os.listdir(e.pub())) if os.path.isdir(e.pub()) else []
    ok('① 起了一次 Godot', e.popens == 1)
    ok('① ★对外目录有全部 %d 块 + end.json' % e.chunks, files == ['%06d.bin' % i for i in range(e.chunks)] + ['end.json'], str(files))
    ok('① done(ok=true) 恰好一次', len(done) == 1 and done[0][1]['p_ok'] is True and done[0][1]['p_match_id'] == MID, str(done))
    ok('① ★★一次 referee_complete / referee_fail 都没有(不写回结果、不改账)',
       not e.names('referee_complete') and not e.names('referee_fail'), str([c[0] for c in e.calls]))
    e.close()
    # ② 胜方不同
    e = Env(m)
    e.fake_res = res(winner='b')
    m.handle_restream(job(), m.discover_versions(e.tmp), 'w-0', os.path.join(e.tmp, 'w0'))
    done = e.names('referee_restream_done')
    ok('② ★重算胜方与原结果不同 ⇒ 流撤掉(对外目录没有 end.json)', not os.path.exists(os.path.join(e.pub(), 'end.json')))
    ok('② done(ok=false, permanent) 原因 winner_mismatch', len(done) == 1 and done[0][1]['p_ok'] is False
       and done[0][1]['p_permanent'] is True and str(done[0][1]['p_error']).startswith('winner_mismatch'), str(done))
    ok('② 也没有 referee_complete', not e.names('referee_complete'))
    e.close()
    # ③ 指纹不同
    e = Env(m)
    e.fake_res = res(digest='zzz')
    m.handle_restream(job(), m.discover_versions(e.tmp), 'w-0', os.path.join(e.tmp, 'w0'))
    done = e.names('referee_restream_done')
    ok('③ ★指纹不同 ⇒ 流撤掉、done(digest_mismatch, permanent)', not os.path.exists(os.path.join(e.pub(), 'end.json'))
       and len(done) == 1 and done[0][1]['p_error'] == 'digest_mismatch' and done[0][1]['p_permanent'] is True, str(done))
    e.close()
    # ④ 没设 STREAM_ROOT
    e = Env(m)
    os.environ['STREAM_ROOT'] = ''
    e.fake_res = res()
    m.handle_restream(job(), m.discover_versions(e.tmp), 'w-0', os.path.join(e.tmp, 'w0'))
    done = e.names('referee_restream_done')
    ok('④ 没设 STREAM_ROOT ⇒ 不起 Godot、done(stream_off, permanent)', e.popens == 0 and len(done) == 1
       and done[0][1]['p_error'] == 'stream_off' and done[0][1]['p_permanent'] is True, str(done))
    e.close()
    # ⑤ 已有完整流
    e = Env(m)
    os.makedirs(e.pub())
    with open(os.path.join(e.pub(), 'end.json'), 'w') as f:
        f.write('{"chunks": 1}')
    m.handle_restream(job(), m.discover_versions(e.tmp), 'w-0', os.path.join(e.tmp, 'w0'))
    done = e.names('referee_restream_done')
    ok('⑤ 对外目录已有 end.json ⇒ 不起 Godot、done(ok)', e.popens == 0 and len(done) == 1 and done[0][1]['p_ok'] is True, str(done))
    e.close()
    # ⑥ worker_loop: 先正常任务, 空了才补流
    e = Env(m)
    e.fake_res = res()
    e.claims['referee_claim_restream'] = [job()]
    m.worker_loop(0, True)
    order = [c[0] for c in e.calls if c[0].startswith('referee_claim')]
    ok('⑥ ★领活顺序: referee_claim 在前, 空了才 referee_claim_restream', order == ['referee_claim', 'referee_claim_restream'], str(order))
    ok('⑥ 补流任务交给 handle_restream(done 一次、没有 complete)', len(e.names('referee_restream_done')) == 1
       and not e.names('referee_complete'))
    e.close()
    # ⑦ 404(旧库路径: 没有 referee_poll 才会分开问补流)
    e = Env(m)
    m._restream_off.clear()
    e.poll_404 = True
    e.restream_404 = True
    m.worker_loop(0, True)
    m.worker_loop(0, True)
    rs = e.names('referee_claim_restream')
    ok('⑦ referee_claim_restream 404 ⇒ 本进程只问一次就不再领(问了 %d 次)' % len(rs), len(rs) == 1 and m._restream_off.is_set())
    m._restream_off.clear()
    e.close()
    # ⑧ 正常任务照旧
    e = Env(m)
    e.fake_res = res()
    nj = job()
    nj.pop('task')
    e.claims['referee_claim'] = [nj]
    m.worker_loop(0, True)
    ok('⑧ 正常任务: referee_complete 一次、没有补流写回', len(e.names('referee_complete')) == 1
       and not e.names('referee_restream_done') and not e.names('referee_claim_restream'), str([c[0] for c in e.calls]))
    e.close()
    # ⑨ 空闲放慢 + 补流限频: 一小时全空闲
    e = Env(m)
    st = run_sim(m, 3600)
    c, r = len(e.names('referee_claim')), len(e.names('referee_claim_restream'))
    ok('⑨ 空闲一小时领活 %d 次(不放慢是 1800, 应约 610)' % c, 560 <= c <= 660)
    ok('⑨ 空闲一小时问补流 %d 次(不限频是 1800, 应约 60)' % r, 55 <= r <= 66)
    ok('⑨ 头 30 秒仍是 2 秒一次', st.waits[:15] == [2.0] * 15, str(st.waits[:16]))
    ok('⑨ 空闲之后是 6 秒一次(分母 %d 次等待)' % len(st.waits), len(st.waits) > 500 and st.waits[-1] == 6.0)
    e.close()
    # ⑩ 放慢后来了任务
    e = Env(m)
    e.fake_res = res()
    nj = job()
    nj.pop('task')
    st = run_sim(m, 660, [(600, lambda: e.claims['referee_claim'].append(nj))])
    t, k = 0.0, 0
    while t < 600:
        t += st.waits[k]
        k += 1
    ok('⑩ 放慢后来的任务被领走(complete %d 次)' % len(e.names('referee_complete')), len(e.names('referee_complete')) == 1)
    ok('⑩ 等待不超过 6 秒', st.waits[k - 1] == 6.0, str(st.waits[k - 2:k + 2]))
    ok('⑩ 领到之后回到 2 秒', st.waits[k:k + 15] == [2.0] * 15, str(st.waits[k:k + 16]))
    e.close()
    # ⑩ 一局算很久: 算完也算刚忙过, 不是从领到那一刻起算空闲
    e = Env(m)
    e.fake_res = res()
    nj = job()
    nj.pop('task')
    e.claims['referee_claim'] = [nj]
    st = run_sim(m, 180, e=e, job_sec=120.0)
    ok('⑩ 算了 120 秒的局结束后仍 2 秒一次(分母 %d 次等待)' % len(st.waits), len(st.waits) >= 15 and st.waits[:15] == [2.0] * 15, str(st.waits[:16]))
    e.close()
    # ⑪ 补流有积压
    e = Env(m)
    e.fake_res = res()
    e.claims['referee_claim_restream'] = [job(), job()]
    run_sim(m, 10)
    ok('⑪ 积压的两份 10 秒内都领走(done %d 次, 问 %d 次)' % (len(e.names('referee_restream_done')), len(e.names('referee_claim_restream'))),
       len(e.names('referee_restream_done')) == 2 and len(e.names('referee_claim_restream')) == 3)
    e.close()
    # ⑫ 限频窗口内来了补流
    e = Env(m)
    e.fake_res = res()
    run_sim(m, 170, [(100, lambda: e.claims['referee_claim_restream'].append(job()))])
    ok('⑫ 窗口内来的补流下一次询问就领到(done %d 次)' % len(e.names('referee_restream_done')), len(e.names('referee_restream_done')) == 1)
    e.close()
    # ⑬ 领补流失败也限频(旧库路径)
    e = Env(m)
    e.poll_404 = True
    e.restream_err = True
    run_sim(m, 600)
    r = len(e.names('referee_claim_restream'))
    ok('⑬ 网络失败时十分钟只问 %d 次(不限频约 300 次)' % r, 8 <= r <= 12)
    e.close()
    print('=== 局外经济流水重放 ===')
    ejobs = [{'account_id': 'a1', 'week': 1, 'seen': 2, 'facts': {'ranked': {'n': 3}},
              'rows': [{'op': 'lock', 'seq': 0}, {'op': 'lock', 'seq': 1}]},
             {'account_id': 'a2', 'week': 1, 'seen': 1, 'facts': {'ranked': {'n': 7}}, 'rows': [{'op': 'buy_xp', 'seq': 0}]}]
    # ⑭
    e = Env(m)
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    vers = m.discover_versions(e.tmp)
    wd = os.path.join(e.tmp, 'econw')
    e.claims['econ_replay_claim'] = [ejobs]
    e.flags = {'econ_on': True}
    n9 = m.handle_econ(m.claim_econ(), vers, wd)
    done = e.names('econ_replay_done')
    ok('⑭ 一个 Godot 进程算一批: 进去 2 个号、strict = econ_on(开)', e.popens == 1 and e.econ_in is not None
       and len(e.econ_in.get('jobs', [])) == 2 and e.econ_in.get('strict') is True, str(e.econ_in)[:120])
    ok('⑭ ★每个号的 facts 原样进输入文件', e.econ_in is not None
       and [j.get('facts', {}).get('ranked', {}).get('n') for j in e.econ_in['jobs']] == [3, 7], str(e.econ_in)[:160])
    ok('⑭ ★econ_replay_done 回写那一批(2 个号, seen 原样带回)', n9 == 2 and len(done) == 1
       and [i['account_id'] for i in done[0][1]['p_items']] == ['a1', 'a2']
       and [i['seen'] for i in done[0][1]['p_items']] == [2, 1], str(done)[:200])
    e.close()
    # ⑮
    e = Env(m)
    e.claims['econ_replay_claim'] = [ejobs]
    m.worker_loop(0, True)
    m.worker_loop(1, True)
    ok('⑮ ★比赛工作线程不领经济重放', not e.names('econ_replay_claim'), str([c[0] for c in e.calls]))
    e.close()
    # ⑯
    e = Env(m)
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    e.claims['econ_replay_claim'] = [ejobs]
    os.environ['POLL_SEC'] = '0.01'
    th = threading.Thread(target=m.econ_loop, daemon=True)
    th.start()
    for _ in range(300):
        if e.names('econ_replay_done'):
            break
        time.sleep(0.01)
    m._stop.set()
    th.join(5)
    m._stop.clear()
    os.environ.pop('POLL_SEC', None)
    ok('⑯ ★单开的 econ_loop 领了一批并回写、_stop 之后退出', len(e.names('econ_replay_done')) == 1 and not th.is_alive())
    src = open(m.__file__, encoding='utf-8').read()
    ok('⑯ ★main 真起了这条线程', 'threading.Thread(target=econ_loop' in src)
    e.close()
    # ⑰
    e = Env(m)
    m._econ_off.clear()
    e.econ_404 = True
    r1 = m.claim_econ()
    r2 = m.claim_econ()
    ok('⑰ econ_replay_claim 404 ⇒ 本进程只问一次就不再领', r1 == [] and r2 == [] and len(e.names('econ_replay_claim')) == 1
       and m._econ_off.is_set())
    m.econ_loop()
    ok('⑰ 404 之后 econ_loop 立刻退出(不空转)', len(e.names('econ_replay_claim')) == 1)
    m._econ_off.clear()
    e.close()
    # ⑱
    e = Env(m)
    old = os.path.join(e.tmp, 'old')
    os.makedirs(os.path.join(old, 'scripts', 'referee'))
    os.makedirs(os.path.join(old, 'scenes'))
    open(os.path.join(old, 'scenes', 'Referee.tscn'), 'w').close()
    open(os.path.join(old, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    with open(os.path.join(old, 'project.godot'), 'w', encoding='utf-8') as f:
        f.write('config/version="9.9.8"\n')
    vers = m.discover_versions(e.tmp)
    ok('⑱ 最新的 9.9.9 没有 econ_replay.gd ⇒ 用带它的 9.9.8', m.econ_project(vers) == old, str(vers))
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    ok('⑱ 9.9.9 也带了 ⇒ 用最新的 9.9.9', m.econ_project(vers) == e.proj)
    e.close()
    # ⑲
    e = Env(m)
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    e.econ_poison = 'a2'
    n14 = m.handle_econ(ejobs, m.discover_versions(e.tmp), os.path.join(e.tmp, 'econw'))
    done = e.names('econ_replay_done')
    ok('⑲ ★整批算不出来 ⇒ 拆开算: 算得出的 a1 回写了, a2 没回写, 共起 3 个进程', n14 == 1 and e.popens == 3 and len(done) == 1
       and [i['account_id'] for i in done[0][1]['p_items']] == ['a1'], '%d popens=%d %s' % (n14, e.popens, str(done)[:160]))
    e.close()
    # ⑳ econ_loop 空闲放慢: 一小时全空闲(econ_replay_claim 一直回空); econ_on 开着(关着见 ㉑)
    e = Env(m)
    e.flags = {'econ_on': True}
    m._econ_off.clear()
    st = run_sim(m, 3600, loop=m.econ_loop)
    c = len(e.names('econ_replay_claim'))
    ok('⑳ econ_loop 空闲一小时领 %d 次(不放慢是 1800, 应约 610)' % c, 560 <= c <= 660)
    ok('⑳ econ_loop 头 30 秒仍是 2 秒一次', st.waits[:15] == [2.0] * 15, str(st.waits[:16]))
    ok('⑳ econ_loop 空闲之后是 6 秒一次(分母 %d 次等待)' % len(st.waits), len(st.waits) > 500 and st.waits[-1] == 6.0)
    e.close()
    print('=== 空闲省流量第二步(#23) ===')
    # ㉑ econ_on 关着: 5 分钟领一次, 开关 1 分钟读一次
    e = Env(m)
    st = run_sim(m, 3600, loop=m.econ_loop)
    c, fr = len(e.names('econ_replay_claim')), len(e.names('referee_flags'))
    ok('㉑ econ_on 关着: 一小时领 %d 次(开着约 610, 应 12)' % c, 11 <= c <= 13)
    ok('㉑ econ_on 关着: 一小时读开关 %d 次(应约 60)' % fr, 55 <= fr <= 62)
    ok('㉑ 合计 %d 次请求 < 开着时的八分之一' % (c + fr), c + fr < 610 / 8)
    e.close()
    e = Env(m)
    os.makedirs(os.path.join(e.proj, 'scripts', 'referee'), exist_ok=True)
    open(os.path.join(e.proj, 'scripts', 'referee', 'econ_replay.gd'), 'w').close()
    e.claims['econ_replay_claim'] = [ejobs, ejobs, ejobs]
    st = run_sim(m, 10, loop=m.econ_loop)
    ok('㉑ econ_on 关着但有积压: 10 秒内三批都领完回写(回写 %d 批)' % len(e.names('econ_replay_done')),
       len(e.names('econ_replay_done')) == 3)
    e.close()
    # ㉒ econ_on 第 600 秒打开: 一分钟内回到正常节奏
    e = Env(m)
    st = run_sim(m, 1800, [(600, lambda: e.flags.update({'econ_on': True}))], loop=m.econ_loop)
    t, k = 0.0, 0
    while t < 660 and k < len(st.waits):
        t += st.waits[k]
        k += 1
    ok('㉒ 开关打开后一分钟内回到 ≤6 秒一次(之后 %d 次等待都 ≤6)' % len(st.waits[k:]),
       len(st.waits[k:]) > 150 and max(st.waits[k:]) <= 6.0, str(st.waits[max(0, k - 3):k + 3]))
    e.close()
    # ㉓ 发件箱: econ_on 关着 5 分钟领一次, 开着 30 秒
    for on, lo, hi, label in ((False, 18, 26, '关着 ⇒ 约 22 次'), (True, 120, 135, '开着 ⇒ 约 130 次')):
        e = Env(m)
        e.flags = {'econ_on': on}
        e.claims['mainsite_outbox_claim'] = []
        os.environ['MAINSITE_BASE'] = 'http://127.0.0.1:9'
        os.environ['MAINSITE_HOOK_SECRET'] = 'f' * 64
        m._outbox_off.clear()
        try:
            run_sim(m, 3600, loop=m.outbox_loop)
        finally:
            os.environ.pop('MAINSITE_BASE', None)
            os.environ.pop('MAINSITE_HOOK_SECRET', None)
        c = len(e.names('mainsite_outbox_claim'))
        ok('㉓ 发件箱 econ_on %s: 一小时领 %d 次(%s)' % ('开' if on else '关', c, label), lo <= c <= hi)
        e.close()
    # ㉔ 三条比赛线程都闲着只有一条在问(真线程, 时间缩小 100 倍: 忙时 0.02 秒, 空闲 0.06 秒)
    e = Env(m)
    e.fake_res = res()
    os.environ.update({'POLL_SEC': '0.02', 'IDLE_POLL_SEC': '0.06', 'IDLE_AFTER_SEC': '0', 'RESTREAM_POLL_SEC': '1000',
                       'IDLE_FOLLOW_SEC': '30'})
    m._workers = 3
    m._stop.clear()
    ths = [threading.Thread(target=m.worker_loop, args=(i, False), daemon=True) for i in range(3)]
    for th in ths:
        th.start()
    time.sleep(1.2)
    idle_claims = list(e.names('referee_claim'))
    who = sorted({c[1]['p_worker'] for c in idle_claims})
    ok('㉔ 三条线程都闲着 1.2 秒: 领活 %d 次(各问各的约 60 次, 应约 20)、问的只有 %s' % (len(idle_claims), who),
       8 <= len(idle_claims) <= 30, str(who))
    # 两份是两局 ⇒ match_id 也要不同(2026-11-11): 同一个 match_id 两条线程同时录同一个流目录, 先算完的那份收尾时把目录删了,
    #   另一份 FileNotFoundError、永远算不完 ⇒ 等满 5 秒误红(Linux CI 上两次; 本机 Windows 时序撞不上)。正式环境一局只有一份任务。
    nj1, nj2 = job(), job(job_id=78, match_id=MID[:-1] + 'c')
    e.echo_mid = True
    nj1.pop('task')
    nj2.pop('task')
    busy = {}

    def slow_complete():
        busy[threading.current_thread().name] = time.time()
        time.sleep(0.4)                  # 一局算 0.4 秒: 第二份要等第一份算完 ⇒ 说明没被叫醒
    e.on_complete = slow_complete
    t0 = time.time()
    e.claims['referee_claim'] = [nj1, nj2]
    while len(e.names('referee_complete')) < 2 and time.time() - t0 < 5:
        time.sleep(0.01)
    took = time.time() - t0
    m._stop.set()
    m._baton.poke()
    for th in ths:
        th.join(5)
    ok('㉔ 来了一对任务: 两条线程各领一份(%d 条线程在算)、%.2f 秒两份都开算(没叫醒要等第一份算完 ≥0.4 秒)' % (len(busy), took),
       len(busy) == 2 and took < 0.3)
    ok('㉔ 停机后三条线程都退出(睡在接力棒上的也被叫醒)', not any(th.is_alive() for th in ths))
    m._stop.clear()
    m._workers = 1
    for k in ('POLL_SEC', 'IDLE_POLL_SEC', 'IDLE_AFTER_SEC', 'RESTREAM_POLL_SEC', 'IDLE_FOLLOW_SEC'):
        os.environ.pop(k, None)
    e.close()
    third_step(m, ejobs)
    print('')
    if fails[0] == 0 and n[0] >= 40:
        print('ALL OK — 补流只产出状态流、不写回结果; 重算对不上就撤流; 空闲放慢; 经济重放单开线程批量做 (%d 条)' % n[0])
        return 0
    print('FAIL x%d (断言 %d 条)' % (fails[0], n[0]))
    return 1


if __name__ == '__main__':
    sys.exit(main())
