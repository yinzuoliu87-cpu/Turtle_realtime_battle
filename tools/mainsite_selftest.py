# -*- coding: utf-8 -*-
"""mainsite_selftest —— 龟投（主站）对接服务器侧的自证门禁（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.1 / §4.8 / §6）。

不连库、不连主站、不起 Godot。真的部分：签名模块 server/referee/mainsite_sign.py、网关 mainsite_gateway.py（真 HTTP 服务）、
发件箱 referee_poller.py 的 outbox_send / outbox_pass / outbox_loop、假主站 tools/mock_mainsite.py（真 HTTP 服务）。
假的部分只有数据库：FakeDB 照迁移 20261109a 各函数的回包形状写的内存版 ——
★数据库函数本身的语义（5 分钟过期、一次性、领活顺序、settle 等 started、删号写 unlinked）由
  server/supabase/tests/20261109a_mainsite_core_check.sql 在真 PG16（PGlite 沙盒）里守；这里守的是「网关 / 发件箱用对了它们」。

断言：
  A 签名 = 主站 Go 代码逐字节：三条已知签名向量 + 20 种验签输入的放行 / 拒绝（Go 原函数跑出来的，见 VERIFY_GO）
  B 假主站（照 arena_service.go）：缺签名 / 签名错 / 时间戳过期 / 改了请求体 ⇒ 401；Content-Type 不对 ⇒ 415；
    started 回新 expireAt（现在 + 30 分钟）；settle 同结果幂等、结果不同 ⇒ ok:false；pet-level 没拥有 ⇒ ok:false
  C 网关（主站 → 我们）：过期 / 签名错 / 改字段 三种被拒（401，且库一次没碰）；重放同一请求回同一结果；
    登录码格式（32 位 [A-Za-z0-9_-]）与确认页地址；码不对格式不进库；5 分钟过期 / 一次性在网关回包里如实体现；
    已绑在别的号上 ⇒ switched:true + 那个号的 session；偷袭建任务转给 raid_intake.handle_create（没部署 503 / 抛异常 500）；
    App 没令牌 401；拥有龟刷新：调主站 /player 写库、主站挂了回缓存 + stale
  D 发件箱：ok:false 不重试（终态、主站只收到一次）；5xx / 401 / 断连 ⇒ 退避重试、下一次成功；
    settle 等 started（started 先 500，settle 一直到 started 成功之后才发）；started 回包（新 expireAt）整个存进 reply；
    开关默认关；缺地址 / 密钥不启动；领活 404 ⇒ 本进程不再领
进 run-tests.sh 门禁（成功打印 ALL OK）。
"""
import importlib.util
import io
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'server', 'referee'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
for _k in ('MAINSITE_OUTBOX', 'MAINSITE_BASE', 'MAINSITE_HOOK_SECRET', 'MAINSITE_HOOK_SECRET_FILE'):
    os.environ.pop(_k, None)


def _load(name, rel):
    """server/referee/ 下的模块按文件载入并登记进 sys.modules（网关内部的 import 拿到的是同一个对象，打桩才对它生效）。"""
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, 'server', 'referee', rel))
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


MS = _load('mainsite_sign', 'mainsite_sign.py')
RP = _load('referee_poller', 'referee_poller.py')
GW = _load('mainsite_gateway', 'mainsite_gateway.py')
import mock_mainsite as MOCK  # noqa: E402

fails = [0]
n = [0]
LOGS = []
RP.log = lambda m: LOGS.append(m)          # 网关 / 发件箱的日志收起来，门禁输出只留断言
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
SECRET = 'selftest-hook-secret-不进仓库的是真密钥'
CODE_RE = re.compile(r'^[A-Za-z0-9_-]{4,64}$')


def ok(name, cond, detail=''):
    n[0] += 1
    detail = '' if detail is None else str(detail)
    if cond:
        print('  [PASS] ' + name + (('   ' + detail) if detail else ''))
    else:
        fails[0] += 1
        print('  [FAIL] ' + name + '   ' + detail)


# ── A 的已知向量：C:/…/govec/main.go 里逐字拷贝 Go 的 ArenaSign / ArenaVerify 跑出来的（2026-11-09，go1.27.3）──
SIGN_GO = [
    ('s3cret', 1800000000, b'{"raidId":1}', '451ef45bb6e329dcab87a6461e60dab38e0958ecf161bf44d31acd11e7fbc911'),
    ('s3cret', 1800000000, None, '59d2b4f98fa9c15a86f3ed3a009e2c131309e4acd7db53cdcb31ed60982d3078'),
    ('密钥-k', 1700000123, '{"code":"abc_DEF-1","user_id":"GEACjjPJERy","n":"龟"}'.encode('utf-8'),
     '25010e5f89b5b9b3c4e393f658c0bee779e918a18be0e194c096ff552813b81f'),
]
_G = SIGN_GO[0][3]
#            名字              secret        ts 头              签名头             请求体            now         Go 结果
VERIFY_GO = [
    ('ok',              's3cret',     '1800000000',      _G,                 '{"raidId":1}', 1800000000, True),
    ('plus_sign_ts',    's3cret',     '+1800000000',     _G,                 '{"raidId":1}', 1800000000, True),
    ('leading_zero_ts', 's3cret',     '01800000000',     _G,                 '{"raidId":1}', 1800000000, True),
    ('space_ts',        's3cret',     ' 1800000000 ',    _G,                 '{"raidId":1}', 1800000000, True),
    ('underscore_ts',   's3cret',     '1_800_000_000',   _G,                 '{"raidId":1}', 1800000000, False),
    ('upper_sig',       's3cret',     '1800000000',      _G.upper(),         '{"raidId":1}', 1800000000, True),
    ('space_sig',       's3cret',     '1800000000',      ' ' + _G + '\t',    '{"raidId":1}', 1800000000, True),
    ('secret_space',    ' s3cret\n',  '1800000000',      _G,                 '{"raidId":1}', 1800000000, True),
    ('skew_300',        's3cret',     '1800000000',      _G,                 '{"raidId":1}', 1800000300, True),
    ('skew_301',        's3cret',     '1800000000',      _G,                 '{"raidId":1}', 1800000301, False),
    ('skew_neg_300',    's3cret',     '1800000000',      _G,                 '{"raidId":1}', 1799999700, True),
    ('skew_neg_301',    's3cret',     '1800000000',      _G,                 '{"raidId":1}', 1799999699, False),
    ('body_changed',    's3cret',     '1800000000',      _G,                 '{"raidId":2}', 1800000000, False),
    ('wrong_secret',    'other',      '1800000000',      _G,                 '{"raidId":1}', 1800000000, False),
    ('empty_secret',    '  ',         '1800000000',      _G,                 '{"raidId":1}', 1800000000, False),
    ('empty_ts',        's3cret',     '',                _G,                 '{"raidId":1}', 1800000000, False),
    ('float_ts',        's3cret',     '1800000000.0',    _G,                 '{"raidId":1}', 1800000000, False),
    ('overflow_ts',     's3cret',     '99999999999999999999', _G,            '{"raidId":1}', 1800000000, False),
    ('short_sig',       's3cret',     '1800000000',      _G[:63],            '{"raidId":1}', 1800000000, False),
    ('empty_sig',       's3cret',     '1800000000',      '',                 '{"raidId":1}', 1800000000, False),
]


# ─────────────────────────────── FakeDB：迁移 20261109a 各函数的内存版 ───────────────────────────────
class FakeDB:
    def __init__(self):
        self.t = 1_800_000_000.0
        self.calls = []
        self.codes = {}
        self.links = {}          # account → userId
        self.pets = {}           # account → set(pet_key)
        self.outbox = []
        self.claim_404 = False

    def names(self, fn):
        return [c for c in self.calls if c[0] == fn]

    def rpc(self, fn, body, timeout=20.0):
        self.calls.append((fn, json.loads(json.dumps(body))))     # 和真 PostgREST 一样过一遍 JSON
        if fn == 'mainsite_outbox_claim' and self.claim_404:
            raise urllib.error.HTTPError('http://x/rpc/' + fn, 404, 'Not Found', None, None)
        return json.loads(json.dumps(getattr(self, fn)(**body)))

    # ── 登录码 ──
    def mainsite_link_start(self, p_account, p_code, p_device):
        if not CODE_RE.match(p_code or ''):
            return {'ok': False, 'error': 'bad_code'}
        if p_code in self.codes:
            return {'ok': False, 'error': 'code_taken'}
        for c in self.codes.values():
            if c['account'] == p_account and c['confirmed'] is None and c['expires'] > self.t:
                c['expires'] = self.t
        self.codes[p_code] = {'account': p_account, 'device': (p_device or '').strip()[:128], 'expires': self.t + 300,
                              'user': None, 'confirmed': None, 'result': None, 'target': None}
        return {'ok': True, 'code': p_code, 'expires_in': 300}

    def mainsite_link_info(self, p_code):
        c = self.codes.get(p_code)
        if not c or c['confirmed'] is not None or c['expires'] <= self.t:
            return {'ok': False, 'error': 'bad_code'}
        return {'ok': True, 'device': c['device']}

    def mainsite_link_confirm(self, p_code, p_user_id):
        if not MOCK.user_id_ok(p_user_id):
            return {'ok': False, 'error': 'bad userId'}
        c = self.codes.get(p_code)
        if not c:
            return {'ok': False, 'error': 'bad_code'}
        if c['confirmed'] is not None:
            return {'ok': True, 'result': c['result'], 'account': c['target']} if c['user'] == p_user_id else {'ok': False, 'error': 'code_used'}
        if c['expires'] <= self.t:
            return {'ok': False, 'error': 'expired'}
        tgt = next((a for a, u in self.links.items() if u == p_user_id), None)
        if tgt == c['account']:
            res = 'same'
        elif tgt is not None:
            res = 'switched'
        else:
            res = 'rebound' if c['account'] in self.links else 'bound'
            self.links[c['account']] = p_user_id
            tgt = c['account']
        c.update(confirmed=self.t, user=p_user_id, result=res, target=tgt)
        return {'ok': True, 'result': res, 'account': tgt}

    def raid_defense_report(self, p_uid, p_force=False):
        return {'ok': True}

    def mainsite_link_poll(self, p_account, p_code):
        c = self.codes.get(p_code)
        if not c or c['account'] != p_account:
            return {'ok': False, 'error': 'bad_code'}
        if c['confirmed'] is None:
            return {'ok': True, 'status': 'expired' if c['expires'] <= self.t else 'pending', 'switched': False}
        if c['confirmed'] <= self.t - 300:
            return {'ok': True, 'status': 'expired', 'switched': False}
        out = {'ok': True, 'status': 'confirmed', 'switched': c['result'] == 'switched', 'result': c['result'],
               'user_id': c['user']}
        if c['result'] == 'switched':
            out['target_account'] = c['target']
        return out

    # ── 拥有龟 ──
    def mainsite_status(self, p_account):
        if p_account not in self.links:
            return {'ok': True, 'linked': False, 'user_id': None, 'owned': [], 'fetched_at': None}
        return {'ok': True, 'linked': True, 'user_id': self.links[p_account],
                'owned': sorted(self.pets.get(p_account, ())), 'fetched_at': None}

    def mainsite_pets_put(self, p_account, p_user_id, p_keys):
        if p_account not in self.links:
            return {'ok': False, 'error': 'not_linked'}
        if self.links[p_account] != p_user_id:
            return {'ok': False, 'error': 'relinked'}
        self.pets[p_account] = {k for k in p_keys if re.match(r'^[a-z0-9_]{1,32}$', k)}
        return self.mainsite_status(p_account)

    # ── 发件箱 ──
    def add(self, topic, key, body):
        self.outbox.append({'id': len(self.outbox) + 1, 'topic': topic, 'idem_key': key, 'body': body, 'attempts': 0,
                            'next_at': self.t, 'done_at': None, 'last_status': None, 'reply': None})

    @staticmethod
    def lane(r):
        b = r['body']
        return ('raid:%s' % b.get('raidId')) if r['topic'] in ('started', 'settle') else ('user:%s' % b.get('userId'))

    def row(self, key):
        return next(r for r in self.outbox if r['idem_key'] == key)

    def mainsite_outbox_claim(self, p_limit=20, p_lease_sec=120):
        open_ = [r for r in self.outbox if r['done_at'] is None]
        out = []
        for r in sorted(open_, key=lambda x: x['id']):
            if r['next_at'] > self.t:
                continue
            if any(e['id'] < r['id'] and self.lane(e) == self.lane(r) and not (r['topic'] == 'started' and e['topic'] == 'settle')
                   for e in open_):
                continue
            if r['topic'] == 'settle' and any(s['topic'] == 'started' and s['body'].get('raidId') == r['body'].get('raidId')
                                              for s in open_):
                continue
            out.append(r)
            if len(out) >= p_limit:
                break
        for r in out:
            r['next_at'] = self.t + max(10, p_lease_sec)
        return [{'id': r['id'], 'topic': r['topic'], 'idem_key': r['idem_key'], 'body': r['body'],
                 'attempts': r['attempts']} for r in out]

    def mainsite_outbox_mark(self, p_id, p_status, p_reply, p_retry_sec):
        r = next((x for x in self.outbox if x['id'] == p_id and x['done_at'] is None), None)
        if r is None:
            return {'ok': False, 'done': p_retry_sec is None}
        r['attempts'] += 1
        r['last_status'] = p_status
        if p_reply is not None:
            r['reply'] = p_reply
        if p_retry_sec is None:
            r['done_at'] = self.t
        else:
            r['next_at'] = self.t + p_retry_sec
        return {'ok': True, 'done': p_retry_sec is None}


class FakeAuth:
    def __init__(self, tokens):
        self.tokens = tokens
        self.issued = []
        self.fail = False

    def account_of(self, token):
        return self.tokens.get(token)

    def issue_session(self, account):
        if self.fail:
            raise GW.Upstream('auth down')
        self.issued.append(account)
        return {'access_token': 'at-' + account, 'refresh_token': 'rt-' + account}


def raw(method, url, body=None, headers=None):
    """返回 (HTTP 状态, 解析后的回包)。"""
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with OP.open(req, timeout=10) as r:
            return r.status, json.loads(r.read().decode('utf-8') or 'null')
    except urllib.error.HTTPError as e:
        t = e.read().decode('utf-8')
        try:
            return e.code, json.loads(t)
        except ValueError:
            return e.code, t


def signed(secret, body, ts=None, ctype=True):
    h = MS.headers(secret, body, now=ts)
    if ctype:
        h['Content-Type'] = 'application/json'
    return h


def app(gw_base, path, token, body=None):
    h = {'Content-Type': 'application/json'}
    if token:
        h['Authorization'] = 'Bearer ' + token
    return raw('POST', gw_base + path, json.dumps(body or {}).encode('utf-8'), h)


ACC_A = '11111111-1111-4111-8111-111111111111'
ACC_B = '22222222-2222-4222-8222-222222222222'
UID = 'GEACjjPJERy'


def part_a():
    print('=== A 签名 = 主站 Go 代码 ===')
    for i, (sec, ts, body, want) in enumerate(SIGN_GO):
        got = MS.sign(sec, ts, body)
        ok('A%d 已知签名向量%s' % (i + 1, '（GET 空体签 ts + "."）' if body is None else ''), got == want, got)
    bad = [c[0] for c in VERIFY_GO if MS.verify(c[1], c[2], c[3], c[4].encode(), now=c[5]) != c[6]]
    ok('A4 验签 %d 种输入的放行 / 拒绝与 Go 完全相同' % len(VERIFY_GO), not bad and len(VERIFY_GO) == 20, '不同: %s' % bad)
    h = MS.headers('k', b'x', now=1800000001)
    ok('A5 headers(): 时间戳是十进制秒、签名 = sign()', h == {MS.HDR_TS: '1800000001', MS.HDR_SIG: MS.sign('k', 1800000001, b'x')})
    env = {'MAINSITE_HOOK_SECRET': '', 'MAINSITE_HOOK_SECRET_FILE': os.path.join(ROOT, 'no-such-file')}
    ok('A6 没配密钥 ⇒ load_secret() 空（调用方据此不启用）', MS.load_secret(env) == '')


def part_b():
    print('=== B 假主站（照 arena_service.go）===')
    db = FakeDB()
    st = MOCK.State(clock_ms=lambda: int(db.t * 1000))
    st.add_user(UID, ['basic', 'stone'], linked=True)
    srv, base = MOCK.start(SECRET, st)
    try:
        url = base + '/api/arena-hook/'
        body = b'{"userId":"GEACjjPJERy"}'
        c, r = raw('POST', url + 'player', body, signed(SECRET, body))
        ok('B1 签名对 ⇒ 200 + 拥有的龟', c == 200 and r == {'ok': True, 'userId': UID, 'turtles': ['basic', 'stone']}, '%s %s' % (c, r))
        c, r = raw('POST', url + 'player', body, {'Content-Type': 'application/json'})
        ok('B2 不带签名 ⇒ 401 bad arena signature', c == 401 and r == {'ok': False, 'error': 'bad arena signature'}, '%s %s' % (c, r))
        c, r = raw('POST', url + 'player', body, signed('wrong-secret', body))
        ok('B2 签名错（别的密钥）⇒ 401', c == 401, str(c))
        c, r = raw('POST', url + 'player', body, signed(SECRET, body, ts=int(time.time()) - 301))
        ok('B2 时间戳过期（301 秒前）⇒ 401', c == 401, str(c))
        c, _ = raw('POST', url + 'player', body, signed(SECRET, body, ts=int(time.time()) - 290))
        ok('B2 对照: 290 秒前仍放行', c == 200, str(c))
        c, r = raw('POST', url + 'player', b'{"userId":"HxyzOtherU1"}', signed(SECRET, body))
        ok('B2 改了请求体（签的是另一份）⇒ 401', c == 401, str(c))
        c, r = raw('POST', url + 'player', body, signed(SECRET, body, ctype=False))
        ok('B2 Content-Type 不是 json ⇒ 415', c == 415, str(c))
        st.add_raid(101)
        sb = b'{"raidId":101}'
        c, r = raw('POST', url + 'started', sb, signed(SECRET, sb))
        ok('B3 started ⇒ ok + 新 expireAt = 现在 + 30 分钟', c == 200 and r == {'ok': True, 'expireAt': int(db.t * 1000) + 30 * 60000}, str(r))
        db.t += 60
        c, r2 = raw('POST', url + 'started', sb, signed(SECRET, sb))
        ok('B3 started 再来一次 ⇒ ok、expireAt 不变', r2 == r, str(r2))
        se = b'{"raidId":101,"result":"attacker","matchId":"m-101"}'
        c, r = raw('POST', url + 'settle', se, signed(SECRET, se))
        ok('B4 settle attacker ⇒ ok / settled', r == {'ok': True, 'status': 'settled', 'result': 'attacker'}, str(r))
        c, r = raw('POST', url + 'settle', se, signed(SECRET, se))
        ok('B4 同一场同结果再发 ⇒ ok（幂等）', r == {'ok': True, 'status': 'settled', 'result': 'attacker'}, str(r))
        sd = b'{"raidId":101,"result":"defender","matchId":"m-101"}'
        c, r = raw('POST', url + 'settle', sd, signed(SECRET, sd))
        ok('B4 结果不同 ⇒ HTTP 200 + ok:false', c == 200 and r.get('ok') is False and 'already settled' in r.get('error', ''), str(r))
        st.add_raid(102, queue_min=1)
        db.t += 120
        sv = b'{"raidId":102,"result":"void","matchId":""}'
        c, r = raw('POST', url + 'settle', sv, signed(SECRET, sv))
        ok('B5 过了 expireAt ⇒ ok:false expired', r == {'ok': False, 'error': 'raid 102 expired'}, str(r))
        pl = b'{"userId":"GEACjjPJERy","petKey":"lava","level":3}'
        c, r = raw('POST', url + 'pet-level', pl, signed(SECRET, pl))
        ok('B6 pet-level 没拥有 ⇒ ok:false pet not owned', r == {'ok': False, 'error': 'pet not owned'}, str(r))
        pb = b'{"userId":"12345678","petKey":"basic","level":3}'
        c, r = raw('POST', url + 'pet-level', pb, signed(SECRET, pb))
        ok('B6 纯数字 userId ⇒ bad userId', r == {'ok': False, 'error': 'bad userId'}, str(r))
    finally:
        srv.shutdown()


def part_c():
    print('=== C 网关 ===')
    db = FakeDB()
    st = MOCK.State(clock_ms=lambda: int(db.t * 1000))
    st.add_user(UID, ['basic', 'stone'], linked=True)
    msrv, mbase = MOCK.start(SECRET, st)
    auth = FakeAuth({'tok-A': ACC_A, 'tok-B': ACC_B})
    raid_calls = []

    def raid_stub(body, rpc):
        raid_calls.append((body, rpc))
        return {'ok': True, 'jobId': 'job-%s' % body.get('raidId')}

    gw = GW.Gateway(SECRET, mbase, link_base='https://turtlepoll.example', rpc=db.rpc, auth=auth, raid_handler=raid_stub)
    gsrv = GW.serve(gw, port=0, quiet=True)
    threading.Thread(target=gsrv.serve_forever, daemon=True).start()
    g = 'http://127.0.0.1:%d' % gsrv.server_address[1]
    try:
        c, r = raw('GET', g + '/healthz')
        ok('C0 /healthz', c == 200 and r == {'ok': True})
        # ── 登录码 ──
        c, r = app(g, '/app/link/start', 'tok-A', {'device': 'iPhone 15'})
        code = (r or {}).get('code', '')
        ok('C1 登录码: 32 位、只有 [A-Za-z0-9_-]、5 分钟', c == 200 and r.get('ok') is True and len(code) == 32
           and CODE_RE.match(code) is not None and r.get('expires_in') == 300, str(r))
        ok('C1 确认页地址 = 主站/game/link?code=<码>', r.get('url') == 'https://turtlepoll.example/game/link?code=' + code, r.get('url'))
        c2, r2 = app(g, '/app/link/start', 'tok-A', {'device': 'iPhone 15'})
        ok('C1 每次都是新的随机码', r2.get('code') and r2['code'] != code)
        code = r2['code']
        c, r = MOCK.link_info(g, SECRET, code)
        ok('C2 主站查设备型号（GET，签 ts + "."）⇒ {ok:true, device}', c == 200 and r == {'ok': True, 'device': 'iPhone 15'}, '%s %s' % (c, r))
        n_info = len(db.names('mainsite_link_info'))
        c, r = MOCK.link_info(g, SECRET, code, ts=int(time.time()) - 301)
        ok('C3 ★时间戳过期 ⇒ 401', c == 401 and r == {'ok': False, 'error': 'bad arena signature'}, '%s %s' % (c, r))
        c, r = MOCK.link_info(g, 'not-the-secret', code)
        ok('C3 ★签名错 ⇒ 401', c == 401, str(c))
        ok('C3 被拒的两次一次都没进库', len(db.names('mainsite_link_info')) == n_info)
        good = MOCK.go_json({'code': code, 'user_id': UID})
        h = signed(SECRET, good)
        evil = MOCK.go_json({'code': code, 'user_id': 'HxyzOtherU1'})
        c, r = raw('POST', g + '/mainsite/link/confirm', evil, h)
        ok('C3 ★改字段（签的是 user_id=A，送的是 B）⇒ 401、库没碰', c == 401 and not db.names('mainsite_link_confirm'), '%s %s' % (c, r))
        c, r = raw('POST', g + '/mainsite/link/confirm', good, h)
        ok('C4 确认 ⇒ {ok:true}', c == 200 and r.get('ok') is True and r.get('result') == 'bound', '%s %s' % (c, r))
        c2, r2 = raw('POST', g + '/mainsite/link/confirm', good, h)
        ok('C4 ★原样重放同一个请求（同时间戳同签名）⇒ 同一个结果、绑定不变', (c2, r2) == (c, r) and db.links == {ACC_A: UID},
           '%s %s' % (c2, r2))
        for _ in range(100):          # 绑定后的两步在后台线程里(回包之后)
            if db.names('raid_defense_report'):
                break
            time.sleep(0.02)
        time.sleep(0.1)
        rep = db.names('raid_defense_report')
        ok('C4b ★新绑定后报防守状态 raid_defense_report(这个号, 非强制 ⇒ 重放不多发)(11-08 A1×A2 接线)',
           len(rep) >= 1 and all(x == ('raid_defense_report', {'p_uid': ACC_A, 'p_force': False}) for x in rep), str(rep))
        ok('C4b 新绑定后先拉过一次拥有的龟(mainsite_status)', len(db.names('mainsite_status')) >= 1, str(db.names('mainsite_status')))
        c, r = MOCK.link_confirm(g, SECRET, code, 'HxyzOtherU1')
        ok('C7 一次性: 用过的码换个主站用户再确认 ⇒ ok:false', c == 200 and r.get('ok') is False, str(r))
        c, r = MOCK.link_info(g, SECRET, code)
        ok('C7 一次性: 确认过的码 info ⇒ ok:false', r == {'ok': False, 'error': 'bad_code'}, str(r))
        c, r = app(g, '/app/link/poll', 'tok-A', {'code': code})
        ok('C5 App 轮询 ⇒ confirmed / switched:false / 不带 session', r == {'ok': True, 'status': 'confirmed', 'switched': False,
                                                                         'result': 'bound'}, str(r))
        c, r = app(g, '/app/link/poll', 'tok-B', {'code': code})
        ok('C5 别的号查这个码 ⇒ bad_code', r == {'ok': False, 'error': 'bad_code'}, str(r))
        # ── 换号 ──
        c, r = app(g, '/app/link/start', 'tok-B', {'device': 'Pixel 8'})
        code_b = r['code']
        c, r = app(g, '/app/link/poll', 'tok-B', {'code': code_b})
        ok('C6 确认之前 ⇒ pending', r == {'ok': True, 'status': 'pending', 'switched': False}, str(r))
        MOCK.link_confirm(g, SECRET, code_b, UID)
        c, r = app(g, '/app/link/poll', 'tok-B', {'code': code_b})
        ok('C6 ★已绑在 A 上 ⇒ switched:true + A 的 session', c == 200 and r.get('switched') is True
           and r.get('session') == {'access_token': 'at-' + ACC_A, 'refresh_token': 'rt-' + ACC_A} and auth.issued == [ACC_A], str(r))
        ok('C6 回 App 的包里没有 target_account / user_id', 'target_account' not in r and 'user_id' not in r)
        auth.fail = True
        c, r = app(g, '/app/link/poll', 'tok-B', {'code': code_b})
        ok('C6 签发失败 ⇒ 503 session_failed（App 再轮询一次）', c == 503 and r == {'ok': False, 'error': 'session_failed'}, '%s %s' % (c, r))
        auth.fail = False
        # ── 过期 ──
        c, r = app(g, '/app/link/start', 'tok-B', {'device': 'Pixel 8'})
        code_x = r['code']
        db.t += 301
        c, r = app(g, '/app/link/poll', 'tok-B', {'code': code_x})
        ok('C7 ★5 分钟没确认 ⇒ expired', r == {'ok': True, 'status': 'expired', 'switched': False}, str(r))
        c, r = MOCK.link_info(g, SECRET, code_x)
        ok('C7 过期的码 info ⇒ ok:false', r.get('ok') is False, str(r))
        c, r = MOCK.link_confirm(g, SECRET, code_x, UID)
        ok('C7 过期的码确认 ⇒ ok:false expired', r == {'ok': False, 'error': 'expired'}, str(r))
        # ── 码格式 ──
        k = len(db.calls)
        c1, r1 = MOCK.link_info(g, SECRET, 'a b')
        c2, r2 = MOCK.link_confirm(g, SECRET, 'x' * 65, UID)
        c3, r3 = app(g, '/app/link/poll', 'tok-A', {'code': 'abc'})
        ok('C8 ★不对格式的码（空格 / 65 位 / 3 位）⇒ bad_code、不进库',
           r1 == r2 == r3 == {'ok': False, 'error': 'bad_code'} and len(db.calls) == k, '%s %s %s' % (r1, r2, r3))
        # ── App 身份 ──
        c, r = app(g, '/app/link/start', None, {})
        c2, r2 = app(g, '/app/link/start', 'tok-nobody', {})
        ok('C9 App 没令牌 / 令牌无效 ⇒ 401', c == 401 and c2 == 401 and r == {'ok': False, 'error': 'not_signed_in'}, '%s %s' % (c, c2))
        # ── 偷袭建任务 ──
        rb = MOCK.raid_body(7001, UID, 'HxyzOtherU1', state=st)
        c, r = MOCK.create_raid(g + '/mainsite/raid', SECRET, rb)
        ok('C10 建任务 ⇒ 转给 raid_intake.handle_create，原样回 {ok, jobId}', c == 200 and r == {'ok': True, 'jobId': 'job-7001'}
           and len(raid_calls) == 1 and raid_calls[0][0] == rb and callable(raid_calls[0][1]), '%s %s' % (c, r))
        body = MOCK.go_json(rb)
        h = signed(SECRET, body)
        c1, r1 = raw('POST', g + '/mainsite/raid', body, h)
        c2, r2 = raw('POST', g + '/mainsite/raid', body, h)
        ok('C10 ★原样重放同一个建任务请求 ⇒ 同一个 jobId', (c1, r1) == (c2, r2) == (200, {'ok': True, 'jobId': 'job-7001'}), '%s %s' % (r1, r2))
        bad = MOCK.go_json(dict(rb, stake=500))
        c, r = raw('POST', g + '/mainsite/raid', bad, h)
        ok('C10 ★改了押注额（签名不变）⇒ 401、没进 handle_create', c == 401 and len(raid_calls) == 3, '%s %d' % (c, len(raid_calls)))
        gw.raid_handler = None
        c, r = MOCK.create_raid(g + '/mainsite/raid', SECRET, rb)
        ok('C10 raid_intake 没部署 ⇒ 503（主站按龟战忙、立刻退押注）', c == 503 and r.get('ok') is False, '%s %s' % (c, r))

        def boom(body, rpc):
            raise RuntimeError('boom')
        gw.raid_handler = boom
        c, r = MOCK.create_raid(g + '/mainsite/raid', SECRET, rb)
        ok('C10 handle_create 抛异常 ⇒ 500 JSON、网关不挂', c == 500 and r == {'ok': False, 'error': 'internal'}, '%s %s' % (c, r))
        gw.raid_handler = lambda body, rpc: 'not a dict'
        c, r = MOCK.create_raid(g + '/mainsite/raid', SECRET, rb)
        ok('C10 handle_create 回的不是 {ok…} ⇒ 500', c == 500, str(c))
        c, r = raw('GET', g + '/healthz')
        ok('C10 之后网关照常', c == 200)
        # ── 拥有龟 ──
        c, r = app(g, '/app/pets/refresh', 'tok-A')
        ok('C11 已绑 ⇒ 调主站 /player、写库、回拥有的龟', r == {'ok': True, 'linked': True, 'owned': ['basic', 'stone']}
           and db.pets.get(ACC_A) == {'basic', 'stone'} and st.topics().count('player') == 1, str(r))
        c, r = app(g, '/app/pets/refresh', 'tok-A')
        ok('C11 10 秒内再刷 ⇒ 不再调主站、回库里的', r == {'ok': True, 'linked': True, 'owned': ['basic', 'stone']}
           and st.topics().count('player') == 1, str(r))
        gw.now = lambda: time.time() + 11
        st.inject('player', 'http500')
        st.add_user(UID, ['basic', 'stone', 'lava'], linked=True)
        c, r = app(g, '/app/pets/refresh', 'tok-A')
        ok('C11 ★主站 500 ⇒ 回上次缓存 + stale:true', r == {'ok': True, 'linked': True, 'owned': ['basic', 'stone'], 'stale': True}, str(r))
        gw.now = lambda: time.time() + 22
        c, r = app(g, '/app/pets/refresh', 'tok-A')
        ok('C11 主站恢复 ⇒ 新得的龟进来', r == {'ok': True, 'linked': True, 'owned': ['basic', 'lava', 'stone']}, str(r))
        c, r = app(g, '/app/pets/refresh', 'tok-B')
        ok('C11 没绑 ⇒ linked:false、不调主站', r == {'ok': True, 'linked': False, 'owned': []}
           and st.topics().count('player') == 3, str(r))
        gw.now = time.time
        # ── 杂项 ──
        c, r = raw('GET', g + '/mainsite/link/confirm')
        c2, r2 = raw('GET', g + '/nope')
        ok('C12 方法不对 405 / 路径不对 404', c == 405 and c2 == 404, '%s %s' % (c, c2))
        gw.secret = ''
        c, r = MOCK.link_info(g, SECRET, code)
        ok('C12 网关没配密钥 ⇒ 主站来的一律 401（不会空密钥放行）', c == 401, str(c))
        gw.secret = SECRET
    finally:
        gsrv.shutdown()
        msrv.shutdown()


def part_d():
    print('=== D 发件箱 ===')
    ok('D0 开关默认关（MAINSITE_OUTBOX 没设）', RP.outbox_enabled() is False)
    os.environ['MAINSITE_OUTBOX'] = '1'
    ok('D0 MAINSITE_OUTBOX=1 才开', RP.outbox_enabled() is True)
    os.environ.pop('MAINSITE_OUTBOX')
    db = FakeDB()
    RP.rpc = db.rpc
    ok('D0 缺 MAINSITE_BASE / 密钥 ⇒ 不启动、一次库都不碰', RP.outbox_loop(once=True) == 0 and not db.calls)
    ok('D0 退避: 5, 10, 20 … 封顶 300 秒', [RP.outbox_retry_sec(i) for i in range(8)] == [5, 10, 20, 40, 80, 160, 300, 300]
       and RP.outbox_retry_sec(99) == 300)
    st = MOCK.State(clock_ms=lambda: int(db.t * 1000))
    st.add_user(UID, ['basic', 'stone'], linked=True)
    st.add_raid(201)
    st.add_raid(202)
    srv, base = MOCK.start(SECRET, st)
    os.environ['MAINSITE_BASE'] = base
    os.environ['MAINSITE_HOOK_SECRET'] = SECRET
    try:
        db.add('started', 'st:201', {'raidId': 201})
        db.add('settle', 'se:201', {'raidId': 201, 'result': 'attacker', 'matchId': 'm-201'})
        db.add('pet-level', 'pl:basic', {'userId': UID, 'petKey': 'basic', 'level': 3})
        db.add('defense', 'def:1', {'userId': UID, 'hasDefense': True, 'rating': 4, 'device': 'iPhone 15'})
        db.add('settle', 'se:202', {'raidId': 202, 'result': 'void', 'matchId': ''})
        db.add('pet-level', 'pl:lava', {'userId': UID, 'petKey': 'lava', 'level': 2})
        st.inject('started', 'http500')
        st.inject('defense', 'http401')
        st.inject('settle', 'drop')
        sent1 = RP.outbox_loop(once=True)
        r_st, r_pl, r_se2 = db.row('st:201'), db.row('pl:basic'), db.row('se:202')
        ok('D1 第一批 3 条: started 201 / pet-level basic / settle 202（settle 201 等 started、defense 等 pet-level）',
           sent1 == 3 and [c[0] for c in st.calls] == ['started', 'pet-level', 'settle'], '%d %s' % (sent1, [c[0] for c in st.calls]))
        ok('D2 ★5xx ⇒ 重试（没完成、5 秒后、last_status=http_500）',
           r_st['done_at'] is None and r_st['next_at'] == db.t + 5 and r_st['last_status'] == 'http_500', str(r_st))
        ok('D2 ★对面断连 ⇒ 重试', r_se2['done_at'] is None and r_se2['last_status'].startswith('conn'), str(r_se2['last_status']))
        ok('D1 成功 ⇒ 终态 ok', r_pl['done_at'] is not None and r_pl['last_status'] == 'ok')
        RP.outbox_loop(once=True)
        r_def = db.row('def:1')
        ok('D2 ★401 ⇒ 重试（pet-level 完成后 defense 当轮就发、被 401）',
           r_def['done_at'] is None and r_def['last_status'] == 'http_401' and r_def['attempts'] == 1, str(r_def))
        ok('D3 ★started 还没成功 ⇒ settle 201 一次都没发', not [c for c in st.calls if c[0] == 'settle' and (c[1] or {}).get('raidId') == 201])
        db.t += 6
        RP.outbox_loop(once=True)
        ok('D2 到点重发: started 成功 / settle 202 成功 / defense 成功',
           db.row('st:201')['last_status'] == 'ok' and db.row('se:202')['last_status'] == 'ok' and db.row('def:1')['last_status'] == 'ok',
           str([db.row(k)['last_status'] for k in ('st:201', 'se:202', 'def:1')]))
        ok('D4 ★started 的回包整个存进 reply（新 expireAt = 开算时刻 + 30 分钟）',
           db.row('st:201')['reply'] == {'ok': True, 'expireAt': int(db.t * 1000) + 30 * 60000}, str(db.row('st:201')['reply']))
        RP.outbox_loop(once=True)
        idx_ok_started = max(i for i, c in enumerate(st.calls) if c[0] == 'started' and c[2] == 200)
        idx_settle = [i for i, c in enumerate(st.calls) if c[0] == 'settle' and (c[1] or {}).get('raidId') == 201]
        ok('D3 ★settle 201 在 started 成功之后才发、只发一次', len(idx_settle) == 1 and idx_settle[0] > idx_ok_started
           and db.row('se:201')['last_status'] == 'ok', str(idx_settle))
        r_lava = db.row('pl:lava')
        ok('D5 ★HTTP 200 + ok:false（pet not owned）⇒ 终态、记下原因', r_lava['done_at'] is not None
           and r_lava['last_status'] == 'ok_false: pet not owned', str(r_lava))
        for _ in range(3):
            db.t += 600
            RP.outbox_loop(once=True)
        ok('D5 ★ok:false 之后半小时三轮都不重发（主站只收到一次）',
           [c[0] for c in st.calls].count('pet-level') == 2 and r_lava['attempts'] == 1, str([c[0] for c in st.calls]))
        ok('D6 分母: 6 条全部终态、主站共收到 9 次（3 次故障 + 6 次成功或 ok:false）',
           all(r['done_at'] is not None for r in db.outbox) and len(st.calls) == 9, str(len(st.calls)))
        db.add('unlinked', 'del:x', {'userId': UID})
        srv.shutdown()
        srv.server_close()          # 关掉监听口 ⇒ 连接立刻被拒（只 shutdown 的话连接会挂到超时）
        RP.outbox_loop(once=True)
        ok('D2 ★主站整个连不上 ⇒ 重试', db.row('del:x')['done_at'] is None and db.row('del:x')['last_status'].startswith('conn'),
           str(db.row('del:x')['last_status']))
        db.claim_404 = True
        RP._outbox_off.clear()
        t0 = time.time()
        RP.outbox_loop(once=False)
        ok('D7 领活 404（库里没上迁移）⇒ 常驻循环自己退、本进程不再领', RP._outbox_off.is_set() and time.time() - t0 < 5)
        RP._outbox_off.clear()
    finally:
        try:
            srv.shutdown()
        except Exception:
            pass
        for k in ('MAINSITE_BASE', 'MAINSITE_HOOK_SECRET'):
            os.environ.pop(k, None)


def main():
    part_a()
    part_b()
    part_c()
    part_d()
    print('')
    if fails[0] == 0 and n[0] >= 77:
        print('ALL OK — 签名与主站 Go 逐字节相同; 网关三种篡改被拒、重放同结果; 发件箱 ok:false 停 / 5xx·401 重试 / settle 等 started (%d 条)' % n[0])
        return 0
    print('FAIL x%d (断言 %d 条)' % (fails[0], n[0]))
    return 1


if __name__ == '__main__':
    sys.exit(main())
