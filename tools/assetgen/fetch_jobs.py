# -*- coding: utf-8 -*-
"""tools/assetgen/fetch_jobs.py — 批量下 PixelLab animate_image 任务的帧(2026-11-05)。

任务清单(tsv, 每行: 龟id 段名 job_id 帧数), 下到 tools/assetgen/pet_src/<龟>/<段>/ai_N.png。
多线程逐个等(423 = 还在生成, 每 10 秒重试, 最多 8 分钟), 全部下完才退出 —— 不用 shell 管道 + 后台 &
(11-05 踩过: 管道里起的后台子进程随管道结束被收掉, 目录建了一帧没下, 还打出「下完」)。
用法: python tools/assetgen/fetch_jobs.py <清单.tsv> [龟id ...]   (不给龟 id = 清单里全部; 已下齐的段跳过)
"""
import concurrent.futures as cf
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fetch_pixellab_frames as F  # noqa: E402


def main() -> int:
	sys.stdout.reconfigure(encoding="utf-8")
	rows = [ln.split() for ln in open(sys.argv[1], encoding="utf-8") if ln.strip()]
	want = set(sys.argv[2:])
	todo = []
	for tid, seg, job, n in rows:
		if want and tid not in want:
			continue
		d = os.path.join(HERE, "pet_src", tid, seg)
		if os.path.isdir(d) and len([f for f in os.listdir(d) if f.startswith("ai_")]) >= int(n):
			continue
		todo.append((d, job, int(n)))
	with cf.ThreadPoolExecutor(max_workers=8) as ex:
		futs = [ex.submit(F.fetch, d, job, n) for d, job, n in todo]
		bad = 0
		for f in futs:
			try:
				f.result()
			except SystemExit as e:
				bad += 1
				print("失败:", e)
	print("下完 %d 段, 失败 %d" % (len(todo) - bad, bad))
	return 1 if bad else 0


if __name__ == "__main__":
	raise SystemExit(main())
