# 技能特效 VFX 美术计划 — ✅ 全部完成（2026-07-10）

> **状态：所有技能 VFX 美术已完成并实装。代码里 VFX 占位（`_skill_ring`/`_bolt_line` 标"占位"的）已全清空为 0。**
> 素材 59 → **77 个**。逐项照 `VFX美术原话简报.md` 的用户逐字原话做，绝不自造。

## 关键结论（实测得出）
- **PixelLab (`create-image-pixflux`) 只出实心像素物体**：护盾→实心壳、屏障→实心宝石、"sword slash"→实心剑。
  - ✅ **诀窍**：特效类必须用 `negative_description` 排除实体（`sword,blade,weapon,character,object`），才拿到"斩弧/爆发/溅射"本身。
  - ❌ **半透明/发光/能量场做不出来** → 改用 **PIL 程序化生成带 alpha 的渐变贴图**（白色可 `modulate` 染色，一张多处复用）。
- 分辨率统一 **64×64**（用户标准）；程序化贴图 128px（渐变类不需像素对齐）。

## 新增通用助手（可复用）
| 助手 | 用途 |
|---|---|
| `_burst_vfx(path,pos,size,h)` | 命中爆发/溅射：放大入场→保持→淡出→自销 |
| `_fly_vfx(path,from,to,size,dur,h,delay)` | 飞行投射物（自动识别横排帧动画；delay 做连珠错峰）|
| `_aura_vfx(path,unit,radius,color,dur,h)` | 贴地半透明光环罩住单位·跟随单位·淡入淡出（仿 `_shield_dome`）|
| `_beam_vfx(path,from,to,width,color,dur,h)` | 贴地长条纹理（激光/索线/拖影），自动对齐方向 |

---

## A 组 · PixelLab 实心类（9/9 ✅）
| 龟 | 特效 | 素材 | 照的原话 |
|---|---|---|---|
| 小龟 | 龟派气波 | `qibo-spawn` + `qibo-ball` | 07-05「拳皇罗伯特能量弹·生成+飞行循环·**无消失**」·移速 300码/秒（07-10 用户"太快了"从562下调）|
| 小龟 | 过肩摔落地 | `dust-impact` + `fx-shock-ring` | 07-05「二人落地」|
| 石头 | 嘲讽砸地 | `stone-slam-impact` | 07-06「像地面猛砸」|
| 忍者 | 疾风斩弧（冲击/背刺）| `ninja-slash` | 07-06「参考亚索 E」|
| 糖果 | 糖爆 | `candy-burst` | 07-07「蓄力举糖果锤猛砸直线200码」|
| 星际 | 巨彗星冲击 | `comet-impact` | #3「召唤巨大彗星·爆炸释放大冲击波·龙王R」|
| 宝箱 | 砸点金光 | `treasure-slam` | #3「参考 LoL K'Sante Q·aoe短直线」|
| 线条 | 墨爆溅（每敌+中心）| `ink-splat` | 墨水炸弹全体 |
| 海盗 | 掠夺登场轰击 | `cannon-blast` | 07-09「加回原版掠夺」|
| 竹叶 | 竹藤钩 | `bamboo-vine` | 07-06「伸出一条竹藤·打最远的敌人·拉过来」|

## B 组 · 接现有素材（✅ 0 额度）
- 猎人 狩猎弹幕 10 绿箭 → `hunter-arrow.png`（4帧）· `_fly_vfx` 每箭错峰 0.055s = 连珠速射。
- 小龟 打击 10 波 → 复用 `qibo-ball` 慢飞（07-05「速度要慢」）。

## C 组 · PIL 程序化半透明（✅ 全接）
新素材：`fx-glow-ring` / `fx-energy-beam` / `fx-vortex` / `fx-trail` / `fx-hex-bubble` / `fx-black-hole` / `fx-shock-ring`

| 龟 | 特效 | 做法 |
|---|---|---|
| 石头 | 500码仇恨光环（4s跟随）/ 岩脊冲击环 | `_aura_vfx` / `_burst_vfx` |
| 寒冰 | 六棱冰晶护盾泡（罩友军4s）| `_aura_vfx` hex-bubble |
| 幽灵 | 虚化紫环（4s）| `_aura_vfx` |
| 凤凰 | 烈焰加速火环 | `_aura_vfx` |
| 天使 | 金光飞升圣环 | `_aura_vfx` |
| 宝箱 | 财宝炮击长激光 / 普攻短直线 | `_beam_vfx` |
| 赛博 | 能量大炮长激光 / 数据链 / 瞬移残影 | `_beam_vfx` |
| 猎人 | 灵巧侧翻残影（薇恩Q）| `_beam_vfx` trail |
| 龟壳 | 暗影猛扑拖影（库奇W）| `_beam_vfx` trail |
| 忍者 | 背刺刀光拖影 | `_beam_vfx` trail + 斩弧 |
| 海盗 | 死亡钩索索线 | `_beam_vfx`（**并修 bug**：原索线画在拉近后的位置，改画到抓取点）|
| 星际 | 虫洞真紫旋涡 / 引力黑洞 / 星波环形扩散 | `fx-vortex` / **黑色椭圆**(用户05-29原话) / `fx-shock-ring` |

---

## 已打通：游戏内实拍管线
Godot 自带的 `_self_screenshot`（`frame_post_draw`）在后台会话里挂死。改用：
`PowerShell Start-Process Godot --path . scenes/RealtimeBattle3D.tscn` + `VFXPREVIEW=<eff>` 钩子 + `CopyFromScreen` 连拍 → 裁剪 → GIF。
`VFXPREVIEW` 可选：`qibo / stone_slam / ninja_slash / beam / aura / vortex / blackhole / hexbubble`。
**已实拍验证**：气波飞行（GIF）、光束朝向正确。

## 📌 用户要亲自做的
- **龟派气波图 = 用户要回来手动生成**（2026-07-10"气波那里你先装着，但是计划里加上我要回来手动生成气波图"）。
  - 现状：我用 PixelLab 生成的 `qibo-spawn.png` + `qibo-ball.png` **先装着能跑**（KOF罗伯特能量弹·生成帧+飞行球·无消失·300码/秒）。
  - 待用户手动出图后**直接替换这两个文件**即可，代码不用动（`_sk_basic_chiwave` 已按"生成帧→飞行循环→无消失"结构接好）。
  - 若用户的新图是**多帧横排 strip**，`_fly_vfx` 已能自动识别帧数（nf=宽/高）；`_sk_basic_chiwave` 里的飞行球是单张 Sprite3D，若要帧动画需把 `ball.hframes` 接上（一行）。

## ⚠ 留给用户 F5 眼验 / 待定
1. 各特效**尺寸/时长/手感**（数值都在代码里，一行可调）。激光束已按实拍加宽1.5x补偿贴地俯角压扁。
2. **无原话、我按合理默认做的**（已在简报标红，非自造设计、只是视觉细节）：赛博数据链配色 / 赛博瞬移残影 / 幽灵紫风暴+虚化环 / 彩虹全色风暴 / 财神金光。
3. ✅海盗掠夺数值已订死（2026-07-10）：登场轰击 & 死亡钩索 均 **25%目标最大生命·真实伤害**。
