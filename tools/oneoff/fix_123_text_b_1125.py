"""fix_123_text_b_1125.py —— 123 亡者之书说明第三版(2026-11-25): 骷髅三项属性放回说明(分星标签按说明里逐星变化的数字显示, 拿掉就哪儿都不显示了),
其余句子压紧, 让 16:9 说明卡不出滚动条。效果 / 数字一个不改。"""
import re

CUR_ZH_START = "释放技能后随机召唤一具骷髅，存在时间等于这次技能消耗的龟能"
NEW_ZH = ("释放技能后随机召唤一具骷髅，持续时间等于这次消耗的龟能 × {C:EqMagicBatch.SKEL_SEC_PER_EN} 秒，骷髅龟能满 {C:EqMagicBatch.SKEL_EN_MAX} 点时释放技能。"
          "骷髅战士：生命值 {C:EqMagicBatch.SKW_HP}、攻击力 {C:EqMagicBatch.SKW_ATK}、双抗 {C:EqMagicBatch.SKW_RES}，近战。【骸骨狂怒】：{C:EqMagicBatch.SKW_RAGE_SEC} 秒内减伤 {C:EqMagicBatch.SKW_DR%}%，攻击额外造成 {C:EqMagicBatch.SKW_EXTRA%}% 攻击力物理伤害，生命偷取 {C:EqMagicBatch.SKW_LS%}%。"
          "骷髅法师：生命值 {C:EqMagicBatch.SKM_HP}、攻击力 {C:EqMagicBatch.SKM_ATK}、双抗 {C:EqMagicBatch.SKM_RES}，攻击造成 {C:EqMagicBatch.SKM_BASIC%}% 攻击力魔法伤害。【骨火爆裂】：目标周围的敌人受到 {C:EqMagicBatch.SKM_BLAST_ATK%}% 攻击力魔法伤害。"
          "骷髅祭司：生命值 {C:EqMagicBatch.SKP_HP}、攻击力 {C:EqMagicBatch.SKP_ATK}、双抗 {C:EqMagicBatch.SKP_RES}，攻击造成 {C:EqMagicBatch.SKP_BASIC%}% 攻击力魔法伤害。【亡灵浪潮】：浪潮缓慢前进，途经的敌人受到 {C:EqMagicBatch.WAVE_DMG} 物理伤害、被击飞并眩晕 {C:EqMagicBatch.WAVE_STUN} 秒、{C:EqMagicBatch.WAVE_MR_SEC} 秒内魔抗降低 {C:EqMagicBatch.WAVE_MR_SHRED%}%，途经的友军回复 {C:EqMagicBatch.WAVE_HEAL} 生命值。")
NEW_EN = ("Casting an ability summons a random skeleton for (energy spent × {C:EqMagicBatch.SKEL_SEC_PER_EN}) seconds. Skeletons cast their ability at {C:EqMagicBatch.SKEL_EN_MAX} energy. "
          "Skeleton Warrior: {C:EqMagicBatch.SKW_HP} Health, {C:EqMagicBatch.SKW_ATK} Attack, {C:EqMagicBatch.SKW_RES} Armor and Magic Resist, melee. [Bone Fury]: for {C:EqMagicBatch.SKW_RAGE_SEC} seconds, takes {C:EqMagicBatch.SKW_DR%}% less damage, attacks deal an extra {C:EqMagicBatch.SKW_EXTRA%}% Attack physical damage, {C:EqMagicBatch.SKW_LS%}% Life Steal. "
          "Skeleton Mage: {C:EqMagicBatch.SKM_HP} Health, {C:EqMagicBatch.SKM_ATK} Attack, {C:EqMagicBatch.SKM_RES} Armor and Magic Resist, attacks deal {C:EqMagicBatch.SKM_BASIC%}% Attack magic damage. [Bonefire Burst]: enemies around its target take {C:EqMagicBatch.SKM_BLAST_ATK%}% Attack magic damage. "
          "Skeleton Priest: {C:EqMagicBatch.SKP_HP} Health, {C:EqMagicBatch.SKP_ATK} Attack, {C:EqMagicBatch.SKP_RES} Armor and Magic Resist, attacks deal {C:EqMagicBatch.SKP_BASIC%}% Attack magic damage. [Wave of the Dead]: a slow wave deals {C:EqMagicBatch.WAVE_DMG} physical damage to enemies it passes, knocks them up and stuns them for {C:EqMagicBatch.WAVE_STUN} seconds, reduces their Magic Resist by {C:EqMagicBatch.WAVE_MR_SHRED%}% for {C:EqMagicBatch.WAVE_MR_SEC} seconds, and restores {C:EqMagicBatch.WAVE_HEAL} Health to allies it passes.")


def swap_zh(path):
    b = open(path, "rb").read().decode("utf-8")
    i = b.find(CUR_ZH_START)
    if i < 0:
        return 0
    j = b.index("生命值。", i) + len("生命值。")
    tail = b[j:j + 40]
    if tail.startswith("三种骷髅"):
        j = b.index("。", j) + 1
    b = b[:i] + NEW_ZH + b[j:]
    open(path, "wb").write(b.encode("utf-8"))
    return 1


n1 = swap_zh("data/phase2-equipment.json")
n2 = swap_zh("docs/design/装备逐件审查进度.md")
po = open("locale/en.po", "rb").read().decode("utf-8")
i = po.index('msgid "' + CUR_ZH_START)
k = po.index('"\r\n', i + 8)
po = po[:i] + 'msgid "' + NEW_ZH + po[k:]
j = po.index('msgstr "', i)
k = po.index('"\r\n', j + 8)
po = po[:j] + 'msgstr "' + NEW_EN + po[k:]
open("locale/en.po", "wb").write(po.encode("utf-8"))
print("ok", n1, n2, len(NEW_ZH))
