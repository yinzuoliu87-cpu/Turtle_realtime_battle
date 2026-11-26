"""batch_copy_fix_1127.py —— 面具 / 长矛 / 筹码批预检第一轮: 文案按体例审计器改(copy_lol_style_lint / copy_style_audit)
  禁用词: 挨打 → 受到伤害 / 对方 → 敌方 / 改为 → 转而(LoL 中文用词)
  叠满 / 攒满 台账只减不增(main 上是 0) ⇒ 改成「达到上限」
  「X% 最大生命值」写明是谁的(自身)
"""
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


J = [
    ("登场获得物理护盾，挨打时按护甲朝攻击者掷出纸刃。", "登场获得物理护盾，受到伤害时按护甲朝攻击者掷出纸刃。"),
    ("每秒偷取对方 {C:OtherworldSystem.OW_STEAL%}%", "每秒偷取敌方 {C:OtherworldSystem.OW_STEAL%}%"),
    ("挨打攒战意，跃起砸地，之后攻击带横扫。", "受到伤害时积攒战意，跃起砸地，之后攻击附带横扫。"),
    ("移动时积攒冲势，攒满后下一次攻击", "移动时积攒冲势，冲势达到上限后，下一次攻击"),
    ("受到伤害时积攒战意，攒满后原地蓄力", "受到伤害时积攒战意，战意达到上限后原地蓄力"),
    ("攻击为目标叠加圣痕，叠满 {C:EqSpearBatch.HOLY_STACKS} 层时引爆", "攻击为目标叠加圣痕，达到 {C:EqSpearBatch.HOLY_STACKS} 层时引爆"),
    ("攻击叠圣痕，叠满引爆并回复生命值。", "攻击叠加圣痕，达到上限时引爆并回复生命值。"),
    ("{C:EqChipBatch.GREY_HP} 最大生命值。叠满后额外获得", "{C:EqChipBatch.GREY_HP} 最大生命值。层数达到上限后额外获得"),
    ("这段时间内每秒回复 {C:EqMaskBatch.GHOST_REGEN%}% 最大生命值。", "这段时间内每秒回复自身 {C:EqMaskBatch.GHOST_REGEN%}% 最大生命值。"),
    ("秒内生命值逐渐回复至 {C:EqMaskBatch.VEN_HEAL%}% 最大生命值后继续战斗", "秒内生命值逐渐回复至自身 {C:EqMaskBatch.VEN_HEAL%}% 最大生命值后继续战斗"),
    ("每秒回复 {C:EqChipBatch.GREEN_REGEN%}% 最大生命值。", "每秒回复自身 {C:EqChipBatch.GREEN_REGEN%}% 最大生命值。"),
    ("秒内回复至 {C:EqChipBatch.BROWN_HEAL%}% 最大生命值后继续战斗", "秒内回复至自身 {C:EqChipBatch.BROWN_HEAL%}% 最大生命值后继续战斗"),
]
patch("data/phase2-equipment.json", J)
## 审查表镜像同一批效果文案(只有 effectDesc1 进表)
p = os.path.join(ROOT, "docs/design/装备逐件审查进度.md")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
n = 0
for a, b in J:
    if s.count(a) == 1:
        s = s.replace(a, b)
        n += 1
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("审查表同步", n, "处")
patch("scripts/gamedata/phase2_types.gd", [
    ("每第 {C:SpearSynergySystem.THROW_EVERY} 次攻击改为把长矛掷向最远的敌人", "每第 {C:SpearSynergySystem.THROW_EVERY} 次攻击转而把长矛掷向最远的敌人"),
])
print("ok")
