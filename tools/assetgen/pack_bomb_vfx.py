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
    "cannon-heavy-shell": "bomb-cannon-shell",  # 105 重炮弹: 带火焰尾巴的炮弹(循环)         # 104 定时炸弹: 红闪 + 准星环 + 火团(与手雷火球区分)           # 102 地雷: 地底炸起(火 + 泥土碎石 + 尘团), 与手雷的纯火焰区分
}
## 召唤物待机表(PixelLab animate_image 首尾钉住同一张原画生成 7 帧; 原画是 create_image_pro_from_style 候选):
##   ai_src/bomb_summons/<名>_<0..6>.png → assets/sprites/vfx/<产出>.png 横排
SUMMONS = {"cannon": ("eq-cannon-idle", 7), "remote": ("eq-remote-bomb-idle", 7), "katana": ("eq-katana-idle", 7),
           "cannonfire": ("eq-cannon-fire", 6)}   # 炮筒开炮 6 帧(animate_image 首尾钉住待机原画: 炮口喷火→后坐→回位, 11-24 用户「炮台攻击动画呢」)
## 101 粘弹的粘液摊(11-24 重做, 用户「没有商业的感觉」): create_image_pro_from_style 8 张候选里挑的 1 号
##   + animate_image 首尾钉住同一张生成冒泡帧; 取 0..7(第 8 张 = 第 0 张, 循环不重复取)
EXTRA = {"bomb_goo/goo": ("bomb-goo-splat", 8)}
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
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        p = os.path.join(DST, dst + ".png")
        strip.save(p, optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, len(frames)))
    for src, (dst, n) in SUMMONS.items():
        frames = [Image.open(os.path.join(ROOT, "tools", "assetgen", "ai_src", "bomb_summons", "%s_%d.png" % (src, i))).convert("RGBA") for i in range(n)]
        w, h = frames[0].size
        ## ★落地(11-24 用户「炮台召唤物怎么看着飞起来的」): 原画底下有透明留白(炮筒 11 行 / 武士刀 17 行),
        ##   召唤物按帧底边贴地 ⇒ 整只悬空。所有帧同一个量往下挪, 让最低的那一行有画的像素贴到帧底。
        low = max((f.getbbox() or (0, 0, 0, h))[3] for f in frames)
        dy = h - low
        if dy > 0:
            moved = []
            for f in frames:
                g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                g.paste(f, (0, dy))
                moved.append(g)
            frames = moved
        strip = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        strip.save(os.path.join(DST, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, n))
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
