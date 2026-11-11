# -*- coding: utf-8 -*-
"""远程小将(海螺炮手) / 精英小将(深渊精英) 2026-11-11 重做接线 —— 一次性补丁(CRLF 二进制读写; 主文件行数不变)。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def patch(rel, pairs, keep_lines=False):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	n0 = b.count(b"\n")
	for old, new in pairs:
		multi = old.startswith("@ALL@")
		old = old[5:] if multi else old
		o = old.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		w = new.replace("\n", "\r\n" if crlf else "\n").encode("utf-8")
		c = b.count(o)
		if c < 1 or (c > 1 and not multi):
			raise SystemExit("%s: 命中 %d 次:\n%s" % (rel, c, old[:160]))
		b = b.replace(o, w)
	if keep_lines and b.count(b"\n") != n0:
		raise SystemExit("%s: 行数 %d → %d(必须不变)" % (rel, n0, b.count(b"\n")))
	open(p, "wb").write(b)
	print("改好", rel, n0, "→", b.count(b"\n"), "行")


MAIN = "scripts/scenes/RealtimeBattle3DScene.gd"
patch(MAIN, [
	('	"__minion_elite__": ["pets/animations/elite/attack.png", 39.0],   # 13 帧 / 0.33s(原 4 帧 × 12)',
	 '	"__minion_elite__": ["pets/animations/elite/attack.png", 10.0],   # 11-11 深渊精英: 11 格 / 1.1s(命中格 4 ÷ 前摇 0.40s)'),
	('	"__minion_back__": ["pets/animations/ranged/attack.png", 28.8],   # 12 帧 / 0.42s(原 5 帧 × 12)',
	 '	"__minion_back__": ["pets/animations/ranged/attack.png", 11.76],   # 11-11 海螺炮手: 9 格 / 0.77s(命中格 3 ÷ 前摇 0.255s)'),
	('	"__minion_elite__": [47.0, 71.0, 71.0],',
	 '	"__minion_elite__": [117.0, 177.0, 117.0, 1.8],   # 11-11 深渊精英 192 方帧(本体 117 / 脚底 177 / 本体 1.8 米)'),
	('	"__minion_back__": [52.0, 76.0, 52.0],   # 实测: 动作第0帧 本体52/脚底76; idle(侧面) 本体52',
	 '	"__minion_back__": [100.0, 177.0, 100.0, 1.5],   # 11-11 海螺炮手 192 方帧(本体 100 / 脚底 177 / 本体 1.5 米)'),
	## 铁锁: 前摇 0.2 s 后甩再出链(用户 11-11「往回这个地上甩一下…紧接着手臂往前甩…链子慢慢的延伸到这个敌人」), 链 = 穿刺链
	('	var whip_links: Array = PullRopeVfx.elite_links(self, from5, to5, load("res://assets/sprites/vfx/bio-chain-h.png"),',
	 '	var whip_links: Array = _elite_sys.whip_chain(u, tgt,   # 穿刺链(11-11): 后甩前摇 WHIP_WINDUP_SEC 后从拳头射出'),
	('	_pending_shots.append({"delay": 0.14, "fn": func() -> void:   # 命中: 顿一下+目标眩晕0.4s',
	 '	_pending_shots.append({"delay": EliteSystem.WHIP_WINDUP_SEC + 0.14, "fn": func() -> void:   # 命中(链头扎中): 顿一下+目标眩晕0.4s'),
	('@ALL@			PullRopeVfx.release(self, whip_links)', '			_elite_sys.whip_chain_release(whip_links)'),
	('	_pending_shots.append({"delay": EliteSystem.WHIP_SHOT_DELAY, "fn": func() -> void:    # 拉体: 按速度飞到目标身后(11-08, 原固定 0.18s)',
	 '	_pending_shots.append({"delay": EliteSystem.WHIP_WINDUP_SEC + EliteSystem.WHIP_SHOT_DELAY, "fn": func() -> void:    # 拉体: 按速度飞到目标身后'),
	('			PullRopeVfx.reel(whip_links, pq * pull_len / chain_len)   # 已经被拽过的链节收掉(画面)',
	 '			_elite_sys.whip_chain_reel(whip_links, q, pull_len / maxf(1.0, chain_len))   # 链随人往前飞自己变短; 撞上前收回拳头'),
], keep_lines=True)
## '@ALL@' 前缀只是让同一行出现多次时全换(上面 patch 的计数允许 > 1)
p = os.path.join(ROOT, MAIN)
b = open(p, "rb").read()
assert b"PullRopeVfx" not in b[b.index(b"func _tick_elite_whip("):b.index(b"const SCREEN_FLASH_GROUP")], "铁锁里还有 PullRopeVfx"

patch("scripts/gamedata/attack_hits.gd", [
	('	"pets/animations/elite/attack.png": 6,      # 13 帧(11-08: 站姿起手 + AI 补拉镰 3 帧 / 收回 5 帧)',
	 '	"pets/animations/elite/attack.png": 4,      # 11 格(11-11 深渊精英: 站 / 举过头 ×2 / 斜前上 / ★劈到前下 / 收)'),
	('	"pets/animations/ranged/attack.png": 5,     # 12 帧(11-08: AI 补收回 4 帧)',
	 '	"pets/animations/ranged/attack.png": 3,     # 9 格(11-11 海螺炮手: 站 / 前压 ×2 / ★后坐 / 收)'),
])
patch("scripts/gamedata/minion_codex.gd", [
	('	"skill": ["pets/animations/ranged/skill.png", 4.6667],   # 7 帧 ÷ 4.6667fps = 1.5 秒 == 火箭蓄力节拍(门禁焊死)',
	 '	"skill": ["pets/animations/ranged/skill.png", 10.0],   # 11-11 海螺炮手: 15 格 ÷ 10fps = 1.5 秒 == 火箭蓄力节拍(门禁焊死)\n'
	 '	"fire": ["pets/animations/ranged/fire.png", 12.0],     # 11-11: 火箭射出那一刻的后坐(5 格 0.42 秒)'),
])
patch("scripts/gamedata/action_elite.gd", [
	('	"whirl":      ["pets/animations/elite/whirl.png", 9.52],      # 4帧 / 0.42s',
	 '	"whirl":      ["pets/animations/elite/whirl.png", 14.3],      # 11-11: 6格 / 0.42s(正面 → 背面 → 转回)'),
	('	"hammer":     ["pets/animations/elite/hammer.png", 9.30],     # 4帧 / 0.43s',
	 '	"hammer":     ["pets/animations/elite/hammer.png", 13.95],    # 11-11: 6格 / 0.43s(砸地在最后一格)'),
	('	"hammer_big": ["pets/animations/elite/hammer_big.png", 12.24],# 18帧 / 1.47s(含1s hold)',
	 '	"hammer_big": ["pets/animations/elite/hammer_big.png", 10.2], # 11-11: 15格 / 1.47s(蹲 / 起跳 / 空中举双拳 10 格 / 砸)'),
	('	"whip":       ["pets/animations/elite/whip.png", 14.0],       # 7帧 / 0.50s ≈ 节拍 0.48s',
	 '	"whip":       ["pets/animations/elite/whip.png", 14.0],       # 11-11: 11格, 运行时按「前摇 + 出手 + 拉人」时长传 fps(EliteSystem.whip_anim_fps)'),
	('	"consume":    ["pets/animations/elite/consume.png", 6.0],     # 9帧 / 1.50s',
	 '	"consume":    ["pets/animations/elite/consume.png", 10.0],    # 11-11: 15格 / 1.50s'),
])
patch("scripts/systems/skills/elite_system.gd", [
	('const WHIP_SHOT_DELAY := 0.3            # 链射出手到开始拉体(与 _tick_elite_whip 的 delay 0.3 同一个数)\n',
	 'const WHIP_SHOT_DELAY := 0.3            # 链射出手到开始拉体(与 _tick_elite_whip 的 delay 0.3 同一个数)\n'
	 '## 铁锁出手前摇(11-11 用户「你的手可以…往回这个地上甩一下，把这个链子带出来…紧接着手臂往前甩」): 后甩 + 后拉 0.2 秒后才出链。\n'
	 '##   改了对局结果(晕 / 拉人都晚 0.2 秒) ⇒ RULES_VER 本周已是 6, 规则指纹要刷。\n'
	 'const WHIP_WINDUP_SEC := 0.2\n'
	 'const WHIP_ANIM_SLOTS := 11.0           # whip.png 格数(tools/assetgen/build_minion_redo.py)\n'
	 '## 穿刺链(PierceChainVfx, 与近战同一套): 从拳头射出, 链头 = elite-chain-head(菱形紫刃), 扎穿目标胸口\n'
	 'const WHIP_CHAIN_FLY := 0.12\n'
	 'const WHIP_CHAIN_PX := 1.8 / 117.0     # 与人物图同一个像素大小(本体 117 像素 = 1.8 米)\n'
	 'const WHIP_PIERCE_OUT := 0.6\n'
	 'const WHIP_FIST_FWD := 54.0            # 甩出那张拳头在身体前方 85 像素 ≈ 1.3 米 ≈ 54 码\n'
	 'const WHIP_FIST_UP := 1.0              # 拳头离地(米)\n'
	 'const WHIP_CHEST_UP := 0.9\n'
	 'const WHIP_RETRACT_SEC := 0.1\n'),
	('static func whip_anim_fps(d: float) -> float:\n'
	 '	return 7.0 / (WHIP_SHOT_DELAY + maxf(WHIP_PULL_MIN, (d + 46.0) / WHIP_PULL_SPD))',
	 'static func whip_anim_fps(d: float) -> float:\n'
	 '	return WHIP_ANIM_SLOTS / (WHIP_WINDUP_SEC + WHIP_SHOT_DELAY + maxf(WHIP_PULL_MIN, (d + 46.0) / WHIP_PULL_SPD))\n'
	 '\n'
	 '\n'
	 '## 铁锁的穿刺链(画面): 前摇后从拳头射出。返回句柄 [状态]; 前摇里就作废(目标死了等)⇒ 不再射。sim 不读。\n'
	 'func whip_chain(u: Dictionary, tgt: Dictionary, life: float) -> Array:\n'
	 '	var st := {"cancel": false, "chain": null}\n'
	 '	var fist := func() -> Vector3:\n'
	 '		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)\n'
	 '		var dn: Vector2 = DetMath.norm(dv) if DetMath.vlen(dv) > 1.0 else Vector2.LEFT\n'
	 '		return battle._world_pos((u["pos"] as Vector2) + dn * WHIP_FIST_FWD, float(u.get("height", 0.0)) + WHIP_FIST_UP)\n'
	 '	var chest := func() -> Vector3:\n'
	 '		return battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + WHIP_CHEST_UP)\n'
	 '	battle._pending_shots.append({"delay": WHIP_WINDUP_SEC, "fn": func() -> void:\n'
	 '		if not st["cancel"]:\n'
	 '			st["chain"] = PierceChainVfx.fire(battle, "elite-chain", WHIP_CHAIN_PX, false, fist, chest, WHIP_CHAIN_FLY, WHIP_PIERCE_OUT, life)\n'
	 '	, "src": u})\n'
	 '	return [st]\n'
	 '\n'
	 '\n'
	 '## 拉人进度 q(0 ~ 1): 链随人往前飞自己变短(PierceChainVfx 每帧从两端推); 最后 WHIP_RETRACT_SEC 秒把链头拔出收回拳头\n'
	 'func whip_chain_reel(h: Array, q: float, _ratio: float) -> void:\n'
	 '	if h.is_empty() or not (h[0] is Dictionary) or h[0]["chain"] == null:\n'
	 '		return\n'
	 '	if q >= 0.88:\n'
	 '		(h[0]["chain"] as PierceChainVfx).retract(WHIP_RETRACT_SEC)\n'
	 '\n'
	 '\n'
	 'func whip_chain_release(h: Array) -> void:\n'
	 '	if h.is_empty() or not (h[0] is Dictionary):\n'
	 '		return\n'
	 '	h[0]["cancel"] = true\n'
	 '	if h[0]["chain"] != null:\n'
	 '		(h[0]["chain"] as PierceChainVfx).release()\n'
	 '	h.clear()'),
])
## 远程: 火箭射出播后坐 + 炮口高度换成海螺炮口(瞄准时炮口离地 0.77 米)
patch("scripts/systems/skills/hiding_system.gd", [
	('		battle._rocket_sys._rocket_muzzle_flash(uu, muzzle, aim2)          # 枪口特效动画(用户2026-07-18): 白热闪+锥形喷火+火星前喷+后坐',
	 '		battle._rocket_sys._rocket_muzzle_flash(uu, muzzle, aim2)          # 枪口特效动画(用户2026-07-18): 白热闪+锥形喷火+火星前喷+后坐\n'
	 '		battle._melee_anim(uu, "fire")                                    # 11-11 海螺炮手: 火箭射出那一刻后坐'),
	('	var mh: float = 0.95\n', '	var mh: float = ROCKET_MUZZLE_H\n'),
	('const ROCKET_CHARGE_SEC := 1.5', '## 火箭炮口离地(米): 11-11 海螺炮手瞄准时炮口在脚底上 51 像素(本体 100 像素 = 1.5 米) ≈ 0.77 米; 原来 0.95 是旧红色炮手的肩炮\n'
	 'const ROCKET_MUZZLE_H := 0.77\n'
	 '## 远程小将普攻弹体从炮口出(11-11): 站姿炮口在腰带扣前 50 像素 ≈ 0.75 米 ≈ 31 码、脚底上 74 像素 ≈ 1.1 米\n'
	 'const RANGED_MUZZLE_FWD := 31.0\n'
	 'const RANGED_MUZZLE_UP := 1.1\n'
	 'const ROCKET_CHARGE_SEC := 1.5'),
	## 待机帧表: 远程 / 精英也换成帧条(呼吸 4 格)
	('	if not is_elite and not is_back and ResourceLoader.exists(battle.SPRITE_DIR + MELEE_IDLE_SHEET):\n'
	 '		var it: Texture2D = load(battle.SPRITE_DIR + MELEE_IDLE_SHEET)\n',
	 '	var idle_sheet: String = "pets/animations/elite/idle.png" if is_elite else ("pets/animations/ranged/idle.png" if is_back else MELEE_IDLE_SHEET)   # 11-11 三种小将都重做\n'
	 '	if ResourceLoader.exists(battle.SPRITE_DIR + idle_sheet):\n'
	 '		var it: Texture2D = load(battle.SPRITE_DIR + idle_sheet)\n'),
])
patch("scripts/systems/skills/rocket_system.gd", [
	('@ALL@battle._world_pos(muzzle, 0.95)', 'battle._world_pos(muzzle, HidingSystem.ROCKET_MUZZLE_H)'),
	('@ALL@battle._world_pos(from2, 0.95)', 'battle._world_pos(from2, HidingSystem.ROCKET_MUZZLE_H)'),
	('battle._world_pos(from2.lerp(muzzle, t), 0.95)', 'battle._world_pos(from2.lerp(muzzle, t), HidingSystem.ROCKET_MUZZLE_H)'),
	('battle._world_pos(muzzle.lerp(dest, t), 0.95 + 0.25 * DetMath.dsin(t * PI))', 'battle._world_pos(muzzle.lerp(dest, t), HidingSystem.ROCKET_MUZZLE_H + 0.25 * DetMath.dsin(t * PI))'),
])
patch("scripts/scenes/battle/battle_ballistics.gd", [
	('	var world_from = battle._world_pos(start2d, 1.0)   # 从胸口高度出\n',
	 '	var world_from = battle._world_pos(start2d, 1.0)   # 从胸口高度出\n'
	 '	if from == null and src is Dictionary and str(src.get("minion_role", "")) == "back" and not bool(src.get("is_elite", false)):   # 11-11 海螺炮手: 从炮口出\n'
	 '		var _md: Vector2 = DetMath.norm((tgt["pos"] as Vector2) - (src["pos"] as Vector2)) if DetMath.vlen((tgt["pos"] as Vector2) - (src["pos"] as Vector2)) > 1.0 else Vector2.LEFT\n'
	 '		world_from = battle._world_pos((src["pos"] as Vector2) + _md * HidingSystem.RANGED_MUZZLE_FWD, HidingSystem.RANGED_MUZZLE_UP)\n'),
])
