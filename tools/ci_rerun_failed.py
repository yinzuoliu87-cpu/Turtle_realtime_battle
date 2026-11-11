# -*- coding: utf-8 -*-
"""tools/ci_rerun_failed.py — 只重跑某次 CI 里红的那几片(GitHub「Re-run failed jobs」), 可选等结论。

用途: CI 偶发红(真线程 / 真时间的自测在繁忙的 runner 上超时), 本机复现不出、代码没改 ⇒ 不必整轮重推,
  只重跑红的那片; 汇总 + promote 跟着重跑, 全绿照常快进 main(重跑的仍是原来那次 push 事件)。
  CLAUDE.md §2「CI 红了不整轮重来」。先在本机确认复现不出再用; 能复现就去修, 别拿重跑掩盖。

用法:
  python tools/ci_rerun_failed.py <run_id>            # 触发重跑, 立刻返回
  python tools/ci_rerun_failed.py <run_id> --wait     # 等这次 run 重新出结论(每 30 秒查一次, 最多 30 分钟)
令牌: Git 凭据管理器里取(不打印); 本机代理会改写请求, 一律绕开(ProxyHandler({}))。
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
REPO = "yinzuoliu87-cpu/Turtle_realtime_battle"
API = "https://api.github.com/repos/%s" % REPO


def token() -> str:
	env = dict(os.environ, GCM_INTERACTIVE="Never")
	out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
		capture_output=True, text=True, env=env, timeout=30).stdout
	for ln in out.splitlines():
		if ln.startswith("password="):
			return ln[len("password="):]
	raise SystemExit("Git 凭据管理器里没取到 github.com 的令牌")


OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def call(method: str, path: str, tok: str):
	req = urllib.request.Request(API + path, method=method, data=(b"" if method == "POST" else None),
		headers={"Authorization": "Bearer " + tok, "Accept": "application/vnd.github+json", "User-Agent": "turtle-ci-rerun"})
	with OPENER.open(req, timeout=60) as r:
		body = r.read()
		return r.status, (json.loads(body) if body else {})


def main() -> None:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	if not args or not args[0].isdigit():
		raise SystemExit(__doc__)
	rid = args[0]
	tok = token()
	st, _ = call("POST", "/actions/runs/%s/rerun-failed-jobs" % rid, tok)
	print("已触发重跑红的那几片: run %s(HTTP %d)" % (rid, st))
	if "--wait" not in sys.argv:
		return
	t0 = time.time()
	time.sleep(20)
	while time.time() - t0 < 1800:
		_, run = call("GET", "/actions/runs/%s" % rid, tok)
		if run.get("status") == "completed":
			print("CI 结论: %s · 第 %s 次尝试 · %s" % (run.get("conclusion"), run.get("run_attempt"), run.get("html_url")))
			_, jobs = call("GET", "/actions/runs/%s/jobs?per_page=50" % rid, tok)
			for j in jobs.get("jobs", []):
				if j.get("conclusion") not in ("success", "skipped"):
					print("  ✗ %s: %s" % (j.get("name"), j.get("conclusion")))
			sys.exit(0 if run.get("conclusion") == "success" else 1)
		time.sleep(30)
	raise SystemExit("等了 30 分钟还没出结论")


if __name__ == "__main__":
	main()
