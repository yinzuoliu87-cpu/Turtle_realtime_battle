# -*- coding: utf-8 -*-
"""tools/probe_finals_health.py —— 周末赛事「到底有没有在跑」健康检查。

★为什么要有这个工具
  周日决赛日的赛程推进器是 `pg_cron` **无人值守**每分钟叫一次
  (`select public.finals_advance(<week>)`)。它要是哪个周日没推，
  **不会有任何人收到通知** —— 玩家只看到对阵图停在那儿。
  这正是本仓反复踩的「静默失败」，而且发生在服务端，本地 385 条门禁一条都碰不到。

★这个工具回答的唯一问题: **现在这一刻，周末赛事是不是健康的。**
  它不是门禁(要真网络、要管理员令牌、结果随时间变)，手动跑或挂定时跑。

★★它必须能分清两种「空」(本仓的 `分流给没做的模式=开后门` 教训):
    ① 空是因为**决赛日玩法还没上线**(`PHASE_MODE_LIVE[finals] = false`) ⇒ 正常
    ② 空是因为**坏了** ⇒ 要报
  分不清的话，等玩法上线那天它会继续安静地说「一切正常」。

★每一项都打分母。`N=0` 是空检查不是通过 —— 输出里一律把 N 写出来。

用法:
    python tools/probe_finals_health.py              # 体检
    python tools/probe_finals_health.py --selftest   # ★先证明它会报: 造一个卡住的桶
退出码: 0 = 健康(或「没上线，空是对的」)  /  1 = 有真问题  /  2 = 查不了(令牌等)
"""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
PROJ = "cjefldecsfpnclhfwriw"
TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".supabase", "access-token")
## ★本机代理会改写 POST body(memory `fb-local-proxy-corrupts-post-body`) ⇒ 一律绕开
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_GD = os.path.join(REPO, "scripts", "gamedata", "phase2_config.gd")

BAD = []          # 真问题
NOTE = []         # 说明(不算问题)


def sql(q):
    """跑一条 SQL(管理员通道)。返回 (status, rows|错误串)。"""
    try:
        tok = io.open(TOKEN_FILE, encoding="utf-8").read().strip()
    except OSError as e:
        return 0, "读不到令牌 %s: %s" % (TOKEN_FILE, e)
    r = urllib.request.Request(
        "https://api.supabase.com/v1/projects/%s/database/query" % PROJ,
        method="POST", data=json.dumps({"query": q}).encode(),
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with OP.open(r, timeout=90) as resp:
            t = resp.read().decode()
            return resp.status, (json.loads(t) if t.strip() else [])
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]
    except Exception as e:                      # 网络不通也要说人话
        return 0, "%s: %s" % (type(e).__name__, e)


def finals_live():
    """决赛日玩法上线了没有 —— 从产品代码读，不在这儿写第二份。"""
    try:
        s = io.open(CONFIG_GD, encoding="utf-8", newline="").read()
    except OSError:
        return None
    m = re.search(r"PHASE_FINALS\s*:\s*(true|false)", s)
    return None if m is None else (m.group(1) == "true")


def ok2xx(st):
    """★Management API 的 `database/query` 回的是 **201** 不是 200 ——
       写死 200 的话它明明拿到了数据却报「查不了」(我第一版就是这么错的,
       正是本仓「判据没卡住那个形状」那一族)。"""
    return 200 <= int(st) < 300


def head(t):
    print("")
    print("── %s ──" % t)


def main():
    selftest = "--selftest" in sys.argv
    print("=== 周末赛事健康检查 ===")

    # ① 查得了吗 —— 查不了的话下面全是空检查，必须先判出来
    head("① 管理员通道")
    st, rows = sql("select now() as t, extract(isodow from now()) as dow")
    if not ok2xx(st) or not isinstance(rows, list) or not rows:
        print("  ✗ 跑不了 SQL: HTTP %s  %s" % (st, str(rows)[:200]))
        print("")
        print("  ⇒ 这不是「赛事健康」的结论，是**查不了** —— 别当成通过。")
        print("     令牌在 %s(记录的到期日 2026-09-29)。" % TOKEN_FILE)
        return 2
    now_s = str(rows[0].get("t"))
    dow = int(float(rows[0].get("dow")))
    wd_name = {1: "周一", 2: "周二", 3: "周三", 4: "周四", 5: "周五", 6: "周六", 7: "周日"}
    print("  ✓ 通  服务端现在 = %s (%s)" % (now_s, wd_name.get(dow, "?")))

    # ② 玩法上线了没有 —— 决定下面的「空」该怎么读
    head("② 决赛日玩法上线了没有")
    live = finals_live()
    if live is None:
        BAD.append("读不到 PHASE_MODE_LIVE[finals]，分不清「空」是没上线还是坏了")
        print("  ✗ 读不到 `PHASE_MODE_LIVE[PHASE_FINALS]`(%s)" % CONFIG_GD)
    elif live:
        print("  ✓ **已上线** ⇒ 下面的空就是**坏了**")
    else:
        print("  ○ **还没上线**(`PHASE_MODE_LIVE[PHASE_FINALS] = false`)")
        print("    ⇒ 下面桶/参赛者为 0 是**正常的**，不报。")
        print("    ⇒ ★上线那天改那一个常量，这里会自动改判 —— 不用记得回来改本工具。")
        NOTE.append("决赛日玩法尚未上线，空桶属正常")

    # ③ 推进器还在不在 —— 无人值守的那一环
    head("③ 赛程推进器(pg_cron)")
    st, jobs = sql("select jobid, schedule, active, command from cron.job order by jobid")
    if not ok2xx(st) or not isinstance(jobs, list):
        BAD.append("读不到 cron.job: %s" % str(jobs)[:120])
        print("  ✗ 读不到 cron.job: HTTP %s %s" % (st, str(jobs)[:160]))
        jobs = []
    print("  分母: cron 任务共 %d 个" % len(jobs))
    adv = [j for j in jobs if "finals_advance" in str(j.get("command", ""))]
    print("  其中推进决赛日的: %d 个" % len(adv))
    if not adv:
        BAD.append("★没有任何 cron 任务在叫 finals_advance —— 周日不会自己推进")
        print("  ✗ **一个都没有** ⇒ 周日的对阵图不会自己往前走")
    for j in adv:
        act = bool(j.get("active"))
        print("    jobid=%s  schedule=「%s」  active=%s" % (
            j.get("jobid"), j.get("schedule"), act))
        if not act:
            BAD.append("cron 任务 %s 是 active=false —— 排着但不会响" % j.get("jobid"))

    # ④ 它最近真的响了吗 —— 「排上了」≠「响了」
    head("④ 推进器最近响过没有")
    if adv:
        ids = ",".join(str(j.get("jobid")) for j in adv)
        st, runs = sql(
            "select jobid, status, start_time, return_message from cron.job_run_details "
            "where jobid in (%s) order by start_time desc limit 10" % ids)
        if not ok2xx(st) or not isinstance(runs, list):
            print("  ? 读不到 job_run_details: HTTP %s %s" % (st, str(runs)[:160]))
            NOTE.append("读不到 cron.job_run_details(权限或扩展版本)，这一项没验")
        else:
            print("  分母: 最近 %d 次运行记录" % len(runs))
            if not runs:
                print("  ○ **一次都没跑过** —— 它是 `* * * * 0`(只在周日响)，")
                print("    今天不是周日的话这就是正常的。")
                if dow == 7:
                    BAD.append("★今天是周日，而推进器一次都没跑过")
            bad_runs = [r for r in runs if str(r.get("status")) != "succeeded"]
            print("  其中**不是 succeeded** 的: %d 次" % len(bad_runs))
            for r in runs[:3]:
                print("    %s  %s  %s" % (r.get("start_time"), r.get("status"),
                                          str(r.get("return_message"))[:60]))
            if bad_runs:
                BAD.append("推进器最近 %d 次运行失败" % len(bad_runs))
    else:
        print("  (没有推进任务，跳过)")

    # ★自证: 在 ⑤ 读桶**之前**注入一个明显卡住的桶。
    #   ★★为什么放这儿而不是最后: 放最后的话只能**把判据再抄一遍**去算"它会不会报",
    #     那是本仓「手抄的副本必然落后」—— 判据一改，抄的那份就悄悄失效了。
    #     放这儿，下面 ⑥ 会像扫真桶一样扫到它，报不报是**它自己**说了算。
    SELF_WK = 1999999999      # 2033 年; 像真周号(>= 1e9 才过得了 ⑥ 的残留过滤), 真赛季碰不到
    if selftest:
        head("★自证(上): 注入一个明显卡住的桶")
        sql("delete from public.finals_buckets where season_week = %d" % SELF_WK)
        st, _ = sql(
            "insert into public.finals_buckets(season_week, bucket_no, n, round, "
            "round_at, closed) values (%d, 0, 8, 1, now() - interval '9 hours', false)"
            % SELF_WK)
        st2, chk = sql("select extract(epoch from (now() - round_at))::bigint as age "
                       "from public.finals_buckets where season_week = %d" % SELF_WK)
        got = int(chk[0]["age"]) if (ok2xx(st2) and isinstance(chk, list) and chk) else -1
        print("  注入 周%d 桶0，本轮开始于 9 小时前  HTTP %s" % (SELF_WK, st))
        print("  ★分母: 它真的进库了 —— age = %d 秒(不进库的话下面是空检查)" % got)
        if got < 0:
            BAD.append("★自证注入失败，这一轮的「没发现问题」不可信")

    # ⑤⑥ 桶的状态 + ★真正的健康判据: 到点了却没推进
    head("⑤ 当前的桶")
    st, secs = sql("select public.finals_round_sec() as s")
    round_sec = int(secs[0]["s"]) if (ok2xx(st) and isinstance(secs, list) and secs) else 0
    print("  每轮时长 = %d 秒" % round_sec)
    st, buckets = sql(
        "select season_week, bucket_no, n, round, closed, round_at, "
        "extract(epoch from (now() - round_at))::bigint as age "
        "from public.finals_buckets order by season_week desc, bucket_no limit 50")
    if not ok2xx(st) or not isinstance(buckets, list):
        BAD.append("读不到 finals_buckets: %s" % str(buckets)[:120])
        print("  ✗ 读不到: HTTP %s %s" % (st, str(buckets)[:160]))
        buckets = []
    print("  分母: 桶共 %d 个" % len(buckets))
    if not buckets:
        print("  ○ 一个桶都没有 —— %s" % (
            "**正常**(玩法没上线)" if live is False else "★玩法已上线却没有桶"))
        if live:
            BAD.append("玩法已上线，但一个桶都没有")

    head("⑥ ★有没有卡住(到点了却没推进)")
    ## ★★先把**测试残留**摘出去。真周号是周一的 unix 时间戳(~1.79e9),
    ##   探针用的是 1 / 2 / 999999 这种小数字。两件事严重性差得远:
    ##     「真桶卡住」= 玩家在等，对阵图不动          ⇒ 要立刻处理
    ##     「假周号残留」= 探针中途挂了没走到收尾      ⇒ 清掉就行
    ##   不分开的话，一条残留会让这个工具**永远在喊狼来了**，
    ##   喊到没人看它的那天，真的卡住就没人知道了。
    ##   (2026-09-24 实测: probe_finals_server 的周2 残留就是这么被照出来的)
    fake = [b for b in buckets if int(b.get("season_week") or 0) < 1000000000]
    if fake:
        print("  ○ 先摘掉**测试残留**(周号 < 1e9, 不是真赛季): %d 个 —— %s" % (
            len(fake), ", ".join("周%s桶%s" % (f.get("season_week"), f.get("bucket_no"))
                                 for f in fake)))
        print("    清法: delete from public.finals_{results,entrants,buckets} "
              "where season_week = <那个假周号>")
        NOTE.append("生产库里有 %d 个探针残留的假周号桶 —— 清掉(不是赛事故障)" % len(fake))
    stuck = []
    for b in buckets:
        if b.get("closed"):
            continue
        if int(b.get("season_week") or 0) < 1000000000:
            continue
        age = int(b.get("age") or 0)
        ## ★判据: 本轮已经过了 2 倍轮时长还没推 ⇒ 推进器没在工作。
        ##   给 2 倍余量是因为 cron 每分钟才叫一次、且一轮结算本身要时间;
        ##   卡住的话 age 会一直涨到几百倍，根本不需要卡得紧。
        if round_sec > 0 and age > round_sec * 2:
            stuck.append((b, age))
    real = [b for b in buckets if int(b.get("season_week") or 0) >= 1000000000]
    print("  分母: 真赛季的桶 %d 个(共 %d 个, 其中残留 %d) · 其中没收盘 %d 个" % (
        len(real), len(buckets), len(fake),
        len([b for b in real if not b.get("closed")])))
    print("  判据: 本轮已过 > 2×%d 秒仍没推进" % round_sec)
    print("  卡住的: %d 个" % len(stuck))
    for b, age in stuck:
        print("    ✗ 周%s 桶%s  第%s轮  已卡 %d 秒(= %.1f 倍轮时长)" % (
            b.get("season_week"), b.get("bucket_no"), b.get("round"),
            age, age / float(round_sec)))
        BAD.append("周%s 桶%s 卡在第%s轮 %d 秒" % (
            b.get("season_week"), b.get("bucket_no"), b.get("round"), age))

    # ⑦ 有没有人报了名却没进桶
    head("⑦ 报了名没进桶的人")
    st, pend = sql("select season_week, count(*) as n from public.finals_pending "
                   "group by season_week order by season_week desc limit 5")
    if not ok2xx(st) or not isinstance(pend, list):
        print("  ? 读不到 finals_pending: HTTP %s %s" % (st, str(pend)[:160]))
        NOTE.append("读不到 finals_pending，这一项没验")
    else:
        print("  分母: 有滞留的周 %d 个" % len(pend))
        for p in pend:
            print("    周%s: %s 人待分桶" % (p.get("season_week"), p.get("n")))
        if pend and live:
            NOTE.append("有人在 finals_pending 里等分桶 —— 分桶那一步跑了没有？")

    # ★自证(下): ⑥ 刚才**自己**有没有把注入的那个桶报出来
    if selftest:
        head("★自证(下): ⑥ 报了没有")
        hit = [x for x in BAD if str(SELF_WK) in x]
        print("  ⑥ 报出来的问题里提到 周%d 的: %d 条" % (SELF_WK, len(hit)))
        for h in hit:
            print("    %s" % h)
        if hit:
            print("  ⇒ **工具有效**: 明显卡住的桶它会报。")
        else:
            print("  ⇒ ★★**工具是死的**: 造了个卡 9 小时的桶它都不报 ——")
            print("     那么「没发现问题」这句话一文不值。")
        ## 把自证造的那条从结论里摘掉(它是我注入的, 不是真问题),
        ## 但**摘之前先证明它在过** —— 顺序不能反。
        for h in hit:
            BAD.remove(h)
        sql("delete from public.finals_buckets where season_week = %d" % SELF_WK)
        st, chk = sql("select count(*) as n from public.finals_buckets "
                      "where season_week = %d" % SELF_WK)
        left = int(chk[0]["n"]) if (ok2xx(st) and isinstance(chk, list) and chk) else -1
        print("  收尾: 注入的数据已清(剩 %d 行)" % left)
        if left != 0:
            BAD.append("★自证注入的假数据没清干净(周%d 还剩 %d 行)" % (SELF_WK, left))
        if not hit:
            BAD.append("★自证失败: 对「卡了 9 小时」的桶也不报 —— 这工具不可信")

    # ── 收口 ──
    print("")
    print("=" * 56)
    for n in NOTE:
        print("  说明: %s" % n)
    if BAD:
        print("  ★ 有 %d 个真问题:" % len(BAD))
        for b in BAD:
            print("     - %s" % b)
        return 1
    print("  ✓ 没发现问题%s" % ("（注意上面的说明：现在为空是因为玩法还没上线，"
                              "这一项的价值要等上线那天才兑现）" if live is False else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
