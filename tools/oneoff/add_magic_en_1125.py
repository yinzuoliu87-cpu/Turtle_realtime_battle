"""add_magic_en_1125.py —— 魔法书羁绊 + 10 件 + 三种骷髅的英文(locale/en.po 末尾追加; 中文原文一律从数据表 / 类型表现读, 不手抄)

    python tools/oneoff/add_magic_en_1125.py      # 幂等: 已有的 msgid 跳过
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
E = "EqMagicBatch"
M = "MagicbookSynergySystem"


def c(n, k=E):
    return "{C:%s.%s}" % (k, n)


def cp(n, k=E):
    return "{C:%s.%s%%}%%" % (k, n)


## 装备: id → (英文名, 效果全文, 一句话)
ITEMS = {
    "p2eq_117": ("Apprentice's Notes",
                 "Every %s attack fires an extra homing magic missile that deals (%s + %s Attack) magic damage." % (c("NOTE_EVERY") + "rd", c("NOTE_FLAT"), cp("NOTE_ATK")),
                 "Every third attack fires an extra homing magic missile."),
    "p2eq_118": ("Parchment Scroll",
                 "Casting an ability grants a %s Shield for %s seconds." % (c("SCROLL_SHIELD"), c("SCROLL_SEC")),
                 "Casting an ability grants a Shield."),
    "p2eq_119": ("Tome of Flames",
                 "Casting an ability hurls a fireball at the nearest enemy, dealing (%s + %s Attack) magic damage and applying Burn stacks equal to %s of the energy spent on that ability."
                 % (c("FIRE_FLAT"), cp("FIRE_ATK"), cp("FIRE_BURN_PER_EN")),
                 "Casting an ability hurls a fireball at the nearest enemy; the more energy spent, the more Burn."),
    "p2eq_120": ("Frostwhisper Grimoire",
                 "Casting an ability releases a frost nova around you, dealing (%s + %s Attack) magic damage and applying Chill, reducing Move Speed by %s and Attack Speed by %s for (energy spent on that ability × %s) seconds."
                 % (c("FROST_FLAT"), cp("FROST_ATK"), cp("FROST_MOVE_DOWN"), cp("FROST_ASPD_DOWN"), c("FROST_SEC_PER_EN")),
                 "Casting an ability chills nearby enemies; the more energy spent, the longer the Chill."),
    "p2eq_121": ("Book of Storms",
                 "Every %s seconds, lightning strikes %s random enemies, each taking (%s + %s Attack) magic damage." % (c("STORM_IV"), c("STORM_N"), c("STORM_FLAT"), cp("STORM_ATK")),
                 "Periodically calls lightning down on random enemies."),
    "p2eq_122": ("Codex of Mending",
                 "Casting an ability grants the ally with the lowest Health percentage a heal over time that restores (%s + %s Attack) Health per second for (energy spent on that ability × %s) seconds."
                 % (c("HOLY_FLAT"), cp("HOLY_ATK"), c("HOLY_SEC_PER_EN")),
                 "Casting an ability heals the ally with the lowest Health percentage over time."),
    "p2eq_123": ("Book of the Dead",
                 "Casting an ability summons a random Skeleton Warrior, Skeleton Mage or Skeleton Priest that lasts for (energy spent on that ability × %s) seconds. Skeletons cast their ability at %s energy. "
                 "Skeleton Warrior: %s Health, %s Attack, %s Armor and Magic Resist, melee attacks. [Bone Fury] For %s seconds, takes %s less damage, its attacks deal an extra %s Attack physical damage and it gains %s Life Steal. "
                 "Skeleton Mage: %s Health, %s Attack, %s Armor and Magic Resist, ranged attacks deal %s Attack magic damage. [Bonefire Burst] Deals %s Attack magic damage to enemies around its target. "
                 "Skeleton Priest: %s Health, %s Attack, %s Armor and Magic Resist, ranged attacks deal %s Attack magic damage. [Wave of the Dead] Pushes a slow wave forward that deals %s physical damage to enemies it passes, knocks them up and stuns them for %s seconds and reduces their Magic Resist by %s for %s seconds, and restores %s Health to allies it passes."
                 % (c("SKEL_SEC_PER_EN"), c("SKEL_EN_MAX"),
                    c("SKW_HP"), c("SKW_ATK"), c("SKW_RES"), c("SKW_RAGE_SEC"), cp("SKW_DR"), cp("SKW_EXTRA"), cp("SKW_LS"),
                    c("SKM_HP"), c("SKM_ATK"), c("SKM_RES"), cp("SKM_BASIC"), cp("SKM_BLAST_ATK"),
                    c("SKP_HP"), c("SKP_ATK"), c("SKP_RES"), cp("SKP_BASIC"), c("WAVE_DMG"), c("WAVE_STUN"), cp("WAVE_MR_SHRED"), c("WAVE_MR_SEC"), c("WAVE_HEAL")),
                 "Casting an ability summons a random skeleton warrior, mage or priest."),
    "p2eq_124": ("Mirror Grimoire",
                 "The first time you cast an ability on each battlefield, cast it again immediately. Each cast stores the energy spent in a charge bar; when it reaches %s, it empties and your next ability is cast again immediately. "
                 "The repeated cast also counts as casting an ability, but does not add to the charge bar." % c("MIRROR_THR"),
                 "Your first ability on each battlefield, and the one after the charge bar fills, are cast twice."),
    "p2eq_125": ("Forbidden Codex",
                 "Your abilities cost %s less energy. After casting an ability, your next attack becomes a forbidden bolt that deals (%s + %s Attack + %s of the target's maximum Health) magic damage, and deals %s of that damage to enemies around the target."
                 % (c("FORB_CUT"), c("FORB_FLAT"), cp("FORB_ATK"), cp("FORB_MAXHP"), cp("FORB_SPLASH")),
                 "Abilities are ready sooner, and the attack after each ability becomes a forbidden bolt."),
    "p2eq_126": ("Floating Tome",
                 "Casting an ability grants %s maximum Health and restores the same amount of Health for (energy spent on that ability × %s) seconds. "
                 "On a melee carrier, %s pages orbit you, dealing (%s + %s Attack) magic damage to enemies they touch every %s seconds and granting a %s Shield for %s seconds for each enemy touched, up to %s. "
                 "On a ranged carrier, up to %s pages float behind you, regrowing one every %s seconds. When a single attack or ability deals damage of at least %s of your maximum Health, a page blocks up to %s of it. Damage over time does not trigger it."
                 % (c("TOME_HP"), c("TOME_SEC_PER_EN"),
                    c("PAGE_N"), c("PAGE_FLAT"), cp("PAGE_ATK"), c("PAGE_IV"), c("PAGE_SHIELD"), c("PAGE_SHIELD_SEC"), c("PAGE_SHIELD_CAP"),
                    c("PAGE_N"), c("PAGE_REGEN"), cp("PAGE_BLOCK_PCT"), c("PAGE_BLOCK_MAX")),
                 "Casting an ability raises maximum Health. Melee: orbiting pages cut enemies and grant Shields. Ranged: pages block big hits."),
}

## 类型表 / 骷髅名 / 其它: 中文 → 英文(中文按类型表现读的那几条在 main 里取)
EXTRA = {
    "魔法书": "Spellbook",
    "魔法书·飞弹": "Spellbooks · Magic Missiles",
    "骷髅战士": "Skeleton Warrior",
    "骷髅法师": "Skeleton Mage",
    "骷髅祭司": "Skeleton Priest",
}
INTRO_EN = "Spellbooks grant their carriers Damage Amp. Whenever any allied unit (summons included) casts an ability, it conjures magic missiles based on the energy spent, which fly at random enemies."
TIER_EN = [
    "Each Spellbook grants its carrier +3%% Damage Amp · [Magic Missiles] Whenever an allied unit casts an ability, it conjures 1 magic missile per {C:%s.PER_ENERGY[0]} energy spent (at least 1). Each flies at a random enemy and deals ({C:%s.DMG_FLAT[0]} + {C:%s.DMG_MAXHP[0]%%}%% of the target's maximum Health) magic damage" % (M, M, M),
    "Each Spellbook grants its carrier +6%% Damage Amp · [Magic Missiles] now 1 missile per {C:%s.PER_ENERGY[1]} energy, damage increased to ({C:%s.DMG_FLAT[1]} + {C:%s.DMG_MAXHP[1]%%}%% of the target's maximum Health)" % (M, M, M),
    "Each Spellbook grants its carrier +10%% Damage Amp · [Magic Missiles] now 1 missile per {C:%s.PER_ENERGY[2]} energy, damage increased to ({C:%s.DMG_FLAT[2]} + {C:%s.DMG_MAXHP[2]%%}%% of the target's maximum Health)" % (M, M, M),
]


def _q(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    po = os.path.join(ROOT, "locale", "en.po")
    raw = open(po, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    have = set(re.findall(r'^msgid "(.*)"$', raw.replace("\r\n", "\n"), re.M))
    pairs = []
    data = json.loads(open(os.path.join(ROOT, "data", "phase2-equipment.json"), "rb").read().decode("utf-8"))
    by = {e["id"]: e for e in data}
    for iid, (name, desc, brief) in ITEMS.items():
        e = by[iid]
        pairs += [(e["name"], name), (e["effectDesc1"], desc), (e["effectBrief"], brief)]
    pairs += list(EXTRA.items())
    ## 类型表里的简介 / 逐档文案: 从源码现读中文(单引号里的那几行), 不手抄
    src = open(os.path.join(ROOT, "scripts", "gamedata", "phase2_types.gd"), "rb").read().decode("utf-8")
    intro = re.search(r'"魔法书": \[\s*"(魔法书提高[^"]*)"', src).group(1)
    pairs.append((intro, INTRO_EN))
    tiers = re.findall(r'"(每件魔法书为携带者提供[^"]*)"', src)
    assert len(tiers) == 3, tiers
    for zh, en in zip(tiers, TIER_EN):
        pairs.append((zh, en))
    add = []
    for zh, en in pairs:
        if zh in have:
            continue
        have.add(zh)
        add.append('msgid "%s"%smsgstr "%s"%s' % (_q(zh), nl, _q(en), nl))
    if add:
        raw = raw.rstrip("\r\n") + nl + nl + (nl).join(add)
        open(po, "wb").write(raw.encode("utf-8"))
    print("追加 %d 条" % len(add))


if __name__ == "__main__":
    main()
