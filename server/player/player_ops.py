#!/usr/bin/env python3
"""网页录像播放器 · 服务器上按版本装 / 清（2026-11-08 · 方案书 docs/plans/20261105c-主站对接偷袭.md §4.7；部署见同目录 README.md）。

只用标准库（Ubuntu 24.04 自带 python3.12）。由 tools/deploy.py --only player 上传后调用，也可手动跑：

  player_ops.py install <prod|beta> <版本> <产物.zip> [--entry <入口页.html>]
        暂存目录解包 → 核文件（index.html / .js / .wasm / .pck 与 webplayer.json 里的版本 = <版本>）→
        原子换入 <根>/<版本>/（同版本已在 ⇒ 旧的挪到 <PLAYER_PREV>/）→ 换入口页 <根>/index.html → 记清单 versions.json → prune。
  player_ops.py prune <prod|beta> [--dry-run]
        删不再需要的版本目录。★一个版本只要满足下面任何一条就留着（约定 §4.4「保留期内各版本的录像都要能播」）：
          ① 是最新的 KEEP_NEWEST 个版本之一；
          ② 流目录里还有这个版本录的局（任一 <流根>/<对局号>/end.json 的 client_version = 它）；
          ③ 被下一个版本取代还不到 RETAIN_DAYS 天（偷袭局保留 30 天 + 余量；清单里没有取代时刻 = 还没被取代）。
  player_ops.py status <prod|beta>     打印清单与目录（只读）
  player_ops.py selftest               在临时目录里把 install / prune 的判据各走一遍（门禁 tools/web_player_audit.py 调）

目录（环境变量可改，门禁的自测靠它指到临时目录）：
  PLAYER_ROOT_PROD  默认 /var/www/turtle-player/prod     PLAYER_ROOT_BETA  默认 /var/www/turtle-player/beta
  STREAM_ROOT_PROD  默认 /var/lib/turtle-referee/streams STREAM_ROOT_BETA  默认 /var/lib/turtle-referee-beta/streams
  PLAYER_STAGING    默认 /var/www/turtle-player/.staging  PLAYER_PREV       默认 /var/www/turtle-player/.prev
★不放在 /opt/turtle*/ 下：referee_poller.py 的 discover_versions 把那一层带 project.godot 的子目录都当版本（server/deploy/README.md）。
"""
import datetime as dt
import json
import os
import re
import shutil
import sys
import tempfile
import time
import zipfile

KEEP_NEWEST = 3
RETAIN_DAYS = 35
VER_RE = re.compile(r"^[0-9]{1,6}(\.[0-9]{1,6}){1,3}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
NEED = ("index.html", "index.js", "index.wasm", "index.pck", "webplayer.json")
MANIFEST = "versions.json"


def log(msg):
    print("[player_ops] " + msg, flush=True)


def ver_key(v):
    return tuple(int(x) for x in v.split("."))


def roots(env):
    if env not in ("prod", "beta"):
        raise SystemExit("环境只能是 prod / beta：%r" % env)
    up = env.upper()
    base = os.environ.get("PLAYER_ROOT_" + up, "/var/www/turtle-player/" + env)
    streams = os.environ.get("STREAM_ROOT_" + up,
                             "/var/lib/turtle-referee/streams" if env == "prod" else "/var/lib/turtle-referee-beta/streams")
    staging = os.environ.get("PLAYER_STAGING", "/var/www/turtle-player/.staging")
    prev = os.environ.get("PLAYER_PREV", "/var/www/turtle-player/.prev")
    return base, streams, staging, prev


def read_manifest(base):
    try:
        with open(os.path.join(base, MANIFEST), encoding="utf-8") as f:
            m = json.load(f)
        return m if isinstance(m, dict) else {}
    except (OSError, ValueError):
        return {}


def write_manifest(base, m):
    tmp = os.path.join(base, MANIFEST + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, os.path.join(base, MANIFEST))


def installed_versions(base):
    if not os.path.isdir(base):
        return []
    return sorted((n for n in os.listdir(base) if VER_RE.match(n) and os.path.isdir(os.path.join(base, n))), key=ver_key)


def stream_versions(streams):
    """流目录里还有局的那些版本（读每一局的 end.json）。读不到的局不算（还在写 / 坏了）。"""
    out = set()
    if not os.path.isdir(streams):
        return out
    for name in os.listdir(streams):
        if not UUID_RE.match(name):
            continue
        try:
            with open(os.path.join(streams, name, "end.json"), encoding="utf-8") as f:
                v = str(json.load(f).get("client_version", ""))
        except (OSError, ValueError, AttributeError):
            continue
        if VER_RE.match(v):
            out.add(v)
    return out


def prune_plan(installed, manifest, in_streams, now):
    """纯函数：返回 [(版本, 留 / 删, 原因)]。now = UNIX 秒。"""
    order = sorted(installed, key=ver_key)
    newest = set(order[-KEEP_NEWEST:])
    plan = []
    for v in order:
        sup = (manifest.get(v) or {}).get("superseded_at")
        if v in newest:
            plan.append((v, "keep", "最新 %d 个之一" % KEEP_NEWEST))
        elif v in in_streams:
            plan.append((v, "keep", "流目录里还有这一版的局"))
        elif not isinstance(sup, (int, float)):
            plan.append((v, "keep", "清单里没有被取代的时刻"))
        elif now - sup < RETAIN_DAYS * 86400:
            plan.append((v, "keep", "被取代 %.1f 天（< %d 天）" % ((now - sup) / 86400.0, RETAIN_DAYS)))
        else:
            plan.append((v, "drop", "被取代 %.1f 天、流目录里没有它的局" % ((now - sup) / 86400.0)))
    return plan


def cmd_prune(env, dry=False, now=None):
    base, streams, _, _ = roots(env)
    now = time.time() if now is None else now
    plan = prune_plan(installed_versions(base), read_manifest(base), stream_versions(streams), now)
    m = read_manifest(base)
    for v, act, why in plan:
        log("%s %s：%s" % ("删" if act == "drop" else "留", v, why))
        if act == "drop" and not dry:
            shutil.rmtree(os.path.join(base, v), ignore_errors=True)
            m.pop(v, None)
    if not dry and os.path.isdir(base):
        write_manifest(base, m)
    return 0


def _check_unpacked(d, version):
    miss = [n for n in NEED if not os.path.isfile(os.path.join(d, n))]
    if miss:
        return "缺文件：%s" % ", ".join(miss)
    try:
        with open(os.path.join(d, "webplayer.json"), encoding="utf-8") as f:
            stamp = json.load(f)
    except (OSError, ValueError):
        return "webplayer.json 读不了"
    if str(stamp.get("version", "")) != version:
        return "产物版本 %r ≠ %s" % (stamp.get("version"), version)
    if os.path.getsize(os.path.join(d, "index.wasm")) < 1000000 or os.path.getsize(os.path.join(d, "index.pck")) < 1000000:
        return "index.wasm / index.pck 小得不像导出产物"
    return ""


def cmd_install(env, version, zpath, entry=None, now=None):
    if not VER_RE.match(version):
        raise SystemExit("版本号不像样：%r" % version)
    base, _, staging, prev = roots(env)
    now = time.time() if now is None else now
    os.makedirs(base, exist_ok=True)
    os.makedirs(staging, exist_ok=True)
    stage = tempfile.mkdtemp(prefix="%s-%s-" % (env, version), dir=staging)
    try:
        with zipfile.ZipFile(zpath) as z:
            for n in z.namelist():
                if n.startswith("/") or ".." in n.split("/") or "/" in n.rstrip("/"):
                    raise SystemExit("产物里有子目录 / 越界路径：%r" % n)
            z.extractall(stage)
        why = _check_unpacked(stage, version)
        if why:
            raise SystemExit("产物不对（%s）⇒ 不换入，线上没变" % why)
        os.chmod(stage, 0o755)
        dst = os.path.join(base, version)
        if os.path.isdir(dst):
            os.makedirs(prev, exist_ok=True)
            old = os.path.join(prev, "%s-%s.prev-%s" % (env, version, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(now))))
            os.rename(dst, old)
            log("同版本已在 ⇒ 旧目录挪到 %s" % old)
        os.rename(stage, dst)
        stage = ""
        log("换入 %s" % dst)
    finally:
        if stage and os.path.isdir(stage):
            shutil.rmtree(stage, ignore_errors=True)
    if entry:
        tmp = os.path.join(base, "index.html.tmp")
        shutil.copyfile(entry, tmp)
        os.chmod(tmp, 0o644)
        os.replace(tmp, os.path.join(base, "index.html"))
        log("入口页已换")
    m = read_manifest(base)
    for v in list(m):
        if v != version and ver_key(v) < ver_key(version) and not isinstance(m[v].get("superseded_at"), (int, float)):
            m[v]["superseded_at"] = int(now)
    m.setdefault(version, {})["installed_at"] = int(now)
    m[version].pop("superseded_at", None)
    write_manifest(base, m)
    return cmd_prune(env, now=now)


def cmd_status(env):
    base, streams, _, _ = roots(env)
    log("根 %s · 入口页 %s" % (base, "在" if os.path.isfile(os.path.join(base, "index.html")) else "没有"))
    log("清单 %s" % json.dumps(read_manifest(base), ensure_ascii=False, sort_keys=True))
    log("目录 %s · 流目录里的版本 %s" % (installed_versions(base), sorted(stream_versions(streams), key=ver_key)))
    return 0


# ─────────────────────────────── 自测 ───────────────────────────────

def _fake_build(d, version, big=True):
    os.makedirs(d, exist_ok=True)
    for n in ("index.html", "index.js"):
        with open(os.path.join(d, n), "w") as f:
            f.write("x")
    for n in ("index.wasm", "index.pck"):
        with open(os.path.join(d, n), "wb") as f:
            f.write(b"\0" * (1100000 if big else 10))
    with open(os.path.join(d, "webplayer.json"), "w") as f:
        json.dump({"version": version}, f)


def _zip(src, out):
    with zipfile.ZipFile(out, "w") as z:
        for n in sorted(os.listdir(src)):
            z.write(os.path.join(src, n), arcname=n)


def selftest():
    bad = []

    def ok(name, cond):
        print("  [%s] %s" % ("PASS" if cond else "FAIL", name))
        if not cond:
            bad.append(name)

    day = 86400
    now = 1_800_000_000
    vs = ["0.22.7", "0.22.8", "0.22.9", "0.23.0", "0.23.1"]
    man = {"0.22.7": {"superseded_at": now - 60 * day}, "0.22.8": {"superseded_at": now - 10 * day},
           "0.22.9": {"superseded_at": now - 9 * day}, "0.23.0": {"superseded_at": now - 2 * day}, "0.23.1": {}}
    plan = dict((v, a) for v, a, _ in prune_plan(vs, man, set(), now))
    ok("超过保留期、流里没有局、不在最新 3 个 ⇒ 删（0.22.7）", plan["0.22.7"] == "drop")
    ok("被取代 10 天 ⇒ 留（0.22.8）", plan["0.22.8"] == "keep")
    ok("最新 3 个一律留", all(plan[v] == "keep" for v in vs[-3:]))
    plan2 = dict((v, a) for v, a, _ in prune_plan(vs, man, {"0.22.7"}, now))
    ok("★流目录里还有 0.22.7 的局 ⇒ 留（保留期内的录像必须能播）", plan2["0.22.7"] == "keep")
    man3 = dict(man)
    man3["0.22.7"] = {}
    ok("清单里没有取代时刻 ⇒ 留（不猜）", dict((v, a) for v, a, _ in prune_plan(vs, man3, set(), now))["0.22.7"] == "keep")
    ok("被取代恰好 %d 天整 ⇒ 删；差一秒 ⇒ 留" % RETAIN_DAYS,
       prune_plan(["0.1.0", "0.2.0", "0.3.0", "0.4.0"], {"0.1.0": {"superseded_at": now - RETAIN_DAYS * day}}, set(), now)[0][1] == "drop"
       and prune_plan(["0.1.0", "0.2.0", "0.3.0", "0.4.0"], {"0.1.0": {"superseded_at": now - RETAIN_DAYS * day + 1}}, set(), now)[0][1] == "keep")
    ok("版本按数值排（0.22.10 比 0.22.9 新）", prune_plan(["0.22.9", "0.22.10", "0.23.0", "0.3.0"], {}, set(), now)[0][0] == "0.3.0")

    with tempfile.TemporaryDirectory() as td:
        os.environ["PLAYER_ROOT_PROD"] = os.path.join(td, "prod")
        os.environ["STREAM_ROOT_PROD"] = os.path.join(td, "streams")
        os.environ["PLAYER_STAGING"] = os.path.join(td, ".staging")
        os.environ["PLAYER_PREV"] = os.path.join(td, ".prev")
        entry = os.path.join(td, "entry.html")
        with open(entry, "w") as f:
            f.write("<!doctype html>")
        mid = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
        os.makedirs(os.path.join(td, "streams", mid))
        with open(os.path.join(td, "streams", mid, "end.json"), "w") as f:
            json.dump({"client_version": "0.1.0", "chunks": 3}, f)
        t = now - 100 * day
        for i, v in enumerate(["0.1.0", "0.2.0", "0.3.0", "0.4.0", "0.5.0"]):
            src = os.path.join(td, "b" + v)
            _fake_build(src, v)
            _zip(src, src + ".zip")
            cmd_install("prod", v, src + ".zip", entry, now=t + i * 20 * day)
        got = installed_versions(os.path.join(td, "prod"))
        ok("装了 5 版、0.2.0 被取代 40 天(> 35)且流里没有 ⇒ 清掉；0.1.0 流里还有局 ⇒ 留", got == ["0.1.0", "0.3.0", "0.4.0", "0.5.0"])
        ok("入口页换上了", os.path.isfile(os.path.join(td, "prod", "index.html")))
        m = read_manifest(os.path.join(td, "prod"))
        ok("清单：最新版没有取代时刻，旧版有", "superseded_at" not in m.get("0.5.0", {}) and isinstance(m.get("0.4.0", {}).get("superseded_at"), int))
        src = os.path.join(td, "bad")
        _fake_build(src, "0.6.0")
        os.remove(os.path.join(src, "index.pck"))
        _zip(src, src + ".zip")
        refused = False
        try:
            cmd_install("prod", "0.6.0", src + ".zip", entry, now=now)
        except SystemExit:
            refused = True
        ok("★缺 index.pck ⇒ 拒绝换入、线上目录不变、暂存目录不留",
           refused and installed_versions(os.path.join(td, "prod")) == got and not os.listdir(os.path.join(td, ".staging")))
        src = os.path.join(td, "wrongver")
        _fake_build(src, "0.7.0")
        _zip(src, src + ".zip")
        refused = False
        try:
            cmd_install("prod", "0.7.1", src + ".zip", entry, now=now)
        except SystemExit:
            refused = True
        ok("★产物里的版本 ≠ 要装的版本 ⇒ 拒绝", refused and "0.7.1" not in installed_versions(os.path.join(td, "prod")))
        src = os.path.join(td, "b0.5.0")
        cmd_install("prod", "0.5.0", src + ".zip", entry, now=now)
        ok("同版本重装 ⇒ 旧目录挪进 .prev", len(os.listdir(os.path.join(td, ".prev"))) == 1)
        for k in ("PLAYER_ROOT_PROD", "STREAM_ROOT_PROD", "PLAYER_STAGING", "PLAYER_PREV"):
            os.environ.pop(k, None)
    print("ALL OK" if not bad else "FAILED %d" % len(bad))
    return 0 if not bad else 1


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # Windows 控制台是 GBK
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    if a[0] == "install" and len(a) >= 4:
        entry = a[a.index("--entry") + 1] if "--entry" in a else None
        return cmd_install(a[1], a[2], a[3], entry)
    if a[0] == "prune" and len(a) >= 2:
        return cmd_prune(a[1], dry="--dry-run" in a)
    if a[0] == "status" and len(a) >= 2:
        return cmd_status(a[1])
    if a[0] == "selftest":
        return selftest()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
