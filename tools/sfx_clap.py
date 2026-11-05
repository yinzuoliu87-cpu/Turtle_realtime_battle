# -*- coding: utf-8 -*-
"""sfx_clap.py — 用 CLAP(声音 ↔ 文字匹配模型)给音效打分, 当我的「耳朵」（2026-11-04 · A5）。

由来: 用户「中间过程都不需要我来…你自己看看有没有达到黑箱的标准」。我听不见; 曲线(时长 / 起音 / 衰减 / 亮度)量得出
  「形状像不像」, 量不出「是不是那个东西」。CLAP(laion/larger_clap_general)把一段声音和一句英文描述映到同一空间,
  余弦相似度高 = 声音像这句话。用途三件:
  ① 候选与它自己的描述有多像(选「是那个东西」的那个);
  ② 坏样本: 最像「音乐 / 人声说话 / 安静无声 / 嘶嘶底噪」的剔掉;
  ③ 标定: 先拿黑箱原声(已知类别)跑一遍分类准确率, 尺子准不准先量出来(--calibrate)。
★依赖不在仓库: 用 D:/turtle_audio_src/clapenv(torch CPU + transformers)跑, 模型缓存 HF_HOME=D:/turtle_audio_src/hf。
用法:
  D:/turtle_audio_src/clapenv/Scripts/python.exe tools/sfx_clap.py --calibrate
  D:/turtle_audio_src/clapenv/Scripts/python.exe tools/sfx_clap.py b1      # 写 .out/sfx_rank/<批次>/clap.tsv
"""
import json
import os
import subprocess
import sys

os.environ.setdefault("HF_HOME", r"D:/turtle_audio_src/hf")
import numpy as np
import torch
from transformers import ClapModel, ClapProcessor

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
REF_DIR = os.path.join(ROOT, ".out", "blackbox", "sfx")
MODEL = "laion/larger_clap_general"
SR = 48000
BAD = {"music": "a piece of music with melody and drums", "speech": "a person speaking words",
	"silence": "silence, nothing audible", "hiss": "constant hiss and static noise"}
## 标定用: 黑箱原声 → 它属于哪一类(按文件名与拆包记录人工标的), 类别 → 描述
CAL_CLASSES = {
	"hit": "a short punchy impact hit sound effect",
	"shot": "a short laser gun shot sound effect",
	"slash": "a sword slash whoosh sound effect",
	"explosion": "an explosion blast sound effect",
	"click": "a short user interface button click",
	"win": "a cheerful victory fanfare jingle",
	"lose": "a sad game over jingle",
	"coin": "coins jingling reward sound",
	"levelup": "a magical level up chime",
	"bubble": "bubbles popping",
}
CAL_FILES = {
	"hit8": "hit", "sfx_boss_skill_orb_hit_1": "hit", "sfx_boss_skill_orb_hit_3": "hit", "hammer_c": "hit",
	"player_shoot": "shot", "sfx_shoot": "shot", "sfx_boss_skill_laser_hit_1": "shot",
	"sfx_boss_skill_slash_hit": "slash", "sfx_boss_skill_spin_hit": "slash",
	"etfx_explosion_gas": "explosion", "etfx_explosion_sparkle2": "explosion",
	"sfx_ui_click": "click", "sfx_ui_click_2": "click", "pickclick": "click",
	"sfx_level_clear": "win", "sfx_game_over": "lose",
	"coin_bag_reward": "coin", "player_levelup": "levelup", "sfx_ui_levelup": "levelup", "bubble": "bubble",
}

_m = None
_p = None


def model():
	global _m, _p
	if _m is None:
		_m = ClapModel.from_pretrained(MODEL).eval()
		_p = ClapProcessor.from_pretrained(MODEL)
	return _m, _p


def decode(path: str) -> np.ndarray:
	raw = subprocess.run([FF, "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
		capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.float32).copy()


@torch.no_grad()
def embed_audio(paths: list) -> np.ndarray:
	m, p = model()
	out = []
	for i in range(0, len(paths), 8):
		xs = [decode(q) for q in paths[i:i + 8]]
		inp = p(audio=xs, sampling_rate=SR, return_tensors="pt", padding=True)
		e = m.get_audio_features(**inp)
		e = e if isinstance(e, torch.Tensor) else e.pooler_output
		out.append(torch.nn.functional.normalize(e, dim=-1).numpy())
	return np.concatenate(out)


@torch.no_grad()
def embed_text(texts: list) -> np.ndarray:
	m, p = model()
	inp = p(text=texts, return_tensors="pt", padding=True)
	e = m.get_text_features(**inp)
	e = e if isinstance(e, torch.Tensor) else e.pooler_output
	return torch.nn.functional.normalize(e, dim=-1).numpy()


def calibrate() -> int:
	names = [n for n in CAL_FILES if os.path.exists(os.path.join(REF_DIR, n + ".wav"))]
	A = embed_audio([os.path.join(REF_DIR, n + ".wav") for n in names])
	cls = list(CAL_CLASSES)
	T = embed_text([CAL_CLASSES[c] for c in cls])
	B = embed_text(list(BAD.values()))
	ok = 0
	for i, n in enumerate(names):
		s = A[i] @ T.T
		top = cls[int(np.argmax(s))]
		bad = A[i] @ B.T
		hit = top == CAL_FILES[n]
		ok += hit
		print("%s %-28s 应=%-9s 判=%-9s 置信差 %.3f · 最像坏样本 %s %.3f" % ("✓" if hit else "✗", n, CAL_FILES[n], top,
			float(np.sort(s)[-1] - np.sort(s)[-2]), list(BAD)[int(np.argmax(bad))], float(np.max(bad))))
	print("标定: %d / %d 认对 (随机猜 = %.0f%%)" % (ok, len(names), 100.0 / len(cls)))
	return 0


def score_batch(batch: str) -> int:
	cdir = os.path.join(SRC, "eleven", batch)
	man = json.load(open(os.path.join(cdir, "manifest.json"), encoding="utf-8"))
	tab = {it["key"]: it for it in json.load(open(os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json"), encoding="utf-8"))["batches"][batch]}
	fns = sorted(f for f in man if os.path.exists(os.path.join(cdir, f)))
	A = embed_audio([os.path.join(cdir, f) for f in fns])
	B = embed_text(list(BAD.values()))
	keys = sorted({man[f]["key"] for f in fns})
	T = embed_text([tab[k]["text"] for k in keys])
	kidx = {k: i for i, k in enumerate(keys)}
	odir = os.path.join(ROOT, ".out", "sfx_rank", batch)
	os.makedirs(odir, exist_ok=True)
	rows = ["cand\tkey\tmatch\tbest_other_key\tbest_other\tbad_kind\tbad"]
	for i, f in enumerate(fns):
		k = man[f]["key"]
		s = A[i] @ T.T
		own = float(s[kidx[k]])
		s2 = s.copy(); s2[kidx[k]] = -9
		j = int(np.argmax(s2))
		bad = A[i] @ B.T
		rows.append("%s\t%s\t%.4f\t%s\t%.4f\t%s\t%.4f" % (f, k, own, keys[j], float(s2[j]), list(BAD)[int(np.argmax(bad))], float(np.max(bad))))
	open(os.path.join(odir, "clap.tsv"), "w", encoding="utf-8").write("\n".join(rows) + "\n")
	## 声音向量也存下来: 挑选时查「不同来源选中的声音互相太像」(sfx_rank.py --pick 读, 不需要 torch)
	np.save(os.path.join(odir, "clap_emb.npy"), A)
	open(os.path.join(odir, "clap_emb.txt"), "w", encoding="utf-8").write("\n".join(fns) + "\n")
	print("分母: %d 个候选 · %d 条描述 → %s" % (len(fns), len(keys), os.path.join(odir, "clap.tsv")))
	return 0


if __name__ == "__main__":
	if "--calibrate" in sys.argv:
		sys.exit(calibrate())
	sys.exit(score_batch(sys.argv[1] if len(sys.argv) > 1 else "b1"))
