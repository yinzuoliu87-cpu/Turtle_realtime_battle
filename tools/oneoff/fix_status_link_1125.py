"""把 status_sources.gd 里 123 两条 link 的 [\s\S] 改成 GDScript 字符串里该写的 [\\s\\S](11-25)"""
p = "scripts/scenes/codex/status_sources.gd"
b = open(p, "rb").read().decode("utf-8")
old = r'"link": "\"p2eq_123\": _summon_skeleton[\s\S]*func _wave_hit"'
new = r'"link": "\"p2eq_123\": _summon_skeleton[\\s\\S]*func _wave_hit"'
n = b.count(old)
b = b.replace(old, new)
open(p, "wb").write(b.encode("utf-8"))
print("replaced", n)
