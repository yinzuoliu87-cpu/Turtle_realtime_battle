# -*- coding: utf-8 -*-
"""tools/probe_ghost_shells.py —— 快照到底是「真队伍」还是「空壳」。

★为什么要有这个工具
  2026-09-29 查出: `build_ghost_snapshot` 三个月来产的每一份真人快照,
  `lane_assign` / `equipped` **整个都是空的** —— 玩家打的真人对手是个空壳。
  而这件事**门禁量不到**: 门禁只能证明「函数读对了字段」,
  证明不了「真客户端跑出来的那份快照是好的」。产物才是判据不是中间步骤。

★这个工具回答两个问题(都打分母):
    ① 服务端 `public.ghosts` 里, 每个客户端版本各传了几份, 其中几份是空壳
    ② 本机十窗模拟的池子里, remote/local/种子 各几份, 其中几份是空壳

★★空壳的判据与产品**同一条**: `Backend.ghost_lanes_broken()` 的形状 B ——
  `lane_assign` **在**, 而 top+bottom 一个统领都没有。
  形状 C(压根没有 `lane_assign`)不算坏, 那是老档, 产品也放它过。
  判据抄两份必然落后 ⇒ 这里的注释写明它镜像的是哪个函数, 改那边要改这边。

用法:
    python tools/probe_ghost_shells.py              # 服务端 + 本机池子
    python tools/probe_ghost_shells.py --local      # 只看本机(不要网络/令牌)
    python tools/probe_ghost_shells.py --selftest   # ★先证明它会报: 喂一份空壳
退出码: 0 = 没有空壳(或只看到老档形状C)  /  1 = 有空壳  /  2 = 查不了(令牌等)
"""
import io
import json
import os
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
PROJ = "cjefldecsfpnclhfwriw"
TOKEN_FILE = os.path.join(os.path.expanduser("~"), ".supabase", "access-token")
## ★本机代理会改写 POST body(memory `fb-local-proxy-corrupts-post-body`) ⇒ 一律绕开
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
SIM_ROOT = os.environ.get("SIM_ROOT", r"C:\tmp\turtle-sim10")
POOL_REL = os.path.join("Godot", "app_userdata", "斗龟场 实时版", "ghost_pool.json")


def is_shell(snap):
	"""★镜像 `scripts/net/backend.gd` 的 `ghost_lanes_broken()` —— 形状 B 才算坏。"""
	la = snap.get("lane_assign", None)
	if not isinstance(la, dict):
		return False                      # 形状 C: 没表态, 不是这条管的事
	for k in ("top", "bottom"):
		arr = la.get(k, None)
		if isinstance(arr, list):
			for pid in arr:
				if str(pid).strip() != "":
					return False          # 形状 A: 至少一路有统领
	return True                           # 形状 B: 表了态而一个统领都没有


def sql(q):
	tok = io.open(TOKEN_FILE, encoding="utf-8").read().strip()
	r = urllib.request.Request(
		"https://api.supabase.com/v1/projects/%s/database/query" % PROJ,
		method="POST", data=json.dumps({"query": q}).encode(),
		headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
	return json.loads(OP.open(r, timeout=60).read().decode())


def probe_server():
	"""★判据放在 Python 这一侧而不是写进 SQL —— 与 `is_shell` 同一份代码,
	   SQL 里再抄一遍 jsonb 表达式就是第二份判据(手抄的副本必然落后)。"""
	rows = sql("select client_version, snapshot from public.ghosts")
	if not rows:
		print("  [分母] 服务端 ghosts 行数 0 —— 空检查不是通过")
		return 0, 0
	per = {}
	for r in rows:
		snap = r.get("snapshot") or {}
		if isinstance(snap, str):
			snap = json.loads(snap)
		v = str(r.get("client_version", "?"))
		d = per.setdefault(v, [0, 0])
		d[0] += 1
		if is_shell(snap):
			d[1] += 1
	print("  [分母] 服务端 ghosts 共 %d 行 / %d 个客户端版本" % (len(rows), len(per)))
	print("    %-16s %8s %8s" % ("client_version", "行数", "空壳"))
	bad = 0
	for v in sorted(per, key=lambda k: -per[k][0]):
		n, sh = per[v]
		bad += sh
		print("    %-16s %8d %8d %s" % (v, n, sh, "  ← 全是空壳" if sh == n and n else ""))
	return len(rows), bad


def probe_local():
	print("  [分母] 本机模拟根目录 %s" % SIM_ROOT)
	tot = {"r": 0, "l": 0, "n": 0, "sh": 0, "slots": 0}
	print("    %-6s %8s %10s %10s %10s %8s" % ("槽位", "池子总", "remote", "local", "种子", "空壳"))
	for i in range(1, 11):
		f = os.path.join(SIM_ROOT, "p%02d" % i, POOL_REL)
		if not os.path.exists(f):
			continue
		d = json.load(io.open(f, encoding="utf-8"))
		snaps = [g for arr in (d.get("by_battles") or {}).values() for g in (arr or [])]
		r = l = n = sh = 0
		for g in snaps:
			o = str(g.get("origin", ""))
			if o == "remote":
				r += 1
			elif o == "local":
				l += 1
			else:
				n += 1
			if is_shell(g):
				sh += 1
		print("    %-6s %8d %10d %10d %10d %8d" % ("p%02d" % i, len(snaps), r, l, n, sh))
		tot["r"] += r; tot["l"] += l; tot["n"] += n; tot["sh"] += sh; tot["slots"] += 1
	if tot["slots"] == 0:
		print("    <没有池子文件 —— 没跑过十窗模拟, 这一段跳过>")
		return 0, 0
	print("    %-6s %8s %10d %10d %10d %8d" % ("合计", "", tot["r"], tot["l"], tot["n"], tot["sh"]))
	## ★这条关系是 2026-09-29 那次归因的关键: 空壳数 == remote + local 逐槽相等
	##   ⇒ 真人快照 100% 是空壳而内置种子 100% 是好的。
	print("    ★对照: remote+local = %d, 空壳 = %d %s"
		% (tot["r"] + tot["l"], tot["sh"],
		   "(相等 ⇒ 真人全空壳·种子全好)" if tot["r"] + tot["l"] == tot["sh"] else ""))
	return tot["r"] + tot["l"] + tot["n"], tot["sh"]


def selftest():
	"""★证明这个工具会报 —— 不然「0 个空壳」可能只是它判不出来。"""
	good = {"lane_assign": {"top": ["basic", "stone"], "bottom": ["ice"]}}
	shell = {"lane_assign": {"top": [], "bottom": []}}
	blank = {"lane_assign": {"top": [""], "bottom": []}}
	old = {}
	cases = [("好快照", good, False), ("空壳(形状B)", shell, True),
	         ("只有空字符串的分路", blank, True), ("老档(形状C·没有lane_assign)", old, False)]
	ok = True
	for name, snap, want in cases:
		got = is_shell(snap)
		mark = "OK" if got == want else "**错**"
		if got != want:
			ok = False
		print("  %-28s 期望空壳=%-5s 实测=%-5s %s" % (name, want, got, mark))
	print("ALL OK — 判据会报" if ok else "FAILED — 判据自己是错的")
	return 0 if ok else 1


def main():
	args = sys.argv[1:]
	if "--selftest" in args:
		return selftest()
	total = bad = 0
	if "--local" not in args:
		if not os.path.exists(TOKEN_FILE):
			print("  <没有 %s，服务端这一段查不了>" % TOKEN_FILE)
			return 2
		try:
			t, b = probe_server()
		except Exception as e:
			print("  <服务端查不了: %s>" % e)
			return 2
		total += t; bad += b
		print("")
	t, b = probe_local()
	total += t; bad += b
	print("")
	if total == 0:
		print("FAILED — 一份快照都没量到, 这是空检查不是通过")
		return 1
	if bad:
		print("有空壳: %d / %d 份 —— 这些快照当对手会是一支空队(产品侧 `ghost_lanes_broken` 会拒它们)" % (bad, total))
		return 1
	print("ALL OK — %d 份快照没有空壳" % total)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
