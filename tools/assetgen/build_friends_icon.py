# 主菜单右上「好友」小图标键的像素图标(用户 2026-11-06: 好友从左列方键挪到右上设置旁边, 「做成一个简单的这个小图标」)。
# 与旁边的设置齿轮(build_gear_icon.py)同一套: 17x17 栅格 + 1 圈描边 = 19x19, 存 ×2 = 38x38;
#   描边 #140a03、本体 #d8d4cc、左上亮右下暗 —— 同一排三颗小键(好友 / ? / ⚙)是一家人。
# 画法: 一前一后两个人(头 + 肩), 前面的人(左下)用亮色, 后面的人(右上)暗一档; 两人交界处留一像素描边色, 读得出是两个人。
# 跑法: python tools/assetgen/build_friends_icon.py assets/sprites/menu/hud/ic-friends-s.png <预览图.png>
#   确定性: 纯几何栅格化, 重跑逐字节相同。
import math
import sys
from PIL import Image

n = 17
BASE = (216, 212, 204, 255)
SHADE = (150, 143, 132, 255)
HI = (246, 243, 236, 255)
OUT = (20, 10, 3, 255)

## (头心 x, 头心 y, 头半径, 肩心 x, 肩心 y, 肩半宽, 肩半高, 肩顶 y)
FRONT = (5.5, 6.2, 3.3, 5.5, 16.8, 5.6, 6.2, 10.6)
BACK = (11.6, 3.4, 2.8, 11.8, 13.6, 4.9, 5.4, 7.4)


def inside(p, x, y):
    hx, hy, hr, bx, by, brx, bry, btop = p
    if math.hypot(x - hx, y - hy) <= hr:
        return 'H'
    if y >= btop and ((x - bx) / brx) ** 2 + ((y - by) / bry) ** 2 <= 1.0:
        return 'S'
    return ''


def kind(x, y):
    if inside(FRONT, x, y):
        return 'F'
    if inside(BACK, x, y):
        return 'B'
    return '.'


N = n + 2
grid = [[kind(x, y) for x in range(n)] for y in range(n)]
## 后面的人挨着前面的人的那一圈 ⇒ 描边色(两人分得开)
sep = set()
for y in range(n):
    for x in range(n):
        if grid[y][x] != 'B':
            continue
        for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, yy = x + ax, y + ay
            if 0 <= xx < n and 0 <= yy < n and grid[yy][xx] == 'F':
                sep.add((x, y))
                break

img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
px = img.load()
for y in range(n):
    for x in range(n):
        k = grid[y][x]
        if k == '.':
            continue
        if (x, y) in sep:
            col = OUT
        elif k == 'F':
            d = (x - FRONT[0]) + (y - FRONT[1])
            col = HI if d <= -2.0 else (SHADE if x - FRONT[3] >= 3.6 else BASE)
        else:
            d = (x - BACK[0]) + (y - BACK[1])
            col = BASE if d <= -1.5 else SHADE
        px[x + 1, y + 1] = col
out = img.copy()
op = out.load()
for y in range(N):
    for x in range(N):
        if px[x, y][3]:
            continue
        for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, yy = x + ax, y + ay
            if 0 <= xx < N and 0 <= yy < N and px[xx, yy][3]:
                op[x, y] = OUT
                break
big = out.resize((N * 2, N * 2), Image.NEAREST)
big.save(sys.argv[1])
if len(sys.argv) > 2:
    prev = Image.new('RGBA', (N * 2 + 20, N * 2 + 20), (96, 70, 44, 255))
    prev.alpha_composite(big, (10, 10))
    prev.resize((prev.width * 5, prev.height * 5), Image.NEAREST).save(sys.argv[2])
for y in range(N):
    print(''.join({OUT: '#', BASE: 'o', SHADE: 's', HI: 'h'}.get(op[x, y], ' ') for x in range(N)))
