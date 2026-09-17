extends Node
## verify_week_season.gd — 大轮赛制 v2 周赛制的存档字段(A2)
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## A2 给 `GameState` 加了 8 个字段，每个都要走**五处**：
##   ① 声明 ② 保存 ③ 载入 ④ `reset_save` ⑤ `start_new_season`
## **漏任何一处都不会报错**，只会在切轮或重启之后悄悄漂 —— 这正是它难自己发现的原因：
##   · 漏「保存」或「载入」⇒ 重启后清零，玩家以为进度丢了
##   · 漏 `start_new_season` ⇒ 新的一周带着上周的配额/战绩开局
##   · 漏 `reset_save` ⇒ 清档清不干净
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★**八个字段逐个验，不抽查** —— 缺口的形状就是「某一个字段漏了某一处」，
##   抽查三个通过不能说明第四个没漏。
## ★① 用**真存档往返**（产品自己的 `save()` → `_load()`，真过一次文件），不是自己拼字典读回来 ——
##   自己拼就绕开了产品的保存/载入代码，等于没验（同族 memory `fb-gate-subject-never-constructed`）。
##   ⚠ `save()` 在 `test_mode` 下直接 return，所以往返这一段必须**临时把 test_mode 关掉**。
##   为此本门禁**先把原存档整份备份、跑完按字节还原**（没有就删掉新建的那份）——
##   这样即使有人不带隔离 APPDATA 手跑，也不会动到玩家真存档
##   （memory `fb-debug-stage-writes-real-save`：台子写真存档是踩过的）。
## ★② 塞的值**全部非零且各不相同**，否则「切轮后 == 0」在字段本来就是 0 时是恒真式。
## ★①**确实会写一次盘**（否则 `save()`→`_load()` 走不通），靠「备份→还原」兜底；②③ 纯内存。

const FIELDS_INT := ["ranked_used", "season_sweeps", "backfill_paid",
	"week_anchor_ts", "gauntlet_wins", "gauntlet_losses"]

var _n := 0
var _fail := 0
var _gs = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	_gs.test_mode = true
	print("=== 周赛制存档字段(A2) ===")

	_t_roundtrip()
	_t_new_season_resets()
	_t_reset_save_clears()

	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 周赛制存档字段" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 塞一组【非零且互不相同】的值 —— 相同值会让"往返保值"在错位赋值时也能蒙对。
func _fill_distinct() -> Dictionary:
	var want := {}
	var v := 11
	for f in FIELDS_INT:
		_gs.set(f, v)
		want[f] = v
		v += 7
	_gs.week_phase = "gauntlet"
	want["week_phase"] = "gauntlet"
	_gs.promoted = true
	want["promoted"] = true
	return want


# ─────────────────────────────────────────────────────────────
# ① 存档往返: 存进去再读回来, 八个字段一个都不许变
#    —— 守「漏了保存」或「漏了载入」
# ─────────────────────────────────────────────────────────────
func _t_roundtrip() -> void:
	print("── ① 存档往返保值(真过一次文件) ──")
	var want: Dictionary = _fill_distinct()
	_ok("① ★分母: 塞进去的值都非零且互不相同",
		want["ranked_used"] != 0 and want["season_sweeps"] != want["ranked_used"], str(want))

	## ★备份原存档 —— 跑完按字节还原, 绝不动玩家真存档
	var had_save: bool = FileAccess.file_exists(_gs.SAVE_PATH)
	var backup: PackedByteArray = PackedByteArray()
	if had_save:
		var bf := FileAccess.open(_gs.SAVE_PATH, FileAccess.READ)
		if bf != null:
			backup = bf.get_buffer(bf.get_length())
			bf.close()
	_ok("① ★分母: 备份拿到了(原来有存档就该非空)", (not had_save) or backup.size() > 0,
		"原存档 %s, 备份 %d 字节" % ["有" if had_save else "无", backup.size()])

	var was_test: bool = bool(_gs.test_mode)
	_gs.test_mode = false          # save() 在 test_mode 下直接 return, 这一段必须放开
	_gs.save()
	_gs.test_mode = was_test

	## 先把内存全打乱, 确保"读回来对"不是因为内存里本来就是对的
	for f in FIELDS_INT:
		_gs.set(f, -999)
	_gs.week_phase = "__dirty__"
	_gs.promoted = false
	_ok("① ★分母: 读回来之前内存确实被打乱了", int(_gs.ranked_used) == -999,
		"ranked_used=%d" % int(_gs.ranked_used))

	_gs._load()

	for f in want.keys():
		var got = _gs.get(f)
		_ok("① 往返保值: %s" % f, got == want[f], "存 %s / 回读 %s" % [str(want[f]), str(got)])

	## ★还原 —— 无论上面绿红都要做
	if had_save:
		var wf := FileAccess.open(_gs.SAVE_PATH, FileAccess.WRITE)
		if wf != null:
			wf.store_buffer(backup)
			wf.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_gs.SAVE_PATH))
	_ok("① ★收尾: 存档已还原成跑之前的样子",
		FileAccess.file_exists(_gs.SAVE_PATH) == had_save,
		"原来%s, 现在%s" % ["有" if had_save else "无", "有" if FileAccess.file_exists(_gs.SAVE_PATH) else "无"])


# ─────────────────────────────────────────────────────────────
# ② 切大轮: 八个字段全部归零 —— 守「漏了 start_new_season」
# ─────────────────────────────────────────────────────────────
func _t_new_season_resets() -> void:
	print("── ② start_new_season() 后全部归零 ──")
	var want: Dictionary = _fill_distinct()
	_ok("② ★分母: 切轮之前它们确实是非零的", int(_gs.ranked_used) > 0 and bool(_gs.promoted),
		"ranked_used=%d promoted=%s" % [int(_gs.ranked_used), str(_gs.promoted)])
	_gs.start_new_season()
	for f in FIELDS_INT:
		_ok("② 切轮归零: %s" % f, int(_gs.get(f)) == 0, "实得 %s" % str(_gs.get(f)))
	_ok("② 切轮归零: week_phase", str(_gs.week_phase) == "", "实得「%s」" % str(_gs.week_phase))
	_ok("② 切轮归零: promoted", bool(_gs.promoted) == false, "实得 %s" % str(_gs.promoted))


# ─────────────────────────────────────────────────────────────
# ③ 清档: 同样八个字段 —— 守「漏了 reset_save」
# ─────────────────────────────────────────────────────────────
func _t_reset_save_clears() -> void:
	print("── ③ reset_save() 后全部归零 ──")
	var want: Dictionary = _fill_distinct()
	_ok("③ ★分母: 清档之前它们确实是非零的", int(_gs.gauntlet_wins) > 0,
		"gauntlet_wins=%d" % int(_gs.gauntlet_wins))
	_gs.reset_save()
	for f in FIELDS_INT:
		_ok("③ 清档归零: %s" % f, int(_gs.get(f)) == 0, "实得 %s" % str(_gs.get(f)))
	_ok("③ 清档归零: week_phase", str(_gs.week_phase) == "", "实得「%s」" % str(_gs.week_phase))
	_ok("③ 清档归零: promoted", bool(_gs.promoted) == false, "实得 %s" % str(_gs.promoted))
