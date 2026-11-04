# -*- coding: utf-8 -*-
"""blackbox_unpack_study.py —— 拆《黑箱：无限构筑》Demo（Steam 5294350）的资源包，量它的特效 / 音效 / 技能数据是怎么组织的。

★由来（2026-11-04，方案书 docs/plans/20261102b-参考黑箱学AI开发方式.md S2 / S3 / §8.3，Issue #3）：
  预告片逐帧（S1）只能从画面反推；Demo 装上以后直接读它的 Unity Addressables 包，结论从「推断」变「实证」。
  只读、只统计，不导出任何素材（素材不复用铁律；这里也不该拿别人的东西）。

  python tools/oneoff/blackbox_unpack_study.py [Demo 安装目录]
  依赖 UnityPy（pip install --user UnityPy）；不进门禁。默认目录 D:/steam/steamapps/common/blackbox_creations_demo

量什么（每段都打分母）：
  ① 音效：sfx / bgm 两个包里的 AudioClip 名字与时长
  ② 特效：game_fx_prefab 包 —— 成品特效个数、粒子系统数、材质用的着色器、贴图是否灰度、
     按「元素 × 敌我 × 主体/辅助」统计材质 `_Color`（HDR 染色，真正画出来的颜色；贴图是灰度）的色相与亮度。
     ★量尺先标定：火爆炸应量成橙红、冰爆炸应量成蓝 —— 不是就停（第一版用材质里所有颜色属性，冰量成了红，弃）。
  ③ 技能数据：meta.bytes 包里 gzip 的 JSON —— 技能描述语言的词表（出手 / 实体 / 触发 / 动作 / 积木 / 外观类别 / 元素）
"""
import collections, colorsys, gzip, json, os, re, statistics, sys

sys.stdout.reconfigure(encoding="utf-8")
try:
    import UnityPy
except ImportError:
    raise SystemExit("缺 UnityPy：pip install --user UnityPy")

ROOT = sys.argv[1] if len(sys.argv) > 1 else "D:/steam/steamapps/common/blackbox_creations_demo"
AA = os.path.join(ROOT, "Blackbox Creations_Data", "StreamingAssets", "aa", "StandaloneWindows64")
if not os.path.isdir(AA):
    raise SystemExit("找不到 Addressables 目录 %s（Demo 没装？）" % AA)


def load(name):
    return UnityPy.load(os.path.join(AA, name))


# ───────────────────────── ① 音效
def audio():
    print("① 音效")
    for b in ("audio_assets_assets_ab_audio_sfx.bundle", "audio_assets_assets_ab_audio_bgm.bundle"):
        clips = []
        for o in load(b).objects:
            if o.type.name == "AudioClip":
                d = o.read()
                clips.append((d.m_Name, float(getattr(d, "m_Length", 0) or 0)))
        print("  [分母] %s：%d 条" % (b.split("_audio_")[-1].replace(".bundle", ""), len(clips)))
        if "sfx" in b:
            names = [n for n, _ in clips]
            elem = [n for n in names if re.search(r"(^|_)(fire|ice|frost|thunder|ele|elec|poison|holy|divine|evergreen)(_|\d|$)", n)]
            boss = sorted(n for n in names if n.startswith("sfx_boss_skill"))
            print("    名字里带元素词的：%d 条 %s" % (len(elem), elem))
            print("    首领技能（前摇 pre / 命中 hit）：%s" % boss)
            print("    生成流程三段：%s" % sorted(n for n in names if re.match(r"generat|sfx_fusion|sfx_incubator", n)))
            print("    玩家出手 / 命中：%s" % sorted(n for n in names if re.match(r"player_shoot|sfx_shoot|hit\d|etfx_", n)))


# ───────────────────────── ② 特效
def bucket(r, g, b):
    mx = max(r, g, b)
    if mx <= 0.02:
        return None, 0.0
    h, s, _ = colorsys.rgb_to_hsv(min(r / mx, 1), min(g / mx, 1), min(b / mx, 1))
    if s < 0.2:
        return "白", mx
    h *= 360
    for lim, nm in [(15, "红"), (45, "橙"), (70, "黄"), (160, "绿"), (200, "青"), (255, "蓝"), (290, "紫"), (340, "品红"), (361, "红")]:
        if h < lim:
            return nm, mx
    return "红", mx


def effects():
    print("② 特效")
    env = load("effect_assets_assets_ab_effects_game_fx_prefab.bundle")
    types = collections.Counter(o.type.name for o in env.objects)
    shaders = collections.Counter()
    cache = {}

    def mat(mp):
        if mp.path_id in cache:
            return cache[mp.path_id]
        try:
            m = mp.read()
        except Exception:
            cache[mp.path_id] = (None, 0.0)
            return cache[mp.path_id]
        try:
            shaders[m.m_Shader.read().m_ParsedForm.m_Name] += 1
        except Exception:
            shaders["<外部>"] += 1
        cols = {k: v for k, v in (m.m_SavedProperties.m_Colors or [])}
        c = cols.get("_Color") or cols.get("_TintColor") or cols.get("_BaseColor")
        cache[mp.path_id] = bucket(c.r, c.g, c.b) if c is not None else (None, 0.0)
        return cache[mp.path_id]

    def walk(go, acc):
        tr = None
        for comp in go.m_Component:
            try:
                c = comp.component.read()
            except Exception:
                continue
            tn = c.object_reader.type.name
            if tn == "ParticleSystem":
                acc["ps"] += 1
            elif tn.endswith("Renderer"):
                for mp in (getattr(c, "m_Materials", None) or []):
                    if mp and mp.path_id:
                        b, i = mat(mp)
                        if b:
                            acc["m"].append((b, i))
            elif tn in ("Transform", "RectTransform"):
                tr = c
        if tr is not None:
            for ch in (tr.m_Children or []):
                walk(ch.read().m_GameObject.read(), acc)

    rows = []
    for path, obj in env.container.items():
        if obj.type.name == "GameObject":
            acc = {"ps": 0, "m": []}
            walk(obj.read(), acc)
            rows.append((path.rsplit("/", 1)[-1].replace(".prefab", ""), acc))
    print("  [分母] 成品特效 %d 个 · 粒子系统 %d · 材质 %d · 贴图 %d" % (len(rows), types["ParticleSystem"], types["Material"], types["Texture2D"]))
    print("  着色器（按材质计）：%s" % shaders.most_common(4))
    E = {"fire": "火", "ice": "冰", "bing": "冰", "ele": "电", "du": "毒", "changqing": "常青", "shensheng": "神圣", "light": "光"}

    def el(n):
        for t in n.split("_"):
            t = re.sub(r"\d+$", "", t)
            if t in E:
                return E[t]
        return None

    def show(label, rs):
        c = collections.Counter(b for _, a in rs for b, _ in a["m"])
        t = sum(c.values()) or 1
        it = [i for _, a in rs for _, i in a["m"]]
        print("    %-10s %3d 个 %4d 层 · %s · 亮度中位 %.1f · HDR(>1) %d%% · 每个粒子系统中位 %s" % (
            label, len(rs), t, "、".join("%s %d%%" % (k, 100 * v // t) for k, v in c.most_common(3)),
            statistics.median(it) if it else 0, 100 * sum(1 for x in it if x > 1) // max(len(it), 1),
            statistics.median([a["ps"] for _, a in rs]) if rs else 0))
        return c

    print("  【量尺标定】")
    cf = show("火爆炸", [r for r in rows if "boom_fire_01_body" in r[0]])
    ci = show("冰爆炸", [r for r in rows if "boom_ice_01_body" in r[0]])
    if cf.most_common(1)[0][0] not in ("红", "橙") or ci.most_common(1)[0][0] != "蓝":
        raise SystemExit("✗ 量尺没标定上（火应橙红、冰应蓝）—— 下面的数不可信，停")
    pl = [r for r in rows if "yerskill" in r[0]]
    print("  【玩家技能 按元素】")
    for e in ("火", "冰", "电", "毒", "常青", "神圣", "光"):
        show(e, [r for r in pl if el(r[0]) == e])
    show("无元素", [r for r in pl if el(r[0]) is None])
    print("  【敌我】")
    show("玩家", pl)
    show("怪物", [r for r in rows if "monskill" in r[0]])
    print("  【主体 body / 辅助 fuzhu】")
    show("body", [r for r in pl if "_body" in r[0]])
    show("fuzhu", [r for r in pl if "fuzhu" in r[0]])
    forms = collections.defaultdict(set)
    for n, _ in pl:
        m = re.match(r"fx_pa?l?a?yerskill_([a-z]+)", n)
        forms[m.group(1) if m else "?"].add(el(n) or "-")
    print("  【玩家技能 形态 × 元素（每格各一套成品）】")
    for f, es in sorted(forms.items(), key=lambda kv: -len(kv[1]))[:8]:
        print("    %-10s %s" % (f, " ".join(sorted(es))))


# ───────────────────────── ③ 技能数据
def skills():
    print("③ 技能数据")
    env = load("loose_assets_assets_meta_meta.bytes.bundle")
    raw = None
    for o in env.objects:
        if o.type.name == "TextAsset":
            b = o.read().m_Script
            b = b.encode("utf-8", "surrogateescape") if isinstance(b, str) else bytes(b)
            raw = gzip.decompress(b[b.find(b"\x1f\x8b"):]).decode("utf-8", "replace")
    if raw is None:
        raise SystemExit("✗ meta 包里没有 TextAsset")
    docs = []
    for m in re.finditer(r"\{\s*\"meta\"\s*:\s*\{", raw):
        d, i = 0, m.start()
        for j in range(i, len(raw)):
            if raw[j] == "{":
                d += 1
            elif raw[j] == "}":
                d -= 1
                if d == 0:
                    try:
                        docs.append(json.loads(raw[i:j + 1]))
                    except Exception:
                        pass
                    break
    C = collections.Counter
    cnt = {k: C() for k in ("cast", "entity", "trigger", "action", "block", "category", "element")}

    def walk(o, key=""):
        if isinstance(o, dict):
            t = o.get("type")
            if key == "entities" and t:
                cnt["entity"][t] += 1
            if key == "triggers" and t:
                cnt["trigger"][t] += 1
            if key == "action" and t:
                cnt["action"][t] += 1
            if isinstance(o.get("n"), str):
                cnt["block"][o["n"]] += 1
            v = o.get("visual")
            if isinstance(v, dict):
                cnt["category"][str(v.get("category"))] += 1
            for e in (o.get("element") or []) if isinstance(o.get("element"), list) else []:
                cnt["element"][str(e)] += 1
            for k, x in o.items():
                walk(x, k)
        elif isinstance(o, list):
            for x in o:
                walk(x, key)

    for d in docs:
        cnt["cast"][str((d.get("cast") or {}).get("type"))] += 1
        walk(d)
    print("  [分母] 技能文档 %d 份（每份 = meta 名字/描述/实现说明 + cast + entities + triggers）" % len(docs))
    for k in ("cast", "entity", "trigger", "action", "element"):
        print("    %-8s %d 种：%s" % (k, len(cnt[k]), cnt[k].most_common(10)))
    print("    积木 block %d 种：%s" % (len(cnt["block"]), [k for k, _ in cnt["block"].most_common(30)]))
    print("    外观类别 %d 种（前 12）：%s" % (len(cnt["category"]), cnt["category"].most_common(12)))
    ex = next((d for d in docs if d["meta"].get("name") == "灼烧弹"), None)
    if ex:
        print("  样例「灼烧弹」：" + json.dumps({k: ex[k] for k in ("cast", "entities", "triggers")}, ensure_ascii=False)[:600])


audio()
effects()
skills()
print("\nDONE")
