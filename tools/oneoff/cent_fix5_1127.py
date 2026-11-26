"""cent_fix5_1127.py —— 百夫长第五轮(用户 11-27, 方案书附录 C):
  「矩阵感觉你离参考的有点远」⇒ 龟甲阵照潘森 E(研究稿 docs/studies/20261127-龟甲阵参考-潘森E逐帧.md):
      ① 盾面换成朝敌人那一侧的金色半弧能量盾(特效工作台自写图层 centurion-arc-shield-open 4 帧 @20 + loop 8 帧 @12; 画里弧朝左鼓)
      ② 撑盾时人不再死站: 每 0.5 秒(= 结算 POKE_IV, 第一下 0.5 秒)从盾上沿往前一捅再收回(PixelLab 自定义动作 brace_jab, 跟撑盾帧逐像素对齐)
         帧条 eq-centurion-shield 42 帧 @14 = 3 秒: 举盾 6 帧 + 撑盾 36 帧(第 6/13/20/27/34 帧后拉, 第 7–8/14–15/… 帧捅出 = 0.5/1.0/…/2.5 秒)
      ③ 举盾那一下本体闪白金
  「普通攻击…矛刺出去…想要那种明显一点的冲击罩」⇒ 刺到最远那一帧在矛尖前炸开冲击罩
      (特效工作台自写图层 centurion-thrust-impact: 中心白闪 → 朝前的半月冲击环 + 往外推的气浪 + 速度线, 7 帧 @20), 矛刃光叠加层保留
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
import shutil

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


## ① shield_mix: 0 = shield_brace2 站姿(打包对齐用) / 1..6 = 举盾 brace 3..8 / 7 = 后拉 / 8, 9 = 捅出(brace_jab 1..3, 贴到 180 画布偏移 (-36,-2))
from PIL import Image
CC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "cent_char")
MIX = os.path.join(CC, "shield_mix")
os.makedirs(MIX, exist_ok=True)
shutil.copyfile(os.path.join(CC, "shield_brace2", "frame_000.png"), os.path.join(MIX, "frame_000.png"))
for i, k in enumerate([3, 4, 5, 6, 7, 8]):
    shutil.copyfile(os.path.join(CC, "shield_brace2", "frame_%03d.png" % k), os.path.join(MIX, "frame_%03d.png" % (i + 1)))
for i, k in enumerate([1, 2, 3]):
    src = Image.open(os.path.join(CC, "brace_jab", "frame_%03d.png" % k)).convert("RGBA")
    fr = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
    fr.alpha_composite(src.crop((36, 2, 216, 182)))
    fr.save(os.path.join(MIX, "frame_%03d.png" % (7 + i)), optimize=False)
open(os.path.join(MIX, "SOURCE.txt"), "w", encoding="utf-8").write(
    "shield_mix(11-27 cent_fix5_1127.py 生成, 重跑逐字节相同)\n"
    "000 = shield_brace2/000(站姿, 打包时只用来对齐包围盒)\n"
    "001-006 = shield_brace2/003-008(下蹲举盾)\n"
    "007 = brace_jab/001(盾后把矛往回拉) · 008 = brace_jab/002 · 009 = brace_jab/003(从盾上沿捅出)\n"
    "brace_jab = PixelLab pixminimax 自定义动作, 首帧 = shield_brace2/008; 252×184 画布, 与 180 画布偏移 (-36,-2) 逐像素对上\n")

hold = []
for p in range(6, 42):
    if (p + 1) % 7 == 0:
        hold.append(7)
    elif p % 7 == 0:
        hold.append(8)
    elif p % 7 == 1:
        hold.append(9)
    else:
        hold.append(6)
IDX = [1, 2, 3, 4, 5, 6] + hold
assert len(IDX) == 42 and IDX[7] == 8 and IDX[6] == 7 and IDX[35] == 8, IDX

patch("tools/assetgen/pack_spear_chip_art.py", [
    ('    "eq-centurion-shield": ("shield_brace2", [3, 4, 5, 6, 7, 8] + [8] * 36),',
     '    "eq-centurion-shield": ("shield_mix",    %r),   # 11-27 附录 C: 举盾 6 帧 + 撑盾 36 帧, 每 7 帧(0.5 秒 @14)从盾上沿捅一下(见 shield_mix/SOURCE.txt) #' % IDX),
    ('            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False),',
     '            ("centurion-arc-shield-open+centurion-arc-shield-loop", "spear-cent-aegis", False), ("centurion-thrust-impact", "spear-cent-dome", False),'),
])

patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ("const AEGIS_FWD := 46.0     # 立在身前多远(码)\n"
     "const AEGIS_H_M := 3.4      # 能量盾高(米)\n"
     "const AEGIS_NF := 13        # 帧条: 0..4 展开(16 fps) + 5..12 循环(12 fps)\n"
     "const AEGIS_OPEN := 5\n",
     "## 11-27 附录 C(照潘森 E): 竖长方形板 → 朝敌人那一侧的金色半弧能量盾(画里弧朝左鼓), 比人高半个身位\n"
     "const AEGIS_FWD := 40.0     # 立在身前多远(码)\n"
     "const AEGIS_H_M := 4.4      # 能量盾高(米)\n"
     "const AEGIS_NF := 12        # 帧条: 0..3 张开(20 fps) + 4..11 循环(12 fps)\n"
     "const AEGIS_OPEN := 4\n"
     "const AEGIS_OPEN_FPS := 20.0\n"),
    ("\t_cent_play(u, \"shield\", float(nf) / maxf(0.5, sec))\n",
     "\t_cent_play(u, \"shield\", float(nf) / maxf(0.5, sec))   # 42 帧 / 3 秒 = 14 fps: 盾后出刺的捅出帧恰好落在 0.5 / 1.0 / … 秒(= 结算 POKE_IV)\n"
     "\tbattle._vfx._flash(u, Color(1.0, 0.9, 0.55), 0.12)   # 扎稳那一下本体闪白金\n"),
    ("\t\t(n as Sprite3D).flip_h = fx < 0.0\n"
     "\t\tif a.get(\"mf\") is Dictionary:   # 展开段放一次(16 fps), 之后循环段(12 fps); 在 super.tick 的通用推帧之后覆盖\n"
     "\t\t\tvar at: float = float((a[\"mf\"] as Dictionary)[\"t\"])\n"
     "\t\t\tvar ok: float = float(AEGIS_OPEN) / 16.0\n"
     "\t\t\t(n as Sprite3D).frame = mini(AEGIS_OPEN - 1, int(at * 16.0)) if at < ok else AEGIS_OPEN + (int((at - ok) * 12.0) % (AEGIS_NF - AEGIS_OPEN))\n",
     "\t\t(n as Sprite3D).flip_h = fx > 0.0   # 画里弧朝左鼓 ⇒ 敌人在右边就翻过来\n"
     "\t\tif a.get(\"mf\") is Dictionary:   # 张开段放一次(20 fps), 之后循环段(12 fps); 在 super.tick 的通用推帧之后覆盖\n"
     "\t\t\tvar at: float = float((a[\"mf\"] as Dictionary)[\"t\"])\n"
     "\t\t\tvar ok: float = float(AEGIS_OPEN) / AEGIS_OPEN_FPS\n"
     "\t\t\t(n as Sprite3D).frame = mini(AEGIS_OPEN - 1, int(at * AEGIS_OPEN_FPS)) if at < ok else AEGIS_OPEN + (int((at - ok) * 12.0) % (AEGIS_NF - AEGIS_OPEN))\n"),
    ("\t_cent_glow_on(u)   # 矛刃光叠加层(贴着矛, 跟本体同帧)\n",
     "\t_cent_glow_on(u)   # 矛刃光叠加层(贴着矛, 跟本体同帧)\n"
     "\t_cent_impact_dome(u)   # 矛尖前炸开的冲击罩(附录 C)\n"),
    ("func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:\n",
     "## 普攻冲击罩(11-27 用户「矛刺出去…想要那种明显一点的冲击罩」): 刺到最远那一帧(本体普攻帧 5, 矛尖在帧里 (21,161), 脚底 (96,191)\n"
     "##   ⇒ 立足点往前 75 像素、离地 30 像素)炸开: 中心白闪 → 朝前的半月冲击环 + 气浪 + 速度线, 7 帧 @20\n"
     "##   帧 112×96 里矛尖锚点 (80,48), 冲击往画面左边(= 刺的方向)推; 比本体放大 1.8 倍\n"
     "const CENT_IMP_FWD_PX := 75.0\n"
     "const CENT_IMP_UP_PX := 30.0\n"
     "const CENT_IMP_SCALE := 1.8\n"
     "\n"
     "func _cent_impact_dome(u: Dictionary) -> void:\n"
     "\tvar spr = u.get(\"sprite\", null)\n"
     "\tif not _ok() or not is_instance_valid(spr) or not ResourceLoader.exists(SV + \"spear-cent-dome.png\"):\n"
     "\t\treturn\n"
     "\tvar px: float = float((spr as Sprite3D).pixel_size)\n"
     "\tvar fr: bool = bool((spr as Sprite3D).flip_h)   # 原画朝左; 翻转 = 朝右\n"
     "\tvar t: Texture2D = load(SV + \"spear-cent-dome.png\")\n"
     "\tvar s := Sprite3D.new()\n"
     "\ts.texture = t\n"
     "\ts.hframes = 7\n"
     "\ts.shaded = false\n"
     "\ts.transparent = true\n"
     "\ts.no_depth_test = true\n"
     "\ts.render_priority = 10\n"
     "\ts.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n"
     "\ts.billboard = BaseMaterial3D.BILLBOARD_ENABLED\n"
     "\ts.pixel_size = px * CENT_IMP_SCALE\n"
     "\ts.flip_h = fr\n"
     "\ts.offset = Vector2((56.0 - 80.0) * (-1.0 if fr else 1.0), 0.0)   # 锚点(矛尖)对上节点位置\n"
     "\tvar base: Vector3 = (spr as Sprite3D).global_position\n"
     "\tvar cb: Basis = battle._cam.global_transform.basis if battle.get(\"_cam\") != null else Basis.IDENTITY   # 立绘是朝镜头的板: 帧里的左右 / 上下 = 镜头的 x / y 轴\n"
     "\ts.position = base + cb.x * (CENT_IMP_FWD_PX * px * (1.0 if fr else -1.0)) + cb.y * (CENT_IMP_UP_PX * px)\n"
     "\tbattle._world.add_child(s)\n"
     "\t_mfx.append({\"node\": s, \"nf\": 7, \"fps\": 20.0, \"t\": 0.0, \"life\": 7.0 / 20.0, \"loop\": false, \"follow\": null, \"h\": 0.0})\n"
     "\n"
     "\n"
     "func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:\n"),
])
print("ok", IDX)
