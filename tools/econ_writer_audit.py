"""局外经济字段的直接写入审计(方案书 docs/plans/20261106-装备与深海币服务器记账.md §4.3 / §6)。

用户 2026-11-06「装备要改成伏击机装(= 服务器记账)了，这个要做。」—— 服务器按经济流水重放出权威状态,
前提是**每一笔**改深海币 / 背包 / 身上装备 / 货架 / 卡池 / 大轮等级 / 统领 / 小木斧 / 糖果罐 / 宝箱 / 香火石的地方
都走 `EconLedger`(scripts/gamedata/econ_ledger.gd + econ_inv.gd)。漏一处 = 本机与重放对不上 = 好人被拒。

判据一(写入): 扫 autoload/ 与 scripts/ 里对这些字段的写入(赋值 / 自增 / 容器改动), 按「文件::函数::字段」归类:
  ① 记账口本身 / 记账口才调的 GameState 辅助函数(HELPERS, 见判据二)
  ② 永久放行(ALLOW, 每条写理由): 读档 / 清档 / 换周、沙盒(教程)、调试注入、截图工具、战斗工作副本
  ③ 存量(STOCK): S1 时还没迁走的直接写入, 只减不增 —— S2(2026-11-06)已清零, 表留着空
  ④ 其余 = 新增的直接写入 ⇒ 红
判据二(调用点): HELPERS 里那些 GameState 函数会改经济字段, 它们**只许**在记账口里、别的 HELPERS 里、或 ALLOW 的函数里被调。
  有人在界面 / 战斗 / 结算里直接调 `gs.add_season_xp(..)` ⇒ 红(那一笔没进流水)。
静态扫描看不见别名写法(`var b = gs.persistent_bench; b.append(..)`)⇒ 运行时还有哨兵 `EconLedger.check`
  (门禁 verify_econ_paths ③ 证明它会响)。

只读, 可反复跑:  python tools/econ_writer_audit.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FIELDS = [
	"meta_deepsea_coins", "meta_shop_offer", "meta_shop_locked",
	"equip_pool", "persistent_bench", "persistent_equipped",
	"season_level", "season_xp", "season_leaders",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "axe_syn_matches",
	"candy_jar_count", "candy_jar_broken", "candy_temp_levels",
	"chest_treasure_value", "chest_treasures_won", "incense_marks", "incense_charge",
]
## 不在表里的(有意): axe_evo_pending(进化演出排队, 不是资产)、meta_shop_battles(自动换货的戳)、
##   dual_lineup(阵型 / 前后排 / 站位是选择; 小将身上的装备与临时等级由哨兵按资产指纹盯)。
MUT = (r"(\s*(\+=|-=|\*=|=(?!=))|\.(append|push_back|push_front|erase|remove_at|clear|insert|assign|merge|resize|fill|sort|pop_back|pop_front)\("
	r"|\[[^\]]+\]\s*(\+=|-=|=(?!=)))")
RX = {f: re.compile(r"(?<![A-Za-z0-9_\"'])" + re.escape(f) + MUT) for f in FIELDS}
FUNC = re.compile(r"^(static\s+)?func\s+([A-Za-z0-9_]+)")

LEDGER = ("scripts/gamedata/econ_ledger.gd", "scripts/gamedata/econ_inv.gd")

## 判据二: 记账口才调的 GameState 辅助函数(函数体里改经济字段; 调用点受限)
HELPERS = {
	"add_season_xp", "auto_merge_all", "sync_synergy_grants", "pool_take", "pool_give_back",
	"axe_add_exp", "axe_on_match_end", "axe_pick_final", "candy_jar_add", "candy_jar_open_seeded",
	"apply_temp_leveler", "apply_temp_leveler_minion", "consume_temp_leveler", "migrate_equip_caps",
}
CALL_RX = re.compile(r"\b(" + "|".join(sorted(HELPERS)) + r")\(")

## ② 永久放行: (文件, 函数) 或 (文件, 函数, 字段); 函数为 "*" = 整个文件
ALLOW = {
	("autoload/GameState.gd", "_apply_save_dict"): "读档(之后 EconLedger.rebase = 新起点)",
	("autoload/GameState.gd", "reset_save"): "清档(同上)",
	("autoload/GameState.gd", "start_new_season"): "换周清零(本周开局 = 服务器重放的起点)",
	("autoload/GameState.gd", "ensure_equip_pool"): "卡池懒补齐: 资产指纹本来就按「补齐之后」算(EconLedger._eff_pool), 落地不改资产",
	("autoload/tutorial_director.gd", "*"): "教程沙盒(tutorial_active 期间哨兵静音, 退出整份还原)",
	("autoload/shot_diff.gd", "*"): "截图工具",
	("scripts/scenes/ShopScene.gd", "_shop_selfshot"): "截图工具(SHOT_COINS)",
	("scripts/scenes/TeamSelectScene.gd", "_on_start", "season_leaders"): "教程分支(沙盒); 正式锁统领走 econ leaders",
	("scripts/scenes/InventoryScene.gd", "_inject_demo_inventory"): "INV_DEMO 调试注入(环境变量开关, 不存盘)",
	("scripts/scenes/InventoryScene.gd", "_ready", "season_leaders"): "PH_DEMO 调试(环境变量开关, 不存盘)",
	("scripts/scenes/RealtimeBattle3DScene.gd", "_stress_pre"): "STRESS 卡死猎手调试(环境变量开关)",
	("scripts/systems/skills/chest_system.gd", "*"): "战斗工作副本: 宝箱财宝值 / 战利品当场写存档(换路要读回来, 对局规则); "
		"哨兵发现变了就补一条 prog(终值)",
	("scripts/systems/equip/incense_stone_system.gd", "*"): "战斗工作副本: 香火刻痕 / 充能(同上)",
	("scripts/systems/replay/abandoned_match.gd", "_apply"): "中途退出补打: 把开局那一刻的状态摆回去(正常与当前逐字节相同; 真不同由哨兵判)",
}

## ③ 存量: S1(2026-11-06)时还没迁进记账口的直接写入, 只减不增。S2(同日)已清零。
STOCK = """
""".split()

FILES = ("autoload", "scripts")


def _allowed(rel: str, fn: str, field: str = "") -> bool:
	if rel in LEDGER:
		return True
	if (rel, "*") in ALLOW or (rel, fn) in ALLOW:
		return True
	return field != "" and (rel, fn, field) in ALLOW


def scan() -> tuple:
	"""({文件::函数::字段: [行号...]}, {文件::函数::辅助函数: [行号...]})"""
	hits: dict = {}
	calls: dict = {}
	for base in FILES:
		for dp, _dn, fns in os.walk(os.path.join(ROOT, base)):
			for n in fns:
				if not n.endswith(".gd"):
					continue
				p = os.path.join(dp, n)
				rel = os.path.relpath(p, ROOT).replace("\\", "/")
				fn = "<顶层>"
				with open(p, encoding="utf-8", errors="replace") as fh:
					for i, line in enumerate(fh, 1):
						m = FUNC.match(line)
						if m:
							fn = m.group(2)
							continue
						code = line.split("#", 1)[0]
						if not code.strip():
							continue
						for f in FIELDS:
							if RX[f].search(code):
								hits.setdefault("%s::%s::%s" % (rel, fn, f), []).append(i)
						for cm in CALL_RX.finditer(code):
							calls.setdefault("%s::%s::%s" % (rel, fn, cm.group(1)), []).append(i)
	return hits, calls


def main() -> int:
	try:
		sys.stdout.reconfigure(encoding="utf-8")
	except Exception:
		pass
	hits, calls = scan()
	ledger, helper, allowed, stock_live, new = [], [], [], [], []
	for k in sorted(hits):
		rel, fn, f = k.split("::")
		if rel in LEDGER:
			ledger.append(k)
		elif rel == "autoload/GameState.gd" and fn in HELPERS:
			helper.append(k)
		elif _allowed(rel, fn, f):
			allowed.append(k)
		elif k in STOCK:
			stock_live.append(k)
		else:
			new.append(k)
	gone = [k for k in STOCK if k not in hits]
	bad_calls = []
	for k in sorted(calls):
		rel, fn, _h = k.split("::")
		if _allowed(rel, fn) or (rel == "autoload/GameState.gd" and fn in HELPERS):
			continue
		bad_calls.append(k)
	n_calls = sum(len(v) for v in calls.values())
	print("  [分母] 经济字段写入 %d 组(文件::函数::字段): 记账口 %d · 记账口辅助函数 %d · 永久放行 %d · 存量 %d / 表里 %d · 新增 %d"
		% (len(hits), len(ledger), len(helper), len(allowed), len(stock_live), len(STOCK), len(new)))
	print("  [分母] 辅助函数(%d 个)调用点 %d 处 / %d 组, 记账口外 %d 组" % (len(HELPERS), n_calls, len(calls), len(bad_calls)))
	bad = 0
	if len(ledger) == 0 or len(helper) == 0 or n_calls == 0:
		bad += 1
		print("[FAIL] 分母为 0(记账口 %d / 辅助函数 %d / 调用点 %d)—— 扫描器没扫到东西, 不是通过" % (len(ledger), len(helper), n_calls))
	if new:
		bad += 1
		print("[FAIL] 新增了不走记账口(EconLedger)的经济字段写入 %d 组 —— 服务器重放看不到它, 本机与重放必然对不上:" % len(new))
		for k in new:
			print("   %s  (行 %s)" % (k, ",".join(str(x) for x in hits[k])))
		print("  ⇒ 改成 GameState.econ({...}); 真不是玩家的经济操作(读档/沙盒/工具)才进 ALLOW 并写理由。")
	if bad_calls:
		bad += 1
		print("[FAIL] 记账口辅助函数在记账口外被调了 %d 组 —— 那一笔改了资产却没进流水:" % len(bad_calls))
		for k in bad_calls:
			print("   %s  (行 %s)" % (k, ",".join(str(x) for x in calls[k])))
		print("  ⇒ 改成 GameState.econ({...}) 的某个操作(econ_ledger.gd apply 里没有合适的就加一个)。")
	if gone:
		bad += 1
		print("[FAIL] 存量表里登记了、代码里已经没有的 %d 组(迁走了就把表里那行删掉, 存量数才是真的):" % len(gone))
		for k in gone:
			print("   " + k)
	if bad:
		print("FAILED: %d 处" % bad)
		return 1
	print("ALL OK — 经济字段的写入全在记账口 / 永久放行里(存量 %d 组), 辅助函数没有在记账口外被调" % len(stock_live))
	return 0


if __name__ == "__main__":
	sys.exit(main())
