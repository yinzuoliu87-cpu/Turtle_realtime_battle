-- header_bar.lua —— 二级页顶栏素材(先用在图鉴): 横幅 / 返回键 / 回主页键 / 页签(选中 · 未选中)
-- 用户 11-27「顶上图鉴这个箭头…商业游戏不会像我们这个顶部这样子去做的吧？」→ 方向认可「你做一个看看」。
-- 参考研究 docs/studies/20261127-参考-装备稀有度框与二级页顶栏.md: 返回键要有底板(荒野乱斗斜切面板 / 像素风带框小按钮), 顶栏是一条带主题的横幅, 页签贴在内容上沿。
-- 配色取图鉴现有: 深海蓝底 + 内容框那道暗金边(#9d892e) + 页签金(#ffd93d)。
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 分层存 .aseprite + 导出原尺寸 png 与 2 倍 png(游戏用 2 倍, 像素均匀)。
--   做法(如实): 逐像素按公式判层上色; 箭头 / 房子图标是我逐格定的格子图。不用随机数, 重跑逐字节相同。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/header_bar.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local OUTL = rgba(5, 10, 16, 255)
local NAVY_T = rgba(11, 20, 32, 255)
local NAVY_B = rgba(20, 34, 56, 255)
local NAVY_HI = rgba(34, 54, 84, 255)
local NAVY_DK = rgba(8, 15, 24, 255)
local GOLD_DK = rgba(92, 79, 24, 255)
local GOLD = rgba(157, 137, 46, 255)
local GOLD_HI = rgba(255, 217, 61, 255)
local CREAM = rgba(244, 236, 216, 255)
local CREAM_SH = rgba(176, 160, 128, 255)

local function lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end
local function mix(c1, c2, t)
  local P = app.pixelColor
  return rgba(lerp(P.rgbaR(c1), P.rgbaR(c2), t), lerp(P.rgbaG(c1), P.rgbaG(c2), t), lerp(P.rgbaB(c1), P.rgbaB(c2), t), 255)
end

-- 分层落笔 + 存过程图 + .aseprite + 原尺寸 / 2 倍 png
local function save_layers(name, W, H, layer_names, layers)
  local spr = Sprite(W, H, ColorMode.RGB)
  spr.layers[1].name = layer_names[1]
  for k = 2, #layer_names do spr:newLayer().name = layer_names[k] end
  for k = 1, #layer_names do
    spr:newCel(spr.layers[k], spr.frames[1], layers[k], Point(0, 0))
    local f = Image(spr.spec); f:drawSprite(spr, 1)
    f:saveAs(OUT .. "/" .. name .. "-step" .. k .. ".png")
  end
  spr:saveAs(OUT .. "/" .. name:gsub("-", "_") .. ".aseprite")
  local f = Image(spr.spec); f:drawSprite(spr, 1)
  f:saveAs(OUT .. "/" .. name .. ".png")
  spr:resize(W * 2, H * 2)
  local f2 = Image(spr.spec); f2:drawSprite(spr, 1)
  f2:saveAs(OUT .. "/" .. name .. "@2x.png")
  spr:close()
end

local function new_layers(n, W, H)
  local t = {}
  for k = 1, n do t[k] = Image(W, H, ColorMode.RGB) end
  return t
end

---------------- 横幅(九宫格横向平铺: 16 宽一节) ----------------
do
  local W, H = 16, 44
  local L = new_layers(4, W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      -- ① 底: 上深下浅的海蓝
      if y <= 38 then L[1]:drawPixel(x, y, mix(NAVY_T, NAVY_B, y / 38)) end
      -- ② 顶上一行高光(波纹试过: 断断续续像杂线, 去掉)
      if y == 1 then L[2]:drawPixel(x, y, NAVY_HI) end
      -- ③ 底沿金边: 39 暗线 / 40 亮金(隔格高光) / 41 金 / 42 暗金
      if y == 39 then L[3]:drawPixel(x, y, OUTL)
      elseif y == 40 then L[3]:drawPixel(x, y, (x % 4 == 0) and GOLD_HI or mix(GOLD, GOLD_HI, 0.5))
      elseif y == 41 then L[3]:drawPixel(x, y, GOLD)
      elseif y == 42 then L[3]:drawPixel(x, y, GOLD_DK) end
      -- ④ 最下一行描边
      if y == 43 then L[4]:drawPixel(x, y, OUTL) end
    end
  end
  save_layers("hdr-banner", W, H, {"底", "高光", "金边", "描边"}, L)
end

---------------- 按钮底板 + 图标 ----------------
local ARROW = {   -- 18 × 14, o = 描边, c = 奶白, s = 阴影(上下对称的粗箭头)
  ".......oo.........",
  "......occo........",
  ".....occco........",
  "....occcco........",
  "...occccoooooooo..",
  "..occccccccccccco.",
  ".occccccccccccccco",
  ".occccccccccccccco",
  "..occsssssssssssso",
  "...occsoooooooooo.",
  "....occso.........",
  ".....occo.........",
  "......oso.........",
  ".......oo.........",
}
local HOUSE = {   -- 18 × 14
  "........oo........",
  ".......occo.......",
  "......occcco......",
  ".....occcccco.....",
  "....occcccccco....",
  "...occcccccccco...",
  "..occcccccccccco..",
  ".ooooccccccccoooo.",
  "....occcooocco....",
  "....occco.occo....",
  "....occco.occo....",
  "....occco.occo....",
  "....osssooosso....",
  "....oooooooooo....",
}
local function button(name, icon)
  local W, H = 40, 34
  local L = new_layers(4, W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local e = math.min(x, y, W - 1 - x, H - 1 - y)
      local corner = (math.min(x, W - 1 - x) + math.min(y, H - 1 - y)) < 2   -- 切角
      if not corner then
        -- ① 底板: 海蓝, 上亮下暗
        if e >= 2 then L[1]:drawPixel(x, y, mix(NAVY_B, NAVY_T, y / H)) end
        if y == 2 and e >= 2 then L[1]:drawPixel(x, y, NAVY_HI) end   -- 顶上一行高光
        -- ② 金边: e==1, 左上亮金 右下暗金
        if e == 1 then
          local tl = (y == 1 and x < W - 2) or (x == 1 and y < H - 2)   -- 上边 / 左边亮, 下边 / 右边暗
          L[2]:drawPixel(x, y, tl and GOLD_HI or GOLD)
        end
        if e == 0 then L[4]:drawPixel(x, y, OUTL) end
      else
        local cx = math.min(x, W - 1 - x); local cy = math.min(y, H - 1 - y)
        if cx + cy == 1 then L[4]:drawPixel(x, y, OUTL) end
      end
    end
  end
  -- 底边一行暗金厚度(按钮的「立体」)
  for x = 2, W - 3 do L[2]:drawPixel(x, H - 3, GOLD_DK) end
  -- ③ 图标: 居中
  local ox = math.floor((W - #icon[1]) / 2); local oy = math.floor((H - 1 - #icon) / 2)
  for r = 1, #icon do
    for c = 1, #icon[r] do
      local ch = icon[r]:sub(c, c)
      local col = nil
      if ch == "o" then col = OUTL elseif ch == "c" then col = CREAM elseif ch == "s" then col = CREAM_SH end
      if col ~= nil then L[3]:drawPixel(ox + c - 1, oy + r - 1, col) end
    end
  end
  save_layers(name, W, H, {"底板", "金边", "图标", "描边"}, L)
end
button("hdr-back", ARROW)
button("hdr-home", HOUSE)

---------------- 页签(九宫格: 上沿切角 + 三面金边, 底边敞开) ----------------
local function tab(name, active)
  local W, H = 24, 24
  local L = new_layers(3, W, H)
  local fill_t = active and NAVY_HI or NAVY_DK
  local fill_b = active and NAVY_B or NAVY_T
  local rim = active and GOLD_HI or GOLD_DK
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local ex = math.min(x, W - 1 - x)
      local corner = (ex + y) < 3
      if not corner then
        if ex >= 2 and y >= 2 then L[1]:drawPixel(x, y, mix(fill_t, fill_b, y / H)) end
        if (ex == 1 and y >= 1) or (y == 1 and ex >= 1) then L[2]:drawPixel(x, y, rim) end
        if active and y == 2 and ex >= 2 then L[2]:drawPixel(x, y, mix(GOLD_HI, NAVY_HI, 0.55)) end
        if ex == 0 or y == 0 then L[3]:drawPixel(x, y, OUTL) end
        -- 没选中的: 最底两行是内容区那道金线(选中的底边敞开, 和内容连成一块)
        if not active and y >= H - 2 then L[2]:drawPixel(x, y, (y == H - 2) and GOLD or OUTL) end
      else
        if ex + y == 2 then L[3]:drawPixel(x, y, OUTL) end
        if ex + y == 3 then L[2]:drawPixel(x, y, rim) end
      end
    end
  end
  save_layers(name, W, H, {"底", "金边", "描边"}, L)
end
tab("hdr-tab-on", true)
tab("hdr-tab-off", false)
print("ok")
