# -*- coding: utf-8 -*-
"""twin_radius_audit.py — 判定侧与演出侧【不同名但同值】的范围常量。

★★为什么有这个东西(2026-09-14):
  装备逐件体检到第七、第八批, **同一个形状连抓四处**:
    · 070 压舱咸鱼砖  `BRICK_SPLASH_R` = 250  ↔ 演出 `SPLASH_RANGE_PX` = 250
    · 071 炼乳罐      `CREAM_BURST_R`  = 300  ↔ 演出里**硬写** `range_m(300.0)`
    · 072 铁皮蛋糕盒  `BOX_TAUNT_PX`   = 550  ↔ 演出 `TAUNT_RANGE_PX` = 550
    · 072 铁皮蛋糕盒  `BOX_FIELD_PX`   = 300  ↔ 演出 `CAKE_FIELD_PX`  = 300

  值今天都一样, 所以画面上看不出任何问题。它是**潜伏缺陷**: 改一个不改另一个,
  环画的范围就和真打的范围对不上 —— 而这正是第五批(046~051)抓到的那一整类
  「文案写明判定半宽, 演出一件都盖不住」的成因。

★为什么现有的三条都守不住它:
  · `twin_const_audit`      —— 只查**同名**常量取值打架; 这四处是**不同的名字**。
  · `const_leftover_audit`  —— 只查**裸数字**; 这四处里有三处是**具名常量**。
  · 各批级门禁              —— 期望值写死在门禁自己那儿(这是对的), 所以改常量时
                               它会红, 但报的是"演出画错了", **指向错的地方**。
  ⇒ 少的正是这一条: **不同名 + 同值 + 一个在判定侧一个在演出侧**。

★判据(刚好卡住那个形状, 不多不少):
  演出文件(`*_vfx.gd`)里每一个"范围型"常量(名字以 _PX / _RANGE / _RADIUS / _R 结尾,
  值是数字字面量), 只要在**对应的判定文件**里找得到同值的范围型常量, 就报。
  修法只有一个: 演出侧改成读判定侧那一个(`const X := YBatch.Z`), 之后它不再是字面量,
  自然就不在扫描范围里了。
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## 演出文件 → 它对应的判定文件(同一批装备的两侧)。
## ★只配**成对**的; 配不上对的演出文件不扫 —— 宽一格会把满仓同值的常量淹进来。
PAIRS = {
    "scripts/scenes/battle/food_eq_vfx.gd": ["scripts/systems/equip/eq_food_batch.gd"],
    "scripts/scenes/battle/bow_eq_vfx.gd": ["scripts/systems/equip/eq_bow_batch.gd"],
    "scripts/scenes/battle/potion_eq_vfx.gd": ["scripts/systems/equip/eq_potion_batch.gd"],
    "scripts/scenes/battle/gun_eq_vfx.gd": ["scripts/systems/equip/eq_gun_batch.gd"],
    "scripts/scenes/battle/blade_eq_vfx.gd": ["scripts/systems/equip/eq_blade_batch.gd"],
    "scripts/scenes/battle/arcane_eq_vfx.gd": ["scripts/systems/equip/eq_arcane_batch.gd"],
    "scripts/scenes/battle/gadget_eq_vfx.gd": ["scripts/systems/equip/eq_gadget_batch.gd"],
}

## 范围型常量的名字形状。★不含 `_SEC`/`_IV`(时间)、`_PCT`(比例) —— 那些同值是巧合常态。
RANGEY = re.compile(r"^[A-Z][A-Z0-9_]*(_PX|_RANGE|_RADIUS|_R)$")
CONST = re.compile(r"^\s*const\s+([A-Z][A-Z0-9_]*)\s*:?=\s*([0-9]+(?:\.[0-9]+)?)\s*(?:#.*)?$", re.M)

## 逐条人工定性过的巧合同值。★加白名单前必须真的去读那两行。
ALLOW = {
    # (演出侧常量, 判定侧常量): 为什么它们同值是巧合
}


def consts_of(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.isfile(path):
        return {}
    txt = io.open(path, encoding="utf-8", newline="").read()
    out = {}
    for m in CONST.finditer(txt):
        if RANGEY.match(m.group(1)):
            out[m.group(1)] = float(m.group(2))
    return out


def main():
    print("=== 判定侧↔演出侧【不同名但同值】的范围常量 ===")
    nv = nj = 0
    bad = []
    for vfx, judges in sorted(PAIRS.items()):
        vc = consts_of(vfx)
        nv += len(vc)
        jc = {}
        for j in judges:
            d = consts_of(j)
            nj += len(d)
            for k, v in d.items():
                jc[k] = (v, j)
        for vk, vv in sorted(vc.items()):
            for jk, (jv, jfile) in sorted(jc.items()):
                if jk == vk or abs(jv - vv) > 1e-9:
                    continue
                if (vk, jk) in ALLOW:
                    continue
                bad.append(
                    "[FAIL] %s\n"
                    "         演出 `%s` = %g   ↔   判定 `%s` = %g  (%s)\n"
                    "       同一个数, 两个名字, 两个文件 —— 改一个不改另一个就是\n"
                    "       「环画的范围和真打的范围对不上」, 而且没有任何东西会当场红。\n"
                    "       修法: 演出侧改成读判定侧那一个, 例如 `const %s := %sBatch.%s`。"
                    % (vfx, vk, vv, jk, jv, jfile, vk, "Eq", jk))
    print("  [分母] 演出侧范围常量 %d 个 · 判定侧范围常量 %d 个 · 配对文件 %d 组"
          % (nv, nj, len(PAIRS)))
    print("  [分母] 已定性的巧合同值白名单 %d 条" % len(ALLOW))
    print("")
    if bad:
        for b in bad:
            print(b)
        print("FAILED: %d 处" % len(bad))
        return 1
    print("ALL OK — 范围常量在判定侧与演出侧只有一份")
    return 0


if __name__ == "__main__":
    sys.exit(main())
