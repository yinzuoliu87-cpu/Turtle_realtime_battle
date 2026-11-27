-- fortune_beam.lua —— 财神龟【招财进宝】剑尖冲天的细金光柱 8 帧(每帧 16×128, 横排 128×128)
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出横条。方案书 20261126d「特效重做」第 4 行。
-- 做法(如实): 每帧一根竖直光柱, 底部 = 剑尖(画布底边), 往上长到第 TOP 行;
--   横向: 中间 2 像素白热芯 → 亮黄 → 金, 两侧半透明金辉往外衰减; 竖向: 顶端 6 像素收尖变淡; 每帧亮度 / 宽度按表变化,
--   第 3~5 帧芯上按固定哈希挖几处暗格当闪动(不用随机数, 重跑逐字节相同)。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_beam.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local N, W, H = 8, 16, 128
-- 每帧: 长到哪一行(越小越高) / 半宽(像素, 含辉光) / 亮度 0~1
local FR = {
  {84, 3.0, 0.8}, {30, 4.5, 1.0}, {0, 6.0, 1.0}, {0, 7.0, 0.95},
  {0, 6.5, 0.9}, {0, 5.5, 0.8}, {0, 4.0, 0.6}, {0, 2.5, 0.35},
}
local function hash(x, y)
  local h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return h - math.floor(h)
end
local spr = Sprite(W * N, H, ColorMode.RGB)
spr.filename = OUT .. "/fortune_beam.aseprite"
local img = Image(W * N, H, ColorMode.RGB)
for f = 1, N do
  local top, hw, br = FR[f][1], FR[f][2], FR[f][3]
  local ox = (f - 1) * W
  for y = top, H - 1 do
    local tipk = math.min(1.0, (y - top) / 6.0)                -- 顶端收尖
    local w = hw * (0.35 + 0.65 * tipk)
    for x = 0, W - 1 do
      local d = math.abs(x + 0.5 - W / 2)
      if d <= w then
        local k = d / math.max(0.5, w)                          -- 0 芯 → 1 边
        local r, g, b, a
        if d < 1.0 then r, g, b, a = 255, 252, 226, 255
        elseif k < 0.45 then r, g, b, a = 255, 224, 110, 255
        elseif k < 0.7 then r, g, b, a = 240, 172, 40, math.floor(220 * br)
        else r, g, b, a = 230, 150, 30, math.floor(120 * (1.0 - k) / 0.3 * br) end
        a = math.floor(a * (0.4 + 0.6 * tipk) * (d < 1.0 and 1.0 or br))
        if f >= 3 and f <= 5 and d < 1.0 and hash(x + f * 7, y) < 0.12 then r, g, b = 255, 210, 90 end
        if a > 6 then img:drawPixel(ox + x, y, rgba(r, g, b, a)) end
      end
    end
  end
end
spr:newCel(spr.layers[1], spr.frames[1], img, Point(0, 0))
spr:saveAs(OUT .. "/fortune_beam.aseprite")
img:saveAs(OUT .. "/fortune-beam.png")
print("ok")
