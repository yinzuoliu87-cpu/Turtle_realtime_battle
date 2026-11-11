# -*- coding: utf-8 -*-
"""铁链手端按人物图像素算(用户 11-11「射出这个锁链的时候…有从手上射出来吗？你自己没看吗？」)
+ 近战人体浪板踩在目标身上(用户 11-11「自己踩到对面的时候…应该踩在他身上…在他体型的上方」)。
原来手端 = 沿地面朝目标前推 N 码、离地 M 米; 人物图是正对镜头的公告板, 目标在斜下方时投到屏幕上就不在拳头上。
拳头 / 手腕像素是逐格量的(tools 量法: 每格手伸出那一侧最外沿 6 像素以内不透明像素的平均, 标回图上逐格核过)。
CRLF / LF 保留原样。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


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


patch("scripts/systems/skills/elite_system.gd", [
	('const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")\n',
	 'const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")\n'
	 'const SpriteArt := preload("res://scripts/util/sprite_art.gd")\n'),
	('const WHIP_BACK_TIP := 66.0            # 链头拖在身后地面多远(码): 拳头到链头约 1.1 米一节链\n',
	 'const WHIP_BACK_TIP := 66.0            # 链头拖在身后地面多远(码): 拳头到链头约 1.1 米一节链\n'
	 '## ★11-11 链子手端改按人物图像素(用户「射出这个锁链的时候…有从手上射出来吗？」): whip.png 11 格每格拳头最外沿(帧内坐标, 192×192 帧)。\n'
	 '##   格 → 图: [0,1,2,2,2,3,4,4,4,4,5](build_minion_redo.py); 0 往地上甩(拳头垂在身后)/ 1 后拉 / 2~4 甩出 / 5 被拽前倾 / 6~9 拉平飞 / 10 落地砍。\n'
	 '##   上面 WHIP_FIST_FWD / WHIP_BACK_HAND_* 只在拿不到人物图(或已不在播 whip)时兜底。\n'
	 'const WHIP_FIST_ART := [Vector2(142, 145), Vector2(158, 121), Vector2(18, 110), Vector2(18, 110), Vector2(18, 110),\n'
	 '	Vector2(46, 108), Vector2(28, 104), Vector2(28, 104), Vector2(28, 104), Vector2(28, 104), Vector2(162, 130)]\n'
	 'const WHIP_BACK_TIP_ART := Vector2(212.0, 176.0)   # 身后拖地的链头: 后甩拳头再往后约 60 像素、脚底那一行(屏幕上一定在身后地上)\n'),
	('	var fist := func() -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return battle._world_pos((u["pos"] as Vector2) + dn * WHIP_FIST_FWD, float(u.get("height", 0.0)) + WHIP_FIST_UP)\n',
	 '	var fist := func() -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return _whip_fist(u, battle._world_pos((u["pos"] as Vector2) + dn * WHIP_FIST_FWD, float(u.get("height", 0.0)) + WHIP_FIST_UP))\n'),
	('		return battle._world_pos((u["pos"] as Vector2) - dn * back, float(u.get("height", 0.0)) + up)\n'
	 '	var back_tip := func(_q: float) -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return battle._world_pos((u["pos"] as Vector2) - dn * WHIP_BACK_TIP, 0.06)\n',
	 '		return _whip_fist(u, battle._world_pos((u["pos"] as Vector2) - dn * back, float(u.get("height", 0.0)) + up))\n'
	 '	var back_tip := func(_q: float) -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		var fb: Vector3 = battle._world_pos((u["pos"] as Vector2) - dn * WHIP_BACK_TIP, 0.06)\n'
	 '		if str(u.get("anim_action", "")) != "whip":\n'
	 '			return fb\n'
	 '		var p: Vector3 = SpriteArt.point(battle, u, WHIP_BACK_TIP_ART, fb)\n'
	 '		p.y = maxf(p.y, 0.06)                                       # 贴地(人在空中时也躺在地上)\n'
	 '		return p\n'),
	('## 拉人进度 q(0 ~ 1): 链随人往前飞自己变短',
	 '## 链子手端 = 人物图当前这一格的拳头像素(只在播 whip 时; 别的动作 / 拿不到人物图 ⇒ fallback)\n'
	 'func _whip_fist(u: Dictionary, fallback: Vector3) -> Vector3:\n'
	 '	if str(u.get("anim_action", "")) != "whip":\n'
	 '		return fallback\n'
	 '	var s = u.get("sprite", null)\n'
	 '	if not (s is Sprite3D) or not is_instance_valid(s):\n'
	 '		return fallback\n'
	 '	var f: int = clampi((s as Sprite3D).frame, 0, WHIP_FIST_ART.size() - 1)\n'
	 '	return SpriteArt.point(battle, u, WHIP_FIST_ART[f], fallback)\n'
	 '\n'
	 '\n'
	 '## 拉人进度 q(0 ~ 1): 链随人往前飞自己变短'),
])

patch("scripts/systems/skills/hiding_system.gd", [
	('class_name HidingSystem\nextends RefCounted\n',
	 'class_name HidingSystem\nextends RefCounted\nconst SpriteArt := preload("res://scripts/util/sprite_art.gd")\n'),
	('const SURF_CHEST_UP := 0.9            # 目标胸口离脚底多高(米)\n',
	 'const SURF_CHEST_UP := 0.9            # 目标胸口离脚底多高(米)\n'
	 '## ★11-11 链子手端改按人物图像素(用户「射出这个锁链的时候…有从手上射出来吗？」): 手腕(三刺头射出后空着的护手口)帧内坐标。\n'
	 '##   throw.png 6 格同一张图; dive.png 8 格手腕随身体前倾往下 2 ~ 5 像素。上面 SURF_WRIST_* 只在拿不到人物图时兜底。\n'
	 'const SURF_WRIST_ART_THROW := Vector2(62, 123.6)\n'
	 'const SURF_WRIST_ART_DIVE := [Vector2(62, 125.6), Vector2(62, 128.2), Vector2(62, 129.1), Vector2(62, 129.1),\n'
	 '	Vector2(62, 129.1), Vector2(62, 129.1), Vector2(62, 129.1), Vector2(62, 129.1)]\n'
	 '## 踩人高度(用户 11-11「应该踩在他身上…在他体型的上方」): 目标当前这一格本体顶部(SpriteArt.top_m); 拿不到人物图 ⇒ 这个兜底\n'
	 'const SURF_RIDE_H_FALLBACK := 1.2\n'),
	('		return battle._world_pos((uu["pos"] as Vector2) + dn * SURF_WRIST_FWD, float(uu.get("height", 0.0)) + SURF_WRIST_UP)\n',
	 '		var fb: Vector3 = battle._world_pos((uu["pos"] as Vector2) + dn * SURF_WRIST_FWD, float(uu.get("height", 0.0)) + SURF_WRIST_UP)\n'
	 '		var act := str(uu.get("anim_action", ""))\n'
	 '		var s = uu.get("sprite", null)\n'
	 '		if act == "throw":\n'
	 '			return SpriteArt.point(battle, uu, SURF_WRIST_ART_THROW, fb)\n'
	 '		if act == "dive" and s is Sprite3D and is_instance_valid(s):\n'
	 '			return SpriteArt.point(battle, uu, SURF_WRIST_ART_DIVE[clampi((s as Sprite3D).frame, 0, SURF_WRIST_ART_DIVE.size() - 1)], fb)\n'
	 '		return fb\n'),
	('	var h0: float = float(u.get("height", 0.0))           # 从空中悬停高度俯冲下来\n',
	 '	var h0: float = float(u.get("height", 0.0))           # 从空中悬停高度俯冲下来\n'
	 '	var ride_h: float = SpriteArt.top_m(tref, SURF_RIDE_H_FALLBACK)   # 落到目标背上(本体顶部), 不是和目标叠在一起\n'),
	('			u["height"] = PullCurve.dive_height(kk, h0, 0.3)\n',
	 '			u["height"] = PullCurve.dive_height(kk, h0, ride_h)\n'),
	('		u["height"] = 0.3                                  # 踩在目标身上(略高=站在冲浪板上·参考浪板)\n',
	 '		u["height"] = ride_h                               # 踩在目标背上(用户 11-11「在他体型的上方」; 原 0.3 米 = 和目标叠在一起)\n'),
	('			u["height"] = 0.3 + 1.5 * 4.0 * q * (1.0 - q)   # 跳弧\n',
	 '			u["height"] = ride_h * (1.0 - q) + 1.5 * 4.0 * q * (1.0 - q)   # 从目标背上跳下来的弧\n'),
])
