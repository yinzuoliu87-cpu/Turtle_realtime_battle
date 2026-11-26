"""tame_cap_cut_1126.py —— 训龟大师【驯服】削弱: 归顺后每秒削 5% 生命值上限(按归顺时的上限算), 20 秒后上限 1 点
用户 11-26 晚:「训龟大师的驯服技能需要进行削弱…现在是改为每秒开始削减百分之五的生命值上限，所以…在二十秒之后。这个龟的生命值上限将会被削为一点，你这一碰就死。」
原来: 每秒损失 5% 最大生命值的真实伤害(扣当前血, 能被治疗 / 护盾抵掉, 上限不变)。
现在: 每秒最大生命值减少基准的 5%(基准 = 开始削的那一刻的最大生命值, 记 _tame_max0), 最低 1 点; 当前血不超过新上限。不是伤害(不过护盾、不算谁的输出)。
跨进终极战场: 已削的次数 _tame_cut_n 记进幸存名单, 重建后按新上限的同一比例补削, 接着往下削(否则换路就回满)。
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/RealtimeBattle3DScene.gd", [
    ("const TAME_DECAY_PCT := 0.05      # 归顺后每秒损失 5% 最大生命(用户 11-08: 2% → 5%)\n",
     "const TAME_DECAY_PCT := 0.05      # 归顺后每秒削减基准 5% 的生命值上限, 20 秒后上限 1 点(用户 11-26 晚: 原为每秒 5% 真伤; 11-08: 2% → 5%)\n", 1),
])

TS = "scripts/systems/trainer/trainer_system.gd"
patch(TS, [
    ("#   · 归顺后每秒损失 TAME_DECAY_PCT(5%) 最大生命(永久, 没有解除手段)\n",
     "#   · 归顺后每秒削减 TAME_DECAY_PCT(5%) 生命值上限(按开始削时的上限算, 20 秒后 1 点; 永久, 没有解除手段; 用户 11-26 晚)\n", 1),
    ("""		var amt: int = maxi(1, int(round(float(u["maxHp"]) * battle.TAME_DECAY_PCT))) * ticks
		# ★参数位置: _apply_damage(u, dmg, col, src, bucket, is_self, ...) ——
		#   第 4 个是 src 不是 is_self。写成 (u, d, col, true) 会把 true 当 src 传进去。
		battle._damage._apply_damage(u, amt, Color("#8b2e4a"), null, "tru", true)
""", """		tame_cut(u, int(u.get("_tame_cut_n", 0)) + ticks)


## ★★11-26 晚用户改: 不再是每秒 5% 真实伤害, 而是每秒削 5% 生命值上限 ——「二十秒之后…生命值上限将会被削为一点，你这一碰就死」。
##   基准 _tame_max0 = 第一次削的那一刻的最大生命值(之后别的效果加的上限不进基准); 第 n 次后上限 = max(1, 基准 × (1 − 5% × n))。
##   不是伤害: 不过护盾、不进任何人的输出统计; 当前血只是被压到不超过新上限。
##   n 记在 _tame_cut_n, 跨进终极战场时写进幸存名单, 重建后用新上限当基准补到同一个 n(换路不回满)。
func tame_cut(u: Dictionary, n: int) -> void:
	if not u.has("_tame_max0"):
		u["_tame_max0"] = float(u.get("maxHp", 1.0))
	var base: float = float(u["_tame_max0"])
	var cap: float = maxf(1.0, round(base * (1.0 - battle.TAME_DECAY_PCT * float(n))))
	var cut: int = int(float(u.get("maxHp", 1.0)) - cap)
	u["_tame_cut_n"] = n
	if cut <= 0:
		return
	u["maxHp"] = cap
	if float(u.get("hp", 0.0)) > cap:
		u["hp"] = cap
	battle._vfx._float_text(u["pos"] + Vector2(0, -40), Lang.t("生命上限 -%d") % cut, Color("#8b2e4a"))
""", 1),
])

patch("scripts/scenes/battle/dual_lane_flow.gd", [
    ("""				spec["tamed_side"] = str(u["tamed_side"])
				spec["tame_used"] = true
""", """				spec["tamed_side"] = str(u["tamed_side"])
				spec["tame_used"] = true
				spec["tame_cut_n"] = int(u.get("_tame_cut_n", 0))   # 已削了几次生命值上限(11-26 晚驯服削弱): 进终极战场按同一比例补削
""", 1),
])
patch("scripts/scenes/battle/battle_spawn.gd", [
    ("""			made["_tame_decay_next"] = -1.0                      # 掉血节拍重新起算(进场后整 1 秒才掉第一次)
""", """			made["_tame_decay_next"] = -1.0                      # 削上限节拍重新起算(进场后整 1 秒才削下一次)
			if int(u.get("tame_cut_n", 0)) > 0:                  # 已削过的上限跟过去(否则换路就回满; 11-26 晚驯服削弱)
				made["_tame_max0"] = float(made["maxHp"])
				var tcap: float = maxf(1.0, round(float(made["maxHp"]) * (1.0 - battle.TAME_DECAY_PCT * float(u["tame_cut_n"]))))
				made["maxHp"] = tcap
				made["hp"] = minf(float(made.get("hp", tcap)), tcap)
				made["_tame_cut_n"] = int(u["tame_cut_n"])
""", 1),
])

OLD = "此后每秒损失 5% 最大生命值，持续作战至终极战场。"
NEW = "此后每秒最大生命值降低复活时的 5%，20 秒后降至 1 点，持续作战至终极战场。"
patch("scripts/scenes/TrainerConfigScene.gd", [(OLD, NEW, 1)])
print("ok")

## 英文
p = os.path.join(ROOT, "locale/en.po")
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
pairs = [
    ("复活后 2.5 秒无敌，此后每秒损失 5% 最大生命值，持续作战至终极战场。冷却 999 秒，未命中时冷却 30 秒。\"",
     "复活后 2.5 秒无敌，此后每秒最大生命值降低复活时的 5%，20 秒后降至 1 点，持续作战至终极战场。冷却 999 秒，未命中时冷却 30 秒。\""),
    ("then loses 5% max health per second, fighting on into the Final Battle.",
     "then its max health drops by 5% of its revived max health every second, down to 1 after 20 seconds, fighting on into the Final Battle."),
]
for a, b in pairs:
    assert s.count(a) == 1, a[:40]
    s = s.replace(a, b)
s = s.rstrip("\n") + "\n\nmsgid \"生命上限 -%d\"\nmsgstr \"Max Health -%d\"\n"
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("en ok")
