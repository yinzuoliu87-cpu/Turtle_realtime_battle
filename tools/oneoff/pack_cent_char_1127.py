"""pack_cent_char_1127.py —— 百夫长换成 PixelLab「角色」流程的新形象(11-27 用户「重画」+「这次尝试…不如 Pixel AI」后定用角色流程):
改 tools/assetgen/pack_spear_chip_art.py —— 旧百夫长 6 条帧条从 STRIPS / SHIFT_DOWN 拿掉, 加 CENT2 一段从 ai_src/cent_char/ 拼 192 方帧:
  各动作以第 0 帧(角色原画站姿)对齐: 包围盒左沿 → 第 62 列、脚底 → 第 186 行; 动作之间切换不跳。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "tools", "assetgen", "pack_spear_chip_art.py")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")

PAIRS = [
    ('    "eq-centurion-idle": [(SP, "cBidle3c_%d" % i, False) for i in range(0, 4)],\n'
     '    "eq-centurion-walk": [(SP, "cBwalk3c_%d" % i, False) for i in range(0, 8)],\n'
     '    "eq-centurion-attack": [(SP, "cBatk_%d" % i, False) for i in range(1, 9)],\n'
     '    "eq-centurion-throw": [(SP, "cBthr_%d" % i, False) for i in range(1, 9)],\n', ''),
    ('    "eq-centurion-shield": [(SP, "cBshd_%d" % i, False) for i in range(1, 7)]\n'
     '        + [(SP, "cBshd_%d" % (6 if (k // 4) % 2 == 0 else 5), False) for k in range(36)],\n', ''),
    ('    "eq-centurion-death": [(SP, "cBdie_%d" % i, False) for i in [0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]],   # 11-27 重画: cBdie 末帧连停 4 拍\n', ''),
    ('SHIFT_DOWN = {"eq-centurion-idle": 7, "eq-centurion-walk": 7, "eq-centurion-attack": 7, "eq-centurion-throw": 7,\n'
     '              "eq-centurion-shield": 7, "eq-centurion-death": 7, "eq-cavalry-run": 7}\n',
     'SHIFT_DOWN = {"eq-cavalry-run": 7}   # 百夫长 11-27 换新形象后由下面 CENT2 统一对齐\n'
     '\n'
     '## ★11-27 百夫长换新形象(用户「重画」; 手画一版用户看了「不如 Pixel AI」⇒ PixelLab「角色」流程):\n'
     '##   create_character(v3, 128, low top-down, 8 方向同一个角色) → 只用西南向(朝左四分之三侧身); animate_character 逐个动作:\n'
     '##   待机 = skeleton-v3 breathing-idle · 走路 = skeleton-v3 walking(普通模板那版盾会消失、鹰徽丢、人变瘦, 弃) ·\n'
     '##   普攻 / 掷矛 / 举盾 / 转圈横扫 / 倒下 = pixminimax 自定义动作(普攻、举盾第一版矛尖朝右后方, 写死「矛尖朝左」重出 attack2 / shield_brace2)。\n'
     '##   举盾姿势按潘森 E 研究(docs/studies/20261127-龟甲阵参考-潘森E逐帧.md): 压低重心蹲在盾后、盾往前推、矛架盾上沿。\n'
     '##   帧(下标 = 下载包里的 frame_NNN, 0 = 角色原画站姿):\n'
     'CENT2 = {\n'
     '    "eq-centurion-idle":   ("idle",          [0, 1, 2, 3]),\n'
     '    "eq-centurion-walk":   ("walk_skel",     [0, 1, 2, 3, 4, 5]),\n'
     '    "eq-centurion-attack": ("attack2",       [1, 2, 3, 4, 5, 6, 7, 8, 1, 0]),          # 命中 = 原第 6 帧(矛尖最远) = 下标 5; 末尾补回 1 / 0 接待机\n'
     '    "eq-centurion-throw":  ("throw",         [3, 4, 5, 6, 7, 8, 0]),                   # 从举矛过肩截起: 出手在下标 2(引擎里飞矛动作一开始就发)\n'
     '    "eq-centurion-shield": ("shield_brace2", [3, 4, 5, 6, 7, 8] + [8] * 36),           # 下蹲举盾 6 帧 + 撑盾(结构同旧帧条, 引擎按举盾秒数算播放速度)\n'
     '    "eq-centurion-sweep":  ("spin_sweep",    list(range(5, 17))),                      # 原地转一圈横扫(前 5 帧几乎不动, 截掉)\n'
     '    "eq-centurion-death":  ("death",         [0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8]),     # 末帧连停 4 拍\n'
     '}\n'
     'CENT2_FW, CENT2_LEFT, CENT2_FOOT = 192, 62, 186\n'),
    ('    for dst, srcs in STRIPS.items():\n',
     '    ## 11-27 百夫长新形象(见 CENT2 头注): 每个动作以第 0 帧包围盒对齐(左沿 → CENT2_LEFT、脚底 → CENT2_FOOT)\n'
     '    CC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "cent_char")\n'
     '    for dst, (anim, idx) in CENT2.items():\n'
     '        fp = lambda k: os.path.join(CC, anim, "frame_%03d.png" % k)\n'
     '        if not os.path.exists(fp(0)):\n'
     '            print("缺帧, 跳过", dst)\n'
     '            continue\n'
     '        bb = Image.open(fp(0)).convert("RGBA").getchannel("A").getbbox()\n'
     '        dx, dy = CENT2_LEFT - bb[0], CENT2_FOOT - bb[3]\n'
     '        out = Image.new("RGBA", (CENT2_FW * len(idx), CENT2_FW), (0, 0, 0, 0))\n'
     '        for i, k in enumerate(idx):\n'
     '            fr = Image.new("RGBA", (CENT2_FW, CENT2_FW), (0, 0, 0, 0))\n'
     '            fr.alpha_composite(Image.open(fp(k)).convert("RGBA"), (dx, dy)) if dx >= 0 and dy >= 0 else fr.paste(Image.open(fp(k)).convert("RGBA"), (dx, dy))\n'
     '            out.paste(fr, (i * CENT2_FW, 0))\n'
     '        out.save(os.path.join(VFX, dst + ".png"), optimize=False)\n'
     '        print(dst, len(idx), "帧", CENT2_FW, "方 · 位移", (dx, dy))\n'
     '    for dst, srcs in STRIPS.items():\n'),
]
for a, b in PAIRS:
    assert s.count(a) == 1, a[:70]
    s = s.replace(a, b)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
