# -*- coding: utf-8 -*-
"""tools/sb_migrate.py —— 服务端迁移的固定流程（2026-10-21 · 方案书 docs/plans/20261020-内测服.md §5）。

一份迁移 = server/supabase/migrations/<名>.sql（同时作为一段 `-- >>> BEGIN … <<< END` 追加在 schema.sql 末尾）
          + server/supabase/tests/<名>_check.sql（结尾一定抛异常：'ALL PASS (N 条)' 或 'FAIL …' ⇒ 整段回滚）。

标准路径（每一步不过就停）：
  1. sandbox <名>              本机 PGlite：schema.sql + 迁移 + 检查脚本 ⇒ ALL PASS（要 PGLITE_MODULE，见 tools/sql_sandbox.mjs 头注）
  2. beta --rehearse <名>       内测服回滚事务里「迁移 + 检查脚本」⇒ ALL PASS；事后结构指纹与表行数不变
  2b. beta --check <名>         只跑检查脚本（不带迁移）：验内测服「上完 + beta_setup 之后」的样子
  3. beta --apply <名>          先自动再演练一遍；单事务执行；notify pgrst；重跑 beta_setup.sql；
                                回读函数体与迁移文件逐字相同；记 schema_migrations（name + sha256）
  4. （内测服冒烟：beta_ops 剧本 / 模拟号）
  5. prod --precheck <名>       【只读】生产现行函数体 == 仓库迁移前版本（去注释空白）；内测服账本里有同名同 sha256
  6. prod --rehearse <名>       生产回滚事务里「迁移 + 检查脚本」⇒ ALL PASS（要 --yes-prod）
  7. prod --apply <名>          ★拒绝内测服账本里没有同名同 sha256 的迁移；要 --yes-prod；
                                紧急修复 --hotfix：两边账本都记一行（note=hotfix），并提示事后补走内测服
其他：
  diff                         两边结构指纹对比（函数体 / grants / RLS / 约束 / 触发器 / cron），【对正式服只读】
  status                       仓库迁移清单 × 两边账本
  backfill beta                把仓库现有迁移按 sha256 记进内测服账本（建库时用；那些段已随 schema.sql 执行过）

★sha256 按「行尾归一成 LF」算（仓库行尾是混的，memory fb-orphan-worktrees-hold-unmerged-work）。
★本工具对正式服的写只发生在 `prod --rehearse/--apply/--hotfix` 且带 `--yes-prod` 时；其余一律只读。
"""
import argparse
import getpass
import hashlib
import io
import json
import os
import re
import socket
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(REPO, "server", "supabase", "schema.sql")
MIG_DIR = os.path.join(REPO, "server", "supabase", "migrations")
CHK_DIR = os.path.join(REPO, "server", "supabase", "tests")
BETA_SETUP = os.path.join(REPO, "server", "supabase", "beta", "beta_setup.sql")
# 账本里比对时跳过的、内测服独有的结构差异（diff 子命令据此分「已解释 / 未解释」）
BETA_ONLY_CRON = {"beta_tick"}
PROD_ONLY_CRON = {"finals_seat", "finals_cup_seat", "finals_advance"}   # 内测服由 beta_tick 代替


def read_lf(path):
    return io.open(path, encoding="utf-8", newline="").read().replace("\r\n", "\n")


def sha256_lf(path):
    return hashlib.sha256(read_lf(path).encode("utf-8")).hexdigest()


def mig_path(name):
    name = os.path.basename(name)
    if name.endswith(".sql"):
        name = name[:-4]
    p = os.path.join(MIG_DIR, name + ".sql")
    if not os.path.exists(p):
        raise SystemExit("没有这份迁移: %s" % p)
    return name, p


def chk_path(name):
    p = os.path.join(CHK_DIR, name + "_check.sql")
    return p if os.path.exists(p) else None


def statement_count(sql):
    """粗数顶层语句（行尾 ';' 且不在 $$ 体内）—— 只用来打印分母、发现「截多了 / 截少了」。"""
    n = 0
    in_body = None
    for line in sql.split("\n"):
        s = line.strip()
        if s.startswith("--"):
            continue
        for m in re.finditer(r"\$[a-zA-Z_]*\$", line):
            tag = m.group(0)
            if in_body is None:
                in_body = tag
            elif in_body == tag:
                in_body = None
        if in_body is None and s.endswith(";"):
            n += 1
    return n


def section_markers(sql):
    begins = re.findall(r"^-- >>> (?:BEGIN )?(.+?) >>>\s*$", sql, re.M)
    ends = re.findall(r"^-- <<< END (.+?) <<<\s*$", sql, re.M)
    return begins, ends


def check_mirror(name, path):
    """迁移文件必须逐字（行尾归一）出现在 schema.sql 里，且起止标记各唯一（memory fb-sql-extract-by-unique-marker）。"""
    m = read_lf(path).strip("\n")
    s = read_lf(SCHEMA)
    begins, ends = section_markers(m)
    problems = []
    if len(begins) != 1 or len(ends) != 1:
        problems.append("迁移文件里 BEGIN/END 标记不是各 1 个: %d/%d" % (len(begins), len(ends)))
    else:
        b_line = "-- >>> BEGIN %s >>>" % begins[0] if ("BEGIN " + begins[0]) in m else "-- >>> %s >>>" % begins[0]
        if s.count(b_line) != 1:
            problems.append("schema.sql 里起始标记出现 %d 次（要恰好 1 次）: %s" % (s.count(b_line), b_line))
    if m not in s:
        problems.append("迁移文件内容没有逐字出现在 schema.sql 里（追加那一段与文件不一致）")
    return problems


def func_bodies(sql):
    """迁移里每个 create or replace function 的 (签名头, 函数体)；体 = 两个同名 dollar 标记之间。"""
    out = []
    for m in re.finditer(r"create\s+or\s+replace\s+function\s+(public\.[\w]+)\s*\(", sql, re.I):
        rest = sql[m.end():]
        t = re.search(r"\$[a-zA-Z_]*\$", rest)
        if not t:
            continue
        tag = t.group(0)
        b0 = m.end() + t.end()
        b1 = sql.find(tag, b0)
        if b1 < 0:
            continue
        out.append((m.group(1), sql[b0:b1]))
    return out


def _norm_body(b):
    """去注释（-- 到行尾）与空白 —— 只用于「生产现行 == 仓库迁移前」的比对。"""
    b = re.sub(r"--[^\n]*", "", b.replace("\r\n", "\n"))
    return re.sub(r"\s+", " ", b).strip()


def run_with_check(ref, mig_sql, chk_sql, prod_write_ok=False):
    """回滚事务里「迁移 + 检查脚本」。检查脚本自带的 begin 去掉，整段一个事务，结尾异常 ⇒ 全回滚。"""
    chk = re.sub(r"^\s*begin\s*;\s*$", "", chk_sql, count=1, flags=re.I | re.M)
    body = "begin;\n" + mig_sql + "\n" + chk
    if ref == S.PROD_REF:
        st, b = (S.api(ref, "POST", "/v1/projects/{ref}/database/query", {"query": body})
                 if prod_write_ok else (0, "refused"))
        if not prod_write_ok:
            raise S.ProdRefused("★拒绝: 正式服演练要 --yes-prod")
    else:
        st, b = S.api(ref, "POST", "/v1/projects/{ref}/database/query", {"query": body})
    text = b if isinstance(b, str) else json.dumps(b, ensure_ascii=False)
    m = re.search(r"ALL PASS \((\d+) 条\)", text)
    return (m is not None), text, (int(m.group(1)) if m else 0)


COUNT_SQL = """
select jsonb_object_agg(relname, n_live) as c from (
  select c.relname, (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text::bigint as n_live
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r') x
"""


def table_counts(ref):
    return S.one(S.query_ro(ref, COUNT_SQL)).get("c") or {}


def ledger(ref):
    try:
        rows = S.query_ro(ref, "select name, sha256, applied_at::text, applied_by, note from public.schema_migrations order by name")
        return {r["name"]: r for r in rows}
    except S.SqlError as e:
        if "schema_migrations" in str(e) and "does not exist" in str(e):
            return None
        raise


def prod_apply_allowed(name, sha, beta_ledger, hotfix=False):
    """纯函数（自测量它）：正式服只收内测服账本里同名同 sha256 的迁移；--hotfix 例外但要两边记账。"""
    if hotfix:
        return True, "hotfix: 两边账本都记一行, 事后补走内测服"
    if beta_ledger is None:
        return False, "内测服没有 schema_migrations 账本"
    row = beta_ledger.get(name)
    if row is None:
        return False, "内测服没上过 %s" % name
    if row.get("sha256") != sha:
        return False, "内测服上的 %s sha256=%s… 与仓库 %s… 不同（迁移在内测服之后又改过）" % (
            name, str(row.get("sha256"))[:12], sha[:12])
    return True, "内测服 %s 已上（%s）" % (name, row.get("applied_at"))


def who():
    try:
        return "%s@%s" % (getpass.getuser(), socket.gethostname())
    except Exception:
        return "unknown"


def readback_bodies(ref, mig_sql):
    """回读迁移里每个函数的现行体，与迁移文件逐字（行尾归一）比较。返回 (总数, 不同的名字列表)。"""
    fb = func_bodies(mig_sql)
    if not fb:
        return 0, []
    names = sorted({n for n, _ in fb})
    want = {}
    for n, b in fb:
        want[n] = b   # 同名多次定义取最后一次
    rows = S.query_ro(ref, "select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
                           "where n.nspname = 'public' and p.proname = any(array[%s])"
                      % ",".join("'%s'" % x.split(".")[1] for x in names))
    live = {}
    for r in rows:
        live.setdefault("public." + r["proname"], []).append(r["prosrc"].replace("\r\n", "\n"))
    bad = [n for n in names if want[n].replace("\r\n", "\n") not in live.get(n, [])]
    return len(names), bad


def beta_setup_sql():
    return ("select set_config('turtle.beta_ref', '%s', false);\n" % S.BETA_REF) + read_lf(BETA_SETUP)


# ── 子命令 ──────────────────────────────────────────────────────
def cmd_sandbox(a):
    name, p = mig_path(a.name)
    c = chk_path(name)
    if not c:
        raise SystemExit("缺检查脚本 %s_check.sql —— 没有检查脚本的迁移不进流程" % name)
    if not os.environ.get("PGLITE_MODULE"):
        raise SystemExit("PGLITE_MODULE 没设（见 tools/sql_sandbox.mjs 头注）")
    r = subprocess.run(["node", os.path.join(REPO, "tools", "sql_sandbox.mjs"), p, c], cwd=REPO,
                       capture_output=True, text=True, encoding="utf-8")
    print(r.stdout.strip())
    if r.returncode != 0 or "ALL PASS" not in r.stdout:
        print("✗ sandbox 没过"); return 1
    print("✓ sandbox ALL PASS"); return 0


def _preflight(name, p):
    sql = read_lf(p)
    probs = check_mirror(name, p)
    print("迁移 %s: %d 字 / 顶层语句约 %d 条 / 函数 %d 个 / sha256 %s" % (
        name, len(sql), statement_count(sql), len(func_bodies(sql)), sha256_lf(p)))
    for x in probs:
        print("  ✗ " + x)
    if probs:
        raise SystemExit(2)
    return sql


def _rehearse(ref, name, p, prod_write_ok=False):
    sql = _preflight(name, p)
    c = chk_path(name)
    if not c:
        raise SystemExit("缺检查脚本 %s_check.sql" % name)
    fp0 = S.fingerprint(ref)
    n0 = table_counts(ref)
    ok, text, n = run_with_check(ref, sql, read_lf(c), prod_write_ok=prod_write_ok)
    fp1 = S.fingerprint(ref)
    n1 = table_counts(ref)
    d = S.diff_fingerprints(fp0, fp1)
    dn = {k: (n0.get(k), n1.get(k)) for k in set(n0) | set(n1) if n0.get(k) != n1.get(k)}
    print("  演练: %s（%d 条）" % ("ALL PASS" if ok else "没过", n))
    if not ok:
        print("  " + text[:3000])
    print("  事后结构指纹差异 %d 处 / 表行数变化 %d 张（分母: %d 张表）" % (len(d), len(dn), len(n0)))
    for k in d[:10]:
        print("    结构变了: %s %s" % (k[0], k[1]))
    for k, v in sorted(dn.items()):
        print("    行数变了: %s %s → %s（演练期间别处有写入？）" % (k, v[0], v[1]))
    return ok and not d, sql


def cmd_beta(a):
    name, p = mig_path(a.name)
    if a.check:
        # 只跑检查脚本（不带迁移）: 验「内测服现在的样子」—— 上完迁移 + beta_setup 之后用
        c = chk_path(name)
        if not c:
            raise SystemExit("缺检查脚本 %s_check.sql" % name)
        ok, text, n = run_with_check(S.BETA_REF, "", read_lf(c))
        print("  内测服现状检查: %s（%d 条）" % ("ALL PASS" if ok else "没过", n))
        if not ok:
            print("  " + text[:3000])
        return 0 if ok else 1
    if a.rehearse or a.apply:
        ok, sql = _rehearse(S.BETA_REF, name, p)
        if not ok:
            print("✗ 内测服演练没过 ⇒ 停"); return 1
        print("✓ 内测服演练过了")
    if not a.apply:
        return 0
    sha = sha256_lf(p)
    led0 = ledger(S.BETA_REF)
    body = ("begin;\n" + sql + "\n"
            + "insert into public.schema_migrations (name, sha256, applied_by, note) values ('%s', '%s', '%s', 'sb_migrate beta --apply')\n"
              "  on conflict (name) do update set sha256 = excluded.sha256, applied_at = now(), applied_by = excluded.applied_by, note = excluded.note;\n"
            % (name, sha, who().replace("'", ""))
            + "commit;\nnotify pgrst, 'reload schema';\n")
    S.query(S.BETA_REF, body)
    S.query(S.BETA_REF, beta_setup_sql())
    total, bad = readback_bodies(S.BETA_REF, sql)
    led1 = ledger(S.BETA_REF) or {}
    print("  回读函数体: %d 个, 不同 %d 个 %s" % (total, len(bad), bad))
    print("  账本: 之前 %s 行 → 之后 %d 行; %s = %s…" % (
        "无表" if led0 is None else len(led0), len(led1), name, (led1.get(name) or {}).get("sha256", "")[:12]))
    if bad or (led1.get(name) or {}).get("sha256") != sha:
        print("✗ 回读不一致"); return 1
    print("✓ 内测服已上 %s" % name); return 0


def cmd_prod(a):
    name, p = mig_path(a.name)
    sql = _preflight(name, p)
    sha = sha256_lf(p)
    okb, why = prod_apply_allowed(name, sha, ledger(S.BETA_REF), hotfix=a.hotfix)
    print("  内测服账本: %s" % why)
    if not okb:
        print("✗ 拒绝: 正式服只收内测服上过、同一 sha256 的迁移"); return 1
    # 【只读】生产现行函数体 == 仓库迁移前版本
    s = read_lf(SCHEMA)
    begins, _ = section_markers(sql)
    cut = s.find(sql.strip("\n")) if begins else -1
    before = s[:cut] if cut > 0 else ""
    prev = {}
    for n, b in func_bodies(before):
        prev[n] = b
    mine = sorted({n for n, _ in func_bodies(sql)})
    rows = S.query_ro(S.PROD_REF, "select p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
                                  "where n.nspname = 'public' and p.proname = any(array[%s])"
                      % ",".join("'%s'" % x.split(".")[1] for x in mine) if mine else "select 1 where false")
    live = {}
    for r in rows:
        live.setdefault("public." + r["proname"], []).append(_norm_body(r["prosrc"]))
    drift = []
    for n in mine:
        if n in prev:
            if _norm_body(prev[n]) not in live.get(n, []):
                drift.append(n)
    newf = [n for n in mine if n not in prev]
    print("  生产现行 vs 仓库迁移前: 比了 %d 个函数, 漂移 %d 个 %s; 本迁移新建 %d 个" % (
        len(mine) - len(newf), len(drift), drift, len(newf)))
    if drift:
        print("✗ 生产函数体与仓库迁移前版本不同 ⇒ 先查清是谁在面板上改的"); return 1
    if a.precheck and not (a.rehearse or a.apply):
        print("✓ 只读预检过了（没有对正式服写任何东西）"); return 0
    if not a.yes_prod:
        print("✗ 对正式服的演练 / 执行要 --yes-prod（并且先得到用户同意）"); return 1
    if a.rehearse or a.apply:
        ok, _ = _rehearse(S.PROD_REF, name, p, prod_write_ok=True)
        if not ok:
            print("✗ 正式服演练没过 ⇒ 停"); return 1
    if not a.apply:
        return 0
    note = "hotfix" if a.hotfix else "sb_migrate prod --apply"
    body = ("begin;\n" + sql + "\n"
            + "insert into public.schema_migrations (name, sha256, applied_by, note) values ('%s', '%s', '%s', '%s')\n"
              "  on conflict (name) do update set sha256 = excluded.sha256, applied_at = now(), applied_by = excluded.applied_by, note = excluded.note;\n"
            % (name, sha, who().replace("'", ""), note)
            + "commit;\nnotify pgrst, 'reload schema';\n")
    S.query(S.PROD_REF, body, prod_write_ok=True)
    if a.hotfix:
        S.query(S.BETA_REF, "insert into public.schema_migrations (name, sha256, applied_by, note) values ('%s', '%s', '%s', 'hotfix: 正式服先上, 内测服待补')"
                            " on conflict (name) do nothing" % (name, sha, who().replace("'", "")))
    total, bad = readback_bodies(S.PROD_REF, sql)
    print("  回读函数体: %d 个, 不同 %d 个 %s" % (total, len(bad), bad))
    return 1 if bad else 0


def cmd_diff(a):
    fb = S.fingerprint(S.BETA_REF)
    fp = S.fingerprint(S.PROD_REF)   # 只读
    d = S.diff_fingerprints(fb, fp)
    led_b = ledger(S.BETA_REF) or {}
    led_p = ledger(S.PROD_REF) or {}
    # 正式服还没有账本时: 内测服账本里 note 以 backfill 开头的那些 = 建库时随 schema.sql 执行的历史迁移(正式服早就上过)
    pending = sorted(n for n, r in led_b.items()
                     if n not in led_p and not (not led_p and str(r.get("note", "")).startswith("backfill")))
    explained, unexplained = [], []
    for k, n, vb, vp in d:
        why = None
        if k == "cron" and (n in BETA_ONLY_CRON or n in PROD_ONLY_CRON):
            why = "内测服用 beta_tick 代替周日三条 cron（方案书 §2.5）"
        elif k == "cons" and n == "server_clock.server_clock_prod_zero":
            why = "内测服删了「偏移恒 0」约束（beta_setup.sql）"
        elif k == "funcs" and n == "rls_auto_enable()":
            why = "Supabase 面板「自动开 RLS」事件触发器（平台功能，不在仓库；内测服 bootstrap 补了同款）"
        elif pending and vp is None:
            why = "内测服已上、正式服未上的迁移带来的新对象（%s）" % ", ".join(pending)
        elif pending and k == "funcs" and vb is not None and vp is not None:
            why = "内测服已上、正式服未上的迁移改过的函数（%s）" % ", ".join(pending)
        (explained if why else unexplained).append((k, n, vb, vp, why))
    print("结构差异 %d 处（分母: 内测服 %d 个函数 / 正式服 %d 个函数）: 已解释 %d / 未解释 %d" % (
        len(d), len(fb.get("funcs") or {}), len(fp.get("funcs") or {}), len(explained), len(unexplained)))
    for k, n, vb, vp, why in explained:
        print("  · %s %s —— %s" % (k, n, why))
    for k, n, vb, vp, why in unexplained:
        print("  ✗ %s %s\n      beta: %s\n      prod: %s" % (k, n, str(vb)[:200], str(vp)[:200]))
    return 1 if unexplained else 0


def cmd_status(a):
    names = sorted(f[:-4] for f in os.listdir(MIG_DIR) if f.endswith(".sql"))
    lb = ledger(S.BETA_REF)
    lp = ledger(S.PROD_REF)
    print("仓库迁移 %d 份; 内测服账本 %s; 正式服账本 %s" % (
        len(names), "无表" if lb is None else "%d 行" % len(lb), "无表" if lp is None else "%d 行" % len(lp)))
    for n in names:
        sha = sha256_lf(os.path.join(MIG_DIR, n + ".sql"))
        def mark(l):
            if l is None:
                return "  -  "
            r = l.get(n)
            if r is None:
                return " 未上 "
            return " ✓   " if r.get("sha256") == sha else " ≠sha "
        print("  %s|%s| %s" % (mark(lb), mark(lp), n))
    return 0


def cmd_backfill(a):
    if a.target != "beta":
        raise SystemExit("backfill 只做内测服（正式服账本由正式服首次执行 20261021 迁移后再回填, 要用户点头）")
    names = sorted(f[:-4] for f in os.listdir(MIG_DIR) if f.endswith(".sql"))
    led0 = ledger(S.BETA_REF)
    if led0 is None:
        raise SystemExit("内测服还没有 schema_migrations 表")
    rows = []
    for n in names:
        if n in led0 and not a.force:
            continue
        rows.append("('%s', '%s', '%s', 'backfill: 随 schema.sql 建库时执行')" % (
            n, sha256_lf(os.path.join(MIG_DIR, n + ".sql")), who().replace("'", "")))
    if rows:
        S.query(S.BETA_REF, "insert into public.schema_migrations (name, sha256, applied_by, note) values %s "
                            "on conflict (name) do update set sha256 = excluded.sha256" % ", ".join(rows))
    led1 = ledger(S.BETA_REF) or {}
    print("内测服账本: %d 行 → %d 行（仓库 %d 份, 本次写 %d 行）" % (len(led0), len(led1), len(names), len(rows)))
    return 0


def main():
    S.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    x = sp.add_parser("sandbox"); x.add_argument("name"); x.set_defaults(fn=cmd_sandbox)
    x = sp.add_parser("beta"); x.add_argument("name")
    x.add_argument("--rehearse", action="store_true"); x.add_argument("--apply", action="store_true")
    x.add_argument("--check", action="store_true", help="只跑检查脚本(不带迁移), 验内测服现状")
    x.set_defaults(fn=cmd_beta)
    x = sp.add_parser("prod"); x.add_argument("name")
    x.add_argument("--precheck", action="store_true"); x.add_argument("--rehearse", action="store_true")
    x.add_argument("--apply", action="store_true"); x.add_argument("--hotfix", action="store_true")
    x.add_argument("--yes-prod", action="store_true")
    x.set_defaults(fn=cmd_prod)
    x = sp.add_parser("diff"); x.set_defaults(fn=cmd_diff)
    x = sp.add_parser("status"); x.set_defaults(fn=cmd_status)
    x = sp.add_parser("backfill"); x.add_argument("target"); x.add_argument("--force", action="store_true")
    x.set_defaults(fn=cmd_backfill)
    a = ap.parse_args()
    if a.cmd == "prod" and not (a.precheck or a.rehearse or a.apply):
        a.precheck = True
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main() or 0)
