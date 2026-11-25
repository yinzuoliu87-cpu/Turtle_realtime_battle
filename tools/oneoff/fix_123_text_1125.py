"""fix_123_text_1125.py —— 123 亡者之书说明压短 + 三个技能名改成就地定义「【X】：」(2026-11-25 预检: verify_glossary 要求专名有出处;
verify_shop_interactions I8 16:9 说明卡出滚动条)。效果与数字不变, 只改写法: 「护甲和魔抗」→「双抗」(数据里已有 16 处同写法), 合并重复的句式。"""
import io, json, re

OLD_ZH = "释放技能后随机召唤一具骷髅战士、骷髅法师或骷髅祭司，存在时间等于这次技能消耗的龟能 × {C:EqMagicBatch.SKEL_SEC_PER_EN} 秒。骷髅龟能满 {C:EqMagicBatch.SKEL_EN_MAX} 点时释放技能。骷髅战士：{C:EqMagicBatch.SKW_HP} 生命值、{C:EqMagicBatch.SKW_ATK} 攻击力、{C:EqMagicBatch.SKW_RES} 护甲和魔抗，近战攻击。【骸骨狂怒】{C:EqMagicBatch.SKW_RAGE_SEC} 秒内受到的伤害降低 {C:EqMagicBatch.SKW_DR%}%，攻击额外造成 {C:EqMagicBatch.SKW_EXTRA%}% 攻击力物理伤害，并获得 {C:EqMagicBatch.SKW_LS%}% 生命偷取。骷髅法师：{C:EqMagicBatch.SKM_HP} 生命值、{C:EqMagicBatch.SKM_ATK} 攻击力、{C:EqMagicBatch.SKM_RES} 护甲和魔抗，远程攻击造成 {C:EqMagicBatch.SKM_BASIC%}% 攻击力魔法伤害。【骨火爆裂】对目标周围的敌人造成 {C:EqMagicBatch.SKM_BLAST_ATK%}% 攻击力魔法伤害。骷髅祭司：{C:EqMagicBatch.SKP_HP} 生命值、{C:EqMagicBatch.SKP_ATK} 攻击力、{C:EqMagicBatch.SKP_RES} 护甲和魔抗，远程攻击造成 {C:EqMagicBatch.SKP_BASIC%}% 攻击力魔法伤害。【亡灵浪潮】推出一道缓慢前进的浪潮，对途经的敌人造成 {C:EqMagicBatch.WAVE_DMG} 物理伤害、击飞并眩晕 {C:EqMagicBatch.WAVE_STUN} 秒、魔抗降低 {C:EqMagicBatch.WAVE_MR_SHRED%}%，持续 {C:EqMagicBatch.WAVE_MR_SEC} 秒，为途经的友军回复 {C:EqMagicBatch.WAVE_HEAL} 生命值。"
NEW_ZH = "释放技能后随机召唤一具骷髅，存在时间等于这次技能消耗的龟能 × {C:EqMagicBatch.SKEL_SEC_PER_EN} 秒，骷髅龟能满 {C:EqMagicBatch.SKEL_EN_MAX} 点时释放技能。骷髅战士：{C:EqMagicBatch.SKW_HP} 生命值、{C:EqMagicBatch.SKW_ATK} 攻击力、{C:EqMagicBatch.SKW_RES} 双抗，近战。【骸骨狂怒】：{C:EqMagicBatch.SKW_RAGE_SEC} 秒内受到的伤害降低 {C:EqMagicBatch.SKW_DR%}%，攻击额外造成 {C:EqMagicBatch.SKW_EXTRA%}% 攻击力物理伤害，获得 {C:EqMagicBatch.SKW_LS%}% 生命偷取。骷髅法师：{C:EqMagicBatch.SKM_HP} 生命值、{C:EqMagicBatch.SKM_ATK} 攻击力、{C:EqMagicBatch.SKM_RES} 双抗，攻击造成 {C:EqMagicBatch.SKM_BASIC%}% 攻击力魔法伤害。【骨火爆裂】：对目标周围的敌人造成 {C:EqMagicBatch.SKM_BLAST_ATK%}% 攻击力魔法伤害。骷髅祭司：{C:EqMagicBatch.SKP_HP} 生命值、{C:EqMagicBatch.SKP_ATK} 攻击力、{C:EqMagicBatch.SKP_RES} 双抗，攻击造成 {C:EqMagicBatch.SKP_BASIC%}% 攻击力魔法伤害。【亡灵浪潮】：缓慢前进的浪潮对途经的敌人造成 {C:EqMagicBatch.WAVE_DMG} 物理伤害、击飞并眩晕 {C:EqMagicBatch.WAVE_STUN} 秒、{C:EqMagicBatch.WAVE_MR_SEC} 秒内魔抗降低 {C:EqMagicBatch.WAVE_MR_SHRED%}%，为途经的友军回复 {C:EqMagicBatch.WAVE_HEAL} 生命值。"
NEW_EN = "Casting an ability summons a random skeleton that lasts for (energy spent on that ability × {C:EqMagicBatch.SKEL_SEC_PER_EN}) seconds. Skeletons cast their ability at {C:EqMagicBatch.SKEL_EN_MAX} energy. Skeleton Warrior: {C:EqMagicBatch.SKW_HP} Health, {C:EqMagicBatch.SKW_ATK} Attack, {C:EqMagicBatch.SKW_RES} Armor and Magic Resist, melee. [Bone Fury]: for {C:EqMagicBatch.SKW_RAGE_SEC} seconds, takes {C:EqMagicBatch.SKW_DR%}% less damage, attacks deal an extra {C:EqMagicBatch.SKW_EXTRA%}% Attack physical damage and it gains {C:EqMagicBatch.SKW_LS%}% Life Steal. Skeleton Mage: {C:EqMagicBatch.SKM_HP} Health, {C:EqMagicBatch.SKM_ATK} Attack, {C:EqMagicBatch.SKM_RES} Armor and Magic Resist, attacks deal {C:EqMagicBatch.SKM_BASIC%}% Attack magic damage. [Bonefire Burst]: deals {C:EqMagicBatch.SKM_BLAST_ATK%}% Attack magic damage to enemies around its target. Skeleton Priest: {C:EqMagicBatch.SKP_HP} Health, {C:EqMagicBatch.SKP_ATK} Attack, {C:EqMagicBatch.SKP_RES} Armor and Magic Resist, attacks deal {C:EqMagicBatch.SKP_BASIC%}% Attack magic damage. [Wave of the Dead]: a slow wave deals {C:EqMagicBatch.WAVE_DMG} physical damage to enemies it passes, knocks them up and stuns them for {C:EqMagicBatch.WAVE_STUN} seconds, reduces their Magic Resist by {C:EqMagicBatch.WAVE_MR_SHRED%}% for {C:EqMagicBatch.WAVE_MR_SEC} seconds, and restores {C:EqMagicBatch.WAVE_HEAL} Health to allies it passes."


def sub(path, old, new):
    b = open(path, "rb").read().decode("utf-8")
    assert b.count(old) >= 1, (path, "旧串没找到")
    b = b.replace(old, new)
    open(path, "wb").write(b.encode("utf-8"))


sub("data/phase2-equipment.json", OLD_ZH, NEW_ZH)
sub("docs/design/装备逐件审查进度.md", OLD_ZH, NEW_ZH) if OLD_ZH in open("docs/design/装备逐件审查进度.md", encoding="utf-8").read() else None
po = open("locale/en.po", "rb").read().decode("utf-8")
i = po.index('msgid "' + OLD_ZH + '"')
j = po.index("msgstr \"", i)
k = po.index("\"", j + 8)
while po[k - 1] == "\\":
    k = po.index("\"", k + 1)
po = po[:i] + 'msgid "' + NEW_ZH + '"' + po[i + len('msgid "' + OLD_ZH + '"'):j] + 'msgstr "' + NEW_EN + po[k:]
open("locale/en.po", "wb").write(po.encode("utf-8"))
print("ok", len(OLD_ZH), "→", len(NEW_ZH))
