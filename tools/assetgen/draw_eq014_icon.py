# -*- coding: utf-8 -*-
"""4 费装备「深海堡垒甲」(p2eq_014) 的 32×32 图标(2026-11-15 重画, 用户「还行吧，这部分看上去没啥问题啊」认可)。

确定性生成, 重跑逐字节相同:
  python tools/assetgen/draw_eq014_icon.py            写 assets/sprites/equip/eq014-icon.png
  python tools/assetgen/draw_eq014_icon.py <路径>     写到别处(出对照图用)

做法(如实): 左半边每个像素的颜色是手写在下面 LEFT 字符图里的; 右半边由脚本镜像并压暗一档(光从左上来),
  外轮廓的 1 像素描边由脚本补。中脊、腰带扣、甲裙铆钉、右肩上沿亮边是单独点的几个像素。
参考(只学画法, 不取像素): Necesse / Hero Siege / 泰拉瑞亚 / Moonlighter 的胸甲图标约 120 件 ——
  肩宽腰窄的剪影、左上受光的球面胸甲、肩甲叠片上沿受光、U 形领口能看见内壁、描边用材质最暗的颜色。
"""
import os
import sys
from PIL import Image

PAL = {
    "K": (22, 29, 42),     # 描边(深蓝灰, 不用纯黑)
    "D": (42, 58, 82),     # 暗
    "M": (72, 103, 138),   # 中
    "L": (126, 166, 194),  # 亮
    "H": (198, 226, 238),  # 高光
    "W": (244, 251, 255),  # 白点
    "g": (122, 74, 28),    # 金暗
    "G": (196, 145, 58),   # 金中
    "Y": (242, 210, 124),  # 金亮
    "a": (176, 255, 236),  # 海蓝宝石亮
    "A": (54, 196, 186),   # 海蓝宝石
    "q": (20, 104, 112),   # 海蓝宝石暗
}
# 左半边 x 0..15(第 16 列起是镜像), y 0..31; '.' 透明
LEFT = [
    "................",  # 0
    "................",  # 1
    "................",  # 2
    ".....HLLL...gGGG",  # 3  肩甲圆顶最高处 · 领口远沿(背后那圈, 暗金)
    "...HHLLLLM.GKKKK",  # 4  领口里面(看进盔甲内壁, 最暗)
    "..HLLLLLMMDGKKDD",  # 5  内壁背板受一点光
    ".HLLLLMMMMD.YKDD",  # 6  领口往下收(U 形)
    ".LLMMMMMMDDDLYYY",  # 7  第一片下沿压暗 · 领口近沿(朝光, 亮金)
    ".DDDDDDDDDDDMGGG",  # 8  两片之间的暗缝 · 近沿厚度
    ".HHLLLLMMMDDDDDD",  # 9  第二片上沿受光 · 护颈投影
    ".LMMMMMMMDD.MLLM",  # 10
    "..DDDDDDDD..MLLL",  # 11 第二片下沿
    "..GYYGGGGg.MLLHL",  # 12 金边包底
    "...DDDDDD..LLHHL",  # 13 左胸受光的圆斑从这里开始
    "......DMLLHHHLLM",  # 14 胸甲两侧出来
    "......DMLHHWHLLM",  # 15 圆斑中心 + 一个白点
    ".......DLHHHLLMM",  # 16
    ".......DMLLLLMMM",  # 17
    "........DMMMMMMM",  # 18
    "........DDMMMMMM",  # 19 胸下压暗
    ".........DDDDDDD",  # 20
    ".........gGGGGGY",  # 21 腰带(中间是扣)
    ".........gggggGG",  # 22
    "........HLLLLLLL",  # 23 甲裙第一片(连成一片)
    "........MMMMMMMM",  # 24
    "........DDDDDDDD",  # 25
    ".......HLLLLLLLL",  # 26 第二片往外张一格
    ".......MMMMMMMMM",  # 27
    "........DDDDDDDD",  # 28
    "................",  # 29
    "................",  # 30
    "................",  # 31
]
DARKEN = {"W": "L", "H": "L", "L": "M", "M": "M", "D": "D", "K": "K", "Y": "G", "G": "G", "g": "g"}


def build():
    g = [list(r + "." * 16) for r in LEFT]
    for y in range(32):
        for x in range(16):
            c = LEFT[y][x]
            g[y][31 - x] = DARKEN.get(c, c) if c != "." else "."
    ## 中脊: 左面受光(H) / 右面背光(D), 胸口 y 9~20
    for y in range(10, 21):
        if g[y][15] != ".":
            g[y][15] = "H" if y < 17 else "L"
            g[y][16] = "D"
    ## 腰带扣: 中间两格亮金 + 一格暗
    g[21][15], g[21][16] = "a", "A"
    g[22][15], g[22][16] = "A", "q"
    ## 甲裙两片中间各一颗铆钉(连成一片的裙甲, 不留中缝)
    g[23][15], g[23][16] = "W", "L"
    g[26][15], g[26][16] = "W", "L"
    ## 右肩甲顶补一点亮(光从左上来, 右边也该有一条上沿亮边)
    for x in (23, 24, 25):
        if g[4][x] != ".":
            g[4][x] = "L"
    for x in (24, 25, 26):
        if g[3][x] != ".":
            g[3][x] = "L"
    ## 外轮廓补 1 像素描边(4 邻接)
    op = [[g[y][x] != "." for x in range(32)] for y in range(32)]
    for y in range(32):
        for x in range(32):
            if op[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 32 and 0 <= ny < 32 and op[ny][nx]:
                    g[y][x] = "K"
                    break
    return g


def save(g, out):
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    px = im.load()
    for y in range(32):
        for x in range(32):
            if g[y][x] != ".":
                px[x, y] = PAL[g[y][x]] + (255,)
    im.save(out)


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sprites", "equip", "eq014-icon.png")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    save(build(), out)
    print("ok", out)
