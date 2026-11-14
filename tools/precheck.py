# -*- coding: utf-8 -*-
"""tools/precheck.py —— 推之前的本机预检, 过了 ship.py 才放行(2026-11-06)。

用户 11-06「你是每次跑个十分钟 CI, 然后找个小问题, 然后又跑个十分钟 CI …我不觉得这是很好的呀。」
当天 4 轮红全是小问题(夹具写死满命数 / 脚本没登记例外 / 函数基线没挪 / 测试收尾删键), 3 轮本机就能查出来 ——
原因是本机只跑「相关测试」, 而这些红来自**扫全仓**的测试和审计器, 不属于「相关」。

跑三样, 全过才在 .out/precheck_ok 记下这个提交:
  ① run-tests.sh 登记的全部审计器
  ② 全仓扫描类测试(源码里遍历目录的 verify_*: 这类最容易被任何改动碰红, 而且大多很快)
  ③ 和这次改动有关的测试: 改动里的 verify_* 本身 + 源码提到改动文件路径 / class_name 的 verify_*(枢纽文件不展开)
  ④ 数据整表扫描(2026-11-14 补): 改了 data/*.json ⇒ 把那份数据整张遍历的 verify_*(`for x in DataRegistry.<字段>`)也选上。
     由来: 11-14 连发弩机正文多一组分档, verify_equip_tier_labels(逐件对标签条数)只读 DataRegistry.phase2_equipment,
     既不提文件路径也不提改动的 .gd ⇒ 预检没选, 红在 CI 上。读这份数据的测试有 51 条(超枢纽线), 只选「整表遍历」那 46 条。
判定与门禁同一套: 退出码 0 + 日志有 ALL PASS + 不命中 run-tests.sh 的 FATAL 正则。
★11-14 用户「CI 每次都跑了太多遍了…你得思考一下」, 补两处省轮次:
  · 工作区不干净在**开头**就退(原来跑完几分钟才说「这次不算数」);
  · 测试红了先**单独重跑那一条**(并行下偶发段错误 / 超时, 单跑复现不出的就是偶发): 单跑过 ⇒ 记「偶发」不拦,
    写进 .out/precheck_flaky.tsv 留账; 单跑还红才算红(审计器早就这样, 测试原来没有 ⇒ 为一条偶发整套重跑)。

用法:
  python tools/precheck.py             # 比 origin/main 的改动; 全过写印记
  python tools/precheck.py --list      # 只列要跑哪些、预计多久
  JOBS=4 python tools/precheck.py      # 默认并行 8
★只测「我碰到的 + 扫全仓的」, 不是全套: 全套仍由 CI 跑。CI 红了别整轮重来: 本机 SHARD=k/8 bash run-tests.sh 只跑红的那片。
"""
import concurrent.futures as cf
import glob
import os
import re
import subprocess
import sys
import tempfile
import time

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT_BIN", r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe")
STAMP = os.path.join(ROOT, ".out", "precheck_ok")
SCAN = re.compile(r"get_files_at|DirAccess\.open|_walk\(")
HUB_MAX = 25       # 被超过这么多条测试提到的文件 / 类算枢纽
## 不管改了什么都跑: 钉函数基线 / 规则指纹的, 改枢纽文件时最容易红, 而枢纽过滤会把它们漏掉(11-06 backend.gd 基线就是这么红在 CI 上的)
ALWAYS = ["verify_gauntlet_online_queue", "verify_rules_fingerprint"]


def git(*a):
	return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace").stdout.strip()


def changed():
	git("fetch", "-q", "origin", "main")
	base = git("merge-base", "origin/main", "HEAD")
	names = set(git("diff", "--name-only", base, "HEAD").splitlines())
	names |= set(git("status", "--porcelain").replace('"', "").split("\n")) and {l[3:].strip() for l in git("status", "--porcelain").splitlines() if len(l) > 3}
	return sorted(n for n in names if n)


def read(p):
	try:
		return open(p, encoding="utf-8", errors="replace").read()
	except OSError:
		return ""


def pick(files):
	"""返回 {测试名: 入选原因}。★枢纽文件(被很多测试提到, 如主战斗文件)不算「相关」: 否则选出来就是全套, 占满机器又不多抓问题。"""
	keys = []
	for f in files:
		if f.endswith(".gd") and f.startswith(("scripts/", "autoload/")):
			keys.append(f)
			m = re.search(r"^class_name\s+(\w+)", read(os.path.join(ROOT, f)), re.M)
			if m:
				keys.append(m.group(1))
	srcs = {os.path.basename(p)[:-3]: read(p) for p in sorted(glob.glob(os.path.join(ROOT, "tests", "verify_*.gd")))}
	hub = {k for k in keys if sum(1 for t in srcs.values() if k in t) > HUB_MAX}
	data_scan = data_scan_patterns(files)
	## ★枢纽文件不按文件展开, 但按「这次改了它里面哪些函数 / 常量 / 装备」展开(2026-11-14 加):
	##   改 043 时 equip_system.gd 是枢纽 ⇒ 点名 `_eq_water_wave` 的 verify_line_band_vfx、按类型表遍历全部法器的
	##   verify_staff_actives_fire 都没被选上, 红在 CI 上(用户 11-06「CI 不是用来找小错的」)。
	syms, eq_ids = hub_symbols([f for f in files if f in hub])
	syms = {s for s in syms if sum(1 for t in srcs.values() if s in t) <= HUB_MAX}
	out = {}
	for name, src in srcs.items():
		if name in ALWAYS:
			out[name] = "必跑"
		elif "tests/%s.gd" % name in files:
			out[name] = "改动本身"
		elif SCAN.search(src):
			out[name] = "全仓扫描"
		elif any(p.search(src) for p, _ in data_scan):
			out[name] = "数据整表扫描 " + next(f for p, f in data_scan if p.search(src))
		elif eq_ids and EQ_TABLE.search(src):
			out[name] = "装备整表遍历(改了 %s)" % ",".join(sorted(eq_ids)[:3])
		else:
			for k in keys:
				if k not in hub and k in src:
					out[name] = "提到 " + k
					break
			else:
				for s in sorted(syms):
					if re.search(r"\b%s\b" % re.escape(s), src):
						out[name] = "提到枢纽里改动的 " + s
						break
	if hub:
		print("枢纽文件不展开: " + ", ".join(sorted(hub)) + (" · 但按改动的符号展开 %d 个" % len(syms) if syms else ""))
	return out


## 测试里「按装备表把全部装备 / 某一类装备挨个跑」的写法: 改了某件装备的玩法就要跑它们
EQ_TABLE = re.compile(r"p2eq-types\.json|phase2-equipment\.json|for\s+\w+\s+in\s+DataRegistry\.equip\w*|EquipStats\.STATS\b")


def hub_symbols(hub_files):
	"""枢纽文件这次 diff 里动到的函数名 / 常量名 / 装备 id(取 hunk 头所在函数 + 改动行里定义或点名的)。"""
	syms, eq_ids = set(), set()
	if not hub_files:
		return syms, eq_ids
	base = git("merge-base", "origin/main", "HEAD")
	for f in hub_files:
		diff = git("diff", "-U0", base, "--", f) + "\n" + git("diff", "-U0", "--", f)
		for line in diff.splitlines():
			if line.startswith("@@"):
				m = re.search(r"@@[^@]*@@\s*(?:static\s+)?func\s+(\w+)", line)
				if m:
					syms.add(m.group(1))
			elif line[:1] in "+-" and not line.startswith(("+++", "---")):
				for m in re.finditer(r"\b(?:func|const|var)\s+(\w+)", line):
					syms.add(m.group(1))
				eq_ids.update(re.findall(r"\bp2eq_\d{3}\b", line))
	syms = {s for s in syms if len(s) >= 6}   # 太短的名字(如 `u` / `dir`)到处都是, 不当信号
	return syms, eq_ids


def data_scan_patterns(files):
	"""改动里的 data/*.json ⇒ [(「整张遍历这份数据」的正则, 文件名)]。字段名从 DataRegistry 的载入行读(不手抄一份对照表)。"""
	reg = read(os.path.join(ROOT, "autoload", "DataRegistry.gd"))
	out = []
	for f in files:
		if not (f.startswith("data/") and f.endswith(".json")):
			continue
		for m in re.finditer(r"^\s*(\w+)\s*=\s*_load_json_\w+\(\"res://%s\"\)" % re.escape(f), reg, re.M):
			out.append((re.compile(r"for\s+\w+\s+in\s+DataRegistry\.%s\b" % m.group(1)), f))
	return out


def seconds():
	sec = {}
	for line in read(os.path.join(ROOT, "tests", "golden", "test_seconds.tsv")).splitlines():
		parts = line.split("\t")
		if len(parts) >= 2 and not line.startswith("#"):
			try:
				sec[parts[0]] = float(parts[1])
			except ValueError:
				pass
	return sec


def frames(name, runner):
	## 与 run-tests.sh frames_for 同一套: case 分支可以是 `a|b|c) echo N ;;`(11-08: 原来只认单个名字, 多名字共用一条的
	##   verify_stream_coverage 掉到默认值; 默认原来写 4000 正好盖住了这个缺陷)。都没登记 ⇒ 与 `*) echo 500` 一致。
	for m in re.finditer(r"^\s*([\w|]+)\)\s*echo\s+(\d+)", runner, re.M):
		if name in m.group(1).split("|"):
			return m.group(2)
	return "500"


def run_test(name, fatal, budget):
	u = tempfile.mkdtemp(prefix="pc_")
	## 与 run-tests.sh 的 run_one 同一套环境(11-08: 这里原来多设 SHIP=1, 会关掉审阅台演示劫持 ⇒ verify_two_head_anim 在预检里假红、CI 里绿)
	env = dict(os.environ, APPDATA=u, XDG_DATA_HOME=u, TURTLE_SUPABASE=" ", TURTLE_BACKEND=" ", QUIET="1")
	env.pop("SHIP", None)
	log = os.path.join(ROOT, ".out", "gate", name + ".log")
	os.makedirs(os.path.dirname(log), exist_ok=True)
	t0 = time.time()
	try:
		r = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "res://tests/%s.tscn" % name, "--quit-after", budget],
		                   capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=900)
		out, rc = r.stdout + r.stderr, r.returncode
	except subprocess.TimeoutExpired:
		out, rc = "超时", 124
	hits = [l for l in out.splitlines() if fatal.search(l)]
	ok = rc == 0 and "ALL PASS" in out and not hits
	if ok:
		if os.path.exists(log):
			os.remove(log)
	else:
		open(log, "w", encoding="utf-8").write(out)
	fails = [l.strip()[:150] for l in out.splitlines() if "[FAIL]" in l] + [l.strip()[:150] for l in hits[:2]]
	return name, ok, time.time() - t0, fails[:3]


def audits(runner):
	bad = []
	tools = sorted(set(re.findall(r'^run_audit "(tools/[^"]+)"', runner, re.M)))
	## 有的审计器要调 sh: 从 PowerShell 起的时候 PATH 里没有。★要 Git\usr\bin 的真 sh, 不是 Git\bin 的启动器:
	##   启动器会把系统路径插到最前面, 盖掉 beta_server_selftest 假的 date / systemctl(四种环境对比实测)
	env = dict(os.environ, PYTHONIOENCODING="utf-8", PATH=r"C:\Program Files\Git\usr\bin;" + os.environ.get("PATH", ""))

	def one(t):
		try:
			r = subprocess.run([sys.executable, t], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=300)
			return t, r.returncode, (r.stdout.strip().splitlines() or [""])[-1][:110]
		except subprocess.TimeoutExpired:
			return t, 124, "超时"

	with cf.ThreadPoolExecutor(6) as ex:
		for t, rc, last in ex.map(one, tools):
			if rc != 0:
				bad.append(t)
	## 并行时偶发红(本来就不是并行写的审计器): 单独重跑一次, 还红才算红
	final = []
	for t in bad:
		_, rc, last = one(t)
		if rc != 0:
			final.append((t, last))
	return len(tools), final


def main():
	runner = read(os.path.join(ROOT, "run-tests.sh"))
	fatal = re.compile(re.search(r"^FATAL='([^']*)'", runner, re.M).group(1))
	files = changed()
	picked = pick(files)
	sec = seconds()
	names = sorted(picked, key=lambda n: sec.get(n, 8.5))
	total = sum(sec.get(n, 8.5) for n in names)
	jobs = int(os.environ.get("JOBS", "8"))
	print("改动 %d 个文件 · 选中 %d 条测试(全仓扫描 %d) · 单核合计约 %d 秒, 并行 %d ≈ %d 秒" % (
		len(files), len(names), sum(1 for v in picked.values() if v == "全仓扫描"), total, jobs, total / jobs))
	if "--list" in sys.argv:
		for n in names:
			print("  %-44s %6.0f 秒  %s" % (n, sec.get(n, 8.5), picked[n]))
		return 0
	## ★开头就查工作区(11-14): 印记记的是提交号, 工作区不干净时跑完也不作数 —— 别先跑几分钟再说
	if git("status", "--porcelain"):
		print("✗ 工作区还有没提交的改动: 先提交(或把没认可的改动挪出去)再跑预检 —— 印记只认提交")
		for l in git("status", "--porcelain").splitlines()[:12]:
			print("   ", l)
		return 1
	n_aud, bad_aud = audits(runner)
	print("审计器 %d 个, 红 %d 个" % (n_aud, len(bad_aud)))
	for t, last in bad_aud:
		print("  ✗", t, last)
	bad = []
	with cf.ThreadPoolExecutor(jobs) as ex:
		futs = [ex.submit(run_test, n, fatal, frames(n, runner)) for n in names]
		for f in cf.as_completed(futs):
			n, ok, dt, fails = f.result()
			if not ok:
				bad.append(n)
				print("  ✗ %s(%d 秒)" % (n, dt))
				for x in fails:
					print("      ", x)
	## ★红了的测试单独重跑一次(11-14): 并行下的偶发段错误 / 超时单跑复现不出 —— 单跑过 ⇒ 记偶发不拦, 单跑还红才算红
	if bad:
		still = []
		for n in bad:
			_, ok2, dt2, fails2 = run_test(n, fatal, frames(n, runner))
			if ok2:
				print("  ↺ %s 单独重跑通过(%d 秒) ⇒ 记为偶发, 不拦" % (n, dt2))
				with open(os.path.join(ROOT, ".out", "precheck_flaky.tsv"), "a", encoding="utf-8") as fh:
					fh.write("%s\t%s\t%s\n" % (time.strftime("%Y-%m-%d %H:%M"), git("rev-parse", "--short", "HEAD"), n))
			else:
				still.append(n)
				print("  ✗ %s 单独重跑仍红" % n)
				for x in fails2:
					print("      ", x)
		bad = still
	if bad or bad_aud:
		print("FAIL 测试红 %d / %d, 审计器红 %d —— 修好再推(日志在 .out/gate/)" % (len(bad), len(names), len(bad_aud)))
		return 1
	head = git("rev-parse", "HEAD")
	dirty = git("status", "--porcelain")
	if dirty:
		print("★工作区还有没提交的改动: 这次预检不算数, 提交之后再跑")
		return 1
	os.makedirs(os.path.dirname(STAMP), exist_ok=True)
	open(STAMP, "w", encoding="utf-8").write(head)
	print("ALL OK — 预检通过 %s(%d 条测试 + %d 个审计器)" % (head[:8], len(names), n_aud))
	return 0


if __name__ == "__main__":
	sys.exit(main())
