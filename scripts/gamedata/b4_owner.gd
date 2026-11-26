extends RefCounted
## b4_owner.gd —— 批④装备 id → 宿主批系统 的路由表(2026-11-25 从 equip_system.gd 挪出来: 那个文件到了 3000 行上限)。
## 消费方一律读 `EquipSystem.B4_OWNER`(= 这里的 OWNER), 不在别处抄一份。
## ★新增一批: 这里加 id → 键, equip_system.gd 的 `_b4_by` / `_b4_all()` 各加一个系统(顺序 = 遍历顺序, 新批排最后)。
const OWNER := {
	"p2eq_077": "gun", "p2eq_078": "gun", "p2eq_079": "gun", "p2eq_080": "gun",
	"p2eq_081": "blade", "p2eq_082": "blade", "p2eq_083": "blade", "p2eq_084": "blade",
	"p2eq_085": "gadget", "p2eq_086": "gadget", "p2eq_087": "gadget",
	"p2eq_088": "arcane", "p2eq_089": "arcane", "p2eq_090": "arcane",
	"p2eq_091": "relic", "p2eq_094": "relic",
	"p2eq_093": "incense",
	"p2eq_097": "bomb", "p2eq_098": "bomb", "p2eq_099": "bomb", "p2eq_100": "bomb", "p2eq_101": "bomb", "p2eq_102": "bomb",
	"p2eq_103": "bomb", "p2eq_104": "bomb", "p2eq_105": "bomb", "p2eq_106": "bomb", "p2eq_107": "bomb",
	## 匕首批(2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md)
	"p2eq_108": "dagger", "p2eq_109": "dagger", "p2eq_110": "dagger", "p2eq_111": "dagger", "p2eq_112": "dagger",
	"p2eq_113": "dagger", "p2eq_114": "dagger", "p2eq_115": "dagger", "p2eq_116": "dagger",
	## 魔法书批(2026-11-25 · 方案书 docs/plans/20261125b-魔法书羁绊.md)
	"p2eq_117": "magic", "p2eq_118": "magic", "p2eq_119": "magic", "p2eq_120": "magic", "p2eq_121": "magic",
	"p2eq_122": "magic", "p2eq_123": "magic", "p2eq_124": "magic", "p2eq_125": "magic", "p2eq_126": "magic",
	## 面具批(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md)
	"p2eq_127": "mask", "p2eq_128": "mask", "p2eq_129": "mask", "p2eq_130": "mask", "p2eq_131": "mask",
	"p2eq_132": "mask", "p2eq_133": "mask", "p2eq_134": "mask", "p2eq_135": "mask", "p2eq_136": "mask",
	## 长矛批(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md)
	"p2eq_137": "spear", "p2eq_138": "spear", "p2eq_139": "spear", "p2eq_140": "spear", "p2eq_141": "spear",
	"p2eq_142": "spear", "p2eq_143": "spear", "p2eq_144": "spear", "p2eq_145": "spear", "p2eq_146": "spear",
	## 筹码(2026-11-26 · 方案书 docs/plans/20261126b-筹码.md)
	"p2eq_147": "chip", "p2eq_148": "chip", "p2eq_149": "chip", "p2eq_150": "chip", "p2eq_151": "chip",
	"p2eq_152": "chip", "p2eq_153": "chip", "p2eq_154": "chip", "p2eq_155": "chip", "p2eq_156": "chip",
}
