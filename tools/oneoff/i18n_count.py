"""只读: 数要翻译的中文量(代码字符串字面量 / data json / 场景文件)。"""
import os
import re
import sys

ROOT = sys.argv[1]
os.chdir(ROOT)
cjk = re.compile(r"[一-鿿]")
lit = re.compile(r'"((?:[^"\\]|\\.)*)"')


def strings_gd(path):
    n = ns = 0
    for line in open(path, encoding="utf-8", errors="replace"):
        s = line.strip()
        if s.startswith("#"):
            continue
        for m in lit.finditer(line):
            c = len(cjk.findall(m.group(1)))
            if c:
                n += c
                ns += 1
    return n, ns


tot = {}
files = []
for base in ["scripts", "autoload"]:
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith(".gd"):
                p = os.path.join(dp, f)
                n, ns = strings_gd(p)
                key = "/".join(dp.replace(os.sep, "/").split("/")[:3])
                a = tot.setdefault(key, [0, 0, 0])
                a[0] += n
                a[1] += ns
                a[2] += 1
                files.append((n, p.replace(os.sep, "/")))
for k, v in sorted(tot.items(), key=lambda x: -x[1][0])[:22]:
    print("%-36s 汉字 %6d  字符串 %5d  文件 %3d" % (k, v[0], v[1], v[2]))
print("代码字符串合计 汉字 %d / 字符串 %d" % (sum(v[0] for v in tot.values()), sum(v[1] for v in tot.values())))
print("最多的 12 个文件:")
for n, p in sorted(files, reverse=True)[:12]:
    print("  %6d %s" % (n, p))
dn = 0
for f in sorted(os.listdir("data")):
    if f.endswith(".json"):
        t = open("data/" + f, encoding="utf-8").read()
        c = len(cjk.findall(t))
        dn += c
        if c:
            print("data/%s 汉字 %d" % (f, c))
print("data 合计 %d" % dn)
sn = 0
for dp, _, fs in os.walk("scenes"):
    for f in fs:
        if f.endswith(".tscn"):
            t = open(os.path.join(dp, f), encoding="utf-8", errors="replace").read()
            sn += len(cjk.findall(t))
print("scenes/*.tscn 汉字 %d" % sn)
