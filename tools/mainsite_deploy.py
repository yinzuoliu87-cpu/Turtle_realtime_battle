# -*- coding: utf-8 -*-
"""tools/mainsite_deploy.py —— 龟投（主站）网关 · 内测环境一条命令部署（2026-11-09 · 方案书 docs/plans/20261107-龟战主站对接.md §4.7）。

照 tools/deploy.py / tools/sb_migrate.py 的形状，但**默认就是演练**：

  python tools/mainsite_deploy.py                  = --dry-run：本机检查（只读本机文件）+ 打印要做的每一步；不连任何服务器 / 数据库
  python tools/mainsite_deploy.py --apply          真执行（周六 / 周日 UTC 还要再加 --weekend-ok；CLAUDE.md §3「周末不动裁判机」）
  python tools/mainsite_deploy.py --apply --only readback   只做第 ③ 段回读（不改任何东西）

做的事（顺序固定，前一步不过就停；门禁 tools/mainsite_deploy_selftest.py 量这个顺序）：
  ① 内测服迁移：记账 20261106 / b / c / e / g + 20261109a / b / c / d / e，按这个顺序；
     先读内测服账本（= sb_migrate.py status 的判据：同名且 sha256 相同 ⇒ 已上，跳过；同名 sha256 不同 ⇒ 停，迁移在上内测服之后又改过）；
     没上的每份 `sb_migrate.py beta <名> --rehearse` → `sb_migrate.py beta <名> --apply`（apply 自己还会再演练一遍）
  ② 裁判机（root@49.13.166.188，每步一条短 ssh ≤ 25 秒）：
     备份（Caddyfile / /opt/turtle-beta/referee / 旧 env）→ 传代码到暂存目录（行尾转 LF、sha256 回读、py_compile）→
     装进 /opt/turtle-beta/referee/ → 写 env（/etc/turtle-referee/env-mainsite-beta，root 600；密钥只走 ssh 标准输入，
     不进命令行 / 不打印 / 不落本地文件；回读 sha256 与权限）→ 装 systemd 单元 + 两个 drop-in（网关与内测服轮询器各加一行
     EnvironmentFile，**不改** env-beta 与已部署的单元文件）→ daemon-reload →
     DNS（arena / arena-beta 两个子域名都要已指向裁判机，否则 Caddy 会一直申请证书失败）→ Caddy：装片段、Caddyfile 末尾补 import、
     **caddy validate 通过才 reload**（不过 ⇒ 从备份还原 Caddyfile 并停）→
     起 / 重启网关、try-restart 内测服轮询器（周末被 peak timer 停着的不拉起）→ **读进程环境确认**（memory「改 env 必须重启服务并读进程环境确认」：
     MainPID 的 /proc/<pid>/environ 里密钥 / 主站地址与 env 文件一致、进程比 env 文件新、GATEWAY_PORT=8791、MAINSITE_OUTBOX=1）
  ③ 回读（本机 HTTPS，只读）：网关 /healthz = 200 {ok:true}；不带签名的 /mainsite/link/confirm、/mainsite/link/info = 401；
     不带令牌的 /app/link/start = 401；未知路径 = 404；内测服账本两份 20261109 已上；referee_config raid_on / econ_on 现状

内测主站地址：环境变量 MAINSITE_BETA_BASE，没有就读 turtlebet 仓库 origin/main 的 docs/arena-plan.md §8「主站内测网站」
  （`git -C <turtlebet> show origin/main:docs/arena-plan.md`；★不许写进本仓库 —— 公开仓库）。打印时打码。
密钥：~/.config/turtle/secrets/mainsite_beta_hook.txt（或 MAINSITE_BETA_SECRET_FILE 指的文件）。只读进内存。
不写 referee_config（raid_on / econ_on 打印给人）。

正式服（2026-11-10 加；用户 11-10「行」= 迁移 + 正式网关排在白天、过审前上，执行前仍要一句话确认）：
  python tools/mainsite_deploy.py --env prod                         演练（同上，不连任何东西）
  python tools/mainsite_deploy.py --env prod --apply --yes-prod      真执行；不带 --yes-prod ⇒ 退出码 4、什么都不做
  与内测的差别：① 迁移每份一条 `sb_migrate.py prod <名> --rehearse --apply --yes-prod`（它自己先做只读预检：生产函数体 == 仓库迁移前版本、
  内测服账本有同名同 sha256；再在回滚事务里演练；过了才上并回读函数体），账本读正式服的；
  ② 代码装进 /opt/turtle/referee/，env 写 /etc/turtle-referee/env-mainsite（**不改** /etc/turtle-referee/env），drop-in 加给
  turtle-mainsite-gateway（127.0.0.1:8790）与正式服轮询器 turtle-referee；轮询器重启要等在跑的对局收尾（TimeoutStopSec=150）⇒ 这一步等 200 秒；
  正式服轮询器没在跑 = 红（它不该停）；③ 回读多一条：用正式密钥签名调 /mainsite/link/info（假码）⇒ 200 {ok:false}（不是 401 = 密钥对得上，
  且网关 → 正式库的 rpc 通）。正式主站地址 = MAINSITE_PROD_BASE，没有就用 https://turtlepoll.com（主站公开域名，README 里本来就写着）；
  密钥 ~/.config/turtle/secrets/mainsite_prod_hook.txt（或 MAINSITE_PROD_SECRET_FILE）。
"""
import argparse
import datetime as dt
import hashlib
import io
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sb_common as S  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable or "python"
SSH_KEY = os.path.join(os.path.expanduser("~"), ".ssh", "turtle_referee")
SSH_HOST = "root@49.13.166.188"
SERVER_IP = "49.13.166.188"
SSH_OPTS = ["-i", SSH_KEY, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=5"]
REMOTE_LOCK = "/run/lock/turtle-deploy.lock"
TURTLEBET = os.environ.get("TURTLEBET_REPO") or os.path.join(
    os.path.dirname(REPO.rstrip("/\\").split(os.sep + ".claude" + os.sep)[0]), "turtlebet")
SECRET_FILE = os.path.join(os.path.expanduser("~"), ".config", "turtle", "secrets", "mainsite_beta_hook.txt")
PROD_SECRET_FILE = os.path.join(os.path.expanduser("~"), ".config", "turtle", "secrets", "mainsite_prod_hook.txt")
PROD_BASE_DEFAULT = "https://turtlepoll.com"      # 主站公开域名（server/referee/README.md「龟投网关」里本来就写着）

## 内测服要上的迁移（顺序 = 依赖顺序：记账在前，20261109c 的 raid_enabled 读 econ_on）
##   ★2026-11-09 补 20261109b（龟等级 + 领活盖章：拥有 / 等级表进任务 meta，联调要走升级与 pet-level）与
##   20261109d（命运之轮层数按结果单封顶）、20261109e（本周上场过的统领整周都认）—— 两份的检查脚本都要看到 20261109b
##   盖的 a_owned / a_lv ⇒ 排在 b 之后。
MIGRATIONS = ("20261106_econ_ops", "20261106b_econ_flag", "20261106c_econ_state", "20261106e_econ_facts",
              "20261106g_econ_axe_temp", "20261109a_mainsite_core", "20261109b_pet_levels", "20261109c_raid",
              "20261109d_econ_wheel", "20261109e_pet_kept")
NEW_MIGRATIONS = tuple(n for n in MIGRATIONS if n.startswith("20261109"))

BETA = {
    "env": "beta", "label": "内测服", "sb": "beta",
    "unit_file": "server/referee/turtle-mainsite-gateway-beta.service",
    "restart_timeout": 25,
    "host": "arena-beta.turtlearena.xyz",
    "also_dns": ("arena.turtlearena.xyz",),           # 同一个 Caddy 片段里还有正式那个站点：DNS 没加 ⇒ Caddy 一直申请证书失败
    "port": 8791,
    "code_dir": "/opt/turtle-beta/referee",
    "stage": "/root/deploy/mainsite-beta",
    "backup_root": "/root/betadeploy",
    "env_file": "/etc/turtle-referee/env-mainsite-beta",
    "gw_unit": "turtle-mainsite-gateway-beta",
    "poller_unit": "turtle-referee-beta",
    "dropin_name": "10-mainsite.conf",
    "caddy_snip": "/etc/caddy/mainsite-gateway.caddy",
    "caddyfile": "/etc/caddy/Caddyfile",
}
## 正式服：同一台机、同一个 Caddy 片段（片段里本来就有 arena.turtlearena.xyz → 127.0.0.1:8790）。
##   env 单独一份 env-mainsite（root 600），网关单元自带 EnvironmentFile=/etc/turtle-referee/env（SUPABASE_URL / KEY），
##   drop-in 再加 env-mainsite；/etc/turtle-referee/env 本身一个字不动。
PROD = dict(BETA, **{
    "env": "prod", "label": "正式服", "sb": "prod",
    "unit_file": "server/referee/turtle-mainsite-gateway.service",
    "restart_timeout": 200,                         # turtle-referee TimeoutStopSec=150：在跑的对局收尾
    "host": "arena.turtlearena.xyz",
    "also_dns": ("arena-beta.turtlearena.xyz",),
    "port": 8790,
    "code_dir": "/opt/turtle/referee",
    "stage": "/root/deploy/mainsite-prod",
    "backup_root": "/root/proddeploy",
    "env_file": "/etc/turtle-referee/env-mainsite",
    "gw_unit": "turtle-mainsite-gateway",
    "poller_unit": "turtle-referee",
})
ENVS = {"beta": BETA, "prod": PROD}
## 传上去的文件：仓库路径 → 服务器上装到哪（暂存目录里按文件名）
CODE_FILES = ("server/referee/mainsite_gateway.py", "server/referee/mainsite_sign.py",
              "server/referee/raid_intake.py", "server/referee/referee_poller.py")
UNIT_FILE = BETA["unit_file"]
CADDY_FILE = "server/referee/mainsite-gateway.caddy"


def cfg_of(a):
    return ENVS[getattr(a, "env", None) or "beta"]


# ── 本机小工具 ──────────────────────────────────────────────────
def read_lf(rel):
    with open(os.path.join(REPO, rel), "rb") as f:
        return f.read().replace(b"\r\n", b"\n")      # 仓库工作区可能是 CRLF（core.autocrlf=true）；服务器上一律 LF


def sha(b):
    return hashlib.sha256(b).hexdigest()


def mask_url(u):
    m = re.match(r"^(https?://)([^/]+)(.*)$", u or "")
    if not m:
        return "（空）"
    h = m.group(2)
    return "%s%s***%s（%d 字）" % (m.group(1), h[:2], h[-2:] if len(h) > 6 else "", len(u))


def beta_mainsite_base(environ=None):
    """内测主站根地址（不带结尾斜杠）。返回 (地址, 出处)；拿不到 ⇒ ("", 原因)。地址只在内存里。"""
    e = os.environ if environ is None else environ
    v = (e.get("MAINSITE_BETA_BASE") or "").strip().rstrip("/")
    if v:
        return v, "环境变量 MAINSITE_BETA_BASE"
    try:
        r = subprocess.run(["git", "-C", TURTLEBET, "show", "origin/main:docs/arena-plan.md"],
                           capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as ex:
        return "", "读不了 turtlebet 仓库（%s）" % ex
    if r.returncode != 0:
        return "", "turtlebet 仓库 %s 里没有 origin/main:docs/arena-plan.md" % TURTLEBET
    return parse_arena_plan(r.stdout.decode("utf-8", "replace"))


def parse_arena_plan(text):
    """docs/arena-plan.md §8：「主站内测网站：`<根>`」；另核「小游戏调主站：`<根>/api/arena-hook…`」同一个根。"""
    sec = re.split(r"^## 8\.", text, maxsplit=1, flags=re.M)
    body = sec[1] if len(sec) == 2 else ""
    body = re.split(r"^## \d+\.", body, maxsplit=1, flags=re.M)[0]
    m = re.search(r"主站内测网站[:：]\s*`(https?://[^`\s]+)`", body)
    if not m:
        return "", "turtlebet docs/arena-plan.md §8 里找不到「主站内测网站：`…`」"
    base = m.group(1).rstrip("/")
    h = re.search(r"小游戏调主站[:：]\s*`(https?://[^`\s]+)`", body)
    if h and not h.group(1).startswith(base + "/api/arena-hook"):
        return "", "§8 里「小游戏调主站」与「主站内测网站」不是同一个根"
    return base, "turtlebet origin/main docs/arena-plan.md §8"


def prod_mainsite_base(environ=None):
    e = os.environ if environ is None else environ
    v = (e.get("MAINSITE_PROD_BASE") or "").strip().rstrip("/")
    return (v, "环境变量 MAINSITE_PROD_BASE") if v else (PROD_BASE_DEFAULT, "默认（主站公开域名）")


def load_secret(environ=None, env_name="beta"):
    e = os.environ if environ is None else environ
    if env_name == "prod":
        p = (e.get("MAINSITE_PROD_SECRET_FILE") or "").strip() or PROD_SECRET_FILE
    else:
        p = (e.get("MAINSITE_BETA_SECRET_FILE") or "").strip() or SECRET_FILE
    try:
        with open(p, encoding="utf-8") as f:
            s = f.read().strip()
    except OSError:
        return "", p
    return s, p


def env_file_bytes(base, secret, stamp, label="内测服"):
    """服务器上 env-mainsite(-beta) 的全部内容（只在内存里；经 ssh 标准输入写过去）。"""
    return ("# 龟投（主站）对接 · %s —— tools/mainsite_deploy.py 写于 %s；root 600；★密钥不进仓库\n"
            "MAINSITE_BASE=%s\nMAINSITE_HOOK_SECRET=%s\nMAINSITE_OUTBOX=1\n" % (label, stamp, base, secret)).encode("utf-8")


def dropin_bytes(env_file):
    return ("# tools/mainsite_deploy.py：龟投网关 / 发件箱的地址与密钥（不改 env-beta 本身）\n"
            "[Service]\nEnvironmentFile=%s\n" % env_file).encode("utf-8")


def utc_now(a):
    if getattr(a, "now", None):
        return dt.datetime.strptime(a.now, "%Y-%m-%dT%H:%MZ").replace(tzinfo=dt.timezone.utc)
    return dt.datetime.now(dt.timezone.utc)


# ── 步骤 ────────────────────────────────────────────────────────
class Step:
    """kind: local（本机子进程）/ ssh（短 ssh）/ ssh_in（ssh + 标准输入，内容不打印）/ check（本机 Python 判据）/ skip。"""

    def __init__(self, key, phase, title, kind, cmd=None, data=None, expect=None, on_fail=None, fn=None, note="", timeout=25):
        self.key, self.phase, self.title, self.kind = key, phase, title, kind
        self.cmd, self.data, self.expect, self.on_fail, self.fn, self.note = cmd, data, expect, on_fail, fn, note
        self.timeout = timeout


def remote_check_proc(unit, env_file, want, port=None):
    """读 unit 的 MainPID 进程环境：只把各值的 sha256 前 16 位打回来（本机比，不打印值）；进程比 env 文件新 ⇒ fresh=1。"""
    keys = ["MAINSITE_BASE", "MAINSITE_HOOK_SECRET", "MAINSITE_OUTBOX", "GATEWAY_PORT", "SUPABASE_URL"]
    return ("P=$(systemctl show -p MainPID --value %s); if [ -z \"$P\" ] || [ \"$P\" = 0 ]; then echo NOPID; exit 0; fi; "
            "echo pid=$P; E=$(tr '\\0' '\\n' < /proc/$P/environ); "
            "for k in %s; do v=$(printf '%%s\\n' \"$E\" | grep -m1 \"^$k=\" | cut -d= -f2-); "
            "printf '%%s %%s %%s\\n' \"$k\" \"$(printf '%%s' \"$v\" | sha256sum | cut -c1-16)\" \"${#v}\"; done; "
            "[ $(stat -c %%Y /proc/$P) -ge $(stat -c %%Y %s) ] && echo fresh=1 || echo fresh=0"
            % (shlex.quote(unit), " ".join(keys), shlex.quote(env_file)))


def judge_proc(out, want):
    """remote_check_proc 的回显 → (ok, 说明)。want: {键: 期望值}（值只在内存里比 sha256）。"""
    if "NOPID" in out:
        return False, "进程没在跑（MainPID 为空）"
    got = {}
    for ln in out.splitlines():
        p = ln.split()
        if len(p) == 3 and p[0].isupper():
            got[p[0]] = p[1]
    bad = [k for k, v in want.items() if got.get(k) != sha(v.encode("utf-8"))[:16]]
    fresh = "fresh=1" in out
    if bad or not fresh:
        return False, "进程环境与 env 不一致: %s%s" % (",".join(bad) or "-", "；进程比 env 文件旧（没重启？）" if not fresh else "")
    return True, "进程环境里 %s 与 env 一致、进程比 env 文件新" % "/".join(sorted(want))


def plan(a, ctx, ledger=None):
    """完整步骤表（顺序即执行顺序）。ledger = 目标库账本 {名: sha256}（None = 演练：没读账本，全部列出）。"""
    b = cfg_of(a)
    lab = b["label"]
    prod = b["env"] == "prod"
    steps = []
    only = getattr(a, "only", None)
    # ① 迁移
    if only in (None, "migrations"):
        for name in MIGRATIONS:
            want = ctx["mig_sha"].get(name, "")
            got = None if ledger is None else ledger.get(name)
            if got is not None and got == want:
                steps.append(Step("mig:%s:skip" % name, "①迁移", "%s %s已上（sha256 相同）⇒ 跳过" % (name, lab), "skip"))
                continue
            if got is not None and got != want:
                steps.append(Step("mig:%s:shadiff" % name, "①迁移", "%s %s账本 sha256 与仓库不同 ⇒ 停" % (name, lab), "check",
                                  fn=lambda n=name: (False, "%s 上%s之后又改过（sb_migrate 不会重上同名迁移）" % (n, lab))))
                continue
            tag = "" if ledger is not None else "（--apply 时先读账本：已上且 sha256 相同 ⇒ 跳过）"
            if prod:
                # 一条命令 = 只读预检（漂移 / 内测服账本同名同 sha256）→ 回滚事务演练 → 上线 → 回读函数体；任何一关不过 rc≠0
                steps.append(Step("mig:%s:apply" % name, "①迁移", "%s 正式服 预检 → 演练 → 上线%s" % (name, tag), "local",
                                  cmd=[PY, os.path.join(REPO, "tools", "sb_migrate.py"), "prod", name, "--rehearse", "--apply", "--yes-prod"],
                                  expect=["演练: ALL PASS", "不同 0 个"]))
                continue
            steps.append(Step("mig:%s:rehearse" % name, "①迁移", "%s 内测服演练%s" % (name, tag), "local",
                              cmd=[PY, os.path.join(REPO, "tools", "sb_migrate.py"), "beta", name, "--rehearse"],
                              expect="内测服演练过了"))
            steps.append(Step("mig:%s:apply" % name, "①迁移", "%s 内测服上线" % name, "local",
                              cmd=[PY, os.path.join(REPO, "tools", "sb_migrate.py"), "beta", name, "--apply"],
                              expect="内测服已上 %s" % name))
    if only in (None, "server"):
        st, cd = b["stage"], b["code_dir"]
        steps.append(Step("srv:lock", "②裁判机", "ssh 通、没有别的部署在跑（%s）" % REMOTE_LOCK, "ssh",
                          cmd="[ -e %s ] && ! flock -n %s true && echo BUSY || echo FREE" % (REMOTE_LOCK, REMOTE_LOCK),
                          expect="FREE"))
        steps.append(Step("srv:backup", "②裁判机", "备份 Caddyfile / %s / 旧 env → %s/mainsite-<时刻>/" % (cd, b["backup_root"]), "ssh",
                          cmd=("B=%s/mainsite-$(date -u +%%Y%%m%%dT%%H%%M%%SZ); mkdir -p $B && cp -a %s $B/ && cp -a %s $B/referee && "
                               "{ [ ! -f %s ] || cp -a %s $B/; } && echo $B > %s/mainsite-last && echo BACKUP=$B"
                               % (b["backup_root"], b["caddyfile"], cd, b["env_file"], b["env_file"], b["backup_root"])),
                          expect="BACKUP="))
        files = [(rel, os.path.basename(rel)) for rel in CODE_FILES + (b["unit_file"], CADDY_FILE)]
        for rel, name in files:
            steps.append(Step("srv:put:%s" % name, "②裁判机", "传 %s → %s/%s（LF，sha256 %s…）" % (rel, st, name, ctx["file_sha"][rel][:12]),
                              "ssh_in", cmd="mkdir -p %s && cat > %s/%s.part && mv %s/%s.part %s/%s && sha256sum %s/%s"
                              % (st, st, name, st, name, st, name, st, name),
                              data=lambda r=rel: read_lf(r), expect=ctx["file_sha"][rel], note="（标准输入 = 文件内容）"))
        steps.append(Step("srv:compile", "②裁判机", "暂存目录里 py_compile 四个 .py", "ssh",
                          cmd="cd %s && python3 -m py_compile %s && echo COMPILE_OK" % (st, " ".join(os.path.basename(x) for x in CODE_FILES)),
                          expect="COMPILE_OK"))
        steps.append(Step("srv:install-code", "②裁判机", "装代码 → %s/（root 644）" % cd, "ssh",
                          cmd="install -m 644 -o root -g root %s %s/ && echo INSTALLED" % (" ".join("%s/%s" % (st, os.path.basename(x)) for x in CODE_FILES), cd),
                          expect="INSTALLED"))
        steps.append(Step("srv:env", "②裁判机", "写 %s（root 600：MAINSITE_BASE / MAINSITE_HOOK_SECRET / MAINSITE_OUTBOX=1）" % b["env_file"],
                          "ssh_in", cmd="umask 077 && cat > %s.part && chown root:root %s.part && chmod 600 %s.part && mv %s.part %s && "
                          "stat -c 'MODE=%%a %%U:%%G' %s && sha256sum %s" % ((b["env_file"],) * 7),
                          data=lambda: ctx["env_bytes"], expect=["MODE=600 root:root", ctx["env_sha"]],
                          note="（标准输入 = env 内容，★含密钥：不打印、不落本地文件、不进命令行）"))
        dropin = dropin_bytes(b["env_file"])
        for unit in (b["gw_unit"], b["poller_unit"]):
            d = "/etc/systemd/system/%s.service.d" % unit
            steps.append(Step("srv:dropin:%s" % unit, "②裁判机", "drop-in %s/%s（EnvironmentFile=%s）" % (d, b["dropin_name"], b["env_file"]),
                              "ssh_in", cmd="mkdir -p %s && cat > %s/%s && chmod 644 %s/%s && sha256sum %s/%s"
                              % (d, d, b["dropin_name"], d, b["dropin_name"], d, b["dropin_name"]),
                              data=lambda x=dropin: x, expect=sha(dropin)))
        steps.append(Step("srv:unit", "②裁判机", "装 %s.service → /etc/systemd/system/ + daemon-reload" % b["gw_unit"], "ssh",
                          cmd="install -m 644 %s/%s /etc/systemd/system/%s.service && systemctl daemon-reload && "
                              "systemctl show -p EnvironmentFiles %s.service" % (st, os.path.basename(b["unit_file"]), b["gw_unit"], b["gw_unit"]),
                          expect=b["env_file"]))
        steps.append(Step("srv:dns", "②裁判机", "DNS：%s 都解析到 %s（没加 ⇒ Caddy 一直申请证书失败，停）"
                          % (" / ".join((b["host"],) + b["also_dns"]), SERVER_IP), "check",
                          fn=lambda: check_dns((b["host"],) + b["also_dns"])))
        backup = "$(cat %s/mainsite-last)" % b["backup_root"]
        steps.append(Step("srv:caddy-snippet", "②裁判机", "装 Caddy 片段 → %s；Caddyfile 末尾没有 import 就补一行" % b["caddy_snip"], "ssh",
                          cmd=("install -m 644 %s/%s %s && { grep -qxF 'import %s' %s || printf '\\nimport %s\\n' >> %s; } && "
                               "grep -cxF 'import %s' %s" % (st, os.path.basename(CADDY_FILE), b["caddy_snip"], b["caddy_snip"], b["caddyfile"],
                                                             b["caddy_snip"], b["caddyfile"], b["caddy_snip"], b["caddyfile"])),
                          expect="1"))
        steps.append(Step("srv:caddy-validate", "②裁判机", "caddy validate（不过 ⇒ 从备份还原 Caddyfile、删片段，停；不 reload）", "ssh",
                          cmd="caddy validate --config %s --adapter caddyfile 2>&1 | tail -n 3; [ ${PIPESTATUS[0]} -eq 0 ] && echo VALIDATE_OK" % b["caddyfile"],
                          expect="VALIDATE_OK",
                          on_fail="cp -a %s/Caddyfile %s && rm -f %s && echo RESTORED" % (backup, b["caddyfile"], b["caddy_snip"])))
        steps.append(Step("srv:caddy-reload", "②裁判机", "systemctl reload caddy（validate 过了才到这一步）", "ssh",
                          cmd="systemctl reload caddy && systemctl is-active caddy", expect="active"))
        steps.append(Step("srv:restart", "②裁判机",
                          ("enable + restart 网关；try-restart 正式服轮询器（在跑的对局收尾后才退，最多等 %d 秒）" % b["restart_timeout"]) if prod
                          else "enable + restart 网关；try-restart 内测服轮询器（周末 / beta-off 停着的不拉起）", "ssh",
                          cmd="systemctl enable %s >/dev/null 2>&1; systemctl restart %s && sleep 2 && systemctl try-restart %s; "
                              "echo GW=$(systemctl is-active %s) POLLER=$(systemctl is-active %s)"
                              % (b["gw_unit"], b["gw_unit"], b["poller_unit"], b["gw_unit"], b["poller_unit"]),
                          expect=["GW=active", "POLLER=active"] if prod else "GW=active", timeout=b["restart_timeout"]))
        steps.append(Step("srv:procenv:gw", "②裁判机", "读网关进程环境（密钥 / 主站地址与 env 一致、GATEWAY_PORT=%d、进程比 env 新）" % b["port"], "ssh",
                          cmd=remote_check_proc(b["gw_unit"], b["env_file"], None),
                          fn=lambda out: judge_proc(out, {"MAINSITE_HOOK_SECRET": ctx["secret"], "MAINSITE_BASE": ctx["base"],
                                                          "MAINSITE_OUTBOX": "1", "GATEWAY_PORT": str(b["port"])})))
        steps.append(Step("srv:procenv:poller", "②裁判机",
                          "读%s轮询器进程环境（发件箱：密钥 / 地址 / MAINSITE_OUTBOX=1；%s）" % (lab, "没在跑 = 红" if prod else "没在跑 ⇒ 记一条待办"), "ssh",
                          cmd=remote_check_proc(b["poller_unit"], b["env_file"], None),
                          fn=lambda out: (True, "内测服轮询器没在跑（周末 / beta-off）：drop-in 已装，下次被拉起时读新 env")
                          if ("NOPID" in out and not prod)
                          else judge_proc(out, {"MAINSITE_HOOK_SECRET": ctx["secret"], "MAINSITE_BASE": ctx["base"], "MAINSITE_OUTBOX": "1"})))
        steps.append(Step("srv:journal", "②裁判机", "网关日志：起来了、raid_intake=on；本机回环 /healthz", "ssh",
                          cmd="journalctl -u %s -n 50 -r --no-pager -o cat | grep -m1 'mainsite gateway: 127.0.0.1:%d' ; "
                              "curl -s -m 5 http://127.0.0.1:%d/healthz" % (b["gw_unit"], b["port"], b["port"]),
                          expect=["raid_intake=on", '"ok": true']))
    if only in (None, "server", "readback"):
        base = "https://" + b["host"]
        for key, title, method, path, hdr, code in (
                ("rb:healthz", "= 200 {ok:true}", "GET", "/healthz", {}, 200),
                ("rb:confirm-unsigned", "不带签名 = 401", "POST", "/mainsite/link/confirm", {"Content-Type": "application/json"}, 401),
                ("rb:info-unsigned", "不带签名 = 401", "GET", "/mainsite/link/info?code=abcd1234", {}, 401),
                ("rb:app-unsigned", "不带令牌 = 401", "POST", "/app/link/start", {"Content-Type": "application/json"}, 401),
                ("rb:404", "= 404（Caddy 只放 /mainsite/* /app/* /healthz）", "GET", "/nope", {}, 404)):
            steps.append(Step(key, "③回读", "%s %s%s %s" % (method, base, path, title), "check",
                              fn=lambda m=method, p=path, h=hdr, c=code: http_expect(m, base + p, h, c)))
        if prod:
            steps.append(Step("rb:signed", "③回读", "GET %s/mainsite/link/info（假码，用正式密钥签名）= 200 {ok:false}"
                                                  "（不是 401 ⇒ 密钥对得上；有回包 ⇒ 网关 → 正式库 rpc 通）" % base, "check",
                              fn=lambda: signed_probe(base, ctx["secret"])))
        steps.append(Step("rb:ledger", "③回读", "%s账本：20261109a / b / c / d / e 已上；referee_config raid_on / econ_on 现状（只读）" % lab,
                          "check", fn=lambda: readback_db(ctx)))
    return steps


# ── 本机判据（--apply 才跑；演练不连网）────────────────────────────
def check_dns(hosts):
    bad = []
    for h in hosts:
        try:
            ips = sorted({x[4][0] for x in socket.getaddrinfo(h, 443, socket.AF_INET)})
        except OSError as ex:
            ips = ["解析失败 %s" % ex]
        if ips != [SERVER_IP]:
            bad.append("%s → %s" % (h, ips))
    return (not bad), ("都指向 %s" % SERVER_IP) if not bad else "；".join(bad) + "（Porkbun 加 A 记录）"


def http_expect(method, url, headers, code):
    req = urllib.request.Request(url, data=b"{}" if method == "POST" else None, method=method, headers=headers)
    try:
        with S.OPENER.open(req, timeout=20) as r:
            st, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        st, raw = e.code, e.read()
    except (urllib.error.URLError, OSError) as e:
        return False, "连不上: %s" % e
    txt = raw.decode("utf-8", "replace")[:120]
    return st == code, "HTTP %d %s" % (st, txt)


def signed_probe(base, secret):
    """用主站的签名规则（server/referee/mainsite_sign.py）调 GET /mainsite/link/info?code=<假码>：
    密钥对得上 ⇒ 网关验签放行 → rpc mainsite_link_info → 200 {ok:false, error}；密钥不对 ⇒ 401；库函数不在 ⇒ 5xx。"""
    sys.path.insert(0, os.path.join(REPO, "server", "referee"))
    import mainsite_sign as MS
    ts = int(time.time())
    hdr = {MS.HDR_TS: str(ts), MS.HDR_SIG: MS.sign(secret, ts, None)}
    req = urllib.request.Request(base + "/mainsite/link/info?code=deployprobe0000", method="GET", headers=hdr)
    try:
        with S.OPENER.open(req, timeout=20) as r:
            st, raw = r.status, r.read()
    except urllib.error.HTTPError as e:
        st, raw = e.code, e.read()
    except (urllib.error.URLError, OSError) as e:
        return False, "连不上: %s" % e
    try:
        body = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        body = {}
    good = st == 200 and body.get("ok") is False and "signature" not in str(body.get("error"))
    return good, "HTTP %d ok=%s error=%s" % (st, body.get("ok"), str(body.get("error"))[:60])


def read_ledger(env="beta"):
    import sb_migrate as M
    led = M.ledger(S.PROD_REF if env == "prod" else S.BETA_REF)
    return {} if led is None else {k: v.get("sha256") for k, v in led.items()}


def read_beta_ledger():
    return read_ledger("beta")


def readback_db(ctx):
    env = ctx.get("env", "beta")
    ref = S.PROD_REF if env == "prod" else S.BETA_REF
    led = read_ledger(env)
    miss = [n for n in NEW_MIGRATIONS if led.get(n) != ctx["mig_sha"].get(n)]
    cfg = S.one(S.query_ro(ref, "select (to_jsonb(c) ->> 'raid_on') as raid_on, (to_jsonb(c) ->> 'econ_on') as econ_on "
                                "from public.referee_config c where id = 1"))
    ctx["cfg"] = cfg
    msg = "raid_on=%s econ_on=%s" % (cfg.get("raid_on"), cfg.get("econ_on"))
    return (not miss), ("两份已上；" if not miss else "没上: %s；" % miss) + msg


# ── 执行器（门禁把它换成假的：记账不连网）───────────────────────────
class Runner:
    def local(self, argv):
        r = subprocess.run(argv, cwd=REPO, capture_output=True, timeout=1800)
        return r.returncode, r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")

    def ssh(self, cmd, data=None, timeout=25):
        try:
            r = subprocess.run(["ssh"] + SSH_OPTS + [SSH_HOST, "bash -c " + shlex.quote(cmd)], input=data,
                               capture_output=True, timeout=timeout)
            return r.returncode, r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")
        except (subprocess.TimeoutExpired, OSError) as e:
            return None, str(e)


def run_step(s, runner):
    """返回 (ok, 说明)。说明里不会有 data 的内容（data 只给标准输入）。"""
    if s.kind == "skip":
        return True, "跳过"
    if s.kind == "check":
        return s.fn()
    if s.kind == "local":
        rc, out = runner.local(s.cmd)
    else:
        rc, out = runner.ssh(s.cmd, data=s.data() if s.data else None, timeout=s.timeout)
    if s.fn is not None:
        ok, why = s.fn(out)
        return (rc == 0 and ok), why
    exp = s.expect if isinstance(s.expect, list) else ([s.expect] if s.expect else [])
    miss = [e for e in exp if e not in out]
    tail = out.strip().splitlines()[-1][:200] if out.strip() else ""
    if s.kind == "ssh_in" and s.key == "srv:env":
        tail = "（回显含 sha256 与权限，已核对，不打印）"
    return (rc == 0 and not miss), ("rc=%s %s" % (rc, tail)) + ("；缺 %s" % [m[:16] for m in miss] if miss else "")


def print_step(i, s):
    print("  %2d. [%s] %s" % (i, s.phase, s.title))
    if s.kind == "local":
        print("        $ %s" % " ".join(shlex.quote(os.path.relpath(x, REPO) if os.path.isabs(x) and x.startswith(REPO) else x)
                                       for x in [os.path.basename(PY)] + s.cmd[1:]))
    elif s.kind in ("ssh", "ssh_in"):
        print("        ssh> %s%s" % (s.cmd if len(s.cmd) < 260 else s.cmd[:257] + "…", s.note))
        if s.on_fail:
            print("        不过 ⇒ ssh> %s" % s.on_fail)


# ── 主流程 ──────────────────────────────────────────────────────
def build_ctx(a, c):
    b = cfg_of(a)
    ctx = {"mig_sha": {}, "file_sha": {}, "env": b["env"]}
    import sb_migrate as M
    for name in MIGRATIONS:
        p = os.path.join(M.MIG_DIR, name + ".sql")
        if not os.path.exists(p):
            c.append("仓库里没有迁移 %s" % name)
            continue
        ctx["mig_sha"][name] = M.sha256_lf(p)
        if not M.chk_path(name):
            c.append("迁移 %s 缺检查脚本（sb_migrate 会拒）" % name)
    for rel in CODE_FILES + (b["unit_file"], CADDY_FILE):
        try:
            ctx["file_sha"][rel] = sha(read_lf(rel))
        except OSError:
            c.append("仓库里没有 %s" % rel)
            ctx["file_sha"][rel] = "?"
    base, src = prod_mainsite_base() if b["env"] == "prod" else beta_mainsite_base()
    ctx["base"], ctx["base_src"] = base, src
    if not base:
        c.append("%s主站地址: %s" % (b["label"], src))
    secret, sp = load_secret(env_name=b["env"])
    ctx["secret"] = secret
    if not secret:
        c.append("没有%s密钥文件 %s（或是空的）" % (b["label"], sp))
    ctx["secret_path"] = sp
    ctx["stamp"] = utc_now(a).strftime("%Y-%m-%dT%H:%MZ")
    ctx["env_bytes"] = env_file_bytes(base, secret, ctx["stamp"], b["label"])
    ctx["env_sha"] = sha(ctx["env_bytes"])
    return ctx


def main(argv=None, runner=None):
    S.stdout_utf8()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env", choices=["beta", "prod"], default="beta",
                    help="beta = 内测服（默认）；prod = 正式服（真执行还要 --yes-prod，且先得到用户同意）")
    ap.add_argument("--dry-run", action="store_true", help="（默认）只打印要做的每一步，不连任何服务器 / 数据库")
    ap.add_argument("--apply", action="store_true", help="真执行")
    ap.add_argument("--yes-prod", action="store_true", help="--env prod --apply 必带（不是授权：用户的话才是）")
    ap.add_argument("--weekend-ok", action="store_true", help="周六 / 周日（UTC）真执行要再加这个（用户明说了才加）")
    ap.add_argument("--only", choices=["migrations", "server", "readback"], help="只做其中一段（server 段含回读）")
    ap.add_argument("--now", help=argparse.SUPPRESS)      # 门禁用：假装现在是某一刻（%Y-%m-%dT%H:%MZ）
    a = ap.parse_args(argv)
    b = cfg_of(a)
    lab = b["label"]
    prod = b["env"] == "prod"
    runner = runner or Runner()
    apply = a.apply and not a.dry_run
    probs = []
    ctx = build_ctx(a, probs)
    now = utc_now(a)
    weekend = now.weekday() >= 5
    print("== 龟投网关 · %s部署（%s）%s" % (lab, "--apply 真执行" if apply else "--dry-run 演练：不连任何服务器 / 数据库",
                                       "  ★%s UTC 是周%s" % (now.strftime("%m-%d %H:%M"), "六日"[now.weekday() - 5]) if weekend else ""))
    print("== 本机检查（只读本机文件）")
    print("  · %s主站地址 %s（出处: %s）" % (lab, mask_url(ctx["base"]), ctx["base_src"]))
    print("  · 密钥文件 %s：%s" % (ctx["secret_path"], "在（%d 字，不打印）" % len(ctx["secret"]) if ctx["secret"] else "没有"))
    print("  · 迁移 %d 份、传上去的文件 %d 个（sha256 按 LF 算）" % (len(ctx["mig_sha"]), len(ctx["file_sha"])))
    for p in probs:
        print("  ✗ " + p)
    if apply and prod and not a.yes_prod:
        print("\n✗ 拒绝：正式服真执行要 --yes-prod（并且先得到用户同意）")
        return 4
    if apply and weekend and not a.weekend_ok:
        print("\n✗ 拒绝：周末（周六 / 周日 UTC）不动裁判机与%s库（CLAUDE.md §3）；用户明说了再加 --weekend-ok" % lab)
        return 3
    if apply and probs:
        print("\n✗ 本机检查没过（%d 条）⇒ 不执行" % len(probs))
        return 1
    ledger = None
    if apply and a.only in (None, "migrations"):
        try:
            ledger = runner.ledger() if hasattr(runner, "ledger") else read_ledger(b["env"])
        except (S.SqlError, SystemExit) as ex:
            print("✗ 读不到%s账本: %s" % (lab, str(ex)[:200]))
            return 1
    steps = plan(a, ctx, ledger)
    print("== 步骤（%d 步，顺序即执行顺序）" % len(steps))
    if not apply:
        for i, s in enumerate(steps, 1):
            print_step(i, s)
        if weekend and not a.weekend_ok:
            print("\n  ★今天是周末：--apply 还要再加 --weekend-ok（用户明说了才加）")
        print("\n== 演练结束：什么都没改。真执行: python tools/mainsite_deploy.py %s"
              % ("--env prod --apply --yes-prod（先得到用户同意）" if prod else "--apply；之后 python tools/mainsite_beta_smoke.py"))
        return 0 if not probs else 1
    for i, s in enumerate(steps, 1):
        print_step(i, s)
        t0 = time.time()
        ok, why = run_step(s, runner)
        print("        %s %s（%.1f 秒）" % ("✓" if ok else "✗", why, time.time() - t0))
        if not ok:
            if s.on_fail:
                rc, out = runner.ssh(s.on_fail)
                print("        还原: rc=%s %s" % (rc, out.strip()[-120:]))
            print("\n✗ 第 %d 步没过 ⇒ 停（前面已做的见上；备份在服务器 %s/mainsite-last 指的目录）" % (i, b["backup_root"]))
            return 1
    print("\n== 全部 %d 步过了" % len(steps))
    cfg = ctx.get("cfg") or {}
    if prod:
        print("  %s referee_config: raid_on=%s econ_on=%s（用户 11-10 定：正式服这两个保持关，本工具不写）"
              % (lab, cfg.get("raid_on"), cfg.get("econ_on")))
        return 0
    if str(cfg.get("raid_on")) != "true" or str(cfg.get("econ_on")) != "true":
        print("  待办（内测服写入，本工具不做）：偷袭要 raid_on 与 econ_on 都开（20261109c raid_enabled）——"
              "\n    update public.referee_config set raid_on = true, updated_at = now() where id = 1;   -- econ_on 由记账线（S5）开")
    print("  下一步：python tools/mainsite_beta_smoke.py（以主站身份走一遍登录 / 绑定 / 偷袭）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
