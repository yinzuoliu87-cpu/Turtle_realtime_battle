"""pack_spear_chip_art.py —— 长矛羁绊(方案书 20261126)与筹码(20261126b)的美术打包

来源(如实, 没有一张是手画的; 也没有照任何参考 —— 百夫长 / 骑兵形象按「罗马百夫长」通用印象写进提示词):
  · 图标: 长矛 137–146 / 筹码 147–156 = PixelLab create_image_pro_flash 64×64, 风格锚 = 110 苦无图标;
    筹码 148–156 再以 147 白色筹码为风格锚(同一枚筹码只换颜色); 149 红 / 150 绿 / 152 紫第一版整面是白的、只有边条带色, 重出(icon149/150/152 已覆盖)。
    标签 tag-spear / tag-chip = 32×32, 风格锚 = 魔法书标签。
  · 百夫长: 原画 cent_0(create_image_pro_flash 112×112)朝向不清(刺击往右捅、掷矛往左扔)⇒ 左右翻转成 centL_0(朝左、盾在前),
    两套各自 animate_image(待机 / 走路 / 刺 / 掷 首尾钉原画, 举盾只钉首帧); 最后怎么拼见下面 STRIPS 上方的注释(两套朝向都不严格)。
  · 骑兵: cav_0(128×112)+ animate_image 首尾钉原画 8 帧奔跑。
  · 飞行物: pilum(百夫长掷矛)/ javelin(139 标枪)/ dart(144 投矛器)/ gungnir(145 永恒之枪)各一张, 朝右; 引擎里按方向转。
本脚本只做拷贝 / 拼接 / 量化, 重跑逐字节相同。

    python tools/assetgen/pack_spear_chip_art.py
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SP = os.path.join(ROOT, "tools", "assetgen", "ai_src", "spear")
CH = os.path.join(ROOT, "tools", "assetgen", "ai_src", "chip")
EQ = os.path.join(ROOT, "assets", "sprites", "equip")
TAGS = os.path.join(ROOT, "assets", "sprites", "tags")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")

## 11-26 夜自查(如实): PixelLab 出的是半侧身姿势, 两版的朝向都不严格 —— cent_0 一套里待机 / 走路 / 掷矛朝左、刺击往右捅;
##   左右翻转的 centL_0 一套里刺击往右捅、掷矛朝左。按「整套朝左」拼: 待机 / 走路 / 掷矛 = cent_0 那套, 刺击 = centL_0 那套再翻回来(往左捅),
##   举盾 11-26 夜重做(见下面 eq-centurion-shield 那行)。第三个元素 True = 左右翻转。
STRIPS = {
    "eq-centurion-idle": [(SP, "cidle_%d" % i, False) for i in range(0, 6)],
    "eq-centurion-walk": [(SP, "cwalk_%d" % i, False) for i in range(1, 9)],
    "eq-centurion-attack": [(SP, "latk_%d" % i, True) for i in range(1, 11)],
    "eq-centurion-throw": [(SP, "cthr_%d" % i, False) for i in range(1, 11)],
    ## 举盾(11-26 夜重做): 原画 cent_0 → edit_image_pro_flash 改出「屈膝、大盾举到身前、长矛架在盾沿上」cshdA_end,
    ##   animate_image 首尾钉这两张出 6 帧(cshdA_1..6)。帧条 = 举盾 6 帧 + 撑盾 36 帧(末两帧每 4 帧换一次, 慢慢用力),
    ##   引擎按举盾秒数算播放速度(3 秒 ⇒ 14 fps: 举盾 0.43 秒, 之后一直撑着)。旧 cshd_* 盾没举起来, 弃。
    "eq-centurion-shield": [(SP, "cshdA_%d" % i, False) for i in range(1, 7)]
        + [(SP, "cshdA_%d" % (6 if (k // 4) % 2 == 0 else 5), False) for k in range(36)],
    "eq-cavalry-run": [(SP, "cav_%d" % i, False) for i in range(0, 8)],
    ## 11-26 夜 10 件长矛的演出(create_image_pro_flash 无锚原画 fx_* + animate_image; 没照参考):
    ##   只钉首帧(一次性): 骑枪冲阵 slan / 长戟横扫 shal / 圣枪引爆 shbu
    ##   首尾钉原画(循环, 末帧 = 原画不取): 方天画戟刃环 sftj / 圣痕 shmk
    ##   (竹矛穿刺 sbam / 鱼叉倒钩 sbarb / 盾矛反刺 sshs / 投矛器飞矛 dart 随 11-26 夜机制重做弃用, 原图留在 ai_src)
    "spear-lance-hit": [(SP, "slan_%d" % i, False) for i in range(0, 7)],
    "spear-halb-sweep": [(SP, "shal_%d" % i, False) for i in range(0, 7)],
    "spear-ftj-ring": [(SP, "sftj_%d" % i, False) for i in range(0, 6)],
    "spear-holy-mark": [(SP, "shmk_%d" % i, False) for i in range(0, 4)],
    "spear-holy-burst": [(SP, "shbu_%d" % i, False) for i in range(0, 9)],
    ## 筹码(11-26 夜): 151 黑 / 152 紫 = 各自的图标 p2eq_151 / 152 当首帧 animate_image 转一圈(cspk / cspp, 首帧 = 图标, 末帧转回正面);
    ##   156 灰满层 = create_image_pro_flash 银灰光焰 fx_grey + animate_image 只钉首帧(cgry)
    "chip-spin-black": [(CH, "cspk_%d" % i, False) for i in range(0, 6)],
    "chip-spin-purple": [(CH, "cspp_%d" % i, False) for i in range(0, 6)],
    "chip-grey-flare": [(CH, "cgry_%d" % i, False) for i in range(0, 7)],
    "chip-spin-brown": [(CH, "cspb_%d" % i, False) for i in range(0, 6)],   # 154 棕: 同黑紫, 图标 p2eq_154 当首帧转一圈
    "chip-gold-dome": [(CH, "cgdm_%d" % i, False) for i in range(0, 6)],    # 155 金色护罩: create_image_pro_flash 无锚 fx_golddome + animate_image 首尾钉原画循环(引擎里半透明)
    ## 11-26 夜第二轮(用户改了 137~144 的机制; create_image_pro_flash 无锚原画 b2_* + animate_image, 没照参考):
    ##   竹刺: 原画 b2_spike(满) → edit_image_pro_flash 改出只冒竹尖的 b2_spike_small → 首尾钉这两张出「刺出」6 帧(b2erp);
    ##         帧条 = 刺出 7 帧 + 停 1 帧 + 倒放缩回 5 帧(第一版「缩回」b2spk 七帧一样高, 弃)
    ##   骑枪标记 b2lnc / 大盾 b2sct / 聚气 b2chg = 首尾钉原画循环; 冲击波 b2swv / 裂坑 b2crt(第一版 b2_crater 太小太暗, 用重出的 b2_crater2)/ 扎地 b2stk = 只钉首帧
    "spear-bamboo-spike": [(SP, "b2erp_%d" % i, False) for i in [0, 1, 2, 3, 4, 5, 6, 6, 5, 4, 3, 2, 1]],
    "spear-lance-ready": [(SP, "b2lnc_%d" % i, False) for i in range(0, 4)],
    "spear-scutum": [(SP, "b2sct_%d" % i, False) for i in range(0, 4)],
    "spear-shsp-wave": [(SP, "b2swv_%d" % i, False) for i in range(0, 7)],
    "spear-ftj-charge": [(SP, "b2chg_%d" % i, False) for i in range(0, 6)],
    "spear-ftj-crater": [(SP, "b2crt_%d" % i, False) for i in range(0, 9)],
    "spear-atl-stuck": [(SP, "b2stk_%d" % i, False) for i in range(0, 7)],
    ## 百夫长登场(11-26 夜重做): 落点金光柱 c3_beam(首尾钉原画循环) / 落地金色冲击 c3_impact2(第一版 c3_impact 中间画进了一个人, 弃)
    ##   = create_image_pro_flash 无锚 + animate_image; 冲击第 2 帧中间一道 1 像素白竖线(生成瑕疵)不取
    "spear-cent-beam": [(SP, "c3bm_%d" % i, False) for i in range(0, 6)],
    "spear-cent-impact": [(SP, "c3im_%d" % i, False) for i in [0, 1, 3, 4, 5, 6, 7, 8]],
}

## 脚底对齐(11-26 夜录像量过: 原画人物脚只到第 92 行, 帧高 112 ⇒ 引擎按帧底边贴地, 百夫长浮在半空)。
##   同一个角色的所有帧条按「全部帧里最低那只脚」统一下移同样多 ⇒ 脚贴帧底、动作之间切换不跳。
SHIFT_DOWN = {"eq-centurion-idle": 19, "eq-centurion-walk": 19, "eq-centurion-attack": 19, "eq-centurion-throw": 19,
              "eq-centurion-shield": 19, "eq-cavalry-run": 7}


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
    for i in range(137, 147):
        _icon(os.path.join(SP, "icon%d.png" % i), os.path.join(EQ, "p2eq_%d.png" % i))
    for i in range(147, 157):
        _icon(os.path.join(CH, "icon%d.png" % i), os.path.join(EQ, "p2eq_%d.png" % i))
    _icon(os.path.join(SP, "tagspear.png"), os.path.join(TAGS, "tag-spear.png"))
    _icon(os.path.join(SP, "tagchip.png"), os.path.join(TAGS, "tag-chip.png"))
    for n in ["pilum", "javelin", "gungnir"]:
        p = os.path.join(SP, n + ".png")
        if os.path.exists(p):
            _icon(p, os.path.join(VFX, "spear-%s.png" % n))
    ## 第二轮的单张(飞行物 / 绳子): 鱼叉 / 绳 / 下落的矛
    for src, dst in {"b2_harpoon": "spear-harpoon", "b2_rope": "spear-rope", "b2_fall": "spear-atl-fall"}.items():
        _icon(os.path.join(SP, src + ".png"), os.path.join(VFX, dst + ".png"))
    for dst, srcs in STRIPS.items():
        ims = []
        for d, n, flip in srcs:
            p = os.path.join(d, n + ".png")
            if not os.path.exists(p):
                ims = []
                break
            im = Image.open(p).convert("RGBA")
            ims.append(im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if flip else im)
        if not ims:
            print("缺帧, 跳过", dst)
            continue
        fw, fh = ims[0].size
        out = Image.new("RGBA", (fw * len(ims), fh), (0, 0, 0, 0))
        for i, im in enumerate(ims):
            assert im.size == (fw, fh), (dst, i, im.size)
            out.paste(im, (i * fw, SHIFT_DOWN.get(dst, 0)))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(ims), "帧", fw, "×", fh)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
