# -*- coding: utf-8 -*-
"""特效纪律审计 —— 把三条【已经写过、我照样犯】的教训焊成门禁 (2026-09-11)

════════════════════════════════════════════════════════════════════════
 ★由来
════════════════════════════════════════════════════════════════════════
2026-09-11 用户看完 012 那一版, 一路问下来抓到三件事, **每一件都已经写在这个仓库里了**:

  ① 「**为什么那个地面的东西糊弄啊**」
     → `_skill_ring` 换了像素贴图, 却把原来那套 `tween pixel_size 连续放大` 原样留着。
       连续缩放像素贴图 = 非整数倍缩放 = 像素网格被打烂。
       这条白纸黑字写在 `tools/blender_ring.py:13` 的头注里, 还抄了用户原话
       「**最好不要程序弄吧**」; `equip_system.gd:1169` 与 `battle_ballistics.gd:675`
       也各写了一遍。我照样犯。

  ② 「**你不是接了blender吗**」
     → Blender 5.2 装着、6 个 `tools/blender_*.py` 在用(003 的冲击环就是它烤的),
       我却手写 PIL 生成器画了 `skill-ring.png` / `shield-shell.png` / `kelp-frond.png`。
       memory `fb-search-repo-before-building` 说的就是这个。

  ③ 「**这是012？**」/「**牵强海藻**」
     → 我拿自己裁的 **4 倍放大接触印相**做自我验收, 觉得没问题;
       1:1 游戏尺寸(那只龟才 40 像素高)一看是"龟身前戳着两根绿柱子"。
       **放大图骗了我。** 而这两张新素材落地时**一篇逐帧研究都没有**。

用户当时那句是:「**我问一句你才意识到一个漏洞？那我怎么敢开工，你任何东西也不记住**」。

★结论(他 2026-09-01 就下过): **memory 靠我想起来, 门禁自己会红。**
  焊进门禁的教训没再复发过; 留在 memory 里的, 今天又复发了三条。

════════════════════════════════════════════════════════════════════════
 ★三条判据
════════════════════════════════════════════════════════════════════════
A. **硬边像素贴图不许被 tween 连续缩放**(`pixel_size` / `scale`)。
   ★判据落在**贴图本身**, 不落在调用点的字眼 —— 第一版探针按 "load() 还是 VfxTex."
     分类, 结果把 `_skill_ring` 判成"程序软光"放过了, 而 `_make_ring_texture` 早就改成
     **加载烤好的 PNG** 了。所以这里把表达式解析到真实文件, 再**量那张图**:
     **半透明像素 == 0 ⇒ 它是硬边像素画 ⇒ 连续缩放就是打烂网格**。
   ★解析不出来的一律**不判**, 但计入"未判定"并打印 —— 盲区要看得见, 不许假装覆盖全。

B. **不许新增手写生成器画素材**。已有 `tools/blender_*.py` 那条路(真 3D 几何 + 真光照),
   `tools/gen_*.py` 手算像素只适合占位。存量冻台账, 新增当场红。

C. **新增 vfx 素材必须有一篇逐帧研究**(`docs/studies/` 里提到它的文件名)。
   逐帧研究是**唯一会逼我在 1:1 下逐帧看**的东西 —— ③ 就是没有它才漏的。
   存量 219 张冻台账(补历史没价值), 新增当场红。

★三条都是**只减不增**的棘轮, 且**还了债要销账**(台账里某条已经修好也 FAIL) ——
  否则台账会一直停在历史最大值(照 `shield_duration_audit` 的规矩; `zero_caller_audit`
  与 `arch_budget` 只做了"新增当场红"这一半)。

跑法:
  python tools/vfx_discipline_audit.py
  VFX_DISCIPLINE_UPDATE=1 python tools/vfx_discipline_audit.py   # 重写台账(还债后用)
"""
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "tools", "vfx_discipline_debt.json")

SCAN_DIRS = ["scripts"]
VFX_DIR = os.path.join("assets", "sprites", "vfx")
STUDIES_DIR = os.path.join("docs", "studies")

TWEEN = re.compile(r'tween_property\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*"(pixel_size|scale)"')
FUNC = re.compile(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)')
LOAD_ASSET = re.compile(r'(?:load|preload)\s*\(\s*"(res://assets/[^"]+)"')
VFXTEX_CALL = re.compile(r'VfxTex\.(_make_[A-Za-z0-9_]+)\s*\(')
EXEMPT = re.compile(r'#\s*vfx-scale-ok:\s*(.+?)\s*$')
LINEAR = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\.texture_filter\s*=\s*\w+\.TEXTURE_FILTER_LINEAR')
EXEMPT_LIN = re.compile(r'#\s*vfx-linear-ok:\s*(.+?)\s*$')

## 分母下界: 扫到的 tween 缩放点少于这个数 = 扫描口径坏了(实测 174 处)
MIN_TWEENS = 120
## 同理: D 条的分母下界(实测 28 处)。★反向验证抳出来的 ——
##   第一版 D 条**没有分母断言**: 把 LINEAR 正则改坏扫到 0 处, 审计照样绿。
##   memory `fb-verify-check-can-fail`: **N=0 是空检查不是通过**。
MIN_LINEAR = 18


# ───────────────────────────────────────────────────────────────────────
#  贴图解析与测量
# ───────────────────────────────────────────────────────────────────────
_tex_cache = {}


def _is_hard_pixel_art(res_path):
    """量这张图: 半透明像素 == 0 ⇒ 硬边像素画。取不到就返回 None(不判)。"""
    if res_path in _tex_cache:
        return _tex_cache[res_path]
    rel = res_path.replace("res://", "").replace("/", os.sep)
    full = os.path.join(ROOT, rel)
    ans = None
    if os.path.exists(full):
        try:
            im = Image.open(full).convert("RGBA")
            ## 只看 alpha 通道的原始字节: 比逐像素元组快, 也不吃 getdata 的弃用告警
            alpha = im.getchannel("A").tobytes()
            ans = not any(0 < b < 255 for b in alpha)
        except Exception:
            ans = None
    _tex_cache[res_path] = ans
    return ans


_vfxtex_src = None


def _vfxtex_loads(fn_name):
    """`VfxTex._make_X_texture` 内部是不是 load 了一张烤好的 PNG。是则返回那个路径。

    ★这一步是本审计的关键: 2026-09 起 `_make_ring_texture` / `_make_shellhalf_texture`
      已经改成加载烤好的像素图了, 光看调用点写着 `VfxTex.` 会把它们误判成"程序软光"。
    """
    global _vfxtex_src
    if _vfxtex_src is None:
        p = os.path.join(ROOT, "scripts", "util", "vfx_textures.gd")
        _vfxtex_src = io.open(p, encoding="utf-8", newline="").read() if os.path.exists(p) else ""
    m = re.search(r'static func ' + re.escape(fn_name) + r'\b(.*?)(?=\nstatic func |\Z)',
                  _vfxtex_src, re.S)
    if not m:
        return None
    hit = LOAD_ASSET.search(m.group(1))
    return hit.group(1) if hit else None


def _resolve_expr(expr, body, filesrc, depth=0):
    """把一个"贴图表达式"解析成 res:// 路径; 解析不出返回 None。

    ★为什么要递归而不是只配 `load("res://…")`:
      第一版只配字面量, 反向验证时**卡在我自己写的代码上** ——
      `kelp_burst` 是 `var tex = load(KELP_TEX)` 再 `s.texture = tex`, 两层都配不上,
      于是"新增一处连续缩放"的变异**没红**。盲区不补上, 这条门禁就是摆设。
    ⇒ 处理三种: 字面量 / `load(常量名)` / 裸变量名(回查本函数里的 `var x = …`)。
    """
    if depth > 3 or not expr:
        return None
    expr = expr.split("#")[0].strip()
    hit = LOAD_ASSET.search(expr)
    if hit:
        return hit.group(1)
    call = VFXTEX_CALL.search(expr)
    if call:
        return _vfxtex_loads(call.group(1))
    ## load(SOME_CONST) / preload(SOME_CONST) —— 回查本文件的 const
    cm = re.search(r'(?:load|preload)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)', expr)
    if cm:
        cv = re.search(r'const\s+' + re.escape(cm.group(1)) +
                       r'\s*(?::\s*String\s*)?:?=\s*"(res://[^"]+)"', filesrc)
        if cv:
            return cv.group(1)
        return None
    ## 带点的成员(`battle._shellhalf_tex` 这类) —— 回查本函数里对它的赋值。
    ## ★ 018 守护贝壳就落在这个盲区里: `sh.texture = battle._shellhalf_tex`,
    ##   而上一行才是 `battle._shellhalf_tex = VfxTex._make_shellhalf_texture()`。
    ##   不补这一层, D 条正好放过了它 —— 而它正是我要查的那一件。
    dotted = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)'
                          r'(?:\s+as\s+\w+)?', expr)
    if dotted:
        am = re.search(re.escape(dotted.group(1)) + r'\s*=\s*(?!=)(.+)', body)
        if am:
            return _resolve_expr(am.group(1), body, filesrc, depth + 1)
    ## 裸变量(允许 `x as Texture2D`) —— 回查本函数里它是怎么来的
    bare = re.fullmatch(r'([A-Za-z_][A-Za-z0-9_]*)(?:\s+as\s+\w+)?', expr)
    if bare:
        vm = re.search(r'var\s+' + re.escape(bare.group(1)) +
                       r'\s*(?::[^=\n]*)?=\s*(.+)', body)
        if vm:
            return _resolve_expr(vm.group(1), body, filesrc, depth + 1)
    return None


def _resolve_texture(body, var, filesrc):
    """在函数体里找 `<var>.texture = …`, 解析成 res:// 路径; 解析不出返回 None。"""
    m = re.search(re.escape(var) + r'\.texture\s*=\s*(.+)', body)
    if not m:
        return None
    return _resolve_expr(m.group(1), body, filesrc)


# ───────────────────────────────────────────────────────────────────────
#  A: 硬边像素贴图不许被连续缩放
# ───────────────────────────────────────────────────────────────────────
def check_a():
    bad, unknown, total = [], 0, 0
    exempt = []
    for d in SCAN_DIRS:
        for root, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if not f.endswith(".gd"):
                    continue
                p = os.path.join(root, f)
                rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
                filesrc = io.open(p, encoding="utf-8", newline="").read()
                L = filesrc.split(chr(10))
                starts = [i for i, ln in enumerate(L) if FUNC.match(ln)]
                for i, ln in enumerate(L):
                    m = TWEEN.search(ln)
                    if not m:
                        continue
                    total += 1
                    var, prop = m.group(1), m.group(2)
                    s0 = max([k for k in starts if k <= i], default=0)
                    s1 = min([k for k in starts if k > i], default=len(L))
                    fn = FUNC.match(L[s0]).group(1) if FUNC.match(L[s0]) else "(顶层)"
                    res = _resolve_texture(chr(10).join(L[s0:s1]), var, filesrc)
                    if res is None:
                        unknown += 1
                        continue
                    hard = _is_hard_pixel_art(res)
                    if hard is not True:
                        continue
                    ex = EXEMPT.search(ln) or (EXEMPT.search(L[i - 1]) if i > 0 else None)
                    if ex:
                        exempt.append("%s:%d  %s" % (rel, i + 1, ex.group(1)))
                        continue
                    bad.append({
                        "key": "%s::%s::%s" % (rel, fn, prop),
                        "line": i + 1, "rel": rel, "tex": res, "prop": prop,
                    })
    return bad, unknown, total, exempt


# ───────────────────────────────────────────────────────────────────────
#  B: 不许新增手写生成器画素材
# ───────────────────────────────────────────────────────────────────────
ASSET_IN_PY = re.compile(r'assets/sprites/[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\.png')


## ★D: 硬边像素贴图不许用 TEXTURE_FILTER_LINEAR。
##   由来: 018 守护贝壳的半壳写着 LINEAR —— **素材再好也是糊的**。
##   spec《装备特效制作流程》阶段 4 三条渲染纪律第一条就是这个;
##   memory `fb-vfx-defect-families` 也列了「贴图糊 = 没设 NEAREST」。
## ★判据与 A 条同形: **量贴图本身**(半透==0 ⇒ 硬边像素画)。
##   程序软辉光用 LINEAR 是对的, 不能一刀切; 解析不出来的不判(计入盲区)。
def check_d():
    bad, unknown, total, exempt = [], 0, 0, []
    for d in SCAN_DIRS:
        for root, _dirs, files in os.walk(os.path.join(ROOT, d)):
            for f in sorted(files):
                if not f.endswith('.gd'):
                    continue
                p = os.path.join(root, f)
                rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
                filesrc = io.open(p, encoding='utf-8', newline='').read()
                L = filesrc.split(chr(10))
                starts = [i for i, ln in enumerate(L) if FUNC.match(ln)]
                for i, ln in enumerate(L):
                    m = LINEAR.search(ln)
                    if not m:
                        continue
                    total += 1
                    var = m.group(1)
                    s0 = max([k for k in starts if k <= i], default=0)
                    s1 = min([k for k in starts if k > i], default=len(L))
                    mf = FUNC.match(L[s0])
                    fn2 = mf.group(1) if mf else '(顶层)'
                    res = _resolve_texture(chr(10).join(L[s0:s1]), var, filesrc)
                    if res is None:
                        unknown += 1
                        continue
                    if _is_hard_pixel_art(res) is not True:
                        continue
                    ex = EXEMPT_LIN.search(ln) or (EXEMPT_LIN.search(L[i - 1]) if i > 0 else None)
                    if ex:
                        exempt.append('%s:%d  %s' % (rel, i + 1, ex.group(1)))
                        continue
                    bad.append('%s::%s' % (rel, fn2))
    return bad, unknown, total, exempt


def check_b():
    pairs = []
    tdir = os.path.join(ROOT, "tools")
    for f in sorted(os.listdir(tdir)):
        if not (f.startswith("gen_") and f.endswith(".py")):
            continue
        src = io.open(os.path.join(tdir, f), encoding="utf-8", newline="").read()
        for a in sorted(set(ASSET_IN_PY.findall(src))):
            pairs.append("%s -> %s" % (f, a))
    return pairs


# ───────────────────────────────────────────────────────────────────────
#  C: 新增 vfx 素材必须有逐帧研究
# ───────────────────────────────────────────────────────────────────────
def check_c():
    sdir = os.path.join(ROOT, STUDIES_DIR)
    blob = ""
    if os.path.isdir(sdir):
        for f in sorted(os.listdir(sdir)):
            if f.endswith(".md"):
                blob += io.open(os.path.join(sdir, f), encoding="utf-8",
                                errors="replace", newline="").read()
    vdir = os.path.join(ROOT, VFX_DIR)
    missing, total = [], 0
    if os.path.isdir(vdir):
        for f in sorted(os.listdir(vdir)):
            if not f.endswith(".png"):
                continue
            total += 1
            if f not in blob:
                missing.append(f)
    return missing, total


# ───────────────────────────────────────────────────────────────────────
def main():
    bad_a, unknown_a, total_a, exempt_a = check_a()
    bad_d, unknown_d, total_d, exempt_d = check_d()
    pairs_b = check_b()
    missing_c, total_c = check_c()

    print("=== 特效纪律审计 ===")
    print("  A 连续缩放: 扫到 %d 处 tween 缩放 · 解析出贴图并判定 %d 处 · 未判定 %d 处(盲区)"
          % (total_a, total_a - unknown_a, unknown_a))
    print("  B 手写生成器: %d 对(生成器 → 素材)" % len(pairs_b))
    print("  C 逐帧研究: vfx 素材 %d 张 · 其中无研究 %d 张" % (total_c, len(missing_c)))
    print("  D LINEAR: 扫到 %d 处 · 解析并判定 %d 处 · 未判定 %d 处(盲区)"
          % (total_d, total_d - unknown_d, unknown_d))
    if exempt_d:
        print("  [豁免] D 有 %d 处写了理由:" % len(exempt_d))
        for e in exempt_d:
            print("     " + e)
    if exempt_a:
        print("  [豁免] A 有 %d 处写了理由:" % len(exempt_a))
        for e in exempt_a:
            print("     " + e)

    if total_d < MIN_LINEAR:
        print("")
        print("[FAIL] ★分母: 只扫到 %d 处 texture_filter=LINEAR(<%d) —— 扫描口径坏了"
              % (total_d, MIN_LINEAR))
        return 1
    if total_a < MIN_TWEENS:
        print("")
        print("[FAIL] ★分母: 只扫到 %d 处 tween 缩放(<%d) —— 扫描口径坏了, 这是空检查不是通过"
              % (total_a, MIN_TWEENS))
        return 1

    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}

    cur = {
        "a_scale": sorted(x["key"] for x in bad_a),
        "b_generators": sorted(pairs_b),
        "c_no_study": sorted(missing_c),
        "d_linear": sorted(set(bad_d)),
    }

    if os.environ.get("VFX_DISCIPLINE_UPDATE") == "1":
        out = {"_": "特效纪律存量台账(只减不增)。新增当场红; 还了债要跑 "
                    "VFX_DISCIPLINE_UPDATE=1 重写。判据见 tools/vfx_discipline_audit.py"}
        out.update(cur)
        io.open(LEDGER, "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (A %d · B %d · C %d)"
              % (os.path.relpath(LEDGER, ROOT), len(cur["a_scale"]),
                 len(cur["b_generators"]), len(cur["c_no_study"])))
        return 0

    TITLES = {
        "a_scale": ("硬边像素贴图被 tween **连续缩放**(非整数倍 ⇒ 像素网格被打烂)",
                    "改成【逐帧烤好、pixel_size 固定只切帧】(做法见 tools/blender_ring.py);"
                    "\n    确实该缩的加 `# vfx-scale-ok: 原因`, 原因会被打印。"),
        "b_generators": ("**手写生成器**画素材(公式算像素只适合占位)",
                         "改走 tools/blender_*.py 那条(真 3D 几何 + 真光照);"
                         "\n    要质感就走 PixelLab。"),
        "d_linear": ("**硬边像素贴图用了 TEXTURE_FILTER_LINEAR**(素材再好也是糊的)",
                     "改成 TEXTURE_FILTER_NEAREST;"
                     "\n    确实该用线性的(程序软辉光)加 `# vfx-linear-ok: 原因`。"),
        "c_no_study": ("新增 vfx 素材**没有逐帧研究**(docs/studies/ 里没提到它)",
                       "逐帧研究是唯一会逼人在 1:1 下逐帧看的东西 ——"
                       "\n    2026-09-11 那两张就是没有它才漏的(我拿 4 倍放大图自我验收)。"),
    }

    rc = 0
    for k in ("a_scale", "b_generators", "c_no_study", "d_linear"):
        known = set(ledger.get(k, []))
        fresh = [x for x in cur[k] if x not in known]
        stale = sorted(known - set(cur[k]))
        title, how = TITLES[k]
        if fresh:
            print("")
            print("[FAIL] **新增**了%s —— %d 条:" % (title, len(fresh)))
            for x in fresh[:20]:
                print("   " + x)
            if len(fresh) > 20:
                print("   …… 另 %d 条" % (len(fresh) - 20))
            print("  ⇒ " + how)
            rc = 1
        elif stale:
            print("")
            print("[FAIL] 台账里这 %d 条已经不成立了 —— 还了债要销账(棘轮只能往小转):"
                  % len(stale))
            for x in stale[:20]:
                print("   " + x)
            print("  跑一次: VFX_DISCIPLINE_UPDATE=1 python tools/vfx_discipline_audit.py")
            rc = 1
        else:
            print("  [存量] %-14s %d 条在台账里(只减不增)" % (k, len(cur[k])))

    if rc == 0:
        print("")
        print("ALL OK — 特效纪律没有新增欠债")
    return rc


if __name__ == "__main__":
    sys.exit(main())
