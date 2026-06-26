# 血条真实规格 (2026-06-04, 对真PoC运行时核验) — ⭐ 之前两次读错代码层

## 教训 (用户"UI差远了"的根因)
战斗血条**可见层 = DOM overlay** `scene-turtle-dom.ts` 的 `.st-hp-row` (CSS 在该文件 injectCss).
- ❌ 我先读 `turtle-hud.ts`(88×5/逐行渐变/0x281010槽) → **那不是运行的实现**.
- ❌ 我又 runtime dump Phaser `hpBar/hpBarBg`(118×8/0x22c55e/0x0a0f1a) → **那些 `.setAlpha(0)` 是隐形诱饵**
  (BattleScene.ts:1941-1945 注释明说 "Phaser canvas bars 全 alpha 0 legacy兼容, 真实显示走 sceneTurtleDom").
- ✅ **真实可见 = DOM `.st-hp-row`**, 验证: `bs.views[i].sceneTurtleDom.refreshStatusIcons` 是渲染状态的; 血条同源.
**核验法**: 对真PoC(localhost:5173) Playwright → `bs.views[i].sceneTurtleDom` + `getComputedStyle('.poc-scene-turtle .st-hp-bar')`, 别信 Phaser 对象(decoy)也别信 turtle-hud.ts.

## 真实 DOM 规格 (scene-turtle-dom.ts injectCss, 非boss; .poc-scene-turtle 整体 transform:scale(baseScale≈1.275) → 屏幕值×1.275; boss scale 1.913)

### 结构 (root .poc-scene-turtle.side-left/right[.is-boss])
```
.st-hp-row (flex, align center, margin-bottom 2px)
  .st-level-badge   (10px bold #ffd93d, bg linear-gradient(135deg,#4a3520,#2a1d12), border 1px #ffd93d80, radius3, pad 1×4, shadow 0 1px2 rgba0,0,0,.5, margin-right 2px)
  .st-hp-wrap (width 88px; boss 160)
    .st-hp-bar (width100% height10px; boss h16 border2; bg linear-gradient(180deg, rgba(20,8,8,.7)0%, rgba(40,15,15,.9)100%); radius2; overflow hidden; border 1px solid rgba(80,80,80,.6); box-shadow inset 0 1px2 rgba0,0,0,.5)
      .st-hp-delay  (absolute left0 top0 h100% z0, opacity0; 受击红trail)
      .st-hp-fill   (absolute left0 top0 h100%, width=hp/maxHp set by JS, transition width .15s; 渐变inline JS: 我方 #3deb9e→#1fb57f / 敌方 #c084fc→#9d5be8; z1)
        .hp-flash (受击60ms: filter brightness(2) saturate(.5))
      .st-shield-fill (absolute top0 h100%, left+width by JS, bg linear-gradient(180deg, rgba(255,255,255,.55)40%, rgba(200,200,220,.35)60%); z2; 白普盾)
      .st-aura-shield (金: linear-gradient(90deg, rgba(255,217,102,.45/.7/.45)) + bubbleShimmer1.6s; z2)
      .st-bubble-shield(青: linear-gradient(90deg, rgba(76,201,240,.4/.6/.4)) + shimmer; z3)
      .st-hp-ticks (absolute full, z4 在fill之上; **50/500刻度** repeating-linear-gradient, 按barMax由JS算)
  (.st-hp-text 不插入 — JS从不渲染HP数字, scene-turtle-dom.ts:404-405)
```

### 关键修正 (我当前 hp_bar.gd 错的)
1. **尺寸**: 屏幕 = 88×1.275 ≈ **112 宽**, 10×1.275 ≈ **13 高** (boss 160×1.913≈306, 16×1.913≈30). 我F6改成88×5 = 太小太薄. (pre-F6 的112宽其实更对!)
2. **槽 trough**: 暗红**渐变** rgba(20,8,8,.7)→rgba(40,15,15,.9) + **1px 灰边** rgba(80,80,80,.6) + 内阴影. (我用纯0x281010无灰边 → 截图里"灰"其实是灰边)
3. **刻度 50/500** (我用了100/500). minor 50HP / major 500HP.
4. **护盾不撑长bar**: shield/aura/bubble 都是 absolute 叠在 bar 内, left=hp宽, width=shield/**maxHp**×88 (非barMax!). hp+shield>maxHp 时 overflow hidden 裁掉. 我F6用barMax撑长 = 错.
5. fill **渐变** #3deb9e→#1fb57f(我方)/#c084fc→#9d5be8(敌方) — 颜色对, 我已用.
6. 白闪 filter brightness(2)saturate(.5) 60ms — 我近似对.
7. 红trail .st-hp-delay: oldPct→等200ms→500ms shrink+400ms fade (回血绿底0.7→0 fade 400ms).
8. level badge: 10px金 + 渐变棕底 + 金边 + margin-right2 接在bar左 (我有, 校尺寸).

## 下一步: 按此重写 hp_bar.gd (112×13 / 灰边 / 渐变槽 / 50·500刻度 / 护盾叠内不撑长). 然后对真PoC并排截图核验.

## 2026-06-04 重写完成 (纯读代码, 不用浏览器 — 用户: 代码优先, 浏览器没用)
仔细读 scene-turtle-dom.ts 全部 (constructor 380-486 / update 537-625) 改正:
- ✓ barMax = max(maxHp, hp+shield+aura+bubble) (:545, 护盾撑长; 我之前误用 maxHp).
- ✓ fill 2-band 锐渐变 (#3deb9e 38%, #1fb57f 42% → 上40%top色 下60%bot色; 我之前误用平滑lerp).
- ✓ delay 红 2-band #ff4d4d/#c81e1e (hold200ms→shrink500ms; 我之前solid#ee5555).
- ✓ 护盾 left 累加 hp%→+shield%→+aura%, 宽 val/barMax (白2-band/金/青).
- ✓ 尺寸 112×12.75 (88×10×1.275), 灰边 rgba(80,80,80,.6), 暗红平滑槽 rgba(20,8,8,.7)→(40,15,15,.9), 刻度50/500.
截图验: 2-band绿渐变 + 50刻度 + 灰边 + 等级徽章, 112×13. 余: 真PoC并排终验(浏览器状态乱, 待干净一帧).
