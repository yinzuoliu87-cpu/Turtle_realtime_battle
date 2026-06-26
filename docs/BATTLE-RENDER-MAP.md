# 战斗 HUD 真实渲染层地图 (2026-06-04, 2-agent 逐行追调用链, cited)

⭐**根因/教训**: 我反复匹配错代码层 (turtle-hud / scene-turtle-dom / Phaser rect 间反复横跳), 因为没**追调用链**.
真相 (agent 逐行 grep 调用方确认):
- **`view.sceneTurtleDom` 字段名误导 — 它的 TYPE 是 `TurtleHud`** (BattleScene.ts:1987 `new TurtleHud(...)`). 这是我全部混乱的根源.
- **`scene-turtle-dom.ts` 全仓库无 `new SceneTurtleDom`, 从不 import = 死代码**. 它的 CSS/DOM 从不注入 → 运行时 `.poc-scene-turtle` count=0. **改它无用**.
- **BattleScene.ts:1944-1966 的 Phaser `hpBar/hpBarBg/hpBarHi/hpDelayBar/shieldBar/hpText/nameText` 全 `.setAlpha(0)` = 诱饵** (留着只为 legacy `.width`/`.setText()` 不报错).
- **`statusGroup` (depth60) 每帧定位但永远 `removeAll` = 空诱饵**.

## 渲染层地图 (改视觉去对的文件!)
| 元素 | 真渲染层 | 诱饵(别改) |
|---|---|---|
| HP条/护盾/槽/刻度/玻璃 | **TurtleHud (turtle-hud.ts, Phaser Graphics, depth7, 88px未缩放)** | Phaser rect alpha0 / scene-turtle-dom 死码 |
| 特殊资源条(储能/怒气/泡/坚壁) | **TurtleHud.drawSpecialtyBars (:503-548, h=4)** | scene-turtle-dom 死码 |
| 装备图标行 | **TurtleHud.refreshEquipBadges/layoutEquips (:574-672)** | scene-turtle-dom 死码 |
| 等级徽章 | **TurtleHud.levelText (:182-189,354)** | nameText alpha0 / scene-turtle-dom 死码 |
| 宝箱币堆 | **TurtleHud.chestText (:198-205)** | — |
| **状态图标(buff/debuff)** | **⚠️战斗画面不渲染!** turtle-hud refreshStatusIcons `return`短路(:555-557); statusGroup 永空(BattleScene:3965-3970 只removeAll). **只在点龟详情面板看**. | statusGroup空 / scene-turtle-dom 死码 |
| 伤害飘字 | **DOM overlay (visual_dispatcher.ts:392 scene.add.dom; CSS index.html:149-187)** | FLOAT_STYLE 是文档副本 |
| 顶部回合药丸/timeline/出手倒计时条 | **DOM (BattleTopRow.ts #poc-battle-top-row z100)** | — |
| 侧回合横幅(我方/敌方回合) | **Phaser showSideTurnBanner (BattleScene:2396-2417 depth190)** | DOM showCenterBanner 是登场/事件公告(别混) |

## 进度 / 下一步 (像素级死抠, 战斗优先; 每项: 对真层→Godot复刻→自截验→commit)
- [x] HP条: 按 turtle-hud 重写 (88×5未缩放/黑边/暗红槽/刻度/渐变/盾/trail). 自截验过.
- [x] 等级徽章底色 #2a1d12.
- [x] 删 F10 状态图标行 (自创).
- [x] 伤害飘字: 核对 VisualConstants 颜色/字号 = visual_dispatcher (#ff4444/22 物 #4dabf7/22 法 #fff true 26暴 #06d6a0/24治) ✓ 已1:1, 非诱饵层.
- [x] **特殊资源条**: turtle-hud drawSpecialtyBars(:503-548) — HpBar 下方加 h=4 条(储能青/怒气橙/星能黄/坚壁黄). 已做+测.
- [x] **装备图标列**(v1: 20×20暗框+14×14图标竖排龟外侧, 宝箱金边; 余子角标孵化器进度/电棍层数/竹叶✓): 战斗龟身上**没渲染**装备图标(grep BattleScene 0命中). turtle-hud refreshEquipBadges/layoutEquips(:574-672): box20内嵌14×14, 竖排 gap5, 在龟**外侧**(side-left左外/right右外), `equip-<id>`纹理, 宝箱专属金边, 子角标(孵化器进度条/电棍层数/竹叶✓/雷杖充能). 我只在 DetailPanel 显. 需在 makeView 加 equip 列 + update. (注意位置: 龟外侧不是血条下)
- [ ] 我的 DmgStatsPanel(F3)/DetailPanel(F4): 对真 PoC DmgStatsPanel.ts/DetailPanel.ts 核 (是真元素非诱饵, 但要核样式像素).
- [ ] 顶部回合UI (DOM BattleTopRow): 药丸/timeline轨道/出手倒计时条 — 我只有规则徽章(F7部分), timeline+倒计时条缺.
- [ ] 侧回合横幅 (Phaser showSideTurnBanner): 核我的 _show_side_banner 对不对.
- [ ] 然后逐场景 (选龟/主菜单/结算/图鉴) 按同法对真层.

## ⚠️ 我的自创 (用户要删):
- **F10 状态图标行 (我加在龟头上) = 自创!** PoC 战斗根本不渲染状态图标 (只详情面板看). **必须删 hp_bar 旁的 status_row / _refresh_status_row / _STATUS_ICON_MAP**.
- (待查: 我加的别的元素是否也自创 — 对照上表逐个核.)

## ⚠️ PoC 有但我可能漏的:
- 浮游炮(赛博龟)蓝条: turtle-hud **未移植**(只在死码), PoC实际也不显示 → 不用做.
- 伤害飘字三色分行堆叠 / 顶部 timeline+出手倒计时条 / 特殊资源条: 需对真层逐个 1:1.

## HP条 turtle-hud.ts 完整 cited 规格 (88px 未缩放; 见 hp_bar.gd 复刻)
尺寸: BAR_W=88 BAR_H=5 BORDER=2 (boss 160/8/3); SPECIAL_H=4; CHIP_BOX=20. (BAR_H 用户"扁1倍"减半过.)
frame (drawFrame:312-357, x=-BAR_W/2, y=-LIFT-BAR_H):
1. 阴影 0x000000@.4 rect(x-bd,y-bd+2,w+2bd,h+2bd) 下偏2px
2. 黑硬边框 0x0a0606@1 rect(x-bd,y-bd,w+2bd,h+2bd)
3. 暗红槽 0x281010@.95 rect(x,y,w,h)
4. 顶玻璃高光 0xffffff@.22 rect(x,y,w,1)
5. 底暗线 0x000000@.55 rect(x,y+h-1,w,1)
刻度(tickG在fill上,:333-352): minor100 0x000000@.35 1px上半(h max(2,ceil(h/2))) v=100;v<barMax;+=100; major500 0x000000@.6 全高 v=500;<barMax;+=500.
barMax(:228): max(maxHp, hp+shield+aura+bubble+anemone). 各frac=val/barMax.
fill逐行(fillBand:401-419): r=0&h>=3→gloss=lerp(light,白,.55); else lerp(light,dark,(r-1)/(h-2)). α1. 我方light0x3deb9e dark0x1fb57f; 敌light0xc084fc dark0x9d5be8.
护盾(cursor链 HP→盾→气场→泡→海葵): 白0xf0f0f5/0xc8c8dc@.55; 金气场0xffd966@.6; 青泡0x4cc9f0@.55; 紫海葵0xd96bff@.7. 宽w*frac.
红trail(delayG在fill下,:445-460): 2带 0xff4d4d[上topH] /0xc81e1e[下], 起max(_trail,old), hold200ms→500ms Sine.easeOut缩到hpFrac α1.
白闪(flashG在fill上,:462-470): 0xffffff@.6 rect(x,y,w*hpFrac,h) 60ms清.
回血(:475-500): 绿0x9dffd0 新段, α.85→0, delay60 dur450.
横抖(:428): _shakeX:3 dur30 yoyo repeat2 加到容器x.
等级徽章(:182,354): 10px(boss13) 金#ffd93d, bg#2a1d12, pad L/R3 T/B1, origin(1,.5), at(x-3,y+h/2) bar左.
