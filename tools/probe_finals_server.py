# -*- coding: utf-8 -*-
"""tools/probe_finals_server.py —— 周日决赛日赛程推进的【真服务器】端到端探针。

★不是门禁: 要真网络、要管理员令牌、会在生产库里留两个匿名测试账号。手动跑:
      python tools/probe_finals_server.py

★为什么非跑不可: 表建了、函数建了、pg_cron 装了 —— 这三件都只证明
  「SQL 执行没报错」。**没有一件证明这条路会动**
  (memory `fb-verify-artifact-not-steps`: 产物才是判据, 不是中间步骤)。
  尤其推进器是个**定时才会被叫到**的东西: 它是这个项目里第一个
  「没人点按钮也会发生」的逻辑, 写错了不会有任何人看见。

验这十四件事。★每条「不该发生」都配了分母 ——
  「推进器返回 0」既可能是"规则挡住了", 也可能是"库里根本没有桶",
  不配分母就分不出来(memory `fb-gate-tautological-when-it-spans-a-frame` 同族):

  ① 分母: 桶建起来了, `finals_view` 拿得到 n / round / 四个参赛者
  ② **不剧透**: 第一轮结果已经在库里了, 但 round 还是 1 ⇒ 回包 `done` 是空的
  ③ 分母: 推进到第 2 轮之后, `done` 里**就有**了 1-0 / 1-1 —— 证明 ② 不是"库里没结果"
  ④ **不早推**: 本轮刚开始(round_at = now) + 结果齐 ⇒ 推进器返回 0, round 不动
  ⑤ 分母: 把 round_at 挪到 10 分钟前 ⇒ 推进器返回 1, round 变 2
  ⑥ **没打完不推**: 第 2 轮时间到了但没有结果 ⇒ 返回 0, round 还是 2
  ⑦ 分母: 补上第 2 轮结果 ⇒ 返回 1, 且 closed = true
  ⑧ **收盘后冠军才公布**: done 里出现 2-0（这一条是探针写到一半才发现的洞:
     round 停在最后一轮 ⇒ `r.round < b.round` 把决赛结果自己永久挡掉）
  ⑨ 收盘的桶不再被推: 再叫一次返回 0
  ⑩ **客户端直读结果表 = 0 行**(没有 select 策略); 分母: 管理员看得见 3 行
  ⑪ 参赛者阵容快照**不下发**(看图不需要, 别把 28 只龟塞给每个观众)
  ⑫ anon 调 `finals_view` 被拒
  ⑬ 登录用户调 `finals_advance` **被拒**(不是"返回 0"是调不动 —— 只有 pg_cron 能推)
  ⑭ **pg_cron 真的会跑**: 临时挂一个每分钟的任务, 等它真的写进库里
     —— 「装上了」不等于「会响」(memory `fb-wake-by-background-task-not-schedulewakeup` 同族)
"""
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
PROJ = "cjefldecsfpnclhfwriw"
URL = "https://cjefldecsfpnclhfwriw.supabase.co"
KEY = "sb_publishable_tvCm2DPO9SflJHME9K_MGA_u04tG8bi"
TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".supabase", "access-token")
## ★本机代理会改写 POST body(memory `fb-local-proxy-corrupts-post-body`) ⇒ 一律绕开
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
WEEK = 2                     # ★假周号: cron 传的是真周一时间戳(~1.79e9), 永远碰不到这里
BUCKET = 0
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT_BIN = os.environ.get("GODOT",
    r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe")
OK = [0]
BAD = [0]


def chk(name, cond, detail=""):
    if cond:
        OK[0] += 1
        print("  [PASS] %s%s" % (name, ("  " + detail) if detail else ""))
    else:
        BAD[0] += 1
        print("  [FAIL] %s  %s" % (name, detail))


# ── 管理员通道(跑 SQL: 造数据 / 直接叫推进器 / 回读真相) ──
def sql(q):
    tok = io.open(TOKEN_FILE, encoding="utf-8").read().strip()
    r = urllib.request.Request(
        "https://api.supabase.com/v1/projects/%s/database/query" % PROJ,
        method="POST", data=json.dumps({"query": q}).encode(),
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with OP.open(r, timeout=90) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


# ── 客户端通道(就是游戏里走的那条: anon key + 用户令牌) ──
def req(method, path, body=None, tok=None):
    h = {"apikey": KEY, "Content-Type": "application/json",
         "Authorization": "Bearer " + (tok or KEY)}
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


def advance():
    """直接叫推进器(管理员身份) —— 和 pg_cron 每分钟干的事完全一样。"""
    st, d = sql("select public.finals_advance(%d) as moved" % WEEK)
    if isinstance(d, list) and d:
        return int(d[0]["moved"])
    return -1


def bucket_row():
    st, d = sql("""select round, closed, extract(epoch from round_at)::bigint as rat
                   from public.finals_buckets
                   where season_week = %d and bucket_no = %d""" % (WEEK, BUCKET))
    return d[0] if isinstance(d, list) and d else {}


def view(tok):
    return req("POST", "/rest/v1/rpc/finals_view",
               {"p_week": WEEK, "p_bucket": BUCKET}, tok)


print("=== 周日决赛日 · 赛程推进 · 真服务器端到端 ===")

# ─────────────────────────────────────────────────────────────
# 造场子: 两个匿名号当四个参赛者(主键含 seed, 同一个号可以坐两个位子)
# ─────────────────────────────────────────────────────────────
st, a = req("POST", "/auth/v1/signup", {})
st2, b = req("POST", "/auth/v1/signup", {})
if not (isinstance(a, dict) and a.get("access_token")):
    print("  [FAIL] 匿名注册失败: %s %s" % (st, str(a)[:200]))
    sys.exit(1)
TA, IA = a["access_token"], a["user"]["id"]
TB, IB = b["access_token"], b["user"]["id"]
print("  两个测试号已开: %s… / %s…" % (IA[:8], IB[:8]))

sql("delete from public.finals_results  where season_week = %d" % WEEK)
sql("delete from public.finals_entrants where season_week = %d" % WEEK)
sql("delete from public.finals_buckets  where season_week = %d" % WEEK)
st, d = sql("""
insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
  values (%d, %d, 4, 1, now(), false);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  values (%d,%d,0,'%s','探针甲','{"pets":[1,2,3]}'::jsonb),
         (%d,%d,1,'%s','探针乙','{"pets":[4,5,6]}'::jsonb),
         (%d,%d,2,'%s','探针丙','{"pets":[7,8,9]}'::jsonb),
         (%d,%d,3,'%s','探针丁','{"pets":[10,11,12]}'::jsonb);
""" % (WEEK, BUCKET, WEEK, BUCKET, IA, WEEK, BUCKET, IB,
       WEEK, BUCKET, IA, WEEK, BUCKET, IB))
if st not in (200, 201):
    print("  [FAIL] 造场子失败: %s %s" % (st, str(d)[:300]))
    sys.exit(1)

# ─────────────────────────────────────────────────────────────
print("── ① 分母: 桶拿得到 ──")
st, v = view(TA)
chk("① finals_view 通了", st == 200 and isinstance(v, dict) and v.get("ok") is True,
    "HTTP %s %s" % (st, str(v)[:160]))
chk("① n = 4 / round = 1", v.get("n") == 4 and v.get("round") == 1, str(v)[:120])
ents = v.get("entrants") or []
chk("① ★分母: 四个参赛者都在, 种子 0~3 顺序对",
    [e["seed"] for e in ents] == [0, 1, 2, 3] and
    [e["name"] for e in ents] == ["探针甲", "探针乙", "探针丙", "探针丁"],
    str([e.get("name") for e in ents]))
chk("① ★回包带了 next_at(客户端不必知道「一轮多长」)",
    int(v.get("next_at", 0)) - int(v.get("round_at", 0)) == 480,
    "next_at - round_at = %d" % (int(v.get("next_at", 0)) - int(v.get("round_at", 0))))
st, nv = req("POST", "/rest/v1/rpc/finals_view", {"p_week": WEEK, "p_bucket": 99}, TA)
chk("① ★分母: 不存在的桶 ⇒ ok=false(证明 ok=true 有内容)",
    isinstance(nv, dict) and nv.get("ok") is False and nv.get("reason") == "no_bucket",
    str(nv)[:120])

# ─────────────────────────────────────────────────────────────
print("── ①b 「我那个桶」自己查得到 ──")
## 客户端并不知道自己被分到哪个桶(分桶是服务端做的) ⇒ p_bucket < 0 = 「我那个」
st, mv = req("POST", "/rest/v1/rpc/finals_view", {"p_week": WEEK, "p_bucket": -1}, TA)
chk("①b ★p_bucket=-1 ⇒ 自己查出我在 %d 号桶" % BUCKET,
    isinstance(mv, dict) and mv.get("ok") is True and int(mv.get("bucket", -9)) == BUCKET,
    str(mv)[:140])
chk("①b ★分母: 拿到的就是同一个桶(n / round 对得上)",
    int(mv.get("n", 0)) == 4 and int(mv.get("round", 0)) == 1, str(mv)[:120])
## ★反面: 没报名的人查「我那个桶」要被拒 —— 不能悄悄拿到别人的桶
sql("""delete from public.finals_entrants
       where season_week = %d and bucket_no = %d and seed in (1,3)""" % (WEEK, BUCKET))
st, ne = req("POST", "/rest/v1/rpc/finals_view", {"p_week": WEEK, "p_bucket": -1}, TB)
chk("①b ★★没报名的人 ⇒ not_entered(而不是拿到别人的桶)",
    isinstance(ne, dict) and ne.get("ok") is False and ne.get("reason") == "not_entered",
    str(ne)[:140])
sql("""insert into public.finals_entrants (season_week,bucket_no,seed,account_id,name,snapshot)
       values (%d,%d,1,'%s','探针乙','{}'::jsonb),
              (%d,%d,3,'%s','探针丁','{}'::jsonb)"""
    % (WEEK, BUCKET, IB, WEEK, BUCKET, IB))

print("── ② 不剧透: 当前轮的结果根本不下发 ──")
sql("""insert into public.finals_results
         (season_week,bucket_no,round,match_no,winner_side,seed_used)
       values (%d,%d,1,0,0,111),(%d,%d,1,1,1,222)"""
    % (WEEK, BUCKET, WEEK, BUCKET))
st, cnt = sql("select count(*)::int as c from public.finals_results where season_week = %d" % WEEK)
have = int(cnt[0]["c"]) if isinstance(cnt, list) else -1
chk("② ★分母: 库里**确实已经有**两场结果了(否则下面「拿不到」是恒真)", have == 2, "%d 行" % have)
st, v = view(TA)
chk("② ★★round=1 时, 回包 done 是空的 —— 当前轮的胜负一个字都没下发",
    v.get("done") == {}, str(v.get("done")))

# ─────────────────────────────────────────────────────────────
print("── ③④⑤ 推进器: 时间没到不推, 到了才推 ──")
before = bucket_row()
moved = advance()
after = bucket_row()
chk("④ ★★本轮刚开始(round_at=now) ⇒ 推进器返回 0", moved == 0, "moved=%d" % moved)
chk("④ ★round 没动", int(after.get("round", -1)) == 1, str(after))

sql("""update public.finals_buckets set round_at = now() - interval '10 minutes'
       where season_week = %d and bucket_no = %d""" % (WEEK, BUCKET))
moved = advance()
after = bucket_row()
chk("⑤ ★分母: 时间挪到 10 分钟前 ⇒ 返回 1(证明 ④ 不是「库里没桶」)", moved == 1, "moved=%d" % moved)
chk("⑤ round 变成 2, round_at 重置成刚才", int(after.get("round", -1)) == 2, str(after))
chk("⑤ ★round_at 被刷新了(不是沿用旧的)",
    int(after.get("rat", 0)) > int(before.get("rat", 0)),
    "%s → %s" % (before.get("rat"), after.get("rat")))

st, v = view(TA)
chk("③ ★★翻面之后, 第一轮的胜负**就能拿到了**(证明 ② 是规则挡的, 不是库里空的)",
    v.get("done") == {"1-0": 0, "1-1": 1}, str(v.get("done")))
chk("③ ★而第 2 轮(当前轮)还是拿不到", "2-0" not in (v.get("done") or {}), str(v.get("done")))

# ─────────────────────────────────────────────────────────────
print("── ⑥⑦ 没打完不推 ──")
sql("""update public.finals_buckets set round_at = now() - interval '10 minutes'
       where season_week = %d and bucket_no = %d""" % (WEEK, BUCKET))
moved = advance()
after = bucket_row()
chk("⑥ ★★时间到了但第 2 轮没有结果 ⇒ 返回 0(宁可晚一分钟, 不能翻没结果的一轮)",
    moved == 0, "moved=%d" % moved)
chk("⑥ ★round 还是 2 且没收盘",
    int(after.get("round", -1)) == 2 and after.get("closed") is False, str(after))

sql("""insert into public.finals_results
         (season_week,bucket_no,round,match_no,winner_side,seed_used)
       values (%d,%d,2,0,0,333)""" % (WEEK, BUCKET))
moved = advance()
after = bucket_row()
chk("⑦ ★分母: 补上决赛结果 ⇒ 返回 1(证明 ⑥ 是「没打完」挡的)", moved == 1, "moved=%d" % moved)
chk("⑦ ★★最后一轮打完 ⇒ closed = true(不是 round 变成 3)",
    after.get("closed") is True and int(after.get("round", -1)) == 2, str(after))

# ─────────────────────────────────────────────────────────────
print("── ⑧⑨ 收盘之后 ──")
st, v = view(TA)
chk("⑧ ★★收盘后冠军**才**公布: done 里有 2-0",
    (v.get("done") or {}).get("2-0") == 0, str(v.get("done")))
chk("⑧ 三场结果全都在", len(v.get("done") or {}) == 3, str(v.get("done")))
chk("⑧ closed 下发给客户端了", v.get("closed") is True, str(v.get("closed")))
moved = advance()
chk("⑨ ★收盘的桶不再被推(返回 0)", moved == 0, "moved=%d" % moved)

# ─────────────────────────────────────────────────────────────
print("── ⑩⑪ 客户端拿不到不该拿的 ──")
st, rows = req("GET", "/rest/v1/finals_results?season_week=eq.%d&select=*" % WEEK, None, TA)
chk("⑩ ★★登录用户**直读结果表 = 0 行**(没有 select 策略, 只能走 finals_view)",
    st == 200 and rows == [], "HTTP %s %s" % (st, str(rows)[:160]))
st, cnt = sql("select count(*)::int as c from public.finals_results where season_week = %d" % WEEK)
have = int(cnt[0]["c"]) if isinstance(cnt, list) else -1
chk("⑩ ★分母: 管理员看得见 3 行(证明 ⑩ 不是「表本来就空」)", have == 3, "%d 行" % have)
st, v = view(TB)
leaked = any("snapshot" in e for e in (v.get("entrants") or []))
chk("⑪ 参赛者阵容快照不下发(看图不需要)", not leaked, str((v.get("entrants") or [{}])[0])[:140])
chk("⑪ ★分母: 另一个号(B)也读得到同一个桶 —— 观赛是公开的",
    v.get("ok") is True and len(v.get("entrants") or []) == 4, str(v)[:120])

# ─────────────────────────────────────────────────────────────
print("── ⑫⑬ 权限 ──")
st, d = view(None)                      # 只带 anon key, 没有用户令牌
chk("⑫ ★anon 调不动 finals_view", st != 200 or (isinstance(d, dict) and d.get("ok") is False),
    "HTTP %s %s" % (st, str(d)[:140]))
st, d = req("POST", "/rest/v1/rpc/finals_advance", {"p_week": WEEK}, TA)
chk("⑬ ★★登录用户调不动 finals_advance —— 只有 pg_cron 能推赛程",
    st != 200, "HTTP %s %s" % (st, str(d)[:140]))

# ─────────────────────────────────────────────────────────────


print("── ⑮ 切桶规则: 规格(bracket.gd) ↔ 实现(SQL) 逐个对 ──")
## ★切桶是**服务端一次性**的事, 客户端只从回包里拿「这个桶几个人」⇒
##   `bracket.gd` 的 bucket_size_for / bucket_count / bucket_of_seed 在产品代码里
##   **零个调用者**: 它们是**规格**(41 条门禁守着), SQL 里那一份才是**实现**。
##   两份必须给同一个答案 —— 而「必须」要有人真的去量(memory `fb-hand-rolled-copies-drift`)。
spec = None
dump_dir = os.path.join(os.environ.get("TEMP", "."), "probe_br")
p = subprocess.run([GODOT_BIN, "--headless", "--path", REPO,
                    "res://tests/_dump_bracket_rules.tscn", "--quit-after", "120"],
                   capture_output=True, cwd=REPO,
                   env=dict(os.environ, APPDATA=dump_dir))
for line in p.stdout.decode("utf-8", "replace").splitlines():
    if line.startswith("DUMPED "):
        spec = json.load(io.open(line[7:].strip(), encoding="utf-8"))
chk("⑮ ★分母: 规格那一份真的导出来了(导不出来下面全是空检查)",
    spec is not None and len(spec.get("size", {})) > 300,
    "%d 个人数" % (len(spec.get("size", {})) if spec else 0))
if spec is not None:
    ns = list(range(0, 201))
    st, rows = sql("select n, public.finals_bucket_size(n) as sz, "
                   "public.finals_bucket_count(n) as cnt "
                   "from generate_series(0, 200) as n order by n")
    bad = []
    for r in (rows if isinstance(rows, list) else []):
        n = int(r["n"])
        if int(r["sz"]) != int(spec["size"][str(n)]):
            bad.append("n=%d 容量 SQL %s / 规格 %s" % (n, r["sz"], spec["size"][str(n)]))
        if int(r["cnt"]) != int(spec["count"][str(n)]):
            bad.append("n=%d 桶数 SQL %s / 规格 %s" % (n, r["cnt"], spec["count"][str(n)]))
    chk("⑮ ★分母: 真比了 %d 个人数 × 2 个量" % len(rows if isinstance(rows, list) else []),
        isinstance(rows, list) and len(rows) == 201, str(len(rows) if isinstance(rows, list) else -1))
    chk("⑮ ★★桶容量与桶数: 两份逐个一致(0~200 人)", not bad, str(bad[:4]))

    badof = []
    cnt_of = 0
    for nb_s, row in spec["of"].items():
        nb = int(nb_s)
        st, rows = sql("select i, public.finals_bucket_of(i, %d) as b "
                       "from generate_series(0, 39) as i order by i" % nb)
        for r in (rows if isinstance(rows, list) else []):
            cnt_of += 1
            if int(r["b"]) != int(row[int(r["i"])]):
                badof.append("nb=%d i=%s SQL %s / 规格 %s" % (nb, r["i"], r["b"], row[int(r["i"])]))
    chk("⑮ ★分母: 蛇形比了 %d 个点" % cnt_of, cnt_of >= 300, str(cnt_of))
    chk("⑮ ★★蛇形切桶: 两份逐个一致", not badof, str(badof[:4]))

print("── ⑯ 报到 finals_enter ──")
## ★★结果表也要清 —— 前面 ② 段用管理员 SQL 直插过几行(seed_used=111),
##   不清的话下面那条「重复报不覆盖」量到的是**旧行**, 不是我刚报的那一行
##   (实拍一样的毛病: 判据没错, 被测对象不对)。
sql("delete from public.finals_results  where season_week = %d" % WEEK)
sql("delete from public.finals_pending where season_week = %d" % WEEK)
sql("delete from public.finals_entrants where season_week = %d" % WEEK)
sql("delete from public.finals_buckets  where season_week = %d" % WEEK)
st, d = req("POST", "/rest/v1/rpc/finals_enter",
            {"p_week": WEEK, "p_name": "甲", "p_snapshot": {"pets": [1]}, "p_gw": 2, "p_gl": 1}, TA)
chk("⑯ ★★没到晋级线 ⇒ 收不了(晋级线在**服务端**判)",
    isinstance(d, dict) and d.get("reason") == "not_qualified", str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_enter",
            {"p_week": WEEK, "p_name": "甲", "p_snapshot": {"pets": [1]}, "p_gw": 7, "p_gl": 1}, TA)
chk("⑯ ★分母: 到线了就收(证明上面那条是「线」挡的, 不是函数坏了)",
    isinstance(d, dict) and d.get("ok") is True, str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_enter",
            {"p_week": WEEK, "p_name": "乙", "p_snapshot": {"pets": [2]}, "p_gw": 6, "p_gl": 2}, TB)
chk("⑯ 另一个号也收了", isinstance(d, dict) and d.get("ok") is True, str(d)[:140])
st, rows = req("GET", "/rest/v1/finals_pending?season_week=eq.%d&select=*" % WEEK, None, TA)
chk("⑯ ★★只看得见**自己**那一行(「谁报名了」本身就是情报)",
    isinstance(rows, list) and len(rows) == 1 and str(rows[0].get("name")) == "甲",
    str(rows)[:160])
st, c = sql("select count(*)::int as c from public.finals_pending where season_week = %d" % WEEK)
chk("⑯ ★分母: 库里其实有 2 行(证明上面那条是策略挡的, 不是只写进去 1 行)",
    isinstance(c, list) and int(c[0]["c"]) == 2, str(c)[:80])
st, d = req("POST", "/rest/v1/rpc/finals_enter",
            {"p_week": WEEK, "p_name": "甲改名", "p_snapshot": {"pets": [9]}, "p_gw": 9, "p_gl": 0}, TA)
st, rows = req("GET", "/rest/v1/finals_pending?season_week=eq.%d&select=name,gw" % WEEK, None, TA)
chk("⑯ ★再报一次 = 覆盖(不是撞主键报错) —— 阵容会改, 战绩也会变",
    isinstance(rows, list) and len(rows) == 1 and int(rows[0].get("gw", 0)) == 9, str(rows)[:120])

print("── ⑰ 坐下 finals_seat + 报结果 finals_report ──")
st, d = sql("select public.finals_seat(%d) as nb" % WEEK)
nb = int(d[0]["nb"]) if isinstance(d, list) and d else -1
chk("⑰ ★2 个人 ⇒ 切出 1 个桶", nb == 1, "nb=%d" % nb)
st, rows = sql("""select bucket_no, n from public.finals_buckets
                  where season_week = %d order by bucket_no""" % WEEK)
chk("⑰ 桶建出来了, n=2", isinstance(rows, list) and len(rows) == 1 and int(rows[0]["n"]) == 2,
    str(rows)[:120])
st, rows = sql("""select seed, name from public.finals_entrants
                  where season_week = %d order by seed""" % WEEK)
chk("⑰ ★★种子顺序 = 胜场降序(甲 9 胜在前, 乙 6 胜在后)",
    isinstance(rows, list) and [r["name"] for r in rows] == ["甲改名", "乙"], str(rows)[:140])
st, d = sql("select public.finals_seat(%d) as nb" % WEEK)
chk("⑰ ★幂等: 再坐一次返回 0, 不重复插",
    isinstance(d, list) and int(d[0]["nb"]) == 0, str(d)[:80])
st, d = req("POST", "/rest/v1/rpc/finals_enter",
            {"p_week": WEEK, "p_name": "丙", "p_snapshot": {}, "p_gw": 9, "p_gl": 0}, TB)
chk("⑰ ★★已经坐定之后不再收报名(这时塞人会让别人的对阵图当场变形)",
    isinstance(d, dict) and d.get("reason") == "already_seated", str(d)[:140])

## 报结果
st, d = req("POST", "/rest/v1/rpc/finals_report",
            {"p_week": WEEK, "p_bucket": 0, "p_round": 2, "p_match": 0,
             "p_winner_side": 0, "p_seed": 42}, TA)
chk("⑰ ★★只收**当前轮**(报第 2 轮被拒 —— 收未来轮等于提前定胜负)",
    isinstance(d, dict) and d.get("reason") == "wrong_round", str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_report",
            {"p_week": WEEK, "p_bucket": 0, "p_round": 1, "p_match": 0,
             "p_winner_side": 3, "p_seed": 42}, TA)
chk("⑰ winner_side 只能是 0/1", isinstance(d, dict) and d.get("reason") == "bad_side",
    str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_report",
            {"p_week": WEEK, "p_bucket": 0, "p_round": 1, "p_match": 0,
             "p_winner_side": 0, "p_seed": 42}, TA)
chk("⑰ ★分母: 当前轮 + 合法侧 ⇒ 收了", isinstance(d, dict) and d.get("ok") is True, str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_report",
            {"p_week": WEEK, "p_bucket": 0, "p_round": 1, "p_match": 0,
             "p_winner_side": 1, "p_seed": 99}, TB)
st, rows = sql("""select winner_side, seed_used from public.finals_results
                  where season_week = %d and round = 1 and match_no = 0""" % WEEK)
chk("⑰ ★★同一场重复报**不覆盖**(先到先得: 两边都会报, 谁先到都一样)",
    isinstance(rows, list) and len(rows) == 1 and int(rows[0]["winner_side"]) == 0
    and int(rows[0]["seed_used"]) == 42, str(rows)[:140])

## 桶外的人不许报
st, a3 = req("POST", "/auth/v1/signup", {})
T3 = a3["access_token"] if isinstance(a3, dict) and a3.get("access_token") else None
if T3:
    sql("""delete from public.finals_results
           where season_week = %d and round = 1 and match_no = 1""" % WEEK)
    st, d = req("POST", "/rest/v1/rpc/finals_report",
                {"p_week": WEEK, "p_bucket": 0, "p_round": 1, "p_match": 1,
                 "p_winner_side": 0, "p_seed": 1}, T3)
    chk("⑰ ★★不在这个桶里的人报不了", isinstance(d, dict) and d.get("reason") == "not_in_bucket",
        str(d)[:140])
st, d = req("POST", "/rest/v1/rpc/finals_seat", {"p_week": WEEK}, TA)
chk("⑰ ★登录用户调不动 finals_seat(切桶只有 pg_cron 干得了)", st != 200,
    "HTTP %s %s" % (st, str(d)[:120]))

## ★★已知缺口, 显式登记(不静默截断):
##   `finals_report` 只挡到**桶级** —— 同桶的旁观者能替别人报一场。
##   精确到"这一场"要服务端自己推对阵树, 那就是把对阵规则在 SQL 里写第二遍。
##   与排行榜/快照池同一个信任模型; 服务端复算是 B 阶段第二步的事。
print("  [GAP ] ⑰ ★已知缺口: finals_report 只挡到桶级, 同桶旁观者能替别人报一场")
print("         (要挡到「这一场」得在 SQL 里把对阵规则写第二遍; 服务端复算是 B 阶段第二步)")

# ═════════════════════════════════════════════════════════════
# ⑱ 对手快照 finals_opponent (E-B4, 2026-09-25)
#
# 这一段守的是 2026-09-25 查出来的那条死锁的上半截:
#   快照写进去了, 但 `finals_view` 不下发 ⇒ 客户端**永远读不回来**
#   ⇒ 没法替不在线的人打 ⇒ 那一场没人报 ⇒ 桶永久卡死。
#
# ★判据的重点不是「拿得到」, 是**「只拿得到一个」** —— 那一条才是它不泄露
#   全桶阵容的全部依据。所以下面每条「拿不到」都配一条「换个条件就拿得到」的分母。
# ═════════════════════════════════════════════════════════════
print("")
print("── ⑱ 对手快照 finals_opponent ──")
B2 = 1                                   # 另起一个桶, 不碰 ⑰ 用的那个
sql("delete from public.finals_scout    where season_week = %d and bucket_no = %d" % (WEEK, B2))
sql("delete from public.finals_entrants where season_week = %d and bucket_no = %d" % (WEEK, B2))
sql("delete from public.finals_buckets  where season_week = %d and bucket_no = %d" % (WEEK, B2))
st, _ = sql("""
insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
  values (%d, %d, 4, 1, now(), false);
insert into public.finals_entrants (season_week, bucket_no, seed, account_id, name, snapshot)
  values (%d,%d,0,'%s','甲','{"tag":"AAA"}'::jsonb),
         (%d,%d,1,'%s','乙','{"tag":"BBB"}'::jsonb),
         (%d,%d,2,'%s','丙','{"tag":"CCC"}'::jsonb),
         (%d,%d,3,'%s','丁','{"tag":"DDD"}'::jsonb);
""" % (WEEK, B2, WEEK, B2, IA, WEEK, B2, IB, WEEK, B2, IB, WEEK, B2, IB))
chk("⑱ ★分母: 造场子成功(否则下面全是空检查)", st in (200, 201), "HTTP %s" % st)


def opp(tok, seed, week=WEEK, bucket=B2, rnd=1):
    s, d = req("POST", "/rest/v1/rpc/finals_opponent",
               {"p_week": week, "p_bucket": bucket, "p_round": rnd, "p_seed": seed}, tok)
    return d if isinstance(d, dict) else {"_http": s, "_raw": str(d)[:80]}


## ★★正路: 甲(seed 0)问乙(seed 1) —— 这是整条链的第一次「读得回来」
d = opp(TA, 1)
chk("⑱ ★★★拿得到对手的 snapshot —— 在此之前客户端永远读不回来",
    bool(d.get("ok")) and isinstance(d.get("snapshot"), dict)
    and d["snapshot"].get("tag") == "BBB", str(d)[:160])
chk("⑱ ★连名字一起给(对阵图上要显示)", str(d.get("name", "")) == "乙", str(d)[:120])

## 同一个种子再问一次 ⇒ 照给(幂等; 掉线重连不该被自己的记账挡住)
d = opp(TA, 1)
chk("⑱ 同一个种子再问一次照给(幂等)", bool(d.get("ok")), str(d)[:140])

## ★★★核心: 同一轮换一个种子 ⇒ 拒, 并告诉它第一次问的是谁
d = opp(TA, 2)
chk("⑱ ★★★同一轮问第二个种子**被拒** —— 这一条是它不泄露全桶阵容的全部依据",
    (not d.get("ok")) and d.get("reason") == "already_asked", str(d)[:160])
chk("⑱ ★拒的时候把第一次问的号告诉它(否则客户端只知道拿不到, 不知道为什么)",
    int(d.get("seed", -1)) == 1, str(d)[:140])
chk("⑱ ★★被拒时**一个字节的快照都不给**(不然拒了也白拒)",
    "snapshot" not in d, str(d)[:140])

## 问自己 ⇒ 拒
d = opp(TB, 1)      # 乙 = seed 1
chk("⑱ 问自己 ⇒ 拒", (not d.get("ok")) and d.get("reason") == "thats_you", str(d)[:140])

## 轮次不对 ⇒ 拒(问未来轮 = 提前侦察)
d = opp(TB, 0, rnd=2)
chk("⑱ ★轮次不对 ⇒ 拒(问未来轮等于提前侦察)",
    (not d.get("ok")) and d.get("reason") == "wrong_round", str(d)[:140])

## 不在这个桶里的人 ⇒ 拒
if T3:
    d = opp(T3, 0)
    chk("⑱ ★★不在这个桶里的人问不到", (not d.get("ok")) and d.get("reason") == "not_in_bucket",
        str(d)[:140])

## ★★问一个不存在的号**不许烧掉自己的机会** —— 先查存在再记账, 顺序反了就坑人
##   用乙来验(它上面只做过被拒的调用, 还没成功记过账)
sql("delete from public.finals_scout where season_week = %d and bucket_no = %d and account_id = '%s'"
    % (WEEK, B2, IB))
d = opp(TB, 9)
chk("⑱ 不存在的种子 ⇒ no_such_seed",
    (not d.get("ok")) and d.get("reason") == "no_such_seed", str(d)[:140])
d = opp(TB, 0)
chk("⑱ ★★★问了一个不存在的号之后, **还能正常问真正的对手** —— 先查存在再记账",
    bool(d.get("ok")) and d.get("snapshot", {}).get("tag") == "AAA", str(d)[:160])

## ★分母: scout 表真的记了账(否则上面的「被拒」可能是别的原因)
st, rows = sql("select account_id, seed from public.finals_scout "
               "where season_week = %d and bucket_no = %d and round = 1 order by seed" % (WEEK, B2))
chk("⑱ ★分母: scout 表真的有记账(证明限流是它做的)",
    isinstance(rows, list) and len(rows) == 2, str(rows)[:200])

## ★客户端直接读 finals_scout / finals_entrants ⇒ 都该读不到(表上没给策略)
st, d = req("GET", "/rest/v1/finals_scout?select=*&season_week=eq.%d" % WEEK, None, TA)
chk("⑱ ★★客户端**直连读不到 scout 表**(谁问过谁本身就是情报)",
    not (isinstance(d, list) and len(d) > 0), "HTTP %s %s" % (st, str(d)[:110]))
st, d = req("GET", "/rest/v1/finals_entrants?select=snapshot&season_week=eq.%d" % WEEK, None, TA)
chk("⑱ ★★客户端**直连读不到 entrants 的 snapshot**(否则上面那套限流全白做)",
    not (isinstance(d, list) and len(d) > 0), "HTTP %s %s" % (st, str(d)[:110]))

# ═════════════════════════════════════════════════════════════
# ⑲ 补判: 没人打的那一场 (E-B4 下半)
#
# 原来 `finals_advance` 是 `if got < want then continue` —— **无上限**。
# 注释写的是「宁可晚一分钟」, 实际是**永远不推**。
# ★判据必须分开两件事: 宽限期内**不许**补(会把正在打的判掉) / 过了才补。
# ═════════════════════════════════════════════════════════════
print("")
print("── ⑲ 没人打的那一场: 补判 ──")
st, d = sql("select public.finals_round_sec() as s")
RSEC = int(d[0]["s"]) if isinstance(d, list) and d else 0
chk("⑲ ★分母: 拿到轮时长(否则下面的时间都是瞎设的)", RSEC > 0, str(RSEC))
B3 = 2


def setup_b3(age_sec, results_sql=""):
    sql("delete from public.finals_results  where season_week = %d and bucket_no = %d" % (WEEK, B3))
    sql("delete from public.finals_entrants where season_week = %d and bucket_no = %d" % (WEEK, B3))
    sql("delete from public.finals_buckets  where season_week = %d and bucket_no = %d" % (WEEK, B3))
    sql("""insert into public.finals_buckets (season_week, bucket_no, n, round, round_at, closed)
             values (%d, %d, 4, 1, now() - make_interval(secs => %d), false);
           insert into public.finals_entrants (season_week,bucket_no,seed,account_id,name,snapshot)
             values (%d,%d,0,'%s','甲','{}'::jsonb),(%d,%d,1,'%s','乙','{}'::jsonb),
                    (%d,%d,2,'%s','丙','{}'::jsonb),(%d,%d,3,'%s','丁','{}'::jsonb);
           %s"""
        % (WEEK, B3, age_sec, WEEK, B3, IA, WEEK, B3, IB, WEEK, B3, IA, WEEK, B3, IB,
           results_sql))


def b3_state():
    st2, r = sql("""select b.round, b.closed,
                      (select count(*) from public.finals_results x
                        where x.season_week=%d and x.bucket_no=%d and x.round=1) as res1
                    from public.finals_buckets b
                   where b.season_week=%d and b.bucket_no=%d"""
                 % (WEEK, B3, WEEK, B3))
    return r[0] if isinstance(r, list) and r else {}


## ① 宽限期**内**, 一条结果都没有 ⇒ 不许补, 也不许翻面
setup_b3(int(RSEC * 1.2))          # 过了 1 倍, 没过 2 倍
sql("select public.finals_advance(%d)" % WEEK)
s1 = b3_state()
chk("⑲ ★★宽限期内(1.2×)**不补判也不翻面** —— 补早了会把正在打的比赛判掉",
    int(s1.get("round", -1)) == 1 and int(s1.get("res1", -1)) == 0, str(s1))

## ② 过了宽限期 ⇒ 补成 side 0 并翻面
setup_b3(int(RSEC * 3))
sql("select public.finals_advance(%d)" % WEEK)
s2 = b3_state()
chk("⑲ ★★★过了宽限期(3×) ⇒ 把缺的两场补上", int(s2.get("res1", -1)) == 2, str(s2))
chk("⑲ ★★★补完照常翻面(这正是原来永远不会发生的那一步)",
    int(s2.get("round", -1)) == 2, str(s2))
st, rows = sql("select match_no, winner_side from public.finals_results "
               "where season_week=%d and bucket_no=%d and round=1 order by match_no"
               % (WEEK, B3))
chk("⑲ 补判一律 side 0(上半区晋级)",
    isinstance(rows, list) and len(rows) == 2
    and all(int(x["winner_side"]) == 0 for x in rows), str(rows)[:180])

## ③ ★★已经打完的那几场**一个字都不许被覆盖**
setup_b3(int(RSEC * 3), """
  insert into public.finals_results (season_week,bucket_no,round,match_no,winner_side,seed_used)
    values (%d,%d,1,0,1,777);""" % (WEEK, B3))
sql("select public.finals_advance(%d)" % WEEK)
st, rows = sql("select match_no, winner_side, seed_used from public.finals_results "
               "where season_week=%d and bucket_no=%d and round=1 order by match_no"
               % (WEEK, B3))
m0 = next((x for x in rows if int(x["match_no"]) == 0), {}) if isinstance(rows, list) else {}
m1 = next((x for x in rows if int(x["match_no"]) == 1), {}) if isinstance(rows, list) else {}
chk("⑲ ★★★真打过的那一场没被覆盖(side 仍是 1, 种子仍是 777)",
    int(m0.get("winner_side", -1)) == 1 and int(m0.get("seed_used", -1)) == 777, str(m0))
chk("⑲ ★只把**缺的**那一场补成 side 0", int(m1.get("winner_side", -1)) == 0, str(m1))

sql("delete from public.finals_scout    where season_week = %d" % WEEK)
for _b in (B2, B3):
    sql("delete from public.finals_results  where season_week = %d and bucket_no = %d" % (WEEK, _b))
    sql("delete from public.finals_entrants where season_week = %d and bucket_no = %d" % (WEEK, _b))
    sql("delete from public.finals_buckets  where season_week = %d and bucket_no = %d" % (WEEK, _b))

sql("delete from public.finals_pending where season_week = %d" % WEEK)

# ═════════════════════════════════════════════════════════════
# ㉑ 【整轮端到端】报名 → 切桶 → 看图 → 要对手 → 打完报结果 → 翻面 → 再看图
#
# ★★为什么单独来一段: 上面每一段验的是**一个 RPC**。而今天两次「写了没人读」
#   都是**各块单看都对、串起来断掉**(快照写了读不回来 / 结果报不上去)。
#   ⇒ 这一段**只按玩家真实顺序走一遍**, 一个 RPC 都不跳。
# ★用户侧全走 `req(..., tok)`(真 REST + 真 token); 只有 `finals_seat` /
#   `finals_advance` 用 `sql()` —— 它们本来就只有 pg_cron 叫得动。
# ═════════════════════════════════════════════════════════════
print("")
print("── ㉑ 整轮端到端(按玩家真实顺序, 一个 RPC 都不跳) ──")
EW = 3                                  # 又一个假周号, 不碰上面几段
for _t in ("finals_scout", "finals_results", "finals_entrants",
           "finals_buckets", "finals_pending"):
    sql("delete from public.%s where season_week = %d" % (_t, EW))

# ① 两个人报名(客户端 RPC, 带真快照)
e_ok = True
for tok, nm, snap, gw in ((TA, "端到端甲", '{"leaders":["basic"],"tag":"AAA"}', 6),
                          (TB, "端到端乙", '{"leaders":["ninja"],"tag":"BBB"}', 5)):
    st, d = req("POST", "/rest/v1/rpc/finals_enter",
                {"p_week": EW, "p_name": nm, "p_snapshot": json.loads(snap),
                 "p_gw": gw, "p_gl": 1}, tok)
    e_ok = e_ok and isinstance(d, dict) and bool(d.get("ok"))
chk("㉑ ① 两个人都报上名了(客户端 RPC + 真 token)", e_ok)

# ② 切桶(只有 pg_cron 干得动)
st, d = sql("select public.finals_seat(%d) as nb" % EW)
nb = int(d[0]["nb"]) if isinstance(d, list) and d else -1
chk("㉑ ② 切出 1 个桶", nb == 1, str(nb))

# ③ 甲看图: 拿得到自己的桶 + 名字按种子落位
st, v = req("POST", "/rest/v1/rpc/finals_view", {"p_week": EW, "p_bucket": -1}, TA)
chk("㉑ ③ 甲查到了自己那个桶(p_bucket=-1 那条路)",
    isinstance(v, dict) and bool(v.get("ok")) and int(v.get("n", 0)) == 2, str(v)[:170])
bno = int(v.get("bucket", -1)) if isinstance(v, dict) else -1
ents = v.get("entrants", []) if isinstance(v, dict) else []
chk("㉑ ③ ★回包里带着桶号(客户端要拿它去问对手)", bno >= 0, str(bno))
chk("㉑ ③ ★★回包里**没有 snapshot**(全桶阵容不许下发)",
    all("snapshot" not in e for e in ents), str(ents)[:170])
# 甲的种子
my_seed = -1
foe_seed = -1
for e in ents:
    if str(e.get("account_id")) == IA:
        my_seed = int(e.get("seed", -1))
    else:
        foe_seed = int(e.get("seed", -1))
chk("㉑ ③ ★分母: 甲和乙的种子都认出来了", my_seed >= 0 and foe_seed >= 0,
    "我=%d 对手=%d" % (my_seed, foe_seed))

# ④ 甲要对手快照 —— 这一步在 2026-09-25 之前**根本做不到**
st, o = req("POST", "/rest/v1/rpc/finals_opponent",
            {"p_week": EW, "p_bucket": bno, "p_round": 1, "p_seed": foe_seed}, TA)
chk("㉑ ④ ★★★甲拿到了对手的快照 —— 这一步在 E-B4 之前根本做不到",
    isinstance(o, dict) and bool(o.get("ok"))
    and isinstance(o.get("snapshot"), dict), str(o)[:170])
chk("㉑ ④ ★拿到的是**对手那一份**(不是自己的)",
    isinstance(o, dict) and str(o.get("snapshot", {}).get("tag", "")) == "BBB",
    str(o.get("snapshot", {}))[:90] if isinstance(o, dict) else "?")

# ⑤ 打完 → 甲报结果(甲赢: winner_side = 甲所在那一侧)
#   4 人以下的桶里第 1 轮第 0 场就是这两个人; 甲的坑位 = 种子序(0/1)
side_a = 0 if my_seed == 0 else 1
st, r = req("POST", "/rest/v1/rpc/finals_report",
            {"p_week": EW, "p_bucket": bno, "p_round": 1, "p_match": 0,
             "p_winner_side": side_a, "p_seed": 4242}, TA)
chk("㉑ ⑤ ★★结果报上去了(这一步在 E-B6 之前客户端一个调用者都没有)",
    isinstance(r, dict) and bool(r.get("ok")), str(r)[:140])

# ⑥ 还没到点 ⇒ 不许翻面(打完就翻的话, 全桶同步就没了)
sql("select public.finals_advance(%d)" % EW)
st, b = sql("select round, closed from public.finals_buckets "
            "where season_week=%d and bucket_no=%d" % (EW, bno))
chk("㉑ ⑥ ★★本轮时间没到 ⇒ **不翻面**(全桶同步靠这条)",
    isinstance(b, list) and b and int(b[0]["round"]) == 1 and not b[0]["closed"],
    str(b)[:120])

# ⑦ 把本轮开始时刻推早 ⇒ 到点 ⇒ 翻面。2 人桶只有 1 轮 ⇒ 直接收盘
sql("update public.finals_buckets set round_at = now() - interval '20 minutes' "
    "where season_week=%d and bucket_no=%d" % (EW, bno))
sql("select public.finals_advance(%d)" % EW)
st, b = sql("select round, closed from public.finals_buckets "
            "where season_week=%d and bucket_no=%d" % (EW, bno))
chk("㉑ ⑦ ★★★到点了 ⇒ 桶收盘(2 人桶只有 1 轮) —— 对阵图**真的走完了**",
    isinstance(b, list) and b and bool(b[0]["closed"]), str(b)[:120])

# ⑧ 甲再看图: 现在该看得到结果了(收盘之后全给)
st, v2 = req("POST", "/rest/v1/rpc/finals_view", {"p_week": EW, "p_bucket": bno}, TA)
done = v2.get("done", {}) if isinstance(v2, dict) else {}
chk("㉑ ⑧ ★★★收盘后甲看得到这一场的结果 —— 冠军公布了",
    isinstance(done, dict) and "1-0" in done, str(done)[:140])
chk("㉑ ⑧ ★而且赢的是甲那一侧(报什么就是什么, 没被改过)",
    int(done.get("1-0", -1)) == side_a, "done=%s 甲那侧=%d" % (str(done)[:60], side_a))

# 收尾
for _t in ("finals_scout", "finals_results", "finals_entrants",
           "finals_buckets", "finals_pending"):
    sql("delete from public.%s where season_week = %d" % (_t, EW))
st, c = sql("select (select count(*) from public.finals_buckets where season_week=%d)"
            " + (select count(*) from public.finals_entrants where season_week=%d)"
            " as leftover" % (EW, EW))
chk("㉑ 收尾: 端到端那一周的数据清干净了",
    isinstance(c, list) and c and int(c[0]["leftover"]) == 0, str(c)[:110])


## ★反向验证时跳过这一段(它要真等 pg_cron 醒, 一轮 30~90 秒)
if os.environ.get("SKIP_CRON") == "1":
    print("── ⑭ (SKIP_CRON=1, 跳过) ──")
    print("")
    print("══ %d 通过 / %d 失败 ══" % (OK[0], BAD[0]))
    sys.exit(1 if BAD[0] else 0)


print("── ⑭ pg_cron 真的会响 ──")
st, j = sql("select jobname, schedule, active from cron.job where jobname = 'finals_advance'")
row = j[0] if isinstance(j, list) and j else {}
chk("⑭ 正式任务在调度表里、active、只在周日(dow=0)",
    row.get("active") is True and str(row.get("schedule", "")).endswith(" 0"), str(row))

## ★正式任务是周日跑的, 等不到。临时挂一个**每分钟**的探针任务, 证明这个项目里
##   pg_cron 真的会被唤醒 —— 「装上了」跟「会响」是两件事。
sql("create table if not exists public._cron_probe (t timestamptz default now())")
sql("delete from public._cron_probe")
sql("select cron.unschedule('_cron_probe')")
st, d = sql("""select cron.schedule('_cron_probe', '* * * * *',
             $$insert into public._cron_probe default values$$)""")
chk("⑭ 探针任务挂上了", st in (200, 201), "HTTP %s" % st)
print("     等它自己响(最多 150 秒)…")
fired = 0
t0 = time.time()
while time.time() - t0 < 150:
    time.sleep(10)
    st, c = sql("select count(*)::int as c from public._cron_probe")
    fired = int(c[0]["c"]) if isinstance(c, list) and c else 0
    if fired > 0:
        break
    print("       …%d 秒" % int(time.time() - t0))
chk("⑭ ★★pg_cron **真的自己跑了**(没人点任何按钮) ⇒ 周日的赛程推进会动",
    fired > 0, "%d 次, 等了 %d 秒" % (fired, int(time.time() - t0)))
## ★`cron.job_run_details` 里没有 jobname(只有 jobid), 要 join cron.job
st, r = sql("""select d.status from cron.job_run_details d
               join cron.job j on j.jobid = d.jobid
               where j.jobname = '_cron_probe' order by d.start_time desc limit 1""")
chk("⑭ 运行记录里 status = succeeded",
    isinstance(r, list) and r and r[0].get("status") == "succeeded", str(r)[:140])

## 收尾: 撤探针任务、删探针表、清掉假周号的数据
sql("select cron.unschedule('_cron_probe')")
sql("drop table if exists public._cron_probe")
sql("delete from public.finals_results  where season_week = %d" % WEEK)
sql("delete from public.finals_entrants where season_week = %d" % WEEK)
sql("delete from public.finals_buckets  where season_week = %d" % WEEK)
st, c = sql("""select (select count(*) from cron.job where jobname='_cron_probe')
               + (select count(*) from public.finals_buckets where season_week=%d)
               as leftover""" % WEEK)
chk("收尾: 探针任务与假周号数据都清干净了",
    isinstance(c, list) and int(c[0]["leftover"]) == 0, str(c)[:120])

print("")
print("══ %d 通过 / %d 失败 ══" % (OK[0], BAD[0]))
print("(留了两个匿名测试号在库里: %s… %s…)" % (IA[:8], IB[:8]))
sys.exit(1 if BAD[0] else 0)
