# -*- coding: utf-8 -*-
"""summon_avatars.py —— 图鉴「角色」栏召唤物的列表头像(方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md)。

做法(如实): 从召唤物现有的待机序列第 0 帧**裁一块方形头部特写**, 不重画、不缩放(像素硬边保持原样)。
与深海小将头像(avatars/minion*.png, 52~58 像素)同一种东西。重跑逐字节相同。
用法: python tools/assetgen/summon_avatars.py   (仓库根目录按往上三层算)
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

## id → (源图, 帧宽, 裁剪框(左, 上, 右, 下) 帧内坐标)
SRC = {
	"centurion": ("assets/sprites/vfx/eq-centurion-idle.png", 192, (74, 64, 126, 116)),   # 头盔红缨 + 面甲 + 盾牌上沿, 52×52
}


def main():
	for sid, (src, fw, box) in SRC.items():
		im = Image.open(os.path.join(ROOT, src)).convert("RGBA").crop((0, 0, fw, fw)).crop(box)
		out = os.path.join(ROOT, "assets", "sprites", "avatars", "summon-%s.png" % sid)
		im.save(out)
		print("ok", out, im.size)


if __name__ == "__main__":
	main()
