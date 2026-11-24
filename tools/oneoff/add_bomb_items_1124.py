"""add_bomb_items_1124.py —— 炸弹羁绊 10 件 + 剑 2 费武士刀 进数据表(方案书 docs/plans/20261124f-炸弹羁绊.md §4.2 / §4.3)

  python tools/oneoff/add_bomb_items_1124.py      # 幂等: 已有同 id 就覆盖那一条

写三处: data/phase2-equipment.json(条目) · data/p2eq-types.json(羁绊归属) · scripts/gamedata/equip_stats.gd(STATS 基础属性)。
效果文案里的数一律 {C:EqBombBatch.X} 引用常量(tooltip_number_audit 对账), 逐星数组写成 a/b/c 由常量展开。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
B = "EqBombBatch"

ITEMS = [
    # id, 名, 费, 羁绊, 展示属性, STATS(1/2/3★), 效果全文, 一句话
    ("p2eq_097", "鞭炮", 1, "炸弹", "+攻8/15/25·护穿4/7/12",
     [{"atk": 8, "armorPen": 4}, {"atk": 15, "armorPen": 7}, {"atk": 25, "armorPen": 12}],
     "普攻有 {C:%s.CRACKER_CHANCE%%}%% 几率在目标周围炸开一串鞭炮，对 {C:%s.CRACKER_R} 码内的敌人造成 {C:%s.CRACKER_ATK%%}%% 攻击力的物理伤害。" % (B, B, B),
     "普攻有几率在目标周围炸开一串鞭炮，造成范围物理伤害。"),
    ("p2eq_098", "爆竹筒", 1, "炸弹", "+生命40/80/150·护甲5/9/15",
     [{"hp": 40, "def": 5}, {"hp": 80, "def": 9}, {"hp": 150, "def": 15}],
     "每 {C:%s.TUBE_IV} 秒在自己周围炸一圈：击退 {C:%s.TUBE_R} 码内的敌人，造成（{C:%s.TUBE_FLAT}+{C:%s.TUBE_ATK%%}%% 攻击力）物理伤害，并获得 {C:%s.TUBE_SHIELD} 点护盾，持续 {C:%s.TUBE_SHIELD_SEC} 秒。" % (B, B, B, B, B, B),
     "定时在自己周围炸一圈，击退身边的敌人并获得护盾。"),
    ("p2eq_099", "手雷", 2, "炸弹", "+攻12/25/45",
     [{"atk": 12}, {"atk": 25}, {"atk": 45}],
     "每 {C:%s.GRENADE_IV} 秒朝敌人最密集处扔一颗手雷，对 {C:%s.GRENADE_R} 码内的敌人造成（{C:%s.GRENADE_FLAT}+{C:%s.GRENADE_ATK%%}%% 攻击力）物理伤害，并使其护甲降低 {C:%s.GRENADE_SHRED}，持续 {C:%s.GRENADE_SHRED_SEC} 秒。" % (B, B, B, B, B, B),
     "定时朝敌人最密集处扔手雷，造成范围物理伤害并破甲。"),
    ("p2eq_100", "烟雾弹", 2, "炸弹", "+生命80/160/300·护甲8/15/25",
     [{"hp": 80, "def": 8}, {"hp": 160, "def": 15}, {"hp": 300, "def": 25}],
     "每 {C:%s.SMOKE_IV} 秒在身边放一团烟雾，持续 {C:%s.SMOKE_SEC} 秒。烟雾内的友军每 {C:%s.SMOKE_PULSE} 秒获得一次潜行：无法被选中，攻击时现形。潜行状态下的下一次攻击额外造成（{C:%s.SMOKE_TRUE_FLAT}+{C:%s.SMOKE_TRUE_ATK%%}%% 攻击力）真实伤害。" % (B, B, B, B, B),
     "定时放烟雾，烟里的友军获得潜行，潜行中的攻击额外造成真实伤害。"),
    ("p2eq_101", "粘弹", 3, "炸弹", "+攻15/28/48·护穿8/14/24",
     [{"atk": 15, "armorPen": 8}, {"atk": 28, "armorPen": 14}, {"atk": 48, "armorPen": 24}],
     "每 {C:%s.STICKY_IV} 秒朝一个敌人丢一枚粘弹，使其移动速度降低 {C:%s.STICKY_SLOW%%}%%，持续 {C:%s.STICKY_FUSE} 秒；随后粘弹爆炸，造成（{C:%s.STICKY_FLAT}+{C:%s.STICKY_ATK%%}%% 攻击力）物理伤害，并在地上铺粘液 {C:%s.GOO_SEC} 秒：粘液里的敌人移动速度降低 {C:%s.GOO_SLOW%%}%%，每 {C:%s.GOO_TICK} 秒叠加 {C:%s.GOO_POISON} 层中毒。" % (B, B, B, B, B, B, B, B, B),
     "定时丢粘弹减速敌人，爆炸后铺粘液，叠加中毒。"),
    ("p2eq_102", "地雷", 3, "炸弹", "+生命120/240/450",
     [{"hp": 120}, {"hp": 240}, {"hp": 450}],
     "在站位图中摆放 {C:%s.MINE_COUNT} 颗地雷（不摆则埋在己方前排正前方，对手看不见）。敌人踩中时爆炸，对 {C:%s.MINE_BLAST_R} 码内的敌人造成 {C:%s.MINE_DMG} 物理伤害并眩晕 {C:%s.MINE_STUN} 秒。" % (B, B, B, B),
     "在站位图里摆地雷，敌人踩中爆炸并眩晕。"),
    ("p2eq_103", "炸药桶", 4, "炸弹", "+生命200/420/1000·护甲&魔抗12/22/45",
     [{"hp": 200, "def": 12, "mr": 12}, {"hp": 420, "def": 22, "mr": 22}, {"hp": 1000, "def": 45, "mr": 45}],
     "阵亡时原地大爆炸，对 {C:%s.BARREL_R} 码内的敌人造成自身最大生命值 {C:%s.BARREL_PCT%%}%% 的物理伤害。" % (B, B),
     "阵亡时原地大爆炸，按自身最大生命值造成范围物理伤害。"),
    ("p2eq_104", "定时炸弹", 4, "炸弹", "+攻20/38/90·护穿12/20/36",
     [{"atk": 20, "armorPen": 12}, {"atk": 38, "armorPen": 20}, {"atk": 90, "armorPen": 36}],
     "每 {C:%s.TIMER_IV} 秒给最近的敌人绑一颗定时炸弹，{C:%s.TIMER_FUSE} 秒后爆炸，对 {C:%s.TIMER_R} 码内的敌人造成（{C:%s.TIMER_FLAT}+{C:%s.TIMER_ATK%%}%% 攻击力）物理伤害。每绑一颗，之后的定时炸弹伤害提高 {C:%s.TIMER_STACK%%}%%，跨战场保留，一局结束重置。" % (B, B, B, B, B, B),
     "定时给敌人绑炸弹，每绑一颗之后的伤害都更高。"),
    ("p2eq_105", "炮筒", 5, "炸弹", "+生命200/450/2500·攻20/50/250",
     [{"hp": 200, "atk": 20}, {"hp": 450, "atk": 50}, {"hp": 2500, "atk": 250}],
     "登场时在己方后方召唤一门炮筒：{C:%s.CANNON_HP} 生命值、{C:%s.CANNON_ATK} 攻击力，龟能上限 {C:%s.CANNON_EN_MAX}。炮筒攻击速度 {C:%s.CANNON_ASPD}，每次攻击朝敌人开一炮，造成 100%% 攻击力的物理伤害。龟能满时进入重炮状态：每发消耗 {C:%s.CANNON_HEAVY_COST} 龟能，炮弹沿直线飞行 {C:EqBombBatch.CANNON_HEAVY_LEN} 码，击退直线上的敌人，造成 {C:%s.CANNON_HEAVY_MULT%%}%% 攻击力的物理伤害并施加 {C:%s.CANNON_HEAVY_BLEED} 层流血；龟能耗尽时回到普通炮击。" % (B, B, B, B, B, B, B, B),
     "召唤一门高血量炮筒，龟能满时进入重炮状态，直线击退并流血。"),
    ("p2eq_106", "遥控炸弹", 5, "炸弹", "+生命200/450/2500·护甲&魔抗15/30/120",
     [{"hp": 200, "def": 15, "mr": 15}, {"hp": 450, "def": 30, "mr": 30}, {"hp": 2500, "def": 120, "mr": 120}],
     "登场时在己方前排召唤一枚遥控炸弹：{C:%s.REMOTE_HP} 生命值、{C:%s.REMOTE_RES} 护甲和魔抗。它追着一个敌人移动，不攻击，每秒损失 {C:%s.REMOTE_DECAY%%}%% 最大生命值。生命值耗尽时爆炸，对 {C:%s.REMOTE_R} 码内的敌人造成 {C:%s.REMOTE_FLAT} 物理伤害和携带者最大生命值 {C:%s.REMOTE_TRUE_PCT%%}%% 的真实伤害，并施加 {C:%s.REMOTE_BLEED} 层流血。" % (B, B, B, B, B, B, B),
     "召唤一枚追着敌人跑的遥控炸弹，生命耗尽时大范围爆炸。"),
    ("p2eq_107", "武士刀", 2, "剑", "+攻14/30/50·暴击8/12/18%",
     [{"atk": 14, "crit": 0.08}, {"atk": 30, "crit": 0.12}, {"atk": 50, "crit": 0.18}],
     "登场时召唤一名武士刀小将：{C:%s.KATANA_HP} 生命值、{C:%s.KATANA_ATK} 攻击力，龟能上限 {C:%s.KATANA_EN_MAX}，普攻造成 100%% 攻击力的物理伤害。龟能满时释放技能，四次一循环：前三次向前方 {C:%s.KATANA_WAVE_LEN} 码挥出一道剑气波，造成 {C:%s.KATANA_WAVE_MULT%%}%% 攻击力的物理伤害；第四次蓄力 {C:%s.KATANA_CHARGE} 秒并回复 {C:%s.KATANA_HEAL_TOTAL%%}%% 最大生命值，随后向前方吹出 {C:%s.KATANA_TORNADOES} 道龙卷风，造成 {C:%s.KATANA_TORNADO_MULT%%}%% 攻击力的物理伤害并击飞 {C:%s.KATANA_AIR} 秒。" % (B, B, B, B, B, B, B, B, B, B),
     "召唤一名武士刀小将，前三次技能挥剑气波，第四次蓄力回血后吹出龙卷风。"),
]


def main():
    p = os.path.join(ROOT, "data/phase2-equipment.json")
    d = json.loads(open(p, "rb").read().decode("utf-8"))
    idx = {e["id"]: i for i, e in enumerate(d)}
    for (iid, name, cost, typ, shown, stats, desc, brief) in ITEMS:
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "💣" if typ == "炸弹" else "🗡️",
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
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, typ, shown, stats, desc, brief) in reversed(ITEMS):   # 倒着插在 096 后面 ⇒ 表里按 097→107 顺序
        line = '\t"%s": %s,   # %s · %d费 · %s(2026-11-24 方案书 20261124f)' % (iid, json.dumps(stats, ensure_ascii=False).replace('": ', '": '), typ, cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_096": .*$', s, re.M)
        assert anchor, "找不到 p2eq_096 锚点"
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("写入 %d 件" % len(ITEMS))


if __name__ == "__main__":
    main()
