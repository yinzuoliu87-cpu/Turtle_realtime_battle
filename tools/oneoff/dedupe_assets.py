# -*- coding: utf-8 -*-
"""去重: 内容 md5 相同的一组文件里, 只保留【真被引用】的那份。
引用判定用【路径级】(带扩展名的完整文件名出现在代码/json 里, 或走 pets/<id>.png 动态拼接),
不用主干 —— 因为 "赛博龟" 正好是 pets.json 里的龟【名字】, 主干判定会把 赛博龟.png 误判成活的。
"""
import io, os, json, collections, hashlib

texts = []
for dp, dn, fn in os.walk("."):
    dn[:] = [d for d in dn if d not in (".git", ".godot", "assets", "build", "docs")]
    for f in fn:
        if f.endswith((".gd", ".tscn", ".tres", ".json", ".cfg")):
            texts.append(io.open(os.path.join(dp, f), encoding="utf-8", errors="replace").read())
BLOB = "\n".join(texts)

d = json.load(io.open("data/pets.json", encoding="utf-8"))
ids = {p["id"] for p in (d["pets"] if isinstance(d, dict) else d)}

by = collections.defaultdict(list)
for dp, dn, fn in os.walk("assets"):
    for f in fn:
        if f.endswith(".import"):
            continue
        p = os.path.join(dp, f).replace("\\", "/")
        by[hashlib.md5(open(p, "rb").read()).hexdigest()].append(p)


def path_referenced(p):
    base = os.path.basename(p)
    stem = base.rsplit(".", 1)[0]
    if base in BLOB:      # 完整文件名(带扩展名)出现在代码/json 里
        return True
    if stem in ids:       # 走 SPRITE_DIR + "pets/" + id + ".png"
        return True
    return False


# 自检: shell.png 必判引用; 龟壳v1.png(若还在) 必判未引用
assert path_referenced("assets/sprites/pets/shell.png")
assert not path_referenced("assets/sprites/pets/__假的__.png")

kill = []
manual = []
for k, v in by.items():
    if len(v) < 2:
        continue
    keep = [p for p in v if path_referenced(p)]
    drop = [p for p in v if not path_referenced(p)]
    if keep and drop:
        kill += drop
    elif not keep:
        manual.append(v)

kill = sorted(set(kill))
io.open("c:/tmp/dup_kill.txt", "w", encoding="utf-8").write("\n".join(kill))
L = ["可删重复副本 %d 个, %.2f MB" % (len(kill), sum(os.path.getsize(p) for p in kill) / 1048576)]
L += ["  " + p for p in kill]
L.append("")
L.append("⚠ 整组都没被引用, 交人工: %d 组" % len(manual))
for v in manual:
    L.append("  " + " == ".join(v))
io.open("c:/tmp/dup_report.txt", "w", encoding="utf-8").write("\n".join(L))
print("ok kill=%d manual=%d" % (len(kill), len(manual)))
