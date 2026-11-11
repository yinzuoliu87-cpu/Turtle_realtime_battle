# -*- coding: utf-8 -*-
"""build_minion_avatars.py — 四种小将的头像(头部特写), 与龟的 avatars/<id>.png 同一种东西。

由来(2026-11-04): 用户看远程小将的信息面板「这里按规矩了吗」→「头像不等于全身画啊」。
  龟的头像是独立的头部特写文件(脸占满框); 小将没有头像, 面板 / 顶栏 / 头像框 / 换路过场 / 结算 / 排队页
  一直把全身立绘缩进框里(远程小将那帧 100×100 里人物只占 21%, 框里一小团暗红),
  换路过场和排队页还三种小将一律用近战那一张。

做法: 从【每种小将自己的】立绘(pets/minion*.png, 全身单帧)裁出头部那一块正方形, 原分辨率保存。
  不借别的素材; 裁框是按 10px 坐标格逐只看图定的(头盔 / 面罩 / 潜水头盔 + 一点肩), 写死在下表。
  远程小将没有脸(红色装甲 + 肩扛炮管), 取头盔顶 + 炮口那一截 —— 它的辨识点就是那门炮。

确定性: 只做裁切(无缩放 / 无重采样), 重跑逐字节相同(PNG 用 PIL 默认参数写)。
跑法: python tools/assetgen/build_minion_avatars.py           # 生成
      python tools/assetgen/build_minion_avatars.py --check   # 只核对仓库里的文件与脚本输出一致
"""
import io
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "sprites", "pets")
DST = os.path.join(ROOT, "assets", "sprites", "avatars")

## 源立绘 → 头像文件名(与 MinionCodex.AVATAR 同一张表), 裁框 (左, 上, 边长)。
CROPS = [
	("minion.png", "minion.png", (12, 2, 52)),           # 近战小将(11-11 珊瑚骑士): 鱼鳍头盔 + 面罩两点青光 + 两肩珊瑚
	("minion-back.png", "minion-back.png", (30, 21, 36)),  # 远程小将: 红色头盔顶 + 肩扛炮口
	("minion-elite.png", "minion-elite.png", (19, 5, 38)), # 精英小将: 紫色面罩头盔
	("minion-reserve.png", "minion-reserve.png", (37, 28, 30)),  # 援军小将: 黄铜潜水头盔 + 青色舷窗
]


def build(name_src, side_box):
	x, y, s = side_box
	im = Image.open(os.path.join(SRC, name_src)).convert("RGBA")
	assert x >= 0 and y >= 0 and x + s <= im.width and y + s <= im.height, (name_src, side_box, im.size)
	out = im.crop((x, y, x + s, y + s))
	buf = io.BytesIO()
	out.save(buf, format="PNG")
	return buf.getvalue()


def main():
	check = "--check" in sys.argv
	bad = 0
	for src, dst, box in CROPS:
		data = build(src, box)
		path = os.path.join(DST, dst)
		if check:
			cur = open(path, "rb").read() if os.path.exists(path) else b""
			ok = cur == data
			bad += 0 if ok else 1
			print(("OK   " if ok else "DIFF ") + os.path.relpath(path, ROOT))
		else:
			open(path, "wb").write(data)
			print("写 " + os.path.relpath(path, ROOT), box)
	if check:
		print("ALL OK" if bad == 0 else "%d 张与脚本输出不一致" % bad)
		sys.exit(1 if bad else 0)


if __name__ == "__main__":
	main()
