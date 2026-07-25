# 28 龟战斗属性 —— 单一事实源 (从 RealtimeBattle3DScene 抽出, 供战斗+图鉴同源读)。
# id → [melee(近战bool), move_spd(px/s), atk_interval(s), atk_range(px)]。攻速=1/atk_interval。
# ★攻速按定位压到 0.6-0.85 次/秒: 刺客0.85/近战斗士0.8/远程射手0.75/法师+辅助0.7/坦克0.6; 精英0.65(另处硬编)。
# 等级缩放(战斗 _make_unit): 攻速 +2%/级(atk_interval /= 1+0.02*(lv-1)); 移速不缩放。图鉴显示须同口径。
extends RefCounted

const STATS := {
	"basic": [true, 105.0, 1.25, 70.0], "stone": [true, 70.0, 1.6667, 70.0], "bamboo": [true, 105.0, 1.4286, 70.0],
	"angel": [false, 105.0, 1.4286, 400.0], "ice": [false, 105.0, 1.4286, 400.0], "ninja": [true, 145.0, 1.1765, 70.0],
	"two_head": [false, 145.0, 1.25, 400.0], "ghost": [false, 145.0, 1.1765, 400.0], "diamond": [true, 70.0, 1.6667, 70.0],
	"fortune": [true, 105.0, 1.4286, 70.0], "dice": [true, 145.0, 1.1765, 70.0], "rainbow": [true, 105.0, 1.4286, 70.0],
	"gambler": [false, 145.0, 1.3333, 400.0], "hunter": [false, 145.0, 1.3333, 400.0], "pirate": [true, 105.0, 1.25, 70.0],   # 赌神0.75次/秒(远程射手档·多段CD另算·2026-07-18)
	"candy": [true, 105.0, 1.4286, 70.0], "bubble": [false, 70.0, 1.4286, 400.0], "line": [false, 145.0, 1.4286, 400.0],
	"lightning": [false, 145.0, 1.4286, 400.0], "phoenix": [false, 105.0, 1.4286, 400.0], "lava": [false, 145.0, 1.4286, 400.0],
	"cyber": [false, 74.0, 1.3333, 450.0], "crystal": [true, 70.0, 1.6667, 70.0], "chest": [true, 105.0, 1.4286, 70.0],   # cyber移速74(削30%·2026-07-16)/攻速0.75射手档
	"space": [false, 145.0, 1.4286, 400.0], "hiding": [true, 70.0, 1.6667, 70.0], "headless": [true, 145.0, 1.25, 70.0],   # space攻速保0.7=1/0.7间隔(法师档·用户2026-07-16封板令)
	"shell": [true, 105.0, 1.6667, 70.0],
}
