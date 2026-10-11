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
# ★2026-10-11 全项目通读: tools/ 下起 Godot 跑测试场景的 Python 工具(变异验证器等)同样不许打生产库 ——
#   mutate_verify.py / mutation_probe.py 原来只关一半或都没关, 而本审计只扫 run-tests.sh, 看不见它们。
#   判据: 文件里出现「GODOT 可执行 + .tscn」就必须同时出现 TURTLE_BACKEND 与 TURTLE_SUPABASE 两个关闭。
import glob as _glob, os as _os
## 本来就是去量正式服的只读探针(不进门禁、手动跑) —— 名单必须写理由, 不许拿来放水。
_PROD_OK = {
    "probe_finals_server.py": "周日赛程的线上体检探针: 它的用途就是连正式服只读核对 finals_* 函数",
}
py_hits = 0
for _f in sorted(_glob.glob(_os.path.join("tools", "**", "*.py"), recursive=True)):
    if _os.path.basename(_f) == "gate_offline_audit.py":
        continue
    try:
        _t = io.open(_f, encoding="utf-8", errors="replace").read()
    except Exception:
        continue
    if not re.search(r"GODOT", _t) or not re.search(r"\.tscn", _t) or "--headless" not in _t:
        continue
    py_hits += 1
    if _os.path.basename(_f) in _PROD_OK:
        continue
    if not (re.search(r"TURTLE_BACKEND[\"'\]]*\s*[=:]\s*[\"']\s[\"']", _t) and re.search(r"TURTLE_SUPABASE[\"'\]]*\s*[=:]\s*[\"']\s[\"']", _t)):
        bad.append("[tools] " + _f.replace(_os.sep, "/") + " 起 Godot 跑场景但没同时关掉 TURTLE_BACKEND / TURTLE_SUPABASE")
        print("  [FAIL] 没关后端(会打生产库): " + bad[-1])
print("  tools/ 下起 Godot 跑场景的 Python 工具: %d 个" % py_hits)
if bad:
    print("FAILED: %d 条" % len(bad))
    sys.exit(1)
print("ALL OK — 门禁里每个跑场景的 Godot 进程都关掉了后端")
