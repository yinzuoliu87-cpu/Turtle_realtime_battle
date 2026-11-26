"""chip_copy_1127.py —— 筹码文案按规矩重写(用户 11-27「描述按规矩来呀，不要有这种 AI 味道的描述…打完一场就损坏…肯定没有符合规矩」)
  参考: 云顶之弈中文官方数据(CommunityDragon cdragon/tft/zh_cn.json)里 84 件消耗品, 一律「效果句 + [消耗品 - 这个装备会在使用后消失。]」,
        不计羁绊的写「(但不贡献羁绊计数)」; 没有「买入后放进背包…」这种说明书步骤, 没有「一次性的 X」。
  改: 10 枚筹码效果末尾的规则句 / 9 条简介 / 图鉴筹码说明两条 / 图鉴抬头与小标题(无档位的羁绊)。
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:50], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


OLD_RULE = "消耗品：只有一星，不会升星，带进一场积分赛、闯关赛或决赛日对局后损坏。"
NEW_RULE = "消耗品：无法升星，一场积分赛、闯关赛或决赛日对局结束后消失。"
BRIEFS = [
    ("一次性的攻击力与攻击速度。", "提供攻击力与攻击速度。"),
    ("一次性的生命值与护甲。", "提供生命值与护甲。"),
    ("一次性的攻击力与暴击率。", "提供攻击力与暴击率。"),
    ("一次性的生命值、魔抗与持续回复。", "提供生命值与魔抗，并持续回复生命值。"),
    ("一次性的攻击属性，整个战场免疫控制。", "提供攻击属性，整个战场免疫控制。"),
    ("一次性的双抗与复活。", "提供护甲与魔抗，首次受到致命伤害时倒地不死。"),
    ("第 8 秒全队金色护罩并提升全队属性。", "开打第 8 秒为全队套上金色护罩并提升全队属性。"),
    ("攻击或挨打叠层，越打越强。", "攻击或受到攻击时叠层，每层提升攻击力、护甲、魔抗与生命值。"),
]

patch("data/phase2-equipment.json", [(OLD_RULE, NEW_RULE, 10)] + [(a, b, 1) for a, b in BRIEFS])
patch("docs/design/装备逐件审查进度.md", [(OLD_RULE, NEW_RULE, 10)])
patch("scripts/gamedata/phase2_types.gd", [
    ('		"筹码是特殊羁绊：没有羁绊档位，不提供羁绊效果，件数也不计入任何羁绊。",\n'
     '		"筹码是消耗品：只有一星、不能合成。买入后放进背包，装在龟身上带进一场对局，这一场打完筹码就损坏。",\n',
     '		"筹码没有羁绊加成，也不计入其他羁绊的件数。",\n'
     '		"筹码为消耗品：无法升星，一场积分赛、闯关赛或决赛日对局结束后消失。",\n', 1),
])
patch("scripts/scenes/codex/synergy_view.gd", [
    ('Lang.t("激活：%s 件") % thresh if not tiers.is_empty() else Lang.t("没有羁绊档位")',
     'Lang.t("激活：%s 件") % thresh if not tiers.is_empty() else Lang.t("无羁绊加成")', 1),
    ('	host._add_text(20, y, "羁绊效果", 17, "#58d3ff", 0.0, 0.0, true)\n',
     '	host._add_text(20, y, "羁绊效果" if not tiers.is_empty() else "说明", 17, "#58d3ff", 0.0, 0.0, true)   # 没有档位的羁绊(筹码)不写「羁绊效果」\n', 1),
])
patch("tests/verify_codex_synergy_card.gd", [
    ('		_ok("⑤ %s 详情写「没有羁绊档位」、没有「激活」" % tname, joined.find("没有羁绊档位") >= 0 and joined.find("激活") < 0, joined.substr(0, 160))\n',
     '		_ok("⑤ %s 详情写「无羁绊加成」「说明」、没有「激活」「羁绊效果」" % tname,\n'
     '			joined.find("无羁绊加成") >= 0 and joined.find("说明") >= 0 and joined.find("激活") < 0 and joined.find("羁绊效果") < 0, joined.substr(0, 160))\n', 1),
])
print("ok")
