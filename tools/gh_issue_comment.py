"""gh_issue_comment.py —— 给 GitHub Issue 留一条进度评论（待办在 Issues 里，进度也记在那里）。

  python tools/gh_issue_comment.py <编号> <文本文件>
令牌取自 Git 凭据管理器（不打印）；绕开本机代理（代理会改写 POST body）。
"""
import json, os, subprocess, sys, urllib.request
sys.stdout.reconfigure(encoding="utf-8")
API = "https://api.github.com/repos/yinzuoliu87-cpu/Turtle_realtime_battle"


def token():
    p = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n", capture_output=True, text=True,
                       env={**os.environ, "GCM_INTERACTIVE": "Never"})
    return [l.split("=", 1)[1] for l in p.stdout.splitlines() if l.startswith("password=")][0]


num, path = int(sys.argv[1]), sys.argv[2]
body = open(path, encoding="utf-8").read()
op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
rq = urllib.request.Request("%s/issues/%d/comments" % (API, num), data=json.dumps({"body": body}).encode("utf-8"), method="POST",
                            headers={"Authorization": "Bearer " + token(), "Accept": "application/vnd.github+json",
                                     "Content-Type": "application/json; charset=utf-8"})
with op.open(rq, timeout=30) as r:
    print(r.status, json.loads(r.read().decode("utf-8"))["html_url"])
