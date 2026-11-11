"""tools/referee_version.py —— 登记裁判版本(referee_versions 一行)的固定做法(2026-11-11, 取代按版本复制的 oneoff/register_0231_prod.py)。

服务端对没登记的客户端版本一律回 update_required(玩家看到「需要更新」墙)⇒ 每次发版 deploy.py 装完、切陪练号之前登记一次。
rules_ver 从 tag v<版本> 那一提交的 RULES_VER 读(不手填), 与 deploy.py 传给服务器核对的是同一个数。

  python tools/referee_version.py 0.23.2 --env beta                 只读: 打印现状 + 将要写的 SQL
  python tools/referee_version.py 0.23.2 --env beta --apply         内测服写 + 回读
  python tools/referee_version.py 0.23.2 --env prod --apply --yes-prod   正式服写 + 回读(★每次都要用户点头; --yes-prod 不是授权)
"""
import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rules_ver_at_tag(ver: str) -> int:
    src = subprocess.run(["git", "show", "v%s:scripts/gamedata/phase2_config.gd" % ver], cwd=REPO,
                         capture_output=True, text=True, encoding="utf-8")
    if src.returncode != 0:
        raise SystemExit("★找不到 tag v%s(先 release.py tag): %s" % (ver, src.stderr.strip()))
    m = re.search(r"^const RULES_VER := (\d+)", src.stdout, re.M)
    if not m:
        raise SystemExit("★tag v%s 那一提交里读不到 RULES_VER" % ver)
    return int(m.group(1))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--env", choices=["beta", "prod"], required=True)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--yes-prod", action="store_true")
    a = ap.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", a.version):
        raise SystemExit("★版本号格式不对: %s" % a.version)
    rv = rules_ver_at_tag(a.version)
    ref = S.REFS[a.env]
    show = ("select client_version, enabled, rules_ver, added_at from public.referee_versions "
            "order by added_at desc limit 5")
    print("现状(%s):" % a.env, json.dumps(S.query_ro(ref, show), ensure_ascii=False, default=str))
    sql = ("insert into public.referee_versions (client_version, rules_ver) values ('%s', %d) "
           "on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;" % (a.version, rv))
    print("将写:", sql)
    if not a.apply:
        print("(只读演练; 加 --apply 才写)")
        return 0
    if a.env == "prod" and not a.yes_prod:
        raise SystemExit("★正式服写入要 --yes-prod(且要用户点头)")
    S.query(ref, sql, prod_write_ok=(a.env == "prod"))
    back = S.query_ro(ref, "select client_version, enabled, rules_ver from public.referee_versions "
                           "where client_version = '%s'" % a.version)
    ok = len(back) == 1 and back[0].get("enabled") is True and int(back[0].get("rules_ver", -1)) == rv
    print("回读:", json.dumps(back, ensure_ascii=False, default=str), "✓" if ok else "✗")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
