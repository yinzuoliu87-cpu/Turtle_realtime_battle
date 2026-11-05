# -*- coding: utf-8 -*-
"""tools/sfx_measure.py — 一条音效的「长相」量成数字(2026-11-05)。
由来: 用户 11-05「你音效是死贴着像素吗，跟云顶学啥了」。我听不见, 判「像不像云顶」只能量:
  同一把尺子量云顶 / LoL 原声(tools/oneoff/riot_audio_extract.py 解出, .out/riot_audio/)与我们的, 逐项比。
量什么(每条):
  dur      总长(秒): 包络最后一次高于 峰值−50 dB 的时刻
  attack   起音(秒): 从第一次高于 峰值−30 dB 到峰值
  tail     尾音(秒): 峰值之后包络最后一次高于 峰值−20 dB 的时刻 − 峰值时刻(混响 / 余响有多长)
  rms      有声段 RMS(dBFS)        peak  峰值(dBFS)        crest 峰值 − RMS(dB)
  cent     频谱质心(Hz)            low   150 Hz 以下能量占比   high  5 kHz 以上能量占比
  flat     频谱平坦度(0 = 纯音 / 方波一类, 1 = 白噪声)
  tonal    最强 12 根谱线占总能量比(方波 / 芯片音这一类谐波尖峰多, 写实拟音低)
  width    立体声宽度 = 侧声 / 中声 能量比(单声道 = 0)
用法: python tools/sfx_measure.py <wav 或目录> [...] [--tsv 输出.tsv]
"""
import argparse
import os
import sys

import wave

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
COLS = ["dur", "attack", "tail", "rms", "peak", "crest", "cent", "low", "high", "flat", "tonal", "width"]


def _read(path):
	"""16 位 PCM 走标准库 wave(CLAP 环境没有 scipy); 别的格式再交给 scipy。"""
	try:
		w = wave.open(path, "rb")
		if w.getsampwidth() == 2:
			sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
			x = np.frombuffer(w.readframes(n), dtype=np.int16).reshape(-1, ch)
			w.close()
			return sr, x
		w.close()
	except Exception:
		pass
	from scipy.io import wavfile
	return wavfile.read(path)


def load(path):
	sr, x = _read(path)
	if x.dtype == np.int16:
		x = x.astype(np.float32) / 32768.0
	elif x.dtype == np.int32:
		x = x.astype(np.float32) / 2147483648.0
	elif x.dtype == np.uint8:
		x = (x.astype(np.float32) - 128.0) / 128.0
	else:
		x = x.astype(np.float32)
	if x.ndim == 1:
		x = x[:, None]
	return sr, x


def measure(path):
	sr, x = load(path)
	mono = x.mean(axis=1)
	n = len(mono)
	if n < 64:
		return None
	hop = max(1, int(sr * 0.005))
	env = np.array([np.sqrt(np.mean(mono[i:i + hop] ** 2) + 1e-12) for i in range(0, n, hop)])
	edb = 20 * np.log10(env + 1e-9)
	pk_i = int(np.argmax(edb))
	pk = edb[pk_i]
	if pk < -80:
		return None
	t = lambda i: i * hop / sr
	above50 = np.where(edb > pk - 50)[0]
	above30 = np.where(edb > pk - 30)[0]
	above20 = np.where(edb > pk - 20)[0]
	dur = t(above50[-1] + 1)
	attack = t(pk_i) - t(above30[0])
	tail = t(above20[-1]) - t(pk_i)
	act = mono[int(above30[0] * hop):int((above50[-1] + 1) * hop)]
	rms = 20 * np.log10(np.sqrt(np.mean(act ** 2)) + 1e-9)
	peak = 20 * np.log10(np.max(np.abs(x)) + 1e-9)
	# 频谱(有声段, 汉宁窗分帧平均功率谱)
	N = 2048
	if len(act) < N:
		act = np.pad(act, (0, N - len(act)))
	fr = [act[i:i + N] * np.hanning(N) for i in range(0, len(act) - N + 1, N // 2)]
	P = np.mean([np.abs(np.fft.rfft(f)) ** 2 for f in fr], axis=0) + 1e-18
	f = np.fft.rfftfreq(N, 1 / sr)
	tot = P.sum()
	cent = float((P * f).sum() / tot)
	low = float(P[f < 150].sum() / tot)
	high = float(P[f > 5000].sum() / tot)
	band = (f > 40) & (f < min(16000, sr / 2 - 1))
	pb = P[band]
	flat = float(np.exp(np.mean(np.log(pb))) / np.mean(pb))
	tonal = float(np.sort(pb)[-12:].sum() / pb.sum())
	if x.shape[1] >= 2:
		m = (x[:, 0] + x[:, 1]) / 2
		s = (x[:, 0] - x[:, 1]) / 2
		width = float(np.sum(s ** 2) / (np.sum(m ** 2) + 1e-12))
	else:
		width = 0.0
	return dict(dur=dur, attack=attack, tail=tail, rms=rms, peak=peak, crest=peak - rms, cent=cent, low=low, high=high,
		flat=flat, tonal=tonal, width=width, sr=sr, ch=x.shape[1])


def files_of(paths):
	for p in paths:
		if os.path.isdir(p):
			for fn in sorted(os.listdir(p)):
				if fn.lower().endswith(".wav"):
					yield os.path.join(p, fn)
		else:
			yield p


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("paths", nargs="+")
	ap.add_argument("--tsv", default="")
	a = ap.parse_args()
	rows = []
	for fp in files_of(a.paths):
		try:
			m = measure(fp)
		except Exception as e:
			print("跳过", fp, e)
			continue
		if m:
			rows.append((os.path.basename(fp), m))
	hdr = "文件\t" + "\t".join(COLS) + "\tsr\tch"
	lines = [hdr] + ["%s\t" % n + "\t".join(("%.3f" % m[c]) for c in COLS) + "\t%d\t%d" % (m["sr"], m["ch"]) for n, m in rows]
	if a.tsv:
		open(a.tsv, "w", encoding="utf-8").write("\n".join(lines) + "\n")
	if rows:
		arr = {c: np.array([m[c] for _, m in rows]) for c in COLS}
		print("分母 %d 条" % len(rows))
		print("项\t中位\tP10\tP90")
		for c in COLS:
			print("%s\t%.3f\t%.3f\t%.3f" % (c, np.median(arr[c]), np.percentile(arr[c], 10), np.percentile(arr[c], 90)))
		print("立体声占比 %.0f%%" % (100.0 * sum(1 for _, m in rows if m["ch"] >= 2) / len(rows)))
	else:
		print("分母 0 条")


if __name__ == "__main__":
	main()
