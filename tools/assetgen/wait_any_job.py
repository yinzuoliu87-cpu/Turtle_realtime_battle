# -*- coding: utf-8 -*-
"""tools/assetgen/wait_any_job.py — 等 PixelLab 任务里任意 N 个生成完就退出(2026-11-05)。
PixelLab 同时只许 8 个任务在跑; 排队提交时用它当「空出一个槽」的信号(后台跑, 退出即通知), 不用人盯着轮询。
用法: python tools/assetgen/wait_any_job.py <N> <job_id> [job_id ...]   (下载口返回 200 = 生成完; 423 = 还在跑; 开始时已完成的不计)
"""
import sys
import time
import urllib.error
import urllib.request

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def done(job: str) -> bool:
	try:
		OPENER.open("https://api.pixellab.ai/mcp/images/%s/download" % job, timeout=60).read()
		return True
	except urllib.error.HTTPError as e:
		if e.code == 423:
			return False
		raise


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	need, jobs = int(sys.argv[1]), list(sys.argv[2:])
	## 开始时已经生成完的不算(那是上一轮空出来、已经补交过的槽), 只数「之后新完成」的
	jobs = [j for j in jobs if not done(j)]
	need = min(need, len(jobs))
	t0, fin = time.time(), []
	while len(fin) < need and time.time() - t0 < 900:
		for j in [j for j in jobs if j not in fin]:
			if done(j):
				fin.append(j)
		if len(fin) < need:
			time.sleep(8)
	print("生成完 %d 个: %s" % (len(fin), " ".join(j[:8] for j in fin)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
