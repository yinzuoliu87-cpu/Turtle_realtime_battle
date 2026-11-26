"""add_mask_items_1126.py —— 面具羁绊 10 件新装备进数据表(方案书 docs/plans/20261125c-面具羁绊.md §3)

  python tools/oneoff/add_mask_items_1126.py      # 幂等: 已有同 id 就覆盖那一条

写三处: data/phase2-equipment.json(条目) · data/p2eq-types.json(羁绊归属) · scripts/gamedata/equip_stats.gd(STATS 基础属性)。
效果文案里的数一律 {C:EqMaskBatch.X} / {C:OtherworldSystem.X} 引用常量(tooltip_number_audit 对账); 体例照 copy_lol_style_lint 等
(写「攻击」不写普攻、不写码数、不用分号、百分比生命写明是谁的、不写「携带者」)。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")


def c(name, cls="EqMaskBatch"):
    return "{C:%s.%s}" % (cls, name)


def cp(name, cls="EqMaskBatch"):
    return "{C:%s.%s%%}%%" % (cls, name)


ITEMS = [
    # id, 名, 费, 展示属性, STATS(1/2/3★), 效果全文, 一句话
    ("p2eq_127", "纸面具", 1, "+护甲8/15/25·减伤2/3/5%",
     [{"def": 8, "dmgRed": 0.02}, {"def": 15, "dmgRed": 0.03}, {"def": 25, "dmgRed": 0.05}],
     "登场时获得自身 %s 最大生命值的物理护盾，该护盾只吸收物理伤害。每受到一段攻击或技能伤害，朝攻击者掷出一片纸刃，造成自身 %s 护甲的物理伤害。持续伤害不会触发此效果。"
     % (cp("PAPER_SHIELD_PCT"), cp("PAPER_COUNTER")),
     "登场获得物理护盾，挨打时按护甲朝攻击者掷出纸刃。"),
    ("p2eq_128", "狐狸面具", 1, "+攻6/12/20·减伤2/3/5%",
     [{"atk": 6, "dmgRed": 0.02}, {"atk": 12, "dmgRed": 0.03}, {"atk": 20, "dmgRed": 0.05}],
     "对最大生命值高于自身的敌人伤害提高，提高量随两者最大生命值的差值增加，差值达到 %s 时提高 %s。" % (c("FOX_FULL_DIFF"), cp("FOX_MAX")),
     "对最大生命值比自己高的敌人伤害提高，差得越多提高越多。"),
    ("p2eq_129", "京剧脸谱", 2, "+攻14/30/50·减伤3/4/6%",
     [{"atk": 14, "dmgRed": 0.03}, {"atk": 30, "dmgRed": 0.04}, {"atk": 50, "dmgRed": 0.06}],
     "每 %s 秒按红、黑、白的顺序换一次脸谱。红脸：攻击额外造成 %s 攻击力的真实伤害。黑脸：每段受到的伤害减少 %s 点，并获得 %s 护甲和魔抗。"
     "白脸：获得 %s 攻击速度，攻击偷取目标 %s 点龟能。"
     % (c("FACE_IV"), cp("FACE_RED_TRUE"), c("FACE_BLACK_FLAT"), c("FACE_BLACK_RES"), cp("FACE_WHITE_ASPD"), c("FACE_WHITE_EN")),
     "定时按红、黑、白轮换脸谱：红脸加真伤，黑脸减伤加双抗，白脸加攻速并偷龟能。"),
    ("p2eq_130", "舞狮头", 2, "+生命100/200/380·减伤3/4/6%",
     [{"hp": 100, "dmgRed": 0.03}, {"hp": 200, "dmgRed": 0.04}, {"hp": 380, "dmgRed": 0.06}],
     "登场时召唤一头舞狮：%s 生命值、%s 攻击力、%s 护甲和魔抗，近战攻击。舞狮龟能满时朝前方冲撞，对途经的敌人造成 %s 舞狮攻击力的物理伤害，将其撞退并眩晕 %s 秒。"
     % (c("LION_HP"), c("LION_ATK"), c("LION_RES"), cp("LION_CHARGE_ATK"), c("LION_STUN")),
     "召唤一头舞狮，龟能满时冲撞途经的敌人，撞退并眩晕。"),
    ("p2eq_131", "小丑面具", 3, "+生命120/240/450·减伤3/5/8%",
     [{"hp": 120, "dmgRed": 0.03}, {"hp": 240, "dmgRed": 0.05}, {"hp": 450, "dmgRed": 0.08}],
     "释放技能后嘲讽附近的敌人，每消耗 100 点龟能嘲讽 %s 秒，并获得自身 %s 最大生命值的护盾，持续 %s 秒。"
     % (c("CLOWN_SEC_PER_100"), cp("CLOWN_SHIELD_PCT"), c("CLOWN_SHIELD_SEC")),
     "释放技能后嘲讽附近的敌人并获得护盾，技能消耗的龟能越多嘲讽越久。"),
    ("p2eq_132", "鬼面", 3, "+攻15/28/48·减伤3/5/8%",
     [{"atk": 15, "dmgRed": 0.03}, {"atk": 28, "dmgRed": 0.05}, {"atk": 48, "dmgRed": 0.08}],
     "生命值首次降到 %s 时进入潜行，持续 %s 秒：无法被选中，攻击时现形。潜行期间每秒回复 %s 最大生命值。每个战场一次。"
     % (cp("GHOST_LINE"), c("GHOST_SEC"), cp("GHOST_REGEN")),
     "生命值首次降到一半时潜行并回复生命值。"),
    ("p2eq_133", "防毒面具", 4, "+生命200/420/1000·减伤4/6/10%",
     [{"hp": 200, "dmgRed": 0.04}, {"hp": 420, "dmgRed": 0.06}, {"hp": 1000, "dmgRed": 0.10}],
     "免疫灼烧、中毒和流血。每损失 1%% 生命值，获得 %s 移动速度。" % cp("GAS_MOVE_PER_PCT"),
     "免疫灼烧、中毒和流血，生命值越低移动越快。"),
    ("p2eq_134", "威尼斯面具", 4, "+生命220/460/1050·减伤4/6/10%",
     [{"hp": 220, "dmgRed": 0.04}, {"hp": 460, "dmgRed": 0.06}, {"hp": 1050, "dmgRed": 0.10}],
     "首次受到致命伤害时倒地不死，%s 秒内生命值逐渐回复至 %s 最大生命值后继续战斗，倒地期间无法被选中。每个战场一次。"
     % (c("VEN_SEC"), cp("VEN_HEAL")),
     "首次受到致命伤害时倒地复活，继续战斗。"),
    ("p2eq_135", "黄金面具", 5, "+攻30/90/260·射程+150/200/300",
     [{"atk": 30, "_rangeAdd": 150}, {"atk": 90, "_rangeAdd": 200}, {"atk": 260, "_rangeAdd": 300}],
     "面具升空射出一道金光，%s 秒后从天而降钉住一名敌人，每秒造成（%s+目标 %s 最大生命值）真实伤害，之后每过 1 秒，每秒伤害再提高 %s，直到目标死亡。"
     "目标死亡后金光冷却 %s 秒。金光每击杀一个单位，生成 1 枚深海币，并使这件黄金面具永久获得 1 层，每层提供 %s 最大生命值和 %s 攻击力。"
     % (c("GOLD_DELAY"), c("GOLD_FLAT"), cp("GOLD_PCT"), cp("GOLD_RAMP"), c("GOLD_CD"), c("GOLD_STK_HP"), c("GOLD_STK_ATK")),
     "金光钉住一名敌人持续造成递增的真实伤害直到其死亡，击杀生成深海币并让这件面具永久成长。"),
    ("p2eq_136", "千面", 5, "+生命300/700/2000·攻30/70/300",
     [{"hp": 300, "atk": 30}, {"hp": 700, "atk": 70}, {"hp": 2000, "atk": 300}],
     "开打第 %s 秒，把一名随机敌人拽进里世界决斗，至多 %s 秒。在里世界中每秒偷取对方 %s 攻击力、护甲和魔抗，偷到的属性持续到战场结束。"
     "里世界中一方全部阵亡时决斗提前结束。" % (c("OW_AT", "OtherworldSystem"), c("OW_SEC", "OtherworldSystem"), cp("OW_STEAL", "OtherworldSystem")),
     "把一名敌人拽进里世界决斗，期间持续偷取它的属性。"),
]


def main():
    p = os.path.join(ROOT, "data/phase2-equipment.json")
    d = json.loads(open(p, "rb").read().decode("utf-8"))
    idx = {e["id"]: i for i, e in enumerate(d)}
    for (iid, name, cost, shown, stats, desc, brief) in ITEMS:
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "🎭",
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
        t[it[0]] = "面具"
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, shown, stats, desc, brief) in reversed(ITEMS):   # 倒着插在 126 后面 ⇒ 表里按 127→136 顺序
        line = '\t"%s": %s,   # 面具 · %d费 · %s(2026-11-26 方案书 20261125c)' % (iid, json.dumps(stats, ensure_ascii=False), cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_126": .*$', s, re.M)
        assert anchor, "找不到 p2eq_126 锚点"
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("写入 %d 件" % len(ITEMS))


if __name__ == "__main__":
    main()
