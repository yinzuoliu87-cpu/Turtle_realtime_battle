-- fortune_dice.lua —— 财神龟【骰子】头顶翻滚落定的骰子 6 帧(每帧 24×24, 横排 144×24)
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出横条。方案书 20261126d「特效重做」第 2 行。
-- 做法(如实): 每帧给出骰子各可见面的多边形(正面 / 顶面 / 侧面), 逐像素判点在哪个面里上色(正面白、顶面浅灰、侧面暗灰),
--   1 像素深棕描边; 面上的红点按面心 + 点数表摆; 0~3 帧翻滚(角朝前 / 正面 + 顶面 / 角朝前 / 正面 + 侧面), 4 帧落定弹起 2 像素, 5 帧落定(6 点朝前)。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_dice.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local OUTL = rgba(64, 38, 24, 255)
local FACE = rgba(250, 246, 236, 255)
local TOP = rgba(222, 216, 204, 255)
local SIDE = rgba(186, 178, 166, 255)
local PIP = rgba(206, 32, 44, 255)
local N, S = 6, 24

local function inside(px, py, poly)
  local c = false
  local j = #poly
  for i = 1, #poly do
    local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then c = not c end
    j = i
  end
  return c
end

-- 点数布局(面内归一化 -1..1)
local PIPS = {
  [1] = {{0, 0}},
  [2] = {{-0.5, -0.5}, {0.5, 0.5}},
  [3] = {{-0.55, -0.55}, {0, 0}, {0.55, 0.55}},
  [4] = {{-0.5, -0.5}, {0.5, -0.5}, {-0.5, 0.5}, {0.5, 0.5}},
  [6] = {{-0.5, -0.6}, {0.5, -0.6}, {-0.5, 0}, {0.5, 0}, {-0.5, 0.6}, {0.5, 0.6}},
}

-- 每帧: 面列表 {多边形, 颜色, 点数或 nil, 面心 x, 面心 y, 半宽, 半高}
local function square(cx, cy, h, dy) return {{cx - h, cy - h + dy}, {cx + h, cy - h + dy}, {cx + h, cy + h + dy}, {cx - h, cy + h + dy}} end
local FR = {
  { {{{12, 3}, {21, 12}, {12, 21}, {3, 12}}, FACE, 3, 12, 12, 5, 5} },
  { {{{4, 4}, {19, 4}, {21, 8}, {6, 8}}, TOP, nil}, {square(12, 14, 7, 0), FACE, 2, 12, 14, 7, 7} },
  { {{{12, 2}, {22, 12}, {12, 22}, {2, 12}}, FACE, 1, 12, 12, 5, 5} },
  { {{{19, 6}, {22, 4}, {22, 18}, {19, 21}}, SIDE, nil}, {square(11, 13, 8, 0), FACE, 4, 11, 13, 8, 8} },
  { {square(12, 12, 8, -2), FACE, 6, 12, 10, 8, 8} },
  { {square(12, 13, 8, 0), FACE, 6, 12, 13, 8, 8} },
}

local spr = Sprite(S * N, S, ColorMode.RGB)
spr.filename = OUT .. "/fortune_dice.aseprite"
local img = Image(S * N, S, ColorMode.RGB)
for f = 1, N do
  local ox = (f - 1) * S
  for _, fc in ipairs(FR[f]) do
    local poly, col, pips, cx, cy, hw, hh = fc[1], fc[2], fc[3], fc[4], fc[5], fc[6], fc[7]
    for y = 0, S - 1 do
      for x = 0, S - 1 do
        if inside(x + 0.5, y + 0.5, poly) then
          -- 描边: 四邻有一个不在面里 = 边
          local edge = not (inside(x + 1.5, y + 0.5, poly) and inside(x - 0.5, y + 0.5, poly) and inside(x + 0.5, y + 1.5, poly) and inside(x + 0.5, y - 0.5, poly))
          img:drawPixel(ox + x, y, edge and OUTL or col)
        end
      end
    end
    if pips ~= nil then
      for _, p in ipairs(PIPS[pips]) do
        local px = math.floor(cx + p[1] * hw * 0.85 + 0.5)
        local py = math.floor(cy + p[2] * hh * 0.85 + 0.5)
        img:drawPixel(ox + px, py, PIP); img:drawPixel(ox + px - 1, py, PIP)
        img:drawPixel(ox + px, py - 1, PIP); img:drawPixel(ox + px - 1, py - 1, PIP)
      end
    end
  end
end
spr:newCel(spr.layers[1], spr.frames[1], img, Point(0, 0))
spr:saveAs(OUT .. "/fortune_dice.aseprite")
img:saveAs(OUT .. "/fortune-dice-roll.png")
print("ok")
