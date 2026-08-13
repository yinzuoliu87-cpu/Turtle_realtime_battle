class_name RelicEqVfx
extends RefCounted
## relic_eq_vfx.gd — 遗物两件新装备(091 远古龟甲片 / 094 祖龟碑)的演出层
## (规格 `docs/plans/20260805-装备逐件重做.md` §0.5 ★091 / ★094 · 契约 `20260806-实装契约-批④.md` §7)
##
## ══════════════════════════════════════════════════════════════════════
##  ★判据: 可验证的几何/物理规律, 不是"我调得像"
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-05 立的 3D 水准线是【触手那一版】, 第一条判据是「逐帧量参考做成包络表」。
## ⚠ **诚实记录**: 这两件**一张参考素材都没有** ⇒ 本文件**没有"逐帧量参考"这一步**。
## 代替它的是下面四条**闭式解 / 精确几何**, 判据不是"我调得像", 而是"它满足这几条可验证的等式"。
## 门禁验的正是这几条性质, 手调出来的缓动曲线一条都过不了。
##
## ── ① 091 甲片环: 正六边形密铺的【精确几何】 ────────────────────────
##   六片甲片围着携带者, 是正六边形**边对边密铺**中"中心那片的六个邻居"。
##   密铺给出两条**精确**关系(不是我拍的数):
##       邻居中心距 = √3 · R      (R = 甲片外接圆半径)
##       邻居方位角 = 30° + k·60° (k = 0..5)
##   ⇒ `hex_ring_centers()` 里没有一个手调系数; 门禁 ② 量的是**真实顶点**算出的
##     中心距/夹角/顶点角距, 随便挪一片都会红。
##   ★为什么非要密铺: "龟甲片"这四个字说的就是这个 —— 甲片之间**不留缝也不重叠**,
##     随手摆六个圆点摆不出这个性质。
##
## ── ② 091 回复脉冲: 二维柱面波的能量守恒 ────────────────────────────
##   一跳回复 = 一次点源脉冲。它在地面上铺成一圈, 圈长 2πr ⇒ **单位长度能量 ∝ 1/r**,
##   而能量 ∝ 振幅² ⇒
##       a(r) ∝ r^(−1/2)          `wave_amp()`
##   ★可验证性质(门禁 ③): **a(4r)/a(r) ≡ 1/2**, 与 r 无关。任何 `ease_out` 都给不出这条。
##
##   ★★**振幅与回复量焊死**: 脉冲总能量 ∝ 这一跳回的血 ⇒ 振幅 ∝ √(回复量)。
##     所以血量 <25% 翻 6 倍时, 甲片亮度恰好是 **√6 = 2.4495 倍** ——
##     「6」这个数在本项目里只有一份(`EqRelicBatch.SCUTE_LOW_MULT`), 由系统侧**传进来**,
##     本文件不抄第二遍(memory [[fb-write-without-reader-and-fake-gates]]:
##     抄两遍的话把产品代码改坏、门禁照样绿)。门禁 ③ 量的是**真实材质的 albedo alpha**。
##
## ── ③ 094 立碑: 匀减速上升(软着陆的唯一解) ──────────────────────────
##   碑被从地下顶出来, 到位那一刻速度**恰好为 0**(不是"到了再刹车"、也不是"撞上去弹一下")。
##   匀减速 a = −v₀/T 的唯一解归一后是
##       ĥ(τ) = 2τ − τ²          `rise_profile()`
##   ★三条可验证性质(门禁 ⑤): ĥ(1) ≡ 1 · ĥ′(1) ≡ 0(软着陆) · **ĥ(0.5) ≡ 0.75**。
##     线性上升在半程给 0.5、`ease_out_cubic` 给 0.875 —— 三者一测就分开。
##
## ── ④ 094 石雷: 真自由落体 ──────────────────────────────────────────
##   石块从 H 高处**无初速**落下:  z(t) = H − ½g t²  ⇒ 归一后 ẑ(τ) = 1 − τ²
##       T = √(2H/g)      v_落地 = gT = √(2gH)
##   ★可验证性质(门禁 ⑥): 等距采样的**二阶差分恒为 −2/N²**(抛物线的定义), 且
##     `fall_time(4H) / fall_time(H) ≡ 2`(尺度律)。匀速直线给二阶差分 0, ease 曲线给别的数。
##   落地的爆点**复用** `ShockwaveVfx`(Sedov–Taylor 波前 + Friedlander 超压), 不重造 ——
##   契约 §5「零素材特效原语」点名的就是它。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 091 全程序化 `ArrayMesh`(`SurfaceTool` 现算)；
## 094 = **两张新像素立绘** + 程序化几何 + `ShockwaveVfx`。
##
## ★2026-08-09 更正一条旧记录。这里原来写着「零素材 ⇒ 天然合规」, 那是把
##   **不生成素材** 说成了 **满足素材铁律**。铁律的原文是「新内容一律新素材」——
##   它要的是"别拿别件的图顶替", 不是"干脆别用图"。实拍的结论很直白:
##   五个 UNSHADED 纯色盒子拼出来的碑, 在实战镜头下就是一块**灰色多米诺骨牌**,
##   零质感、零"祖龟"身份。⇒ 碑体与石块改用 PixelLab 现生成的两张新图
##   (`eq094-stele.png` 52×62 / `eq094-stone.png` 28×30), 与 vfx 库里的其它素材无关联。
##
## ⚠ 朝向坑 (memory [[fb-axis-y-plus-rotation-cancels]]): 094 的两张立绘用 Sprite3D,
##   但**不设 `axis`、不设 billboard**, 顶点就在默认的 XY 平面(法线 +Z)⇒ 世界里真的立着,
##   没有"两个朝向设置互相抵消"的余地。贴地的东西(甲片/碑基石台)一律 y = GROUND_Y 的
##   水平顶点、用**贴地**网格; 立着的东西(碑顶符石/全队印记)用**立着**的网格 `_m_hexv`。
##   门禁两边各量一条 |三角面法线·上|(贴地要 ≈1.000, 立着要 ≈0.000)。
##
## ⚠ **立着的片要补长宽比**: 世界竖直在屏幕上被压扁到 0.626(见 PX_PER_M / PX_PER_M_VERT)。
##   直接按世界 1:1 摆 52×62 的碑立绘 ⇒ 屏幕上 70 宽 × 52 高 = 一块横匾。
##   补偿走 `screen_aspect_w()`; 会翻滚的片(石块)还得把补偿放到**父**节点上, 见 `_spin_sprite`。
##
## ⚠ 不用 `create_tween` (CLAUDE.md §3.5): 无头 CI 下 tween 推进不稳, 而且走 sim 的 delta
##   才跟时停/换路同步。**本层每一条形态都由 `tick(delta)` 推进**, 门禁可以同步喂任意 delta。
##
## ⚠ 材质一律 `material_override` 而不是 `set_surface_override_material` ——
##   后者在 `--headless` 的 dummy renderer 下每设一次刷一条
##   `ERROR: Parameter "material" is null.`(shockwave_vfx.gd:244 记的坑, 不在 FATAL 正则里但真的在刷)。


# ══════════════════════════════════════════════════════════════════
#  §几何/物理常数 —— 全部进闭式解, 没有一个是"调得像"调出来的
# ══════════════════════════════════════════════════════════════════

## 节点上打的自定义 meta 键(同 SynergyVfx.META_KEY 的做法: 程序生成的网格没有
## resource_path, 按路径数会全部数成 0)。
const META_KEY := "relic_eq_vfx"

## _owned 的上限, 照 SynergyVfx.OWNED_CAP / RB:_reg_tween 的做法留最后一道闸。
const OWNED_CAP := 256

## ── ① 甲片环(091) ────────────────────────────────────────────────
## 甲片的外接圆半径(场地像素)。密铺关系把环半径完全定死, 不另设参数。
## ★2026-08-07 从 13 提到 21 —— 实战默认视角标尺(1280×720·相机 (0,28,22) look_at (0,0.6,0)·fov 40):
##   横向 0.6755 屏幕像素/码、贴地纵深 0.5267 px/码。13 码外接圆 ⇒ 单片只有 17.6×13.7 px、
##   整环跨度 (2·√3·13 + 26) 码 = 30 px, 挤在龟脚底下一团。
##   21 码 ⇒ 单片 **28.4×22.1 px**、整环跨度 (2·√3·21 + 42) = 114.7 码 = **77.5×60.4 px**,
##   环真的"围着"44 px 高的龟立绘, 而不是垫在它脚下。
const PLATE_R_PX := 21.0
## 甲片数 = 正六边形密铺里"中心那片的邻居数", 是 6 —— 不是可调的美术数。
const PLATE_N := 6
## 甲片贴地高度(米)。略高于地面, 免得被地板 z-fighting 吃掉。
const GROUND_Y := 0.06
## 甲片的基准亮度(mult=1 那一跳)。★**上限校核**: ×√6 = 0.980 < 1.0 ⇒ **量程内不会被钳**,
##   门禁量到的 alpha 比值才是真的 √6 而不是"两边都撞上限所以相等"。
##   ⇒ PLATE_A 的**硬天花板是 1/√6 = 0.4082**, 想再提亮只能走描边/本色, 不能动这个数。
const PLATE_A := 0.40
## 甲片内芯 / 外沿的**顶点色 alpha**。总亮度 = PLATE_A(材质) × 顶点 alpha ⇒
## ★描边不占 alpha 量程: 提亮外沿不会把 ×√6 那条比值断言变成"两边都撞上限"。
## ⚠ 写了顶点色还得有人读 —— 材质必须开 `vertex_color_use_as_albedo`
##   (memory [[fb-write-without-reader-and-fake-gates]]: 生产侧写了消费侧没读, 一天踩三次)。门禁 G6 守这条。
const PLATE_VA_CORE := 0.62
const PLATE_VA_RIM := 1.00
## 外沿描边带的内边界(占外接圆半径的比例)
const PLATE_RIM_IN := 0.80
## 甲片亮度的指数衰减时间常数(秒)。= 一个回复节拍, 于是"上一片还没暗完下一片就亮"。
## ★2026-08-07 0.25 → 0.42: 节拍也是 0.25 秒 ⇒ 旧值让每片在下一跳之前刚好衰到 1/e = 37%,
##   随手截一帧十有八九落在低谷(改后实拍 `_vfxlab_af091_*.png` 三张全是暗的就是这么来的)。
const PLATE_TAU := 0.42
## 甲片亮度的**下限**(占 PLATE_A 的比例)。★这条是"甲片环随时看得见"的结构保证:
##   指数衰减的终点是 0, 意味着只要采样落在两跳之间的低谷, 甲片就是不存在的。
##   加了地板之后甲片环是一个**常驻**的玉青六边形环, 脉冲只是在它上面加亮。
## ⚠ 地板只作用在 `tick()` 的衰减上, **不碰 `scute_pulse` 写下的峰值** ——
##   否则 ×√6 那条比值断言会变成 (floor+a)/(floor+b) ≠ √6。
const PLATE_FLOOR_FRAC := 0.30

## ── 回复微粒(091) ────────────────────────────────────────────
## ★为什么要有它: 甲片脉冲的峰/谷之比被 PLATE_A 的天花板(1/√6)锁死, 实拍量到
##   "一跳只把环带总亮度推 5%" —— 机制在跑, 但**读不出在回血**(2026-08-09 用
##   "变亮像素数" 量出来的: 21393 像素亮起、间隔 0.24 秒 = 节拍, 肉眼却看不见)。
##   微粒不占 alpha 量程, 所以提可读性不会动那条 ×√6 的断言。
const MOTE_LIFE := 0.62
## 微粒升起的高度(米)与横向漂移(米)。
const MOTE_RISE_M := 1.9
const MOTE_DRIFT_M := 0.42
## 微粒边长(场地像素)。
const MOTE_SZ_PX := 3.6
## 一跳放几颗: 平时 1 颗(4 颗/秒, 不糊), <25% 爆发档 4 颗。
const MOTE_N := 1
const MOTE_N_LOW := 4

## ── ② 回复脉冲波(091) ────────────────────────────────────────────
## 柱面波振幅公式的起算半径(归一)。a(x) = √(X0/x), 在 x = X0 处恰为 1。
## ★取 1/16 是为了让"4 倍半径 → 半振幅"这条在 [X0, 1] 内**跨得下两整段**(1/16→1/4→1)。
const WAVE_X0 := 0.0625
## 脉冲波的最大半径(场地像素)与寿命(秒)。
const WAVE_R_PX := 74.0
const WAVE_LIFE := 0.42

## ── ★实战镜头的两把尺子(094 全靠它们定尺寸) ──────────────────────
## 默认视角 1280×720: 相机 (0,28,22) look_at (0,0.6,0), fov 40(竖直)。
##   视距 d = √(27.4² + 22²) = 35.13915 米, 屏高 = 2·d·tan20° = 25.5794 米
##   ⇒ **横向**(与视轴垂直) 28.14758 px/米 ／ **世界竖直** ×22/d = 17.62155 px/米
## ★关键推论: 世界里"立着"的一张片会被压扁到 **0.626**。
##   直接把 52×62 的碑立绘按世界高宽 1:1 摆上去, 屏幕上会变成 **宽 70 × 高 52** ——
##   一块躺倒的匾, 不是碑。所以碑/符石/石块的世界宽度都要按 `screen_aspect_w()` 反算。
const PX_PER_M := 28.147577
const PX_PER_M_VERT := 17.621551

## ── ③ 立碑(094) ──────────────────────────────────────────────────
## 碑破土升起的时长(秒)。
const RISE_SEC := 0.85
## 碑体总高(米)。★3.60 米 ⇒ 屏幕 **63.4 px 高**(龟立绘 44 px), 是个"地标"而不是路边石。
const STELE_H := 3.60
## 碑体立绘(新素材·PixelLab 2026-08-09 生成, 52×62)。
## ★为什么必须是立绘: 旧版是 5 个 UNSHADED 纯色盒子拼的, 实拍读成"一块灰色多米诺骨牌" ——
##   零质感、零"祖龟"身份。素材铁律(用户 2026-08-03):【新内容一律新素材】。
const STELE_TEX := "res://assets/sprites/vfx/eq094-stele.png"

## ── ③b 碑顶符石(094 唯一的分星信息) ──────────────────────────────
## ★2026-08-09 第三次重做。前两版的分星都**在屏幕上读不出来**:
##   · 第一版靠刻纹**宽度** 0.13/0.17/0.22 —— 7.3/9.6/12.4 px 的宽度差, 肉眼分不出。
##   · 第二版改成"数条数"(si+1 道横纹), 但**两面各画一组**, 而背面那组在屏幕上
##     正好被抬高约一个 GLYPH_PITCH ⇒ 与正面错位半格, **屏幕上数出来是 si+2**。
##     干净台实测(2026-08-09): 1★ 数出 2 条 / 2★ 数出 3 条 / 3★ 数出 4 条, 每档都多一条。
##     而当时的门禁只量了 `glyph_bands()` 这个**纯函数**(它当然返回 si+1)⇒ 全绿。
##     教训: 分星信息的门禁必须落在**屏幕上数得出来的东西**上。
## ⇒ 现在: **碑顶上方悬浮 si+1 颗琥珀六边形符石, 横向排开**。
##   横向排开 ⇒ 吃满 28.15 px/米(竖排只有 17.62), 且背景是空的天空, 对比度拉满。
const CREST_N_BASE := 1
## 单颗符石的外接圆半径(米)与相邻两颗的中心间距(米)。
## ★2·0.26·28.15 = 14.6 px 宽 / 间距 0.66·28.15 = 18.6 px ⇒ 3 颗跨 51.8 px, 一眼数得清。
const CREST_R_M := 0.26
const CREST_PITCH_M := 0.66
## 碑顶到符石中心的间距(米)。
const CREST_GAP_M := 0.40
## 符石的呼吸(振幅·占基准亮度的比例)与频率(Hz)。★纯正弦, 由 tick 推进, 不是自己的秒表。
const CREST_BREATH := 0.22
const CREST_HZ := 0.45
## 立着的六边形(符石 / 全队印记 / 台基石板)的内芯与外沿顶点 alpha, 以及外沿带的内边界。
## ★**自成一套, 不复用 091 的 PLATE_\*** —— 那三个常数归甲片环, 借过来用就是
##   "手抄的副本必然落后"的另一种写法: 甲片那边一调, 碑这边跟着变, 而两件毫无关系。
const CREST_RIM_IN := 0.72
const CREST_VA_CORE := 0.55
const CREST_VA_RIM := 1.00
## 全队光环头顶印记的外接圆半径(米)与离地高度(米)。
## ★0.30 米 ⇒ 屏幕 **16.9 px 宽**(阈值 16 px = 龟头顶等级徽章的边长)。
##   旧版是 7.5 **场地像素** = 0.18 米的**贴地**片, 实拍在实战镜头下只剩 10 个像素。
const MARK_R_M := 0.30
## ★3.30 米 ⇒ 屏幕 **58.2 px**。为什么不是"龟身高 2.0 米":
##   龟立绘是 **billboard**(正对镜头, 不吃竖直压缩)⇒ 它在屏幕上是 2.0 × 28.15 = 56.3 px 高;
##   而印记是世界里立着的片, 只吃 17.62 px/米。按 2.0 米摆会落在 35 px 处 = **正贴在龟背上**
##   (2026-08-09 实拍确认: 琥珀六边形压在友军的壳中间)。两套尺子不能混用。
const MARK_H_M := 3.30
const MARK_BOB_M := 0.09
const MARK_HZ := 0.55

## ── ③c 碑基石台(替掉旧的"无含义大圆环") ──────────────────────────
## ★旧版是一圈 58 码半径的实心圆环带, ADD 0.42 ⇒ 实拍量到 RGB(117,106,64) 的
##   **脏芥末色甜甜圈**, 横跨 320 屏幕像素, 比碑本身还大、还抢眼, 且不含任何信息
##   (memory [[fb-vfx-defect-families]] 点名的"无含义圆环")。
## ★更糟的是它**挂在会移动的 root 下** ⇒ 碑升起时它跟着从地下往上跑,
##   实测屏幕上整整走了 148 px(2.62 秒 y=579 → 3.42 秒 y=431), 而且因为开了
##   `no_depth_test` 连埋在地下都照样可见。地面上的印记本来就该钉死在地面。
## ⇒ 现在: **8 块梯形石板拼成的台基**(有缝隙 = 看得出是"砌"出来的), 半径收到 30 码,
##   钉在地面、不吃 no_depth_test, 石雷发射时整台亮一下(事件驱动, 不是自己数秒)。
const BASE_SIDES := 8
const BASE_R_PX := 30.0
const BASE_INNER := 0.52
const BASE_GAP_DEG := 3.2
const BASE_A := 0.80
## 石台的常态亮度与"发射石雷"闪光的衰减时间常数(秒)。
const BASE_FLASH_TAU := 0.42

## ── ④ 石雷(094) ──────────────────────────────────────────────────
## 石块的起落高度(米)与重力(米/秒²)。★两者一起把落时定死成 T = √(2H/g) = 0.5 秒,
##   不是"我觉得 0.5 秒好看"—— 改任一个, `fall_time()` 与门禁 ⑥ 一起跟着变。
## ══ 石雷 = 闪电劈下(2026-08-09 用户:「石雷我要闪电高高劈下来，不要图片」) ══
## 旧实现: 一张**静态石头贴图**从 BOLT_H 米自由落体 —— 那正是"图片"。
## 现在: [0,T) 目标头顶蓄能(预兆) → **T 那一刻**一道 7 帧闪电从高处贯到地面 + 白闪 + 震屏。
## ★★T 一帧不动 —— 伤害仍由 `stele_bolt_land` 在 T 结算, 演出只是换了内容。
##   (闪电本身是瞬时的, 拿它走"下落"就没有物理意义了; 所以把 T 用作**预兆窗口**。)
const THUNDER_TEX := "res://assets/sprites/vfx/eq094-thunder.png"
const THUNDER_FRAMES := 7
## 闪电从多高劈下来(米)。★"高高" —— 比旧石块的 5.25 高一截, 顶端出画外才有"从天上来"。
const THUNDER_H_M := 9.0
const THUNDER_LIFE := 0.34        ## 整道闪电活多久(秒)
const THUNDER_RACE := 0.14        ## 前 14% 寿命里通道**自上而下贯下来**(逐行揭开)
const THUNDER_FPS := 22.0         ## 通道抖动的帧速
## 预兆: 目标头顶聚一点能量, 随 τ 长大变亮。
const TELE_H_M := 2.2             ## 蓄能点离地高度(米)
const TELE_PX := 26.0             ## 蓄能点最大直径(码)

const BOLT_H := 5.25
const BOLT_G := 42.0
## 石块立绘(新素材·28×30)的世界高度(米)与翻滚角速度(弧度/秒)。
## ★旧版是程序化八面体 + UNSHADED 纯色 ⇒ 每个面同一个颜色, 只剩剪影,
##   实拍读成"一枚橙色五边形"(见 `_vfxlab_z1_3.png`), 完全不像石头。
const BOLT_TEX := "res://assets/sprites/vfx/eq094-stone.png"
const BOLT_H_M := 0.86
const BOLT_SPIN := 6.4

## 配色。甲片=玉青; 符石/台基描边=琥珀; 石雷落地=暖岩; 破土=暖尘。
## ★COL_DUST 是 2026-08-09 新加的: 破土爆点原来用 COL_STONE(luma 0.257), 实拍量到峰值
##   只有 RGB(52,43,44) —— 在 (9,10,16) 的黑场上是**全屏最暗的东西**, 而它本该是
##   "碑破土而出"这一刻的重音。改成暖尘 luma 0.69。
const COL_SCUTE := Color(0.48, 1.00, 0.74, 1.0)
const COL_STONE := Color(0.26, 0.28, 0.31, 1.0)
const COL_GLYPH := Color(1.00, 0.78, 0.34, 1.0)
const COL_BOLT := Color(0.86, 0.62, 0.36, 1.0)
const COL_DUST := Color(0.82, 0.70, 0.50, 1.0)


var battle
## 爆点原语(Sedov–Taylor + Friedlander)。★复用不重造 —— 契约 §5。
var _shock: ShockwaveVfx = null

## 本层建出来、还活着的节点(撤场用)。存节点不存单位字典 —— CLAUDE.md §3.2。
var _owned: Array = []

## 网格缓存。★存实例上不存 `static var` —— static 的话进程退出时 Godot 会报
##   `N resources still in use at exit`(shockwave_vfx.gd:146 记的坑)。
var _m_hex: ArrayMesh = null
var _m_ring: ArrayMesh = null
## 094: 立着的六边形(碑顶符石 / 全队印记) 与 贴地的分块石板环(碑基台)。
var _m_hexv: ArrayMesh = null
var _m_plates: ArrayMesh = null
## 094 的两张新立绘(碑体 / 石块)。★懒加载并缓存 —— `load()` 每次都查资源表。
var _tex_stele: Texture2D = null
var _tex_stone: Texture2D = null

## 091 每个携带者一套常驻甲片环: {u, root, plates:[6], a:[6], n}
var _scutes: Array = []
## 091 正在扩的回复脉冲波: {node, t, amp}
var _waves: Array = []
var _motes: Array = []
## 微粒的横向漂移**不走 rng** —— 用自增计数派生, 保住确定性(战斗 rng 序列一动, 别处钉序列的门禁就错位)。
var _mote_seq: int = 0
## 094 每座碑一套常驻碑体: {root, crest, t, si}
## ★注释里那个 `rune` 字段 2026-08-09 第三次重做时就没了(刻纹→碑顶符石), 一直没跟着改。
var _steles: Array = []
## 094 在途石块: {node, t, T, from(Vector3), to(Vector3), col}
var _rocks: Array = []
## 在途闪电(见 `thunder_strike`)。
var _thunders: Array = []
## 094 全队光环的头顶印记: {u, node, t}
var _marks: Array = []
## 正在播的爆点(ShockwaveVfx 句柄)
var _shocks: Array = []


func _init(b) -> void:
	battle = b
	_shock = ShockwaveVfx.new(b)


## 世界在不在。所有对外入口的第一行都是它 ——
## 主场景那几个 vfx 入口不守 `_world == null`, 在"只建单位不建世界"的数值测试里
## 那是 SCRIPT ERROR 而不是 FAIL, 会被 run-tests.sh 的 FATAL 正则接住(SynergyVfx R2 同款)。
func _has_world() -> bool:
	return battle != null and is_instance_valid(battle._world)


func _adopt(n: Node3D, kind: String) -> void:
	n.set_meta(META_KEY, kind)
	battle._world.add_child(n)
	if _owned.size() >= OWNED_CAP:
		_owned = _owned.filter(func(x): return is_instance_valid(x))
	_owned.append(n)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等 tween(契约 §7 / CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

## 正六边形密铺中, 中心那片的六个邻居的**中心偏移**(场地像素)。
##
## ★两条精确关系, 一个手调系数都没有:
##     距离 = √3 · R   (R = 外接圆半径; 两片共边 ⇒ 中心距 = 2 × 边心距 = 2 · (√3/2)R)
##     方位 = 30° + k·60°   (邻居在边心方向上, 而边心与顶点差 30°)
## 顶点自己在 0°, 60°, …, 300°(见 `_build_hex`)。
static func hex_ring_centers(plate_r: float) -> Array:
	var out: Array = []
	var d: float = sqrt(3.0) * plate_r
	for k in range(PLATE_N):
		var th: float = deg_to_rad(30.0 + 60.0 * float(k))
		out.append(Vector2(d * cos(th), d * sin(th)))
	return out


## 二维柱面波的归一振幅 a(x) = √(X0 / x), x = r / r_max ∈ (0, 1]。
##
## ★由能量守恒推出来的, 不是缓动曲线: 波前铺在周长 2πr 上 ⇒ 线密度 ∝ 1/r,
##   能量 ∝ 振幅² ⇒ 振幅 ∝ r^(−1/2)。
## ★可验证: a(4x)/a(x) ≡ 1/2, 与 x 无关。
static func wave_amp(x: float) -> float:
	return sqrt(WAVE_X0 / maxf(x, WAVE_X0))


## 一次回复脉冲的**初始振幅** = √(回复倍率)。
##
## ★脉冲总能量 ∝ 这一跳回的血, 能量 ∝ 振幅² ⇒ 振幅 ∝ √量。
##   `mult` 由系统侧传进来(平时 1.0 / 血量 <25% 时 `EqRelicBatch.SCUTE_LOW_MULT`),
##   本文件**不抄那个 6**。
static func pulse_amp(mult: float) -> float:
	return sqrt(maxf(mult, 0.0))


## 094 碑顶符石的位置(★门禁直接调, 不建节点)。
##
## 返回 `si + 1` 个 `Vector2(x, y)`(单位: 米, 相对碑底的地面点):
##   · **颗数 = si + 1** —— 分星信息落在"数得清的颗数"上
##   · **横向**排开 ⇒ 吃满 28.15 px/米(世界竖直只有 17.62), 且相邻两颗的屏幕间距
##     = CREST_PITCH_M × 28.15 = 18.6 px, 比单颗宽度(14.6 px)还大 ⇒ 一定分得开
##   · 以碑轴为中心左右均分 ⇒ 1/2/3 颗时视觉重心都在碑正上方
static func crest_slots(si: int, stele_h: float) -> Array:
	var n: int = CREST_N_BASE + clampi(si, 0, 2)
	var out: Array = []
	for k in range(n):
		out.append(Vector2((float(k) - float(n - 1) * 0.5) * CREST_PITCH_M, stele_h + CREST_GAP_M))
	return out


## 一张**立着**的片要多宽, 才能在屏幕上保住它自己的长宽比。
##
## ★世界竖直方向被压扁到 PX_PER_M_VERT / PX_PER_M = 0.626 ⇒
##     屏幕宽 = 世界宽 × PX_PER_M     屏幕高 = 世界高 × PX_PER_M_VERT
##   要 `屏幕宽 / 屏幕高 == tex_w / tex_h`, 世界宽就必须是
##     world_w = world_h × (PX_PER_M_VERT / PX_PER_M) × (tex_w / tex_h)
##   漏掉这个系数的话, 52×62 的碑立绘在屏幕上会变成 70 宽 × 52 高的**横匾**。
## ★可验证性质(门禁): `screen_aspect_w(h, w, h) / h ≡ 0.626`(正方形贴图的世界宽只有高的 0.626)。
static func screen_aspect_w(world_h: float, tex_w: float, tex_h: float) -> float:
	return world_h * (PX_PER_M_VERT / PX_PER_M) * (maxf(tex_w, 1.0) / maxf(tex_h, 1.0))


## 匀减速上升的归一高度 ĥ(τ) = 2τ − τ²(τ ∈ [0,1])。
## ★ĥ(1) = 1 且 ĥ′(1) = 0 ⇒ 到位那一刻速度恰为 0(软着陆的唯一解); ĥ(0.5) = 0.75。
static func rise_profile(tau: float) -> float:
	var t: float = clampf(tau, 0.0, 1.0)
	return 2.0 * t - t * t


## 无初速自由落体的归一高度 ẑ(τ) = 1 − τ²。等距采样二阶差分恒为 −2/N²(抛物线的定义)。
static func fall_profile(tau: float) -> float:
	var t: float = clampf(tau, 0.0, 1.0)
	return 1.0 - t * t


## 落时 T = √(2H/g)。★可验证: T(4H)/T(H) ≡ 2。
static func fall_time(h: float, g: float) -> float:
	return sqrt(2.0 * maxf(h, 0.0) / maxf(g, 0.001))


## 落地速度 v = gT = √(2gH)。
static func impact_speed(h: float, g: float) -> float:
	return g * fall_time(h, g)


# ══════════════════════════════════════════════════════════════════
#  §网格 —— 程序化 ArrayMesh, 零素材
# ══════════════════════════════════════════════════════════════════

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## 单位外接圆半径的正六边形甲片(贴地·顶点在 0°/60°/…/300°)。
## ★顶点角必须是这六个 —— `hex_ring_centers` 的 30° 偏移是**相对它们**成立的。
##
## ★2026-08-07 加**描边**: 内芯顶点 alpha PLATE_VA_CORE、外沿一圈 PLATE_VA_RIM。
##   原因是 PLATE_A 的天花板被 ×√6 那条比值断言焊死在 1/√6 = 0.408 —— 整片一起提亮
##   最多只能提 1.33 倍, 提不到"看得见"。描边走**顶点色**这条独立通道:
##   最终 alpha = 材质 alpha × 顶点 alpha, 比值断言只看材质那一半, 不受影响。
static func _build_hex() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rin: float = PLATE_RIM_IN
	for k in range(PLATE_N):
		var t0: float = TAU * float(k) / float(PLATE_N)
		var t1: float = TAU * float(k + 1) / float(PLATE_N)
		var i0 := Vector3(rin * cos(t0), 0.0, rin * sin(t0))
		var i1 := Vector3(rin * cos(t1), 0.0, rin * sin(t1))
		var o0 := Vector3(cos(t0), 0.0, sin(t0))
		var o1 := Vector3(cos(t1), 0.0, sin(t1))
		# 内芯扇形(暗)
		_tri_c(st, Vector3.ZERO, i0, i1, PLATE_VA_CORE)
		# 外沿描边带(亮)
		_tri_c(st, i0, o0, o1, PLATE_VA_RIM)
		_tri_c(st, i0, o1, i1, PLATE_VA_RIM)
	return st.commit()


## 带顶点 alpha 的三角面(RGB 恒白 —— 本色由材质 albedo 给, 顶点色只管明暗)。
static func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, va: float) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(Color(1.0, 1.0, 1.0, va))
		st.add_vertex(v)


## 单位外半径的贴地圆环带(内半径 inner)。
static func _build_annulus(inner: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg):
		var t0: float = TAU * float(i) / float(seg)
		var t1: float = TAU * float(i + 1) / float(seg)
		_quad(st,
			Vector3(inner * cos(t0), 0.0, inner * sin(t0)),
			Vector3(cos(t0), 0.0, sin(t0)),
			Vector3(cos(t1), 0.0, sin(t1)),
			Vector3(inner * cos(t1), 0.0, inner * sin(t1)))
	return st.commit()


## **立着**的正六边形(单位外接圆·XY 平面·法线 +Z)。094 的碑顶符石与全队印记都是它。
##
## ⚠ 与 `_build_hex()` 的区别只有"躺着还是立着", 但这正是 2026-08-09 实拍抓到的缺陷:
##   旧的全队印记直接拿**贴地**的 `_m_hex` 悬在头顶 1.15 米 —— 一张水平的片被 52° 俯角
##   看过去只剩一条缝, 实拍在实战镜头下**整只友军身上只有 10 个琥珀像素**。
##   贴地的东西用贴地网格、立着的东西用立着的网格, 不许混用
##   (memory [[fb-axis-y-plus-rotation-cancels]] 是同一个坑的另一面)。
## ★不设 `axis`、不设 `rotation` —— 顶点直接建在 XY 平面上, 没有"两个朝向设置互相抵消"的余地。
static func _build_hex_v() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rin: float = CREST_RIM_IN
	for k in range(6):
		var t0: float = TAU * float(k) / 6.0
		var t1: float = TAU * float(k + 1) / 6.0
		var i0 := Vector3(rin * cos(t0), rin * sin(t0), 0.0)
		var i1 := Vector3(rin * cos(t1), rin * sin(t1), 0.0)
		var o0 := Vector3(cos(t0), sin(t0), 0.0)
		var o1 := Vector3(cos(t1), sin(t1), 0.0)
		_tri_c(st, Vector3.ZERO, i0, i1, CREST_VA_CORE)
		_tri_c(st, i0, o0, o1, CREST_VA_RIM)
		_tri_c(st, i0, o1, i1, CREST_VA_RIM)
	return st.commit()


## 贴地的**分块环带**: `sides` 块梯形石板绕成一圈, 每块之间留 `gap_deg` 的缝。
##
## ★为什么不是一整圈实心环: 一整圈是"无含义圆环"(memory [[fb-vfx-defect-families]] 的一类),
##   而**留了缝的多块石板**一眼看得出是"砌"出来的台基 —— 同样的像素数, 多了含义。
## ★顶点 alpha: 内沿 CREST_VA_CORE(暗) / 外沿 CREST_VA_RIM(亮) ⇒ 每块石板自己有个边,
##   缝之外还多一层可读性。材质要开 `vertex_color_use_as_albedo` 才有人读它。
static func _build_plate_ring(sides: int, inner: float, gap_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = maxi(3, sides)
	var g: float = deg_to_rad(maxf(gap_deg, 0.0))
	for k in range(n):
		var t0: float = TAU * float(k) / float(n) + g
		var t1: float = TAU * float(k + 1) / float(n) - g
		var seg: int = 3
		for i in range(seg):
			var a0: float = lerpf(t0, t1, float(i) / float(seg))
			var a1: float = lerpf(t0, t1, float(i + 1) / float(seg))
			var pi0 := Vector3(inner * cos(a0), 0.0, inner * sin(a0))
			var pi1 := Vector3(inner * cos(a1), 0.0, inner * sin(a1))
			var po0 := Vector3(cos(a0), 0.0, sin(a0))
			var po1 := Vector3(cos(a1), 0.0, sin(a1))
			_tri_a(st, pi0, po0, po1, CREST_VA_CORE, CREST_VA_RIM, CREST_VA_RIM)
			_tri_a(st, pi0, po1, pi1, CREST_VA_CORE, CREST_VA_RIM, CREST_VA_CORE)
	return st.commit()


## 逐顶点 alpha 的三角面(RGB 恒白 —— 本色由材质 albedo 给, 顶点色只管明暗)。
## ★与 `_tri_c` 的区别: 那个一整面同一个 alpha, 这个内沿/外沿可以不同 ⇒ 石板才有"边"。
static func _tri_a(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		va: float, vb: float, vc: float) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length() > 1e-9 else Vector3.UP
	var vs: Array = [a, b, c]
	var al: Array = [va, vb, vc]
	for i in range(3):
		st.set_normal(n)
		st.set_color(Color(1.0, 1.0, 1.0, float(al[i])))
		st.add_vertex(vs[i])


## `use_vcol` = 让**顶点色**参与 albedo(甲片描边靠它; 见 `_build_hex`)。
## ⚠ 默认关: `_m_ring` 没有顶点色数组, 全局打开会让它吃到未定义的默认值。
##   有顶点色的只有 `_m_hex`(091 甲片) / `_m_hexv`(094 符石·印记) / `_m_plates`(094 石台)。
static func _mat(col: Color, additive: bool, no_depth: bool, prio: int,
		use_vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.no_depth_test = no_depth
	m.render_priority = prio
	m.vertex_color_use_as_albedo = use_vcol
	return m


func _mesh_node(mesh: ArrayMesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _ensure_meshes() -> void:
	if _m_hex == null:
		_m_hex = _build_hex()
	if _m_ring == null:
		_m_ring = _build_annulus(0.74, 48)
	if _m_hexv == null:
		_m_hexv = _build_hex_v()
	if _m_plates == null:
		_m_plates = _build_plate_ring(BASE_SIDES, BASE_INNER, BASE_GAP_DEG)


## 094 的两张立绘。★缺图时返回 null 而不是崩 —— 调用侧一律判 null 再建节点。
var _tex_thunder: Texture2D = null
func _tex(path: String) -> Texture2D:
	if path == STELE_TEX:
		if _tex_stele == null and ResourceLoader.exists(path):
			_tex_stele = load(path) as Texture2D
		return _tex_stele
	if path == THUNDER_TEX:
		if _tex_thunder == null and ResourceLoader.exists(path):
			_tex_thunder = load(path) as Texture2D
		return _tex_thunder
	if _tex_stone == null and ResourceLoader.exists(path):
		_tex_stone = load(path) as Texture2D
	return _tex_stone


## 一张**立着**的立绘片(碑体 / 石块共用)。★不 billboard、不设 axis、不加 rotation ——
##   顶点就在 XY 平面上, 世界里真的是竖着的, 与地面的遮挡关系精确。
## ★世界宽由 `screen_aspect_w()` 反算, 保证屏幕上是立绘本来的长宽比。
func _sprite_node(tex: Texture2D, world_h: float, prio: int) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sp.shaded = false
	sp.transparent = true
	## ⚠ 不用 ALPHA_CUT_DISCARD: 它按 0.5 阈值丢像素, 而这两张片都会被整体压暗
	##   (碑升起时的入场淡入 / 石块的落地前压暗) ⇒ 整张图会被丢光
	##   (2026-08-09 在 090 的电弧上刚踩过这条)。
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.render_priority = prio
	var tw: float = float(maxi(1, tex.get_width()))
	var th: float = float(maxi(1, tex.get_height()))
	sp.pixel_size = world_h / th
	var nat_w: float = world_h * tw / th                       # pixel_size 直接给出的世界宽
	sp.scale = Vector3(screen_aspect_w(world_h, tw, th) / maxf(nat_w, 1e-6), 1.0, 1.0)
	return sp


## 会**翻滚**的立绘片: 压缩放**父**节点、旋转放**子**节点, 返回父节点。
##
## ★为什么非拆两层不可(2026-08-09 实拍抓到): 横向压缩是"世界竖直被压扁 0.626"的补偿,
##   它必须**永远沿世界 x** 生效。写在同一个节点上时 `basis = R · S` ⇒ 压缩跟着一起转,
##   翻到 90° 那一刻长宽直接对调 —— 实测石块在半程被压成 **32 × 13.6 px 的一条**
##   (本该是 18.7 × 20)。放到父节点后 `basis = S · R`: 先转再压, 任何角度都对。
func _spin_sprite(tex: Texture2D, world_h: float, prio: int) -> Node3D:
	var sp := _sprite_node(tex, world_h, prio)
	var comp: float = sp.scale.x
	sp.scale = Vector3.ONE
	var wrap := Node3D.new()
	wrap.scale = Vector3(comp, 1.0, 1.0)
	wrap.add_child(sp)
	return wrap


# ══════════════════════════════════════════════════════════════════
#  §091 远古龟甲片 —— 常驻甲片环 + 回复脉冲波
# ══════════════════════════════════════════════════════════════════

## 找(或建)某个携带者的甲片环句柄。世界不在 → 返回 {}。
func ensure_scutes(u: Dictionary) -> Dictionary:
	if not _has_world() or not (u is Dictionary):
		return {}
	for h in _scutes:
		if is_same(h["u"], u):                # is_same: 单位字典互引成环, == 会深比较→卡死
			return h
	_ensure_meshes()
	var root := Node3D.new()
	var plates: Array = []
	var alphas: Array = []
	var ps: float = PLATE_R_PX * float(battle.WS)
	for c in hex_ring_centers(PLATE_R_PX):
		# no_depth=false: 甲片是**贴地**的(y=GROUND_Y), 开了 no_depth_test 就会画在龟立绘之上
		# ⇒ 六倍档全甲亮起时整片压住龟壳和脸(2026-08-09 实拍确认)。关掉后由深度决定遮挡。
		var mi := _mesh_node(_m_hex, _mat(Color(COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, 0.0), true, false, 8, true))
		mi.scale = Vector3(ps, 1.0, ps)
		mi.position = Vector3(float(c.x) * float(battle.WS), 0.0, float(c.y) * float(battle.WS))
		root.add_child(mi)
		plates.append(mi)
		alphas.append(0.0)
	root.position = battle._world_pos(u["pos"], GROUND_Y)
	_adopt(root, "scute_ring")
	var h2 := {"u": u, "root": root, "plates": plates, "a": alphas, "n": 0}
	_scutes.append(h2)
	return h2


## 一跳回复的演出。**每一跳都调**, `mult` 由系统侧传(平时 1.0 / <25% 时 6.0)。
##
## ★甲片按密铺顺序**轮流**点亮(第 n 跳点第 n%6 片) —— 一秒 4 跳、六片一轮半 ⇒
##   看得出"在一片片长回来"; 而 <25% 时**六片同时**点亮到 √6 倍, 那道悬崖是看得见的。
## ⚠ 本函数返回时甲片亮度就是最终值, 门禁下一行就能量, 不等任何动画。
func scute_pulse(u: Dictionary, _si: int, mult: float) -> Dictionary:
	var h: Dictionary = ensure_scutes(u)
	if h.is_empty():
		return {}
	var amp: float = PLATE_A * pulse_amp(mult)
	var n: int = int(h["n"])
	var plates: Array = h["plates"]
	var alphas: Array = h["a"]
	var low: bool = mult > 1.0
	for k in range(plates.size()):
		if low or k == (n % maxi(1, plates.size())):
			alphas[k] = amp
			var mi = plates[k]
			if is_instance_valid(mi):
				(mi.material_override as StandardMaterial3D).albedo_color = Color(
					COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, amp)
	h["n"] = n + 1
	h["a"] = alphas
	## 微粒从**这一跳点亮的那片甲**上升起(爆发档六片全亮 ⇒ 绕环均摊)
	var lit_k: int = n % maxi(1, plates.size())
	_emit_motes(h, lit_k, MOTE_N_LOW if low else MOTE_N, low)
	if low:
		_emit_wave(u["pos"], amp)
	return h


## 一跳的回复微粒: 从甲片位置升起、边升边淡。
## ⚠ 位置取的是**甲片节点的真实 local position**(不是重算一遍几何) —— 手抄的副本必然落后。
func _emit_motes(h: Dictionary, lit_k: int, cnt: int, low: bool) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var root = h.get("root", null)
	if not is_instance_valid(root):
		return
	var plates: Array = h["plates"]
	if plates.is_empty():
		return
	var ms: float = MOTE_SZ_PX * float(battle.WS)
	for i in range(cnt):
		var k: int = (lit_k + i * 2) % plates.size()
		var pl = plates[k]
		if not is_instance_valid(pl):
			continue
		# no_depth=false: 微粒从环上升起, 让龟立绘按深度遮挡它 —— 否则前后排的微粒
		# 一律糊在龟脸上(实拍见 m091e)。
		## ⚠ `_adopt` 自己会把节点挂到 World —— 再 `root.add_child` 一次就是
		##   "already has a parent"(实拍 log 里刷了 24 条)。所以这里换算成**世界坐标**。
		var wp: Vector3 = (root as Node3D).position + (pl as Node3D).position
		var mi := _mesh_node(_m_hex, _mat(COL_SCUTE, true, false, 10))
		mi.scale = Vector3(ms, 1.0, ms)
		mi.position = wp
		_adopt(mi, "heal_mote")
		var ph: float = float(_mote_seq)
		_mote_seq += 1
		_motes.append({
			"node": mi, "t": 0.0,
			"p0": wp,
			"dx": cos(ph * 2.399) * MOTE_DRIFT_M,
			"dz": sin(ph * 2.399) * MOTE_DRIFT_M,
			"rise": MOTE_RISE_M * (1.25 if low else 1.0),
		})


## 把 t ∈ [0, MOTE_LIFE] 的微粒写到真实节点上(纯同步, 门禁可直接调)。
func apply_mote(m: Dictionary, t: float) -> void:
	var mi = m.get("node", null)
	if not is_instance_valid(mi):
		return
	var uu: float = clampf(t / MOTE_LIFE, 0.0, 1.0)
	var p0: Vector3 = m["p0"]
	(mi as Node3D).position = Vector3(
		p0.x + float(m["dx"]) * uu, p0.y + float(m["rise"]) * uu, p0.z + float(m["dz"]) * uu)
	## ★holdfade: 前 55% 满亮再收 —— 从出生就淡是本轮改了五次的老毛病
	var a: float = 1.0 if uu < 0.55 else (1.0 - (uu - 0.55) / 0.45)
	((mi as Node3D).get("material_override") as StandardMaterial3D).albedo_color = Color(
		COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, a)


## 一圈柱面波(只在 <25% 的爆发态放 —— 平时 4 次/秒放圈会糊成一片)。
func _emit_wave(pos2d: Vector2, amp: float) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var mi := _mesh_node(_m_ring, _mat(Color(COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, 0.0), true, true, 9))
	mi.position = battle._world_pos(pos2d, GROUND_Y)
	_adopt(mi, "heal_wave")
	var w := {"node": mi, "t": 0.0, "amp": amp}
	_waves.append(w)
	apply_wave(w, 0.0)


## 把 u ∈ [0,1] 时刻的波形写到**真实节点**上。纯同步 —— 演出与门禁只有这一份实现。
func apply_wave(w: Dictionary, u: float) -> void:
	var mi = w.get("node", null)
	if not is_instance_valid(mi):
		return
	var x: float = maxf(clampf(u, 0.0, 1.0), WAVE_X0)
	var r: float = WAVE_R_PX * float(battle.WS) * x
	mi.scale = Vector3(maxf(r, 1e-4), 1.0, maxf(r, 1e-4))
	(mi.material_override as StandardMaterial3D).albedo_color = Color(
		COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, float(w["amp"]) * wave_amp(x))


## 携带者死了 / 换路: 收掉它的甲片环。
func drop_scutes(u: Dictionary) -> void:
	var keep: Array = []
	for h in _scutes:
		if is_same(h["u"], u):
			var r = h["root"]
			if is_instance_valid(r):
				r.queue_free()
			continue
		keep.append(h)
	_scutes = keep


# ══════════════════════════════════════════════════════════════════
#  §094 祖龟碑 —— 破土立碑 + 碑基石台 + 碑顶符石 + 石雷 + 全队印记
# ══════════════════════════════════════════════════════════════════

## 在 pos2d 立一座碑。返回句柄; 世界不在时返回 {}。
##
## 句柄: {root, sprite, base, crests:[si+1], pos, t, si, flash}
## ⚠ 句柄在本函数返回时就是 **τ=0 的最终值**(碑还一点没露头), 门禁下一行就能量。
func raise_stele(pos2d: Vector2, si: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	var sn: int = clampi(si, 0, 2)
	var root := Node3D.new()
	root.position = battle._world_pos(pos2d, 0.0)
	var gl: Color = COL_GLYPH

	## ── 碑基石台(贴地) ──
	## ★**先建、位置写死在 root 的局部 0 高度**, 而且 root 从此**一动不动** ——
	##   旧版把它挂在会上下移动的 root 下, 碑升起时它跟着从地里冒出来, 实测在屏幕上
	##   走了 148 px。地面上的印记就该钉在地面上。
	## ★no_depth=false: 它是**贴地**的石台, 开了 no_depth_test 会连埋在地下都可见(旧版的另一半毛病)。
	var base := _mesh_node(_m_plates, _mat(
		Color(COL_STONE.r * 1.30, COL_STONE.g * 1.22, COL_STONE.b * 1.05, BASE_A), false, false, 3, true))
	var br: float = BASE_R_PX * float(battle.WS)
	base.scale = Vector3(br, 1.0, br)
	base.position = Vector3(0.0, GROUND_Y, 0.0)
	root.add_child(base)

	## ── 碑体(新立绘·竖直片) ──
	var tex: Texture2D = _tex(STELE_TEX)
	var sprite: Sprite3D = null
	if tex != null:
		sprite = _sprite_node(tex, STELE_H, 5)
		sprite.position = Vector3(0.0, 0.0, 0.0)
		root.add_child(sprite)

	## ── 碑顶符石: si+1 颗, 横向排开(分星信息) ──
	var crests: Array = []
	for s in crest_slots(sn, STELE_H):
		var mi := _mesh_node(_m_hexv, _mat(Color(gl.r, gl.g, gl.b, 1.0), false, false, 8, true))
		mi.scale = Vector3(CREST_R_M, CREST_R_M, CREST_R_M)
		mi.position = Vector3(float(s.x), float(s.y), 0.02)
		root.add_child(mi)
		crests.append(mi)

	_adopt(root, "stele")
	var h := {
		"root": root, "sprite": sprite, "base": base, "crests": crests,
		"pos": pos2d, "t": 0.0, "si": sn, "flash": 0.0,
	}
	_steles.append(h)
	apply_stele(h, 0.0)
	# 破土: 复用 ShockwaveVfx 的爆点(不重造)。★颜色是**暖尘**不是石头本色 ——
	#   旧版用 COL_STONE(luma 0.257), 实拍峰值只有 RGB(52,43,44), 是全屏最暗的东西。
	_blast(pos2d, Color(COL_DUST.r, COL_DUST.g, COL_DUST.b, 0.9))
	return h


## 把 τ ∈ [0,1] 的升起形态写到**真实节点**上。纯同步。
##
## ★升起靠 **`region_rect` 逐行揭开立绘**, 不靠"把整座碑往下埋再让地板挡住":
##   ① 地板挡不挡得住取决于地图(VFXLAB 的黑场、某些关卡的镂空地面都会漏),
##      而 region 是**画多少就是多少**, 与场景无关;
##   ② 屏幕上"露出多少"变成一个可以直接读的数(`region_rect.size.y / 贴图高`),
##      门禁能量真实节点, 不用去反推一个世界坐标。
## 露出的是立绘的**上半部**(碑顶先破土), 区域的**下边缘恒在地面** ⇒ 看着就是从土里顶出来。
func apply_stele(h: Dictionary, tau: float) -> void:
	var sp = h.get("sprite", null)
	if not is_instance_valid(sp):
		return
	var tex: Texture2D = (sp as Sprite3D).texture
	if tex == null:
		return
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	var f: float = clampf(rise_profile(tau), 0.0, 1.0)
	var rh: float = maxf(th * f, 1.0)
	(sp as Sprite3D).region_enabled = true
	(sp as Sprite3D).region_rect = Rect2(0.0, 0.0, tw, rh)
	## offset 单位是贴图像素, +y = 往上 ⇒ 区域底边正好落在节点(地面)上。
	(sp as Sprite3D).offset = Vector2(0.0, rh * 0.5)


## 每帧推进一座碑(升起 + 符石呼吸/跟顶 + 石台闪光衰减)。
func advance_stele(h: Dictionary, delta: float) -> void:
	var d: float = maxf(delta, 0.0)
	h["t"] = float(h.get("t", 0.0)) + d
	var t: float = float(h["t"])
	var f: float = clampf(rise_profile(t / RISE_SEC), 0.0, 1.0)
	apply_stele(h, t / RISE_SEC)
	## 符石跟着碑顶一起冒出来 —— 碑没升到位, 符石就还在土里(y 跟着 f 走), 且整体淡入。
	var breath: float = 1.0 + CREST_BREATH * sin(TAU * CREST_HZ * t)
	var crests: Array = h.get("crests", [])
	var slots: Array = crest_slots(int(h.get("si", 0)), STELE_H * f)
	for k in range(mini(crests.size(), slots.size())):
		var mi = crests[k]
		if not is_instance_valid(mi):
			continue
		var s: Vector2 = slots[k]
		(mi as Node3D).position = Vector3(float(s.x), float(s.y), 0.02)
		((mi as Node3D).get("material_override") as StandardMaterial3D).albedo_color = Color(
			COL_GLYPH.r, COL_GLYPH.g, COL_GLYPH.b, clampf(f * f * breath, 0.0, 1.0))
	## 石台: 常态 BASE_A, 发射石雷时被 `stele_flash()` 推到 1.0 再指数衰减回来。
	## ⚠ 这是**事件驱动**的 —— 石台不数自己的秒表, 它只在系统真的发射了石雷时被推一下
	##   (CLAUDE.md 的"必须与物理事件同帧的演出不能有自己的秒表")。
	h["flash"] = float(h.get("flash", 0.0)) * exp(-d / BASE_FLASH_TAU)
	var bs = h.get("base", null)
	if is_instance_valid(bs):
		var a: float = clampf(BASE_A + (1.0 - BASE_A) * float(h["flash"]), 0.0, 1.0)
		var c: Color = Color(COL_STONE.r * 1.30, COL_STONE.g * 1.22, COL_STONE.b * 1.05, 1.0)
		var w: float = float(h["flash"])
		((bs as Node3D).get("material_override") as StandardMaterial3D).albedo_color = Color(
			lerpf(c.r, COL_GLYPH.r, w), lerpf(c.g, COL_GLYPH.g, w), lerpf(c.b, COL_GLYPH.b, w), a)


## 石雷发射的那一刻: 把碑基石台推到满亮(之后由 `advance_stele` 指数衰减)。
## ★由 `EqRelicBatch.stele_fire()` 调 —— 与"真的发射了一发"同帧, 演出侧不自己判时。
func stele_flash(h) -> void:
	if h is Dictionary:
		(h as Dictionary)["flash"] = 1.0


## 收掉一座碑(换路 / 撤场)。
func drop_stele(h: Dictionary) -> void:
	var keep: Array = []
	for x in _steles:
		if x.get("root", null) == h.get("root", null):
			var r = x.get("root", null)
			if is_instance_valid(r):
				r.queue_free()
			continue
		keep.append(x)
	_steles = keep


## 砸一道石雷: 石块从 `to2d` 正上方 BOLT_H 米无初速落下, 落地放爆点。
## 返回句柄; 世界不在时返回 {}。★落时由 `fall_time(BOLT_H, BOLT_G)` 定死。
## 石雷的**预兆**: 目标头顶聚一点能量, 随 τ 长大变亮。真正的闪电在 `thunder_strike` 里,
## 由结算侧在**伤害那一帧**调 —— 演出与伤害同帧, 演出侧不自己数秒。
## 函数名沿用 `stone_bolt`(结算侧与门禁都在调它), 内容已换成蓄能点。
func stone_bolt(to2d: Vector2, si: int) -> Dictionary:
	if not _has_world():
		return {}
	_ensure_meshes()
	var sn: int = clampi(si, 0, 2)
	var mi := _mesh_node(_m_ring, _mat(COL_GLYPH, true, true, 14))
	mi.position = battle._world_pos(to2d, TELE_H_M)
	_adopt(mi, "stone_bolt")
	var b := {
		"node": mi, "spr": null, "t": 0.0, "T": fall_time(BOLT_H, BOLT_G),
		"pos": to2d, "si": sn, "h_m": TELE_H_M,
	}
	_rocks.append(b)
	apply_bolt(b, 0.0)
	return b


## ★★真正的闪电: 从 THUNDER_H_M 米高处**贯到地面**。
## · 前 THUNDER_RACE 段用 `region_rect` **自上而下逐行揭开** ⇒ 看得出是"劈下来"而不是"整根冒出来"
## · 通道每帧换一张(7 帧) ⇒ 抖动是**逐帧变形**, 不是缩放假动
## · holdfade: 前 55% 满亮再收
func thunder_strike(at2d: Vector2, si: int) -> Dictionary:
	if not _has_world():
		return {}
	var tex: Texture2D = _tex(THUNDER_TEX)
	if tex == null:
		return {}
	var sn: int = clampi(si, 0, 2)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.hframes = THUNDER_FRAMES
	sp.frame = 0
	## ⚠ 必须 FIXED_Y 不能 ENABLED: `BILLBOARD_ENABLED` 会让精灵**完全**对齐相机(含 roll),
	##   而本作相机是 52° 俯视 ⇒ 一道竖直的闪电会被掰成斜的短条(2026-08-09 实拍确认)。
	##   `BILLBOARD_FIXED_Y` 只绕 Y 轴转 ⇒ 始终正对镜头**且保持直立**。
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.transparent = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED   # ⚠ DISCARD 会把压暗的整道闪电丢光
	sp.render_priority = 20
	var fw: float = float(tex.get_width()) / float(THUNDER_FRAMES)
	var fh: float = float(tex.get_height())
	## 高度按 THUNDER_H_M 反算 pixel_size; 3★ 再粗壮一点
	sp.pixel_size = THUNDER_H_M * (1.0 + 0.10 * float(sn)) / maxf(1.0, fh)
	sp.position = battle._world_pos(at2d, THUNDER_H_M * 0.5 * (1.0 + 0.10 * float(sn)))
	_adopt(sp, "thunder")
	var h := {"node": sp, "t": 0.0, "life": THUNDER_LIFE, "at": at2d, "si": sn,
		"fw": fw, "fh": fh, "y_full": sp.position.y}
	_thunders.append(h)
	apply_thunder(h, 0.0)
	return h


## 把 u ∈ [0,1] 的闪电形态写到**真实节点**上。纯同步 —— 门禁直接调, 不等任何动画。
func apply_thunder(h: Dictionary, u: float) -> void:
	var sp = h.get("node", null)
	if not is_instance_valid(sp):
		return
	var t: float = clampf(u, 0.0, 1.0)
	var s3 := sp as Sprite3D
	## ⚠ **不用 `region_enabled`**: 实拍证明那条路走不通 —— 节点 visible=true/alpha=1/挂在
	##   World 下, 把它染成品红后全屏**零个品红像素**(两轮: 区域高度下限 0 与 0.06 都一样)。
	##   090 的电弧用的是 `hframes` + `frame`, 那条路是验证过能渲染的, 这里照抄。
	s3.hframes = THUNDER_FRAMES
	s3.frame = int(floor(t * float(h.get("life", THUNDER_LIFE)) * THUNDER_FPS)) % THUNDER_FRAMES
	## holdfade: 前 55% 满亮再收
	s3.modulate.a = 1.0 if t < 0.55 else (1.0 - (t - 0.55) / 0.45)


## 把 τ ∈ [0,1] 的落体形态写到**真实节点**上。纯同步。
## ★高度走 `fall_profile`(真抛物线), 自转是**匀角速**(刚体无力矩 —— 空中没有力矩就不会变速)。
## ⚠ 只绕**视线轴 z** 转: 立绘是一张竖直的片, 绕 x/y 转会把它转到侧面变成一条线
##   (旧版的程序化石头绕 x/y 转没事, 换成片之后就不行了)。
func apply_bolt(b: Dictionary, tau: float) -> void:
	var mi = b.get("node", null)
	if not is_instance_valid(mi):
		return
	var t: float = clampf(tau, 0.0, 1.0)
	## 蓄能点: 随 τ 长大变亮, 停在目标头顶 TELE_H_M。★不再有"下落"这回事 ——
	##   闪电是瞬时的, 真正的一击在 `thunder_strike`, 由结算侧在伤害那一帧调。
	var d: float = TELE_PX * float(battle.WS) * (0.25 + 0.75 * t * t)
	(mi as Node3D).scale = Vector3(d, 1.0, d)
	(mi as Node3D).position = battle._world_pos(b["pos"], TELE_H_M)
	var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
	if m != null:
		m.albedo_color = Color(COL_GLYPH.r, COL_GLYPH.g, COL_GLYPH.b, 0.15 + 0.85 * t * t)


## 一次点爆(复用 ShockwaveVfx)。
func _blast(pos2d: Vector2, col: Color) -> void:
	if not _has_world():
		return
	var h: Dictionary = _shock.make_blast(pos2d, col, 1)
	if h.is_empty():
		return
	for k in ShockwaveVfx.NODE_KEYS:
		_adopt(h[k], "blast")
	_shocks.append(h)


## 全队光环的头顶印记 —— **名单由系统侧给**(全场生效、不设半径)。
##
## ★门禁数的就是这个名单的长度: 若哪天有人把光环改成"半径内才吃",
##   印记数会立刻对不上友军数 —— 这正是把"全场"这句话变成可判定的形式。
func set_marks(units: Array) -> void:
	if not _has_world():
		return
	_ensure_meshes()
	var keep: Array = []
	for m in _marks:
		var still := false
		for u in units:
			if u is Dictionary and is_same(m["u"], u):
				still = true
				break
		if still:
			keep.append(m)
		else:
			var n = m.get("node", null)
			if is_instance_valid(n):
				n.queue_free()
	_marks = keep
	for u in units:
		if not (u is Dictionary):
			continue
		var have := false
		for m in _marks:
			if is_same(m["u"], u):
				have = true
				break
		if have:
			continue
		## ★用**立着**的六边形 `_m_hexv`, 不是贴地的 `_m_hex`。
		##   旧版拿贴地网格悬在头顶 1.15 米 —— 52° 俯角看一张水平的片, 实拍在实战镜头下
		##   整只友军身上只剩 **10 个琥珀像素**(2026-08-09 逐像素数出来的), 等于没做。
		## ★半径 0.30 米 ⇒ 屏幕 16.9 px 宽, 刚过"龟头顶等级徽章 16 px"这条存在阈值。
		var mi := _mesh_node(_m_hexv, _mat(Color(COL_GLYPH.r, COL_GLYPH.g, COL_GLYPH.b, 0.92), false, true, 9, true))
		mi.scale = Vector3(MARK_R_M, MARK_R_M, MARK_R_M)
		_adopt(mi, "aura_mark")
		_marks.append({"u": u, "node": mi, "t": 0.0})


func mark_count() -> int:
	var n := 0
	for m in _marks:
		if is_instance_valid(m.get("node", null)):
			n += 1
	return n


# ══════════════════════════════════════════════════════════════════
#  §每帧推进 —— 全部走 sim 的 delta, 一个 tween 都不用(CLAUDE.md §3.5)
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	if not _has_world():
		clear_all()
		return
	var d: float = maxf(delta, 0.0)
	# 甲片环: 跟随携带者 + 亮度指数衰减
	var ks: Array = []
	for h in _scutes:
		var u = h["u"]
		if not (u is Dictionary) or not u.get("alive", false):
			var r0 = h["root"]
			if is_instance_valid(r0):
				r0.queue_free()
			continue
		var root = h["root"]
		if not is_instance_valid(root):
			continue
		root.position = battle._world_pos(u["pos"], GROUND_Y)
		var decay: float = exp(-d / PLATE_TAU)
		var floor_a: float = PLATE_A * PLATE_FLOOR_FRAC
		var alphas: Array = h["a"]
		for k in range(alphas.size()):
			## ★衰减到地板为止, 不衰到 0 —— 甲片环是常驻物件, 脉冲只是往上加亮
			alphas[k] = maxf(floor_a, float(alphas[k]) * decay)
			var mi = (h["plates"] as Array)[k]
			if is_instance_valid(mi):
				(mi.material_override as StandardMaterial3D).albedo_color = Color(
					COL_SCUTE.r, COL_SCUTE.g, COL_SCUTE.b, float(alphas[k]))
		h["a"] = alphas
		ks.append(h)
	_scutes = ks
	# 回复脉冲波
	var kw: Array = []
	for w in _waves:
		w["t"] = float(w["t"]) + d
		var uu: float = float(w["t"]) / WAVE_LIFE
		if uu >= 1.0 or not is_instance_valid(w.get("node", null)):
			var wn = w.get("node", null)
			if is_instance_valid(wn):
				wn.queue_free()
			continue
		apply_wave(w, uu)
		kw.append(w)
	_waves = kw
	# 回复微粒
	var kmo: Array = []
	for m in _motes:
		m["t"] = float(m["t"]) + d
		if float(m["t"]) >= MOTE_LIFE or not is_instance_valid(m.get("node", null)):
			var mn = m.get("node", null)
			if is_instance_valid(mn):
				mn.queue_free()
			continue
		apply_mote(m, float(m["t"]))
		kmo.append(m)
	_motes = kmo
	# 碑: 升起 + 符环自转
	for h in _steles:
		advance_stele(h, d)
	# 在途石块
	var kr: Array = []
	var kt: Array = []
	for h in _thunders:
		h["t"] = float(h["t"]) + delta
		var lf: float = float(h.get("life", THUNDER_LIFE))
		if float(h["t"]) >= lf or not is_instance_valid(h.get("node", null)):
			var hn = h.get("node", null)
			if is_instance_valid(hn):
				hn.queue_free()
			continue
		apply_thunder(h, float(h["t"]) / maxf(lf, 1e-4))
		kt.append(h)
	_thunders = kt
	for b in _rocks:
		b["t"] = float(b["t"]) + d
		var tt: float = float(b["t"]) / maxf(float(b["T"]), 0.001)
		if tt >= 1.0:
			var bn = b.get("node", null)
			if is_instance_valid(bn):
				bn.queue_free()
			_blast(b["pos"], COL_BOLT)
			continue
		apply_bolt(b, tt)
		kr.append(b)
	_rocks = kr
	# 头顶印记: 跟随 + 缓慢起伏(受迫振子的稳态解 —— 纯正弦, 不是随手加的抖动)
	var km: Array = []
	for m in _marks:
		var u = m["u"]
		var mi = m.get("node", null)
		if not (u is Dictionary) or not u.get("alive", false) or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			continue
		m["t"] = float(m.get("t", 0.0)) + d
		var bob: float = MARK_BOB_M * sin(TAU * MARK_HZ * float(m["t"]))
		mi.position = battle._world_pos(u["pos"], MARK_H_M + bob)
		km.append(m)
	_marks = km
	# 爆点
	var kb: Array = []
	for h in _shocks:
		if _shock.advance(h, d):
			kb.append(h)
			continue
		for k in ShockwaveVfx.NODE_KEYS:
			var n = h[k]
			if is_instance_valid(n):
				n.queue_free()
	_shocks = kb


# ══════════════════════════════════════════════════════════════════
#  §撤场
# ══════════════════════════════════════════════════════════════════

## free 掉本层建出来、还活着的所有节点; 返回真的 free 掉几个。
## ★句柄表也要清 —— 只 free 节点不清表, 下一帧 tick() 会拿着已 free 的句柄继续推
##   (memory [[fb-write-without-reader-and-fake-gates]] 的另一半)。
## ★网格缓存一并放掉: 不放的话进程退出时 Godot 报
##   `RID allocations of type DummyMesh were leaked at exit`(spirit_eq_vfx.gd:828 记的坑)。
func clear_all() -> int:
	var freed := 0
	for n in _owned:
		if is_instance_valid(n):
			n.queue_free()
			freed += 1
	_owned.clear()
	_scutes.clear()
	_waves.clear()
	_motes.clear()
	_steles.clear()
	_rocks.clear()
	_thunders.clear()
	_marks.clear()
	_shocks.clear()
	_m_hex = null
	_m_ring = null
	_m_hexv = null
	_m_plates = null
	# ★连 `_shock` 的三个网格缓存一起放 —— 它是**本层 new 出来的**实例, 生命周期归本层。
	#   实测: 不放的话进程退出刷 `3 RID allocations of type DummyMesh were leaked at exit`
	#   (对照组 verify_synergy_vfx 没有这三条 —— 它没触发过 make_blast, 缓存压根没建)。
	#   这条不在 run-tests.sh 的 FATAL 正则里、不会红门禁, 但它是真的在漏。
	if _shock != null:
		_shock._cache_shell = null
		_shock._cache_ring = null
		_shock._cache_dust = null
	return freed


## 本层还活着的节点数(kind 为空 = 不筛类型)。门禁/调试用。
func alive_count(kind: String = "") -> int:
	var n := 0
	for x in _owned:
		if not is_instance_valid(x):
			continue
		## ★`queue_free()` 是**延迟**的 —— 同一帧里 `is_instance_valid` 仍然为 true。
		##   不排掉它, "收掉了吗"这类断言会读到已经判死的节点(2026-08-08 在 090
		##   的预警圈上栽过一次: 明明收了, 门禁读出"还在")。
		if (x as Node).is_queued_for_deletion():
			continue
		if kind != "" and str(x.get_meta(META_KEY, "")) != kind:
			continue
		n += 1
	return n
