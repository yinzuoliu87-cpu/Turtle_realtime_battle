-- fortune_idle.lua —— 财神龟待机 8 帧(CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐帧改像素, 不花 PixelLab 额度)
-- 后台跑: Aseprite.exe -b --script-param base=<定稿 152×152 png> --script-param out=<目录> --script tools/assetgen/ase/fortune_idle.lua
-- 做法(如实): 以定稿(tools/assetgen/ai_src/fortune/fortE_base.png, pixen 出图)为第 0 帧, 每帧在 Aseprite 的 Image 上逐像素改:
--   ① 呼吸: 腰线(WAIST)以上整块上抬 BREATH[f] 像素(第 2~5 帧抬 1), 腰线那一行用下一行补齐(不留缝)
--   ② 墨镜反光: 第 3~4 帧两格白色高光从左往右扫过镜片
-- 产物: <out>/fortune_idle.aseprite(8 帧) + <out>/fortune_idle_NN.png(每帧一张, 打包脚本读)
local BASE = app.params["base"]
local OUT = app.params["out"]
local WAIST = 116                         -- 152 帧里胸口与腰带之间那一行(放大定稿量的: 腰带上沿约第 117 行; 手和剑在下面不动)
local BREATH = {0, 0, 1, 1, 1, 1, 0, 0}
local GLINT = { [4] = {62, 88}, [5] = {69, 88} }   -- 帧号(1 起) → 高光左上角(镜片 x 60~78 · y 86~92)

local src = Image{ fromFile = BASE }
local W, H = src.width, src.height
local spr = Sprite(W, H, ColorMode.RGB)
spr.filename = OUT .. "/fortune_idle.aseprite"
for i = 2, 8 do spr:newEmptyFrame() end
local lay = spr.layers[1]
lay.name = "待机"
local white = app.pixelColor.rgba(255, 255, 255, 255)

for f = 1, 8 do
  local img = Image(W, H, ColorMode.RGB)
  local up = BREATH[f]
  for y = 0, H - 1 do
    local sy = y
    if y < WAIST then
      sy = y + up                               -- 腰线以上整块往上抬
    elseif y == WAIST and up > 0 then
      sy = y + 1                                -- 补缝
    end
    if sy < H then
      for x = 0, W - 1 do
        img:drawPixel(x, y, src:getPixel(x, sy))
      end
    end
  end
  local g = GLINT[f]
  if g then
    local gx, gy = g[1], g[2] - up
    for dx = 0, 1 do
      if app.pixelColor.rgbaA(img:getPixel(gx + dx, gy)) > 0 then img:drawPixel(gx + dx, gy, white) end
      if app.pixelColor.rgbaA(img:getPixel(gx + dx + 1, gy + 1)) > 0 then img:drawPixel(gx + dx + 1, gy + 1, white) end
    end
  end
  spr:newCel(lay, spr.frames[f], img, Point(0, 0))
  img:saveAs(string.format("%s/fortune_idle_%02d.png", OUT, f - 1))
end
spr:saveAs(OUT .. "/fortune_idle.aseprite")
print("ok 8 frames")
