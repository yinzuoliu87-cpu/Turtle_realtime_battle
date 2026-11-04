# -*- coding: utf-8 -*-
"""sfx_rank.py — 音效候选初筛: 拿黑箱同类原声当尺子量曲线, 排序, 出一页本地试听页给用户耳朵定稿（2026-11-04 · A5）。

我听不见, 能做的只有「量」: 每个候选与它那条的黑箱参照比四项曲线, 距离越小越像:
  ① 有效时长(包络高于峰值 −40 dB 的那段) ② 音色亮度(频谱质心) ③ 起音(起点到包络峰值) ④ 衰减(峰值到降 20 dB)
  响度不进距离 —— 进游戏时 build_sfx 统一响度; 试听页里参照与候选也先统一到同一 RMS,
  否则人耳会把「更响」听成「更好」。
另外标出: 开头静音过长 / 削波 / 时长离参照差一倍以上。

输入: 候选目录 <SFX_SRC>/eleven/<批次>/(gen_sfx_elevenlabs.py 产出, 带 manifest.json 记每条的参照名)
      参照 .out/blackbox/sfx/<ref>.wav(tools/oneoff 拆包研究抽出来的黑箱 Demo 原声, 只做尺子不进游戏)
输出: .out/sfx_rank/<批次>/rank.tsv · index.html(试听页) · a/*.wav(统一响度后的试听副本)
用法: python tools/sfx_rank.py b1
"""
import html
import json
import math
import os
import subprocess
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
REF_DIR = os.path.join(ROOT, ".out", "blackbox", "sfx")
SR = 44100
LISTEN_RMS_DB = -20.0


def decode(path: str) -> np.ndarray:
	raw = subprocess.run([FF, "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
		capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def feats(x: np.ndarray) -> dict:
	win = int(SR * 0.01)
	n = max(1, len(x) // win)
	env = np.sqrt(np.mean(x[: n * win].reshape(n, win) ** 2, axis=1) + 1e-12)
	edb = 20 * np.log10(env + 1e-12)
	pk = int(np.argmax(edb))
	act = np.where(edb > edb[pk] - 40)[0]
	s, e = int(act[0]), int(act[-1])
	dec_idx = np.where(edb[pk:] > edb[pk] - 20)[0]
	seg = x[s * win:(e + 1) * win]
	spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) if len(seg) > 32 else np.ones(2)
	fr = np.fft.rfftfreq(len(seg), 1.0 / SR) if len(seg) > 32 else np.ones(2)
	cent = float(np.sum(fr * spec) / (np.sum(spec) + 1e-12))
	return {"dur": (e - s + 1) * 0.01, "lead": s * 0.01, "attack": (pk - s) * 0.01, "decay": (int(dec_idx[-1]) + 1) * 0.01,
		"cent": cent, "rms": float(20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12)),
		"peak": float(20 * np.log10(np.max(np.abs(x)) + 1e-12))}


def dist(f: dict, r: dict) -> float:
	return (abs(math.log(max(f["dur"], 0.01) / max(r["dur"], 0.01))) + abs(math.log(max(f["cent"], 50) / max(r["cent"], 50)))
		+ 0.5 * abs(math.log((f["attack"] + 0.005) / (r["attack"] + 0.005)))
		+ 0.5 * abs(math.log((f["decay"] + 0.01) / (r["decay"] + 0.01))))


def flags(f: dict, r: dict) -> list:
	out = []
	if f["lead"] > 0.05:
		out.append("开头静音 %.2fs" % f["lead"])
	if f["peak"] > -0.2:
		out.append("削波")
	if f["dur"] > 2 * r["dur"] or f["dur"] < 0.5 * r["dur"]:
		out.append("时长差一倍(%.2f / 参照 %.2f)" % (f["dur"], r["dur"]))
	return out


def write_listen(path: str, x: np.ndarray) -> None:
	f = feats(x)
	g = 10 ** ((LISTEN_RMS_DB - f["rms"]) / 20)
	y = np.clip(x * g, -0.98, 0.98)
	pcm = (y * 32767).astype("<i2").tobytes()
	import wave
	with wave.open(path, "wb") as w:
		w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)


def main() -> int:
	batch = sys.argv[1] if len(sys.argv) > 1 else "b1"
	cdir = os.path.join(SRC, "eleven", batch)
	man = json.load(open(os.path.join(cdir, "manifest.json"), encoding="utf-8"))
	odir = os.path.join(ROOT, ".out", "sfx_rank", batch)
	os.makedirs(os.path.join(odir, "a"), exist_ok=True)
	groups = {}
	for fn, rec in man.items():
		if os.path.exists(os.path.join(cdir, fn)):
			groups.setdefault(rec["key"], []).append((fn, rec))
	tab = json.load(open(os.path.join(ROOT, "tools", "assetgen", "sfx_prompts.json"), encoding="utf-8"))["batches"][batch]
	order = [it["key"] for it in tab if it["key"] in groups]
	rows = ["key\tcand\trank\tdist\tdur\tattack\tdecay\tcent\tflags"]
	sections = []
	n_c = 0
	for k in order:
		cands = groups[k]
		ref = cands[0][1]["ref"]
		rx = decode(os.path.join(REF_DIR, ref + ".wav"))
		rf = feats(rx)
		write_listen(os.path.join(odir, "a", "ref_%s.wav" % k), rx)
		scored = []
		for fn, rec in cands:
			x = decode(os.path.join(cdir, fn))
			f = feats(x)
			scored.append((dist(f, rf), fn, f, flags(f, rf)))
			write_listen(os.path.join(odir, "a", fn.replace(".mp3", ".wav")), x)
			n_c += 1
		scored.sort(key=lambda t: t[0])
		for i, (d, fn, f, fl) in enumerate(scored):
			rows.append("%s\t%s\t%d\t%.3f\t%.2f\t%.2f\t%.2f\t%.0f\t%s" % (k, fn, i + 1, d, f["dur"], f["attack"], f["decay"], f["cent"], "; ".join(fl)))
		zh = html.escape(cands[0][1].get("zh", k))
		li = ['<div class="c ref"><b>黑箱参照</b> <span>%s · %.2fs · 亮度 %.0f Hz</span><audio controls preload="none" src="a/ref_%s.wav"></audio></div>'
			% (html.escape(ref), rf["dur"], rf["cent"], k)]
		for i, (d, fn, f, fl) in enumerate(scored):
			num = fn.rsplit("_", 1)[1].split(".")[0]
			tag = "我的首选 · " if i == 0 else ""
			li.append('<label class="c"><input type="radio" name="%s" value="%s"%s><b>候选 %s</b> <span>%s离参照 %.2f · %.2fs · 亮度 %.0f Hz%s</span>'
				'<audio controls preload="none" src="a/%s"></audio></label>'
				% (k, num, " checked" if i == 0 else "", num, tag, d, f["dur"], f["cent"],
				   (" · ⚠ " + html.escape("；".join(fl))) if fl else "", fn.replace(".mp3", ".wav")))
		sections.append('<section><h2>%s <small>%s</small></h2>%s</section>' % (zh, k, "".join(li)))
	open(os.path.join(odir, "rank.tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
	page = """<!doctype html><meta charset="utf-8"><title>音效试听 %s</title>
<style>body{font:15px/1.5 system-ui,"Microsoft YaHei";background:#1b1916;color:#efe6d6;max-width:980px;margin:0 auto;padding:16px}
h1{color:#ffce4d}section{background:#26231f;border-radius:8px;padding:10px 14px;margin:12px 0}h2{margin:4px 0 8px;font-size:17px}
h2 small{color:#8f8676;font-weight:normal}.c{display:grid;grid-template-columns:1fr 320px;align-items:center;gap:8px;padding:4px 0}
.c span{color:#b9ae9c;font-size:13px}.ref b{color:#7fd1ff}audio{width:320px;height:32px}
#out{position:sticky;bottom:0;background:#111;padding:10px;border-top:2px solid #ffce4d}textarea{width:100%%;height:60px}</style>
<h1>音效试听 · 第一批 %d 条</h1>
<p>每条先听「黑箱参照」, 再听我们的候选(已统一到同一响度, 只比声音本身)。默认勾的是我按曲线量出来最像参照的那个;
觉得哪个最好就点哪个, 都不行就不用管。全部听完把最下面那一行原样发给我。</p>%s
<div id="out"><textarea id="t" readonly></textarea></div>
<script>function up(){var r=[];document.querySelectorAll('section').forEach(function(s){var c=s.querySelector('input:checked');
if(c)r.push(c.name+'='+c.value)});document.getElementById('t').value=r.join(',')}
document.addEventListener('change',up);up();</script>""" % (batch, len(order), "".join(sections))
	open(os.path.join(odir, "index.html"), "w", encoding="utf-8").write(page)
	print("分母: %d 条 · %d 个候选 · 参照 %d 条" % (len(order), n_c, len(order)))
	print("试听页:", os.path.join(odir, "index.html"))
	return 0


if __name__ == "__main__":
	sys.exit(main())
