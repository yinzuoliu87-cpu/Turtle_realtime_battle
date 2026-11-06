"""tools/oneoff/art_review_sheet.py — 28 只龟全动作验收表(给用户验收美术分支)。
每只龟一屏: 待机 / 走路 / 普攻 / 每个技能 / 状态 / 形态 / 阵亡 同屏循环, 帧率取游戏里的帧表;
第一屏 = 28 只待机全家福。素材直接读 assets/sprites/pets, 画面就是游戏实际用的帧条。
用法: python tools/oneoff/art_review_sheet.py <输出.mp4> [只出哪几只, 逗号分隔]
"""
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = sys.argv[1]
ONLY = set(sys.argv[2].split(",")) if len(sys.argv) > 2 and sys.argv[2] else None
FF = "D:/oopz/ffmpeg.exe"
FPS = 30
W, H = 1920, 1080
BG = (66, 84, 70)
CELL_BG = (54, 70, 58)
FONT = "C:/Windows/Fonts/msyh.ttc"
SPR = os.path.join(ROOT, "assets", "sprites")
ANIM = os.path.join(SPR, "pets", "animations")
f_title = ImageFont.truetype(FONT, 40)
f_sub = ImageFont.truetype(FONT, 24)
f_cell = ImageFont.truetype(FONT, 26)
f_small = ImageFont.truetype(FONT, 20)

pets = json.load(open(os.path.join(ROOT, "data", "pets.json"), encoding="utf-8"))
pets = pets if isinstance(pets, list) else pets.get("pets", pets)
pets = pets if isinstance(pets, list) else list(pets.values())

# 帧率: 全仓帧表里 "pets/animations/x/y.png", <fps> 的写法都算
FPS_OF = {}
for r, _, fs in os.walk(os.path.join(ROOT, "scripts")):
    for f in fs:
        if f.endswith(".gd"):
            t = open(os.path.join(r, f), encoding="utf-8", errors="ignore").read()
            for m in re.finditer(r'"(pets/animations/[^"]+\.png)"\s*,\s*([0-9.]+)', t):
                FPS_OF[m.group(1)] = float(m.group(2))

## 变脸龟的帧表是 "段名": [命中帧, 帧率]
two = open(os.path.join(ROOT, "scripts", "scenes", "battle", "two_head_art.gd"), encoding="utf-8").read()
for m in re.finditer(r'"([a-z_]+)":\s*\[\d+,\s*([0-9.]+)\]', two):
    FPS_OF["pets/animations/two_head/%s.png" % m.group(1)] = float(m.group(2))

FIXED = {"idle": "待机", "run": "走路", "walk": "走路", "attack": "普攻", "slash": "普攻", "throw": "投掷",
         "dash": "冲刺", "backstab-rt": "背刺", "death": "阵亡", "revive": "复活", "awaken": "觉醒",
         "transform": "变身", "revert": "变回", "strike": "重击", "absorb": "吸收", "cast": "释放",
         "disrupt": "灵能冲击", "to_melee_a": "切近战·前段", "to_melee_b": "切近战·后段",
         "to_ranged_a": "切远程·前段", "to_ranged_b": "切远程·后段"}
LABEL_OF = {"melee_strike": "近战·锤击", "ranged_strike": "远程·法球", "state_diamondRoll": "状态·蜷球"}
ORDER = ["idle", "run", "walk", "attack", "slash", "throw", "dash", "backstab-rt", "cast_", "state_", "transform",
         "revert", "awaken", "revive", "death"]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def skill_name(pet, key):
    k = norm(key)
    for sk in pet.get("skillPool", []):
        slug = norm(os.path.basename(str(sk.get("icon", ""))).rsplit(".", 1)[0])
        if norm(str(sk.get("type", ""))) == k or slug == k or (slug and (slug in k or k in slug)):
            return sk.get("name", key)
    return key


def label(pet, stem):
    if stem in LABEL_OF:
        return LABEL_OF[stem]
    prefix = ""
    for form, cn in (("melee_", "近战·"), ("ranged_", "远程·"), ("fusion_", "融合·")):
        if stem.startswith(form):
            stem, prefix = stem[len(form):], cn
    if stem in FIXED:
        return prefix + FIXED[stem]
    if stem.startswith("cast_"):
        return prefix + "技能·" + skill_name(pet, stem[5:])
    if stem.startswith("state_"):
        return prefix + "状态·" + skill_name(pet, stem[6:])
    return prefix + stem


def rank(stem):
    s = re.sub(r"^(melee|ranged|fusion)_", "", stem)
    for i, k in enumerate(ORDER):
        if s == k or (k.endswith("_") and s.startswith(k)):
            return i
    return len(ORDER)


def strip(path, fw, fh, n):
    im = Image.open(path).convert("RGBA")
    cols = max(1, im.width // fw)
    rows = max(1, im.height // fh)
    out = []
    for i in range(min(n, cols * rows)):
        x, y = (i % cols) * fw, (i // cols) * fh
        out.append(im.crop((x, y, x + fw, y + fh)))
    return out


def idle_of(pet):
    img = pet.get("img", "")
    m = pet.get("sprite") or {}
    path = os.path.join(SPR, img.replace("/", os.sep))
    im = Image.open(path)
    if isinstance(m, dict) and "frameW" in m:
        fw, fh = int(m["frameW"]), int(m.get("frameH", im.height))
        total = (im.width // fw) * (im.height // fh)
        n = max(1, min(int(m.get("frames", total)), total - 1))
        fps = max(4.0, round(n * 1000.0 / max(200.0, float(m.get("duration", 800)))))
    else:
        fw, fh, n, fps = im.width, im.height, 1, 8.0
    return {"label": "待机", "frames": strip(path, fw, fh, n), "fps": fps, "loop": True, "hold": 0.0}


def actions_of(pid, pet):
    out = []
    d = os.path.join(ANIM, pid)
    if not os.path.isdir(d):
        return out
    stems = sorted((f[:-4] for f in os.listdir(d) if f.endswith(".png")), key=lambda s: (rank(s), s))
    for stem in stems:
        ## 待机以 pets.json 为准(animations/basic/idle.png 这种是旧档, 游戏不用); 火山形态没有 pets.json 条目才读目录
        if stem == "idle" and pid != "lava_volcano":
            continue
        p = os.path.join(d, stem + ".png")
        im = Image.open(p)
        fh = im.height
        n = max(1, im.width // fh)
        rel = "pets/animations/%s/%s.png" % (pid, stem)
        is_loop = stem in ("run", "walk", "idle") or stem.endswith("_walk") or stem.endswith("_idle") or stem.startswith("state_")
        out.append({"label": label(pet, stem), "frames": strip(p, fh, fh, n), "fps": FPS_OF.get(rel, 12.0),
                    "loop": is_loop, "hold": 1.2 if "death" in stem else 0.45, "rel": rel, "stem": stem})
    return out


def frame_at(c, t):
    n = len(c["frames"])
    length = n / c["fps"]
    if c["loop"]:
        return c["frames"][int(t * c["fps"]) % n]
    cyc = length + c["hold"]
    u = t % cyc
    return c["frames"][min(n - 1, int(u * c["fps"]))]


def page_seconds(cells):
    longest = 0.0
    for c in cells:
        n = len(c["frames"])
        longest = max(longest, n / c["fps"] + c["hold"])
    return min(14.0, max(6.0, longest * 2.0))


proc = subprocess.Popen([FF, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H),
                         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                         "-pix_fmt", "yuv420p", OUT], stdin=subprocess.PIPE)


def emit(im):
    proc.stdin.write(im.tobytes())


def header(dr, title, sub, no):
    dr.text((36, 18), title, font=f_title, fill=(255, 244, 214))
    dr.text((36, 74), sub, font=f_sub, fill=(205, 222, 208))
    dr.text((W - 36, 26), no, font=f_sub, fill=(205, 222, 208), anchor="ra")


# ── 全家福 ──
ids = [p["id"] for p in pets]
if not ONLY:
    idle = [(p, idle_of(p)) for p in pets]
    cols, rows = 7, 4
    cw, ch = (W - 48) // cols, (H - 118) // rows
    base = Image.new("RGB", (W, H), BG)
    header(ImageDraw.Draw(base), "28 只龟全动作验收表", "第一屏：全家福（待机，同一比例）", "")
    for fr in range(int(FPS * 7)):
        t = fr / FPS
        im = base.copy()
        dr = ImageDraw.Draw(im)
        for i, (p, c) in enumerate(idle):
            x0, y0 = 24 + (i % cols) * cw, 108 + (i // cols) * ch
            spr = frame_at(c, t)
            big = max(spr.width, spr.height)
            s = (ch - 40) / float(big) if big < 150 else 0.9 * min(1.0, (ch - 32) / (272 * 0.9))
            sw, sh = int(spr.width * s), int(spr.height * s)
            a = spr.resize((sw, sh), Image.NEAREST)
            im.paste(a, (x0 + (cw - sw) // 2, y0 + ch - 30 - sh), a)
            dr.text((x0 + cw // 2, y0 + ch - 26), p["name"], font=f_small, fill=(255, 244, 214), anchor="ma")
        emit(im)

# ── 逐只 ──
pages = []
for p in pets:
    pid = p["id"]
    if ONLY and pid not in ONLY:
        continue
    cells = actions_of(pid, p)
    if not any(c.get("stem") in ("melee_idle", "ranged_idle") for c in cells):
        cells.insert(0, idle_of(p))
    pages.append((p["name"], pid, cells))
    if pid == "lava":
        pages.append(("熔岩龟·火山形态", "lava_volcano", actions_of("lava_volcano", p)))

report = []
for pno, (name, pid, cells) in enumerate(pages):
    n = len(cells)
    cols = 5 if n <= 10 else 6
    rows = 2 if n <= (cols * 2) else 3
    cw, ch = (W - 48) // cols, (H - 118) // rows
    ## 同一屏同一比例; 帧大小每只不同(忍者 64 / 变脸 128 / 其余 272), 按这只最大的本体放满格子
    big_w = max(c["frames"][k].getbbox()[2] - c["frames"][k].getbbox()[0] for c in cells for k in range(len(c["frames"])) if c["frames"][k].getbbox())
    big_h = max(c["frames"][k].getbbox()[3] - c["frames"][k].getbbox()[1] for c in cells for k in range(len(c["frames"])) if c["frames"][k].getbbox())
    scale = min((cw - 24) / float(big_w), (ch - 60) / float(big_h), 2.0 if big_h > 150 else 5.0)
    base = Image.new("RGB", (W, H), BG)
    header(ImageDraw.Draw(base), name, "%d 段动作 · 游戏内帧率 · 本屏同一比例" % n, "%d / %d" % (pno + 1, len(pages)))
    bd = ImageDraw.Draw(base)
    for i, c in enumerate(cells):
        x0, y0 = 24 + (i % cols) * cw, 108 + (i // cols) * ch
        bd.rounded_rectangle((x0 + 3, y0 + 3, x0 + cw - 3, y0 + ch - 3), 8, fill=CELL_BG)
        bd.text((x0 + cw // 2, y0 + 8), c["label"], font=f_cell, fill=(255, 244, 214), anchor="ma")
    secs = page_seconds(cells)
    for fr in range(int(FPS * secs)):
        t = fr / FPS
        im = base.copy()
        for i, c in enumerate(cells):
            x0, y0 = 24 + (i % cols) * cw, 108 + (i // cols) * ch
            spr = frame_at(c, t)
            sw, sh = max(1, int(spr.width * scale)), max(1, int(spr.height * scale))
            a = spr.resize((sw, sh), Image.NEAREST)
            ## 按第 0 帧的本体脚底中点对齐(帧条画布大小不同, 不对齐会像站位在跳)
            bb = c["frames"][0].getbbox() or (0, 0, spr.width, spr.height)
            px = x0 + cw // 2 - int((bb[0] + bb[2]) * 0.5 * scale)
            py = y0 + ch - 22 - int(bb[3] * scale)
            im.paste(a, (px, py), a)
        emit(im)
    report.append((name, n, round(secs, 1), [c["label"] for c in cells]))

proc.stdin.close()
proc.wait()
for r in report:
    print(r[0], r[1], "段", r[2], "秒", " / ".join(r[3]))
print("总页", len(report), "总秒", round(sum(r[2] for r in report), 1), "退出码", proc.returncode)
