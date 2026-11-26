"""ui_drive.py —— 像人一样操作桌面程序(截屏 + 鼠标 + 键盘), 用于在 Aseprite 里一笔笔画像素(2026-11-25)

用户 11-25:「就像人一样使用设计的软件…操控像素软件去进行设计，然后存文件…这种工作流应该更可控一点」。
记忆 fb-aseprite-human-workflow-1125; CLAUDE.md §10 第 7 条。

坐标 = 虚拟桌面物理像素(每屏 DPI 感知 v2; 截图坐标 = 点击坐标)。本机: 左屏 0..1920×1080, 右屏 1920..4480×1600(窗口只开右屏)。

    python tools/oneoff/ui_drive.py shot <out.png> [x0 y0 x1 y1]
    python tools/oneoff/ui_drive.py click <x> <y> [left|right]
    python tools/oneoff/ui_drive.py drag <x0> <y0> <x1> <y1> ... (按住左键沿折线走, 每段插点)
    python tools/oneoff/ui_drive.py key <组合>            例: ctrl+n / enter / b / alt+f4
    python tools/oneoff/ui_drive.py type <文字>
    python tools/oneoff/ui_drive.py move <x> <y>
"""
import ctypes, sys, time
from ctypes import wintypes

user32 = ctypes.windll.user32
user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))   # PER_MONITOR_AWARE_V2

INPUT_MOUSE, INPUT_KEYBOARD = 0, 1
MOVE, LDOWN, LUP, RDOWN, RUP, MDOWN, MUP, ABS, VDESK = 0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x8000, 0x4000
KEYUP, UNICODE = 0x2, 0x4


class MI(ctypes.Structure):
    _fields_ = [("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG))]


class KI(ctypes.Structure):
    _fields_ = [("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD),
                ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG))]


class _U(ctypes.Union):
    _fields_ = [("mi", MI), ("ki", KI), ("pad", ctypes.c_byte * 32)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


def _vd():
    return (user32.GetSystemMetrics(76), user32.GetSystemMetrics(77), user32.GetSystemMetrics(78), user32.GetSystemMetrics(79))


def _send(*ins):
    arr = (INPUT * len(ins))(*ins)
    user32.SendInput(len(ins), arr, ctypes.sizeof(INPUT))


def _mouse(flags, x=0, y=0):
    vx, vy, vw, vh = _vd()
    ax = int((x - vx) * 65535 / max(1, vw - 1))
    ay = int((y - vy) * 65535 / max(1, vh - 1))
    i = INPUT(type=INPUT_MOUSE)
    i.u.mi = MI(ax, ay, 0, flags | ABS | VDESK | MOVE, 0, None)
    _send(i)


def move(x, y):
    _mouse(0, x, y)
    time.sleep(0.02)


def click(x, y, button="left"):
    move(x, y)
    d, u = (LDOWN, LUP) if button == "left" else (RDOWN, RUP)
    _mouse(d, x, y); time.sleep(0.03); _mouse(u, x, y); time.sleep(0.05)


def drag(pts, step=4, button="left"):
    down, up = (LDOWN, LUP) if button == "left" else (MDOWN, MUP)
    x0, y0 = pts[0]
    move(x0, y0)
    _mouse(down, x0, y0); time.sleep(0.03)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        n = max(1, int(max(abs(bx - ax), abs(by - ay)) / step))
        for k in range(1, n + 1):
            _mouse(0, ax + (bx - ax) * k / n, ay + (by - ay) * k / n)
            time.sleep(0.004)
    _mouse(up, *pts[-1]); time.sleep(0.05)


VK = {"ctrl": 0x11, "shift": 0x10, "alt": 0x12, "enter": 0x0D, "esc": 0x1B, "tab": 0x09, "space": 0x20, "back": 0x08, "del": 0x2E,
      "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28, "home": 0x24, "end": 0x23, "pgup": 0x21, "pgdn": 0x22}
VK.update({"f%d" % i: 0x6F + i for i in range(1, 13)})


def key(combo):
    names = combo.lower().split("+")
    codes = [VK[n] if n in VK else ord(n.upper()) for n in names]
    for c in codes:
        i = INPUT(type=INPUT_KEYBOARD); i.u.ki = KI(c, 0, 0, 0, None); _send(i); time.sleep(0.02)
    for c in reversed(codes):
        i = INPUT(type=INPUT_KEYBOARD); i.u.ki = KI(c, 0, KEYUP, 0, None); _send(i); time.sleep(0.02)
    time.sleep(0.05)


def type_text(s):
    for ch in s:
        for fl in (UNICODE, UNICODE | KEYUP):
            i = INPUT(type=INPUT_KEYBOARD); i.u.ki = KI(0, ord(ch), fl, 0, None); _send(i)
        time.sleep(0.01)


def shot(out, box=None):
    from PIL import ImageGrab
    im = ImageGrab.grab(all_screens=True)
    vx, vy, _w, _h = _vd()
    if box:
        im = im.crop((box[0] - vx, box[1] - vy, box[2] - vx, box[3] - vy))
    im.save(out)
    return im.size


## ── Aseprite 画布坐标(格子) → 屏幕: 画布左上角 + 每格点数(当次缩放实测, 环境变量 ASE_X0 / ASE_Y0 / ASE_Z) ──
import os
X0 = int(os.environ.get("ASE_X0", "2160")); Y0 = int(os.environ.get("ASE_Y0", "201")); Z = int(os.environ.get("ASE_Z", "24"))
HEX = (int(os.environ.get("ASE_HEX_X", "2238")), int(os.environ.get("ASE_HEX_Y", "1275")))   # 前景色弹框里的十六进制输入框


def cell(px, py):
    return X0 + px * Z + Z // 2, Y0 + py * Z + Z // 2


FG = (int(os.environ.get("ASE_FG_X", "1996")), int(os.environ.get("ASE_FG_Y", "1440")))   # 左下角前景色块


def color(hexstr):
    """点开前景色弹框 → 点十六进制框 → 输色值 → 回车 → Esc 关弹框(弹框没开就点输入框, 后面敲的字会被当成快捷键)"""
    click(*FG); time.sleep(0.35)
    click(*HEX); time.sleep(0.1); key("ctrl+a"); type_text(hexstr); key("enter"); time.sleep(0.1); key("esc"); time.sleep(0.1)


def find_canvas():
    """右屏截图里找透明底棋盘格(128/192 灰)的外框 ⇒ 画布左上角屏幕坐标"""
    from PIL import ImageGrab
    im = ImageGrab.grab(all_screens=True).convert("RGB")
    vx, vy, _w, _h = _vd()
    px = im.load()
    xs, ys = [], []
    for y in range(150 - vy, 1100 - vy, 6):
        for x in range(2100 - vx, 4420 - vx, 6):
            if px[x, y] in ((128, 128, 128), (192, 192, 192)):
                xs.append(x); ys.append(y)
    if not xs:
        return None
    x0, y0 = min(xs), min(ys)
    while x0 > 0 and px[x0 - 1, y0 + 3] in ((128, 128, 128), (192, 192, 192)):
        x0 -= 1
    while y0 > 0 and px[x0 + 3, y0 - 1] in ((128, 128, 128), (192, 192, 192)):
        y0 -= 1
    return x0 + vx, y0 + vy


def fitview(zoom="1200"):
    click(4420, 1510); time.sleep(0.2); key("ctrl+a"); type_text(zoom); key("enter"); time.sleep(0.5)
    move(3000, 1450); time.sleep(0.2)
    c = find_canvas()
    if c is None:
        return None
    drag([(3300, 700), (3300 + X0 - c[0], 700 + Y0 - c[1])], button="middle"); time.sleep(0.3)
    move(3000, 1450); time.sleep(0.2)
    return find_canvas()


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "shot":
        print(shot(a[1], [int(v) for v in a[2:6]] if len(a) >= 6 else None))
    elif a[0] == "click":
        click(int(a[1]), int(a[2]), a[3] if len(a) > 3 else "left")
    elif a[0] == "pan":   # 中键拖动(平移画布)
        v = [int(x) for x in a[1:5]]
        drag([(v[0], v[1]), (v[2], v[3])], button="middle")
    elif a[0] == "color":   # Aseprite 前景色(色值不带 #)
        color(a[1])
    elif a[0] == "cdrag":   # 按画布格子坐标拖(落笔一条折线 / 椭圆、矩形工具的两个角)
        v = [int(x) for x in a[1:]]
        drag([cell(x, y) for x, y in zip(v[0::2], v[1::2])], step=3)
    elif a[0] == "cclick":
        for x, y in zip([int(v) for v in a[1::2]], [int(v) for v in a[2::2]]):
            click(*cell(x, y))
    elif a[0] == "fitview":
        print(fitview(a[1] if len(a) > 1 else "1200"))
    elif a[0] == "move":
        move(int(a[1]), int(a[2]))
    elif a[0] == "drag":
        v = [int(x) for x in a[1:]]
        drag(list(zip(v[0::2], v[1::2])))
    elif a[0] == "key":
        key(a[1])
    elif a[0] == "type":
        type_text(" ".join(a[1:]))
