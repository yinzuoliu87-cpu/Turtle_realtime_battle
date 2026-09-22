# -*- coding: utf-8 -*-
"""tools/probe_d8_server.py —— D-8 存档同步【服务端】真 Supabase 端到端探针。

★不是门禁(要真网络、会建两个一次性匿名号), 手动跑:  python tools/probe_d8_server.py
★为什么要有它: 门禁(tests/verify_save_sync.gd)喂的是 schema.sql 里写死的回包形状,
  服务端那一半 —— 比较并交换 / RLS / 只能走函数写 / 不登录不能调 —— 只有打真服务器才验得到。
★2026-09-22 首跑 12/12。改了 server/supabase/schema.sql 里 saves / push_save 之后必须重跑。
"""
import json
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
URL = "https://cjefldecsfpnclhfwriw.supabase.co"
KEY = "sb_publishable_tvCm2DPO9SflJHME9K_MGA_u04tG8bi"
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def req(method, path, body=None, token=None, extra=None):
    h = {"apikey": KEY, "Content-Type": "application/json",
         "Authorization": "Bearer " + (token or KEY)}
    if extra:
        h.update(extra)
    r = urllib.request.Request(URL + path, method=method, headers=h,
                               data=None if body is None else json.dumps(body).encode())
    try:
        with op.open(r, timeout=30) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def signup():
    st, d = req("POST", "/auth/v1/signup", {})
    assert st == 200, (st, d)
    return d["user"]["id"], d["access_token"]


results = []


def check(name, cond, detail=""):
    results.append(bool(cond))
    print("  [%s] %s  %s" % ("PASS" if cond else "FAIL", name, detail))


def push(tok, payload, expected):
    return req("POST", "/rest/v1/rpc/push_save",
               {"p_payload": payload, "p_expected_rev": expected, "p_client_version": "e2e-d8"}, tok)


a_id, a_tok = signup()
b_id, b_tok = signup()
print("两个一次性匿名号: A=%s B=%s" % (a_id[:8], b_id[:8]))

print("── ① 比较并交换 ──")
st, r = push(a_tok, {"coins": 1, "who": "first"}, 0)
check("① 云端没有 + expected=0 ⇒ 建行, rev=1", st == 200 and r.get("ok") and r.get("rev") == 1, str(r))
st, r = push(a_tok, {"coins": 999, "who": "stale"}, 0)
check("① ★★拿过期的 expected=0 再推 ⇒ 冲突, 云端当前 rev=1", st == 200 and r.get("ok") is False
      and r.get("reason") == "conflict" and r.get("rev") == 1, str(r))
st, rows = req("GET", "/rest/v1/saves?select=payload,save_rev&account_id=eq." + a_id, token=a_tok)
check("① ★★冲突那次【没有覆盖】云端(还是 first / rev 1)", st == 200 and rows
      and rows[0]["payload"].get("who") == "first" and rows[0]["save_rev"] == 1, str(rows))
st, r = push(a_tok, {"coins": 2, "who": "second"}, 1)
check("① 带着对的 expected=1 ⇒ 覆盖, rev=2", st == 200 and r.get("ok") and r.get("rev") == 2, str(r))
st, rows = req("GET", "/rest/v1/saves?select=payload,save_rev&account_id=eq." + a_id, token=a_tok)
check("① 拉回来是第二份(second / rev 2)", st == 200 and rows and rows[0]["payload"].get("who") == "second"
      and rows[0]["save_rev"] == 2, str(rows))

print("── ② RLS: 只能读自己的 ──")
st, rows = req("GET", "/rest/v1/saves?select=payload&account_id=eq." + a_id, token=a_tok)
check("② ★分母: A 读得到自己那行", st == 200 and len(rows) == 1, "%d 行" % len(rows or []))
st, rows = req("GET", "/rest/v1/saves?select=payload&account_id=eq." + a_id, token=b_tok)
check("② ★★B 用同样的查询读 A 的存档 ⇒ 0 行", st == 200 and rows == [], str(rows))

print("── ③ 绕过函数直接写表 ⇒ 拒 ──")
st, r = req("POST", "/rest/v1/saves", {"account_id": b_id, "payload": {"x": 1}, "save_rev": 0,
                                       "client_version": "e2e"}, b_tok)
check("③ ★★B 直接 INSERT 自己的行 ⇒ 被拒(表上没有写策略, 只能走函数)", st in (401, 403), "HTTP %s %s" % (st, str(r)[:90]))
st, r = req("PATCH", "/rest/v1/saves?account_id=eq." + a_id, {"payload": {"hacked": True}}, a_tok,
            {"Prefer": "return=representation"})
check("③ ★★A 直接 UPDATE 自己的行(绕过版本号) ⇒ 一行都没改", (st in (401, 403)) or (st == 200 and r == []),
      "HTTP %s %s" % (st, str(r)[:90]))
st, rows = req("GET", "/rest/v1/saves?select=payload,save_rev&account_id=eq." + a_id, token=a_tok)
check("③ ★分母: A 的存档还是 second / rev 2(直接写确实没生效)", rows and rows[0]["payload"].get("who") == "second"
      and rows[0]["save_rev"] == 2, str(rows))

print("── ④ 只有 anon key(没登录)调函数 ⇒ 拒 ──")
st, r = req("POST", "/rest/v1/rpc/push_save", {"p_payload": {"x": 1}, "p_expected_rev": 0,
                                              "p_client_version": "e2e"})
check("④ ★★不带用户令牌调 push_save ⇒ 被拒(已从 anon 收回执行权)", st in (401, 403, 404),
      "HTTP %s %s" % (st, str(r)[:100]))
st, r = push(b_tok, {"coins": 5}, 0)
check("④ ★分母: 同样的调用带上 B 的用户令牌 ⇒ 成功(证明上一条不是函数本身坏了)",
      st == 200 and r.get("ok") is True, str(r))

print("")
print("══ %d/%d 通过 ══" % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
