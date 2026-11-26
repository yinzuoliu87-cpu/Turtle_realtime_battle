"""cent_fix14_land_rise_1127.py —— 百夫长砸地后蹲起再起身(用户 11-27「人物砸地之后，应该是有个蹲起…然后站起身，然后再移动」)
  动作: PixelLab pixminimax 自定义动作 land_rise_a(组 01d3b303), 首帧 = shield_brace2/008(落地那一刻的下蹲举盾), 尾帧目标 = 站姿;
        12 帧: 1–6 再往下沉 2 像素蹲住 → 7–8 撑起 → 9–12 站直(末帧与站姿逐像素相同, 接待机不跳)
  画布 180×184, 与 180 方画布偏移 (0,-2) 逐像素对上(首帧与 shield_brace2/008 差 0)
  结算: 落地那一步起原地停 RISE_SEC 0.8 秒(不走不打, 与帧条等长); 帧条 12 帧 / 0.8 秒 = 15 fps, 播完自动回待机
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import io, os, shutil, zipfile
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CC = os.path.join(ROOT, "tools", "assetgen", "ai_src", "cent_char")
ZIP = os.path.join(ROOT, ".out", "cent_char_dl", "char3.zip")


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


## 帧夹: 000 = 站姿(打包对齐用), 001–012 = 生成的 1–12 贴进 180 方画布(偏移 0,-2)
D = os.path.join(CC, "land_rise")
os.makedirs(D, exist_ok=True)
shutil.copyfile(os.path.join(CC, "shield_brace2", "frame_000.png"), os.path.join(D, "frame_000.png"))
if os.path.exists(ZIP):
    z = zipfile.ZipFile(ZIP)
    for k in range(1, 13):
        src = Image.open(io.BytesIO(z.read("Idle/animations/land_rise_a/west/frame_%03d.png" % k))).convert("RGBA")
        fr = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
        fr.alpha_composite(src.crop((0, 2, 180, 182)))
        fr.save(os.path.join(D, "frame_%03d.png" % k), optimize=False)
open(os.path.join(D, "SOURCE.txt"), "w", encoding="utf-8").write(
    "land_rise(11-27 cent_fix14_land_rise_1127.py 生成)\n"
    "000 = shield_brace2/000(站姿, 打包时只用来对齐包围盒)\n"
    "001-012 = PixelLab pixminimax 自定义动作 land_rise_a(角色 9185546b, 组 01d3b303), 首帧 shield_brace2/008、尾帧目标 = 站姿;\n"
    "  画布 180×184 按 (0,-2) 贴进 180 方画布(首帧与 shield_brace2/008 逐像素相同)\n"
    "提示词: Recovering from a heavy landing: he stays crouched low behind his big shield for a beat with knees deeply bent, then plants his feet,\n"
    "  pushes up with his legs, straightens his back, lowers the shield to his side and stands up tall, ending in a relaxed upright stance holding the spear vertically.\n"
    "同时出了 land_rise_b(另一种写法), 第 2 帧有红色杂点, 不用。\n")

patch("tools/assetgen/pack_spear_chip_art.py", [
    ('    "eq-centurion-brace":  ("shield_mix",',
     '    "eq-centurion-rise":   ("land_rise",     list(range(1, 13))),   # 11-27 砸地后蹲住 → 撑起 → 站直(见 land_rise/SOURCE.txt) #\n'
     '    "eq-centurion-brace":  ("shield_mix",'),
])
patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ('"brace": "eq-centurion-brace.png", ', '"brace": "eq-centurion-brace.png", "rise": "eq-centurion-rise.png", '),
    ('func cent_impact(p: Dictionary) -> void:\n\tp["_slam_voff"] = Vector3.ZERO\n',
     'func cent_impact(p: Dictionary) -> void:\n\tp["_slam_voff"] = Vector3.ZERO\n'
     '\t_cent_play(p, "rise", 12.0 / SpearSynergySystem.RISE_SEC)   # 砸地后蹲住 → 撑起 → 站直(11-27 用户「应该是有个蹲起…然后站起身，然后再移动」), 播完自动回待机\n'),
])
patch("scripts/systems/equip/spear_synergy_system.gd", [
    ("const LAND_SEC := 1.2", "const RISE_SEC := 0.8   # 11-27 砸地后蹲起再起身: 落地那一步起原地停这么久(不走不打), 与 eq-centurion-rise 帧条等长\nconst LAND_SEC := 1.2"),
    ('\tp["untargetable_until"] = minf(float(p.get("untargetable_until", 0.0)), float(battle._t))\n\t_fx("cent_impact", [p])\n',
     '\tp["untargetable_until"] = minf(float(p.get("untargetable_until", 0.0)), float(battle._t))\n\tbattle._damage.channel(p, RISE_SEC)\n\t_fx("cent_impact", [p])\n'),
])
print("ok")
