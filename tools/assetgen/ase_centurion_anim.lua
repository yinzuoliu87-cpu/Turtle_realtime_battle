-- ase_centurion_anim.lua —— 百夫长逐帧动作(后台驱动 Aseprite 自己的工具逐笔画; 原画见 ase_centurion_draw.lua, 11-27)
-- 每一帧按关节摆姿势: 腿 = 髋 → 膝 → 踝 → 脚(两段反解, 膝朝前), 持矛手 = 肩 → 肘 → 手(肘朝后), 长矛按手位置 + 角度;
-- 上身 / 头 / 盾整体按身体起伏平移, 头始终朝左。每帧从后往前逐部件画完(远腿 → 上身 → 持矛手 → 矛 → 拳 → 近腿 → 近肩甲 → 盾)。
-- 过程: K = 1 剪影 / 2 平涂 / 3 暗部 / 4 亮部 / 5 细节 / 6 描边, 同一段动画按 K 各画一遍, 每一步存一张整段帧表。
-- 用法: Aseprite.exe -b --script-param out=<目录> --script-param anim=walk --script tools/assetgen/ase_centurion_anim.lua
local OUT = app.params["out"] or "."
local ANIM = app.params["anim"] or "walk"

local function C(hex)
  return Color{r=tonumber(hex:sub(2,3),16), g=tonumber(hex:sub(4,5),16), b=tonumber(hex:sub(6,7),16), a=255}
end
local OL = C("#1c1722"); local WH = C("#ffffff")
local S0, S1, S2, S3, S4 = C("#2f3542"), C("#4b5466"), C("#717c92"), C("#a3adc0"), C("#dfe5ee")
local R0, R1, R2, R3, R4 = C("#3e0d14"), C("#6e1820"), C("#a3242a"), C("#cf3d33"), C("#ee6e4e")
local G0, G1, G2, G3 = C("#5a3c10"), C("#9a6c22"), C("#d4a23e"), C("#f6d878")
local L0, L1, L2, L3 = C("#2e1c12"), C("#523420"), C("#7c5232"), C("#a87648")
local K0, K1, K2, K3 = C("#5a2e20"), C("#94523a"), C("#c97f55"), C("#eab084")
local W0, W1, W2 = C("#3a2414"), C("#69442a"), C("#8f6640")
local SIL = C("#2a2230")

local K = 6            -- 当前画到第几步
local OX, OY = 0, 0    -- 当前部件平移
local function col(c) return (K == 1) and SIL or c end
local function P(c, pts)
  local t = {}
  for i, p in ipairs(pts) do t[i] = Point(math.floor(p[1] + OX + 0.5), math.floor(p[2] + OY + 0.5)) end
  app.useTool{tool="contour", color=col(c), points=t, brush=Brush(1)}
end
local function L(c, x1, y1, x2, y2)
  app.useTool{tool="pencil", color=col(c), points={Point(math.floor(x1+OX+0.5), math.floor(y1+OY+0.5)), Point(math.floor(x2+OX+0.5), math.floor(y2+OY+0.5))}, brush=Brush(1)}
end
local function D(c, x, y)
  app.useTool{tool="pencil", color=col(c), points={Point(math.floor(x+OX+0.5), math.floor(y+OY+0.5))}, brush=Brush(1)}
end
-- 一段有宽度的肢体(a → b, 两端宽 wa / wb)
local function seg(a, b, wa, wb)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local n = math.sqrt(dx * dx + dy * dy); if n < 0.01 then n = 0.01 end
  local nx, ny = -dy / n, dx / n
  return {{a[1] + nx * wa / 2, a[2] + ny * wa / 2}, {b[1] + nx * wb / 2, b[2] + ny * wb / 2},
          {b[1] - nx * wb / 2, b[2] - ny * wb / 2}, {a[1] - nx * wa / 2, a[2] - ny * wa / 2}}
end
-- 两段反解: 根 r, 末端 e, 两段长 l1 l2; forward = 关节偏向 x 小的一侧
local function ik(r, e, l1, l2, forward)
  local dx, dy = e[1] - r[1], e[2] - r[2]
  local d = math.sqrt(dx * dx + dy * dy)
  d = math.min(d, l1 + l2 - 0.01); d = math.max(d, math.abs(l1 - l2) + 0.01)
  local base = math.atan(dy, dx)
  local cb = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
  local b = math.acos(math.max(-1, math.min(1, cb)))
  local k1 = {r[1] + l1 * math.cos(base + b), r[2] + l1 * math.sin(base + b)}
  local k2 = {r[1] + l1 * math.cos(base - b), r[2] + l1 * math.sin(base - b)}
  if forward then return (k1[1] < k2[1]) and k1 or k2 else return (k1[1] > k2[1]) and k1 or k2 end
end

-- ── 腿: hip / ankle 由姿势给, lift = 脚尖下垂程度(0 = 平放) ──
local function leg(hip, ankle, near, lift)
  local knee = ik(hip, ankle, 13, 15, true)
  local thigh = seg(hip, knee, 10, 8)
  local shin = seg(knee, ankle, 8, 6)
  local skin = near and K2 or K1
  local steel = near and S2 or S1
  P(skin, thigh)                                             -- 大腿
  P(skin, seg({knee[1], knee[2] - 1}, {knee[1], knee[2] + 2}, 9, 9))   -- 膝
  P(steel, shin)                                             -- 护胫
  local ax, ay = ankle[1], ankle[2]
  local drop = lift or 0
  local foot = {{ax + 5, ay - 1}, {ax + 5, ay + 4}, {ax - 11, ay + 4 + drop}, {ax - 12, ay + 1 + drop}, {ax - 4, ay - 1}}
  P(near and L2 or L1, foot)                                 -- 凉鞋
  if K >= 3 then
    local mx, my = (hip[1] + knee[1]) / 2, (hip[2] + knee[2]) / 2
    P(near and K1 or K0, seg({mx + 2, hip[2]}, {knee[1] + 2, knee[2]}, 5, 4))   -- 大腿右半暗
    P(near and S1 or S0, seg({knee[1] + 2, knee[2] + 2}, {ax + 2, ay}, 3, 2))   -- 护胫右侧暗
    P(L0, {{ax + 5, ay + 3}, {ax - 11, ay + 3 + drop}, {ax - 11, ay + 4 + drop}, {ax + 5, ay + 4}})   -- 鞋底
  end
  if K >= 4 and near then
    L(K3, hip[1] - 4, hip[2] + 1, knee[1] - 3, knee[2] - 1)  -- 大腿受光
    L(S3, knee[1] - 3, knee[2] + 3, ax - 2, ay - 2)          -- 护胫亮边
    D(S4, knee[1] - 3, knee[2] + 5)
  end
  if K >= 5 then
    L(near and S1 or S0, knee[1] - 4, knee[2] + 2, knee[1] + 4, knee[2] + 2)   -- 护胫上沿
    L(L0, ax - 9, ay + 2 + drop, ax + 4, ay + 2)                               -- 绑带
    L(L0, ax - 3, ay - 1, ax - 1, ay + 4)
  end
end

-- ── 上身(躯干 / 远侧肩甲 / 短袍 / 垂带 / 腰带 / 脖子 / 头 / 冠饰), 坐标同原画, 整体平移 ──
local function upper()
  P(S2, {{52,54},{60,50},{80,49},{88,54},{89,64},{86,80},{56,82},{51,68}})       -- 躯干
  P(S2, {{79,47},{90,49},{95,56},{94,62},{87,62},{82,56}})                         -- 远侧肩甲
  P(R2, {{54,80},{86,78},{89,92},{51,94}})                                         -- 短袍
  P(K2, {{60,46},{68,46},{69,53},{60,53}})                                         -- 脖子
  P(S2, {{56,32},{61,28},{70,28},{75,32},{76,39},{72,42},{57,41},{55,37}})         -- 盔
  P(S2, {{71,38},{80,40},{82,46},{72,46}})                                         -- 护颈
  P(K2, {{52,38},{63,38},{64,50},{61,54},{55,54},{52,50},{50,45},{51,42}})         -- 脸
  P(S2, {{62,39},{66,39},{66,50},{63,51}})                                         -- 护颊
  P(R2, {{49,30},{50,25},{52,22},{54,23},{56,19},{58,20},{61,17},{63,18},{66,15},{68,17},{71,16},{73,18},{76,18},{78,21},{80,22},{82,26},{83,29},{80,31},{52,32}})   -- 冠饰
  P(G1, {{54,79},{87,77},{87,82},{54,84}})                                         -- 腰带
  if K >= 3 then
    P(S1, {{77,49},{80,49},{88,54},{89,64},{86,80},{77,81}})
    P(R1, {{52,89},{89,87},{89,92},{51,94}}); P(R1, {{79,79},{86,78},{89,92},{79,92}})
    P(S1, {{69,28},{75,32},{76,39},{72,42},{67,41}}); P(S1, {{76,43},{82,44},{82,46},{74,46}})
    P(K1, {{55,51},{63,50},{61,54},{55,54}}); P(K1, {{60,46},{63,46},{63,53},{60,53}})
    P(R1, {{70,18},{79,21},{83,27},{80,31},{70,31}})
    P(S0, {{90,52},{95,56},{94,62},{87,62}})
  end
  if K >= 4 then
    L(S3, 53, 54, 60, 51); L(S3, 60, 51, 79, 50); L(S3, 52, 57, 52, 66)
    P(S3, {{59,29},{63,28},{65,30},{59,32}}); D(S4, 60, 29); D(S4, 61, 29)
    L(S3, 80, 48, 90, 50)
    L(K3, 51, 40, 51, 45); L(K3, 52, 39, 56, 39)
    L(R3, 52, 23, 58, 19); L(R3, 58, 19, 66, 17); L(R4, 56, 20, 62, 18)
    L(G3, 55, 79, 70, 78)
    for _, y in ipairs({57, 63, 69, 75}) do L(S3, 55, y, 76, y - 1) end
  end
  if K >= 5 then
    for _, y in ipairs({60, 66, 72, 78}) do L(S1, 54, y, 86, y - 1) end
    for _, y in ipairs({58, 64, 70}) do D(G2, 57, y + 1); D(G2, 83, y) end
    for _, c in ipairs({{63,62},{69,61},{66,68}}) do
      P(G1, {{c[1]-2,c[2]-2},{c[1]+2,c[2]-2},{c[1]+2,c[2]+2},{c[1]-2,c[2]+2}}); D(G3, c[1]-1, c[2]-1); D(G0, c[1]+1, c[2]+1)
    end
    for i = 0, 10 do L((i % 2 == 0) and R1 or R0, 56 + i * 2, 30, 50 + i * 3, 20 + math.floor(math.abs(i - 5) * 0.8)) end
    for _, t in ipairs({{53,23},{59,19},{66,16},{73,18},{79,22}}) do D(R4, t[1], t[2]) end
    P(G1, {{52,37},{74,37},{74,39},{52,40}}); L(G3, 53, 37, 66, 37)
    D(OL, 54, 42); D(OL, 55, 42); D(WH, 54, 42); L(K0, 53, 41, 57, 40); L(K3, 50, 44, 50, 46); D(K1, 50, 47); L(K0, 52, 49, 56, 49)
  end
end
-- 垂带(跟着上身, 但下摆随步子轻摆 sway)
local function pteruges(sway)
  for x = 56, 84, 5 do
    local s = sway or 0
    P(L2, {{x,82},{x+3,82},{x+3+s,92},{x+s,92}})
    if K >= 4 then L(L3, x, 82, x + s, 91) end
    if K >= 3 then L(L1, x + 3, 83, x + 3 + s, 92) end
    if K >= 5 then D(G2, x + 1 + s, 91) end
  end
end

-- ── 持矛手 + 矛: shoulder 跟上身, hand 由姿势给, ang = 矛倾角(度, 0 = 竖直矛尖朝上, 正 = 矛尖往右倒) ──
local function rad(d) return d * math.pi / 180 end
local function arm(shoulder, hand)
  local elbow = ik(shoulder, hand, 11, 10, false)
  P(K2, seg(shoulder, elbow, 10, 8)); P(K2, seg(elbow, hand, 8, 7))
  if K >= 3 then P(K1, seg({shoulder[1] + 3, shoulder[2]}, {elbow[1] + 3, elbow[2]}, 4, 3)) end
  if K >= 4 then L(K3, shoulder[1] - 3, shoulder[2] + 1, elbow[1] - 3, elbow[2]) end
  if K >= 5 then L(L1, elbow[1] + (hand[1] - elbow[1]) * 0.55 - 4, elbow[2] + (hand[2] - elbow[2]) * 0.55, elbow[1] + (hand[1] - elbow[1]) * 0.55 + 4, elbow[2] + (hand[2] - elbow[2]) * 0.55) end
end
local function spear(hand, ang)
  local sx, sy = math.sin(rad(ang)), -math.cos(rad(ang))     -- 矛尖方向单位向量
  local tip = {hand[1] + sx * 58, hand[2] + sy * 58}
  local butt = {hand[1] - sx * 44, hand[2] - sy * 44}
  local px, py = -sy, sx
  P(W1, {{butt[1], butt[2]}, {tip[1], tip[2]}, {tip[1] + px, tip[2] + py}, {butt[1] + px, butt[2] + py}})   -- 杆(2 像素)
  local t0 = {tip[1] + sx * 1, tip[2] + sy * 1}
  local blade = {{t0[1] + sx * 17, t0[2] + sy * 17}, {t0[1] + sx * 11 + px * 3, t0[2] + sy * 11 + py * 3},
                 {t0[1] + sx * 3 + px * 3, t0[2] + sy * 3 + py * 3}, {t0[1], t0[2]}, {t0[1] + sx * 3 - px * 2.5, t0[2] + sy * 3 - py * 2.5},
                 {t0[1] + sx * 11 - px * 2.5, t0[2] + sy * 11 - py * 2.5}}
  P(S3, blade)                                                 -- 矛头
  if K >= 3 then L(W0, butt[1] + px, butt[2] + py, tip[1] + px, tip[2] + py) end
  if K >= 4 then L(S4, t0[1] + sx * 4 - px * 1.5, t0[2] + sy * 4 - py * 1.5, t0[1] + sx * 12 - px * 1.5, t0[2] + sy * 12 - py * 1.5); L(W2, hand[1] - sx * 2, hand[2] - sy * 2, tip[1] - sx * 3, tip[2] - sy * 3) end
  if K >= 5 then L(S1, t0[1] - px * 2, t0[2] - py * 2, t0[1] + px * 3, t0[2] + py * 3) end
end
local function fist(hand)
  P(K2, {{hand[1] - 4, hand[2] - 4}, {hand[1] + 5, hand[2] - 4}, {hand[1] + 6, hand[2] + 4}, {hand[1] - 3, hand[2] + 5}})
  if K >= 3 then P(K1, {{hand[1] + 2, hand[2] - 4}, {hand[1] + 5, hand[2] - 4}, {hand[1] + 6, hand[2] + 4}, {hand[1] + 2, hand[2] + 4}}) end
  if K >= 5 then L(K1, hand[1] - 3, hand[2] + 1, hand[1] + 4, hand[2] + 1); L(L1, hand[1] - 4, hand[2] - 6, hand[1] + 5, hand[2] - 6) end
end

-- ── 近侧肩甲 + 盾(整体平移) ──
local function shield()
  P(S2, {{47,55},{57,52},{61,57},{50,60}})                                         -- 近肩甲
  if K >= 4 then L(S3, 48, 55, 56, 52); L(S4, 49, 54, 53, 53) end
  P(R2, {{30,57},{34,54},{55,55},{58,58},{58,106},{55,109},{34,110},{30,107}})
  P(G1, {{30,57},{34,54},{55,55},{58,58},{58,60},{32,59}}); P(G1, {{30,105},{58,104},{55,109},{34,110}})
  if K >= 3 then P(R1, {{51,56},{55,55},{55,108},{51,108}}); P(R0, {{55,58},{58,60},{58,104},{55,106}}) end
  if K >= 4 then L(R3, 32, 61, 32, 104); L(R3, 33, 61, 33, 104); L(R4, 32, 62, 32, 76); L(G3, 33, 55, 54, 56) end
  if K >= 5 then
    L(S3, 30, 58, 30, 106); L(S1, 58, 59, 58, 105)
    P(G1, {{40,78},{47,78},{48,85},{40,86}}); D(G3, 41, 79); D(G3, 42, 79); D(G0, 46, 85)
    L(G2, 39, 76, 33, 68); L(G2, 39, 77, 34, 71); L(G2, 48, 76, 54, 68); L(G2, 48, 77, 53, 71)
    L(G2, 43, 88, 40, 95); L(G2, 40, 95, 44, 95); L(G2, 44, 95, 41, 102); L(G2, 43, 74, 43, 63)
  end
end

-- ── 一帧: pose = {by = 身体起伏, sh = {dx, dy} 盾, near = {hip, ankle, lift}, far = {...}, hand, ang, sway} ──
local function frame(p)
  local by = p.by or 0
  OX, OY = 0, 0; leg({72, 90 + by}, p.far.ankle, false, p.far.lift)
  OX, OY = 0, by; upper(); pteruges(p.sway)
  OX, OY = 0, 0
  local sh = {90, 58 + by}
  arm(sh, p.hand); spear(p.hand, p.ang or 0); fist(p.hand)
  leg({58, 90 + by}, p.near.ankle, true, p.near.lift)
  OX, OY = (p.sh and p.sh[1] or 0), by + (p.sh and p.sh[2] or 0); shield()
  OX, OY = 0, 0
end

-- ── 动作表 ──
local POSES = {}
-- 走路 8 帧(朝左走): 近侧脚 0 帧脚跟着地在前, 0→3 贴地往后滑, 4→7 抬起往前摆; 远侧脚差半个周期; 1 / 5 下沉, 3 / 7 抬起
do
  local A = 14        -- 步幅(像素, 相对髋; 第一版 10 太小, 两腿挤在一起)
  local nearHip, farHip = 58, 72
  local function footx(hx, ph)   -- ph 0..7
    if ph <= 3 then return hx - 6 - A + (2 * A) * ph / 4 else return hx - 6 + A - (2 * A) * (ph - 4) / 4 end
  end
  local LIFT = {[4] = 3, [5] = 8, [6] = 9, [7] = 4}
  local BOB = {[0] = 0, [1] = 2, [2] = 1, [3] = -1, [4] = 0, [5] = 2, [6] = 1, [7] = -1}
  local walk = {}
  for i = 0, 7 do
    local pn, pf = i, (i + 4) % 8
    local by = BOB[i]
    walk[#walk + 1] = {
      by = by,
      near = {ankle = {footx(nearHip, pn), 116 - (LIFT[pn] or 0)}, lift = (LIFT[pn] or 0) > 3 and 2 or 0},
      far  = {ankle = {footx(farHip, pf) + 4, 116 - (LIFT[pf] or 0)}, lift = (LIFT[pf] or 0) > 3 and 2 or 0},
      hand = {91 + ((i < 4) and (i - 1.5) or (5.5 - i)) * 0.8, 77 + by},
      ang = ((i < 4) and (1.5 - i) or (i - 5.5)) * 1.5,
      sway = ((i % 4) < 2) and 1 or 0,
      sh = {((i < 4) and (i - 1.5) or (5.5 - i)) * -0.6 - 2, -10},   -- 行进中盾提高 10(第一版盾把近侧腿全挡住)
    }
  end
  POSES.walk = walk
end

-- ── 画: 每个 K 一个 Sprite, 每帧一格; 存过程帧表(横排) ──
local poses = POSES[ANIM]
local N = #poses
local function render(kk, save_ase)
  K = kk
  local spr = Sprite(128, 128, ColorMode.RGB)
  for i = 2, N do spr:newEmptyFrame() end
  for i = 1, N do
    app.activeFrame = spr.frames[i]
    if spr.layers[1]:cel(i) == nil then spr:newCel(spr.layers[1], i) end
    frame(poses[i])
  end
  if kk == 6 then   -- 描边: 每帧外轮廓外一圈透明像素描深色
    local l2 = spr:newLayer(); l2.name = "描边"
    for i = 1, N do
      local flat = Image(spr.spec); flat:drawSprite(spr, i)
      local ol = Image(spr.spec)
      local function a(x, y)
        if x < 0 or y < 0 or x >= 128 or y >= 128 then return 0 end
        return app.pixelColor.rgbaA(flat:getPixel(x, y))
      end
      for y = 0, 127 do for x = 0, 127 do
        if a(x, y) == 0 and (a(x-1,y) > 0 or a(x+1,y) > 0 or a(x,y-1) > 0 or a(x,y+1) > 0) then
          ol:drawPixel(x, y, app.pixelColor.rgba(OL.red, OL.green, OL.blue, 255))
        end
      end end
      spr:newCel(l2, i, ol, Point(0, 0))
    end
    l2.stackIndex = 1   -- 描边垫在最底
  end
  local sheet = Image(128 * N, 128, ColorMode.RGB)
  for i = 1, N do
    local im = Image(spr.spec); im:drawSprite(spr, i)
    sheet:drawImage(im, Point((i - 1) * 128, 0))
  end
  sheet:saveAs(OUT .. "/" .. ANIM .. "_" .. kk .. ".png")
  if save_ase then spr:saveAs(OUT .. "/centurion_" .. ANIM .. ".aseprite") end
  spr:close()
end
for kk = 1, 6 do render(kk, kk == 6) end
print("done " .. ANIM .. " " .. N)
