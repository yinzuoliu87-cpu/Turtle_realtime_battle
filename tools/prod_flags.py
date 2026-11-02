# -*- coding: utf-8 -*-
"""tools/prod_flags.py —— 正式服开关与强制更新（2026-11-02 · 方案书 20261102-文件管理与发版流程重整 §4.2 P4）。

此前这一步是临时手写 SQL；「苹果审过才能抬最低版本」只记在 memory 里（抬早了公测玩家被关在门外）。

  show [--env prod|beta]                    【只读】referee_config 全部开关（ranked_on / ranked_any_day /
                                            ranked_client_write / finals_version …）、service_status.min_client_version、
                                            referee_versions 每一行、两个对手池按 rules_ver 的行数
  set <键> <值> [--env] [--dry-run] [--yes-prod]
                                            只认白名单里的键（FLAGS）；正式服要 --yes-prod；写完回读
  force-update <版本> [--env] [--yes-prod]  service_status.min_client_version 抬到 <版本>。前置检查：
                                            ① 只升不降 ② tools/asc.py 查到这一版有构建 betaReviewState = APPROVED
                                            ③ referee_versions 里有这一版且 enabled（裁判机装好了，tools/deploy.py）
                                            不带 --yes-prod ⇒ 只打计划

表与列以 server/supabase/schema.sql 为准：
  service_status（id = 1）：min_client_version / maintenance / notice / clock_offset_sec
  referee_config（id = 1）：finals_on / gauntlet_on / gauntlet_any_day / finals_version / stream_on / stream_version /
                            gauntlet_server_pick / finals_sequential / ranked_on / ranked_any_day / ranked_client_write …
  referee_versions：client_version / enabled / rules_ver / added_at
  gauntlet_bot_pool、ranked_pool：按 rules_ver 分代
★只读走 sb_common.query_ro（同一请求先 set transaction read only）；写只在 --yes-prod 时传 prod_write_ok=True。
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release as R  # noqa: E402
import sb_common as S  # noqa: E402

## set 能改的键：键 → (表, 类型, 说明)。不在这里的一律拒（改别的走 sb_migrate 或先加进来）。
FLAGS = {
    "ranked_on": ("referee_config", "bool", "积分赛对局由服务器裁判算（关 = 客户端本机那一路）"),
    "ranked_any_day": ("referee_config", "bool", "内测服彩排：不限周二~周五（正式服保持 false）"),
    "ranked_client_write": ("referee_config", "bool", "客户端还能不能直接写积分赛成绩（切换的最后一步才关）"),
    "finals_version": ("referee_config", "version", "周日任务按哪个客户端版本算（必须在 referee_versions 里且 enabled）"),
    "stream_version": ("referee_config", "version", "逐帧直播按哪个客户端版本出（必须在 referee_versions 里且 enabled）"),
}
## 正式服上只许是 false 的键
PROD_FALSE_ONLY = {"ranked_any_day"}
SHOW_FIRST = ["ranked_on", "ranked_any_day", "ranked_client_write", "finals_version"]

SNAPSHOT_SQL = """
select jsonb_build_object(
 'cfg', (select to_jsonb(c) from public.referee_config c where c.id = 1),
 'status', (select to_jsonb(s) from public.service_status s where s.id = 1),
 'versions', (select coalesce(jsonb_agg(to_jsonb(v) order by v.added_at desc), '[]'::jsonb) from public.referee_versions v),
 'gpool', (select coalesce(jsonb_agg(x order by x.rules_ver), '[]'::jsonb)
             from (select rules_ver, count(*) as n from public.gauntlet_bot_pool group by 1) x),
 'rpool', (select coalesce(jsonb_agg(x order by x.rules_ver, x.kind), '[]'::jsonb)
             from (select kind, rules_ver, count(*) as n from public.ranked_pool group by 1, 2) x)
) as j
"""


def ref_of(env):
    return S.REFS[env]


def snapshot(env):
    return S.one(S.query_ro(ref_of(env), SNAPSHOT_SQL)).get("j") or {}


def _ver_ok(v):
    try:
        R.vtuple(v)
        return True
    except R.ReleaseError:
        return False


def enabled_versions(snap):
    return {v.get("client_version"): v for v in snap.get("versions") or [] if v.get("enabled")}


def cmd_show(a):
    env = a.env
    snap = snapshot(env)
    cfg = snap.get("cfg") or {}
    st = snap.get("status") or {}
    print("%s %s（只读）" % ("★正式服" if env == "prod" else "内测服", ref_of(env)))
    print("service_status: min_client_version = %s / maintenance = %s / clock_offset_sec = %s / 更新于 %s" % (
        st.get("min_client_version"), st.get("maintenance"), st.get("clock_offset_sec"), str(st.get("updated_at"))[:19]))
    if st.get("notice"):
        print("  notice: %s" % str(st.get("notice"))[:200])
    print("referee_config（%d 列，更新于 %s）:" % (len(cfg), str(cfg.get("updated_at"))[:19]))
    keys = SHOW_FIRST + sorted(k for k in cfg if k not in SHOW_FIRST and k not in ("id", "updated_at"))
    for k in keys:
        print("  %s %-22s = %s" % ("·" if k in FLAGS else " ", k, json.dumps(cfg.get(k), ensure_ascii=False)))
    vs = snap.get("versions") or []
    print("referee_versions（%d 行）:" % len(vs))
    for v in sorted(vs, key=lambda x: R.vtuple(x["client_version"]) if _ver_ok(x.get("client_version")) else (0,),
                    reverse=True):
        print("  %-9s enabled=%-5s rules_ver=%-4s 登记于 %s" % (
            v.get("client_version"), v.get("enabled"), v.get("rules_ver"), str(v.get("added_at"))[:16]))
    print("gauntlet_bot_pool: %s" % (", ".join("rules_ver %s = %s 行" % (x["rules_ver"], x["n"])
                                              for x in snap.get("gpool") or []) or "空"))
    print("ranked_pool: %s" % (", ".join("rules_ver %s %s = %s 行" % (x["rules_ver"], x["kind"], x["n"])
                                         for x in snap.get("rpool") or []) or "空"))
    for k in ("finals_version", "stream_version"):
        v = cfg.get(k)
        if v and v not in enabled_versions(snap):
            print("  ⚠ %s = %s 不在 referee_versions 的 enabled 行里" % (k, v))
    return 0


def parse_value(key, raw):
    typ = FLAGS[key][1]
    if typ == "bool":
        s = raw.strip().lower()
        if s in ("true", "on", "1", "yes"):
            return True
        if s in ("false", "off", "0", "no"):
            return False
        raise SystemExit("%s 是开关，值只认 true / false" % key)
    if not _ver_ok(raw):
        raise SystemExit("%s 要 x.y.z 形式的版本号" % key)
    return raw


def sql_literal(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if not _ver_ok(v):   # 只放行纯版本号，拼进 SQL 也不会出事
        raise SystemExit("拒绝拼进 SQL 的值: %r" % v)
    return "'%s'" % v


def _write(env, sql):
    S.query(ref_of(env), sql, prod_write_ok=(env == "prod"))


def cmd_set(a):
    env = a.env
    key = a.key
    if key not in FLAGS:
        print("✗ 不在白名单里: %s（只认 %s）" % (key, ", ".join(sorted(FLAGS))))
        return 2
    table, typ, note = FLAGS[key]
    val = parse_value(key, a.value)
    if env == "prod" and key in PROD_FALSE_ONLY and val is not False:
        print("✗ %s 在正式服只许是 false（%s）" % (key, note))
        return 1
    snap = snapshot(env)
    cur = (snap.get("cfg") or {}).get(key)
    if typ == "version" and val not in enabled_versions(snap):
        print("✗ %s 不在 %s 的 referee_versions enabled 行里（裁判机没装这一版）—— 先 tools/deploy.py" % (val, env))
        return 1
    print("%s %s.%s: %s → %s（%s）" % (env, table, key, json.dumps(cur), json.dumps(val), note))
    if cur == val:
        print("已经是这个值，不用改")
        return 0
    if a.dry_run:
        print("（演练: 没有写）")
        return 0
    if env == "prod" and not a.yes_prod:
        print("✗ 对正式服写要 --yes-prod（并且先得到用户同意）")
        return 1
    _write(env, "update public.%s set %s = %s, updated_at = now() where id = 1" % (table, key, sql_literal(val)))
    got = (snapshot(env).get("cfg") or {}).get(key)
    print("回读: %s = %s %s" % (key, json.dumps(got), "✓" if got == val else "✗"))
    return 0 if got == val else 1


def cmd_force_update(a):
    env = a.env
    ver = a.version
    R.vtuple(ver)
    snap = snapshot(env)
    cur = (snap.get("status") or {}).get("min_client_version") or "0.0.0"
    print("%s service_status.min_client_version: 现在 %s → 要抬到 %s" % (env, cur, ver))
    probs = []
    if _ver_ok(cur) and R.vtuple(ver) == R.vtuple(cur):
        print("已经是 %s，不用改" % ver)
        return 0
    if _ver_ok(cur) and R.vtuple(ver) < R.vtuple(cur):
        probs.append("只升不降（%s < 现在的 %s）" % (ver, cur))
    # ② 苹果 Beta 审核过了没有（没过就抬 = 公测玩家装不到能进游戏的包）
    try:
        import asc as A
        rows = A.build_rows(ver, detail=False)
        okb = [r for r in rows if r["review"] == "APPROVED" and not r["expired"]]
        print("  App Store Connect %s: %s" % (ver, ", ".join(
            "%s %s%s" % (r["number"], r["review"] or "未提交", " 已作废" if r["expired"] else "") for r in rows) or "没有构建"))
        if not okb:
            probs.append("苹果还没批 %s 的 Beta 审核（要有一份没作废、betaReviewState = APPROVED 的构建）"
                         "—— 早抬会把公测玩家关在门外" % ver)
    except Exception as e:  # noqa: BLE001 —— 查不到 = 不放行
        probs.append("查不到苹果审核状态: %s" % e)
    # ③ 裁判机装了这一版
    ev = enabled_versions(snap)
    if ver not in ev:
        probs.append("referee_versions 里没有 enabled 的 %s（裁判机没装 ⇒ 新包的裁判局没人算）—— 先 tools/deploy.py %s" % (ver, ver))
    else:
        print("  referee_versions %s: enabled, rules_ver = %s" % (ver, ev[ver].get("rules_ver")))
    for p in probs:
        print("✗ " + p)
    if probs:
        print("✗ 不抬（%d 个问题）" % len(probs))
        return 1
    print("计划: update public.service_status set min_client_version = '%s', updated_at = now() where id = 1" % ver)
    print("  ⚠ 陪练号的 BOT_GAME_DIR 也得 ≥ %s，否则一进主菜单就被版本墙拦下（tools/deploy.py 管）" % ver)
    if env == "prod" and not a.yes_prod:
        print("（没带 --yes-prod：只打计划，没有写。对正式服写要先得到用户同意）")
        return 1
    _write(env, "update public.service_status set min_client_version = %s, updated_at = now() where id = 1" % sql_literal(ver))
    got = (snapshot(env).get("status") or {}).get("min_client_version")
    print("回读: min_client_version = %s %s" % (got, "✓" if got == ver else "✗"))
    return 0 if got == ver else 1


def main(argv=None):
    S.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    x = sp.add_parser("show", help="【只读】开关 / 最低版本 / 裁判版本 / 对手池")
    x.add_argument("--env", choices=["prod", "beta"], default="prod")
    x.set_defaults(fn=cmd_show)
    x = sp.add_parser("set", help="改白名单里的一个开关")
    x.add_argument("key")
    x.add_argument("value")
    x.add_argument("--env", choices=["prod", "beta"], default="prod")
    x.add_argument("--dry-run", action="store_true")
    x.add_argument("--yes-prod", action="store_true")
    x.set_defaults(fn=cmd_set)
    x = sp.add_parser("force-update", help="min_client_version 抬到 <版本>（苹果审过 + 裁判机装好才放行）")
    x.add_argument("version")
    x.add_argument("--env", choices=["prod", "beta"], default="prod")
    x.add_argument("--yes-prod", action="store_true")
    x.set_defaults(fn=cmd_force_update)
    a = ap.parse_args(argv)
    try:
        return a.fn(a)
    except R.ReleaseError as e:
        print("✗ %s" % e)
        return 2
    except S.SqlError as e:
        print("✗ SQL: %s" % str(e)[:600])
        return 2


if __name__ == "__main__":
    sys.exit(main() or 0)
