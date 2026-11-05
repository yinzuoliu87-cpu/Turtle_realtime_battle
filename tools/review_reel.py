"""tools/review_reel.py — 审核片(用户 11-04 给的格式): 每只龟依次 普攻 / 技能1 / 技能2 / 技能3, 每段 6 秒、正常速度、对一个敌人, 片头标「龟名 · 普攻/技能名」, 另出时间表。
录法: REVIEW=1 审阅台(受审龟对一个假人) + Movie Maker 固定 30 帧; 外壳场景 tests/probes/review_rec_probe.tscn 每帧读技能冷却, 回满那帧 = 放技能, 打印 [CAST] frame=N。
技能段从「放技能前 1 秒」剪到「放技能后 5 秒」; 25 秒内没放出来的段标出来。
用法: python tools/review_reel.py <工程根> <输出目录(放 .out/ 下)> <标签(改前/改后)> [并行数] [只录哪些段]
  只录哪些段: 逗号分隔, 每项 = 龟id(四段全录) 或 龟id:段号(0=普攻 1~3=技能) 或 lava@volcano:段号(火山形态)
画面(2026-11-05 改): 主画面 = 整场 1280×720 原样(之前是中心放大 2 倍 + 右下小窗, 用户看熔岩龟时浪在场边被裁掉, 「你怎么看不见」)。
熔岩龟(会变身)两种形态各录一套: 普通形态怒气锁 0, 火山形态开打 2 秒直接变身(外壳场景 REVIEW_FORM)。
★必须开可见窗口(放右屏): 最小化时 Godot 不渲染(实测黑帧)、负坐标会被夹回主屏。工程根可以是旧提交的 worktree(外壳场景会自动拷过去)。
★不许带 STRESS(那是 5 倍速)。"""
import concurrent.futures as cf
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
ROOT, OUT, TAG = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
JOBS = int(sys.argv[4]) if len(sys.argv) > 4 else 4
ONLY = set(sys.argv[5].split(",")) if len(sys.argv) > 5 and sys.argv[5] else None
FORMS = {"lava": [("normal", ""), ("volcano", "火山形态·")]}   # 会变身的龟: (REVIEW_FORM, 段名前缀)
G = "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe"
FF = "D:/oopz/ffmpeg.exe"
FPS = 30
SEG = 6.0
os.makedirs(OUT, exist_ok=True)
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = "res://tests/probes/review_rec_probe.tscn"
if not os.path.exists(os.path.join(ROOT, "tests", "probes", "review_rec_probe.gd")):
	os.makedirs(os.path.join(ROOT, ".out", "review"), exist_ok=True)
	for fn in ("review_rec_probe.gd", "review_rec_probe.tscn"):
		t = open(os.path.join(HERE, "tests", "probes", fn), encoding="utf-8").read().replace("res://tests/probes/", "res://.out/review/")
		open(os.path.join(ROOT, ".out", "review", fn), "w", encoding="utf-8").write(t)
	PROBE = "res://.out/review/review_rec_probe.tscn"
shutil.copy("C:/Windows/Fonts/msyh.ttc", os.path.join(OUT, "msyh.ttc"))
pets = json.load(open(os.path.join(ROOT, "data", "pets.json"), encoding="utf-8"))
pets = pets if isinstance(pets, list) else pets.get("pets")
VOLCANO_NAMES = {}
jobs = []
for p in pets:
	for form, prefix in FORMS.get(p["id"], [("", "")]):
		key = p["id"] + ("@" + form if form == "volcano" else "")
		if form == "volcano":
			alt = p.get("volcanoSkills") or p.get("transformSkills") or []
			names = [s.get("name", "?") for s in alt] if alt else []
		for idx, sk in enumerate(p["skillPool"][:4]):
			if ONLY and key not in ONLY and ("%s:%d" % (key, idx)) not in ONLY:
				continue
			kind = prefix + ("普攻" if idx == 0 else "技能%d" % idx)
			nm = sk.get("name", "?")
			if form == "volcano" and idx < len(names):
				nm = names[idx]
			jobs.append({"id": p["id"], "name": p["name"], "idx": idx, "kind": kind, "skill": nm, "form": form})


def record(j):
	raw = os.path.join(OUT, "raw_%s%s_%d.avi" % (j["id"], ("_" + j["form"]) if j["form"] else "", j["idx"]))
	log = raw + ".log"
	n = 300 if j["idx"] == 0 else 750
	u = tempfile.mkdtemp()
	env = dict(os.environ, REVIEW="1", REVIEW_TURTLE=j["id"], REVIEW_SKILL=str(j["idx"]), TURTLE_SUPABASE=" ", TURTLE_BACKEND=" ",
		APPDATA=u, XDG_DATA_HOME=u)
	if j["form"]:
		env["REVIEW_FORM"] = j["form"]
	env.pop("SHIP", None)
	env.pop("STRESS", None)
	with open(log, "w", encoding="utf-8") as lf:
		subprocess.run([G, "--path", ROOT, "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--resolution", "1280x720",
			"--position", "1960,60", "--disable-vsync", "--write-movie", raw, "--fixed-fps", str(FPS), "--quit-after", str(n),
			PROBE], env=env, stdout=lf, stderr=subprocess.STDOUT, timeout=600)
	txt = open(log, encoding="utf-8", errors="replace").read()
	casts = [int(x) for x in re.findall(r"\[CAST\] frame=(\d+)", txt)]
	if j["idx"] == 0:
		t0, note = 1.0, ""
	elif casts:
		t0, note = max(0.0, casts[0] / FPS - 1.0), "放技能在第 %.1f 秒" % (casts[0] / FPS)
	else:
		t0, note = 12.0, "25 秒内没放出"
	j.update({"raw": raw, "t0": t0, "note": note, "cast_frames": casts[:3], "err": "SCRIPT ERROR" in txt})
	return j


def cut(j, k):
	seg = os.path.join(OUT, "seg_%03d.mp4" % k)
	title = "%s · %s「%s」" % (j["name"], j["kind"], j["skill"])
	open(os.path.join(OUT, "t1_%03d.txt" % k), "w", encoding="utf-8").write(title)
	open(os.path.join(OUT, "t2_%03d.txt" % k), "w", encoding="utf-8").write(TAG + ("  " + j["note"] if j["note"] else ""))
	## 整场原样(2026-11-05: 原来的中心放大裁切会把场边的东西切掉)
	fc = ("[0:v]"
		"drawtext=fontfile=msyh.ttc:textfile=t1_%03d.txt:x=24:y=20:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=10,"
		"drawtext=fontfile=msyh.ttc:textfile=t2_%03d.txt:x=w-tw-24:y=24:fontsize=24:fontcolor=yellow:box=1:boxcolor=black@0.55:boxborderw=8[v]") % (k, k)
	subprocess.run([FF, "-y", "-v", "error", "-ss", "%.3f" % j["t0"], "-t", "%.1f" % SEG, "-i", j["raw"], "-filter_complex", fc, "-map", "[v]", "-map", "0:a?", "-r", str(FPS),
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2",
		os.path.basename(seg)], cwd=OUT, check=True)
	return seg


done = []
with cf.ThreadPoolExecutor(max_workers=JOBS) as ex:
	for r in ex.map(record, jobs):
		done.append(r)
		print("录完 %s %s %s %s" % (r["id"], r["kind"], r["note"], "⚠脚本报错" if r["err"] else ""), flush=True)
segs = []
idx_lines = ["# 审核片 · %s" % TAG, "", "| 片内时间 | 龟 | 段 | 备注 |", "|---|---|---|---|"]
for k, j in enumerate(done):
	segs.append(cut(j, k))
	t = k * SEG
	idx_lines.append("| %d:%02d | %s | %s「%s」 | %s |" % (int(t // 60), int(t % 60), j["name"], j["kind"], j["skill"], j["note"]))
open(os.path.join(OUT, "list.txt"), "w", encoding="utf-8").write("".join("file '%s'\n" % os.path.basename(s) for s in segs))
reel = os.path.join(OUT, "审核片_%s.mp4" % TAG)
subprocess.run([FF, "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", "list.txt", "-c", "copy", os.path.basename(reel)], cwd=OUT, check=True)
open(os.path.join(OUT, "时间表_%s.md" % TAG), "w", encoding="utf-8").write("\n".join(idx_lines) + "\n")
miss = [d for d in done if d["idx"] > 0 and not d["cast_frames"]]
print("完成: %d 段 · 成片 %s · 没放出技能的段 %d: %s · 报错 %d" % (len(done), reel, len(miss), [(m["id"], m["kind"]) for m in miss],
	sum(1 for d in done if d["err"])))
