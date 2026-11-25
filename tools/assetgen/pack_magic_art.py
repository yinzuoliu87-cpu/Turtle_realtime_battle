"""pack_magic_art.py —— 魔法书羁绊(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md)的美术打包

来源(如实, 没有一张是手画的):
  · 装备图标 117–126 / 类型标签: PixelLab create_image_pro_flash 64×64 / 32×32。
    117–121 风格锚 = 110 苦无图标; 122–126 风格锚 = 119 烈焰法典(同一套书的样子); 标签无锚。原图在 ai_src/magic/icon*.png / tagmagic.png
  · 123 亡者之书三种骷髅龟: 待机原画 = create_image_pro_flash 112×112(风格锚 = 115 暗影忍者待机原画 eq-ninja-idle 第 0 帧, 写明严格侧面朝左);
    骷髅祭司的头第一版画成了活龟的光头 ⇒ edit_image_pro_flash 只改头成骷髅(skp_0b)。
    关键姿势 kw_* / km_* / kp_* = edit_image_pro_flash 从各自原画改出来(写明严格侧面朝左、两手两脚);
    关键姿势之间 = animate_image 首尾钉住两张关键姿势生成(序号 0 = 输入原画, 不取); 待机 / 走路 = animate_image 首尾都钉原画。
    自查后弃用的帧(如实): 战士横斩第二段开头两格剑弹回竖直(kwa_b_1/2) · 横斩第二段第 3 格剑竖回脸前(kwa_b_3, 轨迹倒退) · 战士狂怒第 2 格全身被刷成绿色(kwr_up_2) ·
    法师普攻第一版三格大块纯白拖影(kma_cast_*, 重生成为 kma2_cast_*, 仍有一格拖影 kma2_cast_2 不取) · 法师举杖第一版三格白云(kms_up_*, 重生成为 kms2_up_*)。
    祭司甩灯蓄力三格头顶多画了一个青色法阵圈(与身体不相连的独立块) ⇒ DROP_FLOATERS 去掉「整块都在 y ≤ 40 的非身体块」。
  · 特效: PixelLab 特效工作台(vfx_workbench)的预设改配色 / 改参数后导出的网格表 + 逐帧坐标 json, 在 ai_src/magic_vfx/(导出 id 记在 exports.txt);
    一次性的去掉末尾全透明帧, 循环的原样保留。打印出来的表行(帧宽 / 帧高 / 内容直径 / 锚点)抄进 MagicEqVfx.MSHEETS。
  · 126 书页: create_image_pro_flash 64×64(无锚, 11-25 第二版: 青色符文的书页), ai_src/magic/page2.png → vfx/magic-page.png
  · 125 禁咒书: create_image_pro_flash 64×64(无锚, 翻开的品红禁咒书), ai_src/magic/forbook.png → vfx/magic-forbook.png;
    悬浮 / 飞行的上下浮动、翻转是引擎里按时间摆位置 / 缩放(不是逐帧画的)
  · 【飞弹】光尾段: 工作台 beam 图层画的竖光带, 裁中段转横(见 main 里那一段注释)。
本脚本只做拷贝 / 拼接 / 去碎块, 重跑逐字节相同。

    python tools/assetgen/pack_magic_art.py
"""
import json, os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AI = os.path.join(ROOT, "tools", "assetgen", "ai_src", "magic")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")

ICONS = {"icon%d" % i: "p2eq_%d" % i for i in range(117, 127)}
TAG = {"tagmagic": "tag-magicbook"}
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
FW = 112

## 骷髅帧条(源名; 拼成横条 112 方帧)。命中 / 出招帧下标(从 0 数)抄到 AttackHits(普攻)与 MagicEqVfx.SKEL_SKILL_HIT(技能)
SKEL_SEQ = {
    "eq-skelw-idle": ["skw_idle_%d" % i for i in range(0, 6)],
    "eq-skelw-walk": ["skw_walk_%d" % i for i in range(1, 9)],
    ## 横斩: 剑收到头后 → 举过头顶竖直 → 斜指前上(kw_mid) → 劈到前下 → ★横平指敌人 → 收势
    "eq-skelw-attack": ["kwa_wind_%d" % i for i in range(1, 5)] + ["kwa_a_%d" % i for i in range(1, 5)] + ["kwa_b_4"]
                       + ["kwa_rec_%d" % i for i in range(1, 5)],
    ## 骸骨狂怒: 举剑 → ★仰头怒吼、眼冒绿火 → 收剑
    "eq-skelw-skill": ["kwr_up_1", "kwr_up_3", "kwr_up_4"] + ["kwr_dn_%d" % i for i in range(1, 5)],
    "eq-skelm-idle": ["skm_idle_%d" % i for i in range(0, 6)],
    "eq-skelm-walk": ["skm_walk_%d" % i for i in range(1, 9)],
    ## 暗影弹: 杖收到身后 → 甩过头顶 → ★杖前刺指敌人 → 收杖
    "eq-skelm-attack": ["kma_wind_%d" % i for i in range(1, 5)] + ["kma2_cast_1", "kma2_cast_3", "kma2_cast_4"]
                       + ["kma_rec_%d" % i for i in range(1, 5)],
    ## 骨火爆裂: 站直双手举杖 → ★杖头火团最大 → 放下
    "eq-skelm-skill": ["kms2_up_%d" % i for i in range(1, 5)] + ["kms_dn_%d" % i for i in range(1, 5)],
    "eq-skelp-idle": ["skp_idle_%d" % i for i in range(0, 6)],
    "eq-skelp-walk": ["skp_walk_%d" % i for i in range(1, 9)],
    ## 甩灯: 灯甩到身后 → 绕前 → ★手臂前伸、灯冲敌人亮 → 收回
    "eq-skelp-attack": ["kpa_wind_%d" % i for i in range(1, 5)] + ["kpa_cast_%d" % i for i in range(1, 5)]
                       + ["kpa_rec_%d" % i for i in range(1, 5)],
    ## 亡灵浪潮: 下蹲 → ★双手前推、青色浪涌 → 收势
    "eq-skelp-skill": ["kps_up_%d" % i for i in range(1, 5)] + ["kps_dn_%d" % i for i in range(1, 5)],
}
SKEL_HIT = {"eq-skelw-attack": 8, "eq-skelm-attack": 6, "eq-skelp-attack": 7,
            "eq-skelw-skill": 2, "eq-skelm-skill": 3, "eq-skelp-skill": 3}
DROP_FLOATERS = {"kpa_wind_1", "kpa_wind_2", "kpa_wind_3"}
## 每种骷髅所有帧同一个下移量(按待机原画最低一行贴到帧底, 同暗影忍者), 换表不跳
FOOT_REF = {"eq-skelw": "skw_0", "eq-skelm": "skm_0", "eq-skelp": "skp_0b"}

AIV = os.path.join(ROOT, "tools", "assetgen", "ai_src", "magic_vfx")
VFX_SHEETS = ["magic-missile-orb", "magic-missile-hit", "magic-note-bolt", "magic-note-hit", "magic-fire-head", "magic-fire-hit3", "magic-fire-cast", "magic-fire-ember",
              "magic-frost-e", "magic-frost-shard", "magic-storm-bolt", "magic-holy-chest", "magic-scroll-shield", "magic-skel-rise", "magic-skel-crumble",
              "magic-skel-blast", "magic-skel-wave", "magic-wave-hit", "magic-wave-heal", "magic-mirror-shatter",
              "magic-forbidden-blast", "magic-page-cut", "magic-page-block", "magic-tome-hp", "magic-skelm-bolt", "magic-skelp-bolt"]
VFX_LOOPS = {"magic-missile-orb", "magic-note-bolt", "magic-fire-head", "magic-holy-chest", "magic-scroll-shield", "magic-skel-wave",
             "magic-skelm-bolt", "magic-skelp-bolt"}
## 锚点改写(工作台导出的锚点是效果原点, 不是要对准的那一点): 122 胸口绿光 = 光团中心(逐帧量绿芯质心 ≈ (20, 30))
ANCHOR_FIX = {"magic-holy-chest": (20, 30)}


def _drop_floaters(im, ymax=40):
    """去掉与身体(最大连通块)不相连、且整块都在 y ≤ ymax 的碎块(头顶多画的法阵圈)"""
    px = im.load()
    w, h = im.size
    seen = set()
    comps = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 or (x, y) in seen:
                continue
            st = [(x, y)]
            seen.add((x, y))
            c = []
            while st:
                a, b = st.pop()
                c.append((a, b))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = a + dx, b + dy
                        if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3] > 0:
                            seen.add((nx, ny))
                            st.append((nx, ny))
            comps.append(c)
    comps.sort(key=len, reverse=True)
    for c in comps[1:]:
        if max(p[1] for p in c) <= ymax:
            for q in c:
                px[q] = (0, 0, 0, 0)
    return im


def _strip(names, dy=0):
    out = Image.new("RGBA", (FW * len(names), FW), (0, 0, 0, 0))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(AI, n + ".png")).convert("RGBA")
        assert im.size == (FW, FW), (n, im.size)
        if n in DROP_FLOATERS:
            im = _drop_floaters(im)
        out.paste(im, (i * FW, dy))
    return out


def _vfx(name):
    sheet = Image.open(os.path.join(AIV, name + ".png")).convert("RGBA")
    meta = json.load(open(os.path.join(AIV, name + ".json"), encoding="utf-8"))
    frames = []
    for f in meta["frames"]:
        r = f["frame"]
        frames.append(sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
    if name not in VFX_LOOPS:
        while len(frames) > 1 and frames[-1].getbbox() is None:
            frames.pop()
    w, h = frames[0].size
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    diam = 0
    for i, f in enumerate(frames):
        out.paste(f, (i * w, 0))
        bb = f.getbbox()
        if bb:
            diam = max(diam, bb[2] - bb[0], bb[3] - bb[1])
    out.save(os.path.join(VFX, name + ".png"), optimize=False)
    an = meta["meta"]["anchor"]
    if name in ANCHOR_FIX:
        an = {"x": ANCHOR_FIX[name][0], "y": ANCHOR_FIX[name][1]}
    return '\t"%s": ["vfx/%s.png", %d, %d, %.1f, %d, %d],   # %d 帧%s' % (
        name[6:], name, w, h, float(diam), int(an["x"]), int(an["y"]), len(frames), " · 循环" if name in VFX_LOOPS else "")


def main():
    for src, dst in ICONS.items():
        shutil.copyfile(os.path.join(AI, src + ".png"), os.path.join(EQ, dst + ".png"))
    for src, dst in TAG.items():
        shutil.copyfile(os.path.join(AI, src + ".png"), os.path.join(TAGS, dst + ".png"))
    for dst, names in SKEL_SEQ.items():
        ref = Image.open(os.path.join(AI, FOOT_REF[dst[:8]] + ".png")).convert("RGBA")
        _strip(names, FW - ref.getbbox()[3]).save(os.path.join(VFX, dst + ".png"), optimize=False)
    rows = [_vfx(n) for n in VFX_SHEETS]
    Image.open(os.path.join(AI, "page2.png")).convert("RGBA").save(os.path.join(VFX, "magic-page.png"), optimize=False)
    Image.open(os.path.join(AI, "forbook.png")).convert("RGBA").save(os.path.join(VFX, "magic-forbook.png"), optimize=False)
    ## 125 禁咒书飞行光尾: 蓝光尾逐色换成品红(同一条光带的形状, 只改四个颜色)
    pal = {(58, 94, 224, 255): (112, 18, 104, 255), (127, 176, 255, 255): (214, 58, 196, 255), (214, 232, 255, 255): (255, 168, 238, 255)}
    tr = Image.open(os.path.join(AIV, "magic-missile-trail.png")).convert("RGBA").crop((0, 10, 24, 18)).transpose(Image.Transpose.ROTATE_90)
    tr.putdata([pal.get(c, c) for c in tr.getdata()])
    tr.save(os.path.join(VFX, "magic-forb-trail.png"), optimize=False)
    ## 119 火球光尾: 同一条光带换成灰白(颜色在引擎里按年龄从粉 → 红 → 暗紫插值, 贴安妮 Q 视频「头粉尾红」)
    grey = {(58, 94, 224, 255): (92, 92, 104, 255), (127, 176, 255, 255): (168, 168, 180, 255), (214, 232, 255, 255): (226, 226, 232, 255)}
    tg = Image.open(os.path.join(AIV, "magic-missile-trail.png")).convert("RGBA").crop((0, 10, 24, 18)).transpose(Image.Transpose.ROTATE_90)
    tg.putdata([grey.get(c, c) for c in tg.getdata()])
    tg.save(os.path.join(VFX, "magic-glow-trail.png"), optimize=False)
    ## 羁绊【飞弹】光尾段: 工作台导出的竖光带(24×32, 上端圆头)只取长度方向一致的第 10–17 行, 转成「沿路径 = 横向」的 8×24
    ##   (引擎里每个 sim 步铺一段, 按路径方向转、按段长拉伸; 圆头那几行会在段与段接缝处出现亮点, 不取)
    for tn in ["magic-missile-trail"]:   # 蓝(羁绊飞弹 / 学徒笔记); 119 火球改用下面的灰白光带(引擎里按年龄染色)
        Image.open(os.path.join(AIV, tn + ".png")).convert("RGBA").crop((0, 10, 24, 18)).transpose(Image.Transpose.ROTATE_90).save(
            os.path.join(VFX, tn + ".png"), optimize=False)
    print("图标 %d 张 + 标签 %d 张 + 骷髅帧条 %d 条 + 特效 %d 张 + 书页 1 张" % (len(ICONS), len(TAG), len(SKEL_SEQ), len(rows)))
    print("\n".join(rows))


if __name__ == "__main__":
    main()
