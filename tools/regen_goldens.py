# -*- coding: utf-8 -*-
"""tools/regen_goldens.py —— 有意改了数值 / 文案 / 对局结果之后, 一条命令把跟着要变的金标全部重算(2026-11-14)。

由来: 用户 11-14「CI 每次都跑了太多遍了…你改了数值，你还有相同的测试，那肯定跑不通啊。然后你又循环，然后再跑 CI…效率很低」。
  当天一批调数, 预检第一遍红在 4 样「改数值必然跟着变」的东西上(文案措辞 / 文案数值 / 护盾台账 / 跨平台确定性摘要),
  CI 又红在分星标签上 —— 全是改完就该一次更新好的, 却靠预检 / CI 一轮一轮替我找。
做法同 Jest `-u` / insta `cargo insta review`: 一条命令重算, 改动在 git diff 里一眼看完, 然后预检只跑一次。

按顺序(每步打印结果; 不该自动认的只报告, 不替人认):
  ① 装备审查表   tools/review_table_sync.py --write          (json 文案的手抄副本)
  ② 文案快照     tools/text_golden.py --update                (data 侧 + .gd 屏幕侧)
  ③ 文案数值     tools/text_value_golden.py --update
  ④ 文案措辞     tools/text_prose_guard.py --update
  ⑤ 护盾台账     tools/shield_duration_audit.py              ★只在「还了债(永久盾变限时)」时销账; 新增永久盾 ⇒ 报告, 不自动认
  ⑥ 规则指纹     tools/rules_fingerprint.py --update          ★它自己核 RULES_VER(没升过就拒写 ⇒ 先去升版本)
  ⑦ 跨平台确定性 data/determinism_cross.json                  跑 verify_determinism_cross, 只把对不上的那几项换成新摘要
  ⑧ 只检查不改   tooltip_number_audit / verify_equip_tier_labels(分星短标签要人写, 对不上只报告)
用法:
  python tools/regen_goldens.py            # 全做
  python tools/regen_goldens.py --skip-det # 跳过 ⑦(要跑 Godot 约 5 分钟; 只改文案、没改对局结果时用)
做完看 `git diff --stat`, 再提交 → `python tools/precheck.py` 一次 → `tools/ship.py`。
"""
import json
import os
import re
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PY = sys.executable
GODOT = os.environ.get("GODOT_BIN", r"C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe")
DET_GOLDEN = os.path.join(ROOT, "data", "determinism_cross.json")


def tool(args, env=None):
	e = dict(os.environ, PYTHONIOENCODING="utf-8")
	if env:
		e.update(env)
	r = subprocess.run([PY] + args, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=e, timeout=1800)
	return r.returncode, (r.stdout + r.stderr).strip()


def last(out, n=1):
	return " / ".join(l.strip() for l in out.splitlines()[-n:])


def godot_test(name, budget):
	u = tempfile.mkdtemp(prefix="rg_")
	env = dict(os.environ, APPDATA=u, XDG_DATA_HOME=u, TURTLE_SUPABASE=" ", TURTLE_BACKEND=" ", QUIET="1")
	env.pop("SHIP", None)
	r = subprocess.run([GODOT, "--headless", "--audio-driver", "Dummy", "--path", ROOT, "res://tests/%s.tscn" % name, "--quit-after", str(budget)],
	                   capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, timeout=1800)
	return r.returncode, r.stdout + r.stderr


def main():
	report = []
	attention = []   # 需要人处理的步骤(★不从报告文字里找符号: 场景名「3★」自带星号, 11-14 因此误报退出码 1)
	## ①~④ 文案类: 直接按事实源重写
	for label, args in (("① 装备审查表", ["tools/review_table_sync.py", "--write"]),
	                    ("② 文案快照", ["tools/text_golden.py", "--update"]),
	                    ("③ 文案数值", ["tools/text_value_golden.py", "--update"]),
	                    ("④ 文案措辞", ["tools/text_prose_guard.py", "--update"])):
		rc, out = tool(args)
		report.append("%s: %s" % (label, last(out)))
	## ⑤ 护盾台账: 只销账, 不替人认新增
	rc, out = tool(["tools/shield_duration_audit.py"])
	if rc == 0:
		report.append("⑤ 护盾台账: 不用动")
	elif "已经不是永久盾" in out and "新增" not in out:
		rc2, out2 = tool(["tools/shield_duration_audit.py"], {"SHIELD_PERM_UPDATE": "1"})
		report.append("⑤ 护盾台账: 销账 —— %s" % last(out2))
	else:
		report.append("⑤ 护盾台账: ★有新增永久盾, 没自动认 —— %s" % last(out, 3))
		attention.append("⑤")
	## ⑥ 规则指纹
	rc, out = tool(["tools/rules_fingerprint.py", "--update"])
	report.append("⑥ 规则指纹: %s" % (last(out) if rc == 0 else "★拒写(先升 RULES_VER?) —— " + last(out, 2)))
	if rc != 0:
		attention.append("⑥")
	## ⑦ 跨平台确定性: 一次跑完, 只换对不上的
	if "--skip-det" in sys.argv:
		report.append("⑦ 跨平台确定性: 跳过(--skip-det)")
	else:
		## 帧预算照 run-tests.sh 的 frames_for(40000); 11-14 写成 12000 时没跑完就截断, 误报「没打出新摘要但也没全过」
		rc, out = godot_test("verify_determinism_cross", 40000)
		new = dict(re.findall(r"\[新摘要\] (.+?)\t([0-9a-f]{64})", out))
		if not new:
			report.append("⑦ 跨平台确定性: 不用动" if "ALL PASS" in out else "⑦ 跨平台确定性: ★没打出新摘要但也没全过, 去看日志")
			if "ALL PASS" not in out:
				attention.append("⑦")
		else:
			raw = open(DET_GOLDEN, "rb").read().decode("utf-8")
			for tag, dig in new.items():
				pat = re.compile(r'("%s"\s*:\s*")[0-9a-f]{64}(")' % re.escape(tag))
				raw, n = pat.subn(lambda m, d=dig: m.group(1) + d + m.group(2), raw)
				assert n == 1, (tag, n)
			json.loads(raw)
			open(DET_GOLDEN, "wb").write(raw.encode("utf-8"))
			report.append("⑦ 跨平台确定性: 换了 %d 项 %s(其余不动; CI 的 Linux 会再核一遍两平台一致)" % (len(new), list(new)))
	## ⑧ 只检查
	rc, out = tool(["tools/tooltip_number_audit.py"])
	report.append("⑧ 文案数值三元组: %s" % ("ALL OK" if rc == 0 else "★要看 —— " + last(out, 3)))
	if rc != 0:
		attention.append("⑧ 三元组")
	rc, out = godot_test("verify_equip_tier_labels", 2000)
	bad = [l.strip() for l in out.splitlines() if "[FAIL]" in l]
	report.append("⑧ 分星短标签: %s" % ("ALL PASS" if "ALL PASS" in out else "★要人补标签 —— " + " | ".join(bad[:3])))
	if "ALL PASS" not in out:
		attention.append("⑧ 标签")
	print("\n".join(report))
	print("\n下一步: git diff --stat 看一眼 → 提交 → python tools/precheck.py(一次) → python tools/ship.py <主题> --wait")
	if attention:
		print("★要人处理: %s" % " ".join(attention))
	return 1 if attention else 0


if __name__ == "__main__":
	sys.exit(main())
