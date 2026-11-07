"""猎人 / 赌神 / 海盗 + 糖果龟: 排成游戏用的裸帧(新节奏), 落到 seq_raw/<龟>/; 动画自带的飞行道具擦掉(游戏特效已画)"""
import glob, json, os, sys
from collections import deque
from PIL import Image
sys.stdout.reconfigure(encoding="utf-8")
R = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/.out/review/"


def seq(d):
    return [Image.open(p).convert("RGBA") for p in sorted(glob.glob(d + "/f_*.png"))]


def main_only(im, keep=0.12):
    """只留最大连通块 + 大于它 keep 比例的块(飞出去的牌 / 箭 / 碎点全掉)"""
    im = im.copy()
    px = im.load()
    W, H = im.size
    seen = {}
    comps = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3] and (x, y) not in seen:
                q = deque([(x, y)])
                seen[(x, y)] = 1
                c = [(x, y)]
                while q:
                    cx, cy = q.popleft()
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            p = (cx + dx, cy + dy)
                            if 0 <= p[0] < W and 0 <= p[1] < H and p not in seen and px[p][3]:
                                seen[p] = 1
                                c.append(p)
                                q.append(p)
                comps.append(c)
    if not comps:
        return im
    m = max(len(c) for c in comps)
    for c in comps:
        if len(c) < m * keep:
            for p in c:
                px[p] = (0, 0, 0, 0)
    return im


def wipe_above(im, y0):
    im = im.copy()
    px = im.load()
    for y in range(y0):
        for x in range(im.width):
            px[x, y] = (0, 0, 0, 0)
    return im


def shift(im, dx):
    st = Image.new("RGBA", (im.width + 8, im.height), (0, 0, 0, 0))
    st.alpha_composite(im, (4 + dx, 0))
    return st.crop((4, 0, 4 + im.width, im.height))


def wipe_left(im, x0):
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(x0):
            px[x, y] = (0, 0, 0, 0)
    return im


def put(tid, name, frames, fps=15, ox=0, ground=123, rel=-1, cancel=-1):
    d = R + "seq_raw/%s/%s/" % (tid, name)
    os.makedirs(d, exist_ok=True)
    for f in glob.glob(d + "*.png"):
        os.remove(f)
    for i, im in enumerate(frames):
        im.save(d + "f_%02d.png" % i)
    mp = R + "seq_raw/%s/meta.json" % tid
    m = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    m[name] = {"n": len(frames), "fps": fps, "ox": ox, "ground": ground, "rel": rel, "cancel": cancel}
    json.dump(m, open(mp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(tid, name, len(frames), "rel", rel)


## 猎人
D = R + "hunter_sample/"
s = lambda n: seq(D + n)
put("hunter", "待机", s("idle")[:-1], 8)
put("hunter", "走路", s("run2")[:-1], 12)
a = s("attack_pin")
put("hunter", "普攻_射箭", [a[i] for i in (1, 3, 5, 7, 8, 9, 10, 10, 11, 12)], rel=5)
a = s("cast_hunterShot")
put("hunter", "技能_精准射击", [main_only(a[i]) for i in (1, 3, 5, 7, 8, 9, 10, 10, 10, 11, 12, 13, 14, 15, 16)], rel=4, cancel=11)
put("hunter", "技能_隐蔽", s("cast_hunterStealth"), rel=4)
a = [main_only(x) for x in s("cast_hunterBarrage")]
put("hunter", "技能_狩猎弹幕", a[:5] + [a[5], a[6], a[4]] * 9 + a[7:], rel=5, cancel=32)
put("hunter", "被动_闪避", s("dodge"), 18)
put("hunter", "被动_处决", s("passive_exec"), 15)
a = s("death")
put("hunter", "阵亡", [a[i] for i in (5, 7, 8, 9, 10, 12, 13, 14, 16)])

## 赌神
D = R + "gambler_sample/"
s = lambda n: seq(D + n)
put("gambler", "待机", s("idle")[:-1], 8)
put("gambler", "走路", s("run")[:-1], 12)
a = s("attack2")
put("gambler", "普攻_卡牌射击", [a[i] for i in (1, 2, 3, 4, 5, 5, 5, 6, 7, 8)], rel=4)
a = s("joker3")
put("gambler", "技能_万能牌", [a[i] for i in (2, 4, 6, 8, 9, 11, 12)], rel=4)
a = [main_only(x) for x in s("cast_bet")]
a[6] = wipe_left(wipe_above(a[6], 44), 42)
a[7] = wipe_left(wipe_above(a[7], 44), 42)
a[8] = wipe_above(a[8], 44)
put("gambler", "技能_赌注", [a[i] for i in (0, 4, 5, 6, 7, 8, 9, 10, 11, 12)], rel=3)
a = s("cast_wheel")
a = [wipe_above(x, 45) if 3 <= i <= 6 else x for i, x in enumerate(a)]
put("gambler", "技能_命运之轮", a[:7] + [a[5], a[6]] * 4 + [a[6]] + a[7:], rel=4)
put("gambler", "被动_多重打击", s("multi2"), 18)
put("gambler", "被动_登场", s("enter"), 12)
a = s("death")
put("gambler", "阵亡", [a[i] for i in (3, 5, 7, 9, 11, 12, 13, 14, 16)])

## 海盗
D = R + "pirate_sample/"
s = lambda n: seq(D + n)
put("pirate", "待机", s("idle")[:-1], 8)
put("pirate", "走路", s("run")[:-1], 12)
a = s("attack2")
put("pirate", "普攻_弯刀", [a[1], a[2], a[3], a[5], a[7], a[8], shift(a[8], -2), shift(a[8], -3), a[9], a[10], a[11], a[12]], rel=5)
a = s("cast_volley")
put("pirate", "技能_火炮齐射", [a[i] for i in (1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)], rel=4)
put("pirate", "技能_朗姆酒", s("rum3")[:17], rel=4)
a = s("cast_ship")
put("pirate", "技能_海盗船", [a[i] for i in (2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)], rel=4)
put("pirate", "被动_霰弹", s("shot"), 15)
put("pirate", "被动_登场", s("enter"), 12)
a = s("death")
put("pirate", "阵亡", [a[i] for i in (4, 5, 9, 10, 11, 12, 13, 14, 16)])

## 糖果
D = R + "candy_sample/"
s = lambda n: seq(D + n)
sys.path.insert(0, "C:/Users/Louis/AppData/Local/Temp/claude/5a6586b023f62759/a1c0e931-7a92-4ec5-b358-31af224163c8/scratchpad")
from act import L, despeck
bare = s("sweep4")
CP, CT = 80, 12


def cstage(im, dx):
    st = Image.new("RGBA", bare[0].size, (0, 0, 0, 0))
    st.alpha_composite(im, (CP + dx, CT))
    return st


s1, s3 = despeck(L(D, "sw", 1), 14), despeck(L(D, "sw", 3), 14)
new = [bare[1], bare[3], cstage(s1, 6), cstage(s3, -9), bare[4], bare[5], bare[5]] + bare[6:]
put("candy", "待机", s("idle_final"), 8)
put("candy", "走路", s("walk_final"), 12)
put("candy", "普攻_横扫大锤", new, ox=80, ground=135, rel=4)
a = s("q_final3")
put("candy", "技能_糖果锤", a[:6] + [a[5], a[5]] + a[6:], ox=60, ground=123, rel=5, cancel=12)
put("candy", "技能_糖衣炮弹", s("barrage_final"), ox=40, ground=213, rel=4)
put("candy", "技能_糖果炸弹", s("bomb_final"), ox=40, ground=153, rel=5)
put("candy", "被动_甜蜜吸取", s("drain_final"), 12)
put("candy", "阵亡", s("death_final"))
