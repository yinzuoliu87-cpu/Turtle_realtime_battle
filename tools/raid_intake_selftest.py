# -*- coding: utf-8 -*-
"""raid_intake_selftest —— 主站建偷袭任务的入口 server/referee/raid_intake.py 的自证门禁
(2026-11-09 · 工作线 A2 · 方案书 docs/plans/20261107-龟战主站对接.md §4.4 / §4.8)。

不连库、不起网关: 把 raid_intake.py 当模块载入, rpc 换成记账的假函数。断言:
  ① 正常请求体 ⇒ 只调一次 rpc/raid_create, 形参 = 主站七个键逐个对上; 回 {ok:true, jobId}(字符串)
  ② ★参数不对一律 ok:false 且**不调数据库**: 缺键 / 类型错 / bool 冒充整数 / raidId ≤ 0 / 纯数字或带怪字符的用户 ID /
     攻守同一人 / seed 或 stake 为负 / isRevenge 不是 bool / expireAt 缺或已过(= now 也算过)
  ③ stake / isRevenge 缺省 ⇒ 0 / false 照建(主站总会带, 缺了不该整场退回)
  ④ 数据库回 ok:false ⇒ 错误码原样透传(raid_off / no_referee / raid_conflict); 怪错误码 ⇒ rejected
  ⑤ ★数据库连不上 / 抛异常 / 回包不是对象 / ok 却没有 jobId ⇒ busy(主站立即退回, 不挂单); handle_create 本身不抛
  ⑥ jobId 是整数 ⇒ 转成字符串; 同一 raidId 重发两次 ⇒ 两次都原样回数据库给的同一个 jobId(幂等在数据库, 本层不缓存不改写)
  ⑦ rpc 支持 timeout 参数 ⇒ 传 < 10 秒(主站 10 秒超时); 不支持 ⇒ 照样能调
  ⑧ ★形参对账: 迁移 20261109c 里 raid_create 的形参 = 本模块 ARG_MAP 的右列(顺序也同); 本模块先查的那几个错误码数据库也查
进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import importlib.util
import io
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'server', 'referee', 'raid_intake.py')
MIG = os.path.join(ROOT, 'server', 'supabase', 'migrations', '20261109c_raid.sql')

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
    spec = importlib.util.spec_from_file_location('raid_intake_under_test', SRC)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


NOW = 1_762_600_000_000            # 毫秒
GOOD = {'raidId': 4242, 'attacker': 'GEACjjPJERy', 'defender': 'HFBDkkQKFSz', 'seed': 123456789, 'stake': 50,
        'isRevenge': False, 'expireAt': NOW + 6 * 3600 * 1000}


class Rpc:
    """假 rpc: 记下每次调用; reply 是回包(可调用 ⇒ 按参数算)。"""

    def __init__(self, reply=None, raises=None):
        self.calls = []
        self.reply = {'ok': True, 'jobId': '17'} if reply is None else reply
        self.raises = raises

    def call(self, fn, body, timeout=None):
        self.calls.append((fn, dict(body), timeout))
        if self.raises is not None:
            raise self.raises
        return self.reply(body) if callable(self.reply) else self.reply


def rpc_t(r):
    def f(fn, body, timeout=20.0):
        return r.call(fn, body, timeout)
    return f


def rpc_no_t(r):
    def f(fn, body):
        return r.call(fn, body, None)
    return f


def with_(**kw):
    b = dict(GOOD)
    for k, v in kw.items():
        if v is KeyError:
            b.pop(k, None)
        else:
            b[k] = v
    return b


def main():
    m = load()
    print('── ① 正常请求体 ──')
    r = Rpc()
    out = m.handle_create(dict(GOOD), rpc_t(r), now_ms=NOW)
    ok('① 回 {ok:true, jobId:"17"}', out == {'ok': True, 'jobId': '17'}, str(out))
    ok('① 只调一次 rpc/raid_create', len(r.calls) == 1 and r.calls[0][0] == 'raid_create', str(r.calls))
    want = {'p_raid_id': 4242, 'p_attacker': 'GEACjjPJERy', 'p_defender': 'HFBDkkQKFSz', 'p_seed': 123456789,
            'p_stake': 50, 'p_is_revenge': False, 'p_expire_at': NOW + 6 * 3600 * 1000}
    ok('① ★形参 = 主站七个键逐个对上(值原样)', r.calls and r.calls[0][1] == want, str(r.calls[0][1] if r.calls else None))

    print('── ② 参数不对 ⇒ ok:false 且不调数据库 ──')
    bad = [
        ('不是对象', ['raidId', 1], 'bad_body'),
        ('缺 raidId', with_(raidId=KeyError), 'bad_raidId'),
        ('raidId = 0', with_(raidId=0), 'bad_raidId'),
        ('raidId 负数', with_(raidId=-3), 'bad_raidId'),
        ('raidId 是字符串', with_(raidId='4242'), 'bad_raidId'),
        ('raidId 是 true(bool 冒充 1)', with_(raidId=True), 'bad_raidId'),
        ('raidId 是小数', with_(raidId=4242.5), 'bad_raidId'),
        ('raidId 超 int64', with_(raidId=2 ** 63), 'bad_raidId'),
        ('攻方纯数字(内部 ID)', with_(attacker='123456'), 'bad_userId'),
        ('守方带空格', with_(defender='HFB Dkk'), 'bad_userId'),
        ('守方空串', with_(defender=''), 'bad_userId'),
        ('攻方超 64 字', with_(attacker='a' * 65), 'bad_userId'),
        ('缺攻方', with_(attacker=KeyError), 'bad_userId'),
        ('★攻守同一人', with_(defender='GEACjjPJERy'), 'same_user'),
        ('缺 seed', with_(seed=KeyError), 'bad_seed'),
        ('seed 负数', with_(seed=-1), 'bad_seed'),
        ('stake 负数', with_(stake=-5), 'bad_stake'),
        ('stake 字符串', with_(stake='50'), 'bad_stake'),
        ('isRevenge 不是 bool', with_(isRevenge=0), 'bad_isRevenge'),
        ('缺 expireAt', with_(expireAt=KeyError), 'bad_expireAt'),
        ('expireAt 字符串', with_(expireAt=str(NOW + 1000)), 'bad_expireAt'),
        ('★expireAt 已过', with_(expireAt=NOW - 1), 'expired'),
        ('★expireAt = 现在(也算过)', with_(expireAt=NOW), 'expired'),
    ]
    for name, body, code in bad:
        r = Rpc()
        out = m.handle_create(body, rpc_t(r), now_ms=NOW)
        ok('② %s ⇒ %s、没调数据库' % (name, code), out == {'ok': False, 'error': code} and not r.calls,
           '%s / 调了 %d 次' % (out, len(r.calls)))
    ok('② 分母: 坏请求体 %d 种, 覆盖全部 %d 个本层错误码' % (len(bad), len({c for _, _, c in bad})), len({c for _, _, c in bad}) == 9)

    print('── ③ 缺省值 ──')
    r = Rpc()
    out = m.handle_create(with_(stake=KeyError, isRevenge=KeyError), rpc_t(r), now_ms=NOW)
    ok('③ 缺 stake / isRevenge ⇒ 0 / false 照建', out['ok'] and r.calls and r.calls[0][1]['p_stake'] == 0
       and r.calls[0][1]['p_is_revenge'] is False, str(r.calls[0][1] if r.calls else None))
    r = Rpc()
    m.handle_create(with_(isRevenge=True), rpc_t(r), now_ms=NOW)
    ok('③ isRevenge = true 照建(只记录)', r.calls and r.calls[0][1]['p_is_revenge'] is True)

    print('── ④ 数据库回 ok:false ──')
    for code in ('raid_off', 'no_referee', 'raid_conflict', 'bad_userId'):
        out = m.handle_create(dict(GOOD), rpc_t(Rpc(reply={'ok': False, 'error': code})), now_ms=NOW)
        ok('④ 数据库 %s ⇒ 原样透传' % code, out == {'ok': False, 'error': code}, str(out))
    out = m.handle_create(dict(GOOD), rpc_t(Rpc(reply={'ok': False, 'error': 'x y<script>'})), now_ms=NOW)
    ok('④ 怪错误码 ⇒ rejected(不把数据库原文回给主站)', out == {'ok': False, 'error': 'rejected'}, str(out))
    out = m.handle_create(dict(GOOD), rpc_t(Rpc(reply={'ok': False})), now_ms=NOW)
    ok('④ ok:false 没带错误码 ⇒ rejected', out == {'ok': False, 'error': 'rejected'}, str(out))

    print('── ⑤ 数据库不可用 ⇒ busy ──')
    cases = [
        ('连不上(OSError)', Rpc(raises=OSError('connection refused'))),
        ('超时(TimeoutError)', Rpc(raises=TimeoutError('timed out'))),
        ('任意异常', Rpc(raises=RuntimeError('500'))),
        ('回包是 null', Rpc(reply=lambda b: None)),
        ('回包是数组', Rpc(reply=[{'ok': True, 'jobId': '1'}])),
        ('ok 但没有 jobId', Rpc(reply={'ok': True})),
        ('ok 但 jobId 空串', Rpc(reply={'ok': True, 'jobId': ''})),
        ('ok 是字符串 "true"', Rpc(reply={'ok': 'true', 'jobId': '1'})),
    ]
    for name, r in cases:
        try:
            out = m.handle_create(dict(GOOD), rpc_t(r), now_ms=NOW)
            raised = ''
        except Exception as ex:         # noqa: BLE001
            out, raised = None, repr(ex)
        want_out = {'ok': False, 'error': 'busy'} if name != 'ok 是字符串 "true"' else {'ok': False, 'error': 'rejected'}
        ok('⑤ %s ⇒ %s、不抛' % (name, want_out['error']), out == want_out and not raised, '%s %s' % (out, raised))

    print('── ⑥ jobId 与幂等 ──')
    out = m.handle_create(dict(GOOD), rpc_t(Rpc(reply={'ok': True, 'jobId': 99})), now_ms=NOW)
    ok('⑥ jobId 是整数 ⇒ 转成字符串', out == {'ok': True, 'jobId': '99'}, str(out))
    seen = {}

    def idem(body):
        seen.setdefault(body['p_raid_id'], str(100 + len(seen)))
        return {'ok': True, 'jobId': seen[body['p_raid_id']]}
    r = Rpc(reply=idem)
    a = m.handle_create(dict(GOOD), rpc_t(r), now_ms=NOW)
    b = m.handle_create(dict(GOOD), rpc_t(r), now_ms=NOW)
    c = m.handle_create(with_(raidId=4243), rpc_t(r), now_ms=NOW)
    ok('⑥ ★同 raidId 重发两次 ⇒ 都原样回数据库的同一个 jobId; 换 raidId ⇒ 新 jobId(本层不缓存、不改写)',
       a == b == {'ok': True, 'jobId': '100'} and c == {'ok': True, 'jobId': '101'} and len(r.calls) == 3, '%s %s %s' % (a, b, c))

    print('── ⑦ 超时参数 ──')
    r = Rpc()
    m.handle_create(dict(GOOD), rpc_t(r), now_ms=NOW)
    ok('⑦ rpc 收 timeout ⇒ 传 %.1f 秒(< 主站 10 秒)' % (r.calls[0][2] or -1),
       r.calls and r.calls[0][2] is not None and 0 < r.calls[0][2] < 10, str(r.calls))
    r = Rpc()
    out = m.handle_create(dict(GOOD), rpc_no_t(r), now_ms=NOW)
    ok('⑦ rpc 不收 timeout(网关自测桩) ⇒ 照样能调', out['ok'] and len(r.calls) == 1, str(out))
    out = m.handle_create(dict(GOOD), rpc_t(Rpc()))
    ok('⑦ 不给 now_ms ⇒ 用真时间(expireAt 是 2025 年的 ⇒ expired)', out == {'ok': False, 'error': 'expired'}, str(out))

    print('── ⑧ 与迁移 20261109c 对账 ──')
    sql = open(MIG, encoding='utf-8').read().replace('\r\n', '\n')
    mm = re.search(r'create or replace function public\.raid_create\(([^)]*)\)', sql)
    params = [p.strip().split()[0] for p in mm.group(1).split(',')] if mm else []
    ok('⑧ ★raid_create 形参 = ARG_MAP 右列(顺序也同)', params == [p for _, p in m.ARG_MAP], '%s / %s' % (params, [p for _, p in m.ARG_MAP]))
    ok('⑧ 只给 service_role', 'grant execute on function public.raid_create(bigint, text, text, bigint, bigint, boolean, bigint) to service_role;' in sql
       and 'raid_create(bigint, text, text, bigint, bigint, boolean, bigint) to authenticated' not in sql)
    body = sql[sql.find('function public.raid_create('):]
    body = body[:body.find('end $$;')]
    for code in ('bad_raidId', 'bad_userId', 'same_user', 'expired', 'raid_off', 'no_referee', 'raid_conflict'):
        ok("⑧ 数据库也回 '%s'" % code, ("'error', '%s'" % code) in body)
    ok('⑧ 用户 ID 判据同一条(纯数字拒)', '^[A-Za-z0-9_-]{1,64}$' in sql and m._USER_RE.pattern == '^[A-Za-z0-9_-]{1,64}$')

    print('ALL OK (%d 条)' % n[0] if fails[0] == 0 and n[0] >= 50 else 'FAIL %d / %d' % (fails[0], n[0]))
    return 0 if fails[0] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
