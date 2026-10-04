"""门禁离线审计: run-tests.sh 里每一条起 Godot 跑场景(res://...tscn)的命令,
都必须同时带 TURTLE_BACKEND=" " 与 TURTLE_SUPABASE=" "(整层停用后端)。

2026-10-04 查实: 冒烟那一行漏了这两个变量 ⇒ 每跑一次门禁就用全新存档匿名登录生产库,
在线上 auth.users 里造一个垃圾账号(本机 + CI; 9-27 起每天 25~125 个, 零真人)。
只读, 不起 Godot。
"""
import io, re, sys
sys.stdout.reconfigure(encoding="utf-8")

P = "run-tests.sh"
src = io.open(P, encoding="utf-8").read()
# 把反斜杠续行拼成一条逻辑命令
logical = re.sub(r"\\r?\n", " ", src).splitlines()
cmds = [l for l in logical
        if re.search(r'"\$GODOT"', l) and re.search(r"res://\S+\.tscn", l) and not l.lstrip().startswith("#")]
bad = [c.strip()[:160] for c in cmds
       if 'TURTLE_BACKEND=" "' not in c or 'TURTLE_SUPABASE=" "' not in c]
print("  起 Godot 跑场景的命令: %d 条" % len(cmds))
if len(cmds) < 2:
    print("  [FAIL] 分母过小: 至少应有测试池与冒烟两条, 扫描本身坏了")
    sys.exit(1)
for b in bad:
    print("  [FAIL] 没关后端(会打生产库): " + b)
if bad:
    print("FAILED: %d 条" % len(bad))
    sys.exit(1)
print("ALL OK — 门禁里每个跑场景的 Godot 进程都关掉了后端")
