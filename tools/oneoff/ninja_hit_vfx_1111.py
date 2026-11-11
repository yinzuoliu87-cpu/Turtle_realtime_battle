# -*- coding: utf-8 -*-
"""忍者普攻命中刀痕接进游戏(2026-11-11 用户「蒲公英(普攻)这种特效呢？攻击的命中特效」「每个角色将有自己的…命中特效」)。
① ninja_system.gd 加 basic_hit_vfx(u, tgt): 目标胸口放 ninja-hit-slash.png(build_ninja_hit_slash.py, 6 格 96×64), 固定像素尺寸逐格切;
② 主文件普攻附带效果 "bleed" 那一行(忍者斩击专属)顺带调它 —— 行数不变。CRLF / LF 保留原样。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	s = b.decode("utf-8").replace("\r\n", "\n")
	for o, n in pairs:
		if s.count(o) != 1:
			raise SystemExit("%s: 命中 %d 次: %s" % (rel, s.count(o), o[:90]))
		s = s.replace(o, n)
	if crlf:
		s = s.replace("\n", "\r\n")
	open(p, "wb").write(s.encode("utf-8"))
	print("改好", rel)


patch("scripts/systems/skills/ninja_system.gd", [
	('static func slash_bleed_stacks(u: Dictionary, crit: bool) -> int:\n'
	 '	return maxi(1, roundi(float(u.get("atk", 0.0)) * (SLASH_BLEED_ATK_CRIT if crit else SLASH_BLEED_ATK)))\n',
	 'static func slash_bleed_stacks(u: Dictionary, crit: bool) -> int:\n'
	 '	return maxi(1, roundi(float(u.get("atk", 0.0)) * (SLASH_BLEED_ATK_CRIT if crit else SLASH_BLEED_ATK)))\n'
	 '\n'
	 '## ── 普攻命中刀痕(11-11 用户「攻击的命中特效」「每个角色将有自己的…普攻和技能命中特效」)──\n'
	 '## 参考外部商业游戏(LoL Battle Boss 亚索普攻命中 + Katana ZERO 刀斩, 逐帧研究 docs/studies/20261111b-忍者普攻命中刀痕逐帧.md):\n'
	 '##   一条细长亮线斜穿目标、出现即全长再从起手端缩短 + 命中点星闪 1 ~ 2 格 + 像素碎片沿刀向迸出下落; 6 格共 0.2 秒。\n'
	 '## 图画的是「出手方朝左」(刀路右上 → 左下, 接 build_ninja_slash.py 的挥刀), 朝右时镜像。只管画面, sim 不读。\n'
	 'const HIT_SLASH_TEX := "res://assets/sprites/vfx/ninja-hit-slash.png"\n'
	 'const HIT_SLASH_FW := 96\n'
	 'const HIT_SLASH_FRAME_SEC := 1.0 / 30.0\n'
	 'const HIT_SLASH_PX := 2.0 / 64.0       # 与龟人物图同一个像素尺寸(帧高 64 像素 = 2 米), 固定不缩放\n'
	 'const HIT_SLASH_UP := 0.95             # 目标胸口离脚底多高(米)\n'
	 '\n'
	 'func basic_hit_vfx(u: Dictionary, tgt: Dictionary) -> void:\n'
	 '	if str(u.get("id", "")) != "ninja" or battle._world == null or not tgt.get("alive", false):\n'
	 '		return\n'
	 '	var tex: Texture2D = load(HIT_SLASH_TEX)\n'
	 '	if tex == null:\n'
	 '		return\n'
	 '	var s := Sprite3D.new()\n'
	 '	s.texture = tex\n'
	 '	s.hframes = maxi(1, tex.get_width() / HIT_SLASH_FW)\n'
	 '	s.frame = 0\n'
	 '	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED\n'
	 '	s.shaded = false\n'
	 '	s.transparent = true\n'
	 '	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD\n'
	 '	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST\n'
	 '	s.no_depth_test = true\n'
	 '	s.render_priority = 12                 # 画在目标身上(刀痕穿过目标, 被立绘挡住就看不出是砍中)\n'
	 '	s.pixel_size = HIT_SLASH_PX\n'
	 '	s.flip_h = bool(u.get("face_right", false))\n'
	 '	s.position = battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + HIT_SLASH_UP)\n'
	 '	battle._world.add_child(s)\n'
	 '	var n: int = s.hframes\n'
	 '	var tw = battle._reg_tween()\n'
	 '	tw.bind_node(s)\n'
	 '	tw.tween_method(func(fv: float) -> void:\n'
	 '		if is_instance_valid(s):\n'
	 '			s.frame = clampi(int(fv), 0, n - 1)\n'
	 '	, 0.0, float(n) - 0.001, HIT_SLASH_FRAME_SEC * float(n))\n'
	 '	tw.tween_callback(s.queue_free)\n'),
])
patch("scripts/scenes/RealtimeBattle3DScene.gd", [
	('		"bleed":   _damage._apply_dot_stacks(tgt, "bleed", NinjaSystem.slash_bleed_stacks(u, _last_atk_crit), u)   # 忍者斩击:',
	 '		"bleed":   _damage._apply_dot_stacks(tgt, "bleed", NinjaSystem.slash_bleed_stacks(u, _last_atk_crit), u); _ninja_sys.basic_hit_vfx(u, tgt)   # 忍者斩击(+命中刀痕 11-11):'),
])
