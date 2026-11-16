"""裁判机换 ARM · 编排（2026-11-16 · 方案书 docs/plans/20261116c-裁判机换ARM.md §4.2 / §4.3）。

用户 11-16「就现在转」「你能自己就是终止计费，然后在新的那边…开始啥的都你都可以搞搞定吧」⇒ 全程走 Hetzner API + ssh，用户不用动手。
本机跑；Hetzner 令牌只从 ~/.config/turtle/hcloud_token 读，不打印；服务器上的密钥文件只在两台服务器之间直拷。

  status                     旧机 / 新机 / 主 IP 现状（只读）
  unkeys                     旧机删掉 arm-migrate 临时钥匙
  keys                       新机生成临时钥匙 /root/.ssh/from_old，公钥加进旧机 authorized_keys（标记 arm-migrate）
  provision [--final]        把 server/referee/arm_provision.sh 传到新机后台跑（--final = 切换时的最后增量同步）
  log                        看新机装机日志尾巴
  verify [N]                 新机上每个版本抽 N 局（默认 5）已算完的真实对局重算，比胜方 + 指纹（正式服版本查正式服、内测版本查内测服；只读）
  cutover --yes              ①记旧机 enable 清单 ②停旧机全部 turtle-* 与 caddy ③--final 同步 ④主 IP 挪到新机 ⑤新机照清单起服务 ⑥验收
  rollback --yes             新机关机 → 主 IP 挪回旧机 → 旧机开机（旧机服务原本就 enable，开机即起）
  finish --yes               删旧机（停止计费）+ 删旧机 authorized_keys 里的临时钥匙已不必要（旧机已删）+ 新机删 from_old 钥匙
  rehearse-ip --yes          演练挪 IP：开两台临时 cpx22，把 A 的主 IPv4 挪给 B，验 B 用这个 IP 能 ssh，删两台（约 €0.01）
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
OLD_NAME = "turtle-referee-1"
NEW_NAME = os.environ.get("ARM_NEW_NAME", "turtle-referee-2")   # 演练装机时指到临时 x86 机
PROD_IP = "49.13.166.188"
KEY = os.path.expanduser("~/.ssh/turtle_referee")
OUT = os.path.join(ROOT, ".out", "arm_cutover")
OP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def log(msg: str) -> None:
	print("%s %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def hz(method, path, body=None):
	tok = open(os.path.expanduser("~/.config/turtle/hcloud_token"), encoding="utf-8").read().strip()
	data = json.dumps(body).encode() if body is not None else None
	req = urllib.request.Request("https://api.hetzner.cloud/v1" + path, data=data, method=method,
								 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
	try:
		with OP.open(req, timeout=60) as r:
			raw = r.read()
			return r.status, (json.loads(raw) if raw else {})
	except urllib.error.HTTPError as e:
		return e.code, json.loads(e.read() or b"{}")


def server(name):
	st, b = hz("GET", "/servers?name=" + name)
	return (b.get("servers") or [None])[0]


def ssh(ip, cmd, timeout=40, check=True):
	r = subprocess.run(["ssh", "-i", KEY, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
						"-o", "ConnectTimeout=10", "root@" + ip, cmd], capture_output=True, text=True, timeout=timeout,
					   encoding="utf-8", errors="replace")
	if check and r.returncode != 0:
		raise RuntimeError("ssh %s 失败 rc=%d: %s" % (ip, r.returncode, (r.stderr or r.stdout)[-400:]))
	return r.stdout


def ipv4(s):
	return ((s.get("public_net") or {}).get("ipv4") or {}) if s else {}


def wait_status(sid, want, sec=180):
	for _ in range(sec // 3):
		st, b = hz("GET", "/servers/%d" % sid)
		if b["server"]["status"] == want:
			return True
		time.sleep(3)
	raise RuntimeError("机子 %d 等不到 %s" % (sid, want))


def power_off(sid):
	st, b = hz("GET", "/servers/%d" % sid)
	if b["server"]["status"] == "off":
		return
	hz("POST", "/servers/%d/actions/shutdown" % sid)          # 正常关机（ACPI）
	try:
		wait_status(sid, "off", 90)
	except RuntimeError:
		log("正常关机 90 秒没关上 ⇒ 断电")
		hz("POST", "/servers/%d/actions/poweroff" % sid)
		wait_status(sid, "off", 120)


def wait_ip(ip_id, assignee):
	for _ in range(60):
		st, b = hz("GET", "/primary_ips/%d" % ip_id)
		if b["primary_ip"].get("assignee_id") == assignee:
			return
		time.sleep(2)
	raise RuntimeError("主 IP %d 等不到 assignee=%s" % (ip_id, assignee))


def wait_action(kind, resp, sec=120):
	"""等 Hetzner 动作真正跑完（11-16 演练: 只看 assignee 已清空就去绑 ⇒ 403 assignment limit reached, 解绑动作其实还没完）。"""
	st, b = resp
	a = (b or {}).get("action") or {}
	if not a.get("id"):
		return st, b
	for _ in range(sec // 2):
		s2, b2 = hz("GET", "/%s/actions/%d" % (kind, a["id"]))
		if (b2.get("action") or {}).get("status") in ("success", "error"):
			if b2["action"]["status"] == "error":
				raise RuntimeError("%s 动作失败: %s" % (kind, b2["action"].get("error")))
			return st, b
		time.sleep(2)
	raise RuntimeError("%s 动作 %s 秒没跑完" % (kind, sec))


def retry(fn, what, tries=12):
	"""忙 / 锁 / 超限(多半是上一个动作还没收尾)⇒ 隔 5 秒再试, 最多一分钟。"""
	for i in range(tries):
		st, b = fn()
		if st < 300:
			return st, b
		code = ((b or {}).get("error") or {}).get("code")
		if code not in ("locked", "conflict", "resource_limit_exceeded", "rate_limit_exceeded") or i == tries - 1:
			raise RuntimeError("%s 失败 %s %s" % (what, st, b))
		log("%s: %s, 5 秒后重试" % (what, code))
		time.sleep(5)


def move_ipv4(from_id, to_id, delete_to_ip=True):
	"""把 from 机的主 IPv4 挪给 to 机（两台都会被关机；to 机自带的那个 IPv4 删掉）。返回 (挪走的 IP, 它的 id)。"""
	st, b = hz("GET", "/servers/%d" % from_id)
	src = ipv4(b["server"])
	st, b = hz("GET", "/servers/%d" % to_id)
	dst = ipv4(b["server"])
	if not src.get("id"):
		raise RuntimeError("源机没有主 IPv4")
	log("主 IP %s(id %s) 设 auto_delete=false" % (src["ip"], src["id"]))
	retry(lambda: hz("PUT", "/primary_ips/%d" % src["id"], {"auto_delete": False}), "设 auto_delete")
	log("关源机 %d" % from_id)
	power_off(from_id)
	log("从源机解绑")
	wait_action("primary_ips", retry(lambda: hz("POST", "/primary_ips/%d/actions/unassign" % src["id"]), "解绑源 IP"))
	wait_ip(src["id"], None)
	log("关目标机 %d" % to_id)
	power_off(to_id)
	if dst.get("id"):
		log("目标机自带 IPv4 %s 解绑%s" % (dst["ip"], "并删除" if delete_to_ip else ""))
		retry(lambda: hz("PUT", "/primary_ips/%d" % dst["id"], {"auto_delete": False}), "设目标 IP auto_delete")
		wait_action("primary_ips", retry(lambda: hz("POST", "/primary_ips/%d/actions/unassign" % dst["id"]), "解绑目标 IP"))
		wait_ip(dst["id"], None)
		if delete_to_ip:
			retry(lambda: hz("DELETE", "/primary_ips/%d" % dst["id"]), "删目标机自带 IP")
	log("绑到目标机")
	wait_action("primary_ips", retry(lambda: hz("POST", "/primary_ips/%d/actions/assign" % src["id"],
												  {"assignee_id": to_id, "assignee_type": "server"}), "绑定"))
	wait_ip(src["id"], to_id)
	log("开目标机")
	wait_action("servers", retry(lambda: hz("POST", "/servers/%d/actions/poweron" % to_id), "开机"))
	wait_status(to_id, "running")
	return src["ip"], src["id"]


def wait_ssh(ip, sec=240):
	subprocess.run(["ssh-keygen", "-R", ip], capture_output=True)
	for _ in range(sec // 5):
		try:
			return ssh(ip, "hostname", timeout=15)
		except Exception:
			time.sleep(5)
	raise RuntimeError("%s ssh 连不上" % ip)


# ─────────────────────────────── 子命令 ───────────────────────────────

def cmd_status():
	for n in (OLD_NAME, NEW_NAME):
		s = server(n)
		if s:
			print("%s id=%s %s %s %s IPv4=%s(id %s)" % (n, s["id"], s["server_type"]["name"], s["server_type"]["architecture"],
													  s["status"], ipv4(s).get("ip"), ipv4(s).get("id")))
		else:
			print("%s: 没有" % n)
	return 0


def need_new():
	s = server(NEW_NAME)
	if not s:
		raise SystemExit("还没有 %s（等抢货）" % NEW_NAME)
	return s


def cmd_keys():
	new_ip = ipv4(need_new())["ip"]
	pub = ssh(new_ip, "test -f /root/.ssh/from_old || ssh-keygen -q -t ed25519 -N '' -C arm-migrate -f /root/.ssh/from_old; "
					  "cat /root/.ssh/from_old.pub").strip()
	if not pub.startswith("ssh-ed25519 ") or "arm-migrate" not in pub:
		raise SystemExit("新机公钥不对: %r" % pub[:40])
	ssh(PROD_IP, "grep -qF '%s' /root/.ssh/authorized_keys || echo '%s' >> /root/.ssh/authorized_keys" % (pub, pub))
	log("旧机已认新机钥匙（arm-migrate）")
	return 0


def cmd_unkeys():
	"""旧机 authorized_keys 里删掉 arm-migrate 临时钥匙（演练完 / 回退后用）。"""
	n = ssh(PROD_IP, "grep -c arm-migrate /root/.ssh/authorized_keys || true; sed -i '/arm-migrate/d' /root/.ssh/authorized_keys; "
					 "grep -c arm-migrate /root/.ssh/authorized_keys || true").split()
	log("旧机临时钥匙: 删前 %s 行 → 删后 %s 行" % (n[0], n[-1]))
	return 0


def cmd_provision(final):
	new_ip = ipv4(need_new())["ip"]
	subprocess.run(["scp", "-q", "-i", KEY, "-o", "BatchMode=yes", os.path.join(ROOT, "server", "referee", "arm_provision.sh"),
					"root@%s:/root/arm_provision.sh" % new_ip], check=True)
	ssh(new_ip, "sed -i 's/\\r$//' /root/arm_provision.sh; nohup bash /root/arm_provision.sh %s %s > /root/arm_provision.log 2>&1 "
				"< /dev/null & echo started" % (PROD_IP, "--final" if final else ""), timeout=20, check=False)
	log("新机装机已在后台跑（log 子命令看进度）")
	return 0


def cmd_log():
	print(ssh(ipv4(need_new())["ip"], "tail -15 /root/arm_provision.log"))
	return 0


def wait_provision(new_ip, sec=3600):
	for _ in range(sec // 15):
		out = ssh(new_ip, "tail -3 /root/arm_provision.log", check=False)
		if "DONE" in out:
			return True
		if "rror" in out or "失败" in out:
			raise RuntimeError("装机日志有错: " + out)
		time.sleep(15)
	raise RuntimeError("装机 %d 秒没跑完" % sec)


def cmd_verify(n):
	"""每个装着的版本抽 n 局真实对局在新机上重算。"""
	import sb_common as S
	new_ip = ipv4(need_new())["ip"]
	os.makedirs(OUT, exist_ok=True)
	plan = []
	for base, ref in (("/opt/turtle", S.PROD_REF), ("/opt/turtle-beta", S.BETA_REF)):
		vers = json.loads(ssh(new_ip, "VERSIONS_DIR=%s python3 /opt/turtle/referee/referee_poller.py --versions" % base))
		for v in sorted(vers):
			rows = S.query_ro(ref, "select job_id, match_id, kind, meta, season_week, match_key, seed, client_version, level, a_snapshot, "
								   "b_snapshot, result->>'winner' w, result->>'digest' d from referee_jobs where status = 'done' and "
								   "client_version = '%s' and result ? 'digest' order by job_id desc limit %d" % (v, int(n)))
			plan.append((base, v, ref, rows))
	total = same = 0
	bad = []
	for base, v, ref, rows in plan:
		if not rows:
			## 库里没有算完的对局(刚发的版本 / 内测老版本)⇒ 跑这个版本自带的规则指纹门禁: 金标是 Windows x86 生成的, 新机上过 = 跨架构一致
			vdir = "%s/v%s" % (base, v)
			out = ssh(new_ip, "test -f %s/tests/verify_rules_fingerprint.tscn || { echo NO_GATE; exit 0; }; rm -rf /tmp/rf; mkdir -p /tmp/rf; "
							  "cd /tmp; XDG_DATA_HOME=/tmp/rf APPDATA=/tmp/rf HOME=/tmp/rf TURTLE_SUPABASE=' ' timeout 900 /opt/godot/godot "
							  "--headless --audio-driver Dummy --path %s res://tests/verify_rules_fingerprint.tscn --quit-after 12000 2>&1 "
							  "| grep -E 'ALL PASS|FAIL' | tail -2" % (vdir, vdir), timeout=1000, check=False)
			if "NO_GATE" in out:
				log("%s %s: 库里没有算完的对局、工程里也没有指纹门禁 ⇒ 跳过（换完看第一局）" % (base, v))
				continue
			total += 1
			if "ALL PASS" in out and "FAIL" not in out:
				same += 1
				log("%s %s: 库里没有对局 ⇒ 指纹门禁 ALL PASS" % (base, v))
			else:
				bad.append((v, "rules_fingerprint"))
				log("%s %s: 指纹门禁不过: %s" % (base, v, out.strip()[-200:]))
			continue
		jl = os.path.join(OUT, "jobs_%s_%s.jsonl" % (os.path.basename(base), v))
		with open(jl, "w", encoding="utf-8") as f:
			for r in rows:
				key = dict(r["meta"] or {})
				key.update({"week": r["season_week"], "match_key": r["match_key"]})
				f.write(json.dumps({"v": 1, "job_id": r["job_id"], "match_id": r["match_id"], "mode": r["kind"], "key": key,
									"seed": r["seed"], "client_version": r["client_version"], "level": r["level"],
									"a": r["a_snapshot"], "b": r["b_snapshot"]}, ensure_ascii=False) + "\n")
		subprocess.run(["scp", "-q", "-i", KEY, "-o", "BatchMode=yes", jl, "root@%s:/root/verify_jobs.jsonl" % new_ip], check=True)
		out = ssh(new_ip, "cd /root && rm -rf vj && mkdir vj && python3 -c \"import json\nfor l in open('verify_jobs.jsonl'):\n"
						  " j=json.loads(l); json.dump(j, open('vj/%%s.json' %% j['job_id'], 'w'))\" && for f in vj/*.json; do "
						  "WORK_DIR=/tmp/vw VERSIONS_DIR=%s GODOT_BIN=/opt/godot/godot python3 /opt/turtle/referee/referee_poller.py "
						  "--local $f 2>/dev/null | tail -1; done; rm -rf /tmp/vw" % base, timeout=3600)
		got = {}
		for line in out.splitlines():
			try:
				d = json.loads(line)
				got[str(d.get("digest"))] = d
			except ValueError:
				pass
		for r in rows:
			total += 1
			d = got.get(str(r["d"]))
			if d and str(d.get("winner")) == str(r["w"]):
				same += 1
			else:
				bad.append((v, r["job_id"]))
		log("%s %s: %d 局 → 相同 %d" % (os.path.basename(base), v, len(rows), sum(1 for r in rows if str(r["d"]) in got)))
	print("分母 %d 局: 相同 %d · 不同 %d %s" % (total, same, total - same, bad[:10]))
	print("ALL SAME" if total > 0 and same == total else "NOT SAME")
	return 0 if total > 0 and same == total else 1


def cmd_cutover():
	old, new = server(OLD_NAME), need_new()
	if ipv4(old).get("ip") != PROD_IP:
		raise SystemExit("旧机的 IP 不是 %s，停" % PROD_IP)
	os.makedirs(OUT, exist_ok=True)
	new_ip = ipv4(new)["ip"]
	log("① 预同步全部内容（旧机照常跑, 不停服务）")
	cmd_provision(final=False)
	wait_provision(new_ip, 3600)
	t0 = time.time()
	units = ssh(PROD_IP, "systemctl list-unit-files 'turtle-*' caddy.service --state=enabled --no-legend | awk '{print $1}'").split()
	open(os.path.join(OUT, "enabled_units.txt"), "w").write("\n".join(units) + "\n")
	log("旧机 enable 清单 %d 个: %s" % (len(units), " ".join(units)))
	log("② 停旧机服务")
	ssh(PROD_IP, "systemctl stop 'turtle-*.timer'; systemctl stop 'turtle-*.service' caddy; "
				 "systemctl list-units 'turtle-*' caddy.service --state=active --no-legend | wc -l", timeout=180)
	log("③ 最后一次同步（只同步会变的: /etc 配置 + /var/lib 状态; 工程目录在停服务前已预同步）")
	new_ip = ipv4(new)["ip"]
	cmd_provision(final=True)
	wait_provision(new_ip, 1800)
	log("④ 挪主 IP")
	move_ipv4(old["id"], new["id"])
	log("新机 hostname: %s" % wait_ssh(PROD_IP).strip())
	log("⑤ 新机照清单起服务")
	ssh(PROD_IP, "systemctl daemon-reload; systemctl enable --now %s" % " ".join(units), timeout=120)
	time.sleep(20)
	log("停机约 %.0f 秒（从停旧机服务到新机起服务）" % (time.time() - t0))
	return cmd_check()


def cmd_check():
	import sb_common as S
	res = []
	for name, url in (("直播", "https://stream.turtlearena.xyz/healthz"), ("主站网关", "https://arena.turtlearena.xyz/healthz")):
		try:
			with OP.open(urllib.request.Request(url, headers={"User-Agent": "turtle-ops"}), timeout=20) as r:
				res.append((name, r.status == 200, r.status))
		except Exception as e:
			res.append((name, False, str(e)[:80]))
	import socket
	try:
		socket.create_connection((PROD_IP, 8443), timeout=10).close()
		res.append(("大陆中转 8443", True, "connect ok"))
	except OSError as e:
		res.append(("大陆中转 8443", False, str(e)[:80]))
	for nm, ref in (("正式裁判心跳", S.PROD_REF), ("内测裁判心跳", S.BETA_REF)):
		r = S.query_ro(ref, "select worker, extract(epoch from now() - seen_at)::int s from referee_workers order by seen_at desc limit 1")
		ok = bool(r) and int(r[0]["s"]) < 60
		res.append((nm, ok, r[0] if r else None))
	active = ssh(PROD_IP, "systemctl list-units 'turtle-*' caddy.service --state=failed --no-legend | wc -l; uname -m").split()
	res.append(("没有起不来的服务", active[0] == "0", "failed=%s 架构=%s" % (active[0], active[-1])))
	for nm, ok, info in res:
		print("  [%s] %s  %s" % ("OK" if ok else "FAIL", nm, info))
	good = all(ok for _, ok, _ in res)
	print("ALL OK" if good else "有项不过 —— 看上面；要回退就 rollback --yes")
	return 0 if good else 1


def cmd_rollback():
	old, new = server(OLD_NAME), need_new()
	if ipv4(new).get("ip") != PROD_IP:
		raise SystemExit("主 IP 不在新机上，不用回退")
	st, b = hz("GET", "/primary_ips?ip=" + PROD_IP)
	pid = b["primary_ips"][0]["id"]
	log("关新机")
	power_off(new["id"])
	hz("POST", "/primary_ips/%d/actions/unassign" % pid)
	wait_ip(pid, None)
	power_off(old["id"])
	hz("POST", "/primary_ips/%d/actions/assign" % pid, {"assignee_id": old["id"], "assignee_type": "server"})
	wait_ip(pid, old["id"])
	hz("POST", "/servers/%d/actions/poweron" % old["id"])
	wait_status(old["id"], "running")
	log("旧机 hostname: %s" % wait_ssh(PROD_IP).strip())
	return cmd_check()


def cmd_finish():
	old, new = server(OLD_NAME), need_new()
	if ipv4(new).get("ip") != PROD_IP:
		raise SystemExit("主 IP 还不在新机上，不删旧机")
	ssh(PROD_IP, "rm -f /root/.ssh/from_old /root/.ssh/from_old.pub; echo ok")
	st, b = hz("DELETE", "/servers/%d" % old["id"])
	log("删旧机 %s → %s（从现在起不再计费）" % (OLD_NAME, st))
	return 0 if st in (200, 201, 204) else 1


def cmd_rehearse_ip():
	ids, moved, ip_ids = [], None, []
	try:
		for loc in ("nbg1", "fsn1", "hel1"):         # 两台必须同一机房(主 IP 只能同机房挪)
			got = []
			for nm in ("arm-rehearse-a", "arm-rehearse-b"):
				st, b = hz("POST", "/servers", {"name": nm, "server_type": "cpx22", "image": "ubuntu-24.04", "location": loc,
												"ssh_keys": ["turtle-referee"], "labels": {"purpose": "arm-rehearse"}})
				if st in (200, 201):
					got.append(b["server"]["id"])
					ip_ids.append(ipv4(b["server"]).get("id"))
			ids += got
			if len(got) == 2:
				break
			for i in got:
				hz("DELETE", "/servers/%d" % i)
			ids = [i for i in ids if i not in got]
		if len(ids) != 2:
			raise RuntimeError("哪个机房都开不出两台演练机")
		for i in ids:
			wait_status(i, "running")
		st, b = hz("GET", "/servers/%d" % ids[0])
		ip_a = ipv4(b["server"])["ip"]
		log("A=%s 等 ssh" % ip_a)
		wait_ssh(ip_a)
		ip, moved = move_ipv4(ids[0], ids[1])
		host = wait_ssh(ip).strip()
		log("挪完后 %s 上是 %s" % (ip, host))
		ok = host == "arm-rehearse-b"
		print("REHEARSE OK" if ok else "REHEARSE FAIL")
		return 0 if ok else 1
	finally:
		for i in ids:
			hz("DELETE", "/servers/%d" % i)
		## 演练机的 IP 设过 auto_delete=false ⇒ 删机不会带走, 要单独删(否则每月计费); 中途出错也照删
		for pid in [i for i in ip_ids if i]:
			for _ in range(30):
				st, b = hz("GET", "/primary_ips/%d" % pid)
				if st == 404 or b["primary_ip"].get("assignee_id") is None:
					break
				time.sleep(3)
			if st != 404 and b["primary_ip"]["ip"] != PROD_IP:
				st, _b = hz("DELETE", "/primary_ips/%d" % pid)
				log("删演练 IP %s → %s" % (b["primary_ip"]["ip"], st))
		log("演练机与 IP 已清")


if __name__ == "__main__":
	sys.stdout.reconfigure(encoding="utf-8")
	a = sys.argv[1:]
	yes = "--yes" in a
	if not a:
		print(__doc__)
		sys.exit(2)
	c = a[0]
	if c in ("cutover", "rollback", "finish", "rehearse-ip") and not yes:
		sys.exit("%s 会关机 / 挪 IP / 删机，要加 --yes" % c)
	fn = {"status": cmd_status, "keys": cmd_keys, "unkeys": cmd_unkeys, "log": cmd_log, "cutover": cmd_cutover, "rollback": cmd_rollback,
		  "finish": cmd_finish, "rehearse-ip": cmd_rehearse_ip, "check": cmd_check}
	if c == "provision":
		sys.exit(cmd_provision("--final" in a))
	if c == "verify":
		sys.exit(cmd_verify(int(a[1]) if len(a) > 1 and a[1].isdigit() else 5))
	if c in fn:
		sys.exit(fn[c]())
	print(__doc__)
	sys.exit(2)
