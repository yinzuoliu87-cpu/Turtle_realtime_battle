# -*- coding: utf-8 -*-
"""裁判机外部探活（2026-10-26 · 方案书 docs/plans/20261026-裁判机外部监控.md）。

由来：10-25 裁判机整机断网约 79 分钟没人知道 —— 机器上的健康检查跑在同一台机器上，连不上库、也没有对外通知。
这里从**外面**（GitHub Actions `referee-watch.yml`，每 10 分钟）看两个独立信号：

  ① https://stream.turtlearena.xyz/healthz      —— 整机断网时打不开
  ② 正式服 rpc `referee_health()`（匿名可调）     —— 最新一次裁判心跳距今多少秒

结论与动作（`decide()`，与方案书 §4 那张表一一对应）：
  ok             两个都正常                              —— 无
  worker_down    healthz 正常、心跳旧了                  —— 报警，不重启（程序挂了、机器在）
  edge_down      healthz 打不开、心跳新鲜                —— 报警，不重启（只有 Caddy / 直播口）
  suspect        healthz 打不开、心跳 300~600 秒         —— 报警，不重启（还说不准）
  machine_down   healthz 打不开、心跳 > 600 秒 / 没有    —— 隔 RECHECK_SEC 复查，仍是 ⇒ 软重启（限频）+ 报警
  blind          读不到心跳（库连不上 / 426 / 函数没了） —— 报警，不重启（监控自己瞎了）

报警 = 进程退出码 1 ⇒ GitHub 给工作流的主人发失败邮件；Job Summary 写清哪项失败、有没有自动重启。
重启 = Hetzner `POST /servers/{id}/actions/reboot`（软重启，10-25 手工用过同一个接口）。
  只在 machine_down 复查仍成立时；最近 REBOOT_COOLDOWN_SEC 内有过 reboot / reset / start ⇒ 不再重启。
  没有 HCLOUD_TOKEN（仓库 Secrets 没填）⇒ 只报警。

  python tools/referee_watch.py              探活（CI 用）
  python tools/referee_watch.py --no-reboot  只看不动
  python tools/referee_watch.py --selftest   量 decide() / 限频的全部分支（不联网）
"""
import argparse
import datetime
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEALTHZ = "https://stream.turtlearena.xyz/healthz"
SERVER_ID = 171098941
STALE_SEC = 300            # 心跳超过它 ⇒ 不算新鲜
DEAD_SEC = 600             # healthz 打不开 + 心跳超过它 ⇒ 整机失联
RECHECK_SEC = 180          # 失联后隔多久复查一次
REBOOT_COOLDOWN_SEC = 3600
REBOOT_COMMANDS = {"reboot_server", "reset_server", "start_server", "poweron_server"}

# 不走本机代理（memory fb-local-proxy-corrupts-post-body: 本机代理会改写 POST body）
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def read_project():
    """正式服地址 / 公开 key / 当前版本 —— 都从 project.godot 读(不带 .beta_server 后缀的那一组)。"""
    s = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    url = re.search(r'^supabase_url="([^"]+)"', s, re.M).group(1)
    key = re.search(r'^supabase_anon_key="([^"]+)"', s, re.M).group(1)
    ver = re.search(r'^config/version="([^"]+)"', s, re.M).group(1)
    return url, key, ver


def probe_healthz(tries=2):
    for i in range(tries):
        try:
            with OPENER.open(urllib.request.Request(HEALTHZ, method="GET"), timeout=15) as r:
                if r.status == 200:
                    return True
        except Exception:
            pass
        if i + 1 < tries:
            time.sleep(5)
    return False


def probe_health(url, key, ver):
    """rpc referee_health() → dict;读不到返回 None。"""
    req = urllib.request.Request(url.rstrip("/") + "/rest/v1/rpc/referee_health", data=b"{}", method="POST", headers={
        "apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json",
        "X-Client-Version": ver})
    try:
        with OPENER.open(req, timeout=20) as r:
            d = json.loads(r.read().decode("utf-8"))
            return d if isinstance(d, dict) else None
    except Exception as e:  # noqa: BLE001
        print("  读心跳失败: %s" % e)
        return None


def decide(healthz_ok, h):
    """纯函数: 两个信号 → 结论。见文件头那张表。"""
    if not isinstance(h, dict):
        return "blind"
    sec = h.get("freshest_sec")
    fresh = sec is not None and int(sec) <= STALE_SEC and int(h.get("fresh_workers") or 0) >= 1
    if healthz_ok:
        return "ok" if fresh else "worker_down"
    if fresh:
        return "edge_down"
    if sec is None or int(sec) > DEAD_SEC:
        return "machine_down"
    return "suspect"


def _ts(s):
    return datetime.datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()


def cooldown_blocks(actions, now):
    """纯函数: Hetzner 最近的 actions 里, REBOOT_COOLDOWN_SEC 内有没有重启类动作。"""
    for a in actions or []:
        if str(a.get("command")) in REBOOT_COMMANDS and a.get("started"):
            if now - _ts(a["started"]) < REBOOT_COOLDOWN_SEC:
                return True
    return False


def hcloud(token, method, path):
    req = urllib.request.Request("https://api.hetzner.cloud/v1" + path, method=method,
                                 data=(b"{}" if method == "POST" else None),
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with OPENER.open(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def summary(lines):
    p = os.environ.get("GITHUB_STEP_SUMMARY")
    if p:
        with open(p, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


WORDS = {
    "ok": "正常",
    "worker_down": "裁判程序心跳停了，但机器能连上（没重启，去看 journalctl -u turtle-referee）",
    "edge_down": "直播口打不开，但裁判心跳正常（没重启，去看 caddy）",
    "suspect": "直播口打不开、心跳 5~10 分钟没更新（还说不准，没重启）",
    "machine_down": "整机失联（直播口打不开 + 心跳超过 10 分钟）",
    "blind": "读不到心跳（数据库 / 版本闸 / 探活函数出问题），没重启",
}


def run(no_reboot):
    url, key, ver = read_project()
    hz = probe_healthz()
    h = probe_health(url, key, ver)
    v = decide(hz, h)
    print("healthz=%s health=%s ⇒ %s" % (hz, json.dumps(h, ensure_ascii=False), v))
    lines = ["## 裁判机探活", "", "- 直播口 healthz：%s" % ("200" if hz else "打不开"),
             "- 心跳：%s" % (json.dumps(h, ensure_ascii=False) if h else "读不到"), "- 结论：**%s**" % WORDS[v]]
    if v == "machine_down":
        print("  失联 ⇒ %d 秒后复查" % RECHECK_SEC)
        time.sleep(RECHECK_SEC)
        hz2 = probe_healthz()
        h2 = probe_health(url, key, ver)
        v = decide(hz2, h2)
        print("复查: healthz=%s health=%s ⇒ %s" % (hz2, json.dumps(h2, ensure_ascii=False), v))
        lines.append("- 复查（%d 秒后）：**%s**" % (RECHECK_SEC, WORDS[v]))
        if v == "machine_down":
            token = os.environ.get("HCLOUD_TOKEN", "").strip()
            if no_reboot:
                lines.append("- 自动重启：没做（--no-reboot）")
            elif not token:
                lines.append("- 自动重启：没做（仓库 Secrets 没填 HCLOUD_TOKEN）")
            else:
                acts = hcloud(token, "GET", "/servers/%d/actions?sort=id:desc&per_page=10" % SERVER_ID).get("actions", [])
                if cooldown_blocks(acts, time.time()):
                    lines.append("- 自动重启：没做（%d 分钟内已经重启过一次）" % (REBOOT_COOLDOWN_SEC // 60))
                else:
                    a = hcloud(token, "POST", "/servers/%d/actions/reboot" % SERVER_ID).get("action", {})
                    lines.append("- 自动重启：**已软重启**（Hetzner action %s，%s）" % (a.get("id"), a.get("status")))
    for l in lines:
        print(l)
    summary(lines)
    return 0 if v == "ok" else 1


def selftest():
    bad = []

    def t(name, got, want):
        ok = got == want
        print(("  [ok]   " if ok else "  [FAIL] ") + "%s ⇒ %r（应 %r）" % (name, got, want))
        if not ok:
            bad.append(name)

    H = lambda sec, n=4: {"freshest_sec": sec, "fresh_workers": n, "pending": 0, "oldest_pending_sec": 0}
    t("① healthz 正常 + 心跳 2 秒", decide(True, H(2)), "ok")
    t("① 边界: 心跳正好 STALE_SEC 秒仍算新鲜", decide(True, H(STALE_SEC)), "ok")
    t("② healthz 正常 + 心跳 STALE_SEC+1 秒", decide(True, H(STALE_SEC + 1)), "worker_down")
    t("② healthz 正常 + 心跳新但 0 个新鲜线程", decide(True, H(5, 0)), "worker_down")
    t("② healthz 正常 + 一行心跳都没有(null)", decide(True, H(None, 0)), "worker_down")
    t("③ healthz 打不开 + 心跳新鲜", decide(False, H(3)), "edge_down")
    t("④ healthz 打不开 + 心跳在 STALE~DEAD 之间", decide(False, H(DEAD_SEC)), "suspect")
    t("⑤ healthz 打不开 + 心跳 DEAD_SEC+1 秒", decide(False, H(DEAD_SEC + 1)), "machine_down")
    t("⑤ healthz 打不开 + 心跳 4742 秒(10-25 实况)", decide(False, H(4742, 0)), "machine_down")
    t("⑤ healthz 打不开 + 一行心跳都没有", decide(False, H(None, 0)), "machine_down")
    t("⑥ 读不到心跳(None) + healthz 正常", decide(True, None), "blind")
    t("⑥ 读不到心跳(None) + healthz 打不开 ⇒ 不当失联(不重启)", decide(False, None), "blind")
    now = _ts("2026-10-26T12:00:00Z")
    t("限频: 30 分钟前软重启过 ⇒ 挡住", cooldown_blocks([{"command": "reboot_server", "started": "2026-10-26T11:30:00Z"}], now), True)
    t("限频: 61 分钟前重启过 ⇒ 放行", cooldown_blocks([{"command": "reboot_server", "started": "2026-10-26T10:59:00Z"}], now), False)
    t("限频: 10 分钟前是别的动作(change_server_type) ⇒ 放行",
      cooldown_blocks([{"command": "change_server_type", "started": "2026-10-26T11:50:00Z"}], now), False)
    t("限频: 10 分钟前 reset_server ⇒ 挡住", cooldown_blocks([{"command": "reset_server", "started": "2026-10-26T11:50:00Z"}], now), True)
    print("ALL OK" if not bad else "FAILED %d 条" % len(bad))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-reboot", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    return selftest() if a.selftest else run(a.no_reboot)


if __name__ == "__main__":
    sys.exit(main())
