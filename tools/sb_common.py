# -*- coding: utf-8 -*-
"""tools/sb_common.py —— 内测服 / 正式服两台 Supabase 的共用底座(2026-10-21 · 方案书 docs/plans/20261020-内测服.md)。

给 tools/beta_ops.py、tools/sb_migrate.py 与 tools/probe_*.py 用。只做四件事:
  ① 两台的项目 ref / 地址 / 令牌文件(令牌只从本机文件读, 不打印、不进仓库)
  ② 跑 SQL(Management API `POST /v1/projects/{ref}/database/query`, 一律绕开本机代理)
  ③ ★正式服写保护: 只有 `prod_write_ok=True` 显式放行才能对正式服发写语句;
     只读查询走 `query_ro()`, 它在同一个请求里先 `set transaction read only`
     (2026-10-21 实测: `set default_transaction_read_only = on` 对同一请求里的语句**不生效**, 照样建出了表)。
  ④ 探针选台 `probe_target()`: 默认内测服, `--prod` 才连正式服

★本机代理会改写 POST body(memory fb-local-proxy-corrupts-post-body) ⇒ ProxyHandler({})。
"""
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

PROD_REF = "cjefldecsfpnclhfwriw"
BETA_REF = "twxkroptuqbfhmlojjgl"
REFS = {"prod": PROD_REF, "beta": BETA_REF}
URLS = {r: "https://%s.supabase.co" % r for r in (PROD_REF, BETA_REF)}
_HOME = os.path.expanduser("~")
TOKEN_FILES = {
    PROD_REF: os.path.join(_HOME, ".supabase", "access-token"),
    BETA_REF: os.path.join(_HOME, ".supabase", "beta-access-token"),
}
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
## 公开 key(设计上就嵌进客户端; 与 project.godot 的 turtle/supabase_anon_key / .beta_server 同值)
PUBLISHABLE = {
    PROD_REF: "sb_publishable_tvCm2DPO9SflJHME9K_MGA_u04tG8bi",
    BETA_REF: "sb_publishable_bLKRe9xrtS5knJhyDRK4jg_Pc7NZJ-f",
}

## 探针走客户端通道时要带的版本头(服务端最低版本闸: 不带 = 当成 (none) ⇒ PT426 update_required)。
##   与 scripts/net/supabase.gd 的 HDR_CLIENT_VERSION 同名; 取值 = project.godot 的 config/version(版本号事实源)。
HDR_CLIENT_VERSION = "X-Client-Version"


def client_version():
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "project.godot")
    m = re.search(r'^config/version="([^"]+)"', io.open(p, encoding="utf-8").read(), re.M)
    if not m:
        raise SystemExit("project.godot 里找不到 config/version")
    return m.group(1)


def probe_target():
    """探针工具(tools/probe_*.py)选台: 默认内测服, 命令行带 `--prod` 才连正式服(方案书 §6 表「探针工具」那一行)。

    由来: 探针会建匿名测试号、写假周数据 —— 跑在正式服上的那些年, 10-04 清过 585 个垃圾号、10-18 手删 9 号 11 行。
    `--prod` 从 sys.argv 里拿掉, 各工具自己的参数解析不受影响。开头打一行目标, 输出里看得出量的是哪台。
    返回 (ref, url, 公开 key, 管理令牌文件)。客户端通道的请求头记得带 {HDR_CLIENT_VERSION: client_version()}。
    """
    prod = "--prod" in sys.argv
    while "--prod" in sys.argv:
        sys.argv.remove("--prod")
    ref = PROD_REF if prod else BETA_REF
    if prod:
        print("★目标: 正式服 %s(--prod)—— 连的是正式库" % ref)
    else:
        print("目标: 内测服 %s(连正式服要加 --prod)" % ref)
    return ref, URLS[ref], PUBLISHABLE[ref], TOKEN_FILES[ref]


class ProdRefused(SystemExit):
    """对正式服的写被拒(写死的拒绝, 不是配置)。"""


def refuse_prod(ref_or_text, what):
    """参数里只要出现正式服 ref 就退出。beta_ops 的每个入口都先过这一道。"""
    if PROD_REF in str(ref_or_text):
        msg = "★拒绝: %s 只对内测服(%s); 收到的参数里有正式服 ref %s" % (what, BETA_REF, PROD_REF)
        print(msg)
        raise ProdRefused(3)


def _token(ref):
    p = TOKEN_FILES.get(ref)
    if p is None:
        raise SystemExit("不认识的项目 ref: %s" % ref)
    if not os.path.exists(p):
        raise SystemExit("缺令牌文件 %s" % p)
    return io.open(p, encoding="utf-8").read().strip()


def api(ref, method, path, body=None, timeout=180):
    """Management API。返回 (status, parsed-or-text)。429 退避重试。"""
    tok = _token(ref)
    url = "https://api.supabase.com" + path.replace("{ref}", ref)
    for attempt in range(6):
        r = urllib.request.Request(url, method=method,
                                   data=None if body is None else json.dumps(body).encode(),
                                   headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
        try:
            with OPENER.open(r, timeout=timeout) as resp:
                t = resp.read().decode("utf-8")
                try:
                    return resp.status, (json.loads(t) if t.strip() else None)
                except ValueError:
                    return resp.status, t
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 5:
                time.sleep(8 * (attempt + 1))
                continue
            return e.code, e.read().decode("utf-8", "replace")[:4000]
    return 0, "unreachable"


class SqlError(RuntimeError):
    pass


def query(ref, sql, prod_write_ok=False):
    """跑 SQL(可写)。正式服必须显式 prod_write_ok=True —— beta_ops 永远不传。"""
    if ref == PROD_REF and not prod_write_ok:
        raise ProdRefused("★拒绝: 对正式服的写语句没有显式放行(prod_write_ok)")
    st, b = api(ref, "POST", "/v1/projects/{ref}/database/query", {"query": sql})
    if st not in (200, 201):
        raise SqlError("HTTP %s: %s" % (st, b))
    return b


def query_ro(ref, sql):
    """只读查询: 同一请求先 `set transaction read only` ⇒ 里面任何写都会被库拒。"""
    body = sql.strip().rstrip(";")
    st, b = api(ref, "POST", "/v1/projects/{ref}/database/query",
                {"query": "set transaction read only;\n" + body + ";"})
    if st not in (200, 201):
        raise SqlError("HTTP %s: %s" % (st, b))
    return b


def one(rows):
    """[{...}] → {...}; 空 → {}"""
    if isinstance(rows, list) and rows:
        return rows[0]
    return {}


def stdout_utf8():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass


# ── 结构指纹(sb_migrate diff 与建库对账共用) ─────────────────────
FINGERPRINT_SQL = r"""
select jsonb_build_object(
 'funcs', (select jsonb_object_agg(p.oid::regprocedure::text, jsonb_build_object(
            'md5', md5(regexp_replace(p.prosrc, '\s+', ' ', 'g')), 'secdef', p.prosecdef, 'vol', p.provolatile,
            'acl', coalesce(p.proacl::text, ''), 'cfg', coalesce(p.proconfig::text, '')))
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'),
 'cols', (select jsonb_object_agg(table_name || '.' || column_name,
            data_type || '|' || coalesce(column_default, '') || '|' || is_nullable)
           from information_schema.columns where table_schema = 'public'),
 'pols', (select jsonb_object_agg(tablename || '.' || policyname,
            cmd || '|' || coalesce(qual, '') || '|' || coalesce(with_check, '') || '|' || roles::text)
           from pg_policies where schemaname = 'public'),
 'tacl', (select jsonb_object_agg(c.relname, coalesce(c.relacl::text, '') || '|rls=' || c.relrowsecurity)
           from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relkind in ('r', 'v', 'm')),
 'cons', (select jsonb_object_agg(conrelid::regclass::text || '.' || conname, pg_get_constraintdef(oid))
           from pg_constraint where connamespace = 'public'::regnamespace),
 'idx', (select jsonb_object_agg(indexname, indexdef) from pg_indexes where schemaname = 'public'),
 'trg', (select jsonb_object_agg(tgrelid::regclass::text || '.' || tgname, pg_get_triggerdef(oid))
          from pg_trigger where not tgisinternal
           and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
 'cron', (select jsonb_object_agg(jobname, schedule || '|' || regexp_replace(command, '\s+', ' ', 'g')) from cron.job),
 'roles', (select jsonb_object_agg(rolname, coalesce(rolconfig::text, ''))
            from pg_roles where rolname in ('authenticator', 'anon', 'authenticated'))
) as fp
"""


def fingerprint(ref):
    return one(query_ro(ref, FINGERPRINT_SQL)).get("fp") or {}


def diff_fingerprints(a, b, label_a="a", label_b="b"):
    """返回 [(类别, 名字, a 值, b 值)]。"""
    out = []
    for k in sorted(set(a) | set(b)):
        da = a.get(k) or {}
        db = b.get(k) or {}
        for n in sorted(set(da) | set(db)):
            if da.get(n) != db.get(n):
                out.append((k, n, da.get(n), db.get(n)))
    return out
