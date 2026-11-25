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
}
