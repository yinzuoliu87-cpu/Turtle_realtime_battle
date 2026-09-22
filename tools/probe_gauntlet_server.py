# -*- coding: utf-8 -*-
"""tools/probe_gauntlet_server.py —— 周六闯关赛快照池的【真服务器】端到端探针。

★不是门禁: 要真网络、会在生产库里留两个匿名测试账号与几行快照。手动跑:
      python tools/probe_gauntlet_server.py
★为什么非跑不可: `gauntlet_ghosts` 表是我建的、客户端代码是我写的,
  但在这个探针之前**从来没有任何客户端真的跟那张表说过话**。
  「SQL 执行了没报错」「GDScript 编译过了」都不等于这条路通
  (memory `fb-verify-artifact-not-steps`: 产物才是判据, 不是中间步骤)。

验这七件事(每条都配了分母, 不让"恰好没出错"冒充"规则生效"):
  ① 能写自己的行
  ② 同一格再写一次 = 覆盖(upsert), 不是撞主键报 409  —— 「每场都传」靠这个
  ③ 同一个人不同标签的行**并存**(主键含 gw/gl) —— 否则后来者按自己那格找不到人
  ④ 按标签查, **只**查得到同标签的(3-1 查不到 3-2/2-1/4-0)
  ⑤ 查询里带 `account_id=neq.自己` ⇒ 查不到自己
  ⑥ **RLS**: B 改不了 A 的行(写别人的行要被拒)
  ⑦ 分母: 把 ④ 的条件换成对方那一格, **就查得到** —— 证明 ④ 不是"库里本来就空"
"""
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
URL = "https://cjefldecsfpnclhfwriw.supabase.co"
KEY = "sb_publishable_tvCm2DPO9SflJHME9K_MGA_u04tG8bi"
## ★本机代理会改写 POST body(memory `fb-local-proxy-corrupts-post-body`) ⇒ 一律绕开
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
WEEK = 1789344000            # 2026-09-14 周一锚点(固定值, 与线上真数据不同周, 互不干扰)
OK = [0]
BAD = [0]


def chk(name, cond, detail=""):
    if cond:
        OK[0] += 1
        print("  [PASS] %s%s" % (name, ("  " + detail) if detail else ""))
    else:
        BAD[0] += 1
        print("  [FAIL] %s  %s" % (name, detail))


def req(method, path, body=None, tok=None, extra=None):
    h = {"apikey": KEY, "Content-Type": "application/json",
         "Authorization": "Bearer " + (tok or KEY)}
    if extra:
        h.update(extra)
    r = urllib.request.Request(URL + path, method=method,
                               data=None if body is None else json.dumps(body).encode(),
                               headers=h)
    try:
        with OP.open(r, timeout=40) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def row(acc, gw, gl, marker):
    return {"account_id": acc, "season_week": WEEK, "gw": gw, "gl": gl,
            "snapshot": {"ghost_id": "probe_%s_%d-%d" % (marker, gw, gl),
                         "name": marker, "avatar": "basic",
                         "gl_w": gw, "gl_l": gl, "gl_ts": int(time.time())},
            "client_version": "probe"}


UPSERT = {"Prefer": "resolution=merge-duplicates,return=minimal"}

print("=== 闯关快照池 · 真服务器端到端 ===")

## 两个匿名号 = 两台设备
st, a = req("POST", "/auth/v1/signup", {})
st2, b = req("POST", "/auth/v1/signup", {})
chk("★分母: 两个匿名号都建出来了", st == 200 and st2 == 200 and a and b,
    "HTTP %d / %d" % (st, st2))
if not (a and b):
    sys.exit(1)
A, AT = a["user"]["id"], a["access_token"]
B, BT = b["user"]["id"], b["access_token"]
print("  设备A=%s  设备B=%s" % (A[:8], B[:8]))

## ① 写自己的行
st, d = req("POST", "/rest/v1/gauntlet_ghosts", row(A, 3, 1, "A31"), AT, UPSERT)
chk("① 设备A 写 3-1 的行", st in (200, 201, 204), "HTTP %d %s" % (st, str(d)[:120]))

## ② 同一格再写 = 覆盖, 不是 409
st, d = req("POST", "/rest/v1/gauntlet_ghosts", row(A, 3, 1, "A31b"), AT, UPSERT)
chk("② ★同一格再传一次是【覆盖】不是撞主键(每场都传靠这个)",
    st in (200, 201, 204), "HTTP %d %s" % (st, str(d)[:120]))

## ③ 同一个人不同标签的行并存
st, d = req("POST", "/rest/v1/gauntlet_ghosts", row(A, 3, 2, "A32"), AT, UPSERT)
chk("③ 设备A 再写 3-2 的行", st in (200, 201, 204), "HTTP %d" % st)
st, rows = req("GET", "/rest/v1/gauntlet_ghosts?season_week=eq.%d&account_id=eq.%s"
               "&select=gw,gl&order=gw.asc" % (WEEK, A), tok=AT)
labs = sorted(["%d-%d" % (r["gw"], r["gl"]) for r in rows]) if isinstance(rows, list) else []
chk("③ ★同一个人的两格**并存**(主键含 gw/gl ⇒ 后来者按自己那格找得到人)",
    labs == ["3-1", "3-2"], str(labs))

## 设备B 也写几格, 好让 ④ 有东西可查
for gw, gl, m in [(3, 1, "B31"), (2, 1, "B21"), (4, 0, "B40")]:
    req("POST", "/rest/v1/gauntlet_ghosts", row(B, gw, gl, m), BT, UPSERT)

## ④ 按标签查: 只看得到同标签的
q = ("/rest/v1/gauntlet_ghosts?season_week=eq.%d&gw=eq.3&gl=eq.1&account_id=neq.%s"
     "&select=snapshot,gw,gl") % (WEEK, A)
st, rows = req("GET", q, tok=AT)
got = [(r["gw"], r["gl"]) for r in rows] if isinstance(rows, list) else []
chk("④ ★分母: 这一格确实查到了东西(0 行的话下面全是空检查)", len(got) > 0, str(got))
chk("④ ★★查回来的**每一行**都是 3-1(永不跨标签)",
    all(g == (3, 1) for g in got), str(got))
chk("④ ★一行都不是 3-2 / 2-1 / 4-0",
    not any(g in [(3, 2), (2, 1), (4, 0)] for g in got), str(got))

## ⑤ 查不到自己
ids = [r.get("snapshot", {}).get("name", "") for r in rows] if isinstance(rows, list) else []
chk("⑤ ★查询带 account_id=neq.自己 ⇒ 结果里没有自己那份",
    not any(str(x).startswith("A3") for x in ids), str(ids))

## ⑥ 分母: 换成设备B 的视角查 3-2, 就该看到 A 那份 —— 证明 ④ 不是"库里本来就空"
st, rows2 = req("GET", "/rest/v1/gauntlet_ghosts?season_week=eq.%d&gw=eq.3&gl=eq.2"
                "&account_id=neq.%s&select=snapshot" % (WEEK, B), tok=BT)
names2 = [r.get("snapshot", {}).get("name", "") for r in rows2] if isinstance(rows2, list) else []
chk("⑥ ★★分母: 设备B 查 3-2 【看得到】A 那份 —— 证明 ④ 是标签挡住的, 不是库里没数据",
    any(str(x).startswith("A32") for x in names2), str(names2))

## ⑦ RLS: B 写不了 A 的行
st, d = req("POST", "/rest/v1/gauntlet_ghosts", row(A, 0, 0, "B伪造"), BT, UPSERT)
chk("⑦ ★★RLS: 设备B 写【A 的 account_id】被拒(否则谁都能改别人的阵容)",
    st not in (200, 201, 204), "HTTP %d %s" % (st, str(d)[:140]))
st, chk_rows = req("GET", "/rest/v1/gauntlet_ghosts?season_week=eq.%d&account_id=eq.%s"
                   "&gw=eq.0&gl=eq.0&select=gw" % (WEEK, A), tok=AT)
chk("⑦ ★分母: 那一行确实没落库", isinstance(chk_rows, list) and len(chk_rows) == 0,
    str(chk_rows))

print("")
print("══ 真服务器端到端: %d 通过 / %d 失败 ══" % (OK[0], BAD[0]))
print("⚠ 生产库里留下了两个匿名测试号与几行 season_week=%d 的快照(与线上真周不同, 互不干扰)。" % WEEK)
sys.exit(1 if BAD[0] else 0)
