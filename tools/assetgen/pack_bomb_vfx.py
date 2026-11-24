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
}
## 召唤物待机表(PixelLab animate_image 首尾钉住同一张原画生成 7 帧; 原画是 create_image_pro_from_style 候选):
##   ai_src/bomb_summons/<名>_<0..6>.png → assets/sprites/vfx/<产出>.png 横排
SUMMONS = {"cannon": ("eq-cannon-idle", 7), "remote": ("eq-remote-bomb-idle", 7), "katana": ("eq-katana-idle", 7)}
## 循环播放的不去尾帧(循环要首尾相接)
LOOPS = {"bomb-goo-puddle"}


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
        strip = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * w, 0))
        strip.save(os.path.join(DST, dst + ".png"), optimize=False)
        out.append("%s %dx%d x%d" % (dst, w, h, n))
    print("\n".join(out))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
