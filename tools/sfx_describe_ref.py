# -*- coding: utf-8 -*-
"""tools/sfx_describe_ref.py — 用 CLAP 反过来「听」Riot 原声: 一组描述词逐个比, 报这条原声最像哪几个词(2026-11-05)。
由来: 11-05 用户「角色死亡的时候有什么声音？你怎么参考的？」—— 我的描述是凭空编的。逐条尺子重挑后, 阵亡提示 / 治疗 / 复活 / 升级
  与它自己那条云顶原声只有 0.23~0.42 像 ⇒ 写描述前先量原声「听起来像什么」, 按量出来的词写。
用法: D:/turtle_audio_src/clapenv/Scripts/python.exe tools/sfx_describe_ref.py "<文件名正则>" [...]
"""
import glob
import os
import re
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import sfx_clap  # noqa: E402

VOCAB = [
	"a deep boom", "a sub bass drop", "a heavy thud", "a punchy impact", "a crunchy hit", "a metal clang", "a glass shatter", "a bell chime",
	"a soft chime", "a bright sparkle", "a magical shimmer", "a rising magical swell", "a descending magical tone", "a whoosh", "a reverse whoosh",
	"a wind gust", "an electric zap", "a fire burst", "a water splash", "a choir pad", "an orchestral hit", "a short brass fanfare", "a harp gliss",
	"a heartbeat pulse", "a low drone", "a dark rumble", "a ghostly wail", "a monster growl", "a user interface click", "a soft user interface tap",
	"coins jingling", "a cash register", "a power up sound", "a power down sound", "a pop", "a crystal ring", "a wooden knock", "a stone crack",
	"a shield block", "a healing spell", "a resurrection spell", "a level up jingle", "a knockout punch", "a defeat sting", "a victory sting",
	"a synth pluck", "a musical arpeggio", "a gong", "a drum hit", "a cymbal crash", "a magical dust sprinkle", "a dark magic pulse",
]


def main() -> int:
	allf = sorted(glob.glob(os.path.join(ROOT, ".out", "riot_audio", "**", "*.wav"), recursive=True))
	T = sfx_clap.embed_text(VOCAB)
	for rx in sys.argv[1:]:
		fs = [f for f in allf if re.search(rx, os.path.basename(f).lower())][:20]
		if not fs:
			print("== %s: 0 个文件" % rx)
			continue
		E = sfx_clap.embed_audio(fs)
		c = E.mean(axis=0)
		c /= np.linalg.norm(c)
		s = T @ c
		top = np.argsort(-s)[:8]
		print("== %s(%d 个文件): %s" % (rx, len(fs), " · ".join("%s %.3f" % (VOCAB[i], s[i]) for i in top)))
	return 0


if __name__ == "__main__":
	sys.exit(main())
