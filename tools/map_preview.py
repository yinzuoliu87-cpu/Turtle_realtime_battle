# -*- coding: utf-8 -*-
"""arena.json 的【离线预览】—— 按战斗相机的真投影把地砖画出来, 用【实测的渲染后颜色】上色。

为什么要这个: 起一次 Godot 抓图约 2 分钟, 构图要试十几版根本试不动。
这个脚本 0.3 秒出图, 用来【筛】方案; 选中的那版仍然必须进游戏抓真图确认
(离线预览没有雾/光照/装饰物/单位, 只能判构图, 不能当验收 —— 产物才是判据)。

★颜色不是从 TILE_COLS 抄的, 是从 map_v2_game.png 上【量】出来的渲染后均值:
    淤泥(26,33,42) 石(44,49,67) 沙(49,59,100) 水(15,132,142) void(1,25,48)
  直接抄 TILE_COLS 会偏 —— 那是 albedo, 还要乘灰度贴图、过光照与 filmic tonemap。

★相机参数来自 battle_world_builder._build_camera 的 MAP_V2 分支: pos(0,28,22) fov40 look_at(0,0.6,0)。

跑法: python tools/map_preview.py data/maps/arena.json out.png
"""
import io
import json
import math
import sys

from PIL import Image, ImageDraw

WS = 0.024
CX, CY = 868.0, 474.0
CAM = (0.0, 28.0, 22.0)
TGT = (0.0, 0.6, 0.0)
FOV = 40.0
SW, SH = 1280, 720

# 实测渲染后颜色(不是 TILE_COLS 的 albedo)
COL = [(26, 33, 42), (15, 132, 142), (44, 49, 67), (49, 59, 100), None]

# 屏幕上被 UI 吃掉的区域(16:9 实测): 左右队伍面板 / 顶部 PK 条
PANEL_L, PANEL_R = 170, 1110
PK_BOTTOM = 60

_f = [TGT[i] - CAM[i] for i in range(3)]
_L = math.dist(CAM, TGT)
_f = [x / _L for x in _f]
_RT = (1.0, 0.0, 0.0)
_UP = (_RT[1] * _f[2] - _RT[2] * _f[1], _RT[2] * _f[0] - _RT[0] * _f[2], _RT[0] * _f[1] - _RT[1] * _f[0])
_TH = math.tan(math.radians(FOV / 2.0))
_ASP = SW / float(SH)


def proj(px, py, wy=0.0):
    P = ((px - CX) * WS, wy, (py - CY) * WS)
    v = [P[i] - CAM[i] for i in range(3)]
    zc = sum(v[i] * _f[i] for i in range(3))
    if zc <= 0.02:
        return None
    xc = sum(v[i] * _RT[i] for i in range(3))
    yc = sum(v[i] * _UP[i] for i in range(3))
    return ((1.0 + (xc / zc) / (_TH * _ASP)) / 2.0 * SW, (1.0 - (yc / zc) / _TH) / 2.0 * SH)


def render(path, out):
    m = json.load(io.open(path, encoding='utf-8'))
    tile, ox, oy = m['tile'], m['origin_x'], m['origin_y']
    w, h = m['w'], m['h']
    im = Image.new('RGB', (SW, SH), (6, 14, 26))
    dr = ImageDraw.Draw(im, 'RGBA')
    g = 0.055 / 0.024 / 2.0                             # 砖缝: 与引擎的 TILE_GAP_M(绝对宽度)对齐
                                                        #   0.055m ÷ WS ÷ 2 = 单边 1.15px
    for r in range(h):                                  # 远→近画, 近的盖远的
        for c in range(w):
            ti = int(m['grid'][r][c])
            if COL[ti] is None:
                continue
            x0, y0 = ox + c * tile + g, oy + r * tile + g
            x1, y1 = ox + (c + 1) * tile - g, oy + (r + 1) * tile - g
            q = [proj(x0, y0), proj(x1, y0), proj(x1, y1), proj(x0, y1)]
            if any(p is None for p in q):
                continue
            dr.polygon(q, fill=COL[ti])
    # 参考线: 队伍面板 / PK 条 / 两队站位 / 战场边界
    dr.rectangle([0, 0, PANEL_L, SH], fill=(0, 0, 0, 150))
    dr.rectangle([PANEL_R, 0, SW, SH], fill=(0, 0, 0, 150))
    dr.rectangle([0, 0, SW, PK_BOTTOM], fill=(0, 0, 0, 150))
    for dx in (-420.0, 420.0):                          # 两队站位(4 只的纵向铺开 ±231)
        for k in (-1.5, -0.5, 0.5, 1.5):
            p = proj(CX + dx, CY + k * 154.0)
            if p:
                dr.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], outline=(255, 90, 90), width=2)
    pts = [proj(70, 110), proj(1666, 110), proj(1666, 838), proj(70, 838)]
    dr.line([p for p in pts] + [pts[0]], fill=(255, 200, 60, 120), width=2)
    im.save(out)
    return out


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else 'data/maps/arena.json'
    dst = sys.argv[2] if len(sys.argv) > 2 else 'C:/tmp/map_preview.png'
    print("预览 →", render(src, dst))
