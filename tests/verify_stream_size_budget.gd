extends Node
## verify_stream_size_budget.gd — 逐帧直播 S1: 状态流体积不超预算, 而且写出来的每一块都解得开。
## 方案书 docs/plans/20261019-服务器逐帧直播.md 验收清单「体积预算」; 预算的来历见方案书 §2.2「体积预算」。
##
## 两局三路打满的裁判局各录一遍(块文件写进本测试自己的 user:// 目录):
##   · 镜像快照局(verify_referee_job_roundtrip 同款, 种子 2000023)
##   · 真实快照局(tests/golden/stream_heavy_pair.json, S0 的最重那局)
## 判据:
##   ★整局压缩后字节 ≤ 预算; 最大的一块 ≤ 块预算(观看端带宽)
##   ★格式自洽: 块文件个数 = 元数据 chunks; 每块版本号 = StreamFormat.VERSION、按顺序解码到最后一个字节不多不少;
##     块序号连续、每 KEY_CHUNKS 块一个 keyframe 块; 各块步数之和 = 录的步数; end.json 读得回、版本号一致
## 分母: 两局都打满三路(开打 3 次)、录到节点 / 事件、块数 > 100。

const J := preload("res://tests/_stream_jobs.gd")
const F := preload("res://scripts/systems/stream/stream_format.gd")
## 预算(字节) = S0 实测(2026-10-19, 原型编码器): 镜像局 0.91 MB / 真实快照局 2.54 MB / 最大一块 49.2 KB。
##   方案书 R1 的存储 / 流量 / 观看带宽估算就是按这三个数算的 ⇒ 超了不是「抬预算」, 是 R1 要重算、先查哪一层涨了。
## S1 实测(同日): 镜像局 0.87 MB / 真实快照局 2.37 MB / 最大一块 46 KB(余量 4~7%; 特效随机 juice_rng 让同一局每遍差 ±1% 左右)。
const BUDGET := {"镜像快照局": 910000, "真实快照局(最重)": 2540000}
const BUDGET_CHUNK := 49200
const DIR := "user://stream_size_budget"

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var jobs := [["镜像快照局", J.mirror(gs), "m"], ["真实快照局(最重)", J.heavy(), "h"]]
	for jj in jobs:
		await _one(str(jj[0]), jj[1], DIR.path_join(str(jj[2])))
	_finish()


func _clear(dir: String) -> void:
	var adir := ProjectSettings.globalize_path(dir)
	if DirAccess.dir_exists_absolute(adir):
		for f in DirAccess.get_files_at(adir):
			DirAccess.remove_absolute(adir.path_join(f))


func _one(tag: String, job: Dictionary, dir: String) -> void:
	print("=== %s ===" % tag)
	_ok("分母 · %s 任务单读得到" % tag, not job.is_empty())
	if job.is_empty():
		return
	_clear(dir)
	var adir := ProjectSettings.globalize_path(dir)
	var res: Dictionary = await RefereeRunner.run(self, job, Callable(), {"dir": adir})
	var m: Dictionary = res.get("stream", {})
	var z := int(m.get("z_bytes", 0))
	print("  [量] %s: ok=%s 开打 %d 步 %d · 原始 %d B → 压缩后 %d B(%.2f MB, %.1f KB/s) · 块 %d 个、最大 %d B · 节点 %d / 事件 %s" % [tag,
		str(res.get("ok")), int(res.get("fights", 0)), int(m.get("steps", 0)), int(m.get("raw_bytes", 0)), z, z / 1.0e6,
		z / 1024.0 / maxf(1.0, int(m.get("steps", 0)) / 60.0), int(m.get("chunks", 0)), int(m.get("max_chunk_bytes", 0)),
		int(m.get("nodes_new", 0)), str(m.get("events", {}))])
	_ok("分母 · %s 算完且打满三路" % tag, bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3)
	_ok("分母 · %s 录到东西: 块 %d > 100、节点 %d > 1000、事件 %d 类" % [tag, int(m.get("chunks", 0)), int(m.get("nodes_new", 0)),
		(m.get("events", {}) as Dictionary).size()], int(m.get("chunks", 0)) > 100 and int(m.get("nodes_new", 0)) > 1000
		and (m.get("events", {}) as Dictionary).size() >= 4)
	var budget := int(BUDGET.get(tag, 0))
	_ok("★★%s 整局压缩后 %d B ≤ 预算 %d B" % [tag, z, budget], z > 0 and z <= budget)
	_ok("★%s 最大一块 %d B ≤ 块预算 %d B" % [tag, int(m.get("max_chunk_bytes", 0)), BUDGET_CHUNK],
		int(m.get("max_chunk_bytes", 0)) > 0 and int(m.get("max_chunk_bytes", 0)) <= BUDGET_CHUNK)
	## ── 格式自洽: 从盘上读回来逐块解 ──
	var files: Array = []
	for f in DirAccess.get_files_at(adir):
		if str(f).ends_with(".bin"):
			files.append(str(f))
	files.sort()
	_ok("%s 块文件 %d 个 = 元数据 chunks %d" % [tag, files.size(), int(m.get("chunks", 0))], files.size() == int(m.get("chunks", 0)) and files.size() > 0)
	var st := {}
	var bad: Array = []
	var steps_sum := 0
	var bytes_sum := 0
	var seq_ok := true
	var key_ok := true
	var keys := 0
	for i in range(files.size()):
		var data := FileAccess.get_file_as_bytes(adir.path_join(files[i]))
		bytes_sum += data.size()
		var d := F.decode_chunk(data, st)
		if not bool(d["ok"]):
			bad.append("%s:%s" % [files[i], str(d["err"])])
			continue
		steps_sum += int(d["steps"])
		seq_ok = seq_ok and int(d["seq"]) == i and int(d["version"]) == F.VERSION
		var want_key := (i % F.KEY_CHUNKS) == 0
		key_ok = key_ok and bool(d["key"]) == want_key and (int((d["ops"] as Dictionary).get(F.OP_KEYFRAME, 0)) == (1 if want_key else 0))
		if bool(d["key"]):
			keys += 1
	_ok("★%s 每块都解得开(版本 %d, 解到最后一个字节)" % [tag, F.VERSION], bad.is_empty(), str(bad.slice(0, 3)))
	_ok("%s 块序号连续、版本号一致" % tag, seq_ok)
	_ok("%s 每 %d 块一个 keyframe 块(共 %d 个)、keyframe 块里恰一条 KEYFRAME" % [tag, F.KEY_CHUNKS, keys], key_ok and keys > 0)
	_ok("%s 各块步数之和 %d = 录的步数 %d; 盘上字节 %d = 元数据 %d" % [tag, steps_sum, int(m.get("steps", -1)), bytes_sum, z],
		steps_sum == int(m.get("steps", -1)) and bytes_sum == z)
	var ej = JSON.parse_string(FileAccess.get_file_as_string(adir.path_join("end.json")))
	_ok("%s end.json 读得回、版本号 %s = %d、digest 与结果单相同" % [tag, str((ej as Dictionary).get("format", "?")) if ej is Dictionary else "?", F.VERSION],
		ej is Dictionary and int((ej as Dictionary).get("format", -1)) == F.VERSION
		and str((ej as Dictionary).get("digest", "")) == str(res.get("digest", "x")))
	_clear(dir)


func _finish() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 状态流体积在预算内、格式自洽 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
