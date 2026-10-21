# -*- coding: utf-8 -*-
"""beta_server_selftest —— 内测服工具链的自证门禁（2026-10-21 · 方案书 docs/plans/20261020-内测服.md）。

不连网、不读令牌（把 sb_common.api 换成记账的假函数，一条请求都发不出去）。断言：
  ① tools/beta_ops.py：命令行里出现正式服 ref ⇒ 退出码 3、打印「拒绝」；分母：--help 退出码 0
  ② beta_ops 写死的目标 ref = 内测服、≠ 正式服；公开 key 与 project.godot 的 .beta_server 那把逐字相同
  ③ sb_common.query(正式服) 不带 prod_write_ok ⇒ 拒绝且【一条请求都没发】；分母：对内测服同一调用发出 1 条
  ④ sb_migrate.prod_apply_allowed：内测服没上过 / sha256 不同 / 没有账本 ⇒ 拒；同名同 sha ⇒ 收；--hotfix ⇒ 收
  ⑤ 迁移 20261021_beta_server_clock：逐字在 schema.sql 里（标记唯一）、有检查脚本、sha256 按 LF 归一后稳定
  ⑥ beta_setup.sql 第一句就挡：没看到内测服 ref 的 GUC 就整段报错；且文件里不含正式服 ref
  ⑦ 裁判机内测服 unit：EnvironmentFile = env-beta（不是正式服 env）、Nice=15、CPUQuota=100%、工作 / 工程 / 直播目录都是 -beta；
     高峰停起脚本：周六全天 + 周日 17:30 起停
  ⑧ Caddyfile：/beta/streams 两段 + 第二个版本闸片段；正式服 /streams 那两段还在
进 run-tests.sh 门禁（成功打印 ALL OK）。
"""
import importlib
import io
import os
import re
import subprocess
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

fails = [0]
n = [0]


def ok(name, cond, detail=""):
    n[0] += 1
    if cond:
        print("  [PASS] " + name + (("   " + detail) if detail else ""))
    else:
        fails[0] += 1
        print("  [FAIL] " + name + "   " + detail)


def read(rel):
    return io.open(os.path.join(ROOT, rel), encoding="utf-8", newline="").read().replace("\r\n", "\n")


import sb_common as S  # noqa: E402
import sb_migrate as M  # noqa: E402

# ── 把网络换成记账 ──
CALLS = []


def fake_api(ref, method, path, body=None, timeout=180):
    CALLS.append((ref, method, path))
    return 201, []


S.api = fake_api

print("=== 内测服工具链自证 ===")

# ① beta_ops 拒正式服（子进程：真入口；令牌文件不存在也该先拒 ⇒ 证明拒绝发生在任何网络 / 令牌之前）
env = dict(os.environ)
env["PYTHONIOENCODING"] = "utf-8"
env["HOME"] = env["USERPROFILE"] = os.path.join(ROOT, "build", "_no_home_for_selftest")
bo = os.path.join(ROOT, "tools", "beta_ops.py")
r = subprocess.run([sys.executable, bo, "status", "--no-ssh", S.PROD_REF], capture_output=True, text=True, encoding="utf-8", env=env)
ok("① beta_ops 参数里有正式服 ref ⇒ 退出码 3 且打印拒绝", r.returncode == 3 and "拒绝" in r.stdout, "rc=%s out=%s" % (r.returncode, r.stdout[-120:]))
r2 = subprocess.run([sys.executable, bo, "wipe-week", "1792368000", "--", "https://%s.supabase.co" % S.PROD_REF],
                    capture_output=True, text=True, encoding="utf-8", env=env)
ok("① 正式服 ref 藏在 URL 里也拒", r2.returncode == 3, "rc=%s" % r2.returncode)
r0 = subprocess.run([sys.executable, bo, "--help"], capture_output=True, text=True, encoding="utf-8", env=env)
ok("① 分母: 不带正式服 ref 的 --help ⇒ 退出码 0（证明上面的 3 不是脚本自己坏了）", r0.returncode == 0 and "clock" in r0.stdout, "rc=%s" % r0.returncode)

# ② 目标 ref 与公开 key
bsrc = read("tools/beta_ops.py")
ok("② beta_ops 的目标 = sb_common.BETA_REF（写死）且 ≠ 正式服", "REF = S.BETA_REF" in bsrc and S.BETA_REF != S.PROD_REF and S.PROD_REF not in bsrc)
pg = read("project.godot")
m = re.search(r'^supabase_anon_key\.beta_server="([^"]+)"', pg, re.M)
pk = re.search(r'^PUBLISHABLE = "([^"]+)"', bsrc, re.M)
ok("② beta_ops 的公开 key = project.godot 的 supabase_anon_key.beta_server（逐字）",
   m is not None and pk is not None and m.group(1) == pk.group(1))
mu = re.search(r'^supabase_url\.beta_server="([^"]+)"', pg, re.M)
ok("② project.godot 的内测服地址 = sb_common.URLS[BETA_REF]", mu is not None and mu.group(1) == S.URLS[S.BETA_REF])

# ③ 正式服写保护
CALLS.clear()
refused = False
try:
    S.query(S.PROD_REF, "select 1")
except SystemExit:
    refused = True
ok("③ query(正式服) 不带 prod_write_ok ⇒ 拒且一条请求都没发", refused and not CALLS, "calls=%s" % CALLS)
CALLS.clear()
S.query(S.BETA_REF, "select 1")
ok("③ 分母: query(内测服) 发出 1 条", len(CALLS) == 1 and CALLS[0][0] == S.BETA_REF)
CALLS.clear()
S.query_ro(S.PROD_REF, "select 1")
ok("③ query_ro(正式服) 允许（只读事务）", len(CALLS) == 1)

# ④ 正式服上线只收内测服上过的
sha = "a" * 64
led = {"20261021_x": {"name": "20261021_x", "sha256": sha, "applied_at": "t"}}
ok("④ 内测服没上过 ⇒ 拒", not M.prod_apply_allowed("20261021_y", sha, led)[0])
ok("④ sha256 不同（内测服之后又改过）⇒ 拒", not M.prod_apply_allowed("20261021_x", "b" * 64, led)[0])
ok("④ 内测服没有账本 ⇒ 拒", not M.prod_apply_allowed("20261021_x", sha, None)[0])
ok("④ 分母: 同名同 sha ⇒ 收", M.prod_apply_allowed("20261021_x", sha, led)[0])
ok("④ --hotfix ⇒ 收（两边记账）", M.prod_apply_allowed("20261021_y", sha, led, hotfix=True)[0])

# ⑤ 迁移文件
name = "20261021_beta_server_clock"
mp = os.path.join(M.MIG_DIR, name + ".sql")
ok("⑤ 迁移文件在、有检查脚本", os.path.exists(mp) and M.chk_path(name) is not None)
probs = M.check_mirror(name, mp) if os.path.exists(mp) else ["缺文件"]
ok("⑤ 迁移逐字在 schema.sql 里、起止标记唯一", not probs, str(probs))
sql = M.read_lf(mp) if os.path.exists(mp) else ""
ok("⑤ 迁移定义 app_now / server_clock 恒 0 约束 / schema_migrations / beta_tick",
   all(x in sql for x in ("function public.app_now()", "server_clock_prod_zero check (offset_sec = 0)",
                          "table if not exists public.schema_migrations", "function public.beta_tick()")))
fb = M.func_bodies(sql)
ok("⑤ 分母: 迁移里的函数 ≥ 15 个（12 个赛程闸 + app_now / beta_tick / 镜像触发器）", len(fb) >= 15, "%d" % len(fb))
crlf = M.sha256_lf(mp) if os.path.exists(mp) else ""
ok("⑤ sha256 按 LF 归一（与行尾无关）", crlf != "" and crlf == __import__("hashlib").sha256(sql.encode("utf-8")).hexdigest())

# ⑥ beta_setup.sql
bs = read("server/supabase/beta/beta_setup.sql")
first_stmt = bs[bs.find("do $$"):bs.find("end $$;") + 7] if "do $$" in bs else ""
ok("⑥ beta_setup 第一句挡: 没看到内测服 ref 的 GUC 就报错", S.BETA_REF in first_stmt and "raise exception" in first_stmt
   and bs.find("do $$") < bs.find("update public.service_env"))
ok("⑥ beta_setup 不含正式服 ref", S.PROD_REF not in bs)

# ⑦ 裁判机 unit
u = read("server/referee/turtle-referee-beta.service")
prod_u = read("server/referee/turtle-referee.service")
ok("⑦ 内测服 unit: EnvironmentFile=env-beta、不读正式服 env",
   "EnvironmentFile=/etc/turtle-referee/env-beta" in u and not re.search(r"EnvironmentFile=/etc/turtle-referee/env\s*$", u, re.M))
ok("⑦ 内测服 unit: Nice=15、CPUQuota=100%、只写 -beta 目录",
   "Nice=15" in u and "CPUQuota=100%" in u and "ReadWritePaths=/var/lib/turtle-referee-beta /opt/turtle-beta" in u)
ok("⑦ 分母: 正式服 unit 仍读正式服 env（没被改成 beta）", "EnvironmentFile=/etc/turtle-referee/env\n" in prod_u and "beta" not in prod_u)
g = read("server/referee/beta_peak_guard.sh")
ok("⑦ 高峰停起: 周六全天 + 周日 17:30 起", '[ "$dow" = "6" ] && peak=1' in g and '[ "$dow" = "7" ] && [ "$hm" -ge 1730 ] && peak=1' in g
   and "date -u" in g)

# ⑧ Caddyfile
c = read("server/stream/Caddyfile")
ok("⑧ Caddyfile: /beta/streams 块与 end.json 两段 + 第二个版本闸片段",
   "import /etc/caddy/turtle-min-version-beta.caddy" in c and "root * /var/lib/turtle-referee-beta/streams" in c
   and c.count("uri strip_prefix /beta/streams") == 2)
ok("⑧ 分母: 正式服 /streams 两段还在、仍读正式服目录",
   c.count("uri strip_prefix /streams\n") == 2 and c.count("root * /var/lib/turtle-referee/streams") == 2
   and "import /etc/caddy/turtle-min-version.caddy" in c)

print("分母: %d 条断言" % n[0])
if fails[0] == 0 and n[0] >= 25:
    print("ALL OK — 内测服工具链 (%d/%d)" % (n[0], n[0]))
    sys.exit(0)
print("FAIL %d / %d" % (fails[0], n[0]))
sys.exit(1)
