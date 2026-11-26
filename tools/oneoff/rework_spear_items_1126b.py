"""rework_spear_items_1126b.py —— 长矛 137~145 按用户 11-26 夜的改法重写数据(方案书 docs/plans/20261126-长矛羁绊.md 第 7 节)

用户原话要点: 「这装备不要再提供龟能回复速率了，因为这个是羁绊的提供的属性…装备提供的基础属性你不能是同样的」;
竹矛 / 鱼叉 / 标枪 / 骑枪 / 长戟 / 盾矛 / 方天画戟 / 投矛器 机制重写; 永恒之枪 / 圣枪待重新设计(这里只换掉 145 的龟能回复)。

写: data/phase2-equipment.json(baseStats1 / effectDesc1 / effectBrief) · scripts/gamedata/equip_stats.gd(STATS 那一行)。
文案体例同面具批(写「攻击」不写普攻、不写码数、不用分号、百分比生命写明是谁的、不写「携带者」)。幂等。

    python tools/oneoff/rework_spear_items_1126b.py
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
E = "EqSpearBatch"


def c(n):
    return "{C:%s.%s}" % (E, n)


def cp(n):
    return "{C:%s.%s%%}%%" % (E, n)


## id → (展示属性, STATS 三星, 效果, 一句话; None = 不改)
ITEMS = {
    "p2eq_137": ("+攻6/12/20·护甲穿透3/5/8",
                 [{"atk": 6, "armorPen": 3}, {"atk": 12, "armorPen": 5}, {"atk": 20, "armorPen": 8}],
                 "每第 %s 次攻击，朝最远的敌人方向从地里刺出一道竹刺浪，对路径上的每名敌人造成 %s 攻击力的物理伤害。" % (c("BAMBOO_EVERY"), cp("BAMBOO_PCT")),
                 "每第三次攻击刺出一道竹刺浪。"),
    "p2eq_138": ("+生命80/160/300·法术穿透3/5/8",
                 [{"hp": 80, "magicPen": 3}, {"hp": 160, "magicPen": 5}, {"hp": 300, "magicPen": 8}],
                 "每 %s 秒朝造成伤害最多的敌人射出鱼叉，造成 %s 魔法伤害并眩晕 %s 秒，眩晕期间每 %s 秒把它朝自己拉近一段距离。"
                 % (c("HARPOON_IV"), c("HARPOON_DMG"), c("HARPOON_STUN"), c("HARPOON_PULL_IV")),
                 "定时叉住伤害最高的敌人拉过来。"),
    "p2eq_139": ("+攻14/30/50·暴击4/6/10%",
                 [{"atk": 14, "crit": 0.04}, {"atk": 30, "crit": 0.06}, {"atk": 50, "crit": 0.10}],
                 "每 %s 秒朝最远的敌人掷出一根标枪，造成 %s 攻击力的物理伤害，并施加 %s 攻击力的流血层数。"
                 % (c("JAV_IV"), cp("JAV_PCT"), cp("JAV_BLEED_PCT")),
                 "定时朝最远的敌人掷标枪，附带流血。"),
    "p2eq_140": ("+生命100/200/380·移速4/6/10%",
                 [{"hp": 100, "_mspdPct": 4}, {"hp": 200, "_mspdPct": 6}, {"hp": 380, "_mspdPct": 10}],
                 "移动时积攒冲势，攒满后下一次攻击消耗全部冲势，造成 %s 攻击力的物理伤害，将目标击飞并眩晕 %s 秒，自己回复 %s 点龟能。"
                 % (cp("LANCE_PCT"), c("LANCE_STUN"), c("LANCE_EN")),
                 "跑起来攒冲势，下一击击飞敌人。"),
    "p2eq_141": ("+攻15/28/48·射程20/40/60",
                 [{"atk": 15, "_rangeAdd": 20}, {"atk": 28, "_rangeAdd": 40}, {"atk": 48, "_rangeAdd": 60}],
                 "每隔一次攻击间隔朝最近的敌人横扫前方扇形，半径等于自身攻击射程，近战时半径额外增加。对扇形内每名敌人造成 %s 攻击力的物理伤害。"
                 % cp("HALB_PCT"),
                 "按攻击节奏横扫前方一片。"),
    "p2eq_142": (None, None,
                 "每 %s 秒举盾 %s 秒，期间受到的每段攻击和技能伤害降低 %s 点，并把这些伤害存起来。放下盾时获得存下伤害 %s 的护盾，持续 %s 秒，并朝前方推出一道冲击波，路径上的敌人分摊存下伤害 %s 的魔法伤害。"
                 % (c("SHSP_IV"), c("SHSP_SEC"), c("SHSP_FLAT"), cp("SHSP_SHIELD_PCT"), c("SHSP_SHIELD_SEC"), cp("SHSP_WAVE_PCT")),
                 "定时举盾存伤害，放盾时化成护盾和冲击波。"),
    "p2eq_143": (None, None,
                 "受到伤害时积攒战意，攒满后原地蓄力高高跃起，将戟砸入地面，对周围大范围的敌人造成 %s 攻击力的物理伤害并击飞。之后 %s 秒内每次攻击额外绕身横扫一圈，对周围的敌人造成 %s 攻击力的物理伤害，并回复 %s 生命值。"
                 % (cp("FTJ_SLAM_PCT"), c("FTJ_BUFF_SEC"), cp("FTJ_PCT"), c("FTJ_HEAL")),
                 "挨打攒战意，跃起砸地，之后攻击带横扫。"),
    "p2eq_144": ("+攻25/45/110·攻速8/12/18%",
                 [{"atk": 25, "_aspdPct": 8}, {"atk": 45, "_aspdPct": 12}, {"atk": 110, "_aspdPct": 18}],
                 "每 %s 秒朝敌人最密集的位置投出 %s 根矛，矛雨陆续落在那一圈里，每根对落点附近的敌人造成 %s 攻击力的物理伤害。"
                 % (c("ATL_IV"), c("ATL_N"), cp("ATL_PCT")),
                 "定时朝敌人扎堆处落一场矛雨。"),
    "p2eq_145": ("+攻40/90/400·护甲穿透8/12/20",
                 [{"atk": 40, "armorPen": 8}, {"atk": 90, "armorPen": 12}, {"atk": 400, "armorPen": 20}],
                 None, None),
}


def main():
    p = os.path.join(ROOT, "data", "phase2-equipment.json")
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    txt = raw.decode("utf-8")
    data = json.loads(txt)
    lst = data if isinstance(data, list) else data.get("equipment", data)
    n = 0
    for e in lst:
        it = ITEMS.get(e.get("id"))
        if it is None:
            continue
        bs, _st, eff, brief = it
        if bs is not None:
            e["baseStats1"] = bs
        if eff is not None:
            e["effectDesc1"] = eff
        if brief is not None:
            e["effectBrief"] = brief
        n += 1
    out = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if crlf:
        out = out.replace("\n", "\r\n")
    ## 只在内容真的变了时写(保持原文件缩进风格: 先比对一次原样重写是否逐字节相同)
    same_shape = json.dumps(json.loads(txt), ensure_ascii=False, indent=2) + "\n"
    if crlf:
        same_shape = same_shape.replace("\n", "\r\n")
    assert same_shape.encode("utf-8") == raw, "json 原文件不是 indent=2 的格式, 改用逐条替换"
    open(p, "wb").write(out.encode("utf-8"))
    print("json 改了", n, "件")

    q = os.path.join(ROOT, "scripts", "gamedata", "equip_stats.gd")
    rawq = open(q, "rb").read()
    crq = b"\r\n" in rawq
    s = rawq.decode("utf-8").replace("\r\n", "\n")
    for eid, it in ITEMS.items():
        st = it[1]
        if st is None:
            continue
        m = re.search(r'^\t"%s": \[.*?\],(.*)$' % eid, s, re.M)
        assert m, eid
        body = ", ".join("{" + ", ".join('"%s": %s' % (k, v) for k, v in d.items()) + "}" for d in st)
        s = s[:m.start()] + '\t"%s": [%s],%s' % (eid, body, m.group(1)) + s[m.end():]
    if crq:
        s = s.replace("\n", "\r\n")
    open(q, "wb").write(s.encode("utf-8"))
    print("STATS 改了", sum(1 for v in ITEMS.values() if v[1] is not None), "件")


if __name__ == "__main__":
    main()
