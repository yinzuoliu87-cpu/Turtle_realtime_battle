# -*- coding: utf-8 -*-
"""精英铁锁后甩「带出一节链子」(用户 11-11「你的手可以…往回这个地上甩一下，把这个链子带出来，就带出一节这种链子，
然后紧接着手臂往前甩之后呢，这个链子就是有一个…动画形状，然后链子慢慢的延伸到这个敌人这里」)。
PierceChainVfx 加「出手前」阶段: pre_sec 秒内链头拖在 pre_tip(身后地面), 链子一头连 pre_hand(身后的拳头); 之后照常从手腕飞向目标。
精英 whip_chain 改成前摇一开始就出链(带 pre 阶段)。CRLF 二进制读写。"""
import os

ROOT = r"C:\Users\Louis\Documents\GitHub\turtle-realtime-godot"


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	for old, new in pairs:
		o = old.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		w = new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		c = b.count(o)
		if c != 1:
			raise SystemExit("%s: 命中 %d 次:\n%s" % (rel, c, old[:120]))
		b = b.replace(o, w)
	open(p, "wb").write(b)
	print("改好", rel)


patch("scripts/scenes/battle/pierce_chain_vfx.gd", [
	('var _ret_sec := 0.1\n',
	 'var _ret_sec := 0.1\n'
	 '## 出手前阶段(精英铁锁后甩, 11-11): _pre 秒内链头拖在 _pre_tip(身后地面), 链子一头连 _pre_hand; 之后照常飞\n'
	 'var _pre := 0.0\n'
	 'var _pre_hand: Callable\n'
	 'var _pre_tip: Callable\n'),
	('static func fire(b, kind: String, px_m: float, head_left: bool, from_fn: Callable, to_fn: Callable, fly_sec: float, pierce_out: float, life_sec: float) -> PierceChainVfx:\n'
	 '	var c := PierceChainVfx.new()\n',
	 'static func fire(b, kind: String, px_m: float, head_left: bool, from_fn: Callable, to_fn: Callable, fly_sec: float, pierce_out: float, life_sec: float,\n'
	 '		pre_sec: float = 0.0, pre_hand: Callable = Callable(), pre_tip: Callable = Callable()) -> PierceChainVfx:\n'
	 '	var c := PierceChainVfx.new()\n'
	 '	c._pre = pre_sec if pre_hand.is_valid() and pre_tip.is_valid() else 0.0\n'
	 '	c._pre_hand = pre_hand\n'
	 '	c._pre_tip = pre_tip\n'),
	('func _tick(t: float) -> void:\n'
	 '	_t = t\n'
	 '	if _done or not is_instance_valid(_head):\n'
	 '		return\n',
	 'func _tick(t: float) -> void:\n'
	 '	_t = t - _pre                 # 出手时刻起算(retract 记的也是这个口径)\n'
	 '	if _done or not is_instance_valid(_head):\n'
	 '		return\n'
	 '	if _t < 0.0:                  # 出手前: 链头拖在身后地面, 一头连身后的拳头, 不波动\n'
	 '		var q: float = clampf(t / maxf(0.001, _pre), 0.0, 1.0)\n'
	 '		var ph: Vector3 = _pre_hand.call(q)\n'
	 '		var pt: Vector3 = _pre_tip.call(q)\n'
	 '		_lay(ph, pt, 0.0, t, (pt - ph).normalized())\n'
	 '		return\n'
	 '	t = _t\n'),
])
## 把「从手到链头摆一串」抽成 _lay(a, tip, wave, t), 出手前阶段与飞行 / 钉住阶段共用
p = os.path.join(ROOT, "scripts/scenes/battle/pierce_chain_vfx.gd")
b = open(p, "rb").read()
crlf = b"\r\n" in b
s = b.decode("utf-8").replace("\r\n", "\n")
i = s.index("	var head_len: float = float(_head.texture.get_width()) * _px\n")
j = s.index("## 精灵沿屏幕上 p0 → p1 的方向摆")
body = s[i:j]
old_wave = "	var wave: float = WAVE_AMP * (1.0 - fly) * (1.0 - fly)          # 越接近目标越小, 到达那刻 0 = 绷直\n"
old_dir = "		hd = dir\n"
assert body.count(old_wave) == 1 and body.count(old_dir) == 1, "抽 _lay: 找不到 wave / dir 行"
body = body.replace(old_wave, "").replace(old_dir, "		hd = dir\n")
s = s[:i] + "	_lay(a, tip, WAVE_AMP * (1.0 - fly) * (1.0 - fly), t, dir)   # 越接近目标波越小, 到达那刻 0 = 绷直\n\n\n" \
	"## 从手 a 到链头尖 tip 摆一串链节 + 链头(wave = 横向波浪振幅, 米; dir = 手与链头重合时的朝向)\n" \
	"func _lay(a: Vector3, tip: Vector3, wave: float, t: float, dir: Vector3) -> void:\n" \
	+ body + s[j:]
if crlf:
	s = s.replace("\n", "\r\n")
open(p, "wb").write(s.encode("utf-8"))
print("抽出 _lay")

patch("scripts/systems/skills/elite_system.gd", [
	('	battle._pending_shots.append({"delay": WHIP_WINDUP_SEC, "fn": func() -> void:\n'
	 '		if not st["cancel"]:\n'
	 '			st["chain"] = PierceChainVfx.fire(battle, "elite-chain", WHIP_CHAIN_PX, false, fist, chest, WHIP_CHAIN_FLY, WHIP_PIERCE_OUT, life)\n'
	 '	, "src": u})\n',
	 '	## 后甩(前摇 WHIP_WINDUP_SEC 秒): 链头拖在身后地面, 一头连身后的拳头 —— 用户「往回这个地上甩一下，把这个链子带出来」\n'
	 '	## 拳头按 whip.png 前两张走: 第 1 张(往地上甩)→ 第 2 张(后拉蓄力), q = 前摇进度 0 ~ 1\n'
	 '	var back_hand := func(q: float) -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		var back: float = lerpf(WHIP_BACK_HAND_0, WHIP_BACK_HAND_1, q)\n'
	 '		var up: float = lerpf(WHIP_BACK_UP_0, WHIP_BACK_UP_1, q)\n'
	 '		return battle._world_pos((u["pos"] as Vector2) - dn * back, float(u.get("height", 0.0)) + up)\n'
	 '	var back_tip := func(_q: float) -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return battle._world_pos((u["pos"] as Vector2) - dn * WHIP_BACK_TIP, 0.06)\n'
	 '	st["chain"] = PierceChainVfx.fire(battle, "elite-chain", WHIP_CHAIN_PX, false, fist, chest, WHIP_CHAIN_FLY, WHIP_PIERCE_OUT, life + WHIP_WINDUP_SEC,\n'
	 '		WHIP_WINDUP_SEC, back_hand, back_tip)\n'),
	('const WHIP_RETRACT_SEC := 0.1\n',
	 'const WHIP_RETRACT_SEC := 0.1\n'
	 '## 后甩时拳头在身后多少码 / 离地多少米(whip.png 第 1 张: 腰带扣后 30 像素、离地 31 像素; 第 2 张: 55 / 56 像素; 1 像素 = 1.8 / 117 米, 1 码 = 0.024 米)\n'
	 'const WHIP_BACK_HAND_0 := 19.0\n'
	 'const WHIP_BACK_HAND_1 := 35.0\n'
	 'const WHIP_BACK_UP_0 := 0.48\n'
	 'const WHIP_BACK_UP_1 := 0.86\n'
	 'const WHIP_BACK_TIP := 66.0            # 链头拖在身后地面多远(码): 拳头到链头约 1.1 米一节链\n'),
	('## 铁锁的穿刺链(画面): 前摇后从拳头射出。返回句柄 [状态]; 前摇里就作废(目标死了等)⇒ 不再射。sim 不读。\n',
	 '## 铁锁的穿刺链(画面): 前摇里链头拖在身后地面(后甩带出一节), 前摇完从拳头射出。返回句柄 [状态]; 作废 ⇒ whip_chain_release 立刻放掉。sim 不读。\n'),
])
## 作废(前摇里目标死了等): 原来靠 cancel 拦住还没射的; 现在一开始就有链 ⇒ release 直接放掉
print("ok")
