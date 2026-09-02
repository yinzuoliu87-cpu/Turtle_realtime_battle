class_name ActionElite
extends RefCounted
## 【非标准一次性动作】的总表 —— 从 RealtimeBattle3DScene.gd 搬出来 (2026-09-03)。
##
## ★为什么搬: CLAUDE.md §5 落位表写着「纯数据 / 常量表 → scripts/gamedata/」,
##   而这张表是纯常量。2026-09-03 给斧头加了八个招式条目, 主文件 8928 → 8949 行,
##   `arch_budget` 当场红。**不抬台账** —— 按落位表把整表搬走, 主文件净减 28 行。
##
## ★表名叫 ELITE 只是历史包袱: 它实际是"committed 动作"的总表 ——
##   `battle_vfx` 的打断闸认的就是 `ACTION_ELITE.has(_cur_act)`,
##   登记进来的动作播到一半不会被普攻顶掉。精英小将的五个招式与斧头的九个都在这。
##
## ★格式: `键: [相对 assets/sprites 的路径, fps]`。
##   fps **一律由代码里的真实节拍倒推**, 不是拍的 —— 见各行注释。

const TABLE := {
	"axe_cast": ["vfx/eq-axe-cast.png", 12.0],   # 096 斧头召唤物·技能释放(2026-09-01)
	## ★★096 斧头的八个招式帧 —— 素材 2026-09-01 就在盘上(全部 480x80 = 6 帧 x 80),
	##   但**一张都没登记、零调用者**, 于是石斧/铁斧/金斧/钻石斧的四条被动和三个造物主动
	##   在场上全是"站着不动就把伤害结算了"(用户 2026-09-03:「钻石以及4个最终造物什么特效
	##   都没有是吧」)。同族: memory [[fb-zero-caller-is-a-whole-class]]。
	## ★fps 一律由**代码里的真实节拍**倒推, 不是拍的(照 whirl/hammer 那几行的规矩):
	##     普攻间隔 = 1/MINION_ASPD = 1/0.8 = 1.25 秒 ⇒ 招式动画占约 60% = 0.75 秒
	##     ⇒ 6 帧 / 0.75 秒 = 8.0 fps          (smash/cleave/sweep/slam/execute 五个瞬发式)
	##     炽天使 SERAPH_CAST_TIME 4 秒甩 SERAPH_BOOMERANGS 10 把 ⇒ 每把 0.4 秒
	##     ⇒ 6 帧 / 0.4 秒 = 15.0 fps          (throw)
	##     charge/plant 是**持续 4 秒**的状态(CHARGE_TIME / HOLO_PLANT_TIME), 走循环播放,
	##     单圈仍取 0.75 秒 = 8.0 fps ⇒ 4 秒里循环 5.3 圈。
	##     ⚠ 别把 4 秒摊成 6 帧(1.5 fps / 每帧 667ms) —— 远超本项目 62~208ms 的区间,
	##       看上去是卡住而不是蓄力(hammer_big 那行注释记的就是同一个坑)。
	"axe_smash":   ["vfx/eq-axe-smash.png", 8.0],    # 被动3 石斧·每 SMASH_IV=9 秒的强化猛砸
	"axe_cleave":  ["vfx/eq-axe-cleave.png", 8.0],   # 被动4 铁斧·每第 2 次普攻竖劈
	"axe_sweep":   ["vfx/eq-axe-sweep.png", 8.0],    # 被动5 金斧·每第 1 次普攻 180° 横扫
	"axe_charge":  ["vfx/eq-axe-charge.png", 8.0],   # 被动6 钻石斧·4 秒蓄力(循环)
	"axe_slam":    ["vfx/eq-axe-slam.png", 8.0],     # 被动6 钻石斧·蓄力完毕砸下
	"axe_throw":   ["vfx/eq-axe-throw.png", 15.0],   # 炽天使·甩回旋镖(4 秒 10 把 ⇒ 每把 0.4 秒)
	"axe_plant":   ["vfx/eq-axe-plant.png", 8.0],    # 全息·插地开法阵 4 秒(循环)
	"axe_execute": ["vfx/eq-axe-execute.png", 8.0],  # 余烬·处决
	"whirl":      ["pets/animations/elite/whirl.png", 9.52],      # 4帧 / 0.42s
	"hammer":     ["pets/animations/elite/hammer.png", 9.30],     # 4帧 / 0.43s
	"hammer_big": ["pets/animations/elite/hammer_big.png", 12.24],# 18帧 / 1.47s(含1s hold)
	"whip":       ["pets/animations/elite/whip.png", 14.0],       # 7帧 / 0.50s ≈ 节拍 0.48s
	"consume":    ["pets/animations/elite/consume.png", 6.0],     # 9帧 / 1.50s
}
