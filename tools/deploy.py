# -*- coding: utf-8 -*-
"""tools/deploy.py —— 裁判机装一个客户端版本的固定流程（2026-11-02 · 方案书 docs/plans/20261102-文件管理与发版流程重整.md §4.2 P3）。

照 tools/sb_migrate.py 的形状：分环境、本机前置检查、演练（--dry-run）、执行、回读。服务器那一半是
server/deploy/deploy_version.sh（暂存目录装 tag 那一提交 → 导入两次 → 两条一致性门禁 → 原子换入 → 两个对手池 →
陪练号工程 → 改 env → 重启调度器 → 读进程环境确认）；用法与回退见 server/deploy/README.md。

  python tools/deploy.py 0.22.8 --dry-run          本机前置检查 + 服务器只读演练（打印每一步会做什么，什么都不改）+ 现状回读
  python tools/deploy.py 0.22.8                    正式服部署（长任务在服务器上 nohup 起，本机每 15 秒一条短 ssh 看日志）
  python tools/deploy.py 0.22.8 --status           接着看上一次的日志，直到 DEPLOY OK / FAILED，然后回读
  python tools/deploy.py 0.22.8 --only pools       只重跑对手池 + 回读（工程已在）
  python tools/deploy.py 0.22.8 --only bots-switch 登记 referee_versions 之后再切陪练号
  python tools/deploy.py 0.22.8 --env beta         内测服（/opt/turtle-beta；内测服陪练号停用中时自动不碰）

本机前置检查（不过就停；--dry-run 照跑完、最后报红）：
  ① tag v<版本> 在本机且已推（远端 tag 剥皮后 = 本机）；--sha 给了就必须等于 tag 那一提交
  ② 那一提交的 project.godot 版本 = <版本>；读出 RULES_VER（传给服务器核对 + 登记 SQL 用）；裁判入口 / 两条门禁场景都在
  ③ CI「提交门禁」tests.yml 在那一提交上绿（GitHub API；令牌取自 Git 凭据管理器，不打印）
  ④ 库里（只读）：referee_versions 有没有这个版本 —— 没有就自动 --no-bots-switch（陪练号切过去会开不了积分赛），
     装完、人登记之后再 `--only bots-switch`
  ⑤ 服务器连得上、没有别的部署在跑（/run/lock/turtle-deploy.lock）

回读（只读）：referee_versions 那一行、两个对手池按 rules_ver 的行数（应 2052 / seed 396 / bot 186）、referee_config、
服务器上两个工程目录的 HEAD、陪练号 env 与调度器进程环境里的 BOT_GAME_DIR。

★本工具不写任何库。剩下要写库的（登记版本、finals_version）打印 SQL 给人 —— 正式服写入要用户点头。
★长任务一律服务器上 setsid nohup 起、本机短 ssh（≤ 25 秒）轮询（memory「SSH 起后台又等结果会挂住」）。
"""
import argparse
import hashlib
import io
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_SCRIPT = os.path.join(REPO, "server", "deploy", "deploy_version.sh")
## 热修只许改这些路径（2026-11-03）: 录流 / 测试 / 文档 / 工具 / 服务器脚本。动到对局计算的不许走热修。
HOTFIX_OK = ("scripts/systems/stream/", "tests/", "docs/", "tools/", "server/")
SSH_KEY = os.path.join(os.path.expanduser("~"), ".ssh", "turtle_referee")
SSH_HOST = "root@49.13.166.188"
REMOTE_DIR = "/root/deploy"
REMOTE_SCRIPT = REMOTE_DIR + "/deploy_version.sh"
REMOTE_LOGS = REMOTE_DIR + "/logs"
REMOTE_LOCK = "/run/lock/turtle-deploy.lock"
WORKFLOW = "tests.yml"
EXPECT_POOLS = (2052, 396, 186)          # 闯关机器人池 / 积分赛内置陪练 / 积分赛机器人（server/referee/README.md「发版时」第 4 步）
ENVS = {
    "prod": {"ref_root": "/opt/turtle", "bots_root": "/opt/turtle-bots-prod",
             "bots_env": "/etc/turtle-referee/env-bots-prod", "bots_off": "/etc/turtle-referee/bots-prod-off",
             "planner": "turtle-gauntlet-planner-prod"},
    "beta": {"ref_root": "/opt/turtle-beta", "bots_root": "/opt/turtle-bots-beta",
             "bots_env": "/etc/turtle-referee/env-bots-beta", "bots_off": "/etc/turtle-referee/bots-beta-off",
             "planner": ""},
}
FINAL_RE = re.compile(r"^DEPLOY (OK|FAILED)")
SSH_OPTS = ["-i", SSH_KEY, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5"]


# ── 小工具 ──────────────────────────────────────────────────────
def git(*args, check=True):
    r = subprocess.run(["git"] + list(args), cwd=REPO, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and r.returncode != 0:
        return None
    return r.stdout.strip()


def ssh(cmd, timeout=25, data=None):
    """短 ssh。返回 (rc, stdout, stderr)；超时 / 起不来 rc=None。"""
    try:
        r = subprocess.run(["ssh"] + SSH_OPTS + [SSH_HOST, cmd], input=data, capture_output=True, timeout=timeout)
        return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")
    except (subprocess.TimeoutExpired, OSError) as e:
        return None, "", str(e)


class Checks:
    def __init__(self):
        self.bad = []

    def ok(self, msg):
        print("  ✓ " + msg)

    def info(self, msg):
        print("  · " + msg)

    def fail(self, msg):
        print("  ✗ " + msg)
        self.bad.append(msg)


def gh_token():
    """Git 凭据管理器里存的 GitHub 令牌（CLAUDE.md §6「iOS 的硬事实」最后一条）。不打印。拿不到返回 None（公开仓库照样能读，限 60 次/时）。"""
    env = dict(os.environ, GCM_INTERACTIVE="Never", GIT_TERMINAL_PROMPT="0")
    try:
        r = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                           capture_output=True, text=True, timeout=20, env=env)
    except (subprocess.TimeoutExpired, OSError):
        return None
    for line in r.stdout.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    return None


def repo_slug():
    url = git("remote", "get-url", "origin") or ""
    m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", url)
    return m.group(1) if m else "yinzuoliu87-cpu/Turtle_realtime_battle"


def ci_runs(sha):
    """tests.yml 在这一提交上的运行。返回 (runs, 错误)。绕开本机代理（ProxyHandler({})，同 sb_common.OPENER）。"""
    url = "https://api.github.com/repos/%s/actions/workflows/%s/runs?head_sha=%s&per_page=20" % (repo_slug(), WORKFLOW, sha)
    hdr = {"Accept": "application/vnd.github+json", "User-Agent": "turtle-deploy", "X-GitHub-Api-Version": "2022-11-28"}
    tok = gh_token()
    if tok:
        hdr["Authorization"] = "Bearer " + tok
    try:
        with S.OPENER.open(urllib.request.Request(url, headers=hdr), timeout=30) as r:
            return json.loads(r.read().decode("utf-8")).get("workflow_runs") or [], None
    except urllib.error.HTTPError as e:
        return None, "HTTP %s" % e.code
    except (urllib.error.URLError, OSError, ValueError) as e:
        return None, str(e)


# ── 本机前置检查 ──────────────────────────────────────────────────
def local_preflight(a):
    c = Checks()
    print("== 本机前置检查（只读）")
    info = {"sha": None, "rules_ver": None, "overlay": None, "reg": None}
    if not re.match(r"^\d+\.\d+\.\d+$", a.version):
        c.fail("版本号格式不对: %s" % a.version)
        return c, info
    tag = "v" + a.version
    sha = git("rev-parse", "-q", "--verify", "refs/tags/%s^{commit}" % tag)
    if not sha:
        c.fail("本机没有 tag %s（先 tools/release.py tag，或 git fetch --tags）" % tag)
        return c, info
    c.ok("tag %s → %s" % (tag, sha))
    if a.sha:
        want = git("rev-parse", "-q", "--verify", a.sha + "^{commit}")
        if want != sha:
            c.fail("--sha %s → %s ≠ tag 那一提交 %s" % (a.sha, want, sha))
    tag_sha = sha
    if a.hotfix:
        ## ★2026-11-03 热修（积分赛播流信息面板全是默认值）: 手机还是这个版本, 只修服务器侧 ⇒ 不升版本号、tag 不挪,
        ##   从 tag 拉热修分支, 部署那一提交。守住三条: tag 是它的祖先 / 改动只在录流 · 测试 · 文档 · 工具 · 服务器脚本里
        ##   （动到对局计算的不许走热修, 那要出新版本）/ 版本号与 RULES_VER 与 tag 相同。
        hs = git("rev-parse", "-q", "--verify", a.hotfix + "^{commit}")
        if not hs:
            c.fail("--hotfix %s 本机找不到" % a.hotfix)
            return c, info
        if subprocess.run(["git", "merge-base", "--is-ancestor", tag_sha, hs], cwd=REPO).returncode != 0:
            c.fail("热修 %s 不是从 tag %s 拉出来的（tag 不是它的祖先）" % (hs[:8], tag))
        changed = [f for f in (git("diff", "--name-only", tag_sha, hs) or "").splitlines() if f]
        bad = [f for f in changed if not f.startswith(HOTFIX_OK)]
        if not changed:
            c.fail("热修与 tag 没有差别")
        elif bad:
            c.fail("热修改到了录流 / 测试 / 文档 / 工具 / 服务器脚本之外的文件（动对局计算要出新版本）: %s" % bad[:6])
        else:
            c.ok("热修 %s ← tag %s, 改了 %d 个文件（都在允许范围内）: %s" % (hs[:8], tag, len(changed), changed[:6]))
        if not (git("branch", "-r", "--contains", hs) or "").strip():
            c.fail("热修 %s 还没推到 GitHub（服务器按 sha 取）" % hs[:8])
        rv = lambda s: (re.search(r"const RULES_VER\s*:?=\s*(\d+)", git("show", "%s:scripts/gamedata/phase2_config.gd" % s) or "") or [None, None])[1]
        if rv(hs) != rv(tag_sha):
            c.fail("热修改了 RULES_VER（%s → %s）—— 那是出新版本的事" % (rv(tag_sha), rv(hs)))
        sha = hs
        info["hotfix"] = True
    info["sha"] = sha
    remote = git("ls-remote", "origin", "refs/tags/%s" % tag, "refs/tags/%s^{}" % tag) or ""
    peel = {ln.split("\t")[1]: ln.split("\t")[0] for ln in remote.splitlines() if "\t" in ln}
    rsha = peel.get("refs/tags/%s^{}" % tag) or peel.get("refs/tags/%s" % tag)
    if not rsha:
        c.fail("远端没有 tag %s（没推？服务器按 sha 取也要这一提交在 GitHub 上）" % tag)
    elif rsha != tag_sha:
        c.fail("远端 tag %s → %s ≠ 本机 %s（tag 挪过位？先对齐）" % (tag, rsha, tag_sha))
    else:
        c.ok("远端 tag %s 一致" % tag)
    pg = git("show", "%s:project.godot" % sha) or ""
    m = re.search(r'^config/version="([^"]+)"', pg, re.M)
    if not m or m.group(1) != a.version:
        c.fail("那一提交的 project.godot 版本 = %s ≠ %s" % (m.group(1) if m else "?", a.version))
    else:
        c.ok("project.godot 版本 = %s" % a.version)
    p2 = git("show", "%s:scripts/gamedata/phase2_config.gd" % sha) or ""
    m = re.search(r"const RULES_VER\s*:?=\s*(\d+)", p2)
    if not m:
        c.fail("读不到 RULES_VER（scripts/gamedata/phase2_config.gd）")
    else:
        info["rules_ver"] = int(m.group(1))
        prev = git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", tag_sha + "^", check=True)
        prv = None
        if prev:
            pm = re.search(r"const RULES_VER\s*:?=\s*(\d+)", git("show", "%s:scripts/gamedata/phase2_config.gd" % prev) or "")
            prv = pm.group(1) if pm else None
        c.ok("RULES_VER = %s（上一个 tag %s 是 %s%s）" % (info["rules_ver"], prev or "?", prv or "?",
                                                    "；★变了 ⇒ 对手池按新 rules_ver 另起一套" if prv and int(prv) != info["rules_ver"] else ""))
    for f in ("scenes/Referee.tscn", "tests/verify_determinism_cross.tscn", "tests/verify_referee_job_roundtrip.tscn",
              "scripts/systems/sim/sim_driver.gd"):
        if subprocess.run(["git", "cat-file", "-e", "%s:%s" % (sha, f)], cwd=REPO, capture_output=True).returncode != 0:
            c.fail("那一提交里没有 %s" % f)
    bp = git("show", "%s:scripts/referee/bot_pool.gd" % sha) or ""
    if "static func generate_ranked(" not in bp:
        c.fail("bot_pool.gd 没有 generate_ranked ⇒ 生成不了积分赛池（0.22.7 起才有）")
    else:
        c.ok("裁判入口 / 两条门禁场景 / 陪练驱动 / 积分赛池生成器都在")
    # CI
    if a.skip_ci:
        c.info("★--skip-ci：不看 CI（只给紧急修复用）")
    else:
        runs, err = ci_runs(sha)
        if runs is None:
            c.fail("读不到 CI（%s）" % err)
        elif not runs:
            c.fail("tests.yml 在 %s 上没有运行记录（一次推多个提交时只有最上面那个跑 CI）" % sha[:8])
        else:
            good = [r for r in runs if r.get("conclusion") == "success"]
            last = runs[0]
            if good:
                c.ok("CI 绿: %s（%s）" % (good[0].get("html_url"), good[0].get("updated_at")))
            else:
                c.fail("CI 没绿: 最近一次 status=%s conclusion=%s %s" % (last.get("status"), last.get("conclusion"), last.get("html_url")))
    # sim 覆盖
    if a.sim_overlay:
        osha = git("rev-parse", "-q", "--verify", a.sim_overlay + "^{commit}")
        if not osha:
            c.fail("--sim-overlay %s 解析不出提交" % a.sim_overlay)
        elif subprocess.run(["git", "merge-base", "--is-ancestor", osha, "origin/main"], cwd=REPO).returncode != 0:
            c.fail("--sim-overlay %s 不在 origin/main 上（服务器取不到没推的提交）" % osha[:8])
        else:
            info["overlay"] = osha
            st = git("diff", "--stat", sha, osha, "--", "scripts/systems/sim") or "（无差别）"
            c.ok("陪练号 scripts/systems/sim/ 覆盖成 %s：%s" % (osha[:8], st.splitlines()[-1]))
    else:
        st = git("diff", "--stat", sha, "origin/main", "--", "scripts/systems/sim") or ""
        if st:
            c.info("origin/main 的 scripts/systems/sim/ 比 tag 新（%s）；陪练号要用 main 版时加 --sim-overlay origin/main"
                   "（README「常驻陪练号」第 1 步；默认不覆盖）" % st.splitlines()[-1].strip())
    # 库（只读）
    try:
        rows = S.query_ro(S.REFS[a.env], "select client_version, enabled, rules_ver from public.referee_versions "
                                         "where client_version = '%s'" % a.version)
        info["reg"] = S.one(rows) or None
        r = info["reg"]
        if r and r.get("enabled"):
            c.ok("referee_versions 已登记 %s（rules_ver=%s）" % (a.version, r.get("rules_ver")))
        else:
            c.info("referee_versions 里%s %s" % ("有但 enabled=false：" if r else "还没有", a.version))
    except (S.SqlError, SystemExit) as e:
        c.fail("读不到 %s 库的 referee_versions: %s" % (a.env, str(e)[:200]))
    return c, info


def server_preflight(c):
    print("== 服务器")
    rc, out, err = ssh("[ -e %s ] && ! flock -n %s true && echo BUSY || echo FREE; uptime" % (REMOTE_LOCK, REMOTE_LOCK))
    if rc is None or rc != 0:
        c.fail("ssh %s 不通: %s" % (SSH_HOST, (err or out).strip()[:200]))
        return
    lines = out.strip().splitlines()
    if lines and lines[0] == "BUSY":
        c.fail("服务器上另一次部署正在跑（%s 被占）—— 用 --status 看它" % REMOTE_LOCK)
    else:
        c.ok("ssh 通、没有别的部署在跑；%s" % (lines[-1].strip() if lines else ""))


# ── 上传 / 起 / 跟 ──────────────────────────────────────────────
def upload():
    data = io.open(SERVER_SCRIPT, "rb").read().replace(b"\r\n", b"\n")   # 仓库 core.autocrlf=true ⇒ 工作区可能是 CRLF
    want = hashlib.sha256(data).hexdigest()
    rc, out, err = ssh("mkdir -p %s %s" % (REMOTE_DIR, REMOTE_LOGS))
    if rc != 0:
        raise SystemExit("建 %s 失败: %s" % (REMOTE_LOGS, err.strip()))
    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "deploy_version.sh"), "wb") as f:
            f.write(data)
        # 相对路径 + cwd：Windows 的 scp 会把「C:\…」里的冒号当主机名
        r = subprocess.run(["scp", "-q"] + SSH_OPTS[:6] + ["deploy_version.sh", "%s:%s" % (SSH_HOST, REMOTE_SCRIPT)],
                           cwd=td, capture_output=True, timeout=60)
        if r.returncode != 0:
            raise SystemExit("scp 失败: %s" % r.stderr.decode("utf-8", "replace").strip())
    rc, out, err = ssh("sha256sum %s && bash -n %s && echo SYNTAX_OK" % (REMOTE_SCRIPT, REMOTE_SCRIPT))
    got = out.split()[0] if out.split() else ""
    if got != want or "SYNTAX_OK" not in out:
        raise SystemExit("上传回读不对: sha256 %s ≠ %s / %s" % (got[:12], want[:12], (out + err).strip()[-200:]))
    print("  ✓ 已上传 %s（sha256 %s…，bash -n 过）" % (REMOTE_SCRIPT, want[:12]))


def server_args(a, info):
    args = [a.env, a.version, info["sha"], "--expect-pools", "%d,%d,%d" % EXPECT_POOLS]
    if info.get("rules_ver") is not None:
        args += ["--rules-ver", str(info["rules_ver"])]
    for flag in ("dry_run", "skip_bots", "no_bots_switch", "no_pools", "no_drain", "allow_weekend"):
        if getattr(a, flag):
            args.append("--" + flag.replace("_", "-"))
    if a.bots_drain_sec is not None:
        args += ["--bots-drain-sec", str(a.bots_drain_sec)]
    if info.get("overlay"):
        args += ["--sim-overlay", info["overlay"]]
    if info.get("hotfix"):
        args += ["--hotfix"]
    if a.only:
        args += ["--only", a.only]
    return args


def link_path(a):
    return "%s/last-%s-v%s.log" % (REMOTE_LOGS, a.env, a.version)


def start(a, info):
    ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    log = "%s/%s-v%s-%s-%s%s.log" % (REMOTE_LOGS, a.env, a.version, info["sha"][:8], ts, "-dry" if a.dry_run else "")
    argv = " ".join(shlex.quote(x) for x in server_args(a, info))
    # ★只把那一条简单命令放后台：写成「a && b && c &」时后台的是整串的子 shell，它攥着 ssh 的 stdout ⇒ ssh 挂到部署跑完
    cmd = ("ln -sfn %s %s; cd /; setsid nohup bash %s %s > %s 2>&1 < /dev/null & echo STARTED"
           % (log, link_path(a), REMOTE_SCRIPT, argv, log))
    rc, out, err = ssh(cmd, timeout=25)
    if rc != 0 or "STARTED" not in out:
        raise SystemExit("起不来: rc=%s %s" % (rc, (out + err).strip()[-300:]))
    print("  ✓ 服务器上已起: bash %s %s" % (REMOTE_SCRIPT, argv))
    print("    日志 %s（另开窗口: python tools/deploy.py %s --env %s --status）" % (log, a.version, a.env))
    return log


def follow(log, interval, max_sec, head=None):
    """短 ssh 轮询日志尾，打印新行，直到 DEPLOY OK / FAILED。返回最后那一行（超时 / 连不上返回 None）。
    head：给一个 list 就把日志第一行（脚本自报的参数）放进去 —— --status 靠它知道那一次带了哪些开关。"""
    seen = 0
    t0 = time.time()
    quiet = 0
    misses = 0
    while time.time() - t0 < max_sec:
        rc, out, err = ssh("tail -n +%d %s 2>/dev/null | head -c 200000" % (seen + 1, shlex.quote(log)), timeout=25)
        if rc is None:
            misses += 1
            if misses >= 10:
                print("  ✗ 连续 10 次连不上服务器；部署还在服务器上跑，过会儿 --status")
                return None
        else:
            misses = 0
            lines = out.split("\n")[:-1]     # 最后一段 = 空串（以换行结尾）或半行（留到下一次）
            for ln in lines:
                print("  | " + ln)
                if head is not None and not head and "deploy_version.sh env=" in ln:
                    head.append(ln)
                if FINAL_RE.match(ln):
                    return ln
            seen += len(lines)
            quiet = 0 if lines else quiet + interval
            if quiet and quiet % 300 < interval:
                print("  …（%d 分钟没有新输出，仍在等；Ctrl+C 不影响服务器上的部署）" % (quiet // 60))
        time.sleep(interval)
    print("  ✗ 等了 %d 秒还没结束；部署还在服务器上跑，过会儿 --status" % max_sec)
    return None


# ── 回读（只读） ────────────────────────────────────────────────
def readback(a, info, final):
    e = ENVS[a.env]
    ref = S.REFS[a.env]
    ver, rv = a.version, info.get("rules_ver")
    g_exp, s_exp, b_exp = EXPECT_POOLS
    probs, todo = [], []
    print("== 回读（只读）%s" % ("—— dry-run：下面是现状，不是部署结果" if a.dry_run else ""))
    try:
        reg = S.one(S.query_ro(ref, "select client_version, enabled, rules_ver, added_at::text as added_at "
                                    "from public.referee_versions where client_version = '%s'" % ver))
        en = S.query_ro(ref, "select client_version, rules_ver from public.referee_versions where enabled order by added_at desc limit 6")
        gp = {r["rules_ver"]: r["n"] for r in S.query_ro(ref, "select rules_ver, count(*)::int as n from public.gauntlet_bot_pool group by 1")}
        rp = {}
        for r in S.query_ro(ref, "select kind, rules_ver, count(*)::int as n from public.ranked_pool group by 1, 2"):
            rp[(r["kind"], r["rules_ver"])] = r["n"]
        cfg = S.one(S.query_ro(ref, "select to_jsonb(c) - 'updated_at' as c from public.referee_config c where id = 1")).get("c") or {}
    except (S.SqlError, SystemExit) as ex:
        print("  ✗ 读不到 %s 库: %s" % (a.env, str(ex)[:300]))
        return ["库回读失败"], todo
    print("  referee_versions[%s] = %s" % (ver, json.dumps(reg, ensure_ascii=False) if reg else "（没有）"))
    print("  启用中的版本: %s" % ", ".join("%s(rv=%s)" % (r["client_version"], r["rules_ver"]) for r in en))
    print("  闯关机器人池 rules_ver=%s: %s 行（要 %d）；各 rules_ver: %s" % (rv, gp.get(rv, 0), g_exp, json.dumps(gp)))
    print("  积分赛池 rules_ver=%s: seed %s / bot %s（要 %d / %d）" % (rv, rp.get(("seed", rv), 0), rp.get(("bot", rv), 0), s_exp, b_exp))
    print("  referee_config: finals_version=%r finals_on=%s gauntlet_on=%s ranked_on=%s" % (
        cfg.get("finals_version"), cfg.get("finals_on"), cfg.get("gauntlet_on"), cfg.get("ranked_on")))
    pools_wanted = not a.dry_run and not a.no_pools and a.only != "bots-switch"
    if pools_wanted:
        if gp.get(rv, 0) != g_exp:
            probs.append("闯关机器人池 rules_ver=%s 有 %s 行 ≠ %d" % (rv, gp.get(rv, 0), g_exp))
        if rp.get(("seed", rv), 0) != s_exp or rp.get(("bot", rv), 0) != b_exp:
            probs.append("积分赛池 rules_ver=%s seed %s / bot %s ≠ %d / %d" % (rv, rp.get(("seed", rv), 0), rp.get(("bot", rv), 0), s_exp, b_exp))
    # 服务器（只读）
    cmd = ("for d in %s/v%s %s/v%s; do printf '%%s HEAD=%%s %%s\\n' \"$d\" \"$(cat $d/.git/HEAD 2>/dev/null || echo 无)\" "
           "\"$(grep -m1 '^config/version=' $d/project.godot 2>/dev/null)\"; done; "
           "echo \"env $(grep -m1 '^BOT_GAME_DIR=' %s 2>/dev/null)\"; " % (e["ref_root"], ver, e["bots_root"], ver, e["bots_env"]))
    if e["planner"]:
        cmd += ("P=$(systemctl show -p MainPID --value %s); echo \"planner $(systemctl is-active %s) pid=$P "
                "$(tr '\\0' '\\n' < /proc/$P/environ 2>/dev/null | grep -m1 '^BOT_GAME_DIR=')\"; " % (e["planner"], e["planner"]))
    cmd += "ls -1d /opt/turtle-prev/%s-* 2>/dev/null | tail -n 4 | sed 's/^/prev /'; ls -1 /etc/turtle-referee/ | grep -- '-off$' | sed 's/^/off /'" % a.env
    rc, out, err = ssh(cmd)
    srv = out.strip().splitlines() if rc == 0 else ["（ssh 失败: %s）" % (err.strip()[:200])]
    for ln in srv:
        print("  服务器 " + ln)
    want_dir = "%s/v%s" % (e["bots_root"], ver)
    if not a.dry_run and final and final.startswith("DEPLOY OK") and a.only != "bots-switch":
        ref_line = next((ln for ln in srv if ln.startswith("%s/v%s " % (e["ref_root"], ver))), "")
        if ("HEAD=%s" % info["sha"]) not in ref_line:
            probs.append("服务器 %s/v%s 的 HEAD 不是 %s" % (e["ref_root"], ver, info["sha"][:8]))
    switched = any(ln == "env BOT_GAME_DIR=%s" % want_dir for ln in srv)
    proc_ok = (not e["planner"]) or any(ln.startswith("planner active") and ln.endswith("BOT_GAME_DIR=%s" % want_dir) for ln in srv)
    switch_wanted = not a.dry_run and not a.skip_bots and not a.no_bots_switch and a.only != "pools"
    if switch_wanted and final and final.startswith("DEPLOY OK") and not (switched and proc_ok):
        probs.append("陪练号没切到 %s（env / 调度器进程环境）" % want_dir)
    # 剩下要人做的
    if not reg or not reg.get("enabled"):
        todo.append("登记版本（%s 库写入，要用户点头）:\n      insert into public.referee_versions (client_version, rules_ver) values ('%s', %s)\n"
                    "        on conflict (client_version) do update set enabled = true, rules_ver = excluded.rules_ver;" % (a.env, ver, rv))
    elif rv is not None and reg.get("rules_ver") != rv:
        todo.append("rules_ver 对不上（登记 %s ≠ 工程 %s）: 重跑 `python tools/deploy.py %s --env %s --only pools`（--bot-pool 会写上）"
                    % (reg.get("rules_ver"), rv, ver, a.env))
    if not a.skip_bots and not (a.env == "beta" and any(ln == "off bots-beta-off" for ln in srv)) and not (switched and proc_ok):
        todo.append("切陪练号（登记之后）: python tools/deploy.py %s --env %s --only bots-switch" % (ver, a.env))
    if cfg.get("finals_version") != ver:
        todo.append("周日用的版本（现在 %r；★非周日才改，= 当周锁定的客户端版本，必须已登记且 enabled）:\n"
                    "      update public.referee_config set finals_version = '%s', updated_at = now() where id = 1;" % (cfg.get("finals_version"), ver))
    todo.append("旧版本：任务清空后再删旧目录、update referee_versions set enabled = false（server/referee/README.md「发版时」第 5 步）")
    return probs, todo


# ── 主流程 ──────────────────────────────────────────────────────
def main():
    S.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("version")
    ap.add_argument("--env", choices=sorted(ENVS), default="prod")
    ap.add_argument("--sha", help="核对用：必须等于 tag v<版本> 那一提交")
    ap.add_argument("--hotfix", metavar="SHA", help="热修：部署从 tag 拉出的补丁提交（不升版本号；只许改录流 / 测试 / 文档 / 工具 / 服务器脚本）")
    ap.add_argument("--dry-run", action="store_true", help="本机检查 + 服务器只读演练 + 现状回读，什么都不改")
    ap.add_argument("--status", action="store_true", help="接着看上一次的日志直到结束，然后回读")
    ap.add_argument("--no-follow", action="store_true", help="起完就返回，不跟日志")
    ap.add_argument("--only", choices=["pools", "bots-switch"])
    ap.add_argument("--skip-bots", action="store_true")
    ap.add_argument("--no-bots-switch", action="store_true")
    ap.add_argument("--no-pools", action="store_true")
    ap.add_argument("--no-drain", action="store_true")
    ap.add_argument("--bots-drain-sec", type=int)
    ap.add_argument("--sim-overlay", metavar="REF", help="陪练号工程的 scripts/systems/sim/ 换成这一提交（如 origin/main）")
    ap.add_argument("--allow-weekend", action="store_true")
    ap.add_argument("--skip-ci", action="store_true", help="★不看 CI（只给紧急修复用）")
    ap.add_argument("--max-wait-min", type=int, default=240, help="跟日志最多等几分钟（默认 240：陪练号退完最多要 2 小时）")
    a = ap.parse_args()

    c, info = local_preflight(a)
    if a.status:
        if not info["sha"]:
            return 1
        rc, out, err = ssh("readlink -f %s" % link_path(a))
        log = out.strip()
        if rc != 0 or not log:
            print("✗ 服务器上没有 %s" % link_path(a))
            return 1
        print("== 跟日志 %s" % log)
        head = []
        final = follow(log, 15, a.max_wait_min * 60, head)
        # 那一次带的开关以日志第一行为准（本机这次命令行没带也照它判，免得回读误报）
        kv = dict(re.findall(r"(\w+)=(\S+)", head[0])) if head else {}
        a.dry_run = kv.get("dry") == "1" or log.endswith("-dry.log")
        a.skip_bots = a.skip_bots or kv.get("skip_bots") == "1"
        a.no_bots_switch = a.no_bots_switch or kv.get("no_switch") == "1"
        a.no_pools = a.no_pools or kv.get("no_pools") == "1"
        if kv.get("only") in ("pools", "bots-switch"):
            a.only = kv["only"]
    else:
        # 没登记 ⇒ 不切陪练号（自动），装完、登记后再 --only bots-switch
        reg = info.get("reg")
        registered = bool(reg and reg.get("enabled"))
        if not registered and not a.skip_bots and not a.no_bots_switch and a.only is None and info["sha"]:
            a.no_bots_switch = True
            c.info("★referee_versions 里还没有 %s ⇒ 这次自动 --no-bots-switch（陪练号切过去会开不了积分赛）；"
                   "装完、登记后跑 --only bots-switch" % a.version)
        if a.only == "bots-switch" and not registered:
            c.fail("--only bots-switch 要先登记 referee_versions（%s）" % a.version)
        if a.only and (a.no_pools or a.no_bots_switch):
            c.info("--only 下 --no-pools / --no-bots-switch 不起作用")
        server_preflight(c)
        if c.bad and not a.dry_run:
            print("\n✗ 前置检查没过（%d 条）⇒ 不部署" % len(c.bad))
            return 1
        if not info["sha"]:
            return 1
        print("== 上传并起%s" % ("（--dry-run：服务器只读演练）" if a.dry_run else ""))
        upload()
        log = start(a, info)
        if a.no_follow:
            return 0
        final = follow(log, 5 if a.dry_run else 15, a.max_wait_min * 60)
    probs, todo = readback(a, info, final)
    print("\n== 结果")
    print("  服务器: %s" % (final or "没等到结束（--status 接着看）"))
    for p in probs:
        print("  ✗ " + p)
    if c.bad:
        print("  ✗ 本机前置检查没过 %d 条：%s" % (len(c.bad), "；".join(c.bad)))
    if todo:
        print("\n== 剩下要人做的（本工具不写库）")
        for i, t in enumerate(todo, 1):
            print("  %d. %s" % (i, t))
    ok = bool(final and final.startswith("DEPLOY OK")) and not probs and not c.bad
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
