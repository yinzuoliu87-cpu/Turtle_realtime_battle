# -*- coding: utf-8 -*-
"""2026-11-11 联调「绑定直接登录失败、浏览器不开」: 内测主站确认页只有 http://45.125.219.123:8088, App 只肯打开 https。
修法(只动内测): Caddy arena-beta 站点 redir /game/link → 主站 http 确认页; 内测网关 env 加 MAINSITE_LINK_BASE=https://arena-beta.turtlearena.xyz。
这个脚本把仓库里两处跟上:
  ① tools/mainsite_deploy.py 写 env 时, 主站根地址是 http ⇒ 自动带上 MAINSITE_LINK_BASE(否则下次部署会把手工加的那行冲掉)
  ② tools/mainsite_beta_smoke.py S3: 确认页地址认「主站地址开头」或「我们网关地址开头」两种
CRLF / LF 保留原样。"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
	p = os.path.join(ROOT, rel)
	b = open(p, "rb").read()
	crlf = b"\r\n" in b
	s = b.decode("utf-8").replace("\r\n", "\n")
	for o, n in pairs:
		if s.count(o) != 1:
			raise SystemExit("%s: 命中 %d 次: %s" % (rel, s.count(o), o[:80]))
		s = s.replace(o, n)
	if crlf:
		s = s.replace("\n", "\r\n")
	open(p, "wb").write(s.encode("utf-8"))
	print("改好", rel)


patch("tools/mainsite_deploy.py", [
	('def env_file_bytes(base, secret, stamp, label="内测服"):\n'
	 '    """服务器上 env-mainsite(-beta) 的全部内容（只在内存里；经 ssh 标准输入写过去）。"""\n',
	 'def env_file_bytes(base, secret, stamp, label="内测服", host=""):\n'
	 '    """服务器上 env-mainsite(-beta) 的全部内容（只在内存里；经 ssh 标准输入写过去）。\n'
	 '    主站根地址是 http（内测主站只有 http://IP:8088）⇒ 加 MAINSITE_LINK_BASE=https://<我们的站点>: App 只肯打开 https 确认页,\n'
	 '    由 Caddy 片段里 arena-beta 那条 redir /game/link 302 到主站 http 确认页（2026-11-11 联调「绑定直接登录失败、浏览器不开」）。"""\n'
	 '    link = ("MAINSITE_LINK_BASE=https://%s\\n" % host) if (host and str(base).startswith("http://")) else ""\n'),
	('"MAINSITE_BASE=%s\\nMAINSITE_HOOK_SECRET=%s\\nMAINSITE_OUTBOX=1\\n" % (label, stamp, base, secret)).encode("utf-8")\n',
	 '"MAINSITE_BASE=%s\\nMAINSITE_HOOK_SECRET=%s\\nMAINSITE_OUTBOX=1\\n%s" % (label, stamp, base, secret, link)).encode("utf-8")\n'),
	('    ctx["env_bytes"] = env_file_bytes(base, secret, ctx["stamp"], b["label"])\n',
	 '    ctx["env_bytes"] = env_file_bytes(base, secret, ctx["stamp"], b["label"], b["host"])\n'),
])
patch("tools/mainsite_beta_smoke.py", [
	('          and str(r.get("url", "")).endswith("/game/link?code=" + code) and (not base or str(r.get("url", "")).startswith(base + "/")),\n',
	 '          and str(r.get("url", "")).endswith("/game/link?code=" + code)\n'
	 '          and (not base or str(r.get("url", "")).startswith(base + "/") or str(r.get("url", "")).startswith(gw + "/")),\n'),
])
