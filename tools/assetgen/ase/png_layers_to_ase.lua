-- png_layers_to_ase.lua —— 把一组分层 PNG(同尺寸)按顺序在 Aseprite 里叠成一个分层 .aseprite, 再导出合成 PNG 核对。
-- 用在按几何判层上色的图标(例: tools/assetgen/eq010_icon.py 出的 layer-*.png): 源文件按层留在仓库里, 以后在 Aseprite 里能逐层改。
-- 后台跑: Aseprite.exe -b --script-param dir=<分层 PNG 目录> --script-param layers=glow,blade,hilt,guard,outline,spark
--          --script-param out=<.aseprite 路径> --script tools/assetgen/ase/png_layers_to_ase.lua
local dir = app.params["dir"]
local out = app.params["out"]
local names = {}
for n in string.gmatch(app.params["layers"], "[^,]+") do names[#names + 1] = n end
local first = Image{ fromFile = dir .. "/layer-" .. names[1] .. ".png" }
local spr = Sprite(first.width, first.height, ColorMode.RGB)
spr.layers[1].name = names[1]
for k = 2, #names do spr:newLayer().name = names[k] end
for k, n in ipairs(names) do
  local img = Image{ fromFile = dir .. "/layer-" .. n .. ".png" }
  spr:newCel(spr.layers[k], spr.frames[1], img, Point(0, 0))
end
spr:saveAs(out)
local flat = Image(spr.spec)
flat:drawSprite(spr, 1)
flat:saveAs(string.gsub(out, "%.aseprite$", "-flat.png"))
spr:close()
print("ok")
