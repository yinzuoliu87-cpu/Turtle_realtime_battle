-- ase_centurion_draw.lua —— 百夫长原画(后台驱动 Aseprite 自己的工具逐笔画, 11-27 用户「从零去一个一个去绘画这个百夫长」「所有按钮…都可以用后台调用」)
-- 画法: 剪影 → 平涂 → 暗部 → 亮部 → 细节 → 描边, 每层一个图层, 每一步存一张过程图; 源文件 .aseprite。
-- 设计: 128×128 画布、脚底第 121 行; 朝左四分之三侧身; 近身左手大盾挡在身前, 远侧右手竖握长矛; 横冠帝国高卢盔; 环片甲 + 胸前三枚勋章;
--       红短袍 + 皮垂带 + 露大腿 + 护胫 + 绑带凉鞋; 不画披风; 光从左上来。
-- 第二版(自评第一版: 脸被头盔盖成一团灰 / 冠饰像方帽 / 身体灰方块 / 右臂太细 / 大腿错画成红色 / 腿短脚怪)。
-- 用法: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase_centurion_draw.lua
local OUT = app.params["out"] or "."

local function C(hex)
  return Color{r=tonumber(hex:sub(2,3),16), g=tonumber(hex:sub(4,5),16), b=tonumber(hex:sub(6,7),16), a=255}
end
-- 调色板(暗 → 亮)
local OL = C("#1c1722")
local WH = C("#ffffff")
local S0, S1, S2, S3, S4 = C("#2f3542"), C("#4b5466"), C("#717c92"), C("#a3adc0"), C("#dfe5ee")
local R0, R1, R2, R3, R4 = C("#3e0d14"), C("#6e1820"), C("#a3242a"), C("#cf3d33"), C("#ee6e4e")
local G0, G1, G2, G3 = C("#5a3c10"), C("#9a6c22"), C("#d4a23e"), C("#f6d878")
local L0, L1, L2, L3 = C("#2e1c12"), C("#523420"), C("#7c5232"), C("#a87648")
local K0, K1, K2, K3 = C("#5a2e20"), C("#94523a"), C("#c97f55"), C("#eab084")
local W0, W1, W2 = C("#3a2414"), C("#69442a"), C("#8f6640")
local SIL = C("#2a2230")

local spr = Sprite(128, 128, ColorMode.RGB)
local function layer(name)
  local l = spr:newLayer(); l.name = name; spr:newCel(l, 1); app.activeLayer = l; return l
end
local function P(c, pts)   -- 实心多边形(轮廓工具)
  local t = {}
  for i, p in ipairs(pts) do t[i] = Point(p[1], p[2]) end
  app.useTool{tool="contour", color=c, points=t, brush=Brush(1)}
end
local function L(c, x1, y1, x2, y2)   -- 一笔直线(铅笔)
  app.useTool{tool="pencil", color=c, points={Point(x1, y1), Point(x2, y2)}, brush=Brush(1)}
end
local function D(c, x, y)   -- 点一个像素
  app.useTool{tool="pencil", color=c, points={Point(x, y)}, brush=Brush(1)}
end
local function snap(name) spr:saveCopyAs(OUT .. "/" .. name .. ".png") end

-- ── 各部件形状(剪影和平涂共用) ──
local SH = {
  back_thigh = {{68,90},{77,90},{80,103},{73,104}},
  back_knee  = {{73,102},{80,101},{81,105},{74,106}},
  back_shin  = {{74,105},{81,104},{82,116},{76,117}},
  back_foot  = {{71,116},{84,116},{86,121},{70,121}},
  torso      = {{52,54},{60,50},{80,49},{88,54},{89,64},{86,80},{56,82},{51,68}},
  r_pauld    = {{79,47},{90,49},{95,56},{94,62},{87,62},{82,56}},
  skirt      = {{54,80},{86,78},{89,92},{51,94}},
  neck       = {{60,46},{68,46},{69,53},{60,53}},
  helmet     = {{56,32},{61,28},{70,28},{75,32},{76,39},{72,42},{57,41},{55,37}},
  neckguard  = {{71,38},{80,40},{82,46},{72,46}},
  face       = {{52,38},{63,38},{64,50},{61,54},{55,54},{52,50},{50,45},{51,42}},
  cheek      = {{62,39},{66,39},{66,50},{63,51}},
  crest      = {{49,30},{50,25},{52,22},{54,23},{56,19},{58,20},{61,17},{63,18},{66,15},{68,17},{71,16},{73,18},{76,18},{78,21},{80,22},{82,26},{83,29},{80,31},{52,32}},
  r_upper    = {{86,57},{95,59},{96,70},{88,71}},
  r_fore     = {{88,68},{96,69},{96,77},{88,78}},
  spear_tip  = {{91,3},{94,9},{94,17},{91,21},{89,17},{89,9}},
  r_fist     = {{87,73},{96,73},{97,81},{88,82}},
  front_thigh= {{53,90},{63,90},{61,101},{52,102}},
  front_knee = {{50,100},{60,99},{60,104},{50,105}},
  front_shin = {{50,104},{59,103},{57,115},{50,116}},
  front_foot = {{40,115},{57,114},{58,121},{38,121}},
  shield     = {{30,57},{34,54},{55,55},{58,58},{58,106},{55,109},{34,110},{30,107}},
  l_pauld    = {{47,55},{57,52},{61,57},{50,60}},
}
local ORDER = {"back_thigh","back_knee","back_shin","back_foot","torso","r_pauld","skirt","neck","helmet","neckguard","face","cheek","crest",
  "r_upper","r_fore","spear_shaft","spear_tip","r_fist","front_thigh","front_knee","front_shin","front_foot","l_pauld","shield"}
local function shape(name, c)
  if name == "spear_shaft" then
    P(c, {{91,20},{92,20},{92,121},{91,121}})
  else
    P(c, SH[name])
  end
end

-- ① 剪影
layer("1剪影")
for _, n in ipairs(ORDER) do shape(n, SIL) end
snap("1_剪影")

-- ② 平涂(远侧的腿 / 手臂压一档暗, 交代前后)
local FLAT = {
  back_thigh=K1, back_knee=K1, back_shin=S1, back_foot=L1, torso=S2, r_pauld=S2, skirt=R2, neck=K2, helmet=S2, neckguard=S2,
  face=K2, cheek=S2, crest=R2, r_upper=K2, r_fore=K2, spear_shaft=W1, spear_tip=S3, r_fist=K2,
  front_thigh=K2, front_knee=K2, front_shin=S2, front_foot=L2, shield=R2, l_pauld=S2,
}
layer("2平涂")
for _, n in ipairs(ORDER) do shape(n, FLAT[n]) end
P(G1, {{54,79},{87,77},{87,82},{54,84}})                  -- 腰带
P(G1, {{30,57},{34,54},{55,55},{58,58},{58,60},{32,59}})   -- 盾上沿金边
P(G1, {{30,105},{58,104},{55,109},{34,110}})              -- 盾下沿金边
snap("2_平涂")

-- ③ 暗部(光从左上: 右侧 / 下侧 / 被遮挡处)
layer("3暗部")
P(S1, {{77,49},{80,49},{88,54},{89,64},{86,80},{77,81}})   -- 胸甲右侧
P(R1, {{52,89},{89,87},{89,92},{51,94}})                    -- 短袍下摆
P(R1, {{79,79},{86,78},{89,92},{79,92}})
P(S1, {{69,28},{75,32},{76,39},{72,42},{67,41}})            -- 盔右侧
P(S1, {{76,43},{82,44},{82,46},{74,46}})                    -- 护颈下沿
P(K1, {{55,51},{63,50},{61,54},{55,54}})                    -- 下巴阴影(胡茬)
P(K1, {{60,46},{63,46},{63,53},{60,53}})
P(R1, {{70,18},{79,21},{83,27},{80,30},{70,30}})            -- 冠饰右半
P(R1, {{51,56},{55,55},{55,108},{51,108}})                  -- 盾右侧弧面暗
P(R0, {{55,58},{58,60},{58,104},{55,106}})
P(S1, {{55,104},{59,103},{57,115},{54,115}})                -- 近腿护胫右侧
P(K1, {{58,90},{63,90},{61,101},{58,101}})                  -- 近腿大腿右侧
P(L1, {{50,118},{58,117},{58,121},{48,121}})                -- 鞋底
P(S0, {{90,52},{95,56},{94,62},{87,62}})                    -- 远侧肩甲右下
P(K1, {{92,59},{95,59},{96,70},{92,70}})                    -- 上臂右侧
P(K1, {{93,69},{96,69},{96,77},{93,77}})
L(W0, 92, 21, 92, 121)                                      -- 矛杆右侧一列
P(K0, {{73,102},{80,101},{81,105},{74,106}})                -- 远腿膝下
snap("3_暗部")

-- ④ 亮部(左上边缘)
layer("4亮部")
L(S3, 53, 54, 60, 51); L(S3, 60, 51, 79, 50)                -- 胸甲上沿
L(S3, 52, 57, 52, 66)
P(S3, {{59,29},{63,28},{65,30},{59,32}})                    -- 盔顶高光
D(S4, 60, 29); D(S4, 61, 29)
L(S3, 48, 55, 56, 52)                                       -- 近肩甲上沿
L(S4, 49, 54, 53, 53)
L(S3, 80, 48, 90, 50)                                       -- 远肩甲上沿
L(K3, 87, 58, 87, 69)                                       -- 上臂受光
L(K3, 89, 70, 89, 76)
L(R3, 32, 61, 32, 104); L(R3, 33, 61, 33, 104)              -- 盾左侧受光
L(R4, 32, 62, 32, 76)
L(G3, 33, 55, 54, 56)
L(S3, 51, 106, 51, 114); L(S4, 51, 107, 51, 110)            -- 近腿护胫亮边
L(K3, 54, 91, 54, 100); L(K3, 51, 101, 54, 100)             -- 近腿大腿 / 膝盖受光
L(K3, 51, 40, 51, 45); L(K3, 52, 39, 56, 39)                -- 额头 / 鼻梁受光
L(R3, 52, 23, 58, 19); L(R3, 58, 19, 66, 17)                -- 冠饰上沿
L(R4, 56, 20, 62, 18)
L(S4, 90, 8, 90, 16)                                        -- 矛尖左侧亮
L(W2, 91, 23, 91, 72)                                       -- 矛杆左侧亮
L(G3, 55, 79, 70, 78)                                       -- 腰带亮
for _, y in ipairs({57, 63, 69, 75}) do L(S3, 55, y, 76, y - 1) end   -- 每片环甲上沿亮
snap("4_亮部")

-- ⑤ 细节
layer("5细节")
for _, y in ipairs({60, 66, 72, 78}) do L(S1, 54, y, 86, y - 1) end   -- 环片甲每片下沿暗线
for _, y in ipairs({58, 64, 70}) do D(G2, 57, y + 1); D(G2, 83, y) end   -- 铆钉
for _, c in ipairs({{63,62},{69,61},{66,68}}) do             -- 三枚勋章
  P(G1, {{c[1]-2,c[2]-2},{c[1]+2,c[2]-2},{c[1]+2,c[2]+2},{c[1]-2,c[2]+2}})
  D(G3, c[1]-1, c[2]-1); D(G0, c[1]+1, c[2]+1)
end
for i = 0, 10 do                                             -- 冠饰放射鬃毛(根部收在盔顶, 梢往外散)
  local bx = 56 + i * 2
  local tx = 50 + i * 3
  L((i % 2 == 0) and R1 or R0, bx, 30, tx, 20 + math.floor(math.abs(i - 5) * 0.8))
end
for _, t in ipairs({{53,23},{59,19},{66,16},{73,18},{79,22}}) do D(R4, t[1], t[2]) end   -- 鬃毛梢受光
P(G1, {{52,37},{74,37},{74,39},{52,40}})                    -- 盔檐(金)
L(G3, 53, 37, 66, 37)
D(OL, 54, 42); D(OL, 55, 42); D(WH, 54, 42)                 -- 眼(白点 + 瞳)
L(K0, 53, 41, 57, 40)                                       -- 眉
L(K3, 50, 44, 50, 46); D(K1, 50, 47)                        -- 鼻尖侧影
L(K0, 52, 49, 56, 49)                                       -- 嘴
for x = 56, 84, 5 do                                         -- 皮垂带
  P(L2, {{x,82},{x+3,82},{x+3,92},{x,92}}); L(L3, x, 82, x, 91); L(L1, x+3, 83, x+3, 92); D(G2, x + 1, 91)
end
L(S3, 30, 58, 30, 106); L(S1, 58, 59, 58, 105)              -- 盾金属包边
P(G1, {{40,78},{47,78},{48,85},{40,86}}); D(G3, 41, 79); D(G3, 42, 79); D(G0, 46, 85)   -- 盾钉
L(G2, 39, 76, 33, 68); L(G2, 39, 77, 34, 71)                -- 左翼
L(G2, 48, 76, 54, 68); L(G2, 48, 77, 53, 71)                -- 右翼
L(G2, 43, 88, 40, 95); L(G2, 40, 95, 44, 95); L(G2, 44, 95, 41, 102)   -- 闪电
L(G2, 43, 74, 43, 63)
L(S3, 89, 10, 92, 6)                                        -- 矛尖脊
L(S1, 89, 21, 94, 21)                                       -- 矛箍
L(L1, 88, 71, 96, 71); L(L2, 88, 72, 96, 72)                -- 护腕
L(K1, 89, 78, 96, 78); D(K1, 92, 80)                        -- 指节
L(L0, 40, 118, 57, 117); L(L0, 44, 115, 47, 120); L(L0, 51, 115, 53, 120)   -- 凉鞋绑带
L(L0, 72, 118, 84, 118); L(L0, 76, 116, 78, 121)
L(S1, 50, 104, 59, 103); L(S1, 74, 105, 81, 104)            -- 护胫上沿
snap("5_细节")

-- ⑥ 描边: 合成后把外轮廓外一圈透明像素描成深色(选择性只描外边)
local flat = Image(spr.spec)
flat:drawSprite(spr, 1)
layer("6描边")
local ol = Image(spr.spec)
local function a(x, y)
  if x < 0 or y < 0 or x >= 128 or y >= 128 then return 0 end
  return app.pixelColor.rgbaA(flat:getPixel(x, y))
end
for y = 0, 127 do
  for x = 0, 127 do
    if a(x, y) == 0 and (a(x-1,y) > 0 or a(x+1,y) > 0 or a(x,y-1) > 0 or a(x,y+1) > 0) then
      ol:drawPixel(x, y, app.pixelColor.rgba(OL.red, OL.green, OL.blue, 255))
    end
  end
end
spr.layers[#spr.layers].cels[1].image = ol
for _, l in ipairs(spr.layers) do if l.name == "1剪影" then l.isVisible = false end end
snap("6_描边")
spr:saveAs(OUT .. "/centurion_base.aseprite")
print("done")
