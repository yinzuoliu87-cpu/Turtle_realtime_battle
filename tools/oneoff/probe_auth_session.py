# -*- coding: utf-8 -*-
"""tools/oneoff/probe_auth_session.py —— 「网关给指定账号签发登录态」可行性探针（2026-11-09 · 主站对接 A1）。

★只连内测服（写死 BETA_REF，参数里出现正式服 ref 直接拒）。不是门禁：要真网络、会建一个临时匿名号，跑完删掉。
网关 /app/link/poll 的 switched:true 情形要把 App 切到「这个主站用户早先绑定的那个号」，Supabase 没有「直接给某用户发 session」的
管理接口；官方做法是 管理员 generate_link（magiclink）→ /auth/v1/verify（token_hash）换出 session。generate_link 要 email，
匿名号没有 ⇒ 先用管理接口给它补一个内部邮箱（email_confirm: true，不发信）。
★③④⑤ 调的是网关自己的 mainsite_gateway.SupabaseAdmin（account_of / issue_session），探针里不另抄一份步骤。逐步量：
  ① 建临时匿名号（/auth/v1/signup {}）
  ② 管理接口读它：email 空、is_anonymous = true；②' 网关 account_of(它的 access_token) = 它、坏令牌 = None
  ③ 补内部邮箱 <uid>@<域名>（email_confirm）—— 之后 is_anonymous / email_confirmed_at 变成什么
  ④ generate_link magiclink —— 回包里 hashed_token（11-09 首跑：平铺在顶层，另有 action_link / email_otp，不发信）
  ⑤ /auth/v1/verify {type: magiclink, token_hash} —— 换出 access_token / refresh_token，user.id = ①
  ⑥ 新 access_token 调 /auth/v1/user 得到同一个 id；refresh_token 能续（grant_type=refresh_token）
  ⑦ 同一个号第二次签（已有邮箱，跳过 ③）照样成功
  ⑧ 删掉临时号，回读 404
service_role 密钥用管理令牌（~/.supabase/beta-access-token）从 Management API 取，只在内存里，不打印。令牌一律不打印。
用法：python tools/oneoff/probe_auth_session.py [--domain link.turtlearena.xyz]
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import sb_common as S  # noqa: E402

S.stdout_utf8()
S.refuse_prod(" ".join(sys.argv), "probe_auth_session")
REF = S.BETA_REF
URL = S.URLS[REF]
PUB = S.PUBLISHABLE[REF]
DOMAIN = sys.argv[sys.argv.index("--domain") + 1] if "--domain" in sys.argv else "link.turtlearena.xyz"
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def service_key():
    st, keys = S.api(REF, "GET", "/v1/projects/{ref}/api-keys?reveal=true")
    if st != 200 or not isinstance(keys, list):
        raise SystemExit("取 api-keys 失败 HTTP %s" % st)
    for k in keys:      # 新式 secret key 优先，没有再用旧的 service_role JWT
        if k.get("type") == "secret" and k.get("api_key"):
            return k["api_key"], "secret(%s)" % k.get("name")
    for k in keys:
        if k.get("name") == "service_role" and k.get("api_key"):
            return k["api_key"], "legacy service_role"
    raise SystemExit("api-keys 里没有 service key（只列名字）: %s" % [k.get("name") for k in keys])


SVC, SVC_KIND = service_key()
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "server", "referee"))
import mainsite_gateway as GW  # noqa: E402
ADMIN = GW.SupabaseAdmin(URL, SVC, DOMAIN)


def req(method, path, body=None, key=None, bearer=None):
    k = key or PUB
    hdr = {"apikey": k, "Content-Type": "application/json", "Authorization": "Bearer " + (bearer or k),
           S.HDR_CLIENT_VERSION: S.client_version()}
    r = urllib.request.Request(URL + path, method=method, headers=hdr,
                               data=None if body is None else json.dumps(body).encode())
    try:
        with op.open(r, timeout=40) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(t)
        except ValueError:
            return e.code, t[:300]


def shape(d, hide=("access_token", "refresh_token", "hashed_token", "email_otp", "action_link", "token")):
    """只打印键与非机密值（令牌类一律只报「有 / 长度」）。"""
    if not isinstance(d, dict):
        return str(d)[:300]
    out = {}
    for k, v in d.items():
        if k in hide:
            out[k] = "<%d 字>" % len(str(v)) if v else "<空>"
        elif k in ("user", "properties") and isinstance(v, dict):
            out[k] = shape(v)
        elif k in ("identities", "app_metadata", "user_metadata", "factors"):
            out[k] = "…"
        else:
            out[k] = v
    return json.dumps(out, ensure_ascii=False, default=str)[:900]


fails = []


def ok(name, cond, detail=""):
    print(("  [PASS] " if cond else "  [FAIL] ") + name + (("   " + detail) if detail else ""))
    if not cond:
        fails.append(name)


def issue(uid):
    """★用网关自己的 SupabaseAdmin（server/referee/mainsite_gateway.py）签 —— 不在探针里另抄一份步骤。返回 (session 或 None, 记录)。"""
    note = {}
    before = req("GET", "/auth/v1/admin/users/" + uid, key=SVC)[1] or {}
    note["had_email"] = bool(before.get("email"))
    try:
        sess = ADMIN.issue_session(uid)
    except GW.Upstream as ex:
        note["error"] = str(ex)
        return None, note
    after = req("GET", "/auth/v1/admin/users/" + uid, key=SVC)[1] or {}
    note["after"] = {"is_anonymous": after.get("is_anonymous"), "email_confirmed": bool(after.get("email_confirmed_at")),
                     "email_is_internal": after.get("email") == "%s@%s" % (uid, DOMAIN)}
    return sess, note


uid = None
try:
    print("目标: 内测服 %s（service key 类型: %s，不打印）" % (REF, SVC_KIND))
    st, d = req("POST", "/auth/v1/signup", {})
    uid = ((d or {}).get("user") or {}).get("id") if isinstance(d, dict) else None
    ok("① 建临时匿名号 HTTP %s" % st, st == 200 and bool(uid), shape(d))
    if not uid:
        raise SystemExit(1)
    st, u = req("GET", "/auth/v1/admin/users/" + uid, key=SVC)
    ok("② 管理接口读到它: email 空、is_anonymous", st == 200 and not (u or {}).get("email") and (u or {}).get("is_anonymous") is True,
       "HTTP %s is_anonymous=%s email=%r" % (st, (u or {}).get("is_anonymous"), (u or {}).get("email")))
    ok("②' 网关 account_of(App 的 access_token) ⇒ 这个号", ADMIN.account_of(d["access_token"]) == uid)
    ok("②' 网关 account_of(坏令牌) ⇒ None", ADMIN.account_of("not-a-token") is None)
    sess, note = issue(uid)
    print("  记录: " + json.dumps(note, ensure_ascii=False, default=str))
    ok("③④⑤ 网关 issue_session：补内部邮箱 → generate_link → verify 换出 session", bool(sess))
    ok("③ 副作用如实: 补了内部邮箱后 is_anonymous = false", (note.get("after") or {}).get("is_anonymous") is False
       and (note.get("after") or {}).get("email_is_internal") is True)
    if sess:
        ok("⑤ session 里 access_token / refresh_token 都有", bool(sess.get("access_token")) and bool(sess.get("refresh_token")))
        st, me = req("GET", "/auth/v1/user", bearer=sess["access_token"])
        ok("⑥ 新 access_token 调 /auth/v1/user ⇒ 同一个 id", st == 200 and (me or {}).get("id") == uid,
           "HTTP %s is_anonymous=%s" % (st, (me or {}).get("is_anonymous")))
        st, rf = req("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": sess["refresh_token"]})
        ok("⑥ refresh_token 能续", st == 200 and bool((rf or {}).get("access_token")) and ((rf or {}).get("user") or {}).get("id") == uid,
           "HTTP %s" % st)
        sess2, note2 = issue(uid)
        ok("⑦ 第二次签（已有邮箱、不再补）照样成功、换出的是新令牌", bool(sess2) and note2.get("had_email") is True
           and sess2["access_token"] != sess["access_token"], json.dumps(note2, ensure_ascii=False, default=str)[:400])
finally:
    if uid:
        st, _ = req("DELETE", "/auth/v1/admin/users/" + uid, key=SVC)
        st2, _ = req("GET", "/auth/v1/admin/users/" + uid, key=SVC)
        ok("⑧ 删掉临时号（DELETE HTTP %s，回读 HTTP %s）" % (st, st2), st in (200, 204) and st2 == 404)
print("")
print("ALL OK" if not fails else "FAIL x%d: %s" % (len(fails), fails))
sys.exit(0 if not fails else 1)
