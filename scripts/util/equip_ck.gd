class_name EquipCk
extends RefCounted
## 同名装备多件的「份号」(copy key)纯函数 —— 零依赖(2026-11-13)。
## 用户 11-13「两件相同装备…各自生效各自的效果…统计那肯定是分开」; 方案书 docs/plans/20261113-同名装备多件各自生效.md。
## ★故意不放进 EquipStatsApply / EquipSystem: 那两个类依赖整套装备系统, 伤害 / 面板 / 统计 / 斧头这些启动时就加载的脚本
##   一引用它们, 整套装备系统就跟着在启动时被拉进来(11-13 CI 抓到: 商店说明卡的后台预加载因此落空)。

## ── 份号(copy key · 2026-11-13 用户「两件相同装备…各自生效各自的效果…统计那肯定是分开」) ──
## 同一只龟身上同名装备按装备栏顺序编号: 第 1 件 = 原 id, 第 2 件起 = 「id#2」「id#3」。
## eq_state / 装备统计都按份号分槽 ⇒ 每件各自的计时 / 计数 / 召唤物 / 统计行。
## ★第 1 件的键与原来一字不差 ⇒ 不带重复装备的对局结果不变(规则指纹守)。
## 方案书 docs/plans/20261113-同名装备多件各自生效.md。
const CK_SEP := "#"

static func ck_name(iid: String, n: int) -> String:
	return iid if n <= 1 else "%s%s%d" % [iid, CK_SEP, n]


## 条目 e 在 u 身上的份号(按 is_same 定位; 不在身上 ⇒ 原 id)。
static func ck_of(u: Dictionary, e) -> String:
	if not (e is Dictionary):
		return ""
	var iid: String = str((e as Dictionary).get("id", ""))
	var n: int = 0
	for x in u.get("equips", []):
		if x is Dictionary and str((x as Dictionary).get("id", "")) == iid:
			n += 1
			if is_same(x, e):
				return ck_name(iid, n)
	return iid


## 遍历时逐件算份号: `var seen := {}` 放循环外, 每件调一次 `ck_next(seen, iid)`。
static func ck_next(seen: Dictionary, iid: String) -> String:
	var n: int = int(seen.get(iid, 0)) + 1
	seen[iid] = n
	return ck_name(iid, n)


## 份号 → 装备 id(「p2eq_058#2」→「p2eq_058」)。
static func base_id(ck: String) -> String:
	var i: int = ck.find(CK_SEP)
	return ck if i < 0 else ck.substr(0, i)


## 某件装备在 u 身上的全部份: [[份号, 星级(1~3), 条目], ...](装备栏顺序)。
static func copies(u: Dictionary, iid: String) -> Array:
	var out: Array = []
	var n: int = 0
	for x in u.get("equips", []):
		if x is Dictionary and str((x as Dictionary).get("id", "")) == iid:
			n += 1
			out.append([ck_name(iid, n), clampi(int((x as Dictionary).get("star", 1)), 1, 3), x])
	return out
