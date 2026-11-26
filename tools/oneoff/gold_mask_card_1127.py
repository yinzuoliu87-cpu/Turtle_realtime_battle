"""gold_mask_card_1127.py —— 背包卡上显示 135 黄金面具这一件攒下的层数(11-27); 一次性, 原行尾二进制读写。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:60], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


patch("scripts/scenes/InventoryScene.gd", [(
    '\t\tbody += "\\n[color=#ff6b7a]%s[/color]" % EqDaggerBatch.progress_text(int(GameState.ritual_marks))\n',
    '\t\tbody += "\\n[color=#ff6b7a]%s[/color]" % EqDaggerBatch.progress_text(int(GameState.ritual_marks))\n'
    '\telif eid == "p2eq_135":   # 135 黄金面具: 金光击杀攒的层数记在这一件上(跨对局保留, 11-27)\n'
    '\t\tbody += "\\n[color=#ffd93d]%s[/color]" % EqMaskBatch.gold_progress_text(GameState.eq_gm(it))\n')])

patch("scripts/systems/equip/eq_mask_batch.gd", [(
    "## 本场层数账的键: 一方 + 龟 + 份号(换路后同一只龟、同一件拿到同一个键)",
    "## 背包卡上的一行: 这一件攒下的层数(局外也看得到, 11-27)\n"
    "static func gold_progress_text(stk: int) -> String:\n"
    "\treturn Lang.t(\"金光层数 %d（每层 +%d 生命值、+%d 攻击力）\") % [maxi(0, stk), int(GOLD_STK_HP), int(GOLD_STK_ATK)]\n\n\n"
    "## 本场层数账的键: 一方 + 龟 + 份号(换路后同一只龟、同一件拿到同一个键)")])

p = os.path.join(ROOT, "locale", "en.po")
raw = open(p, "rb").read()
nl = b"\r\n" if b"\r\n" in raw else b"\n"
if "金光层数 %d".encode("utf-8") not in raw:
    add = ('msgid "金光层数 %d（每层 +%d 生命值、+%d 攻击力）"\nmsgstr "Gold stacks %d (each +%d HP, +%d Attack)"\n').encode("utf-8").replace(b"\n", nl)
    open(p, "wb").write(raw.rstrip() + nl + nl + add)
    print("en.po +1")
