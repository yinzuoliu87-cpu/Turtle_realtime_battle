# -*- coding: utf-8 -*-
"""gen_sfx_elevenlabs.py — 用 ElevenLabs 音效接口按描述表批量出候选（2026-11-04 · A5，用户选 ElevenLabs、已订 Starter）。

由来: 用户听了第一版(库音按伤害类型分)「完全达不到黑箱的水平」; 黑箱的做法 = 每个来源一条专属声音 + 统一响度 + 高频音做变体。
  ⇒ 描述表 tools/assetgen/sfx_prompts.json 按【来源】一条(每只龟的普攻 / 技能、每件装备、胜负、界面…), 每条出 N 个候选,
     再拿黑箱同类原声当尺子量曲线初筛(tools/sfx_rank.py), 最后由用户耳朵定稿 —— 我听不见, 只能量。

★本脚本只把【原始候选】拉到仓库外的源素材目录(SFX_SRC, 默认 D:/turtle_audio_src)/eleven/<批次>/<key>_<n>.mp3,
  并写同目录 manifest.json(每个文件的描述 / 参数 / 时间 / 请求号)。AI 生成不可能逐字节复现 ——
  进游戏的那一步是 tools/assetgen/build_sfx.py(确定性: 从选定的候选解码 → 统一响度 → 写 WAV)。
★已存在的候选文件跳过(中断后重跑只补缺的)。
★key 只从 ~/.config/turtle/secrets/elevenlabs_key.txt 读, 不打印、不进仓库。POST 走 ProxyHandler({}) 绕开本机代理(会改写 body)。

用法:
  python tools/assetgen/gen_sfx_elevenlabs.py b1             # 出 b1 批, 每条 4 个候选
  python tools/assetgen/gen_sfx_elevenlabs.py b1 --n 2 --only atk_basic,victory
  python tools/assetgen/gen_sfx_elevenlabs.py --credits      # 只查额度
"""
import argparse
import concurrent.futures as cf
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROMPTS = os.path.join(ROOT, "tools", "assetgen", "sfx_prompts_v2.json")   # 11-05 起只有 v2 表(旧表 sfx_prompts.json 统一前缀 cartoon pixel-art, 已删)
## 11-05 v2(全部重做): --prompts tools/assetgen/sfx_prompts_v2.json; 每条可带自己的候选数 n
SRC = os.environ.get("SFX_SRC", r"D:/turtle_audio_src")
KEY_FILE = os.path.join(os.path.expanduser("~"), ".config", "turtle", "secrets", "elevenlabs_key.txt")
API = "https://api.elevenlabs.io/v1"
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def key() -> str:
	k = open(KEY_FILE, encoding="utf-8").read().strip()
	assert k.startswith("sk_"), "key 文件内容不像 ElevenLabs key"
	return k


def credits() -> dict:
	req = urllib.request.Request(API + "/user/subscription", headers={"xi-api-key": key()})
	d = json.loads(OPENER.open(req, timeout=30).read())
	return {"tier": d.get("tier"), "used": d.get("character_count"), "limit": d.get("character_limit")}


def generate(text: str, dur: float, influence: float) -> tuple:
	body = json.dumps({"text": text, "duration_seconds": dur, "prompt_influence": influence}).encode("utf-8")
	req = urllib.request.Request(API + "/sound-generation?output_format=mp3_44100_128", data=body, method="POST",
		headers={"xi-api-key": key(), "Content-Type": "application/json", "Accept": "audio/mpeg"})
	for attempt in range(4):
		try:
			r = OPENER.open(req, timeout=120)
			return r.read(), r.headers.get("request-id", "")
		except urllib.error.HTTPError as e:
			msg = e.read()[:300].decode("utf-8", "replace")
			if e.code in (429, 500, 502, 503) and attempt < 3:
				time.sleep(4 * (attempt + 1))
				continue
			raise RuntimeError("HTTP %d %s" % (e.code, msg))
	raise RuntimeError("重试用尽")


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("batch", nargs="?", default="")
	ap.add_argument("--n", type=int, default=4, help="每条几个候选")
	ap.add_argument("--only", default="", help="逗号分隔的 key, 只出这几条")
	ap.add_argument("--influence", type=float, default=0.45, help="prompt_influence(接口默认 0.3; 越高越照字面)")
	ap.add_argument("--workers", type=int, default=3)
	ap.add_argument("--credits", action="store_true")
	ap.add_argument("--prompts", default=PROMPTS, help="描述表路径(v2 = tools/assetgen/sfx_prompts_v2.json)")
	a = ap.parse_args()
	c0 = credits()
	print("额度 %s: 已用 %s / %s" % (c0["tier"], c0["used"], c0["limit"]))
	if a.credits or not a.batch:
		return 0
	tab = json.load(open(a.prompts, encoding="utf-8"))
	style = str(tab.get("styles", {}).get(a.batch, tab.get("style", "")))   # 每批可有自己的风格前缀(v2r2)
	items = tab["batches"][a.batch]
	if a.only:
		keep = set(a.only.split(","))
		items = [it for it in items if it["key"] in keep]
	out_dir = os.path.join(SRC, "eleven", a.batch)
	os.makedirs(out_dir, exist_ok=True)
	man_path = os.path.join(out_dir, "manifest.json")
	man = json.load(open(man_path, encoding="utf-8")) if os.path.exists(man_path) else {}
	jobs = []
	for it in items:
		for i in range(1, int(it.get("n", a.n)) + 1):
			fn = "%s_%d.mp3" % (it["key"], i)
			if not os.path.exists(os.path.join(out_dir, fn)):
				jobs.append((it, fn))
	print("批次 %s: %d 条 × %d 候选, 要出 %d 个(已存在的跳过)" % (a.batch, len(items), a.n, len(jobs)))

	def run(job):
		it, fn = job
		text = (style + ", " + it["text"]) if style else it["text"]
		if len(text) > 450:   # 接口上限 450 字: 超了换短版风格前缀(v2r2 风格长)
			text = ("High-fidelity League of Legends style game sound effect, crisp, balanced, not muddy, no music, no speech, " + it["text"])[:450]
		data, rid = generate(text, float(it["dur"]), a.influence)
		open(os.path.join(out_dir, fn), "wb").write(data)
		return fn, {"key": it["key"], "zh": it.get("zh", ""), "ref": it.get("ref", ""), "text": text,
			"duration_seconds": float(it["dur"]), "prompt_influence": a.influence, "bytes": len(data),
			"request_id": rid, "at": time.strftime("%Y-%m-%d %H:%M:%S")}

	bad = 0
	with cf.ThreadPoolExecutor(max_workers=a.workers) as ex:
		for fut in cf.as_completed([ex.submit(run, j) for j in jobs]):
			try:
				fn, rec = fut.result()
				man[fn] = rec
				print("  ✓", fn, rec["bytes"], "字节", flush=True)
			except Exception as e:
				bad += 1
				print("  ✗", e, flush=True)
	json.dump(man, open(man_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
	c1 = credits()
	print("完成: 成功 %d / 失败 %d · 额度 已用 %s → %s(本次 %s)" % (len(jobs) - bad, bad, c0["used"], c1["used"],
		(c1["used"] or 0) - (c0["used"] or 0)))
	return 1 if bad else 0


if __name__ == "__main__":
	sys.exit(main())
