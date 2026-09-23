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

sql("delete from public.finals_pending where season_week = %d" % WEEK)

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
