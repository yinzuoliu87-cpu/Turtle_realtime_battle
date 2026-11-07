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
进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import importlib.util
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
        self.claims = {'referee_claim': [], 'referee_claim_restream': []}
        self.restream_404 = False
        self.restream_err = False
        self.on_complete = None
        for k in ('POLL_SEC', 'IDLE_POLL_SEC', 'IDLE_AFTER_SEC', 'RESTREAM_POLL_SEC'):
            os.environ.pop(k, None)
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
            if fn == 'referee_complete' and env.on_complete:
                env.on_complete()
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
                stream = out = None
                for a in cmd:
                    if a.startswith('--stream='):
                        stream = a[len('--stream='):]
                    if a.startswith('--out='):
                        out = a[len('--out='):]
                if stream:
                    os.makedirs(stream, exist_ok=True)
                    for i in range(me.chunks):
                        with open(os.path.join(stream, '%06d.bin' % i), 'wb') as f:
                            f.write(b'chunk%d' % i)
                    with open(os.path.join(stream, 'end.json'), 'w', encoding='utf-8') as f:
                        json.dump({'chunks': me.chunks, 'last_step': 600}, f)
                if out:
                    with open(out, 'w', encoding='utf-8') as f:
                        json.dump(me.fake_res, f)

            def wait(self, timeout=None):
                return 0

            def kill(self):
                pass

        me = self
        m.rpc = fake_rpc
        m.subprocess.Popen = FakePopen

    def names(self, fn):
        return [c for c in self.calls if c[0] == fn]

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


def run_sim(m, sec, hooks=(), e=None, job_sec=0.0):
    """跑真 worker_loop, 时钟是假的。hooks = [(第几秒, 函数)]。job_sec = 一局在假时钟上算多久。"""
    clock = [1000.0]
    if e is not None:
        e.on_complete = lambda: clock.__setitem__(0, clock[0] + job_sec)
    st = FakeStop(clock, 1000.0 + sec, hooks)
    old_now, old_stop = m._now, m._stop
    m._now, m._stop = (lambda: clock[0]), st
    try:
        m.worker_loop(0, False)
    finally:
        m._now, m._stop = old_now, old_stop
    return st


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
    # ⑦ 404
    e = Env(m)
    m._restream_off.clear()
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
    # ⑬ 领补流失败也限频
    e = Env(m)
    e.restream_err = True
    run_sim(m, 600)
    r = len(e.names('referee_claim_restream'))
    ok('⑬ 网络失败时十分钟只问 %d 次(不限频约 300 次)' % r, 8 <= r <= 12)
    e.close()
    print('')
    if fails[0] == 0 and n[0] >= 26:
        print('ALL OK — 补流只产出状态流、不写回结果; 重算对不上就撤流 (%d 条)' % n[0])
        return 0
    print('FAIL x%d (断言 %d 条)' % (fails[0], n[0]))
    return 1


if __name__ == '__main__':
    sys.exit(main())
