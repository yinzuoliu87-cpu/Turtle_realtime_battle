"""cent_char_engine_1127.py —— 百夫长新形象接进引擎(帧条见 pack_spear_chip_art.py 的 CENT2):
  · 帧宽 128 → 192(spear_eq_vfx.CENT_FW + 主场景召唤物帧表)
  · 放大倍数 1.3 → 1.55: 旧版人约 101 / 128 帧、屏幕上 ≈ 2.64 米(探针 px 0.02612); 新版人约 127 / 192 帧 ⇒ 2.572 × 1.55 / 192 × 127 ≈ 2.64 米
  · 普攻命中帧 3 → 5(矛尖最远)
  · 横扫: 新帧条 eq-centurion-sweep(原地转一圈), 放盾横扫那一刻播(用户 11-27「我们是…原地横扫转一圈啊」)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ('const CENT_SHEETS := {"attack": "eq-centurion-attack.png", "throw": "eq-centurion-throw.png", "shield": "eq-centurion-shield.png"}\n'
     'const CENT_FW := 128\n',
     'const CENT_SHEETS := {"attack": "eq-centurion-attack.png", "throw": "eq-centurion-throw.png", "shield": "eq-centurion-shield.png", "sweep": "eq-centurion-sweep.png"}\n'
     'const CENT_FW := 192   # 11-27 换 PixelLab「角色」流程新形象: 192 方帧(人约 127 像素高)\n'),
    ('func cent_sweep(u: Dictionary) -> void:\n',
     'func cent_sweep(u: Dictionary) -> void:\n'
     '\t_cent_play(u, "sweep", 16.0)   # 本体原地转一圈横扫(12 帧 0.75 秒; 用户 11-27「原地横扫转一圈」)\n'),
])
patch("scripts/scenes/RealtimeBattle3DScene.gd", [
    ('"eq-centurion": ["vfx/eq-centurion-idle.png", 128],',
     '"eq-centurion": ["vfx/eq-centurion-idle.png", 192],'),
])
patch("scripts/systems/equip/spear_synergy_system.gd", [
    ('"vis_mul": 1.3,', '"vis_mul": 1.55,'),
])
patch("scripts/gamedata/attack_hits.gd", [
    ('"vfx/eq-centurion-attack.png": 3,', '"vfx/eq-centurion-attack.png": 5,'),
])
print("ok")
