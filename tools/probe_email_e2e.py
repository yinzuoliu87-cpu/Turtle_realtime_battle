# -*- coding: utf-8 -*-
"""tools/probe_email_e2e.py —— 绑定邮箱 / 换设备取回 / 存档同步【真邮件】端到端探针。

★不是门禁: 要真网络、要有人去收件箱读验证码、会在生产库里留一个测试账号。手动跑, 分四步:
  python tools/probe_email_e2e.py bind-send          # 设备1 建匿名号, 发绑定码
  python tools/probe_email_e2e.py bind-verify <码>   # 验码(要求返回同一个号) + 推存档
  python tools/probe_email_e2e.py recover-send       # 设备2 建新匿名号, 发取回码
  python tools/probe_email_e2e.py recover-verify <码># 验码(要求拿回设备1 的号) + 拉存档
★收件地址 turtlesupport32+e2e<时刻>@gmail.com: Gmail 的 + 别名投到同一收件箱,
  Supabase 当它是新地址 ⇒ 每跑一次都是全新的绑定, 不会撞 email_exists, 也不占支持邮箱本身。
★2026-09-22 首跑全链路通过(当时用的是 +test)。改了邮件模板 / 发信设置 / 登录相关代码后重跑。
"""
import io
import json
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
URL = "https://cjefldecsfpnclhfwriw.supabase.co"
KEY = "sb_publishable_tvCm2DPO9SflJHME9K_MGA_u04tG8bi"
STATE = os.path.join(os.path.expanduser("~"), ".supabase", "probe_email_e2e_state.json")
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def req(method, path, body=None, tok=None):
    r = urllib.request.Request(URL + path, method=method,
                               data=None if body is None else json.dumps(body).encode(),
                               headers={"apikey": KEY, "Content-Type": "application/json",
                                        "Authorization": "Bearer " + (tok or KEY)})
    try:
        with op.open(r, timeout=40) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def load():
    return json.load(io.open(STATE, encoding="utf-8")) if os.path.exists(STATE) else {}


def save(s):
    io.open(STATE, "w", encoding="utf-8").write(json.dumps(s))


cmd = sys.argv[1]
s = load()
## 每轮一个新的 + 标签(存在状态里, 四步用同一个)
EMAIL = s.get("email") or ("turtlesupport32+e2e%d@gmail.com" % int(__import__("time").time()))

if cmd == "bind-send":
    st, d = req("POST", "/auth/v1/signup", {})
    assert st == 200, (st, d)
    s = {"a_id": d["user"]["id"], "a_tok": d["access_token"], "email": EMAIL}
    print("收件地址: %s" % EMAIL)
    save(s)
    print("设备1 匿名号 A = %s" % s["a_id"][:8])
    st, d = req("PUT", "/auth/v1/user", {"email": EMAIL}, s["a_tok"])
    print("补绑发码 PUT /auth/v1/user → HTTP %d  %s" % (st, str(d)[:160] if st >= 300 else "(已发出)"))

elif cmd == "bind-verify":
    code = sys.argv[2].strip()
    st, d = req("POST", "/auth/v1/verify", {"email": EMAIL, "token": code, "type": "email_change"})
    ok = st == 200 and isinstance(d, dict) and (d.get("user") or {}).get("id")
    print("补绑验码 → HTTP %d" % st + ("" if ok else "  " + str(d)[:200]))
    if ok:
        same = d["user"]["id"] == s["a_id"]
        print("  ★★返回的还是同一个号(补绑=升级不是新建): %s" % same)
        print("  邮箱已绑上: %s" % (d["user"].get("email") == EMAIL))
        s["a_tok"] = d["access_token"]
        save(s)
        st, r = req("POST", "/rest/v1/rpc/push_save",
                    {"p_payload": {"marker": "e2e-mail-0922", "meta_deepsea_coins": 4242},
                     "p_expected_rev": 0, "p_client_version": "e2e-mail"}, s["a_tok"])
        print("  设备1 推存档 → HTTP %d %s" % (st, r))

elif cmd == "recover-send":
    st, d = req("POST", "/auth/v1/signup", {})
    assert st == 200, (st, d)
    s["b_id"] = d["user"]["id"]
    s["b_tok"] = d["access_token"]
    save(s)
    print("设备2 新匿名号 B = %s (换设备后开机就是这样)" % s["b_id"][:8])
    st, d = req("POST", "/auth/v1/otp", {"email": EMAIL, "create_user": False})
    print("取回发码 POST /auth/v1/otp → HTTP %d  %s" % (st, str(d)[:160] if st >= 300 else "(已发出)"))

elif cmd == "recover-verify":
    code = sys.argv[2].strip()
    st, d = req("POST", "/auth/v1/verify", {"email": EMAIL, "token": code, "type": "email"})
    ok = st == 200 and isinstance(d, dict) and (d.get("user") or {}).get("id")
    print("取回验码 → HTTP %d" % st + ("" if ok else "  " + str(d)[:200]))
    if ok:
        got = d["user"]["id"]
        print("  ★★取回的是设备1 那个号 A(不是设备2 的 B): %s" % (got == s["a_id"] and got != s["b_id"]))
        st, rows = req("GET", "/rest/v1/saves?select=payload,save_rev&account_id=eq." + got,
                       tok=d["access_token"])
        p = (rows[0]["payload"] if st == 200 and rows else {})
        print("  ★★★设备2 拉回存档: marker=%s  深海币=%s  rev=%s" % (
            p.get("marker"), p.get("meta_deepsea_coins"), rows[0]["save_rev"] if rows else None))
        print("══ 真邮件全链路: %s ══" % ("通过" if p.get("marker") == "e2e-mail-0922" and got == s["a_id"] else "★没通过"))
        os.remove(STATE)
else:
    raise SystemExit("未知命令")
