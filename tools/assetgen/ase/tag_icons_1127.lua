-- tag_icons_1127.lua —— 旧 10 个羁绊图标(剑 盾 枪 弓箭 法器 灵物 奇械 食物 遗物 药水)在 Aseprite 里按层画出来。
-- 输入: tools/assetgen/tag_icons_1127.py 定好的格子图(每格一个字符 = 材质 + 色阶)与色板。
-- 每个图标一个 .aseprite, 6 个图层按画师顺序逐层落笔: 剪影 → 平涂 → 暗部 → 亮部 → 高光细节 → 描边;
--   每落完一层导出一张过程图 <名>-step<k>.png; 最后合层导出 tag-<名>.png(32×32, 硬边, 无半透明)。
-- 后台跑: Aseprite.exe -b --script-param grid=<格子目录> --script-param out=<输出目录> --script tools/assetgen/ase/tag_icons_1127.lua
local GRID = app.params["grid"]
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local NAMES = {"sword", "shield", "gun", "bow", "staff", "spirit", "gadget", "food", "relic", "potion"}

-- 色板: 字符 → {r,g,b, 色阶}; 色阶 = 该字符在所属材质 4 个字符里的位置(0 暗 1 本色 2 亮 3 高光), 描边 ~ = 9
local PAL = {}
local idx = 0
for line in io.lines(GRID .. "/palette.txt") do
  local c, r, g, b = line:match("^(%S+) (%d+) (%d+) (%d+)")
  if c ~= nil then
    if c == "~" then
      PAL[c] = {tonumber(r), tonumber(g), tonumber(b), 9}
    else
      PAL[c] = {tonumber(r), tonumber(g), tonumber(b), idx % 4}
      idx = idx + 1
    end
  end
end
PAL["~"] = PAL["~"] or {59, 37, 49, 9}

local STEPS = {
  {"剪影", function(t) return t ~= 9 end, "sil"},
  {"平涂", function(t) return t ~= 9 end, "flat"},
  {"暗部", function(t) return t == 0 end, "own"},
  {"亮部", function(t) return t == 2 end, "own"},
  {"高光细节", function(t) return t == 3 end, "own"},
  {"描边", function(t) return t == 9 end, "own"},
}

-- 平涂用的本色: 同一材质 4 个字符里的第 2 个(色阶 1)
local function base_of(ch)
  local order = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-+=<>?/"
  local p = order:find(ch, 1, true)
  if p == nil then return PAL[ch] end
  local b = order:sub(p - ((p - 1) % 4) + 1, p - ((p - 1) % 4) + 1)
  return PAL[b] or PAL[ch]
end

for _, name in ipairs(NAMES) do
  local rows = {}
  for line in io.lines(GRID .. "/" .. name .. ".txt") do
    if #line > 0 then rows[#rows + 1] = line end
  end
  local W, H = #rows[1], #rows
  local spr = Sprite(W, H, ColorMode.RGB)
  spr.layers[1].name = STEPS[1][1]
  for k = 2, #STEPS do
    local l = spr:newLayer()
    l.name = STEPS[k][1]
  end
  for k, st in ipairs(STEPS) do
    local img = Image(W, H, ColorMode.RGB)
    for y = 1, H do
      for x = 1, W do
        local ch = rows[y]:sub(x, x)
        local p = PAL[ch]
        if p ~= nil and st[2](p[4]) then
          local col
          if st[3] == "sil" then col = rgba(60, 60, 60, 255)
          elseif st[3] == "flat" then local b = base_of(ch); col = rgba(b[1], b[2], b[3], 255)
          else col = rgba(p[1], p[2], p[3], 255) end
          img:drawPixel(x - 1, y - 1, col)
        end
      end
    end
    spr:newCel(spr.layers[k], spr.frames[1], img, Point(0, 0))
    if k == 2 then spr.layers[1].isVisible = false end   -- 平涂落完, 剪影只留作底稿
    local flat = Image(spr.spec)
    flat:drawSprite(spr, 1)
    flat:saveAs(OUT .. "/" .. name .. "-step" .. k .. ".png")
  end
  spr:saveAs(OUT .. "/tag-" .. name .. ".aseprite")
  local final = Image(spr.spec)
  final:drawSprite(spr, 1)
  final:saveAs(OUT .. "/tag-" .. name .. ".png")
  spr:close()
end
print("ok")
