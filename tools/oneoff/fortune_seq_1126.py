"""fortune_seq_1126.py —— 财神龟重做(方案书 20261126d)的源帧排进 tools/assetgen/pet_seq/fortune/(build_turtle_seq.py 的输入)
来源(如实):
  定稿 fortE_2 = PixelLab create_image_pixen 88×88(只用文字描述, 不挂参照图), 贴进 152×152 帧 = fortE_base(脚底第 147 行)
  待机 = Aseprite 后台脚本 tools/assetgen/ase/fortune_idle.lua 在定稿上逐帧改像素(呼吸 + 墨镜反光), 不是 AI
  其余 6 段 = PixelLab animate_image_pixminimax, 首尾钉定稿(死亡只钉首帧), 8 帧(+ 第 0 帧原图)
排帧:
  攻击: 用 0~4 + 7~8(第 5 / 6 帧 AI 让它转过身去、壳朝前, 违反「不转身」, 删掉); 命中 = 第 4 帧(剑劈到身前)
  攻击 / 招财进宝: 只留跟身体连在一起的像素(AI 自己画的剑弧、白光星、撒出的金币是演示特效, 游戏另有特效画; pet_seq/README「裸帧」)
  骰子: 抛在空中的骰子是动作本身, 保留
一次性; 输出逐字节确定。
"""
import json
import os
import shutil
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "fortune")
DST = os.path.join(ROOT, "tools", "assetgen", "pet_seq", "fortune")
IDLE = os.path.join(ROOT, ".out", "fortune", "idle")
GROUND = 147


def main_body(im: Image.Image) -> Image.Image:
    """只留最大的一块连通像素(身体 + 手上的剑 / 骰子 / 钱袋都连在身上)"""
    im = im.convert("RGBA")
    W, H = im.size
    px = im.load()
    seen = [[False] * W for _ in range(H)]
    best = []
    for y in range(H):
        for x in range(W):
            if seen[y][x] or px[x, y][3] < 128:
                continue
            comp, st = [], [(x, y)]
            seen[y][x] = True
            while st:
                cx, cy = st.pop()
                comp.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and px[nx, ny][3] >= 128:
                        seen[ny][nx] = True
                        st.append((nx, ny))
            if len(comp) > len(best):
                best = comp
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    op = out.load()
    for x, y in best:
        op[x, y] = px[x, y]
    return out


def put(seg: str, frames: list) -> None:
    d = os.path.join(DST, seg)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    for i, im in enumerate(frames):
        im.save(os.path.join(d, "f_%02d.png" % i), optimize=False)


def ai(seg: str, idx: list, clean: bool = False) -> list:
    out = []
    for i in idx:
        im = Image.open(os.path.join(SRC, seg, "f_%d.png" % i)).convert("RGBA")
        out.append(main_body(im) if clean else im)
    return out


def main() -> None:
    os.makedirs(DST, exist_ok=True)
    put("idle", [Image.open(os.path.join(IDLE, "fortune_idle_%02d.png" % i)).convert("RGBA") for i in range(8)])
    put("run", ai("fE_walk", list(range(8))))
    put("attack", ai("fE_atk", [0, 1, 2, 3, 4, 7, 8], clean=True))
    put("death", ai("fE_die", list(range(9))))
    put("cast_fortuneDice", ai("fE_dice", list(range(9))))
    put("cast_fortuneAllIn", ai("fE_allin", list(range(8))))   # 末帧(第 8 帧)AI 画了撒出去的金币 —— 投币由游戏弹道画, 不要
    put("cast_fortuneBuyEquip", ai("fE_buy", list(range(9)), clean=True))
    shutil.copyfile(os.path.join(SRC, "fortE_2.png"), os.path.join(DST, "avatar.png"))
    seg = lambda rel, fps=15: {"cancel": -1, "fps": fps, "ground": GROUND, "ox": 0, "rel": rel}
    meta = {
        "idle": seg(-1, 8), "run": seg(-1, 12), "attack": seg(4), "death": seg(-1),
        "cast_fortuneDice": seg(4), "cast_fortuneAllIn": seg(5), "cast_fortuneBuyEquip": seg(4),
    }
    json.dump(meta, open(os.path.join(DST, "seq.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    ## 头像框(avatar_heads.json 里 fortune 那一项手改: src = pet_seq/fortune/avatar.png, k 1, box [14, 6, 38] = 88×88 源图里头部含墨镜)
    print("ok")


if __name__ == "__main__":
    main()
