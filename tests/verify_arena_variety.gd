extends Node
## verify_arena_variety.gd — 主题物件的【类别数】与【同一张图重复多少】
##
## ★由来: 方案书 §4.4「物件类别数往参考靠 —— 同一个精灵重复出现, 看得出来」。
##   2026-10-04 改前实测(暗林): 一圈 20 来棵巨树干**全是同一张图**, 18 盏周边灯 + 3 盏场内灯**全是同一张图**,
##   站着的物件只有 5 类(草丛/叠石/沉船遗物/灯具/巨树干)。
## ★参考靶子: 咩咩地牢一屏 7~8 类(人工归类 23 张, `docs/plans/ref/20261002-咩咩启示录地图参考.md` §7.5)。
##   类别表在 `ArenaTheme.PROP_CLASS`(换成我们自己的世界观, 不照搬题材)。
## ★量的是**产品真的摆出来的精灵**(建真战斗场 + 真对局那条 `_build_map_props`), 不是数配置。
## ★「没分到类」单独一个桶: 场上出现表里没有的主题素材 ⇒ 红(memory `fb-guessed-field-name-silently-zero`)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const CLASS_MIN := 8          # 参考 7~8 类, 取上沿
const REPEAT_FROM := 6        # 一类摆了 ≥6 件才谈得上「重复看得出来」
const SHARE_MAX := 0.6        # 这样的类里, 单张图占比上限

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 主题物件的类别数与重复度 ===")
	var keep: String = AT.active
	RB.DEBUG_EDIT = true
	_ok("★分母: 至少有一版标成「已画出来」", AT.DRAWN.size() >= 1, str(AT.DRAWN))
	for th in AT.DRAWN:
		AT.active = str(th)
		var s = RB.new()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		s._world_builder._build_map_props()
		await get_tree().process_frame
		var by_class: Dictionary = {}       # 类 → {素材名: 件数}
		var unclassified: Dictionary = {}
		var total := 0
		for sp in _all_sprites(s._world):
			var tx: Texture2D = (sp as Sprite3D).texture
			if tx == null or not ("/map/themes/" in tx.resource_path) or (sp as Node).has_meta("fg_band"):
				continue
			var nm: String = tx.resource_path.get_file().get_basename()
			total += 1
			if not AT.PROP_CLASS.has(nm):
				unclassified[nm] = int(unclassified.get(nm, 0)) + 1
				continue
			var cl: String = str(AT.PROP_CLASS[nm])
			if not by_class.has(cl):
				by_class[cl] = {}
			by_class[cl][nm] = int(by_class[cl].get(nm, 0)) + 1
		_ok("[%s] ★分母: 场上站着的主题物件 ≥ 60 件" % th, total >= 60, "%d 件" % total)
		_ok("[%s] ★★「没分到类」的桶是空的(新素材必须登记进 PROP_CLASS)" % th, unclassified.is_empty(), str(unclassified))
		var summary: Array = []
		for cl in by_class:
			var n_cl := 0
			for v in by_class[cl].values():
				n_cl += int(v)
			summary.append("%s×%d(%d张图)" % [cl, n_cl, (by_class[cl] as Dictionary).size()])
		_ok("[%s] ★★一屏的物件类别 ≥ %d(参考咩咩地牢 7~8 类)" % [th, CLASS_MIN], by_class.size() >= CLASS_MIN,
			"%d 类: %s" % [by_class.size(), ", ".join(summary)])
		var bad: Array = []
		var n_big := 0
		for cl in by_class:
			var d: Dictionary = by_class[cl]
			var n_cl := 0
			var top := 0
			for v in d.values():
				n_cl += int(v)
				top = maxi(top, int(v))
			if n_cl < REPEAT_FROM:
				continue
			n_big += 1
			var share: float = float(top) / float(n_cl)
			if d.size() < 2 or share > SHARE_MAX:
				bad.append("%s: %d 件 %d 张图, 最多的一张占 %.0f%%" % [cl, n_cl, d.size(), share * 100.0])
		_ok("[%s] ★分母: 至少 3 类摆了 ≥%d 件(否则下一条没东西可量)" % [th, REPEAT_FROM], n_big >= 3, "%d 类" % n_big)
		_ok("[%s] ★★摆得多的类都不止一张图, 且单张图占比 ≤ %.0f%%(同一个精灵重复看得出来)" % [th, SHARE_MAX * 100.0],
			bad.is_empty(), str(bad))
		s.queue_free()
		await get_tree().process_frame
	AT.active = keep
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 主题物件类别与重复度" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _all_sprites(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		if c is Sprite3D:
			out.append(c)
		out.append_array(_all_sprites(c))
	return out
