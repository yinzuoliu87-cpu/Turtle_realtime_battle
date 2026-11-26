"""chip_codex_1127.py —— 筹码在图鉴里作为「特殊羁绊」列出(用户 11-27「筹码也是羁绊啊，只不过它是特殊的羁绊…没有羁绊的提供的羁绊效果。但是你图鉴要写啊」)
  结算不动(筹码仍是 TAG_ONLY: 不算件数、没有档位); 图鉴羁绊页列 TYPES + TAG_ONLY, 详情页对特殊羁绊不写「激活 N 件」, 写「没有羁绊档位」+ 说明。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/gamedata/phase2_types.gd", [
    ("## 只有类型标签、不成羁绊的类型(不进 TYPES ⇒ 不算件数、不亮羁绊徽章; 装备卡上照样挂标签图标)。\n"
     "##   筹码: 用户 11-26「没有羁绊档位」—— 消耗品, 不是羁绊(方案书 20261126b)。data_integrity 认这份名单。\n",
     "## 特殊羁绊: 没有档位、不提供羁绊效果(不进 TYPES ⇒ 不算件数、不亮羁绊徽章; 装备卡上照样挂标签图标), 图鉴羁绊页照样列出、写说明。\n"
     "##   筹码: 用户 11-26「没有羁绊档位」, 11-27「筹码也是羁绊啊，只不过它是特殊的羁绊…没有羁绊的提供的羁绊效果。但是你图鉴要写啊」\n"
     "##   (方案书 20261126b; 每周轮换的 16 个羁绊之一, 见 WeeklySynergy.ALL)。data_integrity / type_tables_audit 认这份名单。\n"),
    ('	"仪式": [\n		"仪式匕首的携带者每击杀一名敌人刻下一道血契。',
     '	"筹码": [\n'
     '		"筹码是特殊羁绊：没有羁绊档位，不提供羁绊效果，件数也不计入任何羁绊。",\n'
     '		"筹码是消耗品：只有一星、不能合成。买入后放进背包，装在龟身上带进一场对局，这一场打完筹码就损坏。",\n'
     '	],\n'
     '	"仪式": [\n		"仪式匕首的携带者每击杀一名敌人刻下一道血契。'),
])

patch("scripts/scenes/CodexScene.gd", [
    ('	"面具": {"color": "#e879f9", "icon": "res://assets/sprites/tags/tag-mask.png"},   # 2026-11-26 新羁绊\n',
     '	"面具": {"color": "#e879f9", "icon": "res://assets/sprites/tags/tag-mask.png"},   # 2026-11-26 新羁绊\n'
     '	"筹码": {"color": "#facc15", "icon": "res://assets/sprites/tags/tag-chip.png"},   # 2026-11-26 特殊羁绊(没有档位, 图鉴照样列; 用户 11-27)\n'),
    ('			for sname in Phase2Types.TYPES.keys():\n',
     '			for sname in Phase2Types.TYPES.keys() + Phase2Types.TAG_ONLY:   # 特殊羁绊(筹码)排在最后, 用户 11-27「图鉴要写」\n'),
])
## 计数: 图鉴页签 / 状态栏里的「羁绊 N」也算上特殊羁绊
p = os.path.join(ROOT, "scripts/scenes/CodexScene.gd")
s = open(p, "rb").read().decode("utf-8")
n = s.count("Phase2Types.TYPES.size()")
s = s.replace("Phase2Types.TYPES.size()", "(Phase2Types.TYPES.size() + Phase2Types.TAG_ONLY.size())")
open(p, "wb").write(s.encode("utf-8"))
print("codex 计数处", n)

patch("scripts/scenes/codex/synergy_view.gd", [
    ('''	## 两件事各占一行(文案规则 2: 不拿「·」把两个读数拼成一行)
	host._add_text(130, 80, Lang.t("激活：%s 件") % thresh, 16, color, 0.0, 0.5, true)
''', '''	## 两件事各占一行(文案规则 2: 不拿「·」把两个读数拼成一行)
	## 特殊羁绊(筹码, 用户 11-27): 没有档位 ⇒ 不写「激活 N 件」
	host._add_text(130, 80, Lang.t("激活：%s 件") % thresh if not tiers.is_empty() else Lang.t("没有羁绊档位"), 16, color, 0.0, 0.5, true)
'''),
])

## 审计: 特殊羁绊允许(且必须)出现在图标 / 名字 / 说明 / 图鉴样式四张表; 逐档表仍严格
patch("tools/type_tables_audit.py", [
    ('''        extra = sorted(ks[t] - base - (tag_only if t in ('TYPE_ICON', 'TYPE_NAME') else set()))
''', '''        allow = tag_only if t in TAG_TABLES else set()
        extra = sorted(ks[t] - base - allow)
        miss = sorted(set(miss) | (tag_only - ks[t] if t in TAG_TABLES else set()))   # 特殊羁绊在这几张表里也必须有(图鉴要写)
'''),
    ('''    ## 11-27: 只当标签、不是羁绊的类型(phase2_types.gd `TAG_ONLY`, 现在是「筹码」)只许出现在图标 / 名字两张标签表里,
    ##   羁绊档位 / 说明 / 图鉴表仍严格等于 TYPES。data_integrity 认同一份名单。
''', '''    ## 11-27: 特殊羁绊(phase2_types.gd `TAG_ONLY`, 现在是「筹码」: 没有档位、不提供羁绊效果)必须出现在图标 / 名字 / 说明 / 图鉴样式表里
    ##   (用户 11-27「图鉴要写」), 逐档表 TIER_DESCS 里不许有。data_integrity 认同一份名单。
    TAG_TABLES = ('TYPE_ICON', 'TYPE_NAME', 'TYPE_INTRO', 'CodexScene.gd::TYPE_STYLE')
'''),
])
print("ok")
