# -*- coding: utf-8 -*-
"""tools/mainsite_beta_smoke.py —— 龟投（主站）对接 · 我们这一侧的联调冒烟（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.7 / §4.8）。

部署好（tools/mainsite_deploy.py --apply）之后一条命令验收：本脚本**扮演主站**（用内测密钥按主站算法签名，签名模块 =
server/referee/mainsite_sign.py，与主站 Go 代码逐字节）调我们的内测网关，同时**扮演 App**（内测服匿名测试号的登录态）。

  python tools/mainsite_beta_smoke.py                  内测：https://arena-beta.turtlearena.xyz + 内测服 turtle-beta（★会建 3 个匿名测试号，结束时删掉）
  python tools/mainsite_beta_smoke.py --keep           不删测试号（排查用）
  python tools/mainsite_beta_smoke.py --no-raid        只验到登录 / 绑定 / 换号（偷袭要内测服 raid_on + econ_on 与认 raid 模式的裁判版本）
  python tools/mainsite_beta_smoke.py --mock           本机：假主站 tools/mock_mainsite.py + 本机起真网关进程 + 假库（不连任何外网 / 库）

步骤（内测；每步打印 ✓ / ✗，第一条 ✗ 就停并说先看哪里）：
  S1 网关 /healthz 200；不带签名 / 签名错 / 时间戳过期 / 改了请求体 一律 401
  S2 建两个测试号 A（攻）、D（守）：内测服匿名注册（= tools/beta_ops.py signup-smoke 的做法），拿 access_token
  S3 A：App POST /app/link/start → 码（32 位 [A-Za-z0-9_-]）+ 确认页地址 {主站}/game/link?code=<码>
  S4 主站 GET /mainsite/link/info?code= → {ok:true, device}（device = S3 交的设备名）
  S5 主站 POST /mainsite/link/confirm {code, user_id} → {ok:true, result:"bound"}；重发同一请求 ⇒ 同一结果
  S6 A：App POST /app/link/poll → status = confirmed、switched = false；D 同样走一遍（S3 ~ S6）
  S7 换号：第三个号 S 发起登录码，主站用 A 的 user_id 确认 ⇒ result = switched；S 轮询 ⇒ switched:true + A 的登录态
     （用这份登录态调 /auth/v1/user 得到 A 的账号 —— 证明网关签发登录态在真环境里通）
  S8 两个号存本周防守阵容：raid_defense_put（快照 = tests/golden/stream_heavy_pair.json 的 a / b，三统领齐的真实快照）⇒ has_defense
  S8b 扮演主站 /player：快照三只统领写进两个号的拥有龟缓存（mainsite_pets_put）—— 裁判把关「拥有 ∪ 限免」，编的主站用户主站不认 ⇒
      不写就 a_bad_snapshot（11-09 内测实测）；给了 --attacker-uid / --defender-uid 就不写
  S9 主站 POST /mainsite/raid {raidId, attacker, defender, seed, stake, isRevenge, expireAt} ⇒ {ok:true, jobId}；同 raidId 重发 ⇒ 同一 jobId
  S10 轮询（只读 SQL）raid_jobs 直到 done / void（默认最多 15 分钟）；打印裁判任务的状态与错误码
  S11 读发件箱（只读 SQL）这个 raidId 的 started / settle 两行：started 已发、settle 结果 = attacker / defender、matchId 非空
  S12 删测试号（--keep 不删）
★S9 之后要三件事都在：内测服 referee_config raid_on 与 econ_on 都开（20261109c raid_enabled）、内测服裁判机装了认 raid 模式的客户端版本
  （0.22.9 及更早的 referee_job.gd 没有 raid ⇒ 裁判拒算 bad_mode ⇒ settle void）、内测服轮询器在跑（周末被 peak timer 停着）。
  缺哪件脚本就停在那一步并直说缺的是哪件。
★本脚本建的偷袭主站并不知道（raidId 是本脚本编的）⇒ 发件箱的 started / settle 发到主站内测会回 ok:false（raid not found），属预期；
  主站用户 ID 默认也是编的（--attacker-uid / --defender-uid 换成主站内测的真测试号即可做双方联调）。

--mock 覆盖到哪：网关真进程（读 env、验签、路由、回包形状、登录码 / 轮询 / 换号签发、拥有龟刷新调假主站 /player、偷袭建任务转 raid_intake）；
  库是内存假库（mainsite_selftest.FakeDB + raid_create / raid_defense_put 的最小替身），所以 S8 只验调用形状、S10 / S11（裁判 / 发件箱 / 真 SQL）不覆盖
  —— 那两步只能部署后在内测跑。
密钥：内测 ~/.config/turtle/secrets/mainsite_beta_hook.txt（或 MAINSITE_BETA_SECRET_FILE）；--mock 现生成一个随机密钥。只在内存里，不打印。
内测主站地址：MAINSITE_BETA_BASE 或 turtlebet origin/main docs/arena-plan.md §8（同 tools/mainsite_deploy.py；★不进本仓库）。
"""
import argparse
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "server", "referee"))
import sb_common as S  # noqa: E402
import mainsite_sign as MS  # noqa: E402
import mainsite_deploy as DEP  # noqa: E402

OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CODE_RE = re.compile(r"^[A-Za-z0-9_-]{4,64}$")
SNAP_FILE = os.path.join(ROOT, "tests", "golden", "stream_heavy_pair.json")


class Fail(Exception):
    pass


class Smoke:
    def __init__(self, a):
        self.a = a
        self.n = 0
        self.cleanup = []

    def ok(self, name, cond, detail="", hint=""):
        self.n += 1
        print(("  ✓ " if cond else "  ✗ ") + name + ("" if cond else "  —— %s" % str(detail)[:300]))
        if not cond:
            if hint:
                print("    先看：" + hint)
            raise Fail(name)


def http(method, url, body=None, headers=None, timeout=12):
    data = body if (body is None or isinstance(body, bytes)) else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with OP.open(req, timeout=timeout) as r:
            code, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        code, raw = e.code, e.read()
    except (urllib.error.URLError, OSError) as e:
        return 0, {"_err": str(e)}
    try:
        return code, json.loads(raw.decode("utf-8")) if raw else None
    except ValueError:
        return code, {"_raw": raw.decode("utf-8", "replace")[:200]}


def go_json(obj):
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def site(gw, secret, method, path, body=None, ts=None, tamper=False, sig=None):
    """以主站身份调网关（= turtlebet ArenaGameClient：POST 签原始请求体，GET 签 ts + "."）。"""
    raw = None if body is None else go_json(body)
    hdr = MS.headers(secret, raw, now=ts)
    if sig is not None:
        hdr[MS.HDR_SIG] = sig
    if raw is not None:
        hdr["Content-Type"] = "application/json"
        if tamper:
            raw = raw.replace(b'"', b'"', 1) + b" "
    return http(method, gw + path, raw, hdr)


def app(gw, token, path, body=None):
    h = {"Content-Type": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    return http("POST", gw + path, json.dumps(body or {}).encode("utf-8"), h)


# ── 内测服（真）──────────────────────────────────────────────────
class BetaBackend:
    """内测服 turtle-beta：匿名注册 / 用户 RPC（公开 key）/ 只读 SQL / 删测试号（管理令牌，同 beta_ops signup-smoke）。"""

    def __init__(self):
        S.refuse_prod(" ".join(sys.argv), "mainsite_beta_smoke")
        self.ref = S.BETA_REF
        self.url = S.URLS[self.ref]
        self.pub = S.PUBLISHABLE[self.ref]

    def signup(self):
        st, b = http("POST", self.url + "/auth/v1/signup", b"{}", {"apikey": self.pub, "Content-Type": "application/json"})
        if st != 200 or not isinstance(b, dict) or not b.get("access_token"):
            return None, None
        return (b.get("user") or {}).get("id"), b["access_token"]

    def user_of(self, token):
        st, b = http("GET", self.url + "/auth/v1/user", None, {"apikey": self.pub, "Authorization": "Bearer " + token})
        return (b or {}).get("id") if st == 200 and isinstance(b, dict) else None

    def user_rpc(self, token, fn, body):
        return http("POST", self.url + "/rest/v1/rpc/" + fn, json.dumps(body).encode("utf-8"),
                    {"apikey": self.pub, "Authorization": "Bearer " + token, "Content-Type": "application/json",
                     S.HDR_CLIENT_VERSION: S.client_version()})

    def ro(self, sql):
        return S.query_ro(self.ref, sql)

    def week(self):
        return int(S.one(self.ro("select public.raid_week() as w")).get("w"))

    def delete_users(self, ids):
        ids = [i for i in ids if re.fullmatch(r"[0-9a-f-]{36}", i or "")]
        if ids:
            S.query(self.ref, "delete from auth.users where id in (%s)" % ",".join("'%s'" % i for i in ids))


# ── 本机（--mock）──────────────────────────────────────────────────
class MockBackend:
    """内存假库 + 假 Supabase Auth（一个本机 HTTP 服务：/rest/v1/rpc/<fn>、/auth/v1/…），给本机起的真网关进程连。"""

    def __init__(self, mock_state):
        import mainsite_selftest as MT          # FakeDB = 迁移 20261109a 各函数的内存版（门禁同一份，不另抄）
        self.MT = MT
        db = MT.FakeDB()
        db.t = time.time()
        self.db = db
        self.mock = mock_state
        self.tokens = {}
        self.defense = {}
        self.raids = {}
        db.raid_defense_put = None
        srv = self._serve()
        self.url = "http://127.0.0.1:%d" % srv.server_address[1]
        self.srv = srv

    def _serve(self):
        import http.server
        me = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _send(self, code, obj):
                raw = json.dumps(obj).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_GET(self):
                tok = (self.headers.get("Authorization") or "")[7:]
                if self.path == "/auth/v1/user" and tok in me.tokens:
                    return self._send(200, {"id": me.tokens[tok]})
                m = re.match(r"^/auth/v1/admin/users/([0-9a-f-]{36})$", self.path)
                if m:
                    return self._send(200, {"id": m.group(1), "email": m.group(1) + "@link.test"})
                return self._send(401 if self.path == "/auth/v1/user" else 404, {})

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(n) or b"{}")
                if self.path == "/auth/v1/admin/generate_link":
                    return self._send(200, {"hashed_token": "h:" + body["email"].split("@")[0]})
                if self.path == "/auth/v1/verify":
                    acc = body["token_hash"][2:]
                    tok = "tok-" + secrets.token_hex(8)
                    me.tokens[tok] = acc
                    return self._send(200, {"access_token": tok, "refresh_token": "r", "user": {"id": acc}})
                m = re.match(r"^/rest/v1/rpc/(\w+)$", self.path)
                if m:
                    fn = m.group(1)
                    if fn == "raid_create":
                        return self._send(200, me.raid_create(**body))
                    if not hasattr(me.db, fn) or getattr(me.db, fn) is None:
                        return self._send(404, {"message": "no function"})
                    return self._send(200, me.db.rpc(fn, body))
                return self._send(404, {})

        srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        srv.daemon_threads = True
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        return srv

    def signup(self):
        acc = "%08x-0000-4000-8000-%012x" % (secrets.randbits(32), secrets.randbits(48))
        tok = "tok-" + secrets.token_hex(8)
        self.tokens[tok] = acc
        return acc, tok

    def user_of(self, token):
        return self.tokens.get(token)

    def user_rpc(self, token, fn, body):
        if fn != "raid_defense_put":
            return 404, None
        acc = self.tokens.get(token)
        snap = body.get("p_snapshot") or {}
        okk = acc and len(snap.get("leaders") or []) == 3
        if okk:
            self.defense[acc] = snap
        return 200, {"ok": bool(acc), "stored": bool(okk), "has_defense": bool(okk)}

    def raid_create(self, p_raid_id, p_attacker, p_defender, **kw):
        """最小替身：同 raidId 回同一 jobId；没绑定 / 没阵容照 20261109c 的口径 ok:true 但不排裁判。"""
        if p_raid_id in self.raids:
            return {"ok": True, "jobId": self.raids[p_raid_id]}
        self.raids[p_raid_id] = str(len(self.raids) + 1)
        return {"ok": True, "jobId": self.raids[p_raid_id]}

    def week(self):
        return 0

    def delete_users(self, ids):
        pass


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def start_local_gateway(supabase_url, mainsite_base, secret):
    """本机起真网关进程（server/referee/mainsite_gateway.py 的 main：读 env、起 HTTP）。密钥只经子进程环境传。"""
    port = free_port()
    env = dict(os.environ, SUPABASE_URL=supabase_url, SUPABASE_SERVICE_KEY="mock-service-key", MAINSITE_BASE=mainsite_base,
               MAINSITE_HOOK_SECRET=secret, GATEWAY_BIND="127.0.0.1", GATEWAY_PORT=str(port),
               no_proxy="127.0.0.1,localhost", NO_PROXY="127.0.0.1,localhost", PYTHONIOENCODING="utf-8")
    p = subprocess.Popen([sys.executable, os.path.join(ROOT, "server", "referee", "mainsite_gateway.py")], env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    gw = "http://127.0.0.1:%d" % port
    for _ in range(50):
        if http("GET", gw + "/healthz", timeout=1)[0] == 200:
            return p, gw
        if p.poll() is not None:
            break
        time.sleep(0.1)
    p.kill()
    raise SystemExit("本机网关起不来: %s" % (p.stdout.read() or b"").decode("utf-8", "replace")[-400:])


# ── 剧本 ──────────────────────────────────────────────────────────
def link_one(sm, be, gw, secret, base, label, uid, device):
    acc, tok = be.signup()
    sm.ok("S2 %s：建测试号（匿名注册）拿到登录态" % label, bool(acc and tok), "", "内测服匿名登录开没开（tools/beta_ops.py signup-smoke）")
    sm.cleanup.append(acc)
    st, r = app(gw, tok, "/app/link/start", {"device": device})
    code = (r or {}).get("code", "")
    sm.ok("S3 %s：/app/link/start → 码 + 确认页地址" % label,
          st == 200 and (r or {}).get("ok") is True and CODE_RE.match(code or "") and len(code) == 32
          and str(r.get("url", "")).endswith("/game/link?code=" + code)
          and (not base or str(r.get("url", "")).startswith(base + "/") or str(r.get("url", "")).startswith(gw + "/")),
          (st, {k: v for k, v in (r or {}).items() if k != "code"}),
          "网关日志 journalctl -u turtle-mainsite-gateway-beta；url 前缀不对 = env 里 MAINSITE_BASE / MAINSITE_LINK_BASE")
    st, r = site(gw, secret, "GET", "/mainsite/link/info?code=" + urllib.parse.quote(code))
    sm.ok("S4 %s：主站 GET /mainsite/link/info → {ok:true, device}" % label,
          st == 200 and (r or {}).get("ok") is True and r.get("device") == device, (st, r),
          "401 = 密钥 / 时钟不对（env 里的 MAINSITE_HOOK_SECRET 与主站后台内测密钥是不是同一个）；503 = 库连不上 / 迁移 20261109a 没上")
    body = {"code": code, "user_id": uid}
    st, r = site(gw, secret, "POST", "/mainsite/link/confirm", body)
    st2, r2 = site(gw, secret, "POST", "/mainsite/link/confirm", body)
    sm.ok("S5 %s：主站 POST /mainsite/link/confirm → bound；重发同一请求 → 同一结果" % label,
          st == 200 and (r or {}).get("ok") is True and r.get("result") == "bound" and r2 == r, (st, r, r2))
    st, r = app(gw, tok, "/app/link/poll", {"code": code})
    sm.ok("S6 %s：/app/link/poll → confirmed、switched:false" % label,
          st == 200 and (r or {}).get("status") == "confirmed" and r.get("switched") is False, (st, r))
    return acc, tok


def scenario(a, be, gw, secret, base):
    sm = Smoke(a)
    try:
        print("== S1 网关活着、验签")
        st, r = http("GET", gw + "/healthz")
        sm.ok("S1a GET /healthz = 200 {ok:true}", st == 200 and (r or {}).get("ok") is True, (st, r),
              "DNS / Caddy（journalctl -u caddy）/ 网关进程（systemctl status turtle-mainsite-gateway-beta）")
        b = {"code": "abcd1234", "user_id": "SmokeNobody1"}
        for name, kw in (("不带签名", {"sig": ""}), ("签名错", {"sig": "0" * 64}), ("时间戳过期 301 秒", {"ts": int(time.time()) - 301}),
                         ("改了请求体", {"tamper": True})):
            st, r = site(gw, "" if name == "不带签名" else secret, "POST", "/mainsite/link/confirm", b, **kw)
            sm.ok("S1b %s ⇒ 401 bad arena signature" % name, st == 401 and (r or {}).get("error") == "bad arena signature", (st, r))
        uid_a = a.attacker_uid or "SmkA" + secrets.token_hex(5)
        uid_d = a.defender_uid or "SmkD" + secrets.token_hex(5)
        print("== S2 ~ S6 登录码 → 主站确认 → App 轮询（A = 攻、D = 守）")
        acc_a, tok_a = link_one(sm, be, gw, secret, base, "A", uid_a, "smoke-A-iPhone")
        acc_d, tok_d = link_one(sm, be, gw, secret, base, "D", uid_d, "smoke-D-iPad")
        print("== S7 换号：第三个号发起、主站用 A 的 user_id 确认")
        acc_s, tok_s = be.signup()
        sm.cleanup.append(acc_s)
        st, r = app(gw, tok_s, "/app/link/start", {"device": "smoke-S"})
        code = (r or {}).get("code", "")
        st, r = site(gw, secret, "POST", "/mainsite/link/confirm", {"code": code, "user_id": uid_a})
        sm.ok("S7a 主站确认 → result = switched", (r or {}).get("ok") is True and r.get("result") == "switched", (st, r))
        st, r = app(gw, tok_s, "/app/link/poll", {"code": code})
        sess = (r or {}).get("session") or {}
        sm.ok("S7b S 轮询 → switched:true + 登录态（不打印）", st == 200 and r.get("switched") is True and sess.get("access_token"),
              (st, {k: v for k, v in (r or {}).items() if k != "session"}),
              "503 session_failed = 网关签发登录态失败（SUPABASE_SERVICE_KEY / LOGIN_EMAIL_DOMAIN；tools/oneoff/probe_auth_session.py）")
        sm.ok("S7c 这份登录态就是 A 的账号", be.user_of(sess["access_token"]) == acc_a, "")
        st, r = app(gw, tok_a, "/app/pets/refresh", {})
        sm.ok("S7d A：/app/pets/refresh → linked:true（主站不认这个编的 user_id 时回缓存 + stale，也算通）",
              st == 200 and (r or {}).get("ok") is True and r.get("linked") is True, (st, r))
        if a.no_raid:
            print("== --no-raid：偷袭段跳过")
            return sm, 0
        print("== S8 两个号存本周防守阵容（raid_defense_put）")
        with open(SNAP_FILE, encoding="utf-8") as f:
            pair = json.load(f)
        wk = be.week()
        for label, tok, snap in (("A", tok_a, pair["a"]), ("D", tok_d, pair["b"])):
            st, r = be.user_rpc(tok, "raid_defense_put", {"p_week": wk, "p_snapshot": snap, "p_device": "smoke-" + label})
            sm.ok("S8 %s：raid_defense_put(本周 %s) → stored、has_defense" % (label, wk),
                  st == 200 and (r or {}).get("has_defense") is True and r.get("stored") is True, (st, r),
                  "404 = 迁移 20261109c 没上；wrong_week = 内测服假时钟（tools/beta_ops.py status）")
        if not isinstance(be, MockBackend):
            # ★0.23.0 起裁判把关「拥有 ∪ 本周限免」（20261109b · RefereeJob.pets_allowed）：脚本编的主站用户主站不认 ⇒
            #   拥有龟缓存是空的 ⇒ 快照三只统领多半不在这个号的 7 只限免里 ⇒ 裁判拒算 a_bad_snapshot（11-09 内测实测）。
            #   扮演主站 /player 的回包：把快照统领写进拥有龟缓存（= 网关刷新拥有龟时调的同一个 mainsite_pets_put）。
            #   偷袭建任务（raid_create）从这份缓存盖 a_owned / b_owned。给了 --attacker-uid / --defender-uid（主站真测试号）⇒ 不写，以主站为准。
            print("== S8b 扮演主站 /player：快照统领写进拥有龟缓存")
            for label, acc, uid, snap, given in (("A", acc_a, uid_a, pair["a"], a.attacker_uid),
                                                 ("D", acc_d, uid_d, pair["b"], a.defender_uid)):
                if given:
                    print("  · %s：用的是主站真测试号，拥有龟以主站 /player 为准（不写）" % label)
                    continue
                keys = sorted(set(str(p) for p in snap.get("leaders", [])))
                r = S.one(S.query(be.ref, "select public.mainsite_pets_put('%s'::uuid, '%s', '%s'::jsonb) as r"
                                  % (acc, uid, json.dumps(keys))) or [{}]).get("r") or {}
                own = [x.get("k") for x in be.ro("select pet_key as k from public.mainsite_pets where account_id = '%s' order by 1" % acc)]
                sm.ok("S8b %s：拥有龟缓存 = 快照统领 %s" % (label, keys), own == keys, (r, own),
                      "not_linked / relinked = S5 绑定没成；拥有龟缓存表 mainsite_pets（迁移 20261109a）")
        print("== S9 主站建偷袭任务")
        raid_id = a.raid_id or (int(time.time() * 1000) * 1000 + secrets.randbelow(1000))
        body = {"raidId": raid_id, "attacker": uid_a, "defender": uid_d, "seed": 123456789, "stake": 0,
                "isRevenge": False, "expireAt": int(time.time() * 1000) + 6 * 3600 * 1000}
        st, r = site(gw, secret, "POST", "/mainsite/raid", body)
        hint = {"raid_off": "内测服 referee_config raid_on / econ_on 没都开（tools/mainsite_deploy.py 结尾的待办）",
                "no_referee": "内测服 referee_versions 里没有启用的版本", "busy": "库连不上 / 超时（网关日志）"}
        err = (r or {}).get("error")
        sm.ok("S9a POST /mainsite/raid → {ok:true, jobId}（raidId %d）" % raid_id, st == 200 and (r or {}).get("ok") is True and r.get("jobId"),
              (st, r), hint.get(err, "503 raid_unavailable = 裁判机上没拷 raid_intake.py"))
        job = r["jobId"]
        st, r2 = site(gw, secret, "POST", "/mainsite/raid", body)
        sm.ok("S9b 同 raidId 重发 → 同一 jobId", (r2 or {}).get("jobId") == job, (st, r2))
        if isinstance(be, MockBackend):
            print("  · --mock：S10 / S11（裁判算 / 发件箱 / 真 SQL）不覆盖 —— 只能部署后在内测跑")
            return sm, 0
        print("== S10 等裁判算完（只读 SQL，最多 %d 分钟）" % a.wait_min)
        ver = S.one(be.ro("select public.raid_pick_version() as v")).get("v")
        print("  · 内测服偷袭用的客户端版本 = %s（要认 raid 模式；0.22.9 及更早不认 ⇒ bad_mode ⇒ void）" % ver)
        t0 = time.time()
        row = {}
        while time.time() - t0 < a.wait_min * 60:
            row = S.one(be.ro("select r.status, r.reason, r.result, r.match_id::text as match_id, j.status as job_status, j.error "
                              "from public.raid_jobs r left join public.referee_jobs j on j.job_id = r.referee_job_id "
                              "where r.raid_id = %d" % raid_id))
            if row.get("status") in ("done", "void"):
                break
            time.sleep(10)
        sm.ok("S10 偷袭任务算完：status = done、result = attacker / defender", row.get("status") == "done" and row.get("result") in ("attacker", "defender"),
              row, "void + bad_mode = 裁判机版本不认 raid；一直 queued = 内测服轮询器没在跑（周末 / beta-off）或版本没登记")
        print("== S11 发件箱这一场的 started / settle")
        q_out = ("select id, topic, body, attempts, last_status, done_at::text as done_at from public.mainsite_outbox "
                 "where topic in ('started', 'settle') and body ->> 'raidId' = '%d' order by id" % raid_id)
        rows = be.ro(q_out)
        t1 = time.time()
        # 发件箱每 5 ~ 30 秒领一批：最多再等 2 分钟让两行都发出去
        while (len(rows) < 2 or not all(x.get("done_at") for x in rows)) and time.time() - t1 < 120:
            time.sleep(10)
            rows = be.ro(q_out)
        topics = [x.get("topic") for x in rows]
        st_row = next((x for x in rows if x.get("topic") == "settle"), {})
        sm.ok("S11a 发件箱有 started 与 settle 各一行（%s）" % topics, topics.count("started") == 1 and topics.count("settle") == 1, rows)
        sm.ok("S11b settle 的结果 = %s、matchId 非空" % row.get("result"),
              (st_row.get("body") or {}).get("result") == row.get("result") and (st_row.get("body") or {}).get("matchId"), st_row)
        sm.ok("S11c 两行都已发出（done_at 有值；last_status = %s）" % [x.get("last_status") for x in rows],
              all(x.get("done_at") for x in rows), rows,
              "没发 = 轮询器没开发件箱（env 里 MAINSITE_OUTBOX=1、读进程环境）；主站回 ok:false raid not found 属预期（这场是脚本编的）")
        return sm, 0
    except Fail:
        return sm, 1
    finally:
        if not a.keep:
            try:
                be.delete_users(sm.cleanup)
                if sm.cleanup and not isinstance(be, MockBackend):
                    print("  · 已删测试号 %d 个" % len([x for x in sm.cleanup if x]))
            except Exception as ex:
                print("  ✗ 删测试号失败（--keep 情形同）: %s" % str(ex)[:200])


def main(argv=None):
    S.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--gateway", default="https://arena-beta.turtlearena.xyz")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--no-raid", action="store_true")
    ap.add_argument("--attacker-uid", default="")
    ap.add_argument("--defender-uid", default="")
    ap.add_argument("--raid-id", type=int, default=0)
    ap.add_argument("--wait-min", type=int, default=15)
    a = ap.parse_args(argv)
    if a.mock:
        import mock_mainsite as MOCK
        secret = secrets.token_hex(32)
        msrv, mbase = MOCK.start(secret)
        be = MockBackend(msrv.state)
        proc, gw = start_local_gateway(be.url, mbase, secret)
        print("== --mock：假主站 %s · 假库 %s · 本机网关进程 %s（密钥现生成，不打印）" % (mbase, be.url, gw))
        try:
            sm, rc = scenario(a, be, gw, secret, mbase)
        finally:
            proc.terminate()
            try:
                proc.wait(5)
            except subprocess.TimeoutExpired:
                proc.kill()
            msrv.shutdown()
            be.srv.shutdown()
        calls = msrv.state.topics() if hasattr(msrv.state, "topics") else []
        print("  · 假主站收到的调用: %s" % calls)
    else:
        secret, sp = DEP.load_secret()
        if not secret:
            raise SystemExit("没有内测密钥 %s" % sp)
        base, src = DEP.beta_mainsite_base()
        print("== 内测：网关 %s · 内测主站 %s（%s）· 内测服 %s · 密钥 %s（不打印）" % (a.gateway, DEP.mask_url(base), src, S.BETA_REF, sp))
        sm, rc = scenario(a, BetaBackend(), a.gateway.rstrip("/"), secret, base)
    print("\n%d 步%s" % (sm.n, " ALL PASS" if rc == 0 else " —— 停在最后一条 ✗"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
