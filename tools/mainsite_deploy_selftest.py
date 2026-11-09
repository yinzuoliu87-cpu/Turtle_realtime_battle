# -*- coding: utf-8 -*-
"""mainsite_deploy_selftest —— tools/mainsite_deploy.py（龟投网关内测环境部署）的自证门禁（2026-11-09 · 20261107 §4.7）。

不连网、不 ssh、不连库：执行器换成记账的假 Runner（本机子进程 / ssh 一律只记下来、按命令回假回显），
DNS / HTTPS 回读 / 账本回读三个本机判据打桩。真的部分是 mainsite_deploy.py 的 main()、plan()、run_step()、judge_proc()。

断言：
  A 默认（不带任何参数）= 演练：一条 ssh / 本机子进程 / 账本读取都没有；打印「什么都没改」
  B 周末（UTC 周六 / 周日）--apply 不带 --weekend-ok ⇒ 退出码 3、什么都没做（连账本都不读）；带了 ⇒ 放行
  C 平日 --apply 的执行顺序：迁移（账本里已上且 sha256 相同的跳过、没上的先 --rehearse 再 --apply）全部在裁判机之前 →
    传代码 → 写 env → 装单元 → DNS → Caddy 片段 → caddy validate → reload → 重启 → 读进程环境 → HTTPS 回读
  D 密钥只出现在写 env 那一步的标准输入里：不在任何命令行、不在任何本机子进程参数、不在打印输出里
  E caddy validate 不过 ⇒ 不 reload、跑还原命令、退出码 1
  F 进程比 env 文件旧（没重启）/ 进程环境里的密钥与 env 不同 ⇒ 退出码 1（读进程环境这一关真会红）
  G 账本里同名迁移 sha256 与仓库不同 ⇒ 停在迁移段、一条 ssh 都不发
  H 内测主站地址只从 turtlebet docs/arena-plan.md §8 / 环境变量读（解析器两种写法 + 根不一致拒）
进 run-tests.sh 门禁（成功打印 ALL OK）。
"""
import hashlib
import io
import os
import sys
import tempfile

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mainsite_deploy as D  # noqa: E402

SECRET = "selftest-only-secret-0123456789abcdef"      # 假密钥（真密钥只在本机 ~/.config/turtle/secrets/）
BASE = "http://mock-mainsite.invalid:8080"
fails = [0]
n = [0]


def ok(name, cond, detail=""):
    n[0] += 1
    print(("  ✓ " if cond else "  ✗ ") + name + ("" if cond else "  —— " + str(detail)[:400]))
    if not cond:
        fails[0] += 1


def sha(b):
    return hashlib.sha256(b if isinstance(b, bytes) else b.encode("utf-8")).hexdigest()


class FakeRunner:
    """记账的执行器。ssh 按命令认步骤、回最像真机的回显；env 那一步把标准输入里的 env 记下来，读进程环境时照它回 sha256。"""

    def __init__(self, ledger=None, validate_ok=True, fresh=True, proc_secret=None):
        self.calls = []          # (种类, 命令或 argv, 标准输入)
        self.led = ledger
        self.validate_ok = validate_ok
        self.fresh = fresh
        self.proc_secret = proc_secret
        self.env = {}
        self.ledger_reads = 0

    def ledger(self):
        self.ledger_reads += 1
        return dict(self.led or {})

    def local(self, argv):
        self.calls.append(("local", list(argv), None))
        name = argv[3]
        return 0, ("✓ 内测服演练过了" if "--rehearse" in argv else "✓ 内测服已上 %s" % name)

    def ssh(self, cmd, data=None, timeout=25):
        self.calls.append(("ssh", cmd, data))
        if "flock" in cmd:
            return 0, "FREE\n"
        if cmd.startswith("B="):
            return 0, "BACKUP=/root/betadeploy/mainsite-x\n"
        if "py_compile" in cmd:
            return 0, "COMPILE_OK\n"
        if cmd.startswith("install -m 644 -o root"):
            return 0, "INSTALLED\n"
        if "env-mainsite-beta.part" in cmd:
            for ln in data.decode("utf-8").splitlines():
                if "=" in ln and not ln.startswith("#"):
                    k, v = ln.split("=", 1)
                    self.env[k] = v
            return 0, "MODE=600 root:root\n%s  /etc/turtle-referee/env-mainsite-beta\n" % sha(data)
        if data is not None:                                   # 传文件 / drop-in：回读 sha256
            return 0, "%s  x\n" % sha(data)
        if "daemon-reload" in cmd:
            return 0, "EnvironmentFiles=/etc/turtle-referee/env-beta (ignore_errors=no) /etc/turtle-referee/env-mainsite-beta (ignore_errors=no)\n"
        if "grep -cxF" in cmd:
            return 0, "1\n"
        if cmd.startswith("caddy validate"):
            return (0, "Valid configuration\nVALIDATE_OK\n") if self.validate_ok else (0, "Error: adapting config\n")
        if cmd.startswith("systemctl reload caddy"):
            return 0, "active\n"
        if "systemctl restart" in cmd:
            return 0, "GW=active POLLER=active\n"
        if "MainPID" in cmd:
            env = dict(self.env)
            if self.proc_secret is not None:
                env["MAINSITE_HOOK_SECRET"] = self.proc_secret
            env["GATEWAY_PORT"] = "8791" if "gateway" in cmd else ""
            env["SUPABASE_URL"] = "https://beta.invalid"
            out = "pid=4242\n" + "".join("%s %s %d\n" % (k, sha(env.get(k, ""))[:16], len(env.get(k, "")))
                                         for k in ("MAINSITE_BASE", "MAINSITE_HOOK_SECRET", "MAINSITE_OUTBOX", "GATEWAY_PORT", "SUPABASE_URL"))
            return 0, out + ("fresh=1\n" if self.fresh else "fresh=0\n")
        if "journalctl" in cmd:
            return 0, 'mainsite gateway: 127.0.0.1:8791, raid_intake=on\n{"ok": true}'
        if "RESTORED" in cmd:
            return 0, "RESTORED\n"
        return 1, "（假 Runner 不认识的命令）"

    def ssh_cmds(self):
        return [c[1] for c in self.calls if c[0] == "ssh"]


PROBES = []


def stub_checks():
    D.check_dns = lambda hosts: (PROBES.append(("dns", tuple(hosts))) or True, "stub")
    D.http_expect = lambda m, url, h, code: (PROBES.append(("http", m, url, code)) or True, "stub HTTP %d" % code)
    D.readback_db = lambda ctx: (PROBES.append(("db",)) or True, "stub")


def run(argv, runner):
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    try:
        rc = D.main(argv, runner=runner)
    finally:
        sys.stdout = old
    return rc, buf.getvalue()


def full_ledger(skip_new=True):
    """账本：记账五份已上（sha256 与仓库同），20261109a / b / c / d / e 没上。"""
    import sb_migrate as M
    led = {}
    for name in D.MIGRATIONS:
        if skip_new and name.startswith("20261109"):
            continue
        led[name] = M.sha256_lf(os.path.join(M.MIG_DIR, name + ".sql"))
    return led


def main():
    td = tempfile.mkdtemp(prefix="msdeploy-selftest-")
    sp = os.path.join(td, "secret.txt")
    with open(sp, "w", encoding="utf-8") as f:
        f.write(SECRET + "\n")
    os.environ["MAINSITE_BETA_SECRET_FILE"] = sp
    os.environ["MAINSITE_BETA_BASE"] = BASE
    stub_checks()
    WEEKDAY, SUNDAY, SATURDAY = "2026-11-09T09:00Z", "2026-11-08T12:00Z", "2026-11-14T23:59Z"

    print("=== A 默认就是演练 ===")
    r = FakeRunner(ledger=full_ledger())
    PROBES.clear()
    rc, out = run(["--now", WEEKDAY], r)
    ok("A1 不带参数：一条 ssh / 本机子进程都没有（N=%d）" % len(r.calls), not r.calls, r.calls[:2])
    ok("A2 不带参数：没读账本、没做 DNS / HTTPS / 库回读", r.ledger_reads == 0 and not PROBES, (r.ledger_reads, PROBES[:2]))
    ok("A3 打印「演练」「什么都没改」且列出了步骤", "演练" in out and "什么都没改" in out and "caddy validate" in out, out[-300:])
    ok("A4 退出码 0", rc == 0, rc)
    r2 = FakeRunner(ledger=full_ledger())
    rc2, out2 = run(["--dry-run", "--apply", "--now", WEEKDAY], r2)
    ok("A5 --dry-run 与 --apply 同时给 ⇒ 按演练（什么都不做）", not r2.calls and r2.ledger_reads == 0 and "什么都没改" in out2, r2.calls[:2])

    print("=== B 周末不动裁判机 ===")
    for label, when in (("周日", SUNDAY), ("周六", SATURDAY)):
        r = FakeRunner(ledger=full_ledger())
        PROBES.clear()
        rc, out = run(["--apply", "--now", when], r)
        ok("B1 %s --apply 不带 --weekend-ok ⇒ 退出码 3（实际 %s）" % (label, rc), rc == 3, out[-200:])
        ok("B2 %s 被拒时什么都没做（ssh / 子进程 %d 条、账本读 %d 次、判据 %d 次）" % (label, len(r.calls), r.ledger_reads, len(PROBES)),
           not r.calls and r.ledger_reads == 0 and not PROBES)
    rc, out = run(["--now", SUNDAY], FakeRunner())
    ok("B3 周末演练照打步骤、提示要 --weekend-ok", rc == 0 and "--weekend-ok" in out, out[-200:])
    r = FakeRunner(ledger=full_ledger())
    rc, out = run(["--apply", "--weekend-ok", "--now", SUNDAY], r)
    ok("B4 周末带 --weekend-ok ⇒ 放行（退出码 0，ssh %d 条）" % len(r.ssh_cmds()), rc == 0 and r.ssh_cmds(), out[-300:])

    print("=== C 平日 --apply 的顺序 ===")
    r = FakeRunner(ledger=full_ledger())
    PROBES.clear()
    rc, out = run(["--apply", "--now", WEEKDAY], r)
    ok("C0 退出码 0", rc == 0, out[-500:])
    seq = []
    for kind, cmd, data in r.calls:
        if kind == "local":
            seq.append("mig:%s:%s" % (cmd[3], "rehearse" if "--rehearse" in cmd else "apply"))
        elif "flock" in cmd:
            seq.append("lock")
        elif "env-mainsite-beta.part" in cmd:
            seq.append("env")
        elif data is not None and "mainsite-beta/mainsite_gateway.py.part" in cmd:
            seq.append("put-gateway")
        elif cmd.startswith("install -m 644 -o root"):
            seq.append("install-code")
        elif "daemon-reload" in cmd:
            seq.append("unit")
        elif "grep -cxF" in cmd:
            seq.append("caddy-snippet")
        elif cmd.startswith("caddy validate"):
            seq.append("validate")
        elif cmd.startswith("systemctl reload caddy"):
            seq.append("reload")
        elif "systemctl restart" in cmd:
            seq.append("restart")
        elif "MainPID" in cmd and "gateway" in cmd:
            seq.append("procenv-gw")
        elif "MainPID" in cmd:
            seq.append("procenv-poller")
    migs = [x for x in seq if x.startswith("mig:")]
    ok("C1 只上没上过的五份、按清单顺序、每份先演练再上线（%s）" % migs,
       migs == ["mig:20261109a_mainsite_core:rehearse", "mig:20261109a_mainsite_core:apply",
                "mig:20261109b_pet_levels:rehearse", "mig:20261109b_pet_levels:apply",
                "mig:20261109c_raid:rehearse", "mig:20261109c_raid:apply",
                "mig:20261109d_econ_wheel:rehearse", "mig:20261109d_econ_wheel:apply",
                "mig:20261109e_pet_kept:rehearse", "mig:20261109e_pet_kept:apply"])
    ok("C2 账本里已上（sha256 相同）的五份记账迁移一条子进程都没起", not any(x.startswith("mig:20261106") for x in migs))
    ok("C3 账本读了 1 次（= sb_migrate status 的判据）", r.ledger_reads == 1, r.ledger_reads)
    first_srv = min((i for i, x in enumerate(seq) if not x.startswith("mig:")), default=-1)
    ok("C4 迁移全部在裁判机第一条 ssh 之前", first_srv > 0 and all(i < first_srv for i, x in enumerate(seq) if x.startswith("mig:")), seq)
    want = ["lock", "put-gateway", "install-code", "env", "unit", "caddy-snippet", "validate", "reload", "restart",
            "procenv-gw", "procenv-poller"]
    got = [x for x in seq if x in want]
    ok("C5 裁判机段顺序 = 锁 → 传代码 → 装代码 → env → 单元 → Caddy 片段 → validate → reload → 重启 → 读进程环境", got == want, got)
    ok("C6 caddy validate 在 reload 之前、各恰好一次", seq.count("validate") == 1 and seq.count("reload") == 1
       and seq.index("validate") < seq.index("reload"), seq)
    ok("C7 读进程环境在重启之后（网关 + 轮询器两个都读）", seq.index("restart") < seq.index("procenv-gw") < seq.index("procenv-poller"), seq)
    dns_i = [i for i, p in enumerate(PROBES) if p[0] == "dns"]
    http = [p for p in PROBES if p[0] == "http"]
    ok("C8 DNS 判据跑了 1 次、两个子域名都查（%s）" % ((PROBES[dns_i[0]][1] if dns_i else None),),
       len(dns_i) == 1 and set(PROBES[dns_i[0]][1]) == {"arena-beta.turtlearena.xyz", "arena.turtlearena.xyz"})
    ok("C9 HTTPS 回读 5 条（healthz 200 / 两个不带签名 401 / 不带令牌 401 / 404）",
       sorted(p[3] for p in http) == [200, 401, 401, 401, 404] and all(p[2].startswith("https://arena-beta.turtlearena.xyz/") for p in http), http)
    ok("C10 HTTPS 回读与库回读在最后（PROBES 末两类 = http… db）", PROBES and PROBES[-1] == ("db",) and PROBES[0][0] == "dns", PROBES)
    ok("C11 env 写进的是 MAINSITE_BASE / MAINSITE_HOOK_SECRET / MAINSITE_OUTBOX=1（值从环境变量与密钥文件来）",
       r.env.get("MAINSITE_BASE") == BASE and r.env.get("MAINSITE_HOOK_SECRET") == SECRET and r.env.get("MAINSITE_OUTBOX") == "1", sorted(r.env))
    puts = [c for c in r.calls if c[0] == "ssh" and c[2] is not None and ".part" in c[1] and "env-mainsite" not in c[1]]
    ok("C12 传上去的 6 个文件都转成了 LF（标准输入里没有 \\r\\n）", len(puts) == 6 and all(b"\r\n" not in c[2] for c in puts), len(puts))

    print("=== D 密钥不进命令行 / 输出 ===")
    carriers = [c for c in r.calls if c[2] is not None and SECRET.encode() in c[2]]
    ok("D1 密钥只在 1 条 ssh 的标准输入里（写 env 那一步）", len(carriers) == 1 and "env-mainsite-beta.part" in carriers[0][1], len(carriers))
    ok("D2 任何 ssh 命令行 / 本机子进程参数里都没有密钥",
       not any(SECRET in (c[1] if isinstance(c[1], str) else " ".join(c[1])) for c in r.calls))
    ok("D3 打印输出里没有密钥、没有内测主站地址原文", SECRET not in out and BASE not in out, "")

    print("=== E caddy validate 不过 ===")
    r = FakeRunner(ledger=full_ledger(), validate_ok=False)
    rc, out = run(["--apply", "--now", WEEKDAY], r)
    cmds = r.ssh_cmds()
    ok("E1 退出码 1", rc == 1, rc)
    ok("E2 没有 reload caddy、没有重启网关", not any(c.startswith("systemctl reload caddy") for c in cmds)
       and not any("systemctl restart" in c for c in cmds), cmds[-3:])
    ok("E3 跑了还原（从备份拷回 Caddyfile、删片段）", any("RESTORED" in c and "Caddyfile" in c for c in cmds), cmds[-2:])

    print("=== F 读进程环境这一关会红 ===")
    r = FakeRunner(ledger=full_ledger(), fresh=False)
    rc, out = run(["--apply", "--now", WEEKDAY], r)
    ok("F1 进程比 env 文件旧（没重启）⇒ 退出码 1", rc == 1 and "进程比 env 文件旧" in out, out[-300:])
    r = FakeRunner(ledger=full_ledger(), proc_secret="some-other-secret")
    rc, out = run(["--apply", "--now", WEEKDAY], r)
    ok("F2 进程里的密钥与 env 不同 ⇒ 退出码 1、点名 MAINSITE_HOOK_SECRET", rc == 1 and "MAINSITE_HOOK_SECRET" in out, out[-300:])
    ok("F3 F2 的输出里也没有密钥原文", "some-other-secret" not in out and SECRET not in out)

    print("=== G 账本 sha256 不同 ⇒ 停 ===")
    led = full_ledger()
    led["20261106c_econ_state"] = "0" * 64
    r = FakeRunner(ledger=led)
    rc, out = run(["--apply", "--now", WEEKDAY], r)
    ok("G1 退出码 1、一条 ssh / 子进程都没有", rc == 1 and not r.calls, r.calls[:2])

    print("=== H 内测主站地址的出处 ===")
    doc = ("## 7. x\n\n## 8. 上线步骤\n\n1. 内测环境：\n   - 主站内测网站：`http://203.0.113.9:8080`（确认页：`http://203.0.113.9:8080/game/link?code=…`）\n"
           "   - 小游戏调主站：`http://203.0.113.9:8080/api/arena-hook/…`\n\n## 9. 待确认\n- 主站内测网站：`http://wrong.invalid`\n")
    b, src = D.parse_arena_plan(doc)
    ok("H1 §8 解析出根地址（不带结尾斜杠；不吃 §9 里的同名行）", b == "http://203.0.113.9:8080", (b, src))
    b, src = D.parse_arena_plan(doc.replace("小游戏调主站：`http://203.0.113.9:8080", "小游戏调主站：`http://198.51.100.1"))
    ok("H2 「小游戏调主站」与「主站内测网站」不是同一个根 ⇒ 拒", b == "", (b, src))
    b, src = D.beta_mainsite_base({"MAINSITE_BETA_BASE": "http://x.invalid/"})
    ok("H3 环境变量优先、去结尾斜杠", b == "http://x.invalid", b)
    src_text = open(os.path.join(D.REPO, "tools", "mainsite_deploy.py"), encoding="utf-8").read()
    hits = __import__("re").findall(r"https?://(?!127\.0\.0\.1)\d+\.\d+\.\d+\.\d+", src_text)
    ok("H4 部署脚本源码里没有写死 http(s)://<IP> 形式的地址（回环 127.0.0.1 除外）", not hits, hits)

    print("\n%d 条断言, %d 条失败" % (n[0], fails[0]))
    if fails[0] == 0:
        print("ALL OK")
    return 1 if fails[0] else 0


if __name__ == "__main__":
    sys.exit(main())
