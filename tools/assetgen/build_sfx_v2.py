# -*- coding: utf-8 -*-
"""tools/assetgen/build_sfx_v2.py — 音效 v2 成品: 定选的候选 → 进游戏的 WAV + 事件表(2026-11-05 · 全部重做, 对标云顶)。
由来: 用户 11-05「全部都要重做，全部都要达到云顶的标准」「原来的音效要删掉」。
  定选在 tools/sfx_pick_v2.py(.out/sfx_v2/picks.json); 本脚本只做确定性加工(同一批候选重跑逐字节相同):
  ① 解码(ffmpeg) → 单声道 44.1 kHz(战斗内声音: 云顶 / LoL 的单位音效是单声道, 3D 定位); 全局大事件与界面保留立体声
  ② 30 Hz 高通(只去听不见、吃余量的次低频)
  ③ 裁头: 包络第一次高于 峰值−45 dB 之前 5 ms 起; 裁尾: 最后一次高于 峰值−55 dB 之后 20 ms, 25 ms 余弦淡出, 3 ms 淡入
  ④ 响度: 有声段(峰值−30 dB 以上)RMS 拉到这一类的目标(TARGET_RMS); 峰值不许超过 −1 dBFS(超了整体降, 不削波)
  ⑤ 写 assets/audio/sfx/v2/<事件>__<k>.wav, 事件表 scripts/gamedata/sfx_events.gd(EVENTS 第一变体 / VARIANTS 全部变体)
响度目标(有声段 RMS, dBFS) —— 层次对标 11-04 云顶实录(大事件比平时声高 6.9 dB):
  普攻出手 −20 · 普攻命中 −16 · 暴击 −15 · 技能放出 −13 · 技能命中 −15 · 装备 −15 · 全局按条
  游戏里普攻层再压 ATK_GAIN(−7 dB) ⇒ 大招放出比普攻命中高 ≈ 10 dB, 普通技能 ≈ 7 dB。
用法: python tools/assetgen/build_sfx_v2.py [--check]
"""
import argparse
import json
import os
import subprocess
import sys
import wave
import zlib

import numpy as np
## scipy 只在加工音频时用(butter / sosfilt); 审计 check() 只读成品, CI 环境没有 scipy ⇒ 不在模块顶上导入(11-05 CI 红过一次)


def butter(*a, **k):
	from scipy.signal import butter as _b
	return _b(*a, **k)


def sosfilt(*a, **k):
	from scipy.signal import sosfilt as _s
	return _s(*a, **k)

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
FF = os.environ.get("FFMPEG", r"D:/oopz/ffmpeg.exe")
CAND = os.path.join(SRC, "eleven", "v2")
CAND_R2 = os.path.join(SRC, "eleven", "v2r2")   # 第二轮候选(定选里文件名前缀 r2__)
CAND_R3 = os.path.join(SRC, "eleven", "v2r3")   # 第三轮候选(前缀 r3__)
CAND_PS = os.path.join(SRC, "eleven", "v2ps")   # 被动候选(文件名 ps_* 本身唯一)
CAND_DT = os.path.join(SRC, "eleven", "v2dt")   # 阵亡候选(g_death_enemy / g_death_ally)
CAND_R4 = os.path.join(SRC, "eleven", "v2r4")   # 第四轮候选(前缀 r4__)
CAND_R5 = os.path.join(SRC, "eleven", "v2r5")   # 第五轮候选(前缀 r5__)
PICKS = os.path.join(ROOT, ".out", "sfx_v2", "picks.json")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx", "v2")
EVENTS_GD = os.path.join(ROOT, "scripts", "gamedata", "sfx_events.gd")
SR = 44100
TARGET_RMS = {"ba_cast": -20.0, "ba_hit": -16.0, "crit": -15.0, "sk_cast": -13.0, "sk_hit": -15.0, "equip": -15.0, "passive": -15.0, "death": -16.0}
TARGET_KEY = {"g_hit": -16.0, "g_crit": -15.0, "g_skill_hit": -16.0, "g_shield_gain": -17.0, "g_shield_break": -16.0,
	"g_heal": -18.0, "g_death": -14.0, "g_death_enemy": -15.0, "g_death_ally": -14.0, "g_rebirth": -13.0, "g_dodge": -20.0, "fight_start": -12.0, "victory": -14.0,
	"defeat": -15.0, "ui_click": -20.0, "ui_confirm": -19.0, "ui_back": -21.0, "reward_normal": -16.0, "reward_rare": -14.0,
	"level_up": -15.0, "coin_buy": -17.0, "match_found": -15.0, "studio_intro": -16.0}
STEREO = {"fight_start", "victory", "defeat", "reward_normal", "reward_rare", "level_up", "match_found", "studio_intro"}
## 开场标的「点灯」在 0.22 秒(scripts/scenes/studio_intro.gd TIMING.ignite): 主冲击(包络最高点)对齐到这一刻
ALIGN_PEAK = {"studio_intro": 0.22}
## 定长(秒): 开场标的音效长度 = 时间轴总长 TIMING.end(verify_studio_intro ⑦)
FIX_LEN = {"studio_intro": 2.5}
CEIL = 10 ** (-1.0 / 20)


def decode(path: str, ch: int) -> np.ndarray:
	raw = subprocess.run([FF, "-v", "error", "-i", path, "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"],
		capture_output=True, check=True).stdout
	return np.frombuffer(raw, dtype=np.float32).reshape(-1, ch).astype(np.float64)


def env_db(mono: np.ndarray) -> tuple:
	hop = int(SR * 0.005)
	n = len(mono) // hop
	e = np.sqrt(np.mean(mono[: n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)
	return 20 * np.log10(e + 1e-9), hop


## ── 母带均衡(按类别往 Riot 同类的频谱形状拉, 每处最多 ±6 dB) ───────────────────────────────────────
## 两轮合挑后选中的仍有偏差(sfx_pick_v2 报告, 选中中位 vs Riot 中位):
##   普攻命中 低频占比 0.58(0.33)、质心 1269 Hz(2220) · 暴击 0.75 / 746(0.35 / 2225) ⇒ 偏闷(手机喇叭上更糊)
##   技能放出 低频 0.17(0.41)、质心 2215(1141) ⇒ 偏薄
## 做法(商业通行的母带步骤): 量这一条的低频占比, 比 Riot 同类多 ⇒ 160 Hz 低架切、3 kHz 高架提清晰度; 少 ⇒ 150 Hz 低架补。
RIOT_LOW = {"ba_cast": 0.12, "ba_hit": 0.35, "crit": 0.35, "sk_cast": 0.41, "sk_hit": 0.46, "equip": 0.35}


def _shelf(f0: float, gain_db: float, high: bool) -> np.ndarray:
	"""RBJ 搁架滤波器(S = 1) → 二阶节 sos。"""
	A = 10 ** (gain_db / 40)
	w0 = 2 * np.pi * f0 / SR
	cw, sw = np.cos(w0), np.sin(w0)
	alpha = sw / 2 * np.sqrt(2)
	sa = 2 * np.sqrt(A) * alpha
	if high:
		b0 = A * ((A + 1) + (A - 1) * cw + sa); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - sa)
		a0 = (A + 1) - (A - 1) * cw + sa; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - sa
	else:
		b0 = A * ((A + 1) - (A - 1) * cw + sa); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - sa)
		a0 = (A + 1) + (A - 1) * cw + sa; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - sa
	return np.array([[b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0]])


def low_ratio(mono: np.ndarray) -> float:
	P = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2 + 1e-18
	f = np.fft.rfftfreq(len(mono), 1 / SR)
	return float(P[f < 150].sum() / P.sum())


def tone_match(x: np.ndarray, cat: str) -> np.ndarray:
	want = RIOT_LOW.get(cat)
	if want is None:
		return x
	lo = low_ratio(x.mean(axis=1))
	if lo > want + 0.12:
		g = -min(6.0, (lo - want) * 12.0)
		x = sosfilt(_shelf(160.0, g, False), x, axis=0)
		x = sosfilt(_shelf(3000.0, min(4.0, -g * 0.6), True), x, axis=0)
	elif lo < want - 0.15:
		x = sosfilt(_shelf(150.0, min(6.0, (want - lo) * 12.0), False), x, axis=0)
	return x


## ── 低频垫底层(sweetener): 技能放出偏薄(低频占比 0.12 vs Riot 0.41)⇒ 在起音处垫一层低通 300 Hz 的分量 ─────────────────
## 素材 = ElevenLabs v2sw 批(tools/assetgen/sfx_v2_table.sweeteners); 只用质心 120~380 Hz 的 6 个(纯 40 Hz 次低频手机放不出, 不用)。
## 按技能名固定挑一层(crc32), 增益从 −30 dB 往上试, 到低频占比 ≥ SW_GOAL 为止(上限 −4 dB)。用了哪层、多大增益记进定选记录。
CAND_SW = os.path.join(SRC, "eleven", "v2sw")
SW_USE = ["sw_body_3", "sw_body_4", "sw_swell_1", "sw_swell_2", "sw_swell_3", "sw_swell_4"]
SW_TRIGGER = 0.25
SW_GOAL = 0.30
SW_CAP_DB = -6   # 垫层最多比主体 RMS 低 6 dB(第一版 −4 dB 卡上限的太多, 怕把主体糊住)
_sw_cache = {}
DMG_CASTS = set()   # main() 里按「有没有 skh_ 命中声」填: sk_<技能> 的技能会造成伤害


def _sw_layer(name: str, ch: int) -> np.ndarray:
	k = (name, ch)
	if k not in _sw_cache:
		y = decode(os.path.join(CAND_SW, name + ".mp3"), ch)
		y = sosfilt(butter(4, 300.0, btype="lowpass", fs=SR, output="sos"), y, axis=0)
		e, hop = env_db(y.mean(axis=1))
		i0 = int(np.argmax(e > e.max() - 30)) * hop
		_sw_cache[k] = y[i0:]
	return _sw_cache[k]


def sweeten(x: np.ndarray, key: str) -> tuple:
	"""返回 (加了垫底层的 x, 记录)。低频够的原样返回。"""
	lo = low_ratio(x.mean(axis=1))
	if lo >= SW_TRIGGER:
		return x, None
	name = SW_USE[zlib.crc32(key.encode("utf-8")) % len(SW_USE)]
	layer = _sw_layer(name, x.shape[1])
	e, hop = env_db(x.mean(axis=1))
	on = int(np.argmax(e > e.max() - 20)) * hop
	rms_x = np.sqrt(np.mean(x ** 2)) + 1e-12
	base = np.zeros_like(x)
	n = min(len(layer), len(x) - on)
	base[on:on + n] = layer[:n]
	base *= rms_x / (np.sqrt(np.mean(base ** 2)) + 1e-12)
	for g_db in range(-30, SW_CAP_DB + 1, 2):
		y = x + base * 10 ** (g_db / 20)
		if low_ratio(y.mean(axis=1)) >= SW_GOAL:
			return y, {"layer": name, "gain_db": g_db, "low_before": round(lo, 3)}
	return x + base * 10 ** (SW_CAP_DB / 20), {"layer": name, "gain_db": SW_CAP_DB, "low_before": round(lo, 3)}


def process(x: np.ndarray, target: float, cat: str = "", key: str = "", rec: dict = None) -> np.ndarray:
	sos = butter(2, 30.0, btype="highpass", fs=SR, output="sos")
	x = sosfilt(sos, x, axis=0)
	x = tone_match(x, cat)
	if cat == "sk_cast" and key in DMG_CASTS:   # 只给造成伤害的技能垫分量; 治疗 / 护盾 / 增益类不垫(钟声垫一层闷响不对)
		x, r = sweeten(x, key)
		if r is not None and rec is not None:
			rec.update(r)
	mono = x.mean(axis=1)
	edb, hop = env_db(mono)
	pk = float(edb.max())
	a = np.where(edb > pk - 45)[0]
	b = np.where(edb > pk - 55)[0]
	s0 = max(0, a[0] * hop - int(SR * 0.005))
	s1 = min(len(x), (b[-1] + 1) * hop + int(SR * 0.020))
	x = x[s0:s1].copy()
	nf_out = min(len(x) // 3, int(SR * 0.025))
	nf_in = min(len(x) // 10, int(SR * 0.003))
	if nf_out > 0:
		x[-nf_out:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, nf_out)))[:, None]
	if nf_in > 0:
		x[:nf_in] *= np.linspace(0, 1, nf_in)[:, None]
	mono = x.mean(axis=1)
	edb, hop = env_db(mono)
	act = np.repeat(edb > edb.max() - 30, hop)[: len(mono)]
	rms = 20 * np.log10(np.sqrt(np.mean(mono[: len(act)][act] ** 2)) + 1e-12)
	x *= 10 ** ((target - rms) / 20)
	pk = float(np.max(np.abs(x)))
	if pk > CEIL:
		x *= CEIL / pk
	return x


def align_peak(x: np.ndarray, at: float) -> np.ndarray:
	"""把包络最高点挪到 at 秒: 前面不够就补静音, 多了就裁(裁掉的部分加 3 ms 淡入)。"""
	edb, hop = env_db(x.mean(axis=1))
	pk = int(np.argmax(edb)) * hop
	want = int(at * SR)
	if pk < want:
		return np.concatenate([np.zeros((want - pk, x.shape[1])), x])
	y = x[pk - want:].copy()
	n = min(len(y) // 10, int(SR * 0.003))
	if n > 0:
		y[:n] *= np.linspace(0, 1, n)[:, None]
	return y


def fix_len(x: np.ndarray, sec: float) -> np.ndarray:
	"""裁或补到正好 sec 秒; 裁的话最后 0.3 秒余弦淡出。"""
	n = int(round(sec * SR))
	if len(x) < n:
		return np.concatenate([x, np.zeros((n - len(x), x.shape[1]))])
	y = x[:n].copy()
	f = min(n // 4, int(SR * 0.3))
	y[-f:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, f)))[:, None]
	return y


def write_wav(path: str, x: np.ndarray) -> None:
	q = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
	w = wave.open(path, "wb")
	w.setnchannels(x.shape[1])
	w.setsampwidth(2)
	w.setframerate(SR)
	w.writeframes(q.tobytes())
	w.close()


PICKS_V2 = os.path.join(ROOT, "tools", "assetgen", "sfx_picks_v2.json")   # 定选记录(进仓库; 审计不需要仓库外的源文件)
LEDGER = os.path.join(ROOT, "tools", "assetgen", "sfx_licenses.md")
PROMPTS_V2 = os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json")
LIC = "ElevenLabs 音效生成(Starter 订阅, 含商用授权; 2026-11-04 起; v2 全部重做 2026-11-05) · 生成参数与请求号见 <SFX_SRC>/eleven/v2(及 v2r2)/manifest.json"
## 旧音效(11-05 全部删掉): 不许再出现
OLD = ["assets/audio/sfx/ev", "assets/audio/sfx/hit-physical.wav", "assets/audio/sfx/hit-crit.wav", "assets/audio/sfx/heal.wav",
	"assets/audio/sfx/shield-gain.wav", "assets/audio/sfx/shield-break.wav", "assets/audio/sfx/defeat.wav", "assets/audio/sfx/rebirth.wav",
	"assets/audio/sfx/queue_found.wav", "assets/audio/sfx/studio_intro.wav"]
PIXEL_WORDS = ["pixel", "8-bit", "8bit", "chiptune", "retro", "cartoon", "bleep"]
MAX_DUR = 3.2


def rms_peak_dur(path: str) -> tuple:
	w = wave.open(path, "rb")
	ch, n = w.getnchannels(), w.getnframes()
	x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64).reshape(-1, ch) / 32768.0
	w.close()
	mono = x.mean(axis=1)
	edb, hop = env_db(mono)
	act = np.repeat(edb > edb.max() - 30, hop)[: len(mono)]
	rms = 20 * np.log10(np.sqrt(np.mean(mono[: len(act)][act] ** 2)) + 1e-12)
	peak = 20 * np.log10(float(np.max(np.abs(x))) + 1e-12)
	return rms, peak, n / float(SR), ch


def events_gd_text(ev_vars: dict) -> str:
	lines = ["class_name SfxEvents", "extends RefCounted",
		"## 音效事件表(tools/assetgen/build_sfx_v2.py 生成, 勿手改)。2026-11-05 全部重做, 对标云顶 / LoL(用户「全部都要达到云顶的标准」)。",
		"## 事件名: bas_<龟> 普攻出手 · bah_<龟> 普攻命中 · crit_<龟> 暴击 · sk_<技能类型> 放出 · skh_<技能类型> 命中 · eq_<编号> 装备 · g_* 公共 · 界面 / 结算。",
		"## Audio 启动时整张表载入; VARIANTS 里多于一个的, 每次播放随机挑一个(不连续重复同一个) —— 云顶普攻 / 命中 3~4 个变体轮换。",
		"", "const EVENTS := {"]
	for k in sorted(ev_vars):
		lines.append('\t"%s": "%s",' % (k, ev_vars[k][0]))
	lines += ["}", "", "const VARIANTS := {"]
	for k in sorted(ev_vars):
		lines.append('\t"%s": [%s],' % (k, ", ".join('"%s"' % q for q in ev_vars[k])))
	lines += ["}", ""]
	return "\n".join(lines)


def ev_vars_of(picks: dict) -> dict:
	return {k: ["res://assets/audio/sfx/v2/%s__%d.wav" % (k, i) for i in range(1, len(p["sel"]) + 1)] for k, p in sorted(picks.items()) if p["sel"]}


def check() -> int:
	"""门禁审计(tools/sfx_audit.py 调): 只读仓库里的东西。"""
	bad = []
	picks = json.load(open(PICKS_V2, encoding="utf-8"))
	ev_vars = ev_vars_of(picks)
	n_files = 0
	for k, paths in ev_vars.items():
		cat = picks[k]["cat"]
		target = TARGET_KEY.get(k, TARGET_RMS.get(cat, -15.0))
		for q in paths:
			f = os.path.join(ROOT, q[6:])
			if not os.path.exists(f):
				bad.append("缺文件 %s" % q)
				continue
			n_files += 1
			rms, peak, dur, ch = rms_peak_dur(f)
			if peak > -0.9:
				bad.append("%s 峰值 %.2f dBFS 超过 −0.9" % (q, peak))
			if not (abs(rms - target) <= 1.0 or (rms < target and peak > -1.2)):
				bad.append("%s 有声段 RMS %.1f dB, 目标 %.1f ±1(峰值没卡住)" % (q, rms, target))
			if dur > MAX_DUR:
				bad.append("%s 时长 %.2f 秒超过 %.1f" % (q, dur, MAX_DUR))
			if ch != (2 if k in STEREO else 1):
				bad.append("%s 声道 %d 不对" % (q, ch))
	gd = open(EVENTS_GD, encoding="utf-8").read()
	if gd != events_gd_text(ev_vars):
		bad.append("scripts/gamedata/sfx_events.gd 与定选表不一致(重跑 build_sfx_v2.py)")
	on_disk = {fn for fn in os.listdir(OUT_DIR) if fn.endswith(".wav")} if os.path.isdir(OUT_DIR) else set()
	want = {os.path.basename(q) for v in ev_vars.values() for q in v}
	bad += ["v2 目录里有定选表外的文件 %s" % f for f in sorted(on_disk - want)]
	ledger = open(LEDGER, encoding="utf-8").read() if os.path.exists(LEDGER) else ""
	bad += ["授权台账缺 %s" % f for f in sorted(want) if ("| %s |" % f) not in ledger]
	bad += ["旧音效还在: %s" % o for o in OLD if os.path.exists(os.path.join(ROOT, o))]
	tab = json.load(open(PROMPTS_V2, encoding="utf-8"))
	low = (tab.get("style", "") + " " + " ".join(it["text"] for it in tab["batches"]["v2"])).lower()
	bad += ["描述表里出现「%s」(像素 / 卡通一类的字眼不许再有)" % w for w in PIXEL_WORDS if w in low]
	print("分母: %d 条事件 · %d 个变体文件" % (len(ev_vars), n_files))
	for b in bad[:60]:
		print("  [FAIL]", b)
	if bad or n_files < 300:
		print("FAIL x%d" % max(1, len(bad)))
		return 1
	print("ALL OK —— 音效 v2 产物与定选表一致(文件齐 / 响度在目标 ±1 dB 或峰值卡住 / 峰值与时长不超上限 / 声道 / 授权台账全覆盖 / 事件表一致 / 旧音效已删 / 描述无像素字眼)")
	return 0


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--check", action="store_true", help="只核对(= tools/sfx_audit.py)")
	a = ap.parse_args()
	if a.check:
		return check()
	picks = json.load(open(PICKS, encoding="utf-8"))
	man = json.load(open(os.path.join(CAND, "manifest.json"), encoding="utf-8"))
	mans = {}
	for bn, d in (("v2", CAND), ("v2r2", CAND_R2), ("v2r3", CAND_R3), ("v2ps", CAND_PS), ("v2dt", CAND_DT), ("v2r4", CAND_R4), ("v2r5", CAND_R5)):
		mp = os.path.join(d, "manifest.json")
		mans[bn] = (d, json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {})
	os.makedirs(OUT_DIR, exist_ok=True)
	keep_picks = {}
	sw_used = {}
	DMG_CASTS.update(k for k in picks if k.startswith("sk_") and ("skh_" + k[3:]) in picks)
	made = 0
	led = ["# 游戏音效授权台账（tools/assetgen/build_sfx_v2.py 生成，勿手改）", "", LIC, "",
		"| 产物 | 事件 | 来源候选 | 生成描述 |", "|---|---|---|---|"]
	for key in sorted(picks):
		p = picks[key]
		if not p["sel"]:
			continue
		target = TARGET_KEY.get(key, TARGET_RMS.get(p["cat"], -15.0))
		ch = 2 if key in STEREO else 1
		for k, wavname in enumerate(p["sel"], start=1):
			bn = {"r2__": "v2r2", "r3__": "v2r3", "r4__": "v2r4", "r5__": "v2r5"}.get(wavname[:4]) or ("v2ps" if wavname.startswith("ps_") else ("v2dt" if wavname.startswith(("g_death_enemy", "g_death_ally")) else "v2"))
			mp3name = (wavname[4:] if bn in ("v2r2", "v2r3", "v2r4", "v2r5") else wavname)[:-4] + ".mp3"
			out = "%s__%d.wav" % (key, k)
			swrec = {}
			y = process(decode(os.path.join(mans[bn][0], mp3name), ch), target, p["cat"], key, swrec)
			if swrec:
				sw_used[out] = swrec
			if key in ALIGN_PEAK:
				y = align_peak(y, ALIGN_PEAK[key])
			if key in FIX_LEN:
				y = fix_len(y, FIX_LEN[key])
			write_wav(os.path.join(OUT_DIR, out), y)
			made += 1
			led.append("| %s | %s | %s/%s | %s |" % (out, key, bn, mp3name, str(mans[bn][1].get(mp3name, {}).get("text", "")).replace("|", "/")))
		sel_scores = [s for s in p["all"] if os.path.basename(s["file"]) in p["sel"]]
		keep_picks[key] = {"cat": p["cat"], "zh": p["zh"], "sel": p["sel"],
			"score": [{k2: s[k2] for k2 in ("text", "riot", "champ", "pen", "pix", "score", "dur", "low", "cent")} for s in sel_scores]}
		sw = {o: sw_used[o] for o in ("%s__%d.wav" % (key, k) for k in range(1, len(p["sel"]) + 1)) if o in sw_used}
		if sw:
			keep_picks[key]["sweetener"] = sw
	ev_vars = ev_vars_of(keep_picks)
	keep = {os.path.basename(q) for v in ev_vars.values() for q in v}
	for fn in os.listdir(OUT_DIR):
		if fn.endswith(".wav") and fn not in keep:
			os.remove(os.path.join(OUT_DIR, fn))
			if os.path.exists(os.path.join(OUT_DIR, fn + ".import")):
				os.remove(os.path.join(OUT_DIR, fn + ".import"))
	open(PICKS_V2, "w", encoding="utf-8", newline="\n").write(json.dumps(keep_picks, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
	if sw_used:
		led += ["", "低频垫底层(技能放出偏薄时垫在起音处, 同一授权): " + " · ".join(sorted({v["layer"] + ".mp3" for v in sw_used.values()})) + " (<SFX_SRC>/eleven/v2sw/)"]
	open(LEDGER, "w", encoding="utf-8", newline="\n").write("\n".join(led) + "\n")
	print("垫了低频层的技能放出: %d 条" % len(sw_used))
	open(EVENTS_GD, "w", encoding="utf-8", newline="\n").write(events_gd_text(ev_vars))
	print("写出 %d 个文件 · %d 条事件 → %s" % (made, len(ev_vars), OUT_DIR))
	return 0


if __name__ == "__main__":
	sys.exit(main())
