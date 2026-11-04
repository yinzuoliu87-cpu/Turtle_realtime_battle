"""reset_test_account.py —— 把测试号整个重置（云存档 + 本周积分赛账本 + 本周快照 + 本周积分赛任务的去重键）。

  python tools/reset_test_account.py <账号 uuid>                    # 只读演练：查现状、备份、生成重置后的存档、打印要改什么
  python tools/reset_test_account.py <账号 uuid> --apply --yes-prod  # 真写正式服（一个事务里四处一起改，带条件，失败整体回滚）

为什么四处（2026-11-04，0.22.7 起积分赛由服务器裁判）：
  ① saves：存档换成产品 `GameState.reset_save()` 的结果（保留昵称 / 称号 / 历届决赛 / 新手完成），save_rev +1，只在版本号没变时才写。
  ② ranked_records：删本周这一行 —— 不删的话手机一开战就被服务器以账本为准拉回原来的场次 / 余命。
  ③ ghosts：删本周这个号的快照 —— 账本没有行时 `ranked_ledger_peek` 会拿本周快照补种账本。
  ④ referee_jobs：本周这个号的积分赛任务去重键加 `:void<日期>` —— 不改的话新打的第 0 场按 `ranked:周:号:0` 撞上旧任务、直接返回旧结果。
     任务行本身保留（历史 / 录像还在）；`tools/ranked_reconcile.py` 不数带 `:void` 的任务。
只认 ACCOUNTS 里的测试号（防止手滑重置真人）。正式服写入每次都要用户点头（CLAUDE.md §3）—— `--yes-prod` 只是开关，不是授权。
备份与中间文件在 `.out/reset_acct/<时间>/`（含存档全文，不进仓库）。手机上要「设置 → 邮箱登录」把新版本拉回来，或在存档冲突里选云端。
"""
import datetime, json, os, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sb_common as S  # noqa: E402

GODOT = os.environ.get("GODOT") or r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe"
ACCOUNTS = {
    "b250de29-1be0-4b17-81bc-a97ea91376d2": "LouisT01 #F5ZRDR（用户手机测试号；10-22 / 10-27 / 11-04 用户要求重置过）",
}
TAG = "$rstpl$"


def ro(sql):
    return S.query_ro(S.REFS["prod"], sql)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv and "--yes-prod" in sys.argv
    if len(args) != 1 or args[0] not in ACCOUNTS:
        raise SystemExit("✗ 只认测试号白名单里的账号: %s" % ", ".join("%s（%s）" % kv for kv in ACCOUNTS.items()))
    acc = args[0]
    print("账号 %s —— %s" % (acc, ACCOUNTS[acc]))
    week = int(ro("select max(season_week) w from public.ranked_records")[0]["w"])
    sv = ro("select save_rev, client_version, updated_at, payload from public.saves where account_id = '%s'" % acc)
    if len(sv) != 1:
        raise SystemExit("✗ saves 里这个号不是恰好一行（%d）" % len(sv))
    sv = sv[0]
    payload = sv["payload"] if isinstance(sv["payload"], dict) else json.loads(sv["payload"])
    rr = ro("select * from public.ranked_records where account_id = '%s' and season_week = %d" % (acc, week))
    gh = ro("select * from public.ghosts where account_id = '%s' and season_week = %d" % (acc, week))
    jb = ro("select job_id, match_key, status from public.referee_jobs where a_account = '%s' and season_week = %d "
            "and kind = 'ranked' and match_key not like '%%:void%%' order by job_id" % (acc, week))
    inflight = [j for j in jb if j["status"] in ("pending", "claimed")]
    print("本周 %d · 存档第 %s 版（%s，%s）· 本周 %s 场 %s 胜 · 账本 %d 行 · 快照 %d 份 · 积分赛任务 %d 个（在算 %d）"
          % (week, sv["save_rev"], sv["client_version"], sv["updated_at"], payload.get("season_total_battles"),
             payload.get("season_wins"), len(rr), len(gh), len(jb), len(inflight)))
    if inflight:
        raise SystemExit("✗ 有在算的积分赛任务 %s —— 等它算完再重置" % [j["job_id"] for j in inflight])
    d = os.path.join(ROOT, ".out", "reset_acct", datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    os.makedirs(d, exist_ok=True)
    json.dump({"account": acc, "week": week, "saves": {**sv, "payload": payload}, "ranked_records": rr, "ghosts": gh, "jobs": jb},
              open(os.path.join(d, "backup.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    json.dump(payload, open(os.path.join(d, "payload_in.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("备份 → %s" % os.path.relpath(os.path.join(d, "backup.json"), ROOT))
    ## 用产品自己的 reset_save() 生成重置后的存档（隔离 user://，不连服务器）
    ud = os.path.join(d, "ud")
    env = {**os.environ, "APPDATA": ud, "XDG_DATA_HOME": ud, "TURTLE_SUPABASE": " ", "TURTLE_BACKEND": " ",
           "RESET_IN": os.path.join(d, "payload_in.json"), "RESET_OUT": os.path.join(d, "payload_out.json")}
    p = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "res://tests/probes/_reset_save_runner.tscn",
                        "--quit-after", "600"], capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=300)
    lines = [l for l in (p.stdout + p.stderr).splitlines() if l.startswith("[RESET]")]
    for l in lines:
        print("  " + l)
    if p.returncode != 0 or "[RESET] OK" not in lines:
        raise SystemExit("✗ 生成重置存档失败（退出码 %d）" % p.returncode)
    out = json.load(open(os.path.join(d, "payload_out.json"), encoding="utf-8"))
    hearts_max = int(out.get("hearts", 0))
    ok = (out.get("nickname") == payload.get("nickname") and int(out.get("season_total_battles", -1)) == 0
          and int(out.get("season_wins", -1)) == 0 and int(out.get("season_level", 0)) == 1 and hearts_max > 0
          and set(out) == set(payload))
    if not ok:
        raise SystemExit("✗ 重置后的存档不像重置过（昵称 / 场次 / 胜场 / 等级 / 命 / 键集）—— 不写")
    body = json.dumps(out, ensure_ascii=False)
    if TAG in body:
        raise SystemExit("✗ 存档里含引号标记 %s" % TAG)
    void = ":void" + datetime.date.today().strftime("%Y%m%d")
    print("要改：存档 %s → %s 版 · 删账本 %d 行 · 删快照 %d 份 · 任务去重键加「%s」%d 个"
          % (sv["save_rev"], int(sv["save_rev"]) + 1, len(rr), len(gh), void, len(jb)))
    if not apply:
        print("\n（演练）没写。确认后加 --apply --yes-prod")
        return 0
    sql = """do $do$
declare n int;
begin
  update public.saves set payload = %(tag)s%(body)s%(tag)s::jsonb, save_rev = save_rev + 1, updated_at = now()
   where account_id = '%(acc)s' and save_rev = %(rev)d;
  get diagnostics n = row_count; if n <> 1 then raise exception 'saves 版本变了（%%）', n; end if;
  delete from public.ranked_records where account_id = '%(acc)s' and season_week = %(week)d;
  get diagnostics n = row_count; if n <> %(nrr)d then raise exception 'ranked_records 行数变了（%%）', n; end if;
  delete from public.ghosts where account_id = '%(acc)s' and season_week = %(week)d;
  get diagnostics n = row_count; if n <> %(ngh)d then raise exception 'ghosts 份数变了（%%）', n; end if;
  update public.referee_jobs set match_key = match_key || '%(void)s'
   where a_account = '%(acc)s' and season_week = %(week)d and kind = 'ranked' and match_key not like '%%:void%%';
  get diagnostics n = row_count; if n <> %(njb)d then raise exception 'referee_jobs 个数变了（%%）', n; end if;
end $do$;""" % {"tag": TAG, "body": body, "acc": acc, "rev": int(sv["save_rev"]), "week": week, "nrr": len(rr),
                "ngh": len(gh), "void": void, "njb": len(jb)}
    S.query(S.REFS["prod"], sql, prod_write_ok=True)
    chk = ro("select (select save_rev from public.saves where account_id = '%(a)s') rev, "
             "(select payload->>'season_total_battles' from public.saves where account_id = '%(a)s') battles, "
             "(select payload->>'hearts' from public.saves where account_id = '%(a)s') hearts, "
             "(select count(*) from public.ranked_records where account_id = '%(a)s' and season_week = %(w)d) rr, "
             "(select count(*) from public.ghosts where account_id = '%(a)s' and season_week = %(w)d) gh, "
             "(select count(*) from public.referee_jobs where a_account = '%(a)s' and season_week = %(w)d and kind = 'ranked' "
             "and match_key not like '%%:void%%') jobs" % {"a": acc, "w": week})[0]
    print("回读：%s" % chk)
    good = (int(chk["rev"]) == int(sv["save_rev"]) + 1 and int(chk["battles"]) == 0 and int(chk["rr"]) == 0
            and int(chk["gh"]) == 0 and int(chk["jobs"]) == 0)
    print("\nALL OK —— 已重置；手机上「设置 → 邮箱登录」拉回第 %s 版" % chk["rev"] if good else "\nFAILED —— 回读不对，看上面")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
