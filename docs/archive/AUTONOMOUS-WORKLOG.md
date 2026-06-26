# 自主优化工作日志 (2026-06-07 起, 用户离开 ~10h)

进度看 `git log`; 本文件只记**需 F5 / 待定 / 发现 / 决策**。append-only, 不打断节奏。

## ⭐ 本 RUN 总结 (先看这段)
**搭了像素 diff 工具 → 客观验证 + 修真问题。本 run commit (git log):**
1. 像素 diff 工具 `diff_images.gd` + worklog (76ebac08) + SHOT_PANEL/BG/TAB/BUFF dev钩子
2. **场景切换丝滑** — 全局 EXPAND + 同步建场景, 根治进选龟/图鉴的撕裂感 (ea004d94)
3. **图鉴龟详情改全身 idle 立绘** — 原误用方头像, diff 抓到 (acefdc1d)
4. 技能卡/全局 RichTextLabel 字体锁 m6x11+YaHei + 粗体 (86e32a17/c451f29e)
5. **商店单体增益→装备席拖用** — 补最后 gameplay gap, emoji渲染已验, 拖落需F5 (72345de9)
6. **中央回合横幅补背景带+金边+字间距+居中** — 审计项, 顺带修横幅偏左 bug (9dcceb19)

**diff 客观验证结论: UI/场景结构 1:1 稳**。菜单1.9% 设置1.4% 图鉴(UI部分) 成就 指定Boss 残差全是
【跨引擎sprite渲染 + 存档/状态态 + idle帧相位】, 无真 UI/布局/字体/配色 bug。战斗整帧diff噪声大
(cover-zoom+高频bg+sprite), UI 靠动作面板DOM核对(1:1)+席位尺寸分项验。

**剩余 (需你 F5 / 交互):**
- ✅ 单体buff商店→装备席 已做(72345de9): 进席+emoji渲染已ShotDiff验; 拖/落/应用镜像装备路径, **交互需F5**
- 前几轮改动的手感/交互: 拖拽残影/光标动画/教程/选龟框点选+换龟/战斗节奏停顿/idle播放 — 都需眼验
- (低) 头像方角 vs PoC 圆裁/圆角

**怎么验我的工作**: ① `git log` 看 commit ② F5 进选龟/图鉴看入场是否丝滑(不撕裂) ③ F5 看图鉴龟详情是不是
全身会动的立绘 ④ F5 看技能卡字体是不是像素体+粗名 ⑤ 像素 diff 工具留着: 见下方用法。

## 方案 (定好就照跑)
**每场景闭环**: ①Playwright 截 PoC(1280×720, scale css) ②ShotDiff 截 Godot(同分辨率/状态) ③`diff_images.gd` 像素叠差 → 红色簇=真差异 ④读 PoC 源码确认值+机制(引行号), 照搬结构不自创 ⑤改→`bash run-tests.sh`保407绿→复 diff 确认 ⑥一处一commit(记PoC出处) ⑦交互/手感/没法headless验的→标"需F5"。

**diff 工具**: `DIFF_A=res://poc.png DIFF_B=res://godot.png DIFF_OUT=res://diff.png DIFF_T=0.15 godot --headless -s diff_images.gd` → 打印 整体% + 九宫格 hotspots; 红=差异灰=Godot底。基线: 匹配场景 ~2%(跨引擎AA+bg瓷砖相位), 看红色**簇**不看零散点。
**截 Godot 动作面板**: 加 `SHOT_PANEL=1` 越过选龟框。

**护栏**: 不自创; 不靠数值/单测说"视觉验过"(必并排diff); 一处一commit, 407全绿, 不push; 有意分歧(决胜局怒气疲惫)不改回; 拿不准记本文件。

## 优先级队列
- [进行中] A1 场景切换丝滑: 全局 EXPAND(项目级 stretch/aspect) 消 aspect 翻转 + 同步建场景
- [ ] A2 actor-picker 交互自审 + headless 打通整局
- [ ] B 逐场景 diff: BattleEnd / Dungeon / RewardPick / ChoiceEvent / Shop / Settings / Achievements / Record / BossPick / 初始装备弹窗
- [ ] C1 全局字体扫(Label/Button 漏网)
- [ ] C2 战斗中飘字/数字 对比(SHOT_PANEL+autoplay)
- [ ] C3 动画/时序(windup/横幅pop/飘字时机)
- [ ] D memory backlog(单体buff入席/Codex idle/hit-stop/震屏衰减…)

## 基线 diff 记录 (DIFF_T=0.15, 1280×720)
- 主菜单 1.86% ✓匹配 (红=文字AA+bg瓷砖相位+标题)
- 设置 1.40% ✓匹配 (红=bg瓷砖+滑块默认值位置略差+文字AA; 3按钮齐)
- 图鉴 12.2% — UI/文字/面板**不红=匹配**; 红集中在 sprites(龟头像列表/技能图标=跨引擎) + 详情大头像(idle动画缺, 已知)
- 成就 6.75% — 结构匹配(同 bg/网格/卡); 红=解锁数不同(18/50 vs 4/50存档态→不同"已解锁"徽章)+图标跨引擎
- **结论: UI 一致 1:1**(布局/字体/配色/面板都对); 残差=跨引擎sprite渲染 + 存档态 + idle动画缺。diff工具有效。

- 指定Boss 16.3% — **结构1:1**(grid/title/框/text都对; 两边都 filter 掉 leftTeam, BossPickScene.gd:42); diff 高=我PoC截图 leftTeam空(28龟) vs Godot chain(25龟)状态不一致 + 龟sprite跨引擎。**非bug**(差点误修, 读真代码才发现 Godot 有 filter)。
- **diff 工具用法坑**: 有状态门控的场景(BossPick需 has_team)要 SHOT_SETUP=chain(设左右队); test 只设左队 → has_team()=false 回菜单。随机内容场景(Reward/Event)无法公平 diff。

## 已修 (本自主run)
- 场景切换丝滑: 全局 EXPAND + 同步建场景 (ea004d94)
- 图鉴龟详情改全身 idle 立绘 (acefdc1d) — 原误用头像; diff 12.2%→10.9%

## 结论 (diff 验证)
**UI/场景结构 1:1 确认**: 菜单/设置/图鉴/成就/指定Boss diff 残差全是【跨引擎sprite渲染 + 存档/状态态 + idle帧相位】, 无真UI/布局/字体/配色 bug。字体已全局锁 m6x11+YaHei。**迁移 UI 层很稳**。

## 待修 (diff 找到的真差/已知)
- 单体buff商店→装备席 (PoC ShopOverlay buySlot 单体buff也 addToBench 拖用; Godot 自动施) — **交互型(拖拽), 需F5, 较大**(bench 要持 buff 项+敌方落点)。是剩余唯一明确 1:1 gameplay gap。
- (低)图鉴列表头像方角 vs PoC 圆裁; 动作面板/选龟框头像方角 vs PoC 圆角(容器有 radius 但 TextureRect 没 clip)。

## 需 F5 清单 (机器验不了的)
- 拖拽残影大小/光标动画/教程流程/选龟框点选+←换龟交互/战斗节奏手感 (前几轮已改, 待眼验)

## 发现 / 待定
(随做随记)
