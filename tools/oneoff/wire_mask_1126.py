"""wire_mask_1126.py —— 面具批(127~136)接线: 路由表 / 批系统 / 伤害管线钩子 / 铸币出口 / 属性通道。一次性, 幂等检查靠 assert 计数。"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")


def ed(rel, old, new, cnt=1):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    s = raw.decode("utf-8").replace("\r\n", "\n")
    if new in s and old not in s:
        print("已接过:", rel, new[:40].replace("\n", " "))
        return
    assert s.count(old) == cnt, (rel, old[:70], s.count(old))
    s = s.replace(old, new)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(p, "wb").write(s.encode("utf-8"))


# ① 路由表
ed("scripts/gamedata/b4_owner.gd", '''	"p2eq_122": "magic", "p2eq_123": "magic", "p2eq_124": "magic", "p2eq_125": "magic", "p2eq_126": "magic",
}''', '''	"p2eq_122": "magic", "p2eq_123": "magic", "p2eq_124": "magic", "p2eq_125": "magic", "p2eq_126": "magic",
	## 面具批(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)
	"p2eq_127": "mask", "p2eq_128": "mask", "p2eq_129": "mask", "p2eq_130": "mask", "p2eq_131": "mask",
	"p2eq_132": "mask", "p2eq_133": "mask", "p2eq_134": "mask", "p2eq_135": "mask", "p2eq_136": "mask",
}''')

# ② 批系统
E = "scripts/systems/equip/equip_system.gd"
ed(E, '''var _magic_sys: EqMagicBatch     # 魔法书 10 件(117~126)·eq_magic_batch.gd(11-25 方案书 20261125b)''',
   '''var _magic_sys: EqMagicBatch     # 魔法书 10 件(117~126)·eq_magic_batch.gd(11-25 方案书 20261125b)
var _mask_sys: EqMaskBatch       # 面具 10 件(127~136)·eq_mask_batch.gd(11-26 方案书 20261125c)''')
ed(E, '''	_dagger_sys = EqDaggerBatch.new(b); _magic_sys = EqMagicBatch.new(b)''',
   '''	_dagger_sys = EqDaggerBatch.new(b); _magic_sys = EqMagicBatch.new(b); _mask_sys = EqMaskBatch.new(b)''')
ed(E, '''"dagger": _dagger_sys, "magic": _magic_sys}''', '''"dagger": _dagger_sys, "magic": _magic_sys, "mask": _mask_sys}''')
ed(E, '''	return [_gun_sys, _blade_sys, _gadget_sys, _arcane_sys, _relic_sys, _incense, _bomb_sys, _dagger_sys, _magic_sys]''',
   '''	return [_gun_sys, _blade_sys, _gadget_sys, _arcane_sys, _relic_sys, _incense, _bomb_sys, _dagger_sys, _magic_sys, _mask_sys]''')
ed(E, '''	_dagger_sys.on_any_basic(u, tgt); _magic_sys.on_any_basic(u, tgt)''',
   '''	_dagger_sys.on_any_basic(u, tgt); _magic_sys.on_any_basic(u, tgt); _mask_sys.on_any_basic(u, tgt)''')

# ③ 释放技能 → 131 小丑面具
ed("scripts/systems/equip/magicbook_synergy_system.gd", '''	battle._equip_sys._magic_sys.on_unit_cast(u, tgt, stype, cost, echo)''',
   '''	battle._equip_sys._magic_sys.on_unit_cast(u, tgt, stype, cost, echo)
	battle._equip_sys._mask_sys.on_unit_cast(u, tgt, stype, cost, echo)   # 面具批 131 小丑面具: 释放技能后嘲讽 + 护盾''')

# ④ 伤害管线: 127 物理护盾 / 134 复活(两条路都接, CLAUDE.md §4.3)
D = "scripts/scenes/battle/battle_damage.gd"
ed(D, '''	d = MagicShield.absorb(u, d, bucket == "mag")   # 魔法护盾(012): 只挡魔法, 先于普通盾; §3.3 两路都接''',
   '''	d = MagicShield.absorb(u, d, bucket == "mag")   # 魔法护盾(012): 只挡魔法, 先于普通盾; §3.3 两路都接
	d = EqMaskBatch.phys_absorb(u, d, bucket == "phy")   # 物理护盾(127 纸面具): 只挡物理, 先于普通盾; §3.3 两路都接''')
ed(D, '''	d = MagicShield.absorb(u, d, _dtv == "magic" and not raw)   # 魔法护盾(012): 只挡魔法, 先于普通盾; §3.3 两路都接''',
   '''	d = MagicShield.absorb(u, d, _dtv == "magic" and not raw)   # 魔法护盾(012): 只挡魔法, 先于普通盾; §3.3 两路都接
	d = EqMaskBatch.phys_absorb(u, d, _dtv == "physical" and not raw)   # 物理护盾(127 纸面具): 只挡物理; §3.3 两路都接''')
ed(D, '''	if u.get("_ink_sac", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:
		d = battle._equip_sys._eq_ink_sac(u, d)''', '''	if u.get("_ink_sac", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:
		d = battle._equip_sys._eq_ink_sac(u, d)
	if u.get("_ven_ready", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:
		d = battle._equip_sys._mask_sys.revive(u, d)   # 134 威尼斯面具: 倒地复活(§3.3 两路都接)''', 2)

# ⑤ 133 防毒面具: 灼烧 / 中毒 / 流血免疫(唯一入口)
ed(D, '''func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if battle._untouch_block(u, "dot_stacks"):
		return   # §UNTOUCHABLE 训龟大师(见 RealtimeBattle3DScene._is_untouchable)''', '''func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if battle._untouch_block(u, "dot_stacks"):
		return   # §UNTOUCHABLE 训龟大师(见 RealtimeBattle3DScene._is_untouchable)
	if u is Dictionary and u.get("_gas_mask", false) and battle._equip_sys._mask_sys.dot_immune(u, type):
		return   # 133 防毒面具: 免疫灼烧 / 中毒 / 流血''')

# ⑥ 128 狐狸面具: 对最大生命值更高的目标增伤
ed("scripts/scenes/RealtimeBattle3DScene.gd", '''	base *= 1.0 + float(u.get("damage_amp", 0.0))          # 攻击者增伤%''',
   '''	base *= 1.0 + float(u.get("damage_amp", 0.0))          # 攻击者增伤%
	base *= 1.0 + EqMaskBatch.fox_amp(u, tgt)              # 128 狐狸面具: 打最大生命值比自己高的目标''')

# ⑦ 135 黄金面具的深海币 → 本场铸币唯一出口
ed("scripts/systems/equip/equip_tick_system.gd", '''	return int(battle._gadget_syn.minted(side)) + int(battle._equip_tick_sys.gear_minted(side))''',
   '''	return int(battle._gadget_syn.minted(side)) + int(battle._equip_tick_sys.gear_minted(side)) + int(battle._equip_sys._mask_sys.gold_minted(side))''')

# ⑧ 属性通道 dmgRed(面具每件基础属性)
ed("scripts/systems/equip/equip_stats_apply.gd", '''	if st.has("dmgAmp"):   # 增伤''', '''	if st.has("dmgRed"):   # 减伤(2026-11-26 面具装备): 加到 damage_reduction(DamageMath.dr_mult 封顶 90%)
		u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + float(st["dmgRed"])
	if st.has("dmgAmp"):   # 增伤''')
ed("scripts/gamedata/equip_stats.gd", '''	if st.has("dmgAmp"):         out.append(["增伤", "+%d%%" % int(round(float(st["dmgAmp"]) * 100.0))])''',
   '''	if st.has("dmgAmp"):         out.append(["增伤", "+%d%%" % int(round(float(st["dmgAmp"]) * 100.0))])
	if st.has("dmgRed"):         out.append(["减伤", "+%d%%" % int(round(float(st["dmgRed"]) * 100.0))])''')

# ⑨ 图鉴颜色 / 图标
ed("scripts/scenes/CodexScene.gd", '''	"魔法书": {"color": "#60a5fa", "icon": "res://assets/sprites/tags/tag-magicbook.png"''',
   '''	"面具": {"color": "#e879f9", "icon": "res://assets/sprites/tags/tag-mask.png"},   # 2026-11-26 新羁绊
	"魔法书": {"color": "#60a5fa", "icon": "res://assets/sprites/tags/tag-magicbook.png"''')
print("ok")
