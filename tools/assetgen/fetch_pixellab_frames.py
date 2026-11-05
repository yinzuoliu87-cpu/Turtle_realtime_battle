# -*- coding: utf-8 -*-
"""tools/assetgen/fetch_pixellab_frames.py — 把 PixelLab animate_image 任务的生成帧下到仓库(素材源, 2026-11-05)。

为什么进仓库: PixelLab 生成不可离线重现; 原始帧落盘当「素材源」, 之后的后处理(锁原调色板 / 拼帧条)只读仓库文件 ⇒ 重跑逐字节相同。
用法: python tools/assetgen/fetch_pixellab_frames.py <输出目录> <job_id> [帧数=8]
  下 index 1..帧数(index 0 是输入帧原样, 不要)到 <输出目录>/ai_<n>.png; 任务没完成(423)每 10 秒重试, 最多 6 分钟。
下载接口公开、不带令牌(https://api.pixellab.ai/mcp/images/<job>/download?index=N)。
"""
import os
import sys
import time
import urllib.error
import urllib.request

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def fetch(out_dir: str, job: str, n: int) -> int:
	os.makedirs(out_dir, exist_ok=True)
	t0 = time.time()
	for i in range(1, n + 1):
		url = "https://api.pixellab.ai/mcp/images/%s/download?index=%d" % (job, i)
		while True:
			try:
				data = OPENER.open(url, timeout=60).read()
				if data[:8] != b"\x89PNG\r\n\x1a\n":
					raise SystemExit("%s 第 %d 帧不是 PNG" % (job, i))
				open(os.path.join(out_dir, "ai_%d.png" % i), "wb").write(data)
				break
			except urllib.error.HTTPError as e:
				if e.code != 423 or time.time() - t0 > 360:
					raise SystemExit("%s 第 %d 帧下载失败: HTTP %d" % (job, i, e.code))
				time.sleep(10)
	print("下完 %s → %s(%d 帧)" % (job, out_dir, n))
	return 0


if __name__ == "__main__":
	sys.stdout.reconfigure(encoding="utf-8")
	if len(sys.argv) < 3:
		print(__doc__)
		raise SystemExit(2)
	raise SystemExit(fetch(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8))
