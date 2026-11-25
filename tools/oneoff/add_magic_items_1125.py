"""add_magic_items_1125.py —— 魔法书羁绊 10 件新装备进数据表(方案书 docs/plans/20261125b-魔法书羁绊.md §4.2)

  python tools/oneoff/add_magic_items_1125.py      # 幂等: 已有同 id 就覆盖那一条

写三处: data/phase2-equipment.json(条目) · data/p2eq-types.json(羁绊归属) · scripts/gamedata/equip_stats.gd(STATS 基础属性)。
效果文案里的数一律 {C:EqMagicBatch.X} 引用常量(tooltip_number_audit 对账); 体例照 copy_lol_style_lint / copy_style_audit /
codex_text_lint(写「攻击」不写普攻、不写码数、不用分号、百分比生命写明是谁的、不写「携带者」)。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
E = "EqMagicBatch"


def c(name):
    return "{C:%s.%s}" % (E, name)


def cp(name):
    return "{C:%s.%s%%}%%" % (E, name)


ITEMS = [
    # id, 名, 费, 展示属性, STATS(1/2/3★), 效果全文, 一句话
    ("p2eq_117", "学徒笔记", 1, "+攻6/12/20·增伤3/5/8%",
     [{"atk": 6, "dmgAmp": 0.03}, {"atk": 12, "dmgAmp": 0.05}, {"atk": 20, "dmgAmp": 0.08}],
     "每第 %s 次攻击额外射出一枚追踪魔法飞弹，造成（%s+%s 攻击力）魔法伤害。" % (c("NOTE_EVERY"), c("NOTE_FLAT"), cp("NOTE_ATK")),
     "每第三次攻击额外射出一枚追踪魔法飞弹。"),
    ("p2eq_118", "羊皮咒卷", 1, "+生命80/160/300·魔抗8/15/25",
     [{"hp": 80, "mr": 8}, {"hp": 160, "mr": 15}, {"hp": 300, "mr": 25}],
     "释放技能时获得 %s 点护盾，持续 %s 秒。" % (c("SCROLL_SHIELD"), c("SCROLL_SEC")),
     "释放技能时获得护盾。"),
    ("p2eq_119", "烈焰法典", 2, "+攻14/30/50·增伤4/7/10%",
     [{"atk": 14, "dmgAmp": 0.04}, {"atk": 30, "dmgAmp": 0.07}, {"atk": 50, "dmgAmp": 0.10}],
     "释放技能时朝最近的敌人掷出一颗火球，造成（%s+%s 攻击力）魔法伤害并施加灼烧，层数等于这次技能消耗龟能的 %s。"
     % (c("FIRE_FLAT"), cp("FIRE_ATK"), cp("FIRE_BURN_PER_EN")),
     "释放技能时朝最近的敌人掷出火球，消耗的龟能越多灼烧越多。"),
    ("p2eq_120", "霜语魔典", 2, "+生命100/200/380·护甲8/15/25",
     [{"hp": 100, "def": 8}, {"hp": 200, "def": 15}, {"hp": 380, "def": 25}],
     "释放技能时对周围的敌人释放冰霜新星，造成（%s+%s 攻击力）魔法伤害并施加冰寒，使其移动速度降低 %s、攻击速度降低 %s，"
     "持续时间等于这次技能消耗的龟能 × %s 秒。" % (c("FROST_FLAT"), cp("FROST_ATK"), cp("FROST_MOVE_DOWN"), cp("FROST_ASPD_DOWN"), c("FROST_SEC_PER_EN")),
     "释放技能时冻住周围的敌人，消耗的龟能越多冰寒越久。"),
    ("p2eq_121", "风暴之书", 3, "+攻15/28/48·增伤5/8/12%",
     [{"atk": 15, "dmgAmp": 0.05}, {"atk": 28, "dmgAmp": 0.08}, {"atk": 48, "dmgAmp": 0.12}],
     "每 %s 秒对 %s 名随机敌人各降下一道闪电，造成（%s+%s 攻击力）魔法伤害。" % (c("STORM_IV"), c("STORM_N"), c("STORM_FLAT"), cp("STORM_ATK")),
     "定时对随机敌人降下闪电。"),
    ("p2eq_122", "治愈圣典", 3, "+生命120/240/450·治疗增幅6/10/15%",
     [{"hp": 120, "healAmp": 6}, {"hp": 240, "healAmp": 10}, {"hp": 450, "healAmp": 15}],
     "释放技能时为生命值比例最低的友军施加持续回复，每秒回复（%s+%s 攻击力）生命值，持续时间等于这次技能消耗的龟能 × %s 秒。"
     % (c("HOLY_FLAT"), cp("HOLY_ATK"), c("HOLY_SEC_PER_EN")),
     "释放技能时为生命值比例最低的友军持续回复生命值。"),
    ("p2eq_123", "亡者之书", 4, "+生命200/420/1000·攻20/38/90",
     [{"hp": 200, "atk": 20}, {"hp": 420, "atk": 38}, {"hp": 1000, "atk": 90}],
     "释放技能后随机召唤一具骷髅战士、骷髅法师或骷髅祭司，存在时间等于这次技能消耗的龟能 × %s 秒。骷髅龟能满 %s 点时释放技能。"
     "骷髅战士：%s 生命值、%s 攻击力、%s 护甲和魔抗，近战攻击。【骸骨狂怒】%s 秒内受到的伤害降低 %s，攻击额外造成 %s 攻击力物理伤害，并获得 %s 生命偷取。"
     "骷髅法师：%s 生命值、%s 攻击力、%s 护甲和魔抗，远程攻击造成 %s 攻击力魔法伤害。【骨火爆裂】对目标周围的敌人造成 %s 攻击力魔法伤害。"
     "骷髅祭司：%s 生命值、%s 攻击力、%s 护甲和魔抗，远程攻击造成 %s 攻击力魔法伤害。【亡灵浪潮】推出一道缓慢前进的浪潮，对途经的敌人造成 %s 物理伤害、击飞并眩晕 %s 秒、魔抗降低 %s，持续 %s 秒，为途经的友军回复 %s 生命值。"
     % (c("SKEL_SEC_PER_EN"), c("SKEL_EN_MAX"),
        c("SKW_HP"), c("SKW_ATK"), c("SKW_RES"), c("SKW_RAGE_SEC"), cp("SKW_DR"), cp("SKW_EXTRA"), cp("SKW_LS"),
        c("SKM_HP"), c("SKM_ATK"), c("SKM_RES"), cp("SKM_BASIC"), cp("SKM_BLAST_ATK"),
        c("SKP_HP"), c("SKP_ATK"), c("SKP_RES"), cp("SKP_BASIC"), c("WAVE_DMG"), c("WAVE_STUN"), cp("WAVE_MR_SHRED"), c("WAVE_MR_SEC"), c("WAVE_HEAL")),
     "释放技能后召唤一具随机的骷髅战士、法师或祭司。"),
    ("p2eq_124", "镜像魔典", 4, "+生命220/460/1050·双抗10/18/30",
     [{"hp": 220, "def": 10, "mr": 10}, {"hp": 460, "def": 18, "mr": 18}, {"hp": 1050, "def": 30, "mr": 30}],
     "每个战场第一次释放技能后，立即再释放一次。每次释放技能将消耗的龟能存入充能条，存满 %s 点后清空，下一次释放技能后立即再释放一次。"
     "再释放的那一次同样算作释放技能，但不存入充能条。" % c("MIRROR_THR"),
     "每个战场第一次释放技能和充能条存满后的那次技能，都会再释放一次。"),
    ("p2eq_125", "禁咒全书", 5, "+攻40/90/400·增伤10/15/25%",
     [{"atk": 40, "dmgAmp": 0.10}, {"atk": 90, "dmgAmp": 0.15}, {"atk": 400, "dmgAmp": 0.25}],
     "技能的龟能消耗减少 %s 点。释放技能后，下一次攻击额外射出一枚禁咒弹，造成（%s+%s 攻击力+目标 %s 最大生命值）魔法伤害，并对目标周围的敌人造成其 %s 的伤害。"
     % (c("FORB_CUT"), c("FORB_FLAT"), cp("FORB_ATK"), cp("FORB_MAXHP"), cp("FORB_SPLASH")),
     "技能更快就绪，释放技能后的下一次攻击射出禁咒弹。"),
    ("p2eq_126", "浮空魔典", 5, "+生命300/700/2000·攻30/70/300",
     [{"hp": 300, "atk": 30}, {"hp": 700, "atk": 70}, {"hp": 2000, "atk": 300}],
     "释放技能后获得 %s 点最大生命值并回复等量生命值，持续时间等于这次技能消耗的龟能 × %s 秒。"
     "近战单位携带时，%s 张书页环绕自身，每 %s 秒对碰到的敌人造成（%s+%s 攻击力）魔法伤害，每碰到一名敌人获得 %s 点护盾，持续 %s 秒，至多 %s 点。"
     "远程单位携带时，身后悬浮至多 %s 张书页，每 %s 秒补充一张。受到不低于自身 %s 最大生命值的单次攻击或技能伤害时，消耗一张书页抵挡至多 %s 点伤害，持续伤害不会触发。"
     % (c("TOME_HP"), c("TOME_SEC_PER_EN"),
        c("PAGE_N"), c("PAGE_IV"), c("PAGE_FLAT"), cp("PAGE_ATK"), c("PAGE_SHIELD"), c("PAGE_SHIELD_SEC"), c("PAGE_SHIELD_CAP"),
        c("PAGE_N"), c("PAGE_REGEN"), cp("PAGE_BLOCK_PCT"), c("PAGE_BLOCK_MAX")),
     "释放技能后提高最大生命值。近战时书页环绕伤敌并给护盾，远程时书页替自身挡下大额伤害。"),
]


def main():
    p = os.path.join(ROOT, "data/phase2-equipment.json")
    d = json.loads(open(p, "rb").read().decode("utf-8"))
    idx = {e["id"]: i for i, e in enumerate(d)}
    for (iid, name, cost, shown, stats, desc, brief) in ITEMS:
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "📖",
               "effectDesc1": desc, "effectDesc3": "", "img": "equip/%s.png" % iid, "effectBrief": brief}
        if iid in idx:
            d[idx[iid]] = ent
        else:
            d.append(ent)
    out = json.dumps(d, ensure_ascii=False, indent=2) + "\n"
    open(p, "wb").write(out.replace("\n", "\r\n").encode("utf-8"))

    tp = os.path.join(ROOT, "data/p2eq-types.json")
    t = json.loads(open(tp, "rb").read().decode("utf-8"))
    for it in ITEMS:
        t[it[0]] = "魔法书"
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, shown, stats, desc, brief) in reversed(ITEMS):   # 倒着插在 116 后面 ⇒ 表里按 117→126 顺序
        line = '\t"%s": %s,   # 魔法书 · %d费 · %s(2026-11-25 方案书 20261125b)' % (iid, json.dumps(stats, ensure_ascii=False), cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_116": .*$', s, re.M)
        assert anchor, "找不到 p2eq_116 锚点"
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("写入 %d 件" % len(ITEMS))


if __name__ == "__main__":
    main()
