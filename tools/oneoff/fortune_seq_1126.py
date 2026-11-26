"""fortune_seq_1126.py —— 财神龟重做(方案书 20261126d)的源帧排进 tools/assetgen/pet_seq/fortune/(build_turtle_seq.py 的输入)
来源(如实):
  定稿 fortE_2 = PixelLab create_image_pixen 88×88(只用文字描述, 不挂参照图), 贴进 152×152 帧 = fortE_base(脚底第 147 行)
  待机 = Aseprite 后台脚本 tools/assetgen/ase/fortune_idle.lua 在定稿上逐帧改像素(呼吸 + 墨镜反光), 不是 AI
  其余 6 段 = PixelLab animate_image_pixminimax, 首尾钉定稿(死亡只钉首帧), 8 帧(+ 第 0 帧原图)
排帧:
  攻击: 用 0~4 + 7~8(第 5 / 6 帧 AI 让它转过身去、壳朝前, 违反「不转身」, 删掉); 命中 = 第 4 帧(剑劈到身前)
  攻击 / 招财进宝: 只留跟身体连在一起的像素(AI 自己画的剑弧、白光星、撒出的金币是演示特效, 游戏另有特效画; pet_seq/README「裸帧」)
  骰子: 抛在空中的骰子是动作本身, 保留
  11-26 深夜自查(拼图逐帧看)补两处:
  · 攻击命中帧(原第 4 帧)AI 画的剑弧跟剑连成一块, 连通块清不掉 ⇒ 按区域擦掉剑弧(头顶以上 / 头左侧 / 手左下),
    再从待机第 0 帧拷剑身(护手 → 剑尖, 斜向左下)贴到手上 —— 脚本拷像素, 不是重画
  · 招财进宝原第 2~4 帧有 AI 画的大白星 / 小闪光(第 2 帧整张脸被星盖住, 第 4 帧闪光压在壳边上, 擦了会在壳上开洞)⇒ 删掉, 第 5 帧(同一举剑姿势、干净)停三拍
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


def fix_hit(im: Image.Image) -> Image.Image:
    """攻击命中帧: 擦剑弧 + 从待机帧拷剑身(坐标在 4 倍网格图上量的, 152 帧坐标)"""
    im = im.copy()
    px = im.load()
    for y in range(152):
        for x in range(152):
            if y <= 81 or (x <= 63 and 82 <= y <= 111) or (x <= 58 and 112 <= y <= 131):
                px[x, y] = (0, 0, 0, 0)
    for y in range(82, 89):             # 头顶左角压着的一截剑弧: 只擦非绿、非暗描边的像素
        for x in range(63, 73):
            c = px[x, y]
            if c[3] >= 128 and not (c[1] > c[0] and c[1] > c[2]) and sum(c[:3]) > 150:
                px[x, y] = (0, 0, 0, 0)
    idle = Image.open(os.path.join(IDLE, "fortune_idle_00.png")).convert("RGBA").load()
    dx, dy = -7, -6                     # 待机护手(66,125) → 命中帧手里(59,119)
    for y in range(118, 147):
        for x in range(44, 67):
            c = idle[x, y]
            if c[3] < 128 or (c[1] > c[0] and c[1] > c[2] + 20):   # 跳过透明与绿色(手)
                continue
            px[x + dx, y + dy] = c
    return im


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
    atk = ai("fE_atk", [0, 1, 2, 3, 4, 7, 8], clean=True)
    atk[4] = fix_hit(atk[4])
    put("attack", atk)
    put("death", ai("fE_die", list(range(9))))
    put("cast_fortuneDice", ai("fE_dice", list(range(9))))
    put("cast_fortuneAllIn", ai("fE_allin", list(range(8))))   # 末帧(第 8 帧)AI 画了撒出去的金币 —— 投币由游戏弹道画, 不要
    put("cast_fortuneBuyEquip", ai("fE_buy", [0, 1, 5, 5, 5, 6, 7, 8], clean=True))
    shutil.copyfile(os.path.join(SRC, "fortE_2.png"), os.path.join(DST, "avatar.png"))
    seg = lambda rel, fps=15: {"cancel": -1, "fps": fps, "ground": GROUND, "ox": 0, "rel": rel}
    meta = {
        "idle": seg(-1, 8), "run": seg(-1, 12), "attack": seg(4), "death": seg(-1),
        "cast_fortuneDice": seg(4), "cast_fortuneAllIn": seg(5), "cast_fortuneBuyEquip": seg(3),
    }
    json.dump(meta, open(os.path.join(DST, "seq.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    ## 头像框(avatar_heads.json 里 fortune 那一项手改: src = pet_seq/fortune/avatar.png, k 1, box [14, 6, 38] = 88×88 源图里头部含墨镜)
    print("ok")


if __name__ == "__main__":
    main()
