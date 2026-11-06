# -*- coding: utf-8 -*-
"""tools/ship.py — 把当前提交交给 CI 验收, 全绿自动进 main(2026-11-05)。

用户 11-05:「肯定是要改呀…这个做法效率太低了呀。网上最好的做法是什么呢？…你按最好的做法来呀。」
取代 10-31 的「推送前本机跑完整门禁」(那一条占满用户电脑约 15 分钟、跑的期间不能改仓库 / 开录制;
而它跑的是和 CI 同一套测试, 并不多抓问题)。业界通行做法 = 主干开发 + CI 把关合并:
  · 改动推到 wip/<主题> 分支 → tests.yml 八片并行跑全套(约 10 分钟, 公开仓库不计费)
  · 八片全绿 ⇒ tests.yml 的 promote 把这次提交「快进」进 main(不是后代就失败, 不硬塞) ⇒ main 永远是 CI 验过的
  · 本机只跑跟改动直接相关的测试 + 审计器(几秒到几分钟); 等 CI 的时候接着干别的

用法:
  python tools/ship.py <主题>            # 推 HEAD 到 wip/<主题>, 立刻返回
  python tools/ship.py <主题> --wait     # 推完等 CI 结论(每 60 秒查一次, 最多 40 分钟); 红了打印失败测试与日志尾
  python tools/ship.py --status          # 看 HEAD 这个提交在 CI 上的状态
  ★推之前先过 python tools/precheck.py(11-06 起强制; 只改文档免; 紧急绕过 --no-precheck)
前提: 工作区干净(未提交的改动不会被验, 拒绝推); HEAD 是 origin/main 的后代(否则 CI 绿了也快进不了)。
令牌: Git 凭据管理器里取(不打印); 本机代理会改写请求, 一律绕开(ProxyHandler({}))。
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "yinzuoliu87-cpu/Turtle_realtime_battle"
API = "https://api.github.com/repos/" + REPO
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def git(*args: str) -> str:
	return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout.strip()


def token() -> str:
	out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n", capture_output=True, text=True,
		env={**os.environ, "GCM_INTERACTIVE": "Never"}).stdout
	return next((ln.split("=", 1)[1] for ln in out.splitlines() if ln.startswith("password=")), "")


def api(path: str) -> dict:
	req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token(), "Accept": "application/vnd.github+json"})
	return json.loads(OPENER.open(req, timeout=30).read())


def run_for(sha: str) -> dict:
	## ★必须用完整 40 位提交号: 短号查不到(11-04 白等 36 分钟)
	runs = api("/actions/workflows/tests.yml/runs?head_sha=%s&per_page=5" % sha).get("workflow_runs", [])
	return runs[0] if runs else {}


def show_failures() -> None:
	subprocess.run(["git", "fetch", "-q", "-f", "origin", "+refs/heads/ci-logs:refs/remotes/origin/ci-logs"], cwd=ROOT)
	files = git("ls-tree", "--name-only", "origin/ci-logs").splitlines()
	fails = [f for f in files if f.endswith(".log")]
	print("ci-logs 里的失败日志 %d 份: %s" % (len(fails), ", ".join(fails[:12])))
	for f in fails[:3]:
		tail = git("show", "origin/ci-logs:" + f).splitlines()
		bad = [ln for ln in tail if "[FAIL]" in ln or "SCRIPT ERROR" in ln][:4]
		print("── %s ──\n%s" % (f, "\n".join(bad or tail[-6:])))


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	head = git("rev-parse", "HEAD")
	if "--status" in sys.argv:
		r = run_for(head)
		print("HEAD %s · CI: %s / %s" % (head[:8], r.get("status", "没找到"), r.get("conclusion")))
		return 0
	if not args:
		print(__doc__)
		return 2
	if git("status", "--porcelain", "--untracked-files=no"):
		print("✗ 工作区有没提交的改动 —— CI 只验提交过的东西, 先提交")
		return 1
	## ★没过本机预检不许推(用户 11-06「跑个十分钟 CI, 找个小问题, 又跑个十分钟 CI …我不觉得这是很好的呀」): 只改文档的提交不用过
	code = [f for f in git("diff", "--name-only", "origin/main", "HEAD").split() if not f.startswith("docs/") and not f.endswith(".md")]
	stamp = os.path.join(ROOT, ".out", "precheck_ok")
	done = open(stamp, encoding="utf-8").read().strip() if os.path.exists(stamp) else ""
	if code and done != head and "--no-precheck" not in sys.argv:
		print("✗ 这个提交没过本机预检 —— 先跑 python tools/precheck.py(CI 不是用来找小错的)")
		return 1
	git("fetch", "-q", "origin", "main")
	if subprocess.run(["git", "merge-base", "--is-ancestor", "origin/main", "HEAD"], cwd=ROOT).returncode != 0:
		print("✗ HEAD 不是 origin/main 的后代 —— 先 rebase 到最新 main, 否则 CI 绿了也快进不了")
		return 1
	branch = "wip/" + args[0]
	r = subprocess.run(["git", "push", "-f", "origin", "HEAD:refs/heads/" + branch], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
	if r.returncode != 0:
		print("✗ 推送失败:", r.stderr.strip()[-300:])
		return 1
	print("已推 %s → %s(CI 跑全套, 全绿自动快进 main)" % (head[:8], branch))
	if "--wait" not in sys.argv:
		return 0
	t0 = time.time()
	while time.time() - t0 < 40 * 60:
		time.sleep(60)
		rr = run_for(head)
		if rr.get("status") == "completed":
			c = rr.get("conclusion")
			print("CI 结论: %s · %.0f 分钟 · %s" % (c, (time.time() - t0) / 60, rr.get("html_url", "")))
			if c == "success":
				time.sleep(20)
				git("fetch", "-q", "origin", "main")
				ok = git("rev-parse", "origin/main") == head
				print("main %s %s" % ("已快进到" if ok else "★没有快进到", head[:8]))
				return 0 if ok else 1
			show_failures()
			return 1
	print("等了 40 分钟还没结论")
	return 1


if __name__ == "__main__":
	sys.exit(main())
