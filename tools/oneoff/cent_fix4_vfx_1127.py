"""cent_fix4_vfx_1127.py —— cent_fix4_1127.py 的演出段(主脚本前两段已生效、这段锚点写错后重跑)。 —— 百夫长第四轮(用户 11-27):
  「原本的四到五针之间要补一针…扛着这个矛…转身准备投掷」⇒ throw_mix 第三版 15 帧(见 ai_src/cent_char/throw_mix/SOURCE.txt), @14 ≈ 1.07 秒, 出手 = 下标 4(0.29 秒)
  「矛刺出去…特效肯定是要贴着这个矛来做」⇒ 普攻叠加帧条 eq-centurion-attack-glow(tools/assetgen/build_cent_spear_glow.py 按逐帧量的矛坐标画):
      每帧跟本体同帧号 / 同位置 / 同朝向 / 同像素尺寸, 只在本体正播普攻帧条时可见 ⇒ 光永远贴在矛上; 删掉上一轮钉在命中点的 _cent_tip_flash
      叠加节点登记进 _mfx(hold 帧号每帧跟本体), 直播录得到
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


patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ("\t_cent_play(u, \"throw\", 16.0)   # 17 帧 @16, 出手帧下标 6(结算 THROW_RELEASE 0.38 同一刻)\n",
     "\t_cent_play(u, \"throw\", 14.0)   # 15 帧 @14, 出手帧下标 4(结算 THROW_RELEASE 0.29 同一刻)\n"),
    ("\t_cent_tip_flash(u)\n", "\t_cent_glow_on(u)   # 矛刃光叠加层(贴着矛, 跟本体同帧)\n"),
    ("func _cent_tip_flash(u: Dictionary) -> void:\n",
     "## 普攻矛刃光叠加层: 一只百夫长一个节点, 首次普攻时建; 每帧跟本体同帧号 / 位置 / 朝向 / 尺寸, 只在本体播普攻帧条时显示\n"
     "const CENT_GLOW_TEX := \"res://assets/sprites/vfx/eq-centurion-attack-glow.png\"\n"
     "var _cent_glows: Array = []   # {u, node, mf}\n"
     "\n"
     "func _cent_glow_on(u: Dictionary) -> void:\n"
     "\tfor g in _cent_glows:\n"
     "\t\tif is_same(g[\"u\"], u):\n"
     "\t\t\treturn\n"
     "\tif not _ok() or not ResourceLoader.exists(CENT_GLOW_TEX):\n"
     "\t\treturn\n"
     "\tvar t: Texture2D = load(CENT_GLOW_TEX)\n"
     "\tvar s := Sprite3D.new()\n"
     "\ts.texture = t\n"
     "\ts.hframes = maxi(1, t.get_width() / 192)\n"
     "\ts.shaded = false\n"
     "\ts.transparent = true\n"
     "\ts.no_depth_test = true\n"
     "\ts.render_priority = 9\n"
     "\ts.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n"
     "\ts.billboard = BaseMaterial3D.BILLBOARD_ENABLED\n"
     "\tbattle._world.add_child(s)\n"
     "\t_mfx.append({\"node\": s, \"nf\": s.hframes, \"fps\": 0.0, \"t\": 0.0, \"life\": 0.0, \"loop\": false, \"follow\": null, \"h\": 0.0, \"hold\": 0})\n"
     "\t_cent_glows.append({\"u\": u, \"node\": s, \"mf\": _mfx.back()})\n"
     "\t_tick_cent_glows()\n"
     "\n"
     "\n"
     "func _tick_cent_glows() -> void:\n"
     "\tvar keep: Array = []\n"
     "\tfor g in _cent_glows:\n"
     "\t\tvar n = g[\"node\"]\n"
     "\t\tvar u: Dictionary = g[\"u\"]\n"
     "\t\tvar spr = u.get(\"sprite\", null)\n"
     "\t\tif n == null or not is_instance_valid(n) or not is_instance_valid(spr) or not u.get(\"alive\", false):\n"
     "\t\t\t_free(n)\n"
     "\t\t\tcontinue\n"
     "\t\tvar s: Sprite3D = n\n"
     "\t\tvar src: Sprite3D = spr\n"
     "\t\tvar tx = (u.get(\"anim_sd\", {}) as Dictionary).get(\"tex\", null)\n"
     "\t\tvar on: bool = tx != null and (tx as Texture2D).resource_path.ends_with(\"eq-centurion-attack.png\") and src.frame < s.hframes\n"
     "\t\t(g[\"mf\"] as Dictionary)[\"hold\"] = src.frame if on else 0\n"
     "\t\ts.frame = src.frame if on else 0\n"
     "\t\ts.modulate = Color(1.0, 1.0, 1.0, 1.0 if on else 0.0)\n"
     "\t\ts.pixel_size = src.pixel_size\n"
     "\t\ts.offset = src.offset\n"
     "\t\ts.flip_h = src.flip_h\n"
     "\t\ts.global_position = src.global_position\n"
     "\t\tkeep.append(g)\n"
     "\t_cent_glows = keep\n"
     "\n"
     "\n"
     "func _cent_tip_flash_unused(u: Dictionary) -> void:   # 上一轮钉在命中点的版本(矛收回后光还浮着), 11-27 第四轮起不用\n"),
    ("\t_tick_fall(delta)\n\t_tick_aegis()\n",
     "\t_tick_fall(delta)\n\t_tick_aegis()\n\t_tick_cent_glows()\n"),
    ("func clear() -> void:\n\tsuper.clear()\n\t_stig.clear()\n",
     "func clear() -> void:\n\tsuper.clear()\n\t_cent_glows.clear()\n\t_stig.clear()\n"),
])
print("ok")
