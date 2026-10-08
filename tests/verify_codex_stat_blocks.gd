## verify_codex_stat_blocks.gd — 图鉴属性方块条(2026-10-08 用户「属性除了给出数值外需要以方块的形式横向叠加，比如100生命值一格，10攻击力一格」)
##
## ★判据量【需求】不量我的钩子: 每格单位写死在本文件(用户原话 + AskUserQuestion 拍板),
##   **不读** `CodexDetail.STAT_BLOCK_UNIT` —— 读产品常量的话, 我把单位改错, 判据跟着错, 照样绿。
## ★屏上数字从真实 Label 读(产品给数值 Label 挂了 `stat_num` 元数据, 只用来认是哪一行),
##   方块从真实 ColorRect 数(`stat_block` 元数据)。期望 = floor(屏上数字 / 单位) —— 用户选「只画满格」。
## ★还守三件事: ①方块不越出左栏(LCOL_W) ②一行方块同一个 y、从左往右不重叠 ③没有空槽底轨(9-27 被否的仪表盘长相)。
##
## 跑法: <godot> --headless --path . res://tests/verify_codex_stat_blocks.tscn --quit-after 3000
extends Node

const SCN := preload("res://scenes/Codex.tscn")

## 用户 2026-10-08 定的每格单位(攻击/双抗看过实拍后改:「攻击力按6，双抗按2」)。射程(只有小将页有)是我定的 100。
const UNIT := {"hp": 100.0, "atk": 6.0, "def": 2.0, "mr": 2.0, "move": 10.0, "aspd": 0.1, "range": 100.0}
const PET_KEYS := ["hp", "atk", "def", "mr", "move", "aspd", "range"]   # 射程 2026-10-08 起龟页也有
const BANNED_LABEL_WORDS := ["三选一", "四选一", "选一", "候选", "普攻"]
const MINION_KEYS :=["hp", "atk", "def", "mr", "aspd", "range", "move"]

var _n := 0
var _fail := 0
var _c = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 图鉴属性方块条 ===")
	_c = SCN.instantiate()
	add_child(_c)
	await _settle(10)
	_c._switch_tab("pets")
	await _settle(4)

	var n_pet := 0
	var n_min := 0
	var n_rows := 0
	var n_blocks := 0
	var wrong: PackedStringArray = []
	var missing: PackedStringArray = []
	var overflow: PackedStringArray = []
	var messy: PackedStringArray = []
	var banned: PackedStringArray = []
	var n_labels := 0
	var lcol_w: float = float(CodexDetail.LCOL_W)
	for i in range(_c._items.size()):
		var it = _c._items[i]
		if not (it is Dictionary):
			continue
		var is_min: bool = (it as Dictionary).has("_minion")
		var tag: String = str((it as Dictionary).get("_minion", (it as Dictionary).get("id", "?")))
		_c._codex_skill_detail = {}
		_c._codex_passive_view = false
		_c._codex_form_view = false
		_c._select(i)
		await _settle(3)
		if is_min:
			n_min += 1
		else:
			n_pet += 1
		## 屏上数字(按行认) + 方块(按行数)
		var nums: Dictionary = {}
		var blocks: Dictionary = {}
		for ch in _c.detail.get_children():
			## 标签上不许有「讲我们机制」的说法(用户 10-08「开局三选一是啥呢」「哪个参考游戏会这么说？」/ 10-06 不叫「普攻」)。
			##   只查 Label(标题/签/抬头), 不查技能正文 RichTextLabel —— 正文用词是另一件事。
			if ch is Label:
				for w in BANNED_LABEL_WORDS:
					if str((ch as Label).text).find(w) >= 0:
						banned.append("%s「%s」" % [tag, (ch as Label).text])
				n_labels += 1
			if ch is Label and (ch as Label).has_meta("stat_num"):
				nums[str(ch.get_meta("stat_num"))] = str((ch as Label).text)
			elif ch is ColorRect and (ch as ColorRect).has_meta("stat_block"):
				var k: String = str(ch.get_meta("stat_block"))
				if not blocks.has(k):
					blocks[k] = []
				(blocks[k] as Array).append(ch)
		for key in (MINION_KEYS if is_min else PET_KEYS):
			if not nums.has(key):
				missing.append("%s.%s" % [tag, key])
				continue
			n_rows += 1
			var disp: String = str(nums[key])
			var want: int = int(floorf(float(disp) / float(UNIT[key]) + 1e-6)) if disp.is_valid_float() else -1
			var got: Array = blocks.get(key, [])
			n_blocks += got.size()
			if got.size() != want:
				wrong.append("%s.%s 屏上 %s ⇒ 应 %d 格, 实 %d 格" % [tag, key, disp, want, got.size()])
			var prev_r: float = -1.0
			for b in got:
				var r := (b as ColorRect).get_rect()
				if r.end.x > lcol_w + 0.5:
					overflow.append("%s.%s 右缘 %.0f" % [tag, key, r.end.x])
				if r.position.x < prev_r - 0.5 or absf(r.position.y - (got[0] as ColorRect).position.y) > 0.5:
					messy.append("%s.%s" % [tag, key])
				prev_r = r.end.x
	_ok("分母: 28 只龟 + 3 个小将都打开了", n_pet == 28 and n_min == 3, "龟 %d / 小将 %d" % [n_pet, n_min])
	_ok("分母: 量到的属性行数 = 28×7 + 3×7 = 217", n_rows == 28 * 7 + 3 * 7, "%d 行 / %d 块" % [n_rows, n_blocks])
	_ok("★分母: 方块真画出来了(不是全 0 格)", n_blocks > n_rows * 3, "%d 块" % n_blocks)
	_ok("每一行都有屏上数字", missing.is_empty(), ", ".join(missing))
	_ok("★★★每行方块数 = floor(屏上数字 / 每格单位)(生命 100 · 攻击 6 · 双抗 2 · 移速 10 · 每秒攻击 0.1 · 射程 100)",
		wrong.is_empty(), ", ".join(wrong.slice(0, 6)))
	_ok("方块不越出左栏(右缘 ≤ %.0f)" % lcol_w, overflow.is_empty(), ", ".join(overflow.slice(0, 6)))
	_ok("一行方块同一高度、从左往右不重叠", messy.is_empty(), ", ".join(messy.slice(0, 6)))
	_ok("★分母: 扫过的标签数 %d(31 页)" % n_labels, n_labels > 31 * 10)
	_ok("标签上没有「三选一/四选一/候选/普攻」这类说法(对齐「被动 / 普通攻击 / 技能」)", banned.is_empty(), ", ".join(banned.slice(0, 6)))

	## 9-27 被否的长相: 空槽底轨。方块之外不许再有横贯整行的同色/暗色条 —— 只量左栏里比一格还宽的 ColorRect。
	_c._select(0)
	await _settle(3)
	var tracks := 0
	for ch in _c.detail.get_children():
		if ch is ColorRect and not (ch as ColorRect).has_meta("stat_block"):
			var r := (ch as ColorRect).get_rect()
			if r.position.x < lcol_w and r.size.x > float(CodexDetail.BLOCK_W) * 3.0 and r.size.y <= float(CodexDetail.BLOCK_H) + 0.5:
				tracks += 1
	_ok("左栏没有横贯一行的底轨条(只画满格, 不画空槽)", tracks == 0, "%d 条" % tracks)

	print("ALL PASS — 图鉴属性方块条 (%d 项)" % _n if _fail == 0 else "FAILED: %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
