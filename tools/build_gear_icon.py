# 主菜单设置键的像素齿轮(替换 ⚙ 字符; 用户 2026-10-23「换上」)。17x17 栅格 + 1 圈描边 = 19x19, 存 ×2 = 38x38。
# 跑法: python tools/build_gear_icon.py assets/sprites/menu/hud/ic-gear.png <预览图.png>
#   与旁边 m6x11「?」同一种块感; 描边色 = ? 的描边色 #140a03; 本体色 = 原来 ⚙ 字的 #d8d4cc; 左上亮右下暗。
# 齿 = 离齿轴线 < TOOTH_W 且半径在 [R_BODY-1, R_TIP] 的点(直边齿); 齿间缺口 ≥2px ⇒ 描边后轮廓仍是齿轮不是圆团。
import math, sys
from PIL import Image

n = 17
c = (n - 1) / 2.0
R_BODY = 6.1
R_TIP = 8.3
R_HOLE = 2.3
TOOTH_W = 1.75
TEETH = 8
BASE = (216, 212, 204, 255)
SHADE = (150, 143, 132, 255)
HI = (246, 243, 236, 255)
OUT = (20, 10, 3, 255)
HOLE = (58, 42, 30, 255)


def kind(x, y):
    dx, dy = x - c, y - c
    r = math.hypot(dx, dy)
    if r <= R_HOLE:
        return 'O'
    if r <= R_BODY:
        return 'X'
    if r <= R_TIP:
        for k in range(TEETH):
            a = k * 2 * math.pi / TEETH
            ux, uy = math.cos(a), math.sin(a)
            along = dx * ux + dy * uy
            perp = abs(-dx * uy + dy * ux)
            if along > 0 and perp <= TOOTH_W:
                return 'X'
    return '.'


N = n + 2
img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
px = img.load()
for y in range(n):
    for x in range(n):
        k = kind(x, y)
        if k == '.':
            continue
        dx, dy = x - c, y - c
        if k == 'O':
            col = HOLE
        elif dx + dy >= 3.5:
            col = SHADE
        elif dx + dy <= -5:
            col = HI
        else:
            col = BASE
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
## 轴孔描一圈深色(孔边)
for y in range(N):
    for x in range(N):
        if px[x, y] == HOLE:
            pass
big = out.resize((N * 2, N * 2), Image.NEAREST)
big.save(sys.argv[1])
prev = Image.new('RGBA', (N * 2 + 20, N * 2 + 20), (96, 70, 44, 255))
prev.alpha_composite(big, (10, 10))
prev.resize((prev.width * 5, prev.height * 5), Image.NEAREST).save(sys.argv[2])
for y in range(N):
    print(''.join({OUT: '#', BASE: 'o', SHADE: 's', HI: 'h', HOLE: '.'}.get(op[x, y], ' ') for x in range(N)))
