"""pack_patch_cent_vfx_1127.py —— 给 tools/assetgen/pack_spear_chip_art.py 加「特效工作台网格帧表 → 横排帧条」一段(11-27 百夫长自查返工)。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "tools", "assetgen", "pack_spear_chip_art.py")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")

a = "本脚本只做拷贝 / 拼接 / 量化, 重跑逐字节相同。\n"
assert s.count(a) == 1
s = s.replace(a, (
    "  · 11-27 百夫长自查返工(用户「有没有说过，它是全屏击飞的」): PixelLab 特效工作台(vfx_workbench)自己写图层画的, 不是模板改色 ——\n"
    "    ai_src/cent_vfx/centurion-ground-erupt(.json): 每个被击飞的敌人脚下的裂地爆(贴地闪电形状画金色地裂 + 贴地光 + 短金光柱 + 土块碎石 + 尘烟 + 火星, 10 帧);\n"
    "    ai_src/cent_vfx/centurion-crack-segment(.json): 俯视、两端等高可首尾拼接的一段地裂(暗缝 + 金色裂光, 8 帧), 引擎里贴地从落点铺到每个敌人。\n"
    "    工作台导出的是网格帧表 + JSON(帧位置 / 锚点), 下面 GRIDS 一段按 JSON 拆帧拼成横排; 裂地爆每帧左右补齐, 让锚点(地面点)落在帧的正中。\n"
    + a))

b = "    for dst, srcs in STRIPS.items():\n"
assert s.count(b) == 1
s = s.replace(b, (
    "    ## 11-27 特效工作台网格帧表 → 横排帧条(见头注)\n"
    "    import json\n"
    "    CV = os.path.join(ROOT, \"tools\", \"assetgen\", \"ai_src\", \"cent_vfx\")\n"
    "    for src, dst, centre in [(\"centurion-ground-erupt\", \"spear-cent-erupt\", True), (\"centurion-crack-segment\", \"spear-cent-crack\", False)]:\n"
    "        jp = os.path.join(CV, src + \".json\")\n"
    "        if not os.path.exists(jp):\n"
    "            print(\"缺帧表, 跳过\", dst)\n"
    "            continue\n"
    "        meta = json.load(open(jp, encoding=\"utf-8\"))\n"
    "        sheet = Image.open(os.path.join(CV, src + \".png\")).convert(\"RGBA\")\n"
    "        fr = meta[\"frames\"]\n"
    "        w0, h0 = fr[0][\"frame\"][\"w\"], fr[0][\"frame\"][\"h\"]\n"
    "        ax = int(round(fr[0][\"pivot\"][\"x\"] * w0))\n"
    "        fw = 2 * max(ax, w0 - ax) if centre else w0\n"
    "        dx = fw // 2 - ax if centre else 0\n"
    "        out = Image.new(\"RGBA\", (fw * len(fr), h0), (0, 0, 0, 0))\n"
    "        for i, f in enumerate(fr):\n"
    "            r = f[\"frame\"]\n"
    "            out.paste(sheet.crop((r[\"x\"], r[\"y\"], r[\"x\"] + r[\"w\"], r[\"y\"] + r[\"h\"])), (i * fw + dx, 0))\n"
    "        out.save(os.path.join(VFX, dst + \".png\"), optimize=False)\n"
    "        print(dst, len(fr), \"帧\", fw, \"×\", h0, \"锚点行\", int(round(fr[0][\"pivot\"][\"y\"] * h0)))\n"
    + b))
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
