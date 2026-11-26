"""cent_fix3_1127.py —— 百夫长第三轮(用户 11-27):
  「投掷…把整个序列帧给我看一下…中间是少了一针」⇒ 掷矛补两处过渡: 握矛前倾送出 3 帧(4→5 之间) + 起身抽新矛 3 帧(10→11 之间);
      帧条 throw_mix 取 1..17 共 17 帧 @16 ≈ 1.06 秒, 出手帧 = 下标 6(握矛最后一帧之后那一帧, 0.44 秒)
  「普通攻击的那个矛刺出去的话…带点特效…直接画点特效」⇒ 普攻刺出那一下矛刃上裹一层白金突刺光(spear-cent-tip, 特效工作台自写图层:
      光刃 + 矛尖星形闪光 + 速度线, 6 帧 0.3 秒), 钉在命中帧的矛尖上(帧里量的: 相对立足点往前 75 像素、离地 25 像素)
  (预警圈 14 米 / 落地裂坑 600 码已在本轮前直接改了 spear_eq_vfx.gd)
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
    ('    "eq-centurion-throw":  ("throw_mix",     list(range(1, 13))),',
     '    "eq-centurion-throw":  ("throw_mix",     list(range(1, 18))),   # 11-27 第二版 17 帧: 后拉 3 + 握矛送出 3 + 甩出随势 6 + 起身抽新矛 3 + 站直 2(见 SOURCE.txt), @16, 出手下标 6 #'),
    ('            ("centurion-fall-trail", "spear-cent-trail", False)]:\n',
     '            ("centurion-fall-trail", "spear-cent-trail", False), ("centurion-spear-thrust-tip", "spear-cent-tip", False)]:\n'),
])

patch("scripts/systems/equip/spear_synergy_system.gd", [
    ("const THROW_ANIM := 1.0      # 11-27 重出的掷矛动作 16 帧 @16\n",
     "const THROW_ANIM := 1.06     # 11-27 掷矛 17 帧 @16(补了握矛送出 / 起身抽新矛两段过渡)\n"),
    ("const THROW_RELEASE := 0.34   # 出手帧 = 下标 4(12 fps)",
     "const THROW_RELEASE := 0.38   # 出手帧 = 下标 6(16 fps)"),
])

patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ("\t_cent_play(u, \"throw\", 12.0)   # 12 帧 = 1 秒, 出手帧下标 4(结算 THROW_RELEASE 0.34 同一刻)\n",
     "\t_cent_play(u, \"throw\", 16.0)   # 17 帧 @16, 出手帧下标 6(结算 THROW_RELEASE 0.38 同一刻)\n"),
    ("\t_dir_strip(SV + \"spear-cent-thrust.png\", 7, mid, dir, ln * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)\n",
     "\t_dir_strip(SV + \"spear-cent-thrust.png\", 7, mid, dir, ln * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)\n"
     "\t_cent_tip_flash(u)\n"),
    ("func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:\n",
     "## 普攻刺出那一下矛刃上的白金突刺光(11-27 用户「矛刺出去的话…带点特效」): 钉在命中帧的矛尖上\n"
     "##   命中帧矛尖在帧里 (21, 161), 立足点 (96, 186) ⇒ 往前 75 像素、离地 25 像素; 帧 128×48 里矛尖在 x≈18, 光刃往后延 100 像素\n"
     "const CENT_TIP_FWD_PX := 75.0\n"
     "const CENT_TIP_UP_PX := 25.0\n"
     "\n"
     "func _cent_tip_flash(u: Dictionary) -> void:\n"
     "\tvar spr = u.get(\"sprite\", null)\n"
     "\tif not _ok() or not is_instance_valid(spr) or not ResourceLoader.exists(SV + \"spear-cent-tip.png\"):\n"
     "\t\treturn\n"
     "\tvar px: float = float((spr as Sprite3D).pixel_size)\n"
     "\tvar fr: bool = bool((spr as Sprite3D).flip_h)   # 原画朝左; 翻转 = 朝右\n"
     "\tvar fwd: float = CENT_TIP_FWD_PX * px\n"
     "\tvar t: Texture2D = load(SV + \"spear-cent-tip.png\")\n"
     "\tvar s := Sprite3D.new()\n"
     "\ts.texture = t\n"
     "\ts.hframes = 6\n"
     "\ts.shaded = false\n"
     "\ts.transparent = true\n"
     "\ts.no_depth_test = true\n"
     "\ts.render_priority = 9\n"
     "\ts.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n"
     "\ts.billboard = BaseMaterial3D.BILLBOARD_ENABLED\n"
     "\ts.pixel_size = px\n"
     "\ts.flip_h = fr\n"
     "\ts.offset = Vector2((64.0 - 18.0) * (-1.0 if fr else 1.0), 0.0)   # 帧里矛尖在 x=18: 让矛尖对上锚点\n"
     "\tvar base: Vector3 = (spr as Sprite3D).global_position\n"
     "\tvar cb: Basis = battle._cam.global_transform.basis if battle.get(\"_cam\") != null else Basis.IDENTITY   # 立绘是朝镜头的板: 帧里的左右 / 上下 = 镜头的 x / y 轴\n"
     "\ts.position = base + cb.x * (fwd if fr else -fwd) + cb.y * (CENT_TIP_UP_PX * px)\n"
     "\tbattle._world.add_child(s)\n"
     "\t_mfx.append({\"node\": s, \"nf\": 6, \"fps\": 20.0, \"t\": 0.0, \"life\": 0.3, \"loop\": false, \"follow\": null, \"h\": 0.0})\n"
     "\n"
     "\n"
     "func cent_thrust(u: Dictionary, t: Dictionary, n: int) -> void:\n"),
])
print("ok")
