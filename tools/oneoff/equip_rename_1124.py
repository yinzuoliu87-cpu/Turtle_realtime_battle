"""equip_rename_1124.py —— 装备名 / 图标去 AI 味(2026-11-24 · 方案书 docs/plans/20261124c-装备名与图标去AI味.md)

  python tools/oneoff/equip_rename_1124.py sheet   # 出对照图 .out/equip_names/rename_*.png(图标 · 旧名 → 新名 · 理由)

RENAME = 建议表(用户拍板前是草案; 拍板后按用户改过的为准)。理由码:
  生造 = 修饰词叠加 / 拼出来的不存在的东西      海洋 = 硬加深海·潮汐·珊瑚·鲸之类前缀
  占位 = 像占位名 / 技术术语                    撞名 = 与另一件几乎同名
  图不符 = 名字与图标画的东西对不上(改名让它们对上, 或另重画图标)
ICON = 图标问题(重画候选)。
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")

## ★11-24 用户逐件过完(原话见方案书 §7): 下表 = 用户定下的; PENDING = 用户让我起名 / 还要再定的(定了再挪进 RENAME)
RENAME = {
    "p2eq_022": ("燃烧瓶", "用户定"),
    "p2eq_041": ("潮汐药水", "用户定"),
    "p2eq_044": ("珍珠项链", "用户定"),
    "p2eq_048": ("燧发枪", "用户定"),
    "p2eq_060": ("水母伞", "用户定"),
    "p2eq_073": ("藤弓", "用户定"),
    "p2eq_077": ("小手枪", "用户定"),
    "p2eq_085": ("蓄电池", "用户定"),
    "p2eq_088": ("潮汐图腾", "用户定"),
    "p2eq_089": ("符咒", "用户定"),
    "p2eq_091": ("龟甲", "用户定"),
    "p2eq_008": ("珊瑚刺", "用户定"),
    "p2eq_013": ("烤海胆", "用户定"),
    "p2eq_019": ("药膏", "用户定"),
    "p2eq_039": ("竹弓", "用户定"),
    "p2eq_042": ("活力药水", "用户定"),
    "p2eq_047": ("战锤", "用户定"),
    "p2eq_049": ("手弩", "用户定"),
    "p2eq_078": ("双管枪", "用户定"),
    "p2eq_092": ("毒蛾", "用户定"),
    "p2eq_011": ("血滴护符", "用户定"),
    "p2eq_021": ("蚌壳", "用户定"),
    "p2eq_023": ("火珊瑚", "用户定"),
    "p2eq_029": ("寒冰法杖", "用户定"),
    "p2eq_037": ("蜡烛", "用户定"),
    "p2eq_053": ("喇叭枪", "用户定"),
    "p2eq_058": ("远古炮塔", "用户定"),
    "p2eq_065": ("轻盈药水", "用户定"),
    "p2eq_079": ("医疗塔", "用户定"),
    "p2eq_083": ("细剑", "用户定"),
    "p2eq_015": ("荆棘盾牌", "用户定"),
    "p2eq_050": ("加特林", "用户定"),
    "p2eq_057": ("狙击枪", "用户定"),
    "p2eq_064": ("溺者符囊", "用户定"),
    "p2eq_066": ("狂暴药水", "用户定"),
    "p2eq_076": ("连弩", "用户定"),
    "p2eq_094": ("墓碑", "用户定"),
    "p2eq_033": ("魔法海螺", "用户定"),
    "p2eq_068": ("氧气瓶", "用户定"),
    "p2eq_072": ("蛋糕盒", "用户定"),
    "p2eq_080": ("旋翼机", "用户定"),
    "p2eq_087": ("潜水钟", "用户定"),
    "p2eq_032": ("骨哨", "用户定"),
    "p2eq_070": ("大火腿", "用户定"),
    "p2eq_086": ("终极浮游炮", "用户定"),
    "p2eq_027": ("电击器", "用户定"),
    "p2eq_063": ("灵火", "用户定"),
    "p2eq_030": ("粉色迷你水晶", "用户定"),
    "p2eq_031": ("蓝色迷你水晶", "用户定"),
}
## 用户让我起名 / 待定: id → (我的建议, 备选)
PENDING = {}
## 效果说明里跟着旧名起的机制词(用户 11-24: 灵火那件(用户「不是灵环，是灵火，就是火焰的火」)⇒ 效果说明【气环】一起改)
TERMS = {"气环": "灵火"}
## 新英文名(en.po msgstr / glossary_en.md)。旧英文名从 en.po 里按旧中文 msgid 取。
EN = {
    "燃烧瓶": "Molotov", "潮汐药水": "Tide Potion", "珍珠项链": "Pearl Necklace", "燧发枪": "Flintlock",
    "水母伞": "Jellyfish Umbrella", "藤弓": "Vine Bow", "小手枪": "Little Pistol", "蓄电池": "Battery",
    "潮汐图腾": "Tide Totem", "符咒": "Talisman", "龟甲": "Tortoise Shell", "珊瑚刺": "Coral Spike",
    "烤海胆": "Grilled Urchin", "药膏": "Salve", "竹弓": "Bamboo Bow", "活力药水": "Vigor Potion",
    "战锤": "Warhammer", "手弩": "Hand Crossbow", "双管枪": "Double-Barrel", "毒蛾": "Venom Moth",
    "血滴护符": "Blood Drop Amulet", "蚌壳": "Clam Shell", "火珊瑚": "Fire Coral", "寒冰法杖": "Frost Staff",
    "蜡烛": "Candle", "喇叭枪": "Blunderbuss", "远古炮塔": "Ancient Turret", "轻盈药水": "Swiftness Potion",
    "医疗塔": "Medic Tower", "细剑": "Rapier", "荆棘盾牌": "Thorn Shield", "加特林": "Gatling",
    "狙击枪": "Sniper Rifle", "溺者符囊": "Drowned Charm Pouch", "狂暴药水": "Berserk Potion", "连弩": "Repeating Crossbow",
    "墓碑": "Tombstone", "魔法海螺": "Magic Conch", "氧气瓶": "Oxygen Tank", "蛋糕盒": "Cake Box",
    "旋翼机": "Gyrocopter", "潜水钟": "Diving Bell", "骨哨": "Bone Whistle", "大火腿": "Big Ham",
    "终极浮游炮": "Ultimate Drone Cannon", "电击器": "Stun Gun",
    "灵火": "Spirit Flame", "粉色迷你水晶": "Pink Mini Crystal", "蓝色迷你水晶": "Blue Mini Crystal",
}

ICON = {
    "p2eq_036": "图不符: 画的是孵化器, 不是温泉蛋",
    "p2eq_039": "图不符: 画的是竹叶, 不是弓",
    "p2eq_082": "图不符: 画的是贝壳, 不是护甲",
    "p2eq_064": "看不出是什么(白色蛋形)",
    "p2eq_037": "看不出是什么(一团)",
    "p2eq_030": "AI 大图缩小 · 球里是动漫人物",
    "p2eq_031": "AI 大图缩小 · 球里是动漫人物",
    "p2eq_034": "AI 大图缩小(609px)· 风格不一致",
    "p2eq_033": "AI 大图缩小(500px)",
    "p2eq_052": "AI 大图缩小(1024px)· 写实",
    "p2eq_056": "AI 大图缩小(1024px)· 写实",
    "p2eq_059": "AI 大图缩小(642px)",
    "p2eq_026": "AI 大图缩小(1024px)",
    "p2eq_043": "AI 大图缩小(1024px)",
    "p2eq_029": "AI 大图缩小(510px)",
    "p2eq_047": "AI 大图缩小(500px)",
    "p2eq_023": "AI 大图缩小(518px)",
    "p2eq_046": "AI 大图缩小(505px)",
    "p2eq_038": "AI 大图缩小(832px)",
    "p2eq_027": "AI 大图缩小(1024px)",
    "p2eq_025": "AI 大图缩小(510px)",
    "p2eq_032": "改名后图不符: 画的是一团绿火",
    "p2eq_073": "改名后图不符: 画的是藤环, 不是弓",
    "p2eq_085": "改名后图不符: 画的是底座上的火苗",
    "p2eq_091": "改名后图不符: 画的是螺壳",
    "p2eq_078": "改名后图不符: 画的是一捆带电的东西",
    "p2eq_070": "改名后图不符: 画的是一摞砖",
    "p2eq_086": "改名后图不符: 画的是六分仪",
    "p2eq_090": "改名后图不符: 画的是狼牙棒",
}


def sheet():
    from PIL import Image, ImageDraw, ImageFont
    d = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "data/phase2-equipment.json"), encoding="utf-8"))}
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 17)
    fs = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 13)
    ids = sorted(set(RENAME) | set(ICON), key=lambda i: (d[i]["cost"], i))
    W, H, IC, PER = 760, 78, 64, 20
    out = os.path.join(ROOT, ".out", "equip_names")
    os.makedirs(out, exist_ok=True)
    for part in range((len(ids) + PER - 1) // PER):
        chunk = ids[part * PER:(part + 1) * PER]
        im = Image.new("RGB", (W, H * len(chunk) + 36), (30, 34, 42))
        dr = ImageDraw.Draw(im)
        dr.text((12, 8), "图标 · 现在的名字 → 建议的新名字 · 理由 · 图标问题(第 %d 页)" % (part + 1), fill=(150, 200, 255), font=fs)
        for k, i in enumerate(chunk):
            y = 36 + k * H
            if k % 2:
                dr.rectangle([0, y, W, y + H], fill=(36, 41, 50))
            e = d[i]
            ic = Image.open(os.path.join(ROOT, "assets/sprites", e["img"])).convert("RGBA")
            ic.thumbnail((IC, IC), Image.LANCZOS)
            if max(ic.size) < IC:
                s = IC // max(ic.size)
                ic = ic.resize((ic.width * s, ic.height * s), Image.NEAREST)
            im.paste(ic, (10 + (IC - ic.width) // 2, y + 7 + (IC - ic.height) // 2), ic)
            dr.text((86, y + 8), "%d费" % e["cost"], fill=(150, 160, 175), font=fs)
            if i in RENAME:
                new, why = RENAME[i]
                dr.text((126, y + 6), e["name"], fill=(200, 200, 200), font=f)
                x = 126 + dr.textlength(e["name"], font=f) + 10
                dr.text((x, y + 6), "→", fill=(150, 160, 175), font=f)
                dr.text((x + 28, y + 6), new, fill=(255, 214, 90), font=f)
                dr.text((420, y + 8), why, fill=(255, 150, 120), font=fs)
            else:
                dr.text((126, y + 6), e["name"] + "(名字不改)", fill=(200, 200, 200), font=f)
            if i in ICON:
                dr.text((126, y + 42), "图标: " + ICON[i], fill=(140, 220, 160), font=fs)
        p = os.path.join(out, "rename_%d.png" % (part + 1))
        im.save(p)
        print(p, len(chunk))
    print("改名 %d 件 · 图标重画候选 %d 件 · 合计涉及 %d 件" % (len(RENAME), len(ICON), len(ids)))
    news = [v[0] for v in RENAME.values()]
    keep = [e["name"] for k, e in d.items() if k not in RENAME and e.get("shopAvailable") == 1]
    dup = sorted({n for n in news if news.count(n) > 1 or n in keep})
    print("新名重名 / 与不改的撞名:", dup or "无")


## 改名只换玩家看得到 / 测试会比的地方; 历史文档(docs/、CHANGELOG)、旧报告、本脚本自己(存着旧名)不动; 文案金标交给 regen_goldens。
SKIP_PREFIX = ("docs/", "tests/golden/", ".out/", "CHANGELOG.md", "tools/oneoff/equip_rename_1124.py", "tools/plans_")
EXTS = (".gd", ".json", ".po", ".md", ".py", ".tscn", ".txt", ".cfg")


def _sub_all(text, mapping):
    import re
    if not mapping:
        return text, 0
    keys = sorted(mapping, key=len, reverse=True)          # 长的先配(连发弩机 先于 连发弩); 一遍同时替换, 不会换两次
    rx = re.compile("|".join(re.escape(k) for k in keys))
    n = [0]

    def rep(m):
        n[0] += 1
        return mapping[m.group(0)]
    return rx.sub(rep, text), n[0]


def apply():
    import re, subprocess
    d = {e["id"]: e for e in json.load(open(os.path.join(ROOT, "data/phase2-equipment.json"), encoding="utf-8"))}
    zh = {d[i]["name"]: new for i, (new, _) in RENAME.items() if d[i]["name"] != new}
    zh.update(TERMS)
    po_path = os.path.join(ROOT, "locale/en.po")
    po = open(po_path, encoding="utf-8").read()
    old_en = dict(re.findall(r'^msgid "(.*)"\r?\nmsgstr "(.*)"\r?$', po, re.M))
    en = {}
    for old, new in zh.items():
        if old in old_en and old_en[old] and new in EN and old_en[old] != EN[new]:
            en[old_en[old]] = EN[new]
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    tot = 0
    touched = []
    for f in files:
        if f.startswith(SKIP_PREFIX) or not f.endswith(EXTS) or re.search(r"report.*\.txt$", f):
            continue
        p = os.path.join(ROOT, f)
        b = open(p, "rb").read()
        try:
            t = b.decode("utf-8")
        except UnicodeDecodeError:
            continue
        t2, n = _sub_all(t, zh)
        n2 = 0
        if f in ("locale/en.po", "locale/glossary_en.md"):
            if f.endswith(".po"):        # 英文只换 msgstr 行
                lines = t2.split("\n")
                for k, ln in enumerate(lines):
                    if ln.startswith("msgstr "):
                        lines[k], c = _sub_all(ln, en)
                        n2 += c
                t2 = "\n".join(lines)
            else:
                t2, n2 = _sub_all(t2, en)
        if n or n2:
            open(p, "wb").write(t2.encode("utf-8"))
            tot += n + n2
            touched.append("%s(%d+%d)" % (f, n, n2))
    ## en.po 去重: 改名后撞上已有词条(例: 铜管手铳 → 小手枪 = 召唤物已有的「小手枪」)⇒ 留第一条
    raw = open(po_path, "rb").read().decode("utf-8")
    nl = "\r\n" if raw.count("\r\n") > raw.count("\n") / 2 else "\n"
    po = raw.replace("\r\n", "\n")
    blocks = po.split("\n\n")
    seen = set()
    keep = []
    dup = 0
    for bl in blocks:
        m = re.search(r'^msgid "(.*)"$', bl, re.M)
        key = m.group(1) if m and not bl.lstrip().startswith("#~") else None
        if key and key in seen and "msgctxt" not in bl:
            dup += 1
            continue
        if key:
            seen.add(key)
        keep.append(bl)
    open(po_path, "wb").write("\n\n".join(keep).replace("\n", nl).encode("utf-8"))
    print("改了 %d 处 · %d 个文件 · en.po 去重 %d 条" % (tot, len(touched), dup))
    for t in touched:
        print("  " + t)
    left = [o for o in zh if o in open(os.path.join(ROOT, "data/phase2-equipment.json"), encoding="utf-8").read()]
    print("数据表里还剩旧名:", left or "无")


if __name__ == "__main__":
    if sys.argv[1:] == ["sheet"]:
        sheet()
    elif sys.argv[1:] == ["apply"]:
        apply()
    else:
        print(__doc__)
