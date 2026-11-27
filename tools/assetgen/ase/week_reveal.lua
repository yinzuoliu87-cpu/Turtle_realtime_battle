-- week_reveal.lua —— 本周羁绊开周揭晓的卡片素材(方案书 docs/plans/20261127b-本周羁绊开周揭晓.md 分段表)
--   week-card-back.png   96×128   卡背: 深海蓝底 + 双层金边 + 四角铆钉 + 中间龟壳六边形徽记(金线 + 暗金填)
--   week-card-front.png  96×128   卡面: 深色羊皮纸底(上浅下深) + 双层金边 + 上部图标窗(暗底金框) + 名字横条
--   week-card-flash.png  6 帧 × 112×144   翻开那一下沿卡框亮起的金光圈: 贴边亮 → 往外扩一圈变淡 → 散成碎点
--   week-shard.png       4 帧 × 8×8   溶解碎片: 竖长金色菱形 白芯 → 金 → 暗金 → 余点
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出 png。做法(如实): 逐像素按公式判层上色, 不用随机数, 重跑逐字节相同。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/week_reveal.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local DARK = rgba(28, 16, 6, 255)
local GOLD_D = rgba(150, 92, 22, 255)
local GOLD = rgba(226, 164, 48, 255)
local GOLD_L = rgba(255, 220, 120, 255)
local WHITE = rgba(255, 248, 220, 255)
local function save(img, w, h, name)
  local s = Sprite(w, h, ColorMode.RGB)
  s:newCel(s.layers[1], s.frames[1], img, Point(0, 0))
  s:saveAs(OUT .. "/" .. name .. ".aseprite")
  img:saveAs(OUT .. "/" .. name:gsub("_", "-") .. ".png")
end

-- 共用: 双层金边 + 四角铆钉(b = 离外沿几像素)
local function frame(img, W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local e = math.min(x, y, W - 1 - x, H - 1 - y)
      local col = nil
      if e == 0 then col = DARK
      elseif e == 1 then col = GOLD_D
      elseif e == 2 then col = (x + y) % 2 == 0 and GOLD_L or GOLD
      elseif e == 3 then col = GOLD_D
      elseif e == 6 then col = GOLD_D
      end
      if col ~= nil then img:drawPixel(x, y, col) end
    end
  end
  for _, c in ipairs({{5, 5}, {W - 6, 5}, {5, H - 6}, {W - 6, H - 6}}) do
    for dy = -1, 1 do for dx = -1, 1 do
      img:drawPixel(c[1] + dx, c[2] + dy, (dx == 0 and dy == 0) and WHITE or GOLD)
    end end
  end
end

---------------- 卡背 ----------------
do
  local W, H = 96, 128
  local img = Image(W, H, ColorMode.RGB)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local k = y / H
      local col = rgba(math.floor(18 + 10 * k), math.floor(34 + 14 * k), math.floor(62 + 18 * k), 255)
      if ((x + y) % 8 == 0) and x > 8 and x < W - 9 and y > 8 and y < H - 9 then col = rgba(30, 52, 86, 255) end   -- 斜纹
      img:drawPixel(x, y, col)
    end
  end
  frame(img, W, H)
  -- 龟壳六边形徽记
  local cx, cy, R = 47.5, 63.5, 22.0
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local dx, dy = math.abs(x + 0.5 - cx), math.abs(y + 0.5 - cy)
      local hex = math.max(dx * 0.866 + dy * 0.5, dy)                 -- 尖朝左右的六边形距离
      if hex <= R + 0.5 then
        local col
        if hex > R - 1.0 then col = DARK
        elseif hex > R - 3.0 then col = GOLD
        elseif hex > R - 4.0 then col = GOLD_D
        else
          local inner = math.max(dx * 0.866 + dy * 0.5, dy)
          col = rgba(70, 46, 16, 255)
          if math.abs(inner - 9.0) < 0.8 then col = GOLD end            -- 中间小六边形金线
          if inner < 8.2 then col = rgba(120, 78, 20, 255) end
          if inner < 3.0 then col = GOLD_L end
          if (dx < 0.8 or math.abs(dy - dx * 0.577) < 0.7) and inner > 9.5 then col = GOLD_D end   -- 放射壳纹
        end
        img:drawPixel(x, y, col)
      end
    end
  end
  save(img, W, H, "week_card_back")
end

---------------- 卡面 ----------------
do
  local W, H = 96, 128
  local img = Image(W, H, ColorMode.RGB)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local k = y / H
      img:drawPixel(x, y, rgba(math.floor(64 - 30 * k), math.floor(46 - 22 * k), math.floor(30 - 14 * k), 255))
    end
  end
  frame(img, W, H)
  -- 图标窗(放 32 像素图标 ×1, 窗 40×40): x 28..67, y 12..51
  for y = 12, 51 do
    for x = 28, 67 do
      local e = math.min(x - 28, y - 12, 67 - x, 51 - y)
      local col = rgba(20, 14, 10, 255)
      if e == 0 then col = DARK elseif e == 1 then col = GOLD elseif e == 2 then col = GOLD_D end
      img:drawPixel(x, y, col)
    end
  end
  -- 名字横条 y 55..70(16 像素高: 放大 1.75 倍后 28 像素, 装得下 19 号字; 11-27 用户「文字确定放对位置了吗」—— 原来 12 像素高, 字掉出下沿)
  for y = 55, 70 do
    for x = 8, 87 do
      local col = rgba(110, 30, 24, 255)
      if y == 55 or y == 70 then col = GOLD_D elseif y == 56 then col = rgba(150, 48, 36, 255) end
      img:drawPixel(x, y, col)
    end
  end
  save(img, W, H, "week_card_front")
end

---------------- 翻开金光圈 ----------------
do
  local N, W, H = 6, 112, 144
  local OFF = {0, 1, 3, 5, 7, 9}          -- 光圈离卡边(卡在中间 96×128, 四周各留 8)
  local TH = {3.0, 3.5, 3.0, 2.2, 1.5, 1.0}
  local AL = {255, 255, 220, 160, 100, 50}
  local img = Image(W * N, H, ColorMode.RGB)
  local function hash(x, y)
    local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return h - math.floor(h)
  end
  for f = 1, N do
    local ox = (f - 1) * W
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        -- 离卡外沿(8..103, 8..135)的有符号距离: 外为正
        local dx = math.max(8 - x, x - 103, 0)
        local dy = math.max(8 - y, y - 135, 0)
        local d = (dx > 0 or dy > 0) and math.sqrt(dx * dx + dy * dy) or -math.min(x - 8, 103 - x, y - 8, 135 - y)
        local g = math.abs(d - OFF[f])
        if g < TH[f] then
          local a = math.floor(AL[f] * (1.0 - g / TH[f] * 0.6))
          local col = (g < TH[f] * 0.35) and rgba(255, 246, 200, a) or rgba(255, 196, 70, math.floor(a * 0.85))
          if f >= 5 and hash(x, y + f) < 0.5 then col = nil end
          if col ~= nil then img:drawPixel(ox + x, y, col) end
        end
      end
    end
  end
  save(img, W * N, H, "week_card_flash")
end

---------------- 溶解碎片 ----------------
do
  local N, S = 4, 8
  local img = Image(S * N, S, ColorMode.RGB)
  local R = {3.5, 3.0, 2.0, 0.8}
  for f = 1, N do
    local ox = (f - 1) * S
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local u, v = x + 0.5 - 4, y + 0.5 - 4.5
        if math.abs(u) * 1.6 + math.abs(v) <= R[f] then   -- 竖长菱形碎片
          local col = (f == 1 and math.abs(u) < 1 and v > -1) and WHITE or ((f <= 2) and GOLD_L or ((f == 3) and GOLD or GOLD_D))
          img:drawPixel(ox + x, y, col)
        end
      end
    end
  end
  save(img, S * N, S, "week_shard")
end
print("ok")
