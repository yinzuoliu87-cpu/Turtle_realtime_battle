-- fortune_coin_spin.lua —— 财神龟梭哈投出去的金币(翻转 8 帧, 每帧 16×16, 横排 128×16)
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画(不花 PixelLab 额度), 存 .aseprite + 导出横条。
-- 由来(11-27): 梭哈投币原来用 assets/sprites/ui/coin.png —— 那是一张全黑的界面小图标(项目初建就在),
--   演示台录像里飞出去的是一串黑色空心圈。金币要跟财神龟壳上嵌的金币同一种: 金色圆币、深棕描边、
--   内圈一道暗金环、中间方孔(铜钱样式)、左上高光。飞行中绕竖轴翻转(会动的东西必须真的动, §10 第 4 条)。
-- 做法(如实): 每帧按「圆币绕竖轴转 θ」算椭圆宽度 |cos θ|, 逐像素判在哪一层(描边 / 外缘 / 币面 / 内环 / 方孔 / 高光)上色;
--   θ 每帧 22.5°, 8 帧转半圈(正反两面一样, 半圈就能无缝循环); 侧立那帧画成 2 像素宽的金边。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_coin_spin.lua
local OUT = app.params["out"]
local N, S = 8, 16
local C = 7.5          -- 圆心(像素中心坐标)
local R = 7.4          -- 半径
local rgba = app.pixelColor.rgba
local OUTLINE = rgba(74, 38, 10, 255)
local RIM = rgba(201, 132, 24, 255)
local FACE = rgba(255, 201, 56, 255)
local FACE_DK = rgba(230, 165, 36, 255)
local RING = rgba(176, 104, 16, 255)
local HOLE = rgba(92, 48, 12, 255)
local HI = rgba(255, 244, 170, 255)
local EDGE = rgba(236, 170, 40, 255)

local spr = Sprite(S * N, S, ColorMode.RGB)
spr.filename = OUT .. "/fortune_coin_spin.aseprite"
local lay = spr.layers[1]
lay.name = "金币"
local img = Image(S * N, S, ColorMode.RGB)

for f = 0, N - 1 do
  local w = math.abs(math.cos(f * math.pi / N))
  local ox = f * S
  if w < 0.2 then
    -- 侧立: 一根 2 像素宽的金边(上下收圆)
    for y = 1, S - 2 do
      img:drawPixel(ox + 7, y, (y == 1 or y == S - 2) and OUTLINE or EDGE)
      img:drawPixel(ox + 8, y, (y == 1 or y == S - 2) and OUTLINE or RIM)
      img:drawPixel(ox + 6, y, OUTLINE)
      img:drawPixel(ox + 9, y, OUTLINE)
    end
  else
    local rx = math.max(1.5, R * w)
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        local dx, dy = (x - C) / rx, (y - C) / R
        local d = math.sqrt(dx * dx + dy * dy)
        local col = nil
        if d <= 1.0 then
          local px_edge = 1.0 / math.min(rx, R)            -- 一个像素在归一化半径里占多少
          if d > 1.0 - px_edge * 1.1 then
            col = OUTLINE
          elseif d > 1.0 - px_edge * 2.1 then
            col = RIM
          elseif d > 0.50 and d < 0.50 + px_edge * 1.1 then
            col = RING
          else
            col = (dx + dy < -0.35) and FACE or FACE_DK  -- 左上亮右下暗
            if math.abs(x - C) <= 1.0 * w + 0.1 and math.abs(y - C) <= 1.0 then
              col = HOLE                                  -- 方孔(跟着转窄)
            end
            if w > 0.55 and d > 0.58 and d < 0.86 and dx < -0.25 and dy < -0.25 then
              col = HI                                    -- 左上一弯高光(正面时才有)
            end
          end
        end
        if col ~= nil then img:drawPixel(ox + x, y, col) end
      end
    end
  end
end
spr:newCel(lay, spr.frames[1], img, Point(0, 0))
spr:saveAs(OUT .. "/fortune_coin_spin.aseprite")
img:saveAs(OUT .. "/fortune-coin-spin.png")
print("ok " .. N .. " frames")
