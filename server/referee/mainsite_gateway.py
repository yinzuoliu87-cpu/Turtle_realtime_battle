#!/usr/bin/env python3
"""龟投（主站）网关（方案书 docs/plans/20261107-龟战主站对接.md §4.1 / §4.4 / §4.8；原始设计 20261105c §4.6 D38）。

裁判机上一个常驻 HTTP 服务（systemd：turtle-mainsite-gateway.service / -beta.service；Caddy 反代
arena.turtlearena.xyz / arena-beta.turtlearena.xyz → 本机回环端口）。只用标准库。三类入口：

主站 → 我们（HMAC 验签，规则 = mainsite_sign.py；验不过一律 401 {ok:false, error:"bad arena signature"}；回复一律带 ok）
  GET  /mainsite/link/info?code=        → {ok:true, device} / {ok:false, error}        （GET 签 ts + "."；code 不受签名保护）
  POST /mainsite/link/confirm {code, user_id} → {ok:true, result} / {ok:false, error}
  POST /mainsite/raid {raidId, attacker, defender, seed, stake, isRevenge, expireAt}
                                        → raid_intake.handle_create(body, rpc) 的返回原样（A2 线的模块；没部署 ⇒ 503）
App → 我们（Authorization: Bearer <Supabase access_token>，向 Supabase /auth/v1/user 换出账号）
  POST /app/link/start {device}         → {ok, code, url, expires_in}   url = {MAINSITE_LINK_BASE}/game/link?code=<code>
  POST /app/link/poll {code}            → {ok, status: pending|confirmed|expired, switched, result?, session?}
                                           switched:true ⇒ session = 那个号的 {access_token, refresh_token}（见 SupabaseAdmin）
  POST /app/pets/refresh {}             → {ok, linked, owned:[…]}（调主站 /player 写 mainsite_pets；主站不可用 ⇒ 上次缓存 + stale:true）
其他
  GET  /healthz                         → {ok:true}

数据库全走 PostgREST rpc（service key；函数见迁移 20261109a_mainsite_core.sql），与 referee_poller.rpc 同一个函数。

环境变量（systemd EnvironmentFile，与裁判轮询器同一份 /etc/turtle-referee/env[-beta]）：
  SUPABASE_URL / SUPABASE_SERVICE_KEY   同轮询器
  MAINSITE_BASE                         主站根地址（https://turtlepoll.com；内测地址只在 turtlebet 仓库 docs/arena-plan.md §8）
  MAINSITE_LINK_BASE                    App 打开的确认页根地址，默认 = MAINSITE_BASE
  MAINSITE_HOOK_SECRET[_FILE]           签名密钥（内测 / 正式各一套；★不进仓库、不打印）
  GATEWAY_BIND / GATEWAY_PORT           默认 127.0.0.1 / 8790（内测服那份 8791，见 -beta.service）
  LOGIN_EMAIL_DOMAIN                    匿名号补内部邮箱用的域名，默认 link.turtlearena.xyz（见 SupabaseAdmin）

★日志只记方法、路径、状态码、耗时；不记请求体、令牌、签名。
"""
import hashlib
import http.server
import json
import os
import re
import secrets
import signal
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mainsite_sign as MS  # noqa: E402
import referee_poller as RP  # noqa: E402  —— rpc / log / env 用同一份

CODE_RE = re.compile(r"^[A-Za-z0-9_-]{4,64}$")
MAX_BODY = 64 * 1024
LINK_TTL_SEC = 300
PETS_MIN_GAP_SEC = 10.0
RPC_TIMEOUT_SEC = 8.0
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Upstream(Exception):
    """下游（数据库 / Supabase Auth / 主站）不可用 ⇒ 5xx。"""


def _json(raw: bytes):
    try:
        v = json.loads(raw.decode("utf-8")) if raw else None
    except (ValueError, UnicodeDecodeError):
        return None
    return v


def _http(method, url, headers, body=None, timeout=10.0):
    """返回 (HTTP 状态, 解析后的回包或 None)。连不上 ⇒ 抛 Upstream。"""
    data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode("utf-8"))
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with OPENER.open(req, timeout=timeout) as r:
            return r.status, _json(r.read())
    except urllib.error.HTTPError as e:
        return e.code, _json(e.read())
    except Exception as e:      # 连不上 / 超时 / 对面断开（http.client 的几种异常不都是 OSError）
        raise Upstream("%s %s: %s" % (method, url.split("?")[0], getattr(e, "reason", e)))


class SupabaseAdmin:
    """App 令牌 → 账号；给指定账号签发登录态（2026-11-09 在内测服实测通过：tools/oneoff/probe_auth_session.py）。

    签发 = Supabase 官方的「管理员生成登录链接再兑换」：
      ① GET  /auth/v1/admin/users/{id}                 有没有邮箱
      ② 没有（匿名号）⇒ PUT /auth/v1/admin/users/{id} {email: <id>@LOGIN_EMAIL_DOMAIN, email_confirm: true}
         —— 不发信；★副作用（实测）：is_anonymous 变 false、email_confirmed_at 有值（这个号从此是「有邮箱」的正式号）
      ③ POST /auth/v1/admin/generate_link {type: magiclink, email} —— 回包平铺 hashed_token（不发信）
      ④ POST /auth/v1/verify {type: magiclink, token_hash} —— 回 {access_token, refresh_token, user}
    """

    def __init__(self, url, service_key, email_domain="link.turtlearena.xyz", cache_sec=30.0):
        self.url = url.rstrip("/")
        self.key = service_key
        self.domain = email_domain
        self.cache_sec = cache_sec
        self._cache = {}
        self._lock = threading.Lock()

    def _hdr(self, bearer=None):
        return {"apikey": self.key, "Authorization": "Bearer " + (bearer or self.key),
                "Content-Type": "application/json"}

    def account_of(self, token: str):
        """App 的 access_token → 账号 uuid；令牌无效 ⇒ None；Supabase 连不上 ⇒ Upstream。短缓存（轮询每 2 秒一次）。"""
        h = hashlib.sha256(token.encode("utf-8")).hexdigest()
        now = time.monotonic()
        with self._lock:
            hit = self._cache.get(h)
            if hit and hit[1] > now:
                return hit[0]
        st, u = _http("GET", self.url + "/auth/v1/user", self._hdr(token))
        if st >= 500:
            raise Upstream("auth/v1/user HTTP %d" % st)
        uid = u.get("id") if st == 200 and isinstance(u, dict) else None
        if not uid:
            return None
        with self._lock:
            if len(self._cache) > 2000:
                self._cache.clear()
            self._cache[h] = (uid, now + self.cache_sec)
        return uid

    def issue_session(self, account_id: str) -> dict:
        st, u = _http("GET", self.url + "/auth/v1/admin/users/" + account_id, self._hdr())
        if st != 200 or not isinstance(u, dict):
            raise Upstream("admin get user HTTP %d" % st)
        email = u.get("email") or ""
        if not email:
            email = "%s@%s" % (account_id, self.domain)
            st, _ = _http("PUT", self.url + "/auth/v1/admin/users/" + account_id, self._hdr(),
                          {"email": email, "email_confirm": True})
            if st != 200:
                raise Upstream("admin set email HTTP %d" % st)
        st, link = _http("POST", self.url + "/auth/v1/admin/generate_link", self._hdr(),
                         {"type": "magiclink", "email": email})
        th = None
        if isinstance(link, dict):
            # 实测（11-09 内测服）：直接调 REST 时 hashed_token 平铺在顶层；supabase-js 会把它挪进 properties —— 两种都认
            th = link.get("hashed_token") or (link.get("properties") or {}).get("hashed_token")
        if st != 200 or not th:
            raise Upstream("generate_link HTTP %d" % st)
        st, sess = _http("POST", self.url + "/auth/v1/verify", self._hdr(), {"type": "magiclink", "token_hash": th})
        if st != 200 or not isinstance(sess, dict) or not sess.get("access_token") or not sess.get("refresh_token"):
            raise Upstream("verify HTTP %d" % st)
        if ((sess.get("user") or {}).get("id") or account_id) != account_id:
            raise Upstream("verify 换出的不是这个号")
        return {"access_token": sess["access_token"], "refresh_token": sess["refresh_token"]}


def mainsite_post(base, secret, topic, body, timeout=10.0):
    """签名调主站 {base}/api/arena-hook/{topic}。返回 (HTTP 状态, 回包)；连不上 ⇒ Upstream。"""
    data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    hdr = MS.headers(secret, data)
    hdr["Content-Type"] = "application/json"
    return _http("POST", base.rstrip("/") + "/api/arena-hook/" + topic, hdr, data, timeout=timeout)


def load_raid_handler():
    """A2 线的 raid_intake.handle_create(body, rpc) -> dict；还没部署 ⇒ None（/mainsite/raid 回 503）。"""
    try:
        import raid_intake  # noqa: WPS433
    except ImportError:
        return None
    return getattr(raid_intake, "handle_create", None)


class Gateway:
    """路由与业务。HTTP 外壳（_Handler）只管读写字节；门禁可以把 rpc / auth / 主站 换成假的。"""

    def __init__(self, secret, mainsite_base, link_base=None, rpc=None, auth=None, raid_handler=None,
                 now=None, post=None):
        self.secret = secret
        self.base = (mainsite_base or "").rstrip("/")
        self.link_base = (link_base or self.base).rstrip("/")
        self.rpc = rpc or RP.rpc
        self.auth = auth                      # SupabaseAdmin 形状：account_of(token) / issue_session(account)
        self.raid_handler = raid_handler
        self.now = now or time.time
        self.post = post or mainsite_post
        self._pets_last = {}                  # 账号 → 上次调主站 /player 的时刻（同一个号 10 秒内只调一次）
        self._pets_lock = threading.Lock()
        self.rpc_timeout = RPC_TIMEOUT_SEC

    # ── 入口 ──
    def handle(self, method, path, query, headers, body):
        """返回 (HTTP 状态, 回包 dict)。headers：大小写不敏感的取值函数 get(name)。"""
        if path == "/healthz":
            return 200, {"ok": True}
        route = {("GET", "/mainsite/link/info"): self.link_info,
                 ("POST", "/mainsite/link/confirm"): self.link_confirm,
                 ("POST", "/mainsite/raid"): self.raid,
                 ("POST", "/app/link/start"): self.app_link_start,
                 ("POST", "/app/link/poll"): self.app_link_poll,
                 ("POST", "/app/pets/refresh"): self.app_pets_refresh}
        fn = route.get((method, path))
        if fn is None:
            if any(p == path for (_, p) in route):
                return 405, {"ok": False, "error": "method_not_allowed"}
            return 404, {"ok": False, "error": "not_found"}
        if len(body) > MAX_BODY:
            return 413, {"ok": False, "error": "too_large"}
        try:
            if path.startswith("/mainsite/"):
                if not MS.verify(self.secret, headers(MS.HDR_TS), headers(MS.HDR_SIG), body, now=self.now()):
                    return 401, {"ok": False, "error": "bad arena signature"}
                if method == "GET":
                    return fn(query, None)
                data = _json(body)
                if not isinstance(data, dict):
                    return 400, {"ok": False, "error": "bad json"}
                return fn(query, data)
            acc = self._account(headers("Authorization"))
            if acc is None:
                return 401, {"ok": False, "error": "not_signed_in"}
            data = _json(body) if body else {}
            if not isinstance(data, dict):
                return 400, {"ok": False, "error": "bad json"}
            return fn(acc, data)
        except (Upstream, urllib.error.URLError, OSError, ValueError) as ex:
            RP.log("WARN gateway %s %s: %s" % (method, path, str(ex)[:200]))
            return 503, {"ok": False, "error": "unavailable"}

    def _account(self, authz):
        m = re.match(r"^Bearer\s+(\S+)$", (authz or "").strip())
        if not m or self.auth is None:
            return None
        return self.auth.account_of(m.group(1))

    def _rpc(self, fn, body, timeout=None):
        """同 referee_poller.rpc 的签名；超时默认 8 秒（主站调我们 10 秒就放弃，库慢了宁可早点回 503）。"""
        try:
            return self.rpc(fn, body, timeout=self.rpc_timeout if timeout is None else timeout)
        except urllib.error.HTTPError as ex:
            raise Upstream("rpc %s HTTP %d" % (fn, ex.code))

    # ── 主站 → 我们 ──
    def link_info(self, query, _):
        code = (query.get("code") or [""])[0]
        if not CODE_RE.match(code):
            return 200, {"ok": False, "error": "bad_code"}
        r = self._rpc("mainsite_link_info", {"p_code": code}) or {}
        return 200, {"ok": True, "device": str(r.get("device") or "")} if r.get("ok") is True \
            else {"ok": False, "error": str(r.get("error") or "bad_code")}

    def link_confirm(self, _, data):
        code, uid = data.get("code"), data.get("user_id")
        if not isinstance(code, str) or not CODE_RE.match(code):
            return 200, {"ok": False, "error": "bad_code"}
        if not isinstance(uid, str) or not uid:
            return 200, {"ok": False, "error": "bad userId"}
        r = self._rpc("mainsite_link_confirm", {"p_code": code, "p_user_id": uid}) or {}
        if r.get("ok") is True:
            return 200, {"ok": True, "result": r.get("result")}
        return 200, {"ok": False, "error": str(r.get("error") or "bad_code")}

    def raid(self, _, data):
        if self.raid_handler is None:
            return 503, {"ok": False, "error": "raid_unavailable"}
        try:
            ## 给 A2 的 rpc 与 referee_poller.rpc 同签名，只是默认超时短（同 _rpc 的理由）；HTTPError 原样抛给它自己判
            r = self.raid_handler(data, lambda fn, body, timeout=None: self.rpc(
                fn, body, timeout=self.rpc_timeout if timeout is None else timeout))
        except Exception as ex:      # A2 的模块抛什么都不能让网关挂：主站按「龟战忙」处理、立刻退押注
            RP.log("ERROR gateway raid_intake: %r" % (ex,))
            return 500, {"ok": False, "error": "internal"}
        if not isinstance(r, dict) or "ok" not in r:
            return 500, {"ok": False, "error": "internal"}
        return 200, r

    # ── App → 我们 ──
    def app_link_start(self, acc, data):
        if not self.link_base:
            return 503, {"ok": False, "error": "not_configured"}
        dev = str(data.get("device") or "").strip()[:128]
        for _ in range(3):
            code = secrets.token_urlsafe(24)          # 32 个 [A-Za-z0-9_-]（192 位随机）
            r = self._rpc("mainsite_link_start", {"p_account": acc, "p_code": code, "p_device": dev}) or {}
            if r.get("ok") is True:
                return 200, {"ok": True, "code": code, "url": self.link_base + "/game/link?code=" + code,
                             "expires_in": int(r.get("expires_in") or LINK_TTL_SEC)}
            if r.get("error") != "code_taken":
                return 200, {"ok": False, "error": str(r.get("error") or "failed")}
        return 503, {"ok": False, "error": "unavailable"}

    def app_link_poll(self, acc, data):
        code = data.get("code")
        if not isinstance(code, str) or not CODE_RE.match(code):
            return 200, {"ok": False, "error": "bad_code"}
        r = self._rpc("mainsite_link_poll", {"p_account": acc, "p_code": code}) or {}
        if r.get("ok") is not True:
            return 200, {"ok": False, "error": str(r.get("error") or "bad_code")}
        out = {"ok": True, "status": r.get("status"), "switched": r.get("switched") is True}
        if r.get("result"):
            out["result"] = r["result"]
        if out["status"] == "confirmed" and out["switched"]:
            tgt = str(r.get("target_account") or "")
            if not tgt or self.auth is None:
                return 503, {"ok": False, "error": "session_failed"}
            try:
                out["session"] = self.auth.issue_session(tgt)
            except (Upstream, urllib.error.URLError, OSError, ValueError) as ex:
                RP.log("WARN gateway 签发登录态失败: %s" % (str(ex)[:200],))
                return 503, {"ok": False, "error": "session_failed"}
        return 200, out

    def app_pets_refresh(self, acc, _):
        st = self._rpc("mainsite_status", {"p_account": acc}) or {}
        if st.get("linked") is not True:
            return 200, {"ok": True, "linked": False, "owned": []}
        cached = {"ok": True, "linked": True, "owned": list(st.get("owned") or []), "stale": True}
        uid = str(st.get("user_id") or "")
        if not self.base or not self.secret:
            return 200, cached
        now = self.now()
        with self._pets_lock:
            last = self._pets_last.get(acc)
            if last is not None and now - last[0] < PETS_MIN_GAP_SEC:
                # 刚取过：成功 ⇒ 库里就是最新的；失败 ⇒ 照旧标 stale（10 秒内不再让 App 每次多等一个主站超时）
                return 200, cached if not last[1] else {"ok": True, "linked": True, "owned": cached["owned"]}
            if len(self._pets_last) > 5000:
                self._pets_last.clear()
            self._pets_last[acc] = (now, False)
        try:
            code, rep = self.post(self.base, self.secret, "player", {"userId": uid})
        except Upstream as ex:
            RP.log("WARN gateway /player 连不上: %s" % (str(ex)[:200],))
            return 200, cached
        if code != 200 or not isinstance(rep, dict) or rep.get("ok") is not True or not isinstance(rep.get("turtles"), list):
            RP.log("WARN gateway /player HTTP %s ok=%s" % (code, (rep or {}).get("ok") if isinstance(rep, dict) else None))
            return 200, cached
        w = self._rpc("mainsite_pets_put", {"p_account": acc, "p_user_id": uid, "p_keys": rep["turtles"]}) or {}
        if w.get("ok") is not True:
            return 200, cached
        with self._pets_lock:
            self._pets_last[acc] = (now, True)
        return 200, {"ok": True, "linked": True, "owned": list(w.get("owned") or [])}


class _Handler(http.server.BaseHTTPRequestHandler):
    server_version = "turtle-gateway"
    sys_version = ""
    timeout = 15          # HTTP/1.0：每个回包后断开（长连接由前面的 Caddy 管）；慢客户端 15 秒踢掉

    def log_message(self, fmt, *args):
        pass

    def _go(self, method):
        t0 = time.monotonic()
        u = urllib.parse.urlsplit(self.path)
        body = b""
        if (self.headers.get("Transfer-Encoding") or "").lower() == "chunked":
            code, rep = 411, {"ok": False, "error": "length_required"}
        else:
            try:
                n = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                n = -1
            if n < 0 or n > MAX_BODY:
                code, rep = 413, {"ok": False, "error": "too_large"}
            else:
                body = self.rfile.read(n) if n else b""
                try:
                    code, rep = self.server.gw.handle(method, u.path, urllib.parse.parse_qs(u.query, keep_blank_values=True),
                                                      self.headers.get, body)
                except Exception as ex:      # 意外：回 500 JSON（主站按「龟战忙」处理），网关本身不挂
                    RP.log("ERROR gateway %s %s: %r" % (method, u.path, ex))
                    code, rep = 500, {"ok": False, "error": "internal"}
        raw = json.dumps(rep, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)
        if not getattr(self.server, "quiet", False):
            RP.log("gateway %s %s → %d %.0fms" % (method, u.path, code, (time.monotonic() - t0) * 1000))

    def do_GET(self):
        self._go("GET")

    def do_POST(self):
        self._go("POST")


def serve(gw, bind="127.0.0.1", port=8790, quiet=False):
    """起服务（门禁用 port=0 拿随机端口）。返回 server；server.server_address[1] 是端口。"""
    srv = http.server.ThreadingHTTPServer((bind, port), _Handler)
    srv.daemon_threads = True
    srv.gw = gw
    srv.quiet = quiet
    return srv


def main() -> int:
    e = RP.env
    secret = MS.load_secret()
    if not e("SUPABASE_URL") or not e("SUPABASE_SERVICE_KEY"):
        print("缺 SUPABASE_URL / SUPABASE_SERVICE_KEY")
        return 2
    if not secret or not e("MAINSITE_BASE"):
        print("缺 MAINSITE_BASE / MAINSITE_HOOK_SECRET(_FILE)")
        return 2
    auth = SupabaseAdmin(e("SUPABASE_URL"), e("SUPABASE_SERVICE_KEY"), e("LOGIN_EMAIL_DOMAIN", "link.turtlearena.xyz"))
    raid = load_raid_handler()
    gw = Gateway(secret, e("MAINSITE_BASE"), e("MAINSITE_LINK_BASE") or None, auth=auth, raid_handler=raid)
    bind, port = e("GATEWAY_BIND", "127.0.0.1"), int(e("GATEWAY_PORT", "8790"))
    srv = serve(gw, bind, port)
    RP.log("mainsite gateway: %s:%d, raid_intake=%s" % (bind, port, "on" if raid else "off(503)"))
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=srv.shutdown, daemon=True).start())
    signal.signal(signal.SIGINT, lambda *_: threading.Thread(target=srv.shutdown, daemon=True).start())
    srv.serve_forever()
    RP.log("mainsite gateway: stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
