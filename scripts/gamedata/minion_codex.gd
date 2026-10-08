class_name MinionCodex
extends RefCounted
## 深海小将的【单一文案源】(2026-08-20 建)。
##
## ★为什么要单独抽出来: 之前同一批小将技能说明**存在两份互相独立的手抄** ——
##   图鉴一份(CodexScene.MINION_INFO)、战斗信息面板一份(RealtimeBattle3DScene.MINION_SKILL_DESC),
##   而且**已经漂了**: 图鉴的铁锤写着"0.35 秒蓄力 / 60° 锥形 / 4×攻击力", 战斗那份连伤害数字都没有;
##   反过来战斗那份写了"100/120 龟能", 图鉴又没有。两边各缺各的, 玩家在两个地方读到两套说法。
##   (memory: 手抄的副本必然落后)
## ⇒ 现在只有这一份, 图鉴与战斗都从这里取。
##
## ⚠ 这里的**数值仍然是从战斗代码抄来的**(`_make_unit` 的 is_minion 分支 + `_sk_minion_*` / `_elite_*`),
##   由 `tests/verify_minion_text_single_source.gd` 焊住"只有一份", 但"数字对不对"要靠改代码时同步。
##   注意 `scripts/gamedata/phase2_minion.gd` 是回合制遗留壳(名字"深海小将精英"、数值也不同), **不是事实源**。


## 战斗侧技能 type → 本表的 kind。战斗用 `minionBodysurf` 这类 type 名, 图鉴用 `front/back/elite`。
const TYPE_TO_KIND := {
	"minionBodysurf": "front",
	"minionRocket": "back",
	"eliteHammer": "elite",
}


## 战斗信息面板要的 {name, desc} —— 从同一张表现算, 不再另存一份。
static func skill_desc(stype: String) -> Variant:
	var k: String = str(TYPE_TO_KIND.get(stype, ""))
	if k == "" or not MINION_INFO.has(k):
		return null
	var d: Dictionary = MINION_INFO[k]
	## ★icon(2026-10-06): 信息面板技能格要图标 —— 原来小将两个技能没有图, 那一格是空的。
	return {"name": str(d.get("skill_name", "")), "desc": str(d.get("skill_desc", "")),
		"icon": str(d.get("skill_icon", ""))}


# 深海小将 (虚拟图鉴条目 — 非龟, pets.json 里没有)
#
# 【事实源】RealtimeBattle3DScene.gd `_make_unit` 的 is_minion 分支 + `_sk_minion_*` / `_elite_*`.
# 这里的每个数字都是从那段代码抄的, 改小将数值时【必须同步这张表】, 否则图鉴就开始骗人。
# 注意 scripts/gamedata/phase2_minion.gd 是回合制遗留壳(名字叫"深海小将精英", 数值也不同), 不是事实源。
# ══════════════════════════════════════════════════════════
const MINION_KINDS := [
	{"kind": "front", "name": "近战小将", "img": "minion.png"},
	{"kind": "back",  "name": "远程小将", "img": "minion-back.png"},
	{"kind": "elite", "name": "精英小将", "img": "minion-elite.png"},
]

## Lv1 数值 + 说明. hp/atk 随等级 ×1.05^(lv-1) 复利, 双抗定值(与 _make_unit 一致).
## ★`range` 写的是【实际生效】的射程: 近战单位在 `_make_unit` 里被抬到 ≥ MELEE_ATK_RANGE_MIN(100),
##   原表照抄 `st` 里的 70 / 90 ⇒ 图鉴比战斗少报(2026-10-07 体检 H)。
##   守卫: tests/verify_codex_battle_parity.gd 拿真生成的小将逐项比(血/攻/双抗/攻击间隔/射程)。
const MINION_INFO := {
	"front": {
		"name": "近战小将", "img": "minion.png", "role": "前排 · 近战",
		"hp": 750, "atk": 42, "def": 13, "mr": 13, "interval": 0.85, "range": 100, "spd": 105,
		"skill_name": "人体浪板", "skill_cost": 120, "skill_icon": "skills/minion-bodysurf.png",
		"skill_desc": "锁定 2000 码内的一个敌人并跃起，起跳时回复 2×攻击力 的生命值，距离过近时先向后跳开。随后射出铁链眩晕该敌人并将自身拉向目标，接触时造成 [color=#ff9f43]目标 10% 最大生命[/color] 的物理伤害。之后踩着目标滑行，对其持续造成 2×攻击力 的物理伤害，并对沿途敌人造成 1.5×攻击力 的物理伤害并将其击退，最后跳下。",
	},
	"back": {
		"name": "远程小将", "img": "minion-back.png", "role": "后排 · 远程",
		"hp": 750, "atk": 45, "def": 7, "mr": 7, "interval": 0.85, "range": 400, "spd": 105,
		"skill_name": "追踪火箭筒", "skill_cost": 120, "skill_icon": "skills/minion-rocket.png",
		"skill_desc": "锁定 2000 码内的敌人，蓄力 1.5 秒后发射一枚慢速追踪导弹，命中时引发核爆，对 400 码范围内的敌人造成 [color=#ff9f43]4×攻击力[/color] 的物理伤害，并使其受到的治疗效果降低 50%，持续 4 秒。",
	},
	"elite": {
		"name": "精英小将", "img": "minion-elite.png", "role": "精英 · 近战",
		"hp": 1000, "atk": 50, "def": 16, "mr": 20, "interval": 1.54, "range": 100, "spd": 105,
		"skill_name": "铁锤", "skill_cost": 100,
		"skill_desc": "500 码内有敌人时举拳蓄力 0.35 秒，随后砸向地面，对前方 60° 锥形范围内 500 码的敌人造成 [color=#ff9f43]4×攻击力[/color] 的魔法伤害。每第 3 次施放时转而高高跃起，在空中蓄力 1 秒后砸下，对 700 码内的全部敌人造成 [color=#ff9f43]6×攻击力[/color] 的魔法伤害。",
		"passives": [
			{"name": "长手刃", "desc": "普通攻击造成 1×攻击力 的物理伤害，每第 5 次攻击附带旋刃。"},
			{"name": "吞噬", "desc": "目标生命值低于 15% 时发动吞噬，持续 1.5 秒，期间自身获得 [color=#ff9f43]95% 伤害减免[/color]。吞噬完成后回复 [color=#ff9f43]目标剩余生命的 2 倍[/color]，获得 50% 攻击速度提升，持续 5 秒，并窃取目标的主动技能。普通攻击、铁锁、铁拳与强化普通攻击均可触发。"},
			{"name": "铁锁", "desc": "每 5 秒一次：锁定 150~350 码之间的敌人，射出锁链，命中后将其眩晕 0.4 秒并拉至自身后方，造成 1×攻击力 的魔法伤害。"},
		],
	},
}

## 远程小将的非标准动作(技能)。★放这里不放主战斗文件: 项目规矩「纯数据/常量表 → gamedata/」,
## 而且主文件有行数预算(arch_budget), 加表会被拦。
const ACTION_RANGED := {
	"skill": ["pets/animations/ranged/skill.png", 4.6667],   # 7 帧 ÷ 4.6667fps = 1.5 秒 == 火箭蓄力节拍(门禁焊死)
}

## 原始立绘【朝右】的动画键(全项目默认朝左)。
##
## ★2026-08-21 按【动画键】而不是 id 登记(用户 2026-08-20 拍板方案 b):
##   三种小将**共用 id `"__minion__"`** ⇒ 按 id 登记会把三种一起翻,
##   而实测只有精英小将的 idle 立绘朝右(reach +37, 另两张 -28/-34)。
##   后果: 精英小将**站着不动时背对敌人, 一跑动/一出招又正对敌人**。
##   ⇒ 只翻精英那一个; **不动素材**(动素材会连带翻图鉴/背包/头像, 那三处不翻转直接贴 png)。
## ★2026-08-21 清空: 原来登记精英小将=朝右, 是为了绕开"idle 立绘朝右而动作图朝左"。
##   但逐帧量面罩位置后发现**动作图之间本身就不一致**(attack/hammer 朝右、hammer_big 朝左),
##   光改查表救不了 ⇒ 直接把 idle/attack/hammer **逐帧镜像**成朝左, 整套回归全局约定。
##   表留着(机制还在), 但现在是空的 —— 没有单位需要例外。
const ART_FACES_RIGHT_KEY: Array = []
