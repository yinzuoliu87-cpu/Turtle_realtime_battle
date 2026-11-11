# -*- coding: utf-8 -*-
"""三种小将 11-11 重做后跟着改的门禁(一次性补丁, CRLF 二进制读写)。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	for old, new in pairs:
		o = old.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		w = new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次:\n%s" % (rel, c, old[:160]))
		b = b.replace(o, w)
	open(p, "wb").write(b)
	print("改好", rel)


patch("tests/verify_minion_idle_align.gd", [
	('	["远程小将", "res://assets/sprites/pets/minion-back.png",\n'
	 '		"res://assets/sprites/pets/animations/ranged/run.png"],',
	 '	## 11-11 三种小将重做: 待机改成 192 方帧呼吸帧条(第 0 帧 = 站姿底图), 拿它比普攻第 0 帧(同一张底图);\n'
	 '	##   跑步第 0 帧本来就是跑的姿势, 不再等于站姿(原来比的是静态立绘 vs 跑步第 0 帧)\n'
	 '	["远程小将", "res://assets/sprites/pets/animations/ranged/idle.png",\n'
	 '		"res://assets/sprites/pets/animations/ranged/attack.png"],\n'
	 '	["精英小将", "res://assets/sprites/pets/animations/elite/idle.png",\n'
	 '		"res://assets/sprites/pets/animations/elite/attack.png"],'),
	('		var ii: Image = idle_t.get_image()\n',
	 '		var ii: Image = idle_t.get_image()\n'
	 '		if ii.get_width() > ii.get_height():   # 待机是横排帧条 ⇒ 取第 0 帧\n'
	 '			ii = ii.get_region(Rect2i(0, 0, ii.get_height(), ii.get_height()))\n'),
	('	_anchor_check("远程小将", seen, ["minion-back.png"])',
	 '	_anchor_check("远程小将", seen, ["animations/ranged/idle.png"])'),
])
patch("tests/verify_minion_pull_speed.gd", [
	('		f["maxHp"] = 50000.0; f["hp"] = 50000.0\n'
	 '		s._units.append(e); s._units.append(f)',
	 '		f["maxHp"] = 50000.0; f["hp"] = 50000.0\n'
	 '		f["move_spd"] = 0.0; f["no_move"] = true   # 11-11 铁锁加了 0.2 秒后甩前摇(晕在扎中那一刻), 前摇里目标会走动 ⇒ 量的是拉人速度, 目标定住\n'
	 '		s._units.append(e); s._units.append(f)'),
])
