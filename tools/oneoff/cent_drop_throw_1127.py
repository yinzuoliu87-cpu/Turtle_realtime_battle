"""cent_drop_throw_1127.py —— 百夫长登场与掷矛节奏(用户 11-27, 方案书 20261126 附录 B):
登场「出现一个预警图标…标记圈，然后…把这个矛插到这个标记圈中心，随后角色是从一个很高的高度砸下来的，而不是…空中突然变出来的」:
  · 结算 LAND_SEC 0.7 → 1.2; 演出: 0 秒落点亮出预警标记圈(spear-cent-marker, 特效工作台自写图层: 金环 + 月桂叶 + 红底 + 像素鹰徽);
    0.35 秒他自己的长矛(掷矛同一张 pilum 转成矛尖朝下)从高空直插圈心(扬尘 + 金光 + 轻震); 0.75–1.2 秒本人从画面外的高空(30 米)
    加速砸下、身后残影; 1.2 秒砸地接整岛地裂。删掉旧的通用金光柱 spear-cent-beam。
掷矛「普攻回到 idle，然后再在 idle 这上面去投掷这个矛，投掷的时候不普攻啊，完成投掷动作再普攻」:
  · 第 3 下普攻命中后 THROW_LEAD 秒(刺的动作收回、待机停一拍)起手掷矛, 掷矛动作 THROW_ANIM 秒、出手帧 THROW_RELEASE 秒才发飞矛;
    整段定身不普攻(channel), 掷完恢复普攻; 这次掷矛占用第 4 下那一拍(n_atk +1)。原来第 4 下前摇播「刺」、命中那刻换成扔、下一记马上顶上。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
from PIL import Image

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


# ── 结算 ──
patch("scripts/systems/equip/spear_synergy_system.gd", [
    ("const LAND_SEC := 0.7\n",
     "const LAND_SEC := 1.2   # 11-27 用户: 预警标记圈 → 长矛插进圈心(0.35)→ 本人从高空砸下(0.75–1.2), 方案书附录 B\n"),
    ("const THROW_W := 30.0\n",
     "const THROW_W := 30.0\n"
     "## 掷矛节奏(11-27 用户「普攻回到 idle，然后再在 idle 这上面去投掷…投掷的时候不普攻…完成投掷动作再普攻」):\n"
     "##   第 3 下普攻命中后 THROW_LEAD 秒起手, 掷矛动作 THROW_ANIM 秒(帧条 7 帧 @12), 出手帧 THROW_RELEASE 秒才发飞矛; 整段定身\n"
     "const THROW_LEAD := 0.45\n"
     "const THROW_ANIM := 0.58\n"
     "const THROW_RELEASE := 0.17\n"),
    ('\t## 4 档: 每第 4 下掷矛(扔向最远的敌人)\n'
     '\tif tier >= 4 and int(r["n_atk"]) % THROW_EVERY == 0:\n'
     '\t\t_throw(u)\n'
     '\t\treturn\n',
     ''),
    ('\t_fx("cent_thrust", [u, t, hits.size()])\n',
     '\t_fx("cent_thrust", [u, t, hits.size()])\n'
     '\t## 4 档: 第 3 下刺完 ⇒ 回待机再起手掷矛(占用第 4 下那一拍, 见 THROW_LEAD)\n'
     '\tif tier >= 4 and int(r["n_atk"]) % THROW_EVERY == THROW_EVERY - 1:\n'
     '\t\t_throw_schedule(r)\n'),
    ("\nfunc _throw(u: Dictionary) -> void:\n",
     "\n## 掷矛排程: 从现在起定身到掷完(不出普攻); THROW_LEAD 后起手(播掷矛动作), 再过 THROW_RELEASE 出手发飞矛。被晕 / 击飞 ⇒ 这次掷矛取消(cc 组)\n"
     "func _throw_schedule(r: Dictionary) -> void:\n"
     "\tvar u: Dictionary = r[\"u\"]\n"
     "\tbattle._damage.channel(u, THROW_LEAD + THROW_ANIM)\n"
     "\tvar g := {}\n"
     "\tbattle._pending_shots.append({\"delay\": THROW_LEAD, \"src\": u, \"cc\": g, \"fn\": func() -> void:\n"
     "\t\tif u.get(\"alive\", false):\n"
     "\t\t\t_fx(\"cent_throw_begin\", [u])})\n"
     "\tbattle._pending_shots.append({\"delay\": THROW_LEAD + THROW_RELEASE, \"src\": u, \"cc\": g, \"fn\": func() -> void:\n"
     "\t\tif u.get(\"alive\", false):\n"
     "\t\t\tr[\"n_atk\"] = int(r[\"n_atk\"]) + 1\n"
     "\t\t\t_throw(u)})\n"
     "\n\nfunc _throw(u: Dictionary) -> void:\n"),
])

# ── 演出 ──
patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ('func cent_land(p: Dictionary, sec: float) -> void:\n'
     '\tp["_slam_voff"] = Vector3(0.0, LAND_H, 0.0)\n'
     '\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec)})\n'
     '\tvar beam := _strip(V + "spear-cent-beam.png", 6, battle._world_pos(Vector2(p["pos"]), 0.0), 9.5, 14.0, true, sec + 0.15, false, null, 0.0)\n'
     '\tif beam != null:\n'
     '\t\t## 光柱画在人后面、半透明: 原来不透明 + 渲染优先级高, 把顺着光柱落下来的百夫长整个挡住了(11-26 夜录像探针量出人在落、画面上看不见)\n'
     '\t\tbeam.render_priority = -2\n'
     '\t\tbeam.no_depth_test = false\n'
     '\t\tbeam.modulate = Color(1.0, 1.0, 1.0, 0.6)\n'
     '\t_cent_play(p, "shield", 42.0 / maxf(0.1, sec))   # 下落途中把盾举起, 落地时正好举满\n',
     '## 登场(11-27 用户, 方案书附录 B): 0 秒落点亮出预警标记圈 → PLANT_T 他自己的长矛从高空直插圈心 → 最后 DROP_SEC 本人从画面外高空砸下(残影)\n'
     '##   → 落地那一步(cent_impact)裂坑 + 震屏 + 整岛地裂。旧的通用金光柱删了(用户「这个落下的这个光特效，你是不是偷偷复用了什么东西」)。\n'
     'const MARKER_M := 4.0      # 预警标记圈直径(米)\n'
     'const DROP_H := 30.0       # 本人从多高砸下来(米, 画面外)\n'
     'const DROP_SEC := 0.45     # 砸下来用时(落地前最后这段)\n'
     'const PLANT_T := 0.35      # 长矛插进圈心的时刻\n'
     'const PLANT_FALL := 0.12   # 长矛从高空落下用时\n'
     'const PLANT_H0 := 16.0     # 长矛从多高落(米)\n'
     'const PLANT_M := 2.6       # 插着的长矛高(米)\n'
     'const PLANT_BURY := 0.35   # 矛尖扎进地里多深(米)\n'
     '\n'
     'func cent_land(p: Dictionary, sec: float) -> void:\n'
     '\tp["_slam_voff"] = Vector3(0.0, DROP_H, 0.0)   # 先在画面外的高空\n'
     '\tvar mk := _strip(V + "spear-cent-marker.png", 8, battle._world_pos(Vector2(p["pos"]), 0.05), MARKER_M, 10.0, true, sec + 0.05, true, null, 0.0)\n'
     '\tvar sp: Sprite3D = null\n'
     '\tif _ok() and ResourceLoader.exists(V + "spear-cent-plant.png"):\n'
     '\t\tsp = Sprite3D.new()\n'
     '\t\tsp.texture = load(V + "spear-cent-plant.png")\n'
     '\t\tsp.shaded = false\n'
     '\t\tsp.transparent = true\n'
     '\t\tsp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n'
     '\t\tsp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y\n'
     '\t\tsp.pixel_size = PLANT_M / float(sp.texture.get_height())\n'
     '\t\tsp.offset = Vector2(0.0, float(sp.texture.get_height()) * 0.5)   # 原点 = 矛尖(底边)\n'
     '\t\tsp.visible = false\n'
     '\t\tbattle._world.add_child(sp)\n'
     '\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "planted": false, "ghost": 0.0})\n'
     '\t_cent_play(p, "shield", 42.0 / maxf(0.1, sec))   # 举盾下蹲的姿势砸下来, 落地时正好举满\n'
     '\n'
     '\n'
     '## 下落残影: 复制本体此刻这一帧, 金色半透明, 0.15 秒淡掉\n'
     'func _drop_ghost(u: Dictionary) -> void:\n'
     '\tvar spr = u.get("sprite", null)\n'
     '\tif not is_instance_valid(spr):\n'
     '\t\treturn\n'
     '\tvar src: Sprite3D = spr\n'
     '\tvar g := Sprite3D.new()\n'
     '\tg.texture = src.texture\n'
     '\tg.hframes = src.hframes\n'
     '\tg.vframes = src.vframes\n'
     '\tg.frame = src.frame\n'
     '\tg.pixel_size = src.pixel_size\n'
     '\tg.offset = src.offset\n'
     '\tg.flip_h = src.flip_h\n'
     '\tg.billboard = src.billboard\n'
     '\tg.shaded = false\n'
     '\tg.transparent = true\n'
     '\tg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n'
     '\tg.modulate = Color(1.0, 0.85, 0.45, 0.5)\n'
     '\tbattle._world.add_child(g)\n'
     '\tg.global_position = src.global_position\n'
     '\t_fade_out(g, 0.15)\n'),
    ('\t## 百夫长从天上砸下来\n'
     '\tvar keep: Array = []\n'
     '\tfor l in _lands:\n'
     '\t\tvar u: Dictionary = l["u"]\n'
     '\t\tl["t"] = float(l["t"]) + delta\n'
     '\t\tvar k: float = clampf(float(l["t"]) / float(l["sec"]), 0.0, 1.0)\n'
     '\t\tu["_slam_voff"] = Vector3(0.0, LAND_H * (1.0 - k * k), 0.0)   # 加速落下(落地那一刻由 cent_impact 归零)\n'
     '\t\tif k >= 1.0 or not u.get("alive", false):\n'
     '\t\t\tu["_slam_voff"] = Vector3.ZERO\n'
     '\t\t\tcontinue\n'
     '\t\tkeep.append(l)\n'
     '\t_lands = keep\n',
     '\t## 百夫长登场: 预警圈 → 长矛插进圈心 → 本人从高空砸下(残影)\n'
     '\tvar keep: Array = []\n'
     '\tfor l in _lands:\n'
     '\t\tvar u: Dictionary = l["u"]\n'
     '\t\tl["t"] = float(l["t"]) + delta\n'
     '\t\tvar t: float = float(l["t"])\n'
     '\t\tvar sec: float = float(l["sec"])\n'
     '\t\tvar t0: float = maxf(0.0, sec - DROP_SEC)\n'
     '\t\tif t < t0:\n'
     '\t\t\tu["_slam_voff"] = Vector3(0.0, DROP_H, 0.0)\n'
     '\t\telse:\n'
     '\t\t\tvar k: float = clampf((t - t0) / DROP_SEC, 0.0, 1.0)\n'
     '\t\t\tu["_slam_voff"] = Vector3(0.0, DROP_H * (1.0 - k * k), 0.0)   # 加速砸下(落地那一刻由 cent_impact 归零)\n'
     '\t\t\tl["ghost"] = float(l["ghost"]) - delta\n'
     '\t\t\tif float(l["ghost"]) <= 0.0 and k < 1.0:\n'
     '\t\t\t\tl["ghost"] = 0.04\n'
     '\t\t\t\t_drop_ghost(u)\n'
     '\t\tvar sp = l["sp"]\n'
     '\t\tif sp != null and is_instance_valid(sp):\n'
     '\t\t\tif t >= PLANT_T - PLANT_FALL:\n'
     '\t\t\t\t(sp as Sprite3D).visible = true\n'
     '\t\t\t\tvar kk: float = clampf((t - (PLANT_T - PLANT_FALL)) / PLANT_FALL, 0.0, 1.0)\n'
     '\t\t\t\t(sp as Sprite3D).position = battle._world_pos(Vector2(u["pos"]), lerpf(PLANT_H0, -PLANT_BURY, kk * kk))\n'
     '\t\t\t\tif kk >= 1.0 and not bool(l["planted"]):\n'
     '\t\t\t\t\tl["planted"] = true\n'
     '\t\t\t\t\t_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)\n'
     '\t\t\t\t\t_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(Vector2(u["pos"]), 0.3), 1.6, 20.0, false, 6.0 / 20.0, false, null, 0.0)\n'
     '\t\t\t\t\tbattle._shake(battle.JUICE_SHAKE_HEAVY * 0.35)\n'
     '\t\tif t >= sec or not u.get("alive", false):\n'
     '\t\t\tu["_slam_voff"] = Vector3.ZERO\n'
     '\t\t\tif sp != null and is_instance_valid(sp):\n'
     '\t\t\t\t_fade_out(sp as Sprite3D, 0.3)\n'
     '\t\t\tcontinue\n'
     '\t\tkeep.append(l)\n'
     '\t_lands = keep\n'),
    ('func cent_throw(u: Dictionary, s: Dictionary) -> void:\n'
     '\t_cent_play(u, "throw", 20.0)\n',
     '## 掷矛起手(结算侧第 3 下刺完、回待机停一拍后调): 掷矛动作 7 帧 @12 = 0.58 秒, 出手帧在第 2 帧(结算 THROW_RELEASE 同一刻发飞矛)\n'
     'func cent_throw_begin(u: Dictionary) -> void:\n'
     '\t_cent_play(u, "throw", 12.0)\n'
     '\n'
     '\n'
     'func cent_throw(u: Dictionary, s: Dictionary) -> void:\n'),
])

# ── 打包: 预警圈帧条 + 插地长矛(掷矛同一张 pilum 转成矛尖朝下), 旧通用光柱删 ──
patch("tools/assetgen/pack_spear_chip_art.py", [
    ('    "spear-cent-beam": [(SP, "c3bm_%d" % i, False) for i in range(0, 6)],\n',
     '    ## spear-cent-beam(通用金光柱)11-27 删: 用户「这个落下的这个光特效，你是不是偷偷复用了什么东西」⇒ 换成预警标记圈 + 插地长矛(下面 GRIDS / PLANT)\n'),
    ('            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False)]:\n',
     '            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False), ("centurion-drop-marker", "spear-cent-marker", False)]:\n'),
    ('    ## 11-27 特效工作台网格帧表 → 横排帧条(见头注)\n',
     '    ## 11-27 登场插进标记圈的长矛 = 掷矛同一张 spear-pilum 顺时针转 90°(矛尖朝下)\n'
     '    pil = os.path.join(VFX, "spear-pilum.png")\n'
     '    if os.path.exists(pil):\n'
     '        Image.open(pil).convert("RGBA").transpose(Image.Transpose.ROTATE_270).save(os.path.join(VFX, "spear-cent-plant.png"), optimize=False)\n'
     '    ## 11-27 特效工作台网格帧表 → 横排帧条(见头注)\n'),
])
for f in ["assets/sprites/vfx/spear-cent-beam.png", "assets/sprites/vfx/spear-cent-beam.png.import"]:
    p = os.path.join(ROOT, f)
    if os.path.exists(p):
        os.remove(p)
print("ok")
