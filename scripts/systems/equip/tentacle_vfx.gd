class_name TentacleVfx
extends RefCounted
## 灵物【触手】演出 —— **常驻实体 + 状态机**（2026-08-04）
##
## ══════════════════════════════════════════════════════════════════════
##  ★这一版改的是【它是什么】，不是【它长什么样】
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-04：「我为什么让你参考？」
##
## 我前两版把「参考俄洛伊」当成**照着画一条触手**在用（拿配色、拿形状、拿纹路），
## 做出来的是「每 5 秒凭空冒一条出来拍一下就没了」。**那是技能特效，不是一个存在。**
##
## 俄洛伊触手真正的设计是 —— 它**长在地上、一直在那儿**：
##   · 出土要 **2 秒**且期间不可选中 → 那 2 秒不是动画，是**给对手的预告**
##   · 有**待机态**（蛰伏）与**唤醒态**，攻击只是它的一个动作
##   · 所以玩家会**数**：这片区域有几根 = 这里有多危险
##
## ⇒ 本版：**每根触手一个常驻节点**，从出土活到换路，由状态机驱动。
##   文案写的是「N 个无敌触手**登场**」——"登场"意味着它在场上，
##   不常驻的话这四个字玩家永远读不到，后面画得再好也是给错的东西上妆。
##
## ── 时间节点（★取自 Riot 官方数值，不是我编的）──────────────────────
## | 出土 | **2 秒**（`wiki:Illaoi` "Tentacles fully spawn after a 2 second delay"）|
## | 唤醒/立起 | **0.25 秒**（"The Tentacle awakens over 0.25 seconds"）|
## | 一次攻击 | **0.5 秒**出手 + **0.5 秒**锁定（大招态原文）|
## | 连续攻击间隔 | 上次攻击后 **0.25 秒** |
##
## ⚠ 我们的触手是**每 5 秒拍一次的常驻 AOE**，不是"生成后被英雄唤醒"的实体。
##   照搬 2 秒出土会占掉 40% 周期 ⇒ **2 秒出土只在【登场】用一次**，
##   之后每次拍击走 `0.25 立起 + 0.5 出手`。
##
## ── 外观 ────────────────────────────────────────────────────────────
##
## ★★★2026-08-04【下载视频逐帧看之后的第 N 次修正 —— 也是最重要的一次】
##
## 用户：「我老早跟你说去抓视频，下载一帧帧看，你还要等我干什么」
## —— 我一直卡在"我解码不了视频"这句话上，**却没试过下载 + 抽帧**。
##    装 `yt-dlp` + `imageio-ffmpeg`，抽成 PNG，我就能看。这条路我早该走。
##
## 抽帧看完发现：**原画和实机是两个东西**，我之前照着原画做的方向是偏的。
##
## | | 原画 `ref-tentacle-illaoi.png` | **实机** `ref-tentacle-ingame.png` |
## |---|---|---|
## | 颜色 | 饱和翠绿 `#20c050` | **淡青绿、半透明**，能看到背后地形 |
## | 回纹 | 醒目的方折刻纹 | **几乎看不见**（那是原画的艺术加工） |
## | 形状 | S 形 + 梢端卷成整圈 | **平缓单弧**，梢端只是向下弯回收细 |
## | 粗细 | 较粗 | **很细**（宽约长的 1/15） |
##
## ⇒ 用户要的是「**参考视频**」，所以按**实机**来：淡青绿半透明 · 细 · 平缓单弧 ·
##   回纹极弱（只在近处隐约可见）· 攻击时才爆发亮光（实机待机是暗的、出手才亮）。
##
## 原画那份仍然有用 —— 它给了**回纹这个母题**与配色的方向；只是强度要按实机压下来。
##
## ── 技术路线 ────────────────────────────────────────────────────────
## 程序化 `ArrayMesh`（`SurfaceTool` 现算），不导 `.glb`：实跑核实本仓库
## **0 个模型文件 / 0 个 Skeleton3D / 0 个 AnimationPlayer**；而地图那三处
## （礁石/墙/穹顶）本来就是现算网格（`battle_world_builder.gd:710,742`）。
## 另一个好处：**程序化不产出图片，不吃「素材不许复用」那条铁律**。
##
## ⚠ 朝向坑：`Sprite3D.axis = AXIS_Y` 本身就是平铺，再 `rotation.x = -90` 会掰成竖环。
##   本文件不用 Sprite3D，直接建 `ArrayMesh` 顶点（世界坐标），没有那层歧义。

const VfxTex := preload("res://scripts/util/vfx_textures.gd")

var battle

# ── 状态 ──────────────────────────────────────────────────────────
## ★ST_WARN 追加在【末尾】(=6)，不插进中间 —— 现有门禁按数字比状态(0..5)，插中间全错位。
enum { ST_EMERGE, ST_IDLE, ST_REAR, ST_SLAM, ST_RECOVER, ST_RETRACT, ST_WARN }

## 各态时长（秒）。EMERGE / REAR / SLAM 三个取自官方数值，见文件头。
const T_EMERGE := 2.0
## ★★★以下三个时长【逐帧量出来的】(W 技能预览 `ImiPef9gzoE` 2.2~4.2s @30fps)：
##   2.80s  爆发 —— **2 帧内(≈0.07s)猛地伸直** + 命中点白色爆闪
##   2.87~3.20s  **保持一条笔直的粗光带**(0.33s)，亮度是待机的好几倍
##   3.20~3.40s  变细变淡
##   3.40~3.53s  收回弯曲 → 回 idle
## ⇒ **不是"抬起来砸下去"，是【蜷缩 → 瞬间弹射成直光带 → 保持 → 收回】。**
##   我原来做的 0.25 前摇 + 0.5 砸下是慢动作，跟实机的爆发感完全不是一回事。
## ══════════════════════════════════════════════════════════════════
##  ★★★2026-08-04【第二次逐帧重看，用户指出我漏了整整一大段】
## ══════════════════════════════════════════════════════════════════
## 用户：「08 的时候 W 命中，09 出现预警，一直到 075 才回到 idle，不是吗？」——**是的**。
##
## 我前一版只看了 f035~f062 那 0.9 秒，把 f040 当成动作起点。
## 把 f001~f080 全铺开才看到：**动作从 f008 就开始了，全长 2.23 秒**。
## 而且我两次说过"LoL 这里没有地面预警区"，**两次都是错的** ——
## f009 起有一条宽的淡青斜带，从触手一直穿过目标，亮到 f040 拍击为止。
##
## 用干净采样窗（预警带路径上、避开两根触手）量出来的包络：
##   f001~f008  基线（−20.7，草地暖色）
##   **f009     +26.9  ← 亮起那一帧【闪一下】，是稳定值的 2 倍**
##   f010~f039  +12.5~+15.7 稳定持续（±12% 起伏 = 有流动感）
##   f040       +72.2  ← 拍击
##   f042       +93.6  峰值
##   f060 之后  回基线
##
## ── 完整时间轴（30fps，以 W 命中 = t0）───────────────────────────
## | 预警 | f009~f039 | **1.00 秒** | 带亮起(首帧闪) + 触手长大→立柱→梢端卷钩→回落 |
## | 前摇 | f036~f039 | 0.13 秒 | 触手再次长大（叠在预警末尾） |
## | 拍击 | f040~f055 | 0.50 秒 | 一帧抽直 + 余振 + 淡出 |
## | 收回 | f056~f075 | 0.67 秒 | 长尾回 idle |
const T_WARN := 1.00
const T_REAR := 0.13                 # 前摇极短：只是微微后缩蓄力
const T_SLAM := 0.50                 # 伸直(前 0.07s 完成) + 保持 —— 官方保持 500ms+
const T_RECOVER := 0.67              # 收回
const T_RETRACT := 0.6
## 【转移阵地】重新破土的时长。比【登场】的 2 秒短 —— 登场那 2 秒是一次性预告，
## 搬家每局要发生好几次，2 秒会让触手大半时间待在地里。
const T_EMERGE_MOVE := 1.0
## 闪避追击用的短促点刺（不立起、不预告）
const T_JAB := 0.30

# ── 形状 ──────────────────────────────────────────────────────────
##
## ★★2026-08-04【自截图看出来的第三次认错】：
##   我从参考图里读出"扁带状截面"，做出来是**一条挂着的缎带**，拍击时变成
##   **横躺过去的香蕉**。原因是 —— **参考图是 2D 插画，我看到的是【侧面轮廓】，
##   而真实结构是【锥体】。** 同一个错误我犯了三次（配色/形状/截面），
##   全都是"把 2D 呈现当成 3D 结构"。
##
## ★★第二个根本错误：拍击被我做成了**沿地面伸长**（`reach` 把它拉向目标）。
##   真触手**根部不动、总长固定**，形态只靠**弯曲角度**变 —— 像鞭子/手臂。
##   ⇒ 改成【固定弧长 + 沿切角积分】：
##      p(0) = 根部；逐段 p += (cos θ·前 + sin θ·上) · ds
##      θ(u) 由状态机给：待机前倾下垂、蓄势竖直后仰、砸下整条前倒。
##      这样长度天然守恒，看起来才像一根真的触手在动。
const SEG := 36
## 截面边数。★8 那版并排比对时**看得见多边形棱面**（轮廓是折的不是圆的）。
const RING := 7                      # 扁带横向的采样点数（不再是圆周边数）
## ★★★【官方被动预览 `ref-tentacle-passive.png` 逐帧看出来的】体型完全反了 ——
##   我做的是**细长鞭子**，实机被动是**粗壮矮胖**：根部占很大面积、总高约等于总宽。
##   （之前照的是 Q 技能与原画 —— 那两个确实是细长的鞭状能量体；**被动不是**，
##     被动是一根有体积的实体触手。同一个英雄，三种形态，我一直在照错的那两种。）
## ★★绝对尺寸砍到 ~1/3 —— 放大对比图看：官方是**细带**，我的是**粗管**，
##   画面占比差好几倍。之前那个 `thickness-ratio .120 vs .115-.140` 是
##   【带宽 ÷ 长度】的**相对值**，我的长度也短，所以比值对上了、绝对尺寸完全不对。
##   典型的"指标绿了但东西不对"。
## ★★2026-08-04【像素量出来的，不是眼睛看出来的】：
##   官方 SLAM+3 帧 `wfull/041` 横切带宽归一 **0.0286×画面宽**、青像素覆盖 **7.18%**；
##   我上一版 0.0195 / 4.48% —— **窄了 32%**。
##   （上上版是"太粗的白管"，这一版矫枉过正成了"发丝"。两次都是没量就调。）
## ★★2026-08-04 射程 583→400 之后粗细没跟着缩，实测粗细比 0.138 vs 官方 0.103
##   ⇒ 触手变"矮胖"。R_BASE/R_TIP 同比 ×0.75。
const R_BASE := 0.85
const R_TIP := 0.212                 # 梢端半径
## ★总弧长固定 —— 不随目标距离变。这是"它是一根实体"的关键。
const ARC_LEN := 3.25                 # 待机时的弧长（实机被动"粗但有高度"）
## ★前摇【长大】的倍率 —— 官方前摇 5 帧投影臂长 0.097→0.167（+72%）、青覆盖 +76%。
##   做成常量是为了让门禁上限跟着它走（门禁量的仍是**真实网格弧长**，不是这个数）。
const REAR_GROW := 2.15
## 带宽包络的峰值倍率 —— 标定值：1.36 时实测带宽 0.0510，官方峰 0.0508
const W_PEAK := 1.36

# ══════════════════════════════════════════════════════════════════
#  ★★★官方拍击的【逐帧包络表】—— 手调系数换成照抄曲线
# ══════════════════════════════════════════════════════════════════
## 用户 2026-08-04：「我回来验收要看到所有节奏和每个时间点的形状和视频里的一模一样」。
##
## 我之前一路在【手调系数】（0.07s 抽直 / lerp 1.62→0.86 / pow(cp,2.4) …），
## 逐帧一比就发现手调补不出真实曲线的形状 ——
## 最典型的是官方在 **+2 帧有个二次峰**（臂长 0.435 → 0.354 → **0.417**，
## 鞭子甩出去之后的**余振**），任何单调缓动都做不出来。
##
## ⇒ 直接把官方 `wfull` 从拍击起始帧（f040）往后 30 帧的
##   **投影臂长 / 带宽**量出来、除以各自峰值，做成两张 30fps 的表。
##   （量法与门禁同口径：青色掩膜 → 最大连通域 → 距离变换取脊线宽 + PCA 主轴长）
##
## ⚠ 表是**相对值**：绝对尺寸仍由 `ATTACK_LEN`(玩法射程) 决定，不照抄官方的绝对长度 ——
##   官方那条投影短 19%，但那是 LoL 相机的事；照抄会让触手够不到射程边缘的敌人。
##   **这里复刻的是节奏与形状，不是像素尺寸。**
const SLAM_LEN_CURVE := [
	1.000, 0.813, 0.958, 0.932, 0.806, 0.791, 0.799, 0.795,
	0.807, 0.756, 0.751, 0.564, 0.557, 0.501, 0.511, 0.536,
	0.516, 0.475, 0.448, 0.406, 0.381, 0.377, 0.351, 0.346,
	0.335, 0.323, 0.313, 0.306, 0.292, 0.286, 0.284, 0.290,
	0.303, 0.313, 0.319, 0.321,
]
## 带宽包络。★注意 [0] < [2] —— 官方**甩出去那一瞬间是细的，之后才鼓起来**。
const SLAM_W_CURVE := [
	0.780, 0.953, 1.000, 0.996, 0.827, 0.742, 0.582, 0.567,
	0.570, 0.538, 0.518, 0.553, 0.567, 0.581, 0.589, 0.590,
	0.564, 0.588, 0.556, 0.548, 0.545, 0.532, 0.506, 0.507,
	0.489, 0.467, 0.454, 0.456, 0.431, 0.414, 0.410, 0.418,
	0.412, 0.398, 0.392, 0.405,
]
## 表是 30fps 一格；ts 是【从拍击起始算起】的秒数（RECOVER 要加上 T_SLAM）
static func _env(c: Array, ts: float) -> float:
	var x: float = maxf(ts, 0.0) * 30.0
	var i: int = int(floor(x))
	if i >= c.size() - 1:
		return float(c[c.size() - 1])
	return lerpf(float(c[i]), float(c[i + 1]), x - float(i))
## ★★攻击伸长到的长度 —— **固定值**（用户 2026-08-04：
##   「俄洛伊触手的攻击长度是固定的，不会随目标距离改动」）。
##
##   我中途做过一版"按到目标的实际距离伸长"，那是错的：
##   固定长度意味着触手有**明确的攻击范围** —— 玩家能学会"站在这条线外就安全"，
##   而"够多远伸多远"等于没有范围，也就没有博弈。
##   ⇒ 攻击时一律伸到 `ATTACK_LEN`，够不够得着由**逻辑侧的选靶**决定
##     （范围外的敌人根本不该被选为目标）。
## ★★2026-08-04 用户拍板缩短：原 14.0 → 战场 2D 码 **583**，实测
##   = 战场【高度】的 80% / 比全场最远的远程龟(450)还远 30% / 中位近战龟(70)的 8.3 倍。
##   那个数是我按"演出好看"反推的，从没按玩法平衡定过。缩到 ~400 ≈ 远程龟档位。
## ⚠ `ARC_LEN` 必须同比缩 —— 不缩的话恢复期包络尾巴(0.29×peak)会被
##   `maxf(reach*env, ARC_LEN)` 钳掉，长尾就没了。
const ATTACK_LEN := 9.6
## 同一个范围换算成【战场 2D 码】给逻辑侧用（在 `_init` 里按真实缩放量一次）
var attack_range_2d := 520.0
## 各态的切角（度）：[根部角, 梢端角]。90° = 竖直向上，0° = 水平向前，负 = 朝下
## ★★★2026-08-04【逐帧量官方 f001~f007 之后推翻重做】
##   我原来做的是"卷成环 ⇄ 舒展成波浪长条、周期 2.4 秒的大幅呼吸" —— **编的**。
##   官方真待机实测：**矮而扁的小土堆**，宽高比 **1.3~1.5（宽 > 高）**、
##   最高点只到画面 **0.149**、而且**几乎不动**（7 帧标准差 < 1.5%）。
##   （之前当成 idle 的 f076~f105 其实是"回收动作的收尾"——
##     钩子→炸开→摊平水洼，一次性阻尼过冲，不是循环。）
## ★★★2026-08-04【用户提醒"上面那根一起看"之后的再修正】
##   官方画面里有两根：**下方那根被俯角压扁**（宽高比 1.4~1.7，看着像一坨），
##   **上方那根离相机远、畸变小，宽高比 0.55~1.14（接近方/偏立）**——
##   它才反映真实 3D 形状。我上一版照的是被压扁那根 ⇒ 把"投影的假象"当成了形状。
##   （用户原话：「这样在下面触手以俯视角缩成一团时可以看上面吊顶」。）
const ANG_IDLE := [79.0, 30.0]       # 待机: 升起后大幅弧过去（牧羊杖形，靠角度不靠螺旋）
## ★★2026-08-04【逐帧曲线抓到的】：[104, 88] = 近乎【笔直站立】，
##   而本作是俯角相机 ⇒ 竖直方向被压扁，**越立投影越短**：
##   实测前摇 −3→−2 投影臂长 0.134 → 0.085（塌了 37%），而官方是 0.167（在长）。
##   官方那个形状是**后仰 + 梢端回勾的「?」形立环**，在屏幕上占得高又占得长。
const ANG_REAR := [92.0, 108.0]      # 蓄势: 后仰 + 梢端回勾成【张开的】环
## ★砸下：根部保持较立（58°）、梢端扎到地里（−80°）——
##   【自截图看出来的】根部倒到 30° 时整条【平躺】在地上，像一条海带，
##   而参考里是"根立着、梢抽下来"的一道弧。差别就在根部这个角。
## ★攻击姿态：**整条笔直地指向目标**（不是弧）。
##   逐帧看到的就是"一条从根部斜插到目标身上的粗光带"。
##   根部略抬、梢端略低 = 一条几乎直的斜线。
const ANG_SLAM := [26.0, 14.0]
const ANG_EMERGE := [90.0, 86.0]     # 出土: ★近乎竖直的一道光柱（实机就是这样起的）
## 梢端打卷：最后这一段额外多转的角度（度）
## ★★【探针算出来的 bug】: 原来 CURL_EXTRA 是恒定 210°，于是砸下时
##   梢端 = −78° − 210° = **−288° ≡ +72°**，又转回朝上 —— 卷曲和砸下互相抵消，
##   12 帧自截图看下来姿态几乎没变。
##   ⇒ 卷曲量改成**随状态变**：待机卷紧(蓄势)、砸下时【松开甩直】。
##     这也符合参考：俄洛伊触手蛰伏时卷着，砸下去是抽直的。
## ★卷曲起点：0.42 那一版【自截图实测】从中段就卷，整条没机会长高，
##   看着像只虾。实机是**先立起来一段、再在上半段卷成钩**。
## ★★★2026-08-04【卷不出 C 形钩的根因】
##   官方预警期 f016~f023 是一个**开口很大的 C 形钩**（顶端弯回来接近根部高度）。
##   0.68 意味着**只有上段 32% 参与卷曲** —— 剩下 68% 是直的，
##   再大的 `curl` 也只能在梢端勾一小下，弯不出一个 C。
##   ⇒ 改成【按状态分】：待机/预警从 0.30 就开始卷（大半条参与，才成 C）；
##     拍击仍是 0.68（那时它要绷直，只有梢端稍勾）。
const CURL_FROM := 0.68              # 拍击：上段三分之一才回勾
const CURL_FROM_CURLY := 0.30        # 待机/预警：大半条参与卷曲，才能弯成 C
## ★★★待机的卷曲量 —— 【逐帧看 idle 段】之后的第三次修正：
##   它不是一个固定值，而是**周期性呼吸**的。
##   官方 idle（`baYW1HaSbRU` 5.6s~9.5s，30fps 逐帧看完）里触手在：
##     **卷成 "9" 字环（≈330°）** ⇄ **舒展成向上斜伸的波浪长条（≈70°）**
##   之间来回，周期约 2.4 秒。这是个**大幅度**的动作，不是我原来做的"轻微摇曳"。
##   （我先做 250° → 看单张静止图改成 120° → 看动画才发现两个都不对：
##     它两个姿态都会经过。静止图只能告诉你某一瞬间。）
## ★呼吸幅度砍到 1/6 —— 官方待机 7 帧标准差 < 1.5%，肉眼几乎看不出在动。
##   原来 330 ⇄ 70 那种大幅摆动是我编的，画面上像条活鳗鱼。
## ★★★重标定：`CURL_FROM` 从 0.68 降到 0.30 之后，参与卷曲的长度从 32% 变成 70%，
##   **同样的数值卷曲量翻了一倍多** —— 原来的 318/299 在新口径下会把整条盘成蚊香
##   （实测 +13~+22 那几帧就是一坨旋涡）。整条曲线的 curl 值全部按新口径重定。
const CURL_TIGHT := 116.0            # 待机：细长立柱 + 梢端弯钩
## ★立起来(ANG_IDLE 66→79)之后，同样的摆幅在投影上被放大：实测波动
## 从 1.2% 跳到 10.6%（官方 <1.5%）⇒ 摆幅再砍一半。
const CURL_LOOSE := 101.0            # 舒展到底：只松一点点（官方待机基本不动）
const BREATH_PERIOD := 3.6           # 一次完整呼吸的秒数（慢而轻）
const CURL_SLAM := 6.0               # 攻击: ★完全抻直（逐帧看是一条直光带）
## 待机摇曳的横向摆幅（度）
const S_AMP := 3.5                   # ★实机摆得很轻, 原画那种 S 形是艺术加工
## 梢端相位滞后（鞭子感 —— 整条一起动就是根棍子）
const LAG := 0.26
## 待机摇曳
const SWAY_SPEED := 1.15
const SWAY_AMP := 0.30

# ── 配色（★参考图逐像素统计，不是我挑的）────────────────────────────
## ★色相取自【实机视频】抽帧（`#205040`~`#408070` 那一带的青绿），
##   但**明度/饱和度按【我们自己的背景】调过** ——
##   ⚠ 照搬实机数值那一版【自截图实测几乎看不见】：LoL 的场景是暗绿褐色，
##     而本作战场是一大片**亮青色**，同样一条淡青绿在上面直接糊掉。
##   ⇒ 参考给的是【色相与关系】（青绿、边缘微亮、待机暗出手亮），
##     不是能照抄的 RGB。压暗主体 + 提高与背景的明度差，才读得出轮廓。
const C_CORE := Color(0.09, 0.40, 0.42)      # 主体：压暗的【青】（官方偏 cyan，我原来偏绿）
const C_EDGE := Color(0.42, 0.92, 0.94)      # 边缘亮青
const C_GLYPH := Color(0.34, 0.72, 0.64)     # 回纹（弱，近看才见）

## 回纹：1 = 亮刻痕。BAND 列 × 8 行一循环，沿长度平铺。
## ★方折的阶梯/迷宫纹（参考图上那种直角折线纹样），不是随便的亮条。
const GLYPH := [
	[0, 1, 1, 1, 0],
	[0, 1, 0, 0, 0],
	[0, 1, 0, 1, 1],
	[0, 1, 0, 1, 0],
	[0, 0, 0, 1, 0],
	[1, 1, 0, 1, 0],
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
]

## 待机态的重算节流：摇曳很慢，不必每帧重建网格（4 根 × 320 面是每帧开销）
const IDLE_REBUILD_HZ := 12.0

## 常驻触手：key = "side|idx" → 状态字典
var _tents: Dictionary = {}
## 本帧正在重建的这根触手是不是攻击态 —— 攻击时辉光放大 2 倍(官方整条在发光)
var _halo_hot := false
## 【调试台专用】锁住根数：预览自己 ensure 之后，别让 `spirit_synergy_system` 每帧
## 按真实档位把它撤掉（真实档位在调试台里是 0）。只有 VFXPREVIEW 会打开它。
var preview_lock := false
## 表皮贴图（只生成一次，全部触手共用同一张 —— 这是【同一个东西的同一张皮】，不是复用别的素材）
static var _skin_tex: ImageTexture = null


static func _skin() -> ImageTexture:
	if _skin_tex == null:
		_skin_tex = VfxTex._make_tentacle_skin()
	return _skin_tex


func _init(b) -> void:
	battle = b
	# ★量一次"1 个战场 2D 码 = 多少世界米"，把固定攻击长度换算成逻辑侧能用的 2D 范围。
	#   不写死数字 —— 相机/缩放改了这里会自动跟上。
	var a3: Vector3 = battle._world_pos(Vector2.ZERO, 0.0)
	var b3: Vector3 = battle._world_pos(Vector2(100.0, 0.0), 0.0)
	var per_yard: float = a3.distance_to(b3) / 100.0
	if per_yard > 0.0001:
		attack_range_2d = ATTACK_LEN / per_yard


func _key(side: String, idx: int) -> String:
	return "%s|%d" % [side, idx]


## 让某方场上恰好有 n 根触手（多了撤场、少了出土）。每帧由 spirit 系统调。
## ★这是"登场"那一段 —— 不调它，触手永远不存在。
## 【调试台专用】把某根触手的根部直接挪到指定点（不走钻地演出）。
func set_root(side: String, idx: int, to2: Vector2) -> void:
	var k: String = _key(side, idx)
	if _tents.has(k):
		(_tents[k] as Dictionary)["root"] = to2


## 【调试台专用】绕过 preview_lock 强制摆一根 —— 只有预览会调。
func ensure_forced(side: String, n: int) -> void:
	var lk: bool = preview_lock
	preview_lock = false
	ensure(side, n)
	preview_lock = lk


func ensure(side: String, n: int) -> void:
	if preview_lock:
		return
	for idx in range(4):
		var k: String = _key(side, idx)
		var has: bool = _tents.has(k)
		if idx < n and not has:
			_spawn(side, idx)
		elif idx >= n and has:
			var t: Dictionary = _tents[k]
			if int(t["state"]) != ST_RETRACT:
				t["state"] = ST_RETRACT
				t["ts"] = 0.0


## 根部的光花：官方被动里触手立在地上时，根部一直有一圈溅开的微光。
## 没有它，触手看着像"插在地上的棍子"而不是"从地里钻出来的活物"。
func _base_glow(t: Dictionary) -> void:
	var p2: Vector2 = root_pos(str(t["side"]), int(t["idx"]))
	battle._skill_ring(p2, Color(0.42, 0.95, 0.86, 0.22), 46.0)


func _spawn(side: String, idx: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Tentacle_%s_%d" % [side, idx]
	mi.mesh = ArrayMesh.new()
	var mat := StandardMaterial3D.new()
	# ★unshaded + 加色 + 半透明 —— 参考图上触手是【能看到背后城镇的发光能量体】。
	#   开光照会有连续明暗渐变，跟限色像素立绘立刻打架。
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ★★不能用 BLEND_MODE_ADD ——【自截图实测】：加色混合叠在本作那片【亮青色】战场上
	#   直接爆成白色，画面上看到的是一条白影，一点绿都没有。
	#   参考图上触手之所以是绿的，是因为它【本体接近不透明】、只有边缘发光；
	#   叠加混合只适合暗背景。⇒ 用普通 alpha 混合，亮边靠顶点色做。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# ★★这里【必须双面】(2026-08-04 试过单面, 实测更差)：
	#   本体是半透明的能量体，远壁透过近壁叠加正好给出"体积感"——
	#   单面(CULL_FRONT)实测变成一根【空心管】：亮轮廓 + 暗芯，
	#   峰值从 220 掉到 199(官方 236)、均值 173→160。数字和眼睛一致。
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	# ★★回纹用【贴图】不用顶点色 ——【自截图实测】36×8 的网格上，一个格子在屏幕上才几像素，
	#   顶点色插值出来是一片糊，参考图上最有辨识度的方折回纹**一点都看不见**。
	#   贴图是逐像素画的（`VfxTex._make_tentacle_skin`），不复用任何现成图。
	# ★★2026-08-04：贴图关掉过一轮（管体时代那几条丝变成了【接缝线】）。
	#   扁带定型后并排看，"没有贴图"暴露了新问题：官方那条带**内部有流动的丝缕**，
	#   我是一片纯色渐变 ⇒ 读起来是【霓虹灯管】不是【能量体】。
	#   ⇒ 换一张**专给扁带画的**流纹（`_make_tentacle_flow`，只当亮度倍率，
	#     横向不画任何明暗——横向渐隐已由顶点 alpha 负责）。
	mat.albedo_texture = VfxTex._make_tentacle_flow()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素风：不做双线性
	# ★不再平铺 —— 平铺 3 遍 + 密环纹 = 毛线织物（并排比对时最刺眼的问题）
	# 沿长度平铺 3 遍（贴图 Y 向无缝），配合 tick 里滚 uv1_offset.y = 能量往梢端流
	mat.uv1_scale = Vector3(1.0, 3.0, 1.0)
	# 实机是半透明的能量体。本作背景亮 ⇒ 不能照抄实机的 0.72（那版糊掉），
	# 但 0.90 又太"实"（并排比对像塑料）。0.80 + 更强的边缘光是折中点。
	# ★RGB 抬到 1.3：流纹贴图均值 ≈0.78，直接乘上去整条会暗一档。
	mat.albedo_color = Color(1.3, 1.3, 1.3, 0.72)
	mi.material_override = mat
	battle._world.add_child(mi)
	# ★外发光壳：实机触手裹着一层辉光雾，并排对比时我的显得"干"。
	#   做法是同一条曲线再画一遍、半径放大、加色混合、很淡 —— 便宜且有效。
	var halo := MeshInstance3D.new()
	halo.name = "TentacleHalo_%s_%d" % [side, idx]
	halo.mesh = ArrayMesh.new()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.vertex_color_use_as_albedo = true
	hm.albedo_color = Color(1, 1, 1, 0.20)   # 攻击时在 tick 里提到 0.55
	halo.material_override = hm
	battle._world.add_child(halo)
	_tents[_key(side, idx)] = {
		"mi": mi, "halo": halo, "side": side, "idx": idx,
		"state": ST_EMERGE, "ts": 0.0,
		"aim": Vector2.ZERO, "share": 1.0,
		"phase": float(idx) * 1.7,          # 相位错开 → 两根不同步摇
		"acc": 0.0,
	}


## 请求一次拍击：进入蓄势(REAR) → 拍击(SLAM) → 回位。
## `share` 只影响幅度（正常 1.0，闪避追击 0.25 → 走短促点刺）。
## ★伤害【不在这里结算】—— 逻辑侧早就结完了。
##   CLAUDE.md §3.5：一个测数值的用例不该依赖任何动画跑完。
func strike(side: String, idx: int, aim2: Vector2, share: float = 1.0) -> void:
	var k: String = _key(side, idx)
	if not _tents.has(k):
		return
	var t: Dictionary = _tents[k]
	var s: int = int(t["state"])
	if s == ST_EMERGE or s == ST_RETRACT:
		return                                  # 还没站稳 / 正在撤 → 不接指令
	t["aim"] = aim2
	t["share"] = share
	# ★追击走【点刺】（不立起、不预告），正常拍击走【蓄势】——
	#   只有触手常驻，玩家才看得出"是它反应了一下"，所以追击不该复用整套拍击。
	# ★正常拍击先进【预警】(1 秒)，再蓄势 → 拍击。追击(share<0.9)仍走点刺、不预告。
	t["state"] = ST_SLAM if share < 0.9 else ST_WARN
	t["ts"] = 0.0
	t["hit"] = false
	t["warned"] = false


func tick(delta: float) -> void:
	for k in _tents.keys():
		var t: Dictionary = _tents[k]
		t["ts"] = float(t["ts"]) + delta
		var st: int = int(t["state"])
		var ts: float = float(t["ts"])
		# ── 状态转移 ──────────────────────────────────
		match st:
			ST_EMERGE:
				if ts >= T_EMERGE:
					t["state"] = ST_IDLE; t["ts"] = 0.0
					_base_glow(t)          # 出土落定：根部溅一圈光
			ST_WARN:
				# ★预警带在这 1 秒里【一直存在】(官方 f009~f039)，每帧刷亮度包络。
				#   原来是"蓄势开始时画一条线"= 0.13 秒的一闪，等于没有。
				_telegraph_tick(t, ts)
				if ts >= T_WARN:
					t["state"] = ST_REAR; t["ts"] = 0.0
			ST_REAR:
				_telegraph_tick(t, T_WARN + ts)     # 前摇叠在预警末尾，带子还亮着
				if ts >= T_REAR:
					t["state"] = ST_SLAM; t["ts"] = 0.0
			ST_SLAM:
				var dur: float = T_JAB if float(t["share"]) < 0.9 else T_SLAM
				# ★★爆闪放在【伸直完成那一刻】——
				#   时间对齐对比实测：官方是【命中即炸】(0.03s)，我原来放在动作 60%
				#   ⇒ 0.33 秒才响，观感是"打完了才有反馈"。
				#   伸直只要 0.07 秒，所以 0.08 秒就该炸。
				_telegraph_hide(t)                 # 拍下去了，带子撤
				if not bool(t.get("hit", true)) and ts >= 0.08:
					t["hit"] = true
					_impact(t)
				if ts >= dur:
					t["state"] = ST_RECOVER; t["ts"] = 0.0
			ST_RECOVER:
				if ts >= T_RECOVER:
					t["state"] = ST_IDLE; t["ts"] = 0.0
			ST_RETRACT:
				if ts >= T_RETRACT:
					# ★分两种撤场：搬家(有 relocate_to) vs 掉档真撤。
					#   共用同一段钻地演出，只在这里分叉。
					if t.has("relocate_to"):
						t["root"] = t["relocate_to"]
						t.erase("relocate_to")
						t["state"] = ST_EMERGE
						t["ts"] = T_EMERGE - T_EMERGE_MOVE   # 搬家的破土比【登场】快
						t["acc"] = 99.0
						continue
					for kk in ["mi", "halo", "warn_mi"]:
						var n = t.get(kk, null)
						if is_instance_valid(n):
							n.queue_free()
					_tents.erase(k)
					continue
		# ── 重建网格（待机降频）────────────────────────
		t["acc"] = float(t["acc"]) + delta
		if int(t["state"]) == ST_IDLE and float(t["acc"]) < 1.0 / IDLE_REBUILD_HZ:
			continue
		t["acc"] = 0.0
		_rebuild(t)
		# ★攻击时把整条的不透明度也提上去 —— 只改顶点色不够，
		#   0.80 的 alpha 会把"爆亮"稀释掉（对比时看不出明暗落差）。
		var mi2 = t.get("mi", null)
		if is_instance_valid(mi2):
			var mm: StandardMaterial3D = (mi2 as MeshInstance3D).material_override
			if mm != null:
				var sN: int = int(t["state"])
				# ★0.99 那版等于"不透明白板"；官方那条光带**能看到背后的地面和英雄**。
				mm.albedo_color = Color(1.3, 1.3, 1.3,
					0.84 if sN == ST_SLAM else (0.82 if sN == ST_REAR else
					(_warn_alpha(t) if sN == ST_WARN else
					(0.70 if sN == ST_IDLE else 0.80))))
				# ★能量沿长度往梢端流 —— 攻击时流得快（爆发感），待机时缓慢蠕动。
				mm.uv1_offset = Vector3(0.0,
					-battle._t * (1.35 if sN == ST_SLAM else 0.28), 0.0)
		var ha = t.get("halo", null)
		if is_instance_valid(ha):
			var hmm: StandardMaterial3D = (ha as MeshInstance3D).material_override
			if hmm != null:
				# 0.30 那档实测把本体推到 253（官方 ~205）——辉光是"托轮廓"的，不是"加亮度"的
				hmm.albedo_color = Color(1, 1, 1, 0.26 if int(t["state"]) == ST_SLAM else 0.20)


## 外发光壳：同一条曲线放大 2.6 倍再画一遍，加色混合、很淡。
## ★便宜（面数只有本体的 1/2，六边截面）且效果立竿见影 —— 并排对比时"干不干"就差这一层。
## 预警期的不透明度：立钩时最实，**摊平时淡下去**（官方那几帧画面上几乎看不见），
## 蓄力时再回来。
func _warn_alpha(t: Dictionary) -> float:
	var wq: float = clampf(float(t["ts"]) / T_WARN, 0.0, 1.0)
	if wq < 0.27:
		return lerpf(0.70, 0.78, wq / 0.27)
	if wq < 0.53:
		return lerpf(0.78, 0.40, (wq - 0.27) / 0.26)
	if wq < 0.80:
		return 0.40
	return lerpf(0.40, 0.80, (wq - 0.80) / 0.20)


func _rebuild_halo(t: Dictionary, pts: Array, rs: Array) -> void:
	var halo = t.get("halo", null)
	if not is_instance_valid(halo) or pts.size() < 2:
		return
	var hmesh: ArrayMesh = halo.mesh
	hmesh.clear_surfaces()
	_halo_hot = int(t["state"]) == ST_SLAM
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var RN := 7
	var camp := Vector3.ZERO
	var camp_ok := false
	if battle._cam != null and is_instance_valid(battle._cam):
		camp = (battle._cam as Camera3D).global_position
		camp_ok = true
	var prev: Array = []
	for i in range(pts.size()):
		var c: Vector3 = pts[i][0]
		var sv: Vector3 = pts[i][1]
		var uv: Vector3 = pts[i][2]
		# ★★2026-08-04【探针 + 时间对齐对比抓到的真凶】：
		#   上一版 `hk=3.1 / +0.34 / alpha 0.55 / 近白色` 的加色外壳，把整条触手糊成
		#   **一块纯白实心板**（截图里本体的青色一点不剩）。
		#   逐帧量官方 `wfull/041` 的横截面：R 18~108 / G 170~202 / B 140~224 ——
		#   **它整条都是青的**，只有命中点那一小团是白的。
		#   ⇒ 辉光退回"薄薄一层雾"：倍率 1.9、偏移 0.14，只把轮廓托出来，不吃掉本体。
		# ★★2026-08-04【归一化裁切逐帧对照看出来的】：辉光壳占了包围盒一半以上、
		#   糊成一片，官方的辉光是**贴着本体**的一薄层。收敛。
		var hk: float = 1.34 if _halo_hot else 1.16
		# ★★2026-08-04：本体加粗到 R_BASE 0.94 之后，`hk=2.9` 让根部辉光宽到
		#   **4.1 世界单位** ⇒ 截图上是一大片【扇形淡雾】(官方根部是紧凑一团, 没有这个)。
		#   辉光倍率必须跟着本体粗细走 —— 本体越粗, 倍率越要小。
		var r: float = float(rs[i]) * hk + (0.05 if _halo_hot else 0.03)
		# ★★2026-08-04【放大对比抓到的第二只】：本体改成扁带之后，**辉光还在绕环** ——
		#   于是那根细光带外面套着一圈宽的、边界很硬的暗青板（放大图里那个"宽边框"）。
		#   官方那条根本没有"外壳"这个东西，只有【亮芯往两侧化开】。
		#   ⇒ 辉光也必须是朝向相机的扁带，而且**横向 alpha 渐隐**，不能是一块实色。
		var vd: Vector3 = (c - camp).normalized() if camp_ok else Vector3(0, -1, 0)
		var sd: Vector3 = uv.cross(vd)
		if sd.length() < 0.001:
			sd = sv
		sd = sd.normalized()
		var ring: Array = []
		for k in range(RN):
			var f2: float = float(k) / float(RN - 1) * 2.0 - 1.0
			ring.append(c + sd * (f2 * r))
		if not prev.is_empty():
			var f: float = float(i) / float(pts.size())
			# ★梢端不再往白里提 —— 那是并排比对时那个突兀的白点的来源
			# 攻击时辉光【更青、不更白】—— 白是留给命中点的
			var base: Color = (Color(0.24, 0.86, 0.96) if _halo_hot
				else Color(0.26, 0.78, 0.76).lerp(Color(0.40, 0.88, 0.90), f * 0.45))
			for k2 in range(RN - 1):
				var k3: int = k2 + 1
				# 横向渐隐：这两列各自的 alpha（实色 = 硬边框）
				var e2: float = pow(1.0 - absf(float(k2) / float(RN - 1) * 2.0 - 1.0), 1.1)
				var e3: float = pow(1.0 - absf(float(k3) / float(RN - 1) * 2.0 - 1.0), 1.1)
				var c2 := Color(base.r, base.g, base.b, e2)
				var c3 := Color(base.r, base.g, base.b, e3)
				st.set_color(c2); st.add_vertex(prev[k2])
				st.set_color(c3); st.add_vertex(prev[k3])
				st.set_color(c2); st.add_vertex(ring[k2])
				st.set_color(c3); st.add_vertex(prev[k3])
				st.set_color(c3); st.add_vertex(ring[k3])
				st.set_color(c2); st.add_vertex(ring[k2])
		prev = ring
	st.commit(hmesh)


## 命中爆闪：一个朝向相机的发光球，瞬间放大到最亮再收掉。
## ★用 billboard 而不是贴地环 —— 本作是 2.5D 俯角，贴地的东西会被压扁到看不见。
func _flash(pos2: Vector2, scale: float) -> void:
	var sp := Sprite3D.new()
	sp.texture = VfxTex._make_glow_texture()
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# ★★2026-08-04：上一版是【黑底上一个灰球】——柔和径向渐变 + alpha 0.72，
	#   官方那团是**紧凑的白热爆点**（101×84 框里只有 589 个 >195 的白像素，
	#   即"小而极亮"，不是"大而灰"）。⇒ 尺寸砍到 62%、modulate 抬过 1.0 打到过曝、
	#   总时长 0.66→0.47 秒（闪要快）。
	sp.render_priority = 4
	sp.shaded = false
	sp.modulate = Color(1.06, 1.12, 1.14, 0.96)
	sp.pixel_size = 0.0039 * scale
	sp.position = battle._world_pos(pos2, battle.GROUND_LIFT + 0.6)
	battle._world.add_child(sp)
	var tw: Tween = battle._reg_tween()
	# ★★时间对齐对比实测：官方那团白闪从 +2 帧一直亮到 +14 帧（≈0.4 秒）才淡；
	#   我原来 0.09 涨 + 0.46 淡，看起来只是"闪了一下"，命中的分量完全不够。
	#   ⇒ 快涨(0.06) → **保持 0.26 秒** → 再淡 0.34 秒。
	tw.tween_property(sp, "scale", Vector3(1.30, 1.30, 1.30), 0.05).from(Vector3(0.25, 0.25, 0.25))
	tw.tween_property(sp, "scale", Vector3(1.62, 1.62, 1.62), 0.20)
	tw.parallel().tween_property(sp, "modulate:a", 0.62, 0.20)
	tw.tween_property(sp, "modulate:a", 0.0, 0.22)
	tw.tween_callback(sp.queue_free)


## 预警区：蓄势那 0.10 秒里，在地面画出【即将被扫到的那条直线】。
## ★用户 2026-08-04 点名要的（「应该有前摇，预警区，拍下去，命中特效，后摇回到idel」）——
##   我前几版一条都没做。机制上打的是"根部到目标直线上的所有敌人"，
##   没有预警区的话，站在那条线上的玩家没有任何机会反应。
## ★预警区是**以触手为原点、固定长度**的一条线（用户 2026-08-04 两条都点到了：
##   「预警区是根据触手的位置来对吧」「攻击长度是固定的」）——
##   不是"从触手画到目标"。画到目标的话，范围会随目标远近伸缩 = 玩家学不会安全距离。
## ══════════════════════════════════════════════════════════════════
##  预警带 —— 持续 1 秒的贴地扫描带
## ══════════════════════════════════════════════════════════════════
## ★★★2026-08-04 重做。我做过两版，两版都是错的：
##   ① 第一版：`_bolt_line` 一条 alpha 0.32 的发丝，只在蓄势那 0.13 秒画一次 ⇒ 等于没有
##   ② 第二版：三条线拼出宽度，仍然只有 0.13 秒
##   而且我两次断言"官方没有地面预警区" —— **两次都错**。
##   干净采样窗量出来：官方 f009 亮起（**闪一下**，是稳定值的 2 倍）、
##   f010~f039 稳定持续、**整整 1.00 秒**，到 f040 拍击才消失。
##
## ★宽度 = **真实命中通道**（`spirit_synergy_system._slap` 的 `cross(dir) > 40.0`，
##   即半宽 40 码 / 全宽 80）。预警区画得比命中范围宽或窄都是骗人的。
## ★长度 = 固定射程（不是"到目标的距离"）—— 用户 2026-08-04 点过：
##   攻击长度固定，玩家才学得会安全距离。
const WARN_HALF_W := 40.0            # ＝ _slap 的命中半宽，改一处要改两处
## ★★★2026-08-04【第三次重做预警带 —— 前两次的量法都不对】
##   用户：「现在这预警区压根和参考的不沾边」。放大 3.8× 一看确实：
##   官方是**一层极淡的、完全羽化的、偏蓝的雾**（石板缝和草完整可见），
##   我做的是**边界清晰的亮青实心带**，像贴了条胶带。
##
## ★这次量法换成【有带帧 − 无带基线(f003) 的差值】，而不是"偏青度"——
##   后者混进了背景本身的颜色，前两次就是被它带偏的。
##
##   颜色：Δ(R,G,B) = **(−6, +26, +52)** ⇒ **蓝是绿的 2 倍，R 还是负的**。
##         我原来用青绿 (0.38,0.86,0.94)，色相就错了。
##   亮度：峰值 Δ 只有 **+39/255 ≈ 0.15** ⇒ 极淡。
##   包络：**f009 立刻到 0.40 并保持 5 帧 → f014 突起到峰值 → 缓降 → f028 基本消失**，
##         有效时长 **20 帧 = 0.67 秒**（不是 1 秒；也不是我以为的"起始最亮然后单调衰减"）。
##   剖面：中心 ±15px 是主体、羽化到 ±30px，**不对称**（斜带 + 透视）。
const WARN_ENV := [
	0.537, 0.538, 0.540, 0.533, 0.531, 1.000, 0.703, 0.460,
	0.439, 0.439, 0.424, 0.422, 0.411, 0.383, 0.353, 0.329,
	0.159, 0.235, 0.207, 0.138, 0.096, 0.058, 0.033, 0.045,
	0.044, 0.045, 0.037, 0.038, 0.036, 0.030,
]
## 亮核占半宽的比例。官方剖面：中心 ±15px 是主体、±30px 才归零 ⇒ 亮核占一半，其余羽化。
const WARN_CORE_FRAC := 0.48


func _telegraph_tick(t: Dictionary, ts: float) -> void:
	var from2: Vector2 = root_pos(str(t["side"]), int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		_telegraph_hide(t)
		return
	var dir: Vector2 = to2 - from2
	if dir.length() < 1.0:
		_telegraph_hide(t)
		return
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	# ★官方实测：带子**到目标身上就停**，没有穿过去（往远处延伸信号回落到噪声）。
	#   但长度仍**钳在固定射程内** —— 够不着的目标本来就不该被选中。
	var end2: Vector2 = from2 + dir * minf((to2 - from2).length(), attack_range_2d)
	var mi = t.get("warn_mi", null)
	if not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		mi.name = "TentacleWarn_%s_%d" % [str(t["side"]), int(t["idx"])]
		mi.mesh = ArrayMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD    # 贴地淡带，加色才不挡住地面
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		# ★官方实测【贴地】：带子穿过目标腿部时**被腿挡住**，是正常深度排序的地面 decal。
		#   原来开 no_depth_test 会画在最上层 = 浮空贴图，穿帮。
		m.no_depth_test = false
		mi.material_override = m
		mi.sorting_offset = 0.6
		battle._world.add_child(mi)
		t["warn_mi"] = mi
	mi.visible = true
	# 亮度包络：查官方逐帧表（0.8 秒指数衰减 → 稳态）
	var amp: float = _env(WARN_ENV, ts)
	var mm: StandardMaterial3D = mi.material_override
		# 稳态时 amp≈1.0；起始 7.66× 会被 clampf 顶住 → 那正是"一开始很亮然后暗下去"
	# ★标定：顶点色 B=0.95、ADD 混合 ⇒ 屏幕 ΔB ≈ 0.20×0.95×255 ≈ 48（官方 52）。
	mm.albedo_color = Color(1, 1, 1, clampf(0.20 * amp, 0.0, 1.0))
	# 网格：沿方向分 10 段的贴地长条，横向 alpha 渐隐（中间亮、两侧化开）
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# ★★2026-08-04 重写：上一版的 lane 循环写错了（第二片从 HALF_W 画到 0，
	#   和第一片重叠）⇒ **横向根本没有渐隐**，出来是一块边界很硬的实心梯形。
	#   官方那条是【淡淡的、边缘化开的青雾】。
	#   ⇒ 横向按 LAT 段插值，alpha 从中心 1.0 平滑落到边缘 0；
	#     纵向也渐隐（远端更淡 = 能量从根部涌出去）。
	var N := 12          # 沿长度分段
	var LAT := 7         # 横向采样（含中心与两侧边缘）
	var col := Color(0.02, 0.46, 0.95)      # ★量出来的 ΔG:ΔB = 26:52 = 1:2，是【蓝】不是青绿
	var prev_row: Array = []
	for i in range(N + 1):
		var u: float = float(i) / float(N)
		var pc: Vector2 = from2.lerp(end2, u)
		var fade_u: float = (1.0 - u * 0.55)                    # 越远越淡
		var row: Array = []
		for j in range(LAT):
			var f: float = float(j) / float(LAT - 1) * 2.0 - 1.0   # -1..1
			var pos2: Vector2 = pc + perp * (f * WARN_HALF_W)
			# ★官方横向剖面：**亮核半宽只有 ~0.008 归一(≈5px)**，外面才是
			#   0.03~0.04 的一圈很淡软光 —— 不是一整条均匀渐隐的宽带。
			var af: float = absf(f)
			var core: float = clampf(1.0 - af / WARN_CORE_FRAC, 0.0, 1.0)
			# 亮核(±48% 半宽) + 一路羽化到边缘 —— 官方没有硬边界
			var av: float = (pow(core, 1.1) * 0.62 + pow(1.0 - af, 1.5) * 0.38) * fade_u
			row.append([battle._world_pos(pos2, battle.GROUND_LIFT + 0.04),
				Color(col.r, col.g, col.b, av)])
		if not prev_row.is_empty():
			for j2 in range(LAT - 1):
				var a00 = prev_row[j2]; var a01 = prev_row[j2 + 1]
				var a10 = row[j2]; var a11 = row[j2 + 1]
				stool.set_color(a00[1]); stool.add_vertex(a00[0])
				stool.set_color(a01[1]); stool.add_vertex(a01[0])
				stool.set_color(a10[1]); stool.add_vertex(a10[0])
				stool.set_color(a01[1]); stool.add_vertex(a01[0])
				stool.set_color(a11[1]); stool.add_vertex(a11[0])
				stool.set_color(a10[1]); stool.add_vertex(a10[0])
		prev_row = row
	stool.commit(mesh)


func _telegraph_hide(t: Dictionary) -> void:
	var mi = t.get("warn_mi", null)
	if is_instance_valid(mi):
		mi.visible = false


## 落地冲击：贴地冲击环 + 一撮碎屑。
## ★只是演出 —— 伤害早就在逻辑侧结完了（CLAUDE.md §3.5：测数值的用例不该依赖动画）。
func _impact(t: Dictionary) -> void:
	var from2: Vector2 = root_pos(str(t["side"]), int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		return
	var d: Vector2 = to2 - from2
	if d.length() < 1.0:
		return
	# 落点：朝目标方向、触手弧长够得到的地方（总长固定，够不着就落在最远处）
	# ★命中点 = **目标身上**（不是"触手够得到的地方"）——
	#   时间对齐对比里，官方的爆闪是在【目标身上】炸的，而我原来炸在半路。
	# 命中点：目标位置，但**钳在固定射程内**（射程外不该被选为目标，这里只是兜底）
	var hit2: Vector2 = from2 + d.normalized() * minf(d.length(), attack_range_2d)
	var big: bool = float(t["share"]) >= 0.9
	# 大爆闪：三层环 + 两撮粒子。官方那一下持续 0.5 秒以上、亮到发白，
	# 我原来只有一个小环 + 一撮粒子，对比时几乎看不见。
	# ★★爆闪必须是【朝向相机的】—— 探针实测贴地环确实建出来了(+6 节点)，
	#   但这个俯角下它压成一条缝，画面上根本看不见。官方那一下是正对镜头的大白闪。
	# ★6.2 那版把半个屏幕炸成白色（自截图实测）——官方那团白只裹住目标本身。
	_flash(hit2, 3.8 if big else 1.8)
	battle._skill_ring(hit2, Color(0.70, 1.0, 1.0, 0.50), 120.0 if big else 60.0)
	battle._vfx._impact_particles(hit2, 0.0)
	if big:
		battle._vfx._impact_particles(hit2, 0.6)
	# ★沿途那条【直线命中范围】也画出来 —— 机制上打的是"根部到目标直线上所有敌人"，
	#   不画的话玩家永远不知道被扫到的是一条线。
	battle._bolt_line(from2, hit2, Color(0.62, 1.0, 0.96, 0.55))


## 触手的根部坐标（场边固定位，idx 0/1 分上下）。
## ★这是**唯一一份**公式 —— `spirit_synergy_system.tentacle_pos()` 直接调它算伤害原点。
## ★★上下分得开一点（0.35/0.65 → 0.16/0.84）：
##   时间对齐对比第一张就看出来了 —— 官方那两根是**从两个方向收敛到目标身上**
##   （命中白闪正好在 V 的顶点），而我的两根根部只差 0.30 场高、目标又远，
##   于是永远是**两条平行的板子**并排飞过去（用户点名的那条差距）。
##   拉开到 0.24/0.76 后，同一个目标的两条攻击线夹角从 32° 变成 ~60°，V 才成立。
## ⚠ 拉开是有**上限**的：0.16/0.84 那一版探针实测 `left|1` 全程 `IDL` ——
##   两根离得太远，同一个目标进不了下面那根的 520 码固定射程，于是**它压根不出手**，
##   画面上从"两条平行板"变成"只有一条"。0.24/0.76 是"够开成 V"且"两根都够得着"的折中。
const ROOT_Y_HI := 0.24
const ROOT_Y_LO := 0.76

func root_pos(side: String, idx: int) -> Vector2:
	# ★搬过家之后根部就不在默认点了 —— 每根触手自己存一个 `root`。
	var tt = _tents.get("%s|%d" % [side, idx], null)
	if tt is Dictionary and (tt as Dictionary).has("root"):
		return (tt as Dictionary)["root"]
	return default_root(side, idx)


## 默认出生点（还没搬过家时用它）
func default_root(side: String, idx: int) -> Vector2:
	var a: Rect2 = battle.ARENA
	var y: float = a.position.y + a.size.y * (ROOT_Y_HI if idx == 0 else ROOT_Y_LO)
	var x: float = a.position.x + a.size.x * 0.18
	if side != "left":
		x = a.position.x + a.size.x * 0.82
	return Vector2(x, y)


## 【转移阵地】钻回地下 → 在 `to2` 重新破土。
## 用户 2026-08-04：「触手攻击范围内没有敌人持续一秒后，触手会钻入地下消失，
##   然后从可攻击的目标附近再重新破土而出」。
## ★只搬**待机中**的（正在出土/预警/拍击/撤场的不打断）。返回是否受理。
func relocate(side: String, idx: int, to2: Vector2) -> bool:
	var k: String = _key(side, idx)
	if not _tents.has(k):
		return false
	var t: Dictionary = _tents[k]
	if int(t["state"]) != ST_IDLE:
		return false
	t["state"] = ST_RETRACT
	t["ts"] = 0.0
	t["relocate_to"] = to2
	_telegraph_hide(t)
	return true


## 当前这根触手的「动作进度」→ [露出比例 emerge, 根部切角(度), 梢端切角(度), 卷曲量(度)]
## ★不再返回"高度/前伸" —— 那套做出来是"沿地面伸长"，不是砸下。见形状常量那节。
func _phase(t: Dictionary) -> Array:
	var st: int = int(t["state"])
	var ts: float = float(t["ts"])
	match st:
		ST_EMERGE:
			var e: float = clampf(ts / T_EMERGE, 0.0, 1.0)
			var k: float = smoothstep(0.0, 1.0, e)
			return [e, lerpf(ANG_EMERGE[0], ANG_IDLE[0], k), lerpf(ANG_EMERGE[1], ANG_IDLE[1], k), CURL_TIGHT * k]
		ST_IDLE:
			# ★呼吸：卷成环 ⇄ 舒展。用触手自己的相位错开，两根不同步。
			var br: float = 0.5 - 0.5 * cos(TAU * (battle._t + float(t["phase"])) / BREATH_PERIOD)
			# 舒展时不只是松卷，整条也会更斜地伸出去（逐帧看到的）
			return [1.0, lerpf(ANG_IDLE[0], ANG_IDLE[0] - 1.8, br),
				lerpf(ANG_IDLE[1], ANG_IDLE[1] + 3.0, br),
				lerpf(CURL_TIGHT, CURL_LOOSE, br)]
		ST_WARN:
			# ★★★2026-08-04【第四次改，这次以【图】为准 —— 前一次的数字是脏的】
			#   我拿"左下角小窗"量宽高比，得出 1.5→0.82 判成"越来越竖"，
			#   **裁切窗把摊平时横向超出的部分切掉了** ⇒ 摊平被量成"变竖"。
			#   放大看图才是对的，官方预警这 1 秒是【两次起伏】：
			#     +0        贴地一坨青团（趴着）
			#     **+8**    立起成一个大 **C 形钩**（梢端朝斜上勾回来，最显眼的姿态）
			#     +16~+24   **塌下去摊平**成一片横躺的雾
			#     **+28**   **再立起卷成环**（蓄力，接前摇）
			#   我前一版是"全程同一个钩"，两次起伏一个都没有。
			var wp: float = clampf(ts / T_WARN, 0.0, 1.0)
			if wp < 0.27:                                   # 趴 → 立成 C 钩
				var q: float = smoothstep(0.0, 1.0, wp / 0.27)
				return [1.0, lerpf(ANG_IDLE[0], 98.0, q), lerpf(ANG_IDLE[1], 104.0, q),
					lerpf(CURL_TIGHT, 232.0, q)]
			elif wp < 0.53:                                 # 塌下去摊平
				var q2: float = smoothstep(0.0, 1.0, (wp - 0.27) / 0.26)
				return [1.0, lerpf(98.0, 34.0, q2), lerpf(104.0, -12.0, q2),
					lerpf(232.0, 62.0, q2)]
			elif wp < 0.80:                                 # 保持摊平（只轻微起伏）
				var q3: float = sin(TAU * (wp - 0.53) / 0.27) * 0.5 + 0.5
				return [1.0, lerpf(34.0, 40.0, q3), lerpf(-12.0, -4.0, q3),
					lerpf(62.0, 78.0, q3)]
			else:                                           # 再立起卷环（蓄力）
				var q4: float = smoothstep(0.0, 1.0, (wp - 0.80) / 0.20)
				return [1.0, lerpf(34.0, 96.0, q4), lerpf(-12.0, 96.0, q4),
					lerpf(62.0, 205.0, q4)]
		ST_REAR:
			# ★★★2026-08-04【整条曲线逐帧对齐之后的重做】
			#   官方前摇 5 帧（−5→−1）：青覆盖 **1.55 → 2.73（+76%）**、
			#   投影臂长 0.097 → 0.167、最高点 0.14 → 0.30。
			#   = 它在【长大 + 立起来】。
			#   我上一版同一段：覆盖 1.52 → **1.17（缩小）**、臂长 0.163 → 0.084。
			#   **方向是反的** —— 因为我把前摇写成"往 CURL_TIGHT 卷"，卷 = 缩成一团。
			#   ⇒ 前摇不卷，反而略松开一点，靠【立起 + 长大】(arc 在 _rebuild 里放大)撑面积。
			var r: float = smoothstep(0.0, 1.0, clampf(ts / T_REAR, 0.0, 1.0))
			return [1.0, lerpf(ANG_IDLE[0], ANG_REAR[0], r), lerpf(ANG_IDLE[1], ANG_REAR[1], r),
				# 前摇要【张开】不是卷死 —— 卷死 = 缩成一团 = 投影塌(实测 −3→−2 掉 24%)
				lerpf(CURL_TIGHT, 196.0, r)]
		ST_SLAM:
			# ★★★官方拍击【一帧都没有停过】：
			#     覆盖 +0 7.06 → +2 峰值 8.53 → +6 5.47 → +9 4.11（**每帧都在降**）
			#     臂长 +0 **0.435（一帧就到最长，还过冲）** → +1 0.354 → +2 0.417 → +6 0.348
			#   我上一版 +2~+9 覆盖恒定 9.06、臂长恒定 0.521 —— **定格了 8 帧**。
			#   这是"节奏不像"里最大的一条，比任何配色/粗细都显眼。
			#   ⇒ 姿态角改成【一帧甩到位 + 之后持续压低】，长度的过冲/回缩在 _rebuild 里。
			# ★★★2026-08-04【锚点对齐后抓到的真 bug】：
			#   姿态角原来还在 `ts/0.018` 插值，于是 **ts=0 那一帧**长度已经跳到最大、
			#   角度却仍是完全后仰 —— 一根 14 单位长的【竖直杆子】在俯角相机下
			#   投影几乎为零（实测那帧青覆盖 1.48%，官方同帧 7.06%）。
			#   官方 f039→f040 是**一帧之内从蜷缩直接到伸展**，姿态没有插值过程。
			#   ⇒ 角度【瞬时到位】；"鞭子感"由长度包络表的 +2 二次峰给，不由角度缓动给。
			var e2: float = 1.0
			# 甩到位之后【继续往下压】—— 官方最高点 +0 0.93 → +4 0.77，是压下来的
			var dur: float = T_JAB if float(t["share"]) < 0.9 else T_SLAM
			var settle: float = clampf((ts - 0.033) / maxf(dur - 0.033, 0.01), 0.0, 1.0)
			var a0v: float = lerpf(ANG_REAR[0], ANG_SLAM[0], e2) - 10.0 * settle
			var a1v: float = lerpf(ANG_REAR[1], ANG_SLAM[1], e2) - 8.0 * settle
			return [1.0, a0v, a1v, lerpf(CURL_TIGHT, CURL_SLAM, e2)]
		ST_RECOVER:
			# ★官方恢复是 **19 帧的长尾**（+10 3.91 缓降到 +28 1.72），
			#   我上一版 8 帧就掉回基线 = 收得太干脆。T_RECOVER 已拉长，这里用
			#   **前慢后快**的曲线（官方 +10 0.327 → +11 0.245 有个拐点）。
			var c: float = clampf(ts / T_RECOVER, 0.0, 1.0)
			c = pow(c, 2.2)
			return [1.0, lerpf(ANG_SLAM[0] - 10.0, ANG_IDLE[0], c),
				lerpf(ANG_SLAM[1] - 8.0, ANG_IDLE[1], c), lerpf(CURL_SLAM, CURL_TIGHT, c)]
		ST_RETRACT:
			var q: float = clampf(ts / T_RETRACT, 0.0, 1.0)
			return [1.0 - q, ANG_IDLE[0], ANG_IDLE[1], CURL_TIGHT]
	return [1.0, ANG_IDLE[0], ANG_IDLE[1], CURL_TIGHT]


## 当前状态下的【弧长】。从 `_rebuild` 拆出来 —— 那个函数长到 277 行，
## 撞了架构预算的 250 行上限（`tools/arch_budget.py`）。
##
## ★★★逐帧曲线对齐（长度包络照官方投影臂长走）：
##     前摇 −5→−1  0.097 → 0.167  （**长大 72%**）
##     +0          0.435            （**一帧到最长，且过冲**）
##     +1/+2       0.354 / 0.417    （回弹一下 = 鞭子的余振）
##     +3→+9       0.405→0.329      （持续回缩，不停）
##     +10→+20     0.327→0.166      （长尾收回）
##   我做过的错版：前摇缩短、+0 只到 0.251、+1~+9 恒定 0.521（**定格 8 帧**）。
func _arc_for(t: Dictionary, stt: int) -> float:
	var reach_arc: float = ATTACK_LEN          # ★固定长度，不随目标距离变
	match stt:
		ST_WARN:
			# ★弧长跟着【两次起伏】走：立钩 ×1.45 → 摊平 ×1.10 → 再立起卷环 ×1.55
			var wq: float = clampf(float(t["ts"]) / T_WARN, 0.0, 1.0)
			# ★官方摊平段(f024~f036)面积**回落到待机的 0.72~0.75 倍** —— 是缩小不是涨。
			#   我原来给 ×1.10 ⇒ 摊平时反而是一大团胖云朵，画面上比待机还显眼。
			if wq < 0.27:
				return ARC_LEN * lerpf(1.00, 1.45, smoothstep(0.0, 1.0, wq / 0.27))
			if wq < 0.53:
				return ARC_LEN * lerpf(1.45, 0.86, smoothstep(0.0, 1.0, (wq - 0.27) / 0.26))
			if wq < 0.80:
				return ARC_LEN * 0.86
			return ARC_LEN * lerpf(0.86, 1.55, smoothstep(0.0, 1.0, (wq - 0.80) / 0.20))
		ST_REAR:
			# 前摇【长大】：不是缩，官方那 5 帧面积涨了 76%
			var rp: float = clampf(float(t["ts"]) / T_REAR, 0.0, 1.0)
			return lerpf(ARC_LEN, ARC_LEN * REAR_GROW, smoothstep(0.0, 1.0, rp))
		ST_SLAM:
			# ★查官方包络表：峰值锚在 reach_arc，形状(含 +2 的余振二次峰)照抄
			return maxf(reach_arc * _env(SLAM_LEN_CURVE, float(t["ts"])), ARC_LEN)
		ST_RECOVER:
			# ★同一条曲线继续走（偏移 T_SLAM），末段并到待机弧长
			var te: float = T_SLAM + float(t["ts"])
			var blend: float = clampf(float(t["ts"]) / T_RECOVER, 0.0, 1.0)
			return lerpf(maxf(reach_arc * _env(SLAM_LEN_CURVE, te), ARC_LEN),
				ARC_LEN, pow(blend, 4.5))
	return ARC_LEN


func _rebuild(t: Dictionary) -> void:
	var mi: MeshInstance3D = t["mi"]
	if not is_instance_valid(mi):
		return
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	var side: String = str(t["side"])
	var from2: Vector2 = root_pos(side, int(t["idx"]))
	var to2: Vector2 = t["aim"]
	if to2 == Vector2.ZERO:
		to2 = from2 + Vector2(1.0 if side == "left" else -1.0, 0.0) * 400.0
	var ph: Array = _phase(t)
	var emerge: float = float(ph[0])
	var a0: float = float(ph[1])       # 根部切角(度)
	var a1: float = float(ph[2])       # 梢端切角(度)
	var curl: float = float(ph[3])     # 卷曲量(度) —— 随状态变, 砸下时松开

	# 世界系的"前"与"上"
	var d2: Vector2 = to2 - from2
	if d2.length() < 1.0:
		d2 = Vector2.RIGHT
	var dir2: Vector2 = d2.normalized()
	var nrm2 := Vector2(-dir2.y, dir2.x)
	var root3: Vector3 = battle._world_pos(from2, battle.GROUND_LIFT)
	var wa: Vector3 = battle._world_pos(from2 + dir2 * 100.0, battle.GROUND_LIFT)
	var fwd: Vector3 = (wa - root3).normalized()
	var wn: Vector3 = battle._world_pos(from2 + nrm2 * 100.0, battle.GROUND_LIFT)
	var lat: Vector3 = (wn - root3).normalized()
	var up := Vector3.UP

	var swayt: float = battle._t * SWAY_SPEED + float(t["phase"])
	# ★攻击时弧长拉长（扑出去够到目标），其余状态用待机弧长
	var arc: float = ARC_LEN
	var stt: int = int(t["state"])
	# 攻击/回位时按【到目标的真实世界距离】伸长
	arc = _arc_for(t, stt)
	var ds: float = arc * emerge / float(SEG)     # 出土 = 露出的弧长在长

	# 菲涅尔边缘光要用相机位置。无头门禁里没有相机 ⇒ 退化成"全边缘"（不影响几何断言）。
	var camp := Vector3.ZERO
	var camp_ok := false
	if battle._cam != null and is_instance_valid(battle._cam):
		camp = (battle._cam as Camera3D).global_position
		camp_ok = true

	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos: Vector3 = root3
	var prev: Array = []
	var prev_cols: Array = []
	var prev_uvs: Array = []
	var halo_pts: Array = []      # 外发光壳用: 每段的环心 + 切/侧/上
	var halo_r: Array = []
	var any := false
	for sidx in range(SEG + 1):
		var u: float = float(sidx) / float(SEG)
		# ★切角沿长度插值；梢端那一段额外多转 → 卷成钩
		# ★弯曲集中在【中后段】—— 实机根部一截是相对直的，弧度往梢端堆。
		#   原来用 smoothstep(0,1,u) 是对称的，从根就开始弯。
		var ang: float = lerpf(a0, a1, pow(u, 1.05))
		var cfrom: float = (CURL_FROM_CURLY
			if (stt == ST_IDLE or stt == ST_WARN) else CURL_FROM)
		if u > cfrom:
			var cu: float = (u - cfrom) / (1.0 - cfrom)
			ang -= curl * cu * cu
		# 横向摆（待机摇曳 + S 形）
		# ★★攻击时【摆动与波浪都要压掉】——
		#   官方 `wfull` +2~+14 那几帧是**一条绷直的光带**；
		#   我把待机的 ±7° 起伏一直留着，攻击态就变成一根【一节一节鼓起来的胖香肠】
		#   （时间对齐对比 v2 最刺眼的问题）。绷直才有"抽出去"的力量感。
		var wavy: float = 0.14 if int(t["state"]) == ST_SLAM else 1.0
		var yaw: float = deg_to_rad(S_AMP * sin(u * TAU * 0.6 + swayt) * wavy)
		# ★主干的波浪起伏 —— 逐帧看官方 idle，主干【不是光滑的弧】，
		#   沿长度有明显的一波一波（像水流）。叠在切角上，幅度不大但读得出来。
		ang += 7.0 * wavy * sin(u * TAU * 2.1 + swayt * 1.7)
		var ar: float = deg_to_rad(ang)
		var tan: Vector3 = (fwd * cos(ar) * cos(yaw) + lat * sin(yaw) * cos(ar) + up * sin(ar)).normalized()
		# ══ 截面：★★★2026-08-04【放大看图之后的路线更换】═════════════
		#   原来是【闭合圆环】(RING 个点绕切向一圈) + `CULL_DISABLED` ⇒
		#   放大之后是**两根空心塑料水管**：看得见内壁、看得见圆周多边形棱、
		#   而且为了"有体积"必须做粗 —— 三个毛病同一个根：**它是个管**。
		#   而参考根本没有"管"这个概念，它是**一条细的发光带**。
		#   ⇒ 改成【朝向相机的扁带】(side = 切向 × 视线)：
		#     · 没有背面 ⇒ 内壁消失
		#     · 没有圆周 ⇒ 多边形棱消失
		#     · 不靠体积撑存在感 ⇒ 可以做细
		var vdir: Vector3 = (pos - camp).normalized() if camp_ok else Vector3(0, -1, 0)
		var sidev: Vector3 = tan.cross(vdir)
		if sidev.length() < 0.001:
			sidev = tan.cross(up)
		if sidev.length() < 0.001:
			sidev = lat
		sidev = sidev.normalized()
		var up2: Vector3 = sidev.cross(tan).normalized()
		# ★收细曲线 0.72 → 0.42：实机是【根粗、迅速变细、梢端成尖】，
		#   0.72 那条几乎是等粗的一根管子（并排对比时最明显的差异之一）。
		# 粗壮体型：收细放缓（0.42 是细长鞭子的曲线，粗触手要更饱满）
		# ★★★2026-08-04【归一化裁切逐帧对照看出来的形状核心差异】
		#   官方**待机/预警**的触手是【中间鼓、两头收】的纺锤/团（像水母、像一坨），
		#   **拍击**才是【根粗梢细】的锥（那时它是抽出去的能量带）。
		#   我原来全程都用锥形剖面 ⇒ 待机看着像根上尖下宽的萝卜，不是团。
		var r: float
		var stt0: int = int(t["state"])
		if stt0 == ST_IDLE or stt0 == ST_WARN:
			# 纺锤：0 和 1 两端收到 0.42，中段 (u≈0.45) 鼓到 1.0
			var bulge: float = 0.42 + 0.58 * pow(sin(PI * clampf(u, 0.0, 1.0)), 0.72)
			r = R_BASE * bulge
		else:
			r = lerpf(R_BASE, R_TIP, pow(u, 0.85))
		# ★★官方轮廓是【毛的】(不规则起伏)，我是光滑的数学曲线 ——
		#   沿长度给半径加一点点确定性起伏（不用随机：确定性演出，换路可复现）。
		r *= 1.0 + 0.055 * sin(u * 21.0 + float(t["phase"]) * 3.1) 			+ 0.032 * sin(u * 47.0 + float(t["phase"]))
		# ★最底下那一小段【快速收窄】—— 官方是"从地里钻出来"，
		#   等粗到底会变成一只方底的脚（并排比对时很假）。
		if u < 0.10:
			r *= 0.42 + 0.58 * (u / 0.10)
		# ★★攻击时它不是"变长的触手"，是**一条粗光带** ——
		#   时间对齐对比里官方那条从根到目标粗细几乎不变、又粗又亮。
		#   所以攻击态把锥度压平（往均匀靠）并整体加粗。
		#   ★但"压平锥度"上一版压过头了(0.92/0.80 → 几乎等粗的一根白管)。
		#   官方逐帧量下来：横向弦宽 35px / 投影长 188px ≈ **0.14 的粗细比**，
		#   而且**梢端仍然收**（它是触手，不是激光柱）。⇒ 保留 1/5 左右的锥度。
		# ★★★粗细是【量出来的】不是看出来的（`ttmeasure.py`：把光带做 PCA，
		#   短轴/长轴 = 粗细比，官方 `wfull/041,043` 单条臂 = **0.30~0.35**）。
		#   我一路眼看着"我的好像更胖"，实测却是 **0.18 —— 反而太细**：
		#   截图里显胖只是因为两条臂张成 V 之后包围盒变宽，每条臂被缩得又短又粗。
		#   （memory [[fb-probe-before-claiming-rootcause]]：推理出来的不算根因。）
		# ★★待机与预警期本体要【厚】—— 官方那是个圆钝饱满的半透明团/粗钩，
		#   我原来是根细弯钩。只有【拍击】才该细而亮（那时它是能量不是肉）。
		if int(t["state"]) == ST_IDLE:
			r *= 1.75
		if int(t["state"]) == ST_WARN:
			# ★★★官方 f016~f021 是一个**有明显钩口的 C 形钩**；
			#   我加粗 + 纺锤剖面之后钩口被**填满**了，变成一根实心柱。
			#   ⇒ 预警期反而要【比待机细】，卷曲更紧，钩口才露得出来。
			r *= 0.92
		if int(t["state"]) == ST_RECOVER:
			# ★收细【延续到恢复期】—— 官方 +12 带宽仍在 0.0288 一路细下去，
			#   我上一版恢复期恒定 0.0354 ⇒ 收回来的是一根还很粗的棍子。
			var _te: float = T_SLAM + float(t["ts"])
			var _bl: float = clampf(float(t["ts"]) / T_RECOVER, 0.0, 1.0)
			r *= lerpf(W_PEAK * _env(SLAM_W_CURVE, _te), 1.0, pow(_bl, 3.0))
		if int(t["state"]) == ST_SLAM:
			# ★★★2026-08-04【距离变换沿臂量出来的第三只】
			#   官方 `wfull/041` 单臂：**根 0.0585 → 梢 0.0319（锥度 1.83:1，根粗）**
			#   我上一版：      **根 0.0238 → 梢 0.0316（0.75 —— 锥度是【反】的）**
			#   两个抹平锥度的元凶：
			#     ① 这里原本 `lerpf(r, R_BASE*1.35, 0.75)` 把全长往同一个数拉 ⇒ 等宽霓虹管
			#     ② 辉光半径的**常数偏移**给全长等量加宽 ⇒ 越细的地方占比越大，越抹越平
			#   ⇒ ① 改等比放大（形状守住）；② 偏移砍到 1/4。
			# ★官方拍击【带宽也在变细】: +2 峰值 0.051 → +6 0.030（×0.59）。
			#   我上一版是恒定 ×1.50 ⇒ 抽出去之后杵着不动、更像根管子。
			# ★★★官方带宽曲线：+0 **0.0396(细)** → +2 **0.0508(峰)** → +6 0.0296 → +12 0.0288。
			#   ——【甩出去那一瞬间是细的，之后才鼓起来，再收细】。
			#   我上一版是"起点最粗、一路细下去" = **方向反的**（+0 实测 0.0622，官方 1.57 倍）。
			#   这是能量"涌过去"和"戳过去"的区别。
			r *= W_PEAK * _env(SLAM_W_CURVE, float(t["ts"]))
		# ★梢端【收成尖】—— 时间对齐对比里我的攻击态是一根**平头管子**，
		#   官方那两条都是从粗到尖收干净的（它是触手，不是水管）。
		if u > 0.86:
			r *= 1.0 - 0.86 * pow((u - 0.86) / 0.14, 1.4)

		var ring: Array = []
		var cols: Array = []
		var uvs: Array = []
		var st2: int = int(t["state"])
		for k in range(RING):
			# ★横向铺开的一条直线（不是绕一圈）—— f∈[-1,1]，0 是芯、±1 是边
			var f: float = float(k) / float(RING - 1) * 2.0 - 1.0
			var vpos: Vector3 = pos + sidev * (f * r)
			ring.append(vpos)
			uvs.append(Vector2(float(k) / float(RING - 1), u))
			# ★★★【菲涅尔边缘光】—— 这一版最重要的一处。
			#   官方那条光带的质感 = **半透明的暗青芯 + 一圈很亮的轮廓边**；
			#   我原来用 `0.5+0.5*sin(环角)` 假装边缘光，那是"固定的一侧亮"，
			#   跟真正的轮廓边**根本不重合**，所以并排看永远是一根「均匀塑料管」。
			#   真轮廓边 = 法线与视线【垂直】的地方 ⇒ rim = 1 − |n·v|。
			# ★扁带上所有点法线相同 ⇒ 菲涅尔失效。改用【横向到边的距离】：
			#   芯部(f=0) rim=0、边缘(|f|=1) rim=1 —— 这正是"暗芯 + 亮边"的那条梯度。
			var rimf: float = clampf(absf(f), 0.0, 1.0)
			# ★实机: **待机是暗的、出手才爆亮** —— 明暗对比是这条特效的力量感来源。
			var col: Color
			if st2 == ST_SLAM:
				# ★★上一版写死成常数 `Color(0.86,1,1)` = 一片均匀的近白 ⇒「实心板」。
				#   官方 `wfull/041` 横截面实测：暗侧 (31,185,188)、亮边 (108,197,182)、
				#   热条 (27,202,224) —— **明暗差在，白不在**。
				#   顶点色允许 >1（乘在贴图上当增益），这样芯部才够亮又不吃掉梯度。
				#   ★亮度也量过：官方那条光带**最亮处只有 ~205**（G+B 均值口径），
				#     我上一版顶到 255 = 溢出成白。整体压 ~20% 才落回官方那一档。
				#   ★★2026-08-04 补：压亮度还不够——真正把它变白的是 **R 通道**。
				#     官方横截面 (31,185,188) / (108,197,182) / (27,202,224)：
				#     **R 只有 G·B 的 1/6 ~ 1/2**，而我写的是 0.80 ≈ G ⇒ 必然是白。
				#     量了却没照着用，是这次"完全不像"里最好修的一条。
				col = Color(0.52, 1.06, 1.10).lerp(Color(0.10, 0.60, 0.62), pow(rimf, 1.3))
			elif st2 == ST_REAR:
				var kk: float = clampf(float(t["ts"]) / T_REAR, 0.0, 1.0)
				col = Color(0.46, 1.00, 1.04).lerp(Color(0.09, 0.56, 0.58), pow(rimf, 1.4))
				col = col.lerp(Color(0.70, 1.26, 1.32), 0.5 * kk)
			else:
				col = Color(0.34, 0.86, 0.90).lerp(Color(0.08, 0.48, 0.52), pow(rimf, 1.5))
			# ★梢端别再往白里提 —— 比对时那是个突兀的白点。改成【边缘】亮、梢端只是稍亮。
			# ★官方那条光带【越靠近命中端越亮】(能量往目标涌)，我原来是均匀的。
			if st2 == ST_SLAM:
				col = Color(col.r * (0.84 + 0.30 * u), col.g * (0.84 + 0.30 * u), col.b * (0.84 + 0.30 * u))
			# ★★2026-08-04【放大对比】：扁带解决了"空心管/多边棱"，但芯变成了一条
			#   **硬边白条** —— 边界是切出来的。官方那条是【亮芯往两侧化开】，
			#   边界糊的。色梯度做不到这件事，得靠**顶点 alpha 横向渐隐**。
			# ★★2026-08-04 放大对比：官方【待机】是一坨**不透明的圆润青团**（像果冻），
			#   我是一根半透明发光带（边缘透）。量出来我反而比官方粗 33% ——
			#   所以差的不是宽度，是**实心度**。待机时把横向渐隐压平（边缘也不透）。
			# ★★预警期也要【有体积】—— 放大对比官方那个 C 钩是粗壮饱满的半透明实体，
			#   我原来在 WARN 期用 0.85（细发光带），看着像根发丝。
			#   只有【拍击】才该是细而亮的光带（那时它是"能量"不是"肉"）。
			var soft: float = pow(1.0 - rimf,
				0.34 if (st2 == ST_IDLE or st2 == ST_WARN) else 0.85)
			var fin: Color = col.lerp(Color(0.62, 0.94, 0.88), u * 0.12)
			cols.append(Color(fin.r, fin.g, fin.b, soft))
		if not prev.is_empty():
			any = true
			# ★开放带：k2 只到 RING-2，且【不回绕】——
			#   闭合环的 `% RING` 会把最后一点连回第一点，在扁带上就是一张
			#   横穿整条带子的面（把带子封成了管），空心内壁就是这么来的。
			for k2 in range(RING - 1):
				var k3: int = k2 + 1
				var u3a: Vector2 = prev_uvs[k2]
				var u3b: Vector2 = Vector2(1.0, prev_uvs[k3].y) if k3 == 0 else prev_uvs[k3]
				var u3c: Vector2 = uvs[k2]
				var u3d: Vector2 = Vector2(1.0, uvs[k3].y) if k3 == 0 else uvs[k3]
				stool.set_color(prev_cols[k2]); stool.set_uv(u3a); stool.add_vertex(prev[k2])
				stool.set_color(prev_cols[k3]); stool.set_uv(u3b); stool.add_vertex(prev[k3])
				stool.set_color(cols[k2]);      stool.set_uv(u3c); stool.add_vertex(ring[k2])
				stool.set_color(prev_cols[k3]); stool.set_uv(u3b); stool.add_vertex(prev[k3])
				stool.set_color(cols[k3]);      stool.set_uv(u3d); stool.add_vertex(ring[k3])
				stool.set_color(cols[k2]);      stool.set_uv(u3c); stool.add_vertex(ring[k2])
		halo_pts.append([pos, sidev, up2])
		halo_r.append(r)
		prev = ring
		prev_cols = cols
		prev_uvs = uvs
		# ★沿切向走一步 —— 弧长天然守恒，这就是"长度固定"的来源
		pos += tan * ds
		if pos.y < root3.y - 0.4:
			pos.y = root3.y - 0.4                 # 别扎穿地板太多
	if any:
		stool.generate_normals()
		stool.commit(mesh)
	_rebuild_halo(t, halo_pts, halo_r)


## 场上现有几根（给门禁与调试用）
func count(side: String = "") -> int:
	if side == "":
		return _tents.size()
	var n := 0
	for k in _tents:
		if str((_tents[k] as Dictionary)["side"]) == side:
			n += 1
	return n


## 调试探针：把每根触手的 `态/ts/可见` 打成一行。
## ★做时间对齐对比图时**必须有它** —— 只看截图会把"状态切换"和"演出被藏了"
##   两种完全不同的原因看成同一个现象（CLAUDE.md：断根因先写探针打数值）。
func probe() -> String:
	# ★★ST_WARN 追加在末尾(=6)，这张表也必须跟着补 ——
	#   漏补的话越界，探针把整整 33 帧的【预警】显示成 "IDL"，
	#   看着像"预警根本没做出来"（实测被这条骗过一次）。
	var names := ["EM", "IDL", "REAR", "SLAM", "REC", "RET", "WARN"]
	var out: Array = []
	for k in _tents:
		var t: Dictionary = _tents[k]
		var mi = t.get("mi", null)
		var ha = t.get("halo", null)
		out.append("%s=%s/%.2f/mi%s/ha%s" % [k, (names[int(t["state"])] if int(t["state"]) < names.size() else "?%d" % int(t["state"])), float(t["ts"]),
			"1" if (is_instance_valid(mi) and (mi as MeshInstance3D).visible) else "0",
			"1" if (is_instance_valid(ha) and (ha as MeshInstance3D).visible) else "0"])
	return " ".join(out)


func state_of(side: String, idx: int) -> int:
	var k: String = _key(side, idx)
	return int((_tents[k] as Dictionary)["state"]) if _tents.has(k) else -1


## 换路 / 战斗结束：立刻撤干净（不走 RETRACT 动画 —— 场景要清空了）
func clear() -> void:
	for k in _tents:
		# ★★2026-08-04：这里原来漏了 `warn_mi` ⇒ **换路/清场每次泄漏一个预警带节点**。
		#   症状极隐蔽：泄漏的节点占着 "TentacleWarn_left_0" 这个名字，
		#   下一根触手新建的同名节点被 Godot 自动改名成 `@TentacleWarn_left_0@…`，
		#   于是按名字找节点的代码（门禁）**找到的是那个已隐藏的旧节点** ——
		#   报出来是"预警带没建出来"，实际是建了两个、找错了一个。
		for kk in ["mi", "halo", "warn_mi"]:
			var n = (_tents[k] as Dictionary).get(kk, null)
			if is_instance_valid(n):
				n.queue_free()
	_tents.clear()
