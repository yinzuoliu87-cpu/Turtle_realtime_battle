"""add_dagger_items_1125.py —— 匕首羁绊 9 件新装备进数据表 + 005 双生匕首改归匕首(方案书 docs/plans/20261125-匕首羁绊.md §4.2)

  python tools/oneoff/add_dagger_items_1125.py      # 幂等: 已有同 id 就覆盖那一条

写三处: data/phase2-equipment.json(条目) · data/p2eq-types.json(羁绊归属) · scripts/gamedata/equip_stats.gd(STATS 基础属性)。
效果文案里的数一律 {C:EqDaggerBatch.X} 引用常量(tooltip_number_audit 对账); 体例照 copy_lol_style_lint / copy_style_audit /
codex_text_lint(写「攻击」不写普攻、不写码数、不用分号、百分比生命写明是谁的、不写「携带者」)。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
D = "EqDaggerBatch"

ITEMS = [
    # id, 名, 费, 羁绊(字符串或列表), 展示属性, STATS(1/2/3★), 效果全文, 一句话
    ("p2eq_108", "折叠小刀", 1, "匕首", "+攻8/15/25·暴伤5/8/12%",
     [{"atk": 8, "critDmg": 0.05}, {"atk": 15, "critDmg": 0.08}, {"atk": 25, "critDmg": 0.12}],
     "每个战场开打后，第一次攻击附带 {C:%s.FOLD_BLEED} 层流血。" % D,
     "每个战场的第一次攻击附带流血。"),
    ("p2eq_109", "柳叶飞刀", 1, "匕首", "+攻6/12/20·暴击4/6/10%",
     [{"atk": 6, "crit": 0.04}, {"atk": 12, "crit": 0.06}, {"atk": 20, "crit": 0.10}],
     "每 {C:%s.KNIFE_IV} 秒朝最远的敌人射出一把柳叶飞刀，命中途经的第一个敌人，造成（{C:%s.KNIFE_FLAT}+{C:%s.KNIFE_ATK%%}%% 攻击力）魔法伤害，可以暴击。" % (D, D, D),
     "定时朝最远的敌人射出飞刀，造成可以暴击的魔法伤害。"),
    ("p2eq_110", "苦无", 2, "匕首", "+生命80/160/300·护甲8/15/25",
     [{"hp": 80, "def": 8}, {"hp": 160, "def": 15}, {"hp": 300, "def": 25}],
     "每 {C:%s.KUNAI_IV} 秒朝随机敌人掷出 {C:%s.KUNAI_N} 枚苦无，每枚造成（{C:%s.KUNAI_FLAT}+{C:%s.KUNAI_ATK%%}%% 攻击力）魔法伤害，并为自身回复 {C:%s.KUNAI_HEAL} 点生命值。" % (D, D, D, D, D),
     "定时朝随机敌人掷出苦无，每命中一枚为自身回复生命值。"),
    ("p2eq_111", "毒牙匕首", 3, "匕首", "+生命120/240/450·魔抗10/18/30",
     [{"hp": 120, "mr": 10}, {"hp": 240, "mr": 18}, {"hp": 450, "mr": 30}],
     "造成暴击时，使目标叠加相当于自身 {C:%s.FANG_POISON_ATK%%}%% 攻击力的中毒层数。" % D,
     "暴击时按自身攻击力施加中毒。"),
    ("p2eq_112", "三棱刺", 3, "匕首", "+攻15/28/48·暴击6/10/16%",
     [{"atk": 15, "crit": 0.06}, {"atk": 28, "crit": 0.10}, {"atk": 48, "crit": 0.16}],
     "攻击和技能无视目标 {C:%s.PIERCE_PCT%%}%% 护甲。" % D,
     "攻击和技能无视目标一部分护甲。"),
    ("p2eq_113", "弯匕", 4, "匕首", "+生命200/420/1000·攻20/38/90",
     [{"hp": 200, "atk": 20}, {"hp": 420, "atk": 38}, {"hp": 1000, "atk": 90}],
     "击杀敌人后 {C:%s.KRIS_SEC} 秒内攻击速度提高 {C:%s.KRIS_ASPD%%}%%。" % (D, D),
     "击杀敌人后短时间内提高攻击速度。"),
    ("p2eq_114", "仪式匕首", 4, ["匕首", "仪式"], "+生命200/420/1000·攻15/30/70",
     [{"hp": 200, "atk": 15}, {"hp": 420, "atk": 30}, {"hp": 1000, "atk": 70}],
     "攻击和技能直接击杀生命值低于其 {C:%s.RITUAL_EXEC%%}%% 最大生命值的敌人。每击杀一名敌人刻下 1 道【血契】，整个大轮累计，至多 {C:%s.RITUAL_CAP} 道。每道血契使自身攻击力提高 {C:%s.RITUAL_ATK}、护甲穿透提高 {C:%s.RITUAL_PEN}。" % (D, D, D, D),
     "斩杀低血量的敌人，每次击杀刻下血契，整个大轮持续变强。"),
    ("p2eq_115", "暗影匕首", 5, "匕首", "+攻40/90/400·暴伤20/35/80%",
     [{"atk": 40, "critDmg": 0.20}, {"atk": 90, "critDmg": 0.35}, {"atk": 400, "critDmg": 0.80}],
     "登场时召唤一名暗影忍者：{C:%s.NINJA_HP} 生命值、{C:%s.NINJA_ATK} 攻击力、{C:%s.NINJA_RES} 护甲和魔抗、{C:%s.NINJA_CRIT%%}%% 暴击率，登场时隐身，攻击时现形。"
     "龟能满时释放【影袭】：化为黑烟，闪到生命值比例最低的敌人身后背刺，造成 {C:%s.NINJA_STRIKE_MULT%%}%% 攻击力的物理伤害，必定暴击，随后隐身 {C:%s.NINJA_RESTEALTH} 秒。"
     "暗影忍者的生命值首次低于其 {C:%s.NINJA_CLONE_HP_PCT%%}%% 最大生命值时，分出一名影子忍者，持续 {C:%s.NINJA_CLONE_SEC} 秒，拥有其 {C:%s.NINJA_CLONE_STAT%%}%% 最大生命值与攻击力。"
     "影子在场时，每次【影袭】两名忍者各朝目标掷出一枚手里剑，对路径上的敌人造成（{C:%s.SHURIKEN_FLAT}+{C:%s.SHURIKEN_ATK%%}%% 攻击力）魔法伤害。" % ((D,) * 11),
     "召唤暗影忍者，影袭背刺生命值最低的敌人，半血时分出影子一起掷出手里剑。"),
    ("p2eq_116", "黑曜石匕首", 5, "匕首", "+攻40/90/400·暴击15/25/50%",
     [{"atk": 40, "crit": 0.15}, {"atk": 90, "crit": 0.25}, {"atk": 400, "crit": 0.50}],
     "造成暴击时，在目标身上插入一把黑曜石匕首，匕首不会自行拔出。目标身上全部匕首一起拔出的伤害足以击杀目标时，立即全部拔出：每把造成（{C:%s.OBS_FLAT}+{C:%s.OBS_ATK%%}%% 攻击力+目标 {C:%s.OBS_MAXHP%%}%% 最大生命值）物理伤害，并为自身回复 {C:%s.OBS_HEAL} 点生命值。" % (D, D, D, D),
     "暴击时把黑曜石匕首插进敌人身上，足以致命时一起拔出并回复生命值。"),
]


def main():
    p = os.path.join(ROOT, "data/phase2-equipment.json")
    d = json.loads(open(p, "rb").read().decode("utf-8"))
    idx = {e["id"]: i for i, e in enumerate(d)}
    for (iid, name, cost, typ, shown, stats, desc, brief) in ITEMS:
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "🗡️",
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
        t[it[0]] = it[3]
    t["p2eq_005"] = "匕首"   # 双生匕首改归匕首(用户 11-24「双生匕首我们现在归类为匕首了」, 随匕首上线同版改)
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, typ, shown, stats, desc, brief) in reversed(ITEMS):   # 倒着插在 107 后面 ⇒ 表里按 108→116 顺序
        tname = typ if isinstance(typ, str) else "+".join(typ)
        line = '\t"%s": %s,   # %s · %d费 · %s(2026-11-25 方案书 20261125)' % (iid, json.dumps(stats, ensure_ascii=False), tname, cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_107": .*$', s, re.M)
        assert anchor, "找不到 p2eq_107 锚点"
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("写入 %d 件 + 005 改归匕首" % len(ITEMS))


if __name__ == "__main__":
    main()
