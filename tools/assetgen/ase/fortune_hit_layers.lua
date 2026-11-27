-- fortune_hit_layers.lua —— 财神龟普攻命中的分层素材(11-27 用户「做这种命中特效，难道也是一层的事情吗？」)
--   ③ 横扫拖痕 fortune-hit-streak.png 5 帧(每帧 64×32): 从命中点往挥剑方向(画布右)拉出 4 道横向速度线, 头亮尾淡
--   ④ 火花     fortune-hit-spark.png  4 帧(每帧 8×8):  金色小方火花 亮 → 收 → 暗 → 余点(粒子用, 代码抛)
--   ⑤ 冲击环   fortune-hit-ring.png   5 帧(每帧 64×64): 贴地俯视的金色细环, 由小到大、由实到断
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出横条。做法(如实): 逐像素按公式判层上色, 不用随机数。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_hit_layers.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local function hash(x, y)
  local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return h - math.floor(h)
end
local function save(img, w, h, name)
  local s = Sprite(w, h, ColorMode.RGB)
  s:newCel(s.layers[1], s.frames[1], img, Point(0, 0))
  s:saveAs(OUT .. "/" .. name .. ".aseprite")
  img:saveAs(OUT .. "/" .. name:gsub("_", "-") .. ".png")
end

---------------- ③ 横扫拖痕 ----------------
do
  local N, W, H = 5, 64, 32
  local LINES = { {16, 0.95}, {12, 0.7}, {20, 0.75}, {9, 0.45} }    -- 每道: 所在行 / 长度系数
  local HEAD = {22, 44, 60, 64, 64}                                  -- 每帧线头跑到哪一列
  local TAIL = {0, 8, 26, 44, 56}                                    -- 每帧线尾在哪一列
  local img = Image(W * N, H, ColorMode.RGB)
  for f = 1, N do
    local ox = (f - 1) * W
    for li, L in ipairs(LINES) do
      local y, lk = L[1], L[2]
      local head = math.floor(HEAD[f] * lk + 0.5)
      local tail = math.floor(TAIL[f] * lk + 0.5)
      for x = tail, head - 1 do
        local t = (x - tail) / math.max(1, head - tail)               -- 0 尾 → 1 头
        local a = math.floor(255 * (0.25 + 0.75 * t))
        local col
        if t > 0.85 then col = rgba(255, 252, 228, a)
        elseif t > 0.5 then col = rgba(255, 222, 96, a)
        else col = rgba(236, 160, 36, math.floor(a * 0.8)) end
        if f >= 4 and hash(x + li * 13, f) < 0.35 then col = nil end   -- 收尾两帧断开
        if col ~= nil then
          img:drawPixel(ox + x, y, col)
          if li == 1 and t > 0.5 then img:drawPixel(ox + x, y + 1, rgba(240, 172, 40, math.floor(a * 0.6))) end   -- 主线加粗一行
        end
      end
    end
  end
  save(img, W * N, H, "fortune_hit_streak")
end

---------------- ④ 火花 ----------------
do
  local N, S = 4, 8
  local img = Image(S * N, S, ColorMode.RGB)
  local R = {3, 2, 1, 0}
  for f = 1, N do
    local ox = (f - 1) * S
    local r = R[f]
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local d = math.max(math.abs(x - 3.5), math.abs(y - 3.5))
        if d <= r + 0.5 then
          local col = (d < 1.0) and rgba(255, 250, 220, 255) or ((d < 2.0) and rgba(255, 220, 90, 255) or rgba(232, 150, 30, 255))
          if f == 3 then col = rgba(240, 172, 40, 255) end
          img:drawPixel(ox + x, y, col)
        end
      end
    end
    if f == 4 then img:drawPixel(ox + 3, 3, rgba(200, 120, 20, 255)) end
  end
  save(img, S * N, S, "fortune_hit_spark")
end

---------------- ⑤ 冲击环 ----------------
do
  local N, S = 5, 64
  local RR = {8, 15, 21, 26, 30}
  local TH = {2.6, 2.2, 1.8, 1.3, 1.0}
  local AL = {255, 235, 200, 150, 90}
  local img = Image(S * N, S, ColorMode.RGB)
  for f = 1, N do
    local ox = (f - 1) * S
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local dx, dy = x + 0.5 - 32, y + 0.5 - 32
        local r = math.sqrt(dx * dx + dy * dy)
        local d = math.abs(r - RR[f])
        if d < TH[f] then
          local a = AL[f]
          local col = (d < TH[f] * 0.4) and rgba(255, 236, 150, a) or rgba(236, 166, 40, math.floor(a * 0.8))
          if f >= 4 and hash(math.floor(math.atan(dy, dx) * 8.0), f) < 0.4 then col = nil end
          if col ~= nil then img:drawPixel(ox + x, y, col) end
        end
      end
    end
  end
  save(img, S * N, S, "fortune_hit_ring")
end
print("ok")
