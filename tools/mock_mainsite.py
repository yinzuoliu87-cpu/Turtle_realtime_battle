# -*- coding: utf-8 -*-
"""tools/mock_mainsite.py —— 假主站（龟投）：门禁与联调前开发用（方案书 docs/plans/20261107-龟战主站对接.md §4.7 / §4.8）。

CI 连不上主站内测环境，门禁（tools/mainsite_selftest.py）全靠它。照主站真实代码写（turtlebet origin/main：
backend/internal/services/arena_game.go 签名、arena_service.go 各接口语义、controllers/api/arena_controller.go 回包形状），
不是照文档想象：

① 扮演主站被我们调（发件箱 / 网关调 /player）：POST /api/arena-hook/{player|defense|pet-level|started|settle|unlinked}
   · Content-Type 不是 application/json ⇒ 415；验签不过（缺头 / 签名错 / 时差 > 300 秒 / 改了请求体）⇒ 401 {ok:false, error:"bad arena signature"}；
     JSON 坏 ⇒ 400 {ok:false, error:"bad json"}；业务失败 ⇒ HTTP 200 + {ok:false, error}（与主站同一套字样）
   · userId 不是对外编码 ID（纯数字 / 带符号）⇒ bad userId；defense / unlinked 对没注册的用户 ⇒ user not found
   · pet-level：等级 1 ~ 999 之外 ⇒ invalid level；没拥有 ⇒ pet not owned
   · started：只对 pending；已开算 ⇒ 原样回 ok 与原 expireAt；过期 ⇒ raid N expired；开算 ⇒ expireAt = 现在 + 30 分钟
   · settle：attacker / defender / void；同一场重复、结果相同 ⇒ ok（幂等）；结果不同或已作废 ⇒ ok:false；过期 ⇒ ok:false
② 扮演主站调我们（网关）：link_info（GET，签 ts + "."）、link_confirm、create_raid（POST gameServerURL；同时在假主站里登记这场偷袭，
   状态 pending、排队截止 6 小时，之后的 started / settle 才对得上）
③ 故障注入：inject(topic, kind, n) —— http500 / http502 / http401 / drop（不回包直接断）/ slow（睡 12 秒）

命令行（本机联调）：
  python tools/mock_mainsite.py serve [--port 8799] [--user GEACjjPJERy:basic,stone] …
  python tools/mock_mainsite.py link-info    --base http://127.0.0.1:8790 --code <码>
  python tools/mock_mainsite.py link-confirm --base http://127.0.0.1:8790 --code <码> --user GEACjjPJERy
  python tools/mock_mainsite.py raid --url http://127.0.0.1:8790/mainsite/raid --raid-id 1 --attacker A… --defender B…
密钥：环境变量 MAINSITE_HOOK_SECRET 或 MAINSITE_HOOK_SECRET_FILE（与网关 / 发件箱同一个读法），都没有 ⇒ --secret-file。
★只用标准库；本机代理会改写 POST body（memory fb-local-proxy-corrupts-post-body）⇒ 一律 ProxyHandler({})。
"""
import argparse
import http.server
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "server", "referee"))
import mainsite_sign as MS  # noqa: E402

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
TOPICS = ("player", "defense", "pet-level", "started", "settle", "unlinked")
RAID_TIMEOUT_MIN = 30          # 主站后台 arena.raidTimeoutMinutes 默认值
QUEUE_TIMEOUT_MIN = 360        # arena.queueTimeoutMinutes（建任务后 6 小时还没开算 ⇒ 作废）
_UID_RE = re.compile(r"^[0-9A-Za-z]{4,32}$")


def user_id_ok(s) -> bool:
    """主站 arenaUserId 的替身：对外编码 ID 是 base62；纯数字主站当内部 ID 拒掉。"""
    s = str(s or "").strip()
    return bool(_UID_RE.match(s)) and not s.isdigit()


class State:
    """假主站的全部状态（线程安全：一把锁）。时钟默认真时钟，门禁可换成假的（毫秒）。"""

    def __init__(self, clock_ms=None):
        self.lock = threading.Lock()
        self.users = {}            # userId → {pets: {key: level}, linked, has_defense, rating, device}
        self.raids = {}            # raidId → {status, result, started_at, expire_at, match_id}
        self.calls = []            # (topic, body, http 状态, 回包) —— 按到达顺序
        self.faults = []           # [topic 或 None, kind, 剩余次数]
        self.clock_ms = clock_ms or (lambda: int(time.time() * 1000))

    def add_user(self, uid, pets=(), linked=False):
        with self.lock:
            self.users[uid] = {"pets": {k: 1 for k in pets}, "linked": linked, "has_defense": False,
                               "rating": 0, "device": ""}

    def add_raid(self, raid_id, queue_min=QUEUE_TIMEOUT_MIN):
        with self.lock:
            self.raids[int(raid_id)] = {"status": "pending", "result": "", "started_at": 0,
                                        "expire_at": self.clock_ms() + queue_min * 60000, "match_id": ""}

    def inject(self, topic, kind, n=1):
        with self.lock:
            self.faults.append([topic, kind, n])

    def take_fault(self, topic):
        with self.lock:
            for f in self.faults:
                if (f[0] is None or f[0] == topic) and f[2] > 0:
                    f[2] -= 1
                    return f[1]
        return None

    def topics(self):
        with self.lock:
            return [c[0] for c in self.calls]

    # ── 各接口（照 arena_service.go）──
    def player(self, b):
        uid = str(b.get("userId", ""))
        if not user_id_ok(uid):
            return {"ok": False, "error": "bad userId"}
        u = self.users.get(uid)
        return {"ok": True, "userId": uid, "turtles": sorted((u or {}).get("pets", {}))}

    def defense(self, b):
        uid = str(b.get("userId", ""))
        if not user_id_ok(uid):
            return {"ok": False, "error": "bad userId"}
        u = self.users.get(uid)
        if u is None:
            return {"ok": False, "error": "user not found"}
        u["has_defense"] = bool(b.get("hasDefense"))
        u["rating"] = int(b.get("rating") or 0)
        dev = str(b.get("device") or "").strip()
        if dev:
            u["device"] = dev[:128]
        return {"ok": True}

    def pet_level(self, b):
        uid = str(b.get("userId", ""))
        if not user_id_ok(uid):
            return {"ok": False, "error": "bad userId"}
        lv = b.get("level")
        if not isinstance(lv, int) or isinstance(lv, bool) or lv < 1 or lv > 999:
            return {"ok": False, "error": "invalid level: %s" % lv}
        u = self.users.get(uid)
        key = str(b.get("petKey") or "").strip()
        if u is None or not key or key not in u["pets"]:
            return {"ok": False, "error": "pet not owned"}
        u["pets"][key] = lv
        return {"ok": True}

    def started(self, b):
        rid = b.get("raidId")
        r = self.raids.get(rid) if isinstance(rid, int) else None
        if r is None:
            return {"ok": False, "error": "raid not found"}
        if r["status"] != "pending":
            return {"ok": False, "error": "raid %d is %s" % (rid, r["status"])}
        if r["started_at"] > 0:
            return {"ok": True, "expireAt": r["expire_at"]}
        now = self.clock_ms()
        if r["expire_at"] > 0 and now > r["expire_at"]:
            return {"ok": False, "error": "raid %d expired" % rid}
        r["started_at"] = now
        r["expire_at"] = now + RAID_TIMEOUT_MIN * 60000
        return {"ok": True, "expireAt": r["expire_at"]}

    def settle(self, b):
        result = b.get("result")
        if result not in ("attacker", "defender", "draw", "void"):
            return {"ok": False, "error": "invalid result: %s" % json.dumps(result)}
        rid = b.get("raidId")
        r = self.raids.get(rid) if isinstance(rid, int) else None
        if r is None:
            return {"ok": False, "error": "raid not found"}
        if r["status"] == "settled" or (r["status"] == "refunded" and r["result"] == "void"):
            if r["result"] == result:
                return {"ok": True, "status": r["status"], "result": r["result"]}
            return {"ok": False, "error": "raid %d already settled as %s" % (rid, r["result"])}
        if r["status"] != "pending":
            return {"ok": False, "error": "raid %d is %s" % (rid, r["status"])}
        if r["expire_at"] > 0 and self.clock_ms() > r["expire_at"]:
            return {"ok": False, "error": "raid %d expired" % rid}
        r["status"] = "refunded" if result == "void" else "settled"
        r["result"] = result
        r["match_id"] = str(b.get("matchId") or "").strip()
        return {"ok": True, "status": r["status"], "result": r["result"]}

    def unlinked(self, b):
        uid = str(b.get("userId", ""))
        if not user_id_ok(uid):
            return {"ok": False, "error": "bad userId"}
        u = self.users.get(uid)
        if u is None:
            return {"ok": False, "error": "user not found"}
        u["linked"] = False
        u["has_defense"] = False
        return {"ok": True}

    def dispatch(self, topic, body):
        fn = {"player": self.player, "defense": self.defense, "pet-level": self.pet_level,
              "started": self.started, "settle": self.settle, "unlinked": self.unlinked}[topic]
        with self.lock:
            return fn(body)


class _Handler(http.server.BaseHTTPRequestHandler):
    server_version = "mock-mainsite"
    sys_version = ""
    timeout = 15

    def log_message(self, fmt, *args):      # 门禁输出保持干净；serve 子命令另开 verbose
        if getattr(self.server, "verbose", False):
            sys.stderr.write("mock-mainsite %s\n" % (fmt % args))

    def _reply(self, code, obj):
        raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        self._reply(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        st = self.server.state
        path = urllib.parse.urlsplit(self.path).path
        pre = "/api/arena-hook/"
        topic = path[len(pre):] if path.startswith(pre) else ""
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(min(n, 64 * 1024)) if n > 0 else b""
        if topic not in TOPICS:
            self._reply(404, {"ok": False, "error": "not found"})
            return
        fault = st.take_fault(topic)
        if fault == "drop":
            with st.lock:
                st.calls.append((topic, None, 0, None))
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            return
        if fault == "slow":
            time.sleep(12)
        if fault in ("http500", "http502"):
            with st.lock:
                st.calls.append((topic, None, int(fault[4:]), None))
            self.send_response(int(fault[4:]))
            self.send_header("Content-Length", "4")
            self.end_headers()
            self.wfile.write(b"boom")
            return
        code, rep, body = 200, None, None
        if not (self.headers.get("Content-Type") or "").lower().startswith("application/json"):
            code, rep = 415, {"ok": False, "error": "Content-Type must be application/json"}
        elif fault == "http401" or not MS.verify(self.server.secret, self.headers.get(MS.HDR_TS),
                                                 self.headers.get(MS.HDR_SIG), raw):   # 验签用真时钟（发方也用真时钟签）
            code, rep = 401, {"ok": False, "error": "bad arena signature"}
        else:
            try:
                body = json.loads(raw.decode("utf-8"))
                if not isinstance(body, dict):
                    raise ValueError("not an object")
            except ValueError:
                code, rep = 400, {"ok": False, "error": "bad json"}
            else:
                rep = st.dispatch(topic, body)
        with st.lock:
            st.calls.append((topic, body, code, rep))
        self._reply(code, rep)


def start(secret, state=None, port=0, bind="127.0.0.1", verbose=False):
    """起一个假主站（后台线程）。返回 (server, base_url)；server.state 就是 State。用完 server.shutdown()。"""
    srv = http.server.ThreadingHTTPServer((bind, port), _Handler)
    srv.daemon_threads = True
    srv.secret = secret
    srv.state = state or State()
    srv.verbose = verbose
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, "http://%s:%d" % (bind, srv.server_address[1])


# ─────────────────────────────── 扮演主站调我们 ───────────────────────────────

def _call(method, url, secret, body_bytes, ts=None, timeout=10.0):
    """返回 (HTTP 状态, 解析后的回包或 None)。连不上 ⇒ (0, None)。主站一律 10 秒超时。"""
    hdr = MS.headers(secret, body_bytes, now=ts)
    if body_bytes is not None:
        hdr["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body_bytes, method=method, headers=hdr)
    try:
        with OPENER.open(req, timeout=timeout) as r:
            code, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        code, raw = e.code, e.read()
    except (urllib.error.URLError, OSError):
        return 0, None
    try:
        return code, json.loads(raw.decode("utf-8")) if raw else None
    except ValueError:
        return code, None


def go_json(obj) -> bytes:
    """Go json.Marshal 的样子：紧凑、无空格（map 按键排序由调用方给定顺序；struct 按字段顺序）。"""
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def link_info(base, secret, code, ts=None):
    """= ArenaGameClient.LinkInfo：GET /mainsite/link/info?code=…，没有请求体，签 ts + "."。"""
    return _call("GET", base.rstrip("/") + "/mainsite/link/info?code=" + urllib.parse.quote(code, safe=""),
                 secret, None, ts=ts)


def link_confirm(base, secret, code, user_id, ts=None):
    """= ArenaGameClient.ConfirmLink：json.Marshal(map[string]string{code, user_id})（Go 的 map 按键排序）。"""
    return _call("POST", base.rstrip("/") + "/mainsite/link/confirm", secret,
                 go_json({"code": code, "user_id": user_id}), ts=ts)


def raid_body(raid_id, attacker, defender, seed=123456789, stake=50, is_revenge=False, expire_at=None, state=None):
    """= ArenaRaidJobRequest（struct 字段顺序）。expire_at 默认 = 现在 + 6 小时（毫秒）。"""
    if expire_at is None:
        now = state.clock_ms() if state is not None else int(time.time() * 1000)
        expire_at = now + QUEUE_TIMEOUT_MIN * 60000
    return {"raidId": int(raid_id), "attacker": attacker, "defender": defender, "seed": int(seed),
            "stake": int(stake), "isRevenge": bool(is_revenge), "expireAt": int(expire_at)}


def create_raid(url, secret, body, state=None, ts=None):
    """= ArenaGameClient.CreateRaidJob：POST gameServerURL。state 给了 ⇒ 先在假主站登记这场（pending）。"""
    if state is not None:
        state.add_raid(body["raidId"])
    return _call("POST", url, secret, go_json(body), ts=ts)


# ─────────────────────────────── 命令行 ───────────────────────────────

def _secret(a):
    s = MS.load_secret()
    if not s and a.secret_file:
        with open(a.secret_file, encoding="utf-8") as f:
            s = f.read().strip()
    if not s:
        raise SystemExit("没有密钥：设 MAINSITE_HOOK_SECRET / MAINSITE_HOOK_SECRET_FILE，或给 --secret-file")
    return s


def main(argv=None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="假主站（龟投）")
    ap.add_argument("--secret-file", default="")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("serve")
    s.add_argument("--port", type=int, default=8799)
    s.add_argument("--bind", default="127.0.0.1")
    s.add_argument("--user", action="append", default=[], help="userId:pet1,pet2（可重复）")
    s.add_argument("--raid", action="append", default=[], type=int, help="预先登记一场 pending 的偷袭（可重复）")
    x = sp.add_parser("link-info")
    x.add_argument("--base", required=True)
    x.add_argument("--code", required=True)
    x = sp.add_parser("link-confirm")
    x.add_argument("--base", required=True)
    x.add_argument("--code", required=True)
    x.add_argument("--user", required=True)
    x = sp.add_parser("raid")
    x.add_argument("--url", required=True)
    x.add_argument("--raid-id", type=int, required=True)
    x.add_argument("--attacker", required=True)
    x.add_argument("--defender", required=True)
    x.add_argument("--seed", type=int, default=123456789)
    x.add_argument("--stake", type=int, default=50)
    a = ap.parse_args(argv)
    sec = _secret(a)
    if a.cmd == "serve":
        st = State()
        for u in a.user:
            uid, _, pets = u.partition(":")
            st.add_user(uid, [p for p in pets.split(",") if p], linked=True)
        for r in a.raid:
            st.add_raid(r)
        srv, base = start(sec, st, port=a.port, bind=a.bind, verbose=True)
        print("假主站在 %s（接口前缀 %s/api/arena-hook/…）；Ctrl+C 停" % (base, base), flush=True)
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            srv.shutdown()
        return 0
    if a.cmd == "link-info":
        print(json.dumps(link_info(a.base, sec, a.code), ensure_ascii=False))
    elif a.cmd == "link-confirm":
        print(json.dumps(link_confirm(a.base, sec, a.code, a.user), ensure_ascii=False))
    elif a.cmd == "raid":
        print(json.dumps(create_raid(a.url, sec, raid_body(a.raid_id, a.attacker, a.defender, a.seed, a.stake)),
                         ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
