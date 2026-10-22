class_name ChestLoot
extends RefCounted
## 宝箱龟【藏宝图】的战利品表: 三个池子 / 名字 / 效果说明 / 开箱阈值 / 图标路径。
##
## ★为什么单独一个文件(2026-10-22 背包显示战利品): 原来这几张表写在战斗主场景里,
##   只有战斗读; 背包的宝箱龟卡要显示「已开的战利品 + 距下一箱」, 也得读同一张表。
##   背包去引用战斗主场景的私有常量不对, 抄一份更不对 ⇒ 按 CLAUDE.md §5「纯数据 / 常量表 → scripts/gamedata/」落在这里。
##   主场景的 `_CHEST_TREASURE_POOL` / `_CHEST_TREASURE_NAME` / `_CHEST_TREASURE_DESC` / `_CHEST_THRESH`
##   只是指向这里的别名(玩家文案 `{C:RealtimeBattle3DScene._CHEST_THRESH}` 照旧能取到)。
##
## ⚠ 本文件只放常量与取数, 不放逻辑。战利品的【效果】在 `ChestSystem._chest_apply_treasure`。

## 第 1~2 箱开基础池, 第 3~4 箱开进阶池, 第 5 箱开传说池(`ChestSystem` 按已开件数选池)。
const POOL := {
	"basic":  ["dagger", "wood_shield", "rum", "blood_dice", "chain", "stone"],
	"adv":    ["long_sword", "bloodblade", "flint", "gem_armor", "poison", "phoenix_statue"],
	"legend": ["crown", "thunder", "starlight"],
}
## 名字 = 回合制版原名(`docs/design/回合制原始数值-对照表.md` 宝箱龟 pools 的 name)。
##   2026-07-09 移植实时版时被缩成两三个字(「星辉」「雷刃」…), 没经过拍板; 用户 2026-10-22「就叫星辉？不对啊」⇒ 全部恢复原名。
const NAME := {
	"dagger": "锋利短刃", "wood_shield": "坚固木盾", "rum": "海盗龟的小瓶朗姆酒", "blood_dice": "骰子龟的血筛子",
	"chain": "锁链", "stone": "神奇石头",
	"long_sword": "精钢长剑", "bloodblade": "嗜血之刃", "flint": "灼热火石", "gem_armor": "宝石铠甲",
	"poison": "淬毒箭矢", "phoenix_statue": "凤凰龟雕像",
	"crown": "王者之冠", "thunder": "闪电龟的雷刃", "starlight": "星际龟的星辉",
}

## 战利品说明 —— 照装备文案的规矩写(用户 2026-10-22「这里的描述也得符合规矩」):
##   云顶式不写龟名、「攻击」不写「普攻」、系数写百分比不写「×」、数字一律 `{C:}` 引用代码常量(展开走 `desc_plain` / `desc_bb`)。
##   句式出处是 LoL 中文原文(C:/tmp/lol/corpus.json), 不拿本仓自己的文案当出处(用户 2026-10-22「满N层时引爆，这是哪来的」):
##   叠层触发 =「在{{N}}层时，这个炸弹会立刻爆炸」· 范围 =「攻击范围都得到提高」· 获得属性 =「获得{{ totalad }}攻击力」·
##   「一部分伤害会转化为真实伤害」·「她的攻击和技能会造成额外伤害」。
##   体例门禁 `tools/copy_lol_style_lint.py` 扫这个文件。效果的实现在 `ChestSystem._chest_apply_treasure` 与 battle_damage 的命中钩子。
const DESC := {
	"dagger": "获得 {C:ChestSystem.DAGGER_ATK%}% 攻击力。",
	"wood_shield": "获得 {C:ChestSystem.WOOD_RES%}% 护甲与魔抗。",
	"rum": "每秒回复自身 {C:ChestSystem.RUM_HEAL_PCT%}% 最大生命值。",
	"blood_dice": "获得 {C:ChestSystem.DICE_CRIT%}% 暴击率。",
	"chain": "【宝箱砸击】的范围提高 {C:ChestSystem.CHAIN_AOE_UP%}%。",
	"stone": "【宝箱砸击】额外造成（{C:ChestSystem.STONE_RES_COEF%}% 护甲与魔抗之和）物理伤害。",
	"long_sword": "获得 {C:ChestSystem.SWORD_ATK%}% 攻击力。",
	"bloodblade": "获得 {C:ChestSystem.BLADE_LS%}% 生命偷取。",
	"flint": "攻击和技能命中时，施加（{C:ChestSystem.FLINT_BURN_COEF%}% 攻击力）层灼烧。",
	"gem_armor": "获得 {C:ChestSystem.GEM_HP} 最大生命值、{C:ChestSystem.GEM_RES%}% 护甲与魔抗。",
	"poison": "攻击和技能命中时，对目标施加 {C:ChestSystem.POISON_CUT%}% 治疗削减，持续 {C:ChestSystem.POISON_SEC} 秒。",
	"phoenix_statue": "首次死亡时以自身 {C:AngelSystem.REVIVE_HP_PCT%}% 最大生命值复活一次。",
	"crown": "获得 {C:ChestSystem.CROWN_ATK%}% 攻击力、{C:ChestSystem.CROWN_CRIT%}% 暴击率、{C:ChestSystem.CROWN_CRIT_DMG%}% 暴击伤害与 {C:ChestSystem.CROWN_LS%}% 生命偷取。",
	"thunder": "攻击和技能命中时为目标叠加 1 层金色闪电。在 {C:ChestSystem.THUNDER_STACKS} 层时，金色闪电会引爆，造成 {C:ChestSystem.THUNDER_ATK_COEF%}% 攻击力的真实伤害。",
	"starlight": "攻击和技能伤害转化为真实伤害。",   # 用户 2026-10-22 原话「攻击和技能伤害转化为真实伤害」
}

## 大轮制开箱阈值(用户 2026-08-14 上调: 原 1000/2500/4500/7000/12000)。件数上限 = 本表长度。
const THRESH := [3000.0, 6000.0, 10000.0, 18000.0, 30000.0]


## 说明的纯文本(`{C:}` 已展开)。
static func desc_plain(tid: String) -> String:
	return SkillText.render_consts(str(DESC.get(tid, "")))


## 说明的 BBCode 版: 与装备说明同一条上色 / 内联属性图标管线(`SkillText.plain_to_bb`)。
static func desc_bb(tid: String, font_px: int = 0) -> String:
	return SkillText.plain_to_bb(desc_plain(tid), font_px)


static func icon_path(tid: String) -> String:
	return "res://assets/sprites/equip/chest-t-%s.png" % tid


## 已开 `opened` 件时, 下一箱的阈值; 已开满 ⇒ -1。
static func next_threshold(opened: int) -> float:
	return float(THRESH[opened]) if opened >= 0 and opened < THRESH.size() else -1.0
