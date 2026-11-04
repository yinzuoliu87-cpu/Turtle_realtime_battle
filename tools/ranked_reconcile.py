"""ranked_reconcile.py —— 积分赛服务器账本三方对账（只读；方案书 docs/plans/20261101c-积分赛服务器裁判.md V9，Issue #1）。

  python tools/ranked_reconcile.py [--env prod|beta] [--week N]   # 不给 --week 用账本里最新那一周

三方：
  ① 账本 ranked_records（每人每周：场次 battles / 胜 wins / 命 hearts / 横扫 sweeps）
  ② 快照 ghosts：同一人同一周场次最大的那份 —— 场次 = 账本场次，胜 / 命 / 横扫 与账本一致
  ③ 任务 referee_jobs（kind = ranked, status = done, a_account = 本人, season_week = 该周, 去重键不带 :void）个数 = 账本场次
     （seeded = true 的账本行是从客户端账本接过来的，起点不是 0 ⇒ 只比 ①②，③ 单列）
另报：该周积分赛任务的状态分布、平均 / 最长出结果时间。全对上打印 ALL OK，否则逐行列出对不上的人。
"""
import argparse, json, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
PY = sys.executable


def q(env, sql):
    r = subprocess.run([PY, "tools/sb_ro.py", env, sql], capture_output=True, text=True, encoding="utf-8")
    out = r.stdout
    i = out.find("[")
    if i < 0:
        raise SystemExit("查询失败: %s" % (out + r.stderr)[-400:])
    return json.loads(out[i:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", default="prod", choices=["prod", "beta"])
    ap.add_argument("--week", type=int)
    a = ap.parse_args()
    wk = a.week
    if wk is None:
        rows = q(a.env, "select max(season_week) w from public.ranked_records")
        wk = int(rows[0]["w"])
    rec = q(a.env, "select account_id, battles, wins, hearts, sweeps, seeded from public.ranked_records where season_week = %d" % wk)
    gh = q(a.env, "select distinct on (account_id) account_id, battles, season_wins, hearts, season_sweeps from public.ghosts "
                  "where season_week = %d order by account_id, battles desc" % wk)
    ## 带 `:void` 的任务 = 测试号被 tools/reset_test_account.py 重置前打的（账本那一行已删）⇒ 不数
    jobs = q(a.env, "select a_account, count(*) n from public.referee_jobs where kind = 'ranked' and status = 'done' "
                    "and season_week = %d and match_key not like '%%:void%%' group by a_account" % wk)
    ## a_account 为空 = 那个号后来删了（referee_jobs 外键 on delete set null，账本行随删号级联删掉）⇒ 不对账，单列报数
    deleted = [r for r in jobs if r["a_account"] is None]
    jobs = [r for r in jobs if r["a_account"] is not None]
    st = q(a.env, "select status, count(*) n, round(avg(extract(epoch from (done_at - created_at)))::numeric, 1) avg_s, "
                  "round(max(extract(epoch from (done_at - created_at)))::numeric, 1) max_s from public.referee_jobs "
                  "where kind = 'ranked' and season_week = %d group by status order by 2 desc" % wk)
    G = {r["account_id"]: r for r in gh}
    J = {r["a_account"]: int(r["n"]) for r in jobs}
    bad = []
    seeded_job_diff = 0
    for r in rec:
        acc = r["account_id"]
        b, w, h, s = int(r["battles"]), int(r["wins"]), int(r["hearts"]), int(r["sweeps"])
        g = G.get(acc)
        if b > 0:
            if g is None:
                bad.append("%s 账本 %d 场 / 快照没有" % (acc[:8], b))
            elif (int(g["battles"]), int(g["season_wins"]), int(g["hearts"]), int(g["season_sweeps"])) != (b, w, h, s):
                bad.append("%s 账本 场%d 胜%d 命%d 扫%d ≠ 快照 场%s 胜%s 命%s 扫%s" % (acc[:8], b, w, h, s, g["battles"],
                           g["season_wins"], g["hearts"], g["season_sweeps"]))
        nj = J.get(acc, 0)
        if r.get("seeded"):
            if nj != b:
                seeded_job_diff += 1
        elif nj != b:
            bad.append("%s 账本 %d 场 ≠ 服务器完成任务 %d 个" % (acc[:8], b, nj))
    orphan = [acc for acc in J if acc not in {r["account_id"] for r in rec}]
    for acc in orphan:
        bad.append("%s 有 %d 个完成任务但账本没有这人" % (acc[:8], J[acc]))
    print("第 %d 周 · %s" % (wk, a.env))
    print("[分母] 账本 %d 人 · 快照 %d 人 · 有完成任务的 %d 人 · 完成任务合计 %d 个" % (len(rec), len(gh), len(J), sum(J.values())))
    if deleted:
        print("  （已删号的完成任务 %d 个：账号已不存在，账本随删号删掉，不对账）" % sum(int(r["n"]) for r in deleted))
    for s in st:
        print("  任务 %-8s %5s 个  平均 %ss  最长 %ss" % (s["status"], s["n"], s["avg_s"], s["max_s"]))
    if seeded_job_diff:
        print("  （seeded 账本行 %d 个：起点来自客户端账本，任务数本来就少，只比账本与快照）" % seeded_job_diff)
    if bad:
        for x in bad[:30]:
            print("[FAIL] " + x)
        print("\nFAILED: %d 处" % len(bad))
        return 1
    print("\nALL OK —— 账本 = 快照 = 服务器完成任务（%d 人）" % len(rec))
    return 0


if __name__ == "__main__":
    sys.exit(main())
