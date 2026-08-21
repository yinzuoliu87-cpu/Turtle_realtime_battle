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
	return {"name": str(d.get("skill_name", "")), "desc": str(d.get("skill_desc", ""))}


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
const MINION_INFO := {
	"front": {
		"name": "近战小将", "img": "minion.png", "role": "前排 · 近战",
		"hp": 750, "atk": 42, "def": 13, "mr": 13, "interval": 0.85, "range": 70, "spd": 105,
		"skill_name": "人体浪板", "skill_cost": 120,
		"skill_desc": "射程 2000。高高跃起并回复 2×攻击力 生命(离目标太近则先后跳拉开)，射出铁链将目标眩晕并把自己拉过去；接触瞬间造成 [color=#ff9f43]目标 10% 最大生命[/color] 物理伤害，随后踩着目标滑行——对被踩者持续造成 2×攻击力 物理伤害，沿途敌人受到 1.5×攻击力 物理伤害并被击退，最后跳下。",
	},
	"back": {
		"name": "远程小将", "img": "minion-back.png", "role": "后排 · 远程",
		"hp": 750, "atk": 45, "def": 7, "mr": 7, "interval": 0.85, "range": 400, "spd": 105,
		"skill_name": "追踪火箭筒", "skill_cost": 120,
		"skill_desc": "射程 2000。蓄力 1.5 秒后发射一枚慢速追踪导弹，命中处核爆：400 码范围内造成 [color=#ff9f43]4×攻击力[/color] 物理伤害，并使命中的敌人受到的治疗降低 50%，持续 4 秒。",
	},
	"elite": {
		"name": "精英小将", "img": "minion-elite.png", "role": "统领位补位 · 近战",
		"hp": 1000, "atk": 50, "def": 16, "mr": 20, "interval": 1.54, "range": 90, "spd": 105,
		"skill_name": "铁锤", "skill_cost": 100,
		"skill_desc": "射程 500。举拳蓄力 0.35 秒后砸地，对身前 60° 锥形 500 码内造成 [color=#ff9f43]4×攻击力[/color] 魔法伤害；每第 3 次改为高高跃起、空中蓄力 1 秒后下锤，覆盖 700 码全域并造成 [color=#ff9f43]6×攻击力[/color] 魔法伤害。",
		"passives": [
			{"name": "长手刃 (普攻)", "desc": "普攻造成 1×攻击力 物理伤害，每第 5 击附带旋刃。"},
			{"name": "吞噬", "desc": "目标生命低于 15% 时发动，1.5 秒演出期间自身获得 [color=#ff9f43]95% 伤害减免[/color]，完成后回复 [color=#ff9f43]目标剩余生命的 2 倍[/color]，并获得持续 5 秒的 50% 攻速提升，同时窃取目标的主动技能。普攻、铁锁、铁拳与强化普攻都能触发。"},
			{"name": "铁锁", "desc": "冷却 5 秒。锁定 150~350 码之间的敌人，链射命中后使其眩晕 0.4 秒、拉到自己身后，并造成 1×攻击力 魔法伤害。"},
		],
	},
}

## 远程小将的非标准动作(技能)。★放这里不放主战斗文件: 项目规矩「纯数据/常量表 → gamedata/」,
## 而且主文件有行数预算(arch_budget), 加表会被拦。
const ACTION_RANGED := {
	"skill": ["pets/animations/ranged/skill.png", 4.0],   # 6 帧 ÷ 4fps = 1.5 秒 == 火箭蓄力节拍(门禁焊死)
}

## 原始立绘【朝右】的动画键(全项目默认朝左)。
##
## ★2026-08-21 按【动画键】而不是 id 登记(用户 2026-08-20 拍板方案 b):
##   三种小将**共用 id `"__minion__"`** ⇒ 按 id 登记会把三种一起翻,
##   而实测只有精英小将的 idle 立绘朝右(reach +37, 另两张 -28/-34)。
##   后果: 精英小将**站着不动时背对敌人, 一跑动/一出招又正对敌人**。
##   ⇒ 只翻精英那一个; **不动素材**(动素材会连带翻图鉴/背包/头像, 那三处不翻转直接贴 png)。
const ART_FACES_RIGHT_KEY := ["__minion_elite__"]
