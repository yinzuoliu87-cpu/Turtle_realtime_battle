"""正式服登记裁判版本 0.23.1(2026-11-10 用户「现在就直接发版」)。deploy.py 0.23.1 DEPLOY OK 之后、切陪练号之前。
SQL 照 deploy.py 打印的那一条, 写完回读。"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import sb_common as sb  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
SQL = ("insert into public.referee_versions (client_version, rules_ver) values ('0.23.1', 5) "
       "on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;")
print("写:", SQL)
print(sb.query(sb.PROD_REF, SQL, prod_write_ok=True))
rows = sb.query_ro(sb.PROD_REF, "select client_version, enabled, rules_ver, added_at from public.referee_versions "
                                "where client_version in ('0.23.1', '0.22.9') order by client_version")
print("回读:", json.dumps(rows, ensure_ascii=False, default=str))
