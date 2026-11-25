class_name MagicEqVfx
extends BombEqVfx
## magic_eq_vfx.gd —— 魔法书羁绊【飞弹】+ 魔法书 10 件 + 三种骷髅 的演出层(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md)
##
## ★只画不判定: 结算全在 EqMagicBatch / MagicbookSynergySystem; 无头 / 没有世界节点时什么都不做(继承的 _ok())。
## ★生命周期 = 继承炸弹演出层的 `tick` / `_anim` / `_later`(不用 tween, CLAUDE.md §4.5); 本文件只换特效表(覆盖 `_row`),
##   另加两种自己的: 飞行物(位置由结算侧每步回调摆, 演出不按固定秒数补间) / 126 书页(每帧按批系统里的角度 / 张数摆)。
## 素材(如实): assets/sprites/vfx/magic-*.png = PixelLab 特效工作台预设改配色 / 改参数导出; magic-page.png = PixelLab 生成的单张书页;
##   eq-skel*-*.png = PixelLab 生成的骷髅龟动作帧。全部由 tools/assetgen/pack_magic_art.py 打包(确定性)。
##   逐帧研究: docs/studies/20261125-魔法书羁绊特效逐帧.md。

## 特效表: 名 → [路径, 帧宽, 帧高, 内容直径(像素), 锚点 x, 锚点 y](pack_magic_art.py 打印, 照抄)
const MSHEETS := {
	"missile-orb": ["vfx/magic-missile-orb.png", 48, 48, 37.0, 24, 24],   # 8 帧 · 循环 ·【飞弹】弹头: 蓝色奥术球
	"missile-hit": ["vfx/magic-missile-hit.png", 64, 64, 44.0, 32, 32],   # 5 帧 ·【飞弹】命中: 蓝白闪 + 射线 + 环
	"note-bolt": ["vfx/magic-note-bolt.png", 32, 32, 24.0, 16, 16],   # 8 帧 · 循环 · 117 学徒笔记飞弹: 小而淡的青白球(与羁绊飞弹区分)
	"note-hit": ["vfx/magic-note-hit.png", 43, 42, 37.0, 18, 23],   # 5 帧 · 117 命中: 青白小十字环
	"fireball": ["vfx/magic-fireball.png", 48, 48, 39.0, 24, 24],   # 8 帧 · 循环 · 119 烈焰法典火球
	"fireball-hit": ["vfx/magic-fireball-hit.png", 58, 81, 67.0, 29, 29],   # 10 帧 · 119 火球爆开
	"frost-nova": ["vfx/magic-frost-nova.png", 115, 47, 109.0, 55, 23],   # 7 帧 · 120 冰霜新星: 贴地冰环 + 雪花甩出
	"storm-bolt": ["vfx/magic-storm-bolt.png", 96, 128, 127.0, 48, 110, 2],   # 8 帧 · 121 风暴之书: 天降黄色闪电(第 7 列 = 从第 2 帧开播: 闪电已快到地面, 落地格对上伤害那一刻)
	"holy-regen": ["vfx/magic-holy-regen.png", 80, 112, 60.0, 40, 92],   # 12 帧 · 循环 · 122 治愈圣典持续回复: 脚下绿环 + 上飘的加号
	"scroll-shield": ["vfx/magic-scroll-shield.png", 96, 96, 81.0, 48, 48],   # 8 帧 · 循环 · 118 羊皮咒卷护盾: 金色符文环
	"skel-rise": ["vfx/magic-skel-rise.png", 64, 63, 58.0, 32, 18],   # 9 帧 · 123 骷髅破土: 绿环 + 骨灰 + 骨头蹦出
	"skel-crumble": ["vfx/magic-skel-crumble.png", 54, 91, 71.0, 26, 27],   # 8 帧 · 123 骷髅时间到化灰: 灰烟 + 骨头往下掉
	"skel-blast": ["vfx/magic-skel-blast.png", 128, 128, 105.0, 64, 64],   # 10 帧 · 123 骷髅法师骨火爆裂: 紫色爆炸
	"skel-wave": ["vfx/magic-skel-wave.png", 60, 76, 70.0, 30, 46],   # 8 帧 · 循环 · 123 骷髅祭司亡灵浪潮: 青色鬼火团 + 骷髅头
	"wave-hit": ["vfx/magic-wave-hit.png", 51, 47, 45.0, 23, 24],   # 5 帧 · 浪潮打到敌人: 青色爆闪 + 骷髅头飞散
	"wave-heal": ["vfx/magic-wave-heal.png", 46, 51, 31.0, 23, 28],   # 5 帧 · 浪潮经过友军: 青绿光球 + 加号
	"mirror-echo": ["vfx/magic-mirror-echo.png", 70, 70, 64.0, 35, 35],   # 12 帧 · 循环 · 124 镜像魔典再放一次: 紫色法阵
	"forbidden-bolt": ["vfx/magic-forbidden-bolt.png", 50, 50, 42.0, 25, 25],   # 8 帧 · 循环 · 125 禁咒弹: 品红大球 + 环绕符文
	"forbidden-blast": ["vfx/magic-forbidden-blast.png", 78, 94, 80.0, 39, 39],   # 10 帧 · 125 禁咒弹命中: 品红爆炸 + 符文碎片
	"forbidden-ready": ["vfx/magic-forbidden-ready.png", 37, 37, 28.0, 18, 18],   # 8 帧 · 循环 · 125 下一次攻击已装填: 头顶三枚品红符文
	"page-cut": ["vfx/magic-page-cut.png", 47, 42, 41.0, 22, 26],   # 6 帧 · 126 近战书页划过敌人: 青色纸刃弧
	"page-block": ["vfx/magic-page-block.png", 51, 46, 45.0, 23, 23],   # 5 帧 · 126 远程书页格挡: 纸白闪 + 碎纸片
	"tome-hp": ["vfx/magic-tome-hp.png", 46, 51, 45.0, 23, 28],   # 5 帧 · 126 释放技能后临时最大生命: 金闪 + 上飘加号
	## 下面两张给骷髅远程普攻的弹道用(battle_ballistics._fire_bolt_from 直接 load, 取第 0 帧), 这里登记尺寸备查
	"skelm-bolt": ["vfx/magic-skelm-bolt.png", 40, 40, 30.0, 20, 20],   # 8 帧 · 循环 · 骷髅法师暗影弹: 紫球 + 小骷髅头
	"skelp-bolt": ["vfx/magic-skelp-bolt.png", 33, 33, 26.0, 16, 16],   # 8 帧 · 循环 · 骷髅祭司鬼火光: 青球 + 白点
}
const PAGE_TEX := "vfx/magic-page.png"
const PAGE_PX := 26.0           ## 书页显示大小(世界码)
const PAGE_ORBIT_H := 1.05      ## 近战书页环绕高度(米)

var _flies: Array = []          ## 飞行物节点(换路清)
var _pages: Array = []          ## 126 书页 {u, ck, melee, nodes:[]}
var _marks: Array = []          ## 125 装填标记 {u, node}


func _row(key: String) -> Array:   # zero-caller-ok: 覆盖父类 BombEqVfx._row —— 父类的 _anim / _load 经它查表, 调用方在父类
	return MSHEETS.get(key, [])


# ═══════════════════════════════ 飞行物(结算侧每步摆位置) ═══════════════════════════════

func _fly_node(key: String, u: Dictionary, world_d: float) -> Sprite3D:
	var s := _anim(key, Vector2(u["pos"]), world_d, 60.0, 0.02, false, true)
	if s == null:
		return null
	s.no_depth_test = true
	s.render_priority = 11
	s.set_meta("h", body_h(u))
	s.position = battle._world_pos(Vector2(u["pos"]), float(s.get_meta("h")))
	_flies.append(s)
	return s


func _fly_to(node, p2: Vector2) -> void:
	if node is Sprite3D and is_instance_valid(node):
		(node as Sprite3D).position = battle._world_pos(p2, float((node as Sprite3D).get_meta("h", 1.0)))


func _fly_end(node) -> void:
	if node is Sprite3D and is_instance_valid(node):
		(node as Sprite3D).queue_free()


func mb_launch(u: Dictionary, _tgt: Dictionary, _i: int, _n: int):
	return _fly_node("missile-orb", u, 36.0)


func mb_step(node, _from2: Vector2, p2: Vector2, _to2: Vector2, _k: float, _i: int) -> void:
	_fly_to(node, p2)


func mb_land(node, tgt: Dictionary, hit: bool) -> void:
	_fly_end(node)
	if hit:
		_anim("missile-hit", Vector2(tgt["pos"]), 56.0, 0.35, 0.02, false, false, Color.WHITE, tgt)


func note_launch(u: Dictionary, _tgt: Dictionary):
	return _fly_node("note-bolt", u, 28.0)


func note_land(node, tgt: Dictionary, hit: bool) -> void:
	_fly_end(node)
	if hit:
		_anim("note-hit", Vector2(tgt["pos"]), 50.0, 0.32, 0.02, false, false, Color.WHITE, tgt)


func fire_launch(u: Dictionary, _tgt: Dictionary):
	return _fly_node("fireball", u, 54.0)


func fire_land(node, tgt: Dictionary) -> void:
	_fly_end(node)
	_anim("fireball-hit", Vector2(tgt["pos"]), 110.0, 0.7, 0.02, false, false, Color.WHITE, tgt)


func forb_launch(u: Dictionary, _tgt: Dictionary):
	return _fly_node("forbidden-bolt", u, 46.0)


func forb_land(node, tgt: Dictionary) -> void:
	_fly_end(node)
	_anim("forbidden-blast", Vector2(tgt["pos"]), 200.0, 0.75, 0.02, false, false, Color.WHITE, tgt)


func bolt_step(node, _from2: Vector2, p2: Vector2, _to2: Vector2, _k: float) -> void:
	_fly_to(node, p2)


## 125 下一次攻击已装填: 头顶三枚品红符文(射出那一下就收)
func forb_ready(u: Dictionary, on: bool) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		if is_same(_marks[i]["u"], u):
			if is_instance_valid(_marks[i]["node"]):
				(_marks[i]["node"] as Node3D).queue_free()
			_marks.remove_at(i)
	if not on or not _ok():
		return
	var s := _follow("forbidden-ready", u, 86.0, 600.0, body_h(u))   # 三枚符文绕身体中段转(放头顶会被血条挡、太挤; 11-25 录像自查)
	if s != null:
		_marks.append({"u": u, "node": s})


# ═══════════════════════════════ 释放技能时 ═══════════════════════════════

func scroll_shield(u: Dictionary) -> void:
	_follow("scroll-shield", u, 80.0, 4.0, body_h(u))


func frost_nova(c: Vector2, r: float) -> void:
	_anim("frost-nova", c, r * 2.0, 0.5, 0.05, false, false, Color.WHITE, "ground")


func storm_bolt(o: Dictionary) -> void:
	var s := _anim("storm-bolt", Vector2(o["pos"]), 300.0, 0.5, 0.05, false, false)   # 300 码高: 从画面上方劈下来
	if s != null:
		## 锚点在闪电落地点(贴图第 110 行): 落点放在敌人脚下
		s.position = battle._world_pos(Vector2(o["pos"]), 0.05)
		s.no_depth_test = true
		s.render_priority = 10


func holy_mark(o: Dictionary, sec: float) -> void:
	_follow("holy-regen", o, 110.0, sec, 0.05)


func tome_hp(u: Dictionary, _sec: float) -> void:
	_anim("tome-hp", Vector2(u["pos"]), 60.0, 0.45, 0.02, false, false, Color.WHITE, u)


func mirror_echo(u: Dictionary, delay: float) -> void:
	_follow("mirror-echo", u, 90.0, delay + 0.35, body_h(u))


## 跟着单位走的循环特效(护盾环 / 持续回复 / 再放法阵 / 装填标记)
func _follow(key: String, u: Dictionary, world_d: float, life: float, h: float) -> Sprite3D:
	var s := _anim(key, Vector2(u["pos"]), world_d, life, h, false, true)
	if s == null:
		return null
	s.position = battle._world_pos(Vector2(u["pos"]), h)
	s.no_depth_test = true
	s.render_priority = 10
	for f in _fx:
		if f.get("node") == s:
			f["kind"] = "anim_follow"
			f["tgt"] = u
	return s


# ═══════════════════════════════ 123 骷髅 ═══════════════════════════════

func skel_rise(p: Dictionary, _kind: String) -> void:
	_anim("skel-rise", Vector2(p["pos"]), 90.0, 0.7, 0.05, false, false, Color.WHITE, "ground")


func skel_crumble(p: Dictionary) -> void:
	_anim("skel-crumble", Vector2(p["pos"]), 80.0, 0.65, 0.02, false, false, Color.WHITE, p)


func skm_blast(_p: Dictionary, c: Vector2, r: float) -> void:
	_anim("skel-blast", c, r * 1.5, 0.55, 0.05, false, false, Color.WHITE, "ground")   # 内容直径按 1.5 × 半径: 火团最大时盖住范围内的人, 后半段烟团不至于糊满屏(11-25 录像自查)


func wave_launch(p: Dictionary, _dir: Vector2):
	var s := _anim("skel-wave", Vector2(p["pos"]), 90.0, 60.0, 0.05, false, true)
	if s == null:
		return null
	s.no_depth_test = true
	s.render_priority = 10
	s.set_meta("h", 0.05 + 70.0 * 0.5 * s.pixel_size)
	s.position = battle._world_pos(Vector2(p["pos"]), float(s.get_meta("h")))
	_flies.append(s)
	return s


func wave_step(node, b: Vector2, _dir) -> void:
	_fly_to(node, b)


func wave_end(node) -> void:
	_fly_end(node)


func wave_hit(o: Dictionary) -> void:
	_anim("wave-hit", Vector2(o["pos"]), 56.0, 0.35, 0.02, false, false, Color.WHITE, o)


func wave_heal(o: Dictionary) -> void:
	_anim("wave-heal", Vector2(o["pos"]), 44.0, 0.35, 0.02, false, false, Color.WHITE, o)


# ═══════════════════════════════ 126 浮空魔典 · 书页 ═══════════════════════════════

func pages_spawn(u: Dictionary, ck: String, n: int, melee: bool) -> void:
	if not _ok():
		return
	var t: Texture2D = _load(PAGE_TEX)
	if t == null:
		return
	var nodes: Array = []
	for i in range(n):
		var s := Sprite3D.new()
		s.texture = t
		s.shaded = false
		s.transparent = true
		s.no_depth_test = true
		s.render_priority = 9
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.pixel_size = (PAGE_PX * float(battle.WS)) / float(maxi(t.get_width(), t.get_height()))
		s.position = battle._world_pos(Vector2(u["pos"]), PAGE_ORBIT_H)
		battle._world.add_child(s)
		nodes.append(s)
	_pages.append({"u": u, "ck": ck, "melee": melee, "nodes": nodes})


func _page_acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_magic_acc", {})
	return float(d.get(key, 0.0))


func _tick_pages() -> void:
	for i in range(_pages.size() - 1, -1, -1):
		var g: Dictionary = _pages[i]
		var u: Dictionary = g["u"]
		var nodes: Array = g["nodes"]
		if not u.get("alive", false):
			for s in nodes:
				if is_instance_valid(s):
					(s as Node3D).queue_free()
			_pages.remove_at(i)
			continue
		var n: int = nodes.size()
		var c := Vector2(u["pos"])
		var t := float(battle._t)
		if bool(g["melee"]):
			## 近战: 按批系统里的角度绕身转(结算判定用同一个角度)
			var ang: float = _page_acc(u, "pang:" + str(g["ck"]))
			for j in range(n):
				var th: float = ang + TAU * float(j) / float(n)
				var p := c + Vector2(cos(th), sin(th)) * EqMagicBatch.PAGE_R
				(nodes[j] as Sprite3D).position = battle._world_pos(p, PAGE_ORBIT_H + 0.12 * sin(th * 2.0))
		else:
			## 远程: 身后扇形悬着现有的张数(用掉一张少一张, 长回来再出现)
			var have: int = int(_page_acc(u, "pages:" + str(g["ck"])))
			var back: float = -1.0 if bool(u.get("face_right", str(u.get("side", "left")) == "left")) else 1.0
			for j in range(n):
				var s: Sprite3D = nodes[j]
				s.visible = j < have
				var fan: float = (float(j) - float(n - 1) * 0.5) * 0.32
				var p := c + Vector2(back * (34.0 + 6.0 * absf(fan)), 0.0)
				s.position = battle._world_pos(p, 1.35 + fan * 0.9 + 0.05 * sin(t * 2.0 + float(j)))


func page_cut(o: Dictionary) -> void:
	_anim("page-cut", Vector2(o["pos"]), 46.0, 0.3, 0.02, false, false, Color.WHITE, o)


func page_block(u: Dictionary, _ck: String, absorbed: float = 0.0) -> void:
	_anim("page-block", Vector2(u["pos"]), 60.0, 0.32, 0.02, false, false, Color.WHITE, u)
	## 伤害飘字照常显示格挡前的数(同护盾口径) ⇒ 另跳一个「格挡 N」, 看得出书页吃掉了多少(11-25 录像自查)
	if absorbed >= 1.0 and battle.get("_vfx") != null:
		battle._vfx._float_text(Vector2(u["pos"]) + Vector2(0, -70), "格挡 %d" % int(round(absorbed)), Color("#f2e6c0"))


func page_regen(_u: Dictionary, _ck: String, _n: int) -> void:
	pass   # 张数一变, _tick_pages 下一帧就把那张显示出来


# ═══════════════════════════════ 123 亡者之书 · 骷髅技能动作 ═══════════════════════════════

## 技能动作帧条(112 方帧, 与待机同贴地线); 出招帧 = SKEL_SKILL_HIT(从 0 数), 帧率 = 出招帧 / 前摇秒数 ⇒ 出招帧落在结算那一刻
const SKEL_SKILL := {
	"skel_warrior": "res://assets/sprites/vfx/eq-skelw-skill.png",
	"skel_mage": "res://assets/sprites/vfx/eq-skelm-skill.png",
	"skel_priest": "res://assets/sprites/vfx/eq-skelp-skill.png",
}
const SKEL_SKILL_HIT := {"skel_warrior": 2, "skel_mage": 3, "skel_priest": 3}   # 抄自 pack_magic_art.py SKEL_HIT(怒吼 / 火团最大 / 双手前推)
static var _ssd := {}


func _skel_sd(kind: String, fps: float) -> Dictionary:
	if not _ssd.has(kind):
		var path: String = SKEL_SKILL.get(kind, "")
		var sd := {}
		if path != "" and ResourceLoader.exists(path):
			var tx: Texture2D = load(path)
			sd = battle._sprite_dict_from(tx, {"frames": tx.get_width() / 112, "frameW": 112, "frameH": 112, "duration": 800}, false)
		_ssd[kind] = sd
	var out: Dictionary = (_ssd[kind] as Dictionary).duplicate()
	if not out.is_empty():
		out["fps"] = fps
	return out


func skel_cast(p: Dictionary, kind: String, windup: float) -> void:
	if not _ok() or not p.get("alive", false):
		return
	var sd := _skel_sd(kind, float(SKEL_SKILL_HIT.get(kind, 4)) / maxf(0.05, windup))
	if not sd.is_empty():
		battle._set_anim_sheet(p, sd, "skel_" + kind, true)


# ═══════════════════════════════ 生命周期 ═══════════════════════════════

func tick(delta: float) -> void:
	super.tick(delta)
	_tick_pages()


func clear() -> void:
	super.clear()
	for s in _flies:
		if is_instance_valid(s):
			(s as Node3D).queue_free()
	_flies.clear()
	for g in _pages:
		for s in g["nodes"]:
			if is_instance_valid(s):
				(s as Node3D).queue_free()
	_pages.clear()
	_marks.clear()
