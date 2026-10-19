#!/usr/bin/env python3
"""逐帧直播 · 传输运维（方案书 docs/plans/20261019-服务器逐帧直播.md §3 / S4；部署见同目录 README.md）。

只用标准库（Ubuntu 24.04 自带 python3.12）。三个子命令：

  stream_ops.py minver     读 Supabase service_status.min_client_version（只读 GET），生成 Caddy 片段
                           /etc/caddy/turtle-min-version.caddy；内容变了才写、写完 `caddy validate` 过了才
                           `systemctl reload caddy`，验不过就还原旧片段。读不到库 ⇒ 片段不动（沿用上次的最低版本）。
                           systemd timer 每分钟跑一次（root：要写 /etc/caddy、要 reload）。
  stream_ops.py purge      删过期的流目录。口径与库里录像 `purge_old_matches` 逐字同一条：
                           「每周二 00:00 UTC 删掉本周一 00:00 UTC 之前的」⇒ 任意时刻的截止线 =
                           「(现在 − 1 天) 所在 ISO 周的周一 00:00 UTC」。目录的时间取 mtime。
                           另删临时目录里超过 1 天的残留（裁判进程被杀时留下的）。
  stream_ops.py selftest   版本正则对拍：生成的正则 vs 与 SQL `semver_arr` / `client_version_ok` 同口径的
                           Python 参考实现，边界 + 随机共几万条，必须全同。

配置（环境变量；minver 从 /etc/turtle-referee/env 读 SUPABASE_URL / SUPABASE_SERVICE_KEY，★钥匙绝不打印）：
  STREAM_ENV_FILE    默认 /etc/turtle-referee/env
  STREAM_SNIPPET     默认 /etc/caddy/turtle-min-version.caddy
  STREAM_CADDYFILE   默认 /etc/caddy/Caddyfile
  STREAM_ROOT        默认 /var/lib/turtle-referee/streams（对外目录）
  STREAM_TMP         默认 <STREAM_ROOT>-tmp（裁判边算边写的临时目录，不对外）
"""
import datetime as dt
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.request

UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def log(msg: str) -> None:
    print("%s %s" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg), flush=True)


# ─────────────────────── 版本口径（与 SQL 20261019_min_version_gate.sql 同一条） ───────────────────────
_SEMVER_RE = re.compile(r"^[0-9]{1,6}(\.[0-9]{1,6}){0,3}$")


def semver_arr(v):
    """= SQL public.semver_arr：1~4 段、每段 1~6 位数字，补齐 4 段；看不懂 ⇒ None。"""
    s = (v or "").strip()
    if not _SEMVER_RE.match(s):
        return None
    a = [int(x) for x in s.split(".")]
    return a + [0] * (4 - len(a))


def client_ok(cv, mv) -> bool:
    """= SQL public.client_version_ok：最低版本看不懂 ⇒ 放行；客户端缺 / 看不懂 ⇒ 按 0.0.0.0。"""
    m = semver_arr(mv)
    if m is None:
        return True
    return (semver_arr(cv) or [0, 0, 0, 0]) >= m


# ─────────────────────── 生成「版本 ≥ 最低版本」的 RE2 正则 ───────────────────────
# ★Caddyfile 里的 `{…}` 会被当占位符，所以正则里**不用花括号量词**：重复一律展开成 `[0-9]` / `0?` 串。

def _zeros_opt(n: int) -> str:
    return "0?" * n


def _eq(v: int) -> str:
    """一段数字 == v（允许前导零，总长 ≤ 6）。"""
    s = str(v)
    return _zeros_opt(6 - len(s)) + s


def _gt(v: int) -> str:
    """一段数字 > v（允许前导零，总长 ≤ 6）。v = 999999 ⇒ 空串（不可能）。"""
    s = str(v)
    L = len(s)
    alts = []
    for L2 in range(L + 1, 7):            # 位数更多
        alts.append(_zeros_opt(6 - L2) + "[1-9]" + "[0-9]" * (L2 - 1))
    for i, ch in enumerate(s):            # 同位数：前 i 位相同、第 i 位更大
        d = int(ch)
        if d == 9:
            continue
        lo = d + 1
        cls = str(lo) if lo == 9 else "[%d-9]" % lo
        alts.append(_zeros_opt(6 - L) + s[:i] + cls + "[0-9]" * (L - i - 1))
    return "(?:" + "|".join(alts) + ")" if alts else ""


_ANY = "[0-9]" + "[0-9]?" * 5


def version_regex(min_version):
    """返回匹配「放行的版本串」的整串正则；最低版本看不懂或全 0 ⇒ None（= 不设闸，与 SQL 同）。"""
    m = semver_arr(min_version)
    if m is None or m == [0, 0, 0, 0]:
        return None
    alts = []
    # ① 前 i 段相等、第 i 段更大、其后随意（第 i 段必须写出来：没写 = 0，不可能 > m_i）
    for i in range(4):
        g = _gt(m[i])
        if not g:
            continue
        pre = "".join(_eq(m[j]) + r"\." for j in range(i))
        alts.append(pre + g + (r"(?:\." + _ANY + ")?") * (3 - i))
    # ② 写出来的 k 段全相等，没写的段在最低版本里都是 0
    for k in range(1, 5):
        if all(m[j] == 0 for j in range(k, 4)):
            alts.append(r"\.".join(_eq(m[j]) for j in range(k)))
    return "^(?:" + "|".join(alts) + ")$"


def selftest() -> int:
    rnd = random.Random(20261019)
    mins = ["0.20.1", "0.20.0", "0.19.571", "1", "0.0.1", "0.0.0.1", "9.9.9", "0.20", "1.0.0.0",
            "999999.999999.999999.999999", "000.020.001", "0.9.10", "10.0.0", "0.0.0", "", "abc", "1.2.3.4.5"]
    for _ in range(300):
        k = rnd.randint(1, 4)
        mins.append(".".join(str(rnd.choice([0, 0, 1, 9, 10, 19, 20, 99, 100, 571, 999999, rnd.randint(0, 999999)]))
                             for _ in range(k)))
    n = bad = 0
    for mv in mins:
        rx = version_regex(mv)
        pat = re.compile(rx) if rx else None
        m = semver_arr(mv)
        cands = ["", " ", "0.20.1 ", "abc", "0.20.1-beta", "1.2.3.4.5", "1..2", ".1", "0000001.0", "v0.20.1"]
        if m:
            for i in range(4):
                for dlt in (-1, 0, 1):
                    t = list(m)
                    t[i] = max(0, min(999999, t[i] + dlt))
                    for k in range(1, 5):
                        parts = [str(x) for x in t[:k]]
                        cands.append(".".join(parts))
                        cands.append(".".join(p.zfill(min(6, len(p) + 1)) for p in parts))
        for _ in range(150):
            k = rnd.randint(1, 4)
            cands.append(".".join(str(rnd.randint(0, 30) if rnd.random() < .7 else rnd.randint(0, 999999)) for _ in range(k)))
        for cv in cands:
            want = client_ok(cv, mv)
            got = True if pat is None else bool(pat.match(cv.strip()))
            n += 1
            if want != got:
                bad += 1
                if bad <= 20:
                    print("MISMATCH min=%r client=%r want=%s got=%s" % (mv, cv, want, got))
    # 分母 + 两条正反对照（证明这把尺子会红）
    rx = re.compile(version_regex("0.20.1"))
    probes = {"0.20.1": True, "0.20.2": True, "0.21": True, "1.0.0": True, "0.20.0": False, "0.19.999": False, "": False}
    for cv, want in probes.items():
        if bool(rx.match(cv)) != want:
            bad += 1
            print("PROBE FAIL %r want %s" % (cv, want))
    print("selftest: %d 条对拍, %d 条不一致" % (n, bad))
    return 0 if (bad == 0 and n > 10000) else 1


# ─────────────────────── minver：service_status → Caddy 片段 ───────────────────────

def _read_env_file(path: str) -> dict:
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def fetch_min_version() -> str:
    cfg = _read_env_file(os.environ.get("STREAM_ENV_FILE", "/etc/turtle-referee/env"))
    url = cfg["SUPABASE_URL"].rstrip("/") + "/rest/v1/service_status?id=eq.1&select=min_client_version"
    key = cfg["SUPABASE_SERVICE_KEY"]
    req = urllib.request.Request(url, method="GET", headers={
        "apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        rows = json.loads(r.read() or b"[]")
    if not isinstance(rows, list) or not rows:
        raise ValueError("service_status 没有 id=1 那一行")
    return str(rows[0].get("min_client_version") or "")


def render_snippet(min_version: str) -> str:
    rx = version_regex(min_version)
    head = ("# 由 stream_ops.py minver 生成（每分钟从 service_status.min_client_version 读一次）。别手改。\n"
            "# min_client_version = %s\n" % json.dumps(min_version))
    if rx is None:
        # 与 SQL 同：最低版本看不懂 / 全 0 ⇒ 不设闸
        return head + "# 最低版本看不懂或为 0 ⇒ 不设闸\n@stream_old expression `false`\n"
    body = json.dumps({"message": "update_required", "min_client_version": min_version}, ensure_ascii=False)
    return (head +
            "@stream_old {\n"
            "\tpath /streams/*\n"
            "\tnot header_regexp X-Client-Version `%s`\n"
            "}\n"
            "header @stream_old Cache-Control no-store\n"
            "header @stream_old X-Min-Client-Version `%s`\n"
            "respond @stream_old `%s` 426\n") % (rx, min_version, body)


def cmd_minver() -> int:
    snip = os.environ.get("STREAM_SNIPPET", "/etc/caddy/turtle-min-version.caddy")
    caddyfile = os.environ.get("STREAM_CADDYFILE", "/etc/caddy/Caddyfile")
    try:
        mv = fetch_min_version()
    except Exception as ex:   # 读不到 ⇒ 片段不动（沿用上次）；只打异常类型，免得把 URL / 头带出来
        log("WARN 读不到 service_status（%s），沿用上次的最低版本" % type(ex).__name__)
        return 1
    new = render_snippet(mv)
    old = None
    if os.path.exists(snip):
        with open(snip, encoding="utf-8") as f:
            old = f.read()
    if new == old:
        return 0
    tmp = snip + ".new"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(new)
    os.chmod(tmp, 0o644)
    os.replace(tmp, snip)
    v = subprocess.run(["caddy", "validate", "--config", caddyfile, "--adapter", "caddyfile"],
                       capture_output=True, text=True)
    if v.returncode != 0:
        if old is not None:
            with open(snip, "w", encoding="utf-8", newline="\n") as f:
                f.write(old)
        else:
            os.remove(snip)
        log("ERROR 新片段 caddy validate 不过，已还原：%s" % (v.stderr or v.stdout)[-400:])
        return 1
    r = subprocess.run(["systemctl", "reload", "caddy"], capture_output=True, text=True)
    log("min_client_version → %r（片段已更新，reload rc=%d）" % (mv, r.returncode))
    return 0 if r.returncode == 0 else 1


# ─────────────────────── purge：保留期到了就删 ───────────────────────

def purge_cutoff(now: dt.datetime) -> dt.datetime:
    """(now − 1 天) 所在 ISO 周的周一 00:00 UTC。周二 00:00 起 = 本周一；周一全天 = 上周一。"""
    d = (now - dt.timedelta(days=1)).date()
    monday = d - dt.timedelta(days=d.weekday())
    return dt.datetime(monday.year, monday.month, monday.day, tzinfo=dt.timezone.utc)


def cmd_purge(dry: bool = False) -> int:
    root = os.environ.get("STREAM_ROOT", "/var/lib/turtle-referee/streams")
    tmp_root = os.environ.get("STREAM_TMP", root.rstrip("/") + "-tmp")
    now = dt.datetime.now(dt.timezone.utc)
    cut = purge_cutoff(now).timestamp()
    n_del = n_keep = 0
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            p = os.path.join(root, name)
            if not os.path.isdir(p) or not UUID_RE.match(name):
                continue                      # 只动 UUID 命名的局目录，别的一概不碰
            if os.stat(p).st_mtime < cut:
                n_del += 1
                if not dry:
                    shutil.rmtree(p, ignore_errors=True)
            else:
                n_keep += 1
    n_tmp = 0
    if os.path.isdir(tmp_root):
        for name in os.listdir(tmp_root):
            p = os.path.join(tmp_root, name)
            if os.path.isdir(p) and UUID_RE.match(name) and os.stat(p).st_mtime < now.timestamp() - 86400:
                n_tmp += 1
                if not dry:
                    shutil.rmtree(p, ignore_errors=True)
    log("purge%s: 截止 %s ⇒ 删 %d 局、留 %d 局、删临时残留 %d" % (
        "(dry)" if dry else "", purge_cutoff(now).isoformat(), n_del, n_keep, n_tmp))
    return 0


def main() -> int:
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    if a[0] == "minver":
        return cmd_minver()
    if a[0] == "purge":
        return cmd_purge(dry="--dry-run" in a)
    if a[0] == "selftest":
        return selftest()
    if a[0] == "regex":           # 运维查看：stream_ops.py regex 0.20.1
        print(version_regex(a[1] if len(a) > 1 else ""))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
