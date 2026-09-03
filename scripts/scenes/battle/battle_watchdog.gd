class_name BattleWatchdog
extends RefCounted
## 卡死看门狗 —— 独立线程盯主循环心跳，冻结 >4 秒就把现场写出来。
##
## ══════════════════════════════════════════════════════════════════
##  为什么单独成文件
## ══════════════════════════════════════════════════════════════════
## 它**不在 `_sim_step` 调用链上**（独立线程 + `_ready` 启动），按 CLAUDE.md §5 的判据
## 就不该待在主文件里。2026-09-03 抽出来的直接原因是 `arch_budget` 红了：
## 我为了追一个 bug 往主文件加了 58 行，而那条红线是「欠债只减不增」。
##
## ══════════════════════════════════════════════════════════════════
##  两种模式
## ══════════════════════════════════════════════════════════════════
## | env | 行为 |
## |---|---|
## | `STRESS=1` | 卡死猎手：冻结 → 打 FROZEN 行 → `OS.crash()`（外层脚本读日志定位） |
## | `WATCHDOG=1` | **正常游戏**：冻结 → 追加写 `user://freeze_report.txt` → **继续监测** |
##
## ★`WATCHDOG` 那条是 2026-09-03 加的。由来：用户「在 godot 打游戏有的时候直接卡住」
##   「画面完全不动」，而看门狗原本只在 STRESS 下开 ⇒ 他正常玩时卡住，现场什么都没留下。
##   正常游戏里**不 crash**（太粗暴，玩家还得能自己退出/截图），改成写报告并继续盯，
##   这样能分辨「只卡一次」（首次资源加载）和「反复卡」（真死循环）。
##
## ══════════════════════════════════════════════════════════════════
##  ★★★用它之前先知道这个坑（我踩过，代价是一整晚）
## ══════════════════════════════════════════════════════════════════
## 加 `WATCHDOG` 模式时我接了线程、接了 `_dbg_op` 打点，**唯独漏了心跳** ——
## `_hb += 1` 那一行写在主文件的 `if _stress:` 里面。心跳恒为 0 ⇒ 看门狗
## **从第一次检测起就一直报 FROZEN**，我照着这些假报告"定位"出一串不存在的根因。
##
## 线索早就在报告里：**`fps=137`**。帧率正常却说主循环冻结，两件事不可能同时成立。
## ⇒ **信任任何 FROZEN 报告之前，先拿一个确定正常的场景跑一遍，确认它「不报」。**
##   报告里自相矛盾的字段（fps 正常 vs 冻结、容器没涨 vs 说爆炸）就是止损信号。

const STALL_SEC := 4          # 连续多少秒没心跳算冻死
const REPORT_PATH := "user://freeze_report.txt"

var battle = null
var _thread: Thread = null


func _init(b) -> void:
	battle = b


## 启动。`crash_on_freeze` = STRESS 那套（冻死直接崩，外层读日志）。
func start(crash_on_freeze: bool) -> void:
	if _thread != null:
		return
	_thread = Thread.new()
	_thread.start(_loop.bind(crash_on_freeze))


## 收线程。★必须在场景退出时调 —— 线程活过场景会让 Godot 在退出时报
##   "A Thread object is being destroyed without its completion having been realized"。
func stop() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


func _loop(crash_on_freeze: bool) -> void:
	var last_hb := -1
	var stall := 0
	while battle != null and is_instance_valid(battle) and (battle._stress or battle._wd_on):
		OS.delay_msec(1000)
		if battle._hb != last_hb:
			stall = 0
			last_hb = battle._hb
			continue
		stall += 1
		if stall < STALL_SEC:
			continue
		var rpt: String = _snapshot()
		printerr("[看门狗] ★★★ MAIN LOOP FROZEN ★★★ " + rpt)
		if crash_on_freeze:
			OS.crash("frozen " + rpt)
			return
		_append(rpt)
		stall = 0
		last_hb = battle._hb


## 冻结现场。★光有 `last_op` 不够 —— 要能一眼看出"是不是真的冻了"
##   与"有没有东西在无限增长"，所以把 fps / 各容器大小一起报出来。
##   `fps` 那一项尤其重要：它正是让我发现看门狗自己坏了的那个字段。
func _snapshot() -> String:
	var tw: int = -1
	if battle.get_tree() != null:
		tw = battle.get_tree().get_processed_tweens().size()
	return "[FROZEN] %s  battle#%d  battle_t=%.2f  last_op=%s  op2=%s  adf_ct=%d  burst_depth=%d  units=%d  pending=%d  world=%d  ui=%d  tweens=%d  fps=%.1f  objs=%d" % [
		Time.get_datetime_string_from_system(), battle._stress_n, battle._t,
		battle._dbg_op, battle._dbg_op2, battle._adf_ct, battle._burst_depth,
		battle._units.size(), battle._pending_shots.size(),
		(battle._world.get_child_count() if is_instance_valid(battle._world) else -1),
		(battle._ui_layer.get_child_count() if is_instance_valid(battle._ui_layer) else -1),
		tw, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.OBJECT_COUNT)]


## 追加写（不是覆盖）—— 多次冻结要能看出 battle_t 有没有在推进。
## 写 `user://` 而不是 `res://`：导出版的 res:// 是只读的。
func _append(line: String) -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()
