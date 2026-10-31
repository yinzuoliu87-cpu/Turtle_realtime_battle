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
     高峰停起脚本：周六、周日全天停（2026-10-26 起闯关赛打到周日 17:30，原为周六全天 + 周日 17:30 起）
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
# ★2026-10-26 闯关赛截止从周六 23:00 挪到周日 17:30 UTC ⇒ 周日整天都是正式服高峰（上午闯关赛、18:00 小组赛、20:00 冠军杯赛）。
#   判据从「逐字找那两行」换成**把脚本里设 peak 的每一行按它自己的条件求值**，扫 7 天 × 24 小时 × 2 个分钟位：
#   peak 必须恰好 = 周六 + 周日。认不出的 peak= 行直接判红（换了写法要来这里补解析，不许静默跳过）。
_peak_lines = [L.strip() for L in g.split("\n") if re.search(r"\bpeak=1\b", L) and not L.strip().startswith("#")]
_conds = []
_unknown = []
for L in _peak_lines:
    m_dow = re.fullmatch(r'\[ "\$dow" = "(\d)" \] && peak=1', L)
    m_dow_hm = re.fullmatch(r'\[ "\$dow" = "(\d)" \] && \[ "\$hm" -ge (\d{4}) \] && peak=1', L)
    if m_dow:
        _conds.append((int(m_dow.group(1)), 0))
    elif m_dow_hm:
        _conds.append((int(m_dow_hm.group(1)), int(m_dow_hm.group(2))))
    else:
        _unknown.append(L)
ok("⑦ 高峰停起 ★分母: 读出了设 peak 的行且每一行都认得出（%d 行）" % len(_peak_lines),
   len(_peak_lines) >= 1 and not _unknown and "date -u +%u" in g and "date -u +%H%M" in g, "认不出: %s" % _unknown)
_bad = []
_on = 0
for _dow in range(1, 8):
    for _h in range(24):
        for _mi in (0, 45):
            _hm = _h * 100 + _mi
            _peak = any(_dow == d and _hm >= hm for d, hm in _conds)
            _on += 1 if _peak else 0
            if _peak != (_dow in (6, 7)):
                _bad.append("dow%d %04d peak=%d" % (_dow, _hm, 1 if _peak else 0))
ok("⑦ 高峰停起: 周六、周日全天停（含周日 00:00~17:30 闯关赛），周一~周五一刻都不停",
   not _bad and _on == 2 * 24 * 2, "不对的时刻 %d 个: %s" % (len(_bad), _bad[:4]))

# ★2026-10-31: 周末内测服裁判被上面停掉之后, 健康检查照样每 5 分钟报「心跳: 没有裁判在线」(全是误报)。
#   健康检查的 ExecCondition 调 `beta_peak_guard.sh --should-run`; 这里**真跑那个脚本**(假 date / systemctl 放 PATH 最前),
#   不是读字面量 —— 判据量的是「该跳过的时刻跳过、该查的时刻照查」。
hu = read("server/referee/turtle-referee-beta-health.service")
ok("⑦ 内测服健康检查: ExecCondition 走 beta_peak_guard.sh --should-run",
   "ExecCondition=/bin/sh /opt/turtle-beta/referee/beta_peak_guard.sh --should-run" in hu)
import shutil, subprocess, tempfile
_sh = shutil.which("sh")


def _guard_rc(dow: int, active: bool, up_sec: int, beta_off: bool) -> int:
    """假时钟 / 假 systemctl 下跑一次 --should-run, 返回退出码。"""
    with tempfile.TemporaryDirectory() as d:
        now = 1_800_000_000
        with open(os.path.join(d, "date"), "w", encoding="utf-8", newline="\n") as f:
            f.write('#!/bin/sh\ncase "$*" in\n'
                    '  *+%%u*) echo %d ;;\n  *+%%H%%M*) echo 1200 ;;\n'
                    '  *-d*) echo %d ;;\n  *+%%s*) echo %d ;;\nesac\n' % (dow, now - up_sec, now))
        with open(os.path.join(d, "systemctl"), "w", encoding="utf-8", newline="\n") as f:
            f.write('#!/bin/sh\ncase "$1" in\n  is-active) exit %d ;;\n  show) echo since ;;\nesac\nexit 0\n'
                    % (0 if active else 3))
        os.chmod(os.path.join(d, "date"), 0o755)
        os.chmod(os.path.join(d, "systemctl"), 0o755)
        g2 = g if not beta_off else g.replace("[ -e /etc/turtle-referee/beta-off ] && off=1", "off=1")
        with open(os.path.join(d, "guard.sh"), "w", encoding="utf-8", newline="\n") as f:
            f.write(g2)
        env = dict(os.environ, PATH=d + os.pathsep + os.environ.get("PATH", ""))
        return subprocess.run([_sh, os.path.join(d, "guard.sh"), "--should-run"], env=env,
                              capture_output=True, timeout=30).returncode


if _sh is None:
    ok("⑦ 内测服健康检查: 本机有 sh 才能真跑 beta_peak_guard.sh", False, "找不到 sh")
else:
    _cases = [  # (说明, 周几, 在岗, 起来几秒, beta-off, 期望退出码: 0 = 照查, 1 = 跳过)
        ("周六 停着", 6, False, 0, False, 1),
        ("周日 停着", 7, False, 0, False, 1),
        ("周三 beta-off 停着", 3, False, 0, True, 1),
        ("周一 刚起来 30 秒", 1, True, 30, False, 1),
        ("周三 在岗 1 小时", 3, True, 3600, False, 0),
        ("周三 该在岗却没起来(真问题, 必须照报)", 3, False, 0, False, 0),
    ]
    _got = [(c[0], _guard_rc(c[1], c[2], c[3], c[4]), c[5]) for c in _cases]
    _wrong = [x for x in _got if x[1] != x[2]]
    ok("⑦ 内测服健康检查: 周末 / beta-off / 刚起来 ⇒ 跳过; 平日在岗或该在岗没起来 ⇒ 照查（%d 种情形）" % len(_cases),
       not _wrong, "不对: %s" % _wrong)

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
