class_name EqGunBatch
extends RefCounted
## eq_gun_batch.gd — 枪线四件新装备的效果本体
## 077 铜管手铳 · 078 电鳗双管铳 · 079 珊瑚急救塔 · 080 打捞旋翼机
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数都不许改。
## 演出层放 `scripts/scenes/battle/gun_eq_vfx.gd`(本文件自己 new 出来, 不进共享文件)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★本文件是【本批唯一归你的产品代码】—— 共享文件一律不要动
## ══════════════════════════════════════════════════════════════════════
## 已由主会话预接线、**不要改**:
##   · `scripts/systems/equip/equip_system.gd`      (声明/构造/tick/全部钩子派发)
##   · `scripts/systems/equip/equip_stats_apply.gd` (常驻字段/登场标记)
##   · `scripts/gamedata/equip_stats.gd`            (STATS 三星属性)
##   · `data/phase2-equipment.json`                 (名字/属性镜像/文案)
##   · `scripts/scenes/battle/dual_lane_flow.gd`    (换路调 clear_all)
## 归你的: **本文件** + `scripts/scenes/battle/gun_eq_vfx.gd` + `tests/verify_eq_gun_batch.gd/.tscn`
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(与批①/批② 同, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**。裸 `randi()`/`randf()` 会破坏确定性 ——
##    `tools/rng_discipline.py` 冻结了裸调用数, `verify_battle_determinism` 同种子比指纹。
##    ⚠ 080 的坠机目标是随机的, 必须走播种 RNG。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 处决 / 冰封 / 僵硬)。
##    ⚠ 080 的 3★ 一轮扫射 10 发 + 地毯轰炸连续投弹, 回钩 on-hit 会自激。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 所有"持续 N 秒 / 每 N 秒"
##    存**到期时刻**或**自管累加器**, 不许拿 `_t` 直接和常数比。
##    本文件**一个计时都没读 `battle._t` 当起点** —— 全是自己累加的 delta
##    (`e["acc"]` / `st["t"]` / `h["fire_t"]` / `h["doom_t"]` / `h["run_t"]`)。
##
## ══════════════════════════════════════════════════════════════════════
##  本批的分派落点(主会话已接好)
## ══════════════════════════════════════════════════════════════════════
##   077 → `on_spawn`(生成小手枪召唤物) + `tick`(小手枪自走)
##   078 → `tick_unit`(自管 2 秒交替左右管)
##   079 → `on_spawn`(生成医疗炮台) + `tick`(炮台自走, 攻速实时跟随携带者)
##   080 → `on_spawn`(生成直升机) + `tick`(盘旋/扫射/龟能/地毯轰炸/坠机) + `on_death`(倒计时坠机)
##
## ══════════════════════════════════════════════════════════════════════
##  ★金弹: 复用 `battle._queue_shots(n, gap, fn, src, gun_id)`, 没有第二套
## ══════════════════════════════════════════════════════════════════════
## 枪羁绊【金弹】= 每把枪射满 4/3/2 发额外射一发, 完整继承那一发的效果 + 60/80/100% 真伤,
## 金弹本身不计入计数。这套**已经实现在 `_queue_shots` 里**(RealtimeBattle3DScene.gd:4377):
##   · 计数存在 `src["_gun_shot_ct"][gun_id]` ⇒ **每把枪各自计数**是天然的;
##   · 金弹那一发**复用同一个 `fn`** ⇒ "完整继承效果"是结构性的, 不是抄一遍;
##   · 期间把 `src["_golden_pct"]` 标在 src 上, 伤害管线读它补真伤(`battle_damage.gd:150`)。
## ⇒ 本文件四件的每一发子弹/机炮/炸弹**都从这个出口出去**, 一行金弹逻辑都没有重写。
##   · 077 小手枪: `src` = 小手枪自己(它是单位) ⇒ 它自己一份计数, 与携带者互不相干;
##   · 078: `src` = 携带者, `gun_id="p2eq_078"` ⇒ 左右两管**共享一份计数**(规格原文"左右管共享计数"),
##          且金弹复用轮到那一管的 `fn` ⇒ "从轮到的那一管打出、完整继承该管效果"是天然的;
##   · 079 炮台: `src` = 炮台自己 ⇒ 规格要的"炮台自己维持一份金弹计数";
##   · 080: 直升机不是单位 ⇒ `src` = 携带者, 机炮与炸弹共用 `gun_id="p2eq_080"`(规格: 两者都计数)。
## ★读"这一发是不是金弹"就读 `src["_golden_pct"] > 0.0`(079 的治疗翻倍靠它)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★规格没写死、由我定的地方(交付要求 §8.4: 选了哪一侧 / 为什么 / 另一侧是什么)
## ══════════════════════════════════════════════════════════════════════
## D1【077 小手枪会不会走动】→ **会走**(远程 AI: 追到 700 码就停, 进到 490 码内会风筝后撤)。
##    另一侧是"钉在原地"。选会走: 规格写它是"召唤物"不是"炮台"(079 才写了生成位置),
##    而 700 码在 1596×728 的场地上够不到对面半场; 钉死会让它在拉扯局里整局空放。
##    ⚠ 代价: 它会往前挤 ⇒ 更容易被集火。规格的生存表(挨 15/30/50 下)本来就假设它会挨打。
##
## D2【077 的 +1 破甲按"每次攻击"还是"每发子弹"】→ **每次攻击各 +1, 金弹那一发不再 +1**。
##    另一侧是"每发子弹(含金弹)各 +1"。选前者: 规格与羁绊原文都写"金弹本身不计入计数",
##    金弹是**附赠**的一发, 让它也涨破甲等于把 3 档的破甲增速直接 ×1.5, 而规格的穿透曲线表
##    (10 秒 20 点 = 攻速 2/秒 × 10 秒)算的就是**每秒 2 点**, 与"每次攻击各 1"完全吻合。
##
## D3【077/079 的召唤物在携带者死后是否留场】→ **留场**。
##    077 规格明写"携带者死亡则受到的伤害降为 5 点" ⇒ 它必须还活着才有意义。
##    079 规格没写, 我按同批同口径给"留场"; 另一侧是"随携带者一起消失"。
##    ★079 在携带者死后**攻速取携带者字典里的最后数值**(单位字典阵亡后不销毁, 属性还在)——
##      与 DoT 的 `dot_src` 同口径(`battle_damage.gd:578` 注明"施加者死后按它死时的数值算")。
##
## D4【079 炮台的射程】→ **700 码**(与 077 小手枪同)。规格给了血/攻/双抗/攻速却**没给射程**。
##    另一侧是照 058 穿甲遗弹的炮台给 2000(全场)。选 700: 本批唯一被用户写出来的射程数字就是
##    077 的 700; 给全场射程会让"生成在携带者后方 150 码"这条**完全失去意义**(站哪都一样)。
##
## D5【079"最低血友军"含不含炮台/小手枪自己】→ **含**(它们是我方单位), 但**排除龟蛋与训龟大师**
##    (契约 §4 的全表通用口径)。另一侧是"只奶龟"。选前者: 077 的小手枪正是"需要被保护的资产",
##    两件枪装配套时炮台奶它是设计上说得通的正反馈。
##
## D6【080 携带者死后那 10 秒里直升机还打不打】→ **照常扫射/轰炸**。
##    另一侧是"只飞不打"。选前者: 规格原文是"继续飞行 10 秒", 而 §0.5 自己写了这条的用意是
##    "给对手一个明确的窗口感" —— 窗口要**有压力**才叫窗口, 只飞不打就只是个倒计时动画。
##
## D7【080 地毯轰炸投几枚 / 多久投完】→ **枚数是设计量 `BOMB_COUNT = 8/10/14`(按星级),
##    间距由它算出来**(`bomb_spacing` = 800 / (n-1) = 114.3 / 88.9 / 61.5 码);
##    航线速度 500 码/秒 ⇒ 全程 1.6 秒, 相邻两枚 0.229 / 0.178 / 0.123 秒。
##    ⚠ 这一段【曾经】写的是"每 160 码一枚共 6 枚 / 每 0.32 秒一枚 / 每枚半径 180 码" ——
##    那是 2026-08-08 被推翻的旧实现(见下方 `BOMB_COUNT` 处那段记录), 半径也早已是
##    `BOMB_R = 150`。升星改的就是覆盖密度, 三星不再长得一模一样。
##
## D8【080 轰炸期间机炮停不停】→ **停**(它在跑航线)。另一侧是边飞边扫射。
##    选停: 轰炸是"充能技能", 与普攻互斥在本项目是常规(龟的 windup 状态也锁普攻)。
##
## D9【080 航线候选集怎么枚举】→ **以每个敌人为带心 × 12 个固定方位(每 15°)**, 数覆盖人数取最大,
##    并列取先枚举到的那条(敌人按 `battle._units` 顺序, 方位按角度升序) ⇒ **完全确定性, 不掷骰**。
##    另一侧是连续优化(旋转卡壳求最优带)。选枚举: 规格明写"航线判据必须是确定性的、门禁可验",
##    枚举法的最优性可以被门禁**穷举复算**, 连续优化不能。
##
## ══════════════════════════════════════════════════════════════════════
##  ★077 的伤害封顶走【共用收口】, 不在本文件里补差额
## ══════════════════════════════════════════════════════════════════════
## "受到的所有伤害(含真伤)降为 2 点 / 携带者死后 5 点" 落在
## `RealtimeBattle3DScene._mitigate_incoming()` 末尾的带值闸 `_dmg_cap_val`
## (主会话 2026-08-06 应本路请求加的; 布尔版 `_dmg_cap_one` 是亡灵骷髅 032 的"命数式单位",
##  语义不同, 保留不动)。
## ⇒ 那里是**两条伤害路径唯一的共用收口**(CLAUDE.md §3.3), 所以真伤与 DoT 一并盖住;
##   而且值可以在战斗中改 —— 携带者一死, `on_death` 把它从 2 改成 5 就完事。
## ★我最初的绕法(靠 `_st_taken` 增量反推挨打次数再补扣差额)已整段删除:
##   它的可观测行为虽然对, 但依赖"`_st_taken` 增量 = 挨打次数"这个不变式,
##   而任何别的往 `_st_taken` 记账的东西都会**不报错地**把它悄悄弄偏。

var battle
var vfx

## 077 在场的小手枪: [{u, owner, si, acc(攻击累加器)}]
var _pistols: Array = []
## 079 在场的医疗炮台: [{u, owner, si, acc}]
var _towers: Array = []
## 080 在场的直升机(**不是单位**, 见 D-heli): [{owner, si, pos, vel, fire_t, energy, state, ...}]
var _helis: Array = []


func _init(b) -> void:
	battle = b
	vfx = GunEqVfx.new(b)


# ══════════════════════════════════════════════════════════════════
#  §常量 —— 只放"与某一件的三元数值无关"的口径
#  ★逐星三元数组一律【就近声明】在各自的 "p2eq_0XX" 字面量旁边:
#    tooltip_number_audit 靠 id 字面量 ±2500 字符判"这个数组是不是这件的",
#    提到文件顶部会被判【远处命中】直接红(契约 §6)。
# ══════════════════════════════════════════════════════════════════
## 金弹与本体之间的间隔(秒)。传给 `_queue_shots` 当 interval ——
## 单发时它只影响金弹的延迟(= interval × 0.5), 让金弹紧跟在本体之后半拍而不是同帧。
const GOLD_GAP := 0.12
## 077 小手枪: 攻速 2/秒 ⇒ 攻击间隔 0.5 秒 · 射程 700 码(规格原文)
const PISTOL_IV := 0.5
const PISTOL_RANGE := 700.0
## 077 小手枪的暴击率(规格原文 50%)
const PISTOL_CRIT := 0.5
## 077 小手枪的固定站位(2026-08-06 用户看图后要求): 携带者【斜后方】——
## 后退 PISTOL_BACK 码 + 抬高 PISTOL_SIDE_Y 码。规格没给站位, 这两个数是我定的:
## · 后退 70 码 ≈ 一个龟身多一点 —— 够分得开、又还在"跟着主人"的读感里(079 炮台是 150, 那是建筑)
## · 抬高 -34 码 = 斜后方而不是正后方, 免得与携带者的血条上下叠在一起
const PISTOL_BACK := 70.0
## ★2026-08-07 实拍后从 -34 加大到 -78: -34 时枪与目标的连线**正好穿过携带者的龟壳**
##   (枪在携带者左后方、目标在正右方 ⇒ 射线必然掠过携带者)。加大侧偏让弹道从龟【上方】过。
##   ⚠ 这两个数本来就是我定的(规格没给站位), 不是在改用户拍板的东西。
##   ★-78 又太高了(枪看着像挂在天上、不像携带者的枪), 回调到 -56: 弹道刚好从龟头上方掠过。
const PISTOL_SIDE_Y := -56.0
## 演出层还没回填 `_muzzle_px` 时的兜底半枪长(码)。实测 15.93(算式见下行), 取 15.9。
const PISTOL_MUZZLE_FALLBACK := 15.9   ## 实测: 0.4875 帧宽 × 40px × 0.0196 ÷ WS 0.024 = 15.9 码
## 077 每次攻击给自己 +1 护甲穿透(规格原文), 每路重置 —— 换路重建召唤物即天然重置
const PISTOL_PEN_PER_SHOT := 1.0
## 079 炮台: 生成在携带者【后方】这么远(规格原文 150 码) · 射程见 D4
const TOWER_BACK := 150.0
const TOWER_RANGE := 700.0
## 炮口在炮台立绘高度的哪一成 —— 顶端那颗发光的珊瑚珠(实量立绘 0.78 处)。
## ★不写死米数: 立绘一换尺寸, 写死的米数就错了(零系数素材纪律的同一条)。
const TOWER_MUZZLE_FRAC := 0.78
## 080 直升机: 机炮节拍 1.2 秒(规格原文) · 每命中一发 +4 龟能、上限 100(规格原文)
## 【080 打捞旋翼机】每发机炮的 ×ATK 物理系数(发数是三元数组, 就近声明在开火处)。
const HELI_SHOT_COEF := 0.35
## 【077 铜管手铳】携带者阵亡后, 小手枪受到的所有伤害降为这个固定值。
const PISTOL_DMG_CAP_DEAD := 5.0
const HELI_FIRE_IV := 1.2
const HELI_EN_PER_HIT := 4.0
const HELI_EN_MAX := 100.0
## 080 机炮一轮内的逐发间隔(秒) —— 一轮 10 发也要在 1.2 秒的节拍内打完
const HELI_SHOT_GAP := 0.06
## 080 地毯轰炸: 航线 800 长 × 120 宽(规格原文) · 每枚落点半径 180 码(规格原文)
const BOMB_LANE_LEN := 800.0
const BOMB_LANE_W := 120.0
## ★2026-08-08 用户削弱: 落点半径 **180 → 150 码**(直径 300)。
## ⚠ 预警贴花/爆炸火球的尺寸**全部由这一个数推出来**(零系数), 所以改这里就够了 ——
##   这正是"把系数从素材上消灭掉"的好处: 数值改动不会再漏掉某个演出。
const BOMB_R := 150.0
## 080 地毯轰炸的**枚数**(按星级)与航线速度。
## ★★2026-08-08 修正一处【我推翻了用户已过稿的设计】:
##   设计阶段我给的草案是「沿途投下 **8/10/14 枚**」, 用户回「地毯轰炸不错」过了稿,
##   他那一轮只改了航线(横穿全场 → 起点终点相距 800 码 × 120 宽), **没有一个字动过枚数**。
##   而我写方案书时把 8/10/14 **漏掉了**, 写成「边飞边不断投弹」;
##   实现时又照着自己写歪的那句话拍了个**固定 6 枚**(先定间距 160 码, 再反推枚数)。
##   ⇒ 后果: 三个星级的大招在画面上**完全一样**, 而我自己草案里写明的
##     「升星改的是覆盖密度」被删掉了。
##   ⇒ 现在: **枚数才是设计量, 间距是算出来的结果**(方向原来是反的)。
const BOMB_COUNT := [8, 10, 14]
const BOMB_RUN_SPD := 500.0
## 080 航线候选方位数(D9): 12 个方位 = 每 15°(带是双向对称的, 180° 就够)
const LANE_DIRS := 12
## 080 携带者阵亡后继续飞行的秒数(规格原文 10 秒)
const DOOM_SEC := 10.0
## 080 坠机时的爆炸半径(规格原文 500 码)与灼烧层数(规格原文 40 层)
const CRASH_R := 500.0
const CRASH_BURN := 40
## 080 直升机的巡航/坠落速度(码/秒)与飞行高度(演出用)
const HELI_SPD := 210.0
## 巡航交战距离(码)与绕圈的切向速度(码/秒)。★standoff 取 220 —— 明显是"隔着一段打",
## 又远小于机炮的有效射程(机炮不设射程上限, 靠 _heli_prey 选最近敌)。
## 切向 150 让它绕得看得出来但不至于转晕(绕一圈约 2π×220/150 ≈ 9.2 秒)。
const HELI_STANDOFF := 220.0
const HELI_ORBIT_SPD := 150.0
## 轰炸后的脱离: 沿原航向再飞这么远(码), 速度取进场速度的 0.8。
const HELI_EGRESS_LEN := 260.0
const HELI_EGRESS_SPD := 500.0
const CRASH_SPD := 900.0

const COL_PHYS := Color("#ffcf6b")
const COL_MAGIC := Color("#9bdcff")
const COL_HEAL := Color("#7dffb0")
const COL_BOMB := Color("#ff8a4d")


# ══════════════════════════════════════════════════════════════════
#  §钩子
# ══════════════════════════════════════════════════════════════════

## 携带者登场(每路开战、全队属性都写完之后跑一次): 三件召唤类在这里生成。
## ★逐星三元组就近写在 `match` 分支里(契约 §6)。
func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	match eid:
		"p2eq_077":
			# 小手枪: 30/60/100 生命 · 10/20/30 攻击。
			# ★hp【已是最终值, 不乘 HP_MULT】—— 用户原话"拥有 30/60/100 生命值",
			#   文案也照写(CLAUDE.md §3.1 那条"多乘一次"的旧账, 032 骷髅/058 炮台同口径)。
			_spawn_pistol(u, si, [30.0, 60.0, 100.0][si], [10.0, 20.0, 30.0][si])
		"p2eq_078":
			# 左右管【共享】一个计数与一个节拍 ⇒ 常驻字段两枚, tick_unit 每帧推进。
			u["_g078_si"] = si
			u["_g078_t"] = 0.0
			u["_g078_n"] = 0
		"p2eq_079":
			# 医疗炮台: 700/1200/2500 生命 · 15/20/30 攻击 · 50/70/100 双抗(同上, hp 不乘 HP_MULT)
			_spawn_tower(u, si, [700.0, 1200.0, 2500.0][si], [15.0, 20.0, 30.0][si], [50.0, 70.0, 100.0][si])
		"p2eq_080":
			# 坠机爆炸: 500 码内 200/300/500 物理 + 40 层灼烧(规格原文)。
			# ★在【登场】就写进直升机, 不等 on_death —— 万一携带者是被某条不走 on-death 钩的
			#   路径抹掉的(换路/团灭清场), 直升机照样能带着正确的爆炸参数坠下去, 而不是炸出 0。
			_spawn_heli(u, si, [200.0, 300.0, 500.0][si])


## 携带者普攻发出(本批四件都不挂普攻)
func on_basic(_u: Dictionary, _tgt, _eid: String, _si: int) -> void:
	pass


## 携带者命中结算后(本批四件都不挂 on-hit)
func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者受到伤害后(★两条伤害路径都会调, CLAUDE.md §3.3)。本批四件都不挂。
func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者受到法术伤害后(本批不用)
func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者阵亡。
##   077: 小手枪受到的伤害封顶从 2 放宽到 5(规格原文) —— 直接改共用收口读的那个字段。
##   080: 开始 10 秒倒计时(爆炸参数在登场时就写好了, 见 on_spawn)。
func on_death(u: Dictionary, eid: String, _si: int) -> void:
	match eid:
		"p2eq_077":
			for e in _pistols:
				if is_same(e["owner"], u):
					(e["u"] as Dictionary)["_dmg_cap_val"] = PISTOL_DMG_CAP_DEAD
					vfx.pistol_uncovered(Vector2(e["u"]["pos"]))
		"p2eq_080":
			for h in _helis:
				if not is_same(h["owner"], u):
					continue
				# ★正在跑轰炸航线时【不打断】—— 航线跑完自己会回到 doom。
				#   倒计时不看 state, 只要携带者死了就一直走(见 _tick_helis), 所以不会被轰炸拖长。
				if str(h.get("state", "")) == "patrol":
					h["state"] = "doom"
				h["doom_t"] = 0.0


## 法器法力条集满(本批不用)
func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 每帧【全局】推进: 三种常驻物各自的节拍 + 演出。
## ★由 `EquipSystem.tick_global` 调, 而 `tick_global` 由主循环【无条件】每帧调一次 ——
##   不是挂在"某只龟身上有装备"那个闸里面。这三种常驻物在携带者阵亡后都要继续动
##   (小手枪要接着打、炮台要接着奶、直升机还有 10 秒才坠), 挂在那个闸里就会整个停摆而且不报错。
func tick(delta: float) -> void:
	_tick_pistols(delta)
	_tick_towers(delta)
	_tick_helis(delta)
	vfx.tick(delta)


## 每帧【逐单位】推进: 只有 078 用(左右管的 2 秒交替要秒级精度)。
## ★守卫是常驻字段 `_g078_si`(on_spawn 写), 不遍历 equips —— 这是全 95 件装备的公共热路径。
func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.has("_g078_si"):
		return
	if not u.get("alive", false):
		return
	# ★自管累加器, 不读 battle._t(它跨路累加永不重置, CLAUDE.md §3.4)
	u["_g078_t"] = float(u.get("_g078_t", 0.0)) + delta
	if float(u["_g078_t"]) < EEL_IV:
		return
	u["_g078_t"] = float(u["_g078_t"]) - EEL_IV
	_eel_fire(u, int(u.get("_g078_si", 0)))


## ★换路撤场: 三种常驻物 + 演出全部拔掉。漏了就把上一路的东西带进下一路。
## ★小手枪与炮台是 `battle._units` 里的单位, 换路时整张单位表会被重建 ⇒ 这里只要
##   丢掉自己的登记表(留着就是悬空引用, 下一路会对着上一路的字典结算)。直升机不是单位,
##   它的节点必须自己拔。
func clear_all() -> void:
	_pistols.clear()
	_towers.clear()
	for h in _helis:
		vfx.heli_free(h)
	_helis.clear()
	vfx.clear()


# ══════════════════════════════════════════════════════════════════
#  §077 铜管手铳 —— 迷你小手枪召唤物
# ══════════════════════════════════════════════════════════════════

func _spawn_pistol(owner: Dictionary, si: int, hp: float, atk: float) -> void:
	var p = battle._spawn._spawn_summon(owner, "pistol", hp, atk,
		{"label": "小手枪", "spr_id": "pistol", "col_size": 22.0, "hp_w": 20.0,
		 "atk_interval": PISTOL_IV, "atk_range": PISTOL_RANGE, "melee": false})
	if p == null:
		return
	p["crit"] = PISTOL_CRIT
	p["crit_dmg"] = 1.5
	p["armor_pen"] = 0.0
	p["base_def"] = 0.0; p["base_mr"] = 0.0; p["def"] = 0.0; p["mr"] = 0.0
	# ★普攻由本系统自己驱动(见 D2/金弹段: 要每次攻击 +1 破甲、要走 _queue_shots 出金弹),
	#   sim 的 `_basic_attack` 没有给召唤物的钩子 ⇒ 关掉它自己的普攻, 移动/索敌照旧。
	p["no_basic"] = true
	# ★伤害封顶: 走共用收口 `_mitigate_incoming` 末尾的带值闸 —— 两条伤害路径、含真伤全覆盖。
	#   携带者阵亡后 `on_death` 把它改成 5.0(规格原文)。
	p["_dmg_cap_val"] = 2.0
	## 受到的所有治疗封顶 1 点(用户 2026-08-12 削弱)。走 battle_damage._heal 的共用收口,
	## 所以 079 医疗炮台 / 法器灵泉 / 食物盛宴 / 090 的治疗浪潮 一律只回 1。
	p["_heal_cap_val"] = 1.0
	p["_g077"] = true
	# ★★2026-08-06 用户看图后拍板: 小手枪原来生成在携带者【随机偏移】处, 经常直接压在龟身上
	#   ⇒ 读不出"这是一个独立的、会被打死的单位"(它是"需要保护的资产", 那是这件的设计核心)。
	#   改成与 079 炮台同一套定位: **携带者斜后方固定位**, side-aware + 战场边界/障碍钳制。
	#   ★复用 `tower_pos` 而不是另写一份 —— 它已经处理好了"左右阵营的后方是反的"
	#   与"落点非法要推出去"两件事(memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后)。
	p["pos"] = tower_pos(Vector2(owner["pos"]), str(owner.get("side", "left")),
		battle.ARENA, battle._obstacles if battle.get("_obstacles") != null else [],
		22.0, PISTOL_BACK, 30.0) + Vector2(0.0, PISTOL_SIDE_Y)
	if p.has("sprite") and is_instance_valid(p["sprite"]):
		p["sprite"].position = battle._world_pos(p["pos"], battle.GROUND_LIFT)
	_pistols.append({"u": p, "owner": owner, "si": si, "acc": 0.0})
	vfx.pistol_deploy(Vector2(p["pos"]))


func _tick_pistols(delta: float) -> void:
	for i in range(_pistols.size() - 1, -1, -1):
		var e: Dictionary = _pistols[i]
		var p: Dictionary = e["u"]
		if not (p is Dictionary) or not p.get("alive", false):
			_pistols.remove_at(i)
			continue
		_pistol_kick_tick(p, delta)
		e["acc"] = float(e.get("acc", 0.0)) + delta
		while float(e["acc"]) >= PISTOL_IV:
			e["acc"] = float(e["acc"]) - PISTOL_IV
			_pistol_attack(e)


## 后坐力每帧推进: 开火瞬间把立绘弹开 `_pistol_kick_d`, 再**临界阻尼**回位。
## ★临界阻尼 = 永不过冲(x̂(τ) = (1+τ)e^(−τ)) —— 枪不该"弹回来又晃出去"。
## ★只动【立绘节点的偏移】, 不动单位的 `pos` —— pos 是结算用的(索敌/射程/碰撞),
##   演出碰它就会变成"后坐把射程改了"这种只在特定时刻出现的诡异行为。
func _pistol_kick_tick(p: Dictionary, delta: float) -> void:
	var T: float = float(p.get("_pistol_kick_T", 0.0))
	if T <= 0.0:
		return
	var spr = p.get("sprite", null)
	if not is_instance_valid(spr):
		p["_pistol_kick_T"] = 0.0
		return
	var t: float = float(p.get("_pistol_kick_t", 0.0)) + delta
	p["_pistol_kick_t"] = t
	var base: Vector3 = battle._world_pos(Vector2(p["pos"]), battle.GROUND_LIFT)
	if t >= T:
		p["_pistol_kick_T"] = 0.0
		spr.position = base
		return
	var tau: float = (t / T) * 4.0                    # 4τ 内衰减到 ~9%
	var amp: float = (1.0 + tau) * exp(-tau)          # 临界阻尼包络
	var d: Vector2 = p.get("_pistol_kick_d", Vector2.ZERO)
	spr.position = base + Vector3(d.x * amp * float(battle.WS), 0.0, d.y * amp * float(battle.WS))


## 一次攻击 = 一发子弹(1 ATK 物理, 自带 50% 暴击) + 自己 +1 破甲。
## ★金弹走 `_queue_shots`: src 是小手枪自己 ⇒ 它自己一份计数(规格"每把枪各自计数"),
##   金弹复用同一个 `fn` ⇒ 效果完整继承; 金弹那一发**不再** +1 破甲(D2)。
func _pistol_attack(e: Dictionary) -> void:
	var p: Dictionary = e["u"]
	var tgt = battle._targeting._nearest_enemy(p)
	if tgt == null or not tgt.get("alive", false):
		return
	if (Vector2(tgt["pos"]) - Vector2(p["pos"])).length() > PISTOL_RANGE:
		return
	# ★演出: 枪口火焰 + 后坐力。**朝向取"打谁"** —— 立绘是朝右的(见 _resolve_summon_sprite 的
	#   pistol 分支), 所以火焰锚点也按同一个朝向算, 两者天然一致。
	#   后坐时长传实际攻击间隔 ⇒ 攻速被枪羁绊拉到 4/秒 时也占满一个周期, 不会播不完被打断。
	var _aim: Vector2 = (Vector2(tgt["pos"]) - Vector2(p["pos"])).normalized()
	vfx.pistol_fire(p, _aim, PISTOL_IV)
	# ★★2026-08-07: **让枪转身面向目标**。用户问「子弹方向有考虑吗」时查出来的:
	#   渲染层的 flip_h = face_right != 立绘朝向, 而小手枪是 no_basic 召唤物、
	#   **不走普攻状态机 ⇒ 从来没有人给它写过 face_right** ⇒ 它永远按队伍朝右。
	#   敌人绕到身后时, 枪不转身、枪口仍在右边, 弹却往左飞 = **从枪背后飞出去**。
	#   写了这一行之后, flip_h 会跟着变, 而枪口锚点本来就读 flip_h ⇒ 枪口自动跟到另一侧。
	p["face_right"] = Vector2(tgt["pos"]).x >= Vector2(p["pos"]).x
	p["armor_pen"] = float(p.get("armor_pen", 0.0)) + PISTOL_PEN_PER_SHOT
	# ★出膛点回调: 金弹也从**枪管尖**出去, 不再从携带者身上。`p` 是小手枪自己。
	battle._queue_shots(1, GOLD_GAP, func() -> void: _pistol_bullet(p), p, "p2eq_077",
		func() -> Vector2: return Vector2(p["pos"]) + Vector2(float(p.get("_muzzle_px", PISTOL_MUZZLE_FALLBACK)), 0.0))


## 一发子弹落地: 1 ATK 物理。★from_equip=true(焊死口径②)。
func _pistol_bullet(p: Dictionary) -> void:
	if not p.get("alive", false):
		return
	var tgt = battle._targeting._nearest_enemy(p)
	if tgt == null or not tgt.get("alive", false):
		return
	if (Vector2(tgt["pos"]) - Vector2(p["pos"])).length() > PISTOL_RANGE:
		return
	var gold: float = float(p.get("_golden_pct", 0.0))
	# ★弹道从**枪管尖**出发, 不是单位中心 —— 与枪口火焰同一个锚点(pistol_fire 里写的)。
	#   `_muzzle_px` 是"半枪长(码)", 由演出层按精灵实际尺寸算出来回填, 这里不重算。
	# ★★只偏**水平**: 枪立绘永远朝右不转向 ⇒ 枪口在 +x。
	#   第一版乘的是 aim(指向目标 = 右下方) ⇒ 弹从枪的右下角冒出来而不是枪口(用户实拍抓到)。
	var _muz: Vector2 = Vector2(p["pos"]) + Vector2(float(p.get("_muzzle_px", PISTOL_MUZZLE_FALLBACK)), 0.0)
	# ★⑭ 同上: 结算等弹飞到(内层空 gun_id, 不重复计金弹)
	var _fly2: float = vfx.tracer(_muz, Vector2(tgt["pos"]), COL_PHYS, gold,
		float(p.get("_muzzle_h", 0.6)), GunEqVfx.body_mid_h(tgt), tgt)
	# ★★把 `_golden_pct` **带进**延后的结算 —— 这是延后伤害引入的真 bug:
	#   金弹的真伤在 `battle_damage` 里是从 `src["_golden_pct"]` 读的, 而那个标记
	#   在 `_queue_shots` 的闭包里**用完就清零**。伤害一旦推迟到弹落地, 读到的就是 0
	#   ⇒ **金弹白打**(实测 6 发全按普通弹算, 240 变 180)。
	#   ⇒ 结算前把当时的 gold 标回去, 算完立刻还原。
	battle._queue_shots(1, 0.0, func() -> void:
		if not tgt.get("alive", false):
			return
		var _sv: float = float(p.get("_golden_pct", 0.0))
		p["_golden_pct"] = gold
		battle._damage._apply_damage_from(p, tgt, battle._atk_dmg(p, 1.0, tgt), COL_PHYS, 0.0, false, true)
		p["_golden_pct"] = _sv
	, p, "", Callable(), _fly2)


# ══════════════════════════════════════════════════════════════════
#  §078 电鳗双管铳 —— 左右管共享计数, 每 2 秒交替
# ══════════════════════════════════════════════════════════════════

## 轮到哪一管: 偶数发左管(霰弹), 奇数发右管(电击弹)。
## ★"共享计数"就是这一个 `n`: 两管加起来每 2 秒一发, 所以每管各 4 秒一次(规格原文的节拍)。
func _eel_fire(u: Dictionary, si: int) -> void:
	var tgt = battle._targeting._nearest_enemy(u)
	if tgt == null or not tgt.get("alive", false):
		return
	var n: int = int(u.get("_g078_n", 0))
	u["_g078_n"] = n + 1
	var left: bool = (n % 2) == 0
	var aim: Vector2 = Vector2(tgt["pos"]) - Vector2(u["pos"])
	if aim.length() < 1.0:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	# ★金弹从【轮到的那一管】打出并完整继承该管效果 —— 因为金弹复用的就是这里这个 `fn`。
	var fn: Callable = (func() -> void: _eel_left(u, si, aim)) if left else (func() -> void: _eel_right(u, si))
	# ★★2026-08-08: 补上 muzzle 回调。原来没传 ⇒ 金弹的菱珠串从**携带者中心**出发,
	#   而本体那一发是从**轮到的那一管**出的 —— 同一发的两半从两个地方出来。
	#   080 已经修过同款; 这里用**同一个** `GunEqVfx.barrel_muzzle`, 不是再手抄一份几何
	#   (手抄的副本必然落后: BARREL_OFF 一改, 抄的那份就错了)。
	var apex: Vector2 = Vector2(u["pos"])
	battle._queue_shots(1, GOLD_GAP, fn, u, "p2eq_078",
		func() -> Vector2: return GunEqVfx.barrel_muzzle(apex, aim, left))


## 左管: 400 码 60 度锥形霰弹, 15+0.3ATK / 25+0.6ATK / 40+1ATK 物理。
## ★金弹时锥内**每人各吃一次**真伤 —— 因为真伤是伤害管线按段补的, 锥内每人各走一段。
##
## ★★2026-08-08 三处重做:
##   ①【原点合一】判定原来以**携带者中心**为锥顶算 400 码 / 60 度, 演出却从**管口**画出去
##     (垂直偏 22 码 + 前 12 码)。锥边缘于是会出现"画到了不掉血 / 没画到反而掉血"。
##     ⇒ 判定与演出**同用 `barrel_muzzle` 这一个点**, 不各算各的。
##   ②【伤害等弹到达】弹丸现在真的要飞(见 cone_blast), 伤害就不能还在开火那一帧掉完 ——
##     这是 080 立下的规矩(炸弹落地 = 伤害 = 爆炸)。每个目标按**自己的距离**算飞行时间。
##   ③【命中反馈】原来锥内 n 个人挨了打, 身上什么都不出现。⇒ 各打一次 hit_spark。
func _eel_left(u: Dictionary, si: int, aim: Vector2) -> void:
	if not u.get("alive", false):
		return
	var flat: float = [15.0, 25.0, 40.0][si]
	var scale: float = [0.3, 0.6, 1.0][si]
	var half_cos: float = cos(deg_to_rad(EEL_CONE_DEG * 0.5))     # 60 度锥 ⇒ 半角 30 度
	var apex: Vector2 = GunEqVfx.barrel_muzzle(Vector2(u["pos"]), aim, true)
	var gpct: float = float(u.get("_golden_pct", 0.0))
	var muz_h: float = GunEqVfx.body_mid_h(u)
	var n := 0
	var hit_h: float = -1.0
	var hit_d: float = INF
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		var rel: Vector2 = Vector2(o["pos"]) - apex
		var d: float = rel.length()
		if d > EEL_CONE_RANGE:
			continue
		if d > 1.0 and rel.normalized().dot(aim) < half_cos:
			continue
		if d < hit_d:
			hit_d = d
			hit_h = GunEqVfx.body_mid_h(o)
		var fly: float = clampf(d / GunEqVfx.PELLET_SPD, 0.0, 0.6)
		# ★金弹标记在 `_queue_shots` 的闭包里用完就清零(080 踩过) ⇒ 延后的这一段必须
		#   自己把它捎上, 否则弹一延后, 真伤就读到 0、金弹白打。
		var tgt: Dictionary = o
		battle._queue_shots(1, 0.0, func() -> void:
			if not tgt.get("alive", false):
				return
			var keep: float = float(u.get("_golden_pct", 0.0))
			u["_golden_pct"] = gpct
			var dmg: int = battle._resolve_dmg(u, flat + scale * float(u["atk"]), tgt, false)
			battle._damage._apply_damage_from(u, tgt, dmg, COL_PHYS, 0.0, false, true)
			u["_golden_pct"] = keep
			vfx.hit_spark(Vector2(tgt["pos"]), GunEqVfx.body_mid_h(tgt)), u, "", Callable(), fly)
		n += 1
	# 弹丸落到**最近那个命中者的身体中段**(由它的立绘算, 不写死);
	# 一个都没打中 ⇒ 保持出膛高度平着飞完 400 码(没有落点可言)。
	var h_to: float = muz_h if hit_h < 0.0 else hit_h
	vfx.cone_blast(Vector2(u["pos"]), aim, EEL_CONE_RANGE, EEL_CONE_DEG * 0.5, COL_PHYS, gpct, 14, muz_h, h_to)


## 右管: 首目标 0.5ATK 物理 + 50/100/180 魔法; 魔法段按最近顺序连锁到**所有还没被这一发电过**
## 的敌人, 每跳后续伤害降低 20/15/10%。
## ★金弹时首目标与每一跳都吃真伤(用户明确拍板) —— 同样是伤害管线按段补, 天然成立。
func _eel_right(u: Dictionary, si: int) -> void:
	if not u.get("alive", false):
		return
	var first = battle._targeting._nearest_enemy(u)
	if first == null or not first.get("alive", false):
		return
	# ★三元数组就近声明(契约 §6): 魔法基数 / 每跳衰减 / 金弹真伤比例, 都在 "p2eq_078" 锚点窗口内。
	var mag: float = [50.0, 100.0, 180.0][si]
	var decay: float = [0.20, 0.15, 0.10][si]
	var gold_pct: float = [0.60, 0.80, 1.00][clampi(int(battle._synergy.tier_for(u, "枪")) - 1, 0, 2)]
	battle._damage._apply_damage_from(u, first, battle._atk_dmg(u, EEL_BOLT_ATK, first), COL_PHYS, 0.0, false, true)
	# ★纯演出(2026-08-07): 右管出膛的那一束电。原来右管只画"目标之间的连锁", 完全没有
	#   "从枪口打出去"这一段 ⇒ 读不出是左管还是右管在响。
	#   ⚠ 2026-08-08 更正: 上一版这里写着「用户:『左右两管的相位读不出来』」—— **用户从没说过这句**,
	#     全篇聊天记录里 "相位"/"左右两管"/"读不出" 出现 0 次。那是我自己的判断被我写成了他的原话。
	#     和 080 的"6 枚炸弹"是同一种病: 把自己的决定记进"事实源"。判断本身仍然成立, 但署名归我。
	#   一个数都没动: 伤害在上一行就结算完了, 这里只画。
	var gold_now: float = (gold_pct if float(u.get("_golden_pct", 0.0)) > 0.0 else 0.0)
	vfx.eel_bolt(Vector2(u["pos"]), Vector2(first["pos"]), gold_now,
		GunEqVfx.body_mid_h(u), GunEqVfx.body_mid_h(first))
	# ★★2026-08-08【时序合一】原来整条链的**全部跳跃与全部伤害都在同一帧**结算完,
	#   实拍(_vfxlab_p2eq_078_3.png)里就是一根穿了 4 只龟的紫管子 —— 规格原文的
	#   「电流按最近顺序**不断**往没被电过的敌人**跳跃**」一点都读不出来。
	#   ⇒ 改成一跳一跳走: 电弧画到哪一跳, 那一跳的伤害才掉。这正是 080 定下的规矩
	#     (炸弹落地 = 伤害 = 爆炸)。排程走**已有的** `_queue_shots`(按 sim 帧推进),
	#     不用 tween —— tween 在无头 CI 下推进不稳(§3.5, 海盗钩连红三次的那一课)。
	_eel_hop(u, {"chain": [first], "cur": first, "amt": mag, "decay": decay,
		"gold": float(u.get("_golden_pct", 0.0)), "vg": gold_now}, 0)


## 电链每 0.09 秒跳一格。★不是随手取的: 这个间隔要**看得出先后**又不能拖到
## 下一次开火(每 2 秒一发)之后 —— 最多 8 个敌人 ⇒ 满链 0.72 秒, 留足余量。
## 078 电鳗双管铳: 左右管共享计数, 每 EEL_IV 秒交替射一管。
## 左管 = EEL_CONE_RANGE 码 × EEL_CONE_DEG 度锥形霰弹; 右管 = 电击弹, 首目标物理 + 魔法连锁。
const EEL_IV := 2.0            # 交替节拍(秒)
const EEL_CONE_RANGE := 400.0  # 左管锥形射程(码)
const EEL_CONE_DEG := 60.0     # 左管锥角(全角; 代码里取半角 = ÷2)
const EEL_BOLT_ATK := 0.5      # 右管电击弹: 首目标 ×ATK 物理
const EEL_HOP_GAP := 0.09
const EEL_HOP_MAX := 64

## 第 i 跳: 先把伤害**落在当前这一格**, 再找下一格、画过去、排下一跳。
## ★递归排程用具名函数而不是自引用的 lambda —— GDScript 里 lambda 引用自己是脏活。
func _eel_hop(u: Dictionary, st: Dictionary, i: int) -> void:
	if i >= EEL_HOP_MAX:
		return
	var cur = st.get("cur", null)
	if not (cur is Dictionary):
		return
	if (cur as Dictionary).get("alive", false):
		# 金弹标记捎带(080 的账): 延后的段读不到开火那一刻的 `_golden_pct`
		var keep: float = float(u.get("_golden_pct", 0.0))
		u["_golden_pct"] = float(st.get("gold", 0.0))
		var mdmg: int = battle._resolve_dmg(u, float(st["amt"]), cur, true)
		battle._damage._apply_damage_from(u, cur, mdmg, COL_MAGIC, 0.0, false, true)
		u["_golden_pct"] = keep
		# 每一跳的落点都要有"这一下打中了"—— 用电色, 和霰弹的暖白分得开
		vfx.hit_spark(Vector2((cur as Dictionary)["pos"]), GunEqVfx.body_mid_h(cur), GunEqVfx.COL_ARC_CORE)
	var nxt = _eel_next_hop(u, cur, st["chain"])
	if nxt == null:
		return
	vfx.chain_arc(Vector2((cur as Dictionary)["pos"]), Vector2((nxt as Dictionary)["pos"]), COL_MAGIC,
		float(st.get("vg", 0.0)), GunEqVfx.body_mid_h(cur), GunEqVfx.body_mid_h(nxt))
	st["chain"].append(nxt)
	st["cur"] = nxt
	st["amt"] = float(st["amt"]) * (1.0 - float(st["decay"]))
	battle._queue_shots(1, 0.0, func() -> void: _eel_hop(u, st, i + 1), u, "", Callable(), EEL_HOP_GAP)


## 下一跳 = 离当前落点**最近**且**还没被这一发电过**的敌人。
## ★"电过没有"用 `battle._arr_has_unit`(引用判重) —— Array.has()/in 对单位字典是深比较, 会卡死(§3.2)。
func _eel_next_hop(u: Dictionary, from_u: Dictionary, done: Array):
	var best = null
	var bd := INF
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or battle._arr_has_unit(done, o):
			continue
		var d: float = (Vector2(o["pos"]) - Vector2(from_u["pos"])).length_squared()
		if d < bd:
			bd = d
			best = o
	return best


# ══════════════════════════════════════════════════════════════════
#  §079 珊瑚急救塔 —— 后方 150 码的医疗炮台
# ══════════════════════════════════════════════════════════════════

## "携带者后方 150 码" 的落点。**纯函数**, 门禁直接验坐标而不是等召唤物出现(CLAUDE.md §3.5)。
## ★双边: left 阵营朝右打 ⇒ 后方是 −X; right 阵营朝左打 ⇒ 后方是 +X。
## ★边界与障碍: 先钳进 ARENA(留 pad 免得贴边), 再把落进障碍椭圆里的点沿径向推到椭圆边上 ——
##   与 `dual_lane_flow._dl_clamp_place` **同一条椭圆推出规则**(含 OBSTACLE_MARGIN)。
##   没有直接调它: 那个函数把 x 硬钳在"我方半场且不越中线"(写死左半场), 对 right 阵营是错的。
static func tower_pos(carrier: Vector2, side: String, arena: Rect2, obstacles: Array,
		margin: float, back: float = TOWER_BACK, pad: float = 40.0) -> Vector2:
	var p: Vector2 = carrier + Vector2(-back if side == "left" else back, 0.0)
	p.x = clampf(p.x, arena.position.x + pad, arena.end.x - pad)
	p.y = clampf(p.y, arena.position.y + pad, arena.end.y - pad)
	for ob in obstacles:
		if not (ob is Dictionary):
			continue
		var c: Vector2 = ob["c"]
		var rx: float = float(ob["rx"]) + margin
		var ry: float = float(ob["ry"]) + margin
		var d: Vector2 = p - c
		var t: float = Vector2(d.x / maxf(1.0, rx), d.y / maxf(1.0, ry)).length()
		if t < 1.0:
			p = c + (d / t if t > 0.01 else Vector2(rx, 0.0))
	p.x = clampf(p.x, arena.position.x + pad, arena.end.x - pad)
	p.y = clampf(p.y, arena.position.y + pad, arena.end.y - pad)
	return p


func _spawn_tower(owner: Dictionary, si: int, hp: float, atk: float, res: float) -> void:
	var t = battle._spawn._spawn_summon(owner, "medtower", hp, atk,
		{"label": "急救塔", "spr_id": "coraltower", "col_size": 40.0, "hp_w": 30.0,
		 "atk_interval": 1.0, "atk_range": TOWER_RANGE, "melee": false, "no_move": true})
	if t == null:
		return
	t["pos"] = tower_pos(Vector2(owner["pos"]), str(owner.get("side", "left")),
		battle.ARENA, battle._obstacles, battle.OBSTACLE_MARGIN)
	t["move_spd"] = 0.0
	t["no_move"] = true
	t["no_basic"] = true          # 射速由本系统按携带者攻速实时驱动, 不走 sim 的普攻冷却
	t["crit"] = 0.0
	t["base_def"] = res; t["base_mr"] = res
	battle._recalc_stats(t)
	t["_g079"] = true
	_towers.append({"u": t, "owner": owner, "si": si, "acc": 0.0})
	vfx.tower_deploy(Vector2(t["pos"]))


## 携带者【当前】的每秒攻击次数。★是实时的, 不是生成时快照(规格原文强调)。
## 口径与 sim 里排下一次普攻冷却的那一行一致(RealtimeBattle3DScene 状态机 "windup" 分支):
##   冷却 = atk_interval / (临时攻速 × 永久攻速 × 沉锚 × 058炮台加成)
## ⇒ 每秒攻击次数 = 那个乘子 / atk_interval。
## ★没有把 `hunter` 的"残血追猎 ×1.5"抄进来: 那一条要**当前攻击目标**才判得出来,
##   而炮台跟随的是"携带者的攻速属性", 不是"携带者这一下打的是谁"。
func carrier_aps(owner: Dictionary) -> float:
	var iv: float = maxf(0.05, float(owner.get("atk_interval", 1.0)))
	var m: float = float(owner.get("aspd_perm", 1.0)) * battle._anchor_aspd(owner) * float(owner.get("_turret_aspd_mult", 1.0))
	if battle._t < float(owner.get("haste_until", 0.0)):
		m *= maxf(1.0, float(owner.get("haste_mult", 1.0)))
	if battle._t < float(owner.get("spd_dbf_until", 0.0)):
		m *= float(owner.get("spd_aspd_mult", 1.0))
	return maxf(0.1, m) / iv


func _tick_towers(delta: float) -> void:
	for i in range(_towers.size() - 1, -1, -1):
		var e: Dictionary = _towers[i]
		var t: Dictionary = e["u"]
		if not (t is Dictionary) or not t.get("alive", false):
			_towers.remove_at(i)
			continue
		var aps: float = carrier_aps(e["owner"])
		t["atk_interval"] = 1.0 / maxf(0.01, aps)     # 血条/信息面板读它 ⇒ 显示也跟着实时变
		e["acc"] = float(e.get("acc", 0.0)) + delta
		var iv: float = 1.0 / maxf(0.01, aps)
		var guard := 0
		while float(e["acc"]) >= iv and guard < 32:
			guard += 1
			e["acc"] = float(e["acc"]) - iv
			_tower_shot(e)


## 炮台开一发: 走 `_queue_shots` ⇒ **炮台自己维持一份金弹计数**(规格原文)。
func _tower_shot(e: Dictionary) -> void:
	var t: Dictionary = e["u"]
	var si: int = int(e["si"])
	battle._queue_shots(1, GOLD_GAP, func() -> void: _tower_bullet(t, si), t, "p2eq_079")


## 一发炮弹: 1ATK 物理 + 目标最大生命 1/1.5/2% 魔法, 并为**生命百分比最低的友军**回 10/15/20。
## ★★本件专属: **金弹时回血量翻倍**(全表唯一的例外, 用户 2026-08-06 拍板)。
##   "这一发是不是金弹"读 `t["_golden_pct"]` —— 那是 `_queue_shots` 在调 fn 前后标上/清掉的。
func _tower_bullet(t: Dictionary, si: int) -> void:
	if not t.get("alive", false):
		return
	# ★三元数组就近声明(契约 §6): 都在上面 `_queue_shots(..., "p2eq_079")` 的锚点窗口内。
	var hp_pct: float = [0.01, 0.015, 0.02][si]
	var heal: float = [10.0, 15.0, 20.0][si]
	var gold_pct: float = [0.60, 0.80, 1.00][clampi(int(battle._synergy.tier_for(t, "枪")) - 1, 0, 2)]
	var per_gold: int = [4, 3, 2][clampi(int(battle._synergy.tier_for(t, "枪")) - 1, 0, 2)]
	var golden: bool = float(t.get("_golden_pct", 0.0)) > 0.0
	var tgt = battle._targeting._nearest_enemy(t)
	if tgt != null and tgt.get("alive", false) and (Vector2(tgt["pos"]) - Vector2(t["pos"])).length() <= TOWER_RANGE:
		# ★★2026-08-08 实拍(_vfxlab_p2eq_079_2.png): 炮弹**贴着地面滑行**, 从敌人**脚下**穿过去。
		#   根因是这一行 `tracer(a, b, col, gold)` 后面三个参数一个都没传 ⇒ 全吃默认值:
		#     · h_m 默认 0.05 米(手枪的枪口高度) ⇒ 炮台从自己脚底 5 厘米处开火
		#     · h_to 默认 −1(不下落) ⇒ 一路平飞, 永远碰不到身体
		#     · tgt 默认 null ⇒ 目标一动就打到它刚才站的地方
		#   077/080 上被用户逐条盯出来改过的三件事, 在这件上一件都没做。
		#   ⇒ 炮口取炮台立绘顶端那颗珊瑚珠(0.78), 落点取目标身体中段, 并把目标本体传进去。
		var muz_h: float = GunEqVfx.sprite_h(t, TOWER_MUZZLE_FRAC)
		var fly: float = vfx.tracer(Vector2(t["pos"]), Vector2(tgt["pos"]), COL_PHYS,
			gold_pct if golden else 0.0, muz_h, GunEqVfx.body_mid_h(tgt), tgt)
		vfx.tower_muzzle(Vector2(t["pos"]), muz_h, COL_PHYS)
		# ★伤害等炮弹到达(080 立的规矩)。金弹标记在闭包返回时被清掉 ⇒ 延后段自己捎上。
		var gp: float = float(t.get("_golden_pct", 0.0))
		var vt: Dictionary = tgt
		battle._queue_shots(1, 0.0, func() -> void:
			if not vt.get("alive", false):
				return
			var keep: float = float(t.get("_golden_pct", 0.0))
			t["_golden_pct"] = gp
			battle._damage._apply_damage_from(t, vt, battle._atk_dmg(t, 1.0, vt), COL_PHYS, 0.0, false, true)
			var mdm: int = battle._resolve_dmg(t, float(vt["maxHp"]) * hp_pct, vt, true)
			if vt.get("alive", false):
				battle._damage._apply_damage_from(t, vt, mdm, COL_MAGIC, 0.0, false, true)
			t["_golden_pct"] = keep, t, "", Callable(), fly)
	var low = lowest_ally(t)
	if low is Dictionary:
		battle._damage._heal(low, heal * (2.0 if golden else 1.0))
		# 束的两端各按自己的立绘取身体中段 —— 旧版两端都写死 1.2 米
		vfx.heal_beam(Vector2(t["pos"]), Vector2(low["pos"]), COL_HEAL, golden,
			GunEqVfx.sprite_h(t, TOWER_MUZZLE_FRAC), GunEqVfx.body_mid_h(low))
	vfx.tower_charge(t, int((t.get("_gun_shot_ct", {}) as Dictionary).get("p2eq_079", 0)), per_gold)


## 生命【百分比】最低的友军。★契约 §4 全表通用口径: **一律排除龟蛋与训龟大师**。
## ★炮台/小手枪这类召唤物**算友军**(D5)。
func lowest_ally(t: Dictionary):
	var best = null
	var bv := INF
	for o in battle._targeting._allies_of(t, true):
		if not o.get("alive", false):
			continue
		if o.get("_isEgg", false) or o.get("is_trainer", false):
			continue
		var r: float = float(o.get("hp", 0.0)) / maxf(1.0, float(o.get("maxHp", 1.0)))
		if r < bv:
			bv = r
			best = o
	return best


# ══════════════════════════════════════════════════════════════════
#  §080 打捞旋翼机 —— 不可选中、完全免疫的空中平台
# ══════════════════════════════════════════════════════════════════
#  ★为什么不做成 `battle._units` 里的单位: 规格要"无法选中 + 完全免疫"。做成真单位再打
#    两个 flag, 要额外应付团灭判定(留一架活的会卡住换路窗口)、分离/寻路/血条/伤害统计/
#    召唤物特殊 tick, 而且"免疫"要靠一个可能被别处忽略的 flag。做成纯逻辑 + 演出体则
#    这两条是**结构性成立**的 —— 与 092 剧毒飞行物同一条理由(eq_venom_drone.gd 判断②)。

func _spawn_heli(owner: Dictionary, si: int, crash_phys: float) -> void:
	var back: float = -160.0 if str(owner.get("side", "left")) == "left" else 160.0
	var h: Dictionary = {
		"owner": owner, "si": si,
		"pos": Vector2(owner["pos"]) + Vector2(back, -90.0),
		"energy": 0.0, "fire_t": 0.0, "state": "patrol",
		"doom_t": 0.0, "run_t": 0.0, "bomb_t": 0.0, "bombs": 0,
		"lane_a": Vector2.ZERO, "lane_b": Vector2.ZERO,
		"crash_to": Vector2.ZERO, "crash_phys": crash_phys, "crash_burn": CRASH_BURN,
		"node": null, "rotor": 0.0,
	}
	_helis.append(h)
	vfx.heli_spawn(h)


func _tick_helis(delta: float) -> void:
	for i in range(_helis.size() - 1, -1, -1):
		var h: Dictionary = _helis[i]
		match str(h.get("state", "patrol")):
			"patrol", "doom":
				_heli_patrol(h, delta)
			"approach":
				_heli_approach(h, delta)
			"egress":
				_heli_egress(h, delta)
			"bomb":
				_heli_bomb_run(h, delta)
			"crash":
				_heli_crash_fly(h, delta)
		# ★"携带者死后继续飞 10 秒"的倒计时【不看 state】: 只要携带者死了就一直走。
		#   挂在 state=="doom" 上会让"死时正在跑轰炸航线"把这 10 秒白白拖长一轮 ——
		#   规格给的是一个**对手能读的窗口**, 窗口长度不该被我方的技能节拍改写。
		if _heli_doomed(h) and not (str(h.get("state", "")) in ["crash", "dead"]):
			h["doom_t"] = float(h.get("doom_t", 0.0)) + delta
			if float(h["doom_t"]) >= DOOM_SEC:
				_heli_begin_crash(h)
		if str(h.get("state", "")) == "dead":
			vfx.heli_free(h)
			_helis.remove_at(i)
			continue
		vfx.heli_update(h, delta)


## 巡航 + 机炮扫射 + 龟能满则转入地毯轰炸。
func _heli_patrol(h: Dictionary, delta: float) -> void:
	var owner: Dictionary = h["owner"]
	var aim = _heli_prey(h)
	if aim is Dictionary:
		_heli_orbit_step(h, Vector2(aim["pos"]), delta)
	h["fire_t"] = float(h.get("fire_t", 0.0)) + delta
	if float(h["fire_t"]) < HELI_FIRE_IV:
		return
	h["fire_t"] = float(h["fire_t"]) - HELI_FIRE_IV
	var si: int = int(h["si"])
	# ★三元数组就近声明(契约 §6): 发数 / 每发 ATK 倍率 —— 与下面的 "p2eq_080" 锚点同窗口。
	var shots: int = [3, 4, 10][si]
	var scale: float = HELI_SHOT_COEF
	# ★出膛点回调: 金弹从**机头**出去, 不再从地上那只龟身上。回调 ⇒ 直升机飞到哪就从哪出。
	battle._queue_shots(shots, HELI_SHOT_GAP, func() -> void: _heli_bullet(h, scale), owner, "p2eq_080",
		func() -> Vector2: return Vector2(h["pos"]) + Vector2(float(h.get("_muzzle_px", 0.0)), 0.0))


## 巡航的**移动**一步(纯几何, 不索敌不开火 ⇒ 门禁可以单独喂它)。
## ★抽出来的理由和 CLAUDE.md §3.5 同源: 一个测"它怎么飞"的用例, 不该被"它开枪"那条路径拖下水
##   —— 第一版门禁直接调 `_heli_patrol`, 合成假人缺 `crit`/`dmg_dealt` 字段, 伤害管线报了 16 条错。
##   移动与开火本来就是两件事, 分开之后两边都好测。
func _heli_orbit_step(h: Dictionary, target: Vector2, delta: float) -> void:
		# ★★2026-08-07 用户「别扭那就改」——原来是**贴到敌人脸上 60 码就停**, 然后钉在那儿。
		#   一架武装直升机应该**保持距离盘旋**, 不是悬在敌人头顶不动。
		#   模型: 径向趋近到 HELI_STANDOFF 码(远了进、近了退) + 切向绕圈。
		#   ⇒ 它永远在动、永远保持一个可读的交战距离; 而 60 码那版是"飞过去 → 定住"。
		#   ⚠ standoff 必须 < 机炮实际射程, 否则会站在射程外空转。
		var to: Vector2 = target - Vector2(h["pos"])
		var dist: float = maxf(1.0, to.length())
		var radial: Vector2 = to / dist
		var tangent := Vector2(-radial.y, radial.x)
		# 径向速度分量: 正=靠近, 负=后退。误差越大走得越快, 到位就自然停在环上。
		var err: float = dist - HELI_STANDOFF
		var v_r: float = clampf(err, -HELI_SPD, HELI_SPD)
		var v_t: float = HELI_ORBIT_SPD
		h["pos"] = Vector2(h["pos"]) + (radial * v_r + tangent * v_t).limit_length(HELI_SPD) * delta


## 一发机炮: 0.35 ATK 物理; **每命中一发 +4 龟能**(上限 100)。
func _heli_bullet(h: Dictionary, scale: float) -> void:
	var owner: Dictionary = h["owner"]
	var tgt = _heli_prey(h)
	if tgt == null or not tgt.get("alive", false):
		return
	# ★出膛点 = **机头**(不是机身中心)。`_muzzle_px` 由演出层按机头在贴图里的实测像素位置回填
	#   (见 heli_update), 已把 flip_h 算进去 ⇒ 直升机掉头时出膛点自动跟到另一侧。
	var muz: Vector2 = Vector2(h["pos"]) + Vector2(float(h.get("_muzzle_px", 0.0)), 0.0)
	# ★★2026-08-08 ⑭【伤害早于弹到达】: 原来这里当场扣血, 而弹要飞 0.4~0.7 秒 ——
	#   **血条先掉、弹后到**, 画面和实际发生的事是两回事(弹纯装饰)。
	#   ⇒ 先放演出拿到**飞行时间**, 再把结算推到弹真正到达那一刻(和炸弹同一条纪律)。
	#   ⚠ 内层 `_queue_shots` 传空 gun_id ⇒ **不重复计金弹**(外层那一发已经计过了)。
	var _fly: float = vfx.tracer(muz, Vector2(tgt["pos"]), COL_PHYS,
		float(owner.get("_golden_pct", 0.0)), GunEqVfx.HELI_H, GunEqVfx.body_mid_h(tgt), tgt,
		GunEqVfx.BUL_MG)   # ★机炮型: 快/细/长尾
	var _gp: float = float(owner.get("_golden_pct", 0.0))
	battle._queue_shots(1, 0.0, func() -> void:
		if not tgt.get("alive", false):
			return                                   # 弹在途中目标就死了 ⇒ 这一发落空(合理)
		# ★金弹标记要带过来, 理由同 _pistol_bullet 的长注释(否则金弹真伤白丢)
		var _sv: float = float(owner.get("_golden_pct", 0.0))
		owner["_golden_pct"] = _gp
		battle._damage._apply_damage_from(owner, tgt, battle._atk_dmg(owner, scale, tgt), COL_PHYS, 0.0, false, true)
		owner["_golden_pct"] = _sv
		h["energy"] = minf(HELI_EN_MAX, float(h.get("energy", 0.0)) + HELI_EN_PER_HIT)
		_heli_check_bomb(h)
	, owner, "", Callable(), _fly)


## 龟能满 ⇒ 起飞轰炸。★抽出来是因为结算已经推迟到弹到达那一刻(见 _heli_bullet),
## 检查也得跟着推迟 —— 否则会出现"龟能还没加上就先检查"。
## ⚠ `approach`/`egress` 也要排除: 否则进场途中龟能仍是满的, 每帧重算航线, 直升机原地抖。
func _heli_check_bomb(h: Dictionary) -> void:
	if float(h.get("energy", 0.0)) >= HELI_EN_MAX and not (str(h.get("state", "")) in ["bomb", "approach", "egress"]):
		_heli_begin_bomb(h)


## "正下方最近的敌人" —— 直升机在空中, 所以按【直升机自己的位置】找最近敌, 不是按携带者。
## ★走 `_nearest_enemy_from` 的同一套排除规则(黑洞/龟蛋围栏/训龟大师), 不就地手写
##   ([[fb-hand-rolled-copies-drift]])。
func _heli_prey(h: Dictionary):
	var owner: Dictionary = h["owner"]
	return battle._targeting._nearest_enemy_from(owner, Vector2(h["pos"]))


# ── 地毯轰炸 ──────────────────────────────────────────────────────

## 800×120 的带里有几个敌人。**纯函数**, 门禁可以拿它穷举复算(D9)。
static func lane_cover(center: Vector2, dir: Vector2, pts: Array,
		half_len: float = BOMB_LANE_LEN * 0.5, half_w: float = BOMB_LANE_W * 0.5) -> int:
	var n := 0
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	for p in pts:
		var rel: Vector2 = (p as Vector2) - center
		if absf(rel.dot(dir)) <= half_len and absf(rel.dot(perp)) <= half_w:
			n += 1
	return n


## 选覆盖敌人最多的那条航线。**确定性**: 候选 = 每个敌人当带心 × LANE_DIRS 个固定方位,
## 并列取先枚举到的(敌人按传入顺序、方位按角度升序)。返回 [center, dir]。
static func best_lane(pts: Array) -> Array:
	var best_c: Vector2 = Vector2.ZERO
	var best_d: Vector2 = Vector2.RIGHT
	var best_n := -1
	for c in pts:
		for k in range(LANE_DIRS):
			var a: float = PI * float(k) / float(LANE_DIRS)
			var d: Vector2 = Vector2(cos(a), sin(a))
			var n: int = lane_cover(c, d, pts)
			if n > best_n:
				best_n = n
				best_c = c
				best_d = d
	return [best_c, best_d, best_n]


## 一条航线上投几枚(按星级: 8/10/14, 含两端)。
static func bomb_count(si: int = 2) -> int:
	return BOMB_COUNT[clampi(si, 0, 2)]


## 相邻两枚的间距(码) —— 由枚数算出来, 不是反过来。
static func bomb_spacing(si: int = 2) -> float:
	return BOMB_LANE_LEN / float(maxi(1, bomb_count(si) - 1))


## 进场速度(码/秒)与兜底超时(秒)。★比巡航快 —— 它是"去占位", 慢吞吞飞过去会把节奏拖垮;
## 但仍然是**飞过去**而不是瞬移, 玩家看得到它在往哪儿去。
const HELI_APPROACH_SPD := 620.0
const HELI_APPROACH_MAX := 2.2

func _heli_begin_bomb(h: Dictionary) -> void:
	var owner: Dictionary = h["owner"]
	var pts: Array = []
	for o in battle._targeting._enemies_of(owner):
		if o.get("alive", false):
			pts.append(Vector2(o["pos"]))
	if pts.is_empty():
		return
	var lane: Array = best_lane(pts)
	var c: Vector2 = lane[0]
	var d: Vector2 = lane[1]
	var e1: Vector2 = c - d * (BOMB_LANE_LEN * 0.5)
	var e2: Vector2 = c + d * (BOMB_LANE_LEN * 0.5)
	# ★★2026-08-07 用户:「这种情况为什么不从右往左？不智能吗」——
	#   **原来根本没有"从哪头进"这个概念**: 起点写死成 `中心 − 方向×400`,
	#   而 `方向` 只由「哪条带覆盖敌人最多」决定(`best_lane` 枚举 12 个方位取覆盖最大),
	#   跟直升机当前在哪边**毫无关系** ⇒ 它经常绕到远端再飞回来, 看着就是"傻"。
	#   ⇒ **就近进场**: 两个端点里选离直升机近的那个当起点。
	#     这既是玩家期待的行为, 也顺带把进场那段路缩到最短(进场是 v0.19.45 加的, 会真的飞)。
	#   ⚠ 结算完全不变 —— 航线是**双向对称**的带(`lane_cover` 只看点到直线的距离),
	#     从哪头进, 覆盖到的敌人、投弹枚数、间隔都一样。
	var here: Vector2 = Vector2(h["pos"])
	if here.distance_squared_to(e2) < here.distance_squared_to(e1):
		var t: Vector2 = e1
		e1 = e2
		e2 = t
	h["lane_a"] = e1
	h["lane_b"] = e2
	# ★★2026-08-07 用户实拍:「你用瞬移了？」—— **是的, 这里原来就是一行瞬移**:
	#   `h["pos"] = lane_a` 把直升机**直接挪到航线起点**, 玩家看到的是它凭空闪了一下。
	#   航线起点离它当前位置最远可达 800 码(整条航线长), 这一跳非常显眼。
	#   ⇒ 加一个 `approach` 进场状态: 按 HELI_APPROACH_SPD 飞过去, 到位才开始投弹。
	#   ⚠ 结算不受影响 —— 投弹的落点/枚数/间隔都由 `run_t` 从 0 开始算, 进场只是多花一段时间。
	vfx.heli_alert(h)          # ★㉒ 起手提示: 机身闪白 + 脚下警示环 + 轻震屏
	h["state"] = "approach"
	h["run_t"] = 0.0
	h["bomb_t"] = 0.0
	h["bombs"] = 0
	h["energy"] = 0.0
	vfx.lane_marker(Vector2(h["lane_a"]), Vector2(h["lane_b"]), BOMB_LANE_W)


## 进场: 飞向航线起点。到位(或飞太久)就转 `bomb` 开投。
## ★兜底超时是必须的 —— 航线起点可能落在障碍/场外, 没有超时就会永远飞不到、卡死在这个状态。
func _heli_approach(h: Dictionary, delta: float) -> void:
	h["appr_t"] = float(h.get("appr_t", 0.0)) + delta
	var to: Vector2 = Vector2(h["lane_a"]) - Vector2(h["pos"])
	if to.length() <= HELI_APPROACH_SPD * delta + 6.0 or float(h["appr_t"]) >= HELI_APPROACH_MAX:
		h["pos"] = Vector2(h["lane_a"])
		h["state"] = "bomb"
		h["appr_t"] = 0.0
		return
	h["pos"] = Vector2(h["pos"]) + to.normalized() * HELI_APPROACH_SPD * delta


## 脱离: 沿原航向再飞一段, 然后回巡航。★这段**不索敌、不开火** —— 它就是"飞出去"。
func _heli_egress(h: Dictionary, delta: float) -> void:
	h["egr_t"] = float(h.get("egr_t", 0.0)) + delta
	var d: Vector2 = h.get("egr_dir", Vector2.RIGHT)
	h["pos"] = Vector2(h["pos"]) + d * HELI_EGRESS_SPD * delta
	if float(h["egr_t"]) * HELI_EGRESS_SPD >= HELI_EGRESS_LEN:
		h["state"] = "doom" if _heli_doomed(h) else "patrol"
		h["egr_t"] = 0.0


func _heli_bomb_run(h: Dictionary, delta: float) -> void:
	var total: float = BOMB_LANE_LEN / BOMB_RUN_SPD
	var n_total: int = bomb_count(int(h["si"]))
	var gap: float = total / float(maxi(1, n_total - 1))
	h["run_t"] = float(h.get("run_t", 0.0)) + delta
	var f: float = clampf(float(h["run_t"]) / total, 0.0, 1.0)
	h["pos"] = Vector2(h["lane_a"]).lerp(Vector2(h["lane_b"]), f)
	while int(h.get("bombs", 0)) < n_total and float(h["run_t"]) >= gap * float(h.get("bombs", 0)):
		var at: Vector2 = Vector2(h["lane_a"]).lerp(Vector2(h["lane_b"]), float(h["bombs"]) / float(maxi(1, n_total - 1)))
		h["bombs"] = int(h.get("bombs", 0)) + 1
		var si: int = int(h["si"])
		# ★炸弹也计入金弹计数(规格原文) ⇒ 同样从 `_queue_shots` 出去, gun_id 与机炮共用。
		# ★演出走**真入口**: 每投一枚就放一次完整演出(预警圈 + 真炸弹 + 尾迹)。
		#   `at` 是**伤害真正结算的那个落点**, 直接传给演出 ⇒ 预警圈和伤害范围天然是同一个数。
		vfx.bomb_drop(Vector2(h["pos"]), at, BOMB_R)
		# ★★2026-08-08【时序合一】用户:「炸弹碰到目标，爆炸特效？」——
		#   原来 `_queue_shots(1, …)` 的单发 delay 是 **0** ⇒ **伤害与爆炸在投弹那一瞬就发生**,
		#   而炸弹要飞 BOMB_FALL_SEC 才落地。玩家看到的是:
		#   **圈刚出现 → 立刻炸开 → 然后一颗炸弹慢悠悠落进一个已经炸完的坑里**, 落地悄无声息。
		#   ⇒ 把结算推迟到**炸弹真的落地那一刻**: 落地 = 伤害 = 爆炸, 三者同一时间点。
		#   ⚠ 用 `_queue_shots` 的 delay 而不是自己起计时器 —— 金弹计数/演出仍走同一个出口。
		battle._queue_shots(1, GOLD_GAP, func() -> void: heli_bomb_hit(h, si, at),
			h["owner"], "p2eq_080", func() -> Vector2: return at, GunEqVfx.BOMB_FALL_SEC)
	if f >= 1.0:
		# ★★用户「别扭那就改」——原来投完最后一枚**当帧就切回追敌**, 像被人拽了一把。
		#   真实的对地攻击机跑完航线要**沿航向脱离**再回来。加一个 `egress` 段:
		#   继续沿原航向飞 HELI_EGRESS_LEN 码, 期间不索敌、不开火, 飞完才回巡航。
		#   ⚠ 携带者已死(doom)时**不脱离** —— 那 10 秒窗口是给对手读的, 不该被这段拖长。
		if _heli_doomed(h):
			h["state"] = "doom"
		else:
			h["state"] = "egress"
			h["egr_t"] = 0.0
			h["egr_dir"] = (Vector2(h["lane_b"]) - Vector2(h["lane_a"])).normalized()
		h["fire_t"] = 0.0


func _heli_doomed(h: Dictionary) -> bool:
	var owner = h.get("owner", null)
	return not (owner is Dictionary and owner.get("alive", false))


## 一枚炸弹落地: 落点 BOMB_R(150) 码内 0.8/1.1/1.5 ATK 物理 + 40/70/120 魔法。
## ★公开(非下划线): 门禁直接调它验数值, **不依赖演出 tween 跑完**(CLAUDE.md §3.5)。
func heli_bomb_hit(h: Dictionary, si: int, at: Vector2) -> int:
	var owner: Dictionary = h["owner"]
	# ★三元数组就近声明(契约 §6): 上面 `_queue_shots(..., "p2eq_080")` 就是锚点。
	var scale: float = [0.8, 1.1, 1.5][si]
	var mag: float = [40.0, 70.0, 120.0][si]
	var n := 0
	for o in battle._targeting._enemies_of(owner):
		if not o.get("alive", false):
			continue
		if (Vector2(o["pos"]) - at).length() > BOMB_R:
			continue
		battle._damage._apply_damage_from(owner, o, battle._atk_dmg(owner, scale, o), COL_BOMB, 0.0, false, true)
		if o.get("alive", false):
			battle._damage._apply_damage_from(owner, o, battle._resolve_dmg(owner, mag, o, true), COL_MAGIC, 0.0, false, true)
		n += 1
	vfx.blast(at, BOMB_R, COL_BOMB)
	return n


# ── 坠机 ──────────────────────────────────────────────────────────

## 携带者死后 10 秒: 飞向**敌方随机一个单位**。★随机走 `battle._battle_rng`(焊死口径①)。
func _heli_begin_crash(h: Dictionary) -> void:
	var owner: Dictionary = h["owner"]
	var foes: Array = []
	for o in battle._targeting._enemies_of(owner):
		if o.get("alive", false):
			foes.append(o)
	if foes.is_empty():
		h["state"] = "dead"
		return
	var pick: Dictionary = foes[battle._battle_rng.randi() % foes.size()]
	h["crash_to"] = Vector2(pick["pos"])
	h["state"] = "crash"


func _heli_crash_fly(h: Dictionary, delta: float) -> void:
	var to: Vector2 = Vector2(h["crash_to"]) - Vector2(h["pos"])
	if to.length() <= CRASH_SPD * delta + 8.0:
		h["pos"] = Vector2(h["crash_to"])
		heli_crash_explode(h)
		h["state"] = "dead"
		return
	h["pos"] = Vector2(h["pos"]) + to.normalized() * CRASH_SPD * delta


## 坠机爆炸: 500 码内 200/300/500 物理 + 40 层灼烧(数值在 on_death 里就近声明并存进 h)。
## ★公开: 门禁直接调, 不等演出。
func heli_crash_explode(h: Dictionary) -> int:
	var owner: Dictionary = h["owner"]
	var at: Vector2 = Vector2(h["pos"])
	var phys: float = float(h.get("crash_phys", 0.0))
	var burn: int = int(h.get("crash_burn", 0))
	var n := 0
	for o in battle._targeting._enemies_of(owner):
		if not o.get("alive", false):
			continue
		if (Vector2(o["pos"]) - at).length() > CRASH_R:
			continue
		battle._damage._apply_damage_from(owner, o, battle._resolve_dmg(owner, phys, o, false), COL_BOMB, 0.0, false, true)
		if o.get("alive", false) and burn > 0:
			battle._damage._apply_dot_stacks(o, "burn", burn, owner)
		n += 1
	vfx.blast(at, CRASH_R, COL_BOMB)
	return n
