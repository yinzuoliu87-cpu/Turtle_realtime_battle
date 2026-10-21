# -*- coding: utf-8 -*-
"""tools/beta_ops.py —— 内测服（turtle-beta）手动推进赛程 / 看状态（2026-10-21 · 方案书 docs/plans/20261020-内测服.md §3）。

★只认内测服：项目 ref 写死成 sb_common.BETA_REF；命令行里出现正式服 ref ⇒ 当场退出（退出码 3），
  这是写死的拒绝，不是配置（tools/beta_server_selftest.py 在门禁里量它）。
★每条会改东西的命令都打印「做之前 / 做之后」的计数（分母），不只打印 OK。

子命令：
  status                     假时间（app_now / 偏移 / 真实 now）、本周（按假时间）各阶段、各表行数、cron、beta_tick 最近一次、
                             配置行、迁移账本、裁判机内测服轮询器停没停（--no-ssh 跳过）
  clock set <时刻>           把服务端假时间设到某一刻。写法：
                               sun 18:05 / 周日 18:05 —— 「真实时间所在那一周」那天的 UTC 时刻（--week +1 = 下一周）
                               2026-10-25T18:05Z      —— 绝对时刻（UTC）
                               +90m / +2h / +1d        —— 在当前假时间上往后拨
  clock reset                偏移归零（假时间 = 真实时间）
  seat                       立刻按假时间的周号叫一次 finals_seat（不等 beta_tick）
  cup-seat                   立刻叫一次 finals_cup_seat
  advance [轮数]             每轮：假时间往后拨 finals_round_sec() + 5 秒，再叫 finals_advance（默认 1 轮）
  close-week                 反复 advance 直到本周（假时间）所有组收盘（最多 30 轮）
  wipe-week <周号>           删掉某一周（season_week = 周号）在所有带 season_week 列的表里的行（打印逐表计数）
  seed-bots [--version V]    让裁判机按内测服 env 生成机器人池（ssh 跑 referee_poller.py --bot-pool）
  signup-smoke               用公开 key 匿名注册一个号 → 回读 auth.users 有它 → 删掉（证明匿名登录开着）
  bootstrap [--schema]       （重新）把内测服配成内测服：beta_setup.sql + 配置行 + 匿名登录；--schema 先整份跑 schema.sql
"""
import argparse
import datetime as dt
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = S.BETA_REF
URL = S.URLS[REF]
## 公开 key（设计上就嵌进客户端，与 project.godot 的 turtle/supabase_anon_key.beta_server 同一个值）
PUBLISHABLE = "sb_publishable_bLKRe9xrtS5knJhyDRK4jg_Pc7NZJ-f"
SSH_KEY = os.path.join(os.path.expanduser("~"), ".ssh", "turtle_referee")
SSH_HOST = "root@49.13.166.188"
WD = {"mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7,
      "周一": 1, "周二": 2, "周三": 3, "周四": 4, "周五": 5, "周六": 6, "周日": 7}
WD_CN = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
## 状态里要数的表（分母）
COUNT_TABLES = ["finals_pending", "finals_buckets", "finals_entrants", "finals_results", "finals_scout",
                "gauntlet_records", "gauntlet_ghosts", "ghosts", "matches", "live_matches", "standings",
                "referee_jobs", "accounts", "saves"]

q = lambda sql: S.query(REF, sql)
qro = lambda sql: S.query_ro(REF, sql)


def clock_row():
    return S.one(qro("""
select public.app_now() as fake, now() as real, (select offset_sec from public.server_clock where id = 1) as off,
       (select env from public.service_env where id = 1) as env,
       (select clock_offset_sec from public.service_status where id = 1) as mirror,
       extract(epoch from date_trunc('week', public.app_now() at time zone 'UTC'))::bigint as week,
       extract(isodow from public.app_now() at time zone 'UTC')::int as dow,
       to_char(public.app_now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') as fake_utc,
       to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS') as real_utc"""))


def counts(week=None):
    parts = []
    for t in COUNT_TABLES:
        parts.append("'%s', (select count(*) from public.%s)" % (t, t))
        if week is not None and t in ("finals_pending", "finals_buckets", "finals_entrants", "finals_results",
                                      "gauntlet_records", "gauntlet_ghosts", "ghosts"):
            parts.append("'%s@周', (select count(*) from public.%s where season_week = %d)" % (t, t, int(week)))
    parts.append("'auth.users', (select count(*) from auth.users)")
    parts.append("'open_buckets@周', (select count(*) from public.finals_buckets where season_week = %d and not closed)" % int(week or 0))
    return S.one(qro("select jsonb_build_object(%s) as c" % ", ".join(parts))).get("c") or {}


def show_counts(before, after, keys=None):
    keys = keys or sorted(set(before) | set(after))
    for k in keys:
        a, b = before.get(k), after.get(k)
        print("    %-24s %6s → %-6s%s" % (k, a, b, "" if a == b else "  *"))


def phase(dow, hhmm):
    h = int(hhmm[:2])
    if dow == 6:
        return "周六闯关日"
    if dow == 7:
        if h < 18:
            return "周日（小组赛 18:00 UTC 才分组）"
        if h < 20:
            return "周日小组赛"
        return "周日冠军杯赛时段"
    return "积分赛日（%s）" % WD_CN[dow]


def ssh(cmd, timeout=60):
    if not os.path.exists(SSH_KEY):
        return None, "没有 %s" % SSH_KEY
    try:
        r = subprocess.run(["ssh", "-i", SSH_KEY, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", SSH_HOST, cmd],
                           capture_output=True, text=True, encoding="utf-8", timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except Exception as e:
        return None, str(e)


# ── 子命令 ──────────────────────────────────────────────────────
def cmd_status(a):
    c = clock_row()
    print("内测服 %s" % URL)
    print("  台: service_env = %s" % c.get("env"))
    print("  假时间 app_now() = %s UTC（%s）  真实 now() = %s UTC  偏移 = %s 秒（客户端镜像 %s）" % (
        c["fake_utc"], WD_CN[int(c["dow"])], c["real_utc"], c["off"], c["mirror"]))
    print("  本周（按假时间）周号 = %s · 阶段: %s" % (c["week"], phase(int(c["dow"]), c["fake_utc"][11:16])))
    n = counts(c["week"])
    print("  行数（分母）:")
    for k in sorted(n):
        print("    %-24s %s" % (k, n[k]))
    jobs = qro("""select j.jobname, j.schedule, j.active,
                  (select d.status || ' @ ' || to_char(d.end_time at time zone 'UTC', 'MM-DD HH24:MI:SS')
                     from cron.job_run_details d where d.jobid = j.jobid order by d.runid desc limit 1) as last
                  from cron.job j order by j.jobname""")
    print("  cron（%d 条）:" % len(jobs))
    for j in jobs:
        print("    %-24s %-16s %s  最近: %s" % (j["jobname"], j["schedule"], "开" if j["active"] else "停", j.get("last")))
    t = S.one(qro("select last_fake, last_real, last_result from public.beta_tick_state where id = 1"))
    print("  beta_tick 最近一次: 真实 %s / 假 %s / %s" % (t.get("last_real"), t.get("last_fake"),
                                                        json.dumps(t.get("last_result"), ensure_ascii=False)))
    cfg = S.one(qro("""select (select to_jsonb(s) - 'notice' - 'updated_at' from public.service_status s) ss,
                            (select to_jsonb(r) - 'updated_at' from public.referee_config r) rc,
                            (select jsonb_agg(v.client_version || '/r' || v.rules_ver || case when v.enabled then '' else '(停)' end
                                     order by v.client_version) from public.referee_versions v) rv,
                            (select count(*) from public.schema_migrations) mig,
                            (select count(*) from public.gauntlet_bot_pool) bots"""))
    print("  service_status: %s" % json.dumps(cfg.get("ss"), ensure_ascii=False))
    print("  referee_config: %s" % json.dumps(cfg.get("rc"), ensure_ascii=False))
    print("  referee_versions: %s · 机器人池 %s 行 · 迁移账本 %s 行" % (cfg.get("rv"), cfg.get("bots"), cfg.get("mig")))
    if not a.no_ssh:
        rc, out = ssh("systemctl is-active turtle-referee-beta turtle-referee-beta-peak.timer turtle-referee; "
                      "systemctl show -p ActiveEnterTimestamp --value turtle-referee-beta")
        if rc is None:
            print("  裁判机: 连不上（%s）" % out)
        else:
            ls = out.splitlines()
            print("  裁判机: 内测服轮询器 %s · 高峰停起 timer %s · 正式服轮询器 %s · 内测服轮询器起于 %s" % (
                ls[0] if ls else "?", ls[1] if len(ls) > 1 else "?", ls[2] if len(ls) > 2 else "?",
                ls[3] if len(ls) > 3 else "?"))
    return 0


def parse_when(s, real_ts, fake_ts, week_shift=0):
    """返回目标 unix 秒（UTC）。解析不了 ⇒ None。"""
    s = s.strip()
    m = re.fullmatch(r"\+(\d+)\s*([mhd])", s)
    if m:
        k = int(m.group(1)) * {"m": 60, "h": 3600, "d": 86400}[m.group(2)]
        return fake_ts + k
    m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})[T ](\d{1,2}):(\d{2})(?::(\d{2}))?Z?", s)
    if m:
        t = dt.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)),
                        int(m.group(6) or 0), tzinfo=dt.timezone.utc)
        return int(t.timestamp())
    m = re.fullmatch(r"(\S+)(?:\s+(\d{1,2}):(\d{2}))?", s)
    if m and m.group(1).lower() in WD:
        wd = WD[m.group(1).lower()]
        h = int(m.group(2) or 0)
        mi = int(m.group(3) or 0)
        if h > 23 or mi > 59:
            return None
        real = dt.datetime.fromtimestamp(real_ts, dt.timezone.utc)
        monday = (real - dt.timedelta(days=real.isoweekday() - 1)).replace(hour=0, minute=0, second=0, microsecond=0)
        t = monday + dt.timedelta(days=wd - 1 + 7 * week_shift, hours=h, minutes=mi)
        return int(t.timestamp())
    return None


def set_offset_to(target_ts):
    """偏移 = 目标 − 服务器 now()（向上取整到秒 ⇒ 假时间不会落在目标前一刻）。"""
    r = S.one(q("update public.server_clock set offset_sec = ceil(%d - extract(epoch from now()))::bigint, updated_at = now() "
                "where id = 1 returning offset_sec" % int(target_ts)))
    return r.get("offset_sec")


def cmd_clock(a):
    c0 = clock_row()
    if c0.get("env") != "beta":
        print("✗ service_env = %s（不是 beta）—— 先 bootstrap" % c0.get("env")); return 1
    if a.action == "reset":
        q("update public.server_clock set offset_sec = 0, updated_at = now() where id = 1")
    else:
        if not a.when:
            print("clock set 要一个时刻（见 --help）"); return 2
        real_ts = int(dt.datetime.strptime(c0["real_utc"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=dt.timezone.utc).timestamp())
        fake_ts = int(dt.datetime.strptime(c0["fake_utc"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=dt.timezone.utc).timestamp())
        tgt = parse_when(" ".join(a.when), real_ts, fake_ts, a.week)
        if tgt is None:
            print("✗ 看不懂的时刻: %s" % " ".join(a.when)); return 2
        set_offset_to(tgt)
    c1 = clock_row()
    print("  假时间: %s UTC（%s, 偏移 %s）→ %s UTC（%s, 偏移 %s）" % (
        c0["fake_utc"], WD_CN[int(c0["dow"])], c0["off"], c1["fake_utc"], WD_CN[int(c1["dow"])], c1["off"]))
    print("  回读: app_now() = %s · service_status.clock_offset_sec = %s（%s）" % (
        c1["fake_utc"], c1["mirror"], "与偏移一致" if c1["mirror"] == c1["off"] else "✗ 与偏移不一致"))
    return 0 if c1["mirror"] == c1["off"] else 1


def _call(fn, label):
    c = clock_row()
    wk = int(c["week"])
    n0 = counts(wk)
    r = S.one(q("select public.%s(%d) as r" % (fn, wk))).get("r")
    n1 = counts(wk)
    print("  %s(周号 %d, 假时间 %s UTC %s) ⇒ %s" % (fn, wk, c["fake_utc"], WD_CN[int(c["dow"])], r))
    show_counts(n0, n1, ["finals_pending@周", "finals_buckets@周", "finals_entrants@周", "finals_results@周",
                         "open_buckets@周", "referee_jobs"])
    return r


def cmd_seat(a):
    _call("finals_seat", "seat"); return 0


def cmd_cup_seat(a):
    _call("finals_cup_seat", "cup-seat"); return 0


def _advance_once():
    rs = S.one(qro("select public.finals_round_sec() as s")).get("s") or 480
    c = clock_row()
    set_offset_to(int(dt.datetime.strptime(c["fake_utc"], "%Y-%m-%d %H:%M:%S")
                      .replace(tzinfo=dt.timezone.utc).timestamp()) + int(rs) + 5)
    return _call("finals_advance", "advance")


def cmd_advance(a):
    for i in range(max(1, a.rounds)):
        print("第 %d 轮:" % (i + 1))
        _advance_once()
    return 0


def cmd_close_week(a):
    c = clock_row()
    wk = int(c["week"])
    open0 = S.one(qro("select count(*) as n from public.finals_buckets where season_week = %d and not closed" % wk)).get("n")
    print("本周（假时间）周号 %d: 没收盘的组 %s 个" % (wk, open0))
    for i in range(30):
        n = S.one(qro("select count(*) as n from public.finals_buckets where season_week = %d and not closed" % wk)).get("n")
        if not n:
            break
        print("第 %d 轮（还有 %s 组没收盘）:" % (i + 1, n))
        _advance_once()
    n = S.one(qro("select count(*) as n from public.finals_buckets where season_week = %d and not closed" % wk)).get("n")
    print("没收盘的组: %s → %s" % (open0, n))
    return 0 if not n else 1


def cmd_wipe_week(a):
    wk = int(a.week)
    if wk < 1000000000:
        print("✗ 周号看着不像周一 00:00 UTC 的 epoch 秒: %d" % wk); return 2
    tabs = [r["table_name"] for r in qro("""select table_name from information_schema.columns
        where table_schema = 'public' and column_name = 'season_week' order by table_name""")]
    b = S.one(qro("select jsonb_build_object(%s) as c" % ", ".join(
        "'%s', (select count(*) from public.%s where season_week = %d)" % (t, t, wk) for t in tabs))).get("c")
    # 依赖顺序: 先删引用别人的（结果 / 参赛者 / 任务），再删被引用的
    order = sorted(tabs, key=lambda t: (0 if t in ("finals_results", "finals_scout", "referee_restream") else
                                        1 if t in ("finals_entrants", "referee_jobs") else 2, t))
    q("begin;\n" + "\n".join("delete from public.%s where season_week = %d;" % (t, wk) for t in order) + "\ncommit;")
    after = S.one(qro("select jsonb_build_object(%s) as c" % ", ".join(
        "'%s', (select count(*) from public.%s where season_week = %d)" % (t, t, wk) for t in tabs))).get("c")
    print("删周号 %d（%d 张带 season_week 的表）:" % (wk, len(tabs)))
    show_counts(b, after)
    return 0


def cmd_seed_bots(a):
    n0 = S.one(qro("select count(*) as n from public.gauntlet_bot_pool")).get("n")
    ver = (" --version %s" % a.version) if a.version else ""
    cmd = ("set -a; . /etc/turtle-referee/env-beta; set +a; "
           "cd /var/lib/turtle-referee-beta && sudo -E -u turtle-referee nice -n 15 python3 /opt/turtle-beta/referee/referee_poller.py --bot-pool%s" % ver)
    rc, out = ssh(cmd, timeout=1800)
    print(out[-3000:] if out else "")
    n1 = S.one(qro("select count(*) as n from public.gauntlet_bot_pool")).get("n")
    print("机器人池: %s → %s 行（ssh 退出码 %s）" % (n0, n1, rc))
    return 0 if rc == 0 else 1


def cmd_signup_smoke(a):
    op = S.OPENER
    u0 = S.one(qro("select count(*) as n from auth.users")).get("n")
    r = urllib.request.Request(URL + "/auth/v1/signup", method="POST", data=b"{}",
                               headers={"apikey": PUBLISHABLE, "Content-Type": "application/json"})
    try:
        with op.open(r, timeout=30) as resp:
            body = json.loads(resp.read().decode())
            code = resp.status
    except urllib.error.HTTPError as e:
        print("✗ 匿名注册 HTTP %s: %s" % (e.code, e.read().decode()[:300])); return 1
    uid = (body.get("user") or {}).get("id", "")
    has_tok = bool(body.get("access_token"))
    seen = S.one(qro("select count(*) as n from auth.users where id = '%s' and is_anonymous" % uid)).get("n") if re.fullmatch(r"[0-9a-f-]{36}", uid) else 0
    u1 = S.one(qro("select count(*) as n from auth.users")).get("n")
    if seen:
        q("delete from auth.users where id = '%s'" % uid)
    u2 = S.one(qro("select count(*) as n from auth.users")).get("n")
    print("匿名注册 HTTP %s · 拿到令牌 %s · auth.users 里有这个匿名号 %s · 用户数 %s → %s → 删后 %s" % (
        code, has_tok, bool(seen), u0, u1, u2))
    return 0 if (has_tok and seen) else 1


BOOT_CONFIG_SQL = """
update public.service_status set maintenance = false, notice = '', min_client_version = '0.21.3', updated_at = now() where id = 1;
update public.referee_config set finals_on = true, gauntlet_on = true, gauntlet_server_pick = true, gauntlet_any_day = false,
  stream_on = true, stream_version = '0.21.0', finals_version = '0.21.4', updated_at = now() where id = 1;
insert into public.referee_versions (client_version, enabled, rules_ver) values ('0.21.3', true, 1), ('0.21.4', true, 1)
  on conflict (client_version) do nothing;
"""

## 正式服面板「自动开 RLS」那个事件触发器的同款（正式服有、仓库没有 —— 内测服补上以免「忘了开 RLS 的表」两边表现不同）
RLS_AUTO_SQL = r"""
create or replace function public.rls_auto_enable() returns event_trigger
language plpgsql security definer set search_path = pg_catalog as $f$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$f$;
drop event trigger if exists ensure_rls;
create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();
"""


def cmd_bootstrap(a):
    if a.schema:
        q("create extension if not exists pg_cron with schema pg_catalog;")
        sql = io.open(os.path.join(REPO, "server", "supabase", "schema.sql"), encoding="utf-8").read()
        print("整份 schema.sql: %d 字" % len(sql))
        q(sql)
    setup = io.open(os.path.join(REPO, "server", "supabase", "beta", "beta_setup.sql"), encoding="utf-8").read()
    q("select set_config('turtle.beta_ref', '%s', false);\n%s" % (REF, setup))
    if a.config:
        q(BOOT_CONFIG_SQL)
    try:
        q(RLS_AUTO_SQL)
        print("  rls_auto_enable 事件触发器: 已装")
    except S.SqlError as e:
        print("  rls_auto_enable 事件触发器: 没装上（%s）" % str(e)[:200])
    st, b = S.api(REF, "PATCH", "/v1/projects/{ref}/config/auth", {"external_anonymous_users_enabled": True})
    st2, b2 = S.api(REF, "GET", "/v1/projects/{ref}/config/auth")
    print("  匿名登录: PATCH %s · 回读 %s" % (st, (b2 or {}).get("external_anonymous_users_enabled") if isinstance(b2, dict) else b2))
    return cmd_status(argparse.Namespace(no_ssh=True))


def main():
    S.stdout_utf8()
    S.refuse_prod(" ".join(sys.argv[1:]) + " " + os.environ.get("TURTLE_BETA_REF", ""), "tools/beta_ops.py")
    S.refuse_prod(REF, "tools/beta_ops.py")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    x = sp.add_parser("status"); x.add_argument("--no-ssh", action="store_true"); x.set_defaults(fn=cmd_status)
    x = sp.add_parser("clock"); x.add_argument("action", choices=["set", "reset"]); x.add_argument("when", nargs="*")
    x.add_argument("--week", type=int, default=0, help="写法是「周X hh:mm」时, 相对真实时间所在那一周再挪几周")
    x.set_defaults(fn=cmd_clock)
    x = sp.add_parser("seat"); x.set_defaults(fn=cmd_seat)
    x = sp.add_parser("cup-seat"); x.set_defaults(fn=cmd_cup_seat)
    x = sp.add_parser("advance"); x.add_argument("rounds", nargs="?", type=int, default=1); x.set_defaults(fn=cmd_advance)
    x = sp.add_parser("close-week"); x.set_defaults(fn=cmd_close_week)
    x = sp.add_parser("wipe-week"); x.add_argument("week"); x.set_defaults(fn=cmd_wipe_week)
    x = sp.add_parser("seed-bots"); x.add_argument("--version", default=""); x.set_defaults(fn=cmd_seed_bots)
    x = sp.add_parser("signup-smoke"); x.set_defaults(fn=cmd_signup_smoke)
    x = sp.add_parser("bootstrap"); x.add_argument("--schema", action="store_true")
    x.add_argument("--config", action="store_true", help="同时把配置行写成内测服初值")
    x.set_defaults(fn=cmd_bootstrap)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main() or 0)
