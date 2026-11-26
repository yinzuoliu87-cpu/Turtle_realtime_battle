"""pack_spear_chip_art.py —— 长矛羁绊(方案书 20261126)与筹码(20261126b)的美术打包

来源(如实, 没有一张是手画的; 也没有照任何参考 —— 百夫长 / 骑兵形象按「罗马百夫长」通用印象写进提示词):
  · 图标: 长矛 137–146 / 筹码 147–156 = PixelLab create_image_pro_flash 64×64, 风格锚 = 110 苦无图标;
    筹码 148–156 再以 147 白色筹码为风格锚(同一枚筹码只换颜色); 149 红 / 150 绿 / 152 紫第一版整面是白的、只有边条带色, 重出(icon149/150/152 已覆盖)。
    标签 tag-spear / tag-chip = 32×32, 风格锚 = 魔法书标签。
  · 百夫长: 原画 cent_0(create_image_pro_flash 112×112)朝向不清(刺击往右捅、掷矛往左扔)⇒ 左右翻转成 centL_0(朝左、盾在前),
    两套各自 animate_image(待机 / 走路 / 刺 / 掷 首尾钉原画, 举盾只钉首帧); 最后怎么拼见下面 STRIPS 上方的注释(两套朝向都不严格)。
  · 骑兵: cav_0(128×112)+ animate_image 首尾钉原画 8 帧奔跑。
  · 飞行物: pilum(百夫长掷矛)/ javelin(139 标枪)/ dart(144 投矛器)/ gungnir(145 永恒之枪)各一张, 朝右; 引擎里按方向转。
  · 11-27 换掉程序画的圆圈(自查 18 处): 全部 create_image_pro_flash(无锚, 没照参考) + animate_image ——
    命中火星 hit_spark(hspk_0..5, 只钉首帧) / 鱼叉溅水 harpoon_splash(hwsp_0..8) / 百夫长横扫气刃 cent_sweep(俯视, cswp_0..8) /
    投矛器落点警示区 atl_target(俯视, atgt_0..3 首尾钉原画循环) / 标枪迸血 javelin_blood(第一版 48×48 太淡弃, 64×64 重出; jbld_0..6) /
    棕色筹码起身光柱 brown_rise(crev_0..6, 后两帧只剩一块黑影不取) / 筹码盾落进胸口的盾光 shield_glint(cglt_0..6, 引擎按物理 / 魔法着色)。
  · 11-27 百夫长自查返工(用户「有没有说过，它是全屏击飞的」): PixelLab 特效工作台(vfx_workbench)自己写图层画的, 不是模板改色 ——
    (centurion-ground-erupt 每人脚下裂地爆: 用户 11-27 否掉「哪有说什么对每个敌人脚下的地裂爆」, 不再打包, 源留在 ai_src)
    ai_src/cent_vfx/centurion-crack-segment(.json): 俯视、两端等高可首尾拼接的一段地裂(暗缝 + 金色裂光, 8 帧), 引擎里从落点往四面八方铺满整座岛。
    工作台导出的是网格帧表 + JSON(帧位置 / 锚点), 下面 GRIDS 一段按 JSON 拆帧拼成横排; 裂地爆每帧左右补齐, 让锚点(地面点)落在帧的正中。
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
## ★11-27 百夫长整套重画(用户「这个形象就太小了…肯定是要大一点的，要健壮一点」): 原画 centB_a = create_image_pro_flash 128×128,
##   风格锚 = 旧百夫长待机首帧 cent_old_idle0(只借配色 / 描边 / 明暗), 提示词写「重甲巨汉、宽肩、大肩甲、大塔盾、粗长矛」; 另一版 centB_b 弃;
##   左右翻转成朝左 centB_0, 六套 animate_image 都从它出: 待机 cBidle3(首尾钉) / 走路 cBwalk3(首尾钉) / 刺 cBatk(首尾钉) /
##   掷 cBthr(首尾钉) / 举盾 cBshd(只钉首帧, 末帧 = 撑盾姿势) / 阵亡 cBdie(只钉首帧)。
##   待机和走路三次生成都凭空长出一条红披风(底图没有): cBidle3 / cBwalk3 按底图每一行的盾左缘把盾外侧的披风像素清掉 ⇒ cBidle3c / cBwalk3c
##   (清理脚本 tools/oneoff/cent_cape_clean_1127.py, 盾内与脚不动); 前两次的 cBidle / cBidle2 / cBwalk / cBwalk2 弃。旧 112 帧那套(cidle / cwalk / latk / cthr / cshdA / cdie)留在 ai_src。
STRIPS = {
    ## 举盾(11-26 夜重做): 原画 cent_0 → edit_image_pro_flash 改出「屈膝、大盾举到身前、长矛架在盾沿上」cshdA_end,
    ##   animate_image 首尾钉这两张出 6 帧(cshdA_1..6)。帧条 = 举盾 6 帧 + 撑盾 36 帧(末两帧每 4 帧换一次, 慢慢用力),
    ##   引擎按举盾秒数算播放速度(3 秒 ⇒ 14 fps: 举盾 0.43 秒, 之后一直撑着)。旧 cshd_* 盾没举起来, 弃。
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
    ## 153 黄(11-27 自查补: 挡掉控制时画面上原来什么都没有): 图标 icon153 首尾都钉 animate_image 6 帧(cspy_0..6, 末帧 = 钉住的图标不取)
    "chip-spin-yellow": [(CH, "cspy_%d" % i, False) for i in range(0, 6)],
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
    ## spear-cent-beam(通用金光柱)11-27 删: 用户「这个落下的这个光特效，你是不是偷偷复用了什么东西」⇒ 换成预警标记圈 + 插地长矛(下面 GRIDS / PLANT)
    "spear-cent-impact": [(SP, "c3im_%d" % i, False) for i in [0, 1, 3, 4, 5, 6, 7, 8]],
    ## 11-27 换掉程序圆圈
    "spear-hit-spark": [(SP, "hspk_%d" % i, False) for i in range(0, 6)],
    "spear-harpoon-splash": [(SP, "hwsp_%d" % i, False) for i in range(0, 9)],
    "spear-cent-sweep": [(SP, "cswp_%d" % i, False) for i in range(0, 9)],
    "spear-atl-target": [(SP, "atgt_%d" % i, False) for i in range(0, 4)],
    "spear-javelin-blood": [(SP, "jbld_%d" % i, False) for i in range(0, 7)],
    "chip-brown-rise": [(CH, "crev_%d" % i, False) for i in range(0, 7)],
    "chip-shield-glint": [(CH, "cglt_%d" % i, False) for i in range(0, 7)],
    ## 百夫长阵亡(11-27 自查: 原来只有通用淡出): 打包好的待机首帧(已下移贴地, cent_stand_packed)→ edit 出倒地 cent_fallen,
    ##   animate_image 首尾钉住 10 帧(第一条中间 4 帧矛放平像在出招、盾变黑, 换提示词重出) ⇒ cdie_0..10; 输入已贴地不再下移;
    ##   前段抽帧, 末帧连停 4 拍(12 帧 @12 = 1 秒 ≥ 阵亡淡出 0.95 秒)
    ## 骑兵冲锋(11-27 补, 同舞狮冲撞): 身后灰白风线 cav_speed / 马头前尘浪 cav_dustbow = create_image_pro_flash(无锚, 没照参考)
    ##   + animate_image 首尾钉原画循环(cvspd_0..3 / cvbow_0..5)
    "spear-cav-speed": [(SP, "cvspd_%d" % i, False) for i in range(0, 4)],
    "spear-cav-dustbow": [(SP, "cvbow_%d" % i, False) for i in range(0, 6)],
    ## 11-27 百夫长特效加强(用户「技能特效感觉都不明显。普攻也没有特效」; create_image_pro_flash 无锚 + animate_image, 没照参考):
    ##   普攻突刺气劲 fx_thrust(128×48, 画的是朝左 ⇒ 翻成朝右, 引擎按方向转)+ 只钉首帧 7 帧(cthr2: 矛尖闪 → 光尾拉长 → 碎成火星)
    ##   龟甲阵金色能量巨盾 fx_aegis(64×128)+ 首尾钉原画循环 6 帧(caeg)
    "spear-cent-thrust": [(SP, "cthr2_%d" % i, True) for i in range(0, 7)],
    ## spear-cent-aegis: 11-27 自查返工改由下面 GRIDS 拼(特效工作台 aegis-open 5 帧 + aegis-loop 8 帧); 旧的 caeg_0..5(金色实心盾)留在 ai_src 不用
}

## 脚底对齐(11-26 夜录像量过: 原画人物脚只到第 92 行, 帧高 112 ⇒ 引擎按帧底边贴地, 百夫长浮在半空)。
##   同一个角色的所有帧条按「全部帧里最低那只脚」统一下移同样多 ⇒ 脚贴帧底、动作之间切换不跳。
##   11-27 重画的 128 帧: 全部帧最低的脚在第 120 行 ⇒ 统一下移 7(阵亡也一起)
SHIFT_DOWN = {"eq-cavalry-run": 7}   # 百夫长 11-27 换新形象后由下面 CENT2 统一对齐

## ★11-27 百夫长换新形象(用户「重画」; 手画一版用户看了「不如 Pixel AI」⇒ PixelLab「角色」流程):
##   create_character(v3, 128, low top-down, 8 方向同一个角色) → 只用西南向(朝左四分之三侧身); animate_character 逐个动作:
##   待机 = skeleton-v3 breathing-idle · 走路 = skeleton-v3 walking(普通模板那版盾会消失、鹰徽丢、人变瘦, 弃) ·
##   普攻 / 掷矛 / 举盾 / 转圈横扫 / 倒下 = pixminimax 自定义动作(普攻、举盾第一版矛尖朝右后方, 写死「矛尖朝左」重出 attack2 / shield_brace2)。
##   举盾姿势按潘森 E 研究(docs/studies/20261127-龟甲阵参考-潘森E逐帧.md): 压低重心蹲在盾后、盾往前推、矛架盾上沿。
##   帧(下标 = 下载包里的 frame_NNN, 0 = 角色原画站姿):
CENT2 = {
    "eq-centurion-idle":   ("idle",          [0, 1, 2, 3]),
    "eq-centurion-walk":   ("walk_skel",     [0, 1, 2, 3, 4, 5]),
    "eq-centurion-attack": ("attack2",       [1, 2, 3, 4, 5, 6, 7, 8, 1, 0]),          # 命中 = 原第 6 帧(矛尖最远) = 下标 5; 末尾补回 1 / 0 接待机
    "eq-centurion-throw":  ("throw",         [3, 4, 5, 6, 7, 8, 0]),                   # 从举矛过肩截起: 出手在下标 2(引擎里飞矛动作一开始就发)
    "eq-centurion-shield": ("shield_brace2", [3, 4, 5, 6, 7, 8] + [8] * 36),           # 下蹲举盾 6 帧 + 撑盾(结构同旧帧条, 引擎按举盾秒数算播放速度)
    "eq-centurion-sweep":  ("spin_sweep",    list(range(5, 17))),                      # 原地转一圈横扫(前 5 帧几乎不动, 截掉)
    "eq-centurion-death":  ("death",         [0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]),     # 末帧连停 4 拍
}
CENT2_FW, CENT2_LEFT, CENT2_FOOT = 192, 62, 186


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
    ## 11-27 登场插进标记圈的长矛 = 掷矛同一张 spear-pilum 顺时针转 90°(矛尖朝下)
    pil = os.path.join(VFX, "spear-pilum.png")
    if os.path.exists(pil):
        Image.open(pil).convert("RGBA").transpose(Image.Transpose.ROTATE_270).save(os.path.join(VFX, "spear-cent-plant.png"), optimize=False)
    ## 11-27 特效工作台网格帧表 → 横排帧条(见头注)
    import json
    CV = os.path.join(ROOT, "tools", "assetgen", "ai_src", "cent_vfx")
    for src, dst, centre in [("centurion-crack-segment", "spear-cent-crack", False),
            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False), ("centurion-drop-marker", "spear-cent-marker", False)]:
        if "+" in src:   # 两段接成一条(先展开后循环)
            parts = []
            for one in src.split("+"):
                mj = json.load(open(os.path.join(CV, one + ".json"), encoding="utf-8"))
                sh = Image.open(os.path.join(CV, one + ".png")).convert("RGBA")
                for f in mj["frames"]:
                    r = f["frame"]
                    parts.append(sh.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
            fw0, fh0 = parts[0].size
            out = Image.new("RGBA", (fw0 * len(parts), fh0), (0, 0, 0, 0))
            for i, im in enumerate(parts):
                out.paste(im, (i * fw0, 0))
            out.save(os.path.join(VFX, dst + ".png"), optimize=False)
            print(dst, len(parts), "帧", fw0, "×", fh0)
            continue
        jp = os.path.join(CV, src + ".json")
        if not os.path.exists(jp):
            print("缺帧表, 跳过", dst)
            continue
        meta = json.load(open(jp, encoding="utf-8"))
        sheet = Image.open(os.path.join(CV, src + ".png")).convert("RGBA")
        fr = meta["frames"]
        w0, h0 = fr[0]["frame"]["w"], fr[0]["frame"]["h"]
        ax = int(round(fr[0]["pivot"]["x"] * w0))
        fw = 2 * max(ax, w0 - ax) if centre else w0
        dx = fw // 2 - ax if centre else 0
        out = Image.new("RGBA", (fw * len(fr), h0), (0, 0, 0, 0))
        for i, f in enumerate(fr):
            r = f["frame"]
            out.paste(sheet.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])), (i * fw + dx, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(fr), "帧", fw, "×", h0, "锚点行", int(round(fr[0]["pivot"]["y"] * h0)))
    ## 11-27 百夫长新形象(见 CENT2 头注): 每个动作以第 0 帧包围盒对齐(左沿 → CENT2_LEFT、脚底 → CENT2_FOOT)
    CC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "cent_char")
    for dst, (anim, idx) in CENT2.items():
        fp = lambda k: os.path.join(CC, anim, "frame_%03d.png" % k)
        if not os.path.exists(fp(0)):
            print("缺帧, 跳过", dst)
            continue
        bb = Image.open(fp(0)).convert("RGBA").getchannel("A").getbbox()
        dx, dy = CENT2_LEFT - bb[0], CENT2_FOOT - bb[3]
        out = Image.new("RGBA", (CENT2_FW * len(idx), CENT2_FW), (0, 0, 0, 0))
        for i, k in enumerate(idx):
            fr = Image.new("RGBA", (CENT2_FW, CENT2_FW), (0, 0, 0, 0))
            fr.alpha_composite(Image.open(fp(k)).convert("RGBA"), (dx, dy)) if dx >= 0 and dy >= 0 else fr.paste(Image.open(fp(k)).convert("RGBA"), (dx, dy))
            out.paste(fr, (i * CENT2_FW, 0))
        out.save(os.path.join(VFX, dst + ".png"), optimize=False)
        print(dst, len(idx), "帧", CENT2_FW, "方 · 位移", (dx, dy))
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
