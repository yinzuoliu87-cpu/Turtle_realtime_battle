# -*- coding: utf-8 -*-
"""实时版·素材引用普查 v2 —— 【保守】判定, 宁可漏删不可错删。

v1 的两个坑(都被自检/人工抓到了):
  · 只做全路径比对 → 相对路径("skills/x.png")全判死  → 491 个误判
  · DYN 白名单不全 → `SPRITE_DIR + "pets/" + spr_id` 里 spr_id 还有
    candy-bomb / conch-worm / crystal-ball / doll-bear / mech / skeleton,
    以及 map/%s.png、tags/%s标签.png、stats/%s-icon.png、status/%s-icon.png、
    rules/%s.png、sprites/%s.png(icon_key 自带子目录) 等一堆动态前缀。

v2 判定(保守):
  一个资源算【活】, 只要满足任意一条:
    A. 它的路径(或路径后缀)在代码/json 里作为字符串出现
    B. 它的【文件名主干】(去扩展名, 再去 `-icon`/`标签` 等后缀变体) 作为【带引号的字面量】出现在任何代码/json 里
    C. 主干 ∈ 已知 id 域(龟id / 装备id / 状态id / 规则id / tag / 属性名)
  → 只有【主干在全库一次都没出现过】的, 才判死。这样会漏删一些真死文件, 但不会错删活文件。

★自检探针: 阳性(shell/candy-bomb/volcano-0/basic 头像)必须判活; 阴性(不存在的假文件 / 中文名副本)必须判死。
"""
import io, os, re, json, hashlib, collections

ASSET_DIR = "assets"
CODE_EXT = (".gd", ".tscn", ".tres", ".json", ".cfg", ".godot")

code_files, texts = [], []
for dp, dn, fn in os.walk("."):
    dn[:] = [d for d in dn if d not in (".git", ".godot", "assets", "build", "docs")]
    for f in fn:
        if f.endswith(CODE_EXT):
            p = os.path.normpath(os.path.join(dp, f)).replace("\\", "/")
            code_files.append(p)
            texts.append(io.open(p, encoding="utf-8", errors="replace").read())
BLOB = "\n".join(texts)

# 所有带引号的字面量 (代码 + json 的字符串值)
LITERALS = set(re.findall(r'"([^"\n]{1,120})"', BLOB))
LITERALS |= set(re.findall(r"'([^'\n]{1,120})'", BLOB))
# 把 "a/b/c.png" 也拆出主干
STEMS = set()
for s in LITERALS:
    s = s.strip()
    if not s:
        continue
    STEMS.add(s)
    base = s.split("/")[-1]
    STEMS.add(base)
    if "." in base:
        STEMS.add(base.rsplit(".", 1)[0])

# 已知 id 域
def ids_of(path, key="id"):
    if not os.path.exists(path):
        return []
    d = json.load(io.open(path, encoding="utf-8"))
    for k in ("pets", "equipment", "status", "rules", "buffs", "synergies"):
        if isinstance(d, dict) and k in d and isinstance(d[k], list):
            d = d[k]
            break
    if isinstance(d, dict):
        return list(d.keys())
    return [x.get(key) for x in d if isinstance(x, dict) and key in x]

DOMAIN = set()
for f in os.listdir("data"):
    if f.endswith(".json"):
        try:
            DOMAIN |= {str(x) for x in ids_of(os.path.join("data", f)) if x}
        except Exception:
            pass
DOMAIN |= {"hp", "atk", "def", "mr", "crit", "shield", "energy"}

# 资源清单
assets = []
for dp, dn, fn in os.walk(ASSET_DIR):
    for f in fn:
        if f.endswith(".import"):
            continue
        assets.append(os.path.normpath(os.path.join(dp, f)).replace("\\", "/"))

SUFFIX_STRIP = ["-icon", "标签", "-0", "-1", "-2", "-3", "-4", "_sm"]

def stem_variants(path):
    base = os.path.basename(path)
    stem = base.rsplit(".", 1)[0] if "." in base else base
    out = {stem}
    for suf in SUFFIX_STRIP:
        if stem.endswith(suf):
            out.add(stem[: -len(suf)])
    return out

def is_ref(path):
    p = path.replace("\\", "/")
    # A. 路径/后缀出现
    for lit in STEMS:
        if lit and (p.endswith("/" + lit) or p == lit):
            return True
    # B/C. 主干出现在字面量或 id 域
    for st in stem_variants(p):
        if st in STEMS or st in DOMAIN:
            return True
    return False

# ── 自检探针 ────────────────────────────────────────────────────────────────
LIVE_PROBES = [
    "assets/sprites/pets/shell.png",
    "assets/sprites/pets/candy-bomb.png",       # spr_id 字面量 (v1 误判成死)
    "assets/sprites/skills/volcano-0.png",      # pets.json volcanoSkills icon
    "assets/sprites/avatars/basic.png",
]
DEAD_PROBES = [
    "assets/sprites/pets/__不存在的假文件__.png",
    "assets/sprites/pets/龟壳v1.png",            # 中文名副本, 全库 0 处
]
for p in LIVE_PROBES:
    assert is_ref(p), "自检失败(阳性判死): " + p
for p in DEAD_PROBES:
    assert not is_ref(p), "自检失败(阴性判活): " + p

dead = sorted(a for a in assets if not is_ref(a))
live = [a for a in assets if is_ref(a)]

def sz(p):
    try:
        return os.path.getsize(p)
    except OSError:
        return 0

by_md5 = collections.defaultdict(list)
for a in assets:
    try:
        by_md5[hashlib.md5(open(a, "rb").read()).hexdigest()].append(a)
    except OSError:
        pass
dups = {k: v for k, v in by_md5.items() if len(v) > 1}

L = ["自检探针: 通过 (4 阳性判活 / 2 阴性判死)", ""]
L.append("资源总数 %d | 活 %d | 死 %d | 死文件体积 %.1f MB"
         % (len(assets), len(live), len(dead), sum(sz(d) for d in dead) / 1048576))
L.append("")
bydir = collections.Counter(os.path.dirname(d) for d in dead)
L.append("=== 死文件按目录 ===")
for k, v in bydir.most_common(20):
    tot = sum(sz(x) for x in dead if os.path.dirname(x) == k)
    L.append("  %3d 个  %7.1f MB  %s" % (v, tot / 1048576, k))
L.append("")
L.append("=== 全部死文件 ===")
for d in sorted(dead, key=sz, reverse=True):
    L.append("  %8.2f MB  %s" % (sz(d) / 1048576, d))
L.append("")
L.append("=== 内容重复组 %d ===" % len(dups))
for k, v in dups.items():
    L.append("  %6.2f MB × %d : %s" % (sz(v[0]) / 1048576, len(v), " == ".join(v)))
io.open("c:/tmp/asset_audit2.txt", "w", encoding="utf-8").write("\n".join(L))
io.open("c:/tmp/dead_list.txt", "w", encoding="utf-8").write("\n".join(dead))
print("selftest OK; dead=%d" % len(dead))
