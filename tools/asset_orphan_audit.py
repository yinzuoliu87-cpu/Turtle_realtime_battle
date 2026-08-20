# -*- coding: utf-8 -*-
"""asset_orphan_audit.py —— 素材孤儿 / json 死字段普查（**解析式**判定）

★为什么不用 tools/asset_audit.py 就够了（这不是重复造轮子, 是补它的盲区）:
  asset_audit.py 是**按文件名主干**判活的 —— "主干在全库出现过就算活"。
  这条判据对**拼出来的路径**是错的, 因为拼路径里根本不会出现完整文件名:

      "res://assets/sprites/equip/chest-t-%s.png" % tid          (chest_system.gd:63)
      "res://assets/sprites/trainer/anim/trainer-" + id + "-idle.png"  (trainer_system.gd:1135)

  实测: asset_audit.py 报的 60 个"死文件"里, 24 个是这两条拼路径的产物 —— 全是**误报**,
  删掉就是线上开宝箱掉图 / 训龟师站在原地没动画。

★本脚本的判据（三级, 从强到弱, 全部**保守**——判不准就不判死）:
  L1 STATIC   文件全路径(或路径后缀)以字符串字面量形式出现   → 活
  L2 RESOLVED 存在拼路径模板 (前缀,后缀), 且存在某个**真实字面量/id** L
              使 前缀+L+后缀 == 该文件路径                    → 活 (带证据: 模板位置 + 代入值)
  L3 DYNDIR   文件"长得能被某个模板拼出来"(前缀是它的前缀·后缀是它的后缀),
              但库里找不到那个 L                              → **不判死**, 单列「拼路径可达·存疑」
  以上都不沾  → ORPHAN

  L3 就是需求里说的"按目录判定而不是按文件名": 只要它落在拼路径够得着的形状里, 一律不删。

★分母必打（`N=0 是空检查不是通过`）: 扫了多少文件 / 多少字面量 / 多少模板 / 各级各多少。
★自检探针在 selftest(): 阳性(已知活)必须判活, 阴性(不存在的假路径)必须判死; 失败直接 raise。

用法:
    python tools/asset_orphan_audit.py            # 素材 + json 双段报告
    python tools/asset_orphan_audit.py --assets   # 只跑素材
    python tools/asset_orphan_audit.py --json     # 只跑 json 字段
报告写到 c:/tmp/asset_orphan_audit.txt (与仓库里其它审计器一致), 同时 stdout 打摘要。
"""
import io, os, re, sys, json, glob, collections

ASSET_DIR = "assets"
# 语料: 会真正影响运行时的文件。**排除 .import/.uid** —— 它们是 Godot 自动生成的伴生文件,
# 里面 source_file="res://assets/..." 会让每个素材都"看起来被引用", 判据直接失效。
CORPUS_EXT = (".gd", ".tscn", ".tres", ".json", ".cfg", ".godot", ".gdshader")
SKIP_DIRS = {".git", ".godot", "build", "docs", "__pycache__", ".import"}

# docs/ 里提到某素材 **不算**运行时引用, 但单独统计一下, 方便人判断"是不是废弃素材的历史记录"
DOC_EXT = (".md",)


# ── 语料装载 ──────────────────────────────────────────────────────────────────
def load_corpus():
    files = {}
    for dp, dn, fn in os.walk("."):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            if f.endswith((".import", ".uid")):
                continue
            if not f.endswith(CORPUS_EXT):
                continue
            p = os.path.normpath(os.path.join(dp, f)).replace("\\", "/").lstrip("./")
            # assets/ 内部的 .tres/.tscn 要读(主题引用字体), 但 assets 内的 .json(如骨骼)也读
            try:
                files[p] = io.open(p, encoding="utf-8", errors="replace").read()
            except OSError:
                pass
    return files


def load_docs():
    txt = []
    for dp, dn, fn in os.walk("docs"):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            if f.endswith(DOC_EXT):
                try:
                    txt.append(io.open(os.path.join(dp, f), encoding="utf-8",
                                       errors="replace").read())
                except OSError:
                    pass
    return "\n".join(txt)


STR_RE = re.compile(r'"([^"\n]{0,200})"' r"|'([^'\n]{0,200})'")


def literals_of(text):
    out = set()
    for m in STR_RE.finditer(text):
        s = m.group(1) if m.group(1) is not None else m.group(2)
        if s is not None:
            out.add(s)
    return out


# ── 常量替换: const SPRITE_DIR := "res://assets/sprites/" ─────────────────────
CONST_RE = re.compile(
    r'^[ \t]*(?:const|var)[ \t]+(\w+)[ \t]*(?::=|=|:[ \t]*String[ \t]*=)[ \t]*"([^"\n]*)"',
    re.M)


def const_map(files):
    m = {}
    for p, s in files.items():
        if not p.endswith(".gd"):
            continue
        for mo in CONST_RE.finditer(s):
            name, val = mo.group(1), mo.group(2)
            if "assets/" in val or val.startswith("res://"):
                m[name] = val
    return m


def substitute_consts(text, cm):
    """把 SPRITE_DIR + "pets/" 变成 "res://assets/sprites/" + "pets/", 好让模板正则吃到前缀。"""
    if not cm:
        return text
    pat = re.compile(r'\b(' + "|".join(re.escape(k) for k in sorted(cm, key=len, reverse=True)) + r')\b')
    return pat.sub(lambda mo: '"' + cm[mo.group(1)] + '"', text)


# ── 拼路径模板抽取 ────────────────────────────────────────────────────────────
# 模板 = (prefix, suffix, 出处). 只要 prefix 里含 assets/ 就收。
FMT_RE = re.compile(r'"([^"\n]*assets/[^"\n]*?)%[sdv]([^"\n]*)"')
# "…assets/x/" + var + ".png"      → (pre, post)
CAT2_RE = re.compile(r'"([^"\n]*assets/[^"\n]*?)"[ \t]*\+[ \t]*[^"\n+]{1,80}?[ \t]*\+[ \t]*"([^"\n]*?)"')
# "…assets/x/" + var               → (pre, "")
CAT1_RE = re.compile(r'"([^"\n]*assets/[^"\n]*?)"[ \t]*\+[ \t]*([A-Za-z_]\w*)')


def norm(p):
    p = p.replace("\\", "/")
    if p.startswith("res://"):
        p = p[6:]
    return p.lstrip("./")


def extract_patterns(files, cm):
    pats = {}   # (pre,post) -> set(出处)
    for p, s in files.items():
        if not p.endswith((".gd", ".tscn", ".tres")):
            continue
        sub = substitute_consts(s, cm)
        for lineno, line in enumerate(sub.splitlines(), 1):
            for rx, two in ((FMT_RE, True), (CAT2_RE, True), (CAT1_RE, False)):
                for mo in rx.finditer(line):
                    pre = norm(mo.group(1))
                    post = mo.group(2) if two else ""
                    if not two:
                        post = ""
                    if "assets/" not in pre:
                        continue
                    pats.setdefault((pre, post), set()).add("%s:%d" % (p, lineno))
    return pats


# ── id 域: json 里所有 id / 键名 / 字符串值, 都可能被代入模板 ──────────────────
def walk_strings(o, out):
    if isinstance(o, dict):
        for k, v in o.items():
            out.add(str(k))
            walk_strings(v, out)
    elif isinstance(o, list):
        for v in o:
            walk_strings(v, out)
    elif isinstance(o, str):
        out.add(o)


def data_domain():
    dom = set()
    for p in glob.glob("data/**/*.json", recursive=True):
        try:
            walk_strings(json.load(io.open(p, encoding="utf-8")), dom)
        except Exception:
            pass
    return dom


# ══════════════════════════════════════════════════════════════════════════════
class Audit(object):
    def __init__(self):
        self.files = load_corpus()
        self.cm = const_map(self.files)
        blob = "\n".join(self.files.values())
        self.lits = literals_of(blob)
        # 字面量 + 其去引号的片段(rich text "[img]res://..." 里嵌的路径也要吃到)
        for m in re.finditer(r'res://assets/[^\s"\'\]\[)]+', blob):
            self.lits.add(m.group(0))
        self.dom = data_domain()
        self.subs = self.lits | self.dom          # 可代入模板的候选值
        self.pats = extract_patterns(self.files, self.cm)
        # 反查: 字面量的规范化路径集合
        self.lit_paths = set()
        for s in self.lits:
            n = norm(s)
            if n:
                self.lit_paths.add(n)
        # 预先把所有模板能拼出的真实路径算出来(解析式)
        self.resolved = {}    # path -> (pre,post,val,出处)
        self.assets = self._scan_assets()
        aset = set(self.assets)
        for (pre, post), where in self.pats.items():
            for v in self.subs:
                if not v or len(v) > 80 or "\n" in v:
                    continue
                cand = norm(pre + v + post)
                if cand in aset and cand not in self.resolved:
                    self.resolved[cand] = (pre, post, v, sorted(where)[0])

    def _scan_assets(self):
        out = []
        for dp, dn, fn in os.walk(ASSET_DIR):
            dn[:] = [d for d in dn if d not in SKIP_DIRS]
            for f in fn:
                if f.endswith((".import", ".uid")):
                    continue
                out.append(norm(os.path.join(dp, f)))
        return sorted(out)

    # ── 判定 ──────────────────────────────────────────────────────────────
    def static_ref(self, p):
        """全路径 或 任意路径后缀 以字面量形式出现。"""
        if p in self.lit_paths:
            return "全路径字面量"
        parts = p.split("/")
        for i in range(1, len(parts)):
            suf = "/".join(parts[i:])
            if suf in self.lit_paths:
                return "路径后缀字面量 '%s'" % suf
        return None

    def dyn_dir(self, p):
        """L3: 形状上能被某模板拼出来(前缀+后缀都对得上), 但找不到具体代入值。

        返回 (同目录命中, 跨目录命中)。区分这两种是本函数存在的理由:
          · 同目录 = 模板前缀正好停在该文件所在目录, 通配符**不跨 `/`**
            (如 vfx/ 里的文件被 "assets/sprites/vfx/%s.png" 够到)
            ⇒ 这个目录**确实在被动态索引**, 判死风险高, 一律不删。
          · 跨目录 = 只有祖先级通配符够得着(如 "assets/sprites/%s" 要吃掉 "equip/xxx.png"
            整段含 `/` 的值)。这种模板的实参是 json 里的 icon 字段, 而 icon 字段的
            **全部取值都已在 self.subs 里试过了**(27618 个候选) —— 试不出来说明
            没有任何已知取值指向它。证据弱于同目录, 但**仍不自动判死**, 单列人工看。
        """
        same, anc = [], []
        for (pre, post), where in self.pats.items():
            if not (p.startswith(pre) and p.endswith(post)):
                continue
            mid = p[len(pre):len(p) - len(post)] if post else p[len(pre):]
            if not mid:
                continue
            rec = (pre + "<*>" + post, sorted(where)[0])
            (same if "/" not in mid else anc).append(rec)
        return same, anc

    def classify(self, p):
        s = self.static_ref(p)
        if s:
            return "STATIC", s
        if p in self.resolved:
            pre, post, v, w = self.resolved[p]
            return "RESOLVED", "%s<%s>%s  @%s" % (pre, v, post, w)
        same, anc = self.dyn_dir(p)
        if same:
            return "DYN_SAMEDIR", "; ".join("%s @%s" % x for x in same[:2])
        if anc:
            return "DYN_ANCESTOR", "; ".join("%s @%s" % x for x in anc[:2])
        return "ORPHAN", ""


# ── 自检探针 ──────────────────────────────────────────────────────────────────
LIVE_PROBES = [
    ("assets/sprites/avatars/basic.png",                "拼路径 avatars/%s.png + pets.json id"),
    ("assets/sprites/equip/chest-t-blood_dice.png",     "拼路径 chest-t-%s.png + 宝箱战利品 id"),
    ("assets/sprites/trainer/anim/trainer-girl-idle.png", "拼路径 trainer-<id>-idle.png"),
    ("assets/sprites/pets/shell.png",                   "spr_id 拼路径"),
    ("assets/sprites/vfx/qibo-ball.png",                "vfx 字面量/拼路径"),
    ("assets/fonts/NotoSansSC-Regular.otf",             "主题 .tres 间接引用的字体"),
]
DEAD_PROBES = [
    "assets/sprites/pets/__不存在的假文件__.png",
    "assets/sprites/equip/chest-t-__没有这个战利品__.png",
    "assets/fonts/__fake-font__.ttf",
]


def selftest(a):
    bad = []
    for p, why in LIVE_PROBES:
        if not os.path.exists(p):
            bad.append("阳性探针文件本身不存在(探针写错了): " + p)
            continue
        k, _ = a.classify(p)
        if k == "ORPHAN":
            bad.append("阳性判死: %s (%s)" % (p, why))
    for p in DEAD_PROBES:
        k, ev = a.classify(p)
        if k in ("STATIC", "RESOLVED"):
            bad.append("阴性判活: %s [%s] %s" % (p, k, ev))
    if bad:
        raise SystemExit("SELFTEST FAILED:\n  " + "\n  ".join(bad))
    return "自检通过: %d 阳性判活 / %d 阴性未判活" % (len(LIVE_PROBES), len(DEAD_PROBES))


# ══ ② data/*.json 字段消费者 ═══════════════════════════════════════════════════
def json_keys():
    """收集 data/*.json 的所有键名 + 它的路径签名(pets[].skills[].icon 这种)。"""
    keys = collections.defaultdict(set)     # leafname -> set(签名)
    def rec(o, sig, f):
        if isinstance(o, dict):
            for k, v in o.items():
                keys[str(k)].add("%s:%s.%s" % (f, sig, k) if sig else "%s:%s" % (f, k))
                rec(v, (sig + "." + str(k)) if sig else str(k), f)
        elif isinstance(o, list):
            for v in o[:200]:
                rec(v, sig + "[]", f)
    for p in sorted(glob.glob("data/**/*.json", recursive=True)):
        try:
            rec(json.load(io.open(p, encoding="utf-8")), "", os.path.basename(p))
        except Exception:
            pass
    return keys


def code_blob():
    txt = []
    for r in ("scripts", "autoload", "tests", "tools"):
        for dp, dn, fn in os.walk(r):
            dn[:] = [d for d in dn if d not in SKIP_DIRS]
            for f in fn:
                if f.endswith((".gd", ".py", ".tscn")):
                    try:
                        txt.append(io.open(os.path.join(dp, f), encoding="utf-8",
                                           errors="replace").read())
                    except OSError:
                        pass
    return "\n".join(txt)


def audit_json_fields():
    keys = json_keys()
    blob = code_blob()
    lits = literals_of(blob)
    # 「有消费者」= 键名以带引号字面量出现在代码里(覆盖 get("k") / ["k"] / has("k") / 常量表)
    unread, read = [], []
    for k, sigs in sorted(keys.items()):
        if k in lits:
            read.append(k)
        else:
            unread.append((k, sorted(sigs)[:3], len(sigs)))
    return keys, read, unread


# ══════════════════════════════════════════════════════════════════════════════
def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    L = []
    summary = []

    if only != "--json":
        a = Audit()
        st = selftest(a)
        buckets = collections.defaultdict(list)
        for p in a.assets:
            k, ev = a.classify(p)
            buckets[k].append((p, ev))
        n = len(a.assets)
        docs = load_docs()

        L.append("═══ ① 素材引用普查 ═══")
        L.append(st)
        L.append("")
        L.append("【分母】")
        L.append("  扫描素材文件      %d 个 (已排除 .import/.uid 伴生文件)" % n)
        L.append("    其中 .png       %d" % sum(1 for p in a.assets if p.endswith(".png")))
        L.append("  语料文件          %d 个 (%s)" % (len(a.files), "/".join(e.lstrip(".") for e in CORPUS_EXT)))
        L.append("  字符串字面量      %d 个" % len(a.lits))
        L.append("  可代入值(字面量+json 全字符串域)  %d 个" % len(a.subs))
        L.append("  拼路径模板        %d 条" % len(a.pats))
        L.append("  路径前缀常量      %d 个 (%s)" % (len(a.cm), ", ".join(sorted(a.cm)[:6])))
        L.append("")
        L.append("【分级结果】")
        for k in ("STATIC", "RESOLVED", "DYN_SAMEDIR", "DYN_ANCESTOR", "ORPHAN"):
            L.append("  %-9s %4d  %s" % (k, len(buckets[k]), {
                "STATIC": "全路径/路径后缀直接出现在代码",
                "RESOLVED": "拼路径模板 + 真实代入值 → 精确命中(带证据)",
                "DYN_SAMEDIR": "所在目录正被拼路径动态索引 —— **存疑, 一律不删**",
                "DYN_ANCESTOR": "只有祖先级通配符够得着, 27618 个候选值全试过都拼不出 —— 疑似孤儿, 人工过目",
                "ORPHAN": "三级都不沾 —— 无任何引用",
            }[k]))
        L.append("")

        L.append("【拼路径模板一览(决定哪些目录不能按文件名判死)】")
        for (pre, post), where in sorted(a.pats.items()):
            L.append("  %-52s @ %s" % (pre + "<*>" + post, sorted(where)[0]))
        L.append("")

        L.append("═══ 孤儿清单 (%d 个) ═══" % len(buckets["ORPHAN"]))
        L.append("  每个都满足: 全路径 0 引用 + 路径后缀 0 引用 + 不属于任何拼路径形状")
        L.append("")
        bydir = collections.Counter(os.path.dirname(p) for p, _ in buckets["ORPHAN"])
        for d, c in bydir.most_common():
            L.append("  [%s]  %d 个" % (d, c))
            for p, _ in buckets["ORPHAN"]:
                if os.path.dirname(p) == d:
                    sz = os.path.getsize(p) if os.path.exists(p) else 0
                    indoc = "docs有提及" if os.path.basename(p) in docs or p in docs else "docs也无"
                    L.append("      %8.1f KB  %-58s  (%s)" % (sz / 1024.0, os.path.basename(p), indoc))
        L.append("")

        L.append("═══ 疑似孤儿·只有祖先级通配符够得着 (%d 个) —— 需人工过目, 本脚本不判死 ═══"
                 % len(buckets["DYN_ANCESTOR"]))
        L.append("  这些文件: 全路径 0 引用, 且把全库 %d 个候选值代进所有模板都拼不出它。" % len(a.subs))
        L.append("  唯一让它'可能还活着'的理由是 assets/sprites/<*> 这种要跨目录的通配符。")
        L.append("")
        byd = collections.Counter(os.path.dirname(x) for x, _ in buckets["DYN_ANCESTOR"])
        for d, c in byd.most_common():
            L.append("  [%s]  %d 个" % (d, c))
            for x, ev in buckets["DYN_ANCESTOR"]:
                if os.path.dirname(x) == d:
                    sz = os.path.getsize(x) if os.path.exists(x) else 0
                    indoc = "docs有提及" if os.path.basename(x) in docs else "docs也无"
                    L.append("      %8.1f KB  %-52s (%s)" % (sz / 1024.0, os.path.basename(x), indoc))
        L.append("")
        L.append("═══ 存疑·所在目录正被动态索引 (%d 个) —— 一律不删 ═══"
                 % len(buckets["DYN_SAMEDIR"]))
        byd2 = collections.Counter(os.path.dirname(x) for x, _ in buckets["DYN_SAMEDIR"])
        for d, c in byd2.most_common():
            L.append("  [%s] %d 个" % (d, c))
        L.append("")
        for x, ev in buckets["DYN_SAMEDIR"]:
            L.append("    %-56s  ← %s" % (x, ev))
        L.append("")
        summary.append("assets: N=%d  STATIC=%d RESOLVED=%d DYN_SAMEDIR=%d DYN_ANCESTOR=%d ORPHAN=%d"
                       % (n, len(buckets["STATIC"]), len(buckets["RESOLVED"]),
                          len(buckets["DYN_SAMEDIR"]), len(buckets["DYN_ANCESTOR"]),
                          len(buckets["ORPHAN"])))

    if only != "--assets":
        keys, read, unread = audit_json_fields()
        L.append("")
        L.append("═══ ② data/*.json 字段消费者普查 ═══")
        L.append("【分母】")
        L.append("  data/**/*.json 里出现的**不同键名** %d 个" % len(keys))
        L.append("  在 scripts/ autoload/ tests/ tools/ 里作为带引号字面量出现的 %d 个" % len(read))
        L.append("  找不到任何字面量消费者的 %d 个" % len(unread))
        L.append("")
        L.append("  ⚠ 口径说明: 键名可能同时是 id(ghost_seed 用龟 id 当键), 所以这里的")
        L.append("     '无消费者' 只说明**这个字符串在代码里一次都没出现**, 不等于字段无用 ——")
        L.append("     还要人工看它的路径签名是不是 '容器键'。签名一并列出。")
        L.append("")
        L.append("═══ 无消费者键名 (%d 个) ═══" % len(unread))
        for k, sigs, nsig in unread:
            L.append("  %-34s  出现 %3d 处, 例: %s" % (k, nsig, "; ".join(sigs)))
        summary.append("json keys: N=%d  consumed=%d  no-consumer=%d"
                       % (len(keys), len(read), len(unread)))

    out = "c:/tmp/asset_orphan_audit.txt"
    try:
        os.makedirs("c:/tmp", exist_ok=True)
        io.open(out, "w", encoding="utf-8").write("\n".join(L))
    except OSError:
        out = "(write failed)"
    for s in summary:
        print(s)
    print("report -> " + out)


if __name__ == "__main__":
    main()
