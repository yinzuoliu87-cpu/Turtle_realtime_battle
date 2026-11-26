"""pack_mask_art.py —— 面具羁绊(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)的美术打包

来源(如实, 没有一张是手画的):
  · 装备图标 127–136: PixelLab create_image_pro_flash 64×64, 风格锚 = 110 苦无图标(与魔法书批同一锚); 类型标签 32×32, 风格锚 = 魔法书标签。
    原图在 ai_src/mask/icon*.png / tagmask.png。
  · 130 舞狮: 原画 = create_image_pro_flash 112×112(无锚, 写明严格侧面朝左) lion_0.png;
    待机 / 走路 / 咬 = animate_image 首尾都钉原画(序号 0 = 输入原画); 冲撞 = animate_image 只钉首帧。
  · 135 金光第一版(11-26 用户说敷衍, 已弃): gold_beam.png / gold_ground.png 原图留在 ai_src, 不再打包。
    面具升空用的是 135 自己的图标; 光柱的伸缩 / 跟随 / 变亮是引擎里按时间摆(不是逐帧画的)。
  · 136 里世界场景: 地砖 ow_tile(64×64) / 法阵 ow_circle(256×256) / 断柱 ow_pillar / 巨面具两种 ow_maskA·B(128×128) / 鬼火灯台 ow_brazier(48×96)
    = create_image_pro_flash(无锚); 巨面具与鬼火 = animate_image 首尾钉原画 8 帧(owA_0..7 / owB_0..7 / owF_0..7, 序号 8 = 钉住的末帧不取)。
    平台椭圆裁切 / 边缘碎口 / 变暗是着色器(otherworld_ground.gdshader); 摆位见 OtherworldStage。
  · 11-26 第二轮(用户看过参考后): 135 金光照云顶雷欧娜(docs/studies/20261126-参考-云顶雷欧娜金光.md) ——
    锁定圈 gl_ring / 三层光柱 gl_beam / 底部飞溅 gl_splash / 收尾烟 gl_smoke = create_image_pro_flash(无锚);
    光柱 / 飞溅 = animate_image 首尾钉原画 6 帧(glb_0..5 / gls_0..5); 烟 = animate_image 只钉首帧(glk_1..6)。
    136 千面演出照莫德凯撒 R(docs/studies/20261126-参考-莫德凯撒R死亡之境.md) —— 面具印记 ow_sigil2 / 鬼手 ow_hand / 紫雾 ow_mist /
    裂隙 ow_rift / 魂流 ow_wisp / 光环 ow_aura2 / 回落光柱 ow_pillar2 = create_image_pro_flash(无锚), 各自 animate_image;
    自查弃用(如实): 裂隙第 2、3 帧多一圈白描边(owr_2/3 不取) · 第一版光环中间画了白人影(ow_aura 弃, 重出 ow_aura2) · 第一版印记底下多一块白方块(ow_sigil 弃)。
    里世界按钮图标 btn_ow / btn_main = create_image_pro_flash 40×36, 风格锚 = hud-stats 顶栏图标。
  · 11-26 夜 134 威尼斯复活: 面具 ven_mask(64×64) / 光环 ven_halo / 爆闪 ven_burst(128×128) = create_image_pro_flash(无锚, 没照参考);
    面具 / 光环 = animate_image 首尾钉原画 8 帧(venm_* / venh_*), 爆闪 = 只钉首帧 8 帧(venb_*)。
  · 11-26 夜其余面具演出(全部 create_image_pro_flash 无锚原画 + animate_image, 没照参考):
    偷脸魂面具 cp_ghostmask / 赠属性光球 gift_orb / 纸刃 paper_blade / 小丑脸 clown_jeer = 首尾钉原画 4 帧循环;
    京剧三张脸 face_r / face_k2 / face_w2(黑白两张以红脸为风格锚重出: 第一版 face_k / face_w 比红脸小一圈, 弃)
      = 首尾各钉一张脸出 6 帧变脸(fcrk / fckw / fcwr);
    红脸火花 face_redhit / 鬼面烟 ghost_puff / 挡毒 gas_block / 舞狮爆竹 lion_burst2(第一版 lion_burst 画进了一只狮子, 弃) = 只钉首帧。
  · 11-27 舞狮冲撞重做(用户「冲刺特效呢」; 原来冲撞帧条几乎不动、蓄力 / 撞上是程序圆圈):
    以已打包的冲撞首帧(已下移贴地)为底, edit_image_pro_flash 出奔腾姿势 lion_gallop / 蓄力压低姿势 lion_crouch;
    蓄力 lwind_0..6 = animate_image 首帧钉站姿、末帧钉 lion_crouch; 奔腾 lgal_0..7 = animate_image 首尾都钉 lion_gallop(序号 8 = 钉住的末帧不取)。
    这两套输入已贴地, 不再下移(LION_SEQ0)。
    撞击鞭炮 lion_hitburst(96×96) / 身后红金彩绸 lion_ribbon(160×48) = create_image_pro_flash(无锚, 没照参考);
    鞭炮 lhit_0..8 = animate_image 只钉首帧; 彩绸 lrib_0..5 = animate_image 首尾钉原画(序号 6 不取)。
  · 11-27 舞狮普攻重做(用户「lion 太敷衍了吧，特效，攻击特效」; 原来 10 帧只张张嘴、身子不动):
    edit_image_pro_flash 出两个关键姿势 扬起张嘴 lion_rear / 前扑咬 lion_lunge(底图同上), 再 animate_image 三段首尾钉住:
    站→扬起(latk2_0..4) / 扬起→前扑(latk2_5..8, 第 8 帧前扑最远 = 命中帧) / 前扑→站(latk2_9..12)。
    咬击特效: 狮牙合拢 lion_fang + 张开 lion_fang_open(edit) = create_image_pro_flash(无锚, 没照参考);
    张开→合拢 = animate_image 首尾钉住(lfang_0..4); 白闪散开 = 另一条只钉 lion_fang 首帧的 animate_image 第 2 / 5 / 6 帧(lfang_5..7;
    第 3 / 4 帧多一圈白边, 弃)。
  · 11-27 小丑面具嘲讽(原来一圈程序粉环): 彩纸星星铃铛炸开 clown_burst = create_image_pro_flash(无锚, 没照参考; 第一次提示词里写 jester taunt 被内容过滤拦了, 换说法重出)
    + animate_image 只钉首帧(clb_0..8)。
  · 11-27 舞狮冲撞照塞恩 R 重做(用户点名; 研究 docs/studies/20261127-参考-塞恩R冲撞.md): 全部 create_image_pro_flash(无锚) + animate_image ——
    蓄力时狮头前方聚起的能量球 lion_orb(+ edit 出的小火星 lion_orb_small; 首尾钉住小→大 lorb_0..6) /
    冲锋时狮头前的弯月冲击罩 lion_bow(lbow_0..5; 11-27 用户「冲击罩不适合」——整只裹红光后多余, 不再打包, 源图留档) /
    身后速度线 lion_speed(首尾钉原画, lspd_0..3) /
    撞击后地面冲击环 lion_shock(俯视, 只钉首帧 lgsw_0..10; 生成的第 5~8 帧焦黑处发蓝, 打包时把偏蓝像素按亮度改成焦褐色, 见 BLUE_TO_SCORCH)。
  · 11-27 用户「冲击的时候，它整个身上应该是这个冲击波的这个红红色特效」: 奔腾 8 帧(lgal)左右各补 24 像素透明边成 160×112(lgalpad_*, 留出拖尾的地方),
    逐帧 edit_image_pro_flash「整只裹进红色冲击能量壳: 前缘橙黄最烫、全身泛红、身后拖长火舌」(同一句提示词同一种子) ⇒ lfire_0..7;
    第 7 帧第一次多一圈浅色描边, 换种子重出。
, 重跑逐字节相同。

    python tools/assetgen/pack_mask_art.py
"""
import os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AI = os.path.join(ROOT, "tools", "assetgen", "ai_src", "mask")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
FW = 112

ICONS = {"icon%d" % i: "p2eq_%d" % i for i in range(127, 137)}
TAG = {"tagmask": "tag-mask"}
## 舞狮帧条(源名)。咬的命中帧下标抄到 AttackHits
LION_SEQ = {
    "eq-masklion-idle": ["lidle_%d" % i for i in range(0, 6)],
    "eq-masklion-walk": ["lwalk_%d" % i for i in range(1, 9)],
}
## 11-27 舞狮冲撞重做: 输入是已贴地的帧, 不再下移
LION_SEQ0 = {
    "eq-masklion-charge": ["lgal_%d" % i for i in range(0, 8)],   # 奔腾(循环)
    "eq-masklion-windup": ["lwind_%d" % i for i in range(0, 7)],  # 蓄力压低(放一遍停在末帧)
    "eq-masklion-attack": ["latk2_%d" % i for i in range(0, 13)], # 普攻: 扬起 → 前扑咬(下标 8 = 命中) → 收回
}


## 特效帧条(源名按帧序; 一律横排一行)
STRIPS = {
    "mask-gold-beam-anim": ["glb_%d" % i for i in range(0, 6)],
    "mask-gold-splash": ["gls_%d" % i for i in range(0, 6)],
    "mask-gold-smoke": ["glk_%d" % i for i in range(1, 7)],
    "ow-hand": ["owh_%d" % i for i in range(0, 9)],
    "ow-mist": ["owm_%d" % i for i in range(0, 9)],
    "ow-rift": ["owr_0", "owr_1", "owr_4", "owr_5"],
    "ow-pillar2": ["owp_%d" % i for i in range(0, 6)],
    "ow-wisp": ["oww_%d" % i for i in range(0, 4)],
    "ow-aura": ["owaura_%d" % i for i in range(0, 8)],   # 源名不能叫 owa_*: Windows 不分大小写, 会和巨面具 owA_* 撞名(11-26 撞过一次, 从提交里取回)
    "ow-sigil": ["ows_0", "ows_2", "ows_3", "ows_2"],
    "mask-venice-mask": ["venm_%d" % i for i in range(0, 8)],    # 134 复活: 头顶浮着的面具(呼吸发光, 首尾钉原画, 末帧 = 原画不取)
    "mask-venice-halo": ["venh_%d" % i for i in range(0, 8)],    # 134 复活光环(循环, 首尾钉原画)
    "mask-venice-burst": ["venb_%d" % i for i in range(0, 9)],   # 134 起身爆闪(只钉首帧, 第 9 帧散尽)
    "mask-copy-spirit": ["cpm_%d" % i for i in range(0, 4)],     # 偷脸: 从原版飞到复制体的魂面具(循环, 首尾钉原画)
    "mask-gift-orb": ["gfo_%d" % i for i in range(0, 4)],        # 偷脸: 复制体死后飞向友军的属性光球(循环); 129 白脸偷龟能也用(底层光点, 换色)
    "mask-face-rk": ["fcrk_0", "fcrk_1", "fcrk_5", "fcrk_6"],     # 129 红→黑(第 2~4 帧闪出白脸, 与白脸状态混淆, 不取)
    "mask-face-kw": ["fckw_%d" % i for i in range(0, 7)],        # 129 黑→白
    "mask-face-wr": ["fcwr_%d" % i for i in range(0, 7)],        # 129 白→红
    "mask-face-redhit": ["frh_%d" % i for i in range(0, 7)],     # 129 红脸真伤火花
    "mask-clown-jeer": ["clj_%d" % i for i in range(0, 4)],      # 131 被嘲讽者头上的小丑脸(循环)
    "mask-paper-blade": ["ppb_%d" % i for i in range(0, 4)],     # 127 反击纸刃(循环)
    "mask-ghost-puff": ["ghp_%d" % i for i in range(0, 9)],      # 132 潜行 / 现形的暗红烟
    "mask-gas-block": ["gsb_%d" % i for i in range(0, 7)],       # 133 毒气撞上滤网散掉
    "mask-lion-pop": ["lnb_%d" % i for i in range(0, 9)],        # 130 舞狮登场爆竹
    "mask-lion-hit": ["lhit_%d" % i for i in range(0, 9)],       # 130 舞狮冲撞撞上: 鞭炮炸开(11-27)
    "mask-lion-ribbon": ["lrib_%d" % i for i in range(0, 6)],
    "mask-lion-bite": ["lfang_%d" % i for i in range(0, 8)],
    "mask-clown-burst": ["clb_%d" % i for i in range(0, 9)],     # 131 小丑面具嘲讽: 彩纸炸开(11-27)
    "mask-lion-gather": ["lorb_%d" % i for i in range(0, 7)],    # 130 冲撞蓄力: 狮头前方聚能(11-27 照塞恩 R)
    "mask-lion-speed": ["lspd_%d" % i for i in range(0, 4)],     # 130 冲锋中: 身后速度线(循环)
    "mask-lion-shock": ["lgsw_%d" % i for i in range(0, 11)],    # 130 撞上: 地面冲击环 → 变暗焦痕 → 淡出
    "eq-masklion-charge-fire": ["lfire_%d" % i for i in range(0, 8)],   # 130 冲锋中: 整只裹在红色冲击能量里(160×112, 狮身在中间 112 宽)     # 130 舞狮普攻命中: 狮牙合拢(11-27)    # 130 舞狮冲撞身后红金彩绸(循环, 11-27)
    "mask-fox-fire": ["foxf_%d" % i for i in range(0, 7)],       # 128 狐狸面具增伤狐火(11-26 夜: create_image_pro_flash 无锚 fox_fire + animate_image 只钉首帧)   # 第 1 帧整张发白不取; 2/3 帧右侧杂点在 CLEAN_RIGHT 里清
}


CLEAN_RIGHT = {"ow-sigil": 21}
BLUE_TO_SCORCH = {"mask-lion-shock"}   # 偏蓝像素(b > r)按亮度改成焦褐色 —— 生成的焦黑帧带蓝灰, 和红金配色不搭   # 印记本体占 x 2..20, 21 起是杂点(逐列量过)


def _icon(src, dst, maxc=64):
    im = Image.open(src).convert("RGBA")
    if len({p[:3] for p in im.getdata() if p[3] > 0}) <= maxc:
        im.save(dst, optimize=False)
        return
    a = im.getchannel("A")
    q = im.convert("RGB").quantize(colors=maxc, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = q.convert("RGBA")
    out.putalpha(a)
    out.save(dst, optimize=False)


def main():
    for src, dst in ICONS.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(EQ, dst + ".png"))
    for src, dst in TAG.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(TAGS, dst + ".png"))
    for src, dst in {"ow_tile": "ow-tile", "ow_circle": "ow-circle", "ow_pillar": "ow-pillar"}.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(VFX, dst + ".png"))
    for pre, dst, (fw, fh) in [("owA", "ow-maskA", (128, 128)), ("owB", "ow-maskB", (128, 128)), ("owF", "ow-brazier", (48, 96))]:
        out = Image.new("RGBA", (fw * 8, fh), (0, 0, 0, 0))
        for i in range(8):
            im = Image.open(os.path.join(AI, "%s_%d.png" % (pre, i))).convert("RGBA")
            assert im.size == (fw, fh), (pre, i, im.size)
            out.paste(im, (i * fw, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
    for src, dst in {"gl_ring": "mask-gold-ring"}.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(VFX, dst + ".png"))
    UI = os.path.join(ROOT, "assets", "sprites", "ui")
    for src, dst in {"btn_ow": "hud-ow-enter", "btn_main": "hud-ow-back"}.items():
        _icon(os.path.join(AI, src + ".png"), os.path.join(UI, dst + ".png"))
    for dst, names in STRIPS.items():
        ims = [Image.open(os.path.join(AI, n + ".png")).convert("RGBA") for n in names]
        if dst in CLEAN_RIGHT:   # 去掉帧右缘以外的杂点(自查: 印记第 2/3 帧右侧多出一小撮白点)
            for im in ims:
                px = im.load()
                for y in range(im.height):
                    for x in range(CLEAN_RIGHT[dst], im.width):
                        px[x, y] = (0, 0, 0, 0)
        if dst in BLUE_TO_SCORCH:
            for im in ims:
                px = im.load()
                for y in range(im.height):
                    for x in range(im.width):
                        r, g, b, a = px[x, y]
                        if a > 0 and b > r:
                            l = (r * 299 + g * 587 + b * 114) // 1000
                            px[x, y] = (min(255, l * 3 // 5 + 24), min(255, l * 2 // 5 + 10), l // 4, a)
        fw, fh = ims[0].size
        out = Image.new("RGBA", (fw * len(ims), fh), (0, 0, 0, 0))
        for i, im in enumerate(ims):
            assert im.size == (fw, fh), (dst, names[i], im.size)
            out.paste(im, (i * fw, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(ims), "帧", fw, "×", fh)
    for dst, names in LION_SEQ.items():
        out = Image.new("RGBA", (FW * len(names), FW), (0, 0, 0, 0))
        for i, n in enumerate(names):
            im = Image.open(os.path.join(AI, n + ".png")).convert("RGBA")
            assert im.size == (FW, FW), (n, im.size)
            out.paste(im, (i * FW, 17))   # 脚底对齐: 舞狮原画脚只到第 95 行(帧高 112), 四套统一下移 17 贴地(11-26 夜量过, 原来浮在半空)
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(names), "帧")
    for dst, names in LION_SEQ0.items():
        out = Image.new("RGBA", (FW * len(names), FW), (0, 0, 0, 0))
        for i, n in enumerate(names):
            im = Image.open(os.path.join(AI, n + ".png")).convert("RGBA")
            assert im.size == (FW, FW), (n, im.size)
            out.paste(im, (i * FW, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(names), "帧")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
