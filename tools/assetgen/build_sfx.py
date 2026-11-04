# -*- coding: utf-8 -*-
"""build_sfx.py — 把定选的音效候选做成游戏里的成品（2026-11-04 · A5; 方案书 docs/plans/20261102b §8.5）。

输入: tools/assetgen/sfx_picks.json(tools/sfx_pick.py 自动定选; 每个事件一个候选文件)
      候选源文件在仓库外: <SFX_SRC>/eleven/<批次>/(tools/assetgen/gen_sfx_elevenlabs.py 拉下来的 ElevenLabs 生成结果)
输出: assets/audio/sfx/ev/<事件>.wav(单声道 44.1 kHz 16 位) + tools/assetgen/sfx_licenses.md(授权台账)
      scripts/gamedata/sfx_events.gd(事件 → 路径表, Audio 读它; 本脚本生成, 勿手改)

处理照黑箱 Demo 拆包实测(按类整组量的中位数, 见 CAT 表):
  ① 裁开头静音(留 3 ms) ② 按黑箱同类最长时长截断 ③ 尾巴淡出 ④ 统一响度(L100 = K 加权最响 100 ms):
     命中锚在我们原有混音(原 hit-physical.wav 的 L100 −11.8), 其余各类与命中的差照黑箱整组实测(见 CAT 表);
     峰值卡在上限, 卡住时以峰值为准(响度可能低于目标, --check 认这种情况)。
确定性: 只用 ffmpeg 解码 → numpy 处理 → 标准 WAV 写出, 同机重跑逐字节相同; --check 不需要源文件(门禁用)。
用法:
  python tools/assetgen/build_sfx.py            # 生成
  python tools/assetgen/build_sfx.py --check    # 只核对产物与定选表一致
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PICKS = os.path.join(ROOT, "tools", "assetgen", "sfx_picks.json")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx", "ev")
## 授权台账是文档不是素材 ⇒ 放 tools/assetgen/(原来写在 assets/ 里, asset_orphan 审计当它是没人引用的素材)
LIC_PATH = os.path.join(ROOT, "tools", "assetgen", "sfx_licenses.md")
EVENTS_GD = os.path.join(ROOT, "scripts", "gamedata", "sfx_events.gd")
SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
SR = 44100
## ★响度一律用 L100(K 加权最响 100 ms, 见 l100 头注)。锚点 = 我们原命中音 hit-physical.wav 的 L100(实测 −11.8), 保持现有混音。
## ★11-04 实机录 2 分钟量出整段 −6.4 LUFS、1200 个 0.1 秒块里 981 个贴顶(削波): 原锚点(原命中音 −11.8)比黑箱命中中位(−16.4)
##   响 4.6 dB, 原来全场命中只响一路时被盖住, 按来源出声后叠起来就爆了 ⇒ 绝对响度也对齐黑箱: 锚点 = 黑箱命中整组 L100 中位数。
##   (游戏里没换掉的旧音效同降 4.6 dB, 见 Audio.LEGACY_GAIN; 全场命中同时最多 2 路, 见 audio_system._sfx_hit; 总线有限幅器兜底。)
ANCHOR = -16.4
## 类 → 与命中的响度差(黑箱同类整组 L100 中位数之差, 11-04 实测) / 峰值上限 / 最长秒数 / 淡出秒数
##   胜利 / 失败不照黑箱(+9.6 / +8.3 会远超峰值上限被硬压): 取我们原失败音 defeat.wav 的 L100(−8.9) ⇒ +2.9, 两者同级。
CAT = {
	"atk": (0.0, -1.0, 0.45, 0.06),
	"click": (-13.7, -8.0, 0.15, 0.03),
	"confirm": (2.4, -1.0, 0.45, 0.06),
	"win": (2.9, -1.0, 3.5, 0.3),
	"lose": (2.9, -1.0, 3.2, 0.3),
	"reward_normal": (3.4, -1.0, 0.9, 0.12),
	"reward_rare": (7.0, -1.0, 1.0, 0.15),
	"levelup": (2.8, -1.0, 1.4, 0.15),
	"coin": (-1.5, -3.0, 0.9, 0.1),
	"popup": (0.4, -1.0, 0.9, 0.1),
}
LIC = "ElevenLabs 音效生成(Starter 订阅, 含商用授权; 2026-11-04 起) · 生成参数与请求号见 <SFX_SRC>/eleven/<批次>/manifest.json"


def decode(path: str) -> np.ndarray:
	raw = subprocess.run([FF, "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
		capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def _biquad(x: np.ndarray, b: tuple, a: tuple) -> np.ndarray:
	y = np.empty_like(x)
	x1 = x2 = y1 = y2 = 0.0
	b0, b1, b2 = b
	a1, a2 = a
	for i in range(len(x)):
		xi = x[i]
		yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2, x1, y2, y1 = x1, xi, y1, yi
		y[i] = yi
	return y


def _kcoef(rate: int) -> tuple:
	"""ITU-R BS.1770 K 加权(高架 +4 dB @1500 Hz + 高通 38 Hz), 按采样率现算系数(pyloudnorm 同一套公式)。"""
	A = 10 ** (4.0 / 40.0)
	w0 = 2 * np.pi * 1500.0 / rate
	al = np.sin(w0) / (2 * (1 / np.sqrt(2)))
	c = np.cos(w0)
	a0 = (A + 1) - (A - 1) * c + 2 * np.sqrt(A) * al
	shelf = ((A * ((A + 1) + (A - 1) * c + 2 * np.sqrt(A) * al) / a0, -2 * A * ((A - 1) + (A + 1) * c) / a0,
		A * ((A + 1) + (A - 1) * c - 2 * np.sqrt(A) * al) / a0), (2 * ((A - 1) - (A + 1) * c) / a0, ((A + 1) - (A - 1) * c - 2 * np.sqrt(A) * al) / a0))
	w0 = 2 * np.pi * 38.0 / rate
	al = np.sin(w0) / (2 * 0.5)
	c = np.cos(w0)
	a0 = 1 + al
	hp = (((1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0), (-2 * c / a0, (1 - al) / a0))
	return shelf, hp


_KC = _kcoef(SR)


def l100(x: np.ndarray) -> float:
	"""短音效的响度: K 加权后最响 100 ms 的均方(LUFS 记法)。
	★为什么不用整段 RMS / R128 瞬时(400 ms): 前者把骰子这类「几下分开的碰撞」中间的空隙算进平均 ⇒ 偏低;
	  后者 400 ms 窗把 0.15 秒的短声和一大截静音平均 ⇒ 越短越低(实测普攻 R128 极差 13.6 LU, 黑箱同长度的 5 个变体 1.6)。
	  人耳对短促声的响度大约按 100 ms 积分 ⇒ 取最响的 100 ms。"""
	y = _biquad(_biquad(x, *_KC[0]), *_KC[1])
	w = int(SR * 0.1)
	h = int(SR * 0.01)
	if len(y) <= w:
		ms = float(np.mean(y ** 2)) * len(y) / w
		return -0.691 + 10 * np.log10(ms + 1e-12)
	c = np.concatenate([[0.0], np.cumsum(y ** 2)])
	idx = np.arange(0, len(y) - w + 1, h)
	ms = (c[idx + w] - c[idx]) / w
	return float(-0.691 + 10 * np.log10(float(ms.max()) + 1e-12))


def active_rms_db(x: np.ndarray) -> float:
	win = int(SR * 0.01)
	n = max(1, len(x) // win)
	env = np.sqrt(np.mean(x[: n * win].reshape(n, win) ** 2, axis=1) + 1e-12)
	edb = 20 * np.log10(env)
	act = np.where(edb > edb.max() - 40)[0]
	seg = x[act[0] * win:(act[-1] + 1) * win]
	return float(20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12))


def process(x: np.ndarray, cat: str) -> np.ndarray:
	rel, peak_db, max_s, fade_s = CAT[cat]
	pk = float(np.max(np.abs(x))) if len(x) else 0.0
	thr = pk * 10 ** (-45 / 20)
	nz = np.where(np.abs(x) > thr)[0]
	i0 = max(0, int(nz[0]) - int(0.003 * SR)) if len(nz) else 0
	i1 = int(nz[-1]) + 1 if len(nz) else len(x)
	x = x[i0:i1]
	x = x[: int(max_s * SR)]
	f_in = min(len(x), int(0.002 * SR))
	x[:f_in] *= np.linspace(0.0, 1.0, f_in, endpoint=False) if f_in else 1.0
	f_out = min(len(x) // 3, int(fade_s * SR))
	if f_out > 0:
		x[-f_out:] *= np.linspace(1.0, 0.0, f_out)
	target = ANCHOR + rel
	lim = 10 ** (peak_db / 20)
	## 先拉到目标响度, 再用限幅器只压超过上限的尖峰(平滑增益: 起 1 ms / 回 40 ms), 最多压 LIM_MAX_DB;
	##   原来直接整体降增益 ⇒ 尖峰大的声音整体变轻, 普攻成品响度极差 14.3 dB(黑箱同一声音 5 个变体 L100 极差 1.6)。
	global LAST_GR
	tot = np.ones_like(x)
	for _ in range(3):
		x = x * 10 ** ((target - l100(x)) / 20)
		y = limit(x, lim)
		m = np.abs(x) > 1e-6
		tot[m] *= np.abs(y[m]) / np.abs(x[m])
		x = y
	## 限幅器三轮累计的最大压缩量(dB)。挑选时 > 6 dB 算不达标(压太狠会削掉起手的脆劲; 我听不见, 只能卡量)。
	LAST_GR = float(-20 * np.log10(max(1e-9, float(tot.min()))))
	if float(np.max(np.abs(x))) > lim:
		x = x * (lim / float(np.max(np.abs(x))))
	return np.clip(x, -1.0, 1.0)


LAST_GR = 0.0
LIM_MAX_DB = 12.0   # 9 时骰子 / 忍者 / 猎人这类全是尖瞬态的拉不到目标, 普攻响度极差 4.8 dB


def limit(x: np.ndarray, lim: float) -> np.ndarray:
	a = np.abs(x)
	need = np.minimum(1.0, lim / np.maximum(a, 1e-12))
	need = np.maximum(need, 10 ** (-LIM_MAX_DB / 20))
	## 前瞻 1 ms 取窗内最小值(增益先到位再遇到尖峰), 再一阶平滑回升 —— 纯 numpy, 确定性
	la = int(0.001 * SR)
	g = need.copy()
	for s in range(1, la + 1):
		g[:-s] = np.minimum(g[:-s], need[s:])
	rel = np.exp(-1.0 / (0.04 * SR))
	out = np.empty_like(g)
	cur = 1.0
	for i in range(len(g)):
		cur = g[i] if g[i] < cur else g[i] + (cur - g[i]) * rel
		out[i] = cur
	return x * out


def write_wav(path: str, x: np.ndarray) -> None:
	pcm = np.round(x * 32767).astype("<i2").tobytes()
	with wave.open(path, "wb") as w:
		w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)


def read_wav(path: str) -> np.ndarray:
	with wave.open(path) as w:
		return np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


def events_gd(picks: dict) -> str:
	lines = ["class_name SfxEvents", "extends RefCounted",
		"## 音效事件 → 文件(tools/assetgen/build_sfx.py 生成, 勿手改; 定选依据见 tools/assetgen/sfx_picks.json)。",
		"## Audio 启动时整张表载入, 按事件名播放(Audio.play_sfx(\"atk_<龟 id>\") 等)。", "",
		"const EVENTS := {"]
	for k in sorted(picks):
		lines.append("\t\"%s\": \"res://assets/audio/sfx/ev/%s.wav\"," % (k, k))
	lines.append("}")
	return "\n".join(lines) + "\n"


def check() -> int:
	pj = json.load(open(PICKS, encoding="utf-8"))
	picks = pj["picks"]
	bad = []
	lic = open(LIC_PATH, encoding="utf-8").read() if os.path.exists(LIC_PATH) else ""
	for k, v in sorted(picks.items()):
		p = os.path.join(OUT_DIR, k + ".wav")
		if not os.path.exists(p):
			bad.append("缺 %s.wav" % k)
			continue
		x = read_wav(p)
		rel, peak_db, max_s, _ = CAT[v["cat"]]
		r = l100(x)
		pk = 20 * np.log10(float(np.max(np.abs(x))) + 1e-12)
		capped = pk >= peak_db - 0.3
		if r > ANCHOR + rel + 1.0 or (r < ANCHOR + rel - 1.0 and not capped):
			bad.append("%s 响度 L100 %.1f 偏离目标 %.1f(峰值 %.1f)" % (k, r, ANCHOR + rel, pk))
		if pk > peak_db + 0.3:
			bad.append("%s 峰值 %.1f dB 超上限 %.1f" % (k, pk, peak_db))
		if len(x) > int(max_s * SR) + 1:
			bad.append("%s 时长 %.2f s 超上限 %.2f" % (k, len(x) / SR, max_s))
		if ("| %s.wav |" % k) not in lic:
			bad.append("授权台账缺 %s.wav" % k)
	want = {k + ".wav" for k in picks}
	extra = sorted(f for f in os.listdir(OUT_DIR) if f.endswith(".wav") and f not in want) if os.path.isdir(OUT_DIR) else []
	bad += ["清单外的文件 %s(没登记来源与授权)" % f for f in extra]
	cur = open(EVENTS_GD, encoding="utf-8").read().replace("\r\n", "\n") if os.path.exists(EVENTS_GD) else ""
	if cur != events_gd(picks):
		bad.append("scripts/gamedata/sfx_events.gd 与定选表不一致(重跑 build_sfx.py)")
	print("[分母] %d 个事件(定选表) · 产物 %d 个" % (len(picks), len(want) - sum(1 for b in bad if b.startswith("缺 "))))
	for b in bad:
		print("  [FAIL] " + b)
	if bad:
		print("FAILED: %d 处" % len(bad))
		return 1
	print("ALL OK —— 音效产物与定选表一致(文件齐 / 响度在目标 ±1 dB 或峰值卡住 / 峰值与时长不超上限 / 授权台账全覆盖 / 事件表一致)")
	return 0


def main() -> int:
	if "--check" in sys.argv:
		return check()
	pj = json.load(open(PICKS, encoding="utf-8"))
	picks = pj["picks"]
	os.makedirs(OUT_DIR, exist_ok=True)
	man = json.load(open(os.path.join(SRC, "eleven", pj["batch"], "manifest.json"), encoding="utf-8"))
	lic = ["# 游戏音效授权台账（tools/assetgen/build_sfx.py 生成，勿手改）", "", LIC, "",
		"| 产物 | 事件 | 来源候选 | 生成描述 |", "|---|---|---|---|"]
	for k, v in sorted(picks.items()):
		x = process(decode(os.path.join(SRC, "eleven", pj["batch"], v["file"])), v["cat"])
		write_wav(os.path.join(OUT_DIR, k + ".wav"), x)
		lic.append("| %s.wav | %s | %s/%s | %s |" % (k, k, pj["batch"], v["file"], man.get(v["file"], {}).get("text", "?").replace("|", "/")))
	open(LIC_PATH, "w", encoding="utf-8").write("\n".join(lic) + "\n")
	open(EVENTS_GD, "w", encoding="utf-8").write(events_gd(picks))
	print("生成 %d 个事件 → %s" % (len(picks), OUT_DIR))
	return check()


if __name__ == "__main__":
	sys.exit(main())
