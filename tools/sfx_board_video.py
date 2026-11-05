# -*- coding: utf-8 -*-
"""tools/sfx_board_video.py — 音效总览视频: 每条音效事件一张字幕卡 + 依次播放它的全部变体(2026-11-05)。
由来: 用户 11-05「八个小时之后，必须看到所有龟、所有装备完成这个音效的」。审核片里只听得到每只龟放技能那一刻;
  装备、暴击、命中变体在审核片里不一定碰得到 ⇒ 另出一份逐条可听的总览, 字幕写明是谁的哪一下、参考的是哪条 Riot 原声。
顺序: 每只龟(普攻出手 → 普攻命中 → 暴击 → 每个技能的放出 / 命中) → 装备(按编号) → 公共 / 界面。
读: scripts/gamedata/sfx_events.gd 同源的 tools/assetgen/sfx_picks_v2.json + tools/assetgen/sfx_prompts_v2.json(参考列)。
产物: .out/sfx_board/音效总览.mp4(1280×720, 字幕卡 + 声音) 与 音效总览_目录.md(每条在第几分第几秒)。
用法: python tools/sfx_board_video.py
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
OUT = os.path.join(ROOT, ".out", "sfx_board")
FONT = r"C:/Windows/Fonts/msyh.ttc"
SR = 44100
GAP = 0.35          # 变体之间
LEAD = 0.5          # 字幕卡先亮 0.5 秒再出声
TAIL = 0.4
CAT_ZH = {"ba_cast": "普攻出手", "ba_hit": "普攻命中", "crit": "暴击", "sk_cast": "技能放出", "sk_hit": "技能命中", "equip": "装备", "global": "公共 / 界面"}


def read_wav(path: str) -> np.ndarray:
	w = wave.open(path, "rb")
	ch, n = w.getnchannels(), w.getnframes()
	x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32).reshape(-1, ch) / 32768.0
	w.close()
	return x.mean(axis=1) if ch > 1 else x[:, 0]


def order(picks: dict, prompts: dict) -> list:
	pets = json.load(open(os.path.join(ROOT, "data", "pets.json"), encoding="utf-8"))
	pets = pets if isinstance(pets, list) else pets.get("pets", [])
	keys = []
	for p in pets:
		tid = p.get("id")
		for pre in ("bas_", "bah_", "crit_"):
			keys.append(pre + tid)
		for s in p.get("skillPool", [])[1:4]:
			st = s.get("type", "")
			keys += ["sk_" + st, "skh_" + st]
			if tid == "lava":
				vol = {"lavaQuake": "volcanoErupt", "lavaSurge": "volcanoSmash", "lavaErupt": "lavaRampage"}.get(st)
				if vol:
					keys += ["sk_" + vol, "skh_" + vol]
	keys += sorted(k for k in picks if k.startswith("eq_"))
	keys += sorted(k for k in picks if picks[k]["cat"] == "global")
	seen = set()
	out = []
	for k in keys:
		if k in picks and picks[k]["sel"] and k not in seen:
			seen.add(k)
			out.append(k)
	out += sorted(k for k in picks if picks[k]["sel"] and k not in seen)
	return out


def card(path: str, title: str, sub: str, idx: str, cat: str) -> None:
	img = Image.new("RGB", (1280, 720), (16, 20, 30))
	d = ImageDraw.Draw(img)
	f_big = ImageFont.truetype(FONT, 64)
	f_mid = ImageFont.truetype(FONT, 30)
	f_small = ImageFont.truetype(FONT, 24)
	d.rectangle([0, 0, 1280, 8], fill=(255, 196, 64))
	d.text((80, 70), cat, font=f_mid, fill=(255, 196, 64))
	d.text((80, 230), title, font=f_big, fill=(240, 244, 250))
	d.text((80, 340), sub, font=f_mid, fill=(150, 170, 190))
	d.text((80, 640), idx, font=f_small, fill=(110, 125, 140))
	img.save(path)


def main() -> int:
	os.makedirs(OUT, exist_ok=True)
	picks = json.load(open(os.path.join(ROOT, "tools", "assetgen", "sfx_picks_v2.json"), encoding="utf-8"))
	tab = json.load(open(os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json"), encoding="utf-8"))
	ref = {it["key"]: it.get("ref", "") for it in tab["batches"]["v2"]}
	keys = order(picks, tab)
	audio = []
	concat = []
	toc = ["# 音效总览 · 目录(tools/sfx_board_video.py 生成)", "", "共 %d 条事件。每条: 字幕卡先亮 %.1f 秒, 然后依次播放它的全部变体(间隔 %.2f 秒)。" % (len(keys), LEAD, GAP), "",
		"| # | 开始 | 类别 | 名称 | 事件 | 变体 | 参考的 Riot 原声 |", "|---|---|---|---|---|---|---|"]
	t = 0.0
	for i, k in enumerate(keys):
		p = picks[k]
		n = len(p["sel"])
		segs = [read_wav(os.path.join(ROOT, "assets", "audio", "sfx", "v2", "%s__%d.wav" % (k, j))) for j in range(1, n + 1)]
		buf = [np.zeros(int(LEAD * SR), dtype=np.float32)]
		for j, s in enumerate(segs):
			buf.append(s)
			buf.append(np.zeros(int((GAP if j < n - 1 else TAIL) * SR), dtype=np.float32))
		a = np.concatenate(buf)
		dur = len(a) / SR
		png = os.path.join(OUT, "card_%03d.png" % i)
		card(png, p["zh"], "%s  ·  %d 个变体  ·  参考 %s" % (k, n, ref.get(k, "")), "%d / %d" % (i + 1, len(keys)), CAT_ZH.get(p["cat"], p["cat"]))
		concat.append("file '%s'\nduration %.4f\n" % (png.replace("\\", "/"), dur))
		toc.append("| %d | %d:%05.2f | %s | %s | %s | %d | %s |" % (i + 1, int(t // 60), t % 60, CAT_ZH.get(p["cat"], ""), p["zh"], k, n, ref.get(k, "")))
		audio.append(a)
		t += dur
	concat.append("file '%s'\n" % os.path.join(OUT, "card_%03d.png" % (len(keys) - 1)).replace("\\", "/"))
	open(os.path.join(OUT, "list.txt"), "w", encoding="utf-8").write("".join(concat))
	x = np.concatenate(audio)
	q = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
	w = wave.open(os.path.join(OUT, "audio.wav"), "wb")
	w.setnchannels(1)
	w.setsampwidth(2)
	w.setframerate(SR)
	w.writeframes(q.tobytes())
	w.close()
	mp4 = os.path.join(OUT, "音效总览.mp4")
	subprocess.run([FF, "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", os.path.join(OUT, "list.txt"), "-i", os.path.join(OUT, "audio.wav"),
		"-vf", "fps=10,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "30", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
	open(os.path.join(OUT, "音效总览_目录.md"), "w", encoding="utf-8").write("\n".join(toc) + "\n")
	print("写出 %s · %d 条事件 · %.1f 分钟" % (mp4, len(keys), t / 60))
	return 0


if __name__ == "__main__":
	sys.exit(main())
