"""cent_aegis_redo_1127.py —— 龟甲阵能量盾重做(11-27 自查: 原来是一面不透明的金色实心盾牌, 中间两帧还裂开 / 十字闪, 不像能量盾)
新的: PixelLab 特效工作台自写图层 —— 半透明浅金盾面(罗马大盾轮廓) + 亮边呼吸 + 一道扫光从上往下 + 若隐若现的鹰徽(我在配方里按像素画的) + 边上星点;
展开段 5 帧(亮边沿轮廓画出 → 盾面与鹰徽充满, 中间一下白光)+ 循环段 8 帧, 打包成一条 13 帧: 前 5 帧放一次, 之后 5..12 循环。
改: pack_spear_chip_art.py(STRIPS 里旧的 caeg 一行换成网格拼接) · spear_eq_vfx.gd(cent_shield 按段放帧, _tick_aegis 推帧)。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("tools/assetgen/pack_spear_chip_art.py", [
    ('    "spear-cent-aegis": [(SP, "caeg_%d" % i, False) for i in range(0, 6)],\n',
     '    ## spear-cent-aegis: 11-27 自查返工改由下面 GRIDS 拼(特效工作台 aegis-open 5 帧 + aegis-loop 8 帧); 旧的 caeg_0..5(金色实心盾)留在 ai_src 不用\n'),
    ('    for src, dst, centre in [("centurion-ground-erupt", "spear-cent-erupt", True), ("centurion-crack-segment", "spear-cent-crack", False)]:\n',
     '    for src, dst, centre in [("centurion-ground-erupt", "spear-cent-erupt", True), ("centurion-crack-segment", "spear-cent-crack", False),\n'
     '            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False)]:\n'
     '        if "+" in src:   # 两段接成一条(先展开后循环)\n'
     '            parts = []\n'
     '            for one in src.split("+"):\n'
     '                mj = json.load(open(os.path.join(CV, one + ".json"), encoding="utf-8"))\n'
     '                sh = Image.open(os.path.join(CV, one + ".png")).convert("RGBA")\n'
     '                for f in mj["frames"]:\n'
     '                    r = f["frame"]\n'
     '                    parts.append(sh.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))\n'
     '            fw0, fh0 = parts[0].size\n'
     '            out = Image.new("RGBA", (fw0 * len(parts), fh0), (0, 0, 0, 0))\n'
     '            for i, im in enumerate(parts):\n'
     '                out.paste(im, (i * fw0, 0))\n'
     '            out.save(os.path.join(VFX, dst + ".png"), optimize=False)\n'
     '            print(dst, len(parts), "帧", fw0, "×", fh0)\n'
     '            continue\n'),
])

patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ('\tvar s := _strip(SV + "spear-cent-aegis.png", 6, battle._world_pos(Vector2(u["pos"]), 0.0), AEGIS_H_M, 10.0, true, sec, false, null, 0.0)\n'
     '\tif s != null:\n'
     '\t\ts.modulate = Color(1.15, 1.1, 1.0, 0.86)\n'
     '\t\t_aegis.append({"u": u, "node": s})\n',
     '\t## 11-27 自查重做: 半透明能量盾(13 帧 = 展开 5 + 循环 8), 帧号由 _tick_aegis 推: 展开放一次、之后循环段\n'
     '\tvar s := _strip(SV + "spear-cent-aegis.png", AEGIS_NF, battle._world_pos(Vector2(u["pos"]), 0.0), AEGIS_H_M, 0.0, true, sec, false, null, 0.0)\n'
     '\tif s != null:\n'
     '\t\ts.frame = 0\n'
     '\t\t_aegis.append({"u": u, "node": s, "mf": _mfx.back()})   # mf: 借通用帧推进的计时(t 累加), 帧号这里自己算\n'),
    ('\t\t(n as Sprite3D).flip_h = fx < 0.0\n\t\tkeep.append(a)\n',
     '\t\t(n as Sprite3D).flip_h = fx < 0.0\n'
     '\t\tif a.get("mf") is Dictionary:   # 展开段放一次(16 fps), 之后循环段(12 fps); 在 super.tick 的通用推帧之后覆盖\n'
     '\t\t\tvar at: float = float((a["mf"] as Dictionary)["t"])\n'
     '\t\t\tvar ok: float = float(AEGIS_OPEN) / 16.0\n'
     '\t\t\t(n as Sprite3D).frame = mini(AEGIS_OPEN - 1, int(at * 16.0)) if at < ok else AEGIS_OPEN + (int((at - ok) * 12.0) % (AEGIS_NF - AEGIS_OPEN))\n'
     '\t\tkeep.append(a)\n'),
    ('const AEGIS_H_M := 3.4      # 能量盾高(米)\n',
     'const AEGIS_H_M := 3.4      # 能量盾高(米)\n'
     'const AEGIS_NF := 13        # 帧条: 0..4 展开(16 fps) + 5..12 循环(12 fps)\n'
     'const AEGIS_OPEN := 5\n'),
])
print("ok")
