-- fortune_strike.lua —— 财神龟金星 4 帧(24×24, 招财进宝升星落下的星)
-- ★11-27 用户否了竖劈新月剑光(「普攻明明是偏横扫…做一个爆点就好」), 普攻改用 fortune_hit.lua 的爆点;
--   本脚本里剑光那一段的产物 fortune-strike-slash.png 已不进游戏(不再拷进 assets), 只拿金星。
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出横条。方案书 20261126d「特效重做」第 1 行。
-- 由来(11-27): 原来借钻石龟的斩弧 diamond-slash.png 染金(画面发绿, 也违反「招牌不复用」)。
-- 做法(如实): 剑光 = 以 (CX,CY) 为圆心的一段圆弧(上 → 下斜劈, 朝右; 游戏里朝左时水平翻转),
--   每帧按「扫过进度 / 厚度包络 / 侵蚀阈值」逐像素判层: 外沿白热芯 → 亮黄 → 金 → 暗金尾 + 1 像素暗描边;
--   弧两头按 sin 收尖; 第 4~5 帧按固定哈希噪声侵蚀成碎块(不用随机数, 重跑逐字节相同)。
--   金星 = 十字四芒 + 中心白点, 4 帧 大 → 最大 → 收 → 残点。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_strike.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local OUTL = rgba(96, 52, 8, 255)
local TAIL = rgba(168, 96, 16, 255)
local GOLD = rgba(236, 168, 36, 255)
local BRIGHT = rgba(255, 222, 96, 255)
local CORE = rgba(255, 250, 214, 255)

local function hash(x, y)
  local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return h - math.floor(h)
end

---------------- 剑光 ----------------
local N, S = 6, 64
local CX, CY = 18.0, 30.0          -- 圆心偏左: 弧在右侧(朝目标)
local R = 29.0                     -- 外沿半径
local A0, A1 = -1.25, 1.35         -- 弧的起止角(弧度; 0 = 正右, 负 = 上方): 右上 → 右下
-- 每帧: 扫到哪(0~1) / 厚度倍数 / 侵蚀阈值(0 = 不侵蚀)
local FR = {
  {0.45, 0.70, 0.0},
  {0.80, 1.00, 0.0},
  {1.00, 1.00, 0.0},
  {1.00, 0.80, 0.0},
  {1.00, 0.65, 0.45},
  {1.00, 0.50, 0.75},
}
local W = 12.0                     -- 最厚处(像素)

local spr = Sprite(S * N, S, ColorMode.RGB)
spr.filename = OUT .. "/fortune_strike.aseprite"
local lay = spr.layers[1]
lay.name = "剑光"
local img = Image(S * N, S, ColorMode.RGB)
for f = 1, N do
  local sweep, thick, ero = FR[f][1], FR[f][2], FR[f][3]
  local amax = A0 + (A1 - A0) * sweep
  local ox = (f - 1) * S
  for y = 0, S - 1 do
    for x = 0, S - 1 do
      local dx, dy = x + 0.5 - CX, y + 0.5 - CY
      local r = math.sqrt(dx * dx + dy * dy)
      local a = math.atan(dy, dx)
      if a >= A0 and a <= amax then
        local k = (a - A0) / (A1 - A0)                       -- 0 弧头 → 1 弧尾(沿弧)
        local lead = (amax - a) / math.max(0.01, amax - A0)   -- 0 = 刀尖(正在扫的那头)
        local w = W * thick * math.sin(math.pi * math.min(1.0, k)) * (0.35 + 0.65 * math.min(1.0, lead * 3.0))
        local d = R - r                                      -- 离外沿多深
        if w > 0.6 and d >= -0.5 and d <= w * 2.2 then
          local col
          if d > w + 0.5 then                                -- 内侧半透明拖影(挥过去的速度感): 越往里越淡
            local al = math.floor(150 * (1.0 - (d - w) / (w * 1.2)) * (1.0 - ero))
            col = (al > 8) and rgba(236, 168, 36, al) or nil
          elseif d < 0.5 then col = OUTL
          elseif d < 2.4 then col = CORE
          elseif d < w * 0.5 then col = BRIGHT
          elseif d < w * 0.82 then col = GOLD
          else col = TAIL end
          if ero > 0 and hash(x, y) < ero * (0.6 + 0.4 * (1.0 - k)) then col = nil end
          if col ~= nil then img:drawPixel(ox + x, y, col) end
        end
      end
    end
  end
end
spr:newCel(lay, spr.frames[1], img, Point(0, 0))
spr:saveAs(OUT .. "/fortune_strike.aseprite")
img:saveAs(OUT .. "/fortune-strike-slash.png")

---------------- 金星 ----------------
local NS, SS = 4, 24
local ARM = {6, 10, 7, 3}          -- 每帧芒长
local star = Image(SS * NS, SS, ColorMode.RGB)
for f = 1, NS do
  local ox = (f - 1) * SS
  local c = 11
  local L = ARM[f]
  for i = -L, L do
    local t = math.abs(i) / L
    local col = (t < 0.25) and CORE or ((t < 0.6) and BRIGHT or GOLD)
    star:drawPixel(ox + c + i, c, col)
    star:drawPixel(ox + c, c + i, col)
    if f <= 2 and t < 0.5 then                   -- 前两帧芒根加粗一圈
      star:drawPixel(ox + c + i, c + 1, BRIGHT)
      star:drawPixel(ox + c + 1, c + i, BRIGHT)
    end
  end
  if f <= 3 then                                 -- 斜向小芒
    local d = math.floor(L * 0.4)
    for i = 1, d do
      star:drawPixel(ox + c + i, c + i, GOLD); star:drawPixel(ox + c - i, c - i, GOLD)
      star:drawPixel(ox + c + i, c - i, GOLD); star:drawPixel(ox + c - i, c + i, GOLD)
    end
  end
  star:drawPixel(ox + c, c, CORE)
end
star:saveAs(OUT .. "/fortune-strike-star.png")
local s2 = Sprite(SS * NS, SS, ColorMode.RGB)
s2:newCel(s2.layers[1], s2.frames[1], star, Point(0, 0))
s2:saveAs(OUT .. "/fortune_strike_star.aseprite")
print("ok")
