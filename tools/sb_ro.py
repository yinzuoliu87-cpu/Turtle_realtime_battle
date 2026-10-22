"""只读查询一条 SQL(正式服 / 内测服)。用户 2026-10-22 放行「正式服只读查询」时建的窄口子。

    python tools/sb_ro.py prod "select count(*) from auth.users"
    python tools/sb_ro.py beta "select ..."

只认**一条** select / with 语句(不许分号): sb_common.query_ro 是在同一个请求里先
`set transaction read only` 再拼上正文 —— 正文里要是再带一个 `commit; ...` 就能逃出只读事务,
所以这里把多语句整个挡掉。权限规则只放行这个脚本, 不放行任意 python。
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402


def main() -> int:
    S.stdout_utf8()
    if len(sys.argv) != 3 or sys.argv[1] not in S.REFS:
        print("用法: python tools/sb_ro.py prod|beta \"select ...\"")
        return 2
    sql = sys.argv[2].strip().rstrip(";").strip()
    if ";" in sql:
        print("★拒绝: 只认一条语句(正文里不许有分号)")
        return 2
    if not re.match(r"(?is)^\s*(select|with)\b", sql):
        print("★拒绝: 只认 select / with 开头的查询")
        return 2
    rows = S.query_ro(S.REFS[sys.argv[1]], sql)
    print(json.dumps(rows, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
