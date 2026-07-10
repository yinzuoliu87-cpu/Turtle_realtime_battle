# -*- coding: utf-8 -*-
"""把超过 4096 的横条 sprite-sheet 重排成网格 (像素逐帧逐字节不变)。
为什么: 安卓 GL_MAX_TEXTURE_SIZE 常见 4096/8192, 10000x500 的贴图【创建失败 → 采样即黑】。

不变量(逐条断言):
  · 每一帧的像素与原图对应帧【完全相同】(bytes 级)
  · 帧序 row-major (frame 0..n 顺序不变) —— Sprite3D 的 hframes/vframes 就是 row-major
  · frameW/frameH 不变 → pixel_size / offset / 图鉴缩放全都不用改
  · pets.json 的 sprite.frames 改成【有效帧数】(旧: min(declared, total-1); drop_last 会再丢一帧,
    所以新 declared 必须 = 旧有效帧数, 否则动画会多播一帧)
"""
import io, json, math, os
from PIL import Image

plan = json.load(io.open("c:/tmp/repack.json", encoding="utf-8"))
report = []
for e in plan:
    fp = "assets/sprites/" + e["img"]
    im = Image.open(fp).convert("RGBA")
    w, h = im.size
    fw, fh, total, cols, rows = e["fw"], e["fh"], e["total"], e["cols"], e["rows"]
    assert w == total * fw and h == fh, "%s 不是单行横条: %dx%d" % (e["id"], w, h)

    # 原图逐帧切出
    frames = [im.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(total)]

    new = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        new.paste(f, (c * fw, r * fh))

    # ★逐帧像素断言: 新图里第 i 格 == 原图第 i 帧
    for i in range(total):
        r, c = divmod(i, cols)
        got = new.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
        assert got.tobytes() == frames[i].tobytes(), "%s 第 %d 帧像素不一致!" % (e["id"], i)
    # 空白格必须全透明
    for i in range(total, cols * rows):
        r, c = divmod(i, cols)
        cell = new.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
        assert cell.getextrema()[3] == (0, 0), "%s 空白格 %d 不是全透明" % (e["id"], i)

    assert max(new.size) <= 4096, "%s 重排后仍超 4096: %s" % (e["id"], new.size)
    new.save(fp)
    report.append("  %-10s %5dx%-5d -> %4dx%-4d  (%d列x%d行, 总格%d, 有效帧%d)"
                  % (e["id"], w, h, new.size[0], new.size[1], cols, rows, cols * rows, e["eff"]))

# pets.json: sprite.frames -> 有效帧数
raw = io.open("data/pets.json", encoding="utf-8").read()
doc = json.loads(raw)
pets = doc["pets"] if isinstance(doc, dict) else doc
eff = {e["id"]: e["eff"] for e in plan}
n = 0
for p in pets:
    if p["id"] in eff and isinstance(p.get("sprite"), dict):
        old = p["sprite"].get("frames")
        if old != eff[p["id"]]:
            p["sprite"]["frames"] = eff[p["id"]]
            n += 1
out = json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
json.loads(out)
assert len(pets) == 28
io.open("data/pets.json", "w", encoding="utf-8", newline="\n").write(out)

io.open("c:/tmp/repack_done.txt", "w", encoding="utf-8").write(
    "重排 %d 张 (像素逐帧断言通过):\n" % len(plan) + "\n".join(report)
    + "\n\npets.json sprite.frames 改了 %d 处 (改成有效帧数, 保证 drop_last 后帧数不变)" % n)
print("repack ok: %d 张, pets.json 改 %d 处" % (len(plan), n))
