"""pack_bomb_vfx.py —— 炸弹羁绊 / 武士刀 特效序列帧打包(2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md)

来源(如实): tools/assetgen/ai_src/bomb_vfx/*.png + *.json —— PixelLab「特效工作台」(vfx_workbench)按预设 / 部件
  渲染导出的像素特效表(网格排布 + 逐帧坐标 json); 改过配色 / 删过图层, 不是手画。
本脚本: 按 json 逐帧切出 → 去掉末尾全透明帧 → 横排成一条(hframes = 帧数) → assets/sprites/vfx/<名>.png。
确定性: 只做裁切与拼接, 重跑逐字节相同。

    python tools/assetgen/pack_bomb_vfx.py
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_vfx")
DST = os.path.join(ROOT, "assets", "sprites", "vfx")

## 源名 → 产出名
JOBS = {
    "bomb-blast-std": "bomb-blast-std",
    "bomb-blast-big": "bomb-blast-big",
    "bomb-goo-puddle": "bomb-goo-puddle",
    "katana-wave": "katana-wave",
    "cracker-pop": "bomb-cracker-pop",
    "smoke-bomb-cloud": "bomb-smoke-cloud",
    "bomb-missile-strike": "bomb-missile-strike",
    "tube-crackle": "bomb-tube-crackle",
    "barrel-boom": "bomb-barrel-boom",
    "cannon-muzzle": "bomb-cannon-muzzle",
    "katana-charge": "katana-charge",
    "cracker-spark": "bomb-cracker-spark",     # 097 鞭炮连炸的每一响(11-24 重做: 用户「感觉这个特效不行」)
    "cracker-paper": "bomb-cracker-paper",     # 097 鞭炮红纸屑
    "mine-blast": "bomb-mine-blast",
    "timer-blast": "bomb-timer-blast",
    "cannon-heavy-shell": "bomb-cannon-shell",
    "remote-blast": "bomb-remote-blast",
    "katana-hslash": "katana-hslash",          # 107 小将普攻横斩刀光(11-25 特效工作台 slash_trail 部件: 压扁成横向、钢白配色)       # 106 遥控炸弹专属爆炸(11-24: 蘑菇云 + 地面一圈火团铺满 600 码, 不再借炸药桶的大爆炸)
}
## 召唤物待机表(PixelLab animate_image 首尾钉住同一张原画生成 7 帧; 原画是 create_image_pro_from_style 候选):
##   ai_src/bomb_summons/<名>_<0..6>.png → assets/sprites/vfx/<产出>.png 横排
SUMMONS = {"cannon": ("eq-cannon-idle", 7), "remote": ("eq-remote-bomb-idle", 7), "katana": ("eq-katana-idle", 7),
           "cannonfire": ("eq-cannon-fire", 6),
           ## 重炮形态(11-24 用户「武器进入强化形态…应该武器会有什么变化」): 原画 = cannonheavy_base(edit_image_pro_flash 从炮台原画改: 炮管烧红+裂纹+钢箍)
           "cannonheat": ("eq-cannon-heat", 7),     # 变身: 普通 → 烧红(animate_image 首=普通原画 尾=强化原画)
           "cannonhidle": ("eq-cannon-hidle", 4),   # 强化待机: 裂纹明暗呼吸(生成的 6 帧里 3~5 帧炮管变黑, 只取 0→1→2→1)
           "cannonhfire": ("eq-cannon-hfire", 7)}   # 强化开炮: 喷火→重后坐→回位(炮尾冒火的几帧擦掉)   # 炮筒开炮 6 帧(animate_image 首尾钉住待机原画: 炮口喷火→后坐→回位, 11-24 用户「炮台攻击动画呢」)
## 101 粘弹的粘液摊(11-24 重做, 用户「没有商业的感觉」): create_image_pro_from_style 8 张候选里挑的 1 号
##   + animate_image 首尾钉住同一张生成冒泡帧; 取 0..7(第 8 张 = 第 0 张, 循环不重复取)
EXTRA = {"bomb_goo/goo": ("bomb-goo-splat", 8)}
## 生成帧的手工修正(11-24 用户「从待机到整个动作，自己看看合适嘛」自查):
##   · 炮筒待机: 生成的「炮口冒烟」冒在了炮尾 ⇒ 不要烟, 每帧都用原画(静止)
##   · 炮筒开炮: 第 3 帧炮口一个红圈 + 炮尾一团闪光(生成错误) ⇒ 整帧不要; 第 4 帧(后坐上翘)炮尾 22 个火星像素擦掉;
##     顺序 = 喷火(1) → 大火光(2) → 后坐(4 擦净) ×2 → 原画(0)
def _erase_hot(img, x0):
    img = img.copy()
    px = img.load()
    for y in range(img.height):
        for x in range(x0, img.width):
            r, g, b, a = px[x, y]
            if a and ((r > 200 and g > 150) or (r > 170 and g < 110 and b < 110)):
                px[x, y] = (0, 0, 0, 0)
    ## 再去掉孤立的散点(四周 8 格里最多 1 个有画的 = 飞出来的火星残渣)
    src = img.copy().load()
    for y in range(img.height):
        for x in range(img.width):
            if src[x, y][3] == 0:
                continue
            nb = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if (dx or dy) and 0 <= x + dx < img.width and 0 <= y + dy < img.height and src[x + dx, y + dy][3] > 0:
                        nb += 1
            if nb <= 1:
                px[x, y] = (0, 0, 0, 0)
    return img
## 107 武士刀小将的动作(11-25 用户「武士这个动作…普通攻击应该是一个横横斩…把刀放下，然后往上挥出一道这个气波…
##   强化形态下…一套序列动作…刀会放到这个左身方，然后这样子挥出去，挥出这个龙卷风」):
##   做法(如实): 关键姿势 = PixelLab edit_image_pro_flash 从待机原画改出来(katkey_low 刀尖压地 / katkey_up 上挑后刀指天 /
##   katkey_coil 蹲低收刀到身侧 / katkey_high 甩完刀举过头顶); 关键姿势之间的帧 = animate_image 首尾钉住两张关键姿势生成;
##   横斩 = animate_image 首尾钉住待机原画(第二版, 身体转得多)。每段按下表挑帧拼(序号 = 生成结果的第几张, 0 = 输入原画不要)。
##   所有段与待机同一个下移量(KATANA_DY), 换表不跳。
KATANA_SEQ = {
    ## 横斩(11-25 第五版): 用户「你不是量了吗？就看它到底有没有从一边横扫到另外一边啊？那很明显是没有」——
    ##   前几版是生成器在关键姿势之间补帧, 刀一帧之间直接翻 166°(跳过去, 不是扫过去), 拖尾把跳变盖住了。
    ##   这一版不让生成器补扫刀的帧: 每隔约 45° 单独定一张姿势(PixelLab edit_image_pro_flash 从待机原画改, 每张写明刀指向哪):
    ##   kathw05 刀竖直举起 → kathw1 右上 → kath0 正右 → kath05 右下(半朝镜头) → kath1 正对镜头(刀缩成一小截) →
    ##   kath15 左下(半朝镜头) → katkey_s2b 正左(命中, 下标 6) → kath25 绕到左肩后; 收刀 khr_1..3 = animate_image(kath25 → 待机)。
    ##   刀尖沿椭圆下半边从右走到左(tools/oneoff/sweep_check.py 逐帧量): (93,75) → (51,69) → (15,70) → (3,51)。
    "eq-katana-attack": ["kathw05", "kathw1", "kath0", "kath05", "kath1", "kath15", "katkey_s2b", "kath25", "khr_1", "khr_2", "khr_3"],
    "eq-katana-walk": ["katwalk_%d" % i for i in range(1, 9)],                           # 走路循环 8 帧(首尾钉住待机原画生成)
    ## 上挑: katup_3 不要(刀身画成一团往身后飞的白雾, 方向反了) ⇒ 刀尖压地后一下挑到指天; 第 6 帧(刀指天)出波
    "eq-katana-rise": ["katlow_%d" % i for i in range(1, 5)] + ["katup_1", "katup_2", "katup_4"]
                      + ["katuprec_%d" % i for i in range(1, 4)],
    "eq-katana-coil": ["katcoil_%d" % i for i in range(1, 7)],                           # 蹲低收刀到身侧
    "eq-katana-hold": ["kathold_%d" % i for i in range(1, 4)],                           # 蓄力循环(身边风丝)
    "eq-katana-release": ["katrel_%d" % i for i in range(1, 7)] + ["katrec_%d" % i for i in range(1, 4)],   # 绕身甩刀(第 4 帧甩出龙卷风) → 刀举过头顶 → 收刀
}
## 横斩刀光拖尾画进帧(tools/assetgen/katana_trail.py): 段名 → (从第几帧画, 画到第几帧)
KATANA_TRAIL = {"eq-katana-attack": (3, 7)}   # 下标 3(正右 → 右下) 到 7(正左 → 绕到肩后)
KATANA_DY = 112 - Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_summons", "katana_0.png")).convert("RGBA").getbbox()[3]
## 炮筒原画底下空 11 行(见下方「落地」): 所有炮筒动作一律挪这么多
CANNON_DY = 64 - Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_summons", "cannon_0.png")).convert("RGBA").getbbox()[3]
CLEAN = {
    "cannon": lambda fs: [fs[0]] * len(fs),
    "cannonhfire": lambda fs: [fs[1], _erase_hot(fs[2], 48), _erase_hot(fs[3], 48), _erase_hot(fs[4], 48), fs[5], fs[6]],
    "cannonfire": lambda fs: [fs[1], fs[2], _erase_hot(fs[4], 50), _erase_hot(fs[4], 50), fs[0]],
}
## 擦掉帧中心一圈(11-25 自查): 107 蓄力的聚气粒子图正中心有一个光点, 放大到小将身上成了一块压在身上的蓝方块;
##   只留往里收的风粒子。值 = (中心 x, 中心 y, 半径)
CLEAR_CENTER = {"katana-charge": (33, 33, 9)}
## 循环播放的不去尾帧(循环要首尾相接)
LOOPS = {"bomb-goo-puddle", "cannon-heavy-shell"}


def main() -> None:
    out = []
    for src, dst in JOBS.items():
        sheet = Image.open(os.path.join(SRC, src + ".png")).convert("RGBA")
        meta = json.load(open(os.path.join(SRC, src + ".json"), encoding="utf-8"))
        frames = []
        for f in meta["frames"]:
            r = f["frame"]
            frames.append(sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
        if src not in LOOPS:
            while len(frames) > 1 and frames[-1].getbbox() is None:
                frames.pop()
        if src in CLEAR_CENTER:
            cx, cy, cr = CLEAR_CENTER[src]
            for fr in frames:
                px = fr.load()
                for y in range(fr.height):
                    for x in range(fr.width):
                        if (x - cx) ** 2 + (y - cy) ** 2 <= cr * cr:
                            px[x, y] = (0, 0, 0, 0)
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        p = os.path.join(DST, dst + ".png")
        strip.save(p, optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, len(frames)))
    for src, (dst, n) in SUMMONS.items():
        frames = [Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_summons", "%s_%d.png" % (src, i))).convert("RGBA") for i in range(n)]
        frames = CLEAN.get(src, lambda fs: fs)(frames)
        w, h = frames[0].size
        ## ★落地(11-24 用户「炮台召唤物怎么看着飞起来的」): 原画底下有透明留白(炮筒 11 行 / 武士刀 17 行),
        ##   召唤物按帧底边贴地 ⇒ 整只悬空。所有帧同一个量往下挪, 让最低的那一行有画的像素贴到帧底。
        low = max((f.getbbox() or (0, 0, 0, h))[3] for f in frames)
        dy = h - low
        if src.startswith("cannon"):
            dy = CANNON_DY   # 炮筒所有动作同一个下移量(按原画算), 换表不跳
        if src == "katana":
            dy = KATANA_DY   # 待机与各动作同一个下移量
        if dy > 0:
            moved = []
            for f in frames:
                g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                g.paste(f, (0, dy))
                moved.append(g)
            frames = moved
        n = len(frames)
        strip = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        strip.save(os.path.join(DST, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, n))
        if src == "cannonheat":   # 退出强化 = 变身倒着播(冷却回黑铁)
            rev = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
            for i, fr in enumerate(reversed(frames)):
                rev.paste(fr, (i * w, 0))
            rev.save(os.path.join(DST, "eq-cannon-cool.png"), optimize=False)
            out.append("eq-cannon-cool %dx%d x%d" % (w, h, n))
    for dst, names in KATANA_SEQ.items():
        frames = []
        for nm in names:
            f = Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_summons", nm + ".png")).convert("RGBA")
            g = Image.new("RGBA", f.size, (0, 0, 0, 0))
            g.paste(f, (0, KATANA_DY))
            frames.append(g)
        if dst in KATANA_TRAIL:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import katana_trail
            frames, _ = katana_trail.apply(frames, *KATANA_TRAIL[dst])
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        strip.save(os.path.join(DST, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, len(frames)))
    for src, (dst, n) in EXTRA.items():
        frames = [Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "%s_%d.png" % (src, i))).convert("RGBA") for i in range(n)]
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        strip.save(os.path.join(DST, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, n))
    print("\n".join(out))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
