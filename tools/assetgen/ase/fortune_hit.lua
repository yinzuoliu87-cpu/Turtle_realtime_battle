-- fortune_hit.lua —— 财神龟普攻·金剑命中爆点 6 帧(每帧 48×48, 横排 288×48)
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出横条。方案书 20261126d「特效重做」第 1 行(11-27 改)。
-- 由来: 11-27 第一版做成竖着劈的新月剑光, 用户:「这个普攻明明是一个偏横扫的…攻击, 为什么你要做竖着的这个命中特效呢？
--   横扫的话…就是做一个爆点的命中特效就好了呀」⇒ 只留命中点一个爆点。
-- 做法(如实): 每帧逐像素算: 中心闪光圆(白热芯 → 亮黄 → 金, 1 像素暗金描边) + 8 道金芒(角度固定、长短按固定哈希错开,
--   芒身两头收尖) + 第 2 帧起一圈细环外扩; 第 3 帧起芒从根部断开往外飞成短段, 第 5 帧只剩外圈几颗碎点。不用随机数, 重跑逐字节相同。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/fortune_hit.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local OUTL = rgba(120, 66, 10, 255)
local GOLD = rgba(240, 172, 40, 255)
local BRIGHT = rgba(255, 224, 100, 255)
local CORE = rgba(255, 252, 228, 255)
local N, S = 6, 48
local C = 23.5
-- 每帧: 闪光半径 / 芒内端 / 芒外端 / 芒半宽 / 环半径(0 = 无) / 环亮度(0~1)
local FR = {
  {4.0, 0.0, 9.0, 1.6, 0.0, 0.0},
  {6.5, 0.0, 15.0, 2.2, 0.0, 0.0},
  {5.0, 2.0, 20.0, 1.8, 11.0, 1.0},
  {2.5, 9.0, 22.0, 1.3, 15.0, 0.8},
  {0.0, 15.0, 23.0, 0.9, 19.0, 0.5},
  {0.0, 19.0, 23.0, 0.6, 0.0, 0.0},
}
local function hash(x)
  local h = math.sin(x * 12.9898) * 43758.5453
  return h - math.floor(h)
end
local spr = Sprite(S * N, S, ColorMode.RGB)
spr.filename = OUT .. "/fortune_hit.aseprite"
local img = Image(S * N, S, ColorMode.RGB)
for f = 1, N do
  local rc, r0, r1, hw, rr, ra = FR[f][1], FR[f][2], FR[f][3], FR[f][4], FR[f][5], FR[f][6]
  local ox = (f - 1) * S
  for y = 0, S - 1 do
    for x = 0, S - 1 do
      local dx, dy = x + 0.5 - C, y + 0.5 - C
      local r = math.sqrt(dx * dx + dy * dy)
      local a = math.atan(dy, dx)
      local col = nil
      -- 环
      if rr > 0 and math.abs(r - rr) < 0.75 then
        col = (ra > 0.7) and BRIGHT or GOLD
        if ra < 0.6 and hash(math.floor(a * 9.0) + f) < 0.45 then col = nil end   -- 后面几帧环断开
      end
      -- 芒(8 道, 每道长短错开)
      for k = 0, 7 do
        local ak = k * math.pi / 4.0 + 0.2
        local lk = (k % 2 == 0) and 1.0 or 0.72
        lk = lk * (0.85 + 0.3 * hash(k + 1))
        local e0, e1 = r0 * lk, r1 * lk
        local da = math.atan(math.sin(a - ak), math.cos(a - ak))
        local off = math.abs(math.sin(da)) * r                 -- 离芒中线的距离
        if math.cos(da) > 0 and r >= e0 and r <= e1 then
          local t = (r - e0) / math.max(0.5, e1 - e0)
          local w = hw * (1.0 - t) * math.min(1.0, (t + 0.15) * 4.0)   -- 两头收尖
          if off <= w then
            col = (off < w * 0.45 and t < 0.6) and CORE or ((t < 0.7) and BRIGHT or GOLD)
          end
        end
      end
      -- 中心闪光
      if rc > 0 and r <= rc + 0.5 then
        if r > rc - 0.5 then col = OUTL
        elseif r < rc * 0.55 then col = CORE
        elseif r < rc * 0.85 then col = BRIGHT
        else col = GOLD end
      end
      if col ~= nil then img:drawPixel(ox + x, y, col) end
    end
  end
end
spr:newCel(spr.layers[1], spr.frames[1], img, Point(0, 0))
spr:saveAs(OUT .. "/fortune_hit.aseprite")
img:saveAs(OUT .. "/fortune-hit.png")
print("ok")
