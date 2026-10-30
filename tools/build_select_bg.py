"""选龟页背景: 把旧回合制版式烤在桌面上的面板(6 卡槽托盘 + 前/后排横幅 / 顶栏两块木托 / 龟池大凹槽 / 右栏两格 + 绿牌)
铺回成桌面木板, 只留桌子四周的道具和左上的羊皮纸(羁绊写在上面)。界面的框改由代码按背包页那一套画。

由来: 2026-10-30 用户「整个背景图，每个方正条条框框的地方，你都没有注意吗？」「你这还是一股浏览器的感觉啊」
  —— 背景是给旧 6 格版式画的, 后来的界面一层层贴在上面, 框对不上(方案书 docs/plans/20261030-选龟页重做.md)。
做法: 取原图下沿一段干净的整块桌板(BAND), 一行一行错位铺满中间区域, 接缝补一道板缝暗线, 边缘羽化进原图。
确定性: 不用随机数(错位量写死), 重跑逐字节相同。
源图: tools/art_src/select-bg-src.png(改之前那张原样存档; 本脚本只读它, 写 assets/sprites/bg/select-bg.png)。
跑法: python tools/build_select_bg.py   然后 Godot --import(换了 png 必须重新导入)
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art_src", "select-bg-src.png")
OUT = os.path.join(ROOT, "assets", "sprites", "bg", "select-bg.png")

BAND = (380, 788, 1150, 866)          # 原图下沿一段干净整板(左: 酒杯右侧; 右: 钱袋左侧; 下: 金币上方)
## 要铺回桌面的区域(设计坐标 = 原图像素, 1647×955): 羊皮纸右边那一片 + 羊皮纸下面那一片
FILL = [(404, 58, 1512, 362), (196, 352, 1512, 808)]
FEATHER = 10
## 每一行板的横向错位(写死, 不用随机数)
OFFSETS = [0, 311, 147, 523, 64, 402, 219, 590, 96, 355, 488]


def plank_field(w: int, h: int, band: Image.Image) -> Image.Image:
    bw, bh = band.size
    field = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(field)
    row = 0
    y = 0
    while y < h:
        off = OFFSETS[row % len(OFFSETS)]
        flip = row % 2 == 1
        src = band.transpose(Image.FLIP_LEFT_RIGHT) if flip else band
        x = -off
        while x < w:
            field.paste(src, (x, y))
            ## 板与板的接头: 一道竖向暗线 + 右侧一列高光(与原图板缝同一种画法)
            if x > 0:
                d.line([(x, y + 2), (x, y + bh - 3)], fill=(22, 13, 8))
                d.line([(x + 1, y + 2), (x + 1, y + bh - 3)], fill=(74, 46, 28))
            x += bw
        ## 板与板之间的横缝
        d.line([(0, y), (w, y)], fill=(18, 11, 6))
        d.line([(0, y + 1), (w, y + 1)], fill=(30, 19, 11))
        y += bh
        row += 1
    return field


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    band = src.crop(BAND).convert("RGB")
    out = src.copy()
    W, H = src.size
    ## 先在整张图大小上铺一张木板场, 再按 FILL 的并集(羽化)贴上去 —— 两块区域共用同一张场, 接缝处行对得上
    field = plank_field(W, H, band).convert("RGBA")
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for r in FILL:
        md.rectangle(r, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(FEATHER / 2))
    ## 羊皮纸(左上道具)不能被盖: 它的右沿 ~400、下沿 ~350, FILL 已绕开; 再保险抠掉
    md2 = ImageDraw.Draw(mask)
    md2.rectangle((140, 60, 402, 352), fill=0)
    out = Image.composite(field, out, mask)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("ok", OUT, out.size)


if __name__ == "__main__":
    main()
