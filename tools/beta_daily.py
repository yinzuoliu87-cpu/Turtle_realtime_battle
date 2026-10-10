# -*- coding: utf-8 -*-
"""tools/beta_daily.py —— 内测每日数据(只读)。

用户 2026-10-10:「周一我就给他们发包，然后周二他们开始打，我们自己看后台数据」。
还没有后台界面 ⇒ 这个脚本就是后台: 一条命令看某一天(UTC)服务端的真实情况。

★只读: 只发 select。走管理员通道(与 tools/probe_finals_health.py 同一个 sql())。
★把「模拟号」和「其他人(朋友 / 我们自己)」分开数: 模拟号的 account_id 从本机模拟存档里读
  (默认 C:/tmp/turtle-sim60/pNN/.../savegame.json)。读不到就全算「其他人」并在输出里说明。
★每一项都打分母(N=0 是空检查不是「没问题」)。

用法:
    python tools/beta_daily.py                    # 今天(UTC)
    python tools/beta_daily.py --day 2026-10-13   # 指定某天
    python tools/beta_daily.py --sim-root D:/x    # 模拟存档根目录
退出码: 0 = 跑完 / 2 = 查不了(令牌 / 网络)
"""
import argparse
import datetime as dt
import glob
import io
import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_finals_health import sql  # noqa: E402  管理员通道 + 绕代理, 同一份

WEEK_SEC = 7 * 86400
MONDAY0 = 1790553600  # 2026-09-28 周一 00:00 UTC(任一周一都行, 只用来算周锚点)


def q(text):
    st, rows = sql(text)
    if not (200 <= int(st or 0) < 300) or not isinstance(rows, list):
        print("[查不了] HTTP %s %s" % (st, str(rows)[:300]))
        sys.exit(2)
    return rows


def sim_ids(root):
    ids = set()
    for f in glob.glob(os.path.join(root, "p*", "Godot", "app_userdata", "*", "savegame.json")):
        try:
            a = str(json.load(io.open(f, encoding="utf-8")).get("account_id", "")).strip()
        except Exception:
            continue
        if a:
            ids.add(a)
    return ids


def in_list(ids):
    return "('" + "','".join(sorted(ids)) + "')" if ids else "('00000000-0000-0000-0000-000000000000')"


def pct(a, b):
    return "%d/%d (%.0f%%)" % (a, b, 100.0 * a / b) if b else "%d/0" % a


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--day", default=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d"))
    ap.add_argument("--sim-root", default="C:/tmp/turtle-sim60")
    a = ap.parse_args()
    d0 = dt.datetime.strptime(a.day, "%Y-%m-%d").replace(tzinfo=dt.timezone.utc)
    t0 = int(d0.timestamp())
    t1 = t0 + 86400
    wk = MONDAY0 + ((t0 - MONDAY0) // WEEK_SEC) * WEEK_SEC
    sims = sim_ids(a.sim_root)
    S = in_list(sims)
    day = "to_timestamp(%d) and to_timestamp(%d)" % (t0, t1)
    print("══ 内测每日数据 · %s (UTC) · 周锚点 %d ══" % (a.day, wk))
    print("模拟号: 本机读到 %d 个 account_id(%s)%s" % (len(sims), a.sim_root,
          "" if sims else " ⚠ 一个都没读到 ⇒ 下面全算「其他人」"))

    ## ① 账号
    r = q("select count(*) filter (where created_at between %s) new_all, "
          "count(*) filter (where created_at between %s and is_anonymous) new_anon, "
          "count(*) filter (where created_at between %s and not is_anonymous) new_bound "
          "from auth.users where id::text not in %s" % (day, day, day, S))[0]
    ## ★「上过线」不读 accounts.last_seen —— 那张表没人写(2026-10-10 实测 0 行)。改数当天往服务端传过东西的账号。
    act = q("select count(distinct a) n from (select left_account a from public.matches where created_at between %s "
            "union all select account_id from public.ghosts where uploaded_at between %s "
            "union all select account_id from public.gauntlet_ghosts where uploaded_at between %s "
            "union all select account_id from public.live_matches where started_at between %s) t "
            "where a::text not in %s" % (day, day, day, day, S))[0]
    print("\n① 账号(其他人)")
    print("  当天新注册 %s 个(游客 %s / 已绑定 %s)" % (r["new_all"], r["new_anon"], r["new_bound"]))
    print("  当天传过对局 / 快照 / 直播的 %s 个" % act["n"])

    ## ② 对局(matches = 录像上传成功的那些; 投降局 / 没传上去的不在这里)
    ## ★对手是不是真人: `right_account` 故意恒为 null(填了机器人就露馅, replay_uploader.gd 头注)。
    ##   ⇒ 用赛况板同一条规则: 对手的 #ID 自己传过录像 = 真人(机器人一场一个新号, 从不当录像方)。
    m = q("select case when m.left_account::text in %s then '模拟号' else '其他人' end who, m.phase, "
          "count(*) n, count(*) filter (where exists (select 1 from public.matches m2 where "
          "m2.left_snapshot->'profile'->>'tag' = m.right_snapshot->'profile'->>'tag')) vs_human, "
          "count(*) filter (where (m.result->>'won')::boolean) won, count(distinct m.left_account) players "
          "from public.matches m where m.created_at between %s group by 1, 2 order by 1, 2" % (S, day))
    print("\n② 对局(录像已上传的)")
    if not m:
        print("  N=0 —— 当天一场都没有")
    for x in m:
        print("  %s · %-8s %4d 场 · %3d 人 · 对手是真人 %s · 录像方胜 %s" % (
            x["who"], x["phase"], x["n"], x["players"], pct(x["vs_human"], x["n"]), pct(x["won"], x["n"])))
    v = q("select coalesce(client_version,'?') v, count(*) n from public.matches where created_at between %s "
          "and left_account::text not in %s group by 1 order by 2 desc" % (day, S))
    print("  其他人的客户端版本: " + (", ".join("%s×%s" % (x["v"], x["n"]) for x in v) if v else "N=0"))

    ## ③ 本周进度(每人取最新一份积分赛快照)
    g = q("select count(*) n, "
          "count(*) filter (where hearts <= 0) out_, "
          "count(*) filter (where season_wins >= 11) promoted, "
          "coalesce(max(battles),0) maxb, coalesce(round(avg(battles)::numeric,1),0) avgb "
          "from (select distinct on (account_id) account_id, battles, season_wins, hearts from public.ghosts "
          "where season_week=%d and account_id::text not in %s "
          "and coalesce(snapshot->'gl_w','0'::jsonb)='0'::jsonb and coalesce(snapshot->'gl_l','0'::jsonb)='0'::jsonb "
          "order by account_id, battles desc, uploaded_at desc) t" % (wk, S))[0]
    print("\n③ 本周积分赛进度(其他人, 每人最新一份)")
    print("  有快照的 %s 人 · 平均打到第 %s 场(最多 %s) · 11 胜过线 %s · 没命出局 %s" % (
        g["n"], g["avgb"], g["maxb"], g["promoted"], g["out_"]))

    ## ④ 此刻在打
    lv = q("select count(*) filter (where account_id::text not in %s) others, count(*) n from public.live_matches "
           "where not ended and updated_at > now() - interval '60 seconds'" % S)[0]
    print("\n④ 此刻正在打(直播行 60 秒内有更新)  其他人 %s / 全部 %s" % (lv["others"], lv["n"]))

    ## ⑤ 要看一眼的
    up = q("select count(*) n from public.live_matches l where l.started_at between %s and l.ended "
           "and l.account_id::text not in %s and not exists (select 1 from public.matches m where m.match_id = l.match_id)" % (day, S))[0]
    stale = q("select count(*) n from public.live_matches where started_at between %s and not ended "
              "and updated_at < now() - interval '10 minutes' and account_id::text not in %s" % (day, S))[0]
    idle = q("select count(*) n from auth.users u where u.created_at between %s and u.id::text not in %s "
             "and not exists (select 1 from public.matches m where m.left_account = u.id)" % (day, S))[0]
    print("\n⑤ 要看一眼的(其他人)")
    print("  直播已打完、录像却没进 matches: %s 场(录像上传失败 / 还在补传)" % up["n"])
    print("  直播开了没结束、10 分钟没更新: %s 场(中途退出 / 掉线 / 杀进程)" % stale["n"])
    print("  当天新注册、一场都没传上来: %s 个(只走了教学 / 卡在某处 / 没联网)" % idle["n"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
